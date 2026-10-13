#!/usr/bin/env python3
"""Annotated disassembly of the hottest blocks from `xef --profile` (/tmp/xef-hotN.*).

usage: tools/annotate_hot.py [N...]     (default: 0 1 2 3 4)
Each host instruction is prefixed with the share of the block's samples that landed on it
(the sampled RIP is the next instruction to execute, so cost shows up one instruction late).
"""
import os, re, subprocess, sys

def annotate(i):
    host, counts = '/tmp/xef-hot%d.host' % i, '/tmp/xef-hot%d.counts' % i
    if not os.path.exists(host) or not os.path.exists(counts):
        return
    hdr, cnt = '', {}
    for line in open(counts):
        if line.startswith('#'):
            hdr = line[1:].strip()
            continue
        o, c = line.split()
        cnt[int(o)] = int(c)
    total = sum(cnt.values()) or 1
    print('=== hot%d: %s, %d samples' % (i, hdr, total))
    out = subprocess.run(['objdump', '-D', '-b', 'binary', '-mi386:x86-64', '-M', 'intel', host],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        m = re.match(r'\s*([0-9a-f]+):\t[0-9a-f ]+\t(.*)', line)
        if not m:
            continue
        off = int(m.group(1), 16)
        c = cnt.get(off, 0)
        print('%6s %5x  %s' % ('%.1f%%' % (100.0 * c / total) if c else '', off, m.group(2)))

for a in (sys.argv[1:] or ['0', '1', '2', '3', '4']):
    annotate(int(a))
