// Promotion of odd-width integers (i2, i7, i24, ...) that LLVM's optimizer creates (bitreverse matching,
// switch lookup bitmaps, narrowed compares) to i32/i64, which SPIR-V can express.
// Promoted values carry garbage in the bits above N; operations that observe those bits re-normalize.
#include "mtlc.h"
#include "llvm/ADT/PostOrderIterator.h"
#include "llvm/IR/ConstantFold.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include <map>
#include <set>

namespace mtlc {
using namespace llvm;

static bool odd_int(Type* t) {
    t = t->getScalarType();
    if (!t->isIntegerTy()) return false;
    unsigned w = t->getIntegerBitWidth();
    return w != 1 && w != 8 && w != 16 && w != 32 && w != 64;
}

static Type* widened(Type* t) {
    unsigned w = t->getScalarType()->getIntegerBitWidth();
    Type* e = Type::getIntNTy(t->getContext(), w <= 32 ? 32 : 64);
    if (auto* v = dyn_cast<VectorType>(t)) return VectorType::get(e, v->getElementCount());
    return e;
}

static bool involves_odd(Instruction& i) {
    if (odd_int(i.getType())) return true;
    for (Value* o : i.operands()) if (odd_int(o->getType())) return true;
    return false;
}

// lanes of i1 vectors wider than SPIR-V allows (<24 x i1> = bitcast of <3 x i8> bool lanes, as InstCombine
// produces for bool vectors): rebuild each extracted lane through elementwise ops, shuffles and the bitcast
static Value* wide_lane(IRBuilder<>& b, Value* v, uint64_t k, int depth) {
    if (depth > 16) return nullptr;
    if (auto* c = dyn_cast<Constant>(v)) {
        Constant* e = c->getAggregateElement((unsigned)k);
        return e && !isa<PoisonValue>(e) && !isa<UndefValue>(e) ? e : ConstantInt::getFalse(v->getContext());
    }
    if (auto* bc = dyn_cast<BitCastInst>(v)) {
        if (!bc->getSrcTy()->isVectorTy() || !bc->getSrcTy()->getScalarType()->isIntegerTy()) return nullptr;
        unsigned m = bc->getSrcTy()->getScalarSizeInBits();
        Value* lane = b.CreateExtractElement(bc->getOperand(0), b.getInt64(k / m));
        if (k % m) lane = b.CreateLShr(lane, ConstantInt::get(lane->getType(), k % m));
        return b.CreateTrunc(lane, b.getInt1Ty());
    }
    if (auto* bo = dyn_cast<BinaryOperator>(v)) {
        Value* x = wide_lane(b, bo->getOperand(0), k, depth + 1);
        Value* y = x ? wide_lane(b, bo->getOperand(1), k, depth + 1) : nullptr;
        return y ? b.CreateBinOp(bo->getOpcode(), x, y) : nullptr;
    }
    if (auto* sv = dyn_cast<ShuffleVectorInst>(v)) {
        int src = sv->getMaskValue((unsigned)k);
        if (src < 0) return ConstantInt::getFalse(v->getContext());
        unsigned n = cast<FixedVectorType>(sv->getOperand(0)->getType())->getNumElements();
        return (unsigned)src < n ? wide_lane(b, sv->getOperand(0), src, depth + 1) : wide_lane(b, sv->getOperand(1), src - n, depth + 1);
    }
    if (auto* sel = dyn_cast<SelectInst>(v)) {
        Value* c = sel->getCondition()->getType()->isVectorTy() ? wide_lane(b, sel->getCondition(), k, depth + 1) : sel->getCondition();
        Value* x = c ? wide_lane(b, sel->getTrueValue(), k, depth + 1) : nullptr;
        Value* y = x ? wide_lane(b, sel->getFalseValue(), k, depth + 1) : nullptr;
        return y ? b.CreateSelect(c, x, y) : nullptr;
    }
    auto* vt = dyn_cast<FixedVectorType>(v->getType());
    if (vt && vt->getNumElements() <= 4) return b.CreateExtractElement(v, b.getInt64(k));
    return nullptr;
}

static void fold_bool_bitcasts(Function& f) {
    std::vector<ExtractElementInst*> work;
    for (BasicBlock& b : f)
        for (Instruction& i : b)
            if (auto* ee = dyn_cast<ExtractElementInst>(&i))
                if (auto* vt = dyn_cast<FixedVectorType>(ee->getVectorOperandType()))
                    if (vt->getNumElements() > 4 && ee->getType()->isIntegerTy(1) && isa<ConstantInt>(ee->getIndexOperand()))
                        work.push_back(ee);
    std::set<Instruction*> maybe_dead;
    for (ExtractElementInst* ee : work) {
        IRBuilder<> b(ee);
        Value* r = wide_lane(b, ee->getVectorOperand(), cast<ConstantInt>(ee->getIndexOperand())->getZExtValue(), 0);
        if (!r) continue;
        if (auto* src = dyn_cast<Instruction>(ee->getVectorOperand())) maybe_dead.insert(src);
        ee->replaceAllUsesWith(r);
        ee->eraseFromParent();
    }
    // drop the now unused wide vector computations
    while (!maybe_dead.empty()) {
        Instruction* x = *maybe_dead.begin();
        maybe_dead.erase(maybe_dead.begin());
        if (!x->use_empty() || x->mayHaveSideEffects()) continue;
        for (Value* o : x->operands()) if (auto* oi = dyn_cast<Instruction>(o)) maybe_dead.insert(oi);
        x->eraseFromParent();
    }
}

// llvm.{s,u}cmp and llvm.*.with.overflow have no SPIR-V counterpart: expand them
static void expand_int_intrinsics(Function& f) {
    std::vector<IntrinsicInst*> work;
    for (BasicBlock& b : f)
        for (Instruction& i : b)
            if (auto* ii = dyn_cast<IntrinsicInst>(&i)) {
                switch (ii->getIntrinsicID()) {
                case Intrinsic::scmp: case Intrinsic::ucmp:
                case Intrinsic::sadd_with_overflow: case Intrinsic::uadd_with_overflow:
                case Intrinsic::ssub_with_overflow: case Intrinsic::usub_with_overflow:
                case Intrinsic::smul_with_overflow: case Intrinsic::umul_with_overflow:
                    work.push_back(ii); break;
                default: break;
                }
            }
    for (IntrinsicInst* ii : work) {
        IRBuilder<> b(ii);
        Value* x = ii->getArgOperand(0);
        Value* y = ii->getArgOperand(1);
        Value* r = nullptr;
        Intrinsic::ID id = ii->getIntrinsicID();
        if (id == Intrinsic::scmp || id == Intrinsic::ucmp) {
            bool sg = id == Intrinsic::scmp;
            Type* rt = ii->getType();
            Value* lt = b.CreateICmp(sg ? CmpInst::ICMP_SLT : CmpInst::ICMP_ULT, x, y);
            Value* gt = b.CreateICmp(sg ? CmpInst::ICMP_SGT : CmpInst::ICMP_UGT, x, y);
            r = b.CreateSelect(lt, ConstantInt::getSigned(rt, -1), b.CreateSelect(gt, ConstantInt::get(rt, 1), ConstantInt::get(rt, 0)));
        } else {
            Value* v = nullptr;
            Value* ov = nullptr;
            unsigned w = x->getType()->getScalarSizeInBits();
            switch (id) {
            case Intrinsic::uadd_with_overflow: v = b.CreateAdd(x, y); ov = b.CreateICmpULT(v, x); break;
            case Intrinsic::usub_with_overflow: v = b.CreateSub(x, y); ov = b.CreateICmpULT(x, y); break;
            case Intrinsic::sadd_with_overflow: {
                v = b.CreateAdd(x, y);   // overflow when x and y share a sign that the sum lacks
                Value* t = b.CreateAnd(b.CreateXor(v, x), b.CreateXor(v, y));
                ov = b.CreateICmpSLT(t, Constant::getNullValue(x->getType()));
                break;
            }
            case Intrinsic::ssub_with_overflow: {
                v = b.CreateSub(x, y);
                Value* t = b.CreateAnd(b.CreateXor(x, y), b.CreateXor(v, x));
                ov = b.CreateICmpSLT(t, Constant::getNullValue(x->getType()));
                break;
            }
            default: {   /* multiplications through the double-width product */
                bool sg = id == Intrinsic::smul_with_overflow;
                Type* wt = x->getType()->getWithNewBitWidth(2 * w);
                Value* p = b.CreateMul(sg ? b.CreateSExt(x, wt) : b.CreateZExt(x, wt), sg ? b.CreateSExt(y, wt) : b.CreateZExt(y, wt));
                v = b.CreateTrunc(p, x->getType());
                Value* back = sg ? b.CreateSExt(v, wt) : b.CreateZExt(v, wt);
                ov = b.CreateICmpNE(back, p);
                break;
            }
            }
            r = b.CreateInsertValue(b.CreateInsertValue(PoisonValue::get(ii->getType()), v, {0}), ov, {1});
        }
        ii->replaceAllUsesWith(r);
        ii->eraseFromParent();
    }
}

bool legalize_ints(Function& f, std::string& err) {
    expand_int_intrinsics(f);
    fold_bool_bitcasts(f);
    std::vector<Instruction*> work;
    for (BasicBlock& b : f) for (Instruction& i : b) if (involves_odd(i)) work.push_back(&i);
    if (work.empty()) return true;

    std::map<Value*, Value*> prom;
    auto get = [&](Value* v) -> Value* {
        auto it = prom.find(v);
        if (it != prom.end()) return it->second;
        Type* wt = widened(v->getType());
        if (isa<PoisonValue>(v) || isa<UndefValue>(v)) return PoisonValue::get(wt);
        if (auto* c = dyn_cast<Constant>(v))
            if (Constant* r = ConstantFoldCastInstruction(Instruction::ZExt, c, wt)) return prom[v] = r;
        return nullptr;
    };
    // the promoted value with bits >= N cleared / replicated from bit N-1
    auto norm = [&](IRBuilder<>& b, Value* v, unsigned n, bool sign) -> Value* {
        unsigned w = v->getType()->getScalarSizeInBits();
        if (sign) {
            Constant* sh = ConstantInt::get(v->getType(), w - n);
            return b.CreateAShr(b.CreateShl(v, sh), sh);
        }
        return b.CreateAnd(v, ConstantInt::get(v->getType(), APInt::getLowBitsSet(w, n)));
    };
    auto resize = [&](IRBuilder<>& b, Value* v, Type* to, bool sign) -> Value* {
        unsigned a = v->getType()->getScalarSizeInBits(), c = to->getScalarSizeInBits();
        if (a == c) return v;
        return a > c ? b.CreateTrunc(v, to) : sign ? b.CreateSExt(v, to) : b.CreateZExt(v, to);
    };

    // phis first so that loop-carried uses resolve
    std::vector<std::pair<PHINode*, PHINode*>> phis;
    for (Instruction* i : work)
        if (auto* p = dyn_cast<PHINode>(i)) {
            PHINode* np = PHINode::Create(widened(p->getType()), p->getNumIncomingValues(), p->getName(), p->getIterator());
            prom[p] = np;
            phis.push_back({p, np});
        }

    std::vector<Instruction*> dead;
    ReversePostOrderTraversal<Function*> rpo(&f);
    for (BasicBlock* bb : rpo) {
        for (Instruction& ins : *bb) {
            Instruction* i = &ins;
            if (!involves_odd(*i) || isa<PHINode>(i)) continue;
            if (prom.count(i)) continue;
            IRBuilder<> b(i);
            Value* out = nullptr;      // promoted replacement of an odd-typed result
            Value* repl = nullptr;     // direct replacement of a legal-typed result
            auto op = [&](unsigned k) -> Value* {
                Value* v = i->getOperand(k);
                return odd_int(v->getType()) ? get(v) : v;
            };
            auto bad = [&]() { err = "cannot legalize odd integer width in: " + std::string(i->getOpcodeName()); return false; };
            for (Value* o : i->operands())
                if (odd_int(o->getType()) && !get(o)) { err = "odd integer operand defined after use"; return false; }

            if (auto* bo = dyn_cast<BinaryOperator>(i)) {
                unsigned n = bo->getType()->getScalarSizeInBits();
                Value *x = op(0), *y = op(1);
                switch (bo->getOpcode()) {
                case Instruction::LShr: x = norm(b, x, n, false); y = norm(b, y, n, false); break;
                case Instruction::AShr: x = norm(b, x, n, true); y = norm(b, y, n, false); break;
                case Instruction::Shl: y = norm(b, y, n, false); break;
                case Instruction::UDiv: case Instruction::URem: x = norm(b, x, n, false); y = norm(b, y, n, false); break;
                case Instruction::SDiv: case Instruction::SRem: x = norm(b, x, n, true); y = norm(b, y, n, true); break;
                default: break;
                }
                out = b.CreateBinOp(bo->getOpcode(), x, y);
            } else if (auto* c = dyn_cast<ICmpInst>(i)) {
                unsigned n = c->getOperand(0)->getType()->getScalarSizeInBits();
                bool s = c->isSigned();
                repl = b.CreateICmp(c->getPredicate(), norm(b, op(0), n, s), norm(b, op(1), n, s));
            } else if (auto* cast = dyn_cast<CastInst>(i)) {
                Type* src = cast->getSrcTy();
                Type* dst = cast->getDestTy();
                Value* v = op(0);
                Type* to = odd_int(dst) ? widened(dst) : dst;
                unsigned sn = src->getScalarSizeInBits();
                switch (cast->getOpcode()) {
                case Instruction::Trunc: v = resize(b, v, to, false); break;
                case Instruction::ZExt: v = resize(b, odd_int(src) ? norm(b, v, sn, false) : v, to, false); break;
                case Instruction::SExt: v = resize(b, odd_int(src) ? norm(b, v, sn, true) : v, to, true); break;
                default: return bad();
                }
                (odd_int(dst) ? out : repl) = v;
            } else if (auto* s = dyn_cast<SelectInst>(i)) {
                out = b.CreateSelect(s->getCondition(), op(1), op(2));
            } else if (isa<FreezeInst>(i)) {
                out = b.CreateFreeze(op(0));
            } else if (auto* ee = dyn_cast<ExtractElementInst>(i)) {
                out = b.CreateExtractElement(op(0), ee->getIndexOperand());
            } else if (auto* ie = dyn_cast<InsertElementInst>(i)) {
                out = b.CreateInsertElement(op(0), op(1), ie->getOperand(2));
            } else if (auto* sv = dyn_cast<ShuffleVectorInst>(i)) {
                out = b.CreateShuffleVector(op(0), op(1), sv->getShuffleMask());
            } else if (auto* ii = dyn_cast<IntrinsicInst>(i)) {
                Type* rt = ii->getType();
                if (!odd_int(rt)) return bad();
                unsigned n = rt->getScalarSizeInBits();
                Type* wt = widened(rt);
                unsigned w = wt->getScalarSizeInBits();
                Value* x = op(0);
                switch (ii->getIntrinsicID()) {
                case Intrinsic::bitreverse:
                    out = b.CreateLShr(b.CreateUnaryIntrinsic(Intrinsic::bitreverse, x), ConstantInt::get(wt, w - n));
                    break;
                case Intrinsic::ctpop: out = b.CreateUnaryIntrinsic(Intrinsic::ctpop, norm(b, x, n, false)); break;
                case Intrinsic::ctlz:
                    out = b.CreateSub(b.CreateBinaryIntrinsic(Intrinsic::ctlz, norm(b, x, n, false), b.getFalse()), ConstantInt::get(wt, w - n));
                    break;
                case Intrinsic::cttz:
                    out = b.CreateBinaryIntrinsic(Intrinsic::cttz, b.CreateOr(x, ConstantInt::get(wt, APInt::getOneBitSet(w, n))), b.getFalse());
                    break;
                case Intrinsic::umin: case Intrinsic::umax:
                    out = b.CreateBinaryIntrinsic(ii->getIntrinsicID(), norm(b, x, n, false), norm(b, op(1), n, false));
                    break;
                case Intrinsic::smin: case Intrinsic::smax:
                    out = b.CreateBinaryIntrinsic(ii->getIntrinsicID(), norm(b, x, n, true), norm(b, op(1), n, true));
                    break;
                case Intrinsic::abs:
                    out = b.CreateBinaryIntrinsic(Intrinsic::abs, norm(b, x, n, true), b.getFalse());
                    break;
                default: return bad();
                }
            } else {
                return bad();
            }
            if (out) prom[i] = out;
            else i->replaceAllUsesWith(repl);
            dead.push_back(i);
        }
    }
    for (auto& [p, np] : phis) {
        for (unsigned k = 0; k < p->getNumIncomingValues(); k++) {
            Value* v = get(p->getIncomingValue(k));
            if (!v) { err = "odd integer phi input not promoted"; return false; }
            np->addIncoming(v, p->getIncomingBlock(k));
        }
        dead.push_back(p);
    }
    for (Instruction* i : dead) i->replaceAllUsesWith(PoisonValue::get(i->getType()));
    for (Instruction* i : dead) i->eraseFromParent();
    return true;
}

} // namespace mtlc
