// XEF — tier 2: hot regions with a region-specific register mapping.
//
// Hot blocks are found by sampling (kSampleSig) (no counters on the hot path). A
// background thread forms a region (the hot block plus hot direct successors),
// picks a register mapping that gives host registers of guest registers unused
// in the region to the most used X8..X28, and compiles all region blocks with
// that mapping. Internal edges are direct jumps; the register transfer happens
// only on region entry/exit. The region is then made live by re-pointing the
// head block's incoming links to the region entry.
#include "os/syscalls.h"
#include "runtime/tier2.h"
#include "os/signals.h"
#include "os/thread.h"
#include <sys/syscall.h>
#include <time.h>

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
using backend::RegionVXfer;

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
        case ir::Op::ExitCall: out[0] = in.imm2; *nout = 1; return true;   // callee outside the region
        default: return false;
        }
    }
    return false;
}

bool is_call(const ir::Block& b) {
    for (int v = b.n - 1; v >= 1; v--)
        if (ir::is_terminator(b.insts[v].op)) return b.insts[v].op == ir::Op::ExitCall;
    return false;
}

// a region with this block's call was evicted (calls too frequent)
bool no_calls_at(GuestAddr pc) {
    BlockMeta* m = g_cache.lookup(pc);
    return m && (m->flags & BF_NOCALLS);
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
    // cache maintenance does not take the lock where no code is marked (CodeCache::mark_code)
    u64 ep = g_cache.epoch.load(std::memory_order_seq_cst);
    // every guest range decoded ahead while forming the region becomes an invalidation dependency
    static PeekLog peeks;
    peeks.reset();
    a64::set_peek_log(&peeks);
    struct ClearPeek { ~ClearPeek() { a64::set_peek_log(nullptr); } } clear_peek;
    ir::Block& blk = *g_t2_blk;
    a64::TranslateOpts topt;
    topt.max_insts = g_opt.max_block_insts;
    topt.flags_liveness = false;   // the region's own NZCV dataflow below decides flags_live_out

    // ---- region formation: BFS over hot direct successors. Everything the passes below need
    // about a member is recorded here (by position in R), so it is decoded once more only for
    // code generation.
    Region R;
    R.pcs[R.n++] = head;
    int uses[32] = {0}, writes[32] = {0};
    int vuses[32] = {0}, vwrites[32] = {0};
    static u16 b_uses[kMaxRegionBlocks][32], b_writes[kMaxRegionBlocks][32], b_vuses[kMaxRegionBlocks][32],
        b_vwrites[kMaxRegionBlocks][32];   // per member, summed after pruning
    bool f_reads[kMaxRegionBlocks], f_writes[kMaxRegionBlocks], helper_of[kMaxRegionBlocks], call_of[kMaxRegionBlocks];
    GuestAddr f_succ[kMaxRegionBlocks][2];
    int f_nsucc[kMaxRegionBlocks];
    for (int qi = 0; qi < R.n; qi++) {
        a64::translate_block(R.pcs[qi], blk, topt);
        GuestAddr* succ = f_succ[qi];
        int ns = 0;
        if (has_unsupported(blk) || !direct_terminator(blk, succ, &ns) || (is_call(blk) && no_calls_at(R.pcs[qi]))) {
            if (qi == 0) {
                XEF_LOG(1, "tier2: %#lx: head block not supported", (unsigned long)head);
                return false;
            }
            // drop it from the region
            R.pcs[qi] = R.pcs[--R.n];
            qi--;
            continue;
        }
        f_nsucc[qi] = ns;
        f_reads[qi] = f_writes[qi] = helper_of[qi] = false;
        call_of[qi] = is_call(blk);
        memset(b_uses[qi], 0, sizeof b_uses[qi]);
        memset(b_writes[qi], 0, sizeof b_writes[qi]);
        memset(b_vuses[qi], 0, sizeof b_vuses[qi]);
        memset(b_vwrites[qi], 0, sizeof b_vwrites[qi]);
        for (int v = 1; v < blk.n; v++) {
            const ir::Inst& in = blk.insts[v];
            if (in.op == ir::Op::GetReg || in.op == ir::Op::SetReg) b_uses[qi][in.aux & 31] += in.aux < 32;
            if (in.op == ir::Op::SetReg) b_writes[qi][in.aux & 31] += in.aux < 32;
            if (in.op == ir::Op::VGet || in.op == ir::Op::VSet) b_vuses[qi][in.aux & 31] += in.aux < 32;
            if (in.op == ir::Op::VSet) b_vwrites[qi][in.aux & 31] += in.aux < 32;
            if (in.op == ir::Op::GetFlags) f_reads[qi] = true;
            if (in.op == ir::Op::SetFlags) f_writes[qi] = true;
            if (in.op == ir::Op::Helper) helper_of[qi] = true;
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
    // A call block is kept only on a cycle through the head: the code after other calls is mostly
    // outside the loop (it would only add transfers and dilute the register choice). Then what
    // the head no longer reaches goes too.
    {
        auto idx = [&](GuestAddr pc) { for (int i = 0; i < R.n; i++) if (R.pcs[i] == pc) return i; return -1; };
        bool fwd[kMaxRegionBlocks] = {}, bwd[kMaxRegionBlocks] = {}, keep[kMaxRegionBlocks];
        auto reach = [&](bool* out, const bool* allowed) {
            int st[kMaxRegionBlocks], sp = 0;
            out[0] = true;
            st[sp++] = 0;
            while (sp) {
                int i = st[--sp];
                for (int k = 0; k < f_nsucc[i]; k++) {
                    int j = idx(f_succ[i][k]);
                    if (j >= 0 && !out[j] && (!allowed || allowed[j])) { out[j] = true; st[sp++] = j; }
                }
            }
        };
        reach(fwd, nullptr);
        for (bool ch = true; ch;) {
            ch = false;
            for (int i = 0; i < R.n; i++) {
                if (bwd[i]) continue;
                for (int k = 0; k < f_nsucc[i]; k++) {
                    int j = idx(f_succ[i][k]);
                    if (j == 0 || (j > 0 && bwd[j])) { bwd[i] = ch = true; break; }
                }
            }
        }
        for (int i = 0; i < R.n; i++) keep[i] = i == 0 || !call_of[i] || (fwd[i] && bwd[i]);
        bool reached[kMaxRegionBlocks] = {};
        reach(reached, keep);
        int n = 0;
        for (int i = 0; i < R.n; i++) {
            if (!reached[i]) continue;
            if (n != i) {
                R.pcs[n] = R.pcs[i];
                f_succ[n][0] = f_succ[i][0];
                f_succ[n][1] = f_succ[i][1];
                f_nsucc[n] = f_nsucc[i];
                f_reads[n] = f_reads[i];
                f_writes[n] = f_writes[i];
                helper_of[n] = helper_of[i];
                call_of[n] = call_of[i];
                memcpy(b_uses[n], b_uses[i], sizeof b_uses[n]);
                memcpy(b_writes[n], b_writes[i], sizeof b_writes[n]);
                memcpy(b_vuses[n], b_vuses[i], sizeof b_vuses[n]);
                memcpy(b_vwrites[n], b_vwrites[i], sizeof b_vwrites[n]);
            }
            n++;
        }
        R.n = n;
        for (int i = 0; i < R.n; i++)
            for (int g = 0; g < 32; g++) {
                uses[g] += b_uses[i][g];
                writes[g] += b_writes[i][g];
                vuses[g] += b_vuses[i][g];
                vwrites[g] += b_vwrites[i][g];
            }
    }
    // a region is only worth it if it loops back into itself
    bool loops = false;
    for (int i = 0; i < R.n && !loops; i++)
        for (int k = 0; k < f_nsucc[i]; k++) if (R.contains(f_succ[i][k])) loops = true;
    if (!loops) {
        if (hm->exec_count < (u64)g_tier2_threshold * 16) hm->tier = 1;  // allow retry once successors are translated
        XEF_LOG(1, "tier2: %#lx: no loop among %d blocks", (unsigned long)head, R.n);
        return false;
    }

    // ---- NZCV liveness over the region CFG (more precise than per-block lookahead)
    bool f_live_in[kMaxRegionBlocks], f_live_out[kMaxRegionBlocks];
    for (int i = 0; i < R.n; i++) {
        f_live_in[i] = f_reads[i];
        f_live_out[i] = false;
    }
    auto idx_of = [&](GuestAddr pc) { for (int i = 0; i < R.n; i++) if (R.pcs[i] == pc) return i; return -1; };
    bool ext_live[kMaxRegionBlocks][2];
    for (int i = 0; i < R.n; i++)
        for (int k = 0; k < f_nsucc[i]; k++)
            ext_live[i][k] = !call_of[i] && idx_of(f_succ[i][k]) < 0 ? a64::nzcv_live_at(f_succ[i][k]) : false;
    for (bool changed = true; changed;) {
        changed = false;
        for (int i = R.n - 1; i >= 0; i--) {
            // a call: NZCV is dead at it by the ABI (else live: the callee may read it)
            bool out = call_of[i] && !a64::g_abi_flags;
            for (int k = 0; k < f_nsucc[i] && !call_of[i]; k++) {
                int j = idx_of(f_succ[i][k]);
                out |= j >= 0 ? f_live_in[j] : ext_live[i][k];
            }
            bool in = f_reads[i] || (!f_writes[i] && out);
            if (out != f_live_out[i] || in != f_live_in[i]) { f_live_out[i] = out; f_live_in[i] = in; changed = true; }
        }
    }

    // ---- register mapping
    Reg map[32];
    memcpy(map, regmap::g_map, sizeof map);
    Reg freed[16];
    int nfree = 0;
    RegionXfer xfer[16];
    int nxfer = 0;
    // The region keeps its most-used guest registers in host registers: canonical ones that are
    // used less are displaced (to CpuState, via the entry/exit transfers) in favour of hot ones
    // that normally live in memory. Ties keep the canonical mapping (no transfer cost).
    static const Reg pref[] = {RDI, RSI, RDX, R10, R8, R9, RBX, RBP, R12, R13, R14};
    constexpr int kHosts = sizeof pref / sizeof pref[0];
    int cand[32], nc = 0;
    for (int g = 0; g < 32; g++) if (uses[g] > 0) cand[nc++] = g;
    std::sort(cand, cand + nc, [&](int a, int b) {
        if (uses[a] != uses[b]) return uses[a] > uses[b];
        return regmap::mapped(a) && !regmap::mapped(b);
    });
    bool in_top[32] = {};
    for (int i = 0; i < nc && i < kHosts; i++) in_top[cand[i]] = true;
    for (Reg h : pref) {
        int gc = -1;
        for (int g = 0; g < 32; g++) if (regmap::host(g) == h) gc = g;
        if (gc >= 0 && in_top[gc]) continue;              // stays where it is
        freed[nfree++] = h;
        if (gc >= 0) map[gc] = NOREG;
    }
    int order[32], no = 0;                                 // hot guests without a host register yet
    for (int i = 0; i < nc && i < kHosts; i++) if (map[cand[i]] == NOREG) order[no++] = cand[i];
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

    // ---- vector register mapping (pin up to 10 hot guest V registers in XMM6..XMM15; XMM0..XMM5 stay scratch)
    u8 vmap[32];
    memset(vmap, NOREG, sizeof vmap);
    RegionVXfer vxfer[10];
    int nvxfer = 0;
    int vcand[32], nvc = 0;
    for (int g = 0; g < 32; g++) if (vuses[g] > 0) vcand[nvc++] = g;
    std::sort(vcand, vcand + nvc, [&](int a, int b) { return vuses[a] > vuses[b]; });
    for (int i = 0; i < nvc && i < 10; i++) {
        int g = vcand[i];
        Xmm h = (Xmm)(XMM6 + i);
        vmap[g] = (u8)h;
        vxfer[nvxfer++] = {h, (u8)g, vwrites[g] > 0};
    }

    // ---- runtime feedback record
    RegionInfo* ri = new RegionInfo();
    ri->head_t1 = hm;
    ri->blocks = new BlockMeta*[R.n];
    ri->nblocks = 0;
    ri->branches = nullptr;
    ri->nbranches = 0;
    ri->killed = false;
    for (int g = 0; g < 32; g++) { ri->map[g] = (u8)map[g]; ri->vmap[g] = vmap[g]; }
    ri->exit_counter = (u64*)g_cache.alloc_data(8);
    *ri->exit_counter = 0;
    ri->call_counter = (u64*)g_cache.alloc_data(8);
    *ri->call_counter = 0;
    ri->call_moves = 0;
    for (int i = 0; i < nxfer; i++)
        ri->call_moves += (xfer[i].g_region >= 0) * (1 + xfer[i].written) + (xfer[i].g_canon >= 0) * 2;
    for (int i = 0; i < nvxfer; i++) ri->call_moves += 1 + vxfer[i].written;

    // ---- code generation
    backend::CodegenCtx ctx;
    ctx.exit_counter = ri->exit_counter;
    ctx.call_counter = ri->call_counter;
    ctx.map = map;
    ctx.vmap = vmap;
    ctx.temps = temps;
    ctx.ntemps = ntemps;
    ctx.region = true;
    ctx.is_internal = is_internal_cb;
    ctx.user = &R;
    ctx.xfer = xfer;
    ctx.nxfer = nxfer;
    ctx.vxfer = vxfer;
    ctx.nvxfer = nvxfer;

    // entry stub
    BlockMeta* entry = g_cache.alloc_meta(0);
    entry->start = head;
    entry->end = head + 4;
    entry->tier = 2;
    u8* ecode = g_cache.alloc_code(1024);
    Assembler eas(ecode, 1024);
    backend::emit_region_xfer(eas, xfer, nxfer, vxfer, nvxfer, true);
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
        backend::emit_region_xfer(sas, xfer, nxfer, vxfer, nvxfer, false);
        sas.jmp_rel32(g_cache.stubs.exit_to_runtime);
        g_cache.commit_code(sc, sas.size());
        ri->sig_exit = sc;
    }

    u8* code_of[kMaxRegionBlocks];
    struct Fix { u8* field; GuestAddr target; };
    static Fix fixes[kMaxRegionBlocks * 64];
    int nfix = 0;
    BlockMeta* metas[kMaxRegionBlocks];

    // ---- layout: chains along the fall-through successor (the not-taken side of a conditional
    // exit, the target of an unconditional one), so the member laid out next needs no jump. A
    // member with a helper call (IC IVAU) ends its chain: the code after it is entered by a jump,
    // which region invalidation can retarget.
    int lay[kMaxRegionBlocks], nord = 0;
    bool placed[kMaxRegionBlocks] = {};
    int fall_of[kMaxRegionBlocks];
    for (int i = 0; i < R.n; i++) fall_of[i] = f_nsucc[i] ? idx_of(f_succ[i][f_nsucc[i] - 1]) : -1;
    for (int i = 0; i < R.n; i++)
        for (int cur = i; cur >= 0 && !placed[cur];) {
            placed[cur] = true;
            lay[nord++] = cur;
            cur = helper_of[cur] ? -1 : fall_of[cur];
        }

    // ---- code generation: member bodies back to back, then all their exit stubs
    const size_t kMax = (size_t)R.n * (64 << 10) + (64 << 10);
    u8* code = g_cache.alloc_code(kMax);
    Assembler as(code, kMax);
    static backend::CodegenOut outs[kMaxRegionBlocks];
    backend::RegionBodyGen* gens[kMaxRegionBlocks];
    for (int k = 0; k < nord; k++) {
        int i = lay[k];
        a64::translate_block(R.pcs[i], blk, topt);
        blk.flags_live_out = f_live_out[i];
        BlockMeta* meta = g_cache.alloc_meta(backend::count_exits(blk));
        meta->start = R.pcs[i];
        meta->end = blk.end;
        meta->tier = 2;
        meta->region = ri;
        outs[i].reset();
        backend::CodegenCtx c = ctx;
        c.fall_pc = k + 1 < nord && !helper_of[i] ? R.pcs[lay[k + 1]] : 0;
        u8* bcode = as.cur();
        gens[k] = backend::emit_region_body(blk, as, meta, outs[i], c, true);
        if (!gens[k]) {
            for (int q = 0; q < k; q++) backend::finish_region_body(gens[q], false);
            XEF_LOG(1, "tier2: %#lx: code generation failed for block %#lx", (unsigned long)head, (unsigned long)R.pcs[i]);
            return false;
        }
        meta->code = bcode;
        meta->code_size = (u32)outs[i].size;
        g_cache.set_pcmap(meta, outs[i].pcmap, outs[i].npcmap);
        code_of[i] = bcode;
        metas[i] = meta;
    }
    bool cold_ok = true;
    for (int k = 0; k < nord; k++) cold_ok &= backend::finish_region_body(gens[k], true);
    if (!cold_ok || as.overflow()) {
        XEF_LOG(1, "tier2: %#lx: region code too large", (unsigned long)head);
        return false;
    }
    g_cache.commit_code(code, as.size());
    for (int k = 0; k < nord; k++) {
        int i = lay[k];
        BlockMeta* meta = metas[i];
        if (g_opt.dump_code && g_opt.dump_wants(R.pcs[i])) {
            char path[64];
            snprintf(path, sizeof path, "/tmp/xef-t2-%lx.bin", (unsigned long)R.pcs[i]);
            if (FILE* f = fopen(path, "wb")) { fwrite(meta->code, 1, meta->code_size, f); fclose(f); }
        }
        g_cache.register_block(meta);
        meta->nexits = (u16)outs[i].nexits;
        for (int q = 0; q < outs[i].nfixes; q++) fixes[nfix++] = {outs[i].fixes[q].field, outs[i].fixes[q].target};
    }
    // in R order: RegionInfo::Branch::target indexes it (kill_region)
    for (int i = 0; i < R.n; i++) ri->blocks[ri->nblocks++] = metas[i];
    auto code_for = [&](GuestAddr pc) -> u8* {
        for (int i = 0; i < R.n; i++) if (R.pcs[i] == pc) return code_of[i];
        return nullptr;
    };
    for (int k = 0; k < nfix; k++) Assembler::patch_rel32(fixes[k].field, code_for(fixes[k].target));
    ri->branches = new RegionInfo::Branch[nfix];
    ri->nbranches = 0;
    for (int k = 0; k < nfix; k++)
        for (int i = 0; i < R.n; i++)
            if (R.pcs[i] == fixes[k].target) ri->branches[ri->nbranches++] = {fixes[k].field, i};
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
    if (peeks.overflow) {   // dependencies not trackable (abandoned code stays unpublished)
        XEF_LOG(1, "tier2: %#lx: too many lookahead ranges", (unsigned long)head);
        return false;
    }
    for (int i = 0; i < R.n; i++) g_cache.mark_code(metas[i]->start, metas[i]->end, i ? nullptr : &peeks);
    if (g_cache.epoch.load(std::memory_order_seq_cst) != ep) { hm->tier = 1; return false; }   // code changed
    PeekLog all = peeks;   // the region's code and its lookahead: one merged set of ranges
    for (int i = 0; i < R.n; i++) all.add(metas[i]->start, metas[i]->end);
    if (!all.overflow) g_cache.add_deps(entry, all);
    else
        for (int i = 0; i < R.n; i++) g_cache.add_deps(entry, metas[i]->start, metas[i]->end, i ? nullptr : &peeks);
    // ---- go live: publish the entry and re-point incoming links of the tier-1 head
    entry->incoming = hm->incoming;
    hm->incoming = nullptr;
    for (ExitInfo* e = entry->incoming; e; e = e->next_in) link_exit(e, entry->code);
    g_cache.publish(entry);
    // A head inside a tier-1 chain is also reached by falling through from the members before it
    // (no exit to re-point): typically a loop right after a function's entry blocks, whose first
    // iteration would run in tier 1 on every call. Kill those members; their retranslation
    // ends with a linked exit to the region entry.
    // IBTC entries of indirect branches to the head still point to its tier-1 code: dropped.
    for (BlockMeta* p = hm->chain_prev; p && !(p->flags & BF_DEAD); p = p->chain_prev) g_cache.invalidate_block(p);
    g_cache.forget_ibtc(head);
    g_cache.scrub_ibtcs();
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
    if (ri->demoted || ri->killed) return;
    ri->demoted = true;
    BlockMeta* hm = ri->head_t1;
    BlockMeta* entry = ri->entry;
    hm->incoming = entry->incoming;
    entry->incoming = nullptr;
    for (ExitInfo* e = hm->incoming; e; e = e->next_in) link_exit(e, hm->code);
    if (!(hm->flags & BF_DEMOTED_ONCE)) {
        hm->flags |= BF_DEMOTED_ONCE;
        hm->tier = 1;
        hm->exec_count = 0;
    } else {
        hm->tier = 4;  // never promote again
    }
    if (!(hm->flags & BF_DEAD)) g_cache.publish(hm);
    // a region headed by another member would cover the same code and exit as often: members not
    // tried yet are not promoted (state machines like coremark's formed a region per block)
    for (int i = 0; i < ri->nblocks; i++)
        if (BlockMeta* m = g_cache.lookup(ri->blocks[i]->start); m && m != hm && m->tier == 1) m->tier = 4;
    if (g_opt.stats) g_stats.regions_demoted++;
    XEF_LOG(1, "tier2: demoted region %#lx (exits=%lu samples=%lu)", (unsigned long)hm->start,
            (unsigned long)*ri->exit_counter, (unsigned long)ri->samples);
}

int g_tier2_max_exits_per_ms = 100000;
// Calls from inside a region pay a register transfer each way: a region whose calls cost more
// transfer moves per ms of region time than this is evicted and formed again without calls.
u64 g_tier2_max_call_moves_per_ms = 18000000;

// Region with too expensive calls: make threads leave it, retry the head without calls.
static void evict_calls_region(RegionInfo* ri) {
    if (ri->killed) return;
    BlockMeta* hm = ri->head_t1;
    // the members' calls are not taken into regions again (other heads in the same loop)
    for (int i = 0; i < ri->nblocks; i++)
        if (BlockMeta* m = g_cache.lookup(ri->blocks[i]->start); m && m->tier != 2) m->flags |= BF_NOCALLS;
    g_cache.evict_region(ri);
    if (hm && !(hm->flags & BF_DEAD)) {
        hm->flags |= BF_NOCALLS;
        if (hm->tier == 3) { hm->tier = 1; hm->exec_count = 0; }
    }
    XEF_LOG(1, "tier2: evicted region %#lx (calls=%lu x %u moves, samples=%lu)", (unsigned long)(hm ? hm->start : 0),
            (unsigned long)*ri->call_counter, ri->call_moves, (unsigned long)ri->samples);
}

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
        if (pc & 1) demote_region((RegionInfo*)(pc & ~3ull));
        else if (pc & 2) evict_calls_region((RegionInfo*)(pc & ~3ull));
        else compile_region(pc);
    }
    return nullptr;
}

