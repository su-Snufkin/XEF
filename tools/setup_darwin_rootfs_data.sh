#!/bin/bash
# Data files macOS programs expect that are not part of any dylib: time zone database, etc.
set -e
cd "$(dirname "$0")/.."
mkdir -p darwin-rootfs/var/db/timezone
rm -rf darwin-rootfs/var/db/timezone/zoneinfo
rsync -aL --exclude=right --exclude=posix --exclude='*.tab' /usr/share/zoneinfo/ darwin-rootfs/var/db/timezone/zoneinfo/
cp /usr/share/zoneinfo/zone.tab darwin-rootfs/var/db/timezone/zoneinfo/ 2>/dev/null || cp /usr/share/zoneinfo/zone1970.tab darwin-rootfs/var/db/timezone/zoneinfo/zone.tab 2>/dev/null || true
mkdir -p darwin-rootfs/private/var
ln -sfn ../var/db darwin-rootfs/private/var/db 2>/dev/null || true
echo "zoneinfo: $(du -sh darwin-rootfs/var/db/timezone/zoneinfo | cut -f1)"
