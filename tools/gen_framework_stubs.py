#!/usr/bin/env python3
"""Generates placeholder ("stub") versions of every macOS system framework that darwin-rootfs lacks, from the
export lists of the SDK (.tbd) and from facts recorded on a real Mac by tools/mac_fwdump.m.

  tools/gen_framework_stubs.py request --sdk DIR > request.txt      # what mac_fwdump should look up
  tools/gen_framework_stubs.py build   --sdk DIR [--facts facts.txt] [--rootfs darwin-rootfs] [--only REGEX]

For each library of the SDK under --prefix (default: /System/Library/{Frameworks,PrivateFrameworks,SubFrameworks}):

  * not in the rootfs: a stub dylib is installed at its install name;
  * hand-written in the rootfs: "<dylib>.xefstubs" next to it gets only the names it does not implement
    (xef-osx loads that file together with the dylib).

A stub has the real library's exported names: functions return 0 (integer, pointer and floating point), string
constants have their real value, plain constants their real bytes, other data is zero-filled with its real size,
Objective-C classes exist with their real superclass and answer every message they do not implement with nil. Stubs are arm64
Mach-O built here with clang and ld64.lld; no Apple code or header is used. xef-osx binds to a stub only what
nothing else (rootfs dylibs, the HLE, the host) provides, so generating them never replaces an implementation.
Names already implemented anywhere are left out. XEF_STUB_TRACE=1 logs every stub call at run time.

Swift and C++ symbols are skipped unless --mangled is given (their ABI needs more than a placeholder).
"""
import argparse
import concurrent.futures
import glob
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tbd  # noqa: E402

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
PREFIXES = ['/System/Library/Frameworks/', '/System/Library/PrivateFrameworks/', '/System/Library/SubFrameworks/']
TARGET = 'arm64-apple-macos12.0'
MARKER = '_xef_generated_stub'
IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*$')
C_KEYWORDS = set('''auto break case char const continue default do double else enum extern float for goto if inline
int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile
while id self super nil Nil YES NO SEL Class BOOL IMP in out inout bycopy byref oneway'''.split())


def tool(*names):
    for n in names:
        for cand in (n, n + '-18', n + '-19', n + '-20', n + '-17'):
            if shutil.which(cand):
                return cand
    sys.exit('missing tool: ' + names[0])


def read_sdk(sdk):
    """install name -> tbd.Lib for every library of the SDK"""
    libs = {}
    for p in sorted(glob.glob(os.path.join(sdk, '**', '*.tbd'), recursive=True)):
        if os.path.islink(p) or not os.path.isfile(p):
            continue
        for lib in tbd.read(p):
            libs.setdefault(lib.install_name, lib)
    return libs


def wanted_symbol(name, mangled):
    if name.startswith('$ld$') or name.startswith('.objc') or '\n' in name or '"' in name or ' ' in name:
        return False
    if not mangled and (name.startswith(('_$s', '_$S', '__Z', '___Z', '_swift', '__swift', '_$e')) or '$s' in name[:4]):
        return False
    return True


# --- facts from the Mac -----------------------------------------------------------------------------------

class Facts:
    def __init__(self):
        self.sym = {}        # (lib, name) -> ('F',) | ('S', str) | ('D', size, bytes or None)
        self.any = {}        # name -> the same, from whichever library answered first
        self.super = {}      # class -> superclass name or None (root)
        self.loaded = set()  # libraries the Mac could load

    @staticmethod
    def read(path):
        f = Facts()
        if not path:
            return f
        lib = None
        with open(path, errors='replace') as fh:
            for line in fh:
                if not line.endswith('\n'):
                    break                      # cut off: the child died while writing
                p = line.rstrip('\n').split('\t')
                fact = None
                try:
                    if p[0] == 'L' and len(p) == 3:
                        lib = p[1]
                        if p[2] == '1':
                            f.loaded.add(lib)
                    elif p[0] == 'F' and len(p) == 2:
                        fact = ('F',)
                    elif p[0] == 'S' and len(p) == 3:
                        fact = ('S', bytes.fromhex(p[2]))
                    elif p[0] == 'D' and len(p) == 5:
                        fact = ('D', int(p[2]), None if p[3] == '-' else bytes.fromhex(p[3]))
                    elif p[0] == 'C' and len(p) == 4:
                        f.super.setdefault(p[1], None if p[2] == '-' else p[2])
                except ValueError:
                    continue
                if fact:
                    f.sym[(lib, p[1])] = fact
                    f.any.setdefault(p[1], fact)
        return f


