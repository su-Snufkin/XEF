#!/usr/bin/env python3
"""Public Objective-C API of AppKit, read from its headers: one line per method,

    Class <TAB> + or - <TAB> selector <TAB> D (deprecated) or -

  tools/appkit_api.py mac-out/headers > mac-out/appkit_api.txt

Properties give their getter and setter; a class also gets the required members of the protocols it adopts (optional
members - delegates, data sources - are left out). The NSAccessibility protocols are skipped unless
WITH_ACCESSIBILITY=1. The parsing is tools/appkit_headers.py. Used by tools/appkit_gap.sh.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appkit_headers  # noqa: E402

classes, _ = appkit_headers.parse_dir(sys.argv[1])
for name, info in classes.items():
    for m in info['methods'].values():
        print('%s\t%s\t%s\t%s' % (name, m.kind, m.sel, m.dep))
