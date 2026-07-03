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
  Vcl.ComCtrls, Vcl.Buttons, Vcl.Dialogs,
  rh.Types, rh.Model.Types, rh.Objects, rh.Bands, rh.Page, rh.Report,
  rh.Design.Surface, rh.Design.Inspector, rh.Design.Data;

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
    FData: TrhDesignData;
    FOwnedData: TrhDesignData;              // instancias criadas por Atualizar (a form libera)
    FOnCollectData: TFunc<TrhDesignData>;   // recoleta dados sob demanda (design-time)
    FDataTree: TTreeView;
    FDataPanel: TPanel;
    FDataSplitter: TSplitter;
    FStructTree: TTreeView;   // outline de estrutura (Fase 5.3)
    FSyncing: Boolean;        // guarda contra recursao entre outline <-> surface
    FStructSig: string;       // assinatura da estrutura (rebuild so quando muda)
    FCurGroup: TPanel;
    FGroupX: Integer;
    function BeginGroup(const ACaption: string; AWidth: Integer): TPanel;
    function GBtn(const ACaption, AHint: string; AWidth: Integer;
      AClick: TNotifyEvent): TSpeedButton;
    procedure DoAddText(Sender: TObject);
    procedure DoAddImage(Sender: TObject);
    procedure DoAddLine(Sender: TObject);
    procedure DoAddShape(Sender: TObject);
    procedure DoAddBarcode(Sender: TObject);
    procedure DoAddChart(Sender: TObject);
    procedure DoDelObj(Sender: TObject);
    procedure DoAddBand(Sender: TObject);
    procedure DoDelBand(Sender: TObject);
    procedure DoBandUp(Sender: TObject);
    procedure DoBandDown(Sender: TObject);
    procedure DoZoomIn(Sender: TObject);
    procedure DoZoomOut(Sender: TObject);
    procedure DoOpenFile(Sender: TObject);
    procedure DoSaveFile(Sender: TObject);
    procedure DoPreview(Sender: TObject);
    procedure DoHelp(Sender: TObject);
    procedure DoAlign(Sender: TObject);
    procedure DoDistribute(Sender: TObject);
    procedure DoOK(Sender: TObject);
    procedure DoCancel(Sender: TObject);
    procedure SurfaceModified(Sender: TObject);
    procedure SurfaceSelChanged(Sender: TObject);
    procedure InspectorChanged(Sender: TObject);
    procedure InspectorBeforeChange(Sender: TObject);
    procedure FormKeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure BuildUI;
    procedure BuildDataPanel;
    procedure PopulateDataTree;
    procedure UpdateInspectorFields;
    procedure DoRefreshData(Sender: TObject);
    procedure DataTreeDblClick(Sender: TObject);
    procedure DoInsertField(Sender: TObject);
    procedure SurfaceDragOver(Sender, Source: TObject; X, Y: Integer;
      State: TDragState; var Accept: Boolean);
    procedure SurfaceDragDrop(Sender, Source: TObject; X, Y: Integer);
    // outline de estrutura (Fase 5.3)
    procedure StructTreeChange(Sender: TObject; Node: TTreeNode);
    procedure RebuildStructTree;
    procedure SyncStructToSurface;
    function FindStructNode(Target: TObject): TTreeNode;
    function StructSignature: string;
    function ObjOutlineLabel(Obj: TrhReportObject): string;
    procedure UpdateZoomLabel;
    procedure UpdateStatus;
  public
    constructor CreateForReport(AOwner: TComponent; AReport: TrhReport;
      AData: TrhDesignData; AOnCollectData: TFunc<TrhDesignData> = nil);
    destructor Destroy; override;
    class function Execute(AReport: TrhReport; AData: TrhDesignData = nil;
      AOnCollectData: TFunc<TrhDesignData> = nil): Boolean;
  end;

implementation

uses
  Winapi.ShellAPI, System.IOUtils,
  rh.Preview.Form;

