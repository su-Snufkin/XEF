#include <map>
#include <string>
#include <cstring>
#include <unistd.h>
#include <fcntl.h>
#include "profile/stats.h"

#include <signal.h>
#include <sys/time.h>
#include <ucontext.h>

#include <algorithm>
#include <vector>

#include "frontend/a64/translate.h"
#include "runtime/cpu_state.h"
#include "runtime/dispatch.h"
#include "ir/ir.h"
#include "runtime/code_cache.h"

extern "C" char __executable_start, __etext;
namespace xef {

Stats g_stats;

// ---- sampling profiler (--profile): kSampleSig every 1 ms CPU time, host RIP recorded ----
static constexpr int kMaxSamples = 1 << 22;
static u64* g_samples;
static volatile int g_nsamples;

void profile_sample(u8* rip) {
    int i = g_nsamples;
    if (g_samples && i < kMaxSamples) { g_samples[i] = (u64)rip; g_nsamples = i + 1; }
}

void profile_start() { g_samples = new u64[kMaxSamples]; }

void profile_report() {
    if (!g_samples) return;
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
    int in_t2 = 0;
    for (BlockMeta* b : blocks) if (b->tier == 2) in_t2++;
    fprintf(stderr, "  tier-2 regions: %.1f%% of samples\n", n ? 100.0 * in_t2 / n : 0.0);
    // the hottest blocks' host and guest code, for offline disassembly
    for (size_t i = 0; i < counts.size() && i < 5; i++) {
        BlockMeta* b = counts[i].first;
        char path[64];
        snprintf(path, sizeof path, "/tmp/xef-hot%zu.host", i);
        if (FILE* f = fopen(path, "wb")) { fwrite(b->code, 1, b->code_size, f); fclose(f); }
        snprintf(path, sizeof path, "/tmp/xef-hot%zu.guest", i);
        int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);   // guest code may be unmapped by now
        if (fd >= 0) { ssize_t w = write(fd, (void*)b->start, b->end - b->start); (void)w; close(fd); }
        // per host-instruction sample counts (tools/annotate_hot.py)
        snprintf(path, sizeof path, "/tmp/xef-hot%zu.counts", i);
        if (FILE* f = fopen(path, "w")) {
            fprintf(f, "# guest %#lx..%#lx host %p tier %d\n", (unsigned long)b->start, (unsigned long)b->end,
                    (void*)b->code, (int)b->tier);
            std::map<u32, int> off;
            for (int k = 0; k < n; k++) {
                u8* p = (u8*)g_samples[k];
                if (p >= b->code && p < b->code + b->code_size) off[(u32)(p - b->code)]++;
            }
            for (auto& [o, c] : off) fprintf(f, "%u %d\n", o, c);
            fclose(f);
        }
    }
    for (size_t i = 0; i < counts.size() && i < 25; i++) {
        BlockMeta* b = counts[i].first;
        fprintf(stderr, "  %5.1f%%  guest %#lx..%#lx  (%d insns, host %u bytes @%p) %s\n", 100.0 * counts[i].second / n,
                (unsigned long)b->start, (unsigned long)b->end, (int)((b->end - b->start) / 4), b->code_size, b->code,
                b->tier == 2 ? "t2" : b->tier == 3 ? "t1 (region failed)" : b->tier == 4 ? "t1 (demoted)" : "t1");
    }
    // XEF_REGSTATS=1: guest register accesses (GetReg/SetReg) of the sampled blocks, weighted by
    // their samples: which registers the canonical mapping should keep in host registers
    if (getenv("XEF_REGSTATS")) {
        double w[32] = {};
        static ir::Block blk;
        a64::TranslateOpts topt;
        topt.max_insts = g_opt.max_block_insts;
        for (auto& [b, c] : counts) {
            if (!a64::guest_readable(b->start)) continue;
            a64::translate_block(b->start, blk, topt);
            for (int v = 1; v < blk.n; v++) {
                const ir::Inst& in = blk.insts[v];
                if ((in.op == ir::Op::GetReg || in.op == ir::Op::SetReg) && in.aux < 32) w[in.aux] += c;
            }
        }
        int order[32];
        for (int g = 0; g < 32; g++) order[g] = g;
        std::sort(order, order + 32, [&](int a, int b) { return w[a] > w[b]; });
        double tot = 0;
        for (double x : w) tot += x;
        fprintf(stderr, "  guest register accesses (sample-weighted), * = mapped:\n   ");
        for (int i = 0; i < 32; i++)
            fprintf(stderr, " %s%d%s %.1f%%", order[i] == 31 ? "sp" : "x", order[i] == 31 ? 0 : order[i],
                    regmap::mapped(order[i]) ? "*" : "", tot ? 100.0 * w[order[i]] / tot : 0.0);
        fprintf(stderr, "\n");
    }
    // outside translated code: XEF functions via addr2line, everything else by mapping
    std::map<std::string, int> where;
    std::vector<u64> own;
    u64 lo = (u64)&__executable_start, hi = (u64)&__etext;
    for (int i = 0; i < n; i++) {
        u64 p = g_samples[i];
        if (g_cache.contains((u8*)p)) continue;
        if (p >= lo && p < hi) { own.push_back(p - lo); continue; }
        char d[512];
        describe_addr(p, d, sizeof d);
        const char* paren = strchr(d, '(');
        std::string lib = paren ? std::string(paren + 1) : std::string("?");
        size_t plus = lib.rfind('+');
        if (plus != std::string::npos) lib.resize(plus);
        where[lib]++;
    }
    if (!own.empty()) {
        char cmd[256];
        snprintf(cmd, sizeof cmd, "addr2line -f -C -e /proc/%d/exe > /tmp/xef-prof-sym.txt", (int)getpid());
        if (FILE* f = popen(cmd, "w")) {
            for (u64 o : own) fprintf(f, "%#lx\n", (unsigned long)o);
            pclose(f);
            if (FILE* r = fopen("/tmp/xef-prof-sym.txt", "r")) {
                char fn[1024], loc[1024];
                while (fgets(fn, sizeof fn, r) && fgets(loc, sizeof loc, r)) {
                    fn[strcspn(fn, "\n")] = 0;
                    where[std::string("xef: ") + fn]++;
                }
                fclose(r);
            }
        }
    }
    std::vector<std::pair<std::string, int>> w(where.begin(), where.end());
    std::sort(w.begin(), w.end(), [](auto& a, auto& b) { return a.second > b.second; });
    fprintf(stderr, "  outside translated code:\n");
    for (size_t i = 0; i < w.size() && i < 20; i++)
        fprintf(stderr, "  %5.1f%%  %s\n", 100.0 * w[i].second / n, w[i].first.c_str());
}

