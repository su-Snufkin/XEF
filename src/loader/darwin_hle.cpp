// XEF-OSX — Darwin High-Level Emulation (HLE) Runtime implementation.
#include "loader/darwin_hle.h"
#include "loader/elf_loader.h"
#include "os/darwin/darwin_types.h"
#include "os/thread.h"
#include "os/signals.h"
#include "thunks/thunks.h"
#include "runtime/dispatch.h"

#include <dlfcn.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/random.h>
#include <sys/epoll.h>
#include <sched.h>
#include <pthread.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <ctype.h>
#include <math.h>
#include <chrono>
#include <condition_variable>
#include <vector>
#include <unordered_map>
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
};

static std::vector<ThunkEntry> g_thunks;
static std::unordered_map<std::string, uint64_t> g_symbol_cache;

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
uint64_t g_darwin_thread_exit_trampoline = 0;
const uint8_t* g_darwin_tlv_template = nullptr;
size_t g_darwin_tlv_template_size = 0;

// Darwin RuneLocale (ctype) structures
struct DarwinRuneLocale {
    char magic[8];
    char encoding[32];
    uint32_t (*sgetrune)(const char*, size_t, char const**);
    int (*sputrune)(uint32_t, char*, size_t, char**);
    uint32_t invalid_rune;
    uint32_t runetype[256];
    uint32_t maplower[256];
    uint32_t mapupper[256];
};

static DarwinRuneLocale g_darwin_rune_locale;

static void init_rune_locale() {
    memcpy(g_darwin_rune_locale.magic, "RuneMagi", 8);
    strcpy(g_darwin_rune_locale.encoding, "NONE");
    g_darwin_rune_locale.invalid_rune = 0xffffffff;

    for (int i = 0; i < 256; i++) {
        uint32_t flags = 0;
        if (isalpha(i)) flags |= 0x00000100; // _CTYPE_A
        if (isupper(i)) flags |= 0x00000200; // _CTYPE_U
        if (islower(i)) flags |= 0x00000400; // _CTYPE_L
        if (isdigit(i)) flags |= 0x00000800; // _CTYPE_D
        if (isspace(i)) flags |= 0x00004000; // _CTYPE_S
        if (isprint(i)) flags |= 0x00040000; // _CTYPE_R
        if (isxdigit(i)) flags |= 0x00010000; // _CTYPE_X
        if (ispunct(i)) flags |= 0x00002000; // _CTYPE_P
        g_darwin_rune_locale.runetype[i] = flags;
        g_darwin_rune_locale.maplower[i] = tolower(i);
        g_darwin_rune_locale.mapupper[i] = toupper(i);
    }
}

// Special wrapper functions
static int* darwin_error_wrapper() {
    return &errno;
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
    return memcpy(dst, src, len);
}

static std::vector<u64> g_guest_atexit;
static int darwin_atexit_wrapper(u64 fn) {
    if (fn) {
        g_guest_atexit.push_back(fn);
    }
    return 0;
}

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

