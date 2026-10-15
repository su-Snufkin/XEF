#!/bin/bash
# Builds AppKit-lite (AppKit/Cocoa/OpenGL.framework, arm64 Mach-O) from rootfs-src/appkit on the remote Mac
# and installs it into ./darwin-rootfs. Links against the rootfs Foundation/CoreFoundation/libobjc (not the Mac's
# frameworks); the SDK is used for Foundation headers only. Needs build_foundation.sh output on the Mac first.
# AppKit install name is Versions/C (what cand3_cocoa/GLFW link against); Versions/A is a symlink to it.
set -e
cd "$(dirname "$0")/.."
ssh mac 'mkdir -p ~/xef-remote/src/appkit'; rsync -a --delete rootfs-src/appkit/ mac:xef-remote/src/appkit/
ssh mac 'bash -s' <<'REMOTE'
set -e
S=$HOME/xef-remote/src/appkit; R=$HOME/xef-remote/out/rootfs; F=$R/System/Library/Frameworks; O=$HOME/xef-remote/src/appkit-build
mkdir -p $O; rm -rf $O/*
SDK=$(xcrun --show-sdk-path)
COMMON="-arch arm64 -mmacosx-version-min=12.0"
LIBS="$F/Foundation.framework/Versions/C/Foundation $F/CoreFoundation.framework/Versions/A/CoreFoundation -L$R/usr/lib -lobjc"
mk() { # name version dir
  mkdir -p $F/$1.framework/Versions/$2; }
# AppKit
mk AppKit C
clang $COMMON -O2 -w -fno-objc-arc -fobjc-exceptions -fblocks -isysroot $SDK -I$S -c $S/AppKit.m -o $O/AppKit.o
clang $COMMON -dynamiclib -install_name /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit \
  -Wl,-compatibility_version,45 -Wl,-current_version,2685.10.108 -Wl,-not_for_dyld_shared_cache \
  $O/AppKit.o $LIBS -Wl,-undefined,dynamic_lookup -o $F/AppKit.framework/Versions/C/AppKit
# OpenGL (empty image; gl*/CGL* come from the loader HLE)
mk OpenGL A
clang $COMMON -O2 -w -c $S/OpenGL.c -o $O/OpenGL.o
clang $COMMON -dynamiclib -install_name /System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL \
  -Wl,-compatibility_version,1 -Wl,-current_version,1 -Wl,-not_for_dyld_shared_cache \
  $O/OpenGL.o -Wl,-undefined,dynamic_lookup -o $F/OpenGL.framework/Versions/A/OpenGL
# Cocoa umbrella: re-exports AppKit + Foundation
mk Cocoa A
clang $COMMON -O2 -w -c $S/Cocoa.c -o $O/Cocoa.o
clang $COMMON -dynamiclib -install_name /System/Library/Frameworks/Cocoa.framework/Versions/A/Cocoa \
  -Wl,-compatibility_version,1 -Wl,-current_version,24 -Wl,-not_for_dyld_shared_cache \
  -Wl,-reexport_library,$F/AppKit.framework/Versions/C/AppKit -Wl,-reexport_library,$F/Foundation.framework/Versions/C/Foundation \
  $O/Cocoa.o -Wl,-undefined,dynamic_lookup -o $F/Cocoa.framework/Versions/A/Cocoa
# symlinks + ad-hoc signature
ln -sfn C $F/AppKit.framework/Versions/Current; ln -sfn C $F/AppKit.framework/Versions/A
ln -sfn Versions/Current/AppKit $F/AppKit.framework/AppKit
for p in AppKit.framework/Versions/C/AppKit OpenGL.framework/Versions/A/OpenGL Cocoa.framework/Versions/A/Cocoa; do codesign -f -s - $F/$p; done
ln -sfn A $F/OpenGL.framework/Versions/Current; ln -sfn Versions/Current/OpenGL $F/OpenGL.framework/OpenGL
ln -sfn A $F/Cocoa.framework/Versions/Current; ln -sfn Versions/Current/Cocoa $F/Cocoa.framework/Cocoa
ls -la $F/AppKit.framework/Versions/C/AppKit $F/OpenGL.framework/Versions/A/OpenGL $F/Cocoa.framework/Versions/A/Cocoa
REMOTE
for f in AppKit Cocoa OpenGL; do rsync -a mac:xef-remote/out/rootfs/System/Library/Frameworks/$f.framework darwin-rootfs/System/Library/Frameworks/; done
echo "installed into darwin-rootfs/System/Library/Frameworks"
