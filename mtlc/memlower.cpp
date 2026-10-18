// Memory lowering: every pointer value becomes an i64.
//   device/constant memory (AS 1/2): the i64 is a buffer device address; loads/stores stay typed and go through
//                                    `inttoptr i64 to ptr addrspace(1)` (the emitter turns these into
//                                    PhysicalStorageBuffer accesses). Aggregates are split into scalars/vectors.
//   thread memory (allocas, AS 0):   offsets into one function-local [N x i32] word arena, tagged kTagPriv.
//   threadgroup memory (AS 3):       offsets into one workgroup [N x i32] word arena, tagged kTagTg.
// Pointers whose provenance is not statically known are dispatched at run time on the tag.
#include "mtlc.h"
#include "llvm/ADT/PostOrderIterator.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/ReplaceConstant.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"
#include <cstring>
#include <set>

namespace mtlc {
using namespace llvm;
using namespace xef::mtlabi;

namespace {

enum : uint8_t { P_GLOBAL = 1, P_PRIV = 2, P_TG = 4 };

struct GInfo {
    enum Kind { CONSTDATA, PRIV, TG, SAMPLER, DEVICE } kind = CONSTDATA;
    uint32_t offset = 0;
    uint16_t sampler = 0;
};

// decoded constexpr sampler (see ConstSampler in mtl_shader_abi.h)
static unsigned vlen_of(Type* t) { auto* v = dyn_cast<FixedVectorType>(t); return v ? v->getNumElements() : 1; }

static ConstSampler decode_sampler(uint64_t lo, uint64_t hi) {
    ConstSampler s{};
    // AIR address modes: 0 clamp_to_zero, 1 clamp_to_edge, 2 repeat, 3 mirrored_repeat, 4 clamp_to_border
    auto addr = [](uint32_t v) -> uint8_t {
        switch (v & 7) {
        case 0: return 4;   // MTLSamplerAddressModeClampToZero
        case 1: return 0;   // ClampToEdge
        case 2: return 2;   // Repeat
        case 3: return 3;   // MirrorRepeat
        case 4: return 5;   // ClampToBorderColor
        default: return 0;
        }
    };
    s.s_address = addr((uint32_t)lo);
    s.t_address = addr((uint32_t)(lo >> 3));
    s.r_address = addr((uint32_t)(lo >> 6));
    s.mag_filter = (uint8_t)((lo >> 9) & 3);    // 0 nearest 1 linear
    s.min_filter = (uint8_t)((lo >> 11) & 3);
    s.mip_filter = (uint8_t)((lo >> 13) & 3);   // 0 none 1 nearest 2 linear
    s.normalized = ((lo >> 15) & 1) ? 0 : 1;   // coord::pixel sets the bit
    s.compare = (uint8_t)((lo >> 16) & 15);
    s.max_aniso = (uint8_t)(((lo >> 20) & 15) + 1);
    s.border = (uint8_t)((lo >> 24) & 3);
    uint16_t lmin = (uint16_t)(lo >> 32), lmax = (uint16_t)(lo >> 48);
    auto h2f = [](uint16_t h) {
        uint32_t sign = (h >> 15) & 1, e = (h >> 10) & 31, m = h & 1023, f;
        if (e == 0) f = sign << 31;
        else if (e == 31) f = (sign << 31) | 0x7f800000 | (m << 13);
        else f = (sign << 31) | ((e + 112) << 23) | (m << 13);
        float r; memcpy(&r, &f, 4); return r;
    };
    s.lod_min = h2f(lmin);
    s.lod_max = h2f(lmax);
    if (s.lod_max <= 0.0f && lmax == 0) s.lod_max = 1000.0f;
    (void)hi;
    return s;
}

class MemLower {
public:
    PreparedStage& ps;
    Module& m;
    Function& f;
    const DataLayout& dl;
    LLVMContext& ctx;
    std::string& err;
    Type* i64; Type* i32; Type* i8;

    DenseMap<Value*, Value*> map;
    DenseMap<Value*, uint8_t> prov;
    DenseMap<GlobalVariable*, GInfo> ginfo;
    std::vector<Instruction*> dead;
    std::vector<std::pair<PHINode*, PHINode*>> phis;
    std::vector<CallInst*> deferred;   // xef.mixed.* / xef.memcpy calls expanded after the rewrite
    Value* const_base = nullptr;
    Value* table = nullptr;
    Instruction* entry_pt = nullptr;   // insertion point for entry-block values
    uint32_t priv_size = 0;
    uint32_t tg_size = 0;
    std::vector<uint8_t> const_blob;
    bool failed = false;

    MemLower(PreparedStage& p, std::string& e)
        : ps(p), m(*p.mod), f(*p.main), dl(p.mod->getDataLayout()), ctx(p.mod->getContext()), err(e) {
        i64 = Type::getInt64Ty(ctx); i32 = Type::getInt32Ty(ctx); i8 = Type::getInt8Ty(ctx);
    }

    void fail(const std::string& msg) { if (!failed) { err = msg; failed = true; } }

    static bool is_ptr(Value* v) { return v->getType()->isPointerTy(); }

    // ---------------- setup ----------------
    void classify_globals() {
        std::set<GlobalVariable*> samplers;
        if (NamedMDNode* nm = m.getNamedMetadata("air.sampler_states"))
            for (MDNode* n : nm->operands())
                for (unsigned i = 0; i < n->getNumOperands(); i++)
                    if (auto* vm = dyn_cast_or_null<ValueAsMetadata>(n->getOperand(i)))
                        if (auto* g = dyn_cast<GlobalVariable>(vm->getValue())) samplers.insert(g);
        for (GlobalVariable& g : m.globals()) {
            if (g.getName().starts_with("llvm.") || g.use_empty()) continue;
            GInfo gi;
            unsigned as = g.getAddressSpace();
            bool written = false;
            for (User* u : g.users()) {
                if (auto* st = dyn_cast<StoreInst>(u)) { if (st->getPointerOperand() == &g) written = true; }
                else if (!isa<LoadInst>(u) && !isa<CallInst>(u)) written = true;   // conservatively (GEPs etc.)
            }
            if (samplers.count(&g) || g.getName().starts_with("__air_sampler_state")) {
                gi.kind = GInfo::SAMPLER;
                gi.sampler = (uint16_t)ps.res->const_samplers.size();
                uint64_t lo = 0, hi = 0;
                if (g.hasInitializer()) {
                    Constant* c = g.getInitializer();
                    if (auto* ci = dyn_cast<ConstantInt>(c)) lo = ci->getZExtValue();
                    else if (auto* ca = dyn_cast<ConstantDataArray>(c)) { lo = ca->getElementAsInteger(0); if (ca->getNumElements() > 1) hi = ca->getElementAsInteger(1); }
                }
                ps.res->const_samplers.push_back(decode_sampler(lo, hi));
            } else if (as == 3) {
                gi.kind = GInfo::TG;
                uint64_t sz = dl.getTypeAllocSize(g.getValueType());
                uint32_t a = std::max<uint32_t>(4, (uint32_t)g.getAlign().valueOrOne().value());
                tg_size = (tg_size + a - 1) & ~(a - 1);
                gi.offset = tg_size;
                tg_size += (uint32_t)((sz + 3) & ~3ull);
            } else if (as == 2 && g.hasInitializer() && !written && !g.isExternallyInitialized()) {
                gi.kind = GInfo::CONSTDATA;
                uint64_t sz = dl.getTypeAllocSize(g.getValueType());
                uint32_t a = std::max<uint32_t>(16, (uint32_t)g.getAlign().valueOrOne().value());
                size_t off = (const_blob.size() + a - 1) & ~(size_t)(a - 1);
                const_blob.resize(off + sz, 0);
                write_constant(g.getInitializer(), const_blob.data() + off);
                gi.offset = (uint32_t)off;
            } else if (as == 1) {
                gi.kind = GInfo::DEVICE;
            } else {
                gi.kind = GInfo::PRIV;
                uint64_t sz = dl.getTypeAllocSize(g.getValueType());
                uint32_t a = std::max<uint32_t>(4, (uint32_t)g.getAlign().valueOrOne().value());
                priv_size = (priv_size + a - 1) & ~(a - 1);
                gi.offset = priv_size;
                priv_size += (uint32_t)((sz + 3) & ~3ull);
            }
            ginfo[&g] = gi;
        }
    }

