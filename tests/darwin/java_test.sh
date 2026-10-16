#!/bin/bash
# OpenJDK (Homebrew openjdk bottle: tools/fetch_bottle.py openjdk) under xef-osx: java -version, javac of a program
# using collections, streams, a thread pool and MessageDigest, then running it (interpreter + JIT-compiled code);
# the output is fully determined by the program (no JDK on the test Mac to compare with). Skips (exit 0) when the JDK is missing.
cd "$(dirname "$0")/../.."
J=darwin-rootfs/opt/homebrew/opt/openjdk/bin
[ -e "$J/java" ] || { echo "SKIP java_test: $J/java not found"; exit 0; }
OUT=${TMPDIR:-/tmp}/xef-java-test; rm -rf "$OUT"; mkdir -p "$OUT"
X="$PWD/build/xef-osx -L $PWD/darwin-rootfs"
unset JAVA_TOOL_OPTIONS
v=$(timeout 300 $X /opt/homebrew/opt/openjdk/bin/java -version 2>&1)
case "$v" in *"OpenJDK 64-Bit Server VM"*) ;; *) echo "FAIL java_test (java -version: $v)"; exit 1;; esac
cat > "$OUT/Hello.java" <<'JV'
import java.util.*;
import java.util.stream.*;
import java.util.concurrent.*;
public class Hello {
    public static void main(String[] a) throws Exception {
        Map<String,Integer> m = new TreeMap<>();
        for (String w : "the quick brown fox jumps over the lazy dog the end".split(" ")) m.merge(w, 1, Integer::sum);
        System.out.println(m);
        ExecutorService ex = Executors.newFixedThreadPool(4);
        List<Future<Long>> fs = new ArrayList<>();
        for (int i = 0; i < 4; i++) { final int k = i; fs.add(ex.submit(() -> LongStream.range(0, 5_000_000).map(x -> x % (k + 2)).sum())); }
        for (Future<Long> f : fs) System.out.print(f.get() + " ");
        System.out.println();
        ex.shutdown();
        System.out.println(String.format("%.6f", IntStream.rangeClosed(1, 100000).mapToDouble(i -> 1.0 / ((double) i * i)).sum()));
        System.out.println(java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest("abc".getBytes())));
        System.out.println(System.getProperty("os.name") + " " + System.getProperty("os.arch"));
    }
}
JV
(cd "$OUT" && timeout 600 $X /opt/homebrew/opt/openjdk/bin/javac Hello.java > javac.log 2>&1) || { echo "FAIL java_test (javac)"; tail -5 "$OUT/javac.log"; exit 1; }
got=$(cd "$OUT" && timeout 600 $X /opt/homebrew/opt/openjdk/bin/java Hello 2>&1)
want='{brown=1, dog=1, end=1, fox=1, jumps=1, lazy=1, over=1, quick=1, the=3}
2500000 4999999 7500000 10000000 
1.644924
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
Mac OS X aarch64'
[ "$got" = "$want" ] && { echo "PASS java_test"; exit 0; }
echo "FAIL java_test (output: $got)"; exit 1
