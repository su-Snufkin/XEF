#!/bin/bash
# Builds Darling's CoreFoundation (darlinghq/darling-corefoundation: Apple CF + the NS* toll-free-bridging
# classes) for macOS arm64 on the remote Mac into ./darwin-rootfs (CoreFoundation.framework layout).
set -e
cd "$(dirname "$0")/.."
scp -q tools/xbuild.py mac:xef-remote/xbuild.py
ssh mac 'bash -s' <<'REMOTE'
set -e
W=$HOME/xef-remote/src; D=$W/darling; CF=$D/corefoundation; B=$W/cf-build; SDK=$(xcrun --show-sdk-path)
mkdir -p $B/obj $B/inc/CoreFoundation; rm -rf $B/obj/*
cp $CF/*.h $B/inc/CoreFoundation/ 2>/dev/null || true
mkdir -p $B/inc/dispatch $B/inc/os $B/stub/AE
cat > $B/stub/AE/AE.h <<'EOF2'
#pragma once
#include <MacTypes.h>
typedef int AEEventClass; typedef int AEEventID; typedef int AEReturnID; typedef UInt32 AEKeyword; typedef int AETransactionID; typedef int DescType;
struct AEDesc { DescType descriptorType; void *dataHandle; }; typedef struct AEDesc AEDesc; typedef AEDesc AppleEvent;
EOF2
cp $W/apple-oss/libclosure/Block_private.h $B/stub/
mkdir -p $B/stub/mach-o $B/stub/CoreServices $B/stub/unicode $B/stub/pthread $B/patched
cp $W/privinc/mach-o/dyld_priv.h $B/stub/mach-o/ 2>/dev/null || true
(rmdir $B/stub/objc 2>/dev/null || true); ln -sfn $W/darling/objc4-apple/runtime $B/stub/objc
cp $W/apple-oss/libpthread/private/pthread/*.h $B/stub/pthread/ 2>/dev/null || true
cp $W/apple-oss/libpthread/private/*.h $B/stub/ 2>/dev/null || true
sed -i '' -E 's/, *bridgeos(\([^)]*\))?//g; s/, *driverkit//g; s/, *xros\([^)]*\)(\([^)]*\))?//g' $B/stub/pthread/*.h 2>/dev/null || true
printf '#pragma once\n#include <CoreFoundation/CoreFoundation.h>\ntypedef void *FSRefPtr;\ntypedef const void *ConstFSRefPtr;\n' > $B/stub/CoreServices/FileManager.h
printf '#pragma once\n#include <unicode/uloc.h>\n#define UADATPG_FORCE_12_HOUR_CYCLE 0x4000\n#define UADATPG_FORCE_24_HOUR_CYCLE 0x8000\n' > $B/stub/unicode/ualoc.h
cat > $B/stub/bootstrap_priv.h <<'EOF2'
#pragma once
#include <mach/mach.h>
#include <servers/bootstrap.h>
#define BOOTSTRAP_PER_PID_SERVICE 0x10
EOF2
cat > $B/stub/vproc_priv.h <<'EOF2'
#pragma once
#include <stdint.h>
#include <stdbool.h>
typedef void *vproc_err_t;
#define VPROC_GSK_IS_MANAGED 1
static inline vproc_err_t vproc_swap_integer(void *v, int k, int64_t *in, int64_t *out) { if (out) *out = 0; return 0; }
static inline void _vproc_transaction_begin(void) {} static inline void _vproc_transaction_end(void) {} static inline void _vproc_transactions_enable(void) {}
static inline void _vproc_transaction_try_exit(int s) {} static inline size_t _vproc_transaction_count(void) { return 0; }
EOF2
printf '#pragma once\n' > $B/stub/vproc.h
sed -E 's/objc_msgSend\(objc_msgSend\(clsDict, selAlloc\), selInit\)/((id(*)(id,SEL))objc_msgSend)(((id(*)(id,SEL))objc_msgSend)((id)clsDict, selAlloc), selInit)/; s/objc_msgSend\(objc_msgSend\(clsArray, selAlloc\), selInit\)/((id(*)(id,SEL))objc_msgSend)(((id(*)(id,SEL))objc_msgSend)((id)clsArray, selAlloc), selInit)/' $CF/CFRuntime.c > $CF/CFRuntime_xef.c
sed 's/    Class cls = objc_getClass(sup);/    if (objc_getClass(name)) return YES;\n    Class cls = objc_getClass(sup);/' $CF/NSBlock.m > $CF/NSBlock_xef.m
cp $W/apple-oss/libdispatch/dispatch/*.h $B/inc/dispatch/; cp $W/apple-oss/libdispatch/private/*.h $B/inc/dispatch/
cp $W/apple-oss/libdispatch/os/*.h $B/inc/os/ 2>/dev/null || true
sed -i '' -E 's/, *driverkit//g; s/driverkit, *//g; s/, *xros\([^)]*\)//g' $B/inc/dispatch/*.h $B/inc/os/*.h 2>/dev/null || true
SRCS=$(B=$B python3 - <<'PY'
import re, os
t = open(os.environ['HOME'] + '/xef-remote/src/darling/corefoundation/CMakeLists.txt').read()
c = re.search(r'set\(cf_c_sources(.*?)\n\)', t, re.S).group(1).split()
m = re.search(r'set\(cf_sources(.*?)\n\)', t, re.S).group(1)
m = [x for x in re.sub(r'#.*', '', m).split() if x.endswith(('.m', '.S')) and not x.startswith('$') and 'x86' not in x and 'ForwardingPrep' not in x]
print(' '.join(("CFRuntime_xef.c" if x == "CFRuntime.c" else "NSBlock_xef.m" if x == "NSBlock.m" else x) for x in c + m) + ' ' + os.environ['B'] + '/patched/arm64_stubs.c')
PY
)
cat > $B/patched/arm64_stubs.c <<'EOF2'
#include <stdlib.h>
#include <stdio.h>
// NSInvocation-style message forwarding trampolines are not ported to arm64 yet
void _CF_forwarding_prep_0(void) { fprintf(stderr, "CoreFoundation: message forwarding is not supported on arm64 yet\n"); abort(); }
void _CF_forwarding_prep_1(void) { _CF_forwarding_prep_0(); }
void _CF_forwarding_prep_b(void) { _CF_forwarding_prep_0(); }
void __invoke__(void) { _CF_forwarding_prep_0(); }
EOF2
cd $CF
FLAGS="-arch arm64 -mmacosx-version-min=12.0 -O2 -w -Wno-error -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types -fgnu89-inline -fblocks -fconstant-cfstrings -fexceptions -fobjc-exceptions -include libkern/OSAtomic.h -include $CF/CoreFoundation_Prefix.h -include $CF/macros.h \
 -DDARLING=1 -D__BRIDGEOS_DEPRECATED(...)= -D__BRIDGEOS_AVAILABLE(...)= -D__BRIDGEOS_UNAVAILABLE= -DCF_BUILDING_CF -DDEPLOYMENT_TARGET_MACOSX=1 -DU_SHOW_DRAFT_API=1 -DU_SHOW_CPLUSPLUS_API=0 -DINCLUDE_OBJC -DDISPATCH_SUPPORT=1 -D__CONSTANT_CFSTRINGS__=1 -D__CONSTANT_STRINGS__=1 -DU_DISABLE_RENAMING=1 -DOBJC_OLD_DISPATCH_PROTOTYPES=1 -Dmarg_list=void* -DUADATPG_FORCE_12_HOUR_CYCLE=0x4000 -DUADATPG_FORCE_24_HOUR_CYCLE=0x8000 -DCF_BUILDING_CF_STATIC=0 \
 -I$CF/include -I$CF/include/CoreFoundation -I$B/stub -I$D/foundation/include -I$D/foundation/internal_include -I$CF -I$B/inc -I$D/foundation/src -I$W/icu/inst/include -I$W/avail-dst/usr/include -I$W/avail-dst/usr/local/include -idirafter $W/apple-oss/xnu/osfmk -idirafter $W/apple-oss/xnu/libsyscall"