    void write_constant(Constant* c, uint8_t* dst) {
        Type* t = c->getType();
        if (isa<UndefValue>(c) || isa<ConstantAggregateZero>(c) || isa<ConstantPointerNull>(c)) return;
        if (auto* ci = dyn_cast<ConstantInt>(c)) {
            uint64_t v = ci->getZExtValue();
            memcpy(dst, &v, std::min<uint64_t>(dl.getTypeStoreSize(t), 8));
            return;
        }
        if (auto* cf = dyn_cast<ConstantFP>(c)) {
            APInt bits = cf->getValueAPF().bitcastToAPInt();
            uint64_t v = bits.getZExtValue();
            memcpy(dst, &v, std::min<uint64_t>(dl.getTypeStoreSize(t), 8));
            return;
        }
        if (auto* cds = dyn_cast<ConstantDataSequential>(c)) {
            uint64_t es = dl.getTypeAllocSize(cds->getElementType());
            for (unsigned i = 0; i < cds->getNumElements(); i++) write_constant(cds->getElementAsConstant(i), dst + i * es);
            return;
        }
        if (auto* st = dyn_cast<StructType>(t)) {
            const StructLayout* sl = dl.getStructLayout(st);
            for (unsigned i = 0; i < c->getNumOperands(); i++) write_constant(cast<Constant>(c->getOperand(i)), dst + sl->getElementOffset(i));
            return;
        }
        if (auto* at = dyn_cast<ArrayType>(t)) {
            uint64_t es = dl.getTypeAllocSize(at->getElementType());
            for (unsigned i = 0; i < c->getNumOperands(); i++) write_constant(cast<Constant>(c->getOperand(i)), dst + i * es);
            return;
        }
        if (auto* vt = dyn_cast<FixedVectorType>(t)) {
            uint64_t es = dl.getTypeAllocSize(vt->getElementType());
            for (unsigned i = 0; i < c->getNumOperands(); i++) write_constant(cast<Constant>(c->getOperand(i)), dst + i * es);
            return;
        }
        fail("unsupported constant initializer");
    }

    uint8_t prov_of_as(unsigned as) { return as == 0 ? P_PRIV : as == 3 ? P_TG : P_GLOBAL; }

    uint8_t get_prov(Value* v) {
        auto it = prov.find(v);
        if (it != prov.end()) return it->second;
        if (auto* g = dyn_cast<GlobalVariable>(v)) {
            auto gi = ginfo.find(g);
            if (gi == ginfo.end()) return P_GLOBAL;
            switch (gi->second.kind) {
            case GInfo::PRIV: return P_PRIV;
            case GInfo::TG: return P_TG;
            default: return P_GLOBAL;
            }
        }
        if (isa<ConstantPointerNull>(v) || isa<UndefValue>(v)) return 0;
        if (v->getType()->isPointerTy()) return prov_of_as(v->getType()->getPointerAddressSpace());
        return P_GLOBAL;
    }

    void compute_provenance() {
        bool changed = true;
        int iter = 0;
        while (changed && iter++ < 64) {
            changed = false;
            for (BasicBlock& bb : f)
                for (Instruction& i : bb) {
                    if (!is_ptr(&i)) continue;
                    uint8_t p = 0;
                    if (isa<AllocaInst>(i)) p = P_PRIV;
                    else if (auto* g = dyn_cast<GetElementPtrInst>(&i)) p = get_prov(g->getPointerOperand());
                    else if (auto* li = dyn_cast<LoadInst>(&i)) {
                        unsigned as = i.getType()->getPointerAddressSpace();
                        if (as != 0) p = prov_of_as(as);
                        // generic pointers (MSL frontend): loaded from device memory -> device, otherwise unknown
                        else p = get_prov(li->getPointerOperand()) == P_GLOBAL ? P_GLOBAL : (P_GLOBAL | P_PRIV | P_TG);
                    } else if (isa<CallInst>(i)) p = i.getType()->getPointerAddressSpace() == 0 ? P_GLOBAL : prov_of_as(i.getType()->getPointerAddressSpace());
                    else if (auto* c = dyn_cast<CastInst>(&i)) {
                        if (isa<IntToPtrInst>(c)) p = i.getType()->getPointerAddressSpace() == 0 ? P_GLOBAL : prov_of_as(i.getType()->getPointerAddressSpace());
                        else p = get_prov(c->getOperand(0));
                    } else if (auto* phi = dyn_cast<PHINode>(&i)) {
                        for (Value* in : phi->incoming_values()) p |= get_prov(in);
                    } else if (auto* s = dyn_cast<SelectInst>(&i)) {
                        p = get_prov(s->getTrueValue()) | get_prov(s->getFalseValue());
                    } else if (auto* fr = dyn_cast<FreezeInst>(&i)) {
                        p = get_prov(fr->getOperand(0));
                    } else p = prov_of_as(i.getType()->getPointerAddressSpace());
                    if (!p) p = prov_of_as(i.getType()->getPointerAddressSpace());
                    auto it = prov.find(&i);
                    if (it == prov.end() || it->second != p) { prov[&i] = p; changed = true; }
                }
        }
    }

    // ---------------- value mapping ----------------
    Value* table_value() {
        if (!table) {
            IRBuilder<> b(entry_pt);
            table = b.CreateCall(get_placeholder(m, "xef.pc.table", i64, {}), {});
        }
        return table;
    }
    Value* load_table_entry(uint8_t kind, uint16_t index) {
        StageResult& r = *ps.res;
        uint32_t off = ~0u;
        for (auto& t : r.table) if (t.kind == kind && t.index == index) off = t.offset;
        if (off == ~0u) {
            off = (uint32_t)r.table.size() * 8;
            r.table.push_back(TableEntry{kind, 0, index, off});
            r.table_size = off + 8;
        }
        Value* t = table_value();
        IRBuilder<> b(entry_pt);
        Value* p = b.CreateIntToPtr(b.CreateAdd(t, b.getInt64(off)), PointerType::get(ctx, 1));
        return b.CreateAlignedLoad(i64, p, Align(8));
    }

    Value* get(Value* v) {
        auto it = map.find(v);
        if (it != map.end()) return it->second;
        if (isa<ConstantPointerNull>(v)) return ConstantInt::get(i64, 0);
        if (isa<PoisonValue>(v)) return PoisonValue::get(i64);
        if (isa<UndefValue>(v)) return ConstantInt::get(i64, 0);
        if (auto* g = dyn_cast<GlobalVariable>(v)) {
            auto gi = ginfo.find(g);
            Value* r = nullptr;
            if (gi == ginfo.end()) { fail("unknown global " + g->getName().str()); return ConstantInt::get(i64, 0); }
            switch (gi->second.kind) {
            case GInfo::PRIV: r = ConstantInt::get(i64, kTagPriv | gi->second.offset); break;
            case GInfo::TG: r = ConstantInt::get(i64, kTagTg | gi->second.offset); break;
            case GInfo::SAMPLER: r = load_table_entry(BIND_CONST_SAMPLER, gi->second.sampler); break;
            case GInfo::CONSTDATA: {
                if (!const_base) const_base = load_table_entry(BIND_CONST_DATA, 0);
                IRBuilder<> b(entry_pt);
                r = gi->second.offset ? b.CreateAdd(const_base, b.getInt64(gi->second.offset)) : const_base;
                break;
            }
            case GInfo::DEVICE: fail("device address space global " + g->getName().str()); r = ConstantInt::get(i64, 0); break;
            }
            map[v] = r;
            return r;
        }
        if (auto* ce = dyn_cast<ConstantExpr>(v)) {
            // remaining constant expressions (inttoptr of a constant etc.)
            if (ce->getOpcode() == Instruction::IntToPtr) {
                if (auto* ci = dyn_cast<ConstantInt>(ce->getOperand(0))) return ConstantInt::get(i64, ci->getZExtValue());
            }
            // address space casts keep the (tagged) address; constant GEPs add their offset
            if (ce->getOpcode() == Instruction::AddrSpaceCast || ce->getOpcode() == Instruction::BitCast)
                return map[v] = get(ce->getOperand(0));
            if (auto* gep = dyn_cast<GEPOperator>(ce)) {
                APInt off(64, 0);
                if (gep->accumulateConstantOffset(m.getDataLayout(), off)) {
                    Value* base = get(gep->getPointerOperand());
                    if (off.isZero()) return map[v] = base;
                    if (auto* cb = dyn_cast<ConstantInt>(base)) return map[v] = ConstantInt::get(i64, cb->getZExtValue() + off.getZExtValue());
                    IRBuilder<> b(entry_pt);
                    return map[v] = b.CreateAdd(base, b.getInt64(off.getZExtValue()));
                }
            }
            fail("unsupported pointer constant expression");
            return ConstantInt::get(i64, 0);
        }
        if (isa<Argument>(v)) { fail("pointer argument in xef.main"); return ConstantInt::get(i64, 0); }
        std::string vs; raw_string_ostream os(vs); v->print(os);
        fail("pointer value used before definition: " + vs);
        return ConstantInt::get(i64, 0);
    }

