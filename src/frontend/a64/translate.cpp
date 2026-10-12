// XEF — AArch64 base (integer / branch / load-store / system) translation.
#include "frontend/a64/translate.h"

#include <sys/mman.h>

namespace xef::a64 {

using namespace ir;

static inline Type T(bool sf) { return sf ? Type::I64 : Type::I32; }

bool decode_bit_masks(u32 n, u32 imms, u32 immr, bool immediate, int datasize, u64* wmask) {
    u32 combined = (n << 6) | (~imms & 0x3f);
    if (combined == 0) return false;
    int len = 31 - __builtin_clz(combined);
    if (len < 1) return false;
    u32 levels = (1u << len) - 1;
    if (immediate && (imms & levels) == levels) return false;
    u32 s = imms & levels, r = immr & levels;
    int esize = 1 << len;
    if (esize > datasize) return false;
    u64 welem = (s + 1 == 64) ? ~0ull : ((1ull << (s + 1)) - 1);
    u64 emask = esize == 64 ? ~0ull : ((1ull << esize) - 1);
    // rotate right within esize
    u64 rot = r ? (((welem >> r) | (welem << (esize - r))) & emask) : welem;
    u64 res = 0;
    for (int i = 0; i < datasize; i += esize) res |= rot << i;
    if (datasize == 32) res &= 0xffffffffull;
    *wmask = res;
    return true;
}

void Translator::undef(GuestAddr pc, u32 insn) {
    Val v = ir_.emit(Op::ExitUndef, Type::None, kNone, kNone, kNone, pc);
    ir_.inst(v).imm2 = insn;
    ended_ = true;
}

bool Translator::step(GuestAddr pc, u32 i) {
    pc_ = pc;
    ended_ = false;
    ir_.set_pc_off((u32)(pc - b_.start));
    u32 op0 = bits(i, 28, 25);
    bool ok;
    switch (op0) {
    case 0x8: case 0x9: ok = dp_imm(i); break;
    case 0xA: case 0xB: ok = branch_sys(i); break;
    case 0x4: case 0x6: case 0xC: case 0xE: ok = ldst(i); break;
    case 0x5: case 0xD: ok = dp_reg(i); break;
    case 0x7: case 0xF: ok = simd_fp(i); break;
    default: ok = false; break;
    }
    if (!ok) undef(pc, i);
    return !ended_;
}

// ---------------------------------------------------------------- operands

Val Translator::shift_reg(Type t, Val v, int type, int amount) {
    if (amount == 0) return v;
    Val a = ir_.cnst(t, amount);
    switch (type) {
    case 0: return ir_.shl(t, v, a);
    case 1: return ir_.lshr(t, v, a);
    case 2: return ir_.ashr(t, v, a);
    default: return ir_.ror(t, v, a);
    }
}

Val Translator::extend_reg(Type t, Val v, int option, int shift) {
    // v is the 64-bit (or 32-bit) register value; extend then shift
    Val r;
    switch (option) {
    case 0: r = ir_.zext_from(t, v, 8); break;
    case 1: r = ir_.zext_from(t, v, 16); break;
    case 2: r = ir_.zext_from(t, v, 32); break;
    case 3: r = v; break;
    case 4: r = ir_.sext_from(t, v, 8); break;
    case 5: r = ir_.sext_from(t, v, 16); break;
    case 6: r = ir_.sext_from(t, v, 32); break;
    default: r = v; break;
    }
    if (shift) r = ir_.shl(t, r, ir_.cnst(t, shift));
    return r;
}

// ---------------------------------------------------------------- DP imm

bool Translator::dp_imm(u32 i) {
    u32 op = bits(i, 25, 23);
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5);
    bool sf = bit(i, 31);
    Type t = T(sf);
    switch (op) {
    case 0: case 1: {  // ADR / ADRP
        i64 imm = sext((bits(i, 23, 5) << 2) | bits(i, 30, 29), 21);
        u64 v = bit(i, 31) ? ((pc_ & ~0xfffull) + (imm << 12)) : (pc_ + imm);
        setX(rd, ir_.c64(v));
        return true;
    }
    case 2: {  // add/sub immediate
        bool sub = bit(i, 30), s = bit(i, 29);
        u64 imm = bits(i, 21, 10);
        if (bit(i, 22)) imm <<= 12;
        Val a = XSP(rn, t);
        Val b = ir_.cnst(t, imm);
        Val r = sub ? ir_.sub(t, a, b) : ir_.add(t, a, b);
        if (s) {
            Val f = ir_.emit(sub ? Op::FlagsSub : Op::FlagsAdd, Type::Flags, a, b);
            ir_.inst(f).size = sf ? 64 : 32;
            ir_.set_flags(f);
            setX(rd, r);
        } else {
            setXSP(rd, r);
        }
        return true;
    }
    case 4: {  // logical immediate
        u32 opc = bits(i, 30, 29);
        u64 imm;
        if (!sf && bit(i, 22)) return false;
        if (!decode_bit_masks(bit(i, 22), bits(i, 15, 10), bits(i, 21, 16), true, sf ? 64 : 32, &imm)) return false;
        Val a = X(rn, t), b = ir_.cnst(t, imm), r;
        switch (opc) {
        case 0: r = ir_.and_(t, a, b); setXSP(rd, r); break;
        case 1: r = ir_.or_(t, a, b); setXSP(rd, r); break;
        case 2: r = ir_.xor_(t, a, b); setXSP(rd, r); break;
        default: {
            r = ir_.and_(t, a, b);
            Val f = ir_.emit(Op::FlagsLogic, Type::Flags, r);
            ir_.inst(f).size = sf ? 64 : 32;
            ir_.set_flags(f);
            setX(rd, r);
            break;
        }
        }
        return true;
    }
    case 5: {  // move wide
        u32 opc = bits(i, 30, 29), hw = bits(i, 22, 21);
        if (!sf && hw >= 2) return false;
        u64 imm = (u64)bits(i, 20, 5) << (hw * 16);
        if (opc == 0) setX(rd, ir_.cnst(t, ~imm));
        else if (opc == 2) setX(rd, ir_.cnst(t, imm));
        else if (opc == 3) {
            Val old = X(rd, t);
            Val r = ir_.or_(t, ir_.and_(t, old, ir_.cnst(t, ~(0xffffull << (hw * 16)))), ir_.cnst(t, imm));
            setX(rd, r);
        } else return false;
        return true;
    }
    case 6: {  // bitfield
        u32 opc = bits(i, 30, 29);
        if (bit(i, 22) != sf) return false;
        int ds = sf ? 64 : 32;
        int immr = bits(i, 21, 16), imms = bits(i, 15, 10);
        if (!sf && (immr >= 32 || imms >= 32)) return false;
        Val src = X(rn, t);
        auto ones = [&](int w) -> u64 { return w >= 64 ? ~0ull : ((1ull << w) - 1); };
        Val r;
        if (opc == 2) {  // UBFM
            if (imms >= immr) {
                int w = imms - immr + 1;
                r = ir_.lshr(t, src, ir_.cnst(t, immr));
                if (immr + w < ds) r = ir_.and_(t, r, ir_.cnst(t, ones(w)));
                if (w == 8 || w == 16 || w == 32) {
                    // canonical zext pattern when immr == 0
                    if (immr == 0) r = ir_.zext_from(t, src, w);
                }
            } else {
                int w = imms + 1, sh = ds - immr;
                if (w + sh >= ds) r = ir_.shl(t, src, ir_.cnst(t, sh));  // LSL
                else r = ir_.shl(t, ir_.zext_from(t, src, w), ir_.cnst(t, sh));
            }
        } else if (opc == 0) {  // SBFM
            if (imms >= immr) {
                int w = imms - immr + 1;
                if (immr == 0) r = ir_.sext_from(t, src, w);
                else if (imms == ds - 1) r = ir_.ashr(t, src, ir_.cnst(t, immr));  // ASR
                else {
                    r = ir_.shl(t, src, ir_.cnst(t, ds - 1 - imms));
                    r = ir_.ashr(t, r, ir_.cnst(t, ds - w));
                }
            } else {
                int w = imms + 1, sh = ds - immr;
                r = ir_.shl(t, ir_.sext_from(t, src, w), ir_.cnst(t, sh));
            }
        } else if (opc == 1) {  // BFM
            Val dst = X(rd, t);
            int w, lsb;
            Val field;
            if (imms >= immr) {  // BFXIL
                w = imms - immr + 1; lsb = 0;
                field = ir_.lshr(t, src, ir_.cnst(t, immr));
            } else {  // BFI
                w = imms + 1; lsb = ds - immr;
                field = ir_.shl(t, src, ir_.cnst(t, lsb));
            }
            u64 m = ones(w) << lsb;
            if (ds == 32) m &= 0xffffffffull;
            Val keep = ir_.and_(t, dst, ir_.cnst(t, ~m));
            Val ins = ir_.and_(t, field, ir_.cnst(t, m));
            r = ir_.or_(t, keep, ins);
        } else return false;
        setX(rd, r);
        return true;
    }
    case 7: {  // EXTR
        if (bits(i, 30, 29) != 0 || bit(i, 22) != sf || bit(i, 21)) return false;
        int rm = bits(i, 20, 16), lsb = bits(i, 15, 10);
        int ds = sf ? 64 : 32;
        if (lsb >= ds) return false;
        Val r;
        if (rn == rm) r = ir_.ror(t, X(rn, t), ir_.cnst(t, lsb));
        else if (lsb == 0) r = X(rm, t);
        else r = ir_.or_(t, ir_.lshr(t, X(rm, t), ir_.cnst(t, lsb)), ir_.shl(t, X(rn, t), ir_.cnst(t, ds - lsb)));
        setX(rd, r);
        return true;
    }
    default: return false;
    }
}

