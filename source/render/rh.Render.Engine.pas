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
  rh.Types, rh.Bands, rh.Report, rh.Render.Intf, rh.Expr.Nodes;

type
  TrhRenderEngine = class
  public
    /// <summary>
    ///   Constroi o documento renderizado a partir do relatorio. Se Ctx for
    ///   informado, os textos com ilhas [expr] sao avaliados; senao ficam
    ///   literais (util para preview do template em design-time).
    ///   O chamador e dono do resultado.
    /// </summary>
    class function BuildDocument(Report: TrhReport;
      const Ctx: IrhEvalContext = nil): TrhRenderedDocument;

    /// <summary>Emite os objetos de uma banda numa pagina (usado pelo pipeline de dados).</summary>
    class procedure EmitBand(RP: TrhRenderedPage; Band: TrhBand;
      OriginX, BandTop: TrhUnit; const Ctx: IrhEvalContext);

    /// <summary>Emite a marca d'agua ao fundo da pagina (se habilitada). Deve ser
    ///  chamada logo apos criar a pagina, antes das bandas, para ficar por baixo.</summary>
    class procedure EmitWatermark(RP: TrhRenderedPage; Report: TrhReport;
      const Ctx: IrhEvalContext);
  end;

implementation

uses
  System.SysUtils, System.Math, System.UITypes,
  Vcl.Graphics, rh.Model.Types, rh.Page, rh.Objects, rh.Expr, rh.Barcode,
  rh.QRCode, rh.Watermark;

const
  RH_CHART_PALETTE: array[0..7] of TColor = (
    $00C08040, $004080E0, $0050B050, $00A050C0,
    $0030C0C0, $004040D0, $00C060A0, $0080C040);

function ChartPalette(I: Integer): TColor;
begin
  Result := RH_CHART_PALETTE[I mod Length(RH_CHART_PALETTE)];
end;

// pt (tamanho de fonte) -> unidades de relatorio (0,1 mm)
function PtToUnits(Pt: Integer): Integer;
begin
  Result := Round(Pt * 254 / 72);
end;

// Desenha um grafico (barras/linhas/pizza) a partir da serie agregada.
procedure EmitChart(RP: TrhRenderedPage; Chart: TrhChartObject; L, T: TrhUnit);
var
  W, H, TitleH, LabelH, ValueH, PlotL, PlotT, PlotR, PlotB, PlotW, PlotH: Integer;
  N, I, J, Slot, BarW, BX, BH, BY, PX, PY, PrevX, PrevY: Integer;
  MaxV, MinV, TotalV, A0, A1, Ang, CX, CY, Rad: Double;
  Op: TrhDrawOp;
  S: TArray<TrhChartPoint>;

  procedure Lbl(ALeft, ATop, AWidth, AHeight: Integer; const AText: string;
    AHAlign: TrhHAlign; ABold: Boolean);
  var
    TO_: TrhDrawOp;
  begin
    TO_ := RP.AddOp(rhdkText);
    TO_.Rect := TrhRectU.Create(ALeft, ATop, AWidth, AHeight);
    TO_.Text := AText;
    TO_.FontName := Chart.Font.Name;
    TO_.FontSize := Chart.Font.Size;
    if ABold then TO_.FontStyle := [fsBold] else TO_.FontStyle := [];
    TO_.FontColor := Chart.Font.Color;
    TO_.HAlign := AHAlign;
    TO_.VAlign := rhvaCenter;
    TO_.WordWrap := False;
    TO_.Transparent := True;
  end;

  function Fmt(V: Double): string;
  begin
    Result := FormatFloat('#,##0.##', V);
  end;

