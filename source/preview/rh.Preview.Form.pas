{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Janela de preview construida em codigo (sem .dfm). Exibe o
///   TrhRenderedDocument com zoom, navegacao de paginas e impressao. Fornece o
///   class helper TrhReport.ShowPreview para uso direto:
///     uses rh.Preview.Form;  ...  MeuReport.ShowPreview;
/// </summary>
unit rh.Preview.Form;

interface

uses
  System.Classes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Graphics,
  rh.Report, rh.Render.Intf;

type
  TrhPreviewForm = class(TForm)
  private
    FDoc: TrhRenderedDocument;
    FOwnsDoc: Boolean;
    FTitle: string;
    FPageIndex: Integer;
    FZoom: Double;
    FBasePPI: Integer;
    FToolbar: TPanel;
    FScroll: TScrollBox;
    FPaint: TPaintBox;
    FLblPage: TLabel;
    FLblZoom: TLabel;
    procedure BuildUI;
    function Scale: Double;
    procedure UpdateView;
    procedure PaintBoxPaint(Sender: TObject);
    procedure DoFirst(Sender: TObject);
    procedure DoPrev(Sender: TObject);
    procedure DoNext(Sender: TObject);
    procedure DoLast(Sender: TObject);
    procedure DoZoomIn(Sender: TObject);
    procedure DoZoomOut(Sender: TObject);
    procedure DoPrint(Sender: TObject);
    procedure DoClose(Sender: TObject);
  public
    constructor CreateWithDocument(AOwner: TComponent; ADoc: TrhRenderedDocument;
      AOwnsDoc: Boolean; const ATitle: string);
    destructor Destroy; override;
  end;

  /// <summary>Atalho: abre o preview do relatorio.</summary>
  TrhReportPreviewHelper = class helper for TrhReport
  public
    procedure ShowPreview;
  end;

implementation

uses
  System.SysUtils, System.StrUtils, System.Types, Winapi.Windows,
  rh.Render.Engine, rh.Render.VCLCanvas;

const
  PAGE_PAD = 24; // px de folga ao redor da pagina

function MakeButton(AOwner: TWinControl; const ACaption: string; ALeft, AWidth: Integer;
  AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AOwner;
  Result.Caption := ACaption;
  Result.SetBounds(ALeft, 6, AWidth, 28);
  Result.OnClick := AOnClick;
end;

{ TrhPreviewForm }

constructor TrhPreviewForm.CreateWithDocument(AOwner: TComponent;
  ADoc: TrhRenderedDocument; AOwnsDoc: Boolean; const ATitle: string);
begin
  inherited CreateNew(AOwner);
  FDoc := ADoc;
  FOwnsDoc := AOwnsDoc;
  FTitle := ATitle;
  FPageIndex := 0;
  FZoom := 1.0;
  FBasePPI := Screen.PixelsPerInch;
  BuildUI;
  UpdateView;
end;

destructor TrhPreviewForm.Destroy;
begin
  if FOwnsDoc then
    FDoc.Free;
  inherited Destroy;
end;

procedure TrhPreviewForm.BuildUI;
var
  X: Integer;
begin
  Caption := 'Preview' + IfThen(FTitle <> '', ' - ' + FTitle, '');
  Width := 900;
  Height := 700;
  Position := poScreenCenter;

  FToolbar := TPanel.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := alTop;
  FToolbar.Height := 40;
  FToolbar.BevelOuter := bvNone;

  X := 8;
  MakeButton(FToolbar, '|<', X, 34, DoFirst); Inc(X, 36);
  MakeButton(FToolbar, '<',  X, 34, DoPrev);  Inc(X, 36);

  FLblPage := TLabel.Create(FToolbar);
  FLblPage.Parent := FToolbar;
  FLblPage.SetBounds(X, 12, 90, 20);
  FLblPage.AutoSize := False;
  FLblPage.Alignment := taCenter;
  Inc(X, 94);

  MakeButton(FToolbar, '>',  X, 34, DoNext); Inc(X, 36);
  MakeButton(FToolbar, '>|', X, 34, DoLast); Inc(X, 44);

  MakeButton(FToolbar, '-', X, 34, DoZoomOut); Inc(X, 36);
  FLblZoom := TLabel.Create(FToolbar);
  FLblZoom.Parent := FToolbar;
  FLblZoom.SetBounds(X, 12, 60, 20);
  FLblZoom.AutoSize := False;
  FLblZoom.Alignment := taCenter;
  Inc(X, 64);
  MakeButton(FToolbar, '+', X, 34, DoZoomIn); Inc(X, 48);

  MakeButton(FToolbar, 'Imprimir', X, 90, DoPrint); Inc(X, 98);
  MakeButton(FToolbar, 'Fechar', X, 80, DoClose);

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

function TrhPreviewForm.Scale: Double;
begin
  Result := FBasePPI * FZoom / 254; // pixels por unidade (0,1 mm)
end;

procedure TrhPreviewForm.UpdateView;
var
  Page: TrhRenderedPage;
begin
  if (FDoc = nil) or (FDoc.PageCount = 0) then
  begin
    FLblPage.Caption := '0 / 0';
    FLblZoom.Caption := Format('%d%%', [Round(FZoom * 100)]);
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

procedure TrhPreviewForm.PaintBoxPaint(Sender: TObject);
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

procedure TrhPreviewForm.DoFirst(Sender: TObject);
begin
  FPageIndex := 0;
  UpdateView;
end;

procedure TrhPreviewForm.DoPrev(Sender: TObject);
begin
  Dec(FPageIndex);
  UpdateView;
end;

procedure TrhPreviewForm.DoNext(Sender: TObject);
begin
  Inc(FPageIndex);
  UpdateView;
end;

procedure TrhPreviewForm.DoLast(Sender: TObject);
begin
  FPageIndex := FDoc.PageCount - 1;
  UpdateView;
end;

procedure TrhPreviewForm.DoZoomIn(Sender: TObject);
begin
  if FZoom < 4.0 then FZoom := FZoom * 1.25;
  UpdateView;
end;

procedure TrhPreviewForm.DoZoomOut(Sender: TObject);
begin
  if FZoom > 0.25 then FZoom := FZoom / 1.25;
  UpdateView;
end;

procedure TrhPreviewForm.DoPrint(Sender: TObject);
begin
  TrhVCLRenderer.PrintDocument(FDoc, FTitle);
end;

procedure TrhPreviewForm.DoClose(Sender: TObject);
begin
  Close;
end;

{ TrhReportPreviewHelper }

procedure TrhReportPreviewHelper.ShowPreview;
var
  Doc: TrhRenderedDocument;
  Frm: TrhPreviewForm;
begin
  Doc := TrhRenderEngine.BuildDocument(Self);
  Frm := TrhPreviewForm.CreateWithDocument(Application, Doc, True, Self.Title);
  try
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

end.
