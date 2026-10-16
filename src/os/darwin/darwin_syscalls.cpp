// XEF-OSX — Darwin system call and Mach trap emulation.
#include "os/darwin/darwin_syscalls.h"
#include "os/darwin/darwin_types.h"
#include "os/thread.h"
#include "os/signals.h"
#include "runtime/code_cache.h"
#include "runtime/dispatch.h"
#include "loader/elf_loader.h"
#include "loader/darwin_hle.h"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/sysinfo.h>
#include <sys/ioctl.h>
#include <linux/futex.h>
#include <sched.h>
#include <string.h>
#include <stdio.h>
#include <atomic>
#include <string>

namespace xef {

bool g_is_darwin = false;

static inline void set_darwin_success(CpuState* st, u64 res) {
    st->x[0] = res;
    // In XEF: signals.cpp defines c = !(eflags & 1).
    // To have AArch64 Carry = 0 (Darwin syscall success), eflags bit 0 must be 1.
    st->eflags |= 1;
}

static inline void set_darwin_error(CpuState* st, int err) {
    st->x[0] = (u64)(err < 0 ? -err : err);
    // To have AArch64 Carry = 1 (Darwin syscall error), eflags bit 0 must be 0.
    st->eflags &= ~1ull;
}

static int open_flags_darwin_to_linux(u64 df) {
    int lf = 0;
    if ((df & 3) == DARWIN_O_RDONLY) lf |= O_RDONLY;
    if ((df & 3) == DARWIN_O_WRONLY) lf |= O_WRONLY;
    if ((df & 3) == DARWIN_O_RDWR)   lf |= O_RDWR;
    if (df & DARWIN_O_NONBLOCK)      lf |= O_NONBLOCK;
    if (df & DARWIN_O_APPEND)        lf |= O_APPEND;
    if (df & DARWIN_O_ASYNC)         lf |= O_ASYNC;
    if (df & DARWIN_O_FSYNC)         lf |= O_SYNC;
    if (df & DARWIN_O_NOFOLLOW)      lf |= O_NOFOLLOW;
    if (df & DARWIN_O_CREAT)         lf |= O_CREAT;
    if (df & DARWIN_O_TRUNC)         lf |= O_TRUNC;
    if (df & DARWIN_O_EXCL)          lf |= O_EXCL;
    if (df & DARWIN_O_DIRECTORY)     lf |= O_DIRECTORY;
    if (df & DARWIN_O_CLOEXEC)       lf |= O_CLOEXEC;
    return lf;
}

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

static bool handle_darwin_sysctl(CpuState* st, const int* mib, int namelen,
                                 void* oldp, size_t* oldlenp, void* newp, size_t newlen) {
    if (namelen < 1) return false;

    auto copy_out = [&](const void* data, size_t sz) {
        if (oldlenp) {
            size_t max = *oldlenp;
            *oldlenp = sz;
            if (oldp && max > 0) {
                size_t to_copy = std::min(max, sz);
                memcpy(oldp, data, to_copy);
            }
        }
    };

    auto copy_str = [&](const char* s) { copy_out(s, strlen(s) + 1); };
    auto copy_u32 = [&](uint32_t v) { copy_out(&v, sizeof(v)); };
    auto copy_u64 = [&](uint64_t v) { copy_out(&v, sizeof(v)); };

    if (mib[0] == DARWIN_CTL_KERN) {
        if (namelen < 2) return false;
        switch (mib[1]) {
        case DARWIN_KERN_OSTYPE:    copy_str("Darwin"); return true;
        case DARWIN_KERN_OSRELEASE: copy_str("21.6.0"); return true;
        case DARWIN_KERN_OSREV:     copy_u32(199506); return true;
        case DARWIN_KERN_VERSION:   copy_str("Darwin Kernel Version 21.6.0; root:xnu-8020.140.49~2/RELEASE_ARM64"); return true;
        case DARWIN_KERN_OSVERSION: copy_str("21G115"); return true;
        case DARWIN_KERN_ARGMAX:    copy_u32(1048576); return true;
        case DARWIN_KERN_HOSTNAME: {
            char h[256] = "localhost";
            gethostname(h, sizeof(h));
            copy_str(h);
            return true;
        }
        default: break;
        }
    } else if (mib[0] == DARWIN_CTL_HW) {
        if (namelen < 2) return false;
        long ncpus = sysconf(_SC_NPROCESSORS_ONLN);
        if (ncpus <= 0) ncpus = 1;

        struct sysinfo si;
        uint64_t totalram = 8ull * 1024 * 1024 * 1024;
        if (sysinfo(&si) == 0) totalram = (uint64_t)si.totalram * si.mem_unit;

        switch (mib[1]) {
        case DARWIN_HW_MACHINE:   copy_str("arm64"); return true;
        case DARWIN_HW_MODEL:     copy_str("MacBookPro18,1"); return true;
        case DARWIN_HW_NCPU:      copy_u32((uint32_t)ncpus); return true;
        case DARWIN_HW_AVAILCPU:  copy_u32((uint32_t)ncpus); return true;
        case DARWIN_HW_BYTEORDER: copy_u32(1234); return true;
        case DARWIN_HW_PAGESIZE:  copy_u32((uint32_t)sysconf(_SC_PAGESIZE)); return true;
        case DARWIN_HW_PHYSMEM:   copy_u32((uint32_t)totalram); return true;
        case DARWIN_HW_USERMEM:   copy_u32((uint32_t)totalram); return true;
        case DARWIN_HW_MEMSIZE:   copy_u64(totalram); return true;
        default: break;
        }
    }
    return false;
}

bool darwin_sysctl_impl(const int* mib, int namelen, void* oldp, size_t* oldlenp, void* newp, size_t newlen) {
    return handle_darwin_sysctl(nullptr, mib, namelen, oldp, oldlenp, newp, newlen);
}

void do_darwin_syscall(CpuState* st) {
    uint64_t full_nr = st->x[16];
    if (full_nr == 0 && st->x[8] != 0) {
        // Fallback to x8 if x16 was not set
        full_nr = st->x[8];
    }

    uint64_t a0 = st->x[0], a1 = st->x[1], a2 = st->x[2], a3 = st->x[3], a4 = st->x[4], a5 = st->x[5];

    // Check for Mach Traps
    int mach_nr = 0;
    if ((int32_t)full_nr < 0) {
        mach_nr = (int32_t)full_nr;
    } else if ((full_nr & SYSCALL_CLASS_MASK) == SYSCALL_CLASS_MACH) {
        mach_nr = -(int)(full_nr & SYSCALL_NUMBER_MASK);
    }

    if (mach_nr < 0) {
        switch (mach_nr) {
        case DARWIN_MACH_reply_port: {
            static std::atomic<uint32_t> g_port_seq{0x1000};
            set_darwin_success(st, g_port_seq.fetch_add(1));
            return;
        }
        case DARWIN_MACH_thread_self:
            set_darwin_success(st, darwin_thread_port((int)syscall(SYS_gettid)));
            return;
        case DARWIN_MACH_task_self:
            set_darwin_success(st, 0x103);   // = mach_task_self_ (darwin_sys_shims.cpp)
            return;
        case DARWIN_MACH_host_self:
            set_darwin_success(st, 0x100);
            return;
        case DARWIN_MACH_timebase_info: {
            mach_timebase_info_data_t* tb = (mach_timebase_info_data_t*)a0;
            if (tb) {
                tb->numer = 1;
                tb->denom = 1;
            }
            set_darwin_success(st, 0);
            return;
        }
        case DARWIN_MACH_thread_switch:
            sched_yield();
            set_darwin_success(st, 0);
            return;
        case DARWIN_MACH_msg:
            // Pretend Mach IPC message completed successfully
            set_darwin_success(st, 0);
            return;
        case DARWIN_MACH_semaphore_signal:
        case DARWIN_MACH_semaphore_wait:
        case DARWIN_MACH_semaphore_wait_signal:
        case DARWIN_MACH_semaphore_timedwait:
            set_darwin_success(st, 0);
            return;
        default:
            XEF_LOG(2, "xef-osx: Unhandled Mach trap %d", mach_nr);
            set_darwin_success(st, 0);
            return;
        }
    }

    // Machine-dependent trap class (0x03000000)
    if ((full_nr & SYSCALL_CLASS_MASK) == SYSCALL_CLASS_MDEP) {
        uint32_t mdep_nr = full_nr & SYSCALL_NUMBER_MASK;
        if (mdep_nr == 3) { // thread_fast_set_cthread_self
            st->tpidrro_el0 = a0;
            st->tpidr_el0 = a0;
            set_darwin_success(st, 0);
            return;
        }
        set_darwin_success(st, 0);
        return;
    }

    // BSD Syscalls
    int nr = (int)(full_nr & SYSCALL_NUMBER_MASK);
    XEF_LOG(2, "darwin_syscall: nr=%d (a0=%#lx, a1=%#lx, a2=%#lx, a3=%#lx)",
            nr, (unsigned long)a0, (unsigned long)a1, (unsigned long)a2, (unsigned long)a3);

    switch (nr) {
    case 184:    // sigreturn(ucontext*, infostyle)
        sig_darwin_sigreturn(st, a0);
        return;
    case DARWIN_SYS_exit:
        _exit((int)a0);
        break;

    case DARWIN_SYS_read:
    case DARWIN_SYS_read_nocancel: {
        ssize_t r = read((int)a0, (void*)a1, (size_t)a2);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, (u64)r);
        break;
    }

    case DARWIN_SYS_write:
    case DARWIN_SYS_write_nocancel: {
        ssize_t r = write((int)a0, (const void*)a1, (size_t)a2);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, (u64)r);
        break;
    }

