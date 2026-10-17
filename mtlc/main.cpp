// xef-mtlc: Metal shader compiler process.
//   xef-mtlc --server                         serve compile requests on stdin/stdout (used by xef-osx)
//   xef-mtlc LIB.metallib --list              list functions
//   xef-mtlc LIB.metallib --all [--dump]      compile every function separately and validate it
//   xef-mtlc LIB.metallib -f NAME [-F FRAG] [-o out.spv] [--dump] [--tg X,Y,Z]
#include "mtlc.h"
#include "../src/metal/metallib.h"
#include "llvm/Support/InitLLVM.h"
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unistd.h>
#include <vector>

using namespace xef::mtlabi;
namespace mtlc { std::string disassemble(const std::vector<uint32_t>& words); }

static bool read_full(int fd, void* p, size_t n) {
    uint8_t* b = (uint8_t*)p;
    while (n) {
        ssize_t r = read(fd, b, n);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) return false;
        b += r; n -= (size_t)r;
    }
    return true;
}
static bool write_full(int fd, const void* p, size_t n) {
    const uint8_t* b = (const uint8_t*)p;
    while (n) {
        ssize_t r = write(fd, b, n);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) return false;
        b += r; n -= (size_t)r;
    }
    return true;
}

static int serve() {
    for (;;) {
        uint32_t hdr[3];
        if (!read_full(0, hdr, sizeof(hdr))) return 0;
        if (hdr[0] != kProtoMagic) { fprintf(stderr, "xef-mtlc: bad message magic\n"); return 1; }
        std::vector<uint8_t> payload(hdr[2]);
        if (hdr[2] && !read_full(0, payload.data(), payload.size())) return 1;
        if (hdr[1] == MSG_QUIT) return 0;
        CompileResult res;
        if (hdr[1] == MSG_COMPILE) {
            CompileRequest req;
            if (!deserialize(payload.data(), payload.size(), req)) res.log = "malformed request";
            else mtlc::compile(req, res);
        } else if (hdr[1] == MSG_PING) {
            res.ok = true;
        }
        std::vector<uint8_t> out = serialize(res);
        uint32_t rh[3] = {kProtoMagic, MSG_RESULT, (uint32_t)out.size()};
        if (!write_full(1, rh, sizeof(rh)) || !write_full(1, out.data(), out.size())) return 1;
    }
}

static std::vector<uint8_t> read_file(const char* path) {
    std::vector<uint8_t> d;
    FILE* f = fopen(path, "rb");
    if (!f) return d;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    d.resize((size_t)n);
    if (n > 0 && fread(d.data(), 1, (size_t)n, f) != (size_t)n) d.clear();
    fclose(f);
    return d;
}

static uint32_t stage_of(uint8_t t) {
    return t == xef::metallib::FN_FRAGMENT ? STAGE_FRAGMENT : t == xef::metallib::FN_KERNEL ? STAGE_KERNEL : STAGE_VERTEX;
}

