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
# SystemVersion.plist (platform.mac_ver(), NSProcessInfo, sw_vers readers): the version xef-osx reports through
# sysctl kern.osproductversion / kern.osversion (darwin_stubs.cpp, darwin_syscalls.cpp)
mkdir -p darwin-rootfs/System/Library/CoreServices
cat > darwin-rootfs/System/Library/CoreServices/SystemVersion.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ProductBuildVersion</key>
	<string>21G115</string>
	<key>ProductName</key>
	<string>macOS</string>
	<key>ProductUserVisibleVersion</key>
	<string>26.0</string>
	<key>ProductVersion</key>
	<string>26.0</string>
</dict>
</plist>
PLIST
echo "zoneinfo: $(du -sh darwin-rootfs/var/db/timezone/zoneinfo | cut -f1)"
