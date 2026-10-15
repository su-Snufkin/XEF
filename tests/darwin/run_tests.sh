#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$DIR/../../build"
XEF_OSX="$BUILD_DIR/xef-osx"

if [ ! -f "$XEF_OSX" ]; then
    echo "xef-osx binary not found, please build first!"
    exit 1
fi

echo "=== Building Darwin ARM64 test binaries ==="

# 1. Hello Darwin
clang --target=arm64-apple-macos11 -c "$DIR/hello_darwin.s" -o "$DIR/hello_darwin.o"
ld64.lld -arch arm64 -platform_version macos 11.0.0 11.0.0 "$DIR/hello_darwin.o" -o "$DIR/hello_darwin" -e _main

# 2. Complex Darwin
clang --target=arm64-apple-macos11 -c "$DIR/complex_darwin.s" -o "$DIR/complex_darwin.o"
ld64.lld -arch arm64 -platform_version macos 11.0.0 11.0.0 "$DIR/complex_darwin.o" -o "$DIR/complex_darwin" -e _main

# 3. Universal FAT binary
cat << 'EOF' > "$DIR/hello_x86_64.s"
.global _main
.text
_main:
    mov $0x2000001, %rax
    mov $0, %rdi
    syscall
EOF
clang --target=x86_64-apple-macos11 -c "$DIR/hello_x86_64.s" -o "$DIR/hello_x86_64.o"
ld64.lld -arch x86_64 -platform_version macos 11.0.0 11.0.0 "$DIR/hello_x86_64.o" -o "$DIR/hello_x86_64" -e _main
llvm-lipo -create "$DIR/hello_darwin" "$DIR/hello_x86_64" -output "$DIR/hello_universal"

# 4. Freestanding C program
clang --target=arm64-apple-macos11 -ffreestanding -c "$DIR/test_c.c" -o "$DIR/test_c.o"
ld64.lld -arch arm64 -platform_version macos 11.0.0 11.0.0 "$DIR/test_c.o" -o "$DIR/test_c" -e __start

echo "=== Running tests under xef-osx ==="

echo "--- Test 1: Hello Darwin (Mach-O ARM64) ---"
"$XEF_OSX" "$DIR/hello_darwin"

echo "--- Test 2: Complex Darwin (Mach traps, mmap, NEON FP) ---"
"$XEF_OSX" "$DIR/complex_darwin"

echo "--- Test 3: Universal FAT binary (x86_64 + ARM64) ---"
"$XEF_OSX" "$DIR/hello_universal"

echo "--- Test 4: C program with arguments ---"
"$XEF_OSX" "$DIR/test_c" "arg1" "arg2"

echo "=== ALL TESTS COMPLETED SUCCESSFULLY! ==="
