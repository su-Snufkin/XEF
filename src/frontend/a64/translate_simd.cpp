// XEF — AArch64 SIMD & floating-point translation.
//
// Vector registers are V128 SSA values. Every vector/FP operation becomes a
// VOp with an element size and flags (scalar / 64-bit), so the backend can
// pick an SSE/AVX lowering or fall back to the C reference implementation.
#include "frontend/a64/translate.h"

namespace xef::a64 {

using namespace ir;

namespace {
constexpr u8 F_SCALAR = 1;
constexpr u8 F_HALF = 2;   // 64-bit vector: zero the upper 64 bits of the result
}  // namespace

// AdvSIMDExpandImm
static u64 expand_simd_imm(u32 op, u32 cmode, u32 imm8) {
    u64 imm = imm8, r = 0;
    auto rep32 = [](u64 v) { return v | (v << 32); };
    auto rep16 = [](u64 v) { return v | (v << 16) | (v << 32) | (v << 48); };
    switch (cmode >> 1) {
    case 0: r = rep32(imm); break;
    case 1: r = rep32(imm << 8); break;
    case 2: r = rep32(imm << 16); break;
    case 3: r = rep32(imm << 24); break;
    case 4: r = rep16(imm); break;
    case 5: r = rep16(imm << 8); break;
    case 6:
        if (!(cmode & 1)) r = rep32((imm << 8) | 0xff);
        else r = rep32((imm << 16) | 0xffff);
        break;
    case 7:
        if (!(cmode & 1) && !op) { for (int i = 0; i < 8; i++) r |= imm << (8 * i); }
        else if (!(cmode & 1) && op) {
            for (int i = 0; i < 8; i++) if (imm & (1u << i)) r |= 0xffull << (8 * i);
        } else if ((cmode & 1) && !op) {
            // FMOV vector single: imm8 -> float32 replicated
            u32 a = (u32)bit(imm8, 7) << 31;
            u32 b = bit(imm8, 6);
            u32 f = a | ((b ? 0x1f : 0x20) << 25) | ((imm8 & 0x3f) << 19);
            if (b) f |= 0; else f |= 0;
            u32 e = (b ? 0x3e000000u : 0x40000000u);
            f = a | e | ((imm8 & 0x3f) << 19);
            r = rep32(f);
        } else {
            // FMOV vector double
            u64 a = (u64)bit(imm8, 7) << 63;
            u64 b = bit(imm8, 6);
            u64 e = b ? 0x3fc0000000000000ull : 0x4000000000000000ull;
            r = a | e | ((u64)(imm8 & 0x3f) << 48);
        }
        break;
    }
    return r;
}

// VFPExpandImm for scalar FMOV (imm8 -> f32/f64 bit pattern)
static u64 vfp_expand_imm(u32 imm8, int size) {
    u32 sign = bit(imm8, 7), b6 = bit(imm8, 6);
    if (size == 4) {
        u32 exp = (b6 ? 0x7c : 0x80) | ((imm8 >> 4) & 3);  // NOT(b6):b6:b6:b6:b6:b6:imm[5:4] (8 bits)
        exp = ((!b6) << 7) | (b6 ? 0x7c : 0) | ((imm8 >> 4) & 3);
        u32 frac = (imm8 & 0xf) << 19;
        return ((u32)sign << 31) | (exp << 23) | frac;
    }
    if (size == 8) {
        u64 exp = ((u64)(!b6) << 10) | (b6 ? 0x3fcull : 0) | ((imm8 >> 4) & 3);
        u64 frac = (u64)(imm8 & 0xf) << 48;
        return ((u64)sign << 63) | (exp << 52) | frac;
    }
    // half
    u32 exp = ((!b6) << 4) | (b6 ? 0xc : 0) | ((imm8 >> 4) & 3);
    return ((u32)sign << 15) | (exp << 10) | ((imm8 & 0xf) << 6);
}

namespace {
struct S {
    Translator& t;
    Builder& ir;
    S(Translator& tt) : t(tt), ir(tt.ir()) {}

