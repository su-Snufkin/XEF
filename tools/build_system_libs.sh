#!/bin/bash
# Builds small open-source Apple system libraries on the remote Mac for ./darwin-rootfs:
#   libsystem_blocks (libclosure: _NSConcreteStackBlock, _Block_copy, ...)
set -e
cd "$(dirname "$0")/.."
ssh mac 'mkdir -p ~/xef-remote/src/compat'
rsync -a rootfs-src/compat/blocks_objc.m mac:xef-remote/src/compat/
ssh mac 'bash -s' <<'REMOTE'
set -e
W=$HOME/xef-remote/src; cd $W/apple-oss
test -d libclosure || git clone -q --depth 1 https://github.com/apple-oss-distributions/libclosure.git
cd libclosure
mkdir -p $HOME/xef-remote/out/rootfs/usr/lib/system
clang -arch arm64 -mmacosx-version-min=11.0 -O2 -w -fno-objc-arc -DHAVE_OBJC=1 -c data.m -o /tmp/blocks_data.o
clang++ -arch arm64 -mmacosx-version-min=11.0 -O2 -w -fno-rtti -fno-exceptions -DHAVE_OBJC=1 -DHAVE_UNWIND=1 -I. -c runtime.cpp -o /tmp/blocks_runtime.o
clang -arch arm64 -mmacosx-version-min=11.0 -O2 -w -I. -DHAVE_OBJC=1 -DHAVE_UNWIND=1 -c generic_helpers.c -o /tmp/blocks_helpers.o
clang -arch arm64 -mmacosx-version-min=11.0 -O2 -w -fno-objc-arc -I. -c $HOME/xef-remote/src/compat/blocks_objc.m -o /tmp/blocks_objc.o
clang++ -arch arm64 -mmacosx-version-min=11.0 -dynamiclib /tmp/blocks_data.o /tmp/blocks_runtime.o /tmp/blocks_helpers.o /tmp/blocks_objc.o \
  -Wl,-alias_list,Blocks.alias -install_name /usr/lib/system/libsystem_blocks.dylib -Wl,-not_for_dyld_shared_cache \
  -lobjc -lc++ -lSystem -o $HOME/xef-remote/out/rootfs/usr/lib/system/libsystem_blocks.dylib 2>&1 | grep -v warning || true
otool -L $HOME/xef-remote/out/rootfs/usr/lib/system/libsystem_blocks.dylib
REMOTE
mkdir -p darwin-rootfs/usr/lib/system
rsync -a mac:xef-remote/out/rootfs/usr/lib/system/ darwin-rootfs/usr/lib/system/
