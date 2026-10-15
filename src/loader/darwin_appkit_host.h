// XEF-OSX — host side of AppKit-lite (rootfs-src/appkit/xef_host.h): window, events and GL swap on X11/GLX.
#pragma once
#include <stdint.h>

namespace xef {
// Resolves `_xef_host_*` to a guest thunk; 0 when the name is not ours. Called without g_hle_lock held.
uint64_t darwin_appkit_host_resolve(const char* name);
}