    Val V(int r) { return ir.vget(r); }
    void setV(int r, Val v) { ir.vset(r, v); }
    Val vop(u16 op, int esize, u8 flags, Val a, Val b = kNone, Val c = kNone, u64 imm = 0) {
        Val v = ir.emit(Op::VOp, Type::V128, a, b, c, imm, flags, (u8)esize);
        ir.inst(v).sub = op;
        return v;
    }
    Val vconst(u64 lo, u64 hi) {
        Val v = ir.emit(Op::VConst, Type::V128, kNone, kNone, kNone, lo);
        ir.inst(v).imm2 = hi;
        return v;
    }
    Val zext(Val v, int bytes) { return vop(V_ZEXT, bytes, 0, v); }
};
}  // namespace

// ---------------------------------------------------------------------------- loads/stores

bool Translator::ldst_simd_struct(u32 i) {
    S s(*this);
    bool q = bit(i, 30), l = bit(i, 22), post = bit(i, 23);
    int rn = bits(i, 9, 5), rt = bits(i, 4, 0), rm = bits(i, 20, 16);
    int size = bits(i, 11, 10);
    Val base = XSP(rn, Type::I64);
    int total = 0;
    if (!bit(i, 24)) {
        // multiple structures
        if (bit(i, 21)) return false;
        if (!post && rm != 0) return false;
        u32 opcode = bits(i, 15, 12);
        int nregs, selem;
        switch (opcode) {
        case 0x0: nregs = 4; selem = 4; break;
        case 0x2: nregs = 4; selem = 1; break;
        case 0x4: nregs = 3; selem = 3; break;
        case 0x6: nregs = 3; selem = 1; break;
        case 0x7: nregs = 1; selem = 1; break;
        case 0x8: nregs = 2; selem = 2; break;
        case 0xA: nregs = 2; selem = 1; break;
        default: return false;
        }
        int esize = 1 << size;
        int rbytes = q ? 16 : 8;
        if (size == 3 && !q && selem != 1) return false;
        total = nregs * rbytes;
        if (selem == 1) {
            for (int k = 0; k < nregs; k++) {
                Val addr = ir_.add(Type::I64, base, ir_.c64(k * rbytes));
                int r = (rt + k) & 31;
                if (l) s.setV(r, ir_.emit(Op::VLoad, Type::V128, addr, kNone, kNone, 0, 0, (u8)rbytes));
                else ir_.emit(Op::VStore, Type::None, addr, s.V(r), kNone, 0, 0, (u8)rbytes);
            }
        } else if (selem == 2 || selem == 4) {
            if (l) {
                // load in 16-byte chunks; 64-bit forms use the 64-bit-vector (F_HALF) permutes
                int nchunks = total / 16;
                Val ch[4];
                for (int k = 0; k < nchunks; k++)
                    ch[k] = ir_.emit(Op::VLoad, Type::V128, ir_.add(Type::I64, base, ir_.c64(k * 16)), kNone, kNone,
                                     0, 0, 16);
                if (!q) {
                    if (selem == 2) {
                        Val a = ch[0], ah = s.vop(V_DUPELEM, 8, 0, a, kNone, kNone, 1);
                        s.setV(rt, s.vop(V_UZP1, esize, F_HALF, a, ah));
                        s.setV((rt + 1) & 31, s.vop(V_UZP2, esize, F_HALF, a, ah));
                    } else {
                        Val e = s.vop(V_UZP1, esize, 0, ch[0], ch[1]), o = s.vop(V_UZP2, esize, 0, ch[0], ch[1]);
                        Val e_hi = s.vop(V_DUPELEM, 8, 0, e, kNone, kNone, 1);
                        Val o_hi = s.vop(V_DUPELEM, 8, 0, o, kNone, kNone, 1);
                        s.setV(rt, s.vop(V_UZP1, esize, F_HALF, e, e_hi));
                        s.setV((rt + 2) & 31, s.vop(V_UZP2, esize, F_HALF, e, e_hi));
                        s.setV((rt + 1) & 31, s.vop(V_UZP1, esize, F_HALF, o, o_hi));
                        s.setV((rt + 3) & 31, s.vop(V_UZP2, esize, F_HALF, o, o_hi));
                    }
                } else if (selem == 2) {
                    s.setV(rt, s.vop(V_UZP1, esize, 0, ch[0], ch[1]));
                    s.setV((rt + 1) & 31, s.vop(V_UZP2, esize, 0, ch[0], ch[1]));
                } else {
                    Val e01 = s.vop(V_UZP1, esize, 0, ch[0], ch[1]);
                    Val o01 = s.vop(V_UZP2, esize, 0, ch[0], ch[1]);
                    Val e23 = s.vop(V_UZP1, esize, 0, ch[2], ch[3]);
                    Val o23 = s.vop(V_UZP2, esize, 0, ch[2], ch[3]);
                    s.setV(rt, s.vop(V_UZP1, esize, 0, e01, e23));
                    s.setV((rt + 2) & 31, s.vop(V_UZP2, esize, 0, e01, e23));
                    s.setV((rt + 1) & 31, s.vop(V_UZP1, esize, 0, o01, o23));
                    s.setV((rt + 3) & 31, s.vop(V_UZP2, esize, 0, o01, o23));
                }
            } else {
                Val r[4];
                for (int k = 0; k < nregs; k++) r[k] = s.V((rt + k) & 31);
                Val out[4];
                if (selem == 2) {
                    if (q) { out[0] = s.vop(V_ZIP1, esize, 0, r[0], r[1]); out[1] = s.vop(V_ZIP2, esize, 0, r[0], r[1]); }
                    else out[0] = s.vop(V_ZIP1, esize, 0, r[0], r[1]);
                } else {
                    Val z02a = s.vop(V_ZIP1, esize, 0, r[0], r[2]), z13a = s.vop(V_ZIP1, esize, 0, r[1], r[3]);
                    Val z02b = s.vop(V_ZIP2, esize, 0, r[0], r[2]), z13b = s.vop(V_ZIP2, esize, 0, r[1], r[3]);
                    out[0] = s.vop(V_ZIP1, esize, 0, z02a, z13a);
                    out[1] = s.vop(V_ZIP2, esize, 0, z02a, z13a);
                    if (q) {
                        out[2] = s.vop(V_ZIP1, esize, 0, z02b, z13b);
                        out[3] = s.vop(V_ZIP2, esize, 0, z02b, z13b);
                    }
                }
                int nout = total / 16;
                for (int k = 0; k < nout; k++)
                    ir_.emit(Op::VStore, Type::None, ir_.add(Type::I64, base, ir_.c64(k * 16)), out[k], kNone, 0, 0, 16);
            }
        } else {
            // LD3/ST3: element-wise (rare)
            int lanes = rbytes / esize;
            Type et = esize == 8 ? Type::I64 : Type::I32;
            if (l) {
                Val regs[3];
                for (int k = 0; k < 3; k++) regs[k] = s.vconst(0, 0);
                for (int e = 0; e < lanes; e++)
                    for (int k = 0; k < 3; k++) {
                        Val addr = ir_.add(Type::I64, base, ir_.c64((e * 3 + k) * esize));
                        Val x = ir_.load(et, addr, esize, false);
                        Val g = ir_.emit(Op::GprToV, Type::V128, x, regs[k], kNone, e, 1, (u8)esize);
                        regs[k] = g;
                    }
                for (int k = 0; k < 3; k++) s.setV((rt + k) & 31, regs[k]);
            } else {
                Val regs[3];
                for (int k = 0; k < 3; k++) regs[k] = s.V((rt + k) & 31);
                for (int e = 0; e < lanes; e++)
                    for (int k = 0; k < 3; k++) {
                        Val x = ir_.emit(Op::VToGpr, et, regs[k], kNone, kNone, e, 0, (u8)esize);
                        ir_.store(ir_.add(Type::I64, base, ir_.c64((e * 3 + k) * esize)), x, esize);
                    }
            }
        }
    } else {
        // single structure (lane) / replicate
        u32 opcode = bits(i, 15, 13), sbit = bit(i, 12), r = bit(i, 21);
        int selem = ((opcode & 1) << 1 | r) + 1;
        int scale = opcode >> 1;
        bool replicate = false;
        int index = 0;
        int esize;
        switch (scale) {
        case 0: index = (q << 3) | (sbit << 2) | size; esize = 1; break;
        case 1: if (size & 1) return false; index = (q << 2) | (sbit << 1) | (size >> 1); esize = 2; break;
        case 2:
            if (size & 2) return false;
            if (!(size & 1)) { index = (q << 1) | sbit; esize = 4; }
            else { if (sbit) return false; index = q; esize = 8; }
            break;
        default:
            if (!l || sbit) return false;
            replicate = true;
            esize = 1 << size;
            break;
        }
        if (!post && rm != 0) return false;
        total = selem * esize;
        Type et = esize == 8 ? Type::I64 : Type::I32;
        for (int k = 0; k < selem; k++) {
            Val addr = ir_.add(Type::I64, base, ir_.c64(k * esize));
            int reg = (rt + k) & 31;
            if (replicate) {
                Val x = ir_.load(et, addr, esize, false);
                Val d = ir_.emit(Op::GprToV, Type::V128, x, kNone, kNone, 0, 0, (u8)esize);
                if (!q) d = s.zext(d, 8);
                s.setV(reg, d);
            } else if (l) {
                Val x = ir_.load(et, addr, esize, false);
                s.setV(reg, ir_.emit(Op::GprToV, Type::V128, x, s.V(reg), kNone, index, 1, (u8)esize));
            } else {
                Val x = ir_.emit(Op::VToGpr, et, s.V(reg), kNone, kNone, index, 0, (u8)esize);
                ir_.store(addr, x, esize);
            }
        }
    }
    if (post) {
        Val off = rm == 31 ? ir_.c64(total) : X(rm, Type::I64);
        setXSP(rn, ir_.add(Type::I64, base, off));
    }
    return true;
}

// ---------------------------------------------------------------------------- scalar FP

static int ftype_size(u32 ftype) {
    switch (ftype) { case 0: return 4; case 1: return 8; case 3: return 2; default: return 0; }
}

static bool fp_scalar(Translator& t, u32 i) {
    S s(t);
    Builder& ir = s.ir;
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5), rm = bits(i, 20, 16);
    u32 ftype = bits(i, 23, 22);
    int fs = ftype_size(ftype);
    if (bit(i, 24)) {  // FP data-processing 3 source
        if (!fs || fs == 2) return false;
        int ra = bits(i, 14, 10);
        u32 o1 = bit(i, 21), o0 = bit(i, 15);
        u16 op = !o1 ? (o0 ? V_FMSUB : V_FMADD) : (o0 ? V_FNMSUB : V_FNMADD);
        s.setV(rd, s.vop(op, fs, F_SCALAR, s.V(rn), s.V(rm), s.V(ra)));
        return true;
    }
    if (!bit(i, 21)) {  // fixed-point conversions
        int sf = bit(i, 31);
        u32 rmode = bits(i, 20, 19), opcode = bits(i, 18, 16);
        int scale = 64 - (int)bits(i, 15, 10);
        if (!fs || fs == 2) return false;
        if (!sf && scale > 32) return false;
        Type it = sf ? Type::I64 : Type::I32;
        if (rmode == 3 && (opcode & 6) == 0) {  // FCVTZS/FCVTZU (fixed)
            bool u = opcode & 1;
            Val r = ir.emit(Op::FToI, it, s.V(rn), kNone, kNone, (u64)scale, (u8)(FR_ZERO | (u ? 0 : 0x10)), (u8)fs);
            t.setX(rd, r);
            return true;
        }
        if (rmode == 0 && (opcode & 6) == 2) {  // SCVTF/UCVTF (fixed)
            bool u = opcode & 1;
            Val r = ir.emit(Op::IToF, Type::V128, t.X(rn, it), kNone, kNone, (u64)scale, (u8)(u ? 0 : 1), (u8)fs);
            s.setV(rd, r);
            return true;
        }
        return false;
    }
    u32 b1510 = bits(i, 15, 10);
    if (b1510 == 0) {  // FP <-> integer conversions
        int sf = bit(i, 31);
        u32 rmode = bits(i, 20, 19), opcode = bits(i, 18, 16);
        Type it = sf ? Type::I64 : Type::I32;
        if (opcode == 6 || opcode == 7) {  // FMOV
            if (rmode == 0) {
                if ((fs == 4 && sf) || (fs == 8 && !sf)) {
                    if (fs != 2) return false;
                }
                int sz = fs;
                if (opcode == 6) t.setX(rd, ir.emit(Op::VToGpr, it, s.V(rn), kNone, kNone, 0, 0, (u8)sz));
                else s.setV(rd, ir.emit(Op::GprToV, Type::V128, t.X(rn, it), kNone, kNone, 0, 2, (u8)sz));
                return true;
            }
            if (rmode == 1 && ftype == 2 && sf) {  // FMOV Xd, Vn.D[1] / Vd.D[1], Xn
                if (opcode == 6) t.setX(rd, ir.emit(Op::VToGpr, Type::I64, s.V(rn), kNone, kNone, 1, 0, 8));
                else s.setV(rd, ir.emit(Op::GprToV, Type::V128, t.X(rn, Type::I64), s.V(rd), kNone, 1, 1, 8));
                return true;
            }
            return false;
        }
        if (!fs) return false;
        if (opcode == 2 || opcode == 3) {  // SCVTF / UCVTF
            if (rmode != 0) return false;
            Val r = ir.emit(Op::IToF, Type::V128, t.X(rn, it), kNone, kNone, 0, (u8)(opcode == 2 ? 1 : 0), (u8)fs);
            s.setV(rd, r);
            return true;
        }
        // FCVT{N,P,M,Z,A}{S,U}
        u8 rnd;
        if (opcode == 0 || opcode == 1) rnd = rmode == 0 ? FR_TIEEVEN : rmode == 1 ? FR_POSINF : rmode == 2 ? FR_NEGINF : FR_ZERO;
        else if (opcode == 4 || opcode == 5) { if (rmode) return false; rnd = FR_TIEAWAY; }
        else return false;
        bool u = opcode & 1;
        Val r = ir.emit(Op::FToI, it, s.V(rn), kNone, kNone, 0, (u8)(rnd | (u ? 0 : 0x10)), (u8)fs);
        t.setX(rd, r);
        return true;
    }
    if (bits(i, 14, 10) == 0x10) {  // FP data-processing 1 source
        u32 opcode = bits(i, 20, 15);
        if (!fs) return false;
        Val a = s.V(rn);
        switch (opcode) {
        case 0: s.setV(rd, s.zext(a, fs)); return true;  // FMOV
        case 1: s.setV(rd, s.vop(V_FABS, fs, F_SCALAR, a)); return true;
        case 2: s.setV(rd, s.vop(V_FNEG, fs, F_SCALAR, a)); return true;
        case 3: s.setV(rd, s.vop(V_FSQRT, fs, F_SCALAR, a)); return true;
        case 4: case 5: case 7: {  // FCVT to single/double/half
            int to = opcode == 4 ? 4 : opcode == 5 ? 8 : 2;
            if (to == fs) return false;
            u16 op;
            if (fs == 4 && to == 8) op = V_FCVTS2D;
            else if (fs == 8 && to == 4) op = V_FCVTD2S;
            else if (fs == 2 && to == 4) op = V_FCVTH2S;
            else if (fs == 4 && to == 2) op = V_FCVTS2H;
            else if (fs == 2 && to == 8) op = V_FCVTH2D;
            else op = V_FCVTD2H;
            s.setV(rd, s.vop(op, fs, F_SCALAR, a));
            return true;
        }
        case 8: case 9: case 10: case 11: case 12: case 14: case 15: {  // FRINTN/P/M/Z/A/X/I
            if (fs == 2) return false;
            u8 rnd = opcode == 8 ? FR_TIEEVEN : opcode == 9 ? FR_POSINF : opcode == 10 ? FR_NEGINF
                   : opcode == 11 ? FR_ZERO : opcode == 12 ? FR_TIEAWAY : FR_CURRENT;
            s.setV(rd, s.vop(opcode == 14 ? V_FRINTX : V_FRINT, fs, F_SCALAR, a, kNone, kNone, rnd));
            return true;
        }
        default: return false;
        }
    }
    if (bits(i, 13, 10) == 0x8) {  // FP compare
        if (!fs || bits(i, 15, 14) != 0) return false;
        u32 opc2 = bits(i, 4, 0);
        bool zero = opc2 & 8;
        Val a = s.V(rn);
        Val b = zero ? s.vconst(0, 0) : s.V(rm);
        Val f = ir.emit(Op::FCmpFlags, Type::Flags, a, b, kNone, 0, (u8)((opc2 >> 4) & 1), (u8)fs);
        ir.set_flags(f);
        return true;
    }
    if (bits(i, 12, 10) == 0x4) {  // FMOV (scalar immediate)
        if (!fs || bits(i, 9, 5) != 0) return false;
        u64 imm = vfp_expand_imm(bits(i, 20, 13), fs);
        s.setV(rd, s.vconst(imm, 0));
        return true;
    }
    if (bits(i, 11, 10) == 0x1) {  // FCCMP / FCCMPE
        if (!fs) return false;
        Cond c = (Cond)bits(i, 15, 12);
        Val f = ir.emit(Op::FCCmpFlags, Type::Flags, s.V(rn), s.V(rm), ir.get_flags(), bits(i, 3, 0), (u8)c, (u8)fs);
        ir.set_flags(f);
        return true;
    }
    if (bits(i, 11, 10) == 0x2) {  // FP data-processing 2 source
        if (!fs) return false;
        u32 opcode = bits(i, 15, 12);
        static const u16 ops[9] = {V_FMUL, V_FDIV, V_FADD, V_FSUB, V_FMAX, V_FMIN, V_FMAXNM, V_FMINNM, V_FNMUL};
        if (opcode > 8) return false;
        s.setV(rd, s.vop(ops[opcode], fs, F_SCALAR, s.V(rn), s.V(rm)));
        return true;
    }
    if (bits(i, 11, 10) == 0x3) {  // FCSEL
        if (!fs) return false;
        Cond c = (Cond)bits(i, 15, 12);
        Val v = ir.emit(Op::VSelect, Type::V128, ir.get_flags(), s.V(rn), s.V(rm), 0, (u8)c, (u8)fs);
        s.setV(rd, v);
        return true;
    }
    return false;
}

