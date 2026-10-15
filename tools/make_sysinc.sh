#!/bin/bash
# Assembles ./sysinc on the remote Mac: the private/SPI headers of the Apple open-source projects laid out as
# an include tree (first writer wins), to be used as `-I $W/sysinc` before the SDK when building libSystem parts.
set -e
ssh mac 'bash -s' <<'REMOTE'
set -e
W=$HOME/xef-remote/src; O=$W/apple-oss; S=$W/sysinc
rm -rf $S; mkdir -p $S
cp_tree() { # src dest-subdir
  [ -d "$1" ] || return 0
  mkdir -p "$S/$2"
  rsync -a --ignore-existing --include='*/' --include='*.h' --include='*.defs' --include='*.inc' --exclude='*' "$1/" "$S/$2/"
}
cp_tree $O/xnu/libsyscall/os os
cp_tree $O/xnu/libsyscall/wrappers/libproc .
cp_tree $O/xnu/libsyscall/wrappers .
cp_tree $O/xnu/libkern/os os
cp_tree $O/xnu/libkern/libkern libkern
cp_tree $O/libplatform/private .
cp_tree $O/libplatform/include .
cp_tree $O/libplatform/internal .
cp_tree $O/libpthread/private .
cp_tree $O/libpthread/include .
cp_tree $O/libpthread/src/internal pthread
[ -d $O/Libc/include ] && rsync -a --ignore-existing --exclude='sys/' --include='*/' --include='*.h' --exclude='*' $O/Libc/include/ $S/
cp_tree $O/Libc/os os
cp_tree $O/Libc/libdarwin/h os
cp_tree $O/dyld/include .
cp_tree $O/dyld/common dyld
cp_tree $O/libmalloc/private .
cp_tree $O/libmalloc/include .
cp_tree $O/libdispatch/private .
cp_tree $O/libdispatch/dispatch dispatch
cp_tree $O/libdispatch/os os
cp_tree $O/libclosure .
cp_tree $W/avail-dst/usr/include .
cp_tree $W/avail-dst/usr/local/include .
mkdir -p $S/AppleFeatures && printf '#pragma once\n#define os_feature_enabled(a,b) 0\n#define os_feature_enabled_simple(a,b,c) (c)\n' > $S/AppleFeatures/AppleFeatures.h
mkdir -p $S/CrashReporterClient && cp $W/privinc/CrashReporterClient.h $S/CrashReporterClient.h 2>/dev/null || true
find $S -name '*.h' | wc -l
REMOTE
