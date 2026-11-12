#!/bin/bash
# Builds tests/darwin/image_test on Linux (clang + ld64.lld against the SDK stubs in mac-out/sdk); no SDK headers needed.
set -e
cd "$(dirname "$0")"
SDK=${SDK:-../../../mac-out/sdk}
LD=$(command -v ld64.lld || command -v ld64.lld-18)
F=$SDK/System/Library/Frameworks
clang -target arm64-apple-macos12.0 -fobjc-runtime=macosx-12.0 -fno-objc-arc -w -O1 -c image_test.m -o image_test.o
$LD -arch arm64 -platform_version macos 12.0 12.0 -syslibroot $SDK image_test.o $SDK/usr/lib/libSystem.B.tbd $SDK/usr/lib/libobjc.A.tbd \
  $F/Foundation.framework/Versions/C/Foundation.tbd $F/AppKit.framework/Versions/C/AppKit.tbd -undefined dynamic_lookup -o ../image_test
rm -f image_test.o