// ---------------------------------------------------------------------------- Advanced SIMD

static bool simd_three_same(Translator& t, u32 i, bool scalar) {
    S s(t);
    bool q = bit(i, 30), u = bit(i, 29);
    int size = bits(i, 23, 22), opcode = bits(i, 15, 11);
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5), rm = bits(i, 20, 16);
    int esize = 1 << size;
    u8 fl = scalar ? F_SCALAR : (q ? 0 : F_HALF);
    Val a = s.V(rn), b = s.V(rm);
    u16 op;
    if (opcode >= 0x18) {  // FP three same
        int fsz = (size & 1) ? 8 : 4;
        if (fsz == 8 && !q && !scalar) return false;
        bool hi = size & 2;
        u32 key = (u << 6) | (hi << 5) | opcode;
        switch (key) {
        case 0x18: op = V_FMAXNM; break;
        case 0x19: op = V_FMLA; break;
        case 0x1a: op = V_FADD; break;
        case 0x1b: op = V_FMULX; break;
        case 0x1c: op = V_FCMEQ; break;
        case 0x1e: op = V_FMAX; break;
        case 0x1f: op = V_FRECPS; break;
        case 0x38: op = V_FMINNM; break;
        case 0x39: op = V_FMLS; break;
        case 0x3a: op = V_FSUB; break;
        case 0x3e: op = V_FMIN; break;
        case 0x3f: op = V_FRSQRTS; break;
        case 0x58: op = V_FMAXNMP; break;
        case 0x5a: op = V_FADDP; break;
        case 0x5b: op = V_FMUL; break;
        case 0x5c: op = V_FCMGE; break;
        case 0x5d: op = V_FACGE; break;
        case 0x5e: op = V_FMAXP; break;
        case 0x5f: op = V_FDIV; break;
        case 0x78: op = V_FMINNMP; break;
        case 0x7a: op = V_FABD; break;
        case 0x7c: op = V_FCMGT; break;
        case 0x7d: op = V_FACGT; break;
        case 0x7e: op = V_FMINP; break;
        default: return false;
        }
        if (scalar && (op == V_FMLA || op == V_FMLS || op == V_FADD || op == V_FSUB || op == V_FMUL ||
                       op == V_FDIV || op == V_FMAX || op == V_FMIN || op == V_FMAXNM || op == V_FMINNM ||
                       op == V_FADDP || op == V_FMAXP || op == V_FMINP || op == V_FMAXNMP || op == V_FMINNMP))
            return false;
        Val c = (op == V_FMLA || op == V_FMLS) ? s.V(rd) : kNone;
        s.setV(rd, s.vop(op, fsz, fl, a, b, c));
        return true;
    }
    if (opcode == 0x03) {  // logical
        u32 opc = (u << 2) | size;
        Val r;
        switch (opc) {
        case 0: r = s.vop(V_AND, 16, fl, a, b); break;
        case 1: r = s.vop(V_BIC, 16, fl, a, b); break;
        case 2: r = s.vop(V_ORR, 16, fl, a, b); break;
        case 3: r = s.vop(V_ORN, 16, fl, a, b); break;
        case 4: r = s.vop(V_EOR, 16, fl, a, b); break;
        case 5: r = s.vop(V_BSL, 16, fl, s.V(rd), a, b); break;                 // BSL: d = d ? n : m
        case 6: r = s.vop(V_BSL, 16, fl, b, a, s.V(rd)); break;                 // BIT: m ? n : d
        case 7: r = s.vop(V_BSL, 16, fl, b, s.V(rd), a); break;                 // BIF: m ? d : n
        default: return false;
        }
        if (scalar) return false;
        s.setV(rd, r);
        return true;
    }
    if (size == 3 && !q && !scalar) return false;
    switch ((u << 5) | opcode) {
    case 0x00: op = V_SHADD; break;
    case 0x01: op = V_SQADD; break;
    case 0x02: op = V_SRHADD; break;
    case 0x04: op = V_SHSUB; break;
    case 0x05: op = V_SQSUB; break;
    case 0x06: op = V_CMGT; break;
    case 0x07: op = V_CMGE; break;
    case 0x08: op = V_SSHL; break;
    case 0x09: op = V_SQSHL; break;
    case 0x0a: op = V_SRSHL; break;
    case 0x0b: op = V_SQRSHL; break;
    case 0x0c: op = V_SMAX; break;
    case 0x0d: op = V_SMIN; break;
    case 0x0e: op = V_SABD; break;
    case 0x0f: op = V_SABA; break;
    case 0x10: op = V_ADD; break;
    case 0x11: op = V_CMTST; break;
    case 0x12: op = V_MLA; break;
    case 0x13: op = V_MUL; break;
    case 0x14: op = V_SMAXP; break;
    case 0x15: op = V_SMINP; break;
    case 0x16: op = V_SQDMULH; break;
    case 0x17: op = V_ADDP; break;
    case 0x20: op = V_UHADD; break;
    case 0x21: op = V_UQADD; break;
    case 0x22: op = V_URHADD; break;
    case 0x24: op = V_UHSUB; break;
    case 0x25: op = V_UQSUB; break;
    case 0x26: op = V_CMHI; break;
    case 0x27: op = V_CMHS; break;
    case 0x28: op = V_USHL; break;
    case 0x29: op = V_UQSHL; break;
    case 0x2a: op = V_URSHL; break;
    case 0x2b: op = V_UQRSHL; break;
    case 0x2c: op = V_UMAX; break;
    case 0x2d: op = V_UMIN; break;
    case 0x2e: op = V_UABD; break;
    case 0x2f: op = V_UABA; break;
    case 0x30: op = V_SUB; break;
    case 0x31: op = V_CMEQ; break;
    case 0x32: op = V_MLS; break;
    case 0x33: op = V_PMUL; break;
    case 0x34: op = V_UMAXP; break;
    case 0x35: op = V_UMINP; break;
    case 0x36: op = V_SQRDMULH; break;
    default: return false;
    }
    if (scalar) {
        // scalar three-same allows only a subset (64-bit integer ops + saturating ops)
        switch (op) {
        case V_ADD: case V_SUB: case V_CMGT: case V_CMGE: case V_CMHI: case V_CMHS: case V_CMEQ: case V_CMTST:
        case V_SSHL: case V_USHL: case V_SRSHL: case V_URSHL:
            if (size != 3) return false;
            break;
        case V_SQADD: case V_UQADD: case V_SQSUB: case V_UQSUB: case V_SQSHL: case V_UQSHL: case V_SQRSHL: case V_UQRSHL:
        case V_SQDMULH: case V_SQRDMULH:
            break;
        default: return false;
        }
    }
    Val c = (op == V_MLA || op == V_MLS || op == V_SABA || op == V_UABA) ? s.V(rd) : kNone;
    s.setV(rd, s.vop(op, esize, fl, a, b, c));
    return true;
}