    // ---------------- device memory ----------------
    Value* load_global(IRBuilder<>& b, Type* t, Value* addr, Align al) {
        if (t->isPointerTy()) t = i64;
        if (t->isIntegerTy(1)) return b.CreateICmpNE(load_global(b, i8, addr, al), b.getInt8(0));
        if (auto* vt = dyn_cast<FixedVectorType>(t)) {
            Type* et = vt->getElementType();
            unsigned n = vt->getNumElements();
            if (et->isIntegerTy(1)) {
                Value* v = load_global(b, FixedVectorType::get(i8, n), addr, al);
                return b.CreateICmpNE(v, Constant::getNullValue(v->getType()));
            }
            if (et->isPointerTy()) {
                Value* v = load_global(b, FixedVectorType::get(i64, n), addr, al);
                return v;
            }
            if (n > 4) {
                uint64_t es = dl.getTypeAllocSize(et);
                Value* r = PoisonValue::get(t);
                for (unsigned i = 0; i < n; i += 4) {
                    unsigned c = std::min(4u, n - i);
                    Type* ct = c == 1 ? et : (Type*)FixedVectorType::get(et, c);
                    Value* part = load_global(b, ct, b.CreateAdd(addr, b.getInt64(i * es)), commonAlignment(al, i * es));
                    for (unsigned j = 0; j < c; j++)
                        r = b.CreateInsertElement(r, c == 1 ? part : b.CreateExtractElement(part, (uint64_t)j), (uint64_t)(i + j));
                }
                return r;
            }
        }
        if (auto* st = dyn_cast<StructType>(t)) {
            const StructLayout* sl = dl.getStructLayout(st);
            Value* r = PoisonValue::get(t);
            for (unsigned i = 0; i < st->getNumElements(); i++) {
                uint64_t off = sl->getElementOffset(i);
                Value* e = load_global(b, st->getElementType(i), off ? b.CreateAdd(addr, b.getInt64(off)) : addr, commonAlignment(al, off));
                r = b.CreateInsertValue(r, e, {i});
            }
            return r;
        }
        if (auto* at = dyn_cast<ArrayType>(t)) {
            uint64_t es = dl.getTypeAllocSize(at->getElementType());
            Value* r = PoisonValue::get(t);
            for (unsigned i = 0; i < at->getNumElements(); i++) {
                Value* e = load_global(b, at->getElementType(), i ? b.CreateAdd(addr, b.getInt64(i * es)) : addr, commonAlignment(al, i * es));
                r = b.CreateInsertValue(r, e, {i});
            }
            return r;
        }
        Type* st = t->getScalarType();
        if (!(st->isIntegerTy(8) || st->isIntegerTy(16) || st->isIntegerTy(32) || st->isIntegerTy(64) || st->isHalfTy() ||
              st->isFloatTy() || st->isDoubleTy())) {
            fail("unsupported device load type " + type_tag(t));
            return PoisonValue::get(t);
        }
        Value* p = b.CreateIntToPtr(addr, PointerType::get(ctx, 1));
        return b.CreateAlignedLoad(t, p, al);
    }

    void store_global(IRBuilder<>& b, Value* v, Value* addr, Align al) {
        Type* t = v->getType();
        if (t->isIntegerTy(1)) { store_global(b, b.CreateZExt(v, i8), addr, al); return; }
        if (auto* vt = dyn_cast<FixedVectorType>(t)) {
            Type* et = vt->getElementType();
            unsigned n = vt->getNumElements();
            if (et->isIntegerTy(1)) { store_global(b, b.CreateZExt(v, FixedVectorType::get(i8, n)), addr, al); return; }
            if (n > 4) {
                uint64_t es = dl.getTypeAllocSize(et);
                for (unsigned i = 0; i < n; i += 4) {
                    unsigned c = std::min(4u, n - i);
                    Value* part;
                    if (c == 1) part = b.CreateExtractElement(v, (uint64_t)i);
                    else {
                        SmallVector<int, 4> mask;
                        for (unsigned j = 0; j < c; j++) mask.push_back((int)(i + j));
                        part = b.CreateShuffleVector(v, mask);
                    }
                    store_global(b, part, b.CreateAdd(addr, b.getInt64(i * es)), commonAlignment(al, i * es));
                }
                return;
            }
        }
        if (auto* st = dyn_cast<StructType>(t)) {
            const StructLayout* sl = dl.getStructLayout(st);
            for (unsigned i = 0; i < st->getNumElements(); i++) {
                uint64_t off = sl->getElementOffset(i);
                store_global(b, b.CreateExtractValue(v, {i}), off ? b.CreateAdd(addr, b.getInt64(off)) : addr, commonAlignment(al, off));
            }
            return;
        }
        if (auto* at = dyn_cast<ArrayType>(t)) {
            uint64_t es = dl.getTypeAllocSize(at->getElementType());
            for (unsigned i = 0; i < at->getNumElements(); i++)
                store_global(b, b.CreateExtractValue(v, {i}), i ? b.CreateAdd(addr, b.getInt64(i * es)) : addr, commonAlignment(al, i * es));
            return;
        }
        Value* p = b.CreateIntToPtr(addr, PointerType::get(ctx, 1));
        b.CreateAlignedStore(v, p, al);
    }

    // ---------------- word arenas ----------------
    Value* arena_ptr(IRBuilder<>& b, bool tg, Value* word_index) {
        if (tg) {
            if (!ps.tg_arena) { fail("threadgroup access without threadgroup memory"); return PoisonValue::get(PointerType::get(ctx, 3)); }
            return b.CreateInBoundsGEP(ps.tg_arena->getValueType(), ps.tg_arena, {b.getInt32(0), word_index});
        }
        if (!ps.priv_arena) { fail("thread-memory access without thread memory"); return PoisonValue::get(PointerType::get(ctx, 0)); }
        return b.CreateInBoundsGEP(ps.priv_arena->getAllocatedType(), ps.priv_arena, {b.getInt32(0), word_index});
    }
    Value* load_word(IRBuilder<>& b, bool tg, Value* byte_off) {
        Value* wi = b.CreateLShr(byte_off, 2);
        return b.CreateAlignedLoad(i32, arena_ptr(b, tg, wi), Align(4));
    }
    void store_word(IRBuilder<>& b, bool tg, Value* byte_off, Value* w) {
        Value* wi = b.CreateLShr(byte_off, 2);
        b.CreateAlignedStore(w, arena_ptr(b, tg, wi), Align(4));
    }

    struct Leaf { Type* t; uint64_t off; };
    void leaves(Type* t, uint64_t off, std::vector<Leaf>& out) {
        if (auto* st = dyn_cast<StructType>(t)) {
            const StructLayout* sl = dl.getStructLayout(st);
            for (unsigned i = 0; i < st->getNumElements(); i++) leaves(st->getElementType(i), off + sl->getElementOffset(i), out);
        } else if (auto* at = dyn_cast<ArrayType>(t)) {
            uint64_t es = dl.getTypeAllocSize(at->getElementType());
            for (unsigned i = 0; i < at->getNumElements(); i++) leaves(at->getElementType(), off + i * es, out);
        } else if (auto* vt = dyn_cast<FixedVectorType>(t)) {
            uint64_t es = dl.getTypeAllocSize(vt->getElementType());
            for (unsigned i = 0; i < vt->getNumElements(); i++) leaves(vt->getElementType(), off + i * es, out);
        } else out.push_back({t->isPointerTy() ? i64 : t, off});
    }
    Value* assemble(IRBuilder<>& b, Type* t, std::vector<Value*>& vals, size_t& k) {
        if (auto* st = dyn_cast<StructType>(t)) {
            Value* r = PoisonValue::get(t);
            for (unsigned i = 0; i < st->getNumElements(); i++) r = b.CreateInsertValue(r, assemble(b, st->getElementType(i), vals, k), {i});
            return r;
        }
        if (auto* at = dyn_cast<ArrayType>(t)) {
            Value* r = PoisonValue::get(t);
            for (unsigned i = 0; i < at->getNumElements(); i++) r = b.CreateInsertValue(r, assemble(b, at->getElementType(), vals, k), {i});
            return r;
        }
        if (auto* vt = dyn_cast<FixedVectorType>(t)) {
            Type* rt = vt->getElementType()->isPointerTy() ? (Type*)FixedVectorType::get(i64, vt->getNumElements()) : t;
            Value* r = PoisonValue::get(rt);
            for (unsigned i = 0; i < vt->getNumElements(); i++) r = b.CreateInsertElement(r, vals[k++], (uint64_t)i);
            return r;
        }
        return vals[k++];
    }
    void flatten(IRBuilder<>& b, Value* v, std::vector<Value*>& out) {
        Type* t = v->getType();
        if (auto* st = dyn_cast<StructType>(t)) { for (unsigned i = 0; i < st->getNumElements(); i++) flatten(b, b.CreateExtractValue(v, {i}), out); }
        else if (auto* at = dyn_cast<ArrayType>(t)) { for (unsigned i = 0; i < at->getNumElements(); i++) flatten(b, b.CreateExtractValue(v, {i}), out); }
        else if (auto* vt = dyn_cast<FixedVectorType>(t)) { for (unsigned i = 0; i < vt->getNumElements(); i++) out.push_back(b.CreateExtractElement(v, (uint64_t)i)); }
        else out.push_back(v);
    }