begin
  S := Chart.Series;
  N := Length(S);
  W := Chart.Width; H := Chart.Height;

  TitleH := 0;
  if Chart.Title <> '' then TitleH := Round(PtToUnits(Chart.Font.Size) * 1.6);
  if N = 0 then
  begin
    if Chart.Title <> '' then Lbl(L, T, W, TitleH, Chart.Title, rhhaCenter, True);
    Lbl(L, T + TitleH, W, H - TitleH, '(sem dados)', rhhaCenter, False);
    Exit;
  end;
  if Chart.Title <> '' then Lbl(L, T, W, TitleH, Chart.Title, rhhaCenter, True);

  if Chart.ChartType = rhctPie then
  begin
    // area do grafico: reserva ~40% a direita para legenda (se ShowLegend)
    CX := L + W * 0.30;
    CY := T + TitleH + (H - TitleH) / 2;
    if Chart.ShowLegend then
      Rad := Min(W * 0.28, (H - TitleH) * 0.45)
    else
    begin
      CX := L + W / 2;
      Rad := Min(W * 0.45, (H - TitleH) * 0.45);
    end;
    TotalV := 0;
    for I := 0 to N - 1 do TotalV := TotalV + Abs(S[I].Value);
    if TotalV <= 0 then TotalV := 1;
    A0 := -PI / 2; // comeca no topo
    for I := 0 to N - 1 do
    begin
      A1 := A0 + 2 * PI * Abs(S[I].Value) / TotalV;
      Op := RP.AddOp(rhdkPolygon);
      Op.BrushColor := ChartPalette(I);
      Op.BrushTransparent := False;
      Op.PenColor := clWhite;
      Op.PenWidth := 3;
      // vertices: centro + arco (passo ~5 graus)
      J := Max(2, Round((A1 - A0) / (PI / 36)));
      SetLength(Op.Points, J + 2);
      Op.Points[0].X := Round(CX); Op.Points[0].Y := Round(CY);
      for BX := 0 to J do
      begin
        Ang := A0 + (A1 - A0) * BX / J;
        Op.Points[BX + 1].X := Round(CX + Rad * Cos(Ang));
        Op.Points[BX + 1].Y := Round(CY + Rad * Sin(Ang));
      end;
      A0 := A1;
    end;
    // legenda a direita
    if Chart.ShowLegend then
    begin
      LabelH := Round(PtToUnits(Chart.Font.Size) * 1.4);
      PY := Round(CY - (N * LabelH) / 2);
      PX := L + Round(W * 0.60);
      for I := 0 to N - 1 do
      begin
        Op := RP.AddOp(rhdkRect);
        Op.Rect := TrhRectU.Create(PX, PY + I * LabelH + LabelH div 4,
          LabelH div 2, LabelH div 2);
        Op.PenColor := ChartPalette(I); Op.PenWidth := 0;
        Op.BrushColor := ChartPalette(I); Op.BrushTransparent := False;
        Lbl(PX + LabelH, PY + I * LabelH, W - (PX - L) - LabelH, LabelH,
          S[I].Category + ' (' + Fmt(S[I].Value) + ')', rhhaLeft, False);
      end;
    end;
    Exit;
  end;

  // ----- barras e linhas -----
  LabelH := Round(PtToUnits(Chart.Font.Size) * 1.4);
  if Chart.ShowValues then ValueH := LabelH else ValueH := 0;
  PlotL := L;
  PlotR := L + W;
  PlotT := T + TitleH + ValueH;
  PlotB := T + H - LabelH;
  PlotW := PlotR - PlotL;
  PlotH := PlotB - PlotT;
  if PlotH < 10 then PlotH := 10;

  MaxV := 0; MinV := 0;
  for I := 0 to N - 1 do
  begin
    MaxV := Max(MaxV, S[I].Value);
    MinV := Min(MinV, S[I].Value);
  end;
  if MaxV <= 0 then MaxV := 1;

  // linha de base
  Op := RP.AddOp(rhdkLine);
  Op.Rect := TrhRectU.Create(PlotL, PlotB, PlotW, 0);
  Op.PenColor := clSilver; Op.PenWidth := 2;

  Slot := PlotW div N;
  if Slot < 1 then Slot := 1;

  if Chart.ChartType = rhctBar then
  begin
    BarW := Round(Slot * 0.6);
    if BarW > 300 then BarW := 300;   // teto ~30mm: evita barras gigantes com poucas categorias
    if BarW < 1 then BarW := 1;
    for I := 0 to N - 1 do
    begin
      BH := Round(S[I].Value / MaxV * PlotH);
      if BH < 0 then BH := 0;
      BX := PlotL + I * Slot + (Slot - BarW) div 2;
      BY := PlotB - BH;
      Op := RP.AddOp(rhdkRect);
      Op.Rect := TrhRectU.Create(BX, BY, BarW, BH);
      Op.PenColor := Chart.BarColor; Op.PenWidth := 0;
      Op.BrushColor := Chart.BarColor; Op.BrushTransparent := False;
      if Chart.ShowValues then
        Lbl(PlotL + I * Slot, BY - ValueH, Slot, ValueH, Fmt(S[I].Value), rhhaCenter, False);
      Lbl(PlotL + I * Slot, PlotB, Slot, LabelH, S[I].Category, rhhaCenter, False);
    end;
  end
  else // rhctLine
  begin
    PrevX := 0; PrevY := 0;
    for I := 0 to N - 1 do
    begin
      PX := PlotL + I * Slot + Slot div 2;
      PY := PlotB - Round(S[I].Value / MaxV * PlotH);
      if I > 0 then
      begin
        Op := RP.AddOp(rhdkLine);
        Op.Rect := TrhRectU.Create(PrevX, PrevY, PX - PrevX, PY - PrevY);
        Op.PenColor := Chart.BarColor; Op.PenWidth := 5;
      end;
      // marcador
      Op := RP.AddOp(rhdkRect);
      Op.Rect := TrhRectU.Create(PX - 8, PY - 8, 16, 16);
      Op.PenColor := Chart.BarColor; Op.PenWidth := 0;
      Op.BrushColor := Chart.BarColor; Op.BrushTransparent := False;
      if Chart.ShowValues then
        Lbl(PlotL + I * Slot, PY - ValueH, Slot, ValueH, Fmt(S[I].Value), rhhaCenter, False);
      Lbl(PlotL + I * Slot, PlotB, Slot, LabelH, S[I].Category, rhhaCenter, False);
      PrevX := PX; PrevY := PY;
    end;
  end;
