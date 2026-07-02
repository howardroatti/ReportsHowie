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

  /// <summary>Modos de alinhamento/distribuicao de multipla selecao.</summary>
  TrhAlignMode = (ramLeft, ramHCenter, ramRight, ramTop, ramVCenter, ramBottom);

  TrhDesignSurface = class(TCustomControl)
  private
    FReport: TrhReport;
    FPage: TrhPage;
    FZoom: Integer;
    FGridSize: TrhUnit;
    FSnap: Boolean;
    FSelObj: TrhReportObject;              // primario (alcas/inspetor)
    FSelBand: TrhBand;
    FSelection: TList<TrhReportObject>;    // selecao (toda na mesma banda)
    FLayouts: TList<TrhBandLayout>;
    FOnModified: TNotifyEvent;
    FOnSelChanged: TNotifyEvent;
    // interacao
    FDragging: Boolean;
    FDragHandle: TrhDesignHandle;
    FDragStart: TPoint;
    FObjStart: TRect;          // Left/Top/Right/Bottom em unidades (primario)
    FSelStart: TList<TRect>;   // bounds iniciais de cada item selecionado
    FBandResizing: TrhBand;
    FBandStartH: TrhUnit;
    FMarquee: Boolean;
    FMarqueeRect: TRect;       // em pixels
    FGuideVX: Integer;         // guia vertical (px), -1 = nenhuma
    FGuideHY: Integer;         // guia horizontal (px), -1 = nenhuma
    // desfazer (pilha de snapshots JSON)
    FUndo: TList<string>;
    FPendingUndo: string;
    FUndoPending: Boolean;
    procedure PushSnapshot(const S: string);
    procedure BeginDragUndo;
    procedure CommitDragUndo;
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
    procedure DrawSelection(const R: TRect; Primary: Boolean);
    procedure DoModified;
    procedure DoSelChanged;
    procedure SetZoom(V: Integer);
    procedure SetSelObj(V: TrhReportObject);
    procedure SelectSingle(Obj: TrhReportObject);
    procedure ToggleSel(Obj: TrhReportObject);
    function IsSelected(Obj: TrhReportObject): Boolean;
    procedure CaptureSelStart;
    procedure ComputeGuides(var NX, NY: TrhUnit; W, H: TrhUnit; const Lay: TrhBandLayout);
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
    procedure InsertField(const ADatasetName, AFieldName: string);
    /// <summary>Drag-to-bind: solta um campo em (X,Y) da superficie. Se cair sobre
    ///  um texto, seta o DataField dele; senao cria um texto vinculado ali.</summary>
    procedure DropField(X, Y: Integer; const ADatasetName, AFieldName: string);
    procedure DeleteSelected;
    procedure AddBand(BandType: TrhBandType);
    procedure DeleteSelectedBand;
    procedure AlignSelected(Mode: TrhAlignMode);
    procedure DistributeSelected(Horizontal: Boolean);
    procedure Undo;
    procedure PushUndoNow;
    function CanUndo: Boolean;
    function SelectionCount: Integer;
    property Report: TrhReport read FReport;
    property Selected: TrhReportObject read FSelObj write SetSelObj;
    property SelectedBand: TrhBand read FSelBand;
    property Zoom: Integer read FZoom write SetZoom;
    property Snap: Boolean read FSnap write FSnap;
    property GridSize: TrhUnit read FGridSize write FGridSize;
    property OnModified: TNotifyEvent read FOnModified write FOnModified;
    property OnSelectionChanged: TNotifyEvent read FOnSelChanged write FOnSelChanged;
    // promove a visibilidade (protegidas em TControl) para o form ligar o drop
    property OnDragOver;
    property OnDragDrop;
  end;

/// <summary>Rotulo amigavel do tipo de banda (para o gutter).</summary>
function BandCaption(BT: TrhBandType): string;

implementation

