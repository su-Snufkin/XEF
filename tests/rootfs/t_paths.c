// Path resolution inside the guest rootfs: absolute symlinks point into the rootfs, not the host's /.
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void show(const char* p) {
    char buf[64] = {0};
    int fd = open(p, O_RDONLY);
    if (fd >= 0) { read(fd, buf, sizeof buf - 1); close(fd); buf[strcspn(buf, "\n")] = 0; }
    printf("%s: %s\n", p, fd >= 0 ? buf : "missing");
}

int main(void) {
    show("/etc/xef-real.conf");
    show("/usr/share/xef/link.conf");        // -> /etc/xef-real.conf
    show("/usr/share/xef/etc/xef-real.conf"); // directory link -> /etc
    show("/usr/share/xef/rel.conf");          // -> ../../../etc/xef-real.conf
    show("/usr/share/xef/chain.conf");        // -> /usr/share/xef/link.conf
    char t[128];
    ssize_t n = readlink("/usr/share/xef/link.conf", t, sizeof t - 1);
    t[n > 0 ? n : 0] = 0;
    printf("readlink: %s\n", t);
    struct stat st;
    printf("lstat is link: %d, stat is file: %d\n", lstat("/usr/share/xef/link.conf", &st) == 0 && S_ISLNK(st.st_mode),
           stat("/usr/share/xef/link.conf", &st) == 0 && S_ISREG(st.st_mode));
    printf("unlink link: %d\n", unlink("/usr/share/xef/chain.conf"));
    show("/usr/share/xef/chain.conf");
    show("/etc/xef-real.conf");
    return 0;
}
