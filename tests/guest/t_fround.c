// FP rounding modes (fesetround -> FPCR.RMode -> host MXCSR): CGAL's interval arithmetic checks them.
#include <fenv.h>
#include <stdio.h>
#include <math.h>
int main(void) {
    volatile double a = 1.0, b = 3.0, n = -1.0;
    int modes[] = {FE_TONEAREST, FE_UPWARD, FE_DOWNWARD, FE_TOWARDZERO};
    for (int i = 0; i < 4; i++) {
        fesetround(modes[i]);
        volatile double q = a / b, r = n / b;
        volatile float f = (float)q;
        printf("%d %.20g %.20g %.10g %ld %g\n", fegetround() == modes[i], q, r, f, lrint(2.5), nearbyint(-2.5));
    }
    return 0;
}