VERB = re.compile(r'(Get|Copy|Create|Set|Make|Add|Remove|Is|Has|With|Find|Apply|Release|Retain|Register|Load|Read|Write)')


def guess(name):
    """Without a fact from the Mac: Apple's naming conventions for string constants; everything else is a function."""
    n = name[1:] if name.startswith('_') else name
    if re.match(r'k[A-Z0-9_]', n) or n.endswith(('Notification', 'ErrorDomain', 'ErrorKey')):
        return ('S', n.encode())
    if n.endswith(('Key', 'Identifier', 'Attribute', 'AttributeName')) and not VERB.search(n):
        return ('S', n.encode())
    if name.startswith(('__ZTV', '__ZTI', '__ZTS')):
        return ('D', 256, None)
    if name.startswith(('_$s', '_$S')) and re.search(r'(N|Mn|Mp|Mc|Mm|MV|WP|WV|Wvd|Tq|Mf|ML|Mo|MF|MB|Ml|Mu|Wl|WL|Mr|Mq|Hn|Hc)$', name):
        return ('D', 256, None)
    return ('F',)


# --- what the rootfs already implements -------------------------------------------------------------------

def is_macho(path):
    try:
        with open(path, 'rb') as f:
            return f.read(4) in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf')
    except OSError:
        return False


def defined(nm, path):
    """(exported names, Objective-C classes defined - exported or not) of a Mach-O file"""
    out = subprocess.run([nm, '--defined-only', path], capture_output=True, text=True, errors='replace').stdout
    names, classes = set(), set()
    for line in out.splitlines():
        p = line.split()
        if len(p) < 3 or len(p[-2]) != 1:
            continue
        if p[-2].isupper():
            names.add(p[-1])
        if p[-1].startswith('_OBJC_CLASS_$_'):
            classes.add(p[-1][len('_OBJC_CLASS_$_'):])
    return names, classes


def scan_rootfs(rootfs, nm, jobs):
    """(names implemented by real dylibs of the rootfs, classes they define, {realpath of a real dylib})"""
    files = []
    for top in ('System', 'usr/lib'):
        for d, _, names in os.walk(os.path.join(rootfs, top)):
            for n in names:
                p = os.path.join(d, n)
                if not os.path.islink(p) and not n.endswith('.xefstubs') and not n.endswith('.a') and is_macho(p):
                    files.append(p)
    taken, classes, real = set(), set(), set()
    with concurrent.futures.ThreadPoolExecutor(jobs) as ex:
        for p, (names, cls) in zip(files, ex.map(lambda p: defined(nm, p), files)):
            if MARKER in names:
                continue                        # a stub from an earlier run
            real.add(os.path.realpath(p))
            taken |= names
            classes |= cls
    return taken, classes, real


def hle_names():
    names = set()
    for src in glob.glob(os.path.join(REPO, 'src', 'loader', 'darwin_*.cpp')):
        with open(src, errors='replace') as f:
            names.update(re.findall(r'"(_[A-Za-z_][A-Za-z0-9_$]*)"', f.read()))
    return names


def host_libc_names():
    names = set()
    for lib in ('libc.so.6', 'libm.so.6'):
        for d in ('/lib/x86_64-linux-gnu', '/usr/lib/x86_64-linux-gnu', '/lib64', '/usr/lib64'):
            p = os.path.join(d, lib)
            if os.path.exists(p):
                out = subprocess.run(['nm', '-D', '--defined-only', p], capture_output=True, text=True).stdout
                names.update('_' + line.split()[-1].split('@')[0] for line in out.splitlines() if line.split())
                break
    return names


# --- source of one stub -----------------------------------------------------------------------------------