// ---------------------------------------------------------------- branches / system

bool Translator::branch_sys(u32 i) {
    GuestAddr pc = pc_;
    if (bits(i, 30, 26) == 0x05) {  // B / BL
        u64 target = pc + (sext(bits(i, 25, 0), 26) << 2);
        if (bit(i, 31)) {
            setX(30, ir_.c64(pc + 4));
            Val v = ir_.emit(Op::ExitCall, Type::None, kNone, kNone, kNone, target);
            ir_.inst(v).imm2 = pc + 4;
        } else {
            ir_.emit(Op::ExitJump, Type::None, kNone, kNone, kNone, target);
        }
        ended_ = true;
        return true;
    }
    if (bits(i, 30, 25) == 0x1A) {  // CBZ/CBNZ
        bool sf = bit(i, 31);
        u64 target = pc + (sext(bits(i, 23, 5), 19) << 2);
        Val v = ir_.emit(Op::ExitCbz, Type::None, X(bits(i, 4, 0), T(sf)), kNone, kNone, target, bit(i, 24));
        ir_.inst(v).imm2 = pc + 4;
        ended_ = true;
        return true;
    }
    if (bits(i, 30, 25) == 0x1B) {  // TBZ/TBNZ
        int b = (bit(i, 31) << 5) | bits(i, 23, 19);
        u64 target = pc + (sext(bits(i, 18, 5), 14) << 2);
        Val v = ir_.emit(Op::ExitTbz, Type::None, X(bits(i, 4, 0), b >= 32 ? Type::I64 : Type::I64), kNone, kNone,
                         target, bit(i, 24), (u8)b);
        ir_.inst(v).imm2 = pc + 4;
        ended_ = true;
        return true;
    }
    if (bits(i, 31, 24) == 0x54) {  // B.cond / BC.cond
        u64 target = pc + (sext(bits(i, 23, 5), 19) << 2);
        Cond c = (Cond)bits(i, 3, 0);
        if (c == AL || c == NV) {
            ir_.emit(Op::ExitJump, Type::None, kNone, kNone, kNone, target);
        } else {
            Val v = ir_.emit(Op::ExitCond, Type::None, ir_.get_flags(), kNone, kNone, target, (u8)c);
            ir_.inst(v).imm2 = pc + 4;
        }
        ended_ = true;
        return true;
    }
    if (bits(i, 31, 24) == 0xD4) {  // exception generation
        u32 opc = bits(i, 23, 21), ll = bits(i, 1, 0);
        u32 imm16 = bits(i, 20, 5);
        if (opc == 0 && ll == 1) {  // SVC
            Val v = ir_.emit(Op::ExitSyscall, Type::None, kNone, kNone, kNone, pc + 4);
            ir_.inst(v).imm2 = imm16;
            ended_ = true;
            return true;
        }
        if (opc == 1 && ll == 0) {  // BRK
            Val v = ir_.emit(Op::ExitBrk, Type::None, kNone, kNone, kNone, pc);
            ir_.inst(v).imm2 = imm16;
            ended_ = true;
            return true;
        }
        if (opc == 2 && ll == 0 && imm16 == 0x5846) {  // HLT #0x5846: host library thunk (thunks.h)
            Val v = ir_.emit(Op::ExitSyscall, Type::None, kNone, kNone, kNone, pc + 4);
            ir_.inst(v).imm2 = 0x10000 | imm16;
            ended_ = true;
            return true;
        }
        if (opc == 2 && ll == 0) {  // HLT
            Val v = ir_.emit(Op::ExitBrk, Type::None, kNone, kNone, kNone, pc);
            ir_.inst(v).imm2 = 0x10000 | imm16;
            ended_ = true;
            return true;
        }
        return false;
    }
    if (bits(i, 31, 22) == 0x354) return system(i);
    if (bits(i, 31, 25) == 0x6B) {  // unconditional branch (register)
        u32 opc = bits(i, 24, 21), op2 = bits(i, 20, 16), op3 = bits(i, 15, 10), rn = bits(i, 9, 5), op4 = bits(i, 4, 0);
        if (op2 != 0x1f) return false;
        // PAC variants (BRAA, BLRAA, RETAA, ...) are treated as their plain forms
        // because we advertise no PAuth and pointers are never signed.
        bool pac = (op3 & 0x3e) == 0x02;
        if (op3 != 0 && !pac) return false;
        if (!pac && op4 != 0 && opc != 2) return false;
        switch (opc) {
        case 0: case 8: {  // BR / BRAA(Z)
            ir_.emit(Op::ExitIndirect, Type::None, X(rn, Type::I64));
            break;
        }
        case 1: case 9: {  // BLR
            Val tgt = X(rn, Type::I64);
            setX(30, ir_.c64(pc + 4));
            Val v = ir_.emit(Op::ExitCallIndirect, Type::None, tgt);
            ir_.inst(v).imm2 = pc + 4;
            break;
        }
        case 2: {  // RET / RETAA
            if (pac) rn = 30;
            ir_.emit(Op::ExitRet, Type::None, X(rn, Type::I64));
            break;
        }
        default: return false;
        }
        ended_ = true;
        return true;
    }
    return false;
}

