# Demos — exemplos de relatorio (dados ficticios)

Templates `.rhr` de exemplo, com dados de amostra **ficticios e genericos**
(varejo/escritorio) em arquivos `*.data.json`. Nenhum dado real de cliente.

Renderize com o `rhtool` (ver `tools/rhtool`):

```sh
rhtool export demos/vendas.rhr demos/vendas.pdf --data demos/vendas.data.json
rhtool export demos/vendas.rhr demos/vendas.html --data demos/vendas.data.json
```

## Exemplos

| Template          | Mostra                                                              | Dados                 |
|-------------------|--------------------------------------------------------------------|-----------------------|
| `vendas.rhr`      | Agrupamento por categoria, subtotais, total geral e **grafico de barras** (vendas por categoria) | `vendas.data.json`    |
| `pedidos.rhr`     | Lista de pedidos por cliente/UF com totais                         | `pedidos.data.json`   |
| `catalogo.rhr`    | Catalogo de produtos com **codigo de barras (Code128)** e **QR** por item | `catalogo.data.json`  |
| `subrelatorio.rhr`| **Subrelatorio / master-detail**: entregas por paciente (banda `detailData` ligada por chave) | `subrelatorio.data.json` |
| `exemplo.rhr`     | Template minimo de referencia                                      | —                     |

O formato de `--data` e `{ "NomeDataset": [ { campo: valor, ... }, ... ] }`,
onde `NomeDataset` casa com o `dataSetName` das bandas de dados.

> Os PDFs/HTML versionados sao saidas de referencia. Os exemplos que usam
> **grafico** e **codigo de barras/QR** exigem um `rhtool` compilado com o
> suporte a esses objetos (v0.1.0+).
