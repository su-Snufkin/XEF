"""Reader for Apple's text-based stub files (.tbd v4 YAML and v5 JSON): what each library exports for arm64 macOS.

    for lib in tbd.read('Foo.tbd'):        # the main library and every inlined sub-library
        lib.install_name, lib.symbols, lib.classes, lib.reexports ...

Only what the stub generator needs is read; no YAML package is required.
"""
import json
import re

ARCHS = ('arm64-macos', 'arm64e-macos')


class Lib:
    def __init__(self):
        self.install_name = ''
        self.current = '1'
        self.compat = '1'
        self.symbols = set()       # '_name' (functions and data, undistinguished)
        self.weak = set()
        self.tlv = set()
        self.classes = set()       # 'Foo'
        self.ehtypes = set()       # 'Foo'
        self.ivars = set()         # 'Foo._bar'
        self.reexports = []        # install names of re-exported libraries
        self.reexported_symbols = set()   # names this library re-exports from elsewhere
        self.parent = ''           # umbrella framework, if any

    def __repr__(self):
        return '<Lib %s: %d symbols, %d classes>' % (self.install_name, len(self.symbols), len(self.classes))


def _mine(targets):
    return any(t in ARCHS for t in targets)


# --- v4: a small reader for the YAML subset TAPI writes -------------------------------------------------

_TOKEN = re.compile(r"'((?:[^']|'')*)'|\"((?:[^\"\\\\]|\\\\.)*)\"|([^,\[\]\s]+)")


def _flow_list(text):
    """'[ a, 'b', "c" ]' -> ['a', 'b', 'c']"""
    text = text.strip()
    if not text.startswith('['):
        return [_scalar(text)] if text else []
    return [q.replace("''", "'") if q else d or bare for q, d, bare in _TOKEN.findall(text[1:text.rindex(']')])]


def _scalar(text):
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in '\'"':
        return text[1:-1]
    return text


def _entries(doc):
    """Top-level 'key: value' pairs of one YAML document; a value keeps its continuation lines."""
    cur = None
    for line in doc.split('\n'):
        if not line.strip() or line.startswith('#'):
            continue
        m = re.match(r'([A-Za-z][\w-]*):(.*)$', line) if line[0].isalpha() else None
        if m:
            if cur:
                yield cur[0], '\n'.join(cur[1])
            cur = (m.group(1), [m.group(2)])
        elif cur:
            cur[1].append(line)
    if cur:
        yield cur[0], '\n'.join(cur[1])


def _items(block):
    """A block sequence of mappings ('  - key: value' ...) -> list of {key: raw value}."""
    items = []
    indent = 0
    parts = None
    for line in block.split('\n'):
        if not line.strip():
            continue
        m = re.match(r'\s*(-\s+)?([A-Za-z][\w-]*):(.*)$', line) if ':' in line else None
        if m and (m.group(1) or (items and len(line) - len(line.lstrip()) <= indent)):
            if m.group(1):
                items.append({})
                indent = line.index('-') + 2
            parts = items[-1][m.group(2)] = [m.group(3)]
        elif parts is not None:
            parts.append(line)
    return [{k: '\n'.join(v) for k, v in it.items()} for it in items]


def _read_v4(text):
    libs = []
    for doc in re.split(r'^--- !tapi-tbd[^\n]*$', text, flags=re.M)[1:]:
        doc = doc.split('\n...')[0]
        lib = Lib()
        fields = dict(_entries(doc))
        if 'targets' in fields and not _mine(_flow_list(fields['targets'])):
            continue
        lib.install_name = _scalar(fields.get('install-name', ''))
        lib.current = _scalar(fields.get('current-version', '1')) or '1'
        lib.compat = _scalar(fields.get('compatibility-version', '1')) or '1'
        for it in _items(fields.get('parent-umbrella', '')):
            if _mine(_flow_list(it.get('targets', '[]'))):
                lib.parent = _scalar(it.get('umbrella', ''))
        for it in _items(fields.get('reexported-libraries', '')):
            if _mine(_flow_list(it.get('targets', '[]'))):
                lib.reexports += _flow_list(it.get('libraries', '[]'))
        for section, into in (('exports', lib), ('reexports', None)):
            for it in _items(fields.get(section, '')):
                if not _mine(_flow_list(it.get('targets', '[]'))):
                    continue
                syms = _flow_list(it.get('symbols', '[]'))
                if into is None:
                    lib.reexported_symbols.update(syms)
                    lib.reexported_symbols.update('_OBJC_CLASS_$_' + c for c in _flow_list(it.get('objc-classes', '[]')))
                    continue
                lib.symbols.update(syms)
                weak = _flow_list(it.get('weak-symbols', '[]'))
                lib.symbols.update(weak)
                lib.weak.update(weak)
                tlv = _flow_list(it.get('thread-local-symbols', '[]'))
                lib.symbols.update(tlv)
                lib.tlv.update(tlv)
                lib.classes.update(_flow_list(it.get('objc-classes', '[]')))
                lib.ehtypes.update(_flow_list(it.get('objc-eh-types', '[]')))
                lib.ivars.update(_flow_list(it.get('objc-ivars', '[]')))
        if lib.install_name:
            libs.append(lib)
    return libs


# --- v5 (JSON) ------------------------------------------------------------------------------------------

def _read_v5(text):
    data = json.loads(text)
    libs = []
    for rec in [data.get('main_library')] + list(data.get('libraries', [])):
        if not rec:
            continue
        if not _mine([t.get('target', '') for t in rec.get('target_info', [])]):
            continue
        lib = Lib()

        def pick(key, field, default=''):
            for e in rec.get(key, []):
                if 'targets' not in e or _mine(e['targets']):
                    return e.get(field, default)
            return default
        lib.install_name = pick('install_names', 'name')
        lib.current = str(pick('current_versions', 'version', '1'))
        lib.compat = str(pick('compatibility_versions', 'version', '1'))
        lib.parent = pick('parent_umbrellas', 'umbrella')
        for e in rec.get('reexported_libraries', []):
            if 'targets' not in e or _mine(e['targets']):
                lib.reexports += e.get('names', [])
        for section in ('exported_symbols', 'reexported_symbols'):
            for e in rec.get(section, []):
                if 'targets' in e and not _mine(e['targets']):
                    continue
                for kind in ('text', 'data'):
                    k = e.get(kind, {})
                    if section == 'reexported_symbols':
                        lib.reexported_symbols.update(k.get('global', []))
                        lib.reexported_symbols.update('_OBJC_CLASS_$_' + c for c in k.get('objc_class', []))
                        continue
                    for f in ('global', 'weak', 'thread_local'):
                        lib.symbols.update(k.get(f, []))
                    lib.weak.update(k.get('weak', []))
                    lib.tlv.update(k.get('thread_local', []))
                    lib.classes.update(k.get('objc_class', []))
                    lib.ehtypes.update(k.get('objc_eh_type', []))
                    lib.ivars.update(k.get('objc_ivar', []))
        if lib.install_name:
            libs.append(lib)
    return libs


def read(path):
    with open(path, errors='replace') as f:
        text = f.read()
    return _read_v5(text) if text.lstrip().startswith('{') else _read_v4(text)