// kSampleSig: count samples per translated block, request tier 2 for hot ones.
static void sample_handler(int sig, siginfo_t* si, void* ctx) {
    ucontext_t* uc = (ucontext_t*)ctx;
    u8* rip = (u8*)uc->uc_mcontext.gregs[REG_RIP];
    // safety net: a pending guest signal whose single-step request was lost (TF overwritten by a
    // popfq in translated code) is re-armed here, at most 1 ms of CPU time later
    if (ThreadCtx* t = tls_thread; t && t->st && t->st->pending_signal && !(uc->uc_mcontext.gregs[REG_EFL] & 0x100) &&
                                   (g_cache.contains(rip) || t->st->in_jit)) {
        t->stepping = true;
        uc->uc_mcontext.gregs[REG_EFL] |= 0x100;
    }
    if (g_opt.profile) profile_sample(rip);
    if (!g_cache.contains(rip)) return;
    BlockMeta* b = g_cache.find_by_host(rip);
    if (!b) return;
    u64 c = ++b->exec_count;
    if (b->tier == 2 && b->region && !b->region->killed) {
        RegionInfo* ri = b->region;
        u64 n = ++ri->samples;
        if ((n & 3) == 0 && g_pipe[1] >= 0) {
            u64 msg = 0;
            if (ri->call_moves && n >= 16 && *ri->call_counter * ri->call_moves > n * g_tier2_max_call_moves_per_ms)
                msg = (u64)ri | 2;
            else if (!ri->demoted && *ri->exit_counter > n * (u64)g_tier2_max_exits_per_ms) msg = (u64)ri | 1;
            if (msg) {
                ssize_t w = write(g_pipe[1], &msg, sizeof msg);
                (void)w;
            }
        }
        return;
    }
    u64 th = (u64)g_tier2_threshold;
    if (b->tier == 1 && (c == th || c == th * 4 || c == th * 16) && g_pipe[1] >= 0) {
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
    // the sampling handler must never block: drop requests if the pipe is full
    fcntl(g_pipe[1], F_SETFL, O_NONBLOCK);
    g_pipe[0] = reserve_host_fd(g_pipe[0]);
    g_pipe[1] = reserve_host_fd(g_pipe[1]);
    pthread_t th;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_attr_setstacksize(&attr, 8 << 20);
    if (pthread_create(&th, &attr, compiler_thread, nullptr) != 0) fatal("tier2: thread");
}

// Sampling (tier-2 hotness, --profile) uses one CPU-time timer per guest thread that signals that
// very thread: a process-wide ITIMER_PROF delivers SIGPROF to an arbitrary thread, often one
// sleeping in a syscall, which starved busy threads of samples.
static bool g_sampling;

void tier2_thread_start(ThreadCtx* t) {
    if (!g_sampling || !t || t->prof_timer_ok) return;
    struct sigevent sev {};
    sev.sigev_notify = SIGEV_THREAD_ID;
    sev.sigev_signo = kSampleSig;
    sev._sigev_un._tid = (int)syscall(SYS_gettid);
    timer_t tm;
    if (syscall(SYS_timer_create, CLOCK_THREAD_CPUTIME_ID, &sev, &tm) != 0) return;
    struct itimerspec its {};
    its.it_interval.tv_nsec = 1000000;
    its.it_value.tv_nsec = 1000000;
    syscall(SYS_timer_settime, tm, 0, &its, nullptr);
    t->prof_timer = tm;
    t->prof_timer_ok = true;
}

void tier2_thread_stop(ThreadCtx* t) {
    if (t && t->prof_timer_ok) { syscall(SYS_timer_delete, t->prof_timer); t->prof_timer_ok = false; }
}

void tier2_after_fork(ThreadCtx* t) {
    if (t) t->prof_timer_ok = false;   // POSIX timers are not inherited by fork
    tier2_thread_start(t);
    if (!g_t2_enabled) return;
    release_host_fd(g_pipe[0]);
    release_host_fd(g_pipe[1]);
    close(g_pipe[0]);
    close(g_pipe[1]);
    start_compiler_thread();
}

void tier2_init(bool enable) {
    g_t2_enabled = enable;
    if (const char* e = getenv("XEF_T2_CALL_MOVES")) g_tier2_max_call_moves_per_ms = strtoull(e, nullptr, 0);
    if (enable) start_compiler_thread();
    if (!enable && !g_opt.profile) return;
    struct sigaction sa {};
    sa.sa_sigaction = sample_handler;
    sa.sa_flags = SA_SIGINFO | SA_RESTART;
    sigfillset(&sa.sa_mask);   // see trap_handler: guest signals must see the interrupted context
    sa.sa_flags |= SA_ONSTACK;
    sigaction(kSampleSig, &sa, nullptr);
    g_sampling = true;
    tier2_thread_start(tls_thread);   // the main thread; others start theirs in thread_trampoline
}

}  // namespace xef
