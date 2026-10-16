#!/bin/bash
# FFmpeg 8.1 (Homebrew arm64 Mach-O, tools/pull_homebrew.sh ffmpeg) under xef-osx: a bitexact single-threaded
# x264 + AAC encode of lavfi sources must give the same file as on the Mac (md5 recorded from the Mac run).
# Skips (exit 0) when darwin-rootfs/opt/homebrew/bin/ffmpeg is missing.
cd "$(dirname "$0")/../.."
FF=darwin-rootfs/opt/homebrew/bin/ffmpeg
[ -e "$FF" ] || { echo "SKIP ffmpeg_test: $FF not found"; exit 0; }
OUT=${TMPDIR:-/tmp}/xef-ffmpeg-test; mkdir -p "$OUT"
timeout 300 build/xef-osx -L darwin-rootfs "$FF" -hide_banner -loglevel error -y -f lavfi -i testsrc=duration=2:size=320x240:rate=25 \
  -f lavfi -i sine=frequency=440:duration=2 -c:v libx264 -preset veryfast -threads 1 -c:a aac -shortest \
  -fflags +bitexact -flags:v +bitexact -flags:a +bitexact "$OUT/o.mp4" || { echo "FAIL ffmpeg_test (encode rc=$?)"; exit 1; }
got=$(md5sum "$OUT/o.mp4" | cut -c1-32)
want=c2c3c7db64fef3d4e8750734fb13a779
[ "$got" = "$want" ] && { echo "PASS ffmpeg_test"; exit 0; }
echo "FAIL ffmpeg_test (md5 $got, Mac $want)"; exit 1
