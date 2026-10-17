// xef-mtlc: Metal AIR -> Vulkan SPIR-V compiler (internal interfaces).
//
// Pipeline per stage:
//   prepare_stage   - resolve function constants and static initializers, build the `xef.main` wrapper that
//                     fetches arguments (argument table / builtins / stage inputs) and writes outputs through
//                     xef.* placeholder calls, inline everything, simplify.
//   lower_memory    - pointers become i64: device/constant memory stays as typed loads through
//                     inttoptr (-> PhysicalStorageBuffer), thread/threadgroup memory goes to word arenas.
//   structurize     - LowerSwitch + StructurizeCFG + clspv-style fixups (structured control flow).
//   emit_spirv      - LLVM IR -> SPIR-V words (incl. air.* intrinsics).
#pragma once
#include "air_meta.h"
#include "../src/metal/mtl_shader_proto.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include <string>
#include <vector>

namespace mtlc {

using xef::mtlabi::CompileRequest;
using xef::mtlabi::StageResult;

// tags of i64 pointer values that do not address device memory
constexpr uint64_t kTagPriv = 0xFFFF000000000000ull;
constexpr uint64_t kTagTg = 0xFFFE000000000000ull;
constexpr uint64_t kTagMask = 0xFFFF000000000000ull;

struct LinkInfo {
    std::vector<std::string> vertex_outputs;    // location -> name (filled by the vertex stage)
    bool have_vertex = false;
};

struct PreparedStage {
    StageKind stage = StageKind::Vertex;
    llvm::Module* mod = nullptr;
    llvm::Function* main = nullptr;
    StageResult* res = nullptr;
    llvm::AllocaInst* priv_arena = nullptr;     // [N x i32] in the entry block
    llvm::GlobalVariable* tg_arena = nullptr;   // [N x i32] addrspace(3)
    uint32_t priv_bytes = 0;
    uint32_t tg_bytes = 0;
    uint32_t tg_size[3] = {1, 1, 1};
    bool early_fragment_tests = false;
    std::string depth_mode;                     // "", "any", "greater", "less"
    uint32_t table_slot = 0;                    // which push-constant table this stage reads
};

bool prepare_stage(llvm::Module& m, AirEntry& e, const CompileRequest& req, LinkInfo& link, PreparedStage& ps, std::string& err);
bool lower_memory(PreparedStage& ps, std::string& err);
bool structurize(llvm::Function& f, std::string& err);
bool legalize_ints(llvm::Function& f, std::string& err);
bool emit_spirv(PreparedStage& ps, std::vector<uint32_t>& out, std::string& err);

// structured order + merge/continue targets of a structurized function (clspv algorithm)
struct StructureInfo {
    std::vector<llvm::BasicBlock*> order;
    std::vector<std::pair<llvm::BasicBlock*, llvm::BasicBlock*>> merge;   // header -> merge
    std::vector<std::pair<llvm::BasicBlock*, llvm::BasicBlock*>> cont;    // loop header -> continue target
};
bool compute_structure_info(llvm::Function& f, StructureInfo& out);

// whole request
bool compile(const CompileRequest& req, xef::mtlabi::CompileResult& res);

// helpers
llvm::Function* get_placeholder(llvm::Module& m, const std::string& base, llvm::Type* ret, llvm::ArrayRef<llvm::Type*> params);
std::string type_tag(llvm::Type* t);
bool run_cleanup(llvm::Function& f, bool full);

// SPIR-V builtin ids used by placeholder calls
enum : uint32_t {
    BI_POSITION = 0, BI_POINT_SIZE = 1, BI_CLIP_DISTANCE = 3, BI_PRIMITIVE_ID = 7, BI_LAYER = 9, BI_VIEWPORT_INDEX = 10,
    BI_FRAG_COORD = 15, BI_POINT_COORD = 16, BI_FRONT_FACING = 17, BI_SAMPLE_ID = 18, BI_SAMPLE_MASK = 20,
    BI_FRAG_DEPTH = 22, BI_NUM_WORKGROUPS = 24, BI_WORKGROUP_ID = 26, BI_LOCAL_INVOCATION_ID = 27,
    BI_GLOBAL_INVOCATION_ID = 28, BI_LOCAL_INVOCATION_INDEX = 29, BI_SUBGROUP_SIZE = 36, BI_NUM_SUBGROUPS = 38,
    BI_SUBGROUP_ID = 40, BI_SUBGROUP_LOCAL_INVOCATION_ID = 41, BI_VERTEX_INDEX = 42, BI_INSTANCE_INDEX = 43,
    BI_BASE_VERTEX = 4424, BI_BASE_INSTANCE = 4425, BI_FRAG_STENCIL_REF = 5014, BI_BARY_COORD = 5286,
};
// interpolation flags of xef.in.loc
enum : uint32_t { INTERP_FLAT = 1, INTERP_NOPERSPECTIVE = 2, INTERP_CENTROID = 4, INTERP_SAMPLE = 8 };

} // namespace mtlc
