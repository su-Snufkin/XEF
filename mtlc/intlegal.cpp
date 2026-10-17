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

// extractelement (bitcast <N x iM> x to <N*M x i1>), k  ->  trunc (lshr x[k / M], k % M)
// (InstCombine's form of reading lanes of a bool vector stored as bytes)
static void fold_bool_bitcasts(Function& f) {
    std::vector<ExtractElementInst*> work;
    for (BasicBlock& b : f)
        for (Instruction& i : b)
            if (auto* ee = dyn_cast<ExtractElementInst>(&i))
                if (auto* bc = dyn_cast<BitCastInst>(ee->getVectorOperand()))
                    if (ee->getType()->isIntegerTy(1) && isa<ConstantInt>(ee->getIndexOperand()) &&
                        bc->getSrcTy()->isVectorTy() && bc->getSrcTy()->getScalarType()->isIntegerTy())
                        work.push_back(ee);
    std::vector<Instruction*> casts;
    for (ExtractElementInst* ee : work) {
        auto* bc = cast<BitCastInst>(ee->getVectorOperand());
        unsigned m = bc->getSrcTy()->getScalarSizeInBits();
        uint64_t k = cast<ConstantInt>(ee->getIndexOperand())->getZExtValue();
        IRBuilder<> b(ee);
        Value* lane = b.CreateExtractElement(bc->getOperand(0), b.getInt64(k / m));
        if (k % m) lane = b.CreateLShr(lane, ConstantInt::get(lane->getType(), k % m));
        ee->replaceAllUsesWith(b.CreateTrunc(lane, b.getInt1Ty()));
        ee->eraseFromParent();
        casts.push_back(bc);
    }
    for (Instruction* c : casts)
        if (c->getParent() && c->use_empty()) c->eraseFromParent();
}

bool legalize_ints(Function& f, std::string& err) {
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
