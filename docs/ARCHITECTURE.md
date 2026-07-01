# Arquitetura do ReportsHowie

Este documento resume as decisões de arquitetura. É a referência para quem for contribuir.

## Visão geral

O ReportsHowie separa **modelo** (dados puros e serializáveis), **engine de renderização** (uma única display list paginada) e **saídas** (preview + exportadores). Preview e todos os exports consomem a *mesma* display list, garantindo WYSIWYG.

```
TrhReport (modelo)  ──►  TrhRenderEngine  ──►  TrhRenderedDocument (display list)
                                                    │
                        ┌───────────────┬───────────┼───────────┬───────────┐
                     Preview VCL       HTML         PDF        XLSX/DOCX    (email anexa)
```

## Decisões-chave

- **VCL**, Windows-nativo.
- **Split de pacotes obrigatório:** `ReportsHowieRT` (runtime, redistribuível) × `ReportsHowieDT` (design-time, só no IDE). Nada de `DesignIntf` no runtime.
- **Unidade interna de coordenadas:** *report unit* = **0,1 mm** (inteiro). Conversão apenas nas pontas via `rh.Types` (`MMToPx/MMToPt/MMToTwips/MMToEMU`).
- **Exports em Pascal puro**, sem dependências externas (RTL, `System.Zip`, `System.ZLib`, GDI, Indy).
- **Dados via `TDataSet` genérico** (FireDAC/ADO/dbExpress/CDS).
- **Persistência:** um único serializador canônico (JSON) em dois envelopes — arquivo `.rhr` (runtime) e blob binário no DFM (`DefineProperties`) no design-time.

## Camadas e units

| Camada | Pasta | Units principais |
|--------|-------|------------------|
| Core | `source/core` | `rh.Types`, `rh.Consts`, `rh.Classes` |
| Modelo | `source/model` | `rh.Report`, `rh.Page`, `rh.Bands`, `rh.Objects`, `rh.Collections` |
| Expressões | `source/expr` | `rh.Expr.Lexer/Parser/Nodes/Eval/Functions` |
| Dados | `source/data` | `rh.Data.Pipeline`, `rh.Data.Groups` |
| Render | `source/render` | `rh.Render.Intf`, `rh.Render.Engine`, `rh.Render.VCLCanvas` |
| Export | `source/export/{pdf,ooxml,html}` | `rh.Export.*`, `rh.PDF.*`, `rh.OOXML.*` |
| Preview | `source/preview` | `rh.Preview.Form`, `rh.Preview.Control` |
| E-mail | `source/email` | `rh.Email` |
| Design-time | `designtime` | `rh.Reg`, `rh.Design.*` |

## Roadmap

Ver a tabela de fases no [README](../README.md#roadmap). O plano detalhado que originou este projeto descreve cada fase, o modelo de objetos completo, a engine de expressões (tokenizer → parser → avaliador), o pipeline de dados (master-detail, grupos, agregados em duas fases) e o writer de PDF (objetos/xref/content streams).
