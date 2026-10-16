// mach_port_construct + kevent64 EVFILT_MACHPORT: the port is readable while a message waits (as libdispatch/bun use)
#include <mach/mach.h>
#include <stdio.h>
#include <string.h>
#include <sys/event.h>
#include <unistd.h>

int main(void) {
    mach_port_options_t opt;
    memset(&opt, 0, sizeof opt);
    opt.flags = MPO_INSERT_SEND_RIGHT | MPO_QLIMIT;
    opt.mpl.mpl_qlimit = 1;
    mach_port_t port = MACH_PORT_NULL;
    kern_return_t kr = mach_port_construct(mach_task_self(), &opt, 0, &port);
    printf("construct kr=%d port!=0 %d\n", kr, port != MACH_PORT_NULL);
    int kq = kqueue();
    struct kevent64_s ch, ev;
    EV_SET64(&ch, port, EVFILT_MACHPORT, EV_ADD, 0, 0, 0x77, 0, 0);
    printf("register: %d\n", kevent64(kq, &ch, 1, NULL, 0, 0, NULL));
    printf("poll empty: %d\n", kevent64(kq, NULL, 0, &ev, 1, KEVENT_FLAG_IMMEDIATE, NULL));
    mach_msg_header_t m;
    memset(&m, 0, sizeof m);
    m.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_MAKE_SEND, 0);
    m.msgh_size = sizeof m;
    m.msgh_remote_port = port;
    m.msgh_id = 4242;
    kr = mach_msg(&m, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof m, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
    printf("send kr=%d\n", kr);
    int n = kevent64(kq, NULL, 0, &ev, 1, KEVENT_FLAG_IMMEDIATE, NULL);
    printf("poll after send: n=%d filter_machport=%d ident_ok=%d udata=%#llx\n", n, n == 1 && ev.filter == EVFILT_MACHPORT,
           n == 1 && ev.ident == port, n == 1 ? (unsigned long long)ev.udata : 0ull);
    n = kevent64(kq, NULL, 0, &ev, 1, KEVENT_FLAG_IMMEDIATE, NULL);
    printf("still pending (level): n=%d\n", n);
    struct { mach_msg_header_t h; mach_msg_trailer_t t; } r;
    kr = mach_msg(&r.h, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof r, port, 0, MACH_PORT_NULL);
    printf("receive kr=%d id=%d\n", kr, r.h.msgh_id);
    printf("poll after receive: %d\n", kevent64(kq, NULL, 0, &ev, 1, KEVENT_FLAG_IMMEDIATE, NULL));
    printf("destruct: %d\n", mach_port_destruct(mach_task_self(), port, -1, 0));
    close(kq);
    return 0;
}
