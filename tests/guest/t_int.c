#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
static uint64_t h = 1469598103934665603ull;
static void mix(uint64_t v) { h ^= v; h *= 1099511628211ull; }
__attribute__((noinline)) int64_t sdiv(int64_t a, int64_t b) { return b ? a / b : 0; }
__attribute__((noinline)) uint32_t udiv32(uint32_t a, uint32_t b) { return b ? a / b : 0; }
__attribute__((noinline)) int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
typedef int (*binop)(int, int);
static int add(int a, int b) { return a + b; }
static int sub(int a, int b) { return a - b; }
static int mul(int a, int b) { return a * b; }
static int xr(int a, int b) { return a ^ b; }
int sw(int x) {
    switch (x & 15) {
    case 0: return 3; case 1: return 7; case 2: return x * 2; case 3: return x >> 1; case 4: return -x;
    case 5: return x % 7; case 6: return ~x; case 7: return x | 0x100; case 8: return 11; case 9: return x * x;
    case 10: return x - 100; case 11: return x + 99; case 12: return x & 0xf0; default: return 42;
    }
}
int main(void) {
    uint64_t x = 0x123456789abcdefull;
    for (int i = 0; i < 20000; i++) {
        x = x * 6364136223846793005ull + 1442695040888963407ull;
        int64_t s = (int64_t)x;
        mix(x >> 7); mix(x << 13); mix((uint64_t)(s >> 9)); mix(__builtin_popcountll(x));
        mix(__builtin_clzll(x | 1)); mix(__builtin_ctzll(x | 0x8000)); mix(__builtin_bswap64(x));
        mix(__builtin_bswap32((uint32_t)x)); mix((uint64_t)sdiv(s, (int64_t)(x >> 40) - 1000));
        mix(udiv32((uint32_t)x, (uint32_t)(x >> 50))); mix((unsigned __int128)x * (x >> 3) >> 64);
        mix((__int128)s * (int64_t)(x ^ 0x5555) >> 64); mix(sw((int)x));
        mix((uint32_t)x * (uint32_t)(x >> 32)); mix((int32_t)x < 0 ? 1 : 2);
        mix((x & 0xff) > 128 ? x % 1000 : x / 3); mix((uint64_t)(uint16_t)x << 5);
        mix((int64_t)(int8_t)x); mix((int64_t)(int16_t)(x >> 3)); mix(x > (x >> 1) ? x - (x >> 1) : 0);
        mix(sdiv(INT64_MIN, -1)); mix(udiv32(7, 0));
    }
    binop ops[4] = {add, sub, mul, xr};
    int acc = 1;
    for (int i = 0; i < 100000; i++) acc = ops[i & 3](acc, i);
    printf("hash=%016llx acc=%d fib=%d\n", (unsigned long long)h, acc, fib(24));
    long long v = strtoll("-9223372036854775807", 0, 10);
    printf("%lld %llu %x %o %ld\n", v, (unsigned long long)v, 0xdeadbeef, 0755, labs(-123456789L));
    return 0;
}
