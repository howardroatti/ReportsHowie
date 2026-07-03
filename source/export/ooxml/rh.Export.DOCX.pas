{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Exportador DOCX (WordprocessingML/OOXML, puro Pascal via System.Zip).
///   Reproduz o layout POSICIONAL do relatorio (fiel ao preview/PDF): cada objeto
///   de texto vira um paragrafo com text frame (w:framePr) ancorado a pagina na
///   posicao/largura exatas do objeto, com fonte/negrito/italico/sublinhado/cor/
///   alinhamento. Imagens viram <w:drawing> FLUTUANTE ancorado (wp:anchor) em x/y
///   absolutos (PNG em word/media, dimensionado em EMU pelo retangulo). Linhas e
///   retangulos viram formas VML (<v:rect>) posicionadas em absoluto (atras do
///   texto). Elipses/poligonos ainda nao exportados.
/// </summary>
unit rh.Export.DOCX;

interface

uses
  rh.Render.Intf;

type
  TrhDocxExporter = class
  public
    class procedure ExportToFile(Doc: TrhRenderedDocument; const FileName: string);
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Generics.Defaults,
  Winapi.Windows, Vcl.Graphics, Vcl.Imaging.pngimage,
  rh.Types, rh.Model.Types, rh.OOXML.Zip;

function RgbHex(C: TColor): string;
var
  RGB: Longint;
begin
  RGB := ColorToRGB(C);
  Result := Format('%.2X%.2X%.2X', [GetRValue(RGB), GetGValue(RGB), GetBValue(RGB)]);
end;

/// <summary>Codifica um TGraphic (bitmap/jpeg/png) em bytes PNG para word/media.</summary>
function ImagePngBytes(G: TGraphic): TBytes;
var
  BMP: TBitmap;
  PNG: TPngImage;
  MS: TMemoryStream;
begin
  BMP := TBitmap.Create;
  PNG := TPngImage.Create;
  MS := TMemoryStream.Create;
  try
    BMP.PixelFormat := pf24bit;
    BMP.SetSize(G.Width, G.Height);
    BMP.Canvas.Brush.Color := clWhite;
    BMP.Canvas.FillRect(TRect.Create(0, 0, BMP.Width, BMP.Height));
    BMP.Canvas.Draw(0, 0, G);
    PNG.Assign(BMP);
    PNG.SaveToStream(MS);
    SetLength(Result, MS.Size);
    if MS.Size > 0 then
      Move(MS.Memory^, Result[0], MS.Size);
  finally
    MS.Free;
    PNG.Free;
    BMP.Free;
  end;
end;

/// <summary>Paragrafo com uma imagem inline (drawingML). RId casa com a
///  relationship em word/_rels/document.xml.rels; Id e unico no documento.</summary>
/// <summary>Paragrafo com uma imagem FLUTUANTE ancorada em posicao absoluta na
///  pagina (x/y/tamanho do retangulo do objeto, em EMU) — reproduz o layout
///  posicional do relatorio (nao empilha em fluxo). RId casa com a relationship.</summary>
function DrawingXml(Op: TrhDrawOp; RId, Id: Integer): string;
var
  CX, CY, PX, PY: Int64;
begin
  CX := MMToEMU(Op.Rect.Width);
  CY := MMToEMU(Op.Rect.Height);
  if CX <= 0 then CX := 990000;   // ~27,5mm fallback
  if CY <= 0 then CY := 990000;
  PX := MMToEMU(Op.Rect.Left);
  PY := MMToEMU(Op.Rect.Top);
  Result :=
    '<w:drawing>' +
    Format('<wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" ' +
      'relativeHeight="%3:d" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">' +
      '<wp:simplePos x="0" y="0"/>' +
      '<wp:positionH relativeFrom="page"><wp:posOffset>%4:d</wp:posOffset></wp:positionH>' +
      '<wp:positionV relativeFrom="page"><wp:posOffset>%5:d</wp:posOffset></wp:positionV>' +
      '<wp:extent cx="%0:d" cy="%1:d"/>' +
      '<wp:effectExtent l="0" t="0" r="0" b="0"/>' +
      '<wp:wrapNone/>' +
      '<wp:docPr id="%2:d" name="Imagem %2:d"/>' +
      '<wp:cNvGraphicFramePr>' +
      '<a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>' +
      '</wp:cNvGraphicFramePr>' +
      '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">' +
      '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">' +
      '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">' +
      '<pic:nvPicPr><pic:cNvPr id="%2:d" name="Imagem %2:d"/><pic:cNvPicPr/></pic:nvPicPr>' +
      '<pic:blipFill><a:blip r:embed="rId%6:d"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>' +
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%0:d" cy="%1:d"/></a:xfrm>' +
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>' +
      '</pic:pic></a:graphicData></a:graphic></wp:anchor>',
      [CX, CY, Id, Id, PX, PY, RId]) +
    '</w:drawing>';
end;

/// <summary>Valor em pontos (pt) com ponto decimal invariante, p/ estilos VML.</summary>
function Pt(U: TrhUnit): string;
begin
  Result := Format('%.2f', [MMToPt(U)], TFormatSettings.Invariant);
end;

/// <summary>Linha/retangulo como forma VML `<v:rect>` (SEM wrapper de paragrafo)
///  posicionada em absoluto na pagina (pt). Linha = retangulo fino preenchido com
///  a cor da caneta; retangulo = borda (PenWidth/PenColor) + preenchimento se opaco.
///  Atras do texto (z-index negativo). Todas as formas vao num unico <w:pict>
///  (um so paragrafo) para nao empurrar o fluxo/paginas. Reproduz reguas/molduras/
///  barras de barcode/modulos de QR do relatorio.</summary>
function ShapeXml(Op: TrhDrawOp): string;
const
  BASE = 'position:absolute;mso-position-horizontal-relative:page;' +
         'mso-position-vertical-relative:page;z-index:-1';
var
  L, T, W, H, Attrs: string;
begin
  L := Pt(Op.Rect.Left);
  T := Pt(Op.Rect.Top);
  case Op.Kind of
    rhdkLine:
      begin
        if Op.Rect.Width <= 0 then W := Pt(Op.PenWidth) else W := Pt(Op.Rect.Width);
        if Op.Rect.Height <= 0 then H := Pt(Op.PenWidth) else H := Pt(Op.Rect.Height);
        Attrs := Format('filled="t" fillcolor="#%s" stroked="f"', [RgbHex(Op.PenColor)]);
      end;
    rhdkRect:
      begin
        W := Pt(Op.Rect.Width);
        H := Pt(Op.Rect.Height);
        if Op.BrushTransparent then
          Attrs := Format('filled="f" stroked="t" strokecolor="#%s" strokeweight="%spt"',
            [RgbHex(Op.PenColor), Pt(Op.PenWidth)])
        else
          Attrs := Format('filled="t" fillcolor="#%s" stroked="t" strokecolor="#%s" strokeweight="%spt"',
            [RgbHex(Op.BrushColor), RgbHex(Op.PenColor), Pt(Op.PenWidth)]);
      end;
  else
    Exit('');
  end;
  Result := Format('<v:rect ' +
    'style="%s;left:%spt;top:%spt;width:%spt;height:%spt" %s/>',
    [BASE, L, T, W, H, Attrs]);
end;

function RunProps(Op: TrhDrawOp): string;
begin
  Result := '<w:rPr>';
  Result := Result + Format('<w:rFonts w:ascii="%0:s" w:hAnsi="%0:s" w:cs="%0:s"/>',
    [XmlEscape(Op.FontName)]);
  if fsBold in Op.FontStyle then Result := Result + '<w:b/>';
  if fsItalic in Op.FontStyle then Result := Result + '<w:i/>';
  if fsUnderline in Op.FontStyle then Result := Result + '<w:u w:val="single"/>';
  Result := Result + Format('<w:color w:val="%s"/>', [RgbHex(Op.FontColor)]);
  Result := Result + Format('<w:sz w:val="%d"/><w:szCs w:val="%d"/>',
    [Op.FontSize * 2, Op.FontSize * 2]); // half-points
  Result := Result + '</w:rPr>';
end;

function ParaProps(Op: TrhDrawOp): string;
var
  Jc, Frame: string;
  W, H: Integer;
begin
  case Op.HAlign of
    rhhaCenter:  Jc := 'center';
    rhhaRight:   Jc := 'right';
    rhhaJustify: Jc := 'both';
  else
    Jc := 'left';
  end;
  // posicionamento ABSOLUTO na pagina via text frame (w:framePr): x/y/largura do
  // objeto (twips), ancorados a pagina -> reproduz o layout posicional do relatorio
  // em vez de empilhar por fluxo. wrap="none" permite objetos lado a lado.
  W := MMToTwips(Op.Rect.Width);
  H := MMToTwips(Op.Rect.Height);
  if W <= 0 then W := 1000;
  Frame := Format('<w:framePr w:w="%d" w:h="%d" w:hRule="atLeast" w:wrap="none" ' +
    'w:hAnchor="page" w:vAnchor="page" w:x="%d" w:y="%d"/>',
    [W, H, MMToTwips(Op.Rect.Left), MMToTwips(Op.Rect.Top)]);
  Result := Format('<w:pPr>%s<w:jc w:val="%s"/></w:pPr>', [Frame, Jc]);
end;

function ParagraphXml(Op: TrhDrawOp): string;
var
  Lines: TArray<string>;
  I: Integer;
  Runs: string;
begin
  Lines := Op.Text.Replace(#13#10, #10).Split([#10]);
  Runs := '';
  for I := 0 to High(Lines) do
  begin
    if I > 0 then Runs := Runs + '<w:br/>';
    Runs := Runs + Format('<w:t xml:space="preserve">%s</w:t>', [XmlEscape(Lines[I])]);
  end;
  Result := '<w:p>' + ParaProps(Op) +
    '<w:r>' + RunProps(Op) + Runs + '</w:r></w:p>';
end;

type
  TFlowItem = record
    Op: TrhDrawOp;
    Page, Top, Left: Integer;
  end;

class procedure TrhDocxExporter.ExportToFile(Doc: TrhRenderedDocument;
  const FileName: string);
var
  Pkg: TrhOoxmlPackage;
  SB, Rels: TStringBuilder;
  Items: TList<TFlowItem>;
  Item: TFlowItem;
  P, PgW, PgH, ImgN: Integer;
  Op: TrhDrawOp;
  HasImages: Boolean;
  Shapes, Draws: TStringBuilder;
begin
  Items := TList<TFlowItem>.Create;
  SB := TStringBuilder.Create;
  Rels := TStringBuilder.Create;
  Shapes := TStringBuilder.Create;
  Draws := TStringBuilder.Create;
  try
    // coletar textos E imagens em ordem de fluxo (pagina, Top, Left)
    for P := 0 to Doc.PageCount - 1 do
      for Op in Doc.Pages[P].Ops do
        if ((Op.Kind = rhdkText) and (Trim(Op.Text) <> '')) or
           (Op.Kind in [rhdkLine, rhdkRect]) or
           ((Op.Kind = rhdkImage) and (Op.Graphic <> nil) and
            (Op.Graphic.Width > 0) and (Op.Graphic.Height > 0)) then
        begin
          Item.Op := Op;
          Item.Page := P;
          Item.Top := Op.Rect.Top;
          Item.Left := Op.Rect.Left;
          Items.Add(Item);
        end;

    Items.Sort(TComparer<TFlowItem>.Construct(
      function(const A, B: TFlowItem): Integer
      begin
        Result := A.Page - B.Page;
        if Result = 0 then Result := A.Top - B.Top;
        if Result = 0 then Result := A.Left - B.Left;
      end));

    // tamanho de pagina (em twips) a partir da 1a pagina
    PgW := 11906; PgH := 16838; // A4 fallback
    if Doc.PageCount > 0 then
    begin
      PgW := MMToTwips(Doc.Pages[0].Width);
      PgH := MMToTwips(Doc.Pages[0].Height);
    end;

    Pkg := TrhOoxmlPackage.Create;
    try
      SB.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
      SB.Append('<w:document ' +
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" ' +
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ' +
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" ' +
        'xmlns:v="urn:schemas-microsoft-com:vml" ' +
        'xmlns:o="urn:schemas-microsoft-com:office:office">');
      SB.Append('<w:body>');

      Rels.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
      Rels.Append('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');

      // Texto -> paragrafos com framePr (frames, fora do fluxo). Imagens e formas
      // -> acumuladas e emitidas num UNICO paragrafo flutuante (abaixo), para que
      // centenas de formas (ex.: modulos de QR) NAO gerem centenas de paragrafos
      // de fluxo que empurrariam o conteudo por varias paginas.
      ImgN := 0;
      for Item in Items do
        if Item.Op.Kind = rhdkImage then
        begin
          Inc(ImgN);
          Pkg.AddBytes(Format('word/media/image%d.png', [ImgN]),
            ImagePngBytes(Item.Op.Graphic));
          Rels.Append(Format('<Relationship Id="rId%0:d" ' +
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" ' +
            'Target="media/image%0:d.png"/>', [ImgN]));
          Draws.Append(DrawingXml(Item.Op, ImgN, ImgN));
        end
        else if Item.Op.Kind in [rhdkLine, rhdkRect] then
          Shapes.Append(ShapeXml(Item.Op))
        else
          SB.Append(ParagraphXml(Item.Op));

      HasImages := ImgN > 0;
      Rels.Append('</Relationships>');

      // paragrafo unico com todo o conteudo flutuante (formas VML num so <w:pict>
      // + imagens ancoradas), tudo posicionado em absoluto -> 1 linha de fluxo so.
      if (Shapes.Length > 0) or (Draws.Length > 0) then
      begin
        SB.Append('<w:p><w:r>');
        if Shapes.Length > 0 then
          SB.Append('<w:pict>').Append(Shapes.ToString).Append('</w:pict>');
        if Draws.Length > 0 then
          SB.Append(Draws.ToString);
        SB.Append('</w:r></w:p>');
      end;

      // paragrafo normal de fecho (o corpo nao pode terminar num frame) e sectPr.
      // Margens 0: os frames sao ancorados a pagina e o retangulo do objeto ja
      // inclui a margem do relatorio -> evita deslocamento duplo.
      SB.Append('<w:p/>');
      SB.Append(Format('<w:sectPr><w:pgSz w:w="%d" w:h="%d"/>' +
        '<w:pgMar w:top="0" w:right="0" w:bottom="0" w:left="0" ' +
        'w:header="0" w:footer="0" w:gutter="0"/></w:sectPr>', [PgW, PgH]));
      SB.Append('</w:body></w:document>');

      Pkg.AddXml('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        '<Default Extension="png" ContentType="image/png"/>' +
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
        '</Types>');

      Pkg.AddXml('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' +
        '</Relationships>');

      Pkg.AddXml('word/document.xml', SB.ToString);

      if HasImages then
        Pkg.AddXml('word/_rels/document.xml.rels', Rels.ToString);

      Pkg.SaveToFile(FileName);
    finally
      Pkg.Free;
    end;
  finally
    Draws.Free;
    Shapes.Free;
    Rels.Free;
    SB.Free;
    Items.Free;
  end;
end;

end.
