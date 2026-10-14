// A block of many element-wise LD3/ST3 (~150 IR instructions each) must be split before the IR
// buffer fills up (XEF stopped with an assertion in the IR builder).
#include <stdio.h>
unsigned char a[64], b[64];
int main(void) {
    for (int i = 0; i < 48; i++) a[i] = (unsigned char)(i * 7 + 3);
    __asm__ volatile("mov x0, %0\n\tmov x1, %1\n"
                     ".rept 40\n"
                     "ld3 {v0.16b, v1.16b, v2.16b}, [x0]\n\t"
                     "add v0.16b, v0.16b, v1.16b\n\t"
                     "st3 {v0.16b, v1.16b, v2.16b}, [x1]\n\t"
                     "ld3 {v3.8b, v4.8b, v5.8b}, [x1]\n\t"
                     "st3 {v3.8b, v4.8b, v5.8b}, [x0]\n"
                     ".endr"
                     :: "r"(a), "r"(b) : "x0", "x1", "v0", "v1", "v2", "v3", "v4", "v5", "memory");
    unsigned s = 0;
    for (int i = 0; i < 48; i++) s = s * 31 + a[i] + 3 * b[i];
    printf("%u\n", s);
    return 0;
}
