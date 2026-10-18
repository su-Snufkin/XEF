#!/bin/bash
export DISPLAY=:0
cd "$(dirname "$0")" || exit 1
X=build/xef-osx

APPS=(
  "darwin-rootfs/Applications/TrackWeight.app/Contents/MacOS/TrackWeight"
  "darwin-rootfs/Applications/Rectangle.app/Contents/MacOS/Rectangle"
  "darwin-rootfs/Applications/DaisyDisk.app/Contents/MacOS/DaisyDisk"
  "darwin-rootfs/Applications/Blackmagic Disk Speed Test.app/Contents/MacOS/DiskSpeedTest"
  "darwin-rootfs/Applications/Balatro.app/Contents/Game/Balatro.app/Contents/MacOS/love"
)

for APP in "${APPS[@]}"; do
  if [ -f "$APP" ]; then
    echo "=================================================="
    echo ">>> Odpalam aplikacje: $APP"
    echo ">>> Zamknij jej okno (lub nacisnij Ctrl+C), aby przejsc do nastepnej."
    echo "=================================================="
    chmod +x "$APP"
    $X -L darwin-rootfs "$APP"
    echo ">>> Aplikacja zakonczona. Przechodze do kolejnej..."
    sleep 1
  else
    echo "Pominieto: $APP (brak pliku)"
  fi
done
echo "Wszystkie aplikacje zostaly uruchomione!"
