#!/usr/bin/env python3
"""Runs the benchmark suite natively (x86-64), under XEF and under qemu-aarch64
and writes docs/benchmarks.md.

usage: bench/run.py [--reps N] [--only name,...] [--no-qemu] [--label TEXT]
"""
import argparse, datetime, os, platform, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(ROOT, 'bench/bin')
XEF = os.path.join(ROOT, 'build/xef')
QEMU = os.path.join(ROOT, '.tools/qemu/usr/bin/qemu-aarch64')
DATA = '/tmp/xef_bench_data'

def make_data():
    if os.path.exists(DATA) and os.path.getsize(DATA) == 48_000_000:
        return
    import random
    rng = random.Random(7)
    letters = 'etaoinshrdlcumwfgypbvkjxqz'
    vocab = [''.join(rng.choice(letters[:rng.randint(8, 26)]) for _ in range(rng.randint(2, 11))) for _ in range(20000)]
    weights = [1.0 / (i + 1) for i in range(len(vocab))]
    parts = []
    size = 0
    while size < 48_000_000:
        words = rng.choices(vocab, weights=weights, k=4096)
        line = ' '.join(words) + ' %d %x\n' % (rng.randrange(10**9), rng.getrandbits(48))
        parts.append(line)
        size += len(line)
    open(DATA, 'wb').write(''.join(parts).encode()[:48_000_000])
    subprocess.run([os.path.join(BIN, 'native/zstd'), '-q', '-f', '-6', DATA, '-o', DATA + '.zst'], check=True)

BENCHES = [
    ('coremark', ['coremark', '0x0', '0x0', '0x66', '200000'], 'CoreMark (200k iterations)'),
    ('intloop', ['intloop'], 'integer loops (sieve, hash, counting)'),
    ('fploop', ['fploop'], 'FP loops (matmul, n-body, mandelbrot)'),
    ('calls', ['calls'], 'calls + indirect branches (fib, fn pointers, interpreter)'),
    ('simd', ['simd'], 'auto-vectorized NEON loops (saxpy, dot, u8 blend, s16 saturate, SAD, clamp, cvt)'),
    ('zstd-c', ['zstd', '-q', '-6', '-c', DATA], 'zstd -6 compress 48 MB text'),
    ('zstd-d', ['zstd', '-q', '-d', '-c', DATA + '.zst'], 'zstd decompress 48 MB text'),
]

PIN = ['taskset', '-c', '2,3'] if os.path.exists('/usr/bin/taskset') else []

def timeit(cmd, reps, timeout):
    cmd = PIN + cmd
    best = None
    for _ in range(reps):
        t0 = time.perf_counter()
        try:
            p = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=timeout)
        except subprocess.TimeoutExpired:
            return None, 'timeout'
        dt = time.perf_counter() - t0
        if p.returncode != 0:
            return None, p.stderr.decode(errors='replace').strip()[-200:]
        best = dt if best is None else min(best, dt)
    return best, None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--reps', type=int, default=5)
    ap.add_argument('--only', default=None)
    ap.add_argument('--no-qemu', action='store_true')
    ap.add_argument('--label', default='')
    args = ap.parse_args()
    make_data()
    rows = []
    for name, cmd, desc in BENCHES:
        if args.only and name not in args.only.split(','):
            continue
        exe = cmd[0]
        nat, e1 = timeit([os.path.join(BIN, 'native', exe)] + cmd[1:], args.reps, 600)
        xef, e2 = timeit([XEF, os.path.join(BIN, 'aarch64', exe)] + cmd[1:], args.reps, 600)
        qem, e3 = (None, 'skipped') if args.no_qemu else timeit([QEMU, os.path.join(BIN, 'aarch64', exe)] + cmd[1:], 1, 900)
        rows.append((name, desc, nat, xef, qem, e2))
        def f(v): return '%.3f' % v if v else '-'
        print('%-10s native %8s  xef %8s  qemu %8s  %s' % (name, f(nat), f(xef), f(qem), e2 or ''), flush=True)
    write_md(rows, args)

def write_md(rows, args):
    path = os.path.join(ROOT, 'docs/benchmarks.md')
    cpu = ''
    try:
        for l in open('/proc/cpuinfo'):
            if l.startswith('model name'):
                cpu = l.split(':', 1)[1].strip()
                break
    except OSError:
        pass
    rev = subprocess.run(['git', '-C', ROOT, 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True).stdout.strip()
    lines = []
    lines.append('## %s — %s (commit %s)%s\n' % (datetime.date.today().isoformat(), cpu, rev,
                                                ' — ' + args.label if args.label else ''))
    lines.append('| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |')
    lines.append('|---|---:|---:|---:|---:|---:|')
    for name, desc, nat, xef, qem, err in rows:
        def f(v): return '%.3f' % v if v else '—'
        vs_nat = '%.0f%%' % (100 * nat / xef) if nat and xef else '—'
        vs_q = '%.1f×' % (qem / xef) if qem and xef else '—'
        lines.append('| %s — %s | %s | %s | %s | %s | %s |' % (name, desc, f(nat), f(xef) if xef else 'FAIL', f(qem), vs_nat, vs_q))
    lines.append('')
    block = '\n'.join(lines) + '\n'
    header = ('# XEF benchmarks\n\nEach benchmark is built from the same source with the same flags (-O2) for '
              'x86-64 (native) and AArch64 (static). Times are best-of-N wall clock. "XEF vs native" is native '
              'time / XEF time (100% = native speed). Newest results first. Regenerate with `bench/build.sh && '
              'bench/run.py`.\n\n')
    old = ''
    if os.path.exists(path):
        old = open(path).read()
        if old.startswith('# XEF benchmarks'):
            idx = old.find('\n## ')
            old = old[idx + 1:] if idx >= 0 else ''
    open(path, 'w').write(header + block + old)
    print('wrote', path)

if __name__ == '__main__':
    main()
