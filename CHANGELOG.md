# Changelog

Todas as mudanças notáveis deste projeto são documentadas aqui.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o projeto adota o [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Unreleased]

### Adicionado (Fase 8 — Export XLSX e DOCX / OOXML)
- `rh.OOXML.Zip`: empacotador OOXML minimo sobre `System.Zip` — acumula *parts* XML/binárias e
  grava o `.xlsx`/`.docx` como ZIP (reutilizável entre XLSX e DOCX). Helper `XmlEscape`.
- `rh.Export.XLSX`: `TrhXlsxExporter` gera SpreadsheetML puro-Pascal. Como a display list é
  posicional, reconstrói uma **grade tabular** agrupando os textos por posição (linhas por `Top`
  dentro da página, colunas por `Left` global). Cada texto vira célula `inlineStr` já formatada,
  com fonte/negrito/itálico/cor e alinhamento (styles.xml com fontes e `cellXfs` deduplicados),
  larguras de coluna e alturas de linha derivadas das dimensões dos objetos.
- `rh.Export.DOCX`: `TrhDocxExporter` gera WordprocessingML puro-Pascal. Documento de **fluxo**:
  cada objeto de texto vira um parágrafo (ordenado por página/`Top`/`Left`) com fonte, estilo,
  cor, alinhamento (`jc`), recuo esquerdo a partir do `Left` e `sectPr` com o tamanho da página.

### Adicionado (Fase 7 — Export PDF nativo)
- `rh.Export.PDF`: `TrhPdfExporter` escreve um **PDF 1.4 puro-Pascal** (sem dependências) a
  partir do `TrhRenderedDocument`: objetos indiretos, tabela `xref` com offsets de bytes reais,
  `trailer` (`/Root`+`/Size`) e árvore `/Catalog → /Pages → /Page`.
- Content stream por página mapeando a display list para operadores PDF: texto (`BT/Tf/Tm/Tj/ET`),
  retângulos/linhas (`re`/`m`/`l`/`S`/`B`) e elipses via 4 curvas de Bézier; cores (`rg`/`RG`);
  eixo Y invertido (origem PDF é o canto inferior-esquerdo).
- Fontes: as **Type1 padrão** da família Helvetica (normal/bold/italic/bold-italic, `WinAnsiEncoding`)
  — sem embutir arquivo de fonte.
- Alinhamento horizontal (esq./centro/dir.) calculado por métricas GDI; múltiplas linhas por objeto.
- Imagens embutidas como XObject `/DCTDecode` (JPEG).

### Adicionado (Fase 6 — Export HTML)
- `rh.Export.HTML`: `TrhHtmlExporter` reproduz o `TrhRenderedDocument` como páginas HTML com
  elementos absolutamente posicionados em mm (WYSIWYG com o preview). Imagens em data-URI base64,
  molduras/formas/linhas em CSS, e `@media print` com quebra de página.

### Adicionado (Fase 4 — Pipeline de dados)
- `rh.Data.Pipeline`: percorre um `TDataSet` genérico emitindo a banda de dados por registro.
- Grupo (header/footer) com quebra por `GroupExpression`; cabeçalho/rodapé de página; sumário.
- Agregações reais `SUM`/`AVG`/`COUNT`/`MIN`/`MAX` — por grupo e geral — via re-varredura do
  dataset com filtro de grupo e bookmark (sem acumuladores).
- `TrhReport.SetDataSet`/`FindDataSet` (binding runtime nome→`TDataSet`) e helper `ShowDataPreview`.
- Total de páginas correto (`[TOTALPAGES]`) via duas passagens.
- Rodapé de grupo posiciona no último registro do grupo (rótulos `[Campo]` corretos).
- `TrhRenderEngine.EmitBand` exposto para reuso pelo pipeline.

