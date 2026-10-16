// Named POSIX semaphores: O_CREAT|O_EXCL (Darwin values), SEM_FAILED, cross-process post/wait, trywait EAGAIN,
// sem_init unsupported on macOS (ENOSYS).
#include <errno.h>
#include <fcntl.h>
#include <semaphore.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>
int main(void) {
  char name[64]; snprintf(name, sizeof name, "/xef-sem-%d", getpid());
  sem_t *s = sem_open(name, O_CREAT | O_EXCL, 0600, 0);
  printf("open ok=%d\n", s != SEM_FAILED);
  sem_t *again = sem_open(name, O_CREAT | O_EXCL, 0600, 0);
  printf("excl again failed=%d eexist=%d\n", again == SEM_FAILED, errno == EEXIST);
  errno = 0; printf("trywait=%d eagain=%d\n", sem_trywait(s), errno == EAGAIN);
  pid_t p = fork();
  if (p == 0) { sem_t *c = sem_open(name, 0); usleep(50000); sem_post(c); sem_post(c); _exit(0); }
  printf("wait=%d ", sem_wait(s)); printf("wait2=%d\n", sem_wait(s));
  waitpid(p, NULL, 0);
  printf("close=%d unlink=%d missing=%d\n", sem_close(s), sem_unlink(name), sem_open(name, 0) == SEM_FAILED);
  sem_t u; errno = 0; printf("sem_init=%d enosys=%d\n", sem_init(&u, 0, 1), errno == ENOSYS);
  return 0;
}
