// 128-bit arithmetic as used by libmpdec (Python's decimal): __udivti3/__umodti3, 128x64
// multiplies and the shift/clz based long division.
#include <stdint.h>
#include <stdio.h>

typedef unsigned __int128 u128;
static uint64_t s = 88172645463325252ull;
static uint64_t rnd(void) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }

// Hacker's Delight divlu (as in mpdecimal's _mpd_div_words portable path)
static void divlu(uint64_t* q, uint64_t* r, uint64_t u1, uint64_t u0, uint64_t v) {
    const uint64_t b = 1ull << 32;
    uint64_t un1, un0, vn1, vn0, q1, q0, un32, un21, un10, rhat, t;
    int n = __builtin_clzll(v);
    v <<= n;
    vn1 = v >> 32; vn0 = v & 0xffffffff;
    t = n ? u0 >> (64 - n) : 0;
    un32 = (u1 << n) | t;
    un10 = u0 << n;
    un1 = un10 >> 32; un0 = un10 & 0xffffffff;
    q1 = un32 / vn1; rhat = un32 - q1 * vn1;
again1:
    if (q1 >= b || q1 * vn0 > b * rhat + un1) { q1--; rhat += vn1; if (rhat < b) goto again1; }
    un21 = un32 * b + un1 - q1 * v;
    q0 = un21 / vn1; rhat = un21 - q0 * vn1;
again2:
    if (q0 >= b || q0 * vn0 > b * rhat + un0) { q0--; rhat += vn1; if (rhat < b) goto again2; }
    *q = q1 * b + q0;
    *r = (un21 * b + un0 - q0 * v) >> n;
}

int main(void) {
    uint64_t h1 = 0, h2 = 0, h3 = 0;
    const uint64_t base = 10000000000000000000ull;
    for (int i = 0; i < 200000; i++) {
        uint64_t d = rnd() >> (rnd() & 63);
        if (!d) d = 7;
        uint64_t hi = rnd() % d, lo = rnd();
        u128 n = ((u128)hi << 64) | lo;
        u128 q = n / d, r = n % d;
        h1 = h1 * 31 + (uint64_t)q + (uint64_t)(q >> 64) * 7 + (uint64_t)r;
        uint64_t q2, r2;
        divlu(&q2, &r2, hi, lo, d);
        h2 = h2 * 31 + q2 + r2;
        // base-10^19 word step (mpd short division)
        u128 m = (u128)(rnd() % base) * base + (rnd() % base);
        h3 = h3 * 31 + (uint64_t)(m / 7) + (uint64_t)(m % 7) + (uint64_t)((m * 3) >> 64);
    }
    printf("%016llx %016llx %016llx\n", (unsigned long long)h1, (unsigned long long)h2, (unsigned long long)h3);
    return 0;
}
