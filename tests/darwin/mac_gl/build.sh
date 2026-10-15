#!/bin/bash
# Builds tests/darwin/gltri (arm64 Mach-O, XEF variant: xef_win_* resolved at load time) on the real Mac,
# and the Mac-oracle variant (shim_mac.m) which dumps a reference PPM. Needs `ssh mac`.
set -e
cd "$(dirname "$0")"
ssh mac 'mkdir -p ~/xef-remote/src/gltri'
rsync -az gltri.c shim_mac.m mac:xef-remote/src/gltri/
ssh mac 'cd ~/xef-remote/src/gltri && clang -O1 -arch arm64 -mmacosx-version-min=11.0 -framework OpenGL -Wl,-undefined,dynamic_lookup gltri.c -o gltri'
rsync -az mac:xef-remote/src/gltri/gltri ../gltri
# Mac oracle (needs a GUI session on the Mac); writes ref.ppm
ssh mac 'cd ~/xef-remote/src/gltri && clang -O1 -DGL_SILENCE_DEPRECATION -framework Cocoa -framework OpenGL gltri.c shim_mac.m -o gltri_mac' && \
ssh mac 'cd ~/xef-remote/src/gltri && ./gltri_mac /tmp/gltri_ref.ppm' && \
rsync -az mac:/tmp/gltri_ref.ppm ref.ppm || echo "Mac oracle failed (no GUI session?)" >&2
