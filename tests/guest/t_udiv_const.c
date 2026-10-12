// UDIV by a 64-bit constant whose dividend is a guest register not yet read in the block: with
// every temporary pinned the codegen borrows a mapped guest register (here x7's), which used to
// leave the dividend reading the borrowed register (libmpdec: Decimal(1)/7 printed "1{7").
#include <stdint.h>
#include <stdio.h>
__asm__(".text\n.globl blk\nblk:\n"
        "  mov x7, x1\n"
        "  b 1f\n"
        "1:\n"
        "  mov x6, #0x1000\n"
        "  movk x6, #0xd4a5, lsl #16\n"
        "  movk x6, #0xe8, lsl #32\n"
        "  udiv x2, x7, x6\n"
        "  add w8, w2, #0x30\n"
        "  strb w8, [x0], #1\n"
        "  msub x2, x2, x6, x7\n"
        "  cbz x0, 2f\n"
        "  mov x0, x2\n"
        "2: ret\n");
uint64_t blk(char* buf, uint64_t v);
int main(void) {
    char buf[8] = {0};
    uint64_t vals[] = {9999999999999ull, 1234567890123ull, 5000000000000ull, 999999999999ull, 7142857142857ull};
    for (int i = 0; i < 5; i++) {
        uint64_t r = blk(buf, vals[i]);
        printf("%c %llu\n", buf[0], (unsigned long long)r);
    }
    return 0;
}
