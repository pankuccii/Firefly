#!/bin/sh
set -eu
# Supply include directories containing libimobiledevice/ and plist/ respectively.
: "${IDEVICE_INCLUDE:?}" "${PLIST_INCLUDE:?}"
cd "$(dirname "$0")/.."
out=Resources/DeviceTools/bin/firefly-session
xcrun clang -O2 -arch arm64 -I"$IDEVICE_INCLUDE" -I"$PLIST_INCLUDE" DeviceSession/session.c -LResources/DeviceTools/lib -limobiledevice-1.0 -lplist-2.0 -o "$out"
for lib in libimobiledevice-1.0.6.dylib libplist-2.0.12.dylib; do
    install_name_tool -change "@loader_path/$lib" "@loader_path/../lib/$lib" "$out"
done
codesign --force --sign - "$out"
