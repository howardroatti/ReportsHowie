# Changelog

Todas as mudanças notáveis deste projeto são documentadas aqui.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o projeto adota o [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Unreleased]

### Melhorado (designer — descoberta de datasets em DataModules)
- O painel de campos do designer agora encontra datasets por **três caminhos**, com dedup:
  (1) `TDataSet` no próprio form/DM sendo desenhado; (2) seguindo os **`TDataSource`** do
  form (resolve datasets em outro `DataModule`); e (3) **enumerando todos os DataModules/
  forms abertos no IDE via ToolsAPI** — pega datasets de um `DataModule` mesmo **sem**
  nenhum `TDataSource` no form. Antes só listava (1). Requer os módulos **abertos no IDE**;
  falhas de ToolsAPI são silenciadas (segue com o que encontrou).

## [0.1.0] - 2026-07-02

Primeiro lançamento público. Componente **TrhReport** instalável (RT+DT), com
modelo/persistência `.rhr`, engine de expressões, pipeline de dados com grupos
aninhados e agregados, **preview VCL embutível** (`TrhPreviewControl`), designer
visual em design-time, exportadores puro-Pascal **PDF/HTML/XLSX/DOCX**, envio por
e-mail (SMTP/Indy), objetos visuais (marca d'água, códigos de barras/QR, gráficos)
e o ecossistema de IA (`rhtool` CLI + JSON Schema + servidor MCP).

### Adicionado (Fase 5 — designer: refazer, reordenar bandas e click-to-place)
- **Refazer (Ctrl+Y)**: o designer agora mantém pilha de refazer além do desfazer (Ctrl+Z). Uma nova
  edição invalida o ramo de refazer; ambos limitados a 50 passos. `TrhDesignSurface.Redo`/`CanRedo`.
- **Reordenar bandas**: botões ▲/▼ no grupo *Banda* (e `MoveBand(Delta)`) sobem/descem a banda
  selecionada, mudando a ordem de renderização — via `TrhBandList.Move` (herdado de `TObjectList`).
- **Click-to-place**: os botões de *Inserir* (Texto/Imagem/Linha/Forma/Barras/Gráfico) agora **armam a
  ferramenta** — o próximo clique na superfície posiciona o objeto onde o usuário clicou (cursor de mira;
  Esc ou clique direito cancela), em vez de cair sempre numa posição fixa. `TrhDesignSurface.ArmTool`.

### Adicionado (Objetos visuais — marca d'água, códigos de barras/QR e gráficos)
- **Marca d'água** (`rh.Watermark`, `TrhReport.Watermark`): texto diagonal repetido ao fundo de cada
  página (fonte/ângulo configuráveis; padrão Arial 72 bold cinza a 45°). Renderizada por baixo das bandas
  na tela, no PDF (matriz de texto) e no HTML (`transform:rotate`).
- **Códigos de barras 1D** (`TrhBarcodeObject`, `rh.Barcode`): **Code128** (Set B) e **Code39**, com texto
  legível opcional. Encoders puro-Pascal validados contra `python-barcode`.
- **QR Code** (`rh.QRCode`): modo byte, correção **M**, versões 1–10 (Reed–Solomon/GF(256), 8 máscaras com
  scoring). Validado byte a byte contra `segno` + leitura no OpenCV. Barras/módulos viram `rhdkRect` na
  display list (coalescidos por linha), compartilhados por preview e todos os exports.
- **Gráficos** (`TrhChartObject`): **barras**, **linhas** e **pizza**, com a série **agregada do dataset da
  banda** (SUM/AVG/COUNT/MIN/MAX por categoria) — escopo geral no Summary, escopo do grupo no GroupFooter.
  Novo primitivo `rhdkPolygon` na display list, com desenho de polígono no VCL (`Polygon`), PDF (path
  `m/l/h` + `f/B/S`) e HTML (SVG `<polygon>`). Título, rótulos de valor, legenda (pizza) e paleta.
- **Designer**: botões *Barras* e *Gráfico* na paleta *Inserir*; a superfície desenha QR/1D reais e um
  esquema ilustrativo do gráfico. **Schema `.rhr`** estendido com `barcodeObject` e `chartObject`.

### Melhorado (12.a/12.b — render com dados via JSON)
- **`rhtool export ... --data <dados.json>`**: alimenta datasets em memória a partir de um JSON
  `{ "NomeDataset": [ {campo: valor}, ... ] }` (nome casa com o `dataSetName` das bandas), então as
  bandas de dados/grupos passam a **produzir linhas** — antes o `export` renderizava só o layout.
  Datasets em memória via `TClientDataSet` (linkado com `MidasLib`, sem DLL); tipos inferidos por campo
  (número→float, booleano→boolean, resto→texto). Exemplo em `demos/pedidos.data.json`.
- **MCP `export_template(template, out_path, fmt, data?)`**: novo parâmetro `data` (mesmo formato),
  repassado ao `rhtool --data`. Verificado ponta a ponta (PDF com dados ~3x maior que só o layout).

### Adicionado (Fase 12.b — Servidor MCP em Python)
- **`tools/mcp/server.py`**: servidor **MCP** (Model Context Protocol) que permite a LLMs (Claude/etc.)
  criar, validar e renderizar relatórios `.rhr`. Tools: `get_schema`, `list_functions` (funções/agregados/
  pseudo-vars do motor de expressões), `validate_template` (via JSON Schema), `info_template` e
  `export_template` (pdf/html/xlsx/docx). Expõe o schema como recurso `schema://reportshowie`.
- **Adaptador fino:** reusa o JSON Schema (12.a) e o `rhtool` CLI (12.a) — o núcleo em Pascal não muda.
  Lógica de núcleo isolada em funções testáveis; verificada de ponta a ponta contra o `rhtool` real
  (validação positiva/negativa, `info` e `export` de PDF) e com *smoke test* do servidor FastMCP.
- Instruções para conectar ao **Claude Code** e **Claude Desktop** no `tools/mcp/README.md`.

### Adicionado (Fase 12.a — `rhtool` CLI + JSON Schema do `.rhr`)
- **JSON Schema** (`schema/reportshowie.schema.json`, draft-07): contrato completo do formato `.rhr`
  (páginas, bandas, objetos text/image/line/shape, frame, font; enums de `bandType`/`hAlign`/`vAlign`/
  `orientation`/`kind`; `oneOf` por tipo de objeto e `additionalProperties:false`). Valida/gera templates
  em qualquer linguagem (ajv, `jsonschema`) e serve de contrato para LLMs (base do MCP). Verificado contra
  os `.rhr` de exemplo e com casos negativos.
- **`rhtool` CLI** (`tools/rhtool/rhtool.dpr`): app de console que **valida**, **inspeciona** (`info`) e
  **exporta** (`.pdf/.html/.xlsx/.docx`) templates `.rhr` sem abrir o IDE — base *headless* para o servidor
  MCP (12.b). Linka os fontes `rh.*` estaticamente; exit codes 0/1/2.

### Adicionado (Fase 9 — Envio por e-mail / SMTP)
- **`rh.Email` (`TrhMailer`)**: `SendReport(Report, Formato, Destinatários, Assunto, Corpo, Settings, [NomeAnexo])`
  renderiza o relatório (PDF/HTML/XLSX/DOCX) a partir da mesma display list dos exportadores, grava num
  arquivo temporário e o anexa a uma mensagem SMTP (Indy `TIdSMTP`/`TIdMessage`), apagando o temporário
  ao final. Novos tipos `TrhReportFormat`, `TrhSMTPSecurity` (`rssNone`/`rssStartTLS`/`rssImplicitTLS`) e
  o record `TrhSMTPSettings` (com `Create` de conveniência) para host/porta/credenciais/remetente.
- **TLS desacoplado (mantém "zero dependências externas"):** a unit **não** referencia nenhuma biblioteca
  SSL. Para transporte seguro, a aplicação atribui o IOHandler que preferir (OpenSSL **ou** SChannel) via
  o evento `OnConfigureSMTP`; se TLS for pedido sem IOHandler, `SendReport` lança `ErhEmail` explicativo.
  `rh.Email` adicionado ao pacote runtime `ReportsHowieRT` (que já requeria Indy).
- **Exemplo** no app de testes (`Button4` "Enviar por e-mail (PDF)") + **sink SMTP** em Python
  (`aiosmtpd`) para captura local; documentado no manual (seção 13.1, MD e HTML).

### Adicionado (Fase 5.3 — Árvore de estrutura no designer)
- **Outline de estrutura** na coluna direita do designer (acima do inspetor, com *splitter*): um
  `TTreeView` que reflete **Página → Bandas → Objetos** (o rótulo do objeto mostra o tipo e, para
  textos, a expressão efetiva `DisplayExpression`/`[campo]`).
- **Seleção sincronizada nos dois sentidos**, com guarda anti-recursão (`FSyncing`): clicar num nó
  seleciona a banda/objeto na superfície e atualiza o inspetor; selecionar na tela realça o nó
  correspondente. Novo método público `TrhDesignSurface.SelectInOutline(Band, Obj)` (mantém o
  `FSelBand` coerente, que o setter `Selected` sozinho não ajustava).
- **Rebuild inteligente:** a árvore só é reconstruída quando a *estrutura* muda (comparação por
  assinatura), evitando *flicker* ao arrastar/redimensionar objetos (o `OnModified` dispara no
  `MouseMove`). Reconstrói ao abrir/carregar `.rhr`, inserir/excluir objeto ou banda, no drag-to-bind
  e ao editar propriedades (para refrescar os rótulos).

### Adicionado (Fase 5.2b — Drag-to-bind no designer)
- **Arrastar campo → objeto** na superfície do designer: a árvore de dados (`FDataTree`) passou a
  `DragMode = dmAutomatic`; a superfície (`TrhDesignSurface`) recebe `OnDragOver`/`OnDragDrop` e expõe
  `DropField(X, Y, Dataset, Campo)` — se o campo cai **sobre um texto**, seta o `DataField` dele; se cai
  em **área vazia** de uma banda, cria um texto vinculado na posição do drop (e ajusta o `DataSetName`
  da banda). Duplo-clique no campo continua inserindo (comportamento da 5.1).
- **Indicador visual de vínculo**: objetos com `DataField` preenchido ganham um triângulo azul no canto
  superior esquerdo; no design-time o texto mostra a expressão efetiva (`DisplayExpression` → `[campo]`).
  A propriedade `DataField` já aparece no inspetor (RTTI).
- **Botão "Ajuda"** no ribbon (grupo Ver): abre a documentação — tenta o `docs/index.html` local
  (procurando a partir do executável) e cai na versão online em HTML (GitHub Pages:
  `https://howardroatti.github.io/ReportsHowie/`) se não achar. Manual publicado via Pages (branch `main`, `/docs`).

### Adicionado (Fase 4 — Grupos aninhados / multi-nível)
- **Agrupamento em vários níveis** no pipeline de dados (`rh.Data.Pipeline`): antes só havia
  1 nível de grupo; agora `Classify` coleta **todos** os `GroupHeader`/`GroupFooter` (a ordem dos
  cabeçalhos define o aninhamento: topo = mais externo) e casa header↔footer pela `GroupExpression`.
  `RunData` passou a rodar o algoritmo clássico de *banded report*: a cada quebra fecha os rodapés do
  nível **interno→externo** (rótulos lidos na última linha do grupo) e abre os cabeçalhos
  **externo→interno**. Ex.: **Cliente › Categoria › produtos › Subtotal categoria › Total cliente**.
  Os agregados já eram multi-escopo (o contexto filtra por N `GroupFilter` em AND), então
  `SUM`/`COUNT`/etc. somam corretamente o escopo de cada nível (ex.: total da categoria **dentro** do
  cliente). Requisito: dataset **ordenado na ordem dos grupos** (ex.: `ORDER BY cliente, categoria`).
  Retrocompatível: relatórios de 1 nível (ou sem grupos) continuam idênticos.

### Adicionado (Documentação)
- **Manual de uso** (`docs/MANUAL.md`): guia completo com dezenas de exemplos — conceitos, instalação,
  bandas, objetos (texto/imagem/linha/forma), fonte/cores/moldura, expressões e funções, data binding
  híbrido, agrupamento/agregados, master-detail, conexão a banco (FireDAC/PostgreSQL), preview embutida
  vs. externa, exportação (HTML/PDF/XLSX/DOCX), persistência, designer, impressão, receitas rápidas e
  solução de problemas. Linkado no README.

### Adicionado (Fase 5.2a — Data binding híbrido)
- **`DataField` no `TrhTextObject`:** bind direto a um campo do dataset da banda (modo simples, estilo
  DB-aware), convivendo com as ilhas `[expr]` do `Text`. Quando preenchido, tem precedência e compila
  para a mesma ilha `[campo]` (motor único). Novo `DisplayExpression` centraliza a resolução; o render
  passa a usá-lo. Persistido em JSON (`dataField`) e copiado no `Assign`. Retrocompatível.

### Adicionado (Fase 5.1 — Designer: Arquivo + preview embutida)
- **Abrir/Salvar `.rhr` no designer:** novo grupo **"Arquivo"** no ribbon (`Abrir`/`Salvar`) usando
  `TrhReport.LoadFromFile`/`SaveToFile`, com refresh da superfície e undo. Permite abrir no design-time
  um template montado em código (salvo em `.rhr`).
- **`TrhPreviewControl` (`rh.Preview.Control`):** controle de preview **embutível** (não modal) que
  desenha um `TrhRenderedDocument` inline em qualquer form/painel, com navegação de páginas e zoom,
  reutilizando o mesmo `TrhVCLRenderer` (WYSIWYG). Complementa a janela `TrhPreviewForm`.

### Adicionado (Fase 5 — Designer visual em design-time)
- **5.1 — Vínculo de dados no designer:** o component editor varre os `TDataSet` do form/data module
  (nomes + campos, via `Fields`/`FieldDefs`) e os entrega ao designer. Novo painel **"Dados"** (árvore
  datasets→campos) à esquerda; **duplo-clique** (ou botão) num campo insere um texto `[Campo]` na banda
  selecionada e já define o `DataSetName` dela. `rh.Design.Data` (`TrhDesignData`) é o portador reutilizável
  no designer runtime (Fase 10). Mantém a filosofia DB-agnóstica: o binding de dados vivo continua sendo
  `TrhReport.SetDataSet` em runtime.
- **5c — Seleção múltipla, guias, alinhar/distribuir, undo, imagens e toolbar ribbon:**
  - Seleção múltipla (Shift+clique alterna; *marquee* por área na banda); arrastar move o grupo.
  - **Guias de alinhamento** vermelhas ao mover (bordas/centros vs. irmãos) com *snap*.
  - **Alinhar** (esq./centro-H/dir./topo/centro-V/base) e **distribuir** (H/V).
  - **Desfazer (Ctrl+Z)** com histórico de 50 passos (snapshots JSON) cobrindo mover, redimensionar,
    inserir/excluir objeto e banda, alinhar/distribuir, editar texto, carregar imagem e edições do inspetor.
  - **Carregar imagem** real: duplo-clique num objeto imagem ou botão "Carregar imagem..." no inspetor
    (BMP/JPG/PNG), serializada em base64 no template.
  - **Toolbar estilo ribbon**: grupos (Zoom/Inserir/Banda/Alinhar/Ver) com botões *flat*, rótulo de
    seção, divisórias e tooltips; altura fixa com rolagem horizontal quando a janela estreita.
- **5b — Inspetor de propriedades (RTTI):** `rh.Design.Inspector` (`TrhInspector`, VCL puro).
  Lista as propriedades publicadas do objeto/banda selecionado e edita conforme o tipo: string,
  inteiro, geometria em **mm** (Left/Top/Width/Height), enumeração e booleano (combo), cor
  (diálogo) e fonte (diálogo). Painel acoplado à direita do designer, com splitter; sincroniza
  com a seleção e reflete mudanças ao arrastar/redimensionar na surface.

### Adicionado (Fase 5 — Designer visual em design-time, incremento 5a)
- `rh.Design.Surface`: `TrhDesignSurface` (`TCustomControl` puro VCL, **livre de DesignIntf** —
  reutilizável no designer runtime da Fase 10). Editor por bandas: faixas empilhadas com rótulo
  no gutter, grade/snap, seleção de objeto/banda, mover e redimensionar por 8 alças, resize da
  altura da banda arrastando a borda inferior, e edição do texto por duplo-clique. Coordenadas
  idênticas às do motor de render (Left/Top relativos à área de conteúdo da banda).
- `rh.Design.Designer.Form`: `TrhDesignerForm` (construído em código, sem DesignIntf) com toolbar
  (zoom, inserir Texto/Imagem/Linha/Forma, excluir, inserir/excluir banda, Preview), área rolável
  e OK/Cancelar. Edita in-place e restaura o snapshot JSON ao cancelar.
- `rh.Design.ComponentEditor`: `TrhReportComponentEditor` — duplo-clique/verbo abre o designer e,
  ao confirmar, chama `Designer.Modified` (persiste o template no DFM). `rh.Reg` registra o editor.

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

[Unreleased]: https://github.com/howardroatti/ReportsHowie/compare/v0.1.0...main
[0.1.0]: https://github.com/howardroatti/ReportsHowie/releases/tag/v0.1.0
