// XEF — tier-1 code generator internals (shared by codegen_t1*.cpp).
#pragma once
#include <cstddef>

#include "backend/x64/codegen.h"
#include "common/cpu_features.h"
#include "runtime/cpu_state.h"

namespace xef::backend {

using namespace x64;
using namespace ir;
using regmap::host;
using regmap::mapped;
using x64::Cond;

Cond x86_cond(ir::Cond c);

namespace t1 {

enum LocKind : u8 { L_NONE, L_REG, L_GREG, L_GMEM, L_CONST, L_SPILL, L_ALIAS, L_XMM, L_VMEM, L_VSPILL };

struct VI {
    LocKind k = L_NONE;
    u8 reg = 0;        // host reg (L_REG / L_GREG) or xmm
    u8 g = 0;          // guest reg index for L_GREG / L_GMEM
    i8 home = -1;      // guest reg whose current value equals this value
    i8 slot = -1;      // spill slot
    i8 vhome = -1;     // vector register whose CpuState slot holds this value
    bool dead = false;
    bool folded = false;
    bool clean32 = false;
    u16 uses = 0;
    i32 last = 0;
};

constexpr Val kEntryFlags = 0xFFFF;

struct Opnd {
    enum K : u8 { R, M, I } k;
    Reg r;
    Mem m;
    i64 imm;
};

class T1 {
public:
    T1(const Block& b, Assembler& as, BlockMeta* meta, CodegenOut& out) : b_(b), as_(as), meta_(meta), out_(out) {}
    bool run();

private:
    const Block& b_;
    Assembler& as_;
    BlockMeta* meta_;
    CodegenOut& out_;
    VI vi_[kMaxBlockInsts];
    Val owner_[16] = {};        // owned temp regs: which value holds it
    Val xowner_[16] = {};
    u16 pinned_ = 0;            // host regs that must not be evicted in current inst
    u16 xpinned_ = 0;
    int cur_ = 0;
    Val eflags_ = kEntryFlags;  // flags value currently in EFLAGS (0 = garbage)
    Val spilled_flags_ = 0;
    Val final_flags_ = kEntryFlags;
    i32 entry_flags_last_ = 0;
    u32 spill_used_ = 0;
    int nexits_ = 0;
    struct PendingStub { ExitInfo* e; };
    PendingStub stubs_[512];
    int nstubs_ = 0;
    struct ColdIbtc { Label l; };
    HostPcEntry pcmap_[1024];
    int npc_ = 0;
    u32 vspill_used_ = 0;
    struct ConstFix { u64 lo, hi; u8* field; };
    ConstFix consts_[256];
    int nconsts_ = 0;

    static constexpr Reg kTemps[3] = {RAX, RCX, R11};

    const Inst& I(Val v) const { return b_.insts[v]; }
    static int sz(Type t) { return t == Type::I32 ? 4 : 8; }
    Val fid(Val v) const { return (v && v != kEntryFlags && I(v).op == Op::GetFlags) ? kEntryFlags : v; }

    // ---- analysis ----
    template <typename F>
    void for_operands(const Inst& in, F f) {
        if (in.a) f(in.a);
        if (in.b) f(in.b);
        if (in.c) f(in.c);
        if (in.op == Op::Cas && in.aux == 1) { f((Val)(in.imm & 0xffff)); f((Val)((in.imm >> 16) & 0xffff)); }
    }
    bool has_side_effects(const Inst& in) const {
        switch (in.op) {
        case Op::SetReg: case Op::SetFlags: case Op::Store: case Op::Load:
        case Op::LoadExcl: case Op::StoreExcl: case Op::ClearExcl: case Op::AtomicRMW: case Op::Cas:
        case Op::Barrier: case Op::SetSys: case Op::Helper: case Op::VSet: case Op::VStore: case Op::VLoad:
        case Op::UDiv: case Op::SDiv:  // keep (cheap to keep, safe)
            return true;
        default: return is_terminator(in.op);
        }
    }
    bool is_alias_op(const Inst& in) const {
        if (in.op == Op::GetFlags) return true;
        if (in.op == Op::Zext && in.size == 32 && in.ty == Type::I32) return true;   // trunc view
        if (in.op == Op::Zext && in.size == 32 && in.ty == Type::I64 && vi_[in.a].clean32) return true;
        return false;
    }
    void analyze();

