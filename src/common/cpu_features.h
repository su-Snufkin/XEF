// Host CPU feature detection (runtime, via CPUID).
#pragma once
#include "common/common.h"

namespace xef {

struct HostFeatures {
    bool sse41 = false, sse42 = false, popcnt = false;
    bool avx = false, avx2 = false, bmi1 = false, bmi2 = false;
    bool lzcnt = false, fma = false, f16c = false;
    bool cmpxchg16b = false, fsgsbase = false;
    bool aes = false, pclmul = false, sha = false;
};

extern HostFeatures g_host;
void detect_host_features();

}  // namespace xef
