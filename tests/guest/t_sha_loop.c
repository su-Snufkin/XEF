// SHA-1 / SHA-256 instructions in a hot loop (tier 2, SHA-NI paths) against qemu.
#include <arm_neon.h>
#include <stdio.h>
#include <stdint.h>
#define CRYPTO __attribute__((target("aes,sha2")))
CRYPTO int main(void) {
    uint32x4_t abcd = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a}, efgh = {0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    uint32x4_t m0 = {1, 2, 3, 4}, m1 = {5, 6, 7, 8}, m2 = {9, 10, 11, 12}, m3 = {13, 14, 15, 16};
    uint32x4_t s1 = {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476};
    uint32_t e = 0xC3D2E1F0;
    for (int n = 0; n < 3000000; n++) {
        uint32x4_t wk = vaddq_u32(m0, vdupq_n_u32(0x428a2f98));
        uint32x4_t t = abcd;
        abcd = vsha256hq_u32(abcd, efgh, wk);
        efgh = vsha256h2q_u32(efgh, t, wk);
        m0 = vsha256su1q_u32(vsha256su0q_u32(m0, m1), m2, m3);
        uint32x4_t tmp = m1; m1 = m2; m2 = m3; m3 = m0; m0 = tmp;
        uint32_t ne = vsha1h_u32(vgetq_lane_u32(s1, 0));
        s1 = vsha1cq_u32(s1, e, m0);
        s1 = vsha1pq_u32(s1, ne, m1);
        s1 = vsha1mq_u32(s1, e ^ n, vsha1su1q_u32(vsha1su0q_u32(m0, m1, m2), m3));
        e = ne;
    }
    printf("%08x %08x %08x %08x %08x\n", vgetq_lane_u32(abcd, 0), vgetq_lane_u32(efgh, 3), vgetq_lane_u32(s1, 1), vgetq_lane_u32(m0, 2), e);
    return 0;
}
