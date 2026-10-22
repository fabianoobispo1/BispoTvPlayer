#!/bin/bash
#
# Publica uma versão: monta o DMG do Mac, o zip do Windows (de ../BispoTvWin),
# o APK da TV Box (de ../BispoTvAndroid), o do celular (de ../BispoTvCell) e os
# pacotes das TVs Samsung e LG (de ../BispoTvWeb, scripts/montar_tv.sh).
#
# Desde a 2.6.0 cada app tem a sua versão e dá para publicar só os que
# mudaram. O release continua sempre com os quatro arquivos (os que não mudaram
# são copiados do release anterior), porque os atalhos do site, o monitor do
# Kuma e os apps antigos procuram tudo em /releases/latest. Junto vai o
# versoes.json ({"mac": "2.6.0", "tvbox": "2.6.1", ...}): é nele, e não na tag,
# que cada app confere se há versão nova para ele.
#
# O nome dos arquivos é o contrato com os atualizadores: o Mac procura um .dmg,
# o Windows o BispoTv-Windows.zip, a TV Box o BispoTv.apk, o celular o
# BispoTvCell.apk, e o site linka os quatro.
#
#   ./release.sh 2.6.0                  todos os apps
#   ./release.sh 2.6.1 tvbox            só a TV Box (os outros ficam como estão)
#   ./release.sh 2.6.2 mac windows      só Mac e Windows
#   ./release.sh 2.6.0 --rascunho       cria como rascunho, para revisar no site
#
# Apps: mac, windows, tvbox, celular, tvs (Samsung e LG juntas). O número vale para a tag e para os apps
# publicados nela; precisa ser maior que o do último release, mesmo que o app
# seja outro, e nunca se reutiliza.
set -euo pipefail
cd "$(dirname "$0")"

PLIST="Info.plist"
WIN="../BispoTvWin"
TV="../BispoTvAndroid"
CELL="../BispoTvCell"
WEB="../BispoTvWeb"
GRADLE="$TV/app/build.gradle.kts"
JAVA17="/opt/homebrew/opt/openjdk@17"
TODOS="mac windows tvbox celular tvs"

versao="${1:-}"
if ! [[ "$versao" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "uso: ./release.sh <versão> [mac] [windows] [tvbox] [celular] [tvs] [--rascunho]" >&2
  exit 1
fi
shift

apps=""
extra=""
for arg in "$@"; do
  case "$arg" in
    --rascunho) extra="--draft" ;;
    mac|windows|tvbox|celular|tvs) apps="$apps $arg" ;;
    *) echo "app desconhecido: $arg (use: $TODOS)" >&2; exit 1 ;;
  esac
done
[ -z "$apps" ] && apps=" $TODOS"
publica() { [[ " $apps " == *" $1 "* ]]; }

# Desde a 2.9.1 os releases ficam num repositório público só de downloads (sem
# código nem histórico), e este, o do código, pode ficar privado. Os apps e o
# site leem os arquivos e o versoes.json de lá.
repo="fabianoobispo1/BispoTv-downloads"
# Na transição, o mesmo release sai também aqui, para quem ainda está numa
# versão que procura atualização no BispoTvPlayer. Deixe vazio quando este
# repositório ficar privado.
ESPELHO="fabianoobispo1/BispoTvPlayer"

anterior=$(gh release view --repo "$repo" --json tagName -q .tagName 2>/dev/null | sed 's/^v//' || true)
# O primeiro release do repositório de downloads copia do espelho o que não for publicado.
if [ -z "$anterior" ] && [ -n "$ESPELHO" ]; then
  repo_anterior="$ESPELHO"
  anterior=$(gh release view --repo "$ESPELHO" --json tagName -q .tagName 2>/dev/null | sed 's/^v//' || true)
else
  repo_anterior="$repo"
fi
maior() {   # maior <a> <b>: a > b, número a número
  python3 -c 'import sys; f=lambda v: [int(x) for x in v.split(".")]; sys.exit(0 if f(sys.argv[1]) > f(sys.argv[2]) else 1)' "$1" "$2"
}
if [ -n "$anterior" ] && ! maior "$versao" "$anterior"; then
  echo "a versão $versao precisa ser maior que a do último release ($anterior)" >&2
  exit 1
fi

if publica mac; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $versao" "$PLIST"
fi
if publica windows && [ -d "$WIN" ]; then
  sed -i '' "1,/^version = /s/^version = \".*\"/version = \"$versao\"/" "$WIN/Cargo.toml"
fi
if publica tvbox && [ -f "$GRADLE" ]; then
  # O versionCode precisa só crescer, então vira um número a partir da versão:
  # 1.2.3 -> 10203. Sem isso o Android recusa a instalação por cima.
  codigo=$(python3 -c 'import sys; p=(sys.argv[1].split(".")+["0","0"])[:3]; print(int(p[0])*10000+int(p[1])*100+int(p[2]))' "$versao")
  sed -i '' "s/versionName = \".*\"/versionName = \"$versao\"/" "$GRADLE"
  sed -i '' "s/versionCode = .*/versionCode = $codigo/" "$GRADLE"
