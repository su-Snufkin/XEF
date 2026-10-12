#!/bin/sh
# OpenJDK under XEF (needs `tools/mkrootfs.sh openjdk-21-jre` and a host javac): compares the
# output of Bench.java with the host JVM. SwingDemo.java is a GUI check (DISPLAY needed).
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
R=$ROOT/.tools/rootfs-arm64
OUT=/tmp/xef_java; mkdir -p $OUT
javac -d $OUT $ROOT/tests/java/Bench.java || exit 1
exp=$(java -cp $OUT Bench 2>/dev/null | grep -v '^ms ')
got=$($ROOT/build/xef -L $R /usr/lib/jvm/java-21-openjdk-arm64/bin/java -cp $OUT Bench 2>/dev/null | grep -v '^ms ')
if [ "$exp" = "$got" ]; then echo "java tests: 1 passed, 0 failed"; else echo "FAIL Bench"; echo "$got"; exit 1; fi
