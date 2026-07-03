{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Component editor do TrhReport (design-time). Duplo-clique no componente (ou
///   o verbo "Abrir Designer") abre o TrhDesignerForm modal; ao confirmar (OK),
///   chama Designer.Modified para que o IDE regrave o template no DFM (blob
///   'ReportData' via DefineBinaryProperty). Referencia DesignIntf — vive apenas
///   no pacote design-time.
/// </summary>
unit rh.Design.ComponentEditor;

interface

uses
  DesignIntf, DesignEditors;

type
  TrhReportComponentEditor = class(TComponentEditor)
  private
    function CollectDesignData: TObject; // retorna TrhDesignData
    procedure ImportFastReport;          // verbo "Importar FastReport (.frx)..."
  public
    procedure Edit; override;
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

implementation

uses
  System.Classes, System.SysUtils, System.UITypes, Data.DB, ToolsAPI,
  Vcl.Dialogs,
  rh.Report, rh.Page, rh.Import.FastReport,
  rh.Design.Designer.Form, rh.Design.Data, rh.Preview.Form;

function ReportHasContent(R: TrhReport): Boolean;
var
  P: Integer;
begin
  Result := False;
  for P := 0 to R.Pages.Count - 1 do
    if R.Pages[P].Bands.Count > 0 then
      Exit(True);
end;

function TrhReportComponentEditor.CollectDesignData: TObject;
var
  Data: TrhDesignData;
  Root: TComponent;
  I: Integer;
  Flds, Seen: TStringList;

  // Coleta os campos de um dataset (persistentes ou via FieldDefs). Evita
  // duplicar quando o mesmo dataset e achado direto e via TDataSource.
  procedure AddDS(DS: TDataSet);
  var
    J: Integer;
  begin
    if (DS = nil) or (DS.Name = '') then Exit;
    if Seen.IndexOf(DS.Name) >= 0 then Exit;
    Seen.Add(DS.Name);
    Flds.Clear;
    try
      if DS.Fields.Count > 0 then
      begin
        for J := 0 to DS.Fields.Count - 1 do
          Flds.Add(DS.Fields[J].FieldName);
      end
      else
      begin
        DS.FieldDefs.Update;
        for J := 0 to DS.FieldDefs.Count - 1 do
          Flds.Add(DS.FieldDefs[J].Name);
      end;
    except
      // dataset fechado/sem conexao: fica so o nome, sem campos
    end;
    Data.AddDataset(DS.Name, Flds);
  end;

  // Enumera os modulos ABERTOS no IDE (via ToolsAPI) e coleta os TDataSet do
  // root de cada um — pega datasets de DataModules mesmo SEM um TDataSource no
  // form. Falhas de ToolsAPI sao silenciadas (o designer segue com o que achou).
  procedure ScanOpenModules;
  var
    MS: IOTAModuleServices;
    M: IOTAModule;
    Ed: IOTAEditor;
    FE: IOTAFormEditor;
    RootIntf: IOTAComponent;
    NativeRoot: TComponent;
    MI, EI, CI: Integer;
  begin
    try
      if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
      for MI := 0 to MS.ModuleCount - 1 do
      begin
        M := MS.Modules[MI];
        if M = nil then Continue;
        // acha o editor de formulario/datamodule do modulo (se houver)
        FE := nil;
        for EI := 0 to M.GetModuleFileCount - 1 do
        begin
          Ed := M.GetModuleFileEditor(EI);
          if Supports(Ed, IOTAFormEditor, FE) then Break;
        end;
        if FE = nil then Continue;
        RootIntf := FE.GetRootComponent;
        if (RootIntf = nil) or (not Supports(RootIntf, INTAComponent)) then Continue;
        NativeRoot := (RootIntf as INTAComponent).GetComponent;
        if NativeRoot = nil then Continue;
        for CI := 0 to NativeRoot.ComponentCount - 1 do
          if NativeRoot.Components[CI] is TDataSet then
            AddDS(TDataSet(NativeRoot.Components[CI]));
      end;
    except
      // ToolsAPI indisponivel/erro: ignora e mantem os datasets ja coletados
    end;
  end;

begin
  Data := TrhDesignData.Create;
  Result := Data;
  if Designer = nil then Exit;
  Root := Designer.Root;
  if Root = nil then Exit;
  Flds := TStringList.Create;
  Seen := TStringList.Create;
  try
    // 1) datasets que vivem no proprio form/DM sendo desenhado
    for I := 0 to Root.ComponentCount - 1 do
      if Root.Components[I] is TDataSet then
        AddDS(TDataSet(Root.Components[I]));
    // 2) datasets referenciados por TDataSource no form (resolve a referencia,
    //    inclusive quando o dataset mora em OUTRO DataModule aberto no IDE)
    for I := 0 to Root.ComponentCount - 1 do
      if Root.Components[I] is TDataSource then
        AddDS(TDataSource(Root.Components[I]).DataSet);
    // 3) datasets de QUALQUER DataModule/form aberto no IDE (via ToolsAPI)
    ScanOpenModules;
  finally
    Flds.Free;
    Seen.Free;
  end;
end;

procedure TrhReportComponentEditor.Edit;
begin
  ExecuteVerb(0);
end;

function TrhReportComponentEditor.GetVerbCount: Integer;
begin
  Result := 3;
end;

function TrhReportComponentEditor.GetVerb(Index: Integer): string;
begin
  case Index of
    0: Result := 'Abrir &Designer...';
    1: Result := 'Pre&view do template';
    2: Result := 'Importar &FastReport (.frx)...';
  else
    Result := '';
  end;
end;

procedure TrhReportComponentEditor.ExecuteVerb(Index: Integer);
var
  Data: TrhDesignData;
begin
  if not (Component is TrhReport) then Exit;
  case Index of
    0:
      begin
        Data := TrhDesignData(CollectDesignData);
        try
          // callback de Atualizar: recoleta os datasets abertos no IDE sob demanda
          if TrhDesignerForm.Execute(TrhReport(Component), Data,
               function: TrhDesignData
               begin
                 Result := TrhDesignData(CollectDesignData);
               end) then
            if Designer <> nil then
              Designer.Modified;
        finally
          Data.Free;
        end;
      end;
    1:
      TrhReport(Component).ShowPreview;
    2:
      ImportFastReport;
  end;
end;

procedure TrhReportComponentEditor.ImportFastReport;
var
  Dlg: TOpenDialog;
  FileName: string;
  Imp: TrhFastReportImporter;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := 'Importar template FastReport';
    Dlg.Filter := 'FastReport (*.frx)|*.frx|Todos os arquivos (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist, ofPathMustExist];
    if not Dlg.Execute then Exit;
    FileName := Dlg.FileName;
  finally
    Dlg.Free;
  end;

  // importar SUBSTITUI o conteudo atual (ImportXML chama Clear): confirma se houver
  if ReportHasContent(TrhReport(Component)) then
    if MessageDlg('Importar vai SUBSTITUIR o conteudo atual do relatorio.'#13#10 +
         'Deseja continuar?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;

  Imp := TrhFastReportImporter.Create;
  try
    try
      Imp.ImportFile(FileName, TrhReport(Component));
      if Designer <> nil then
        Designer.Modified;
      if Imp.Warnings.Count > 0 then
        MessageDlg(Format('Importado com %d aviso(s):'#13#10#13#10'%s',
          [Imp.Warnings.Count, Imp.Warnings.Text]), mtWarning, [mbOK], 0)
      else
        MessageDlg('Template FastReport importado com sucesso.',
          mtInformation, [mbOK], 0);
    except
      on E: Exception do
        MessageDlg('Falha ao importar "' + FileName + '":'#13#10 + E.Message,
          mtError, [mbOK], 0);
    end;
  finally
    Imp.Free;
  end;
end;

end.