    // ---- locations ----
    bool flags_needed_after(int i) const {
        if (!eflags_) return false;
        if (eflags_ == final_flags_) return true;
        if (eflags_ == kEntryFlags) return entry_flags_last_ > i;
        return vi_[eflags_].last > i;
    }
    void clobber_flags() {
        if (flags_needed_after(cur_)) {
            as_.pushfq();
            as_.pop(mem(R15, XEF_ST(flags_spill)));
            spilled_flags_ = eflags_;
        }
        eflags_ = 0;
    }
    void need_flags(Val f) {
        f = fid(f);
        if (eflags_ == f) return;
        XEF_ASSERT(spilled_flags_ == f);
        as_.push(mem(R15, XEF_ST(flags_spill)));
        as_.popfq();
        eflags_ = f;
    }
    Val resolve(Val v) const {
        while (vi_[v].k == L_ALIAS) v = I(v).a;
        return v;
    }
    Mem gmem(int g) const { return mem(R15, st_x(g)); }
    Reg alloc_temp(Reg prefer = NOREG);
    void free_reg(Reg r) { owner_[r] = 0; }
    void evict(Reg r);
    void take_reg(Reg r) { if (owner_[r]) evict(r); }
    void assign_reg(Val v, Reg r) {
        vi_[v].k = L_REG;
        vi_[v].reg = r;
        owner_[r] = v;
    }
    Opnd opnd(Val v, bool allow_mem, bool allow_imm, int size);
    Reg to_reg(Val v, int size = 8);
    Reg to_reg_copy(Val v, Reg dst, int size);
    void load_into(Reg dst, Val v, int size);
    void pin(Val v) { v = resolve(v); if (vi_[v].k == L_REG || vi_[v].k == L_GREG) pinned_ |= 1 << vi_[v].reg; }
    void release_operands(const Inst& in);
    void evacuate_guest(int g, int upto);
    Reg dest_for(Val v, int size);
    Reg dest_hint(Val v);
    void finish_def(Val v, Reg r);
    bool is_c(Val v) const { return I(resolve(v)).op == Op::Const; }
    u64 cv(Val v) const { return I(resolve(v)).imm; }
    bool fits_i32(Val v, int size) const {
        if (!is_c(v)) return false;
        u64 x = cv(v);
        return size == 4 ? true : ((i64)x == (i32)x);
    }

    // ---- emit helpers ----
    void emit_mov_opnd(int size, Reg dst, const Opnd& o) {
        if (o.k == Opnd::R) { if (o.r != dst || size == 4) as_.mov(size, dst, o.r); }
        else if (o.k == Opnd::M) as_.mov(size, dst, o.m);
        else as_.mov_imm(dst, size == 4 ? (u64)(u32)o.imm : (u64)o.imm);
    }
    void emit_alu(AluOp op, int size, Reg dst, const Opnd& o) {
        if (o.k == Opnd::R) as_.alu(op, size, dst, o.r);
        else if (o.k == Opnd::M) as_.alu(op, size, dst, o.m);
        else as_.alu_imm(op, size, dst, (i32)o.imm);
    }
    Mem addr_mem(Val a);
    void emit_inst(Val v);
    void emit_binop(Val v);
    void emit_shift(Val v);
    void emit_load(Val v);
    void emit_store(Val v);
    void emit_flags(Val v, bool fused_with_result, Reg result_reg);
    void emit_select(Val v);
    void emit_ccmp(Val v);
    void emit_set_const_flags(u32 nzcv);
    void emit_div(Val v);
    void emit_mulh(Val v);
    void emit_misc_unary(Val v);
    void emit_ext(Val v);
    void emit_adc_sbc(Val v, bool with_flags_val, Val flags_v);
    void emit_atomic(Val v);
    void emit_sys(Val v);
    void emit_vec(Val v);
    // vector helpers (codegen_t1_vec.cpp)
    Xmm alloc_x();
    void evict_x(int x);
    Xmm xreg(Val v);
    void xpin(Val v) { v = resolve(v); if (vi_[v].k == L_XMM) xpinned_ |= 1 << vi_[v].reg; }
    void evacuate_vreg(int r, int upto);
    Xmm new_x(Val v) { Xmm x = alloc_x(); vi_[v].k = L_XMM; vi_[v].reg = x; xowner_[x] = v; xpinned_ |= 1 << x; return x; }
    void emit_vop(Val v);
    void emit_vec_helper(Val v);
    void load_vconst(Xmm x, u64 lo, u64 hi);
    Mem vconst_mem(u64 lo, u64 hi);
    void emit_fcmp(Val v);
    void emit_fccmp(Val v);
    void emit_ftoi(Val v);
    void emit_itof(Val v);
    void emit_fcmp_seq(Val a, Val b, int fs, bool signaling);
    void call_prepare(Val a, Val b, Val c);
    void zero_upper(Xmm x, int bytes);
    void emit_const_pool();
    void emit_terminator(Val v);
    void emit_call_c(void* fn, Val v, Val a, Val b, u64 imm);