    Value* load_arena(IRBuilder<>& b, bool tg, Type* t, Value* addr, Align al) {
        Value* base = b.CreateTrunc(addr, i32);
        std::vector<Leaf> ls;
        leaves(t, 0, ls);
        std::vector<Value*> vals;
        bool aligned4 = al.value() >= 4;
        for (Leaf& l : ls) {
            uint64_t size = dl.getTypeStoreSize(l.t);
            Value* off = l.off ? b.CreateAdd(base, b.getInt32((uint32_t)l.off)) : base;
            Value* v;
            if (size == 4) {
                v = load_word(b, tg, off);
                if (!l.t->isIntegerTy(32)) v = b.CreateBitCast(v, l.t);
            } else if (size == 8) {
                Value* lo = b.CreateZExt(load_word(b, tg, off), i64);
                Value* hi = b.CreateZExt(load_word(b, tg, b.CreateAdd(off, b.getInt32(4))), i64);
                v = b.CreateOr(lo, b.CreateShl(hi, 32));
                if (!l.t->isIntegerTy(64)) v = b.CreateBitCast(v, l.t);
            } else if (size == 2 || size == 1) {
                Value* w = load_word(b, tg, off);
                Value* sh = aligned4 ? (Value*)b.getInt32((uint32_t)(l.off & 3) * 8) : b.CreateShl(b.CreateAnd(off, 3), 3);
                Type* it = IntegerType::get(ctx, (unsigned)size * 8);
                v = b.CreateTrunc(b.CreateLShr(w, sh), it);
                if (l.t->isIntegerTy(1)) v = b.CreateICmpNE(v, ConstantInt::get(it, 0));
                else if (l.t != it) v = b.CreateBitCast(v, l.t);
            } else {
                fail("unsupported arena load size");
                v = PoisonValue::get(l.t);
            }
            vals.push_back(v);
        }
        size_t k = 0;
        return assemble(b, t->isPointerTy() ? i64 : t, vals, k);
    }

    void store_arena(IRBuilder<>& b, bool tg, Value* v, Value* addr, Align al) {
        Value* base = b.CreateTrunc(addr, i32);
        std::vector<Leaf> ls;
        leaves(v->getType(), 0, ls);
        std::vector<Value*> vals;
        flatten(b, v, vals);
        bool aligned4 = al.value() >= 4;
        for (size_t i = 0; i < ls.size(); i++) {
            Leaf& l = ls[i];
            Value* x = vals[i];
            if (x->getType()->isPointerTy()) x = get(x);
            uint64_t size = dl.getTypeStoreSize(l.t);
            Value* off = l.off ? b.CreateAdd(base, b.getInt32((uint32_t)l.off)) : base;
            if (size == 4) {
                if (!x->getType()->isIntegerTy(32)) x = b.CreateBitCast(x, i32);
                store_word(b, tg, off, x);
            } else if (size == 8) {
                if (!x->getType()->isIntegerTy(64)) x = b.CreateBitCast(x, i64);
                store_word(b, tg, off, b.CreateTrunc(x, i32));
                store_word(b, tg, b.CreateAdd(off, b.getInt32(4)), b.CreateTrunc(b.CreateLShr(x, 32), i32));
            } else if (size == 2 || size == 1) {
                Type* it = IntegerType::get(ctx, (unsigned)size * 8);
                if (x->getType()->isIntegerTy(1)) x = b.CreateZExt(x, it);
                else if (x->getType() != it) x = b.CreateBitCast(x, it);
                Value* sh = aligned4 ? (Value*)b.getInt32((uint32_t)(l.off & 3) * 8) : b.CreateShl(b.CreateAnd(off, 3), 3);
                Value* bits = b.CreateShl(b.CreateZExt(x, i32), sh);
                Value* mask = b.CreateShl(b.getInt32(size == 2 ? 0xffff : 0xff), sh);
                if (tg) {
                    Value* p = arena_ptr(b, true, b.CreateLShr(off, 2));
                    b.CreateAtomicRMW(AtomicRMWInst::And, p, b.CreateNot(mask), Align(4), AtomicOrdering::Monotonic, ctx.getOrInsertSyncScopeID("workgroup"));
                    b.CreateAtomicRMW(AtomicRMWInst::Or, p, bits, Align(4), AtomicOrdering::Monotonic, ctx.getOrInsertSyncScopeID("workgroup"));
                } else {
                    Value* w = load_word(b, false, off);
                    store_word(b, false, off, b.CreateOr(b.CreateAnd(w, b.CreateNot(mask)), bits));
                }
            } else fail("unsupported arena store size");
        }
    }

    // ---------------- dispatch ----------------
    Value* load_mem(IRBuilder<>& b, Type* t, Value* addr, uint8_t p, Align al) {
        if (p == P_GLOBAL || p == 0) return load_global(b, t, addr, al);
        if (p == P_PRIV) return load_arena(b, false, t, addr, al);
        if (p == P_TG) return load_arena(b, true, t, addr, al);
        // mixed: defer (needs control flow)
        Type* rt = t->isPointerTy() ? i64 : t;
        Function* fn = get_placeholder(m, "xef.mixed.load", rt, {i64, i32, i32});
        CallInst* ci = b.CreateCall(fn, {addr, b.getInt32(p), b.getInt32((uint32_t)al.value())});
        deferred.push_back(ci);
        return ci;
    }
    void store_mem(IRBuilder<>& b, Value* v, Value* addr, uint8_t p, Align al) {
        if (p == P_GLOBAL || p == 0) return store_global(b, v, addr, al);
        if (p == P_PRIV) return store_arena(b, false, v, addr, al);
        if (p == P_TG) return store_arena(b, true, v, addr, al);
        Function* fn = get_placeholder(m, "xef.mixed.store", Type::getVoidTy(ctx), {v->getType(), i64, i32, i32});
        CallInst* ci = b.CreateCall(fn, {v, addr, b.getInt32(p), b.getInt32((uint32_t)al.value())});
        deferred.push_back(ci);
    }

    // ---------------- atomics ----------------
    Value* atomic_ptr(IRBuilder<>& b, Value* addr, uint8_t p, Type* t) {
        if (p == P_TG) {
            if (!t->isIntegerTy(32) && !t->isFloatTy()) fail("non-32-bit threadgroup atomic");
            return arena_ptr(b, true, b.CreateLShr(b.CreateTrunc(addr, i32), 2));
        }
        return b.CreateIntToPtr(addr, PointerType::get(ctx, 1));
    }

