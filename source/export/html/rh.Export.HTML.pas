{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Exportador HTML: reproduz um TrhRenderedDocument como paginas HTML com
///   elementos absolutamente posicionados (em mm). Consome a MESMA display list
///   do preview e dos demais exports — WYSIWYG. Imagens viram data-URI base64.
/// </summary>
unit rh.Export.HTML;

interface

uses
  rh.Render.Intf;

type
  TrhHtmlExporter = class
  public
    class function ExportToString(Doc: TrhRenderedDocument; const Title: string = ''): string;
    class procedure ExportToFile(Doc: TrhRenderedDocument; const FileName: string;
      const Title: string = '');
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Types, System.NetEncoding,
  Winapi.Windows, Vcl.Graphics, Vcl.Imaging.pngimage,
  rh.Types, rh.Model.Types;

var
  FS: TFormatSettings;

function MMStr(U: TrhUnit): string;
begin
  Result := Format('%.2f', [U / 10], FS);
end;

function ColorToHtml(C: TColor): string;
var
  RGB: Longint;
begin
  RGB := ColorToRGB(C);
  Result := Format('#%.2x%.2x%.2x', [GetRValue(RGB), GetGValue(RGB), GetBValue(RGB)]);
end;

function EscapeHtml(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '<br>', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '<br>', [rfReplaceAll]);
end;

function GraphicToDataURI(G: TGraphic): string;
var
  MS: TMemoryStream;
  PNG: TPngImage;
  BMP: TBitmap;
begin
  Result := '';
  if (G = nil) or (G.Width <= 0) or (G.Height <= 0) then Exit;
  MS := TMemoryStream.Create;
  BMP := TBitmap.Create;
  PNG := TPngImage.Create;
  try
    BMP.SetSize(G.Width, G.Height);
    BMP.Canvas.Brush.Color := clWhite;
    BMP.Canvas.FillRect(TRect.Create(0, 0, G.Width, G.Height));
    BMP.Canvas.Draw(0, 0, G);
    PNG.Assign(BMP);
    PNG.SaveToStream(MS);
    Result := 'data:image/png;base64,' +
      TNetEncoding.Base64.EncodeBytesToString(MS.Memory, Integer(MS.Size));
  finally
    PNG.Free;
    BMP.Free;
    MS.Free;
  end;
end;

function PosStyle(const R: TrhRectU): string;
begin
  Result := Format('left:%smm;top:%smm;width:%smm;height:%smm;',
    [MMStr(R.Left), MMStr(R.Top), MMStr(R.Width), MMStr(R.Height)]);
end;

procedure EmitTextOp(SB: TStringBuilder; Op: TrhDrawOp);
var
  Outer, Inner, VA, HA: string;
begin
  case Op.VAlign of
    rhvaCenter: VA := 'center';
    rhvaBottom: VA := 'flex-end';
  else
    VA := 'flex-start';
  end;
  case Op.HAlign of
    rhhaCenter:  HA := 'center';
    rhhaRight:   HA := 'right';
    rhhaJustify: HA := 'justify';
  else
    HA := 'left';
  end;
  // texto rotacionado (marca d'agua): centraliza dentro do box
  if Op.Angle <> 0 then
  begin
    VA := 'center';
    HA := 'center';
  end;

  Outer := PosStyle(Op.Rect) + 'display:flex;align-items:' + VA + ';';
  if Op.Angle <> 0 then
    // CSS rotate e horario; nosso angulo e anti-horario -> inverte o sinal
    Outer := Outer + 'justify-content:center;overflow:visible;transform-origin:center center;' +
      'transform:rotate(' + IntToStr(Round(-Op.Angle)) + 'deg);';
  if not Op.Transparent then
    Outer := Outer + 'background:' + ColorToHtml(Op.BackColor) + ';';
  if rhfsLeft in Op.FrameSides then
    Outer := Outer + 'border-left:' + MMStr(Op.FrameWidth) + 'mm solid ' + ColorToHtml(Op.FrameColor) + ';';
  if rhfsTop in Op.FrameSides then
    Outer := Outer + 'border-top:' + MMStr(Op.FrameWidth) + 'mm solid ' + ColorToHtml(Op.FrameColor) + ';';
  if rhfsRight in Op.FrameSides then
    Outer := Outer + 'border-right:' + MMStr(Op.FrameWidth) + 'mm solid ' + ColorToHtml(Op.FrameColor) + ';';
  if rhfsBottom in Op.FrameSides then
    Outer := Outer + 'border-bottom:' + MMStr(Op.FrameWidth) + 'mm solid ' + ColorToHtml(Op.FrameColor) + ';';

  Inner := Format('width:100%%;text-align:%s;font-family:''%s'',sans-serif;font-size:%dpt;color:%s;',
    [HA, Op.FontName, Op.FontSize, ColorToHtml(Op.FontColor)]);
  if fsBold in Op.FontStyle then Inner := Inner + 'font-weight:bold;';
  if fsItalic in Op.FontStyle then Inner := Inner + 'font-style:italic;';
  if fsUnderline in Op.FontStyle then Inner := Inner + 'text-decoration:underline;';
  if Op.WordWrap then Inner := Inner + 'white-space:pre-wrap;'
  else Inner := Inner + 'white-space:pre;';

  SB.Append('<div class="rh-obj" style="' + Outer + '"><div style="' + Inner + '">');
  SB.Append(EscapeHtml(Op.Text));
  SB.Append('</div></div>');
end;

procedure EmitShapeOp(SB: TStringBuilder; Op: TrhDrawOp);
var
  Style: string;
begin
  Style := PosStyle(Op.Rect) +
    'border:' + MMStr(Op.PenWidth) + 'mm solid ' + ColorToHtml(Op.PenColor) + ';';
  if not Op.BrushTransparent then
    Style := Style + 'background:' + ColorToHtml(Op.BrushColor) + ';';
  if Op.Kind = rhdkEllipse then
    Style := Style + 'border-radius:50%;'
  else if Op.RoundRect then
    Style := Style + 'border-radius:2mm;';
  SB.Append('<div class="rh-obj" style="' + Style + '"></div>');
end;

procedure EmitLineOp(SB: TStringBuilder; Op: TrhDrawOp);
var
  W, H: TrhUnit;
  Style, Col: string;
begin
  W := Op.Rect.Width;
  H := Op.Rect.Height;
  Col := ColorToHtml(Op.PenColor);
  if Abs(H) <= Op.PenWidth then
    Style := Format('left:%smm;top:%smm;width:%smm;height:0;border-top:%smm solid %s;',
      [MMStr(Op.Rect.Left), MMStr(Op.Rect.Top), MMStr(W), MMStr(Op.PenWidth), Col])
  else if Abs(W) <= Op.PenWidth then
    Style := Format('left:%smm;top:%smm;width:0;height:%smm;border-left:%smm solid %s;',
      [MMStr(Op.Rect.Left), MMStr(Op.Rect.Top), MMStr(H), MMStr(Op.PenWidth), Col])
  else
    Style := PosStyle(Op.Rect) + 'border:' + MMStr(Op.PenWidth) + 'mm solid ' + Col + ';';
  SB.Append('<div class="rh-obj" style="' + Style + '"></div>');
end;

procedure EmitPolygonOp(SB: TStringBuilder; Op: TrhDrawOp);
var
  I, MinX, MinY, MaxX, MaxY, W, H: TrhUnit;
  Pts, Fill, Stroke: string;
begin
  if Length(Op.Points) < 3 then Exit;
  MinX := Op.Points[0].X; MaxX := MinX;
  MinY := Op.Points[0].Y; MaxY := MinY;
  for I := 1 to High(Op.Points) do
  begin
    if Op.Points[I].X < MinX then MinX := Op.Points[I].X;
    if Op.Points[I].X > MaxX then MaxX := Op.Points[I].X;
    if Op.Points[I].Y < MinY then MinY := Op.Points[I].Y;
    if Op.Points[I].Y > MaxY then MaxY := Op.Points[I].Y;
  end;
  W := MaxX - MinX; H := MaxY - MinY;
  if (W <= 0) or (H <= 0) then Exit;
  Pts := '';
  for I := 0 to High(Op.Points) do
    Pts := Pts + IntToStr(Op.Points[I].X - MinX) + ',' +
                 IntToStr(Op.Points[I].Y - MinY) + ' ';
  if Op.BrushTransparent then Fill := 'none' else Fill := ColorToHtml(Op.BrushColor);
  if Op.PenWidth > 0 then Stroke := ColorToHtml(Op.PenColor) else Stroke := 'none';
  SB.Append(Format('<svg class="rh-obj" style="left:%smm;top:%smm;width:%smm;' +
    'height:%smm;overflow:visible;" viewBox="0 0 %d %d"><polygon points="%s" ' +
    'fill="%s" stroke="%s" stroke-width="%d"/></svg>',
    [MMStr(MinX), MMStr(MinY), MMStr(W), MMStr(H), W, H, Trim(Pts), Fill, Stroke,
     Op.PenWidth]));
end;

procedure EmitImageOp(SB: TStringBuilder; Op: TrhDrawOp);
var
  Fit, URI: string;
begin
  URI := GraphicToDataURI(Op.Graphic);
  if URI = '' then Exit;
  if not Op.Stretch then Fit := 'none'
  else if Op.KeepAspect then Fit := 'contain'
  else Fit := 'fill';
  SB.Append(Format('<img class="rh-obj" style="%sobject-fit:%s;" src="%s"/>',
    [PosStyle(Op.Rect), Fit, URI]));
end;

class function TrhHtmlExporter.ExportToString(Doc: TrhRenderedDocument; const Title: string): string;
var
  SB: TStringBuilder;
  Page: TrhRenderedPage;
  Op: TrhDrawOp;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('<!DOCTYPE html><html><head><meta charset="utf-8">');
    SB.Append('<title>' + EscapeHtml(Title) + '</title><style>');
    SB.Append('body{background:#e0e0e0;margin:0;padding:16px;}');
    SB.Append('.rh-page{position:relative;background:#fff;margin:0 auto 16px;' +
      'box-shadow:0 2px 8px rgba(0,0,0,.3);overflow:hidden;}');
    SB.Append('.rh-obj{position:absolute;box-sizing:border-box;overflow:hidden;}');
    SB.Append('@media print{body{background:#fff;padding:0;}' +
      '.rh-page{box-shadow:none;margin:0;page-break-after:always;}}');
    SB.Append('</style></head><body>');

    if Doc <> nil then
      for Page in Doc.Pages do
      begin
        SB.Append(Format('<div class="rh-page" style="width:%smm;height:%smm;">',
          [MMStr(Page.Width), MMStr(Page.Height)]));
        for Op in Page.Ops do
          case Op.Kind of
            rhdkText:    EmitTextOp(SB, Op);
            rhdkLine:    EmitLineOp(SB, Op);
            rhdkRect,
            rhdkEllipse: EmitShapeOp(SB, Op);
            rhdkPolygon: EmitPolygonOp(SB, Op);
            rhdkImage:   EmitImageOp(SB, Op);
          end;
        SB.Append('</div>');
      end;

    SB.Append('</body></html>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class procedure TrhHtmlExporter.ExportToFile(Doc: TrhRenderedDocument;
  const FileName, Title: string);
var
  Bytes: TBytes;
  FStream: TFileStream;
begin
  Bytes := TEncoding.UTF8.GetBytes(ExportToString(Doc, Title));
  FStream := TFileStream.Create(FileName, fmCreate);
  try
    if Length(Bytes) > 0 then
      FStream.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    FStream.Free;
  end;
end;

initialization
  FS := TFormatSettings.Invariant;

end.
