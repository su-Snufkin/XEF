#!/bin/bash
# Stub versions of every macOS system framework darwin-rootfs has no implementation of (see
# tools/gen_framework_stubs.py). Run after the hand-written frameworks are installed (tools/build_appkit.sh ...):
# a name they implement is never stubbed.
#
#   1. the export lists (.tbd) of the SDK on the remote Mac          -> mac-out/sdk
#   2. tools/mac_fwdump.m on the Mac: function or data, constant
#      values, superclasses - read from the running system            -> mac-out/facts.txt
#   3. stubs built here with clang + ld64.lld                         -> darwin-rootfs
#
# Steps 1 and 2 are skipped when their output exists (REFRESH=1 repeats them); step 3 needs no Mac.
# Extra arguments go to gen_framework_stubs.py build (e.g. --only '/GameKit$').
set -e
cd "$(dirname "$0")/.."
OUT=mac-out
mkdir -p $OUT
if [ -n "$REFRESH" ] || [ ! -d $OUT/sdk/System ]; then
  rm -rf $OUT/sdk; mkdir -p $OUT/sdk
  ssh mac 'cd "$(xcrun --show-sdk-path)" && find System/Library/Frameworks System/Library/PrivateFrameworks System/Library/SubFrameworks usr/lib -name "*.tbd" -print0 2>/dev/null | tar --null -T - -cf - | gzip -3' \
    | tar -xzf - -C $OUT/sdk 2>/dev/null
fi
if [ -n "$REFRESH" ] || [ ! -s $OUT/facts.txt ]; then
  tools/gen_framework_stubs.py request --sdk $OUT/sdk > $OUT/request.txt
  ssh mac 'mkdir -p ~/xef-remote/src/fwdump'
  scp -q tools/mac_fwdump.m mac:xef-remote/src/fwdump/
  gzip -c $OUT/request.txt | ssh mac 'gunzip > ~/xef-remote/src/fwdump/request.txt'
  ssh mac 'cd ~/xef-remote/src/fwdump && clang -O1 -w -framework Foundation mac_fwdump.m -o mac_fwdump && ./mac_fwdump < request.txt 2> facts.err | gzip -3' \
    | gunzip > $OUT/facts.txt
fi
exec tools/gen_framework_stubs.py build --sdk $OUT/sdk --facts $OUT/facts.txt "$@"
