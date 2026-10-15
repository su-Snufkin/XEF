#!/bin/bash
# Builds tests/darwin/gltri (arm64 Mach-O, XEF variant: xef_win_* resolved at load time) on the real Mac,
# and the Mac-oracle variant (shim_mac.m) which dumps a reference PPM. Needs `ssh mac`.
set -e
cd "$(dirname "$0")"
ssh mac 'mkdir -p ~/xef-remote/src/gltri'
rsync -az gltri.c gltri_core.c shim_mac.m mac:xef-remote/src/gltri/
ssh mac 'cd ~/xef-remote/src/gltri && clang -O1 -arch arm64 -mmacosx-version-min=11.0 -framework OpenGL -Wl,-undefined,dynamic_lookup gltri.c -o gltri'
rsync -az mac:xef-remote/src/gltri/gltri ../gltri
ssh mac 'cd ~/xef-remote/src/gltri && clang -O1 -arch arm64 -mmacosx-version-min=11.0 -framework OpenGL -Wl,-undefined,dynamic_lookup gltri_core.c -o gltri_core'
rsync -az mac:xef-remote/src/gltri/gltri_core ../gltri_core
# Mac oracle (needs a GUI session on the Mac); writes ref.ppm
ssh mac 'cd ~/xef-remote/src/gltri && clang -O1 -DGL_SILENCE_DEPRECATION -framework Cocoa -framework OpenGL gltri.c shim_mac.m -o gltri_mac' && \
ssh mac 'cd ~/xef-remote/src/gltri && ./gltri_mac /tmp/gltri_ref.ppm' && \
rsync -az mac:/tmp/gltri_ref.ppm ref.ppm || echo "Mac oracle failed (no GUI session?)" >&2
# core-profile oracle (3.2 core NSOpenGLContext); writes ref_core.ppm
ssh mac 'cd ~/xef-remote/src/gltri && clang -O1 -DGL_SILENCE_DEPRECATION -framework Cocoa -framework OpenGL gltri_core.c shim_mac.m -o gltri_core_mac' && \
ssh mac 'cd ~/xef-remote/src/gltri && ./gltri_core_mac /tmp/gltri_core_ref.ppm' && \
rsync -az mac:/tmp/gltri_core_ref.ppm ref_core.ppm || echo "Mac core oracle failed" >&2
# Cocoa app (NSOpenGLView; AppKit-lite on XEF, real AppKit on the Mac): same binary is the oracle, writes ref_cocoa.ppm
ssh mac 'mkdir -p ~/xef-remote/src/cocoa_gl'
rsync -az cocoa_gl.m mac:xef-remote/src/cocoa_gl/
ssh mac 'cd ~/xef-remote/src/cocoa_gl && clang -O1 -arch arm64 -mmacosx-version-min=11.0 -fno-objc-arc -framework Cocoa -framework OpenGL cocoa_gl.m -o cocoa_gl'
rsync -az mac:xef-remote/src/cocoa_gl/cocoa_gl ../cocoa_gl
ssh mac 'cd ~/xef-remote/src/cocoa_gl && ./cocoa_gl /tmp/cocoa_ref.ppm' && \
rsync -az mac:/tmp/cocoa_ref.ppm ref_cocoa.ppm || echo "Mac cocoa oracle failed (no GUI session?)" >&2
