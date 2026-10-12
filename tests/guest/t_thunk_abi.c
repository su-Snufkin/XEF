// Host-thunk ABI (XEF only: HLT #0x5846 calls into XEF): AAPCS64 -> SysV marshalling of every
// argument class, with both register files overflowing to the stack on both sides.
#include <stdio.h>
#include "../../thunks/thunk_ids.h"

#define STR2(x) #x
#define STR(x) STR2(x)
double xef_selftest_mix(int a, float b, double c, long d, unsigned char e, signed char f, short g,
                        unsigned short h, float i, double j, int k, int l, int m, int n, int o, float p,
                        float q, float r, float s, float t, double u, long v);
__asm__(".text\n.globl xef_selftest_mix\nxef_selftest_mix:\n"
        "  mov x17, #" STR(XEF_THUNK_SELFTEST_MIX) "\n  hlt #0x5846\n  ret\n");

static double expect(int a, float b, double c, long d, unsigned char e, signed char f, short g, unsigned short h,
                     float i, double j, int k, int l, int m, int n, int o, float p, float q, float r, float s,
                     float t, double u, long v) {
    return a * 1.0 + b * 2.0 + c * 3.0 + (double)d * 4.0 + e * 5.0 + f * 6.0 + g * 7.0 + h * 8.0 + i * 9.0 +
           j * 10.0 + k * 11.0 + l * 12.0 + m * 13.0 + n * 14.0 + o * 15.0 + p * 16.0 + q * 17.0 + r * 18.0 +
           s * 19.0 + t * 20.0 + u * 21.0 + (double)v * 22.0;
}

int main(void) {
    int bad = 0;
    for (int it = 0; it < 50; it++) {
        // small types with garbage-prone values: negative chars/shorts, large unsigned
        int a = -7 * it; float b = 0.5f + it; double c = 1e9 + it; long d = -(1L << 40) + it;
        unsigned char e = (unsigned char)(250 + it); signed char f = (signed char)(-100 - it);
        short g = (short)(-30000 + it); unsigned short h = (unsigned short)(65000 + it);
        float i = -1.25f * it; double j = 3.5e-3 * it; int k = it, l = -it, m = 1 << 20, n = -(1 << 20), o = 77;
        float p = 1.0f / (it + 1), q = 2.0f, r = -3.0f, s = 4.5f, t = 5.25f; double u = -6.125; long v = 1L << 50;
        double got = xef_selftest_mix(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v);
        double want = expect(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v);
        if (got != want) { if (bad < 3) printf("it %d: got %.17g want %.17g\n", it, got, want); bad++; }
    }
    printf("thunk abi: %s\n", bad ? "MISMATCH" : "ok");
    return 0;
}
