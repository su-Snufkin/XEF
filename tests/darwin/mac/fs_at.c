// *at calls with a directory fd and Darwin AT_* flags, renameatx_np, utimensat UTIME_OMIT/NOW, pathconf names, mkstemp
// family (template written back), xattrs (options, ENOATTR, listing), statfs/statvfs layout, BSD basename/dirname.
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/xattr.h>
#include <unistd.h>
int main(void) {
  char base[] = "/tmp/xef_fsat_XXXXXX";
  printf("mkdtemp ok=%d tail_changed=%d\n", mkdtemp(base) != NULL, strcmp(base + strlen(base) - 6, "XXXXXX") != 0);
  int d = open("/", O_RDONLY | O_DIRECTORY);
  struct stat st;
  printf("fstatat(/,tmp) via fd=%d\n", fstatat(d, "tmp", &st, AT_SYMLINK_NOFOLLOW) == 0 || fstatat(d, "private/tmp", &st, 0) == 0);
  close(d);
  int dir = open(base, O_RDONLY | O_DIRECTORY);
  printf("mkdirat=%d ", mkdirat(dir, "sub", 0755));
  int f = openat(dir, "sub/file", O_CREAT | O_WRONLY | O_EXCL, 0644); write(f, "abc", 3); close(f);
  printf("openat excl again=%d errno=%d\n", openat(dir, "sub/file", O_CREAT | O_WRONLY | O_EXCL, 0644), errno);
  printf("symlinkat=%d ", symlinkat("sub/file", dir, "link"));
  char buf[256]; ssize_t n = readlinkat(dir, "link", buf, sizeof buf); buf[n > 0 ? n : 0] = 0; printf("readlinkat=%s ", buf);
  printf("fstatat nofollow islnk=%d follow size=%lld\n", fstatat(dir, "link", &st, AT_SYMLINK_NOFOLLOW) == 0 && S_ISLNK(st.st_mode),
         fstatat(dir, "link", &st, 0) == 0 ? (long long)st.st_size : -1LL);
  printf("faccessat W=%d X=%d\n", faccessat(dir, "sub/file", W_OK, 0), faccessat(dir, "sub/file", X_OK, AT_EACCESS) == 0);
  printf("fchmodat=%d mode=%o\n", fchmodat(dir, "sub/file", 0600, 0), fstatat(dir, "sub/file", &st, 0) == 0 ? st.st_mode & 0777 : 0);
  printf("linkat=%d nlink=%d\n", linkat(dir, "sub/file", dir, "hard", 0), fstatat(dir, "hard", &st, 0) == 0 ? (int)st.st_nlink : -1);
  struct timespec ts[2] = {{1000000000, 0}, {1200000000, 500}};
  utimensat(dir, "sub/file", ts, 0); fstatat(dir, "sub/file", &st, 0);
  printf("utimensat atime=%ld mtime=%ld.%ld ", (long)st.st_atimespec.tv_sec, (long)st.st_mtimespec.tv_sec, (long)st.st_mtimespec.tv_nsec);
  struct timespec omit[2] = {{0, UTIME_OMIT}, {0, UTIME_OMIT}}; utimensat(dir, "sub/file", omit, 0); fstatat(dir, "sub/file", &st, 0);
  printf("omit kept=%d\n", st.st_mtimespec.tv_sec == 1200000000);
  f = openat(dir, "other", O_CREAT | O_WRONLY, 0644); write(f, "zz", 2); close(f);
  printf("renameatx SWAP=%d ", renameatx_np(dir, "other", dir, "sub/file", RENAME_SWAP));
  fstatat(dir, "sub/file", &st, 0); printf("swapped size=%lld ", (long long)st.st_size);
  printf("EXCL=%d errno=%d\n", renameatx_np(dir, "other", dir, "sub/file", RENAME_EXCL), errno);
  printf("unlinkat dir no flag=%d errno=%d ", unlinkat(dir, "sub", 0), errno);
  unlinkat(dir, "sub/file", 0);
  printf("REMOVEDIR=%d\n", unlinkat(dir, "sub", AT_REMOVEDIR));
  char path[512]; snprintf(path, sizeof path, "%s/other", base);
  printf("pathconf NAME_MAX=%ld PIPE_BUF ok=%d CASE_SENSITIVE ok=%d bad=%ld errno=%d\n", pathconf(path, _PC_NAME_MAX),
         pathconf(path, _PC_PIPE_BUF) >= 512, pathconf(path, _PC_CASE_SENSITIVE) >= 0, pathconf(path, 999), errno);
  errno = 0; ssize_t gx = getxattr(path, "org.xef.test", buf, sizeof buf, 0, 0); printf("getxattr missing=%zd enoattr=%d\n", gx, errno == ENOATTR);
  int sx = setxattr(path, "org.xef.test", "val", 3, 0, 0);
  if (sx == 0) {
    n = getxattr(path, "org.xef.test", buf, sizeof buf, 0, 0); buf[n > 0 ? n : 0] = 0;
    printf("xattr set get=%s create-again=%d errno_eexist=%d ", buf, setxattr(path, "org.xef.test", "x", 1, 0, XATTR_CREATE), errno == EEXIST);
    n = listxattr(path, buf, sizeof buf, 0); printf("list=%.*s remove=%d\n", (int)(n > 0 ? n - 1 : 0), buf, removexattr(path, "org.xef.test", 0));
  } else printf("xattr unsupported here\n");
  struct statfs sf; struct statvfs sv;
  printf("statfs=%d bsize>0=%d blocks>0=%d mnton_abs=%d local=%d statvfs=%d frsize>0=%d namemax=%lu\n", statfs(path, &sf), sf.f_bsize > 0, sf.f_blocks > 0,
         sf.f_mntonname[0] == '/', !!(sf.f_flags & MNT_LOCAL), statvfs(path, &sv), sv.f_frsize > 0, sv.f_namemax);
  char t1[] = "/tmp/xef_ms_XXXXXX"; int mf = mkstemp(t1); printf("mkstemp fd>=0=%d exists=%d\n", mf >= 0, access(t1, F_OK) == 0); unlink(t1);
  char t2[] = "/tmp/xef_ms_XXXXXX.txt"; mf = mkstemps(t2, 4); printf("mkstemps suffix kept=%d\n", mf >= 0 && !strcmp(t2 + strlen(t2) - 4, ".txt")); unlink(t2);
  char b1[] = "/a/b/", b2[] = "usr", b3[] = "/", b4[] = "a//b";
  printf("basename %s %s %s dirname %s %s %s\n", basename(b1), basename(b2), basename(b3), dirname(strdup("/a/b/")), dirname(strdup("usr")), dirname(b4));
  unlinkat(dir, "other", 0); unlinkat(dir, "link", 0); unlinkat(dir, "hard", 0); close(dir); rmdir(base);
  printf("cleanup gone=%d\n", access(base, F_OK) != 0);
  return 0;
}
