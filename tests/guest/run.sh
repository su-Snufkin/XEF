#!/bin/sh
# Guest program tests: build each test for AArch64 (static and dynamic, -O2 and -O3)
# and compare stdout + exit code between qemu-aarch64 and XEF.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
S=$ROOT/.tools/sysroot-aarch64
Q=$ROOT/.tools/qemu/usr/bin/qemu-aarch64
X=${XEF:-$ROOT/build/xef}
OUT=/tmp/xef_guest
mkdir -p $OUT
pass=0; fail=0
for src in "$ROOT"/tests/guest/t_*.c "$ROOT"/tests/guest/t_*.cpp; do
  name=$(basename "$src"); name=${name%.*}
  case "$src" in *.cpp) CC=clang++;; *) CC=clang;; esac
  # NZCV live across a return (not AAPCS64): exercise the rematerialization with strict flags
  case $name in t_ret_flags) export XEF_STRICT_FLAGS=1;; *) unset XEF_STRICT_FLAGS;; esac
  for variant in "static -O2" "dyn -O3" "static -O3"; do
    set -- $variant
    link=$1; opt=$2
    exe=$OUT/$name-$link$opt
    lflag=""; [ "$link" = static ] && lflag=-static
    if [ ! -x "$exe" ] || [ "$src" -nt "$exe" ]; then
      $CC --target=aarch64-linux-gnu --sysroot=$S -fuse-ld=lld $lflag $opt "$src" -lm -o "$exe" 2>$OUT/build.log || { echo "BUILD FAIL $name"; cat $OUT/build.log; continue; }
    fi
    if [ -f "${src%.*}.expected" ]; then exp=$(cat "${src%.*}.expected"); ec=0
    else exp=$(XEF_T=v $Q -L $S "$exe" a b 2>&1); ec=$?; fi
    got=$(XEF_T=v $X -L $S "$exe" a b 2>&1); gc=$?
    if [ "$exp" = "$got" ] && [ $ec = $gc ]; then pass=$((pass+1)); else
      fail=$((fail+1)); echo "FAIL $name-$link$opt (exit qemu=$ec xef=$gc)"
      echo "$exp" > $OUT/exp.txt; echo "$got" > $OUT/got.txt; diff $OUT/exp.txt $OUT/got.txt | head -10
    fi
  done
done
echo "guest tests: $pass passed, $fail failed"
