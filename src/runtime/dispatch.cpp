// XEF — translation driver and per-thread execution loop.
#include "runtime/dispatch.h"

#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "backend/x64/codegen.h"
#include "frontend/a64/translate.h"
#include "os/signals.h"
#include "os/syscalls.h"
#include "profile/stats.h"

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

// Translate the block at pc (caller holds no lock). Returns host entry.
static BlockMeta* translate(ThreadCtx* t, GuestAddr pc) {
    u64 t0 = g_opt.stats ? stats_now() : 0;
    ir::Block& blk = *t->blk;
    a64::TranslateOpts topt;
    topt.max_insts = g_opt.max_block_insts;
    a64::translate_block(pc, blk, topt);
    if (g_opt.dump_ir) ir::dump(blk, stderr);
    std::lock_guard<std::mutex> lk(g_cache.lock);
    if (BlockMeta* b = g_cache.lookup(pc)) return b;  // raced with another thread
    int nexits = backend::count_exits(blk);
    BlockMeta* meta = g_cache.alloc_meta(nexits);
    meta->start = pc;
    meta->end = blk.end;
    const size_t kMax = 256 * 1024;
    u8* code = g_cache.alloc_code(kMax);
    x64::Assembler as(code, kMax);
    backend::CodegenOut out;
    if (!backend::emit_tier1(blk, as, meta, out)) fatal("block at %#lx too large", (unsigned long)pc);
    meta->code = code;
    meta->code_size = (u32)out.size;
    meta->tier = 1;
    g_cache.commit_code(code, out.size);
    if (g_opt.dump_code) dump_code(code, out.size, pc);
    // link exits whose targets already exist
    for (int i = 0; i < out.nexits; i++) {
        ExitInfo* e = &meta->exits[i];
        if (BlockMeta* tb = g_cache.lookup(e->target)) {
            link_exit(e, tb->code);
            e->next_in = tb->incoming;
            tb->incoming = e;
        }
    }
    g_cache.register_block(meta);
    g_cache.publish(meta);
    if (g_opt.stats) {
        g_stats.blocks_t1++;
        g_stats.guest_insts_translated += blk.guest_insts;
        g_stats.host_bytes += out.size;
        g_stats.translate_ns += stats_now() - t0;
    }
    return meta;
}

u8* get_or_translate(ThreadCtx* t, GuestAddr pc) {
    BlockMeta* b = g_cache.lookup(pc);
    if (!b) b = translate(t, pc);
    return b->code;
}

void code_invalidate_range(GuestAddr start, u64 len) {
    // TODO(milestone 3): page-indexed block lists; unpublish + unlink affected blocks.
    (void)start;
    (void)len;
}

[[noreturn]] void cpu_loop(ThreadCtx* t) {
    CpuState* st = t->st;
    EnterFn enter = (EnterFn)g_cache.stubs.enter;
    IbtcEntry* ibtc = (IbtcEntry*)st->ibtc;
    u8* host = get_or_translate(t, st->pc);
    for (;;) {
        enter(st, host);
        switch (st->exit_reason) {
        case EXIT_LINK: {
            ExitInfo* e = (ExitInfo*)st->exit_info;
            st->pc = e->target;
            if (g_opt.stats) g_stats.exits_link++;
            BlockMeta* tb = g_cache.lookup(e->target);
            if (!tb) tb = translate(t, e->target);
            {
                std::lock_guard<std::mutex> lk(g_cache.lock);
                if (!e->linked) {
                    link_exit(e, tb->code);
                    e->next_in = tb->incoming;
                    tb->incoming = e;
                }
            }
            host = tb->code;
            break;
        }
        case EXIT_LOOKUP: {
            if (g_opt.stats) g_stats.exits_lookup++;
            host = get_or_translate(t, st->pc);
            g_cache.ibtc_insert(ibtc, st->pc, host);
            break;
        }
        case EXIT_SYSCALL:
            if (g_opt.stats) g_stats.exits_syscall++;
            do_syscall(st);
            if (st->pending_signal) signals_deliver_pending(st);
            host = get_or_translate(t, st->pc);
            break;
        case EXIT_UNDEF:
            fatal("unsupported instruction at %#lx: %08x", (unsigned long)st->pc, (u32)st->exit_info);
        case EXIT_BRK:
            fatal("guest trap (brk/hlt #%#lx) at %#lx", (unsigned long)(st->exit_info & 0xffff), (unsigned long)st->pc);
        default:
            fatal("unknown exit reason %lu", (unsigned long)st->exit_reason);
        }
    }
}

// ---- helpers called from JIT code ----

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

extern "C" u64 xef_helper_crc32(u64 crc, u64 data, u64 size_and_c) {
    static bool inited = (crc_init(), true);
    (void)inited;
    int size = size_and_c & 0xff;
    int t = (size_and_c >> 8) & 1;
    u32 c = (u32)crc;
    for (int i = 0; i < size; i++) c = crc_table[t][(c ^ (u8)(data >> (8 * i))) & 0xff] ^ (c >> 8);
    return c;
}

}  // namespace xef
