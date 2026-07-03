#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Demo generico MATRICIAL: relatorio denso estilo formulario continuo / impressora
matricial (fonte monoespacada, colunas alinhadas), agrupado por categoria, com
subtotais, total geral e MULTI-PAGINA (pageHeader e pageFooter repetem a cada
pagina; Folha [PAGE]/[TOTALPAGES]). demos/matricial.rhr + .data.json.

A mesma tecnica de pageHeader/pageFooter serve para paginar DANFE/DACTE longos.

Uso:  python matricial_build.py
"""
from fiscal_common import mm, txt, hline, band, page, save

# paisagem A4: passe dims RETRATO ao page() + orientation=landscape (o motor faz
# o swap; largura efetiva = paperHeight). O layout usa a largura EFETIVA (297).
PAPER_W, PAPER_H, MARGIN = mm(210), mm(297), mm(8)
EFF_W = mm(297)
X0 = 0
W = EFF_W - 2 * MARGIN
MONO = "Courier New"

# (titulo, largura_mm, campo, alinhamento)
COLS = [
    ("CODIGO", 20, "codigo", "left"),
    ("DESCRICAO", 88, "descricao", "left"),
    ("UN", 10, "un", "center"),
    ("ESTOQUE", 24, "estoque", "right"),
    ("CUSTO UNIT", 28, "custo", "right"),
    ("PRECO VENDA", 28, "preco", "right"),
    ("VALOR ESTOQUE", 32, "valor_estoque", "right"),
    ("FORNECEDOR", 51, "fornecedor", "left"),
]


def col_x(idx):
    return mm(sum(c[1] for c in COLS[:idx]))


def pageheader_band():
    o, y = [], 0
    txt(o, X0, y, mm(200), mm(6), "POSICAO DE ESTOQUE", size=13, style="B", fname=MONO)
    # pageHeader roda FORA do contexto de dados: use pseudo-var/funcao (NOW), nao campo
    txt(o, W - mm(70), y + mm(1), mm(70), mm(4),
        "Emitido em [FORMATDATETIME('dd\"/\"mm\"/\"yyyy', NOW)]", size=8, align="right")
    y += mm(7)
    hline(o, X0, y, W)
    x = X0
    for (label, cw, _f, al) in COLS:
        txt(o, x + mm(1), y + mm(1), mm(cw) - mm(2), mm(4), label, size=8, style="B",
            align=al, fname=MONO)
        x += mm(cw)
    y += mm(6)
    hline(o, X0, y - mm(0.5), W)
    return o, y


def group_header_band():
    o = []
    txt(o, X0, mm(1), mm(200), mm(4), ">> CATEGORIA: [categoria]", size=9, style="B", fname=MONO)
    return o, mm(6)


def data_band():
    o = []
    RH = mm(4.4)
    for i, (_l, cw, fld, al) in enumerate(COLS):
        if fld in ("custo", "preco", "valor_estoque"):
            val = "[FORMATFLOAT('#,##0.00', %s)]" % fld
        elif fld == "estoque":
            val = "[FORMATFLOAT('#,##0', estoque)]"
        else:
            val = "[%s]" % fld
        txt(o, col_x(i) + mm(1), mm(0.4), mm(cw) - mm(2), mm(3.6), val, size=8, align=al,
            fname=MONO)
    return o, RH


def group_footer_band():
    o = []
    vx = col_x(6)  # coluna VALOR ESTOQUE
    txt(o, X0, mm(0.5), vx - mm(2), mm(4),
        "   Subtotal [categoria]:  [COUNT([codigo])] itens", size=8, style="B", fname=MONO,
        align="right")
    txt(o, vx + mm(1), mm(0.5), mm(32) - mm(2), mm(4),
        "[FORMATFLOAT('#,##0.00', SUM([valor_estoque]))]", size=8, style="B", align="right",
        fname=MONO)
    hline(o, X0, mm(0.2), W)
    return o, mm(6)


def summary_band():
    o = []
    hline(o, X0, mm(0.5), W)
    vx = col_x(6)
    txt(o, X0, mm(1.5), vx - mm(2), mm(5),
        "TOTAL GERAL:  [COUNT([codigo])] itens em estoque", size=10, style="B", fname=MONO,
        align="right")
    txt(o, vx + mm(1), mm(1.5), mm(32) - mm(2), mm(5),
        "[FORMATFLOAT('#,##0.00', SUM([valor_estoque]))]", size=10, style="B", align="right",
        fname=MONO)
    return o, mm(8)


def pagefooter_band():
    o = []
    hline(o, X0, mm(0.5), W)
    txt(o, X0, mm(1.5), mm(120), mm(4), "ReportsHowie - demo matricial", size=7, fname=MONO)
    txt(o, W - mm(80), mm(1.5), mm(80), mm(4), "Folha [PAGE] de [TOTALPAGES]", size=8,
        align="right", fname=MONO)
    return o, mm(6)


def build_data():
    cats = {
        "FERRAMENTAS": ("FERRAGENS SUL", [
            ("Furadeira de impacto 650W", "UN", 12, 189.90, 329.90),
            ("Parafusadeira 12V bateria", "UN", 8, 145.00, 259.90),
            ("Jogo de chaves combinadas 12pc", "JG", 20, 78.50, 149.90),
            ("Martelo unha 27mm cabo fibra", "UN", 35, 22.00, 44.90),
            ("Alicate universal 8pol", "UN", 40, 18.90, 37.90),
            ("Trena 5m emborrachada", "UN", 60, 12.50, 26.90),
            ("Nivel laser autonivelante", "UN", 5, 220.00, 419.00),
            ("Serra circular 7.1/4 1800W", "UN", 6, 310.00, 559.00),
            ("Esmerilhadeira 4.1/2 720W", "UN", 10, 165.00, 289.90),
            ("Chave de fenda kit 6pc", "JG", 50, 24.00, 49.90),
        ]),
        "ELETRICA": ("ELETRO DISTRIB", [
            ("Cabo flexivel 2.5mm rolo 100m", "RL", 25, 189.00, 279.00),
            ("Disjuntor DIN 20A monopolar", "UN", 120, 12.90, 24.90),
            ("Tomada 2P+T 10A branca", "UN", 200, 4.50, 9.90),
            ("Interruptor simples branco", "UN", 180, 3.90, 8.50),
            ("Lampada LED 9W bivolt", "UN", 300, 6.20, 13.90),
            ("Fita isolante 20m preta", "UN", 150, 3.10, 7.50),
            ("Quadro distribuicao 8 disj", "UN", 15, 45.00, 89.90),
            ("Reator LED painel 18W", "UN", 40, 22.00, 42.90),
            ("Conduite corrugado 3/4 rolo", "RL", 30, 28.00, 49.90),
            ("Sensor presenca teto 360", "UN", 18, 34.00, 64.90),
        ]),
        "HIDRAULICA": ("HIDRO ATACADO", [
            ("Tubo PVC 25mm barra 6m", "BR", 80, 14.50, 27.90),
            ("Joelho 90 PVC 25mm", "UN", 400, 0.90, 2.20),
            ("Registro esfera 3/4", "UN", 45, 18.00, 34.90),
            ("Torneira jardim 1/2 metal", "UN", 60, 22.50, 42.90),
            ("Caixa dagua 500L polietileno", "UN", 8, 189.00, 329.00),
            ("Sifao sanfonado universal", "UN", 90, 6.80, 14.90),
            ("Veda rosca 18mm x 50m", "UN", 120, 2.40, 5.90),
            ("Adaptador soldavel 25x3/4", "UN", 250, 1.10, 2.80),
            ("Cola PVC 175g pincel", "UN", 70, 8.90, 17.90),
            ("Boia automatica caixa dagua", "UN", 30, 19.90, 38.90),
        ]),
        "FIXACAO": ("PARAFUSOS BR", [
            ("Parafuso sextavado M8x40 inox", "PC", 2000, 0.55, 1.20),
            ("Porca sextavada M8 inox", "PC", 2500, 0.32, 0.70),
            ("Arruela lisa 5/16 galv", "PC", 5000, 0.08, 0.15),
            ("Bucha nylon 8mm", "PC", 3000, 0.12, 0.30),
            ("Parafuso chipboard 4.0x40", "PC", 8000, 0.06, 0.14),
            ("Rebite aluminio 4.0x10", "PC", 4000, 0.10, 0.25),
            ("Prego 17x27 kg", "KG", 200, 9.50, 16.90),
            ("Abraçadeira nylon 200mm 100un", "PC", 60, 7.80, 15.90),
            ("Grampo cerca ondulado kg", "KG", 90, 8.20, 15.50),
            ("Pino aco fixacao concreto", "PC", 1500, 0.28, 0.65),
        ]),
        "PINTURA": ("TINTAS COSTA", [
            ("Tinta acrilica 18L branco", "LT", 22, 189.00, 299.00),
            ("Rolo la carneiro 23cm", "UN", 80, 14.90, 28.90),
            ("Pincel cerda 2pol", "UN", 120, 5.50, 11.90),
            ("Lixa dagua 220 folha", "UN", 500, 0.90, 2.10),
            ("Massa corrida 25kg", "SC", 40, 32.00, 58.90),
            ("Fita crepe 48mm x 50m", "UN", 90, 6.90, 13.90),
            ("Solvente thinner 900ml", "UN", 60, 12.00, 22.90),
            ("Fundo preparador parede 5L", "GL", 25, 45.00, 84.90),
            ("Bandeja plastica p/ pintura", "UN", 70, 4.20, 9.50),
            ("Esmalte sintetico 900ml azul", "UN", 35, 28.00, 52.90),
        ]),
    }
    rows = []
    idx = 1
    for cat in cats:
        forn, items = cats[cat]
        for (desc, un, est, custo, preco) in items:
            rows.append({
                "categoria": cat, "codigo": "%05d" % idx, "descricao": desc, "un": un,
                "estoque": est, "custo": custo, "preco": preco,
                "valor_estoque": round(est * custo, 2), "fornecedor": forn,
                "dt_emissao": "03/07/2026 17:40",
            })
            idx += 1
    return rows


def main():
    phb, phh = pageheader_band()
    ghb, ghh = group_header_band()
    db, dh = data_band()
    gfb, gfh = group_footer_band()
    sb, sh = summary_band()
    pfb, pfh = pagefooter_band()
    report = {
        "formatVersion": 1, "generator": "matricial_build.py",
        "title": "Posicao de Estoque (matricial, multi-pagina)", "author": "ReportsHowie",
        "pages": [page("Estoque", PAPER_W, PAPER_H, MARGIN, [
            band("pageHeader", "Cab", phh, phb),
            band("groupHeader", "GrpCat", ghh, ghb),
            band("masterData", "Estoque", dh, db, dataset="Estoque"),
            band("groupFooter", "SubCat", gfh, gfb),
            band("summary", "Total", sh, sb),
            band("pageFooter", "Rodape", pfh, pfb),
        ], orientation="landscape")],
    }
    # grupos precisam de expressao nos header/footer
    report["pages"][0]["bands"][1]["groupExpression"] = "[categoria]"
    report["pages"][0]["bands"][3]["groupExpression"] = "[categoria]"

    data = {"Estoque": build_data()}
    save(report, data, "matricial")
    print("   %d itens de estoque" % len(data["Estoque"]))


if __name__ == "__main__":
    main()
