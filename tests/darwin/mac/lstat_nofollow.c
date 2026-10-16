// lstat/open/mkdir/rmdir on symbolic links: the link itself, not its target
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char* kind(mode_t m) { return S_ISLNK(m) ? "link" : S_ISDIR(m) ? "dir" : S_ISREG(m) ? "file" : "other"; }

int main(void) {
    char dir[] = "/tmp/xef_lstat_XXXXXX";
    if (!mkdtemp(dir)) { perror("mkdtemp"); return 1; }
    if (chdir(dir) < 0) { perror("chdir"); return 1; }
    mkdir("realdir", 0755);
    int fd = open("realdir/file", O_CREAT | O_WRONLY, 0644); write(fd, "abc", 3); close(fd);
    symlink("realdir", "dirlink");
    symlink("realdir/file", "filelink");
    symlink("nowhere", "dangling");

    struct stat st;
    const char* names[] = {"dirlink", "filelink", "dangling", "realdir"};
    for (int i = 0; i < 4; i++) {
        int r = lstat(names[i], &st);
        printf("lstat %-8s r=%d %s", names[i], r, r == 0 ? kind(st.st_mode) : strerror(errno));
        r = stat(names[i], &st);
        printf(" | stat r=%d %s\n", r, r == 0 ? kind(st.st_mode) : strerror(errno));
    }
    char abs[1100];
    snprintf(abs, sizeof abs, "%s/dirlink", dir);
    printf("lstat abs dirlink: %s\n", lstat(abs, &st) == 0 ? kind(st.st_mode) : strerror(errno));

    errno = 0; fd = open("filelink", O_RDONLY | O_NOFOLLOW);
    printf("open O_NOFOLLOW filelink: %s\n", fd >= 0 ? "opened" : strerror(errno));
    if (fd >= 0) close(fd);
    errno = 0; fd = open("filelink", O_RDONLY);
    printf("open filelink: %s\n", fd >= 0 ? "opened" : strerror(errno));
    if (fd >= 0) close(fd);
    errno = 0; fd = open("dangling", O_CREAT | O_EXCL | O_WRONLY, 0644);
    printf("open O_CREAT|O_EXCL dangling: %s\n", fd >= 0 ? "created" : strerror(errno));
    if (fd >= 0) close(fd);
    printf("nowhere exists: %s\n", access("nowhere", F_OK) == 0 ? "yes" : "no");
    errno = 0; fd = open("dangling", O_CREAT | O_WRONLY, 0644);
    printf("open O_CREAT dangling: %s\n", fd >= 0 ? "created target" : strerror(errno));
    if (fd >= 0) close(fd);
    printf("nowhere exists: %s\n", access("nowhere", F_OK) == 0 ? "yes" : "no");

    errno = 0; printf("mkdir dirlink: %d %s\n", mkdir("dirlink", 0755), strerror(errno));
    errno = 0; printf("rmdir dirlink: %d %s\n", rmdir("dirlink"), strerror(errno));
    printf("realdir still there: %s\n", stat("realdir/file", &st) == 0 ? "yes" : "no");

    unlink("dirlink"); unlink("filelink"); unlink("dangling"); unlink("nowhere");
    unlink("realdir/file"); rmdir("realdir");
    chdir("/"); printf("cleanup: %d\n", rmdir(dir));
    return 0;
}
