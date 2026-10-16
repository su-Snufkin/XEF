// <fenv.h> on arm64: 16-byte fenv_t (the bytes after it stay untouched), rounding modes, exception flags
#include <fenv.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static volatile double zero = 0.0, one = 1.0, big = 1e308, tiny = 1e-308;

int main(void) {
    struct { fenv_t env; unsigned char guard[32]; } s;
    memset(&s, 0xAB, sizeof s);
    printf("sizeof fenv_t %zu, fegetenv %d\n", sizeof(fenv_t), fegetenv(&s.env));
    int intact = 1;
    for (int i = 0; i < 32; i++) intact &= s.guard[i] == 0xAB;
    printf("guard intact %d\n", intact);

    int modes[4] = {FE_TONEAREST, FE_UPWARD, FE_DOWNWARD, FE_TOWARDZERO};
    for (int i = 0; i < 4; i++) {
        fesetround(modes[i]);
        volatile double a = 1.0, b = 3.0;
        printf("round %#x: get %#x 1/3 %.17g -1/3 %.17g rint(2.5) %g\n", modes[i], fegetround(), a / b, -a / b, rint(2.5));
    }
    fesetround(FE_TONEAREST);

    feclearexcept(FE_ALL_EXCEPT);
    volatile double r = one / zero; (void)r;
    printf("div by zero -> %#x\n", fetestexcept(FE_ALL_EXCEPT) & (FE_DIVBYZERO | FE_INVALID | FE_OVERFLOW));
    feclearexcept(FE_ALL_EXCEPT);
    r = zero / zero;
    printf("0/0 -> %#x\n", fetestexcept(FE_INVALID | FE_DIVBYZERO));
    feclearexcept(FE_ALL_EXCEPT);
    r = big * 10;
    printf("overflow -> %#x\n", fetestexcept(FE_OVERFLOW));
    feclearexcept(FE_ALL_EXCEPT);
    r = tiny / 1e10;
    printf("underflow -> %#x\n", fetestexcept(FE_UNDERFLOW));
    feclearexcept(FE_ALL_EXCEPT);
    feraiseexcept(FE_INEXACT | FE_OVERFLOW);
    printf("raised -> %#x\n", fetestexcept(FE_ALL_EXCEPT));

    fenv_t held;
    feholdexcept(&held);
    printf("after feholdexcept %#x\n", fetestexcept(FE_ALL_EXCEPT));
    r = one / zero;
    feupdateenv(&held);
    printf("after feupdateenv %#x\n", fetestexcept(FE_DIVBYZERO | FE_INEXACT | FE_OVERFLOW));

    fesetround(FE_UPWARD);
    fesetenv(FE_DFL_ENV);
    printf("FE_DFL_ENV: round %#x flags %#x\n", fegetround(), fetestexcept(FE_ALL_EXCEPT));
    fexcept_t fl;
    feraiseexcept(FE_INVALID);
    fegetexceptflag(&fl, FE_ALL_EXCEPT);
    feclearexcept(FE_ALL_EXCEPT);
    fesetexceptflag(&fl, FE_INVALID);
    printf("exceptflag roundtrip %#x\n", fetestexcept(FE_ALL_EXCEPT));
    printf("bad round %d\n", fesetround(0x123));
    return 0;
}
