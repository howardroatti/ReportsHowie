{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Exportador XLSX (SpreadsheetML/OOXML, puro Pascal via System.Zip).
///   A display list e posicional (nao tabular); reconstruimos uma grade
///   agrupando os objetos de texto por posicao: linhas por coordenada Top
///   (por pagina) e colunas por coordenada Left (global). Cada texto vira uma
///   celula (inlineStr, ja formatado pelo pipeline) com fonte/estilo/alinhamento.
///   Imagens sao ancoradas (oneCellAnchor) a celula mais proxima, no tamanho do
///   objeto (EMU). Linhas/formas seguem ignoradas nesta versao tabular pragmatica.
/// </summary>
unit rh.Export.XLSX;

interface

uses
  rh.Render.Intf;

type
  TrhXlsxExporter = class
  public
    class procedure ExportToFile(Doc: TrhRenderedDocument; const FileName: string;
      const SheetName: string = 'Relatorio');
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Generics.Defaults, System.Math, System.StrUtils,
  Winapi.Windows, Vcl.Graphics, Vcl.Imaging.pngimage,
  rh.Types, rh.Model.Types, rh.OOXML.Zip;

const
  ROW_TOL = 15;  // 1,5 mm: tops mais proximos que isso = mesma linha
  COL_TOL = 30;  // 3,0 mm: lefts mais proximos que isso = mesma coluna

type
  TCell = record
    Op: TrhDrawOp;
    Row, Col: Integer;
  end;

  TImageAnchor = record
    Op: TrhDrawOp;
    Row, Col: Integer;           // celula-ancora (0-based) mais proxima
  end;

  TXlsxBuilder = class
  private
    FDoc: TrhRenderedDocument;
    FCells: TList<TCell>;
    FImages: TList<TImageAnchor>;
    FColLefts: TList<Integer>;   // representantes de coluna (global)
    FMaxRow, FMaxCol: Integer;
    FRowH: TArray<Integer>;      // altura (unidades) por linha
    FColW: TArray<Integer>;      // largura (unidades) por coluna
    FFonts: TList<string>;       // xml interno de cada <font>
    FXfs: TList<string>;         // xml de cada <xf>
    procedure BuildGrid;
    function GetFontId(Op: TrhDrawOp): Integer;
    function GetXfId(Op: TrhDrawOp): Integer;
    function StylesXml: string;
    function SheetXml: string;
    function DrawingXml: string;
  public
    constructor Create(ADoc: TrhRenderedDocument);
    destructor Destroy; override;
    procedure Save(const FileName, SheetName: string);
  end;

/// <summary>Codifica um TGraphic em bytes PNG para xl/media.</summary>
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

function ArgbHex(C: TColor): string;
var
  RGB: Longint;
begin
  RGB := ColorToRGB(C);
  Result := Format('FF%.2X%.2X%.2X', [GetRValue(RGB), GetGValue(RGB), GetBValue(RGB)]);
end;

function ColRef(Col: Integer): string; // Col e 1-based
var
  N: Integer;
begin
  Result := '';
  N := Col;
  while N > 0 do
  begin
    Dec(N);
    Result := Chr(Ord('A') + (N mod 26)) + Result;
    N := N div 26;
  end;
end;

/// <summary>Deduplica valores ordenados por tolerancia; cada cluster = 1o valor.</summary>
function DedupeTol(const Sorted: TList<Integer>; Tol: Integer): TList<Integer>;
var
  V: Integer;
begin
  Result := TList<Integer>.Create;
  for V in Sorted do
    if (Result.Count = 0) or (V - Result.Last > Tol) then
      Result.Add(V);
end;

/// <summary>Indice do representante mais proximo de Value.</summary>
function NearestIdx(const Reps: TList<Integer>; Value: Integer): Integer;
var
  I, BestD, D: Integer;
begin
  Result := 0;
  if Reps.Count = 0 then Exit;
  BestD := Abs(Value - Reps[0]);
  for I := 1 to Reps.Count - 1 do
  begin
    D := Abs(Value - Reps[I]);
    if D < BestD then
    begin
      BestD := D;
      Result := I;
    end;
  end;
end;

{ TXlsxBuilder }

constructor TXlsxBuilder.Create(ADoc: TrhRenderedDocument);
begin
  inherited Create;
  FDoc := ADoc;
  FCells := TList<TCell>.Create;
  FImages := TList<TImageAnchor>.Create;
  FColLefts := TList<Integer>.Create;
  FFonts := TList<string>.Create;
  FXfs := TList<string>.Create;
  // fonte 0 e xf 0 padrao (obrigatorios pela especificacao)
  FFonts.Add('<sz val="11"/><color rgb="FF000000"/><name val="Calibri"/><family val="2"/>');
  FXfs.Add('<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>');
end;

destructor TXlsxBuilder.Destroy;
begin
  FXfs.Free;
  FFonts.Free;
  FColLefts.Free;
  FImages.Free;
  FCells.Free;
  inherited Destroy;
end;

procedure TXlsxBuilder.BuildGrid;
var
  Page: TrhRenderedPage;
  Op: TrhDrawOp;
  AllLefts, PageTops, RowReps: TList<Integer>;
  PageImgs: TList<TImageAnchor>;
  GlobalRow, R, C, K, M, N, GrpBottom, GrpRow: Integer;
  Cell: TCell;
  Img: TImageAnchor;
begin
  // colunas: clusteriza todos os lefts de texto (global)
  AllLefts := TList<Integer>.Create;
  try
    for Page in FDoc.Pages do
      for Op in Page.Ops do
        if ((Op.Kind = rhdkText) and (Trim(Op.Text) <> '')) or
           ((Op.Kind = rhdkImage) and (Op.Graphic <> nil) and
            (Op.Graphic.Width > 0) and (Op.Graphic.Height > 0)) then
          AllLefts.Add(Op.Rect.Left);
    AllLefts.Sort;
    FColLefts.Free;
    FColLefts := DedupeTol(AllLefts, COL_TOL);
  finally
    AllLefts.Free;
  end;

  // linhas: por pagina, clusteriza tops; empilha paginas com 1 linha em branco
  GlobalRow := 0;
  for Page in FDoc.Pages do
  begin
    PageTops := TList<Integer>.Create;
    try
      for Op in Page.Ops do
        if ((Op.Kind = rhdkText) and (Trim(Op.Text) <> '')) or
           ((Op.Kind = rhdkImage) and (Op.Graphic <> nil) and
            (Op.Graphic.Width > 0) and (Op.Graphic.Height > 0)) then
          PageTops.Add(Op.Rect.Top);
      PageTops.Sort;
      RowReps := DedupeTol(PageTops, ROW_TOL);
      PageImgs := TList<TImageAnchor>.Create;
      try
        for Op in Page.Ops do
          if (Op.Kind = rhdkText) and (Trim(Op.Text) <> '') then
          begin
            Cell.Op := Op;
            Cell.Row := GlobalRow + NearestIdx(RowReps, Op.Rect.Top);
            Cell.Col := NearestIdx(FColLefts, Op.Rect.Left);
            FCells.Add(Cell);
          end
          else if (Op.Kind = rhdkImage) and (Op.Graphic <> nil) and
                  (Op.Graphic.Width > 0) and (Op.Graphic.Height > 0) then
          begin
            Img.Op := Op;
            Img.Row := GlobalRow + NearestIdx(RowReps, Op.Rect.Top);
            Img.Col := NearestIdx(FColLefts, Op.Rect.Left);
            PageImgs.Add(Img);
          end;

        // alinha na MESMA linha as imagens que se sobrepoem verticalmente (ex.: o
        // QR no topo do item e o barcode logo abaixo) -> grupo recebe a linha do topo.
        PageImgs.Sort(TComparer<TImageAnchor>.Construct(
          function(const A, B: TImageAnchor): Integer
          begin
            Result := A.Op.Rect.Top - B.Op.Rect.Top;
          end));
        K := 0;
        while K < PageImgs.Count do
        begin
          GrpBottom := PageImgs[K].Op.Rect.Bottom;
          GrpRow := PageImgs[K].Row;
          M := K + 1;
          while (M < PageImgs.Count) and (PageImgs[M].Op.Rect.Top <= GrpBottom) do
          begin
            GrpBottom := Max(GrpBottom, PageImgs[M].Op.Rect.Bottom);
            GrpRow := Min(GrpRow, PageImgs[M].Row);
            Inc(M);
          end;
          for N := K to M - 1 do
          begin
            Img := PageImgs[N];
            Img.Row := GrpRow;
            PageImgs[N] := Img;
          end;
          K := M;
        end;
        FImages.AddRange(PageImgs);

        GlobalRow := GlobalRow + RowReps.Count + 1;
      finally
        PageImgs.Free;
        RowReps.Free;
      end;
    finally
      PageTops.Free;
    end;
  end;

  FMaxRow := GlobalRow;
  FMaxCol := FColLefts.Count;
  if FMaxCol = 0 then FMaxCol := 1;

  // dimensoes (texto e imagens: a coluna/linha da imagem precisa comportar o
  // tamanho dela para as imagens nao se sobreporem nem cairem sobre o texto)
  SetLength(FRowH, Max(FMaxRow, 1));
  SetLength(FColW, FMaxCol);
  for Cell in FCells do
  begin
    R := Cell.Row; C := Cell.Col;
    if (R >= 0) and (R < Length(FRowH)) then
      FRowH[R] := Max(FRowH[R], Cell.Op.Rect.Height);
    if (C >= 0) and (C < Length(FColW)) then
      FColW[C] := Max(FColW[C], Cell.Op.Rect.Width);
  end;
  for Img in FImages do
  begin
    R := Img.Row; C := Img.Col;
    if (R >= 0) and (R < Length(FRowH)) then
      FRowH[R] := Max(FRowH[R], Img.Op.Rect.Height);
    if (C >= 0) and (C < Length(FColW)) then
      FColW[C] := Max(FColW[C], Img.Op.Rect.Width);
  end;
end;

function TXlsxBuilder.GetFontId(Op: TrhDrawOp): Integer;
var
  Inner: string;
  I: Integer;
begin
  Inner := Format('<sz val="%d"/><color rgb="%s"/><name val="%s"/><family val="2"/>',
    [Op.FontSize, ArgbHex(Op.FontColor), XmlEscape(Op.FontName)]);
  if fsBold in Op.FontStyle then Inner := '<b/>' + Inner;
  if fsItalic in Op.FontStyle then Inner := '<i/>' + Inner;
  if fsUnderline in Op.FontStyle then Inner := '<u/>' + Inner;
  for I := 0 to FFonts.Count - 1 do
    if FFonts[I] = Inner then Exit(I);
  Result := FFonts.Add(Inner);
end;

function TXlsxBuilder.GetXfId(Op: TrhDrawOp): Integer;
var
  FId, I: Integer;
  HA, VA, Xf: string;
begin
  FId := GetFontId(Op);
  case Op.HAlign of
    rhhaCenter:  HA := 'center';
    rhhaRight:   HA := 'right';
    rhhaJustify: HA := 'justify';
  else
    HA := 'left';
  end;
  case Op.VAlign of
    rhvaCenter: VA := 'center';
    rhvaBottom: VA := 'bottom';
  else
    VA := 'top';
  end;
  Xf := Format('<xf numFmtId="0" fontId="%d" fillId="0" borderId="0" xfId="0" ' +
    'applyFont="1" applyAlignment="1"><alignment horizontal="%s" vertical="%s"%s/></xf>',
    [FId, HA, VA, IfThen(Op.WordWrap, ' wrapText="1"', '')]);
  for I := 0 to FXfs.Count - 1 do
    if FXfs[I] = Xf then Exit(I);
  Result := FXfs.Add(Xf);
end;

function TXlsxBuilder.StylesXml: string;
var
  SB: TStringBuilder;
  S: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    SB.Append('<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    SB.Append(Format('<fonts count="%d">', [FFonts.Count]));
    for S in FFonts do SB.Append('<font>' + S + '</font>');
    SB.Append('</fonts>');
    SB.Append('<fills count="2"><fill><patternFill patternType="none"/></fill>' +
      '<fill><patternFill patternType="gray125"/></fill></fills>');
    SB.Append('<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>');
    SB.Append('<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>');
    SB.Append(Format('<cellXfs count="%d">', [FXfs.Count]));
    for S in FXfs do SB.Append(S);
    SB.Append('</cellXfs>');
    SB.Append('<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>');
    SB.Append('</styleSheet>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TXlsxBuilder.SheetXml: string;
var
  SB: TStringBuilder;
  RowMap: TDictionary<Integer, TList<TCell>>;
  Cell: TCell;
  R, C: Integer;
  RowCells: TList<TCell>;
  WChars, HPts: Double;
begin
  RowMap := TDictionary<Integer, TList<TCell>>.Create;
  SB := TStringBuilder.Create;
  try
    // bucket por linha
    for Cell in FCells do
    begin
      if not RowMap.TryGetValue(Cell.Row, RowCells) then
      begin
        RowCells := TList<TCell>.Create;
        RowMap.Add(Cell.Row, RowCells);
      end;
      RowCells.Add(Cell);
    end;

    SB.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    SB.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' +
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');

    // larguras de coluna
    if FMaxCol > 0 then
    begin
      SB.Append('<cols>');
      for C := 0 to FMaxCol - 1 do
      begin
        WChars := 12;
        if (C < Length(FColW)) and (FColW[C] > 0) then
          WChars := Min(90, Max(8, (FColW[C] / 10 / 25.4 * 96 - 5) / 7));
        SB.Append(Format('<col min="%d" max="%d" width="%.2f" customWidth="1"/>',
          [C + 1, C + 1, WChars], TFormatSettings.Invariant));
      end;
      SB.Append('</cols>');
    end;

    SB.Append('<sheetData>');
    for R := 0 to FMaxRow - 1 do
    begin
      if not RowMap.TryGetValue(R, RowCells) then Continue;
      HPts := 15;
      if (R < Length(FRowH)) and (FRowH[R] > 0) then
        HPts := Max(12, FRowH[R] / 10 / 25.4 * 72);
      RowCells.Sort(TComparer<TCell>.Construct(
        function(const A, B: TCell): Integer
        begin
          Result := A.Col - B.Col;
        end));
      SB.Append(Format('<row r="%d" ht="%.2f" customHeight="1">', [R + 1, HPts],
        TFormatSettings.Invariant));
      for Cell in RowCells do
        SB.Append(Format('<c r="%s%d" s="%d" t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>',
          [ColRef(Cell.Col + 1), R + 1, GetXfId(Cell.Op), XmlEscape(Cell.Op.Text)]));
      SB.Append('</row>');
    end;
    SB.Append('</sheetData>');
    // referencia ao desenho (imagens); rId1 casa com xl/worksheets/_rels/sheet1.xml.rels
    if FImages.Count > 0 then
      SB.Append('<drawing r:id="rId1"/>');
    SB.Append('</worksheet>');
    Result := SB.ToString;
  finally
    for RowCells in RowMap.Values do
      RowCells.Free;
    RowMap.Free;
    SB.Free;
  end;
end;

function TXlsxBuilder.DrawingXml: string;
var
  SB: TStringBuilder;
  I: Integer;
  A: TImageAnchor;
  CX, CY: Int64;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    SB.Append('<xdr:wsDr ' +
      'xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" ' +
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" ' +
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    for I := 0 to FImages.Count - 1 do
    begin
      A := FImages[I];
      CX := MMToEMU(A.Op.Rect.Width);
      CY := MMToEMU(A.Op.Rect.Height);
      if CX <= 0 then CX := 990000;
      if CY <= 0 then CY := 990000;
      // oneCellAnchor: ancorado a celula (from) + tamanho fixo (ext) -> a imagem
      // nao distorce quando as colunas sao redimensionadas.
      SB.Append(Format('<xdr:oneCellAnchor>' +
        '<xdr:from><xdr:col>%0:d</xdr:col><xdr:colOff>0</xdr:colOff>' +
        '<xdr:row>%1:d</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>' +
        '<xdr:ext cx="%2:d" cy="%3:d"/>' +
        '<xdr:pic><xdr:nvPicPr>' +
        '<xdr:cNvPr id="%4:d" name="Imagem %4:d"/><xdr:cNvPicPr/></xdr:nvPicPr>' +
        '<xdr:blipFill><a:blip r:embed="rId%4:d"/>' +
        '<a:stretch><a:fillRect/></a:stretch></xdr:blipFill>' +
        '<xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%2:d" cy="%3:d"/></a:xfrm>' +
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>' +
        '</xdr:pic><xdr:clientData/></xdr:oneCellAnchor>',
        [A.Col, A.Row, CX, CY, I + 1]));
    end;
    SB.Append('</xdr:wsDr>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TXlsxBuilder.Save(const FileName, SheetName: string);
var
  Pkg: TrhOoxmlPackage;
  Sheet, Styles, CtImg, CtDraw: string;
  DrawRels: TStringBuilder;
  I: Integer;
begin
  BuildGrid;
  // gerar sheet ANTES de styles: SheetXml popula FXfs via GetXfId
  Sheet := SheetXml;
  Styles := StylesXml;

  // partes extras do Content_Types quando ha imagens (png + o drawing)
  CtImg := ''; CtDraw := '';
  if FImages.Count > 0 then
  begin
    CtImg := '<Default Extension="png" ContentType="image/png"/>';
    CtDraw := '<Override PartName="/xl/drawings/drawing1.xml" ' +
      'ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>';
  end;

  Pkg := TrhOoxmlPackage.Create;
  try
    Pkg.AddXml('[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="xml" ContentType="application/xml"/>' +
      CtImg +
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
      CtDraw +
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
      '</Types>');

    Pkg.AddXml('_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
      '</Relationships>');

    Pkg.AddXml('xl/workbook.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' +
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
      '<sheets><sheet name="' + XmlEscape(SheetName) + '" sheetId="1" r:id="rId1"/></sheets>' +
      '</workbook>');

    Pkg.AddXml('xl/_rels/workbook.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' +
      '</Relationships>');

    Pkg.AddXml('xl/styles.xml', Styles);
    Pkg.AddXml('xl/worksheets/sheet1.xml', Sheet);

    // imagens: media PNG + drawing + rels (sheet->drawing e drawing->media)
    if FImages.Count > 0 then
    begin
      Pkg.AddXml('xl/worksheets/_rels/sheet1.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>' +
        '</Relationships>');

      Pkg.AddXml('xl/drawings/drawing1.xml', DrawingXml);

      DrawRels := TStringBuilder.Create;
      try
        DrawRels.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        DrawRels.Append('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
        for I := 0 to FImages.Count - 1 do
        begin
          Pkg.AddBytes(Format('xl/media/image%d.png', [I + 1]),
            ImagePngBytes(FImages[I].Op.Graphic));
          DrawRels.Append(Format('<Relationship Id="rId%0:d" ' +
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" ' +
            'Target="../media/image%0:d.png"/>', [I + 1]));
        end;
        DrawRels.Append('</Relationships>');
        Pkg.AddXml('xl/drawings/_rels/drawing1.xml.rels', DrawRels.ToString);
      finally
        DrawRels.Free;
      end;
    end;

    Pkg.SaveToFile(FileName);
  finally
    Pkg.Free;
  end;
end;

{ TrhXlsxExporter }

class procedure TrhXlsxExporter.ExportToFile(Doc: TrhRenderedDocument;
  const FileName, SheetName: string);
var
  Builder: TXlsxBuilder;
begin
  Builder := TXlsxBuilder.Create(Doc);
  try
    Builder.Save(FileName, SheetName);
  finally
    Builder.Free;
  end;
end;

end.
