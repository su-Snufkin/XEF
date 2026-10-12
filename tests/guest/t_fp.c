#include <math.h>
#include <stdio.h>
#include <stdlib.h>
int main(void) {
    double s = 0;
    float fs = 0;
    for (int i = 1; i < 20000; i++) {
        double x = i * 0.001;
        s += sin(x) * cos(x * 0.5) + exp(-x) + log(x) + pow(x, 1.3) + sqrt(x) + fmod(x, 0.7) + atan2(x, 1.5);
        s += floor(x * 3.3) + ceil(x * 1.7) + round(x * 2.5) + trunc(-x * 4.4) + rint(x * 9.5);
        fs += sinf((float)x) + sqrtf((float)x) * 0.5f + (float)(long)(x * 10.0f);
        s += (double)(int)(x * 1000.0) / 7 + (double)(unsigned)(x * 10) + (long long)(-x * 1e6);
        s += fma(x, 1.0000001, -x) * 1e6 + fmin(x, 1.0) + fmax(x, 2.0) + fabs(-x) + copysign(x, -1.0);
        s += hypot(x, 2.0) + cbrt(x) + tanh(x - 5) + asin(1 / (x + 1)) + log1p(x) + expm1(x * 0.01);
    }
    printf("%.10g %.6g\n", s, (double)fs);
    printf("%g %g %g %g %e %a %.20f\n", 1.0 / 3, -0.0, INFINITY, 1e300 * 1e10, 12345.678e-20, 0.1, M_PI);
    printf("%f %f %d %d %ld\n", (double)(float)1.1, nextafter(1.0, 2.0), (int)2.9, (int)-2.9, lrint(2.5));
    printf("%.17g %.9g %g\n", strtod("3.14159265358979323846", 0), (double)strtof("2.7182818", 0), atof("1e-5"));
    volatile double z = 0.0;
    printf("isnan=%d isinf=%d %d\n", isnan(z / z), isinf(1 / z), signbit(-z));
    float a[64]; double b[64];
    for (int i = 0; i < 64; i++) { a[i] = i * 1.5f - 20; b[i] = a[i] * a[i]; }
    float sa = 0; double sb = 0;
    for (int i = 0; i < 64; i++) { sa += a[i] * 2 + 1; sb += b[i] / (i + 1); }
    printf("%g %g\n", sa, sb);
    return 0;
}
