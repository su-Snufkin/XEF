#!/bin/bash
# Re-checks on the Mac that no selector in tools/appkit_exempt.txt is implemented by macOS (so excluding it from the API gap is right).
cd "$(dirname "$0")/.."
grep -v '^#' tools/appkit_exempt.txt > /tmp/exempt_sel.txt
scp -q tools/verify_exempt.m /tmp/exempt_sel.txt mac:xef-remote/
ssh mac 'cd xef-remote && clang -fobjc-arc -w -framework Cocoa verify_exempt.m -o verify_exempt && ./verify_exempt exempt_sel.txt' | grep -v '^20'
