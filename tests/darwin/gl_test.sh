#!/bin/bash
# GL regression: runs tests/darwin/gltri under xef-osx on a private Xvfb, checks rc, "frames=300",
# the in-process PPM dump, a root-window screenshot, and repeatability across two runs.
cd "$(dirname "$0")/../.." || exit 1
X=build/xef-osx
if ! command -v Xvfb >/dev/null || ! command -v import >/dev/null || ! ldconfig -p 2>/dev/null | grep -q 'libGL\.so'; then
  echo "SKIP: Xvfb, ImageMagick import or libGL missing"; exit 0
fi
[ -x $X ] && [ -f tests/darwin/gltri ] && [ -f tests/darwin/gltri_core ] || { echo "FAIL: missing $X or tests/darwin/gltri{,_core}"; exit 1; }
T=$(mktemp -d); N=99
while [ -e /tmp/.X11-unix/X$N ] || [ -e /tmp/.X$N-lock ]; do N=$((N+1)); done
Xvfb :$N -screen 0 640x480x24 >$T/xvfb.log 2>&1 & XPID=$!
trap 'kill $XPID 2>/dev/null; wait $XPID 2>/dev/null; rm -rf $T' EXIT
for i in $(seq 50); do [ -e /tmp/.X11-unix/X$N ] && break; sleep 0.1; done
[ -e /tmp/.X11-unix/X$N ] || { echo "SKIP: Xvfb failed to start"; cat $T/xvfb.log; exit 0; }
fail=0; bad() { echo "FAIL: $*"; fail=1; }
for A in gltri gltri_core; do
for r in 1 2; do
  DISPLAY=:$N LIBGL_ALWAYS_SOFTWARE=1 GLTRI_HOLD_MS=2000 timeout 60 $X -L darwin-rootfs tests/darwin/$A $T/${A}_r$r.ppm >$T/${A}_r$r.out 2>$T/${A}_r$r.err &
  APID=$!
  # root-window screenshots while the app is alive; passes if any shows a non-empty scene
  k=0; rootok=0
  while kill -0 $APID 2>/dev/null && [ $k -lt 100 ]; do
    sleep 0.3; k=$((k+1))
    import -window root -display :$N $T/${A}_root$r.png 2>/dev/null && python3 tools/imgcheck.py $T/${A}_root$r.png --min-colors 8 >$T/${A}_s$r.txt && { rootok=1; break; }
  done
  wait $APID; rc=$?
  [ $rc = 0 ] || { bad "$A run $r rc=$rc"; tail -3 $T/${A}_r$r.err; }
  grep -q '^frames=300$' $T/${A}_r$r.out || bad "$A run $r: no frames=300 in stdout"
  [ -s $T/${A}_r$r.ppm ] && python3 tools/imgcheck.py $T/${A}_r$r.ppm --min-colors 8 >$T/${A}_c$r.txt || { bad "$A run $r: dump empty/blank"; cat $T/${A}_c$r.txt 2>/dev/null; }
  [ $rootok = 1 ] || { bad "$A run $r: root screenshot missing/blank"; cat $T/${A}_s$r.txt 2>/dev/null; }
done
if [ -s $T/${A}_r1.ppm ] && [ -s $T/${A}_r2.ppm ] && ! cmp -s $T/${A}_r1.ppm $T/${A}_r2.ppm; then
  python3 tools/imgcheck.py $T/${A}_r1.ppm --ref $T/${A}_r2.ppm --min-ssim 0.99 >$T/cmp.txt || { bad "$A: runs differ"; cat $T/cmp.txt; }
fi
if [ "$A" = gltri_core ] && [ -s $T/${A}_r1.ppm ] && [ -f tests/darwin/mac_gl/ref_core.ppm ]; then
  python3 tools/imgcheck.py $T/${A}_r1.ppm --ref tests/darwin/mac_gl/ref_core.ppm --min-colors 8 --min-ssim 0.95 >$T/ref.txt || { bad "gltri_core differs from the Mac reference"; cat $T/ref.txt; }
fi
done
[ $fail = 0 ] && { echo "PASS gl_test"; exit 0; }
echo "FAIL gl_test"; exit 1
