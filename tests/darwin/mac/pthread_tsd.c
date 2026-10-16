// pthread keys: numbering, values in the TSD array behind TPIDRRO_EL0 (Go reads them there), destructors at
// thread exit (also for pthread_exit), pthread_exit's return value.
#include <pthread.h>
#include <stdio.h>
#include <stdint.h>
static pthread_key_t k1, k2;
static unsigned long *tsd(void) { unsigned long t; __asm__ volatile("mrs %0, tpidrro_el0" : "=r"(t)); return (unsigned long *)(t & ~7ul); }
static void d1(void *v) { printf("d1(%lu)\n", (unsigned long)(uintptr_t)v); }
static int d2n;
static void d2(void *v) { printf("d2(%lu)\n", (unsigned long)(uintptr_t)v); if (++d2n < 3) pthread_setspecific(k2, (void *)(uintptr_t)(100 + d2n)); }
static void *worker(void *arg) {
  pthread_setspecific(k1, (void *)11); pthread_setspecific(k2, (void *)22);
  printf("thread slot=%lu own=%d main-value-hidden=%d\n", tsd()[k1], tsd()[0] == (unsigned long)pthread_self(), pthread_getspecific(k1) == (void *)11);
  if (arg) pthread_exit((void *)77);
  return (void *)5;
}
int main(void) {
  pthread_key_create(&k1, d1); pthread_key_create(&k2, d2);
  printf("keys %lu %lu\n", (unsigned long)k1, (unsigned long)k2);
  pthread_setspecific(k1, (void *)1);
  printf("main slot=%lu get=%lu\n", tsd()[k1], (unsigned long)(uintptr_t)pthread_getspecific(k1));
  pthread_t t; void *r;
  pthread_create(&t, NULL, worker, NULL); pthread_join(t, &r); printf("ret=%lu\n", (unsigned long)(uintptr_t)r);
  d2n = 0;
  pthread_create(&t, NULL, worker, (void *)1); pthread_join(t, &r); printf("ret=%lu\n", (unsigned long)(uintptr_t)r);
  printf("main still=%lu\n", (unsigned long)(uintptr_t)pthread_getspecific(k1));
  pthread_key_delete(k1);
  pthread_key_t k3; pthread_key_create(&k3, NULL); printf("reuse=%d\n", k3 == k1);
  return 0;
}
