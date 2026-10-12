// Call depth beyond the JIT's native return stack (one entry per BL): must keep working.
#include <stdio.h>

__attribute__((noinline)) static unsigned rec(unsigned n) {
    volatile unsigned keep = n;
    if (n == 0) return 1;
    unsigned r = rec(n - 1);
    return r * 31 + keep;
}

int main(void) {
    unsigned total = 0;
    for (int i = 0; i < 3; i++) total += rec(150000 + i);
    printf("deep: %u\n", total);
    printf("shallow after deep: %u\n", rec(10));
    return 0;
}
