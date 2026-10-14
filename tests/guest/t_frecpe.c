// FRECPE / FRSQRTE (single precision: native; double: C helper) against qemu: special values,
// denormals, |x| >= 2^126 (denormal estimates), FPCR.FZ / DN and all rounding modes.
#include <arm_neon.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint32_t f2u(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }
static float u2f(uint32_t u) { float f; memcpy(&f, &u, 4); return f; }
static uint32_t mix(uint32_t acc, float32x4_t r, float32x4_t q) {
    uint32_t a[4], b[4];
    memcpy(a, &r, 16);
    memcpy(b, &q, 16);
    for (int k = 0; k < 4; k++) acc = acc * 31 + a[k] * 7 + b[k];
    return acc;
}
static void setfpcr(uint64_t v) { __asm__ volatile("msr fpcr, %0" ::"r"(v)); }

static const uint32_t in[] = {0x7e800000, 0x7f000000, 0x7f7fffff, 0x7e7fffff, 0x00200000, 0x001fffff, 0x00400000,
                              0x003fffff, 0x00600001, 0x00000001, 0x007fffff, 0x00800000, 0x80000000, 0x00000000,
                              0x7f800000, 0xff800000, 0x7fc00001, 0xffc00001, 0x7f800001, 0xff812345, 0x3f800000,
                              0x40490fdb, 0xc0490fdb, 0x3e800000, 0x80400000, 0x80200000, 0xfe900000};
#define N (int)(sizeof in / sizeof in[0])

int main(void) {
    for (int m = 0; m < 16; m++) {   // FZ, DN, RMode
        setfpcr((uint64_t)(m & 3) << 24 | (uint64_t)(m >> 2) << 22);
        uint32_t acc = 0;
        for (int i = 0; i < N; i++) {
            float32x4_t v = {u2f(in[i]), u2f(in[(i + 1) % N]), u2f(in[(i + 5) % N]), u2f(in[(i + 11) % N])};
            float32x4_t r = vrecpeq_f32(v), q = vrsqrteq_f32(v);
            float32x2_t r2 = vrecpe_f32(vget_low_f32(v)), q2 = vrsqrte_f32(vget_low_f32(v));
            float rs, qs;
            __asm__ volatile("frecpe %s0, %s1" : "=w"(rs) : "w"(u2f(in[i])));
            __asm__ volatile("frsqrte %s0, %s1" : "=w"(qs) : "w"(u2f(in[i])));
            uint64_t dd = (uint64_t)in[i] << 32 | in[(i + 3) % N];
            float64x2_t dv;
            memcpy(&dv, &dd, 8);
            memcpy((char*)&dv + 8, &dd, 8);
            float64x2_t dr = vrecpeq_f64(dv), dq = vrsqrteq_f64(dv);
            uint64_t a1, a2;
            memcpy(&a1, &dr, 8);
            memcpy(&a2, &dq, 8);
            if (m == 0 || m == 3 || m == 12)
                printf("m%d %08x: %08x %08x %08x %08x | %08x %08x | %08x | %08x %08x %08x %08x | %08x | %016llx %016llx\n",
                       m, in[i], f2u(vgetq_lane_f32(r, 0)), f2u(vgetq_lane_f32(r, 1)), f2u(vgetq_lane_f32(r, 2)),
                       f2u(vgetq_lane_f32(r, 3)), f2u(vget_lane_f32(r2, 0)), f2u(vget_lane_f32(r2, 1)), f2u(rs),
                       f2u(vgetq_lane_f32(q, 0)), f2u(vgetq_lane_f32(q, 1)), f2u(vgetq_lane_f32(q, 3)),
                       f2u(vget_lane_f32(q2, 1)), f2u(qs), (unsigned long long)a1, (unsigned long long)a2);
            acc = mix(acc, r, q);
            acc = acc * 31 + (uint32_t)(a1 ^ a1 >> 32 ^ a2 ^ a2 >> 32) + f2u(rs) + f2u(qs);
        }
        uint32_t s = 12345 + m;   // random encodings
        for (int i = 0; i < 100000; i++) {
            s = s * 1103515245u + 12345u;
            uint32_t x = s ^ (s >> 7) * 2654435761u;
            float32x4_t v = {u2f(x), u2f(x >> 9), u2f(x * 3), u2f(~x)};
            float32x4_t r = vrecpeq_f32(v), q = vrsqrteq_f32(v);
            acc = mix(acc, r, q);
        }
        printf("mode %d: %08x\n", m, acc);
    }
    setfpcr(0);
    return 0;
}
