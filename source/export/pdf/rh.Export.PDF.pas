{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Exportador PDF nativo (puro Pascal, sem dependencias). Escreve um PDF 1.4
///   a partir do TrhRenderedDocument: catalogo, arvore de paginas, content
///   streams e imagens como XObject /DCTDecode (JPEG).
///
///   FONTES: cada (nome+estilo) usado vira uma fonte composta Type0/Identity-H
///   com a TrueType EMBUTIDA (FontFile2), CIDFontType2, larguras /W e CMap
///   ToUnicode -> acentuacao/Unicode e fontes customizadas saem corretas e o
///   texto e copiavel/buscavel. O texto e escrito como glyph indices (via
///   rh.PDF.TrueType). Origem do PDF e canto inferior-esquerdo; convertemos a
///   partir do topo. Alinhamento de texto usa metricas GDI.
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
  rh.Types, rh.Model.Types, rh.PDF.TrueType;

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
  // Uma fonte embutida usada no documento (por nome + estilo). Dona da TTF.
  TPdfFont = class
    Name: string;
    Bold, Italic: Boolean;
    TTF: TrhTrueTypeFont;
    destructor Destroy; override;
  end;

destructor TPdfFont.Destroy;
begin
  TTF.Free;
  inherited Destroy;
end;

// Nome seguro para /BaseFont (PDF name): so ASCII alfanumerico + '-'.
function SanitizeName(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or
       ((C >= '0') and (C <= '9')) or (C = '-') then
      Result := Result + C;
  end;
  if Result = '' then Result := 'Font';
end;

// Carrega a TTF instalada; se falhar, tenta fontes de fallback comuns do Windows.
function LoadTTF(const AName: string; ABold, AItalic: Boolean): TrhTrueTypeFont;
const
  FALLBACKS: array[0..2] of string = ('Arial', 'Segoe UI', 'Tahoma');
var
  I: Integer;
begin
  try
    Exit(TrhTrueTypeFont.CreateFromFont(AName, ABold, AItalic));
  except
    // tenta os fallbacks
  end;
  for I := Low(FALLBACKS) to High(FALLBACKS) do
    try
      Exit(TrhTrueTypeFont.CreateFromFont(FALLBACKS[I], ABold, AItalic));
    except
    end;
  raise Exception.CreateFmt('ReportsHowie: nenhuma fonte TrueType disponivel (%s).', [AName]);
end;

// Texto -> string hexadecimal de glyph indices (2 bytes cada), para Identity-H.
function HexGIDs(const S: string; F: TrhTrueTypeFont): RawByteString;
var
  I: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for I := 1 to Length(S) do
      SB.Append(IntToHex(F.GlyphIndex(Ord(S[I])), 4));
    Result := RawByteString(SB.ToString);
  finally
    SB.Free;
  end;
end;

// Array /W [ 0 [ w0 w1 ... ] ] com a largura de cada glifo (espaco 1000/em).
function WidthsArray(F: TrhTrueTypeFont): RawByteString;
var
  I: Integer;
  SB: TStringBuilder;
begin
  if F.NumGlyphs <= 0 then Exit('');
  SB := TStringBuilder.Create;
  try
    SB.Append('/W [ 0 [');
    for I := 0 to F.NumGlyphs - 1 do
    begin
      SB.Append(' ');
      SB.Append(F.AdvanceWidth1000(I));
    end;
    SB.Append(' ] ]');
    Result := RawByteString(SB.ToString);
  finally
    SB.Free;
  end;
end;

// CMap ToUnicode (GID -> codepoint) para permitir copiar/buscar texto no PDF.
function BuildToUnicode(F: TrhTrueTypeFont): RawByteString;
var
  SB: TStringBuilder;
  Pairs: TArray<TPair<Word, Word>>;
  I, J, Blk: Integer;
begin
  Pairs := F.GIDToCode.ToArray;
  SB := TStringBuilder.Create;
  try
    SB.Append('/CIDInit /ProcSet findresource begin'#10);
    SB.Append('12 dict begin'#10'begincmap'#10);
    SB.Append('/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def'#10);
    SB.Append('/CMapName /Adobe-Identity-UCS def'#10'/CMapType 2 def'#10);
    SB.Append('1 begincodespacerange'#10'<0000> <FFFF>'#10'endcodespacerange'#10);
    I := 0;
    while I < Length(Pairs) do
    begin
      Blk := Min(100, Length(Pairs) - I);
      SB.Append(Blk).Append(' beginbfchar'#10);
      for J := I to I + Blk - 1 do
        SB.Append(Format('<%.4x> <%.4x>'#10, [Pairs[J].Key, Pairs[J].Value]));
      SB.Append('endbfchar'#10);
      Inc(I, Blk);
    end;
    SB.Append('endcmap'#10);
    SB.Append('CMapName currentdict /CMap defineresource pop'#10'end'#10'end'#10);
    Result := RawByteString(SB.ToString);
  finally
    SB.Free;
  end;
end;

type
  TPdfBuilder = class
  private
    FDoc: TrhRenderedDocument;
    FImages: TList<TrhDrawOp>;
    FFonts: TObjectList<TPdfFont>;      // fontes embutidas (dono)
    FFontIndex: TDictionary<string, Integer>;
    FFontFirst: Integer;      // numero do 1o objeto de fonte (=3)
    FImgFirst: Integer;       // numero do 1o objeto de imagem
    FPageFirst: Integer;      // numero do 1o objeto de pagina
    procedure CollectImages;
    procedure CollectFonts;
    function FontKey(const AName: string; ABold, AItalic: Boolean): string;
    function FontIndexOf(Op: TrhDrawOp): Integer;
    function TextOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
    function LineOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
    function ShapeOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
    function PolygonOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
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
  FFonts := TObjectList<TPdfFont>.Create(True);
  FFontIndex := TDictionary<string, Integer>.Create;
end;

destructor TPdfBuilder.Destroy;
begin
  FFontIndex.Free;
  FFonts.Free;
  FImages.Free;
  inherited Destroy;
end;

function TPdfBuilder.FontKey(const AName: string; ABold, AItalic: Boolean): string;
begin
  Result := LowerCase(AName) + '|' + IntToStr(Ord(ABold)) + IntToStr(Ord(AItalic));
end;

// Varre os text ops e carrega uma TTF por (nome, bold, italic) distinto.
procedure TPdfBuilder.CollectFonts;
var
  Page: TrhRenderedPage;
  Op: TrhDrawOp;
  Key: string;
  Bold, Italic: Boolean;
  F: TPdfFont;
begin
  FFonts.Clear;
  FFontIndex.Clear;
  for Page in FDoc.Pages do
    for Op in Page.Ops do
      if (Op.Kind = rhdkText) and (Trim(Op.Text) <> '') then
      begin
        Bold := fsBold in Op.FontStyle;
        Italic := fsItalic in Op.FontStyle;
        Key := FontKey(Op.FontName, Bold, Italic);
        if not FFontIndex.ContainsKey(Key) then
        begin
          F := TPdfFont.Create;
          F.Name := Op.FontName;
          F.Bold := Bold;
          F.Italic := Italic;
          F.TTF := LoadTTF(Op.FontName, Bold, Italic);
          FFontIndex.Add(Key, FFonts.Count);
          FFonts.Add(F);
        end;
      end;
end;

function TPdfBuilder.FontIndexOf(Op: TrhDrawOp): Integer;
begin
  if not FFontIndex.TryGetValue(
    FontKey(Op.FontName, fsBold in Op.FontStyle, fsItalic in Op.FontStyle), Result) then
    Result := -1;
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
  I, Idx: Integer;
  LineWidth: Double;
  ang, ca, sa, cxp, cyp, sxp, syp: Double;
  Txt: string;
  F: TrhTrueTypeFont;
begin
  Result := '';
  if Trim(Op.Text) = '' then Exit;
  Idx := FontIndexOf(Op);
  if Idx < 0 then Exit;
  F := FFonts[Idx].TTF;
  LeftPt := MMToPt(Op.Rect.Left);
  TopPt := MMToPt(Op.Rect.Top);
  WPt := MMToPt(Op.Rect.Width);
  LineH := Op.FontSize * 1.2;
  ColorRGB(Op.FontColor, R, G, B);

  // texto ROTACIONADO (marca d'agua): uma linha, centralizado, com matriz de rotacao
  if Op.Angle <> 0 then
  begin
    ang := Op.Angle * Pi / 180;
    Txt := Op.Text.Replace(#13#10, ' ').Replace(#10, ' ');
    LineWidth := MeasureTextPt(Txt, Op.FontName, Op.FontSize, Op.FontStyle);
    cxp := MMToPt(Op.Rect.Left + Op.Rect.Width div 2);
    cyp := PageHpt - MMToPt(Op.Rect.Top + Op.Rect.Height div 2);
    ca := Cos(ang); sa := Sin(ang);
    sxp := cxp - (LineWidth / 2) * ca + (0.35 * Op.FontSize) * sa;
    syp := cyp - (LineWidth / 2) * sa - (0.35 * Op.FontSize) * ca;
    Result := RawByteString(Format('%s %s %s rg'#10, [NS(R), NS(G), NS(B)]));
    Result := Result + RawByteString(Format('BT /F%d %d Tf'#10, [Idx, Op.FontSize]));
    Result := Result + RawByteString(Format('%s %s %s %s %s %s Tm <',
      [NS(ca), NS(sa), NS(-sa), NS(ca), NS(sxp), NS(syp)]));
    Result := Result + HexGIDs(Txt, F);
    Result := Result + '> Tj'#10'ET'#10;
    Exit;
  end;

  Lines := Op.Text.Replace(#13#10, #10).Split([#10]);

  Result := Result + RawByteString(Format('%s %s %s rg'#10, [NS(R), NS(G), NS(B)]));
  Result := Result + RawByteString(Format('BT /F%d %d Tf'#10, [Idx, Op.FontSize]));
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
    Result := Result + RawByteString(Format('1 0 0 1 %s %s Tm <', [NS(X), NS(BaseY)]));
    Result := Result + HexGIDs(Lines[I], F);
    Result := Result + '> Tj'#10;
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

function TPdfBuilder.PolygonOpContent(Op: TrhDrawOp; PageHpt: Double): RawByteString;
var
  I: Integer;
  X, Y, R, G, B, Br, Bg, Bb: Double;
  HasFill, HasStroke: Boolean;
begin
  Result := '';
  if Length(Op.Points) < 3 then Exit;
  HasFill := not Op.BrushTransparent;
  HasStroke := Op.PenWidth > 0;
  ColorRGB(Op.PenColor, R, G, B);
  ColorRGB(Op.BrushColor, Br, Bg, Bb);
  if HasStroke then
    Result := Result + RawByteString(Format('%s %s %s RG %s w'#10,
      [NS(R), NS(G), NS(B), NS(Max(0.3, MMToPt(Op.PenWidth)))]));
  if HasFill then
    Result := Result + RawByteString(Format('%s %s %s rg'#10, [NS(Br), NS(Bg), NS(Bb)]));
  for I := 0 to High(Op.Points) do
  begin
    X := MMToPt(Op.Points[I].X);
    Y := PageHpt - MMToPt(Op.Points[I].Y);
    if I = 0 then
      Result := Result + RawByteString(Format('%s %s m'#10, [NS(X), NS(Y)]))
    else
      Result := Result + RawByteString(Format('%s %s l'#10, [NS(X), NS(Y)]));
  end;
  Result := Result + 'h'#10; // fecha o contorno
  if HasFill and HasStroke then
    Result := Result + 'B'#10
  else if HasFill then
    Result := Result + 'f'#10
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
      rhdkPolygon: Result := Result + PolygonOpContent(Op, PageHpt);
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
  TotalObjs, I, K, Base, PageObj, ContentObj: Integer;
  NPages: Integer;
  Kids, XObjRes, FontRes, Body, Content, ToUni: RawByteString;
  JpegBytes: TBytes;
  PF: TPdfFont;
  StemV: Integer;

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
  CollectFonts;
  NPages := FDoc.PageCount;

  // Numeracao: 1 Catalog, 2 Pages, fontes (5 objs por fonte embutida), imagens,
  // depois paginas + conteudo.
  FFontFirst := 3;
  FImgFirst := FFontFirst + FFonts.Count * 5;
  FPageFirst := FImgFirst + FImages.Count;
  TotalObjs := FPageFirst + NPages * 2 - 1;
  if TotalObjs < 2 then TotalObjs := 2;

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

    // fontes embutidas: 5 objetos por fonte (Type0, CIDFontType2, FontDescriptor,
    // FontFile2, ToUnicode). BaseName com sufixo de estilo p/ nao colidir entre estilos.
    for K := 0 to FFonts.Count - 1 do
    begin
      Base := FFontFirst + K * 5;
      PF := FFonts[K];
      var BN: RawByteString := RawByteString(SanitizeName(PF.Name));
      if PF.Bold and PF.Italic then BN := BN + RawByteString('-BoldItalic')
      else if PF.Bold then BN := BN + RawByteString('-Bold')
      else if PF.Italic then BN := BN + RawByteString('-Italic');
      if PF.Bold then StemV := 120 else StemV := 80;

      // Type0 (composta, Identity-H)
      BeginObj(Base);
      W(RawByteString(Format('<< /Type /Font /Subtype /Type0 /BaseFont /%s ' +
        '/Encoding /Identity-H /DescendantFonts [ %d 0 R ] /ToUnicode %d 0 R >>',
        [string(BN), Base + 1, Base + 4])));
      EndObj;

      // CIDFontType2 (descendente) + larguras
      BeginObj(Base + 1);
      W(RawByteString(Format('<< /Type /Font /Subtype /CIDFontType2 /BaseFont /%s ' +
        '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> ' +
        '/FontDescriptor %d 0 R /CIDToGIDMap /Identity /DW 1000 ',
        [string(BN), Base + 2])));
      W(WidthsArray(PF.TTF));
      W(' >>');
      EndObj;

      // FontDescriptor
      BeginObj(Base + 2);
      W(RawByteString(Format('<< /Type /FontDescriptor /FontName /%s /Flags %d ' +
        '/FontBBox [ %d %d %d %d ] /ItalicAngle %d /Ascent %d /Descent %d ' +
        '/CapHeight %d /StemV %d /FontFile2 %d 0 R >>',
        [string(BN), PF.TTF.Flags, PF.TTF.BBox(0), PF.TTF.BBox(1), PF.TTF.BBox(2),
         PF.TTF.BBox(3), PF.TTF.ItalicAngle, PF.TTF.Ascent, PF.TTF.Descent,
         PF.TTF.CapHeight, StemV, Base + 3])));
      EndObj;

      // FontFile2 (a fonte inteira embutida)
      BeginObj(Base + 3);
      W(RawByteString(Format('<< /Length %d /Length1 %d >>'#10'stream'#10,
        [Length(PF.TTF.FontData), Length(PF.TTF.FontData)])));
      WBytes(PF.TTF.FontData);
      W(#10'endstream');
      EndObj;

      // ToUnicode
      ToUni := BuildToUnicode(PF.TTF);
      BeginObj(Base + 4);
      W(RawByteString('<< /Length ' + IntToStr(Length(ToUni)) + ' >>'#10'stream'#10));
      W(ToUni);
      W(#10'endstream');
      EndObj;
    end;

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

    // recurso de fontes compartilhado (/F0 = fonte 0, ...)
    FontRes := '';
    for K := 0 to FFonts.Count - 1 do
      FontRes := FontRes + RawByteString(Format('/F%d %d 0 R ', [K, FFontFirst + K * 5]));

    // paginas + conteudo
    for I := 0 to NPages - 1 do
    begin
      PageObj := FPageFirst + I * 2;
      ContentObj := PageObj + 1;

      Body := RawByteString(Format(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %s %s] ' +
        '/Resources << /Font << %s>>',
        [string(NS(MMToPt(FDoc.Pages[I].Width))), string(NS(MMToPt(FDoc.Pages[I].Height))),
         string(FontRes)]));
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
