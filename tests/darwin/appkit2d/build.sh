#!/bin/bash
# Builds the AppKit 2D drawing test on the remote Mac (tools/ conventions: ssh mac).
set -e
cd "$(dirname "$0")"
ssh mac 'mkdir -p ~/xef-remote/src/appkit2d'
rsync -a appkit2d.m mac:xef-remote/src/appkit2d/
ssh mac 'cd ~/xef-remote/src/appkit2d && clang -arch arm64 -mmacosx-version-min=12.0 -fobjc-arc -framework Cocoa appkit2d.m -o appkit2d'
scp -q mac:xef-remote/src/appkit2d/appkit2d .
