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
};
extern Stats g_stats;

inline u64 stats_now() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (u64)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}
void stats_print();

}  // namespace xef