fi
# As TVs levam a versão do package.json do site (a casca; o app vem do site).
if publica tvs; then
  ( cd "$WEB" && npm version "$versao" --no-git-tag-version --allow-same-version >/dev/null )
fi

echo "==> versão $versao:$apps"

# Primeiro o Mac: o build.sh apaga build/ inteiro, inclusive build/release.
if publica mac; then
  echo "==> montando o DMG"
  ./make_dmg.sh >/dev/null
fi
rm -rf build/release
mkdir -p build/release
publica mac && cp "build/BispoTv.dmg" "build/release/BispoTv.dmg"

# O que não for publicado agora vem do release anterior, com a versão que tinha
# lá (do versoes.json dele; num release de antes da 2.6.0, a da tag).
anteriores="build/anteriores"
rm -rf "$anteriores" && mkdir -p "$anteriores"
gh release download --repo "$repo_anterior" --pattern versoes.json --dir "$anteriores" 2>/dev/null || true
versao_anterior() {
  python3 -c 'import json, sys
try: print(json.load(open(sys.argv[1]))[sys.argv[2]])
except Exception: print(sys.argv[3])' "$anteriores/versoes.json" "$1" "$anterior"
}
v_mac=$versao; v_windows=$versao; v_tvbox=$versao; v_celular=$versao; v_tvs=$versao
copiar() {   # copiar <app> <arquivo>
  echo "==> $1: fica na $(versao_anterior "$1") ($2 do release anterior)"
  gh release download --repo "$repo_anterior" --pattern "$2" --dir build/release
}
publica mac     || { copiar mac BispoTv.dmg;             v_mac=$(versao_anterior mac); }
publica windows || { copiar windows BispoTv-Windows.zip; v_windows=$(versao_anterior windows); }
publica tvbox   || { copiar tvbox BispoTv.apk;           v_tvbox=$(versao_anterior tvbox); }
publica celular || { copiar celular BispoTvCell.apk;     v_celular=$(versao_anterior celular); }
if ! publica tvs; then
  copiar tvs BispoTv-Samsung.wgt
  gh release download --repo "$repo_anterior" --pattern BispoTv-LG.ipk --dir build/release
  v_tvs=$(versao_anterior samsung)
fi
printf '{"mac": "%s", "windows": "%s", "tvbox": "%s", "celular": "%s", "samsung": "%s", "lg": "%s"}\n' \
  "$v_mac" "$v_windows" "$v_tvbox" "$v_celular" "$v_tvs" "$v_tvs" > build/release/versoes.json
echo "==> versoes.json: $(cat build/release/versoes.json)"

if publica tvbox; then
  echo "==> montando o APK da TV Box"
  # assembleRelease, e não Debug: o APK publicado sai assinado com a chave de
  # $TV/chaves (ver keystore.properties), que é o que permite atualizar por cima.
  ( cd "$TV" && JAVA_HOME="$JAVA17" ANDROID_HOME="$HOME/Library/Android/sdk" \
    ./gradlew assembleRelease -q --console=plain )
  cp "$TV/app/build/outputs/apk/release/app-release.apk" "build/release/BispoTv.apk"
fi

if publica windows; then
  echo "==> montando o app do Windows"
  ( cd "$WIN" && ./empacotar.sh >/dev/null )
  cp "$WIN/dist/BispoTv-Windows.zip" "build/release/BispoTv-Windows.zip"
fi

# O empacotar.sh do celular grava a versão no app.json e sai com a chave de
# $CELL/chaves.
if publica celular; then
  echo "==> montando o APK do celular"
  ( cd "$CELL" && ./empacotar.sh "$versao" >/dev/null )
  cp "$CELL/build/BispoTvCell.apk" "build/release/BispoTvCell.apk"
fi

if publica tvs; then
  echo "==> montando os pacotes das TVs Samsung e LG"
  ( cd "$WEB" && bash scripts/montar_tv.sh >/dev/null )
  cp "$WEB/build/tv/BispoTv-Samsung.wgt" "$WEB/build/tv/BispoTv-LG.ipk" build/release/
fi

# Um release sem algum dos arquivos faria o app daquela plataforma (e o atalho
# do site) oferecer um download que não existe.
for arquivo in BispoTv.dmg BispoTv-Windows.zip BispoTv.apk BispoTvCell.apk BispoTv-Samsung.wgt BispoTv-LG.ipk; do
  [ -f "build/release/$arquivo" ] || { echo "faltou build/release/$arquivo" >&2; exit 1; }
done

