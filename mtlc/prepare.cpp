// Stage preparation: function constants, static initializers, the xef.main wrapper, inlining.
#include "mtlc.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Intrinsics.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Analysis/ConstantFolding.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Transforms/IPO/AlwaysInliner.h"
#include "llvm/Transforms/IPO/GlobalDCE.h"
#include "llvm/Transforms/InstCombine/InstCombine.h"
#include "llvm/Transforms/Scalar/ADCE.h"
#include "llvm/Transforms/Scalar/EarlyCSE.h"
#include "llvm/Transforms/Scalar/GVN.h"
#include "llvm/Transforms/Scalar/SROA.h"
#include "llvm/Transforms/Scalar/SimplifyCFG.h"
#include "llvm/Transforms/Scalar/InstSimplifyPass.h"
#include "llvm/Transforms/Utils/Cloning.h"
#include <cstring>
#include <map>

namespace mtlc {
using namespace llvm;
using namespace xef::mtlabi;

std::string type_tag(Type* t) {
    if (t->isVoidTy()) return "void";
    if (t->isHalfTy()) return "f16";
    if (t->isFloatTy()) return "f32";
    if (t->isDoubleTy()) return "f64";
    if (t->isIntegerTy()) return "i" + std::to_string(t->getIntegerBitWidth());
    if (t->isPointerTy()) return "p" + std::to_string(t->getPointerAddressSpace());
    if (auto* v = dyn_cast<FixedVectorType>(t)) return "v" + std::to_string(v->getNumElements()) + type_tag(v->getElementType());
    if (auto* a = dyn_cast<ArrayType>(t)) return "a" + std::to_string(a->getNumElements()) + type_tag(a->getElementType());
    if (auto* s = dyn_cast<StructType>(t)) {
        std::string r = "s";
        for (Type* e : s->elements()) r += "_" + type_tag(e);
        return r + "_e";
    }
    return "x";
}

Function* get_placeholder(Module& m, const std::string& base, Type* ret, ArrayRef<Type*> params) {
    std::string name = base + "." + type_tag(ret);
    for (Type* p : params) name += "." + type_tag(p);
    if (Function* f = m.getFunction(name)) return f;
    FunctionType* ft = FunctionType::get(ret, params, false);
    Function* f = Function::Create(ft, GlobalValue::ExternalLinkage, name, m);
    f->addFnAttr(Attribute::NoUnwind);
    f->addFnAttr(Attribute::WillReturn);
    if (base.rfind("xef.out", 0) == 0) f->setMemoryEffects(MemoryEffects::inaccessibleMemOnly());
    else f->setMemoryEffects(MemoryEffects::none());
    return f;
}

static void run_fpm(Function& f, const std::function<void(FunctionPassManager&)>& add) {
    LoopAnalysisManager lam; FunctionAnalysisManager fam; CGSCCAnalysisManager cgam; ModuleAnalysisManager mam;
    PassBuilder pb;
    pb.registerModuleAnalyses(mam); pb.registerCGSCCAnalyses(cgam); pb.registerFunctionAnalyses(fam); pb.registerLoopAnalyses(lam);
    pb.crossRegisterProxies(lam, fam, cgam, mam);
    FunctionPassManager fpm;
    add(fpm);
    fpm.run(f, fam);
}

static void run_mpm(Module& m, const std::function<void(ModulePassManager&)>& add) {
    LoopAnalysisManager lam; FunctionAnalysisManager fam; CGSCCAnalysisManager cgam; ModuleAnalysisManager mam;
    PassBuilder pb;
    pb.registerModuleAnalyses(mam); pb.registerCGSCCAnalyses(cgam); pb.registerFunctionAnalyses(fam); pb.registerLoopAnalyses(lam);
    pb.crossRegisterProxies(lam, fam, cgam, mam);
    ModulePassManager mpm;
    add(mpm);
    mpm.run(m, mam);
}

bool run_cleanup(Function& f, bool full) {
    run_fpm(f, [&](FunctionPassManager& fpm) {
        fpm.addPass(SROAPass(SROAOptions::ModifyCFG));
        fpm.addPass(EarlyCSEPass(true));
        if (full) fpm.addPass(InstCombinePass());
        fpm.addPass(SimplifyCFGPass());
        if (full) {
            fpm.addPass(GVNPass());
            fpm.addPass(SROAPass(SROAOptions::ModifyCFG));
            fpm.addPass(InstCombinePass());
            fpm.addPass(SimplifyCFGPass());
        }
        fpm.addPass(ADCEPass());
    });
    return true;
}

// ---------------- function constants ----------------

static Constant* constant_from_bytes(Type* t, const uint8_t* p, size_t n, const DataLayout& dl) {
    uint64_t sz = dl.getTypeStoreSize(t);
    if (sz > n) return Constant::getNullValue(t);
    if (t->isIntegerTy()) {
        uint64_t v = 0; memcpy(&v, p, std::min<uint64_t>(sz, 8));
        if (t->isIntegerTy(1)) v &= 1;
        return ConstantInt::get(t, v);
    }
    if (t->isFloatTy()) { float f; memcpy(&f, p, 4); return ConstantFP::get(t, f); }
    if (t->isDoubleTy()) { double d; memcpy(&d, p, 8); return ConstantFP::get(t, d); }
    if (t->isHalfTy()) { uint16_t h; memcpy(&h, p, 2); return ConstantFP::get(t->getContext(), APFloat(APFloat::IEEEhalf(), APInt(16, h))); }
    if (auto* vt = dyn_cast<FixedVectorType>(t)) {
        std::vector<Constant*> el;
        uint64_t es = dl.getTypeAllocSize(vt->getElementType());
        for (unsigned i = 0; i < vt->getNumElements(); i++) el.push_back(constant_from_bytes(vt->getElementType(), p + i * es, n - i * es, dl));
        return ConstantVector::get(el);
    }
    if (auto* at = dyn_cast<ArrayType>(t)) {
        std::vector<Constant*> el;
        uint64_t es = dl.getTypeAllocSize(at->getElementType());
        for (unsigned i = 0; i < at->getNumElements(); i++) el.push_back(constant_from_bytes(at->getElementType(), p + i * es, n - i * es, dl));
        return ConstantArray::get(at, el);
    }
    if (auto* st = dyn_cast<StructType>(t)) {
        const StructLayout* sl = dl.getStructLayout(st);
        std::vector<Constant*> el;
        for (unsigned i = 0; i < st->getNumElements(); i++) {
            uint64_t off = sl->getElementOffset(i);
            el.push_back(constant_from_bytes(st->getElementType(i), p + off, n - off, dl));
        }
        return ConstantStruct::get(st, el);
    }
    return Constant::getNullValue(t);
}

static void resolve_function_constants(Module& m, const std::vector<FnConstant>& consts) {
    const DataLayout& dl = m.getDataLayout();
    std::vector<std::pair<GlobalVariable*, bool>> fcs;
    if (NamedMDNode* nm = m.getNamedMetadata("air.function_constants")) {
        for (MDNode* n : nm->operands()) {
            if (n->getNumOperands() < 4) continue;
            auto* vm = dyn_cast_or_null<ValueAsMetadata>(n->getOperand(0));
            auto* g = vm ? dyn_cast<GlobalVariable>(vm->getValue()) : nullptr;
            if (!g) continue;
            std::string name = md_str(n->getOperand(2));
            int64_t index = -1; md_int(n->getOperand(3), index);
            const FnConstant* found = nullptr;
            for (auto& c : consts)
                if ((index >= 0 && c.index == (uint32_t)index && c.name.empty()) || (!c.name.empty() && c.name == name)) { found = &c; break; }
            if (!found)
                for (auto& c : consts)
                    if (index >= 0 && c.index == (uint32_t)index) { found = &c; break; }
            Type* vt = g->getValueType();
            Constant* init = found ? constant_from_bytes(vt, found->value.data(), found->value.size(), dl) : Constant::getNullValue(vt);
            g->setInitializer(init);
            g->setConstant(true);
            g->setExternallyInitialized(false);
            g->setSection("");
            g->setLinkage(GlobalValue::InternalLinkage);
            fcs.push_back({g, found != nullptr});
        }
    }
    // predicates
    std::vector<CallInst*> calls;
    for (Function& f : m)
        if (f.isDeclaration() && (f.getName().starts_with("air.is_function_constant_defined") ||
                                  f.getName().starts_with("air.normalize_function_constant_predicate")))
            for (User* u : f.users()) if (auto* ci = dyn_cast<CallInst>(u)) calls.push_back(ci);
    for (CallInst* ci : calls) {
        StringRef fn = ci->getCalledFunction()->getName();
        Value* repl;
        if (fn.starts_with("air.is_function_constant_defined")) {
            bool defined = false;
            Value* arg = ci->getArgOperand(0)->stripPointerCasts();
            for (auto& [g, d] : fcs) if (g == arg) defined = d;
            repl = ConstantInt::get(ci->getType(), defined ? 1 : 0);
        } else {
            IRBuilder<> b(ci);
            Value* x = ci->getArgOperand(0);
            repl = b.CreateZExt(b.CreateICmpNE(x, Constant::getNullValue(x->getType())), ci->getType());
        }
        ci->replaceAllUsesWith(repl);
        ci->eraseFromParent();
    }
    // fold loads of the now-constant globals
    for (auto& [g, d] : fcs) {
        std::vector<LoadInst*> loads;
        for (User* u : g->users()) if (auto* li = dyn_cast<LoadInst>(u)) loads.push_back(li);
        for (LoadInst* li : loads)
            if (Constant* c = ConstantFoldLoadFromConstPtr(g, li->getType(), dl)) { li->replaceAllUsesWith(c); li->eraseFromParent(); }
    }
}

// ---------------- entry wrapper ----------------

struct WrapperCtx {
    Module& m;
    PreparedStage& ps;
    StageResult& res;
    const CompileRequest& req;
    LinkInfo& link;
    IRBuilder<>& b;
    Value* table = nullptr;
    std::string& err;
    uint32_t tg_static = 0;

