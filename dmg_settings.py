# Janela do DMG, lida pelo dmgbuild (make_dmg.sh passa app e fundo com -D).
# As posições (em pontos, origem no canto de cima) batem com o desenho de
# MakeDmgBackground.swift; mudou aqui, muda lá.
import os

app = defines["app"]            # noqa: F821 — o dmgbuild injeta `defines`
fundo = defines["fundo"]        # noqa: F821

nome_app = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
# As licenças do ffmpeg vão dentro do app (Contents/Resources/Licencas).
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [nome_app]

background = fundo
window_rect = ((200, 120), (660, 440))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    nome_app: (175, 205),
    "Applications": (485, 205),
}
