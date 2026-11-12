#!/usr/bin/env python3
"""Captures the default values of simple getters of AppKit classes on the Mac (the reference) so the generated placeholders can answer like the real classes.

  tools/capture_defaults.py            # writes tests/capture and rootfs-src/appkit/generated_defaults.txt (needs the Mac: ssh mac)

For every class that is still generated (rootfs-src/appkit/generated_classes.txt) and every public no-argument getter with a simple result
(BOOL, integers, floats, NSString / NSNumber, NSRect / NSSize / NSPoint) the Mac program forks, creates the object with -init (or -initWithFrame:
for views), calls the getter and prints  Class<TAB>getter<TAB>shape<TAB>value.  A crash or an exception only loses that class.
"""
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appkit_headers

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_PREFIX = ('init', 'copy', 'mutableCopy', 'new', 'retain', 'release', 'autorelease', 'dealloc', 'run', 'show', 'hide', 'close', 'open', 'display', 'update', 'reload', 'reset', 'clear',
               'remove', 'add', 'insert', 'make', 'create', 'perform', 'send', 'start', 'stop', 'validate', 'begin', 'end', 'cancel', 'discard', 'commit', 'post', 'save', 'print', 'load', 'fetch',
               'sort', 'arrange', 'toggle', 'next', 'previous', 'draw', 'layout', 'finalize', 'prepare', 'invalidate', 'scroll', 'select', 'delete', 'cut', 'paste', 'undo', 'redo', 'order', 'center', 'zoom',
               'miniaturize', 'deminiaturize', 'become', 'resign', 'tile', 'sizeToFit', 'unbind', 'bind', 'accessibility', 'description', 'debugDescription', 'hash', 'class', 'superclass', 'isProxy', 'zone',
               'autoscroll', 'wait', 'sleep', 'exit', 'terminate', 'abort', 'activate', 'deactivate')
SKIP_EXACT = {'window', 'windows', 'screen', 'mainScreen', 'view', 'superview', 'subviews', 'firstResponder', 'keyWindow', 'mainWindow', 'currentEvent', 'currentContext', 'sharedApplication'}
SIMPLE = set('BcsiqfdRSP')


