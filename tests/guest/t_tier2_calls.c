// Tier-2 regions with calls (BL) inside the loop: the callee runs with the canonical register
// mapping (transfers around the call); a region calling too often is evicted while threads run
// in it and formed again without the call. Callees clobber caller-saved X and V registers.
#include <stdio.h>
#include <stdint.h>

__attribute__((noinline)) uint32_t mix(uint32_t x) {
    __asm__ volatile("mov x9, #77\n mov x10, #78\n mov x15, #79\n movi v16.16b, #3\n movi v1.16b, #9" ::: "x9", "x10", "x15", "v16", "v1");
    return x * 2654435761u >> 7;
}
__attribute__((noinline)) float fmix(float x) { return x * 0.5f + 1.0f; }

static uint32_t loop(long n, int every) {
    uint32_t a = 1, b = 2, c = 3, d = 4, e = 5, g = 6, h = 7;
    for (long i = 0; i < n; i++) {
        a += b ^ c; b += c ^ d; c += d ^ e; d += e ^ g; e += g ^ h; g += h ^ a;
        if ((i & (every - 1)) == 0) h += mix(a);
    }
    return a + b + c + d + e + g + h;
}

static float floop(long n) {
    float s = 0, t = 1, u = 2, w = 3;
    for (long i = 0; i < n; i++) {
        s = s * 0.999f + t; t = t * 0.998f + u; u = u * 0.997f + w; w = w * 0.996f + 1.0f;
        if ((i & 15) == 0) s = fmix(s);
    }
    return s + t + u + w;
}

// several call sites of one callee (more than two return addresses), recursion, and returns that
// do not go back to the call site (longjmp out of a callee inlined into the region)
#include <setjmp.h>
__attribute__((noinline)) uint32_t leaf(uint32_t x) { return (x ^ (x >> 5)) * 0x9E3779B1u; }
__attribute__((noinline)) uint32_t fib(uint32_t n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
static jmp_buf jb;
__attribute__((noinline)) uint32_t maybe_jump(uint32_t x) {
    if ((x & 0xffff) == 0x1234) longjmp(jb, 1);
    return x + 1;
}

static uint32_t sites(long n) {
    uint32_t a = 1, b = 2, c = 3;
    for (long i = 0; i < n; i++) {
        a = leaf(a + (uint32_t)i);
        if (i & 1) b = leaf(b ^ a);
        if (i & 2) c = leaf(c + b);
    }
    return a ^ b ^ c;
}

static volatile long ji;   // survives the longjmp: the loop goes on where it left
static uint32_t jumps(long n) {
    static volatile uint32_t s, k;
    if (setjmp(jb)) { s = s + 1000; k = k + 1; ji = ji + 1; }
    for (; ji < n; ji = ji + 1) s = maybe_jump(s * 2654435761u + (uint32_t)ji + k);
    return s + k * 7;
}

int main(void) {
    printf("%u\n", sites(10000000));
    uint32_t f = 0;
    for (int i = 0; i < 40; i++) f += fib(20 + (i & 3));
    printf("%u\n", f);
    printf("%u\n", jumps(3000000));
    printf("%u\n", loop(40000000, 8));   // occasional call: stays in the region
    printf("%u\n", loop(40000000, 1));   // call every iteration: evicted
    printf("%u\n", loop(20000000, 2));
    printf("%.3f\n", (double)floop(20000000));
    return 0;
}
