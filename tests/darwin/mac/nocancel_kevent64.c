// $NOCANCEL entry points (Zig/Bun call them directly) take Darwin flags and a variadic mode; kevent64 with
// KEVENT_FLAG_ERROR_EVENTS reports only failed changes; thread_switch
#include <errno.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <mach/thread_switch.h>
#include <stdio.h>
#include <string.h>
#include <sys/event.h>
#include <sys/stat.h>
#include <unistd.h>

int openat_nc(int, const char*, int, ...) __asm("_openat$NOCANCEL");
int open_nc(const char*, int, ...) __asm("_open$NOCANCEL");
ssize_t read_nc(int, void*, size_t) __asm("_read$NOCANCEL");
ssize_t write_nc(int, const void*, size_t) __asm("_write$NOCANCEL");
int close_nc(int) __asm("_close$NOCANCEL");

int main(void) {
    const char* p = "/tmp/xef_nocancel_test.txt";
    unlink(p);
    int fd = openat_nc(AT_FDCWD, p, O_CREAT | O_TRUNC | O_RDWR | O_CLOEXEC, 0640);
    printf("openat$NOCANCEL create: ok=%d cloexec=%d\n", fd >= 0, fd >= 0 && (fcntl(fd, F_GETFD) & FD_CLOEXEC));
    printf("write$NOCANCEL: %zd\n", write_nc(fd, "hello", 5));
    close_nc(fd);
    struct stat st;
    stat(p, &st);
    printf("mode %o size %lld\n", st.st_mode & 0777, (long long)st.st_size);
    fd = open_nc(p, O_RDONLY);
    char b[16] = {0};
    printf("open$NOCANCEL+read: %zd '%s'\n", read_nc(fd, b, sizeof b - 1), b);
    close(fd);
    errno = 0;
    printf("O_EXCL on existing: %d %s\n", openat_nc(AT_FDCWD, p, O_CREAT | O_EXCL | O_WRONLY, 0600), strerror(errno));
    unlink(p);

    int kq = kqueue(), pp[2];
    pipe(pp);
    struct kevent64_s ch[2], ev[2];
    EV_SET64(&ch[0], pp[0], EVFILT_READ, EV_ADD, 0, 0, 1, 0, 0);
    EV_SET64(&ch[1], 9999, EVFILT_READ, EV_ADD, 0, 0, 2, 0, 0);
    int n = kevent64(kq, ch, 2, ev, 2, KEVENT_FLAG_ERROR_EVENTS, NULL);
    printf("error events: n=%d", n);
    for (int i = 0; i < n; i++) printf(" [ident %llu error %d data %lld]", (unsigned long long)ev[i].ident, !!(ev[i].flags & EV_ERROR), (long long)ev[i].data);
    printf("\n");
    write(pp[1], "x", 1);
    n = kevent64(kq, NULL, 0, ev, 2, KEVENT_FLAG_IMMEDIATE, NULL);
    printf("immediate: n=%d ident_ok=%d udata=%llu\n", n, n >= 1 && ev[0].ident == (uint64_t)pp[0], n >= 1 ? (unsigned long long)ev[0].udata : 0ull);
    printf("thread_switch none %d depress %d wait %d bad %d\n", thread_switch(MACH_PORT_NULL, SWITCH_OPTION_NONE, 0),
           thread_switch(MACH_PORT_NULL, SWITCH_OPTION_DEPRESS, 1), thread_switch(MACH_PORT_NULL, SWITCH_OPTION_WAIT, 5),
           thread_switch(MACH_PORT_NULL, 99, 0));
    return 0;
}
