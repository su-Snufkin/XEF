// SPIR-V emission: types, constants, interface variables, memory, generic instructions, structured CFG.
#include "emit.h"
#include "third_party/spirv/GLSL.std.450.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Operator.h"
#include "llvm/Support/raw_ostream.h"
#include <cstring>
#include <deque>

namespace mtlc {
using namespace llvm;
using namespace xef::mtlabi;

Emitter::Emitter(PreparedStage& p, std::string& e)
    : ps(p), m(*p.mod), f(*p.main), dl(p.mod->getDataLayout()), err(e) {
    fragment = ps.stage == StageKind::Fragment;
    vertex = ps.stage == StageKind::Vertex;
    kernel = ps.stage == StageKind::Kernel;
}

void Emitter::fail(const std::string& msg) {
    if (!failed) { err = msg; failed = true; }
}

Id Emitter::label(BasicBlock* bb) {
    auto it = labels.find(bb);
    if (it != labels.end()) return it->second;
    Id id = sb.alloc();
    labels[bb] = id;
    return id;
}

Id Emitter::id_of(Value* v) {
    auto it = vals.find(v);
    if (it != vals.end()) return it->second;
    Id id = sb.alloc();
    vals[v] = id;
    return id;
}

Id Emitter::val(Value* v) {
    if (auto* c = dyn_cast<Constant>(v)) {
        if (!isa<GlobalValue>(c)) return constant(c);
    }
    if (isa<Instruction>(v)) return id_of(v);
    if (auto* g = dyn_cast<GlobalVariable>(v)) {
        spv::StorageClass sc; Type* vt;
        return local_var(g, sc, vt);
    }
    fail("operand kind not supported");
    return sb.undef(sb.t_int(32));
}

void Emitter::result(Instruction* i, Id id) {
    auto it = vals.find(i);
    if (it == vals.end()) { vals[i] = id; return; }
    if (it->second == id) return;
    // the id was pre-allocated by a forward reference (phi): copy into it
    emit(spv::OpCopyObject, {ty(i->getType()), it->second, id});
}

Id Emitter::copy_into(Id type, Id src, Id dst) {
    emit(spv::OpCopyObject, {type, dst, src});
    return dst;
}

// ---------------- types ----------------

Id Emitter::ty(Type* t) {
    if (t->isVoidTy()) return sb.t_void();
    if (t->isIntegerTy(1)) return sb.t_bool();
    if (t->isIntegerTy()) {
        unsigned w = t->getIntegerBitWidth();
        if (w != 8 && w != 16 && w != 32 && w != 64) { fail("unsupported integer width i" + std::to_string(w)); return sb.t_int(32); }
        return sb.t_int(w);
    }
    if (t->isHalfTy()) return sb.t_float(16);
    if (t->isFloatTy()) return sb.t_float(32);
    if (t->isDoubleTy()) return sb.t_float(64);
    if (auto* v = dyn_cast<FixedVectorType>(t)) {
        unsigned n = v->getNumElements();
        if (n == 1) return ty(v->getElementType());
        if (n > 4) { fail("vector with more than 4 elements: " + type_tag(t)); return sb.t_int(32); }
        return sb.t_vec(ty(v->getElementType()), n);
    }
    if (auto* a = dyn_cast<ArrayType>(t)) return sb.t_array(ty(a->getElementType()), (uint32_t)a->getNumElements());
    if (auto* s = dyn_cast<StructType>(t)) {
        Words mem;
        for (Type* e : s->elements()) mem.push_back(ty(e));
        return sb.t_struct(mem);
    }
    if (t->isPointerTy()) return sb.t_int(64);
    fail("unsupported type " + type_tag(t));
    return sb.t_int(32);
}

static unsigned vec_len(Type* t) {
    if (auto* v = dyn_cast<FixedVectorType>(t)) return v->getNumElements();
    return 1;
}

Id Emitter::splat(Type* t, Id scalar) {
    unsigned n = vec_len(t);
    if (n == 1) return scalar;
    Words parts(n, scalar);
    return emit_r(spv::OpCompositeConstruct, ty(t), parts);
}

Id Emitter::const_like(Type* t, double fv, int64_t iv) {
    Type* e = t->getScalarType();
    Id s;
    if (e->isFloatTy()) s = sb.const_f32((float)fv);
    else if (e->isHalfTy()) s = constant(ConstantFP::get(e, fv));
    else if (e->isDoubleTy()) s = constant(ConstantFP::get(e, fv));
    else if (e->isIntegerTy(1)) s = sb.const_bool(iv != 0);
    else s = constant(ConstantInt::get(e, (uint64_t)iv, true));
    unsigned n = vec_len(t);
    if (n == 1) return s;
    return sb.const_composite(ty(t), Words(n, s));
}

// ---------------- constants ----------------

Id Emitter::constant(Constant* c) {
    auto it = vals.find(c);
    if (it != vals.end()) return it->second;
    Type* t = c->getType();
    Id r = 0;
    if (isa<PoisonValue>(c) || isa<UndefValue>(c)) {
        r = sb.undef(ty(t));
    } else if ((isa<ConstantInt>(c) || isa<ConstantFP>(c)) && t->isVectorTy()) {
        // vector splat constants (LLVM 23 ConstantInt/ConstantFP with vector type)
        Constant* s = isa<ConstantInt>(c) ? (Constant*)ConstantInt::get(t->getScalarType(), cast<ConstantInt>(c)->getValue())
                                          : (Constant*)ConstantFP::get(t->getScalarType(), cast<ConstantFP>(c)->getValueAPF());
        Id e = constant(s);
        r = vec_len(t) == 1 ? e : sb.const_composite(ty(t), Words(vec_len(t), e));
    } else if (auto* ci = dyn_cast<ConstantInt>(c)) {
        if (t->isIntegerTy(1)) r = sb.const_bool(!ci->isZero());
        else {
            unsigned w = t->getIntegerBitWidth();
            uint64_t v = ci->getZExtValue();
            if (w <= 32) r = sb.constant(ty(t), {(uint32_t)(w < 32 ? (v & ((1ull << w) - 1)) : v)});
            else r = sb.constant(ty(t), {(uint32_t)v, (uint32_t)(v >> 32)});
        }
    } else if (auto* cf = dyn_cast<ConstantFP>(c)) {
        uint64_t bits = cf->getValueAPF().bitcastToAPInt().getZExtValue();
        if (t->isDoubleTy()) r = sb.constant(ty(t), {(uint32_t)bits, (uint32_t)(bits >> 32)});
        else r = sb.constant(ty(t), {(uint32_t)bits});
    } else if (isa<ConstantAggregateZero>(c) || isa<ConstantPointerNull>(c)) {
        if (t->isPointerTy()) r = sb.const_u64(0);
        else r = sb.const_null(ty(t));
    } else if (auto* cds = dyn_cast<ConstantDataSequential>(c)) {
        if (vec_len(t) == 1 && t->isVectorTy()) r = constant(cds->getElementAsConstant(0));
        else {
            Words parts;
            for (unsigned i = 0; i < cds->getNumElements(); i++) parts.push_back(constant(cds->getElementAsConstant(i)));
            r = sb.const_composite(ty(t), parts);
        }
    } else if (isa<ConstantVector>(c) || isa<ConstantArray>(c) || isa<ConstantStruct>(c)) {
        if (t->isVectorTy() && vec_len(t) == 1) r = constant(cast<Constant>(c->getOperand(0)));
        else {
            Words parts;
            bool any_undef = false;
            for (unsigned i = 0; i < c->getNumOperands(); i++) {
                Constant* op = cast<Constant>(c->getOperand(i));
                if (isa<UndefValue>(op)) any_undef = true;
                parts.push_back(constant(op));
            }
            (void)any_undef;
            r = sb.const_composite(ty(t), parts);
        }
    } else if (auto* ce = dyn_cast<ConstantExpr>(c)) {
        // materialize as an instruction in the current block
        Instruction* inst = ce->getAsInstruction();
        BasicBlock* tmp = BasicBlock::Create(m.getContext(), "", &f);
        inst->insertInto(tmp, tmp->end());
        emit_inst(inst);
        r = vals.lookup(inst);
        vals.erase(inst);
        inst->eraseFromParent();
        tmp->eraseFromParent();
        return r;   // not cached: instruction result is block-local
    } else {
        fail("unsupported constant");
        r = sb.undef(ty(t));
    }
    vals[c] = r;
    return r;
}

// ---------------- interface ----------------

Id Emitter::push_constants() {
    if (pc_var) return pc_var;
    Id u64 = sb.t_int(64), u32 = sb.t_int(32);
    Id arr_t = sb.unique_type(spv::OpTypeArray, {u64, c_u32(2)});
    sb.decorate(arr_t, spv::DecorationArrayStride, {8});
    Id arr3 = sb.unique_type(spv::OpTypeArray, {u32, c_u32(3)});
    sb.decorate(arr3, spv::DecorationArrayStride, {4});
    pc_struct = sb.unique_type(spv::OpTypeStruct, {arr_t, arr3, u32, u32, u32});
    sb.decorate(pc_struct, spv::DecorationBlock);
    sb.member_decorate(pc_struct, 0, spv::DecorationOffset, {0});
    sb.member_decorate(pc_struct, 1, spv::DecorationOffset, {16});
    sb.member_decorate(pc_struct, 2, spv::DecorationOffset, {28});
    sb.member_decorate(pc_struct, 3, spv::DecorationOffset, {32});
    sb.member_decorate(pc_struct, 4, spv::DecorationOffset, {36});
    pc_var = sb.variable(sb.t_ptr(spv::StorageClassPushConstant, pc_struct), spv::StorageClassPushConstant);
    sb.name(pc_var, "xef_pc");
    interface_ids.push_back(pc_var);
    return pc_var;
}

Id Emitter::builtin_var(bool out, uint32_t bi, Id type) {
    auto& cache = out ? builtin_out : builtin_in;
    auto it = cache.find(bi);
    if (it != cache.end()) return it->second;
    spv::StorageClass sc = out ? spv::StorageClassOutput : spv::StorageClassInput;
    Id v = sb.variable(sb.t_ptr(sc, type), sc);
    sb.decorate(v, spv::DecorationBuiltIn, {bi});
    if (!out && fragment && (bi == BI_SAMPLE_ID || bi == BI_PRIMITIVE_ID || bi == BI_LAYER || bi == BI_VIEWPORT_INDEX))
        sb.decorate(v, spv::DecorationFlat);
    switch (bi) {
    case BI_SAMPLE_ID: sb.cap(spv::CapabilitySampleRateShading); break;
    case BI_CLIP_DISTANCE: sb.cap(spv::CapabilityClipDistance); break;
    case BI_LAYER: if (out) sb.cap(spv::CapabilityShaderLayer); else sb.cap(spv::CapabilityGeometry); break;
    case BI_VIEWPORT_INDEX: if (out) sb.cap(spv::CapabilityShaderViewportIndex); else sb.cap(spv::CapabilityMultiViewport); break;
    case BI_BASE_VERTEX: case BI_BASE_INSTANCE: sb.cap(spv::CapabilityDrawParameters); break;
    case BI_FRAG_STENCIL_REF: sb.cap(spv::CapabilityStencilExportEXT); sb.ext("SPV_EXT_shader_stencil_export"); break;
    case BI_BARY_COORD: sb.cap(spv::CapabilityFragmentBarycentricKHR); sb.ext("SPV_KHR_fragment_shader_barycentric"); break;
    case BI_SUBGROUP_SIZE: case BI_SUBGROUP_LOCAL_INVOCATION_ID: case BI_SUBGROUP_ID: case BI_NUM_SUBGROUPS:
        sb.cap(spv::CapabilityGroupNonUniform); break;
    case BI_PRIMITIVE_ID: if (fragment) sb.cap(spv::CapabilityGeometry); break;
    default: break;
    }
    cache[bi] = v;
    interface_ids.push_back(v);
    return v;
}

Id Emitter::location_var(bool out, uint32_t loc, uint32_t index, uint32_t interp, Id type) {
    auto& cache = out ? loc_out : loc_in;
    uint64_t key = ((uint64_t)index << 32) | loc;
    auto it = cache.find(key);
    if (it != cache.end()) return it->second;
    spv::StorageClass sc = out ? spv::StorageClassOutput : spv::StorageClassInput;
    Id v = sb.variable(sb.t_ptr(sc, type), sc);
    sb.decorate(v, spv::DecorationLocation, {loc});
    if (index) sb.decorate(v, spv::DecorationIndex, {index});
    bool varying = (fragment && !out) || (vertex && out);
    if (varying) {
        if (interp & INTERP_FLAT) sb.decorate(v, spv::DecorationFlat);
        else {
            if (interp & INTERP_NOPERSPECTIVE) sb.decorate(v, spv::DecorationNoPerspective);
            if (interp & INTERP_CENTROID) sb.decorate(v, spv::DecorationCentroid);
            if (interp & INTERP_SAMPLE) { sb.decorate(v, spv::DecorationSample); sb.cap(spv::CapabilitySampleRateShading); }
        }
    }
    cache[key] = v;
    interface_ids.push_back(v);
    return v;
}

// ---------------- memory ----------------

Id Emitter::psb_pointer(Value* addr_ptr, Id pointee) {
    // addr_ptr is `inttoptr i64 x` (or a constant inttoptr)
    Value* addr = nullptr;
    if (auto* ip = dyn_cast<IntToPtrInst>(addr_ptr)) addr = ip->getOperand(0);
    else if (auto* ce = dyn_cast<ConstantExpr>(addr_ptr)) { if (ce->getOpcode() == Instruction::IntToPtr) addr = ce->getOperand(0); }
    if (!addr) { fail("device access through a non-inttoptr pointer"); return 0; }
    Id a = val(addr);
    if (!addr->getType()->isIntegerTy(64)) a = emit_r(spv::OpUConvert, sb.t_int(64), {a});
    return emit_r(spv::OpConvertUToPtr, sb.t_ptr(spv::StorageClassPhysicalStorageBuffer, pointee), {a});
}

Id Emitter::local_var(Value* base, spv::StorageClass& sc, Type*& vty) {
    auto it = local_vars.find(base);
    if (auto* a = dyn_cast<AllocaInst>(base)) {
        sc = spv::StorageClassFunction;
        vty = a->getAllocatedType();
        if (it != local_vars.end()) return it->second;
        Id v = sb.alloc();
        SpvBuilder::inst(fvars, spv::OpVariable, {sb.t_ptr(sc, ty(vty)), v, (uint32_t)sc});
        local_vars[base] = v;
        return v;
    }
    if (auto* g = dyn_cast<GlobalVariable>(base)) {
        vty = g->getValueType();
        sc = g->getAddressSpace() == 3 ? spv::StorageClassWorkgroup : spv::StorageClassPrivate;
        if (it != local_vars.end()) return it->second;
        Id init = 0;
        if (sc == spv::StorageClassPrivate && g->hasInitializer() && !isa<UndefValue>(g->getInitializer())) init = constant(g->getInitializer());
        Id v = sb.variable(sb.t_ptr(sc, ty(vty)), sc, init);
        sb.name(v, g->getName().str());
        local_vars[base] = v;
        interface_ids.push_back(v);
        return v;
    }
    fail("unsupported local pointer base");
    return 0;
}

// pointer into a function/workgroup variable: base + byte offset -> OpAccessChain to a leaf element
bool Emitter::local_pointer(Value* p, Id& ptr_id, Type*& elem_ty, spv::StorageClass& sc) {
    // collect the byte offset
    Value* base = p;
    int64_t coff = 0;
    std::vector<std::pair<Value*, int64_t>> vars;   // (index, scale)
    while (true) {
        if (auto* g = dyn_cast<GEPOperator>(base)) {
            SmallMapVector<Value*, APInt, 4> var;
            APInt cst(64, 0);
            if (!g->collectOffset(dl, 64, var, cst)) { fail("local GEP offset"); return false; }
            coff += cst.getSExtValue();
            for (auto& [v, s] : var) vars.push_back({v, s.getSExtValue()});
            base = g->getPointerOperand();
            continue;
        }
        if (auto* bc = dyn_cast<BitCastOperator>(base)) { base = bc->getOperand(0); continue; }
        break;
    }
    Type* vty;
    Id var = local_var(base, sc, vty);
    if (!var) return false;
    // walk the variable type: arrays of uniform leaf elements are indexed by offset / element size
    Words chain;
    Type* cur = vty;
    Id dyn = 0;   // dynamic byte offset (u32)
    for (auto& [v, scale] : vars) {
        Id x = val(v);
        Type* it = v->getType();
        if (it->getIntegerBitWidth() != 32) {
            if (it->getIntegerBitWidth() > 32) x = emit_r(spv::OpUConvert, t_u32(), {x});
            else x = emit_r(spv::OpSConvert, t_u32(), {x});
        }
        if (scale != 1) x = emit_r(spv::OpIMul, t_u32(), {x, c_u32((uint32_t)scale)});
        dyn = dyn ? emit_r(spv::OpIAdd, t_u32(), {dyn, x}) : x;
    }
    while (true) {
        if (auto* at = dyn_cast<ArrayType>(cur)) {
            uint64_t es = dl.getTypeAllocSize(at->getElementType());
            Id idx;
            if (dyn) {
                Id off = coff ? emit_r(spv::OpIAdd, t_u32(), {dyn, c_u32((uint32_t)coff)}) : dyn;
                if ((es & (es - 1)) == 0) idx = emit_r(spv::OpShiftRightLogical, t_u32(), {off, c_u32((uint32_t)__builtin_ctzll(es))});
                else idx = emit_r(spv::OpUDiv, t_u32(), {off, c_u32((uint32_t)es)});
                // remaining offset inside the element must be static zero for leaf arrays
                dyn = 0; coff = 0;
            } else {
                idx = c_u32((uint32_t)(coff / (int64_t)es));
                coff = coff % (int64_t)es;
            }
            chain.push_back(idx);
            cur = at->getElementType();
            continue;
        }
        if (auto* st = dyn_cast<StructType>(cur)) {
            if (dyn) { fail("dynamic offset into struct variable"); return false; }
            const StructLayout* sl = dl.getStructLayout(st);
            unsigned idx = sl->getElementContainingOffset((uint64_t)coff);
            coff -= (int64_t)sl->getElementOffset(idx);
            chain.push_back(c_u32(idx));
            cur = st->getElementType(idx);
            continue;
        }
        if (auto* vt = dyn_cast<FixedVectorType>(cur)) {
            if (vt->getNumElements() == 1) { cur = vt->getElementType(); continue; }
            uint64_t es = dl.getTypeAllocSize(vt->getElementType());
            Id idx;
            if (dyn) {
                Id off = coff ? emit_r(spv::OpIAdd, t_u32(), {dyn, c_u32((uint32_t)coff)}) : dyn;
                idx = emit_r(spv::OpUDiv, t_u32(), {off, c_u32((uint32_t)es)});
                dyn = 0; coff = 0;
            } else { idx = c_u32((uint32_t)(coff / (int64_t)es)); coff %= (int64_t)es; }
            chain.push_back(idx);
            cur = vt->getElementType();
            continue;
        }
        break;
    }
    if (dyn || coff) { fail("unaligned local access"); return false; }
    elem_ty = cur;
    if (chain.empty()) { ptr_id = var; return true; }
    Words ops{var};
    ops.insert(ops.end(), chain.begin(), chain.end());
    ptr_id = emit_r(spv::OpAccessChain, sb.t_ptr(sc, ty(cur)), ops);
    return true;
}

static bool is_psb_ptr(Value* p) {
    if (isa<IntToPtrInst>(p)) return true;
    if (auto* ce = dyn_cast<ConstantExpr>(p)) return ce->getOpcode() == Instruction::IntToPtr;
    return false;
}

static void storage_caps(SpvBuilder& sb, Type* t) {
    Type* e = t->getScalarType();
    if (e->isIntegerTy(8)) { sb.cap(spv::CapabilityStorageBuffer8BitAccess); }
    if (e->isIntegerTy(16) || e->isHalfTy()) { sb.cap(spv::CapabilityStorageBuffer16BitAccess); }
}

void Emitter::emit_load(LoadInst* li) {
    Value* p = li->getPointerOperand();
    Type* t = li->getType();
    if (is_psb_ptr(p)) {
        storage_caps(sb, t);
        Id ptr = psb_pointer(p, ty(t));
        uint32_t al = (uint32_t)li->getAlign().value();
        Id r = id_of(li);
        if (li->isAtomic()) {
            emit(spv::OpAtomicLoad, {ty(t), r, ptr, c_u32(spv::ScopeDevice), c_u32(0)});
        } else {
            emit(spv::OpLoad, {ty(t), r, ptr, (uint32_t)spv::MemoryAccessAlignedMask, al});
        }
        return;
    }
    Id ptr; Type* et; spv::StorageClass sc;
    if (!local_pointer(p, ptr, et, sc)) return;
    Id r;
    if (li->isAtomic()) r = emit_r(spv::OpAtomicLoad, ty(et), {ptr, c_u32(sc == spv::StorageClassWorkgroup ? spv::ScopeWorkgroup : spv::ScopeInvocation), c_u32(0)});
    else r = emit_r(spv::OpLoad, ty(et), {ptr});
    if (et != t) {
        if (dl.getTypeStoreSize(et) == dl.getTypeStoreSize(t) && !t->isAggregateType()) r = emit_r(spv::OpBitcast, ty(t), {r});
        else { fail("local load type mismatch " + type_tag(et) + " vs " + type_tag(t)); return; }
    }
    result(li, r);
}

void Emitter::emit_store(StoreInst* si) {
    Value* p = si->getPointerOperand();
    Value* v = si->getValueOperand();
    Type* t = v->getType();
    if (is_psb_ptr(p)) {
        storage_caps(sb, t);
        Id ptr = psb_pointer(p, ty(t));
        if (si->isAtomic()) emit(spv::OpAtomicStore, {ptr, c_u32(spv::ScopeDevice), c_u32(0), val(v)});
        else emit(spv::OpStore, {ptr, val(v), (uint32_t)spv::MemoryAccessAlignedMask, (uint32_t)si->getAlign().value()});
        return;
    }
    Id ptr; Type* et; spv::StorageClass sc;
    if (!local_pointer(p, ptr, et, sc)) return;
    Id x = val(v);
    if (et != t) {
        if (dl.getTypeStoreSize(et) == dl.getTypeStoreSize(t) && !t->isAggregateType()) x = emit_r(spv::OpBitcast, ty(et), {x});
        else { fail("local store type mismatch"); return; }
    }
    if (si->isAtomic()) emit(spv::OpAtomicStore, {ptr, c_u32(sc == spv::StorageClassWorkgroup ? spv::ScopeWorkgroup : spv::ScopeInvocation), c_u32(0), x});
    else emit(spv::OpStore, {ptr, x});
}

Id Emitter::atomic_pointer(Value* p, Type* vt, uint32_t& scope) {
    if (is_psb_ptr(p)) {
        scope = spv::ScopeDevice;
        if (vt->isIntegerTy(64)) sb.cap(spv::CapabilityInt64Atomics);
        return psb_pointer(p, ty(vt));
    }
    Id ptr; Type* et; spv::StorageClass sc;
    if (!local_pointer(p, ptr, et, sc)) return 0;
    scope = sc == spv::StorageClassWorkgroup ? spv::ScopeWorkgroup : spv::ScopeInvocation;
    if (et != vt) { fail("atomic type mismatch"); return 0; }
    return ptr;
}

void Emitter::emit_atomicrmw(AtomicRMWInst* a) {
    Type* vt = a->getValOperand()->getType();
    uint32_t scope;
    Id ptr = atomic_pointer(a->getPointerOperand(), vt, scope);
    if (!ptr) return;
    spv::Op op;
    switch (a->getOperation()) {
    case AtomicRMWInst::Add: op = spv::OpAtomicIAdd; break;
    case AtomicRMWInst::Sub: op = spv::OpAtomicISub; break;
    case AtomicRMWInst::And: op = spv::OpAtomicAnd; break;
    case AtomicRMWInst::Or: op = spv::OpAtomicOr; break;
    case AtomicRMWInst::Xor: op = spv::OpAtomicXor; break;
    case AtomicRMWInst::Max: op = spv::OpAtomicSMax; break;
    case AtomicRMWInst::Min: op = spv::OpAtomicSMin; break;
    case AtomicRMWInst::UMax: op = spv::OpAtomicUMax; break;
    case AtomicRMWInst::UMin: op = spv::OpAtomicUMin; break;
    case AtomicRMWInst::Xchg: op = spv::OpAtomicExchange; break;
    case AtomicRMWInst::FAdd:
        op = spv::OpAtomicFAddEXT;
        sb.ext("SPV_EXT_shader_atomic_float_add");
        sb.cap(vt->isDoubleTy() ? spv::CapabilityAtomicFloat64AddEXT : vt->isHalfTy() ? spv::CapabilityAtomicFloat16AddEXT : spv::CapabilityAtomicFloat32AddEXT);
        break;
    case AtomicRMWInst::FMin: case AtomicRMWInst::FMax:
        op = a->getOperation() == AtomicRMWInst::FMin ? spv::OpAtomicFMinEXT : spv::OpAtomicFMaxEXT;
        sb.ext("SPV_EXT_shader_atomic_float_min_max");
        sb.cap(spv::CapabilityAtomicFloat32MinMaxEXT);
        break;
    default: fail("unsupported atomicrmw"); return;
    }
    Id r = id_of(a);
    emit(op, {ty(vt), r, ptr, c_u32(scope), c_u32(0), val(a->getValOperand())});
}

void Emitter::emit_cmpxchg(AtomicCmpXchgInst* a) {
    Type* vt = a->getNewValOperand()->getType();
    uint32_t scope;
    Id ptr = atomic_pointer(a->getPointerOperand(), vt, scope);
    if (!ptr) return;
    Id old = emit_r(spv::OpAtomicCompareExchange, ty(vt), {ptr, c_u32(scope), c_u32(0), c_u32(0), val(a->getNewValOperand()), val(a->getCompareOperand())});
    Id ok = emit_r(spv::OpIEqual, sb.t_bool(), {old, val(a->getCompareOperand())});
    Id r = emit_r(spv::OpCompositeConstruct, ty(a->getType()), {old, ok});
    result(a, r);
}

// ---------------- conversions ----------------

Id Emitter::to_bool(Value* v) {
    Type* t = v->getType();
    if (t->getScalarType()->isIntegerTy(1)) return val(v);
    Type* bt = t->isVectorTy() ? (Type*)FixedVectorType::get(Type::getInt1Ty(m.getContext()), vec_len(t)) : Type::getInt1Ty(m.getContext());
    if (t->getScalarType()->isFloatingPointTy()) return emit_r(spv::OpFUnordNotEqual, ty(bt), {val(v), const_like(t, 0, 0)});
    return emit_r(spv::OpINotEqual, ty(bt), {val(v), const_like(t, 0, 0)});
}

Id Emitter::convert_numeric_ids(Id v, Type* from, Type* to, bool src_signed) {
    if (from == to) return v;
    Type* fe = from->getScalarType();
    Type* te = to->getScalarType();
    Id tt = ty(to);
    if (fe->isFloatingPointTy() && te->isFloatingPointTy()) return emit_r(spv::OpFConvert, tt, {v});
    if (fe->isIntegerTy(1)) {
        Id one = const_like(to, 1.0, src_signed ? -1 : 1), zero = const_like(to, 0, 0);
        return emit_r(spv::OpSelect, tt, {v, one, zero});
    }
    if (te->isIntegerTy(1)) {
        if (fe->isFloatingPointTy()) return emit_r(spv::OpFUnordNotEqual, tt, {v, const_like(from, 0, 0)});
        return emit_r(spv::OpINotEqual, tt, {v, const_like(from, 0, 0)});
    }
    if (fe->isIntegerTy() && te->isIntegerTy()) {
        if (fe->getIntegerBitWidth() == te->getIntegerBitWidth()) return v;
        if (fe->getIntegerBitWidth() > te->getIntegerBitWidth()) return emit_r(spv::OpUConvert, tt, {v});
        return emit_r(src_signed ? spv::OpSConvert : spv::OpUConvert, tt, {v});
    }
    if (fe->isIntegerTy() && te->isFloatingPointTy()) return emit_r(src_signed ? spv::OpConvertSToF : spv::OpConvertUToF, tt, {v});
    if (fe->isFloatingPointTy() && te->isIntegerTy()) return emit_r(src_signed ? spv::OpConvertFToS : spv::OpConvertFToU, tt, {v});
    fail("bad numeric conversion");
    return v;
}

Id Emitter::convert_numeric(Id v, Type* from, Type* to, bool src_signed, bool dst_signed) {
    Type* fe = from->getScalarType();
    Type* te = to->getScalarType();
    if (fe->isFloatingPointTy() && te->isIntegerTy() && !te->isIntegerTy(1))
        return emit_r(dst_signed ? spv::OpConvertFToS : spv::OpConvertFToU, ty(to), {v});
    return convert_numeric_ids(v, from, to, src_signed);
}

// ---------------- generic instructions ----------------

static spv::Op int_binop(unsigned opc) {
    switch (opc) {
    case Instruction::Add: return spv::OpIAdd;
    case Instruction::Sub: return spv::OpISub;
    case Instruction::Mul: return spv::OpIMul;
    case Instruction::UDiv: return spv::OpUDiv;
    case Instruction::SDiv: return spv::OpSDiv;
    case Instruction::URem: return spv::OpUMod;
    case Instruction::SRem: return spv::OpSRem;
    case Instruction::Shl: return spv::OpShiftLeftLogical;
    case Instruction::LShr: return spv::OpShiftRightLogical;
    case Instruction::AShr: return spv::OpShiftRightArithmetic;
    case Instruction::And: return spv::OpBitwiseAnd;
    case Instruction::Or: return spv::OpBitwiseOr;
    case Instruction::Xor: return spv::OpBitwiseXor;
    case Instruction::FAdd: return spv::OpFAdd;
    case Instruction::FSub: return spv::OpFSub;
    case Instruction::FMul: return spv::OpFMul;
    case Instruction::FDiv: return spv::OpFDiv;
    case Instruction::FRem: return spv::OpFRem;
    default: return spv::OpNop;
    }
}

void Emitter::emit_inst(Instruction* i) {
    if (failed) return;
    unsigned opc = i->getOpcode();
    Type* t = i->getType();
    if (auto* bo = dyn_cast<BinaryOperator>(i)) {
        Value* a = bo->getOperand(0);
        Value* b = bo->getOperand(1);
        if (t->getScalarType()->isIntegerTy(1)) {
            spv::Op op;
            switch (opc) {
            case Instruction::And: case Instruction::Mul: op = spv::OpLogicalAnd; break;
            case Instruction::Or: op = spv::OpLogicalOr; break;
            case Instruction::Xor: case Instruction::Add: case Instruction::Sub: op = spv::OpLogicalNotEqual; break;
            default: fail("bool arithmetic"); return;
            }
            emit(op, {ty(t), id_of(i), val(a), val(b)});
            return;
        }
        spv::Op op = int_binop(opc);
        if (op == spv::OpNop) { fail("unsupported binary op"); return; }
        emit(op, {ty(t), id_of(i), val(a), val(b)});
        return;
    }
    switch (opc) {
    case Instruction::FNeg:
        emit(spv::OpFNegate, {ty(t), id_of(i), val(i->getOperand(0))});
        return;
    case Instruction::ICmp: {
        auto* c = cast<ICmpInst>(i);
        Type* ot = c->getOperand(0)->getType();
        spv::Op op;
        bool isbool = ot->getScalarType()->isIntegerTy(1);
        switch (c->getPredicate()) {
        case CmpInst::ICMP_EQ: op = isbool ? spv::OpLogicalEqual : spv::OpIEqual; break;
        case CmpInst::ICMP_NE: op = isbool ? spv::OpLogicalNotEqual : spv::OpINotEqual; break;
        case CmpInst::ICMP_UGT: op = spv::OpUGreaterThan; break;
        case CmpInst::ICMP_UGE: op = spv::OpUGreaterThanEqual; break;
        case CmpInst::ICMP_ULT: op = spv::OpULessThan; break;
        case CmpInst::ICMP_ULE: op = spv::OpULessThanEqual; break;
        case CmpInst::ICMP_SGT: op = spv::OpSGreaterThan; break;
        case CmpInst::ICMP_SGE: op = spv::OpSGreaterThanEqual; break;
        case CmpInst::ICMP_SLT: op = spv::OpSLessThan; break;
        case CmpInst::ICMP_SLE: op = spv::OpSLessThanEqual; break;
        default: fail("icmp predicate"); return;
        }
        Id a = val(c->getOperand(0)), b = val(c->getOperand(1));
        if (isbool && op != spv::OpLogicalEqual && op != spv::OpLogicalNotEqual) {
            Type* it = ot->isVectorTy() ? (Type*)FixedVectorType::get(Type::getInt32Ty(m.getContext()), vec_len(ot)) : Type::getInt32Ty(m.getContext());
            a = convert_numeric_ids(a, ot, it, false);
            b = convert_numeric_ids(b, ot, it, false);
        }
        emit(op, {ty(t), id_of(i), a, b});
        return;
    }
    case Instruction::FCmp: {
        auto* c = cast<FCmpInst>(i);
        Id a = val(c->getOperand(0)), b = val(c->getOperand(1));
        Id bt = ty(t);
        spv::Op op = spv::OpNop;
        switch (c->getPredicate()) {
        case CmpInst::FCMP_OEQ: op = spv::OpFOrdEqual; break;
        case CmpInst::FCMP_ONE: op = spv::OpFOrdNotEqual; break;
        case CmpInst::FCMP_OLT: op = spv::OpFOrdLessThan; break;
        case CmpInst::FCMP_OLE: op = spv::OpFOrdLessThanEqual; break;
        case CmpInst::FCMP_OGT: op = spv::OpFOrdGreaterThan; break;
        case CmpInst::FCMP_OGE: op = spv::OpFOrdGreaterThanEqual; break;
        case CmpInst::FCMP_UEQ: op = spv::OpFUnordEqual; break;
        case CmpInst::FCMP_UNE: op = spv::OpFUnordNotEqual; break;
        case CmpInst::FCMP_ULT: op = spv::OpFUnordLessThan; break;
        case CmpInst::FCMP_ULE: op = spv::OpFUnordLessThanEqual; break;
        case CmpInst::FCMP_UGT: op = spv::OpFUnordGreaterThan; break;
        case CmpInst::FCMP_UGE: op = spv::OpFUnordGreaterThanEqual; break;
        case CmpInst::FCMP_ORD: case CmpInst::FCMP_UNO: {
            Id na = emit_r(spv::OpIsNan, bt, {a});
            Id nb = emit_r(spv::OpIsNan, bt, {b});
            Id any = emit_r(spv::OpLogicalOr, bt, {na, nb});
            if (c->getPredicate() == CmpInst::FCMP_UNO) result(i, any);
            else result(i, emit_r(spv::OpLogicalNot, bt, {any}));
            return;
        }
        case CmpInst::FCMP_TRUE: result(i, const_like(t, 0, 1)); return;
        case CmpInst::FCMP_FALSE: result(i, const_like(t, 0, 0)); return;
        default: fail("fcmp predicate"); return;
        }
        emit(op, {bt, id_of(i), a, b});
        return;
    }
    case Instruction::Select: {
        auto* s = cast<SelectInst>(i);
        emit(spv::OpSelect, {ty(t), id_of(i), val(s->getCondition()), val(s->getTrueValue()), val(s->getFalseValue())});
        return;
    }
    case Instruction::Trunc: case Instruction::ZExt: case Instruction::SExt: {
        Type* from = i->getOperand(0)->getType();
        Id v = val(i->getOperand(0));
        Id r;
        if (opc == Instruction::Trunc && t->getScalarType()->isIntegerTy(1)) {
            Id one = const_like(from, 0, 1);
            Id masked = emit_r(spv::OpBitwiseAnd, ty(from), {v, one});
            r = emit_r(spv::OpINotEqual, ty(t), {masked, const_like(from, 0, 0)});
        } else r = convert_numeric_ids(v, from, t, opc == Instruction::SExt);
        result(i, r);
        return;
    }
    case Instruction::FPTrunc: case Instruction::FPExt:
        emit(spv::OpFConvert, {ty(t), id_of(i), val(i->getOperand(0))});
        return;
    case Instruction::FPToUI: case Instruction::FPToSI:
        if (t->getScalarType()->isIntegerTy(1)) { result(i, to_bool(i->getOperand(0))); return; }
        emit(opc == Instruction::FPToUI ? spv::OpConvertFToU : spv::OpConvertFToS, {ty(t), id_of(i), val(i->getOperand(0))});
        return;
    case Instruction::UIToFP: case Instruction::SIToFP: {
        Type* from = i->getOperand(0)->getType();
        if (from->getScalarType()->isIntegerTy(1)) {
            result(i, emit_r(spv::OpSelect, ty(t), {val(i->getOperand(0)), const_like(t, opc == Instruction::SIToFP ? -1.0 : 1.0, 0), const_like(t, 0, 0)}));
            return;
        }
        emit(opc == Instruction::UIToFP ? spv::OpConvertUToF : spv::OpConvertSToF, {ty(t), id_of(i), val(i->getOperand(0))});
        return;
    }
    case Instruction::BitCast: {
        Type* from = i->getOperand(0)->getType();
        if (from == t || (vec_len(from) == 1 && vec_len(t) == 1 && from->getScalarType() == t->getScalarType())) {
            result(i, val(i->getOperand(0)));
            return;
        }
        emit(spv::OpBitcast, {ty(t), id_of(i), val(i->getOperand(0))});
        return;
    }
    case Instruction::IntToPtr:
        return;   // consumed by memory instructions / calls
    case Instruction::PtrToInt: {
        Value* p = i->getOperand(0);
        if (auto* ip = dyn_cast<IntToPtrInst>(p)) {
            Id v = val(ip->getOperand(0));
            result(i, convert_numeric_ids(v, ip->getOperand(0)->getType(), t, false));
            return;
        }
        if (isa<CallInst>(p)) { result(i, sb.const_null(ty(t))); return; }
        fail("ptrtoint of non-integer pointer");
        return;
    }
    case Instruction::ExtractElement: {
        auto* e = cast<ExtractElementInst>(i);
        Value* vec = e->getVectorOperand();
        if (vec_len(vec->getType()) == 1) { result(i, val(vec)); return; }
        if (auto* ci = dyn_cast<ConstantInt>(e->getIndexOperand()))
            emit(spv::OpCompositeExtract, {ty(t), id_of(i), val(vec), (uint32_t)ci->getZExtValue()});
        else {
            Value* ix = e->getIndexOperand();
            Id idx = ix->getType()->isIntegerTy(32) ? val(ix) : convert_numeric_ids(val(ix), ix->getType(), Type::getInt32Ty(m.getContext()), false);
            emit(spv::OpVectorExtractDynamic, {ty(t), id_of(i), val(vec), idx});
        }
        return;
    }
    case Instruction::InsertElement: {
        auto* e = cast<InsertElementInst>(i);
        if (vec_len(t) == 1) { result(i, val(e->getOperand(1))); return; }
        if (auto* ci = dyn_cast<ConstantInt>(e->getOperand(2)))
            emit(spv::OpCompositeInsert, {ty(t), id_of(i), val(e->getOperand(1)), val(e->getOperand(0)), (uint32_t)ci->getZExtValue()});
        else {
            Value* ix = e->getOperand(2);
            Id idx = ix->getType()->isIntegerTy(32) ? val(ix) : convert_numeric_ids(val(ix), ix->getType(), Type::getInt32Ty(m.getContext()), false);
            emit(spv::OpVectorInsertDynamic, {ty(t), id_of(i), val(e->getOperand(0)), val(e->getOperand(1)), idx});
        }
        return;
    }
    case Instruction::ShuffleVector: {
        auto* sv = cast<ShuffleVectorInst>(i);
        ArrayRef<int> mask = sv->getShuffleMask();
        Value* a = sv->getOperand(0);
        Value* b = sv->getOperand(1);
        unsigned na = vec_len(a->getType());
        Type* et = t->getScalarType();
        if (vec_len(t) == 1) {   // single element result
            int k = mask[0];
            if (k < 0) { result(i, sb.undef(ty(et))); return; }
            Value* src = (unsigned)k < na ? a : b;
            unsigned idx = (unsigned)k < na ? (unsigned)k : (unsigned)k - na;
            if (vec_len(src->getType()) == 1) { result(i, val(src)); return; }
            emit(spv::OpCompositeExtract, {ty(et), id_of(i), val(src), idx});
            return;
        }
        if (na == 1) {   // operands are <1 x T>: build with composite construct
            Words parts;
            for (int k : mask) parts.push_back(k < 0 ? sb.undef(ty(et)) : val(k == 0 ? a : b));
            Words ops{ty(t), id_of(i)}; ops.insert(ops.end(), parts.begin(), parts.end());
            emit(spv::OpCompositeConstruct, ops);
            return;
        }
        Words ops{ty(t), id_of(i), val(a), val(b)};
        for (int k : mask) ops.push_back(k < 0 ? 0xFFFFFFFFu : (uint32_t)k);
        emit(spv::OpVectorShuffle, ops);
        return;
    }
    case Instruction::ExtractValue: {
        auto* e = cast<ExtractValueInst>(i);
        Words ops{ty(t), id_of(i), val(e->getAggregateOperand())};
        for (unsigned k : e->getIndices()) ops.push_back(k);
        emit(spv::OpCompositeExtract, ops);
        return;
    }
    case Instruction::InsertValue: {
        auto* e = cast<InsertValueInst>(i);
        Words ops{ty(t), id_of(i), val(e->getInsertedValueOperand()), val(e->getAggregateOperand())};
        for (unsigned k : e->getIndices()) ops.push_back(k);
        emit(spv::OpCompositeInsert, ops);
        return;
    }
    case Instruction::Freeze:
        result(i, val(i->getOperand(0)));
        return;
    case Instruction::Load: emit_load(cast<LoadInst>(i)); return;
    case Instruction::Store: emit_store(cast<StoreInst>(i)); return;
    case Instruction::AtomicRMW: emit_atomicrmw(cast<AtomicRMWInst>(i)); return;
    case Instruction::AtomicCmpXchg: emit_cmpxchg(cast<AtomicCmpXchgInst>(i)); return;
    case Instruction::Fence: {
        emit(spv::OpMemoryBarrier, {c_u32(spv::ScopeDevice), c_u32(spv::MemorySemanticsAcquireReleaseMask | spv::MemorySemanticsUniformMemoryMask | spv::MemorySemanticsWorkgroupMemoryMask)});
        return;
    }
    case Instruction::Alloca: {
        spv::StorageClass sc; Type* vt;
        local_var(i, sc, vt);
        return;
    }
    case Instruction::GetElementPtr:
        return;   // folded into the accesses (local_pointer)
    case Instruction::Call: emit_call(cast<CallInst>(i)); return;
    case Instruction::PHI: {
        auto* phi = cast<PHINode>(i);
        Words ops{ty(t), id_of(i)};
        for (unsigned k = 0; k < phi->getNumIncomingValues(); k++) {
            ops.push_back(val(phi->getIncomingValue(k)));
            ops.push_back(label(phi->getIncomingBlock(k)));
        }
        emit(spv::OpPhi, ops);
        return;
    }
    case Instruction::UncondBr: {
        auto* br = cast<UncondBrInst>(i);
        BasicBlock* bb = i->getParent();
        if (merge_of.count(bb) && continue_of.count(bb))
            emit(spv::OpLoopMerge, {label(merge_of[bb]), label(continue_of[bb]), 0});
        emit(spv::OpBranch, {label(br->getSuccessor(0))});
        return;
    }
    case Instruction::CondBr: {
        auto* br = cast<CondBrInst>(i);
        BasicBlock* bb = i->getParent();
        if (merge_of.count(bb)) {
            if (continue_of.count(bb)) emit(spv::OpLoopMerge, {label(merge_of[bb]), label(continue_of[bb]), 0});
            else emit(spv::OpSelectionMerge, {label(merge_of[bb]), 0});
        }
        emit(spv::OpBranchConditional, {val(br->getCondition()), label(br->getSuccessor(0)), label(br->getSuccessor(1))});
        return;
    }
    case Instruction::Ret:
        emit(spv::OpReturn, {});
        return;
    case Instruction::Unreachable:
        emit(spv::OpUnreachable, {});
        return;
    default:
        fail(std::string("unsupported instruction ") + i->getOpcodeName());
    }
}

// ---------------- structure ----------------

void Emitter::compute_structure() {
    StructureInfo si;
    if (!compute_structure_info(f, si)) { fail("malformed loop after structurization"); return; }
    order = std::move(si.order);
    for (auto& [h, m] : si.merge) merge_of[h] = m;
    for (auto& [h, c] : si.cont) continue_of[h] = c;
}

void Emitter::emit_block(BasicBlock* bb) {
    if (bb != &f.getEntryBlock()) emit(spv::OpLabel, {label(bb)});
    for (Instruction& i : *bb) {
        emit_inst(&i);
        if (failed) return;
    }
}

// ---------------- driver ----------------

bool Emitter::run(std::vector<uint32_t>& out) {
    sb.cap(spv::CapabilityShader);
    sb.cap(spv::CapabilityPhysicalStorageBufferAddresses);
    SpvBuilder::inst(sb.memory_model, spv::OpMemoryModel, {(uint32_t)spv::AddressingModelPhysicalStorageBuffer64, (uint32_t)spv::MemoryModelGLSL450});

    compute_structure();
    if (failed) return false;

    Id fn = sb.alloc();
    Id entry_label = label(&f.getEntryBlock());
    for (BasicBlock* bb : order) {
        emit_block(bb);
        if (failed) return false;
    }

    // function: OpFunction, entry label, variables, body
    Id void_t = sb.t_void();
    Id fn_t = sb.t_func(void_t);
    Words& F = sb.functions;
    SpvBuilder::inst(F, spv::OpFunction, {void_t, fn, 0, fn_t});
    SpvBuilder::inst(F, spv::OpLabel, {entry_label});
    F.insert(F.end(), fvars.begin(), fvars.end());
    F.insert(F.end(), body.begin(), body.end());
    SpvBuilder::inst(F, spv::OpFunctionEnd, {});

    spv::ExecutionModel model = vertex ? spv::ExecutionModelVertex : fragment ? spv::ExecutionModelFragment : spv::ExecutionModelGLCompute;
    Words ep{(uint32_t)model, fn};
    SpvBuilder::append_string(ep, "main");
    for (Id v : interface_ids) ep.push_back(v);
    SpvBuilder::inst(sb.entry_points, spv::OpEntryPoint, ep);
    if (fragment) {
        SpvBuilder::inst(sb.exec_modes, spv::OpExecutionMode, {fn, (uint32_t)spv::ExecutionModeOriginUpperLeft});
        if (writes_depth) {
            SpvBuilder::inst(sb.exec_modes, spv::OpExecutionMode, {fn, (uint32_t)spv::ExecutionModeDepthReplacing});
            if (ps.depth_mode == "air.depth_greater" || ps.depth_mode == "greater")
                SpvBuilder::inst(sb.exec_modes, spv::OpExecutionMode, {fn, (uint32_t)spv::ExecutionModeDepthGreater});
            else if (ps.depth_mode == "air.depth_less" || ps.depth_mode == "less")
                SpvBuilder::inst(sb.exec_modes, spv::OpExecutionMode, {fn, (uint32_t)spv::ExecutionModeDepthLess});
        }
        if (writes_stencil) SpvBuilder::inst(sb.exec_modes, spv::OpExecutionMode, {fn, (uint32_t)spv::ExecutionModeStencilRefReplacingEXT});
        if (ps.early_fragment_tests) SpvBuilder::inst(sb.exec_modes, spv::OpExecutionMode, {fn, (uint32_t)spv::ExecutionModeEarlyFragmentTests});
    }
    if (kernel)
        SpvBuilder::inst(sb.exec_modes, spv::OpExecutionMode, {fn, (uint32_t)spv::ExecutionModeLocalSize, ps.tg_size[0], ps.tg_size[1], ps.tg_size[2]});
    sb.name(fn, "main");
    out = sb.finish();
    return !failed;
}

bool emit_spirv(PreparedStage& ps, std::vector<uint32_t>& out, std::string& err) {
    Emitter e(ps, err);
    return e.run(out);
}

} // namespace mtlc
