#!/bin/bash
# Builds libsystem_kernel (xnu/libsyscall: BSD syscall stubs, Mach traps, MIG client stubs) for macOS arm64
# on the remote Mac from apple-oss-distributions/xnu.  The result runs under xef-osx on top of the XNU
# syscall/trap emulation in src/os/darwin/.
set -e
cd "$(dirname "$0")/.."
scp -q tools/xbuild.py mac:xef-remote/xbuild.py
ssh mac 'bash -s' <<'REMOTE'
set -e
W=$HOME/xef-remote/src; LS=$W/apple-oss/xnu/libsyscall; B=$W/libsys; SDK=$(xcrun --show-sdk-path)
mkdir -p $B/sys $B/mig $B/obj $B/hdr
rm -rf $B/obj/* $B/mig/*
cd $LS
ARCHS=arm64 ./xcodescripts/create-syscalls.pl ../bsd/kern/syscalls.master custom Platforms MacOSX $B/sys >/dev/null
# MIG client stubs
for d in clock clock_priv clock_reply exc host_priv host_security mach_eventlink mach_host mach_port mach_vm mach_voucher memory_entry notify processor processor_set restartable task thread_act vm_map; do
  src=mach/$d.defs; [ -f $src ] || src=../osfmk/mach/$d.defs
  mig -arch arm64 -cc clang -novouchers -DKOBJECT_SERVER -I$SDK/usr/include -I$W/apple-oss/xnu/osfmk -I$W/apple-oss/xnu/bsd \
      -user $B/mig/${d}User.c -server /dev/null -header $B/mig/$d.h -sheader /dev/null $src 2>&1 | grep -v "^$" || true
done
# public / internal MIG headers (see xcodescripts/mach_install_mig.sh)
mkdir -p $B/mig_hdr/include/mach $B/mig_hdr/local/include/mach $B/internal_hdr/include/mach $B/mig_hdr/include/servers
for d in clock clock_priv clock_reply exc host_priv host_security mach_eventlink mach_host mach_port mach_voucher memory_entry processor processor_set task thread_act vm_map mach_vm; do
  src=mach/$d.defs; [ -f $src ] || src=../osfmk/mach/$d.defs
  mig -novouchers -arch armv7 -cc clang -header $B/mig_hdr/include/mach/$d.h -DLIBSYSCALL_INTERFACE -I../osfmk -I$SDK/usr/include /dev/null $src >/dev/null 2>&1 || \
  mig -novouchers -arch armv7 -cc clang -header $B/mig_hdr/include/mach/$d.h -DLIBSYSCALL_INTERFACE -I../osfmk $src 2>&1 | head -3
  awk -f xcodescripts/filter_mig.awk mach/add_attributes_to_mig.txt $B/mig_hdr/include/mach/$d.h > $B/mig_hdr/include/mach/$d.tmp 2>/dev/null && mv $B/mig_hdr/include/mach/$d.tmp $B/mig_hdr/include/mach/$d.h || true
done
for d in mach_port mach_vm task thread_act vm_map; do
  mig -novouchers -arch armv7 -cc clang -header $B/internal_hdr/include/mach/${d}_internal.h -I../osfmk mach/$d.defs 2>&1 | head -3
done
cp mach/servers/*.h $B/mig_hdr/include/servers/ 2>/dev/null || true
mig -novouchers -arch armv7 -cc clang -header $B/mig_hdr/include/servers/netname.h -I../osfmk mach/servers/netname.defs 2>&1 | head -3
# source list: what the Xcode project compiles for the static library
python3 - <<'PY' > $B/sources.txt
import re, os
txt = open(os.environ['HOME'] + '/xef-remote/src/apple-oss/xnu/libsyscall/Libsyscall.xcodeproj/project.pbxproj').read()
names = sorted(set(re.findall(r'([A-Za-z_0-9.+-]+\.(?:c|s)) in Sources', txt)))
root = os.environ['HOME'] + '/xef-remote/src/apple-oss/xnu/libsyscall'
idx = {}
for dp, dn, fn in os.walk(root):
    for f in fn: idx.setdefault(f, []).append(os.path.join(dp, f))
for n in names:
    for p in idx.get(n, [])[:1]:
        if 'Platforms' in p and 'MacOSX/arm64' not in p: continue
        if any(x in p for x in ('/skywalk/', 'exclaves.c', 'nfsclnt.c', 'vm_reclaim.c', 'sigsuspend-cancel.c')): continue
        print(p)
PY
ls $B/sys/*.s $B/mig/*User.c > $B/gen.txt
echo "$(wc -l < $B/sources.txt) project sources, $(wc -l < $B/gen.txt) generated"
AV=$W/avail-dst
FLAGS="-arch arm64 -I$AV/usr/include -I$AV/usr/local/include -mmacosx-version-min=12.0 -O2 -w -Wno-error -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types -fno-stack-protector -fno-builtin-calloc -fdollars-in-identifiers -DPRIVATE=1 -D__APPLE_API_PRIVATE=1 -DLIBSYSCALL_INTERFACE -D__DARWIN_VERS_1050=1 -DNO_SYSCALL_LEGACY -DCF_OPEN_SOURCE -DCF_EXCLUDE_CSTD_HEADERS -D_FORTIFY_SOURCE=0 -D__BRIDGEOS_DEPRECATED(...)= -D__BRIDGEOS_AVAILABLE(...)= -D__BRIDGEOS_UNAVAILABLE= \
  -I$LS/mach -I$LS/os -I$LS/wrappers -I$LS/wrappers/string -I$LS/wrappers/libproc -I$LS/wrappers/libproc/spawn -I$B/mig_hdr/include -I$B/mig_hdr/local/include -I$B/internal_hdr/include -I$B/mig -I$B/hdr -I$LS/wrappers/spawn -I$LS/custom -I$LS \
  -I$W/apple-oss/xnu/libsyscall/wrappers/libproc -I$W/apple-oss/xnu/bsd -I$W/apple-oss/xnu/osfmk -I$W/apple-oss/xnu/libkern -I$W/apple-oss/xnu/bsd/sys"
XBUILD_VERBOSE=1 python3 $HOME/xef-remote/xbuild.py --out $B/obj --cflags "$FLAGS -std=gnu11 -include stddef.h -include stdatomic.h" --sflags "-arch arm64 -DLIBSYSCALL_INTERFACE=1 -DPRIVATE=1 -I$B/sys -I$LS/custom -I$LS/os -I$W/apple-oss/xnu/osfmk -I$W/apple-oss/xnu/bsd" $(cat $B/sources.txt $B/gen.txt) || true
mkdir -p $HOME/xef-remote/out/rootfs/usr/lib/system
cd $B/obj
clang -arch arm64 -mmacosx-version-min=12.0 -dynamiclib -nostdlib -install_name /usr/lib/system/libsystem_kernel.dylib \
  -Wl,-fixup_chains -Wl,-not_for_dyld_shared_cache -Wl,-undefined,dynamic_lookup -Wl,-compatibility_version,1.0.0 -Wl,-current_version,1.0.0 \
  *.o -o $HOME/xef-remote/out/rootfs/usr/lib/system/libsystem_kernel.dylib 2>&1 | grep -v "warning" | head -20
nm -u $HOME/xef-remote/out/rootfs/usr/lib/system/libsystem_kernel.dylib | sort -u | tr '\n' ' ' | head -c 2000; echo
REMOTE
mkdir -p darwin-rootfs/usr/lib/system
rsync -a mac:xef-remote/out/rootfs/usr/lib/system/libsystem_kernel.dylib darwin-rootfs/usr/lib/system/
