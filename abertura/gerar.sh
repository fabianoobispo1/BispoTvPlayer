#!/bin/bash
#
# Bispo TV: gera a abertura animada (o vídeo da marca) nos dois formatos e
# copia para os apps que a usam. O original tem um gerador próprio, com a
# marca dele; este é o nosso (MakeAbertura.swift, nas cores Nocturne).
#
#   ./gerar.sh
set -euo pipefail
cd "$(dirname "$0")"
QUADROS="$(mktemp -d)"
trap 'rm -rf "$QUADROS"' EXIT

for formato in "h 1920 1080" "v 1080 1920"; do
  set -- $formato
  swift MakeAbertura.swift "$2" "$3" "$QUADROS/$1" >/dev/null
  ffmpeg -v error -y -framerate 60 -i "$QUADROS/$1/%04d.png" -c:v libx264 -profile:v main \
    -pix_fmt yuv420p -crf 20 -movflags +faststart "abertura-$1.mp4"
done

# Os outros apps, quando estão ao lado (a mesma pasta de sempre).
RAIZ=..
[ -d "$RAIZ/../BispoTvWin/assets" ] && cp abertura-h.mp4 "$RAIZ/../BispoTvWin/assets/abertura.mp4"
if [ -d "$RAIZ/../BispoTvAndroid/app/src/main/res/raw" ]; then
  cp abertura-h.mp4 "$RAIZ/../BispoTvAndroid/app/src/main/res/raw/abertura_h.mp4"
  cp abertura-v.mp4 "$RAIZ/../BispoTvAndroid/app/src/main/res/raw/abertura_v.mp4"
fi
if [ -d "$RAIZ/../BispoTvCell/assets/abertura" ]; then
  cp abertura-h.mp4 abertura-v.mp4 "$RAIZ/../BispoTvCell/assets/abertura/"
fi
echo "abertura gerada: abertura-h.mp4 e abertura-v.mp4"
