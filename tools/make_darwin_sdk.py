#!/usr/bin/env python3
"""Generates a minimal link-time macOS "SDK" for toolchains running under xef-osx (ld64.lld, rustc, clang):
text-based stubs (.tbd) only, no headers and nothing taken from Apple's SDK.

  tools/make_darwin_sdk.py                 # -> darwin-rootfs/opt/xef-sdk
  SDKROOT=/opt/xef-sdk build/xef-osx -L darwin-rootfs /opt/homebrew/bin/rustc \\
      -C linker=/opt/homebrew/bin/ld64.lld -C linker-flavor=ld64.lld hello.rs

usr/lib/libSystem.tbd (install name /usr/lib/libSystem.B.dylib) exports what xef-osx resolves for libSystem at run
time: the Darwin names implemented by the HLE layer (string literals "_name" in src/loader/darwin_*.cpp), the C
library functions it forwards to the host (glibc's public dynamic symbols, '_'-prefixed) and the exports of the
rootfs dylibs xef-osx loads as parts of libSystem (IMPLICIT, as load_implicit_images in macho_loader.cpp). libc/libm/libpthread/
libdl/libdyld .tbd are aliases of it, as in Apple's SDK. Real dylibs in darwin-rootfs/usr/lib (libiconv, libc++,
libz, ...) get a .tbd listing their exported symbols (llvm-nm).
"""
import glob
import os
import re
import subprocess
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
ROOTFS = os.path.join(REPO, 'darwin-rootfs')
SDK = os.path.join(ROOTFS, 'opt', 'xef-sdk')
TARGET = 'arm64-macos'
IMPLICIT = ['/usr/lib/libunwind.1.dylib', '/usr/lib/system/libsystem_blocks.dylib', '/usr/lib/system/libdispatch.dylib',
            '/usr/lib/system/libsystem_fts.dylib']


def tbd(install_name, symbols, path, current='1.0.0'):
    syms = sorted(set(symbols))
    lines = ['--- !tapi-tbd', 'tbd-version: 4', 'targets: [ %s ]' % TARGET,
             "install-name: '%s'" % install_name, 'current-version: %s' % current, 'exports:',
             '  - targets: [ %s ]' % TARGET, '    symbols: [']
    lines += ["      '%s'," % s for s in syms]
    if syms:
        lines[-1] = lines[-1].rstrip(',')
    lines += ['    ]', '...', '']
    with open(path, 'w') as f:
        f.write('\n'.join(lines))
    return len(syms)


def hle_names():
    names = set()
    for src in glob.glob(os.path.join(REPO, 'src', 'loader', 'darwin_*.cpp')):
        with open(src, errors='replace') as f:
            names.update(re.findall(r'"(_[A-Za-z_][A-Za-z0-9_$]*)"', f.read()))
    return {n for n in names if not n.startswith('_xef_')}


def host_libc_names():
    names = set()
    for lib in ('libc.so.6', 'libm.so.6'):
        for d in ('/lib/x86_64-linux-gnu', '/usr/lib/x86_64-linux-gnu', '/lib64', '/usr/lib64'):
            p = os.path.join(d, lib)
            if os.path.exists(p):
                out = subprocess.run(['nm', '-D', '--defined-only', p], capture_output=True, text=True).stdout
                for line in out.splitlines():
                    parts = line.split()
                    if len(parts) < 3 or parts[1] not in 'TtWiV':
                        continue
                    n = parts[2].split('@')[0]
                    if n and not n.startswith('_'):
                        names.add('_' + n)
                break
    return names


def dylib_exports(path):
    for nm in ('llvm-nm', 'nm'):
        try:
            out = subprocess.run([nm, '-g', '--defined-only', path], capture_output=True, text=True).stdout
        except FileNotFoundError:
            continue
        syms = [l.split()[-1] for l in out.splitlines() if len(l.split()) >= 3]
        if syms:
            return syms
    return []


def install_name(path):
    try:
        out = subprocess.run(['llvm-objdump', '--macho', '--dylib-id', path], capture_output=True, text=True).stdout
        lines = [l.strip() for l in out.splitlines() if l.strip()]
        if len(lines) >= 2 and lines[1].startswith('/'):
            return lines[1]
    except FileNotFoundError:
        pass
    return '/usr/lib/' + os.path.basename(path)


def main():
    lib = os.path.join(SDK, 'usr', 'lib')
    os.makedirs(lib, exist_ok=True)
    system = hle_names() | host_libc_names() | {'dyld_stub_binder'}   # referenced by lazy-binding stubs
    for g in IMPLICIT:
        if os.path.exists(ROOTFS + g):
            system.update(dylib_exports(ROOTFS + g))
    n = tbd('/usr/lib/libSystem.B.dylib', system, os.path.join(lib, 'libSystem.tbd'), '1351.0.0')
    print('libSystem.tbd: %d symbols' % n)
    for alias in ('libSystem.B.tbd', 'libc.tbd', 'libm.tbd', 'libpthread.tbd', 'libdl.tbd', 'libdyld.tbd', 'libinfo.tbd'):
        p = os.path.join(lib, alias)
        if os.path.lexists(p):
            os.remove(p)
        os.symlink('libSystem.tbd', p)
    for dylib in sorted(glob.glob(os.path.join(ROOTFS, 'usr', 'lib', '*.dylib'))):
        if os.path.islink(dylib) or dylib[len(ROOTFS):] in IMPLICIT:
            continue
        base = os.path.basename(dylib)
        stem = re.sub(r'(\.[0-9A-Z]+)*\.dylib$', '', base)       # libiconv.2.dylib -> libiconv
        syms = dylib_exports(dylib)
        if not syms:
            continue
        cnt = tbd(install_name(dylib), syms, os.path.join(lib, stem + '.tbd'))
        print('%s.tbd: %d symbols (%s)' % (stem, cnt, base))
    with open(os.path.join(SDK, 'SDKSettings.json'), 'w') as f:
        f.write('{"CanonicalName": "macosx15.0", "Version": "15.0", "DisplayName": "xef-osx stub SDK"}\n')
    print('SDK at', SDK, '(guest path /opt/xef-sdk)')


if __name__ == '__main__':
    sys.exit(main())
