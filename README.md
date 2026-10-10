<div align="center">

<h1>BispoTv</h1>

### canais ao vivo, filmes e séries no Mac

<p>
  <img src="https://img.shields.io/badge/Swift-FA7343?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white" alt="macOS 15+">
</p>

</div>

## Sobre

Este repositório é só o **app do Mac**. Ele é baseado no app do
[Saimo TV](https://github.com/gabrielsaimo/SaimoPlayer) e depende dele para os
dados:

| O quê | De onde vem |
|---|---|
| Canais ao vivo (`catalogo.txt`, `canais.txt`, `restritos.txt`) | repositório original |
| Filmes, séries, fichas, destaques e legendas (`vod/`) | repositório original |
| Capas e fichas do TMDB | API do TMDB, com a sua chave |
| Servidores desligados (`fontes-desativadas.json`) | este repositório |
| Atualizações do app (DMG) | releases deste repositório |

Quem mantém a lista de canais e o acervo é o repositório original; aqui não há
nada para atualizar à mão.

## O que o app tem

- Canais ao vivo com várias fontes por canal e troca automática quando uma cai
- Ao vivo nunca pausa: pausa só existe em filme e série
- Guia de programação (meuguia.tv, guiadetv e feeds XMLTV)
- Filmes, séries, animes e doramas com ficha, elenco e episódios
- Pular abertura e recapitulação com tempos do [TheIntroDB](https://theintrodb.org)
- Próximo episódio nos créditos e continuar de onde parou
- Favoritos, busca, áudio, legendas e qualidade; filmes e séries ganham legendas do
  OpenSubtitles (pt-BR, pt-PT, inglês, espanhol) com ajuste de sincronia, sem chave
  nem cadastro (`Sources/Legendas.swift`)

SwiftUI + AVFoundation. O AVFoundation não abre DASH nem HEVC em TS, então o app
tem um proxy HTTP local (`ProxyServer.swift`) e um ffmpeg embutido
(`Remuxer.swift`) que remontam o que ele recusa. Também tem PiP, AirPlay e
Chromecast (`Cast.swift`).

## Compilar

Precisa das Command Line Tools (`xcode-select --install`); o Xcode completo é
opcional. Sem ele, o `build.sh` usa o SDK do macOS 26.5.

A chave do TMDB (capas e fichas) entra no app na hora de compilar e nunca vai
para o git. Peça a sua em themoviedb.org → Configurações → API e guarde:

```bash
mkdir -p arquivos-gerados
echo "SUA_CHAVE" > arquivos-gerados/tmdb-chave.txt   # ou: export TMDB_API_KEY=...
```

```bash
./build.sh                  # monta build/BispoTv.app
open build/BispoTv.app
./make_dmg.sh               # gera build/BispoTv.dmg, com o ffmpeg embutido
```

O DMG precisa do ffmpeg instalado (`brew install ffmpeg`).

## Trazer as mudanças do original

O `.upstream-base` guarda o commit do repositório original de onde este código
saiu (ou foi sincronizado pela última vez).

```bash
./sincronizar_original.sh --ver   # só mostra o que mudou no app original
./sincronizar_original.sh         # traz as mudanças para cá
```

O script mescla arquivo por arquivo, já trocando os nomes (Saimo TV → BispoTv),
e mantém o que foi mudado só aqui. Nada é commitado: confira com `git diff`,
rode `./build.sh` e commite. Se houver conflito, o arquivo fica com marcas
`<<<<<<<` para resolver à mão.

## Publicar uma versão

```bash
./release.sh 2.1.2              # marca a versão, monta o DMG e publica no release
```

O passo a passo completo (preparar o Mac, sincronizar com o original, testar,
publicar e conferir), os problemas comuns e as métricas estão em
[PUBLICAR.md](PUBLICAR.md).

## Avisos

- Fontes externas podem sair do ar sem aviso; o sistema de fontes reserva existe
  por isso.
- Respeite direitos autorais e de distribuição do conteúdo.
- Não coloque tokens, credenciais ou dados pessoais no código.
