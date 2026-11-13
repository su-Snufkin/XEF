#!/bin/bash
# Quick rebuild of AppKit.framework alone (the AppKit-lite *.m sources) on the remote Mac; see tools/build_appkit.sh
# for the full set of frameworks it is normally built with.
set -e
cd "$(dirname "$0")/.."
rsync -a --delete rootfs-src/appkit/ mac:xef-remote/src/appkit/
ssh mac 'bash -s' <<'REMOTE'
set -e
S=$HOME/xef-remote/src/appkit; R=$HOME/xef-remote/out/rootfs; F=$R/System/Library/Frameworks; O=$HOME/xef-remote/src/appkit-build-only
mkdir -p $O
SDK=$(xcrun --show-sdk-path)
COMMON="-arch arm64 -mmacosx-version-min=12.0"
LIBS="$F/Foundation.framework/Versions/C/Foundation $F/CoreFoundation.framework/Versions/A/CoreFoundation -L$R/usr/lib -lobjc"
HIT=$F/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox
OBJS=""
for m in AppKitFunctions AppKit AppKitNib AppKitGraphics AppKitControls AppKitControls2 AppKitTable AppKitView AppKitLayout AppKitControllers AppKitModel AppKitGenerated AppKitMenu AppKitAssets AppKitFoundationCompat AppKitDocument AppKitText AppKitTextKit2; do
  clang $COMMON -O2 -w -fno-objc-arc -fobjc-exceptions -fblocks -isysroot $SDK -I$S -c $S/$m.m -o $O/$m.o &
  OBJS="$OBJS $O/$m.o"
done
for z in lzfse_decode lzfse_decode_base lzfse_fse lzvn_decode_base; do
  clang $COMMON -O2 -w -isysroot $SDK -c $S/lzfse/$z.c -o $O/appkit_$z.o
  OBJS="$OBJS $O/appkit_$z.o"
done
wait
clang $COMMON -dynamiclib -install_name /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit \
  -Wl,-compatibility_version,45 -Wl,-current_version,2685.10.108 -Wl,-not_for_dyld_shared_cache \
  $OBJS $LIBS $HIT $F/CoreGraphics.framework/Versions/A/CoreGraphics $F/CoreText.framework/Versions/A/CoreText -Wl,-undefined,dynamic_lookup -o $F/AppKit.framework/Versions/C/AppKit
codesign -f -s - $F/AppKit.framework/Versions/C/AppKit 2>/dev/null
REMOTE
rsync -a mac:xef-remote/out/rootfs/System/Library/Frameworks/AppKit.framework darwin-rootfs/System/Library/Frameworks/
echo "AppKit.framework rebuilt"
# NSSpellChecker reads /usr/share/dict/words: taken from the Mac the first time (the rootfs is built from the user's own Mac)
[ -f darwin-rootfs/usr/share/dict/words ] || { mkdir -p darwin-rootfs/usr/share/dict; scp -q mac:/usr/share/dict/words darwin-rootfs/usr/share/dict/words; }

# system images (NSImageName*): taken from the Mac the first time
[ -f darwin-rootfs/System/Library/Frameworks/AppKit.framework/Resources/NamedImages/manifest.txt ] || tools/capture_named_images.sh