    uint32_t table_slot(uint8_t kind, uint16_t index) {
        for (auto& t : res.table) if (t.kind == kind && t.index == index) return t.offset;
        TableEntry te{kind, 0, index, (uint32_t)res.table.size() * 8};
        res.table.push_back(te);
        res.table_size = (uint32_t)res.table.size() * 8;
        return te.offset;
    }
    Value* load_table(uint8_t kind, uint16_t index) {
        uint32_t off = table_slot(kind, index);
        Value* addr = b.CreateAdd(table, b.getInt64(off));
        Value* p = b.CreateIntToPtr(addr, PointerType::get(m.getContext(), 1));
        return b.CreateAlignedLoad(b.getInt64Ty(), p, Align(8));
    }
};

// converts between numeric shapes: int width, float width, vector length (pads with 0 / truncates)
static Value* adapt(IRBuilder<>& b, Value* v, Type* want) {
    Type* have = v->getType();
    if (have == want) return v;
    auto* hv = dyn_cast<FixedVectorType>(have);
    auto* wv = dyn_cast<FixedVectorType>(want);
    Type* he = have->getScalarType();
    Type* we = want->getScalarType();
    unsigned hn = hv ? hv->getNumElements() : 1, wn = wv ? wv->getNumElements() : 1;
    // element conversion first (on the full vector)
    if (he != we) {
        Type* mid = hv ? (Type*)FixedVectorType::get(we, hn) : we;
        if (he->isIntegerTy() && we->isIntegerTy()) v = b.CreateZExtOrTrunc(v, mid);
        else if (he->isFloatingPointTy() && we->isFloatingPointTy()) v = b.CreateFPCast(v, mid);
        else if (he->isIntegerTy() && we->isFloatingPointTy()) v = b.CreateUIToFP(v, mid);
        else if (he->isFloatingPointTy() && we->isIntegerTy()) v = b.CreateFPToUI(v, mid);
        else return PoisonValue::get(want);
    }
    if (hn == wn) return v;
    if (!hv) {   // scalar -> vector: element 0
        Value* r = Constant::getNullValue(want);
        return b.CreateInsertElement(r, v, (uint64_t)0);
    }
    if (!wv) return b.CreateExtractElement(v, (uint64_t)0);
    SmallVector<int, 4> mask;
    for (unsigned i = 0; i < wn; i++) mask.push_back(i < hn ? (int)i : (int)hn);
    Value* zero = Constant::getNullValue(v->getType());
    return b.CreateShuffleVector(v, zero, mask);
}

static Value* in_builtin(WrapperCtx& c, uint32_t id, Type* t) {
    Function* f = get_placeholder(c.m, "xef.in.builtin", t, {c.b.getInt32Ty()});
    return c.b.CreateCall(f, {c.b.getInt32(id)});
}

// 32-bit interface type for varyings (half -> float, short/char -> int)
static Type* widen_varying(Type* t) {
    Type* e = t->getScalarType();
    Type* ne = e;
    if (e->isHalfTy()) ne = Type::getFloatTy(t->getContext());
    else if (e->isIntegerTy() && e->getIntegerBitWidth() < 32) ne = Type::getInt32Ty(t->getContext());
    if (ne == e) return t;
    if (auto* v = dyn_cast<FixedVectorType>(t)) return FixedVectorType::get(ne, v->getNumElements());
    return ne;
}
static Value* convert_varying(IRBuilder<>& b, Value* v, Type* want, bool is_signed) {
    Type* have = v->getType();
    if (have == want) return v;
    Type* he = have->getScalarType(); Type* we = want->getScalarType();
    if (he->isFloatingPointTy()) return b.CreateFPCast(v, want);
    if (he->isIntegerTy() && we->isIntegerTy()) return is_signed ? b.CreateSExtOrTrunc(v, want) : b.CreateZExtOrTrunc(v, want);
    return adapt(b, v, want);
}

static bool type_is_signed_name(const std::string& tn) {
    return tn.rfind("int", 0) == 0 || tn.rfind("short", 0) == 0 || tn.rfind("char", 0) == 0 || tn.rfind("long", 0) == 0;
}

static Value* in_location(WrapperCtx& c, uint32_t loc, Type* t, uint32_t interp, const std::string& tn) {
    Type* it = widen_varying(t);
    if (it->getScalarType()->isIntegerTy()) interp |= INTERP_FLAT;
    Function* f = get_placeholder(c.m, "xef.in.loc", it, {c.b.getInt32Ty(), c.b.getInt32Ty()});
    Value* v = c.b.CreateCall(f, {c.b.getInt32(loc), c.b.getInt32(interp)});
    return convert_varying(c.b, v, t, type_is_signed_name(tn));
}

static void out_builtin(WrapperCtx& c, uint32_t id, Value* v) {
    Function* f = get_placeholder(c.m, "xef.out.builtin", c.b.getVoidTy(), {c.b.getInt32Ty(), v->getType()});
    c.b.CreateCall(f, {c.b.getInt32(id), v});
}
static void out_location(WrapperCtx& c, uint32_t loc, uint32_t index, Value* v, uint32_t interp, const std::string& tn) {
    Type* it = widen_varying(v->getType());
    v = convert_varying(c.b, v, it, type_is_signed_name(tn));
    if (it->getScalarType()->isIntegerTy() && c.ps.stage == StageKind::Vertex) interp |= INTERP_FLAT;
    Function* f = get_placeholder(c.m, "xef.out.loc", c.b.getVoidTy(), {c.b.getInt32Ty(), c.b.getInt32Ty(), c.b.getInt32Ty(), it});
    c.b.CreateCall(f, {c.b.getInt32(loc), c.b.getInt32(index), c.b.getInt32(interp), v});
}

static uint8_t base_type_of(Type* t) {
    Type* e = t->getScalarType();
    if (e->isFloatTy()) return BT_FLOAT;
    if (e->isHalfTy()) return BT_HALF;
    if (e->isIntegerTy(32)) return BT_INT;
    if (e->isIntegerTy(16)) return BT_SHORT;
    if (e->isIntegerTy(8)) return BT_CHAR;
    if (e->isIntegerTy(1)) return BT_BOOL;
    return BT_OTHER;
}
static uint8_t comps_of(Type* t) {
    if (auto* v = dyn_cast<FixedVectorType>(t)) return (uint8_t)v->getNumElements();
    return 1;
}

static uint32_t interp_flags(const AirElem& e) {
    uint32_t f = 0;
    if (e.flat) f |= INTERP_FLAT;
    if (e.no_perspective) f |= INTERP_NOPERSPECTIVE;
    if (e.centroid) f |= INTERP_CENTROID;
    if (e.sample) f |= INTERP_SAMPLE;
    return f;
}

static bool module_has_barrier(Module& m) {
    for (Function& f : m)
        if (f.isDeclaration() && (f.getName().starts_with("air.wg.barrier") || f.getName().starts_with("air.simdgroup.barrier")) && !f.use_empty())
            return true;
    return false;
}

static Value* make_arg(WrapperCtx& c, const AirElem& e, Type* t) {
    IRBuilder<>& b = c.b;
    const std::string& k = e.kind;
    LLVMContext& ctx = c.m.getContext();
    auto vec3 = [&](uint32_t id) { return adapt(b, in_builtin(c, id, FixedVectorType::get(b.getInt32Ty(), 3)), t); };
    auto scalar = [&](uint32_t id) { return adapt(b, in_builtin(c, id, b.getInt32Ty()), t); };
    auto as_ptr = [&](Value* v) -> Value* {
        if (t->isPointerTy()) return b.CreateIntToPtr(v, t);
        if (t->isIntegerTy()) return b.CreateZExtOrTrunc(v, t);
        return PoisonValue::get(t);
    };
    // arrays of resources arrive as a byval pointer to [N x ptr]: build that array from consecutive bindings
    if ((k == "air.texture" || k == "air.sampler" || k == "air.buffer") && e.location_count > 1 && t->isPointerTy() && e.location >= 0) {
        uint8_t kind = k == "air.texture" ? BIND_TEXTURE : k == "air.sampler" ? BIND_SAMPLER : BIND_BUFFER;
        Type* et = PointerType::get(ctx, k == "air.sampler" ? 2 : 1);
        ArrayType* at = ArrayType::get(et, (uint64_t)e.location_count);
        IRBuilder<> eb(&*b.GetInsertBlock()->getParent()->getEntryBlock().getFirstInsertionPt());
        AllocaInst* arr = eb.CreateAlloca(at);
        for (int i = 0; i < e.location_count; i++) {
            Value* h = b.CreateIntToPtr(c.load_table(kind, (uint16_t)(e.location + i)), et);
            b.CreateStore(h, b.CreateConstInBoundsGEP2_32(at, arr, 0, (unsigned)i));
        }
        return b.CreateAddrSpaceCast(arr, t);
    }
    if (k == "air.buffer" || k == "air.indirect_buffer") {
        if (e.location < 0) return PoisonValue::get(t);
        return as_ptr(c.load_table(BIND_BUFFER, (uint16_t)e.location));
    }
    if (k == "air.indirect_constant") return as_ptr(c.load_table(BIND_BUFFER, (uint16_t)std::max(e.location, 0)));
    if (k == "air.texture") return as_ptr(c.load_table(BIND_TEXTURE, (uint16_t)std::max(e.location, 0)));
    if (k == "air.sampler") return as_ptr(c.load_table(BIND_SAMPLER, (uint16_t)std::max(e.location, 0)));
    if (k == "air.buffer_size") return adapt(b, c.load_table(BIND_BUFFER_SIZE, (uint16_t)std::max(e.location, 0)), t);
    if (k == "air.threadgroup") {
        uint32_t idx = e.location < 0 ? 0 : (uint32_t)e.location;
        uint32_t len = idx < c.req.tg_mem.size() ? c.req.tg_mem[idx] : 0;
        if (!len) len = (uint32_t)std::max(e.type_size, 16);
        uint32_t off = (c.ps.tg_bytes + 15) & ~15u;
        c.ps.tg_bytes = off + ((len + 15) & ~15u);
        return as_ptr(b.getInt64(kTagTg | off));
    }
    if (k == "air.vertex_input") {
        uint32_t loc = e.location < 0 ? 0 : (uint32_t)e.location;
        Type* it = widen_varying(t);
        c.res.attribs.push_back(VertexAttrib{loc, base_type_of(t), comps_of(t), 0});
        Function* f = get_placeholder(c.m, "xef.in.loc", it, {b.getInt32Ty(), b.getInt32Ty()});
        Value* v = b.CreateCall(f, {b.getInt32(loc), b.getInt32(0)});
        return convert_varying(b, v, t, type_is_signed_name(e.type_name));
    }
    if (k == "air.fragment_input") {
        uint32_t loc = 0;
        bool found = false;
        for (size_t i = 0; i < c.link.vertex_outputs.size(); i++)
            if (c.link.vertex_outputs[i] == e.user_name) { loc = (uint32_t)i; found = true; break; }
        if (!found) {
            loc = (uint32_t)c.link.vertex_outputs.size();
            c.link.vertex_outputs.push_back(e.user_name);   // unmatched input: reads undefined data
        }
        return in_location(c, loc, t, interp_flags(e), e.type_name);
    }
    if (k == "air.stage_in") return PoisonValue::get(t);
    // builtins
    if (k == "air.vertex_id") return scalar(BI_VERTEX_INDEX);
    if (k == "air.instance_id") return scalar(BI_INSTANCE_INDEX);
    if (k == "air.base_vertex") return scalar(BI_BASE_VERTEX);
    if (k == "air.base_instance") return scalar(BI_BASE_INSTANCE);
    if (k == "air.position") return adapt(b, in_builtin(c, BI_FRAG_COORD, FixedVectorType::get(b.getFloatTy(), 4)), t);
    if (k == "air.front_facing") {
        Value* v = in_builtin(c, BI_FRONT_FACING, b.getInt1Ty());
        return t->isIntegerTy(1) ? v : b.CreateZExt(v, t);
    }
    if (k == "air.point_coord") return adapt(b, in_builtin(c, BI_POINT_COORD, FixedVectorType::get(b.getFloatTy(), 2)), t);
    if (k == "air.sample_id") return scalar(BI_SAMPLE_ID);
    if (k == "air.sample_mask") return adapt(b, in_builtin(c, BI_SAMPLE_MASK, b.getInt32Ty()), t);
    if (k == "air.primitive_id") return scalar(BI_PRIMITIVE_ID);
    if (k == "air.render_target_array_index") return scalar(BI_LAYER);
    if (k == "air.viewport_array_index") return scalar(BI_VIEWPORT_INDEX);
    if (k == "air.barycentric_coord") return adapt(b, in_builtin(c, BI_BARY_COORD, FixedVectorType::get(b.getFloatTy(), 3)), t);
    if (k == "air.thread_position_in_grid") return vec3(BI_GLOBAL_INVOCATION_ID);
    if (k == "air.thread_position_in_threadgroup") return vec3(BI_LOCAL_INVOCATION_ID);
    if (k == "air.threadgroup_position_in_grid") return vec3(BI_WORKGROUP_ID);
    if (k == "air.threadgroups_per_grid") return vec3(BI_NUM_WORKGROUPS);
    if (k == "air.thread_index_in_threadgroup") return scalar(BI_LOCAL_INVOCATION_INDEX);
    if (k == "air.thread_index_in_simdgroup") return scalar(BI_SUBGROUP_LOCAL_INVOCATION_ID);
    if (k == "air.simdgroup_index_in_threadgroup") return scalar(BI_SUBGROUP_ID);
    if (k == "air.threads_per_simdgroup") return scalar(BI_SUBGROUP_SIZE);
    if (k == "air.simdgroups_per_threadgroup" || k == "air.dispatch_simdgroups_per_threadgroup") return scalar(BI_NUM_SUBGROUPS);
    if (k == "air.thread_index_in_quadgroup")
        return adapt(b, b.CreateAnd(in_builtin(c, BI_LOCAL_INVOCATION_INDEX, b.getInt32Ty()), 3), t);
    if (k == "air.quadgroup_index_in_threadgroup")
        return adapt(b, b.CreateLShr(in_builtin(c, BI_LOCAL_INVOCATION_INDEX, b.getInt32Ty()), 2), t);
    if (k == "air.threads_per_threadgroup" || k == "air.dispatch_threads_per_threadgroup") {
        Value* v = ConstantVector::get({b.getInt32(c.ps.tg_size[0]), b.getInt32(c.ps.tg_size[1]), b.getInt32(c.ps.tg_size[2])});
        return adapt(b, v, t);
    }
    if (k == "air.threads_per_grid" || k == "air.grid_size") {
        Function* f = get_placeholder(c.m, "xef.pc.u32", b.getInt32Ty(), {b.getInt32Ty()});
        Value* v = PoisonValue::get(FixedVectorType::get(b.getInt32Ty(), 3));
        for (unsigned i = 0; i < 3; i++)
            v = b.CreateInsertElement(v, b.CreateCall(f, {b.getInt32(16 + 4 * i)}), (uint64_t)i);
        return adapt(b, v, t);
    }
    if (k == "air.grid_origin") return Constant::getNullValue(t);
    (void)ctx;
    return PoisonValue::get(t);
}

static std::map<GlobalVariable*, int64_t> g_ctor_values;
static bool predicate_true(Metadata* pred);

static void write_output(WrapperCtx& c, const AirElem& e, Value* v) {
    IRBuilder<>& b = c.b;
    const std::string& k = e.kind;
    if (k == "air.position") {
        out_builtin(c, BI_POSITION, adapt(b, v, FixedVectorType::get(b.getFloatTy(), 4)));
        c.res.flags |= SF_HAS_POSITION;
    } else if (k == "air.vertex_output") {
        uint32_t loc = (uint32_t)c.link.vertex_outputs.size();
        c.link.vertex_outputs.push_back(e.user_name);
        out_location(c, loc, 0, v, interp_flags(e), e.type_name);
    } else if (k == "air.point_size") {
        out_builtin(c, BI_POINT_SIZE, adapt(b, v, b.getFloatTy()));
        c.res.flags |= SF_POINT_SIZE;
    } else if (k == "air.clip_distance") {
        Type* t = v->getType();
        unsigned n = 1;
        if (auto* at = dyn_cast<ArrayType>(t)) n = (unsigned)at->getNumElements();
        else if (auto* vt = dyn_cast<FixedVectorType>(t)) n = vt->getNumElements();
        Type* arr = ArrayType::get(b.getFloatTy(), n);
        Value* a = PoisonValue::get(arr);
        for (unsigned i = 0; i < n; i++) {
            Value* el = t->isArrayTy() ? b.CreateExtractValue(v, {i}) : t->isVectorTy() ? b.CreateExtractElement(v, (uint64_t)i) : v;
            a = b.CreateInsertValue(a, adapt(b, el, b.getFloatTy()), {i});
        }
        out_builtin(c, BI_CLIP_DISTANCE, a);
    } else if (k == "air.render_target_array_index") {
        out_builtin(c, BI_LAYER, adapt(b, v, b.getInt32Ty()));
    } else if (k == "air.viewport_array_index") {
        out_builtin(c, BI_VIEWPORT_INDEX, adapt(b, v, b.getInt32Ty()));
    } else if (k == "air.render_target") {
        int64_t lv = e.location < 0 ? 0 : e.location;
        if (e.location_expr) {
            auto it = g_ctor_values.find(e.location_expr);
            if (it != g_ctor_values.end()) lv = it->second;
            else if (e.location_expr->hasInitializer())
                if (auto* ci = dyn_cast<ConstantInt>(e.location_expr->getInitializer())) lv = ci->getSExtValue();
        }
        uint32_t loc = (uint32_t)lv;
        c.res.colors.push_back(ColorOutput{loc, (uint8_t)e.rt_index, base_type_of(v->getType()), comps_of(v->getType()), 0});
        // color outputs are always 4-component 32-bit (attachment formats decide what is kept)
        Type* t = v->getType();
        Type* et = t->getScalarType();
        Type* want = et->isFloatingPointTy() ? (Type*)FixedVectorType::get(b.getFloatTy(), 4) : (Type*)FixedVectorType::get(b.getInt32Ty(), 4);
        Value* w;
        if (et->isIntegerTy() && et->getIntegerBitWidth() < 32 && type_is_signed_name(e.type_name)) {
            Type* mid = isa<FixedVectorType>(t) ? (Type*)FixedVectorType::get(b.getInt32Ty(), cast<FixedVectorType>(t)->getNumElements()) : b.getInt32Ty();
            w = adapt(b, b.CreateSExt(v, mid), want);
        } else w = adapt(b, v, want);
        Function* f = get_placeholder(c.m, "xef.out.loc", b.getVoidTy(), {b.getInt32Ty(), b.getInt32Ty(), b.getInt32Ty(), want});
        b.CreateCall(f, {b.getInt32(loc), b.getInt32(e.rt_index), b.getInt32(0), w});
    } else if (k == "air.depth") {
        out_builtin(c, BI_FRAG_DEPTH, adapt(b, v, b.getFloatTy()));
        c.res.flags |= SF_WRITES_DEPTH;
        c.ps.depth_mode = e.depth_qualifier;
    } else if (k == "air.sample_mask") {
        out_builtin(c, BI_SAMPLE_MASK, adapt(b, v, b.getInt32Ty()));
        c.res.flags |= SF_WRITES_SAMPLE_MASK;
    } else if (k == "air.stencil") {
        out_builtin(c, BI_FRAG_STENCIL_REF, adapt(b, v, b.getInt32Ty()));
        c.res.flags |= SF_WRITES_STENCIL;
    }
}

// (g_ctor_values: values stored to globals by the static initializers, e.g. implicit function-constant predicates)

static bool predicate_true(Metadata* pred) {
    // the predicate references a function-constant global (now constant), a global written by a static
    // initializer, or a constant
    if (!pred) return true;
    if (auto* vm = dyn_cast<ValueAsMetadata>(pred)) {
        Value* v = vm->getValue();
        if (auto* g = dyn_cast<GlobalVariable>(v)) {
            auto it = g_ctor_values.find(g);
            if (it != g_ctor_values.end()) return it->second != 0;
            if (g->hasInitializer())
                if (auto* ci = dyn_cast<ConstantInt>(g->getInitializer())) return !ci->isZero();
            return false;
        }
        if (auto* ci = dyn_cast<ConstantInt>(v)) return !ci->isZero();
    }
    if (auto* n = dyn_cast<MDNode>(pred))
        if (n->getNumOperands()) return predicate_true(n->getOperand(0));
    return true;
}

bool prepare_stage(Module& m, AirEntry& e, const CompileRequest& req, LinkInfo& link, PreparedStage& ps, std::string& err) {
    LLVMContext& ctx = m.getContext();
    StageResult& res = *ps.res;
    ps.mod = &m;
    ps.stage = e.stage;
    ps.early_fragment_tests = e.early_fragment_tests;
    if (e.early_fragment_tests) res.flags |= SF_EARLY_FRAGMENT_TESTS;
    if (e.stage == StageKind::Kernel) {
        for (int i = 0; i < 3; i++) ps.tg_size[i] = req.tg_size[i] ? req.tg_size[i] : 1;
        memcpy(res.tg_size, ps.tg_size, sizeof(ps.tg_size));
    }

    {
        std::vector<FnConstant> consts = req.constants;
        for (auto& st : req.stages)
            if (st.function == e.fn->getName() && !st.constants.empty()) consts = st.constants;
        resolve_function_constants(m, consts);
    }

    Function* entry = e.fn;
    // build the wrapper
    Function* main = Function::Create(FunctionType::get(Type::getVoidTy(ctx), false), GlobalValue::ExternalLinkage, "xef.main", m);
    BasicBlock* bb = BasicBlock::Create(ctx, "entry", main);
    IRBuilder<> b(bb);
    ps.main = main;

    // static initializers run first; fold them to learn the implicit predicates they compute
    g_ctor_values.clear();
    if (GlobalVariable* ctors = m.getGlobalVariable("llvm.global_ctors")) {
        if (auto* arr = dyn_cast<ConstantArray>(ctors->getInitializer()))
            for (Use& u : arr->operands())
                if (auto* cs = dyn_cast<ConstantStruct>(u.get()))
                    if (auto* f = dyn_cast<Function>(cs->getOperand(1)->stripPointerCasts())) {
                        if (f->isDeclaration()) continue;
                        run_cleanup(*f, true);
                        for (BasicBlock& blk : *f)
                            for (Instruction& i : blk)
                                if (auto* st = dyn_cast<StoreInst>(&i))
                                    if (auto* g = dyn_cast<GlobalVariable>(st->getPointerOperand()->stripPointerCasts()))
                                        if (auto* ci = dyn_cast<ConstantInt>(st->getValueOperand())) g_ctor_values[g] = ci->getSExtValue();
                    }
    }
    if (GlobalVariable* ctors = m.getGlobalVariable("llvm.global_ctors")) {
        if (auto* arr = dyn_cast<ConstantArray>(ctors->getInitializer()))
            for (Use& u : arr->operands())
                if (auto* cs = dyn_cast<ConstantStruct>(u.get()))
                    if (auto* f = dyn_cast<Function>(cs->getOperand(1)->stripPointerCasts()))
                        b.CreateCall(f, {});
        ctors->eraseFromParent();
    }

    WrapperCtx c{m, ps, res, req, link, b, nullptr, err};
    Function* ptab = get_placeholder(m, "xef.pc.table", b.getInt64Ty(), {});
    c.table = b.CreateCall(ptab, {});

    // kernel: mask threads outside the dispatchThreads grid (only safe without barriers)
    BasicBlock* body = nullptr;
    if (e.stage == StageKind::Kernel && !module_has_barrier(m)) {
        Function* pcu = get_placeholder(m, "xef.pc.u32", b.getInt32Ty(), {b.getInt32Ty()});
        Value* flags = b.CreateCall(pcu, {b.getInt32(28)});
        Value* gid = in_builtin(c, BI_GLOBAL_INVOCATION_ID, FixedVectorType::get(b.getInt32Ty(), 3));
        Value* out = b.getFalse();
        for (unsigned i = 0; i < 3; i++) {
            Value* g = b.CreateCall(pcu, {b.getInt32(16 + 4 * i)});
            out = b.CreateOr(out, b.CreateICmpUGE(b.CreateExtractElement(gid, (uint64_t)i), g));
        }
        Value* check = b.CreateAnd(b.CreateICmpNE(b.CreateAnd(flags, PC_FLAG_GRID_BOUNDS), b.getInt32(0)), out);
        BasicBlock* exit = BasicBlock::Create(ctx, "grid_exit", main);
        body = BasicBlock::Create(ctx, "body", main);
        b.CreateCondBr(check, exit, body);
        IRBuilder<> eb(exit); eb.CreateRetVoid();
        b.SetInsertPoint(body);
        res.flags |= SF_GRID_BOUNDS;
    }

    std::vector<Value*> args(entry->arg_size(), nullptr);
    for (const AirElem& in : e.inputs) {
        if (in.arg_index < 0 || in.arg_index >= (int)entry->arg_size()) continue;
        Type* t = entry->getArg(in.arg_index)->getType();
        if (in.fc_predicate && !predicate_true(in.fc_predicate)) { args[in.arg_index] = PoisonValue::get(t); continue; }
        args[in.arg_index] = make_arg(c, in, t);
    }
    for (size_t i = 0; i < args.size(); i++)
        if (!args[i]) args[i] = PoisonValue::get(entry->getArg((unsigned)i)->getType());
    CallInst* call = b.CreateCall(entry, args);
    Type* rt = entry->getReturnType();
    if (!rt->isVoidTy()) {
        if (auto* st = dyn_cast<StructType>(rt)) {
            for (unsigned i = 0; i < e.outputs.size() && i < st->getNumElements(); i++)
                if (!e.outputs[i].fc_predicate || predicate_true(e.outputs[i].fc_predicate))
                    write_output(c, e.outputs[i], b.CreateExtractValue(call, {i}));
        } else if (!e.outputs.empty()) {
            if (!e.outputs[0].fc_predicate || predicate_true(e.outputs[0].fc_predicate)) write_output(c, e.outputs[0], call);
        }
    }
    if (e.stage == StageKind::Vertex && !(res.flags & SF_POINT_SIZE)) out_builtin(c, BI_POINT_SIZE, ConstantFP::get(b.getFloatTy(), 1.0));
    b.CreateRetVoid();
    if (e.stage == StageKind::Vertex) link.have_vertex = true;

    // inline everything into xef.main
    for (Function& f : m) {
        if (f.isDeclaration() || &f == main) continue;
        f.removeFnAttr(Attribute::NoInline);
        f.removeFnAttr(Attribute::OptimizeNone);
        f.addFnAttr(Attribute::AlwaysInline);
        if (&f != entry) f.setLinkage(GlobalValue::InternalLinkage);
    }
    run_mpm(m, [](ModulePassManager& mpm) { mpm.addPass(AlwaysInlinerPass(false)); });
    // the entry itself may not have been inlined if it is recursive (cannot happen in Metal)
    for (BasicBlock& blk : *main)
        for (Instruction& i : blk)
            if (auto* ci = dyn_cast<CallInst>(&i))
                if (ci->getCalledFunction() && !ci->getCalledFunction()->isDeclaration()) {
                    err = "could not inline " + ci->getCalledFunction()->getName().str();
                    return false;
                }
    // drop every other definition
    std::vector<Function*> dead;
    for (Function& f : m) if (&f != main && !f.isDeclaration()) dead.push_back(&f);
    for (Function* f : dead) { f->replaceAllUsesWith(PoisonValue::get(f->getType())); f->eraseFromParent(); }
    for (const char* md : {"air.vertex", "air.fragment", "air.kernel", "air.function_constants"})
        if (NamedMDNode* nm = m.getNamedMetadata(md)) nm->eraseFromParent();

    run_cleanup(*main, true);
    return true;
}

} // namespace mtlc