static int sysreg_id(u32 o0, u32 op1, u32 crn, u32 crm, u32 op2) {
    u32 key = (o0 << 14) | (op1 << 11) | (crn << 7) | (crm << 3) | op2;
#define SR(a, b, c, d, e) (((a) << 14) | ((b) << 11) | ((c) << 7) | ((d) << 3) | (e))
    switch (key) {
    case SR(3, 3, 13, 0, 2): return SYS_TPIDR_EL0;
    case SR(3, 3, 13, 0, 3): return SYS_TPIDRRO_EL0;
    case SR(3, 3, 4, 4, 0): return SYS_FPCR;
    case SR(3, 3, 4, 4, 1): return SYS_FPSR;
    case SR(3, 3, 14, 0, 2): return SYS_CNTVCT;
    case SR(3, 3, 14, 0, 6): return SYS_CNTVCT;   // CNTVCTSS_EL0
    case SR(3, 3, 14, 0, 1): return SYS_CNTVCT;   // CNTPCT_EL0
    case SR(3, 3, 14, 0, 0): return SYS_CNTFRQ;
    case SR(3, 0, 0, 0, 0): return SYS_MIDR;
    case SR(3, 0, 0, 0, 5): return SYS_MPIDR;
    case SR(3, 3, 0, 0, 7): return SYS_DCZID;
    case SR(3, 3, 0, 0, 1): return SYS_CTR;
    case SR(3, 3, 2, 4, 0): return SYS_RNDR;
    case SR(3, 3, 2, 4, 1): return SYS_RNDR;      // RNDRRS
    }
#undef SR
    return -1;
}

