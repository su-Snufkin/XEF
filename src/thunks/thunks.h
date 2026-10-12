// XEF — guest -> host library thunks (see thunks.cpp).
#pragma once
#include "common/common.h"

namespace xef {

struct CpuState;

// HLT #kThunkHlt in guest code calls host function x17 (exit_info carries kThunkExit).
constexpr u32 kThunkHlt = 0x5846;
constexpr u64 kThunkExit = 0x10000 | kThunkHlt;

extern bool g_host_gl;   // --host-gl: guest libGL/GLX calls go to the host's native libGL

void thunk_dispatch(CpuState* st);
// Host path of the thunk shim replacing the guest library `path` (nullptr: no redirection).
const char* thunk_lib_redirect(const char* path);

}  // namespace xef
