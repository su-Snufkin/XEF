#!/bin/sh
# Runs a guest GUI program under XEF on $DISPLAY (default :1), screenshots after N seconds.
#   tools/guishot.sh SECONDS OUT.png [--keep] -- guest-program args...
# Program paths are relative to the rootfs (.tools/rootfs-arm64), e.g. /usr/games/neverball.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
R=${XEF_ROOTFS:-$ROOT/.tools/rootfs-arm64}
secs=$1 out=$2; shift 2
keep=0; [ "$1" = --keep ] && { keep=1; shift; }
[ "$1" = -- ] && shift
prog=$1; shift
export DISPLAY=${DISPLAY:-:1} LIBGL_ALWAYS_SOFTWARE=1 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null NO_AT_BRIDGE=1
"$ROOT/build/xef" -L "$R" "$prog" "$@" > "${out%.png}.log" 2>&1 &
pid=$!
sleep "$secs"
xwd -root -silent | convert xwd:- "$out"
[ $keep = 1 ] || { kill $pid 2>/dev/null; sleep 1; kill -9 $pid 2>/dev/null; }
echo "screenshot: $out (log: ${out%.png}.log)"