bool Translator::system(u32 i) {
    u32 l = bit(i, 21), op0 = bits(i, 20, 19), op1 = bits(i, 18, 16), crn = bits(i, 15, 12), crm = bits(i, 11, 8),
        op2 = bits(i, 7, 5), rt = bits(i, 4, 0);
    if (l == 0 && op0 == 0 && crn == 2 && op1 == 3 && rt == 31) {
        return true;  // HINT space: NOP, YIELD, WFE, WFI, SEV, PACIASP, AUTIASP, BTI, ... — all NOPs for us
    }
    if (l == 0 && op0 == 0 && crn == 3 && op1 == 3 && rt == 31) {  // barriers
        switch (op2) {
        case 2: ir_.emit(Op::ClearExcl, Type::None); return true;  // CLREX
        case 4:   // DSB
        case 5: { // DMB
            // CRm<1:0>: 01 = LD-only, 10 = ST-only, 11 = full. Under x86-TSO, load→load,
            // load→store and store→store ordering is architectural, so only barriers
            // that order store→load (full ones) need a real fence. See docs/memory-model.md.
            u32 types = crm & 3;
            if (types == 3 || op2 == 4) ir_.emit(Op::Barrier, Type::None, kNone, kNone, kNone, 0, BAR_FULL);
            return true;
        }
        case 6: ir_.emit(Op::Barrier, Type::None, kNone, kNone, kNone, 0, BAR_ISB); return true;  // ISB
        case 7: return true;  // SB
        default: return true;
        }
    }
    if (l == 0 && op0 == 0 && crn == 4) {  // MSR (immediate): PSTATE fields
        // op1=3,op2=1? -> e.g. MSR DAIFSet etc. (not EL0) / SVCR. Accept CFINV/XAFLAG/AXFLAG later.
        if (op1 == 0 && op2 == 0 && crm == 0) {  // CFINV
            Val f = ir_.get_flags();
            Val n = ir_.emit(Op::NZCVFromFlags, Type::I64, f);
            n = ir_.xor_(Type::I64, n, ir_.c64(1u << 29));
            ir_.set_flags(ir_.emit(Op::FlagsFromNZCV, Type::Flags, n));
            return true;
        }
        if (op1 == 3 && op2 == 1) return true;  // MSR SSBS/DIT style: ignore
        return false;
    }
    if (op0 == 1) {  // SYS / SYSL: cache maintenance
        // DC ZVA: op1=3 crn=7 crm=4 op2=1
        if (!l && op1 == 3 && crn == 7 && crm == 4 && op2 == 1) {
            Val addr = ir_.and_(Type::I64, X(rt, Type::I64), ir_.c64(~63ull));
            Val z = ir_.c64(0);
            for (int k = 0; k < 64; k += 8) ir_.store(ir_.add(Type::I64, addr, ir_.c64(k)), z, 8);
            return true;
        }
        // IC IVAU: op1=3 crn=7 crm=5 op2=1 -> drop translations of that cache line
        if (!l && op1 == 3 && crn == 7 && crm == 5 && op2 == 1) {
            Val h = ir_.emit(Op::Helper, Type::None, X(rt, Type::I64));
            ir_.inst(h).sub = 2;  // helper id: IC IVAU
            return true;
        }
        // DC CVAU / DC CIVAC / DC CVAC ...: no-ops (x86 caches are coherent)
        return !l;
    }
    if (op0 >= 2) {  // MRS / MSR (register)
        // NZCV: op0=3 op1=3 crn=4 crm=2 op2=0
        if (op0 == 3 && op1 == 3 && crn == 4 && crm == 2 && op2 == 0) {
            if (l) setX(rt, ir_.emit(Op::NZCVFromFlags, Type::I64, ir_.get_flags()));
            else ir_.set_flags(ir_.emit(Op::FlagsFromNZCV, Type::Flags, X(rt, Type::I64)));
            return true;
        }
        int id = sysreg_id(op0, op1, crn, crm, op2);
        if (id < 0) {
            // ID registers (op0=3, op1=0, crn=0): kernel emulates and returns 0 for unknown fields
            if (l && op0 == 3 && op1 == 0 && crn == 0) { setX(rt, ir_.c64(0)); return true; }
            return false;
        }
        if (l) {
            Val v = ir_.emit(Op::GetSys, Type::I64, kNone, kNone, kNone, 0, (u8)id);
            setX(rt, v);
        } else {
            if (id != SYS_TPIDR_EL0 && id != SYS_FPCR && id != SYS_FPSR) return false;
            ir_.emit(Op::SetSys, Type::None, X(rt, Type::I64), kNone, kNone, 0, (u8)id);
        }
        return true;
    }
    return false;
}

// ---------------------------------------------------------------- loads / stores

void Translator::do_load(int rt, Val addr, int size, bool sign, Type dst, bool vec) {
    if (vec) {
        Val v = ir_.emit(Op::VLoad, Type::V128, addr, kNone, kNone, 0, 0, (u8)size);
        ir_.vset(rt, v);
        return;
    }
    Val v = ir_.load(dst, addr, size, sign);
    setX(rt, v);
}

void Translator::do_store(int rt, Val addr, int size, bool vec) {
    if (vec) {
        Val v = ir_.vget(rt);
        ir_.emit(Op::VStore, Type::None, addr, v, kNone, 0, 0, (u8)size);
        return;
    }
    Val v = X(rt, size == 8 ? Type::I64 : Type::I32);
    ir_.store(addr, v, size);
}

