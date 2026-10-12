#!/bin/sh
# Guest rootfs path handling (-L): builds a small rootfs with symlinks and runs a static program in it.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
S=$ROOT/.tools/sysroot-aarch64
OUT=/tmp/xef_rootfs_t; rm -rf $OUT; mkdir -p $OUT/r/etc $OUT/r/usr/share/xef
echo inside > $OUT/r/etc/xef-real.conf
ln -s /etc/xef-real.conf $OUT/r/usr/share/xef/link.conf
ln -s /etc $OUT/r/usr/share/xef/etc
ln -s ../../../etc/xef-real.conf $OUT/r/usr/share/xef/rel.conf
ln -s /usr/share/xef/link.conf $OUT/r/usr/share/xef/chain.conf
pass=0; fail=0
for src in "$ROOT"/tests/rootfs/t_*.c; do
  name=$(basename "$src" .c)
  clang --target=aarch64-linux-gnu --sysroot=$S -fuse-ld=lld -static -O2 "$src" -o $OUT/$name || { fail=$((fail+1)); continue; }
  got=$($ROOT/build/xef -L $OUT/r $OUT/$name 2>&1)
  if [ "$got" = "$(cat "${src%.c}.expected")" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); echo "FAIL $name"; echo "$got"; fi
done
echo "rootfs tests: $pass passed, $fail failed"