    case DARWIN_SYS_open:
    case DARWIN_SYS_open_nocancel: {
        const char* p = (const char*)a0;
        std::string rp = resolve_guest_path(p);
        int lflags = open_flags_darwin_to_linux(a1);
        int fd = open(rp.c_str(), lflags, (mode_t)a2);
        if (fd < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, (u64)fd);
        break;
    }

    case DARWIN_SYS_openat: {
        const char* p = (const char*)a1;
        std::string rp = resolve_guest_path(p);
        int lflags = open_flags_darwin_to_linux(a2);
        int fd = openat((int)a0, rp.c_str(), lflags, (mode_t)a3);
        if (fd < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, (u64)fd);
        break;
    }

    case DARWIN_SYS_close:
    case DARWIN_SYS_close_nocancel: {
        int r = close((int)a0);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_stat:
    case DARWIN_SYS_stat64: {
        const char* p = (const char*)a0;
        std::string rp = resolve_guest_path(p);
        struct stat hst;
        if (stat(rp.c_str(), &hst) < 0) {
            set_darwin_error(st, errno);
        } else {
            convert_stat_to_darwin(hst, (darwin_stat64*)a1);
            set_darwin_success(st, 0);
        }
        break;
    }

    case DARWIN_SYS_fstat:
    case DARWIN_SYS_fstat64: {
        struct stat hst;
        if (fstat((int)a0, &hst) < 0) {
            set_darwin_error(st, errno);
        } else {
            convert_stat_to_darwin(hst, (darwin_stat64*)a1);
            set_darwin_success(st, 0);
        }
        break;
    }

    case DARWIN_SYS_lstat:
    case DARWIN_SYS_lstat64: {
        const char* p = (const char*)a0;
        std::string rp = resolve_guest_path(p, false);
        struct stat hst;
        if (lstat(rp.c_str(), &hst) < 0) {
            set_darwin_error(st, errno);
        } else {
            convert_stat_to_darwin(hst, (darwin_stat64*)a1);
            set_darwin_success(st, 0);
        }
        break;
    }

    case DARWIN_SYS_fstatat64: {
        const char* p = (const char*)a1;
        std::string rp = resolve_guest_path(p);
        struct stat hst;
        if (fstatat((int)a0, rp.c_str(), &hst, (int)a3) < 0) {
            set_darwin_error(st, errno);
        } else {
            convert_stat_to_darwin(hst, (darwin_stat64*)a2);
            set_darwin_success(st, 0);
        }
        break;
    }

    case DARWIN_SYS_mmap: {
        int dflags = (int)a3;
        int lflags = 0;
        if (dflags & DARWIN_MAP_SHARED)    lflags |= MAP_SHARED;
        if (dflags & DARWIN_MAP_PRIVATE)   lflags |= MAP_PRIVATE;
        if (dflags & DARWIN_MAP_FIXED)     lflags |= MAP_FIXED;
        if (dflags & DARWIN_MAP_ANONYMOUS) lflags |= MAP_ANONYMOUS;

        int prot = (int)a2;
        int fd = (int)a4;
        off_t off = (off_t)a5;
        if (lflags & MAP_ANONYMOUS) {
            fd = -1;
            off = 0;
        }

        void* r = mmap((void*)a0, (size_t)a1, prot, lflags, fd, off);
        if (r == MAP_FAILED) {
            set_darwin_error(st, errno);
        } else {
            set_darwin_success(st, (u64)r);
        }
        break;
    }

    case DARWIN_SYS_munmap: {
        int r = munmap((void*)a0, (size_t)a1);
        if (r == 0) code_invalidate_range(a0, a1);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_mprotect: {
        int r = mprotect((void*)a0, (size_t)a1, (int)a2);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_madvise: {
        int r = madvise((void*)a0, (size_t)a1, (int)a2);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_lseek: {
        off_t r = lseek((int)a0, (off_t)a1, (int)a2);
        if (r == (off_t)-1) set_darwin_error(st, errno);
        else set_darwin_success(st, (u64)r);
        break;
    }

    case DARWIN_SYS_getpid: {
        pid_t pid = getpid();
        set_darwin_success(st, (u64)pid);
        st->x[1] = (u64)getppid(); // Darwin getpid puts ppid into second return register
        break;
    }

    case DARWIN_SYS_getppid:
        set_darwin_success(st, (u64)getppid());
        break;

    case DARWIN_SYS_getuid:
        set_darwin_success(st, (u64)getuid());
        break;

    case DARWIN_SYS_geteuid:
        set_darwin_success(st, (u64)geteuid());
        break;

    case DARWIN_SYS_getgid:
        set_darwin_success(st, (u64)getgid());
        break;

    case DARWIN_SYS_getegid:
        set_darwin_success(st, (u64)getegid());
        break;

    case DARWIN_SYS_pipe: {
        int fds[2];
        if (pipe(fds) < 0) {
            set_darwin_error(st, errno);
        } else {
            st->x[0] = (u64)fds[0];
            st->x[1] = (u64)fds[1];
            st->eflags |= 1;
        }
        break;
    }

    case DARWIN_SYS_dup: {
        int fd = dup((int)a0);
        if (fd < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, (u64)fd);
        break;
    }

    case DARWIN_SYS_ioctl: {
        int r = ioctl((int)a0, a1, a2);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, (u64)r);
        break;
    }

    case DARWIN_SYS_fcntl:
    case DARWIN_SYS_fcntl_nocancel: {
        int r = fcntl((int)a0, (int)a1, a2);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, (u64)r);
        break;
    }

    case DARWIN_SYS_sysctl: {
        bool ok = handle_darwin_sysctl(st, (const int*)a0, (int)a1, (void*)a2, (size_t*)a3, (void*)a4, (size_t)a5);
        if (!ok) set_darwin_error(st, ENOENT);
        else set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_bsdthread_register: {
        // Registers Darwin thread functions and sets thread-specific pointer
        if (a0) st->tpidrro_el0 = a0;
        set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_bsdthread_terminate: {
        darwin_tsd_run_destructors();
        thread_set_retval(a0);
        thread_exit(st, (int)a0);
        break;
    }

    case DARWIN_SYS_ulock_wait: {
        // Darwin user locks: map to Linux futex
        uint32_t* uaddr = (uint32_t*)a1;
        uint32_t val = (uint32_t)a2;
        syscall(SYS_futex, uaddr, FUTEX_WAIT_PRIVATE, val, nullptr, nullptr, 0);
        set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_ulock_wake: {
        uint32_t* uaddr = (uint32_t*)a1;
        syscall(SYS_futex, uaddr, FUTEX_WAKE_PRIVATE, 1, nullptr, nullptr, 0);
        set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_getentropy: {
        long r = syscall(SYS_getrandom, a0, a1, 0);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_gettimeofday: {
        int r = gettimeofday((struct timeval*)a0, (struct timezone*)a1);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_clock_gettime: {
        struct timespec ts;
        int r = clock_gettime(CLOCK_REALTIME, &ts);
        if (r < 0) {
            set_darwin_error(st, errno);
        } else {
            if (a1) *(struct timespec*)a1 = ts;
            set_darwin_success(st, 0);
        }
        break;
    }

    case DARWIN_SYS_nanosleep: {
        int r = nanosleep((const struct timespec*)a0, (struct timespec*)a1);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_chdir: {
        std::string p = resolve_guest_path((const char*)a0);
        int r = chdir(p.c_str());
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_fchdir: {
        int r = fchdir((int)a0);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_mkdir: {
        std::string p = resolve_guest_path((const char*)a0);
        int r = mkdir(p.c_str(), (mode_t)a1);
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_rmdir: {
        std::string p = resolve_guest_path((const char*)a0);
        int r = rmdir(p.c_str());
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, 0);
        break;
    }

    case DARWIN_SYS_unlink: {
        std::string p = resolve_guest_path((const char*)a0, false);
        int r = unlink(p.c_str());
        if (r < 0) set_darwin_error(st, errno);
        else set_darwin_success(st, 0);
        break;
    }

    default:
        XEF_LOG(2, "xef-osx: Unhandled Darwin syscall %d (x16=%#lx, a0=%#lx, a1=%#lx)",
                nr, (unsigned long)full_nr, (unsigned long)a0, (unsigned long)a1);
        set_darwin_error(st, ENOSYS);
        break;
    }
}

} // namespace xef
