#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gera o demo NFC-e (DANFE NFC-e / Nota Fiscal de Consumidor Eletronica, modelo 65):
  demos/nfce.rhr + demos/nfce.data.json

Formato CUPOM em bobina de 80 mm (PDV/varejo), com QR Code de consulta do
consumidor e chave de acesso. Mostra QR + MASK + FORMATFLOAT + banda de detalhe.

Uso:  python nfce_build.py
"""
from fiscal_common import (mm, txt, hline, qrcode, band, page, save)

PW, PH, MARGIN = mm(80), mm(122), mm(2)
X0 = MARGIN
X1 = PW - MARGIN
W = X1 - X0
CHAVE_MASK = "#### #### #### #### #### #### #### #### #### #### ####"


def header_band():
    o, y = [], 0
    txt(o, X0, y, W, mm(5), "[emit_nome]", size=8, style="B", align="center"); y += mm(5)
    txt(o, X0, y, W, mm(3), "CNPJ [MASK(emit_cnpj,'##.###.###/####-##')]  IE [emit_ie]",
        size=6, align="center"); y += mm(3.5)
    txt(o, X0, y, W, mm(6), "[emit_end] - [emit_mun]/[emit_uf]",
        size=6, align="center", wrap=True); y += mm(6)
    hline(o, X0, y, W); y += mm(1)
    txt(o, X0, y, W, mm(6),
        "DANFE NFC-e - Documento Auxiliar da Nota Fiscal de Consumidor Eletronica",
        size=5, style="B", align="center", wrap=True); y += mm(7)
    hline(o, X0, y, W); y += mm(1)
    txt(o, X0, y, mm(10), mm(3), "COD", size=5, style="B")
    txt(o, X0 + mm(11), y, mm(30), mm(3), "DESCRICAO", size=5, style="B")
    txt(o, X1 - mm(20), y, mm(20), mm(3), "QTD x UN     VL.TOTAL", size=5, style="B",
        align="right"); y += mm(3.5)
    hline(o, X0, y - mm(0.5), W)
    return o, y


def item_band():
    o = []
    txt(o, X0, mm(0.5), mm(10), mm(3), "[codigo]", size=6)
    txt(o, X0 + mm(11), mm(0.5), W - mm(11), mm(3), "[descricao]", size=6)
    txt(o, X0 + mm(3), mm(4), mm(40), mm(3),
        "[FORMATFLOAT('#,##0.###', qtd)] [un] x [FORMATFLOAT('#,##0.00', valor_unit)]",
        size=6)
    txt(o, X1 - mm(24), mm(4), mm(24), mm(3),
        "[FORMATFLOAT('#,##0.00', valor_total)]", size=6, align="right")
    return o, mm(7.5)


def totals_band():
    o, y = [], 0
    hline(o, X0, y, W); y += mm(1)
    txt(o, X0, y, mm(40), mm(4), "QTD. TOTAL DE ITENS", size=7)
    txt(o, X1 - mm(30), y, mm(30), mm(4), "[qtd_itens]", size=7, align="right"); y += mm(4)
    txt(o, X0, y, mm(40), mm(4), "VALOR TOTAL R$", size=8, style="B")
    txt(o, X1 - mm(30), y, mm(30), mm(4), "[FORMATFLOAT('#,##0.00', valor_total)]",
        size=8, style="B", align="right"); y += mm(5)
    txt(o, X0, y, mm(40), mm(3), "FORMA DE PAGAMENTO", size=5, style="B")
    txt(o, X1 - mm(30), y, mm(30), mm(3), "VALOR PAGO", size=5, style="B", align="right"); y += mm(3.5)
    txt(o, X0, y, mm(40), mm(4), "[forma_pgto]", size=7)
    txt(o, X1 - mm(30), y, mm(30), mm(4), "[FORMATFLOAT('#,##0.00', valor_pago)]",
        size=7, align="right"); y += mm(5)
    hline(o, X0, y, W); y += mm(1.5)

    txt(o, X0, y, W, mm(3), "Consulte pela Chave de Acesso em", size=6, align="center"); y += mm(3)
    txt(o, X0, y, W, mm(3), "[url_consulta]", size=6, align="center"); y += mm(4)
    txt(o, X0, y, W, mm(3), "CHAVE DE ACESSO", size=5, style="B", align="center"); y += mm(3)
    txt(o, X0, y, W, mm(3), "[MASK(chave,'%s')]" % CHAVE_MASK, size=5, align="center"); y += mm(4.5)

    qr = mm(34)
    qrcode(o, X0 + (W - qr) // 2, y, qr, "[qr_conteudo]"); y += qr + mm(2)
    txt(o, X0, y, W, mm(3), "Protocolo de autorizacao: [protocolo]", size=6, align="center"); y += mm(3.5)
    txt(o, X0, y, W, mm(3), "Emissao: [dt_emissao]", size=6, align="center"); y += mm(3.5)
    hline(o, X0, y, W); y += mm(1)
    txt(o, X0, y, W, mm(4), "CONSUMIDOR", size=6, style="B", align="center"); y += mm(4)
    txt(o, X0, y, W, mm(4), "[consumidor]", size=6, align="center", wrap=True); y += mm(5)
    return o, y


def main():
    hb, hh = header_band()
    ib, ih = item_band()
    tb, th = totals_band()
    report = {
        "formatVersion": 1, "generator": "nfce_build.py",
        "title": "NFC-e - Nota Fiscal de Consumidor Eletronica (demo)", "author": "ReportsHowie",
        "pages": [page("NFCe", PW, PH, MARGIN, [
            band("masterData", "Venda", hh, hb, dataset="Venda"),
            band("detailData", "Itens", ih, ib, dataset="Itens"),
            band("summary", "Totais", th, tb),
        ])],
    }
    data = {
        "Venda": [{
            "emit_nome": "MERCADO EXEMPLO LTDA", "emit_cnpj": "12345678000199",
            "emit_ie": "082345678", "emit_end": "RUA DO VAREJO, 45 - CENTRO",
            "emit_mun": "VITORIA", "emit_uf": "ES",
            "qtd_itens": "3", "valor_total": 47.30, "valor_pago": 50.00,
            "forma_pgto": "Dinheiro (troco R$ 2,70)",
            "url_consulta": "www.sefaz.es.gov.br/nfce/consulta",
            "chave": "35240712345678000199650010000012341123456789",
            "qr_conteudo": "https://www.sefaz.es.gov.br/nfce/qrcode?p=35240712345678000199650010000012341123456789|2|1|1|ABCDEF0123456789",
            "protocolo": "135240000987654 - 03/07/2026 14:07",
            "dt_emissao": "03/07/2026 14:07:33",
            "consumidor": "CONSUMIDOR: JOAO DA SILVA - CPF 123.456.789-00",
        }],
        "Itens": [
            {"codigo": "7891", "descricao": "REFRIGERANTE COLA 2L", "un": "UN",
             "qtd": 2.0, "valor_unit": 8.90, "valor_total": 17.80},
            {"codigo": "7420", "descricao": "PAO FRANCES", "un": "KG",
             "qtd": 0.650, "valor_unit": 15.00, "valor_total": 9.75},
            {"codigo": "3310", "descricao": "CAFE TORRADO E MOIDO 500G", "un": "UN",
             "qtd": 1.0, "valor_unit": 19.75, "valor_total": 19.75},
        ],
    }
    save(report, data, "nfce")


if __name__ == "__main__":
    main()
