#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Demo generico MALA DIRETA (mail merge): uma carta por destinatario, cada uma
em sua propria pagina, com campos mesclados ([nome], [empresa], [endereco]...)
e corpo com quebra de linha automatica. demos/mala_direta.rhr + .data.json.

Truque de "uma pagina por registro": a banda masterData tem altura ~= a area de
conteudo, entao cada registro preenche a pagina e o proximo cai na pagina seguinte.

Uso:  python mala_direta_build.py
"""
from fiscal_common import mm, txt, hline, band, page, save

PW, PH, MARGIN = mm(210), mm(297), mm(18)
X0 = 0
W = PW - 2 * MARGIN
BAND_H = mm(255)   # ~ altura util -> 1 carta por pagina


def carta_band():
    o, y = [], 0
    # papel timbrado
    txt(o, X0, y, W, mm(6), "[remetente_nome]", size=13, style="B");
    txt(o, X0, y + mm(6), W, mm(4), "[remetente_end] - [remetente_cidade]/[remetente_uf]",
        size=8)
    txt(o, X0, y + mm(10), W, mm(4), "CNPJ [MASK(remetente_cnpj,'##.###.###/####-##')]  -  [remetente_site]",
        size=8)
    y += mm(15)
    hline(o, X0, y, W); y += mm(6)

    # data (direita)
    txt(o, X0, y, W, mm(5), "[remetente_cidade], [data_extenso]", size=10, align="right")
    y += mm(10)

    # destinatario
    txt(o, X0, y, W, mm(5), "A/C [nome]", size=11, style="B"); y += mm(5)
    txt(o, X0, y, W, mm(5), "[cargo] - [empresa]", size=10); y += mm(5)
    txt(o, X0, y, W, mm(5), "[endereco]", size=10); y += mm(5)
    txt(o, X0, y, W, mm(5), "[cidade]/[uf]  -  CEP [MASK(cep,'#####-###')]", size=10); y += mm(12)

    # saudacao
    txt(o, X0, y, W, mm(5), "Prezado(a) [nome],", size=11); y += mm(9)

    # corpo (paragrafos com merge + word-wrap)
    p1 = ("E com satisfacao que a [remetente_nome] convida a [empresa] a conhecer o "
          "ReportsHowie, nosso gerador de relatorios para Delphi. Identificamos que "
          "empresas do seu segmento em [cidade] tem obtido ganhos expressivos de "
          "produtividade ao adotar a solucao.")
    p2 = ("Como [cargo], voce sabe o quanto relatorios fiscais e gerenciais confiaveis "
          "fazem diferenca. O ReportsHowie exporta para PDF, HTML, DOCX e XLSX, envia por "
          "e-mail e ainda importa modelos legados do FastReport - tudo em Pascal puro, "
          "sem dependencias externas.")
    p3 = ("Gostariamos de agendar uma demonstracao sem compromisso. Basta responder este "
          "convite ou visitar [remetente_site]. Sera um prazer atender a [empresa].")
    for p in (p1, p2, p3):
        txt(o, X0, y, W, mm(24), p, size=11, wrap=True, align="justify"); y += mm(18)

    y += mm(6)
    txt(o, X0, y, W, mm(5), "Atenciosamente,", size=11); y += mm(16)
    txt(o, X0, y, W, mm(5), "[remetente_assinante]", size=11, style="B"); y += mm(5)
    txt(o, X0, y, W, mm(5), "[remetente_cargo] - [remetente_nome]", size=9)
    return o, BAND_H


def main():
    cb, ch = carta_band()
    report = {
        "formatVersion": 1, "generator": "mala_direta_build.py",
        "title": "Mala Direta (mail merge) - demo", "author": "ReportsHowie",
        "pages": [page("Carta", PW, PH, MARGIN, [
            band("masterData", "Contatos", ch, cb, dataset="Contatos"),
        ])],
    }
    REM = {
        "remetente_nome": "REPORTSHOWIE SOFTWARE LTDA",
        "remetente_end": "AV. DA TECNOLOGIA, 500", "remetente_cidade": "VITORIA",
        "remetente_uf": "ES", "remetente_cnpj": "12345678000199",
        "remetente_site": "github.com/howardroatti/ReportsHowie",
        "remetente_assinante": "Howard Roatti", "remetente_cargo": "Diretor de Produto",
    }

    def contato(nome, cargo, empresa, endereco, cidade, uf, cep):
        d = dict(REM)
        d.update(nome=nome, cargo=cargo, empresa=empresa, endereco=endereco,
                 cidade=cidade, uf=uf, cep=cep, data_extenso="03 de julho de 2026")
        return d

    data = {"Contatos": [
        contato("Ana Beatriz Souza", "Gerente de TI", "Industria Alfa S/A",
                "Rua das Fabricas, 1000 - Distrito Industrial", "Serra", "ES", "29160000"),
        contato("Carlos Eduardo Lima", "Diretor Financeiro", "Comercial Beta Ltda",
                "Av. do Comercio, 250 - Centro", "Vila Velha", "ES", "29100000"),
        contato("Daniela Martins", "Coordenadora de Sistemas", "Servicos Gamma ME",
                "Rua da Inovacao, 45 - Praia do Canto", "Vitoria", "ES", "29055000"),
        contato("Eduardo Nogueira", "Analista de Sistemas Senior", "Delta Solucoes S/A",
                "Rod. BR-101, km 300 - Civit II", "Serra", "ES", "29168000"),
        contato("Fernanda Ribeiro", "Socia-Diretora", "Epsilon Consultoria",
                "Av. Nossa Senhora dos Navegantes, 900", "Vitoria", "ES", "29050000"),
    ]}
    save(report, data, "mala_direta")
    print("   %d cartas (uma por pagina)" % len(data["Contatos"]))


if __name__ == "__main__":
    main()
