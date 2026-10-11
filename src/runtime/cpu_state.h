// XEF — guest CPU state and the fixed guest→host register mapping.
//
// One CpuState per guest thread. While JIT code runs, R15 points at
// (CpuState* + kStateBias) so that the hottest fields (X0..X31, flags) are
// reachable with 1-byte displacements.
#pragma once
#include <cstddef>

#include "backend/x64/assembler.h"
#include "common/common.h"

namespace xef {

struct ThreadCtx;

// Exit reasons returned by the JIT to the C++ runtime loop.
enum ExitReason : u32 {
    EXIT_NONE = 0,
    EXIT_SYSCALL = 1,      // guest executed SVC; state.pc = next insn
    EXIT_LOOKUP = 2,       // indirect branch / unlinked target miss; state.pc = target
    EXIT_LINK = 3,         // direct exit stub; state.exit_info = ExitInfo*
    EXIT_UNDEF = 4,        // undefined/unsupported instruction at state.pc
    EXIT_BRK = 5,          // BRK / trap
    EXIT_SIGNAL = 6,       // pending signal delivery
    EXIT_HELPER = 7,       // generic helper (state.helper_id)
    EXIT_INTERRUPT = 8,
};

struct alignas(64) CpuState {
    // --- hot, disp8 region (relative to R15 = this + kStateBias) ---
    u64 x[32];          // X0..X30, x[31] = SP. Mapped registers' slots are only valid outside JIT.
    u64 pc;             // guest PC (valid at exits)
    u64 eflags;         // saved host EFLAGS holding guest NZCV (canonical: CF = !C)
    u64 flags_spill;    // scratch: EFLAGS spill inside a block
    u64 excl_addr;      // exclusive monitor
    u64 excl_val;
    u64 excl_val2;
    u64 tpidr_el0;
    u64 tpidrro_el0;
    // --- runtime ---
    u64 host_sp;        // C++ stack pointer saved by xef_enter
    u64 jit_sp;         // JIT stack pointer (native return-stack)
    u64 jit_stack_top;
    u64 exit_reason;
    u64 exit_info;      // ExitInfo* / helper arg
    void* ibtc;         // indirect branch target cache table
    ThreadCtx* thread;
    u64 spill[16];      // codegen spill slots
    u32 fpcr, fpsr;
    u64 _pad0;
    alignas(16) u8 v[32][16];  // NEON / FP registers
    alignas(16) u8 vtmp[4][16];   // vector helper arguments / result
    alignas(16) u8 vspill[16][16];
    u64 host_mxcsr_saved;
    volatile u32 pending_signal;
    u32 _pad1;
};

constexpr int kStateBias = 128;

constexpr int st_off(size_t off) { return (int)off - kStateBias; }
#define XEF_ST(field) (::xef::st_off(offsetof(::xef::CpuState, field)))
constexpr int st_x(int r) { return (int)(r * 8) - kStateBias; }
constexpr int st_v(int r) { return (int)(offsetof(CpuState, v) + r * 16) - kStateBias; }

constexpr int kGuestSP = 31;

// ---- Fixed register mapping (see docs/ARCHITECTURE.md §3.2) ----
// X0-X5 sit in the x86 syscall argument registers, so pass-through syscalls
// need no moves, and X0-X2 match SysV rdi/rsi/rdx for library thunks.
namespace regmap {
using namespace x64;
constexpr Reg kState = R15;
constexpr Reg kTmp0 = RAX, kTmp1 = RCX, kTmp2 = R11;
constexpr Reg kUnmapped = NOREG;
// guest index -> host register (NOREG = lives in CpuState)
constexpr Reg kMap[32] = {
    RDI, RSI, RDX, R10, R8, R9, RBX, RBP,             // X0..X7
    NOREG, NOREG, NOREG, NOREG, NOREG, NOREG, NOREG, NOREG,  // X8..X15
    NOREG, NOREG, NOREG, NOREG, NOREG, NOREG, NOREG, NOREG,  // X16..X23
    NOREG, NOREG, NOREG, NOREG, NOREG,                // X24..X28
    R12,                                              // X29 (FP)
    R13,                                              // X30 (LR)
    R14,                                              // SP
};
inline Reg host(int guest) { return kMap[guest]; }
inline bool mapped(int guest) { return kMap[guest] != NOREG; }
}  // namespace regmap

}  // namespace xef