uses
  System.SysUtils, System.Math, System.Generics.Defaults, Vcl.Dialogs, Vcl.ExtDlgs;

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
  FSelection := TList<TrhReportObject>.Create;
  FSelStart := TList<TRect>.Create;
  FUndo := TList<string>.Create;
  FGuideVX := -1;
  FGuideHY := -1;
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
  FUndo.Free;
  FSelStart.Free;
  FSelection.Free;
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
  FSelection.Clear;
  FUndo.Clear;
  FUndoPending := False;
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

  // selecao (todos os itens; alcas so no primario)
  if (FSelBand <> nil) and LayoutOf(FSelBand, Lay) then
    for Obj in FSelection do
    begin
      R := ObjRectPx(Lay, Obj);
      DrawSelection(R, Obj = FSelObj);
    end;

  // guias de alinhamento (durante o arrasto)
  if FDragging then
  begin
    Canvas.Pen.Color := clRed;
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Width := 1;
    if FGuideVX >= 0 then
    begin
      Canvas.MoveTo(FGuideVX, 0);
      Canvas.LineTo(FGuideVX, Height);
    end;
    if FGuideHY >= 0 then
    begin
      Canvas.MoveTo(RH_GUTTER, FGuideHY);
      Canvas.LineTo(Width, FGuideHY);
    end;
  end;

  // retangulo de selecao (marquee)
  if FMarquee then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := clHighlight;
    Canvas.Pen.Style := psDot;
    Canvas.Rectangle(FMarqueeRect);
    Canvas.Pen.Style := psSolid;
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
  DispTxt: string;
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
    // no design-time mostra a expressao efetiva (DataField vira [campo])
    DispTxt := Txt.DisplayExpression;
    DrawText(Canvas.Handle, PChar(DispTxt), Length(DispTxt), R, Flags);
    Canvas.Brush.Style := bsSolid;
    // indicador de campo vinculado: triangulo azul no canto superior esquerdo
    if Txt.DataField <> '' then
    begin
      Canvas.Brush.Color := $00C07000; // azul (BGR)
      Canvas.Brush.Style := bsSolid;
      Canvas.Pen.Style := psClear;
      Canvas.Polygon([Point(R.Left, R.Top), Point(R.Left + 9, R.Top),
        Point(R.Left, R.Top + 9)]);
      Canvas.Pen.Style := psSolid;
    end;
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

procedure TrhDesignSurface.DrawSelection(const R: TRect; Primary: Boolean);
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

  // alcas de redimensionamento so no item primario e quando ha selecao unica
  if not (Primary and (FSelection.Count = 1)) then Exit;

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
  FGuideVX := -1; FGuideHY := -1;

  // resize de altura de banda?
  if (Button = mbLeft) and BandBottomGripAt(P, Band) then
  begin
    BeginDragUndo;
    FBandResizing := Band;
    FBandStartH := Band.Height;
    FDragStart := P;
    FDragging := True;
    FDragHandle := dhNone;
    Exit;
  end;

  // clicou numa alca do primario (apenas selecao unica)?
  if (FSelObj <> nil) and (FSelection.Count = 1) and LayoutOf(FSelBand, Lay) then
  begin
    R := ObjRectPx(Lay, FSelObj);
    FDragHandle := HandleAtPoint(R, P);
    if not (FDragHandle in [dhNone, dhMove]) then
    begin
      BeginDragUndo;
      FDragging := True;
      FDragStart := P;
      FObjStart := Rect(FSelObj.Left, FSelObj.Top,
        FSelObj.Left + FSelObj.Width, FSelObj.Top + FSelObj.Height);
      Exit;
    end;
  end;

  if FindBandAtY(Y, Lay) then
  begin
    // objeto sob o cursor (do topo = fim da lista)
    Hit := nil;
    for I := Lay.Band.Objects.Count - 1 downto 0 do
      if Lay.Band.Objects[I].Visible and PtInRect(ObjRectPx(Lay, Lay.Band.Objects[I]), P) then
      begin
        Hit := Lay.Band.Objects[I];
        Break;
      end;

    if Hit <> nil then
    begin
      if (ssShift in Shift) and (FSelBand = Lay.Band) then
        ToggleSel(Hit)
      else if (FSelBand = Lay.Band) and IsSelected(Hit) then
        FSelObj := Hit
      else
        SelectSingle(Hit);
      FSelBand := Lay.Band;
      DoSelChanged;
      if FSelObj <> nil then
      begin
        BeginDragUndo;
        FDragging := True;
        FDragHandle := dhMove;
        FDragStart := P;
        FObjStart := Rect(FSelObj.Left, FSelObj.Top,
          FSelObj.Left + FSelObj.Width, FSelObj.Top + FSelObj.Height);
        CaptureSelStart;
      end;
    end
    else
    begin
      // area vazia da banda: seleciona banda + inicia marquee
      FSelBand := Lay.Band;
      if not (ssShift in Shift) then
      begin
        FSelection.Clear;
        FSelObj := nil;
      end;
      DoSelChanged;
      if P.X >= RH_GUTTER then
      begin
        FMarquee := True;
        FDragStart := P;
        FMarqueeRect := Rect(P.X, P.Y, P.X, P.Y);
      end;
    end;
  end
  else
  begin
    FSelBand := nil;
    FSelection.Clear;
    FSelObj := nil;
    DoSelChanged;
  end;
  Invalidate;
