"""A chave da API do TMDB, fora do repositório.

Vem da variável TMDB_API_KEY ou de arquivos-gerados/tmdb-chave.txt (que o git
ignora). A chave é pessoal: cada um pede a sua em themoviedb.org → Configurações
→ API.
"""

import os
from pathlib import Path

ARQUIVO = Path(__file__).resolve().parent / "arquivos-gerados" / "tmdb-chave.txt"


def chave_tmdb() -> str:
    if os.environ.get("TMDB_API_KEY"):
        return os.environ["TMDB_API_KEY"].strip()
    try:
        guardada = ARQUIVO.read_text(encoding="utf-8").strip()
    except OSError:
        guardada = ""
    if guardada:
        return guardada
    raise SystemExit(
        f"Chave do TMDB não encontrada: defina TMDB_API_KEY ou grave-a em {ARQUIVO}"
    )
