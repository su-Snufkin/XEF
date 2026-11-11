#!/bin/bash
# Builds tests/darwin/fwstubs_test on Linux: clang + ld64.lld against the .tbd files of the SDK (mac-out/sdk,
# see tools/build_framework_stubs.sh). The test declares what it uses itself, so no SDK headers are needed.
set -e
cd "$(dirname "$0")"
SDK=${SDK:-../../../mac-out/sdk}
LD=$(command -v ld64.lld || command -v ld64.lld-18)
F=$SDK/System/Library/Frameworks
clang -target arm64-apple-macos12.0 -fobjc-runtime=macosx-12.0 -fno-objc-arc -w -O1 -c fwstubs_test.m -o fwstubs_test.o
$LD -arch arm64 -platform_version macos 12.0 12.0 -syslibroot $SDK fwstubs_test.o $SDK/usr/lib/libSystem.B.tbd $SDK/usr/lib/libobjc.A.tbd \
  $F/CoreFoundation.framework/Versions/A/CoreFoundation.tbd $F/Foundation.framework/Versions/C/Foundation.tbd \
  $F/GameKit.framework/Versions/A/GameKit.tbd $F/CoreAudio.framework/Versions/A/CoreAudio.tbd \
  $F/AppKit.framework/Versions/C/AppKit.tbd -o ../fwstubs_test
rm -f fwstubs_test.o
