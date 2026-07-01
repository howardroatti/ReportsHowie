{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Fonte de dados do designer: lista de datasets (por nome) e seus campos,
///   apenas como strings. E preenchida pelo component editor a partir dos
///   TDataSet do form/data module (no IDE) ou pela aplicacao (no designer
///   runtime da Fase 10). Nao referencia Data.DB nem DesignIntf — VCL puro.
/// </summary>
unit rh.Design.Data;

interface

uses
  System.Classes, System.Generics.Collections;

type
  TrhDesignData = class
  private
    FNames: TStringList;                 // nomes dos datasets
    FFields: TObjectList<TStringList>;   // campos por dataset (paralelo a FNames)
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddDataset(const AName: string; AFields: TStrings);
    function Count: Integer;
    function DatasetName(Index: Integer): string;
    function Fields(Index: Integer): TStringList;
    function IndexOf(const AName: string): Integer;
  end;

implementation

uses
  System.SysUtils;

constructor TrhDesignData.Create;
begin
  inherited Create;
  FNames := TStringList.Create;
  FFields := TObjectList<TStringList>.Create(True);
end;

destructor TrhDesignData.Destroy;
begin
  FFields.Free;
  FNames.Free;
  inherited Destroy;
end;

procedure TrhDesignData.AddDataset(const AName: string; AFields: TStrings);
var
  L: TStringList;
begin
  L := TStringList.Create;
  if AFields <> nil then
    L.Assign(AFields);
  FNames.Add(AName);
  FFields.Add(L);
end;

function TrhDesignData.Count: Integer;
begin
  Result := FNames.Count;
end;

function TrhDesignData.DatasetName(Index: Integer): string;
begin
  Result := FNames[Index];
end;

function TrhDesignData.Fields(Index: Integer): TStringList;
begin
  Result := FFields[Index];
end;

function TrhDesignData.IndexOf(const AName: string): Integer;
begin
  Result := FNames.IndexOf(AName);
end;

end.