def main():
    classes, _ = appkit_headers.parse_dir(os.path.join(REPO, 'mac-out', 'headers'))
    gen = [l.strip() for l in open(os.path.join(REPO, 'rootfs-src', 'appkit', 'generated_classes.txt')) if l.strip() and not l.startswith('#')]
    out = ['#import <Cocoa/Cocoa.h>', '#include <unistd.h>', '#include <sys/wait.h>', '#include <signal.h>', '#include <objc/message.h>',
           'static void emit(const char *c, const char *sel, char shape, id obj, SEL s) {',
           '  switch (shape) {',
           '   case \'B\': printf("%s\\t%s\\tB\\t%d\\n", c, sel, ((BOOL (*)(id, SEL))objc_msgSend)(obj, s)); break;',
           '   case \'c\': printf("%s\\t%s\\tq\\t%d\\n", c, sel, ((signed char (*)(id, SEL))objc_msgSend)(obj, s)); break;',
           '   case \'s\': printf("%s\\t%s\\tq\\t%d\\n", c, sel, ((short (*)(id, SEL))objc_msgSend)(obj, s)); break;',
           '   case \'i\': printf("%s\\t%s\\tq\\t%d\\n", c, sel, ((int (*)(id, SEL))objc_msgSend)(obj, s)); break;',
           '   case \'q\': printf("%s\\t%s\\tq\\t%lld\\n", c, sel, ((long long (*)(id, SEL))objc_msgSend)(obj, s)); break;',
           '   case \'f\': printf("%s\\t%s\\td\\t%.9g\\n", c, sel, (double)((float (*)(id, SEL))objc_msgSend)(obj, s)); break;',
           '   case \'d\': printf("%s\\t%s\\td\\t%.17g\\n", c, sel, ((double (*)(id, SEL))objc_msgSend)(obj, s)); break;',
           '   case \'R\': { NSRect r = ((NSRect (*)(id, SEL))objc_msgSend)(obj, s); printf("%s\\t%s\\tR\\t%.9g,%.9g,%.9g,%.9g\\n", c, sel, r.origin.x, r.origin.y, r.size.width, r.size.height); break; }',
           '   case \'S\': { NSSize r = ((NSSize (*)(id, SEL))objc_msgSend)(obj, s); printf("%s\\t%s\\tS\\t%.9g,%.9g\\n", c, sel, r.width, r.height); break; }',
           '   case \'P\': { NSPoint r = ((NSPoint (*)(id, SEL))objc_msgSend)(obj, s); printf("%s\\t%s\\tP\\t%.9g,%.9g\\n", c, sel, r.x, r.y); break; }',
           '   case \'@\': { id v = ((id (*)(id, SEL))objc_msgSend)(obj, s); if ([v isKindOfClass:[NSString class]]) printf("%s\\t%s\\t@\\t%s\\n", c, sel, [[(NSString *)v stringByReplacingOccurrencesOfString:@"\\n" withString:@"\\\\n"] UTF8String]); else if ([v isKindOfClass:[NSNumber class]]) printf("%s\\t%s\\tq\\t%lld\\n", c, sel, [(NSNumber *)v longLongValue]); break; }',
           '  } fflush(stdout); }',
           'int main(int argc, char **argv) { @autoreleasepool { if (argc < 2) return 1; [NSApplication sharedApplication]; setvbuf(stdout, NULL, _IOLBF, 0);']
    n = 0; probed = []
    for cname in gen:
        c = classes.get(cname)
        if not c:
            continue
        gets = []
        for (kind, sel), m in c['methods'].items():
            if kind != '-' or ':' in sel or m.dep == 'D' or sel.startswith(SKIP_PREFIX) or sel in SKIP_EXACT:
                continue
            sh = appkit_headers.shape(m.ret)
            if sh in SIMPLE or (sh == '@' and ('NSString' in m.ret or 'NSNumber' in m.ret)):
                gets.append((sel, sh))
        if not gets:
            continue
        n += 1; probed.append(cname)
        out.append('  if (!strcmp(argv[1], "%s")) { Class C = objc_getClass("%s"); if (C) { { alarm(6);' % (cname, cname))
        out.append('    @try { id o = nil; if ([C instancesRespondToSelector:@selector(initWithFrame:)] && [C isSubclassOfClass:[NSView class]]) o = [[C alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)]; else if ([C isSubclassOfClass:[NSTouchBarItem class]]) o = [[C alloc] initWithIdentifier:@"xef.id"]; else o = [[C alloc] init];')
        out.append('      if (o) {')
        for sel, sh in gets:
            out.append('        @try { if ([o respondsToSelector:@selector(%s)]) emit("%s", "%s", \'%s\', o, @selector(%s)); } @catch (id e) {}' % (sel, cname, sel, sh, sel))
        out.append('      } } @catch (id e) {} _exit(0); } } }')
    out.append('} return 0; }')
    open('/tmp/capture_defaults.m', 'w').write('\n'.join(out) + '\n')
    subprocess.check_call('scp -q /tmp/capture_defaults.m mac:xef-remote/capture_defaults.m', shell=True)
    names = ' '.join(sorted(probed))
    r = subprocess.run("ssh mac 'cd xef-remote && clang -fobjc-arc -w -framework Cocoa capture_defaults.m -o capture_defaults 2>&1 | grep -m5 error; for c in %s; do DISPLAY= ./capture_defaults $c 2>/dev/null; done'" % names, shell=True, capture_output=True, text=True, timeout=3000)
    rows = [l for l in r.stdout.split('\n') if l.count('\t') == 3]
    if not rows:
        sys.exit('nothing captured; keeping the old table\n' + r.stdout[:500] + r.stderr[:500])
    open(os.path.join(REPO, 'rootfs-src', 'appkit', 'generated_defaults.txt'), 'w').write('\n'.join(rows) + '\n')
    print('classes probed: %d, defaults captured: %d' % (n, len(rows)))
    if r.stdout and not rows:
        print(r.stdout[:800])


if __name__ == '__main__':
    main()
