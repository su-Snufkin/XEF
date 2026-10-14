// Many short-lived threads, created in parallel batches: exited threads' contexts must be reused
// (XEF leaked ~0.5 MB of RSS and several mappings per thread).
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static long rss_kb(void) {
    FILE* f = fopen("/proc/self/status", "r");
    char l[256];
    long v = -1;
    while (f && fgets(l, sizeof l, f))
        if (!strncmp(l, "VmRSS:", 6)) v = atol(l + 6);
    if (f) fclose(f);
    return v;
}

static void* work(void* a) {
    long x = (long)a, s = 0;
    for (long i = 0; i < 200; i++) s += (x ^ i) * 3;
    return (void*)s;
}

int main(void) {
    enum { kBatch = 8, kRounds = 1500 };
    long sum = 0, before = 0;
    for (int r = 0; r < kRounds; r++) {
        pthread_t t[kBatch];
        for (int i = 0; i < kBatch; i++)
            if (pthread_create(&t[i], 0, work, (void*)(long)(r * kBatch + i))) { printf("create failed\n"); return 1; }
        for (int i = 0; i < kBatch; i++) { void* v; pthread_join(t[i], &v); sum += (long)v; }
        if (r == 100) before = rss_kb();
    }
    long grown = rss_kb() - before;
    printf("sum %ld\n", sum);
    printf("rss %s\n", grown < 64 * 1024 ? "stable" : "grows");
    return 0;
}
