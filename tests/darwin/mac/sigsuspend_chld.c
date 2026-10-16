// The nginx master loop: block signals, fork workers, sigsuspend() with an empty mask; SIGCHLD/SIGTERM/SIGALRM
// handlers run inside sigsuspend, which then returns -1/EINTR with the old mask restored; waitpid reaps.
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>
static volatile sig_atomic_t got_chld, got_term, got_alrm;
static void h(int s) { if (s == SIGCHLD) got_chld++; else if (s == SIGTERM) got_term++; else if (s == SIGALRM) got_alrm++; }
int main(void) {
  struct sigaction sa; memset(&sa, 0, sizeof sa); sa.sa_handler = h; sigemptyset(&sa.sa_mask);
  sigaction(SIGCHLD, &sa, NULL); sigaction(SIGTERM, &sa, NULL); sigaction(SIGALRM, &sa, NULL);
  sigset_t block, empty, cur; sigemptyset(&block); sigaddset(&block, SIGCHLD); sigaddset(&block, SIGTERM); sigaddset(&block, SIGALRM);
  sigprocmask(SIG_BLOCK, &block, NULL); sigemptyset(&empty);
  pid_t kids[2];
  for (int i = 0; i < 2; i++) if ((kids[i] = fork()) == 0) { sigprocmask(SIG_UNBLOCK, &block, NULL); pause(); _exit(3); }
  kill(getpid(), SIGTERM);   // pending while blocked
  int r = sigsuspend(&empty);
  sigprocmask(SIG_BLOCK, NULL, &cur);
  printf("sigsuspend=%d eintr=%d term=%d mask_restored=%d\n", r, errno == EINTR, got_term, sigismember(&cur, SIGCHLD));
  for (int i = 0; i < 2; i++) kill(kids[i], SIGKILL);
  int reaped = 0;
  while (reaped < 2) {
    sigsuspend(&empty);
    int st; pid_t p;
    while ((p = waitpid(-1, &st, WNOHANG)) > 0) reaped++;
  }
  printf("reaped=%d chld_seen=%d\n", reaped, got_chld > 0);
  struct itimerval it = {{0, 0}, {0, 50000}}; setitimer(ITIMER_REAL, &it, NULL);
  while (!got_alrm) sigsuspend(&empty);
  printf("alarm=%d\n", got_alrm);
  return 0;
}
