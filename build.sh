#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
APP="build/Bispo TV.app"

# Sem o Xcode, o SDK do macOS 27 das Command Line Tools não tem o plugin das
# macros do SwiftUI (@State). O SDK 26.5 compila sem ele.
SDK_26="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ -d "$SDK_26" ] && ! xcode-select -p | grep -q Xcode; then
  export SDKROOT="$SDK_26"
fi

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

# A chave do TMDB (capas e fichas) entra só no app compilado, nunca no git:
# vem de TMDB_API_KEY ou de arquivos-gerados/tmdb-chave.txt.
CHAVE_TMDB="${TMDB_API_KEY:-$(cat arquivos-gerados/tmdb-chave.txt 2>/dev/null || true)}"
CHAVE_TMDB="$(printf '%s' "$CHAVE_TMDB" | tr -d '[:space:]')"
[ -n "$CHAVE_TMDB" ] || echo "aviso: sem chave do TMDB; capas e fichas não vão carregar" >&2
printf 'enum TMDBChave {\n    static let valor = "%s"\n}\n' "$CHAVE_TMDB" > build/TMDBChave.swift

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
  -o "$APP/Contents/MacOS/BispoTv" \
  Sources/*.swift build/TMDBChave.swift

codesign --force --sign - --identifier dev.bispotv.player "$APP" >/dev/null 2>&1 || true

echo "built: $APP"