static bool simd_two_misc(Translator& t, u32 i, bool scalar) {
    S s(t);
    bool q = bit(i, 30), u = bit(i, 29);
    int size = bits(i, 23, 22), opcode = bits(i, 16, 12);
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5);
    int esize = 1 << size;
    u8 fl = scalar ? F_SCALAR : (q ? 0 : F_HALF);
    Val a = s.V(rn);
    u32 key = (u << 5) | opcode;
    // FP two-reg misc (opcode >= 0x0c with size<2 or 1x)
    bool fpk = (opcode >= 0x0c && opcode <= 0x0f && size >= 2) || (opcode >= 0x16 && opcode <= 0x1f) ||
               (opcode == 0x0c || opcode == 0x0d || opcode == 0x0e) ;
    (void)fpk;
    switch (key) {
    case 0x00: if (scalar || size == 3) return false; s.setV(rd, s.vop(V_REV64, esize, fl, a)); return true;
    case 0x20: if (scalar || size >= 2) return false; s.setV(rd, s.vop(V_REV32, esize, fl, a)); return true;
    case 0x01: if (scalar || size >= 1) return false; s.setV(rd, s.vop(V_REV16, esize, fl, a)); return true;
    case 0x02: case 0x22: if (scalar || size == 3) return false;
        s.setV(rd, s.vop(u ? V_UADDLP : V_SADDLP, esize, fl, a)); return true;
    case 0x06: case 0x26: if (scalar || size == 3) return false;
        s.setV(rd, s.vop(u ? V_UADALP : V_SADALP, esize, fl, a, kNone, s.V(rd))); return true;
    case 0x03: case 0x23: s.setV(rd, s.vop(u ? V_USQADD : V_SUQADD, esize, fl, a, kNone, s.V(rd))); return true;
    case 0x04: if (scalar || size == 3) return false; s.setV(rd, s.vop(V_CLS, esize, fl, a)); return true;
    case 0x24: if (scalar || size == 3) return false; s.setV(rd, s.vop(V_CLZ, esize, fl, a)); return true;
    case 0x05: if (scalar || size != 0) return false; s.setV(rd, s.vop(V_CNT, 1, fl, a)); return true;
    case 0x25:
        if (scalar) return false;
        if (size == 0) { s.setV(rd, s.vop(V_NOT, 16, fl, a)); return true; }
        if (size == 1) { s.setV(rd, s.vop(V_RBIT, 1, fl, a)); return true; }
        return false;
    case 0x07: s.setV(rd, s.vop(V_SQABS, esize, fl, a)); return true;
    case 0x27: s.setV(rd, s.vop(V_SQNEG, esize, fl, a)); return true;
    case 0x08: case 0x09: case 0x28: case 0x29: case 0x0a: case 0x0b: case 0x2b: {
        if (scalar && size != 3 && key != 0x07) return false;
        if (!scalar && size == 3 && !q) return false;
        Val z = s.vconst(0, 0);
        switch (key) {
        case 0x08: s.setV(rd, s.vop(V_CMGT, esize, fl, a, z)); return true;
        case 0x09: s.setV(rd, s.vop(V_CMEQ, esize, fl, a, z)); return true;
        case 0x0a: s.setV(rd, s.vop(V_CMGT, esize, fl, z, a)); return true;  // CMLT #0
        case 0x28: s.setV(rd, s.vop(V_CMGE, esize, fl, a, z)); return true;
        case 0x29: s.setV(rd, s.vop(V_CMGE, esize, fl, z, a)); return true;  // CMLE #0
        case 0x0b: s.setV(rd, s.vop(V_ABS, esize, fl, a)); return true;
        case 0x2b: s.setV(rd, s.vop(V_NEG, esize, fl, a)); return true;
        }
        return false;
    }
    case 0x12: case 0x32: {  // XTN/XTN2, SQXTUN
        if (size == 3) return false;
        u16 op = key == 0x12 ? V_XTN : V_SQXTUN;
        Val r = s.vop(op, esize, scalar ? F_SCALAR : 0, a);   // narrow into low 64 bits
        if (scalar) { s.setV(rd, r); return true; }
        if (q) r = s.vop(V_INSELEM, 8, 0, s.V(rd), r, kNone, 1 | (0 << 8));  // XTN2: upper half
        s.setV(rd, r);
        return true;
    }
    case 0x14: case 0x34: {  // SQXTN, UQXTN
        if (size == 3) return false;
        Val r = s.vop(key == 0x14 ? V_SQXTN : V_UQXTN, esize, scalar ? F_SCALAR : 0, a);
        if (!scalar && q) r = s.vop(V_INSELEM, 8, 0, s.V(rd), r, kNone, 1);
        s.setV(rd, r);
        return true;
    }
    case 0x33: {  // SHLL
        if (scalar || size == 3) return false;
        Val src = q ? s.vop(V_DUPELEM, 8, 0, a, kNone, kNone, 1) : a;
        s.setV(rd, s.vop(V_SHLL, esize, 0, src));
        return true;
    }
    case 0x16: {  // FCVTN/FCVTN2 (double->single, single->half)
        if (scalar) return false;
        Val r = s.vop(V_FCVTN, (size & 1) ? 8 : 4, 0, a);
        if (q) r = s.vop(V_INSELEM, 8, 0, s.V(rd), r, kNone, 1);
        s.setV(rd, r);
        return true;
    }
    case 0x17: {  // FCVTL/FCVTL2
        if (scalar) return false;
        Val src = q ? s.vop(V_DUPELEM, 8, 0, a, kNone, kNone, 1) : a;
        s.setV(rd, s.vop(V_FCVTL, (size & 1) ? 8 : 4, 0, src));
        return true;
    }
    default: break;
    }
    // floating point two-reg misc
    int fsz = (size & 1) ? 8 : 4;
    if (!scalar && fsz == 8 && !q) return false;
    bool hi = size & 2;
    u32 fk = (u << 6) | (hi << 5) | opcode;
    Val z = s.vconst(0, 0);
    switch (fk) {
    case 0x18: case 0x19: case 0x38: case 0x39: case 0x58: case 0x59: case 0x78: case 0x79: {
        // FRINTN, FRINTM, FRINTP, FRINTZ, FRINTA, FRINTX, FRINTI
        u8 rnd;
        u16 op = V_FRINT;
        switch (fk) {
        case 0x18: rnd = FR_TIEEVEN; break;
        case 0x19: rnd = FR_NEGINF; break;
        case 0x38: rnd = FR_POSINF; break;
        case 0x39: rnd = FR_ZERO; break;
        case 0x58: rnd = FR_TIEAWAY; break;
        case 0x59: rnd = FR_CURRENT; op = V_FRINTX; break;
        case 0x79: rnd = FR_CURRENT; break;
        default: return false;
        }
        s.setV(rd, s.vop(op, fsz, fl, a, kNone, kNone, rnd));
        return true;
    }
    case 0x1a: case 0x1b: case 0x1c: case 0x3a: case 0x3b: case 0x5a: case 0x5b: case 0x5c:
    case 0x7a: case 0x7b: {
        // FCVTNS FCVTMS FCVTAS FCVTPS FCVTZS / U variants (vector)
        u8 rnd;
        switch (fk & 0x3f) {
        case 0x1a: rnd = FR_TIEEVEN; break;
        case 0x1b: rnd = FR_NEGINF; break;
        case 0x1c: rnd = FR_TIEAWAY; break;
        case 0x3a: rnd = FR_POSINF; break;
        case 0x3b: rnd = FR_ZERO; break;
        default: return false;
        }
        bool uu = u;
        s.setV(rd, s.vop(uu ? V_FCVTZU : V_FCVTZS, fsz, fl, a, kNone, kNone, rnd));
        return true;
    }
    case 0x1d: s.setV(rd, s.vop(V_SCVTF, fsz, fl, a)); return true;
    case 0x5d: s.setV(rd, s.vop(V_UCVTF, fsz, fl, a)); return true;
    case 0x2c: s.setV(rd, s.vop(V_FCMGT, fsz, fl, a, z)); return true;
    case 0x2d: s.setV(rd, s.vop(V_FCMEQ, fsz, fl, a, z)); return true;
    case 0x2e: s.setV(rd, s.vop(V_FCMGT, fsz, fl, z, a)); return true;  // FCMLT #0
    case 0x6c: s.setV(rd, s.vop(V_FCMGE, fsz, fl, a, z)); return true;
    case 0x6d: s.setV(rd, s.vop(V_FCMGE, fsz, fl, z, a)); return true;  // FCMLE #0
    case 0x2f: s.setV(rd, s.vop(V_FABS, fsz, fl, a)); return true;
    case 0x6f: s.setV(rd, s.vop(V_FNEG, fsz, fl, a)); return true;
    case 0x7f: s.setV(rd, s.vop(V_FSQRT, fsz, fl, a)); return true;
    case 0x3d: s.setV(rd, s.vop(V_FRECPE, fsz, fl, a)); return true;
    case 0x7d: s.setV(rd, s.vop(V_FRSQRTE, fsz, fl, a)); return true;
    case 0x3c: if (scalar) return false; s.setV(rd, s.vop(V_URECPE, 4, fl, a)); return true;
    case 0x7c: if (scalar) return false; s.setV(rd, s.vop(V_URSQRTE, 4, fl, a)); return true;
    default: return false;
    }
}

