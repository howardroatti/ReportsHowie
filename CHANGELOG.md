# Changelog

Todas as mudanças notáveis deste projeto são documentadas aqui.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o projeto adota o [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Unreleased]

### Adicionado (Fase 0 — Esqueleto + estrutura open-source)
- Estrutura de pastas do projeto (`source/`, `designtime/`, `packages/`, `tests/`, `demos/`, `docs/`).
- Pacotes Delphi com o split obrigatório **runtime** (`ReportsHowieRT`) e **design-time** (`ReportsHowieDT`), mais o grupo `ReportsHowieGroup.groupproj`.
- Units core: `rh.Types` (unidade de relatório 0,1 mm + conversores mm/px/pt/twips/EMU), `rh.Consts`, `rh.Classes`.
- Componente `TrhReport` (esqueleto instalável) e registro na paleta **ReportsHowie** (`rh.Reg`).
- Estrutura open-source: `LICENSE` (LGPL-3.0), `COPYING.GPL`, `README`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, `.gitignore`/`.gitattributes` para Delphi, templates de issue/PR e workflow de CI (`.github/workflows/ci.yml`).

[Unreleased]: https://github.com/howardroatti/ReportsHowie/commits/main
