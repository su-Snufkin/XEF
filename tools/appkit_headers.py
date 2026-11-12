"""Typed reader for the public Objective-C API of a framework's headers (the AppKit headers of a macOS SDK).

    classes, protocols = appkit_headers.parse_dir('mac-out/headers')
    classes['NSView']['methods'][('-', 'setFrame:')]  ->  Method(kind, sel, ret, args, dep)

Types are kept as written (nullability, generics and availability macros removed). `shape(type)` reduces a type to the
ABI class the runtime needs: one character from SHAPES. A class also lists the required members of the protocols it
adopts (applications implement the optional ones: delegates, data sources).
"""
import collections
import glob
import os
import re

Method = collections.namedtuple('Method', 'kind sel ret args dep')

MACRO_NAMES = re.compile(r'^(API_\w+|NS_\w+|APPKIT_\w+|IB\w*|CF_\w+|__\w+|DEPRECATED\w*|UNAVAILABLE\w*|NSAppKitVersion\w*|AVAILABLE\w*)$')
NULLABILITY = re.compile(r'\b(_Nullable|_Nonnull|_Null_unspecified|nullable|nonnull|null_unspecified|__nullable|__nonnull|__kindof|__strong|__weak|'
                         r'__unsafe_unretained|__autoreleasing|NS_NOESCAPE|const|volatile|inout|in|out|bycopy|byref|oneway)\b')
STRUCTS = {'NSRect': 'R', 'CGRect': 'R', 'NSSize': 'S', 'CGSize': 'S', 'NSPoint': 'P', 'CGPoint': 'P', 'NSEdgeInsets': 'E',
           'NSDirectionalEdgeInsets': 'E', 'NSRange': 'N', 'CFRange': 'N'}
FOUR = {'int', 'unsigned int', 'unsigned', 'int32_t', 'uint32_t', 'OSStatus', 'CGDirectDisplayID', 'CGWindowID', 'GLint', 'GLuint', 'GLenum', 'u_int32_t',
        'NSWindowNumberListOptions_', 'CGGlyph_', 'UInt32', 'SInt32', 'CGWindowLevel'}
TWO = {'short', 'unsigned short', 'uint16_t', 'int16_t', 'unichar', 'UInt16', 'SInt16', 'NSUInteger16_'}
ONE = {'bool', 'BOOL', 'Boolean', '_Bool'}
DOUBLE = {'double', 'CGFloat', 'NSTimeInterval', 'CFTimeInterval', 'NSTimeInterval_'}
FLOAT = {'float', 'NSLayoutPriority', 'NSStackViewVisibilityPriority', 'NSWindowLevel_', 'NSLayoutPriorityValue_'}


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', text)


def balanced(s, i):
    """s[i] == '(': index just after the matching ')'"""
    depth = 0
    for j in range(i, len(s)):
        if s[j] == '(':
            depth += 1
        elif s[j] == ')':
            depth -= 1
            if depth == 0:
                return j + 1
    return len(s)


def drop_macros(s):
    """removes MACRO(...) groups and bare MACRO words"""
    out, i = [], 0
    while i < len(s):
        m = re.match(r'[A-Za-z_]\w*', s[i:])
        if m:
            word = m.group(0)
            j = i + len(word)
            k = j
            while k < len(s) and s[k] == ' ':
                k += 1
            if MACRO_NAMES.match(word):
                i = balanced(s, k) if k < len(s) and s[k] == '(' else j
                continue
            out.append(word); i = j
        else:
            out.append(s[i]); i += 1
    return ''.join(out)


def norm(t):
    t = drop_macros(t)
    t = NULLABILITY.sub(' ', t)
    t = re.sub(r'<[^<>]*(<[^<>]*>[^<>]*)*>', '', t)          # lightweight generics and protocol qualifiers
    t = re.sub(r'\b(struct|enum|union)\s+', '', t)
    return re.sub(r'\s+', ' ', t).strip()


def shape(t):
    """ABI class of a type: v void, B bool, c/s/i/q integers of 1/2/4/8 bytes, f float, d double, @ object,
    ^ pointer, : SEL, # Class, R/S/P/E/N the geometry structs; None when the type cannot be handled"""
    t = norm(t)
    if t == 'void':
        return 'v'
    if t in ONE:
        return 'B'
    if t in STRUCTS:
        return STRUCTS[t]
    if t in DOUBLE:
        return 'd'
    if t in FLOAT:
        return 'f'
    if t == 'SEL':
        return ':'
    if t == 'Class':
        return '#'
    if '(^' in t or t.endswith('^') or t == 'block':
        return '@'
    if t.endswith('*') or t.endswith('Ref') or t in ('id', 'instancetype') or re.match(r'^id\b', t):
        base = t.rstrip('* ').strip()
        return '^' if (base in ('void', 'char', 'unsigned char', 'uint8_t', 'int', 'unichar', 'CGFloat', 'double', 'float', 'NSUInteger', 'NSInteger') or t.endswith('Ref') or
                       base in ('NSRect', 'NSPoint', 'NSSize', 'NSRange', 'NSRectArray', 'NSPointPointer', 'NSRangePointer', 'NSPointArray', 'NSSizePointer', 'NSRectPointer', 'NSZone', 'NSInteger *') or
                       base.startswith(('CG', 'CF', 'CT', 'GL', 'IO', 'AU', 'MT', 'Audio', 'OS', 'UI'))) else '@'
    if t in FOUR:
        return 'i'
    if t in TWO:
        return 's'
    if t in ('char', 'signed char', 'unsigned char', 'uint8_t', 'int8_t'):
        return 'c'
    if t in ('NSPointPointer', 'NSRectPointer', 'NSRangePointer'):
        return '^'
    if re.match(r'^[A-Z]\w*$', t) and t.startswith(('NSAffineTransformStruct', 'CGAffineTransform', 'NSDirectionalRectEdge_', 'CGVector', 'NSAppKitStruct_')):
        return None
    return 'q'


