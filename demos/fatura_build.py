#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Demo generico FATURA / DUPLICATA MERCANTIL (comercial), com itens, totais,
parcelas (duplicatas) e um bloco tipo boleto (linha digitavel + codigo de
barras). demos/fatura.rhr + demos/fatura.data.json.

Master 'Fatura' (1 registro: emitente/sacado/totais) + detalhes 'Itens' e
'Parcelas'. Reusa as primitivas de fiscal_common.

Uso:  python fatura_build.py
"""
from fiscal_common import (mm, txt, cell, box, fill, vline, hline, barcode,
                           band, page, save)

PW, PH, MARGIN = mm(210), mm(297), mm(10)
X0 = 0
W = PW - 2 * MARGIN
X1 = W
ROW = mm(8)


def sect(o, y, text):
    fill(o, X0, y, W, mm(4.5))
    txt(o, X0 + mm(1), y + mm(0.8), W, mm(3), text, size=7, style="B")
    return y + mm(4.5)


def item_columns():
    return [
        ("COD", mm(16), "codigo", "left"),
        ("DESCRICAO DO PRODUTO / SERVICO", W - mm(16 + 18 + 26 + 30), "descricao", "left"),
        ("QTD", mm(18), "qtd", "right"),
        ("VL. UNIT", mm(26), "valor_unit", "right"),
        ("VL. TOTAL", mm(30), "valor_total", "right"),
    ]


def head_band():
    o, y = [], 0
    # cabecalho: emitente | numero da fatura
    HH = mm(20)
    box(o, X0, y, W, HH)
    vline(o, X0 + int(W * 0.68), y, HH)
    txt(o, X0 + mm(2), y + mm(2), int(W * 0.68) - mm(4), mm(5), "[emit_nome]",
        size=11, style="B")
    txt(o, X0 + mm(2), y + mm(8), int(W * 0.68) - mm(4), mm(4),
        "CNPJ [MASK(emit_cnpj,'##.###.###/####-##')]  IE [emit_ie]", size=7)
    txt(o, X0 + mm(2), y + mm(12), int(W * 0.68) - mm(4), mm(4),
        "[emit_end] - [emit_mun]/[emit_uf]", size=7, wrap=True)
    rx = X0 + int(W * 0.68)
    txt(o, rx + mm(2), y + mm(2), W - int(W * 0.68) - mm(4), mm(4), "FATURA / DUPLICATA No.",
        size=7, style="B", align="center")
    txt(o, rx + mm(2), y + mm(6), W - int(W * 0.68) - mm(4), mm(5), "[numero]",
        size=13, style="B", align="center")
    txt(o, rx + mm(2), y + mm(13), W - int(W * 0.68) - mm(4), mm(4), "Emissao: [dt_emissao]",
        size=7, align="center")
    y += HH + mm(2)

    # sacado / cliente
    y = sect(o, y, "SACADO / CLIENTE")
    cell(o, X0, y, int(W * 0.68), ROW, "NOME / RAZAO SOCIAL", "[sacado_nome]", vsize=7,
         valign_val="left")
    cell(o, X0 + int(W * 0.68), y, W - int(W * 0.68), ROW, "CNPJ / CPF",
         "[MASK(sacado_cnpj,'##.###.###/####-##')]", vsize=7, valign_val="left"); y += ROW
    cell(o, X0, y, int(W * 0.68), ROW, "ENDERECO", "[sacado_end]", vsize=7, valign_val="left")
    cell(o, X0 + int(W * 0.68), y, W - int(W * 0.68), ROW, "MUNICIPIO/UF",
         "[sacado_mun]/[sacado_uf]", vsize=7, valign_val="left"); y += ROW + mm(2)

    # cabecalho da tabela de itens
    y = sect(o, y, "PRODUTOS / SERVICOS")
    HHc = mm(5)
    box(o, X0, y, W, HHc)
    x = X0
    for (label, cw, _f, _al) in item_columns():
        txt(o, x + mm(1), y + mm(1), cw - mm(2), mm(3), label, size=6, style="B", align="center")
        if x > X0:
            vline(o, x, y, HHc)
        x += cw
    y += HHc
    return o, y


def item_band():
    o = []
    RH = mm(5)
    x = X0
    for i, (_l, cw, fld, al) in enumerate(item_columns()):
        if fld in ("valor_unit", "valor_total"):
            val = "[FORMATFLOAT('#,##0.00', %s)]" % fld
        elif fld == "qtd":
            val = "[FORMATFLOAT('#,##0.###', qtd)]"
        else:
            val = "[%s]" % fld
        txt(o, x + mm(1), mm(0.6), cw - mm(2), mm(3.5), val, size=7, align=al)
        if i > 0:
            vline(o, x, 0, RH)
        x += cw
    hline(o, X0, RH - mm(0.2), W)
    vline(o, X0, 0, RH); vline(o, X1, 0, RH)
    return o, RH


def parcela_band():
    o = []
    RH = mm(5)
    txt(o, X0 + mm(2), mm(0.6), mm(40), mm(3.5), "Parcela [parcela] - venc. [vencimento]", size=7)
    txt(o, X1 - mm(40), mm(0.6), mm(38), mm(3.5), "[FORMATFLOAT('#,##0.00', valor)]",
        size=7, align="right")
    return o, RH


def totals_band():
    o, y = [], 0
    # totais (direita)
    tw = int(W * 0.42)
    tx = X1 - tw
    box(o, tx, y, tw, mm(20))
    rows = [("SUBTOTAL", "subtotal", False), ("DESCONTO", "desconto", False),
            ("IMPOSTOS", "impostos", False), ("TOTAL A PAGAR", "total", True)]
    ry = y
    for (lbl, fld, bold) in rows:
        sz = 9 if bold else 7
        st = "B" if bold else ""
        txt(o, tx + mm(2), ry + mm(1), tw - mm(40), mm(4), lbl, size=sz, style=st)
        txt(o, tx + tw - mm(38), ry + mm(1), mm(36), mm(4),
            "[FORMATFLOAT('#,##0.00', %s)]" % fld, size=sz, style=st, align="right")
        ry += mm(5)
    # parcelas titulo (esquerda)
    txt(o, X0, y + mm(1), int(W * 0.5), mm(4), "DUPLICATAS / PARCELAS:", size=7, style="B")
    y += mm(22)

    # bloco boleto
    y = sect(o, y, "RECIBO DO SACADO - BANCO EXEMPLO S/A  |  237-2")
    box(o, X0, y, W, mm(24))
    txt(o, X0 + mm(2), y + mm(1.5), W - mm(4), mm(4), "Linha digitavel:  [linha_digitavel]",
        size=7, style="B")
    txt(o, X0 + mm(2), y + mm(6), int(W * 0.5), mm(4), "Beneficiario: [emit_nome]", size=7)
    txt(o, X0 + mm(2), y + mm(10), int(W * 0.5), mm(4), "Pagador: [sacado_nome]", size=7)
    txt(o, X1 - mm(60), y + mm(6), mm(58), mm(4), "Vencimento: [vencimento_final]", size=7,
        align="right")
    txt(o, X1 - mm(60), y + mm(10), mm(58), mm(5), "Valor: R$ [FORMATFLOAT('#,##0.00', total)]",
        size=9, style="B", align="right")
    barcode(o, X0 + mm(2), y + mm(16), int(W * 0.6), mm(7), "[codigo_barras]")
    y += mm(26)
    return o, y


def main():
    hb, hh = head_band()
    ib, ih = item_band()
    pb, ph = parcela_band()
    tb, th = totals_band()
    report = {
        "formatVersion": 1, "generator": "fatura_build.py",
        "title": "Fatura / Duplicata Mercantil (demo)", "author": "ReportsHowie",
        "pages": [page("Fatura", PW, PH, MARGIN, [
            band("masterData", "Fatura", hh, hb, dataset="Fatura"),
            band("detailData", "Itens", ih, ib, dataset="Itens"),
            band("detailData", "Parcelas", ph, pb, dataset="Parcelas"),
            band("summary", "Totais", th, tb),
        ])],
    }
    data = {
        "Fatura": [{
            "emit_nome": "DISTRIBUIDORA EXEMPLO LTDA", "emit_cnpj": "12345678000199",
            "emit_ie": "082345678", "emit_end": "AV. DO COMERCIO, 900 - CENTRO",
            "emit_mun": "VITORIA", "emit_uf": "ES",
            "numero": "FAT-2026/00875", "dt_emissao": "03/07/2026",
            "sacado_nome": "SUPERMERCADO CLIENTE LTDA", "sacado_cnpj": "98765432000155",
            "sacado_end": "RUA DAS COMPRAS, 120 - CENTRO", "sacado_mun": "VILA VELHA",
            "sacado_uf": "ES",
            "subtotal": 4850.00, "desconto": 150.00, "impostos": 0.00, "total": 4700.00,
            "linha_digitavel": "23793.38128 60000.000000 00000.000000 1 99999000470000",
            "vencimento_final": "10/08/2026", "codigo_barras": "23791999900004700003381286000000000000000000",
        }],
        "Itens": [
            {"codigo": "A100", "descricao": "ARROZ TIPO 1 - FARDO 30KG", "qtd": 20.0,
             "valor_unit": 95.00, "valor_total": 1900.00},
            {"codigo": "B220", "descricao": "FEIJAO CARIOCA - FARDO 30KG", "qtd": 15.0,
             "valor_unit": 120.00, "valor_total": 1800.00},
            {"codigo": "C330", "descricao": "OLEO DE SOJA - CAIXA 20UN", "qtd": 10.0,
             "valor_unit": 115.00, "valor_total": 1150.00},
        ],
        "Parcelas": [
            {"parcela": "1/3", "vencimento": "10/08/2026", "valor": 1566.67},
            {"parcela": "2/3", "vencimento": "10/09/2026", "valor": 1566.67},
            {"parcela": "3/3", "vencimento": "10/10/2026", "valor": 1566.66},
        ],
    }
    save(report, data, "fatura")


if __name__ == "__main__":
    main()
