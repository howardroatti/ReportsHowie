#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gera os assets visuais do manual (docs/index.html + docs/MANUAL.md):

  - docs/exemplos/<nome>.html  -> export HTML self-contained dos relatorios FISCAIS
                                   (embutidos no help via <iframe>).
  - docs/img/gallery/<nome>.png -> print (pagina 1) de TODOS os relatorios
                                    documentados, para a galeria e para o Markdown.

E, se os marcadores existirem no index.html, injeta o grid da galeria de demos
genericos entre:
    <!-- gallery:auto:start -->  ...  <!-- gallery:auto:end -->

Nada aqui edita a prosa dos tutoriais fiscais (essa e escrita a mao). O script so
regenera os arquivos que o help referencia por caminho relativo estavel, entao um
unico comando poe o manual em dia quando um layout de demo muda:

    py docs/build_gallery.py

Requer: rhtool.exe compilado (tools/rhtool) e pdftoppm no PATH (MiKTeX/poppler).
Os PDFs intermediarios sao gerados num diretorio temporario e apagados (nao vao
versionados — sao grandes por causa das fontes embutidas).
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    Image = None

HERE = Path(__file__).resolve().parent          # .../docs
REPO = HERE.parent                              # raiz do repositorio
DEMOS = REPO / "demos"
EXEMPLOS = HERE / "exemplos"
GALLERY_IMG = HERE / "img" / "gallery"
INDEX_HTML = HERE / "index.html"

PDF_DPI = 110
MAX_STITCH_PAGES = 4     # limite de paginas empilhadas na miniatura

# nome, kind ("fiscal"|"generic"), descricao (usada na galeria de genericos)
REPORTS = [
    # --- fiscais: geram HTML (iframe) + PNG ---
    ("danfe", "fiscal", "DANFE — Nota Fiscal Eletronica (produtos)."),
    ("nfce",  "fiscal", "NFC-e — cupom fiscal em bobina 80 mm, com QR Code."),
    ("dacte", "fiscal", "DACTE — Conhecimento de Transporte Eletronico (CT-e)."),
    ("mdfe",  "fiscal", "DAMDFE — Manifesto de Documentos Fiscais (MDF-e)."),
    ("nfse",  "fiscal", "NFS-e — Nota Fiscal de Servico (prefeitura)."),
    ("dacce", "fiscal", "DACCE — Carta de Correcao Eletronica (CC-e)."),
    # --- genericos: so PNG na galeria ---
    ("fatura",      "generic", "Fatura/duplicata com itens, parcelas e boleto (Code128)."),
    ("matricial",   "generic", "Matricial em paisagem, grupos com subtotais e paginacao."),
    ("mala_direta", "generic", "Mala direta — uma carta por destinatario (1 pagina/registro)."),
    ("catalogo",    "generic", "Catalogo de produtos com codigo de barras e QR por item."),
    ("vendas",      "generic", "Vendas por categoria com subtotais, total e grafico de barras."),
]


def find_rhtool() -> Path:
    env = os.environ.get("REPORTSHOWIE_RHTOOL")
    if env and Path(env).exists():
        return Path(env)
    candidates = [
        REPO / "tools" / "rhtool" / "rhtool.exe",
        REPO / "tools" / "rhtool" / "Win64" / "Debug" / "rhtool.exe",
        REPO / "tools" / "rhtool" / "Win32" / "Debug" / "rhtool.exe",
        REPO / "tools" / "rhtool" / "Win64" / "Release" / "rhtool.exe",
        REPO / "tools" / "rhtool" / "Win32" / "Release" / "rhtool.exe",
    ]
    for c in candidates:
        if c.exists():
            return c
    sys.exit("ERRO: rhtool.exe nao encontrado. Compile tools/rhtool no IDE "
             "ou defina REPORTSHOWIE_RHTOOL.")


def find_pdftoppm() -> str:
    exe = shutil.which("pdftoppm")
    if exe:
        return exe
    for c in (r"C:\Program Files\MiKTeX\miktex\bin\x64\pdftoppm.exe",
              r"C:\Program Files\poppler\bin\pdftoppm.exe"):
        if Path(c).exists():
            return c
    sys.exit("ERRO: pdftoppm nao encontrado no PATH (instale poppler/MiKTeX).")


def run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError("falhou: %s\n%s\n%s"
                           % (" ".join(str(c) for c in cmd),
                              proc.stdout.strip(), proc.stderr.strip()))


