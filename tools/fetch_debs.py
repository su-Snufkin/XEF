#!/usr/bin/env python3
"""Fetch Debian/Ubuntu packages (no root) and extract into a directory.
usage: fetch_debs.py [--deps] <mirror-url> <outdir> <Packages.xz>[,<Packages.xz>...] pkg1 pkg2 ..
Later indexes override earlier ones (e.g. "noble,noble-updates").
--deps: also fetch (recursively) everything the packages Depend / Pre-Depend on."""
import lzma, sys, os, re, subprocess, urllib.request
args = sys.argv[1:]
deps = '--deps' in args
args = [a for a in args if a != '--deps']
base, out, idxs, pkgs = args[0].rstrip('/') + '/', args[1], args[2].split(','), args[3:]
db, provides = {}, {}
for idx in idxs:
    for stanza in lzma.open(idx, 'rt').read().split('\n\n'):
        d = {}
        for line in stanza.split('\n'):
            if ': ' in line and not line.startswith(' '):
                k, v = line.split(': ', 1); d[k] = v
        if 'Package' in d:
            db[d['Package']] = d
            for p in d.get('Provides', '').split(','):
                p = re.sub(r'\(.*?\)', '', p).strip()
                if p: provides.setdefault(p, d['Package'])
# packages a guest rootfs never needs (maintainer scripts, init system, shells we don't run)
SKIP = {'debconf', 'dpkg', 'init-system-helpers', 'systemd', 'libsystemd-shared', 'adduser', 'perl-base',
        'debianutils', 'ucf', 'sensible-utils', 'passwd', 'login', 'dconf-service', 'gsettings-backend',
        'install-info', 'mount', 'util-linux', 'procps', 'lsb-base', 'sysvinit-utils', 'systemd-sysv'}

def resolve(name):
    name = name.split(':')[0]
    if name in db: return name
    return provides.get(name)

order, seen = [], set()
def visit(p):
    p = resolve(p)
    if not p or p in seen: return
    seen.add(p)
    order.append(p)
    if not deps: return
    for field in ('Pre-Depends', 'Depends'):
        for alt in db[p].get(field, '').split(','):
            if not alt.strip(): continue
            for a in alt.split('|'):
                a = re.sub(r'\(.*?\)', '', a).strip()
                if a.split(':')[0] in SKIP: break
                if resolve(a): visit(a); break

for p in pkgs:
    if not resolve(p): sys.exit('unknown package ' + p)
    visit(p)

os.makedirs(out, exist_ok=True)
stamp = os.path.join(out, '.xef-packages')
done = set(open(stamp).read().split()) if os.path.exists(stamp) else set()
dl = os.path.dirname(idxs[0])
for p in order:
    if p in done: continue
    f = db[p]['Filename']
    deb = os.path.join(dl, os.path.basename(f))
    if not os.path.exists(deb):
        urllib.request.urlretrieve(base + f, deb)
    tmp = deb + '.x'; os.makedirs(tmp, exist_ok=True)
    subprocess.check_call(['bsdtar', '-xf', deb, '-C', tmp])
    data = [x for x in os.listdir(tmp) if x.startswith('data.tar')][0]
    subprocess.check_call(['bsdtar', '-xf', os.path.join(tmp, data), '-C', out])
    with open(stamp, 'a') as s: s.write(p + '\n')
    print('ok', p, db[p]['Version'])
