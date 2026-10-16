// a signal handler that changes errno does not change the errno seen by the interrupted code
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t hits;
static void handler(int sig) {
    (void)sig;
    close(-1);           // EBADF inside the handler
    hits++;
}

int main(void) {
    signal(SIGUSR1, handler);
    errno = EINTR;
    kill(getpid(), SIGUSR1);
    int e1 = errno;
    errno = EAGAIN;
    raise(SIGUSR1);
    int e2 = errno;
    printf("hits=%d after kill errno=%s, after raise errno=%s\n", (int)hits, strerror(e1), strerror(e2));
    return 0;
}
