// XEF — translation verifier (debugging aid): XEF_VERIFY=lo-hi runs every scalar block starting in
// [lo, hi) through a reference IR interpreter before the JIT executes it, and reports blocks whose
// translated code ends with different registers, flags, next pc or stored memory.
#pragma once
#include "common/common.h"

namespace xef {

struct CpuState;
struct ThreadCtx;

bool verify_enabled();
bool verify_wants(GuestAddr pc);
// Before the JIT runs the block at st->pc: interpret it on a copy of the state. Returns false
// (nothing to check) for blocks the interpreter does not model.
bool verify_before(ThreadCtx* t, CpuState* st);
// After the JIT returned from that block: compare and report.
void verify_after(CpuState* st);

}  // namespace xef
