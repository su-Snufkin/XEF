// pthread_setname_np(name) names the calling thread (up to 63 bytes, unlike Linux's 15); pthread_getname_np of
// another thread; pthread_threadid_np changes in a forked child
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile int ready, done_flag;
static void* worker(void* a) {
    (void)a;
    pthread_setname_np("worker-with-a-rather-long-name-of-40-chars");
    ready = 1;
    while (!done_flag) usleep(1000);
    return NULL;
}

int main(void) {
    char buf[128];
    pthread_getname_np(pthread_self(), buf, sizeof buf);
    printf("initial main name: '%s'\n", buf);
    printf("set main: %d\n", pthread_setname_np("main-thread"));
    pthread_getname_np(pthread_self(), buf, sizeof buf);
    printf("main name: '%s'\n", buf);
    char longname[80]; memset(longname, 'x', 79); longname[79] = 0;
    int r = pthread_setname_np(longname);
    pthread_getname_np(pthread_self(), buf, sizeof buf);
    printf("set 79 chars: %d, stored length %zu\n", r, strlen(buf));
    pthread_t t;
    pthread_create(&t, NULL, worker, NULL);
    while (!ready) usleep(1000);
    pthread_getname_np(t, buf, sizeof buf);
    printf("worker name: '%s'\n", buf);
    pthread_getname_np(t, buf, 8);
    printf("worker name in 8 bytes: '%s'\n", buf);
    done_flag = 1;
    pthread_join(t, NULL);
    uint64_t a, b;
    pthread_threadid_np(NULL, &a);
    int p[2]; pipe(p);
    pid_t pid = fork();
    if (pid == 0) { pthread_threadid_np(NULL, &b); write(p[1], &b, 8); _exit(0); }
    read(p[0], &b, 8); waitpid(pid, NULL, 0);
    printf("child thread id differs: %d\n", a != b);
    return 0;
}