def c_string(data):
    out = []
    for b in data:
        if b in (0x22, 0x5c) or b < 0x20 or b > 0x7e or b == 0x3f:
            out.append('\\%03o' % b)
        else:
            out.append(chr(b))
    return '"' + ''.join(out) + '"'


def asm_name(name):
    return '"' + name.replace('\\', '\\\\') + '"'


PRELUDE_M = r'''// Generated by tools/gen_framework_stubs.py - do not edit.
extern id objc_getClass(const char *);
extern SEL sel_registerName(const char *);
extern Class object_getClass(id);
extern const char *class_getName(Class);
extern const char *sel_getName(SEL);
extern int class_isMetaClass(Class);
extern char *getenv(const char *);
extern int dprintf(int, const char *, ...);

const char xef_generated_stub = 1;
__attribute__((visibility("hidden"))) char xef_stub_trace;
__attribute__((visibility("hidden"))) void xef_stub_log(const char *name) { dprintf(2, "xef-stub: %s\n", name); }
__attribute__((constructor)) static void xef_stub_init(void) { xef_stub_trace = getenv("XEF_STUB_TRACE") != 0; }

// An unknown message to a stub class goes (forwardingTargetForSelector:) to a sink object whose class grows a
// method returning nil / 0 for each selector it is sent. The stub class itself keeps answering NO to
// respondsToSelector:. One sink class serves every stub image of the process.
typedef id (*IMP)(id, SEL, ...);
extern Class objc_allocateClassPair(Class, const char *, unsigned long);
extern void objc_registerClassPair(Class);
extern signed char class_addMethod(Class, SEL, IMP, const char *);
extern id class_createInstance(Class, unsigned long);
extern id xef_stub_zero(id, SEL, ...);
static signed char xef_sink_resolve(id cls, SEL _cmd, SEL sel) {
    class_addMethod((Class)cls, sel, xef_stub_zero, "@@:");
    return 1;
}
static id xef_stub_target(id self, SEL s) {
    static id sink;
    if (xef_stub_trace) {
        Class c = object_getClass(self);
        dprintf(2, "xef-stub: %c[%s %s]\n", class_isMetaClass(c) ? '+' : '-', class_getName(c), sel_getName(s));
    }
    if (!sink) {
        Class c = (Class)objc_getClass("XEFStubSink");
        if (!c) {
            c = objc_allocateClassPair((Class)objc_getClass("NSObject"), "XEFStubSink", 0);
            class_addMethod(object_getClass((id)c), sel_registerName("resolveInstanceMethod:"), (IMP)xef_sink_resolve, "c@::");
            objc_registerClassPair(c);
        }
        sink = class_createInstance(c, 0);
    }
    return sink;
}
#define XEF_STUB(C) @implementation C \
- (id)forwardingTargetForSelector:(SEL)s { return xef_stub_target(self, s); } \
+ (id)forwardingTargetForSelector:(SEL)s { return xef_stub_target(self, s); } \
@end
'''

PRELUDE_S = r'''// Generated by tools/gen_framework_stubs.py - do not edit.
.section __TEXT,__text,regular,pure_instructions
.p2align 2
Lxef_common:
    adrp x17, _xef_stub_trace@PAGE
    ldrb w17, [x17, _xef_stub_trace@PAGEOFF]
    cbnz w17, Lxef_slow
    .private_extern _xef_stub_zero
_xef_stub_zero:
Lxef_zero:
    mov x0, #0
    mov x1, #0
    movi d0, #0
    movi d1, #0
    movi d2, #0
    movi d3, #0
    ret
Lxef_slow:
    stp x29, x30, [sp, #-16]!
    mov x0, x16
    bl _xef_stub_log
    ldp x29, x30, [sp], #16
    b Lxef_zero
'''