### Adicionado (Fase 3 — Motor de expressões/fórmulas)
- `rh.Expr.Lexer`: tokenizador (campos `[Nome]`, strings, números, operadores, `AND/OR/NOT/MOD`).
- `rh.Expr.Nodes`: nós da AST + `IrhEvalContext` + avaliador (Variant); nós de agregação delegam ao contexto.
- `rh.Expr.Functions`: registro extensível de funções (`UPPER`, `LOWER`, `TRIM`, `LEN`, `COPY`, `POS`,
  `IIF`, `COALESCE`, `ROUND`, `TRUNC`, `INT`, `ABS`, `FORMATFLOAT`, `FORMATDATETIME`, `DATETOSTR`, `STR`, `NOW`).
- `rh.Expr.Parser`: parser descendente-recursivo com precedência (OR/AND/comparação/±/×÷/unário/primário).
- `rh.Expr`: fachada `TrhExpression`, `rhEvalText` (ilhas `[expr]` com colchetes balanceados), `TrhDictContext`.
- Integração no render: `BuildDocument`/`ShowPreview` aceitam `IrhEvalContext` opcional e avaliam os textos.
- Agregações (`SUM`/`AVG`/`COUNT`/`MIN`/`MAX`) já parseadas; avaliação real na Fase 4.

### Adicionado (Fase 2 — Motor de renderização + preview VCL)
- `rh.Render.Intf`: display list (`TrhRenderedDocument`/`TrhRenderedPage`/`TrhDrawOp`) —
  formato intermediário paginado que preview e todos os exports vão compartilhar.
- `rh.Render.Engine`: `TrhRenderEngine.BuildDocument` — percorre páginas/bandas/objetos e
  produz a display list (layout estático do template, com quebra de página por transbordo).
- `rh.Render.VCLCanvas`: `TrhVCLRenderer` — desenha uma página num `TCanvas` (tela/designer)
  com escala/zoom, e imprime o documento via `TPrinter`.
- `rh.Preview.Form`: janela de preview (construída em código) com zoom, navegação de páginas,
  impressão e o class helper `TrhReport.ShowPreview`.

### Adicionado (Fase 1 — Modelo de objetos + persistência)
- Modelo completo: `TrhReport` (dono das páginas) → `TrhPage` → `TrhBand` → `TrhReportObject`
  (`TrhTextObject`, `TrhImageObject`, `TrhLineObject`, `TrhShapeObject`).
- Enums do modelo + conversores string (`rh.Model.Types`): tipo de banda, alinhamento, shape, orientação, molduras.
- Serialização JSON canônica: arquivo `.rhr` (`SaveToFile`/`LoadFromFile`/`ToJSONString`) e streaming DFM
  via `DefineProperties` (blob `ReportData`) — o mesmo JSON nos dois envelopes.
- Coleção polimórfica de objetos com fábrica (`CreateReportObject`) e `AddNew<T>`.
- Imagens serializadas em base64; fontes/cores em `rh.Serialization`.
- Round-trip validado no Delphi 12.1 (montar em código → salvar → recarregar).

### Adicionado (Fase 0 — Esqueleto + estrutura open-source)
- Estrutura de pastas do projeto (`source/`, `designtime/`, `packages/`, `tests/`, `demos/`, `docs/`).
- Pacotes Delphi com o split obrigatório **runtime** (`ReportsHowieRT`) e **design-time** (`ReportsHowieDT`), mais o grupo `ReportsHowieGroup.groupproj`.
- Units core: `rh.Types` (unidade de relatório 0,1 mm + conversores mm/px/pt/twips/EMU), `rh.Consts`, `rh.Classes`.
- Componente `TrhReport` (esqueleto instalável) e registro na paleta **ReportsHowie** (`rh.Reg`).
- Estrutura open-source: `LICENSE` (LGPL-3.0), `COPYING.GPL`, `README`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, `.gitignore`/`.gitattributes` para Delphi, templates de issue/PR e workflow de CI (`.github/workflows/ci.yml`).

[Unreleased]: https://github.com/howardroatti/ReportsHowie/commits/main
