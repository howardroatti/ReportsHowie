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
  public
    procedure Edit; override;
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

implementation

uses
  rh.Report, rh.Design.Designer.Form, rh.Preview.Form;

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
begin
  if not (Component is TrhReport) then Exit;
  case Index of
    0:
      if TrhDesignerForm.Execute(TrhReport(Component)) then
        if Designer <> nil then
          Designer.Modified;
    1:
      TrhReport(Component).ShowPreview;
  end;
end;

end.
