#!/bin/sh
# Recreates the local toolchain in .tools/ (no root needed):
#   - cmake + ninja (python venv)
#   - AArch64 glibc sysroot (Debian trixie arm64 packages)  -> .tools/sysroot-aarch64
#   - qemu-aarch64 (Debian qemu-user, static)               -> .tools/qemu  (test oracle only)
#   - benchmark sources (coremark, zstd)                     -> .tools/src
# When deb.debian.org is unreachable (e.g. sandboxed cloud sessions) it falls back to
# Ubuntu noble (ports.ubuntu.com / archive.ubuntu.com).
# Requires: python3, clang/lld (with aarch64 target), curl, bsdtar, git.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$ROOT/.tools
mkdir -p $T/dl $T/src
[ -x $T/venv/bin/cmake ] || { python3 -m venv $T/venv && $T/venv/bin/pip install -q cmake ninja; }
cd $T/dl
if [ -f Packages-arm64.xz ] || curl -sf -o Packages-arm64.xz https://deb.debian.org/debian/dists/trixie/main/binary-arm64/Packages.xz; then
  [ -f Packages-amd64.xz ] || curl -sf -o Packages-amd64.xz https://deb.debian.org/debian/dists/trixie/main/binary-amd64/Packages.xz
  ARM_MIRROR=https://deb.debian.org/debian AMD_MIRROR=$ARM_MIRROR
  ARM_IDX=Packages-arm64.xz AMD_IDX=Packages-amd64.xz
  GCCV=14 QEMU_PKG=qemu-user QEMU_BIN=qemu-aarch64
else
  echo "deb.debian.org unreachable, using Ubuntu noble"
  ARM_MIRROR=http://ports.ubuntu.com/ubuntu-ports AMD_MIRROR=http://archive.ubuntu.com/ubuntu
  ARM_IDX= AMD_IDX=
  for s in noble noble-updates; do for c in main universe; do
    [ -f $s-arm64-$c.xz ] || curl -sf -o $s-arm64-$c.xz $ARM_MIRROR/dists/$s/$c/binary-arm64/Packages.xz
    [ -f $s-amd64-$c.xz ] || curl -sf -o $s-amd64-$c.xz $AMD_MIRROR/dists/$s/$c/binary-amd64/Packages.xz
    ARM_IDX=$ARM_IDX${ARM_IDX:+,}$T/dl/$s-arm64-$c.xz AMD_IDX=$AMD_IDX${AMD_IDX:+,}$T/dl/$s-amd64-$c.xz
  done; done
  GCCV=13 QEMU_PKG=qemu-user-static QEMU_BIN=qemu-aarch64-static
fi
[ -d $T/sysroot-aarch64/usr ] || python3 $ROOT/tools/fetch_debs.py $ARM_MIRROR $T/sysroot-aarch64 $ARM_IDX \
    libc6 libc6-dev libgcc-s1 libgcc-$GCCV-dev libstdc++6 libstdc++-$GCCV-dev linux-libc-dev libzstd1
[ -e $T/sysroot-aarch64/lib ] || ln -s usr/lib $T/sysroot-aarch64/lib
if [ ! -x $T/qemu/usr/bin/qemu-aarch64 ]; then
  python3 $ROOT/tools/fetch_debs.py $AMD_MIRROR $T/qemu $AMD_IDX $QEMU_PKG
  [ $QEMU_BIN = qemu-aarch64 ] || ln -sf $QEMU_BIN $T/qemu/usr/bin/qemu-aarch64
fi
cd $T/src
[ -d coremark ] || git clone -q --depth 1 https://github.com/eembc/coremark.git
[ -d zstd ] || git clone -q --depth 1 --branch v1.5.6 https://github.com/facebook/zstd.git
echo "tools ready. Build:"
echo "  export PATH=$T/venv/bin:\$PATH"
echo "  cmake -S . -B build -G Ninja -DCMAKE_CXX_COMPILER=clang++ && ninja -C build"
