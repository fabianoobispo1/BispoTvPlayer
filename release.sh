#!/bin/bash
#
# Publica uma versão: monta o DMG do Mac, o zip do Windows (de ../BispoTvWin) e
# o APK da TV Box (de ../BispoTvAndroid), e sobe os três no mesmo release, com o
# mesmo número.
#
# A versão sai do Info.plist e é gravada também no Cargo.toml do Windows e no
# Gradle da TV Box. O nome dos arquivos é o contrato com os atualizadores: o
# Mac procura um .dmg, o Windows o BispoTv-Windows.zip, a TV Box o BispoTv.apk,
# e o site linka os três.
#
# O trecho comentado monta o app do celular, que ainda não existe.
#
#   ./release.sh                 usa a versão do Info.plist
#   ./release.sh 1.1.0           marca esta versão antes de publicar
#   ./release.sh 1.1.0 --rascunho  cria como rascunho, para revisar no site
set -euo pipefail
cd "$(dirname "$0")"

PLIST="Info.plist"
WIN="../BispoTvWin"
TV="../BispoTvAndroid"
GRADLE="$TV/app/build.gradle.kts"
JAVA17="/opt/homebrew/opt/openjdk@17"

versao="${1:-}"
if [ -n "$versao" ] && [ "${versao:0:2}" != "--" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $versao" "$PLIST"
  if [ -d "$WIN" ]; then
    sed -i '' "1,/^version = /s/^version = \".*\"/version = \"$versao\"/" "$WIN/Cargo.toml"
  fi
  # O versionCode precisa só crescer, então vira um número a partir da versão:
  # 1.2.3 -> 10203. Sem isso o Android recusa a instalação por cima.
  codigo=$(python3 - "$versao" <<'PY'
import sys
p = (sys.argv[1].split(".") + ["0", "0"])[:3]
print(int(p[0]) * 10000 + int(p[1]) * 100 + int(p[2]))
PY
)
  if [ -f "$GRADLE" ]; then
    sed -i '' "s/versionName = \".*\"/versionName = \"$versao\"/" "$GRADLE"
    sed -i '' "s/versionCode = .*/versionCode = $codigo/" "$GRADLE"
  fi
  shift
else
  versao=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
fi

echo "==> versão $versao"

echo "==> montando o DMG"
./make_dmg.sh >/dev/null
mkdir -p build/release
cp "build/BispoTv.dmg" "build/release/BispoTv.dmg"

# A TV Box também procura a versão nova neste release (BispoTv.apk).
if [ -d "$TV" ]; then
  echo "==> montando o APK da TV Box"
  # assembleRelease, e não Debug: o APK publicado sai assinado com a chave de
  # $TV/chaves (ver keystore.properties), que é o que permite atualizar por cima.
  ( cd "$TV" && JAVA_HOME="$JAVA17" ANDROID_HOME="$HOME/Library/Android/sdk" \
    ./gradlew assembleRelease -q --console=plain )
  cp "$TV/app/build/outputs/apk/release/app-release.apk" "build/release/BispoTv.apk"
else
  echo "aviso: $TV não existe; o release sai sem a TV Box" >&2
fi

# O Windows procura a versão nova neste mesmo release: um release sem o zip
# ofereceria a quem está no Windows um download que não existe.
if [ -d "$WIN" ]; then
  echo "==> montando o app do Windows"
  ( cd "$WIN" && ./empacotar.sh >/dev/null )
  cp "$WIN/dist/BispoTv-Windows.zip" "build/release/BispoTv-Windows.zip"
else
  echo "aviso: $WIN não existe; o release sai só com o Mac" >&2
fi

# # O APK do celular é montado à parte (Expo) e copiado para cá antes de publicar.
# if [ -f "../BispoTv-Cell/android/app/build/outputs/apk/release/app-release.apk" ]; then
#   cp "../BispoTv-Cell/android/app/build/outputs/apk/release/app-release.apk" "build/release/BispoTvCell.apk"
# fi

if ls build/release/*.apk >/dev/null 2>&1; then
  echo "==> conferindo as assinaturas"
  APKSIGNER=$(ls "$HOME"/Library/Android/sdk/build-tools/*/apksigner | tail -1)
  for apk in build/release/*.apk; do
    echo "    $(basename "$apk"): $(JAVA_HOME="$JAVA17" "$APKSIGNER" verify --print-certs "$apk" 2>/dev/null \
      | grep -m1 -o 'SHA-256 digest: .*')"
  done
fi

# As notas: NOTAS.md na raiz, se você escreveu uma; senão, os commits desde a
# última versão. Fica fora de build/, que o build.sh apaga a cada montagem.
notas="build/release/NOTAS.md"
{
  echo "## Bispo TV $versao"
  echo
  if [ -f NOTAS.md ]; then
    cat NOTAS.md
  else
    git log --pretty="- %s" "$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)"..HEAD \
      | grep -v "^- Merge" || true
  fi
  cat <<'INSTALAR'

### Como instalar

**Mac** (chip Apple, macOS 15 ou mais novo):

1. Baixe o `BispoTv.dmg` abaixo, abra e arraste o Bispo TV para Aplicativos.
2. Na primeira vez, o macOS avisa que não pode verificar o desenvolvedor (o app
   não é assinado pela Apple). Abra **Ajustes do Sistema → Privacidade e
   Segurança**, desça até o aviso do Bispo TV e clique em **Abrir Mesmo Assim**.

**Windows** (10 ou 11, 64 bits):

1. Baixe o `BispoTv-Windows.zip` abaixo, clique com o botão direito nele e
   escolha **Extrair Tudo...**.
2. Abra o **Bispo TV.exe** de dentro da pasta extraída (a `libmpv-2.dll` precisa
   ficar ao lado dele).
3. Se o Windows Defender avisar, clique em **Mais informações** e depois em
   **Executar assim mesmo**: o app não tem assinatura paga da Microsoft.

**TV Box, Fire TV Stick, Android TV e Google TV** (Android 6 ou mais novo):

1. Instale o app **Downloader** pela loja do aparelho.
2. Permita que ele instale apps (Fire TV: Configurações › Meu Fire TV ›
   Opções do desenvolvedor › Instalar apps desconhecidos).
3. No Downloader, digite `bispotv.pages.dev/tvbox` e instale o `BispoTv.apk`.

As licenças do FFmpeg (Mac) e do mpv (Windows) vão junto: no Mac, botão direito
no Bispo TV › Mostrar Conteúdo do Pacote › Contents › Resources › Licencas; no
Windows, a pasta Licencas ao lado do programa.
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
if [ -d "$WIN" ]; then
  ( cd "$WIN"
    if ! git diff --quiet -- Cargo.toml Cargo.lock; then
      git commit -q -m "Versão $versao" -- Cargo.toml Cargo.lock
    fi
    git push -q origin HEAD )
fi
if [ -d "$TV" ]; then
  ( cd "$TV"
    if ! git diff --quiet -- app/build.gradle.kts; then
      git commit -q -m "Versão $versao" -- app/build.gradle.kts
    fi
    git push -q origin HEAD )
fi

# Com o remote "upstream" (o original, do sincronizar_original.sh) o gh não
# sabe sozinho em qual repositório publicar: é sempre no origin.
repo="$(git remote get-url origin | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##')"

echo "==> publicando v$versao em $repo"
gh release create "v$versao" --repo "$repo" \
  --target "$(git rev-parse HEAD)" \
  --title "Bispo TV $versao" \
  --notes-file "$notas" \
  $extra \
  build/release/BispoTv.dmg \
  $(ls build/release/*.zip build/release/*.apk 2>/dev/null)

echo "pronto: https://github.com/$repo/releases/tag/v$versao"
