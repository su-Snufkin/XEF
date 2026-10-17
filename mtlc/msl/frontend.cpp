// Metal Shading Language frontend: MSL source -> AIR-shaped LLVM modules packed in a metallib.
//
//  1. clang preprocesses the source (metal_stdlib comes from an embedded header);
//  2. a small parser over the main-file tokens finds structs, entry points ([[stage]] functions) and function
//     constants; attributes are removed, float literals get an `f` suffix (MSL literals are float), threadgroup
//     locals become sections, entries are renamed __xef_user_* and get extern "C" wrappers that take every
//     input/output through pointers (ABI neutral);
//  3. clang compiles the result as C++20 for aarch64 (vectors/textures live in metal_stdlib);
//  4. the IR gets AIR entry functions + !air.* metadata built from the parsed attributes, so the AIR compiler
//     pipeline (prepare/lower/structurize/emit) handles it like Apple's bitcode.
#include "frontend.h"
#include "../air_meta.h"
#include "clang/Basic/DiagnosticOptions.h"
#include "clang/CodeGen/CodeGenAction.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/CompilerInvocation.h"
#include "clang/Frontend/FrontendActions.h"
#include "clang/Frontend/TextDiagnosticPrinter.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/VirtualFileSystem.h"
#include "llvm/Support/raw_ostream.h"
#include <cctype>
#include <cstring>
#include <map>
#include <set>

#include "metal_stdlib_data.inc"   // k_metal_stdlib[], k_metal_stdlib_size

namespace mtlc::msl {
using namespace llvm;

// ---------------------------------------------------------------- tokens

struct Tok {
    enum Kind { Ident, Number, String, Punct, End } kind;
    std::string text;
    size_t pos, end;   // byte range in the source
};

static std::vector<Tok> tokenize(const std::string& s) {
    std::vector<Tok> t;
    size_t i = 0, n = s.size();
    while (i < n) {
        char c = s[i];
        if (isspace((unsigned char)c)) { i++; continue; }
        if (c == '/' && i + 1 < n && s[i + 1] == '/') { while (i < n && s[i] != '\n') i++; continue; }
        if (c == '/' && i + 1 < n && s[i + 1] == '*') { i += 2; while (i + 1 < n && !(s[i] == '*' && s[i + 1] == '/')) i++; i += 2; continue; }
        if (c == '#') { while (i < n && s[i] != '\n') i++; continue; }   // line markers / pragmas
        size_t b = i;
        if (isalpha((unsigned char)c) || c == '_') {
            while (i < n && (isalnum((unsigned char)s[i]) || s[i] == '_')) i++;
            t.push_back({Tok::Ident, s.substr(b, i - b), b, i});
            continue;
        }
        if (isdigit((unsigned char)c) || (c == '.' && i + 1 < n && isdigit((unsigned char)s[i + 1]))) {
            bool hex = c == '0' && i + 1 < n && (s[i + 1] == 'x' || s[i + 1] == 'X');
            i += hex ? 2 : 0;
            while (i < n) {
                char d = s[i];
                if (isalnum((unsigned char)d) || d == '.' || d == '_') { i++; continue; }
                if ((d == '+' || d == '-') && !hex && (s[i - 1] == 'e' || s[i - 1] == 'E')) { i++; continue; }
                if ((d == '+' || d == '-') && hex && (s[i - 1] == 'p' || s[i - 1] == 'P')) { i++; continue; }
                break;
            }
            t.push_back({Tok::Number, s.substr(b, i - b), b, i});
            continue;
        }
        if (c == '"' || c == '\'') {
            i++;
            while (i < n && s[i] != c) { if (s[i] == '\\') i++; i++; }
            i++;
            t.push_back({Tok::String, s.substr(b, i - b), b, i});
            continue;
        }
        static const char* p3[] = {"<<=", ">>=", "...", "->*"};
        static const char* p2[] = {"[[", "]]", "::", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||",
                                   "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", ".*"};
        bool done = false;
        for (const char* p : p3) if (!s.compare(i, 3, p)) { t.push_back({Tok::Punct, p, i, i + 3}); i += 3; done = true; break; }
        if (done) continue;
        for (const char* p : p2) if (!s.compare(i, 2, p)) { t.push_back({Tok::Punct, p, i, i + 2}); i += 2; done = true; break; }
        if (done) continue;
        t.push_back({Tok::Punct, std::string(1, c), i, i + 1});
        i++;
    }
    t.push_back({Tok::End, "", n, n});
    return t;
}

// ---------------------------------------------------------------- parsed declarations

struct Attr {
    std::string name;
    std::vector<std::string> args;   // raw text of the arguments
};

struct Member {
    std::string type, name;
    std::string array;               // "[N]" suffix
    std::vector<Attr> attrs;
};

struct Param {
    std::string type, name;
    std::vector<Attr> attrs;
};

struct Entry {
    std::string stage;               // vertex / fragment / kernel
    std::string ret, name;
    std::vector<Param> params;
    std::vector<Attr> fn_attrs;      // after the parameter list or before the qualifier
};

struct FnConst {
    std::string type, name, index_expr;
};

static const Attr* find_attr(const std::vector<Attr>& as, const std::string& n) {
    for (const Attr& a : as) if (a.name == n) return &a;
    return nullptr;
}

class Parser {
public:
    const std::string& src;
    std::vector<Tok> t;
    size_t p = 0;
    std::map<std::string, std::vector<Member>> structs;
    std::vector<Entry> entries;
    std::vector<FnConst> fconsts;
    struct Edit { size_t b, e; std::string r; };
    std::vector<Edit> edits;
    std::string err;

    explicit Parser(const std::string& s) : src(s), t(tokenize(s)) {}

    const Tok& cur() const { return t[p]; }
    bool is(const char* s) const { return t[p].text == s && t[p].kind != Tok::String; }
    std::string text(size_t a, size_t b) const {   // token range [a, b) as source text
        if (a >= b) return "";
        return src.substr(t[a].pos, t[b - 1].end - t[a].pos);
    }
    size_t match(size_t i, const char* open, const char* close) const {   // index of the matching close token
        int depth = 0;
        for (size_t k = i; k < t.size(); k++) {
            if (t[k].text == open && t[k].kind == Tok::Punct) depth++;
            else if (t[k].text == close && t[k].kind == Tok::Punct) { if (--depth == 0) return k; }
            else if (t[k].kind == Tok::End) return k;
        }
        return t.size() - 1;
    }