static bool simd_across(Translator& t, u32 i) {
    S s(t);
    bool q = bit(i, 30), u = bit(i, 29);
    int size = bits(i, 23, 22), opcode = bits(i, 16, 12);
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5);
    int esize = 1 << size;
    u8 fl = q ? 0 : F_HALF;
    Val a = s.V(rn);
    u16 op;
    switch ((u << 5) | opcode) {
    case 0x03: op = V_SADDLV; break;
    case 0x0a: op = V_SMAXV; break;
    case 0x1a: op = V_SMINV; break;
    case 0x1b: op = V_ADDV; break;
    case 0x23: op = V_UADDLV; break;
    case 0x2a: op = V_UMAXV; break;
    case 0x3a: op = V_UMINV; break;
    case 0x2c: op = (size & 2) ? V_FMINNMV : V_FMAXNMV; esize = 4; if (!q) return false; break;
    case 0x2f: op = (size & 2) ? V_FMINV : V_FMAXV; esize = 4; if (!q) return false; break;
    default: return false;
    }
    if (op != V_FMAXV && op != V_FMINV && op != V_FMAXNMV && op != V_FMINNMV) {
        if (size == 3 || (size == 2 && !q)) return false;
    }
    s.setV(rd, s.vop(op, esize, fl, a));
    return true;
}

