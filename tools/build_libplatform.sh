#!/bin/bash
# libsystem_platform (apple-oss-distributions/libplatform): string/memory primitives, setjmp, atomics,
# os_unfair_lock, ucontext, ... built for macOS arm64 on the remote Mac into ./darwin-rootfs.
set -e
cd "$(dirname "$0")/.."
scp -q tools/xbuild.py mac:xef-remote/xbuild.py
ssh mac 'bash -s' <<'REMOTE'
set -e
W=$HOME/xef-remote/src; P=$W/apple-oss/libplatform; B=$W/libplat; AV=$W/avail-dst
mkdir -p $B/obj; rm -rf $B/obj/*
cd $P
SRCS="src/init.c src/atomics/arm64/OSAtomic.c src/atomics/init.c src/atomics/common/MKGetTimeBaseInfo.c src/cachecontrol/arm64/cache.s \
 src/os/alloc_once.c src/os/atomic.c src/os/lock.c src/os/semaphore.c src/os/apt_private.c src/os/script_config.c src/os/security_config.c \
 src/setjmp/arm64/setjmp.s src/simple/asl.c src/simple/getenv.c src/simple/log_simple.c src/simple/string_io.c \
 $(ls src/string/generic/*.c) src/timingsafe/arm64/timingsafe.c $(ls src/ucontext/arm64/*.s src/ucontext/arm64/*.c src/ucontext/generic/*.c)"
SRCS=$(for f in $SRCS; do [ -f $f ] && echo $f; done)
FLAGS="-arch arm64 -mmacosx-version-min=12.0 -O2 -w -Wno-error -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types -fno-stack-protector -fdollars-in-identifiers -fno-common -DPRIVATE=1 -D__APPLE_API_PRIVATE=1 -D_FORTIFY_SOURCE=0 -DCONFIG_MTE=0 -DOSATOMIC_USE_INLINED=0 -DOSATOMIC_DEPRECATED=0 -DOSSPINLOCK_USE_INLINED=1 -DOS_UNFAIR_LOCK_INLINE=0 -DVARIANT_DYLD=0 \
 -I$W/sysinc -I$P/private -I$P/include -I$P/internal -I$P/src -I$P/src/os -I$P/src/setjmp/arm64 -I$P/src/ucontext/arm64 -I$P/src/os/resolver -I$W/apple-oss/xnu/libsyscall/os -I$W/apple-oss/xnu/bsd -I$W/apple-oss/xnu/osfmk -I$W/apple-oss/xnu/libkern -I$W/libsys/mig_hdr/include"
XBUILD_VERBOSE=1 python3 $HOME/xef-remote/xbuild.py --out $B/obj --cflags "$FLAGS -std=gnu11 -include stddef.h -include stdatomic.h" --sflags "-arch arm64 -DPRIVATE=1 -I$W/sysinc -I$P/private -I$P/include -I$P/internal -I$P/src -I$P/src/ucontext/arm64 -I$P/src/setjmp/arm64 -I$W/apple-oss/xnu/osfmk -I$W/apple-oss/xnu/bsd" $SRCS || true
mkdir -p $HOME/xef-remote/out/rootfs/usr/lib/system
cd $B/obj
clang -arch arm64 -mmacosx-version-min=12.0 -dynamiclib -nostdlib -install_name /usr/lib/system/libsystem_platform.dylib \
  -Wl,-fixup_chains -Wl,-not_for_dyld_shared_cache -Wl,-undefined,dynamic_lookup \
  *.o -o $HOME/xef-remote/out/rootfs/usr/lib/system/libsystem_platform.dylib 2>&1 | grep -v warning | head -20
nm -u $HOME/xef-remote/out/rootfs/usr/lib/system/libsystem_platform.dylib | sort -u | tr '\n' ' ' | head -c 1500; echo
REMOTE
mkdir -p darwin-rootfs/usr/lib/system
rsync -a mac:xef-remote/out/rootfs/usr/lib/system/libsystem_platform.dylib darwin-rootfs/usr/lib/system/
