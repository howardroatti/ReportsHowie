{******************************************************************************}
{                                                                              }
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{                                                                              }
{  Copyright (C) 2026 Howard Roatti e contribuidores                           }
{                                                                              }
{  Este arquivo e parte do ReportsHowie.                                       }
{                                                                              }
{  ReportsHowie e software livre: voce pode redistribui-lo e/ou modifica-lo    }
{  sob os termos da GNU Lesser General Public License (LGPL) versao 3,         }
{  conforme publicada pela Free Software Foundation.                           }
{                                                                              }
{  Este programa e distribuido na esperanca de que seja util, mas SEM          }
{  QUALQUER GARANTIA; veja a LGPL-3.0 para mais detalhes (arquivo LICENSE).    }
{                                                                              }
{******************************************************************************}

/// <summary>
///   Tipos fundamentais do ReportsHowie. A unidade de trabalho interna e o
///   "report unit" = 0,1 mm (decimo de milimetro), armazenado como inteiro
///   para evitar deriva de ponto flutuante e garantir independencia de
///   dispositivo. A conversao para pixels/points/twips/EMU acontece apenas
///   nas pontas (renderizadores e exportadores).
/// </summary>
unit rh.Types;

interface

uses
  System.Types;

type
  /// <summary>Unidade de relatorio: decimos de milimetro (1 unidade = 0,1 mm).</summary>
  TrhUnit = Integer;

  /// <summary>Ponto em unidades de relatorio.</summary>
  TrhPointU = record
    X, Y: TrhUnit;
  end;

  /// <summary>Tamanho em unidades de relatorio.</summary>
  TrhSizeU = record
    CX, CY: TrhUnit;
  end;

  /// <summary>Retangulo em unidades de relatorio (Left, Top, Right, Bottom).</summary>
  TrhRectU = record
    Left, Top, Right, Bottom: TrhUnit;
    function Width: TrhUnit;
    function Height: TrhUnit;
    class function Create(ALeft, ATop, AWidth, AHeight: TrhUnit): TrhRectU; static;
  end;

const
  /// <summary>Unidades de relatorio por milimetro.</summary>
  RH_UNITS_PER_MM = 10;

  /// <summary>Resolucao logica padrao para conversoes independentes de tela.</summary>
  RH_DEFAULT_DPI = 96;

  /// <summary>Milimetros por polegada.</summary>
  RH_MM_PER_INCH = 25.4;

// ----------------------------------------------------------------------------
// Conversores. Recebem/retornam unidades de relatorio (0,1 mm).
// ----------------------------------------------------------------------------

/// <summary>Converte milimetros (float) para unidades de relatorio.</summary>
function MMToUnits(const AMillimeters: Double): TrhUnit;
/// <summary>Converte unidades de relatorio para milimetros.</summary>
function UnitsToMM(const AUnits: TrhUnit): Double;

/// <summary>Converte unidades de relatorio para pixels de tela no DPI informado.</summary>
function MMToPx(const AUnits: TrhUnit; ADpi: Integer = RH_DEFAULT_DPI): Integer;
/// <summary>Converte pixels de tela para unidades de relatorio no DPI informado.</summary>
function PxToUnits(const APixels: Integer; ADpi: Integer = RH_DEFAULT_DPI): TrhUnit;

/// <summary>Converte unidades de relatorio para points PDF (1/72 pol) como Double.</summary>
function MMToPt(const AUnits: TrhUnit): Double;

/// <summary>Converte unidades de relatorio para twips (1/1440 pol).</summary>
function MMToTwips(const AUnits: TrhUnit): Integer;

/// <summary>Converte unidades de relatorio para EMU do OOXML (914400 por pol).</summary>
function MMToEMU(const AUnits: TrhUnit): Int64;

implementation

{ TrhRectU }

class function TrhRectU.Create(ALeft, ATop, AWidth, AHeight: TrhUnit): TrhRectU;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ALeft + AWidth;
  Result.Bottom := ATop + AHeight;
end;

function TrhRectU.Width: TrhUnit;
begin
  Result := Right - Left;
end;

function TrhRectU.Height: TrhUnit;
begin
  Result := Bottom - Top;
end;

{ Conversores }

function MMToUnits(const AMillimeters: Double): TrhUnit;
begin
  Result := Round(AMillimeters * RH_UNITS_PER_MM);
end;

function UnitsToMM(const AUnits: TrhUnit): Double;
begin
  Result := AUnits / RH_UNITS_PER_MM;
end;

function MMToPx(const AUnits: TrhUnit; ADpi: Integer): Integer;
begin
  // unidades -> mm -> polegadas -> pixels
  Result := Round(UnitsToMM(AUnits) / RH_MM_PER_INCH * ADpi);
end;

function PxToUnits(const APixels: Integer; ADpi: Integer): TrhUnit;
begin
  Result := MMToUnits(APixels / ADpi * RH_MM_PER_INCH);
end;

function MMToPt(const AUnits: TrhUnit): Double;
begin
  // 1 point = 1/72 polegada
  Result := UnitsToMM(AUnits) / RH_MM_PER_INCH * 72;
end;

function MMToTwips(const AUnits: TrhUnit): Integer;
begin
  // 1 twip = 1/1440 polegada
  Result := Round(UnitsToMM(AUnits) / RH_MM_PER_INCH * 1440);
end;

function MMToEMU(const AUnits: TrhUnit): Int64;
begin
  // 914400 EMU por polegada
  Result := Round(UnitsToMM(AUnits) / RH_MM_PER_INCH * 914400);
end;

end.
