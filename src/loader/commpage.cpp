// XEF-OSX — macOS commpage initialization.
#include "loader/commpage.h"
#include <sys/mman.h>
#include <sys/sysinfo.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>

namespace xef {

static bool setup_page_at(uint64_t addr) {
    void* p = mmap((void*)addr, COMM_PAGE_AREA_LENGTH, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    if (p == MAP_FAILED) {
        p = mmap((void*)addr, COMM_PAGE_AREA_LENGTH, PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    }
    if (p == MAP_FAILED) return false;

    uint8_t* cp = (uint8_t*)p;
    memset(cp, 0, COMM_PAGE_AREA_LENGTH);

    // Signature
    const char* sig = "commpage 64-bit";
    memcpy(cp + COMM_PAGE_SIGNATURE, sig, strlen(sig) + 1);

    // Version
    *(uint16_t*)(cp + COMM_PAGE_VERSION) = 17;

    // CPU Capabilities
    uint64_t caps = k64Bit | kHasSSE | kHasSSE2 | kHasSSE3 | kHasSupplementalSSE3 |
                    kHasSSE4_1 | kHasSSE4_2 | kHasAVX1_0 | kHasAVX2_0 |
                    kHasARM_AdvSIMD | kHasARM_FP;
    *(uint64_t*)(cp + COMM_PAGE_CPU_CAPABILITIES64) = caps;
    *(uint32_t*)(cp + COMM_PAGE_CPU_CAPABILITIES) = (uint32_t)caps;

    // Number of CPUs
    int ncpu = (int)sysconf(_SC_NPROCESSORS_ONLN);
    if (ncpu <= 0) ncpu = 1;
    *(uint8_t*)(cp + COMM_PAGE_NCPUS) = (uint8_t)ncpu;
    *(uint8_t*)(cp + COMM_PAGE_ACTIVE_CPUS) = (uint8_t)ncpu;
    *(uint8_t*)(cp + COMM_PAGE_PHYSICAL_CPUS) = (uint8_t)ncpu;
    *(uint8_t*)(cp + COMM_PAGE_LOGICAL_CPUS) = (uint8_t)ncpu;

    // Page shift (12 for 4096-byte page)
    long ps = sysconf(_SC_PAGESIZE);
    uint8_t shift = 12;
    if (ps == 16384) shift = 14;
    *(uint8_t*)(cp + COMM_PAGE_USER_PAGE_SHIFT_64) = shift;
    *(uint8_t*)(cp + COMM_PAGE_KERNEL_PAGE_SHIFT)  = shift;

    // Memory size
    struct sysinfo si;
    if (sysinfo(&si) == 0) {
        *(uint64_t*)(cp + COMM_PAGE_MEMORY_SIZE) = (uint64_t)si.totalram * si.mem_unit;
    } else {
        *(uint64_t*)(cp + COMM_PAGE_MEMORY_SIZE) = 8ull * 1024 * 1024 * 1024;
    }

    // Timebase (1:1)
    *(uint32_t*)(cp + COMM_PAGE_TIMEBASE) = 1;
    *(uint32_t*)(cp + COMM_PAGE_TIMEBASE + 4) = 1;

    // Set page read-only for guest, like actual Darwin kernel does
    mprotect(p, COMM_PAGE_AREA_LENGTH, PROT_READ);
    return true;
}

bool commpage_init() {
    bool ok1 = setup_page_at(COMM_PAGE64_BASE_ADDRESS);
    bool ok2 = setup_page_at(COMM_PAGE64_ARM_ADDRESS);
    return ok1 || ok2;
}

} // namespace xef