def _split_statements(body):
    out, depth, cur = [], 0, []
    for ch in body:
        if ch in '({[':
            depth += 1
        elif ch in ')}]':
            depth -= 1
        if ch == ';' and depth == 0:
            out.append(''.join(cur)); cur = []
        else:
            cur.append(ch)
    return out


def _method(stmt):
    m = re.match(r'\s*([-+])\s*\(', stmt)
    if not m:
        return None
    kind = m.group(1)
    i = m.end() - 1
    j = balanced(stmt, i)
    ret = stmt[i + 1:j - 1]
    rest = stmt[j:]
    parts, args, pos = [], [], 0
    first = True
    while True:
        mm = re.match(r'\s*([A-Za-z_]\w*)', rest[pos:])
        if not mm:
            break
        name = mm.group(1)
        after = pos + mm.end()
        k = after
        while k < len(rest) and rest[k] == ' ':
            k += 1
        if k < len(rest) and rest[k] == ':':
            k += 1
            while k < len(rest) and rest[k] in ' \n':
                k += 1
            if k >= len(rest) or rest[k] != '(':
                return None
            e = balanced(rest, k)
            args.append(rest[k + 1:e - 1])
            parts.append(name + ':')
            n2 = re.match(r'\s*[A-Za-z_]\w*', rest[e:])
            pos = e + (n2.end() if n2 else 0)
            first = False
            continue
        if first and not MACRO_NAMES.match(name):
            parts.append(name)
        break
    if not parts or re.search(r',\s*\.\.\.', rest):
        return None
    dep = 'D' if re.search(r'DEPRECATED|UNAVAILABLE', stmt) else '-'
    return Method(kind, ''.join(parts), ret, args, dep)


def _property(stmt):
    m = re.match(r'\s*@property\s*', stmt)
    if not m:
        return []
    rest = stmt[m.end():]
    attrs = ''
    if rest.startswith('('):
        e = balanced(rest, 0)
        attrs = rest[1:e - 1]
        rest = rest[e:]
    dep = 'D' if re.search(r'DEPRECATED|UNAVAILABLE', rest) else '-'
    rest = drop_macros(rest)
    blk = re.search(r'\(\s*\^\s*(?:_Nullable\s+|_Nonnull\s+|nullable\s+)?([A-Za-z_]\w*)\s*\)', rest)
    if blk:
        name, typ = blk.group(1), 'block'
    else:
        rest = re.sub(r'\[[^\]]*\]', '', rest).strip()
        mm = re.search(r'([A-Za-z_]\w*)\s*$', rest)
        if not mm:
            return []
        name, typ = mm.group(1), rest[:mm.start()]
    kind = '+' if re.search(r'\bclass\b', attrs) else '-'
    g = re.search(r'getter\s*=\s*(\w+)', attrs)
    out = [Method(kind, g.group(1) if g else name, typ, [], dep)]
    if not re.search(r'\breadonly\b', attrs):
        s = re.search(r'setter\s*=\s*(\w+:)', attrs)
        out.append(Method(kind, s.group(1) if s else 'set' + name[0].upper() + name[1:] + ':', 'void', [typ], dep))
    return out


def members(body):
    for stmt in _split_statements(body):
        stmt = stmt.strip()
        if not stmt:
            continue
        stmt = re.sub(r'@(optional|required)', '', stmt).strip()
        starts = list(re.finditer(r'(?m)^\s*(@property\b|[-+]\s*\()', stmt))
        if starts:
            stmt = stmt[starts[-1].start():].strip()       # a line of macro text without ';' can precede the declaration
        if stmt.startswith('@property'):
            yield from _property(stmt)
        elif stmt[:1] in '-+':
            m = _method(stmt)
            if m:
                yield m


def parse_dir(path):
    texts = []
    for p in sorted(glob.glob(os.path.join(path, '*.h'))):
        with open(p, errors='replace') as f:
            texts.append(strip_comments(f.read()))
    protocols = {}
    for text in texts:
        for m in re.finditer(r'@protocol\s+(\w+)[^\n;]*\n(.*?)\n\s*@end', text, flags=re.S):
            required = re.split(r'@optional', m.group(2))[0]
            protocols.setdefault(m.group(1), []).extend(members(required))
    classes = collections.OrderedDict()
    for text in texts:
        for m in re.finditer(r'@interface\s+(\w+)\s*(:\s*(\w+))?([^\n]*)\n(.*?)\n\s*@end', text, flags=re.S):
            name, sup, head, body = m.group(1), m.group(3), m.group(4), m.group(5)
            c = classes.setdefault(name, {'super': None, 'methods': collections.OrderedDict()})
            if sup and not c['super']:
                c['super'] = sup
            if body.lstrip().startswith('{'):
                body = body[balanced_brace(body) :]
            adopted = re.search(r'<([^>]*)>', head)
            found = list(members(body))
            for proto in re.findall(r'\w+', adopted.group(1)) if adopted else []:
                if proto.startswith('NSAccessibility') and not os.environ.get('WITH_ACCESSIBILITY'):
                    continue
                found += protocols.get(proto, [])
            for meth in found:
                c['methods'].setdefault((meth.kind, meth.sel), meth)
    return classes, protocols


def balanced_brace(s):
    depth = 0
    for i, ch in enumerate(s):
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return i + 1
    return len(s)
