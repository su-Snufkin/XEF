// clonefile / clonefileat / fclonefileat: a copy of the data and the attributes; EEXIST on an existing destination
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/clonefile.h>
#include <sys/stat.h>
#include <unistd.h>

static void show(const char* p) {
    struct stat st;
    if (lstat(p, &st) < 0) { printf("  %s: %s\n", p, strerror(errno)); return; }
    char buf[64] = {0};
    if (S_ISLNK(st.st_mode)) { readlink(p, buf, sizeof buf - 1); printf("  %s: link -> %s\n", p, buf); return; }
    int fd = open(p, O_RDONLY); ssize_t n = read(fd, buf, sizeof buf - 1); close(fd);
    printf("  %s: mode %o size %lld mtime %ld data \"%.*s\"\n", p, st.st_mode & 07777, (long long)st.st_size,
           (long)st.st_mtimespec.tv_sec, (int)(n > 0 ? n : 0), buf);
}

int main(void) {
    char dir[] = "/tmp/xef_clone_XXXXXX";
    if (!mkdtemp(dir) || chdir(dir) < 0) { perror("setup"); return 1; }
    int fd = open("src", O_CREAT | O_WRONLY, 0640);
    write(fd, "hello clone", 11);
    close(fd);
    chmod("src", 0640);
    struct timespec ts[2] = {{1000000000, 0}, {1200000000, 0}};
    utimensat(AT_FDCWD, "src", ts, 0);
    symlink("src", "lnk");
    mkdir("sub", 0755);

    printf("clonefile src a: %d\n", clonefile("src", "a", 0)); show("a");
    errno = 0; printf("clonefile src a again: %d %s\n", clonefile("src", "a", 0), strerror(errno));
    printf("clonefile lnk b (follow): %d\n", clonefile("lnk", "b", 0)); show("b");
    printf("clonefile lnk c NOFOLLOW: %d\n", clonefile("lnk", "c", CLONE_NOFOLLOW)); show("c");
    int dfd = open("sub", O_RDONLY | O_DIRECTORY);
    printf("clonefileat src sub/d: %d\n", clonefileat(AT_FDCWD, "src", dfd, "d", 0)); show("sub/d");
    int sfd = open("src", O_RDONLY);
    lseek(sfd, 3, SEEK_SET);
    printf("fclonefileat src sub/e: %d\n", fclonefileat(sfd, dfd, "e", 0)); show("sub/e");
    printf("src offset kept: %lld\n", (long long)lseek(sfd, 0, SEEK_CUR));
    errno = 0; printf("clonefile missing: %d %s\n", clonefile("nope", "f", 0), strerror(errno));
    errno = 0; printf("clonefile bad flags: %d %s\n", clonefile("src", "g", 0x100), strerror(errno));
    close(sfd); close(dfd);

    unlink("a"); unlink("b"); unlink("c"); unlink("sub/d"); unlink("sub/e"); unlink("lnk"); unlink("src");
    rmdir("sub"); chdir("/");
    printf("cleanup: %d\n", rmdir(dir));
    return 0;
}
