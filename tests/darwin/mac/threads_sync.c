#include <stdio.h>
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdatomic.h>
static pthread_mutex_t mu=PTHREAD_MUTEX_INITIALIZER; static pthread_cond_t cv=PTHREAD_COND_INITIALIZER;
static int counter=0, ready=0; static atomic_int ac;
static __thread int tl=5;
static void* worker(void*a){ long id=(long)a; tl+=id; for(int i=0;i<1000;i++){pthread_mutex_lock(&mu);counter++;pthread_mutex_unlock(&mu);atomic_fetch_add(&ac,1);} 
  pthread_mutex_lock(&mu); ready++; pthread_cond_signal(&cv); pthread_mutex_unlock(&mu); return (void*)(long)tl; }
static pthread_once_t once=PTHREAD_ONCE_INIT; static void init(void){ puts("once"); }
int main(void){ pthread_t t[4]; for(long i=0;i<4;i++) pthread_create(&t[i],0,worker,(void*)i);
  pthread_mutex_lock(&mu); while(ready<4) pthread_cond_wait(&cv,&mu); pthread_mutex_unlock(&mu);
  long sum=0; for(int i=0;i<4;i++){void*r; pthread_join(t[i],&r); sum+=(long)r;} 
  pthread_once(&once,init); pthread_once(&once,init);
  printf("counter=%d atomic=%d tlsum=%ld main_tl=%d\n",counter,atomic_load(&ac),sum,tl);
  pthread_key_t k; pthread_key_create(&k,0); pthread_setspecific(k,(void*)7); printf("key=%ld\n",(long)pthread_getspecific(k));
  usleep(1000); printf("done\n"); return 0; }
