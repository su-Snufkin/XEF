// LDXP/STXP and CASP (pair exclusives / 128-bit compare-and-swap), single- and multi-threaded.
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>

typedef struct { uint64_t lo, hi; } __attribute__((aligned(16))) u128;
typedef struct { uint32_t lo, hi; } __attribute__((aligned(8))) u64p;

static void add128(u128* p, uint64_t a) {   // LDXP/STXP loop: {lo,hi} += a with carry
    uint64_t lo, hi;
    uint32_t fail;
    __asm__ volatile(
        "1: ldaxp %0, %1, [%3]\n"
        "   adds %0, %0, %4\n"
        "   adc %1, %1, xzr\n"
        "   stlxp %w2, %0, %1, [%3]\n"
        "   cbnz %w2, 1b\n"
        : "=&r"(lo), "=&r"(hi), "=&r"(fail) : "r"(p), "r"(a) : "memory", "cc");
}

static void inc_pair32(u64p* p) {   // 32-bit LDXP/STXP: lo++, hi += 2
    uint32_t lo, hi, fail;
    __asm__ volatile(
        "1: ldxp %w0, %w1, [%3]\n"
        "   add %w0, %w0, #1\n"
        "   add %w1, %w1, #2\n"
        "   stxp %w2, %w0, %w1, [%3]\n"
        "   cbnz %w2, 1b\n"
        : "=&r"(lo), "=&r"(hi), "=&r"(fail) : "r"(p) : "memory");
}

static int casp64(u128* p, uint64_t* elo, uint64_t* ehi, uint64_t nlo, uint64_t nhi) {
    register uint64_t x0 __asm__("x0") = *elo, x1 __asm__("x1") = *ehi;
    register uint64_t x2 __asm__("x2") = nlo, x3 __asm__("x3") = nhi;
    uint64_t olo = x0, ohi = x1;
    __asm__ volatile(".arch armv8.1-a\n caspal x0, x1, x2, x3, [%4]"
                     : "+r"(x0), "+r"(x1) : "r"(x2), "r"(x3), "r"(p) : "memory");
    int ok = x0 == olo && x1 == ohi;
    *elo = x0; *ehi = x1;
    return ok;
}

static int casp32(u64p* p, uint32_t* elo, uint32_t* ehi, uint32_t nlo, uint32_t nhi) {
    register uint32_t w4 __asm__("w4") = *elo, w5 __asm__("w5") = *ehi;
    register uint32_t w6 __asm__("w6") = nlo, w7 __asm__("w7") = nhi;
    uint32_t olo = w4, ohi = w5;
    __asm__ volatile(".arch armv8.1-a\n casp w4, w5, w6, w7, [%4]"
                     : "+r"(w4), "+r"(w5) : "r"(w6), "r"(w7), "r"(p) : "memory");
    int ok = w4 == olo && w5 == ohi;
    *elo = w4; *ehi = w5;
    return ok;
}

// LSE with acquire/release bits set (bits 23:22 of the encoding)
static void lse_ordered(void) {
    uint64_t m = 10, o1, o2, o3, o4;
    uint32_t w = 0xf0, o5 = 0xe0;
    __asm__ volatile(".arch armv8.1-a\n"
                     " ldaddal %4, %0, [%6]\n"
                     " swpa %4, %1, [%6]\n"
                     " ldsetl %4, %2, [%6]\n"
                     " ldumaxal %4, %3, [%6]\n"
                     " ldclral %w5, %w5, [%7]\n"
                     : "=&r"(o1), "=&r"(o2), "=&r"(o3), "=&r"(o4) , "+r"(m), "+r"(o5) : "r"(&m), "r"(&w) : "memory");
    printf("lse: %llu %llu %llu %llu %u\n", (unsigned long long)o1, (unsigned long long)o2, (unsigned long long)o3,
           (unsigned long long)o4, w);
}

static u128 shared;
static u64p shared32;
static u128 cas_shared;

static void* worker(void* arg) {
    for (int i = 0; i < 20000; i++) {
        add128(&shared, 0x8000000000000001ull);
        inc_pair32(&shared32);
        uint64_t lo = cas_shared.lo, hi = cas_shared.hi;
        while (!casp64(&cas_shared, &lo, &hi, lo + 1, hi + 3)) {}
    }
    return arg;
}

int main(void) {
    u128 a = {~0ull, 5};
    add128(&a, 1);
    printf("add128: %llx %llx\n", (unsigned long long)a.hi, (unsigned long long)a.lo);
    u64p b = {7, 9};
    inc_pair32(&b);
    printf("pair32: %u %u\n", b.lo, b.hi);

    u128 c = {1, 2};
    uint64_t lo = 1, hi = 2;
    int ok = casp64(&c, &lo, &hi, 10, 20);
    printf("casp64 ok=%d mem=%llu,%llu old=%llu,%llu\n", ok, (unsigned long long)c.lo, (unsigned long long)c.hi,
           (unsigned long long)lo, (unsigned long long)hi);
    lo = 1; hi = 2;
    ok = casp64(&c, &lo, &hi, 30, 40);
    printf("casp64 ok=%d mem=%llu,%llu old=%llu,%llu\n", ok, (unsigned long long)c.lo, (unsigned long long)c.hi,
           (unsigned long long)lo, (unsigned long long)hi);
    u64p d = {3, 4};
    uint32_t l32 = 3, h32 = 4;
    ok = casp32(&d, &l32, &h32, 0xdeadbeef, 0xcafe);
    printf("casp32 ok=%d mem=%x,%x\n", ok, d.lo, d.hi);
    l32 = 0; h32 = 0;
    ok = casp32(&d, &l32, &h32, 1, 1);
    printf("casp32 ok=%d mem=%x,%x old=%x,%x\n", ok, d.lo, d.hi, l32, h32);

    // __int128 atomics as emitted by the compiler
    static __int128 v128;
    __atomic_store_n(&v128, ((__int128)3 << 64) | 4, __ATOMIC_SEQ_CST);
    __int128 exp = ((__int128)3 << 64) | 4;
    int r = __atomic_compare_exchange_n(&v128, &exp, (__int128)99, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    __int128 got = __atomic_load_n(&v128, __ATOMIC_SEQ_CST);
    printf("int128 cas=%d val=%llu\n", r, (unsigned long long)got);

    lse_ordered();
    pthread_t t[4];
    for (int i = 0; i < 4; i++) pthread_create(&t[i], 0, worker, 0);
    for (int i = 0; i < 4; i++) pthread_join(t[i], 0);
    printf("threads: add128=%llx:%llx pair32=%u,%u casp=%llu,%llu\n", (unsigned long long)shared.hi,
           (unsigned long long)shared.lo, shared32.lo, shared32.hi, (unsigned long long)cas_shared.lo,
           (unsigned long long)cas_shared.hi);
    return 0;
}
