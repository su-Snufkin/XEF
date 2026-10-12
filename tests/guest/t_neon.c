#include <arm_neon.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static uint32_t hash = 2166136261u;
static void mix(const void* p, int n) { for (int i = 0; i < n; i++) { hash ^= ((uint8_t*)p)[i]; hash *= 16777619u; } }
int main(void) {
    uint8_t a[64], b[64];
    for (int i = 0; i < 64; i++) { a[i] = (uint8_t)(i * 37 + 11); b[i] = (uint8_t)(255 - i * 13); }
    uint8x16_t va = vld1q_u8(a), vb = vld1q_u8(b);
    uint8x16_t r = vaddq_u8(va, vb); mix(&r, 16);
    r = vqaddq_u8(va, vb); mix(&r, 16); r = vqsubq_u8(va, vb); mix(&r, 16);
    r = vmaxq_u8(va, vb); mix(&r, 16); r = vminq_u8(va, vb); mix(&r, 16);
    r = vceqq_u8(va, vb); mix(&r, 16); r = vcgtq_u8(va, vb); mix(&r, 16);
    r = vcntq_u8(va); mix(&r, 16); r = vrbitq_u8(va); mix(&r, 16); r = vrev64q_u8(va); mix(&r, 16);
    r = vqtbl1q_u8(va, vandq_u8(vb, vdupq_n_u8(31))); mix(&r, 16);
    r = vextq_u8(va, vb, 5); mix(&r, 16); r = vzip1q_u8(va, vb); mix(&r, 16); r = vuzp2q_u8(va, vb); mix(&r, 16);
    uint8_t mx = vmaxvq_u8(va), mn = vminvq_u8(vb); uint16_t sm = vaddlvq_u8(va); mix(&mx, 1); mix(&mn, 1); mix(&sm, 2);
    uint16x8_t w = vmull_u8(vget_low_u8(va), vget_low_u8(vb)); mix(&w, 16);
    w = vpaddlq_u8(va); mix(&w, 16); w = vshlq_n_u16(w, 3); mix(&w, 16);
    uint8x8_t n8 = vshrn_n_u16(w, 4); mix(&n8, 8); n8 = vqmovn_u16(w); mix(&n8, 8);
    int16x8_t s16 = vreinterpretq_s16_u16(w);
    s16 = vqdmulhq_s16(s16, vdupq_n_s16(12345)); mix(&s16, 16);
    int32x4_t s32 = vmovl_s16(vget_high_s16(s16)); mix(&s32, 16);
    s32 = vmlaq_s32(s32, s32, vdupq_n_s32(-7)); mix(&s32, 16);
    float32x4_t f = vcvtq_f32_s32(s32); mix(&f, 16);
    f = vmulq_f32(f, vdupq_n_f32(0.25f)); f = vaddq_f32(f, vrndmq_f32(f)); mix(&f, 16);
    f = vfmaq_f32(f, f, vdupq_n_f32(1.5f)); mix(&f, 16);
    float sumf = vaddvq_f32(f); mix(&sumf, 4);
    float32x4_t sq = vsqrtq_f32(vabsq_f32(f)); mix(&sq, 16);
    int32x4_t ci = vcvtq_s32_f32(f); mix(&ci, 16);
    float64x2_t d = vcvt_f64_f32(vget_low_f32(f)); d = vdivq_f64(d, vdupq_n_f64(3.0)); mix(&d, 16);
    uint32x4_t cmp = vcgeq_f32(f, vdupq_n_f32(0)); mix(&cmp, 16);
    uint8x16x2_t z = vld2q_u8(a); mix(&z, 32);
    uint8x16x4_t z4 = vld4q_u8(a); mix(&z4, 64);
    uint8_t out[64]; vst2q_u8(out, z); mix(out, 32); vst4q_u8(out, z4); mix(out, 64);
    uint16x4x3_t t3 = vld3_u16((uint16_t*)a); mix(&t3, 24);
    // auto-vectorizable loops
    int16_t x[1024], y[1024]; int32_t dot = 0; float fx[1024], fy = 0;
    for (int i = 0; i < 1024; i++) { x[i] = (int16_t)(i * 31 - 9000); y[i] = (int16_t)(i ^ 0x55); fx[i] = i * 0.5f; }
    for (int i = 0; i < 1024; i++) dot += x[i] * y[i];
    for (int i = 0; i < 1024; i++) fy += fx[i] * fx[i];
    for (int i = 0; i < 1024; i++) x[i] = x[i] > y[i] ? x[i] : (int16_t)(y[i] >> 1);
    mix(x, sizeof x);
    printf("neon hash=%08x dot=%d fy=%g\n", hash, dot, fy);
    return 0;
}
