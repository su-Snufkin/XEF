// XEF — IR builder with cheap on-the-fly simplification (constant folding,
// identity removal, guest-register forwarding inside the block).
#pragma once
#include "ir/ir.h"

namespace xef::ir {

class Builder {
public:
    explicit Builder(Block& b) : b_(b) { reset_tracking(); }

    Block& block() { return b_; }
    void set_pc_off(u32 off) { pc_off_ = off; }
    void reset_tracking() {
        for (auto& r : reg_) r = kNone;
        for (auto& r : vreg_) r = kNone;
        flags_ = kNone;
        const_count_ = 0;
    }

    Val emit(Op op, Type ty, Val a = kNone, Val b = kNone, Val c = kNone, u64 imm = 0, u8 aux = 0, u8 size = 0) {
        XEF_ASSERT(b_.n < kMaxBlockInsts - 8);
        Val v = (Val)b_.n++;
        Inst& i = b_.insts[v];
        i.op = op; i.ty = ty; i.a = a; i.b = b; i.c = c; i.imm = imm; i.imm2 = 0;
        i.aux = aux; i.size = size; i.sub = 0;
        b_.pc_off[v] = pc_off_;
        return v;
    }
    Inst& inst(Val v) { return b_.insts[v]; }
    bool is_const(Val v) const { return b_.insts[v].op == Op::Const; }
    u64 cval(Val v) const { return b_.insts[v].imm; }

    static u64 mask(Type t) { return t == Type::I32 ? 0xffffffffull : ~0ull; }

    Val cnst(Type ty, u64 imm) {
        imm &= mask(ty);
        // small dedup window
        for (int i = 0; i < const_count_; i++) {
            Inst& c = b_.insts[consts_[i]];
            if (c.imm == imm && c.ty == ty) return consts_[i];
        }
        Val v = emit(Op::Const, ty, kNone, kNone, kNone, imm);
        if (const_count_ < 8) consts_[const_count_++] = v;
        else { consts_[const_slot_] = v; const_slot_ = (const_slot_ + 1) & 7; }
        return v;
    }
    Val c64(u64 v) { return cnst(Type::I64, v); }
    Val c32(u64 v) { return cnst(Type::I32, v); }

    // ---- guest state ----
    Val get_reg(int r, Type ty) {
        Val v = reg_[r];
        if (v == kNone) {
            v = emit(Op::GetReg, Type::I64, kNone, kNone, kNone, 0, (u8)r);
            reg_[r] = v;
        }
        if (ty == Type::I32) return trunc32(v);
        return v;
    }
    void set_reg(int r, Val v) {
        // 32-bit values are implicitly zero-extended into the 64-bit register
        Val v64 = v;
        if (b_.insts[v].ty == Type::I32) v64 = zext32to64(v);
        emit(Op::SetReg, Type::None, v64, kNone, kNone, 0, (u8)r);
        reg_[r] = v64;
    }
    Val vget(int r) {
        Val v = vreg_[r];
        if (v == kNone) {
            v = emit(Op::VGet, Type::V128, kNone, kNone, kNone, 0, (u8)r);
            vreg_[r] = v;
        }
        return v;
    }
    void vset(int r, Val v) {
        emit(Op::VSet, Type::None, v, kNone, kNone, 0, (u8)r);
        vreg_[r] = v;
    }
    Val get_flags() {
        if (flags_ == kNone) flags_ = emit(Op::GetFlags, Type::Flags);
        return flags_;
    }
    void set_flags(Val f) {
        emit(Op::SetFlags, Type::None, f);
        flags_ = f;
    }

    // Value of a 32-bit view: I32 typed alias. 64->32 truncation is a no-op
    // on x86 when consumers use 32-bit operations, so we represent it as Zext(32) typed I32.
    Val trunc32(Val v) {
        Inst& i = b_.insts[v];
        if (i.ty == Type::I32) return v;
        if (i.op == Op::Const) return c32(i.imm);
        if (i.op == Op::Zext && i.size == 32) { Val s = i.a; if (b_.insts[s].ty == Type::I32) return s; }
        return emit(Op::Zext, Type::I32, v, kNone, kNone, 0, 0, 32);
    }
    Val zext32to64(Val v) {
        Inst& i = b_.insts[v];
        if (i.op == Op::Const) return c64(i.imm & 0xffffffffull);
        return emit(Op::Zext, Type::I64, v, kNone, kNone, 0, 0, 32);
    }

