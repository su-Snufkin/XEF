// chflags/lchflags/fchflags with no flags and UF_NODUMP; errors on missing files; ttyname_r on a pty and a bad fd
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <util.h>

int main(void) {
    const char* p = "/tmp/xef_chflags.txt";
    close(open(p, O_CREAT | O_WRONLY, 0644));
    errno = 0; printf("chflags 0: %d\n", chflags(p, 0));
    errno = 0; printf("lchflags 0: %d\n", lchflags(p, 0));
    int fd = open(p, O_RDONLY);
    errno = 0; printf("fchflags 0: %d\n", fchflags(fd, 0));
    errno = 0; int r = chflags(p, UF_NODUMP);
    struct stat st; stat(p, &st);
    printf("chflags NODUMP: %d nodump set %d\n", r, (st.st_flags & UF_NODUMP) != 0);
    chflags(p, 0); stat(p, &st);
    printf("cleared: %d\n", (st.st_flags & UF_NODUMP) != 0);
    errno = 0; printf("chflags missing: %d %s\n", chflags("/tmp/xef_nope_x", 0), strerror(errno));
    errno = 0; printf("lchflags missing: %d %s\n", lchflags("/tmp/xef_nope_x", 0), strerror(errno));
    close(fd); unlink(p);

    int m, s;
    char name[256], buf[256];
    openpty(&m, &s, name, NULL, NULL);
    int e = ttyname_r(s, buf, sizeof buf);
    printf("ttyname_r: %d matches openpty name %d\n", e, e == 0 && strcmp(buf, name) == 0);
    printf("ttyname_r small buffer: %d\n", ttyname_r(s, buf, 5));
    printf("ttyname_r bad fd: %d\n", ttyname_r(1234, buf, sizeof buf));
    int pf = open("/dev/null", O_RDONLY);
    printf("ttyname_r not a tty: %d\n", ttyname_r(pf, buf, sizeof buf));
    errno = 0; char* t = ttyname(1234);
    printf("ttyname bad fd: %s %s\n", t ? t : "NULL", strerror(errno));
    return 0;
}
