#!/usr/bin/env python3
"""Copies ffmpeg and every non-system dylib it needs into the .app.

The DASH/ClearKey and HEVC-in-TS channels are repackaged by ffmpeg at runtime,
so a machine without Homebrew would otherwise lose them. Dependencies are
rewritten to load from Contents/Frameworks, making the bundle self-contained.
"""
import os
import glob
import json
import re
import shutil
import subprocess
import sys

SYSTEM_PREFIXES = ("/usr/lib/", "/System/")


def resolve_dependency(path):
    """Find the exact dylib ABI, even after Homebrew changes its opt symlink."""
    real = os.path.realpath(path)
    if os.path.isfile(real):
        return real
    for prefix in ("/opt/homebrew", "/usr/local"):
        marker = prefix + "/opt/"
        if path.startswith(marker):
            formula, relative = path[len(marker):].split("/", 1)
            candidates = sorted(glob.glob(
                os.path.join(prefix, "Cellar", formula, "*", relative)), reverse=True)
            for candidate in candidates:
                if os.path.isfile(candidate):
                    return os.path.realpath(candidate)
    raise FileNotFoundError(f"Biblioteca necessária ao pacote não encontrada: {path}")


def deps(binary):
    out = subprocess.run(["otool", "-L", binary], capture_output=True, text=True, check=True).stdout
    found = []
    for line in out.splitlines()[1:]:
        path = line.strip().split(" (")[0]
        if not path or path.startswith("@"):
            continue
        if path.startswith(SYSTEM_PREFIXES):
            continue
        found.append(path)
    return found


def formula_of(path):
    """("x264", "r3222") para um arquivo dentro do Cellar do Homebrew."""
    m = re.search(r"/Cellar/([^/]+)/([^/]+)/", os.path.realpath(path))
    return (m.group(1), m.group(2)) if m else None


def write_licenses(app, files):
    """Licenças de tudo o que foi embutido, em Contents/Resources/Licencas.

    O ffmpeg do Homebrew é GPL (e as bibliotecas que ele puxa, como x264 e
    x265, também): distribuí-lo dentro do app exige levar junto o texto das
    licenças e dizer onde está o código-fonte de cada uma.
    """
    formulas = {}
    for path in files:
        found = formula_of(path)
        if found:
            formulas[found[0]] = found[1]
    if not formulas:
        return
    info = {}
    try:
        out = subprocess.run(["brew", "info", "--json=v2", *sorted(formulas)],
                             capture_output=True, text=True, check=True).stdout
        for f in json.loads(out)["formulae"]:
            info[f["name"]] = f
    except (OSError, subprocess.CalledProcessError, ValueError, KeyError):
        pass

    pasta = os.path.join(app, "Contents", "Resources", "Licencas")
    shutil.rmtree(pasta, ignore_errors=True)
    os.makedirs(pasta)
    linhas = [
        "COMPONENTES DE TERCEIROS",
        "",
        "O BispoTv inclui o FFmpeg (https://ffmpeg.org) e as bibliotecas abaixo,",
        "copiados sem modificação do Homebrew. Cada um segue a própria licença; o",
        "texto de cada licença está na pasta com o nome do componente. O código-fonte",
        "correspondente a cada versão está no endereço indicado.",
        "",
    ]
    for nome in sorted(formulas):
        versao = formulas[nome]
        f = info.get(nome, {})
        fonte = (f.get("urls", {}).get("stable", {}) or {}).get("url", "")
        linhas += [
            f"{nome} {versao}",
            f"  licença: {f.get('license') or 'ver pasta'}",
            f"  site:    {f.get('homepage', '')}",
            f"  fonte:   {fonte}",
            "",
        ]
        destino = os.path.join(pasta, nome)
        raiz = os.path.join("/opt/homebrew/Cellar", nome, versao)
        for arq in sorted(glob.glob(os.path.join(raiz, "*"))):
            base = os.path.basename(arq).upper()
            if os.path.isfile(arq) and base.startswith(("COPYING", "LICENSE", "LICENCE", "NOTICE")):
                os.makedirs(destino, exist_ok=True)
                shutil.copy2(arq, destino)
    with open(os.path.join(pasta, "LEIA-ME.txt"), "w", encoding="utf-8") as saida:
        saida.write("\n".join(linhas))
    print(f"licenças de {len(formulas)} componentes em Contents/Resources/Licencas")


def main():
    app = sys.argv[1]
    # ffprobe comes along because the remuxer counts audio tracks before it
    # can tell the HLS muxer how many renditions to write.
    tools = {}
    for name in ("ffmpeg", "ffprobe"):
        path = shutil.which(name) or f"/opt/homebrew/bin/{name}"
        if os.path.exists(path):
            tools[name] = path
    if "ffmpeg" not in tools:
        print("ffmpeg não encontrado — DMG sairá sem suporte a DASH/HEVC")
        return 0

    resources = os.path.join(app, "Contents", "Resources")
    frameworks = os.path.join(app, "Contents", "Frameworks")
    os.makedirs(resources, exist_ok=True)
    os.makedirs(frameworks, exist_ok=True)

    targets = []
    for name, path in tools.items():
        target = os.path.join(resources, name)
        shutil.copy2(os.path.realpath(path), target)
        os.chmod(target, 0o755)
        targets.append(target)

    # Breadth-first over the dependency graph, copying each library once.
    copied = {}
    seen_deps = []
    queue = list(targets)
    while queue:
        binary = queue.pop()
        for dep in deps(binary):
            name = os.path.basename(dep)
            if name not in copied:
                real = resolve_dependency(dep)
                dest = os.path.join(frameworks, name)
                shutil.copy2(real, dest)
                os.chmod(dest, 0o755)
                subprocess.run(["install_name_tool", "-id",
                                f"@loader_path/{name}", dest], capture_output=True, check=True)
                copied[name] = dest
                seen_deps.append(dep)
                queue.append(dest)

            # ffmpeg sits in Resources, the libraries next to each other.
            new = (f"@executable_path/../Frameworks/{name}"
                   if binary in targets else f"@loader_path/{name}")
            subprocess.run(["install_name_tool", "-change", dep, new, binary],
                           capture_output=True, check=True)

    for path in list(copied.values()) + targets:
        subprocess.run(["codesign", "--force", "--sign", "-", path], capture_output=True, check=True)

    for binary in targets:
        subprocess.run([binary, "-version"], capture_output=True, check=True)

    write_licenses(app, [os.path.realpath(p) for p in tools.values()] + [
        resolve_dependency(dep) for dep in seen_deps])

    print(f"{'+'.join(sorted(tools))} embutidos com {len(copied)} bibliotecas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
