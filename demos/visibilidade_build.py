#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Demo das issues #24 (visibleExpr), #25 (parametros/SetParam) e #26 (motor
null-safe). Um UNICO template serve duas variantes de uma "Ordem de Producao":
COM e SEM a coluna de valor, alternadas por um parametro de relatorio.

  - #25 params: [titulo] (titulo dinamico) e [exibe_valor] (S/N) NAO existem no
    dataset — vem de Rep.SetParam / rhtool --param.
  - #24 visibleExpr: a coluna "VALOR" (cabecalho + celula) e a banda de TOTAL so
    aparecem quando "[exibe_valor]='S'".
  - #26 null-safe: a celula de valor usa IIF/FORMATFLOAT sobre [valor], que pode
    ser NULL (item sem custo) ou 0 — deve sair EM BRANCO, nunca o literal cru.

Uso:
  python visibilidade_build.py
  # depois, no rhtool (rebuildado):
  rhtool export visibilidade.rhr com_valor.pdf --data visibilidade.data.json \\
      --param exibe_valor=S --param titulo="ORDEM DE PRODUCAO - VALORADA"
  rhtool export visibilidade.rhr sem_valor.pdf --data visibilidade.data.json \\
      --param exibe_valor=N --param titulo="ORDEM DE PRODUCAO"
"""
from fiscal_common import mm, txt, hline, fill, band, page, save, GRAY

PW, PH, MARGIN = mm(210), mm(297), mm(12)
X0 = 0
W = PW - 2 * MARGIN

# colunas: produto | qtd | valor
WP = int(W * 0.58)
WQ = int(W * 0.14)
WV = W - WP - WQ
XP, XQ, XV = X0, X0 + WP, X0 + WP + WQ

VIS = "[exibe_valor]='S'"   # condicao de visibilidade da coluna/banda de valor
# celula null-safe: NULL ou 0 -> branco; >0 -> valor formatado (nunca o literal)
VALOR_CELL = "[IIF([valor]>0, FORMATFLOAT('#,##0.00', [valor]), '')]"


def vis(objs, expr):
    """Marca o ultimo objeto adicionado com visibilidade condicional (#24)."""
    objs[-1]["visibleExpr"] = expr


def page_header():
    o = []
    # titulo dinamico via parametro (#25) — resolvido fora da linha de dados
    txt(o, X0, 0, W, mm(8), "[titulo]", size=15, style="B", align="center")
    txt(o, X0, mm(8), W, mm(4),
        "Emitida em [FORMATDATETIME('dd\"/\"mm\"/\"yyyy hh\":\"nn', NOW)]",
        size=8, align="center")
    # faixa de cabecalho da tabela
    yh = mm(14)
    fill(o, X0, yh, W, mm(6), GRAY)
    txt(o, XP + mm(1), yh + mm(1.2), WP - mm(2), mm(4), "PRODUTO", size=8, style="B")
    txt(o, XQ, yh + mm(1.2), WQ, mm(4), "QTD", size=8, style="B", align="center")
    # cabecalho da coluna de valor: some quando exibe_valor <> 'S' (#24)
    txt(o, XV, yh + mm(1.2), WV - mm(1), mm(4), "VALOR (R$)", size=8, style="B",
        align="right")
    vis(o, VIS)
    return band("pageHeader", "Cabecalho", mm(21), o)


def master():
    o = []
    txt(o, XP + mm(1), mm(0.6), WP - mm(2), mm(5), "[produto]", size=9, valign="center")
    txt(o, XQ, mm(0.6), WQ, mm(5), "[qtd]", size=9, align="center", valign="center")
    # celula de valor null-safe (#26) + visibilidade condicional (#24)
    txt(o, XV, mm(0.6), WV - mm(1), mm(5), VALOR_CELL, size=9, align="right",
        valign="center")
    vis(o, VIS)
    hline(o, X0, mm(6.4), W)
    return band("masterData", "Itens", mm(6.6), o, dataset="Itens")


def summary():
    o = []
    fill(o, X0, 0, W, mm(7), GRAY)
    txt(o, XP + mm(1), mm(1.4), WP + WQ - mm(2), mm(4), "TOTAL GERAL",
        size=10, style="B")
    # SUM ignora valores NULL; formatacao null-safe
    txt(o, XV, mm(1.4), WV - mm(1), mm(4),
        "[FORMATFLOAT('#,##0.00', SUM([valor]))]", size=10, style="B", align="right")
    b = band("summary", "Total", mm(8), o)
    b["visibleExpr"] = VIS   # a banda inteira some quando exibe_valor <> 'S' (#24)
    return b


def page_footer():
    o = []
    hline(o, X0, 0, W)
    txt(o, X0, mm(1), W, mm(4), "[titulo]", size=7)  # param no rodape (#25)
    txt(o, X0, mm(1), W, mm(4), "Pagina [PAGE] de [TOTALPAGES]", size=7, align="right")
    return band("pageFooter", "Rodape", mm(6), o)


def main():
    report = {
        "formatVersion": 1, "generator": "visibilidade_build.py",
        "title": "Ordem de Producao (demo visibleExpr + params + null-safe)",
        "author": "ReportsHowie",
        "pages": [page("OP", PW, PH, MARGIN,
                       [page_header(), master(), summary(), page_footer()])],
    }
    data = {"Itens": [
        {"produto": "Parafuso sextavado M6 x 20", "qtd": 100, "valor": 12.50},
        {"produto": "Arruela lisa M6",            "qtd": 250, "valor": 3.20},
        {"produto": "Item sem custo (valor null)", "qtd": 10},          # valor NULL
        {"produto": "Bucha de nylon (valor 0)",   "qtd": 40, "valor": 0},  # valor 0
        {"produto": "Porca autotravante M6",      "qtd": 100, "valor": 8.75},
    ]}
    save(report, data, "visibilidade")
    print("   teste: exporte com --param exibe_valor=S e depois =N")


if __name__ == "__main__":
    main()