int main(int argc, char** argv) {
    llvm::InitLLVM init(argc, argv);
    if (argc >= 2 && !strcmp(argv[1], "--server")) return serve();
    if (argc < 2) {
        fprintf(stderr, "usage: xef-mtlc --server | LIB.metallib (--list | --all | -f NAME [-F FRAG]) [-o out] [--dump]\n");
        return 2;
    }
    const char* path = argv[1];
    std::vector<uint8_t> data = read_file(path);
    if (data.empty()) { fprintf(stderr, "cannot read %s\n", path); return 1; }
    std::vector<xef::metallib::Function> fns;
    std::string err;
    bool is_lib = xef::metallib::is_metallib(data.data(), data.size());
    if (is_lib && !xef::metallib::parse(data.data(), data.size(), fns, &err)) { fprintf(stderr, "%s\n", err.c_str()); return 1; }
    bool list = false, all = false, dump = false, noval = false;
    std::string fname, frag, out;
    uint32_t tg[3] = {0, 0, 0};
    for (int i = 2; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--list") list = true;
        else if (a == "--all") all = true;
        else if (a == "--dump") dump = true;
        else if (a == "--noval") noval = true;
        else if (a == "-f" && i + 1 < argc) fname = argv[++i];
        else if (a == "-F" && i + 1 < argc) frag = argv[++i];
        else if (a == "-o" && i + 1 < argc) out = argv[++i];
        else if (a == "--tg" && i + 1 < argc) sscanf(argv[++i], "%u,%u,%u", &tg[0], &tg[1], &tg[2]);
    }
    if (list) {
        for (auto& f : fns) printf("%-10s %8zu  %s\n", xef::metallib::type_name(f.type), f.bitcode_size, f.name.c_str());
        return 0;
    }
    auto find = [&](const std::string& n) -> const xef::metallib::Function* {
        for (auto& f : fns) if (f.name == n) return &f;
        return nullptr;
    };
    auto make_stage = [&](const xef::metallib::Function& f) {
        StageSource s;
        s.stage = stage_of(f.type);
        s.function = f.name;
        s.bitcode.assign(f.bitcode, f.bitcode + f.bitcode_size);
        return s;
    };
    if (all) {
        int ok = 0, bad = 0;
        for (auto& f : fns) {
            if (f.type != xef::metallib::FN_VERTEX && f.type != xef::metallib::FN_FRAGMENT && f.type != xef::metallib::FN_KERNEL) continue;
            CompileRequest req;
            req.flags = REQ_VALIDATE | (dump ? REQ_DUMP : 0);
            req.stages.push_back(make_stage(f));
            if (f.type == xef::metallib::FN_KERNEL) { req.tg_size[0] = tg[0] ? tg[0] : 32; req.tg_size[1] = tg[1] ? tg[1] : 1; req.tg_size[2] = tg[2] ? tg[2] : 1; }
            CompileResult res;
            mtlc::compile(req, res);
            if (res.ok) ok++;
            else { bad++; printf("FAIL %-9s %s\n%s", xef::metallib::type_name(f.type), f.name.c_str(), res.log.c_str()); }
        }
        printf("%s: %d ok, %d failed\n", path, ok, bad);
        return bad ? 1 : 0;
    }
    CompileRequest req;
    req.flags = (noval ? 0 : REQ_VALIDATE) | (dump ? REQ_DUMP : 0);
    memcpy(req.tg_size, tg, sizeof(tg));
    if (is_lib) {
        const xef::metallib::Function* f = fname.empty() && fns.size() == 1 ? &fns[0] : find(fname);
        if (!f) { fprintf(stderr, "function '%s' not found\n", fname.c_str()); return 1; }
        req.stages.push_back(make_stage(*f));
        if (!frag.empty()) {
            const xef::metallib::Function* g = find(frag);
            if (!g) { fprintf(stderr, "function '%s' not found\n", frag.c_str()); return 1; }
            req.stages.push_back(make_stage(*g));
        }
    } else {
        StageSource s;   // raw bitcode module
        s.function = fname;
        s.stage = STAGE_VERTEX;
        s.bitcode = data;
        req.stages.push_back(s);
    }
    CompileResult res;
    mtlc::compile(req, res);
    if (!res.ok) { fprintf(stderr, "%s", res.log.c_str()); return 1; }
    for (size_t i = 0; i < res.stages.size(); i++) {
        auto& s = res.stages[i];
        printf("stage %u: %zu words, table %u bytes (%zu entries), %zu attribs, %zu colors, flags %#x, const %zu bytes, %zu const samplers\n",
               s.stage, s.spirv.size(), s.table_size, s.table.size(), s.attribs.size(), s.colors.size(), s.flags, s.const_data.size(), s.const_samplers.size());
        for (auto& t : s.table) printf("  table +%u: kind %u index %u\n", t.offset, t.kind, t.index);
        if (!out.empty()) {
            std::string p = res.stages.size() > 1 ? out + "." + std::to_string(i) : out;
            FILE* fo = fopen(p.c_str(), "wb");
            if (fo) { fwrite(s.spirv.data(), 4, s.spirv.size(), fo); fclose(fo); }
        }
    }
    return 0;
}
