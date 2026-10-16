// XEF-OSX — Darwin FILE for guests. Darwin's <stdio.h> inlines getc_unlocked/putc_unlocked/feof_unlocked/
// ferror_unlocked/clearerr_unlocked/fileno_unlocked as macros on `struct __sFILE` fields (_p, _r, _w, _flags,
// _file), so a guest FILE* must have that layout. Each guest FILE is a Darwin-layout shell around a host glibc
// FILE (kept in _cookie): _r and _w stay 0, so the macros always take the slow path into __srget / __swbuf;
// _flags mirrors the host EOF/error state and _file the descriptor. Every libc function taking a FILE* is
// wrapped here and unwraps the shell (a pointer that is not a shell is passed through as a host FILE*).
// stdin/stdout/stderr are the shells __sF[0..2], also reachable through __stdinp/__stdoutp/__stderrp.
#include "loader/darwin_hle.h"
#include "loader/elf_loader.h"
#include "thunks/thunks.h"
#include "common/common.h"

#include <errno.h>
#include <stdio.h>
#include <stdio_ext.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wchar.h>
#include <mutex>
#include <string>
#include <unordered_map>

namespace xef {

struct DarwinSbuf { unsigned char* base; int size; };
struct DarwinFILE {
    unsigned char* p;          // 0
    int r, w;                  // 8, 12
    short flags, file;         // 16, 18
    DarwinSbuf bf;             // 24
    int lbfsize;               // 40
    void* cookie;              // 48: host FILE*
    void* close_fn, *read_fn, *seek_fn, *write_fn;   // 56..80
    DarwinSbuf ub;             // 88
    void* extra;               // 104: &g_shell_tag marks our shells
    int ur;                    // 112
    unsigned char ubuf[3], nbuf[1];   // 116
    DarwinSbuf lb;             // 120: fgetln line buffer
    int blksize;               // 136
    int64_t offset;            // 144
};
static_assert(sizeof(DarwinFILE) == 152, "Darwin struct __sFILE");
static_assert(offsetof(DarwinFILE, cookie) == 48 && offsetof(DarwinFILE, lb) == 120, "layout");

constexpr short kSRD = 0x0004, kSWR = 0x0008, kSRW = 0x0010, kSEOF = 0x0020, kSERR = 0x0040;
static int g_shell_tag;
static DarwinFILE g_sF[3];
static DarwinFILE* g_stdp[3] = {&g_sF[0], &g_sF[1], &g_sF[2]};
static std::mutex g_files_lock;
static std::unordered_map<FILE*, DarwinFILE*> g_by_host;

static inline bool is_shell(const void* g) { return g && ((const DarwinFILE*)g)->extra == &g_shell_tag; }

static void init_shell(DarwinFILE* d, FILE* h, const char* mode) {
    memset(d, 0, sizeof *d);
    d->cookie = h;
    d->extra = &g_shell_tag;
    int fd = fileno(h);
    d->file = fd >= 0 && fd <= 0x7fff ? (short)fd : -1;
    d->blksize = 4096;
    short f = 0;
    if (mode) {
        bool plus = strchr(mode, '+') != nullptr;
        f = plus ? kSRW : mode[0] == 'r' ? kSRD : kSWR;
    }
    d->flags = f;
}

static void stdio_init() {
    static std::once_flag once;
    std::call_once(once, [] {
        init_shell(&g_sF[0], stdin, "r");
        init_shell(&g_sF[1], stdout, "w");
        init_shell(&g_sF[2], stderr, "w");
        std::lock_guard<std::mutex> lk(g_files_lock);
        for (auto& s : g_sF) g_by_host[(FILE*)s.cookie] = &s;
    });
}

FILE* darwin_stdio_host(void* g) {
    if (!g) return nullptr;
    if (!is_shell(g)) return (FILE*)g;
    DarwinFILE* d = (DarwinFILE*)g;
    FILE* h = (FILE*)d->cookie;
    // the guest cleared the error/EOF bits inline (clearerr_unlocked): clear them on the host too
    if (!(d->flags & (kSEOF | kSERR)) && (feof(h) || ferror(h))) clearerr(h);
    d->r = d->w = 0;
    return h;
}

static void sync_out(DarwinFILE* d) {
    if (!is_shell(d)) return;
    FILE* h = (FILE*)d->cookie;
    d->flags = (short)((d->flags & ~(kSEOF | kSERR)) | (feof(h) ? kSEOF : 0) | (ferror(h) ? kSERR : 0));
    d->r = d->w = 0;
}

void darwin_stdio_sync(void* g) { sync_out((DarwinFILE*)g); }

void* darwin_stdio_guest(FILE* h, const char* mode) {
    if (!h) return nullptr;
    stdio_init();
    std::lock_guard<std::mutex> lk(g_files_lock);
    auto it = g_by_host.find(h);
    if (it != g_by_host.end()) return it->second;
    DarwinFILE* d = (DarwinFILE*)malloc(sizeof(DarwinFILE));
    init_shell(d, h, mode);
    g_by_host[h] = d;
    return d;
}

static void forget(DarwinFILE* d) {
    if (!is_shell(d)) return;
    {
        std::lock_guard<std::mutex> lk(g_files_lock);
        g_by_host.erase((FILE*)d->cookie);
    }
    free(d->lb.base);
    d->extra = nullptr;
    if (d < &g_sF[0] || d > &g_sF[2]) free(d);
}

#define H(g) darwin_stdio_host(g)
#define OUT(g) sync_out((DarwinFILE*)(g))

// ---- open / close -------------------------------------------------------------------------------------------
static void* s_fopen(const char* path, const char* mode) {
    if (!path || !mode) { errno = EFAULT; return nullptr; }
    return darwin_stdio_guest(fopen(resolve_guest_path(path, true).c_str(), mode), mode);
}
static void* s_fdopen(int fd, const char* mode) { return darwin_stdio_guest(fdopen(fd, mode), mode); }
static void* s_freopen(const char* path, const char* mode, void* g) {
    FILE* h = H(g);
    if (!h) { errno = EFAULT; return nullptr; }
    std::string hp = path ? resolve_guest_path(path, true) : std::string();
    FILE* n = freopen(path ? hp.c_str() : nullptr, mode, h);
    if (!n) { if (is_shell(g)) forget((DarwinFILE*)g); return nullptr; }
    if (!is_shell(g)) return darwin_stdio_guest(n, mode);
    DarwinFILE* d = (DarwinFILE*)g;
    std::lock_guard<std::mutex> lk(g_files_lock);
    g_by_host.erase(h);
    short keep = d->flags;
    void* lb = d->lb.base;
    init_shell(d, n, mode);
    (void)keep;
    d->lb.base = (unsigned char*)lb;
    g_by_host[n] = d;
    return d;
}
static void* s_popen(const char* cmd, const char* mode) { return darwin_stdio_guest(popen(cmd, mode), mode); }
static void* s_tmpfile() { return darwin_stdio_guest(tmpfile(), "w+"); }
static void* s_fmemopen(void* buf, size_t size, const char* mode) { return darwin_stdio_guest(fmemopen(buf, size, mode), mode); }
static void* s_open_memstream(char** p, size_t* s) { return darwin_stdio_guest(open_memstream(p, s), "w"); }
static int s_fclose(void* g) {
    FILE* h = H(g);
    if (!h) { errno = EFAULT; return -1; }
    int r = fclose(h);
    forget((DarwinFILE*)g);
    return r;
}
static int s_pclose(void* g) {
    FILE* h = H(g);
    if (!h) { errno = EFAULT; return -1; }
    int r = pclose(h);
    forget((DarwinFILE*)g);
    return r;
}

// funopen(cookie, readfn, writefn, seekfn, closefn): guest callbacks behind a host fopencookie stream
struct FunCookie { uint64_t cookie, rd, wr, sk, cl; };
static ssize_t fun_read(void* c, char* buf, size_t n) {
    FunCookie* f = (FunCookie*)c;
    if (!f->rd) { errno = EBADF; return -1; }
    u64 a[3] = {f->cookie, (u64)(uintptr_t)buf, (u64)(n > 0x7fffffff ? 0x7fffffff : n)};
    int r = (int)guest_call(f->rd, 3, a);
    return r < 0 ? -1 : r;
}
static ssize_t fun_write(void* c, const char* buf, size_t n) {
    FunCookie* f = (FunCookie*)c;
    if (!f->wr) { errno = EBADF; return 0; }
    u64 a[3] = {f->cookie, (u64)(uintptr_t)buf, (u64)(n > 0x7fffffff ? 0x7fffffff : n)};
    int r = (int)guest_call(f->wr, 3, a);
    return r < 0 ? 0 : r;
}
static int fun_seek(void* c, off64_t* off, int whence) {
    FunCookie* f = (FunCookie*)c;
    if (!f->sk) { errno = ESPIPE; return -1; }
    u64 a[3] = {f->cookie, (u64)*off, (u64)whence};   // SEEK_SET/CUR/END: same values
    int64_t r = (int64_t)guest_call(f->sk, 3, a);
    if (r < 0) return -1;
    *off = r;
    return 0;
}
static int fun_close(void* c) {
    FunCookie* f = (FunCookie*)c;
    int r = 0;
    if (f->cl) { u64 a[1] = {f->cookie}; r = (int)guest_call(f->cl, 1, a); }
    delete f;
    return r;
}
static void* s_funopen(uint64_t cookie, uint64_t rd, uint64_t wr, uint64_t sk, uint64_t cl) {
    if (!rd && !wr) { errno = EINVAL; return nullptr; }
    FunCookie* f = new FunCookie{cookie, rd, wr, sk, cl};
    cookie_io_functions_t io = {fun_read, fun_write, fun_seek, fun_close};
    const char* mode = rd && wr ? "r+" : rd ? "r" : "w";
    FILE* h = fopencookie(f, mode, io);
    if (!h) { delete f; return nullptr; }
    return darwin_stdio_guest(h, mode);
}

// ---- character / block I/O ----------------------------------------------------------------------------------
static int s_fgetc(void* g) { int r = fgetc(H(g)); OUT(g); return r; }
static int s_getc_unlocked(void* g) { int r = getc_unlocked(H(g)); OUT(g); return r; }
static int s_fputc(int c, void* g) { int r = fputc(c, H(g)); OUT(g); return r; }
static int s_putc_unlocked(int c, void* g) { int r = putc_unlocked(c, H(g)); OUT(g); return r; }
static int s_srget(void* g) { int r = getc_unlocked(H(g)); OUT(g); return r; }
static int s_swbuf(int c, void* g) { int r = putc_unlocked(c, H(g)); OUT(g); return r; }
static int s_ungetc(int c, void* g) { int r = ungetc(c, H(g)); OUT(g); return r; }
static int s_getw(void* g) { int r = getw(H(g)); OUT(g); return r; }
static int s_putw(int w, void* g) { int r = putw(w, H(g)); OUT(g); return r; }
static size_t s_fread(void* p, size_t sz, size_t n, void* g) { size_t r = fread(p, sz, n, H(g)); OUT(g); return r; }
static size_t s_fwrite(const void* p, size_t sz, size_t n, void* g) { size_t r = fwrite(p, sz, n, H(g)); OUT(g); return r; }
static char* s_fgets(char* s, int n, void* g) { char* r = fgets(s, n, H(g)); OUT(g); return r; }
static int s_fputs(const char* s, void* g) { int r = fputs(s, H(g)); OUT(g); return r; }
static ssize_t s_getdelim(char** l, size_t* n, int d, void* g) { ssize_t r = getdelim(l, n, d, H(g)); OUT(g); return r; }
static ssize_t s_getline(char** l, size_t* n, void* g) { ssize_t r = getline(l, n, H(g)); OUT(g); return r; }
// fgetln: the line (not NUL-terminated) stays valid until the next I/O on the stream: kept in the shell's _lb
static char* s_fgetln(void* g, size_t* len) {
    FILE* h = H(g);
    if (!h) { errno = EBADF; return nullptr; }
    DarwinFILE* d = is_shell(g) ? (DarwinFILE*)g : nullptr;
    static thread_local char* tl_buf; static thread_local size_t tl_cap;
    char* buf = d ? (char*)d->lb.base : tl_buf;
    size_t cap = d ? (size_t)d->lb.size : tl_cap;
    ssize_t r = getline(&buf, &cap, h);
    if (d) { d->lb.base = (unsigned char*)buf; d->lb.size = (int)cap; } else { tl_buf = buf; tl_cap = cap; }
    OUT(g);
    if (r <= 0) { if (len) *len = 0; return nullptr; }
    if (len) *len = (size_t)r;
    return buf;
}
static wint_t s_fgetwc(void* g) { wint_t r = fgetwc(H(g)); OUT(g); return r; }
static wint_t s_fputwc(wchar_t c, void* g) { wint_t r = fputwc(c, H(g)); OUT(g); return r; }
static wint_t s_ungetwc(wint_t c, void* g) { wint_t r = ungetwc(c, H(g)); OUT(g); return r; }
static wchar_t* s_fgetws(wchar_t* s, int n, void* g) { wchar_t* r = fgetws(s, n, H(g)); OUT(g); return r; }
static int s_fputws(const wchar_t* s, void* g) { int r = fputws(s, H(g)); OUT(g); return r; }
static int s_fwide(void* g, int m) { return fwide(H(g), m); }

// ---- positioning (Darwin fpos_t is a 64-bit offset) -------------------------------------------------------------
static int s_fseek(void* g, long o, int w) { int r = fseek(H(g), o, w); OUT(g); return r; }
static int s_fseeko(void* g, off_t o, int w) { int r = fseeko(H(g), o, w); OUT(g); return r; }
static long s_ftell(void* g) { return ftell(H(g)); }
static off_t s_ftello(void* g) { return ftello(H(g)); }
static void s_rewind(void* g) { rewind(H(g)); OUT(g); }
static int s_fgetpos(void* g, int64_t* pos) {
    off_t o = ftello(H(g));
    if (o < 0) return -1;
    *pos = o;
    return 0;
}
static int s_fsetpos(void* g, const int64_t* pos) { int r = fseeko(H(g), *pos, SEEK_SET); OUT(g); return r; }

// ---- state / buffering ------------------------------------------------------------------------------------------
static int s_feof(void* g) { return feof(H(g)); }
static int s_ferror(void* g) { return ferror(H(g)); }
static void s_clearerr(void* g) { clearerr(H(g)); OUT(g); }
static int s_fileno(void* g) { return fileno(H(g)); }
static int s_fflush(void* g) { if (!g) return fflush(nullptr); int r = fflush(H(g)); OUT(g); return r; }
static int s_fpurge(void* g) { FILE* h = H(g); if (!h) { errno = EBADF; return -1; } __fpurge(h); return 0; }
static int s_setvbuf(void* g, char* b, int mode, size_t sz) { return setvbuf(H(g), b, mode, sz); }   // _IOFBF/_IOLBF/_IONBF: 0/1/2 on both
static void s_setbuf(void* g, char* b) { setbuf(H(g), b); }
static void s_setbuffer(void* g, char* b, int sz) { setbuffer(H(g), b, (size_t)sz); }
static int s_setlinebuf(void* g) { setlinebuf(H(g)); return 0; }
static void s_flockfile(void* g) { flockfile(H(g)); }
static void s_funlockfile(void* g) { funlockfile(H(g)); }
static int s_ftrylockfile(void* g) { return ftrylockfile(H(g)); }
// vfscanf: a Darwin arm64 va_list points at consecutive 8-byte argument slots (as fscanf's, up to 8 targets)
static int s_vfscanf(void* g, const char* fmt, const uint64_t* ap) {
    int r = fscanf(H(g), fmt, (void*)ap[0], (void*)ap[1], (void*)ap[2], (void*)ap[3], (void*)ap[4], (void*)ap[5],
                   (void*)ap[6], (void*)ap[7]);
    OUT(g);
    return r;
}

struct StdioEntry { const char* name; void* fn; };
static const StdioEntry kStdio[] = {
    {"_fopen", (void*)&s_fopen}, {"_fopen$DARWIN_EXTSN", (void*)&s_fopen},
    {"_fdopen", (void*)&s_fdopen}, {"_fdopen$DARWIN_EXTSN", (void*)&s_fdopen},
    {"_freopen", (void*)&s_freopen}, {"_freopen$DARWIN_EXTSN", (void*)&s_freopen},
    {"_popen", (void*)&s_popen}, {"_popen$DARWIN_EXTSN", (void*)&s_popen}, {"_pclose", (void*)&s_pclose},
    {"_tmpfile", (void*)&s_tmpfile}, {"_fmemopen", (void*)&s_fmemopen}, {"_open_memstream", (void*)&s_open_memstream},
    {"_funopen", (void*)&s_funopen}, {"_fclose", (void*)&s_fclose},
    {"_fgetc", (void*)&s_fgetc}, {"_getc", (void*)&s_fgetc}, {"_getc_unlocked", (void*)&s_getc_unlocked},
    {"_fputc", (void*)&s_fputc}, {"_putc", (void*)&s_fputc}, {"_putc_unlocked", (void*)&s_putc_unlocked},
    {"___srget", (void*)&s_srget}, {"___swbuf", (void*)&s_swbuf}, {"_ungetc", (void*)&s_ungetc},
    {"_getw", (void*)&s_getw}, {"_putw", (void*)&s_putw},
    {"_fread", (void*)&s_fread}, {"_fwrite", (void*)&s_fwrite}, {"_fwrite$UNIX2003", (void*)&s_fwrite},
    {"_fgets", (void*)&s_fgets}, {"_fputs", (void*)&s_fputs}, {"_fputs$UNIX2003", (void*)&s_fputs},
    {"_getdelim", (void*)&s_getdelim}, {"_getline", (void*)&s_getline}, {"_fgetln", (void*)&s_fgetln},
    {"_fgetwc", (void*)&s_fgetwc}, {"_getwc", (void*)&s_fgetwc}, {"_fputwc", (void*)&s_fputwc}, {"_putwc", (void*)&s_fputwc},
    {"_ungetwc", (void*)&s_ungetwc}, {"_fgetws", (void*)&s_fgetws}, {"_fputws", (void*)&s_fputws}, {"_fwide", (void*)&s_fwide},
    {"_fseek", (void*)&s_fseek}, {"_fseeko", (void*)&s_fseeko}, {"_ftell", (void*)&s_ftell}, {"_ftello", (void*)&s_ftello},
    {"_rewind", (void*)&s_rewind}, {"_fgetpos", (void*)&s_fgetpos}, {"_fsetpos", (void*)&s_fsetpos},
    {"_feof", (void*)&s_feof}, {"_feof_unlocked", (void*)&s_feof}, {"_ferror", (void*)&s_ferror},
    {"_ferror_unlocked", (void*)&s_ferror}, {"_clearerr", (void*)&s_clearerr}, {"_clearerr_unlocked", (void*)&s_clearerr},
    {"_fileno", (void*)&s_fileno}, {"_fileno_unlocked", (void*)&s_fileno},
    {"_fflush", (void*)&s_fflush}, {"_fpurge", (void*)&s_fpurge},
    {"_setvbuf", (void*)&s_setvbuf}, {"_setbuf", (void*)&s_setbuf}, {"_setbuffer", (void*)&s_setbuffer},
    {"_setlinebuf", (void*)&s_setlinebuf},
    {"_flockfile", (void*)&s_flockfile}, {"_funlockfile", (void*)&s_funlockfile}, {"_ftrylockfile", (void*)&s_ftrylockfile},
    {"_vfscanf", (void*)&s_vfscanf},
};

void* darwin_stdio_lookup(const char* name) {
    stdio_init();
    for (const StdioEntry& e : kStdio) if (!strcmp(e.name, name)) return e.fn;
    return nullptr;
}

void* darwin_stdio_data_lookup(const char* name) {
    stdio_init();
    if (!strcmp(name, "___sF")) return g_sF;
    if (!strcmp(name, "___stdinp")) return &g_stdp[0];
    if (!strcmp(name, "___stdoutp")) return &g_stdp[1];
    if (!strcmp(name, "___stderrp")) return &g_stdp[2];
    return nullptr;
}

}  // namespace xef