static int darwin_vsnprintf(char* str, size_t size, const char* format, const uint64_t* ap) {
    if (!str || size == 0) return 0;
    if (!format) { str[0] = '\0'; return 0; }

    char* out = str;
    size_t rem = size;
    const char* p = format;

    auto append_char = [&](char c) {
        if (rem > 1) {
            *out++ = c;
            rem--;
        }
    };

    while (*p) {
        if (*p != '%') {
            append_char(*p++);
            continue;
        }

        p++; // skip '%'
        if (*p == '%') {
            append_char('%');
            p++;
            continue;
        }

        // Parse format specifier
        const char* spec_start = p - 1;
        while (*p && !strchr("diouxXeEfFgGaAcspn", *p)) {
            p++;
        }
        if (!*p) break;

        char conv = *p++;
        std::string raw_spec(spec_start, p - spec_start);

        // Handle '*' in width/precision
        std::string spec;
        size_t star_pos = raw_spec.find('*');
        if (star_pos != std::string::npos) {
            int star_val = (int)(*ap++);
            spec = raw_spec.substr(0, star_pos) + std::to_string(star_val) + raw_spec.substr(star_pos + 1);
            star_pos = spec.find('*');
            if (star_pos != std::string::npos) {
                int star_val2 = (int)(*ap++);
                spec = spec.substr(0, star_pos) + std::to_string(star_val2) + spec.substr(star_pos + 1);
            }
        } else {
            spec = raw_spec;
        }

        char buf[512];
        int n = 0;

        if (strchr("eEfFgGaA", conv)) {
            double val;
            memcpy(&val, ap++, sizeof(double));
            n = snprintf(buf, sizeof(buf), spec.c_str(), val);
        } else if (conv == 's') {
            const char* s = (const char*)(uintptr_t)(*ap++);
            if (!s) s = "(null)";
            n = snprintf(buf, sizeof(buf), spec.c_str(), s);
        } else if (conv == 'p') {
            void* ptr = (void*)(uintptr_t)(*ap++);
            n = snprintf(buf, sizeof(buf), spec.c_str(), ptr);
        } else if (conv == 'c') {
            int c = (int)(*ap++);
            n = snprintf(buf, sizeof(buf), spec.c_str(), c);
        } else if (conv == 'n') {
            int* ptr = (int*)(uintptr_t)(*ap++);
            if (ptr) *ptr = (int)(out - str);
            n = 0;
        } else {
            uint64_t val = *ap++;
            std::string llspec = "%";
            size_t idx = 1;
            while (idx < spec.size() - 1 && (isdigit(spec[idx]) || strchr("-+ #0.", spec[idx]))) {
                llspec += spec[idx++];
            }
            llspec += "ll";
            llspec += conv;
            n = snprintf(buf, sizeof(buf), llspec.c_str(), (unsigned long long)val);
        }

        if (n > 0) {
            for (int k = 0; k < n; k++) {
                append_char(buf[k]);
            }
        }
    }

    if (rem > 0) {
        *out = '\0';
    } else {
        str[size - 1] = '\0';
    }

    return (int)(out - str);
}

static int darwin_vfprintf(FILE* stream, const char* format, const uint64_t* ap) {
    if (!stream || !format) return 0;
    char buf[16384];
    int len = darwin_vsnprintf(buf, sizeof(buf), format, ap);
    if (len > 0) {
        fwrite(buf, 1, len, stream);
    }
    return len;
}

static int darwin_fprintf(FILE* stream, const char* format, const uint64_t* ap) {
    return darwin_vfprintf(stream, format, ap);
}

static int darwin_printf(const char* format, const uint64_t* ap) {
    return darwin_vfprintf(stdout, format, ap);
}

static int darwin_snprintf(char* str, size_t size, const char* format, const uint64_t* ap) {
    int len = darwin_vsnprintf(str, size, format, ap);
    fprintf(stderr, "\n[DEBUG snprintf: fmt='%s', result='%s', ap=%p, ap[0]=%#lx]\n",
            format, str ? str : "(null)", ap, ap ? ap[0] : 0);
    return len;
}

static int darwin_strerror_r(int errnum, char* buf, size_t buflen) {
    if (!buf || buflen == 0) return ERANGE;
    const char* msg = strerror(errnum);
    if (!msg) msg = "Unknown error";
    strncpy(buf, msg, buflen - 1);
    buf[buflen - 1] = '\0';
    return 0;
}

static void* darwin_mmap(void* addr, size_t length, int prot, int dflags, int fd, off_t offset) {
    int lflags = 0;
    if (dflags & 0x0001) lflags |= MAP_SHARED;
    if (dflags & 0x0002) lflags |= MAP_PRIVATE;
    if (dflags & 0x0010) lflags |= MAP_FIXED;
    if (dflags & 0x1000) lflags |= MAP_ANONYMOUS;

    if (lflags & MAP_ANONYMOUS) {
        fd = -1;
        offset = 0;
    }

    void* r = mmap(addr, length, prot, lflags, fd, offset);
    XEF_LOG(2, "darwin_mmap(addr=%p, len=%#zx, prot=%#x, dflags=%#x -> lflags=%#x, fd=%d, off=%#lx) = %p (errno=%d)",
            addr, length, prot, dflags, lflags, fd, (unsigned long)offset, r, (r == MAP_FAILED) ? errno : 0);
    return r;
}