XBUILD_VERBOSE=1 python3 $HOME/xef-remote/xbuild.py --out $B/obj --cflags "$FLAGS -x objective-c" --sflags "-arch arm64 -I$CF" $SRCS || true
FW=$HOME/xef-remote/out/rootfs/System/Library/Frameworks/CoreFoundation.framework/Versions/A
mkdir -p $FW $FW/Resources
cd $B/obj
clang -arch arm64 -mmacosx-version-min=12.0 -dynamiclib -install_name /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation \
  -Wl,-fixup_chains -Wl,-not_for_dyld_shared_cache -Wl,-init,___CFInitialize -Wl,-compatibility_version,150 -Wl,-current_version,1153.18 \
  -Wl,-alias_list,$CF/SymbolAliases -Wl,-alias,'_OBJC_CLASS_$___NSCFConstantString',___CFConstantStringClassReference \
  -Wl,-sectcreate,__UNICODE,__csbitmaps,$CF/CFCharacterSetBitmaps.bitmap -Wl,-sectcreate,__UNICODE,__properties,$CF/CFUniCharPropertyDatabase.data \
  -Wl,-sectcreate,__UNICODE,__data,$CF/CFUnicodeData-L.mapping -Wl,-segprot,__UNICODE,r,r \
  -L$HOME/xef-remote/out/rootfs/usr/lib -licucore.A -lobjc -lSystem -Wl,-undefined,dynamic_lookup *.o -o $FW/CoreFoundation 2>&1 | grep -v warning | head -30
ls -la $FW/CoreFoundation
REMOTE
