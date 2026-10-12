// NEON ops with native x86 paths: half<->single conversions, 64-bit USHL, SLI/SRI,
// (rounding/saturating) narrowing shifts, SQXTUN, ADDHN/SUBHN, SQRDMULH, FRINTA.
#include <arm_neon.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint64_t rng = 0x243f6a8885a308d3ull;
static uint64_t rnd64(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; }
static uint64_t h = 1469598103934665603ull;
static void mix(const void* p, int n) { const uint8_t* b = p; for (int i = 0; i < n; i++) h = (h ^ b[i]) * 1099511628211ull; }
#define MIX(x) do { __typeof__(x) _t = (x); mix(&_t, sizeof _t); } while (0)

static float fspecial(uint32_t r) {
    static const float s[] = {0.0f, -0.0f, 0.5f, 1.5f, 2.5f, -2.5f, -0.5f, 65504.0f, 65520.0f, 1e-7f, 6e-8f,
                              3e-5f, INFINITY, -INFINITY, 1e10f, 0.49999997f, 8388607.5f};
    return s[r % (sizeof s / sizeof s[0])];
}

int main(void) {
    for (int it = 0; it < 3000; it++) {
        uint64_t q[2] = {rnd64(), rnd64()}, w[2] = {rnd64(), rnd64()};
        float f[4];
        double dd[2];
        for (int i = 0; i < 4; i++) {
            uint32_t r = (uint32_t)rnd64();
            f[i] = (r & 1) ? fspecial(r >> 1) : (float)((int32_t)rnd64()) / (float)(1 + (r >> 16));
        }
        for (int i = 0; i < 2; i++) dd[i] = (it & 1) ? (double)fspecial((uint32_t)rnd64()) : (double)(int64_t)rnd64() / 1e9;
        uint8x16_t u8 = vreinterpretq_u8_u64(vld1q_u64(q)), v8 = vreinterpretq_u8_u64(vld1q_u64(w));
        uint16x8_t u16 = vreinterpretq_u16_u8(u8), v16 = vreinterpretq_u16_u8(v8);
        uint32x4_t u32 = vreinterpretq_u32_u8(u8), v32 = vreinterpretq_u32_u8(v8);
        uint64x2_t u64 = vld1q_u64(q), v64 = vld1q_u64(w);
        int16x8_t s16 = vreinterpretq_s16_u8(u8), t16 = vreinterpretq_s16_u8(v8);
        int32x4_t s32 = vreinterpretq_s32_u8(u8);
        float32x4_t vf = vld1q_f32(f);
        // half <-> single (values from random bits too: NaN payloads normalized below)
        float16x4_t hf = vcvt_f16_f32(vf);
        MIX(hf);
        float32x4_t back = vcvt_f32_f16(vreinterpret_f16_u16(vget_low_u16(u16)));
        uint32_t bb[4]; memcpy(bb, &back, 16);
        for (int i = 0; i < 4; i++) if ((bb[i] & 0x7f800000) == 0x7f800000 && (bb[i] & 0x7fffff)) bb[i] = 0x7fc00000;
        mix(bb, 16);
        MIX(vcvt_high_f16_f32(hf, vf));
        // 64-bit USHL with in/out of range counts
        int64x2_t c64 = vreinterpretq_s64_u64(vandq_u64(v64, vdupq_n_u64(0xff)));
        MIX(vshlq_u64(u64, c64));
        MIX(vshlq_u64(u64, vdupq_n_s64(-3)));
        // shift-insert
        MIX(vsliq_n_u8(u8, v8, 3)); MIX(vsriq_n_u8(u8, v8, 5)); MIX(vsliq_n_u16(u16, v16, 9));
        MIX(vsriq_n_u16(u16, v16, 16)); MIX(vsliq_n_u32(u32, v32, 31)); MIX(vsriq_n_u32(u32, v32, 1));
        MIX(vsliq_n_u64(u64, v64, 17)); MIX(vsriq_n_u64(u64, v64, 63)); MIX(vsri_n_u8(vget_low_u8(u8), vget_low_u8(v8), 8));
        // narrowing
        MIX(vrshrn_n_u16(u16, 3)); MIX(vrshrn_n_u32(u32, 16)); MIX(vrshrn_n_u32(u32, 1)); MIX(vrshrn_high_n_u16(vget_low_u8(v8), u16, 8));
        MIX(vqrshrn_n_s16(s16, 1)); MIX(vqrshrn_n_s16(s16, 8)); MIX(vqrshrn_n_s32(s32, 5)); MIX(vqshrn_n_s16(s16, 2));
        MIX(vqshrn_n_s32(s32, 16));
        MIX(vqmovun_s16(s16)); MIX(vqmovun_s32(s32)); MIX(vqmovun_high_s16(vget_low_u8(v8), s16));
        MIX(vaddhn_u16(u16, v16)); MIX(vsubhn_u32(u32, v32)); MIX(vaddhn_u64(u64, v64)); MIX(vaddhn_high_u16(vget_low_u8(u8), u16, v16));
        int16x8_t m16 = (it & 3) == 0 ? vdupq_n_s16(-32768) : s16;
        MIX(vqrdmulhq_s16(m16, (it & 3) == 0 ? vdupq_n_s16(-32768) : t16)); MIX(vqrdmulh_s16(vget_low_s16(s16), vget_low_s16(t16)));
        // round to nearest, ties away
        MIX(vrndaq_f32(vf)); MIX(vrndaq_f64(vld1q_f64(dd))); MIX(vrnda_f32(vget_low_f32(vf)));
        float sf = f[0]; double sd = dd[0];
        __asm__("frinta %s0, %s0" : "+w"(sf)); __asm__("frinta %d0, %d0" : "+w"(sd));
        MIX(sf); MIX(sd);
        if (it < 2) printf("it%d h=%016llx\n", it, (unsigned long long)h);
    }
    printf("hash %016llx\n", (unsigned long long)h);
    return 0;
}
