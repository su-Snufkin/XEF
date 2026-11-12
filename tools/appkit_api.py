#!/usr/bin/env python3
"""Public Objective-C API of a framework, read from its headers: one line per method,

    Class <TAB> + or - <TAB> selector <TAB> D (deprecated) or -

  tools/appkit_api.py mac-out/headers > mac-out/appkit_api.txt

Properties give their getter and setter. A class also gets the required members of the protocols it adopts;
optional protocol members (delegates, data sources) are left out: applications implement those. Used by
tools/appkit_gap.sh to list what AppKit-lite does not implement.
"""
import glob
import os
import re
import sys


def strip_parens(s):
    """removes every balanced (...) group"""
    out, depth = [], 0
    for ch in s:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth = max(0, depth - 1)
        elif depth == 0:
            out.append(ch)
    return ''.join(out)


MACRO = re.compile(r'^(API_|NS_|APPKIT_|IB|CF_|__|DEPRECATED|UNAVAILABLE)')


def members(body, emit_member):
    """methods and properties declared in the body of an @interface or @protocol"""
    for d in re.finditer(r'(?m)^\s*([-+])\s*(\([^;]*?);', body):
        decl = d.group(2)
        dep = 'D' if 'DEPRECATED' in decl or 'UNAVAILABLE' in decl else '-'
        flat = strip_parens(decl)
        parts = re.findall(r'(\w+)\s*:', flat)
        if parts:
            sel = ''.join(p + ':' for p in parts)
        else:
            ids = [t for t in re.findall(r'\w+', flat) if not MACRO.match(t)]
            if not ids:
                continue
            sel = ids[0]
        emit_member(d.group(1), sel, dep)
    for p in re.finditer(r'(?m)^\s*@property\s*(\([^)]*\))?([^;]*);', body):
        attrs, decl = p.group(1) or '', p.group(2)
        dep = 'D' if 'DEPRECATED' in decl or 'UNAVAILABLE' in decl else '-'
        blk = re.search(r'\(\s*\^\s*(?:_Nullable\s+|_Nonnull\s+)?(\w+)\s*\)', decl)
        if blk:
            name = blk.group(1)
        else:
            ids = [t for t in re.findall(r'\w+', strip_parens(decl)) if not MACRO.match(t)]
            if not ids:
                continue
            name = ids[-1]
        kind = '+' if re.search(r'\bclass\b', attrs) else '-'
        g = re.search(r'getter\s*=\s*(\w+)', attrs)
        emit_member(kind, g.group(1) if g else name, dep)
        if not re.search(r'\breadonly\b', attrs):
            st = re.search(r'setter\s*=\s*(\w+:)', attrs)
            emit_member(kind, st.group(1) if st else 'set' + name[0].upper() + name[1:] + ':', dep)


def clean(text):
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', text)


def protocols(text, table):
    """protocol name -> its required members (what a class adopting it has to implement)"""
    for m in re.finditer(r'@protocol\s+(\w+)[^\n;]*\n(.*?)\n\s*@end', clean(text), flags=re.S):
        required = re.split(r'@optional', m.group(2))[0]
        members(required, lambda kind, sel, dep, name=m.group(1): table.setdefault(name, []).append((kind, sel, dep)))


def parse(text, emit, table):
    text = clean(text)
    for m in re.finditer(r'@interface\s+(\w+)([^\n]*)\n(.*?)\n\s*@end', text, flags=re.S):
        cls, head, body = m.group(1), m.group(2), m.group(3)
        body = re.sub(r'\{[^{}]*\}', ' ', body, count=1) if body.lstrip().startswith('{') else body
        members(body, lambda kind, sel, dep: emit(cls, kind, sel, dep))
        adopted = re.search(r'<([^>]*)>', head)
        for proto in re.findall(r'\w+', adopted.group(1)) if adopted else []:
            for kind, sel, dep in table.get(proto, []):
                emit(cls, kind, sel, dep)


def main():
    seen = set()

    def emit(cls, kind, sel, dep):
        if (cls, kind, sel) not in seen:
            seen.add((cls, kind, sel))
            print('%s\t%s\t%s\t%s' % (cls, kind, sel, dep))
    texts = []
    for path in sorted(glob.glob(os.path.join(sys.argv[1], '*.h'))):
        with open(path, errors='replace') as f:
            texts.append(f.read())
    table = {}
    for t in texts:
        protocols(t, table)
    for t in texts:
        parse(t, emit, table)


if __name__ == '__main__':
    main()