    // parses `[[ a(x), b ]]` at position i, appends to out, schedules removal, returns index after `]]`
    size_t attrs(size_t i, std::vector<Attr>* out) {
        while (t[i].text == "[[" && t[i].kind == Tok::Punct) {
            size_t e = i + 1;
            int depth = 0;
            while (t[e].kind != Tok::End && !(depth == 0 && t[e].text == "]]")) {
                if (t[e].text == "(") depth++;
                if (t[e].text == ")") depth--;
                e++;
            }
            // split by top-level commas
            size_t k = i + 1;
            while (k < e) {
                Attr a;
                size_t s0 = k;
                if (t[k].kind == Tok::Ident) {
                    a.name = t[k].text;
                    k++;
                    while (k < e && t[k].text == "::") { a.name += "::" + t[k + 1].text; k += 2; }
                    if (k < e && t[k].text == "(") {
                        size_t m = match(k, "(", ")");
                        size_t q = k + 1, as = q;
                        int d = 0;
                        for (; q < m; q++) {
                            if (t[q].text == "(") d++;
                            if (t[q].text == ")") d--;
                            if (d == 0 && t[q].text == ",") { a.args.push_back(text(as, q)); as = q + 1; }
                        }
                        if (as < m) a.args.push_back(text(as, m));
                        k = m + 1;
                    }
                }
                if (out && !a.name.empty()) out->push_back(a);
                while (k < e && t[k].text != ",") k++;
                if (k < e) k++;
                if (k == s0) k++;
            }
            edits.push_back({t[i].pos, t[e].end, " "});
            i = e + 1;
        }
        return i;
    }

    // declarator split: tokens [a, b) = "type name [dims]" -> (type, name, array)
    void split_decl(size_t a, size_t b, std::string& type, std::string& name, std::string& array) {
        size_t nb = b;
        while (nb > a && t[nb - 1].text == "]") nb = [&] { int d = 0; for (size_t k = nb - 1; k > a; k--) { if (t[k].text == "]") d++; if (t[k].text == "[") { if (--d == 0) return k; } } return a; }();
        array = text(nb, b);
        if (nb > a && t[nb - 1].kind == Tok::Ident) {
            name = t[nb - 1].text;
            type = text(a, nb - 1);
        } else {
            name = "";
            type = text(a, nb);
        }
    }

    void parse_struct(size_t i) {
        // struct Name [: base] {
        std::string name = t[i + 1].text;
        size_t b = i + 2;
        while (t[b].text != "{" && t[b].text != ";" && t[b].kind != Tok::End) b++;
        if (t[b].text != "{") return;
        size_t e = match(b, "{", "}");
        std::vector<Member> ms;
        size_t k = b + 1;
        while (k < e) {
            // one member declaration up to ';' at depth 0 (skip functions / nested definitions)
            size_t s = k;
            int d = 0;
            bool fn = false;
            while (k < e) {
                if (t[k].text == "(" || t[k].text == "{" ) { if (d == 0 && t[k].text == "(") fn = true; }
                if (t[k].text == "{" ) { k = match(k, "{", "}") + 1; if (fn || d == 0) { if (t[k].text == ";") k++; goto next; } continue; }
                if (t[k].text == "(") d++;
                if (t[k].text == ")") d--;
                if (d == 0 && t[k].text == ";") break;
                k++;
            }
            if (!fn) {
                std::vector<Attr> as;
                // collect attributes inside the declaration, remember token boundaries without them
                std::vector<size_t> keep;
                for (size_t q = s; q < k;) {
                    if (t[q].text == "[[") { q = attrs(q, &as); continue; }
                    keep.push_back(q);
                    q++;
                }
                // declarators separated by top-level commas
                std::vector<std::vector<size_t>> decls(1);
                int dd = 0;
                for (size_t q : keep) {
                    if (t[q].text == "(" || t[q].text == "<" || t[q].text == "[") dd++;
                    if (t[q].text == ")" || t[q].text == ">" || t[q].text == "]") dd--;
                    if (dd == 0 && t[q].text == ",") { decls.emplace_back(); continue; }
                    if (t[q].text == "=") dd += 1000;   // initializer: ignore the rest
                    decls.back().push_back(q);
                }
                std::string base_type;
                for (size_t di = 0; di < decls.size(); di++) {
                    auto& dv = decls[di];
                    if (dv.empty()) continue;
                    if (dv.back() >= t.size()) continue;
                    // rebuild a contiguous view
                    std::string type, name, arr;
                    if (di == 0) {
                        split_decl(dv.front(), dv.back() + 1, type, name, arr);
                        // strip attribute holes: type text may contain removed attributes; that is fine (edits blank them)
                        base_type = type;
                    } else {
                        name = t[dv.back()].text;
                        type = base_type;
                    }
                    if (name.empty() || type.empty()) continue;
                    if (type.find("static") != std::string::npos || type.find("typedef") != std::string::npos ||
                        type.find("using") != std::string::npos) continue;
                    Member m;
                    m.type = strip_attrs(type);
                    m.name = name;
                    m.array = arr;
                    m.attrs = as;
                    ms.push_back(m);
                }
            } else {
                // still remove attributes inside member functions
                for (size_t q = s; q < k; q++) if (t[q].text == "[[") q = attrs(q, nullptr) - 1;
            }
            k++;
        next:;
        }
        structs[name] = ms;
    }

    std::string strip_attrs(const std::string& s) {
        std::string r;
        size_t i = 0;
        while (i < s.size()) {
            if (!s.compare(i, 2, "[[")) {
                size_t e = s.find("]]", i);
                if (e == std::string::npos) break;
                i = e + 2;
                continue;
            }
            r += s[i++];
        }
        // trim
        size_t a = r.find_first_not_of(" \t\n"), b = r.find_last_not_of(" \t\n");
        return a == std::string::npos ? "" : r.substr(a, b - a + 1);
    }

    void parse_entry(size_t qual, std::vector<Attr> pre) {
        Entry e;
        e.stage = t[qual].text;
        e.fn_attrs = pre;
        edits.push_back({t[qual].pos, t[qual].end, " "});
        size_t i = qual + 1;
        // return type up to the identifier followed by '('
        size_t rs = i;
        while (t[i].kind != Tok::End && !(t[i].kind == Tok::Ident && t[i + 1].text == "(")) {
            if (t[i].text == "[[") { i = attrs(i, &e.fn_attrs); continue; }
            i++;
        }
        e.ret = strip_attrs(text(rs, i));
        e.name = t[i].text;
        edits.push_back({t[i].pos, t[i].end, "__xef_user_" + e.name});
        size_t lp = i + 1, rp = match(lp, "(", ")");
        size_t k = lp + 1;
        while (k < rp) {
            size_t s = k;
            int d = 0;
            std::vector<Attr> as;
            std::vector<size_t> keep;
            while (k < rp) {
                if (t[k].text == "[[") { k = attrs(k, &as); continue; }
                if (t[k].text == "(" || t[k].text == "<") d++;
                if (t[k].text == ")" || t[k].text == ">") d--;
                if (d == 0 && t[k].text == ",") break;
                keep.push_back(k);
                k++;
            }
            if (!keep.empty()) {
                Param pr;
                std::string arr;
                // drop default argument
                size_t last = keep.size();
                for (size_t q = 0; q < keep.size(); q++) if (t[keep[q]].text == "=") { last = q; break; }
                if (last > 0) {
                    split_decl(keep[0], keep[last - 1] + 1, pr.type, pr.name, arr);
                    pr.type = strip_attrs(pr.type);
                    pr.attrs = as;
                    if (pr.type != "void" || !pr.name.empty()) e.params.push_back(pr);
                }
            }
            (void)s;
            if (k < rp) k++;
        }
        // attributes after the parameter list
        size_t a = rp + 1;
        a = attrs(a, &e.fn_attrs);
        entries.push_back(e);
        p = a;
    }

