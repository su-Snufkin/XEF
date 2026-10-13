// SIGSEGV delivered to a guest handler from a load that is not in the first block of a translation:
// a block translated together with its predecessor (fall-through chain) and a member of a hot
// tier-2 region. Both share host code with other blocks; the fault must map to the right guest pc.
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <sys/mman.h>

static sigjmp_buf jb;
static volatile long fault_pc_ok;
static void h(int s, siginfo_t* si, void* ctx) { fault_pc_ok += si->si_addr != 0; siglongjmp(jb, 1); }

__attribute__((noinline)) long chained(long x, long* p) {
    long r = x * 3;
    if (__builtin_expect(x == 123456789, 0)) puts("unlikely");   // conditional exit; the load falls through
    r += *p;
    return r;
}

// hot loop (tier 2): the last round reads from the PROT_NONE page after the array
__attribute__((noinline)) long hot(long* a, const int* idx, int n, long rounds) {
    long s = 0;
    for (long r = 0; r < rounds; r++)
        for (int i = 0; i < n; i++) {
            long v = a[idx[i] + (r == rounds - 1 ? 512 : 0)];
            if (__builtin_expect(v == 77777, 0)) s ^= i;
            else s += v;
        }
    return s;
}

int main(void) {
    char* m = mmap(0, 3 * 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    mprotect(m + 4096, 2 * 4096, PROT_NONE);
    struct sigaction sa = {0};
    sa.sa_sigaction = h;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSEGV, &sa, 0);
    int got = 0;
    for (int i = 0; i < 3; i++) {
        if (sigsetjmp(jb, 1) == 0) { chained(i, (long*)(m + 4096)); puts("no fault"); }
        else got++;
    }
    printf("chained: %d faults\n", got);
    long* a = (long*)m;
    static int idx[64];
    for (int i = 0; i < 512; i++) a[i] = i * 7 + 1;
    for (int i = 0; i < 64; i++) idx[i] = (i * 37) % 512;
    long rounds = 2000000;
    if (sigsetjmp(jb, 1) == 0) printf("hot: no fault %ld\n", hot(a, idx, 64, rounds));
    else printf("hot: fault\n");
    printf("addresses: %ld\n", fault_pc_ok);
    return 0;
}
