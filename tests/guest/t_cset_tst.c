// cmp / mov / eor / cset / tst / b.ne in one block (CPython's f-string tokenizer: "}}" was
// rejected as "single '}' is not allowed").
#include <stdint.h>
#include <stdio.h>
__asm__(".text\n.globl blk\nblk:\n"   // w0 = char, w1 = flag (x26); returns 1 if branch taken
        "  stp x26, x30, [sp, #-16]!\n"
        "  mov w26, w1\n"
        "  b 1f\n"
        "1:\n"
        "  cmp w0, #0x7d\n"
        "  mov w1, w0\n"
        "  eor w26, w26, #0x1\n"
        "  cset w0, eq\n"
        "  tst w0, w26\n"
        "  b.ne 2f\n"
        "  mov w0, #0\n"
        "  ldp x26, x30, [sp], #16\n"
        "  ret\n"
        "2:\n"
        "  mov w0, #1\n"
        "  ldp x26, x30, [sp], #16\n"
        "  ret\n");
int blk(int c, int flag);
int main(void) {
    int cs[] = {0x7d, 0x7b, 0x41, 0};
    for (int i = 0; i < 4; i++)
        for (int f = 0; f < 2; f++) printf("%d", blk(cs[i], f));
    printf("\n");
    return 0;
}