def write_sources(work, plan):
    """plan: dict(classes=[(name, super, ivars, eh)], decls=[(name, super or None)], syms=[(name, fact, weak)])"""
    m = [PRELUDE_M]
    for name, sup in plan['decls']:
        m.append('%s@interface %s%s @end' % ('' if sup else '__attribute__((objc_root_class)) ', name, ' : ' + sup if sup else ''))
    for name, sup, ivars, eh in plan['classes']:
        body = ' { @public ' + ' '.join('void *%s;' % i for i in ivars) + ' }' if ivars else ''
        m.append('%s@interface %s : %s%s @end' % ('__attribute__((objc_exception)) ' if eh else '', name, sup, body))
    for name, _, _, _ in plan['classes']:
        m.append('XEF_STUB(%s)' % name)
    s = [PRELUDE_S]
    strings, datas, zeros = [], [], []
    n = 0
    for name, fact, weak in plan['syms']:
        if fact[0] == 'F':
            s.append('.globl %s\n%s%s:\n    adrp x16, Ln%d@PAGE\n    add x16, x16, Ln%d@PAGEOFF\n    b Lxef_common'
                     % (asm_name(name), '.weak_definition %s\n' % asm_name(name) if weak else '', asm_name(name), n, n))
            strings.append('Ln%d: .asciz %s' % (n, c_string(name.encode())))
            n += 1
        elif fact[0] == 'S':
            m.append('const void *const xef_s%d __asm__(%s) = (const void *)__builtin___CFStringMakeConstantString(%s);'
                     % (n, c_string(name.encode()), c_string(fact[1])))
            n += 1
        elif fact[2] is not None and fact[2]:
            datas.append('.globl %s\n.p2align 4\n%s:\n    .byte %s' % (asm_name(name), asm_name(name), ','.join(str(b) for b in fact[2])))
        else:
            zeros.append('.globl %s\n.zerofill __DATA,__common,%s,%d,4' % (asm_name(name), asm_name(name), max(8, min(fact[1], 65536))))
    if strings:
        s.append('.section __TEXT,__cstring,cstring_literals')
        s += strings
    if datas:
        s.append('.section __TEXT,__const')
        s += datas
    s += zeros
    with open(os.path.join(work, 'stub.m'), 'w') as f:
        f.write('\n'.join(m) + '\n')
    with open(os.path.join(work, 'stub.s'), 'w') as f:
        f.write('\n'.join(s) + '\n')


def version(v):
    parts = [int(x) if x.isdigit() else 0 for x in str(v).split('.')[:3]] or [1]
    limits = [65535, 255, 255]
    return '.'.join(str(min(p, limits[i])) for i, p in enumerate(parts))


def write_tbd(path, install_name, classes=()):
    with open(path, 'w') as f:
        f.write("--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-macos ]\ninstall-name: '%s'\n" % install_name)
        if classes:
            f.write('exports:\n  - targets: [ arm64-macos ]\n    objc-classes: [ %s ]\n' % ', '.join(sorted(classes)))
        f.write('...\n')


def build_one(job):
    work, plan, cc, ld = job['work'], job['plan'], job['cc'], job['ld']
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    write_sources(work, plan)
    flags = [cc, '-target', TARGET, '-w', '-O1', '-c']
    for src, extra in (('stub.m', ['-fobjc-runtime=macosx-12.0', '-fno-objc-arc', '-fblocks']), ('stub.s', [])):
        r = subprocess.run(flags + extra + [os.path.join(work, src), '-o', os.path.join(work, src + '.o')],
                           capture_output=True, text=True)
        if r.returncode:
            return job, 'compile %s: %s' % (src, r.stderr[-2000:])
    cmd = [ld, '-arch', 'arm64', '-platform_version', 'macos', '12.0', '12.0', '-dylib', '-install_name', job['install_name'],
           '-compatibility_version', version(plan['compat']), '-current_version', version(plan['current']),
           '-undefined', 'dynamic_lookup', os.path.join(work, 'stub.m.o'), os.path.join(work, 'stub.s.o')]
    for i, (name, classes) in enumerate(sorted(plan['links'].items())):
        p = os.path.join(work, 'dep%d.tbd' % i)
        write_tbd(p, name, classes)
        cmd.append(p)
    for i, name in enumerate(plan['reexports']):
        p = os.path.join(work, 'reexport%d.tbd' % i)
        write_tbd(p, name)
        cmd += ['-reexport_library', p]
    os.makedirs(os.path.dirname(job['dest']), exist_ok=True)
    tmp = job['dest'] + '.tmp'
    r = subprocess.run(cmd + ['-o', tmp], capture_output=True, text=True)
    if r.returncode:
        return job, 'link: ' + r.stderr[-2000:]
    os.replace(tmp, job['dest'])
    if not job['keep']:
        shutil.rmtree(work, ignore_errors=True)
    return job, None