    // exits
    ExitInfo* new_exit(u8 kind, GuestAddr target) {
        XEF_ASSERT(nexits_ < meta_->nexits);
        ExitInfo* e = &meta_->exits[nexits_++];
        e->kind = kind;
        e->target = target;
        e->owner = meta_;
        e->linked = 0;
        e->next_in = nullptr;
        stubs_[nstubs_++].e = e;
        return e;
    }
    void exit_jmp(GuestAddr target) {
        as_.align_field(1, 4);
        ExitInfo* e = new_exit(EK_JMP, target);
        as_.db(0xE9);
        e->site = as_.cur();
        as_.dd(0);
    }
    void exit_jcc(Cond c, GuestAddr target) {
        as_.align_field(2, 4);
        ExitInfo* e = new_exit(EK_JCC, target);
        as_.db(0x0F); as_.db((u8)(0x80 | c));
        e->site = as_.cur();
        as_.dd(0);
    }
    void exit_call(GuestAddr target) {
        as_.align_field(1, 4);
        ExitInfo* e = new_exit(EK_CALL, target);
        as_.db(0xE8);
        e->site = as_.cur();
        as_.dd(0);
    }
    void exit_to_runtime(u32 reason, GuestAddr pc, u64 info, bool have_info) {
        as_.mov_imm(RAX, pc);
        as_.mov(8, mem(R15, XEF_ST(pc)), RAX);
        if (have_info) {
            as_.mov_imm(RAX, info);
            as_.mov(8, mem(R15, XEF_ST(exit_info)), RAX);
        }
        as_.mov_imm(8, mem(R15, XEF_ST(exit_reason)), (i32)reason);
        as_.jmp_rel32(g_cache.stubs.exit_to_runtime);
    }
    // inline IBTC probe on RAX (guest target); flag-free
    void emit_ibtc_probe() {
        as_.movzx16(RCX, RAX);
        as_.mov(8, R11, mem(R15, XEF_ST(ibtc)));
        as_.lea(8, R11, mem(R11, RCX, 2, 0));      // r11 = &table[(pc>>2) & 16383] (16-byte entries)
        as_.mov(8, RCX, mem(R11));
        as_.not_(8, RCX);
        as_.lea(8, RCX, mem(RCX, RAX, 0, 1));
        u8* j = as_.jrcxz_fwd();
        as_.jmp_rel32(g_cache.stubs.ibtc_miss);
        as_.patch_rel8_here(j);
        as_.jmp(mem(R11, 8));
    }
    void record_pc() {
        if (npc_ < 1024) {
            pcmap_[npc_].host_off = (u32)as_.offset();
            pcmap_[npc_].guest_off = b_.pc_off[cur_];
            npc_++;
        }
    }
};


}  // namespace t1
}  // namespace xef::backend
