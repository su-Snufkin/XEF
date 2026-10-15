// XEF — translation driver and per-thread execution loop.
#include "runtime/dispatch.h"
#include "thunks/thunks.h"
#include "runtime/verify.h"

#include <elf.h>
#include <sys/mman.h>
#include <cstring>
#include <string>
#include <vector>
#include <time.h>
#include <unistd.h>

#include "backend/x64/codegen.h"
#include "frontend/a64/translate.h"
#include "os/signals.h"
#include "os/syscalls.h"
#include "loader/darwin_hle.h"
#include "loader/macho_image.h"
#include "os/thread.h"
#include "profile/stats.h"
#include "runtime/aot.h"

namespace xef {

Options g_opt;

static u8* g_stub_mem_end;
void vconst_pool_init();

void runtime_init() {
    g_cache.init(1ull << 30);
    u8* p = g_cache.alloc_code(4096);
    x64::Assembler as(p, 4096);
    backend::emit_runtime_stubs(as, g_cache.stubs);
    g_cache.commit_code(p, as.size());
    g_stub_mem_end = as.cur();
    vconst_pool_init();
}

static void dump_code(const u8* p, size_t n, GuestAddr pc) {
    char path[64];
    snprintf(path, sizeof path, "/tmp/xef-%lx.bin", (unsigned long)pc);
    FILE* f = fopen(path, "wb");
    if (f) { fwrite(p, 1, n, f); fclose(f); }
    fprintf(stderr, "host code for %#lx: %zu bytes -> %s\n", (unsigned long)pc, n, path);
}

// --trace: ring of the last guest blocks entered by this thread
static thread_local GuestAddr tls_trace[64];
static thread_local unsigned tls_trace_n;
static void trace_dump() {
    unsigned n = tls_trace_n < 64 ? tls_trace_n : 64;
    for (unsigned i = n; i > 0; i--) {
        char d[512];
        log_msg("  trace[-%u] %s", i, describe_addr(tls_trace[(tls_trace_n - i) & 63], d, sizeof d));
    }
}

// XEF_SPLIT=lo-hi[,lo-hi...] (debugging aid): blocks starting there are translated one
// instruction at a time (bisecting translation bugs)
static bool split_here(GuestAddr pc) {
    static u64 rng[8][2];
    static int nrng = [] {
        int n = 0;
        const char* e = getenv("XEF_SPLIT");
        while (e && *e && n < 8) {
            if (sscanf(e, "%lx-%lx", &rng[n][0], &rng[n][1]) == 2) n++;
            e = strchr(e, ',');
            if (e) e++;
        }
        return n;
    }();
    for (int i = 0; i < nrng; i++)
        if (pc >= rng[i][0] && pc < rng[i][1]) return true;
    return false;
}

// Where a block continues without a jump: the not-taken side of its conditional exit or the
// target of its unconditional one (0: indirect / call / helper call inside -> no fall-through).
static GuestAddr fall_through(const ir::Block& b) {
    GuestAddr ft = 0;
    for (int v = 1; v < b.n; v++) {
        const ir::Inst& in = b.insts[v];
        if (in.op == ir::Op::Helper) return 0;   // IC IVAU: what follows must be entered by a jump
        if (in.op == ir::Op::ExitJump) ft = in.imm;
        else if (in.op == ir::Op::ExitCond || in.op == ir::Op::ExitCbz || in.op == ir::Op::ExitTbz) ft = in.imm2;
    }
    return ft;
}

// Translate the block at pc (caller holds no lock). Returns its BlockMeta.
// Up to kChain (8) blocks are translated together when each falls through into the next one that
// is not translated yet: they are laid out back to back (no jump between them), their exit
// stubs after the last body. A member depends on the guest code of every member after it.
static BlockMeta* translate(ThreadCtx* t, GuestAddr pc) {
    constexpr int kChain = 8;
    u64 t0 = g_opt.stats ? stats_now() : 0;
    static thread_local ir::Block* chain_blk[kChain];
    chain_blk[0] = t->blk;
    a64::TranslateOpts topt;
    topt.max_insts = g_opt.max_block_insts;
    if (split_here(pc)) topt.max_insts = 1;
    if (!a64::guest_readable(pc)) {
        CpuState* st = t->st;
        if (g_is_darwin && (pc <= 0x1000 || pc == g_darwin_mach_header || pc == g_darwin_exit_trampoline || pc == g_darwin_thread_exit_trampoline)) {
            XEF_LOG(1, "xef-osx: program or thread returned cleanly at %#lx with code %d (lr=%#lx x16=%#lx x17=%#lx sp=%#lx)", (unsigned long)pc, (int)st->x[0], (unsigned long)st->x[30], (unsigned long)st->x[16], (unsigned long)st->x[17], (unsigned long)st->x[kGuestSP]);
            if (pc == 0 && st->x[30] != 0 && st->x[30] != g_darwin_exit_trampoline)
                fprintf(stderr, "xef-osx: warning: jump to address 0 (lr=%#lx)\n", (unsigned long)st->x[30]);
            darwin_run_exit_handlers();
            guest_process_exit((int)st->x[0]);
        }
        char lr[512];
        if (g_opt.trace) trace_dump();
        if (st->exit_reason == EXIT_LINK) {
            ExitInfo* e = (ExitInfo*)st->exit_info;
            log_msg("  via exit of block %#lx..%#lx (kind %d)", (unsigned long)e->owner->start,
                    (unsigned long)e->owner->end, e->kind);
        }
        fatal("guest jumped to unmapped address %#lx (lr=%s, exit reason %lu)", (unsigned long)pc,
              describe_addr(st->x[30], lr, sizeof lr), (unsigned long)st->exit_reason);
    }
    if (BlockMeta* b = aot::try_load(pc)) {
        if (g_opt.stats) g_stats.translate_ns += stats_now() - t0;
        return b;
    }
    bool chain_ok = !g_opt.trace && !g_opt.dump_ir && !g_opt.dump_code;
    static thread_local PeekLog peeks[kChain];
    GuestAddr pcs[kChain];
    int nc = 0;
    u64 ep;
    std::unique_lock<std::mutex> lk(g_cache.lock, std::defer_lock);
    for (;;) {
        ep = g_cache.epoch.load(std::memory_order_seq_cst);
        nc = 0;
        for (GuestAddr cur = pc;;) {
            if (!chain_blk[nc]) chain_blk[nc] = new ir::Block();
            a64::TranslateOpts o = topt;
            if (nc && split_here(cur)) o.max_insts = 1;
            peeks[nc].reset();
            a64::set_peek_log(&peeks[nc]);
            a64::translate_block(cur, *chain_blk[nc], o);
            a64::set_peek_log(nullptr);
            ir::Block& b = *chain_blk[nc];
            if (peeks[nc].overflow) b.flags_live_out = true;   // don't depend on code we can't track
            g_cache.mark_code(cur, b.end, peeks[nc].overflow ? nullptr : &peeks[nc]);   // before the epoch check
            pcs[nc++] = cur;
            GuestAddr ft = chain_ok ? fall_through(b) : 0;
            bool again = ft && nc < kChain && a64::guest_readable(ft) && !g_cache.lookup(ft);
            for (int k = 0; k < nc && again; k++) if (pcs[k] == ft) again = false;
            if (!again) break;
            cur = ft;
        }
        lk.lock();
        if (g_cache.epoch.load(std::memory_order_seq_cst) == ep) break;
        lk.unlock();   // code was invalidated meanwhile: decode again
    }
    if (g_opt.dump_ir && g_opt.dump_wants(pc)) ir::dump(*chain_blk[0], stderr);
    if (BlockMeta* b = g_cache.lookup(pc)) return b;  // raced with another thread
    for (int k = 1; k < nc; k++)
        if (g_cache.lookup(pcs[k])) { nc = k; break; }   // translated by another thread meanwhile
    const size_t kMax = 256 * 1024;
    u8* code = g_cache.alloc_code(kMax * nc);
    x64::Assembler as(code, kMax * nc);
    as.relocs = aot::sink();
    BlockMeta* metas[kChain];
    static thread_local backend::CodegenOut outs[kChain];
    backend::RegionBodyGen* gens[kChain];
    for (int k = 0; k < nc; k++) {
        ir::Block& b = *chain_blk[k];
        BlockMeta* meta = g_cache.alloc_meta(backend::count_exits(b));
        meta->start = pcs[k];
        meta->end = b.end;
        meta->tier = 1;
        meta->chain_prev = k ? metas[k - 1] : nullptr;
        outs[k].reset();
        backend::CodegenCtx ctx;
        ctx.fall_pc = k + 1 < nc ? pcs[k + 1] : 0;
        meta->code = as.cur();
        gens[k] = backend::emit_region_body(b, as, meta, outs[k], ctx, false);
        if (!gens[k]) fatal("block at %#lx too large", (unsigned long)pcs[k]);
        meta->code_size = (u32)outs[k].size;
        g_cache.set_pcmap(meta, outs[k].pcmap, outs[k].npcmap);
        metas[k] = meta;
    }
    for (int k = 0; k < nc; k++)
        if (!backend::finish_region_body(gens[k], true)) fatal("block at %#lx too large", (unsigned long)pcs[k]);
    g_cache.commit_code(code, as.size());
    if (as.relocs) {   // persistent translation cache: before the exits are linked
        GuestAddr ends[kChain];
        const PcMapEntry* pms[kChain];
        int npm[kChain];
        bool ok = true;
        for (int k = 0; k < nc; k++) {
            ends[k] = chain_blk[k]->end;
            pms[k] = g_cache.pcmap_of(metas[k]);
            npm[k] = (int)metas[k]->host_pc_map_len;
            ok &= npm[k] == outs[k].npcmap;
            metas[k]->nexits = (u16)outs[k].nexits;
        }
        if (ok) aot::capture(nc, pcs, ends, metas, peeks, pms, npm, code, as.size(), *as.relocs);
    }
    for (int k = 0; k < nc; k++) {
        BlockMeta* meta = metas[k];
        if (g_opt.dump_code && g_opt.dump_wants(pcs[k])) dump_code(meta->code, meta->code_size, pcs[k]);
        meta->nexits = (u16)outs[k].nexits;
        // link exits whose targets already exist
        for (int i = 0; i < meta->nexits; i++) {
            ExitInfo* e = &meta->exits[i];
            if (BlockMeta* tb = g_opt.trace ? nullptr : g_cache.lookup(e->target)) {
                link_exit(e, tb->code);
                e->next_in = tb->incoming;
                tb->incoming = e;
            }
        }
        g_cache.register_block(meta);
    }
    // a member depends on its own code and peeks and on those of every member after it (it falls
    // through into them): accumulate from the last one, one merged set of ranges per member
    PeekLog acc;
    for (int k = nc - 1; k >= 0; k--) {
        acc.add(pcs[k], chain_blk[k]->end);
        for (int i = 0; !peeks[k].overflow && i < peeks[k].n; i++) acc.add(peeks[k].r[i].lo, peeks[k].r[i].hi);
        if (!acc.overflow) { g_cache.add_deps(metas[k], acc); continue; }
        for (int j = k; j < nc; j++)   // ranges too far apart to merge: one call per member
            g_cache.add_deps(metas[k], pcs[j], chain_blk[j]->end, peeks[j].overflow ? nullptr : &peeks[j]);
    }
    for (int k = nc - 1; k >= 0; k--) g_cache.publish(metas[k]);
    if (g_opt.stats) {
        for (int k = 0; k < nc; k++) {
            g_stats.blocks_t1++;
            g_stats.guest_insts_translated += chain_blk[k]->guest_insts;
            g_stats.host_bytes += metas[k]->code_size;
        }
        g_stats.translate_ns += stats_now() - t0;
    }
    return metas[0];
}

u8* get_or_translate(ThreadCtx* t, GuestAddr pc) {
    if (g_opt.trace) tls_trace[tls_trace_n++ & 63] = pc;
    BlockMeta* b = g_cache.lookup(pc);
    if (!b) b = translate(t, pc);
    return b->code;
}

void code_invalidate_range(GuestAddr start, u64 len) {
    // translations in flight must not be published; then nothing to do where no code was translated
    g_cache.epoch.fetch_add(1, std::memory_order_seq_cst);
    if (g_opt.stats) __atomic_fetch_add(&g_stats.inval_requests, 1, __ATOMIC_RELAXED);
    if (!g_cache.may_have_code(start, start + len)) {
        if (g_opt.stats) __atomic_fetch_add(&g_stats.inval_unmarked, 1, __ATOMIC_RELAXED);
        return;
    }
    std::lock_guard<std::mutex> lk(g_cache.lock);
    if (g_cache.invalidate_range(start, start + len)) {
        g_cache.scrub_ibtcs();
        if (g_opt.stats) g_stats.invalidations++;
    }
}

// Runs guest code on this thread. Nested runs (host -> guest calls, thunks.cpp) return when the
// guest returns to the callback trampoline (HLT #0x5847); the outermost run never returns.
static void run_guest(ThreadCtx* t, bool nested) {
    CpuState* st = t->st;
    if (!nested) {
        XEF_LOG(1, "=== START GUEST: pc=%#lx, lr=%#lx, sp=%#lx ===", (unsigned long)st->pc, (unsigned long)st->x[30], (unsigned long)st->x[kGuestSP]);
    }
    EnterFn enter = (EnterFn)g_cache.stubs.enter;
    IbtcEntry* ibtc = (IbtcEntry*)st->ibtc;
    u8* host = get_or_translate(t, st->pc);
    for (;;) {
        // a signal that arrived while this thread was in the runtime (not in translated code, so
        // no single-step to a block boundary) is only marked pending: deliver it before re-entering
        // the JIT, or a linked hot loop could run forever without seeing it
        if (__atomic_load_n(&st->pending_signal, __ATOMIC_ACQUIRE)) {
            signals_deliver_pending(st);
            host = get_or_translate(t, st->pc);
        }
        {   // XEF_DBG_PC=lo-hi (hex): log the full register file at every block entry in the range (use with --trace --max-block 1)
            static const bool on = [] { return getenv("XEF_DBG_PC") != nullptr; }();
            static u64 lo, hi;
            static std::once_flag once;
            if (on) {
                std::call_once(once, [] { if (sscanf(getenv("XEF_DBG_PC"), "%lx-%lx", &lo, &hi) != 2) { lo = 0; hi = ~0ull; } });
                if (st->pc >= lo && st->pc < hi) {
                    fprintf(stderr, "pc=%#lx", (unsigned long)st->pc);
                    for (int r = 0; r < 31; r++) fprintf(stderr, " x%d=%lx", r, (unsigned long)st->x[r]);
                    fprintf(stderr, "\n");
                }
            }
        }
        bool vf = verify_wants(st->pc) && verify_before(t, st);
        enter(st, host);
        if (vf) verify_after(st);
        switch (st->exit_reason) {
        case EXIT_LINK: {
            ExitInfo* e = (ExitInfo*)st->exit_info;
            st->pc = e->target;
            if (g_opt.stats) g_stats.exits_link++;
            BlockMeta* tb = g_cache.lookup(e->target);
            if (!tb) tb = translate(t, e->target);
            {
                std::lock_guard<std::mutex> lk(g_cache.lock);
                // neither link from nor into code that was invalidated meanwhile
                if (!e->linked && !(tb->flags & BF_DEAD) && !(e->owner->flags & BF_DEAD) && !g_opt.trace) {
                    link_exit(e, tb->code);
                    e->next_in = tb->incoming;
                    tb->incoming = e;
                }
            }
            host = tb->code;
            if (g_opt.trace) tls_trace[tls_trace_n++ & 63] = e->target;
            break;
        }
        case EXIT_LOOKUP: {
            if (g_opt.stats) g_stats.exits_lookup++;
            if (g_opt.trace) tls_trace[tls_trace_n++ & 63] = st->pc;
            if (g_is_darwin && (st->pc == g_darwin_mach_header || st->pc == g_darwin_exit_trampoline)) {
                XEF_LOG(1, "xef-osx: binary returned with exit code %d", (int)st->x[0]);
                darwin_run_exit_handlers();
                guest_process_exit((int)st->x[0]);
            }
            host = get_or_translate(t, st->pc);
            {   // indirect branches / returns assume NZCV dead at their target (a64::g_abi_flags)
                static bool warned;
                if (a64::g_abi_flags && !warned && a64::nzcv_read_first(st->pc)) {
                    warned = true;
                    char d[512];
                    log_msg("warning: indirect branch target %s reads NZCV set before the branch; "
                            "if the program misbehaves, run with XEF_STRICT_FLAGS=1", describe_addr(st->pc, d, sizeof d));
                }
            }
            if (!g_opt.trace) g_cache.ibtc_insert(ibtc, st->pc, host);
            // an invalidation between lookup and insert may have missed this entry
            if (BlockMeta* nb = g_cache.lookup(st->pc); !nb || nb->code != host)
                __atomic_store_n(&ibtc[(st->pc >> 2) & (kIbtcEntries - 1)].guest, 1ull, __ATOMIC_SEQ_CST);
            break;
        }
        case EXIT_SYSCALL:
            if (g_opt.stats) g_stats.exits_syscall++;
            if (st->exit_info == kThunkExit) thunk_dispatch(st);
            else if (st->exit_info == kCallbackRetExit) {
                if (nested) return;
                fatal("guest returned to the host-callback trampoline outside a callback");
            } else do_syscall(st);
            if (st->pending_signal) signals_deliver_pending(st);
            host = get_or_translate(t, st->pc);
            break;
        case EXIT_SIGNAL:
            signals_deliver_pending(st);
            host = get_or_translate(t, st->pc);
            break;
        case EXIT_UNDEF:
        case EXIT_BRK: {
            // like the kernel: UDF/unknown encodings and HLT raise SIGILL, BRK raises SIGTRAP, with
            // pc at the instruction. Only a guest handler gets them (feature probing with
            // sigsetjmp, JITs' traps); otherwise stop with a diagnostic, as before.
            bool brk = st->exit_reason == EXIT_BRK && !(st->exit_info & 0x10000);
            int sig = brk ? SIGTRAP : SIGILL;
            if (g_actions_handler(sig)) {
                XEF_LOG(1, "%s at %#lx: delivered to the guest", brk ? "brk" : "undefined instruction",
                        (unsigned long)st->pc);
                siginfo_t si {};
                si.si_signo = sig;
                si.si_code = brk ? TRAP_BRKPT : ILL_ILLOPC;
                si.si_addr = (void*)st->pc;
                t->sync_sig = sig;
                t->sync_info = si;
                signals_deliver_pending(st);
                host = get_or_translate(t, st->pc);
                break;
            }
            if (g_opt.trace) trace_dump();
            if (st->exit_reason == EXIT_UNDEF)
                fatal("unsupported instruction at %#lx (lr=%#lx, sp=%#lx): %08x",
                      (unsigned long)st->pc, (unsigned long)st->x[30], (unsigned long)st->x[kGuestSP], (u32)st->exit_info);
            {
                std::string d = g_is_darwin ? dyld_describe(st->pc) : std::string();
                fatal("guest trap (brk/hlt #%#lx) at %#lx %s", (unsigned long)(st->exit_info & 0xffff), (unsigned long)st->pc, d.c_str());
            }
        }
        default:
            fatal("unknown exit reason %lu", (unsigned long)st->exit_reason);
        }
    }
}

[[noreturn]] void cpu_loop(ThreadCtx* t) {
    run_guest(t, false);
    __builtin_unreachable();
}

void cpu_run_nested(ThreadCtx* t) { run_guest(t, true); }

// ---- helpers called from JIT code ----

// SVC #0 without leaving enter()'s frame (stubs.cpp, syscall_exit): st->pc and the guest registers
// are in CpuState. Returns the host code to continue at. Not used under XEF_TRACE / XEF_VERIFY
// (codegen_t1.cpp), which need every block entry to go through run_guest.
extern "C" u8* xef_syscall_fast(CpuState* st) {
    if (g_opt.stats) g_stats.exits_syscall++;
    do_syscall(st);
    if (__atomic_load_n(&st->pending_signal, __ATOMIC_ACQUIRE)) signals_deliver_pending(st);
    return get_or_translate(st->thread, st->pc);
}

extern "C" u64 xef_helper_sysreg(u64, u64, u64 id) {
    switch (id) {
    case ir::SYS_CNTVCT: {
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        return (u64)ts.tv_sec * 1000000000ull + (u64)ts.tv_nsec;
    }
    default: return 0;
    }
}

static u32 crc_table[2][256];
static void crc_init() {
    for (int t = 0; t < 2; t++) {
        u32 poly = t ? 0x82F63B78u : 0xEDB88320u;
        for (u32 i = 0; i < 256; i++) {
            u32 c = i;
            for (int k = 0; k < 8; k++) c = (c >> 1) ^ ((c & 1) ? poly : 0);
            crc_table[t][i] = c;
        }
    }
}

// IC IVAU Xt: the guest finished writing code in this cache line (CTR_EL0.IminLine = 64 bytes).
extern "C" u64 xef_helper_ic_ivau(u64 addr, u64, u64) {
    code_invalidate_range(addr & ~63ull, 64);
    return 0;
}

extern "C" u64 xef_helper_crc32(u64 crc, u64 data, u64 size_and_c) {
    static bool inited = (crc_init(), true);
    (void)inited;
    int size = size_and_c & 0xff;
    int t = (size_and_c >> 8) & 1;
    u32 c = (u32)crc;
    for (int i = 0; i < size; i++) c = crc_table[t][(c ^ (u8)(data >> (8 * i))) & 0xff] ^ (c >> 8);
    return c;
}

// FJCVTZS (FEAT_JSCVT): double -> int32 with JavaScript ToInt32 semantics (truncate toward zero, modulo 2^32;
// NaN/Inf -> 0). Returns the result in bits 0-31 and the Z flag in bit 32: Z = the conversion was exact, i.e. the
// input is an integer in the int32 range and not -0.0.
extern "C" u64 xef_helper_fjcvtzs(u64 bits, u64, u64) {
    u64 sign = bits >> 63, frac = bits & ((1ull << 52) - 1);
    int exp = (int)((bits >> 52) & 0x7ff);
    if (exp == 0x7ff) return 0;
    if (exp == 0) return (frac == 0 && !sign) ? (1ull << 32) : 0;   // +0.0 exact, -0.0 and denormals not
    u64 m = frac | (1ull << 52);
    int e = exp - 1075;                                              // value = m * 2^e
    u32 r;
    if (e >= 0) r = e >= 32 ? 0 : (u32)(m << e);
    else r = -e >= 64 ? 0 : (u32)(m >> -e);
    if (sign) r = 0u - r;
    double d;
    memcpy(&d, &bits, 8);
    bool exact = d == __builtin_trunc(d) && d >= -2147483648.0 && d <= 2147483647.0;
    return (u64)r | ((u64)exact << 32);
}

}  // namespace xef

