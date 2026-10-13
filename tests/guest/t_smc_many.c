// Many pages of generated code, each rewritten many times (code invalidation index: growth of the
// page table, reuse of freed dependency entries, blocks spanning a page boundary).
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>

typedef long (*fn_t)(long);
#define NPAGES 96
#define RET 0xd65f03c0u

static uint32_t movz_x0(unsigned imm) { return 0xd2800000u | (imm << 5); }
static uint32_t add_x0(unsigned imm) { return 0x91000000u | (imm << 10); }   // add x0, x0, #imm

__attribute__((noinline)) static long call(fn_t f, long a) { return f(a); }

int main(void) {
    uint32_t* code = mmap(0, (NPAGES + 1) * 4096, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    long total = 0;
    for (int round = 0; round < 40; round++) {
        for (int p = 0; p < NPAGES; p++) {
            // a function at the start of every page, and one crossing into the next page
            uint32_t* f = code + p * 1024;
            f[0] = movz_x0((unsigned)(round * 7 + p) & 0xffff);
            f[1] = RET;
            __builtin___clear_cache((char*)f, (char*)(f + 2));
            uint32_t* g = code + p * 1024 + 1022;
            g[0] = add_x0((unsigned)(p + round) & 0xfff);
            g[1] = add_x0(3);
            g[2] = RET;
            __builtin___clear_cache((char*)g, (char*)(g + 3));
        }
        for (int p = 0; p < NPAGES; p++) {
            total += call((fn_t)(code + p * 1024), 0);
            total += call((fn_t)(code + p * 1024 + 1022), round);
        }
    }
    printf("total %ld\n", total);
    return 0;
}