static bool simd_copy(Translator& t, u32 i, bool scalar) {
    S s(t);
    bool q = bit(i, 30), op = bit(i, 29);
    int imm5 = bits(i, 20, 16), imm4 = bits(i, 14, 11);
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5);
    if ((imm5 & 0xf) == 0) return false;
    int size = __builtin_ctz(imm5);
    int esize = 1 << size;
    int index = imm5 >> (size + 1);
    if (scalar) {  // DUP (element) scalar = MOV
        if (op || imm4 != 0) return false;
        Val r = s.vop(V_DUPELEM, esize, F_SCALAR, s.V(rn), kNone, kNone, index);
        s.setV(rd, r);
        return true;
    }
    if (op) {  // INS (element)
        if (!q) return false;
        int src_index = imm4 >> size;
        Val r = s.vop(V_INSELEM, esize, 0, s.V(rd), s.V(rn), kNone, (u64)index | ((u64)src_index << 8));
        s.setV(rd, r);
        return true;
    }
    Builder& ir = s.ir;
    switch (imm4) {
    case 0: {  // DUP (element)
        if (size == 3 && !q) return false;
        s.setV(rd, s.vop(V_DUPELEM, esize, q ? 0 : F_HALF, s.V(rn), kNone, kNone, index));
        return true;
    }
    case 1: {  // DUP (general)
        if (size == 3 && !q) return false;
        Val g = t.X(rn, size == 3 ? Type::I64 : Type::I32);
        Val r = ir.emit(Op::GprToV, Type::V128, g, kNone, kNone, 0, 0, (u8)esize);
        if (!q) r = s.zext(r, 8);
        s.setV(rd, r);
        return true;
    }
    case 3: {  // INS (general)
        Val g = t.X(rn, size == 3 ? Type::I64 : Type::I32);
        s.setV(rd, ir.emit(Op::GprToV, Type::V128, g, s.V(rd), kNone, index, 1, (u8)esize));
        return true;
    }
    case 5: case 7: {  // SMOV / UMOV
        bool sign = imm4 == 5;
        Type ty = q ? Type::I64 : Type::I32;
        if (sign && size >= (q ? 3 : 2)) return false;
        if (!sign && ((q && size != 3) || (!q && size == 3))) return false;
        Val r = ir.emit(Op::VToGpr, ty, s.V(rn), kNone, kNone, index, sign ? 1 : 0, (u8)esize);
        t.setX(rd, r);
        return true;
    }
    default: return false;
    }
}

static bool simd_mod_imm(Translator& t, u32 i) {
    S s(t);
    bool q = bit(i, 30), op = bit(i, 29);
    u32 cmode = bits(i, 15, 12), o2 = bit(i, 11);
    int rd = bits(i, 4, 0);
    u32 imm8 = (bits(i, 18, 16) << 5) | bits(i, 9, 5);
    if (o2) return false;
    if (cmode == 0xf && op && !q) return false;
    u64 imm = expand_simd_imm(op, cmode, imm8);
    bool is_orr_bic = (cmode < 12 && (cmode & 1)) ;
    Val c = s.vconst(imm, q ? imm : 0);
    if (is_orr_bic) {
        Val d = s.V(rd);
        Val r = op ? s.vop(V_BIC, 16, q ? 0 : F_HALF, d, c) : s.vop(V_ORR, 16, q ? 0 : F_HALF, d, c);
        s.setV(rd, r);
        return true;
    }
    if (op && cmode < 14 && !(cmode == 12 || cmode == 13) ) {
        // MVNI
        u64 n = ~imm;
        s.setV(rd, s.vconst(n, q ? n : 0));
        return true;
    }
    if (op && (cmode == 12 || cmode == 13)) {
        u64 n = ~imm;
        s.setV(rd, s.vconst(n, q ? n : 0));
        return true;
    }
    s.setV(rd, c);
    return true;
}

static bool simd_shift_imm(Translator& t, u32 i, bool scalar) {
    S s(t);
    bool q = bit(i, 30), u = bit(i, 29);
    u32 immh = bits(i, 22, 19), immb = bits(i, 18, 16), opcode = bits(i, 15, 11);
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5);
    if (immh == 0) return false;
    int hsb = 31 - __builtin_clz(immh);
    int esize = 1 << hsb;   // bytes
    int ebits = esize * 8;
    int immhb = (immh << 3) | immb;
    int rshift = 2 * ebits - immhb;      // for right shifts
    int lshift = immhb - ebits;          // for left shifts
    u8 fl = scalar ? F_SCALAR : (q ? 0 : F_HALF);
    if (!scalar && hsb == 3 && !q) return false;
    if (scalar && opcode <= 0x0f && hsb != 3 && opcode != 0x0e && opcode != 0x0c) {
        // most scalar shifts require 64-bit elements
        if (opcode != 0x0e && opcode != 0x0c) return false;
    }
    Val a = s.V(rn);
    switch ((u << 5) | opcode) {
    case 0x00: s.setV(rd, s.vop(V_SSHR_I, esize, fl, a, kNone, kNone, rshift)); return true;
    case 0x20: s.setV(rd, s.vop(V_USHR_I, esize, fl, a, kNone, kNone, rshift)); return true;
    case 0x02: s.setV(rd, s.vop(V_SSRA, esize, fl, a, kNone, s.V(rd), rshift)); return true;
    case 0x22: s.setV(rd, s.vop(V_USRA, esize, fl, a, kNone, s.V(rd), rshift)); return true;
    case 0x04: s.setV(rd, s.vop(V_SRSHR_I, esize, fl, a, kNone, kNone, rshift)); return true;
    case 0x24: s.setV(rd, s.vop(V_URSHR_I, esize, fl, a, kNone, kNone, rshift)); return true;
    case 0x06: s.setV(rd, s.vop(V_SRSRA, esize, fl, a, kNone, s.V(rd), rshift)); return true;
    case 0x26: s.setV(rd, s.vop(V_URSRA, esize, fl, a, kNone, s.V(rd), rshift)); return true;
    case 0x28: s.setV(rd, s.vop(V_SRI, esize, fl, a, kNone, s.V(rd), rshift)); return true;
    case 0x0a: s.setV(rd, s.vop(V_SHL_I, esize, fl, a, kNone, kNone, lshift)); return true;
    case 0x2a: s.setV(rd, s.vop(V_SLI, esize, fl, a, kNone, s.V(rd), lshift)); return true;
    case 0x2c: s.setV(rd, s.vop(V_SQSHLU_I, esize, fl, a, kNone, kNone, lshift)); return true;
    case 0x0e: s.setV(rd, s.vop(V_SQSHL_I, esize, fl, a, kNone, kNone, lshift)); return true;
    case 0x2e: s.setV(rd, s.vop(V_UQSHL_I, esize, fl, a, kNone, kNone, lshift)); return true;
    case 0x10: case 0x11: case 0x30: case 0x31: case 0x12: case 0x13: case 0x32: case 0x33: {
        // narrowing shifts: SHRN RSHRN SQSHRUN SQRSHRUN SQSHRN SQRSHRN UQSHRN UQRSHRN
        if (hsb == 3) return false;
        int dsize = esize;          // destination element size
        int src_es = esize * 2;
        int sh = 2 * ebits - immhb; // shift relative to dest ebits... (immh encodes dest size)
        (void)src_es;
        u16 op;
        switch ((u << 5) | opcode) {
        case 0x10: op = V_SHRN; break;
        case 0x11: op = V_RSHRN; break;
        case 0x30: op = V_SQSHRUN; break;
        case 0x31: op = V_SQRSHRUN; break;
        case 0x12: op = V_SQSHRN; break;
        case 0x13: op = V_SQRSHRN; break;
        case 0x32: op = V_UQSHRN; break;
        case 0x33: op = V_UQRSHRN; break;
        default: return false;
        }
        if (scalar && (op == V_SHRN || op == V_RSHRN)) return false;
        Val r = s.vop(op, dsize, scalar ? F_SCALAR : 0, a, kNone, kNone, sh);
        if (!scalar && q) r = s.vop(V_INSELEM, 8, 0, s.V(rd), r, kNone, 1);
        s.setV(rd, r);
        return true;
    }
    case 0x14: case 0x34: {  // SSHLL/USHLL (SXTL/UXTL)
        if (scalar || hsb == 3) return false;
        Val src = q ? s.vop(V_DUPELEM, 8, 0, a, kNone, kNone, 1) : a;
        Val r = s.vop(u ? V_UXTL : V_SXTL, esize, 0, src);   // esize = source element size
        if (lshift) r = s.vop(V_SHL_I, esize * 2, 0, r, kNone, kNone, lshift);
        s.setV(rd, r);
        return true;
    }
    case 0x1c: case 0x3c: {  // SCVTF/UCVTF (fixed)
        if (hsb < 2) return false;
        s.setV(rd, s.vop(u ? V_UCVTF_FIX : V_SCVTF_FIX, esize, fl, a, kNone, kNone, rshift));
        return true;
    }
    case 0x1f: case 0x3f: {  // FCVTZS/FCVTZU (fixed)
        if (hsb < 2) return false;
        s.setV(rd, s.vop(u ? V_FCVTZU_FIX : V_FCVTZS_FIX, esize, fl, a, kNone, kNone, rshift));
        return true;
    }
    default: return false;
    }
}

