{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Superficie de design (editor visual por bandas). E um TCustomControl puro
///   VCL — LIVRE de DesignIntf — para poder ser reutilizado tanto no designer
///   do IDE (Fase 5) quanto no designer em runtime (Fase 10).
///
///   Layout: as bandas do 1o template sao empilhadas verticalmente como faixas
///   (strips) de largura = area util da pagina; os objetos sao posicionados por
///   (Left, Top) RELATIVOS ao canto superior-esquerdo da area de conteudo da
///   banda — exatamente como o motor de render os emite. Suporta selecao,
///   mover, redimensionar (8 alcas), snap-to-grid e resize de altura de banda.
/// </summary>
unit rh.Design.Surface;

interface

uses
  System.Classes, System.Generics.Collections, System.Types,
  Winapi.Windows, Winapi.Messages, Vcl.Controls, Vcl.Graphics,
  rh.Types, rh.Model.Types, rh.Objects, rh.Bands, rh.Page, rh.Report;

const
  RH_GUTTER   = 132; // faixa esquerda com rotulos de banda (px)
  RH_TOPPAD   = 10;  // respiro no topo/laterais (px)
  RH_HANDLE   = 7;   // tamanho da alca de selecao (px)
  RH_BANDGRIP = 5;   // zona de arraste da borda inferior da banda (px)

type
  TrhDesignHandle = (dhNone, dhMove, dhL, dhR, dhT, dhB, dhTL, dhTR, dhBL, dhBR);

  TrhBandLayout = record
    Band: TrhBand;
    TopPx, HeightPx: Integer;
  end;

  TrhDesignSurface = class(TCustomControl)
  private
    FReport: TrhReport;
    FPage: TrhPage;
    FZoom: Integer;
    FGridSize: TrhUnit;
    FSnap: Boolean;
    FSelObj: TrhReportObject;
    FSelBand: TrhBand;
    FLayouts: TList<TrhBandLayout>;
    FOnModified: TNotifyEvent;
    FOnSelChanged: TNotifyEvent;
    // interacao
    FDragging: Boolean;
    FDragHandle: TrhDesignHandle;
    FDragStart: TPoint;
    FObjStart: TRect;          // Left/Top/Right/Bottom em unidades
    FBandResizing: TrhBand;
    FBandStartH: TrhUnit;
    function Scale: Double;
    procedure Recalc;
    function ContentWidthPx: Integer;
    function FindBandAtY(Y: Integer; out Lay: TrhBandLayout): Boolean;
    function LayoutOf(Band: TrhBand; out Lay: TrhBandLayout): Boolean;
    function ObjRectPx(const Lay: TrhBandLayout; Obj: TrhReportObject): TRect;
    function HandleAtPoint(const R: TRect; const P: TPoint): TrhDesignHandle;
    function BandBottomGripAt(const P: TPoint; out Band: TrhBand): Boolean;
    procedure DrawBandStrip(const Lay: TrhBandLayout);
    procedure DrawObject(const Lay: TrhBandLayout; Obj: TrhReportObject);
    procedure DrawSelection(const R: TRect);
    procedure DoModified;
    procedure DoSelChanged;
    procedure SetZoom(V: Integer);
    procedure SetSelObj(V: TrhReportObject);
    function SnapU(V: TrhUnit): TrhUnit;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadReport(AReport: TrhReport);
    procedure RebuildLayout;
    procedure AddObjectOfClass(AClass: TrhReportObjectClass);
    procedure DeleteSelected;
    procedure AddBand(BandType: TrhBandType);
    procedure DeleteSelectedBand;
    property Report: TrhReport read FReport;
    property Selected: TrhReportObject read FSelObj write SetSelObj;
    property SelectedBand: TrhBand read FSelBand;
    property Zoom: Integer read FZoom write SetZoom;
    property Snap: Boolean read FSnap write FSnap;
    property GridSize: TrhUnit read FGridSize write FGridSize;
    property OnModified: TNotifyEvent read FOnModified write FOnModified;
    property OnSelectionChanged: TNotifyEvent read FOnSelChanged write FOnSelChanged;
  end;

/// <summary>Rotulo amigavel do tipo de banda (para o gutter).</summary>
function BandCaption(BT: TrhBandType): string;

implementation

uses
  System.SysUtils, System.Math, Vcl.Dialogs;

function BandCaption(BT: TrhBandType): string;
begin
  case BT of
    rhbtReportTitle: Result := 'Titulo';
    rhbtPageHeader:  Result := 'Cabecalho Pagina';
    rhbtPageFooter:  Result := 'Rodape Pagina';
    rhbtGroupHeader: Result := 'Cabecalho Grupo';
    rhbtMasterData:  Result := 'Dados';
    rhbtDetailData:  Result := 'Detalhe';
    rhbtGroupFooter: Result := 'Rodape Grupo';
    rhbtSummary:     Result := 'Sumario';
    rhbtChild:       Result := 'Filha';
  else
    Result := 'Banda';
  end;
end;

{ TrhDesignSurface }

constructor TrhDesignSurface.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLayouts := TList<TrhBandLayout>.Create;
  FZoom := 100;
  FGridSize := 25; // 2,5 mm
  FSnap := True;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  Width := 700;
  Height := 500;
end;

destructor TrhDesignSurface.Destroy;
begin
  FLayouts.Free;
  inherited Destroy;
end;

function TrhDesignSurface.Scale: Double;
begin
  // px por unidade (0,1 mm) a 96 dpi, aplicando o zoom
  Result := (96 / 25.4 / 10) * (FZoom / 100);
end;

function TrhDesignSurface.ContentWidthPx: Integer;
begin
  if FPage <> nil then
    Result := Round(FPage.ContentWidth * Scale)
  else
    Result := 400;
end;

procedure TrhDesignSurface.LoadReport(AReport: TrhReport);
begin
  FReport := AReport;
  FSelObj := nil;
  FSelBand := nil;
  if (FReport <> nil) then
  begin
    if FReport.Pages.Count = 0 then
      FReport.EnsurePage;
    FPage := FReport.Pages[0];
  end
  else
    FPage := nil;
  Recalc;
  DoSelChanged;
  Invalidate;
end;

procedure TrhDesignSurface.RebuildLayout;
begin
  Recalc;
  Invalidate;
end;

procedure TrhDesignSurface.Recalc;
var
  Band: TrhBand;
  Lay: TrhBandLayout;
  Y: Integer;
begin
  FLayouts.Clear;
  Y := RH_TOPPAD;
  if FPage <> nil then
    for Band in FPage.Bands do
    begin
      Lay.Band := Band;
      Lay.TopPx := Y;
      Lay.HeightPx := Max(8, Round(Band.Height * Scale));
      FLayouts.Add(Lay);
      Y := Y + Lay.HeightPx + 1; // 1px separador
    end;
  Height := Y + RH_TOPPAD + 40;
  Width := RH_GUTTER + ContentWidthPx + RH_TOPPAD;
end;

function TrhDesignSurface.SnapU(V: TrhUnit): TrhUnit;
begin
  if FSnap and (FGridSize > 0) then
    Result := Round(V / FGridSize) * FGridSize
  else
    Result := V;
end;

function TrhDesignSurface.FindBandAtY(Y: Integer; out Lay: TrhBandLayout): Boolean;
var
  L: TrhBandLayout;
begin
  for L in FLayouts do
    if (Y >= L.TopPx) and (Y < L.TopPx + L.HeightPx) then
    begin
      Lay := L;
      Exit(True);
    end;
  Result := False;
end;

function TrhDesignSurface.LayoutOf(Band: TrhBand; out Lay: TrhBandLayout): Boolean;
var
  L: TrhBandLayout;
begin
  for L in FLayouts do
    if L.Band = Band then
    begin
      Lay := L;
      Exit(True);
    end;
  Result := False;
end;

function TrhDesignSurface.ObjRectPx(const Lay: TrhBandLayout; Obj: TrhReportObject): TRect;
var
  S: Double;
begin
  S := Scale;
  Result.Left := RH_GUTTER + Round(Obj.Left * S);
  Result.Top := Lay.TopPx + Round(Obj.Top * S);
  Result.Right := Result.Left + Max(2, Round(Obj.Width * S));
  Result.Bottom := Result.Top + Max(2, Round(Obj.Height * S));
end;

function TrhDesignSurface.HandleAtPoint(const R: TRect; const P: TPoint): TrhDesignHandle;
  function Near(HX, HY: Integer): Boolean;
  begin
    Result := (Abs(P.X - HX) <= RH_HANDLE) and (Abs(P.Y - HY) <= RH_HANDLE);
  end;
var
  MX, MY: Integer;
begin
  MX := (R.Left + R.Right) div 2;
  MY := (R.Top + R.Bottom) div 2;
  if Near(R.Left, R.Top) then Exit(dhTL);
  if Near(R.Right, R.Top) then Exit(dhTR);
  if Near(R.Left, R.Bottom) then Exit(dhBL);
  if Near(R.Right, R.Bottom) then Exit(dhBR);
  if Near(MX, R.Top) then Exit(dhT);
  if Near(MX, R.Bottom) then Exit(dhB);
  if Near(R.Left, MY) then Exit(dhL);
  if Near(R.Right, MY) then Exit(dhR);
  if PtInRect(R, P) then Exit(dhMove);
  Result := dhNone;
end;

function TrhDesignSurface.BandBottomGripAt(const P: TPoint; out Band: TrhBand): Boolean;
var
  L: TrhBandLayout;
begin
  Band := nil;
  if P.X < RH_GUTTER then Exit(False);
  for L in FLayouts do
    if Abs(P.Y - (L.TopPx + L.HeightPx)) <= RH_BANDGRIP then
    begin
      Band := L.Band;
      Exit(True);
    end;
  Result := False;
end;

// ---------------------------------------------------------------------------
//  Desenho
// ---------------------------------------------------------------------------

procedure TrhDesignSurface.Paint;
var
  Lay: TrhBandLayout;
  Obj: TrhReportObject;
  R: TRect;
begin
  // fundo
  Canvas.Brush.Color := clBtnFace;
  Canvas.FillRect(ClientRect);

  if FPage = nil then Exit;

  for Lay in FLayouts do
    DrawBandStrip(Lay);

  // objetos por banda
  for Lay in FLayouts do
    for Obj in Lay.Band.Objects do
      DrawObject(Lay, Obj);

  // selecao
  if (FSelObj <> nil) and LayoutOf(FSelBand, Lay) then
  begin
    R := ObjRectPx(Lay, FSelObj);
    DrawSelection(R);
  end;
end;

procedure TrhDesignSurface.DrawBandStrip(const Lay: TrhBandLayout);
var
  StripRect, GutterRect: TRect;
  GX, GY, Step: Integer;
  S: Double;
  Cap: string;
begin
  S := Scale;
  StripRect := Rect(RH_GUTTER, Lay.TopPx, RH_GUTTER + ContentWidthPx, Lay.TopPx + Lay.HeightPx);
  GutterRect := Rect(0, Lay.TopPx, RH_GUTTER, Lay.TopPx + Lay.HeightPx);

  // area util (papel)
  Canvas.Brush.Color := clWhite;
  Canvas.FillRect(StripRect);

  // grade (pontos)
  if FSnap and (FGridSize > 0) then
  begin
    Step := Round(FGridSize * S);
    if Step >= 6 then
    begin
      Canvas.Pen.Color := $00E0E0E0;
      GY := Lay.TopPx;
      while GY < Lay.TopPx + Lay.HeightPx do
      begin
        GX := RH_GUTTER;
        while GX < StripRect.Right do
        begin
          Canvas.Pixels[GX, GY] := $00D0D0D0;
          Inc(GX, Step);
        end;
        Inc(GY, Step);
      end;
    end;
  end;

  // separador inferior da banda
  Canvas.Pen.Color := $00B0B0B0;
  Canvas.MoveTo(0, Lay.TopPx + Lay.HeightPx);
  Canvas.LineTo(StripRect.Right, Lay.TopPx + Lay.HeightPx);

  // gutter com rotulo
  if Lay.Band = FSelBand then
    Canvas.Brush.Color := $00F0D8B0
  else
    Canvas.Brush.Color := $00ECECEC;
  Canvas.FillRect(GutterRect);
  Canvas.Pen.Color := $00B0B0B0;
  Canvas.MoveTo(RH_GUTTER, Lay.TopPx);
  Canvas.LineTo(RH_GUTTER, Lay.TopPx + Lay.HeightPx);

  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 8;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := clBlack;
  Canvas.Brush.Style := bsClear;
  Cap := BandCaption(Lay.Band.BandType);
  if Lay.Band.DataSetName <> '' then
    Cap := Cap + ' [' + Lay.Band.DataSetName + ']'
  else if Lay.Band.GroupExpression <> '' then
    Cap := Cap + ' ' + Lay.Band.GroupExpression;
  Canvas.TextOut(6, Lay.TopPx + 4, Cap);
  Canvas.Font.Style := [];
  Canvas.Font.Color := $00808080;
  Canvas.TextOut(6, Lay.TopPx + 20, Format('%.1f mm', [Lay.Band.Height / 10]));
  Canvas.Brush.Style := bsSolid;
end;

procedure TrhDesignSurface.DrawObject(const Lay: TrhBandLayout; Obj: TrhReportObject);
var
  R: TRect;
  Txt: TrhTextObject;
  Lin: TrhLineObject;
  Shp: TrhShapeObject;
  Img: TrhImageObject;
  Flags: Cardinal;
  S: Double;
begin
  if not Obj.Visible then Exit;
  S := Scale;
  R := ObjRectPx(Lay, Obj);

  if Obj is TrhTextObject then
  begin
    Txt := TrhTextObject(Obj);
    if not Txt.Transparent then
    begin
      Canvas.Brush.Color := Txt.Color;
      Canvas.FillRect(R);
    end;
    // moldura declarada
    Canvas.Brush.Style := bsClear;
    if Obj.Frame.Sides <> [] then
    begin
      Canvas.Pen.Color := Obj.Frame.Color;
      Canvas.Pen.Width := Max(1, Round(Obj.Frame.Width * S));
      if rhfsLeft in Obj.Frame.Sides then begin Canvas.MoveTo(R.Left, R.Top); Canvas.LineTo(R.Left, R.Bottom); end;
      if rhfsTop in Obj.Frame.Sides then begin Canvas.MoveTo(R.Left, R.Top); Canvas.LineTo(R.Right, R.Top); end;
      if rhfsRight in Obj.Frame.Sides then begin Canvas.MoveTo(R.Right, R.Top); Canvas.LineTo(R.Right, R.Bottom); end;
      if rhfsBottom in Obj.Frame.Sides then begin Canvas.MoveTo(R.Left, R.Bottom); Canvas.LineTo(R.Right, R.Bottom); end;
      Canvas.Pen.Width := 1;
    end;
    // contorno tracejado (guia de design)
    Canvas.Pen.Color := $00C8C8C8;
    Canvas.Pen.Style := psDot;
    Canvas.Rectangle(R);
    Canvas.Pen.Style := psSolid;
    // texto
    Canvas.Font.Assign(Txt.Font);
    Canvas.Font.Height := -Round(Txt.Font.Size * 96 / 72 * (FZoom / 100));
    Canvas.Brush.Style := bsClear;
    Flags := DT_NOPREFIX or DT_END_ELLIPSIS;
    case Txt.HAlign of
      rhhaCenter: Flags := Flags or DT_CENTER;
      rhhaRight:  Flags := Flags or DT_RIGHT;
    else
      Flags := Flags or DT_LEFT;
    end;
    if Txt.WordWrap then
      Flags := Flags or DT_WORDBREAK or DT_TOP
    else
    begin
      Flags := Flags or DT_SINGLELINE;
      case Txt.VAlign of
        rhvaCenter: Flags := Flags or DT_VCENTER;
        rhvaBottom: Flags := Flags or DT_BOTTOM;
      else
        Flags := Flags or DT_TOP;
      end;
    end;
    DrawText(Canvas.Handle, PChar(Txt.Text), Length(Txt.Text), R, Flags);
    Canvas.Brush.Style := bsSolid;
  end
  else if Obj is TrhLineObject then
  begin
    Lin := TrhLineObject(Obj);
    Canvas.Pen.Color := Lin.PenColor;
    Canvas.Pen.Width := Max(1, Round(Lin.PenWidth * S));
    if Abs(Obj.Height) <= Abs(Obj.Width) then
    begin
      Canvas.MoveTo(R.Left, R.Top);
      Canvas.LineTo(R.Right, R.Top);
    end
    else
    begin
      Canvas.MoveTo(R.Left, R.Top);
      Canvas.LineTo(R.Left, R.Bottom);
    end;
    Canvas.Pen.Width := 1;
  end
  else if Obj is TrhShapeObject then
  begin
    Shp := TrhShapeObject(Obj);
    Canvas.Pen.Color := Shp.PenColor;
    Canvas.Pen.Width := Max(1, Round(Shp.PenWidth * S));
    if Shp.Transparent then
      Canvas.Brush.Style := bsClear
    else
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := Shp.BrushColor;
    end;
    case Shp.Kind of
      rhskEllipse:   Canvas.Ellipse(R);
      rhskRoundRect: Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, 12, 12);
    else
      Canvas.Rectangle(R);
    end;
    Canvas.Pen.Width := 1;
    Canvas.Brush.Style := bsSolid;
  end
  else if Obj is TrhImageObject then
  begin
    Img := TrhImageObject(Obj);
    if (Img.Picture <> nil) and (Img.Picture.Graphic <> nil) and
       (not Img.Picture.Graphic.Empty) then
      Canvas.StretchDraw(R, Img.Picture.Graphic)
    else
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Pen.Color := $00A0A0A0;
      Canvas.Rectangle(R);
      Canvas.MoveTo(R.Left, R.Top); Canvas.LineTo(R.Right, R.Bottom);
      Canvas.MoveTo(R.Right, R.Top); Canvas.LineTo(R.Left, R.Bottom);
      Canvas.Brush.Style := bsSolid;
    end;
  end;
