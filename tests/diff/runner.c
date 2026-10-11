// Differential test runner: executes single instructions with pseudo-random
// register state and prints the resulting state. Run under qemu and XEF.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

typedef struct {
    uint64_t x[28];
    uint64_t nzcv, fpcr;
    uint8_t v[32][16];
} State;

void run_test(State* s, void* code);

static uint64_t rng;
static uint64_t next(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; }

static uint64_t interesting64(void) {
    static const uint64_t vals[] = {0, 1, 2, 0xffffffffffffffffull, 0x7fffffffffffffffull, 0x8000000000000000ull,
                                    0xffffffffull, 0x80000000ull, 0x7fffffffull, 0x100000000ull, 0xff, 0x80, 0x7f,
                                    0xffff, 0x8000};
    switch (next() % 4) {
    case 0: return vals[next() % (sizeof vals / sizeof vals[0])];
    case 1: return next() & 0xff;
    default: return next();
    }
}

static uint64_t fp64(void) {
    static const uint64_t vals[] = {0x0000000000000000ull, 0x8000000000000000ull, 0x3ff0000000000000ull,
                                    0xbff0000000000000ull, 0x7ff0000000000000ull, 0xfff0000000000000ull,
                                    0x7ff8000000000000ull, 0x7ff4000000000000ull, 0x0000000000000001ull,
                                    0x000fffffffffffffull, 0x7fefffffffffffffull, 0x4000000000000000ull,
                                    0x3fe0000000000000ull, 0x43e0000000000000ull, 0x41e0000000000000ull,
                                    0xc3e0000000000000ull};
    if (next() % 3 == 0) return vals[next() % 16];
    double d = (double)(int64_t)(next() % 2000001) / (double)(1 + next() % 1000) - 1000.0;
    uint64_t b;
    memcpy(&b, &d, 8);
    return b;
}
static uint32_t fp32(void) {
    static const uint32_t vals[] = {0, 0x80000000u, 0x3f800000u, 0xbf800000u, 0x7f800000u, 0xff800000u,
                                    0x7fc00000u, 0x7fa00000u, 0x00000001u, 0x007fffffu, 0x7f7fffffu,
                                    0x40000000u, 0x3f000000u, 0x4f000000u, 0x5f000000u, 0xcf000000u};
    if (next() % 3 == 0) return vals[next() % 16];
    float f = (float)(int32_t)(next() % 200001) / (float)(1 + next() % 100) - 1000.0f;
    uint32_t b;
    memcpy(&b, &f, 4);
    return b;
}

static void init_state(State* s, uint64_t idx) {
    rng = 0x9E3779B97F4A7C15ull ^ (idx * 0x100000001B3ull);
    for (int k = 0; k < 4; k++) next();
    for (int i = 0; i < 28; i++) s->x[i] = interesting64();
    s->nzcv = (next() & 0xf) << 28;
    for (int i = 0; i < 32; i++) {
        int kind = next() % 4;
        for (int j = 0; j < 16; j += 8) {
            uint64_t w;
            if (kind == 0) w = fp64();
            else if (kind == 1) w = (uint64_t)fp32() | ((uint64_t)fp32() << 32);
            else w = interesting64();
            memcpy(&s->v[i][j], &w, 8);
        }
    }
}

int main(int argc, char** argv) {
    if (argc < 2) { fprintf(stderr, "usage: runner tests.bin [start]\n"); return 1; }
    FILE* f = fopen(argv[1], "rb");
    if (!f) { perror("open"); return 1; }
    fseek(f, 0, SEEK_END);
    long n = ftell(f) / 4;
    fseek(f, 0, SEEK_SET);
    uint32_t* insns = malloc(n * 4);
    if (fread(insns, 4, n, f) != (size_t)n) return 1;
    long start = argc > 2 ? atol(argv[2]) : 0;
    // one fresh 8-byte slot per test (no address reuse -> no stale translations)
    uint32_t* code = mmap(NULL, (size_t)n * 8 + 4096, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    State s;
    for (long i = start; i < n; i++) {
        uint32_t* c = code + i * 2;
        c[0] = insns[i];
        c[1] = 0xd65f03c0;  // ret
        __builtin___clear_cache((char*)c, (char*)(c + 2));
        init_state(&s, i);
        run_test(&s, c);
        printf("%ld", i);
        for (int r = 0; r < 28; r++) printf(" %lx", (unsigned long)s.x[r]);
        printf(" %lx", (unsigned long)s.nzcv);
        for (int r = 0; r < 32; r++) {
            uint64_t lo, hi;
            memcpy(&lo, s.v[r], 8);
            memcpy(&hi, s.v[r] + 8, 8);
            printf(" %lx:%lx", (unsigned long)hi, (unsigned long)lo);
        }
        printf("\n");
        fflush(stdout);
    }
    return 0;
}
