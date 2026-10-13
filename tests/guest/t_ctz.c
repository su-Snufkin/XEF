// rbit + clz (count trailing zeros) folded into tzcnt, including zero inputs.
#include <stdio.h>
#include <stdint.h>
int main(void) {
    uint64_t s = 0; uint64_t x = 0x9e3779b97f4a7c15ull;
    for (int i = 0; i < 2000; i++) {
        x ^= x << 13; x ^= x >> 7; x ^= x << 17;
        uint32_t w = (uint32_t)x & (i % 7 ? 0xffffffffu : 0);
        uint64_t q = x & (i % 5 ? ~0ull : 0);
        s += (w ? __builtin_ctz(w) : 32) * 3 + (q ? __builtin_ctzll(q) : 64);
    }
    printf("%llu\n", (unsigned long long)s);
    return 0;
}
