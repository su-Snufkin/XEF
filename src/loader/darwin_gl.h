// XEF-OSX — host OpenGL bridge: guest `_gl*` imports run on the host libGL (GLX, in-process),
// plus a tiny window API (`_xef_win_*`) for guest apps.
#pragma once
#include <stdint.h>

namespace xef {

// Resolves `_gl[A-Z]*` and `_xef_win_*` to a guest thunk (registered via darwin_hle_register_function);
// returns 0 when the name is not ours or the host lacks it. Must be called WITHOUT g_hle_lock held.
uint64_t darwin_gl_resolve(const char* name);

// Darwin callers read w0 / the low byte for 32-bit / GLboolean results; the SysV host leaves the upper
// bits of rax undefined, so clamp the result to the function's declared return width.
uint64_t darwin_gl_fix_ret(const char* name, uint64_t ret);

} // namespace xef
