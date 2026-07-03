# frx2rhr — Conversor FastReport → ReportsHowie

Converte templates **FastReport VCL** (`.frx`, que é XML) para o formato
`.rhr` (JSON) do ReportsHowie. Objetivo: reduzir o retrabalho de migração de
bases legadas (issue [#21](https://github.com/howardroatti/ReportsHowie/issues/21)).

Roda em **Python 3** puro (sem Delphi), então cabe num pipeline ou numa etapa
assistida por IA.

## Uso

```sh
python frx2rhr.py entrada.frx saida.rhr [--dpi 96] [--verbose]
```

Depois valide/renderize com o `rhtool`:

```sh
rhtool validate saida.rhr
rhtool export saida.rhr saida.pdf --data dados.json
```

Exemplo pronto em `samples/` (`exemplo.frx` → `exemplo.rhr`, com `exemplo.data.json`).

## Mapa de conversão

| FastReport | ReportsHowie | Observações |
|---|---|---|
| `TfrxReportPage` | página | `PaperWidth/Height` e margens em **mm**; `Orientation` |
| `TfrxReportTitle` | banda `reportTitle` | |
| `TfrxReportSummary` | banda `summary` | |
| `TfrxPageHeader` / `TfrxPageFooter` | `pageHeader` / `pageFooter` | |
| `TfrxMasterData` | `masterData` | `DataSet` → `dataSetName` |
| `TfrxDetailData` / `TfrxSubdetailData` | `detailData` | |
| `TfrxGroupHeader` / `TfrxGroupFooter` | `groupHeader` / `groupFooter` | `Condition` → `groupExpression` |
| `TfrxMemoView` | objeto `text` | fonte (nome/tamanho/estilo/cor), alinhamento, word-wrap |
| `TfrxLineView` | objeto `line` | espessura via `Frame.Width` |
| `TfrxShapeView` | objeto `rect`/`ellipse` | borda + preenchimento |
| `TfrxPictureView` | objeto `image` (vazio) | **imagem embutida não convertida** (reaponte a origem) |
| `TfrxBarCodeView` | objeto `barcode` | `code128`/`qrcode` a partir de `BarType` |

### Coordenadas e unidades

- **Página** (`PaperWidth/Height`, margens): milímetros no `.frx`.
- **Bandas/objetos** (`Left/Top/Width/Height`): **pixels** no DPI de design
  (padrão **96**; ajuste com `--dpi` se o template foi desenhado em outro).
- Conversão: `unidade_rhr (0,1mm) = px / dpi * 25,4 * 10`.

### Expressões

Ilhas `[Dataset."campo"]` / `[Dataset.campo]` → `[campo]`. Pseudovariáveis como
`[PAGE]`/`[TOTALPAGES]` passam direto. **Funções/scripts do FastReport
(PascalScript) não são convertidos** — revise expressões complexas na mão.

## Limitações conhecidas (v0)

- Imagens embutidas (`TfrxPictureView`) saem como objeto vazio — o binário do
  FastReport não é extraído; reaponte a imagem no ReportsHowie.
- Fontes: só nome/tamanho/estilo/cor (sem kerning, sub/superscript, etc.).
- Estilos, `Highlight` condicional, `TfrxCrossView` (tabela dinâmica),
  cabeçalhos/rodapés de coluna e bandas filhas complexas: não cobertos.
- Expressões com funções do FastReport não têm equivalente 1:1 — ficam literais.

Contribuições bem-vindas: ampliar o mapa de objetos, extrair imagens embutidas,
e traduzir mais funções de expressão.
