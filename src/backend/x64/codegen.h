// XEF — x86-64 code generation from IR.
#pragma once
#include "backend/x64/assembler.h"
#include "ir/ir.h"
#include "runtime/code_cache.h"

namespace xef::backend {

// Number of patchable direct exits the block will need.
int count_exits(const ir::Block& b);

struct HostPcEntry {
    u32 host_off;
    u32 guest_off;
};

struct CodegenOut {
    size_t size = 0;
    int nexits = 0;
    HostPcEntry* pcmap = nullptr;
    int npcmap = 0;
};

// Emits tier-1 code for `b` at as.cur(). Exits are recorded in meta->exits
// and point at per-exit link stubs emitted after the block body.
bool emit_tier1(const ir::Block& b, x64::Assembler& as, BlockMeta* meta, CodegenOut& out);

// Generates the shared runtime stubs into the code cache.
void emit_runtime_stubs(x64::Assembler& as, RuntimeStubs& stubs);

}  // namespace xef::backend
