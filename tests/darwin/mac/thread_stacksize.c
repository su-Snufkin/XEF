// pthread_attr_setstacksize is honored: deep recursion on a 64 MB thread stack
#include <pthread.h>
#include <stdio.h>
#include <string.h>

static int depth(int n) {
    volatile char pad[1024];
    memset((char*)pad, n & 0xff, sizeof pad);
    return n == 0 ? pad[3] : depth(n - 1) + (pad[5] & 1);
}
static void* run(void* a) { (void)a; return (void*)(long)depth(40000); }   // ~40 MB of frames

int main(void) {
    pthread_attr_t at;
    pthread_attr_init(&at);
    pthread_attr_setstacksize(&at, 64 << 20);
    size_t got = 0;
    pthread_attr_getstacksize(&at, &got);
    pthread_t t;
    pthread_create(&t, &at, run, NULL);
    void* r;
    pthread_join(t, &r);
    printf("attr stacksize %zu MB, recursion result %ld\n", got >> 20, (long)r);
    return 0;
}
