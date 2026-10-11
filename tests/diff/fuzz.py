#!/usr/bin/env python3
"""Differential instruction fuzzer: XEF vs qemu-aarch64.

Generates random A64 encodings (data-processing / SIMD&FP), keeps the ones
llvm-mc decodes as valid and register-safe, runs them through tests/diff/runner
under qemu and XEF and reports differing register state.

usage: fuzz.py [-n COUNT] [--seed S] [--class int|simd|fp|all] [--grep REGEX]
"""
import argparse, os, random, re, struct, subprocess, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
QEMU = os.path.join(ROOT, '.tools/qemu/usr/bin/qemu-aarch64')
XEF = os.environ.get('XEF', os.path.join(ROOT, 'build/xef'))
RUNNER = os.environ.get('RUNNER', '/tmp/runner')
MATTR = '+neon,+crc,+aes,+sha2,+lse,+rcpc'

BAD = re.compile(r'\b(x28|x29|x30|w28|w29|w30|sp|wsp|fpcr|fpsr|nzcv)\b|\[|^\s*(b|bl|br|blr|ret|cbn?z|tbn?z|svc|hvc|smc|brk|hlt|'
                 r'hint|msr|mrs|sys|sysl|dmb|dsb|isb|clrex|nop|yield|wfe|wfi|sev|udf|b\.\w+|bti|pac\w*|aut\w*|xpac\w*|'
                 r'eret\w*|drps|dcps\d|tbl|tbx|ld\w+|st\w+|prfm|casp?\w*|swp\w*|cfinv|rmif|setf\w+|axflag|xaflag|'
                 r'sha\w+|adrp?)\b')

def gen_candidates(rng, n, cls):
    out = []
    for _ in range(n):
        w = rng.getrandbits(32)
        c = cls if cls != 'all' else rng.choice(['int', 'int', 'simd', 'simd', 'fp'])
        if c == 'int':
            # op0 = 100x (dp imm) or x101 (dp reg)
            if rng.random() < 0.4:
                w = (w & ~(0xE << 25)) | (0x8 << 25)
            else:
                w = (w & ~(0x7 << 25)) | (0x5 << 25)
        elif c == 'simd':
            w = (w & ~(0x7 << 25)) | (0x7 << 25)
            w &= ~(1 << 31)
        else:  # scalar fp: bits 28:24 = 11110, bit 30=0, 29=0, 31 either
            w = (w & ~(0x1F << 24)) | (0x1E << 24)
            w &= ~(3 << 29)
        # bias register fields away from 28..31 most of the time
        for sh in (0, 5, 16, 10):
            if rng.random() < 0.85:
                r = rng.randrange(28)
                w = (w & ~(0x1F << sh)) | (r << sh)
        out.append(w & 0xffffffff)
    return out

def disasm(words):
    data = ' '.join('0x%02x 0x%02x 0x%02x 0x%02x' % tuple(struct.pack('<I', w)) for w in words)
    p = subprocess.run(['llvm-mc', '--disassemble', '-triple=aarch64', '-mattr=' + MATTR],
                       input=data, capture_output=True, text=True)
    lines = [l.strip() for l in p.stdout.splitlines() if l.strip() and not l.strip().startswith('.text')]
    # llvm-mc emits warnings for invalid encodings on stderr and skips them; re-run individually is slow,
    # so decode in a way that keeps alignment: use one instruction per call when counts mismatch.
    if len(lines) == len(words):
        return lines
    res = []
    for w in words:
        d = ' '.join('0x%02x' % b for b in struct.pack('<I', w))
        p = subprocess.run(['llvm-mc', '--disassemble', '-triple=aarch64', '-mattr=' + MATTR],
                           input=d, capture_output=True, text=True)
        l = [x.strip() for x in p.stdout.splitlines() if x.strip() and not x.strip().startswith('.text')]
        res.append(l[0] if l and 'invalid' not in p.stderr else None)
    return res

def disasm_batch(words, chunk=400):
    res = []
    for i in range(0, len(words), chunk):
        res.extend(disasm(words[i:i + chunk]))
    return res

def run(cmd, start=0):
    p = subprocess.run(cmd + [str(start)], capture_output=True, text=True)
    return p.stdout, p.stderr, p.returncode

def parse(out):
    res = {}
    for line in out.splitlines():
        f = line.split()
        if not f or not f[0].isdigit():
            continue
        res[int(f[0])] = f[1:]
    return res

