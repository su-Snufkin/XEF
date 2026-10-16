#!/bin/bash
# Metal regression test suite
cd "$(dirname "$0")/../.." || exit 1
X=build/xef-osx
[ -x $X ] && [ -f tests/darwin/cand4_metal ] || { echo "FAIL: missing $X or tests/darwin/cand4_metal"; exit 1; }

OUT1=$(timeout 30 $X -L darwin-rootfs tests/darwin/cand4_metal 2>&1)
RC1=$?

if [ $RC1 -ne 0 ] || ! echo "$OUT1" | grep -q "frames=300"; then
  echo "FAIL metal_test (cand4_metal): rc=$RC1"
  echo "$OUT1"
  exit 1
fi

if [ -f tests/darwin/metallib_test ] && [ -f tests/darwin/AAPLShaders.metallib ]; then
  OUT2=$(timeout 15 $X -L darwin-rootfs tests/darwin/metallib_test tests/darwin/AAPLShaders.metallib 2>&1)
  RC2=$?
  if [ $RC2 -ne 0 ] || ! echo "$OUT2" | grep -q "PASS metallib_test"; then
    echo "FAIL metal_test (metallib_test): rc=$RC2"
    echo "$OUT2"
    exit 1
  fi
fi

if [ -f tests/darwin/metalkit_test ]; then
  OUT3=$(timeout 15 $X -L darwin-rootfs tests/darwin/metalkit_test 2>&1)
  RC3=$?
  if [ $RC3 -ne 0 ] || ! echo "$OUT3" | grep -q "PASS metalkit_test"; then
    echo "FAIL metal_test (metalkit_test): rc=$RC3"
    echo "$OUT3"
    exit 1
  fi
fi

if [ -f tests/darwin/compute_test ] && [ -f tests/darwin/add.metallib ]; then
  OUT4=$(timeout 15 $X -L darwin-rootfs tests/darwin/compute_test tests/darwin/add.metallib 2>&1)
  RC4=$?
  if [ $RC4 -ne 0 ] || ! echo "$OUT4" | grep -q "PASS compute_test"; then
    echo "FAIL metal_test (compute_test): rc=$RC4"
    echo "$OUT4"
    exit 1
  fi
fi

echo "PASS metal_test"
exit 0
