// LLVM's machine outliner keeps NZCV live across a BL to a helper that does not touch the flags:
// cmp; bl helper; b.eq - the branch must see the caller's compare
#include <stdio.h>

__attribute__((naked, noinline)) static void helper(void) {   // moves registers only, like _OUTLINED_FUNCTION_n
    __asm__ volatile("mov x9, #5\n mov x10, #6\n ret\n");
}

__attribute__((noinline)) static long pick(long a, long b) {
    long r;
    __asm__ volatile(
        "stp x29, x30, [sp, #-16]!\n"
        "cmp %1, %2\n"
        "bl %3\n"
        "b.eq 1f\n"
        "add %0, x9, x10\n"
        "b 2f\n"
        "1: mov %0, #77\n"
        "2: ldp x29, x30, [sp], #16\n"
        : "=&r"(r) : "r"(a), "r"(b), "S"(helper) : "x9", "x10", "x30", "cc", "memory");
    return r;
}

// ... and a helper that consumes the caller's flags on entry: cmp x8, #8 ; bl helper2 (csel x9, x8, x9, lo ; ret)
__attribute__((naked, noinline)) static void helper2(void) {
    __asm__ volatile("csel x9, x8, x9, lo\n ret\n");
}
__attribute__((noinline)) static long cap(long mask) {
    long r;
    __asm__ volatile(
        "stp x29, x30, [sp, #-16]!\n"
        "mov x8, %1\n"
        "lsr x9, x8, #3\n"
        "lsl x9, x9, #3\n"
        "cmp x8, #8\n"
        "bl %2\n"
        "mov %0, x9\n"
        "ldp x29, x30, [sp], #16\n"
        : "=&r"(r) : "r"(mask), "S"(helper2) : "x8", "x9", "x30", "cc", "memory");
    return r;
}

int main(void) {
    long c = 0;
    for (long i = 0; i < 100000; i++) c += cap(i & 15);
    printf("cap(3)=%ld cap(15)=%ld c=%ld\n", cap(3), cap(15), c);
    long s = 0;
    for (long i = 0; i < 200000; i++) s += pick(i & 7, 3);   // hot: tier 2 as well
    printf("pick(3,3)=%ld pick(1,3)=%ld sum=%ld\n", pick(3, 3), pick(1, 3), s);
    return 0;
}
