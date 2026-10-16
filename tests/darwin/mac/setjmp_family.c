// setjmp/longjmp, _setjmp/_longjmp, sigsetjmp/siglongjmp: callee-saved registers survive, val 0 -> 1, the signal mask is
// restored by longjmp/siglongjmp(savemask) and not by _longjmp, longjmp out of a signal handler, nested frames.
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
static jmp_buf jb;
static sigjmp_buf sjb;
static volatile int depth;
static void deep(int n) { volatile char pad[256]; memset((char *)pad, n, sizeof pad); if (n == 0) longjmp(jb, 0); deep(n - 1); }
static void on_usr1(int s) { (void)s; siglongjmp(sjb, 42); }
static int blocked(int sig) { sigset_t cur; sigprocmask(SIG_BLOCK, NULL, &cur); return sigismember(&cur, sig); }
int main(void) {
  volatile double d = 1.5; register long keep = 12345;
  int r = setjmp(jb);
  if (r == 0) { d = 2.5; deep(50); }
  printf("setjmp returned %d d=%.1f keep=%ld\n", r, d, keep);
  sigset_t m; sigemptyset(&m); sigaddset(&m, SIGUSR2);
  r = setjmp(jb);
  if (r == 0) { sigprocmask(SIG_BLOCK, &m, NULL); printf("blocked before longjmp=%d\n", blocked(SIGUSR2)); longjmp(jb, 7); }
  printf("longjmp val=%d mask restored (unblocked)=%d\n", r, !blocked(SIGUSR2));
  r = _setjmp(jb);
  if (r == 0) { sigprocmask(SIG_BLOCK, &m, NULL); _longjmp(jb, 3); }
  printf("_longjmp val=%d mask kept (blocked)=%d\n", r, blocked(SIGUSR2));
  sigprocmask(SIG_UNBLOCK, &m, NULL);
  signal(SIGUSR1, on_usr1);
  r = sigsetjmp(sjb, 1);
  if (r == 0) { raise(SIGUSR1); printf("not reached\n"); }
  printf("siglongjmp from handler val=%d usr1 unblocked=%d\n", r, !blocked(SIGUSR1));
  r = sigsetjmp(sjb, 0);
  if (r == 0) { siglongjmp(sjb, 0); }
  printf("sigsetjmp(0) val=%d\n", r);
  int count = 0;
  for (int i = 0; i < 1000; i++) if (setjmp(jb) == 0) { count++; longjmp(jb, 1); }
  printf("loop %d\n", count);
  return 0;
}
