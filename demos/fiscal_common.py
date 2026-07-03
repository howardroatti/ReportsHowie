# -*- coding: utf-8 -*-
"""
Primitivas compartilhadas pelos geradores de Documentos Auxiliares fiscais
(DANFE, NFC-e, DACTE, DAMDFE, NFS-e). Cada gerador monta o layout do seu
documento com estes tijolos e grava um par .rhr + .data.json.

Unidade do ReportsHowie = 0,1 mm inteiros. Cores em BGR (TColor).
"""
import json
import os

FONT = "Segoe UI"
BLACK = 0
WHITE = 16777215
GRAY = 12632256   # cinza claro (BGR) para faixas de titulo


def mm(v):
    """Milimetros -> unidade de relatorio (0,1 mm)."""
    return int(round(v * 10))


def font(size, style="", color=BLACK):
    return {"name": FONT, "size": size, "color": color, "style": style}


def frame(sides="", width=2, color=BLACK):
    return {"sides": sides, "color": color, "width": width}


def txt(objs, l, t, w, h, text, size=7, style="", align="left", valign="top",
        sides="", wrap=False, color=BLACK):
    """Texto (rotulo/valor). 'sides' desenha a moldura da celula (ex.: 'LTRB')."""
    objs.append({
        "type": "text", "name": "", "left": l, "top": t, "width": w, "height": h,
        "visible": True, "frame": frame(sides),
        "text": text, "dataField": "",
        "font": font(size, style, color),
        "hAlign": align, "vAlign": valign, "wordWrap": wrap,
        "color": WHITE, "transparent": True,
    })


def cell(objs, l, t, w, h, label, value, vsize=7, vstyle="", valign_val="right",
         sides="LTRB", lsize=5):
    """Celula estilo DAC: rotulo pequeno no topo + valor abaixo, com moldura."""
    txt(objs, l, t, w, h, "", sides=sides)                       # moldura
    txt(objs, l + mm(1), t + mm(0.5), w - mm(2), mm(3), label, size=lsize)
    txt(objs, l + mm(1), t + mm(3.3), w - mm(2), h - mm(3.8), value,
        size=vsize, style=vstyle, align=valign_val, valign="top")


def box(objs, l, t, w, h, penw=2):
    objs.append({
        "type": "shape", "name": "", "left": l, "top": t, "width": w, "height": h,
        "visible": True, "frame": frame(),
        "kind": "rectangle", "penColor": BLACK, "penWidth": penw,
        "brushColor": WHITE, "transparent": True,
    })


def fill(objs, l, t, w, h, color=GRAY):
    """Retangulo preenchido (faixa de titulo de secao)."""
    objs.append({
        "type": "shape", "name": "", "left": l, "top": t, "width": w, "height": h,
        "visible": True, "frame": frame(),
        "kind": "rectangle", "penColor": BLACK, "penWidth": 1,
        "brushColor": color, "transparent": False,
    })


def vline(objs, l, t, h):
    objs.append({
        "type": "line", "name": "", "left": l, "top": t, "width": 0, "height": h,
        "visible": True, "frame": frame(), "penColor": BLACK, "penWidth": 2,
    })


def hline(objs, l, t, w):
    objs.append({
        "type": "line", "name": "", "left": l, "top": t, "width": w, "height": 0,
        "visible": True, "frame": frame(), "penColor": BLACK, "penWidth": 2,
    })


def barcode(objs, l, t, w, h, text, symbology="code128"):
    objs.append({
        "type": "barcode", "name": "", "left": l, "top": t, "width": w, "height": h,
        "visible": True, "frame": frame(),
        "symbology": symbology, "text": text, "dataField": "",
        "barColor": BLACK, "showText": False, "moduleWidth": 0,
        "font": font(6),
    })


def qrcode(objs, l, t, size, text):
    barcode(objs, l, t, size, size, text, symbology="qrcode")


def band(band_type, name, height, objects, dataset="", can_grow=False):
    return {
        "bandType": band_type, "name": name, "height": height,
        "visible": True, "canGrow": can_grow, "canShrink": False, "printIfEmpty": False,
        "dataSetName": dataset, "groupExpression": "",
        "masterKeyExpr": "", "detailKeyField": "",
        "objects": objects,
    }


def page(name, pw, ph, margin, bands, orientation="portrait"):
    return {
        "name": name, "paperWidth": pw, "paperHeight": ph, "orientation": orientation,
        "marginLeft": margin, "marginTop": margin,
        "marginRight": margin, "marginBottom": margin,
        "bands": bands,
    }


def save(report, data, basename):
    """Grava <basename>.rhr e <basename>.data.json ao lado deste modulo."""
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, basename + ".rhr"), "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    with open(os.path.join(here, basename + ".data.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    nobj = sum(len(b["objects"]) for p in report["pages"] for b in p["bands"])
    print("OK: %s.rhr (%d objetos) + %s.data.json" % (basename, nobj, basename))
