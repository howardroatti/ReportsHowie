{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Motor de renderizacao: percorre o modelo (paginas -> bandas -> objetos) e
///   produz um TrhRenderedDocument (display list). Esta e a UNICA logica de
///   layout, compartilhada por preview e por todos os exports.
///
///   FASE 2: layout ESTATICO do template — as bandas sao empilhadas na ordem
///   declarada, com quebra de pagina por transbordo. A iteracao de dados
///   (master/detail, grupos, repeticao de cabecalho/rodape) entra na Fase 4.
/// </summary>
unit rh.Render.Engine;

interface

uses
  rh.Report, rh.Render.Intf;

type
  TrhRenderEngine = class
  public
    /// <summary>Constroi o documento renderizado a partir do relatorio. O chamador e dono do resultado.</summary>
    class function BuildDocument(Report: TrhReport): TrhRenderedDocument;
  end;

implementation

uses
  Vcl.Graphics, rh.Types, rh.Model.Types, rh.Page, rh.Bands, rh.Objects;

procedure EmitObject(RP: TrhRenderedPage; Obj: TrhReportObject; OriginX, OriginY: TrhUnit);
var
  Op: TrhDrawOp;
  L, T: TrhUnit;
  Txt: TrhTextObject;
  Img: TrhImageObject;
  Lin: TrhLineObject;
  Shp: TrhShapeObject;
begin
  if not Obj.Visible then Exit;
  L := OriginX + Obj.Left;
  T := OriginY + Obj.Top;

  if Obj is TrhTextObject then
  begin
    Txt := TrhTextObject(Obj);
    Op := RP.AddOp(rhdkText);
    Op.Rect := TrhRectU.Create(L, T, Obj.Width, Obj.Height);
    Op.Text := Txt.Text;
    Op.FontName := Txt.Font.Name;
    Op.FontSize := Txt.Font.Size;
    Op.FontStyle := Txt.Font.Style;
    Op.FontColor := Txt.Font.Color;
    Op.HAlign := Txt.HAlign;
    Op.VAlign := Txt.VAlign;
    Op.WordWrap := Txt.WordWrap;
    Op.BackColor := Txt.Color;
    Op.Transparent := Txt.Transparent;
    Op.FrameSides := Obj.Frame.Sides;
    Op.FrameColor := Obj.Frame.Color;
    Op.FrameWidth := Obj.Frame.Width;
  end
  else if Obj is TrhImageObject then
  begin
    Img := TrhImageObject(Obj);
    Op := RP.AddOp(rhdkImage);
    Op.Rect := TrhRectU.Create(L, T, Obj.Width, Obj.Height);
    if (Img.Picture <> nil) and (Img.Picture.Graphic <> nil) and
       (not Img.Picture.Graphic.Empty) then
      Op.Graphic := Img.Picture.Graphic;
    Op.Stretch := Img.Stretch;
    Op.KeepAspect := Img.KeepAspect;
    Op.Center := Img.Center;
    Op.FrameSides := Obj.Frame.Sides;
    Op.FrameColor := Obj.Frame.Color;
    Op.FrameWidth := Obj.Frame.Width;
  end
  else if Obj is TrhLineObject then
  begin
    Lin := TrhLineObject(Obj);
    Op := RP.AddOp(rhdkLine);
    Op.Rect := TrhRectU.Create(L, T, Obj.Width, Obj.Height);
    Op.PenColor := Lin.PenColor;
    Op.PenWidth := Lin.PenWidth;
  end
  else if Obj is TrhShapeObject then
  begin
    Shp := TrhShapeObject(Obj);
    if Shp.Kind = rhskEllipse then
      Op := RP.AddOp(rhdkEllipse)
    else
      Op := RP.AddOp(rhdkRect);
    Op.Rect := TrhRectU.Create(L, T, Obj.Width, Obj.Height);
    Op.RoundRect := Shp.Kind = rhskRoundRect;
    Op.PenColor := Shp.PenColor;
    Op.PenWidth := Shp.PenWidth;
    Op.BrushColor := Shp.BrushColor;
    Op.BrushTransparent := Shp.Transparent;
  end;
end;

procedure EmitBand(RP: TrhRenderedPage; Band: TrhBand; OriginX, BandTop: TrhUnit);
var
  Obj: TrhReportObject;
begin
  for Obj in Band.Objects do
    EmitObject(RP, Obj, OriginX, BandTop);
end;

class function TrhRenderEngine.BuildDocument(Report: TrhReport): TrhRenderedDocument;
var
  Page: TrhPage;
  Band: TrhBand;
  RP: TrhRenderedPage;
  CurY, ContentBottom: TrhUnit;
begin
  Result := TrhRenderedDocument.Create;
  if Report = nil then Exit;

  for Page in Report.Pages do
  begin
    RP := Result.AddPage(Page.EffectiveWidth, Page.EffectiveHeight);
    CurY := Page.MarginTop;
    ContentBottom := Page.MarginTop + Page.ContentHeight;

    for Band in Page.Bands do
    begin
      if not Band.Visible then Continue;

      // quebra de pagina por transbordo (mantendo ao menos uma banda por pagina)
      if (CurY + Band.Height > ContentBottom) and (CurY > Page.MarginTop) then
      begin
        RP := Result.AddPage(Page.EffectiveWidth, Page.EffectiveHeight);
        CurY := Page.MarginTop;
      end;

      EmitBand(RP, Band, Page.MarginLeft, CurY);
      CurY := CurY + Band.Height;
    end;
  end;
end;

end.
