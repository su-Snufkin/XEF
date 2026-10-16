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
#include <sys/ipc.h>
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
        {"_unlinkat", (void*)&f_unlinkat}, {"_renameat", (void*)&f_renameat}, {"_renameatx_np", (void*)&f_renameatx_np},
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
        {"_basename", (void*)&f_basename}, {"_dirname", (void*)&f_dirname}, {"_shmctl", (void*)&f_shmctl},
    };
    for (const E& e : k) if (!strcmp(e.n, name)) return e.f;
    return nullptr;
}

}  // namespace xef
