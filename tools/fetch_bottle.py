#!/usr/bin/env python3
"""Installs Homebrew arm64 bottles (with runtime dependencies) into ./darwin-rootfs/opt/homebrew
without a Mac: formula metadata from formulae.brew.sh, bottles from ghcr.io (both plain HTTPS).

  tools/fetch_bottle.py --libcxx                # once: /usr/lib/libc++, libc++abi, libunwind (llvm bottle)
  tools/fetch_bottle.py jq ripgrep node         # -> darwin-rootfs/opt/homebrew/{Cellar,opt,bin,lib,...}
  build/xef-osx darwin-rootfs/opt/homebrew/bin/jq --version

Does what `brew pour` does that matters to us: Cellar/<name>/<version>, opt/<name> link, bin/sbin/lib/
share/etc/include links, and the @@HOMEBREW_PREFIX@@ / @@HOMEBREW_CELLAR@@ placeholders replaced in text
files and in Mach-O load commands (install names, dependencies, rpaths). Code signatures are left
stale (xef-osx does not check them). Alternative to tools/pull_homebrew.sh (which copies from the Mac).
"""
import json, os, struct, sys, tarfile, time, urllib.error, urllib.request

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'darwin-rootfs'))
PREFIX = '/opt/homebrew'
CELLAR = PREFIX + '/Cellar'
TAGS = ['arm64_sonoma', 'arm64_sequoia', 'arm64_ventura', 'arm64_tahoe', 'arm64_golden_gate', 'all']
CACHE = os.path.join(os.path.expanduser('~'), '.cache', 'xef-bottles')
LINK_DIRS = ['bin', 'sbin', 'lib', 'include', 'share', 'etc', 'libexec', 'Frameworks']


def get(url, headers=None):
    for attempt in range(6):
        try:
            req = urllib.request.Request(url, headers=headers or {})
            with urllib.request.urlopen(req, timeout=300) as r:
                return r.read()
        except (urllib.error.URLError, OSError) as e:
            if attempt == 5 or getattr(e, 'code', 500) < 500:
                raise
            time.sleep(2 << attempt)


def formula(name):
    return json.loads(get('https://formulae.brew.sh/api/formula/%s.json' % name))


def pick_bottle(f):
    files = f['bottle']['stable']['files']
    for t in TAGS:
        if t in files:
            return t, files[t]
    raise SystemExit('%s: no arm64 macOS bottle (%s)' % (f['name'], ', '.join(files)))


def download(f, tag, info):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, '%s-%s.%s.tar.gz' % (f['name'], f['versions']['stable'], tag))
    if not os.path.exists(path):
        repo = info['url'].split('/v2/')[1].split('/blobs/')[0]
        tok = json.loads(get('https://ghcr.io/token?scope=repository:%s:pull' % repo))['token']
        data = get(info['url'], {'Authorization': 'Bearer ' + tok})
        with open(path + '.part', 'wb') as o:
            o.write(data)
        os.rename(path + '.part', path)
    return path


SUBST = [(b'@@HOMEBREW_PREFIX@@', PREFIX.encode()), (b'@@HOMEBREW_CELLAR@@', CELLAR.encode()),
         (b'@@HOMEBREW_REPOSITORY@@', PREFIX.encode()), (b'@@HOMEBREW_LIBRARY@@', (PREFIX + '/Library').encode()),
         (b'@@HOMEBREW_PERL@@', b'/usr/bin/perl'), (b'@@HOMEBREW_JAVA@@', (PREFIX + '/opt/openjdk/libexec/openjdk.jdk/Contents/Home').encode())]

# load commands whose payload is (offset-to-string, ...) at +8
LC_STR = {0xc: 'LOAD_DYLIB', 0xd: 'ID_DYLIB', 0x80000018: 'LOAD_WEAK_DYLIB', 0x8000001c: 'RPATH',
          0x8000001f: 'REEXPORT_DYLIB', 0x80000023: 'LAZY_LOAD_DYLIB', 0x20: 'LOAD_UPWARD', 0x8000001e: 'DYLD_ENV'}


def patch_macho_slice(buf, off):
    magic, = struct.unpack_from('<I', buf, off)
    if magic != 0xfeedfacf:
        return 0
    ncmds, sizeofcmds = struct.unpack_from('<II', buf, off + 16)
    p, n = off + 32, 0
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', buf, p)
        if cmd in LC_STR:
            so, = struct.unpack_from('<I', buf, p + 8)
            s0, s1 = p + so, p + size
            end = buf.index(b'\0', s0, s1) if b'\0' in buf[s0:s1] else s1
            s = bytes(buf[s0:end])
            new = s
            for a, b in SUBST:
                new = new.replace(a, b)
            if new != s:
                if len(new) >= s1 - s0:
                    print('  warning: %r does not fit its load command' % new, file=sys.stderr)
                else:
                    buf[s0:s1] = new + b'\0' * (s1 - s0 - len(new))
                    n += 1
        p += size
    return n