end;

// Expande um QR Code em retangulos (modulos escuros), coalescendo runs por linha.
procedure EmitQR(RP: TrhRenderedPage; Bar: TrhBarcodeObject;
  L, T: TrhUnit; const Data: string);
var
  QR: TrhQRMatrix;
  Side, ModSize, OffX, OffY, R, C, RunStart: Integer;
  Op: TrhDrawOp;
begin
  QR := rhEncodeQR(Data);
  if QR.Size = 0 then Exit;
  if Bar.Width < Bar.Height then Side := Bar.Width else Side := Bar.Height;
  if Bar.ModuleWidth > 0 then
    ModSize := Bar.ModuleWidth
  else
    ModSize := Side div QR.Size;
  if ModSize < 1 then ModSize := 1;
  OffX := L + (Bar.Width - ModSize * QR.Size) div 2;
  OffY := T + (Bar.Height - ModSize * QR.Size) div 2;
  for R := 0 to QR.Size - 1 do
  begin
    C := 0;
    while C < QR.Size do
      if QR.IsDark(R, C) then
      begin
        RunStart := C;
        while (C < QR.Size) and QR.IsDark(R, C) do Inc(C);
        Op := RP.AddOp(rhdkRect);
        Op.Rect := TrhRectU.Create(OffX + RunStart * ModSize, OffY + R * ModSize,
          (C - RunStart) * ModSize, ModSize);
        Op.PenColor := Bar.BarColor;
        Op.PenWidth := 0;
        Op.BrushColor := Bar.BarColor;
        Op.BrushTransparent := False;
      end
      else
        Inc(C);
  end;
end;

// Expande um codigo de barras em retangulos (barras) + texto opcional legivel.
procedure EmitBarcode(RP: TrhRenderedPage; Bar: TrhBarcodeObject;
  L, T: TrhUnit; const Data: string);
var
  Pat: TrhBarPattern;
  TotalMods, ModW, BarsH, TextH, ActualW, X, W, I: Integer;
  Op: TrhDrawOp;
begin
  Pat := rhEncodeBarcode(Bar.Symbology, Data);
  if Length(Pat) = 0 then Exit;
  TotalMods := rhBarPatternModules(Pat);
  if TotalMods <= 0 then Exit;

  // largura do modulo: fixa (ModuleWidth) ou auto-ajustada para preencher Width
  if Bar.ModuleWidth > 0 then
    ModW := Bar.ModuleWidth
  else
    ModW := Bar.Width div TotalMods;
  if ModW < 1 then ModW := 1;

  // reserva faixa inferior para o texto legivel (converte pt -> 0,1 mm)
  if Bar.ShowText then
    TextH := Round(Bar.Font.Size * 254 / 72 * 1.3)
  else
    TextH := 0;
  BarsH := Bar.Height - TextH;
  if BarsH < 1 then
  begin
    BarsH := Bar.Height;
    TextH := 0;
  end;

  // centraliza o simbolo na largura do objeto
  ActualW := ModW * TotalMods;
  X := L + ((Bar.Width - ActualW) div 2);
  if X < L then X := L;

  for I := 0 to High(Pat) do
  begin
    W := Pat[I] * ModW;
    if (I and 1) = 0 then // indice par = barra (impar = espaco: nao desenha)
    begin
      Op := RP.AddOp(rhdkRect);
      Op.Rect := TrhRectU.Create(X, T, W, BarsH);
      Op.PenColor := Bar.BarColor;      // pen = brush -> barra solida, sem artefato
      Op.PenWidth := 0;
      Op.BrushColor := Bar.BarColor;
      Op.BrushTransparent := False;
    end;
    X := X + W;
  end;

  if TextH > 0 then
  begin
    Op := RP.AddOp(rhdkText);
    Op.Rect := TrhRectU.Create(L, T + BarsH, Bar.Width, TextH);
    Op.Text := Data;
    Op.FontName := Bar.Font.Name;
    Op.FontSize := Bar.Font.Size;
    Op.FontStyle := Bar.Font.Style;
    Op.FontColor := Bar.Font.Color;
    Op.HAlign := rhhaCenter;
    Op.VAlign := rhvaCenter;
    Op.WordWrap := False;
    Op.Transparent := True;
  end;
