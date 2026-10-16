// A small JIT: write code into MAP_JIT memory, run it, rewrite it in place, __builtin___clear_cache, run again
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>

typedef long (*fn_t)(long);

static void emit(uint32_t* p, uint32_t imm, int add) {
    pthread_jit_write_protect_np(0);
    p[0] = (add ? 0x91000000u : 0xD1000000u) | (imm << 10);   // add/sub x0, x0, #imm
    p[1] = 0xD65F03C0u;                                        // ret
    pthread_jit_write_protect_np(1);
}

int main(void) {
    uint32_t* p = mmap(NULL, 16384, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    fn_t f = (fn_t)p;
    long sum = 0;
    for (int round = 0; round < 6; round++) {
        emit(p, 10 + round, round & 1);
        __builtin___clear_cache((char*)p, (char*)(p + 2));
        long r = 0;
        for (int i = 0; i < 1000; i++) r = f(100);              // hot enough to be translated
        printf("round %d: f(100) = %ld\n", round, r);
        sum += r;
    }
    emit(p, 1, 1);
    sys_icache_invalidate(p, 8);
    printf("sys_icache_invalidate: f(1) = %ld, sum %ld\n", f(1), sum);
    return 0;
}