bool Translator::ldst(u32 i) {
    u32 b2927 = bits(i, 29, 27);
    if (bits(i, 29, 24) == 0x08) return ldst_exclusive(i);
    if (bit(i, 31) == 0 && bits(i, 29, 24) == 0x0C) return ldst_simd_struct(i);
    if (bits(i, 29, 24) == 0x0D) return ldst_simd_struct(i);
    if (b2927 == 3 && bits(i, 25, 24) == 0) {  // load literal
        u32 opc = bits(i, 31, 30);
        bool v = bit(i, 26);
        int rt = bits(i, 4, 0);
        u64 addr = pc_ + (sext(bits(i, 23, 5), 19) << 2);
        Val a = ir_.c64(addr);
        if (v) {
            if (opc == 3) return false;
            do_load(rt, a, 4 << opc, false, Type::None, true);
        } else {
            if (opc == 0) do_load(rt, a, 4, false, Type::I32, false);
            else if (opc == 1) do_load(rt, a, 8, false, Type::I64, false);
            else if (opc == 2) do_load(rt, a, 4, true, Type::I64, false);
            // opc==3: PRFM literal -> nop
        }
        return true;
    }
    if (bits(i, 29, 24) == 0x19 && bit(i, 21) == 0 && bits(i, 11, 10) == 0) {
        // LDAPR/STLR unscaled (RCpc, FEAT_LRCPC2): STLUR*, LDAPUR*
        u32 size = bits(i, 31, 30), opc = bits(i, 23, 22);
        int rt = bits(i, 4, 0), rn = bits(i, 9, 5);
        Val addr = ir_.add(Type::I64, XSP(rn, Type::I64), ir_.c64((u64)sext(bits(i, 20, 12), 9)));
        int sz = 1 << size;
        if (opc == 0) {
            Val v = X(rt, sz == 8 ? Type::I64 : Type::I32);
            Val s = ir_.emit(Op::Store, Type::None, addr, v, kNone, 0, 1 /*seq-cst*/, (u8)sz);
            (void)s;
        } else if (opc == 1) do_load(rt, addr, sz, false, sz == 8 ? Type::I64 : Type::I32, false);
        else if (opc == 2) { if (size == 3) return false; do_load(rt, addr, sz, true, Type::I64, false); }
        else { if (size >= 2) return false; do_load(rt, addr, sz, true, Type::I32, false); }
        return true;
    }
    if (b2927 == 5) return ldst_pair(i);
    if (b2927 == 7) return ldst_reg(i);
    return false;
}

bool Translator::ldst_exclusive(u32 i) {
    u32 size = bits(i, 31, 30), o2 = bit(i, 23), l = bit(i, 22), o1 = bit(i, 21), o0 = bit(i, 15);
    int rs = bits(i, 20, 16), rt2 = bits(i, 14, 10), rn = bits(i, 9, 5), rt = bits(i, 4, 0);
    int sz = 1 << size;
    Type t = sz == 8 ? Type::I64 : Type::I32;
    Val addr = XSP(rn, Type::I64);
    if (!o2 && !o1) {  // LDXR/LDAXR/STXR/STLXR
        if (l) {
            Val v = ir_.emit(Op::LoadExcl, t, addr, kNone, kNone, 0, 0, (u8)sz);
            setX(rt, v);
        } else {
            Val st = ir_.emit(Op::StoreExcl, Type::I32, addr, X(rt, t), kNone, 0, 0, (u8)sz);
            setX(rs, st);
        }
        return true;
    }
    if (!o2 && o1) {
        if (bit(i, 31)) {  // LDXP / STXP (pairs)
            int esz = size == 3 ? 8 : 4;
            Type et = esz == 8 ? Type::I64 : Type::I32;
            if (l) {
                Val lo = ir_.emit(Op::LoadExcl, et, addr, kNone, kNone, 0, 1 /*pair lo*/, (u8)(esz * 2));
                Val hi = ir_.emit(Op::LoadExcl, et, addr, lo, kNone, 0, 2 /*pair hi*/, (u8)(esz * 2));
                setX(rt, lo);
                setX(rt2, hi);
            } else {
                Val st = ir_.emit(Op::StoreExcl, Type::I32, addr, X(rt, et), X(rt2, et), 0, 1, (u8)(esz * 2));
                setX(rs, st);
            }
            return true;
        }
        // CASP / CASPA / CASPL / CASPAL
        if (rt2 != 31 || (rs & 1) || (rt & 1)) return false;
        int esz = bit(i, 30) ? 8 : 4;
        Type et = esz == 8 ? Type::I64 : Type::I32;
        Val exp_hi = X(rs + 1, et), new_hi = X(rt + 1, et);
        Val v = ir_.emit(Op::Cas, et, addr, X(rs, et), X(rt, et), 0, 1 /*pair*/, (u8)(esz * 2));
        ir_.inst(v).imm = (u64)exp_hi | ((u64)new_hi << 16);
        Val hi = ir_.emit(Op::Cas, et, v, kNone, kNone, 0, 2 /*pair hi result*/, (u8)(esz * 2));
        setX(rs, v);
        setX(rs + 1, hi);
        return true;
    }
    if (o2 && !o1) {  // LDAR / STLR / LDLAR / STLLR
        if (l) {
            Val v = ir_.load(t, addr, sz, false);
            setX(rt, v);
        } else {
            Val v = X(rt, t);
            // STLR must be ordered before a later LDAR (RCsc): use a seq-cst store (xchg).
            ir_.emit(Op::Store, Type::None, addr, v, kNone, 0, o0 ? 1 : 0, (u8)sz);
        }
        return true;
    }
    // CAS / CASA / CASL / CASAL
    if (rt2 != 31) return false;
    Val v = ir_.emit(Op::Cas, t, addr, X(rs, t), X(rt, t), 0, 0, (u8)sz);
    setX(rs, v);
    return true;
}

