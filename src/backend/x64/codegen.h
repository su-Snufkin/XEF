// XEF — x86-64 code generation from IR.
#pragma once
#include "backend/x64/assembler.h"
#include "ir/ir.h"
#include "runtime/code_cache.h"

namespace xef::backend {

// Number of patchable direct exits the block will need.
int count_exits(const ir::Block& b);

using HostPcEntry = PcMapEntry;

// One host register whose content differs between the canonical mapping and a region mapping.
struct RegionXfer {
    x64::Reg h;
    i8 g_region;  // guest reg held in h inside the region (-1: scratch)
    i8 g_canon;   // guest reg held in h in the canonical mapping (-1: temp)
    bool written; // g_region is written inside the region (needs write-back on exit)
};

// One host XMM register holding a guest V register inside a tier-2 region.
struct RegionVXfer {
    x64::Xmm h;
    u8 g;         // guest V reg (0..31) held in h inside the region
    bool written; // g is written inside the region (needs write-back on exit)
};

struct CodegenCtx {
    const x64::Reg* map = nullptr;   // guest -> host (nullptr: canonical regmap)
    const x64::Reg* temps = nullptr;
    int ntemps = 0;
    const u8* vmap = nullptr;        // guest V -> host Xmm (nullptr: all in CpuState)
    bool region = false;
    bool (*is_internal)(void* user, GuestAddr target) = nullptr;
    void* user = nullptr;
    const RegionXfer* xfer = nullptr;
    int nxfer = 0;
    const RegionVXfer* vxfer = nullptr;
    int nvxfer = 0;
    u64* exit_counter = nullptr;   // region exit counter (RIP-addressable)
    GuestAddr fall_pc = 0;         // region member laid out right after this one (falls through)
};

struct InternalFix {
    u8* field;        // rel32 field to patch
    GuestAddr target; // region-internal guest block
};

struct CodegenOut {
    size_t size = 0;
    int nexits = 0;
    HostPcEntry* pcmap = nullptr;
    int npcmap = 0;
    InternalFix fixes[64];
    int nfixes = 0;
};

// Emits canonical -> region (enter=true) or region -> canonical register transfers.
void emit_region_xfer(x64::Assembler& as, const RegionXfer* x, int n,
                      const RegionVXfer* vx, int nv, bool enter);

// Tier-2 region members: body first (out.size = body bytes), exit stubs after all bodies.
struct RegionBodyGen;
RegionBodyGen* emit_region_body(const ir::Block& b, x64::Assembler& as, BlockMeta* meta, CodegenOut& out,
                                const CodegenCtx& ctx);
bool finish_region_body(RegionBodyGen* g, bool emit_cold);   // emits the cold stubs, frees g

// Emits tier-1 code for `b` at as.cur(). Exits are recorded in meta->exits
// and point at per-exit link stubs emitted after the block body.
bool emit_tier1(const ir::Block& b, x64::Assembler& as, BlockMeta* meta, CodegenOut& out,
                const CodegenCtx* ctx = nullptr);

// Generates the shared runtime stubs into the code cache.
void emit_runtime_stubs(x64::Assembler& as, RuntimeStubs& stubs);

}  // namespace xef::backend
