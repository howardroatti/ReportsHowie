# rhtool — ReportsHowie CLI

Ferramenta de linha de comando para **validar, inspecionar e exportar** templates `.rhr` sem abrir o IDE. É a base *headless* para o futuro servidor **MCP** (Fase 12.b).

## Build

O Delphi **Community não compila por linha de comando** — abra `rhtool.dpr` no IDE e dê **Build** (Win32 ou Win64). O `.dpr` linka os fontes `rh.*` estaticamente (não precisa do pacote instalado).

O executável sai em `tools\rhtool\Win64\Debug\rhtool.exe` (ou conforme a plataforma/config).

## Uso

```text
rhtool validate <arquivo.rhr>            valida o template (parse do modelo)
rhtool info <arquivo.rhr>                mostra a estrutura (paginas/bandas/objetos)
rhtool export <arquivo.rhr> <saida.ext>  exporta para .pdf / .html / .xlsx / .docx
rhtool version
rhtool help
```

Códigos de saída: `0` sucesso · `1` uso incorreto · `2` erro (ex.: arquivo inválido).

### Exemplos

```sh
rhtool validate ..\..\demos\pedidos.rhr
rhtool info ..\..\demos\pedidos.rhr
rhtool export ..\..\demos\vendas.rhr saida\vendas.pdf
```

> **Obs.:** `export` renderiza o **layout** do template. Sem dados ligados, as bandas de dados (`masterData`/grupos) não produzem linhas; bandas estáticas (título, sumário com texto fixo, etc.) saem normalmente. Renderização com dados vindos de JSON/CSV é um próximo passo (12.b).

## JSON Schema

O formato `.rhr` tem um **JSON Schema** em [`schema/reportshowie.schema.json`](../../schema/reportshowie.schema.json) — use-o para validar/gerar templates em qualquer linguagem (ajv, `jsonschema`, etc.) e como contrato para LLMs (Fase 12).