    // ---- arithmetic with folding ----
    Val binop(Op op, Type ty, Val a, Val b) {
        if (is_const(a) && is_const(b)) {
            u64 x = cval(a), y = cval(b), m = mask(ty);
            int sz = ty == Type::I32 ? 32 : 64;
            switch (op) {
            case Op::Add: return cnst(ty, x + y);
            case Op::Sub: return cnst(ty, x - y);
            case Op::And: return cnst(ty, x & y);
            case Op::Or: return cnst(ty, x | y);
            case Op::Xor: return cnst(ty, x ^ y);
            case Op::AndNot: return cnst(ty, x & ~y);
            case Op::OrNot: return cnst(ty, x | (~y & m));
            case Op::XorNot: return cnst(ty, x ^ (~y & m));
            case Op::Shl: return cnst(ty, x << (y & (sz - 1)));
            case Op::Lshr: return cnst(ty, (x & m) >> (y & (sz - 1)));
            case Op::Ashr: return cnst(ty, (u64)(sext(x & m, sz) >> (y & (sz - 1))));
            case Op::Mul: return cnst(ty, x * y);
            default: break;
            }
        }
        if (is_const(b)) {
            u64 y = cval(b);
            switch (op) {
            case Op::Add: case Op::Sub: case Op::Or: case Op::Xor:
            case Op::Shl: case Op::Lshr: case Op::Ashr: case Op::Ror:
                if (y == 0) return a;
                break;
            case Op::And:
                if (y == mask(ty)) return a;
                if (y == 0) return b;
                break;
            default: break;
            }
        }
        if (is_const(a)) {
            u64 x = cval(a);
            switch (op) {
            case Op::Add: case Op::Or: case Op::Xor:
                if (x == 0) return b;
                break;
            case Op::And:
                if (x == 0) return a;
                break;
            default: break;
            }
        }
        return emit(op, ty, a, b);
    }
    Val add(Type t, Val a, Val b) { return binop(Op::Add, t, a, b); }
    Val sub(Type t, Val a, Val b) { return binop(Op::Sub, t, a, b); }
    Val and_(Type t, Val a, Val b) { return binop(Op::And, t, a, b); }
    Val or_(Type t, Val a, Val b) { return binop(Op::Or, t, a, b); }
    Val xor_(Type t, Val a, Val b) { return binop(Op::Xor, t, a, b); }
    Val shl(Type t, Val a, Val b) { return binop(Op::Shl, t, a, b); }
    Val lshr(Type t, Val a, Val b) { return binop(Op::Lshr, t, a, b); }
    Val ashr(Type t, Val a, Val b) { return binop(Op::Ashr, t, a, b); }
    Val ror(Type t, Val a, Val b) { return binop(Op::Ror, t, a, b); }
    Val unop(Op op, Type t, Val a) {
        if (is_const(a)) {
            u64 x = cval(a);
            if (op == Op::Not) return cnst(t, ~x);
            if (op == Op::Neg) return cnst(t, -x);
        }
        return emit(op, t, a);
    }
    Val sext_from(Type t, Val a, int bits) {
        if (is_const(a)) return cnst(t, (u64)sext(cval(a), bits));
        if (bits >= (t == Type::I32 ? 32 : 64)) return a;
        return emit(Op::Sext, t, a, kNone, kNone, 0, 0, (u8)bits);
    }
    Val zext_from(Type t, Val a, int bits) {
        if (is_const(a)) return cnst(t, bits >= 64 ? cval(a) : cval(a) & ((1ull << bits) - 1));
        if (bits >= (t == Type::I32 ? 32 : 64)) return a;
        return emit(Op::Zext, t, a, kNone, kNone, 0, 0, (u8)bits);
    }
    Val select(Type t, Cond c, Val flags, Val tv, Val fv) {
        if (c == AL || c == NV) return tv;
        if (tv == fv) return tv;
        return emit(Op::Select, t, flags, tv, fv, 0, (u8)c);
    }
    Val load(Type t, Val addr, int size, bool sign) {
        return emit(Op::Load, t, addr, kNone, kNone, 0, sign ? 1 : 0, (u8)size);
    }
    void store(Val addr, Val v, int size) { emit(Op::Store, Type::None, addr, v, kNone, 0, 0, (u8)size); }

private:
    Block& b_;
    u32 pc_off_ = 0;
    Val reg_[32];
    Val vreg_[32];
    Val flags_ = kNone;
    Val consts_[8];
    int const_count_ = 0, const_slot_ = 0;
};

}  // namespace xef::ir
