#!/bin/bash
# Rust toolchain (Homebrew rust + lld bottles: tools/fetch_bottle.py rust lld) under xef-osx: cargo new + cargo build
# --release of a HashMap/threads program, linked by ld64.lld against the stub SDK (tools/make_darwin_sdk.py); the
# binary must print what it prints on the Mac. Skips (exit 0) when rustc, cargo or ld64.lld is missing.
cd "$(dirname "$0")/../.."
R=darwin-rootfs/opt/homebrew/bin
for t in rustc cargo ld64.lld; do [ -e "$R/$t" ] || { echo "SKIP rust_test: $R/$t not found"; exit 0; }; done
[ -e darwin-rootfs/opt/xef-sdk/usr/lib/libSystem.tbd ] || python3 tools/make_darwin_sdk.py > /dev/null
OUT=${TMPDIR:-/tmp}/xef-rust-test; rm -rf "$OUT"; mkdir -p "$OUT"
X="$PWD/build/xef-osx -L $PWD/darwin-rootfs"
export PATH=/opt/homebrew/bin:/usr/bin:/bin HOME=/root SDKROOT=/opt/xef-sdk CARGO_HOME="$OUT/cargo-home"
export CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER=/opt/homebrew/bin/ld64.lld
export RUSTFLAGS="-C linker-flavor=ld64.lld -C link-arg=-platform_version -C link-arg=macos -C link-arg=15.0 -C link-arg=15.0"
(cd "$OUT" && timeout 300 $X /opt/homebrew/bin/cargo new --vcs none app > "$OUT/new.log" 2>&1) || { echo "FAIL rust_test (cargo new)"; exit 1; }
cat > "$OUT/app/src/main.rs" <<'RS'
use std::collections::HashMap;
fn main() {
    let mut m = HashMap::new();
    for w in "the quick brown fox jumps over the lazy dog the end".split(' ') { *m.entry(w).or_insert(0) += 1; }
    let mut v: Vec<_> = m.into_iter().collect();
    v.sort();
    println!("{:?}", v);
    let t: Vec<u64> = (0..4).map(|i| std::thread::spawn(move || (0..1_000_000u64).map(|x| x % (i + 2)).sum()).join().unwrap()).collect();
    println!("{:?}", t);
}
RS
(cd "$OUT/app" && timeout 1200 $X /opt/homebrew/bin/cargo build --release > "$OUT/build.log" 2>&1) \
  || { echo "FAIL rust_test (cargo build, see $OUT/build.log)"; tail -5 "$OUT/build.log"; exit 1; }
got=$(timeout 60 $X "$OUT/app/target/release/app")
want='[("brown", 1), ("dog", 1), ("end", 1), ("fox", 1), ("jumps", 1), ("lazy", 1), ("over", 1), ("quick", 1), ("the", 3)]
[500000, 999999, 1500000, 2000000]'
[ "$got" = "$want" ] && { echo "PASS rust_test"; exit 0; }
echo "FAIL rust_test (output: $got)"; exit 1
