// XEF — tier-2 region compiler (hot loops with a region-specific register mapping).
#pragma once
#include "common/common.h"

namespace xef {

extern int g_tier2_threshold;   // SIGPROF samples (1 ms CPU each) before a block is promoted
void tier2_init(bool enable);

}  // namespace xef
