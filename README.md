# ReportsHowie

> Gerador de relatórios **banded** open-source para Delphi (VCL) — uma alternativa **livre e gratuita** ao FastReport / QuickReport / Rave.
>
> *A free & open-source banded report generator component for Delphi (VCL).*

[![License: LGPL v3](https://img.shields.io/badge/License-LGPL_v3-blue.svg)](./LICENSE)
[![Delphi](https://img.shields.io/badge/Delphi-12.1%20Athens%2B-E62431.svg)](https://www.embarcadero.com/products/delphi)
[![Status](https://img.shields.io/badge/status-em%20desenvolvimento-yellow.svg)](#roadmap)
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

🚧 **Em desenvolvimento ativo.** A **Fase 0** (esqueleto instalável dos pacotes + estrutura open-source) está concluída. Veja o [roadmap](#roadmap).

## Instalação (a partir da Fase 0)

Requisitos: **RAD Studio / Delphi 12.1 Athens** (ou versão compatível) com a personalidade VCL.

1. Clone o repositório:
   ```sh
   git clone https://github.com/howardroatti/ReportsHowie.git
   ```
2. Abra `packages/ReportsHowieGroup.groupproj` no IDE.
3. **Build** o `ReportsHowieRT` (runtime) e depois **Install** o `ReportsHowieDT` (design-time).
4. O componente **TrhReport** aparecerá na paleta na página **ReportsHowie**.

> Compilação por linha de comando (usada na CI):
> ```sh
> msbuild packages/ReportsHowieGroup.groupproj /t:Build /p:Config=Release /p:Platform=Win32
> ```

## Exemplo mínimo (API pretendida)

> A API abaixo é o alvo das próximas fases; hoje `TrhReport` é o esqueleto instalável.

```pascal
uses rh.Report;

var
  Rep: TrhReport;
begin
  Rep := TrhReport.Create(nil);
  try
    Rep.LoadFromFile('vendas.rhr');   // template desenhado no designer
    // Rep.DataLinks['Master'].DataSet := qryVendas;  // TDataSet genérico
    Rep.ShowPreview;                  // preview VCL
    Rep.ExportToFile('vendas.pdf');   // PDF / HTML / DOCX / XLSX
    // Rep.SendByEmail(...);          // via Indy SMTP
  finally
    Rep.Free;
  end;
end;
```

## Documentação

- 📘 **[Manual de uso (online)](https://howardroatti.github.io/ReportsHowie/)** — versão HTML navegável com índice lateral, busca e prints (GitHub Pages). Também no repo: **[docs/index.html](./docs/index.html)** e em Markdown **[MANUAL.md](./docs/MANUAL.md)**.
- Cobre: bandas, objetos, expressões, data binding híbrido, agrupamento/agregados e **grupos aninhados**, banco de dados, preview, exportação, designer e receitas prontas.
- 🏗️ [Arquitetura](./docs/ARCHITECTURE.md) — visão interna do componente.
- 🧩 [JSON Schema do `.rhr`](./schema/reportshowie.schema.json) — contrato do formato (draft-07) para validar/gerar templates em qualquer linguagem e como base para LLMs.
- ⌨️ [`rhtool` CLI](./tools/rhtool/) — validar, inspecionar e exportar `.rhr` sem abrir o IDE (base *headless* do MCP).

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
| 10 | Designer *runtime* + release público multi-versão | ⬜ |
| 11 | Export **ODT** / **ODS** (OpenDocument) — *opcional* | ⬜ |
| 12.a | **`rhtool` CLI** (validate/info/export por linha de comando) + **JSON Schema** do `.rhr` | ✅ |
| 12.b | **Servidor MCP** (tools: schema, funções, criar/editar/validar/renderizar template) + manifesto Claude | ⬜ |
| 12.c | Adaptadores de IA: **ChatGPT** (Actions/OpenAPI) e **Gemini** (function declarations) | ⬜ |

## Como contribuir

Contribuições são muito bem-vindas! 🎉 Este projeto nasceu para dar à comunidade Delphi um gerador de relatórios gratuito. Leia o [CONTRIBUTING.md](./CONTRIBUTING.md) e o [Código de Conduta](./CODE_OF_CONDUCT.md).

## Licença

Distribuído sob a **GNU LGPL-3.0** — veja [LICENSE](./LICENSE) (e [COPYING.GPL](./COPYING.GPL), incorporada por referência).

A LGPL-3.0 permite usar o ReportsHowie em aplicações **comerciais e de código fechado** quando distribuído como **pacote/BPL** (linkagem dinâmica). Se você **linkar estaticamente** as units no seu executável, precisa dar aos usuários finais o direito de re-linkar contra uma versão modificada do componente (ex.: fornecendo os objetos/`.dcu` ou permitindo recompilação). Melhorias feitas **no próprio ReportsHowie** devem ser disponibilizadas sob a LGPL.

---

<sub>ReportsHowie © 2026 Howard Roatti e contribuidores.</sub>