end;

procedure TrhDesignSurface.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  S: Double;
  dxU, dyU, L, T, Rr, B, NX, NY, ADX, ADY: TrhUnit;
  Band: TrhBand;
  Lay: TrhBandLayout;
  R: TRect;
  I: Integer;
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
      CommitDragUndo;
      FBandResizing.Height := Max(FGridSize, SnapU(FBandStartH + dyU));
      Recalc;
      Invalidate;
      DoModified;
      Exit;
    end;

    if FSelObj = nil then Exit;

    if FDragHandle = dhMove then
    begin
      // mover o grupo pelo delta do primario, com guias/snap no primario
      if not LayoutOf(FSelBand, Lay) then Exit;
      CommitDragUndo;
      FGuideVX := -1; FGuideHY := -1;
      NX := FObjStart.Left + dxU;
      NY := FObjStart.Top + dyU;
      ComputeGuides(NX, NY, FObjStart.Right - FObjStart.Left,
        FObjStart.Bottom - FObjStart.Top, Lay);
      if FGuideVX < 0 then NX := SnapU(NX);
      if FGuideHY < 0 then NY := SnapU(NY);
      if NX < 0 then NX := 0;
      if NY < 0 then NY := 0;
      ADX := NX - FObjStart.Left;
      ADY := NY - FObjStart.Top;
      for I := 0 to FSelection.Count - 1 do
      begin
        FSelection[I].Left := Max(0, FSelStart[I].Left + ADX);
        FSelection[I].Top := Max(0, FSelStart[I].Top + ADY);
      end;
      Invalidate;
      DoModified;
      Exit;
    end;

    // resize do primario (selecao unica)
    CommitDragUndo;
    L := FObjStart.Left; T := FObjStart.Top;
    Rr := FObjStart.Right; B := FObjStart.Bottom;
    case FDragHandle of
      dhL:  L := L + dxU;
      dhR:  Rr := Rr + dxU;
      dhT:  T := T + dyU;
      dhB:  B := B + dyU;
      dhTL: begin L := L + dxU; T := T + dyU; end;
      dhTR: begin Rr := Rr + dxU; T := T + dyU; end;
      dhBL: begin L := L + dxU; B := B + dyU; end;
      dhBR: begin Rr := Rr + dxU; B := B + dyU; end;
    end;
    L := SnapU(L); T := SnapU(T); Rr := SnapU(Rr); B := SnapU(B);
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

  if FMarquee then
  begin
    FMarqueeRect := Rect(Min(FDragStart.X, X), Min(FDragStart.Y, Y),
      Max(FDragStart.X, X), Max(FDragStart.Y, Y));
    Invalidate;
    Exit;
  end;

  // atualizar cursor (hover)
  if BandBottomGripAt(Point(X, Y), Band) then
    Cursor := crSizeNS
  else if (FSelObj <> nil) and (FSelection.Count = 1) and LayoutOf(FSelBand, Lay) then
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
var
  Lay: TrhBandLayout;
  Obj: TrhReportObject;
  R: TRect;
begin
  inherited;
  if FMarquee then
  begin
    FMarquee := False;
    if LayoutOf(FSelBand, Lay) then
      for Obj in FSelBand.Objects do
        if Obj.Visible then
        begin
          R := ObjRectPx(Lay, Obj);
          if FMarqueeRect.IntersectsWith(R) and (not IsSelected(Obj)) then
            FSelection.Add(Obj);
        end;
    if FSelection.Count > 0 then
      FSelObj := FSelection.Last
    else
      FSelObj := nil;
    DoSelChanged;
  end;
  FDragging := False;
  FDragHandle := dhNone;
  FBandResizing := nil;
  FGuideVX := -1;
  FGuideHY := -1;
  Invalidate;
