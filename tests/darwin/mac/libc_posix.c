#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/select.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <poll.h>
#include <fcntl.h>
#include <errno.h>
#include <pthread.h>
#include <time.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <sys/resource.h>
extern char **environ;
static volatile int got_usr1 = 0, got_alrm = 0;
static void on_usr1(int s) { got_usr1 = s; }
static void on_alrm(int s) { got_alrm = s; }
static void *echo_server(void *arg) {
  int ls = *(int *)arg; int c = accept(ls, NULL, NULL); char buf[64]; ssize_t n = read(c, buf, sizeof buf);
  write(c, buf, n); close(c); return NULL; }
int main(void) {
  setvbuf(stdout, NULL, _IONBF, 0);
  signal(SIGUSR1, on_usr1); kill(getpid(), SIGUSR1); usleep(1000); printf("usr1=%d\n", got_usr1);
  struct sigaction sa; memset(&sa, 0, sizeof sa); sa.sa_handler = on_alrm; sigemptyset(&sa.sa_mask); sigaction(SIGALRM, &sa, NULL);
  alarm(1); pause(); printf("alrm=%d\n", got_alrm);
  signal(SIGPIPE, SIG_IGN);
  int ls = socket(AF_INET, SOCK_STREAM, 0); int one = 1; setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  struct sockaddr_in a; memset(&a, 0, sizeof a); a.sin_len = sizeof a; a.sin_family = AF_INET; a.sin_addr.s_addr = htonl(INADDR_LOOPBACK); a.sin_port = 0;
  printf("bind=%d\n", bind(ls, (struct sockaddr *)&a, sizeof a)); listen(ls, 1);
  socklen_t al = sizeof a; getsockname(ls, (struct sockaddr *)&a, &al); printf("port>0=%d family=%d\n", ntohs(a.sin_port) > 0, a.sin_family);
  pthread_t t; pthread_create(&t, NULL, echo_server, &ls);
  int cs = socket(AF_INET, SOCK_STREAM, 0); printf("connect=%d\n", connect(cs, (struct sockaddr *)&a, sizeof a));
  write(cs, "ping", 4); char rb[16] = {0}; ssize_t n = read(cs, rb, sizeof rb); printf("echo=%.*s\n", (int)n, rb); close(cs); pthread_join(t, NULL);
  int sv[2]; socketpair(AF_UNIX, SOCK_STREAM, 0, sv); write(sv[0], "xy", 2); struct pollfd pf = {sv[1], POLLIN, 0}; printf("poll=%d\n", poll(&pf, 1, 100));
  fd_set rs; FD_ZERO(&rs); FD_SET(sv[1], &rs); struct timeval tv = {0, 1000}; printf("select=%d\n", select(sv[1] + 1, &rs, NULL, NULL, &tv));
  int p[2]; pipe(p); pid_t pid = fork();
  if (pid == 0) { close(p[0]); write(p[1], "child", 5); _exit(7); }
  close(p[1]); char cb[16] = {0}; read(p[0], cb, 15); int st; waitpid(pid, &st, 0); printf("child=%s exit=%d\n", cb, WEXITSTATUS(st));
  pid_t sp; char *args[] = {"/bin/echo", "spawned", NULL}; int r = posix_spawn(&sp, "/bin/echo", NULL, NULL, args, environ); waitpid(sp, &st, 0); printf("spawn=%d exit=%d\n", r, WEXITSTATUS(st));
  FILE *f = popen("echo popen-output", "r"); char pb[64] = {0}; fgets(pb, 64, f); pclose(f); printf("popen=%s", pb);
  { int sr = system("exit 3"); printf("system=%d\n", WEXITSTATUS(sr)); }
  struct utsname u; uname(&u); printf("uname=%s %s\n", u.sysname, u.machine);
  setenv("XEF_T", "val", 1); printf("env=%s\n", getenv("XEF_T"));
  struct addrinfo hints, *res; memset(&hints, 0, sizeof hints); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM;
  int gr = getaddrinfo("127.0.0.1", "80", &hints, &res); printf("gai=%d port=%d\n", gr, gr == 0 ? ntohs(((struct sockaddr_in *)res->ai_addr)->sin_port) : -1);
  char ip[32]; struct sockaddr_in *ra = (struct sockaddr_in *)res->ai_addr; struct in_addr ia = ra->sin_addr; inet_ntop(AF_INET, &ia, ip, sizeof ip); printf("ip=%s\n", ip);
  struct rlimit rl; getrlimit(RLIMIT_NOFILE, &rl); printf("nofile>0=%d\n", rl.rlim_cur > 0);
  struct stat sb; printf("stat=%d dir=%d\n", stat("/tmp", &sb), S_ISDIR(sb.st_mode));
  time_t now = time(NULL); struct tm *lt = localtime(&now); printf("year>=2026=%d\n", lt->tm_year + 1900 >= 2026);
  return 0; }
