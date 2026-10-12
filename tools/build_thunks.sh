#!/bin/sh
# Builds the AArch64 guest shims for --host-gl: build/thunks/libGL.so.1 (GL/GLX/EGL/GLES) and
# build/thunks/libvulkan.so.1, next to build/xef.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
S=$ROOT/.tools/sysroot-aarch64
OUT=${1:-$ROOT/build}/thunks
mkdir -p $OUT
python3 $ROOT/tools/gen_glthunks.py >/dev/null
clang --target=aarch64-linux-gnu --sysroot=$S -fuse-ld=lld -shared -fPIC -O2 -nostartfiles \
  -Wl,-soname,libGL.so.1 -I$ROOT/thunks $ROOT/thunks/gl_stubs.S $ROOT/thunks/glx_shim.c -o $OUT/libGL.so.1
clang --target=aarch64-linux-gnu --sysroot=$S -fuse-ld=lld -shared -fPIC -O2 -nostartfiles \
  -Wl,-soname,libvulkan.so.1 -I$ROOT/thunks $ROOT/thunks/vk_stubs.S $ROOT/thunks/vk_shim.c -o $OUT/libvulkan.so.1
echo "built $OUT/libGL.so.1 $OUT/libvulkan.so.1"
