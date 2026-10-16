// a duplicated kqueue descriptor (mio's Selector::try_clone: fcntl F_DUPFD_CLOEXEC) names the same kqueue
#include <fcntl.h>
#include <stdio.h>
#include <sys/event.h>
#include <unistd.h>

int main(void) {
    int kq = kqueue();
    int kq2 = fcntl(kq, F_DUPFD_CLOEXEC, 0), kq3 = dup(kq);
    int p[2];
    pipe(p);
    struct kevent ch, ev;
    EV_SET(&ch, p[0], EVFILT_READ, EV_ADD, 0, 0, (void*)0x1234);
    printf("register via dup: %d\n", kevent(kq2, &ch, 1, NULL, 0, NULL));
    write(p[1], "x", 1);
    struct timespec ts = {1, 0};
    int n = kevent(kq, NULL, 0, &ev, 1, &ts);
    printf("wait via original: n=%d ident_ok=%d udata=%p\n", n, n == 1 && (int)ev.ident == p[0], ev.udata);
    close(kq);
    n = kevent(kq3, NULL, 0, &ev, 1, &ts);
    printf("after closing the original, wait via dup: n=%d\n", n);
    EV_SET(&ch, 1234, EVFILT_USER, EV_ADD | EV_CLEAR, 0, 0, NULL);
    kevent(kq3, &ch, 1, NULL, 0, NULL);
    int kq4 = kqueue();   // may reuse the closed number
    EV_SET(&ch, 1234, EVFILT_USER, 0, NOTE_TRIGGER, 0, NULL);
    printf("trigger via dup: %d\n", kevent(kq2, &ch, 1, NULL, 0, NULL));
    n = kevent(kq3, NULL, 0, &ev, 1, &ts);
    printf("user event via other dup: n=%d filter_user=%d\n", n, n == 1 && ev.filter == EVFILT_USER);
    struct timespec z = {0, 0};
    printf("new kqueue is empty: %d\n", kevent(kq4, NULL, 0, &ev, 1, &z));
    return 0;
}
