// XEF — guest -> host library thunks (see thunks.cpp).
#pragma once
#include "common/common.h"

namespace xef {

struct CpuState;

// HLT #kThunkHlt in guest code calls host function x17 (exit_info carries kThunkExit).
constexpr u32 kThunkHlt = 0x5846;
constexpr u64 kThunkExit = 0x10000 | kThunkHlt;
// HLT #kCallbackRetHlt: a guest function called by the host returned (see guest_call)
constexpr u32 kCallbackRetHlt = 0x5847;
constexpr u64 kCallbackRetExit = 0x10000 | kCallbackRetHlt;

extern bool g_host_gl;   // --host-gl: guest libGL/GLX calls go to the host's native libGL

void thunk_dispatch(CpuState* st);
// Calls guest function `fn` on the current guest thread with integer/pointer arguments (AAPCS64)
// and returns x0. Returns 0 (and does nothing) on threads that are not guest threads.
u64 guest_call(u64 fn, int nargs, const u64* args);
// Signature string of a GL entry point from gl_table.inc (e.g. "v:ffff"), nullptr if unknown.
const char* thunk_gl_sig(const char* name);
// Host path of the thunk shim replacing the guest library `path` (nullptr: no redirection).
const char* thunk_lib_redirect(const char* path);

}  // namespace xef
