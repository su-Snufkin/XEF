// SHA-256 with the ARMv8 crypto extension (vsha256hq/h2q/su0q/su1q), hot enough for tier 2
#include <arm_neon.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const uint32_t K[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
    0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
    0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
    0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};

// all 16 round-constant vectors stay live in registers across the loop (as in Go's sha256block)
#define RND(k) do { uint32x4_t w = vaddq_u32(m0, k), t = abef; abef = vsha256hq_u32(abef, cdgh, w); \
    cdgh = vsha256h2q_u32(cdgh, t, w); uint32x4_t nm = vsha256su1q_u32(vsha256su0q_u32(m0, m1), m2, m3); \
    m0 = m1; m1 = m2; m2 = m3; m3 = nm; } while (0)
__attribute__((noinline)) static void blocks(uint32_t st[8], const uint8_t* p, size_t n) {
    uint32x4_t abef = vld1q_u32(st), cdgh = vld1q_u32(st + 4);
    uint32x4_t k0 = vld1q_u32(K), k1 = vld1q_u32(K + 4), k2 = vld1q_u32(K + 8), k3 = vld1q_u32(K + 12);
    uint32x4_t k4 = vld1q_u32(K + 16), k5 = vld1q_u32(K + 20), k6 = vld1q_u32(K + 24), k7 = vld1q_u32(K + 28);
    uint32x4_t k8 = vld1q_u32(K + 32), k9 = vld1q_u32(K + 36), k10 = vld1q_u32(K + 40), k11 = vld1q_u32(K + 44);
    uint32x4_t k12 = vld1q_u32(K + 48), k13 = vld1q_u32(K + 52), k14 = vld1q_u32(K + 56), k15 = vld1q_u32(K + 60);
    while (n--) {
        uint32x4_t a0 = abef, c0 = cdgh;
        uint32x4_t m0 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(p)));
        uint32x4_t m1 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(p + 16)));
        uint32x4_t m2 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(p + 32)));
        uint32x4_t m3 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(p + 48)));
        RND(k0); RND(k1); RND(k2); RND(k3); RND(k4); RND(k5); RND(k6); RND(k7);
        RND(k8); RND(k9); RND(k10); RND(k11); RND(k12); RND(k13); RND(k14); RND(k15);
        abef = vaddq_u32(abef, a0); cdgh = vaddq_u32(cdgh, c0);
        p += 64;
    }
    vst1q_u32(st, abef); vst1q_u32(st + 4, cdgh);
}

static void sha256(const uint8_t* d, size_t len, uint8_t out[32]) {
    uint32_t st[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    blocks(st, d, len / 64);
    uint8_t tail[128] = {0};
    size_t rem = len % 64;
    memcpy(tail, d + len - rem, rem);
    tail[rem] = 0x80;
    size_t tl = rem + 9 <= 64 ? 64 : 128;
    uint64_t bits = (uint64_t)len * 8;
    for (int i = 0; i < 8; i++) tail[tl - 1 - i] = (uint8_t)(bits >> (8 * i));
    blocks(st, tail, tl / 64);
    for (int i = 0; i < 8; i++) { out[4*i] = st[i] >> 24; out[4*i+1] = st[i] >> 16; out[4*i+2] = st[i] >> 8; out[4*i+3] = st[i]; }
}

int main(void) {
    static uint8_t buf[1 << 16];
    for (size_t i = 0; i < sizeof buf; i++) buf[i] = (uint8_t)(i * 131 + (i >> 8));
    uint8_t h[32];
    sha256((const uint8_t*)"abc", 3, h);
    for (int i = 0; i < 32; i++) printf("%02x", h[i]);
    printf("\n");
    for (int k = 0; k < 64; k++) { sha256(buf, sizeof buf, h); buf[k] ^= h[0]; }
    for (int i = 0; i < 32; i++) printf("%02x", h[i]);
    printf("\n");
    return 0;
}
