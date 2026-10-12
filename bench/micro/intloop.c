// Integer-heavy loops: sieve, hashing, bit manipulation, sorting.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint8_t sieve[1 << 24];
int main(void) {
    uint64_t total = 0;
    for (int rep = 0; rep < 3; rep++) {
        memset(sieve, 1, sizeof sieve);
        for (uint32_t i = 2; i * i < sizeof sieve; i++)
            if (sieve[i]) for (uint32_t j = i * i; j < sizeof sieve; j += i) sieve[j] = 0;
        for (uint32_t i = 2; i < sizeof sieve; i++) total += sieve[i];
    }
    uint64_t h = 0x9e3779b97f4a7c15ull;
    for (uint32_t i = 0; i < 200000000; i++) {
        h ^= h >> 29; h *= 0xbf58476d1ce4e5b9ull; h += i; h = (h << 7) | (h >> 57);
    }
    static uint32_t arr[1 << 20];
    uint32_t s = 1;
    for (int i = 0; i < (1 << 20); i++) { s = s * 1664525 + 1013904223; arr[i] = s; }
    // radix-like counting
    uint32_t cnt[256] = {0};
    for (int r = 0; r < 20; r++)
        for (int i = 0; i < (1 << 20); i++) cnt[(arr[i] >> (r & 24)) & 255]++;
    printf("%llu %llx %u\n", (unsigned long long)total, (unsigned long long)h, cnt[17]);
    return 0;
}
