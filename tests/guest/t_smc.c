// Runtime-generated / modified code: cache maintenance (IC IVAU), W^X via mprotect,
// munmap + remap at the same address, hot generated loops, indirect calls.
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

typedef long (*fn_t)(long);

static uint32_t movz_w0(unsigned imm) { return 0x52800000u | (imm << 5); }
#define RET 0xd65f03c0u

static void emit_const(uint32_t* p, unsigned v) {
    p[0] = movz_w0(v);
    p[1] = RET;
    __builtin___clear_cache((char*)p, (char*)(p + 2));
}

// x1 = 0; do { x1 += K; } while (--x0); return x1
static void emit_loop(uint32_t* p, unsigned k) {
    p[0] = 0xd2800001u;                  // mov x1, #0
    p[1] = 0x91000021u | (k << 10);      // add x1, x1, #k
    p[2] = 0xf1000400u;                  // subs x0, x0, #1
    p[3] = 0x54ffffc1u;                  // b.ne .-8
    p[4] = 0xaa0103e0u;                  // mov x0, x1
    p[5] = RET;
    __builtin___clear_cache((char*)p, (char*)(p + 6));
}

__attribute__((noinline)) static long call(fn_t f, long a) { return f(a); }

static uint32_t* spin_code;
static void* spinner(void* arg) {
    long n = call((fn_t)spin_code, 0);
    return (void*)(n > 0 ? 1L : 0L);
}

int main(void) {
    long sum;
    // 1. RWX page rewritten in place
    uint32_t* rwx = mmap(0, 4096, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    for (unsigned v = 1; v <= 5; v++) {
        emit_const(rwx, v);
        sum = 0;
        for (int i = 0; i < 1000; i++) sum += call((fn_t)rwx, 0);   // indirect call: IBTC
        printf("rwx v=%u sum=%ld\n", v, sum);
    }

    // 2. W^X: write while RW, execute while RX
    uint32_t* wx = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    for (unsigned v = 10; v <= 12; v++) {
        mprotect(wx, 4096, PROT_READ | PROT_WRITE);
        emit_const(wx, v);
        mprotect(wx, 4096, PROT_READ | PROT_EXEC);
        printf("w^x v=%u got=%ld\n", v, call((fn_t)wx, 0));
    }

    // 3. unmap and map new code at the same address (no cache maintenance needed: fresh pages)
    for (unsigned v = 20; v <= 22; v++) {
        munmap(wx, 4096);
        uint32_t* p = mmap(wx, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
        p[0] = movz_w0(v);
        p[1] = RET;
        mprotect(p, 4096, PROT_READ | PROT_EXEC);
        printf("remap v=%u got=%ld same=%d\n", v, call((fn_t)p, 0), p == wx);
    }

    // 4. hot loop in generated code (becomes a tier-2 region), then patched
    uint32_t* loop = rwx + 256;
    for (unsigned k = 1; k <= 4; k++) {
        emit_loop(loop, k);
        long r = 0;
        for (int i = 0; i < 50; i++) r += call((fn_t)loop, 200000);
        printf("loop k=%u r=%ld\n", k, r);
    }
    // patch a single instruction in the middle of the hot loop
    loop[1] = 0x91000021u | (100 << 10);
    __builtin___clear_cache((char*)&loop[1], (char*)&loop[2]);
    printf("patched loop r=%ld\n", call((fn_t)loop, 1000));

    // 5. another thread spins in generated code (hot: tier-2 region) until its branch is
    //    rewritten into a return
    alarm(20);
    spin_code = rwx + 512;
    spin_code[0] = 0x91000400u;   // add x0, x0, #1
    spin_code[1] = 0x17ffffffu;   // b .-4
    __builtin___clear_cache((char*)spin_code, (char*)(spin_code + 2));
    pthread_t th;
    pthread_create(&th, 0, spinner, 0);
    usleep(300000);
    spin_code[1] = RET;
    __builtin___clear_cache((char*)&spin_code[1], (char*)&spin_code[2]);
    void* res;
    pthread_join(th, &res);
    printf("spinner stopped: %ld\n", (long)res);
    return 0;
}
