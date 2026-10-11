#!/usr/bin/env python3
"""Fetch Debian packages (no root) and extract into a directory.
usage: fetch_debs.py <Packages.xz> <outdir> pkg1 pkg2 ..."""
import lzma, sys, os, subprocess, urllib.request
idx, out, pkgs = sys.argv[1], sys.argv[2], sys.argv[3:]
txt = lzma.open(idx, 'rt').read()
db = {}
for stanza in txt.split('\n\n'):
    d = {}
    for line in stanza.split('\n'):
        if ': ' in line and not line.startswith(' '):
            k, v = line.split(': ', 1); d[k] = v
    if 'Package' in d: db[d['Package']] = d
os.makedirs(out, exist_ok=True)
for p in pkgs:
    f = db[p]['Filename']
    deb = os.path.join(os.path.dirname(idx), os.path.basename(f))
    if not os.path.exists(deb):
        urllib.request.urlretrieve('https://deb.debian.org/debian/' + f, deb)
    tmp = deb + '.x'; os.makedirs(tmp, exist_ok=True)
    subprocess.check_call(['bsdtar', '-xf', deb, '-C', tmp])
    data = [x for x in os.listdir(tmp) if x.startswith('data.tar')][0]
    subprocess.check_call(['bsdtar', '-xf', os.path.join(tmp, data), '-C', out])
    print('ok', p, db[p]['Version'])