bool Translator::ldst_pair(u32 i) {
    u32 opc = bits(i, 31, 30), mode = bits(i, 24, 23);
    bool v = bit(i, 26), l = bit(i, 22);
    int rt = bits(i, 4, 0), rn = bits(i, 9, 5), rt2 = bits(i, 14, 10);
    int scale;
    bool sign = false;
    if (v) { if (opc == 3) return false; scale = 2 + opc; }
    else {
        if (opc == 1) { if (!l) return false; sign = true; scale = 2; }  // LDPSW (STGP unsupported)
        else if (opc == 3) return false;
        else scale = opc == 0 ? 2 : 3;
    }
    i64 off = sext(bits(i, 21, 15), 7) << scale;
    int sz = 1 << scale;
    Val base = XSP(rn, Type::I64);
    Val addr = (mode == 1) ? base : ir_.add(Type::I64, base, ir_.c64((u64)off));
    Val addr2 = ir_.add(Type::I64, addr, ir_.c64(sz));
    if (l) {
        if (v) {
            do_load(rt, addr, sz, false, Type::None, true);
            do_load(rt2, addr2, sz, false, Type::None, true);
        } else {
            Type t = (sz == 8 || sign) ? Type::I64 : Type::I32;
            // Load both before writing registers (rt may equal rn).
            Val a = ir_.load(t, addr, sz, sign);
            Val b = ir_.load(t, addr2, sz, sign);
            setX(rt, a);
            setX(rt2, b);
        }
    } else {
        if (v) {
            do_store(rt, addr, sz, true);
            do_store(rt2, addr2, sz, true);
        } else {
            do_store(rt, addr, sz, false);
            do_store(rt2, addr2, sz, false);
        }
    }
    if (mode == 1) setXSP(rn, ir_.add(Type::I64, base, ir_.c64((u64)off)));
    else if (mode == 3) setXSP(rn, addr);
    return true;
}

bool Translator::ldst_reg(u32 i) {
    u32 size = bits(i, 31, 30), opc = bits(i, 23, 22);
    bool v = bit(i, 26);
    int rt = bits(i, 4, 0), rn = bits(i, 9, 5);
    u32 b2524 = bits(i, 25, 24);
    // LSE atomics: bits 23:22 are the A/R ordering bits there, not opc
    if (!v && b2524 == 0 && bit(i, 21) && bits(i, 11, 10) == 0) return ldst_atomic(i);
    // Determine access properties.
    int sz;
    bool load, sign = false, prfm = false;
    Type dt = Type::None;
    if (v) {
        int scale = ((opc & 2) << 1) | size;
        if (scale > 4) return false;
        sz = 1 << scale;
        load = opc & 1;
    } else {
        sz = 1 << size;
        if (opc == 0) load = false;
        else if (opc == 1) { load = true; dt = sz == 8 ? Type::I64 : Type::I32; }
        else if (opc == 2) {
            if (size == 3) { prfm = true; load = true; }
            else { load = true; sign = true; dt = Type::I64; }
        } else {
            if (size >= 2) return false;
            load = true; sign = true; dt = Type::I32;
        }
    }
    Val base = XSP(rn, Type::I64);
    Val addr;
    int wb = 0;  // 0 none, 1 post, 2 pre
    i64 off = 0;
    if (b2524 == 1) {  // unsigned immediate
        off = (i64)bits(i, 21, 10) * sz;
        addr = ir_.add(Type::I64, base, ir_.c64((u64)off));
    } else if (b2524 == 0) {
        if (bit(i, 21) == 0) {
            off = sext(bits(i, 20, 12), 9);
            u32 m = bits(i, 11, 10);
            if (m == 0 || m == 2) addr = ir_.add(Type::I64, base, ir_.c64((u64)off));  // LDUR / LDTR
            else if (m == 1) { addr = base; wb = 1; }
            else { addr = ir_.add(Type::I64, base, ir_.c64((u64)off)); wb = 2; }
        } else {
            u32 m = bits(i, 11, 10);
            if (m == 0) return ldst_atomic(i);
            if (m != 2) return false;  // PAC loads (LDRAA) unsupported
            int rm = bits(i, 20, 16), option = bits(i, 15, 13);
            if (!(option & 2)) return false;
            int sh = bit(i, 12) ? __builtin_ctz(sz) : 0;
            Val idx = extend_reg(Type::I64, X(rm, Type::I64), option, sh);
            addr = ir_.add(Type::I64, base, idx);
        }
    } else return false;

    if (prfm) {
        // prefetch: nop
    } else if (load) {
        if (wb && !v && rt == rn && rt != 31) {
            // unpredictable; follow writeback-then-load-wins semantics of most cores
        }
        do_load(rt, addr, sz, sign, dt, v);
    } else {
        do_store(rt, addr, sz, v);
    }
    if (wb == 1) setXSP(rn, ir_.add(Type::I64, base, ir_.c64((u64)off)));
    else if (wb == 2) setXSP(rn, addr);
    return true;
}

bool Translator::ldst_atomic(u32 i) {
    u32 size = bits(i, 31, 30), o3 = bit(i, 15), opc = bits(i, 14, 12);
    if (bit(i, 26)) return false;
    int rs = bits(i, 20, 16), rn = bits(i, 9, 5), rt = bits(i, 4, 0);
    int sz = 1 << size;
    Type t = sz == 8 ? Type::I64 : Type::I32;
    Val addr = XSP(rn, Type::I64);
    if (o3 && opc == 4) {  // LDAPR
        if (rs != 31) return false;
        setX(rt, ir_.load(t, addr, sz, false));
        return true;
    }
    u8 aop;
    if (o3) {
        if (opc != 0) return false;
        aop = AT_SWP;
    } else aop = (u8)opc;
    Val old = ir_.emit(Op::AtomicRMW, t, addr, X(rs, t), kNone, 0, aop, (u8)sz);
    setX(rt, old);
    return true;
}

// ---------------------------------------------------------------- DP reg

