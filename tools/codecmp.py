#!/usr/bin/env python3
"""Checks that two XEF builds generate the same host code for a guest run.

usage: tools/codecmp.py XEF_A XEF_B -- [xef options] guest-program args...

Runs the program under each build with ASLR off, --no-tier2 and --dump-code (every block's code
lands in /tmp/xef-<pc>.bin) and compares the blocks present in both runs. Differences that are
only addresses are ignored: 8-byte immediates pointing into the xef image (C helper addresses
move when xef itself changes) and rel32 fields of jmp/call/jcc (a block placed elsewhere in the
code cache). Use it to check that a translator change meant to be code-neutral is. Runs must be
deterministic (e.g. PYTHONHASHSEED=0 for Python; guest JITs and threads are not).
"""
import glob, os, shutil, struct, subprocess, sys, tempfile

def dump(xef, args, out):
    for f in glob.glob('/tmp/xef-*.bin'):
        os.remove(f)
    subprocess.run(['setarch', 'x86_64', '-R', xef, '--no-tier2', '--dump-code'] + args,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for f in glob.glob('/tmp/xef-*.bin'):
        shutil.move(f, os.path.join(out, os.path.basename(f)))

def rel32(x, i):   # byte i inside the rel32 field of a jmp/call (E9/E8) or jcc (0F 8x)
    for s in range(max(0, i - 4), i):
        if s + 5 <= len(x) and x[s] in (0xE8, 0xE9) and s + 1 <= i < s + 5:
            return True
        if s >= 1 and s + 5 <= len(x) and x[s - 1] == 0x0F and 0x80 <= x[s] <= 0x8F and s + 1 <= i < s + 5:
            return True
    return False

def xef_imm(a, b, i, lo, hi):   # byte i inside an 8-byte value pointing into the xef image in both
    return any(0 <= s and s + 8 <= len(a) and lo <= struct.unpack_from('<Q', a, s)[0] < hi
               and lo <= struct.unpack_from('<Q', b, s)[0] < hi for s in range(i - 7, i + 1))

def main():
    if len(sys.argv) < 5 or sys.argv[3] != '--':
        sys.exit(__doc__)
    xa, xb, args = sys.argv[1], sys.argv[2], sys.argv[4:]
    lo, hi = 0x555555554000, 0x555556000000   # where a PIE xef is mapped without ASLR
    with tempfile.TemporaryDirectory() as tmp:
        da, db = os.path.join(tmp, 'a'), os.path.join(tmp, 'b')
        os.mkdir(da)
        os.mkdir(db)
        dump(xa, args, da)
        dump(xb, args, db)
        fa, fb = set(os.listdir(da)), set(os.listdir(db))
        bad = []
        for f in sorted(fa & fb):
            a = open(os.path.join(da, f), 'rb').read()
            b = open(os.path.join(db, f), 'rb').read()
            if a == b:
                continue
            if len(a) != len(b) or any(a[i] != b[i] and not (rel32(a, i) and rel32(b, i)) and not xef_imm(a, b, i, lo, hi)
                                       for i in range(len(a))):
                bad.append(f)
    print('blocks: %d / %d, in one run only: %d, different code: %d %s' %
          (len(fa), len(fb), len(fa ^ fb), len(bad), ' '.join(bad[:8])))
    sys.exit(1 if bad else 0)

if __name__ == '__main__':
    main()
