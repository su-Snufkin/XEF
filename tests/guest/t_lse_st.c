// LSE atomics whose old value is unused (STSET/STCLR/STEOR, Rt = XZR): single locked RMW on x86.
// Several threads toggle disjoint bits of shared words of every size.
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>

static uint8_t b8;
static uint16_t b16;
static uint32_t b32;
static uint64_t b64, x64;

#define ST(insn, p, v) __asm__ volatile(".arch armv8.1-a\n\t" insn " %w1, [%0]" :: "r"(p), "r"(v) : "memory")
#define STX(insn, p, v) __asm__ volatile(".arch armv8.1-a\n\t" insn " %1, [%0]" :: "r"(p), "r"(v) : "memory")

static void* work(void* arg) {
    int k = (int)(long)arg;
    for (int i = 0; i < 100000; i++) {
        ST("stsetb", &b8, 1u << k);
        ST("stclrlb", &b8, 1u << k);
        ST("stsetlh", &b16, 0x101u << k);
        ST("stclrh", &b16, 0x100u << k);
        ST("steor", &b32, 0x10001u << k);
        STX("stset", &b64, 1ull << (k + 40));
        STX("steorl", &x64, (0x8000000000000001ull >> 1) << k);
    }
    return 0;
}

int main(void) {
    pthread_t t[4];
    for (long k = 0; k < 4; k++) pthread_create(&t[k], 0, work, (void*)k);
    for (int k = 0; k < 4; k++) pthread_join(t[k], 0);
    printf("%02x %04x %08x %016llx %016llx\n", b8, b16, b32, (unsigned long long)b64, (unsigned long long)x64);
    return 0;
}
