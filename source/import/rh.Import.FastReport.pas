{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Importador nativo de templates FastReport VCL (.frx, que e XML) para o
///   modelo do ReportsHowie. Constroi o TrhReport vivo direto do codigo/IDE,
///   sem depender do script Python companheiro (tools/frx2rhr). Cobre pagina,
///   bandas e os objetos mais comuns (memo/linha/forma/imagem/barcode).
///
///   Uso:
///     Imp := TrhFastReportImporter.Create;
///     try
///       Imp.ImportFile('template.frx', Report);   // preenche um TrhReport
///       // Imp.Warnings lista o que nao foi convertido 1:1
///     finally
///       Imp.Free;
///     end;
///
///   Limitacoes (ver tools/frx2rhr/README.md e issue #23): imagens embutidas
///   saem vazias; PascalScript/funcoes de expressao nao sao traduzidas;
///   TfrxCrossView, estilos e Highlight condicional nao sao cobertos.
/// </summary>
unit rh.Import.FastReport;

interface

uses
  System.Classes, System.SysUtils, Vcl.Graphics, Xml.XMLIntf,
  rh.Report, rh.Page, rh.Bands, rh.Objects, rh.Model.Types;

type
  /// <summary>Le um .frx (FastReport) e preenche um TrhReport.</summary>
  TrhFastReportImporter = class
  private
    FDpi: Integer;
    FInv: TFormatSettings;
    FWarnings: TStrings;
    function PxU(const S: string): Integer;   // pixel de design -> unidade (0,1mm)
    function MmU(const S: string): Integer;    // milimetro -> unidade (0,1mm)
    function ColorU(const S: string): TColor;  // cor FastReport (BGR) -> TColor
    procedure ApplyFont(AFont: TFont; const AName, AHeight, AStyle, AColor: string);
    function MapExpr(const S: string): string; // [Dataset."campo"] -> [campo]
    procedure ImportObject(Node: IXMLNode; ABand: TrhBand);
    procedure ImportBand(Node: IXMLNode; APage: TrhPage);
    procedure ImportPage(Node: IXMLNode; AReport: TrhReport);
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Le o arquivo .frx e preenche AReport (que e esvaziado antes).</summary>
    procedure ImportFile(const AFileName: string; AReport: TrhReport);
    /// <summary>Le de um stream (conteudo .frx em UTF-8) e preenche AReport.</summary>
    procedure ImportStream(AStream: TStream; AReport: TrhReport);
    /// <summary>Le de uma string com o XML do .frx e preenche AReport.</summary>
    procedure ImportXML(const AXml: string; AReport: TrhReport);

    /// <summary>Conveniencia: cria um novo TrhReport (AOwner opcional) ja importado.</summary>
    class function LoadFromFile(const AFileName: string;
      AOwner: TComponent = nil): TrhReport;

    /// <summary>DPI de design do FastReport (padrao 96).</summary>
    property Dpi: Integer read FDpi write FDpi;
    /// <summary>Avisos de conversao (objetos ignorados, imagens nao extraidas...).</summary>
    property Warnings: TStrings read FWarnings;
  end;

implementation

uses
  System.Variants, System.Math, System.RegularExpressions,
  Xml.XMLDoc;

const
  // classe de banda FastReport -> TrhBandType
  BAND_COUNT = 10;
  BAND_TAGS: array[0..BAND_COUNT - 1] of string = (
    'TfrxReportTitle', 'TfrxReportSummary', 'TfrxPageHeader', 'TfrxPageFooter',
    'TfrxMasterData', 'TfrxDetailData', 'TfrxSubdetailData',
    'TfrxGroupHeader', 'TfrxGroupFooter', 'TfrxChild');
  BAND_TYPES: array[0..BAND_COUNT - 1] of TrhBandType = (
    rhbtReportTitle, rhbtSummary, rhbtPageHeader, rhbtPageFooter,
    rhbtMasterData, rhbtDetailData, rhbtDetailData,
    rhbtGroupHeader, rhbtGroupFooter, rhbtChild);

function TryBandType(const ATag: string; out AType: TrhBandType): Boolean;
var
  I: Integer;
begin
  for I := 0 to BAND_COUNT - 1 do
    if SameText(ATag, BAND_TAGS[I]) then
    begin
      AType := BAND_TYPES[I];
      Exit(True);
    end;
  Result := False;
end;

// ---- acesso a atributos (nomes com ponto, ex.: "Font.Height", sao validos) --

function Attr(Node: IXMLNode; const AName, ADef: string): string;
begin
  if (Node <> nil) and Node.HasAttribute(AName) then
    Result := VarToStr(Node.Attributes[AName])
  else
    Result := ADef;
end;

// texto de um TfrxMemoView: filho <Memo.UTF8> / <Memo>, senao atributo Text
function MemoText(Node: IXMLNode): string;
var
  I: Integer;
  Child: IXMLNode;
  Tag: string;
begin
  if Node <> nil then
    for I := 0 to Node.ChildNodes.Count - 1 do
    begin
      Child := Node.ChildNodes[I];
      Tag := Child.NodeName;
      if SameText(Tag, 'Memo.UTF8') or SameText(Tag, 'Memo') then
        Exit(Trim(Child.Text));
    end;
  Result := Attr(Node, 'Text', '');
end;

{ TrhFastReportImporter }

constructor TrhFastReportImporter.Create;
begin
  inherited Create;
  FDpi := 96;
  FInv := TFormatSettings.Invariant;
  FWarnings := TStringList.Create;
end;

destructor TrhFastReportImporter.Destroy;
begin
  FWarnings.Free;
  inherited Destroy;
end;

function TrhFastReportImporter.PxU(const S: string): Integer;
begin
  // px / dpi * 25,4 mm * 10 (unidade = 0,1 mm)
  Result := Round(StrToFloatDef(S, 0, FInv) / FDpi * 254.0);
end;

function TrhFastReportImporter.MmU(const S: string): Integer;
begin
  Result := Round(StrToFloatDef(S, 0, FInv) * 10.0);
end;

function TrhFastReportImporter.ColorU(const S: string): TColor;
var
  N: Int64;
begin
  // FastReport ja grava a cor no formato BGR do Windows (mesmo do TColor).
  if TryStrToInt64(Trim(S), N) and (N >= 0) then
    Result := TColor(Integer(N))
  else
    Result := clBlack;
end;

procedure TrhFastReportImporter.ApplyFont(AFont: TFont;
  const AName, AHeight, AStyle, AColor: string);
var
  H: Double;
  Style: Integer;
  FS: TFontStyles;
  N: Int64;
begin
  if AName <> '' then
    AFont.Name := AName;
  // Font.Height do FastReport: pixels (negativo). pt = |px| * 72 / dpi
  H := StrToFloatDef(AHeight, -13, FInv);
  if H < 0 then
    H := -H;
  if H > 0 then
    AFont.Size := Max(1, Round(H * 72.0 / FDpi));
  FS := [];
  Style := StrToIntDef(AStyle, 0);
  if (Style and 1) <> 0 then Include(FS, fsBold);
  if (Style and 2) <> 0 then Include(FS, fsItalic);
  if (Style and 4) <> 0 then Include(FS, fsUnderline);
  AFont.Style := FS;
  if TryStrToInt64(Trim(AColor), N) and (N >= 0) then
    AFont.Color := TColor(Integer(N));
end;

function TrhFastReportImporter.MapExpr(const S: string): string;
begin
  if S = '' then
    Exit('');
  // [Dataset."campo"] / [Dataset.campo] / ["campo"] -> [campo]
  Result := TRegEx.Replace(S,
    '\[\s*(?:[A-Za-z_]\w*\s*\.\s*)?"?([A-Za-z_]\w*)"?\s*\]', '[$1]');
end;

procedure TrhFastReportImporter.ImportObject(Node: IXMLNode; ABand: TrhBand);
var
  Tag, Shape, BarType: string;
  L, T, W, H: Integer;
  Txt: TrhTextObject;
  Img: TrhImageObject;
  Ln: TrhLineObject;
  Shp: TrhShapeObject;
  Bc: TrhBarcodeObject;

  procedure SetBounds(AObj: TrhReportObject);
  begin
    AObj.Name := Attr(Node, 'Name', '');
    AObj.Left := L;
    AObj.Top := T;
    AObj.Width := W;
    AObj.Height := H;
  end;

begin
  Tag := Node.NodeName;
  L := PxU(Attr(Node, 'Left', '0'));
  T := PxU(Attr(Node, 'Top', '0'));
  W := PxU(Attr(Node, 'Width', '0'));
  H := PxU(Attr(Node, 'Height', '0'));

  if SameText(Tag, 'TfrxMemoView') then
  begin
    Txt := ABand.Objects.AddNew<TrhTextObject>;
    SetBounds(Txt);
    Txt.Text := MapExpr(MemoText(Node));
    ApplyFont(Txt.Font, Attr(Node, 'Font.Name', ''), Attr(Node, 'Font.Height', '-13'),
      Attr(Node, 'Font.Style', '0'), Attr(Node, 'Font.Color', '0'));
    Txt.HAlign := StrToHAlign(
      TRegEx.Replace(Attr(Node, 'HAlign', 'haLeft'), '^ha', '', [roIgnoreCase]));
    Txt.VAlign := StrToVAlign(
      TRegEx.Replace(Attr(Node, 'VAlign', 'vaTop'), '^va', '', [roIgnoreCase]));
    Txt.WordWrap := not SameText(Attr(Node, 'WordWrap', 'True'), 'False');
  end
  else if SameText(Tag, 'TfrxLineView') then
  begin
    Ln := ABand.Objects.AddNew<TrhLineObject>;
    SetBounds(Ln);
    Ln.Height := 0; // linha horizontal
    Ln.PenColor := ColorU(Attr(Node, 'Frame.Color', '0'));
    Ln.PenWidth := Max(1, Round(StrToFloatDef(Attr(Node, 'Frame.Width', '1'), 1, FInv) * 2));
  end
  else if SameText(Tag, 'TfrxShapeView') then
  begin
    Shp := ABand.Objects.AddNew<TrhShapeObject>;
    SetBounds(Shp);
    Shape := Attr(Node, 'Shape', 'skRectangle');
    if SameText(Shape, 'skEllipse') or SameText(Shape, 'skCircle') then
      Shp.Kind := rhskEllipse
    else if SameText(Shape, 'skRoundRectangle') then
      Shp.Kind := rhskRoundRect
    else
      Shp.Kind := rhskRectangle;
    Shp.PenColor := ColorU(Attr(Node, 'Frame.Color', '0'));
    Shp.PenWidth := Max(1, Round(StrToFloatDef(Attr(Node, 'Frame.Width', '1'), 1, FInv) * 2));
    Shp.BrushColor := ColorU(Attr(Node, 'Color', '16777215'));
    Shp.Transparent := SameText(Attr(Node, 'Color', 'clNone'), 'clNone');
  end
  else if SameText(Tag, 'TfrxPictureView') then
  begin
    Img := ABand.Objects.AddNew<TrhImageObject>;
    SetBounds(Img);
    Img.Stretch := True;
    FWarnings.Add(Format('TfrxPictureView "%s": imagem embutida nao extraida ' +
      '(reaponte a origem no ReportsHowie).', [Attr(Node, 'Name', '?')]));
  end
  else if SameText(Tag, 'TfrxBarCodeView') then
  begin
    Bc := ABand.Objects.AddNew<TrhBarcodeObject>;
    SetBounds(Bc);
    BarType := Attr(Node, 'BarType', '');
    if Pos('QR', UpperCase(BarType)) > 0 then
      Bc.Symbology := rhbcQRCode
    else
      Bc.Symbology := rhbcCode128;
    Bc.Text := MapExpr(Attr(Node, 'Expression', Attr(Node, 'Text', '')));
  end
  else
    FWarnings.Add(Format('Objeto "%s" (%s) ignorado (sem mapeamento).',
      [Attr(Node, 'Name', '?'), Tag]));
end;

procedure TrhFastReportImporter.ImportBand(Node: IXMLNode; APage: TrhPage);
var
  Child: IXMLNode;
  BType: TrhBandType;
  Band: TrhBand;
  I: Integer;
  Tag: string;
begin
  if not TryBandType(Node.NodeName, BType) then
    Exit;
  Band := APage.Bands.AddBand(BType);
  Band.Name := Attr(Node, 'Name', '');
  Band.Height := PxU(Attr(Node, 'Height', '0'));
  Band.DataSetName := Attr(Node, 'DataSet', '');
  Band.GroupExpression := MapExpr(Attr(Node, 'Condition', ''));
  for I := 0 to Node.ChildNodes.Count - 1 do
  begin
    Child := Node.ChildNodes[I];
    Tag := Child.NodeName;
    if (Length(Tag) >= 4) and SameText(Copy(Tag, 1, 4), 'Tfrx') then
      ImportObject(Child, Band);
  end;
end;

procedure TrhFastReportImporter.ImportPage(Node: IXMLNode; AReport: TrhReport);
var
  Child: IXMLNode;
  Page: TrhPage;
  I: Integer;
begin
  Page := AReport.Pages.AddPage;
  Page.Name := Attr(Node, 'Name', '');
  Page.PaperWidth := MmU(Attr(Node, 'PaperWidth', '210'));
  Page.PaperHeight := MmU(Attr(Node, 'PaperHeight', '297'));
  if SameText(Attr(Node, 'Orientation', 'poPortrait'), 'poLandscape') then
    Page.Orientation := rhoLandscape
  else
    Page.Orientation := rhoPortrait;
  Page.MarginLeft := MmU(Attr(Node, 'LeftMargin', '10'));
  Page.MarginTop := MmU(Attr(Node, 'TopMargin', '10'));
  Page.MarginRight := MmU(Attr(Node, 'RightMargin', '10'));
  Page.MarginBottom := MmU(Attr(Node, 'BottomMargin', '10'));
  for I := 0 to Node.ChildNodes.Count - 1 do
  begin
    Child := Node.ChildNodes[I];
    ImportBand(Child, Page);
  end;
end;

procedure TrhFastReportImporter.ImportXML(const AXml: string; AReport: TrhReport);
var
  Doc: IXMLDocument;
  Root: IXMLNode;

  procedure Walk(Node: IXMLNode);
  var
    I: Integer;
  begin
    if Node = nil then
      Exit;
    if SameText(Node.NodeName, 'TfrxReportPage') then
      ImportPage(Node, AReport)
    else
      for I := 0 to Node.ChildNodes.Count - 1 do
        Walk(Node.ChildNodes[I]);
  end;

begin
  FWarnings.Clear;
  Doc := LoadXMLData(AXml);
  Doc.Active := True;
  Root := Doc.DocumentElement;
  if Root = nil then
    raise Exception.Create('ReportsHowie: .frx invalido (sem elemento raiz).');

  AReport.Clear; // esvazia (remove a pagina default)
  AReport.Title := Attr(Root, 'ReportOptions.Name', '');
  AReport.Author := Attr(Root, 'ReportOptions.Author', '');
  Walk(Root);

  if AReport.Pages.Count = 0 then
  begin
    AReport.EnsurePage; // nunca deixa o relatorio sem pagina
    FWarnings.Add('Nenhuma TfrxReportPage encontrada no .frx.');
  end;
end;

procedure TrhFastReportImporter.ImportStream(AStream: TStream; AReport: TrhReport);
var
  Bytes: TBytes;
  Size: Int64;
begin
  Size := AStream.Size - AStream.Position;
  SetLength(Bytes, Size);
  if Size > 0 then
    AStream.ReadBuffer(Bytes[0], Size);
  ImportXML(TEncoding.UTF8.GetString(Bytes), AReport);
end;

procedure TrhFastReportImporter.ImportFile(const AFileName: string; AReport: TrhReport);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    ImportStream(FS, AReport);
  finally
    FS.Free;
  end;
end;

class function TrhFastReportImporter.LoadFromFile(const AFileName: string;
  AOwner: TComponent): TrhReport;
var
  Imp: TrhFastReportImporter;
begin
  Result := TrhReport.Create(AOwner);
  try
    Imp := TrhFastReportImporter.Create;
    try
      Imp.ImportFile(AFileName, Result);
    finally
      Imp.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
