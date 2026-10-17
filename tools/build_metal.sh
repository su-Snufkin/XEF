#!/bin/bash
# Rebuilds only Metal.framework, QuartzCore.framework and MetalKit.framework (arm64 Mach-O) on the remote Mac and
# installs them into ./darwin-rootfs (the full set is built by tools/build_appkit.sh).
set -e
cd "$(dirname "$0")/.."
ssh mac 'mkdir -p ~/xef-remote/src/appkit'
rsync -a rootfs-src/appkit/ mac:xef-remote/src/appkit/
ssh mac 'bash -s' <<'REMOTE'
set -e
S=$HOME/xef-remote/src/appkit; R=$HOME/xef-remote/out/rootfs; F=$R/System/Library/Frameworks; O=$HOME/xef-remote/src/appkit-build-metal
mkdir -p $O
SDK=$(xcrun --show-sdk-path)
COMMON="-arch arm64 -mmacosx-version-min=12.0"
LIBS="$F/Foundation.framework/Versions/C/Foundation $F/CoreFoundation.framework/Versions/A/CoreFoundation -L$R/usr/lib -lobjc"
CFLAGS="$COMMON -O2 -w -fno-objc-arc -fobjc-exceptions -fblocks -isysroot $SDK -I$S"
build() {   # name extra-link-args sources...
  local NAME=$1 EXTRA=$2; shift 2
  local objs=""
  for src in "$@"; do o=$O/$(echo ${src%.*} | tr / _).o; clang $CFLAGS -c $S/$src -o $o; objs="$objs $o"; done
  mkdir -p $F/$NAME.framework/Versions/A
  clang $COMMON -dynamiclib -install_name /System/Library/Frameworks/$NAME.framework/Versions/A/$NAME \
    -Wl,-compatibility_version,1 -Wl,-current_version,1 -Wl,-not_for_dyld_shared_cache \
    $objs $LIBS $EXTRA -Wl,-undefined,dynamic_lookup -o $F/$NAME.framework/Versions/A/$NAME
  ln -sfn A $F/$NAME.framework/Versions/Current
  ln -sfn Versions/Current/$NAME $F/$NAME.framework/$NAME
  codesign -f -s - $F/$NAME.framework/Versions/A/$NAME >/dev/null 2>&1
}
CG=$F/CoreGraphics.framework/Versions/A/CoreGraphics
build Metal "$CG" Metal.m MetalCore.m MetalExtras.m
build GameController "" GameController.m
build QuartzCore "$CG $F/Metal.framework/Versions/A/Metal" QuartzCore.m
build MetalKit "$CG $F/AppKit.framework/Versions/C/AppKit $F/QuartzCore.framework/Versions/A/QuartzCore $F/Metal.framework/Versions/A/Metal" MetalKit.m MetalKitAssets.m \
  lzfse/lzfse_decode.c lzfse/lzfse_decode_base.c lzfse/lzfse_fse.c lzfse/lzvn_decode_base.c
REMOTE
for f in Metal QuartzCore MetalKit GameController; do
  rsync -a mac:xef-remote/out/rootfs/System/Library/Frameworks/$f.framework darwin-rootfs/System/Library/Frameworks/
done
echo "installed Metal, QuartzCore, MetalKit"
