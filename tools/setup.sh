#!/bin/sh
# Recreates the local toolchain in .tools/ (no root needed):
#   - cmake + ninja (python venv)
#   - AArch64 glibc sysroot (Debian trixie arm64 packages)  -> .tools/sysroot-aarch64
#   - qemu-aarch64 (Debian qemu-user, static)               -> .tools/qemu  (test oracle only)
#   - benchmark sources (coremark, zstd)                     -> .tools/src
# Requires: python3, clang/lld (with aarch64 target), curl, bsdtar, git.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$ROOT/.tools
mkdir -p $T/dl $T/src
[ -x $T/venv/bin/cmake ] || { python3 -m venv $T/venv && $T/venv/bin/pip install -q cmake ninja; }
cd $T/dl
[ -f Packages-arm64.xz ] || curl -s -o Packages-arm64.xz https://deb.debian.org/debian/dists/trixie/main/binary-arm64/Packages.xz
[ -f Packages-amd64.xz ] || curl -s -o Packages-amd64.xz https://deb.debian.org/debian/dists/trixie/main/binary-amd64/Packages.xz
[ -d $T/sysroot-aarch64/usr ] || python3 $ROOT/tools/fetch_debs.py Packages-arm64.xz $T/sysroot-aarch64 \
    libc6 libc6-dev libgcc-s1 libgcc-14-dev libstdc++6 libstdc++-14-dev linux-libc-dev libzstd1
[ -e $T/sysroot-aarch64/lib ] || ln -s usr/lib $T/sysroot-aarch64/lib
[ -x $T/qemu/usr/bin/qemu-aarch64 ] || python3 $ROOT/tools/fetch_debs.py Packages-amd64.xz $T/qemu qemu-user
cd $T/src
[ -d coremark ] || git clone -q --depth 1 https://github.com/eembc/coremark.git
[ -d zstd ] || git clone -q --depth 1 --branch v1.5.6 https://github.com/facebook/zstd.git
echo "tools ready. Build:"
echo "  export PATH=$T/venv/bin:\$PATH"
echo "  cmake -S . -B build -G Ninja -DCMAKE_CXX_COMPILER=clang++ && ninja -C build"