end;

procedure TrhDesignSurface.DblClick;
var
  S: string;
  Dlg: TOpenPictureDialog;
begin
  inherited;
  if FSelObj is TrhTextObject then
  begin
    S := TrhTextObject(FSelObj).Text;
    if InputQuery('Editar texto', 'Conteudo (aceita ilhas [expr]):', S) then
    begin
      PushUndoNow;
      TrhTextObject(FSelObj).Text := S;
      Invalidate;
      DoModified;
    end;
  end
  else if FSelObj is TrhImageObject then
  begin
    Dlg := TOpenPictureDialog.Create(nil);
    try
      if Dlg.Execute then
      begin
        PushUndoNow;
        TrhImageObject(FSelObj).Picture.LoadFromFile(Dlg.FileName);
        Invalidate;
        DoModified;
      end;
    finally
      Dlg.Free;
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
  PushUndoNow;
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
  if Obj is TrhImageObject then
  begin
    Obj.Width := 300;   // 30 mm
    Obj.Height := 300;
  end;
  if Obj is TrhLineObject then
    Obj.Height := 0;
  Band.Objects.Add(Obj);
  FSelBand := Band;
  SetSelObj(Obj);
  Invalidate;
  DoModified;
end;

procedure TrhDesignSurface.InsertField(const ADatasetName, AFieldName: string);
var
  Obj: TrhTextObject;
  Band: TrhBand;
begin
  if FPage = nil then Exit;
  PushUndoNow;
  if FPage.Bands.Count = 0 then
    FSelBand := FPage.Bands.AddBand(rhbtMasterData);
  Band := FSelBand;
  if (Band = nil) and (FPage.Bands.Count > 0) then
    Band := FPage.Bands[0];
  if Band = nil then Exit;
  // vincula a banda ao dataset do campo, se ainda nao tiver
  if (Band.DataSetName = '') and (ADatasetName <> '') then
    Band.DataSetName := ADatasetName;
  Obj := Band.Objects.AddNew<TrhTextObject>;
  Obj.Text := '[' + AFieldName + ']';
  Obj.Left := SnapU(50);
  Obj.Top := SnapU(20);
  Obj.Width := 400;  // 40 mm
  Obj.Height := 60;  // 6 mm
  FSelBand := Band;
  SelectSingle(Obj);
  DoSelChanged;
  Recalc;
  Invalidate;
  DoModified;
end;

procedure TrhDesignSurface.DropField(X, Y: Integer; const ADatasetName, AFieldName: string);
var
  Lay: TrhBandLayout;
  Band: TrhBand;
  Hit: TrhReportObject;
  Txt: TrhTextObject;
  I: Integer;
  S: Double;
begin
  if FPage = nil then Exit;
  if not FindBandAtY(Y, Lay) then Exit;
  Band := Lay.Band;

  // texto sob o ponto do drop (do topo da pilha para baixo)
  Hit := nil;
  for I := Band.Objects.Count - 1 downto 0 do
    if Band.Objects[I].Visible and (Band.Objects[I] is TrhTextObject) and
       PtInRect(ObjRectPx(Lay, Band.Objects[I]), Point(X, Y)) then
    begin
      Hit := Band.Objects[I];
      Break;
    end;

  PushUndoNow;
  // vincula a banda ao dataset do campo, se ainda nao tiver
  if (Band.DataSetName = '') and (ADatasetName <> '') then
    Band.DataSetName := ADatasetName;

  if Hit <> nil then
    Txt := TrhTextObject(Hit)          // VINCULA o objeto existente
  else
  begin
    // CRIA um texto vinculado na posicao do drop
    S := Scale;
    Txt := Band.Objects.AddNew<TrhTextObject>;
    Txt.Left := Max(0, SnapU(Round((X - RH_GUTTER) / S)));
    Txt.Top  := Max(0, SnapU(Round((Y - Lay.TopPx) / S)));
    Txt.Width := 400;  // 40 mm
    Txt.Height := 60;  // 6 mm
  end;
  Txt.DataField := AFieldName;

  FSelBand := Band;
  SelectSingle(Txt);
  DoSelChanged;
  Recalc;
  Invalidate;
  DoModified;
