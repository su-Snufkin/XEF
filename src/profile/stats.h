// XEF — profiling counters (--stats).
#pragma once
#include <time.h>

#include "common/common.h"

namespace xef {

struct Stats {
    u64 blocks_t1 = 0, blocks_t2 = 0;
    u64 guest_insts_translated = 0;
    u64 host_bytes = 0;
    u64 translate_ns = 0;
    u64 exits_link = 0, exits_lookup = 0, exits_syscall = 0;
    u64 regions = 0, regions_demoted = 0;
    u64 invalidations = 0;
    u64 inval_requests = 0, inval_unmarked = 0;   // cache maintenance / unmap calls, and those with no code
};
extern Stats g_stats;

inline u64 stats_now() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (u64)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}
void stats_print();
void profile_start();
void profile_sample(u8* rip);
void profile_report();

}  // namespace xef
