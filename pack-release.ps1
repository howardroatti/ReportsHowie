<#
.SYNOPSIS
  Empacota os BPLs/DCPs do ReportsHowie num .zip por versao do Delphi, pronto
  para anexar no GitHub Release.

.DESCRIPTION
  Requer que os BPLs ja tenham sido compilados na IDE (Release / Win32 [/ Win64]).
  Copia RT+DT (.bpl) e os .dcp da pasta de saida do Delphi, junto com LICENSE e as
  notas do release, e gera dist\ReportsHowie-<Version>-<DelphiLabel>.zip.

.EXAMPLE
  # Delphi 12 Athens (sufixo 290), so Win32:
  .\pack-release.ps1

.EXAMPLE
  # incluindo Win64:
  .\pack-release.ps1 -IncludeWin64

.EXAMPLE
  # outra versao/sufixo, apontando pastas de saida manualmente:
  .\pack-release.ps1 -Suffix 280 -DelphiLabel Delphi11 -StudioVer 22.0
#>
[CmdletBinding()]
param(
  [string] $Version     = "0.1.0",     # versao do release (casa com a tag vX.Y.Z)
  [string] $Suffix      = "290",        # LIBSUFFIX AUTO: 290=Delphi 12, 280=11, ...
  [string] $DelphiLabel = "Delphi12",   # rotulo no nome do .zip
  [string] $StudioVer   = "23.0",       # 23.0=Delphi 12, 22.0=11, ...
  [switch] $IncludeWin64,               # tambem empacotar os BPLs Win64
  [string] $BplRoot,                    # override: pasta base dos .bpl (contem Win32\ e Win64\)
  [string] $DcpRoot                     # override: pasta base dos .dcp (contem Win32\ e Win64\)
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot                   # raiz do repo (este script mora na raiz)

# Pastas padrao de saida do Delphi (Public Documents).
if (-not $BplRoot) { $BplRoot = Join-Path $env:PUBLIC "Documents\Embarcadero\Studio\$StudioVer\Bpl" }
if (-not $DcpRoot) { $DcpRoot = Join-Path $env:PUBLIC "Documents\Embarcadero\Studio\$StudioVer\Dcp" }

$Platforms = @("Win32")
if ($IncludeWin64) { $Platforms += "Win64" }

Write-Host "== ReportsHowie - empacotar release $Version ($DelphiLabel, sufixo $Suffix) ==" -ForegroundColor Cyan
Write-Host "BPL: $BplRoot"
Write-Host "DCP: $DcpRoot"
Write-Host "Plataformas: $($Platforms -join ', ')"
Write-Host ""

# Monta a pasta de staging do zero.
$StageBase = Join-Path $Root "dist\ReportsHowie-$Version-$DelphiLabel"
if (Test-Path $StageBase) { Remove-Item $StageBase -Recurse -Force }
New-Item -ItemType Directory -Force -Path $StageBase | Out-Null

$Missing = @()

function Copy-Checked([string]$Src, [string]$DestDir) {
  if (Test-Path $Src) {
    Copy-Item $Src $DestDir -Force
    Write-Host "  + $([System.IO.Path]::GetFileName($Src))" -ForegroundColor Green
  } else {
    $script:Missing += $Src
    Write-Host "  ! FALTA: $Src" -ForegroundColor Red
  }
}

foreach ($Plat in $Platforms) {
  Write-Host "[$Plat]" -ForegroundColor Yellow
  $StagePlat = Join-Path $StageBase $Plat
  New-Item -ItemType Directory -Force -Path $StagePlat | Out-Null

  # Layout do Delphi: Win32 sai direto em Bpl\ e Dcp\; Win64 numa subpasta Win64\.
  if ($Plat -eq "Win32") {
    $bpl = $BplRoot
    $dcp = $DcpRoot
  } else {
    $bpl = Join-Path $BplRoot $Plat
    $dcp = Join-Path $DcpRoot $Plat
  }

  # O .bpl leva o sufixo LIBSUFFIX (ex.: 290); o .dcp NAO leva sufixo.
  Copy-Checked (Join-Path $bpl "ReportsHowieRT$Suffix.bpl") $StagePlat
  Copy-Checked (Join-Path $bpl "ReportsHowieDT$Suffix.bpl") $StagePlat
  Copy-Checked (Join-Path $dcp "ReportsHowieRT.dcp") $StagePlat
  Copy-Checked (Join-Path $dcp "ReportsHowieDT.dcp") $StagePlat
}

# Documentos que acompanham o pacote.
Write-Host "[docs]" -ForegroundColor Yellow
Copy-Checked (Join-Path $Root "LICENSE") $StageBase
Copy-Checked (Join-Path $Root "docs\RELEASE-$Version.md") $StageBase

if ($Missing.Count -gt 0) {
  Write-Host ""
  Write-Host "Abortado: $($Missing.Count) arquivo(s) faltando (ver acima)." -ForegroundColor Red
  Write-Host "Compile os pacotes na IDE em Release/$($Platforms -join '+') ou ajuste -Suffix/-StudioVer/-BplRoot/-DcpRoot." -ForegroundColor Red
  exit 1
}

# Gera o .zip.
$Zip = Join-Path $Root "dist\ReportsHowie-$Version-$DelphiLabel.zip"
if (Test-Path $Zip) { Remove-Item $Zip -Force }
Compress-Archive -Path (Join-Path $StageBase "*") -DestinationPath $Zip -Force

$SizeKB = [math]::Round((Get-Item $Zip).Length / 1KB, 1)
Write-Host ""
Write-Host "OK: $Zip ($SizeKB KB)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Proximo passo (criar o release):" -ForegroundColor Cyan
Write-Host "  gh auth switch --user howardroatti"
Write-Host "  gh release create v$Version --title `"ReportsHowie v$Version`" ``"
Write-Host "    --notes-file docs\RELEASE-$Version.md --latest `"$Zip`""