bool Translator::dp_reg(u32 i) {
    bool sf = bit(i, 31);
    Type t = T(sf);
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5), rm = bits(i, 20, 16);
    if (!bit(i, 28)) {
        if (!bit(i, 24)) {  // logical shifted register
            u32 opc = bits(i, 30, 29), shift = bits(i, 23, 22), n = bit(i, 21);
            int amt = bits(i, 15, 10);
            if (!sf && amt >= 32) return false;
            Val a = X(rn, t), b = shift_reg(t, X(rm, t), shift, amt);
            Val r;
            // MOV alias: ORR Rd, XZR, Rm
            switch ((opc << 1) | n) {
            case 0: r = ir_.and_(t, a, b); break;
            case 1: r = ir_.binop(Op::AndNot, t, a, b); break;
            case 2: r = (rn == 31) ? b : ir_.or_(t, a, b); break;
            case 3: r = (rn == 31) ? ir_.unop(Op::Not, t, b) : ir_.binop(Op::OrNot, t, a, b); break;
            case 4: r = ir_.xor_(t, a, b); break;
            case 5: r = ir_.binop(Op::XorNot, t, a, b); break;
            case 6: case 7: {
                r = n ? ir_.binop(Op::AndNot, t, a, b) : ir_.and_(t, a, b);
                Val f = ir_.emit(Op::FlagsLogic, Type::Flags, r);
                ir_.inst(f).size = sf ? 64 : 32;
                ir_.set_flags(f);
                break;
            }
            }
            setX(rd, r);
            return true;
        }
        bool sub = bit(i, 30), s = bit(i, 29);
        Val a, b;
        if (!bit(i, 21)) {  // add/sub shifted register
            u32 shift = bits(i, 23, 22);
            int amt = bits(i, 15, 10);
            if (shift == 3 || (!sf && amt >= 32)) return false;
            a = X(rn, t);
            b = shift_reg(t, X(rm, t), shift, amt);
        } else {  // extended register
            if (bits(i, 23, 22) != 0) return false;
            int option = bits(i, 15, 13), sh = bits(i, 12, 10);
            if (sh > 4) return false;
            a = XSP(rn, t);
            Val m = (option & 3) == 3 ? X(rm, Type::I64) : X(rm, Type::I32);
            if (t == Type::I64 && ir_.inst(m).ty == Type::I32) m = ir_.zext32to64(m);
            if (t == Type::I32) m = ir_.trunc32(m);
            b = extend_reg(t, m, option, sh);
        }
        Val r = sub ? ir_.sub(t, a, b) : ir_.add(t, a, b);
        if (s) {
            Val f = ir_.emit(sub ? Op::FlagsSub : Op::FlagsAdd, Type::Flags, a, b);
            ir_.inst(f).size = sf ? 64 : 32;
            ir_.set_flags(f);
            setX(rd, r);
        } else if (bit(i, 21)) setXSP(rd, r);
        else setX(rd, r);
        return true;
    }
    u32 op2 = bits(i, 24, 21);
    if (op2 == 0) {
        u32 op3 = bits(i, 15, 10);
        if (op3 == 0) {  // ADC/ADCS/SBC/SBCS
            bool sub = bit(i, 30), s = bit(i, 29);
            Val a = X(rn, t), b = X(rm, t), fl = ir_.get_flags();
            Val r = ir_.emit(sub ? Op::Sbc : Op::Adc, t, a, b, fl);
            if (s) {
                Val f = ir_.emit(sub ? Op::FlagsSbc : Op::FlagsAdc, Type::Flags, a, b, fl);
                ir_.inst(f).size = sf ? 64 : 32;
                ir_.set_flags(f);
            }
            setX(rd, r);
            return true;
        }
        if ((op3 & 0x1f) == 0x02 && bit(i, 29) && !bit(i, 30) && rd == 0xd) {  // SETF8 / SETF16
            return false;
        }
        return false;
    }
    if (op2 == 2) {  // conditional compare
        if (!bit(i, 29) || bit(i, 10) || bit(i, 4)) return false;
        bool sub = bit(i, 30);
        Cond c = (Cond)bits(i, 15, 12);
        Val a = X(rn, t);
        Val b = bit(i, 11) ? ir_.cnst(t, rm) : X(rm, t);
        Val fin = ir_.get_flags();
        Val f = ir_.emit(Op::FlagsCCmp, Type::Flags, a, b, fin, bits(i, 3, 0), (u8)c, sf ? 64 : 32);
        ir_.inst(f).sub = sub ? 1 : 0;
        ir_.set_flags(f);
        return true;
    }
    if (op2 == 4) {  // conditional select
        if (bit(i, 29) || bit(i, 11)) return false;
        u32 op = bit(i, 30), o2 = bit(i, 10);
        Cond c = (Cond)bits(i, 15, 12);
        Val fl = ir_.get_flags();
        Val n = X(rn, t), m = X(rm, t);
        Val fv;
        if (!op && !o2) fv = m;
        else if (!op && o2) fv = ir_.add(t, m, ir_.cnst(t, 1));
        else if (op && !o2) fv = ir_.unop(Op::Not, t, m);
        else fv = ir_.unop(Op::Neg, t, m);
        setX(rd, ir_.select(t, c, fl, n, fv));
        return true;
    }
    if (op2 == 6) {
        if (bit(i, 30)) {  // data-processing 1 source
            if (rm != 0 || bit(i, 29)) return false;
            u32 opc = bits(i, 15, 10);
            Val a = X(rn, t), r;
            switch (opc) {
            case 0: r = ir_.emit(Op::Rbit, t, a); break;
            case 1: r = ir_.emit(Op::Rev16, t, a); break;
            case 2: r = sf ? ir_.emit(Op::Rev32InWords, t, a) : ir_.emit(Op::Bswap, t, a); break;
            case 3: if (!sf) return false; r = ir_.emit(Op::Bswap, t, a); break;
            case 4: r = ir_.emit(Op::Clz, t, a); break;
            case 5: r = ir_.emit(Op::Cls, t, a); break;
            default: return false;
            }
            setX(rd, r);
            return true;
        }
        // data-processing 2 source
        if (bit(i, 29)) return false;
        u32 opc = bits(i, 15, 10);
        Val a = X(rn, t), b = X(rm, t), r;
        switch (opc) {
        case 2: r = ir_.emit(Op::UDiv, t, a, b); break;
        case 3: r = ir_.emit(Op::SDiv, t, a, b); break;
        case 8: r = ir_.shl(t, a, b); break;
        case 9: r = ir_.lshr(t, a, b); break;
        case 10: r = ir_.ashr(t, a, b); break;
        case 11: r = ir_.ror(t, a, b); break;
        default:
            if (opc >= 16 && opc <= 23) {  // CRC32*/CRC32C*
                int sz = 1 << (opc & 3);
                if ((sz == 8) != sf) return false;
                Val bb = X(rm, sz == 8 ? Type::I64 : Type::I32);
                r = ir_.emit(Op::Helper, Type::I32, ir_.trunc32(X(rn, Type::I32)), bb, kNone, 0,
                             (u8)((opc & 4) ? 1 : 0), (u8)sz);
                ir_.inst(r).sub = 1;  // helper id: CRC32
                setX(rd, r);
                return true;
            }
            return false;
        }
        setX(rd, r);
        return true;
    }
    if (bit(i, 24)) {  // data-processing 3 source
        u32 op31 = bits(i, 23, 21), o0 = bit(i, 15);
        int ra = bits(i, 14, 10);
        if (bits(i, 30, 29) != 0) return false;
        switch (op31) {
        case 0: {  // MADD / MSUB
            Val p = ir_.binop(Op::Mul, t, X(rn, t), X(rm, t));
            Val r = (ra == 31 && !o0) ? p : (o0 ? ir_.sub(t, X(ra, t), p) : ir_.add(t, X(ra, t), p));
            setX(rd, r);
            return true;
        }
        case 1: case 5: {  // SMADDL/SMSUBL, UMADDL/UMSUBL
            if (!sf) return false;
            bool u = op31 == 5;
            Val a = X(rn, Type::I32), b = X(rm, Type::I32);
            Val a64 = u ? ir_.zext32to64(a) : ir_.sext_from(Type::I64, ir_.zext32to64(a), 32);
            Val b64 = u ? ir_.zext32to64(b) : ir_.sext_from(Type::I64, ir_.zext32to64(b), 32);
            Val p = ir_.binop(Op::Mul, Type::I64, a64, b64);
            Val r = (ra == 31 && !o0) ? p
                    : (o0 ? ir_.sub(Type::I64, X(ra, Type::I64), p) : ir_.add(Type::I64, X(ra, Type::I64), p));
            setX(rd, r);
            return true;
        }
        case 2: case 6: {  // SMULH / UMULH
            if (!sf || o0) return false;
            setX(rd, ir_.emit(op31 == 6 ? Op::UMulH : Op::SMulH, Type::I64, X(rn, Type::I64), X(rm, Type::I64)));
            return true;
        }
        default: return false;
        }
    }
    return false;
}

