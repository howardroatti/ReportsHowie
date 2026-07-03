{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Enums e conjuntos usados pelo modelo de relatorio, com conversores
///   para/de string (usados na serializacao JSON, que grava nomes estaveis
///   em vez de indices ordinais — resistente a reordenacao de enums).
/// </summary>
unit rh.Model.Types;

interface

type
  /// <summary>Tipo/banda de um TrhBand. Define o papel e o comportamento no pipeline.</summary>
  TrhBandType = (
    rhbtReportTitle,   // uma vez, no inicio do relatorio
    rhbtPageHeader,    // topo de cada pagina
    rhbtPageFooter,    // rodape de cada pagina
    rhbtGroupHeader,   // inicio de um grupo
    rhbtMasterData,    // repete por registro do dataset mestre
    rhbtDetailData,    // repete por registro do dataset detalhe
    rhbtGroupFooter,   // fim de um grupo
    rhbtSummary,       // uma vez, no fim (totais gerais)
    rhbtChild          // banda auxiliar ancorada a outra
  );

  /// <summary>Alinhamento horizontal do texto.</summary>
  TrhHAlign = (rhhaLeft, rhhaCenter, rhhaRight, rhhaJustify);

  /// <summary>Alinhamento vertical do texto.</summary>
  TrhVAlign = (rhvaTop, rhvaCenter, rhvaBottom);

  /// <summary>Formato geometrico de um TrhShapeObject.</summary>
  TrhShapeKind = (rhskRectangle, rhskRoundRect, rhskEllipse);

  /// <summary>Simbologia de um TrhBarcodeObject (1D e 2D).</summary>
  TrhBarcodeSymbology = (rhbcCode128, rhbcCode39, rhbcQRCode);

  /// <summary>Tipo de um TrhChartObject.</summary>
  TrhChartType = (rhctBar, rhctLine, rhctPie);

  /// <summary>Agregacao aplicada ao valor por categoria num TrhChartObject.</summary>
  TrhChartAggregate = (rhcaSum, rhcaAvg, rhcaCount, rhcaMin, rhcaMax);

  /// <summary>Orientacao do papel da pagina.</summary>
  TrhOrientation = (rhoPortrait, rhoLandscape);

  /// <summary>Lados da moldura (frame) de um objeto.</summary>
  TrhFrameSide = (rhfsLeft, rhfsTop, rhfsRight, rhfsBottom);
  TrhFrameSides = set of TrhFrameSide;

const
  RH_ALL_FRAME_SIDES = [rhfsLeft, rhfsTop, rhfsRight, rhfsBottom];

// ----------------------------------------------------------------------------
// Conversores enum <-> string (nomes estaveis para o JSON)
// ----------------------------------------------------------------------------

function BandTypeToStr(V: TrhBandType): string;
function StrToBandType(const S: string; Default: TrhBandType = rhbtMasterData): TrhBandType;

function HAlignToStr(V: TrhHAlign): string;
function StrToHAlign(const S: string; Default: TrhHAlign = rhhaLeft): TrhHAlign;

function VAlignToStr(V: TrhVAlign): string;
function StrToVAlign(const S: string; Default: TrhVAlign = rhvaTop): TrhVAlign;

function ShapeKindToStr(V: TrhShapeKind): string;
function StrToShapeKind(const S: string; Default: TrhShapeKind = rhskRectangle): TrhShapeKind;

function BarcodeSymbologyToStr(V: TrhBarcodeSymbology): string;
function StrToBarcodeSymbology(const S: string; Default: TrhBarcodeSymbology = rhbcCode128): TrhBarcodeSymbology;

function ChartTypeToStr(V: TrhChartType): string;
function StrToChartType(const S: string; Default: TrhChartType = rhctBar): TrhChartType;
function ChartAggregateToStr(V: TrhChartAggregate): string;
function StrToChartAggregate(const S: string; Default: TrhChartAggregate = rhcaSum): TrhChartAggregate;

function OrientationToStr(V: TrhOrientation): string;
function StrToOrientation(const S: string; Default: TrhOrientation = rhoPortrait): TrhOrientation;

function FrameSidesToStr(V: TrhFrameSides): string;   // ex.: 'LTRB'
function StrToFrameSides(const S: string): TrhFrameSides;

implementation

uses
  System.SysUtils;

function BandTypeToStr(V: TrhBandType): string;
begin
  case V of
    rhbtReportTitle: Result := 'reportTitle';
    rhbtPageHeader:  Result := 'pageHeader';
    rhbtPageFooter:  Result := 'pageFooter';
    rhbtGroupHeader: Result := 'groupHeader';
    rhbtMasterData:  Result := 'masterData';
    rhbtDetailData:  Result := 'detailData';
    rhbtGroupFooter: Result := 'groupFooter';
    rhbtSummary:     Result := 'summary';
    rhbtChild:       Result := 'child';
  else
    Result := 'masterData';
  end;
end;

function StrToBandType(const S: string; Default: TrhBandType): TrhBandType;
begin
  if SameText(S, 'reportTitle') then Result := rhbtReportTitle
  else if SameText(S, 'pageHeader') then Result := rhbtPageHeader
  else if SameText(S, 'pageFooter') then Result := rhbtPageFooter
  else if SameText(S, 'groupHeader') then Result := rhbtGroupHeader
  else if SameText(S, 'masterData') then Result := rhbtMasterData
  else if SameText(S, 'detailData') then Result := rhbtDetailData
  else if SameText(S, 'groupFooter') then Result := rhbtGroupFooter
  else if SameText(S, 'summary') then Result := rhbtSummary
  else if SameText(S, 'child') then Result := rhbtChild
  else Result := Default;
end;

function HAlignToStr(V: TrhHAlign): string;
begin
  case V of
    rhhaLeft:    Result := 'left';
    rhhaCenter:  Result := 'center';
    rhhaRight:   Result := 'right';
    rhhaJustify: Result := 'justify';
  else
    Result := 'left';
  end;
end;

function StrToHAlign(const S: string; Default: TrhHAlign): TrhHAlign;
begin
  if SameText(S, 'left') then Result := rhhaLeft
  else if SameText(S, 'center') then Result := rhhaCenter
  else if SameText(S, 'right') then Result := rhhaRight
  else if SameText(S, 'justify') then Result := rhhaJustify
  else Result := Default;
end;

function VAlignToStr(V: TrhVAlign): string;
begin
  case V of
    rhvaTop:    Result := 'top';
    rhvaCenter: Result := 'center';
    rhvaBottom: Result := 'bottom';
  else
    Result := 'top';
  end;
end;

function StrToVAlign(const S: string; Default: TrhVAlign): TrhVAlign;
begin
  if SameText(S, 'top') then Result := rhvaTop
  else if SameText(S, 'center') then Result := rhvaCenter
  else if SameText(S, 'bottom') then Result := rhvaBottom
  else Result := Default;
end;

function ShapeKindToStr(V: TrhShapeKind): string;
begin
  case V of
    rhskRectangle: Result := 'rectangle';
    rhskRoundRect: Result := 'roundRect';
    rhskEllipse:   Result := 'ellipse';
  else
    Result := 'rectangle';
  end;
end;

function StrToShapeKind(const S: string; Default: TrhShapeKind): TrhShapeKind;
begin
  if SameText(S, 'rectangle') then Result := rhskRectangle
  else if SameText(S, 'roundRect') then Result := rhskRoundRect
  else if SameText(S, 'ellipse') then Result := rhskEllipse
  else Result := Default;
end;

function BarcodeSymbologyToStr(V: TrhBarcodeSymbology): string;
begin
  case V of
    rhbcCode39: Result := 'code39';
    rhbcQRCode: Result := 'qrcode';
  else
    Result := 'code128';
  end;
end;

function StrToBarcodeSymbology(const S: string; Default: TrhBarcodeSymbology): TrhBarcodeSymbology;
begin
  if SameText(S, 'code128') then Result := rhbcCode128
  else if SameText(S, 'code39') then Result := rhbcCode39
  else if SameText(S, 'qrcode') then Result := rhbcQRCode
  else Result := Default;
end;

function ChartTypeToStr(V: TrhChartType): string;
begin
  case V of
    rhctLine: Result := 'line';
    rhctPie:  Result := 'pie';
  else
    Result := 'bar';
  end;
end;

function StrToChartType(const S: string; Default: TrhChartType): TrhChartType;
begin
  if SameText(S, 'bar') then Result := rhctBar
  else if SameText(S, 'line') then Result := rhctLine
  else if SameText(S, 'pie') then Result := rhctPie
  else Result := Default;
end;

function ChartAggregateToStr(V: TrhChartAggregate): string;
begin
  case V of
    rhcaAvg:   Result := 'avg';
    rhcaCount: Result := 'count';
    rhcaMin:   Result := 'min';
    rhcaMax:   Result := 'max';
  else
    Result := 'sum';
  end;
end;

function StrToChartAggregate(const S: string; Default: TrhChartAggregate): TrhChartAggregate;
begin
  if SameText(S, 'sum') then Result := rhcaSum
  else if SameText(S, 'avg') then Result := rhcaAvg
  else if SameText(S, 'count') then Result := rhcaCount
  else if SameText(S, 'min') then Result := rhcaMin
  else if SameText(S, 'max') then Result := rhcaMax
  else Result := Default;
end;

function OrientationToStr(V: TrhOrientation): string;
begin
  if V = rhoLandscape then Result := 'landscape' else Result := 'portrait';
end;

function StrToOrientation(const S: string; Default: TrhOrientation): TrhOrientation;
begin
  if SameText(S, 'landscape') then Result := rhoLandscape
  else if SameText(S, 'portrait') then Result := rhoPortrait
  else Result := Default;
end;

function FrameSidesToStr(V: TrhFrameSides): string;
begin
  Result := '';
  if rhfsLeft in V then Result := Result + 'L';
  if rhfsTop in V then Result := Result + 'T';
  if rhfsRight in V then Result := Result + 'R';
  if rhfsBottom in V then Result := Result + 'B';
end;

function StrToFrameSides(const S: string): TrhFrameSides;
begin
  Result := [];
  if Pos('L', UpperCase(S)) > 0 then Include(Result, rhfsLeft);
  if Pos('T', UpperCase(S)) > 0 then Include(Result, rhfsTop);
  if Pos('R', UpperCase(S)) > 0 then Include(Result, rhfsRight);
  if Pos('B', UpperCase(S)) > 0 then Include(Result, rhfsBottom);
end;

end.
