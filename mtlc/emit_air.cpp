// SPIR-V emission of calls: xef.* placeholders, LLVM intrinsics, air.* intrinsics.
#include "emit.h"
#include "third_party/spirv/GLSL.std.450.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/Intrinsics.h"
#include <cmath>

namespace mtlc {
using namespace llvm;
using namespace xef::mtlabi;

static unsigned vlen(Type* t) {
    if (auto* v = dyn_cast<FixedVectorType>(t)) return v->getNumElements();
    return 1;
}

// ---------------- placeholders ----------------

bool Emitter::emit_placeholder(CallInst* ci, StringRef name) {
    Type* t = ci->getType();
    auto cint = [&](unsigned k) -> uint32_t { return (uint32_t)cast<ConstantInt>(ci->getArgOperand(k))->getZExtValue(); };
    if (name.starts_with("xef.pc.table")) {
        Id pc = push_constants();
        Id p = emit_r(spv::OpAccessChain, sb.t_ptr(spv::StorageClassPushConstant, sb.t_int(64)), {pc, c_u32(0), c_u32(ps.table_slot)});
        result(ci, emit_r(spv::OpLoad, sb.t_int(64), {p}));
        return true;
    }
    if (name.starts_with("xef.pc.u32")) {
        Id pc = push_constants();
        uint32_t off = cint(0);
        Words chain;
        if (off >= 16 && off < 28) chain = {c_u32(1), c_u32((off - 16) / 4)};
        else if (off == 28) chain = {c_u32(2)};
        else if (off == 32) chain = {c_u32(3)};
        else chain = {c_u32(4)};
        Words ops{pc}; ops.insert(ops.end(), chain.begin(), chain.end());
        Id p = emit_r(spv::OpAccessChain, sb.t_ptr(spv::StorageClassPushConstant, t_u32()), ops);
        result(ci, emit_r(spv::OpLoad, t_u32(), {p}));
        return true;
    }
    if (name.starts_with("xef.in.builtin")) {
        uint32_t bi = cint(0);
        if (bi == BI_SAMPLE_MASK) {
            Id arr = sb.t_array(t_u32(), 1);
            Id v = builtin_var(false, bi, arr);
            Id p = emit_r(spv::OpAccessChain, sb.t_ptr(spv::StorageClassInput, t_u32()), {v, c_u32(0)});
            result(ci, emit_r(spv::OpLoad, t_u32(), {p}));
            return true;
        }
        Id v = builtin_var(false, bi, ty(t));
        result(ci, emit_r(spv::OpLoad, ty(t), {v}));
        return true;
    }
    if (name.starts_with("xef.in.loc")) {
        Id v = location_var(false, cint(0), 0, cint(1), ty(t));
        result(ci, emit_r(spv::OpLoad, ty(t), {v}));
        return true;
    }
    if (name.starts_with("xef.out.builtin")) {
        uint32_t bi = cint(0);
        Value* x = ci->getArgOperand(1);
        if (bi == BI_FRAG_DEPTH) writes_depth = true;
        if (bi == BI_FRAG_STENCIL_REF) writes_stencil = true;
        if (bi == BI_SAMPLE_MASK) {
            Id arr = sb.t_array(t_u32(), 1);
            Id v = builtin_var(true, bi, arr);
            Id p = emit_r(spv::OpAccessChain, sb.t_ptr(spv::StorageClassOutput, t_u32()), {v, c_u32(0)});
            emit(spv::OpStore, {p, val(x)});
            return true;
        }
        Id v = builtin_var(true, bi, ty(x->getType()));
        if (bi == BI_POSITION && ci->getFunction()) {}
        emit(spv::OpStore, {v, val(x)});
        return true;
    }
    if (name.starts_with("xef.out.loc")) {
        Value* x = ci->getArgOperand(3);
        Id v = location_var(true, cint(0), cint(1), cint(2), ty(x->getType()));
        emit(spv::OpStore, {v, val(x)});
        return true;
    }
    fail("unknown placeholder " + name.str());
    return false;
}

// ---------------- LLVM intrinsics ----------------

bool Emitter::emit_llvm_intrinsic(CallInst* ci) {
    auto* ii = dyn_cast<IntrinsicInst>(ci);
    if (!ii) return false;
    Type* t = ci->getType();
    Id rt = t->isVoidTy() ? 0 : ty(t);
    auto a = [&](unsigned k) { return val(ci->getArgOperand(k)); };
    auto g1 = [&](uint32_t op) { result(ci, ext(rt, op, {a(0)})); return true; };
    auto g2 = [&](uint32_t op) { result(ci, ext(rt, op, {a(0), a(1)})); return true; };
    switch (ii->getIntrinsicID()) {
    case Intrinsic::fabs: return g1(GLSLstd450FAbs);
    case Intrinsic::floor: return g1(GLSLstd450Floor);
    case Intrinsic::ceil: return g1(GLSLstd450Ceil);
    case Intrinsic::trunc: return g1(GLSLstd450Trunc);
    case Intrinsic::round: {   // half away from zero
        Id s = ext(rt, GLSLstd450FSign, {a(0)});
        Id ab = ext(rt, GLSLstd450FAbs, {a(0)});
        Id fl = ext(rt, GLSLstd450Floor, {emit_r(spv::OpFAdd, rt, {ab, const_like(t, 0.5, 0)})});
        result(ci, emit_r(spv::OpFMul, rt, {s, fl}));
        return true;
    }
    case Intrinsic::roundeven: case Intrinsic::rint: case Intrinsic::nearbyint: return g1(GLSLstd450RoundEven);
    case Intrinsic::sqrt: return g1(GLSLstd450Sqrt);
    case Intrinsic::sin: return g1(GLSLstd450Sin);
    case Intrinsic::cos: return g1(GLSLstd450Cos);
    case Intrinsic::tan: return g1(GLSLstd450Tan);
    case Intrinsic::asin: return g1(GLSLstd450Asin);
    case Intrinsic::acos: return g1(GLSLstd450Acos);
    case Intrinsic::atan: return g1(GLSLstd450Atan);
    case Intrinsic::atan2: return g2(GLSLstd450Atan2);
    case Intrinsic::sinh: return g1(GLSLstd450Sinh);
    case Intrinsic::cosh: return g1(GLSLstd450Cosh);
    case Intrinsic::tanh: return g1(GLSLstd450Tanh);
    case Intrinsic::exp: return g1(GLSLstd450Exp);
    case Intrinsic::exp2: return g1(GLSLstd450Exp2);
    case Intrinsic::exp10: result(ci, ext(rt, GLSLstd450Exp2, {emit_r(spv::OpFMul, rt, {a(0), const_like(t, 3.32192809488736234787, 0)})})); return true;
    case Intrinsic::log: return g1(GLSLstd450Log);
    case Intrinsic::log2: return g1(GLSLstd450Log2);
    case Intrinsic::log10: result(ci, emit_r(spv::OpFMul, rt, {ext(rt, GLSLstd450Log2, {a(0)}), const_like(t, 0.301029995663981195, 0)})); return true;
    case Intrinsic::pow: return g2(GLSLstd450Pow);
    case Intrinsic::powi: {
        Id e = emit_r(spv::OpConvertSToF, rt, {a(1)});
        if (vlen(t) > 1) e = splat(t, emit_r(spv::OpConvertSToF, ty(t->getScalarType()), {a(1)}));
        result(ci, ext(rt, GLSLstd450Pow, {a(0), e}));
        return true;
    }
    case Intrinsic::fma: case Intrinsic::fmuladd: result(ci, ext(rt, GLSLstd450Fma, {a(0), a(1), a(2)})); return true;
    case Intrinsic::minnum: case Intrinsic::minimumnum: return g2(GLSLstd450NMin);
    case Intrinsic::maxnum: case Intrinsic::maximumnum: return g2(GLSLstd450NMax);
    case Intrinsic::minimum: return g2(GLSLstd450FMin);
    case Intrinsic::maximum: return g2(GLSLstd450FMax);
    case Intrinsic::copysign: {
        Type* it = t->getScalarType()->isHalfTy() ? Type::getInt16Ty(m.getContext()) : t->getScalarType()->isDoubleTy() ? Type::getInt64Ty(m.getContext()) : Type::getInt32Ty(m.getContext());
        if (auto* vt = dyn_cast<FixedVectorType>(t)) it = FixedVectorType::get(it, vt->getNumElements());
        unsigned bits = it->getScalarSizeInBits();
        Id iti = ty(it);
        Id x = emit_r(spv::OpBitcast, iti, {a(0)});
        Id y = emit_r(spv::OpBitcast, iti, {a(1)});
        Id sign = const_like(it, 0, (int64_t)(1ull << (bits - 1)));
        Id mag = const_like(it, 0, (int64_t)((1ull << (bits - 1)) - 1));
        Id r = emit_r(spv::OpBitwiseOr, iti, {emit_r(spv::OpBitwiseAnd, iti, {x, mag}), emit_r(spv::OpBitwiseAnd, iti, {y, sign})});
        result(ci, emit_r(spv::OpBitcast, rt, {r}));
        return true;
    }
    case Intrinsic::ldexp: result(ci, ext(rt, GLSLstd450Ldexp, {a(0), a(1)})); return true;
    case Intrinsic::smin: return g2(GLSLstd450SMin);
    case Intrinsic::smax: return g2(GLSLstd450SMax);
    case Intrinsic::umin: return g2(GLSLstd450UMin);
    case Intrinsic::umax: return g2(GLSLstd450UMax);
    case Intrinsic::abs: return g1(GLSLstd450SAbs);
    case Intrinsic::ctpop: {
        unsigned w = t->getScalarSizeInBits();
        if (w == 32) { result(ci, emit_r(spv::OpBitCount, rt, {a(0)})); return true; }
        Type* i32t = vlen(t) > 1 ? (Type*)FixedVectorType::get(Type::getInt32Ty(m.getContext()), vlen(t)) : Type::getInt32Ty(m.getContext());
        if (w < 32) {
            Id x = emit_r(spv::OpUConvert, ty(i32t), {a(0)});
            result(ci, emit_r(spv::OpUConvert, rt, {emit_r(spv::OpBitCount, ty(i32t), {x})}));
            return true;
        }
        // 64-bit: popcount of both halves
        Id lo = emit_r(spv::OpUConvert, ty(i32t), {a(0)});
        Id hi = emit_r(spv::OpUConvert, ty(i32t), {emit_r(spv::OpShiftRightLogical, rt, {a(0), const_like(t, 0, 32)})});
        Id s = emit_r(spv::OpIAdd, ty(i32t), {emit_r(spv::OpBitCount, ty(i32t), {lo}), emit_r(spv::OpBitCount, ty(i32t), {hi})});
        result(ci, emit_r(spv::OpUConvert, rt, {s}));
        return true;
    }
    case Intrinsic::ctlz: case Intrinsic::cttz: {
        unsigned w = t->getScalarSizeInBits();
        if (w > 32) { fail("64-bit ctlz/cttz"); return true; }
        Type* i32t = vlen(t) > 1 ? (Type*)FixedVectorType::get(Type::getInt32Ty(m.getContext()), vlen(t)) : Type::getInt32Ty(m.getContext());
        Id it = ty(i32t);
        Id x = w == 32 ? a(0) : emit_r(spv::OpUConvert, it, {a(0)});
        Id r;
        if (ii->getIntrinsicID() == Intrinsic::ctlz) {
            Id msb = ext(it, GLSLstd450FindUMsb, {x});   // -1 for zero
            r = emit_r(spv::OpISub, it, {const_like(i32t, 0, (int64_t)w - 1), msb});
        } else {
            Id lsb = ext(it, GLSLstd450FindILsb, {x});
            Id zero = emit_r(spv::OpIEqual, ty(vlen(t) > 1 ? (Type*)FixedVectorType::get(Type::getInt1Ty(m.getContext()), vlen(t)) : Type::getInt1Ty(m.getContext())), {x, const_like(i32t, 0, 0)});
            r = emit_r(spv::OpSelect, it, {zero, const_like(i32t, 0, w), lsb});
        }
        result(ci, w == 32 ? r : emit_r(spv::OpUConvert, rt, {r}));
        return true;
    }
    case Intrinsic::bitreverse: {
        unsigned w = t->getScalarSizeInBits();
        if (w == 32) { result(ci, emit_r(spv::OpBitReverse, rt, {a(0)})); return true; }
        if (w < 32) {
            Type* i32t = vlen(t) > 1 ? (Type*)FixedVectorType::get(Type::getInt32Ty(m.getContext()), vlen(t)) : Type::getInt32Ty(m.getContext());
            Id x = emit_r(spv::OpUConvert, ty(i32t), {a(0)});
            Id r = emit_r(spv::OpShiftRightLogical, ty(i32t), {emit_r(spv::OpBitReverse, ty(i32t), {x}), const_like(i32t, 0, 32 - w)});
            result(ci, emit_r(spv::OpUConvert, rt, {r}));
            return true;
        }
        fail("64-bit bitreverse");
        return true;
    }
    case Intrinsic::bswap: {
        unsigned w = t->getScalarSizeInBits();
        Id x = a(0);
        Id r = const_like(t, 0, 0);
        for (unsigned byte = 0; byte < w / 8; byte++) {
            Id sh = emit_r(spv::OpShiftRightLogical, rt, {x, const_like(t, 0, byte * 8)});
            Id bb = emit_r(spv::OpBitwiseAnd, rt, {sh, const_like(t, 0, 0xff)});
            Id pl = emit_r(spv::OpShiftLeftLogical, rt, {bb, const_like(t, 0, (w / 8 - 1 - byte) * 8)});
            r = emit_r(spv::OpBitwiseOr, rt, {r, pl});
        }
        result(ci, r);
        return true;
    }
    case Intrinsic::fshl: case Intrinsic::fshr: {
        unsigned w = t->getScalarSizeInBits();
        Id sh = emit_r(spv::OpUMod, rt, {a(2), const_like(t, 0, w)});
        Id inv = emit_r(spv::OpISub, rt, {const_like(t, 0, w), sh});
        Id r;
        if (ii->getIntrinsicID() == Intrinsic::fshl) {
            Id hi = emit_r(spv::OpShiftLeftLogical, rt, {a(0), sh});
            Id lo = emit_r(spv::OpShiftRightLogical, rt, {a(1), inv});
            r = emit_r(spv::OpBitwiseOr, rt, {hi, lo});
            Id z = emit_r(spv::OpIEqual, ty(vlen(t) > 1 ? (Type*)FixedVectorType::get(Type::getInt1Ty(m.getContext()), vlen(t)) : Type::getInt1Ty(m.getContext())), {sh, const_like(t, 0, 0)});
            r = emit_r(spv::OpSelect, rt, {z, a(0), r});
        } else {
            Id lo = emit_r(spv::OpShiftRightLogical, rt, {a(1), sh});
            Id hi = emit_r(spv::OpShiftLeftLogical, rt, {a(0), inv});
            r = emit_r(spv::OpBitwiseOr, rt, {hi, lo});
            Id z = emit_r(spv::OpIEqual, ty(vlen(t) > 1 ? (Type*)FixedVectorType::get(Type::getInt1Ty(m.getContext()), vlen(t)) : Type::getInt1Ty(m.getContext())), {sh, const_like(t, 0, 0)});
            r = emit_r(spv::OpSelect, rt, {z, a(1), r});
        }
        result(ci, r);
        return true;
    }
    case Intrinsic::uadd_sat: {
        Id s = emit_r(spv::OpIAdd, rt, {a(0), a(1)});
        Id ov = emit_r(spv::OpULessThan, ty(t->isVectorTy() ? (Type*)FixedVectorType::get(Type::getInt1Ty(m.getContext()), vlen(t)) : Type::getInt1Ty(m.getContext())), {s, a(0)});
        result(ci, emit_r(spv::OpSelect, rt, {ov, const_like(t, 0, -1), s}));
        return true;
    }
    case Intrinsic::usub_sat: {
        Id gt = emit_r(spv::OpUGreaterThan, ty(t->isVectorTy() ? (Type*)FixedVectorType::get(Type::getInt1Ty(m.getContext()), vlen(t)) : Type::getInt1Ty(m.getContext())), {a(1), a(0)});
        result(ci, emit_r(spv::OpSelect, rt, {gt, const_like(t, 0, 0), emit_r(spv::OpISub, rt, {a(0), a(1)})}));
        return true;
    }
    case Intrinsic::sadd_sat: case Intrinsic::ssub_sat: {
        // widen, clamp, narrow
        unsigned w = t->getScalarSizeInBits();
        if (w >= 64) { fail("64-bit saturating add"); return true; }
        Type* wt = IntegerType::get(m.getContext(), w * 2 > 32 ? 64 : 32);
        if (auto* vt = dyn_cast<FixedVectorType>(t)) wt = FixedVectorType::get(wt, vt->getNumElements());
        Id x = emit_r(spv::OpSConvert, ty(wt), {a(0)});
        Id y = emit_r(spv::OpSConvert, ty(wt), {a(1)});
        Id s = emit_r(ii->getIntrinsicID() == Intrinsic::sadd_sat ? spv::OpIAdd : spv::OpISub, ty(wt), {x, y});
        int64_t mx = (1ll << (w - 1)) - 1, mn = -(1ll << (w - 1));
        Id c = ext(ty(wt), GLSLstd450SClamp, {s, const_like(wt, 0, mn), const_like(wt, 0, mx)});
        result(ci, emit_r(spv::OpSConvert, rt, {c}));
        return true;
    }
    case Intrinsic::uadd_with_overflow: case Intrinsic::usub_with_overflow: {
        Type* et = cast<StructType>(t)->getElementType(0);
        Id st = sb.t_struct({ty(et), ty(et)});
        Id r = emit_r(ii->getIntrinsicID() == Intrinsic::uadd_with_overflow ? spv::OpIAddCarry : spv::OpISubBorrow, st, {a(0), a(1)});
        Id v = emit_r(spv::OpCompositeExtract, ty(et), {r, 0});
        Id c = emit_r(spv::OpCompositeExtract, ty(et), {r, 1});
        Type* bt = cast<StructType>(t)->getElementType(1);
        Id cb = emit_r(spv::OpINotEqual, ty(bt), {c, const_like(et, 0, 0)});
        result(ci, emit_r(spv::OpCompositeConstruct, rt, {v, cb}));
        return true;
    }
    case Intrinsic::umul_with_overflow: case Intrinsic::smul_with_overflow: {
        Type* et = cast<StructType>(t)->getElementType(0);
        Id st = sb.t_struct({ty(et), ty(et)});
        Id r = emit_r(ii->getIntrinsicID() == Intrinsic::umul_with_overflow ? spv::OpUMulExtended : spv::OpSMulExtended, st, {a(0), a(1)});
        Id lo = emit_r(spv::OpCompositeExtract, ty(et), {r, 0});
        Id hi = emit_r(spv::OpCompositeExtract, ty(et), {r, 1});
        Type* bt = cast<StructType>(t)->getElementType(1);
        Id ov = emit_r(spv::OpINotEqual, ty(bt), {hi, const_like(et, 0, 0)});
        result(ci, emit_r(spv::OpCompositeConstruct, rt, {lo, ov}));
        return true;
    }
    case Intrinsic::is_fpclass: {
        uint32_t test = (uint32_t)cast<ConstantInt>(ci->getArgOperand(1))->getZExtValue();
        Id bt = rt;
        Id x = a(0);
        Id r = 0;
        auto orr = [&](Id v) { r = r ? emit_r(spv::OpLogicalOr, bt, {r, v}) : v; };
        if (test & fcNan) orr(emit_r(spv::OpIsNan, bt, {x}));
        if ((test & fcInf) == fcInf) orr(emit_r(spv::OpIsInf, bt, {x}));
        else if (test & fcPosInf) orr(emit_r(spv::OpLogicalAnd, bt, {emit_r(spv::OpIsInf, bt, {x}), emit_r(spv::OpFOrdGreaterThan, bt, {x, const_like(ci->getArgOperand(0)->getType(), 0, 0)})}));
        else if (test & fcNegInf) orr(emit_r(spv::OpLogicalAnd, bt, {emit_r(spv::OpIsInf, bt, {x}), emit_r(spv::OpFOrdLessThan, bt, {x, const_like(ci->getArgOperand(0)->getType(), 0, 0)})}));
        if ((test & fcFinite) == fcFinite)
            orr(emit_r(spv::OpLogicalNot, bt, {emit_r(spv::OpLogicalOr, bt, {emit_r(spv::OpIsNan, bt, {x}), emit_r(spv::OpIsInf, bt, {x})})}));
        else if (test & fcZero)
            orr(emit_r(spv::OpFOrdEqual, bt, {x, const_like(ci->getArgOperand(0)->getType(), 0, 0)}));
        if (!r) r = const_like(t, 0, 0);
        result(ci, r);
        return true;
    }
    case Intrinsic::vector_reduce_add: case Intrinsic::vector_reduce_mul: case Intrinsic::vector_reduce_and:
    case Intrinsic::vector_reduce_or: case Intrinsic::vector_reduce_xor: case Intrinsic::vector_reduce_smax:
    case Intrinsic::vector_reduce_smin: case Intrinsic::vector_reduce_umax: case Intrinsic::vector_reduce_umin:
    case Intrinsic::vector_reduce_fmax: case Intrinsic::vector_reduce_fmin: case Intrinsic::vector_reduce_fadd:
    case Intrinsic::vector_reduce_fmul: {
        Intrinsic::ID id = ii->getIntrinsicID();
        bool fold_start = id == Intrinsic::vector_reduce_fadd || id == Intrinsic::vector_reduce_fmul;
        Value* vec = ci->getArgOperand(fold_start ? 1 : 0);
        unsigned n = vlen(vec->getType());
        Id v = val(vec);
        Id acc = fold_start ? a(0) : 0;
        bool isb = t->isIntegerTy(1);
        for (unsigned k = 0; k < n; k++) {
            Id e = n == 1 ? v : emit_r(spv::OpCompositeExtract, rt, {v, k});
            if (!acc) { acc = e; continue; }
            switch (id) {
            case Intrinsic::vector_reduce_add: acc = emit_r(isb ? spv::OpLogicalNotEqual : spv::OpIAdd, rt, {acc, e}); break;
            case Intrinsic::vector_reduce_mul: acc = emit_r(spv::OpIMul, rt, {acc, e}); break;
            case Intrinsic::vector_reduce_and: acc = emit_r(isb ? spv::OpLogicalAnd : spv::OpBitwiseAnd, rt, {acc, e}); break;
            case Intrinsic::vector_reduce_or: acc = emit_r(isb ? spv::OpLogicalOr : spv::OpBitwiseOr, rt, {acc, e}); break;
            case Intrinsic::vector_reduce_xor: acc = emit_r(isb ? spv::OpLogicalNotEqual : spv::OpBitwiseXor, rt, {acc, e}); break;
            case Intrinsic::vector_reduce_smax: acc = ext(rt, GLSLstd450SMax, {acc, e}); break;
            case Intrinsic::vector_reduce_smin: acc = ext(rt, GLSLstd450SMin, {acc, e}); break;
            case Intrinsic::vector_reduce_umax: acc = ext(rt, GLSLstd450UMax, {acc, e}); break;
            case Intrinsic::vector_reduce_umin: acc = ext(rt, GLSLstd450UMin, {acc, e}); break;
            case Intrinsic::vector_reduce_fmax: acc = ext(rt, GLSLstd450NMax, {acc, e}); break;
            case Intrinsic::vector_reduce_fmin: acc = ext(rt, GLSLstd450NMin, {acc, e}); break;
            case Intrinsic::vector_reduce_fadd: acc = emit_r(spv::OpFAdd, rt, {acc, e}); break;
            case Intrinsic::vector_reduce_fmul: acc = emit_r(spv::OpFMul, rt, {acc, e}); break;
            default: break;
            }
        }
        result(ci, acc);
        return true;
    }
    case Intrinsic::fptosi_sat: case Intrinsic::fptoui_sat: {
        bool sgn = ii->getIntrinsicID() == Intrinsic::fptosi_sat;
        unsigned w = t->getScalarSizeInBits();
        Type* ft = ci->getArgOperand(0)->getType();
        double lo = sgn ? -std::ldexp(1.0, (int)w - 1) : 0.0;
        double hi = sgn ? std::ldexp(1.0, (int)w - 1) - 1 : std::ldexp(1.0, (int)w) - 1;
        Id c = ext(ty(ft), GLSLstd450NClamp, {a(0), const_like(ft, lo, 0), const_like(ft, hi, 0)});
        result(ci, emit_r(sgn ? spv::OpConvertFToS : spv::OpConvertFToU, rt, {c}));
        return true;
    }
    case Intrinsic::expect: case Intrinsic::ssa_copy:
        result(ci, a(0));
        return true;
    case Intrinsic::is_constant:
        result(ci, sb.const_bool(false));
        return true;
    case Intrinsic::lifetime_start: case Intrinsic::lifetime_end: case Intrinsic::assume: case Intrinsic::donothing:
    case Intrinsic::experimental_noalias_scope_decl: case Intrinsic::dbg_value: case Intrinsic::dbg_declare: case Intrinsic::dbg_label:
    case Intrinsic::invariant_start: case Intrinsic::invariant_end:
        return true;
    default:
        fail("unsupported LLVM intrinsic " + ci->getCalledFunction()->getName().str());
        return true;
    }
}

// ---------------- calls ----------------

void Emitter::emit_call(CallInst* ci) {
    Function* callee = ci->getCalledFunction();
    if (!callee) { fail("indirect call"); return; }
    StringRef name = callee->getName();
    if (name.starts_with("xef.")) { emit_placeholder(ci, name); return; }
    if (name.starts_with("llvm.")) { emit_llvm_intrinsic(ci); return; }
    if (name.starts_with("air.")) {
        if (!emit_air(ci, name) && !failed) fail("unsupported AIR intrinsic " + name.str());
        return;
    }
    fail("call to unknown function " + name.str());
}

// strips "air." and "fast_"/"precise_"; returns the op name (up to the first '.')
static StringRef air_op(StringRef name, bool* fast = nullptr) {
    StringRef s = name.drop_front(4);
    if (s.consume_front("fast_")) { if (fast) *fast = true; }
    else s.consume_front("precise_");
    return s.split('.').first;
}

bool Emitter::emit_air(CallInst* ci, StringRef name) {
    StringRef op = air_op(name);
    Type* t = ci->getType();
    Id rt = t->isVoidTy() ? 0 : ty(t);
    unsigned na = ci->arg_size();
    auto a = [&](unsigned k) { return val(ci->getArgOperand(k)); };
    auto at = [&](unsigned k) { return ci->getArgOperand(k)->getType(); };
    auto g = [&](uint32_t gop, std::initializer_list<unsigned> args) {
        Words w; for (unsigned k : args) w.push_back(a(k));
        result(ci, ext(rt, gop, w));
        return true;
    };
    auto bool_ty_like = [&](Type* x) -> Type* {
        if (auto* v = dyn_cast<FixedVectorType>(x)) return FixedVectorType::get(Type::getInt1Ty(m.getContext()), v->getNumElements());
        return Type::getInt1Ty(m.getContext());
    };

    // textures / samplers
    if (op.starts_with("sample") || op.starts_with("gather") || op.starts_with("read_") || op.starts_with("write_") ||
        op.starts_with("get_width") || op.starts_with("get_height") || op.starts_with("get_depth") ||
        op.starts_with("get_array_size") || op.starts_with("get_num_mip_levels") || op.starts_with("get_num_samples_") ||
        op.starts_with("calculate_") || op.starts_with("fence_") || (op.starts_with("atomic_") && op.contains("_explicit_texture")) ||
        op.starts_with("atomic_compare_exchange"))
        return emit_air_texture(ci, name);
    if (op.starts_with("simd") || op.starts_with("quad") || op == "is_uniform")
        return emit_air_simd(ci, name);

    // ---- float math ----
    if (op == "fabs") return g(GLSLstd450FAbs, {0});
    if (op == "floor") return g(GLSLstd450Floor, {0});
    if (op == "ceil") return g(GLSLstd450Ceil, {0});
    if (op == "trunc") return g(GLSLstd450Trunc, {0});
    if (op == "rint") return g(GLSLstd450RoundEven, {0});
    if (op == "round") {
        Id s = ext(rt, GLSLstd450FSign, {a(0)});
        Id ab = ext(rt, GLSLstd450FAbs, {a(0)});
        Id fl = ext(rt, GLSLstd450Floor, {emit_r(spv::OpFAdd, rt, {ab, const_like(t, 0.5, 0)})});
        result(ci, emit_r(spv::OpFMul, rt, {s, fl}));
        return true;
    }
    if (op == "fract") {
        Id fr = ext(rt, GLSLstd450Fract, {a(0)});
        result(ci, ext(rt, GLSLstd450NMin, {fr, const_like(t, t->getScalarType()->isHalfTy() ? 0.99951171875 : 0.99999994039535522461, 0)}));
        return true;
    }
    if (op == "sqrt") return g(GLSLstd450Sqrt, {0});
    if (op == "rsqrt") return g(GLSLstd450InverseSqrt, {0});
    if (op == "exp") return g(GLSLstd450Exp, {0});
    if (op == "exp2") return g(GLSLstd450Exp2, {0});
    if (op == "exp10") { result(ci, ext(rt, GLSLstd450Exp2, {emit_r(spv::OpFMul, rt, {a(0), const_like(t, 3.32192809488736234787, 0)})})); return true; }
    if (op == "log") return g(GLSLstd450Log, {0});
    if (op == "log2") return g(GLSLstd450Log2, {0});
    if (op == "log10") { result(ci, emit_r(spv::OpFMul, rt, {ext(rt, GLSLstd450Log2, {a(0)}), const_like(t, 0.301029995663981195, 0)})); return true; }
    if (op == "pow" || op == "powr") return g(GLSLstd450Pow, {0, 1});
    if (op == "sin") return g(GLSLstd450Sin, {0});
    if (op == "cos") return g(GLSLstd450Cos, {0});
    if (op == "tan") return g(GLSLstd450Tan, {0});
    if (op == "asin") return g(GLSLstd450Asin, {0});
    if (op == "acos") return g(GLSLstd450Acos, {0});
    if (op == "atan") return g(GLSLstd450Atan, {0});
    if (op == "atan2") return g(GLSLstd450Atan2, {0, 1});
    if (op == "sinh") return g(GLSLstd450Sinh, {0});
    if (op == "cosh") return g(GLSLstd450Cosh, {0});
    if (op == "tanh") return g(GLSLstd450Tanh, {0});
    if (op == "asinh") return g(GLSLstd450Asinh, {0});
    if (op == "acosh") return g(GLSLstd450Acosh, {0});
    if (op == "atanh") return g(GLSLstd450Atanh, {0});
    if (op == "sinpi" || op == "cospi" || op == "tanpi") {
        Id x = emit_r(spv::OpFMul, rt, {a(0), const_like(t, M_PI, 0)});
        result(ci, ext(rt, op == "sinpi" ? GLSLstd450Sin : op == "cospi" ? GLSLstd450Cos : GLSLstd450Tan, {x}));
        return true;
    }
    if (op == "sincos") { fail("sincos"); return true; }
    if (op == "fmin") return g(GLSLstd450NMin, {0, 1});
    if (op == "fmax") return g(GLSLstd450NMax, {0, 1});
    if (op == "fmin3") { result(ci, ext(rt, GLSLstd450NMin, {ext(rt, GLSLstd450NMin, {a(0), a(1)}), a(2)})); return true; }
    if (op == "fmax3") { result(ci, ext(rt, GLSLstd450NMax, {ext(rt, GLSLstd450NMax, {a(0), a(1)}), a(2)})); return true; }
    if (op == "fmedian3") {
        Id mn = ext(rt, GLSLstd450NMin, {a(0), a(1)});
        Id mx = ext(rt, GLSLstd450NMax, {a(0), a(1)});
        result(ci, ext(rt, GLSLstd450NMax, {mn, ext(rt, GLSLstd450NMin, {mx, a(2)})}));
        return true;
    }
    if (op == "fmod") { result(ci, emit_r(spv::OpFRem, rt, {a(0), a(1)})); return true; }
    if (op == "fdim") { result(ci, ext(rt, GLSLstd450NMax, {emit_r(spv::OpFSub, rt, {a(0), a(1)}), const_like(t, 0, 0)})); return true; }
    if (op == "fma" || op == "mad") return g(GLSLstd450Fma, {0, 1, 2});
    if (op == "copysign") {
        Value* xv = ci->getArgOperand(0);
        Type* it = t->getScalarType()->isHalfTy() ? Type::getInt16Ty(m.getContext()) : Type::getInt32Ty(m.getContext());
        if (auto* vt = dyn_cast<FixedVectorType>(t)) it = FixedVectorType::get(it, vt->getNumElements());
        unsigned bits = it->getScalarSizeInBits();
        Id x = emit_r(spv::OpBitcast, ty(it), {val(xv)});
        Id y = emit_r(spv::OpBitcast, ty(it), {a(1)});
        Id r = emit_r(spv::OpBitwiseOr, ty(it), {emit_r(spv::OpBitwiseAnd, ty(it), {x, const_like(it, 0, (int64_t)((1ull << (bits - 1)) - 1))}),
                                                emit_r(spv::OpBitwiseAnd, ty(it), {y, const_like(it, 0, (int64_t)(1ull << (bits - 1)))})});
        result(ci, emit_r(spv::OpBitcast, rt, {r}));
        return true;
    }
    if (op == "ldexp") return g(GLSLstd450Ldexp, {0, 1});
    if (op == "step") return g(GLSLstd450Step, {0, 1});
    if (op == "smoothstep") return g(GLSLstd450SmoothStep, {0, 1, 2});
    if (op == "mix") return g(GLSLstd450FMix, {0, 1, 2});
    if (op == "clamp" && t->getScalarType()->isFloatingPointTy()) return g(GLSLstd450NClamp, {0, 1, 2});
    if (op == "saturate") { result(ci, ext(rt, GLSLstd450NClamp, {a(0), const_like(t, 0, 0), const_like(t, 1, 0)})); return true; }
    if (op == "sign") return g(GLSLstd450FSign, {0});
    if (op == "dot") {
        if (vlen(at(0)) == 1) { result(ci, emit_r(spv::OpFMul, rt, {a(0), a(1)})); return true; }
        result(ci, emit_r(spv::OpDot, rt, {a(0), a(1)}));
        return true;
    }
    if (op == "cross") return g(GLSLstd450Cross, {0, 1});
    if (op == "length") { if (vlen(at(0)) == 1) return g(GLSLstd450FAbs, {0}); return g(GLSLstd450Length, {0}); }
    if (op == "distance") return g(GLSLstd450Distance, {0, 1});
    if (op == "normalize") return g(GLSLstd450Normalize, {0});
    if (op == "reflect") return g(GLSLstd450Reflect, {0, 1});
    if (op == "refract") return g(GLSLstd450Refract, {0, 1, 2});
    if (op == "faceforward") return g(GLSLstd450FaceForward, {0, 1, 2});
    if (op == "isnan") { result(ci, convert_numeric_ids(emit_r(spv::OpIsNan, ty(bool_ty_like(at(0))), {a(0)}), bool_ty_like(at(0)), t, false)); return true; }
    if (op == "isinf") { result(ci, convert_numeric_ids(emit_r(spv::OpIsInf, ty(bool_ty_like(at(0))), {a(0)}), bool_ty_like(at(0)), t, false)); return true; }
    if (op == "isfinite") {
        Id bt = ty(bool_ty_like(at(0)));
        Id r = emit_r(spv::OpLogicalNot, bt, {emit_r(spv::OpLogicalOr, bt, {emit_r(spv::OpIsNan, bt, {a(0)}), emit_r(spv::OpIsInf, bt, {a(0)})})});
        result(ci, convert_numeric_ids(r, bool_ty_like(at(0)), t, false));
        return true;
    }
    if (op == "signbit") {
        Id bt = ty(bool_ty_like(at(0)));   // (OpSignBitSet is Kernel-only)
        Type* it = at(0)->getScalarType()->isHalfTy() ? Type::getInt16Ty(m.getContext()) : Type::getInt32Ty(m.getContext());
        if (auto* vt = dyn_cast<FixedVectorType>(at(0))) it = FixedVectorType::get(it, vt->getNumElements());
        Id x = emit_r(spv::OpBitcast, ty(it), {a(0)});
        Id r = emit_r(spv::OpSLessThan, bt, {x, const_like(it, 0, 0)});
        result(ci, convert_numeric_ids(r, bool_ty_like(at(0)), t, false));
        return true;
    }
    if (op == "select") { result(ci, emit_r(spv::OpSelect, rt, {to_bool(ci->getArgOperand(2)), a(1), a(0)})); return true; }
    if (op == "any" || op == "all") {
        Value* x = ci->getArgOperand(0);
        Id b = to_bool(x);
        Id r = vlen(x->getType()) == 1 ? b : emit_r(op == "any" ? spv::OpAny : spv::OpAll, sb.t_bool(), {b});
        result(ci, convert_numeric_ids(r, Type::getInt1Ty(m.getContext()), t, false));
        return true;
    }
    if (op == "dfdx" || op == "dfdy" || op == "fwidth" || op == "dfdx_coarse" || op == "dfdy_coarse" || op == "dfdx_fine" || op == "dfdy_fine") {
        spv::Op o = op == "dfdx" ? spv::OpDPdx : op == "dfdy" ? spv::OpDPdy : op == "fwidth" ? spv::OpFwidth :
                    op == "dfdx_coarse" ? spv::OpDPdxCoarse : op == "dfdy_coarse" ? spv::OpDPdyCoarse : op == "dfdx_fine" ? spv::OpDPdxFine : spv::OpDPdyFine;
        if (o != spv::OpDPdx && o != spv::OpDPdy && o != spv::OpFwidth) sb.cap(spv::CapabilityDerivativeControl);
        if (!fragment) { result(ci, const_like(t, 0, 0)); return true; }
        Type* et = t->getScalarType();
        if (et->isHalfTy()) {   // derivatives on 32-bit
            Type* ft = vlen(t) > 1 ? (Type*)FixedVectorType::get(Type::getFloatTy(m.getContext()), vlen(t)) : Type::getFloatTy(m.getContext());
            Id x = emit_r(spv::OpFConvert, ty(ft), {a(0)});
            result(ci, emit_r(spv::OpFConvert, rt, {emit_r(o, ty(ft), {x})}));
            return true;
        }
        result(ci, emit_r(o, rt, {a(0)}));
        return true;
    }
    // ---- integer ----
    bool sgn = name.contains(".s.");
    if (op == "abs") return g(GLSLstd450SAbs, {0});
    if (op == "absdiff" || op == "abs_diff") {
        Id mx = ext(rt, sgn ? GLSLstd450SMax : GLSLstd450UMax, {a(0), a(1)});
        Id mn = ext(rt, sgn ? GLSLstd450SMin : GLSLstd450UMin, {a(0), a(1)});
        result(ci, emit_r(spv::OpISub, rt, {mx, mn}));
        return true;
    }
    if (op == "min") { if (t->getScalarType()->isFloatingPointTy()) return g(GLSLstd450NMin, {0, 1}); return g(sgn ? GLSLstd450SMin : GLSLstd450UMin, {0, 1}); }
    if (op == "max") { if (t->getScalarType()->isFloatingPointTy()) return g(GLSLstd450NMax, {0, 1}); return g(sgn ? GLSLstd450SMax : GLSLstd450UMax, {0, 1}); }
    if (op == "min3" || op == "max3") {
        uint32_t o = op == "min3" ? (sgn ? GLSLstd450SMin : GLSLstd450UMin) : (sgn ? GLSLstd450SMax : GLSLstd450UMax);
        result(ci, ext(rt, o, {ext(rt, o, {a(0), a(1)}), a(2)}));
        return true;
    }
    if (op == "clamp") return g(sgn ? GLSLstd450SClamp : GLSLstd450UClamp, {0, 1, 2});
    if (op == "popcount") {
        unsigned w = t->getScalarSizeInBits();
        if (w == 32) { result(ci, emit_r(spv::OpBitCount, rt, {a(0)})); return true; }
        Type* i32t = vlen(t) > 1 ? (Type*)FixedVectorType::get(Type::getInt32Ty(m.getContext()), vlen(t)) : Type::getInt32Ty(m.getContext());
        Id x = emit_r(spv::OpUConvert, ty(i32t), {a(0)});
        result(ci, emit_r(spv::OpUConvert, rt, {emit_r(spv::OpBitCount, ty(i32t), {x})}));
        return true;
    }
    if (op == "clz" || op == "ctz") {
        unsigned w = t->getScalarSizeInBits();
        Type* i32t = vlen(t) > 1 ? (Type*)FixedVectorType::get(Type::getInt32Ty(m.getContext()), vlen(t)) : Type::getInt32Ty(m.getContext());
        Id it = ty(i32t);
        Id x = w == 32 ? a(0) : emit_r(spv::OpUConvert, it, {a(0)});
        Id r;
        if (op == "clz") r = emit_r(spv::OpISub, it, {const_like(i32t, 0, (int64_t)w - 1), ext(it, GLSLstd450FindUMsb, {x})});
        else {
            Id z = emit_r(spv::OpIEqual, ty(bool_ty_like(i32t)), {x, const_like(i32t, 0, 0)});
            r = emit_r(spv::OpSelect, it, {z, const_like(i32t, 0, w), ext(it, GLSLstd450FindILsb, {x})});
        }
        result(ci, w == 32 ? r : emit_r(spv::OpUConvert, rt, {r}));
        return true;
    }
    if (op == "reverse_bits") {
        if (t->getScalarSizeInBits() == 32) { result(ci, emit_r(spv::OpBitReverse, rt, {a(0)})); return true; }
        fail("reverse_bits width");
        return true;
    }
    if (op == "mul_hi") {
        Id st = sb.t_struct({rt, rt});
        Id r = emit_r(sgn ? spv::OpSMulExtended : spv::OpUMulExtended, st, {a(0), a(1)});
        result(ci, emit_r(spv::OpCompositeExtract, rt, {r, 1}));
        return true;
    }
    if (op == "add_sat" || op == "sub_sat") {
        unsigned w = t->getScalarSizeInBits();
        Type* wt = IntegerType::get(m.getContext(), w < 32 ? 32 : 64);
        if (auto* vt = dyn_cast<FixedVectorType>(t)) wt = FixedVectorType::get(wt, vt->getNumElements());
        Id x = emit_r(sgn ? spv::OpSConvert : spv::OpUConvert, ty(wt), {a(0)});
        Id y = emit_r(sgn ? spv::OpSConvert : spv::OpUConvert, ty(wt), {a(1)});
        Id s = emit_r(op == "add_sat" ? spv::OpIAdd : spv::OpISub, ty(wt), {x, y});
        int64_t mx = sgn ? (1ll << (w - 1)) - 1 : (int64_t)((w >= 63) ? -1 : ((1ll << w) - 1));
        int64_t mn = sgn ? -(1ll << (w - 1)) : 0;
        Id c = ext(ty(wt), sgn ? GLSLstd450SClamp : GLSLstd450SClamp, {s, const_like(wt, 0, mn), const_like(wt, 0, mx)});
        result(ci, emit_r(sgn ? spv::OpSConvert : spv::OpUConvert, rt, {c}));
        return true;
    }
    if (op == "rotate") {
        unsigned w = t->getScalarSizeInBits();
        Id sh = emit_r(spv::OpUMod, rt, {a(1), const_like(t, 0, w)});
        Id l = emit_r(spv::OpShiftLeftLogical, rt, {a(0), sh});
        Id r = emit_r(spv::OpShiftRightLogical, rt, {a(0), emit_r(spv::OpISub, rt, {const_like(t, 0, w), sh})});
        Id z = emit_r(spv::OpIEqual, ty(bool_ty_like(t)), {sh, const_like(t, 0, 0)});
        result(ci, emit_r(spv::OpSelect, rt, {z, a(0), emit_r(spv::OpBitwiseOr, rt, {l, r})}));
        return true;
    }
    if (op == "extract_bits") {
        result(ci, emit_r(sgn ? spv::OpBitFieldSExtract : spv::OpBitFieldUExtract, rt, {a(0), a(1), a(2)}));
        return true;
    }
    if (op == "insert_bits") {
        result(ci, emit_r(spv::OpBitFieldInsert, rt, {a(0), a(1), a(2), a(3)}));
        return true;
    }
    if (op == "hadd" || op == "rhadd") {
        // (x >> 1) + (y >> 1) + ((x & y) & 1) / ((x | y) & 1)
        Id sh = const_like(t, 0, 1);
        spv::Op shr = sgn ? spv::OpShiftRightArithmetic : spv::OpShiftRightLogical;
        Id x2 = emit_r(shr, rt, {a(0), sh}), y2 = emit_r(shr, rt, {a(1), sh});
        Id lsb = emit_r(spv::OpBitwiseAnd, rt, {emit_r(op == "hadd" ? spv::OpBitwiseAnd : spv::OpBitwiseOr, rt, {a(0), a(1)}), sh});
        result(ci, emit_r(spv::OpIAdd, rt, {emit_r(spv::OpIAdd, rt, {x2, y2}), lsb}));
        return true;
    }
    if (op == "mul24" || op == "mad24") {
        Id r = emit_r(spv::OpIMul, rt, {a(0), a(1)});
        if (op == "mad24") r = emit_r(spv::OpIAdd, rt, {r, a(2)});
        result(ci, r);
        return true;
    }
    // ---- conversions ----
    if (op == "convert") {
        // air.convert.<d|s|u|f>.<dsttype>.<s|u|f>.<srctype>  (optionally ".sat"/".rte" tokens)
        SmallVector<StringRef, 8> parts;
        name.split(parts, '.');
        char dsign = 0, ssign = 0;
        int seen = 0;
        for (size_t k = 2; k < parts.size(); k++) {
            StringRef p = parts[k];
            if (p == "f" || p == "s" || p == "u") { if (seen == 0) dsign = p[0]; else ssign = p[0]; seen++; }
        }
        Type* from = at(0);
        Id v = a(0);
        if (t->getScalarType()->isIntegerTy(1)) { result(ci, to_bool(ci->getArgOperand(0))); return true; }
        bool src_signed = ssign == 's';
        bool dst_signed = dsign == 's';
        Type* fe = from->getScalarType();
        Type* te = t->getScalarType();
        if (fe->isFloatingPointTy() && te->isIntegerTy()) {
            // Metal float->int conversion saturates (rounding toward zero; NaN -> 0)
            unsigned w = te->getIntegerBitWidth();
            double lo = dst_signed ? -std::ldexp(1.0, (int)w - 1) : 0.0;
            double hi = dst_signed ? std::ldexp(1.0, (int)w - 1) - 1 : std::ldexp(1.0, (int)w) - 1;
            Type* ft = from;
            if (fe->isHalfTy() && w > 8) {   // half cannot represent the 16/32-bit limits: clamp in float
                ft = vlen(from) > 1 ? (Type*)FixedVectorType::get(Type::getFloatTy(m.getContext()), vlen(from)) : Type::getFloatTy(m.getContext());
                v = emit_r(spv::OpFConvert, ty(ft), {v});
            }
            if (w < 64) v = ext(ty(ft), GLSLstd450NClamp, {v, const_like(ft, lo, 0), const_like(ft, hi, 0)});
            result(ci, emit_r(dst_signed ? spv::OpConvertFToS : spv::OpConvertFToU, rt, {v}));
            return true;
        }
        result(ci, convert_numeric(v, from, t, src_signed, dst_signed));
        return true;
    }
    if (op == "pack" || op == "unpack") {
        // air.pack.unorm.rgba8 / .snorm / .rgb565 etc.
        SmallVector<StringRef, 8> parts;
        name.split(parts, '.');
        StringRef kind = parts.size() > 2 ? parts[2] : "";
        StringRef fmt = parts.size() > 3 ? parts[3] : "";
        Type* ft = op == "pack" ? at(0) : t;
        Type* fet = ft->getScalarType();
        Type* f32v = FixedVectorType::get(Type::getFloatTy(m.getContext()), vlen(ft));
        if (op == "pack") {
            Id x = fet->isHalfTy() ? emit_r(spv::OpFConvert, ty(f32v), {a(0)}) : a(0);
            Id r = 0;
            if (fmt == "rgba8" || fmt == "v4f32" || fmt == "rgba8u") r = ext(t_u32(), kind == "snorm" ? GLSLstd450PackSnorm4x8 : GLSLstd450PackUnorm4x8, {x});
            else if (fmt == "rg16") r = ext(t_u32(), kind == "snorm" ? GLSLstd450PackSnorm2x16 : GLSLstd450PackUnorm2x16, {x});
            else if (fmt == "rgb565") {
                Id c = ext(ty(f32v), GLSLstd450NClamp, {x, const_like(f32v, 0, 0), const_like(f32v, 1, 0)});
                Id rr = emit_r(spv::OpConvertFToU, t_u32(), {emit_r(spv::OpFAdd, sb.t_float(32), {emit_r(spv::OpFMul, sb.t_float(32), {emit_r(spv::OpCompositeExtract, sb.t_float(32), {c, 0}), c_f32(31)}), c_f32(0.5f)})});
                Id gg = emit_r(spv::OpConvertFToU, t_u32(), {emit_r(spv::OpFAdd, sb.t_float(32), {emit_r(spv::OpFMul, sb.t_float(32), {emit_r(spv::OpCompositeExtract, sb.t_float(32), {c, 1}), c_f32(63)}), c_f32(0.5f)})});
                Id bb = emit_r(spv::OpConvertFToU, t_u32(), {emit_r(spv::OpFAdd, sb.t_float(32), {emit_r(spv::OpFMul, sb.t_float(32), {emit_r(spv::OpCompositeExtract, sb.t_float(32), {c, 2}), c_f32(31)}), c_f32(0.5f)})});
                r = emit_r(spv::OpBitwiseOr, t_u32(), {emit_r(spv::OpShiftLeftLogical, t_u32(), {rr, c_u32(11)}),
                                                      emit_r(spv::OpBitwiseOr, t_u32(), {emit_r(spv::OpShiftLeftLogical, t_u32(), {gg, c_u32(5)}), bb})});
            } else { fail("pack format " + fmt.str()); return true; }
            result(ci, t->getScalarSizeInBits() == 32 ? r : emit_r(spv::OpUConvert, rt, {r}));
            return true;
        }
        Id x = a(0);
        if (at(0)->getScalarSizeInBits() != 32) x = emit_r(spv::OpUConvert, t_u32(), {x});
        Id r = 0;
        if (fmt == "rgba8" || fmt == "v4f32" || fmt == "v4f16") r = ext(ty(FixedVectorType::get(Type::getFloatTy(m.getContext()), 4)), kind == "snorm" ? GLSLstd450UnpackSnorm4x8 : GLSLstd450UnpackUnorm4x8, {x});
        else if (fmt == "rg16" || fmt == "v2f32" || fmt == "v2f16") r = ext(ty(FixedVectorType::get(Type::getFloatTy(m.getContext()), 2)), kind == "snorm" ? GLSLstd450UnpackSnorm2x16 : GLSLstd450UnpackUnorm2x16, {x});
        else { fail("unpack format " + fmt.str()); return true; }
        Type* got = vlen(t) == 2 ? FixedVectorType::get(Type::getFloatTy(m.getContext()), 2) : FixedVectorType::get(Type::getFloatTy(m.getContext()), 4);
        result(ci, convert_numeric_ids(r, got, t, false));
        return true;
    }
    // ---- control / sync ----
    if (op == "discard_fragment") {
        sb.cap(spv::CapabilityDemoteToHelperInvocation);
        emit(spv::OpDemoteToHelperInvocation, {});
        uses_demote = true;
        ps.res->flags |= SF_DISCARD;
        return true;
    }
    if (name.starts_with("air.wg.barrier") || name.starts_with("air.simdgroup.barrier")) {
        uint32_t flags = na > 0 ? (uint32_t)cast<ConstantInt>(ci->getArgOperand(0))->getZExtValue() : 1;
        bool simd = name.starts_with("air.simdgroup");
        uint32_t sem = spv::MemorySemanticsAcquireReleaseMask;
        if (flags & 1) sem |= spv::MemorySemanticsWorkgroupMemoryMask;
        if (flags & 2) sem |= spv::MemorySemanticsUniformMemoryMask;
        if (flags & 4) sem |= spv::MemorySemanticsImageMemoryMask;
        if (!(flags & 7)) sem = 0;
        uint32_t exec = simd ? spv::ScopeSubgroup : spv::ScopeWorkgroup;
        uint32_t mem = (flags & 6) ? spv::ScopeDevice : (simd ? spv::ScopeSubgroup : spv::ScopeWorkgroup);
        if (vertex || fragment) { if (sem) emit(spv::OpMemoryBarrier, {c_u32(spv::ScopeDevice), c_u32(sem)}); }
        else emit(spv::OpControlBarrier, {c_u32(exec), c_u32(mem), c_u32(sem)});
        ps.res->flags |= SF_USES_BARRIER;
        return true;
    }
    if (name.starts_with("air.atomic.fence") || name.starts_with("air.mem_barrier") || name.starts_with("air.threadgroup_barrier")) {
        uint32_t flags = na > 0 ? (uint32_t)cast<ConstantInt>(ci->getArgOperand(0))->getZExtValue() : 3;
        uint32_t sem = spv::MemorySemanticsAcquireReleaseMask;
        if (flags & 1) sem |= spv::MemorySemanticsWorkgroupMemoryMask;
        if (flags & 2) sem |= spv::MemorySemanticsUniformMemoryMask;
        if (flags & 4) sem |= spv::MemorySemanticsImageMemoryMask;
        emit(spv::OpMemoryBarrier, {c_u32((flags & 6) ? spv::ScopeDevice : spv::ScopeWorkgroup), c_u32(sem)});
        return true;
    }
    if (name.starts_with("air.wait_simdgroup_events") || name.starts_with("air.wait_group_events")) {
        if (kernel) emit(spv::OpControlBarrier, {c_u32(spv::ScopeWorkgroup), c_u32(spv::ScopeWorkgroup), c_u32(spv::MemorySemanticsAcquireReleaseMask | spv::MemorySemanticsWorkgroupMemoryMask)});
        return true;
    }
    if (name.starts_with("air.is_null_simdgroup_event")) { result(ci, sb.const_bool(true)); return true; }
    if (op == "get_read_sampler") { result(ci, sb.const_u64(0)); return true; }
    if (op == "get_num_samples") { result(ci, sample_count()); return true; }
    if (op == "get_sample_position") {
        // Metal's default positions equal Vulkan's standard ones: one table for 1, 2, 4 and 8 samples
        Id f32 = sb.t_float(32), f2 = sb.t_vec(f32, 2), u32 = t_u32();
        if (!sample_pos_var) {
            static const float P[15][2] = {{0.5f, 0.5f}, {0.75f, 0.75f}, {0.25f, 0.25f},
                {0.375f, 0.125f}, {0.875f, 0.375f}, {0.125f, 0.625f}, {0.625f, 0.875f},
                {0.5625f, 0.3125f}, {0.4375f, 0.6875f}, {0.8125f, 0.5625f}, {0.3125f, 0.1875f},
                {0.1875f, 0.8125f}, {0.0625f, 0.4375f}, {0.6875f, 0.9375f}, {0.9375f, 0.0625f}};
            Words el;
            for (auto& p : P) el.push_back(sb.const_composite(f2, {sb.const_f32(p[0]), sb.const_f32(p[1])}));
            Id at = sb.t_array(f2, 15);
            sample_pos_var = sb.variable(sb.t_ptr(spv::StorageClassPrivate, at), spv::StorageClassPrivate, sb.const_composite(at, el));
            interface_ids.push_back(sample_pos_var);
        }
        Id n = sample_count();
        Id last = emit_r(spv::OpISub, u32, {n, c_u32(1)});
        Id i = val(ci->getArgOperand(0));
        Id clamped = emit_r(spv::OpExtInst, u32, {sb.glsl(), (uint32_t)GLSLstd450UMin, i, last});
        Id idx = emit_r(spv::OpIAdd, u32, {last, clamped});   // tables start at count - 1
        Id p = emit_r(spv::OpAccessChain, sb.t_ptr(spv::StorageClassPrivate, f2), {sample_pos_var, idx});
        result(ci, emit_r(spv::OpLoad, f2, {p}));
        return true;
    }
    if (op == "get_function_pointer_visible_function_table") { fail("visible function tables"); return true; }
    return false;
}

// ---------------- textures ----------------

namespace {
struct TexKind { const char* name; uint32_t dim; spv::Dim sdim; bool depth, arrayed, ms, cube; unsigned coords; bool mips; };
const TexKind kTexKinds[] = {
    {"texture_buffer_1d", DIM_BUFFER, spv::DimBuffer, false, false, false, false, 1, false},
    {"texture_1d_array", DIM_1D_ARRAY, spv::Dim1D, false, true, false, false, 1, true},
    {"texture_1d", DIM_1D, spv::Dim1D, false, false, false, false, 1, true},
    {"texture_2d_ms_array", DIM_2D_MS_ARRAY, spv::Dim2D, false, true, true, false, 2, false},
    {"texture_2d_ms", DIM_2D_MS, spv::Dim2D, false, false, true, false, 2, false},
    {"texture_2d_array", DIM_2D_ARRAY, spv::Dim2D, false, true, false, false, 2, true},
    {"texture_2d", DIM_2D, spv::Dim2D, false, false, false, false, 2, true},
    {"texture_3d", DIM_3D, spv::Dim3D, false, false, false, false, 3, true},
    {"texture_cube_array", DIM_CUBE_ARRAY, spv::DimCube, false, true, false, true, 3, true},
    {"texture_cube", DIM_CUBE, spv::DimCube, false, false, false, true, 3, true},
    {"depth_2d_ms_array", DIM_2D_MS_ARRAY, spv::Dim2D, true, true, true, false, 2, false},
    {"depth_2d_ms", DIM_2D_MS, spv::Dim2D, true, false, true, false, 2, false},
    {"depth_2d_array", DIM_2D_ARRAY, spv::Dim2D, true, true, false, false, 2, true},
    {"depth_2d", DIM_2D, spv::Dim2D, true, false, false, false, 2, true},
    {"depth_cube_array", DIM_CUBE_ARRAY, spv::DimCube, true, true, false, true, 3, true},
    {"depth_cube", DIM_CUBE, spv::DimCube, true, false, false, true, 3, true},
};
const TexKind* find_kind(StringRef s) {
    for (auto& k : kTexKinds) if (s.starts_with(k.name)) return &k;
    return nullptr;
}
spv::Dim dim_of(uint32_t d) {
    switch (d) {
    case DIM_1D: case DIM_1D_ARRAY: return spv::Dim1D;
    case DIM_3D: return spv::Dim3D;
    case DIM_CUBE: case DIM_CUBE_ARRAY: return spv::DimCube;
    case DIM_BUFFER: return spv::DimBuffer;
    default: return spv::Dim2D;
    }
}
bool arrayed_of(uint32_t d) { return d == DIM_1D_ARRAY || d == DIM_2D_ARRAY || d == DIM_2D_MS_ARRAY || d == DIM_CUBE_ARRAY; }
bool ms_of(uint32_t d) { return d == DIM_2D_MS || d == DIM_2D_MS_ARRAY; }
} // namespace

Id Emitter::image_type_for(uint32_t dim, uint32_t comp, bool storage, uint32_t format) {
    Id st = comp == COMP_FLOAT ? sb.t_float(32) : sb.t_int(32);
    if (comp == COMP_SINT) st = sb.type(spv::OpTypeInt, {32, 1});
    spv::Dim d = dim_of(dim);
    if (d == spv::Dim1D) sb.cap(storage ? spv::CapabilityImage1D : spv::CapabilitySampled1D);
    if (d == spv::DimBuffer) sb.cap(storage ? spv::CapabilityImageBuffer : spv::CapabilitySampledBuffer);
    if (dim == DIM_CUBE_ARRAY) sb.cap(storage ? spv::CapabilityImageCubeArray : spv::CapabilitySampledCubeArray);
    if (storage && ms_of(dim)) sb.cap(spv::CapabilityStorageImageMultisample);
    if (storage && dim == DIM_2D_MS_ARRAY) sb.cap(spv::CapabilityImageMSArray);
    return sb.t_image(st, d, 2, arrayed_of(dim) ? 1 : 0, ms_of(dim) ? 1 : 0, storage ? 2 : 1, format ? (spv::ImageFormat)format : spv::ImageFormatUnknown);
}

Id Emitter::handle_index(Value* handle) {
    Value* h = handle;
    if (auto* ip = dyn_cast<IntToPtrInst>(h)) h = ip->getOperand(0);
    else if (auto* ce = dyn_cast<ConstantExpr>(h)) { if (ce->getOpcode() == Instruction::IntToPtr) h = ce->getOperand(0); }
    if (h->getType()->isPointerTy()) { fail("texture handle is not an integer"); return c_u32(0); }
    Id v = val(h);
    if (h->getType()->getIntegerBitWidth() != 32) v = emit_r(spv::OpUConvert, t_u32(), {v});
    return v;
}

// is the handle a plain load from the argument table (dynamically uniform)?
static bool handle_uniform(Value* handle) {
    Value* h = handle;
    if (auto* ip = dyn_cast<IntToPtrInst>(h)) h = ip->getOperand(0);
    auto* li = dyn_cast<LoadInst>(h);
    if (!li) return false;
    auto* ip = dyn_cast<IntToPtrInst>(li->getPointerOperand());
    if (!ip) return false;
    Value* addr = ip->getOperand(0);
    if (auto* add = dyn_cast<BinaryOperator>(addr)) addr = add->getOperand(0);
    auto* ci = dyn_cast<CallInst>(addr);
    return ci && ci->getCalledFunction() && ci->getCalledFunction()->getName().starts_with("xef.pc.table");
}

Id Emitter::load_image(uint32_t dim, uint32_t comp, bool storage, Value* handle, Id& img_type, uint32_t format, Id* ptr_out) {
    uint32_t binding = storage ? storage_image_binding(dim, comp) : sampled_image_binding(dim, comp);
    img_type = image_type_for(dim, comp, storage, format);
    Id var;
    auto it = image_vars.find(binding | format << 16);   /* typed views (atomics) alias the same binding */
    if (it != image_vars.end()) var = it->second;
    else {
        Id arr = sb.t_rtarray(img_type);
        var = sb.variable(sb.t_ptr(spv::StorageClassUniformConstant, arr), spv::StorageClassUniformConstant);
        sb.decorate(var, spv::DecorationDescriptorSet, {0});
        sb.decorate(var, spv::DecorationBinding, {binding});
        sb.cap(spv::CapabilityRuntimeDescriptorArray);
        image_vars[binding | format << 16] = var;
        interface_ids.push_back(var);
    }
    Id idx = handle_index(handle);
    bool nonuni = !handle_uniform(handle);
    Id p = emit_r(spv::OpAccessChain, sb.t_ptr(spv::StorageClassUniformConstant, img_type), {var, idx});
    if (ptr_out) {
        *ptr_out = p;
        if (!handle_uniform(handle)) {
            sb.cap(spv::CapabilityShaderNonUniform);
            sb.cap(spv::CapabilityStorageImageArrayNonUniformIndexing);
            sb.decorate(idx, spv::DecorationNonUniform);
            sb.decorate(p, spv::DecorationNonUniform);
        }
        return 0;
    }
    Id img = emit_r(spv::OpLoad, img_type, {p});
    if (nonuni) {
        sb.cap(spv::CapabilityShaderNonUniform);
        sb.cap(storage ? spv::CapabilityStorageImageArrayNonUniformIndexing : spv::CapabilitySampledImageArrayNonUniformIndexing);
        sb.decorate(idx, spv::DecorationNonUniform);
        sb.decorate(p, spv::DecorationNonUniform);
        sb.decorate(img, spv::DecorationNonUniform);
    }
    return img;
}

Id Emitter::sample_count() {
    if (!sample_count_id) {
        sample_count_id = sb.alloc();
        SpvBuilder::inst(sb.globals, spv::OpSpecConstant, {t_u32(), sample_count_id, 1});
        sb.decorate(sample_count_id, spv::DecorationSpecId, {0});
    }
    return sample_count_id;
}

Id Emitter::load_sampler(Value* handle, bool compare) {
    Id st = sb.t_sampler();
    Id& var = compare ? cmp_sampler_var : sampler_var;
    if (!var) {
        Id arr = sb.t_rtarray(st);
        var = sb.variable(sb.t_ptr(spv::StorageClassUniformConstant, arr), spv::StorageClassUniformConstant);
        sb.decorate(var, spv::DecorationDescriptorSet, {0});
        sb.decorate(var, spv::DecorationBinding, {compare ? kCompareSamplerBinding : kSamplerBinding});
        sb.cap(spv::CapabilityRuntimeDescriptorArray);
        interface_ids.push_back(var);
    }
    Id idx = handle_index(handle);
    Id p = emit_r(spv::OpAccessChain, sb.t_ptr(spv::StorageClassUniformConstant, st), {var, idx});
    Id s = emit_r(spv::OpLoad, st, {p});
    if (!handle_uniform(handle)) {
        sb.cap(spv::CapabilityShaderNonUniform);
        sb.decorate(idx, spv::DecorationNonUniform);
        sb.decorate(p, spv::DecorationNonUniform);
        sb.decorate(s, spv::DecorationNonUniform);
    }
    return s;
}

// atomic_<op>_explicit_<kind>.{s,u}.v4i32(tex, coord, [slice], <unused>, value | expected desired, ...):
// one 32-bit texel through OpImageTexelPointer on an R32ui/R32i view of the storage-image binding
bool Emitter::emit_texture_atomic(CallInst* ci, StringRef s) {
    size_t e = s.find("_explicit_");
    if (e == StringRef::npos) { fail("unsupported texture atomic air." + s.str()); return true; }
    StringRef op = s.slice(7, e), rest = s.drop_front(e + 10);
    const TexKind* tk = find_kind(rest);
    if (!tk) { fail("unknown texture kind air." + s.str()); return true; }
    bool sgn = s.contains(".s.");
    uint32_t comp = sgn ? COMP_SINT : COMP_UINT;
    Id it, p = 0;
    load_image(tk->dim, comp, true, ci->getArgOperand(0), it, sgn ? spv::ImageFormatR32i : spv::ImageFormatR32ui, &p);
    Type* i32 = Type::getInt32Ty(m.getContext());
    Id u32 = t_u32(), st = sgn ? sb.type(spv::OpTypeInt, {32, 1}) : u32;
    // coordinate (+ slice)
    Value* cv = ci->getArgOperand(1);
    unsigned cn = tk->coords + (tk->cube ? 1 : 0);
    Id c = val(cv);
    if (cv->getType()->getScalarSizeInBits() != 32) c = emit_r(spv::OpUConvert, ty(vlen(cv->getType()) == 1 ? (Type*)i32 : FixedVectorType::get(i32, vlen(cv->getType()))), {c});
    unsigned k = 2;
    if (tk->arrayed) {
        Id layer = val(ci->getArgOperand(k++));
        Words parts;
        if (cn == 1) parts.push_back(c);
        else for (unsigned q = 0; q < cn; q++) parts.push_back(emit_r(spv::OpCompositeExtract, u32, {c, q}));
        parts.push_back(layer);
        c = emit_r(spv::OpCompositeConstruct, sb.t_vec(u32, cn + 1), parts);
    }
    std::vector<Value*> vals;   // 4-component operands after the coordinates
    for (; k < ci->arg_size(); k++) if (vlen(ci->getArgOperand(k)->getType()) == 4) vals.push_back(ci->getArgOperand(k));
    if (vals.empty()) { fail("texture atomic without a value"); return true; }
    auto x_of = [&](Value* v) {
        Id x = emit_r(spv::OpCompositeExtract, u32, {val(v), 0});
        return sgn ? emit_r(spv::OpBitcast, st, {x}) : x;
    };
    Id tp = emit_r(spv::OpImageTexelPointer, sb.t_ptr(spv::StorageClassImage, st), {p, c, c_u32(0)});
    Id scope = c_u32(spv::ScopeDevice), sem = c_u32(0);
    Id r;
    if (op == "xefcmpxchg") {
        if (vals.size() < 2) { fail("texture compare-exchange operands"); return true; }
        r = emit_r(spv::OpAtomicCompareExchange, st, {tp, scope, sem, sem, x_of(vals[vals.size() - 1]), x_of(vals[vals.size() - 2])});
    } else {
        spv::Op o;
        if (op == "fetch_add") o = spv::OpAtomicIAdd;
        else if (op == "fetch_sub") o = spv::OpAtomicISub;
        else if (op == "fetch_and") o = spv::OpAtomicAnd;
        else if (op == "fetch_or") o = spv::OpAtomicOr;
        else if (op == "fetch_xor") o = spv::OpAtomicXor;
        else if (op == "fetch_min") o = sgn ? spv::OpAtomicSMin : spv::OpAtomicUMin;
        else if (op == "fetch_max") o = sgn ? spv::OpAtomicSMax : spv::OpAtomicUMax;
        else if (op == "exchange") o = spv::OpAtomicExchange;
        else if (op == "load") { r = emit_r(spv::OpAtomicLoad, st, {tp, scope, sem}); goto done; }
        else if (op == "store") { emit(spv::OpAtomicStore, {tp, scope, sem, x_of(vals.back())}); return true; }
        else { fail("unsupported texture atomic air." + s.str()); return true; }
        r = emit_r(o, st, {tp, scope, sem, x_of(vals.back())});
    }
done:
    if (sgn) r = emit_r(spv::OpBitcast, u32, {r});
    if (!ci->getType()->isVoidTy()) {
        Id v4 = emit_r(spv::OpCompositeConstruct, sb.t_vec(u32, 4), {r, c_u32(0), c_u32(0), c_u32(0)});
        result(ci, v4);
    }
    return true;
}

bool Emitter::emit_air_texture(CallInst* ci, StringRef name) {
    StringRef s = name.drop_front(4);   // after "air."
    if (s.starts_with("atomic_")) return emit_texture_atomic(ci, s);
    // operation
    enum { SAMPLE, SAMPLE_CMP, GATHER, GATHER_CMP, READ, WRITE, QWIDTH, QHEIGHT, QDEPTH, QARRAY, QMIPS, QSAMPLES, LOD_CL, LOD_UNCL, FENCE, OTHER } kind = OTHER;
    struct { const char* p; int k; } ops[] = {
        {"sample_compare_", SAMPLE_CMP}, {"sample_", SAMPLE}, {"gather_compare_", GATHER_CMP}, {"gather_", GATHER},
        {"read_", READ}, {"write_", WRITE}, {"get_width_", QWIDTH}, {"get_height_", QHEIGHT}, {"get_depth_", QDEPTH},
        {"get_array_size_", QARRAY}, {"get_num_mip_levels_", QMIPS}, {"get_num_samples_", QSAMPLES},
        {"calculate_clamped_lod_", LOD_CL}, {"calculate_unclamped_lod_", LOD_UNCL}, {"fence_", FENCE},
    };
    StringRef rest;
    for (auto& o : ops) if (s.starts_with(o.p)) { kind = (decltype(kind))o.k; rest = s.drop_front(strlen(o.p)); break; }
    if (kind == OTHER) { fail("unsupported texture op " + name.str()); return true; }
    const TexKind* tk = find_kind(rest);
    if (!tk) { fail("unknown texture kind " + name.str()); return true; }
    StringRef after = rest.drop_front(strlen(tk->name));
    bool grad = after.starts_with("_grad");
    if (kind == FENCE) return true;
    Type* t = ci->getType();
    unsigned na = ci->arg_size();
    auto argv = [&](unsigned k) { return ci->getArgOperand(k); };
    Type* f32 = Type::getFloatTy(m.getContext());
    Type* i32 = Type::getInt32Ty(m.getContext());
    Id f32t = ty(f32), i32t = ty(i32);
    // result element info
    Type* res_val_t = t;
    bool res_struct = false;
    if (auto* st = dyn_cast<StructType>(t)) { res_val_t = st->getElementType(0); res_struct = true; }
    uint32_t comp = COMP_FLOAT;
    bool sgn = name.contains(".s.");
    bool uns = name.contains(".u.");
    if (kind == SAMPLE || kind == GATHER || kind == READ) {
        Type* e = res_val_t->getScalarType();
        if (e->isIntegerTy()) comp = sgn ? COMP_SINT : COMP_UINT;
    } else if (kind == WRITE) {
        // value operand decides
        for (unsigned k = 1; k < na; k++) {
            Type* at = argv(k)->getType();
            if (vlen(at) == 4) { if (at->getScalarType()->isIntegerTy()) comp = sgn ? COMP_SINT : COMP_UINT; break; }
        }
        (void)uns;
    }
    auto finish = [&](Id v4, Type* v4t) {
        // v4: vec4 of 32-bit sampled type -> result
        Id r;
        if (tk->depth && (kind == SAMPLE || kind == SAMPLE_CMP || kind == READ) && vlen(res_val_t) == 1) {
            r = vlen(v4t) == 1 ? v4 : emit_r(spv::OpCompositeExtract, f32t, {v4, 0});
            if (!res_val_t->isFloatTy()) r = convert_numeric_ids(r, f32, res_val_t, false);
        } else {
            r = convert_numeric_ids(v4, v4t, res_val_t, comp == COMP_SINT);
        }
        if (res_struct) {
            Type* st = cast<StructType>(t)->getElementType(1);
            r = emit_r(spv::OpCompositeConstruct, ty(t), {r, sb.const_null(ty(st))});
        }
        result(ci, r);
    };
    Type* f4 = FixedVectorType::get(f32, 4);
    Type* i4 = FixedVectorType::get(i32, 4);
    Type* v4t = comp == COMP_FLOAT ? f4 : i4;

    auto int_vec = [&](Value* v, unsigned n) -> Id {   // integer coords -> i32 vector of n
        Type* vt = v->getType();
        Type* want = n == 1 ? i32 : (Type*)FixedVectorType::get(i32, n);
        Id x = val(v);
        if (vt->getScalarType()->isFloatingPointTy()) return emit_r(spv::OpConvertFToS, ty(want), {x});
        if (vt->getScalarSizeInBits() != 32) x = emit_r(spv::OpUConvert, ty(n == 1 ? i32 : (Type*)FixedVectorType::get(i32, vlen(vt))), {x});
        return x;
    };
    auto append = [&](Id vec, unsigned n, Id extra, Id comp_t) -> Id {   // vec(n) + scalar -> vec(n+1)
        Words parts;
        if (n == 1) parts.push_back(vec);
        else for (unsigned k = 0; k < n; k++) parts.push_back(emit_r(spv::OpCompositeExtract, comp_t, {vec, k}));
        parts.push_back(extra);
        return emit_r(spv::OpCompositeConstruct, sb.t_vec(comp_t, n + 1), parts);
    };

    if (kind == QWIDTH || kind == QHEIGHT || kind == QDEPTH || kind == QARRAY || kind == QMIPS || kind == QSAMPLES) {
        sb.cap(spv::CapabilityImageQuery);
        Id it;
        Id img = load_image(tk->dim, COMP_FLOAT, false, argv(0), it);
        Id r;
        if (kind == QMIPS) r = emit_r(spv::OpImageQueryLevels, i32t, {img});
        else if (kind == QSAMPLES) r = emit_r(spv::OpImageQuerySamples, i32t, {img});
        else {
            unsigned n = tk->sdim == spv::DimCube ? 2 : tk->coords;
            if (tk->arrayed) n++;
            Id vt = n == 1 ? i32t : sb.t_vec(i32t, n);
            Id size;
            if (tk->ms || tk->sdim == spv::DimBuffer) size = emit_r(spv::OpImageQuerySize, vt, {img});
            else {
                Id lod = na > 1 ? int_vec(argv(1), 1) : c_u32(0);
                size = emit_r(spv::OpImageQuerySizeLod, vt, {img, lod});
            }
            unsigned comp_i = kind == QWIDTH ? 0 : kind == QHEIGHT ? 1 : kind == QDEPTH ? 2 : n - 1;
            r = n == 1 ? size : emit_r(spv::OpCompositeExtract, i32t, {size, comp_i});
        }
        result(ci, convert_numeric_ids(r, i32, t, false));
        return true;
    }

    if (kind == READ || kind == WRITE) {
        unsigned k = 1;
        if (k < na && argv(k)->getType()->isPointerTy()) k++;   // read with a "read sampler" (get_read_sampler)
        if (tk->depth && kind == READ && k < na && argv(k)->getType()->isIntegerTy(32) && isa<ConstantInt>(argv(k)) &&
            vlen(argv(k + 1 < na ? k + 1 : k)->getType()) == tk->coords && tk->coords > 1) k++;   // depth marker
        Value* coord = argv(k++);
        unsigned cn = tk->sdim == spv::DimCube ? 2 : tk->coords;
        Id c = int_vec(coord, cn);
        // optional texel offset (same shape as the coordinate)
        if (kind == READ && cn > 1 && k < na && argv(k)->getType()->isVectorTy() && vlen(argv(k)->getType()) == vlen(coord->getType()) &&
            argv(k)->getType()->getScalarType()->isIntegerTy()) {
            Value* off = argv(k++);
            if (!isa<ConstantAggregateZero>(off)) c = emit_r(spv::OpIAdd, sb.t_vec(i32t, cn), {c, int_vec(off, cn)});
        }
        Value* face = nullptr; Value* layer = nullptr; Value* sample = nullptr; Value* lod = nullptr; Value* value = nullptr;
        if (tk->cube && kind == READ) face = argv(k++);
        if (tk->cube && kind == WRITE) face = argv(k++);
        if (tk->arrayed) layer = argv(k++);
        if (kind == WRITE) value = argv(k++);
        if (tk->ms && kind == READ) sample = argv(k++);
        if (tk->mips && k < na && argv(k)->getType()->isIntegerTy() && (k + 1 < na || kind == WRITE)) lod = argv(k++);
        else if (tk->mips && k < na && argv(k)->getType()->isIntegerTy() && kind == READ) lod = argv(k++);
        // access qualifier (newer AIR): 3 = read_write -> storage image
        bool storage = kind == WRITE;
        if (kind == READ && k < na && isa<ConstantInt>(argv(k)) && cast<ConstantInt>(argv(k))->getZExtValue() == 3) storage = true;
        uint32_t dim = tk->dim;
        Id coord_full = c;
        unsigned n = cn;
        if (tk->cube) {
            // cube textures are accessed as 2D arrays (face = layer)
            dim = DIM_2D_ARRAY;
            Id f = int_vec(face, 1);
            if (layer) f = emit_r(spv::OpIAdd, i32t, {emit_r(spv::OpIMul, i32t, {int_vec(layer, 1), c_u32(6)}), f});
            coord_full = append(c, n, f, i32t); n++;
        } else if (layer) {
            coord_full = append(c, n, int_vec(layer, 1), i32t); n++;
        }
        Id it;
        Id img = load_image(dim, comp, storage, argv(0), it);
        if (kind == WRITE) {
            Id v = convert_numeric_ids(val(value), value->getType(), v4t, comp == COMP_SINT);
            if (vlen(value->getType()) == 1) v = splat(v4t, convert_numeric_ids(val(value), value->getType(), v4t->getScalarType(), comp == COMP_SINT));
            if (comp == COMP_SINT) v = emit_r(spv::OpBitcast, sb.t_vec(sb.type(spv::OpTypeInt, {32, 1}), 4), {v});   // texel type = sampled type
            sb.cap(spv::CapabilityStorageImageWriteWithoutFormat);
            emit(spv::OpImageWrite, {img, coord_full, v});
            return true;
        }
        Id r;
        Id tt = comp == COMP_SINT ? sb.t_vec(sb.type(spv::OpTypeInt, {32, 1}), 4) : ty(v4t);   // result = sampled type
        if (storage) {
            sb.cap(spv::CapabilityStorageImageReadWithoutFormat);
            if (sample) r = emit_r(spv::OpImageRead, tt, {img, coord_full, (uint32_t)spv::ImageOperandsSampleMask, int_vec(sample, 1)});
            else r = emit_r(spv::OpImageRead, tt, {img, coord_full});
        } else if (tk->sdim == spv::DimBuffer) {
            r = emit_r(spv::OpImageFetch, tt, {img, coord_full});
        } else if (sample) {
            r = emit_r(spv::OpImageFetch, tt, {img, coord_full, (uint32_t)spv::ImageOperandsSampleMask, int_vec(sample, 1)});
        } else {
            r = emit_r(spv::OpImageFetch, tt, {img, coord_full, (uint32_t)spv::ImageOperandsLodMask, lod ? int_vec(lod, 1) : c_u32(0)});
        }
        if (comp == COMP_SINT) r = emit_r(spv::OpBitcast, ty(v4t), {r});
        finish(r, v4t);
        return true;
    }

    // ---- sample / gather / lod ----
    unsigned k = 2;
    if (tk->depth && k < na && argv(k)->getType()->isIntegerTy(32) && isa<ConstantInt>(argv(k))) k++;   // depth marker
    Value* coord = argv(k++);
    Value* layer = nullptr; Value* ref = nullptr; Value* dx = nullptr; Value* dy = nullptr; Value* minlod_g = nullptr;
    Value* offset = nullptr; bool has_off = false;
    Value* ctrl = nullptr; Value* a1 = nullptr; Value* a2 = nullptr; Value* gcomp = nullptr;
    if (tk->arrayed && kind != LOD_CL && kind != LOD_UNCL) layer = argv(k++);
    if (kind == SAMPLE_CMP || kind == GATHER_CMP) ref = argv(k++);
    if (grad) {
        dx = argv(k++); dy = argv(k++);
        if (k < na && argv(k)->getType()->isFloatTy()) minlod_g = argv(k++);
    }
    if (k + 1 < na && argv(k)->getType()->isIntegerTy(1) && argv(k + 1)->getType()->getScalarType()->isIntegerTy(32) &&
        !argv(k + 1)->getType()->isIntegerTy(1)) {
        auto* hc = dyn_cast<ConstantInt>(argv(k));
        has_off = !hc || !hc->isZero();
        offset = argv(k + 1);
        k += 2;
    }
    if (kind == GATHER && k < na && argv(k)->getType()->isIntegerTy(32) && !tk->depth) gcomp = argv(k++);
    if (k + 1 < na && argv(k)->getType()->isIntegerTy(1) && argv(k + 1)->getType()->isFloatTy()) {
        ctrl = argv(k++); a1 = argv(k++);
        if (k < na && argv(k)->getType()->isFloatTy()) a2 = argv(k++);
    }

    Id it;
    Id img = load_image(tk->dim, comp, false, argv(0), it);
    Id smp = load_sampler(argv(1), kind == SAMPLE_CMP || kind == GATHER_CMP);
    Id sit = sb.t_sampled_image(it);
    Id si = emit_r(spv::OpSampledImage, sit, {img, smp});
    if (!handle_uniform(argv(0)) || !handle_uniform(argv(1))) { sb.decorate(si, spv::DecorationNonUniform); sb.cap(spv::CapabilityShaderNonUniform); }
    // coordinate (+layer)
    unsigned cn = tk->coords;
    Id c = val(coord);
    if (coord->getType()->getScalarType()->isHalfTy()) c = emit_r(spv::OpFConvert, cn == 1 ? f32t : sb.t_vec(f32t, cn), {c});
    if (layer && kind != LOD_CL && kind != LOD_UNCL) {
        Id l = layer->getType()->isFloatingPointTy() ? val(layer) : emit_r(spv::OpConvertUToF, f32t, {int_vec(layer, 1)});
        c = append(c, cn, l, f32t);
    }
    if (kind == LOD_CL || kind == LOD_UNCL) {
        sb.cap(spv::CapabilityImageQuery);
        if (!fragment) { result(ci, c_f32(0)); return true; }
        Id q = emit_r(spv::OpImageQueryLod, sb.t_vec(f32t, 2), {si, c});
        result(ci, emit_r(spv::OpCompositeExtract, f32t, {q, kind == LOD_CL ? 0u : 1u}));
        return true;
    }
    // image operands
    uint32_t mask = 0;
    Words iops;
    bool level = ctrl && isa<ConstantInt>(ctrl) && !cast<ConstantInt>(ctrl)->isZero();
    bool dyn_level = ctrl && !isa<ConstantInt>(ctrl);
    if (dyn_level) { fail("dynamic sample level/bias selector"); return true; }
    bool implicit = fragment && !level && !grad;
    auto is_zero = [](Value* v) { auto* c = dyn_cast<ConstantFP>(v); return c && c->isZero(); };
    Id bias = 0, lod = 0, minlod = 0, gx = 0, gy = 0, offs = 0;
    bool const_off = false;
    if (grad) { gx = val(dx); gy = val(dy); }
    if (level) lod = val(a1);
    else if (a1 && !is_zero(a1)) { if (implicit) bias = val(a1); }
    if (!implicit && !grad && !lod) lod = c_f32(0);
    if (a2 && !is_zero(a2) && (implicit || grad)) { minlod = val(a2); sb.cap(spv::CapabilityMinLod); }
    if (minlod_g && !is_zero(minlod_g)) { minlod = val(minlod_g); sb.cap(spv::CapabilityMinLod); }
    if (has_off && offset && !isa<ConstantAggregateZero>(offset) && !(isa<ConstantInt>(offset) && cast<ConstantInt>(offset)->isZero())) {
        const_off = isa<Constant>(offset);
        offs = val(offset);
        if (!const_off) sb.cap(spv::CapabilityImageGatherExtended);
    }
    if (bias) { mask |= spv::ImageOperandsBiasMask; iops.push_back(bias); }
    if (lod) { mask |= spv::ImageOperandsLodMask; iops.push_back(lod); }
    if (gx) { mask |= spv::ImageOperandsGradMask; iops.push_back(gx); iops.push_back(gy); }
    if (offs) { mask |= const_off ? spv::ImageOperandsConstOffsetMask : spv::ImageOperandsOffsetMask; iops.push_back(offs); }
    if (minlod) { mask |= spv::ImageOperandsMinLodMask; iops.push_back(minlod); }
    Words tail;
    if (mask) { tail.push_back(mask); tail.insert(tail.end(), iops.begin(), iops.end()); }

    Id r;
    if (kind == SAMPLE) {
        Words w{si, c}; w.insert(w.end(), tail.begin(), tail.end());
        r = emit_r(implicit ? spv::OpImageSampleImplicitLod : spv::OpImageSampleExplicitLod, ty(v4t), w);
        finish(r, v4t);
    } else if (kind == SAMPLE_CMP) {
        Words w{si, c, val(ref)}; w.insert(w.end(), tail.begin(), tail.end());
        r = emit_r(implicit ? spv::OpImageSampleDrefImplicitLod : spv::OpImageSampleDrefExplicitLod, f32t, w);
        finish(r, f32);
    } else if (kind == GATHER) {
        Words w{si, c, gcomp ? val(gcomp) : c_u32(0)};
        if (offs) { w.push_back(const_off ? (uint32_t)spv::ImageOperandsConstOffsetMask : (uint32_t)spv::ImageOperandsOffsetMask); w.push_back(offs); }
        r = emit_r(spv::OpImageGather, ty(v4t), w);
        Id rr = convert_numeric_ids(r, v4t, res_val_t, comp == COMP_SINT);
        if (res_struct) rr = emit_r(spv::OpCompositeConstruct, ty(t), {rr, sb.const_null(ty(cast<StructType>(t)->getElementType(1)))});
        result(ci, rr);
    } else {   // GATHER_CMP
        Words w{si, c, val(ref)};
        if (offs) { w.push_back(const_off ? (uint32_t)spv::ImageOperandsConstOffsetMask : (uint32_t)spv::ImageOperandsOffsetMask); w.push_back(offs); }
        r = emit_r(spv::OpImageDrefGather, ty(f4), w);
        Id rr = convert_numeric_ids(r, f4, res_val_t, false);
        if (res_struct) rr = emit_r(spv::OpCompositeConstruct, ty(t), {rr, sb.const_null(ty(cast<StructType>(t)->getElementType(1)))});
        result(ci, rr);
    }
    return true;
}

// ---------------- SIMD-group / quad-group ----------------

bool Emitter::emit_air_simd(CallInst* ci, StringRef name) {
    StringRef op = air_op(name);
    Type* t = ci->getType();
    Id rt = t->isVoidTy() ? 0 : ty(t);
    auto a = [&](unsigned k) { return val(ci->getArgOperand(k)); };
    Id sub = c_u32(spv::ScopeSubgroup);
    bool isf = !t->isVoidTy() && t->getScalarType()->isFloatingPointTy();
    bool sgn = name.contains(".s.");
    sb.cap(spv::CapabilityGroupNonUniform);
    auto lane_id = [&]() {
        Id v = builtin_var(false, BI_SUBGROUP_LOCAL_INVOCATION_ID, t_u32());
        return emit_r(spv::OpLoad, t_u32(), {v});
    };
    auto as_u32 = [&](unsigned k) {
        Value* x = ci->getArgOperand(k);
        Id v = val(x);
        if (x->getType()->getScalarSizeInBits() != 32) v = emit_r(spv::OpUConvert, t_u32(), {v});
        return v;
    };
    auto shuffle = [&](Id lane) {
        sb.cap(spv::CapabilityGroupNonUniformShuffle);
        return emit_r(spv::OpGroupNonUniformShuffle, rt, {sub, a(0), lane});
    };
    auto reduce = [&](spv::GroupOperation gop) -> bool {
        spv::Op o;
        if (op.ends_with("sum")) o = isf ? spv::OpGroupNonUniformFAdd : spv::OpGroupNonUniformIAdd;
        else if (op.ends_with("product")) o = isf ? spv::OpGroupNonUniformFMul : spv::OpGroupNonUniformIMul;
        else if (op.ends_with("min")) o = isf ? spv::OpGroupNonUniformFMin : sgn ? spv::OpGroupNonUniformSMin : spv::OpGroupNonUniformUMin;
        else if (op.ends_with("max")) o = isf ? spv::OpGroupNonUniformFMax : sgn ? spv::OpGroupNonUniformSMax : spv::OpGroupNonUniformUMax;
        else if (op.ends_with("and")) o = t->getScalarType()->isIntegerTy(1) ? spv::OpGroupNonUniformLogicalAnd : spv::OpGroupNonUniformBitwiseAnd;
        else if (op.ends_with("or")) o = t->getScalarType()->isIntegerTy(1) ? spv::OpGroupNonUniformLogicalOr : spv::OpGroupNonUniformBitwiseOr;
        else if (op.ends_with("xor")) o = t->getScalarType()->isIntegerTy(1) ? spv::OpGroupNonUniformLogicalXor : spv::OpGroupNonUniformBitwiseXor;
        else return false;
        sb.cap(spv::CapabilityGroupNonUniformArithmetic);
        result(ci, emit_r(o, rt, {sub, (uint32_t)gop, a(0)}));
        return true;
    };
    if (op.starts_with("simd_prefix_inclusive_")) return reduce(spv::GroupOperationInclusiveScan);
    if (op.starts_with("simd_prefix_exclusive_")) return reduce(spv::GroupOperationExclusiveScan);
    if (op == "simd_sum" || op == "simd_product" || op == "simd_min" || op == "simd_max" || op == "simd_and" || op == "simd_or" || op == "simd_xor")
        return reduce(spv::GroupOperationReduce);
    if (op == "simd_broadcast" || op == "simd_shuffle") { result(ci, shuffle(as_u32(1))); return true; }
    if (op == "simd_broadcast_first") {
        sb.cap(spv::CapabilityGroupNonUniformBallot);
        result(ci, emit_r(spv::OpGroupNonUniformBroadcastFirst, rt, {sub, a(0)}));
        return true;
    }
    if (op == "simd_shuffle_xor") { sb.cap(spv::CapabilityGroupNonUniformShuffle); result(ci, emit_r(spv::OpGroupNonUniformShuffleXor, rt, {sub, a(0), as_u32(1)})); return true; }
    if (op == "simd_shuffle_up") { sb.cap(spv::CapabilityGroupNonUniformShuffleRelative); result(ci, emit_r(spv::OpGroupNonUniformShuffleUp, rt, {sub, a(0), as_u32(1)})); return true; }
    if (op == "simd_shuffle_down") { sb.cap(spv::CapabilityGroupNonUniformShuffleRelative); result(ci, emit_r(spv::OpGroupNonUniformShuffleDown, rt, {sub, a(0), as_u32(1)})); return true; }
    if (op == "simd_shuffle_rotate_down" || op == "simd_shuffle_rotate_up") {
        Id l = lane_id();
        Id d = as_u32(1);
        Id nl = op == "simd_shuffle_rotate_down" ? emit_r(spv::OpIAdd, t_u32(), {l, d}) : emit_r(spv::OpISub, t_u32(), {l, d});
        result(ci, shuffle(emit_r(spv::OpBitwiseAnd, t_u32(), {nl, c_u32(31)})));
        return true;
    }
    if (op == "simd_shuffle_and_fill_up" || op == "simd_shuffle_and_fill_down") { fail("simd_shuffle_and_fill"); return true; }
    if (op == "simd_all" || op == "simd_any") {
        Id b = to_bool(ci->getArgOperand(0));
        sb.cap(spv::CapabilityGroupNonUniformVote);
        Id r = emit_r(op == "simd_all" ? spv::OpGroupNonUniformAll : spv::OpGroupNonUniformAny, sb.t_bool(), {sub, b});
        result(ci, convert_numeric_ids(r, Type::getInt1Ty(m.getContext()), t, false));
        return true;
    }
    if (op == "simd_ballot" || op == "simd_active_threads_mask") {
        sb.cap(spv::CapabilityGroupNonUniformBallot);
        Id b = op == "simd_ballot" ? to_bool(ci->getArgOperand(0)) : sb.const_bool(true);
        Id v4 = emit_r(spv::OpGroupNonUniformBallot, sb.t_vec(t_u32(), 4), {sub, b});
        Id lo = emit_r(spv::OpCompositeExtract, t_u32(), {v4, 0});
        if (t->isIntegerTy(64)) {
            Id hi = emit_r(spv::OpCompositeExtract, t_u32(), {v4, 1});
            Id l64 = emit_r(spv::OpUConvert, sb.t_int(64), {lo});
            Id h64 = emit_r(spv::OpShiftLeftLogical, sb.t_int(64), {emit_r(spv::OpUConvert, sb.t_int(64), {hi}), sb.const_u64(32)});
            result(ci, emit_r(spv::OpBitwiseOr, sb.t_int(64), {l64, h64}));
        } else result(ci, convert_numeric_ids(lo, Type::getInt32Ty(m.getContext()), t, false));
        return true;
    }
    if (op == "simd_is_helper_thread") {
        Id r = sb.const_bool(false);
        if (fragment) {
            sb.cap(spv::CapabilityDemoteToHelperInvocation);
            r = emit_r(spv::OpIsHelperInvocationEXT, sb.t_bool(), {});
        }
        result(ci, convert_numeric_ids(r, Type::getInt1Ty(m.getContext()), t, false));
        return true;
    }
    if (op == "simd_is_first") {
        Id r = emit_r(spv::OpGroupNonUniformElect, sb.t_bool(), {sub});
        result(ci, convert_numeric_ids(r, Type::getInt1Ty(m.getContext()), t, false));
        return true;
    }
    if (op == "is_uniform") {
        sb.cap(spv::CapabilityGroupNonUniformVote);
        Id r = emit_r(spv::OpGroupNonUniformAllEqual, sb.t_bool(), {sub, a(0)});
        result(ci, convert_numeric_ids(r, Type::getInt1Ty(m.getContext()), t, false));
        return true;
    }
    if (op.starts_with("quad_")) {
        Id l = lane_id();
        Id base = emit_r(spv::OpBitwiseAnd, t_u32(), {l, c_u32(~3u)});
        Id q = emit_r(spv::OpBitwiseAnd, t_u32(), {l, c_u32(3)});
        Id target;
        if (op == "quad_broadcast" || op == "quad_shuffle") target = emit_r(spv::OpBitwiseOr, t_u32(), {base, emit_r(spv::OpBitwiseAnd, t_u32(), {as_u32(1), c_u32(3)})});
        else if (op == "quad_shuffle_xor") target = emit_r(spv::OpBitwiseOr, t_u32(), {base, emit_r(spv::OpBitwiseAnd, t_u32(), {emit_r(spv::OpBitwiseXor, t_u32(), {q, as_u32(1)}), c_u32(3)})});
        else if (op == "quad_shuffle_up" || op == "quad_shuffle_rotate_up") {
            Id nq = emit_r(spv::OpISub, t_u32(), {q, as_u32(1)});
            if (op == "quad_shuffle_up") {
                Id neg = emit_r(spv::OpSLessThan, sb.t_bool(), {nq, c_u32(0)});
                nq = emit_r(spv::OpSelect, t_u32(), {neg, q, nq});
            }
            target = emit_r(spv::OpBitwiseOr, t_u32(), {base, emit_r(spv::OpBitwiseAnd, t_u32(), {nq, c_u32(3)})});
        } else if (op == "quad_shuffle_down" || op == "quad_shuffle_rotate_down") {
            Id nq = emit_r(spv::OpIAdd, t_u32(), {q, as_u32(1)});
            if (op == "quad_shuffle_down") {
                Id over = emit_r(spv::OpUGreaterThan, sb.t_bool(), {nq, c_u32(3)});
                nq = emit_r(spv::OpSelect, t_u32(), {over, q, nq});
            }
            target = emit_r(spv::OpBitwiseOr, t_u32(), {base, emit_r(spv::OpBitwiseAnd, t_u32(), {nq, c_u32(3)})});
        } else if (op == "quad_broadcast_first") target = base;
        else if (op == "quad_sum" || op == "quad_all" || op == "quad_any") {
            // reduce over the four lanes with xor shuffles
            sb.cap(spv::CapabilityGroupNonUniformShuffle);
            if (op == "quad_sum") {
                Id x = a(0);
                Id s1 = emit_r(isf ? spv::OpFAdd : spv::OpIAdd, rt, {x, emit_r(spv::OpGroupNonUniformShuffleXor, rt, {sub, x, c_u32(1)})});
                Id s2 = emit_r(isf ? spv::OpFAdd : spv::OpIAdd, rt, {s1, emit_r(spv::OpGroupNonUniformShuffleXor, rt, {sub, s1, c_u32(2)})});
                result(ci, s2);
                return true;
            }
            // all/any: OR / AND the predicate across the quad with xor shuffles
            Id u32 = t_u32();
            Id x = emit_r(spv::OpSelect, u32, {a(0), c_u32(1), c_u32(0)});
            spv::Op o = op == "quad_all" ? spv::OpBitwiseAnd : spv::OpBitwiseOr;
            Id s1 = emit_r(o, u32, {x, emit_r(spv::OpGroupNonUniformShuffleXor, u32, {sub, x, c_u32(1)})});
            Id s2 = emit_r(o, u32, {s1, emit_r(spv::OpGroupNonUniformShuffleXor, u32, {sub, s1, c_u32(2)})});
            Id b = emit_r(spv::OpINotEqual, sb.t_bool(), {s2, c_u32(0)});
            result(ci, convert_numeric_ids(b, Type::getInt1Ty(m.getContext()), ci->getType(), false));
            return true;
        } else { fail("unsupported quad op " + name.str()); return true; }
        result(ci, shuffle(target));
        return true;
    }
    if (op.starts_with("simdgroup_matrix")) { fail("simdgroup matrices are not supported"); return true; }
    return false;
}

} // namespace mtlc
