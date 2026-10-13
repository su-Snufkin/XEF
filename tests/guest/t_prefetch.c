// PRFM in every addressing mode and kind: a hint, never a fault (also on unmapped addresses).
#include <stdio.h>
#include <stdint.h>

static long buf[64];

int main(void) {
    long s = 0;
    for (int i = 0; i < 64; i++) buf[i] = i * 3;
    for (long i = 0; i < 64; i++) {
        long* p = &buf[i];
        __asm__ volatile("prfm pldl1keep, [%0]\n\t"
                         "prfm pldl2strm, [%0, #64]\n\t"
                         "prfm pstl1keep, [%0, %1, lsl #3]\n\t"
                         "prfum pldl3keep, [%0, #-3]\n\t"
                         "prfm plil1keep, [%0]\n\t"
                         :: "r"(p), "r"(i) : "memory");
        s += *p;
    }
    uintptr_t bad[] = {0, 8, 0xdead0000, (uintptr_t)1 << 47, ~(uintptr_t)0 - 64};
    for (int i = 0; i < 5; i++)
        __asm__ volatile("prfm pldl1keep, [%0]\n\tprfm pstl2strm, [%0, #8]" :: "r"(bad[i]) : "memory");
    printf("sum %ld\n", s);
    return 0;
}