def fix_file(path):
    with open(path, 'rb') as fh:
        data = fh.read()
    if b'@@HOMEBREW_' not in data:
        return
    head = data[:4]
    if head in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'):
        buf = bytearray(data)
        if head == b'\xca\xfe\xba\xbe':
            nfat, = struct.unpack_from('>I', buf, 4)
            for i in range(nfat):
                _, _, o, _, _ = struct.unpack_from('>IIIII', buf, 8 + 20 * i)
                patch_macho_slice(buf, o)
        else:
            patch_macho_slice(buf, 0)
        data = bytes(buf)
    elif b'\0' not in data[:8192]:
        for a, b in SUBST:
            data = data.replace(a, b)
    else:
        return  # other binaries: brew leaves them alone too
    mode = os.stat(path).st_mode
    os.chmod(path, mode | 0o200)
    with open(path, 'wb') as fh:
        fh.write(data)
    os.chmod(path, mode)


def link_tree(src, dst):
    """brew link: mirror src into dst with relative symlinks (directories merged)."""
    os.makedirs(dst, exist_ok=True)
    for e in os.listdir(src):
        s, d = os.path.join(src, e), os.path.join(dst, e)
        if os.path.isdir(s) and not os.path.islink(s):
            if os.path.islink(d) or not os.path.exists(d):
                if os.path.lexists(d):
                    os.unlink(d)
                os.makedirs(d, exist_ok=True)
            link_tree(s, d)
        else:
            if os.path.lexists(d):
                os.unlink(d)
            os.symlink(os.path.relpath(s, dst), d)


def install(name, done):
    if name in done:
        return
    done.add(name)
    f = formula(name)
    for dep in f.get('dependencies', []):
        install(dep, done)
    tag, info = pick_bottle(f)
    ver = f['versions']['stable'] + ('_%d' % f['revision'] if f.get('revision') else '')
    keg = os.path.join(ROOT + CELLAR, f['name'], ver)
    if not os.path.isdir(keg):
        tgz = download(f, tag, info)
        print('%-20s %-12s %s' % (f['name'], ver, tag))
        with tarfile.open(tgz) as t:
            t.extractall(ROOT + CELLAR, filter='tar')
        for d, _, fs in os.walk(keg):
            for x in fs:
                p = os.path.join(d, x)
                if not os.path.islink(p):
                    fix_file(p)
    for alias in {f['name']} | set(f.get('aliases', [])):
        opt = os.path.join(ROOT + PREFIX, 'opt', alias)
        os.makedirs(os.path.dirname(opt), exist_ok=True)
        if os.path.lexists(opt):
            os.unlink(opt)
        os.symlink(os.path.relpath(keg, os.path.dirname(opt)), opt)
    if not f.get('keg_only'):
        for sub in LINK_DIRS:
            if os.path.isdir(os.path.join(keg, sub)):
                link_tree(os.path.join(keg, sub), os.path.join(ROOT + PREFIX, sub))


def install_libcxx():
    """/usr/lib/libc++.1.dylib, libc++abi.1.dylib, libunwind.1.dylib from the llvm bottle (the system copies
    live in the dyld shared cache); found by the libraries themselves through their @loader_path rpath."""
    f = formula('llvm')
    tag, info = pick_bottle(f)
    tgz = download(f, tag, info)
    dst = os.path.join(ROOT, 'usr/lib')
    os.makedirs(dst, exist_ok=True)
    with tarfile.open(tgz) as t:
        for m in t.getmembers():
            base = os.path.basename(m.name)
            if m.isfile() and base in ('libc++.1.0.dylib', 'libc++abi.1.0.dylib', 'libunwind.1.0.dylib') \
                    and ('/lib/c++/' in m.name or '/lib/unwind/' in m.name):
                out = os.path.join(dst, base.replace('.1.0.', '.1.'))
                buf = bytearray(t.extractfile(m).read())
                set_dylib_id(buf, '/usr/lib/' + os.path.basename(out))
                with open(out, 'wb') as o:
                    o.write(buf)
                print('usr/lib/' + os.path.basename(out), f['versions']['stable'])


def set_dylib_id(buf, name):
    ncmds, = struct.unpack_from('<I', buf, 16)
    p = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', buf, p)
        if cmd == 0xd:
            so, = struct.unpack_from('<I', buf, p + 8)
            assert len(name) < size - so
            buf[p + so:p + size] = name.encode() + b'\0' * (size - so - len(name))
        p += size


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    if sys.argv[1] == '--libcxx':
        install_libcxx()
        sys.argv[1:2] = []
    done = set()
    for n in sys.argv[1:]:
        install(n, done)
