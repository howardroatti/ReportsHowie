# Contribuindo com o ReportsHowie

Obrigado por querer ajudar! 🎉 O ReportsHowie existe para dar à comunidade Delphi um gerador de relatórios **livre e gratuito**. Toda contribuição — código, testes, documentação, exemplos, tradução ou reporte de bug — é bem-vinda.

## Antes de começar

- Leia o [Código de Conduta](./CODE_OF_CONDUCT.md).
- Confira o [roadmap no README](./README.md#roadmap) para entender em que fase o projeto está.
- Para mudanças grandes, **abra uma issue** antes para discutirmos a abordagem. Assim evitamos trabalho duplicado ou fora da direção do projeto.

## Ambiente

- **RAD Studio / Delphi 12.1 Athens** (ou versão compatível), personalidade **VCL**.
- Abra `packages/ReportsHowieGroup.groupproj`, faça **Build** do `ReportsHowieRT` e **Install** do `ReportsHowieDT`.
- Testes usam **DUnitX** (incluso no Delphi) no diretório `tests/`.

## Fluxo de Pull Request

1. Faça um **fork** e crie um branch descritivo: `feature/expr-engine`, `fix/pdf-xref`, etc.
2. Faça commits pequenos e com mensagem clara (recomendado [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `test:`, `refactor:`).
3. Garanta que **os pacotes compilam** e que **os testes passam** localmente.
4. Atualize o `CHANGELOG.md` (seção *Unreleased*) e a documentação, quando aplicável.
5. Abra o PR contra o branch `main`, descrevendo **o quê** e **o porquê**. Vincule a issue relacionada.
6. A CI precisa passar (build dos pacotes + testes).

## Estilo de código (Object Pascal)

Seguimos o estilo idiomático Delphi para manter consistência com a RTL/VCL:

- **Nomes:** classes públicas com prefixo `Trh…`, interfaces `Irh…`, enums `rh…` (ex.: `rhbtMasterData`). Campos privados com `F` (`FTitle`). Parâmetros com `A` (`AOwner`).
- **Units:** namespace pontuado com prefixo `rh.` espelhando a pasta (ex.: `rh.Render.Intf.pas`).
- **Indentação:** 2 espaços, sem tabs. `begin`/`end` alinhados ao bloco.
- **Unidade interna de coordenadas:** sempre **unidade de relatório (0,1 mm)** como inteiro; converta só nas pontas (renderizadores/exportadores) com os helpers de `rh.Types`.
- **Sem dependências externas:** exports em Pascal puro. Não adicione bibliotecas de terceiros sem discussão prévia em issue.
- **Design-time isolado:** nada que referencie `DesignIntf`/`DesignEditors` pode entrar no pacote **runtime**.
- Cada unidade nova deve conter o **cabeçalho de licença LGPL** (veja units existentes) e, quando útil, comentários XMLDoc (`/// <summary>`).

## Reportando bugs

Use o template de issue. Inclua: versão do Delphi, passos para reproduzir, comportamento esperado vs. obtido e, se possível, um `.rhr` ou trecho de código mínimo.

## Licença das contribuições

Ao contribuir, você concorda que seu código será distribuído sob a **LGPL-3.0** do projeto.

Dúvidas? Abra uma issue com o rótulo `question`. 🙂
