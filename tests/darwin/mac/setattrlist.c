// setattrlist / fsetattrlist / setattrlistat: times (as Rust's File::set_times), mode; invalid requests
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/attr.h>
#include <sys/stat.h>
#include <unistd.h>

static void show(const char* tag, const char* p) {
    struct stat st;
    stat(p, &st);
    printf("%s: mtime %ld.%09ld atime %ld.%09ld mode %o\n", tag, (long)st.st_mtimespec.tv_sec, st.st_mtimespec.tv_nsec,
           (long)st.st_atimespec.tv_sec, st.st_atimespec.tv_nsec, st.st_mode & 07777);
}

int main(void) {
    char dir[] = "/tmp/xef_setattr_XXXXXX";
    if (!mkdtemp(dir) || chdir(dir) < 0) return 1;
    int fd = open("f", O_CREAT | O_RDWR, 0644);

    struct attrlist al = {ATTR_BIT_MAP_COUNT, 0, ATTR_CMN_MODTIME | ATTR_CMN_ACCTIME, 0, 0, 0, 0};
    struct timespec t2[2] = {{1500000000, 123456789}, {1400000000, 5}};   // modified, accessed (bit order)
    printf("fsetattrlist times: %d\n", fsetattrlist(fd, &al, t2, sizeof t2, 0));
    show("after fsetattrlist", "f");

    struct attrlist al2 = {ATTR_BIT_MAP_COUNT, 0, ATTR_CMN_MODTIME, 0, 0, 0, 0};
    struct timespec m = {1600000000, 0};
    printf("setattrlist mtime: %d\n", setattrlist("f", &al2, &m, sizeof m, 0));
    show("after setattrlist", "f");

    struct attrlist al3 = {ATTR_BIT_MAP_COUNT, 0, ATTR_CMN_ACCESSMASK, 0, 0, 0, 0};
    uint32_t mode = 0600;
    printf("setattrlistat mode: %d\n", setattrlistat(AT_FDCWD, "f", &al3, &mode, sizeof mode, 0));
    show("after mode", "f");

    errno = 0;
    printf("short buffer: %d %s\n", fsetattrlist(fd, &al, t2, 16, 0), strerror(errno));
    struct attrlist bad = {ATTR_BIT_MAP_COUNT, 0, ATTR_CMN_NAME, 0, 0, 0, 0};
    errno = 0;
    printf("read-only attr: %d %s\n", fsetattrlist(fd, &bad, t2, sizeof t2, 0), strerror(errno));
    errno = 0;
    printf("missing file: %d %s\n", setattrlist("nope", &al2, &m, sizeof m, 0), strerror(errno));
    close(fd);
    unlink("f"); chdir("/"); rmdir(dir);
    return 0;
}
