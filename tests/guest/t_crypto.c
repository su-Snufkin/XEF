// ARMv8 Crypto Extension: SHA1/SHA256 (hardware vs. portable C), AES rounds, PMULL.
#include <arm_neon.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define CRYPTO __attribute__((target("crypto,sha2,aes")))

static const uint32_t K256[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

static uint32_t ror(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
static uint32_t rol(uint32_t x, int n) { return (x << n) | (x >> (32 - n)); }

static void sha256_sw(uint32_t st[8], const uint8_t blk[64]) {
    uint32_t w[64];
    for (int i = 0; i < 16; i++) w[i] = (uint32_t)blk[4 * i] << 24 | blk[4 * i + 1] << 16 | blk[4 * i + 2] << 8 | blk[4 * i + 3];
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = ror(w[i - 15], 7) ^ ror(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = ror(w[i - 2], 17) ^ ror(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = st[0], b = st[1], c = st[2], d = st[3], e = st[4], f = st[5], g = st[6], h = st[7];
    for (int i = 0; i < 64; i++) {
        uint32_t t1 = h + (ror(e, 6) ^ ror(e, 11) ^ ror(e, 25)) + ((e & f) ^ (~e & g)) + K256[i] + w[i];
        uint32_t t2 = (ror(a, 2) ^ ror(a, 13) ^ ror(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
        h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    st[0] += a; st[1] += b; st[2] += c; st[3] += d; st[4] += e; st[5] += f; st[6] += g; st[7] += h;
}

CRYPTO static void sha256_hw(uint32_t st[8], const uint8_t blk[64]) {
    uint32x4_t s0 = vld1q_u32(st), s1 = vld1q_u32(st + 4), a0 = s0, a1 = s1;
    uint32x4_t m[4];
    for (int i = 0; i < 4; i++) m[i] = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(blk + 16 * i)));
    for (int i = 0; i < 16; i++) {
        uint32x4_t wk = vaddq_u32(m[i & 3], vld1q_u32(K256 + 4 * i));
        uint32x4_t t = s0;
        s0 = vsha256hq_u32(s0, s1, wk);
        s1 = vsha256h2q_u32(s1, t, wk);
        if (i < 12) m[i & 3] = vsha256su1q_u32(vsha256su0q_u32(m[i & 3], m[(i + 1) & 3]), m[(i + 2) & 3], m[(i + 3) & 3]);
    }
    vst1q_u32(st, vaddq_u32(s0, a0));
    vst1q_u32(st + 4, vaddq_u32(s1, a1));
}

static void sha1_sw(uint32_t st[5], const uint8_t blk[64]) {
    uint32_t w[80];
    for (int i = 0; i < 16; i++) w[i] = (uint32_t)blk[4 * i] << 24 | blk[4 * i + 1] << 16 | blk[4 * i + 2] << 8 | blk[4 * i + 3];
    for (int i = 16; i < 80; i++) w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    uint32_t a = st[0], b = st[1], c = st[2], d = st[3], e = st[4];
    for (int i = 0; i < 80; i++) {
        uint32_t f, k;
        if (i < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
        else if (i < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
        else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
        else { f = b ^ c ^ d; k = 0xca62c1d6; }
        uint32_t t = rol(a, 5) + f + e + k + w[i];
        e = d; d = c; c = rol(b, 30); b = a; a = t;
    }
    st[0] += a; st[1] += b; st[2] += c; st[3] += d; st[4] += e;
}

CRYPTO static void sha1_hw(uint32_t st[5], const uint8_t blk[64]) {
    static const uint32_t K[4] = {0x5a827999, 0x6ed9eba1, 0x8f1bbcdc, 0xca62c1d6};
    uint32x4_t abcd = vld1q_u32(st), abcd0 = abcd;
    uint32_t e = st[4], e0 = e;
    uint32x4_t m[4];
    for (int i = 0; i < 4; i++) m[i] = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(blk + 16 * i)));
    for (int i = 0; i < 20; i++) {
        uint32x4_t wk = vaddq_u32(m[i & 3], vdupq_n_u32(K[i / 5]));
        uint32_t ne = vsha1h_u32(vgetq_lane_u32(abcd, 0));
        if (i < 5) abcd = vsha1cq_u32(abcd, e, wk);
        else if (i < 10 || i >= 15) abcd = vsha1pq_u32(abcd, e, wk);
        else abcd = vsha1mq_u32(abcd, e, wk);
        e = ne;
        if (i < 16) m[i & 3] = vsha1su1q_u32(vsha1su0q_u32(m[i & 3], m[(i + 1) & 3], m[(i + 2) & 3]), m[(i + 3) & 3]);
    }
    vst1q_u32(st, vaddq_u32(abcd, abcd0));
    st[4] = e + e0;
}

CRYPTO static void aes_and_pmull(void) {
    uint8_t key[16], data[16];
    for (int i = 0; i < 16; i++) { key[i] = (uint8_t)(i * 17 + 3); data[i] = (uint8_t)(i * 5 + 1); }
    uint8x16_t s = vld1q_u8(data), k = vld1q_u8(key);
    for (int r = 0; r < 9; r++) s = vaesmcq_u8(vaeseq_u8(s, k));
    s = vaeseq_u8(s, k);
    for (int r = 0; r < 9; r++) s = vaesimcq_u8(vaesdq_u8(s, k));
    uint8_t out[16];
    vst1q_u8(out, s);
    printf("aes:");
    for (int i = 0; i < 16; i++) printf(" %02x", out[i]);
    poly128_t p = vmull_p64(0x87654321fedcba98ull, 0x0123456789abcdefull);
    printf("\npmull: %016llx%016llx\n", (unsigned long long)(uint64_t)(p >> 64), (unsigned long long)(uint64_t)p);
}

static void pad_block(uint8_t blk[64], const char* msg) {
    size_t n = strlen(msg);
    memset(blk, 0, 64);
    memcpy(blk, msg, n);
    blk[n] = 0x80;
    uint64_t bits = (uint64_t)n * 8;
    for (int i = 0; i < 8; i++) blk[63 - i] = (uint8_t)(bits >> (8 * i));
}

int main(void) {
    const char* msgs[] = {"", "abc", "The quick brown fox jumps over the lazy dog"};
    for (int m = 0; m < 3; m++) {
        uint8_t blk[64];
        pad_block(blk, msgs[m]);
        uint32_t h1[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
        uint32_t h2[8];
        memcpy(h2, h1, sizeof h1);
        sha256_sw(h1, blk);
        sha256_hw(h2, blk);
        printf("sha256(\"%s\") = ", msgs[m]);
        for (int i = 0; i < 8; i++) printf("%08x", h2[i]);
        printf(" %s\n", memcmp(h1, h2, sizeof h1) ? "MISMATCH" : "ok");
        uint32_t g1[5] = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0}, g2[5];
        memcpy(g2, g1, sizeof g1);
        sha1_sw(g1, blk);
        sha1_hw(g2, blk);
        printf("sha1(\"%s\") = ", msgs[m]);
        for (int i = 0; i < 5; i++) printf("%08x", g2[i]);
        printf(" %s\n", memcmp(g1, g2, sizeof g1) ? "MISMATCH" : "ok");
    }
    aes_and_pmull();
    return 0;
}
