#!/usr/bin/env python3
"""Fetch Debian/Ubuntu packages (no root) and extract into a directory.
usage: fetch_debs.py <mirror-url> <outdir> <Packages.xz>[,<Packages.xz>...] pkg1 pkg2 ..
Later indexes override earlier ones (e.g. "noble,noble-updates")."""
import lzma, sys, os, subprocess, urllib.request
base, out, idxs, pkgs = sys.argv[1].rstrip('/') + '/', sys.argv[2], sys.argv[3].split(','), sys.argv[4:]
db = {}
for idx in idxs:
    for stanza in lzma.open(idx, 'rt').read().split('\n\n'):
        d = {}
        for line in stanza.split('\n'):
            if ': ' in line and not line.startswith(' '):
                k, v = line.split(': ', 1); d[k] = v
        if 'Package' in d: db[d['Package']] = d
os.makedirs(out, exist_ok=True)
dl = os.path.dirname(idxs[0])
for p in pkgs:
    f = db[p]['Filename']
    deb = os.path.join(dl, os.path.basename(f))
    if not os.path.exists(deb):
        urllib.request.urlretrieve(base + f, deb)
    tmp = deb + '.x'; os.makedirs(tmp, exist_ok=True)
    subprocess.check_call(['bsdtar', '-xf', deb, '-C', tmp])
    data = [x for x in os.listdir(tmp) if x.startswith('data.tar')][0]
    subprocess.check_call(['bsdtar', '-xf', os.path.join(tmp, data), '-C', out])
    print('ok', p, db[p]['Version'])
