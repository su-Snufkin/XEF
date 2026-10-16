// dispatch_apply returns only when every iteration ran, and nothing touches the caller's stack afterwards
// (a worker that starts late must not write into the frame of a function that already returned)
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <string.h>

__attribute__((noinline)) static int apply_once(int n) {
    __block int sum = 0;
    dispatch_apply((size_t)n, dispatch_get_global_queue(0, 0), ^(size_t i) { __sync_fetch_and_add(&sum, (int)i + 1); });
    return sum;
}
__attribute__((noinline)) static int canary(void) {   // reuses the stack where apply_once's frame was
    volatile unsigned char buf[2048];
    memset((void*)buf, 0x5A, sizeof buf);
    for (volatile int spin = 0; spin < 20000; spin++) {}
    for (size_t i = 0; i < sizeof buf; i++) if (buf[i] != 0x5A) return 0;
    return 1;
}

int main(void) {
    int ok = 1, sums = 1;
    for (int r = 0; r < 300; r++) {
        int n = 1 + r % 4;
        sums &= apply_once(n) == n * (n + 1) / 2;
        ok &= canary();
    }
    printf("sums ok %d, caller stack untouched %d\n", sums, ok);
    return 0;
}
