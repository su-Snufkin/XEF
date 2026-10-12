#include "profile/stats.h"

#include <signal.h>
#include <sys/time.h>
#include <ucontext.h>

#include <algorithm>
#include <vector>

#include "runtime/code_cache.h"

namespace xef {

Stats g_stats;

// ---- sampling profiler (--profile): SIGPROF every 1 ms CPU time, host RIP recorded ----
static constexpr int kMaxSamples = 1 << 22;
static u64* g_samples;
static volatile int g_nsamples;

static void prof_handler(int, siginfo_t*, void* ctx) {
    int i = g_nsamples;
    if (i < kMaxSamples) { g_samples[i] = (u64)((ucontext_t*)ctx)->uc_mcontext.gregs[REG_RIP]; g_nsamples = i + 1; }
}

void profile_start() {
    g_samples = new u64[kMaxSamples];
    struct sigaction sa {};
    sa.sa_sigaction = prof_handler;
    sa.sa_flags = SA_SIGINFO | SA_RESTART;
    sigaction(SIGPROF, &sa, nullptr);
    struct itimerval it {};
    it.it_interval.tv_usec = 1000;
    it.it_value.tv_usec = 1000;
    setitimer(ITIMER_PROF, &it, nullptr);
}

void profile_report() {
    if (!g_samples) return;
    struct itimerval it {};
    setitimer(ITIMER_PROF, &it, nullptr);
    int n = g_nsamples, in_jit = 0;
    std::vector<std::pair<BlockMeta*, int>> counts;
    std::vector<BlockMeta*> blocks;
    for (int i = 0; i < n; i++) {
        u8* p = (u8*)g_samples[i];
        if (!g_cache.contains(p)) continue;
        in_jit++;
        if (BlockMeta* b = g_cache.find_by_host(p)) blocks.push_back(b);
    }
    std::sort(blocks.begin(), blocks.end());
    for (size_t i = 0; i < blocks.size();) {
        size_t j = i;
        while (j < blocks.size() && blocks[j] == blocks[i]) j++;
        counts.push_back({blocks[i], (int)(j - i)});
        i = j;
    }
    std::sort(counts.begin(), counts.end(), [](auto& a, auto& b) { return a.second > b.second; });
    fprintf(stderr, "xef profile: %d samples, %.1f%% in translated code, %.1f%% in runtime/syscalls\n", n,
            n ? 100.0 * in_jit / n : 0.0, n ? 100.0 * (n - in_jit) / n : 0.0);
    for (size_t i = 0; i < counts.size() && i < 25; i++) {
        BlockMeta* b = counts[i].first;
        fprintf(stderr, "  %5.1f%%  guest %#lx..%#lx  (%d insns, host %u bytes @%p)\n", 100.0 * counts[i].second / n,
                (unsigned long)b->start, (unsigned long)b->end, (int)((b->end - b->start) / 4), b->code_size, b->code);
    }
}

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
