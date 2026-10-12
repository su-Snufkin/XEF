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
PKGS=${*:-"busybox-static dash bash coreutils findutils grep sed gawk python3.12-minimal sqlite3 lua5.4
  x11-apps mesa-utils libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libglib2.0-bin librsvg2-common"}
python3 $ROOT/tools/fetch_debs.py --deps $M $R $IDX $PKGS
# usr-merge links and the loader where PT_INTERP expects it
for d in bin sbin lib; do
  if [ -d $R/$d ] && [ ! -L $R/$d ]; then mkdir -p $R/usr/$d && cp -a $R/$d/. $R/usr/$d/ && rm -rf $R/$d; fi
  [ -e $R/$d ] || ln -s usr/$d $R/$d
done
[ -e $R/usr/lib/ld-linux-aarch64.so.1 ] || ln -s aarch64-linux-gnu/ld-linux-aarch64.so.1 $R/usr/lib/ld-linux-aarch64.so.1
# What maintainer scripts would normally generate (needs build/xef): gdk-pixbuf loaders cache,
# compiled GSettings schemas, icon caches, font cache.
X=$ROOT/build/xef
if [ -x $X ]; then
  L=$R/usr/lib/aarch64-linux-gnu
  [ -x $L/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders ] && \
    $X -L $R $L/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders > $L/gdk-pixbuf-2.0/2.10.0/loaders.cache 2>/dev/null
  [ -x $R/usr/bin/glib-compile-schemas ] && [ -d $R/usr/share/glib-2.0/schemas ] && \
    $X -L $R $R/usr/bin/glib-compile-schemas $R/usr/share/glib-2.0/schemas 2>/dev/null
  if [ -x $R/usr/bin/gtk-update-icon-cache ]; then
    for d in $R/usr/share/icons/*/; do
      [ -f $d/index.theme ] && $X -L $R $R/usr/bin/gtk-update-icon-cache -q -f $d 2>/dev/null
    done
  fi
  [ -x $R/usr/bin/fc-cache ] && $X -L $R $R/usr/bin/fc-cache -s 2>/dev/null
fi
echo "rootfs ready: $R"