    void lower_air_atomic(CallInst* ci, StringRef name) {
        // air.atomic.{global,local}.<op>[.s|.u|.f].<type>
        IRBuilder<> b(ci);
        Value* ptr = ci->getArgOperand(0);
        Value* addr = get(ptr);
        uint8_t p = get_prov(ptr);
        bool local = name.contains(".local.");
        if (local) p = P_TG;
        else if (p != P_PRIV && p != P_TG) {
            if (p & P_TG) fail("atomic on a pointer of unknown memory kind: " + name.str());
            p = P_GLOBAL;
        }
        local = p == P_TG;
        SmallVector<StringRef, 6> parts;
        name.split(parts, '.');
        StringRef op = parts.size() > 3 ? parts[3] : "";
        SyncScope::ID scope = local ? ctx.getOrInsertSyncScopeID("workgroup") : ctx.getOrInsertSyncScopeID("device");
        Type* vt = ci->getType()->isVoidTy() ? ci->getArgOperand(1)->getType() : ci->getType();
        if (p == P_PRIV) {   // thread memory: no atomicity needed
            Value* old = load_arena(b, false, vt, addr, Align(4));
            Value* res = old;
            if (op == "store") { store_arena(b, false, ci->getArgOperand(1), addr, Align(4)); }
            else if (op != "load") fail("atomic on thread memory: " + name.str());
            if (!ci->getType()->isVoidTy()) ci->replaceAllUsesWith(res);
            dead.push_back(ci);
            return;
        }
        Value* ap = atomic_ptr(b, addr, p, vt);
        Value* res = nullptr;
        bool sgn = name.contains(".s.");
        AtomicRMWInst::BinOp bop = AtomicRMWInst::BAD_BINOP;
        if (op == "add") bop = vt->isFloatingPointTy() ? AtomicRMWInst::FAdd : AtomicRMWInst::Add;
        else if (op == "sub") bop = vt->isFloatingPointTy() ? AtomicRMWInst::FSub : AtomicRMWInst::Sub;
        else if (op == "and") bop = AtomicRMWInst::And;
        else if (op == "or") bop = AtomicRMWInst::Or;
        else if (op == "xor") bop = AtomicRMWInst::Xor;
        else if (op == "min") bop = vt->isFloatingPointTy() ? AtomicRMWInst::FMin : sgn ? AtomicRMWInst::Min : AtomicRMWInst::UMin;
        else if (op == "max") bop = vt->isFloatingPointTy() ? AtomicRMWInst::FMax : sgn ? AtomicRMWInst::Max : AtomicRMWInst::UMax;
        else if (op == "xchg") bop = AtomicRMWInst::Xchg;
        if (bop != AtomicRMWInst::BAD_BINOP) {
            res = b.CreateAtomicRMW(bop, ap, ci->getArgOperand(1), Align(dl.getTypeStoreSize(vt)), AtomicOrdering::Monotonic, scope);
        } else if (op == "load") {
            LoadInst* li = b.CreateAlignedLoad(vt, ap, Align(dl.getTypeStoreSize(vt)));
            li->setAtomic(AtomicOrdering::Monotonic, scope);
            res = li;
        } else if (op == "store") {
            StoreInst* si = b.CreateAlignedStore(ci->getArgOperand(1), ap, Align(dl.getTypeStoreSize(vt)));
            si->setAtomic(AtomicOrdering::Monotonic, scope);
        } else if (op == "cmpxchg") {
            // (ptr, ptr expected, desired, ...) -> i1, *expected updated with the old value
            Value* expp = ci->getArgOperand(1);
            Value* desired = ci->getArgOperand(2);
            Value* eaddr = get(expp);
            uint8_t ep = get_prov(expp);
            Value* expected = load_mem(b, desired->getType(), eaddr, ep, Align(4));
            AtomicCmpXchgInst* cx = b.CreateAtomicCmpXchg(ap, expected, desired, Align(dl.getTypeStoreSize(vt)),
                                                          AtomicOrdering::Monotonic, AtomicOrdering::Monotonic, scope);
            Value* old = b.CreateExtractValue(cx, {0});
            Value* ok = b.CreateExtractValue(cx, {1});
            store_mem(b, old, eaddr, ep, Align(4));
            res = ok;
            if (ci->getType()->isIntegerTy() && !ci->getType()->isIntegerTy(1)) res = b.CreateZExt(ok, ci->getType());
        } else {
            fail("unsupported atomic " + name.str());
        }
        if (res && !ci->getType()->isVoidTy()) ci->replaceAllUsesWith(res);
        dead.push_back(ci);
    }

    // ---------------- memcpy / memset ----------------
    void lower_memtransfer(CallInst* ci, bool is_set) {
        IRBuilder<> b(ci);
        Value* dst = ci->getArgOperand(0);
        Value* daddr = get(dst);
        uint8_t dp = get_prov(dst);
        Value* len = ci->getArgOperand(2);
        Align dal = cast<MemIntrinsic>(ci)->getDestAlign().valueOrOne();
        if (is_set) {
            Value* val = ci->getArgOperand(1);
            auto* clen = dyn_cast<ConstantInt>(len);
            if (clen && clen->getZExtValue() <= 1024) {
                uint64_t n = clen->getZExtValue();
                bool words = dal.value() >= 4 && n % 4 == 0;
                Value* w = val;
                if (words) {
                    Value* x = b.CreateZExt(val, i32);
                    w = b.CreateMul(x, b.getInt32(0x01010101));
                }
                for (uint64_t o = 0; o < n; o += words ? 4 : 1)
                    store_mem(b, w, o ? b.CreateAdd(daddr, b.getInt64(o)) : daddr, dp, commonAlignment(dal, o));
            } else {
                Function* fn = get_placeholder(m, "xef.memset", Type::getVoidTy(ctx), {i64, i8, i64, i32});
                deferred.push_back(b.CreateCall(fn, {daddr, val, b.CreateZExtOrTrunc(len, i64), b.getInt32(dp)}));
            }
            dead.push_back(ci);
            return;
        }
        Value* src = ci->getArgOperand(1);
        Value* saddr = get(src);
        uint8_t sp = get_prov(src);
        Align sal = cast<MemTransferInst>(ci)->getSourceAlign().valueOrOne();
        auto* clen = dyn_cast<ConstantInt>(len);
        if (clen && clen->getZExtValue() <= 1024) {
            uint64_t n = clen->getZExtValue();
            bool words = dal.value() >= 4 && sal.value() >= 4 && n % 4 == 0;
            Type* et = words ? i32 : i8;
            std::vector<Value*> tmp;
            for (uint64_t o = 0; o < n; o += words ? 4 : 1)
                tmp.push_back(load_mem(b, et, o ? b.CreateAdd(saddr, b.getInt64(o)) : saddr, sp, commonAlignment(sal, o)));
            size_t k = 0;
            for (uint64_t o = 0; o < n; o += words ? 4 : 1)
                store_mem(b, tmp[k++], o ? b.CreateAdd(daddr, b.getInt64(o)) : daddr, dp, commonAlignment(dal, o));
        } else {
            uint32_t al = (dal.value() >= 4 && sal.value() >= 4) ? 4 : 1;
            Function* fn = get_placeholder(m, "xef.memcpy", Type::getVoidTy(ctx), {i64, i64, i64, i32, i32, i32});
            deferred.push_back(b.CreateCall(fn, {daddr, saddr, b.CreateZExtOrTrunc(len, i64), b.getInt32(dp), b.getInt32(sp), b.getInt32(al)}));
        }
        dead.push_back(ci);
    }