void stats_print() {
    const Stats& s = g_stats;
    fprintf(stderr,
            "xef stats:\n"
            "  blocks translated   : %lu (tier1) %lu (tier2)\n"
            "  guest insts         : %lu (%.1f per block)\n"
            "  host code           : %lu bytes (%.1f bytes/guest insn)\n"
            "  translation time    : %.3f ms (%.0f ns/block)\n"
            "  exits: link %lu, lookup(ibtc miss) %lu, syscall %lu\n"
            "  tier-2 regions      : %lu (%lu demoted)\n"
            "  code invalidations  : %lu (requests %lu, %lu on ranges without translations)\n",
            (unsigned long)s.blocks_t1, (unsigned long)s.blocks_t2, (unsigned long)s.guest_insts_translated,
            s.blocks_t1 ? (double)s.guest_insts_translated / s.blocks_t1 : 0.0, (unsigned long)s.host_bytes,
            s.guest_insts_translated ? (double)s.host_bytes / s.guest_insts_translated : 0.0, s.translate_ns / 1e6,
            s.blocks_t1 ? (double)s.translate_ns / s.blocks_t1 : 0.0, (unsigned long)s.exits_link,
            (unsigned long)s.exits_lookup, (unsigned long)s.exits_syscall, (unsigned long)s.regions, (unsigned long)s.regions_demoted,
            (unsigned long)s.invalidations, (unsigned long)s.inval_requests, (unsigned long)s.inval_unmarked);
    extern u64 g_vec_helper_calls[4096];
    std::vector<std::pair<u64, int>> vh;
    for (int k = 0; k < 4096; k++) if (g_vec_helper_calls[k]) vh.push_back({g_vec_helper_calls[k], k});
    std::sort(vh.begin(), vh.end(), [](auto& a, auto& b) { return a.first > b.first; });
    if (!vh.empty()) fprintf(stderr, "  vector ops via C helper (op/esize: calls):\n");
    for (size_t k = 0; k < vh.size() && k < 15; k++)
        fprintf(stderr, "    %-12s e%d: %lu\n", xef::ir::vec_op_name((u16)(vh[k].second / 8)), 1 << (vh[k].second % 8),
                (unsigned long)vh[k].first);
}

}  // namespace xef
