#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
int main(int argc, char** argv) {
    if (argc > 1 && !strcmp(argv[1], "child")) { printf("child got %s\n", argv[2]); return 7; }
    if (argc > 1 && !strcmp(argv[1], "argv0")) { printf("argv[0] = %s\n", argv[0]); return 0; }
    fflush(stdout);
    pid_t p = fork();
    if (p == 0) { printf("in forked child\n"); fflush(stdout); _exit(5); }
    int st; waitpid(p, &st, 0);
    printf("fork child exit=%d\n", WEXITSTATUS(st));
    int fds[2]; pipe(fds);
    p = fork();
    if (p == 0) { close(fds[0]); write(fds[1], "via pipe", 9); _exit(0); }
    close(fds[1]); char buf[32] = {0}; read(fds[0], buf, sizeof buf); waitpid(p, &st, 0);
    printf("pipe: %s\n", buf);
    fflush(stdout);
    p = fork();
    if (p == 0) { execl(argv[0], argv[0], "child", "hello", (char*)0); perror("execl"); _exit(99); }
    waitpid(p, &st, 0);
    printf("exec child exit=%d\n", WEXITSTATUS(st));
    fflush(stdout);
    p = fork();   // argv[0] other than the path (multi-call binaries, login shells)
    if (p == 0) { execl(argv[0], "renamed", "argv0", (char*)0); perror("execl"); _exit(99); }
    waitpid(p, &st, 0);
    int r = system("echo from shell");
    printf("system=%d\n", WEXITSTATUS(r));
    FILE* f = popen("echo popen works", "r");
    char line[64]; fgets(line, sizeof line, f); pclose(f);
    printf("%s", line);
    return 0;
}
