#!/usr/bin/env python3
"""Tiny parallel compile driver used on the remote Mac to build Apple open-source libraries outside Xcode.

  xbuild.py --out DIR --cflags '...' [--cxxflags '...'] [--jobs 8] SOURCES...

Compiles every .c/.m/.cpp/.mm/.s/.S source to DIR/<name>.o, prints the first lines of each failure and
exits non-zero when anything failed.  Object names are made unique from the source path."""
import argparse, os, subprocess, sys, shlex, hashlib
from concurrent.futures import ThreadPoolExecutor

ap = argparse.ArgumentParser()
ap.add_argument('--out', required=True)
ap.add_argument('--cflags', default='')
ap.add_argument('--cxxflags', default='')
ap.add_argument('--sflags', default=None)
ap.add_argument('--jobs', type=int, default=8)
ap.add_argument('--keep-going', action='store_true')
ap.add_argument('srcs', nargs='+')
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)

cmd_of = {}

def compile_one(src):
    base = os.path.basename(src)
    h = hashlib.md5(os.path.abspath(src).encode()).hexdigest()[:6]
    obj = os.path.join(a.out, '%s.%s.o' % (base, h))
    ext = os.path.splitext(src)[1]
    if ext in ('.c', '.m'):
        cmd = ['clang'] + shlex.split(a.cflags) + ['-c', src, '-o', obj]
    elif ext in ('.cpp', '.mm', '.cc'):
        cmd = ['clang++'] + shlex.split(a.cxxflags or a.cflags) + ['-c', src, '-o', obj]
    else:
        cmd = ['clang'] + shlex.split(a.sflags if a.sflags is not None else a.cflags) + ['-c', src, '-o', obj]
    cmd_of[src] = cmd
    r = subprocess.run(cmd, capture_output=True, text=True)
    return src, obj, r.returncode, r.stderr

fails = 0
with ThreadPoolExecutor(a.jobs) as ex:
    for src, obj, rc, err in ex.map(compile_one, a.srcs):
        if rc:
            fails += 1
            lines = [l for l in err.splitlines() if 'error' in l or 'fatal' in l]
            print('FAIL %s' % src)
            if os.environ.get('XBUILD_VERBOSE'): print('   CMD: ' + ' '.join(shlex.quote(c) for c in cmd_of[src]))
            for l in lines[:4]:
                print('   ' + l)
print('compiled %d, failed %d' % (len(a.srcs) - fails, fails))
sys.exit(1 if fails else 0)
