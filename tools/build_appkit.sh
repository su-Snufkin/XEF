#!/bin/bash
# Builds all system frameworks and dylibs (arm64 Mach-O) from rootfs-src/appkit on the remote Mac
# and installs them into ./darwin-rootfs.
set -e
cd "$(dirname "$0")/.."
ssh mac 'mkdir -p ~/xef-remote/src/appkit'; rsync -a --delete rootfs-src/appkit/ mac:xef-remote/src/appkit/
ssh mac 'bash -s' <<'REMOTE'
set -e
S=$HOME/xef-remote/src/appkit; R=$HOME/xef-remote/out/rootfs; F=$R/System/Library/Frameworks; L=$R/usr/lib; O=$HOME/xef-remote/src/appkit-build
mkdir -p $O $L; rm -rf $O/*
SDK=$(xcrun --show-sdk-path)
COMMON="-arch arm64 -mmacosx-version-min=12.0"
LIBS="$F/Foundation.framework/Versions/C/Foundation $F/CoreFoundation.framework/Versions/A/CoreFoundation -L$R/usr/lib -lobjc"
HIT=$F/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox
mk() { # name version dir
  mkdir -p $F/$1.framework/Versions/$2; }

H=$F/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework
CF="$F/CoreFoundation.framework/Versions/A/CoreFoundation"

sysfw() { # name versiondir install-name compat current extra-link
  mkdir -p $(dirname $3 | sed "s|^/System/Library/Frameworks|$F|")
  clang $COMMON -O2 -w -isysroot $SDK -c $S/$1.c -o $O/$1.o
  clang $COMMON -dynamiclib -install_name $3 -Wl,-compatibility_version,$4 -Wl,-current_version,$5 -Wl,-not_for_dyld_shared_cache \
    $O/$1.o $CF -Wl,-undefined,dynamic_lookup -o $(echo $3 | sed "s|^/System/Library/Frameworks|$F|")
  codesign -f -s - $(echo $3 | sed "s|^/System/Library/Frameworks|$F|")
}

sysfw CoreGraphics x /System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics 64 1957.0.0
sysfw IOKit x /System/Library/Frameworks/IOKit.framework/Versions/A/IOKit 1 275.0.0
sysfw CoreServices x /System/Library/Frameworks/CoreServices.framework/Versions/A/CoreServices 1 1226.0.0
sysfw CoreVideo x /System/Library/Frameworks/CoreVideo.framework/Versions/A/CoreVideo 1.2 1.5
sysfw AudioToolbox x /System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox 1 1000
sysfw HIToolbox x /System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox 1 1
sysfw CoreText x /System/Library/Frameworks/CoreText.framework/Versions/A/CoreText 1 1

mkdir -p $H/Versions/A/Resources; cp $S/HIToolbox-Info.plist $H/Versions/A/Resources/Info.plist
ln -sfn A $H/Versions/Current; ln -sfn Versions/Current/HIToolbox $H/HIToolbox; ln -sfn Versions/Current/Resources $H/Resources
for n in CoreGraphics IOKit CoreServices CoreVideo AudioToolbox CoreText; do
  ln -sfn A $F/$n.framework/Versions/Current
  ln -sfn Versions/Current/$n $F/$n.framework/$n
done
ln -sfn A $F/Carbon.framework/Versions/Current

# AppKit
mk AppKit C
clang $COMMON -O2 -w -fno-objc-arc -fobjc-exceptions -fblocks -isysroot $SDK -I$S -c $S/AppKit.m -o $O/AppKit.o
clang $COMMON -dynamiclib -install_name /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit \
  -Wl,-compatibility_version,45 -Wl,-current_version,2685.10.108 -Wl,-not_for_dyld_shared_cache \
  $O/AppKit.o $LIBS $HIT -Wl,-undefined,dynamic_lookup -o $F/AppKit.framework/Versions/C/AppKit

# OpenGL
mk OpenGL A
clang $COMMON -O2 -w -c $S/OpenGL.c -o $O/OpenGL.o
clang $COMMON -dynamiclib -install_name /System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL \
  -Wl,-compatibility_version,1 -Wl,-current_version,1 -Wl,-not_for_dyld_shared_cache \
  $O/OpenGL.o -Wl,-undefined,dynamic_lookup -o $F/OpenGL.framework/Versions/A/OpenGL
mkdir -p $F/OpenGL.framework/Versions/A/Resources; cp $S/OpenGL-Info.plist $F/OpenGL.framework/Versions/A/Resources/Info.plist
ln -sfn Versions/Current/Resources $F/OpenGL.framework/Resources
mkdir -p $F/OpenGL.framework/Versions/A/Libraries; ln -sfn ../OpenGL $F/OpenGL.framework/Versions/A/Libraries/libGL.dylib
ln -sfn Versions/Current/Libraries $F/OpenGL.framework/Libraries

# Cocoa umbrella
mk Cocoa A
clang $COMMON -O2 -w -c $S/Cocoa.c -o $O/Cocoa.o
clang $COMMON -dynamiclib -install_name /System/Library/Frameworks/Cocoa.framework/Versions/A/Cocoa \
  -Wl,-compatibility_version,1 -Wl,-current_version,24 -Wl,-not_for_dyld_shared_cache \
  -Wl,-reexport_library,$F/AppKit.framework/Versions/C/AppKit -Wl,-reexport_library,$F/Foundation.framework/Versions/C/Foundation \
  $O/Cocoa.o -Wl,-undefined,dynamic_lookup -o $F/Cocoa.framework/Versions/A/Cocoa

# Helper to build an ObjC framework
build_objcfw() { # name version srcfile
  local NAME=$1
  local VER=$2
  local SRC=$3
  mk $NAME $VER
  clang $COMMON -O2 -w -fno-objc-arc -fobjc-exceptions -fblocks -isysroot $SDK -I$S -c $S/$SRC -o $O/$NAME.o
  clang $COMMON -dynamiclib -install_name /System/Library/Frameworks/$NAME.framework/Versions/$VER/$NAME \
    -Wl,-compatibility_version,1 -Wl,-current_version,1 -Wl,-not_for_dyld_shared_cache \
    $O/$NAME.o $LIBS $F/CoreGraphics.framework/Versions/A/CoreGraphics -Wl,-undefined,dynamic_lookup -o $F/$NAME.framework/Versions/$VER/$NAME
  ln -sfn $VER $F/$NAME.framework/Versions/Current
  ln -sfn Versions/Current/$NAME $F/$NAME.framework/$NAME
  codesign -f -s - $F/$NAME.framework/Versions/$VER/$NAME
}

# QuartzCore, Metal, MetalKit, ModelIO, ImageIO, IOSurface, CoreData
build_objcfw QuartzCore A QuartzCore.m
build_objcfw Metal A Metal.m

mk MetalKit A
clang $COMMON -O2 -w -fno-objc-arc -fobjc-exceptions -fblocks -isysroot $SDK -I$S -c $S/MetalKit.m -o $O/MetalKit.o
clang $COMMON -dynamiclib -install_name /System/Library/Frameworks/MetalKit.framework/Versions/A/MetalKit \
  -Wl,-compatibility_version,1 -Wl,-current_version,1 -Wl,-not_for_dyld_shared_cache \
  $O/MetalKit.o $LIBS $F/CoreGraphics.framework/Versions/A/CoreGraphics $F/AppKit.framework/Versions/C/AppKit $F/QuartzCore.framework/Versions/A/QuartzCore $F/Metal.framework/Versions/A/Metal -Wl,-undefined,dynamic_lookup -o $F/MetalKit.framework/Versions/A/MetalKit
ln -sfn A $F/MetalKit.framework/Versions/Current
ln -sfn Versions/Current/MetalKit $F/MetalKit.framework/MetalKit
codesign -f -s - $F/MetalKit.framework/Versions/A/MetalKit

build_objcfw ModelIO A ModelIO.m
build_objcfw ImageIO A ImageIO.m
build_objcfw IOSurface A IOSurface.m
build_objcfw CoreData A CoreData.m

# All remaining Darling frameworks
FW_LIST="AGL AVFAudio AVFoundation AVKit Accelerate Accounts AddressBook AudioVideoBridging AuthenticationServices Automator CalendarStore CloudKit Collaboration ColorSync Contacts ContactsUI CoreAudioKit CoreBluetooth CoreImage CoreLocation CoreMIDI CoreMedia CoreMediaIO CoreTelephony CoreWLAN CryptoTokenKit DirectoryServices DiscRecording DiscRecordingUI DrawSprocket EventKit ExceptionHandling ForceFeedback GLKit GameController IOBluetooth IOBluetoothUI ImageCaptureCore InputMethodKit InstantMessage JavaRuntimeSupport JavaVM LocalAuthentication MapKit MediaAccessibility MediaToolbox Message MultipeerConnectivity NetFS Network OSAKit OpenAL OpenCL OpenDirectory PDFKit Photos QTKit Quartz QuickLook QuickTime SceneKit ScreenSaver ScriptingBridge SecurityFoundation SecurityInterface ShazamKit Speech SpriteKit StoreKit SyncServices UniformTypeIdentifiers UserNotifications VideoDecodeAcceleration VideoToolbox Vision WebKit"

for fw in $FW_LIST; do
  if [ -f "$S/$fw.m" ]; then
    build_objcfw $fw A $fw.m
  fi
done

# symlinks + ad-hoc signature for AppKit, OpenGL, Cocoa
ln -sfn C $F/AppKit.framework/Versions/Current; ln -sfn C $F/AppKit.framework/Versions/A
ln -sfn Versions/Current/AppKit $F/AppKit.framework/AppKit
ln -sfn A $F/OpenGL.framework/Versions/Current; ln -sfn Versions/Current/OpenGL $F/OpenGL.framework/OpenGL
ln -sfn A $F/Cocoa.framework/Versions/Current; ln -sfn Versions/Current/Cocoa $F/Cocoa.framework/Cocoa
codesign -f -s - $F/AppKit.framework/Versions/C/AppKit $F/OpenGL.framework/Versions/A/OpenGL $F/Cocoa.framework/Versions/A/Cocoa

# System dylibs (/usr/lib)
clang $COMMON -O2 -w -c $S/libsystem_shims.c -o $O/libsystem_shims.o
for dlib in libcompression libcache libDiagnosticMessagesClient libMobileGestalt libsandbox libsystem_coreservices; do
  clang $COMMON -dynamiclib -install_name /usr/lib/$dlib.dylib \
    -Wl,-compatibility_version,1 -Wl,-current_version,1 -Wl,-not_for_dyld_shared_cache \
    $O/libsystem_shims.o -o $L/$dlib.dylib
  codesign -f -s - $L/$dlib.dylib
done

echo "Remote build complete!"
REMOTE

FRAMEWORKS="AppKit Cocoa OpenGL CoreGraphics IOKit CoreServices Carbon CoreVideo AudioToolbox CoreText QuartzCore Metal MetalKit ModelIO ImageIO IOSurface CoreData CoreImage WebKit SecurityFoundation AVFoundation SceneKit SpriteKit MapKit Photos CloudKit Contacts EventKit GameController StoreKit UserNotifications Vision AGL AVFAudio AVKit Accelerate Accounts AddressBook AudioVideoBridging AuthenticationServices Automator CalendarStore Collaboration ColorSync ContactsUI CoreAudioKit CoreBluetooth CoreLocation CoreMIDI CoreMedia CoreMediaIO CoreTelephony CoreWLAN CryptoTokenKit DirectoryServices DiscRecording DiscRecordingUI DrawSprocket ExceptionHandling ForceFeedback GLKit IOBluetooth IOBluetoothUI ImageCaptureCore InputMethodKit InstantMessage JavaRuntimeSupport JavaVM LocalAuthentication MediaAccessibility MediaToolbox Message MultipeerConnectivity NetFS Network OSAKit OpenAL OpenCL OpenDirectory PDFKit QTKit Quartz QuickLook QuickTime ScreenSaver ScriptingBridge SecurityInterface ShazamKit Speech SyncServices UniformTypeIdentifiers VideoDecodeAcceleration VideoToolbox"

for f in $FRAMEWORKS; do
  rsync -a mac:xef-remote/out/rootfs/System/Library/Frameworks/$f.framework darwin-rootfs/System/Library/Frameworks/
done

DYLIBS="libcompression.dylib libcache.dylib libDiagnosticMessagesClient.dylib libMobileGestalt.dylib libsandbox.dylib libsystem_coreservices.dylib"
for d in $DYLIBS; do
  rsync -a mac:xef-remote/out/rootfs/usr/lib/$d darwin-rootfs/usr/lib/
done

echo "Successfully installed all frameworks and system dylibs into darwin-rootfs!"

