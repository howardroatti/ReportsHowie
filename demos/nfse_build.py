#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gera o demo NFS-e (Nota Fiscal de Servicos Eletronica): demos/nfse.rhr +
demos/nfse.data.json  (A4). Layout generico municipal (prestador/tomador,
discriminacao dos servicos, tributacao do ISS e retencoes federais).

Uso:  python nfse_build.py
"""
from fiscal_common import (mm, txt, cell, box, fill, vline, hline,
                           band, page, save)

PW, PH, MARGIN = mm(210), mm(297), mm(6)
X0, X1 = MARGIN, PW - MARGIN
W = X1 - X0
ROW = mm(9)


def sect(o, y, text):
    fill(o, X0, y, W, mm(4))
    txt(o, X0 + mm(1), y + mm(0.6), W, mm(3), text, size=6, style="B")
    return y + mm(4)


def nfse_band():
    o, y = [], 0

    # ---- cabecalho: prefeitura/NFS-e | numero/emissao/verificacao ----
    HH = mm(24)
    box(o, X0, y, W, HH)
    lw = int(W * 0.62)
    vline(o, X0 + lw, y, HH)
    txt(o, X0 + mm(2), y + mm(3), lw - mm(4), mm(5), "PREFEITURA MUNICIPAL DE [municipio]",
        size=9, style="B", align="center")
    txt(o, X0 + mm(2), y + mm(10), lw - mm(4), mm(5),
        "NOTA FISCAL DE SERVICOS ELETRONICA - NFS-e", size=8, style="B", align="center")
    txt(o, X0 + mm(2), y + mm(16), lw - mm(4), mm(4),
        "Secretaria Municipal de Financas", size=6, align="center")
    # bloco direito
    rx = X0 + lw
    rw = W - lw
    txt(o, rx + mm(2), y + mm(1.5), rw - mm(4), mm(3), "NUMERO DA NFS-e", size=5)
    txt(o, rx + mm(2), y + mm(4), rw - mm(4), mm(5), "[numero]", size=10, style="B", align="right")
    hline(o, rx, y + mm(10), rw)
    txt(o, rx + mm(2), y + mm(10.5), rw - mm(4), mm(3), "DATA/HORA DE EMISSAO", size=5)
    txt(o, rx + mm(2), y + mm(13.5), rw - mm(4), mm(4), "[dt_emissao]", size=6, align="right")
    hline(o, rx, y + mm(17), rw)
    txt(o, rx + mm(2), y + mm(17.5), rw - mm(4), mm(3), "CODIGO DE VERIFICACAO", size=5)
    txt(o, rx + mm(2), y + mm(20), rw - mm(4), mm(3.5), "[cod_verificacao]", size=6, align="right")
    y += HH + mm(1)

    # ---- prestador ----
    y = sect(o, y, "PRESTADOR DE SERVICOS")
    cell(o, X0, y, int(W * 0.7), mm(8), "NOME / RAZAO SOCIAL", "[prest_nome]", vsize=6, valign_val="left")
    cell(o, X0 + int(W * 0.7), y, W - int(W * 0.7), mm(8), "CNPJ",
         "[MASK(prest_cnpj,'##.###.###/####-##')]", vsize=6, valign_val="left"); y += mm(8)
    cell(o, X0, y, int(W * 0.5), mm(8), "ENDERECO", "[prest_end]", vsize=6, valign_val="left")
    cell(o, X0 + int(W * 0.5), y, int(W * 0.3), mm(8), "MUNICIPIO/UF",
         "[prest_mun]/[prest_uf]", vsize=6, valign_val="left")
    cell(o, X0 + int(W * 0.8), y, W - int(W * 0.8), mm(8), "INSC. MUNICIPAL",
         "[prest_im]", vsize=6, valign_val="left"); y += mm(8) + mm(1)

    # ---- tomador ----
    y = sect(o, y, "TOMADOR DE SERVICOS")
    cell(o, X0, y, int(W * 0.7), mm(8), "NOME / RAZAO SOCIAL", "[tom_nome]", vsize=6, valign_val="left")
    cell(o, X0 + int(W * 0.7), y, W - int(W * 0.7), mm(8), "CNPJ / CPF",
         "[MASK(tom_cnpj,'##.###.###/####-##')]", vsize=6, valign_val="left"); y += mm(8)
    cell(o, X0, y, int(W * 0.5), mm(8), "ENDERECO", "[tom_end]", vsize=6, valign_val="left")
    cell(o, X0 + int(W * 0.5), y, int(W * 0.3), mm(8), "MUNICIPIO/UF",
         "[tom_mun]/[tom_uf]", vsize=6, valign_val="left")
    cell(o, X0 + int(W * 0.8), y, W - int(W * 0.8), mm(8), "E-MAIL",
         "[tom_email]", vsize=6, valign_val="left"); y += mm(8) + mm(1)

    # ---- titulo: discriminacao (itens na banda de detalhe) ----
    y = sect(o, y, "DISCRIMINACAO DOS SERVICOS")
    HHc = mm(5)
    box(o, X0, y, W, HHc)
    dc = serv_columns()
    x = X0
    for (label, cwid, _f, _al) in dc:
        txt(o, x + mm(1), y + mm(1), cwid - mm(2), mm(3), label, size=5, style="B", align="center")
        if x > X0:
            vline(o, x, y, HHc)
        x += cwid
    y += HHc
    return o, y


def serv_columns():
    return [
        ("ITEM", mm(14), "item", "center"),
        ("DESCRICAO DO SERVICO", W - mm(14 + 20 + 30), "descricao", "left"),
        ("QTD", mm(20), "qtd", "right"),
        ("VALOR (R$)", mm(30), "valor", "right"),
    ]


def serv_band():
    o = []
    RH = mm(5)
    dc = serv_columns()
    x = X0
    for i, (_l, cwid, fld, al) in enumerate(dc):
        if fld == "valor":
            val = "[FORMATFLOAT('#,##0.00', valor)]"
        elif fld == "qtd":
            val = "[FORMATFLOAT('#,##0.###', qtd)]"
        else:
            val = "[%s]" % fld
        txt(o, x + mm(1), mm(0.6), cwid - mm(2), mm(3.5), val, size=6, align=al)
        if i > 0:
            vline(o, x, 0, RH)
        x += cwid
    hline(o, X0, RH - mm(0.2), W)
    vline(o, X0, 0, RH); vline(o, X1, 0, RH)
    return o, RH


def totals_band():
    o, y = [], 0
    # ---- tributacao do ISS ----
    y = sect(o, y, "TRIBUTACAO DO ISS")
    w5 = W // 5
    cell(o, X0, y, w5, ROW, "CODIGO DO SERVICO", "[cod_servico]", vsize=6, valign_val="left")
    cell(o, X0 + w5, y, w5, ROW, "VALOR DOS SERVICOS", "[FORMATFLOAT('#,##0.00', valor_servicos)]", vsize=6)
    cell(o, X0 + 2 * w5, y, w5, ROW, "BASE DE CALCULO", "[FORMATFLOAT('#,##0.00', base_calculo)]", vsize=6)
    cell(o, X0 + 3 * w5, y, w5, ROW, "ALIQUOTA (%)", "[FORMATFLOAT('#,##0.00', aliquota)]", vsize=6)
    cell(o, X0 + 4 * w5, y, W - 4 * w5, ROW, "VALOR DO ISS", "[FORMATFLOAT('#,##0.00', valor_iss)]",
         vsize=7, vstyle="B")
    y += ROW + mm(1)

    # ---- retencoes federais ----
    y = sect(o, y, "RETENCOES FEDERAIS")
    ret = [("IRRF", "irrf"), ("PIS", "pis"), ("COFINS", "cofins"),
           ("CSLL", "csll"), ("INSS", "inss")]
    rw = W // len(ret)
    for i, (lbl, fld) in enumerate(ret):
        x = X0 + i * rw
        wx = (W - (len(ret) - 1) * rw) if i == len(ret) - 1 else rw
        cell(o, x, y, wx, ROW, lbl, "[FORMATFLOAT('#,##0.00', %s)]" % fld, vsize=6)
    y += ROW + mm(1)

    # ---- valor liquido ----
    box(o, X0, y, W, mm(9))
    txt(o, X0 + mm(2), y + mm(2.5), int(W * 0.6), mm(5),
        "VALOR LIQUIDO DA NOTA (R$)", size=8, style="B")
    txt(o, X0 + int(W * 0.6), y + mm(2), W - int(W * 0.6) - mm(3), mm(5),
        "[FORMATFLOAT('#,##0.00', valor_liquido)]", size=11, style="B", align="right")
    y += mm(9) + mm(1)

    # ---- outras informacoes ----
    y = sect(o, y, "OUTRAS INFORMACOES")
    box(o, X0, y, W, mm(16))
    txt(o, X0 + mm(2), y + mm(1), W - mm(4), mm(14), "[observacoes]", size=6, wrap=True)
    y += mm(17)
    return o, y


def main():
    hb, hh = nfse_band()
    sb, sh = serv_band()
    tb, th = totals_band()
    report = {
        "formatVersion": 1, "generator": "nfse_build.py",
        "title": "NFS-e - Nota Fiscal de Servicos Eletronica (demo)", "author": "ReportsHowie",
        "pages": [page("NFSe", PW, PH, MARGIN, [
            band("masterData", "Nota", hh, hb, dataset="Nota"),
            band("detailData", "Servicos", sh, sb, dataset="Servicos"),
            band("summary", "Totais", th, tb),
        ])],
    }
    data = {
        "Nota": [{
            "municipio": "VITORIA", "numero": "2026/0004587",
            "dt_emissao": "03/07/2026 16:22", "cod_verificacao": "A1B2-C3D4-E5F6",
            "prest_nome": "CONSULTORIA EXEMPLO LTDA", "prest_cnpj": "12345678000199",
            "prest_end": "AV. NOSSA SENHORA DA PENHA, 1200 - SL 801",
            "prest_mun": "VITORIA", "prest_uf": "ES", "prest_im": "123456",
            "tom_nome": "CLIENTE CORPORATIVO S/A", "tom_cnpj": "98765432000155",
            "tom_end": "RUA DA TECNOLOGIA, 45 - CENTRO",
            "tom_mun": "VILA VELHA", "tom_uf": "ES", "tom_email": "financeiro@cliente.com.br",
            "cod_servico": "1.07 - SUPORTE TECNICO", "valor_servicos": 12000.00,
            "base_calculo": 12000.00, "aliquota": 5.00, "valor_iss": 600.00,
            "irrf": 180.00, "pis": 78.00, "cofins": 360.00, "csll": 120.00, "inss": 0.00,
            "valor_liquido": 11262.00,
            "observacoes": "Servicos prestados no mes de junho/2026 conforme contrato 2026-045. "
                           "ISS retido pelo tomador. Documento sem valor de circulacao de mercadoria.",
        }],
        "Servicos": [
            {"item": "1", "descricao": "Consultoria em arquitetura de software (40h)",
             "qtd": 40.0, "valor": 8000.00},
            {"item": "2", "descricao": "Suporte tecnico mensal - plano premium",
             "qtd": 1.0, "valor": 3000.00},
            {"item": "3", "descricao": "Treinamento da equipe (8h)",
             "qtd": 8.0, "valor": 1000.00},
        ],
    }
    save(report, data, "nfse")


if __name__ == "__main__":
    main()
