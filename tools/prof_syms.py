#!/usr/bin/env python3
"""Guest functions by samples from /tmp/xef-prof-guest.txt (written by `xef --profile`).

usage: tools/prof_syms.py [ROOTFS] [N]   (paths in the file are host paths; ROOTFS unused then)
Symbolizes "samples file offset" lines with llvm-symbolizer (file offsets of PIC libraries are
their virtual addresses for the usual layouts) and sums samples per function.
"""
import collections, subprocess, sys
n = int(sys.argv[2]) if len(sys.argv) > 2 else 30
rows = [l.split() for l in open('/tmp/xef-prof-guest.txt')]
total = sum(int(r[0]) for r in rows) or 1
by_file = collections.defaultdict(list)
for c, path, off in rows:
    by_file[path].append((int(c), int(off, 16)))
funcs = collections.Counter()
for path, items in by_file.items():
    if not path.startswith('/'):
        for c, off in items: funcs['%s+%#x' % (path, off)] += c
        continue
    q = '\n'.join('%#x' % off for c, off in items) + '\n'
    out = subprocess.run(['llvm-symbolizer', '--obj=' + path, '--functions=linkage', '--no-inlines'],
                         input=q, capture_output=True, text=True).stdout.split('\n\n')
    for (c, off), o in zip(items, out):
        name = o.strip().split('\n')[0] if o.strip() else '??'
        if name == '??': name = '%s+%#x' % (path.rsplit('/', 1)[-1], off)
        funcs[path.rsplit('/', 1)[-1] + ': ' + name] += c
for name, c in funcs.most_common(n):
    print('%5.1f%%  %s' % (100.0 * c / total, name))
