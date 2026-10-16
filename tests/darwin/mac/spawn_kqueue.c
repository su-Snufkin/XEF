// posix_spawn file actions / attributes and kqueue EVFILT_PROC (NOTE_EXIT|NOTE_EXITSTATUS) + EVFILT_TIMER.
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/event.h>
#include <sys/wait.h>
#include <unistd.h>
extern char **environ;

static int run(const char *script, int cloexec_default, int keep_fd, char *out, size_t cap) {
  int p[2]; pipe(p);
  posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
  posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
  posix_spawn_file_actions_adddup2(&fa, p[1], 1);
  posix_spawn_file_actions_adddup2(&fa, p[1], 2);
  posix_spawn_file_actions_addclose(&fa, p[0]);
  if (keep_fd >= 0) posix_spawn_file_actions_addinherit_np(&fa, keep_fd);
  posix_spawnattr_t at; posix_spawnattr_init(&at);
  sigset_t m; sigemptyset(&m); posix_spawnattr_setsigmask(&at, &m);
  sigset_t d; sigfillset(&d); posix_spawnattr_setsigdefault(&at, &d);
  posix_spawnattr_setflags(&at, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | (cloexec_default ? POSIX_SPAWN_CLOEXEC_DEFAULT : 0));
  pid_t pid;
  char *argv[] = {"sh", "-c", (char *)script, NULL};
  int e = posix_spawn(&pid, "/bin/sh", &fa, &at, argv, environ);
  posix_spawn_file_actions_destroy(&fa); posix_spawnattr_destroy(&at);
  close(p[1]);
  if (e) { close(p[0]); return -e; }
  int kq = kqueue();
  struct kevent ch; EV_SET(&ch, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT | NOTE_EXITSTATUS, 0, (void *)0x1234);
  if (kevent(kq, &ch, 1, NULL, 0, NULL) < 0) printf("kevent add: %s\n", strerror(errno));
  size_t n = 0; ssize_t r;
  while ((r = read(p[0], out + n, cap - 1 - n)) > 0) n += r;
  out[n] = 0; close(p[0]);
  struct kevent ev; struct timespec ts = {5, 0};
  int k = kevent(kq, NULL, 0, &ev, 1, &ts);
  printf("  kevent=%d ident_ok=%d filter=%d fflags=%#x eof=%d status=%#lx udata=%p\n", k, (pid_t)ev.ident == pid, ev.filter,
         ev.fflags, !!(ev.flags & EV_EOF), (long)ev.data, ev.udata);
  int st; waitpid(pid, &st, 0);
  close(kq);
  return st;
}

int main(void) {
  char buf[512];
  int st = run("echo out; echo err >&2; read x; echo read=$?; exit 7", 0, -1, buf, sizeof buf);
  printf("1: exited=%d code=%d out=[%s]\n", WIFEXITED(st), WEXITSTATUS(st), buf);
  int keep = open("/dev/null", O_RDONLY), drop = open("/dev/null", O_RDONLY);
  char script[200];
  snprintf(script, sizeof script, "(exec <&%d) 2>/dev/null && echo keep=open || echo keep=closed; (exec <&%d) 2>/dev/null && echo drop=open || echo drop=closed", keep, drop);
  st = run(script, 1, keep, buf, sizeof buf);
  printf("2: code=%d out=[%s]\n", WEXITSTATUS(st), buf);
  st = run("kill -TERM $$", 0, -1, buf, sizeof buf);
  printf("3: signaled=%d sig=%d\n", WIFSIGNALED(st), WTERMSIG(st));
  pid_t pid; char *argv[] = {"x", NULL};
  printf("4: missing=%d\n", posix_spawn(&pid, "/nonexistent/xef", NULL, NULL, argv, environ) == ENOENT);
  int kq = kqueue();
  struct kevent ch[2];
  EV_SET(&ch[0], 1, EVFILT_TIMER, EV_ADD | EV_ONESHOT, 0, 20, NULL);
  EV_SET(&ch[1], 2, EVFILT_TIMER, EV_ADD, NOTE_USECONDS, 5000, NULL);
  kevent(kq, ch, 2, NULL, 0, NULL);
  int got1 = 0, ticks = 0;
  while (!got1) {
    struct kevent ev[4]; int k = kevent(kq, NULL, 0, ev, 4, NULL);
    for (int i = 0; i < k; i++) { if (ev[i].ident == 1) got1 = 1; else ticks += (int)ev[i].data; }
  }
  printf("5: oneshot fired, periodic ticks>=2: %d\n", ticks >= 2);
  struct kevent del; EV_SET(&del, 1, EVFILT_TIMER, EV_DELETE, 0, 0, NULL);
  printf("6: delete fired oneshot: %d errno=%d\n", kevent(kq, &del, 1, NULL, 0, NULL), errno);
  return 0;
}
