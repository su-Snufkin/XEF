// Cache maintenance loop as in Firefox's libxul (jit FlushICache): line sizes from CTR_EL0, a
// DC CIVAC loop, then an IC IVAU loop that starts from x0 again. Under XEF x0 must survive both.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned dsize, isize;

__attribute__((noinline)) static void setup(void) {
    unsigned long ctr;
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
    unsigned d = 4u << ((ctr >> 16) & 0xf), i = 4u << (ctr & 0xf);
    dsize = d < 32 ? d : 32;
    isize = i < 32 ? i : 32;
}

// x0 = start, x1 = length; returns the number of IC IVAU iterations
__attribute__((noinline)) static unsigned long flush(void* start, unsigned long len) {
    unsigned long n = 0;
    __asm__ volatile(
        "mov x0, %[s]\n mov x1, %[l]\n"
        "cbz x1, 9f\n"
        "mov w10, %w[ds]\n mov w8, %w[is]\n"
        "neg x9, x10\n and x12, x9, x0\n neg x11, x8\n add x9, x1, x0\n"
        "1: dc civac, x12\n add x12, x12, x10\n cmp x12, x9\n b.lo 1b\n"
        "dsb ish\n"
        "and x10, x11, x0\n"
        "2: ic ivau, x10\n add %[n], %[n], #1\n add x10, x10, x8\n cmp x10, x9\n b.lo 2b\n"
        "dsb ish\n isb\n"
        "9:\n"
        : [n] "+r"(n)
        : [s] "r"(start), [l] "r"(len), [ds] "r"(dsize), [is] "r"(isize)
        : "x0", "x1", "x8", "x9", "x10", "x11", "x12", "cc", "memory");
    return n;
}

int main(void) {
    setup();
    printf("line sizes: d %u i %u\n", dsize, isize);
    static unsigned char buf[8192] __attribute__((aligned(4096)));
    memset(buf, 0, sizeof buf);
    printf("flush 4096: %lu lines\n", flush(buf, 4096));
    printf("flush 100 at +7: %lu lines\n", flush(buf + 7, 100));
    printf("flush 0: %lu lines\n", flush(buf, 0));
    return 0;
}
