// FMAXNM / FMINNM (vector, scalar, pairwise, across lanes) with quiet and signaling NaNs, signed
// zeros and infinities: a signaling NaN is propagated (quieted, first operand first), a quiet NaN
// is a missing value. Bit patterns are printed (compared with qemu).
#include <arm_neon.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const uint32_t s_vals[] = {0x00000000, 0x80000000, 0x3f800000, 0xbf800000, 0x7f800000, 0xff800000,
                                  0x7fc00000, 0xffc00001, 0x7fa00000, 0xff800001, 0x7f800001, 0x40490fdb};
static const uint64_t d_vals[] = {0x0000000000000000ull, 0x8000000000000000ull, 0x3ff0000000000000ull,
                                  0xfff0000000000000ull, 0x7ff8000000000000ull, 0x7ff4000000000000ull,
                                  0xfff0000000000001ull, 0x400921fb54442d18ull};
#define NS (sizeof s_vals / sizeof s_vals[0])
#define ND (sizeof d_vals / sizeof d_vals[0])

static float f32(uint32_t b) { float f; memcpy(&f, &b, 4); return f; }
static uint32_t b32(float f) { uint32_t b; memcpy(&b, &f, 4); return b; }

int main(void) {
    uint64_t h = 0;   // hash of all results, plus a few printed lines
    // vector 4S: every pair (i, j) in lane k = (i + j) & 3 of otherwise ordinary vectors
    for (unsigned i = 0; i < NS; i++)
        for (unsigned j = 0; j < NS; j++) {
            float a[4] = {1.5f, -2.0f, 3.0f, 0.25f}, b[4] = {-1.0f, 2.5f, 3.0f, -0.0f};
            int k = (i + j) & 3;
            a[k] = f32(s_vals[i]);
            b[k] = f32(s_vals[j]);
            float32x4_t va = vld1q_f32(a), vb = vld1q_f32(b);
            float r[6][4];
            vst1q_f32(r[0], vmaxnmq_f32(va, vb));
            vst1q_f32(r[1], vminnmq_f32(va, vb));
            vst1q_f32(r[2], vpmaxnmq_f32(va, vb));
            vst1q_f32(r[3], vpminnmq_f32(va, vb));
            r[4][0] = vmaxnmvq_f32(va);
            r[4][1] = vminnmvq_f32(vb);
            r[4][2] = __builtin_fmaxf(a[k], b[k]);   // scalar FMAXNM
            r[4][3] = __builtin_fminf(a[k], b[k]);
            float32x2_t ha = vget_low_f32(va), hb = vget_low_f32(vb);
            vst1_f32(r[5], vmaxnm_f32(ha, hb));
            vst1_f32(r[5] + 2, vpminnm_f32(ha, hb));
            for (int x = 0; x < 6; x++)
                for (int y = 0; y < 4; y++) h = (h * 1000003u) ^ b32(r[x][y]);
            if (i == 8 || j == 8)   // signaling NaN involved
                printf("s %08x %08x: max %08x min %08x maxv %08x\n", s_vals[i], s_vals[j], b32(r[0][k]), b32(r[1][k]),
                       b32(r[4][0]));
        }
    // vector 2D and scalar D
    for (unsigned i = 0; i < ND; i++)
        for (unsigned j = 0; j < ND; j++) {
            double a[2] = {1.5, -2.0}, b[2] = {-1.0, 2.5};
            int k = (i + j) & 1;
            memcpy(&a[k], &d_vals[i], 8);
            memcpy(&b[k], &d_vals[j], 8);
            float64x2_t va = vld1q_f64(a), vb = vld1q_f64(b);
            double r[4][2];
            vst1q_f64(r[0], vmaxnmq_f64(va, vb));
            vst1q_f64(r[1], vminnmq_f64(va, vb));
            vst1q_f64(r[2], vpmaxnmq_f64(va, vb));
            r[3][0] = __builtin_fmax(a[k], b[k]);
            r[3][1] = __builtin_fmin(a[k], b[k]);
            for (int x = 0; x < 4; x++)
                for (int y = 0; y < 2; y++) {
                    uint64_t bits;
                    memcpy(&bits, &r[x][y], 8);
                    h = (h * 1000003u) ^ bits;
                }
            if (i == 5 || j == 5) {
                uint64_t m0, m1;
                memcpy(&m0, &r[0][k], 8);
                memcpy(&m1, &r[1][k], 8);
                printf("d %016llx %016llx: max %016llx min %016llx\n", (unsigned long long)d_vals[i],
                       (unsigned long long)d_vals[j], (unsigned long long)m0, (unsigned long long)m1);
            }
        }
    printf("hash %016llx\n", (unsigned long long)h);
    return 0;
}
