// XEF — syscall translation. Guest uses the asm-generic table (arm64),
// host is x86-64. Most calls pass through with a renumbering; a few need
// structure / flag conversion or emulation.
#include "os/syscalls.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/utsname.h>
#include <unistd.h>

#include <atomic>
#include <mutex>
#include <string>

#include "loader/elf_loader.h"
#include "os/signals.h"
#include "os/thread.h"
#include "runtime/dispatch.h"

namespace xef {

i16 g_passthrough_nr[512];

static inline i64 raw(long nr, u64 a = 0, u64 b = 0, u64 c = 0, u64 d = 0, u64 e = 0, u64 f = 0) {
    i64 ret;
    register u64 r10 __asm__("r10") = d;
    register u64 r8 __asm__("r8") = e;
    register u64 r9 __asm__("r9") = f;
    __asm__ volatile("syscall"
                     : "=a"(ret)
                     : "a"(nr), "D"(a), "S"(b), "d"(c), "r"(r10), "r"(r8), "r"(r9)
                     : "rcx", "r11", "memory");
    return ret;
}

// ---- guest syscall numbers (asm-generic) ----
enum GuestNr {
    G_getcwd = 17, G_eventfd2 = 19, G_epoll_create1 = 20, G_epoll_ctl = 21, G_epoll_pwait = 22, G_dup = 23,
    G_dup3 = 24, G_fcntl = 25, G_inotify_init1 = 26, G_ioctl = 29, G_flock = 32, G_mknodat = 33, G_mkdirat = 34,
    G_unlinkat = 35, G_symlinkat = 36, G_linkat = 37, G_renameat = 38, G_statfs = 43, G_fstatfs = 44,
    G_truncate = 45, G_ftruncate = 46, G_fallocate = 47, G_faccessat = 48, G_chdir = 49, G_fchdir = 50,
    G_chroot = 51, G_fchmod = 52, G_fchmodat = 53, G_fchownat = 54, G_fchown = 55, G_openat = 56, G_close = 57,
    G_pipe2 = 59, G_getdents64 = 61, G_lseek = 62, G_read = 63, G_write = 64, G_readv = 65, G_writev = 66,
    G_pread64 = 67, G_pwrite64 = 68, G_preadv = 69, G_pwritev = 70, G_sendfile = 71, G_pselect6 = 72,
    G_ppoll = 73, G_readlinkat = 78, G_newfstatat = 79, G_fstat = 80, G_sync = 81, G_fsync = 82,
    G_fdatasync = 83, G_timerfd_create = 85, G_timerfd_settime = 86, G_timerfd_gettime = 87, G_utimensat = 88,
    G_capget = 90, G_personality = 92, G_exit = 93, G_exit_group = 94, G_waitid = 95, G_set_tid_address = 96,
    G_unshare = 97, G_futex = 98, G_set_robust_list = 99, G_get_robust_list = 100, G_nanosleep = 101,
    G_getitimer = 102, G_setitimer = 103, G_timer_create = 107, G_timer_gettime = 108,
    G_timer_getoverrun = 109, G_timer_settime = 110, G_timer_delete = 111, G_clock_settime = 112,
    G_clock_gettime = 113, G_clock_getres = 114, G_clock_nanosleep = 115, G_sched_setparam = 118,
    G_sched_setscheduler = 119, G_sched_getscheduler = 120, G_sched_getparam = 121,
    G_sched_setaffinity = 122, G_sched_getaffinity = 123, G_sched_yield = 124,
    G_sched_get_priority_max = 125, G_sched_get_priority_min = 126, G_kill = 129, G_tkill = 130,
    G_tgkill = 131, G_sigaltstack = 132, G_rt_sigsuspend = 133, G_rt_sigaction = 134,
    G_rt_sigprocmask = 135, G_rt_sigpending = 136, G_rt_sigtimedwait = 137, G_rt_sigqueueinfo = 138,
    G_rt_sigreturn = 139, G_setpriority = 140, G_getpriority = 141, G_setregid = 143, G_setgid = 144,
    G_setreuid = 145, G_setuid = 146, G_setresuid = 147, G_getresuid = 148, G_setresgid = 149,
    G_getresgid = 150, G_times = 153, G_setpgid = 154, G_getpgid = 155, G_getsid = 156, G_setsid = 157,
    G_getgroups = 158, G_setgroups = 159, G_uname = 160, G_sethostname = 161, G_getrlimit = 163,
    G_setrlimit = 164, G_getrusage = 165, G_umask = 166, G_prctl = 167, G_getcpu = 168,
    G_gettimeofday = 169, G_getpid = 172, G_getppid = 173, G_getuid = 174, G_geteuid = 175,
    G_getgid = 176, G_getegid = 177, G_gettid = 178, G_sysinfo = 179, G_shmget = 194, G_shmctl = 195,
    G_shmat = 196, G_shmdt = 197, G_socket = 198, G_socketpair = 199, G_bind = 200, G_listen = 201,
    G_accept = 202, G_connect = 203, G_getsockname = 204, G_getpeername = 205, G_sendto = 206,
    G_recvfrom = 207, G_setsockopt = 208, G_getsockopt = 209, G_shutdown = 210, G_sendmsg = 211,
    G_recvmsg = 212, G_readahead = 213, G_brk = 214, G_munmap = 215, G_mremap = 216, G_clone = 220,
    G_execve = 221, G_mmap = 222, G_fadvise64 = 223, G_mprotect = 226, G_msync = 227, G_mlock = 228,
    G_munlock = 229, G_mincore = 232, G_madvise = 233, G_accept4 = 242, G_recvmmsg = 243, G_wait4 = 260,
    G_prlimit64 = 261, G_syncfs = 267, G_sendmmsg = 269, G_renameat2 = 276, G_getrandom = 278,
    G_memfd_create = 279, G_membarrier = 283, G_copy_file_range = 285, G_statx = 291, G_rseq = 293,
    G_clone3 = 435, G_close_range = 436, G_openat2 = 437, G_faccessat2 = 439, G_epoll_pwait2 = 441,
    G_futex_waitv = 449, G_fchmodat2 = 452,
};

struct Pair { i16 g, h; };
static const Pair kPass[] = {
    {G_getcwd, SYS_getcwd}, {G_eventfd2, SYS_eventfd2}, {G_epoll_create1, SYS_epoll_create1}, {G_dup, SYS_dup},
    {G_dup3, SYS_dup3}, {G_inotify_init1, SYS_inotify_init1}, {27, SYS_inotify_add_watch},
    {28, SYS_inotify_rm_watch}, {G_ioctl, SYS_ioctl}, {G_flock, SYS_flock}, {G_mknodat, SYS_mknodat},
    {G_mkdirat, SYS_mkdirat}, {G_unlinkat, SYS_unlinkat}, {G_symlinkat, SYS_symlinkat}, {G_linkat, SYS_linkat},
    {G_renameat, SYS_renameat}, {G_statfs, SYS_statfs}, {G_fstatfs, SYS_fstatfs}, {G_truncate, SYS_truncate},
    {G_ftruncate, SYS_ftruncate}, {G_fallocate, SYS_fallocate}, {G_chdir, SYS_chdir}, {G_fchdir, SYS_fchdir},
    {G_chroot, SYS_chroot}, {G_fchmod, SYS_fchmod}, {G_fchmodat, SYS_fchmodat}, {G_fchownat, SYS_fchownat},
    {G_fchown, SYS_fchown}, {G_close, SYS_close}, {G_pipe2, SYS_pipe2}, {G_getdents64, SYS_getdents64},
    {G_lseek, SYS_lseek}, {G_read, SYS_read}, {G_write, SYS_write}, {G_readv, SYS_readv},
    {G_writev, SYS_writev}, {G_pread64, SYS_pread64}, {G_pwrite64, SYS_pwrite64}, {G_preadv, SYS_preadv},
    {G_pwritev, SYS_pwritev}, {G_sendfile, SYS_sendfile}, {G_pselect6, SYS_pselect6}, {G_ppoll, SYS_ppoll},
    {G_sync, SYS_sync}, {G_fsync, SYS_fsync}, {G_fdatasync, SYS_fdatasync},
    {G_timerfd_create, SYS_timerfd_create}, {G_timerfd_settime, SYS_timerfd_settime},
    {G_timerfd_gettime, SYS_timerfd_gettime}, {G_utimensat, SYS_utimensat}, {G_capget, SYS_capget},
    {G_personality, SYS_personality}, {G_waitid, SYS_waitid}, {G_set_tid_address, SYS_set_tid_address},
    {G_unshare, SYS_unshare}, {G_futex, SYS_futex}, {G_set_robust_list, SYS_set_robust_list},
    {G_get_robust_list, SYS_get_robust_list}, {G_nanosleep, SYS_nanosleep}, {G_getitimer, SYS_getitimer},
    {G_setitimer, SYS_setitimer}, {G_timer_create, SYS_timer_create}, {G_timer_gettime, SYS_timer_gettime},
    {G_timer_getoverrun, SYS_timer_getoverrun}, {G_timer_settime, SYS_timer_settime},
    {G_timer_delete, SYS_timer_delete}, {G_clock_settime, SYS_clock_settime},
    {G_clock_gettime, SYS_clock_gettime}, {G_clock_getres, SYS_clock_getres},
    {G_clock_nanosleep, SYS_clock_nanosleep}, {G_sched_setparam, SYS_sched_setparam},
    {G_sched_setscheduler, SYS_sched_setscheduler}, {G_sched_getscheduler, SYS_sched_getscheduler},
    {G_sched_getparam, SYS_sched_getparam}, {G_sched_setaffinity, SYS_sched_setaffinity},
    {G_sched_getaffinity, SYS_sched_getaffinity}, {G_sched_yield, SYS_sched_yield},
    {G_sched_get_priority_max, SYS_sched_get_priority_max},
    {G_sched_get_priority_min, SYS_sched_get_priority_min}, {G_kill, SYS_kill}, {G_tkill, SYS_tkill},
    {G_tgkill, SYS_tgkill}, {G_rt_sigpending, SYS_rt_sigpending}, {G_rt_sigtimedwait, SYS_rt_sigtimedwait},
    {G_rt_sigqueueinfo, SYS_rt_sigqueueinfo}, {G_setpriority, SYS_setpriority},
    {G_getpriority, SYS_getpriority}, {G_setregid, SYS_setregid}, {G_setgid, SYS_setgid},
    {G_setreuid, SYS_setreuid}, {G_setuid, SYS_setuid}, {G_setresuid, SYS_setresuid},
    {G_getresuid, SYS_getresuid}, {G_setresgid, SYS_setresgid}, {G_getresgid, SYS_getresgid},
    {G_times, SYS_times}, {G_setpgid, SYS_setpgid}, {G_getpgid, SYS_getpgid}, {G_getsid, SYS_getsid},
    {G_setsid, SYS_setsid}, {G_getgroups, SYS_getgroups}, {G_setgroups, SYS_setgroups},
    {G_sethostname, SYS_sethostname}, {G_getrlimit, SYS_getrlimit}, {G_setrlimit, SYS_setrlimit},
    {G_getrusage, SYS_getrusage}, {G_umask, SYS_umask}, {G_getcpu, SYS_getcpu},
    {G_gettimeofday, SYS_gettimeofday}, {G_getpid, SYS_getpid}, {G_getppid, SYS_getppid},
    {G_getuid, SYS_getuid}, {G_geteuid, SYS_geteuid}, {G_getgid, SYS_getgid}, {G_getegid, SYS_getegid},
    {G_gettid, SYS_gettid}, {G_sysinfo, SYS_sysinfo}, {G_shmget, SYS_shmget}, {G_shmctl, SYS_shmctl},
    {G_shmdt, SYS_shmdt}, {G_socket, SYS_socket}, {G_socketpair, SYS_socketpair}, {G_bind, SYS_bind},
    {G_listen, SYS_listen}, {G_accept, SYS_accept}, {G_connect, SYS_connect},
    {G_getsockname, SYS_getsockname}, {G_getpeername, SYS_getpeername}, {G_sendto, SYS_sendto},
    {G_recvfrom, SYS_recvfrom}, {G_setsockopt, SYS_setsockopt}, {G_getsockopt, SYS_getsockopt},
    {G_shutdown, SYS_shutdown}, {G_sendmsg, SYS_sendmsg}, {G_recvmsg, SYS_recvmsg},
    {G_readahead, SYS_readahead}, {G_fadvise64, SYS_fadvise64}, {G_msync, SYS_msync}, {G_mlock, SYS_mlock},
    {G_munlock, SYS_munlock}, {G_mincore, SYS_mincore}, {G_madvise, SYS_madvise}, {G_accept4, SYS_accept4},
    {G_recvmmsg, SYS_recvmmsg}, {G_wait4, SYS_wait4}, {G_prlimit64, SYS_prlimit64}, {G_syncfs, SYS_syncfs},
    {G_sendmmsg, SYS_sendmmsg}, {G_renameat2, SYS_renameat2}, {G_getrandom, SYS_getrandom},
    {G_memfd_create, SYS_memfd_create}, {G_membarrier, SYS_membarrier},
    {G_copy_file_range, SYS_copy_file_range}, {G_statx, SYS_statx}, {G_close_range, 436},
    {G_faccessat2, 439}, {G_futex_waitv, 449}, {G_fchmodat2, 452},
};

// ---- process state ----
static std::mutex g_mm_lock;
static GuestAddr g_brk_start, g_brk_cur, g_brk_mapped;
static std::string g_exe_realpath;

std::string guest_exe_path() { return g_exe_realpath; }

void syscalls_init(const LoadedImage& img) {
    for (auto& v : g_passthrough_nr) v = -1;
    for (auto& p : kPass) g_passthrough_nr[p.g] = p.h;
    g_brk_start = g_brk_cur = g_brk_mapped = align_up<u64>(img.brk_start, 4096);
    char buf[PATH_MAX];
    if (realpath(img.host_path.c_str(), buf)) g_exe_realpath = buf;
    else g_exe_realpath = img.exe_path;
}

// ---- conversions ----
static int open_flags_g2h(u64 f) {
    u64 r = f & ~(u64)(0x4000 | 0x8000 | 0x10000 | 0x20000);
    if (f & 0x4000) r |= O_DIRECTORY;
    if (f & 0x8000) r |= O_NOFOLLOW;
    if (f & 0x10000) r |= O_DIRECT;
    if (f & 0x20000) r |= O_LARGEFILE;
    return (int)r;
}
static u64 open_flags_h2g(u64 f) {
    u64 r = f & ~(u64)(O_DIRECTORY | O_NOFOLLOW | O_DIRECT | O_LARGEFILE);
    if (f & O_DIRECTORY) r |= 0x4000;
    if (f & O_NOFOLLOW) r |= 0x8000;
    if (f & O_DIRECT) r |= 0x10000;
    if (f & O_LARGEFILE) r |= 0x20000;
    return r;
}

struct HostStat {  // x86-64 struct stat
    u64 st_dev, st_ino, st_nlink;
    u32 st_mode, st_uid, st_gid, pad0;
    u64 st_rdev;
    i64 st_size, st_blksize, st_blocks;
    i64 st_atime_, st_atime_nsec, st_mtime_, st_mtime_nsec, st_ctime_, st_ctime_nsec;
    i64 unused[3];
};
struct GuestStat {  // asm-generic struct stat (arm64)
    u64 st_dev, st_ino;
    u32 st_mode, st_nlink, st_uid, st_gid;
    u64 st_rdev, pad1;
    i64 st_size;
    i32 st_blksize, pad2;
    i64 st_blocks;
    i64 st_atime_, st_atime_nsec, st_mtime_, st_mtime_nsec, st_ctime_, st_ctime_nsec;
    u32 unused4, unused5;
};
static_assert(sizeof(HostStat) == 144 && sizeof(GuestStat) == 128);

static void stat_h2g(const HostStat& h, GuestStat* g) {
    GuestStat s{};
    s.st_dev = h.st_dev; s.st_ino = h.st_ino; s.st_mode = h.st_mode; s.st_nlink = (u32)h.st_nlink;
    s.st_uid = h.st_uid; s.st_gid = h.st_gid; s.st_rdev = h.st_rdev; s.st_size = h.st_size;
    s.st_blksize = (i32)h.st_blksize; s.st_blocks = h.st_blocks;
    s.st_atime_ = h.st_atime_; s.st_atime_nsec = h.st_atime_nsec;
    s.st_mtime_ = h.st_mtime_; s.st_mtime_nsec = h.st_mtime_nsec;
    s.st_ctime_ = h.st_ctime_; s.st_ctime_nsec = h.st_ctime_nsec;
    memcpy(g, &s, sizeof s);
}

struct HostEpollEvent { u32 events; u64 data; } __attribute__((packed));
struct GuestEpollEvent { u32 events; u32 pad; u64 data; };

// path redirection into the guest rootfs
struct PathArg {
    std::string s;
    const char* p;
    explicit PathArg(u64 guest) {
        const char* g = (const char*)guest;
        if (!g) { p = nullptr; return; }
        if (g[0] == '/' && !g_rootfs.empty()) { s = resolve_guest_path(g); p = s.c_str(); }
        else p = g;
    }
};

static bool is_proc_self_exe(const char* p) {
    if (!p) return false;
    if (!strcmp(p, "/proc/self/exe")) return true;
    char buf[64];
    snprintf(buf, sizeof buf, "/proc/%d/exe", getpid());
    return !strcmp(p, buf);
}

static i64 do_brk(u64 newbrk) {
    std::lock_guard<std::mutex> g(g_mm_lock);
    if (newbrk < g_brk_start) return (i64)g_brk_cur;
    u64 need = align_up<u64>(newbrk, 4096);
    if (need > g_brk_mapped) {
        void* r = mmap((void*)g_brk_mapped, need - g_brk_mapped, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
        if (r == MAP_FAILED || (u64)r != g_brk_mapped) {
            if (r != MAP_FAILED) munmap(r, need - g_brk_mapped);
            return (i64)g_brk_cur;
        }
        g_brk_mapped = need;
    } else if (need < g_brk_mapped) {
        munmap((void*)need, g_brk_mapped - need);
        g_brk_mapped = need;
    }
    g_brk_cur = newbrk;
    return (i64)g_brk_cur;
}

static inline int prot_g2h(u64 p) { return (int)(p & 7); }  // drop PROT_BTI (0x10), PROT_MTE (0x20)

void do_syscall(CpuState* st) {
    u64 nr = st->x[8];
    u64 a0 = st->x[0], a1 = st->x[1], a2 = st->x[2], a3 = st->x[3], a4 = st->x[4], a5 = st->x[5];
    i64 r;
    if (nr < 512 && g_passthrough_nr[nr] >= 0) {
        r = raw(g_passthrough_nr[nr], a0, a1, a2, a3, a4, a5);
        st->x[0] = (u64)r;
        return;
    }
    switch (nr) {
    case G_openat: {
        PathArg p(a1);
        if (is_proc_self_exe((const char*)a1)) { r = raw(SYS_openat, a0, (u64)g_exe_realpath.c_str(), open_flags_g2h(a2), a3); break; }
        r = raw(SYS_openat, a0, (u64)p.p, open_flags_g2h(a2), a3);
        break;
    }
    case G_openat2: r = -ENOSYS; break;
    case G_faccessat: { PathArg p(a1); r = raw(SYS_faccessat, a0, (u64)p.p, a2); break; }
    case G_fcntl: {
        if (a1 == F_SETFL) r = raw(SYS_fcntl, a0, a1, open_flags_g2h(a2));
        else if (a1 == F_GETFL) { r = raw(SYS_fcntl, a0, a1, a2); if (r >= 0) r = (i64)open_flags_h2g((u64)r); }
        else r = raw(SYS_fcntl, a0, a1, a2);
        break;
    }
    case G_readlinkat: {
        const char* path = (const char*)a1;
        if (is_proc_self_exe(path)) {
            size_t n = std::min<size_t>(g_exe_realpath.size(), a3);
            memcpy((void*)a2, g_exe_realpath.data(), n);
            r = (i64)n;
        } else {
            PathArg p(a1);
            r = raw(SYS_readlinkat, a0, (u64)p.p, a2, a3);
        }
        break;
    }
    case G_fstat: {
        HostStat hs;
        r = raw(SYS_fstat, a0, (u64)&hs);
        if (r == 0) stat_h2g(hs, (GuestStat*)a1);
        break;
    }
    case G_newfstatat: {
        HostStat hs;
        PathArg p(a1);
        r = raw(SYS_newfstatat, a0, (u64)p.p, (u64)&hs, a3);
        if (r == 0) stat_h2g(hs, (GuestStat*)a2);
        break;
    }
    case G_statx: { PathArg p(a1); r = raw(SYS_statx, a0, (u64)p.p, a2, a3, a4); break; }
    case G_exit:
        thread_exit(st, (int)a0);
        return;  // not reached for the last thread
    case G_exit_group:
        signals_flush_output();
        raw(SYS_exit_group, a0);
        __builtin_unreachable();
    case G_brk: r = do_brk(a0); break;
    case G_mmap: {
        int flags = (int)a3;
        r = raw(SYS_mmap, a0, a1, prot_g2h(a2), (u64)flags, a4, a5);
        if (r >= 0 && (flags & MAP_FIXED)) code_invalidate_range((GuestAddr)r, a1);
        break;
    }
    case G_mprotect:
        r = raw(SYS_mprotect, a0, a1, prot_g2h(a2));
        // code made writable or non-executable will change before it runs again (W^X JITs)
        if (r == 0 && ((a2 & PROT_WRITE) || !(a2 & PROT_EXEC))) code_invalidate_range(a0, a1);
        break;
    case G_munmap:
        r = raw(SYS_munmap, a0, a1);
        if (r == 0) code_invalidate_range(a0, a1);
        break;
    case G_mremap:
        r = raw(SYS_mremap, a0, a1, a2, a3, a4);
        if (r >= 0) code_invalidate_range(a0, a1);
        break;
    case G_uname: {
        r = raw(SYS_uname, a0);
        if (r == 0) {
            struct utsname* u = (struct utsname*)a0;
            strcpy(u->machine, "aarch64");
        }
        break;
    }
    case G_rseq: r = -ENOSYS; break;
    case G_prctl: r = raw(SYS_prctl, a0, a1, a2, a3, a4); break;
    case G_epoll_ctl: {
        if (a3) {
            GuestEpollEvent* ge = (GuestEpollEvent*)a3;
            HostEpollEvent he{ge->events, ge->data};
            r = raw(SYS_epoll_ctl, a0, a1, a2, (u64)&he);
        } else r = raw(SYS_epoll_ctl, a0, a1, a2, 0);
        break;
    }
    case G_epoll_pwait: case G_epoll_pwait2: {
        int maxev = (int)a2;
        if (maxev <= 0 || maxev > 4096) { r = -EINVAL; break; }
        HostEpollEvent* he = (HostEpollEvent*)alloca(sizeof(HostEpollEvent) * maxev);
        r = raw(nr == G_epoll_pwait ? SYS_epoll_pwait : 441, a0, (u64)he, a2, a3, a4, a5);
        if (r > 0) {
            GuestEpollEvent* ge = (GuestEpollEvent*)a1;
            for (int i = 0; i < r; i++) { ge[i].events = he[i].events; ge[i].pad = 0; ge[i].data = he[i].data; }
        }
        break;
    }
    case G_shmat: r = raw(SYS_shmat, a0, a1, a2); break;
    case G_rt_sigaction: r = sig_rt_sigaction(st, (int)a0, a1, a2, a3); break;
    case G_rt_sigprocmask: r = sig_rt_sigprocmask(st, (int)a0, a1, a2, a3); break;
    case G_rt_sigreturn: sig_rt_sigreturn(st); return;
    case G_rt_sigsuspend: r = sig_rt_sigsuspend(st, a0, a1); break;
    case G_sigaltstack: r = sig_sigaltstack(st, a0, a1); break;
    case G_clone: r = thread_clone(st, a0, a1, a2, a3, a4); break;
    case G_clone3: r = -ENOSYS; break;  // glibc falls back to clone
    case G_execve: r = process_execve(st, a0, a1, a2); break;
    default:
        XEF_LOG(1, "unsupported syscall %lu", (unsigned long)nr);
        r = -ENOSYS;
        break;
    }
    st->x[0] = (u64)r;
}

}  // namespace xef
