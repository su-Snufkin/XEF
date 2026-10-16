#!/bin/bash
# Bun (Homebrew bun bottle: tools/fetch_bottle.py bun) under xef-osx: a TypeScript program using Map,
# Bun.CryptoHasher, Bun.write/Bun.file, Bun.serve + fetch over loopback, Bun.spawnSync and node:fs. The output is
# fully determined by the program. Skips (exit 0) when bun is missing.
cd "$(dirname "$0")/../.."
B=darwin-rootfs/opt/homebrew/bin/bun
[ -e "$B" ] || { echo "SKIP bun_test: $B not found"; exit 0; }
OUT=${TMPDIR:-/tmp}/xef-bun-test; rm -rf "$OUT"; mkdir -p "$OUT"
X="$PWD/build/xef-osx -L $PWD/darwin-rootfs"
cat > "$OUT/t.ts" <<'TS'
const m = new Map<string, number>();
for (const w of "the quick brown fox jumps over the lazy dog the end".split(" ")) m.set(w, (m.get(w) ?? 0) + 1);
console.log([...m.entries()].sort().map(([k, v]) => `${k}=${v}`).join(","));
console.log(new Bun.CryptoHasher("sha256").update("abc").digest("hex"));
const f = `${import.meta.dir}/x.txt`;
await Bun.write(f, "hello bun");
console.log(await Bun.file(f).text());
const server = Bun.serve({ port: 18085, hostname: "127.0.0.1", fetch() { return new Response("hi from bun"); } });
const r = await fetch("http://127.0.0.1:18085/");
console.log(r.status, await r.text());
server.stop(true);
console.log(Bun.spawnSync(["/bin/sh", "-c", "echo child ok"]).stdout.toString().trim());
const { readdirSync } = require("fs");
console.log(readdirSync(import.meta.dir).sort().join(","));
console.log(process.platform, process.arch);
TS
got=$(cd "$OUT" && NO_COLOR=1 timeout 600 $X /opt/homebrew/bin/bun run t.ts 2>&1)
want='brown=1,dog=1,end=1,fox=1,jumps=1,lazy=1,over=1,quick=1,the=3
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
hello bun
200 hi from bun
child ok
t.ts,x.txt
darwin arm64'
[ "$got" = "$want" ] && { echo "PASS bun_test"; exit 0; }
echo "FAIL bun_test (output: $got)"; exit 1
