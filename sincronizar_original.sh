#!/bin/bash
#
# Traz para cá as mudanças do app feitas no repositório original
# (gabrielsaimo/SaimoPlayer).
#
# Os dois repositórios não têm histórico em comum, então não dá para fazer um
# merge do git. O que existe é o `.upstream-base`: o commit do original de onde
# este código saiu (ou foi sincronizado pela última vez). Para cada arquivo do
# app que o original mudou desde então, é feita uma mescla de três vias:
#
#   base   = o arquivo no commit do .upstream-base
#   deles  = o arquivo no original agora
#   nosso  = o arquivo daqui
#
# Base e deles passam antes pela mesma troca de nomes deste repositório
# (Saimo TV -> Bispo TV etc.), para que só as mudanças de verdade apareçam. O
# que foi mudado só aqui (URLs, chave do TMDB, telemetria) continua como está.
#
# Nada é commitado: o resultado fica na pasta para você revisar com
# `git diff` e commitar. Para desfazer tudo: `git checkout -- . && git clean -fd Sources`.
#
#   ./sincronizar_original.sh           traz as mudanças
#   ./sincronizar_original.sh --ver     só lista o que mudou no original
set -euo pipefail
cd "$(dirname "$0")"

ORIGINAL="https://github.com/gabrielsaimo/SaimoPlayer.git"
BASE_ARQ=".upstream-base"
# O que é do app. Catálogo, acervo e scripts de coleta ficam de fora.
CAMINHOS=(Sources Info.plist build.sh make_dmg.sh make_icon.sh MakeIcon.swift bundle_ffmpeg.py)

# A mesma troca de nomes feita ao trazer o código para cá. Vale para o conteúdo
# e para o nome dos arquivos (Sources/SaimoApp.swift -> Sources/BispoTvApp.swift).
renomear() {
  sed -e 's#/Applications/Saimo TV\.app#/Applications/Bispo TV.app#g' \
      -e 's#build/Saimo TV\.app#build/Bispo TV.app#g' \
      -e 's#SaimoTV-Catalog#BispoTv-Catalog#g' \
      -e 's#dev\.saimo\.#dev.bispotv.#g' \
      -e 's#Saimo Connect#Bispo TV Connect#g' \
      -e 's#o app Saimo #o app Bispo TV #g' \
      -e "s#\"saimo-tv\"#\"bispotv\"#g" \
      -e 's#_saimotv\._tcp#_bispotv._tcp#g' \
      -e 's#[[:<:]]8999[[:>:]]#8988#g' \
      -e 's#Saimo TV#Bispo TV#g' \
      -e 's#SAIMO TV#BISPO TV#g' \
      -e 's#SaimoApp#BispoTvApp#g' \
      -e 's#github\.com/gabrielsaimo/SaimoPlayer/releases#github.com/fabianoobispo1/BispoTvPlayer/releases#g' \
      -e 's#https://saimo-monitor\.gabrielsaimo68\.workers\.dev/v1/eventos#https://bispotv-api.fabianoobispo.com.br/v1/eventos#g' \
      -e 's#Saimo Monitor#monitor do Bispo TV#g' \
      -e 's#"saimo\.m3u"#"bispotv.m3u"#g' \
      -e 's#sender-saimo#sender-bispotv#g' \
      -e 's#saimo-remux#bispotv-remux#g' \
      -e 's#string: "Saimo"#string: "Bispo"#g' \
      -e 's#SaimoTV-Android#@@ANDROID@@#g' \
      -e 's#SaimoTV#BispoTv#g' \
      -e 's#@@ANDROID@@#SaimoTV-Android#g'
}

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$ORIGINAL"
  # Só o histórico, sem baixar o acervo inteiro: os arquivos vêm sob demanda.
  git config remote.upstream.promisor true
  git config remote.upstream.partialclonefilter blob:none
fi
echo "==> buscando o original"
git fetch -q --filter=blob:none upstream main

base="$(cat "$BASE_ARQ")"
novo="$(git rev-parse upstream/main)"

mudados="$(git diff --name-status "$base" "$novo" -- "${CAMINHOS[@]}")"
if [ -z "$mudados" ]; then
  echo "nada mudou no app desde $(git log -1 --format='%h (%ad)' --date=short "$base")."
  git rev-parse "$novo" > "$BASE_ARQ"
  exit 0
fi

echo "==> commits do original que mexem no app:"
git log --format='    %h %ad %s' --date=short "$base..$novo" -- "${CAMINHOS[@]}"

if [ "${1:-}" = "--ver" ]; then
  echo
  echo "arquivos:"
  printf '%s\n' "$mudados" | sed 's/^/    /'
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "==> mesclando"
# Arquivo renomeado no original (R100 velho novo) vira apagar + criar.
printf '%s\n' "$mudados" \
  | awk -F'\t' '$1 ~ /^R/ {print "D\t" $2; print "A\t" $3; next} {print $1 "\t" $2}' \
  | while IFS=$'\t' read -r estado arquivo; do
  nosso="$(printf '%s' "$arquivo" | renomear)"
  case "$estado" in
    A)
      git show "$novo:$arquivo" | renomear > "$tmp/deles"
      if [ -e "$nosso" ] && ! cmp -s "$nosso" "$tmp/deles"; then
        echo "    !  $nosso: novo no original, mas já existe aqui diferente — deixei o daqui"
        echo "$nosso" >> "$tmp/conflitos"
      else
        mkdir -p "$(dirname "$nosso")"
        cp "$tmp/deles" "$nosso"
        echo "    +  $nosso"
      fi
      ;;
    D)
      git show "$base:$arquivo" | renomear > "$tmp/base"
      if [ ! -e "$nosso" ]; then
        :
      elif cmp -s "$nosso" "$tmp/base"; then
        rm "$nosso"
        echo "    -  $nosso"
      else
        echo "    !  $nosso: apagado no original, mas mudado aqui — deixei o daqui"
        echo "$nosso" >> "$tmp/conflitos"
      fi
      ;;
    *)
      git show "$base:$arquivo" | renomear > "$tmp/base"
      git show "$novo:$arquivo" | renomear > "$tmp/deles"
      if [ ! -e "$nosso" ]; then
        echo "    !  $nosso: mudou no original, mas não existe aqui — pulei"
        continue
      fi
      if git merge-file -L "BispoTv" -L "base" -L "original" "$nosso" "$tmp/base" "$tmp/deles"; then
        echo "    ~  $nosso"
      else
        echo "    !  $nosso: conflito — procure por <<<<<<< no arquivo"
        echo "$nosso" >> "$tmp/conflitos"
      fi
      ;;
  esac
done

git rev-parse "$novo" > "$BASE_ARQ"

echo
if [ -s "$tmp/conflitos" ]; then
  echo "Mesclado, com $(wc -l < "$tmp/conflitos" | tr -d ' ') arquivo(s) para resolver à mão:"
  sed 's/^/    /' "$tmp/conflitos"
  echo "Resolva, rode ./build.sh e então commite."
else
  echo "Mesclado sem conflitos. Confira com 'git diff', rode ./build.sh e commite."
fi