const
  // documentacao online em HTML (GitHub Pages serve o docs/index.html);
  // usada quando nao ha o docs\index.html local proximo ao executavel.
  RH_HELP_URL = 'https://howardroatti.github.io/ReportsHowie/';

  BAND_TYPES: array[0..8] of TrhBandType = (
    rhbtReportTitle, rhbtPageHeader, rhbtGroupHeader, rhbtMasterData,
    rhbtDetailData, rhbtGroupFooter, rhbtSummary, rhbtPageFooter, rhbtChild);

{ TrhDesignerForm }

constructor TrhDesignerForm.CreateForReport(AOwner: TComponent; AReport: TrhReport;
  AData: TrhDesignData; AOnCollectData: TFunc<TrhDesignData>);
begin
  inherited CreateNew(AOwner);
  FReport := AReport;
  FData := AData;
  FOnCollectData := AOnCollectData;
  BuildUI;
  if FReport <> nil then
    FSnapshot := FReport.ToJSONString(False);
  FSurface.LoadReport(FReport);
  RebuildStructTree;
  UpdateInspectorFields;
  UpdateZoomLabel;
  UpdateStatus;
end;

destructor TrhDesignerForm.Destroy;
begin
  FOwnedData.Free; // libera as instancias criadas por Atualizar (nil-safe)
  inherited Destroy;
end;

class function TrhDesignerForm.Execute(AReport: TrhReport; AData: TrhDesignData;
  AOnCollectData: TFunc<TrhDesignData>): Boolean;
var
  Form: TrhDesignerForm;
begin
  Form := TrhDesignerForm.CreateForReport(nil, AReport, AData, AOnCollectData);
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
  Bottom, RightPanel, StructPanel: TPanel;
  Splitter, StructSplit: TSplitter;
  StructHeader: TLabel;
  ToolHost: TScrollBox;
  BtnOK, BtnCancel: TButton;
  I: Integer;
