#!/bin/bash
# Copies a Homebrew arm64 binary from the remote Mac together with all its non-system dylibs (recursively,
# preserving /opt/homebrew paths) into ./darwin-rootfs, so that it can be run with:
#   build/xef-osx -L darwin-rootfs darwin-rootfs/opt/homebrew/bin/<name> ...
# (only files on the user's own Mac, for personal testing)
set -e
cd "$(dirname "$0")/.."
name=$1
[ -n "$name" ] || { echo "usage: $0 <binary-name or absolute path on the Mac>"; exit 1; }
list=$(ssh mac "python3 - '$name'" <<'PY'
import subprocess, sys, os
start = sys.argv[1]
if not start.startswith('/'):
    start = '/opt/homebrew/bin/' + start
seen, todo, out = set(), [start], []
while todo:
    p = todo.pop()
    real = os.path.realpath(p)
    if real in seen: continue
    seen.add(real); out.append((p, real))
    try:
        txt = subprocess.run(['otool', '-L', real], capture_output=True, text=True).stdout.splitlines()[1:]
    except Exception: continue
    rpaths = []
    try:
        lc = subprocess.run(['otool', '-l', real], capture_output=True, text=True).stdout.splitlines()
        for i, l in enumerate(lc):
            if 'cmd LC_RPATH' in l: rpaths.append(lc[i + 2].split('path ')[1].split(' (offset')[0])
    except Exception: pass
    for l in txt:
        d = l.strip().split(' (')[0]
        if d.startswith(('/usr/lib/', '/System/')): continue
        if d.startswith('@rpath/'):
            for rp in rpaths:
                rp = rp.replace('@loader_path', os.path.dirname(real)).replace('@executable_path', os.path.dirname(real))
                c = os.path.join(rp, d[7:])
                if os.path.exists(c): d = c; break
            else: continue
        elif d.startswith(('@loader_path/', '@executable_path/')):
            d = os.path.join(os.path.dirname(real), d.split('/', 1)[1])
        if os.path.exists(d): todo.append(d)
for p, real in out: print(p + '\t' + real)
PY
)
echo "$list" | while IFS=$'\t' read -r p real; do
  mkdir -p "darwin-rootfs$(dirname "$real")"
  [ -L "darwin-rootfs$real" ] && rm -f "darwin-rootfs$real"
  rsync -aL "mac:$real" "darwin-rootfs$real"
  # keep the path used in load commands (symlinked names) as symlinks to the real file
  # (skip when the local path already leads to the copied file, e.g. opt/<keg> is a symlink into Cellar:
  #  ln would replace the file with a link to itself)
  if [ "$p" != "$real" ] && [ "$(realpath -m "darwin-rootfs$p")" != "$(realpath -m "darwin-rootfs$real")" ]; then
    mkdir -p "darwin-rootfs$(dirname "$p")"; ln -srfn "darwin-rootfs$real" "darwin-rootfs$p" 2>/dev/null || true; fi
done
# opt/<formula> -> ../Cellar/<formula>/<version>, as brew links it (programs locate themselves through it:
# python's sys.executable is /opt/homebrew/opt/python@3.14/bin/python3.14); an existing opt/<formula> is left alone
echo "$list" | cut -f2 | sed -n 's|^/opt/homebrew/Cellar/\([^/]*\)/\([^/]*\)/.*|\1 \2|p' | sort -u | while read -r f v; do
  [ -e "darwin-rootfs/opt/homebrew/opt/$f" ] || [ -L "darwin-rootfs/opt/homebrew/opt/$f" ] && continue
  mkdir -p darwin-rootfs/opt/homebrew/opt
  ln -s "../Cellar/$f/$v" "darwin-rootfs/opt/homebrew/opt/$f"
done
echo "$list" | wc -l | xargs echo "files copied:"
