#!/bin/bash
# CMake + Ninja + clang + ld64.lld (Homebrew cmake, ninja, llvm, lld bottles) under xef-osx: configure (compiler
# identification, ABI detection), build and run a C project that needs no SDK headers, against the stub SDK
# (tools/make_darwin_sdk.py). Skips (exit 0) when a tool is missing.
cd "$(dirname "$0")/../.."
for t in bin/cmake bin/ninja opt/llvm/bin/clang bin/ld64.lld; do
    [ -e darwin-rootfs/opt/homebrew/$t ] || { echo "SKIP cmake_test: darwin-rootfs/opt/homebrew/$t not found"; exit 0; }
done
python3 tools/make_darwin_sdk.py > /dev/null
OUT=${TMPDIR:-/tmp}/xef-cmake-test; rm -rf "$OUT"; mkdir -p "$OUT"
X="$PWD/build/xef-osx -L $PWD/darwin-rootfs"
cat > "$OUT/CMakeLists.txt" <<'CM'
cmake_minimum_required(VERSION 3.20)
project(hello C)
add_executable(hello main.c)
CM
cat > "$OUT/main.c" <<'C'
int printf(const char*, ...);
int main(int argc, char** argv) { printf("cmake-built hello, argc=%d\n", argc); return 0; }
C
export PATH=/opt/homebrew/bin:/usr/bin:/bin HOME=/root SDKROOT=/opt/xef-sdk
(cd "$OUT" && timeout 900 $X /opt/homebrew/bin/cmake -S . -B b -G Ninja -DCMAKE_C_COMPILER=/opt/homebrew/opt/llvm/bin/clang \
    -DCMAKE_OSX_SYSROOT=/opt/xef-sdk -DCMAKE_EXE_LINKER_FLAGS=--ld-path=/opt/homebrew/bin/ld64.lld \
    -DCMAKE_MAKE_PROGRAM=/opt/homebrew/bin/ninja > configure.log 2>&1 && \
 timeout 900 $X /opt/homebrew/bin/cmake --build b > build.log 2>&1) \
  || { echo "FAIL cmake_test (see $OUT/configure.log, build.log)"; tail -5 "$OUT/configure.log" "$OUT/build.log" 2>/dev/null; exit 1; }
got=$(timeout 60 $X "$OUT/b/hello" a)
[ "$got" = "cmake-built hello, argc=2" ] && { echo "PASS cmake_test"; exit 0; }
echo "FAIL cmake_test (output: $got)"; exit 1