end;

procedure TrhDesignSurface.DeleteSelected;
var
  Band: TrhBand;
  Obj: TrhReportObject;
begin
  if FSelection.Count = 0 then Exit;
  PushUndoNow;
  for Obj in FSelection do
    for Band in FPage.Bands do
      if Band.Objects.Remove(Obj) >= 0 then
        Break;
  FSelection.Clear;
  FSelObj := nil;
  DoSelChanged;
  Invalidate;
  DoModified;
end;

procedure TrhDesignSurface.AddBand(BandType: TrhBandType);
begin
  if FPage = nil then Exit;
  PushUndoNow;
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
    PushUndoNow;
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
  SelectSingle(V);
  DoSelChanged;
end;

procedure TrhDesignSurface.SelectSingle(Obj: TrhReportObject);
begin
  FSelection.Clear;
  if Obj <> nil then
    FSelection.Add(Obj);
  FSelObj := Obj;
end;

procedure TrhDesignSurface.ToggleSel(Obj: TrhReportObject);
begin
  if Obj = nil then Exit;
  if IsSelected(Obj) then
  begin
    FSelection.Remove(Obj);
    if FSelObj = Obj then
      if FSelection.Count > 0 then FSelObj := FSelection.Last else FSelObj := nil;
  end
  else
  begin
    FSelection.Add(Obj);
    FSelObj := Obj;
  end;
end;

function TrhDesignSurface.IsSelected(Obj: TrhReportObject): Boolean;
begin
  Result := FSelection.IndexOf(Obj) >= 0;
end;

function TrhDesignSurface.SelectionCount: Integer;
begin
  Result := FSelection.Count;
end;

procedure TrhDesignSurface.PushSnapshot(const S: string);
begin
  if FReport = nil then Exit;
  FUndo.Add(S);
  while FUndo.Count > 50 do   // limite de historico
    FUndo.Delete(0);
end;

procedure TrhDesignSurface.PushUndoNow;
begin
  if FReport <> nil then
    PushSnapshot(FReport.ToJSONString(False));
end;

procedure TrhDesignSurface.BeginDragUndo;
begin
  if FReport <> nil then
  begin
    FPendingUndo := FReport.ToJSONString(False);
    FUndoPending := True;
  end;
end;

procedure TrhDesignSurface.CommitDragUndo;
begin
  if FUndoPending then
  begin
    PushSnapshot(FPendingUndo);
    FUndoPending := False;
  end;
end;

function TrhDesignSurface.CanUndo: Boolean;
begin
  Result := FUndo.Count > 0;
end;

procedure TrhDesignSurface.Undo;
var
  S: string;
begin
  if (FReport = nil) or (FUndo.Count = 0) then Exit;
  S := FUndo.Last;
  FUndo.Delete(FUndo.Count - 1);
  FReport.LoadFromJSONString(S);
  if FReport.Pages.Count = 0 then
    FReport.EnsurePage;
  FPage := FReport.Pages[0];
  FSelObj := nil;
  FSelBand := nil;
  FSelection.Clear;
  FUndoPending := False;
  Recalc;
  Invalidate;
  DoSelChanged;
  DoModified;
end;

procedure TrhDesignSurface.CaptureSelStart;
var
  Obj: TrhReportObject;
begin
  FSelStart.Clear;
  for Obj in FSelection do
    FSelStart.Add(Rect(Obj.Left, Obj.Top, Obj.Left + Obj.Width, Obj.Top + Obj.Height));
end;

procedure TrhDesignSurface.ComputeGuides(var NX, NY: TrhUnit; W, H: TrhUnit;
  const Lay: TrhBandLayout);
var
  S: Double;
  ThrU, BestDX, BestDY, D, I, J: Integer;
  Obj: TrhReportObject;
  PX, PY, SX, SY: array[0..2] of Integer;
  BestPX, BestSX, BestPY, BestSY: Integer;
  HaveX, HaveY: Boolean;
