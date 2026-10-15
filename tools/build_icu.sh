#!/bin/bash
# Builds ICU (unicode-org/icu release) as a single /usr/lib/libicucore.A.dylib for macOS arm64 on the remote Mac
# (unrenamed symbols, like Apple's libicucore) into ./darwin-rootfs.
set -e
cd "$(dirname "$0")/.."
ICU_VER=${ICU_VER:-74-2}
ssh mac "mkdir -p ~/xef-remote/src/icu-ext"
rsync -a rootfs-src/icu/ mac:xef-remote/src/icu-ext/
ssh mac "bash -s" <<REMOTE
set -e
W=\$HOME/xef-remote/src/icu; mkdir -p \$W; cd \$W
V=$ICU_VER; U=\${V//-/_}
test -f icu4c.tgz || curl -sL -o icu4c.tgz https://github.com/unicode-org/icu/releases/download/release-\$V/icu4c-\$U-src.tgz
test -d icu || tar xzf icu4c.tgz
mkdir -p build && cd build
export CFLAGS="-arch arm64 -mmacosx-version-min=12.0 -O2" CXXFLAGS="-arch arm64 -mmacosx-version-min=12.0 -O2 -std=c++17" LDFLAGS="-arch arm64"
test -f Makefile || ../icu/source/runConfigureICU MacOSX --disable-renaming --disable-samples --disable-tests --disable-extras --disable-layoutex --enable-static --disable-shared --prefix=\$W/inst >/dev/null
make -j8 >/dev/null 2>&1 && make install >/dev/null 2>&1
cd \$W/inst/lib && ls
clang -arch arm64 -mmacosx-version-min=12.0 -O2 -DU_DISABLE_RENAMING=1 -I\$W/inst/include -c \$HOME/xef-remote/src/icu-ext/apple_ext.c -o \$W/apple_ext.o
mkdir -p \$HOME/xef-remote/out/rootfs/usr/lib
clang++ -arch arm64 -mmacosx-version-min=12.0 -dynamiclib -install_name /usr/lib/libicucore.A.dylib -compatibility_version 1.0.0 -current_version 74.2.0 \
  -Wl,-fixup_chains -Wl,-not_for_dyld_shared_cache -Wl,-force_load,libicui18n.a -Wl,-force_load,libicuuc.a -Wl,-force_load,libicuio.a -Wl,-force_load,libicudata.a \$W/apple_ext.o \
  -lc++ -lSystem -o \$HOME/xef-remote/out/rootfs/usr/lib/libicucore.A.dylib 2>&1 | grep -v warning | head
ls -la \$HOME/xef-remote/out/rootfs/usr/lib/libicucore.A.dylib
REMOTE
rsync -a mac:xef-remote/out/rootfs/usr/lib/libicucore.A.dylib darwin-rootfs/usr/lib/
ln -sf libicucore.A.dylib darwin-rootfs/usr/lib/libicucore.dylib