end;

procedure TrhDesignSurface.DrawSelection(const R: TRect);
  procedure H(HX, HY: Integer);
  begin
    Canvas.Rectangle(HX - RH_HANDLE div 2, HY - RH_HANDLE div 2,
      HX + RH_HANDLE div 2 + 1, HY + RH_HANDLE div 2 + 1);
  end;
var
  MX, MY: Integer;
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := clHighlight;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(R.Left - 1, R.Top - 1, R.Right + 1, R.Bottom + 1);

  MX := (R.Left + R.Right) div 2;
  MY := (R.Top + R.Bottom) div 2;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := clHighlight;
  H(R.Left, R.Top); H(MX, R.Top); H(R.Right, R.Top);
  H(R.Left, MY); H(R.Right, MY);
  H(R.Left, R.Bottom); H(MX, R.Bottom); H(R.Right, R.Bottom);
end;

// ---------------------------------------------------------------------------
//  Interacao
// ---------------------------------------------------------------------------

procedure TrhDesignSurface.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Lay: TrhBandLayout;
  Obj, Hit: TrhReportObject;
  R: TRect;
  P: TPoint;
  I: Integer;
  Band: TrhBand;
begin
  inherited;
  if CanFocus then SetFocus;
  if FPage = nil then Exit;
  P := Point(X, Y);

  // resize de altura de banda?
  if (Button = mbLeft) and BandBottomGripAt(P, Band) then
  begin
    FBandResizing := Band;
    FBandStartH := Band.Height;
    FDragStart := P;
    FDragging := True;
    FDragHandle := dhNone;
    Exit;
  end;

  // clicou numa alca do objeto selecionado?
  if (FSelObj <> nil) and LayoutOf(FSelBand, Lay) then
  begin
    R := ObjRectPx(Lay, FSelObj);
    FDragHandle := HandleAtPoint(R, P);
    if FDragHandle <> dhNone then
    begin
      FDragging := True;
      FDragStart := P;
      FObjStart := Rect(FSelObj.Left, FSelObj.Top,
        FSelObj.Left + FSelObj.Width, FSelObj.Top + FSelObj.Height);
      Exit;
    end;
  end;

  // hit-test de objeto (de cima para baixo = do fim da lista)
  Hit := nil;
  FSelBand := nil;
  if FindBandAtY(Y, Lay) then
  begin
    FSelBand := Lay.Band;
    for I := Lay.Band.Objects.Count - 1 downto 0 do
    begin
      Obj := Lay.Band.Objects[I];
      if Obj.Visible and PtInRect(ObjRectPx(Lay, Obj), P) then
      begin
        Hit := Obj;
        Break;
      end;
    end;
  end;

  SetSelObj(Hit);
  if Hit <> nil then
  begin
    FDragging := True;
    FDragHandle := dhMove;
    FDragStart := P;
    FObjStart := Rect(Hit.Left, Hit.Top, Hit.Left + Hit.Width, Hit.Top + Hit.Height);
  end;
  Invalidate;