static bool simd_three_diff(Translator& t, u32 i, bool scalar) {
    S s(t);
    bool q = bit(i, 30), u = bit(i, 29);
    int size = bits(i, 23, 22), opcode = bits(i, 15, 12);
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5), rm = bits(i, 20, 16);
    int esize = 1 << size;
    if (scalar) {
        // scalar SQDMULL / SQDMLAL / SQDMLSL
        if (u || (size != 1 && size != 2)) return false;
        u16 sop = opcode == 0xd ? V_SQDMULL : opcode == 0x9 ? V_SQDMLAL : opcode == 0xb ? V_SQDMLSL : 0;
        if (!sop) return false;
        Val c = sop == V_SQDMULL ? kNone : s.V(rd);
        Val r = s.vop(sop, esize, F_SCALAR, s.V(rn), s.V(rm), c);
        s.setV(rd, s.zext(r, esize * 2));
        return true;
    }
    Val a = s.V(rn), b = s.V(rm);
    // "2" variants operate on upper halves
    auto hi = [&](Val v) { return q ? s.vop(V_DUPELEM, 8, 0, v, kNone, kNone, 1) : v; };
    u16 op;
    bool acc = false, narrow = false, wide = false;
    switch ((u << 4) | opcode) {
    case 0x00: op = V_SADDL; break;
    case 0x01: op = V_SADDW; wide = true; break;
    case 0x02: op = V_SSUBL; break;
    case 0x03: op = V_SSUBW; wide = true; break;
    case 0x04: op = V_ADDHN; narrow = true; break;
    case 0x05: op = V_SABAL; acc = true; break;
    case 0x06: op = V_SUBHN; narrow = true; break;
    case 0x07: op = V_SABDL; break;
    case 0x08: op = V_SMLAL; acc = true; break;
    case 0x09: op = V_SQDMLAL; acc = true; break;
    case 0x0a: op = V_SMLSL; acc = true; break;
    case 0x0b: op = V_SQDMLSL; acc = true; break;
    case 0x0d: op = V_SQDMULL; break;
    case 0x0c: op = V_SMULL; break;
    case 0x0e: op = V_PMULL; break;
    case 0x10: op = V_UADDL; break;
    case 0x11: op = V_UADDW; wide = true; break;
    case 0x12: op = V_USUBL; break;
    case 0x13: op = V_USUBW; wide = true; break;
    case 0x14: op = V_RADDHN; narrow = true; break;
    case 0x15: op = V_UABAL; acc = true; break;
    case 0x16: op = V_RSUBHN; narrow = true; break;
    case 0x17: op = V_UABDL; break;
    case 0x18: op = V_UMLAL; acc = true; break;
    case 0x1a: op = V_UMLSL; acc = true; break;
    case 0x1c: op = V_UMULL; break;
    default: return false;
    }
    if (size == 3 && op != V_PMULL) return false;
    if ((op == V_SQDMULL || op == V_SQDMLAL || op == V_SQDMLSL) && (u || size == 0)) return false;
    if (narrow) {
        Val r = s.vop(op, esize, 0, a, b);   // esize = destination (narrow) element size
        if (q) r = s.vop(V_INSELEM, 8, 0, s.V(rd), r, kNone, 1);
        s.setV(rd, r);
        return true;
    }
    Val c = acc ? s.V(rd) : kNone;
    Val r = wide ? s.vop(op, esize, 0, a, hi(b), c) : s.vop(op, esize, 0, hi(a), hi(b), c);
    s.setV(rd, r);
    return true;
}

static bool simd_indexed(Translator& t, u32 i, bool scalar) {
    S s(t);
    bool q = bit(i, 30), u = bit(i, 29);
    int size = bits(i, 23, 22), opcode = bits(i, 15, 12);
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5);
    int l = bit(i, 21), m = bit(i, 20), h = bit(i, 11);
    int rm = bits(i, 19, 16);
    int index;
    bool fp = (opcode == 0x1 || opcode == 0x5 || opcode == 0x9) && !(u && opcode != 0x9);
    int esize;
    if (fp) {
        if (size == 2) { esize = 4; index = (h << 1) | l; rm |= m << 4; }
        else if (size == 3) { if (l) return false; esize = 8; index = h; rm |= m << 4; }
        else return false;
    } else {
        if (size == 1) { esize = 2; index = (h << 2) | (l << 1) | m; }
        else if (size == 2) { esize = 4; index = (h << 1) | l; rm |= m << 4; }
        else return false;
    }
    u8 fl = scalar ? F_SCALAR : (q ? 0 : F_HALF);
    Val a = s.V(rn);
    Val be = s.vop(V_DUPELEM, esize, 0, s.V(rm), kNone, kNone, index);   // broadcast element
    auto hi = [&](Val v) { return q ? s.vop(V_DUPELEM, 8, 0, v, kNone, kNone, 1) : v; };
    if (fp) {
        u16 op;
        if (opcode == 0x1) op = V_FMLA;
        else if (opcode == 0x5) op = V_FMLS;
        else op = u ? V_FMULX : V_FMUL;
        if (!scalar && esize == 8 && !q) return false;
        Val c = (op == V_FMLA || op == V_FMLS) ? s.V(rd) : kNone;
        s.setV(rd, s.vop(op, esize, fl, a, be, c));
        return true;
    }
    switch ((u << 4) | opcode) {
    case 0x08: if (scalar) return false; s.setV(rd, s.vop(V_MUL, esize, fl, a, be)); return true;
    case 0x10: if (scalar) return false; s.setV(rd, s.vop(V_MLA, esize, fl, a, be, s.V(rd))); return true;
    case 0x14: if (scalar) return false; s.setV(rd, s.vop(V_MLS, esize, fl, a, be, s.V(rd))); return true;
    case 0x0a: if (scalar) return false; s.setV(rd, s.vop(V_SMULL, esize, 0, hi(a), be)); return true;
    case 0x1a: if (scalar) return false; s.setV(rd, s.vop(V_UMULL, esize, 0, hi(a), be)); return true;
    case 0x02: if (scalar) return false; s.setV(rd, s.vop(V_SMLAL, esize, 0, hi(a), be, s.V(rd))); return true;
    case 0x12: if (scalar) return false; s.setV(rd, s.vop(V_UMLAL, esize, 0, hi(a), be, s.V(rd))); return true;
    case 0x06: if (scalar) return false; s.setV(rd, s.vop(V_SMLSL, esize, 0, hi(a), be, s.V(rd))); return true;
    case 0x16: if (scalar) return false; s.setV(rd, s.vop(V_UMLSL, esize, 0, hi(a), be, s.V(rd))); return true;
    case 0x0b: case 0x03: case 0x07: {
        u16 op = opcode == 0xb ? V_SQDMULL : opcode == 0x3 ? V_SQDMLAL : V_SQDMLSL;
        Val c = op == V_SQDMULL ? kNone : s.V(rd);
        if (scalar) { s.setV(rd, s.zext(s.vop(op, esize, F_SCALAR, a, be, c), esize * 2)); return true; }
        s.setV(rd, s.vop(op, esize, 0, hi(a), be, c));
        return true;
    }
    case 0x0c: s.setV(rd, s.vop(V_SQDMULH, esize, fl, a, be)); return true;
    case 0x0d: s.setV(rd, s.vop(V_SQRDMULH, esize, fl, a, be)); return true;
    default: return false;
    }
}

