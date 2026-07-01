{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Controle de preview EMBUTIVEL. Ao contrario da janela TrhPreviewForm
///   (modal), este e um TCustomControl que voce poe direto num form/painel,
///   deixando o relatorio sempre visivel na tela. Traz barra de navegacao de
///   paginas e zoom, e desenha via o MESMO TrhVCLRenderer do preview/designer
///   (WYSIWYG). Reutilizavel tambem no designer runtime (Fase 10).
///
///   Uso tipico (documento vindo do pipeline de dados):
///     FPrev := TrhPreviewControl.Create(Self);
///     FPrev.Parent := Self;
///     FPrev.Align := alClient;
///     Doc := TrhDataPipeline.BuildDocument(MeuReport);
///     FPrev.LoadDocument(Doc);            // controle assume a posse do Doc
/// </summary>
unit rh.Preview.Control;

interface

uses
  System.Classes, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics,
  Vcl.Forms,
  rh.Report, rh.Render.Intf, rh.Expr.Nodes;

type
  TrhPreviewControl = class(TCustomControl)
  private
    FDoc: TrhRenderedDocument;
    FOwnsDoc: Boolean;
    FPageIndex: Integer;
    FZoom: Double;
    FBasePPI: Integer;
    FBar: TPanel;
    FScroll: TScrollBox;
    FPaint: TPaintBox;
    FLblPage: TLabel;
    FLblZoom: TLabel;
    procedure BuildUI;
    function Scale: Double;
    procedure UpdateView;
    procedure ClearDoc;
    procedure PaintBoxPaint(Sender: TObject);
    procedure DoFirst(Sender: TObject);
    procedure DoPrev(Sender: TObject);
    procedure DoNext(Sender: TObject);
    procedure DoLast(Sender: TObject);
    procedure DoZoomIn(Sender: TObject);
    procedure DoZoomOut(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Exibe um documento ja renderizado (do pipeline/engine).
    ///  Se AOwnsDoc, o controle libera o Doc ao trocar/destruir.</summary>
    procedure LoadDocument(ADoc: TrhRenderedDocument; AOwnsDoc: Boolean = True);
    /// <summary>Conveniencia: renderiza o relatorio (layout estatico, sem dados)
    ///  e exibe. Para relatorios com dados, monte o Doc pelo pipeline e use
    ///  LoadDocument.</summary>
    procedure ShowReport(AReport: TrhReport; const Ctx: IrhEvalContext = nil);
  end;

implementation

uses
  System.SysUtils, System.StrUtils, System.Types,
  rh.Render.Engine, rh.Render.VCLCanvas;

const
  PAGE_PAD = 16; // px de folga ao redor da pagina

function MakeBtn(AOwner: TWinControl; const ACaption: string; var X: Integer;
  AWidth: Integer; AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AOwner;
  Result.Caption := ACaption;
  Result.SetBounds(X, 5, AWidth, 26);
  Result.OnClick := AOnClick;
  Inc(X, AWidth + 2);
end;

{ TrhPreviewControl }

constructor TrhPreviewControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 460;
  Height := 560;
  FPageIndex := 0;
  FZoom := 1.0;
  FBasePPI := Screen.PixelsPerInch;
  BuildUI;
  UpdateView;
end;

destructor TrhPreviewControl.Destroy;
begin
  ClearDoc;
  inherited;
end;

procedure TrhPreviewControl.ClearDoc;
begin
  if FOwnsDoc and Assigned(FDoc) then
    FDoc.Free;
  FDoc := nil;
  FOwnsDoc := False;
end;

procedure TrhPreviewControl.BuildUI;
var
  X: Integer;
begin
  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.Height := 36;
  FBar.BevelOuter := bvNone;

  X := 6;
  MakeBtn(FBar, '|<', X, 30, DoFirst);
  MakeBtn(FBar, '<',  X, 30, DoPrev);

  FLblPage := TLabel.Create(FBar);
  FLblPage.Parent := FBar;
  FLblPage.SetBounds(X, 10, 74, 18);
  FLblPage.AutoSize := False;
  FLblPage.Alignment := taCenter;
  Inc(X, 78);

  MakeBtn(FBar, '>',  X, 30, DoNext);
  MakeBtn(FBar, '>|', X, 30, DoLast);
  Inc(X, 8);

  MakeBtn(FBar, '-', X, 30, DoZoomOut);
  FLblZoom := TLabel.Create(FBar);
  FLblZoom.Parent := FBar;
  FLblZoom.SetBounds(X, 10, 50, 18);
  FLblZoom.AutoSize := False;
  FLblZoom.Alignment := taCenter;
  Inc(X, 54);
  MakeBtn(FBar, '+', X, 30, DoZoomIn);

  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := alClient;
  FScroll.Color := clGray;
  FScroll.HorzScrollBar.Tracking := True;
  FScroll.VertScrollBar.Tracking := True;

  FPaint := TPaintBox.Create(Self);
  FPaint.Parent := FScroll;
  FPaint.OnPaint := PaintBoxPaint;
end;

function TrhPreviewControl.Scale: Double;
begin
  Result := FBasePPI * FZoom / 254; // pixels por unidade (0,1 mm)
end;

procedure TrhPreviewControl.LoadDocument(ADoc: TrhRenderedDocument; AOwnsDoc: Boolean);
begin
  if ADoc <> FDoc then
    ClearDoc;
  FDoc := ADoc;
  FOwnsDoc := AOwnsDoc;
  FPageIndex := 0;
  UpdateView;
end;

procedure TrhPreviewControl.ShowReport(AReport: TrhReport; const Ctx: IrhEvalContext);
begin
  LoadDocument(TrhRenderEngine.BuildDocument(AReport, Ctx), True);
end;

procedure TrhPreviewControl.UpdateView;
var
  Page: TrhRenderedPage;
begin
  if (FDoc = nil) or (FDoc.PageCount = 0) then
  begin
    if FLblPage <> nil then FLblPage.Caption := '0 / 0';
    if FLblZoom <> nil then FLblZoom.Caption := Format('%d%%', [Round(FZoom * 100)]);
    FPaint.SetBounds(0, 0, 0, 0);
    FPaint.Invalidate;
    Exit;
  end;
  if FPageIndex < 0 then FPageIndex := 0;
  if FPageIndex > FDoc.PageCount - 1 then FPageIndex := FDoc.PageCount - 1;

  Page := FDoc.Pages[FPageIndex];
  FPaint.SetBounds(0, 0,
    Round(Page.Width * Scale) + PAGE_PAD * 2,
    Round(Page.Height * Scale) + PAGE_PAD * 2);
  FLblPage.Caption := Format('%d / %d', [FPageIndex + 1, FDoc.PageCount]);
  FLblZoom.Caption := Format('%d%%', [Round(FZoom * 100)]);
  FPaint.Invalidate;
end;

procedure TrhPreviewControl.PaintBoxPaint(Sender: TObject);
var
  Page: TrhRenderedPage;
  C: TCanvas;
  PageR: TRect;
begin
  C := FPaint.Canvas;
  C.Brush.Color := clGray;
  C.Brush.Style := bsSolid;
  C.FillRect(FPaint.ClientRect);

  if (FDoc = nil) or (FDoc.PageCount = 0) then Exit;
  Page := FDoc.Pages[FPageIndex];

  PageR := TRect.Create(PAGE_PAD, PAGE_PAD,
    PAGE_PAD + Round(Page.Width * Scale),
    PAGE_PAD + Round(Page.Height * Scale));

  // sombra
  C.Brush.Color := clBlack;
  C.FillRect(TRect.Create(PageR.Left + 4, PageR.Top + 4, PageR.Right + 4, PageR.Bottom + 4));
  // folha branca
  C.Brush.Color := clWhite;
  C.FillRect(PageR);
  C.Pen.Color := clSilver;
  C.Pen.Width := 1;
  C.Brush.Style := bsClear;
  C.Rectangle(PageR);

  TrhVCLRenderer.DrawPage(C, Page, Scale, PAGE_PAD, PAGE_PAD);
end;

procedure TrhPreviewControl.DoFirst(Sender: TObject);
begin
  FPageIndex := 0;
  UpdateView;
end;

procedure TrhPreviewControl.DoPrev(Sender: TObject);
begin
  Dec(FPageIndex);
  UpdateView;
end;

procedure TrhPreviewControl.DoNext(Sender: TObject);
begin
  Inc(FPageIndex);
  UpdateView;
end;

procedure TrhPreviewControl.DoLast(Sender: TObject);
begin
  if FDoc <> nil then
    FPageIndex := FDoc.PageCount - 1;
  UpdateView;
end;

procedure TrhPreviewControl.DoZoomIn(Sender: TObject);
begin
  if FZoom < 4.0 then FZoom := FZoom * 1.25;
  UpdateView;
end;

procedure TrhPreviewControl.DoZoomOut(Sender: TObject);
begin
  if FZoom > 0.25 then FZoom := FZoom / 1.25;
  UpdateView;
end;

end.
