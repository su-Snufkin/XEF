// XEF-OSX — Darwin High-Level Emulation (HLE) Runtime implementation.
#include "loader/darwin_hle.h"
#include "loader/darwin_gl.h"
#include "loader/macho_image.h"
#include "loader/elf_loader.h"
#include "os/darwin/darwin_types.h"
#include "os/thread.h"
#include "os/signals.h"
#include "thunks/thunks.h"
#include "runtime/dispatch.h"

#include <dlfcn.h>
#include <sys/mman.h>
#include <sys/uio.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <search.h>
#include <dirent.h>
#include <sys/ioctl.h>
#include <ftw.h>
#include <algorithm>
#include <fcntl.h>
#include <sys/random.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/timerfd.h>
#include <sched.h>
#include <pthread.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <ctype.h>
#include <math.h>
#include <wchar.h>
#include <pwd.h>
#include <grp.h>
#include <locale.h>
#include <regex.h>
#include <ctype.h>
#include <chrono>
#include <sys/syscall.h>
#include <linux/futex.h>
#include <condition_variable>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <mutex>

extern "C" xef::u64 xef_call_sysv(void* fn, const xef::u64* iregs, const xef::u64* fregs,
                                  const xef::u64* stack, xef::u64 nstack, xef::u64* xmm0_out);

