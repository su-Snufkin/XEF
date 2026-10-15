/* ___sincosf_stret / ___sincos_stret return an HFA of two floats (s0,s1) / doubles (d0,d1) on arm64. */
#include <math.h>
#include <stdio.h>
int main(void) {
  volatile float fx[] = {0.0f, 0.5f, 1.0f, 2.5f, -3.0f, 100.25f};
  volatile double dx[] = {0.0, 0.5, 1.0, 2.5, -3.0, 100.25};
  for (int i = 0; i < 6; i++) {
    struct __float2 f = __sincosf_stret(fx[i]);
    struct __double2 d = __sincos_stret(dx[i]);
    printf("f %.5f sin=%.5f cos=%.5f\n", (double)fx[i], (double)f.__sinval, (double)f.__cosval);
    printf("d %.9f sin=%.9f cos=%.9f\n", dx[i], d.__sinval, d.__cosval);
  }
  return 0;
}
