// XEF-OSX — Darwin system call and Mach trap emulation.
#pragma once
#include "common/common.h"
#include "runtime/cpu_state.h"

namespace xef {

extern bool g_is_darwin;

// Dispatches a Darwin BSD syscall or Mach trap.
// On entrance:
//   Syscall number in st->x[16] (or st->x[8] fallback)
//   Arguments in st->x[0]..st->x[5]
// On exit:
//   Result in st->x[0] (and st->x[1] for pair returns like pipe)
//   AArch64 Carry flag set on error (CF=0 in st->eflags, x0 = positive errno)
//   AArch64 Carry flag cleared on success (CF=1 in st->eflags, x0 = return value)
void do_darwin_syscall(CpuState* st);

} // namespace xef
