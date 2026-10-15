#!/bin/bash
# Node.js (Homebrew arm64 Mach-O) under xef-osx: runs tests/darwin/node_test.js and compares the output with
# tests/darwin/node_expected.txt, which was produced by the same script on the real Mac (node v24.1.0).
# Skips (exit 0) when darwin-rootfs/opt/homebrew/bin/node is missing.
cd "$(dirname "$0")/../.."
NODE=darwin-rootfs/opt/homebrew/bin/node
X=build/xef-osx
if [ ! -e "$NODE" ]; then echo "SKIP node_test: $NODE not found"; exit 0; fi
OUT=${TMPDIR:-/tmp}/xef-node-test; mkdir -p "$OUT"
start=$(date +%s.%N)
timeout -s KILL 50 $X -L darwin-rootfs "$NODE" tests/darwin/node_test.js > "$OUT/actual.txt" 2> "$OUT/err.txt"
rc=$?
t=$(printf "%.2f" "$(echo "$(date +%s.%N) - $start" | bc 2>/dev/null)")
if [ $rc -eq 0 ] && diff -q "$OUT/actual.txt" tests/darwin/node_expected.txt > /dev/null; then
  echo "PASS node_test (${t}s)"; exit 0
fi
echo "FAIL node_test (rc=$rc)"; diff "$OUT/actual.txt" tests/darwin/node_expected.txt | head -10; head -5 "$OUT/err.txt"; exit 1
