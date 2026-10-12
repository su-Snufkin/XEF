// XEF — tier-1 code generator.
//
// Register model (see runtime/cpu_state.h):
//   - mapped guest registers live permanently in their host registers,
//   - unmapped guest registers live in CpuState (R15-relative),
//   - RAX, RCX, R11 are block-local temporaries,
//   - guest NZCV lives in host EFLAGS in canonical form (CF = !C) at every
//     block boundary; inside a block EFLAGS hold the most recent flags value
//     and are spilled only if an instruction must clobber them while live.
#include "backend/x64/t1_internal.h"

namespace xef::backend {


extern "C" u64 xef_helper_sysreg(u64, u64, u64 id);
extern "C" u64 xef_helper_crc32(u64 crc, u64 data, u64 size_and_c);

int count_exits(const Block& b) {
    int n = 0;
    for (int v = 1; v < b.n; v++) {
        switch (b.insts[v].op) {
        case Op::ExitJump: n += 1; break;
        case Op::ExitCond: case Op::ExitCbz: case Op::ExitTbz: n += 2; break;
        case Op::ExitCall: n += 2; break;
        case Op::ExitCallIndirect: n += 1; break;
        default: break;
        }
    }
    return n;
}

Cond x86_cond(ir::Cond c) {
    // Canonical EFLAGS: SF=N ZF=Z CF=!C OF=V
    switch (c) {
    case ir::EQ: return CE;
    case ir::NE: return CNE;
    case ir::HS: return CAE;
    case ir::LO: return CB;
    case ir::MI: return CS;
    case ir::PL: return CNS;
    case ir::VS: return CO;
    case ir::VC: return CNO;
    case ir::HI: return CA;
    case ir::LS: return CBE;
    case ir::GE: return CGE;
    case ir::LT: return CL;
    case ir::GT: return CG;
    case ir::LE: return CLE;
    default: return CE;
    }
}

// Host EFLAGS value (low byte for SAHF + OF) for an ARM NZCV nibble.
static u8 sahf_byte(u32 nzcv) {
    bool n = nzcv & 8, z = nzcv & 4, c = nzcv & 2;
    return (u8)((n << 7) | (z << 6) | ((!c) << 0) | 2);
}

namespace t1 {


// ------------------------------------------------------------------ analysis

void T1::analyze() {
    int n = b_.n;
    // forward: clean32 (needed by is_alias_op) and use counts
    for (int v = 1; v < n; v++) {
        const Inst& in = I(v);
        VI& x = vi_[v];
        x.uses = 0;
        x.last = 0;
        x.clean32 = in.ty == Type::I32 && !(in.op == Op::Zext && in.size == 32) && in.op != Op::GetReg;
        if (in.op == Op::Zext && in.size == 32 && in.ty == Type::I32) x.clean32 = vi_[in.a].clean32;
    }
    // final guest flags value
    live_out_ = b_.flags_live_out;
    final_flags_ = kEntryFlags;
    for (int v = 1; v < n; v++)
        if (I(v).op == Op::SetFlags) final_flags_ = fid(I(v).a);
    // backward: liveness, DCE, alias last-use propagation
    for (int v = n - 1; v >= 1; v--) {
        const Inst& in = I(v);
        VI& x = vi_[v];
        if (!has_side_effects(in) && x.uses == 0 && in.op != Op::SetFlags) {
            // a flags value that is the final guest flags is live at exit
            if (!(live_out_ && in.ty == Type::Flags && fid(v) == final_flags_)) { x.dead = true; continue; }
        }
        if (in.op == Op::SetFlags) continue;  // bookkeeping, not a use
        i32 mylast = x.last ? x.last : v;
        bool alias = is_alias_op(in);
        for_operands(in, [&](Val o) {
            VI& y = vi_[o];
            y.uses++;
            i32 l = alias ? mylast : v;
            if (l > y.last) y.last = l;
        });
    }
    // terminator keeps final flags alive
    int term = n - 1;
    entry_flags_last_ = 0;
    if (live_out_) {
        if (final_flags_ == kEntryFlags) entry_flags_last_ = term;
        else if (vi_[final_flags_].last < term) vi_[final_flags_].last = term;
    }
    for (int v = 1; v < n; v++)
        if (I(v).op == Op::GetFlags && vi_[v].last > entry_flags_last_) entry_flags_last_ = vi_[v].last;

    // flag rematerialization: keep the operands of cheap flag producers alive until the last
    // consumer so clobbered EFLAGS can be recomputed (cmp/test) instead of pushf/popf.
    for (int v = 1; v < n; v++) {
        const Inst& in = I(v);
        VI& x = vi_[v];
        x.rres = 0;
        if (x.dead || !(in.op == Op::FlagsSub || in.op == Op::FlagsAdd || in.op == Op::FlagsLogic)) continue;
        if (in.op == Op::FlagsLogic) x.rres = in.a;
        else if (v > 1 && I(v - 1).op == (in.op == Op::FlagsSub ? Op::Sub : Op::Add) && I(v - 1).a == in.a &&
                 I(v - 1).b == in.b && !vi_[v - 1].dead)
            x.rres = (Val)(v - 1);
        i32 L = x.last;
        // do all consumers only need N/Z? then the result value alone suffices
        bool full = in.op != Op::FlagsLogic && !x.rres;
        if (!full && in.op != Op::FlagsLogic) {
            if (live_out_ && fid(v) == final_flags_) full = true;
            for (int u = v + 1; u < n && !full; u++) {
                const Inst& c = I(u);
                if (vi_[u].dead || c.op == Op::SetFlags) continue;
                bool uses_f = false;
                for_operands(c, [&](Val o) { if (o == v) uses_f = true; });
                if (!uses_f) continue;
                bool cond_ok = (c.op == Op::ExitCond || c.op == Op::Select || c.op == Op::VSelect) &&
                               (c.aux == ir::EQ || c.aux == ir::NE || c.aux == ir::MI || c.aux == ir::PL);
                if (!cond_ok) full = true;
            }
        }
        auto extend = [&](Val o) {
            while (o) {
                if (vi_[o].last < L) vi_[o].last = L;
                if (!is_alias_op(I(o))) break;
                o = I(o).a;
            }
        };
        if (full || in.op == Op::FlagsLogic) {
            if (in.a) extend(in.a);
            if (in.b) extend(in.b);
        }
        if (x.rres) extend(x.rres);
    }

    // address folding: Load/Store(addr = Add(base, const|reg|Shl(reg,k))) with single use
    for (int v = 1; v < n; v++) {
        const Inst& in = I(v);
        if (vi_[v].dead) continue;
        Val a = 0;
        if (in.op == Op::Load || in.op == Op::Store || in.op == Op::VLoad || in.op == Op::VStore) a = in.a;
        if (!a) continue;
        const Inst& ad = I(a);
        if (ad.op != Op::Add || vi_[a].uses != 1 || ad.ty != Type::I64) continue;
        const Inst& rhs = I(ad.b);
        if (rhs.op == Op::Const) {
            if ((i64)rhs.imm == (i32)rhs.imm) vi_[a].folded = true;
        } else if (rhs.op == Op::Shl && I(rhs.b).op == Op::Const && I(rhs.b).imm <= 3 && vi_[ad.b].uses == 1 &&
                   rhs.ty == Type::I64) {
            vi_[a].folded = true;
            vi_[ad.b].folded = true;
        } else {
            vi_[a].folded = true;
        }
    }
}

// ------------------------------------------------------------------ registers

Reg T1::alloc_temp(Reg prefer) {
    if (prefer != NOREG && !owner_[prefer] && !(pinned_ & (1 << prefer))) return prefer;
    for (int ti_ = 0; ti_ < ntemps_; ti_++) if (Reg r = temps_[ti_]; true)
        if (!owner_[r] && !(pinned_ & (1 << r))) return r;
    // evict: prefer values with a valid home (free), else furthest last use
    Reg best = NOREG;
    int best_score = -1;
    for (int ti_ = 0; ti_ < ntemps_; ti_++) if (Reg r = temps_[ti_]; true) {
        if (pinned_ & (1 << r)) continue;
        Val o = owner_[r];
        int score = vi_[o].last + (vi_[o].home >= 0 ? 100000 : 0);
        if (score > best_score) { best_score = score; best = r; }
    }
    if (best == NOREG) {
        // All temporaries are pinned by this instruction: borrow a mapped guest register.
        // Its guest value is saved to CpuState and restored after the instruction.
        static const Reg cands[] = {RBP, RBX, R9, R8, R10, R12, R13, R14, RSI, RDI, RDX};
        for (Reg r : cands) {
            if (pinned_ & (1 << r)) continue;
            int g = -1;
            for (int k = 0; k < 32; k++) if (host(k) == r) g = k;
            if (g < 0) continue;
            as_.mov(8, gmem(g), r);
            borrowed_ |= 1 << r;
            pinned_ |= 1 << r;
            return r;
        }
        fatal("codegen: out of temporaries at ir %d", cur_);
    }
    evict(best);
    return best;
}

void T1::evict(Reg r) {
    Val o = owner_[r];
    if (!o) return;
    VI& x = vi_[o];
    if (x.home >= 0) {
        int g = x.home;
        if (mapped(g)) { x.k = L_GREG; x.reg = host(g); x.g = (u8)g; }
        else { x.k = L_GMEM; x.g = (u8)g; }
    } else {
        int s = -1;
        for (int i = 0; i < 15; i++) if (!(spill_used_ & (1u << i))) { s = i; break; }  // slot 15: flags restore
        if (s < 0) fatal("codegen: out of spill slots");
        spill_used_ |= 1u << s;
        as_.mov(8, mem(R15, XEF_ST(spill) + s * 8), r);
        x.k = L_SPILL;
        x.slot = (i8)s;
    }
    owner_[r] = 0;
}

Opnd T1::opnd(Val v, bool allow_mem, bool allow_imm, int size) {
    Val r = resolve(v);
    VI& x = vi_[r];
    const Inst& in = I(r);
    Opnd o{};
    if (in.op == Op::Const) {
        u64 imm = in.imm;
        if (size == 4) imm &= 0xffffffffull;
        if (allow_imm && (size == 4 || (i64)imm == (i32)imm)) { o.k = Opnd::I; o.imm = (i64)imm; return o; }
        Reg t = alloc_temp();
        as_.mov_imm(t, imm);
        // not cached: constants are cheap to rematerialize
        pinned_ |= 1 << t;
        o.k = Opnd::R; o.r = t;
        return o;
    }
    switch (x.k) {
    case L_REG: case L_GREG: o.k = Opnd::R; o.r = (Reg)x.reg; return o;
    case L_GMEM:
        if (allow_mem) { o.k = Opnd::M; o.m = gmem(x.g); return o; }
        break;
    case L_SPILL:
        if (allow_mem) { o.k = Opnd::M; o.m = mem(R15, XEF_ST(spill) + x.slot * 8); return o; }
        break;
    case L_NONE: {
        // first touch of a GetReg value
        if (in.op == Op::GetReg) {
            int g = in.aux;
            if (mapped(g)) { x.k = L_GREG; x.reg = host(g); x.g = (u8)g; o.k = Opnd::R; o.r = host(g); return o; }
            x.k = L_GMEM; x.g = (u8)g;
            if (allow_mem) { o.k = Opnd::M; o.m = gmem(g); return o; }
            break;
        }
        fatal("codegen: value %%%d (%s) has no location at ir %d", r, op_name(in.op), cur_);
    }
    default: break;
    }
    // materialize into a temp register
    Reg t = alloc_temp();
    if (x.k == L_GMEM) { as_.mov(8, t, gmem(x.g)); x.home = (i8)x.g; }
    else if (x.k == L_SPILL) { as_.mov(8, t, mem(R15, XEF_ST(spill) + x.slot * 8)); spill_used_ &= ~(1u << x.slot); }
    else fatal("codegen: bad loc");
    assign_reg(r, t);
    pinned_ |= 1 << t;
    o.k = Opnd::R; o.r = t;
    return o;
}

Reg T1::to_reg(Val v, int size) {
    Opnd o = opnd(v, false, false, size);
    return o.r;
}

void T1::load_into(Reg dst, Val v, int size) {
    Opnd o = opnd(v, true, true, size);
    emit_mov_opnd(size, dst, o);
}

void T1::release_operands(const Inst& in) {
    for_operands(in, [&](Val o) {
        Val r = resolve(o);
        VI& x = vi_[r];
        if (x.last <= cur_) {
            if (x.k == L_REG && owner_[x.reg] == r) owner_[x.reg] = 0;
            if (x.k == L_XMM && xowner_[x.reg] == r) xowner_[x.reg] = 0;
            if (x.k == L_SPILL) spill_used_ &= ~(1u << x.slot);
            if (x.k == L_VSPILL) vspill_used_ &= ~(1u << x.slot);
        }
    });
}

// Before guest register g is overwritten: move live values that alias it.
void T1::evacuate_guest(int g, int upto) {
    for (int v = 1; v < cur_; v++) {
        VI& x = vi_[v];
        if (x.dead || x.last <= upto) continue;
        if (x.home == g) x.home = -1;
        if ((x.k == L_GREG || x.k == L_GMEM) && x.g == g) {
            Reg t = alloc_temp();
            if (x.k == L_GREG) as_.mov(8, t, (Reg)x.reg);
            else as_.mov(8, t, gmem(g));
            assign_reg((Val)v, t);
        }
    }
    // values not yet touched (L_NONE GetReg of g): they read the *old* value, materialize now
    for (int v = 1; v < cur_; v++) {
        VI& x = vi_[v];
        if (x.dead || x.last <= upto || x.k != L_NONE) continue;
        const Inst& in = I(v);
        if (in.op == Op::GetReg && in.aux == g) {
            Reg t = alloc_temp();
            if (mapped(g)) as_.mov(8, t, host(g));
            else as_.mov(8, t, gmem(g));
            assign_reg((Val)v, t);
        }
    }
}

// Destination hint: if v's only use is the immediately following SetReg of a mapped guest
// register, compute v directly into that host register (after evacuating live aliases).
Reg T1::dest_hint(Val v) {
    int nx = v + 1;
    while (nx < b_.n && (vi_[nx].dead || vi_[nx].folded || I(nx).op == Op::Nop)) nx++;
    if (nx < b_.n) {
        const Inst& s = I(nx);
        if (s.op == Op::SetReg && mapped(s.aux) && s.a == v) {
            pinned_ |= 1 << host(s.aux);
            evacuate_guest(s.aux, cur_);
            return host(s.aux);
        }
    }
    return NOREG;
}

Reg T1::dest_for(Val v, int size) {
    (void)size;
    Reg h = dest_hint(v);
    Reg r = h != NOREG ? h : alloc_temp();
    pinned_ |= 1 << r;
    return r;
}

void T1::finish_def(Val v, Reg r) {
    // r is either a temp (owned) or a mapped guest host register (dest hint)
    bool is_temp = is_temp_reg(r) || (borrowed_ & (1 << r));
    if (is_temp) assign_reg(v, r);
    else {
        // value now lives in the guest register's host register; the following SetReg is a no-op
        vi_[v].k = L_GREG;
        vi_[v].reg = r;
        for (int g = 0; g < 32; g++) if (host(g) == r) { vi_[v].g = (u8)g; break; }
    }
}

Mem T1::addr_mem(Val a) {
    const Inst& ad = I(a);
    if (vi_[a].folded) {
        const Inst& rhs = I(ad.b);
        Reg base = to_reg(ad.a);
        pinned_ |= 1 << base;
        if (rhs.op == Op::Const) return mem(base, (i32)rhs.imm);
        if (rhs.op == Op::Shl && vi_[ad.b].folded) {
            Reg idx = to_reg(rhs.a);
            pinned_ |= 1 << idx;
            if (idx == RSP) fatal("codegen: rsp index");
            return mem(base, idx, (int)I(rhs.b).imm, 0);
        }
        Reg idx = to_reg(ad.b);
        pinned_ |= 1 << idx;
        return mem(base, idx, 0, 0);
    }
    if (is_c(a)) {
        u64 x = cv(a);
        if ((i64)x == (i32)x) { Mem m; m.disp = (i32)x; return m; }
    }
    Reg r = to_reg(a);
    pinned_ |= 1 << r;
    return mem(r, 0);
}

// ------------------------------------------------------------------ main loop

bool T1::run() {
    analyze();
    u8* start = as_.cur();
    (void)start;
    for (int v = 1; v < b_.n; v++) {
        cur_ = v;
        pinned_ = 0;
        xpinned_ = 0;
        if (vi_[v].dead || vi_[v].folded) continue;
        if (as_.overflow()) return false;
        emit_inst((Val)v);
        if (borrowed_) restore_borrowed();
        if (!is_terminator(I(v).op)) release_operands(I(v));
        // free dead results immediately (e.g. results whose only use was folded away)
        VI& x = vi_[v];
        if (x.k == L_REG && x.last <= v && owner_[x.reg] == v) owner_[x.reg] = 0;
        if (x.k == L_XMM && x.last <= v && xowner_[x.reg] == v) xowner_[x.reg] = 0;
    }
    // region exits: transfer back to the canonical mapping, then a normal patchable exit
    for (int i = 0; i < nrstubs_; i++) {
        as_.bind(rstubs_[i].l);
        if (ctx_->exit_counter) {  // flag-free increment (rax is free at block exits)
            as_.mov(8, RAX, rip(ctx_->exit_counter));
            as_.lea(8, RAX, mem(RAX, 1));
            as_.mov(8, rip(ctx_->exit_counter), RAX);
        }
        emit_region_xfer(as_, ctx_->xfer, ctx_->nxfer, false);
        raw_exit_jmp(rstubs_[i].target);
    }
    // link stubs (cold)
    for (int i = 0; i < nstubs_; i++) {
        ExitInfo* e = stubs_[i].e;
        e->stub = as_.cur();
        as_.mov_imm64_fixed(RAX, (u64)e);
        as_.jmp_rel32(g_cache.stubs.link_stub);
        Assembler::patch_rel32(e->site, e->stub);
    }
    emit_const_pool();
    out_.nexits = nexits_;
    out_.npcmap = npc_;
    out_.pcmap = pcmap_;
    return !as_.overflow();
}

// ------------------------------------------------------------------ instructions

void T1::emit_inst(Val v) {
    const Inst& in = I(v);
    switch (in.op) {
    case Op::Nop: case Op::Const: return;
    case Op::GetReg: {
        // location resolved lazily on first use (L_NONE -> L_GREG/L_GMEM)
        return;
    }
    case Op::GetFlags: vi_[v].k = L_ALIAS; return;
    case Op::SetFlags: return;  // bookkeeping only
    case Op::SetReg: {
        int g = in.aux;
        Val src = resolve(in.a);
        VI& x = vi_[src];
        if (mapped(g)) {
            Reg h = host(g);
            if ((x.k == L_GREG || x.k == L_REG) && x.reg == h) {
                // already there (dest hint)
                evacuate_guest(g, cur_);  // other aliases of the old value were moved at def time
                x.home = (i8)g;
                if (x.k == L_GREG) x.g = (u8)g;
                return;
            }
            pinned_ |= 1 << h;
            evacuate_guest(g, cur_);
            pin(src);
            Opnd o = opnd(src, true, true, 8);
            emit_mov_opnd(8, h, o);
            // the value now also lives in h; free its temp if it has further uses
            if (x.k == L_REG && owner_[x.reg] == src && !is_c(src)) owner_[x.reg] = 0;
            if (!is_c(src)) { x.k = L_GREG; x.reg = h; x.g = (u8)g; }
            x.home = (i8)g;
        } else {
            evacuate_guest(g, cur_);
            pin(src);
            Opnd o = opnd(src, false, true, 8);
            if (o.k == Opnd::I) as_.mov_imm(8, gmem(g), (i32)o.imm);
            else as_.mov(8, gmem(g), o.r);
            if (!is_c(src)) x.home = (i8)g;
        }
        return;
    }
    case Op::Add: case Op::Sub: case Op::And: case Op::Or: case Op::Xor:
    case Op::AndNot: case Op::OrNot: case Op::XorNot: case Op::Mul:
        emit_binop(v); return;
    case Op::Shl: case Op::Lshr: case Op::Ashr: case Op::Ror:
        emit_shift(v); return;
    case Op::Not: case Op::Neg: case Op::Clz: case Op::Cls: case Op::Rbit: case Op::Bswap:
    case Op::Rev16: case Op::Rev32InWords:
        emit_misc_unary(v); return;
    case Op::Sext: case Op::Zext:
        emit_ext(v); return;
    case Op::UMulH: case Op::SMulH: emit_mulh(v); return;
    case Op::UDiv: case Op::SDiv: emit_div(v); return;
    case Op::Select: emit_select(v); return;
    case Op::FlagsSub: case Op::FlagsAdd: case Op::FlagsLogic:
        emit_flags(v, false, NOREG); return;
    case Op::FlagsAdc: case Op::FlagsSbc:
        emit_adc_sbc(v, true, v); return;
    case Op::Adc: case Op::Sbc: emit_adc_sbc(v, false, 0); return;
    case Op::FlagsCCmp: emit_ccmp(v); return;
    case Op::FlagsFromNZCV: {
        // EFLAGS <- canonical(nzcv in bits 31:28):  SF=N ZF=Z CF=!C OF=V
        pin(in.a);
        take_reg(RAX);
        pinned_ |= 1 << RAX;
        Reg src = to_reg(in.a); pinned_ |= 1 << src;
        Reg t = alloc_temp(); pinned_ |= 1 << t;
        Reg u = alloc_temp(); pinned_ |= 1 << u;
        clobber_flags();
        as_.mov(4, t, src);
        as_.shift_imm(SHR, 4, t, 28);           // t = NZCV nibble
        as_.mov(4, RAX, t);
        as_.shift_imm(SHR, 4, RAX, 1);
        as_.alu_imm(AND, 4, RAX, 1);
        as_.alu_imm(XOR, 4, RAX, 3);            // (!C) | 2
        as_.mov(4, u, t);
        as_.alu_imm(AND, 4, u, 0xC);
        as_.shift_imm(SHL, 4, u, 4);            // N<<7 | Z<<6
        as_.alu(OR, 4, u, RAX);
        as_.shift_imm(SHL, 4, u, 8);            // -> AH position
        as_.alu_imm(AND, 4, t, 1);              // V in bit 0 -> AL
        as_.alu(OR, 4, u, t);
        as_.mov(4, RAX, u);
        as_.alu_imm(ADD, 1, RAX, 0x7f);         // OF = (AL == 1)
        as_.sahf();                             // SF ZF CF from AH, OF preserved
        eflags_ = v;
        return;
    }
    case Op::NZCVFromFlags: {
        need_flags(in.a);
        take_reg(RAX);
        pinned_ |= 1 << RAX;
        Reg d = alloc_temp();
        pinned_ |= 1 << d;
        // nzcv = N<<31 | Z<<30 | C<<29 | V<<28 from canonical EFLAGS
        as_.pushfq();
        as_.pop(RAX);
        // rax = eflags: CF bit0, ZF bit6, SF bit7, OF bit11
        as_.mov(4, d, RAX);
        // compute using bt-free arithmetic is clumsy; use shifts and masks
        as_.push(RAX);  // keep eflags
        // N
        as_.shift_imm(SHR, 4, d, 7); as_.alu_imm(AND, 4, d, 1); as_.shift_imm(SHL, 4, d, 31);
        // Z
        as_.mov(4, RAX, mem(RSP, 0)); as_.shift_imm(SHR, 4, RAX, 6); as_.alu_imm(AND, 4, RAX, 1);
        as_.shift_imm(SHL, 4, RAX, 30); as_.alu(OR, 4, d, RAX);
        // C = !CF
        as_.mov(4, RAX, mem(RSP, 0)); as_.not_(4, RAX); as_.alu_imm(AND, 4, RAX, 1);
        as_.shift_imm(SHL, 4, RAX, 29); as_.alu(OR, 4, d, RAX);
        // V
        as_.mov(4, RAX, mem(RSP, 0)); as_.shift_imm(SHR, 4, RAX, 11); as_.alu_imm(AND, 4, RAX, 1);
        as_.shift_imm(SHL, 4, RAX, 28); as_.alu(OR, 4, d, RAX);
        as_.popfq();  // restore flags (pops the saved eflags)
        if (owner_[RAX] == 0) {}
        assign_reg(v, d);
        return;
    }
    case Op::Load: emit_load(v); return;
    case Op::Store: emit_store(v); return;
    case Op::LoadExcl: case Op::StoreExcl: case Op::ClearExcl: case Op::AtomicRMW: case Op::Cas:
        emit_atomic(v); return;
    case Op::Barrier:
        if (in.aux == BAR_FULL) {
            if (flags_needed_after(cur_)) as_.mfence();
            else { clobber_flags(); as_.lock_or_rsp(); }
        }
        // BAR_ISB / LOAD / STORE: nothing under TSO (see docs/memory-model.md)
        return;
    case Op::GetSys: case Op::SetSys: emit_sys(v); return;
    case Op::VGet: case Op::VSet: case Op::VLoad: case Op::VStore: case Op::VOp:
    case Op::VToGpr: case Op::GprToV: case Op::FCmpFlags: case Op::FCCmpFlags:
    case Op::VConst: case Op::VSelect: case Op::FToI: case Op::IToF:
        emit_vec(v); return;
    case Op::Helper: {
        // sub=1: CRC32/CRC32C (size in .size, aux=1 for the Castagnoli polynomial)
        if (in.sub == 1 && in.aux == 1 && g_host.sse42) {
            pin(in.a); pin(in.b);
            Reg rb = to_reg(in.b); pinned_ |= 1 << rb;
            Reg ra = to_reg(in.a); pinned_ |= 1 << ra;
            clobber_flags();
            Reg d = dest_for(v, 4);
            if (d == rb) { Reg t = alloc_temp(); pinned_ |= 1 << t; as_.mov(8, t, rb); rb = t; }
            if (d != ra) as_.mov(4, d, ra);
            // crc32 d, rb  (F2 [REX.W] 0F 38 F0/F1)
            int sz = in.size;
            if (sz == 2) as_.db(0x66);
            as_.db(0xF2);
            as_.rex(sz == 8, d, 0, rb, sz == 1 && as_.needs_byte_rex(rb));
            as_.db(0x0F); as_.db(0x38); as_.db(sz == 1 ? 0xF0 : 0xF1);
            as_.modrm_rr(d, rb);
            finish_def(v, d);
            return;
        }
        emit_call_c((void*)&xef_helper_crc32, v, in.a, in.b, (u64)in.size | ((u64)in.aux << 8));
        return;
    }
    default:
        if (is_terminator(in.op)) { emit_terminator(v); return; }
        fatal("codegen: unhandled op %s", op_name(in.op));
    }
}

void T1::emit_binop(Val v) {
    const Inst& in = I(v);
    int s = sz(in.ty);
    Val a = in.a, b = in.b;
    // fuse with an immediately following flags op on the same operands
    int nx = v + 1;
    while (nx < b_.n && (vi_[nx].dead || vi_[nx].folded)) nx++;
    bool fuse = false;
    if (nx < b_.n) {
        const Inst& f = I(nx);
        if ((in.op == Op::Sub && f.op == Op::FlagsSub && f.a == a && f.b == b) ||
            (in.op == Op::Add && f.op == Op::FlagsAdd && f.a == a && f.b == b) ||
            ((in.op == Op::And || in.op == Op::AndNot) && f.op == Op::FlagsLogic && f.a == v))
            if (sz(in.ty) == f.size / 8) fuse = true;
    }
    bool fneed = flags_needed_after(cur_) && !fuse;

    pin(a); pin(b);
    // flag-free forms when EFLAGS must be preserved
    if (fneed && (in.op == Op::Add || (in.op == Op::Sub && fits_i32(b, s) && cv(b) != 0x80000000ull))) {
        Reg ra = to_reg(a);
        pinned_ |= 1 << ra;
        Reg d;
        if (in.op == Op::Add && fits_i32(b, s)) {
            d = dest_for(v, s);
            as_.lea(s, d, mem(ra, (i32)cv(b)));
        } else if (in.op == Op::Sub) {
            d = dest_for(v, s);
            as_.lea(s, d, mem(ra, -(i32)cv(b)));
        } else {
            Reg rb = to_reg(b);
            pinned_ |= 1 << rb;
            d = dest_for(v, s);
            as_.lea(s, d, mem(ra, rb, 0, 0));
        }
        finish_def(v, d);
        return;
    }
    if (fneed && in.op == Op::Sub) {
        // a - b == a + ~b + 1, computed with NOT/LEA (neither touches EFLAGS)
        Opnd ob = opnd(b, true, false, s);
        if (ob.k == Opnd::R) pinned_ |= 1 << ob.r;
        bool ac = fits_i32(a, s) && (i64)cv(a) != INT32_MAX;
        Reg ra = NOREG;
        if (!ac) { ra = to_reg(a); pinned_ |= 1 << ra; }
        Reg d = dest_for(v, s);
        if (d == ra || (ob.k == Opnd::R && d == ob.r && false)) {
            Reg t = alloc_temp(); pinned_ |= 1 << t;
            emit_mov_opnd(s, t, ob);
            as_.not_(s, t);
            as_.lea(s, d, mem(ra, t, 0, 1));
        } else {
            emit_mov_opnd(s, d, ob);
            as_.not_(s, d);
            if (ac) as_.lea(s, d, mem(d, (i32)cv(a) + 1));
            else as_.lea(s, d, mem(ra, d, 0, 1));
        }
        finish_def(v, d);
        return;
    }
    if (in.op == Op::And && is_c(b) && !fuse) {
        u64 m = cv(b);
        if (m == 0xff || m == 0xffff || (m == 0xffffffffull && s == 8)) {
            Reg ra = to_reg(a); pinned_ |= 1 << ra;
            Reg d = dest_for(v, s);
            if (m == 0xff) as_.movzx8(d, ra);
            else if (m == 0xffff) as_.movzx16(d, ra);
            else as_.mov(4, d, ra);
            finish_def(v, d);
            return;
        }
    }
    clobber_flags();
    Reg d;
    switch (in.op) {
    case Op::AndNot: case Op::OrNot: case Op::XorNot: {
        if (in.op == Op::AndNot && g_host.bmi1) {
            Reg ra = to_reg(a); pinned_ |= 1 << ra;
            Reg rb = to_reg(b); pinned_ |= 1 << rb;
            d = dest_for(v, s);
            as_.andn(s, d, rb, ra);
        } else {
            Opnd oa = opnd(a, true, true, s);
            if (oa.k == Opnd::R) pinned_ |= 1 << oa.r;
            Opnd ob = opnd(b, true, true, s);
            if (ob.k == Opnd::R) pinned_ |= 1 << ob.r;
            AluOp op = in.op == Op::AndNot ? AND : in.op == Op::OrNot ? OR : XOR;
            d = dest_for(v, s);
            Reg t = d;
            if (oa.k == Opnd::R && oa.r == d) { t = alloc_temp(); pinned_ |= 1 << t; }
            emit_mov_opnd(s, t, ob);
            as_.not_(s, t);
            emit_alu(op, s, t, oa);
            if (t != d) as_.mov(s, d, t);
        }
        break;
    }
    case Op::Mul: {
        Opnd ob = opnd(b, true, true, s);
        if (ob.k == Opnd::I) {
            Reg ra = to_reg(a); pinned_ |= 1 << ra;
            d = dest_for(v, s);
            as_.imul_imm(s, d, ra, (i32)ob.imm);
        } else {
            if (ob.k == Opnd::R) pinned_ |= 1 << ob.r;
            Opnd oa = opnd(a, true, false, s);
            if (oa.k == Opnd::R) pinned_ |= 1 << oa.r;
            d = dest_for(v, s);
            if (ob.k == Opnd::R && ob.r == d) {
                if (oa.k == Opnd::R) as_.imul(s, d, oa.r); else as_.imul(s, d, oa.m);
            } else {
                emit_mov_opnd(s, d, oa);
                if (ob.k == Opnd::R) as_.imul(s, d, ob.r); else as_.imul(s, d, ob.m);
            }
        }
        break;
    }
    default: {
        AluOp op = in.op == Op::Add ? ADD : in.op == Op::Sub ? SUB : in.op == Op::And ? AND
                 : in.op == Op::Or ? OR : XOR;
        bool comm = op != SUB;
        Opnd ob = opnd(b, true, true, s);
        if (ob.k == Opnd::R) pinned_ |= 1 << ob.r;
        Opnd oa = opnd(a, true, true, s);
        if (oa.k == Opnd::R) pinned_ |= 1 << oa.r;
        d = dest_for(v, s);
        if (oa.k == Opnd::R && oa.r == d) emit_alu(op, s, d, ob);
        else if (ob.k == Opnd::R && ob.r == d) {
            if (comm) emit_alu(op, s, d, oa);
            else {
                Reg t = alloc_temp(); pinned_ |= 1 << t;
                emit_mov_opnd(s, t, oa);
                emit_alu(op, s, t, ob);
                as_.mov(s, d, t);
            }
        } else {
            emit_mov_opnd(s, d, oa);
            emit_alu(op, s, d, ob);
        }
        break;
    }
    }
    finish_def(v, d);
    if (fuse) {
        Val f = (Val)nx;
        const Inst& fi = I(f);
        if (fi.op == Op::FlagsAdd) as_.cmc();
        else if (fi.op == Op::FlagsLogic) as_.stc();
        eflags_ = f;
        vi_[f].folded = true;  // skip
    }
}

void T1::emit_shift(Val v) {
    const Inst& in = I(v);
    int s = sz(in.ty);
    int bitsz = s * 8;
    Val a = in.a, b = in.b;
    pin(a); pin(b);
    bool fneed = flags_needed_after(cur_);
    if (is_c(b)) {
        int k = (int)(cv(b) & (bitsz - 1));
        Reg ra = to_reg(a); pinned_ |= 1 << ra;
        if (in.op == Op::Ror && g_host.bmi2) {
            Reg d = dest_for(v, s);
            as_.rorx(s, d, ra, (u8)k);
            finish_def(v, d);
            return;
        }
        if (in.op == Op::Shl && k >= 1 && k <= 3 && fneed) {
            Reg d = dest_for(v, s);
            as_.lea(s, d, mem_idx(ra, k, 0));
            finish_def(v, d);
            return;
        }
        if (fneed && g_host.bmi2 && in.op != Op::Ror) {
            Reg t = alloc_temp(); pinned_ |= 1 << t;
            as_.mov_imm(t, (u64)k);
            Reg d = dest_for(v, s);
            if (in.op == Op::Shl) as_.shlx(s, d, ra, t);
            else if (in.op == Op::Lshr) as_.shrx(s, d, ra, t);
            else as_.sarx(s, d, ra, t);
            finish_def(v, d);
            return;
        }
        clobber_flags();
        Reg d = dest_for(v, s);
        if (d != ra) as_.mov(s, d, ra);
        ShiftOp op = in.op == Op::Shl ? SHL : in.op == Op::Lshr ? SHR : in.op == Op::Ashr ? SAR : ROR;
        as_.shift_imm(op, s, d, (u8)k);
        finish_def(v, d);
        return;
    }
    // variable shift
    if (g_host.bmi2 && in.op != Op::Ror) {
        Reg ra = to_reg(a); pinned_ |= 1 << ra;
        Reg rb = to_reg(b); pinned_ |= 1 << rb;
        Reg d = dest_for(v, s);
        if (in.op == Op::Shl) as_.shlx(s, d, ra, rb);
        else if (in.op == Op::Lshr) as_.shrx(s, d, ra, rb);
        else as_.sarx(s, d, ra, rb);
        finish_def(v, d);
        return;
    }
    clobber_flags();
    // need count in CL
    Val rb_v = resolve(b);
    bool b_in_rcx = (vi_[rb_v].k == L_REG || vi_[rb_v].k == L_GREG) && vi_[rb_v].reg == RCX;
    if (!b_in_rcx) {
        take_reg(RCX);
        pinned_ |= 1 << RCX;
        load_into(RCX, b, 4);
    } else pinned_ |= 1 << RCX;
    Reg ra = to_reg(a); pinned_ |= 1 << ra;
    Reg d = dest_for(v, s);
    if (d == RCX) { Reg t = alloc_temp(); pinned_ |= 1 << t; d = t; }
    if (d != ra) as_.mov(s, d, ra);
    ShiftOp op = in.op == Op::Shl ? SHL : in.op == Op::Lshr ? SHR : in.op == Op::Ashr ? SAR : ROR;
    as_.shift_cl(op, s, d);
    finish_def(v, d);
}

void T1::emit_misc_unary(Val v) {
    const Inst& in = I(v);
    int s = sz(in.ty);
    Val a = in.a;
    pin(a);
    Reg ra = to_reg(a); pinned_ |= 1 << ra;
    switch (in.op) {
    case Op::Not: {
        Reg d = dest_for(v, s);
        if (d != ra) as_.mov(s, d, ra);
        as_.not_(s, d);  // NOT does not affect flags
        finish_def(v, d);
        return;
    }
    case Op::Bswap: {
        Reg d = dest_for(v, s);
        if (d != ra || s == 4) as_.mov(s, d, ra);
        as_.bswap(s, d);
        finish_def(v, d);
        return;
    }
    case Op::Rev32InWords: {
        clobber_flags();
        Reg d = dest_for(v, s);
        if (d != ra) as_.mov(8, d, ra);
        as_.bswap(8, d);
        as_.shift_imm(ROR, 8, d, 32);
        finish_def(v, d);
        return;
    }
    default: break;
    }
    clobber_flags();
    switch (in.op) {
    case Op::Neg: {
        Reg d = dest_for(v, s);
        if (d != ra) as_.mov(s, d, ra);
        as_.neg(s, d);
        finish_def(v, d);
        return;
    }
    case Op::Clz: case Op::Cls: {
        Reg d;
        Reg src = ra;
        if (in.op == Op::Cls) {
            Reg t = alloc_temp(); pinned_ |= 1 << t;
            as_.mov(s, t, ra);
            as_.shift_imm(SAR, s, t, 1);
            as_.alu(XOR, s, t, ra);
            src = t;
        }
        d = dest_for(v, s);
        if (g_host.lzcnt) as_.lzcnt(s, d, src);
        else {
            // bsr: undefined for 0 -> use cmov
            Reg t2 = alloc_temp(); pinned_ |= 1 << t2;
            as_.mov_imm(t2, (u64)(2 * s * 8 - 1));
            as_.bsr(s, d, src);
            as_.cmov(CE, s, d, t2);
            as_.alu_imm(XOR, s, d, s * 8 - 1);
        }
        if (in.op == Op::Cls) as_.alu_imm(SUB, s, d, 1);
        finish_def(v, d);
        return;
    }
    case Op::Rev16: {
        Reg d = dest_for(v, s);
        if (s == 4) {
            if (d != ra) as_.mov(4, d, ra);
            as_.bswap(4, d);
            as_.shift_imm(ROR, 4, d, 16);
        } else {
            Reg t = alloc_temp(); pinned_ |= 1 << t;
            Reg m = alloc_temp(); pinned_ |= 1 << m;
            as_.mov_imm(m, 0x00ff00ff00ff00ffull);
            if (d == ra) { Reg tt = t; as_.mov(8, tt, ra); ra = tt; t = d; }
            // d = ((ra >> 8) & m) | ((ra & m) << 8)
            as_.mov(8, t, ra);
            as_.shift_imm(SHR, 8, t, 8);
            as_.alu(AND, 8, t, m);
            as_.alu(AND, 8, m, ra);
            as_.shift_imm(SHL, 8, m, 8);
            as_.alu(OR, 8, t, m);
            if (t != d) as_.mov(8, d, t);
        }
        finish_def(v, d);
        return;
    }
    case Op::Rbit: {
        // bswap, then swap nibbles, bit-pairs and bits with masks
        Reg t = alloc_temp(); pinned_ |= 1 << t;
        Reg m = alloc_temp(); pinned_ |= 1 << m;
        Reg x = dest_for(v, s);
        if (x == t || x == m) fatal("rbit regs");
        if (x != ra) as_.mov(s, x, ra);
        as_.bswap(s, x);
        const u64 masks[3] = {0x0f0f0f0f0f0f0f0full, 0x3333333333333333ull, 0x5555555555555555ull};
        const int sh[3] = {4, 2, 1};
        for (int k = 0; k < 3; k++) {
            as_.mov_imm(m, s == 4 ? (masks[k] & 0xffffffffull) : masks[k]);
            as_.mov(s, t, x);
            as_.shift_imm(SHR, s, t, (u8)sh[k]);
            as_.alu(AND, s, t, m);
            as_.alu(AND, s, x, m);
            as_.shift_imm(SHL, s, x, (u8)sh[k]);
            as_.alu(OR, s, x, t);
        }
        finish_def(v, x);
        return;
    }
    default: fatal("unary");
    }
}

void T1::emit_ext(Val v) {
    const Inst& in = I(v);
    int s = sz(in.ty);
    int from = in.size;
    if (is_alias_op(in)) {
        vi_[v].k = L_ALIAS;
        return;
    }
    Val a = in.a;
    pin(a);
    Reg ra = to_reg(a); pinned_ |= 1 << ra;
    if (in.op == Op::Zext) {
        if (from == 8 || from == 16 || from == 32) {
            Reg d = dest_for(v, s);
            if (from == 8) as_.movzx8(d, ra);
            else if (from == 16) as_.movzx16(d, ra);
            else as_.mov(4, d, ra);
            finish_def(v, d);
            return;
        }
        u64 m = (1ull << from) - 1;
        if (m <= 0x7fffffff) {
            clobber_flags();
            Reg d = dest_for(v, s);
            if (d != ra) as_.mov(s, d, ra);
            as_.alu_imm(AND, s, d, (i32)m);
            finish_def(v, d);
            return;
        }
        // wide mask: shl+shr
        bool fneed = flags_needed_after(cur_);
        if (fneed && g_host.bmi2) {
            Reg t = alloc_temp(); pinned_ |= 1 << t;
            Reg d = dest_for(v, s);
            as_.mov_imm(t, (u64)(s * 8 - from));
            as_.shlx(s, d, ra, t);
            as_.shrx(s, d, d, t);
            finish_def(v, d);
            return;
        }
        clobber_flags();
        Reg d = dest_for(v, s);
        if (d != ra) as_.mov(s, d, ra);
        as_.shift_imm(SHL, s, d, (u8)(s * 8 - from));
        as_.shift_imm(SHR, s, d, (u8)(s * 8 - from));
        finish_def(v, d);
        return;
    }
    // Sext
    if (from == 8 || from == 16 || (from == 32 && s == 8)) {
        Reg d = dest_for(v, s);
        as_.movsx(s, d, ra, from / 8);
        finish_def(v, d);
        return;
    }
    bool fneed = flags_needed_after(cur_);
    if (fneed && g_host.bmi2) {
        Reg t = alloc_temp(); pinned_ |= 1 << t;
        Reg d = dest_for(v, s);
        as_.mov_imm(t, (u64)(s * 8 - from));
        as_.shlx(s, d, ra, t);
        as_.sarx(s, d, d, t);
        finish_def(v, d);
        return;
    }
    clobber_flags();
    Reg d = dest_for(v, s);
    if (d != ra) as_.mov(s, d, ra);
    as_.shift_imm(SHL, s, d, (u8)(s * 8 - from));
    as_.shift_imm(SAR, s, d, (u8)(s * 8 - from));
    finish_def(v, d);
}

void T1::emit_mulh(Val v) {
    const Inst& in = I(v);
    clobber_flags();
    // widening multiply uses rdx:rax; rdx is X2, so it is saved in r11 around the mul.
    pin(in.a); pin(in.b);
    take_reg(RAX); pinned_ |= 1 << RAX;
    take_reg(R11); pinned_ |= 1 << R11;
    Reg hint = dest_hint(v);
    load_into(RAX, in.a, 8);
    pinned_ = (1 << RAX) | (1 << R11);
    pin(in.b);
    Opnd ob = opnd(in.b, true, false, 8);
    if (ob.k == Opnd::R) pinned_ |= 1 << ob.r;
    as_.mov(8, R11, RDX);
    if (ob.k == Opnd::R) {
        Reg src = ob.r == RDX ? R11 : ob.r;
        if (in.op == Op::UMulH) as_.mul1(8, src); else as_.imul1(8, src);
    } else {
        as_.op_rm(8, {0xF7}, in.op == Op::UMulH ? 4 : 5, ob.m);
    }
    if (hint == RDX) { finish_def(v, RDX); return; }
    pinned_ = (1 << RAX) | (1 << R11);
    Reg d = hint != NOREG ? hint : alloc_temp();
    as_.mov(8, d, RDX);
    as_.mov(8, RDX, R11);
    finish_def(v, d);
}

void T1::emit_div(Val v) {
    const Inst& in = I(v);
    int s = sz(in.ty);
    clobber_flags();
    pin(in.a); pin(in.b);
    take_reg(RAX); pinned_ |= 1 << RAX;
    take_reg(RCX); pinned_ |= 1 << RCX;
    take_reg(R11); pinned_ |= 1 << R11;
    load_into(RCX, in.b, s);       // divisor
    load_into(RAX, in.a, s);       // dividend
    Label zero, done, neg;
    as_.test(s, RCX, RCX);
    as_.jcc(CE, zero);
    if (in.op == Op::SDiv) {
        as_.alu_imm(CMP, s, RCX, -1);
        as_.jcc(CE, neg);
    }
    as_.mov(8, R11, RDX);
    if (in.op == Op::SDiv) { if (s == 8) as_.cqo(); else as_.cdq(); as_.idiv1(s, RCX); }
    else { as_.alu(XOR, 4, RDX, RDX); as_.div1(s, RCX); }
    as_.mov(8, RDX, R11);
    as_.jmp(done);
    as_.bind(zero);
    as_.alu(XOR, 4, RAX, RAX);
    if (in.op == Op::SDiv) {
        as_.jmp(done);
        as_.bind(neg);
        as_.neg(s, RAX);
    }
    as_.bind(done);
    // result in rax; the operands are no longer needed in RCX/R11
    pinned_ = 1 << RAX;
    Reg d = dest_for(v, s);
    if (d != RAX) as_.mov(8, d, RAX);
    finish_def(v, d);
}

void T1::emit_flags(Val v, bool, Reg) {
    const Inst& in = I(v);
    int s = in.size / 8;
    clobber_flags();
    if (in.op == Op::FlagsSub) {
        Opnd ob = opnd(in.b, true, true, s);
        if (ob.k == Opnd::R) pinned_ |= 1 << ob.r;
        Opnd oa = opnd(in.a, ob.k != Opnd::M, false, s);
        if (oa.k == Opnd::M) {
            if (ob.k == Opnd::I) as_.alu_imm(CMP, s, oa.m, (i32)ob.imm);
            else as_.alu(CMP, s, oa.m, ob.r);
        } else emit_alu(CMP, s, oa.r, ob);
    } else if (in.op == Op::FlagsAdd) {
        // flags of a+b without writing a: use a temp
        Opnd ob = opnd(in.b, true, true, s);
        if (ob.k == Opnd::R) pinned_ |= 1 << ob.r;
        Opnd oa = opnd(in.a, true, true, s);
        if (oa.k == Opnd::R) pinned_ |= 1 << oa.r;
        Reg t = alloc_temp();
        emit_mov_opnd(s, t, oa);
        emit_alu(ADD, s, t, ob);
        as_.cmc();
    } else {  // FlagsLogic
        Reg r = to_reg(in.a, s);
        as_.test(s, r, r);
        as_.stc();
    }
    eflags_ = v;
}

void T1::remat_flags(Val f, u8 cond) {
    const Inst& in = I(f);
    int s = in.size / 8;
    bool nz_only = cond == ir::EQ || cond == ir::NE || cond == ir::MI || cond == ir::PL;
    if (in.op == Op::FlagsLogic || (nz_only && vi_[f].rres)) {
        Reg r = to_reg(vi_[f].rres, s);
        as_.test(s, r, r);
        if (in.op == Op::FlagsLogic) as_.stc();
        return;
    }
    if (in.op == Op::FlagsSub) {
        Opnd ob = opnd(in.b, true, true, s);
        if (ob.k == Opnd::R) pinned_ |= 1 << ob.r;
        Opnd oa = opnd(in.a, ob.k != Opnd::M, false, s);
        if (oa.k == Opnd::M) {
            if (ob.k == Opnd::I) as_.alu_imm(CMP, s, oa.m, (i32)ob.imm);
            else as_.alu(CMP, s, oa.m, ob.r);
        } else emit_alu(CMP, s, oa.r, ob);
        return;
    }
    // FlagsAdd
    Opnd ob = opnd(in.b, true, true, s);
    if (ob.k == Opnd::R) pinned_ |= 1 << ob.r;
    Opnd oa = opnd(in.a, true, true, s);
    if (oa.k == Opnd::R) pinned_ |= 1 << oa.r;
    Reg t = alloc_temp();
    emit_mov_opnd(s, t, oa);
    emit_alu(ADD, s, t, ob);
    as_.cmc();
}

void T1::emit_adc_sbc(Val v, bool flags_out, Val) {
    const Inst& in = I(v);
    bool sub = in.op == Op::Sbc || in.op == Op::FlagsSbc;
    int s = flags_out ? in.size / 8 : sz(in.ty);
    // Pair: an Adc value op followed by the matching Flags op -> emit once
    if (!flags_out) {
        int nx = v + 1;
        while (nx < b_.n && (vi_[nx].dead || vi_[nx].folded)) nx++;
        bool fuse = nx < b_.n && I(nx).op == (sub ? Op::FlagsSbc : Op::FlagsAdc) && I(nx).a == in.a &&
                    I(nx).b == in.b && I(nx).c == in.c;
        pin(in.a); pin(in.b);
        Reg ra = to_reg(in.a); pinned_ |= 1 << ra;
        Opnd ob = opnd(in.b, true, true, s);
        if (ob.k == Opnd::R) pinned_ |= 1 << ob.r;
        Reg d = dest_for(v, s);
        if (ob.k == Opnd::R && ob.r == d && d != ra) {
            Reg t = alloc_temp(); pinned_ |= 1 << t; as_.mov(8, t, ob.r); ob.r = t;
        }
        // flags must hold the input carry; mov does not disturb flags
        if (d != ra) as_.mov(s, d, ra);
        need_flags(in.c);
        if (flags_needed_after(cur_) && !fuse) {
            // preserve: spill, compute, restore later
            as_.pushfq(); as_.pop(mem(R15, XEF_ST(flags_spill)));
            spilled_flags_ = eflags_;
        }
        if (!sub) as_.cmc();
        emit_alu(sub ? SBB : ADC, s, d, ob);
        if (fuse) {
            if (!sub) as_.cmc();
            eflags_ = (Val)nx;
            vi_[nx].folded = true;
        } else eflags_ = 0;
        finish_def(v, d);
        return;
    }
    // standalone flags op (result unused)
    Reg ra = to_reg(in.a); pinned_ |= 1 << ra;
    Opnd ob = opnd(in.b, true, true, s);
    if (ob.k == Opnd::R) pinned_ |= 1 << ob.r;
    Reg t = alloc_temp(); pinned_ |= 1 << t;
    as_.mov(s, t, ra);
    need_flags(in.c);
    if (!sub) as_.cmc();
    emit_alu(sub ? SBB : ADC, s, t, ob);
    if (!sub) as_.cmc();
    eflags_ = v;
}

void T1::emit_select(Val v) {
    const Inst& in = I(v);
    int s = sz(in.ty);
    Cond c = x86_cond((ir::Cond)in.aux);
    pin(in.b); pin(in.c);
    // cset patterns
    if (is_c(in.b) && is_c(in.c)) {
        u64 tv = cv(in.b), fv = cv(in.c);
        u64 m = s == 4 ? 0xffffffffull : ~0ull;
        if ((tv & m) == 1 && fv == 0) {
            need_flags(in.a, in.aux);
            Reg d = dest_for(v, s);
            as_.setcc(c, d);
            as_.movzx8(d, d);
            finish_def(v, d);
            return;
        }
        if ((tv & m) == m && fv == 0) {  // csetm
            need_flags(in.a, in.aux);
            Reg d = dest_for(v, s);
            as_.setcc(c, d);
            as_.movzx8(d, d);
            // negate without flags: d = 0 - d via lea? use not+inc... use: d = ~(d-1)
            as_.lea(s, d, mem(d, -1));
            as_.not_(s, d);
            finish_def(v, d);
            return;
        }
    }
    Opnd ot = opnd(in.b, true, false, s);
    if (ot.k == Opnd::R) pinned_ |= 1 << ot.r;
    Opnd of = opnd(in.c, true, true, s);
    if (of.k == Opnd::R) pinned_ |= 1 << of.r;
    Reg d = dest_for(v, s);
    if (ot.k == Opnd::R && ot.r == d) {
        // d already holds true value: cmov with inverted cond from false value
        if (of.k == Opnd::I) {
            Reg t = alloc_temp(); pinned_ |= 1 << t;
            as_.mov_imm(t, (u64)of.imm);
            of.k = Opnd::R; of.r = t;
        }
        need_flags(in.a, in.aux);
        if (of.k == Opnd::R) as_.cmov(invert(c), s, d, of.r); else as_.cmov(invert(c), s, d, of.m);
        if (s == 4 && false) {}
    } else {
        if (of.k == Opnd::R && of.r == d) {
        } else emit_mov_opnd(s, d, of);  // mov does not touch flags
        need_flags(in.a, in.aux);
        if (ot.k == Opnd::R) as_.cmov(c, s, d, ot.r); else as_.cmov(c, s, d, ot.m);
    }
    finish_def(v, d);
}

void T1::emit_set_const_flags(u32 nzcv) {
    // RAX must be free (caller reserved it). SAHF sets SF ZF AF PF CF; OF is set first.
    if (nzcv & 1) { as_.mov_imm(RAX, 0x7f); as_.alu_imm(ADD, 1, RAX, 1); }
    else as_.alu(XOR, 4, RAX, RAX);
    as_.db(0xB4); as_.db(sahf_byte(nzcv));  // mov ah, imm8
    as_.sahf();
}

void T1::emit_ccmp(Val v) {
    const Inst& in = I(v);
    int s = in.size / 8;
    ir::Cond c = (ir::Cond)in.aux;
    u32 nzcv = (u32)in.imm;
    take_reg(RAX); pinned_ |= 1 << RAX;
    pin(in.a); pin(in.b);
    Opnd ob = opnd(in.b, true, true, s);
    if (ob.k == Opnd::R) pinned_ |= 1 << ob.r;
    Opnd oa = opnd(in.a, false, false, s);
    pinned_ |= 1 << oa.r;
    Reg t = NOREG;
    if (in.sub == 0) { t = alloc_temp(); pinned_ |= 1 << t; }  // CCMN needs scratch
    need_flags(in.c);
    if (c == ir::AL || c == ir::NV) {
        if (in.sub) emit_alu(CMP, s, oa.r, ob);
        else { as_.mov(s, t, oa.r); emit_alu(ADD, s, t, ob); as_.cmc(); }
    } else {
        Label then, done;
        as_.jcc(x86_cond(c), then);
        emit_set_const_flags(nzcv);
        as_.jmp(done);
        as_.bind(then);
        if (in.sub) emit_alu(CMP, s, oa.r, ob);
        else { as_.mov(s, t, oa.r); emit_alu(ADD, s, t, ob); as_.cmc(); }
        as_.bind(done);
    }
    eflags_ = v;
    spilled_flags_ = spilled_flags_ == fid(in.c) ? spilled_flags_ : spilled_flags_;
}

void T1::emit_load(Val v) {
    const Inst& in = I(v);
    int s = sz(in.ty);
    int msz = in.size;
    bool sign = in.aux & 1;
    Mem m = addr_mem(in.a);
    Reg d = dest_for(v, s);
    record_pc();
    if (sign) as_.movsx_load(s, d, m, msz);
    else as_.movzx_load(d, m, msz);
    finish_def(v, d);
}

void T1::emit_store(Val v) {
    const Inst& in = I(v);
    int msz = in.size;
    bool seqcst = in.aux & 1;
    Mem m = addr_mem(in.a);
    Val val = in.b;
    if (seqcst) {
        // xchg has implicit lock semantics: store + full barrier (RCsc release)
        Reg t = alloc_temp(); pinned_ |= 1 << t;
        load_into(t, val, msz == 8 ? 8 : 4);
        record_pc();
        as_.xchg(msz, m, t);
        return;
    }
    Opnd o = opnd(val, false, true, msz == 8 ? 8 : 4);
    record_pc();
    if (o.k == Opnd::I) {
        i64 imm = o.imm;
        if (msz == 8 && (i64)imm != (i32)imm) fatal("store imm");
        as_.mov_imm(msz, m, (i32)imm);
    } else as_.mov(msz, m, o.r);
}

void T1::emit_atomic(Val v) {
    const Inst& in = I(v);
    int msz = in.size;
    int s = msz == 8 ? 8 : 4;
    switch (in.op) {
    case Op::ClearExcl:
        as_.mov_imm(8, mem(R15, XEF_ST(excl_addr)), -1);
        return;
    case Op::LoadExcl: {
        if (in.aux != 0) { emit_pair_atomic(v); return; }
        pin(in.a);
        Reg ra = to_reg(in.a); pinned_ |= 1 << ra;
        Reg d = dest_for(v, s);
        record_pc();
        as_.movzx_load(d, mem(ra, 0), msz);
        as_.mov(8, mem(R15, XEF_ST(excl_addr)), ra);
        as_.mov(8, mem(R15, XEF_ST(excl_val)), d);
        finish_def(v, d);
        return;
    }
    case Op::StoreExcl: {
        if (in.aux != 0) { emit_pair_atomic(v); return; }
        clobber_flags();
        take_reg(RAX); pinned_ |= 1 << RAX;
        pin(in.a); pin(in.b);
        Reg ra = to_reg(in.a); pinned_ |= 1 << ra;
        Reg rv = to_reg(in.b); pinned_ |= 1 << rv;
        if (ra == RAX || rv == RAX) fatal("excl regs");
        Label fail, done;
        as_.alu(CMP, 8, ra, mem(R15, XEF_ST(excl_addr)));
        as_.jcc(CNE, fail);
        as_.mov(8, RAX, mem(R15, XEF_ST(excl_val)));
        record_pc();
        as_.cmpxchg(msz, mem(ra, 0), rv);
        as_.mov_imm(8, mem(R15, XEF_ST(excl_addr)), -1);
        Reg d = dest_for(v, 4);
        if (d == RAX) fatal("excl dest");
        as_.setcc(CNE, d);
        as_.movzx8(d, d);
        as_.jmp(done);
        as_.bind(fail);
        as_.mov_imm(d, 1);
        as_.bind(done);
        finish_def(v, d);
        return;
    }
    case Op::Cas: {
        if (in.aux != 0) { emit_pair_atomic(v); return; }
        clobber_flags();
        take_reg(RAX); pinned_ |= 1 << RAX;
        pin(in.a); pin(in.b); pin(in.c);
        Reg ra = to_reg(in.a); pinned_ |= 1 << ra;
        Reg rn = to_reg(in.c); pinned_ |= 1 << rn;
        if (ra == RAX || rn == RAX) fatal("cas regs");
        load_into(RAX, in.b, s);
        record_pc();
        as_.cmpxchg(msz, mem(ra, 0), rn);
        // old value in rax (zero-extend small sizes)
        if (msz == 1) as_.movzx8(RAX, RAX);
        else if (msz == 2) as_.movzx16(RAX, RAX);
        Reg d = dest_for(v, s);
        if (d != RAX) as_.mov(8, d, RAX);
        finish_def(v, d);
        if (d != RAX) owner_[RAX] = 0;
        return;
    }
    case Op::AtomicRMW: {
        clobber_flags();
        u8 aop = in.aux;
        // the CMPXCHG loop needs RAX: claim it before the address can be placed there
        if (aop != AT_ADD && aop != AT_SWP) { take_reg(RAX); pinned_ |= 1 << RAX; }
        pin(in.a); pin(in.b);
        Reg ra = to_reg(in.a); pinned_ |= 1 << ra;
        if (aop == AT_ADD || aop == AT_SWP) {
            Reg t = alloc_temp(); pinned_ |= 1 << t;
            load_into(t, in.b, s);
            record_pc();
            if (aop == AT_ADD) as_.xadd(msz, mem(ra, 0), t);
            else as_.xchg(msz, mem(ra, 0), t);
            if (msz == 1) as_.movzx8(t, t);
            else if (msz == 2) as_.movzx16(t, t);
            assign_reg(v, t);
            return;
        }
        if (ra == RAX) fatal("rmw regs");
        Reg rv = to_reg(in.b); pinned_ |= 1 << rv;
        Reg t = alloc_temp(); pinned_ |= 1 << t;
        Label loop;
        record_pc();
        as_.movzx_load(RAX, mem(ra, 0), msz);
        as_.bind(loop);
        as_.mov(8, t, RAX);
        int cs = msz == 8 ? 8 : 4;
        switch (aop) {
        case AT_CLR: { as_.push(rv); as_.not_(8, rv); as_.alu(AND, 8, t, rv); as_.pop(rv); break; }
        case AT_EOR: as_.alu(XOR, 8, t, rv); break;
        case AT_SET: as_.alu(OR, 8, t, rv); break;
        case AT_SMAX: case AT_SMIN: case AT_UMAX: case AT_UMIN: {
            // compare at access width (sign-extend for signed small sizes)
            Reg x = t;  // holds old
            if (msz < 4 && (aop == AT_SMAX || aop == AT_SMIN)) {
                as_.push(rv);
                as_.movsx(4, x, RAX, msz);
                as_.movsx(4, rv, rv, msz);
                as_.alu(CMP, 4, x, rv);
                as_.mov(8, x, RAX);
                as_.cmov(aop == AT_SMAX ? CL : CG, 4, x, rv);
                as_.pop(rv);
            } else {
                as_.alu(CMP, cs, x, rv);
                Cond cc = aop == AT_SMAX ? CL : aop == AT_SMIN ? CG : aop == AT_UMAX ? CB : CA;
                as_.cmov(cc, cs, x, rv);
            }
            break;
        }
        default: fatal("atomic op");
        }
        as_.cmpxchg(msz, mem(ra, 0), t);
        as_.jcc(CNE, loop);
        if (msz == 1) as_.movzx8(RAX, RAX);
        else if (msz == 2) as_.movzx16(RAX, RAX);
        Reg d = dest_for(v, s);
        if (d != RAX) as_.mov(8, d, RAX);
        finish_def(v, d);
        if (d != RAX) owner_[RAX] = 0;
        return;
    }
    default: fatal("atomic");
    }
}

// Pair atomics: LDXP/STXP (LoadExcl/StoreExcl aux 1/2) and CASP (Cas aux 1/2); element size is
// in.size / 2. The 2x64-bit forms use LOCK CMPXCHG16B, which needs RAX/RBX/RCX/RDX: operands are
// staged in CpuState::vtmp first, and RBX/RCX/RDX/R11 are preserved around the instruction since
// they may hold guest registers (tier 2) or live temps. LDXP loads the halves separately; a torn
// read is caught by STXP, which compares memory against both halves recorded in the monitor.
void T1::emit_pair_atomic(Val v) {
    const Inst& in = I(v);
    const int esz = in.size / 2;
    const int V0 = XEF_ST(vtmp), V1 = V0 + 16, V2 = V0 + 32, V3 = V0 + 48;
    if (in.op == Op::LoadExcl) {
        pin(in.a);
        Reg ra = to_reg(in.a); pinned_ |= 1 << ra;
        Reg d = dest_for(v, esz);
        if (in.aux == 1) {
            record_pc();
            as_.mov(8, d, mem(ra, 0));
            as_.mov(8, mem(R15, XEF_ST(excl_addr)), ra);
            as_.mov(8, mem(R15, XEF_ST(excl_val)), d);
            if (esz == 4) as_.mov(4, d, d);
        } else if (esz == 4) {          // high word comes from the same 64-bit snapshot
            as_.mov(8, d, mem(R15, XEF_ST(excl_val)));
            as_.shift_imm(SHR, 8, d, 32);
        } else {
            record_pc();
            as_.mov(8, d, mem(ra, 8));
            as_.mov(8, mem(R15, XEF_ST(excl_val2)), d);
        }
        finish_def(v, d);
        return;
    }
    if (in.op == Op::Cas && in.aux == 2) {  // high half of the CASP result, left in vtmp by aux 1
        Reg d = dest_for(v, esz);
        as_.mov(esz, d, mem(R15, V3 + esz));
        finish_def(v, d);
        return;
    }
    clobber_flags();
    take_reg(RAX); pinned_ |= 1 << RAX;
    for_operands(in, [&](Val o) { pin(o); });
    auto stage = [&](Val x, int size, int off) { load_into(RAX, x, size); as_.mov(size, mem(R15, off), RAX); };
    stage(in.a, 8, V2);
    bool cas = in.op == Op::Cas;
    if (cas) {
        stage(in.b, esz, V0);
        stage((Val)(in.imm & 0xffff), esz, V0 + esz);
        stage(in.c, esz, V1);
        stage((Val)((in.imm >> 16) & 0xffff), esz, V1 + esz);
    } else {
        stage(in.b, esz, V1);
        stage(in.c, esz, V1 + esz);
    }
    Label fail, done;
    if (!cas) {
        as_.mov(8, RAX, mem(R15, V2));
        as_.alu(CMP, 8, RAX, mem(R15, XEF_ST(excl_addr)));
        as_.jcc(CNE, fail);
    }
    if (esz == 4) {
        as_.push(RCX); as_.push(R11);
        as_.mov(8, RAX, cas ? mem(R15, V0) : mem(R15, XEF_ST(excl_val)));
        as_.mov(8, RCX, mem(R15, V1));
        as_.mov(8, R11, mem(R15, V2));
        record_pc();
        as_.cmpxchg(8, mem(R11, 0), RCX);
        as_.pop(R11); as_.pop(RCX);
        if (cas) as_.mov(8, mem(R15, V3), RAX);
    } else {
        as_.push(RBX); as_.push(RCX); as_.push(RDX); as_.push(R11);
        as_.mov(8, RAX, cas ? mem(R15, V0) : mem(R15, XEF_ST(excl_val)));
        as_.mov(8, RDX, cas ? mem(R15, V0 + 8) : mem(R15, XEF_ST(excl_val2)));
        as_.mov(8, RBX, mem(R15, V1));
        as_.mov(8, RCX, mem(R15, V1 + 8));
        as_.mov(8, R11, mem(R15, V2));
        record_pc();
        as_.cmpxchg16b(mem(R11, 0));
        if (cas) { as_.mov(8, mem(R15, V3), RAX); as_.mov(8, mem(R15, V3 + 8), RDX); }
        as_.pop(R11); as_.pop(RDX); as_.pop(RCX); as_.pop(RBX);
    }
    if (cas) {
        if (esz == 4) as_.mov(4, RAX, RAX);   // old low word
    } else {
        // STXP status: 0 = stored, 1 = failed. POP/MOV keep ZF from the compare-exchange.
        as_.setcc(CNE, RAX);
        as_.movzx8(RAX, RAX);
        as_.jmp(done);
        as_.bind(fail);
        as_.mov_imm(RAX, 1);
        as_.bind(done);
        as_.mov_imm(8, mem(R15, XEF_ST(excl_addr)), -1);
    }
    pinned_ &= ~(1 << RAX);
    assign_reg(v, RAX);
}

void T1::emit_sys(Val v) {
    const Inst& in = I(v);
    if (in.op == Op::SetSys) {
        pin(in.a);
        Reg r = to_reg(in.a); pinned_ |= 1 << r;
        switch (in.aux) {
        case SYS_TPIDR_EL0: as_.mov(8, mem(R15, XEF_ST(tpidr_el0)), r); return;
        case SYS_FPCR: as_.mov(4, mem(R15, XEF_ST(fpcr)), r); return;  // TODO: MXCSR rounding
        case SYS_FPSR: as_.mov(4, mem(R15, XEF_ST(fpsr)), r); return;
        default: fatal("setsys");
        }
    }
    switch (in.aux) {
    case SYS_TPIDR_EL0: { Reg d = dest_for(v, 8); as_.mov(8, d, mem(R15, XEF_ST(tpidr_el0))); finish_def(v, d); return; }
    case SYS_TPIDRRO_EL0: { Reg d = dest_for(v, 8); as_.mov(8, d, mem(R15, XEF_ST(tpidrro_el0))); finish_def(v, d); return; }
    case SYS_FPCR: { Reg d = dest_for(v, 8); as_.mov(4, d, mem(R15, XEF_ST(fpcr))); finish_def(v, d); return; }
    case SYS_FPSR: { Reg d = dest_for(v, 8); as_.mov(4, d, mem(R15, XEF_ST(fpsr))); finish_def(v, d); return; }
    case SYS_DCZID: { Reg d = dest_for(v, 8); as_.mov_imm(d, 4); finish_def(v, d); return; }
    case SYS_CTR: { Reg d = dest_for(v, 8); as_.mov_imm(d, 0x8444c004); finish_def(v, d); return; }
    case SYS_MIDR: { Reg d = dest_for(v, 8); as_.mov_imm(d, 0x410fd0c0); finish_def(v, d); return; }
    case SYS_MPIDR: { Reg d = dest_for(v, 8); as_.mov_imm(d, 0x80000000); finish_def(v, d); return; }
    case SYS_CNTFRQ: { Reg d = dest_for(v, 8); as_.mov_imm(d, 1000000000); finish_def(v, d); return; }
    default:
        emit_call_c((void*)&xef_helper_sysreg, v, 0, 0, in.aux);
        return;
    }
}

// Generic C helper call: u64 fn(u64 a, u64 b, u64 imm). Guest state is kept consistent:
// live temps are spilled, caller-saved mapped registers are saved/restored around the call.
void T1::emit_call_c(void* fn, Val v, Val a, Val b, u64 imm) {
    // load arguments into temps first (they may alias registers we are about to clobber)
    pin(a); pin(b);
    for (int ti_ = 0; ti_ < ntemps_; ti_++) if (Reg r = temps_[ti_]; true) if (owner_[r] && !(pinned_ & (1 << r))) evict(r);
    for (int x = 0; x < 16; x++) if (xowner_[x] && vi_[xowner_[x]].last > cur_) evict_x(x);
    save_caller_saved_guests();
    // arguments: fetch from current locations (registers hold correct values still)
    // move to rcx/r11 staging to avoid clobber conflicts
    if (a) { Opnd o = opnd(a, true, true, 8); emit_mov_opnd(8, RAX, o); as_.push(RAX); }
    if (b) { Opnd o = opnd(b, true, true, 8); emit_mov_opnd(8, RAX, o); as_.push(RAX); }
    if (b) as_.pop(RSI);
    if (a) as_.pop(RDI);
    as_.mov_imm(RDX, imm);
    bool fl = eflags_ != 0 && flags_needed_after(cur_);
    if (fl) { as_.pushfq(); as_.pop(mem(R15, XEF_ST(flags_spill))); spilled_flags_ = eflags_; }
    eflags_ = 0;
    as_.mov_imm(RAX, (u64)fn);
    as_.call(RAX);
    restore_caller_saved_guests();
    for (int ti_ = 0; ti_ < ntemps_; ti_++) if (Reg r = temps_[ti_]; true) owner_[r] = 0;
    if (v) {
        Reg d = alloc_temp(RAX);
        if (d != RAX) as_.mov(8, d, RAX);
        assign_reg(v, d);
    }
}

void T1::emit_terminator(Val v) {
    const Inst& in = I(v);
    // every other value is dead now; release temps not holding the operand
    {
        Val keep = in.a ? resolve(in.a) : 0;
        for (int ti_ = 0; ti_ < ntemps_; ti_++) if (Reg r = temps_[ti_]; true) if (owner_[r] && owner_[r] != keep) owner_[r] = 0;
    }
    // All terminators: guest NZCV must be in EFLAGS.
    auto ensure_flags = [&]() { if (live_out_ && final_flags_ != eflags_) need_flags(final_flags_); };
    switch (in.op) {
    case Op::ExitJump:
        ensure_flags();
        exit_jmp(in.imm);
        return;
    case Op::ExitCond: {
        Val f = fid(in.a);
        // the branch condition must test the guest flags value it references; this is also
        // the final flags value unless something set flags after (impossible: B.cond ends block)
        ensure_flags();
        need_flags(f, in.aux);
        exit_jcc(x86_cond((ir::Cond)in.aux), in.imm);
        exit_jmp(in.imm2);
        return;
    }
    case Op::ExitCbz: {
        // flag-free: mov rcx, v ; jrcxz
        int s = sz(I(in.a).ty);
        take_reg(RCX);
        pinned_ |= 1 << RCX;
        load_into(RCX, in.a, s);
        ensure_flags();
        bool nz = in.aux;
        u8* j = as_.jrcxz_fwd();
        // not zero
        exit_jmp(nz ? in.imm : in.imm2);
        as_.patch_rel8_here(j);
        exit_jmp(nz ? in.imm2 : in.imm);
        return;
    }
    case Op::ExitTbz: {
        int b = in.size;
        bool nz = in.aux;
        take_reg(R11);
        pinned_ |= 1 << R11;
        load_into(R11, in.a, 8);
        Reg r = R11;
        take_reg(RCX);
        take_reg(RAX);
        if (g_host.bmi2) {
            // rcx = (r << (63-b)) >>s 63  (0 or -1), flag-free
            as_.mov_imm(RAX, (u64)(63 - b));
            as_.shlx(8, RCX, r, RAX);
            as_.mov_imm(RAX, 63);
            as_.sarx(8, RCX, RCX, RAX);
            ensure_flags();
        } else {
            ensure_flags();
            as_.pushfq();
            as_.mov(8, RCX, r);
            as_.shift_imm(SHL, 8, RCX, (u8)(63 - b));
            as_.shift_imm(SAR, 8, RCX, 63);
            as_.popfq();
        }
        u8* j = as_.jrcxz_fwd();
        exit_jmp(nz ? in.imm : in.imm2);   // bit set
        as_.patch_rel8_here(j);
        exit_jmp(nz ? in.imm2 : in.imm);   // bit clear
        return;
    }
    case Op::ExitIndirect: {
        take_reg(RAX);
        load_into(RAX, in.a, 8);
        ensure_flags();
        emit_ibtc_probe();
        return;
    }
    case Op::ExitCall: {
        ensure_flags();
        // native return-stack: push guest return address, call target
        as_.mov_imm(RAX, in.imm2);
        as_.push(RAX);
        exit_call(in.imm);
        // landing pad (reached by RET with matching guest address)
        as_.lea(8, RSP, mem(RSP, 8));
        exit_jmp(in.imm2);
        return;
    }
    case Op::ExitCallIndirect: {
        take_reg(RAX);
        load_into(RAX, in.a, 8);
        ensure_flags();
        as_.mov_imm(RCX, in.imm2);
        as_.push(RCX);
        Label probe;
        as_.call(probe);
        as_.lea(8, RSP, mem(RSP, 8));
        exit_jmp(in.imm2);
        as_.bind(probe);
        emit_ibtc_probe();
        return;
    }
    case Op::ExitRet: {
        take_reg(RAX);
        load_into(RAX, in.a, 8);
        ensure_flags();
        // compare guest return address on the native stack with target (flag-free)
        as_.mov(8, RCX, mem(RSP, 8));
        as_.not_(8, RCX);
        as_.lea(8, RCX, mem(RCX, RAX, 0, 1));
        u8* j = as_.jrcxz_fwd();
        // mismatch: reset the return stack, go through the IBTC
        as_.mov(8, RSP, mem(R15, XEF_ST(jit_stack_top)));
        emit_ibtc_probe();
        as_.patch_rel8_here(j);
        as_.ret();
        return;
    }
    case Op::ExitSyscall:
        ensure_flags();
        exit_to_runtime(EXIT_SYSCALL, in.imm, in.imm2, true);
        return;
    case Op::ExitUndef:
        ensure_flags();
        exit_to_runtime(EXIT_UNDEF, in.imm, in.imm2, true);
        return;
    case Op::ExitBrk:
        ensure_flags();
        exit_to_runtime(EXIT_BRK, in.imm, in.imm2, true);
        return;
    default: fatal("terminator");
    }
}

}  // namespace t1

void emit_region_xfer(Assembler& as, const RegionXfer* x, int n, bool enter) {
    for (int i = 0; i < n; i++) {
        const RegionXfer& r = x[i];
        int from = enter ? r.g_canon : r.g_region, to = enter ? r.g_region : r.g_canon;
        if (from >= 0 && (enter || r.written)) as.mov(8, mem(R15, st_x(from)), r.h);
        if (to >= 0) as.mov(8, r.h, mem(R15, st_x(to)));
    }
}

bool emit_tier1(const Block& b, Assembler& as, BlockMeta* meta, CodegenOut& out, const CodegenCtx* ctx) {
    using t1::T1;
    static thread_local T1* t = nullptr;
    // T1 is large (per-value table); allocate once per thread
    alignas(T1) static thread_local u8 storage[sizeof(T1)];
    t = new (storage) T1(b, as, meta, out, ctx);
    as.avx = g_host.avx;
    bool ok = t->run();
    out.size = as.size();
    t->~T1();
    return ok;
}

}  // namespace xef::backend
