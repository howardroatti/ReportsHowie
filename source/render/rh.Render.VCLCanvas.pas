{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Renderizador VCL: reproduz um TrhRenderedPage em um TCanvas (tela, para o
///   preview e para a superficie do designer) e imprime o documento via
///   TPrinter. A escala e dada em PIXELS POR UNIDADE de relatorio (0,1 mm).
/// </summary>
unit rh.Render.VCLCanvas;

interface

uses
  Vcl.Graphics, rh.Render.Intf;

type
  TrhVCLRenderer = class
  public
    /// <summary>Desenha uma pagina renderizada no canvas. Scale = pixels por unidade (0,1 mm).</summary>
    class procedure DrawPage(Canvas: TCanvas; Page: TrhRenderedPage;
      Scale: Double; OffsetX: Integer = 0; OffsetY: Integer = 0);
    /// <summary>Envia o documento para a impressora padrao.</summary>
    class procedure PrintDocument(Doc: TrhRenderedDocument; const Title: string);
  end;

implementation

uses
  Winapi.Windows, System.Types, System.Math, Vcl.Printers,
  rh.Types, rh.Model.Types;

class procedure TrhVCLRenderer.DrawPage(Canvas: TCanvas; Page: TrhRenderedPage;
  Scale: Double; OffsetX, OffsetY: Integer);
var
  Op: TrhDrawOp;
  R: TRect;
  Flags: Cardinal;
  DrawR: TRect;
  gw, gh: Integer;
  sc: Double;
  tw, th, tx, ty: Integer;

  function PX(u: TrhUnit): Integer;
  begin
    Result := OffsetX + Round(u * Scale);
  end;
  function PY(u: TrhUnit): Integer;
  begin
    Result := OffsetY + Round(u * Scale);
  end;
  function PenPx(u: TrhUnit): Integer;
  begin
    Result := Max(1, Round(u * Scale));
  end;

begin
  for Op in Page.Ops do
  begin
    R := TRect.Create(PX(Op.Rect.Left), PY(Op.Rect.Top),
                      PX(Op.Rect.Right), PY(Op.Rect.Bottom));
    case Op.Kind of
      rhdkText:
        begin
          if not Op.Transparent then
          begin
            Canvas.Brush.Style := bsSolid;
            Canvas.Brush.Color := Op.BackColor;
            Canvas.FillRect(R);
          end;
          // moldura
          if Op.FrameSides <> [] then
          begin
            Canvas.Pen.Color := Op.FrameColor;
            Canvas.Pen.Width := PenPx(Op.FrameWidth);
            Canvas.Pen.Style := psSolid;
            if rhfsLeft in Op.FrameSides then
            begin
              Canvas.MoveTo(R.Left, R.Top); Canvas.LineTo(R.Left, R.Bottom);
            end;
            if rhfsTop in Op.FrameSides then
            begin
              Canvas.MoveTo(R.Left, R.Top); Canvas.LineTo(R.Right, R.Top);
            end;
            if rhfsRight in Op.FrameSides then
            begin
              Canvas.MoveTo(R.Right, R.Top); Canvas.LineTo(R.Right, R.Bottom);
            end;
            if rhfsBottom in Op.FrameSides then
            begin
              Canvas.MoveTo(R.Left, R.Bottom); Canvas.LineTo(R.Right, R.Bottom);
            end;
          end;
          // texto
          Canvas.Font.Name := Op.FontName;
          Canvas.Font.Style := Op.FontStyle;
          Canvas.Font.Color := Op.FontColor;
          Canvas.Font.Height := -Round(Op.FontSize * Scale * 254 / 72);
          Canvas.Brush.Style := bsClear;
          Flags := DT_NOPREFIX;
          case Op.HAlign of
            rhhaCenter: Flags := Flags or DT_CENTER;
            rhhaRight:  Flags := Flags or DT_RIGHT;
          else
            Flags := Flags or DT_LEFT;
          end;
          if Op.WordWrap then
            Flags := Flags or DT_WORDBREAK
          else
          begin
            Flags := Flags or DT_SINGLELINE;
            case Op.VAlign of
              rhvaCenter: Flags := Flags or DT_VCENTER;
              rhvaBottom: Flags := Flags or DT_BOTTOM;
            else
              Flags := Flags or DT_TOP;
            end;
          end;
          DrawR := R;
          Winapi.Windows.DrawText(Canvas.Handle, PChar(Op.Text), Length(Op.Text),
            DrawR, Flags);
        end;

      rhdkLine:
        begin
          Canvas.Pen.Color := Op.PenColor;
          Canvas.Pen.Width := PenPx(Op.PenWidth);
          Canvas.Pen.Style := psSolid;
          Canvas.MoveTo(R.Left, R.Top);
          Canvas.LineTo(R.Right, R.Bottom);
        end;

      rhdkRect, rhdkEllipse:
        begin
          Canvas.Pen.Color := Op.PenColor;
          Canvas.Pen.Width := PenPx(Op.PenWidth);
          Canvas.Pen.Style := psSolid;
          if Op.BrushTransparent then
            Canvas.Brush.Style := bsClear
          else
          begin
            Canvas.Brush.Style := bsSolid;
            Canvas.Brush.Color := Op.BrushColor;
          end;
          if Op.Kind = rhdkEllipse then
            Canvas.Ellipse(R)
          else if Op.RoundRect then
            Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom,
              PenPx(30), PenPx(30))
          else
            Canvas.Rectangle(R);
        end;

      rhdkImage:
        begin
          if Op.Graphic = nil then Continue;
          gw := Op.Graphic.Width;
          gh := Op.Graphic.Height;
          if (gw <= 0) or (gh <= 0) then Continue;
          if not Op.Stretch then
          begin
            // tamanho natural, opcionalmente centralizado
            tw := gw; th := gh;
            if Op.Center then
            begin
              tx := R.Left + ((R.Width - tw) div 2);
              ty := R.Top + ((R.Height - th) div 2);
            end
            else
            begin
              tx := R.Left; ty := R.Top;
            end;
            Canvas.Draw(tx, ty, Op.Graphic);
          end
          else if Op.KeepAspect then
          begin
            sc := Min(R.Width / gw, R.Height / gh);
            tw := Round(gw * sc);
            th := Round(gh * sc);
            tx := R.Left + ((R.Width - tw) div 2);
            ty := R.Top + ((R.Height - th) div 2);
            Canvas.StretchDraw(TRect.Create(tx, ty, tx + tw, ty + th), Op.Graphic);
          end
          else
            Canvas.StretchDraw(R, Op.Graphic);
        end;
    end;
  end;
end;

class procedure TrhVCLRenderer.PrintDocument(Doc: TrhRenderedDocument; const Title: string);
var
  I, DpiX: Integer;
  Scale: Double;
begin
  if (Doc = nil) or (Doc.PageCount = 0) then Exit;
  Printer.Title := Title;
  Printer.BeginDoc;
  try
    for I := 0 to Doc.PageCount - 1 do
    begin
      if I > 0 then Printer.NewPage;
      DpiX := GetDeviceCaps(Printer.Canvas.Handle, LOGPIXELSX);
      Scale := DpiX / 254; // pixels por unidade (254 unidades = 1 polegada)
      DrawPage(Printer.Canvas, Doc.Pages[I], Scale, 0, 0);
    end;
  finally
    Printer.EndDoc;
  end;
end;

end.
