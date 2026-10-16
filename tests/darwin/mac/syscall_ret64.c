// libc syscall wrappers return a full 64-bit -1 in x0 on failure (Go's runtime compares all 64 bits)
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/event.h>
#include <unistd.h>

typedef long (*kevent_l)(int, const struct kevent*, int, struct kevent*, int, const struct timespec*);
typedef long (*fcntl_l)(int, int, ...);

int main(void) {
    volatile kevent_l kv = (kevent_l)(void*)&kevent;
    volatile fcntl_l fc = (fcntl_l)(void*)&fcntl;
    struct kevent ev;
    struct timespec ts = {0, 0};
    errno = 0;
    long r = kv(-1, NULL, 0, &ev, 1, &ts);
    printf("kevent(-1) = %ld errno=%s\n", r, strerror(errno));
    int kq = kqueue();
    struct kevent ch;
    EV_SET(&ch, 12345, EVFILT_READ, EV_ADD, 0, 0, NULL);
    errno = 0;
    r = kv(kq, &ch, 1, NULL, 0, NULL);
    printf("kevent(bad fd change) = %ld errno=%s\n", r, strerror(errno));
    errno = 0;
    r = fc(-1, F_GETFL);
    printf("fcntl(-1) = %ld errno=%s\n", r, strerror(errno));
    r = fc(kq, F_GETFL);
    printf("fcntl(kq, F_GETFL) = %ld\n", r);
    close(kq);
    return 0;
}