namespace xef::regmap {

Reg g_map[32];
static const char* g_map_name = "gcc";

// .comment of an ELF file ("GCC: (Ubuntu ...)", "clang version ..."), empty if unreadable
static std::string elf_comment(const char* path) {
    std::string out;
    FILE* f = fopen(path, "rb");
    if (!f) return out;
    Elf64_Ehdr eh;
    if (fread(&eh, sizeof eh, 1, f) == 1 && !memcmp(eh.e_ident, ELFMAG, SELFMAG) && eh.e_shentsize == sizeof(Elf64_Shdr) &&
        eh.e_shnum > 0 && eh.e_shnum < 4096 && eh.e_shstrndx < eh.e_shnum) {
        std::vector<Elf64_Shdr> sh(eh.e_shnum);
        if (fseek(f, (long)eh.e_shoff, SEEK_SET) == 0 && fread(sh.data(), sizeof(Elf64_Shdr), sh.size(), f) == sh.size()) {
            const Elf64_Shdr& ss = sh[eh.e_shstrndx];
            std::string names(ss.sh_size < (1u << 20) ? ss.sh_size : 0, '\0');
            if (!names.empty() && fseek(f, (long)ss.sh_offset, SEEK_SET) == 0 &&
                fread(&names[0], 1, names.size(), f) == names.size())
                for (const Elf64_Shdr& s : sh)
                    if (s.sh_name < names.size() && !strcmp(&names[s.sh_name], ".comment") && s.sh_size < (1u << 16)) {
                        out.assign(s.sh_size, '\0');
                        if (fseek(f, (long)s.sh_offset, SEEK_SET) != 0 || fread(&out[0], 1, out.size(), f) != out.size())
                            out.clear();
                        break;
                    }
        }
    }
    fclose(f);
    return out;
}

void select(const char* host_exe_path) {
    bool clang = false;
    if (const char* e = getenv("XEF_REGMAP")) clang = !strcmp(e, "clang");
    else if (g_is_darwin) clang = true;
    else if (host_exe_path) {
        std::string c = elf_comment(host_exe_path);
        for (char& ch : c) if (!ch) ch = '\n';
        clang = c.find("clang version") != std::string::npos;
    }
    memcpy(g_map, clang ? kMapClang : kMapGcc, sizeof g_map);
    g_map_name = clang ? "clang" : "gcc";
    XEF_LOG(1, "register mapping: %s", g_map_name);
}

const char* name() { return g_map_name; }

}  // namespace xef::regmap