    void parse_fconst(size_t i, size_t semi) {
        // constant T name [[function_constant(x)]];
        std::vector<Attr> as;
        std::vector<size_t> keep;
        for (size_t q = i; q < semi;) {
            if (t[q].text == "[[") { q = attrs(q, &as); continue; }
            keep.push_back(q);
            q++;
        }
        const Attr* fc = find_attr(as, "function_constant");
        if (!fc || keep.size() < 3) return;
        FnConst f;
        f.name = t[keep.back()].text;
        f.type = text(keep[1], keep.back());
        f.index_expr = fc->args.empty() ? "0" : fc->args[0];
        fconsts.push_back(f);
        // replace the declaration by an extern "C" global the compiler cannot fold
        edits.push_back({t[i].pos, t[semi].end, "extern \"C\" const " + f.type + " " + f.name + ";"});
    }

    // threadgroup declarations inside function bodies become section-tagged statics
    void scan_body(size_t b, size_t e) {
        for (size_t k = b + 1; k < e; k++) {
            if (t[k].text == "[[") { k = attrs(k, nullptr) - 1; continue; }
            if (t[k].kind == Tok::Ident && t[k].text == "threadgroup") {
                const std::string& prev = t[k - 1].text;
                if (prev == ";" || prev == "{" || prev == "}" || prev == ")" ) {
                    // `threadgroup T name[N];` (not a cast `(threadgroup T*)`)
                    size_t q = k + 1;
                    bool decl = false;
                    while (q < e && t[q].text != ";" && t[q].text != "(" && t[q].text != ")") { if (t[q].text == "=" ) break; q++; }
                    if (q < e && t[q].text == ";") decl = true;
                    if (decl && prev != ")")
                        edits.push_back({t[k].pos, t[k].end, "static __attribute__((section(\"xef.tg\")))"});
                }
            }
        }
    }

    bool run() {
        int brace = 0;
        std::vector<Attr> pending;
        while (t[p].kind != Tok::End) {
            const Tok& k = t[p];
            if (k.text == "[[") {
                std::vector<Attr> as;
                size_t n = attrs(p, &as);
                if (brace == 0) pending.insert(pending.end(), as.begin(), as.end());
                p = n;
                continue;
            }
            if (k.kind == Tok::Ident && (k.text == "vertex" || k.text == "fragment" || k.text == "kernel") && brace_ok(brace)) {
                std::vector<Attr> pre = pending;
                pending.clear();
                parse_entry(p, pre);
                continue;
            }
            if (k.kind == Tok::Ident && k.text == "struct" && t[p + 1].kind == Tok::Ident) {
                parse_struct(p);
            }
            if (k.kind == Tok::Ident && k.text == "constant" && brace_ok(brace)) {
                size_t semi = p;
                int d = 0;
                while (t[semi].kind != Tok::End) {
                    if (t[semi].text == "{" || t[semi].text == "(") d++;
                    if (t[semi].text == "}" || t[semi].text == ")") d--;
                    if (d == 0 && t[semi].text == ";") break;
                    if (d < 0) break;
                    semi++;
                }
                bool is_fc = false;
                for (size_t q = p; q < semi; q++) if (t[q].text == "function_constant") is_fc = true;
                if (is_fc) { parse_fconst(p, semi); p = semi + 1; continue; }
            }
            if (k.text == "{") {
                // function bodies: scan for threadgroup locals
                size_t e = match(p, "{", "}");
                if (t[p - 1].text == ")" || t[p - 1].text == "const") { scan_body(p, e); p = e + 1; continue; }
                brace++;
            }
            if (k.text == "}") brace--;
            if (k.text == ";" ) pending.clear();
            p++;
        }
        return err.empty();
    }
    // entries may live in namespaces: braces of namespaces/structs are counted, function bodies are skipped
    bool brace_ok(int) const { return true; }

    // float literals: unsuffixed -> `f`, `h` suffix -> half cast
    void literals() {
        for (const Tok& k : t) {
            if (k.kind != Tok::Number) continue;
            const std::string& s = k.text;
            bool hex = s.size() > 1 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X');
            bool fp = !hex && (s.find('.') != std::string::npos || s.find('e') != std::string::npos || s.find('E') != std::string::npos);
            if (hex && (s.find('p') != std::string::npos || s.find('P') != std::string::npos)) fp = true;
            char last = s.back();
            if (!fp) {
                // integer literal with h suffix is not valid; nothing to do
                continue;
            }
            if (last == 'h' || last == 'H') edits.push_back({k.pos, k.end, "((half)" + s.substr(0, s.size() - 1) + "f)"});
            else if (last == 'f' || last == 'F') continue;
            else if (isdigit((unsigned char)last) || last == '.') edits.push_back({k.end, k.end, "f"});
        }
    }