begin
  Caption := 'ReportsHowie - Designer';
  Position := poScreenCenter;
  Width := 1000;
  Height := 700;
  KeyPreview := True;
  OnKeyDown := FormKeyDownHandler;

  // ---- toolbar estilo ribbon (altura fixa; rola na horizontal quando estreita) ----
  ToolHost := TScrollBox.Create(Self);
  ToolHost.Parent := Self;
  ToolHost.Align := alTop;
  ToolHost.Height := 68;
  ToolHost.BorderStyle := bsNone;
  ToolHost.ParentColor := False;
  ToolHost.Color := clWindow;
  ToolHost.VertScrollBar.Visible := False;
  ToolHost.HorzScrollBar.Tracking := True;

  FToolbar := TFlowPanel.Create(Self);
  FToolbar.Parent := ToolHost;
  FToolbar.Left := 0;
  FToolbar.Top := 0;
  FToolbar.AutoWrap := False;   // uma linha; excedente vira rolagem horizontal
  FToolbar.AutoSize := True;    // largura acompanha o conteudo
  FToolbar.BevelOuter := bvNone;
  FToolbar.ParentBackground := False;
  FToolbar.ParentColor := False;
  FToolbar.Color := clWindow;
  FToolbar.Padding.SetBounds(6, 4, 6, 2);

  // grupo Arquivo
  BeginGroup('Arquivo', 130);
  GBtn('Abrir', 'Abrir um template .rhr', 54, DoOpenFile);
  GBtn('Salvar', 'Salvar o template atual em .rhr', 58, DoSaveFile);

  // grupo Zoom
  BeginGroup('Zoom', 150);
  GBtn('-', 'Diminuir zoom', 30, DoZoomOut);
  FZoomLabel := TLabel.Create(Self);
  FZoomLabel.Parent := FCurGroup;
  FZoomLabel.SetBounds(FGroupX, 14, 46, 18);
  FZoomLabel.Alignment := taCenter;
  FZoomLabel.Layout := tlCenter;
  FZoomLabel.Transparent := True;
  FZoomLabel.Caption := '100%';
  Inc(FGroupX, 48);
  GBtn('+', 'Aumentar zoom', 30, DoZoomIn);

  // grupo Inserir (clique no botao e depois clique na superficie p/ posicionar)
  BeginGroup('Inserir', 330);
  GBtn('Texto', 'Inserir texto: clique aqui e depois na superficie', 54, DoAddText);
  GBtn('Imagem', 'Inserir imagem: clique aqui e depois na superficie', 60, DoAddImage);
  GBtn('Linha', 'Inserir linha: clique aqui e depois na superficie', 50, DoAddLine);
  GBtn('Forma', 'Inserir forma: clique aqui e depois na superficie', 54, DoAddShape);
  GBtn('Barras', 'Inserir codigo de barras (Code128/Code39/QR): clique e posicione', 54, DoAddBarcode);
  GBtn('Grafico', 'Inserir grafico (barras/linha/pizza): clique e posicione', 58, DoAddChart);
  GBtn('Excluir', 'Excluir objeto(s) selecionado(s)  (Del)', 58, DoDelObj);

  // grupo Banda
  BeginGroup('Banda', 312);
  FBandCombo := TComboBox.Create(Self);
  FBandCombo.Parent := FCurGroup;
  FBandCombo.Style := csDropDownList;
  FBandCombo.SetBounds(FGroupX, 11, 128, 24);
  FBandCombo.Hint := 'Tipo de banda a inserir';
  FBandCombo.ShowHint := True;
  for I := Low(BAND_TYPES) to High(BAND_TYPES) do
    FBandCombo.Items.Add(BandCaption(BAND_TYPES[I]));
  FBandCombo.ItemIndex := 3; // Dados
  Inc(FGroupX, 132);
  GBtn('+ Banda', 'Inserir banda do tipo escolhido', 62, DoAddBand);
  GBtn('Excluir', 'Excluir a banda selecionada', 54, DoDelBand);
  GBtn(#$25B2, 'Subir a banda selecionada', 28, DoBandUp);
  GBtn(#$25BC, 'Descer a banda selecionada', 28, DoBandDown);

  // grupo Alinhar (glifos via #$XXXX = seguros no source ANSI)
  BeginGroup('Alinhar', 250);
  GBtn(#$21E4, 'Alinhar a esquerda', 32, DoAlign).Tag := Ord(ramLeft);
  GBtn(#$21D4, 'Centralizar na horizontal', 32, DoAlign).Tag := Ord(ramHCenter);
  GBtn(#$21E5, 'Alinhar a direita', 32, DoAlign).Tag := Ord(ramRight);
  GBtn(#$2912, 'Alinhar ao topo', 32, DoAlign).Tag := Ord(ramTop);
  GBtn(#$21D5, 'Centralizar na vertical', 32, DoAlign).Tag := Ord(ramVCenter);
  GBtn(#$2913, 'Alinhar a base', 32, DoAlign).Tag := Ord(ramBottom);
  GBtn(#$2194, 'Distribuir na horizontal', 32, DoDistribute).Tag := 0;
  GBtn(#$2195, 'Distribuir na vertical', 32, DoDistribute).Tag := 1;

  // grupo Ver
  BeginGroup('Ver', 150);
  GBtn('Preview', 'Pre-visualizar o template', 72, DoPreview);
  GBtn('Ajuda', 'Abrir a documentacao (manual)', 60, DoHelp);
  FCurGroup.Width := FGroupX + 6; // finaliza o ultimo grupo

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

  // ---- painel direito: Estrutura (topo) + Propriedades (baixo) ----
  RightPanel := TPanel.Create(Self);
  RightPanel.Parent := Self;
  RightPanel.Align := alRight;
  RightPanel.Width := 250;
  RightPanel.BevelOuter := bvNone;

  // Estrutura (outline pagina -> banda -> objeto) — Fase 5.3
  StructPanel := TPanel.Create(Self);
  StructPanel.Parent := RightPanel;
  StructPanel.Align := alTop;
  StructPanel.Height := 220;
  StructPanel.BevelOuter := bvNone;

  StructHeader := TLabel.Create(Self);
  StructHeader.Parent := StructPanel;
  StructHeader.Align := alTop;
  StructHeader.Height := 22;
  StructHeader.Alignment := taCenter;
  StructHeader.Layout := tlCenter;
  StructHeader.Caption := 'Estrutura';
  StructHeader.Color := clBtnFace;
  StructHeader.Transparent := False;
  StructHeader.Font.Style := [fsBold];

  FStructTree := TTreeView.Create(Self);
  FStructTree.Parent := StructPanel;
  FStructTree.Align := alClient;
  FStructTree.ReadOnly := True;
  FStructTree.HideSelection := False;
  FStructTree.ShowHint := True;
  FStructTree.Hint := 'Estrutura do relatorio. Clique para selecionar a banda/objeto na tela.';
  FStructTree.OnChange := StructTreeChange;

  StructSplit := TSplitter.Create(Self);
  StructSplit.Parent := RightPanel;
  StructSplit.Align := alTop;
  StructSplit.Height := 4;
  StructSplit.MinSize := 80;

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
  FInspector.OnBeforeChange := InspectorBeforeChange;

  Splitter := TSplitter.Create(Self);
  Splitter.Parent := Self;
  Splitter.Align := alRight;
  Splitter.Width := 4;

  // ---- painel de dados (esquerda), so se houver datasets ----
  BuildDataPanel;

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
  FSurface.OnDragOver := SurfaceDragOver; // drag-to-bind (arrastar campo -> objeto)
  FSurface.OnDragDrop := SurfaceDragDrop;
end;

procedure TrhDesignerForm.BuildDataPanel;
var
  Header: TPanel;
  Cap: TLabel;
  BtnRefresh, BtnIns: TButton;
begin
  // mostra o painel quando ja ha datasets OU quando da para recoletar sob demanda
  // (design-time). No runtime embutido sem callback e sem dados, fica oculto.
  if ((FData = nil) or (FData.Count = 0)) and (not Assigned(FOnCollectData)) then
    Exit;

  FDataPanel := TPanel.Create(Self);
  FDataPanel.Parent := Self;
  FDataPanel.Align := alLeft;
  FDataPanel.Width := 200;
  FDataPanel.BevelOuter := bvNone;

  // cabecalho: titulo + botao Atualizar (recoleta datasets do IDE sob demanda)
  Header := TPanel.Create(Self);
  Header.Parent := FDataPanel;
  Header.Align := alTop;
  Header.Height := 22;
  Header.BevelOuter := bvNone;
  Header.Color := clBtnFace;
  Header.ParentBackground := False;

  Cap := TLabel.Create(Self);
  Cap.Parent := Header;
  Cap.Align := alClient;
  Cap.Alignment := taCenter;
  Cap.Layout := tlCenter;
  Cap.Caption := 'Dados (campos)';
  Cap.Transparent := True;
  Cap.Font.Style := [fsBold];

  if Assigned(FOnCollectData) then
  begin
    BtnRefresh := TButton.Create(Self);
    BtnRefresh.Parent := Header;
    BtnRefresh.Align := alRight;
    BtnRefresh.Width := 64;
    BtnRefresh.Caption := 'Atualizar';
    BtnRefresh.Hint := 'Recoletar os datasets abertos no IDE ' +
      '(use apos adicionar/alterar TDataSource ou abrir um DataModule).';
    BtnRefresh.ShowHint := True;
    BtnRefresh.OnClick := DoRefreshData;
  end;

  BtnIns := TButton.Create(Self);
  BtnIns.Parent := FDataPanel;
  BtnIns.Align := alBottom;
  BtnIns.Height := 28;
  BtnIns.Caption := 'Inserir campo na banda';
  BtnIns.OnClick := DoInsertField;

  FDataTree := TTreeView.Create(Self);
  FDataTree.Parent := FDataPanel;
  FDataTree.Align := alClient;
  FDataTree.ReadOnly := True;
  FDataTree.HideSelection := False;
  FDataTree.OnDblClick := DataTreeDblClick;
  FDataTree.DragMode := dmAutomatic; // permite arrastar campo p/ a superficie
  FDataTree.ShowHint := True;
  FDataTree.Hint := 'Arraste um campo para a superficie (sobre um objeto = vincula; ' +
    'em area vazia = cria texto vinculado). Ou duplo-clique para inserir.';

  PopulateDataTree;

  FDataSplitter := TSplitter.Create(Self);
  FDataSplitter.Parent := Self;
  FDataSplitter.Align := alLeft;
  FDataSplitter.Width := 4;
end;

procedure TrhDesignerForm.PopulateDataTree;
var
  I, J: Integer;
  DsNode: TTreeNode;
begin
  if FDataTree = nil then Exit;
  FDataTree.Items.BeginUpdate;
  try
    FDataTree.Items.Clear;
    if FData <> nil then
      for I := 0 to FData.Count - 1 do
      begin
        DsNode := FDataTree.Items.Add(nil, FData.DatasetName(I));
        for J := 0 to FData.Fields(I).Count - 1 do
          FDataTree.Items.AddChild(DsNode, FData.Fields(I)[J]);
      end;
  finally
    FDataTree.Items.EndUpdate;
  end;
  if FDataTree.Items.Count > 0 then
    FDataTree.Items[0].Expand(True);
end;

// Junta (dedup) os campos de todos os datasets e entrega ao inspetor, para o
// editor de expressao (botao "...") oferecer os campos disponiveis.
procedure TrhDesignerForm.UpdateInspectorFields;
var
  Fields: TStringList;
  I, J: Integer;
begin
  if FInspector = nil then Exit;
  Fields := TStringList.Create;
  try
    Fields.Duplicates := dupIgnore;
    Fields.Sorted := True;
    if FData <> nil then
      for I := 0 to FData.Count - 1 do
        for J := 0 to FData.Fields(I).Count - 1 do
          Fields.Add(FData.Fields(I)[J]);
    FInspector.SetFields(Fields);
  finally
    Fields.Free;
  end;
end;

procedure TrhDesignerForm.DoRefreshData(Sender: TObject);
var
  NewData: TrhDesignData;
begin
  if not Assigned(FOnCollectData) then Exit;
  NewData := FOnCollectData();
  if NewData = nil then Exit;
  // troca a fonte atual pela recem-coletada; a form passa a ser dona dela
  FOwnedData.Free;
  FOwnedData := NewData;
  FData := NewData;
  PopulateDataTree;
  UpdateInspectorFields;
  // feedback: confirma que a coleta rodou e quantos datasets estao visiveis
  // (sem esse aviso, clicar e nao ver mudanca parece que "nao funcionou").
  if FStatus <> nil then
    FStatus.SimpleText := Format('  Dados atualizados: %d dataset(s) encontrado(s).',
      [FData.Count]);
end;

procedure TrhDesignerForm.DoInsertField(Sender: TObject);
var
  Node: TTreeNode;
begin
  if FDataTree = nil then Exit;
  Node := FDataTree.Selected;
  if (Node = nil) or (Node.Parent = nil) then
  begin
    ShowMessage('Selecione um campo (item filho de um dataset) na arvore.');
    Exit;
  end;
  FSurface.InsertField(Node.Parent.Text, Node.Text);
end;

procedure TrhDesignerForm.DataTreeDblClick(Sender: TObject);
var
  Node: TTreeNode;
begin
  Node := FDataTree.Selected;
  if (Node <> nil) and (Node.Parent <> nil) then
    FSurface.InsertField(Node.Parent.Text, Node.Text);
end;

procedure TrhDesignerForm.SurfaceDragOver(Sender, Source: TObject; X, Y: Integer;
  State: TDragState; var Accept: Boolean);
begin
  // aceita apenas quando a origem e a arvore de dados e o no e um CAMPO (tem pai)
  Accept := (Source = FDataTree) and (FDataTree.Selected <> nil) and
    (FDataTree.Selected.Parent <> nil);
end;

procedure TrhDesignerForm.SurfaceDragDrop(Sender, Source: TObject; X, Y: Integer);
var
  Node: TTreeNode;
begin
  if Source <> FDataTree then Exit;
  Node := FDataTree.Selected;
  if (Node = nil) or (Node.Parent = nil) then Exit;
  // Node.Parent.Text = dataset ; Node.Text = campo
  FSurface.DropField(X, Y, Node.Parent.Text, Node.Text);
end;

{ ---- outline de estrutura (Fase 5.3) ---- }

function TrhDesignerForm.ObjOutlineLabel(Obj: TrhReportObject): string;
var
  S: string;
begin
  if Obj is TrhTextObject then
  begin
    S := TrhTextObject(Obj).DisplayExpression;
    if S = '' then S := '(vazio)';
    if Length(S) > 24 then S := Copy(S, 1, 24) + '...';
    Result := 'Texto: ' + S;
  end
  else if Obj is TrhImageObject then Result := 'Imagem'
  else if Obj is TrhLineObject then Result := 'Linha'
  else if Obj is TrhShapeObject then Result := 'Forma'
  else if Obj is TrhBarcodeObject then Result := 'Barras'
  else if Obj is TrhChartObject then Result := 'Grafico: ' + TrhChartObject(Obj).Title
  else Result := Obj.ClassName;
end;

function TrhDesignerForm.StructSignature: string;
var
  Band: TrhBand;
  I: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    if (FReport <> nil) and (FReport.Pages.Count > 0) then
      for Band in FReport.Pages[0].Bands do
      begin
        SB.Append(Ord(Band.BandType)).Append('#').Append(Band.Objects.Count).Append(';');
        for I := 0 to Band.Objects.Count - 1 do
          SB.Append(Band.Objects[I].ClassName).Append(',');
        SB.Append('|');
      end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TrhDesignerForm.RebuildStructTree;
var
  Page: TrhPage;
  Band: TrhBand;
  I: Integer;
  PageNode, BandNode: TTreeNode;
begin
  if FStructTree = nil then Exit;
  FSyncing := True;
  FStructTree.Items.BeginUpdate;
  try
    FStructTree.Items.Clear;
    if (FReport <> nil) and (FReport.Pages.Count > 0) then
    begin
      Page := FReport.Pages[0];
      PageNode := FStructTree.Items.AddChildObject(nil, 'Pagina', nil);
      for Band in Page.Bands do
      begin
        BandNode := FStructTree.Items.AddChildObject(PageNode,
          BandCaption(Band.BandType), Pointer(Band));
        for I := 0 to Band.Objects.Count - 1 do
          FStructTree.Items.AddChildObject(BandNode,
            ObjOutlineLabel(Band.Objects[I]), Pointer(Band.Objects[I]));
      end;
      PageNode.Expand(True);
    end;
  finally
    FStructTree.Items.EndUpdate;
    FSyncing := False;
  end;
  FStructSig := StructSignature;
  SyncStructToSurface; // realca o no correspondente a selecao atual da tela
end;

function TrhDesignerForm.FindStructNode(Target: TObject): TTreeNode;
var
  I: Integer;
begin
  Result := nil;
  if (FStructTree = nil) or (Target = nil) then Exit;
  for I := 0 to FStructTree.Items.Count - 1 do
    if TObject(FStructTree.Items[I].Data) = Target then
      Exit(FStructTree.Items[I]);
end;

procedure TrhDesignerForm.SyncStructToSurface;
var
  Target: TObject;
  Node: TTreeNode;
begin
  if FSyncing or (FStructTree = nil) then Exit;
  if FSurface.Selected <> nil then
    Target := FSurface.Selected
  else
    Target := FSurface.SelectedBand;
  FSyncing := True;
  try
    Node := FindStructNode(Target);
    if Node <> nil then
      Node.Selected := True
    else
      FStructTree.Selected := nil;
  finally
    FSyncing := False;
  end;
end;

procedure TrhDesignerForm.StructTreeChange(Sender: TObject; Node: TTreeNode);
var
  Obj: TObject;
  Band: TrhBand;
begin
  if FSyncing or (Node = nil) or (Node.Data = nil) then Exit;
  Obj := TObject(Node.Data);
  FSyncing := True;
  try
    if Obj is TrhReportObject then
    begin
      if (Node.Parent <> nil) and (Node.Parent.Data <> nil) and
         (TObject(Node.Parent.Data) is TrhBand) then
        Band := TrhBand(Node.Parent.Data)
      else
        Band := nil;
      FSurface.SelectInOutline(Band, TrhReportObject(Obj));
    end
    else if Obj is TrhBand then
      FSurface.SelectInOutline(TrhBand(Obj), nil);
  finally
    FSyncing := False;
  end;
end;

function TrhDesignerForm.BeginGroup(const ACaption: string; AWidth: Integer): TPanel;
var
  Cap: TLabel;
  Divider: TBevel;
begin
  if FCurGroup <> nil then
  begin
    // finaliza a largura do grupo anterior conforme os botoes adicionados
    FCurGroup.Width := FGroupX + 6;
    // divisoria vertical fina entre grupos
    Divider := TBevel.Create(Self);
    Divider.Parent := FToolbar;
    Divider.Shape := bsLeftLine;
    Divider.Width := 9;
    Divider.Height := 52;
  end;

  Result := TPanel.Create(Self);
  Result.Parent := FToolbar;
  Result.BevelOuter := bvNone;
  Result.ParentBackground := False;
  Result.ParentColor := False;
  Result.Color := clWindow;
  Result.Width := AWidth;       // provisorio; ajustado no proximo BeginGroup
  Result.Height := 56;

  // rotulo do grupo embaixo (estilo faixa do Office)
  Cap := TLabel.Create(Self);
  Cap.Parent := Result;
  Cap.Align := alBottom;
  Cap.Height := 14;
  Cap.Caption := ACaption;
  Cap.Alignment := taCenter;
  Cap.Font.Color := clGrayText;
  Cap.Transparent := True;

  FCurGroup := Result;
  FGroupX := 6;
end;

function TrhDesignerForm.GBtn(const ACaption, AHint: string; AWidth: Integer;
  AClick: TNotifyEvent): TSpeedButton;
begin
  Result := TSpeedButton.Create(Self);
  Result.Parent := FCurGroup;
  Result.Caption := ACaption;
  Result.Flat := True;
  Result.SetBounds(FGroupX, 4, AWidth, 34);
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.OnClick := AClick;
  Inc(FGroupX, AWidth + 4);
end;

procedure TrhDesignerForm.DoAddText(Sender: TObject);
begin
  FSurface.ArmTool(TrhTextObject);
end;

procedure TrhDesignerForm.DoAddImage(Sender: TObject);
begin
  FSurface.ArmTool(TrhImageObject);
end;

procedure TrhDesignerForm.DoAddLine(Sender: TObject);
begin
  FSurface.ArmTool(TrhLineObject);
end;

procedure TrhDesignerForm.DoAddShape(Sender: TObject);
begin
  FSurface.ArmTool(TrhShapeObject);
end;

procedure TrhDesignerForm.DoAddBarcode(Sender: TObject);
begin
  FSurface.ArmTool(TrhBarcodeObject);
end;

procedure TrhDesignerForm.DoAddChart(Sender: TObject);
begin
  FSurface.ArmTool(TrhChartObject);
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

procedure TrhDesignerForm.DoBandUp(Sender: TObject);
begin
  if FSurface.SelectedBand = nil then
    ShowMessage('Selecione uma banda (clique na faixa) para mover.')
  else
    FSurface.MoveBand(-1);
end;

procedure TrhDesignerForm.DoBandDown(Sender: TObject);
begin
  if FSurface.SelectedBand = nil then
    ShowMessage('Selecione uma banda (clique na faixa) para mover.')
  else
    FSurface.MoveBand(1);
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

procedure TrhDesignerForm.DoOpenFile(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  if FReport = nil then Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Relatorio ReportsHowie (*.rhr)|*.rhr|Todos (*.*)|*.*';
    Dlg.DefaultExt := 'rhr';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then
    begin
      FSurface.PushUndoNow; // permite desfazer o carregamento
      FReport.LoadFromFile(Dlg.FileName);
      FSurface.LoadReport(FReport);
      RebuildStructTree;
      UpdateZoomLabel;
      UpdateStatus;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TrhDesignerForm.DoSaveFile(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  if FReport = nil then Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Relatorio ReportsHowie (*.rhr)|*.rhr|Todos (*.*)|*.*';
    Dlg.DefaultExt := 'rhr';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if Dlg.Execute then
      FReport.SaveToFile(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TrhDesignerForm.DoPreview(Sender: TObject);
begin
  if FReport <> nil then
    FReport.ShowPreview;
end;

procedure TrhDesignerForm.DoHelp(Sender: TObject);
var
  Dir, Cand: string;
  I: Integer;
begin
  // 1) documentacao LOCAL: procura docs\index.html subindo a partir do executavel
  Dir := ExtractFilePath(ParamStr(0));
  for I := 0 to 7 do
  begin
    Cand := TPath.Combine(Dir, TPath.Combine('docs', 'index.html'));
    if TFile.Exists(Cand) then
    begin
      ShellExecute(0, 'open', PChar(Cand), nil, nil, SW_SHOWNORMAL);
      Exit;
    end;
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  // 2) fallback: documentacao online
  ShellExecute(0, 'open', PChar(RH_HELP_URL), nil, nil, SW_SHOWNORMAL);
end;

procedure TrhDesignerForm.DoAlign(Sender: TObject);
begin
  if FSurface.SelectionCount < 2 then
    ShowMessage('Selecione dois ou mais objetos (Shift+clique ou arraste um retangulo).')
  else
    FSurface.AlignSelected(TrhAlignMode(TComponent(Sender).Tag));
end;

procedure TrhDesignerForm.DoDistribute(Sender: TObject);
begin
  if FSurface.SelectionCount < 3 then
    ShowMessage('Selecione tres ou mais objetos para distribuir.')
  else
    FSurface.DistributeSelected(TComponent(Sender).Tag = 0);
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
  // rebuild do outline SO quando a estrutura muda (nao a cada move/resize),
  // evitando flicker durante o arraste (OnModified dispara no MouseMove).
  if StructSignature <> FStructSig then
    RebuildStructTree;
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
  SyncStructToSurface; // reflete a selecao da tela no outline
end;

procedure TrhDesignerForm.InspectorChanged(Sender: TObject);
begin
  FSurface.RebuildLayout; // props podem mudar altura de banda/geometria
  UpdateStatus;
  RebuildStructTree;      // rotulos do outline (ex.: texto/DataField) podem ter mudado
end;

procedure TrhDesignerForm.InspectorBeforeChange(Sender: TObject);
begin
  FSurface.PushUndoNow; // snapshot antes de aplicar a mudanca do inspetor
end;

procedure TrhDesignerForm.FormKeyDownHandler(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  // Ctrl+Z: desfazer (nao interceptar se estiver editando texto num TEdit)
  if (ssCtrl in Shift) and (Key = Ord('Z')) and
     (not (ActiveControl is TCustomEdit)) then
  begin
    FSurface.Undo;
    Key := 0;
    Exit;
  end;
  // Ctrl+Y: refazer
  if (ssCtrl in Shift) and (Key = Ord('Y')) and
     (not (ActiveControl is TCustomEdit)) then
  begin
    FSurface.Redo;
    Key := 0;
    Exit;
  end;
  // Esc: cancela a ferramenta armada (click-to-place)
  if Key = VK_ESCAPE then
  begin
    FSurface.ArmTool(nil);
    Key := 0;
    Exit;
  end;
  if (Key = VK_DELETE) and (FSurface.Selected <> nil) and
     (not (ActiveControl is TCustomEdit)) and (not (ActiveControl is TComboBox)) then
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
