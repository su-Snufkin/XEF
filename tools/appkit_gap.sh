#!/bin/bash
# What of AppKit's public API AppKit-lite does not implement: per class, the missing methods.
#   tools/appkit_gap.sh            # summary: classes by number of missing methods
#   tools/appkit_gap.sh NSView     # the missing methods of one class
# Measured with the generated placeholders (tools/gen_appkit_stubs.py) switched off: only real implementations count.
# Needs mac-out/headers (the SDK's AppKit.framework/Headers, copied from the Mac on first use) and mac-out/sdk.
set -e
cd "$(dirname "$0")/.."
if [ ! -d mac-out/headers ]; then
  mkdir -p mac-out/headers
  ssh mac 'cd "$(xcrun --show-sdk-path)/System/Library/Frameworks/AppKit.framework/Headers" && tar -cf - . | gzip -3' | tar -xzf - -C mac-out/headers 2>/dev/null
fi
tools/appkit_api.py mac-out/headers > mac-out/appkit_api.txt
SDK=mac-out/sdk; F=$SDK/System/Library/Frameworks; B=build/apigap
LD=$(command -v ld64.lld || command -v ld64.lld-18)
clang -target arm64-apple-macos12.0 -fobjc-runtime=macosx-12.0 -fno-objc-arc -w -O1 -c tests/darwin/apigap/apigap.m -o $B.o
$LD -arch arm64 -platform_version macos 12.0 12.0 -syslibroot $SDK $B.o $SDK/usr/lib/libSystem.B.tbd $SDK/usr/lib/libobjc.A.tbd \
  $F/Foundation.framework/Versions/C/Foundation.tbd $F/AppKit.framework/Versions/C/AppKit.tbd -undefined dynamic_lookup -o $B
XEF_APPKIT_NO_GENERATED=1 build/xef-osx -L darwin-rootfs $B "$PWD/mac-out/appkit_api.txt" 2>/dev/null > mac-out/appkit_gap.txt
total=$(wc -l < mac-out/appkit_api.txt); missing=$(grep -c '^M' mac-out/appkit_gap.txt || true)
absent=$(grep -c '^X' mac-out/appkit_gap.txt || true)
inabsent=$(awk -F'\t' 'NR==FNR { if ($1 == "X") x[$2] = 1; next } ($1 in x) { n++ } END { print n + 0 }' mac-out/appkit_gap.txt mac-out/appkit_api.txt)
if [ -n "$1" ]; then
  grep -P "^[MX]\t$1(\t|$)" mac-out/appkit_gap.txt || echo "$1: nothing missing"
else
  gen=$(grep -c "^{\"" rootfs-src/appkit/AppKitGenerated.m 2>/dev/null || echo 0)
  echo "public methods: $total; implemented: $((total - missing - inabsent)); missing in existing classes: $missing; in $absent absent classes: $inabsent; generated placeholders for $gen of them"
  echo "--- existing classes with the most missing methods"
  grep '^M' mac-out/appkit_gap.txt | cut -f2 | sort | uniq -c | sort -rn | head -${TOP:-25}
  echo "--- absent classes by size of their API"
  awk -F'\t' 'NR==FNR { if ($1 == "X") x[$2] = 1; next } ($1 in x) { n[$1]++ } END { for (c in n) print n[c], c }' mac-out/appkit_gap.txt mac-out/appkit_api.txt | sort -rn | head -${TOP:-25}
fi
