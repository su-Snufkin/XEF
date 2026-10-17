// LLVM IR (after prepare/lower_memory/structurize) -> SPIR-V.
#pragma once
#include "mtlc.h"
#include "spirv_builder.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include <map>

namespace mtlc {

class Emitter {
public:
    Emitter(PreparedStage& ps, std::string& err);
    bool run(std::vector<uint32_t>& out);

    // ---- shared state ----
    PreparedStage& ps;
    llvm::Module& m;
    llvm::Function& f;
    const llvm::DataLayout& dl;
    std::string& err;
    SpvBuilder sb;
    bool failed = false;
    bool fragment = false, vertex = false, kernel = false;

    llvm::DenseMap<llvm::Value*, Id> vals;
    llvm::DenseMap<llvm::BasicBlock*, Id> labels;
    llvm::DenseMap<llvm::BasicBlock*, llvm::BasicBlock*> merge_of, continue_of;
    Words body;             // current function body (after the entry label + variables)
    Words fvars;            // OpVariable Function declarations
    std::vector<Id> interface_ids;

    void fail(const std::string& msg);
    Id id_of(llvm::Value* v);   // result id (allocated on first use, also for forward refs)
    Id val(llvm::Value* v);     // operand id (constants materialized)
    Id ty(llvm::Type* t);
    Id label(llvm::BasicBlock* bb);
    void emit(spv::Op op, const Words& ops) { SpvBuilder::inst(body, op, ops); }
    Id emit_r(spv::Op op, Id type, Words ops) {   // instruction with result
        Id r = sb.alloc();
        ops.insert(ops.begin(), r); ops.insert(ops.begin(), type);
        SpvBuilder::inst(body, op, ops);
        return r;
    }
    Id ext(Id type, uint32_t glsl_op, Words args) {
        args.insert(args.begin(), glsl_op); args.insert(args.begin(), sb.glsl());
        return emit_r(spv::OpExtInst, type, args);
    }

    // scalar / vector helpers
    Id t_u32() { return sb.t_int(32); }
    Id c_u32(uint32_t v) { return sb.const_u32(v); }
    Id c_i32(int32_t v) { return sb.const_u32((uint32_t)v); }
    Id c_f32(float v) { return sb.const_f32(v); }
    Id splat(llvm::Type* t, Id scalar);           // vector of t's shape filled with scalar
    Id const_like(llvm::Type* t, double fv, int64_t iv);
    Id to_bool(llvm::Value* v);                    // int -> bool (!= 0)
    Id convert_numeric(Id v, llvm::Type* from, llvm::Type* to, bool src_signed, bool dst_signed);
    Id convert_numeric_ids(Id v, llvm::Type* from, llvm::Type* to, bool src_signed);

    // ---- constants ----
    Id constant(llvm::Constant* c);

    // ---- interface variables ----
    std::map<uint32_t, Id> builtin_in, builtin_out;
    std::map<uint64_t, Id> loc_in, loc_out;
    Id pc_var = 0, pc_struct = 0;
    Id input_builtin(uint32_t bi, llvm::Type* t, Id& var_type);
    Id builtin_var(bool out, uint32_t bi, Id type);
    Id location_var(bool out, uint32_t loc, uint32_t index, uint32_t interp, Id type);
    Id push_constants();
    bool writes_depth = false, writes_stencil = false, uses_demote = false;

    // ---- memory ----
    Id psb_pointer(llvm::Value* intptr_addr, Id pointee);   // OpConvertUToPtr
    bool local_pointer(llvm::Value* p, Id& ptr_id, llvm::Type*& elem_ty, spv::StorageClass& sc);
    std::map<llvm::Value*, Id> local_vars;                    // allocas / workgroup globals -> variable ids
    Id local_var(llvm::Value* base, spv::StorageClass& sc, llvm::Type*& vty);
    void emit_load(llvm::LoadInst* li);
    void emit_store(llvm::StoreInst* si);
    void emit_atomicrmw(llvm::AtomicRMWInst* a);
    void emit_cmpxchg(llvm::AtomicCmpXchgInst* a);
    Id atomic_pointer(llvm::Value* ptr, llvm::Type* vt, uint32_t& scope);

    // ---- images ----
    std::map<uint32_t, Id> image_vars;   // binding -> variable
    Id sampler_var = 0;
    Id image_type_for(uint32_t dim, uint32_t comp, bool storage);
    Id load_image(uint32_t dim, uint32_t comp, bool storage, llvm::Value* handle, Id& img_type);
    Id load_sampler(llvm::Value* handle);
    Id handle_index(llvm::Value* handle);

    // ---- instructions ----
    void emit_block(llvm::BasicBlock* bb);
    void emit_inst(llvm::Instruction* i);
    void emit_call(llvm::CallInst* ci);
    bool emit_llvm_intrinsic(llvm::CallInst* ci);
    bool emit_air(llvm::CallInst* ci, llvm::StringRef name);
    bool emit_air_texture(llvm::CallInst* ci, llvm::StringRef name);
    bool emit_air_simd(llvm::CallInst* ci, llvm::StringRef name);
    bool emit_placeholder(llvm::CallInst* ci, llvm::StringRef name);
    void set(llvm::Value* v, Id id) { vals[v] = id; }
    void result(llvm::Instruction* i, Id id);   // binds i to an already emitted id (copy if pre-allocated)
    Id copy_into(Id type, Id src, Id dst);

    // structured control flow
    void compute_structure();
    std::vector<llvm::BasicBlock*> order;
};

} // namespace mtlc
