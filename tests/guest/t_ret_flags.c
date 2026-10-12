// Indirect exits (RET/BR/BLR) whose live-out NZCV is rematerialized at the block end: the
// rematerialization must not clobber the branch target (regression: libLLVM jumped to 0).
#include <stdio.h>

__asm__(".text\n.globl cmp_ret\ncmp_ret:\n"
        "  stp x29, x30, [sp, #-16]!\n"
        "  mov x29, sp\n"
        "  ldp x9, x8, [x0]\n"
        "  ldrb w10, [x0, #16]\n"
        "  cmp x9, x8\n"
        "  cset w8, ne\n"
        "  orr w8, w10, w8\n"
        "  and w0, w8, #1\n"
        "  ldp x29, x30, [sp], #16\n"
        "  ret\n"
        ".globl cmp_br\ncmp_br:\n"
        "  ldp x9, x8, [x0]\n"
        "  cmp x9, x8\n"
        "  cset w0, hi\n"
        "  br x1\n");
int cmp_ret(long* p);
int cmp_br(long* p, void* target);
static int after_br(void) { return 0; }

int main(void) {
    long d[3] = {5, 5, 0};
    int r = 0;
    for (int i = 0; i < 4; i++) { d[1] = i; r = r * 2 + cmp_ret(d); }
    printf("ret: %d\n", r);
    printf("br returns via lr: %d\n", cmp_br(d, (void*)after_br) + 7);
    return 0;
}
