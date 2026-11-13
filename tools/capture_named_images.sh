#!/bin/bash
# The system images behind the NSImageName* constants (NSImageNameInfo, NSImageNameFolder, ...): dumped from the user's Mac
# (tools/dump_named_images.m) into darwin-rootfs/System/Library/Frameworks/AppKit.framework/Resources/NamedImages (not committed).
set -e
cd "$(dirname "$0")/.."
D=darwin-rootfs/System/Library/Frameworks/AppKit.framework/Resources/NamedImages
scp -q tools/dump_named_images.m mac:xef-remote/dni.m
ssh mac 'cd xef-remote && clang -fobjc-arc -w -framework Cocoa dni.m -o dni && rm -rf namedimgs && ./dni namedimgs >/dev/null 2>&1'
mkdir -p $D && rsync -a --delete mac:xef-remote/namedimgs/ $D/
echo "named images: $(wc -l < $D/manifest.txt)"
