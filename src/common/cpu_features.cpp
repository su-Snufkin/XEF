#include "common/cpu_features.h"

#include <cpuid.h>

namespace xef {

HostFeatures g_host;

static u64 xgetbv0() {
    u32 lo, hi;
    __asm__ volatile("xgetbv" : "=a"(lo), "=d"(hi) : "c"(0));
    return ((u64)hi << 32) | lo;
}

void detect_host_features() {
    u32 a, b, c, d;
    if (!__get_cpuid(1, &a, &b, &c, &d)) return;
    g_host.sse41 = c & bit_SSE4_1;
    g_host.sse42 = c & bit_SSE4_2;
    g_host.popcnt = c & bit_POPCNT;
    g_host.cmpxchg16b = c & bit_CMPXCHG16B;
    g_host.aes = c & bit_AES;
    g_host.pclmul = c & bit_PCLMUL;
    g_host.fma = c & bit_FMA;
    g_host.f16c = c & bit_F16C;
    bool osxsave = c & bit_OSXSAVE;
    bool avx_os = osxsave && (xgetbv0() & 6) == 6;
    g_host.avx = (c & bit_AVX) && avx_os;
    if (!g_host.avx) g_host.fma = g_host.f16c = false;
    if (__get_cpuid_count(7, 0, &a, &b, &c, &d)) {
        g_host.avx2 = (b & bit_AVX2) && g_host.avx;
        g_host.bmi1 = b & bit_BMI;
        g_host.bmi2 = b & bit_BMI2;
        g_host.fsgsbase = b & bit_FSGSBASE;
        g_host.sha = b & bit_SHA;
    }
    if (__get_cpuid(0x80000001, &a, &b, &c, &d)) g_host.lzcnt = c & bit_LZCNT;
    if (getenv("XEF_NO_AVX")) g_host.avx = g_host.avx2 = g_host.fma = g_host.f16c = false;
    if (getenv("XEF_NO_BMI")) g_host.bmi1 = g_host.bmi2 = false;
}

}  // namespace xef
