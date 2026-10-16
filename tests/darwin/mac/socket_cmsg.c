// sendmsg/recvmsg control messages (SCM_RIGHTS fd passing, several fds, too-small control buffer -> MSG_CTRUNC),
// MSG_TRUNC on a datagram socket, b64_ntop/b64_pton, sys_signame.
#include <fcntl.h>
#include <resolv.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>
static int send_fds(int s, int *fds, int n) {
  char data = 'x'; struct iovec iov = {&data, 1};
  char buf[CMSG_SPACE(sizeof(int) * 4)]; memset(buf, 0, sizeof buf);
  struct msghdr m = {0}; m.msg_iov = &iov; m.msg_iovlen = 1; m.msg_control = buf; m.msg_controllen = CMSG_SPACE(sizeof(int) * n);
  struct cmsghdr *c = CMSG_FIRSTHDR(&m); c->cmsg_level = SOL_SOCKET; c->cmsg_type = SCM_RIGHTS; c->cmsg_len = CMSG_LEN(sizeof(int) * n);
  memcpy(CMSG_DATA(c), fds, sizeof(int) * n);
  return (int)sendmsg(s, &m, 0);
}
int main(void) {
  int sv[2]; socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
  int p[2]; pipe(p);
  printf("send=%d\n", send_fds(sv[0], p, 2));
  char data; struct iovec iov = {&data, 1}; char buf[CMSG_SPACE(sizeof(int) * 4)];
  struct msghdr m = {0}; m.msg_iov = &iov; m.msg_iovlen = 1; m.msg_control = buf; m.msg_controllen = sizeof buf;
  ssize_t r = recvmsg(sv[1], &m, 0);
  struct cmsghdr *c = CMSG_FIRSTHDR(&m);
  printf("recv=%zd data=%c flags=%#x level_ok=%d type_ok=%d nfds=%zu\n", r, data, m.msg_flags, c && c->cmsg_level == SOL_SOCKET,
         c && c->cmsg_type == SCM_RIGHTS, c ? (c->cmsg_len - CMSG_LEN(0)) / sizeof(int) : 0);
  int got[2]; memcpy(got, CMSG_DATA(c), sizeof got);
  write(got[1], "pipe!", 5); char t[8] = {0}; read(p[0], t, 5); printf("passed write end works: %s\n", t);
  printf("next cmsg=%p\n", (void *)CMSG_NXTHDR(&m, c));
  send_fds(sv[0], p, 2);
  char small[CMSG_SPACE(0)]; m.msg_control = small; m.msg_controllen = sizeof small; m.msg_flags = 0;
  r = recvmsg(sv[1], &m, 0); printf("small ctl recv=%zd ctrunc=%d\n", r, !!(m.msg_flags & MSG_CTRUNC));
  int dg[2]; socketpair(AF_UNIX, SOCK_DGRAM, 0, dg); send(dg[0], "abcdef", 6, 0);
  char two[2]; struct iovec iv2 = {two, 2}; struct msghdr m2 = {0}; m2.msg_iov = &iv2; m2.msg_iovlen = 1;
  r = recvmsg(dg[1], &m2, 0); printf("dgram recv=%zd trunc=%d\n", r, !!(m2.msg_flags & MSG_TRUNC));
  char enc[64]; unsigned char dec[64];
  int n = b64_ntop((const unsigned char *)"hello xef", 9, enc, sizeof enc);
  int k = b64_pton(enc, dec, sizeof dec); dec[k > 0 ? k : 0] = 0;
  printf("b64 %d %s -> %d %s bad=%d\n", n, enc, k, dec, b64_pton("a$b", dec, sizeof dec));
  printf("signame %s %s %s\n", sys_signame[SIGINT], sys_signame[SIGWINCH], sys_signame[SIGUSR2]);
  return 0;
}
