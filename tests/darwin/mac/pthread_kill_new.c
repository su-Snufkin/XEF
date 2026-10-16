// pthread_kill on a thread that just published its own pthread_self(), before pthread_create returned in the creator
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static pthread_t volatile g_self;
static volatile int g_go;
static volatile sig_atomic_t g_hits;
static void on_usr1(int s) { (void)s; g_hits++; }

static void* worker(void* a) {
    (void)a;
    g_self = pthread_self();
    while (!__atomic_load_n(&g_go, __ATOMIC_ACQUIRE)) {}
    return NULL;
}
static void* creator(void* a) {
    pthread_t* t = a;
    pthread_create(t, NULL, worker, NULL);
    return NULL;
}

int main(void) {
    signal(SIGUSR1, on_usr1);
    int ok = 0, n = 200;
    for (int i = 0; i < n; i++) {
        g_self = 0; g_go = 0;
        pthread_t t, c;
        pthread_create(&c, NULL, creator, &t);
        while (!g_self) {}
        if (pthread_kill(g_self, SIGUSR1) == 0) ok++;
        __atomic_store_n(&g_go, 1, __ATOMIC_RELEASE);
        pthread_join(c, NULL);
        pthread_join(t, NULL);
    }
    for (int i = 0; i < 1000 && g_hits < ok; i++) usleep(1000);
    printf("pthread_kill ok %d/%d, handled %d\n", ok, n, (int)g_hits);
    pthread_t t;
    pthread_create(&t, NULL, worker, NULL);
    g_go = 1;
    pthread_join(t, NULL);
    printf("done\n");
    return 0;
}
