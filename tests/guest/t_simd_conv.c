// NEON ops with native x86 code paths: conversions (UCVTF/FCVTZU incl. fixed point, FRINTX),
// variable shifts (USHL), absolute differences (UABD/SABD/UABDL/SABDL) and halving adds.
#include <arm_neon.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint64_t rng = 0x9e3779b97f4a7c15ull;
static uint32_t rnd32(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return (uint32_t)rng; }
static uint64_t h = 1469598103934665603ull;
static void mix(const void* p, int n) { const uint8_t* b = p; for (int i = 0; i < n; i++) h = (h ^ b[i]) * 1099511628211ull; }

static float special(int k) {
    static const float s[] = {0.0f, -0.0f, 0.5f, 1.5f, 2.5f, -2.5f, 4294967295.0f, 4294967296.0f, 2147483648.0f,
                              -1.0f, 1e30f, -1e30f, INFINITY, -INFINITY, NAN, 3.999f, 65535.5f, 1e-20f};
    return s[k % (sizeof s / sizeof s[0])];
}

int main(void) {
    for (int it = 0; it < 4000; it++) {
        uint32_t u[4], w[4];
        float f[4];
        for (int i = 0; i < 4; i++) {
            u[i] = rnd32(); w[i] = rnd32();
            uint32_t r = rnd32();
            f[i] = (r & 3) == 0 ? special(r >> 2) : ((float)(int32_t)rnd32() / (float)(1 + (r >> 20)));
        }
        if (it & 1) { u[0] = 0xffffffffu; u[1] = 0x80000000u; u[2] = 0x00ffffffu; u[3] = 0x01000001u; }
        uint32x4_t vu = vld1q_u32(u), vw = vld1q_u32(w);
        float32x4_t vf = vld1q_f32(f);
        float32x4_t c1 = vcvtq_f32_u32(vu);
        uint32x4_t c2 = vcvtq_u32_f32(vf);
        uint32x4_t c3 = vcvtq_n_u32_f32(vf, 8);
        uint32x4_t c4 = vcvtq_n_u32_f32(vf, 31);
        float32x4_t c5 = vrndxq_f32(vf);
        int32x4_t sh = vreinterpretq_s32_u32(vandq_u32(vw, vdupq_n_u32(0x800000ff)));
        sh = vsubq_s32(vandq_s32(sh, vdupq_n_s32(0x7f)), vdupq_n_s32(48));   // -48..79: in/out of range
        uint32x4_t c6 = vshlq_u32(vu, sh);
        uint8x16_t b8 = vreinterpretq_u8_u32(vu), c8 = vreinterpretq_u8_u32(vw);
        uint16x8_t b16 = vreinterpretq_u16_u32(vu), c16 = vreinterpretq_u16_u32(vw);
        uint8x16_t d1 = vabdq_u8(b8, c8);
        uint16x8_t d2 = vabdq_u16(b16, c16);
        uint32x4_t d3 = vabdq_u32(vu, vw);
        int8x16_t d4 = vabdq_s8(vreinterpretq_s8_u8(b8), vreinterpretq_s8_u8(c8));
        int32x4_t d5 = vabdq_s32(vreinterpretq_s32_u32(vu), vreinterpretq_s32_u32(vw));
        uint16x8_t d6 = vabdl_u8(vget_low_u8(b8), vget_low_u8(c8));
        uint16x8_t d7 = vabdl_high_u8(b8, c8);
        uint32x4_t d8 = vabdl_u16(vget_low_u16(b16), vget_low_u16(c16));
        int16x8_t d9 = vabdl_s8(vget_low_s8(vreinterpretq_s8_u8(b8)), vget_low_s8(vreinterpretq_s8_u8(c8)));
        uint8x16_t e1 = vhaddq_u8(b8, c8);
        uint16x8_t e2 = vhaddq_u16(b16, c16);
        uint8x8_t e3 = vhadd_u8(vget_low_u8(b8), vget_high_u8(c8));
        // float results compared by bit pattern except NaN payloads
        uint32_t fb[8];
        memcpy(fb, &c1, 16);
        memcpy(fb + 4, &c5, 16);
        for (int i = 0; i < 8; i++) if ((fb[i] & 0x7f800000) == 0x7f800000 && (fb[i] & 0x7fffff)) fb[i] = 0x7fc00000;
        mix(fb, 32);
        mix(&c2, 16); mix(&c3, 16); mix(&c4, 16); mix(&c6, 16);
        mix(&d1, 16); mix(&d2, 16); mix(&d3, 16); mix(&d4, 16); mix(&d5, 16); mix(&d6, 16); mix(&d7, 16);
        mix(&d8, 16); mix(&d9, 16); mix(&e1, 16); mix(&e2, 16); mix(&e3, 8);
        if (it < 3) {
            printf("it%d ucvtf %a %a fcvtzu %u %u n8 %u n31 %u rndx %a ushl %08x\n", it, vgetq_lane_f32(c1, 0),
                   vgetq_lane_f32(c1, 1), vgetq_lane_u32(c2, 0), vgetq_lane_u32(c2, 3), vgetq_lane_u32(c3, 1),
                   vgetq_lane_u32(c4, 2), vgetq_lane_f32(c5, 0), vgetq_lane_u32(c6, 0));
        }
    }
    printf("hash %016llx\n", (unsigned long long)h);
    return 0;
}
