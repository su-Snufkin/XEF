#!/bin/bash
# Builds the AppKit control gallery on the remote Mac (ssh mac) and copies the binary here (gallery).
set -e
cd "$(dirname "$0")"
ssh mac 'mkdir -p ~/xef-remote/src/appkit_gallery'
scp -q gallery.m mac:xef-remote/src/appkit_gallery/
ssh mac 'cd ~/xef-remote/src/appkit_gallery && clang -arch arm64 -mmacosx-version-min=12.0 -fobjc-arc -w -framework Cocoa gallery.m -o appkit_gallery'
scp -q mac:xef-remote/src/appkit_gallery/appkit_gallery gallery
