#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
APP="build/Saimo TV.app"

# Sem o Xcode, o SDK do macOS 27 das Command Line Tools não tem o plugin das
# macros do SwiftUI (@State). O SDK 26.5 compila sem ele.
SDK_26="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ -d "$SDK_26" ] && ! xcode-select -p | grep -q Xcode; then
  export SDKROOT="$SDK_26"
fi

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

./make_icon.sh >/dev/null
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc \
  -module-cache-path build/ModuleCache \
  -swift-version 6 \
  -target arm64-apple-macos15.0 \
  -O \
  -framework AVKit \
  -framework MediaPlayer \
  -framework AVFoundation \
  -framework SwiftUI \
  -framework AppKit \
  -o "$APP/Contents/MacOS/SaimoTV" \
  Sources/*.swift

codesign --force --sign - --identifier dev.saimo.player "$APP" >/dev/null 2>&1 || true

echo "built: $APP"