// ---------------------------------------------------------------- block

// ---------------------------------------------------------------- NZCV liveness lookahead

bool guest_readable(GuestAddr pc) {
    static thread_local GuestAddr last_ok = 1;
    GuestAddr page = pc & ~0xfffull;
    if (page == last_ok) return true;
    unsigned char v;
    if (mincore((void*)page, 4096, &v) != 0) return false;
    last_ok = page;
    return true;
}

static thread_local PeekLog* tls_peek;
void set_peek_log(PeekLog* log) { tls_peek = log; }

// Returns true if NZCV may be read at `pc` before being overwritten.
bool nzcv_live_at(GuestAddr pc, int depth) {
    static thread_local ir::Block* scratch = new ir::Block();
    for (int i = 0; i < 24; i++) {
        if (!guest_readable(pc)) return true;
        if (tls_peek) tls_peek->add(pc, pc + 4);
        scratch->clear(pc);
        Translator tr(*scratch);
        tr.step(pc, *(const u32*)pc);
        bool reads = false, writes = false;
        const Inst* term = nullptr;
        for (int v = 1; v < scratch->n; v++) {
            const Inst& in = scratch->insts[v];
            if (in.op == Op::GetFlags) reads = true;
            if (in.op == Op::SetFlags) writes = true;
            if (is_terminator(in.op)) term = &in;
        }
        if (reads) return true;
        if (writes) return false;
        if (term) {
            switch (term->op) {
            case Op::ExitJump: pc = term->imm; continue;
            case Op::ExitCbz: case Op::ExitTbz:
                if (depth >= 2) return true;
                return nzcv_live_at(term->imm, depth + 1) || nzcv_live_at(term->imm2, depth + 1);
            default: return true;  // calls, returns, indirect branches, syscalls: conservative
            }
        }
        pc += 4;
    }
    return true;
}

static void compute_flags_liveness(ir::Block& blk) {
    const Inst* term = nullptr;
    for (int v = blk.n - 1; v >= 1; v--)
        if (is_terminator(blk.insts[v].op)) { term = &blk.insts[v]; break; }
    if (!term) return;
    switch (term->op) {
    case Op::ExitJump: blk.flags_live_out = nzcv_live_at(term->imm, 0); break;
    case Op::ExitCond: case Op::ExitCbz: case Op::ExitTbz:
        blk.flags_live_out = nzcv_live_at(term->imm, 0) || nzcv_live_at(term->imm2, 0);
        break;
    default: blk.flags_live_out = true; break;
    }
}

void translate_block(GuestAddr pc, ir::Block& blk, const TranslateOpts& opts) {
    blk.clear(pc);
    Translator tr(blk);
    GuestAddr cur = pc;
    for (int n = 0;; n++) {
        if (n >= opts.max_insts) {
            tr.ir().set_pc_off((u32)(cur - pc));
            tr.ir().emit(Op::ExitJump, Type::None, kNone, kNone, kNone, cur);
            break;
        }
        u32 insn = *(const u32*)cur;
        blk.guest_insts++;
        bool cont = tr.step(cur, insn);
        cur += 4;
        if (!cont) break;
    }
    blk.end = cur;
    compute_flags_liveness(blk);
}

}  // namespace xef::a64
