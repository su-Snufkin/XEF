#!/usr/bin/env python3
"""usage: timeit.py [-n N] cmd args...  -- best-of-N wall time, output discarded"""
import subprocess, sys, time
n = 3
a = sys.argv[1:]
if a and a[0] == '-n':
    n = int(a[1]); a = a[2:]
ts = []
for _ in range(n):
    t = time.perf_counter()
    subprocess.run(a, stdout=subprocess.DEVNULL)
    ts.append(time.perf_counter() - t)
print('best %.3f  median %.3f  (%s)' % (min(ts), sorted(ts)[len(ts) // 2], ' '.join('%.3f' % x for x in ts)))
