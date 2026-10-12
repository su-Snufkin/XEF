#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#define NT 8
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
static long shared = 0;
static atomic_long acount = 0;
static int ready = 0;
static __thread int tls_val;
static void* worker(void* arg) {
    long id = (long)arg;
    tls_val = (int)id * 100;
    for (int i = 0; i < 20000; i++) {
        pthread_mutex_lock(&mu);
        shared += id;
        pthread_mutex_unlock(&mu);
        atomic_fetch_add(&acount, 1);
    }
    pthread_mutex_lock(&mu);
    ready++;
    pthread_cond_broadcast(&cv);
    pthread_mutex_unlock(&mu);
    char* buf = malloc(1000 + id);
    memset(buf, (int)id, 1000);
    long s = 0;
    for (int i = 0; i < 1000; i++) s += buf[i];
    free(buf);
    return (void*)(s + tls_val);
}
int main(void) {
    pthread_t th[NT];
    for (long i = 0; i < NT; i++) pthread_create(&th[i], NULL, worker, (void*)i);
    pthread_mutex_lock(&mu);
    while (ready < NT) pthread_cond_wait(&cv, &mu);
    pthread_mutex_unlock(&mu);
    long total = 0;
    for (int i = 0; i < NT; i++) { void* r; pthread_join(th[i], &r); total += (long)r; }
    printf("shared=%ld atomic=%ld total=%ld\n", shared, (long)acount, total);
    return 0;
}
