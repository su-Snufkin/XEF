#!/bin/bash
# Metal regression: runs tests/darwin/cand4_metal under xef-osx,
# checks rc == 0 and "frames=300" in stdout.
cd "$(dirname "$0")/../.." || exit 1
X=build/xef-osx
[ -x $X ] && [ -f tests/darwin/cand4_metal ] || { echo "FAIL: missing $X or tests/darwin/cand4_metal"; exit 1; }

OUT=$(timeout 30 $X -L darwin-rootfs tests/darwin/cand4_metal 2>&1)
RC=$?

if [ $RC -ne 0 ]; then
  echo "FAIL metal_test: rc=$RC"
  echo "$OUT"
  exit 1
fi

if ! echo "$OUT" | grep -q "frames=300"; then
  echo "FAIL metal_test: expected 'frames=300' in output"
  echo "$OUT"
  exit 1
fi

echo "PASS metal_test"
exit 0
