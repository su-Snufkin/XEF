#!/bin/bash
# Compile one source on the Mac, run it there and under xef-osx; print both outputs (for debugging).
cd "$(dirname "$0")/../.."
src=$1; shift
n=$(basename "$src" | sed 's/\.[^.]*$//')
ext=${src##*.}
case $ext in c) cc="clang -O1";; cpp) cc="clang++ -O1 -std=c++20";; m|mm) cc="clang -framework Foundation";; esac
grep -q CoreFoundation $src && ! grep -q Foundation.h $src && cc="$cc -framework CoreFoundation"
ssh mac "mkdir -p ~/xef-remote/src/try" && scp -q $src mac:xef-remote/src/try/ && ssh mac "cd ~/xef-remote/src/try && $cc $(basename $src) -o $n 2>&1 | grep -E 'error' ; ./$n $* 2>&1" > /tmp/xef-try-mac.txt
scp -q mac:xef-remote/src/try/$n /tmp/xef-try-$n
timeout ${TRY_TIMEOUT:-30} build/xef-osx -L darwin-rootfs /tmp/xef-try-$n "$@" > /tmp/xef-try-xef.txt 2>&1
diff <(sed 's/^[0-9-]* [0-9:.]* [^ ]* //' /tmp/xef-try-mac.txt) <(sed 's/^[0-9-]* [0-9:.]* [^ ]* //' /tmp/xef-try-xef.txt) && echo "SAME" || { echo "--- mac"; head -${TRY_LINES:-20} /tmp/xef-try-mac.txt; echo "--- xef"; head -${TRY_LINES:-20} /tmp/xef-try-xef.txt; }
