#!/bin/sh
# Builds an AArch64 guest root filesystem from Ubuntu noble (arm64) packages, with dependencies:
#   tools/mkrootfs.sh [pkg ...]      -> .tools/rootfs-arm64
# Default set: shells/utilities, X11 demo apps, Mesa (llvmpipe) + GL demos.
# Run GUI programs on a host X server (e.g. Xvfb :1):
#   DISPLAY=:1 build/xef -L .tools/rootfs-arm64 .tools/rootfs-arm64/usr/bin/glxgears
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$ROOT/.tools
R=$T/rootfs-arm64
M=http://ports.ubuntu.com/ubuntu-ports
mkdir -p $T/dl
cd $T/dl
IDX=
for s in noble noble-updates; do for c in main universe; do
  [ -f $s-arm64-$c.xz ] || curl -sf -o $s-arm64-$c.xz $M/dists/$s/$c/binary-arm64/Packages.xz
  IDX=$IDX${IDX:+,}$T/dl/$s-arm64-$c.xz
done; done
PKGS=${*:-"busybox-static bash coreutils findutils grep sed gawk python3.12-minimal sqlite3 lua5.4
  x11-apps mesa-utils libgl1-mesa-dri libglx-mesa0 libegl-mesa0"}
python3 $ROOT/tools/fetch_debs.py --deps $M $R $IDX $PKGS
# usr-merge links and the loader where PT_INTERP expects it
for d in bin sbin lib; do [ -e $R/$d ] || ln -s usr/$d $R/$d; done
[ -e $R/usr/lib/ld-linux-aarch64.so.1 ] || ln -s aarch64-linux-gnu/ld-linux-aarch64.so.1 $R/usr/lib/ld-linux-aarch64.so.1
echo "rootfs ready: $R"
