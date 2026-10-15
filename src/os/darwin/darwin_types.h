// XEF-OSX — Darwin / macOS system types and constants.
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace xef {

// Darwin BSD Syscall Class (top 8 bits)
constexpr uint64_t SYSCALL_CLASS_NONE   = 0x00000000;
constexpr uint64_t SYSCALL_CLASS_MACH   = 0x01000000;
constexpr uint64_t SYSCALL_CLASS_UNIX   = 0x02000000; // BSD
constexpr uint64_t SYSCALL_CLASS_MDEP   = 0x03000000;
constexpr uint64_t SYSCALL_CLASS_MASK   = 0xff000000;
constexpr uint64_t SYSCALL_NUMBER_MASK  = 0x00ffffff;

// Darwin BSD Syscall Numbers
enum DarwinSyscall : int {
    DARWIN_SYS_syscall          = 0,
    DARWIN_SYS_exit             = 1,
    DARWIN_SYS_fork             = 2,
    DARWIN_SYS_read             = 3,
    DARWIN_SYS_write            = 4,
    DARWIN_SYS_open             = 5,
    DARWIN_SYS_close            = 6,
    DARWIN_SYS_wait4            = 7,
    DARWIN_SYS_link             = 9,
    DARWIN_SYS_unlink           = 10,
    DARWIN_SYS_chdir            = 12,
    DARWIN_SYS_fchdir           = 13,
    DARWIN_SYS_mknod            = 14,
    DARWIN_SYS_chmod            = 15,
    DARWIN_SYS_chown            = 16,
    DARWIN_SYS_getfsstat        = 18,
    DARWIN_SYS_getpid           = 20,
    DARWIN_SYS_setuid           = 23,
    DARWIN_SYS_getuid           = 24,
    DARWIN_SYS_geteuid          = 25,
    DARWIN_SYS_ptrace           = 26,
    DARWIN_SYS_recvmsg          = 27,
    DARWIN_SYS_sendmsg          = 28,
    DARWIN_SYS_recvfrom         = 29,
    DARWIN_SYS_accept           = 30,
    DARWIN_SYS_getpeername      = 31,
    DARWIN_SYS_getsockname      = 32,
    DARWIN_SYS_access           = 33,
    DARWIN_SYS_kill             = 37,
    DARWIN_SYS_getppid          = 39,
    DARWIN_SYS_dup              = 41,
    DARWIN_SYS_pipe             = 42,
    DARWIN_SYS_getegid          = 43,
    DARWIN_SYS_sigaction        = 46,
    DARWIN_SYS_getgid           = 47,
    DARWIN_SYS_sigprocmask      = 48,
    DARWIN_SYS_ioctl            = 54,
    DARWIN_SYS_symlink          = 57,
    DARWIN_SYS_readlink         = 58,
    DARWIN_SYS_execve           = 59,
    DARWIN_SYS_umask            = 60,
    DARWIN_SYS_munmap           = 73,
    DARWIN_SYS_mprotect         = 74,
    DARWIN_SYS_madvise          = 75,
    DARWIN_SYS_fcntl            = 92,
    DARWIN_SYS_select           = 93,
    DARWIN_SYS_fsync            = 95,
    DARWIN_SYS_socket           = 97,
    DARWIN_SYS_connect          = 98,
    DARWIN_SYS_bind             = 104,
    DARWIN_SYS_setsockopt       = 105,
    DARWIN_SYS_listen           = 106,
    DARWIN_SYS_gettimeofday     = 116,
    DARWIN_SYS_readv            = 120,
    DARWIN_SYS_writev           = 121,
    DARWIN_SYS_fchmod           = 124,
    DARWIN_SYS_rename           = 128,
    DARWIN_SYS_flock            = 131,
    DARWIN_SYS_sendto           = 133,
    DARWIN_SYS_shutdown         = 134,
    DARWIN_SYS_socketpair       = 135,
    DARWIN_SYS_mkdir            = 136,
    DARWIN_SYS_rmdir            = 137,
    DARWIN_SYS_utimes           = 138,
    DARWIN_SYS_futimes          = 139,
    DARWIN_SYS_getrusage        = 157,
    DARWIN_SYS_getsockopt       = 159,
    DARWIN_SYS_stat             = 188,
    DARWIN_SYS_fstat            = 189,
    DARWIN_SYS_lstat            = 190,
    DARWIN_SYS_mmap             = 197,
    DARWIN_SYS_lseek            = 199,
    DARWIN_SYS_sysctl           = 202,
    DARWIN_SYS_getattrlist      = 220,
    DARWIN_SYS_nanosleep        = 240,
    DARWIN_SYS_clock_gettime    = 286,
    DARWIN_SYS_stat64           = 338,
    DARWIN_SYS_fstat64          = 339,
    DARWIN_SYS_lstat64          = 340,
    DARWIN_SYS_bsdthread_create = 360,
    DARWIN_SYS_bsdthread_terminate = 361,
    DARWIN_SYS_bsdthread_register  = 397,
    DARWIN_SYS_open_nocancel    = 398,
    DARWIN_SYS_close_nocancel   = 399,
    DARWIN_SYS_read_nocancel    = 400,
    DARWIN_SYS_write_nocancel   = 401,
    DARWIN_SYS_fcntl_nocancel   = 406,
    DARWIN_SYS_ulock_wait       = 446,
    DARWIN_SYS_ulock_wake       = 447,
    DARWIN_SYS_openat           = 463,
    DARWIN_SYS_fstatat64        = 469,
    DARWIN_SYS_readlinkat       = 473,
    DARWIN_SYS_getentropy       = 515,
};

// Mach Traps (negative numbers on ARM64)
enum MachTrap : int {
    DARWIN_MACH_reply_port              = -26,
    DARWIN_MACH_thread_self             = -27,
    DARWIN_MACH_task_self               = -28,
    DARWIN_MACH_host_self               = -29,
    DARWIN_MACH_msg                     = -31,
    DARWIN_MACH_semaphore_signal        = -33,
    DARWIN_MACH_semaphore_wait          = -36,
    DARWIN_MACH_semaphore_wait_signal   = -37,
    DARWIN_MACH_semaphore_timedwait     = -38,
    DARWIN_MACH_thread_switch           = -61,
    DARWIN_MACH_timebase_info           = -89,
};

// Darwin Open Flags
constexpr int DARWIN_O_RDONLY   = 0x0000;
constexpr int DARWIN_O_WRONLY   = 0x0001;
constexpr int DARWIN_O_RDWR     = 0x0002;
constexpr int DARWIN_O_NONBLOCK = 0x0004;
constexpr int DARWIN_O_APPEND   = 0x0008;
constexpr int DARWIN_O_SHLOCK   = 0x0010;
constexpr int DARWIN_O_EXLOCK   = 0x0020;
constexpr int DARWIN_O_ASYNC    = 0x0040;
constexpr int DARWIN_O_FSYNC    = 0x0080;
constexpr int DARWIN_O_NOFOLLOW = 0x0100;
constexpr int DARWIN_O_CREAT    = 0x0200;
constexpr int DARWIN_O_TRUNC    = 0x0400;
constexpr int DARWIN_O_EXCL     = 0x0800;
constexpr int DARWIN_O_DIRECTORY= 0x00100000;
constexpr int DARWIN_O_CLOEXEC  = 0x01000000;

// Darwin Mmap Flags
constexpr int DARWIN_MAP_SHARED     = 0x0001;
constexpr int DARWIN_MAP_PRIVATE    = 0x0002;
constexpr int DARWIN_MAP_FIXED      = 0x0010;
constexpr int DARWIN_MAP_RENAME     = 0x0020;
constexpr int DARWIN_MAP_NORESERVE  = 0x0040;
constexpr int DARWIN_MAP_NOEXTEND   = 0x0100;
constexpr int DARWIN_MAP_HASSEMAPHORE = 0x0200;
constexpr int DARWIN_MAP_NOCACHE    = 0x0400;
constexpr int DARWIN_MAP_JIT        = 0x0800;
constexpr int DARWIN_MAP_ANONYMOUS  = 0x1000;

// Darwin Stat64 struct
struct darwin_stat64 {
    int32_t   st_dev;           // [0]
    uint16_t  st_mode;          // [4]
    uint16_t  st_nlink;         // [6]
    uint64_t  st_ino;           // [8]
    uint32_t  st_uid;           // [16]
    uint32_t  st_gid;           // [20]
    int32_t   st_rdev;          // [24]
    int32_t   _pad0;            // [28]
    int64_t   st_atime_sec;     // [32]
    int64_t   st_atime_nsec;    // [40]
    int64_t   st_mtime_sec;     // [48]
    int64_t   st_mtime_nsec;    // [56]
    int64_t   st_ctime_sec;     // [64]
    int64_t   st_ctime_nsec;    // [72]
    int64_t   st_birthtime_sec; // [80]
    int64_t   st_birthtime_nsec;// [88]
    int64_t   st_size;          // [96]
    int64_t   st_blocks;        // [104]
    int32_t   st_blksize;       // [112]
    uint32_t  st_flags;         // [116]
    uint32_t  st_gen;           // [120]
    int32_t   st_lspare;        // [124]
    int64_t   st_qspare[2];     // [128]
};

// Mach Timebase Info
struct mach_timebase_info_data_t {
    uint32_t numer;
    uint32_t denom;
};

// Sysctl Top-Level Names
constexpr int DARWIN_CTL_KERN   = 1;
constexpr int DARWIN_CTL_VM     = 2;
constexpr int DARWIN_CTL_VFS    = 3;
constexpr int DARWIN_CTL_NET    = 4;
constexpr int DARWIN_CTL_DEBUG  = 5;
constexpr int DARWIN_CTL_HW     = 6;
constexpr int DARWIN_CTL_MACHDEP= 7;

// Sysctl KERN Names
constexpr int DARWIN_KERN_OSTYPE       = 1;
constexpr int DARWIN_KERN_OSRELEASE    = 2;
constexpr int DARWIN_KERN_OSREV        = 3;
constexpr int DARWIN_KERN_VERSION      = 4;
constexpr int DARWIN_KERN_ARGMAX       = 8;
constexpr int DARWIN_KERN_HOSTNAME     = 10;
constexpr int DARWIN_KERN_PROC         = 14;
constexpr int DARWIN_KERN_BOOTTIME     = 21;
constexpr int DARWIN_KERN_OSVERSION    = 65;

// Sysctl HW Names
constexpr int DARWIN_HW_MACHINE        = 1;
constexpr int DARWIN_HW_MODEL          = 2;
constexpr int DARWIN_HW_NCPU           = 3;
constexpr int DARWIN_HW_BYTEORDER      = 4;
constexpr int DARWIN_HW_PHYSMEM        = 5;
constexpr int DARWIN_HW_USERMEM        = 6;
constexpr int DARWIN_HW_PAGESIZE       = 7;
constexpr int DARWIN_HW_MEMSIZE        = 24;
constexpr int DARWIN_HW_AVAILCPU       = 25;

} // namespace xef
