// Control flow structurization for SPIR-V.
// LowerSwitch -> FixIrreducible -> mergereturn -> StructurizeCFG, then the fixups from clspv's
// FixupStructuredCFGPass (Apache-2.0, https://github.com/google/clspv) so that every loop has a proper
// continue target and merge block.
#include "mtlc.h"
#include <cstdio>
#include <deque>
#include <cstdlib>
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Instructions.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Transforms/Scalar/StructurizeCFG.h"
#include "llvm/Transforms/Utils/FixIrreducible.h"
#include "llvm/Transforms/Utils/LowerSwitch.h"
#include "llvm/Transforms/Utils/LoopSimplify.h"
#include "llvm/Transforms/Utils/UnifyLoopExits.h"

namespace mtlc {
using namespace llvm;

static void isolate_continue(Function& f, LoopInfo& li) {
    SmallVector<Loop*, 16> loops(li.begin(), li.end());
    DenseSet<Loop*> visited;
    while (!loops.empty()) {
        Loop* loop = loops.back();
        if (!loop->getSubLoops().empty() && !visited.count(loop)) {
            visited.insert(loop);
            for (Loop* s : loop->getSubLoops()) loops.push_back(s);
            continue;
        }
        loops.pop_back();
        Loop* parent = loop->getParentLoop();
        if (!parent) continue;
        BasicBlock* exit = loop->getUniqueExitBlock();
        if (getenv("MTLC_DEBUG_CFG")) fprintf(stderr, "loop %p exit %p parent latch %p\n", (void*)loop->getHeader(), (void*)exit, (void*)parent->getLoopLatch());
        if (!exit || exit != parent->getLoopLatch()) continue;
        BasicBlock* new_exit = BasicBlock::Create(f.getContext(), "", &f, exit);
        UncondBrInst::Create(exit, new_exit);
        parent->addBlockEntry(new_exit);
        SmallVector<BasicBlock*, 4> preds;
        for (BasicBlock* p : predecessors(exit)) if (loop->contains(p)) preds.push_back(p);
        for (auto it = exit->begin(); it != exit->getFirstNonPHIIt(); ++it) {
            PHINode* phi = cast<PHINode>(&*it);
            SmallVector<Value*, 4> vals;
            for (BasicBlock* p : preds) if (Value* v = phi->getIncomingValueForBlock(p)) vals.push_back(v);
            if (vals.size() == 1) phi->addIncoming(vals[0], new_exit);
            else if (!vals.empty()) {
                PHINode* np = PHINode::Create(phi->getType(), (unsigned)vals.size(), "", new_exit->getTerminator()->getIterator());
                for (size_t i = 0; i < vals.size(); i++) np->addIncoming(vals[i], preds[i]);
                phi->addIncoming(np, new_exit);
            }
        }
        for (BasicBlock* p : preds) {
            exit->removePredecessor(p);
            p->getTerminator()->replaceUsesOfWith(exit, new_exit);
        }
    }
}

static void isolate_convergent_latch(Function& f, LoopInfo& li) {
    std::vector<BasicBlock*> blocks;
    for (BasicBlock& bb : f) blocks.push_back(&bb);
    for (BasicBlock* bb : blocks) {
        if (!li.isLoopHeader(bb)) continue;
        Loop* loop = li.getLoopFor(bb);
        BasicBlock* latch = loop->getLoopLatch();
        if (!latch || latch == bb || !latch->hasNPredecessors(2)) continue;
        auto* ht = dyn_cast<CondBrInst>(bb->getTerminator());
        if (!ht || (ht->getSuccessor(0) != latch && ht->getSuccessor(1) != latch)) continue;
        bool conv = false;
        for (Instruction& i : *latch)
            if (auto* c = dyn_cast<CallInst>(&i)) if (c->hasFnAttr(Attribute::Convergent)) { conv = true; break; }
        if (!conv) continue;
        Instruction* lt = latch->getTerminator();
        if (auto* clt = dyn_cast<CondBrInst>(lt)) {
            if (!loop->isLoopExiting(latch)) continue;
            BasicBlock* nl = BasicBlock::Create(f.getContext(), "", &f, latch->getNextNode());
            UncondBrInst::Create(bb, nl);
            loop->addBlockEntry(nl);
            unsigned idx = clt->getSuccessor(0) == bb ? 0 : 1;
            clt->setSuccessor(idx, nl);
            for (PHINode& phi : bb->phis()) phi.replaceIncomingBlockWith(latch, nl);
        } else if (auto* ult = dyn_cast<UncondBrInst>(lt)) {
            BasicBlock* nb = latch->splitBasicBlockBefore(ult);
            loop->addBlockEntry(nb);
        }
    }
}

static void break_conditional_header(Function& f, LoopInfo& li) {
    std::vector<BasicBlock*> blocks;
    for (BasicBlock& bb : f) blocks.push_back(&bb);
    for (BasicBlock* bb : blocks) {
        if (!li.isLoopHeader(bb)) continue;
        auto* t = dyn_cast<CondBrInst>(bb->getTerminator());
        if (!t) continue;
        Loop* loop = li.getLoopFor(bb);
        BasicBlock* latch = loop->getLoopLatch();
        BasicBlock* exit = loop->getUniqueExitBlock();
        BasicBlock* s1 = t->getSuccessor(0);
        BasicBlock* s2 = t->getSuccessor(1);
        if (s1 != latch && s1 != exit && s2 != latch && s2 != exit) {
            BasicBlock* nb = bb->splitBasicBlockBefore(t);
            loop->addBlockEntry(nb);
        }
    }
}

// loops without any exit (infinite loops) get a never-taken exit to an unreachable block, which becomes the merge
static void add_missing_exits(Function& f, LoopInfo& li) {
    for (Loop* l : li.getLoopsInPreorder()) {
        SmallVector<BasicBlock*, 4> exits;
        l->getExitBlocks(exits);
        if (!exits.empty()) continue;
        BasicBlock* latch = l->getLoopLatch();
        if (!latch) continue;
        auto* br = dyn_cast<UncondBrInst>(latch->getTerminator());
        if (!br) continue;
        BasicBlock* dead = BasicBlock::Create(f.getContext(), "noexit", &f);
        new UnreachableInst(f.getContext(), dead);
        Type* i1 = Type::getInt1Ty(f.getContext());
        // the condition must not be a constant (it would be folded): use a freeze of poison
        Value* cond = new FreezeInst(PoisonValue::get(i1), "", br->getIterator());
        Value* never = BinaryOperator::CreateAnd(cond, ConstantInt::getFalse(f.getContext()), "", br->getIterator());
        CondBrInst::Create(never, dead, br->getSuccessor(0), br->getIterator());
        br->eraseFromParent();
    }
}

// single `ret void` block (UnifyFunctionExitNodes no longer exists in LLVM 23)
// (`unreachable` terminators are function exits too: they become branches to the return, the path is UB anyway)
static void merge_returns(Function& f) {
    std::vector<Instruction*> rets;
    for (BasicBlock& bb : f)
        if (isa<ReturnInst>(bb.getTerminator()) || isa<UnreachableInst>(bb.getTerminator())) rets.push_back(bb.getTerminator());
    if (rets.size() <= 1 && (rets.empty() || isa<ReturnInst>(rets[0]))) return;
    BasicBlock* exit = BasicBlock::Create(f.getContext(), "unified_return", &f);
    ReturnInst::Create(f.getContext(), nullptr, exit);
    for (Instruction* r : rets) {
        UncondBrInst::Create(exit, r->getIterator());
        r->eraseFromParent();
    }
}

// ---- structured order and merges (from clspv ComputeStructuredOrder / PopulateStructuredCFGMaps, Apache-2.0) ----
static void structured_order(BasicBlock* block, DominatorTree& dt, LoopInfo& li, std::deque<BasicBlock*>& order, DenseSet<BasicBlock*>& visited) {
    if (!visited.insert(block).second) return;
    Instruction* term = block->getTerminator();
    BasicBlock* cont = nullptr;
    BasicBlock* merge = nullptr;
    if (li.isLoopHeader(block)) {
        Loop* loop = li.getLoopFor(block);
        merge = loop->getExitBlock();
        if (loop->isLoopLatch(block)) cont = block;
        else {
            BasicBlock* latch = loop->getLoopLatch();
            for (BasicBlock* bb : loop->blocks()) {
                if (bb == block) continue;
                if (latch && dt.dominates(bb, latch)) cont = bb;
            }
        }
    } else if (term->getNumSuccessors() > 1) {
        bool back = false;
        for (unsigned i = 0; i < term->getNumSuccessors(); i++)
            if (li.isLoopHeader(term->getSuccessor(i))) back = true;
        if (!back) merge = term->getSuccessor(1);
    }
    if (merge) {
        structured_order(merge, dt, li, order, visited);
        if (cont) structured_order(cont, dt, li, order, visited);
    }
    for (unsigned i = 0; i < term->getNumSuccessors(); i++) {
        BasicBlock* s = term->getSuccessor(i);
        if (s != merge && s != cont) structured_order(s, dt, li, order, visited);
    }
    order.push_front(block);
}

bool compute_structure_info(Function& f, StructureInfo& out) {
    DominatorTree dt(f);
    LoopInfo li(dt);
    std::deque<BasicBlock*> dq;
    DenseSet<BasicBlock*> visited;
    structured_order(&f.getEntryBlock(), dt, li, dq, visited);
    out.order.assign(dq.begin(), dq.end());
    out.merge.clear();
    out.cont.clear();
    DenseSet<BasicBlock*> loop_mc;
    for (BasicBlock* bb : out.order) {
        Instruction* term = bb->getTerminator();
        if (li.isLoopHeader(bb)) {
            Loop* loop = li.getLoopFor(bb);
            BasicBlock* merge = loop->getExitBlock();
            BasicBlock* cont = nullptr;
            if (loop->isLoopLatch(bb)) cont = bb;
            else {
                BasicBlock* latch = loop->getLoopLatch();
                for (BasicBlock* b2 : loop->blocks()) {
                    if (b2 == bb) continue;
                    if (latch && dt.dominates(b2, latch)) cont = b2;
                }
            }
            if (!merge || !cont) return false;
            out.merge.push_back({bb, merge});
            out.cont.push_back({bb, cont});
            loop_mc.insert(merge);
            loop_mc.insert(cont);
        } else if (auto* cb = dyn_cast<CondBrInst>(term)) {
            Loop* l = li.getLoopFor(bb);
            bool backedge = false;
            while (l && !backedge) { if (l->isLoopLatch(bb)) backedge = true; l = l->getParentLoop(); }
            if (!backedge) {
                BasicBlock* t = cb->getSuccessor(0);
                BasicBlock* e = cb->getSuccessor(1);
                if (!loop_mc.count(t) && !loop_mc.count(e)) out.merge.push_back({bb, e});
            }
        }
    }
    return true;
}

// Two headers may end up with the same merge block (nested selections sharing their exit). Give the inner
// header its own merge: a new block that receives all of the merge's predecessors dominated by the inner header.
static bool split_shared_merges(Function& f) {
    StructureInfo si;
    if (!compute_structure_info(f, si)) return false;
    DominatorTree dt(f);
    DenseMap<BasicBlock*, BasicBlock*> owner;   // merge -> header
    for (auto& [h, m] : si.merge) {
        auto it = owner.find(m);
        if (it == owner.end()) { owner[m] = h; continue; }
        BasicBlock* other = it->second;
        BasicBlock* inner = dt.dominates(other, h) ? h : dt.dominates(h, other) ? other : nullptr;
        if (!inner) continue;
        SmallVector<BasicBlock*, 4> preds;
        for (BasicBlock* p : predecessors(m)) if (dt.dominates(inner, p)) preds.push_back(p);
        if (preds.empty()) continue;
        BasicBlock* nm = BasicBlock::Create(f.getContext(), "merge.split", &f, m);
        UncondBrInst::Create(m, nm);
        for (PHINode& phi : m->phis()) {
            SmallVector<std::pair<Value*, BasicBlock*>, 4> moved;
            for (BasicBlock* p : preds) {
                int idx = phi.getBasicBlockIndex(p);
                if (idx >= 0) moved.push_back({phi.getIncomingValue((unsigned)idx), p});
            }
            if (moved.empty()) continue;
            PHINode* np = PHINode::Create(phi.getType(), (unsigned)moved.size(), "", nm->getTerminator()->getIterator());
            for (auto& [v, p] : moved) { np->addIncoming(v, p); phi.removeIncomingValue(p, false); }
            phi.addIncoming(np, nm);
        }
        for (BasicBlock* p : preds) p->getTerminator()->replaceSuccessorWith(m, nm);
        return true;   // one change at a time (dominance changed)
    }
    return false;
}

bool structurize(Function& f, std::string& err) {
    { DominatorTree dt(f); LoopInfo li(dt); add_missing_exits(f, li); }
    merge_returns(f);
    LoopAnalysisManager lam; FunctionAnalysisManager fam; CGSCCAnalysisManager cgam; ModuleAnalysisManager mam;
    PassBuilder pb;
    pb.registerModuleAnalyses(mam); pb.registerCGSCCAnalyses(cgam); pb.registerFunctionAnalyses(fam); pb.registerLoopAnalyses(lam);
    pb.crossRegisterProxies(lam, fam, cgam, mam);
    {
        FunctionPassManager fpm;
        fpm.addPass(LowerSwitchPass());
        fpm.addPass(FixIrreduciblePass());
        fpm.addPass(LoopSimplifyPass());
        fpm.addPass(UnifyLoopExitsPass());
        fpm.addPass(StructurizeCFGPass());
        fpm.run(f, fam);
    }
    // fixups until nothing changes
    for (int round = 0; round < 8; round++) {
        size_t before = f.size();
        { DominatorTree dt(f); LoopInfo li(dt); isolate_continue(f, li); }
        { DominatorTree dt(f); LoopInfo li(dt); isolate_convergent_latch(f, li); }
        { DominatorTree dt(f); LoopInfo li(dt); break_conditional_header(f, li); }
        for (int k = 0; k < 256 && split_shared_merges(f); k++) {}
        if (f.size() == before) break;
    }
    // sanity: every loop must have one exit and one latch
    DominatorTree dt(f);
    LoopInfo li(dt);
    for (Loop* l : li.getLoopsInPreorder()) {
        if (!l->getExitBlock()) { err = "structurize: loop with multiple exits"; return false; }
        if (!l->getLoopLatch()) { err = "structurize: loop with multiple latches"; return false; }
    }
    return true;
}

} // namespace mtlc
