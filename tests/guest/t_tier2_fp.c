// Hot FP / NEON loops that run long enough to be compiled as tier-2 regions (guest V registers
// pinned in XMM registers, constants written to pinned registers, fast FCMP conditions).
#include <arm_neon.h>
#include <stdio.h>

static int mandel(int w, int h) {
    int inside = 0;
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++) {
            float cr = x / (w / 3.0f) - 2.0f, ci = y / (h / 2.0f) - 1.0f, zr = 0, zi = 0;
            int it = 0;
            while (it < 200 && zr * zr + zi * zi < 4.0f) {
                float t = zr * zr - zi * zi + cr;
                zi = 2 * zr * zi + ci;
                zr = t;
                it++;
            }
            inside += it == 200;
        }
    return inside;
}

static double mandel_d(int w, int h) {
    double sum = 0;
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++) {
            double cr = x * (3.0 / w) - 2.0, ci = y * (2.0 / h) - 1.0, zr = 0, zi = 0;
            int it = 0;
            while (it < 100 && !(zr * zr + zi * zi >= 4.0)) {
                double t = zr * zr - zi * zi + cr;
                zi = 2 * zr * zi + ci;
                zr = t;
                it++;
            }
            sum += it > 50 ? zr : -zi;
        }
    return sum;
}

static float neon_loop(int n) {
    float32x4_t acc = vdupq_n_f32(0), k = vdupq_n_f32(0.25f), one = vdupq_n_f32(1.0f);
    float32x4_t x = {1, 2, 3, 4};
    for (int i = 0; i < n; i++) {
        float32x4_t y = vmlaq_f32(one, x, k);
        acc = vaddq_f32(acc, vmulq_f32(y, y));
        x = vbslq_f32(vcltq_f32(x, vdupq_n_f32(100.0f)), vaddq_f32(x, one), vdupq_n_f32(0));
        if (vgetq_lane_f32(acc, 0) > 1e6f) acc = vdupq_n_f32(0);
    }
    return vaddvq_f32(acc);
}

static long int_mix(int n) {
    int32x4_t a = {1, 2, 3, 4}, b = vdupq_n_s32(7);
    long s = 0;
    for (int i = 0; i < n; i++) {
        a = vaddq_s32(vmulq_s32(a, b), vdupq_n_s32(i & 15));
        a = vandq_s32(a, vdupq_n_s32(0xffff));
        int32_t l[4];
        vst1q_s32(l, a);
        float f = (float)l[i & 3];
        s += f < 30000.0f ? 1 : f > 60000.0f ? 3 : 2;
    }
    return s + vaddvq_s32(a);
}

int main(void) {
    for (int r = 0; r < 2; r++) {
        printf("mandel %d\n", mandel(800, 600));
        printf("mandel_d %.6f\n", mandel_d(160, 120));
        printf("neon %.3f\n", neon_loop(2000000));
        printf("int_mix %ld\n", int_mix(2000000));
    }
    return 0;
}