def framework_links(dest):
    """Foo.framework/Versions/A/Foo -> also Versions/Current and Foo.framework/Foo, as in a real framework"""
    d = os.path.dirname(dest)
    name = os.path.basename(dest)
    if os.path.basename(os.path.dirname(d)) != 'Versions' or not os.path.dirname(os.path.dirname(d)).endswith('/' + name + '.framework'):
        return
    versions = os.path.dirname(d)
    cur = os.path.join(versions, 'Current')
    if not os.path.lexists(cur):
        os.symlink(os.path.basename(d), cur)
    top = os.path.join(os.path.dirname(versions), name)
    if not os.path.lexists(top):
        os.symlink('Versions/Current/' + name, top)


# --- commands -----------------------------------------------------------------------------------------------

def in_scope(name, prefixes):
    return name.startswith(tuple(prefixes))


def cmd_request(args):
    libs = read_sdk(args.sdk)
    out = sys.stdout
    for name in sorted(libs):
        if not in_scope(name, args.prefix):
            continue
        lib = libs[name]
        out.write('L %s\n' % name)
        for s in sorted(lib.symbols):
            if wanted_symbol(s, args.mangled) and s not in lib.tlv:
                out.write('S %s\n' % s)
        for c in sorted(lib.classes):
            out.write('C %s\n' % c)


