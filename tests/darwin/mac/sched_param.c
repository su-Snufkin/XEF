// pthread scheduling parameters with Darwin's policy numbers and priority range
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>

static void* thr(void* a) {
    int pol; struct sched_param p;
    int r = pthread_getschedparam(pthread_self(), &pol, &p);
    printf("thread: r=%d policy=%d prio=%d\n", r, pol, p.sched_priority);
    return a;
}

int main(void) {
    printf("SCHED_OTHER=%d RR=%d FIFO=%d sizeof(sched_param)=%zu\n", SCHED_OTHER, SCHED_RR, SCHED_FIFO, sizeof(struct sched_param));
    printf("other min %d max %d, fifo min %d max %d, bad %d\n", sched_get_priority_min(SCHED_OTHER), sched_get_priority_max(SCHED_OTHER),
           sched_get_priority_min(SCHED_FIFO), sched_get_priority_max(SCHED_FIFO), sched_get_priority_min(99));
    int pol; struct sched_param p;
    int r = pthread_getschedparam(pthread_self(), &pol, &p);
    printf("main: r=%d policy=%d prio=%d\n", r, pol, p.sched_priority);
    p.sched_priority = 31;
    printf("set other 31: %d\n", pthread_setschedparam(pthread_self(), SCHED_OTHER, &p));
    printf("set bad policy: %d\n", pthread_setschedparam(pthread_self(), 77, &p));
    pthread_attr_t at;
    pthread_attr_init(&at);
    pthread_attr_getschedpolicy(&at, &pol);
    pthread_attr_getschedparam(&at, &p);
    printf("attr default: policy=%d prio=%d\n", pol, p.sched_priority);
    pthread_t t;
    pthread_create(&t, &at, thr, NULL);
    pthread_join(t, NULL);
    return 0;
}