echo "==> conferindo as assinaturas"
APKSIGNER=$(ls "$HOME"/Library/Android/sdk/build-tools/*/apksigner | tail -1)
for apk in build/release/*.apk; do
  echo "    $(basename "$apk"): $(JAVA_HOME="$JAVA17" "$APKSIGNER" verify --print-certs "$apk" 2>/dev/null \
    | grep -m1 -o 'SHA-256 digest: .*')"
done

# As notas: NOTAS.md na raiz, se você escreveu uma; senão, os commits desde a
# última versão. Ficam em build/anteriores, fora de build/release.
nomes() {
  for a in $apps; do
    case "$a" in mac) echo "Mac" ;; windows) echo "Windows" ;; tvbox) echo "TV Box" ;; celular) echo "Celular" ;; tvs) echo "TVs Samsung e LG" ;; esac
  done | paste -sd, - | sed 's/,/, /g'
}
notas="$anteriores/NOTAS.md"
{
  echo "## Bispo TV $versao"
  echo
  echo "Nesta versão: **$(nomes)**. Versões atuais: Mac $v_mac · Windows $v_windows · TV Box $v_tvbox · Celular $v_celular · TVs Samsung e LG $v_tvs."
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
2. Abra o **Bispo TV.exe** de dentro da pasta extraída (a `libmpv-2.dll` e a
   `vulkan-1.dll` precisam ficar ao lado dele).
3. Se o Windows Defender avisar, clique em **Mais informações** e depois em
   **Executar assim mesmo**: o app não tem assinatura paga da Microsoft.

**TV Box, Fire TV Stick, Android TV e Google TV** (Android 6 ou mais novo):

1. Instale o app **Downloader** pela loja do aparelho.
2. Permita que ele instale apps (Fire TV: Configurações › Meu Fire TV ›
   Opções do desenvolvedor › Instalar apps desconhecidos).
3. No Downloader, digite `bispotv.pages.dev/tvbox` e instale o `BispoTv.apk`.

**Celular e tablet Android** (Android 7 ou mais novo):

1. No celular, abra `bispotv.pages.dev/celular` e baixe o `BispoTvCell.apk`.
2. Abra o arquivo baixado e, se o Android pedir, permita instalar apps do
   navegador.

**TV Samsung e TV LG** (2020 em diante, **em teste**: ainda não foram
instalados numa TV de verdade): exigem o modo desenvolvedor da TV e um
computador na mesma rede. O passo a passo está em `bispotv.pages.dev/app`, nas
abas Samsung e LG. O `BispoTv-Samsung.wgt` sai sem assinatura: assine com o
certificado da sua TV no Tizen Studio antes de instalar.

As licenças do FFmpeg (Mac) e do mpv (Windows) vão junto: no Mac, botão direito
no Bispo TV › Mostrar Conteúdo do Pacote › Contents › Resources › Licencas; no
Windows, a pasta Licencas ao lado do programa.
INSTALAR
} > "$notas"

# A tag é criada no GitHub em cima do main de lá: a versão nova do Info.plist
# precisa estar lá antes.
if ! git diff --quiet -- "$PLIST"; then
  git commit -q -m "Versão $versao" -- "$PLIST"
fi
echo "==> enviando para o GitHub"
git push -q origin HEAD
if publica windows; then
  ( cd "$WIN"
    if ! git diff --quiet -- Cargo.toml Cargo.lock; then
      git commit -q -m "Versão $versao" -- Cargo.toml Cargo.lock
    fi
    git push -q origin HEAD )
fi
if publica tvbox; then
  ( cd "$TV"
    if ! git diff --quiet -- app/build.gradle.kts; then
      git commit -q -m "Versão $versao" -- app/build.gradle.kts
    fi
    git push -q origin HEAD )
fi
if publica celular; then
  ( cd "$CELL"
    if ! git diff --quiet -- app.json package.json; then
      git commit -q -m "Versão $versao" -- app.json package.json
    fi
    git push -q origin HEAD )
fi
# O push do site também publica o código novo das TVs em /tv/ (Cloudflare Pages).
if publica tvs; then
  ( cd "$WEB"
    if ! git diff --quiet -- package.json package-lock.json; then
      git commit -q -m "Versão $versao" -- package.json package-lock.json
    fi
    git push -q origin HEAD )
fi

arquivos=(build/release/BispoTv.dmg build/release/BispoTv-Windows.zip
          build/release/BispoTv.apk build/release/BispoTvCell.apk
          build/release/BispoTv-Samsung.wgt build/release/BispoTv-LG.ipk
          build/release/versoes.json)

# No repositório de downloads a tag fica no commit dele (main), não no código.
echo "==> publicando v$versao em $repo"
gh release create "v$versao" --repo "$repo" \
  --title "Bispo TV $versao" \
  --notes-file "$notas" \
  $extra \
  "${arquivos[@]}"

if [ -n "$ESPELHO" ]; then
  echo "==> espelhando v$versao em $ESPELHO (transição)"
  gh release create "v$versao" --repo "$ESPELHO" \
    --target "$(git rev-parse HEAD)" \
    --title "Bispo TV $versao" \
    --notes-file "$notas" \
    $extra \
    "${arquivos[@]}"
fi

echo "pronto: https://github.com/$repo/releases/tag/v$versao"
