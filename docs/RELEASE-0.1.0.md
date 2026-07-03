# ReportsHowie v0.1.0

> Primeiro lançamento público do **ReportsHowie** — gerador de relatórios *banded*
> open-source (LGPL-3.0) para Delphi VCL. Uma alternativa **livre e gratuita** ao
> FastReport / QuickReport / Rave.

Requisitos: **RAD Studio / Delphi 12.1 Athens** (personalidade VCL). Zero
dependências externas — os exportadores são escritos em Pascal puro.

---

## Destaques

- **Componente `TrhReport`** — solte no form, monte por código ou pelo designer.
- **Modelo + persistência `.rhr`** — template em JSON limpo (round-trip DFM e arquivo).
- **Engine de expressões** — ilhas `[expr]`, funções (`IIF/FORMAT/UPPER/ROUND/…`),
  agregados (`SUM/AVG/COUNT/MIN/MAX`) e pseudo-vars (`PAGE`/`TOTALPAGES`/`DATE`/…).
- **Pipeline de dados** sobre `TDataSet` genérico (FireDAC/ADO/dbExpress/CDS) —
  master-detail, **grupos aninhados** com subtotais por nível e total de páginas.
- **Preview VCL** — janela (`TrhPreviewForm`) **e controle embutível**
  (`TrhPreviewControl`) para colocar a pré-visualização direto no seu form, com
  zoom/navegação. Preview, designer e todos os exports partem da **mesma display
  list** → WYSIWYG real.
- **Designer visual (design-time)** — mover/redimensionar (8 alças), *snap-to-grid*,
  guias inteligentes, alinhar/distribuir, inspetor RTTI, árvore de estrutura,
  **desfazer/refazer**, **reordenar bandas**, **click-to-place**, *drag-to-bind* de
  campos e preview embutida.
- **Exportadores puro-Pascal** — **PDF** (fontes padrão, imagens), **HTML**,
  **XLSX** e **DOCX** (OOXML via `System.Zip`).
- **Envio por e-mail** — `TrhMailer` (SMTP via Indy; TLS plugável OpenSSL/SChannel).
- **Objetos visuais** — **marca d'água**, **códigos de barras** (Code128/Code39),
  **QR Code** e **gráficos** (barras/linha/pizza com série agregada do dataset).
- **Ecossistema de IA** — `rhtool` CLI (validate/info/export *headless*),
  **JSON Schema** (draft-07) do `.rhr` e **servidor MCP** (Python) para Claude
  criar/validar/renderizar relatórios.

Veja o [CHANGELOG](../CHANGELOG.md#010---2026-07-03) para a lista completa.

## Instalação

**Opção A — via código-fonte (recomendada para desenvolvimento):**

1. `git clone https://github.com/howardroatti/ReportsHowie.git`
2. Abra `packages/ReportsHowieGroup.groupproj`.
3. **Build** o `ReportsHowieRT` e depois **Install** o `ReportsHowieDT`.
4. O componente **TrhReport** aparece na paleta **ReportsHowie**.

**Opção B — via BPLs pré-compilados (anexos deste release):**

1. Baixe o `.zip` da sua versão do Delphi (ex.: `ReportsHowie-0.1.0-Delphi12.zip`).
2. Copie os `.bpl` para uma pasta no `PATH` (ou `...\Public Documents\Embarcadero\Studio\<ver>\Bpl`).
3. No IDE: **Components → Install Packages → Add** → selecione `ReportsHowieDT<sufixo>.bpl`.
4. Para redistribuir sua app: entregue junto o `ReportsHowieRT<sufixo>.bpl`
   (linkagem dinâmica — ver nota LGPL no README).

## Conteúdo dos anexos (por versão do Delphi)

| Arquivo | Descrição |
|---|---|
| `ReportsHowieRT<sufixo>.bpl` | Runtime (redistribuível com a sua aplicação) |
| `ReportsHowieDT<sufixo>.bpl` | Design-time (instalar no IDE) |
| `*.dcp` | Para linkar/compilar contra os pacotes |

> `<sufixo>` = sufixo `LIBSUFFIX AUTO` da versão (ex.: `290` no Delphi 12 Athens →
> `ReportsHowieRT290.bpl`).

## Licença

**GNU LGPL-3.0.** Uso em apps comerciais/fechados é permitido via **BPL** (linkagem
dinâmica). Linkagem **estática** exige dar ao usuário final o direito de re-linkar.
Melhorias no próprio ReportsHowie são LGPL.

---

🤖 Documentação: [Manual](https://howardroatti.github.io/ReportsHowie/) ·
[Arquitetura](./ARCHITECTURE.md) · [JSON Schema](../schema/reportshowie.schema.json)
