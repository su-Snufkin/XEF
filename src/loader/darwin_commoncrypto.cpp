// XEF-OSX — CommonCrypto's CommonDigest (libSystem's libcommonCrypto): MD5, SHA-1, SHA-224/256, SHA-384/512 with the
// CC_*_Init/Update/Final and one-shot APIs. The state lives in the guest's context struct and fits Darwin's sizes
// (CC_MD5_CTX 92, CC_SHA1_CTX 96, CC_SHA256_CTX 104, CC_SHA512_CTX 208 bytes). Checked by tests/darwin/mac/commondigest.c.
#include "loader/darwin_hle.h"
#include "common/common.h"

#include <stdint.h>
#include <string.h>

namespace xef {

static inline uint32_t rol(uint32_t x, int n) { return (x << n) | (x >> (32 - n)); }
static inline uint32_t ror(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
static inline uint64_t ror64(uint64_t x, int n) { return (x >> n) | (x << (64 - n)); }
static inline uint32_t be32(const uint8_t* p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static inline uint64_t be64(const uint8_t* p) { return (uint64_t)be32(p) << 32 | be32(p + 4); }
static inline uint32_t le32(const uint8_t* p) { return (uint32_t)p[3] << 24 | (uint32_t)p[2] << 16 | (uint32_t)p[1] << 8 | p[0]; }

// ---- MD5 ------------------------------------------------------------------------------------------------------
struct Md5 { uint32_t h[4]; uint64_t n; uint8_t buf[64]; };
static_assert(sizeof(Md5) <= 92, "CC_MD5_CTX");
static void md5_block(uint32_t* h, const uint8_t* p) {
    static const uint32_t K[64] = {
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af,
        0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
        0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665, 0xf4292244, 0x432aff97,
        0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391};
    static const int S[64] = {7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
                              4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21};
    uint32_t m[16];
    for (int i = 0; i < 16; i++) m[i] = le32(p + 4 * i);
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
    for (int i = 0; i < 64; i++) {
        uint32_t f; int g;
        if (i < 16) { f = (b & c) | (~b & d); g = i; }
        else if (i < 32) { f = (d & b) | (~d & c); g = (5 * i + 1) & 15; }
        else if (i < 48) { f = b ^ c ^ d; g = (3 * i + 5) & 15; }
        else { f = c ^ (b | ~d); g = (7 * i) & 15; }
        uint32_t t = d; d = c; c = b;
        b = b + rol(a + f + K[i] + m[g], S[i]);
        a = t;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d;
}

// ---- SHA-1 ----------------------------------------------------------------------------------------------------
struct Sha1 { uint32_t h[5]; uint64_t n; uint8_t buf[64]; };
static_assert(sizeof(Sha1) <= 96, "CC_SHA1_CTX");
static void sha1_block(uint32_t* h, const uint8_t* p) {
    uint32_t w[80];
    for (int i = 0; i < 16; i++) w[i] = be32(p + 4 * i);
    for (int i = 16; i < 80; i++) w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
    for (int i = 0; i < 80; i++) {
        uint32_t f, k;
        if (i < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
        else if (i < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
        else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
        else { f = b ^ c ^ d; k = 0xca62c1d6; }
        uint32_t t = rol(a, 5) + f + e + k + w[i];
        e = d; d = c; c = rol(b, 30); b = a; a = t;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e;
}

// ---- SHA-256 / SHA-224 ----------------------------------------------------------------------------------------
struct Sha256 { uint32_t h[8]; uint64_t n; uint8_t buf[64]; };
static_assert(sizeof(Sha256) <= 104, "CC_SHA256_CTX");
static void sha256_block(uint32_t* h, const uint8_t* p) {
    static const uint32_t K[64] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01,
        0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
        0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08,
        0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
    uint32_t w[64];
    for (int i = 0; i < 16; i++) w[i] = be32(p + 4 * i);
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = ror(w[i - 15], 7) ^ ror(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = ror(w[i - 2], 17) ^ ror(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 64; i++) {
        uint32_t t1 = hh + (ror(e, 6) ^ ror(e, 11) ^ ror(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i];
        uint32_t t2 = (ror(a, 2) ^ ror(a, 13) ^ ror(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

// ---- SHA-512 / SHA-384 ----------------------------------------------------------------------------------------
struct Sha512 { uint64_t h[8]; uint64_t n; uint8_t buf[128]; };
static_assert(sizeof(Sha512) <= 208, "CC_SHA512_CTX");
static void sha512_block(uint64_t* h, const uint8_t* p) {
    static const uint64_t K[80] = {
        0x428a2f98d728ae22ull, 0x7137449123ef65cdull, 0xb5c0fbcfec4d3b2full, 0xe9b5dba58189dbbcull, 0x3956c25bf348b538ull,
        0x59f111f1b605d019ull, 0x923f82a4af194f9bull, 0xab1c5ed5da6d8118ull, 0xd807aa98a3030242ull, 0x12835b0145706fbeull,
        0x243185be4ee4b28cull, 0x550c7dc3d5ffb4e2ull, 0x72be5d74f27b896full, 0x80deb1fe3b1696b1ull, 0x9bdc06a725c71235ull,
        0xc19bf174cf692694ull, 0xe49b69c19ef14ad2ull, 0xefbe4786384f25e3ull, 0x0fc19dc68b8cd5b5ull, 0x240ca1cc77ac9c65ull,
        0x2de92c6f592b0275ull, 0x4a7484aa6ea6e483ull, 0x5cb0a9dcbd41fbd4ull, 0x76f988da831153b5ull, 0x983e5152ee66dfabull,
        0xa831c66d2db43210ull, 0xb00327c898fb213full, 0xbf597fc7beef0ee4ull, 0xc6e00bf33da88fc2ull, 0xd5a79147930aa725ull,
        0x06ca6351e003826full, 0x142929670a0e6e70ull, 0x27b70a8546d22ffcull, 0x2e1b21385c26c926ull, 0x4d2c6dfc5ac42aedull,
        0x53380d139d95b3dfull, 0x650a73548baf63deull, 0x766a0abb3c77b2a8ull, 0x81c2c92e47edaee6ull, 0x92722c851482353bull,
        0xa2bfe8a14cf10364ull, 0xa81a664bbc423001ull, 0xc24b8b70d0f89791ull, 0xc76c51a30654be30ull, 0xd192e819d6ef5218ull,
        0xd69906245565a910ull, 0xf40e35855771202aull, 0x106aa07032bbd1b8ull, 0x19a4c116b8d2d0c8ull, 0x1e376c085141ab53ull,
        0x2748774cdf8eeb99ull, 0x34b0bcb5e19b48a8ull, 0x391c0cb3c5c95a63ull, 0x4ed8aa4ae3418acbull, 0x5b9cca4f7763e373ull,
        0x682e6ff3d6b2b8a3ull, 0x748f82ee5defb2fcull, 0x78a5636f43172f60ull, 0x84c87814a1f0ab72ull, 0x8cc702081a6439ecull,
        0x90befffa23631e28ull, 0xa4506cebde82bde9ull, 0xbef9a3f7b2c67915ull, 0xc67178f2e372532bull, 0xca273eceea26619cull,
        0xd186b8c721c0c207ull, 0xeada7dd6cde0eb1eull, 0xf57d4f7fee6ed178ull, 0x06f067aa72176fbaull, 0x0a637dc5a2c898a6ull,
        0x113f9804bef90daeull, 0x1b710b35131c471bull, 0x28db77f523047d84ull, 0x32caab7b40c72493ull, 0x3c9ebe0a15c9bebcull,
        0x431d67c49c100d4cull, 0x4cc5d4becb3e42b6ull, 0x597f299cfc657e2aull, 0x5fcb6fab3ad6faecull, 0x6c44198c4a475817ull};
    uint64_t w[80];
    for (int i = 0; i < 16; i++) w[i] = be64(p + 8 * i);
    for (int i = 16; i < 80; i++) {
        uint64_t s0 = ror64(w[i - 15], 1) ^ ror64(w[i - 15], 8) ^ (w[i - 15] >> 7);
        uint64_t s1 = ror64(w[i - 2], 19) ^ ror64(w[i - 2], 61) ^ (w[i - 2] >> 6);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint64_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 80; i++) {
        uint64_t t1 = hh + (ror64(e, 14) ^ ror64(e, 18) ^ ror64(e, 41)) + ((e & f) ^ (~e & g)) + K[i] + w[i];
        uint64_t t2 = (ror64(a, 28) ^ ror64(a, 34) ^ ror64(a, 39)) + ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

// ---- generic buffering (block size B, length field size L bytes, big- or little-endian length) ---------------------
template <class C, size_t B, class F>
static void feed(C* c, const uint8_t* p, size_t len, F block) {
    size_t have = (size_t)(c->n % B);
    c->n += len;
    if (have) {
        size_t k = B - have < len ? B - have : len;
        memcpy(c->buf + have, p, k);
        p += k; len -= k; have += k;
        if (have < B) return;
        block(c->h, c->buf);
    }
    for (; len >= B; p += B, len -= B) block(c->h, p);
    memcpy(c->buf, p, len);
}
template <class C, size_t B, class F>
static void pad(C* c, F block, bool le_len, size_t lenbytes) {
    uint64_t bits = c->n * 8;
    size_t have = (size_t)(c->n % B);
    c->buf[have++] = 0x80;
    if (have > B - lenbytes) { memset(c->buf + have, 0, B - have); block(c->h, c->buf); have = 0; }
    memset(c->buf + have, 0, B - have);
    for (int i = 0; i < 8; i++) {
        uint8_t byte = (uint8_t)(bits >> (8 * i));
        if (le_len) c->buf[B - lenbytes + i] = byte; else c->buf[B - 1 - i] = byte;
    }
    block(c->h, c->buf);
}

static int md5_init(Md5* c) { c->h[0] = 0x67452301; c->h[1] = 0xefcdab89; c->h[2] = 0x98badcfe; c->h[3] = 0x10325476; c->n = 0; return 1; }
static int md5_update(Md5* c, const void* d, uint32_t len) { feed<Md5, 64>(c, (const uint8_t*)d, len, md5_block); return 1; }
static int md5_final(uint8_t* md, Md5* c) {
    pad<Md5, 64>(c, md5_block, true, 8);
    for (int i = 0; i < 4; i++) for (int j = 0; j < 4; j++) md[4 * i + j] = (uint8_t)(c->h[i] >> (8 * j));
    return 1;
}
static int sha1_init(Sha1* c) { static const uint32_t iv[5] = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0}; memcpy(c->h, iv, 20); c->n = 0; return 1; }
static int sha1_update(Sha1* c, const void* d, uint32_t len) { feed<Sha1, 64>(c, (const uint8_t*)d, len, sha1_block); return 1; }
static int sha1_final(uint8_t* md, Sha1* c) {
    pad<Sha1, 64>(c, sha1_block, false, 8);
    for (int i = 0; i < 5; i++) for (int j = 0; j < 4; j++) md[4 * i + j] = (uint8_t)(c->h[i] >> (24 - 8 * j));
    return 1;
}
static int sha256_init(Sha256* c) {
    static const uint32_t iv[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    memcpy(c->h, iv, 32); c->n = 0; return 1;
}
static int sha224_init(Sha256* c) {
    static const uint32_t iv[8] = {0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939, 0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4};
    memcpy(c->h, iv, 32); c->n = 0; return 1;
}
static int sha256_update(Sha256* c, const void* d, uint32_t len) { feed<Sha256, 64>(c, (const uint8_t*)d, len, sha256_block); return 1; }
static void sha256_out(uint8_t* md, Sha256* c, int words) {
    pad<Sha256, 64>(c, sha256_block, false, 8);
    for (int i = 0; i < words; i++) for (int j = 0; j < 4; j++) md[4 * i + j] = (uint8_t)(c->h[i] >> (24 - 8 * j));
}
static int sha256_final(uint8_t* md, Sha256* c) { sha256_out(md, c, 8); return 1; }
static int sha224_final(uint8_t* md, Sha256* c) { sha256_out(md, c, 7); return 1; }
static int sha512_init(Sha512* c) {
    static const uint64_t iv[8] = {0x6a09e667f3bcc908ull, 0xbb67ae8584caa73bull, 0x3c6ef372fe94f82bull, 0xa54ff53a5f1d36f1ull,
                                   0x510e527fade682d1ull, 0x9b05688c2b3e6c1full, 0x1f83d9abfb41bd6bull, 0x5be0cd19137e2179ull};
    memcpy(c->h, iv, 64); c->n = 0; return 1;
}
static int sha384_init(Sha512* c) {
    static const uint64_t iv[8] = {0xcbbb9d5dc1059ed8ull, 0x629a292a367cd507ull, 0x9159015a3070dd17ull, 0x152fecd8f70e5939ull,
                                   0x67332667ffc00b31ull, 0x8eb44a8768581511ull, 0xdb0c2e0d64f98fa7ull, 0x47b5481dbefa4fa4ull};
    memcpy(c->h, iv, 64); c->n = 0; return 1;
}
static int sha512_update(Sha512* c, const void* d, uint32_t len) { feed<Sha512, 128>(c, (const uint8_t*)d, len, sha512_block); return 1; }
static void sha512_out(uint8_t* md, Sha512* c, int words) {
    pad<Sha512, 128>(c, sha512_block, false, 16);   // 128-bit length: the high 64 bits stay zero
    for (int i = 0; i < words; i++) for (int j = 0; j < 8; j++) md[8 * i + j] = (uint8_t)(c->h[i] >> (56 - 8 * j));
}
static int sha512_final(uint8_t* md, Sha512* c) { sha512_out(md, c, 8); return 1; }
static int sha384_final(uint8_t* md, Sha512* c) { sha512_out(md, c, 6); return 1; }

// one-shot: CC_X(data, len, md) returns md
#define ONESHOT(NAME, CTX, INIT, UPD, FIN) \
    static uint8_t* NAME(const void* d, uint32_t len, uint8_t* md) { CTX c; INIT(&c); UPD(&c, d, len); FIN(md, &c); return md; }
ONESHOT(cc_md5, Md5, md5_init, md5_update, md5_final)
ONESHOT(cc_sha1, Sha1, sha1_init, sha1_update, sha1_final)
ONESHOT(cc_sha224, Sha256, sha224_init, sha256_update, sha224_final)
ONESHOT(cc_sha256, Sha256, sha256_init, sha256_update, sha256_final)
ONESHOT(cc_sha384, Sha512, sha384_init, sha512_update, sha384_final)
ONESHOT(cc_sha512, Sha512, sha512_init, sha512_update, sha512_final)

void* darwin_commoncrypto_lookup(const char* name) {
    struct E { const char* n; void* f; };
    static const E k[] = {
        {"_CC_MD5_Init", (void*)&md5_init}, {"_CC_MD5_Update", (void*)&md5_update}, {"_CC_MD5_Final", (void*)&md5_final},
        {"_CC_SHA1_Init", (void*)&sha1_init}, {"_CC_SHA1_Update", (void*)&sha1_update}, {"_CC_SHA1_Final", (void*)&sha1_final},
        {"_CC_SHA224_Init", (void*)&sha224_init}, {"_CC_SHA224_Update", (void*)&sha256_update}, {"_CC_SHA224_Final", (void*)&sha224_final},
        {"_CC_SHA256_Init", (void*)&sha256_init}, {"_CC_SHA256_Update", (void*)&sha256_update}, {"_CC_SHA256_Final", (void*)&sha256_final},
        {"_CC_SHA384_Init", (void*)&sha384_init}, {"_CC_SHA384_Update", (void*)&sha512_update}, {"_CC_SHA384_Final", (void*)&sha384_final},
        {"_CC_SHA512_Init", (void*)&sha512_init}, {"_CC_SHA512_Update", (void*)&sha512_update}, {"_CC_SHA512_Final", (void*)&sha512_final},
        {"_CC_MD5", (void*)&cc_md5}, {"_CC_SHA1", (void*)&cc_sha1}, {"_CC_SHA224", (void*)&cc_sha224},
        {"_CC_SHA256", (void*)&cc_sha256}, {"_CC_SHA384", (void*)&cc_sha384}, {"_CC_SHA512", (void*)&cc_sha512},
    };
    for (const E& e : k) if (!strcmp(e.n, name)) return e.f;
    return nullptr;
}

}  // namespace xef
