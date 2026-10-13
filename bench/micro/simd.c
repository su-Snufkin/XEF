// Auto-vectorized loops (built with -O3 like the rest of the suite's flags allow): float saxpy and
// dot products, int8/int16 image-style kernels, min/max/abs, conversions, a small float GEMM and
// a byte histogram-free blend. Exercises NEON code generation (and the C-helper fallbacks).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define N 4096
static float fa[N], fb[N], fc[N];
static int16_t sa[N], sb[N], sc[N];
static uint8_t ua[N], ub[N], uc[N];
static int32_t ia[N], ib[N];
static double da[N], db[N];

__attribute__((noinline)) static void saxpy(float a, const float* x, float* y, int n) {
    for (int i = 0; i < n; i++) y[i] = a * x[i] + y[i];
}
__attribute__((noinline)) static float dot(const float* x, const float* y, int n) {
    float s = 0;
    for (int i = 0; i < n; i++) s += x[i] * y[i];
    return s;
}
__attribute__((noinline)) static void blend_u8(const uint8_t* a, const uint8_t* b, uint8_t* o, uint8_t alpha, int n) {
    for (int i = 0; i < n; i++) o[i] = (uint8_t)((a[i] * alpha + b[i] * (255 - alpha) + 128) >> 8);
}
__attribute__((noinline)) static void sat_add_s16(const int16_t* a, const int16_t* b, int16_t* o, int n) {
    for (int i = 0; i < n; i++) {
        int v = a[i] + b[i];
        o[i] = v > 32767 ? 32767 : v < -32768 ? -32768 : v;
    }
}
__attribute__((noinline)) static int32_t sad_u8(const uint8_t* a, const uint8_t* b, int n) {
    int32_t s = 0;
    for (int i = 0; i < n; i++) s += abs(a[i] - b[i]);
    return s;
}
__attribute__((noinline)) static void clampf(float* x, float lo, float hi, int n) {
    for (int i = 0; i < n; i++) x[i] = fminf(fmaxf(x[i], lo), hi);
}
__attribute__((noinline)) static void i2f(const int32_t* a, float* o, int n) {
    for (int i = 0; i < n; i++) o[i] = (float)a[i] * 0.5f;
}
__attribute__((noinline)) static void f2i(const float* a, int32_t* o, int n) {
    for (int i = 0; i < n; i++) o[i] = (int32_t)(a[i] * 3.0f);
}
__attribute__((noinline)) static double daxpy_sum(const double* x, double* y, double a, int n) {
    double s = 0;
    for (int i = 0; i < n; i++) { y[i] += a * x[i]; s += y[i]; }
    return s;
}
#define M 64
static float A[M][M], B[M][M], C[M][M];
__attribute__((noinline)) static void gemm(void) {
    for (int i = 0; i < M; i++)
        for (int k = 0; k < M; k++) {
            float a = A[i][k];
            for (int j = 0; j < M; j++) C[i][j] += a * B[k][j];
        }
}

int main(void) {
    for (int i = 0; i < N; i++) {
        fa[i] = (float)(i % 97) * 0.01f; fb[i] = (float)(i % 31) * 0.1f; fc[i] = 0;
        sa[i] = (int16_t)(i * 37); sb[i] = (int16_t)(i * 91 - 20000);
        ua[i] = (uint8_t)(i * 7); ub[i] = (uint8_t)(i * 13 + 5);
        ia[i] = i * 3 - 5000; da[i] = i * 0.001; db[i] = 0;
    }
    for (int i = 0; i < M; i++) for (int j = 0; j < M; j++) { A[i][j] = (i + j) % 5; B[i][j] = (i * j) % 7 * 0.5f; }
    double acc = 0;
    long iacc = 0;
    for (int r = 0; r < 20000; r++) {
        saxpy(1.0001f, fa, fc, N);
        acc += dot(fa, fb, N);
        blend_u8(ua, ub, uc, (uint8_t)r, N);
        sat_add_s16(sa, sb, sc, N);
        iacc += sad_u8(ua, uc, N);
        clampf(fc, -100.0f, 100.0f, N);
        i2f(ia, fb, N);
        f2i(fc, ib, N);
        iacc += ib[r % N] + sc[r % N];
        acc += daxpy_sum(da, db, 1e-6, N);
        if (r % 30 == 0) gemm();
    }
    printf("%.6g %ld %.6g %u\n", acc, iacc, C[5][7], uc[100]);
    return 0;
}