end;

procedure EmitObject(RP: TrhRenderedPage; Obj: TrhReportObject;
  OriginX, OriginY: TrhUnit; const Ctx: IrhEvalContext);
var
  Op: TrhDrawOp;
  L, T: TrhUnit;
  Txt: TrhTextObject;
  Img: TrhImageObject;
  Lin: TrhLineObject;
  Shp: TrhShapeObject;
  Bar: TrhBarcodeObject;
  BarData: string;
begin
  if not Obj.Visible then Exit;
  L := OriginX + Obj.Left;
  T := OriginY + Obj.Top;

  if Obj is TrhTextObject then
  begin
    Txt := TrhTextObject(Obj);
    Op := RP.AddOp(rhdkText);
    Op.Rect := TrhRectU.Create(L, T, Obj.Width, Obj.Height);
    if Ctx <> nil then
      Op.Text := rhEvalText(Txt.DisplayExpression, Ctx)
    else
      Op.Text := Txt.DisplayExpression;
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
    begin
      // clona o grafico p/ a display list ser autossuficiente: o relatorio (e sua
      // TPicture) pode ser liberado antes do preview/export consumir o documento.
      Op.Graphic := TGraphicClass(Img.Picture.Graphic.ClassType).Create;
      Op.Graphic.Assign(Img.Picture.Graphic);
      Op.OwnsGraphic := True;
    end;
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
  end
  else if Obj is TrhBarcodeObject then
  begin
    Bar := TrhBarcodeObject(Obj);
    if Ctx <> nil then
      BarData := rhEvalText(Bar.DisplayExpression, Ctx)
    else
      BarData := Bar.DisplayExpression;
    if Bar.Symbology = rhbcQRCode then
      EmitQR(RP, Bar, L, T, BarData)
    else
      EmitBarcode(RP, Bar, L, T, BarData);
  end
  else if Obj is TrhChartObject then
    EmitChart(RP, TrhChartObject(Obj), L, T);
end;

procedure DoEmitBand(RP: TrhRenderedPage; Band: TrhBand; OriginX, BandTop: TrhUnit;
  const Ctx: IrhEvalContext);
var
  Obj: TrhReportObject;
begin
  for Obj in Band.Objects do
    EmitObject(RP, Obj, OriginX, BandTop, Ctx);
end;

class procedure TrhRenderEngine.EmitBand(RP: TrhRenderedPage; Band: TrhBand;
  OriginX, BandTop: TrhUnit; const Ctx: IrhEvalContext);
begin
  DoEmitBand(RP, Band, OriginX, BandTop, Ctx);
end;

class procedure TrhRenderEngine.EmitWatermark(RP: TrhRenderedPage; Report: TrhReport;
  const Ctx: IrhEvalContext);
var
  Wm: TrhWatermark;
  Op: TrhDrawOp;
begin
  if Report = nil then Exit;
  Wm := Report.Watermark;
  if (Wm = nil) or (not Wm.Visible) or (Wm.Text = '') then Exit;

  Op := RP.AddOp(rhdkText);
  Op.Rect := TrhRectU.Create(0, 0, RP.Width, RP.Height); // pagina inteira; centraliza
  if Ctx <> nil then
    Op.Text := rhEvalText(Wm.Text, Ctx)
  else
    Op.Text := Wm.Text;
  Op.FontName := Wm.Font.Name;
  Op.FontSize := Wm.Font.Size;
  Op.FontStyle := Wm.Font.Style;
  Op.FontColor := Wm.Font.Color;
  Op.HAlign := rhhaCenter;
  Op.VAlign := rhvaCenter;
  Op.WordWrap := False;
  Op.Transparent := True;
  Op.Angle := Wm.Angle;
end;

class function TrhRenderEngine.BuildDocument(Report: TrhReport;
  const Ctx: IrhEvalContext): TrhRenderedDocument;
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
    EmitWatermark(RP, Report, Ctx); // fundo, antes das bandas
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

      DoEmitBand(RP, Band, Page.MarginLeft, CurY, Ctx);
      CurY := CurY + Band.Height;
    end;
  end;
end;

end.
