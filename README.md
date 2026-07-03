# ReportsHowie

> Gerador de relatórios **banded** open-source para Delphi (VCL) — uma alternativa **livre e gratuita** ao FastReport / QuickReport / Rave.
>
> *A free & open-source banded report generator component for Delphi (VCL).*

[![License: LGPL v3](https://img.shields.io/badge/License-LGPL_v3-blue.svg)](./LICENSE)
[![Delphi](https://img.shields.io/badge/Delphi-12.1%20Athens%2B-E62431.svg)](https://www.embarcadero.com/products/delphi)
[![Release](https://img.shields.io/github/v/release/howardroatti/ReportsHowie?sort=semver&color=green)](https://github.com/howardroatti/ReportsHowie/releases)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)

---

## O que é

**ReportsHowie** é um componente para o Delphi (a partir do **Community 12.1 Athens**) que permite:

- **Em tempo de desenvolvimento (design-time):** um designer visual onde você posiciona os campos livremente, com ancoragem, alinhamento e *snap-to-grid* fáceis; insere imagens; conecta a bancos de dados; cria bandas, tabelas, fórmulas e agregações.
- **Em tempo de execução (runtime):** *preview* e exportação para **PDF, HTML, DOCX e XLSX**.
- **Envio por e-mail** do relatório gerado.

### Princípios de projeto

- **VCL, Windows-nativo** — a base clássica e mais confortável para designers de relatório.
- **Zero dependências externas** — os exportadores (PDF, OOXML, HTML) são escritos em **Pascal puro**, usando apenas o que já vem com o Delphi (RTL, `System.Zip`, `System.ZLib`, GDI/`Vcl.Graphics`, Indy para SMTP).
- **`TDataSet` genérico** — funciona com FireDAC, ADO, dbExpress, ClientDataSet… sem acoplar a nenhum driver.
- **Uma engine de renderização compartilhada** — o *preview* na tela e todos os exports partem exatamente da mesma display list, garantindo WYSIWYG.
- **Pronto para IA (*AI-native*)** — o template é um **JSON (`.rhr`) limpo e serializável**, pensado para ser gerado e editado por LLMs. Um futuro **servidor MCP** (+ CLI `rhtool`) permitirá que assistentes como Claude, ChatGPT e Gemini criem, validem e renderizem relatórios diretamente, reutilizando o próprio motor de expressões e os exportadores. Ver [roadmap](#roadmap) (Fase 12).

## Status

✅ **v0.1.0 — primeiro lançamento público.** O componente é usável: montar relatórios
por código ou pelo designer, ligar a `TDataSet`, pré-visualizar (janela **ou** controle
embutível `TrhPreviewControl`) e exportar para **PDF/HTML/XLSX/DOCX** + e-mail. Veja o
[roadmap](#roadmap), o [CHANGELOG](./CHANGELOG.md) e as [releases](https://github.com/howardroatti/ReportsHowie/releases).

## Instalação

Requisitos: **RAD Studio / Delphi 12.1 Athens** (ou versão compatível) com a personalidade VCL.

**Opção A — código-fonte (recomendada para desenvolvimento):**

1. Clone o repositório:
   ```sh
   git clone https://github.com/howardroatti/ReportsHowie.git
   ```
2. Abra `packages/ReportsHowieGroup.groupproj` no IDE.
3. **Build** o `ReportsHowieRT` (runtime) e depois **Install** o `ReportsHowieDT` (design-time).
4. O componente **TrhReport** aparecerá na paleta na página **ReportsHowie**.

**Opção B — BPLs pré-compilados** (anexos de cada [release](https://github.com/howardroatti/ReportsHowie/releases)):
baixe o `.zip` da sua versão do Delphi, instale o `ReportsHowieDT<sufixo>.bpl` em
**Components → Install Packages**, e redistribua o `ReportsHowieRT<sufixo>.bpl` com a sua app.

> Compilação por linha de comando (usada na CI com RAD Studio completo):
> ```sh
> msbuild packages/ReportsHowieGroup.groupproj /t:Build /p:Config=Release /p:Platform=Win32
> ```
> Para publicar uma nova versão, veja **[RELEASING.md](./RELEASING.md)**.

## Getting Started: primeiro relatório com dados

```pascal
uses
  Data.DB,
  rh.Types, rh.Report, rh.Page, rh.Bands, rh.Objects, rh.Model.Types,
  rh.Data.Pipeline, rh.Preview.Form, rh.Export.PDF, rh.Render.Intf;

procedure EmitirRelatorioVendas(DS: TDataSet);
var
  Rep: TrhReport; Page: TrhPage; Band: TrhBand;
  Txt: TrhTextObject; Doc: TrhRenderedDocument;
begin
  Rep := TrhReport.Create(nil);
  try
    Rep.Title := 'Vendas';
    Rep.SetDataSet('Vendas', DS);            // DS deve estar aberto
    Page := Rep.EnsurePage;
    Band := Page.Bands.AddBand(rhbtMasterData);
    Band.DataSetName := 'Vendas';
    Band.Height := MMToUnits(8);
    Txt := Band.Objects.AddNew<TrhTextObject>;
    Txt.Text := '[cliente] - [valor]';       // ilhas avaliadas no dataset
    Txt.Width := Page.ContentWidth;
    Txt.Height := Band.Height;
    Rep.ShowDataPreview;
    Doc := TrhDataPipeline.BuildDocument(Rep);
    try
      TrhPdfExporter.ExportToFile(Doc, 'saida.pdf');
    finally
      Doc.Free;
    end;
  finally
    Rep.Free;
  end;
end;
```

Se você já soltou um `TrhReport` no form, use o componente existente no lugar de
`Rep` e mantenha o mesmo fluxo: `SetDataSet`, banda `masterData`,
`ShowDataPreview` e exportação a partir de `TrhDataPipeline.BuildDocument`.

## Documentação

- 📘 **[Manual de uso (online)](https://howardroatti.github.io/ReportsHowie/)** — versão HTML navegável com índice lateral, busca e prints (GitHub Pages). Também no repo: **[docs/index.html](./docs/index.html)** e em Markdown **[MANUAL.md](./docs/MANUAL.md)**.
- Cobre: bandas, objetos, expressões, data binding híbrido, agrupamento/agregados e **grupos aninhados**, banco de dados, preview, exportação, designer e receitas prontas.
- 🏗️ [Arquitetura](./docs/ARCHITECTURE.md) — visão interna do componente.
- 🧩 [JSON Schema do `.rhr`](./schema/reportshowie.schema.json) — contrato do formato (draft-07) para validar/gerar templates em qualquer linguagem e como base para LLMs.
- ⌨️ [`rhtool` CLI](./tools/rhtool/) — validar, inspecionar e exportar `.rhr` sem abrir o IDE (base *headless* do MCP).
- 🤖 [Servidor MCP](./tools/mcp/) — conecte o **Claude** para criar/validar/renderizar relatórios (reusa o schema + `rhtool`).

## Roadmap

| Fase | Entrega | Status |
|-----:|---------|:------:|
| 0 | Esqueleto dos pacotes (RT+DT) + estrutura open-source | ✅ |
| 1 | Modelo de objetos + persistência JSON (`.rhr`) e DFM | ✅ |
| 2 | Abstração de render + preview VCL | ✅ |
| 3 | Engine de expressões/fórmulas | ✅ |
| 4 | Pipeline de dados (`TDataSet`, grupos, agregados) | ✅ |
| 4.1 | **Grupos aninhados** (multi-nível: Cliente › Categoria › … com subtotais por nível) | ✅ |
| 5 | Designer visual em design-time (selecionar/mover/redimensionar, inspetor, guias, alinhar, undo, imagens) | ✅ |
| 5.1 | Vínculo de dados no designer (painel de campos, inserir campo, `DataSetName` por lista) + Abrir/Salvar `.rhr` no designer + preview embutida (`TrhPreviewControl`) | ✅ |
| 5.2a | **Data binding híbrido**: propriedade `DataField` no texto (bind simples estilo DB-aware) além das ilhas `[expr]` | ✅ |
| 5.2b | Drag-to-bind no designer (arrastar campo → objeto) + indicador visual de campo vinculado | ✅ |
| 5.3 | **Árvore de estrutura** (página→banda→objeto, seleção sincronizada) | ✅ |
| 6 | Export **HTML** | ✅ |
| 7 | Export **PDF** | ✅ |
| 8 | Export **XLSX** e **DOCX** (OOXML) | ✅ |
| 9 | Envio por **e-mail** (SMTP via Indy; TLS plugável OpenSSL/SChannel) | ✅ |
| 10 | Designer *runtime* + release público multi-versão (**v0.1.0**) | 🚧 |
| 11 | Export **ODT** / **ODS** (OpenDocument) — *opcional* | ⬜ |
| 12.a | **`rhtool` CLI** (validate/info/export por linha de comando) + **JSON Schema** do `.rhr` | ✅ |
| 12.b | **Servidor MCP** (Python; tools: schema, funções, validar, info, exportar template) | ✅ |
| 12.c | Adaptadores de IA: **ChatGPT** (Actions/OpenAPI) e **Gemini** (function declarations) | ⬜ |

## Como contribuir

Contribuições são muito bem-vindas! 🎉 Este projeto nasceu para dar à comunidade Delphi um gerador de relatórios gratuito. Leia o [CONTRIBUTING.md](./CONTRIBUTING.md) e o [Código de Conduta](./CODE_OF_CONDUCT.md).

### Bons primeiros issues

Novo por aqui? Estes são pequenos, bem delimitados e ótimos para começar (cada um traz contexto, tarefa e ponteiros de arquivo):

- [#1 — Expressões: funções de string `LEFT`/`RIGHT`/`MID`/`POS`/`REPLACE`](https://github.com/howardroatti/ReportsHowie/issues/1)
- [#2 — Demos: novos exemplos (fatura, matricial, mala direta)](https://github.com/howardroatti/ReportsHowie/issues/2)
- [#3 — Designer: restringir a descoberta ToolsAPI a DataModules](https://github.com/howardroatti/ReportsHowie/issues/3)
- [#4 — Docs: seção *Getting Started* no README](https://github.com/howardroatti/ReportsHowie/issues/4)

Veja também os issues marcados como [`good first issue`](https://github.com/howardroatti/ReportsHowie/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) e [`help wanted`](https://github.com/howardroatti/ReportsHowie/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22).

## Licença

Distribuído sob a **GNU LGPL-3.0** — veja [LICENSE](./LICENSE) (e [COPYING.GPL](./COPYING.GPL), incorporada por referência).

A LGPL-3.0 permite usar o ReportsHowie em aplicações **comerciais e de código fechado** quando distribuído como **pacote/BPL** (linkagem dinâmica). Se você **linkar estaticamente** as units no seu executável, precisa dar aos usuários finais o direito de re-linkar contra uma versão modificada do componente (ex.: fornecendo os objetos/`.dcu` ou permitindo recompilação). Melhorias feitas **no próprio ReportsHowie** devem ser disponibilizadas sob a LGPL.

---

<sub>ReportsHowie © 2026 Howard Roatti e contribuidores.</sub>
