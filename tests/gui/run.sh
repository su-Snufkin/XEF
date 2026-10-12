#!/bin/sh
# Tests for --host-gl (need the rootfs from tools/mkrootfs.sh, the shims from tools/build_thunks.sh
# and a host libGL/libEGL; no X server needed). Each test prints its expected line.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
R=$ROOT/.tools/rootfs-arm64
L=$R/usr/lib/aarch64-linux-gnu
S=$ROOT/.tools/sysroot-aarch64
OUT=/tmp/xef_gui; mkdir -p $OUT
pass=0; fail=0
check() {  # name expected
  got=$(timeout 60 $ROOT/build/xef --host-gl -L $R $OUT/$1 2>&1)
  if [ "$got" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: $got"; fi
}
clang --target=aarch64-linux-gnu --sysroot=$S -fuse-ld=lld -O2 $ROOT/tests/gui/t_gldebug.c $L/libEGL.so.1 $L/libGL.so.1 \
  -Wl,--allow-shlib-undefined -Wl,-rpath-link,$L -o $OUT/t_gldebug
check t_gldebug "debug callback: calls>0=1 type=0x824c user ok=1"
echo "gui tests: $pass passed, $fail failed"
