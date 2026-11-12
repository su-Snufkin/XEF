#!/usr/bin/env python3
"""Compares class-level getters of the public AppKit API between the Mac and XEF: for every +shared… / +default… / … class method with no arguments that returns an object,
the nil-ness of the result must agree (a placeholder singleton that answers nil, or a factory that should answer nil but does not, shows up here).

  tools/probe_factories.py            # needs the Mac (ssh mac), mac-out/headers, build/xef-osx and darwin-rootfs; prints the differences

Probes are one process per class, so a crash only loses that class."""
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appkit_headers as H

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP = ('init', 'copy', 'mutableCopy', 'new', 'alloc', 'retain', 'release', 'autorelease', 'dealloc', 'run', 'show', 'hide', 'close', 'open', 'display', 'update', 'reload', 'reset', 'clear', 'remove', 'add',
        'insert', 'make', 'create', 'perform', 'send', 'start', 'stop', 'validate', 'begin', 'end', 'cancel', 'discard', 'commit', 'post', 'save', 'print', 'load', 'fetch', 'sort', 'arrange', 'toggle', 'draw',
        'layout', 'scroll', 'select', 'delete', 'cut', 'paste', 'undo', 'redo', 'order', 'center', 'zoom', 'accessibility', 'description', 'debugDescription', 'hash', 'class', 'superclass', 'pop', 'unhide',
        'unregister', 'register', 'set', 'push', 'terminate', 'exit', 'abort', 'activate', 'detach', 'sharedApplication', 'dragColor', 'unmount')


def main():
    classes, _ = H.parse_dir(os.path.join(REPO, 'mac-out', 'headers'))
    per = {}
    for cn, c in sorted(classes.items()):
        for (k, sel), m in c['methods'].items():
            if k == '+' and ':' not in sel and m.dep != 'D' and not sel.startswith(SKIP) and H.shape(m.ret) == '@':
                per.setdefault(cn, []).append(sel)
    src = ['#import <Cocoa/Cocoa.h>', '#include <objc/message.h>', '#include <unistd.h>',
           'int main(int argc, char **argv) { @autoreleasepool { if (argc < 2) return 1; [NSApplication sharedApplication]; setvbuf(stdout, NULL, _IOLBF, 0); alarm(8);']
    for cn, sels in per.items():
        src.append('if (!strcmp(argv[1], "%s")) { Class C = objc_getClass("%s"); if (!C) return 0;' % (cn, cn))
        for sel in sels:
            src.append('  if ([C respondsToSelector:@selector(%s)]) { @try { id v = ((id (*)(id, SEL))objc_msgSend)((id)C, @selector(%s)); printf("%s.%s\\t%%d\\n", v != nil); } @catch (id e) { printf("%s.%s\\t-1\\n"); } } else printf("%s.%s\\t-2\\n");' % (sel, sel, cn, sel, cn, sel, cn, sel))
        src.append('  return 0; }')
    src.append('return 0; } }')
    open('/tmp/probe_factories.m', 'w').write('\n'.join(src) + '\n')
    subprocess.check_call('scp -q /tmp/probe_factories.m mac:xef-remote/probe_factories.m && ssh mac "cd xef-remote && clang -fobjc-arc -w -framework Cocoa probe_factories.m -o probe_factories" && scp -q mac:xef-remote/probe_factories /tmp/probe_factories', shell=True)
    names = ' '.join(per)
    mac = subprocess.run('ssh mac \'cd xef-remote && for c in %s; do DISPLAY= ./probe_factories $c 2>/dev/null; done\'' % names, shell=True, capture_output=True, text=True).stdout.split('\n')
    xef = []
    for c in per:
        r = subprocess.run('timeout 40 %s/build/xef-osx -L %s/darwin-rootfs /tmp/probe_factories %s 2>/dev/null' % (REPO, REPO, c), shell=True, capture_output=True, text=True)
        xef += r.stdout.split('\n') if r.returncode == 0 else ['%s.CRASH\tx' % c]
    a, b = {l.split('\t')[0]: l for l in mac if l}, {l.split('\t')[0]: l for l in xef if l}
    diff = [(k, a.get(k), b.get(k)) for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)]
    for k, x, y in diff:
        print('mac: %-60s xef: %s' % (x, y))
    print('%d class getters compared, %d differ' % (len(a), len(diff)))


if __name__ == '__main__':
    main()
