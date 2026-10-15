// A helper that returns its result in NZCV (what LLVM's machine outliner emits, e.g. V8's OUTLINED_FUNCTION_n):
// the RET must not treat the flags as dead.
#include <stdio.h>
__asm__(".text\n.p2align 2\n_xef_flagret_cmp:\n cmp x0, x1\n ret\n"
        ".p2align 2\n_xef_flagret_tst:\n tst x0, x1\n ret\n");
static inline int is_eq(long a, long b) {
    int r;
    __asm__ volatile("mov x0, %1\n mov x1, %2\n bl _xef_flagret_cmp\n cset %w0, eq" : "=r"(r) : "r"(a), "r"(b) : "x0", "x1", "x30", "cc", "memory");
    return r;
}
static inline int is_lt(long a, long b) {
    int r;
    __asm__ volatile("mov x0, %1\n mov x1, %2\n bl _xef_flagret_cmp\n cset %w0, lt" : "=r"(r) : "r"(a), "r"(b) : "x0", "x1", "x30", "cc", "memory");
    return r;
}
static inline int and_zero(long a, long b) {
    int r;
    __asm__ volatile("mov x0, %1\n mov x1, %2\n bl _xef_flagret_tst\n b.ne 1f\n mov %w0, #1\n b 2f\n1: mov %w0, #0\n2:" : "=r"(r) : "r"(a), "r"(b) : "x0", "x1", "x30", "cc", "memory");
    return r;
}
int main(void) {
    long acc = 0;
    for (long i = 0; i < 20000; i++) acc += is_eq(i, i & ~1L) * 3 + is_lt(i, 10000) * 5 + and_zero(i, 0x30) * 7;
    printf("%ld %d %d %d %d\n", acc, is_eq(5, 5), is_eq(5, 6), is_lt(-1, 0), and_zero(8, 7));
    return 0;
}