end;

procedure TrhDesignSurface.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  S: Double;
  dxU, dyU: TrhUnit;
  L, T, Rr, B: TrhUnit;
  Band: TrhBand;
  Lay: TrhBandLayout;
  R: TRect;
begin
  inherited;
  if FPage = nil then Exit;
  S := Scale;

  if FDragging then
  begin
    dxU := Round((X - FDragStart.X) / S);
    dyU := Round((Y - FDragStart.Y) / S);

    // resize de banda
    if FBandResizing <> nil then
    begin
      FBandResizing.Height := Max(FGridSize, SnapU(FBandStartH + dyU));
      Recalc;
      Invalidate;
      DoModified;
      Exit;
    end;

    if FSelObj = nil then Exit;
    L := FObjStart.Left; T := FObjStart.Top;
    Rr := FObjStart.Right; B := FObjStart.Bottom;
    case FDragHandle of
      dhMove: begin L := L + dxU; T := T + dyU; Rr := Rr + dxU; B := B + dyU; end;
      dhL:  L := L + dxU;
      dhR:  Rr := Rr + dxU;
      dhT:  T := T + dyU;
      dhB:  B := B + dyU;
      dhTL: begin L := L + dxU; T := T + dyU; end;
      dhTR: begin Rr := Rr + dxU; T := T + dyU; end;
      dhBL: begin L := L + dxU; B := B + dyU; end;
      dhBR: begin Rr := Rr + dxU; B := B + dyU; end;
    end;
    // snap das bordas
    L := SnapU(L); T := SnapU(T); Rr := SnapU(Rr); B := SnapU(B);
    // limites minimos e nao-negativos
    if L < 0 then L := 0;
    if T < 0 then T := 0;
    if Rr < L + FGridSize then Rr := L + FGridSize;
    if B < T + FGridSize then B := T + FGridSize;

    FSelObj.Left := L;
    FSelObj.Top := T;
    FSelObj.Width := Rr - L;
    FSelObj.Height := B - T;
    Invalidate;
    DoModified;
    Exit;
  end;

  // atualizar cursor (hover)
  if BandBottomGripAt(Point(X, Y), Band) then
    Cursor := crSizeNS
  else if (FSelObj <> nil) and LayoutOf(FSelBand, Lay) then
  begin
    R := ObjRectPx(Lay, FSelObj);
    case HandleAtPoint(R, Point(X, Y)) of
      dhL, dhR:   Cursor := crSizeWE;
      dhT, dhB:   Cursor := crSizeNS;
      dhTL, dhBR: Cursor := crSizeNWSE;
      dhTR, dhBL: Cursor := crSizeNESW;
      dhMove:     Cursor := crSizeAll;
    else
      Cursor := crDefault;
    end;
  end
  else
    Cursor := crDefault;
