// System V semaphores/shared memory with Darwin command numbers and IPC_STAT layouts, kqueue EVFILT_SIGNAL counting,
// pthread_is_threaded_np before/after the first thread, system() and popen() through /bin/sh.
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <sys/shm.h>
#include <sys/wait.h>
#include <unistd.h>
union semun_ { int val; struct semid_ds *buf; unsigned short *array; };
static void *nop(void *a) { return a; }
int main(void) {
  int id = semget(IPC_PRIVATE, 4, IPC_CREAT | 0600);
  union semun_ a; a.val = 536;
  printf("semget ok=%d setval=%d getval=%d\n", id >= 0, semctl(id, 2, SETVAL, a), semctl(id, 2, GETVAL));
  unsigned short all[4] = {1, 2, 3, 4}; a.array = all; semctl(id, 0, SETALL, a);
  unsigned short got[4] = {0}; a.array = got; semctl(id, 0, GETALL, a);
  printf("getall %d%d%d%d pid_ok=%d ncnt=%d\n", got[0], got[1], got[2], got[3], semctl(id, 0, GETPID) == getpid(), semctl(id, 0, GETNCNT));
  struct sembuf op = {1, -2, IPC_NOWAIT}; printf("semop=%d val=%d\n", semop(id, &op, 1), semctl(id, 1, GETVAL));
  struct semid_ds ds; a.buf = &ds; printf("ipc_stat=%d nsems=%d mode=%o\n", semctl(id, 0, IPC_STAT, a), ds.sem_nsems, ds.sem_perm.mode & 0777);
  printf("rmid=%d\n", semctl(id, 0, IPC_RMID));
  int sid = shmget(IPC_PRIVATE, 65536, IPC_CREAT | 0600); char *p = shmat(sid, NULL, 0);
  strcpy(p, "shared"); struct shmid_ds sd; shmctl(sid, IPC_STAT, &sd);
  printf("shm %s segsz=%zu nattch=%d cpid_ok=%d\n", p, (size_t)sd.shm_segsz, (int)sd.shm_nattch, sd.shm_cpid == getpid());
  shmdt(p); shmctl(sid, IPC_STAT, &sd); printf("after shmdt nattch=%d rmid=%d\n", (int)sd.shm_nattch, shmctl(sid, IPC_RMID, NULL));
  signal(SIGUSR1, SIG_DFL); signal(SIGUSR1, (void (*)(int))nop);
  int kq = kqueue(); struct kevent ev; EV_SET(&ev, SIGUSR1, EVFILT_SIGNAL, EV_ADD, 0, 0, NULL);
  printf("kevent add=%d\n", kevent(kq, &ev, 1, NULL, 0, NULL));
  raise(SIGUSR1); raise(SIGUSR1);
  struct timespec ts = {0, 200000000}; int n = kevent(kq, NULL, 0, &ev, 1, &ts);
  printf("raise (thread-directed) events=%d\n", n);
  kill(getpid(), SIGUSR1); kill(getpid(), SIGUSR1);
  struct timespec ts2 = {2, 0}; n = kevent(kq, NULL, 0, &ev, 1, &ts2);
  printf("kill events=%d ident=%lu filter=%d count=%ld\n", n, (unsigned long)ev.ident, ev.filter, (long)ev.data);
  printf("threaded before=%d ", pthread_is_threaded_np()); pthread_t t; pthread_create(&t, NULL, nop, NULL); pthread_join(t, NULL);
  printf("after=%d\n", pthread_is_threaded_np());
  fflush(stdout);
  int st = system("echo from-system; exit 5"); printf("system exit=%d avail=%d\n", WEXITSTATUS(st), system(NULL) != 0);
  FILE *f = popen("echo a; echo b", "r"); char buf[32]; int lines = 0; while (fgets(buf, sizeof buf, f)) lines++;
  printf("popen lines=%d pclose=%d\n", lines, pclose(f));
  FILE *w = popen("cat > /dev/null; exit 3", "w"); fputs("data\n", w); int pw = pclose(w); printf("popen w pclose exit=%d\n", WEXITSTATUS(pw));
  return 0;
}
