#!/bin/bash
# Deno (Homebrew deno bottle: tools/fetch_bottle.py deno) under xef-osx: a TypeScript program (transpiled by swc)
# using Map, WebCrypto, file I/O, an HTTP server + fetch over loopback and a subprocess. The output is fully
# determined by the program. Skips (exit 0) when deno is missing.
cd "$(dirname "$0")/../.."
D=darwin-rootfs/opt/homebrew/bin/deno
[ -e "$D" ] || { echo "SKIP deno_test: $D not found"; exit 0; }
OUT=${TMPDIR:-/tmp}/xef-deno-test; rm -rf "$OUT"; mkdir -p "$OUT"
X="$PWD/build/xef-osx -L $PWD/darwin-rootfs"
cat > "$OUT/t.ts" <<'TS'
const m = new Map<string, number>();
for (const w of "the quick brown fox jumps over the lazy dog the end".split(" ")) m.set(w, (m.get(w) ?? 0) + 1);
console.log([...m.entries()].sort().map(([k, v]) => `${k}=${v}`).join(","));
const h = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode("abc")));
console.log(Array.from(h).map((b) => b.toString(16).padStart(2, "0")).join(""));
const f = Deno.makeTempFileSync();
await Deno.writeTextFile(f, "hello deno");
console.log(await Deno.readTextFile(f));
Deno.removeSync(f);
const s = Deno.serve({ port: 18083, hostname: "127.0.0.1", onListen() {} }, () => new Response("hi from deno"));
const r = await fetch("http://127.0.0.1:18083/");
console.log(r.status, await r.text());
await s.shutdown();
const p = new Deno.Command("/bin/sh", { args: ["-c", "echo child ok"] }).outputSync();
console.log(new TextDecoder().decode(p.stdout).trim());
console.log(Deno.build.os, Deno.build.arch);
TS
got=$(cd "$OUT" && DENO_DIR="$OUT/cache" NO_COLOR=1 timeout 600 $X /opt/homebrew/bin/deno run -A t.ts 2>&1)
want='brown=1,dog=1,end=1,fox=1,jumps=1,lazy=1,over=1,quick=1,the=3
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
hello deno
200 hi from deno
child ok
darwin aarch64'
[ "$got" = "$want" ] && { echo "PASS deno_test"; exit 0; }
echo "FAIL deno_test (output: $got)"; exit 1
