#include "profile/stats.h"

#include "runtime/code_cache.h"

namespace xef {

Stats g_stats;

void stats_print() {
    const Stats& s = g_stats;
    fprintf(stderr,
            "xef stats:\n"
            "  blocks translated   : %lu (tier1) %lu (tier2)\n"
            "  guest insts         : %lu (%.1f per block)\n"
            "  host code           : %lu bytes (%.1f bytes/guest insn)\n"
            "  translation time    : %.3f ms (%.0f ns/block)\n"
            "  exits: link %lu, lookup(ibtc miss) %lu, syscall %lu\n",
            (unsigned long)s.blocks_t1, (unsigned long)s.blocks_t2, (unsigned long)s.guest_insts_translated,
            s.blocks_t1 ? (double)s.guest_insts_translated / s.blocks_t1 : 0.0, (unsigned long)s.host_bytes,
            s.guest_insts_translated ? (double)s.host_bytes / s.guest_insts_translated : 0.0, s.translate_ns / 1e6,
            s.blocks_t1 ? (double)s.translate_ns / s.blocks_t1 : 0.0, (unsigned long)s.exits_link,
            (unsigned long)s.exits_lookup, (unsigned long)s.exits_syscall);
}

}  // namespace xef
