#!/bin/bash
# Builds AppKit-lite (AppKit/Cocoa/OpenGL.framework, arm64 Mach-O) from rootfs-src/appkit on the remote Mac,
# plus CoreGraphics/IOKit/CoreServices-lite and HIToolbox (TIS) for GLFW (see the .c files there),
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
HIT=$F/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox
mk() { # name version dir
  mkdir -p $F/$1.framework/Versions/$2; }
# HIToolbox (Carbon sub-framework, bundle com.apple.HIToolbox: GLFW looks the TIS functions up through CFBundle) and
# the C-only system frameworks. They use CF only; host calls (xef_host_*) are resolved by the loader.
H=$F/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework
CF="$F/CoreFoundation.framework/Versions/A/CoreFoundation"
sysfw() { # name versiondir install-name compat current extra-link
  mkdir -p $(dirname $3 | sed "s|^/System/Library/Frameworks|$F|")
  clang $COMMON -O2 -w -isysroot $SDK -c $S/$1.c -o $O/$1.o
  clang $COMMON -dynamiclib -install_name $3 -Wl,-compatibility_version,$4 -Wl,-current_version,$5 -Wl,-not_for_dyld_shared_cache \
    $O/$1.o $CF -Wl,-undefined,dynamic_lookup -o $(echo $3 | sed "s|^/System/Library/Frameworks|$F|")
  codesign -f -s - $(echo $3 | sed "s|^/System/Library/Frameworks|$F|"); }
sysfw CoreGraphics x /System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics 64 1957.0.0
sysfw IOKit x /System/Library/Frameworks/IOKit.framework/Versions/A/IOKit 1 275.0.0
sysfw CoreServices x /System/Library/Frameworks/CoreServices.framework/Versions/A/CoreServices 1 1226.0.0
sysfw HIToolbox x /System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox 1 1
mkdir -p $H/Versions/A/Resources; cp $S/HIToolbox-Info.plist $H/Versions/A/Resources/Info.plist
ln -sfn A $H/Versions/Current; ln -sfn Versions/Current/HIToolbox $H/HIToolbox; ln -sfn Versions/Current/Resources $H/Resources
for n in CoreGraphics IOKit CoreServices; do ln -sfn A $F/$n.framework/Versions/Current; ln -sfn Versions/Current/$n $F/$n.framework/$n; done
ln -sfn A $F/Carbon.framework/Versions/Current
# AppKit
mk AppKit C
clang $COMMON -O2 -w -fno-objc-arc -fobjc-exceptions -fblocks -isysroot $SDK -I$S -c $S/AppKit.m -o $O/AppKit.o
clang $COMMON -dynamiclib -install_name /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit \
  -Wl,-compatibility_version,45 -Wl,-current_version,2685.10.108 -Wl,-not_for_dyld_shared_cache \
  $O/AppKit.o $LIBS $HIT -Wl,-undefined,dynamic_lookup -o $F/AppKit.framework/Versions/C/AppKit
# OpenGL (empty image; gl*/CGL* come from the loader HLE)
mk OpenGL A
clang $COMMON -O2 -w -c $S/OpenGL.c -o $O/OpenGL.o
clang $COMMON -dynamiclib -install_name /System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL \
  -Wl,-compatibility_version,1 -Wl,-current_version,1 -Wl,-not_for_dyld_shared_cache \
  $O/OpenGL.o -Wl,-undefined,dynamic_lookup -o $F/OpenGL.framework/Versions/A/OpenGL
# bundle com.apple.opengl: GLFW's NSGL layer resolves gl* through CFBundleGetFunctionPointerForName on it
mkdir -p $F/OpenGL.framework/Versions/A/Resources; cp $S/OpenGL-Info.plist $F/OpenGL.framework/Versions/A/Resources/Info.plist
ln -sfn Versions/Current/Resources $F/OpenGL.framework/Resources
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
for f in AppKit Cocoa OpenGL CoreGraphics IOKit CoreServices Carbon; do rsync -a mac:xef-remote/out/rootfs/System/Library/Frameworks/$f.framework darwin-rootfs/System/Library/Frameworks/; done
echo "installed into darwin-rootfs/System/Library/Frameworks"
