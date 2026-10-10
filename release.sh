#!/bin/bash
#
# Publica uma versão: monta o DMG e sobe no release.
#
# A versão sai do Info.plist. O nome do arquivo é o contrato com o
# atualizador: ele procura no release um .dmg.
#
# Os trechos comentados montam os apps da TV, do celular e do Windows, que
# ainda não existem.
#
#   ./release.sh                 usa a versão do Info.plist
#   ./release.sh 1.1.0           marca esta versão antes de publicar
#   ./release.sh 1.1.0 --rascunho  cria como rascunho, para revisar no site
set -euo pipefail
cd "$(dirname "$0")"

PLIST="Info.plist"
# GRADLE="../SaimoTV-Android/app/build.gradle.kts"
# JAVA17="/opt/homebrew/Cellar/openjdk@17/17.0.19/libexec/openjdk.jdk/Contents/Home"

versao="${1:-}"
if [ -n "$versao" ] && [ "${versao:0:2}" != "--" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $versao" "$PLIST"
#   # O versionCode precisa só crescer, então vira um número a partir da versão:
#   # 1.2.3 -> 10203. Sem isso o Android recusa a instalação por cima.
#   codigo=$(python3 - "$versao" <<'PY'
# import sys
# p = (sys.argv[1].split(".") + ["0", "0"])[:3]
# print(int(p[0]) * 10000 + int(p[1]) * 100 + int(p[2]))
# PY
# )
#   if [ -f "$GRADLE" ]; then
#     sed -i '' "s/versionName = \".*\"/versionName = \"$versao\"/" "$GRADLE"
#     sed -i '' "s/versionCode = .*/versionCode = $codigo/" "$GRADLE"
#   fi
  shift
else
  versao=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
fi

echo "==> versão $versao"

echo "==> montando o DMG"
./make_dmg.sh >/dev/null
mkdir -p build/release
cp "build/BispoTv.dmg" "build/release/BispoTv.dmg"

# # Os apps da TV e do Windows só entram quando os projetos estão ao lado deste.
# if [ -d ../SaimoTV-Android ]; then
#   echo "==> montando o APK da TV"
#   # assembleRelease, e não Debug: o APK publicado sai assinado com a chave da
#   # pasta chaves, que é o que permite atualizar por cima.
#   ( cd ../SaimoTV-Android && JAVA_HOME="$JAVA17" ANDROID_HOME="$HOME/Library/Android/sdk" \
#     ./gradlew assembleRelease -q )
#   cp "../SaimoTV-Android/app/build/outputs/apk/release/app-release.apk" "build/release/SaimoTV.apk"
# fi

# if [ -d ../SaimoWin ]; then
#   echo "==> montando o app do Windows"
#   ( cd ../SaimoWin && ./empacotar.sh >/dev/null )
#   cp "../SaimoWin/dist/SaimoTV-Windows.zip" "build/release/SaimoTV-Windows.zip"
# fi

# # O APK do celular é montado à parte (Expo) e copiado para cá antes de publicar.
# if [ -f "../Saimo-Cell-V2/android/app/build/outputs/apk/release/app-release.apk" ]; then
#   cp "../Saimo-Cell-V2/android/app/build/outputs/apk/release/app-release.apk" "build/release/SaimoCell.apk"
# fi

# if ls build/release/*.apk >/dev/null 2>&1; then
#   echo "==> conferindo as assinaturas"
#   APKSIGNER=$(ls "$HOME"/Library/Android/sdk/build-tools/*/apksigner | tail -1)
#   for apk in build/release/*.apk; do
#   echo "    $(basename "$apk"): $("$APKSIGNER" verify --print-certs "$apk" 2>/dev/null \
#     | grep -m1 -o 'SHA-256 digest: .*')"
#   done
# fi

# As notas: NOTAS.md na raiz, se você escreveu uma; senão, os commits desde a
# última versão. Fica fora de build/, que o build.sh apaga a cada montagem.
notas="build/release/NOTAS.md"
{
  echo "## BispoTv $versao"
  echo
  if [ -f NOTAS.md ]; then
    cat NOTAS.md
  else
    git log --pretty="- %s" "$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)"..HEAD \
      | grep -v "^- Merge" || true
  fi
  cat <<'INSTALAR'

### Como instalar

1. Baixe o `BispoTv.dmg` abaixo, abra e arraste o BispoTv para Aplicativos.
2. Na primeira vez, o macOS avisa que não pode verificar o desenvolvedor (o app
   não é assinado pela Apple). Abra **Ajustes do Sistema → Privacidade e
   Segurança**, desça até o aviso do BispoTv e clique em **Abrir Mesmo Assim**.

Requer Mac com Apple Silicon (M1 ou mais novo) e macOS 15 ou mais recente.
As licenças do FFmpeg e das bibliotecas embutidas estão na pasta *Licenças* do DMG.
INSTALAR
} > "$notas"

extra=""
for arg in "$@"; do
  [ "$arg" = "--rascunho" ] && extra="--draft"
done

# A tag é criada no GitHub em cima do main de lá: a versão nova do Info.plist
# precisa estar lá antes.
if ! git diff --quiet -- "$PLIST"; then
  git commit -q -m "Versão $versao" -- "$PLIST"
fi
echo "==> enviando para o GitHub"
git push -q origin HEAD

# Com o remote "upstream" (o original, do sincronizar_original.sh) o gh não
# sabe sozinho em qual repositório publicar: é sempre no origin.
repo="$(git remote get-url origin | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##')"

echo "==> publicando v$versao em $repo"
gh release create "v$versao" --repo "$repo" \
  --target "$(git rev-parse HEAD)" \
  --title "BispoTv $versao" \
  --notes-file "$notas" \
  $extra \
  build/release/BispoTv.dmg
  # Quando existirem os outros apps:
  # $(ls build/release/*.apk build/release/*.zip 2>/dev/null)

echo "pronto: https://github.com/$repo/releases/tag/v$versao"
