#!/usr/bin/env python3
"""A/B timing: ab.py BIN_A BIN_B -- guest args...   (interleaved runs, best-of-N; user+sys CPU time)"""
import os, resource, subprocess, sys
n = int(os.environ.get('N', '7'))
i = sys.argv.index('--')
bins, rest = sys.argv[1:i], sys.argv[i + 1:]
res = {b: [] for b in bins}
for _ in range(n):
    for b in bins:
        r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
        subprocess.run([b] + rest, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
        res[b].append((r1.ru_utime - r0.ru_utime) + (r1.ru_stime - r0.ru_stime))
for b in bins:
    v = sorted(res[b])
    print('%-40s min %.3f  med %.3f' % (b[-40:], v[0], v[len(v) // 2]))
