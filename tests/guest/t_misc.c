#include <dirent.h>
#include <fcntl.h>
#include <setjmp.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
static jmp_buf jb;
static void deep(int n) { if (n == 0) longjmp(jb, 42); deep(n - 1); }
int main(int argc, char** argv) {
    int r = setjmp(jb);
    if (r == 0) deep(100);
    printf("longjmp %d argc=%d\n", r, argc);
    _Atomic long counter = 0;
    atomic_int flag = 0;
    for (int i = 0; i < 10000; i++) { atomic_fetch_add(&counter, i); atomic_fetch_sub(&counter, 1); }
    int expected = 0;
    atomic_compare_exchange_strong(&flag, &expected, 5);
    long ex = atomic_exchange(&counter, 7);
    printf("atomic %ld %d %ld\n", ex, atomic_load(&flag), atomic_load(&counter));
    char path[] = "/tmp/xef_test_XXXXXX";
    int fd = mkstemp(path);
    const char msg[] = "file contents line 1\nline 2\n";
    write(fd, msg, sizeof msg - 1);
    lseek(fd, 0, SEEK_SET);
    char buf[64] = {0};
    ssize_t n = read(fd, buf, sizeof buf - 1);
    struct stat st; fstat(fd, &st);
    printf("read %zd size %lld mode %o\n", n, (long long)st.st_size, st.st_mode & 0777);
    close(fd);
    FILE* f = fopen(path, "r"); char line[64]; int lines = 0;
    while (fgets(line, sizeof line, f)) lines++;
    fclose(f);
    struct stat st2; stat(path, &st2);
    printf("lines %d same-ino %d\n", lines, st.st_ino == st2.st_ino);
    unlink(path);
    printf("exists after unlink %d\n", access(path, F_OK) == 0);
    DIR* d = opendir("/");
    int ents = 0; struct dirent* e;
    while ((e = readdir(d))) ents += e->d_name[0] != 0;
    closedir(d);
    printf("dir ok %d\n", ents > 3);
    struct timespec t1, t2; clock_gettime(CLOCK_MONOTONIC, &t1); clock_gettime(CLOCK_MONOTONIC, &t2);
    printf("time monotonic %d getenv %s\n", t2.tv_sec >= t1.tv_sec, getenv("XEF_T") ? getenv("XEF_T") : "-");
    char cwd[256]; printf("cwd ok %d pid>0 %d\n", getcwd(cwd, sizeof cwd) != 0, getpid() > 0);
    return 3;
}
