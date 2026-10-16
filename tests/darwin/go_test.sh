#!/bin/bash
# Go toolchain (Homebrew go, tools/pull_homebrew.sh go) under xef-osx: `go version` started by its host path inside
# the rootfs, then a cold-cache `go build` (go spawns compile/asm/link, all Mach-O) of a program using goroutines,
# encoding/json and crypto/sha256; the built binary must print what it prints on the Mac.
# Skips (exit 0) when darwin-rootfs/opt/homebrew/bin/go is missing.
cd "$(dirname "$0")/../.."
GO=darwin-rootfs/opt/homebrew/bin/go
[ -e "$GO" ] || { echo "SKIP go_test: $GO not found"; exit 0; }
OUT=${TMPDIR:-/tmp}/xef-go-test; rm -rf "$OUT"; mkdir -p "$OUT/src"
X="$PWD/build/xef-osx -L $PWD/darwin-rootfs"
v=$(HOME=/root timeout 120 $X "$PWD/$GO" version) || { echo "FAIL go_test (go version rc=$?)"; exit 1; }
case "$v" in "go version go"*" darwin/arm64") ;; *) echo "FAIL go_test (go version: $v)"; exit 1;; esac
cat > "$OUT/src/go.mod" <<'G'
module hello
go 1.21
G
cat > "$OUT/src/main.go" <<'G'
package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"runtime"
	"sync"
)

func main() {
	var wg sync.WaitGroup
	res := make([]int, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func(i int) { defer wg.Done(); s := 0; for j := 0; j < 1000000; j++ { s += j % (i + 1) }; res[i] = s }(i)
	}
	wg.Wait()
	b, _ := json.Marshal(map[string]any{"res": res, "os": runtime.GOOS, "arch": runtime.GOARCH})
	fmt.Println(string(b))
	fmt.Printf("%x\n", sha256.Sum256([]byte("abc")))
}
G
(cd "$OUT/src" && GOCACHE="$OUT/cache" HOME=/root timeout 1800 $X /opt/homebrew/bin/go build -o hello . > "$OUT/build.log" 2>&1) \
  || { echo "FAIL go_test (go build, see $OUT/build.log)"; tail -5 "$OUT/build.log"; exit 1; }
got=$(timeout 60 $X "$OUT/src/hello")
want='{"arch":"arm64","os":"darwin","res":[0,500000,999999,1500000,2000000,2499996,2999997,3500000]}
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
[ "$got" = "$want" ] && { echo "PASS go_test"; exit 0; }
echo "FAIL go_test (output: $got)"; exit 1
