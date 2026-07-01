{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Exportador PDF nativo (puro Pascal, sem dependencias). Escreve um PDF 1.4
///   a partir do TrhRenderedDocument: catalogo, arvore de paginas, content
///   streams, as 14 fontes Type1 padrao (familia Helvetica, WinAnsi) e imagens
///   como XObject /DCTDecode (JPEG). Origem do PDF e canto inferior-esquerdo;
///   convertemos a partir do topo. Alinhamento de texto usa metricas GDI.
/// </summary>
unit rh.Export.PDF;

interface

uses
  rh.Render.Intf;

type
  TrhPdfExporter = class
  public
    class procedure ExportToFile(Doc: TrhRenderedDocument; const FileName: string);
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Math,
  Winapi.Windows, Vcl.Graphics, Vcl.Imaging.jpeg,
  rh.Types, rh.Model.Types;

var
  GFS: TFormatSettings;
  GMeasure: TBitmap;

function NS(V: Double): RawByteString;
begin
  Result := RawByteString(Format('%.2f', [V], GFS));
end;

function MeasureBmp: TBitmap;
begin
  if GMeasure = nil then
  begin
    GMeasure := TBitmap.Create;
    GMeasure.SetSize(4, 4);
  end;
  Result := GMeasure;
end;

function MeasureTextPt(const Text, FontName: string; SizePt: Integer; Style: TFontStyles): Double;
begin
  MeasureBmp.Canvas.Font.Name := FontName;
  MeasureBmp.Canvas.Font.Style := Style;
  MeasureBmp.Canvas.Font.Height := -Round(SizePt * 96 / 72);
  Result := MeasureBmp.Canvas.TextWidth(Text) * 72 / 96;
end;

/// <summary>Indice da fonte (1..4) conforme o estilo: 1 normal, 2 bold, 3 italico, 4 bold+italico.</summary>
function FontIndex(Style: TFontStyles): Integer;
begin
  if (fsBold in Style) and (fsItalic in Style) then Result := 4
  else if fsBold in Style then Result := 2
  else if fsItalic in Style then Result := 3
  else Result := 1;
end;

function PdfEscapeText(const S: string): RawByteString;
var
  A: RawByteString;
  I: Integer;
  C: AnsiChar;
begin
  A := RawByteString(AnsiString(S)); // WinAnsi (1252)
  Result := '';
  for I := 1 to Length(A) do
  begin
    C := A[I];
    case C of
      '\': Result := Result + '\\';
      '(': Result := Result + '\(';
      ')': Result := Result + '\)';
      #13: Result := Result + '\r';
      #10: Result := Result + '\n';
    else
      Result := Result + C;
    end;
  end;
end;

function ColorRGB(C: TColor; out R, G, B: Double): string;
var
  V: Longint;
begin
  V := ColorToRGB(C);
  R := GetRValue(V) / 255;
  G := GetGValue(V) / 255;
  B := GetBValue(V) / 255;
  Result := '';
end;

type
  TPdfBuilder = class
  private
    FDoc: TrhRenderedDocument;
    FImages: TList<TrhDrawOp>;
    FImgFirst: Integer;       // numero do 1o objeto de imagem
    FPageFirst: Integer;      // numero do 1o objeto de pagina
    procedure CollectImages;
    function TextOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
    function LineOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
    function ShapeOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
    function ImageOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
    function PageContent(Page: TrhRenderedPage): RawByteString;
    function ImageJpegBytes(Op: TrhDrawOp): TBytes;
  public
    constructor Create(ADoc: TrhRenderedDocument);
    destructor Destroy; override;
    procedure SaveToStream(Stream: TStream);
  end;

constructor TPdfBuilder.Create(ADoc: TrhRenderedDocument);
begin
  inherited Create;
  FDoc := ADoc;
  FImages := TList<TrhDrawOp>.Create;
end;

destructor TPdfBuilder.Destroy;
begin
  FImages.Free;
  inherited Destroy;
end;

procedure TPdfBuilder.CollectImages;
var
  Page: TrhRenderedPage;
  Op: TrhDrawOp;
begin
  FImages.Clear;
  for Page in FDoc.Pages do
    for Op in Page.Ops do
      if (Op.Kind = rhdkImage) and (Op.Graphic <> nil) and
         (Op.Graphic.Width > 0) and (Op.Graphic.Height > 0) then
        FImages.Add(Op);
end;

function TPdfBuilder.TextOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
var
  LeftPt, TopPt, WPt, LineH, X, BaseY, R, G, B: Double;
  Lines: TArray<string>;
  I: Integer;
  LineWidth: Double;
begin
  Result := '';
  if Trim(Op.Text) = '' then Exit;
  LeftPt := MMToPt(Op.Rect.Left);
  TopPt := MMToPt(Op.Rect.Top);
  WPt := MMToPt(Op.Rect.Width);
  LineH := Op.FontSize * 1.2;
  ColorRGB(Op.FontColor, R, G, B);

  Lines := Op.Text.Replace(#13#10, #10).Split([#10]);

  Result := Result + RawByteString(Format('%s %s %s rg'#10, [NS(R), NS(G), NS(B)]));
  Result := Result + RawByteString(Format('BT /F%d %d Tf'#10, [FontIndex(Op.FontStyle), Op.FontSize]));
  for I := 0 to High(Lines) do
  begin
    LineWidth := MeasureTextPt(Lines[I], Op.FontName, Op.FontSize, Op.FontStyle);
    case Op.HAlign of
      rhhaCenter: X := LeftPt + (WPt - LineWidth) / 2;
      rhhaRight:  X := LeftPt + WPt - LineWidth;
    else
      X := LeftPt;
    end;
    // baseline a partir do topo do retangulo, linha a linha
    BaseY := PageHpt - (TopPt + Op.FontSize + I * LineH);
    Result := Result + RawByteString(Format('1 0 0 1 %s %s Tm (', [NS(X), NS(BaseY)]));
    Result := Result + PdfEscapeText(Lines[I]);
    Result := Result + ') Tj'#10;
  end;
  Result := Result + 'ET'#10;
end;

function TPdfBuilder.LineOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
var
  X1, Y1, X2, Y2, R, G, B: Double;
begin
  ColorRGB(Op.PenColor, R, G, B);
  X1 := MMToPt(Op.Rect.Left);
  Y1 := PageHpt - MMToPt(Op.Rect.Top);
  X2 := MMToPt(Op.Rect.Right);
  Y2 := PageHpt - MMToPt(Op.Rect.Bottom);
  Result := RawByteString(Format('%s %s %s RG %s w %s %s m %s %s l S'#10,
    [NS(R), NS(G), NS(B), NS(Max(0.3, MMToPt(Op.PenWidth))),
     NS(X1), NS(Y1), NS(X2), NS(Y2)]));
end;

function TPdfBuilder.ShapeOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
var
  X, Y, W, H, R, G, B, Br, Bg, Bb, K, CX, CY, RX, RY: Double;
  HasFill: Boolean;
begin
  X := MMToPt(Op.Rect.Left);
  W := MMToPt(Op.Rect.Width);
  H := MMToPt(Op.Rect.Height);
  Y := PageHpt - MMToPt(Op.Rect.Bottom); // canto inferior-esquerdo
  HasFill := not Op.BrushTransparent;
  ColorRGB(Op.PenColor, R, G, B);
  ColorRGB(Op.BrushColor, Br, Bg, Bb);

  Result := RawByteString(Format('%s %s %s RG %s w'#10,
    [NS(R), NS(G), NS(B), NS(Max(0.3, MMToPt(Op.PenWidth)))]));
  if HasFill then
    Result := Result + RawByteString(Format('%s %s %s rg'#10, [NS(Br), NS(Bg), NS(Bb)]));

  if Op.Kind = rhdkEllipse then
  begin
    // elipse com 4 curvas de bezier (kappa)
    K := 0.5522847498;
    RX := W / 2; RY := H / 2;
    CX := X + RX; CY := Y + RY;
    Result := Result + RawByteString(Format('%s %s m'#10, [NS(CX + RX), NS(CY)]));
    Result := Result + RawByteString(Format('%s %s %s %s %s %s c'#10,
      [NS(CX + RX), NS(CY + RY * K), NS(CX + RX * K), NS(CY + RY), NS(CX), NS(CY + RY)]));
    Result := Result + RawByteString(Format('%s %s %s %s %s %s c'#10,
      [NS(CX - RX * K), NS(CY + RY), NS(CX - RX), NS(CY + RY * K), NS(CX - RX), NS(CY)]));
    Result := Result + RawByteString(Format('%s %s %s %s %s %s c'#10,
      [NS(CX - RX), NS(CY - RY * K), NS(CX - RX * K), NS(CY - RY), NS(CX), NS(CY - RY)]));
    Result := Result + RawByteString(Format('%s %s %s %s %s %s c'#10,
      [NS(CX + RX * K), NS(CY - RY), NS(CX + RX), NS(CY - RY * K), NS(CX + RX), NS(CY)]));
  end
  else
    Result := Result + RawByteString(Format('%s %s %s %s re'#10, [NS(X), NS(Y), NS(W), NS(H)]));

  if HasFill then
    Result := Result + 'B'#10
  else
    Result := Result + 'S'#10;
end;

function TPdfBuilder.ImageOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
var
  X, Y, W, H: Double;
  Idx: Integer;
begin
  Result := '';
  Idx := FImages.IndexOf(Op);
  if Idx < 0 then Exit;
  X := MMToPt(Op.Rect.Left);
  W := MMToPt(Op.Rect.Width);
  H := MMToPt(Op.Rect.Height);
  Y := PageHpt - MMToPt(Op.Rect.Bottom);
  Result := RawByteString(Format('q %s 0 0 %s %s %s cm /Im%d Do Q'#10,
    [NS(W), NS(H), NS(X), NS(Y), Idx]));
end;

function TPdfBuilder.PageContent(Page: TrhRenderedPage): RawByteString;
var
  Op: TrhDrawOp;
  PageHpt: Double;
begin
  PageHpt := MMToPt(Page.Height);
  Result := '';
  for Op in Page.Ops do
    case Op.Kind of
      rhdkText:    Result := Result + TextOpContent(Op, PageHpt);
      rhdkLine:    Result := Result + LineOpContent(Op, PageHpt);
      rhdkRect,
      rhdkEllipse: Result := Result + ShapeOpContent(Op, PageHpt);
      rhdkImage:   Result := Result + ImageOpContent(Op, PageHpt);
    end;
end;

function TPdfBuilder.ImageJpegBytes(Op: TrhDrawOp): TBytes;
var
  BMP: TBitmap;
  JPG: TJPEGImage;
  MS: TMemoryStream;
begin
  BMP := TBitmap.Create;
  JPG := TJPEGImage.Create;
  MS := TMemoryStream.Create;
  try
    BMP.PixelFormat := pf24bit;
    BMP.SetSize(Op.Graphic.Width, Op.Graphic.Height);
    BMP.Canvas.Brush.Color := clWhite;
    BMP.Canvas.FillRect(TRect.Create(0, 0, BMP.Width, BMP.Height));
    BMP.Canvas.Draw(0, 0, Op.Graphic);
    JPG.CompressionQuality := 90;
    JPG.Assign(BMP);
    JPG.SaveToStream(MS);
    SetLength(Result, MS.Size);
    if MS.Size > 0 then
      Move(MS.Memory^, Result[0], MS.Size);
  finally
    MS.Free;
    JPG.Free;
    BMP.Free;
  end;
end;

procedure TPdfBuilder.SaveToStream(Stream: TStream);
var
  Offsets: TList<Int64>;
  TotalObjs, I, PageObj, ContentObj: Integer;
  NPages: Integer;
  Kids, XObjRes, Body, Content: RawByteString;
  JpegBytes: TBytes;

  procedure W(const S: RawByteString);
  begin
    if Length(S) > 0 then
      Stream.WriteBuffer(S[1], Length(S));
  end;

  procedure WBytes(const B: TBytes);
  begin
    if Length(B) > 0 then
      Stream.WriteBuffer(B[0], Length(B));
  end;

  procedure BeginObj(N: Integer);
  begin
    Offsets[N] := Stream.Position;
    W(RawByteString(IntToStr(N) + ' 0 obj'#10));
  end;

  procedure EndObj;
  begin
    W(#10'endobj'#10);
  end;

begin
  CollectImages;
  NPages := FDoc.PageCount;

  // Numeracao: 1 Catalog, 2 Pages, 3..6 fontes, imagens, depois paginas+conteudo
  FImgFirst := 7;
  FPageFirst := FImgFirst + FImages.Count;
  TotalObjs := FPageFirst + NPages * 2 - 1;
  if NPages = 0 then TotalObjs := 6;

  Offsets := TList<Int64>.Create;
  try
    for I := 0 to TotalObjs do
      Offsets.Add(0);

    W('%PDF-1.4'#10);
    W(RawByteString(#$25 + #$E2 + #$E3 + #$CF + #$D3 + #10));

    // 1: Catalog
    BeginObj(1);
    W('<< /Type /Catalog /Pages 2 0 R >>');
    EndObj;

    // 2: Pages
    Kids := '';
    for I := 0 to NPages - 1 do
      Kids := Kids + RawByteString(IntToStr(FPageFirst + I * 2) + ' 0 R ');
    BeginObj(2);
    W(RawByteString('<< /Type /Pages /Kids [ ' + string(Kids) + '] /Count ' + IntToStr(NPages) + ' >>'));
    EndObj;

    // 3..6: fontes Helvetica
    BeginObj(3); W('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'); EndObj;
    BeginObj(4); W('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>'); EndObj;
    BeginObj(5); W('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique /Encoding /WinAnsiEncoding >>'); EndObj;
    BeginObj(6); W('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-BoldOblique /Encoding /WinAnsiEncoding >>'); EndObj;

    // imagens
    for I := 0 to FImages.Count - 1 do
    begin
      JpegBytes := ImageJpegBytes(FImages[I]);
      BeginObj(FImgFirst + I);
      W(RawByteString(Format('<< /Type /XObject /Subtype /Image /Width %d /Height %d ' +
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length %d >>'#10'stream'#10,
        [FImages[I].Graphic.Width, FImages[I].Graphic.Height, Length(JpegBytes)])));
      WBytes(JpegBytes);
      W(#10'endstream');
      EndObj;
    end;

    // recurso XObject compartilhado (todas as imagens)
    XObjRes := '';
    for I := 0 to FImages.Count - 1 do
      XObjRes := XObjRes + RawByteString(Format('/Im%d %d 0 R ', [I, FImgFirst + I]));

    // paginas + conteudo
    for I := 0 to NPages - 1 do
    begin
      PageObj := FPageFirst + I * 2;
      ContentObj := PageObj + 1;

      Body := RawByteString(Format(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %s %s] ' +
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R /F4 6 0 R >>',
        [string(NS(MMToPt(FDoc.Pages[I].Width))), string(NS(MMToPt(FDoc.Pages[I].Height)))]));
      if FImages.Count > 0 then
        Body := Body + RawByteString(' /XObject << ' + string(XObjRes) + '>>');
      Body := Body + RawByteString(' >> /Contents ' + IntToStr(ContentObj) + ' 0 R >>');

      BeginObj(PageObj);
      W(Body);
      EndObj;

      Content := PageContent(FDoc.Pages[I]);
      BeginObj(ContentObj);
      W(RawByteString('<< /Length ' + IntToStr(Length(Content)) + ' >>'#10'stream'#10));
      W(Content);
      W(#10'endstream');
      EndObj;
    end;

    // xref
    var XrefPos: Int64 := Stream.Position;
    W(RawByteString('xref'#10'0 ' + IntToStr(TotalObjs + 1) + #10));
    W('0000000000 65535 f '#10);
    for I := 1 to TotalObjs do
      W(RawByteString(Format('%.10d 00000 n '#10, [Offsets[I]])));

    // trailer
    W(RawByteString('trailer'#10'<< /Size ' + IntToStr(TotalObjs + 1) + ' /Root 1 0 R >>'#10));
    W(RawByteString('startxref'#10 + IntToStr(XrefPos) + #10'%%EOF'#10));
  finally
    Offsets.Free;
  end;
end;

class procedure TrhPdfExporter.ExportToFile(Doc: TrhRenderedDocument; const FileName: string);
var
  Builder: TPdfBuilder;
  FStream: TFileStream;
begin
  Builder := TPdfBuilder.Create(Doc);
  try
    FStream := TFileStream.Create(FileName, fmCreate);
    try
      Builder.SaveToStream(FStream);
    finally
      FStream.Free;
    end;
  finally
    Builder.Free;
  end;
end;

initialization
  GFS := TFormatSettings.Invariant;

finalization
  GMeasure.Free;

end.
