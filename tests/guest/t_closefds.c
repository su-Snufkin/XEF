// The guest closes every descriptor it does not know about (like fork+exec helpers do) and then
// reuses the numbers; the translator's own descriptors must survive and must not alias them.
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

static volatile unsigned long sink;

int main(void) {
    for (int fd = 3; fd < 1024; fd++) close(fd);
    syscall(SYS_close_range, 3u, ~0u, 0u);
    char path[] = "/tmp/xef_closefds_XXXXXX";
    int fd = mkstemp(path);
    if (fd < 0) return 1;
    printf("fd is small: %d\n", fd < 10);
    // hot code: tier-2 requests flow through the translator's pipe meanwhile
    unsigned long x = 1;
    for (long i = 0; i < 300000000; i++) x = x * 6364136223846793005ul + (unsigned long)i;
    sink = x;
    write(fd, "data", 4);
    char buf[64] = {0};
    lseek(fd, 0, SEEK_SET);
    ssize_t n = read(fd, buf, sizeof buf - 1);
    printf("file: %zd '%s'\n", n, buf);
    close(fd);
    unlink(path);
    int p[2];
    printf("dup3 onto low fd: %d\n", pipe(p) == 0 && dup3(p[0], 5, 0) == 5);
    return 0;
}
