#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gera o demo DACTE (Documento Auxiliar do Conhecimento de Transporte Eletronico,
CT-e modelo 57): demos/dacte.rhr + demos/dacte.data.json  (A4, modal rodoviario).

Uso:  python dacte_build.py
"""
from fiscal_common import (mm, txt, cell, box, fill, vline, hline, barcode,
                           band, page, save)

PW, PH, MARGIN = mm(210), mm(297), mm(4)
# coordenadas relativas a area de conteudo (o motor ja aplica a margem)
X0 = 0
W = PW - 2 * MARGIN
X1 = W
ROW = mm(9)
CHAVE_MASK = "#### #### #### #### #### #### #### #### #### #### ####"


def sect(o, y, text):
    fill(o, X0, y, W, mm(4))
    txt(o, X0 + mm(1), y + mm(0.6), W, mm(3), text, size=6, style="B")
    return y + mm(4)


def cte_band():
    o, y = [], 0

    # ---- emitente | DACTE | chave ----
    HH = mm(34)
    box(o, X0, y, W, HH)
    ca, cb = mm(74), mm(52)
    xa, xb, xc = X0, X0 + ca, X0 + ca + cb
    vline(o, xb, y, HH); vline(o, xc, y, HH)
    # emitente (transportadora)
    txt(o, xa + mm(2), y + mm(2), ca - mm(4), mm(4), "[emit_nome]", size=8, style="B", align="center")
    txt(o, xa + mm(2), y + mm(9), ca - mm(4), mm(4), "[emit_end]", size=6, align="center", wrap=True)
    txt(o, xa + mm(2), y + mm(14), ca - mm(4), mm(4), "[emit_mun]/[emit_uf]", size=6, align="center")
    txt(o, xa + mm(2), y + mm(19), ca - mm(4), mm(4),
        "CNPJ [MASK(emit_cnpj,'##.###.###/####-##')]", size=6, align="center")
    txt(o, xa + mm(2), y + mm(24), ca - mm(4), mm(4), "IE [emit_ie]  Fone [emit_fone]",
        size=6, align="center")
    # DACTE
    txt(o, xb + mm(1), y + mm(2), cb - mm(2), mm(4), "DACTE", size=11, style="B", align="center")
    txt(o, xb + mm(1), y + mm(8), cb - mm(2), mm(6),
        "Documento Auxiliar do Conhecimento de Transporte Eletronico",
        size=5, align="center", wrap=True)
    txt(o, xb + mm(1), y + mm(15), cb - mm(2), mm(3), "MODAL RODOVIARIO", size=6, style="B", align="center")
    txt(o, xb + mm(1), y + mm(19), cb - mm(2), mm(3), "MODELO  SERIE  NUMERO", size=5, align="center")
    txt(o, xb + mm(1), y + mm(22), cb - mm(2), mm(4), "57   [serie]   [numero]",
        size=7, style="B", align="center")
    txt(o, xb + mm(1), y + mm(27), cb - mm(2), mm(3), "FOLHA 1/1", size=5, align="center")
    txt(o, xb + mm(1), y + mm(30), cb - mm(2), mm(3), "TIPO CTe: 0-NORMAL", size=5, align="center")
    # barcode + chave
    wc = W - ca - cb
    barcode(o, xc + mm(3), y + mm(2), wc - mm(6), mm(11), "[chave]")
    txt(o, xc + mm(2), y + mm(14), wc - mm(4), mm(3), "CHAVE DE ACESSO", size=5)
    txt(o, xc + mm(2), y + mm(17), wc - mm(4), mm(4), "[MASK(chave,'%s')]" % CHAVE_MASK,
        size=5, style="B", align="center")
    txt(o, xc + mm(2), y + mm(23), wc - mm(4), mm(8),
        "Consulte em www.cte.fazenda.gov.br/portal ou site da Sefaz autorizadora",
        size=5, align="center", wrap=True)
    y += HH

    # ---- natureza | protocolo ----
    nw = int(W * 0.55)
    cell(o, X0, y, nw, ROW, "NATUREZA DA PRESTACAO", "[natureza]", vsize=6, valign_val="left")
    cell(o, X0 + nw, y, W - nw, ROW, "PROTOCOLO DE AUTORIZACAO DE USO", "[protocolo]",
         vsize=6, valign_val="left")
    y += ROW
    # ---- CFOP | tipo servico | tomador ----
    w3 = W // 3
    cell(o, X0, y, w3, ROW, "CFOP - NATUREZA", "[cfop]", vsize=6, valign_val="left")
    cell(o, X0 + w3, y, w3, ROW, "TIPO DO SERVICO", "0 - NORMAL", vsize=6, valign_val="left")
    cell(o, X0 + 2 * w3, y, W - 2 * w3, ROW, "TOMADOR DO SERVICO", "[tomador]", vsize=6, valign_val="left")
    y += ROW
    # ---- inicio | termino da prestacao ----
    half = W // 2
    cell(o, X0, y, half, ROW, "INICIO DA PRESTACAO", "[ini_mun]/[ini_uf]", vsize=6, valign_val="left")
    cell(o, X0 + half, y, W - half, ROW, "TERMINO DA PRESTACAO", "[fim_mun]/[fim_uf]",
         vsize=6, valign_val="left")
    y += ROW + mm(1)

    # ---- remetente | destinatario ----
    y = sect(o, y, "REMETENTE / DESTINATARIO")
    for (lbl, pre) in (("REMETENTE", "rem"), ("DESTINATARIO", "dest")):
        xh = X0 if lbl == "REMETENTE" else X0 + half
        wh = half if lbl == "REMETENTE" else W - half
        yy = y
        cell(o, xh, yy, wh, mm(8), lbl, "[%s_nome]" % pre, vsize=6, valign_val="left"); yy += mm(8)
        cell(o, xh, yy, wh, mm(8), "ENDERECO", "[%s_end]" % pre, vsize=6, valign_val="left"); yy += mm(8)
        cell(o, xh, yy, int(wh * 0.6), mm(8), "MUNICIPIO", "[%s_mun]/[%s_uf]" % (pre, pre),
             vsize=6, valign_val="left")
        cell(o, xh + int(wh * 0.6), yy, wh - int(wh * 0.6), mm(8), "CNPJ/CPF",
             "[MASK(%s_cnpj,'##.###.###/####-##')]" % pre, vsize=6, valign_val="left")
    y += mm(24) + mm(1)

    # ---- carga ----
    y = sect(o, y, "DADOS DA CARGA")
    cell(o, X0, y, int(W * 0.4), ROW, "PRODUTO PREDOMINANTE", "[produto]", vsize=6, valign_val="left")
    cell(o, X0 + int(W * 0.4), y, int(W * 0.3), ROW, "PESO BRUTO (KG)", "[peso]", vsize=6)
    cell(o, X0 + int(W * 0.7), y, W - int(W * 0.7), ROW, "VALOR TOTAL DA CARGA",
         "[FORMATFLOAT('#,##0.00', valor_carga)]", vsize=7, vstyle="B")
    y += ROW + mm(1)

    # ---- componentes do valor da prestacao | impostos ----
    y = sect(o, y, "COMPONENTES DO VALOR DA PRESTACAO DO SERVICO")
    lw = int(W * 0.62)
    # 3 componentes (nome | valor)
    comp = [("FRETE VALOR", "comp_frete"), ("PEDAGIO", "comp_pedagio"), ("OUTROS", "comp_outros")]
    cw = lw // 3
    for i, (nm, fld) in enumerate(comp):
        x = X0 + i * cw
        cell(o, x, y, cw, ROW, nm, "[FORMATFLOAT('#,##0.00', %s)]" % fld, vsize=6)
    cell(o, X0 + lw, y, W - lw, ROW, "VALOR TOTAL DA PRESTACAO DO SERVICO",
         "[FORMATFLOAT('#,##0.00', valor_total)]", vsize=8, vstyle="B")
    y += ROW + mm(1)

    y = sect(o, y, "INFORMACOES RELATIVAS AO IMPOSTO")
    w5 = W // 5
    cell(o, X0, y, w5, ROW, "SITUACAO TRIBUTARIA", "00 - Tributacao normal", vsize=5, valign_val="left")
    cell(o, X0 + w5, y, w5, ROW, "BASE DE CALCULO", "[FORMATFLOAT('#,##0.00', base_icms)]", vsize=6)
    cell(o, X0 + 2 * w5, y, w5, ROW, "ALIQ ICMS %", "[FORMATFLOAT('#,##0.00', aliq_icms)]", vsize=6)
    cell(o, X0 + 3 * w5, y, w5, ROW, "VALOR ICMS", "[FORMATFLOAT('#,##0.00', valor_icms)]", vsize=6)
    cell(o, X0 + 4 * w5, y, W - 4 * w5, ROW, "% RED. BC", "0,00", vsize=6)
    y += ROW + mm(1)

    # ---- titulo dos documentos originarios (linhas na banda de detalhe) ----
    y = sect(o, y, "DOCUMENTOS ORIGINARIOS")
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
        ("TIPO DOC", mm(30), "tipo", "left"),
        ("CNPJ/CPF DO EMITENTE", mm(60), "emit", "left"),
        ("SERIE", mm(25), "serie", "center"),
        ("NUMERO DOCUMENTO", W - mm(30 + 60 + 25), "numero", "left"),
    ]


def doc_band():
    o = []
    RH = mm(5)
    dc = doc_columns()
    x = X0
    for i, (_l, cwid, fld, al) in enumerate(dc):
        if fld == "emit":
            val = "[MASK(emit,'##.###.###/####-##')]"
        else:
            val = "[%s]" % fld
        txt(o, x + mm(1), mm(0.6), cwid - mm(2), mm(3.5), val, size=6, align=al)
        if i > 0:
            vline(o, x, 0, RH)
        x += cwid
    hline(o, X0, RH - mm(0.2), W)
    vline(o, X0, 0, RH); vline(o, X1, 0, RH)
    return o, RH


def obs_band():
    o = []
    fill(o, X0, mm(1), W, mm(4))
    txt(o, X0 + mm(1), mm(1.6), W, mm(3), "OBSERVACOES / DADOS DO MODAL RODOVIARIO", size=6, style="B")
    box(o, X0, mm(5), W, mm(20))
    txt(o, X0 + mm(2), mm(6), W - mm(4), mm(4), "RNTRC: [rntrc]    LOTACAO: NAO", size=6)
    txt(o, X0 + mm(2), mm(10), W - mm(4), mm(14), "[observacoes]", size=6, wrap=True)
    return o, mm(27)


def main():
    cb, ch = cte_band()
    db, dh = doc_band()
    ob, oh = obs_band()
    report = {
        "formatVersion": 1, "generator": "dacte_build.py",
        "title": "DACTE - Conhecimento de Transporte Eletronico (demo)", "author": "ReportsHowie",
        "pages": [page("DACTE", PW, PH, MARGIN, [
            band("masterData", "CTe", ch, cb, dataset="CTe"),
            band("detailData", "Docs", dh, db, dataset="Docs"),
            band("summary", "Obs", oh, ob),
        ])],
    }
    data = {
        "CTe": [{
            "emit_nome": "TRANSPORTADORA EXEMPLO LTDA", "emit_end": "ROD. BR-101, KM 300",
            "emit_mun": "SERRA", "emit_uf": "ES", "emit_cnpj": "11222333000181",
            "emit_ie": "081234567", "emit_fone": "(27) 3355-6677",
            "serie": "1", "numero": "0004521",
            "chave": "35240711222333000181570010000045211987654321",
            "natureza": "TRANSPORTE DE CARGA FRACIONADA",
            "protocolo": "135240000456789 - 03/07/2026 09:15",
            "cfop": "6353 - PREST.SERVICO TRANSPORTE", "tomador": "REMETENTE",
            "ini_mun": "SERRA", "ini_uf": "ES", "fim_mun": "SAO PAULO", "fim_uf": "SP",
            "rem_nome": "INDUSTRIA REMETENTE S/A", "rem_end": "AV. DAS FABRICAS, 1000 - SERRA/ES",
            "rem_mun": "SERRA", "rem_uf": "ES", "rem_cnpj": "12345678000199",
            "dest_nome": "DISTRIBUIDORA DESTINO LTDA", "dest_end": "RUA DO ATACADO, 500 - SAO PAULO/SP",
            "dest_mun": "SAO PAULO", "dest_uf": "SP", "dest_cnpj": "98765432000155",
            "produto": "AUTOPECAS", "peso": "1.250,000", "valor_carga": 85000.00,
            "comp_frete": 2800.00, "comp_pedagio": 320.00, "comp_outros": 80.00,
            "valor_total": 3200.00,
            "base_icms": 3200.00, "aliq_icms": 12.00, "valor_icms": 384.00,
            "rntrc": "12345678",
            "observacoes": "Mercadoria acondicionada em 25 volumes. Entrega em horario comercial. "
                           "CT-e emitido nos termos do ajuste SINIEF. Frete por conta do remetente (CIF).",
        }],
        "Docs": [
            {"tipo": "NF-e", "emit": "12345678000199", "serie": "1", "numero": "000.123.456"},
            {"tipo": "NF-e", "emit": "12345678000199", "serie": "1", "numero": "000.123.457"},
            {"tipo": "NF-e", "emit": "12345678000199", "serie": "1", "numero": "000.123.460"},
        ],
    }
    save(report, data, "dacte")


if __name__ == "__main__":
    main()
