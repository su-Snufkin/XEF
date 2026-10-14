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

int main(void) {
    printf("%u\n", loop(40000000, 8));   // occasional call: stays in the region
    printf("%u\n", loop(40000000, 1));   // call every iteration: evicted
    printf("%u\n", loop(20000000, 2));
    printf("%.3f\n", (double)floop(20000000));
    return 0;
}
