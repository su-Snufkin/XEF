// XEF — translation verifier: a reference interpreter for the scalar IR (see verify.h).
#include "runtime/verify.h"

#include <cstdlib>
#include <cstring>
#include <vector>

#include "frontend/a64/translate.h"
#include "ir/ir.h"
#include "runtime/code_cache.h"
#include "runtime/cpu_state.h"
#include "runtime/dispatch.h"
#include "backend/vec_ref.h"

extern "C" xef::u64 xef_ftoi_helper(xef::u64 bits, xef::u64 desc, xef::u64 fbits);
extern "C" xef::u64 xef_itof_helper(xef::u64 v, xef::u64 desc, xef::u64 fbits);

namespace xef {

using namespace ir;

static u64 g_lo = 1, g_hi = 0;
static bool g_on = [] {
    const char* e = getenv("XEF_VERIFY");
    if (!e) return false;
    if (sscanf(e, "%lx-%lx", &g_lo, &g_hi) != 2) { g_lo = 0; g_hi = ~0ull; }
    return true;
}();

bool verify_enabled() { return g_on; }

static u64 g_checked_total, g_failed_total;
void verify_report() {
    log_msg("verify: %lu blocks checked, %lu mismatches", (unsigned long)g_checked_total, (unsigned long)g_failed_total);
}

bool verify_wants(GuestAddr pc) { return g_on && pc >= g_lo && pc < g_hi; }

namespace {

struct StoreRec { u64 addr; u64 val; int size; };

struct Expect {
    bool valid = false;
    GuestAddr start = 0;
    u64 x[32];
    V128 v[32];
    u32 nzcv;
    bool flags_live;
    u64 next_pc;
    std::vector<StoreRec> stores;
};
thread_local Expect tls_exp;
thread_local ir::Block* tls_blk;


u32 eflags_nzcv(u64 e) {   // canonical EFLAGS: SF=N ZF=Z CF=!C OF=V
    return (u32)((((e >> 7) & 1) << 3) | (((e >> 6) & 1) << 2) | ((!(e & 1)) << 1) | ((e >> 11) & 1));
}

bool cond_holds(u32 f, int c) {
    bool n = f & 8, z = f & 4, cc = f & 2, v = f & 1;
    bool r;
    switch (c >> 1) {
    case 0: r = z; break;
    case 1: r = cc; break;
    case 2: r = n; break;
    case 3: r = v; break;
    case 4: r = cc && !z; break;
    case 5: r = n == v; break;
    case 6: r = n == v && !z; break;
    default: return true;
    }
    return (c & 1) && c != 15 ? !r : r;
}

u64 tmask(Type t) { return t == Type::I32 ? 0xffffffffull : ~0ull; }
int tbits(Type t) { return t == Type::I32 ? 32 : 64; }

u32 nz(u64 r, int bits) {
    u64 m = bits == 32 ? 0xffffffffull : ~0ull;
    r &= m;
    return (u32)(((r >> (bits - 1)) & 1) << 3 | (r == 0) << 2);
}

u32 add_flags(u64 a, u64 b, u64 cin, int bits) {
    u64 m = bits == 32 ? 0xffffffffull : ~0ull;
    a &= m; b &= m;
    unsigned __int128 s = (unsigned __int128)a + b + cin;
    u64 r = (u64)s & m;
    bool c = bits == 32 ? (s >> 32) & 1 : (u64)(s >> 64) & 1;
    u64 sb = 1ull << (bits - 1);
    bool v = ((a ^ r) & (b ^ r) & sb) != 0;
    return nz(r, bits) | (c << 1) | v;
}

u64 load_mem(u64 addr, int size, const std::vector<StoreRec>& st) {
    u8 b[8];
    memcpy(b, (const void*)addr, size);
    for (const StoreRec& s : st)   // apply buffered stores, oldest first
        for (int i = 0; i < s.size; i++) {
            u64 a = s.addr + i;
            if (a >= addr && a < addr + size) b[a - addr] = (u8)(s.val >> (8 * i));
        }
    u64 v = 0;
    memcpy(&v, b, size);
    return v;
}

u32 fcmp_nzcv(const V128& a, const V128& b, int fs) {
    double x, y;
    if (fs == 8) { memcpy(&x, a.b, 8); memcpy(&y, b.b, 8); }
    else { float f, g; memcpy(&f, a.b, 4); memcpy(&g, b.b, 4); x = f; y = g; }
    if (x != x || y != y) return 0x3;   // unordered: C V
    if (x == y) return 0x6;             // Z C
    return x < y ? 0x8 : 0x2;           // N / C
}

u64 rev_bytes(u64 x, int bits) { return bits == 32 ? __builtin_bswap32((u32)x) : __builtin_bswap64(x); }

bool interpret(const Block& b, const CpuState& in, Expect& ex) {
    std::vector<u64> val(b.n, 0);
    std::vector<V128> vv(b.n);
    for (int g = 0; g < 32; g++) ex.x[g] = in.x[g];
    memcpy(ex.v, in.v, sizeof ex.v);
    u32 flags_in = eflags_nzcv(in.eflags);
    ex.nzcv = flags_in;
    ex.stores.clear();
    for (int v = 1; v < b.n; v++) {
        const Inst& i = b.insts[v];
        u64 A = i.a ? val[i.a] : 0, B = i.b ? val[i.b] : 0, C = i.c ? val[i.c] : 0;
        u64 m = tmask(i.ty);
        int bits = tbits(i.ty);
        u64 r = 0;
        switch (i.op) {
        case Op::Nop: case Op::Barrier: continue;
        case Op::Const: r = i.imm; break;
        case Op::GetReg: r = ex.x[i.aux & 31]; break;
        case Op::SetReg: ex.x[i.aux & 31] = A; continue;
        case Op::GetFlags: r = ex.nzcv; break;
        case Op::SetFlags: ex.nzcv = (u32)A; continue;
        case Op::Add: r = A + B; break;
        case Op::Sub: r = A - B; break;
        case Op::And: r = A & B; break;
        case Op::Or: r = A | B; break;
        case Op::Xor: r = A ^ B; break;
        case Op::AndNot: r = A & ~B; break;
        case Op::OrNot: r = A | ~B; break;
        case Op::XorNot: r = A ^ ~B; break;
        case Op::Shl: r = (A & m) << (B & (bits - 1)); break;
        case Op::Lshr: r = (A & m) >> (B & (bits - 1)); break;
        case Op::Ashr: r = (u64)(sext(A & m, bits) >> (B & (bits - 1))); break;
        case Op::Ror: { int s = (int)(B & (bits - 1)); A &= m; r = s ? (A >> s) | (A << (bits - s)) : A; break; }
        case Op::Not: r = ~A; break;
        case Op::Neg: r = -A; break;
        case Op::Mul: r = A * B; break;
        case Op::UMulH: r = (u64)(((unsigned __int128)A * B) >> 64); break;
        case Op::SMulH: r = (u64)(((__int128)(i64)A * (i64)B) >> 64); break;
        case Op::UDiv: A &= m; B &= m; r = B ? A / B : 0; break;
        case Op::SDiv: {
            i64 a = sext(A & m, bits), d = sext(B & m, bits);
            if (!d) r = 0;
            else if (d == -1) r = (u64)-a;
            else r = (u64)(a / d);
            break;
        }
        case Op::Clz: A &= m; r = A ? (u64)(__builtin_clzll(A) - (64 - bits)) : (u64)bits; break;
        case Op::Cls: {
            i64 s = sext(A & m, bits);
            u64 x = (u64)(s ^ (s >> 63)) & m;   // leading copies of the sign bit, minus the sign bit
            r = x ? (u64)(__builtin_clzll(x) - (64 - bits) - 1) : (u64)(bits - 1);
            break;
        }
        case Op::Rbit: { u64 x = A & m, y = 0; for (int k = 0; k < bits; k++) if (x >> k & 1) y |= 1ull << (bits - 1 - k); r = y; break; }
        case Op::Bswap: r = rev_bytes(A & m, bits); break;
        case Op::Rev16: { u64 x = A & m; r = ((x & 0x00ff00ff00ff00ffull) << 8) | ((x >> 8) & 0x00ff00ff00ff00ffull); break; }
        case Op::Rev32InWords: { u64 x = A; r = (u64)__builtin_bswap32((u32)x) | ((u64)__builtin_bswap32((u32)(x >> 32)) << 32); break; }
        case Op::Sext: r = (u64)sext(A & (i.size >= 64 ? ~0ull : ((1ull << i.size) - 1)), i.size); break;
        case Op::Zext: r = A & (i.size >= 64 ? ~0ull : ((1ull << i.size) - 1)); break;
        case Op::Select: r = cond_holds((u32)A, i.aux) ? B : C; break;
        case Op::FlagsSub: r = add_flags(A, ~B, 1, i.size); break;
        case Op::FlagsAdd: r = add_flags(A, B, 0, i.size); break;
        case Op::FlagsLogic: r = nz(A, i.size); break;
        case Op::FlagsAdc: r = add_flags(A, B, (C >> 1) & 1, i.size); break;
        case Op::FlagsSbc: r = add_flags(A, ~B, (C >> 1) & 1, i.size); break;
        case Op::Adc: r = A + B + ((C >> 1) & 1); break;
        case Op::Sbc: r = A + ~B + ((C >> 1) & 1); break;
        case Op::FlagsCCmp:
            if (cond_holds((u32)C, i.aux)) r = i.sub ? add_flags(A, ~B, 1, i.size) : add_flags(A, B, 0, i.size);
            else r = i.imm & 15;
            break;
        case Op::FlagsFromNZCV: r = (A >> 28) & 15; break;
        case Op::NZCVFromFlags: r = (A & 15) << 28; break;
        case Op::Load: {
            u64 x = load_mem(A, i.size, ex.stores);
            if (i.aux & 1) x = (u64)sext(x, i.size * 8);
            r = x;
            break;
        }
        case Op::Store: ex.stores.push_back({A, B, i.size}); continue;
        case Op::ExitJump: ex.next_pc = i.imm; continue;
        case Op::ExitCall: ex.next_pc = i.imm; continue;
        case Op::ExitCond: ex.next_pc = cond_holds((u32)A, i.aux) ? i.imm : i.imm2; continue;
        case Op::ExitCbz: {
            bool zero = (A & tmask(b.insts[i.a].ty)) == 0;
            ex.next_pc = (i.aux ? !zero : zero) ? i.imm : i.imm2;
            continue;
        }
        case Op::ExitTbz: { bool set = (A >> i.size) & 1; ex.next_pc = (i.aux ? set : !set) ? i.imm : i.imm2; continue; }
        case Op::ExitIndirect: case Op::ExitCallIndirect: case Op::ExitRet: ex.next_pc = A; continue;
        case Op::VGet: vv[v] = ex.v[i.aux & 31]; continue;
        case Op::VSet: ex.v[i.aux & 31] = vv[i.a]; continue;
        case Op::VConst: memcpy(vv[v].b, &i.imm, 8); memcpy(vv[v].b + 8, &i.imm2, 8); continue;
        case Op::VOp:
            vec_ref(i.sub, i.size, i.aux, i.imm, vv[i.a], i.b ? vv[i.b] : vv[i.a], i.c ? vv[i.c] : vv[i.a], vv[v], in.fpcr);
            continue;
        case Op::VLoad: {
            V128 t{};
            for (int k = 0; k < i.size; k += 8) {
                u64 w = load_mem(A + k, i.size - k < 8 ? i.size - k : 8, ex.stores);
                memcpy(t.b + k, &w, i.size - k < 8 ? i.size - k : 8);
            }
            vv[v] = t;
            continue;
        }
        case Op::VStore:
            for (int k = 0; k < i.size; k += 8) {
                u64 w = 0;
                int n = i.size - k < 8 ? i.size - k : 8;
                memcpy(&w, vv[i.b].b + k, n);
                ex.stores.push_back({A + k, w, n});
            }
            continue;
        case Op::GprToV: {
            int es = i.size;
            V128 t{};
            if (i.aux == 1) { t = vv[i.b]; memcpy(t.b + i.imm * es, &A, es); }
            else if (i.aux == 0) for (int k = 0; k < 16; k += es) memcpy(t.b + k, &A, es);
            else memcpy(t.b, &A, es);
            vv[v] = t;
            continue;
        }
        case Op::VToGpr: {
            u64 x = 0;
            memcpy(&x, vv[i.a].b + i.imm * i.size, i.size);
            if (i.aux & 1) x = (u64)sext(x, i.size * 8);
            r = x;
            break;
        }
        case Op::VSelect: {
            V128 t = cond_holds((u32)A, i.aux) ? vv[i.b] : vv[i.c];
            if (i.size < 16) memset(t.b + i.size, 0, 16 - i.size);
            vv[v] = t;
            continue;
        }
        case Op::FToI: {
            if (i.size != 4 && i.size != 8) return false;
            u64 bits = 0;
            memcpy(&bits, vv[i.a].b, i.size);
            u64 desc = (u64)i.size | ((u64)(i.aux & 0xf) << 8) | ((u64)((i.aux >> 4) & 1) << 12) | ((u64)(i.ty == Type::I64 ? 8 : 4) << 16);
            r = xef_ftoi_helper(bits, desc, i.imm);
            break;
        }
        case Op::IToF: {
            bool src64 = b.insts[i.a].ty == Type::I64;
            u64 desc = (u64)i.size | ((u64)(i.aux & 1) << 12) | ((u64)(src64 ? 8 : 4) << 16);
            u64 bits = xef_itof_helper(src64 ? A : (A & 0xffffffffull), desc, i.imm);
            V128 t{};
            memcpy(t.b, &bits, i.size);
            vv[v] = t;
            continue;
        }
        case Op::FCmpFlags:
            if (i.size != 4 && i.size != 8) return false;
            r = fcmp_nzcv(vv[i.a], vv[i.b], i.size);
            break;
        case Op::FCCmpFlags:
            if (i.size != 4 && i.size != 8) return false;
            r = cond_holds((u32)C, i.aux) ? fcmp_nzcv(vv[i.a], vv[i.b], i.size) : (i.imm & 15);
            break;
        default: return false;   // atomics / helpers / system registers: not modelled
        }
        val[v] = (i.ty == Type::Flags) ? r : (r & m);
    }
    return true;
}

}  // namespace

bool verify_before(ThreadCtx*, CpuState* st) {
    tls_exp.valid = false;
    BlockMeta* meta = g_cache.lookup(st->pc);
    if (!meta || meta->tier != 1) return false;
    if (!tls_blk) tls_blk = new ir::Block();
    a64::TranslateOpts o;
    o.max_insts = (int)((meta->end - meta->start) / 4);
    if (o.max_insts <= 0) return false;
    a64::translate_block(st->pc, *tls_blk, o);
    if (tls_blk->end != meta->end) return false;
    tls_exp.start = st->pc;
    tls_exp.flags_live = tls_blk->flags_live_out;
    if (!interpret(*tls_blk, *st, tls_exp)) return false;
    tls_exp.valid = true;
    return true;
}

void verify_after(CpuState* st) {
    if (!tls_exp.valid) return;
    tls_exp.valid = false;
    // a signal interrupted the block (or is about to be delivered): the states legitimately differ
    if (st->exit_reason == EXIT_SIGNAL || st->pending_signal) return;
    u64 next = st->exit_reason == EXIT_LINK ? ((ExitInfo*)st->exit_info)->target : st->pc;
    char msg[4096];
    int n = 0;
    for (int g = 0; g < 32; g++)
        if (st->x[g] != tls_exp.x[g])
            n += snprintf(msg + n, sizeof msg - n, " x%d=%#lx(want %#lx)", g, (unsigned long)st->x[g],
                          (unsigned long)tls_exp.x[g]);
    for (int g = 0; g < 32; g++)
        if (memcmp(st->v[g], tls_exp.v[g].b, 16) && n < (int)sizeof msg - 120) {
            u64 a0, a1, w0, w1;
            memcpy(&a0, st->v[g], 8); memcpy(&a1, st->v[g] + 8, 8);
            memcpy(&w0, tls_exp.v[g].b, 8); memcpy(&w1, tls_exp.v[g].b + 8, 8);
            n += snprintf(msg + n, sizeof msg - n, " v%d=%016lx%016lx(want %016lx%016lx)", g, (unsigned long)a1,
                          (unsigned long)a0, (unsigned long)w1, (unsigned long)w0);
        }
    if ((st->exit_reason == EXIT_LINK || st->exit_reason == EXIT_LOOKUP) && next != tls_exp.next_pc)
        n += snprintf(msg + n, sizeof msg - n, " pc=%#lx(want %#lx)", (unsigned long)next, (unsigned long)tls_exp.next_pc);
    if (tls_exp.flags_live && eflags_nzcv(st->eflags) != tls_exp.nzcv)
        n += snprintf(msg + n, sizeof msg - n, " nzcv=%x(want %x)", eflags_nzcv(st->eflags), tls_exp.nzcv);
    for (const StoreRec& s : tls_exp.stores) {
        u64 got = 0;
        memcpy(&got, (const void*)s.addr, s.size);
        u64 want = load_mem(s.addr, s.size, tls_exp.stores);
        if (got != want && n < (int)sizeof msg - 100)
            n += snprintf(msg + n, sizeof msg - n, " [%#lx]=%#lx(want %#lx)", (unsigned long)s.addr,
                          (unsigned long)got, (unsigned long)want);
    }
    __atomic_add_fetch(&g_checked_total, 1, __ATOMIC_RELAXED);
    if (n) {
        __atomic_add_fetch(&g_failed_total, 1, __ATOMIC_RELAXED);
        char d[512];
        log_msg("verify: block %s:%s", describe_addr(tls_exp.start, d, sizeof d), msg);
    }
}

}  // namespace xef
