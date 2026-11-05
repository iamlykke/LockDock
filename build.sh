#!/bin/zsh
# ./build.sh            — build build/LockDock.app (Apple Silicon + Intel)
# ./build.sh --release  — also pack build/LockDock-<version>.zip for GitHub Releases
set -e
cd "$(dirname "$0")"

APP=build/LockDock.app
BIN="$APP/Contents/MacOS/LockDock"
rm -rf "$APP" build/AppIcon.iconset build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj
cp Info.plist "$APP/Contents/Info.plist"

swift Tools/make_icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target $arch-apple-macos14.4 Sources/main.swift -o build/obj/LockDock-$arch
done
lipo -create build/obj/LockDock-arm64 build/obj/LockDock-x86_64 -output "$BIN"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "$1" == "--release" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
    ZIP=build/LockDock-$VERSION.zip
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Packed $ZIP"
    shasum -a 256 "$ZIP"
fi