    // ---------------- instruction rewrite ----------------
    void visit(Instruction* i) {
        IRBuilder<> b(i);
        if (auto* a = dyn_cast<AllocaInst>(i)) {
            uint64_t sz = dl.getTypeAllocSize(a->getAllocatedType());
            if (auto* n = dyn_cast<ConstantInt>(a->getArraySize())) sz *= n->getZExtValue();
            else fail("dynamic alloca");
            uint32_t al = std::max<uint32_t>(4, (uint32_t)a->getAlign().value());
            priv_size = (priv_size + al - 1) & ~(al - 1);
            map[i] = ConstantInt::get(i64, kTagPriv | priv_size);
            priv_size += (uint32_t)((sz + 3) & ~3ull);
            dead.push_back(i);
            return;
        }
        if (auto* g = dyn_cast<GetElementPtrInst>(i)) {
            if (!is_ptr(i)) { fail("vector GEP"); return; }
            Value* base = get(g->getPointerOperand());
            unsigned bw = 64;
            SmallMapVector<Value*, APInt, 4> var;
            APInt cst(bw, 0);
            if (!g->collectOffset(dl, bw, var, cst)) { fail("GEP offset"); return; }
            Value* r = base;
            if (!cst.isZero()) r = b.CreateAdd(r, b.getInt64(cst.getZExtValue()));
            for (auto& [v, scale] : var) {
                Value* x = b.CreateSExtOrTrunc(v, i64);
                if (scale != 1) x = b.CreateMul(x, b.getInt64(scale.getSExtValue()));
                r = b.CreateAdd(r, x);
            }
            map[i] = r;
            dead.push_back(i);
            return;
        }
        if (auto* phi = dyn_cast<PHINode>(i)) {
            if (!is_ptr(i)) return;
            PHINode* np = PHINode::Create(i64, phi->getNumIncomingValues(), phi->getName(), phi->getIterator());
            map[i] = np;
            phis.push_back({phi, np});
            dead.push_back(i);
            return;
        }
        if (auto* s = dyn_cast<SelectInst>(i)) {
            if (!is_ptr(i)) return;
            map[i] = b.CreateSelect(s->getCondition(), get(s->getTrueValue()), get(s->getFalseValue()));
            dead.push_back(i);
            return;
        }
        if (auto* fr = dyn_cast<FreezeInst>(i)) {
            if (!is_ptr(i)) return;
            map[i] = b.CreateFreeze(get(fr->getOperand(0)));
            dead.push_back(i);
            return;
        }
        if (isa<IntToPtrInst>(i)) {
            map[i] = b.CreateZExtOrTrunc(i->getOperand(0), i64);
            dead.push_back(i);
            return;
        }
        if (isa<PtrToIntInst>(i)) {
            i->replaceAllUsesWith(b.CreateZExtOrTrunc(get(i->getOperand(0)), i->getType()));
            dead.push_back(i);
            return;
        }
        if (isa<AddrSpaceCastInst>(i) || (isa<BitCastInst>(i) && is_ptr(i))) {
            map[i] = get(i->getOperand(0));
            dead.push_back(i);
            return;
        }
        if (auto* c = dyn_cast<ICmpInst>(i)) {
            if (!is_ptr(c->getOperand(0))) return;
            i->replaceAllUsesWith(b.CreateICmp(c->getPredicate(), get(c->getOperand(0)), get(c->getOperand(1))));
            dead.push_back(i);
            return;
        }
        if (auto* li = dyn_cast<LoadInst>(i)) {
            Value* addr = get(li->getPointerOperand());
            Value* v = load_mem(b, li->getType(), addr, get_prov(li->getPointerOperand()), li->getAlign());
            if (is_ptr(li)) map[i] = v; else i->replaceAllUsesWith(v);
            dead.push_back(i);
            return;
        }
        if (auto* si = dyn_cast<StoreInst>(i)) {
            Value* v = si->getValueOperand();
            if (is_ptr(v)) v = get(v);
            store_mem(b, v, get(si->getPointerOperand()), get_prov(si->getPointerOperand()), si->getAlign());
            dead.push_back(i);
            return;
        }
        if (auto* rmw = dyn_cast<AtomicRMWInst>(i)) {
            Value* addr = get(rmw->getPointerOperand());
            uint8_t p = get_prov(rmw->getPointerOperand());
            Value* ap = atomic_ptr(b, addr, p, rmw->getValOperand()->getType());
            Value* r = b.CreateAtomicRMW(rmw->getOperation(), ap, rmw->getValOperand(), rmw->getAlign(), rmw->getOrdering(), rmw->getSyncScopeID());
            i->replaceAllUsesWith(r);
            dead.push_back(i);
            return;
        }
        if (auto* cx = dyn_cast<AtomicCmpXchgInst>(i)) {
            Value* addr = get(cx->getPointerOperand());
            uint8_t p = get_prov(cx->getPointerOperand());
            Value* ap = atomic_ptr(b, addr, p, cx->getNewValOperand()->getType());
            Value* r = b.CreateAtomicCmpXchg(ap, cx->getCompareOperand(), cx->getNewValOperand(), cx->getAlign(),
                                             cx->getSuccessOrdering(), cx->getFailureOrdering(), cx->getSyncScopeID());
            i->replaceAllUsesWith(r);
            dead.push_back(i);
            return;
        }
        if (auto* ci = dyn_cast<CallInst>(i)) {
            Function* callee = ci->getCalledFunction();
            StringRef name = callee ? callee->getName() : "";
            if (auto* ii = dyn_cast<IntrinsicInst>(ci)) {
                switch (ii->getIntrinsicID()) {
                case Intrinsic::memcpy: case Intrinsic::memmove: case Intrinsic::memcpy_inline:
                    lower_memtransfer(ci, false); return;
                case Intrinsic::memset: case Intrinsic::memset_inline:
                    lower_memtransfer(ci, true); return;
                case Intrinsic::lifetime_start: case Intrinsic::lifetime_end: case Intrinsic::invariant_start:
                case Intrinsic::invariant_end: case Intrinsic::experimental_noalias_scope_decl: case Intrinsic::assume:
                case Intrinsic::dbg_value: case Intrinsic::dbg_declare: case Intrinsic::dbg_label:
                    dead.push_back(i); return;
                case Intrinsic::ptrmask: {
                    map[i] = b.CreateAnd(get(ci->getArgOperand(0)), b.CreateZExtOrTrunc(ci->getArgOperand(1), i64));
                    dead.push_back(i); return;
                }
                default: break;
                }
            }
            if (name.starts_with("air.atomic.")) { lower_air_atomic(ci, name); return; }
            if (name.starts_with("air.get_null_texture") || name.starts_with("air.get_null_sampler")) {
                map[i] = ConstantInt::get(i64, 0);   // resource id 0: no resource
                dead.push_back(i);
                return;
            }
            if (name.starts_with("air.atomic_compare_exchange_weak_explicit_texture")) {
                // (tex, coord, [slice], ?, ptr expected, desired, order, order, scope) -> i1, *expected = old:
                // becomes air.atomic_xefcmpxchg_explicit_<kind>(tex, coord, [slice], ?, expected, desired) -> old
                std::vector<Value*> args;
                Value* expp = nullptr;
                for (unsigned k = 0; k < ci->arg_size(); k++) {
                    Value* a = ci->getArgOperand(k);
                    if (k > 0 && is_ptr(a)) { expp = a; continue; }
                    args.push_back(k == 0 ? b.CreateIntToPtr(get(a), a->getType()) : a);
                }
                if (!expp) { fail("texture compare-exchange without expected value"); return; }
                Value* desired = nullptr;
                for (size_t k = 1; k < args.size(); k++) if (vlen_of(args[k]->getType()) == 4) desired = args[k];
                if (!desired) { fail("texture compare-exchange without desired value"); return; }
                Value* eaddr = get(expp);
                uint8_t ep = get_prov(expp);
                Value* expected = load_mem(b, desired->getType(), eaddr, ep, Align(4));
                // keep tex, coords, slice and the unused vector, then expected and desired
                std::vector<Value*> nargs;
                for (Value* a : args) { if (a == desired) break; nargs.push_back(a); }
                nargs.push_back(expected);
                nargs.push_back(desired);
                std::string nn = "air.atomic_xefcmpxchg_explicit_" + name.substr(strlen("air.atomic_compare_exchange_weak_explicit_")).str();
                std::vector<Type*> pts;
                for (Value* a : nargs) pts.push_back(a->getType());
                FunctionCallee fc = m.getOrInsertFunction(nn, FunctionType::get(desired->getType(), pts, false));
                Value* old = b.CreateCall(fc, nargs);
                store_mem(b, old, eaddr, ep, Align(4));
                Value* ok = b.CreateICmpEQ(b.CreateExtractElement(old, (uint64_t)0), b.CreateExtractElement(expected, (uint64_t)0));
                if (ci->getType()->isIntegerTy() && !ci->getType()->isIntegerTy(1)) ok = b.CreateZExt(ok, ci->getType());
                ci->replaceAllUsesWith(ok);
                dead.push_back(ci);
                return;
            }
            if (name == "xef.const_sampler") {
                uint64_t st = 0;
                if (auto* c = dyn_cast<ConstantInt>(ci->getArgOperand(0))) st = c->getZExtValue();
                else { fail("non-constant constexpr sampler"); return; }
                uint16_t idx = 0xffff;
                ConstSampler cs = decode_sampler(st, 0);
                auto& v = ps.res->const_samplers;
                for (size_t k = 0; k < v.size(); k++) if (!memcmp(&v[k], &cs, sizeof cs)) idx = (uint16_t)k;
                if (idx == 0xffff) { idx = (uint16_t)v.size(); v.push_back(cs); }
                map[i] = load_table_entry(BIND_CONST_SAMPLER, idx);
                dead.push_back(i);
                return;
            }
            if (name.starts_with("air.simdgroup_async_copy") || name.starts_with("air.get_null_simdgroup_event")) {
                lower_async_copy(ci, name);
                return;
            }
            // other calls: pass pointer arguments as inttoptr(i64) (texture/sampler handles etc.)
            for (unsigned k = 0; k < ci->arg_size(); k++) {
                Value* a = ci->getArgOperand(k);
                if (!is_ptr(a)) continue;
                Value* v = get(a);
                ci->setArgOperand(k, b.CreateIntToPtr(v, a->getType()));
            }
            if (is_ptr(ci)) {   // pointer-returning calls (events, function pointers): opaque i64
                map[i] = b.CreatePtrToInt(ci, i64);
                cast<Instruction>(map[i])->moveAfter(ci);
            }
            return;
        }
        if (isa<ExtractValueInst>(i) || isa<InsertValueInst>(i) || isa<ExtractElementInst>(i) || isa<InsertElementInst>(i)) {
            if (is_ptr(i)) fail("pointer inside aggregate");
            return;
        }
        if (is_ptr(i)) fail(std::string("unhandled pointer instruction ") + i->getOpcodeName());
    }

