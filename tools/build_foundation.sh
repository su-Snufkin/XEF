#!/bin/bash
# Builds Darling's Foundation (darlinghq/darling-foundation) for macOS arm64 on the remote Mac into ./darwin-rootfs.
# Needs tools/build_corefoundation.sh (headers/stubs in ~/xef-remote/src/cf-build) and the ICU build first.
set -e
cd "$(dirname "$0")/.."
scp -q tools/xbuild.py mac:xef-remote/xbuild.py
ssh mac 'mkdir -p ~/xef-remote/src/compat ~/xef-remote/src/foundation-extras'; rsync -a rootfs-src/compat/ mac:xef-remote/src/compat/; rsync -a rootfs-src/foundation/ mac:xef-remote/src/foundation-extras/
ssh mac 'bash -s' <<'REMOTE'
set -e
W=$HOME/xef-remote/src; D=$W/darling; CF=$D/corefoundation; FD=$D/foundation; B=$W/cf-build; FB=$W/fnd-build
mkdir -p $FB/obj; rm -rf $FB/obj/*
SRCS=$(python3 - <<'PY'
import re, os
t = open(os.environ['HOME'] + '/xef-remote/src/darling/foundation/CMakeLists.txt').read()
m = re.search(r'set\(foundation_sources(.*?)\n\)', t, re.S).group(1)
m = re.sub(r'#.*', '', m)
skip = ('NSXPC', 'PortCoder', 'NSMachBootstrapServer', 'NSTask.m', 'NSKeyValueObserving.m')
print(' '.join(('src/NSLog_xef.m' if x == 'src/NSLog.m' else x) for x in m.split() if x.endswith(('.m', '.c', '.mm')) and not x.startswith('$') and not any(k in x for k in skip)))
PY
)
cp $HOME/xef-remote/src/compat/xef_objc_msgsend.h $FB/
# NSLog goes to stderr with [pid:thread-id] like on macOS
sed -e 's/printf(/fprintf(stderr, /g' -e 's/uid_t uid = getuid();/unsigned long uid = (unsigned long)pthread_mach_thread_np(pthread_self());/' $FD/src/NSLog.m > $FD/src/NSLog_xef.m
cd $FD
FLAGS="-arch arm64 -mmacosx-version-min=12.0 -O2 -w -Wno-error -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types -fgnu89-inline -fblocks -fconstant-cfstrings -fexceptions -fobjc-exceptions -fno-objc-arc \
 -include libkern/OSAtomic.h -include $FB/xef_objc_msgsend.h -include $CF/CoreFoundation_Prefix.h -include $CF/macros.h -DDARLING=1 -D__BRIDGEOS_DEPRECATED(...)= -D__BRIDGEOS_AVAILABLE(...)= -D__BRIDGEOS_UNAVAILABLE= \
 -DNSBUILDINGFOUNDATION=1 -DINCLUDE_OBJC -DDEPLOYMENT_TARGET_MACOSX=1 -D__CONSTANT_CFSTRINGS__=1 -D__CONSTANT_STRINGS__=1 -DOBJC_OLD_DISPATCH_PROTOTYPES=1 -DU_DISABLE_RENAMING=1 -DDISPATCH_SUPPORT=1 \
 -I$CF -I$FD/include/Foundation -I$FD/src -I$FD/include -I$FD/internal_include -I$CF/include -I$CF/include/CoreFoundation -I$B/stub -I$B/inc -I$W/icu/inst/include -I$W/avail-dst/usr/include -I$W/avail-dst/usr/local/include"
XBUILD_VERBOSE= python3 $HOME/xef-remote/xbuild.py --out $FB/obj --cflags "$FLAGS -x objective-c" $SRCS || true
clang -arch arm64 -mmacosx-version-min=12.0 -O2 -w -fno-objc-arc -fobjc-exceptions -fblocks -I$FD/include -I$CF/include -I$B/stub -c $HOME/xef-remote/src/foundation-extras/extras.m -o $FB/obj/xef_extras.o 2>&1 | head -5
FW=$HOME/xef-remote/out/rootfs/System/Library/Frameworks/Foundation.framework/Versions/C
mkdir -p $FW
cd $FB/obj
clang -arch arm64 -mmacosx-version-min=12.0 -dynamiclib -install_name /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation \
  -Wl,-fixup_chains -Wl,-not_for_dyld_shared_cache -Wl,-compatibility_version,300 -Wl,-current_version,4040.1 \
  -L$HOME/xef-remote/out/rootfs/usr/lib -licucore.A -lobjc -lSystem \
  -Wl,-reexport_library,$HOME/xef-remote/out/rootfs/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation \
  -Wl,-undefined,dynamic_lookup *.o -o $FW/Foundation 2>&1 | grep -v warning | head -30
ls -la $FW/Foundation
REMOTE