def cmd_build(args):
    cc, ld, nm = tool('clang'), tool('ld64.lld'), tool('llvm-nm')
    rootfs = os.path.abspath(args.rootfs)
    print('reading the SDK ...', flush=True)
    libs = read_sdk(args.sdk)
    for lib in libs.values():                    # classes listed as plain symbols (Swift classes visible to ObjC)
        for s in [s for s in lib.symbols if s.startswith(('_OBJC_', '__OBJC_'))]:
            lib.symbols.discard(s)
            if s.startswith('_OBJC_CLASS_$_'):
                lib.classes.add(s[len('_OBJC_CLASS_$_'):])
    facts = Facts.read(args.facts)
    print('scanning %s ...' % rootfs, flush=True)
    taken, taken_classes, real = scan_rootfs(rootfs, nm, args.jobs)
    taken |= hle_names() | host_libc_names()

    scope = sorted(n for n in libs if in_scope(n, args.prefix))

    def host(install_name):
        return rootfs + install_name

    def real_at(install_name):
        p = os.path.realpath(host(install_name))
        return p if p in real else None

    # every class gets one home among the libraries generated here
    home = {}
    for name in scope:
        for c in libs[name].classes:
            if c not in taken_classes and IDENT.match(c):
                home.setdefault(c, name)

    def superclass(c):
        """nearest ancestor (as on the Mac) that exists in the rootfs or will be generated; NSObject otherwise"""
        seen = {c}
        s = facts.super.get(c)
        while s and s not in seen:
            if s in taken_classes or s in home:
                return s
            seen.add(s)
            s = facts.super.get(s)
        return 'NSObject'

    jobs = []
    only = re.compile(args.only) if args.only else None
    stats = dict(full=0, companion=0, functions=0, strings=0, data=0, classes=0, guessed=0)
    for name in scope:
        if only and not only.search(name):
            continue
        lib = libs[name]
        target = real_at(name)
        syms = []
        for s in sorted(lib.symbols):
            if s in taken or s in lib.tlv or not wanted_symbol(s, args.mangled) or s == MARKER:
                continue
            fact = facts.sym.get((name, s)) or facts.any.get(s)
            if not fact:
                fact = guess(s)
                stats['guessed'] += 1
            syms.append((s, fact, s in lib.weak))
            stats['functions' if fact[0] == 'F' else 'strings' if fact[0] == 'S' else 'data'] += 1
        ivars = {}
        for iv in lib.ivars:
            c, _, v = iv.partition('.')
            if IDENT.match(v) and v not in C_KEYWORDS:
                ivars.setdefault(c, []).append(v)
        mine = sorted(c for c in lib.classes if home.get(c) == name)
        sup = {c: superclass(c) for c in mine}
        # declarations: ancestors outside this stub, then this stub's classes, each after its superclass
        decls, declared, links = [], set(), {}

        def declare(c):
            if c in declared or c in sup:
                return
            declared.add(c)
            if c == 'NSObject' or (c not in taken_classes and c not in home):
                decls.append((c, None))
                return
            if c in home:
                parent = superclass(c)
            else:
                parent = facts.super.get(c)
                if parent and parent not in taken_classes:
                    parent = None
            if parent:
                declare(parent)
            decls.append((c, parent))
        ordered, placed = [], set()

        def place(c, depth=0):
            if c in placed:
                return
            placed.add(c)
            if sup[c] in sup and depth < 500:
                place(sup[c], depth + 1)
            elif sup[c] not in sup:
                declare(sup[c])
                if sup[c] in home:
                    links.setdefault(home[sup[c]], set()).add(sup[c])
            inherited, a = set(), sup[c]
            while a in sup and a not in (c,) and len(inherited) < 100000:
                inherited.update(ivars.get(a, []))
                a = sup[a] if sup[a] != a else None
            ordered.append((c, sup[c], sorted(set(ivars.get(c, [])) - inherited), c in lib.ehtypes))
        for c in mine:
            place(c)
        stats['classes'] += len(ordered)
        if not syms and not ordered and target:
            continue                             # the hand-written dylib already covers the export list
        reexports = []
        if not target:
            for r in lib.reexports:
                if r != name and (real_at(r) or (r in libs and in_scope(r, args.prefix))):
                    reexports.append(r)
        if target:
            dest, install = target + '.xefstubs', name + '.xefstubs'
            stats['companion'] += 1
        else:
            dest, install = host(name), name
            stats['full'] += 1
        jobs.append(dict(name=name, install_name=install, dest=dest, cc=cc, ld=ld, keep=args.keep,
                         work=os.path.join(args.work, re.sub(r'[^A-Za-z0-9_.]', '_', name.strip('/'))),
                         plan=dict(classes=ordered, decls=decls, syms=syms, links=links, reexports=reexports,
                                   current=lib.current, compat=lib.compat)))
    print('%d stub libraries (%d full, %d companions of hand-written dylibs): %d functions, %d string constants, '
          '%d other data, %d classes; %d kinds guessed from the name'
          % (len(jobs), stats['full'], stats['companion'], stats['functions'], stats['strings'], stats['data'],
             stats['classes'], stats['guessed']), flush=True)
    if args.dry_run:
        return 0
    failed = 0
    os.makedirs(args.work, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as ex:
        for i, (job, err) in enumerate(ex.map(build_one, jobs)):
            if err:
                failed += 1
                print('FAILED %s: %s' % (job['name'], err), flush=True)
            elif not job['install_name'].endswith('.xefstubs'):
                framework_links(job['dest'])
            if (i + 1) % 200 == 0:
                print('  %d / %d' % (i + 1, len(jobs)), flush=True)
    print('done: %d built, %d failed' % (len(jobs) - failed, failed))
    return 1 if failed else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    for name in ('request', 'build'):
        p = sub.add_parser(name)
        p.add_argument('--sdk', required=True, help='directory with the .tbd files of a macOS SDK')
        p.add_argument('--prefix', action='append', help='install-name prefix to cover (repeatable)')
        p.add_argument('--mangled', action='store_true', help='include Swift and C++ symbols')
    p.add_argument('--facts', help='output of tools/mac_fwdump.m')
    p.add_argument('--rootfs', default=os.path.join(REPO, 'darwin-rootfs'))
    p.add_argument('--work', default=os.path.join(REPO, 'build', 'fwstubs'))
    p.add_argument('--only', help='regular expression: only libraries whose install name matches')
    p.add_argument('--keep', action='store_true', help='keep the generated sources in --work')
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('-j', '--jobs', type=int, default=os.cpu_count() or 4)
    args = ap.parse_args()
    args.prefix = args.prefix or PREFIXES
    return cmd_request(args) if args.cmd == 'request' else cmd_build(args)


if __name__ == '__main__':
    sys.exit(main())