end;

procedure TrhDesignSurface.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited;
  FDragging := False;
  FDragHandle := dhNone;
  FBandResizing := nil;
end;

procedure TrhDesignSurface.DblClick;
var
  S: string;
begin
  inherited;
  if FSelObj is TrhTextObject then
  begin
    S := TrhTextObject(FSelObj).Text;
    if InputQuery('Editar texto', 'Conteudo (aceita ilhas [expr]):', S) then
    begin
      TrhTextObject(FSelObj).Text := S;
      Invalidate;
      DoModified;
    end;
  end;
end;

// ---------------------------------------------------------------------------
//  Operacoes
// ---------------------------------------------------------------------------

procedure TrhDesignSurface.AddObjectOfClass(AClass: TrhReportObjectClass);
var
  Obj: TrhReportObject;
  Band: TrhBand;
begin
  if FPage = nil then Exit;
  // um relatorio recem-criado nao tem bandas: cria uma banda de dados
  if FPage.Bands.Count = 0 then
  begin
    FSelBand := FPage.Bands.AddBand(rhbtMasterData);
    Recalc;
  end;
  Band := FSelBand;
  if (Band = nil) and (FPage.Bands.Count > 0) then
    Band := FPage.Bands[0];
  if Band = nil then Exit;

  Obj := AClass.Create;
  Obj.Left := SnapU(50);
  Obj.Top := SnapU(20);
  Obj.Width := 400;  // 40 mm
  Obj.Height := 60;  // 6 mm
  if Obj is TrhTextObject then
    TrhTextObject(Obj).Text := 'Texto';
  if Obj is TrhLineObject then
    Obj.Height := 0;
  Band.Objects.Add(Obj);
  FSelBand := Band;
  SetSelObj(Obj);
  Invalidate;
  DoModified;
