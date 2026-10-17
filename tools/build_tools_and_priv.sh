#!/bin/bash
# Builds PrivateFrameworks and tools on remote Mac and installs to darwin-rootfs
set -e
cd "$(dirname "$0")/.."
ssh mac 'mkdir -p ~/xef-remote/src/appkit/private_frameworks ~/xef-remote/src/tools'
rsync -a --delete rootfs-src/appkit/private_frameworks/ mac:xef-remote/src/appkit/private_frameworks/
rsync -a --delete rootfs-src/tools/ mac:xef-remote/src/tools/

ssh mac 'bash -s' <<'REMOTE'
set -e
S=$HOME/xef-remote/src; R=$HOME/xef-remote/out/rootfs; PF=$R/System/Library/PrivateFrameworks; B=$R/usr/bin; O=$HOME/xef-remote/src/priv-build
mkdir -p $O $PF $B; rm -rf $O/*
SDK=$(xcrun --show-sdk-path)
COMMON="-arch arm64 -mmacosx-version-min=12.0"
F=$R/System/Library/Frameworks
LIBS="$F/Foundation.framework/Versions/C/Foundation $F/CoreFoundation.framework/Versions/A/CoreFoundation -L$R/usr/lib -lobjc"

# Build all PrivateFrameworks
for f in $(ls $S/appkit/private_frameworks/*.m); do
  NAME=$(basename $f .m)
  mkdir -p $PF/$NAME.framework/Versions/A
  clang $COMMON -O2 -w -fno-objc-arc -fobjc-exceptions -fblocks -isysroot $SDK -c $f -o $O/$NAME.o
  clang $COMMON -dynamiclib -install_name /System/Library/PrivateFrameworks/$NAME.framework/Versions/A/$NAME \
    -Wl,-compatibility_version,1 -Wl,-current_version,1 -Wl,-not_for_dyld_shared_cache \
    $O/$NAME.o $LIBS -Wl,-undefined,dynamic_lookup -o $PF/$NAME.framework/Versions/A/$NAME
  ln -sfn A $PF/$NAME.framework/Versions/Current
  ln -sfn Versions/Current/$NAME $PF/$NAME.framework/$NAME
  codesign -f -s - $PF/$NAME.framework/Versions/A/$NAME
done

# Build tools: sw_vers, pbcopy, pbpaste, open
clang $COMMON -O2 -w -isysroot $SDK $S/tools/sw_vers.c $F/CoreFoundation.framework/Versions/A/CoreFoundation -o $B/sw_vers
codesign -f -s - $B/sw_vers

for t in pbcopy pbpaste open; do
  clang $COMMON -O2 -w -fobjc-exceptions -fblocks -isysroot $SDK $S/tools/$t.m $LIBS -o $B/$t
  codesign -f -s - $B/$t
done

echo "Remote PrivateFrameworks and tools build complete!"
REMOTE

mkdir -p darwin-rootfs/System/Library/PrivateFrameworks darwin-rootfs/usr/bin
rsync -a mac:xef-remote/out/rootfs/System/Library/PrivateFrameworks/ darwin-rootfs/System/Library/PrivateFrameworks/
rsync -a mac:xef-remote/out/rootfs/usr/bin/ darwin-rootfs/usr/bin/

echo "Successfully synchronized PrivateFrameworks and tools to darwin-rootfs!"