    // simdgroup_async_copy: synchronous copy + null event
    void lower_async_copy(CallInst* ci, StringRef name) {
        IRBuilder<> b(ci);
        if (name.starts_with("air.get_null_simdgroup_event")) {
            map[ci] = ConstantInt::get(i64, 0);
            dead.push_back(ci);
            return;
        }
        if (name.starts_with("air.simdgroup_async_copy_2d")) {
            // (i64 elemSize, i64 elemAlign, dst, i64 dstElemsPerRow, i64 dstElemStride?, <2 x i64> dstTileDims,
            //  src, i64 srcElemsPerRow, i64 srcElemStride, <2 x i64> srcTileDims, <2 x i64> srcOrigin, i32 clamp)
            Value* esz = ci->getArgOperand(0);
            Value* dst = get(ci->getArgOperand(2)); uint8_t dp = get_prov(ci->getArgOperand(2));
            Value* dpr = ci->getArgOperand(3);
            Value* dtile = ci->getArgOperand(5);
            Value* src = get(ci->getArgOperand(6)); uint8_t sp = get_prov(ci->getArgOperand(6));
            Value* spr = ci->getArgOperand(7);
            Value* stile = ci->getArgOperand(9);
            Function* fn = get_placeholder(m, "xef.copy2d", Type::getVoidTy(ctx), {i64, i64, i64, dtile->getType(), i64, i64, stile->getType(), i32, i32});
            deferred.push_back(b.CreateCall(fn, {esz, dst, dpr, dtile, src, spr, stile, b.getInt32(dp), b.getInt32(sp)}));
        } else {
            fail("unsupported " + name.str());
        }
        if (is_ptr(ci)) map[ci] = ConstantInt::get(i64, 0);
        dead.push_back(ci);
    }

    // ---------------- deferred expansions (create control flow) ----------------
    void expand_mixed_load(CallInst* ci) {
        Value* addr = ci->getArgOperand(0);
        uint8_t p = (uint8_t)cast<ConstantInt>(ci->getArgOperand(1))->getZExtValue();
        Align al((uint64_t)cast<ConstantInt>(ci->getArgOperand(2))->getZExtValue());
        Type* t = ci->getType();
        BasicBlock* head = ci->getParent();
        BasicBlock* tail = head->splitBasicBlock(ci->getIterator(), "mixed.tail");
        head->getTerminator()->eraseFromParent();
        IRBuilder<> hb(head);
        Value* tag = hb.CreateAnd(addr, hb.getInt64(kTagMask));
        PHINode* phi = PHINode::Create(t, 3, "", tail->begin());
        BasicBlock* cur = head;
        std::vector<std::pair<uint8_t, uint64_t>> arms;
        if (p & P_PRIV) arms.push_back({P_PRIV, kTagPriv});
        if (p & P_TG) arms.push_back({P_TG, kTagTg});
        for (auto& [kind, tv] : arms) {
            BasicBlock* yes = BasicBlock::Create(ctx, "mixed.arm", &f, tail);
            BasicBlock* no = BasicBlock::Create(ctx, "mixed.next", &f, tail);
            IRBuilder<> cb(cur);
            if (cur != head) cb.SetInsertPoint(cur);
            cb.CreateCondBr(cb.CreateICmpEQ(tag, cb.getInt64(tv)), yes, no);
            IRBuilder<> yb(yes);
            phi->addIncoming(load_arena(yb, kind == P_TG, t, addr, al), yes);
            yb.CreateBr(tail);
            cur = no;
        }
        IRBuilder<> gb(cur);
        phi->addIncoming(load_global(gb, t, addr, al), cur);
        gb.CreateBr(tail);
        ci->replaceAllUsesWith(phi);
        ci->eraseFromParent();
    }
    void expand_mixed_store(CallInst* ci) {
        Value* v = ci->getArgOperand(0);
        Value* addr = ci->getArgOperand(1);
        uint8_t p = (uint8_t)cast<ConstantInt>(ci->getArgOperand(2))->getZExtValue();
        Align al((uint64_t)cast<ConstantInt>(ci->getArgOperand(3))->getZExtValue());
        BasicBlock* head = ci->getParent();
        BasicBlock* tail = head->splitBasicBlock(ci->getIterator(), "mixed.tail");
        head->getTerminator()->eraseFromParent();
        IRBuilder<> hb(head);
        Value* tag = hb.CreateAnd(addr, hb.getInt64(kTagMask));
        BasicBlock* cur = head;
        std::vector<std::pair<uint8_t, uint64_t>> arms;
        if (p & P_PRIV) arms.push_back({P_PRIV, kTagPriv});
        if (p & P_TG) arms.push_back({P_TG, kTagTg});
        for (auto& [kind, tv] : arms) {
            BasicBlock* yes = BasicBlock::Create(ctx, "mixed.arm", &f, tail);
            BasicBlock* no = BasicBlock::Create(ctx, "mixed.next", &f, tail);
            IRBuilder<> cb(cur);
            cb.CreateCondBr(cb.CreateICmpEQ(tag, cb.getInt64(tv)), yes, no);
            IRBuilder<> yb(yes);
            store_arena(yb, kind == P_TG, v, addr, al);
            yb.CreateBr(tail);
            cur = no;
        }
        IRBuilder<> gb(cur);
        store_global(gb, v, addr, al);
        gb.CreateBr(tail);
        ci->eraseFromParent();
    }
    // byte/word copy loop: for (i = 0; i < len; i += step) *(dst+i) = *(src+i)
    void expand_copy_loop(CallInst* ci, bool is_set) {
        Value* dst = ci->getArgOperand(0);
        Value* src = is_set ? nullptr : ci->getArgOperand(1);
        Value* setv = is_set ? ci->getArgOperand(1) : nullptr;
        Value* len = ci->getArgOperand(2);
        uint8_t dp = (uint8_t)cast<ConstantInt>(ci->getArgOperand(is_set ? 3 : 3))->getZExtValue();
        uint8_t sp = is_set ? 0 : (uint8_t)cast<ConstantInt>(ci->getArgOperand(4))->getZExtValue();
        uint32_t step = is_set ? 1 : (uint32_t)cast<ConstantInt>(ci->getArgOperand(5))->getZExtValue();
        BasicBlock* head = ci->getParent();
        BasicBlock* tail = head->splitBasicBlock(ci->getIterator(), "copy.tail");
        head->getTerminator()->eraseFromParent();
        BasicBlock* loop = BasicBlock::Create(ctx, "copy.loop", &f, tail);
        BasicBlock* body = BasicBlock::Create(ctx, "copy.body", &f, tail);
        IRBuilder<> hb(head);
        hb.CreateBr(loop);
        IRBuilder<> lb(loop);
        PHINode* iv = lb.CreatePHI(i64, 2);
        iv->addIncoming(lb.getInt64(0), head);
        lb.CreateCondBr(lb.CreateICmpULT(iv, len), body, tail);
        IRBuilder<> bb(body);
        Type* et = step == 4 ? i32 : i8;
        Value* v = is_set ? (Value*)setv : load_mem(bb, et, bb.CreateAdd(src, iv), sp, Align(step));
        store_mem(bb, v, bb.CreateAdd(dst, iv), dp, Align(step));
        Value* next = bb.CreateAdd(iv, bb.getInt64(step));
        iv->addIncoming(next, bb.GetInsertBlock());
        bb.CreateBr(loop);
        ci->eraseFromParent();
    }
    void expand_copy2d(CallInst* ci) {
        // element-wise copy of a tile: dst[y*dpr + x] = src[y*spr + x] for x < tile.x, y < tile.y (bytes = esz)
        IRBuilder<> b(ci);
        Value* esz = ci->getArgOperand(0);
        Value* dst = ci->getArgOperand(1);
        Value* dpr = ci->getArgOperand(2);
        Value* dtile = ci->getArgOperand(3);
        Value* src = ci->getArgOperand(4);
        Value* spr = ci->getArgOperand(5);
        uint8_t dp = (uint8_t)cast<ConstantInt>(ci->getArgOperand(7))->getZExtValue();
        uint8_t sp = (uint8_t)cast<ConstantInt>(ci->getArgOperand(8))->getZExtValue();
        Value* tx = b.CreateExtractElement(dtile, (uint64_t)0);
        Value* ty = b.CreateExtractElement(dtile, (uint64_t)1);
        Value* total = b.CreateMul(b.CreateMul(tx, ty), esz);
        // flatten to a byte loop over the tile (rows handled through division)
        BasicBlock* head = ci->getParent();
        BasicBlock* tail = head->splitBasicBlock(ci->getIterator(), "copy2d.tail");
        head->getTerminator()->eraseFromParent();
        BasicBlock* loop = BasicBlock::Create(ctx, "copy2d.loop", &f, tail);
        BasicBlock* body = BasicBlock::Create(ctx, "copy2d.body", &f, tail);
        IRBuilder<> hb(head);
        hb.CreateBr(loop);
        IRBuilder<> lb(loop);
        PHINode* iv = lb.CreatePHI(i64, 2);
        iv->addIncoming(lb.getInt64(0), head);
        lb.CreateCondBr(lb.CreateICmpULT(iv, total), body, tail);
        IRBuilder<> bb(body);
        Value* rowbytes = bb.CreateMul(tx, esz);
        Value* y = bb.CreateUDiv(iv, rowbytes);
        Value* xb = bb.CreateURem(iv, rowbytes);
        Value* so = bb.CreateAdd(bb.CreateMul(y, bb.CreateMul(spr, esz)), xb);
        Value* dof = bb.CreateAdd(bb.CreateMul(y, bb.CreateMul(dpr, esz)), xb);
        Value* v = load_mem(bb, i8, bb.CreateAdd(src, so), sp, Align(1));
        store_mem(bb, v, bb.CreateAdd(dst, dof), dp, Align(1));
        Value* next = bb.CreateAdd(iv, bb.getInt64(1));
        iv->addIncoming(next, bb.GetInsertBlock());
        bb.CreateBr(loop);
        ci->eraseFromParent();
    }

