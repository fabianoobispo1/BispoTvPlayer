#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Bispo TV.app"
DMG="build/BispoTv.dmg"

./build.sh
python3 bundle_ffmpeg.py "$APP"
codesign --force --deep --sign - --identifier dev.bispotv.player "$APP" >/dev/null 2>&1 || true

# Mesmo SDK do build.sh: sem o Xcode, o do macOS 27 não roda os scripts Swift.
SDK_26="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ -d "$SDK_26" ] && ! xcode-select -p | grep -q Xcode; then
  export SDKROOT="$SDK_26"
fi

# Fundo da janela, em 1x e 2x juntos num TIFF para telas Retina.
swift MakeDmgBackground.swift build/dmg-fundo.png 1
swift MakeDmgBackground.swift build/dmg-fundo@2x.png 2
tiffutil -cathidpicheck build/dmg-fundo.png build/dmg-fundo@2x.png -out build/dmg-fundo.tiff 2>/dev/null

# O dmgbuild monta a janela (fundo, posição dos ícones, tamanho) sem precisar
# abrir o Finder. Fica num ambiente próprio, fora de build/, que o build.sh
# apaga a cada montagem.
VENV="arquivos-gerados/venv-dmg"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
  echo "instalando o dmgbuild em $VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q dmgbuild
fi

rm -f "$DMG"
"$VENV/bin/dmgbuild" -s dmg_settings.py \
  -D app="$APP" -D fundo=build/dmg-fundo.tiff \
  "Bispo TV" "$DMG" >/dev/null
echo "DMG: $DMG ($(du -h "$DMG" | cut -f1))"
