# rhtool — ReportsHowie CLI

Ferramenta de linha de comando para **validar, inspecionar e exportar** templates `.rhr` sem abrir o IDE. É a base *headless* para o futuro servidor **MCP** (Fase 12.b).

## Build

O Delphi **Community não compila por linha de comando** — abra `rhtool.dpr` no IDE e dê **Build** (Win32 ou Win64). O `.dpr` linka os fontes `rh.*` estaticamente (não precisa do pacote instalado).

O executável sai em `tools\rhtool\Win64\Debug\rhtool.exe` (ou conforme a plataforma/config).

## Uso

```text
rhtool validate <arquivo.rhr>                        valida o template (parse do modelo)
rhtool info <arquivo.rhr>                            mostra a estrutura (paginas/bandas/objetos)
rhtool export <arquivo.rhr> <saida.ext> [--data <dados.json>]
                                                     exporta para .pdf / .html / .xlsx / .docx
rhtool version
rhtool help
```

Códigos de saída: `0` sucesso · `1` uso incorreto · `2` erro (ex.: arquivo inválido).

### Exemplos

```sh
rhtool validate ..\..\demos\pedidos.rhr
rhtool info ..\..\demos\pedidos.rhr
rhtool export ..\..\demos\vendas.rhr saida\vendas.pdf
rhtool export ..\..\demos\pedidos.rhr saida\pedidos.pdf --data ..\..\demos\pedidos.data.json
```

### Dados (`--data`)

Sem `--data`, `export` renderiza só o **layout** (bandas de dados não geram linhas). Com `--data`, você alimenta datasets em memória e o relatório sai **completo**. O JSON mapeia o **nome do dataset** (igual ao `dataSetName` das bandas) para um array de registros:

```json
{
  "Pedidos": [
    { "cliente": "ACME Ltda", "uf": "SP", "categoria": "Enterais", "produto": "Nutri A", "quantidade": 10, "total": 1250.00 },
    { "cliente": "ACME Ltda", "uf": "SP", "categoria": "Parenterais", "produto": "Sol P1", "quantidade": 2, "total": 980.00 }
  ]
}
```

- Tipos inferidos por campo: número → `float`, booleano → `boolean`, resto → texto.
- Para **grupos**, ordene os registros na ordem dos grupos (ex.: por `cliente`, depois `categoria`).
- Datas: passe como **texto já formatado** (JSON não tem tipo data).
- Datasets em memória via `TClientDataSet` (linkado com `MidasLib`, sem DLL).

## JSON Schema

O formato `.rhr` tem um **JSON Schema** em [`schema/reportshowie.schema.json`](../../schema/reportshowie.schema.json) — use-o para validar/gerar templates em qualquer linguagem (ajv, `jsonschema`, etc.) e como contrato para LLMs (Fase 12).
