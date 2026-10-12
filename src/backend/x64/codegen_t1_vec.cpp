// XEF — tier-1 code generation for SIMD / FP operations.
//
// Vector values live in XMM registers (all 16 are block-local temporaries in
// tier 1); guest V registers live in CpuState. Hot operations are lowered to
// SSE4.1 / AVX (VEX 3-operand forms when available); everything else calls the
// C reference implementation (exact AArch64 semantics).
#include "backend/vec_ref.h"
#include "backend/x64/t1_internal.h"

namespace xef {
extern "C" void xef_vec_helper(CpuState* st, u64 desc, u64 imm);
extern "C" u64 xef_ftoi_helper(u64 bits, u64 desc, u64 fbits);
extern "C" u64 xef_itof_helper(u64 v, u64 desc, u64 fbits);
u8* vconst_pool_get(u64 lo, u64 hi);
}  // namespace xef

namespace xef::backend {
namespace t1 {

namespace sse {
constexpr SseOp P(u8 op) { return {0x66, 1, op, 0}; }
constexpr SseOp P38(u8 op) { return {0x66, 2, op, 0}; }
constexpr SseOp P3A(u8 op) { return {0x66, 3, op, 0}; }
constexpr SseOp PADD[9] = {{}, P(0xFC), P(0xFD), {}, P(0xFE), {}, {}, {}, P(0xD4)};
constexpr SseOp PSUB[9] = {{}, P(0xF8), P(0xF9), {}, P(0xFA), {}, {}, {}, P(0xFB)};
constexpr SseOp PCMPEQ[9] = {{}, P(0x74), P(0x75), {}, P(0x76), {}, {}, {}, P38(0x29)};
constexpr SseOp PCMPGT[9] = {{}, P(0x64), P(0x65), {}, P(0x66), {}, {}, {}, P38(0x37)};
constexpr SseOp PMAXS[9] = {{}, P38(0x3C), P(0xEE), {}, P38(0x3D), {}, {}, {}, {}};
constexpr SseOp PMINS[9] = {{}, P38(0x38), P(0xEA), {}, P38(0x39), {}, {}, {}, {}};
constexpr SseOp PMAXU[9] = {{}, P(0xDE), P38(0x3E), {}, P38(0x3F), {}, {}, {}, {}};
constexpr SseOp PMINU[9] = {{}, P(0xDA), P38(0x3A), {}, P38(0x3B), {}, {}, {}, {}};
constexpr SseOp PABS[9] = {{}, P38(0x1C), P38(0x1D), {}, P38(0x1E), {}, {}, {}, {}};
constexpr SseOp PUNPCKL[9] = {{}, P(0x60), P(0x61), {}, P(0x62), {}, {}, {}, P(0x6C)};
constexpr SseOp PUNPCKH[9] = {{}, P(0x68), P(0x69), {}, P(0x6A), {}, {}, {}, P(0x6D)};
constexpr SseOp PAND = P(0xDB), PANDN = P(0xDF), POR = P(0xEB), PXOR = P(0xEF);
constexpr SseOp PMULLW = P(0xD5), PMULLD = P38(0x40), PMULHW = P(0xE5), PMULHUW = P(0xE4);
constexpr SseOp PMULUDQ = P(0xF4), PMULDQ = P38(0x28);
constexpr SseOp PADDUSB = P(0xDC), PADDUSW = P(0xDD), PSUBUSB = P(0xD8), PSUBUSW = P(0xD9);
constexpr SseOp PADDSB = P(0xEC), PADDSW = P(0xED), PSUBSB = P(0xE8), PSUBSW = P(0xE9);
constexpr SseOp PAVGB = P(0xE0), PAVGW = P(0xE3);
constexpr SseOp PSHUFB = P38(0x00), PALIGNR = P3A(0x0F), PSHUFD = P(0x70);
constexpr SseOp PBLENDW = P3A(0x0E), PSADBW = P(0xF6), PHADDW = P38(0x01), PHADDD = P38(0x02);
constexpr SseOp PHMINPOSUW = P38(0x41);
constexpr SseOp PMOVZX[5] = {{}, P38(0x30), P38(0x33), {}, P38(0x35)};   // bw, wd, dq
constexpr SseOp PMOVSX[5] = {{}, P38(0x20), P38(0x23), {}, P38(0x25)};
constexpr SseOp INSERTPS = P3A(0x21), SHUFPS = {0, 1, 0xC6, 0};
constexpr SseOp PINSRB = P3A(0x20), PINSRW = P(0xC4), PINSRD = P3A(0x22), PINSRQ = {0x66, 3, 0x22, 1};
constexpr SseOp PEXTRB = P3A(0x14), PEXTRW = P3A(0x15), PEXTRD = P3A(0x16), PEXTRQ = {0x66, 3, 0x16, 1};
constexpr SseOp MOVD_XR = P(0x6E), MOVQ_XR = {0x66, 1, 0x6E, 1}, MOVD_RX = P(0x7E), MOVQ_RX = {0x66, 1, 0x7E, 1};
constexpr SseOp MOVQ_XX = {0xF3, 1, 0x7E, 0};
// FP: index by size (4 -> ps/ss, 8 -> pd/sd)
constexpr SseOp FPV(u8 op, int es) { return {(u8)(es == 8 ? 0x66 : 0), 1, op, 0}; }
constexpr SseOp FPS(u8 op, int es) { return {(u8)(es == 8 ? 0xF2 : 0xF3), 1, op, 0}; }
constexpr SseOp ROUNDV(int es) { return P3A(es == 8 ? 0x09 : 0x08); }
constexpr SseOp ROUNDS(int es) { return P3A(es == 8 ? 0x0B : 0x0A); }
constexpr SseOp FMA231V(u8 base, int es) { return {0x66, 2, base, (u8)(es == 8)}; }
constexpr SseOp FMA231S(u8 base, int es) { return {0x66, 2, (u8)(base + 1), (u8)(es == 8)}; }
}  // namespace sse

using namespace sse;

// ------------------------------------------------------------------ xmm allocation

Xmm T1::alloc_x() {
    for (int i = 0; i < 16; i++)
        if (!xowner_[i] && !(xpinned_ & (1 << i))) return (Xmm)i;
    int best = -1, best_score = -1;
    for (int i = 0; i < 16; i++) {
        if (xpinned_ & (1 << i)) continue;
        Val o = xowner_[i];
        int score = vi_[o].last + (vi_[o].vhome >= 0 ? 100000 : 0);
        if (score > best_score) { best_score = score; best = i; }
    }
    if (best < 0) fatal("codegen: out of xmm registers at ir %d", cur_);
    evict_x(best);
    return (Xmm)best;
}

void T1::evict_x(int x) {
    Val o = xowner_[x];
    if (!o) return;
    VI& vi = vi_[o];
    if (vi.vhome >= 0) {
        vi.k = L_VMEM;
    } else {
        int s = -1;
        for (int i = 0; i < 16; i++) if (!(vspill_used_ & (1u << i))) { s = i; break; }
        if (s < 0) fatal("codegen: out of vector spill slots");
        vspill_used_ |= 1u << s;
        as_.movdqu_store(mem(R15, XEF_ST(vspill) + s * 16), (Xmm)x);
        vi.k = L_VSPILL;
        vi.slot = (i8)s;
    }
    xowner_[x] = 0;
}

Mem T1::vconst_mem(u64 lo, u64 hi) { return rip(vconst_pool_get(lo, hi)); }

void T1::load_vconst(Xmm x, u64 lo, u64 hi) {
    if (lo == 0 && hi == 0) as_.xop(PXOR, x, x, x);
    else if (lo == ~0ull && hi == ~0ull) as_.xop(PCMPEQ[4], x, x, x);
    else as_.xop1_m({0, 1, 0x28, 0}, x, vconst_mem(lo, hi));   // movaps
}

Xmm T1::xreg(Val v) {
    Val r = resolve(v);
    VI& x = vi_[r];
    const Inst& in = I(r);
    if (x.k == L_XMM) { xpinned_ |= 1 << x.reg; return (Xmm)x.reg; }
    if (x.k == L_NONE && in.op == Op::VGet) { x.k = L_VMEM; x.vhome = (i8)in.aux; }
    if (x.k == L_NONE && in.op == Op::VConst) {
        Xmm t = new_x(r);
        load_vconst(t, in.imm, in.imm2);
        return t;
    }
    Xmm t = alloc_x();
    if (x.k == L_VMEM) as_.movdqu_load(t, mem(R15, st_v(x.vhome)));
    else if (x.k == L_VSPILL) {
        as_.movdqu_load(t, mem(R15, XEF_ST(vspill) + x.slot * 16));
        vspill_used_ &= ~(1u << x.slot);
    } else fatal("codegen: vector value %%%d has no location (%s)", r, op_name(in.op));
    x.k = L_XMM;
    x.reg = t;
    xowner_[t] = r;
    xpinned_ |= 1 << t;
    return t;
}

void T1::evacuate_vreg(int g, int upto) {
    for (int v = 1; v < cur_; v++) {
        VI& x = vi_[v];
        if (x.dead || x.last <= upto) continue;
        const Inst& in = I(v);
        bool lazy = x.k == L_NONE && in.op == Op::VGet && in.aux == g;
        if (x.vhome == g || lazy) {
            if (x.k == L_VMEM || lazy) {
                if (lazy) { x.k = L_VMEM; x.vhome = (i8)g; }
                Xmm t = alloc_x();
                as_.movdqu_load(t, mem(R15, st_v(g)));
                x.k = L_XMM; x.reg = t; xowner_[t] = (Val)v;
            }
            x.vhome = -1;
        }
    }
}

void T1::zero_upper(Xmm x, int bytes) {
    switch (bytes) {
    case 16: return;
    case 8: as_.xop1(MOVQ_XX, x, x); return;
    case 4: as_.xop(INSERTPS, x, x, x, 0x0E); return;
    case 2: as_.xop_m(PAND, x, x, vconst_mem(0xffff, 0)); return;
    case 1: as_.xop_m(PAND, x, x, vconst_mem(0xff, 0)); return;
    default: fatal("zero_upper %d", bytes);
    }
}

// Spill state for a C call: operands are written by the caller beforehand.
void T1::call_prepare(Val, Val, Val) {
    for (int ti_ = 0; ti_ < ntemps_; ti_++) if (Reg r = temps_[ti_]; true) if (owner_[r] && vi_[owner_[r]].last > cur_) evict(r);
    for (int ti_ = 0; ti_ < ntemps_; ti_++) if (Reg r = temps_[ti_]; true) owner_[r] = 0;
    for (int x = 0; x < 16; x++) {
        if (xowner_[x] && vi_[xowner_[x]].last > cur_) evict_x(x);
        xowner_[x] = 0;
    }
    save_caller_saved_guests();
    if (eflags_ && flags_needed_after(cur_)) {
        as_.pushfq();
        as_.pop(mem(R15, XEF_ST(flags_spill)));
        spilled_flags_ = eflags_;
    }
    eflags_ = 0;
}

void T1::emit_vec_helper(Val v) {
    const Inst& in = I(v);
    Val ops[3] = {in.a, in.b, in.c};
    for (int k = 0; k < 3; k++) {
        if (!ops[k]) continue;
        Xmm x = xreg(ops[k]);
        as_.movdqu_store(mem(R15, XEF_ST(vtmp) + k * 16), x);
    }
    call_prepare(in.a, in.b, in.c);
    as_.lea(8, RDI, mem(R15, -kStateBias));
    u64 desc = (u64)in.sub | ((u64)in.size << 16) | ((u64)in.aux << 24);
    as_.mov_imm(RSI, desc);
    as_.mov_imm(RDX, in.imm);
    as_.mov_imm(RAX, (u64)&xef_vec_helper);
    as_.call(RAX);
    restore_caller_saved_guests();
    xpinned_ = 0;
    Xmm d = new_x(v);
    as_.movdqu_load(d, mem(R15, XEF_ST(vtmp) + 3 * 16));
}

// ------------------------------------------------------------------ dispatch

void T1::emit_vec(Val v) {
    const Inst& in = I(v);
    switch (in.op) {
    case Op::VGet: return;  // lazy: lives in CpuState until used
    case Op::VConst: return;  // materialized on use
    case Op::VSet: {
        int g = in.aux;
        Val src = resolve(in.a);
        VI& x = vi_[src];
        if (x.k == L_VMEM && x.vhome == g) return;  // writing back the same value
        evacuate_vreg(g, cur_);
        Xmm t = xreg(src);
        as_.movdqu_store(mem(R15, st_v(g)), t);
        if (I(src).op != Op::VConst) x.vhome = (i8)g;
        return;
    }
    case Op::VLoad: {
        Mem m = addr_mem(in.a);
        Xmm x = new_x(v);
        record_pc();
        switch (in.size) {
        case 16: as_.movdqu_load(x, m); break;
        case 8: as_.movq_load(x, m); break;
        case 4: as_.movd_load(x, m); break;
        case 2: case 1: {
            Reg t = alloc_temp(); pinned_ |= 1 << t;
            as_.movzx_load(t, m, in.size);
            as_.movd_xr(x, t);
            break;
        }
        default: fatal("vload size");
        }
        return;
    }
    case Op::VStore: {
        Mem m = addr_mem(in.a);
        Xmm x = xreg(in.b);
        record_pc();
        switch (in.size) {
        case 16: as_.movdqu_store(m, x); break;
        case 8: as_.movq_store(m, x); break;
        case 4: as_.movd_store(m, x); break;
        case 2: case 1: {
            Reg t = alloc_temp(); pinned_ |= 1 << t;
            as_.movd_rx(t, x);
            as_.mov(in.size, m, t);
            break;
        }
        default: fatal("vstore size");
        }
        return;
    }
    case Op::GprToV: {
        int es = in.size;
        Reg r = to_reg(in.a); pinned_ |= 1 << r;
        if (in.aux == 1) {  // INS into existing vector
            Xmm src = xreg(in.b);
            Xmm d = new_x(v);
            if (d != src) as_.movaps(d, src);
            int idx = (int)in.imm;
            switch (es) {
            case 1: as_.xop_gx(PINSRB, d, r, idx, d); break;
            case 2: as_.xop_gx(PINSRW, d, r, idx, d); break;
            case 4: as_.xop_gx(PINSRD, d, r, idx, d); break;
            default: as_.xop_gx(PINSRQ, d, r, idx, d); break;
            }
            return;
        }
        Xmm d = new_x(v);
        if (es == 8) as_.xop_gx(MOVQ_XR, d, r);
        else if (es == 2 && in.aux == 2) {
            Reg t = alloc_temp(); pinned_ |= 1 << t;
            as_.movzx16(t, r);
            as_.xop_gx(MOVD_XR, d, t);
        } else if (es == 1 && in.aux == 2) {
            Reg t = alloc_temp(); pinned_ |= 1 << t;
            as_.movzx8(t, r);
            as_.xop_gx(MOVD_XR, d, t);
        } else as_.xop_gx(MOVD_XR, d, r);
        if (in.aux == 0) {  // DUP
            switch (es) {
            case 1: { Xmm z = alloc_x(); xpinned_ |= 1 << z; as_.xop(PXOR, z, z, z); as_.xop(PSHUFB, d, d, z); break; }
            case 2: as_.xop1({0xF2, 1, 0x70, 0}, d, d, 0); as_.xop1(PSHUFD, d, d, 0); break;   // pshuflw + pshufd
            case 4: as_.xop1(PSHUFD, d, d, 0); break;
            default: as_.xop1(PSHUFD, d, d, 0x44); break;
            }
        }
        return;
    }
    case Op::VToGpr: {
        int es = in.size;
        Xmm x = xreg(in.a);
        Reg d = dest_for(v, sz(in.ty));
        int idx = (int)in.imm;
        bool sign = in.aux & 1;
        if (idx == 0 && es == 8) as_.xop_gx(MOVQ_RX, x, d);
        else if (idx == 0 && es == 4) as_.xop_gx(MOVD_RX, x, d);
        else {
            switch (es) {
            case 1: as_.xop_gx(PEXTRB, x, d, idx); break;
            case 2: as_.xop_gx(PEXTRW, x, d, idx); break;
            case 4: as_.xop_gx(PEXTRD, x, d, idx); break;
            default: as_.xop_gx(PEXTRQ, x, d, idx); break;
            }
        }
        if (sign) as_.movsx(sz(in.ty), d, d, es);
        finish_def(v, d);
        return;
    }
    case Op::VSelect: {
        if (in.aux == ir::AL || in.aux == ir::NV) {
            Xmm xt = xreg(in.b);
            Xmm d = new_x(v);
            as_.movaps(d, xt);
            zero_upper(d, in.size);
            return;
        }
        Xmm xt = xreg(in.b);
        Xmm xf = xreg(in.c);
        Xmm d = new_x(v);
        as_.movaps(d, xf);
        need_flags(in.a, in.aux);
        u8* j = as_.jcc_fwd8(invert(x86_cond((ir::Cond)in.aux)));
        as_.movaps(d, xt);
        as_.patch_rel8_here(j);
        zero_upper(d, in.size);
        return;
    }
    case Op::FCmpFlags: emit_fcmp(v); return;
    case Op::FCCmpFlags: emit_fccmp(v); return;
    case Op::FToI: emit_ftoi(v); return;
    case Op::IToF: emit_itof(v); return;
    case Op::VOp: emit_vop(v); return;
    default: fatal("codegen: vector op %s not implemented", op_name(in.op));
    }
}

// ------------------------------------------------------------------ FP compare

void T1::emit_fcmp_seq(Val a, Val b, int fs, bool) {
    Xmm xa = xreg(a), xb = xreg(b);
    // ucomis{s,d} then rebuild canonical NZCV via an integer compare (see docs/ARCHITECTURE.md)
    as_.xop1({(u8)(fs == 8 ? 0x66 : 0), 1, 0x2E, 0}, xa, xb);
    as_.setcc(CA, RAX);
    as_.setcc(CB, RCX);
    as_.setcc(CP, R11);
    as_.movzx8(RAX, RAX);
    as_.movzx8(RCX, RCX);
    as_.movzx8(R11, R11);
    as_.shift_imm(SHL, 4, R11, 31);
    as_.alu(OR, 4, RAX, R11);
    as_.alu(CMP, 4, RAX, RCX);
}

void T1::emit_fcmp(Val v) {
    const Inst& in = I(v);
    xpin(in.a); xpin(in.b);
    take_reg(RAX); take_reg(RCX); take_reg(R11);
    clobber_flags();
    emit_fcmp_seq(in.a, in.b, in.size, in.aux & 1);
    eflags_ = v;
}

void T1::emit_fccmp(Val v) {
    const Inst& in = I(v);
    Xmm xa = xreg(in.a), xb = xreg(in.b);
    (void)xa; (void)xb;
    take_reg(RAX); take_reg(RCX); take_reg(R11);
    pinned_ |= (1 << RAX) | (1 << RCX) | (1 << R11);
    need_flags(in.c);
    ir::Cond c = (ir::Cond)in.aux;
    if (c == ir::AL || c == ir::NV) {
        emit_fcmp_seq(in.a, in.b, in.size, false);
    } else {
        Label then, done;
        as_.jcc(x86_cond(c), then);
        emit_set_const_flags((u32)in.imm);
        as_.jmp(done);
        as_.bind(then);
        emit_fcmp_seq(in.a, in.b, in.size, false);
        as_.bind(done);
    }
    eflags_ = v;
}

// ------------------------------------------------------------------ conversions

void T1::emit_ftoi(Val v) {
    const Inst& in = I(v);
    int fs = in.size;
    int rnd = in.aux & 0xf;
    bool sgn = in.aux & 0x10;
    int is = sz(in.ty);
    bool fast = in.imm == 0 && (fs == 4 || fs == 8) && rnd != FR_TIEAWAY && (sgn || is == 4);
    if (!fast) {
        // generic helper: pass raw FP bits in a GPR
        Xmm x = xreg(in.a);
        Reg t = alloc_temp(); pinned_ |= 1 << t;
        as_.xop_gx(fs == 8 ? MOVQ_RX : MOVD_RX, x, t);
        // stash into a spill-free path: use emit_call_c with a synthetic operand: move to rax first
        u64 desc = (u64)fs | ((u64)rnd << 8) | ((u64)sgn << 12) | ((u64)is << 16);
        // emit_call_c takes Val operands; build the call by hand
        for (int ti_ = 0; ti_ < ntemps_; ti_++) if (Reg r = temps_[ti_]; true) if (r != t && owner_[r] && vi_[owner_[r]].last > cur_) evict(r);
        for (int xx = 0; xx < 16; xx++) { if (xowner_[xx] && vi_[xowner_[xx]].last > cur_) evict_x(xx); xowner_[xx] = 0; }
        save_caller_saved_guests();
        if (eflags_ && flags_needed_after(cur_)) { as_.pushfq(); as_.pop(mem(R15, XEF_ST(flags_spill))); spilled_flags_ = eflags_; }
        eflags_ = 0;
        as_.mov(8, RDI, t);
        as_.mov_imm(RSI, desc);
        as_.mov_imm(RDX, in.imm);
        as_.mov_imm(RAX, (u64)&xef_ftoi_helper);
        as_.call(RAX);
        restore_caller_saved_guests();
        for (int ti_ = 0; ti_ < ntemps_; ti_++) if (Reg r = temps_[ti_]; true) owner_[r] = 0;
        pinned_ = 0;
        Reg d = alloc_temp(RAX);
        if (d != RAX) as_.mov(8, d, RAX);
        assign_reg(v, d);
        return;
    }
    Xmm x = xreg(in.a);
    clobber_flags();
    Xmm src = x;
    if (rnd != FR_ZERO) {
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        int mode = rnd == FR_TIEEVEN ? 0 : rnd == FR_NEGINF ? 1 : rnd == FR_POSINF ? 2 : 4;
        as_.xop(ROUNDS(fs), t, x, x, mode | 8);
        src = t;
    }
    Reg d = dest_for(v, is);
    pinned_ |= 1 << d;
    // cvtts{s,d}2si: signed 64-bit conversion when result is unsigned 32 or signed 64
    bool wide = is == 8 || !sgn;
    as_.xop_gx({(u8)(fs == 8 ? 0xF2 : 0xF3), 1, 0x2C, (u8)wide}, d, src);
    Reg t = alloc_temp(); pinned_ |= 1 << t;
    Label done, fix;
    if (sgn) {
        // indefinite (INT_MIN) -> fix NaN (0) / positive overflow (INT_MAX)
        if (is == 8) { as_.mov_imm(t, 0x8000000000000000ull); as_.alu(CMP, 8, d, t); }
        else as_.alu_imm(CMP, 4, d, (i32)0x80000000);
        as_.jcc(CNE, done);
        as_.xop1({(u8)(fs == 8 ? 0x66 : 0), 1, 0x2E, 0}, src, src);   // ucomis: PF=1 if NaN
        as_.mov_imm(t, 0);
        as_.cmov(CP, is, d, t);
        as_.jcc(CP, done);
        // sign of input
        as_.xop_gx(fs == 8 ? MOVQ_RX : MOVD_RX, src, t);
        as_.test(fs == 8 ? 8 : 4, t, t);
        as_.jcc(CS, done);  // negative: INT_MIN is correct (saturated)
        as_.mov_imm(d, is == 8 ? 0x7fffffffffffffffull : 0x7fffffffull);
        as_.bind(done);
    } else {
        // unsigned 32-bit result from a 64-bit signed conversion: clamp to [0, 2^32-1]
        as_.mov_imm(t, 0);
        as_.test(8, d, d);
        as_.cmov(CS, 8, d, t);          // negative or indefinite -> 0
        as_.mov_imm(t, 0xffffffffull);
        as_.alu(CMP, 8, d, t);
        as_.cmov(CA, 8, d, t);
        // indefinite from huge positive input: input > 0 and result was INT64_MIN -> max
        as_.xop_gx(fs == 8 ? MOVQ_RX : MOVD_RX, src, t);
        as_.test(fs == 8 ? 8 : 4, t, t);
        as_.jcc(CS, done);
        as_.xop1({(u8)(fs == 8 ? 0x66 : 0), 1, 0x2E, 0}, src, src);
        as_.jcc(CP, done);
        // positive non-NaN: if value >= 2^63 the conversion overflowed: compare against 2^32
        if (fs == 8) as_.xop1_m({0x66, 1, 0x2E, 0}, src, vconst_mem(0x41f0000000000000ull, 0));
        else as_.xop1_m({0, 1, 0x2E, 0}, src, vconst_mem(0x4f800000ull, 0));
        as_.jcc(CB, done);
        as_.mov_imm(d, 0xffffffffull);
        as_.bind(done);
        (void)fix;
    }
    finish_def(v, d);
}

void T1::emit_itof(Val v) {
    const Inst& in = I(v);
    int fs = in.size;
    bool sgn = in.aux & 1;
    Type st = I(in.a).ty;
    bool src64 = st == Type::I64;
    if (in.imm != 0 || (!sgn && src64) || (fs != 4 && fs != 8)) {
        Reg r = to_reg(in.a); pinned_ |= 1 << r;
        Reg t = alloc_temp(); pinned_ |= 1 << t;
        if (src64) as_.mov(8, t, r); else as_.mov(4, t, r);
        u64 desc = (u64)fs | ((u64)sgn << 12) | ((u64)(src64 ? 8 : 4) << 16);
        for (int ti_ = 0; ti_ < ntemps_; ti_++) if (Reg rr = temps_[ti_]; true) if (rr != t && owner_[rr] && vi_[owner_[rr]].last > cur_) evict(rr);
        for (int xx = 0; xx < 16; xx++) { if (xowner_[xx] && vi_[xowner_[xx]].last > cur_) evict_x(xx); xowner_[xx] = 0; }
        save_caller_saved_guests();
        if (eflags_ && flags_needed_after(cur_)) { as_.pushfq(); as_.pop(mem(R15, XEF_ST(flags_spill))); spilled_flags_ = eflags_; }
        eflags_ = 0;
        as_.mov(8, RDI, t);
        as_.mov_imm(RSI, desc);
        as_.mov_imm(RDX, in.imm);
        as_.mov_imm(RAX, (u64)&xef_itof_helper);
        as_.call(RAX);
        restore_caller_saved_guests();
        for (int ti_ = 0; ti_ < ntemps_; ti_++) if (Reg rr = temps_[ti_]; true) owner_[rr] = 0;
        pinned_ = 0;
        xpinned_ = 0;
        Xmm d = new_x(v);
        as_.xop_gx(MOVQ_XR, d, RAX);
        return;
    }
    Reg r = to_reg(in.a); pinned_ |= 1 << r;
    Xmm d = new_x(v);
    as_.xop(PXOR, d, d, d);
    SseOp cvt = {(u8)(fs == 8 ? 0xF2 : 0xF3), 1, 0x2A, 0};
    if (!sgn) {
        // unsigned 32-bit: zero-extend and use the 64-bit signed conversion
        Reg t = alloc_temp(); pinned_ |= 1 << t;
        as_.mov(4, t, r);
        cvt.w = 1;
        as_.xop_gx(cvt, d, t, -1, d);
    } else {
        cvt.w = src64;
        as_.xop_gx(cvt, d, r, -1, d);
    }
}

// ------------------------------------------------------------------ vector ops

void T1::emit_vop(Val v) {
    const Inst& in = I(v);
    int es = in.size;
    bool scalar = in.aux & 1, half = in.aux & 2;
    int out_bytes = scalar ? es : half ? 8 : 16;
    auto A = [&]() { return xreg(in.a); };
    auto B = [&]() { return xreg(in.b); };
    auto C = [&]() { return xreg(in.c); };
    auto bin = [&](SseOp o) -> Xmm {
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        as_.xop(o, d, a, b);
        return d;
    };
    auto bin_m = [&](SseOp o, Xmm a, u64 lo, u64 hi) -> Xmm {
        Xmm d = new_x(v);
        as_.xop_m(o, d, a, vconst_mem(lo, hi));
        return d;
    };
    auto rep = [&](u64 pattern, int bytes) -> u64 {
        u64 r = 0;
        for (int i = 0; i < 8; i += bytes) r |= pattern << (i * 8);
        return r;
    };
    auto finish = [&](Xmm d, bool already_zeroed = false) {
        if (!already_zeroed && out_bytes < 16) zero_upper(d, out_bytes);
    };
    auto helper = [&]() { emit_vec_helper(v); };

    bool avx = as_.avx;
    (void)avx;
    switch (in.sub) {
    // ---------------- bitwise
    case V_AND: finish(bin(PAND)); return;
    case V_ORR: finish(bin(POR)); return;
    case V_EOR: finish(bin(PXOR)); return;
    case V_BIC: {  // a & ~b = pandn(b, a)
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        as_.xop(PANDN, d, b, a);
        finish(d);
        return;
    }
    case V_ORN: {
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        as_.xop_m(PXOR, d, b, vconst_mem(~0ull, ~0ull));
        as_.xop(POR, d, d, a);
        finish(d);
        return;
    }
    case V_NOT: finish(bin_m(PXOR, A(), ~0ull, ~0ull)); return;
    case V_BSL: {  // ((x ^ y) & m) ^ y
        Xmm m = A(), x = B(), y = C();
        Xmm d = new_x(v);
        as_.xop(PXOR, d, x, y);
        as_.xop(PAND, d, d, m);
        as_.xop(PXOR, d, d, y);
        finish(d);
        return;
    }
    // ---------------- integer arithmetic
    case V_ADD: finish(bin(PADD[es])); return;
    case V_SUB: finish(bin(PSUB[es])); return;
    case V_MUL:
        if (es == 2) { finish(bin(PMULLW)); return; }
        if (es == 4) { finish(bin(PMULLD)); return; }
        return helper();
    case V_MLA: case V_MLS: {
        if (es != 2 && es != 4) return helper();
        Xmm a = A(), b = B(), c = C();
        Xmm d = new_x(v);
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        as_.xop(es == 2 ? PMULLW : PMULLD, t, a, b);
        as_.xop(in.sub == V_MLA ? PADD[es] : PSUB[es], d, c, t);
        finish(d);
        return;
    }
    case V_NEG: {
        Xmm a = A();
        Xmm d = new_x(v);
        as_.xop(PXOR, d, d, d);
        as_.xop(PSUB[es], d, d, a);
        finish(d);
        return;
    }
    case V_ABS:
        if (es == 8) return helper();
        { Xmm a = A(); Xmm d = new_x(v); as_.xop1(PABS[es], d, a); finish(d); }
        return;
    case V_SMAX: if (es == 8) return helper(); finish(bin(PMAXS[es])); return;
    case V_SMIN: if (es == 8) return helper(); finish(bin(PMINS[es])); return;
    case V_UMAX: if (es == 8) return helper(); finish(bin(PMAXU[es])); return;
    case V_UMIN: if (es == 8) return helper(); finish(bin(PMINU[es])); return;
    case V_UQADD: if (es == 1) { finish(bin(PADDUSB)); return; } if (es == 2) { finish(bin(PADDUSW)); return; } return helper();
    case V_UQSUB: if (es == 1) { finish(bin(PSUBUSB)); return; } if (es == 2) { finish(bin(PSUBUSW)); return; } return helper();
    case V_SQADD: if (es == 1) { finish(bin(PADDSB)); return; } if (es == 2) { finish(bin(PADDSW)); return; } return helper();
    case V_SQSUB: if (es == 1) { finish(bin(PSUBSB)); return; } if (es == 2) { finish(bin(PSUBSW)); return; } return helper();
    case V_UABD: case V_SABD: case V_UABDL: case V_SABDL: {
        if (es == 8) return helper();
        bool sg = in.sub == V_SABD || in.sub == V_SABDL;
        bool lng = in.sub == V_UABDL || in.sub == V_SABDL;
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        as_.xop(sg ? PMAXS[es] : PMAXU[es], d, a, b);
        as_.xop(sg ? PMINS[es] : PMINU[es], t, a, b);
        as_.xop(PSUB[es], d, d, t);          // |a - b| fits the element width (unsigned)
        if (lng) { as_.xop1(PMOVZX[es], d, d); return; }
        finish(d);
        return;
    }
    case V_UHADD: {   // (a + b) >> 1 = pavg(a, b) - ((a ^ b) & 1)
        if (es > 2) return helper();
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        as_.xop(es == 1 ? PAVGB : PAVGW, d, a, b);
        as_.xop(PXOR, t, a, b);
        u64 one = es == 1 ? 0x0101010101010101ull : 0x0001000100010001ull;
        as_.xop_m(PAND, t, t, vconst_mem(one, one));
        as_.xop(PSUB[es], d, d, t);
        finish(d);
        return;
    }
    case V_URHADD: if (es == 1) { finish(bin(PAVGB)); return; } if (es == 2) { finish(bin(PAVGW)); return; } return helper();
    case V_ADDP: {
        if (scalar) {  // d = a[0] + a[1] (64-bit)
            Xmm a = A();
            Xmm d = new_x(v);
            as_.xop1(PSHUFD, d, a, 0xEE);
            as_.xop(PADD[8], d, d, a);
            finish(d);
            return;
        }
        if (es == 2 || es == 4) {
            Xmm a = A(), b = B();
            Xmm d = new_x(v);
            if (half) {
                as_.xop(PUNPCKL[8], d, a, b);
                as_.xop(es == 2 ? PHADDW : PHADDD, d, d, d);
            } else as_.xop(es == 2 ? PHADDW : PHADDD, d, a, b);
            finish(d);
            return;
        }
        if (es == 8) {  // [a0+a1, b0+b1]
            Xmm a = A(), b = B();
            Xmm d = new_x(v);
            Xmm t = alloc_x(); xpinned_ |= 1 << t;
            as_.xop(PUNPCKL[8], d, a, b);
            as_.xop(PUNPCKH[8], t, a, b);
            as_.xop(PADD[8], d, d, t);
            return;
        }
        if (es == 1) {
            // pairwise bytes: sums of adjacent bytes; even = a & 0xff.., odd = a >> 8 per word
            Xmm a = A(), b = B();
            Xmm d = new_x(v);
            Xmm t = alloc_x(); xpinned_ |= 1 << t;
            Xmm u = alloc_x(); xpinned_ |= 1 << u;
            if (half) { as_.xop(PUNPCKL[8], d, a, b); }
            else { as_.movaps(d, a); }
            // process d (first source) and b (second) separately: words = lo + hi bytes
            auto pair = [&](Xmm dst, Xmm src) {
                as_.xshift_imm(0x71, 2, t, src, 8);              // psrlw t, src, 8
                as_.xop(PADD[1], dst, src, t);                    // low byte of each word = sum
            };
            if (half) {
                pair(u, d);
                as_.xop_m(PSHUFB, d, u, vconst_mem(0x0e0c0a0806040200ull, 0x8080808080808080ull));
            } else {
                pair(u, a);
                as_.xop_m(PSHUFB, u, u, vconst_mem(0x0e0c0a0806040200ull, 0x8080808080808080ull));
                Xmm w = alloc_x(); xpinned_ |= 1 << w;
                pair(w, b);
                as_.xop_m(PSHUFB, w, w, vconst_mem(0x0e0c0a0806040200ull, 0x8080808080808080ull));
                as_.xop(PUNPCKL[8], d, u, w);
            }
            finish(d);
            return;
        }
        return helper();
    }
    case V_UMAXP: case V_UMINP: case V_SMAXP: case V_SMINP: {
        if (scalar || es == 8) return helper();
        // de-interleave even/odd elements of concat(a,b) then max/min
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        Xmm ev = alloc_x(); xpinned_ |= 1 << ev;
        Xmm od = alloc_x(); xpinned_ |= 1 << od;
        if (es == 4) {
            if (half) {
                as_.xop(PUNPCKL[8], d, a, b);    // a0 a1 b0 b1
                as_.xop1(PSHUFD, ev, d, 0x08);   // a0 b0
                as_.xop1(PSHUFD, od, d, 0x0D);   // a1 b1
            } else {
                as_.xop(SHUFPS, ev, a, b, 0x88);
                as_.xop(SHUFPS, od, a, b, 0xDD);
            }
        } else {
            u64 lo = es == 1 ? 0x0e0c0a0806040200ull : 0x0d0c090805040100ull;
            u64 lo2 = es == 1 ? 0x0f0d0b0907050301ull : 0x0f0e0b0a07060302ull;
            if (half) {
                as_.xop(PUNPCKL[8], d, a, b);
                as_.xop_m(PSHUFB, ev, d, vconst_mem(lo, 0x8080808080808080ull));
                as_.xop_m(PSHUFB, od, d, vconst_mem(lo2, 0x8080808080808080ull));
            } else {
                Xmm t = alloc_x(); xpinned_ |= 1 << t;
                as_.xop_m(PSHUFB, ev, a, vconst_mem(lo, 0x8080808080808080ull));
                as_.xop_m(PSHUFB, t, b, vconst_mem(lo, 0x8080808080808080ull));
                as_.xop(PUNPCKL[8], ev, ev, t);
                as_.xop_m(PSHUFB, od, a, vconst_mem(lo2, 0x8080808080808080ull));
                as_.xop_m(PSHUFB, t, b, vconst_mem(lo2, 0x8080808080808080ull));
                as_.xop(PUNPCKL[8], od, od, t);
            }
        }
        SseOp o = in.sub == V_UMAXP ? PMAXU[es] : in.sub == V_UMINP ? PMINU[es] : in.sub == V_SMAXP ? PMAXS[es] : PMINS[es];
        as_.xop(o, d, ev, od);
        finish(d);
        return;
    }
    // ---------------- compares
    case V_CMEQ: finish(bin(PCMPEQ[es])); return;
    case V_CMGT: finish(bin(PCMPGT[es])); return;
    case V_CMGE: {  // ~(b > a)
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        as_.xop(PCMPGT[es], d, b, a);
        as_.xop_m(PXOR, d, d, vconst_mem(~0ull, ~0ull));
        finish(d);
        return;
    }
    case V_CMHS: case V_CMHI: {
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        if (es == 8) {
            Xmm t = alloc_x(); xpinned_ |= 1 << t;
            Mem sb = vconst_mem(0x8000000000000000ull, 0x8000000000000000ull);
            if (in.sub == V_CMHI) {  // a > b
                as_.xop_m(PXOR, d, a, sb);
                as_.xop_m(PXOR, t, b, sb);
                as_.xop(PCMPGT[8], d, d, t);
            } else {  // a >= b = ~(b > a)
                as_.xop_m(PXOR, d, b, sb);
                as_.xop_m(PXOR, t, a, sb);
                as_.xop(PCMPGT[8], d, d, t);
                as_.xop_m(PXOR, d, d, vconst_mem(~0ull, ~0ull));
            }
        } else if (in.sub == V_CMHS) {  // max(a,b) == a
            as_.xop(PMAXU[es], d, a, b);
            as_.xop(PCMPEQ[es], d, d, a);
        } else {  // a > b = ~(max(a,b) == b)
            as_.xop(PMAXU[es], d, a, b);
            as_.xop(PCMPEQ[es], d, d, b);
            as_.xop_m(PXOR, d, d, vconst_mem(~0ull, ~0ull));
        }
        finish(d);
        return;
    }
    case V_CMTST: {
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        Xmm z = alloc_x(); xpinned_ |= 1 << z;
        as_.xop(PAND, d, a, b);
        as_.xop(PXOR, z, z, z);
        as_.xop(PCMPEQ[es], d, d, z);
        as_.xop_m(PXOR, d, d, vconst_mem(~0ull, ~0ull));
        finish(d);
        return;
    }
    // ---------------- shifts by immediate
    case V_SHL_I: case V_USHR_I: case V_SSHR_I: {
        int sh = (int)in.imm;
        Xmm a = A();
        if (es == 1) {
            if (in.sub == V_SSHR_I) return helper();
            Xmm d = new_x(v);
            if (sh >= 8) { as_.xop(PXOR, d, d, d); finish(d); return; }
            if (in.sub == V_SHL_I) {
                as_.xshift_imm(0x71, 6, d, a, (u8)sh);
                as_.xop_m(PAND, d, d, vconst_mem(rep((0xff << sh) & 0xff, 1), rep((0xff << sh) & 0xff, 1)));
            } else {
                as_.xshift_imm(0x71, 2, d, a, (u8)sh);
                as_.xop_m(PAND, d, d, vconst_mem(rep(0xff >> sh, 1), rep(0xff >> sh, 1)));
            }
            finish(d);
            return;
        }
        if (es == 8 && in.sub == V_SSHR_I) return helper();
        Xmm d = new_x(v);
        u8 opc = es == 2 ? 0x71 : es == 4 ? 0x72 : 0x73;
        int ext = in.sub == V_SHL_I ? 6 : in.sub == V_USHR_I ? 2 : 4;
        as_.xshift_imm(opc, ext, d, a, (u8)(sh > 255 ? 255 : sh));
        finish(d);
        return;
    }
    case V_USRA: case V_SSRA: {
        int sh = (int)in.imm;
        if (es == 1 || (es == 8 && in.sub == V_SSRA)) return helper();
        Xmm a = A(), c = C();
        Xmm d = new_x(v);
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        u8 opc = es == 2 ? 0x71 : es == 4 ? 0x72 : 0x73;
        as_.xshift_imm(opc, in.sub == V_USRA ? 2 : 4, t, a, (u8)sh);
        as_.xop(PADD[es], d, c, t);
        finish(d);
        return;
    }
    // ---------------- widening / narrowing
    case V_UXTL: case V_SXTL: {
        if (es == 8) return helper();
        Xmm a = A();
        Xmm d = new_x(v);
        as_.xop1(in.sub == V_UXTL ? PMOVZX[es] : PMOVSX[es], d, a);
        return;
    }
    case V_XTN: {
        Xmm a = A();
        Xmm d = new_x(v);
        if (es == 4) { as_.xop1(PSHUFD, d, a, 0x08); zero_upper(d, 8); return; }
        u64 lo = es == 1 ? 0x0e0c0a0806040200ull : 0x0d0c090805040100ull;
        as_.xop_m(PSHUFB, d, a, vconst_mem(lo, 0x8080808080808080ull));
        if (scalar) zero_upper(d, es);
        return;
    }
    case V_SHRN: {
        int sh = (int)in.imm;
        Xmm a = A();
        Xmm d = new_x(v);
        u8 opc = es == 1 ? 0x71 : es == 2 ? 0x72 : 0x73;   // shift the wide source elements
        as_.xshift_imm(opc, 2, d, a, (u8)sh);
        if (es == 4) { as_.xop1(PSHUFD, d, d, 0x08); zero_upper(d, 8); return; }
        u64 lo = es == 1 ? 0x0e0c0a0806040200ull : 0x0d0c090805040100ull;
        as_.xop_m(PSHUFB, d, d, vconst_mem(lo, 0x8080808080808080ull));
        return;
    }
    case V_UMULL: case V_SMULL: case V_UMLAL: case V_SMLAL: case V_UMLSL: case V_SMLSL: {
        bool sg = in.sub == V_SMULL || in.sub == V_SMLAL || in.sub == V_SMLSL;
        bool acc = in.sub != V_UMULL && in.sub != V_SMULL;
        bool sub = in.sub == V_UMLSL || in.sub == V_SMLSL;
        Xmm a = A(), b = B();
        Xmm c = acc ? C() : a;
        Xmm d = new_x(v);
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        if (es == 1) {
            as_.xop1(sg ? PMOVSX[1] : PMOVZX[1], d, a);
            as_.xop1(sg ? PMOVSX[1] : PMOVZX[1], t, b);
            as_.xop(PMULLW, d, d, t);
        } else if (es == 2) {
            as_.xop(PMULLW, d, a, b);
            as_.xop(sg ? PMULHW : PMULHUW, t, a, b);
            as_.xop(PUNPCKL[2], d, d, t);
        } else if (es == 4) {
            Xmm u = alloc_x(); xpinned_ |= 1 << u;
            as_.xop1(PSHUFD, t, a, 0x50);
            as_.xop1(PSHUFD, u, b, 0x50);
            if (sg) as_.xop(PMULDQ, d, t, u); else as_.xop(PMULUDQ, d, t, u);
        } else return helper();
        if (acc) {
            int ws = es * 2;
            if (sub) { as_.xop(PSUB[ws], t, c, d); as_.movaps(d, t); }
            else as_.xop(PADD[ws], d, d, c);
        }
        return;
    }
    case V_UADDL: case V_SADDL: case V_USUBL: case V_SSUBL: case V_UADDW: case V_SADDW: case V_USUBW: case V_SSUBW: {
        if (es == 8) return helper();
        bool sg = in.sub == V_SADDL || in.sub == V_SSUBL || in.sub == V_SADDW || in.sub == V_SSUBW;
        bool wide = in.sub == V_UADDW || in.sub == V_SADDW || in.sub == V_USUBW || in.sub == V_SSUBW;
        bool sub = in.sub == V_USUBL || in.sub == V_SSUBL || in.sub == V_USUBW || in.sub == V_SSUBW;
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        if (wide) as_.movaps(d, a);
        else as_.xop1(sg ? PMOVSX[es] : PMOVZX[es], d, a);
        as_.xop1(sg ? PMOVSX[es] : PMOVZX[es], t, b);
        as_.xop(sub ? PSUB[es * 2] : PADD[es * 2], d, d, t);
        return;
    }
    // ---------------- permutes
    case V_ZIP1: case V_ZIP2: {
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        if (!half) as_.xop(in.sub == V_ZIP1 ? PUNPCKL[es] : PUNPCKH[es], d, a, b);
        else {
            as_.xop(PUNPCKL[es], d, a, b);
            if (in.sub == V_ZIP2) as_.xshift_imm(0x73, 3, d, d, 8);   // psrldq 8
        }
        finish(d);
        return;
    }
    case V_UZP1: case V_UZP2: {
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        bool second = in.sub == V_UZP2;
        if (half) {
            if (es == 4) {
                as_.xop(PUNPCKL[8], d, a, b);
                as_.xop1(PSHUFD, d, d, second ? 0x0D : 0x08);
            } else {
                u64 lo = es == 1 ? (second ? 0x0f0d0b0907050301ull : 0x0e0c0a0806040200ull)
                                 : (second ? 0x0f0e0b0a07060302ull : 0x0d0c090805040100ull);
                as_.xop(PUNPCKL[8], d, a, b);
                as_.xop_m(PSHUFB, d, d, vconst_mem(lo, 0x8080808080808080ull));
            }
            finish(d);
            return;
        }
        if (es == 8) { as_.xop(second ? PUNPCKH[8] : PUNPCKL[8], d, a, b); return; }
        if (es == 4) { as_.xop(SHUFPS, d, a, b, second ? 0xDD : 0x88); return; }
        u64 lo = es == 1 ? (second ? 0x0f0d0b0907050301ull : 0x0e0c0a0806040200ull)
                         : (second ? 0x0f0e0b0a07060302ull : 0x0d0c090805040100ull);
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        Mem m = vconst_mem(lo, 0x8080808080808080ull);
        as_.xop_m(PSHUFB, d, a, m);
        as_.xop_m(PSHUFB, t, b, m);
        as_.xop(PUNPCKL[8], d, d, t);
        return;
    }
    case V_TRN1: case V_TRN2: {
        if (es == 1) return helper();
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        bool second = in.sub == V_TRN2;
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        switch (es) {
        case 8: as_.xop(second ? PUNPCKH[8] : PUNPCKL[8], d, a, b); break;
        case 4:
            as_.xop(SHUFPS, d, a, b, second ? 0xDD : 0x88);
            as_.xop1(PSHUFD, d, d, 0xD8);
            break;
        case 2:
            if (!second) { as_.xshift_imm(0x73, 7, t, b, 2); as_.xop(PBLENDW, d, a, t, 0xAA); }
            else { as_.xshift_imm(0x73, 3, t, a, 2); as_.xop(PBLENDW, d, t, b, 0xAA); }
            break;
        default: fatal("trn bytes");
        }
        finish(d);
        return;
    }
    case V_EXT: {
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        if (!half) as_.xop(PALIGNR, d, b, a, (int)in.imm);
        else {
            as_.xop(PUNPCKL[8], d, a, b);
            as_.xshift_imm(0x73, 3, d, d, (u8)in.imm);
            zero_upper(d, 8);
        }
        return;
    }
    case V_TBX: {
        Xmm tab = A(), idx = B();
        const Inst& ci = I(resolve(in.c));
        bool zero_old = ci.op == Op::VConst && ci.imm == 0 && ci.imm2 == 0;
        Xmm d = new_x(v);
        if (zero_old && in.imm == 0) {
            // TBL single register: indices >= 16 must give 0 -> saturating add sets bit 7
            as_.xop_m(PADDUSB, d, idx, vconst_mem(0x7070707070707070ull, 0x7070707070707070ull));
            as_.xop(PSHUFB, d, tab, d);
            return;
        }
        Xmm old = C();
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        Xmm m = alloc_x(); xpinned_ |= 1 << m;
        u64 off = rep(in.imm & 0xff, 1);
        if (in.imm) as_.xop_m(PSUB[1], t, idx, vconst_mem(off, off));
        else as_.movaps(t, idx);
        // in-range mask: min(t, 15) == t
        as_.xop_m(PMINU[1], m, t, vconst_mem(0x0f0f0f0f0f0f0f0full, 0x0f0f0f0f0f0f0f0full));
        as_.xop(PCMPEQ[1], m, m, t);
        as_.xop(PSHUFB, d, tab, t);
        // d = (d & m) | (old & ~m)
        as_.xop(PAND, d, d, m);
        as_.xop(PANDN, m, m, old);
        as_.xop(POR, d, d, m);
        return;
    }
    case V_DUPELEM: {
        int idx = (int)in.imm;
        Xmm a = A();
        Xmm d = new_x(v);
        if (scalar) {
            if (es == 8) { if (idx) as_.xshift_imm(0x73, 3, d, a, 8); else as_.xop1(MOVQ_XX, d, a); return; }
            if (es == 4) { as_.xop(INSERTPS, d, a, a, (idx << 6) | 0x0E); return; }
            u64 lo = 0x8080808080808080ull;
            if (es == 2) lo = (lo & ~0xffffull) | (u64)(idx * 2) | ((u64)(idx * 2 + 1) << 8);
            else lo = (lo & ~0xffull) | (u64)idx;
            as_.xop_m(PSHUFB, d, a, vconst_mem(lo, 0x8080808080808080ull));
            return;
        }
        switch (es) {
        case 8: as_.xop1(PSHUFD, d, a, idx ? 0xEE : 0x44); break;
        case 4: as_.xop1(PSHUFD, d, a, idx * 0x55); break;
        case 2: { u64 w = (u64)(idx * 2) | ((u64)(idx * 2 + 1) << 8); w = rep(w, 2); as_.xop_m(PSHUFB, d, a, vconst_mem(w, w)); break; }
        default: { u64 w = rep((u64)idx, 1); as_.xop_m(PSHUFB, d, a, vconst_mem(w, w)); break; }
        }
        finish(d);
        return;
    }
    case V_INSELEM: {
        int di = (int)(in.imm & 0xff), si = (int)(in.imm >> 8);
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        if (es == 4) { as_.xop(INSERTPS, d, a, b, (si << 6) | (di << 4)); return; }
        if (es == 8) {
            Xmm t = b;
            if (si != di) { t = alloc_x(); xpinned_ |= 1 << t; as_.xop1(PSHUFD, t, b, si ? 0xEE : 0x44); }
            as_.xop(PBLENDW, d, a, t, di ? 0xF0 : 0x0F);
            return;
        }
        Reg g = alloc_temp(); pinned_ |= 1 << g;
        as_.xop_gx(es == 1 ? PEXTRB : PEXTRW, b, g, si);
        if (d != a) as_.movaps(d, a);
        as_.xop_gx(es == 1 ? PINSRB : PINSRW, d, g, di, d);
        return;
    }
    case V_ZEXT: {
        Xmm a = A();
        Xmm d = new_x(v);
        if (es == 8) as_.xop1(MOVQ_XX, d, a);
        else { as_.movaps(d, a); zero_upper(d, es); }
        return;
    }
    case V_REV16: case V_REV32: case V_REV64: {
        Xmm a = A();
        Xmm d = new_x(v);
        int cont = in.sub == V_REV16 ? 2 : in.sub == V_REV32 ? 4 : 8;
        if (cont == 8 && es == 4) { as_.xop1(PSHUFD, d, a, 0xB1); finish(d); return; }
        u8 mbytes[16];
        for (int i = 0; i < 16; i++) {
            int e = i / es, off = i % es;
            int per = cont / es, base = (e / per) * per;
            int se = base + per - 1 - (e - base);
            mbytes[i] = (u8)(se * es + off);
        }
        u64 lo, hi;
        memcpy(&lo, mbytes, 8);
        memcpy(&hi, mbytes + 8, 8);
        as_.xop_m(PSHUFB, d, a, vconst_mem(lo, hi));
        finish(d);
        return;
    }
    case V_CNT: {
        Xmm a = A();
        Xmm d = new_x(v);
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        Xmm u = alloc_x(); xpinned_ |= 1 << u;
        Mem nib = vconst_mem(0x0f0f0f0f0f0f0f0full, 0x0f0f0f0f0f0f0f0full);
        Mem lut = vconst_mem(0x0302020102010100ull, 0x0403030203020201ull);
        as_.xop_m(PAND, t, a, nib);
        as_.xshift_imm(0x71, 2, u, a, 4);
        as_.xop_m(PAND, u, u, nib);
        as_.xop1_m({0, 1, 0x28, 0}, d, lut);
        as_.xop(PSHUFB, d, d, t);
        as_.xop1_m({0, 1, 0x28, 0}, t, lut);
        as_.xop(PSHUFB, t, t, u);
        as_.xop(PADD[1], d, d, t);
        finish(d);
        return;
    }
    // ---------------- reductions
    case V_ADDV: case V_UADDLV: {
        Xmm a = A();
        Xmm d = new_x(v);
        if (es == 1) {
            Xmm z = alloc_x(); xpinned_ |= 1 << z;
            as_.xop(PXOR, z, z, z);
            if (half) { as_.xop1(MOVQ_XX, d, a); as_.xop(PSADBW, d, d, z); }
            else {
                as_.xop(PSADBW, d, a, z);
                as_.xop1(PSHUFD, z, d, 0xEE);
                as_.xop(PADD[8], d, d, z);
            }
            zero_upper(d, in.sub == V_ADDV ? 1 : 2);
            return;
        }
        if (es == 2 && in.sub == V_ADDV) {
            as_.xop(PHADDW, d, a, a);
            as_.xop(PHADDW, d, d, d);
            if (!half) as_.xop(PHADDW, d, d, d);
            zero_upper(d, 2);
            return;
        }
        if (es == 4 && in.sub == V_ADDV && !half) {
            as_.xop(PHADDD, d, a, a);
            as_.xop(PHADDD, d, d, d);
            zero_upper(d, 4);
            return;
        }
        xowner_[d] = 0; vi_[v].k = L_NONE;
        return helper();
    }
    case V_UMAXV: case V_UMINV: case V_SMAXV: case V_SMINV: {
        if (es == 8) return helper();
        Xmm a = A();
        Xmm d = new_x(v);
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        SseOp o = in.sub == V_UMAXV ? PMAXU[es] : in.sub == V_UMINV ? PMINU[es]
                : in.sub == V_SMAXV ? PMAXS[es] : PMINS[es];
        as_.movaps(d, a);
        int lanes = (half ? 8 : 16) / es;
        // halving tree with byte shifts (psrldq)
        int width = lanes * es;
        while (width > es) {
            width /= 2;
            as_.xshift_imm(0x73, 3, t, d, (u8)width);
            as_.xop(o, d, d, t);
        }
        zero_upper(d, es);
        return;
    }
    // ---------------- floating point
    case V_FADD: case V_FSUB: case V_FMUL: case V_FDIV: {
        u8 opc = in.sub == V_FADD ? 0x58 : in.sub == V_FSUB ? 0x5C : in.sub == V_FMUL ? 0x59 : 0x5E;
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        as_.xop(scalar ? FPS(opc, es) : FPV(opc, es), d, a, b);
        finish(d);
        return;
    }
    case V_FSQRT: {
        Xmm a = A();
        Xmm d = new_x(v);
        if (scalar) as_.xop(FPS(0x51, es), d, a, a);
        else as_.xop1(FPV(0x51, es), d, a);
        finish(d);
        return;
    }
    case V_FABS: case V_FNEG: {
        Xmm a = A();
        u64 m = es == 8 ? 0x8000000000000000ull : 0x8000000080000000ull;
        Xmm d = new_x(v);
        if (in.sub == V_FABS) as_.xop_m(PAND, d, a, vconst_mem(~m, ~m));
        else as_.xop_m(PXOR, d, a, vconst_mem(m, m));
        finish(d);
        return;
    }
    case V_FNMUL: {
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        u64 m = es == 8 ? 0x8000000000000000ull : 0x8000000080000000ull;
        as_.xop(scalar ? FPS(0x59, es) : FPV(0x59, es), d, a, b);
        as_.xop_m(PXOR, d, d, vconst_mem(m, m));
        finish(d);
        return;
    }
    case V_FMLA: case V_FMLS: case V_FMADD: case V_FMSUB: case V_FNMADD: case V_FNMSUB: {
        if (!g_host.fma || !as_.avx) return helper();
        // ARM negates operands before the fused op (FPNeg flips NaN signs too), so negate
        // explicitly and always use vfmadd231: d = a*b + d.
        bool neg_a = in.sub == V_FMLS || in.sub == V_FMSUB || in.sub == V_FNMADD;
        bool neg_c = in.sub == V_FNMADD || in.sub == V_FNMSUB;
        Xmm a = A(), b = B(), c = C();
        Xmm d = new_x(v);
        u64 m = es == 8 ? 0x8000000000000000ull : 0x8000000080000000ull;
        if (neg_c) as_.xop_m(PXOR, d, c, vconst_mem(m, m));
        else as_.movaps(d, c);
        Xmm x = a;
        if (neg_a) { x = alloc_x(); xpinned_ |= 1 << x; as_.xop_m(PXOR, x, a, vconst_mem(m, m)); }
        as_.xop(scalar ? FMA231S(0xB8, es) : FMA231V(0xB8, es), d, x, b);
        finish(d);
        return;
    }
    case V_FMAX: case V_FMIN: case V_FMAXNM: case V_FMINNM: {
        bool isMax = in.sub == V_FMAX || in.sub == V_FMAXNM;
        bool nm = in.sub == V_FMAXNM || in.sub == V_FMINNM;
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        Xmm u = alloc_x(); xpinned_ |= 1 << u;
        u8 opc = isMax ? 0x5F : 0x5D;
        SseOp op = scalar ? FPS(opc, es) : FPV(opc, es);
        as_.xop(op, d, a, b);
        as_.xop(op, t, b, a);
        // equal values / signed zeros: max -> AND (+0 wins), min -> OR (-0 wins)
        as_.xop(isMax ? PAND : POR, d, d, t);
        SseOp cmp = scalar ? FPS(0xC2, es) : FPV(0xC2, es);
        if (!nm) {
            // NaN in either: result = a + b (propagates the NaN)
            as_.xop(cmp, u, a, b, 3);                                     // unordered mask
            as_.xop(scalar ? FPS(0x58, es) : FPV(0x58, es), t, a, b);
            as_.xop(PAND, t, t, u);
            as_.xop(PANDN, u, u, d);
            as_.xop(POR, d, t, u);
        } else {
            // a NaN -> b ; b NaN -> a (quiet NaN semantics)
            as_.xop(cmp, u, a, a, 3);
            as_.xop(PAND, t, b, u);
            as_.xop(PANDN, u, u, d);
            as_.xop(POR, d, t, u);
            as_.xop(cmp, u, b, b, 3);
            as_.xop(PAND, t, a, u);
            as_.xop(PANDN, u, u, d);
            as_.xop(POR, d, t, u);
        }
        finish(d);
        return;
    }
    case V_FCMEQ: case V_FCMGE: case V_FCMGT: case V_FACGE: case V_FACGT: {
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        SseOp cmp = scalar ? FPS(0xC2, es) : FPV(0xC2, es);
        Xmm x = a, y = b;
        if (in.sub == V_FACGE || in.sub == V_FACGT) {
            u64 m = es == 8 ? 0x7fffffffffffffffull : 0x7fffffff7fffffffull;
            x = alloc_x(); xpinned_ |= 1 << x;
            y = alloc_x(); xpinned_ |= 1 << y;
            as_.xop_m(PAND, x, a, vconst_mem(m, m));
            as_.xop_m(PAND, y, b, vconst_mem(m, m));
        }
        switch (in.sub) {
        case V_FCMEQ: as_.xop(cmp, d, x, y, 0); break;
        case V_FCMGE: case V_FACGE: as_.xop(cmp, d, y, x, 2); break;   // y <= x
        default: as_.xop(cmp, d, y, x, 1); break;                      // y < x
        }
        finish(d);
        return;
    }
    case V_FABD: {
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        u64 m = es == 8 ? 0x7fffffffffffffffull : 0x7fffffff7fffffffull;
        as_.xop(scalar ? FPS(0x5C, es) : FPV(0x5C, es), d, a, b);
        as_.xop_m(PAND, d, d, vconst_mem(m, m));
        finish(d);
        return;
    }
    case V_FADDP: {
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        SseOp hadd = {(u8)(es == 8 ? 0x66 : 0xF2), 1, 0x7C, 0};
        if (scalar) { as_.xop(hadd, d, a, a); finish(d); return; }
        if (half) { as_.xop(PUNPCKL[8], d, a, b); as_.xop(hadd, d, d, d); finish(d); return; }
        as_.xop(hadd, d, a, b);
        return;
    }
    case V_FRINT: {
        int rnd = (int)in.imm;
        if (rnd == FR_TIEAWAY) return helper();
        int mode = rnd == FR_TIEEVEN ? 0 : rnd == FR_NEGINF ? 1 : rnd == FR_POSINF ? 2 : rnd == FR_ZERO ? 3 : 4;
        Xmm a = A();
        Xmm d = new_x(v);
        if (scalar) as_.xop(ROUNDS(es), d, a, a, mode | 8);
        else as_.xop1(ROUNDV(es), d, a, mode | 8);
        finish(d);
        return;
    }
    case V_FCVTS2D: case V_FCVTD2S: {
        Xmm a = A();
        Xmm d = new_x(v);
        as_.xop(PXOR, d, d, d);
        SseOp cvt = {(u8)(in.sub == V_FCVTS2D ? 0xF3 : 0xF2), 1, 0x5A, 0};
        as_.xop(cvt, d, d, a);
        return;
    }
    case V_FCVTL: {
        if (es != 8) return helper();
        Xmm a = A();
        Xmm d = new_x(v);
        as_.xop1({0, 1, 0x5A, 0}, d, a);   // cvtps2pd
        return;
    }
    case V_FCVTN: {
        if (es != 8) return helper();
        Xmm a = A();
        Xmm d = new_x(v);
        as_.xop1({0x66, 1, 0x5A, 0}, d, a);   // cvtpd2ps (zeroes upper 64)
        return;
    }
    case V_SCVTF: {
        if (es != 4) return helper();
        Xmm a = A();
        Xmm d = new_x(v);
        if (scalar) { as_.xop(PXOR, d, d, d); as_.xop(INSERTPS, d, d, a, 0x0E); as_.xop1({0, 1, 0x5B, 0}, d, d); }
        else as_.xop1({0, 1, 0x5B, 0}, d, a);
        finish(d);
        return;
    }
    case V_FCVTZS: {
        int rnd = (int)in.imm;
        if (es != 4 || rnd == FR_TIEAWAY) return helper();
        Xmm a = A();
        Xmm d = new_x(v);
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        Xmm src = a;
        if (rnd != FR_ZERO) {
            int mode = rnd == FR_TIEEVEN ? 0 : rnd == FR_NEGINF ? 1 : 2;
            Xmm r = alloc_x(); xpinned_ |= 1 << r;
            as_.xop1(ROUNDV(4), r, a, mode | 8);
            src = r;
        }
        // t = (src >= 2^31) | NaN ; d = cvtt(src) ^ t ; d &= ordered(src)
        as_.xop_m(FPV(0xC2, 4), t, src, vconst_mem(0x4f0000004f000000ull, 0x4f0000004f000000ull), 5);  // NLT
        as_.xop1({0xF3, 1, 0x5B, 0}, d, src);   // cvttps2dq
        as_.xop(PXOR, d, d, t);
        as_.xop(FPV(0xC2, 4), t, src, src, 7);  // ordered
        as_.xop(PAND, d, d, t);
        finish(d);
        return;
    }
    case V_FRINTX: {   // round using the current mode (MXCSR = FPCR rounding, RNE by default)
        Xmm a = A();
        Xmm d = new_x(v);
        if (scalar) as_.xop(ROUNDS(es), d, a, a, 4);
        else as_.xop1(ROUNDV(es), d, a, 4);
        finish(d);
        return;
    }
    case V_UCVTF: {
        if (es != 4) return helper();
        // exact halves: f(hi16) * 65536 + f(lo16), one rounding in the final add
        Xmm a = A();
        Xmm d = new_x(v);
        Xmm t = alloc_x(); xpinned_ |= 1 << t;
        as_.xshift_imm(0x72, 2, t, a, 16);                                  // psrld t, a, 16
        as_.xop1({0, 1, 0x5B, 0}, t, t);                                    // cvtdq2ps
        as_.xop_m(FPV(0x59, 4), t, t, vconst_mem(0x4780000047800000ull, 0x4780000047800000ull));
        as_.xop_m(PAND, d, a, vconst_mem(0x0000ffff0000ffffull, 0x0000ffff0000ffffull));
        as_.xop1({0, 1, 0x5B, 0}, d, d);
        as_.xop(FPV(0x58, 4), d, d, t);                                     // addps
        finish(d);
        return;
    }
    case V_FCVTZU_FIX: case V_FCVTZU: {
        int fb = in.sub == V_FCVTZU_FIX ? (int)in.imm : 0;
        if (es != 4 || fb > 32 || (in.sub == V_FCVTZU && in.imm != FR_ZERO)) return helper();
        Xmm a = A();
        Xmm d = new_x(v);
        Xmm sv = alloc_x(); xpinned_ |= 1 << sv;
        Xmm m = alloc_x(); xpinned_ |= 1 << m;
        u64 scale = (u64)(127 + fb) << 23;
        as_.xop_m(FPV(0x59, 4), sv, a, vconst_mem(scale | scale << 32, scale | scale << 32));   // * 2^fbits
        as_.xop(PXOR, m, m, m);
        as_.xop(FPV(0x5F, 4), sv, sv, m);              // max(x, 0): NaN and negatives -> 0
        const u64 two31 = 0x4f0000004f000000ull, two32 = 0x4f8000004f800000ull;
        as_.xop_m(FPV(0xC2, 4), m, sv, vconst_mem(two31, two31), 5);       // x >= 2^31
        as_.xop_m(PAND, d, m, vconst_mem(two31, two31));
        as_.xop(FPV(0x5C, 4), d, sv, d);                                    // x - (2^31 if big)
        as_.xop1({0xF3, 1, 0x5B, 0}, d, d);                                 // cvttps2dq
        as_.xshift_imm(0x72, 6, m, m, 31);                                  // pslld m, 31
        as_.xop(PXOR, d, d, m);
        as_.xop_m(FPV(0xC2, 4), m, sv, vconst_mem(two32, two32), 5);       // x >= 2^32: saturate
        as_.xop(POR, d, d, m);
        finish(d);
        return;
    }
    case V_USHL: {
        if (es != 4 || scalar || !g_host.avx2 || !as_.avx) return helper();
        // shift count = signed low byte of each lane; out-of-range counts give 0 (as on AArch64)
        Xmm a = A(), b = B();
        Xmm d = new_x(v);
        Xmm c = alloc_x(); xpinned_ |= 1 << c;
        Xmm n = alloc_x(); xpinned_ |= 1 << n;
        as_.xshift_imm(0x72, 6, c, b, 24);
        as_.xshift_imm(0x72, 4, c, c, 24);                                  // c = sext8(b)
        as_.xop(PXOR, n, n, n);
        as_.xop(PSUB[4], n, n, c);                                          // n = -c
        as_.xop({0x66, 2, 0x47, 0}, d, a, c);                               // vpsllvd
        as_.xop({0x66, 2, 0x45, 0}, n, a, n);                               // vpsrlvd
        as_.xop(POR, d, d, n);
        finish(d);
        return;
    }
    default:
        return helper();
    }
}

void T1::emit_const_pool() {}

}  // namespace t1
}  // namespace xef::backend
