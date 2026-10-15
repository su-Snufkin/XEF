// FEAT_JSCVT FJCVTZS (V8 uses it for every double -> int32 JS conversion): result and Z flag must match the real CPU.
#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

static void t(double d) {
    uint32_t r; uint64_t nzcv;
    __asm__ volatile(".arch armv8.3-a\n fjcvtzs %w0, %d2\n mrs %1, nzcv" : "=r"(r), "=r"(nzcv) : "w"(d) : "cc");
    printf("%-24.17g -> %08x nzcv=%llx\n", d, r, (unsigned long long)(nzcv >> 28));
}
int main(void) {
    double v[] = {0.0, -0.0, 1.0, -1.0, 1.5, -1.5, 2147483647.0, 2147483648.0, -2147483648.0, -2147483649.0, 4294967295.0, 4294967296.0,
                  4294967297.5, 1e10, -1e10, 1e300, -1e300, 9007199254740993.0, 5e-324, -5e-324, 0.99999999, 123456789.987, -123456789.987,
                  (double)INFINITY, -(double)INFINITY, (double)NAN, 1099511627776.0 + 5, 4503599627370496.0 + 0.5, 3.0e9, -3.0e9};
    for (unsigned i = 0; i < sizeof v / sizeof *v; i++) t(v[i]);
    return 0;
}
