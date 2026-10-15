#!/bin/bash
# libdispatch-lite (rootfs-src/libdispatch-lite): XEF's own compact GCD, built on the Mac as guest code
# -> /usr/lib/system/libdispatch.dylib in ./darwin-rootfs.
set -e
cd "$(dirname "$0")/.."
ssh mac 'mkdir -p ~/xef-remote/src/dl'
rsync -a rootfs-src/libdispatch-lite/ mac:xef-remote/src/dl/
ssh mac 'bash -s' <<'REMOTE'
set -e
cd ~/xef-remote/src/dl
mkdir -p ~/xef-remote/out/rootfs/usr/lib/system
clang -arch arm64 -mmacosx-version-min=12.0 -O2 -fblocks -fno-objc-arc -dynamiclib -install_name /usr/lib/system/libdispatch.dylib \
  -Wl,-fixup_chains -Wl,-not_for_dyld_shared_cache -Wl,-compatibility_version,1.0.0 -Wl,-current_version,1.0.0 \
  dispatch_lite.m -lobjc -lSystem -o ~/xef-remote/out/rootfs/usr/lib/system/libdispatch.dylib 2>&1 | grep -v "warning\|note:" | head -30
ls -la ~/xef-remote/out/rootfs/usr/lib/system/libdispatch.dylib
REMOTE
mkdir -p darwin-rootfs/usr/lib/system
rsync -a mac:xef-remote/out/rootfs/usr/lib/system/libdispatch.dylib darwin-rootfs/usr/lib/system/
