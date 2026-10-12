#!/bin/sh
# Node.js (V8 JIT) under XEF (needs `tools/mkrootfs.sh nodejs` and a host node): same output.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
exp=$(node $ROOT/tests/node/test.js 2>&1)
got=$($ROOT/build/xef -L $ROOT/.tools/rootfs-arm64 /usr/bin/node $ROOT/tests/node/test.js 2>&1)
if [ "$exp" = "$got" ]; then echo "node tests: 1 passed, 0 failed"; else echo "FAIL node"; echo "$got"; exit 1; fi