end;

procedure TrhDesignSurface.DeleteSelected;
var
  Band: TrhBand;
begin
  if FSelObj = nil then Exit;
  for Band in FPage.Bands do
    if Band.Objects.Remove(FSelObj) >= 0 then
      Break;
  FSelObj := nil;
  DoSelChanged;
  Invalidate;
  DoModified;
end;

procedure TrhDesignSurface.AddBand(BandType: TrhBandType);
begin
  if FPage = nil then Exit;
  FSelBand := FPage.Bands.AddBand(BandType);
  Recalc;
  Invalidate;
  DoModified;
end;

procedure TrhDesignSurface.DeleteSelectedBand;
var
  I: Integer;
begin
  if (FPage = nil) or (FSelBand = nil) then Exit;
  I := FPage.Bands.IndexOf(FSelBand);
  if I >= 0 then
  begin
    FPage.Bands.Delete(I);
    FSelBand := nil;
    FSelObj := nil;
    DoSelChanged;
    Recalc;
    Invalidate;
    DoModified;
  end;
end;

procedure TrhDesignSurface.SetZoom(V: Integer);
begin
  V := Max(25, Min(400, V));
  if V <> FZoom then
  begin
    FZoom := V;
    Recalc;
    Invalidate;
  end;
end;

procedure TrhDesignSurface.SetSelObj(V: TrhReportObject);
begin
  if V <> FSelObj then
  begin
    FSelObj := V;
    DoSelChanged;
  end;
end;

procedure TrhDesignSurface.DoModified;
begin
  if Assigned(FOnModified) then FOnModified(Self);
end;

procedure TrhDesignSurface.DoSelChanged;
begin
  if Assigned(FOnSelChanged) then FOnSelChanged(Self);
end;

end.
