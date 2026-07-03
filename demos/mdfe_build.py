#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gera o demo DAMDFE (Documento Auxiliar do Manifesto Eletronico de Documentos
Fiscais, MDF-e modelo 58): demos/mdfe.rhr + demos/mdfe.data.json  (A4, rodoviario).

Uso:  python mdfe_build.py
"""
from fiscal_common import (mm, txt, cell, box, fill, vline, hline, barcode,
                           qrcode, band, page, save)

PW, PH, MARGIN = mm(210), mm(297), mm(4)
X0, X1 = MARGIN, PW - MARGIN
W = X1 - X0
ROW = mm(9)
CHAVE_MASK = "#### #### #### #### #### #### #### #### #### #### ####"


def sect(o, y, text):
    fill(o, X0, y, W, mm(4))
    txt(o, X0 + mm(1), y + mm(0.6), W, mm(3), text, size=6, style="B")
    return y + mm(4)


def mdfe_band():
    o, y = [], 0

    # ---- emitente | DAMDFE | QR ----
    HH = mm(26)
    box(o, X0, y, W, HH)
    ca, cb = mm(78), mm(70)
    xa, xb, xc = X0, X0 + ca, X0 + ca + cb
    vline(o, xb, y, HH); vline(o, xc, y, HH)
    txt(o, xa + mm(2), y + mm(2), ca - mm(4), mm(4), "[emit_nome]", size=8, style="B", align="center")
    txt(o, xa + mm(2), y + mm(8), ca - mm(4), mm(4), "[emit_end]", size=6, align="center", wrap=True)
    txt(o, xa + mm(2), y + mm(13), ca - mm(4), mm(4), "[emit_mun]/[emit_uf]", size=6, align="center")
    txt(o, xa + mm(2), y + mm(17), ca - mm(4), mm(4),
        "CNPJ [MASK(emit_cnpj,'##.###.###/####-##')]  IE [emit_ie]", size=6, align="center")
    # DAMDFE
    txt(o, xb + mm(1), y + mm(2), cb - mm(2), mm(4), "DAMDFE", size=10, style="B", align="center")
    txt(o, xb + mm(1), y + mm(7), cb - mm(2), mm(6),
        "Documento Auxiliar do Manifesto Eletronico de Documentos Fiscais",
        size=5, align="center", wrap=True)
    txt(o, xb + mm(1), y + mm(14), cb - mm(2), mm(3), "MODELO  SERIE  NUMERO", size=5, align="center")
    txt(o, xb + mm(1), y + mm(17), cb - mm(2), mm(4), "58   [serie]   [numero]",
        size=7, style="B", align="center")
    txt(o, xb + mm(1), y + mm(22), cb - mm(2), mm(3), "MODAL RODOVIARIO   FL 1/1", size=5, align="center")
    # QR
    qr = mm(22)
    qrcode(o, xc + (W - ca - cb - qr) // 2, y + mm(2), qr, "[qr_conteudo]")
    y += HH

    # ---- barcode + chave ----
    HB = mm(15)
    box(o, X0, y, W, HB)
    barcode(o, X0 + mm(3), y + mm(2), int(W * 0.62), mm(8), "[chave]")
    txt(o, X0 + mm(3), y + mm(10), int(W * 0.62), mm(3),
        "CHAVE [MASK(chave,'%s')]" % CHAVE_MASK, size=5)
    vline(o, X0 + int(W * 0.66), y, HB)
    txt(o, X0 + int(W * 0.66) + mm(2), y + mm(1.5), W - int(W * 0.66) - mm(4), mm(3),
        "PROTOCOLO DE AUTORIZACAO", size=5)
    txt(o, X0 + int(W * 0.66) + mm(2), y + mm(5), W - int(W * 0.66) - mm(4), mm(4),
        "[protocolo]", size=6, wrap=True)
    y += HB + mm(1)

    # ---- UFs / quantidades / peso / valor ----
    cols = [("UF CARREG.", "uf_ini"), ("UF DESCARREG.", "uf_fim"),
            ("QTD. CT-e", "qtd_cte"), ("QTD. NF-e", "qtd_nfe"),
            ("PESO TOTAL (KG)", "peso"), ("VALOR TOTAL R$", "valor")]
    cw = W // len(cols)
    for i, (lbl, fld) in enumerate(cols):
        x = X0 + i * cw
        wx = (W - (len(cols) - 1) * cw) if i == len(cols) - 1 else cw
        if fld == "valor":
            v = "[FORMATFLOAT('#,##0.00', %s)]" % fld
            cell(o, x, y, wx, ROW, lbl, v, vsize=7, vstyle="B")
        else:
            cell(o, x, y, wx, ROW, lbl, "[%s]" % fld, vsize=6, valign_val="center")
    y += ROW + mm(1)

    # ---- municipios de carregamento | percurso ----
    half = W // 2
    cell(o, X0, y, half, ROW, "MUNICIPIOS DE CARREGAMENTO", "[mun_carreg]", vsize=6, valign_val="left")
    cell(o, X0 + half, y, W - half, ROW, "PERCURSO (UFs)", "[percurso]", vsize=6, valign_val="left")
    y += ROW + mm(1)

    # ---- modal rodoviario: veiculo | condutor ----
    y = sect(o, y, "RODOVIARIO - VEICULOS E CONDUTORES")
    cell(o, X0, y, int(W * 0.25), ROW, "PLACA", "[placa]", vsize=7, valign_val="center")
    cell(o, X0 + int(W * 0.25), y, int(W * 0.25), ROW, "RENAVAM", "[renavam]", vsize=6, valign_val="center")
    cell(o, X0 + int(W * 0.50), y, int(W * 0.25), ROW, "CONDUTOR", "[condutor]", vsize=6, valign_val="left")
    cell(o, X0 + int(W * 0.75), y, W - int(W * 0.75), ROW, "CPF CONDUTOR",
         "[MASK(cpf_condutor,'###.###.###-##')]", vsize=6, valign_val="left")
    y += ROW + mm(1)

    # ---- titulo docs fiscais (linhas na banda de detalhe) ----
    y = sect(o, y, "INFORMACOES DOS DOCUMENTOS FISCAIS VINCULADOS (POR MUNICIPIO DE DESCARGA)")
    HHc = mm(5)
    box(o, X0, y, W, HHc)
    dc = doc_columns()
    x = X0
    for (label, cwid, _f, _al) in dc:
        txt(o, x + mm(1), y + mm(1), cwid - mm(2), mm(3), label, size=5, style="B", align="center")
        if x > X0:
            vline(o, x, y, HHc)
        x += cwid
    y += HHc
    return o, y


def doc_columns():
    return [
        ("MUNICIPIO DESCARGA", mm(50), "municipio", "left"),
        ("DOCUMENTO", mm(24), "tipo", "center"),
        ("CHAVE DE ACESSO DA NF-e", W - mm(50 + 24), "chave", "left"),
    ]


def doc_band():
    o = []
    RH = mm(5)
    dc = doc_columns()
    x = X0
    for i, (_l, cwid, fld, al) in enumerate(dc):
        if fld == "chave":
            val = "[MASK(chave,'%s')]" % CHAVE_MASK
            sz = 5
        else:
            val = "[%s]" % fld
            sz = 6
        txt(o, x + mm(1), mm(0.6), cwid - mm(2), mm(3.5), val, size=sz, align=al)
        if i > 0:
            vline(o, x, 0, RH)
        x += cwid
    hline(o, X0, RH - mm(0.2), W)
    vline(o, X0, 0, RH); vline(o, X1, 0, RH)
    return o, RH


def obs_band():
    o = []
    fill(o, X0, mm(1), W, mm(4))
    txt(o, X0 + mm(1), mm(1.6), W, mm(3), "OBSERVACOES", size=6, style="B")
    box(o, X0, mm(5), W, mm(16))
    txt(o, X0 + mm(2), mm(6), W - mm(4), mm(14), "[observacoes]", size=6, wrap=True)
    return o, mm(23)


def main():
    mb, mh = mdfe_band()
    db, dh = doc_band()
    ob, oh = obs_band()
    report = {
        "formatVersion": 1, "generator": "mdfe_build.py",
        "title": "DAMDFE - Manifesto Eletronico de Documentos Fiscais (demo)", "author": "ReportsHowie",
        "pages": [page("DAMDFE", PW, PH, MARGIN, [
            band("masterData", "MDFe", mh, mb, dataset="MDFe"),
            band("detailData", "Docs", dh, db, dataset="Docs"),
            band("summary", "Obs", oh, ob),
        ])],
    }
    data = {
        "MDFe": [{
            "emit_nome": "TRANSPORTADORA EXEMPLO LTDA", "emit_end": "ROD. BR-101, KM 300",
            "emit_mun": "SERRA", "emit_uf": "ES", "emit_cnpj": "11222333000181",
            "emit_ie": "081234567", "serie": "1", "numero": "0000789",
            "chave": "35240711222333000181580010000007891123456780",
            "qr_conteudo": "https://dfe-portal.svrs.rs.gov.br/mdfe/qrCode?chMDFe=35240711222333000181580010000007891123456780&tpAmb=1",
            "protocolo": "135240000778899 - 03/07/2026 08:40",
            "uf_ini": "ES", "uf_fim": "SP", "qtd_cte": "0", "qtd_nfe": "3",
            "peso": "1.250,000", "valor": 85000.00,
            "mun_carreg": "SERRA/ES", "percurso": "ES / RJ / SP",
            "placa": "ABC-1D23", "renavam": "00123456789", "condutor": "CARLOS MOTORISTA",
            "cpf_condutor": "12345678900",
            "observacoes": "Manifesto referente a carga fracionada com destino a Sao Paulo/SP. "
                           "Veiculo proprio. Sem contratacao de vale-pedagio.",
        }],
        "Docs": [
            {"municipio": "SAO PAULO/SP", "tipo": "NF-e",
             "chave": "35240712345678000199550010001234561123456780"},
            {"municipio": "SAO PAULO/SP", "tipo": "NF-e",
             "chave": "35240712345678000199550010001234571123456791"},
            {"municipio": "CAMPINAS/SP", "tipo": "NF-e",
             "chave": "35240712345678000199550010001234601123456805"},
        ],
    }
    save(report, data, "mdfe")


if __name__ == "__main__":
    main()
