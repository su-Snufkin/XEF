// XEF-OSX — host OpenGL bridge: guest `_gl*` imports run on the host libGL (GLX, in-process),
// plus a tiny window API (`_xef_win_*`) for guest apps.
#pragma once
#include <stdint.h>

namespace xef {

// Resolves `_gl[A-Z]*` and `_xef_win_*` to a guest thunk (registered via darwin_hle_register_function);
// returns 0 when the name is not ours or the host lacks it. Must be called WITHOUT g_hle_lock held.
uint64_t darwin_gl_resolve(const char* name);

// Shared host access for darwin_appkit_host.cpp: lazily dlopen libGL/libX11 (true on success), and look up
// an Xlib / GL(X) function (GL via glXGetProcAddressARB, falling back to dlsym).
bool darwin_gl_host_libs();
void* darwin_gl_host_x(const char* name);
void* darwin_gl_host_gl(const char* name);

// Darwin callers read w0 / the low byte for 32-bit / GLboolean results; the SysV host leaves the upper
// bits of rax undefined, so clamp the result to the function's declared return width.
uint64_t darwin_gl_fix_ret(const char* name, uint64_t ret);

// For `_gl*` thunks whose Darwin call has stack-passed arguments (>8 integer or >8 FP args): Apple packs the
// stack at natural size/alignment, so re-pack them from the guest stack into 8-byte SysV slots. Returns false
// (nothing written) when `host_fn` needs no repacking. hstack must hold 32 words.
bool darwin_gl_repack(void* host_fn, const uint64_t* x, const uint64_t* v_lo, const uint64_t* guest_sp,
                      uint64_t* iregs, uint64_t* fregs, uint64_t* hstack, uint64_t* nstack);

} // namespace xef
