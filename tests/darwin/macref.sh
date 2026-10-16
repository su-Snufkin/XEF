#!/bin/bash
# Reference tests: every tests/darwin/mac/*.{c,cpp,m} is compiled with the real Apple toolchain on the
# remote Mac (ssh mac), run there for the expected output, then run under xef-osx; outputs must match.
# Usage: tests/darwin/macref.sh [name...]     (needs darwin-rootfs: tools/build_darwin_rootfs.sh)
cd "$(dirname "$0")/../.."
X=build/xef-osx
OUT=${TMPDIR:-/tmp}/xef-macref; mkdir -p $OUT
rsync -az --delete tests/darwin/mac/ mac:xef-remote/src/macref/
names=("$@"); [ ${#names[@]} -eq 0 ] && names=($(cd tests/darwin/mac; ls *.c *.cpp *.m 2>/dev/null | sed 's/\.[^.]*$//'))
pass=0; fail=0
for n in "${names[@]}"; do
  src=$(cd tests/darwin/mac; ls $n.c $n.cpp $n.m 2>/dev/null | head -1)
  case $src in
    *.c)   extra=""; grep -q "arm_neon.h" tests/darwin/mac/$src && extra="-mcpu=apple-m1"; grep -q "<resolv.h>" tests/darwin/mac/$src && extra="-lresolv"; grep -q sqlite3.h tests/darwin/mac/$src && extra="-lsqlite3 -lz -liconv -lxml2 -lcurses -I/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/libxml2"; if grep -q CoreFoundation tests/darwin/mac/$src; then cc="clang -O1 -framework CoreFoundation"; else cc="clang -O1"; fi; cc="$cc $extra";;
    *.cpp) cc="clang++ -O1 -std=c++20";;
    *.m)   if grep -q Foundation.h tests/darwin/mac/$src; then cc="clang -framework Foundation"; else cc="clang -lobjc"; fi;;
  esac
  ssh mac "cd ~/xef-remote/src/macref && $cc $src -o $n && ./$n a b > $n.expected 2>/dev/null; echo \$? > $n.rc" || { echo "BUILD FAIL $n"; fail=$((fail+1)); continue; }
  rsync -az mac:xef-remote/src/macref/$n mac:xef-remote/src/macref/$n.expected mac:xef-remote/src/macref/$n.rc $OUT/
  timeout 60 $X -L darwin-rootfs $OUT/$n a b > $OUT/$n.actual 2>$OUT/$n.err; rc=$?
  if diff -q <(sed 's/^[0-9-]* [0-9:.]* [^ ]* //' $OUT/$n.expected) <(sed 's/^[0-9-]* [0-9:.]* [^ ]* //' $OUT/$n.actual) >/dev/null && [ "$rc" = "$(cat $OUT/$n.rc)" ]; then
    echo "PASS $n"; pass=$((pass+1))
  else
    echo "FAIL $n (rc=$rc, expected $(cat $OUT/$n.rc))"; diff <(cat $OUT/$n.expected) $OUT/$n.actual | head -5; tail -2 $OUT/$n.err; fail=$((fail+1))
  fi
done
echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