    std::string apply() {
        std::sort(edits.begin(), edits.end(), [](const Edit& a, const Edit& b) { return a.b < b.b || (a.b == b.b && a.e < b.e); });
        std::string out;
        size_t at = 0;
        for (const Edit& e : edits) {
            if (e.b < at) continue;   // overlapping (attribute inside an already replaced range)
            out += src.substr(at, e.b - at);
            out += e.r;
            at = e.e;
        }
        out += src.substr(at);
        return out;
    }
};

// ---------------------------------------------------------------- MSL type names -> LLVM types

static Type* scalar_type(LLVMContext& c, const std::string& n, bool& is_signed) {
    is_signed = false;
    if (n == "float") return Type::getFloatTy(c);
    if (n == "half") return Type::getHalfTy(c);
    if (n == "int") { is_signed = true; return Type::getInt32Ty(c); }
    if (n == "uint" || n == "unsigned int" || n == "unsigned") return Type::getInt32Ty(c);
    if (n == "short") { is_signed = true; return Type::getInt16Ty(c); }
    if (n == "ushort" || n == "unsigned short") return Type::getInt16Ty(c);
    if (n == "char") { is_signed = true; return Type::getInt8Ty(c); }
    if (n == "uchar" || n == "unsigned char") return Type::getInt8Ty(c);
    if (n == "bool") return Type::getInt1Ty(c);
    if (n == "long") { is_signed = true; return Type::getInt64Ty(c); }
    if (n == "ulong") return Type::getInt64Ty(c);
    return nullptr;
}

static std::string clean_type(std::string s) {
    for (const char* q : {"const ", "volatile ", "metal::", "thread ", "device ", "constant "}) {
        size_t i;
        while ((i = s.find(q)) != std::string::npos) s.erase(i, strlen(q));
    }
    size_t a = s.find_first_not_of(" \t\n"), b = s.find_last_not_of(" \t\n");
    return a == std::string::npos ? "" : s.substr(a, b - a + 1);
}

// float4 / vec<float, 4> / packed types are not valid in interfaces
static Type* msl_type(LLVMContext& c, const std::string& raw, std::string* elem_name = nullptr) {
    std::string s = clean_type(raw);
    bool sg;
    if (Type* t = scalar_type(c, s, sg)) { if (elem_name) *elem_name = s; return t; }
    // vec<T, N>
    if (s.rfind("vec<", 0) == 0) {
        size_t comma = s.find(','), gt = s.rfind('>');
        if (comma != std::string::npos && gt != std::string::npos) {
            std::string e = clean_type(s.substr(4, comma - 4));
            int n = atoi(s.substr(comma + 1, gt - comma - 1).c_str());
            Type* et = scalar_type(c, e, sg);
            if (et && n >= 2 && n <= 4) { if (elem_name) *elem_name = e; return FixedVectorType::get(et, n); }
        }
    }
    // floatN etc.
    size_t i = s.size();
    while (i > 0 && isdigit((unsigned char)s[i - 1])) i--;
    if (i < s.size() && i > 0) {
        std::string base = s.substr(0, i);
        int n = atoi(s.c_str() + i);
        Type* et = scalar_type(c, base, sg);
        if (et && n >= 2 && n <= 4) { if (elem_name) *elem_name = base; return FixedVectorType::get(et, n); }
    }
    return nullptr;
}

// ---------------------------------------------------------------- AIR metadata helpers

struct Slot {
    enum Kind { Pointer, Value } kind;
    Type* type;                       // value type (Value) / pointer address space via `as`
    unsigned as = 0;
    std::vector<Metadata*> md;        // AIR element metadata operands (without the leading index)
    std::string arg_expr;             // C++ expression for the wrapper (uses __iN)
};

static MDString* S(LLVMContext& c, const std::string& s) { return MDString::get(c, s); }
static Metadata* I(LLVMContext& c, int64_t v) { return ConstantAsMetadata::get(ConstantInt::get(Type::getInt32Ty(c), v)); }

// ---------------------------------------------------------------- clang driver

struct ClangOut {
    std::string text;
    std::unique_ptr<Module> mod;
};

static bool run_clang(const std::string& source, bool preprocess, LLVMContext* ctx, ClangOut& out, std::string& diag) {
    auto ci = std::make_unique<clang::CompilerInstance>();
    std::string dtext;
    raw_string_ostream dos(dtext);
    clang::DiagnosticOptions dopts;
    auto printer = new clang::TextDiagnosticPrinter(dos, dopts);
    auto vfs = llvm::vfs::getRealFileSystem();
    ci->createDiagnostics(*vfs, printer, true);
    std::string outpath;
    std::vector<std::string> args = {
        "-triple", "aarch64-unknown-linux-gnu", "-target-feature", "+neon", "-target-feature", "+fullfp16",
        "-x", "c++", "-std=c++20", "-fms-extensions", "-fdeclspec", "-fno-exceptions", "-fno-rtti", "-O2",
        "-Wno-everything", "-ffp-contract=on", "-fgnuc-version=4.2.1", "-I", "/xef-mtlc/include", "-nostdsysteminc",
        "-nobuiltininc", "-disable-llvm-verifier", "-discard-value-names", "-fno-math-errno",
        "-main-file-name", "shader.metal", "-o", "-",
    };
    if (preprocess) args.push_back("-E");
    else args.push_back("-emit-llvm-only");
    args.push_back("/xef-mtlc/shader.metal");
    std::vector<const char*> argv;
    for (auto& a : args) argv.push_back(a.c_str());
    if (!clang::CompilerInvocation::CreateFromArgs(ci->getInvocation(), argv, ci->getDiagnostics())) {
        diag = "clang invocation failed: " + dtext;
        return false;
    }
    // in-memory files: the source and the embedded headers
    auto& ppo = ci->getInvocation().getPreprocessorOpts();
    ppo.addRemappedFile("/xef-mtlc/shader.metal", MemoryBuffer::getMemBufferCopy(source, "/xef-mtlc/shader.metal").release());
    static const char* headers[] = {"metal_stdlib", "metal_math", "metal_texture", "metal_atomic", "metal_compute",
                                    "metal_graphics", "metal_geometric", "metal_relational", "metal_common", "metal_integer",
                                    "metal_pack", "metal_simdgroup", "metal_matrix", "metal_types", "metal_numeric",
                                    "metal_array", "metal_quadgroup", "simd/simd.h", "metal_stdlib_internal"};
    for (const char* h : headers) {
        std::string path = std::string("/xef-mtlc/include/") + h;
        if (!strcmp(h, "metal_stdlib"))
            ppo.addRemappedFile(path, MemoryBuffer::getMemBuffer(StringRef(k_metal_stdlib, k_metal_stdlib_size), path, false).release());
        else
            ppo.addRemappedFile(path, MemoryBuffer::getMemBufferCopy("#pragma once\n#include <metal_stdlib>\n", path).release());
    }
    ppo.RetainRemappedFileBuffers = false;
    if (preprocess) {
        // -E writes to the output stream: capture it
        std::string text;
        auto os = std::make_unique<raw_string_ostream>(text);
        ci->setOutputStream(std::move(os));
        clang::PrintPreprocessedAction act;
        bool ok = ci->ExecuteAction(act);
        ci->clearOutputFiles(false);
        out.text = text;
        if (!ok || ci->getDiagnostics().hasErrorOccurred()) { diag = dtext; return false; }
        return true;
    }
    clang::EmitLLVMOnlyAction act(ctx);
    bool ok = ci->ExecuteAction(act);
    if (!ok || ci->getDiagnostics().hasErrorOccurred()) { diag = dtext; return false; }
    out.mod = act.takeModule();
    return out.mod != nullptr;
}

// main-file portions of preprocessed output (drops the expanded metal_stdlib)
static std::string main_file_text(const std::string& pp) {
    std::string out;
    bool in_main = true;
    size_t i = 0;
    while (i < pp.size()) {
        size_t e = pp.find('\n', i);
        if (e == std::string::npos) e = pp.size();
        std::string line = pp.substr(i, e - i);
        if (line.size() > 2 && line[0] == '#' && line[1] == ' ' && isdigit((unsigned char)line[2])) {
            in_main = line.find("\"/xef-mtlc/shader.metal\"") != std::string::npos;
        } else if (in_main) {
            out += line;
            out += '\n';
        }
        i = e + 1;
    }
    return out;
}

// ---------------------------------------------------------------- the frontend

static void err_line(std::string& err, const std::string& m) { err += m; err += '\n'; }

static std::string air_builtin(const std::string& n) {
    static const std::set<std::string> known = {
        "position", "vertex_id", "instance_id", "base_vertex", "base_instance", "front_facing", "point_coord", "sample_id",
        "sample_mask", "render_target_array_index", "viewport_array_index", "primitive_id", "barycentric_coord",
        "thread_position_in_grid", "thread_position_in_threadgroup", "threadgroup_position_in_grid", "threadgroups_per_grid",
        "threads_per_threadgroup", "threads_per_grid", "thread_index_in_threadgroup", "thread_index_in_simdgroup",
        "simdgroup_index_in_threadgroup", "threads_per_simdgroup", "simdgroups_per_threadgroup", "thread_index_in_quadgroup",
        "quadgroup_index_in_threadgroup", "dispatch_threads_per_threadgroup", "dispatch_simdgroups_per_threadgroup",
        "grid_origin", "grid_size", "amplification_id", "amplification_count"};
    return known.count(n) ? "air." + n : "";
}

struct EntryPlan {
    Entry* e;
    std::vector<Slot> inputs;         // AIR arguments in order
    std::vector<std::pair<Type*, std::vector<Metadata*>>> outputs;   // AIR return members
    std::string wrapper;              // C++ text
};

bool compile_msl(const std::string& source, std::vector<uint8_t>& metallib, std::string& err) {
    // 1. preprocess
    ClangOut pp;
    std::string diag;
    if (!run_clang(source, true, nullptr, pp, diag)) { err = "MSL preprocessing failed:\n" + diag; return false; }
    std::string user = main_file_text(pp.text);
    // 2. parse + rewrite
    Parser ps(user);
    ps.run();
    ps.literals();
    if (!ps.err.empty()) { err = ps.err; return false; }
    std::string body = ps.apply();

    LLVMContext ctx;
    std::vector<EntryPlan> plans;
    std::string wrappers;
    int attr_n = 0;
    std::string attr_globals;   // extern "C" const int __xef_attr_N = (expr); for attribute arguments
    auto attr_value = [&](const std::string& expr) {
        std::string name = "__xef_attr_" + std::to_string(attr_n++);
        attr_globals += "extern \"C\" const int " + name + " = (int)(" + expr + ");\n";
        return name;
    };
    std::map<std::string, std::string> attr_names;   // global name -> placeholder resolved after compile
    for (Entry& e : ps.entries) {
        EntryPlan pl;
        pl.e = &e;
        std::string sig, pre, call_args;
        int slot = 0;
        auto add_ptr = [&](unsigned as, std::vector<Metadata*> md, const std::string& expr_of_ptr) {
            Slot s{Slot::Pointer, nullptr, as, std::move(md), ""};
            std::string pn = "__i" + std::to_string(slot++);
            sig += (sig.empty() ? "" : ", ") + std::string("void* ") + pn;
            s.arg_expr = expr_of_ptr;
            size_t at;
            while ((at = s.arg_expr.find("$")) != std::string::npos) s.arg_expr.replace(at, 1, pn);
            pl.inputs.push_back(s);
            return pl.inputs.back().arg_expr;
        };
        auto add_val = [&](Type* t, std::vector<Metadata*> md, const std::string& ctype) {
            Slot s{Slot::Value, t, 0, std::move(md), ""};
            std::string pn = "__i" + std::to_string(slot++);
            sig += (sig.empty() ? "" : ", ") + std::string("const void* ") + pn;
            s.arg_expr = "(*(const " + ctype + "*)" + pn + ")";
            pl.inputs.push_back(s);
            return pl.inputs.back().arg_expr;
        };
        for (Param& p : e.params) {
            std::string ty = clean_type(p.type);
            std::string arg;
            const Attr* a;
            bool is_ptr = p.type.find('*') != std::string::npos;
            bool is_ref = p.type.find('&') != std::string::npos;
            std::string base = ty;
            while (!base.empty() && (base.back() == '*' || base.back() == '&' || base.back() == ' ')) base.pop_back();
            std::vector<Metadata*> fc_md;
            if ((a = find_attr(p.attrs, "function_constant"))) {
                // optional argument: present only when the constant is true
                fc_md = {S(ctx, "air.function_constant"), S(ctx, "@fc:" + (a->args.empty() ? "" : a->args[0]))};
            }
            auto with_fc = [&](std::vector<Metadata*> md) { md.insert(md.begin(), fc_md.begin(), fc_md.end()); return md; };
            if ((a = find_attr(p.attrs, "buffer"))) {
                std::string loc = a->args.empty() ? "0" : attr_value(a->args[0]);
                bool cst = p.type.find("constant") != std::string::npos;
                unsigned as = cst ? 2 : 1;
                std::vector<Metadata*> md = with_fc({S(ctx, "air.buffer"), S(ctx, "air.location_index"), S(ctx, "@attr:" + loc), I(ctx, 1),
                                                     S(ctx, cst ? "air.read" : "air.read_write"), S(ctx, "air.address_space"), I(ctx, as),
                                                     S(ctx, "air.arg_name"), S(ctx, p.name)});
                if (is_ref) arg = add_ptr(as, md, "(*(" + base + "*)$)");
                else arg = add_ptr(as, md, "((" + ty + ")$)");
            } else if ((a = find_attr(p.attrs, "texture"))) {
                std::string loc = a->args.empty() ? "0" : attr_value(a->args[0]);
                std::string acc = ty.find("access::read_write") != std::string::npos ? "air.read_write"
                                : ty.find("access::write") != std::string::npos ? "air.write"
                                : ty.find("access::read") != std::string::npos ? "air.read" : "air.sample";
                std::vector<Metadata*> md = with_fc({S(ctx, "air.texture"), S(ctx, "air.location_index"), S(ctx, "@attr:" + loc), I(ctx, 1),
                                                     S(ctx, acc), S(ctx, "air.arg_name"), S(ctx, p.name)});
                arg = add_ptr(1, md, base + "((metal::__xef_tex_h)$)");
            } else if ((a = find_attr(p.attrs, "sampler"))) {
                std::string loc = a->args.empty() ? "0" : attr_value(a->args[0]);
                std::vector<Metadata*> md = with_fc({S(ctx, "air.sampler"), S(ctx, "air.location_index"), S(ctx, "@attr:" + loc), I(ctx, 1),
                                                     S(ctx, "air.arg_name"), S(ctx, p.name)});
                arg = add_ptr(2, md, "metal::sampler((metal::__xef_smp_h)$)");
            } else if ((a = find_attr(p.attrs, "threadgroup"))) {
                std::string loc = a->args.empty() ? "0" : attr_value(a->args[0]);
                std::vector<Metadata*> md = {S(ctx, "air.threadgroup"), S(ctx, "air.location_index"), S(ctx, "@attr:" + loc), I(ctx, 1),
                                             S(ctx, "air.arg_name"), S(ctx, p.name)};
                if (is_ref) arg = add_ptr(3, md, "(*(" + base + "*)$)");
                else arg = add_ptr(3, md, "((" + ty + ")$)");
            } else if ((a = find_attr(p.attrs, "stage_in"))) {
                std::string sname = clean_type(base);
                auto it = ps.structs.find(sname);
                if (it == ps.structs.end()) { err_line(err, "stage_in struct " + sname + " not found"); return false; }
                std::string var = "__s" + std::to_string(slot);
                pre += "  " + sname + " " + var + "{};\n";
                for (Member& m : it->second) {
                    std::string elem;
                    Type* mt = msl_type(ctx, m.type, &elem);
                    if (!mt) { err_line(err, "unsupported stage_in member type " + m.type); return false; }
                    std::vector<Metadata*> md;
                    if (e.stage == "vertex") {
                        const Attr* at = find_attr(m.attrs, "attribute");
                        std::string loc = at && !at->args.empty() ? attr_value(at->args[0]) : "";
                        md = {S(ctx, "air.vertex_input"), S(ctx, "air.location_index"), S(ctx, loc.empty() ? "@int:0" : "@attr:" + loc), I(ctx, 1),
                              S(ctx, "air.arg_type_name"), S(ctx, clean_type(m.type)), S(ctx, "air.arg_name"), S(ctx, m.name)};
                    } else {
                        // fragment input: [[user(x)]] / builtins / interpolation qualifiers
                        std::string uname = "generated(" + m.name + ")";
                        std::string builtin;
                        std::vector<Metadata*> interp;
                        for (const Attr& at : m.attrs) {
                            if (at.name == "user" && !at.args.empty()) uname = "user(" + at.args[0] + ")";
                            else if (at.name == "flat") interp.push_back(S(ctx, "air.flat"));
                            else if (at.name == "center_no_perspective" || at.name == "centroid_no_perspective" || at.name == "sample_no_perspective")
                                interp.push_back(S(ctx, "air.no_perspective"));
                            else if (!air_builtin(at.name).empty()) builtin = air_builtin(at.name);
                            if (at.name.find("centroid") != std::string::npos) interp.push_back(S(ctx, "air.centroid"));
                            if (at.name.rfind("sample_", 0) == 0 && at.name != "sample_id" && at.name != "sample_mask") interp.push_back(S(ctx, "air.sample"));
                        }
                        if (!builtin.empty()) md = {S(ctx, builtin)};
                        else {
                            md = {S(ctx, "air.fragment_input"), S(ctx, uname)};
                            md.insert(md.end(), interp.begin(), interp.end());
                            md.push_back(S(ctx, "air.arg_type_name"));
                            md.push_back(S(ctx, clean_type(m.type)));
                        }
                    }
                    std::string ex = add_val(mt, md, clean_type(m.type));
                    pre += "  " + var + "." + m.name + " = " + ex + ";\n";
                }
                arg = var;
            } else {
                // builtin value
                std::string builtin;
                std::vector<Metadata*> extra;
                for (const Attr& at : p.attrs) {
                    std::string b = air_builtin(at.name);
                    if (!b.empty()) builtin = b;
                    if (at.name == "color") builtin = "air.render_target";
                }
                if (builtin.empty()) { err_line(err, "parameter " + p.name + " of " + e.name + " has no supported attribute"); return false; }
                Type* vt = msl_type(ctx, base);
                if (!vt) { err_line(err, "unsupported builtin parameter type " + p.type); return false; }
                arg = add_val(vt, {S(ctx, builtin), S(ctx, "air.arg_type_name"), S(ctx, clean_type(base)), S(ctx, "air.arg_name"), S(ctx, p.name)}, clean_type(base));
            }
            call_args += (call_args.empty() ? "" : ", ") + arg;
        }
        // outputs
        std::string ret = clean_type(e.ret);
        std::string post;
        int oslot = 0;
        auto add_out = [&](Type* t, std::vector<Metadata*> md, const std::string& ctype, const std::string& val) {
            std::string on = "__o" + std::to_string(oslot++);
            sig += (sig.empty() ? "" : ", ") + std::string("void* ") + on;
            post += "  *(" + ctype + "*)" + on + " = " + val + ";\n";
            pl.outputs.push_back({t, std::move(md)});
        };
        if (ret != "void") {
            auto sit = ps.structs.find(ret);
            if (sit != ps.structs.end()) {
                for (Member& m : sit->second) {
                    std::string elem;
                    Type* mt = msl_type(ctx, m.type, &elem);
                    std::string ctype = clean_type(m.type);
                    if (!m.array.empty()) {
                        int n = atoi(m.array.c_str() + 1);
                        if (mt && n > 0) mt = ArrayType::get(mt, n);
                        ctype = "metal::array<" + ctype + ", " + std::to_string(n) + ">";
                    }
                    if (!mt) { err_line(err, "unsupported output member type " + m.type); return false; }
                    std::vector<Metadata*> md;
                    std::string val = "__r." + m.name;
                    if (!m.array.empty()) val = "*(" + ctype + "*)&__r." + m.name;
                    const Attr* at;
                    if (e.stage == "vertex") {
                        if (find_attr(m.attrs, "position")) md = {S(ctx, "air.position")};
                        else if (find_attr(m.attrs, "point_size")) md = {S(ctx, "air.point_size")};
                        else if (find_attr(m.attrs, "clip_distance")) md = {S(ctx, "air.clip_distance")};
                        else if (find_attr(m.attrs, "render_target_array_index")) md = {S(ctx, "air.render_target_array_index")};
                        else if (find_attr(m.attrs, "viewport_array_index")) md = {S(ctx, "air.viewport_array_index")};
                        else if (find_attr(m.attrs, "invariant") && find_attr(m.attrs, "position")) md = {S(ctx, "air.position")};
                        else {
                            std::string uname = "generated(" + m.name + ")";
                            if ((at = find_attr(m.attrs, "user")) && !at->args.empty()) uname = "user(" + at->args[0] + ")";
                            md = {S(ctx, "air.vertex_output"), S(ctx, uname)};
                            if (find_attr(m.attrs, "flat")) md.push_back(S(ctx, "air.flat"));
                            md.push_back(S(ctx, "air.arg_type_name"));
                            md.push_back(S(ctx, clean_type(m.type)));
                        }
                    } else if (e.stage == "fragment") {
                        if ((at = find_attr(m.attrs, "color"))) {
                            std::string loc = at->args.empty() ? "0" : attr_value(at->args[0]);
                            const Attr* ix = find_attr(m.attrs, "index");
                            std::string idx = ix && !ix->args.empty() ? attr_value(ix->args[0]) : "";
                            md = {S(ctx, "air.render_target"), S(ctx, "@attr:" + loc), S(ctx, idx.empty() ? "@int:0" : "@attr:" + idx),
                                  S(ctx, "air.arg_type_name"), S(ctx, clean_type(m.type))};
                        } else if ((at = find_attr(m.attrs, "depth"))) {
                            md = {S(ctx, "air.depth"), S(ctx, "air.depth_qualifier"), S(ctx, at->args.empty() ? "any" : at->args[0])};
                        } else if (find_attr(m.attrs, "sample_mask")) md = {S(ctx, "air.sample_mask")};
                        else if (find_attr(m.attrs, "stencil")) md = {S(ctx, "air.stencil")};
                        else { err_line(err, "fragment output " + m.name + " has no attribute"); return false; }
                    }
                    add_out(mt, md, ctype, val);
                }
            } else {
                Type* mt = msl_type(ctx, ret);
                if (!mt) { err_line(err, "unsupported return type " + e.ret); return false; }
                std::vector<Metadata*> md;
                if (e.stage == "vertex") md = {S(ctx, "air.position")};
                else {
                    const Attr* at = find_attr(e.fn_attrs, "color");
                    std::string loc = at && !at->args.empty() ? attr_value(at->args[0]) : "";
                    if (find_attr(e.fn_attrs, "depth")) md = {S(ctx, "air.depth"), S(ctx, "air.depth_qualifier"), S(ctx, "any")};
                    else md = {S(ctx, "air.render_target"), S(ctx, loc.empty() ? "@int:0" : "@attr:" + loc), S(ctx, "@int:0"),
                               S(ctx, "air.arg_type_name"), S(ctx, ret)};
                }
                add_out(mt, md, ret, "__r");
            }
        }
        std::string w = "extern \"C\" __attribute__((always_inline)) void __xef_entry_" + e.name + "(" + sig + ") {\n" + pre;
        if (ret != "void") w += "  " + e.ret + " __r = __xef_user_" + e.name + "(" + call_args + ");\n" + post;
        else w += "  __xef_user_" + e.name + "(" + call_args + ");\n";
        w += "}\n";
        wrappers += w;
        plans.push_back(std::move(pl));
    }
    if (plans.empty()) { err = "no vertex, fragment or kernel functions in the source"; return false; }
    std::string full = "#include <metal_stdlib>\nusing namespace metal;\n" + body + "\n" + attr_globals + wrappers;
    if (getenv("XEF_MSL_DUMP")) fprintf(stderr, "=== rewritten MSL\n%s\n", full.c_str());

    // 3. compile
    ClangOut co;
    if (!run_clang(full, false, &ctx, co, diag)) { err = "MSL compilation failed:\n" + diag; return false; }
    Module& m = *co.mod;
    const DataLayout& dl = m.getDataLayout();
    (void)dl;

    // attribute values
    auto attr_int = [&](const std::string& s, bool& ok) -> int64_t {
        ok = true;
        if (s.rfind("@int:", 0) == 0) return atoll(s.c_str() + 5);
        if (s.rfind("@attr:", 0) == 0) {
            GlobalVariable* g = m.getGlobalVariable(s.substr(6), true);
            if (g && g->hasInitializer())
                if (auto* ci = dyn_cast<ConstantInt>(g->getInitializer())) return ci->getSExtValue();
        }
        ok = false;
        return 0;
    };

    // function constants -> AIR pattern
    std::vector<Metadata*> fc_nodes;
    std::map<std::string, GlobalVariable*> fc_globals;
    for (FnConst& f : ps.fconsts) {
        GlobalVariable* g = m.getGlobalVariable(f.name, true);
        if (!g) continue;
        Type* vt = g->getValueType();
        // MSL bool constants are stored as i8
        GlobalVariable* ng = new GlobalVariable(m, vt, true, GlobalValue::InternalLinkage, UndefValue::get(vt), f.name + ".MTL_FC", nullptr,
                                                GlobalValue::NotThreadLocal, 2);
        ng->setExternallyInitialized(true);
        ng->setSection("air.fc_initializer");
        g->replaceAllUsesWith(ConstantExpr::getAddrSpaceCast(ng, g->getType()));
        g->eraseFromParent();
        ng->setName(f.name);
        std::string attr = attr_value(f.index_expr);
        (void)attr;
        // the index is a constant expression in the source: evaluate the simple cases here
        int64_t idx = atoll(f.index_expr.c_str());
        fc_nodes.push_back(MDNode::get(ctx, {ValueAsMetadata::get(ng), S(ctx, clean_type(f.type)), S(ctx, f.name), I(ctx, idx), ConstantAsMetadata::get(ConstantInt::getTrue(ctx))}));
        fc_globals[f.name] = ng;
    }
    if (!fc_nodes.empty()) {
        NamedMDNode* nm = m.getOrInsertNamedMetadata("air.function_constants");
        for (Metadata* n : fc_nodes) nm->addOperand(cast<MDNode>(n));
    }

    // threadgroup locals -> addrspace(3)
    {
        std::vector<GlobalVariable*> tg;
        for (GlobalVariable& g : m.globals()) if (g.getSection() == "xef.tg") tg.push_back(&g);
        for (GlobalVariable* g : tg) {
            auto* ng = new GlobalVariable(m, g->getValueType(), false, GlobalValue::InternalLinkage, UndefValue::get(g->getValueType()),
                                          g->getName() + ".tg", nullptr, GlobalValue::NotThreadLocal, 3);
            ng->setAlignment(g->getAlign());
            g->replaceAllUsesWith(ConstantExpr::getAddrSpaceCast(ng, g->getType()));
            g->eraseFromParent();
        }
    }

    // 4. AIR entry points
    NamedMDNode* mds[3] = {m.getOrInsertNamedMetadata("air.vertex"), m.getOrInsertNamedMetadata("air.fragment"),
                           m.getOrInsertNamedMetadata("air.kernel")};
    std::vector<std::pair<std::string, uint8_t>> fn_list;
    for (EntryPlan& pl : plans) {
        Entry& e = *pl.e;
        Function* w = m.getFunction("__xef_entry_" + e.name);
        if (!w) { err_line(err, "wrapper for " + e.name + " missing"); return false; }
        std::vector<Type*> ptys;
        for (Slot& s : pl.inputs) ptys.push_back(s.kind == Slot::Pointer ? (Type*)PointerType::get(ctx, s.as) : s.type);
        std::vector<Type*> otys;
        for (auto& o : pl.outputs) otys.push_back(o.first);
        Type* rt = otys.empty() ? Type::getVoidTy(ctx) : (Type*)StructType::get(ctx, otys);
        if (Function* old = m.getFunction(e.name)) old->setName(e.name + ".user");
        Function* f = Function::Create(FunctionType::get(rt, ptys, false), GlobalValue::ExternalLinkage, e.name, m);
        BasicBlock* bb = BasicBlock::Create(ctx, "entry", f);
        IRBuilder<> b(bb);
        std::vector<Value*> wargs;
        for (size_t i = 0; i < pl.inputs.size(); i++) {
            Value* a = f->getArg((unsigned)i);
            if (pl.inputs[i].kind == Slot::Pointer) wargs.push_back(b.CreateAddrSpaceCast(a, PointerType::get(ctx, 0)));
            else {
                Type* st = a->getType();
                Value* v = a;
                if (st->getScalarType()->isIntegerTy(1)) {   // C++ bool is a byte in memory
                    st = st->isVectorTy() ? (Type*)FixedVectorType::get(b.getInt8Ty(), cast<FixedVectorType>(st)->getNumElements()) : b.getInt8Ty();
                    v = b.CreateZExt(a, st);
                }
                AllocaInst* al = b.CreateAlloca(st);
                b.CreateStore(v, al);
                wargs.push_back(al);
            }
        }
        std::vector<AllocaInst*> outs;
        for (Type* ot : otys) {
            Type* st = ot->getScalarType()->isIntegerTy(1) ? (Type*)b.getInt8Ty() : ot;
            outs.push_back(b.CreateAlloca(st));
            wargs.push_back(outs.back());
        }
        b.CreateCall(w, wargs);
        if (otys.empty()) b.CreateRetVoid();
        else {
            Value* r = PoisonValue::get(rt);
            for (unsigned i = 0; i < otys.size(); i++) {
                Value* v = b.CreateLoad(outs[i]->getAllocatedType(), outs[i]);
                if (otys[i]->isIntegerTy(1)) v = b.CreateICmpNE(v, b.getInt8(0));
                r = b.CreateInsertValue(r, v, {i});
            }
            b.CreateRet(r);
        }
        // metadata: resolve @attr:/@int:/@fc: placeholders
        auto resolve = [&](std::vector<Metadata*> md, bool& ok) {
            std::vector<Metadata*> r;
            for (Metadata* x : md) {
                if (auto* s = dyn_cast<MDString>(x)) {
                    StringRef v = s->getString();
                    if (v.starts_with("@attr:") || v.starts_with("@int:")) {
                        bool good;
                        int64_t iv = attr_int(v.str(), good);
                        if (!good) ok = false;
                        r.push_back(I(ctx, iv));
                        continue;
                    }
                    if (v.starts_with("@fc:")) {
                        auto it = fc_globals.find(v.drop_front(4).str());
                        if (it != fc_globals.end()) r.push_back(ValueAsMetadata::get(it->second));
                        else r.push_back(ConstantAsMetadata::get(ConstantInt::getTrue(ctx)));
                        continue;
                    }
                }
                r.push_back(x);
            }
            return r;
        };
        std::vector<Metadata*> in_md, out_md;
        bool ok = true;
        for (size_t i = 0; i < pl.inputs.size(); i++) {
            std::vector<Metadata*> md = resolve(pl.inputs[i].md, ok);
            md.insert(md.begin(), I(ctx, (int64_t)i));
            in_md.push_back(MDNode::get(ctx, md));
        }
        for (auto& o : pl.outputs) out_md.push_back(MDNode::get(ctx, resolve(o.second, ok)));
        if (!ok) { err_line(err, "attribute of " + e.name + " is not an integer constant expression"); return false; }
        std::vector<Metadata*> node = {ValueAsMetadata::get(f), MDNode::get(ctx, out_md), MDNode::get(ctx, in_md)};
        if (find_attr(e.fn_attrs, "early_fragment_tests")) node.push_back(MDNode::get(ctx, {S(ctx, "air.early_fragment_tests")}));
        int k = e.stage == "vertex" ? 0 : e.stage == "fragment" ? 1 : 2;
        mds[k]->addOperand(MDNode::get(ctx, node));
        fn_list.push_back({e.name, (uint8_t)k});
    }
    for (Function& fn : m)
        if (!fn.isDeclaration() && fn.getLinkage() == GlobalValue::ExternalLinkage) {
            bool entry = false;
            for (auto& [n, k] : fn_list) if (fn.getName() == n) entry = true;
            if (!entry) fn.setLinkage(GlobalValue::InternalLinkage);
        }
    for (GlobalVariable& g : m.globals())
        if (g.getName().starts_with("__xef_attr_")) g.setLinkage(GlobalValue::InternalLinkage);

    // 5. bitcode + metallib container
    SmallVector<char, 0> bc;
    raw_svector_ostream bos(bc);
    WriteBitcodeToFile(m, bos);
    metallib = make_metallib(fn_list, std::vector<uint8_t>(bc.begin(), bc.end()));
    return true;
}

// minimal MTLB writer: every function points at the same module bitcode
std::vector<uint8_t> make_metallib(const std::vector<std::pair<std::string, uint8_t>>& fns, const std::vector<uint8_t>& bc) {
    std::vector<uint8_t> list;
    auto put = [](std::vector<uint8_t>& v, const void* p, size_t n) { v.insert(v.end(), (const uint8_t*)p, (const uint8_t*)p + n); };
    uint32_t count = (uint32_t)fns.size();
    for (auto& [name, type] : fns) {
        std::vector<uint8_t> e;
        uint32_t sz = 0;
        put(e, &sz, 4);
        put(e, "NAME", 4); uint16_t nl = (uint16_t)(name.size() + 1); put(e, &nl, 2); put(e, name.c_str(), name.size() + 1);
        put(e, "TYPE", 4); uint16_t one = 1; put(e, &one, 2); put(e, &type, 1);
        put(e, "MDSZ", 4); uint16_t eight = 8; put(e, &eight, 2); uint64_t bsz = bc.size(); put(e, &bsz, 8);
        put(e, "OFFT", 4); uint16_t tf = 24; put(e, &tf, 2); uint64_t z[3] = {0, 0, 0}; put(e, z, 24);
        put(e, "ENDT", 4);
        sz = (uint32_t)e.size();
        memcpy(e.data(), &sz, 4);
        list.insert(list.end(), e.begin(), e.end());
    }
    std::vector<uint8_t> out(88, 0);
    memcpy(out.data(), "MTLB", 4);
    uint16_t plat = 0x8001, vmaj = 1, vmin = 2;
    memcpy(&out[4], &plat, 2); memcpy(&out[6], &vmaj, 2); memcpy(&out[8], &vmin, 2);
    uint64_t fl_off = 88, fl_size = list.size();
    uint64_t bc_off = 88 + 4 + list.size();
    bc_off = (bc_off + 15) & ~15ull;
    uint64_t file = bc_off + bc.size();
    memcpy(&out[16], &file, 8);
    memcpy(&out[24], &fl_off, 8);
    memcpy(&out[32], &fl_size, 8);
    memcpy(&out[72], &bc_off, 8);
    uint64_t bcs = bc.size();
    memcpy(&out[80], &bcs, 8);
    out.resize(88);
    out.insert(out.end(), (const uint8_t*)&count, (const uint8_t*)&count + 4);
    out.insert(out.end(), list.begin(), list.end());
    out.resize(bc_off, 0);
    out.insert(out.end(), bc.begin(), bc.end());
    return out;
}

} // namespace mtlc::msl