namespace xef {

static constexpr size_t kThunkCodeSize = 256 * 1024; // 256 KB for stubs
static uint8_t* g_thunk_code = nullptr;
static size_t   g_thunk_code_used = 0;
static std::mutex g_hle_lock;

struct ThunkEntry {
    std::string name;
    void* host_fn;
    bool errno_ret = false;   // returns an errno value (pthread_* style)
};

static std::vector<ThunkEntry> g_thunks;
void* darwin_sys_shim_lookup(const char* name);
void* darwin_stub_lookup(const char* name);
void* darwin_mach_lookup(const char* name);
void* darwin_signal_lookup(const char* name);
void* darwin_net_lookup(const char* name);
void* darwin_pthread_lookup(const char* name);
void darwin_signals_init(uint8_t* stub);
void* darwin_stub_data_lookup(const char* name);
void* darwin_sys_data_lookup(const char* name);
static std::unordered_map<std::string, uint64_t> g_symbol_cache;
static std::unordered_set<std::string> g_host_fallback_names;   // resolved only through the host's dlsym

// Special Darwin globals
static uint64_t g_stack_chk_guard = 0x595e9fbd94fda766ull;
static FILE* g_guest_stdin  = nullptr;
static FILE* g_guest_stdout = nullptr;
static FILE* g_guest_stderr = nullptr;

uint64_t g_darwin_stack_top = 0;
uint64_t g_darwin_stack_size = 0;
uint64_t g_darwin_mach_header = 0;
int g_darwin_argc = 0;
char** g_darwin_argv = nullptr;
char** g_darwin_envp = nullptr;
std::string g_darwin_exe_path;
uint64_t g_darwin_exit_trampoline = 0;
uint64_t g_darwin_start_stub = 0;
uint64_t g_darwin_start_target = 0;
static void darwin_start_marker() {}
uint64_t g_darwin_thread_exit_trampoline = 0;
const uint8_t* g_darwin_tlv_template = nullptr;
size_t g_darwin_tlv_template_size = 0;
static thread_local const char* tl_hle_name = nullptr;
static thread_local u64 tl_hle_lr = 0;

// Darwin RuneLocale (ctype) structures
struct DarwinRuneEntry {
    int32_t min;
    int32_t max;
    int32_t map;
    uint32_t* types;
};

struct DarwinRuneRange {
    int32_t nranges;
    int32_t pad;
    DarwinRuneEntry* ranges;
};

struct DarwinRuneLocale {
    char magic[8];
    char encoding[32];
    uint32_t (*sgetrune)(const char*, size_t, char const**);
    int (*sputrune)(uint32_t, char*, size_t, char**);
    uint32_t invalid_rune;
    uint32_t runetype[256];
    uint32_t maplower[256];
    uint32_t mapupper[256];
    DarwinRuneRange runetype_ext;
    DarwinRuneRange maplower_ext;
    DarwinRuneRange mapupper_ext;
    void* variable;
    int32_t variable_len;
    int32_t pad[3];
};
static_assert(offsetof(DarwinRuneLocale, runetype) == 60, "runetype offset");
static_assert(offsetof(DarwinRuneLocale, maplower) == 1084, "maplower offset");
static_assert(offsetof(DarwinRuneLocale, mapupper) == 2108, "mapupper offset");
static_assert(offsetof(DarwinRuneLocale, runetype_ext) == 3136, "runetype_ext offset");
static_assert(offsetof(DarwinRuneLocale, maplower_ext) == 3152, "maplower_ext offset");
static_assert(offsetof(DarwinRuneLocale, mapupper_ext) == 3168, "mapupper_ext offset");
static_assert(offsetof(DarwinRuneLocale, variable) == 3184, "variable offset");
static_assert(offsetof(DarwinRuneLocale, variable_len) == 3192, "variable_len offset");
static_assert(sizeof(DarwinRuneLocale) == 3208, "DarwinRuneLocale size");

static DarwinRuneLocale g_darwin_rune_locale;
static DarwinRuneLocale* g_darwin_current_rune_locale = &g_darwin_rune_locale;

static void init_rune_locale() {
    memset(&g_darwin_rune_locale, 0, sizeof(g_darwin_rune_locale));
    memcpy(g_darwin_rune_locale.magic, "RuneMagA", 8);
    strcpy(g_darwin_rune_locale.encoding, "NONE");
    g_darwin_rune_locale.invalid_rune = 0xffffffff;
    g_darwin_current_rune_locale = &g_darwin_rune_locale;

    for (int i = 0; i < 256; i++) {
        uint32_t flags = 0;
        // Darwin <runetype.h>: A=0x100 C=0x200 D=0x400 G=0x800 L=0x1000 P=0x2000 S=0x4000 U=0x8000
        //                      X=0x10000 B=0x20000 R=0x40000
        if (isalpha(i)) flags |= 0x00000100;
        if (iscntrl(i)) flags |= 0x00000200;
        if (isdigit(i)) flags |= 0x00000400 | (uint32_t)(i - '0');
        if (isgraph(i)) flags |= 0x00000800;
        if (islower(i)) flags |= 0x00001000;
        if (ispunct(i)) flags |= 0x00002000;
        if (isspace(i)) flags |= 0x00004000;
        if (isupper(i)) flags |= 0x00008000;
        if (isxdigit(i)) flags |= 0x00010000;
        if (i == ' ' || i == '\t') flags |= 0x00020000;
        if (isprint(i)) flags |= 0x00040000;
        if (isxdigit(i) && !isdigit(i)) flags |= (uint32_t)(tolower(i) - 'a' + 10);
        g_darwin_rune_locale.runetype[i] = flags;
        g_darwin_rune_locale.maplower[i] = tolower(i);
        g_darwin_rune_locale.mapupper[i] = toupper(i);
    }
}

// Special wrapper functions
// Darwin errno numbering differs from Linux above 34 (EAGAIN 35 vs 11, ETIMEDOUT 60 vs 110, ...).
static const struct { int linux_e, darwin_e; } kErrnoMap[] = {
    {11, 35}, {115, 36}, {114, 37}, {88, 38}, {89, 39}, {90, 40}, {91, 41}, {92, 42}, {93, 43}, {94, 44},
    {95, 45}, {96, 46}, {97, 47}, {98, 48}, {99, 49}, {100, 50}, {101, 51}, {102, 52}, {103, 53}, {104, 54},
    {105, 55}, {106, 56}, {107, 57}, {108, 58}, {109, 59}, {110, 60}, {111, 61}, {40, 62}, {36, 63}, {112, 64},
    {113, 65}, {39, 66}, {87, 68}, {122, 69}, {116, 70}, {66, 71}, {37, 77}, {38, 78}, {125, 89}, {43, 90},
    {42, 91}, {84, 92}, {61, 96}, {74, 94}, {72, 95}, {67, 97}, {63, 98}, {60, 99},
    {71, 100}, {62, 101}, {131, 104}, {130, 105}, {35, 11},
    {1093, 93},   // ENOATTR: no Linux errno (xattr calls report ENODATA); darwin_fs.cpp uses 1093 for it
};
int darwin_errno_from_linux(int e) {
    if (e <= 34 && e != 11) return e;      // 11 is EAGAIN on Linux but EDEADLK on Darwin
    for (auto& m : kErrnoMap) if (m.linux_e == e) return m.darwin_e;
    return e;
}
int darwin_errno_to_linux(int e) {
    if (e <= 34 && e != 11) return e;
    for (auto& m : kErrnoMap) if (m.darwin_e == e) return m.linux_e;
    return e;
}
static thread_local int g_darwin_errno = 0;
static int* darwin_error_wrapper() {
    return &g_darwin_errno;
}

static void darwin_stack_chk_fail_wrapper() {
    fprintf(stderr, "*** stack smashing detected ***: terminated\n");
    abort();
}

static void darwin_assert_rtn_wrapper(const char* fn, const char* file, int line, const char* expr) {
    fprintf(stderr, "Assertion failed: (%s), function %s, file %s, line %d.\n",
            expr ? expr : "", fn ? fn : "", file ? file : "", line);
    abort();
}

static uint32_t darwin_maskrune_wrapper(int c, uint32_t mask) {
    if (c >= 0 && c < 256) {
        return g_darwin_rune_locale.runetype[c] & mask;
    }
    return 0;
}

static void* darwin_memcpy_chk_wrapper(void* dst, const void* src, size_t len, size_t dst_len) {
    (void)dst_len;
    return memmove(dst, src, len);
}

struct GuestAtExit { u64 fn, arg; bool cxa; };
static std::vector<GuestAtExit> g_guest_atexit;
static std::mutex g_atexit_lock;
static int darwin_atexit_wrapper(u64 fn) {
    if (fn) {
        std::lock_guard<std::mutex> lk(g_atexit_lock);
        g_guest_atexit.push_back({fn, 0, false});
    }
    return 0;
}
static int darwin_cxa_atexit(u64 fn, u64 arg, u64 dso) {
    (void)dso;
    if (fn) {
        std::lock_guard<std::mutex> lk(g_atexit_lock);
        g_guest_atexit.push_back({fn, arg, true});
    }
    return 0;
}
static void darwin_cxa_finalize(u64) {}

void darwin_run_exit_handlers() {
    for (;;) {
        GuestAtExit e;
        {
            std::lock_guard<std::mutex> lk(g_atexit_lock);
            if (g_guest_atexit.empty()) return;
            e = g_guest_atexit.back();
            g_guest_atexit.pop_back();
        }
        if (e.cxa) { u64 a[1] = {e.arg}; guest_call(e.fn, 1, a); }
        else guest_call(e.fn, 0, nullptr);
    }
}

static void darwin_exit_wrapper(int code) {
    darwin_run_exit_handlers();
    guest_process_exit(code);
}

static int darwin_ulock_wait(uint32_t op, void* addr, uint64_t value, uint32_t timeout_us) {
    struct timespec ts, *tsp = nullptr;
    if (timeout_us) { ts.tv_sec = timeout_us / 1000000; ts.tv_nsec = (timeout_us % 1000000) * 1000L; tsp = &ts; }
    long r = syscall(SYS_futex, addr, FUTEX_WAIT_PRIVATE, (uint32_t)value, tsp, nullptr, 0);
    (void)op;
    if (r < 0) return errno == ETIMEDOUT ? -ETIMEDOUT : (errno == EAGAIN ? 0 : -errno);
    return 0;
}
static int darwin_ulock_wake(uint32_t op, void* addr, uint64_t) {
    long r = syscall(SYS_futex, addr, FUTEX_WAKE_PRIVATE, (op & 0x100) ? 0x7fffffff : 1, nullptr, nullptr, 0);
    return r < 0 ? -errno : 0;
}
static int darwin_enosys() { errno = ENOSYS; return -1; }
static void* darwin_copyfile_state_alloc() { return calloc(1, 64); }
static int darwin_copyfile_state_free(void* p) { free(p); return 0; }

static void darwin_memset_pattern16_wrapper(void* b, const void* pat, size_t len) {
    uint8_t* dst = (uint8_t*)b;
    while (len >= 16) {
        memcpy(dst, pat, 16);
        dst += 16;
        len -= 16;
    }
    if (len > 0) {
        memcpy(dst, pat, len);
    }
}

static void darwin_chkstk_wrapper() {
    // Stack probe no-op for our pre-allocated guest stack
}

static double darwin_exp10_wrapper(double x) {
    return pow(10.0, x);
}

static void darwin_missing_symbol_fallback() {
    // Handled in dispatch
}

// Formats `format` with Darwin arm64 variadic arguments: every argument occupies one 8-byte stack
// slot (also for va_list, which is a plain pointer to those slots). Returns the full length.
static std::string darwin_format(const char* format, const uint64_t* ap) {
    std::string out;
    const char* p = format;
    const uint64_t* base = ap;
    int pos = 0;   // positional argument (%n$) of the current conversion, 0: sequential
    auto next = [&]() -> uint64_t {
        if (pos > 0) return base ? base[pos - 1] : 0;
        return ap ? *ap++ : 0;
    };
    // "n$" after '%' or '*': a 1-based argument index (every argument is one 8-byte slot, so any order works)
    auto dollar = [&](const char* q, int* idx) -> const char* {
        int n = 0;
        const char* r = q;
        while (isdigit((unsigned char)*r)) n = n * 10 + (*r++ - '0');
        if (r != q && *r == '$') { *idx = n; return r + 1; }
        return q;
    };
    while (*p) {
        if (*p != '%') { out.push_back(*p++); continue; }
        const char* start = p++;
        if (*p == '%') { out.push_back('%'); p++; continue; }
        pos = 0;
        p = dollar(p, &pos);
        std::string flags, width, prec;
        bool has_prec = false;
        while (*p && strchr("-+ #0'", *p)) flags.push_back(*p++);
        auto star = [&]() -> int {   // '*' or '*m$'
            int idx = 0;
            const char* q = dollar(p + 1, &idx);
            int v;
            if (idx > 0) { v = base ? (int)base[idx - 1] : 0; p = q; }
            else { int save = pos; pos = 0; v = (int)next(); pos = save; p++; }
            return v;
        };
        if (*p == '*') { int w = star(); if (w < 0) { flags.push_back('-'); w = -w; } width = std::to_string(w); }
        else while (isdigit((unsigned char)*p)) width.push_back(*p++);
        if (*p == '.') {
            has_prec = true; p++;
            if (*p == '*') { int pr = star(); if (pr < 0) has_prec = false; else prec = std::to_string(pr); }
            else while (isdigit((unsigned char)*p)) prec.push_back(*p++);
            if (has_prec && prec.empty()) prec = "0";
        }
        int lng = 0;   // 0 int, -1 short, -2 char, 1 long, 2 long long/intmax/size_t/ptrdiff
        bool big_l = false;
        for (;; p++) {
            if (*p == 'h') lng = lng == -1 ? -2 : -1;
            else if (*p == 'l') lng = lng == 1 ? 2 : 1;
            else if (strchr("jztq", *p)) lng = 2;
            else if (*p == 'L') big_l = true;
            else break;
        }
        char conv = *p ? *p++ : 0;
        if (!conv) { out.append(start); break; }
        std::string spec = "%" + flags + width + (has_prec ? "." + prec : "");
        char tmp[64];
        auto emit = [&](const std::string& sp, auto val) {
            int n = snprintf(nullptr, 0, sp.c_str(), val);
            if (n <= 0) return;
            size_t at = out.size();
            out.resize(at + n + 1);
            snprintf(&out[at], n + 1, sp.c_str(), val);
            out.resize(at + n);
        };
        switch (conv) {
            case 'd': case 'i': {
                int64_t v = (int64_t)next();
                if (lng == 0) v = (int32_t)v; else if (lng == -1) v = (int16_t)v; else if (lng == -2) v = (int8_t)v;
                emit(spec + "ll" + conv, (long long)v);
                break;
            }
            case 'D': emit(spec + "lld", (long long)next()); break;
            case 'u': case 'o': case 'x': case 'X': {
                uint64_t v = next();
                if (lng == 0) v = (uint32_t)v; else if (lng == -1) v = (uint16_t)v; else if (lng == -2) v = (uint8_t)v;
                emit(spec + "ll" + conv, (unsigned long long)v);
                break;
            }
            case 'U': case 'O': emit(spec + "ll" + (char)(conv == 'U' ? 'u' : 'o'), (unsigned long long)next()); break;
            case 'e': case 'E': case 'f': case 'F': case 'g': case 'G': case 'a': case 'A': {
                uint64_t raw = next();   // Darwin long double == double
                double d; memcpy(&d, &raw, 8);
                (void)big_l;
                emit(spec + conv, d);
                break;
            }
            case 'c': {
                if (lng == 1) emit(spec + "lc", (wint_t)next());
                else emit(spec + "c", (int)next());
                break;
            }
            case 'C': emit(spec + "lc", (wint_t)next()); break;
            case 's': {
                const void* sp = (const void*)(uintptr_t)next();
                if (!sp) sp = "(null)", lng = 0;
                if (lng == 1) emit(spec + "ls", (const wchar_t*)sp); else emit(spec + "s", (const char*)sp);
                break;
            }
            case 'S': emit(spec + "ls", (const wchar_t*)(uintptr_t)next()); break;
            case 'p': {   // BSD: always "0x" + lowercase hex (NULL is "0x0", not glibc's "(nil)")
                uint64_t v = next();
                char hx[32];
                snprintf(hx, sizeof hx, "%llx", (unsigned long long)v);
                std::string d = (has_prec && prec == "0" && !v) ? std::string() : std::string(hx);
                if (has_prec && d.size() < (size_t)atoi(prec.c_str())) d.insert(0, atoi(prec.c_str()) - d.size(), '0');
                size_t w = width.empty() ? 0 : (size_t)atoi(width.c_str());
                bool left = flags.find('-') != std::string::npos;
                if (!left && !has_prec && flags.find('0') != std::string::npos && d.size() + 2 < w) d.insert(0, w - 2 - d.size(), '0');
                d.insert(0, "0x");
                if (d.size() < w) { if (left) d.append(w - d.size(), ' '); else d.insert(0, w - d.size(), ' '); }
                out += d;
                break;
            }
            case 'n': {
                void* ptr = (void*)(uintptr_t)next();
                if (ptr) { if (lng == 0) *(int*)ptr = (int)out.size(); else *(long long*)ptr = (long long)out.size(); }
                break;
            }
            default: out.append(start, p - start); break;
        }
        (void)tmp;
    }
    return out;
}

static int darwin_vsnprintf(char* str, size_t size, const char* format, const uint64_t* ap) {
    if (!format) { if (str && size) str[0] = 0; return 0; }
    std::string r = darwin_format(format, ap);
    if (str && size) {
        size_t n = std::min(r.size(), size - 1);
        memcpy(str, r.data(), n);
        str[n] = 0;
    }
    return (int)r.size();
}

static int darwin_vfprintf(FILE* guest_stream, const char* format, const uint64_t* ap) {
    FILE* stream = darwin_stdio_host(guest_stream);
    if (!stream || !format) return -1;
    std::string r = darwin_format(format, ap);
    if (!r.empty() && fwrite(r.data(), 1, r.size(), stream) != r.size()) { darwin_stdio_sync(guest_stream); return -1; }
    return (int)r.size();
}

static int darwin_fprintf(FILE* stream, const char* format, const uint64_t* ap) {
    return darwin_vfprintf(stream, format, ap);
}

static int darwin_printf(const char* format, const uint64_t* ap) {
    return darwin_vfprintf(stdout, format, ap);
}

static int darwin_snprintf(char* str, size_t size, const char* format, const uint64_t* ap) {
    return darwin_vsnprintf(str, size, format, ap);
}

static const char* darwin_strerror(int errnum) {
    int le = darwin_errno_to_linux(errnum);
    const char* msg = strerror(le);
    return msg ? msg : "Unknown error";
}

static int darwin_strerror_r(int errnum, char* buf, size_t buflen) {
    if (!buf || buflen == 0) return ERANGE;
    const char* msg = strerror(darwin_errno_to_linux(errnum));
    if (!msg) msg = "Unknown error";
    strncpy(buf, msg, buflen - 1);
    buf[buflen - 1] = '\0';
    return 0;
}

static const char* darwin_getprogname() {
    const char* p = strrchr(g_darwin_exe_path.c_str(), '/');
    return p ? p + 1 : (g_darwin_exe_path.empty() ? "xef" : g_darwin_exe_path.c_str());
}

static void darwin_warn_impl(bool use_errno, const char* format, const uint64_t* ap) {
    const char* prog = darwin_getprogname();
    fprintf(stderr, "%s: ", prog);
    if (format) {
        std::string r = darwin_format(format, ap);
        fprintf(stderr, "%s", r.c_str());
        if (use_errno) fprintf(stderr, ": ");
    }
    if (use_errno) {
        fprintf(stderr, "%s\n", darwin_strerror(g_darwin_errno));
    } else {
        fprintf(stderr, "\n");
    }
}

static void darwin_err(int eval, const char* fmt, ...) { (void)eval; (void)fmt; }
static void darwin_errx(int eval, const char* fmt, ...) { (void)eval; (void)fmt; }
static void darwin_errc(int eval, int code, const char* fmt, ...) { (void)eval; (void)code; (void)fmt; }
static void darwin_warn(const char* fmt, ...) { (void)fmt; }
static void darwin_warnx(const char* fmt, ...) { (void)fmt; }
static void darwin_warnc(int code, const char* fmt, ...) { (void)code; (void)fmt; }

// Darwin regex ABI (32-byte struct with embedded pointer vs Linux 64-byte struct)
struct DarwinRegex {
    int re_magic;
    int _pad;
    size_t re_nsub;
    const char* re_endp;
    void* re_g;
};
static_assert(sizeof(DarwinRegex) == 32, "DarwinRegex size must be 32 bytes");

struct DarwinRegmatch {
    int64_t rm_so;
    int64_t rm_eo;
};
static_assert(sizeof(DarwinRegmatch) == 16, "DarwinRegmatch size must be 16 bytes");

static int darwin_regcomp(DarwinRegex* preg, const char* regex, int cflags) {
    if (!preg || !regex) return 16; // REG_INVARG
    regex_t* host_re = new (std::nothrow) regex_t();
    if (!host_re) return REG_ESPACE;
    int host_cflags = 0;
    if (cflags & 0001) host_cflags |= REG_EXTENDED;
    if (cflags & 0002) host_cflags |= REG_ICASE;
    if (cflags & 0004) host_cflags |= REG_NOSUB;
    if (cflags & 0010) host_cflags |= REG_NEWLINE;
    int rc = regcomp(host_re, regex, host_cflags);
    if (rc != 0) {
        delete host_re;
        return rc;
    }
    preg->re_magic = 0xfedb;
    preg->re_nsub = host_re->re_nsub;
    preg->re_endp = nullptr;
    preg->re_g = host_re;
    return 0;
}

static int darwin_regexec(const DarwinRegex* preg, const char* string, size_t nmatch, DarwinRegmatch* pmatch, int eflags) {
    if (!preg || !preg->re_g || !string) return 16;
    regex_t* host_re = (regex_t*)preg->re_g;
    int host_eflags = 0;
    if (eflags & 00001) host_eflags |= REG_NOTBOL;
    if (eflags & 00002) host_eflags |= REG_NOTEOL;

    std::vector<regmatch_t> host_match;
    regmatch_t* hpmatch = nullptr;
    if (pmatch && nmatch > 0) {
        host_match.resize(nmatch);
        hpmatch = host_match.data();
#ifdef REG_STARTEND
        if (eflags & 00004) {
            host_eflags |= REG_STARTEND;
            hpmatch[0].rm_so = (regoff_t)pmatch[0].rm_so;
            hpmatch[0].rm_eo = (regoff_t)pmatch[0].rm_eo;
        }
#endif
    }
    int rc = regexec(host_re, string, nmatch, hpmatch, host_eflags);
    if (rc == 0 && pmatch && nmatch > 0) {
        for (size_t i = 0; i < nmatch; i++) {
            pmatch[i].rm_so = (int64_t)hpmatch[i].rm_so;
            pmatch[i].rm_eo = (int64_t)hpmatch[i].rm_eo;
        }
    }
    return rc;
}

static void darwin_regfree(DarwinRegex* preg) {
    if (!preg) return;
    regex_t* host_re = (regex_t*)preg->re_g;
    if (host_re) {
        regfree(host_re);
        delete host_re;
        preg->re_g = nullptr;
    }
}

static size_t darwin_regerror(int errcode, const DarwinRegex* preg, char* errbuf, size_t errbuf_size) {
    regex_t* host_re = (preg && preg->re_g) ? (regex_t*)preg->re_g : nullptr;
    return regerror(errcode, host_re, errbuf, errbuf_size);
}


static void* darwin_mmap(void* addr, size_t length, int prot, int dflags, int fd, off_t offset) {
    int lflags = 0;
    if (dflags & 0x0001) lflags |= MAP_SHARED;
    if (dflags & 0x0002) lflags |= MAP_PRIVATE;
    if (dflags & 0x0010) lflags |= MAP_FIXED;
    if (dflags & 0x1000) lflags |= MAP_ANONYMOUS;
    if (dflags & 0x0040) lflags |= MAP_NORESERVE;

    if (lflags & MAP_ANONYMOUS) {
        fd = -1;
        offset = 0;
    }

    // Darwin pages are 16K: the guest rounds lengths and expects 16K-aligned results, and will munmap/mprotect whole
    // 16K pages - so every mapping covers whole 16K pages (else a later munmap would hit host memory next to it)
    size_t len16 = (length + 16383) & ~(size_t)16383;
    if (!length) { errno = EINVAL; return MAP_FAILED; }
    void* r;
    if (lflags & MAP_FIXED) {
        r = mmap(addr, len16, prot, lflags, fd, offset);
    } else {
        r = MAP_FAILED;
        if (addr) {                                            // a hint: taken when the kernel gives an aligned address
            r = mmap(addr, len16, prot, lflags, fd, offset);
            if (r != MAP_FAILED && ((uintptr_t)r & 16383)) { munmap(r, len16); r = MAP_FAILED; }
        }
        if (r == MAP_FAILED) {
            void* res = mmap(nullptr, len16 + 16384, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
            if (res == MAP_FAILED) return MAP_FAILED;
            uintptr_t u = (uintptr_t)res, aligned = (u + 16383) & ~(uintptr_t)16383;
            if (aligned > u) munmap(res, aligned - u);
            if (u + 16384 > aligned) munmap((void*)(aligned + len16), u + 16384 - aligned);
            r = mmap((void*)aligned, len16, prot, lflags | MAP_FIXED, fd, offset);
            if (r == MAP_FAILED) { int e = errno; munmap((void*)aligned, len16); errno = e; }
        }
    }
    XEF_LOG(2, "darwin_mmap(addr=%p, len=%#zx, prot=%#x, dflags=%#x -> lflags=%#x, fd=%d, off=%#lx) = %p (errno=%d)",
            addr, length, prot, dflags, lflags, fd, (unsigned long)offset, r, (r == MAP_FAILED) ? errno : 0);
    return r;
}

static int darwin_getpagesize() {
    return 16384;
}

static int darwin_munmap(void* addr, size_t length) {
    int r = munmap(addr, length);
    if (r != 0) {
        fprintf(stderr, "xef: munmap(addr=%p, len=%#zx) = %d (errno=%d), caller: %s (lr=%#lx)\n",
                addr, length, r, errno, dyld_describe(tl_hle_lr).c_str(), (unsigned long)tl_hle_lr);
        ThreadCtx* t = tls_thread;
        if (t && t->st) {
            u64 fp = t->st->x[29];
            for (int i = 0; i < 10 && fp && !(fp & 7); i++) {
                u64 lr = ((u64*)fp)[1];
                fprintf(stderr, "xef:    #%d %s (fp=%#lx, lr=%#lx)\n", i, dyld_describe(lr).c_str(), (unsigned long)fp, (unsigned long)lr);
                u64 nfp = ((u64*)fp)[0];
                if (nfp <= fp || nfp >= fp + 0x10000000) break;
                fp = nfp;
            }
        }
    }
    return r;
}

static long darwin_sysconf(int name) {
    switch (name) {
    case 29: // Darwin _SC_PAGESIZE / _SC_PAGE_SIZE
        return 16384;
    case 57: // Darwin _SC_NPROCESSORS_CONF
        return sysconf(_SC_NPROCESSORS_CONF);
    case 58: // Darwin _SC_NPROCESSORS_ONLN
        return sysconf(_SC_NPROCESSORS_ONLN);
    case 50: // Darwin _SC_PHYS_PAGES
        return sysconf(_SC_PHYS_PAGES);
    default:
        return sysconf(name);
    }
}

// Guest pthread_t: like libpthread's struct _pthread, a per-thread block whose address is pthread_self() and is
// stored in TSD slot 0 (code reads it with MRS TPIDRRO_EL0). It maps to the host thread for join/detach/kill.
// Created by darwin_spawn_thread, or lazily for threads XEF did not start that way (the main thread).
// Freed by pthread_join; a detached thread's block stays (small, and pthread_t values must not be reused while a
// stale copy could still be compared).
struct DarwinPthread {
    uint64_t sig;              // 0x54485244 'THRD'
    pthread_t host;
    int tid;
    void* stack_top;
    size_t stack_size;
};
static DarwinPthread* g_main_pthread_handle;

uint64_t darwin_new_pthread_handle(void* stack_top, size_t stack_size) {
    DarwinPthread* p = new DarwinPthread{0x54485244, 0, 0, stack_top, stack_size};
    return (uint64_t)(uintptr_t)p;
}
void darwin_set_pthread_host(uint64_t handle, pthread_t host, int tid) {
    DarwinPthread* p = (DarwinPthread*)(uintptr_t)handle;
    p->host = host;
    p->tid = tid;
}
static DarwinPthread* pthread_cur() {
    ThreadCtx* t = tls_thread;
    if (!t || !t->tsd) return nullptr;
    uint64_t v = t->tsd[0];
    if (v && v != (uint64_t)(uintptr_t)t->tsd) return (DarwinPthread*)(uintptr_t)v;
    bool main = getpid() == (pid_t)syscall(SYS_gettid);
    DarwinPthread* p = new DarwinPthread{0x54485244, pthread_self(), (int)syscall(SYS_gettid),
                                         main ? (void*)(uintptr_t)g_darwin_stack_top : nullptr,
                                         main ? (size_t)g_darwin_stack_size : 0};
    if (main && !g_main_pthread_handle) g_main_pthread_handle = p;
    t->tsd[0] = (uint64_t)(uintptr_t)p;
    return p;
}
static DarwinPthread* pthread_of(uint64_t th) {
    DarwinPthread* p = th ? (DarwinPthread*)(uintptr_t)th : pthread_cur();
    if (p && p->sig != 0x54485244) return nullptr;
    if (p && !p->host && p == pthread_cur()) { p->host = pthread_self(); p->tid = (int)syscall(SYS_gettid); }
    return p;
}
uint64_t darwin_pthread_main_handle() {
    if (!g_main_pthread_handle && getpid() == (pid_t)syscall(SYS_gettid)) pthread_cur();
    return (uint64_t)(uintptr_t)g_main_pthread_handle;
}
int darwin_pthread_host(uint64_t th, pthread_t* host) {
    DarwinPthread* p = pthread_of(th);
    if (!p || !p->host) return ESRCH;
    *host = p->host;
    return 0;
}
uint32_t darwin_thread_port(int tid) { return ((uint32_t)tid << 8) | 0x07; }

static void* darwin_pthread_get_stackaddr_np(void* thread) {
    DarwinPthread* p = pthread_of((uint64_t)(uintptr_t)thread);
    return p && p->stack_top ? p->stack_top : (void*)(uintptr_t)g_darwin_stack_top;
}

static size_t darwin_pthread_get_stacksize_np(void* thread) {
    DarwinPthread* p = pthread_of((uint64_t)(uintptr_t)thread);
    return p && p->stack_size ? p->stack_size : (size_t)g_darwin_stack_size;
}

// NSGetArg* runtime helpers
static int* darwin_NSGetArgc() {
    XEF_LOG(2, "_NSGetArgc() returning %p -> %d", &g_darwin_argc, g_darwin_argc);
    return &g_darwin_argc;
}
static char*** darwin_NSGetArgv() {
    XEF_LOG(2, "_NSGetArgv() returning %p -> %p", &g_darwin_argv, g_darwin_argv);
    if (g_darwin_argv) {
        for (int i = 0; i < g_darwin_argc; i++) {
            XEF_LOG(2, "  g_darwin_argv[%d] = %p (%s)", i, g_darwin_argv[i], g_darwin_argv[i] ? g_darwin_argv[i] : "(null)");
        }
    }
    return &g_darwin_argv;
}
// one environment: the host's `environ`, which getenv/setenv/putenv (host libc) maintain and `_environ` names
static char*** darwin_NSGetEnviron() { return &environ; }
// _NSGetProgname: pointer to the program name (basename of argv[0], like libc's __progname)
static char** darwin_NSGetProgname() {
    static char* progname = nullptr;
    if (!progname) {
        const char* a = (g_darwin_argv && g_darwin_argv[0]) ? g_darwin_argv[0] : g_darwin_exe_path.c_str();
        const char* b = strrchr(a, '/');
        progname = strdup(b ? b + 1 : a);
    }
    return &progname;
}
static int darwin_NSGetExecutablePath(char* buf, uint32_t* bufsize) {
    if (!bufsize) return -1;
    uint32_t len = (uint32_t)g_darwin_exe_path.size();
    if (!buf || *bufsize <= len) {
        *bufsize = len + 1;
        return -1;
    }
    memcpy(buf, g_darwin_exe_path.c_str(), len + 1);
    *bufsize = len;
    return 0;
}
// <math.h> classification: Darwin's FP_* values (NAN 1, INFINITE 2, ZERO 3, NORMAL 4, SUBNORMAL 5) differ from glibc's
static int darwin_fp_class(int c) {
    switch (c) {
        case FP_NAN: return 1;
        case FP_INFINITE: return 2;
        case FP_ZERO: return 3;
        case FP_SUBNORMAL: return 5;
        default: return 4;
    }
}
static int darwin_fpclassifyd(double x) { return darwin_fp_class(std::fpclassify(x)); }
// libm's out-of-line classification helpers behind <math.h>'s isfinite/isinf/isnan/isnormal/signbit (long double == double)
static int darwin_isfinited(double x) { return std::isfinite(x); }
static int darwin_isfinitef(float x) { return std::isfinite(x); }
static int darwin_isinfd(double x) { return std::isinf(x); }
static int darwin_isinff(float x) { return std::isinf(x); }
static int darwin_isnand(double x) { return std::isnan(x); }
static int darwin_isnanf(float x) { return std::isnan(x); }
static int darwin_isnormald(double x) { return std::isnormal(x); }
static int darwin_isnormalf(float x) { return std::isnormal(x); }
static int darwin_signbitd(double x) { return std::signbit(x); }
static int darwin_signbitf(float x) { return std::signbit(x); }
static int darwin_fpclassifyf(float x) { return darwin_fp_class(std::fpclassify(x)); }
static float darwin_exp10f(float x) { return exp10f(x); }


// Darwin struct dirent layout (macOS $INODE64)
struct darwin_dirent {
    uint64_t  d_ino;        // [0]
    uint64_t  d_seekoff;    // [8]
    uint16_t  d_reclen;     // [16]
    uint16_t  d_namlen;     // [18]
    uint8_t   d_type;       // [20]
    char      d_name[1024]; // [21]
};

static void convert_stat_to_darwin(const struct stat& src, darwin_stat64* dst) {
    if (!dst) return;
    memset(dst, 0, sizeof(*dst));
    dst->st_dev           = darwin_dev_from_linux(src.st_dev);
    dst->st_mode          = (uint16_t)src.st_mode;
    dst->st_nlink         = (uint16_t)src.st_nlink;
    dst->st_ino           = (uint64_t)src.st_ino;
    dst->st_uid           = (uint32_t)src.st_uid;
    dst->st_gid           = (uint32_t)src.st_gid;
    dst->st_rdev          = darwin_dev_from_linux(src.st_rdev);
    dst->st_atime_sec     = (int64_t)src.st_atim.tv_sec;
    dst->st_atime_nsec    = (int64_t)src.st_atim.tv_nsec;
    dst->st_mtime_sec     = (int64_t)src.st_mtim.tv_sec;
    dst->st_mtime_nsec    = (int64_t)src.st_mtim.tv_nsec;
    dst->st_ctime_sec     = (int64_t)src.st_ctim.tv_sec;
    dst->st_ctime_nsec    = (int64_t)src.st_ctim.tv_nsec;
    dst->st_birthtime_sec = (int64_t)src.st_ctim.tv_sec;
    dst->st_birthtime_nsec= (int64_t)src.st_ctim.tv_nsec;
    dst->st_size          = (int64_t)src.st_size;
    dst->st_blocks        = (int64_t)src.st_blocks;
    dst->st_blksize       = (int32_t)src.st_blksize;
    dst->st_flags         = 0;
    dst->st_gen           = 0;
}

static int darwin_stat_fn(const char* path, darwin_stat64* dst) {
    if (!path || !dst) { errno = EFAULT; return -1; }
    std::string hp = resolve_guest_path(path);
    struct stat host_st;
    int r = stat(hp.c_str(), &host_st);
    if (r < 0) return -1;
    convert_stat_to_darwin(host_st, dst);
    return 0;
}

static int darwin_lstat_fn(const char* path, darwin_stat64* dst) {
    if (!path || !dst) { errno = EFAULT; return -1; }
    std::string hp = resolve_guest_path(path, false);   // the link itself
    struct stat host_st;
    int r = lstat(hp.c_str(), &host_st);
    if (r < 0) return -1;
    convert_stat_to_darwin(host_st, dst);
    return 0;
}

static int darwin_fstat_fn(int fd, darwin_stat64* dst) {
    if (!dst) { errno = EFAULT; return -1; }
    struct stat host_st;
    int r = fstat(fd, &host_st);
    if (r < 0) return -1;
    convert_stat_to_darwin(host_st, dst);
    return 0;
}

static inline int darwin_dfd_to_linux(int dfd) { return (dfd == -2) ? AT_FDCWD : dfd; }

std::string darwin_fstatat_path(int* dfd, const char* path, int dflag, int* lflags);   // darwin_fs.cpp
static int darwin_fstatat_fn(int dfd, const char* path, darwin_stat64* dst, int flag) {
    if (!path || !dst) { errno = EFAULT; return -1; }
    int lflags;
    std::string hp = darwin_fstatat_path(&dfd, path, flag, &lflags);
    struct stat host_st;
    int r = fstatat(dfd, hp.c_str(), &host_st, lflags);
    if (r < 0) return -1;
    convert_stat_to_darwin(host_st, dst);
    return 0;
}

int darwin_open_flags_to_linux(int df) {
    int lf = 0;
    if ((df & 3) == 0) lf |= O_RDONLY;
    if ((df & 3) == 1) lf |= O_WRONLY;
    if ((df & 3) == 2) lf |= O_RDWR;
    if (df & 0x0004) lf |= O_NONBLOCK;
    if (df & 0x0008) lf |= O_APPEND;
    if (df & 0x0080) lf |= O_SYNC;
    if (df & 0x0100) lf |= O_NOFOLLOW;
    if (df & 0x0200) lf |= O_CREAT;
    if (df & 0x0400) lf |= O_TRUNC;
    if (df & 0x0800) lf |= O_EXCL;
    if (df & 0x100000) lf |= O_DIRECTORY;
    if (df & 0x1000000) lf |= O_CLOEXEC;
    return lf;
}

static int darwin_open(const char* path, int dflags, mode_t mode) {
    if (!path) { errno = EFAULT; return -1; }
    // O_NOFOLLOW, or O_CREAT|O_EXCL (which must not follow a final symlink either): resolve up to the last component
    bool nofollow = (dflags & 0x100) || ((dflags & 0x200) && (dflags & 0x800));
    std::string hp = resolve_guest_path(path, !nofollow);
    int lflags = darwin_open_flags_to_linux(dflags);
    int r = open(hp.c_str(), lflags, mode);
    XEF_LOG(2, "darwin_open('%s' -> '%s', dflags=%#x lflags=%#x mode=%o) = %d errno=%d", path, hp.c_str(), dflags, lflags, mode, r, r < 0 ? errno : 0);
    return r;
}

int darwin_openat_impl(int dfd, const char* path, int dflags, mode_t mode);   // darwin_fs.cpp
static int darwin_openat(int dfd, const char* path, int dflags, mode_t mode) { return darwin_openat_impl(dfd, path, dflags, mode); }

static DIR* darwin_opendir(const char* name) {
    if (!name) { errno = EFAULT; return nullptr; }
    std::string hp = resolve_guest_path(name);
    return opendir(hp.c_str());
}

static FILE* darwin_fopen(const char* path, const char* mode) {
    if (!path || !mode) { errno = EFAULT; return nullptr; }
    std::string hp = resolve_guest_path(path);
    return fopen(hp.c_str(), mode);
}

static int darwin_access(const char* path, int mode) {
    if (!path) { errno = EFAULT; return -1; }
    std::string hp = resolve_guest_path(path);
    return access(hp.c_str(), mode);
}

static ssize_t darwin_readlink(const char* path, char* buf, size_t bufsiz) {
    if (!path || !buf) { errno = EFAULT; return -1; }
    std::string hp = resolve_guest_path(path, false);
    return readlink(hp.c_str(), buf, bufsiz);
}

static int darwin_unlink(const char* path) {
    if (!path) { errno = EFAULT; return -1; }
    std::string hp = resolve_guest_path(path, false);
    int r = unlink(hp.c_str());
    if (r < 0 && errno == EISDIR) errno = EPERM;   // Darwin reports EPERM for a directory
    return r;
}

static int darwin_remove(const char* path) {
    if (!path) { errno = EFAULT; return -1; }
    std::string hp = resolve_guest_path(path, false);
    return remove(hp.c_str());
}

static int darwin_mkdir(const char* path, mode_t mode) {
    if (!path) { errno = EFAULT; return -1; }
    std::string hp = resolve_guest_path(path, false);
    return mkdir(hp.c_str(), mode);
}

static int darwin_rmdir(const char* path) {
    if (!path) { errno = EFAULT; return -1; }
    std::string hp = resolve_guest_path(path, false);
    return rmdir(hp.c_str());
}

static int darwin_rename(const char* oldpath, const char* newpath) {
    if (!oldpath || !newpath) { errno = EFAULT; return -1; }
    std::string ho = resolve_guest_path(oldpath, false);
    std::string hn = resolve_guest_path(newpath, false);
    return rename(ho.c_str(), hn.c_str());
}

static int darwin_chmod(const char* path, mode_t mode) {
    if (!path) { errno = EFAULT; return -1; }
    std::string hp = resolve_guest_path(path);
    return chmod(hp.c_str(), mode);
}

static int darwin_chown(const char* path, uid_t owner, gid_t group) {
    if (!path) { errno = EFAULT; return -1; }
    std::string hp = resolve_guest_path(path);
    return chown(hp.c_str(), owner, group);
}

static char* darwin_realpath(const char* path, char* resolved) {
    if (!path) { errno = EINVAL; return nullptr; }
    std::string out;
    if (!resolve_guest_realpath(path, out)) {
        return nullptr;
    }
    if (out.size() >= PATH_MAX) {
        errno = ENAMETOOLONG;
        return nullptr;
    }
    if (!resolved) {
        resolved = (char*)malloc(out.size() + 1);
        if (!resolved) {
            errno = ENOMEM;
            return nullptr;
        }
    }
    memcpy(resolved, out.c_str(), out.size() + 1);
    return resolved;
}

static char* darwin_getcwd(char* buf, size_t size) {
    char hbuf[PATH_MAX];
    if (!getcwd(hbuf, sizeof(hbuf))) return nullptr;
    std::string cwd = hbuf;
    if (!g_rootfs.empty() && cwd.rfind(g_rootfs, 0) == 0) {
        cwd = cwd.substr(g_rootfs.size());
        if (cwd.empty() || cwd[0] != '/') cwd = "/" + cwd;
    }
    if (!buf) {
        if (size == 0) size = cwd.size() + 1;
        buf = (char*)malloc(size);
        if (!buf) {
            errno = ENOMEM;
            return nullptr;
        }
    }
    if (cwd.size() + 1 > size) {
        errno = ERANGE;
        return nullptr;
    }
    memcpy(buf, cwd.c_str(), cwd.size() + 1);
    return buf;
}

// posix_spawn: posix_spawnattr_t / posix_spawn_file_actions_t are opaque pointers on Darwin; ours point to
// these. Signal sets are Darwin sigset_t (uint32, bit n-1 = Darwin signal n).
struct DarwinSpawnAttr {
    short psa_flags;
    pid_t psa_pgroup;
    uint32_t psa_sigmask;
    uint32_t psa_sigdefault;
    int psa_priority;
    size_t psa_binprefs_count;
    uint32_t* psa_binprefs;
};
enum : short {
    kSpawnResetIds = 0x1, kSpawnSetPgroup = 0x2, kSpawnSetSigDef = 0x4, kSpawnSetSigMask = 0x8,
    kSpawnSetExec = 0x40, kSpawnStartSuspended = 0x80, kSpawnSetSid = 0x400, kSpawnCloexecDefault = 0x4000,
};
struct DarwinSpawnAction {
    enum Kind { Open, Close, Dup2, Inherit, Chdir, Fchdir } kind;
    int fd, newfd, oflag;     // oflag: Linux O_* flags
    mode_t mode;
    std::string path;         // host path for Open/Chdir
};
struct DarwinSpawnActions { std::vector<DarwinSpawnAction> acts; };

static int darwin_posix_spawnattr_init(void** attrp) {
    if (!attrp) return EINVAL;
    auto* a = (DarwinSpawnAttr*)calloc(1, sizeof(DarwinSpawnAttr));
    if (!a) return ENOMEM;
    *attrp = a;
    return 0;
}

static int darwin_posix_spawnattr_destroy(void** attrp) {
    if (!attrp || !*attrp) return EINVAL;
    auto* a = (DarwinSpawnAttr*)*attrp;
    if (a->psa_binprefs) free(a->psa_binprefs);
    free(a);
    *attrp = nullptr;
    return 0;
}

static int darwin_posix_spawnattr_setflags(void** attrp, short flags) {
    if (!attrp || !*attrp) return EINVAL;
    auto* a = (DarwinSpawnAttr*)*attrp;
    a->psa_flags = flags;
    return 0;
}

static int darwin_posix_spawnattr_getflags(void** attrp, short* flags) {
    if (!attrp || !*attrp || !flags) return EINVAL;
    auto* a = (DarwinSpawnAttr*)*attrp;
    *flags = a->psa_flags;
    return 0;
}

static int darwin_posix_spawnattr_setbinpref_np(void** attrp, size_t count, const uint32_t* pref, size_t* ocount) {
    if (!attrp || !*attrp) return EINVAL;
    auto* a = (DarwinSpawnAttr*)*attrp;
    if (count > 0 && pref) {
        a->psa_binprefs = (uint32_t*)realloc(a->psa_binprefs, count * sizeof(uint32_t));
        if (a->psa_binprefs) {
            memcpy(a->psa_binprefs, pref, count * sizeof(uint32_t));
            a->psa_binprefs_count = count;
        }
    }
    if (ocount) *ocount = count;
    return 0;
}

static int darwin_posix_spawnattr_getbinpref_np(void** attrp, size_t count, uint32_t* pref, size_t* ocount) {
    if (!attrp || !*attrp) return EINVAL;
    auto* a = (DarwinSpawnAttr*)*attrp;
    size_t n = std::min(count, a->psa_binprefs_count);
    if (pref && n > 0 && a->psa_binprefs) {
        memcpy(pref, a->psa_binprefs, n * sizeof(uint32_t));
    }
    if (ocount) *ocount = n;
    return 0;
}

static int darwin_posix_spawnattr_setpgroup(void** attrp, pid_t pgroup) {
    if (!attrp || !*attrp) return EINVAL;
    ((DarwinSpawnAttr*)*attrp)->psa_pgroup = pgroup;
    return 0;
}
static int darwin_posix_spawnattr_getpgroup(void** attrp, pid_t* pgroup) {
    if (!attrp || !*attrp || !pgroup) return EINVAL;
    *pgroup = ((DarwinSpawnAttr*)*attrp)->psa_pgroup;
    return 0;
}
static int darwin_posix_spawnattr_setsigmask(void** attrp, const uint32_t* set) {
    if (!attrp || !*attrp || !set) return EINVAL;
    ((DarwinSpawnAttr*)*attrp)->psa_sigmask = *set;
    return 0;
}
static int darwin_posix_spawnattr_getsigmask(void** attrp, uint32_t* set) {
    if (!attrp || !*attrp || !set) return EINVAL;
    *set = ((DarwinSpawnAttr*)*attrp)->psa_sigmask;
    return 0;
}
static int darwin_posix_spawnattr_setsigdefault(void** attrp, const uint32_t* set) {
    if (!attrp || !*attrp || !set) return EINVAL;
    ((DarwinSpawnAttr*)*attrp)->psa_sigdefault = *set;
    return 0;
}
static int darwin_posix_spawnattr_getsigdefault(void** attrp, uint32_t* set) {
    if (!attrp || !*attrp || !set) return EINVAL;
    *set = ((DarwinSpawnAttr*)*attrp)->psa_sigdefault;
    return 0;
}

static int darwin_posix_spawn_file_actions_init(void** actp) {
    if (!actp) return EINVAL;
    *actp = new DarwinSpawnActions();
    return 0;
}

static int darwin_posix_spawn_file_actions_destroy(void** actp) {
    if (!actp || !*actp) return EINVAL;
    delete (DarwinSpawnActions*)*actp;
    *actp = nullptr;
    return 0;
}

static int spawn_add(void** actp, DarwinSpawnAction a) {
    if (!actp || !*actp) return EINVAL;
    if (a.fd < 0 && a.kind != DarwinSpawnAction::Chdir) return EBADF;
    if ((a.kind == DarwinSpawnAction::Dup2) && a.newfd < 0) return EBADF;
    ((DarwinSpawnActions*)*actp)->acts.push_back(std::move(a));
    return 0;
}
static int darwin_posix_spawn_file_actions_addclose(void** actp, int fd) {
    return spawn_add(actp, {DarwinSpawnAction::Close, fd, -1, 0, 0, {}});
}
static int darwin_posix_spawn_file_actions_adddup2(void** actp, int fd, int newfd) {
    return spawn_add(actp, {DarwinSpawnAction::Dup2, fd, newfd, 0, 0, {}});
}
static int darwin_posix_spawn_file_actions_addinherit_np(void** actp, int fd) {
    return spawn_add(actp, {DarwinSpawnAction::Inherit, fd, -1, 0, 0, {}});
}
static int darwin_posix_spawn_file_actions_addopen(void** actp, int fd, const char* path, int oflag, mode_t mode) {
    if (!path) return EINVAL;
    return spawn_add(actp, {DarwinSpawnAction::Open, fd, -1, darwin_open_flags_to_linux(oflag), mode, resolve_guest_path(path)});
}
static int darwin_posix_spawn_file_actions_addchdir_np(void** actp, const char* path) {
    if (!path) return EINVAL;
    return spawn_add(actp, {DarwinSpawnAction::Chdir, -1, -1, 0, 0, resolve_guest_path(path)});
}
static int darwin_posix_spawn_file_actions_addfchdir_np(void** actp, int fd) {
    return spawn_add(actp, {DarwinSpawnAction::Fchdir, fd, -1, 0, 0, {}});
}

// Runs in the child between fork and execve (or in-process for POSIX_SPAWN_SETEXEC): only syscalls.
static int spawn_apply(DarwinSpawnActions* fa, DarwinSpawnAttr* a) {
    short fl = a ? a->psa_flags : 0;
    if (fl & kSpawnSetSid) { if (setsid() < 0) return errno; }
    if (fl & kSpawnSetPgroup) { if (setpgid(0, a->psa_pgroup) < 0) return errno; }
    if (fl & kSpawnResetIds) { if (setegid(getgid()) < 0 || seteuid(getuid()) < 0) return errno; }
    if (fl & kSpawnSetSigDef) {
        for (int d = 1; d <= 31; d++) {
            int l = darwin_to_linux_sig(d);
            if (!((a->psa_sigdefault >> (d - 1)) & 1) || l <= 0 || l == SIGKILL || l == SIGSTOP) continue;
            struct sigaction sa; memset(&sa, 0, sizeof sa); sa.sa_handler = SIG_DFL;
            sigaction(l, &sa, nullptr);
        }
    }
    // fds the child keeps under POSIX_SPAWN_CLOEXEC_DEFAULT: those the actions produce or inherit
    uint64_t keep[1024 / 64] = {};
    auto mark = [&](int fd) { if (fd >= 0 && fd < 1024) keep[fd / 64] |= 1ull << (fd % 64); };
    if (fa) {
        for (const DarwinSpawnAction& x : fa->acts) {
            switch (x.kind) {
            case DarwinSpawnAction::Open: {
                int t = open(x.path.c_str(), x.oflag, x.mode);
                if (t < 0) return errno;
                if (t != x.fd) {
                    if (dup2(t, x.fd) < 0) { int e = errno; close(t); return e; }
                    close(t);
                }
                mark(x.fd);
                break;
            }
            case DarwinSpawnAction::Close:
                if (close(x.fd) < 0 && errno != EBADF) return errno;
                break;
            case DarwinSpawnAction::Dup2:
                if (x.fd == x.newfd) {   // POSIX 2024: dup2 onto itself clears FD_CLOEXEC
                    int f = fcntl(x.fd, F_GETFD);
                    if (f < 0 || fcntl(x.fd, F_SETFD, f & ~FD_CLOEXEC) < 0) return errno;
                } else if (dup2(x.fd, x.newfd) < 0) return errno;
                mark(x.newfd);
                break;
            case DarwinSpawnAction::Inherit: {
                int f = fcntl(x.fd, F_GETFD);
                if (f < 0 || fcntl(x.fd, F_SETFD, f & ~FD_CLOEXEC) < 0) return errno;
                mark(x.fd);
                break;
            }
            case DarwinSpawnAction::Chdir:
                if (chdir(x.path.c_str()) < 0) return errno;
                break;
            case DarwinSpawnAction::Fchdir:
                if (fchdir(x.fd) < 0) return errno;
                break;
            }
        }
    }
    if (fl & kSpawnCloexecDefault) {
        // guest fds only: XEF's internal fds (>= 1000) are CLOEXEC already
        for (int fd = 0; fd < 1000; fd++) {
            if (fd < 1024 && (keep[fd / 64] >> (fd % 64)) & 1) continue;
            int f = fcntl(fd, F_GETFD);
            if (f >= 0 && !(f & FD_CLOEXEC)) fcntl(fd, F_SETFD, f | FD_CLOEXEC);
        }
    }
    if (fl & kSpawnSetSigMask) {
        u64 lm = darwin_mask_to_linux(a->psa_sigmask);
        syscall(SYS_rt_sigprocmask, SIG_SETMASK, &lm, nullptr, 8);
    }
    return 0;
}

static int darwin_posix_spawn(pid_t* pid, const char* path, void* file_actions, void* attrp, char* const argv[], char* const envp[]) {
    if (!path || !path[0]) return ENOENT;
    std::string hp = resolve_guest_path(path);
    std::string target_path = (access(hp.c_str(), F_OK) == 0) ? hp : path;
    if (access(target_path.c_str(), F_OK) != 0) return ENOENT;
    if (access(target_path.c_str(), X_OK) != 0) return EACCES;

    int fd = open(target_path.c_str(), O_RDONLY | O_CLOEXEC);
    uint8_t hdr[24] = {0};
    ssize_t n = 0;
    if (fd >= 0) {
        n = read(fd, hdr, sizeof(hdr));
        close(fd);
    }

    bool is_x86_64 = false;
    if (n >= 20 && memcmp(hdr, "\x7f" "ELF", 4) == 0) {
        uint16_t machine = (uint16_t)(hdr[18] | (hdr[19] << 8));
        if (machine == 62) is_x86_64 = true;
    }

    char self[4096];
    ssize_t sl = readlink("/proc/self/exe", self, sizeof(self) - 1);
    if (sl < 0) return errno;
    self[sl] = '\0';

    std::string exe_to_run = is_x86_64 ? target_path : std::string(self);

    std::vector<std::string> args;
    if (!is_x86_64) {
        args.push_back(self);
        if (!g_rootfs.empty()) {
            args.push_back("-L");
            args.push_back(g_rootfs);
        }
        if (argv && argv[0] && strcmp(argv[0], path) != 0) {
            args.push_back("--argv0");
            args.push_back(argv[0]);
        }
        args.push_back(path);
    } else {
        args.push_back((argv && argv[0]) ? argv[0] : target_path);
    }

    if (argv && argv[0]) {
        for (int i = 1; argv[i]; i++) {
            args.push_back(argv[i]);
        }
    }

    std::vector<char*> c_argv;
    for (auto& a : args) c_argv.push_back((char*)a.c_str());
    c_argv.push_back(nullptr);

    std::vector<char*> c_envp;
    for (char* const* e = envp; e && *e; e++) {
        c_envp.push_back(*e);
    }
    std::string root_env;
    if (!g_rootfs.empty() && !is_x86_64) {
        root_env = "XEF_ROOTFS=" + g_rootfs;
        c_envp.push_back((char*)root_env.c_str());
    }
    c_envp.push_back(nullptr);

    DarwinSpawnAttr* a = attrp ? *(DarwinSpawnAttr**)attrp : nullptr;
    DarwinSpawnActions* fa = file_actions ? *(DarwinSpawnActions**)file_actions : nullptr;

    if (a && (a->psa_flags & kSpawnSetExec)) {
        if (int e = spawn_apply(fa, a)) return e;
        execve(exe_to_run.c_str(), c_argv.data(), c_envp.data());
        return errno;
    }

    // the child reports a failed action / execve through a CLOEXEC pipe (posix_spawn returns it)
    int ep[2];
    if (pipe2(ep, O_CLOEXEC) < 0) return errno;
    pid_t child = fork();
    if (child < 0) { int e = errno; close(ep[0]); close(ep[1]); return e; }
    if (child == 0) {
        close(ep[0]);
        if (ep[1] < 1000) {   // keep the report pipe out of the way of dup2 targets
            int hi = fcntl(ep[1], F_DUPFD_CLOEXEC, 1000);
            if (hi >= 0) { close(ep[1]); ep[1] = hi; }
        }
        int e = spawn_apply(fa, a);
        if (!e) {
            if (a && (a->psa_flags & kSpawnStartSuspended)) raise(SIGSTOP);
            execve(exe_to_run.c_str(), c_argv.data(), c_envp.data());
            e = errno;
        }
        ssize_t w = write(ep[1], &e, sizeof e);
        (void)w;
        _exit(127);
    }
    close(ep[1]);
    int ce = 0;
    ssize_t r;
    do r = read(ep[0], &ce, sizeof ce); while (r < 0 && errno == EINTR);
    close(ep[0]);
    if (r == (ssize_t)sizeof ce) {
        waitpid(child, nullptr, 0);
        return ce;
    }
    if (pid) *pid = child;
    return 0;
}


// exec family: process_execve (os/thread.cpp) runs Mach-O / arm64 ELF images under a fresh XEF, x86-64 natively and
// follows #! lines; on failure it returns -errno and the caller keeps running.
static int darwin_execve(const char* path, char* const argv[], char* const envp[]) {
    if (!path) { errno = EFAULT; return -1; }
    i64 r = process_execve(tls_thread ? tls_thread->st : nullptr, (u64)(uintptr_t)path, (u64)(uintptr_t)argv,
                           (u64)(uintptr_t)(envp ? envp : environ));
    errno = (int)-r;
    return -1;
}
static int darwin_execv(const char* path, char* const argv[]) { return darwin_execve(path, argv, environ); }
// execvP: search `search_path` like execvp; ENOEXEC (no #!, not a binary) runs the file with /bin/sh
static int darwin_execvP(const char* file, const char* search_path, char* const argv[]) {
    if (!file || !*file) { errno = ENOENT; return -1; }
    auto try_one = [&](const char* p) {
        darwin_execve(p, argv, environ);
        if (errno == ENOEXEC) {
            std::vector<char*> av{(char*)"sh", (char*)p};
            for (int i = 1; argv && argv[0] && argv[i]; i++) av.push_back(argv[i]);
            av.push_back(nullptr);
            darwin_execve("/bin/sh", av.data(), environ);
            errno = ENOEXEC;
        }
    };
    if (strchr(file, '/')) { try_one(file); return -1; }
    std::string sp = search_path ? search_path : "/usr/bin:/bin";
    bool eacces = false;
    size_t start = 0;
    for (;;) {
        size_t end = sp.find(':', start);
        std::string dir = sp.substr(start, end == std::string::npos ? std::string::npos : end - start);
        std::string cand = (dir.empty() ? std::string(".") : dir) + "/" + file;
        try_one(cand.c_str());
        if (errno == EACCES) eacces = true;
        else if (errno != ENOENT && errno != ENOTDIR && errno != ELOOP && errno != ENAMETOOLONG) return -1;
        if (end == std::string::npos) break;
        start = end + 1;
    }
    errno = eacces ? EACCES : ENOENT;
    return -1;
}
static int darwin_execvp(const char* file, char* const argv[]) {
    const char* path = getenv("PATH");
    return darwin_execvP(file, path ? path : "/usr/bin:/bin:/usr/sbin:/sbin", argv);
}
// execl/execlp(path, arg0, ...) and execle(path, arg0, ..., NULL, envp): variadic arguments come from the stack
static std::vector<char*> exec_list(const char* arg0, const uint64_t* ap, const uint64_t** after) {
    std::vector<char*> av{(char*)arg0};
    if (arg0) { while (*ap) av.push_back((char*)(uintptr_t)*ap++); }
    if (after) *after = arg0 ? ap + 1 : ap;
    av.push_back(nullptr);
    return av;
}
static int darwin_execl(const char* path, const char* arg0, const uint64_t* ap) {
    std::vector<char*> av = exec_list(arg0, ap, nullptr);
    return darwin_execve(path, av.data(), environ);
}
static int darwin_execlp(const char* file, const char* arg0, const uint64_t* ap) {
    std::vector<char*> av = exec_list(arg0, ap, nullptr);
    return darwin_execvp(file, av.data());
}
static int darwin_execle(const char* path, const char* arg0, const uint64_t* ap) {
    const uint64_t* rest;
    std::vector<char*> av = exec_list(arg0, ap, &rest);
    return darwin_execve(path, av.data(), (char* const*)(uintptr_t)*rest);
}

// sh -c for popen/system: the rootfs' /bin/sh when there is one (a Mach-O shell under XEF sees guest paths and
// execs guest programs), else the host's. child_in/child_out become the child's stdin/stdout (-1: inherited).
pid_t darwin_spawn_shell(const char* cmd, int child_in, int child_out) {
    DarwinSpawnActions fa;
    if (child_in >= 0) fa.acts.push_back({DarwinSpawnAction::Dup2, child_in, 0, 0, 0, {}});
    if (child_out >= 0) fa.acts.push_back({DarwinSpawnAction::Dup2, child_out, 1, 0, 0, {}});
    DarwinSpawnActions* fap = &fa;
    char* argv[] = {(char*)"sh", (char*)"-c", (char*)cmd, nullptr};
    pid_t pid;
    int e = darwin_posix_spawn(&pid, "/bin/sh", &fap, nullptr, argv, environ);
    if (e) { errno = e; return -1; }
    return pid;
}
static int darwin_system(const char* cmd) {
    if (!cmd) return 1;   // a shell is available
    pid_t p = darwin_spawn_shell(cmd, -1, -1);
    if (p < 0) return -1;
    int st;
    while (waitpid(p, &st, 0) < 0) if (errno != EINTR) return -1;
    return st;
}

static int darwin_posix_spawnp(pid_t* pid, const char* file, void* file_actions, void* attrp, char* const argv[], char* const envp[]) {
    if (!file || !file[0]) return ENOENT;
    if (strchr(file, '/')) {
        return darwin_posix_spawn(pid, file, file_actions, attrp, argv, envp);
    }
    // Search in PATH
    const char* path_env = getenv("PATH");
    if (!path_env) path_env = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin";
    std::string pstr = path_env;
    size_t start = 0;
    while (start < pstr.size()) {
        size_t end = pstr.find(':', start);
        if (end == std::string::npos) end = pstr.size();
        std::string cand = pstr.substr(start, end - start) + "/" + file;
        std::string hcand = resolve_guest_path(cand.c_str());
        if (access(hcand.c_str(), X_OK) == 0 || access(cand.c_str(), X_OK) == 0) {
            return darwin_posix_spawn(pid, cand.c_str(), file_actions, attrp, argv, envp);
        }
        start = end + 1;
    }
    return ENOENT;
}



static int darwin_readdir_r(DIR* dirp, darwin_dirent* entry, darwin_dirent** result) {
    if (!dirp || !entry) {
        if (result) *result = nullptr;
        return EINVAL;
    }
    errno = 0;
    struct dirent* host_res = readdir(dirp);
    if (!host_res) {
        if (result) *result = nullptr;
        return errno;
    }
    entry->d_ino = host_res->d_ino;
    entry->d_seekoff = host_res->d_off;
    size_t nlen = strlen(host_res->d_name);
    entry->d_namlen = (uint16_t)nlen;
    entry->d_type = host_res->d_type;
    entry->d_reclen = (uint16_t)(sizeof(darwin_dirent) - 1024 + nlen + 1);
    memcpy(entry->d_name, host_res->d_name, nlen + 1);
    if (result) *result = entry;
    return 0;
}

static thread_local darwin_dirent tls_darwin_dirent;
static darwin_dirent* darwin_readdir(DIR* dirp) {
    darwin_dirent* res = nullptr;
    if (darwin_readdir_r(dirp, &tls_darwin_dirent, &res) == 0 && res != nullptr) {
        return res;
    }
    return nullptr;
}

// ---- nftw / scandir with guest callbacks ------------------------------------------------------------
static thread_local u64 tl_nftw_cb = 0;
static int nftw_tramp(const char* path, const struct stat* sb, int typeflag, struct FTW* ftwbuf) {
    static const int map[] = {0, 1, 2, 4 /*NS*/, 5 /*SL*/, 3 /*DP*/, 6 /*SLN*/};   // Linux -> Darwin
    darwin_stat64 ds;
    convert_stat_to_darwin(*sb, &ds);
    struct { int base; int level; } fb = {ftwbuf->base, ftwbuf->level};
    u64 a[4] = {(u64)(uintptr_t)path, (u64)(uintptr_t)&ds, (u64)map[typeflag < 7 ? typeflag : 0], (u64)(uintptr_t)&fb};
    return (int)guest_call(tl_nftw_cb, 4, a);
}
static int darwin_nftw(const char* path, u64 cb, int nopenfd, int flags) {
    int lf = 0;
    if (flags & 1) lf |= FTW_PHYS;
    if (flags & 2) lf |= FTW_MOUNT;
    if (flags & 4) lf |= FTW_DEPTH;
    if (flags & 8) lf |= FTW_CHDIR;
    u64 save = tl_nftw_cb; tl_nftw_cb = cb;
    int r = nftw(path, nftw_tramp, nopenfd, lf);
    tl_nftw_cb = save;
    return r;
}
struct DarwinDirent { uint64_t d_ino; uint64_t d_seekoff; uint16_t d_reclen; uint16_t d_namlen; uint8_t d_type; char d_name[1024]; };
static int darwin_scandir(const char* dir, DarwinDirent*** list, u64 filter, u64 compar) {
    DIR* d = opendir(dir);
    if (!d) return -1;
    std::vector<DarwinDirent*> v;
    while (struct dirent* e = readdir(d)) {
        DarwinDirent* de = (DarwinDirent*)calloc(1, sizeof(DarwinDirent));
        de->d_ino = e->d_ino; de->d_type = e->d_type;
        size_t n = strnlen(e->d_name, 1023);
        memcpy(de->d_name, e->d_name, n);
        de->d_namlen = (uint16_t)n;
        de->d_reclen = (uint16_t)sizeof(DarwinDirent);
        if (filter) {
            u64 a[1] = {(u64)(uintptr_t)de};
            if (!guest_call(filter, 1, a)) { free(de); continue; }
        }
        v.push_back(de);
    }
    closedir(d);
    if (compar) {
        // insertion-style merge using the guest comparator on pointers-to-pointers
        std::stable_sort(v.begin(), v.end(), [&](DarwinDirent* x, DarwinDirent* y) {
            DarwinDirent* px = x; DarwinDirent* py = y;
            u64 a[2] = {(u64)(uintptr_t)&px, (u64)(uintptr_t)&py};
            return (int)guest_call(compar, 2, a) < 0;
        });
    }
    DarwinDirent** out = (DarwinDirent**)malloc((v.size() + 1) * sizeof(void*));
    for (size_t i = 0; i < v.size(); i++) out[i] = v[i];
    out[v.size()] = nullptr;
    *list = out;
    return (int)v.size();
}
// alphasort / versionsort for scandir (Darwin dirent layout)
static int darwin_alphasort(const DarwinDirent** a, const DarwinDirent** b) { return strcoll((*a)->d_name, (*b)->d_name); }

// Grand Central Dispatch (GCD) Semaphores
struct DarwinSemaphore {
    std::mutex mtx;
    std::condition_variable cv;
    long count = 0;
};

static void* darwin_dispatch_semaphore_create(long value) {
    auto* s = new DarwinSemaphore();
    s->count = value;
    return s;
}

static long darwin_dispatch_semaphore_signal(DarwinSemaphore* s) {
    if (!s) return 0;
    std::unique_lock<std::mutex> lk(s->mtx);
    s->count++;
    lk.unlock();
    s->cv.notify_one();
    return 0;
}

#define DISPATCH_TIME_NOW 0ull
#define DISPATCH_TIME_FOREVER (~0ull)

static uint64_t darwin_dispatch_time(uint64_t when, int64_t delta) {
    if (when == DISPATCH_TIME_FOREVER) return DISPATCH_TIME_FOREVER;
    if (when == DISPATCH_TIME_NOW) {
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        uint64_t now_ns = (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
        return (delta < 0 && (uint64_t)(-delta) > now_ns) ? 0 : now_ns + delta;
    }
    return when + delta;
}

static long darwin_dispatch_semaphore_wait(DarwinSemaphore* s, uint64_t timeout) {
    if (!s) return 0;
    std::unique_lock<std::mutex> lk(s->mtx);
    if (timeout == DISPATCH_TIME_FOREVER) {
        s->cv.wait(lk, [&] { return s->count > 0; });
        s->count--;
        return 0;
    }
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    uint64_t now_ns = (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
    if (timeout <= now_ns) {
        if (s->count > 0) {
            s->count--;
            return 0;
        }
        return 1; // timeout
    }
    uint64_t dur_ns = timeout - now_ns;
    if (s->cv.wait_for(lk, std::chrono::nanoseconds(dur_ns), [&] { return s->count > 0; })) {
        s->count--;
        return 0;
    }
    return 1; // timeout
}

static void darwin_dispatch_release(void* obj) {
    (void)obj;
}

// C library functions glibc has and macOS's libSystem does not: the HLE resolver would find them on the host, but a
// program probing with dlsym (HotSpot: pthread_condattr_setclock) must see what macOS shows - nothing.
static bool not_in_libsystem(const char* s) {
    static const char* const kNames[] = {
        "pthread_condattr_setclock", "pthread_condattr_getclock", "pthread_getcpuclockid", "pthread_setaffinity_np",
        "pthread_getaffinity_np", "pthread_tryjoin_np", "pthread_timedjoin_np", "pthread_yield", "clock_nanosleep",
        "accept4", "epoll_create", "epoll_create1", "epoll_ctl", "epoll_wait", "epoll_pwait", "eventfd",
        "signalfd", "timerfd_create", "timerfd_settime", "timerfd_gettime", "inotify_init", "inotify_init1",
        "inotify_add_watch", "inotify_rm_watch", "prctl", "getauxval", "gettid", "sched_getcpu", "memrchr", "rawmemchr",
        "mempcpy", "secure_getenv", "get_nprocs", "get_nprocs_conf", "sysinfo", "mallinfo", "mallinfo2", "malloc_trim",
        "malloc_usable_size", "memfd_create", "copy_file_range", "splice", "tee", "vmsplice", "fallocate", "posix_fallocate",
        "sync_file_range", "syncfs", "statx", "renameat2", "getrandom", "gnu_get_libc_version", "backtrace_symbols_fd",
        "__libc_start_main", "dl_iterate_phdr", "open64", "fopen64", "stat64", "lstat64", "fstat64", "lseek64", "mmap64",
        "pread64", "pwrite64", "ftruncate64", "truncate64", "readdir64", "getrlimit64", "setrlimit64"};
    for (const char* n : kNames) if (!strcmp(s, n)) return true;
    return false;
}

static void* darwin_dlsym(void* handle, const char* symbol) {
    if (!symbol || !symbol[0]) return nullptr;
    std::string prefixed = std::string("_") + symbol;
    XEF_LOG(2, "darwin_dlsym(handle=%p, symbol='%s')", handle, symbol);
    uint64_t addr = 0;
    auto& imgs = dyld_images();
    bool is_image = false;
    for (MachImage* im : imgs) is_image |= ((void*)im == handle);
    // dlopen(NULL) hands out the main executable's image; dyld searches every global image for it (OSG looks
    // gl* extension entry points up this way), so it behaves like RTLD_DEFAULT here
    if (is_image && !imgs.empty() && handle == (void*)imgs[0]) is_image = false;
    if (is_image) addr = dyld_image_lookup((MachImage*)handle, prefixed.c_str());
    else addr = dyld_flat_lookup(prefixed.c_str());
    // The OpenGL.framework image is empty: its gl*/CGL* exports are supplied by the host-GL bridge (darwin_gl.cpp),
    // so a dlsym / CFBundleGetFunctionPointerForName on that image (GLFW's NSGL getProcAddress) resolves through it.
    if (!addr && is_image && ((MachImage*)handle)->path.find("/OpenGL.framework/") != std::string::npos)
        addr = darwin_hle_resolve_symbol(prefixed.c_str(), true);
    if (!addr && !is_image && !not_in_libsystem(symbol)) {
        addr = darwin_hle_resolve_symbol(prefixed.c_str(), true);
        if (!addr) addr = darwin_hle_resolve_symbol(symbol, true);
    }
    XEF_LOG(2, "darwin_dlsym('%s') -> %p", symbol, (void*)addr);
    return (void*)(uintptr_t)addr;
}

static std::string g_dlerror;
static void* darwin_dlopen(const char* path, int mode) {
    (void)mode;
    MachImage* im = dyld_dlopen(path);
    if (!im && path) {
        g_dlerror = std::string("dlopen(") + path + "): image not found";
        return nullptr;
    }
    return im;
}
static int darwin_dlclose(void*) { return 0; }
static const char* darwin_dlerror() {
    if (g_dlerror.empty()) return nullptr;
    static thread_local std::string cur;
    cur = g_dlerror;
    g_dlerror.clear();
    return cur.c_str();
}

struct DarwinDlInfo { const char* fname; void* fbase; const char* sname; void* saddr; };
static int darwin_dladdr(const void* addr, DarwinDlInfo* info) {
    MachImage* im = dyld_image_containing((uint64_t)(uintptr_t)addr);
    if (!im || !info) return 0;
    info->fname = im->path.c_str();
    info->fbase = (void*)(uintptr_t)im->header;
    info->sname = nullptr;
    info->saddr = nullptr;
    return 1;
}


// ---- sorting / searching with guest comparators ---------------------------------------------
static thread_local u64 tl_cmp_fn = 0, tl_cmp_thunk = 0;
static int cmp_guest2(const void* a, const void* b) {
    u64 args[2] = {(u64)(uintptr_t)a, (u64)(uintptr_t)b};
    return (int)guest_call(tl_cmp_fn, 2, args);
}
static int cmp_guest3(const void* a, const void* b) {
    u64 args[3] = {tl_cmp_thunk, (u64)(uintptr_t)a, (u64)(uintptr_t)b};
    return (int)guest_call(tl_cmp_fn, 3, args);
}
static void darwin_qsort(void* base, size_t n, size_t size, u64 cmp) {
    u64 sf = tl_cmp_fn; tl_cmp_fn = cmp;
    qsort(base, n, size, cmp_guest2);
    tl_cmp_fn = sf;
}
// Darwin: qsort_r(base, n, size, thunk, cmp(thunk, a, b))
static void darwin_qsort_r(void* base, size_t n, size_t size, u64 thunk, u64 cmp) {
    u64 sf = tl_cmp_fn, st = tl_cmp_thunk; tl_cmp_fn = cmp; tl_cmp_thunk = thunk;
    qsort(base, n, size, cmp_guest3);
    tl_cmp_fn = sf; tl_cmp_thunk = st;
}
static void* darwin_bsearch(const void* key, const void* base, size_t n, size_t size, u64 cmp) {
    u64 sf = tl_cmp_fn; tl_cmp_fn = cmp;
    void* r = bsearch(key, base, n, size, cmp_guest2);
    tl_cmp_fn = sf;
    return r;
}
// tsearch family: glibc's tree nodes also start with the key pointer, which is all callers may read
static void* darwin_tsearch(const void* key, void** root, u64 cmp) {
    u64 sf = tl_cmp_fn; tl_cmp_fn = cmp;
    void* r = tsearch(key, root, cmp_guest2);
    tl_cmp_fn = sf;
    return r;
}
static void* darwin_tfind(const void* key, void* const* root, u64 cmp) {
    u64 sf = tl_cmp_fn; tl_cmp_fn = cmp;
    void* r = tfind(key, root, cmp_guest2);
    tl_cmp_fn = sf;
    return r;
}
static void* darwin_tdelete(const void* key, void** root, u64 cmp) {
    u64 sf = tl_cmp_fn; tl_cmp_fn = cmp;
    void* r = tdelete(key, root, cmp_guest2);
    tl_cmp_fn = sf;
    return r;
}
static thread_local u64 tl_walk_fn;
static void walk_guest(const void* node, VISIT v, int depth) {   // preorder/postorder/endorder/leaf: 0..3 on both
    u64 args[3] = {(u64)(uintptr_t)node, (u64)v, (u64)depth};
    guest_call(tl_walk_fn, 3, args);
}
static void darwin_twalk(const void* root, u64 fn) {
    u64 sf = tl_walk_fn; tl_walk_fn = fn;
    twalk(root, walk_guest);
    tl_walk_fn = sf;
}
static void* darwin_lfind(const void* key, const void* base, size_t* n, size_t size, u64 cmp) {
    u64 sf = tl_cmp_fn; tl_cmp_fn = cmp;
    void* r = lfind(key, base, n, size, cmp_guest2);
    tl_cmp_fn = sf;
    return r;
}
static void* darwin_lsearch(const void* key, void* base, size_t* n, size_t size, u64 cmp) {
    u64 sf = tl_cmp_fn; tl_cmp_fn = cmp;
    void* r = lsearch(key, base, n, size, cmp_guest2);
    tl_cmp_fn = sf;
    return r;
}
// Blocks variants (qsort_b, bsearch_b, ...): the comparator is a block; invoke(block, a, b) at offset 16
static thread_local u64 tl_cmp_block;
static int cmp_block(const void* a, const void* b) {
    u64 args[3] = {tl_cmp_block, (u64)(uintptr_t)a, (u64)(uintptr_t)b};
    return (int)guest_call(*(u64*)(uintptr_t)(tl_cmp_block + 16), 3, args);
}
static void darwin_qsort_b(void* base, size_t n, size_t size, u64 block) {
    u64 sb = tl_cmp_block; tl_cmp_block = block;
    qsort(base, n, size, cmp_block);
    tl_cmp_block = sb;
}
static void* darwin_bsearch_b(const void* key, const void* base, size_t n, size_t size, u64 block) {
    u64 sb = tl_cmp_block; tl_cmp_block = block;
    void* r = bsearch(key, base, n, size, cmp_block);
    tl_cmp_block = sb;
    return r;
}
static int darwin_stable_sort(void* base, size_t n, size_t size, u64 cmp);
static int darwin_stable_sort_b(void* base, size_t n, size_t size, u64 block);
// mergesort/heapsort/radixsort do not exist in glibc: a stable insertion-merge on a copy
static int darwin_stable_sort(void* base, size_t n, size_t size, u64 cmp) {
    if (n < 2) return 0;
    u64 sf = tl_cmp_fn; tl_cmp_fn = cmp;
    std::vector<uint8_t> tmp(n * size);
    uint8_t* a = (uint8_t*)base;
    for (size_t width = 1; width < n; width *= 2) {
        for (size_t lo = 0; lo < n; lo += 2 * width) {
            size_t mid = std::min(lo + width, n), hi = std::min(lo + 2 * width, n);
            size_t i = lo, j = mid, k = lo;
            while (i < mid && j < hi)
                memcpy(&tmp[(k++) * size], cmp_guest2(a + j * size, a + i * size) < 0 ? a + (j++) * size : a + (i++) * size, size);
            while (i < mid) memcpy(&tmp[(k++) * size], a + (i++) * size, size);
            while (j < hi) memcpy(&tmp[(k++) * size], a + (j++) * size, size);
        }
        memcpy(a, tmp.data(), n * size);
    }
    tl_cmp_fn = sf;
    return 0;
}
static int darwin_stable_sort_b(void* base, size_t n, size_t size, u64 block) {
    if (n < 2) return 0;
    u64 sb = tl_cmp_block; tl_cmp_block = block;
    std::vector<uint8_t> tmp(n * size);
    uint8_t* a = (uint8_t*)base;
    for (size_t width = 1; width < n; width *= 2) {
        for (size_t lo = 0; lo < n; lo += 2 * width) {
            size_t mid = std::min(lo + width, n), hi = std::min(lo + 2 * width, n);
            size_t i = lo, j = mid, k = lo;
            while (i < mid && j < hi)
                memcpy(&tmp[(k++) * size], cmp_block(a + j * size, a + i * size) < 0 ? a + (j++) * size : a + (i++) * size, size);
            while (i < mid) memcpy(&tmp[(k++) * size], a + (i++) * size, size);
            while (j < hi) memcpy(&tmp[(k++) * size], a + (j++) * size, size);
        }
        memcpy(a, tmp.data(), n * size);
    }
    tl_cmp_block = sb;
    return 0;
}


// ---- libSystem functions with stack-passed variadics (Darwin arm64) and xlocale shims --------
static int darwin_snprintf_l(char* str, size_t size, void* loc, const char* format, const uint64_t* ap) {
    (void)loc;
    return darwin_vsnprintf(str, size, format, ap);
}
static int darwin_sprintf(char* str, const char* format, const uint64_t* ap) {
    return darwin_vsnprintf(str, (size_t)1 << 30, format, ap);
}
static int darwin_asprintf(char** out, const char* format, const uint64_t* ap) {
    int n = darwin_vsnprintf(nullptr, 0, format, ap);
    if (n < 0) return n;
    *out = (char*)malloc((size_t)n + 1);
    return darwin_vsnprintf(*out, (size_t)n + 1, format, ap);
}
static int darwin_asprintf_l(char** out, void* loc, const char* format, const uint64_t* ap) {
    (void)loc;
    return darwin_asprintf(out, format, ap);
}
static int darwin_dprintf(int fd, const char* format, const uint64_t* ap) {
    int n = darwin_vsnprintf(nullptr, 0, format, ap);
    if (n < 0) return n;
    std::vector<char> buf((size_t)n + 1);
    darwin_vsnprintf(buf.data(), buf.size(), format, ap);
    return (int)write(fd, buf.data(), (size_t)n);
}
typedef int (*sscanf8_t)(const char*, const char*, void*, void*, void*, void*, void*, void*, void*, void*);
static int darwin_sscanf(const char* str, const char* format, const uint64_t* ap) {
    return ((sscanf8_t)&sscanf)(str, format, (void*)ap[0], (void*)ap[1], (void*)ap[2], (void*)ap[3],
                                (void*)ap[4], (void*)ap[5], (void*)ap[6], (void*)ap[7]);
}
static int darwin_sscanf_l(const char* str, void* loc, const char* format, const uint64_t* ap) {
    (void)loc;
    return darwin_sscanf(str, format, ap);
}
typedef int (*fscanf8_t)(FILE*, const char*, void*, void*, void*, void*, void*, void*, void*, void*);
static int darwin_fscanf(FILE* gf, const char* format, const uint64_t* ap) {
    FILE* f = darwin_stdio_host(gf);
    return ((fscanf8_t)&fscanf)(f, format, (void*)ap[0], (void*)ap[1], (void*)ap[2], (void*)ap[3],
                                (void*)ap[4], (void*)ap[5], (void*)ap[6], (void*)ap[7]);
}

static int darwin_vasprintf(char** out, const char* format, const uint64_t* ap) { return darwin_asprintf(out, format, ap); }
static int darwin_vsprintf(char* str, const char* format, const uint64_t* ap) { return darwin_sprintf(str, format, ap); }
static int darwin_vprintf(const char* format, const uint64_t* ap) { return darwin_vfprintf(stdout, format, ap); }
static int darwin_vdprintf(int fd, const char* format, const uint64_t* ap) { return darwin_dprintf(fd, format, ap); }
// Apple's fortified (_chk) variants: the object-size argument is ignored
static size_t darwin_strlcpy_impl(char* d, const char* s, size_t n) {
    size_t l = strlen(s);
    if (n) { size_t c = l >= n ? n - 1 : l; memcpy(d, s, c); d[c] = 0; }
    return l;
}
static size_t darwin_strlcat_impl(char* d, const char* s, size_t n) {
    size_t dl = strnlen(d, n), sl = strlen(s);
    if (dl == n) return n + sl;
    size_t c = std::min(sl, n - dl - 1);
    memcpy(d + dl, s, c); d[dl + c] = 0;
    return dl + sl;
}
static void darwin_report_null(const char* fn) {
    ThreadCtx* t = tls_thread;
    u64 lr = t ? t->st->x[30] : 0;
    MachImage* im = dyld_image_containing(lr);
    fprintf(stderr, "xef-osx: %s(NULL) called from %s+%#lx\n", fn, im ? im->path.c_str() : "?", (unsigned long)(im ? lr - im->header : lr));
}
static size_t darwin_strlcpy_chk(char* d, const char* s, size_t n, size_t) { if (!s) { darwin_report_null("strlcpy"); return 0; } return darwin_strlcpy_impl(d, s, n); }
static size_t darwin_strlcat_chk(char* d, const char* s, size_t n, size_t) { return darwin_strlcat_impl(d, s, n); }
static char* darwin_strcpy_chk(char* d, const char* s, size_t) { return strcpy(d, s); }
static char* darwin_stpcpy_chk(char* d, const char* s, size_t) { return stpcpy(d, s); }
static char* darwin_strcat_chk(char* d, const char* s, size_t) { return strcat(d, s); }
static char* darwin_strncpy_chk(char* d, const char* s, size_t n, size_t) { return strncpy(d, s, n); }
static char* darwin_stpncpy_chk(char* d, const char* s, size_t n, size_t) { return stpncpy(d, s, n); }
static char* darwin_strncat_chk(char* d, const char* s, size_t n, size_t) { return strncat(d, s, n); }
static void* darwin_memmove_chk(void* d, const void* s, size_t n, size_t) { return memmove(d, s, n); }
static void* darwin_memset_chk(void* d, int c, size_t n, size_t) { return memset(d, c, n); }
static int darwin_snprintf_chk(char* s, size_t n, int, size_t, const char* fmt, const uint64_t* ap) { return darwin_vsnprintf(s, n, fmt, ap); }
static int darwin_sprintf_chk(char* s, int, size_t, const char* fmt, const uint64_t* ap) { return darwin_vsnprintf(s, (size_t)1 << 30, fmt, ap); }
static int darwin_vsnprintf_chk(char* s, size_t n, int, size_t, const char* fmt, const uint64_t* ap) { return darwin_vsnprintf(s, n, fmt, ap); }
static int darwin_vsprintf_chk(char* s, int, size_t, const char* fmt, const uint64_t* ap) { return darwin_vsnprintf(s, (size_t)1 << 30, fmt, ap); }
static int darwin_fprintf_chk(FILE* f, int, const char* fmt, const uint64_t* ap) { return darwin_vfprintf(f, fmt, ap); }
static int darwin_printf_chk(int, const char* fmt, const uint64_t* ap) { return darwin_vfprintf(stdout, fmt, ap); }
static int darwin_vfprintf_chk(FILE* f, int, const char* fmt, const uint64_t* ap) { return darwin_vfprintf(f, fmt, ap); }
static int darwin_vprintf_chk(int, const char* fmt, const uint64_t* ap) { return darwin_vfprintf(stdout, fmt, ap); }
// ---- passwd database in Darwin layout --------------------------------------------------------------
struct DarwinPasswd {
    char* pw_name; char* pw_passwd; uint32_t pw_uid; uint32_t pw_gid; int64_t pw_change;
    char* pw_class; char* pw_gecos; char* pw_dir; char* pw_shell; int64_t pw_expire;
};
static void fill_darwin_passwd(DarwinPasswd* d, const struct passwd* p) {
    memset(d, 0, sizeof(*d));
    d->pw_name = p->pw_name; d->pw_passwd = p->pw_passwd; d->pw_uid = p->pw_uid; d->pw_gid = p->pw_gid;
    d->pw_gecos = p->pw_gecos; d->pw_dir = p->pw_dir; d->pw_shell = p->pw_shell;
    static char empty[] = "";
    d->pw_class = empty;
}
static DarwinPasswd* darwin_getpwuid(uint32_t uid) {
    static thread_local DarwinPasswd d;
    struct passwd* p = getpwuid(uid);
    if (!p) return nullptr;
    fill_darwin_passwd(&d, p);
    return &d;
}
static DarwinPasswd* darwin_getpwnam(const char* name) {
    static thread_local DarwinPasswd d;
    struct passwd* p = getpwnam(name);
    if (!p) return nullptr;
    fill_darwin_passwd(&d, p);
    return &d;
}
static int darwin_getpwuid_r(uint32_t uid, DarwinPasswd* out, char* buf, size_t len, DarwinPasswd** res) {
    struct passwd pw, *p = nullptr;
    int r = getpwuid_r(uid, &pw, buf, len, &p);
    if (r == 0 && p) { fill_darwin_passwd(out, p); *res = out; } else *res = nullptr;
    return r;
}
static int darwin_getpwnam_r(const char* name, DarwinPasswd* out, char* buf, size_t len, DarwinPasswd** res) {
    struct passwd pw, *p = nullptr;
    int r = getpwnam_r(name, &pw, buf, len, &p);
    if (r == 0 && p) { fill_darwin_passwd(out, p); *res = out; } else *res = nullptr;
    return r;
}
// group database: struct group has the same layout; Darwin's standard groups missing on Linux hosts map to their
// counterparts ("nobody" -> "nogroup", "wheel" -> "root")
static const char* darwin_group_alias(const char* name) {
    if (!name) return nullptr;
    if (!strcmp(name, "nobody")) return "nogroup";
    if (!strcmp(name, "wheel")) return "root";
    return nullptr;
}
static struct group* darwin_getgrnam(const char* name) {
    struct group* g = getgrnam(name);
    if (!g && darwin_group_alias(name)) g = getgrnam(darwin_group_alias(name));
    return g;
}
static int darwin_getgrnam_r(const char* name, struct group* out, char* buf, size_t len, struct group** res) {
    int r = getgrnam_r(name, out, buf, len, res);
    if (r == 0 && !*res && darwin_group_alias(name)) r = getgrnam_r(darwin_group_alias(name), out, buf, len, res);
    return r;
}
// pthread_atfork + fork: prepare handlers run in reverse registration order, parent/child ones in order
struct AtforkEntry { u64 prepare, parent, child; };
static std::mutex g_atfork_lock;
static std::vector<AtforkEntry> g_atfork;
static int darwin_pthread_atfork(u64 prepare, u64 parent, u64 child) {
    std::lock_guard<std::mutex> lk(g_atfork_lock);
    g_atfork.push_back({prepare, parent, child});
    return 0;
}
static std::mutex g_kq_lock;
static std::mutex g_tsd_lock;
static void hle_fork_hold(bool take) {
    if (take) { g_hle_lock.lock(); g_kq_lock.lock(); g_tsd_lock.lock(); darwin_stdio_fork_lock(true); }
    else { darwin_stdio_fork_lock(false); g_tsd_lock.unlock(); g_kq_lock.unlock(); g_hle_lock.unlock(); }
}
pid_t darwin_fork() {
    std::vector<AtforkEntry> h;
    { std::lock_guard<std::mutex> lk(g_atfork_lock); h = g_atfork; }
    for (size_t i = h.size(); i-- > 0;) if (h[i].prepare) guest_call(h[i].prepare, 0, nullptr);
    i64 r = process_fork(tls_thread ? tls_thread->st : nullptr, hle_fork_hold);
    for (const AtforkEntry& e : h) {
        u64 fn = r == 0 ? e.child : e.parent;
        if (fn) guest_call(fn, 0, nullptr);
    }
    if (r < 0) { errno = (int)-r; return -1; }
    return (pid_t)r;
}
static int darwin_fprintf_l(FILE* f, void*, const char* fmt, const uint64_t* ap) { return darwin_vfprintf(f, fmt, ap); }
static int darwin_printf_l(void*, const char* fmt, const uint64_t* ap) { return darwin_vfprintf(stdout, fmt, ap); }
static int darwin_sprintf_l(char* s, void*, const char* fmt, const uint64_t* ap) { return darwin_vsnprintf(s, (size_t)1 << 30, fmt, ap); }
static int darwin_vfprintf_l(FILE* f, void*, const char* fmt, const uint64_t* ap) { return darwin_vfprintf(f, fmt, ap); }
static int darwin_vsnprintf_l(char* s, size_t n, void*, const char* fmt, const uint64_t* ap) { return darwin_vsnprintf(s, n, fmt, ap); }
static int darwin_tolower(int c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; }
static int darwin_toupper(int c) { return (c >= 'a' && c <= 'z') ? c - 32 : c; }
static int darwin_tolower_l(int c, void*) { return darwin_tolower(c); }
static int darwin_toupper_l(int c, void*) { return darwin_toupper(c); }
static uint32_t darwin_maskrune_l(int c, uint32_t mask, void*) { return darwin_maskrune_wrapper(c, mask); }
static int darwin_mb_cur_max_l(void*) { return 1; }
static int darwin_btowc_l(int c, void*) { return btowc(c); }
static size_t darwin_mbrlen_l(const char* s, size_t n, mbstate_t* ps, void*) { return mbrlen(s, n, ps); }
static size_t darwin_mbrtowc_l(wchar_t* pwc, const char* s, size_t n, mbstate_t* ps, void*) { return mbrtowc(pwc, s, n, ps); }
static size_t darwin_mbsnrtowcs_l(wchar_t* d, const char** s, size_t nms, size_t len, mbstate_t* ps, void*) { return mbsnrtowcs(d, s, nms, len, ps); }
static size_t darwin_mbsrtowcs_l(wchar_t* d, const char** s, size_t len, mbstate_t* ps, void*) { return mbsrtowcs(d, s, len, ps); }
static int darwin_mbtowc_l(wchar_t* pwc, const char* s, size_t n, void*) { return mbtowc(pwc, s, n); }
static size_t darwin_wcrtomb_l(char* s, wchar_t wc, mbstate_t* ps, void*) { return wcrtomb(s, wc, ps); }
static size_t darwin_wcsnrtombs_l(char* d, const wchar_t** s, size_t nwc, size_t len, mbstate_t* ps, void*) { return wcsnrtombs(d, s, nwc, len, ps); }
static int darwin_wctob_l(wint_t c, void*) { return wctob(c); }
static struct lconv* darwin_localeconv_l(void*) { return localeconv(); }
static uint32_t darwin_pthread_mach_thread_np(uint64_t th) {
    DarwinPthread* p = pthread_of(th);
    return p ? darwin_thread_port(p->tid) : 0;
}

// compiler-rt 128-bit division (two registers in, two registers out)
struct U128Ret { uint64_t lo, hi; };
static U128Ret darwin_udivti3(uint64_t alo, uint64_t ahi, uint64_t blo, uint64_t bhi) {
    unsigned __int128 a = ((unsigned __int128)ahi << 64) | alo, b = ((unsigned __int128)bhi << 64) | blo;
    unsigned __int128 q = b ? a / b : 0;
    return {(uint64_t)q, (uint64_t)(q >> 64)};
}
static U128Ret darwin_divti3(uint64_t alo, uint64_t ahi, uint64_t blo, uint64_t bhi) {
    __int128 a = (__int128)(((unsigned __int128)ahi << 64) | alo), b = (__int128)(((unsigned __int128)bhi << 64) | blo);
    __int128 q = b ? a / b : 0;
    return {(uint64_t)q, (uint64_t)((unsigned __int128)q >> 64)};
}
static U128Ret darwin_umodti3(uint64_t alo, uint64_t ahi, uint64_t blo, uint64_t bhi) {
    unsigned __int128 a = ((unsigned __int128)ahi << 64) | alo, b = ((unsigned __int128)bhi << 64) | blo;
    unsigned __int128 q = b ? a % b : 0;
    return {(uint64_t)q, (uint64_t)(q >> 64)};
}
static U128Ret darwin_modti3(uint64_t alo, uint64_t ahi, uint64_t blo, uint64_t bhi) {
    __int128 a = (__int128)(((unsigned __int128)ahi << 64) | alo), b = (__int128)(((unsigned __int128)bhi << 64) | blo);
    __int128 q = b ? a % b : 0;
    return {(uint64_t)q, (uint64_t)((unsigned __int128)q >> 64)};
}


// xlocale variants: Darwin passes a null locale_t for "the C locale"; glibc's *_l crash on it, so the
// locale argument is ignored.
static long long darwin_strtoll_l(const char* s, char** e, int b, void*) { return strtoll(s, e, b); }
static unsigned long long darwin_strtoull_l(const char* s, char** e, int b, void*) { return strtoull(s, e, b); }
static long darwin_strtol_l(const char* s, char** e, int b, void*) { return strtol(s, e, b); }
static unsigned long darwin_strtoul_l(const char* s, char** e, int b, void*) { return strtoul(s, e, b); }
static double darwin_strtod_l(const char* s, char** e, void*) { return strtod(s, e); }
static float darwin_strtof_l(const char* s, char** e, void*) { return strtof(s, e); }
static double darwin_strtold_l(const char* s, char** e, void*) { return strtod(s, e); }   // long double == double
static int darwin_strcoll_l(const char* a, const char* b, void*) { return strcoll(a, b); }
static size_t darwin_strxfrm_l(char* d, const char* s, size_t n, void*) { return strxfrm(d, s, n); }
// locale_t is a Darwin pointer (never a glibc locale): the C-locale comparison is what CF/GLFW expect
static int darwin_strcasecmp_l(const char* a, const char* b, void*) { return strcasecmp(a, b); }
static int darwin_strncasecmp_l(const char* a, const char* b, size_t n, void*) { return strncasecmp(a, b, n); }
static size_t darwin_strftime(char* s, size_t n, const char* f, const struct tm* t) {
    std::string fmt = f ? f : "";
    size_t pos = 0;
    while ((pos = fmt.find("%+", pos)) != std::string::npos) {
        fmt.replace(pos, 2, "%a %b %e %H:%M:%S %Z %Y");
        pos += 24;
    }
    return strftime(s, n, fmt.c_str(), t);
}
static size_t darwin_strftime_l(char* s, size_t n, const char* f, const struct tm* t, void*) {
    return darwin_strftime(s, n, f, t);
}
static int darwin_wcscoll_l(const wchar_t* a, const wchar_t* b, void*) { return wcscoll(a, b); }
static size_t darwin_wcsxfrm_l(wchar_t* d, const wchar_t* s, size_t n, void*) { return wcsxfrm(d, s, n); }
static long long darwin_wcstoll_l(const wchar_t* s, wchar_t** e, int b, void*) { return wcstoll(s, e, b); }
static unsigned long long darwin_wcstoull_l(const wchar_t* s, wchar_t** e, int b, void*) { return wcstoull(s, e, b); }
static long darwin_wcstol_l(const wchar_t* s, wchar_t** e, int b, void*) { return wcstol(s, e, b); }
static unsigned long darwin_wcstoul_l(const wchar_t* s, wchar_t** e, int b, void*) { return wcstoul(s, e, b); }
static double darwin_wcstod_l(const wchar_t* s, wchar_t** e, void*) { return wcstod(s, e); }
static float darwin_wcstof_l(const wchar_t* s, wchar_t** e, void*) { return wcstof(s, e); }
static double darwin_wcstold_l(const wchar_t* s, wchar_t** e, void*) { return wcstod(s, e); }
static int darwin_isalpha_l(int c, void*) { return isalpha(c); }
static int darwin_isdigit_l(int c, void*) { return isdigit(c); }
static int darwin_isspace_l(int c, void*) { return isspace(c); }
static int darwin_isupper_l(int c, void*) { return isupper(c); }
static int darwin_islower_l(int c, void*) { return islower(c); }
static int darwin_isalnum_l(int c, void*) { return isalnum(c); }
static int darwin_ispunct_l(int c, void*) { return ispunct(c); }
static int darwin_isprint_l(int c, void*) { return isprint(c); }
static int darwin_iswctype_l(wint_t c, wctype_t t, void*) { return iswctype(c, t); }
static wint_t darwin_towlower_l(wint_t c, void*) { return towlower(c); }
static wint_t darwin_towupper_l(wint_t c, void*) { return towupper(c); }
static int darwin_isxdigit_l(int c, void*) { return isxdigit(c); }
static int darwin_iscntrl_l(int c, void*) { return iscntrl(c); }
static int darwin_isgraph_l(int c, void*) { return isgraph(c); }
static int darwin_isblank_l(int c, void*) { return isblank(c); }
static int darwin_tolower_plain_l(int c, void*) { return tolower(c); }
static int darwin_toupper_plain_l(int c, void*) { return toupper(c); }
static int darwin_lc_to_linux(int cat) {
    switch (cat) {
        case 0: return LC_ALL;
        case 1: return LC_COLLATE;
        case 2: return LC_CTYPE;
        case 3: return LC_MONETARY;
        case 4: return LC_NUMERIC;
        case 5: return LC_TIME;
        case 6: return LC_MESSAGES;
        default: return cat;
    }
}

static char* darwin_setlocale(int category, const char* locale) {
    int linux_cat = darwin_lc_to_linux(category);
    char* r = setlocale(linux_cat, locale);
    if (!r && locale) {
        if (strcasecmp(locale, "UTF-8") == 0 || strcasecmp(locale, "utf8") == 0) {
            r = setlocale(linux_cat, "C.UTF-8");
        }
    }
    return r;
}

static void* darwin_newlocale(int, const char*, void*) { return (void*)1; }   // opaque non-null token
static void darwin_freelocale(void*) {}
static void* darwin_uselocale(void*) { return (void*)1; }

// _dyld_lookup_section_info(mh, metadata, kind) -> {buffer, size} in x0:x1
static U128Ret darwin_dyld_lookup_section_info(uint64_t mh, uint64_t, uint64_t kind, uint64_t) {
    static const char* const kNames[] = {
        "__swift5_protos", "__swift5_proto", "__swift5_types", "__swift5_replace", "__swift5_replac2", "__swift5_acfuncs",
        "__objc_imageinfo", "__objc_selrefs", "__objc_msgrefs", "__objc_classrefs", "__objc_superrefs", "__objc_protorefs",
        "__objc_classlist", "__objc_nlclslist", "__objc_stublist", "__objc_catlist", "__objc_catlist2", "__objc_nlcatlist",
        "__objc_protolist", "__objc_fork_ok", "__objc_rawisa"};
    if (kind >= sizeof(kNames) / sizeof(kNames[0])) return {0, (uint64_t)-1};
    for (MachImage* im : dyld_images()) {
        if (im->header != mh) continue;
        for (const MachSection& s : im->sects)
            if (!strncmp(s.sect, kNames[kind], 16)) return {s.addr, s.size};
        return {0, 0};
    }
    return {0, 0};
}

// ___sincosf_stret / ___sincos_stret: arm64 returns the {sin,cos} pair as an HFA in s0,s1 / d0,d1; the SysV structs come
// back packed in xmm0 (floats) / xmm0:xmm1 (doubles), so darwin_hle_dispatch calls these directly (shim modes -3 / -4).
struct F2Ret { float s, c; };
struct D2Ret { double s, c; };
static F2Ret darwin_sincosf_stret(float x) { return {sinf(x), cosf(x)}; }
static D2Ret darwin_sincos_stret(double x) { return {sin(x), cos(x)}; }

struct ShimEntry { const char* name; void* fn; int variadic_fixed; };   // variadic_fixed: >=0 -> args from stack
static int darwin_open_v(const char* path, int dflags, const uint64_t* ap);
static int darwin_openat_v(int dfd, const char* path, int dflags, const uint64_t* ap);
static long darwin_fcntl_v(int fd, int cmd, const uint64_t* ap);
static int darwin_ioctl_v(int fd, unsigned long req, const uint64_t* ap);
void* st_sem_open_entry(const char* name, int oflag, const uint64_t* ap);
int darwin_semctl_v(int id, int num, int cmd, const uint64_t* ap);   // darwin_fs.cpp
int st_shm_open_entry(const char* name, int oflag, const uint64_t* ap);   // darwin_stubs.cpp
static void* darwin_sem_open_v(const char* name, int oflag, const uint64_t* ap) { return st_sem_open_entry(name, oflag, ap); }
static const ShimEntry kShims[] = {
    {"__xef_open", (void*)&darwin_open_v, 2}, {"__xef_openat", (void*)&darwin_openat_v, 3}, {"__xef_fcntl", (void*)&darwin_fcntl_v, 2},
    {"__xef_ioctl", (void*)&darwin_ioctl_v, 2},
    {"_sem_open", (void*)&darwin_sem_open_v, 2}, {"_shm_open", (void*)&st_shm_open_entry, 2}, {"_semctl", (void*)&darwin_semctl_v, 3}, {"_system", (void*)&darwin_system, -1},
    {"_execl", (void*)&darwin_execl, 2}, {"_execlp", (void*)&darwin_execlp, 2}, {"_execle", (void*)&darwin_execle, 2},
    {"_execve", (void*)&darwin_execve, -1}, {"_execv", (void*)&darwin_execv, -1}, {"_execvp", (void*)&darwin_execvp, -1},
    {"_execvP", (void*)&darwin_execvP, -1},
    {"_snprintf_l", (void*)&darwin_snprintf_l, 4}, {"_sprintf", (void*)&darwin_sprintf, 2},
    {"_asprintf", (void*)&darwin_asprintf, 2}, {"_asprintf_l", (void*)&darwin_asprintf_l, 3},
    {"_dprintf", (void*)&darwin_dprintf, 2}, {"_vasprintf", (void*)&darwin_vasprintf, -1},
    {"_vsprintf", (void*)&darwin_vsprintf, -1}, {"_vprintf", (void*)&darwin_vprintf, -1}, {"_vdprintf", (void*)&darwin_vdprintf, -1}, {"_sscanf", (void*)&darwin_sscanf, 2},
    {"_sscanf_l", (void*)&darwin_sscanf_l, 3}, {"_fscanf", (void*)&darwin_fscanf, 2},
    {"___tolower", (void*)&darwin_tolower, -1}, {"___toupper", (void*)&darwin_toupper, -1},
    {"____tolower_l", (void*)&darwin_tolower_l, -1}, {"____toupper_l", (void*)&darwin_toupper_l, -1},
    {"___maskrune_l", (void*)&darwin_maskrune_l, -1}, {"____mb_cur_max_l", (void*)&darwin_mb_cur_max_l, -1},
    {"_btowc_l", (void*)&darwin_btowc_l, -1}, {"_mbrlen_l", (void*)&darwin_mbrlen_l, -1},
    {"_mbrtowc_l", (void*)&darwin_mbrtowc_l, -1}, {"_mbsnrtowcs_l", (void*)&darwin_mbsnrtowcs_l, -1},
    {"_mbsrtowcs_l", (void*)&darwin_mbsrtowcs_l, -1}, {"_mbtowc_l", (void*)&darwin_mbtowc_l, -1},
    {"_wcrtomb_l", (void*)&darwin_wcrtomb_l, -1}, {"_wcsnrtombs_l", (void*)&darwin_wcsnrtombs_l, -1},
    {"_wctob_l", (void*)&darwin_wctob_l, -1}, {"_localeconv_l", (void*)&darwin_localeconv_l, -1},
    {"_strtoll_l", (void*)&darwin_strtoll_l, -1},
    {"_strtoull_l", (void*)&darwin_strtoull_l, -1},
    {"_strtol_l", (void*)&darwin_strtol_l, -1},
    {"_strtoul_l", (void*)&darwin_strtoul_l, -1},
    {"_strtod_l", (void*)&darwin_strtod_l, -1},
    {"_strtof_l", (void*)&darwin_strtof_l, -1},
    {"_strtold_l", (void*)&darwin_strtold_l, -1},
    {"_strcoll_l", (void*)&darwin_strcoll_l, -1},
    {"_strxfrm_l", (void*)&darwin_strxfrm_l, -1},
    {"_strcasecmp_l", (void*)&darwin_strcasecmp_l, -1}, {"_strncasecmp_l", (void*)&darwin_strncasecmp_l, -1},
    {"_strftime", (void*)&darwin_strftime, -1},
    {"_strftime_l", (void*)&darwin_strftime_l, -1},
    {"_wcscoll_l", (void*)&darwin_wcscoll_l, -1},
    {"_wcsxfrm_l", (void*)&darwin_wcsxfrm_l, -1},
    {"_wcstoll_l", (void*)&darwin_wcstoll_l, -1},
    {"_wcstoull_l", (void*)&darwin_wcstoull_l, -1},
    {"_wcstol_l", (void*)&darwin_wcstol_l, -1},
    {"_wcstoul_l", (void*)&darwin_wcstoul_l, -1},
    {"_wcstod_l", (void*)&darwin_wcstod_l, -1},
    {"_wcstof_l", (void*)&darwin_wcstof_l, -1},
    {"_wcstold_l", (void*)&darwin_wcstold_l, -1},
    {"_isalpha_l", (void*)&darwin_isalpha_l, -1},
    {"_isdigit_l", (void*)&darwin_isdigit_l, -1},
    {"_isspace_l", (void*)&darwin_isspace_l, -1},
    {"_isupper_l", (void*)&darwin_isupper_l, -1},
    {"_islower_l", (void*)&darwin_islower_l, -1},
    {"_isalnum_l", (void*)&darwin_isalnum_l, -1},
    {"_ispunct_l", (void*)&darwin_ispunct_l, -1},
    {"_isprint_l", (void*)&darwin_isprint_l, -1},
    {"_iswctype_l", (void*)&darwin_iswctype_l, -1},
    {"_towlower_l", (void*)&darwin_towlower_l, -1},
    {"_towupper_l", (void*)&darwin_towupper_l, -1},
    {"_isxdigit_l", (void*)&darwin_isxdigit_l, -1}, {"_iscntrl_l", (void*)&darwin_iscntrl_l, -1},
    {"_isgraph_l", (void*)&darwin_isgraph_l, -1}, {"_isblank_l", (void*)&darwin_isblank_l, -1},
    {"_tolower_l", (void*)&darwin_tolower_plain_l, -1}, {"_toupper_l", (void*)&darwin_toupper_plain_l, -1},
    {"_setlocale", (void*)&darwin_setlocale, -1},
    {"_newlocale", (void*)&darwin_newlocale, -1}, {"_freelocale", (void*)&darwin_freelocale, -1}, {"_uselocale", (void*)&darwin_uselocale, -1},
    {"___strlcpy_chk", (void*)&darwin_strlcpy_chk, -1}, {"___strlcat_chk", (void*)&darwin_strlcat_chk, -1},
    {"___strcpy_chk", (void*)&darwin_strcpy_chk, -1}, {"___stpcpy_chk", (void*)&darwin_stpcpy_chk, -1},
    {"___strcat_chk", (void*)&darwin_strcat_chk, -1}, {"___strncpy_chk", (void*)&darwin_strncpy_chk, -1},
    {"___stpncpy_chk", (void*)&darwin_stpncpy_chk, -1}, {"___strncat_chk", (void*)&darwin_strncat_chk, -1},
    {"___memmove_chk", (void*)&darwin_memmove_chk, -1}, {"___memset_chk", (void*)&darwin_memset_chk, -1},
    {"___snprintf_chk", (void*)&darwin_snprintf_chk, 5}, {"___sprintf_chk", (void*)&darwin_sprintf_chk, 4},
    {"___vsnprintf_chk", (void*)&darwin_vsnprintf_chk, -1}, {"___vsprintf_chk", (void*)&darwin_vsprintf_chk, -1},
    {"___fprintf_chk", (void*)&darwin_fprintf_chk, 3}, {"___printf_chk", (void*)&darwin_printf_chk, 2},
    {"___vfprintf_chk", (void*)&darwin_vfprintf_chk, -1}, {"___vprintf_chk", (void*)&darwin_vprintf_chk, -1},
    {"_strlcpy", (void*)&darwin_strlcpy_impl, -1}, {"_strlcat", (void*)&darwin_strlcat_impl, -1},
    {"_fprintf_l", (void*)&darwin_fprintf_l, 3}, {"_printf_l", (void*)&darwin_printf_l, 2}, {"_sprintf_l", (void*)&darwin_sprintf_l, 3},
    {"_vfprintf_l", (void*)&darwin_vfprintf_l, -1}, {"_vsnprintf_l", (void*)&darwin_vsnprintf_l, -1},
    {"_getpwuid", (void*)&darwin_getpwuid, -1}, {"_getpwnam", (void*)&darwin_getpwnam, -1},
    {"_getpwuid_r", (void*)&darwin_getpwuid_r, -1}, {"_getpwnam_r", (void*)&darwin_getpwnam_r, -1},
    {"_pthread_atfork", (void*)&darwin_pthread_atfork, -1},
    {"_getgrnam", (void*)&darwin_getgrnam, -1}, {"_getgrnam_r", (void*)&darwin_getgrnam_r, -1},
    {"_fork", (void*)&darwin_fork, -1}, {"_vfork", (void*)&darwin_fork, -1},
    {"_pthread_mach_thread_np", (void*)&darwin_pthread_mach_thread_np, -1},
    {"_regcomp", (void*)&darwin_regcomp, -1}, {"_regcomp$DARWIN_EXTSN", (void*)&darwin_regcomp, -1},
    {"_regexec", (void*)&darwin_regexec, -1}, {"_regexec$DARWIN_EXTSN", (void*)&darwin_regexec, -1},
    {"_regfree", (void*)&darwin_regfree, -1}, {"_regfree$DARWIN_EXTSN", (void*)&darwin_regfree, -1},
    {"_regerror", (void*)&darwin_regerror, -1}, {"_regerror$DARWIN_EXTSN", (void*)&darwin_regerror, -1},
    {"___udivti3", (void*)&darwin_udivti3, -2}, {"___divti3", (void*)&darwin_divti3, -2},
    {"__dyld_lookup_section_info", (void*)&darwin_dyld_lookup_section_info, -2},
    {"___umodti3", (void*)&darwin_umodti3, -2}, {"___modti3", (void*)&darwin_modti3, -2},
    {"_getpagesize", (void*)&darwin_getpagesize, -1}, {"getpagesize", (void*)&darwin_getpagesize, -1},
    {"___sincosf_stret", (void*)&darwin_sincosf_stret, -3}, {"___sincos_stret", (void*)&darwin_sincos_stret, -4},
};
// -2: returns a 128-bit value in x0:x1
static const ShimEntry* find_shim_by_fn(void* fn) {
    for (const ShimEntry& e : kShims) if (e.fn == fn) return &e;
    return nullptr;
}

// Dyld runtime introspection
static uint32_t darwin_dyld_image_count() {
    return (uint32_t)dyld_images().size();
}

static const char* darwin_dyld_get_image_name(uint32_t index) {
    auto& v = dyld_images();
    return index < v.size() ? v[index]->path.c_str() : nullptr;
}

static intptr_t darwin_dyld_get_image_vmaddr_slide(uint32_t index) {
    auto& v = dyld_images();
    return index < v.size() ? (intptr_t)v[index]->slide : 0;
}

static void* darwin_dyld_get_image_header(uint32_t index) {
    auto& v = dyld_images();
    return index < v.size() ? (void*)(uintptr_t)v[index]->header : nullptr;
}

struct DyldUnwindSections {
    const void* mh;
    const void* dwarf_section;
    uintptr_t dwarf_section_length;
    const void* compact_unwind_section;
    uintptr_t compact_unwind_section_length;
};
static bool darwin_dyld_find_unwind_sections(void* addr, DyldUnwindSections* info) {
    MachImage* im = dyld_image_containing((uint64_t)(uintptr_t)addr);
    if (!im || !info) return false;
    info->mh = (const void*)(uintptr_t)im->header;
    info->dwarf_section = (const void*)(uintptr_t)im->eh_frame;
    info->dwarf_section_length = (uintptr_t)im->eh_frame_size;
    info->compact_unwind_section = (const void*)(uintptr_t)im->unwind_info;
    info->compact_unwind_section_length = (uintptr_t)im->unwind_info_size;
    return true;
}

static void darwin_dyld_register_func_for_add_image(u64 fn) {
    if (!fn) return;
    auto imgs = dyld_images();   // copy: the callback may load more
    for (MachImage* im : imgs) {
        u64 a[2] = {im->header, im->slide};
        guest_call(fn, 2, a);
    }
}
static void darwin_dyld_register_func_for_remove_image(u64) {}

static const char* darwin_dyld_get_image_install_name(const void* mh) {
    for (MachImage* im : dyld_images())
        if (im->header == (uint64_t)(uintptr_t)mh) return im->install_name.c_str();
    return nullptr;
}

// Thread-Local Storage (TLV)
struct TLVDescriptor {
    void* (*thunk)(struct TLVDescriptor*);
    unsigned long key;
    unsigned long offset;
};

static thread_local void* g_thread_tlv_block = nullptr;
static constexpr size_t kDefaultTlvSize = 128 * 1024;

static void* darwin_tlv_bootstrap(TLVDescriptor* desc) {
    return dyld_tlv_address((uint64_t)(uintptr_t)desc);
}

static int darwin_tlv_atexit(void (*term)(void*), void* obj, void* dso) {
    (void)term; (void)obj; (void)dso;
    return 0;
}

// Darwin pthread TSD: values live in the guest thread's TSD array behind TPIDRRO_EL0 (os/thread.cpp), like
// libpthread, so code reading the slots directly (Go's runtime.tlsinit, _pthread_getspecific_direct) sees them.
// Slots below 256 are libSystem's static keys; pthread_key_create hands out 256..767, and libSystem itself has
// taken 256 and 257 by the time main runs (the first key a macOS program gets is 258).
static constexpr int kTsdFirstDynamic = 256, kTsdSlots = 768;
static uint64_t g_destructors[kTsdSlots] = {};
static bool g_key_used[kTsdSlots] = {};

static uint64_t* tsd_slots() { return tls_thread ? (uint64_t*)tls_thread->tsd : nullptr; }

static int darwin_pthread_key_create(uint64_t* key_out, uint64_t destructor) {
    std::lock_guard<std::mutex> lk(g_tsd_lock);
    g_key_used[kTsdFirstDynamic] = g_key_used[kTsdFirstDynamic + 1] = true;
    for (int i = kTsdFirstDynamic; i < kTsdSlots; i++) {
        if (!g_key_used[i]) {
            g_key_used[i] = true;
            g_destructors[i] = destructor;
            if (key_out) *key_out = (uint64_t)i;
            return 0;
        }
    }
    return EAGAIN;
}

static int darwin_pthread_setspecific(uint64_t key, const void* value) {
    uint64_t* t = tsd_slots();
    if (key == 0 || key >= kTsdSlots || !t) return EINVAL;
    t[key] = (uint64_t)(uintptr_t)value;
    return 0;
}

static void* darwin_pthread_getspecific(uint64_t key) {
    uint64_t* t = tsd_slots();
    if (key >= kTsdSlots || !t) return nullptr;
    return (void*)(uintptr_t)t[key];
}

static int darwin_pthread_key_delete(uint64_t key) {
    std::lock_guard<std::mutex> lk(g_tsd_lock);
    if (key < kTsdFirstDynamic || key >= kTsdSlots || !g_key_used[key]) return EINVAL;
    g_key_used[key] = false;
    g_destructors[key] = 0;
    return 0;
}

// thread exit (pthread_exit or return from the start routine): run the key destructors for non-NULL values,
// up to PTHREAD_DESTRUCTOR_ITERATIONS (4) rounds, clearing each value before its destructor runs
void darwin_tsd_run_destructors() {
    uint64_t* t = tsd_slots();
    if (!t) return;
    for (int round = 0; round < 4; round++) {
        bool any = false;
        for (int k = kTsdFirstDynamic; k < kTsdSlots; k++) {
            uint64_t v = t[k], d;
            if (!v) continue;
            {
                std::lock_guard<std::mutex> lk(g_tsd_lock);
                d = g_key_used[k] ? g_destructors[k] : 0;
            }
            if (!d) continue;
            t[k] = 0;
            u64 a[1] = {v};
            guest_call(d, 1, a);
            any = true;
        }
        if (!any) break;
    }
}

// Darwin pthread_mutex emulation using host recursive_mutex
static std::mutex g_host_mutex_table_lock;
static std::unordered_map<void*, std::unique_ptr<std::recursive_mutex>> g_host_mutexes;

static std::recursive_mutex* get_host_mutex(void* mutex) {
    if (!mutex) return nullptr;
    std::lock_guard<std::mutex> lk(g_host_mutex_table_lock);
    auto& m = g_host_mutexes[mutex];
    if (!m) m = std::make_unique<std::recursive_mutex>();
    return m.get();
}

static int darwin_pthread_mutex_init(void* mutex, void* attr) {
    (void)attr;
    if (mutex) {
        std::lock_guard<std::mutex> lk(g_host_mutex_table_lock);
        g_host_mutexes[mutex] = std::make_unique<std::recursive_mutex>();
    }
    return 0;
}

static int darwin_pthread_mutex_lock(void* mutex) {
    if (!mutex) return EINVAL;
    get_host_mutex(mutex)->lock();
    return 0;
}

static int darwin_pthread_mutex_trylock(void* mutex) {
    if (!mutex) return EINVAL;
    return get_host_mutex(mutex)->try_lock() ? 0 : EBUSY;
}

static int darwin_pthread_mutex_unlock(void* mutex) {
    if (!mutex) return EINVAL;
    get_host_mutex(mutex)->unlock();
    return 0;
}

static int darwin_pthread_mutex_destroy(void* mutex) {
    if (mutex) {
        std::lock_guard<std::mutex> lk(g_host_mutex_table_lock);
        g_host_mutexes.erase(mutex);
    }
    return 0;
}

// Darwin pthread_cond emulation
static std::mutex g_host_cond_table_lock;
static std::unordered_map<void*, std::unique_ptr<std::condition_variable_any>> g_host_conds;

static std::condition_variable_any* get_host_cond(void* cond) {
    if (!cond) return nullptr;
    std::lock_guard<std::mutex> lk(g_host_cond_table_lock);
    auto& c = g_host_conds[cond];
    if (!c) c = std::make_unique<std::condition_variable_any>();
    return c.get();
}

static int darwin_pthread_cond_init(void* cond, void* attr) {
    (void)attr;
    if (cond) {
        std::lock_guard<std::mutex> lk(g_host_cond_table_lock);
        g_host_conds[cond] = std::make_unique<std::condition_variable_any>();
    }
    return 0;
}

static int darwin_pthread_cond_signal(void* cond) {
    if (!cond) return EINVAL;
    get_host_cond(cond)->notify_one();
    return 0;
}

static int darwin_pthread_cond_broadcast(void* cond) {
    if (!cond) return EINVAL;
    get_host_cond(cond)->notify_all();
    return 0;
}

static int darwin_pthread_cond_wait(void* cond, void* mutex) {
    if (!cond || !mutex) return EINVAL;
    auto* cv = get_host_cond(cond);
    auto* mtx = get_host_mutex(mutex);
    cv->wait(*mtx);
    return 0;
}

static int darwin_pthread_cond_timedwait(void* cond, void* mutex, const struct timespec* abstime) {
    if (!cond || !mutex) return EINVAL;
    auto* cv = get_host_cond(cond);
    auto* mtx = get_host_mutex(mutex);
    if (!abstime) {
        XEF_LOG(2, "pthread_cond_timedwait: abstime is null, waiting indefinitely");
        cv->wait(*mtx);
        return 0;
    }
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    XEF_LOG(2, "pthread_cond_timedwait: now=(%ld, %ld), abstime=(%ld, %ld)",
            (long)now.tv_sec, (long)now.tv_nsec, (long)abstime->tv_sec, (long)abstime->tv_nsec);
    int64_t sec_diff = (int64_t)abstime->tv_sec - (int64_t)now.tv_sec;
    if (sec_diff > 100000000ll) { cv->wait(*mtx); return 0; }    // "forever" (distantFuture etc.): avoid int64 ns overflow
    int64_t nsec_diff = (int64_t)abstime->tv_nsec - (int64_t)now.tv_nsec;
    int64_t total_ns = sec_diff * 1000000000ll + nsec_diff;
    if (total_ns <= 0) return ETIMEDOUT;

    if (cv->wait_for(*mtx, std::chrono::nanoseconds(total_ns)) == std::cv_status::timeout) {
        return ETIMEDOUT;
    }
    return 0;
}

static int darwin_pthread_cond_timedwait_relative_np(void* cond, void* mutex, const struct timespec* reltime) {
    if (!cond || !mutex) return EINVAL;
    auto* cv = get_host_cond(cond);
    auto* mtx = get_host_mutex(mutex);
    if (!reltime) {
        cv->wait(*mtx);
        return 0;
    }
    if (reltime->tv_sec > 100000000ll) { cv->wait(*mtx); return 0; }
    int64_t total_ns = (int64_t)reltime->tv_sec * 1000000000ll + reltime->tv_nsec;
    if (total_ns <= 0) return ETIMEDOUT;

    if (cv->wait_for(*mtx, std::chrono::nanoseconds(total_ns)) == std::cv_status::timeout) {
        return ETIMEDOUT;
    }
    return 0;
}

static int darwin_pthread_cond_destroy(void* cond) {
    if (cond) {
        std::lock_guard<std::mutex> lk(g_host_cond_table_lock);
        g_host_conds.erase(cond);
    }
    return 0;
}

struct DarwinPthreadOnce {
    long sig;
    long padding[2];
};

static int darwin_pthread_once(DarwinPthreadOnce* once_control, u64 init_routine) {
    if (!once_control || !init_routine) return EINVAL;
    if (once_control->sig == 0x30B1BCBA || once_control->sig == 0) {
        once_control->sig = 0x30B1BCBB;
        guest_call(init_routine, 0, nullptr);
    }
    return 0;
}

static int darwin_pthread_create(uint64_t* th_out, void* attr, uint64_t start_routine, uint64_t arg) {
    return darwin_spawn_thread(th_out, attr, start_routine, arg);
}

static int darwin_pthread_join(uint64_t th, void** val_out) {
    DarwinPthread* p = pthread_of(th);
    if (!p || !th) return ESRCH;
    if (p == pthread_cur()) return EDEADLK;
    int r = pthread_join(p->host, val_out);
    if (r == 0) { p->sig = 0; delete p; }
    return r;
}

static int darwin_pthread_detach(uint64_t th) {
    DarwinPthread* p = pthread_of(th);
    return p ? pthread_detach(p->host) : ESRCH;
}

static uint64_t darwin_pthread_self() {
    return (uint64_t)(uintptr_t)pthread_cur();
}

static void darwin_pthread_exit(void* val) {
    darwin_tsd_run_destructors();
    thread_set_retval((u64)(uintptr_t)val);
    ThreadCtx* t = tls_thread;
    thread_exit(t ? t->st : nullptr, 0);
}

static int darwin_pthread_setname_np(const char* name) {
    pthread_setname_np(pthread_self(), name);
    return 0;
}

static int darwin_pthread_threadid_np(uint64_t thread, uint64_t* thread_id) {
    if (!thread_id) return EINVAL;
    DarwinPthread* p = pthread_of(thread);
    if (!p) return ESRCH;
    *thread_id = (uint64_t)p->tid;
    return 0;
}

static int darwin_sched_yield() {
    return sched_yield();
}

// os_unfair_lock: 32-bit atomic lock
// In libsystem_kernel / libsystem_platform:
// 0 = unlocked, non-zero = locked with owner thread id / bits
struct os_unfair_lock_s {
    std::atomic<uint32_t> _os_unfair_lock_opaque;
};

static inline uint32_t unfair_self() { static thread_local uint32_t t = (uint32_t)syscall(SYS_gettid); return t; }
static void darwin_os_unfair_lock_lock(os_unfair_lock_s* lock) {
    if (!lock) return;
    uint32_t me = unfair_self(), expected = 0;
    while (!lock->_os_unfair_lock_opaque.compare_exchange_weak(expected, me, std::memory_order_acquire, std::memory_order_relaxed)) {
        if (expected != 0 && expected != me)
            syscall(SYS_futex, &lock->_os_unfair_lock_opaque, FUTEX_WAIT_PRIVATE, expected, nullptr, nullptr, 0);
        expected = 0;
    }
}

static bool darwin_os_unfair_lock_trylock(os_unfair_lock_s* lock) {
    if (!lock) return false;
    uint32_t expected = 0;
    return lock->_os_unfair_lock_opaque.compare_exchange_strong(expected, unfair_self(), std::memory_order_acquire, std::memory_order_relaxed);
}

static void darwin_os_unfair_lock_unlock(os_unfair_lock_s* lock) {
    if (!lock) return;
    lock->_os_unfair_lock_opaque.store(0, std::memory_order_release);
    syscall(SYS_futex, &lock->_os_unfair_lock_opaque, FUTEX_WAKE_PRIVATE, 1, nullptr, nullptr, 0);
}

static int darwin_issetugid() {
    return 0; // Not setuid/setgid
}

static uint64_t darwin_mach_absolute_time() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint64_t darwin_mach_approximate_time() {
    return darwin_mach_absolute_time();
}

static uint64_t darwin_mach_continuous_time() {
    struct timespec ts;
    clock_gettime(CLOCK_BOOTTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint64_t darwin_mach_continuous_approximate_time() {
    return darwin_mach_continuous_time();
}

static uint64_t darwin_mach_boottime_usec() {
    struct timespec rts, bts;
    clock_gettime(CLOCK_REALTIME, &rts);
    clock_gettime(CLOCK_BOOTTIME, &bts);
    int64_t sec = (int64_t)rts.tv_sec - (int64_t)bts.tv_sec;
    int64_t nsec = (int64_t)rts.tv_nsec - (int64_t)bts.tv_nsec;
    if (nsec < 0) { sec--; nsec += 1000000000ll; }
    return (uint64_t)sec * 1000000ull + (uint64_t)(nsec / 1000);
}

static int darwin_mach_wait_until(uint64_t deadline) {
    uint64_t now = darwin_mach_absolute_time();
    if (deadline > now) {
        struct timespec ts;
        ts.tv_sec = deadline / 1000000000ull;
        ts.tv_nsec = deadline % 1000000000ull;
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, nullptr);
    }
    return 0; // KERN_SUCCESS
}

struct mach_timebase_info_t {
    uint32_t numer;
    uint32_t denom;
};

static int darwin_mach_timebase_info(mach_timebase_info_t* info) {
    if (!info) return EINVAL;
    info->numer = 1;
    info->denom = 1;
    return 0;
}

static int darwin_Unwind_Backtrace(void* trace_fn, void* trace_arg) {
    (void)trace_fn; (void)trace_arg;
    return 5; // _URC_END_OF_STACK
}

static int darwin_CCRandomGenerateBytes(void* bytes, size_t count) {
    if (!bytes && count > 0) return -1;
    if (getrandom(bytes, count, 0) == (ssize_t)count) {
        return 0; // kCCSuccess
    }
    // Fallback: /dev/urandom
    int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        ssize_t rd = read(fd, bytes, count);
        close(fd);
        if (rd == (ssize_t)count) return 0;
    }
    return -1;
}

// Darwin struct kevent (32 bytes)
struct darwin_kevent_t {
    uintptr_t ident;   // identifier for this event (e.g. fd)
    int16_t   filter;  // filter for event: EVFILT_READ (-1), EVFILT_WRITE (-2)
    uint16_t  flags;   // action flags: EV_ADD (1), EV_DELETE (2), EV_ENABLE (4), EV_DISABLE (8)
    uint32_t  fflags;  // filter-specific flags
    intptr_t  data;    // filter-specific data
    void*     udata;   // opaque user data identifier
};

static constexpr int16_t DARWIN_EVFILT_READ  = -1;
static constexpr int16_t DARWIN_EVFILT_WRITE = -2;
static constexpr uint16_t DARWIN_EV_ADD      = 0x0001;
static constexpr uint16_t DARWIN_EV_DELETE   = 0x0002;
static constexpr uint16_t DARWIN_EV_ENABLE   = 0x0004;
static constexpr uint16_t DARWIN_EV_DISABLE  = 0x0008;

static constexpr uint16_t DARWIN_EV_RECEIPT  = 0x0040;
static constexpr uint16_t DARWIN_EV_ERROR    = 0x4000;
static constexpr int16_t  DARWIN_EVFILT_USER = -10;

// ---- kqueue emulation on top of epoll --------------------------------------------------------------------------
// Supported filters: EVFILT_READ, EVFILT_WRITE (one epoll registration per fd, the kevent filters are tracked here, since
// epoll cannot tell them apart and kqueue reports ident = fd, data, EV_EOF and the per-filter udata) and EVFILT_USER
// (libuv's uv_async: triggered flag per ident, woken through an eventfd that is part of the epoll set).
// EVFILT_PROC (NOTE_EXIT[|NOTE_EXITSTATUS] only) through a pidfd, EVFILT_TIMER through a timerfd, EVFILT_SIGNAL ("aux" entries,
// own host fd >= 1000 in the epoll set, tagged with bit 63 in the epoll data).
// Other filters (VNODE/SIGNAL/...) fail with ENOTSUP (reported in the receipt when EV_RECEIPT is set).
static constexpr uint16_t DARWIN_EV_ONESHOT  = 0x0010;
static constexpr uint16_t DARWIN_EV_CLEAR    = 0x0020;
static constexpr uint16_t DARWIN_EV_DISPATCH = 0x0080;
static constexpr uint16_t DARWIN_EV_EOF      = 0x8000;
static constexpr uint32_t DARWIN_NOTE_TRIGGER = 0x01000000;
static constexpr uint32_t DARWIN_NOTE_FFCTRLMASK = 0xc0000000;
static constexpr uint32_t DARWIN_NOTE_FFLAGSMASK = 0x00ffffff;

struct KqEntry { void* udata; uint16_t flags; bool disabled; };
struct KqUser { void* udata; uint16_t flags; uint32_t fflags; bool triggered, disabled; };
struct KqAux { int16_t filter; uint64_t ident; void* udata; uint16_t flags; uint32_t fflags; int hfd; bool disabled; int sig_slot; };
struct KqState {
    int evfd = -1;                                            // wakes epoll_wait for EVFILT_USER triggers
    std::unordered_map<int, KqEntry> rd, wr;                  // fd -> registration
    std::unordered_map<uint64_t, KqUser> user;
    std::unordered_map<uint64_t, KqAux> aux;                  // id -> EVFILT_PROC / EVFILT_TIMER registration
    uint64_t next_aux = 1;
};
static constexpr int16_t  DARWIN_EVFILT_PROC  = -5;
static constexpr int16_t  DARWIN_EVFILT_SIGNAL = -6;
// EVFILT_SIGNAL: the host signal handler counts deliveries in these slots and pokes the registration's eventfd
// (async-signal-safe: atomics and write). Signals the guest ignores never reach the handler and are not counted.
struct KqSigSlot { std::atomic<int> sig{0}; int evfd = -1; std::atomic<uint64_t> count{0}; };
static KqSigSlot g_kq_sig[64];
static void kq_signal_observer(int sig, int code) {
    if (code == SI_TKILL) return;   // as on macOS: thread-directed signals (raise, pthread_kill) are not counted
    for (KqSigSlot& s : g_kq_sig) {
        if (s.sig.load(std::memory_order_acquire) != sig) continue;
        s.count.fetch_add(1);
        uint64_t one = 1;
        if (write(s.evfd, &one, 8) < 0) {}
    }
}
static constexpr int16_t  DARWIN_EVFILT_TIMER = -7;
static constexpr uint32_t DARWIN_NOTE_EXIT = 0x80000000u, DARWIN_NOTE_EXITSTATUS = 0x04000000u;
static constexpr uint64_t kKqAuxTag = 1ull << 63;

static void kq_aux_drop(int kq, KqState& st, std::unordered_map<uint64_t, KqAux>::iterator it) {
    if (it->second.sig_slot >= 0) g_kq_sig[it->second.sig_slot].sig.store(0, std::memory_order_release);
    epoll_ctl(kq, EPOLL_CTL_DEL, it->second.hfd, nullptr);
    close(it->second.hfd);
    st.aux.erase(it);
}
static int kq_hi_fd(int fd) {                                 // keep XEF's fds out of the guest's range
    if (fd < 0 || fd >= 1000) return fd;
    int hi = fcntl(fd, F_DUPFD_CLOEXEC, 1000);
    close(fd);
    return hi;
}
static bool kq_timer_arm(int tfd, const darwin_kevent_t& kev) {
    // data in NOTE_SECONDS(1) / NOTE_USECONDS(2) / NOTE_NSECONDS(4) / NOTE_MACHTIME(0x100), milliseconds by default;
    // NOTE_ABSOLUTE(8): absolute deadline (gettimeofday based), fires once
    int64_t v = kev.data < 0 ? 0 : (int64_t)kev.data, ns;
    uint32_t f = kev.fflags;
    if (f & 1) ns = v * 1000000000; else if (f & 2) ns = v * 1000; else if (f & (4 | 0x100)) ns = v; else ns = v * 1000000;
    struct itimerspec its;
    memset(&its, 0, sizeof its);
    if (f & 8) {
        its.it_value.tv_sec = ns / 1000000000; its.it_value.tv_nsec = ns % 1000000000;
        if (!its.it_value.tv_sec && !its.it_value.tv_nsec) its.it_value.tv_nsec = 1;
        return timerfd_settime(tfd, TFD_TIMER_ABSTIME, &its, nullptr) == 0;
    }
    if (ns <= 0) ns = 1;
    its.it_value.tv_sec = ns / 1000000000; its.it_value.tv_nsec = ns % 1000000000;
    if (!(kev.flags & DARWIN_EV_ONESHOT)) its.it_interval = its.it_value;
    return timerfd_settime(tfd, 0, &its, nullptr) == 0;
}
static int kq_apply_aux(int kq, KqState& st, const darwin_kevent_t& kev) {
    auto it = st.aux.begin();
    for (; it != st.aux.end(); ++it)
        if (it->second.filter == kev.filter && it->second.ident == kev.ident) break;
    if (kev.flags & DARWIN_EV_DELETE) {
        if (it == st.aux.end()) return ENOENT;
        kq_aux_drop(kq, st, it);
        return 0;
    }
    if (kev.flags & DARWIN_EV_ADD) {
        if (it == st.aux.end()) {
            int hfd;
            int slot = -1;
            if (kev.filter == DARWIN_EVFILT_PROC) {
                if (!(kev.fflags & DARWIN_NOTE_EXIT)) return ENOTSUP;     // FORK/EXEC/SIGNAL tracking is not emulated
                hfd = (int)syscall(SYS_pidfd_open, (pid_t)kev.ident, 0);
                if (hfd < 0) return errno == EINVAL ? ESRCH : errno;
            } else if (kev.filter == DARWIN_EVFILT_SIGNAL) {
                int lsig = darwin_to_linux_sig((int)kev.ident);
                if (lsig <= 0 || lsig >= 64) return EINVAL;
                hfd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
                if (hfd < 0) return errno;
                hfd = kq_hi_fd(hfd);
                for (int i = 0; i < 64; i++) if (g_kq_sig[i].sig.load() == 0) { slot = i; break; }
                if (slot < 0) { close(hfd); return ENOMEM; }
                g_signal_observer = kq_signal_observer;
                g_kq_sig[slot].evfd = hfd;
                g_kq_sig[slot].count.store(0);
                g_kq_sig[slot].sig.store(lsig, std::memory_order_release);
            } else {
                hfd = timerfd_create((kev.fflags & 8) ? CLOCK_REALTIME : CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
                if (hfd < 0) return errno;
            }
            hfd = kq_hi_fd(hfd);
            if (hfd < 0) return EMFILE;
            uint64_t id = st.next_aux++;
            struct epoll_event e;
            memset(&e, 0, sizeof e);
            e.events = EPOLLIN;
            e.data.u64 = kKqAuxTag | id;
            if (epoll_ctl(kq, EPOLL_CTL_ADD, hfd, &e) < 0) { int er = errno; close(hfd); return er; }
            it = st.aux.emplace(id, KqAux{kev.filter, (uint64_t)kev.ident, kev.udata, kev.flags, kev.fflags, hfd, false, slot}).first;
        } else {
            it->second.udata = kev.udata; it->second.flags = kev.flags; it->second.fflags = kev.fflags;
        }
        if (kev.filter == DARWIN_EVFILT_TIMER && !kq_timer_arm(it->second.hfd, kev)) { int er = errno; kq_aux_drop(kq, st, it); return er; }
    } else if (it == st.aux.end()) {
        return ENOENT;
    }
    if (kev.flags & DARWIN_EV_DISABLE) it->second.disabled = true;
    if (kev.flags & DARWIN_EV_ENABLE) it->second.disabled = false;
    return 0;
}
static std::unordered_map<int, KqState> g_kq;

static void kq_sync_epoll(int kq, KqState& st, int fd) {      // make the epoll registration of fd match rd/wr
    uint32_t ev = 0;
    auto r = st.rd.find(fd), w = st.wr.find(fd);
    bool et = false;
    if (r != st.rd.end() && !r->second.disabled) { ev |= EPOLLIN | EPOLLRDHUP; et |= !!(r->second.flags & DARWIN_EV_CLEAR); }
    if (w != st.wr.end() && !w->second.disabled) { ev |= EPOLLOUT; et |= !!(w->second.flags & DARWIN_EV_CLEAR); }
    struct epoll_event e;
    memset(&e, 0, sizeof e);
    e.data.u64 = (uint64_t)fd;
    e.events = ev | (et ? EPOLLET : 0);
    if (!ev) { epoll_ctl(kq, EPOLL_CTL_DEL, fd, &e); return; }
    if (epoll_ctl(kq, EPOLL_CTL_MOD, fd, &e) < 0 && errno == ENOENT) epoll_ctl(kq, EPOLL_CTL_ADD, fd, &e);
}

// A kqueue fd duplicated with dup/F_DUPFD (tokio/mio's Selector::try_clone) names the same kqueue: such fds are
// recognized as aliases of the fd the state is kept under (kcmp: the same open file description).
static std::unordered_map<int, int> g_kq_alias;
static bool same_file(int a, int b) { return syscall(SYS_kcmp, getpid(), getpid(), 0 /*KCMP_FILE*/, a, b) == 0; }
static std::unordered_map<int, KqState>::iterator kq_lookup(int kq) {   // g_kq_lock held
    auto it = g_kq.find(kq);
    if (it != g_kq.end()) return it;
    auto a = g_kq_alias.find(kq);
    if (a != g_kq_alias.end()) {
        it = g_kq.find(a->second);
        if (it != g_kq.end() && same_file(kq, a->second)) return it;
        g_kq_alias.erase(a);
    }
    struct stat sb;
    if (fstat(kq, &sb) != 0) return g_kq.end();
    for (it = g_kq.begin(); it != g_kq.end(); ++it)
        if (same_file(kq, it->first)) { g_kq_alias[kq] = it->first; return it; }
    // the fd the state is kept under was closed: find the epoll by the private eventfd registered in it (fdinfo
    // "tfd:" lines) and keep the state under this fd from now on
    FILE* f = fopen(("/proc/self/fdinfo/" + std::to_string(kq)).c_str(), "r");
    if (!f) return g_kq.end();
    char line[256];
    std::vector<int> tfds;
    while (fgets(line, sizeof line, f)) { int t; if (sscanf(line, "tfd: %d", &t) == 1) tfds.push_back(t); }
    fclose(f);
    for (it = g_kq.begin(); it != g_kq.end(); ++it) {
        bool mine = false;
        for (int t : tfds) mine |= t == it->second.evfd;
        if (!mine || fcntl(it->first, F_GETFD) >= 0 && same_file(it->first, kq)) continue;
        KqState moved = std::move(it->second);
        int old_fd = it->first;
        g_kq.erase(it);
        for (auto& a : g_kq_alias) if (a.second == old_fd) a.second = kq;
        return g_kq.emplace(kq, std::move(moved)).first;
    }
    return g_kq.end();
}

static int darwin_kqueue() {
    int epfd = epoll_create1(EPOLL_CLOEXEC);
    XEF_LOG(2, "darwin_kqueue() = %d", epfd);
    if (epfd < 0) return -1;
    int evfd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (evfd < 0) { close(epfd); return -1; }
    struct epoll_event e;
    memset(&e, 0, sizeof e);
    e.events = EPOLLIN;
    e.data.u64 = ~0ull;
    epoll_ctl(epfd, EPOLL_CTL_ADD, evfd, &e);
    std::lock_guard<std::mutex> lk(g_kq_lock);
    // the fd number of a closed kqueue is reused: its state moves to a surviving duplicate, if any, else it is replaced
    for (auto a = g_kq_alias.begin(); a != g_kq_alias.end();) {
        if (a->second != epfd) { ++a; continue; }
        int dup_fd = a->first;
        a = g_kq_alias.erase(a);
        auto old = g_kq.find(epfd);
        if (old != g_kq.end() && fcntl(dup_fd, F_GETFD) >= 0 && !g_kq.count(dup_fd)) {
            KqState moved = std::move(old->second);
            g_kq.erase(old);
            g_kq[dup_fd] = std::move(moved);
            for (auto& b : g_kq_alias) if (b.second == epfd) b.second = dup_fd;
        }
    }
    KqState& st = g_kq[epfd];
    if (st.evfd >= 0) close(st.evfd);
    for (auto& [id, a] : st.aux) { if (a.sig_slot >= 0) g_kq_sig[a.sig_slot].sig.store(0); close(a.hfd); }
    st = KqState();
    st.evfd = evfd;
    return epfd;
}

static int kq_apply_change(int kq, KqState& st, const darwin_kevent_t& kev) {   // returns 0 or an errno
    if (kev.filter == DARWIN_EVFILT_USER) {
        KqUser& u = st.user[kev.ident];
        if (kev.flags & DARWIN_EV_DELETE) { st.user.erase(kev.ident); return 0; }
        if (kev.flags & DARWIN_EV_ADD) { u.udata = kev.udata; u.flags = kev.flags; }
        if (kev.flags & DARWIN_EV_DISABLE) u.disabled = true;
        if (kev.flags & DARWIN_EV_ENABLE) u.disabled = false;
        uint32_t ctl = kev.fflags & DARWIN_NOTE_FFCTRLMASK, v = kev.fflags & DARWIN_NOTE_FFLAGSMASK;
        if (ctl == 0x80000000u) u.fflags &= v; else if (ctl == 0xc0000000u) u.fflags |= v;   // NOTE_FFAND / NOTE_FFOR
        else if (ctl == 0x40000000u) u.fflags = v;                                         // NOTE_FFCOPY
        if (kev.fflags & DARWIN_NOTE_TRIGGER) {
            u.triggered = true;
            uint64_t one = 1;
            if (write(st.evfd, &one, 8) < 0) {}
        }
        return 0;
    }
    if (kev.filter == DARWIN_EVFILT_PROC || kev.filter == DARWIN_EVFILT_TIMER || kev.filter == DARWIN_EVFILT_SIGNAL)
        return kq_apply_aux(kq, st, kev);
    if (kev.filter != DARWIN_EVFILT_READ && kev.filter != DARWIN_EVFILT_WRITE) return ENOTSUP;
    int fd = (int)kev.ident;
    auto& tab = kev.filter == DARWIN_EVFILT_READ ? st.rd : st.wr;
    if (kev.flags & DARWIN_EV_DELETE) {
        if (!tab.erase(fd)) return ENOENT;
        kq_sync_epoll(kq, st, fd);
        return 0;
    }
    if (kev.flags & DARWIN_EV_ADD) {
        tab[fd] = KqEntry{kev.udata, kev.flags, (kev.flags & DARWIN_EV_DISABLE) != 0};
        if (fcntl(fd, F_GETFD) < 0) { tab.erase(fd); return EBADF; }
    } else if (tab.find(fd) == tab.end()) {
        return ENOENT;
    }
    if (kev.flags & DARWIN_EV_DISABLE) tab[fd].disabled = true;
    if (kev.flags & DARWIN_EV_ENABLE) tab[fd].disabled = false;
    kq_sync_epoll(kq, st, fd);
    return 0;
}

static long darwin_kevent(int kq, const darwin_kevent_t* changelist, int nchanges,
                         darwin_kevent_t* eventlist, int nevents, const struct timespec* timeout) {
    XEF_LOG(2, "darwin_kevent(kq=%d, nchanges=%d, nevents=%d, timeout=%p)", kq, nchanges, nevents, timeout);
    int out = 0;
    {
        std::lock_guard<std::mutex> lk(g_kq_lock);
        auto it = kq_lookup(kq);
        if (it == g_kq.end()) { errno = EBADF; return -1; }
        KqState& st = it->second;
        for (int i = 0; i < nchanges && changelist; i++) {
            const darwin_kevent_t& kev = changelist[i];
            XEF_LOG(2, "  change[%d]: ident=%lu, filter=%d, flags=%#x, fflags=%#x, data=%ld, udata=%p", i,
                    (unsigned long)kev.ident, (int)kev.filter, (unsigned)kev.flags, (unsigned)kev.fflags, (long)kev.data, kev.udata);
            int err = kq_apply_change(kq, st, kev);
            if (err && !(kev.flags & DARWIN_EV_RECEIPT) && out >= nevents) { errno = err; return -1; }
            if (((kev.flags & DARWIN_EV_RECEIPT) || err) && eventlist && out < nevents) {
                darwin_kevent_t& rec = eventlist[out++];
                rec = kev;
                rec.flags = (uint16_t)((kev.flags & ~DARWIN_EV_RECEIPT) | DARWIN_EV_ERROR);
                rec.data = err;
            }
        }
    }
    if (out > 0) return out;                                   // receipts / change errors are returned without waiting
    if (nevents <= 0 || !eventlist) return 0;

    int timeout_ms = -1;
    if (timeout) timeout_ms = (int)std::min<int64_t>((int64_t)timeout->tv_sec * 1000 + (timeout->tv_nsec + 999999) / 1000000, INT32_MAX);

    std::vector<struct epoll_event> ep(std::min(nevents, 1024));
    int nfds = epoll_wait(kq, ep.data(), (int)ep.size(), timeout_ms);
    if (nfds < 0) return -1;

    std::lock_guard<std::mutex> lk(g_kq_lock);
    auto it = kq_lookup(kq);
    if (it == g_kq.end()) return 0;
    KqState& st = it->second;
    auto emit = [&](uint64_t ident, int16_t filter, uint16_t flags, uint32_t fflags, int64_t data, void* udata) {
        if (out >= nevents) return;
        darwin_kevent_t& k = eventlist[out++];
        memset(&k, 0, sizeof k);
        k.ident = ident; k.filter = filter; k.flags = flags; k.fflags = fflags; k.data = data; k.udata = udata;
    };
    for (int i = 0; i < nfds; i++) {
        if (ep[i].data.u64 == ~0ull) {                         // EVFILT_USER wake-up
            uint64_t v;
            if (read(st.evfd, &v, 8) < 0) {}
            for (auto& [id, u] : st.user)
                if (u.triggered && !u.disabled) {
                    emit(id, DARWIN_EVFILT_USER, (uint16_t)(u.flags & ~(DARWIN_EV_ADD | DARWIN_EV_DELETE)), u.fflags, 0, u.udata);
                    if (u.flags & (DARWIN_EV_CLEAR | DARWIN_EV_ONESHOT | DARWIN_EV_DISPATCH)) u.triggered = false;
                }
            continue;
        }
        if (ep[i].data.u64 & kKqAuxTag) {
            auto a = st.aux.find(ep[i].data.u64 & ~kKqAuxTag);
            if (a == st.aux.end() || a->second.disabled) continue;
            KqAux& x = a->second;
            uint16_t fl = (uint16_t)(x.flags & ~(DARWIN_EV_ADD | DARWIN_EV_DELETE));
            if (x.filter == DARWIN_EVFILT_PROC) {
                // NOTE_EXIT: the knote goes away with the process; data = wait status with NOTE_EXITSTATUS
                siginfo_t si;
                memset(&si, 0, sizeof si);
                int64_t data = 0;
                if ((x.fflags & DARWIN_NOTE_EXITSTATUS) &&
                    waitid((idtype_t)3 /*P_PIDFD*/, (id_t)x.hfd, &si, WEXITED | WNOWAIT | WNOHANG) == 0 && si.si_pid) {
                    int sig = si.si_code == CLD_EXITED ? 0 : linux_to_darwin_sig(si.si_status);
                    data = si.si_code == CLD_EXITED ? (si.si_status & 0xff) << 8 : (sig | (si.si_code == CLD_DUMPED ? 0x80 : 0));
                }
                emit(x.ident, x.filter, fl | DARWIN_EV_EOF, x.fflags & (DARWIN_NOTE_EXIT | DARWIN_NOTE_EXITSTATUS), data, x.udata);
                kq_aux_drop(kq, st, a);
                continue;
            }
            uint64_t n = 0;
            if (read(x.hfd, &n, 8) != 8 || !n) continue;
            if (x.filter == DARWIN_EVFILT_SIGNAL) n = g_kq_sig[x.sig_slot].count.exchange(0);   // deliveries since last
            if (!n) continue;
            emit(x.ident, x.filter, fl, 0, (int64_t)n, x.udata);
            if (x.flags & DARWIN_EV_ONESHOT) kq_aux_drop(kq, st, a);
            else if (x.flags & DARWIN_EV_DISPATCH) x.disabled = true;
            continue;
        }
        int fd = (int)ep[i].data.u64;
        uint32_t e = ep[i].events;
        bool hup = e & (EPOLLHUP | EPOLLRDHUP), err = e & EPOLLERR;
        auto r = st.rd.find(fd);
        if (r != st.rd.end() && !r->second.disabled && (e & (EPOLLIN | EPOLLHUP | EPOLLRDHUP | EPOLLERR))) {
            int avail = 0;
            if (ioctl(fd, FIONREAD, &avail) < 0) avail = 0;
            emit((uint64_t)fd, DARWIN_EVFILT_READ, (uint16_t)((r->second.flags & ~(DARWIN_EV_ADD | DARWIN_EV_DELETE)) | (hup && !avail ? DARWIN_EV_EOF : 0)),
                 0, avail, r->second.udata);
            if (r->second.flags & DARWIN_EV_ONESHOT) { st.rd.erase(r); kq_sync_epoll(kq, st, fd); }
            else if (r->second.flags & DARWIN_EV_DISPATCH) { r->second.disabled = true; kq_sync_epoll(kq, st, fd); }
        }
        auto w = st.wr.find(fd);
        if (w != st.wr.end() && !w->second.disabled && (e & (EPOLLOUT | EPOLLHUP | EPOLLERR))) {
            emit((uint64_t)fd, DARWIN_EVFILT_WRITE, (uint16_t)((w->second.flags & ~(DARWIN_EV_ADD | DARWIN_EV_DELETE)) | (hup || err ? DARWIN_EV_EOF : 0)),
                 0, 65536, w->second.udata);
            if (w->second.flags & DARWIN_EV_ONESHOT) { st.wr.erase(w); kq_sync_epoll(kq, st, fd); }
            else if (w->second.flags & DARWIN_EV_DISPATCH) { w->second.disabled = true; kq_sync_epoll(kq, st, fd); }
        }
    }
    return out;
}

// Darwin fcntl commands
static constexpr int DARWIN_F_DUPFD_CLOEXEC = 67;
static constexpr int DARWIN_F_SETNOSIGPIPE  = 73;
static constexpr int DARWIN_F_GETNOSIGPIPE  = 74;

static int darwin_fcntl(int fd, int cmd, uint64_t arg) {
    int host_cmd = cmd;
    if (cmd == DARWIN_F_DUPFD_CLOEXEC) {
        host_cmd = F_DUPFD_CLOEXEC;
    } else if (cmd == DARWIN_F_SETNOSIGPIPE || cmd == DARWIN_F_GETNOSIGPIPE) {
        return 0; // Simulated no-op
    }
    int res = fcntl(fd, host_cmd, (intptr_t)arg);
    XEF_LOG(2, "darwin_fcntl(fd=%d, cmd=%d -> %d, arg=%#lx) = %d (errno=%d)",
            fd, cmd, host_cmd, (unsigned long)arg, res, errno);
    return res;
}

// ---- variadic fcntl / open / ioctl (Darwin passes the extra argument on the stack) ----------------------------
static int linux_flags_to_darwin_fl(int lf) {
    int d = lf & 3;                 // O_RDONLY/O_WRONLY/O_RDWR are 0/1/2 on both
    if (lf & O_NONBLOCK) d |= 0x0004;
    if (lf & O_APPEND)   d |= 0x0008;
    if (lf & O_ASYNC)    d |= 0x0040;
    if (lf & O_SYNC)     d |= 0x0080;
    return d;
}
struct DarwinFlock { int64_t l_start; int64_t l_len; int32_t l_pid; int16_t l_type; int16_t l_whence; };
static long darwin_fcntl_v(int fd, int cmd, const uint64_t* ap) {
    uint64_t arg = ap ? ap[0] : 0;
    switch (cmd) {
        case 0: return fcntl(fd, F_DUPFD, (int)arg);
        case 67: return fcntl(fd, F_DUPFD_CLOEXEC, (int)arg);
        case 1: return fcntl(fd, F_GETFD);
        case 2: return fcntl(fd, F_SETFD, (int)arg);
        case 3: { int r = fcntl(fd, F_GETFL); return r < 0 ? r : linux_flags_to_darwin_fl(r); }
        case 4: { int lf = darwin_open_flags_to_linux((int)arg) & ~(O_ACCMODE | O_CREAT | O_TRUNC | O_EXCL); return fcntl(fd, F_SETFL, lf); }
        case 5: return fcntl(fd, F_GETOWN);
        case 6: return fcntl(fd, F_SETOWN, (int)arg);
        case 7: case 8: case 9: {      // F_GETLK / F_SETLK / F_SETLKW
            DarwinFlock* df = (DarwinFlock*)(uintptr_t)arg;
            struct flock fl;
            memset(&fl, 0, sizeof fl);
            fl.l_start = df->l_start; fl.l_len = df->l_len; fl.l_pid = df->l_pid;
            fl.l_type = df->l_type == 1 ? F_RDLCK : df->l_type == 2 ? F_UNLCK : F_WRLCK;   // Darwin RDLCK=1 UNLCK=2 WRLCK=3
            fl.l_whence = df->l_whence;
            int r = fcntl(fd, cmd == 7 ? F_GETLK : cmd == 8 ? F_SETLK : F_SETLKW, &fl);
            if (cmd == 7 && r == 0) {
                df->l_start = fl.l_start; df->l_len = fl.l_len; df->l_pid = fl.l_pid;
                df->l_type = fl.l_type == F_RDLCK ? 1 : fl.l_type == F_UNLCK ? 2 : 3;
            }
            return r;
        }
        case 50: {                     // F_GETPATH
            char link[64], buf[4096];
            snprintf(link, sizeof link, "/proc/self/fd/%d", fd);
            ssize_t n = readlink(link, buf, sizeof buf - 1);
            if (n < 0) return -1;
            buf[n] = 0;
            strncpy((char*)(uintptr_t)arg, buf, 1024);
            return 0;
        }
        case 51: return fsync(fd);     // F_FULLFSYNC
        case 48: case 45: case 42: case 43: case 44: case 73: case 74: return 0;   // NOCACHE, RDAHEAD, PREALLOCATE, SETSIZE..., NOSIGPIPE
        default: errno = EINVAL; return -1;
    }
}
static int darwin_open_v(const char* path, int dflags, const uint64_t* ap) {
    mode_t mode = (dflags & 0x200) ? (mode_t)(ap ? ap[0] : 0) : 0;     // O_CREAT
    return darwin_open(path, dflags, mode);
}
static int darwin_openat_v(int dfd, const char* path, int dflags, const uint64_t* ap) {
    mode_t mode = (dflags & 0x200) ? (mode_t)(ap ? ap[0] : 0) : 0;
    if (dfd == -2) dfd = AT_FDCWD;     // Darwin AT_FDCWD
    return darwin_openat(dfd, path, dflags, mode);
}
static int darwin_isatty(int fd) { return isatty(fd); }
struct DarwinWinsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
static int darwin_ioctl_v(int fd, unsigned long req, const uint64_t* ap) {
    void* arg = ap ? (void*)(uintptr_t)ap[0] : nullptr;
    int tret;
    if (darwin_termios_ioctl(fd, req & 0xffffffffu, arg, &tret)) return tret;
    switch (req) {
        case 0x40087468: { struct winsize w; if (ioctl(fd, TIOCGWINSZ, &w)) return -1; DarwinWinsize* d = (DarwinWinsize*)arg; d->ws_row = w.ws_row; d->ws_col = w.ws_col; d->ws_xpixel = w.ws_xpixel; d->ws_ypixel = w.ws_ypixel; return 0; }
        case 0x4004667f: return ioctl(fd, FIONREAD, arg);                  // FIONREAD
        case 0x8004667e: return ioctl(fd, FIONBIO, arg);                   // FIONBIO
        case 0x20006601: return ioctl(fd, FIOCLEX);                        // FIOCLEX
        case 0x20006602: return ioctl(fd, FIONCLEX);                       // FIONCLEX
        case 0x402c7413: {                                                 // TIOCGETA of the 32-bit termios: "is a tty"
            if (!isatty(fd)) { errno = ENOTTY; return -1; }
            memset(arg, 0, 44);
            return 0;
        }
        default: errno = ENOTTY; return -1;
    }
}

// setjmp family as guest arm64 code (a host setjmp would save the host's registers). jmp_buf as in libplatform:
// x19..x28 @0, fp/lr @0x50, sp @0x60, d8..d15 @0x70, signal mask @0xB0, "mask saved" flag @0xB8. The mask goes
// through the Darwin sigprocmask shim (an HLE thunk called with BLR).
static void emit_setjmp_family() {
    void* spm = darwin_signal_lookup("_sigprocmask");
    if (!spm) return;
    uint32_t mask_id = (uint32_t)g_thunks.size();
    g_thunks.push_back({"__xef_setjmp_sigprocmask", spm});
    uint32_t* mt = (uint32_t*)(g_thunk_code + g_thunk_code_used);
    g_thunk_code_used += 16;
    mt[0] = 0xd2800000u | ((mask_id & 0xffffu) << 5) | 17u;
    mt[1] = 0xd4400000u | (kThunkHlt << 5);
    mt[2] = 0xd65f03c0u;
    mt[3] = 0xd503201fu;
    uint64_t mask_thunk = (uint64_t)(uintptr_t)mt;

    uint32_t* base = (uint32_t*)(g_thunk_code + g_thunk_code_used);
    uint32_t* c = base;
    auto stp = [](int t, int t2, int n, int off) { return 0xA9000000u | ((uint32_t)(off / 8 & 0x7f) << 15) | (t2 << 10) | (n << 5) | t; };
    auto ldp = [&](int t, int t2, int n, int off) { return stp(t, t2, n, off) | 0x00400000u; };
    auto stpd = [](int t, int t2, int n, int off) { return 0x6D000000u | ((uint32_t)(off / 8 & 0x7f) << 15) | (t2 << 10) | (n << 5) | t; };
    auto ldpd = [&](int t, int t2, int n, int off) { return stpd(t, t2, n, off) | 0x00400000u; };
    auto strx = [](int t, int n, int off) { return 0xF9000000u | ((uint32_t)(off / 8) << 10) | (n << 5) | t; };
    auto ldrx = [&](int t, int n, int off) { return strx(t, n, off) | 0x00400000u; };
    auto strw = [](int t, int n, int off) { return 0xB9000000u | ((uint32_t)(off / 4) << 10) | (n << 5) | t; };
    auto ldrw = [&](int t, int n, int off) { return strw(t, n, off) | 0x00400000u; };
    auto movx = [](int d, int m) { return 0xAA0003E0u | (m << 16) | d; };
    auto movz = [](int d, int imm) { return 0xD2800000u | (imm << 5) | d; };
    auto addi = [](int d, int n, int imm) { return 0x91000000u | (imm << 10) | (n << 5) | d; };
    const uint32_t kRet = 0xD65F03C0u, kBlr16 = 0xD63F0000u | (16 << 5);
    std::vector<std::pair<uint32_t*, int>> lits;   // ldr x16, =mask_thunk fixups
    auto save_regs = [&]() {
        for (int r = 19, o = 0; r <= 27; r += 2, o += 16) *c++ = stp(r, r + 1, 0, o);
        *c++ = stp(29, 30, 0, 0x50);
        *c++ = addi(2, 31, 0);       // mov x2, sp
        *c++ = strx(2, 0, 0x60);
        for (int r = 8, o = 0x70; r <= 14; r += 2, o += 16) *c++ = stpd(r, r + 1, 0, o);
    };
    auto call_mask = [&]() { lits.push_back({c, 16}); *c++ = 0x58000000u | 16; *c++ = kBlr16; };

    // setjmp(env): registers + current mask
    uint32_t* p_setjmp = c;
    save_regs();
    *c++ = movx(19, 0);
    *c++ = movz(0, 1);                 // SIG_BLOCK
    *c++ = movz(1, 0);                 // set = NULL
    *c++ = addi(2, 19, 0xB0);          // oset = &env[0xB0]
    call_mask();
    *c++ = 0x52800021u;                // mov w1, #1
    *c++ = strw(1, 19, 0xB8);
    *c++ = movx(0, 19);
    *c++ = ldrx(19, 0, 0);
    *c++ = ldrx(30, 0, 0x58);
    *c++ = movz(0, 0);
    *c++ = kRet;
    // _setjmp(env): registers only
    uint32_t* p__setjmp = c;
    save_regs();
    *c++ = strw(31, 0, 0xB8);          // str wzr: no mask saved
    *c++ = movz(0, 0);
    *c++ = kRet;
    // sigsetjmp(env, savemask)
    uint32_t* p_sigsetjmp = c;
    *c = 0x34000000u | ((uint32_t)((p__setjmp - c) & 0x7ffff) << 5) | 1;   // cbz w1, _setjmp
    c++;
    *c = 0x14000000u | ((uint32_t)(p_setjmp - c) & 0x3ffffff);              // b setjmp
    c++;
    // longjmp(env, val) / siglongjmp: restore the mask if setjmp saved it
    uint32_t* p_longjmp = c;
    *c++ = ldrw(2, 0, 0xB8);
    uint32_t* cbz_restore = c++;
    *c++ = movx(19, 0);
    *c++ = movx(20, 1);
    *c++ = movz(0, 3);                 // SIG_SETMASK
    *c++ = addi(1, 19, 0xB0);
    *c++ = movz(2, 0);
    call_mask();
    *c++ = movx(0, 19);
    *c++ = movx(1, 20);
    // _longjmp(env, val)
    uint32_t* p__longjmp = c;
    *cbz_restore = 0x34000000u | ((uint32_t)((p__longjmp - cbz_restore) & 0x7ffff) << 5) | 2;   // cbz w2
    for (int r = 19, o = 0; r <= 27; r += 2, o += 16) *c++ = ldp(r, r + 1, 0, o);
    *c++ = ldp(29, 30, 0, 0x50);
    *c++ = ldrx(2, 0, 0x60);
    *c++ = addi(31, 2, 0);             // mov sp, x2
    for (int r = 8, o = 0x70; r <= 14; r += 2, o += 16) *c++ = ldpd(r, r + 1, 0, o);
    *c++ = 0x7100003Fu | (1 << 5);     // cmp w1, #0
    *c++ = 0x1A800400u | (31u << 16) | (1u << 12) | (1u << 5);   // csinc w0, w1, wzr, ne  (val 0 -> 1)
    *c++ = kRet;
    // literal pool (8-byte aligned)
    if ((uintptr_t)c & 7) *c++ = 0xd503201fu;
    uint64_t* lit = (uint64_t*)c;
    *lit = mask_thunk;
    c += 2;
    for (auto& [at, reg] : lits) *at = 0x58000000u | ((uint32_t)(((uint32_t*)lit - at) & 0x7ffff) << 5) | (uint32_t)reg;
    g_thunk_code_used += ((uint8_t*)c - (uint8_t*)base + 15) & ~(size_t)15;

    auto reg = [&](const char* n, uint32_t* at) { g_symbol_cache[n] = (uint64_t)(uintptr_t)at; };
    reg("_setjmp", p_setjmp); reg("__setjmp", p__setjmp); reg("_sigsetjmp", p_sigsetjmp);
    reg("_longjmp", p_longjmp); reg("__longjmp", p__longjmp); reg("_siglongjmp", p_longjmp);
}

void darwin_hle_init() {
    std::lock_guard<std::mutex> lk(g_hle_lock);
    if (g_thunk_code) return;

    // Allocate executable memory for ARM64 stubs
    void* p = mmap(nullptr, kThunkCodeSize, PROT_READ | PROT_WRITE | PROT_EXEC,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) fatal("darwin_hle_init: cannot allocate thunk memory");
    g_thunk_code = (uint8_t*)p;
    g_thunk_code_used = 0;

    g_guest_stdin  = stdin;
    g_guest_stdout = stdout;
    g_guest_stderr = stderr;

    init_rune_locale();
    if (getenv("XEF_LINEBUF")) setvbuf(stdout, nullptr, _IOLBF, 0);   // debugging aid: see output while hung

    dlopen("libgcc_s.so.1", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("libpcre2-8.so.0", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("/home/wron4/Pulpit/OSXEMU/lib/usr/lib/libc++abi.so.1", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("/home/wron4/Pulpit/OSXEMU/lib/usr/lib/libc++.so.1", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("libc++abi.so.1", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("libedit.so.0", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("libz.so.1", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("libzstd.so.1", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("liblzma.so.5", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("libbz2.so.1", RTLD_GLOBAL | RTLD_LAZY);

    // Create default return-from-main exit trampoline (mov x16, #1; svc #0x80)
    uint8_t* exit_stub = g_thunk_code + g_thunk_code_used;
    g_thunk_code_used += 16;
    uint32_t* exit_insns = (uint32_t*)exit_stub;
    exit_insns[0] = 0xd2800030u; // mov x16, #1 (DARWIN_SYS_exit)
    exit_insns[1] = 0xd4001001u; // svc #0x80
    exit_insns[2] = 0xd503201fu; // nop
    exit_insns[3] = 0xd503201fu; // nop
    g_darwin_exit_trampoline = (uint64_t)(uintptr_t)exit_stub;

    // Create default return-from-thread exit trampoline (mov x16, #361; svc #0x80)
    uint8_t* thread_exit_stub = g_thunk_code + g_thunk_code_used;
    g_thunk_code_used += 16;
    uint32_t* thread_exit_insns = (uint32_t*)thread_exit_stub;
    thread_exit_insns[0] = 0xd2802d30u; // mov x16, #361 (DARWIN_SYS_bsdthread_terminate)
    thread_exit_insns[1] = 0xd4001001u; // svc #0x80
    thread_exit_insns[2] = 0xd4400000u; // hlt #0
    thread_exit_insns[3] = 0xd65f03c0u; // ret
    g_darwin_thread_exit_trampoline = (uint64_t)(uintptr_t)thread_exit_stub;

    // start stub: mov x17,#id ; hlt ; br x16 ; nop  (the host runs the initializers in between)
    uint8_t* start_stub = g_thunk_code + g_thunk_code_used;
    g_thunk_code_used += 16;
    uint32_t start_id = (uint32_t)g_thunks.size();
    g_thunks.push_back({"__xef_start", (void*)&darwin_start_marker});
    uint32_t* start_insns = (uint32_t*)start_stub;
    start_insns[0] = 0xd2800000u | ((start_id & 0xffffu) << 5) | 17u;
    start_insns[1] = 0xd4400000u | (kThunkHlt << 5);
    start_insns[2] = 0xd61f0200u;   // br x16
    start_insns[3] = 0xd503201fu;
    g_darwin_start_stub = (uint64_t)(uintptr_t)start_stub;

    // signal-return stub (16 bytes)
    uint8_t* sigret = g_thunk_code + g_thunk_code_used;
    g_thunk_code_used += 16;
    darwin_signals_init(sigret);
    emit_setjmp_family();
}

uint64_t darwin_hle_resolve_symbol(const char* name, bool is_weak, bool explicit_only) {
    if (!name || !name[0]) return 0;
    darwin_hle_init();

    // Host OpenGL (`_gl[A-Z]*`) and the window shim: before g_hle_lock (registration takes it) and before
    // the host-libc dlsym fallback, so libc names never reach glX
    if (uint64_t g = darwin_gl_resolve(name)) return g;

    std::lock_guard<std::mutex> lk(g_hle_lock);
    auto it = g_symbol_cache.find(name);
    if (it != g_symbol_cache.end()) {
        if (explicit_only && g_host_fallback_names.count(name)) return 0;
        return it->second;
    }

    if (void* d = darwin_stdio_data_lookup(name)) {
        g_symbol_cache[name] = (uint64_t)(uintptr_t)d;
        return (uint64_t)(uintptr_t)d;
    }
    if (void* d = darwin_fenv_data_lookup(name)) {
        g_symbol_cache[name] = (uint64_t)(uintptr_t)d;
        return (uint64_t)(uintptr_t)d;
    }
    if (void* d = darwin_stub_data_lookup(name)) {
        g_symbol_cache[name] = (uint64_t)(uintptr_t)d;
        return (uint64_t)(uintptr_t)d;
    }
    if (void* d = darwin_sys_data_lookup(name)) {
        g_symbol_cache[name] = (uint64_t)(uintptr_t)d;
        return (uint64_t)(uintptr_t)d;
    }
    // 1. Check special Darwin data variables
    if (strcmp(name, "___stack_chk_guard") == 0) {
        uint64_t addr = (uint64_t)(uintptr_t)&g_stack_chk_guard;
        g_symbol_cache[name] = addr;
        return addr;
    }
    if (strcmp(name, "___stdinp") == 0) {
        uint64_t addr = (uint64_t)(uintptr_t)&g_guest_stdin;
        g_symbol_cache[name] = addr;
        return addr;
    }
    if (strcmp(name, "___stdoutp") == 0) {
        uint64_t addr = (uint64_t)(uintptr_t)&g_guest_stdout;
        g_symbol_cache[name] = addr;
        return addr;
    }
    if (strcmp(name, "___stderrp") == 0) {
        uint64_t addr = (uint64_t)(uintptr_t)&g_guest_stderr;
        g_symbol_cache[name] = addr;
        return addr;
    }
    if (strcmp(name, "__DefaultRuneLocale") == 0 || strcmp(name, "_DefaultRuneLocale") == 0) {
        uint64_t addr = (uint64_t)(uintptr_t)&g_darwin_rune_locale;
        g_symbol_cache[name] = addr;
        return addr;
    }
    if (strcmp(name, "___CurrentRuneLocale") == 0 || strcmp(name, "__CurrentRuneLocale") == 0 || strcmp(name, "_CurrentRuneLocale") == 0) {
        uint64_t addr = (uint64_t)(uintptr_t)&g_darwin_current_rune_locale;
        g_symbol_cache[name] = addr;
        return addr;
    }
    if (strcmp(name, "_environ") == 0 || strcmp(name, "environ") == 0) {
        uint64_t addr = (uint64_t)(uintptr_t)&environ;
        g_symbol_cache[name] = addr;
        return addr;
    }
    if (strcmp(name, "_optarg") == 0 || strcmp(name, "optarg") == 0) {
        uint64_t addr = (uint64_t)(uintptr_t)&optarg;
        g_symbol_cache[name] = addr;
        return addr;
    }
    if (strcmp(name, "_optind") == 0 || strcmp(name, "optind") == 0) {
        uint64_t addr = (uint64_t)(uintptr_t)&optind;
        g_symbol_cache[name] = addr;
        return addr;
    }
    if (strcmp(name, "_opterr") == 0 || strcmp(name, "opterr") == 0) {
        uint64_t addr = (uint64_t)(uintptr_t)&opterr;
        g_symbol_cache[name] = addr;
        return addr;
    }
    if (strcmp(name, "_optopt") == 0 || strcmp(name, "optopt") == 0) {
        uint64_t addr = (uint64_t)(uintptr_t)&optopt;
        g_symbol_cache[name] = addr;
        return addr;
    }
    if (strcmp(name, "___chkstk_darwin") == 0) {
        if (g_thunk_code_used + 16 > kThunkCodeSize) {
            fatal("darwin_hle: thunk code buffer exhausted");
        }
        uint8_t* stub_ptr = g_thunk_code + g_thunk_code_used;
        g_thunk_code_used += 16;
        uint32_t* insns = (uint32_t*)stub_ptr;
        insns[0] = 0xd65f03c0u; // ret
        insns[1] = 0xd503201fu; // nop
        insns[2] = 0xd503201fu; // nop
        insns[3] = 0xd503201fu; // nop
        uint64_t guest_addr = (uint64_t)(uintptr_t)stub_ptr;
        g_symbol_cache[name] = guest_addr;
        return guest_addr;
    }

    // 2. Check special Darwin wrapper functions
    void* host_fn = nullptr;
    if (void* sio = darwin_stdio_lookup(name)) {
        host_fn = sio;
    } else if (void* pr = darwin_proc_lookup(name)) {
        host_fn = pr;
    } else if (void* tc = darwin_termios_lookup(name)) {
        host_fn = tc;
    } else if (void* fs = darwin_fs_lookup(name)) {
        host_fn = fs;
    } else if (void* fe = darwin_fenv_lookup(name)) {
        host_fn = fe;
    } else if (void* cc = darwin_commoncrypto_lookup(name)) {
        host_fn = cc;
    } else if (void* pt = darwin_pthread_lookup(name)) {
        host_fn = pt;
    } else if (strcmp(name, "___error") == 0) {
        host_fn = (void*)&darwin_error_wrapper;
    } else if (strcmp(name, "___stack_chk_fail") == 0) {
        host_fn = (void*)&darwin_stack_chk_fail_wrapper;
    } else if (strcmp(name, "___assert_rtn") == 0) {
        host_fn = (void*)&darwin_assert_rtn_wrapper;
    } else if (strcmp(name, "___maskrune") == 0) {
        host_fn = (void*)&darwin_maskrune_wrapper;
    } else if (strcmp(name, "_memcpy") == 0 || strcmp(name, "memcpy") == 0) {
        host_fn = (void*)&memmove;   // Darwin's memcpy is overlap-safe (same routine as memmove); glibc's is not
    } else if (strcmp(name, "___memcpy_chk") == 0) {
        host_fn = (void*)&darwin_memcpy_chk_wrapper;
    } else if (strcmp(name, "_atexit") == 0 || strcmp(name, "atexit") == 0) {
        host_fn = (void*)&darwin_atexit_wrapper;
    } else if (strcmp(name, "_memset_pattern16") == 0 || strcmp(name, "memset_pattern16") == 0) {
        host_fn = (void*)&darwin_memset_pattern16_wrapper;
    } else if (strcmp(name, "___exp10") == 0 || strcmp(name, "exp10") == 0) {
        host_fn = (void*)&darwin_exp10_wrapper;
    } else if (strcmp(name, "_pthread_key_create") == 0) {
        host_fn = (void*)&darwin_pthread_key_create;
    } else if (strcmp(name, "_pthread_setspecific") == 0) {
        host_fn = (void*)&darwin_pthread_setspecific;
    } else if (strcmp(name, "_pthread_getspecific") == 0) {
        host_fn = (void*)&darwin_pthread_getspecific;
    } else if (strcmp(name, "_pthread_key_delete") == 0) {
        host_fn = (void*)&darwin_pthread_key_delete;
    } else if (strcmp(name, "_pthread_mutex_init") == 0) {
        host_fn = (void*)&darwin_pthread_mutex_init;
    } else if (strcmp(name, "_pthread_mutex_lock") == 0) {
        host_fn = (void*)&darwin_pthread_mutex_lock;
    } else if (strcmp(name, "_pthread_mutex_trylock") == 0) {
        host_fn = (void*)&darwin_pthread_mutex_trylock;
    } else if (strcmp(name, "_pthread_mutex_unlock") == 0) {
        host_fn = (void*)&darwin_pthread_mutex_unlock;
    } else if (strcmp(name, "_pthread_mutex_destroy") == 0) {
        host_fn = (void*)&darwin_pthread_mutex_destroy;
    } else if (strcmp(name, "_pthread_cond_init") == 0) {
        host_fn = (void*)&darwin_pthread_cond_init;
    } else if (strcmp(name, "_pthread_cond_signal") == 0) {
        host_fn = (void*)&darwin_pthread_cond_signal;
    } else if (strcmp(name, "_pthread_cond_broadcast") == 0) {
        host_fn = (void*)&darwin_pthread_cond_broadcast;
    } else if (strcmp(name, "_pthread_cond_wait") == 0) {
        host_fn = (void*)&darwin_pthread_cond_wait;
    } else if (strcmp(name, "_pthread_cond_timedwait") == 0) {
        host_fn = (void*)&darwin_pthread_cond_timedwait;
    } else if (strcmp(name, "_pthread_cond_timedwait_relative_np") == 0) {
        host_fn = (void*)&darwin_pthread_cond_timedwait_relative_np;
    } else if (strcmp(name, "_pthread_cond_destroy") == 0) {
        host_fn = (void*)&darwin_pthread_cond_destroy;
    } else if (strcmp(name, "_pthread_once") == 0) {
        host_fn = (void*)&darwin_pthread_once;
    } else if (strcmp(name, "_vsnprintf") == 0 || strcmp(name, "vsnprintf") == 0) {
        host_fn = (void*)&darwin_vsnprintf;
    } else if (strcmp(name, "_pthread_get_stackaddr_np") == 0) {
        host_fn = (void*)&darwin_pthread_get_stackaddr_np;
    } else if (strcmp(name, "_pthread_get_stacksize_np") == 0) {
        host_fn = (void*)&darwin_pthread_get_stacksize_np;
    } else if (strcmp(name, "__NSGetArgc") == 0) {
        host_fn = (void*)&darwin_NSGetArgc;
    } else if (strcmp(name, "__NSGetArgv") == 0) {
        host_fn = (void*)&darwin_NSGetArgv;
    } else if (strcmp(name, "__NSGetEnviron") == 0) {
        host_fn = (void*)&darwin_NSGetEnviron;
    } else if (strcmp(name, "___isfinited") == 0 || strcmp(name, "___isfinitel") == 0) {
        host_fn = (void*)&darwin_isfinited;
    } else if (strcmp(name, "___isfinitef") == 0) {
        host_fn = (void*)&darwin_isfinitef;
    } else if (strcmp(name, "___isinfd") == 0 || strcmp(name, "___isinfl") == 0) {
        host_fn = (void*)&darwin_isinfd;
    } else if (strcmp(name, "___isinff") == 0) {
        host_fn = (void*)&darwin_isinff;
    } else if (strcmp(name, "___isnand") == 0 || strcmp(name, "___isnanl") == 0) {
        host_fn = (void*)&darwin_isnand;
    } else if (strcmp(name, "___isnanf") == 0) {
        host_fn = (void*)&darwin_isnanf;
    } else if (strcmp(name, "___isnormald") == 0 || strcmp(name, "___isnormall") == 0) {
        host_fn = (void*)&darwin_isnormald;
    } else if (strcmp(name, "___isnormalf") == 0) {
        host_fn = (void*)&darwin_isnormalf;
    } else if (strcmp(name, "___signbitd") == 0 || strcmp(name, "___signbitl") == 0) {
        host_fn = (void*)&darwin_signbitd;
    } else if (strcmp(name, "___signbitf") == 0) {
        host_fn = (void*)&darwin_signbitf;
    } else if (strcmp(name, "___fpclassifyd") == 0 || strcmp(name, "___fpclassifyl") == 0) {   // long double == double
        host_fn = (void*)&darwin_fpclassifyd;
    } else if (strcmp(name, "___fpclassifyf") == 0) {
        host_fn = (void*)&darwin_fpclassifyf;
    } else if (strcmp(name, "___exp10f") == 0) {
        host_fn = (void*)&darwin_exp10f;
    } else if (strcmp(name, "__NSGetProgname") == 0) {
        host_fn = (void*)&darwin_NSGetProgname;
    } else if (strcmp(name, "__NSGetExecutablePath") == 0) {
        host_fn = (void*)&darwin_NSGetExecutablePath;
    } else if (strcmp(name, "__tlv_bootstrap") == 0) {
        host_fn = (void*)&darwin_tlv_bootstrap;
    } else if (strcmp(name, "__tlv_atexit") == 0) {
        host_fn = (void*)&darwin_tlv_atexit;
    } else if (strcmp(name, "_dispatch_semaphore_create") == 0) {
        host_fn = (void*)&darwin_dispatch_semaphore_create;
    } else if (strcmp(name, "_dispatch_semaphore_signal") == 0) {
        host_fn = (void*)&darwin_dispatch_semaphore_signal;
    } else if (strcmp(name, "_dispatch_semaphore_wait") == 0) {
        host_fn = (void*)&darwin_dispatch_semaphore_wait;
    } else if (strcmp(name, "_dispatch_release") == 0) {
        host_fn = (void*)&darwin_dispatch_release;
    } else if (strcmp(name, "_dispatch_time") == 0) {
        host_fn = (void*)&darwin_dispatch_time;
    } else if (strcmp(name, "__dyld_image_count") == 0) {
        host_fn = (void*)&darwin_dyld_image_count;
    } else if (strcmp(name, "__dyld_get_image_name") == 0) {
        host_fn = (void*)&darwin_dyld_get_image_name;
    } else if (strcmp(name, "__dyld_get_image_vmaddr_slide") == 0) {
        host_fn = (void*)&darwin_dyld_get_image_vmaddr_slide;
    } else if (strcmp(name, "__dyld_get_image_header") == 0) {
        host_fn = (void*)&darwin_dyld_get_image_header;
    } else if (strcmp(name, "_strerror") == 0 || strcmp(name, "strerror") == 0) {
        host_fn = (void*)&darwin_strerror;
    } else if (strcmp(name, "_strerror_r") == 0 || strcmp(name, "strerror_r") == 0) {
        host_fn = (void*)&darwin_strerror_r;
    } else if (strcmp(name, "_mmap") == 0 || strcmp(name, "mmap") == 0) {
        host_fn = (void*)&darwin_mmap;
    } else if (strcmp(name, "_munmap") == 0 || strcmp(name, "munmap") == 0) {
        host_fn = (void*)&darwin_munmap;
    } else if (strcmp(name, "_sysconf") == 0 || strcmp(name, "sysconf") == 0) {
        host_fn = (void*)&darwin_sysconf;
    } else if (strcmp(name, "_stat$INODE64") == 0 || strcmp(name, "stat$INODE64") == 0 ||
               strcmp(name, "_stat") == 0 || strcmp(name, "stat") == 0) {
        host_fn = (void*)&darwin_stat_fn;
    } else if (strcmp(name, "_lstat$INODE64") == 0 || strcmp(name, "lstat$INODE64") == 0 ||
               strcmp(name, "_lstat") == 0 || strcmp(name, "lstat") == 0) {
        host_fn = (void*)&darwin_lstat_fn;
    } else if (strcmp(name, "_fstat$INODE64") == 0 || strcmp(name, "fstat$INODE64") == 0 ||
               strcmp(name, "_fstat") == 0 || strcmp(name, "fstat") == 0) {
        host_fn = (void*)&darwin_fstat_fn;
    } else if (strcmp(name, "_fstatat$INODE64") == 0 || strcmp(name, "fstatat$INODE64") == 0 ||
               strcmp(name, "_fstatat") == 0 || strcmp(name, "fstatat") == 0) {
        host_fn = (void*)&darwin_fstatat_fn;
    } else if (strcmp(name, "_opendir$INODE64") == 0 || strcmp(name, "opendir$INODE64") == 0 ||
               strcmp(name, "_opendir") == 0 || strcmp(name, "opendir") == 0) {
        host_fn = (void*)&darwin_opendir;
    } else if (strcmp(name, "_readdir_r$INODE64") == 0 || strcmp(name, "readdir_r$INODE64") == 0 ||
               strcmp(name, "_readdir_r") == 0 || strcmp(name, "readdir_r") == 0) {
        host_fn = (void*)&darwin_readdir_r;
    } else if (strcmp(name, "_readdir$INODE64") == 0 || strcmp(name, "readdir$INODE64") == 0 ||
               strcmp(name, "_readdir") == 0 || strcmp(name, "readdir") == 0) {
        host_fn = (void*)&darwin_readdir;
    } else if (strcmp(name, "_open") == 0 || strcmp(name, "open") == 0) {
        host_fn = (void*)&darwin_open_v;
    } else if (strcmp(name, "_openat") == 0 || strcmp(name, "openat") == 0) {
        host_fn = (void*)&darwin_openat_v;
    } else if (strcmp(name, "_fopen") == 0 || strcmp(name, "fopen") == 0 ||
               strcmp(name, "_fopen$DARWIN_EXTSN") == 0 || strcmp(name, "fopen$DARWIN_EXTSN") == 0) {
        host_fn = (void*)&darwin_fopen;
    } else if (strcmp(name, "_access") == 0 || strcmp(name, "access") == 0) {
        host_fn = (void*)&darwin_access;
    } else if (strcmp(name, "_readlink") == 0 || strcmp(name, "readlink") == 0) {
        host_fn = (void*)&darwin_readlink;
    } else if (strcmp(name, "_unlink") == 0 || strcmp(name, "unlink") == 0) {
        host_fn = (void*)&darwin_unlink;
    } else if (strcmp(name, "_remove") == 0 || strcmp(name, "remove") == 0) {
        host_fn = (void*)&darwin_remove;
    } else if (strcmp(name, "_mkdir") == 0 || strcmp(name, "mkdir") == 0) {
        host_fn = (void*)&darwin_mkdir;
    } else if (strcmp(name, "_rmdir") == 0 || strcmp(name, "rmdir") == 0) {
        host_fn = (void*)&darwin_rmdir;
    } else if (strcmp(name, "_rename") == 0 || strcmp(name, "rename") == 0) {
        host_fn = (void*)&darwin_rename;
    } else if (strcmp(name, "_chmod") == 0 || strcmp(name, "chmod") == 0) {
        host_fn = (void*)&darwin_chmod;
    } else if (strcmp(name, "_chown") == 0 || strcmp(name, "chown") == 0) {
        host_fn = (void*)&darwin_chown;
    } else if (strcmp(name, "_realpath") == 0 || strcmp(name, "realpath") == 0 ||
               strcmp(name, "_realpath$DARWIN_EXTSN") == 0 || strcmp(name, "realpath$DARWIN_EXTSN") == 0) {
        host_fn = (void*)&darwin_realpath;
    } else if (strcmp(name, "_getcwd") == 0 || strcmp(name, "getcwd") == 0) {
        host_fn = (void*)&darwin_getcwd;
    } else if (strcmp(name, "_err") == 0 || strcmp(name, "err") == 0) {
        host_fn = (void*)&darwin_err;
    } else if (strcmp(name, "_errx") == 0 || strcmp(name, "errx") == 0) {
        host_fn = (void*)&darwin_errx;
    } else if (strcmp(name, "_warn") == 0 || strcmp(name, "warn") == 0) {
        host_fn = (void*)&darwin_warn;
    } else if (strcmp(name, "_warnx") == 0 || strcmp(name, "warnx") == 0) {
        host_fn = (void*)&darwin_warnx;
    } else if (strcmp(name, "_errc") == 0 || strcmp(name, "errc") == 0) {
        host_fn = (void*)&darwin_errc;
    } else if (strcmp(name, "_warnc") == 0 || strcmp(name, "warnc") == 0) {
        host_fn = (void*)&darwin_warnc;
    } else if (strcmp(name, "_posix_spawn") == 0 || strcmp(name, "posix_spawn") == 0) {
        host_fn = (void*)&darwin_posix_spawn;
    } else if (strcmp(name, "_posix_spawnp") == 0 || strcmp(name, "posix_spawnp") == 0) {
        host_fn = (void*)&darwin_posix_spawnp;
    } else if (strcmp(name, "_posix_spawnattr_init") == 0 || strcmp(name, "posix_spawnattr_init") == 0) {
        host_fn = (void*)&darwin_posix_spawnattr_init;
    } else if (strcmp(name, "_posix_spawnattr_destroy") == 0 || strcmp(name, "posix_spawnattr_destroy") == 0) {
        host_fn = (void*)&darwin_posix_spawnattr_destroy;
    } else if (strcmp(name, "_posix_spawnattr_setflags") == 0 || strcmp(name, "posix_spawnattr_setflags") == 0) {
        host_fn = (void*)&darwin_posix_spawnattr_setflags;
    } else if (strcmp(name, "_posix_spawnattr_getflags") == 0 || strcmp(name, "posix_spawnattr_getflags") == 0) {
        host_fn = (void*)&darwin_posix_spawnattr_getflags;
    } else if (strcmp(name, "_posix_spawnattr_setbinpref_np") == 0 || strcmp(name, "posix_spawnattr_setbinpref_np") == 0) {
        host_fn = (void*)&darwin_posix_spawnattr_setbinpref_np;
    } else if (strcmp(name, "_posix_spawnattr_getbinpref_np") == 0 || strcmp(name, "posix_spawnattr_getbinpref_np") == 0) {
        host_fn = (void*)&darwin_posix_spawnattr_getbinpref_np;
    } else if (strcmp(name, "_posix_spawnattr_setpgroup") == 0 || strcmp(name, "posix_spawnattr_setpgroup") == 0) {
        host_fn = (void*)&darwin_posix_spawnattr_setpgroup;
    } else if (strcmp(name, "_posix_spawnattr_setsigmask") == 0 || strcmp(name, "posix_spawnattr_setsigmask") == 0) {
        host_fn = (void*)&darwin_posix_spawnattr_setsigmask;
    } else if (strcmp(name, "_posix_spawnattr_setsigdefault") == 0 || strcmp(name, "posix_spawnattr_setsigdefault") == 0) {
        host_fn = (void*)&darwin_posix_spawnattr_setsigdefault;
    } else if (strcmp(name, "_posix_spawn_file_actions_init") == 0 || strcmp(name, "posix_spawn_file_actions_init") == 0) {
        host_fn = (void*)&darwin_posix_spawn_file_actions_init;
    } else if (strcmp(name, "_posix_spawn_file_actions_destroy") == 0 || strcmp(name, "posix_spawn_file_actions_destroy") == 0) {
        host_fn = (void*)&darwin_posix_spawn_file_actions_destroy;
    } else if (strcmp(name, "_posix_spawn_file_actions_addclose") == 0 || strcmp(name, "posix_spawn_file_actions_addclose") == 0) {
        host_fn = (void*)&darwin_posix_spawn_file_actions_addclose;
    } else if (strcmp(name, "_posix_spawn_file_actions_adddup2") == 0 || strcmp(name, "posix_spawn_file_actions_adddup2") == 0) {
        host_fn = (void*)&darwin_posix_spawn_file_actions_adddup2;
    } else if (strcmp(name, "_posix_spawn_file_actions_addopen") == 0 || strcmp(name, "posix_spawn_file_actions_addopen") == 0) {
        host_fn = (void*)&darwin_posix_spawn_file_actions_addopen;
    } else if (strcmp(name, "_posix_spawn_file_actions_addinherit_np") == 0) {
        host_fn = (void*)&darwin_posix_spawn_file_actions_addinherit_np;
    } else if (strcmp(name, "_posix_spawn_file_actions_addchdir_np") == 0) {
        host_fn = (void*)&darwin_posix_spawn_file_actions_addchdir_np;
    } else if (strcmp(name, "_posix_spawn_file_actions_addfchdir_np") == 0) {
        host_fn = (void*)&darwin_posix_spawn_file_actions_addfchdir_np;
    } else if (strcmp(name, "_posix_spawnattr_getpgroup") == 0) {
        host_fn = (void*)&darwin_posix_spawnattr_getpgroup;
    } else if (strcmp(name, "_posix_spawnattr_getsigmask") == 0) {
        host_fn = (void*)&darwin_posix_spawnattr_getsigmask;
    } else if (strcmp(name, "_posix_spawnattr_getsigdefault") == 0) {
        host_fn = (void*)&darwin_posix_spawnattr_getsigdefault;
    } else if (strcmp(name, "_pthread_create") == 0 || strcmp(name, "pthread_create") == 0) {
        host_fn = (void*)&darwin_pthread_create;
    } else if (strcmp(name, "_pthread_join") == 0 || strcmp(name, "pthread_join") == 0) {
        host_fn = (void*)&darwin_pthread_join;
    } else if (strcmp(name, "_pthread_detach") == 0 || strcmp(name, "pthread_detach") == 0) {
        host_fn = (void*)&darwin_pthread_detach;
    } else if (strcmp(name, "_pthread_self") == 0 || strcmp(name, "pthread_self") == 0) {
        host_fn = (void*)&darwin_pthread_self;
    } else if (strcmp(name, "_pthread_threadid_np") == 0 || strcmp(name, "pthread_threadid_np") == 0) {
        host_fn = (void*)&darwin_pthread_threadid_np;
    } else if (strcmp(name, "_pthread_exit") == 0 || strcmp(name, "pthread_exit") == 0) {
        host_fn = (void*)&darwin_pthread_exit;
    } else if (strcmp(name, "_pthread_setname_np") == 0 || strcmp(name, "pthread_setname_np") == 0) {
        host_fn = (void*)&darwin_pthread_setname_np;
    } else if (strcmp(name, "_sched_yield") == 0 || strcmp(name, "sched_yield") == 0 ||
               strcmp(name, "_pthread_yield_np") == 0 || strcmp(name, "pthread_yield_np") == 0) {
        host_fn = (void*)&darwin_sched_yield;
    } else if (strcmp(name, "_os_unfair_lock_lock") == 0 || strcmp(name, "os_unfair_lock_lock") == 0) {
        host_fn = (void*)&darwin_os_unfair_lock_lock;
    } else if (strcmp(name, "_os_unfair_lock_trylock") == 0 || strcmp(name, "os_unfair_lock_trylock") == 0) {
        host_fn = (void*)&darwin_os_unfair_lock_trylock;
    } else if (strcmp(name, "_os_unfair_lock_unlock") == 0 || strcmp(name, "os_unfair_lock_unlock") == 0) {
        host_fn = (void*)&darwin_os_unfair_lock_unlock;
    } else if (strcmp(name, "_issetugid") == 0 || strcmp(name, "issetugid") == 0) {
        host_fn = (void*)&darwin_issetugid;
    } else if (strcmp(name, "_mach_absolute_time") == 0 || strcmp(name, "mach_absolute_time") == 0) {
        host_fn = (void*)&darwin_mach_absolute_time;
    } else if (strcmp(name, "_mach_approximate_time") == 0 || strcmp(name, "mach_approximate_time") == 0) {
        host_fn = (void*)&darwin_mach_approximate_time;
    } else if (strcmp(name, "_mach_continuous_time") == 0 || strcmp(name, "mach_continuous_time") == 0) {
        host_fn = (void*)&darwin_mach_continuous_time;
    } else if (strcmp(name, "_mach_continuous_approximate_time") == 0 || strcmp(name, "mach_continuous_approximate_time") == 0) {
        host_fn = (void*)&darwin_mach_continuous_approximate_time;
    } else if (strcmp(name, "_mach_boottime_usec") == 0 || strcmp(name, "mach_boottime_usec") == 0) {
        host_fn = (void*)&darwin_mach_boottime_usec;
    } else if (strcmp(name, "_mach_wait_until") == 0 || strcmp(name, "mach_wait_until") == 0) {
        host_fn = (void*)&darwin_mach_wait_until;
    } else if (strcmp(name, "_mach_timebase_info") == 0 || strcmp(name, "mach_timebase_info") == 0) {
        host_fn = (void*)&darwin_mach_timebase_info;
    } else if (strcmp(name, "_CCRandomGenerateBytes") == 0 || strcmp(name, "CCRandomGenerateBytes") == 0) {
        host_fn = (void*)&darwin_CCRandomGenerateBytes;
    } else if (strcmp(name, "__Unwind_Backtrace") == 0) {
        host_fn = (void*)&darwin_Unwind_Backtrace;
    } else if (strcmp(name, "_kqueue") == 0 || strcmp(name, "kqueue") == 0) {
        host_fn = (void*)&darwin_kqueue;
    } else if (strcmp(name, "_kevent") == 0 || strcmp(name, "kevent") == 0) {
        host_fn = (void*)&darwin_kevent;
    } else if (strcmp(name, "_fcntl") == 0 || strcmp(name, "fcntl") == 0) {
        host_fn = (void*)&darwin_fcntl_v;
    } else if (const ShimEntry* sh = [&]() -> const ShimEntry* {
                   for (const ShimEntry& e : kShims) if (!strcmp(e.name, name)) return &e;
                   return nullptr; }()) {
        host_fn = sh->fn;
    } else if (void* sf = darwin_sys_shim_lookup(name)) {
        host_fn = sf;
    } else if (void* sf5 = darwin_net_lookup(name)) {
        host_fn = sf5;
    } else if (void* sf4 = darwin_signal_lookup(name)) {
        host_fn = sf4;
    } else if (void* sf3 = darwin_mach_lookup(name)) {
        host_fn = sf3;
    } else if (void* sf2 = darwin_stub_lookup(name)) {
        host_fn = sf2;
    } else if (strcmp(name, "__dyld_objc_register_callbacks") == 0) {
        host_fn = (void*)&dyld_objc_register_callbacks;
    } else if (strcmp(name, "__dyld_objc_notify_register") == 0) {
        host_fn = (void*)&dyld_objc_notify_register;
    } else if (strcmp(name, "_exit") == 0) {
        host_fn = (void*)&darwin_exit_wrapper;
    } else if (strcmp(name, "___cxa_atexit") == 0) {
        host_fn = (void*)&darwin_cxa_atexit;
    } else if (strcmp(name, "___cxa_finalize") == 0) {
        host_fn = (void*)&darwin_cxa_finalize;
    } else if (strcmp(name, "___ulock_wait") == 0 || strcmp(name, "___ulock_wait2") == 0) {
        host_fn = (void*)&darwin_ulock_wait;
    } else if (strcmp(name, "___ulock_wake") == 0) {
        host_fn = (void*)&darwin_ulock_wake;
    } else if (strcmp(name, "_copyfile_state_alloc") == 0) {
        host_fn = (void*)&darwin_copyfile_state_alloc;
    } else if (strcmp(name, "_copyfile_state_free") == 0) {
        host_fn = (void*)&darwin_copyfile_state_free;
    } else if (strcmp(name, "_fcopyfile") == 0 || strcmp(name, "_copyfile") == 0) {
        host_fn = (void*)&darwin_enosys;
    } else if (strcmp(name, "_ioctl") == 0) {
        host_fn = (void*)&darwin_ioctl_v;
    } else if (strcmp(name, "_isatty") == 0) {
        host_fn = (void*)&darwin_isatty;
    } else if (strcmp(name, "_nftw") == 0) {
        host_fn = (void*)&darwin_nftw;
    } else if (strcmp(name, "_scandir") == 0 || strcmp(name, "_scandir$INODE64") == 0) {
        host_fn = (void*)&darwin_scandir;
    } else if (strcmp(name, "_alphasort") == 0 || strcmp(name, "_alphasort$INODE64") == 0) {
        host_fn = (void*)&darwin_alphasort;
    } else if (strcmp(name, "_qsort") == 0) {
        host_fn = (void*)&darwin_qsort;
    } else if (strcmp(name, "_qsort_r") == 0) {
        host_fn = (void*)&darwin_qsort_r;
    } else if (strcmp(name, "_bsearch") == 0) {
        host_fn = (void*)&darwin_bsearch;
    } else if (strcmp(name, "_mergesort") == 0 || strcmp(name, "_heapsort") == 0) {
        host_fn = (void*)&darwin_stable_sort;
    } else if (strcmp(name, "_mergesort_b") == 0 || strcmp(name, "_heapsort_b") == 0) {
        host_fn = (void*)&darwin_stable_sort_b;
    } else if (strcmp(name, "_qsort_b") == 0) {
        host_fn = (void*)&darwin_qsort_b;
    } else if (strcmp(name, "_bsearch_b") == 0) {
        host_fn = (void*)&darwin_bsearch_b;
    } else if (strcmp(name, "_tsearch") == 0) {
        host_fn = (void*)&darwin_tsearch;
    } else if (strcmp(name, "_tfind") == 0) {
        host_fn = (void*)&darwin_tfind;
    } else if (strcmp(name, "_tdelete") == 0) {
        host_fn = (void*)&darwin_tdelete;
    } else if (strcmp(name, "_twalk") == 0) {
        host_fn = (void*)&darwin_twalk;
    } else if (strcmp(name, "_lfind") == 0) {
        host_fn = (void*)&darwin_lfind;
    } else if (strcmp(name, "_lsearch") == 0) {
        host_fn = (void*)&darwin_lsearch;
    } else if (strcmp(name, "_dlsym") == 0 || strcmp(name, "dlsym") == 0) {
        host_fn = (void*)&darwin_dlsym;
    } else if (strcmp(name, "_dlopen") == 0 || strcmp(name, "dlopen") == 0) {
        host_fn = (void*)&darwin_dlopen;
    } else if (strcmp(name, "_dlclose") == 0 || strcmp(name, "dlclose") == 0) {
        host_fn = (void*)&darwin_dlclose;
    } else if (strcmp(name, "_dlerror") == 0 || strcmp(name, "dlerror") == 0) {
        host_fn = (void*)&darwin_dlerror;
    } else if (strcmp(name, "_dladdr") == 0 || strcmp(name, "dladdr") == 0) {
        host_fn = (void*)&darwin_dladdr;
    } else if (strcmp(name, "__dyld_find_unwind_sections") == 0) {
        host_fn = (void*)&darwin_dyld_find_unwind_sections;
    } else if (strcmp(name, "__dyld_register_func_for_add_image") == 0) {
        host_fn = (void*)&darwin_dyld_register_func_for_add_image;
    } else if (strcmp(name, "__dyld_register_func_for_remove_image") == 0) {
        host_fn = (void*)&darwin_dyld_register_func_for_remove_image;
    } else if (strcmp(name, "_dyld_image_path_containing_address") == 0) {
        host_fn = (void*)&darwin_dyld_get_image_install_name;
    } else if (strcmp(name, "_printf") == 0 || strcmp(name, "printf") == 0) {
        host_fn = (void*)&darwin_printf;
    } else if (strcmp(name, "_fprintf") == 0 || strcmp(name, "fprintf") == 0) {
        host_fn = (void*)&darwin_fprintf;
    } else if (strcmp(name, "_vfprintf") == 0 || strcmp(name, "vfprintf") == 0) {
        host_fn = (void*)&darwin_vfprintf;
    } else if (strcmp(name, "_snprintf") == 0 || strcmp(name, "snprintf") == 0) {
        host_fn = (void*)&darwin_snprintf;
    } else if (strcmp(name, "_vsnprintf") == 0 || strcmp(name, "vsnprintf") == 0) {
        host_fn = (void*)&darwin_vsnprintf;
    } else {
        // Strip Darwin version suffixes like $DARWIN_EXTSN or $UNIX2003
        std::string sname = name;
        size_t dollar_pos = sname.find('$');
        if (dollar_pos != std::string::npos) {
            sname = sname.substr(0, dollar_pos);
        }
        // Strip leading '_' (macOS C symbol prefix)
        const char* clean_name = (sname[0] == '_') ? sname.c_str() + 1 : sname.c_str();
        if (explicit_only) return 0;
        host_fn = dlsym(RTLD_DEFAULT, clean_name);
        if (host_fn) g_host_fallback_names.insert(name);
        if (!host_fn) host_fn = dlsym(RTLD_DEFAULT, sname.c_str());
        if (!host_fn) host_fn = dlsym(RTLD_DEFAULT, name);
    }

    if (!host_fn) {
        if (is_weak) {
            XEF_LOG(2, "xef-osx: weak unresolved symbol %s -> NULL", name);
            return 0;
        }
        XEF_LOG(1, "xef-osx: unresolved symbol %s", name);
        host_fn = (void*)&darwin_missing_symbol_fallback;
        g_host_fallback_names.insert(name);
    }

    // Allocate thunk stub in ARM64 executable code page:
    // mov x17, #thunk_id
    // hlt #0x5846
    // ret
    if (g_thunk_code_used + 16 > kThunkCodeSize) {
        fatal("darwin_hle: thunk code buffer exhausted");
    }

    uint32_t thunk_id = (uint32_t)g_thunks.size();
    XEF_LOG(2, "darwin_hle: registered thunk id %u for symbol '%s'", thunk_id, name);
    g_thunks.push_back({name, host_fn, strncmp(name, "_pthread_", 9) == 0 || strncmp(name, "_sem_", 5) == 0 || strstr(name, "posix_spawn") != nullptr});

    uint8_t* stub_ptr = g_thunk_code + g_thunk_code_used;
    g_thunk_code_used += 16; // 16-byte aligned

    uint32_t* insns = (uint32_t*)stub_ptr;
    // mov x17, #thunk_id (MOVZ x17, imm16, LSL #0) -> 0xd2800000 | (imm16 << 5) | 17
    insns[0] = 0xd2800000u | ((thunk_id & 0xffffu) << 5) | 17u;
    // hlt #0x5846
    insns[1] = 0xd4400000u | (kThunkHlt << 5);
    // ret
    insns[2] = 0xd65f03c0u;
    insns[3] = 0xd503201fu; // nop

    uint64_t guest_addr = (uint64_t)(uintptr_t)stub_ptr;
    g_symbol_cache[name] = guest_addr;
    return guest_addr;
}

bool darwin_hle_current(const char** name, u64* lr) {
    if (!tl_hle_name) return false;
    *name = tl_hle_name; *lr = tl_hle_lr;
    return true;
}

uint64_t darwin_hle_register_function(const char* name, void* host_fn) {
    darwin_hle_init();
    std::lock_guard<std::mutex> lk(g_hle_lock);
    auto it = g_symbol_cache.find(name);
    if (it != g_symbol_cache.end()) return it->second;
    uint32_t thunk_id = (uint32_t)g_thunks.size();
    g_thunks.push_back({name, host_fn});
    uint8_t* stub_ptr = g_thunk_code + g_thunk_code_used;
    g_thunk_code_used += 16;
    uint32_t* insns = (uint32_t*)stub_ptr;
    insns[0] = 0xd2800000u | ((thunk_id & 0xffffu) << 5) | 17u;
    insns[1] = 0xd4400000u | (kThunkHlt << 5);
    insns[2] = 0xd65f03c0u;
    insns[3] = 0xd503201fu;
    uint64_t a = (uint64_t)(uintptr_t)stub_ptr;
    g_symbol_cache[name] = a;
    g_host_fallback_names.insert(name);
    return a;
}

// XEF_GUEST_BT=N[,count]: from N seconds after start, the next `count` (default 20) HLE calls of each thread print
// the caller's guest frame-pointer backtrace (where is a busy/hung program spinning?)
static void hle_debug_backtrace(CpuState* st, const char* name) {
    static const char* env = getenv("XEF_GUEST_BT");
    if (!env) return;
    static const double start = [] { timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }();
    static const double after = atof(env);
    static const int count = strchr(env, ',') ? atoi(strchr(env, ',') + 1) : 20;
    static thread_local int printed;
    if (printed >= count) return;
    timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    if (t.tv_sec + t.tv_nsec * 1e-9 - start < after) return;
    printed++;
    std::string out = "xef-bt: tid " + std::to_string(gettid()) + " " + name + " from " + dyld_describe(st->x[30]) + "\n";
    u64 fp = st->x[29];
    for (int i = 0; i < 24 && fp && !(fp & 7); i++) {
        u64 lr = ((u64*)fp)[1];
        out += "xef-bt:    #" + std::to_string(i) + " " + dyld_describe(lr) + "\n";
        u64 nfp = ((u64*)fp)[0];
        if (nfp <= fp || nfp >= fp + 0x10000000) break;
        fp = nfp;
    }
    fputs(out.c_str(), stderr);
}

void darwin_hle_dispatch(CpuState* st) {
    u64 id = st->x[17];
    void* host_fn = nullptr;
    const char* name = nullptr;
    bool errno_ret = false;
    {
        std::lock_guard<std::mutex> lk(g_hle_lock);
        if (id >= g_thunks.size()) {
            fatal("darwin_hle_dispatch: invalid thunk id %lu", (unsigned long)id);
        }
        host_fn = g_thunks[id].host_fn;
        name = g_thunks[id].name.c_str();
        errno_ret = g_thunks[id].errno_ret;
    }
    struct HleScope { ~HleScope() { tl_hle_name = nullptr; } } hle_scope;
    tl_hle_name = name;
    tl_hle_lr = st->x[30];
    XEF_LOG(2, "hle: %s(x0=%#lx, x1=%#lx, x2=%#lx, x3=%#lx)", name,
            (unsigned long)st->x[0], (unsigned long)st->x[1], (unsigned long)st->x[2], (unsigned long)st->x[3]);
    hle_debug_backtrace(st, name);

    if (host_fn == (void*)&darwin_start_marker) {
        // x0..x3 = argc, argv, envp, apple (dyld's initializer arguments)
        u64 argc = st->x[0];
        u64 argv = st->x[1];
        u64 envp = st->x[2];
        u64 apple = st->x[3];
        u64 sp = st->x[kGuestSP];
        u64 lr = st->x[30];
        dyld_run_initializers(argc, argv, envp, apple);
        st->x[0] = argc;
        st->x[1] = argv;
        st->x[2] = envp;
        st->x[3] = apple;
        st->x[kGuestSP] = sp;
        st->x[30] = lr;
        st->x[16] = g_darwin_start_target;
        XEF_LOG(1, "xef-osx: initializers done, entering %#lx (argc=%lu argv=%#lx lr=%#lx sp=%#lx)",
                (unsigned long)st->x[16], (unsigned long)argc, (unsigned long)argv, (unsigned long)lr, (unsigned long)sp);
        return;
    }



    if (host_fn == (void*)&darwin_missing_symbol_fallback) {
        fatal("xef-osx: called unresolved Darwin symbol '%s'", name);
    }

    // Apple Darwin ARM64 ABI:
    // For variadic formatters (printf, fprintf, snprintf), arguments start on the STACK (SP).
    // For va_list formatters (vfprintf, vsnprintf), the va_list pointer is passed as a normal argument register (x2 or x3).
    if (host_fn == (void*)&darwin_printf) {
        // x0 = format, variadic args are at [SP]
        const uint64_t* sp = (const uint64_t*)(uintptr_t)st->x[kGuestSP];
        st->x[0] = (uint64_t)darwin_printf((const char*)(uintptr_t)st->x[0], sp);
        return;
    }
    if (host_fn == (void*)&darwin_fprintf) {
        // x0 = stream, x1 = format, variadic args are at [SP]
        const uint64_t* sp = (const uint64_t*)(uintptr_t)st->x[kGuestSP];
        st->x[0] = (uint64_t)darwin_fprintf((FILE*)(uintptr_t)st->x[0], (const char*)(uintptr_t)st->x[1], sp);
        return;
    }
    if (host_fn == (void*)&darwin_vfprintf) {
        // x0 = stream, x1 = format, x2 = va_list pointer (points to argument list on stack)
        const uint64_t* va = (const uint64_t*)(uintptr_t)st->x[2];
        st->x[0] = (uint64_t)darwin_vfprintf((FILE*)(uintptr_t)st->x[0], (const char*)(uintptr_t)st->x[1], va);
        return;
    }
    if (host_fn == (void*)&darwin_snprintf) {
        // x0 = str, x1 = size, x2 = format, variadic args are at [SP]
        const uint64_t* sp = (const uint64_t*)(uintptr_t)st->x[kGuestSP];
        st->x[0] = (uint64_t)darwin_snprintf((char*)(uintptr_t)st->x[0], (size_t)st->x[1], (const char*)(uintptr_t)st->x[2], sp);
        return;
    }
    if (host_fn == (void*)&darwin_vsnprintf) {
        // x0 = str, x1 = size, x2 = format, x3 = va_list pointer
        const uint64_t* va = (const uint64_t*)(uintptr_t)st->x[3];
        st->x[0] = (uint64_t)darwin_vsnprintf((char*)(uintptr_t)st->x[0], (size_t)st->x[1], (const char*)(uintptr_t)st->x[2], va);
        return;
    }
    if (host_fn == (void*)&darwin_err) {
        int eval = (int)st->x[0];
        const char* fmt = (const char*)(uintptr_t)st->x[1];
        const uint64_t* sp = (const uint64_t*)(uintptr_t)st->x[kGuestSP];
        darwin_warn_impl(true, fmt, sp);
        exit(eval);
    }
    if (host_fn == (void*)&darwin_errx) {
        int eval = (int)st->x[0];
        const char* fmt = (const char*)(uintptr_t)st->x[1];
        const uint64_t* sp = (const uint64_t*)(uintptr_t)st->x[kGuestSP];
        darwin_warn_impl(false, fmt, sp);
        exit(eval);
    }
    if (host_fn == (void*)&darwin_warn) {
        const char* fmt = (const char*)(uintptr_t)st->x[0];
        const uint64_t* sp = (const uint64_t*)(uintptr_t)st->x[kGuestSP];
        darwin_warn_impl(true, fmt, sp);
        return;
    }
    if (host_fn == (void*)&darwin_warnx) {
        const char* fmt = (const char*)(uintptr_t)st->x[0];
        const uint64_t* sp = (const uint64_t*)(uintptr_t)st->x[kGuestSP];
        darwin_warn_impl(false, fmt, sp);
        return;
    }
    if (host_fn == (void*)&darwin_errc) {
        int eval = (int)st->x[0];
        int code = (int)st->x[1];
        const char* fmt = (const char*)(uintptr_t)st->x[2];
        const uint64_t* sp = (const uint64_t*)(uintptr_t)st->x[kGuestSP];
        int saved = g_darwin_errno;
        g_darwin_errno = code;
        darwin_warn_impl(true, fmt, sp);
        g_darwin_errno = saved;
        exit(eval);
    }
    if (host_fn == (void*)&darwin_warnc) {
        int code = (int)st->x[0];
        const char* fmt = (const char*)(uintptr_t)st->x[1];
        const uint64_t* sp = (const uint64_t*)(uintptr_t)st->x[kGuestSP];
        int saved = g_darwin_errno;
        g_darwin_errno = code;
        darwin_warn_impl(true, fmt, sp);
        g_darwin_errno = saved;
        return;
    }


    if (const ShimEntry* sh = find_shim_by_fn(host_fn)) {
        if (sh->variadic_fixed >= 0) {
            u64 a[6] = {st->x[0], st->x[1], st->x[2], st->x[3], st->x[4], st->x[5]};
            a[sh->variadic_fixed] = st->x[kGuestSP];
            u64 fr[8] = {};
            u64 x0 = 0;
            errno = 0;
            st->x[0] = xef_call_sysv(host_fn, a, fr, nullptr, 0, &x0);
            if (errno) g_darwin_errno = darwin_errno_from_linux(errno);
            return;
        }
        if (sh->variadic_fixed == -3 || sh->variadic_fixed == -4) {   // HFA of two floats / doubles in v0,v1
            uint8_t o0[16] = {}, o1[16] = {};
            if (sh->variadic_fixed == -3) {
                float x; memcpy(&x, st->v[0], 4);
                F2Ret r = ((F2Ret(*)(float))host_fn)(x);
                memcpy(o0, &r.s, 4); memcpy(o1, &r.c, 4);
            } else {
                double x; memcpy(&x, st->v[0], 8);
                D2Ret r = ((D2Ret(*)(double))host_fn)(x);
                memcpy(o0, &r.s, 8); memcpy(o1, &r.c, 8);
            }
            memcpy(st->v[0], o0, 16); memcpy(st->v[1], o1, 16);
            return;
        }
        if (sh->variadic_fixed == -2) {
            u64 a[6] = {st->x[0], st->x[1], st->x[2], st->x[3], 0, 0};
            u64 fr[8] = {};
            u64 x0 = 0;
            // the SysV struct return of two words is rax:rdx; xef_call_sysv only gives rax, so call directly
            typedef U128Ret (*fn_t)(uint64_t, uint64_t, uint64_t, uint64_t);
            (void)fr; (void)x0; (void)a;
            errno = 0;
            U128Ret r = ((fn_t)host_fn)(st->x[0], st->x[1], st->x[2], st->x[3]);
            if (errno) g_darwin_errno = darwin_errno_from_linux(errno);
            st->x[0] = r.lo;
            st->x[1] = r.hi;
            return;
        }
    }

    u64 iregs[6] = { st->x[0], st->x[1], st->x[2], st->x[3], st->x[4], st->x[5] };
    u64 fregs[8];
    for (int i = 0; i < 8; i++) memcpy(&fregs[i], st->v[i], 8);

    if (name[1] == 'g' && name[2] == 'l') {
        // GL calls with Darwin stack arguments (natural-size packing): re-pack into 8-byte SysV slots
        u64 gv[8], gst[32], gn = 0;
        for (int i = 0; i < 8; i++) memcpy(&gv[i], st->v[i], 8);
        if (darwin_gl_repack(host_fn, st->x, gv, (const uint64_t*)(uintptr_t)st->x[kGuestSP], iregs, fregs, gst, &gn)) {
            u64 xo = 0;
            errno = 0;
            u64 r = xef_call_sysv(host_fn, iregs, fregs, gst, gn, &xo);
            if (errno) g_darwin_errno = darwin_errno_from_linux(errno);
            st->x[0] = darwin_gl_fix_ret(name, r);
            memcpy(st->v[0], &xo, 8);
            return;
        }
    }

    // Darwin passes the 7th and 8th integer arguments in x6/x7 and the rest on the guest stack; SysV
    // has six integer registers, so x6/x7 go first on the host stack, followed by the guest stack words.
    const uint64_t* guest_stack = (const uint64_t*)(uintptr_t)st->x[kGuestSP];
    u64 hstack[18];
    hstack[0] = st->x[6];
    hstack[1] = st->x[7];
    // (the 16 words may run past the end of the guest stack mapping - a stack switched to the very top of an mmap'ed
    // region, e.g. Rust's stacker - so a copy that crosses a page boundary reads only what is mapped)
    uintptr_t gs = (uintptr_t)guest_stack;
    if (((gs + 16 * sizeof(u64) - 1) ^ gs) < 4096) {
        memcpy(&hstack[2], guest_stack, 16 * sizeof(u64));
    } else {
        memset(&hstack[2], 0, 16 * sizeof(u64));
        struct iovec l{&hstack[2], 16 * sizeof(u64)}, r{(void*)gs, 16 * sizeof(u64)};
        if (process_vm_readv(getpid(), &l, 1, &r, 1, 0) < (ssize_t)(16 * sizeof(u64))) {
            size_t first = 4096 - (gs & 4095);   // the first page is the guest's sp page: readable
            memcpy(&hstack[2], guest_stack, first);
        }
    }
    u64 xmm0_out = 0;
    errno = 0;
    u64 pc_before = st->pc;
    u64 ret = xef_call_sysv(host_fn, iregs, fregs, hstack, 18, &xmm0_out);
    if (errno) g_darwin_errno = darwin_errno_from_linux(errno);
    if (st->pc != pc_before) return;   // the call delivered a signal (sigsuspend): registers belong to the handler now
    if (name[1] == 'g' && name[2] == 'l') ret = darwin_gl_fix_ret(name, ret);
    if (errno_ret && (int64_t)ret > 34 && (int64_t)ret < 200) ret = (u64)darwin_errno_from_linux((int)ret);
    st->x[0] = ret;
    memcpy(st->v[0], &xmm0_out, 8);
    XEF_LOG(2, "hle: %s -> %#lx", name, (unsigned long)ret);
}

} // namespace xef
