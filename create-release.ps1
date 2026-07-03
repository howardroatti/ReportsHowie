<#
.SYNOPSIS
  Cria o GitHub Release da versao informada, anexando o(s) .zip de dist\.

.DESCRIPTION
  Valida a tag (vX.Y.Z) local, o arquivo de notas e os anexos; fixa a conta gh
  correta e chama `gh release create`. Rode DEPOIS de gerar o .zip com
  pack-release.ps1 e de a tag ja existir no remoto.

.EXAMPLE
  .\create-release.ps1                 # cria o release v0.1.0 com os .zip de dist\
.EXAMPLE
  .\create-release.ps1 -DryRun         # so mostra o comando, sem publicar
.EXAMPLE
  .\create-release.ps1 -Version 0.2.0 -Draft
#>
[CmdletBinding()]
param(
  [string]   $Version   = "0.1.0",          # casa com a tag vX.Y.Z
  [string]   $User      = "howardroatti",    # conta gh (evita o 403 da outra conta)
  [string]   $NotesFile,                      # default: docs\RELEASE-<Version>.md
  [string[]] $Assets,                         # default: dist\ReportsHowie-<Version>-*.zip
  [switch]   $Draft,                          # cria como rascunho
  [switch]   $Prerelease,                     # marca como pre-release (senao, --latest)
  [switch]   $DryRun                          # so imprime o comando gh
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Tag  = "v$Version"

if (-not $NotesFile) { $NotesFile = Join-Path $Root "docs\RELEASE-$Version.md" }
elseif (-not [System.IO.Path]::IsPathRooted($NotesFile)) { $NotesFile = Join-Path $Root $NotesFile }

Write-Host "== ReportsHowie - criar release $Tag ==" -ForegroundColor Cyan

# gh instalado?
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI (gh) nao encontrado no PATH. Instale: https://cli.github.com/"
}

# tag existe localmente?
$tagExists = (& git -C $Root tag -l $Tag)
if (-not $tagExists) {
  throw "Tag $Tag nao existe localmente. Crie e faca push antes (git tag -a $Tag ...)."
}

# notas existem?
if (-not (Test-Path $NotesFile)) { throw "Arquivo de notas nao encontrado: $NotesFile" }

# anexos: default = todos os .zip da versao em dist\
if (-not $Assets) {
  $Assets = Get-ChildItem (Join-Path $Root "dist") -Filter "ReportsHowie-$Version-*.zip" `
              -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
}
if (-not $Assets -or $Assets.Count -eq 0) {
  throw "Nenhum anexo .zip encontrado em dist\ (rode pack-release.ps1 primeiro)."
}
$missing = $Assets | Where-Object { -not (Test-Path $_) }
if ($missing) { throw "Anexo(s) inexistente(s):`n  $($missing -join "`n  ")" }

Write-Host "Notas : $NotesFile"
Write-Host "Anexos:"; $Assets | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green }
Write-Host ""

# monta os argumentos do gh release create
$ghArgs = @("release","create",$Tag,"--title","ReportsHowie $Tag","--notes-file",$NotesFile)
if ($Prerelease) { $ghArgs += "--prerelease" } else { $ghArgs += "--latest" }
if ($Draft)      { $ghArgs += "--draft" }
$ghArgs += $Assets

if ($DryRun) {
  Write-Host "[DryRun] gh auth switch --user $User" -ForegroundColor Yellow
  Write-Host "[DryRun] gh $($ghArgs -join ' ')" -ForegroundColor Yellow
  return
}

# fixa a conta correta (o CLAUDE.md avisa que a conta 'volta' para a errada)
& gh auth switch --user $User
if ($LASTEXITCODE -ne 0) { Write-Host "Aviso: 'gh auth switch' retornou $LASTEXITCODE." -ForegroundColor Yellow }

& gh @ghArgs
if ($LASTEXITCODE -ne 0) { throw "gh release create falhou (exit $LASTEXITCODE)." }

Write-Host ""
Write-Host "Release $Tag criado com sucesso." -ForegroundColor Cyan
Write-Host "Confira: https://github.com/$User/ReportsHowie/releases/tag/$Tag"
