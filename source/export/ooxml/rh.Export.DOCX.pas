{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Exportador DOCX (WordprocessingML/OOXML, puro Pascal via System.Zip).
///   Word e um documento de fluxo (paragrafos), nao posicional; mapeamos cada
///   objeto de texto para um paragrafo, ordenado por pagina/Top/Left, com fonte,
///   negrito/italico/sublinhado, cor, alinhamento e recuo esquerdo (a partir do
///   Left). Formas/linhas/imagens sao ignoradas nesta versao de fluxo.
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
  Winapi.Windows, Vcl.Graphics,
  rh.Types, rh.Model.Types, rh.OOXML.Zip;

function RgbHex(C: TColor): string;
var
  RGB: Longint;
begin
  RGB := ColorToRGB(C);
  Result := Format('%.2X%.2X%.2X', [GetRValue(RGB), GetGValue(RGB), GetBValue(RGB)]);
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
  Jc, Ind: string;
begin
  case Op.HAlign of
    rhhaCenter:  Jc := 'center';
    rhhaRight:   Jc := 'right';
    rhhaJustify: Jc := 'both';
  else
    Jc := 'left';
  end;
  Ind := '';
  // recuo esquerdo preserva alguma posicao horizontal (so faz sentido a esquerda)
  if (Op.HAlign = rhhaLeft) and (Op.Rect.Left > 0) then
    Ind := Format('<w:ind w:left="%d"/>', [MMToTwips(Op.Rect.Left)]);
  Result := Format('<w:pPr><w:jc w:val="%s"/>%s</w:pPr>', [Jc, Ind]);
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
  SB: TStringBuilder;
  Items: TList<TFlowItem>;
  Item: TFlowItem;
  P, PgW, PgH: Integer;
  Op: TrhDrawOp;
begin
  Items := TList<TFlowItem>.Create;
  SB := TStringBuilder.Create;
  try
    // coletar textos em ordem de fluxo (pagina, Top, Left)
    for P := 0 to Doc.PageCount - 1 do
      for Op in Doc.Pages[P].Ops do
        if (Op.Kind = rhdkText) and (Trim(Op.Text) <> '') then
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

    SB.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    SB.Append('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">');
    SB.Append('<w:body>');
    for Item in Items do
      SB.Append(ParagraphXml(Item.Op));
    SB.Append(Format('<w:sectPr><w:pgSz w:w="%d" w:h="%d"/>' +
      '<w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" ' +
      'w:header="0" w:footer="0" w:gutter="0"/></w:sectPr>', [PgW, PgH]));
    SB.Append('</w:body></w:document>');

    Pkg := TrhOoxmlPackage.Create;
    try
      Pkg.AddXml('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
        '</Types>');

      Pkg.AddXml('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' +
        '</Relationships>');

      Pkg.AddXml('word/document.xml', SB.ToString);

      Pkg.SaveToFile(FileName);
    finally
      Pkg.Free;
    end;
  finally
    SB.Free;
    Items.Free;
  end;
end;

end.