static long darwin_sysconf(int name) {
    switch (name) {
    case 29: // Darwin _SC_PAGESIZE / _SC_PAGE_SIZE
        return 4096;
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

// Pthread stack query helpers
struct DarwinThreadStackInfo {
    void* stack_top;
    size_t stack_size;
};
static std::mutex g_thread_stacks_lock;
static std::unordered_map<uint64_t, DarwinThreadStackInfo> g_thread_stacks;

void darwin_register_thread_stack(pthread_t th, void* stack_top, size_t stack_size) {
    std::lock_guard<std::mutex> lk(g_thread_stacks_lock);
    g_thread_stacks[(uint64_t)th] = {stack_top, stack_size};
}

static void* darwin_pthread_get_stackaddr_np(void* thread) {
    uint64_t th = thread ? (uint64_t)(uintptr_t)thread : (uint64_t)pthread_self();
    {
        std::lock_guard<std::mutex> lk(g_thread_stacks_lock);
        auto it = g_thread_stacks.find(th);
        if (it != g_thread_stacks.end()) {
            XEF_LOG(2, "pthread_get_stackaddr_np(th=%p): returning %p", (void*)th, it->second.stack_top);
            return it->second.stack_top;
        }
    }
    XEF_LOG(2, "pthread_get_stackaddr_np: returning fallback %p", (void*)g_darwin_stack_top);
    return (void*)(uintptr_t)g_darwin_stack_top;
}

static size_t darwin_pthread_get_stacksize_np(void* thread) {
    uint64_t th = thread ? (uint64_t)(uintptr_t)thread : (uint64_t)pthread_self();
    {
        std::lock_guard<std::mutex> lk(g_thread_stacks_lock);
        auto it = g_thread_stacks.find(th);
        if (it != g_thread_stacks.end()) {
            XEF_LOG(2, "pthread_get_stacksize_np(th=%p): returning %#zx", (void*)th, it->second.stack_size);
            return it->second.stack_size;
        }
    }
    XEF_LOG(2, "pthread_get_stacksize_np: returning fallback %#zx", (size_t)g_darwin_stack_size);
    return (size_t)g_darwin_stack_size;
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
static char*** darwin_NSGetEnviron() { return &g_darwin_envp; }
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
    dst->st_dev           = (int32_t)src.st_dev;
    dst->st_mode          = (uint16_t)src.st_mode;
    dst->st_nlink         = (uint16_t)src.st_nlink;
    dst->st_ino           = (uint64_t)src.st_ino;
    dst->st_uid           = (uint32_t)src.st_uid;
    dst->st_gid           = (uint32_t)src.st_gid;
    dst->st_rdev          = (int32_t)src.st_rdev;
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
    std::string hp = resolve_guest_path(path);
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

static int darwin_fstatat_fn(int dfd, const char* path, darwin_stat64* dst, int flag) {
    if (!path || !dst) { errno = EFAULT; return -1; }
    struct stat host_st;
    int lflags = 0;
    if (flag & 0x002) lflags |= AT_SYMLINK_NOFOLLOW;
    int r = fstatat(dfd, path, &host_st, lflags);
    if (r < 0) return -1;
    convert_stat_to_darwin(host_st, dst);
    return 0;
}

static int darwin_open_flags_to_linux(int df) {
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
    std::string hp = resolve_guest_path(path);
    int lflags = darwin_open_flags_to_linux(dflags);
    return open(hp.c_str(), lflags, mode);
}

static int darwin_openat(int dfd, const char* path, int dflags, mode_t mode) {
    if (!path) { errno = EFAULT; return -1; }
    int lflags = darwin_open_flags_to_linux(dflags);
    return openat(dfd, path, lflags, mode);
}

static DIR* darwin_opendir(const char* name) {
    if (!name) { errno = EFAULT; return nullptr; }
    std::string hp = resolve_guest_path(name);
    return opendir(hp.c_str());
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

static void* darwin_dlsym(void* handle, const char* symbol) {
    (void)handle;
    if (!symbol || !symbol[0]) return nullptr;
    XEF_LOG(2, "darwin_dlsym(handle=%p, symbol='%s')", handle, symbol);
    // Try resolving as Darwin symbol
    uint64_t addr = darwin_hle_resolve_symbol(symbol, true);
    if (!addr && symbol[0] != '_') {
        std::string prefixed = "_" + std::string(symbol);
        addr = darwin_hle_resolve_symbol(prefixed.c_str(), true);
    }
    XEF_LOG(2, "darwin_dlsym('%s') -> %p", symbol, (void*)addr);
    return (void*)(uintptr_t)addr;
}


// Dyld runtime introspection
static uint32_t darwin_dyld_image_count() {
    return 1;
}

static const char* darwin_dyld_get_image_name(uint32_t index) {
    if (index == 0) return g_darwin_exe_path.c_str();
    return nullptr;
}

static intptr_t darwin_dyld_get_image_vmaddr_slide(uint32_t index) {
    (void)index;
    return 0;
}

static void* darwin_dyld_get_image_header(uint32_t index) {
    if (index == 0) return (void*)(uintptr_t)g_darwin_mach_header;
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
    if (!g_thread_tlv_block) {
        g_thread_tlv_block = calloc(1, kDefaultTlvSize);
        if (g_darwin_tlv_template && g_darwin_tlv_template_size > 0) {
            size_t copy_sz = std::min(g_darwin_tlv_template_size, kDefaultTlvSize);
            memcpy(g_thread_tlv_block, g_darwin_tlv_template, copy_sz);
        }
        XEF_LOG(2, "darwin_tlv_bootstrap: allocated and initialized new tlv block %p for pthread %lu",
                g_thread_tlv_block, (unsigned long)pthread_self());
    }
    void* res = (uint8_t*)g_thread_tlv_block + desc->offset;
    XEF_LOG(2, "darwin_tlv_bootstrap(desc=%p, offset=%#lx) on pthread %lu -> %p (val=%#lx)",
            desc, desc->offset, (unsigned long)pthread_self(), res, *(unsigned long*)res);
    return res;
}

static int darwin_tlv_atexit(void (*term)(void*), void* obj, void* dso) {
    (void)term; (void)obj; (void)dso;
    return 0;
}

// Darwin Pthread TSD and Mutex emulation
static constexpr int kMaxTsdKeys = 256;
static void (*g_destructors[kMaxTsdKeys])(void*) = {};
static bool g_key_used[kMaxTsdKeys] = {};
static thread_local void* g_thread_specific[kMaxTsdKeys] = {};
static std::mutex g_tsd_lock;

static int darwin_pthread_key_create(uint64_t* key_out, void (*destructor)(void*)) {
    std::lock_guard<std::mutex> lk(g_tsd_lock);
    for (int i = 1; i < kMaxTsdKeys; i++) {
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
    if (key == 0 || key >= kMaxTsdKeys) return EINVAL;
    g_thread_specific[key] = (void*)value;
    return 0;
}

static void* darwin_pthread_getspecific(uint64_t key) {
    if (key == 0 || key >= kMaxTsdKeys) return nullptr;
    return g_thread_specific[key];
}

static int darwin_pthread_key_delete(uint64_t key) {
    std::lock_guard<std::mutex> lk(g_tsd_lock);
    if (key == 0 || key >= kMaxTsdKeys) return EINVAL;
    g_key_used[key] = false;
    g_destructors[key] = nullptr;
    return 0;
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
    return pthread_join((pthread_t)th, val_out);
}

static int darwin_pthread_detach(uint64_t th) {
    return pthread_detach((pthread_t)th);
}

static uint64_t darwin_pthread_self() {
    return (uint64_t)pthread_self();
}

static void darwin_pthread_exit(void* val) {
    (void)val;
    ThreadCtx* t = tls_thread;
    thread_exit(t ? t->st : nullptr, 0);
}

static int darwin_pthread_setname_np(const char* name) {
    pthread_setname_np(pthread_self(), name);
    return 0;
}

static int darwin_pthread_threadid_np(uint64_t thread, uint64_t* thread_id) {
    if (!thread_id) return EINVAL;
    *thread_id = (thread != 0) ? thread : (uint64_t)pthread_self();
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

static void darwin_os_unfair_lock_lock(os_unfair_lock_s* lock) {
    if (!lock) return;
    uint32_t expected = 0;
    while (!lock->_os_unfair_lock_opaque.compare_exchange_weak(expected, 1, std::memory_order_acquire, std::memory_order_relaxed)) {
        expected = 0;
        sched_yield();
    }
}

static bool darwin_os_unfair_lock_trylock(os_unfair_lock_s* lock) {
    if (!lock) return false;
    uint32_t expected = 0;
    return lock->_os_unfair_lock_opaque.compare_exchange_strong(expected, 1, std::memory_order_acquire, std::memory_order_relaxed);
}

static void darwin_os_unfair_lock_unlock(os_unfair_lock_s* lock) {
    if (!lock) return;
    lock->_os_unfair_lock_opaque.store(0, std::memory_order_release);
}

static int darwin_issetugid() {
    return 0; // Not setuid/setgid
}

static uint64_t darwin_mach_absolute_time() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
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

static int darwin_kqueue() {
    int epfd = epoll_create1(EPOLL_CLOEXEC);
    XEF_LOG(2, "darwin_kqueue() = %d", epfd);
    return epfd;
}

static int darwin_kevent(int kq, const darwin_kevent_t* changelist, int nchanges,
                         darwin_kevent_t* eventlist, int nevents, const struct timespec* timeout) {
    XEF_LOG(2, "darwin_kevent(kq=%d, nchanges=%d, nevents=%d, timeout=%p)",
            kq, nchanges, nevents, timeout);

    int receipts_emitted = 0;

    if (nchanges > 0 && changelist) {
        for (int i = 0; i < nchanges; i++) {
            const darwin_kevent_t& kev = changelist[i];
            XEF_LOG(2, "  change[%d]: ident=%lu, filter=%d, flags=%#x, fflags=%#x, data=%ld, udata=%p",
                    i, (unsigned long)kev.ident, (int)kev.filter, (unsigned)kev.flags,
                    (unsigned)kev.fflags, (long)kev.data, kev.udata);

            int err = 0;
            if (kev.filter == DARWIN_EVFILT_USER) {
                // EVFILT_USER: simulated user event
                err = 0;
            } else {
                int fd = (int)kev.ident;
                struct epoll_event ev;
                memset(&ev, 0, sizeof(ev));
                ev.data.ptr = kev.udata;

                uint32_t events = 0;
                if (kev.filter == DARWIN_EVFILT_READ) events |= EPOLLIN;
                if (kev.filter == DARWIN_EVFILT_WRITE) events |= EPOLLOUT;

                ev.events = events;

                if (kev.flags & DARWIN_EV_ADD) {
                    if (epoll_ctl(kq, EPOLL_CTL_ADD, fd, &ev) < 0) {
                        if (errno == EEXIST) {
                            epoll_ctl(kq, EPOLL_CTL_MOD, fd, &ev);
                        } else {
                            err = errno;
                        }
                    }
                } else if (kev.flags & DARWIN_EV_DELETE) {
                    if (epoll_ctl(kq, EPOLL_CTL_DEL, fd, &ev) < 0) {
                        err = errno;
                    }
                }
            }

            if ((kev.flags & DARWIN_EV_RECEIPT) && eventlist && receipts_emitted < nevents) {
                darwin_kevent_t& rec = eventlist[receipts_emitted++];
                rec = kev;
                rec.flags = DARWIN_EV_ERROR;
                rec.data = err; // 0 on success, or errno
            }
        }
    }

    // If all changes were EV_RECEIPT, kevent returns receipts without waiting
    if (receipts_emitted > 0) {
        return receipts_emitted;
    }

    if (nevents <= 0 || !eventlist) {
        return 0;
    }

    int timeout_ms = -1;
    if (timeout) {
        timeout_ms = (int)(timeout->tv_sec * 1000 + timeout->tv_nsec / 1000000);
    }

    std::vector<struct epoll_event> ep_events(nevents);
    int nfds = epoll_wait(kq, ep_events.data(), nevents, timeout_ms);
    if (nfds < 0) {
        return -1;
    }

    for (int i = 0; i < nfds; i++) {
        darwin_kevent_t& kev = eventlist[i];
        memset(&kev, 0, sizeof(kev));
        kev.udata = ep_events[i].data.ptr;
        if (ep_events[i].events & EPOLLIN) {
            kev.filter = DARWIN_EVFILT_READ;
        } else if (ep_events[i].events & EPOLLOUT) {
            kev.filter = DARWIN_EVFILT_WRITE;
        }
    }

    return nfds;
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

    dlopen("libgcc_s.so.1", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("libpcre2-8.so.0", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("/home/wron4/Pulpit/OSXEMU/lib/usr/lib/libc++abi.so.1", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("/home/wron4/Pulpit/OSXEMU/lib/usr/lib/libc++.so.1", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("libc++abi.so.1", RTLD_GLOBAL | RTLD_LAZY);
    dlopen("libc++.so.1", RTLD_GLOBAL | RTLD_LAZY);

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
}

uint64_t darwin_hle_resolve_symbol(const char* name, bool is_weak) {
    if (!name || !name[0]) return 0;
    darwin_hle_init();

    std::lock_guard<std::mutex> lk(g_hle_lock);
    auto it = g_symbol_cache.find(name);
    if (it != g_symbol_cache.end()) return it->second;

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
    if (strcmp(name, "__DefaultRuneLocale") == 0) {
        uint64_t addr = (uint64_t)(uintptr_t)&g_darwin_rune_locale;
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
    if (strcmp(name, "___error") == 0) {
        host_fn = (void*)&darwin_error_wrapper;
    } else if (strcmp(name, "___stack_chk_fail") == 0) {
        host_fn = (void*)&darwin_stack_chk_fail_wrapper;
    } else if (strcmp(name, "___assert_rtn") == 0) {
        host_fn = (void*)&darwin_assert_rtn_wrapper;
    } else if (strcmp(name, "___maskrune") == 0) {
        host_fn = (void*)&darwin_maskrune_wrapper;
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
    } else if (strcmp(name, "_strerror_r") == 0 || strcmp(name, "strerror_r") == 0) {
        host_fn = (void*)&darwin_strerror_r;
    } else if (strcmp(name, "_mmap") == 0 || strcmp(name, "mmap") == 0) {
        host_fn = (void*)&darwin_mmap;
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
        host_fn = (void*)&darwin_open;
    } else if (strcmp(name, "_openat") == 0 || strcmp(name, "openat") == 0) {
        host_fn = (void*)&darwin_openat;
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
        host_fn = (void*)&darwin_fcntl;
    } else if (strcmp(name, "_dlsym") == 0 || strcmp(name, "dlsym") == 0) {
        host_fn = (void*)&darwin_dlsym;
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
        host_fn = dlsym(RTLD_DEFAULT, clean_name);
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
    g_thunks.push_back({name, host_fn});

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

void darwin_hle_dispatch(CpuState* st) {
    u64 id = st->x[17];
    void* host_fn = nullptr;
    const char* name = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_hle_lock);
        if (id >= g_thunks.size()) {
            fatal("darwin_hle_dispatch: invalid thunk id %lu", (unsigned long)id);
        }
        host_fn = g_thunks[id].host_fn;
        name = g_thunks[id].name.c_str();
    }
    XEF_LOG(2, "hle: %s(x0=%#lx, x1=%#lx, x2=%#lx, x3=%#lx)", name,
            (unsigned long)st->x[0], (unsigned long)st->x[1], (unsigned long)st->x[2], (unsigned long)st->x[3]);

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

    u64 iregs[6] = { st->x[0], st->x[1], st->x[2], st->x[3], st->x[4], st->x[5] };
    u64 fregs[8];
    for (int i = 0; i < 8; i++) memcpy(&fregs[i], st->v[i], 8);

    // Pass guest stack in case function reads stack arguments (e.g. 7th, 8th arguments)
    const uint64_t* guest_stack = (const uint64_t*)(uintptr_t)st->x[kGuestSP];
    u64 xmm0_out = 0;
    u64 ret = xef_call_sysv(host_fn, iregs, fregs, guest_stack, 16, &xmm0_out);
    st->x[0] = ret;
    memcpy(st->v[0], &xmm0_out, 8);
    XEF_LOG(2, "hle: %s -> %#lx", name, (unsigned long)ret);
}

} // namespace xef
