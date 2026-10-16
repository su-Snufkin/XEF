// dlsym(RTLD_DEFAULT) finds libSystem functions, and not glibc-only ones macOS does not have
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    const char* names[] = {"pthread_condattr_setclock", "pipe2", "dup3", "accept4", "epoll_create", "eventfd",
                           "getauxval", "gettid", "malloc_usable_size", "memfd_create", "open64",
                           "printf", "pthread_create", "kqueue", "malloc_size", "pthread_threadid_np"};
    for (unsigned i = 0; i < sizeof names / sizeof *names; i++)
        printf("%-26s %s\n", names[i], dlsym(RTLD_DEFAULT, names[i]) ? "found" : "absent");
    // the ones macOS does have take Darwin flags
    int (*p2)(int*, int) = (int (*)(int*, int))dlsym(RTLD_DEFAULT, "pipe2");
    int (*d3)(int, int, int) = (int (*)(int, int, int))dlsym(RTLD_DEFAULT, "dup3");
    int fds[2];
    if (p2 && p2(fds, O_CLOEXEC | O_NONBLOCK) == 0)
        printf("pipe2: cloexec %d nonblock %d\n", (fcntl(fds[0], F_GETFD) & FD_CLOEXEC) != 0, (fcntl(fds[1], F_GETFL) & O_NONBLOCK) != 0);
    if (d3) {
        int r = d3(fds[0], 20, O_CLOEXEC);
        printf("dup3: %d cloexec %d\n", r, (fcntl(20, F_GETFD) & FD_CLOEXEC) != 0);
        errno = 0;
        printf("dup3 bad flags: %d %s\n", d3(fds[0], 21, O_APPEND), strerror(errno));
    }
    return 0;
}
