// XEF — tier-2 region compiler (hot loops with a region-specific register mapping).
#pragma once
#include "common/common.h"

namespace xef {

extern int g_tier2_threshold;   // SIGPROF samples (1 ms CPU each) before a block is promoted
void tier2_init(bool enable);
// In a forked child: restart the compiler thread (it does not survive fork).
struct ThreadCtx;
void tier2_after_fork(ThreadCtx* t);
void tier2_thread_start(ThreadCtx* t);   // per-thread sampling timer (signals this thread)
void tier2_thread_stop(ThreadCtx* t);

}  // namespace xef
