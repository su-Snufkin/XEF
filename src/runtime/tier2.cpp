// XEF — tier 2: hot regions with a region-specific register mapping.
//
// Hot blocks are found by SIGPROF sampling (no counters on the hot path). A
// background thread forms a region (the hot block plus hot direct successors),
// picks a register mapping that gives host registers of guest registers unused
// in the region to the most used X8..X28, and compiles all region blocks with
// that mapping. Internal edges are direct jumps; the register transfer happens
// only on region entry/exit. The region is then made live by re-pointing the
// head block's incoming links to the region entry.
#include "runtime/tier2.h"

#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <sys/time.h>
#include <ucontext.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>

#include "backend/x64/codegen.h"
#include "frontend/a64/translate.h"
#include "profile/stats.h"
#include "runtime/dispatch.h"

namespace xef {

using namespace x64;
using backend::RegionXfer;

int g_tier2_threshold = 3;
static int g_pipe[2] = {-1, -1};
static ir::Block* g_t2_blk;

namespace {

constexpr int kMaxRegionBlocks = 48;

struct Region {
    GuestAddr pcs[kMaxRegionBlocks];
    int n = 0;
    bool contains(GuestAddr pc) const {
        for (int i = 0; i < n; i++) if (pcs[i] == pc) return true;
        return false;
    }
};

bool is_internal_cb(void* user, GuestAddr t) { return ((Region*)user)->contains(t); }

bool direct_terminator(const ir::Block& b, GuestAddr out[2], int* nout) {
    for (int v = b.n - 1; v >= 1; v--) {
        const ir::Inst& in = b.insts[v];
        if (!ir::is_terminator(in.op)) continue;
        switch (in.op) {
        case ir::Op::ExitJump: out[0] = in.imm; *nout = 1; return true;
        case ir::Op::ExitCond: case ir::Op::ExitCbz: case ir::Op::ExitTbz:
            out[0] = in.imm; out[1] = in.imm2; *nout = 2; return true;
        default: return false;
        }
    }
    return false;
}

bool has_unsupported(const ir::Block& b) {
    for (int v = 1; v < b.n; v++) {
        ir::Op op = b.insts[v].op;
        // helper calls are fine (caller-saved registers are handled generically)
        if (op == ir::Op::ExitSyscall || op == ir::Op::ExitUndef || op == ir::Op::ExitBrk) return true;
    }
    return false;
}

}  // namespace

// Compiles the region headed by `head`. Called with g_cache.lock held.
static bool compile_region(GuestAddr head) {
    BlockMeta* hm = g_cache.lookup(head);
    if (!hm || hm->tier != 1) return false;
    hm->tier = 3;  // "tried": don't retry on failure
    ir::Block& blk = *g_t2_blk;
    a64::TranslateOpts topt;
    topt.max_insts = g_opt.max_block_insts;

    // ---- region formation: BFS over hot direct successors
    Region R;
    R.pcs[R.n++] = head;
    int uses[32] = {0}, writes[32] = {0};
    for (int qi = 0; qi < R.n; qi++) {
        a64::translate_block(R.pcs[qi], blk, topt);
        GuestAddr succ[2];
        int ns = 0;
        if (has_unsupported(blk) || !direct_terminator(blk, succ, &ns)) {
            if (qi == 0) return false;
            // drop it from the region
            R.pcs[qi] = R.pcs[--R.n];
            qi--;
            continue;
        }
        for (int v = 1; v < blk.n; v++) {
            const ir::Inst& in = blk.insts[v];
            if (in.op == ir::Op::GetReg || in.op == ir::Op::SetReg) uses[in.aux] += 1;
            if (in.op == ir::Op::SetReg) writes[in.aux] += 1;
        }
        for (int k = 0; k < ns; k++) {
            if (R.contains(succ[k]) || R.n >= kMaxRegionBlocks) continue;
            BlockMeta* sm = g_cache.lookup(succ[k]);
            // only blocks that already ran (were translated), near the head
            if (!sm || sm->tier == 2) continue;
            i64 dist = (i64)succ[k] - (i64)head;
            if (dist < -16384 || dist > 16384) continue;
            R.pcs[R.n++] = succ[k];
        }
    }
    // a region is only worth it if it loops back into itself
    bool loops = false;
    for (int i = 0; i < R.n && !loops; i++) {
        a64::translate_block(R.pcs[i], blk, topt);
        GuestAddr succ[2];
        int ns = 0;
        direct_terminator(blk, succ, &ns);
        for (int k = 0; k < ns; k++) if (R.contains(succ[k])) loops = true;
    }
    if (!loops) return false;

    // ---- NZCV liveness over the region CFG (more precise than per-block lookahead)
    bool f_reads[kMaxRegionBlocks], f_writes[kMaxRegionBlocks], f_live_in[kMaxRegionBlocks];
    bool f_live_out[kMaxRegionBlocks];
    GuestAddr f_succ[kMaxRegionBlocks][2];
    int f_nsucc[kMaxRegionBlocks];
    for (int i = 0; i < R.n; i++) {
        a64::translate_block(R.pcs[i], blk, topt);
        f_reads[i] = f_writes[i] = false;
        for (int v = 1; v < blk.n; v++) {
            if (blk.insts[v].op == ir::Op::GetFlags) f_reads[i] = true;
            if (blk.insts[v].op == ir::Op::SetFlags) f_writes[i] = true;
        }
        direct_terminator(blk, f_succ[i], &f_nsucc[i]);
        f_live_in[i] = f_reads[i];
        f_live_out[i] = false;
    }
    auto idx_of = [&](GuestAddr pc) { for (int i = 0; i < R.n; i++) if (R.pcs[i] == pc) return i; return -1; };
    bool ext_live[kMaxRegionBlocks][2];
    for (int i = 0; i < R.n; i++)
        for (int k = 0; k < f_nsucc[i]; k++)
            ext_live[i][k] = idx_of(f_succ[i][k]) < 0 ? a64::nzcv_live_at(f_succ[i][k]) : false;
    for (bool changed = true; changed;) {
        changed = false;
        for (int i = R.n - 1; i >= 0; i--) {
            bool out = false;
            for (int k = 0; k < f_nsucc[i]; k++) {
                int j = idx_of(f_succ[i][k]);
                out |= j >= 0 ? f_live_in[j] : ext_live[i][k];
            }
            bool in = f_reads[i] || (!f_writes[i] && out);
            if (out != f_live_out[i] || in != f_live_in[i]) { f_live_out[i] = out; f_live_in[i] = in; changed = true; }
        }
    }

    // ---- register mapping
    Reg map[32];
    memcpy(map, regmap::kMap, sizeof map);
    Reg freed[16];
    int nfree = 0;
    RegionXfer xfer[16];
    int nxfer = 0;
    int order[32], no = 0;
    for (int g = 0; g < 32; g++) if (!regmap::mapped(g) && uses[g] > 0) order[no++] = g;
    std::sort(order, order + no, [&](int a, int b) { return uses[a] > uses[b]; });
    // displace only as many canonical registers as needed (+2 extra temporaries);
    // callee-saved hosts first (no save/restore around helper calls)
    static const Reg pref[] = {RDI, RSI, RDX, R10, R8, R9, RBX, RBP, R12, R13, R14};
    int want = 16;
    for (Reg h : pref) {
        if (nfree >= want) break;
        int gc = -1;
        for (int g = 0; g < 32; g++) if (regmap::host(g) == h) gc = g;
        if (gc >= 0 && uses[gc] == 0) { freed[nfree++] = h; map[gc] = NOREG; }
    }
    Reg temps[12] = {RAX, RCX, R11};
    int ntemps = 3;
    for (int i = 0; i < nfree; i++) {
        Reg h = freed[i];
        int gc = -1;
        for (int g = 0; g < 32; g++) if (regmap::host(g) == h) gc = g;
        int gr = -1;
        if (i < no) { gr = order[i]; map[gr] = h; }
        else if (ntemps < 12) temps[ntemps++] = h;
        xfer[nxfer++] = {h, (i8)gr, (i8)gc, gr >= 0 && writes[gr] > 0};
    }

    // ---- runtime feedback record
    RegionInfo* ri = new RegionInfo();
    ri->head_t1 = hm;
    ri->exit_counter = (u64*)g_cache.alloc_data(8);
    *ri->exit_counter = 0;

    // ---- code generation
    backend::CodegenCtx ctx;
    ctx.exit_counter = ri->exit_counter;
    ctx.map = map;
    ctx.temps = temps;
    ctx.ntemps = ntemps;
    ctx.region = true;
    ctx.is_internal = is_internal_cb;
    ctx.user = &R;
    ctx.xfer = xfer;
    ctx.nxfer = nxfer;

    // entry stub
    BlockMeta* entry = g_cache.alloc_meta(0);
    entry->start = head;
    entry->end = head + 4;
    entry->tier = 2;
    u8* ecode = g_cache.alloc_code(1024);
    Assembler eas(ecode, 1024);
    backend::emit_region_xfer(eas, xfer, nxfer, true);
    eas.db(0xE9);
    u8* entry_fix = eas.cur();
    eas.dd(0);
    entry->code = ecode;
    entry->code_size = (u32)eas.size();
    entry->region = ri;
    ri->entry = entry;
    g_cache.commit_code(ecode, eas.size());
    g_cache.register_block(entry);
    {   // signal-delivery exit for region-internal block entries. alloc_code() only reserves, so
        // this must come after the entry stub is committed or the two would overlap.
        u8* sc = g_cache.alloc_code(1024);
        Assembler sas(sc, 1024);
        backend::emit_region_xfer(sas, xfer, nxfer, false);
        sas.jmp_rel32(g_cache.stubs.exit_to_runtime);
        g_cache.commit_code(sc, sas.size());
        ri->sig_exit = sc;
    }

    u8* code_of[kMaxRegionBlocks];
    struct Fix { u8* field; GuestAddr target; };
    static Fix fixes[kMaxRegionBlocks * 64];
    int nfix = 0;
    BlockMeta* metas[kMaxRegionBlocks];
    for (int i = 0; i < R.n; i++) {
        a64::translate_block(R.pcs[i], blk, topt);
        blk.flags_live_out = f_live_out[i];
        BlockMeta* meta = g_cache.alloc_meta(backend::count_exits(blk));
        meta->start = R.pcs[i];
        meta->end = blk.end;
        meta->tier = 2;
        meta->region = ri;
        const size_t kMax = 256 * 1024;
        u8* code = g_cache.alloc_code(kMax);
        Assembler as(code, kMax);
        static backend::CodegenOut out;
        out = backend::CodegenOut();
        if (!backend::emit_tier1(blk, as, meta, out, &ctx)) return false;
        meta->code = code;
        meta->code_size = (u32)out.size;
        g_cache.commit_code(code, out.size);
        if (g_opt.dump_code) {
            char path[64];
            snprintf(path, sizeof path, "/tmp/xef-t2-%lx.bin", (unsigned long)R.pcs[i]);
            if (FILE* f = fopen(path, "wb")) { fwrite(code, 1, out.size, f); fclose(f); }
        }
        g_cache.register_block(meta);
        meta->nexits = (u16)out.nexits;
        code_of[i] = code;
        metas[i] = meta;
        for (int k = 0; k < out.nfixes; k++) fixes[nfix++] = {out.fixes[k].field, out.fixes[k].target};
    }
    auto code_for = [&](GuestAddr pc) -> u8* {
        for (int i = 0; i < R.n; i++) if (R.pcs[i] == pc) return code_of[i];
        return nullptr;
    };
    for (int k = 0; k < nfix; k++) Assembler::patch_rel32(fixes[k].field, code_for(fixes[k].target));
    Assembler::patch_rel32(entry_fix, code_of[0]);
    // link external exits whose targets exist
    for (int i = 0; i < R.n; i++) {
        BlockMeta* meta = metas[i];
        for (int k = 0; k < meta->nexits; k++) {
            ExitInfo* e = &meta->exits[k];
            if (BlockMeta* tb = g_cache.lookup(e->target)) {
                link_exit(e, tb->code);
                e->next_in = tb->incoming;
                tb->incoming = e;
            }
        }
    }
    // ---- go live: publish the entry and re-point incoming links of the tier-1 head
    entry->incoming = hm->incoming;
    hm->incoming = nullptr;
    for (ExitInfo* e = entry->incoming; e; e = e->next_in) link_exit(e, entry->code);
    g_cache.publish(entry);
    if (g_opt.stats) {
        g_stats.blocks_t2 += R.n;
        g_stats.regions++;
    }
    XEF_LOG(1, "tier2: region %#lx (%d blocks, %d regs remapped, %d temps)", (unsigned long)head, R.n,
            std::min(nfree, no), ntemps);
    return true;
}

// Region exits too often relative to time spent in it: re-point links back to tier 1.
static void demote_region(RegionInfo* ri) {
    if (ri->demoted) return;
    ri->demoted = true;
    BlockMeta* hm = ri->head_t1;
    BlockMeta* entry = ri->entry;
    hm->incoming = entry->incoming;
    entry->incoming = nullptr;
    for (ExitInfo* e = hm->incoming; e; e = e->next_in) link_exit(e, hm->code);
    hm->tier = 4;  // never promote again
    g_cache.publish(hm);
    if (g_opt.stats) g_stats.regions_demoted++;
    XEF_LOG(1, "tier2: demoted region %#lx (exits=%lu samples=%lu)", (unsigned long)hm->start,
            (unsigned long)*ri->exit_counter, (unsigned long)ri->samples);
}

int g_tier2_max_exits_per_ms = 100000;

static void* compiler_thread(void*) {
    sigset_t all;
    sigfillset(&all);
    pthread_sigmask(SIG_BLOCK, &all, nullptr);
    g_t2_blk = new ir::Block();
    for (;;) {
        GuestAddr pc;
        ssize_t r = read(g_pipe[0], &pc, sizeof pc);
        if (r != sizeof pc) continue;
        std::lock_guard<std::mutex> lk(g_cache.lock);
        if (pc & 1) demote_region((RegionInfo*)(pc & ~1ull));
        else compile_region(pc);
    }
    return nullptr;
}

// SIGPROF: count samples per translated block, request tier 2 for hot ones.
static void sample_handler(int sig, siginfo_t* si, void* ctx) {
    u8* rip = (u8*)((ucontext_t*)ctx)->uc_mcontext.gregs[REG_RIP];
    if (g_opt.profile) profile_sample(rip);
    if (!g_cache.contains(rip)) return;
    BlockMeta* b = g_cache.find_by_host(rip);
    if (!b) return;
    u64 c = ++b->exec_count;
    if (b->tier == 2 && b->region && !b->region->demoted) {
        RegionInfo* ri = b->region;
        u64 n = ++ri->samples;
        if ((n & 3) == 0 && *ri->exit_counter > n * (u64)g_tier2_max_exits_per_ms && g_pipe[1] >= 0) {
            u64 msg = (u64)ri | 1;
            ssize_t w = write(g_pipe[1], &msg, sizeof msg);
            (void)w;
        }
        return;
    }
    if (b->tier == 1 && c == (u64)g_tier2_threshold && g_pipe[1] >= 0) {
        GuestAddr pc = b->start;
        ssize_t w = write(g_pipe[1], &pc, sizeof pc);
        (void)w;
    }
    (void)sig;
    (void)si;
}

static bool g_t2_enabled = false;

static void start_compiler_thread() {
    if (pipe2(g_pipe, O_CLOEXEC) != 0) fatal("tier2: pipe");
    // the SIGPROF handler must never block: drop requests if the pipe is full
    fcntl(g_pipe[1], F_SETFL, O_NONBLOCK);
    pthread_t th;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_attr_setstacksize(&attr, 8 << 20);
    if (pthread_create(&th, &attr, compiler_thread, nullptr) != 0) fatal("tier2: thread");
}

void tier2_after_fork() {
    if (!g_t2_enabled) return;
    close(g_pipe[0]);
    close(g_pipe[1]);
    start_compiler_thread();
    // the ITIMER_PROF timer is not inherited by fork
    struct itimerval it {};
    it.it_interval.tv_usec = 1000;
    it.it_value.tv_usec = 1000;
    setitimer(ITIMER_PROF, &it, nullptr);
}

void tier2_init(bool enable) {
    g_t2_enabled = enable;
    if (enable) start_compiler_thread();
    if (!enable && !g_opt.profile) return;
    struct sigaction sa {};
    sa.sa_sigaction = sample_handler;
    sa.sa_flags = SA_SIGINFO | SA_RESTART;
    sigaction(SIGPROF, &sa, nullptr);
    struct itimerval it {};
    it.it_interval.tv_usec = 1000;
    it.it_value.tv_usec = 1000;
    setitimer(ITIMER_PROF, &it, nullptr);
}

}  // namespace xef
