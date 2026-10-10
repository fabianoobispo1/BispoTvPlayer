# Publicar uma versão nova do Bispo TV

Passo a passo para lançar uma versão. Um release só leva o app do Mac
(`BispoTv.dmg`) e o do Windows (`BispoTv-Windows.zip`, de
[BispoTvWin](https://github.com/fabianoobispo1/BispoTvWin), que precisa estar
na pasta ao lado desta), com o mesmo número. O resto do projeto está no
[README](README.md).

## Uma vez só, em cada Mac

```bash
xcode-select --install            # Command Line Tools (o Xcode completo é opcional)
brew install ffmpeg gh            # ffmpeg vai dentro do DMG; gh publica o release
brew install rustup mingw-w64 p7zip   # para montar o app do Windows
rustup default stable && rustup target add x86_64-pc-windows-gnu
gh auth login                     # GitHub.com → HTTPS → login pelo navegador

# chave do TMDB (capas e fichas); fica fora do git
mkdir -p arquivos-gerados
echo "SUA_CHAVE_V3" > arquivos-gerados/tmdb-chave.txt
```

A chave é a "Chave da API" (v3, 32 caracteres) de themoviedb.org →
Configurações → API, e não o token de leitura (v4), que é bem mais longo.

## A cada versão

### 1. Trazer o que mudou no app original (opcional)

```bash
./sincronizar_original.sh --ver   # o que o autor original mudou no app
./sincronizar_original.sh         # traz para cá, sem commitar
git diff                          # confira
```

Se algum arquivo ficar com `<<<<<<<`, resolva à mão: o trecho de cima é o
daqui, o de baixo é o do original.

### 2. Testar

```bash
./build.sh && open "build/Bispo TV.app"
```

Confira pelo menos: um canal ao vivo abre, Filmes e Séries carregam com capa,
um filme toca.

### 3. Commitar

```bash
git add -A && git commit -m "O que mudou"
```

O `release.sh` faz o push; não precisa ter nada pendente além disso.

### 4. Publicar

```bash
./release.sh 2.1.2                # número novo, maior que o anterior
./release.sh 2.1.2 --rascunho     # ou como rascunho, para revisar no site antes
```

O script grava a versão no `Info.plist` e no `Cargo.toml` do Windows, monta o
DMG (com o ffmpeg e as licenças) e o zip do Windows (com o mpv e as licenças),
commita a versão nova e dá push nos dois repositórios, e cria o release
`v2.1.2` com os dois arquivos e as notas. Se `../BispoTvWin` não existir, ele
avisa e publica só o Mac — evite: o app do Windows procura a versão nova no
mesmo release e ofereceria um download que não existe. Para notas
próprias, escreva um `NOTAS.md` na raiz antes; sem ele, entram os commits desde
a versão anterior. As instruções de instalação entram sempre.

### 5. Conferir

- O release aparece em
  [Releases](https://github.com/fabianoobispo1/BispoTvPlayer/releases) com o
  `BispoTv.dmg`.
- Quem tem uma versão anterior instalada recebe o aviso de atualização em até
  uma hora com o app aberto (ou na próxima abertura).

## Regras que o atualizador do app espera

O app (`Sources/Atualizacao.swift`) procura o último release deste repositório.
Para ele funcionar:

- a tag tem que ser um número de versão: `v2.1.2` ou `2.1.2` (nada de `beta-2`);
- o número tem que ser maior que o do app instalado (compara parte por parte:
  `2.10.0` é mais novo que `2.9.3`);
- o release tem que ter o `BispoTv.dmg` (Mac) e o `BispoTv-Windows.zip`
  (Windows, que procura exatamente esse nome);
- rascunhos e pré-lançamentos não contam como "último release".

## Problemas comuns

| Sintoma | Causa e solução |
|---|---|
| `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found` | O SDK do macOS 27 das Command Line Tools não tem as macros do SwiftUI. O `build.sh` já usa o SDK 26.5; se ele não existir, instale o Xcode. |
| `aviso: sem chave do TMDB` | Falta `arquivos-gerados/tmdb-chave.txt`. O app compila, mas sem capas e fichas. |
| `ffmpeg não encontrado — DMG sairá sem suporte a DASH/HEVC` | `brew install ffmpeg`. |
| `gh: command not found` ou `not logged in` | `brew install gh && gh auth login`. |
| `No default remote repository has been set` | Versões antigas do `release.sh` não diziam ao `gh` qual repositório usar (há dois remotes: `origin` e `upstream`). O script atual já passa `--repo`; se precisar, rode `gh repo set-default fabianoobispo1/BispoTvPlayer`. |
| `release ... already exists` | Essa versão já foi publicada. Use um número novo. |
| Quem baixa vê "não é possível verificar o desenvolvedor" | Normal: o app não é assinado pela Apple. As notas do release explicam o "Abrir Mesmo Assim". Para sumir com o aviso, é preciso a conta de desenvolvedor da Apple (assinatura + notarização). |

## Métricas

O app tem telemetria (`Sources/Telemetria.swift`), **desligada**: o endereço
está vazio, e assim nada é enviado. Quando ligada, ela manda para um servidor
seu, em JSON:

| Rota | Quando | O que vai |
|---|---|---|
| `POST /hello` | ao abrir | versão, modelo do Mac, macOS, resolução, idioma |
| `POST /beat` | a cada 5 min (o servidor pode mudar com `heartbeatSeconds`) | segundos assistidos, o que está tocando, pausado, qualidade |
| `POST /event` | ao acontecer | `play_start`, `play_ok`, `play_stop`, `source_fail`, `channel_down`, `stall`, `search_miss`, `crash` |

Todo envio leva um `deviceId` (UUID sorteado na primeira abertura) e
`platform: "mac"`. Nada de nome, conta ou número de série.

Para ligar, é preciso um servidor que receba esses `POST`s (por exemplo, um
Cloudflare Worker com banco D1) e pôr o endereço em `Telemetria.swift`
(`private let base = URL(string: "https://.../v1")`). Ao ligar, avise quem usa
o app (o que é coletado e para quê).

Sem servidor nenhum, a contagem de downloads de cada release aparece na API do
GitHub: `gh release view v2.1.2 --json assets`.
