#!/bin/bash
# Builds Apple's open-source objc4 (apple-oss-distributions/objc4, tag objc4-951.1) as
# /usr/lib/libobjc.A.dylib for macOS arm64 on the remote Mac (see CLAUDE.local.md) and installs it
# into ./darwin-rootfs.  Private headers come from other apple-oss-distributions repos (xnu, Libc,
# libplatform, libpthread, dyld, libmalloc), fetched by tools/fetch_private_headers.py.
set -e
cd "$(dirname "$0")/.."
scp -q tools/fetch_private_headers.py mac:xef-remote/fetchhdr.py
ssh mac 'bash -s' <<'REMOTE'
set -e
W=$HOME/xef-remote/src
mkdir -p $W/apple-oss $W/darling $W/privinc/System $W/privinc/Rosetta
cd $W/apple-oss
for r in xnu Libc libplatform libpthread dyld libmalloc libdispatch libclosure Libsystem; do
  test -d $r || git clone -q --depth 1 https://github.com/apple-oss-distributions/$r.git
done
cd $W/darling
test -d objc4-apple || git clone -q --depth 1 https://github.com/apple-oss-distributions/objc4.git objc4-apple
ln -sfn $W/darling/objc4-apple/runtime $W/privinc/objc
cd objc4-apple/runtime
echo '#include <pthread/tsd_private.h>' > $W/privinc/System/pthread_machdep.h
test -f $W/privinc/objc-probes.h || dtrace -h -s objc-probes.d -o $W/privinc/objc-probes.h
python3 $HOME/xef-remote/fetchhdr.py $(ls *.mm *.m) 2>&1 | grep -E "NOTFOUND|copied" || true
python3 - <<'PY'
# dyld_platform_version_* constants (generated from AvailabilityVersions in the real SDK build)
out = ['#pragma once', '#include <stdint.h>']
def enc(a, b=0, c=0): return (a << 16) | (b << 8) | c
plats = {'macOS': (range(10, 27), 1), 'iOS': (range(2, 27), 2), 'tvOS': (range(9, 27), 3), 'watchOS': (range(1, 27), 4), 'bridgeOS': (range(1, 11), 5)}
for name, _ in plats.items():
    majors = _[0]
    for M in majors:
        for m in (range(0, 17) if name == 'macOS' and M == 10 else range(0, 8)):
            out.append('#ifndef dyld_platform_version_%s_%d_%d\n#define dyld_platform_version_%s_%d_%d ((dyld_build_version_t){%d, 0x%x})\n#endif' % (name, M, m, name, M, m, _[1], enc(M, m)))
import re, glob
for f in glob.glob(__import__('os').environ['HOME'] + '/xef-remote/src/darling/objc4-apple/runtime/*.m*'):
    for n in set(re.findall(r'\bdyld_[a-z]+_20[0-9][0-9]_os_versions\b', open(f, errors='replace').read())):
        out.append('#ifndef %s\n#define %s ((dyld_build_version_t){1, 0x%x})\n#endif' % (n, n, enc(11, 0)))
open(__import__('os').environ['HOME'] + '/xef-remote/src/privinc/dyld_versions.h', 'w').write('\n'.join(out) + '\n')
PY
# bridgeos annotations do not exist in this SDK's availability macros
for h in $(grep -rl bridgeos $W/privinc 2>/dev/null); do python3 - "$h" <<'PY'
import re, sys
t = open(sys.argv[1], errors='replace').read()
t = re.sub(r',\s*bridgeos(\([^)]*\))?', '', t)
t = re.sub(r'bridgeos(\([^)]*\))?\s*,\s*', '', t)
open(sys.argv[1], 'w').write(t)
PY
done
printf '#pragma once\n#define os_feature_enabled_simple(d, f, def) (def)\n' > $W/privinc/os/feature_private.h
printf '#pragma once\n#define SANDBOX_FILTER_PATH 1\nstatic inline int sandbox_check(int pid, const char *op, int type, ...) { return 0; }\n' > $W/privinc/sandbox/private.h
cat > $W/privinc/Rosetta/Traps.h <<'EOF2'
#pragma once
#include <stdbool.h>
extern bool rosetta_is_current_process_translated(void) __attribute__((weak_import));
EOF2
OUT=$W/objc-build; rm -rf $OUT; mkdir -p $OUT
FLAGS="-include $W/privinc/dyld_versions.h -DTARGET_OS_SIMULATOR=1 -arch arm64 -mmacosx-version-min=11.0 -O2 -w -DNDEBUG -DOBJC_PORT -DTARGET_OS_EXCLAVEKIT=0 -D__BRIDGEOS_DEPRECATED(...)= -D__BRIDGEOS_AVAILABLE(...)= -D__BRIDGEOS_UNAVAILABLE= -I. -Iisa -I.. -I$W/privinc -fvisibility-inlines-hidden -fno-rtti -fno-exceptions -fblocks"
fail=0
for f in *.mm *.m Messengers.subproj/objc-msg-arm64.s objc-blocktramps-arm64.s objc-sel-table.s retain-release-helpers-arm64.s; do
  case $f in objc-test-env.c|dummy*) continue;; esac
  o=$OUT/$(basename $f).o
  case $f in
    *.mm) clang++ -std=gnu++20 $FLAGS -c $f -o $o ;;
    *.m)  clang $FLAGS -c $f -o $o ;;
    *.s)  clang -arch arm64 -mmacosx-version-min=11.0 -c -I. -I$W/privinc -DNDEBUG -UTARGET_OS_SIMULATOR -DTARGET_OS_SIMULATOR=1 $f -o $o ;;
  esac 2>$OUT/$(basename $f).err || { echo "COMPILE FAIL $f"; head -5 $OUT/$(basename $f).err; fail=1; }
done
[ $fail = 0 ]
mkdir -p $HOME/xef-remote/out/rootfs/usr/lib
clang++ -arch arm64 -dynamiclib -mmacosx-version-min=11.0 -install_name /usr/lib/libobjc.A.dylib -compatibility_version 1.0.0 -current_version 951.1.0 \
  -nostdlib++ -Wl,-sectalign,__DATA,__objc_data,0x1000 -Wl,-rename_section,__DATA,__mod_init_func,__DATA,__objc_init_func \
  $OUT/*.o -lc++ -lSystem -Wl,-not_for_dyld_shared_cache -Wl,-undefined,dynamic_lookup -o $HOME/xef-remote/out/rootfs/usr/lib/libobjc.A.dylib
clang -arch arm64 -mmacosx-version-min=11.0 -dynamiclib -install_name /usr/lib/libobjc-trampolines.dylib -Wl,-not_for_dyld_shared_cache \
  -I. -DNDEBUG -UTARGET_OS_SIMULATOR -DTARGET_OS_SIMULATOR=1 objc-blocktramps-arm64.s -nostdlib -lSystem -o $HOME/xef-remote/out/rootfs/usr/lib/libobjc-trampolines.dylib 2>&1 | grep -v warning || true
otool -L $HOME/xef-remote/out/rootfs/usr/lib/libobjc.A.dylib
REMOTE
mkdir -p darwin-rootfs/usr/lib
rsync -a mac:xef-remote/out/rootfs/usr/lib/libobjc.A.dylib mac:xef-remote/out/rootfs/usr/lib/libobjc-trampolines.dylib darwin-rootfs/usr/lib/
ln -sf libobjc.A.dylib darwin-rootfs/usr/lib/libobjc.dylib
