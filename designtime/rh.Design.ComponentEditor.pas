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
  public
    procedure Edit; override;
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

implementation

uses
  System.Classes, Data.DB,
  rh.Report, rh.Design.Designer.Form, rh.Design.Data, rh.Preview.Form;

function TrhReportComponentEditor.CollectDesignData: TObject;
var
  Data: TrhDesignData;
  Root: TComponent;
  I, J: Integer;
  DS: TDataSet;
  Flds: TStringList;
begin
  Data := TrhDesignData.Create;
  Result := Data;
  if Designer = nil then Exit;
  Root := Designer.Root;
  if Root = nil then Exit;
  Flds := TStringList.Create;
  try
    for I := 0 to Root.ComponentCount - 1 do
      if Root.Components[I] is TDataSet then
      begin
        DS := TDataSet(Root.Components[I]);
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
  finally
    Flds.Free;
  end;
end;

procedure TrhReportComponentEditor.Edit;
begin
  ExecuteVerb(0);
end;

function TrhReportComponentEditor.GetVerbCount: Integer;
begin
  Result := 2;
end;

function TrhReportComponentEditor.GetVerb(Index: Integer): string;
begin
  case Index of
    0: Result := 'Abrir &Designer...';
    1: Result := 'Pre&view do template';
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
          if TrhDesignerForm.Execute(TrhReport(Component), Data) then
            if Designer <> nil then
              Designer.Modified;
        finally
          Data.Free;
        end;
      end;
    1:
      TrhReport(Component).ShowPreview;
  end;
end;

end.
