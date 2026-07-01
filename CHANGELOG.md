# Changelog

Todas as mudanças notáveis deste projeto são documentadas aqui.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o projeto adota o [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Unreleased]

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
