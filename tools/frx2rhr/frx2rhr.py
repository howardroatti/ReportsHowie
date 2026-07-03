#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
frx2rhr - Conversor de templates FastReport (.frx) para ReportsHowie (.rhr).

FastReport VCL grava o template como XML (<TfrxReport> ... <TfrxReportPage> ...).
Este script mapeia pagina, bandas e os objetos mais comuns (memo/linha/forma/
imagem/barcode) para o JSON .rhr. NAO executa PascalScript nem resolve
funcoes/expressoes que nao tenham equivalente 1:1 (ficam como TODO no texto).

Uso:
    python frx2rhr.py entrada.frx saida.rhr [--dpi 96] [--verbose]

Convencoes de coordenada:
    - Pagina (PaperWidth/PaperHeight/margens): em MILIMETROS no .frx.
    - Bandas/objetos (Left/Top/Width/Height): em PIXELS no DPI de design (96
      por padrao). rhUnit = 0,1 mm; converte px -> mm -> unidades.

Limitacoes conhecidas (ver README): fontes so nome/tamanho/estilo/cor; imagens
so quando embutidas; expressoes complexas/scripts nao convertem.
"""
import sys
import re
import json
import argparse
import xml.etree.ElementTree as ET

# ---- mapeamento de classe de banda FastReport -> bandType ReportsHowie ----
BAND_MAP = {
    "TfrxReportTitle":   "reportTitle",
    "TfrxReportSummary": "summary",
    "TfrxPageHeader":    "pageHeader",
    "TfrxPageFooter":    "pageFooter",
    "TfrxMasterData":    "masterData",
    "TfrxDetailData":    "detailData",
    "TfrxSubdetailData": "detailData",
    "TfrxGroupHeader":   "groupHeader",
    "TfrxGroupFooter":   "groupFooter",
    "TfrxChild":         "child",
}

FONTCOLOR_DEFAULT = -16777208  # clWindowText serializado (igual aos demos)


def px_to_units(px, dpi):
    """Pixel de design (dpi) -> unidade de relatorio (0,1 mm)."""
    return int(round(float(px) / dpi * 25.4 * 10))


def mm_to_units(mm):
    return int(round(float(mm) * 10))


def frx_color_to_rh(v):
    """Cor FastReport (inteiro decimal, formato Windows BGR) -> TColor (BGR)."""
    try:
        n = int(v)
    except (TypeError, ValueError):
        return 0
    # FastReport ja usa BGR (mesmo do Windows/VCL). clNone/negativos -> default.
    if n < 0:
        return FONTCOLOR_DEFAULT
    return n


def frx_style_to_str(v):
    """Font.Style FastReport (bitmask: 1=bold 2=italic 4=underline) -> 'BIU'."""
    try:
        n = int(v)
    except (TypeError, ValueError):
        return ""
    s = ""
    if n & 1:
        s += "B"
    if n & 2:
        s += "I"
    if n & 4:
        s += "U"
    return s


def frx_height_to_pt(v, dpi):
    """Font.Height FastReport (pixels negativos) -> tamanho em pontos."""
    try:
        h = float(v)
    except (TypeError, ValueError):
        return 10
    if h < 0:
        h = -h
    return max(1, int(round(h * 72.0 / dpi)))


def frx_halign(v):
    return {
        "haLeft": "left", "haCenter": "center",
        "haRight": "right", "haBlock": "justify",
    }.get(v, "left")


def frx_valign(v):
    return {"vaTop": "top", "vaCenter": "center", "vaBottom": "bottom"}.get(v, "top")


# ilhas de campo FastReport -> ReportsHowie:  [Dataset."campo"] / [Dataset.campo] -> [campo]
_ISLAND = re.compile(r'\[\s*(?:[A-Za-z_]\w*\s*\.\s*)?"?([A-Za-z_]\w*)"?\s*\]')


def map_expressions(text):
    if not text:
        return ""
    return _ISLAND.sub(lambda m: "[%s]" % m.group(1), text)


def get_memo_text(el):
    """Texto de um TfrxMemoView: filho <Memo.UTF8>/<Memo> (linhas) ou attr Text."""
    for child in el:
        tag = child.tag.split("}")[-1]
        if tag in ("Memo.UTF8", "Memo"):
            # o conteudo costuma vir com quebras de linha; normaliza
            raw = (child.text or "").strip("\r\n")
            return raw
    return el.get("Text", "") or ""


def frame(color=0, width=2, sides=""):
    return {"sides": sides, "color": color, "width": width}


def font_from(el, dpi):
    return {
        "name": el.get("Font.Name", "Segoe UI"),
        "size": frx_height_to_pt(el.get("Font.Height", "-13"), dpi),
        "color": frx_color_to_rh(el.get("Font.Color", str(FONTCOLOR_DEFAULT))),
        "style": frx_style_to_str(el.get("Font.Style", "0")),
    }


def rect_of(el, dpi):
    return dict(
        left=px_to_units(el.get("Left", "0"), dpi),
        top=px_to_units(el.get("Top", "0"), dpi),
        width=px_to_units(el.get("Width", "0"), dpi),
        height=px_to_units(el.get("Height", "0"), dpi),
    )


def convert_object(el, dpi, warnings):
    """Um objeto FastReport dentro de uma banda -> objeto .rhr (ou None)."""
    tag = el.tag.split("}")[-1]
    r = rect_of(el, dpi)
    base = dict(name=el.get("Name", ""), visible=True, frame=frame(), **r)

    if tag == "TfrxMemoView":
        base.update(
            type="text",
            text=map_expressions(get_memo_text(el)),
            dataField="",
            font=font_from(el, dpi),
            hAlign=frx_halign(el.get("HAlign", "haLeft")),
            vAlign=frx_valign(el.get("VAlign", "vaTop")),
            wordWrap=el.get("WordWrap", "True") != "False",
            color=frx_color_to_rh(el.get("Color", "16777215")),
            transparent=el.get("Color", "clNone") in ("clNone", "", None) or
                        el.get("Fill.BackColor", "clNone") == "clNone",
        )
        return base

    if tag == "TfrxLineView":
        base.update(
            type="line",
            penColor=frx_color_to_rh(el.get("Frame.Color", "0")),
            penWidth=max(1, int(round(float(el.get("Frame.Width", "1")) * 2))),
        )
        base["height"] = 0  # linha horizontal
        return base

    if tag == "TfrxShapeView":
        shp = el.get("Shape", "skRectangle")
        if shp in ("skEllipse", "skCircle"):
            kind = "ellipse"
        elif shp == "skRoundRectangle":
            kind = "roundRect"
        else:
            kind = "rectangle"
        # o modelo do ReportsHowie usa type="shape" com discriminador "kind"
        base.update(
            type="shape",
            kind=kind,
            penColor=frx_color_to_rh(el.get("Frame.Color", "0")),
            penWidth=max(1, int(round(float(el.get("Frame.Width", "1")) * 2))),
            brushColor=frx_color_to_rh(el.get("Color", "16777215")),
            transparent=el.get("Color", "clNone") == "clNone",
        )
        return base

    if tag == "TfrxPictureView":
        warnings.append("TfrxPictureView '%s': imagem embutida nao convertida "
                        "(reaponte a origem no ReportsHowie)." % el.get("Name", "?"))
        base.update(type="image", dataField="", stretch=True,
                    keepAspect=True, center=True, picture="")
        return base

    if tag == "TfrxBarCodeView":
        base.update(
            type="barcode",
            symbology="qrcode" if "QR" in el.get("BarType", "") else "code128",
            text=map_expressions(el.get("Expression", "") or el.get("Text", "")),
            barColor=0, moduleWidth=0, showText=True,
            font=font_from(el, dpi),
        )
        return base

    warnings.append("Objeto '%s' (%s) ignorado (sem mapeamento)." %
                    (el.get("Name", "?"), tag))
    return None


def convert(frx_path, dpi, verbose):
    tree = ET.parse(frx_path)
    root = tree.getroot()  # TfrxReport
    warnings = []

    # localiza a(s) pagina(s) de relatorio
    pages_out = []
    for page_el in root.iter():
        if page_el.tag.split("}")[-1] != "TfrxReportPage":
            continue
        orient = page_el.get("Orientation", "poPortrait")
        pw = float(page_el.get("PaperWidth", "210"))
        ph = float(page_el.get("PaperHeight", "297"))
        page = dict(
            name=page_el.get("Name", ""),
            paperWidth=mm_to_units(pw),
            paperHeight=mm_to_units(ph),
            orientation="landscape" if orient == "poLandscape" else "portrait",
            marginLeft=mm_to_units(page_el.get("LeftMargin", "10")),
            marginTop=mm_to_units(page_el.get("TopMargin", "10")),
            marginRight=mm_to_units(page_el.get("RightMargin", "10")),
            marginBottom=mm_to_units(page_el.get("BottomMargin", "10")),
            bands=[],
        )
        for band_el in list(page_el):
            btag = band_el.tag.split("}")[-1]
            if btag not in BAND_MAP:
                continue
            band = dict(
                bandType=BAND_MAP[btag],
                name=band_el.get("Name", ""),
                height=px_to_units(band_el.get("Height", "0"), dpi),
                visible=True, canGrow=False, canShrink=False, printIfEmpty=False,
                dataSetName=band_el.get("DataSet", "") or "",
                groupExpression=map_expressions(band_el.get("Condition", "")),
                objects=[],
            )
            for obj_el in list(band_el):
                otag = obj_el.tag.split("}")[-1]
                if not otag.startswith("Tfrx"):
                    continue
                obj = convert_object(obj_el, dpi, warnings)
                if obj:
                    band["objects"].append(obj)
            page["bands"].append(band)
        pages_out.append(page)

    report = dict(
        formatVersion=1,
        generator="frx2rhr (FastReport->ReportsHowie)",
        title=root.get("ReportOptions.Name", "") or "",
        author=root.get("ReportOptions.Author", "") or "",
        pages=pages_out,
    )
    return report, warnings


def main():
    ap = argparse.ArgumentParser(description="Converte FastReport .frx -> ReportsHowie .rhr")
    ap.add_argument("input", help="arquivo .frx de entrada")
    ap.add_argument("output", help="arquivo .rhr de saida")
    ap.add_argument("--dpi", type=int, default=96,
                    help="DPI de design do FastReport (padrao 96)")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    report, warnings = convert(args.input, args.dpi, args.verbose)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    npages = len(report["pages"])
    nbands = sum(len(p["bands"]) for p in report["pages"])
    nobjs = sum(len(b["objects"]) for p in report["pages"] for b in p["bands"])
    print("OK: %s -> %s (%d pagina(s), %d banda(s), %d objeto(s))"
          % (args.input, args.output, npages, nbands, nobjs))
    if warnings:
        print("Avisos (%d):" % len(warnings))
        for w in warnings:
            print("  - " + w)


if __name__ == "__main__":
    main()