def _nan32(x): return (x & 0x7f800000) == 0x7f800000 and (x & 0x7fffff) != 0
def _nan64(x): return (x & 0x7ff0000000000000) == 0x7ff0000000000000 and (x & 0xfffffffffffff) != 0

def nan_equiv(a, b):
    """True if two V-register values differ only in NaN sign/payload."""
    if ':' not in a:
        return False
    for ha, hb in zip(a.split(':'), b.split(':')):
        x, y = int(ha, 16), int(hb, 16)
        if x == y or (_nan64(x) and _nan64(y)):
            continue
        for sh in (0, 32):
            lx, ly = (x >> sh) & 0xffffffff, (y >> sh) & 0xffffffff
            if lx != ly and not (_nan32(lx) and _nan32(ly)):
                return False
    return True

NAMES = ['x%d' % i for i in range(28)] + ['nzcv'] + ['v%d' % i for i in range(32)]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-n', type=int, default=3000)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--class', dest='cls', default='all')
    ap.add_argument('--grep', default=None)
    ap.add_argument('--show', type=int, default=25)
    ap.add_argument('--strict-nan', action='store_true')
    ap.add_argument('--tmpl', action='append', help='VALUE:FIXEDMASK (hex); other bits random')
    args = ap.parse_args()
    rng = random.Random(args.seed)
    if args.tmpl:
        cands = []
        for t in args.tmpl:
            val, mask = (int(x, 16) for x in t.split(':'))
            for _ in range(args.n * 2 // len(args.tmpl)):
                w = (rng.getrandbits(32) & ~mask) | (val & mask)
                for sh in (0, 5, 16):
                    if not (mask >> sh) & 0x1f and rng.random() < 0.9:
                        w = (w & ~(0x1f << sh)) | (rng.randrange(28) << sh)
                cands.append(w)
    else:
        cands = gen_candidates(rng, args.n * 4, args.cls)
    dis = disasm_batch(cands)
    tests = []
    for w, d in zip(cands, dis):
        if not d or BAD.search(d):
            continue
        if args.grep and not re.search(args.grep, d):
            continue
        tests.append((w, d))
        if len(tests) >= args.n:
            break
    path = '/tmp/xef_fuzz_tests.bin'
    with open(path, 'wb') as f:
        for w, _ in tests:
            f.write(struct.pack('<I', w))
    print('%d tests' % len(tests))
    ref = {}
    start = 0
    while start < len(tests):
        out, err, rc = run([QEMU, RUNNER, path], start)
        part = parse(out)
        ref.update(part)
        if rc == 0:
            break
        start = (max(part.keys()) if part else start - 1) + 2   # skip the encoding qemu rejects
    got = {}
    unsupported = collections.Counter()
    start = 0
    while start < len(tests):
        out, err, rc = run([XEF, RUNNER, path], start)
        part = parse(out)
        got.update(part)
        if rc == 0:
            break
        last = max(part.keys()) if part else start - 1
        fail = last + 1
        m = re.search(r'unsupported instruction at (\S+): ([0-9a-f]+)', err)
        if m:
            mn = tests[fail][1].split()[0] if fail < len(tests) else '?'
            unsupported[mn] += 1
        elif fail in ref or fail >= len(tests):
            print('XEF crashed at test %d (%s): %s' % (fail, tests[fail][1] if fail < len(tests) else '?', err.strip()[:300]))
        start = fail + 1
    mism = collections.Counter()
    shown = 0
    nok = 0
    nan_only = 0
    for i, (w, d) in enumerate(tests):
        if i not in ref or i not in got:
            continue
        if ref[i] == got[i]:
            nok += 1
            continue
        if not args.strict_nan and all(r == g or nan_equiv(r, g) for r, g in zip(ref[i], got[i])):
            nan_only += 1
            continue
        mn = d.split()[0]
        mism[mn] += 1
        if shown < args.show:
            shown += 1
            diffs = ['%s: qemu=%s xef=%s' % (NAMES[k], ref[i][k], got[i][k]) for k in range(len(ref[i])) if ref[i][k] != got[i][k]]
            print('MISMATCH #%d %08x  %-40s %s' % (i, w, d, '; '.join(diffs[:4])))
    print('ok=%d nan-sign/payload-only=%d mismatched=%d unsupported=%d' % (nok, nan_only, sum(mism.values()), sum(unsupported.values())))
    if mism:
        print('mismatch by mnemonic:', ', '.join('%s:%d' % kv for kv in mism.most_common(40)))
    if unsupported:
        print('unsupported by mnemonic:', ', '.join('%s:%d' % kv for kv in unsupported.most_common(40)))

if __name__ == '__main__':
    main()
