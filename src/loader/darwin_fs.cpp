// XEF-OSX — file-system calls that need more than passing the guest's arguments through:
//  * guest paths resolve through the rootfs overlay (resolve_guest_path), also relative to a directory fd that lies
//    inside the rootfs (rsync walks "/tmp/x" as open("/") + fstatat(fd, "tmp"): the rootfs has no /tmp, the host has);
//  * Darwin constants differ: AT_FDCWD -2, AT_* flags, UTIME_NOW/OMIT, RENAME_SWAP/EXCL, pathconf names, xattr
//    options (and Linux keeps unprivileged attributes in "user."), struct statfs (2168 bytes) / statvfs (64 bytes).
// Constants and layouts are from the macOS SDK (tests/darwin/mac/fs_at.c checks them against a Mac).
#include "loader/darwin_hle.h"
#include "loader/elf_loader.h"
#include "os/darwin/darwin_types.h"
#include "common/common.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/statvfs.h>
#include <sys/ioctl.h>
#include <sys/ipc.h>
#include <linux/fs.h>
#include <sys/sem.h>
#include <sys/shm.h>
#include <sys/time.h>
#include <sys/xattr.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <fstream>
#include <vector>
#include <sstream>
#include <string>

namespace xef {

int darwin_open_flags_to_linux(int df);
constexpr int kLinuxEnoattr = 1093;   // mapped to Darwin ENOATTR (93) by darwin_errno_from_linux

// ---- path resolution ------------------------------------------------------------------------------------------
// Returns the path to use with *dfd (AT_FDCWD after resolving to an absolute host path).
static std::string at_path(int* dfd, const char* path, bool follow) {
    if (*dfd == -2) *dfd = AT_FDCWD;
    if (!path) return {};
    if (path[0] == '/' || *dfd == AT_FDCWD) {
        std::string r = resolve_guest_path(path, follow);
        if (path[0] == '/') *dfd = AT_FDCWD;
        return r;
    }
    if (g_rootfs.empty()) return path;
    char dir[PATH_MAX];
    ssize_t n = readlink(("/proc/self/fd/" + std::to_string(*dfd)).c_str(), dir, sizeof dir - 1);
    if (n <= 0) return path;
    dir[n] = 0;
    std::string d(dir);
    if (d == g_rootfs || d.rfind(g_rootfs + "/", 0) == 0) {
        std::string guest = d.substr(g_rootfs.size());
        if (guest.empty()) guest = "/";
        guest += (guest.back() == '/' ? "" : "/") + std::string(path);
        *dfd = AT_FDCWD;
        return resolve_guest_path(guest.c_str(), follow);
    }
    return path;
}
static int at_flags(int d) {   // Darwin AT_EACCESS 0x10, SYMLINK_NOFOLLOW 0x20, SYMLINK_FOLLOW 0x40, REMOVEDIR 0x80
    int l = 0;
    if (d & 0x10) l |= AT_EACCESS;
    if (d & 0x20) l |= AT_SYMLINK_NOFOLLOW;
    if (d & 0x40) l |= AT_SYMLINK_FOLLOW;
    if (d & 0x80) l |= AT_REMOVEDIR;
    return l;
}
static void utime_ts(const struct timespec* in, struct timespec* out) {   // UTIME_NOW -1, UTIME_OMIT -2 on Darwin
    for (int i = 0; i < 2; i++) {
        out[i] = in[i];
        if (in[i].tv_nsec == -1) out[i].tv_nsec = UTIME_NOW;
        else if (in[i].tv_nsec == -2) out[i].tv_nsec = UTIME_OMIT;
    }
}

int darwin_openat_impl(int dfd, const char* path, int dflags, mode_t mode) {
    if (!path) { errno = EFAULT; return -1; }
    std::string p = at_path(&dfd, path, !(dflags & 0x100));   // O_NOFOLLOW
    return openat(dfd, p.c_str(), darwin_open_flags_to_linux(dflags), mode);
}
std::string darwin_fstatat_path(int* dfd, const char* path, int dflag, int* lflags) {
    *lflags = (dflag & 0x20) ? AT_SYMLINK_NOFOLLOW : 0;
    return at_path(dfd, path, !(dflag & 0x20));
}

static int f_mkdirat(int dfd, const char* p, mode_t m) { std::string s = at_path(&dfd, p, false); return mkdirat(dfd, s.c_str(), m); }
static int f_mkfifoat(int dfd, const char* p, mode_t m) { std::string s = at_path(&dfd, p, false); return mkfifoat(dfd, s.c_str(), m); }
static int f_mknodat(int dfd, const char* p, mode_t m, uint32_t dev) {
    std::string s = at_path(&dfd, p, false);
    return mknodat(dfd, s.c_str(), m, linux_dev_from_darwin(dev));
}
static int f_unlinkat(int dfd, const char* p, int fl) {
    std::string s = at_path(&dfd, p, false);
    int r = unlinkat(dfd, s.c_str(), at_flags(fl) & AT_REMOVEDIR);
    if (r < 0 && errno == EISDIR) errno = EPERM;   // unlinking a directory: EPERM on Darwin
    return r;
}
static int f_renameat(int fd1, const char* a, int fd2, const char* b) {
    std::string x = at_path(&fd1, a, false), y = at_path(&fd2, b, false);
    return renameat(fd1, x.c_str(), fd2, y.c_str());
}
// renameatx_np / renamex_np: RENAME_SWAP 2 -> RENAME_EXCHANGE, RENAME_EXCL 4 -> RENAME_NOREPLACE
static int f_renameatx_np(int fd1, const char* a, int fd2, const char* b, unsigned fl) {
    std::string x = at_path(&fd1, a, false), y = at_path(&fd2, b, false);
    unsigned lf = ((fl & 2) ? 2u /*RENAME_EXCHANGE*/ : 0) | ((fl & 4) ? 1u /*RENAME_NOREPLACE*/ : 0);
    if (fl & ~6u & ~0x10u) { errno = EINVAL; return -1; }
    return (int)syscall(SYS_renameat2, fd1, x.c_str(), fd2, y.c_str(), lf);
}
static int f_renamex_np(const char* a, const char* b, unsigned fl) { return f_renameatx_np(-2, a, -2, b, fl); }
// pipe2 / dup3 (macOS 15+): Darwin O_NONBLOCK 0x4, O_CLOEXEC 0x1000000; anything else is EINVAL
static int f_pipe2(int fds[2], int fl) {
    if (fl & ~(0x4 | 0x1000000)) { errno = EINVAL; return -1; }
    return pipe2(fds, ((fl & 0x4) ? O_NONBLOCK : 0) | ((fl & 0x1000000) ? O_CLOEXEC : 0));
}
static int f_dup3(int a, int b, int fl) {
    if (fl & ~0x1000000) { errno = EINVAL; return -1; }
    return dup3(a, b, (fl & 0x1000000) ? O_CLOEXEC : 0);
}
// clonefile family: dst gets the data and the attributes of src (mode, times; the owner too when running as root unless
// CLONE_NOOWNERCOPY 2). FICLONE shares the blocks where the filesystem can, otherwise the data is copied. Directories
// (recursive clones, APFS only) give ENOTSUP, as on volumes without clone support. CLONE_NOFOLLOW 1: a link is cloned.
static int clone_fd(int sfd, int ddir, const char* dst, uint32_t flags) {
    struct stat st;
    if (fstat(sfd, &st) < 0) return -1;
    if (S_ISDIR(st.st_mode)) { errno = ENOTSUP; return -1; }
    if (!S_ISREG(st.st_mode)) { errno = EINVAL; return -1; }
    std::string d = at_path(&ddir, dst, false);
    int dfd = openat(ddir, d.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, st.st_mode & 07777);
    if (dfd < 0) return -1;
    int ok = ioctl(dfd, FICLONE, sfd) == 0;
    for (off_t off = 0; !ok;) {
        ssize_t n = copy_file_range(sfd, &off, dfd, nullptr, 1 << 30, 0);
        if (n == 0) { ok = 1; break; }
        if (n > 0) continue;
        if (errno != EXDEV && errno != EINVAL && errno != ENOSYS && errno != EOPNOTSUPP) break;
        char buf[65536];   // no copy_file_range between these filesystems
        while ((n = pread(sfd, buf, sizeof buf, off)) > 0) {
            for (ssize_t w = 0; w < n;) { ssize_t k = write(dfd, buf + w, n - w); if (k < 0) { n = -1; break; } w += k; }
            if (n < 0) break;
            off += n;
        }
        ok = n == 0;
        break;
    }
    if (ok) {
        fchmod(dfd, st.st_mode & 07777);   // not reduced by the umask
        if (geteuid() == 0 && !(flags & 2)) { if (fchown(dfd, st.st_uid, st.st_gid) < 0) {} }
        struct timespec ts[2] = {st.st_atim, st.st_mtim};
        futimens(dfd, ts);
        close(dfd);
        return 0;
    }
    int e = errno;
    close(dfd);
    unlinkat(ddir, d.c_str(), 0);
    errno = e;
    return -1;
}
static int f_fclonefileat(int sfd, int ddir, const char* dst, uint32_t flags) {
    if (!dst) { errno = EFAULT; return -1; }
    if (flags & ~7u) { errno = EINVAL; return -1; }
    return clone_fd(sfd, ddir, dst, flags);
}
static int f_clonefileat(int sdir, const char* src, int ddir, const char* dst, uint32_t flags) {
    if (!src || !dst) { errno = EFAULT; return -1; }
    if (flags & ~7u) { errno = EINVAL; return -1; }
    std::string s = at_path(&sdir, src, !(flags & 1));
    struct stat st;
    if ((flags & 1) && fstatat(sdir, s.c_str(), &st, AT_SYMLINK_NOFOLLOW) == 0 && S_ISLNK(st.st_mode)) {
        char t[PATH_MAX];
        ssize_t n = readlinkat(sdir, s.c_str(), t, sizeof t - 1);
        if (n < 0) return -1;
        t[n] = 0;
        std::string d = at_path(&ddir, dst, false);
        return symlinkat(t, ddir, d.c_str());
    }
    int sfd = openat(sdir, s.c_str(), O_RDONLY | O_CLOEXEC | ((flags & 1) ? O_NOFOLLOW : 0));
    if (sfd < 0) { if (errno == EISDIR) errno = ENOTSUP; return -1; }
    int r = clone_fd(sfd, ddir, dst, flags);
    int e = errno;
    close(sfd);
    errno = e;
    return r;
}
static int f_clonefile(const char* src, const char* dst, uint32_t flags) { return f_clonefileat(-2, src, -2, dst, flags); }
static ssize_t f_readlinkat(int dfd, const char* p, char* buf, size_t n) { std::string s = at_path(&dfd, p, false); return readlinkat(dfd, s.c_str(), buf, n); }
static int f_faccessat(int dfd, const char* p, int mode, int fl) {
    std::string s = at_path(&dfd, p, !(fl & 0x20));
    return faccessat(dfd, s.c_str(), mode, at_flags(fl) & (AT_EACCESS | AT_SYMLINK_NOFOLLOW));
}
static int f_fchmodat(int dfd, const char* p, mode_t m, int fl) {
    std::string s = at_path(&dfd, p, !(fl & 0x20));
    return fchmodat(dfd, s.c_str(), m, at_flags(fl) & AT_SYMLINK_NOFOLLOW);
}
static int f_fchownat(int dfd, const char* p, uid_t u, gid_t g, int fl) {
    std::string s = at_path(&dfd, p, !(fl & 0x20));
    return fchownat(dfd, s.c_str(), u, g, at_flags(fl) & AT_SYMLINK_NOFOLLOW);
}
static int f_linkat(int fd1, const char* a, int fd2, const char* b, int fl) {
    std::string x = at_path(&fd1, a, (fl & 0x40) != 0), y = at_path(&fd2, b, false);
    return linkat(fd1, x.c_str(), fd2, y.c_str(), at_flags(fl) & AT_SYMLINK_FOLLOW);
}
static int f_symlinkat(const char* target, int dfd, const char* p) {   // the link text is stored as given
    std::string s = at_path(&dfd, p, false);
    return symlinkat(target, dfd, s.c_str());
}
static int f_utimensat(int dfd, const char* p, const struct timespec* t, int fl) {
    std::string s = at_path(&dfd, p, !(fl & 0x20));
    struct timespec lt[2];
    if (t) utime_ts(t, lt);
    return utimensat(dfd, s.c_str(), t ? lt : nullptr, at_flags(fl) & AT_SYMLINK_NOFOLLOW);
}
static int f_futimens(int fd, const struct timespec* t) {
    struct timespec lt[2];
    if (t) utime_ts(t, lt);
    return futimens(fd, t ? lt : nullptr);
}

// ---- plain path calls ----------------------------------------------------------------------------------------
static std::string rp(const char* p, bool follow = true) { return resolve_guest_path(p, follow); }
static int f_chdir(const char* p) { if (!p) { errno = EFAULT; return -1; } return chdir(rp(p).c_str()); }
static int f_chroot(const char* p) { if (!p) { errno = EFAULT; return -1; } return chroot(rp(p).c_str()); }
static int f_link(const char* a, const char* b) { return link(rp(a).c_str(), rp(b, false).c_str()); }
static int f_symlink(const char* target, const char* p) { return symlink(target, rp(p, false).c_str()); }
static int f_truncate(const char* p, off_t len) { return truncate(rp(p).c_str(), len); }
static int f_mkfifo(const char* p, mode_t m) { return mkfifo(rp(p, false).c_str(), m); }
static int f_mknod(const char* p, mode_t m, uint32_t dev) { return mknod(rp(p, false).c_str(), m, linux_dev_from_darwin(dev)); }
static int f_lchown(const char* p, uid_t u, gid_t g) { return lchown(rp(p, false).c_str(), u, g); }
static int f_lchmod(const char* p, mode_t m) {   // Linux cannot chmod a symlink itself
    std::string s = rp(p, false);
    struct stat st;
    if (lstat(s.c_str(), &st) < 0) return -1;
    if (S_ISLNK(st.st_mode)) { errno = EOPNOTSUPP; return -1; }
    return chmod(s.c_str(), m);
}
static int f_creat(const char* p, mode_t m) { return open(rp(p).c_str(), O_CREAT | O_WRONLY | O_TRUNC, m); }
// Darwin struct timeval is {int64 tv_sec; int32 tv_usec; 4 bytes padding}: the padding is not part of tv_usec
static const struct timeval* tv_in(const void* d, struct timeval* l, int n) {
    if (!d) return nullptr;
    for (int i = 0; i < n; i++) {
        memcpy(&l[i].tv_sec, (const char*)d + 16 * i, 8);
        int32_t us; memcpy(&us, (const char*)d + 16 * i + 8, 4);
        l[i].tv_usec = us;
    }
    return l;
}
static void tv_out(const struct timeval* l, void* d, int n) {
    if (!d) return;
    for (int i = 0; i < n; i++) {
        memcpy((char*)d + 16 * i, &l[i].tv_sec, 8);
        int32_t us = (int32_t)l[i].tv_usec; memcpy((char*)d + 16 * i + 8, &us, 4);
        memset((char*)d + 16 * i + 12, 0, 4);
    }
}
static int f_utimes(const char* p, const void* tv) { struct timeval l[2]; return utimes(rp(p).c_str(), tv_in(tv, l, 2)); }
static int f_lutimes(const char* p, const void* tv) { struct timeval l[2]; return lutimes(rp(p, false).c_str(), tv_in(tv, l, 2)); }
static int f_futimes(int fd, const void* tv) { struct timeval l[2]; return futimes(fd, tv_in(tv, l, 2)); }
static int f_setitimer(int which, const void* nv, void* ov) {   // itimerval = {interval, value}
    struct itimerval n, o;
    if (nv) tv_in(nv, &n.it_interval, 2);
    int r = setitimer((__itimer_which_t)which, nv ? &n : nullptr, ov ? &o : nullptr);
    if (r == 0 && ov) tv_out(&o.it_interval, ov, 2);
    return r;
}
static int f_getitimer(int which, void* cv) {
    struct itimerval c;
    int r = getitimer((__itimer_which_t)which, &c);
    if (r == 0) tv_out(&c.it_interval, cv, 2);
    return r;
}
static int f_settimeofday(const void* tv, const void* tz) { struct timeval l; return settimeofday(tv_in(tv, &l, 1), (const struct timezone*)tz); }
static int f_adjtime(const void* d, void* od) {
    struct timeval l, o;
    int r = adjtime(tv_in(d, &l, 1), od ? &o : nullptr);
    if (r == 0 && od) tv_out(&o, od, 1);
    return r;
}
struct DarwinUtimbuf { int64_t actime, modtime; };
static int f_utime(const char* p, const DarwinUtimbuf* b) {
    if (!b) return utimes(rp(p).c_str(), nullptr);
    struct timeval tv[2] = {{b->actime, 0}, {b->modtime, 0}};
    return utimes(rp(p).c_str(), tv);
}

// pathconf: Darwin _PC_* 1..9 are Linux 0..8; the rest are renumbered
static int pc_name(int d) {
    if (d >= 1 && d <= 9) return d - 1;
    switch (d) {
        case 15: return _PC_2_SYMLINKS; case 16: return _PC_ALLOC_SIZE_MIN; case 17: return _PC_ASYNC_IO;
        case 18: return _PC_FILESIZEBITS; case 19: return _PC_PRIO_IO; case 20: return _PC_REC_INCR_XFER_SIZE;
        case 21: return _PC_REC_MAX_XFER_SIZE; case 22: return _PC_REC_MIN_XFER_SIZE; case 23: return _PC_REC_XFER_ALIGN;
        case 24: return _PC_SYMLINK_MAX; case 25: return _PC_SYNC_IO;
    }
    return -1;
}
static long pc_special(int d, bool* done) {   // Darwin-only names
    *done = true;
    switch (d) {
        case 10: return 255;       // _PC_NAME_CHARS_MAX
        case 11: return 1;         // _PC_CASE_SENSITIVE (Linux file systems are)
        case 12: return 1;         // _PC_CASE_PRESERVING
        case 26: return 64;        // _PC_XATTR_SIZE_BITS
    }
    *done = false;
    return 0;
}
static long f_pathconf(const char* p, int name) {
    bool done; long v = pc_special(name, &done);
    if (done) return v;
    int l = pc_name(name);
    if (l < 0) { errno = EINVAL; return -1; }
    return pathconf(rp(p).c_str(), l);
}
static long f_fpathconf(int fd, int name) {
    bool done; long v = pc_special(name, &done);
    if (done) return v;
    int l = pc_name(name);
    if (l < 0) { errno = EINVAL; return -1; }
    return fpathconf(fd, l);
}

// mkstemp family: the template is a guest path; the generated name is written back into it
static int mktemp_common(char* tmpl, int suffix, int (*make)(char*, int, int), int arg) {
    if (!tmpl) { errno = EINVAL; return -1; }
    std::string t(tmpl);
    size_t sl = t.rfind('/');
    std::string base = sl == std::string::npos ? t : t.substr(sl + 1);
    std::string host = sl == std::string::npos ? t : rp(sl == 0 ? "/" : t.substr(0, sl).c_str());
    if (sl != std::string::npos) host += (host.size() && host.back() == '/' ? "" : "/") + base;
    std::vector<char> buf(host.begin(), host.end());
    buf.push_back(0);
    int r = make(buf.data(), suffix, arg);
    memcpy(tmpl + t.size() - base.size(), buf.data() + host.size() - base.size(), base.size());   // the X's, filled in
    return r;
}
static int mk_stemps(char* b, int suffix, int flags) { return flags ? mkostemps(b, suffix, flags) : mkstemps(b, suffix); }
static int mk_dtemp(char* b, int, int) { return mkdtemp(b) ? 0 : -1; }
static int f_mkstemp(char* t) { return mktemp_common(t, 0, mk_stemps, 0); }
static int f_mkstemps(char* t, int s) { return mktemp_common(t, s, mk_stemps, 0); }
static int f_mkostemp(char* t, int fl) { return mktemp_common(t, 0, mk_stemps, darwin_open_flags_to_linux(fl) & ~O_ACCMODE); }
static int f_mkostemps(char* t, int s, int fl) { return mktemp_common(t, s, mk_stemps, darwin_open_flags_to_linux(fl) & ~O_ACCMODE); }
static char* f_mkdtemp(char* t) { return mktemp_common(t, 0, mk_dtemp, 0) == 0 ? t : nullptr; }

// ---- extended attributes: Darwin (path, name, value, size, position, options); Linux user.* namespace -----------
static std::string xname(const char* n) { return std::string("user.") + (n ? n : ""); }
static void xerr() { if (errno == ENODATA) errno = kLinuxEnoattr; }
static ssize_t f_getxattr(const char* p, const char* n, void* v, size_t sz, uint32_t pos, int opt) {
    if (pos) { errno = EINVAL; return -1; }   // resource forks only
    std::string s = rp(p, !(opt & 1));
    ssize_t r = (opt & 1) ? lgetxattr(s.c_str(), xname(n).c_str(), v, sz) : getxattr(s.c_str(), xname(n).c_str(), v, sz);
    if (r < 0) xerr();
    return r;
}
static ssize_t f_fgetxattr(int fd, const char* n, void* v, size_t sz, uint32_t pos, int) {
    if (pos) { errno = EINVAL; return -1; }
    ssize_t r = fgetxattr(fd, xname(n).c_str(), v, sz);
    if (r < 0) xerr();
    return r;
}
static int xflags(int opt) { return ((opt & 2) ? XATTR_CREATE : 0) | ((opt & 4) ? XATTR_REPLACE : 0); }
static int f_setxattr(const char* p, const char* n, const void* v, size_t sz, uint32_t pos, int opt) {
    if (pos) { errno = EINVAL; return -1; }
    std::string s = rp(p, !(opt & 1));
    int r = (opt & 1) ? lsetxattr(s.c_str(), xname(n).c_str(), v, sz, xflags(opt)) : setxattr(s.c_str(), xname(n).c_str(), v, sz, xflags(opt));
    if (r < 0) xerr();
    return r;
}
static int f_fsetxattr(int fd, const char* n, const void* v, size_t sz, uint32_t pos, int opt) {
    if (pos) { errno = EINVAL; return -1; }
    int r = fsetxattr(fd, xname(n).c_str(), v, sz, xflags(opt));
    if (r < 0) xerr();
    return r;
}
static int f_removexattr(const char* p, const char* n, int opt) {
    std::string s = rp(p, !(opt & 1));
    int r = (opt & 1) ? lremovexattr(s.c_str(), xname(n).c_str()) : removexattr(s.c_str(), xname(n).c_str());
    if (r < 0) xerr();
    return r;
}
static int f_fremovexattr(int fd, const char* n, int) { int r = fremovexattr(fd, xname(n).c_str()); if (r < 0) xerr(); return r; }
static ssize_t list_user(const std::vector<char>& raw, ssize_t n, char* buf, size_t sz) {
    std::string out;
    for (ssize_t i = 0; i < n;) {
        const char* e = raw.data() + i;
        size_t l = strlen(e);
        if (!strncmp(e, "user.", 5)) { out.append(e + 5, l - 5); out.push_back(0); }
        i += (ssize_t)l + 1;
    }
    if (!buf || sz == 0) return (ssize_t)out.size();
    if (out.size() > sz) { errno = ERANGE; return -1; }
    memcpy(buf, out.data(), out.size());
    return (ssize_t)out.size();
}
static ssize_t f_listxattr(const char* p, char* buf, size_t sz, int opt) {
    std::string s = rp(p, !(opt & 1));
    ssize_t n = (opt & 1) ? llistxattr(s.c_str(), nullptr, 0) : listxattr(s.c_str(), nullptr, 0);
    if (n <= 0) return n;
    std::vector<char> raw((size_t)n + 256);
    n = (opt & 1) ? llistxattr(s.c_str(), raw.data(), raw.size()) : listxattr(s.c_str(), raw.data(), raw.size());
    if (n < 0) return n;
    return list_user(raw, n, buf, sz);
}
static ssize_t f_flistxattr(int fd, char* buf, size_t sz, int) {
    ssize_t n = flistxattr(fd, nullptr, 0);
    if (n <= 0) return n;
    std::vector<char> raw((size_t)n + 256);
    n = flistxattr(fd, raw.data(), raw.size());
    if (n < 0) return n;
    return list_user(raw, n, buf, sz);
}

// ---- statfs / statvfs ---------------------------------------------------------------------------------------
struct DarwinStatfs {
    uint32_t f_bsize; int32_t f_iosize;
    uint64_t f_blocks, f_bfree, f_bavail, f_files, f_ffree;
    int32_t f_fsid[2];
    uint32_t f_owner, f_type, f_flags, f_fssubtype;
    char f_fstypename[16], f_mntonname[1024], f_mntfromname[1024];
    uint32_t f_flags_ext, f_reserved[7];
};
static_assert(sizeof(DarwinStatfs) == 2168 && offsetof(DarwinStatfs, f_mntfromname) == 1112, "Darwin struct statfs");
struct DarwinStatvfs {
    unsigned long f_bsize, f_frsize;
    uint32_t f_blocks, f_bfree, f_bavail, f_files, f_ffree, f_favail;
    unsigned long f_fsid, f_flag, f_namemax;
};
static_assert(sizeof(DarwinStatvfs) == 64 && offsetof(DarwinStatvfs, f_fsid) == 40, "Darwin struct statvfs");

// mount point / source / type of a host path: longest matching mount in /proc/self/mountinfo
static void mount_of(const std::string& host, std::string& on, std::string& from, std::string& type) {
    std::ifstream f("/proc/self/mountinfo");
    std::string line;
    size_t best = 0;
    on = "/"; from = "none"; type = "unknown";
    while (std::getline(f, line)) {
        std::istringstream ss(line);
        std::string id, parent, dev, root, mp, opts, tok;
        ss >> id >> parent >> dev >> root >> mp >> opts;
        while (ss >> tok && tok != "-") {}
        std::string t, src;
        ss >> t >> src;
        if ((host == mp || host.rfind(mp == "/" ? "/" : mp + "/", 0) == 0) && mp.size() >= best) {
            best = mp.size(); on = mp; from = src; type = t;
        }
    }
}
static int fill_statfs(const struct statfs& l, const std::string& host_path, DarwinStatfs* d) {
    memset(d, 0, sizeof *d);
    d->f_bsize = (uint32_t)l.f_bsize; d->f_iosize = (int32_t)l.f_bsize;
    d->f_blocks = l.f_blocks; d->f_bfree = l.f_bfree; d->f_bavail = l.f_bavail; d->f_files = l.f_files; d->f_ffree = l.f_ffree;
    memcpy(d->f_fsid, &l.f_fsid, 8);
    d->f_owner = 0;
    struct statvfs v;
    uint32_t fl = 0x1000;   // MNT_LOCAL
    if (statvfs(host_path.c_str(), &v) == 0) {
        if (v.f_flag & ST_RDONLY) fl |= 0x1;
        if (v.f_flag & ST_NOSUID) fl |= 0x8;
        if (v.f_flag & ST_NODEV) fl |= 0x10;
        if (v.f_flag & ST_NOEXEC) fl |= 0x4;
    }
    d->f_flags = fl;
    char real[PATH_MAX];
    std::string hp = realpath(host_path.c_str(), real) ? std::string(real) : host_path;
    std::string on, from, type;
    mount_of(hp, on, from, type);
    if (!g_rootfs.empty() && on.rfind(g_rootfs, 0) == 0) { on = on.substr(g_rootfs.size()); if (on.empty()) on = "/"; }
    snprintf(d->f_fstypename, sizeof d->f_fstypename, "%s", type.c_str());
    snprintf(d->f_mntonname, sizeof d->f_mntonname, "%s", on.c_str());
    snprintf(d->f_mntfromname, sizeof d->f_mntfromname, "%s", from.c_str());
    return 0;
}
static int f_statfs(const char* p, DarwinStatfs* d) {
    std::string s = rp(p);
    struct statfs l;
    if (statfs(s.c_str(), &l) < 0) return -1;
    return fill_statfs(l, s, d);
}
static int f_fstatfs(int fd, DarwinStatfs* d) {
    struct statfs l;
    if (fstatfs(fd, &l) < 0) return -1;
    char path[PATH_MAX];
    ssize_t n = readlink(("/proc/self/fd/" + std::to_string(fd)).c_str(), path, sizeof path - 1);
    return fill_statfs(l, n > 0 ? std::string(path, (size_t)n) : std::string("/"), d);
}
static void fill_statvfs(const struct statvfs& l, DarwinStatvfs* d) {
    memset(d, 0, sizeof *d);
    auto c32 = [](unsigned long long v) { return (uint32_t)(v > 0xffffffffull ? 0xffffffffull : v); };
    d->f_bsize = l.f_bsize; d->f_frsize = l.f_frsize;
    d->f_blocks = c32(l.f_blocks); d->f_bfree = c32(l.f_bfree); d->f_bavail = c32(l.f_bavail);
    d->f_files = c32(l.f_files); d->f_ffree = c32(l.f_ffree); d->f_favail = c32(l.f_favail);
    d->f_fsid = l.f_fsid; d->f_flag = l.f_flag & (ST_RDONLY | ST_NOSUID); d->f_namemax = l.f_namemax;
}
static int f_statvfs(const char* p, DarwinStatvfs* d) {
    struct statvfs l;
    if (statvfs(rp(p).c_str(), &l) < 0) return -1;
    fill_statvfs(l, d);
    return 0;
}
static int f_fstatvfs(int fd, DarwinStatvfs* d) {
    struct statvfs l;
    if (fstatvfs(fd, &l) < 0) return -1;
    fill_statvfs(l, d);
    return 0;
}

// basename/dirname: BSD semantics ("/a/b/" -> "b", "" -> "."), results in a per-thread buffer
static char* f_basename(const char* p) {
    static thread_local char buf[PATH_MAX];
    if (!p || !*p) return strcpy(buf, ".");
    std::string s(p);
    while (s.size() > 1 && s.back() == '/') s.pop_back();
    size_t sl = s.rfind('/');
    std::string b = (sl == std::string::npos || s == "/") ? s : s.substr(sl + 1);
    snprintf(buf, sizeof buf, "%s", b.c_str());
    return buf;
}
static char* f_dirname(const char* p) {
    static thread_local char buf[PATH_MAX];
    if (!p || !*p) return strcpy(buf, ".");
    std::string s(p);
    while (s.size() > 1 && s.back() == '/') s.pop_back();
    size_t sl = s.rfind('/');
    if (sl == std::string::npos) return strcpy(buf, ".");
    while (sl > 0 && s[sl - 1] == '/') sl--;
    std::string d = sl == 0 ? "/" : s.substr(0, sl);
    snprintf(buf, sizeof buf, "%s", d.c_str());
    return buf;
}

// ---- getattrlist family (subset): common NAME / DEVID / FSID / OBJTYPE, volume CAPABILITIES ---------------------
struct DarwinAttrlist { uint16_t bitmapcount, reserved; uint32_t commonattr, volattr, dirattr, fileattr, forkattr; };
static uint32_t vtype_of(mode_t m) {
    switch (m & S_IFMT) {
        case S_IFREG: return 1; case S_IFDIR: return 2; case S_IFBLK: return 3; case S_IFCHR: return 4;
        case S_IFLNK: return 5; case S_IFSOCK: return 6; case S_IFIFO: return 7;
    }
    return 0;
}
static int attrlist_fill(const std::string& host, int fd, const DarwinAttrlist* al, void* buf, size_t size, bool nofollow) {
    if (!al || al->bitmapcount != 5) { errno = EINVAL; return -1; }
    const uint32_t kCommon = 0x1 | 0x2 | 0x4 | 0x8, kVol = 0x80000000u | 0x20000;
    if ((al->commonattr & ~kCommon) || (al->volattr & ~kVol) || al->dirattr || al->fileattr || al->forkattr) { errno = ENOTSUP; return -1; }
    struct stat st;
    int r = fd >= 0 ? fstat(fd, &st) : (nofollow ? lstat(host.c_str(), &st) : stat(host.c_str(), &st));
    if (r < 0) return -1;
    std::vector<uint8_t> fixed, var;
    auto put32 = [&](uint32_t v) { fixed.insert(fixed.end(), (uint8_t*)&v, (uint8_t*)&v + 4); };
    size_t name_ref = (size_t)-1;
    if (al->volattr & 0x20000) {   // vol_capabilities_attr_t: FORMAT / INTERFACES capabilities and valid masks
        uint32_t caps[4] = {0x1 | 0x2 | 0x40 | 0x80 | 0x100 | 0x200 | 0x400 | 0x800, 0, 0, 0};
        uint32_t valid[4] = {0x7ffffff, 0, 0, 0};
        for (uint32_t c : caps) put32(c);
        for (uint32_t v : valid) put32(v);
    } else {
        if (al->commonattr & 0x1) { name_ref = fixed.size(); put32(0); put32(0); }
        if (al->commonattr & 0x2) put32((uint32_t)darwin_dev_from_linux(st.st_dev));
        if (al->commonattr & 0x4) { put32((uint32_t)darwin_dev_from_linux(st.st_dev)); put32(0); }
        if (al->commonattr & 0x8) put32(vtype_of(st.st_mode));
        if (name_ref != (size_t)-1) {
            std::string path = host;
            char rpbuf[PATH_MAX];
            if (fd < 0 && !nofollow && realpath(host.c_str(), rpbuf)) path = rpbuf;   // a followed link: the target's name
            if (fd >= 0) {
                char t[PATH_MAX];
                ssize_t n = readlink(("/proc/self/fd/" + std::to_string(fd)).c_str(), t, sizeof t - 1);
                path = n > 0 ? std::string(t, (size_t)n) : std::string();
            }
            while (path.size() > 1 && path.back() == '/') path.pop_back();
            std::string nm = path == "/" || (!g_rootfs.empty() && path == g_rootfs) ? std::string("/") : path.substr(path.rfind('/') + 1);
            var.insert(var.end(), nm.begin(), nm.end());
            var.push_back(0);
            while (var.size() % 4) var.push_back(0);
            int32_t off = (int32_t)(fixed.size() - name_ref);   // from the attrreference to the data
            uint32_t len = (uint32_t)nm.size() + 1;
            memcpy(&fixed[name_ref], &off, 4);
            memcpy(&fixed[name_ref + 4], &len, 4);
        }
    }
    uint32_t total = (uint32_t)(4 + fixed.size() + var.size());
    std::vector<uint8_t> out(4);
    memcpy(out.data(), &total, 4);
    out.insert(out.end(), fixed.begin(), fixed.end());
    out.insert(out.end(), var.begin(), var.end());
    memcpy(buf, out.data(), std::min(size, out.size()));
    if (size >= 4 && size < out.size()) memcpy(buf, &total, 4);   // truncated: the length still says what was needed
    return 0;
}
static int f_getattrlist(const char* p, const DarwinAttrlist* al, void* buf, size_t size, uint32_t opt) {
    return attrlist_fill(rp(p, !(opt & 1)), -1, al, buf, size, opt & 1);
}
static int f_fgetattrlist(int fd, const DarwinAttrlist* al, void* buf, size_t size, uint32_t) { return attrlist_fill({}, fd, al, buf, size, false); }
// setattrlist family: common attributes packed in bit order, each 4-byte aligned. Times (MODTIME, ACCTIME), owner, group,
// mode and flags (0 only: no BSD file flags here) are applied; CRTIME and BKUPTIME are accepted but not stored (Linux
// cannot set a birth time), CHGTIME is read-only (EINVAL), as is any non-common attribute.
static int attrlist_apply(const std::string& host, int fd, const DarwinAttrlist* al, const void* buf, size_t size, bool nofollow) {
    if (!al || !buf) { errno = EFAULT; return -1; }
    const uint32_t kSettable = 0x200 | 0x400 | 0x1000 | 0x2000 | 0x4000 | 0x8000 | 0x10000 | 0x20000 | 0x40000;
    if (al->bitmapcount != 5 || (al->commonattr & ~kSettable) || al->volattr || al->dirattr || al->fileattr || al->forkattr) {
        errno = EINVAL; return -1;
    }
    const uint8_t* p = (const uint8_t*)buf;
    size_t off = 0;
    struct timespec ts[2] = {{0, UTIME_OMIT}, {0, UTIME_OMIT}};
    uid_t uid = (uid_t)-1; gid_t gid = (gid_t)-1;
    int64_t mode = -1;
    uint32_t flags = 0;
    for (uint32_t bit = 0x200; bit <= 0x40000; bit <<= 1) {
        if (!(al->commonattr & bit)) continue;
        size_t len = (bit <= 0x2000) ? 16 : bit == 0x4000 ? 32 : 4;
        if (off + len > size) { errno = EINVAL; return -1; }
        int64_t t[2]; uint32_t v = 0;
        if (len == 16) memcpy(t, p + off, 16); else if (len == 4) memcpy(&v, p + off, 4);
        if (bit == 0x400) { ts[1].tv_sec = t[0]; ts[1].tv_nsec = t[1]; }
        else if (bit == 0x1000) { ts[0].tv_sec = t[0]; ts[0].tv_nsec = t[1]; }
        else if (bit == 0x8000) uid = v;
        else if (bit == 0x10000) gid = v;
        else if (bit == 0x20000) mode = v & 07777;
        else if (bit == 0x40000) flags = v;
        off += (len + 3) & ~(size_t)3;
    }
    if (flags) { errno = ENOTSUP; return -1; }
    int r = 0;
    if (ts[0].tv_nsec != UTIME_OMIT || ts[1].tv_nsec != UTIME_OMIT)
        r = fd >= 0 ? futimens(fd, ts) : utimensat(AT_FDCWD, host.c_str(), ts, nofollow ? AT_SYMLINK_NOFOLLOW : 0);
    if (!r && (uid != (uid_t)-1 || gid != (gid_t)-1))
        r = fd >= 0 ? fchown(fd, uid, gid) : nofollow ? lchown(host.c_str(), uid, gid) : chown(host.c_str(), uid, gid);
    if (!r && mode >= 0) {
        if (fd >= 0) r = fchmod(fd, (mode_t)mode);
        else r = fchmodat(AT_FDCWD, host.c_str(), (mode_t)mode, 0);   // (a link's own mode cannot be set on Linux)
    }
    return r;
}
static int f_setattrlist(const char* p, const DarwinAttrlist* al, const void* buf, size_t size, uint32_t opt) {
    if (!p) { errno = EFAULT; return -1; }
    return attrlist_apply(rp(p, !(opt & 1)), -1, al, buf, size, opt & 1);
}
static int f_fsetattrlist(int fd, const DarwinAttrlist* al, const void* buf, size_t size, uint32_t) {
    return attrlist_apply({}, fd, al, buf, size, false);
}
static int f_setattrlistat(int dfd, const char* p, const DarwinAttrlist* al, const void* buf, size_t size, uint32_t opt) {
    if (!p) { errno = EFAULT; return -1; }
    std::string s = at_path(&dfd, p, !(opt & 1));
    if (dfd != AT_FDCWD && s[0] != '/') s = "/proc/self/fd/" + std::to_string(dfd) + "/" + s;
    return attrlist_apply(s, -1, al, buf, size, opt & 1);
}
static int f_getattrlistat(int dfd, const char* p, const DarwinAttrlist* al, void* buf, size_t size, uint64_t opt) {
    std::string s = at_path(&dfd, p, !(opt & 1));
    if (dfd != AT_FDCWD && s[0] != '/') {
        char t[PATH_MAX];
        ssize_t n = readlink(("/proc/self/fd/" + std::to_string(dfd)).c_str(), t, sizeof t - 1);
        if (n > 0) s = std::string(t, (size_t)n) + "/" + s;
    }
    return attrlist_fill(s, -1, al, buf, size, opt & 1);
}

// ---- System V IPC: semctl commands are renumbered (Darwin GETNCNT..SETALL = 3..9), IPC_STAT/IPC_SET structs differ
// (#pragma pack(4) on Darwin). semget/shmget/semop/shmat/shmdt flags and struct sembuf are the same.
struct DarwinIpcPerm { uint32_t uid, gid, cuid, cgid; uint16_t mode, seq; int32_t key; };
struct __attribute__((packed, aligned(4))) DarwinShmidDs {
    DarwinIpcPerm perm; uint64_t segsz; int32_t lpid, cpid; uint16_t nattch; uint16_t pad;
    int64_t atime, dtime, ctime; uint64_t internal;
};
struct __attribute__((packed, aligned(4))) DarwinSemidDs {
    DarwinIpcPerm perm; int32_t base; uint16_t nsems; uint16_t pad0; int64_t otime; int32_t pad1; int64_t ctime; int32_t pad2, pad3[4];
};
static_assert(sizeof(DarwinShmidDs) == 76 && offsetof(DarwinShmidDs, atime) == 44, "Darwin shmid_ds");
static_assert(sizeof(DarwinSemidDs) == 72 && offsetof(DarwinSemidDs, ctime) == 44, "Darwin semid_ds");
static void perm_out(const struct ipc_perm& l, DarwinIpcPerm* d) {
    d->uid = l.uid; d->gid = l.gid; d->cuid = l.cuid; d->cgid = l.cgid; d->mode = (uint16_t)l.mode; d->seq = (uint16_t)l.__seq; d->key = l.__key;
}
static int f_semctl(int id, int num, int cmd, const uint64_t* ap) {
    static const int kCmd[10] = {IPC_RMID, IPC_SET, IPC_STAT, GETNCNT, GETPID, GETVAL, GETALL, GETZCNT, SETVAL, SETALL};
    if (cmd < 0 || cmd > 9) { errno = EINVAL; return -1; }
    uint64_t arg = ap ? ap[0] : 0;
    int lc = kCmd[cmd];
    if (lc == IPC_STAT || lc == IPC_SET) {
        DarwinSemidDs* d = (DarwinSemidDs*)(uintptr_t)arg;
        struct semid_ds l;
        memset(&l, 0, sizeof l);
        if (lc == IPC_SET) {
            if (semctl(id, 0, IPC_STAT, &l) < 0) return -1;
            l.sem_perm.uid = d->perm.uid; l.sem_perm.gid = d->perm.gid; l.sem_perm.mode = d->perm.mode & 0777;
            return semctl(id, 0, IPC_SET, &l);
        }
        if (semctl(id, 0, IPC_STAT, &l) < 0) return -1;
        memset(d, 0, sizeof *d);
        perm_out(l.sem_perm, &d->perm);
        d->nsems = (uint16_t)l.sem_nsems; d->otime = l.sem_otime; d->ctime = l.sem_ctime;
        return 0;
    }
    if (lc == SETVAL) return semctl(id, num, SETVAL, (int)arg);
    if (lc == GETALL || lc == SETALL) return semctl(id, num, lc, (unsigned short*)(uintptr_t)arg);
    return semctl(id, num, lc);
}
static int f_shmctl(int id, int cmd, void* buf) {
    if (cmd == IPC_RMID) return shmctl(id, IPC_RMID, nullptr);
    if (cmd != IPC_STAT && cmd != IPC_SET) { errno = EINVAL; return -1; }
    DarwinShmidDs* d = (DarwinShmidDs*)buf;
    struct shmid_ds l;
    if (shmctl(id, IPC_STAT, &l) < 0) return -1;
    if (cmd == IPC_SET) {
        l.shm_perm.uid = d->perm.uid; l.shm_perm.gid = d->perm.gid; l.shm_perm.mode = d->perm.mode & 0777;
        return shmctl(id, IPC_SET, &l);
    }
    memset(d, 0, sizeof *d);
    perm_out(l.shm_perm, &d->perm);
    d->segsz = l.shm_segsz; d->lpid = l.shm_lpid; d->cpid = l.shm_cpid; d->nattch = (uint16_t)l.shm_nattch;
    d->atime = l.shm_atime; d->dtime = l.shm_dtime; d->ctime = l.shm_ctime;
    return 0;
}
int darwin_semctl_v(int id, int num, int cmd, const uint64_t* ap) { return f_semctl(id, num, cmd, ap); }

void* darwin_fs_lookup(const char* name) {
    struct E { const char* n; void* f; };
    static const E k[] = {
        {"_mkdirat", (void*)&f_mkdirat}, {"_mkfifoat", (void*)&f_mkfifoat}, {"_mknodat", (void*)&f_mknodat},
        {"_unlinkat", (void*)&f_unlinkat}, {"_renameat", (void*)&f_renameat}, {"_renameatx_np", (void*)&f_renameatx_np}, {"_pipe2", (void*)&f_pipe2}, {"_dup3", (void*)&f_dup3},
        {"_clonefile", (void*)&f_clonefile}, {"_clonefileat", (void*)&f_clonefileat}, {"_fclonefileat", (void*)&f_fclonefileat},
        {"_renamex_np", (void*)&f_renamex_np}, {"_readlinkat", (void*)&f_readlinkat}, {"_faccessat", (void*)&f_faccessat},
        {"_fchmodat", (void*)&f_fchmodat}, {"_fchownat", (void*)&f_fchownat}, {"_linkat", (void*)&f_linkat},
        {"_symlinkat", (void*)&f_symlinkat}, {"_utimensat", (void*)&f_utimensat}, {"_futimens", (void*)&f_futimens},
        {"_chdir", (void*)&f_chdir}, {"_chroot", (void*)&f_chroot}, {"_link", (void*)&f_link}, {"_symlink", (void*)&f_symlink},
        {"_truncate", (void*)&f_truncate}, {"_mkfifo", (void*)&f_mkfifo}, {"_mknod", (void*)&f_mknod},
        {"_lchown", (void*)&f_lchown}, {"_lchmod", (void*)&f_lchmod}, {"_creat", (void*)&f_creat},
        {"_utimes", (void*)&f_utimes}, {"_lutimes", (void*)&f_lutimes}, {"_futimes", (void*)&f_futimes},
        {"_utime", (void*)&f_utime}, {"_setitimer", (void*)&f_setitimer}, {"_getitimer", (void*)&f_getitimer},
        {"_settimeofday", (void*)&f_settimeofday}, {"_adjtime", (void*)&f_adjtime},
        {"_pathconf", (void*)&f_pathconf}, {"_fpathconf", (void*)&f_fpathconf},
        {"_mkstemp", (void*)&f_mkstemp}, {"_mkstemps", (void*)&f_mkstemps}, {"_mkostemp", (void*)&f_mkostemp},
        {"_mkostemps", (void*)&f_mkostemps}, {"_mkdtemp", (void*)&f_mkdtemp},
        {"_getxattr", (void*)&f_getxattr}, {"_fgetxattr", (void*)&f_fgetxattr}, {"_setxattr", (void*)&f_setxattr},
        {"_fsetxattr", (void*)&f_fsetxattr}, {"_removexattr", (void*)&f_removexattr}, {"_fremovexattr", (void*)&f_fremovexattr},
        {"_listxattr", (void*)&f_listxattr}, {"_flistxattr", (void*)&f_flistxattr},
        {"_statfs", (void*)&f_statfs}, {"_statfs$INODE64", (void*)&f_statfs}, {"_statfs64", (void*)&f_statfs},
        {"_fstatfs", (void*)&f_fstatfs}, {"_fstatfs$INODE64", (void*)&f_fstatfs}, {"_fstatfs64", (void*)&f_fstatfs},
        {"_statvfs", (void*)&f_statvfs}, {"_fstatvfs", (void*)&f_fstatvfs},
        {"_getattrlist", (void*)&f_getattrlist}, {"_fgetattrlist", (void*)&f_fgetattrlist},
        {"_getattrlistat", (void*)&f_getattrlistat},
        {"_setattrlist", (void*)&f_setattrlist}, {"_fsetattrlist", (void*)&f_fsetattrlist}, {"_setattrlistat", (void*)&f_setattrlistat},
        {"_basename", (void*)&f_basename}, {"_dirname", (void*)&f_dirname}, {"_shmctl", (void*)&f_shmctl},
    };
    for (const E& e : k) if (!strcmp(e.n, name)) return e.f;
    return nullptr;
}

}  // namespace xef
