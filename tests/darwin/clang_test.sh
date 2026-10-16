#!/bin/bash
# clang (Homebrew llvm bottle) + ld64.lld (lld bottle) under xef-osx: compile and link a C program that needs no
# SDK headers against the stub SDK (tools/make_darwin_sdk.py); the binary must print what it prints natively on the
# Mac. Skips (exit 0) when clang or ld64.lld is missing.
cd "$(dirname "$0")/../.."
for t in opt/llvm/bin/clang bin/ld64.lld; do
    [ -e darwin-rootfs/opt/homebrew/$t ] || { echo "SKIP clang_test: darwin-rootfs/opt/homebrew/$t not found"; exit 0; }
done
python3 tools/make_darwin_sdk.py > /dev/null
OUT=${TMPDIR:-/tmp}/xef-clang-test; rm -rf "$OUT"; mkdir -p "$OUT"
X="$PWD/build/xef-osx -L $PWD/darwin-rootfs"
cat > "$OUT/h.c" <<'C'
int printf(const char*, ...);
static unsigned fib(unsigned n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
int main(int argc, char** argv) {
    double s = 0;
    for (int i = 1; i <= 1000; i++) s += 1.0 / i;
    printf("hello from clang under xef: fib(25)=%u H(1000)=%.6f argc=%d\n", fib(25), s, argc);
    return 0;
}
C
(cd "$OUT" && timeout 600 $X /opt/homebrew/opt/llvm/bin/clang -O2 -target arm64-apple-macos15 -isysroot /opt/xef-sdk \
    --ld-path=/opt/homebrew/bin/ld64.lld -o h h.c > cc.log 2>&1) || { echo "FAIL clang_test (compile)"; tail -5 "$OUT/cc.log"; exit 1; }
got=$(cd "$OUT" && timeout 60 $X ./h a b)
want='hello from clang under xef: fib(25)=75025 H(1000)=7.485471 argc=3'
[ "$got" = "$want" ] && { echo "PASS clang_test"; exit 0; }
echo "FAIL clang_test (output: $got)"; exit 1
