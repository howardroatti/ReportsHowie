#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gera o demo DANFE (Documento Auxiliar da Nota Fiscal Eletronica) do ReportsHowie:
  demos/danfe.rhr        - template banded (.rhr)
  demos/danfe.data.json  - dados de exemplo (1 nota + itens)

E um layout FISCAL brasileiro recriado com os objetos do ReportsHowie (caixas via
shape, rotulos/valores via text, chave de acesso como barcode Code128). Mostra o
uso das funcoes de string MASK/ONLYDIGITS (#1) para formatar CNPJ/CPF/IE/chave.

Uso:  python danfe_build.py            (grava ao lado, em demos/)
Depois: rhtool export demos/danfe.rhr demos/danfe.pdf --data demos/danfe.data.json
"""
import json
import os

# ---- unidades: relatorio usa 0,1 mm inteiros ----
def mm(v): return int(round(v * 10))

PAGE_W, PAGE_H = mm(210), mm(297)   # A4
MARGIN = mm(4)
# coordenadas RELATIVAS a area de conteudo (o motor ja aplica a margem):
# X0=0 e W = largura util. NAO somar a margem de novo aqui.
X0 = 0
W = PAGE_W - 2 * MARGIN              # largura util
X1 = W

FONT = "Segoe UI"
BLACK = 0
WHITE = 16777215


def font(size, style=""):
    return {"name": FONT, "size": size, "color": BLACK, "style": style}


def frame(sides="", width=2, color=BLACK):
    return {"sides": sides, "color": color, "width": width}


def txt(objs, l, t, w, h, text, size=7, style="", align="left", valign="top",
        sides="", wrap=False):
    """Texto (rotulo ou valor). 'sides' desenha a moldura da celula (LTRB)."""
    objs.append({
        "type": "text", "name": "", "left": l, "top": t, "width": w, "height": h,
        "visible": True, "frame": frame(sides),
        "text": text, "dataField": "",
        "font": font(size, style),
        "hAlign": align, "vAlign": valign, "wordWrap": wrap,
        "color": WHITE, "transparent": True,
    })


def cell(objs, l, t, w, h, label, value, vsize=7, vstyle="", valign_val="right",
         sides="LTRB"):
    """Celula estilo DANFE: rotulo pequeno no topo + valor abaixo, com moldura."""
    txt(objs, l, t, w, h, "", sides=sides)              # moldura
    txt(objs, l + mm(1), t + mm(0.5), w - mm(2), mm(3), label, size=5)
    txt(objs, l + mm(1), t + mm(3.5), w - mm(2), h - mm(4), value,
        size=vsize, style=vstyle, align=valign_val, valign="top")


def box(objs, l, t, w, h):
    """Retangulo (moldura de secao)."""
    objs.append({
        "type": "shape", "name": "", "left": l, "top": t, "width": w, "height": h,
        "visible": True, "frame": frame(),
        "kind": "rectangle", "penColor": BLACK, "penWidth": 2,
        "brushColor": WHITE, "transparent": True,
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


def barcode(objs, l, t, w, h, text):
    objs.append({
        "type": "barcode", "name": "", "left": l, "top": t, "width": w, "height": h,
        "visible": True, "frame": frame(),
        "symbology": "code128", "text": text, "dataField": "",
        "barColor": BLACK, "showText": False, "moduleWidth": 0,
        "font": font(6),
    })


# ---------------------------------------------------------------------------
#  Banda 1 (masterData 'Nota'): cabecalho fixo da NF-e (1 registro)
# ---------------------------------------------------------------------------
def build_nota_band():
    o = []
    y = 0

    # ---- canhoto (recebemos de ...) ----
    RECV_H = mm(15)
    box(o, X0, y, W, RECV_H)
    txt(o, X0 + mm(2), y + mm(1), W - mm(70), mm(4),
        "RECEBEMOS DE [emit_nome] OS PRODUTOS CONSTANTES DA NOTA FISCAL INDICADA AO LADO",
        size=5, wrap=True)
    vline(o, X1 - mm(66), y, RECV_H)
    txt(o, X0 + mm(2), y + mm(9), mm(50), mm(3), "DATA DE RECEBIMENTO", size=5)
    txt(o, X0 + mm(58), y + mm(9), mm(60), mm(3), "IDENTIFICACAO E ASSINATURA DO RECEBEDOR", size=5)
    txt(o, X1 - mm(64), y + mm(2), mm(62), mm(4),
        "NF-e", size=11, style="B", align="center")
    txt(o, X1 - mm(64), y + mm(8), mm(62), mm(4),
        "No. [numero]   SERIE [serie]", size=6, align="center")
    y += RECV_H + mm(2)
    hline(o, X0, y - mm(1), W)   # tracejado conceptual (linha de corte)

    # ---- identificacao emitente | DANFE | chave ----
    HEAD_H = mm(34)
    box(o, X0, y, W, HEAD_H)
    col_a = mm(86)          # emitente
    col_b = mm(46)          # DANFE
    xa, xb, xc = X0, X0 + col_a, X0 + col_a + col_b
    vline(o, xb, y, HEAD_H)
    vline(o, xc, y, HEAD_H)

    # coluna A: emitente
    txt(o, xa + mm(2), y + mm(2), col_a - mm(4), mm(5), "[emit_nome]",
        size=9, style="B", align="center")
    txt(o, xa + mm(2), y + mm(10), col_a - mm(4), mm(4), "[emit_end]",
        size=6, align="center", wrap=True)
    txt(o, xa + mm(2), y + mm(15), col_a - mm(4), mm(4),
        "[emit_bairro] - [emit_mun]/[emit_uf]", size=6, align="center")
    txt(o, xa + mm(2), y + mm(19), col_a - mm(4), mm(4),
        "CEP [MASK(emit_cep,'#####-###')]  Fone [emit_fone]", size=6, align="center")

    # coluna B: DANFE
    txt(o, xb + mm(1), y + mm(2), col_b - mm(2), mm(5), "DANFE", size=11, style="B", align="center")
    txt(o, xb + mm(1), y + mm(9), col_b - mm(2), mm(6),
        "Documento Auxiliar da Nota Fiscal Eletronica", size=5, align="center", wrap=True)
    txt(o, xb + mm(2), y + mm(17), mm(20), mm(4), "0 - ENTRADA", size=5)
    txt(o, xb + mm(2), y + mm(21), mm(20), mm(4), "1 - SAIDA", size=5)
    txt(o, xb + col_b - mm(10), y + mm(17), mm(7), mm(7), "[tipo]",
        size=10, style="B", align="center", sides="LTRB")
    txt(o, xb + mm(1), y + mm(27), col_b - mm(2), mm(4),
        "No. [numero]   SERIE [serie]", size=6, style="B", align="center")
    txt(o, xb + mm(1), y + mm(31), col_b - mm(2), mm(3), "FOLHA 1/1", size=5, align="center")

    # coluna C: barcode + chave
    wc = W - col_a - col_b
    barcode(o, xc + mm(3), y + mm(2), wc - mm(6), mm(11), "[chave]")
    txt(o, xc + mm(2), y + mm(14), wc - mm(4), mm(3), "CHAVE DE ACESSO", size=5)
    txt(o, xc + mm(2), y + mm(17), wc - mm(4), mm(4),
        "[MASK(chave,'#### #### #### #### #### #### #### #### #### #### ####')]",
        size=5, style="B", align="center")
    txt(o, xc + mm(2), y + mm(23), wc - mm(4), mm(8),
        "Consulta de autenticidade no portal nacional da NF-e "
        "www.nfe.fazenda.gov.br/portal ou no site da Sefaz autorizadora",
        size=5, align="center", wrap=True)
    y += HEAD_H

    # ---- natureza da operacao | protocolo ----
    ROW = mm(9)
    natw = int(W * 0.62)
    cell(o, X0, y, natw, ROW, "NATUREZA DA OPERACAO", "[natureza]", vsize=6, valign_val="left")
    cell(o, X0 + natw, y, W - natw, ROW, "PROTOCOLO DE AUTORIZACAO DE USO",
         "[protocolo]", vsize=6, valign_val="left")
    y += ROW

    # ---- IE | IE subst | CNPJ ----
    w3 = W // 3
    cell(o, X0, y, w3, ROW, "INSCRICAO ESTADUAL", "[emit_ie]", vsize=6, valign_val="left")
    cell(o, X0 + w3, y, w3, ROW, "INSCR.ESTADUAL DO SUBST.TRIB.", "", vsize=6)
    cell(o, X0 + 2 * w3, y, W - 2 * w3, ROW, "CNPJ",
         "[MASK(emit_cnpj,'##.###.###/####-##')]", vsize=6, valign_val="left")
    y += ROW + mm(2)

    # ---- DESTINATARIO / REMETENTE ----
    txt(o, X0, y, W, mm(4), "DESTINATARIO / REMETENTE", size=6, style="B")
    y += mm(4)
    # linha 1: nome | CNPJ/CPF | data emissao
    c1, c2 = int(W * 0.60), int(W * 0.22)
    cell(o, X0, y, c1, ROW, "NOME / RAZAO SOCIAL", "[dest_nome]", vsize=6, valign_val="left")
    cell(o, X0 + c1, y, c2, ROW, "CNPJ / CPF",
         "[MASK(dest_cnpj,'##.###.###/####-##')]", vsize=6, valign_val="left")
    cell(o, X0 + c1 + c2, y, W - c1 - c2, ROW, "DATA DA EMISSAO", "[dt_emissao]", vsize=6)
    y += ROW
    # linha 2: endereco | bairro | CEP | data entrada/saida
    e1, e2, e3 = int(W * 0.44), int(W * 0.24), int(W * 0.14)
    cell(o, X0, y, e1, ROW, "ENDERECO", "[dest_end]", vsize=6, valign_val="left")
    cell(o, X0 + e1, y, e2, ROW, "BAIRRO", "[dest_bairro]", vsize=6, valign_val="left")
    cell(o, X0 + e1 + e2, y, e3, ROW, "CEP", "[MASK(dest_cep,'#####-###')]", vsize=6, valign_val="left")
    cell(o, X0 + e1 + e2 + e3, y, W - e1 - e2 - e3, ROW, "DATA ENTRADA/SAIDA", "[dt_saida]", vsize=6)
    y += ROW
    # linha 3: municipio | UF | fone | IE
    m1, m2, m3 = int(W * 0.40), int(W * 0.08), int(W * 0.22)
    cell(o, X0, y, m1, ROW, "MUNICIPIO", "[dest_mun]", vsize=6, valign_val="left")
    cell(o, X0 + m1, y, m2, ROW, "UF", "[dest_uf]", vsize=6, valign_val="center")
    cell(o, X0 + m1 + m2, y, m3, ROW, "FONE / FAX", "[dest_fone]", vsize=6, valign_val="left")
    cell(o, X0 + m1 + m2 + m3, y, W - m1 - m2 - m3, ROW, "INSCRICAO ESTADUAL", "[dest_ie]", vsize=6)
    y += ROW + mm(2)

    # ---- CALCULO DO IMPOSTO ----
    txt(o, X0, y, W, mm(4), "CALCULO DO IMPOSTO", size=6, style="B")
    y += mm(4)
    w5 = W // 5
    cell(o, X0, y, w5, ROW, "BASE DE CALCULO DO ICMS",
         "[FORMATFLOAT('#,##0.00', base_icms)]", vsize=6)
    cell(o, X0 + w5, y, w5, ROW, "VALOR DO ICMS",
         "[FORMATFLOAT('#,##0.00', valor_icms)]", vsize=6)
    cell(o, X0 + 2 * w5, y, w5, ROW, "BASE CALCULO ICMS ST", "0,00", vsize=6)
    cell(o, X0 + 3 * w5, y, w5, ROW, "VALOR DO ICMS ST", "0,00", vsize=6)
    cell(o, X0 + 4 * w5, y, W - 4 * w5, ROW, "VALOR TOTAL DOS PRODUTOS",
         "[FORMATFLOAT('#,##0.00', valor_produtos)]", vsize=6)
    y += ROW
    cell(o, X0, y, w5, ROW, "VALOR DO FRETE", "0,00", vsize=6)
    cell(o, X0 + w5, y, w5, ROW, "VALOR DO SEGURO", "0,00", vsize=6)
    cell(o, X0 + 2 * w5, y, w5, ROW, "DESCONTO", "0,00", vsize=6)
    cell(o, X0 + 3 * w5, y, w5, ROW, "OUTRAS DESPESAS", "0,00", vsize=6)
    cell(o, X0 + 4 * w5, y, W - 4 * w5, ROW, "VALOR TOTAL DA NOTA",
         "[FORMATFLOAT('#,##0.00', valor_total)]", vsize=8, vstyle="B")
    y += ROW + mm(2)

    # ---- DADOS DOS PRODUTOS / SERVICOS  (titulo + cabecalho de colunas) ----
    txt(o, X0, y, W, mm(4), "DADOS DOS PRODUTOS / SERVICOS", size=6, style="B")
    y += mm(4)
    HH = mm(6)
    cols = product_columns()
    box(o, X0, y, W, HH)
    x = X0
    for (label, cw, _field, _al) in cols:
        txt(o, x + mm(1), y + mm(1.5), cw - mm(2), mm(4), label, size=5, style="B",
            align="center")
        if x > X0:
            vline(o, x, y, HH)
        x += cw
    y += HH

    return o, y


def product_columns():
    # (rotulo, largura, campo, alinhamento do valor)
    return [
        ("CODIGO", mm(16), "codigo", "left"),
        ("DESCRICAO DO PRODUTO / SERVICO", W - mm(16 + 16 + 12 + 10 + 24 + 26), "descricao", "left"),
        ("NCM/SH", mm(16), "ncm", "center"),
        ("CFOP", mm(12), "cfop", "center"),
        ("UN", mm(10), "un", "center"),
        ("QTD", mm(24), "qtd", "right"),
        ("V.UNIT / V.TOTAL", mm(26), "valor_total", "right"),
    ]


# ---------------------------------------------------------------------------
#  Banda 2 (masterData 'Itens'): uma linha de produto (repete por registro)
# ---------------------------------------------------------------------------
def build_item_band():
    o = []
    RH = mm(5)
    cols = product_columns()
    x = X0
    for i, (_label, cw, field, al) in enumerate(cols):
        if field == "qtd":
            val = "[FORMATFLOAT('#,##0.0000', qtd)] [un]"
        elif field == "valor_total":
            val = "[FORMATFLOAT('#,##0.00', valor_unit)] / [FORMATFLOAT('#,##0.00', valor_total)]"
        else:
            val = "[%s]" % field
        txt(o, x + mm(1), y_pad(RH), cw - mm(2), mm(4), val, size=6, align=al)
        if i > 0:
            vline(o, x, 0, RH)
        x += cw
    hline(o, X0, RH - mm(0.2), W)   # separador de linha
    vline(o, X0, 0, RH)
    vline(o, X1, 0, RH)
    return o, RH


def y_pad(rh):
    return mm(0.6)


# ---------------------------------------------------------------------------
#  Banda 3 (summary): dados adicionais
# ---------------------------------------------------------------------------
def build_summary_band():
    o = []
    H = mm(24)
    txt(o, X0, mm(1), W, mm(4), "DADOS ADICIONAIS", size=6, style="B")
    box(o, X0, mm(5), W, H)
    txt(o, X0 + mm(2), mm(6), int(W * 0.6) - mm(4), mm(3), "INFORMACOES COMPLEMENTARES", size=5)
    txt(o, X0 + mm(2), mm(9.5), int(W * 0.6) - mm(4), H - mm(6),
        "[info_complementar]", size=6, wrap=True)
    vline(o, X0 + int(W * 0.6), mm(5), H)
    txt(o, X0 + int(W * 0.6) + mm(2), mm(6), int(W * 0.4) - mm(4), mm(3), "RESERVADO AO FISCO", size=5)
    return o, mm(5) + H + mm(2)


def band(band_type, name, height, objects, dataset=""):
    return {
        "bandType": band_type, "name": name, "height": height,
        "visible": True, "canGrow": False, "canShrink": False, "printIfEmpty": False,
        "dataSetName": dataset, "groupExpression": "",
        "masterKeyExpr": "", "detailKeyField": "",
        "objects": objects,
    }


def main():
    here = os.path.dirname(os.path.abspath(__file__))

    nota_objs, nota_h = build_nota_band()
    item_objs, item_h = build_item_band()
    summ_objs, summ_h = build_summary_band()

    report = {
        "formatVersion": 1,
        "generator": "danfe_build.py",
        "title": "DANFE - Nota Fiscal Eletronica (demo)",
        "author": "ReportsHowie",
        "pages": [{
            "name": "DANFE",
            "paperWidth": PAGE_W, "paperHeight": PAGE_H, "orientation": "portrait",
            "marginLeft": MARGIN, "marginTop": MARGIN,
            "marginRight": MARGIN, "marginBottom": MARGIN,
            "bands": [
                band("masterData", "Nota", nota_h, nota_objs, dataset="Nota"),
                band("detailData", "Itens", item_h, item_objs, dataset="Itens"),
                band("summary", "Adicionais", summ_h, summ_objs),
            ],
        }],
    }

    data = {
        "Nota": [{
            "tipo": "1", "numero": "000.123.456", "serie": "001",
            "natureza": "VENDA DE MERCADORIA", "protocolo": "135240000123456 - 01/07/2026 10:32",
            "chave": "35240712345678000199550010001234561123456780",
            "emit_nome": "COMERCIAL EXEMPLO LTDA",
            "emit_end": "AV. DAS INDUSTRIAS, 1500",
            "emit_bairro": "DISTRITO INDUSTRIAL", "emit_mun": "SERRA", "emit_uf": "ES",
            "emit_cep": "29160000", "emit_fone": "(27) 3333-4444",
            "emit_cnpj": "12345678000199", "emit_ie": "082345678",
            "dest_nome": "CLIENTE DEMONSTRACAO S/A", "dest_cnpj": "98765432000155",
            "dest_end": "RUA DO COMERCIO, 200", "dest_bairro": "CENTRO",
            "dest_cep": "29010000", "dest_mun": "VITORIA", "dest_uf": "ES",
            "dest_fone": "(27) 3222-1111", "dest_ie": "081112223",
            "dt_emissao": "01/07/2026", "dt_saida": "01/07/2026",
            "base_icms": 2450.00, "valor_icms": 441.00,
            "valor_produtos": 2450.00, "valor_total": 2450.00,
            "info_complementar": "Documento emitido por ME/EPP optante pelo Simples Nacional. "
                                 "Nao gera direito a credito fiscal de ICMS e de ISS. "
                                 "Pedido 4567 - Vendedor: Ana.",
        }],
        "Itens": [
            {"codigo": "1001", "descricao": "PARAFUSO SEXTAVADO M8 x 40MM ACO INOX",
             "ncm": "73181500", "cfop": "5102", "un": "PC", "qtd": 500.0,
             "valor_unit": 1.20, "valor_total": 600.00},
            {"codigo": "1002", "descricao": "PORCA SEXTAVADA M8 ACO INOX",
             "ncm": "73181600", "cfop": "5102", "un": "PC", "qtd": 500.0,
             "valor_unit": 0.70, "valor_total": 350.00},
            {"codigo": "2050", "descricao": "ARRUELA LISA 5/16 GALVANIZADA",
             "ncm": "73182200", "cfop": "5102", "un": "PC", "qtd": 1000.0,
             "valor_unit": 0.15, "valor_total": 150.00},
            {"codigo": "3100", "descricao": "CHAPA ACO CARBONO 2MM 1000x2000",
             "ncm": "72104900", "cfop": "5102", "un": "KG", "qtd": 45.0,
             "valor_unit": 30.00, "valor_total": 1350.00},
        ],
    }

    rhr_path = os.path.join(here, "danfe.rhr")
    data_path = os.path.join(here, "danfe.data.json")
    with open(rhr_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    nobj = len(nota_objs) + len(item_objs) + len(summ_objs)
    print("OK: danfe.rhr (%d objetos, altura cabecalho %.0fmm) + danfe.data.json"
          % (nobj, nota_h / 10.0))


if __name__ == "__main__":
    main()