def export_html(rhtool: Path, name: str) -> None:
    src = DEMOS / (name + ".rhr")
    data = DEMOS / (name + ".data.json")
    out = EXEMPLOS / (name + ".html")
    args = [str(rhtool), "export", str(src), str(out)]
    if data.exists():
        args += ["--data", str(data)]
    run(args)
    print("  html  -> %s (%d KB)" % (out.relative_to(REPO), out.stat().st_size // 1024))


def _stitch(pages: list[Path], out: Path) -> None:
    """Empilha verticalmente os PNGs de pagina (com separador) num unico PNG."""
    imgs = [Image.open(p).convert("RGB") for p in pages]
    gap = 8
    w = max(i.width for i in imgs)
    h = sum(i.height for i in imgs) + gap * (len(imgs) - 1)
    canvas = Image.new("RGB", (w, h), "white")
    y = 0
    for k, im in enumerate(imgs):
        if k:
            # linha separadora fina entre paginas
            for x in range(w):
                canvas.putpixel((x, y - gap // 2), (208, 215, 222))
        canvas.paste(im, (0, y))
        y += im.height + gap
    canvas.save(out)


def export_png(rhtool: Path, pdftoppm: str, name: str, tmp: Path) -> None:
    src = DEMOS / (name + ".rhr")
    data = DEMOS / (name + ".data.json")
    pdf = tmp / (name + ".pdf")
    args = [str(rhtool), "export", str(src), str(pdf)]
    if data.exists():
        args += ["--data", str(data)]
    run(args)
    out = GALLERY_IMG / (name + ".png")
    prefix = tmp / (name + "_p")
    run([pdftoppm, "-png", "-r", str(PDF_DPI), str(pdf), str(prefix)])
    pages = sorted(tmp.glob(name + "_p-*.png"),
                   key=lambda p: int(re.search(r"-(\d+)\.png$", p.name).group(1)))
    extra = ""
    if len(pages) > 1 and Image is not None:
        used = pages[:MAX_STITCH_PAGES]
        _stitch(used, out)
        extra = " [%d pag empilhadas%s]" % (
            len(used), "" if len(pages) <= MAX_STITCH_PAGES
            else " de %d" % len(pages))
    else:
        shutil.copyfile(pages[0], out)
        if len(pages) > 1:
            extra = " [pag 1 de %d; Pillow ausente]" % len(pages)
    print("  png   -> %s (%d KB)%s"
          % (out.relative_to(REPO), out.stat().st_size // 1024, extra))
    for p in pages:
        try:
            p.unlink()
        except OSError:
            pass


def gallery_fragment() -> str:
    """HTML do grid da galeria de demos genericos."""
    figs = []
    for name, kind, desc in REPORTS:
        if kind != "generic":
            continue
        figs.append(
            '        <figure class="shot">\n'
            '          <img src="img/gallery/%s.png" alt="%s" loading="lazy">\n'
            '          <figcaption><strong>%s</strong> — %s '
            '<a href="../demos/%s.rhr"><code>demos/%s.rhr</code></a></figcaption>\n'
            '        </figure>' % (name, desc, name, desc, name, name))
    return "\n".join(figs)


def inject_gallery() -> None:
    start = "<!-- gallery:auto:start -->"
    end = "<!-- gallery:auto:end -->"
    html = INDEX_HTML.read_text(encoding="utf-8")
    i, j = html.find(start), html.find(end)
    if i == -1 or j == -1:
        print("  (marcadores gallery:auto ausentes no index.html — grid nao injetado)")
        return
    frag = gallery_fragment()
    new = html[:i + len(start)] + "\n" + frag + "\n        " + html[j:]
    if new != html:
        INDEX_HTML.write_text(new, encoding="utf-8")
        print("  grid da galeria injetado em docs/index.html")
    else:
        print("  grid da galeria ja estava atualizado")


def main() -> None:
    rhtool = find_rhtool()
    pdftoppm = find_pdftoppm()
    EXEMPLOS.mkdir(parents=True, exist_ok=True)
    GALLERY_IMG.mkdir(parents=True, exist_ok=True)
    print("rhtool  : %s" % rhtool)
    print("pdftoppm: %s" % pdftoppm)
    with tempfile.TemporaryDirectory(prefix="rh_gallery_") as td:
        tmp = Path(td)
        for name, kind, _desc in REPORTS:
            print("[%s] %s" % (kind, name))
            if kind == "fiscal":
                export_html(rhtool, name)
            export_png(rhtool, pdftoppm, name, tmp)
    inject_gallery()
    print("OK.")


if __name__ == "__main__":
    main()