    bool run() {
        // constant expressions using globals -> instructions
        SmallVector<Constant*, 16> gvs;
        for (GlobalVariable& g : m.globals()) if (!g.getName().starts_with("llvm.")) gvs.push_back(&g);
        convertUsersOfConstantsToInstructions(gvs, &f, false);

        classify_globals();
        compute_provenance();
        entry_pt = &*f.getEntryBlock().getFirstInsertionPt();

        // snapshot the original instructions (in RPO) before anything new is created
        std::vector<std::vector<Instruction*>> snap;
        for (BasicBlock* bb : ReversePostOrderTraversal<Function*>(&f)) {
            snap.emplace_back();
            for (Instruction& i : *bb) snap.back().push_back(&i);
        }
        // arenas (sizes fixed after the rewrite; created now with a placeholder size and resized below)

        // first count allocas to size the private arena before creating it
        IRBuilder<> eb(entry_pt);
        ArrayType* placeholder = ArrayType::get(i32, 1);
        ps.priv_arena = eb.CreateAlloca(placeholder, nullptr, "xef.priv");
        ps.tg_arena = new GlobalVariable(m, placeholder, false, GlobalValue::InternalLinkage, PoisonValue::get(placeholder),
                                         "xef.tg", nullptr, GlobalValue::NotThreadLocal, 3);
        tg_size += 0;
        uint32_t tg_args = ps.tg_bytes;   // dynamic threadgroup arguments were laid out by prepare_stage
        // globals in the tg arena go after the arguments
        for (auto& [g, gi] : ginfo) if (gi.kind == GInfo::TG) gi.offset += (tg_args + 15) & ~15u;
        tg_size += (tg_args + 15) & ~15u;

        // initialize private globals
        {
            IRBuilder<> ib(entry_pt);
            for (auto& [g, gi] : ginfo)
                if (gi.kind == GInfo::PRIV && g->hasInitializer() && !isa<UndefValue>(g->getInitializer()))
                    store_arena(ib, false, g->getInitializer(), ConstantInt::get(i64, kTagPriv | gi.offset), Align(4));
        }

        for (auto& insts : snap)
            for (Instruction* i : insts) {
                visit(i);
                if (failed) return false;
            }
        for (auto& [old, np] : phis) {
            for (unsigned k = 0; k < old->getNumIncomingValues(); k++) {
                Value* in = old->getIncomingValue(k);
                BasicBlock* blk = old->getIncomingBlock(k);
                Value* v;
                if (isa<Instruction>(in) && !map.count(in)) {
                    fail("phi incoming not mapped");
                    return false;
                }
                v = get(in);
                np->addIncoming(v, blk);
            }
        }
        for (Instruction* i : dead) i->replaceAllUsesWith(PoisonValue::get(i->getType()));
        for (auto it = dead.rbegin(); it != dead.rend(); ++it) (*it)->eraseFromParent();
        dead.clear();
        if (failed) return false;

        // resize arenas
        uint32_t pw = std::max<uint32_t>(1, (priv_size + 3) / 4);
        uint32_t tw = std::max<uint32_t>(1, (tg_size + 3) / 4);
        ArrayType* pty = ArrayType::get(i32, pw);
        ArrayType* tty = ArrayType::get(i32, tw);
        {
            IRBuilder<> b(ps.priv_arena);
            AllocaInst* na = b.CreateAlloca(pty, nullptr, "xef.priv");
            // GEPs were built with the placeholder type: rebuild them with the real one
            std::vector<User*> users(ps.priv_arena->user_begin(), ps.priv_arena->user_end());
            for (User* u : users)
                if (auto* g = dyn_cast<GetElementPtrInst>(u)) g->setSourceElementType(pty), g->setResultElementType(i32);
            ps.priv_arena->replaceAllUsesWith(na);
            ps.priv_arena->eraseFromParent();
            ps.priv_arena = na;
            if (priv_size == 0 && na->use_empty()) { na->eraseFromParent(); ps.priv_arena = nullptr; }
        }
        {
            auto* ng = new GlobalVariable(m, tty, false, GlobalValue::InternalLinkage, PoisonValue::get(tty), "xef.tg.arena",
                                          nullptr, GlobalValue::NotThreadLocal, 3);
            std::vector<User*> users(ps.tg_arena->user_begin(), ps.tg_arena->user_end());
            for (User* u : users)
                if (auto* g = dyn_cast<GetElementPtrInst>(u)) g->setSourceElementType(tty), g->setResultElementType(i32);
            ps.tg_arena->replaceAllUsesWith(ng);
            ps.tg_arena->eraseFromParent();
            ps.tg_arena = ng;
            if (ng->use_empty()) { ng->eraseFromParent(); ps.tg_arena = nullptr; }
        }
        ps.priv_bytes = priv_size;
        ps.tg_bytes = tg_size;
        ps.res->tg_mem_size = tg_size;

        // deferred control-flow expansions
        for (CallInst* ci : deferred) {
            StringRef n = ci->getCalledFunction()->getName();
            if (n.starts_with("xef.mixed.load")) expand_mixed_load(ci);
            else if (n.starts_with("xef.mixed.store")) expand_mixed_store(ci);
            else if (n.starts_with("xef.memcpy")) expand_copy_loop(ci, false);
            else if (n.starts_with("xef.memset")) expand_copy_loop(ci, true);
            else if (n.starts_with("xef.copy2d")) expand_copy2d(ci);
            if (failed) return false;
        }
        // remove the now unused globals
        std::vector<GlobalVariable*> gdead;
        for (GlobalVariable& g : m.globals())
            if (&g != ps.tg_arena && !g.getName().starts_with("llvm.")) {
                g.removeDeadConstantUsers();
                if (g.use_empty()) gdead.push_back(&g);
            }
        for (GlobalVariable* g : gdead) g->eraseFromParent();
        ps.res->const_data = std::move(const_blob);
        return !failed;
    }
};

} // namespace

// coherent(device) accesses (MSL 3.2): plain volatile loads/stores through the same pointer
static void lower_coherent_accesses(Function& f) {
    std::vector<CallInst*> work;
    for (BasicBlock& b : f)
        for (Instruction& i : b)
            if (auto* ci = dyn_cast<CallInst>(&i))
                if (Function* fn = ci->getCalledFunction())
                    if (fn->getName().starts_with("air.load.device_coherent") || fn->getName().starts_with("air.store.device_coherent"))
                        work.push_back(ci);
    for (CallInst* ci : work) {
        IRBuilder<> b(ci);
        if (ci->getCalledFunction()->getName().starts_with("air.load")) {
            LoadInst* l = b.CreateLoad(ci->getType(), ci->getArgOperand(0), true);
            ci->replaceAllUsesWith(l);
        } else {
            b.CreateStore(ci->getArgOperand(0), ci->getArgOperand(1), true);
        }
        ci->eraseFromParent();
    }
}

bool lower_memory(PreparedStage& ps, std::string& err) {
    lower_coherent_accesses(*ps.main);
    MemLower ml(ps, err);
    if (!ml.run()) return false;
    run_cleanup(*ps.main, false);
    return true;
}

} // namespace mtlc
