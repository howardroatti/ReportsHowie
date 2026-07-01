{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Formulario do designer visual. Construido inteiramente em codigo e LIVRE
///   de DesignIntf, para poder ser aberto tanto pelo component editor do IDE
///   (Fase 5) quanto embutido numa aplicacao em runtime (Fase 10).
///
///   Edita o relatorio in-place; ao Cancelar restaura o snapshot JSON tirado na
///   abertura. Execute retorna True se o usuario confirmou (OK).
/// </summary>
unit rh.Design.Designer.Form;

interface

uses
  System.Classes, System.SysUtils,
  Winapi.Windows, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Dialogs,
  rh.Types, rh.Model.Types, rh.Objects, rh.Bands, rh.Report,
  rh.Design.Surface, rh.Design.Inspector;

type
  TrhDesignerForm = class(TForm)
  private
    FReport: TrhReport;
    FSnapshot: string;
    FScroll: TScrollBox;
    FSurface: TrhDesignSurface;
    FToolbar: TFlowPanel;
    FStatus: TStatusBar;
    FZoomLabel: TLabel;
    FBandCombo: TComboBox;
    FInspector: TrhInspector;
    FInspHeader: TLabel;
    function AddButton(const Caption: string; AWidth: Integer;
      AClick: TNotifyEvent): TButton;
    procedure AddSeparator;
    procedure DoAddText(Sender: TObject);
    procedure DoAddImage(Sender: TObject);
    procedure DoAddLine(Sender: TObject);
    procedure DoAddShape(Sender: TObject);
    procedure DoDelObj(Sender: TObject);
    procedure DoAddBand(Sender: TObject);
    procedure DoDelBand(Sender: TObject);
    procedure DoZoomIn(Sender: TObject);
    procedure DoZoomOut(Sender: TObject);
    procedure DoPreview(Sender: TObject);
    procedure DoOK(Sender: TObject);
    procedure DoCancel(Sender: TObject);
    procedure SurfaceModified(Sender: TObject);
    procedure SurfaceSelChanged(Sender: TObject);
    procedure InspectorChanged(Sender: TObject);
    procedure FormKeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure BuildUI;
    procedure UpdateZoomLabel;
    procedure UpdateStatus;
  public
    constructor CreateForReport(AOwner: TComponent; AReport: TrhReport);
    class function Execute(AReport: TrhReport): Boolean;
  end;

implementation

uses
  rh.Preview.Form;

const
  BAND_TYPES: array[0..8] of TrhBandType = (
    rhbtReportTitle, rhbtPageHeader, rhbtGroupHeader, rhbtMasterData,
    rhbtDetailData, rhbtGroupFooter, rhbtSummary, rhbtPageFooter, rhbtChild);

{ TrhDesignerForm }

constructor TrhDesignerForm.CreateForReport(AOwner: TComponent; AReport: TrhReport);
begin
  inherited CreateNew(AOwner);
  FReport := AReport;
  BuildUI;
  if FReport <> nil then
    FSnapshot := FReport.ToJSONString(False);
  FSurface.LoadReport(FReport);
  UpdateZoomLabel;
  UpdateStatus;
end;

class function TrhDesignerForm.Execute(AReport: TrhReport): Boolean;
var
  Form: TrhDesignerForm;
begin
  Form := TrhDesignerForm.CreateForReport(nil, AReport);
  try
    Result := Form.ShowModal = mrOk;
    if (not Result) and (AReport <> nil) then
      AReport.LoadFromJSONString(Form.FSnapshot);
  finally
    Form.Free;
  end;
end;

procedure TrhDesignerForm.BuildUI;
var
  Bottom, RightPanel: TPanel;
  Splitter: TSplitter;
  BtnOK, BtnCancel: TButton;
  I: Integer;
begin
  Caption := 'ReportsHowie - Designer';
  Position := poScreenCenter;
  Width := 1000;
  Height := 700;
  KeyPreview := True;
  OnKeyDown := FormKeyDownHandler;

  // ---- toolbar ----
  FToolbar := TFlowPanel.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := alTop;
  FToolbar.Height := 40;
  FToolbar.AutoWrap := True;
  FToolbar.BevelOuter := bvNone;
  FToolbar.Padding.SetBounds(4, 6, 4, 4);

  AddButton('Zoom -', 60, DoZoomOut);
  FZoomLabel := TLabel.Create(Self);
  FZoomLabel.Parent := FToolbar;
  FZoomLabel.Layout := tlCenter;
  FZoomLabel.AlignWithMargins := True;
  FZoomLabel.Caption := '100%';
  AddButton('Zoom +', 60, DoZoomIn);
  AddSeparator;
  AddButton('+ Texto', 66, DoAddText);
  AddButton('+ Imagem', 74, DoAddImage);
  AddButton('+ Linha', 62, DoAddLine);
  AddButton('+ Forma', 66, DoAddShape);
  AddButton('Excluir Obj', 78, DoDelObj);
  AddSeparator;

  FBandCombo := TComboBox.Create(Self);
  FBandCombo.Parent := FToolbar;
  FBandCombo.Style := csDropDownList;
  FBandCombo.Width := 150;
  FBandCombo.AlignWithMargins := True;
  for I := Low(BAND_TYPES) to High(BAND_TYPES) do
    FBandCombo.Items.Add(BandCaption(BAND_TYPES[I]));
  FBandCombo.ItemIndex := 3; // Dados
  AddButton('+ Banda', 66, DoAddBand);
  AddButton('Excluir Banda', 92, DoDelBand);
  AddSeparator;
  AddButton('Preview', 70, DoPreview);

  // ---- rodape com OK/Cancelar ----
  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 44;
  Bottom.BevelOuter := bvNone;

  BtnCancel := TButton.Create(Self);
  BtnCancel.Parent := Bottom;
  BtnCancel.Caption := 'Cancelar';
  BtnCancel.Width := 100;
  BtnCancel.Height := 30;
  BtnCancel.Top := 7;
  BtnCancel.Left := Bottom.Width - 110;
  BtnCancel.Anchors := [akTop, akRight];
  BtnCancel.Cancel := True;
  BtnCancel.OnClick := DoCancel;

  BtnOK := TButton.Create(Self);
  BtnOK.Parent := Bottom;
  BtnOK.Caption := 'OK';
  BtnOK.Width := 100;
  BtnOK.Height := 30;
  BtnOK.Top := 7;
  BtnOK.Left := Bottom.Width - 220;
  BtnOK.Anchors := [akTop, akRight];
  BtnOK.Default := True;
  BtnOK.OnClick := DoOK;

  // ---- status ----
  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;

  // ---- inspetor (direita) ----
  RightPanel := TPanel.Create(Self);
  RightPanel.Parent := Self;
  RightPanel.Align := alRight;
  RightPanel.Width := 250;
  RightPanel.BevelOuter := bvNone;

  FInspHeader := TLabel.Create(Self);
  FInspHeader.Parent := RightPanel;
  FInspHeader.Align := alTop;
  FInspHeader.Height := 22;
  FInspHeader.Alignment := taCenter;
  FInspHeader.Layout := tlCenter;
  FInspHeader.Caption := 'Propriedades';
  FInspHeader.Color := clBtnFace;
  FInspHeader.Transparent := False;
  FInspHeader.Font.Style := [fsBold];

  FInspector := TrhInspector.Create(Self);
  FInspector.Parent := RightPanel;
  FInspector.Align := alClient;
  FInspector.OnChanged := InspectorChanged;

  Splitter := TSplitter.Create(Self);
  Splitter.Parent := Self;
  Splitter.Align := alRight;
  Splitter.Width := 4;

  // ---- area de design ----
  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := alClient;
  FScroll.Color := clBtnFace;
  FScroll.HorzScrollBar.Tracking := True;
  FScroll.VertScrollBar.Tracking := True;

  FSurface := TrhDesignSurface.Create(Self);
  FSurface.Parent := FScroll;
  FSurface.Left := 0;
  FSurface.Top := 0;
  FSurface.OnModified := SurfaceModified;
  FSurface.OnSelectionChanged := SurfaceSelChanged;
end;

function TrhDesignerForm.AddButton(const Caption: string; AWidth: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FToolbar;
  Result.Caption := Caption;
  Result.Width := AWidth;
  Result.Height := 26;
  Result.AlignWithMargins := True;
  Result.OnClick := AClick;
end;

procedure TrhDesignerForm.AddSeparator;
var
  P: TPanel;
begin
  P := TPanel.Create(Self);
  P.Parent := FToolbar;
  P.Width := 10;
  P.Height := 26;
  P.BevelOuter := bvNone;
  P.Caption := '';
end;

procedure TrhDesignerForm.DoAddText(Sender: TObject);
begin
  FSurface.AddObjectOfClass(TrhTextObject);
end;

procedure TrhDesignerForm.DoAddImage(Sender: TObject);
begin
  FSurface.AddObjectOfClass(TrhImageObject);
end;

procedure TrhDesignerForm.DoAddLine(Sender: TObject);
begin
  FSurface.AddObjectOfClass(TrhLineObject);
end;

procedure TrhDesignerForm.DoAddShape(Sender: TObject);
begin
  FSurface.AddObjectOfClass(TrhShapeObject);
end;

procedure TrhDesignerForm.DoDelObj(Sender: TObject);
begin
  FSurface.DeleteSelected;
end;

procedure TrhDesignerForm.DoAddBand(Sender: TObject);
begin
  if FBandCombo.ItemIndex >= 0 then
    FSurface.AddBand(BAND_TYPES[FBandCombo.ItemIndex]);
end;

procedure TrhDesignerForm.DoDelBand(Sender: TObject);
begin
  if FSurface.SelectedBand = nil then
    ShowMessage('Selecione uma banda (clique na faixa) para excluir.')
  else if MessageDlg('Excluir a banda selecionada e seus objetos?',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    FSurface.DeleteSelectedBand;
end;

procedure TrhDesignerForm.DoZoomIn(Sender: TObject);
begin
  FSurface.Zoom := FSurface.Zoom + 25;
  UpdateZoomLabel;
end;

procedure TrhDesignerForm.DoZoomOut(Sender: TObject);
begin
  FSurface.Zoom := FSurface.Zoom - 25;
  UpdateZoomLabel;
end;

procedure TrhDesignerForm.DoPreview(Sender: TObject);
begin
  if FReport <> nil then
    FReport.ShowPreview;
end;

procedure TrhDesignerForm.DoOK(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TrhDesignerForm.DoCancel(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TrhDesignerForm.SurfaceModified(Sender: TObject);
begin
  FInspector.RefreshValues;
  UpdateStatus;
end;

procedure TrhDesignerForm.SurfaceSelChanged(Sender: TObject);
begin
  if FSurface.Selected <> nil then
  begin
    FInspHeader.Caption := 'Objeto selecionado';
    FInspector.Inspect(FSurface.Selected);
  end
  else if FSurface.SelectedBand <> nil then
  begin
    FInspHeader.Caption := 'Banda selecionada';
    FInspector.Inspect(FSurface.SelectedBand);
  end
  else
  begin
    FInspHeader.Caption := 'Propriedades';
    FInspector.Inspect(nil);
  end;
  UpdateStatus;
end;

procedure TrhDesignerForm.InspectorChanged(Sender: TObject);
begin
  FSurface.RebuildLayout; // props podem mudar altura de banda/geometria
  UpdateStatus;
end;

procedure TrhDesignerForm.FormKeyDownHandler(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_DELETE) and (FSurface.Selected <> nil) and
     (not (ActiveControl is TComboBox)) then
  begin
    FSurface.DeleteSelected;
    Key := 0;
  end;
end;

procedure TrhDesignerForm.UpdateZoomLabel;
begin
  FZoomLabel.Caption := IntToStr(FSurface.Zoom) + '%';
end;

procedure TrhDesignerForm.UpdateStatus;
var
  Obj: TrhReportObject;
begin
  Obj := FSurface.Selected;
  if Obj <> nil then
    FStatus.SimpleText := Format('  %s  |  L:%.1f T:%.1f  L:%.1f A:%.1f mm',
      [Obj.ClassName, Obj.Left / 10, Obj.Top / 10, Obj.Width / 10, Obj.Height / 10])
  else if FSurface.SelectedBand <> nil then
    FStatus.SimpleText := '  Banda: ' + BandCaption(FSurface.SelectedBand.BandType)
  else
    FStatus.SimpleText := '  Clique numa banda para selecionar; use a toolbar para inserir objetos.';
end;

end.
