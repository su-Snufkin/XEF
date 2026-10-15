#!/bin/bash
# GL regression: runs tests/darwin/gltri under xef-osx on a private Xvfb, checks rc, "frames=300",
# the in-process PPM dump, a root-window screenshot, and repeatability across two runs.
cd "$(dirname "$0")/../.." || exit 1
X=build/xef-osx; APP=tests/darwin/gltri
if ! command -v Xvfb >/dev/null || ! command -v import >/dev/null || ! ldconfig -p 2>/dev/null | grep -q 'libGL\.so'; then
  echo "SKIP: Xvfb, ImageMagick import or libGL missing"; exit 0
fi
[ -x $X ] && [ -f $APP ] || { echo "FAIL: missing $X or $APP"; exit 1; }
T=$(mktemp -d); N=99
while [ -e /tmp/.X11-unix/X$N ] || [ -e /tmp/.X$N-lock ]; do N=$((N+1)); done
Xvfb :$N -screen 0 640x480x24 >$T/xvfb.log 2>&1 & XPID=$!
trap 'kill $XPID 2>/dev/null; wait $XPID 2>/dev/null; rm -rf $T' EXIT
for i in $(seq 50); do [ -e /tmp/.X11-unix/X$N ] && break; sleep 0.1; done
[ -e /tmp/.X11-unix/X$N ] || { echo "SKIP: Xvfb failed to start"; cat $T/xvfb.log; exit 0; }
fail=0; bad() { echo "FAIL: $*"; fail=1; }
for r in 1 2; do
  DISPLAY=:$N LIBGL_ALWAYS_SOFTWARE=1 GLTRI_HOLD_MS=2000 timeout 60 $X -L darwin-rootfs $APP $T/r$r.ppm >$T/r$r.out 2>$T/r$r.err &
  APID=$!
  # root-window screenshots while the app is alive; passes if any shows a non-empty scene
  k=0; rootok=0
  while kill -0 $APID 2>/dev/null && [ $k -lt 100 ]; do
    sleep 0.3; k=$((k+1))
    import -window root -display :$N $T/root$r.png 2>/dev/null && python3 tools/imgcheck.py $T/root$r.png >$T/s$r.txt && { rootok=1; break; }
  done
  wait $APID; rc=$?
  [ $rc = 0 ] || { bad "run $r rc=$rc"; tail -3 $T/r$r.err; }
  grep -q '^frames=300$' $T/r$r.out || bad "run $r: no frames=300 in stdout"
  [ -s $T/r$r.ppm ] && python3 tools/imgcheck.py $T/r$r.ppm >$T/c$r.txt || { bad "run $r: dump empty/blank"; cat $T/c$r.txt 2>/dev/null; }
  [ $rootok = 1 ] || { bad "run $r: root screenshot missing/blank"; cat $T/s$r.txt 2>/dev/null; }
done
if [ -s $T/r1.ppm ] && [ -s $T/r2.ppm ] && ! cmp -s $T/r1.ppm $T/r2.ppm; then
  python3 tools/imgcheck.py $T/r1.ppm --ref $T/r2.ppm --min-ssim 0.99 >$T/cmp.txt || { bad "runs differ"; cat $T/cmp.txt; }
fi
[ $fail = 0 ] && { echo "PASS gl_test"; exit 0; }
echo "FAIL gl_test"; exit 1
