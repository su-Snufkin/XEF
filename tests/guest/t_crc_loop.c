// CRC32 / CRC32C instructions in a hot loop (PCLMULQDQ Barrett reduction, SSE4.2 crc32) against qemu.
#include <arm_acle.h>
#include <stdio.h>
#include <stdint.h>
__attribute__((target("crc"))) int main(void) {
    uint32_t c = 0xffffffff, d = 0;
    static uint8_t buf[1 << 16];
    for (int i = 0; i < (int)sizeof buf; i++) buf[i] = (uint8_t)(i * 131 + 7);
    for (int r = 0; r < 200; r++) {
        const uint64_t* p = (const uint64_t*)buf;
        for (int i = 0; i < (int)(sizeof buf / 8); i++) c = __crc32d(c, p[i]);
        c = __crc32w(c, r); c = __crc32h(c, (uint16_t)r); c = __crc32b(c, (uint8_t)r);
        d = __crc32cd(d, c);
    }
    printf("%08x %08x\n", c, d);
    return 0;
}
