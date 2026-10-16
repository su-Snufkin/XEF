// Darwin sendfile(fd, s, offset, *len, hdtr, flags) with headers/trailers; AF_UNIX bind/connect without a path
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <unistd.h>

int main(void) {
    const char* p = "/tmp/xef_sendfile.txt";
    int fd = open(p, O_CREAT | O_TRUNC | O_RDWR, 0644);
    write(fd, "0123456789abcdefghij", 20);
    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    off_t len = 5;
    int r = sendfile(fd, sv[0], 3, &len, NULL, 0);
    char buf[64] = {0};
    ssize_t n = read(sv[1], buf, sizeof buf - 1);
    printf("count 5 from 3: r=%d len=%lld got '%.*s'\n", r, (long long)len, (int)n, buf);
    len = 0;
    r = sendfile(fd, sv[0], 15, &len, NULL, 0);
    n = read(sv[1], buf, sizeof buf - 1);
    printf("to EOF from 15: r=%d len=%lld got '%.*s'\n", r, (long long)len, (int)n, buf);
    struct iovec h = {"HDR:", 4}, t = {":TRL", 4};
    struct sf_hdtr ht = {&h, 1, &t, 1};
    len = 0;
    r = sendfile(fd, sv[0], 18, &len, &ht, 0);
    n = read(sv[1], buf, sizeof buf - 1);
    printf("hdtr: r=%d len=%lld got '%.*s'\n", r, (long long)len, (int)n, buf);
    errno = 0;
    printf("not a socket: %d %s\n", sendfile(fd, fd, 0, &len, NULL, 0), strerror(errno));
    close(fd); unlink(p);

    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    errno = 0;
    printf("bind empty: %d %s\n", bind(s, (struct sockaddr*)&a, sizeof a), strerror(errno));
    memcpy(a.sun_path, "\0abc", 4);
    errno = 0;
    printf("connect leading NUL: %d %s\n", connect(s, (struct sockaddr*)&a, sizeof a), strerror(errno));
    return 0;
}
