# Como lançar uma release do ReportsHowie

Passo a passo para publicar uma versão (ex.: `v0.1.0`) com os BPLs anexados.
Como o **Delphi Community não compila por linha de comando**, os BPLs são
gerados **pela IDE**; o restante (tag, release, notas) é git/`gh`.

## 0. Pré-requisitos

- Working tree limpa, na branch `main`, tudo commitado.
- `CHANGELOG.md` com a seção da versão (mover `[Unreleased]` → `[X.Y.Z]` com data).
- `docs/RELEASE-X.Y.Z.md` com as notas do release (corpo do GitHub Release).
- Versão coerente no `{$DESCRIPTION}`/badges do README, se aplicável.

## 1. Compilar os BPLs (IDE, por versão do Delphi alvo)

Para **cada** versão do Delphi suportada (12.1 Athens hoje; outras conforme forem
validadas), na plataforma **Win32** e **Win64**:

1. Abra `packages/ReportsHowieGroup.groupproj`.
2. Selecione **Release** / **Win32**.
3. **Build** `ReportsHowieRT` → gera `ReportsHowieRT<sufixo>.bpl` + `.dcp`.
4. **Build** `ReportsHowieDT` → gera `ReportsHowieDT<sufixo>.bpl` + `.dcp`.
5. Repita para **Win64** se for distribuir 64-bit.

Os artefatos ficam em `...\Public Documents\Embarcadero\Studio\<ver>\Bpl\<plat>`
(BPL) e `...\Dcp\<plat>` (DCP). O `<sufixo>` vem do `{$LIBSUFFIX AUTO}` (ex.: `290`
no Delphi 12 Athens).

> **Teste rápido de sanidade** antes de empacotar: em um perfil limpo do IDE,
> instale só o `DT`, solte um `TrhReport` num form novo, abra o designer, gere um
> preview com dados e exporte um PDF. Confirme que o `TrhPreviewControl` (preview
> embutível) está disponível na paleta.

## 2. Empacotar os anexos

Use o script `pack-release.ps1` (na raiz) — ele copia RT+DT (`.bpl`) e os `.dcp`
da pasta de saída do Delphi, junto com `LICENSE` e as notas, e gera o `.zip`:

```powershell
.\pack-release.ps1                 # Delphi 12 (sufixo 290), Win32
.\pack-release.ps1 -IncludeWin64   # inclui Win64
.\pack-release.ps1 -Suffix 280 -DelphiLabel Delphi11 -StudioVer 22.0
```

Ele aborta listando o que falta se algum BPL não foi compilado. Estrutura do
`.zip` gerado (`dist\ReportsHowie-0.1.0-Delphi12.zip`):

```
ReportsHowie-0.1.0-Delphi12.zip
├─ Win32/ ReportsHowieRT290.bpl  ReportsHowieDT290.bpl  *.dcp
└─ Win64/ ReportsHowieRT290.bpl  ReportsHowieDT290.bpl  *.dcp
```

Inclua no `.zip` uma cópia de `LICENSE` e `docs/RELEASE-0.1.0.md`.

## 3. Tag + push (seguir o CLAUDE.md para autenticação)

```sh
gh auth switch --user howardroatti
git tag -a v0.1.0 -m "ReportsHowie v0.1.0"
GIT_TERMINAL_PROMPT=0 git -c credential.https://github.com.helper='' \
  -c credential.https://github.com.helper='!gh auth git-credential' \
  push origin v0.1.0
```

> Não incluir `.github/workflows/` em commits (o token não tem escopo *workflow*).
> Stage explícito dos arquivos, nunca `git add -A`.

## 4. Criar o GitHub Release

Use `create-release.ps1` (na raiz) — valida a tag, as notas e os anexos, fixa a
conta `gh` e cria o release (pega automaticamente todos os `.zip` de `dist\`):

```powershell
.\create-release.ps1            # cria v0.1.0 com os .zip de dist\
.\create-release.ps1 -DryRun    # só mostra o comando, sem publicar
```

Equivalente manual:

```sh
gh release create v0.1.0 \
  --title "ReportsHowie v0.1.0" \
  --notes-file docs/RELEASE-0.1.0.md \
  --latest \
  dist/ReportsHowie-0.1.0-Delphi12.zip
```

(Adicione um `.zip` por versão do Delphi como argumento extra.)

## 5. Pós-release

- Conferir a página do Release e os downloads.
- Rotular issues fáceis com **`good first issue`** (ver template) para atrair
  contribuições.
- Abrir de volta um `[Unreleased]` vazio no topo do `CHANGELOG.md` (já feito no
  fluxo desta versão).
- Anunciar (README badge de versão, comunidade Delphi).

## Checklist rápido

- [ ] `CHANGELOG.md` com a seção `[X.Y.Z]` datada + links de comparação
- [ ] `docs/RELEASE-X.Y.Z.md` escrito
- [ ] BPLs RT+DT compilados (Release, Win32/Win64) por versão do Delphi
- [ ] Sanidade: instalar DT em perfil limpo + preview + export PDF
- [ ] `.zip` por versão do Delphi montado (com LICENSE)
- [ ] `git tag -a vX.Y.Z` + push da tag
- [ ] `gh release create` com notas + anexos
- [ ] Issues `good first issue` rotuladas
