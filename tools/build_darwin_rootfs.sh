#!/bin/bash
# Builds the open-source runtime libraries (libc++, libc++abi, libunwind from LLVM) for macOS arm64
# on the remote Mac (ssh mac, see CLAUDE.local.md) and installs them into ./darwin-rootfs.
# Use with:  build/xef-osx -L darwin-rootfs <macOS binary>
set -e
cd "$(dirname "$0")/.."
LLVM_TAG=${LLVM_TAG:-llvmorg-19.1.7}
ssh mac "mkdir -p ~/xef-remote/src/llvm && cd ~/xef-remote/src/llvm &&
  (test -d llvm-project || git clone --depth 1 --branch $LLVM_TAG https://github.com/llvm/llvm-project.git) &&
  cmake -S llvm-project/runtimes -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_RUNTIMES='libunwind;libcxxabi;libcxx' -DCMAKE_INSTALL_PREFIX=\$HOME/xef-remote/out/rootfs/usr \
    -DCMAKE_INSTALL_NAME_DIR=/usr/lib -DLIBCXX_ENABLE_SHARED=ON -DLIBCXXABI_ENABLE_SHARED=ON \
    -DLIBUNWIND_ENABLE_SHARED=ON -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF \
    -DLIBUNWIND_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 >/dev/null &&
  ninja -C build >/dev/null && ninja -C build install >/dev/null"
mkdir -p darwin-rootfs/usr/lib
rsync -a mac:xef-remote/out/rootfs/usr/lib/ darwin-rootfs/usr/lib/ --exclude '*.a' --exclude '*.json'
echo "darwin-rootfs ready: $(ls darwin-rootfs/usr/lib | tr '\n' ' ')"
