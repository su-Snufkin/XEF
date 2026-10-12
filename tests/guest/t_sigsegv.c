// Synchronous SIGSEGV delivered to guest handlers: siglongjmp out, fix-and-resume with the
// precise register/flag state, ucontext pc, and stack overflow caught on an alternate stack.
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <ucontext.h>
#include <unistd.h>

static sigjmp_buf jb;
static volatile void* fault_addr;
static volatile int fault_code;
static volatile uint64_t fault_pc;
static char* page;
static long pagesz;

static void h_jump(int sig, siginfo_t* si, void* uc) {
    fault_addr = si->si_addr;
    fault_code = si->si_code;
    siglongjmp(jb, sig);
}

static void h_fix(int sig, siginfo_t* si, void* ctx) {
    ucontext_t* uc = ctx;
    fault_addr = si->si_addr;
    fault_pc = uc->uc_mcontext.pc;
    mprotect(page, pagesz, PROT_READ | PROT_WRITE);   // retry succeeds
}

extern char fault_insn[];

// Registers mapped to host registers (x2, x6), in CpuState (x9, x10, x19) and NZCV must survive
// a fault + handler + sigreturn at the faulting store.
__attribute__((noinline)) static void precise(uint64_t out[6]) {
    __asm__ volatile(
        "mov x2, #1111\n"
        "mov x6, #6666\n"
        "mov x9, #123\n"
        "mov x10, #77\n"
        "mov x19, #1919\n"
        "cmp x9, x10\n"                // HI, NE, C set
        ".globl fault_insn\n"
        "fault_insn: str x9, [%1]\n"
        "cset x12, hi\n"
        "cset x13, cs\n"
        "stp x2, x6, [%0]\n"
        "stp x9, x10, [%0, #16]\n"
        "stp x19, x12, [%0, #32]\n"
        "add x13, x13, x12\n"
        "str x13, [%0, #40]\n"
        : : "r"(out), "r"(page) : "x2", "x6", "x9", "x10", "x12", "x13", "x19", "memory", "cc");
}

static volatile int fixes;
static char* region;
static void h_fix_region(int sig, siginfo_t* si, void* ctx) {
    fixes++;
    mprotect(region + pagesz, pagesz, PROT_READ | PROT_WRITE);
}

// hot loop (tier-2 region) whose stores run into a read-only page in the middle of the loop
__attribute__((noinline)) static unsigned long hot_fill(unsigned long seed) {
    unsigned long acc = seed, *p = (unsigned long*)region;
    long n = 2 * pagesz / 8;
    for (long i = 0; i < n; i++) {
        acc = acc * 6364136223846793005ull + 1442695040888963407ull;
        p[i] = acc ^ (unsigned long)i;
        if (acc & 1) acc += i;
    }
    return acc;
}

static volatile int depth_reached;
static int recurse(int n) {
    volatile char buf[512];
    buf[0] = (char)n;
    depth_reached = n;
    return recurse(n + 1) + buf[0];
}

int main(void) {
    pagesz = sysconf(_SC_PAGESIZE);
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = h_jump;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSEGV, &sa, 0);

    // 1. NULL-ish read, escape with siglongjmp
    if (sigsetjmp(jb, 1) == 0) {
        volatile int* p = (int*)16;
        printf("read %d\n", *p);
    } else {
        printf("caught SIGSEGV addr=%p code=%d\n", (void*)fault_addr, fault_code);
    }
    // the handler is still installed and SIGSEGV unblocked (sigsetjmp saved the mask)
    if (sigsetjmp(jb, 1) == 0) {
        *(volatile long*)0x1000 = 5;
    } else {
        printf("caught again addr=%p code=%d\n", (void*)fault_addr, fault_code);
    }

    // 2. write to a read-only page; the handler makes it writable and returns
    page = mmap(0, pagesz, PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    sa.sa_sigaction = h_fix;
    sigaction(SIGSEGV, &sa, 0);
    uint64_t out[6] = {0};
    precise(out);
    printf("fixed: addr ok=%d pc ok=%d stored=%ld\n", fault_addr == page, fault_pc == (uint64_t)fault_insn,
           *(long*)page);
    printf("regs: x2=%lu x6=%lu x9=%lu x10=%lu x19=%lu hi+cs=%lu\n", out[0], out[1], out[2], out[3], out[4], out[5]);
    for (int i = 0; i < 3; i++) {   // again, so the block is hot / reached by other paths
        mprotect(page, pagesz, PROT_READ);
        memset(out, 0, sizeof out);
        precise(out);
        printf("again %d: %lu %lu %lu %lu %lu %lu\n", i, out[0], out[1], out[2], out[3], out[4], out[5]);
    }

    // 2b. the same from inside a hot loop
    region = mmap(0, 2 * pagesz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    sa.sa_sigaction = h_fix_region;
    sigaction(SIGSEGV, &sa, 0);
    unsigned long acc = 0, sum = 0;
    for (int round = 0; round < 4000; round++) {
        mprotect(region + pagesz, pagesz, PROT_READ);
        acc = hot_fill(acc + round);
        for (long i = 0; i < 2 * pagesz / 8; i += 61) sum += ((unsigned long*)region)[i];
    }
    printf("hot loop: fixes=%d acc=%lx sum=%lx\n", fixes, acc, sum);

    // 3. stack overflow detected on an alternate signal stack
    static char altstack[64 * 1024];
    stack_t ss = {.ss_sp = altstack, .ss_size = sizeof altstack, .ss_flags = 0};
    sigaltstack(&ss, 0);
    sa.sa_sigaction = h_jump;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigaction(SIGSEGV, &sa, 0);
    if (sigsetjmp(jb, 1) == 0) {
        recurse(0);
    } else {
        printf("stack overflow caught on altstack (deep=%d)\n", depth_reached > 1000);
    }
    return 0;
}
