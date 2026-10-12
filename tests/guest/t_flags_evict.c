// Flags whose operand is a cset result live across a CBZ exit (CPython's OrderedDict compare):
// the cset value was evicted to its "home" register although that guest register had been
// overwritten, and the exit rematerialized the flags from the new value.
#include <stdint.h>
#include <stdio.h>
__asm__(".text\n.globl blk\nblk:\n"   // x0 = a, x1 = b; returns 1 if (a|b)!=0 && (a==0) ... see C
        "  stp x19, x20, [sp, #-16]!\n"
        "  sub sp, sp, #32\n"
        "  str x0, [sp, #16]\n"
        "  str x1, [sp, #24]\n"
        "  mov x19, sp\n"
        "  add x20, sp, #8\n"
        "  b 1f\n"
        "1:\n"
        "  ldr x19, [x19, #0x10]\n"
        "  ldr x20, [x20, #0x10]\n"
        "  cmp x20, #0x0\n"
        "  cset w0, eq\n"
        "  cmp x19, #0x0\n"
        "  cset w1, eq\n"
        "  mov w2, #0x2\n"
        "  cmp w0, #0x0\n"
        "  orr x0, x19, x20\n"
        "  cbnz x0, 2f\n"
        "  mov w0, #7\n"
        "  b 3f\n"
        "2:\n"
        "  cset w0, ne\n"          // flags of cmp w0(cset of b==0), #0
        "3:\n"
        "  add sp, sp, #32\n"
        "  ldp x19, x20, [sp], #16\n"
        "  ret\n");
int blk(long a, long b);
int main(void) {
    long v[] = {0, 1, 5};
    for (int i = 0; i < 3; i++)
        for (int j = 0; j < 3; j++) printf("%d", blk(v[i], v[j]));
    printf("\n");
    return 0;
}
