// fork + pthread_atfork order, exec family (execl/execlp/execle/execv/execvp/execvP), environ after setenv, memset_s.
#define __STDC_WANT_LIB_EXT1__ 1
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
extern char **environ;
static void pa(void) { printf("prepare A\n"); fflush(stdout); }
static void pb(void) { printf("prepare B\n"); fflush(stdout); }
static void parent_a(void) { printf("parent A\n"); }
static void parent_b(void) { printf("parent B\n"); }
static void child_a(void) { printf("child A\n"); }
static void child_b(void) { printf("child B\n"); }
static void *spin(void *a) { (void)a; for (;;) { void *p = malloc(64); free(p); } return NULL; }

static int run(int how) {
  fflush(stdout);
  pid_t p = fork();
  if (p == 0) {
    char *av[] = {"sh", "-c", "echo argv0=$0 v=$XEF_V; exit 3", NULL};
    char *env[] = {"XEF_V=from_execle", NULL};
    switch (how) {
      case 0: execl("/bin/sh", "sh", "-c", "echo execl $XEF_V; exit 3", (char *)NULL); break;
      case 1: execlp("sh", "sh", "-c", "echo execlp; exit 3", (char *)NULL); break;
      case 2: execle("/bin/sh", "sh", "-c", "echo execle $XEF_V; exit 3", (char *)NULL, env); break;
      case 3: execv("/bin/sh", av); break;
      case 4: execvp("sh", av); break;
      case 5: execvP("sh", "/nonexistent:/bin", av); break;
      case 6: execv("/nonexistent/prog", av); printf("execv failed errno=%d\n", errno); fflush(stdout); _exit(9);
    }
    _exit(99);
  }
  int st; waitpid(p, &st, 0);
  return WEXITSTATUS(st);
}

int main(void) {
  pthread_atfork(pa, parent_a, child_a);
  pthread_atfork(pb, parent_b, child_b);
  pid_t p = fork();
  if (p == 0) { printf("in child\n"); fflush(stdout); _exit(5); }
  int st; waitpid(p, &st, 0);
  printf("child exit=%d\n", WEXITSTATUS(st));
  pthread_t t; pthread_create(&t, NULL, spin, NULL);   // fork while another thread hammers malloc
  for (int i = 0; i < 20; i++) {
    pid_t q = fork();
    if (q == 0) { void *m = malloc(100); free(m); _exit(0); }
    waitpid(q, &st, 0);
  }
  printf("20 forks with a busy thread ok\n");
  setenv("XEF_V", "set_by_setenv", 1);
  for (int how = 0; how <= 6; how++) printf("how=%d rc=%d\n", how, run(how));
  char buf[8] = "abcdefg";
  printf("memset_s=%d buf=%s overflow=%d null=%d\n", memset_s(buf, 8, 'x', 3), buf, memset_s(buf, 2, 'y', 5), memset_s(NULL, 1, 0, 1));
  return 0;
}
