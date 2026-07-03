#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Demo fiscal DACCE - Documento Auxiliar da Carta de Correcao Eletronica (evento
da NF-e). demos/dacce.rhr + demos/dacce.data.json.

Estrutura tipica: identificacao da NF-e corrigida (chave + barcode), emitente/
destinatario, condicoes de uso (texto legal padrao) e o texto da correcao.

Uso:  python dacce_build.py
"""
from fiscal_common import (mm, txt, cell, box, fill, vline, barcode,
                           band, page, save)

PW, PH, MARGIN = mm(210), mm(297), mm(6)
X0 = 0
W = PW - 2 * MARGIN
ROW = mm(9)
CHAVE_MASK = "#### #### #### #### #### #### #### #### #### #### ####"

CONDICOES = (
    "A Carta de Correcao e disciplinada pelo paragrafo 1o-A do art. 7o do Convenio "
    "S/N, de 15 de dezembro de 1970 e pode ser utilizada para regularizacao de erro "
    "ocorrido na emissao de documento fiscal, desde que o erro nao esteja relacionado "
    "com: I - as variaveis que determinam o valor do imposto tais como: base de "
    "calculo, aliquota, diferenca de preco, quantidade, valor da operacao ou da "
    "prestacao; II - a correcao de dados cadastrais que implique mudanca do remetente "
    "ou do destinatario; III - a data de emissao ou de saida."
)


def sect(o, y, text):
    fill(o, X0, y, W, mm(4.5))
    txt(o, X0 + mm(1), y + mm(0.8), W, mm(3), text, size=7, style="B")
    return y + mm(4.5)


def cce_band():
    o, y = [], 0
    # titulo
    box(o, X0, y, W, mm(16))
    txt(o, X0, y + mm(2), W, mm(6), "CARTA DE CORRECAO ELETRONICA", size=14, style="B",
        align="center")
    txt(o, X0, y + mm(9), W, mm(4),
        "DACCE - Documento Auxiliar da Carta de Correcao Eletronica", size=7, align="center")
    txt(o, X0, y + mm(12), W, mm(3),
        "Nao possui valor fiscal - simples representacao da CC-e indicada abaixo", size=6,
        align="center")
    y += mm(16) + mm(2)

    # chave da NF-e (barcode)
    box(o, X0, y, W, mm(16))
    barcode(o, X0 + mm(3), y + mm(2), int(W * 0.62), mm(9), "[chave]")
    txt(o, X0 + mm(3), y + mm(12), int(W * 0.62), mm(3),
        "CHAVE DE ACESSO DA NF-e", size=5)
    vline(o, X0 + int(W * 0.66), y, mm(16))
    txt(o, X0 + int(W * 0.66) + mm(2), y + mm(2), W - int(W * 0.66) - mm(4), mm(3),
        "NF-e CORRIGIDA", size=5)
    txt(o, X0 + int(W * 0.66) + mm(2), y + mm(5), W - int(W * 0.66) - mm(4), mm(4),
        "No. [numero]  SERIE [serie]", size=8, style="B")
    txt(o, X0 + int(W * 0.66) + mm(2), y + mm(10), W - int(W * 0.66) - mm(4), mm(4),
        "[MASK(chave,'%s')]" % CHAVE_MASK, size=5, wrap=True)
    y += mm(16) + mm(2)

    # emitente | destinatario
    half = W // 2
    y = sect(o, y, "EMITENTE / DESTINATARIO")
    cell(o, X0, y, half, mm(8), "EMITENTE", "[emit_nome]", vsize=6, valign_val="left")
    cell(o, X0 + half, y, W - half, mm(8), "DESTINATARIO", "[dest_nome]", vsize=6,
         valign_val="left"); y += mm(8)
    cell(o, X0, y, half, mm(8), "CNPJ EMITENTE",
         "[MASK(emit_cnpj,'##.###.###/####-##')]", vsize=6, valign_val="left")
    cell(o, X0 + half, y, W - half, mm(8), "CNPJ/CPF DESTINATARIO",
         "[MASK(dest_cnpj,'##.###.###/####-##')]", vsize=6, valign_val="left")
    y += mm(8) + mm(2)

    # dados do evento
    w3 = W // 3
    cell(o, X0, y, w3, ROW, "SEQUENCIA DO EVENTO", "[sequencia]", vsize=7, valign_val="left")
    cell(o, X0 + w3, y, w3, ROW, "DATA/HORA DO EVENTO", "[dt_evento]", vsize=7, valign_val="left")
    cell(o, X0 + 2 * w3, y, W - 2 * w3, ROW, "PROTOCOLO DO EVENTO", "[protocolo]",
         vsize=7, valign_val="left")
    y += ROW + mm(2)

    # condicoes de uso (texto legal padrao, com word-wrap)
    y = sect(o, y, "CONDICOES DE USO")
    box(o, X0, y, W, mm(26))
    txt(o, X0 + mm(2), y + mm(1.5), W - mm(4), mm(24), CONDICOES, size=8, wrap=True,
        align="justify")
    y += mm(26) + mm(2)

    # correcao
    y = sect(o, y, "CORRECAO")
    box(o, X0, y, W, mm(30))
    txt(o, X0 + mm(2), y + mm(1.5), W - mm(4), mm(28), "[texto_correcao]", size=9, wrap=True,
        align="justify")
    y += mm(30)
    return o, y


def main():
    cb, ch = cce_band()
    report = {
        "formatVersion": 1, "generator": "dacce_build.py",
        "title": "DACCE - Carta de Correcao Eletronica (demo)", "author": "ReportsHowie",
        "pages": [page("DACCE", PW, PH, MARGIN, [
            band("masterData", "CCe", ch, cb, dataset="CCe"),
        ])],
    }
    data = {"CCe": [{
        "chave": "35240712345678000199550010001234561123456780",
        "numero": "000.123.456", "serie": "001",
        "emit_nome": "COMERCIAL EXEMPLO LTDA", "emit_cnpj": "12345678000199",
        "dest_nome": "CLIENTE DEMONSTRACAO S/A", "dest_cnpj": "98765432000155",
        "sequencia": "1", "dt_evento": "03/07/2026 18:05",
        "protocolo": "135240009988776 - 03/07/2026 18:05",
        "texto_correcao": ("Onde se le 'Transportadora: a definir', leia-se "
                           "'Transportadora: TRANSPORTADORA EXEMPLO LTDA, CNPJ "
                           "11.222.333/0001-81'. Correcao da modalidade do frete de "
                           "'sem frete' para 'por conta do remetente (CIF)'. Demais "
                           "dados da NF-e permanecem inalterados."),
    }]}
    save(report, data, "dacce")


if __name__ == "__main__":
    main()