begin
  S := Scale;
  ThrU := Round(7 / S);
  BestDX := ThrU + 1; BestDY := ThrU + 1;
  HaveX := False; HaveY := False;
  BestPX := 0; BestSX := 0; BestPY := 0; BestSY := 0;
  // pontos de referencia do primario: bordas e centro
  PX[0] := NX; PX[1] := NX + W div 2; PX[2] := NX + W;
  PY[0] := NY; PY[1] := NY + H div 2; PY[2] := NY + H;

  for Obj in Lay.Band.Objects do
  begin
    if IsSelected(Obj) then Continue;
    SX[0] := Obj.Left; SX[1] := Obj.Left + Obj.Width div 2; SX[2] := Obj.Left + Obj.Width;
    SY[0] := Obj.Top;  SY[1] := Obj.Top + Obj.Height div 2; SY[2] := Obj.Top + Obj.Height;
    for I := 0 to 2 do
      for J := 0 to 2 do
      begin
        D := Abs(PX[I] - SX[J]);
        if D < BestDX then begin BestDX := D; BestPX := PX[I]; BestSX := SX[J]; HaveX := True; end;
        D := Abs(PY[I] - SY[J]);
        if D < BestDY then begin BestDY := D; BestPY := PY[I]; BestSY := SY[J]; HaveY := True; end;
      end;
  end;

  if HaveX then
  begin
    NX := NX + (BestSX - BestPX);
    FGuideVX := RH_GUTTER + Round(BestSX * S);
  end;
  if HaveY then
  begin
    NY := NY + (BestSY - BestPY);
    FGuideHY := Lay.TopPx + Round(BestSY * S);
  end;
end;

procedure TrhDesignSurface.AlignSelected(Mode: TrhAlignMode);
var
  Obj: TrhReportObject;
  Ref: TrhUnit;
  First: Boolean;
begin
  if FSelection.Count < 2 then Exit;
  PushUndoNow;
  Ref := 0;
  First := True;
  // calcula a referencia (borda/centro do conjunto)
  for Obj in FSelection do
  begin
    case Mode of
      ramLeft:    if First or (Obj.Left < Ref) then Ref := Obj.Left;
      ramRight:   if First or (Obj.Left + Obj.Width > Ref) then Ref := Obj.Left + Obj.Width;
      ramTop:     if First or (Obj.Top < Ref) then Ref := Obj.Top;
      ramBottom:  if First or (Obj.Top + Obj.Height > Ref) then Ref := Obj.Top + Obj.Height;
      ramHCenter: Ref := Ref + Obj.Left + Obj.Width div 2;
      ramVCenter: Ref := Ref + Obj.Top + Obj.Height div 2;
    end;
    First := False;
  end;
  if Mode = ramHCenter then Ref := Ref div FSelection.Count;
  if Mode = ramVCenter then Ref := Ref div FSelection.Count;

  for Obj in FSelection do
    case Mode of
      ramLeft:    Obj.Left := Ref;
      ramRight:   Obj.Left := Ref - Obj.Width;
      ramHCenter: Obj.Left := Ref - Obj.Width div 2;
      ramTop:     Obj.Top := Ref;
      ramBottom:  Obj.Top := Ref - Obj.Height;
      ramVCenter: Obj.Top := Ref - Obj.Height div 2;
    end;
  Invalidate;
  DoModified;
end;

procedure TrhDesignSurface.DistributeSelected(Horizontal: Boolean);
var
  List: TList<TrhReportObject>;
  I: Integer;
  Lo, Hi, Span, Step: TrhUnit;
begin
  if FSelection.Count < 3 then Exit;
  PushUndoNow;
  List := TList<TrhReportObject>.Create;
  try
    List.AddRange(FSelection);
    List.Sort(TComparer<TrhReportObject>.Construct(
      function(const A, B: TrhReportObject): Integer
      begin
        if Horizontal then Result := A.Left - B.Left
        else Result := A.Top - B.Top;
      end));
    if Horizontal then
    begin
      Lo := List.First.Left;
      Hi := List.Last.Left;
    end
    else
    begin
      Lo := List.First.Top;
      Hi := List.Last.Top;
    end;
    Span := Hi - Lo;
    Step := Span div (List.Count - 1);
    for I := 1 to List.Count - 2 do
      if Horizontal then
        List[I].Left := Lo + I * Step
      else
        List[I].Top := Lo + I * Step;
  finally
    List.Free;
  end;
  Invalidate;
  DoModified;
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