static bool simd_permute(Translator& t, u32 i) {
    S s(t);
    bool q = bit(i, 30);
    int size = bits(i, 23, 22), opcode = bits(i, 14, 12);
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5), rm = bits(i, 20, 16);
    if (size == 3 && !q) return false;
    static const u16 ops[8] = {0, V_UZP1, V_TRN1, V_ZIP1, 0, V_UZP2, V_TRN2, V_ZIP2};
    u16 op = ops[opcode];
    if (!op) return false;
    s.setV(rd, s.vop(op, 1 << size, q ? 0 : F_HALF, s.V(rn), s.V(rm)));
    return true;
}

static bool simd_ext(Translator& t, u32 i) {
    S s(t);
    bool q = bit(i, 30);
    int imm4 = bits(i, 14, 11);
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5), rm = bits(i, 20, 16);
    if (bits(i, 23, 22) != 0 || (!q && imm4 >= 8)) return false;
    s.setV(rd, s.vop(V_EXT, 1, q ? 0 : F_HALF, s.V(rn), s.V(rm), kNone, imm4));
    return true;
}

static bool simd_tbl(Translator& t, u32 i) {
    S s(t);
    bool q = bit(i, 30), op = bit(i, 12);
    int len = bits(i, 14, 13) + 1;
    int rd = bits(i, 4, 0), rn = bits(i, 9, 5), rm = bits(i, 20, 16);
    if (bits(i, 23, 22) != 0) return false;
    // table registers are passed as consecutive values: a = first, imm = count, b = indices, c = old (TBX)
    Val tab[4];
    for (int k = 0; k < len; k++) tab[k] = s.V((rn + k) & 31);
    Val idx = s.V(rm);
    Val old = op ? s.V(rd) : s.vconst(0, 0);
    // chain: TBL over 1..4 registers implemented as a sequence of 16-byte lookups with index offset
    Val acc = old;
    for (int k = 0; k < len; k++) {
        acc = s.vop(V_TBX, 1, 0, tab[k], idx, acc, (u64)(k * 16));
    }
    if (!q) acc = s.zext(acc, 8);
    s.setV(rd, acc);
    return true;
}

static bool simd_crypto_aes(Translator& t, u32 i) {
    S s(t);
    int opcode = bits(i, 16, 12), rd = bits(i, 4, 0), rn = bits(i, 9, 5);
    if (bits(i, 23, 22) != 0) return false;
    switch (opcode) {
    case 4: s.setV(rd, s.vop(V_AESE, 16, 0, s.V(rd), s.V(rn))); return true;
    case 5: s.setV(rd, s.vop(V_AESD, 16, 0, s.V(rd), s.V(rn))); return true;
    case 6: s.setV(rd, s.vop(V_AESMC, 16, 0, s.V(rn))); return true;
    case 7: s.setV(rd, s.vop(V_AESIMC, 16, 0, s.V(rn))); return true;
    default: return false;
    }
}

bool Translator::simd_fp(u32 i) {
    u32 b2824 = bits(i, 28, 24);
    // Scalar floating point (not Advanced SIMD): bit 30 = 0, bits 28:24 = 11110 / 11111
    if (!bit(i, 30) && (b2824 == 0x1E || b2824 == 0x1F)) {
        if (bit(i, 29)) return false;
        return fp_scalar(*this, i);
    }
    bool scalar = bits(i, 31, 30) == 1 && bit(i, 28);
    if (bit(i, 31)) return false;
    if (!scalar && bit(i, 28)) return false;
    u32 b2824s = bits(i, 28, 24);
    // AES: 0100 1110 0010 1000 0xxx 10
    if (bits(i, 31, 24) == 0x4E && bits(i, 21, 17) == 0x14 && bits(i, 11, 10) == 2) return simd_crypto_aes(*this, i);
    if ((b2824s & 0xF) == 0xE) {  // x1110: three same/diff/misc/across/copy/permute/ext/tbl
        if (bit(i, 21)) {
            if (bit(i, 10)) return simd_three_same(*this, i, scalar);
            u32 b1110 = bits(i, 11, 10);
            if (b1110 == 0) return simd_three_diff(*this, i, scalar);
            if (b1110 == 2) {
                u32 b2017 = bits(i, 20, 17);
                if (b2017 == 0) return simd_two_misc(*this, i, scalar);
                if (b2017 == 8) {
                    if (scalar) {
                        // scalar pairwise: ADDP d, FADDP, FMAXP, ...
                        S s(*this);
                        int size = bits(i, 23, 22), opcode = bits(i, 16, 12);
                        bool u = bit(i, 29);
                        int rd = bits(i, 4, 0), rn = bits(i, 9, 5);
                        Val a = s.V(rn);
                        if (!u && opcode == 0x1b && size == 3) { s.setV(rd, s.vop(V_ADDP, 8, F_SCALAR, a, a)); return true; }
                        if (u) {
                            int fsz = (size & 1) ? 8 : 4;
                            u16 op;
                            switch ((opcode << 1) | (size >> 1)) {
                            case (0x0c << 1): op = V_FMAXNMP; break;
                            case (0x0d << 1): op = V_FADDP; break;
                            case (0x0f << 1): op = V_FMAXP; break;
                            case (0x0c << 1) | 1: op = V_FMINNMP; break;
                            case (0x0f << 1) | 1: op = V_FMINP; break;
                            default: return false;
                            }
                            s.setV(rd, s.vop(op, fsz, F_SCALAR, a, a));
                            return true;
                        }
                        return false;
                    }
                    return simd_across(*this, i);
                }
                return false;
            }
            return false;
        }
        // bit21 == 0
        if (!scalar && bits(i, 29, 24) == 0x0E && bits(i, 11, 10) == 2 && !bit(i, 15)) return simd_permute(*this, i);
        if (!scalar && bits(i, 29, 24) == 0x2E && !bit(i, 15) && !bit(i, 10)) return simd_ext(*this, i);
        if (!scalar && bits(i, 29, 24) == 0x0E && bits(i, 11, 10) == 0 && !bit(i, 15)) return simd_tbl(*this, i);
        if (bits(i, 23, 21) == 0 && bit(i, 10) && !bit(i, 15)) {
            if (bits(i, 28, 24) == 0x0E || bits(i, 28, 24) == 0x1E) return simd_copy(*this, i, scalar);
        }
        return false;
    }
    if ((b2824s & 0xF) == 0xF) {  // x1111: shift by immediate / modified immediate / indexed element
        if (!bit(i, 10)) return simd_indexed(*this, i, scalar);
        if (bit(i, 23)) return false;
        if (bits(i, 22, 19) == 0) {
            if (scalar) return false;
            return simd_mod_imm(*this, i);
        }
        return simd_shift_imm(*this, i, scalar);
    }
    return false;
}

}  // namespace xef::a64
