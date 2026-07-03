{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Bandas do relatorio. Uma banda e uma faixa horizontal com altura propria
///   que hospeda objetos. O tipo (TrhBandType) define quando/como o pipeline a
///   emite. Na Fase 1 as bandas sao dados + persistencia; o pipeline entra na
///   Fase 4.
/// </summary>
unit rh.Bands;

interface

uses
  System.Classes, System.Generics.Collections, System.JSON,
  rh.Types, rh.Model.Types, rh.Objects;

type
  TrhBand = class(TPersistent)
  private
    FBandType: TrhBandType;
    FName: string;
    FHeight: TrhUnit;
    FVisible: Boolean;
    FCanGrow: Boolean;
    FCanShrink: Boolean;
    FPrintIfEmpty: Boolean;
    FDataSetName: string;
    FGroupExpression: string;
    FMasterKeyExpr: string;
    FDetailKeyField: string;
    FObjects: TrhObjectList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    procedure SaveToJSON(O: TJSONObject);
    procedure LoadFromJSON(O: TJSONObject);
  published
    property BandType: TrhBandType read FBandType write FBandType default rhbtMasterData;
    property Name: string read FName write FName;
    property Height: TrhUnit read FHeight write FHeight;
    property Visible: Boolean read FVisible write FVisible default True;
    property CanGrow: Boolean read FCanGrow write FCanGrow default False;
    property CanShrink: Boolean read FCanShrink write FCanShrink default False;
    property PrintIfEmpty: Boolean read FPrintIfEmpty write FPrintIfEmpty default False;
    /// <summary>Nome do TrhDataLink que alimenta bandas de dados (master/detail).</summary>
    property DataSetName: string read FDataSetName write FDataSetName;
    /// <summary>Expressao de grupo (para bandas de grupo).</summary>
    property GroupExpression: string read FGroupExpression write FGroupExpression;
    /// <summary>Subrelatorio (banda de detalhe): expressao-chave avaliada no
    ///  contexto do MASTER (ex.: [id]). Junto com DetailKeyField, filtra o
    ///  dataset de detalhe para so as linhas da linha-master corrente.</summary>
    property MasterKeyExpr: string read FMasterKeyExpr write FMasterKeyExpr;
    /// <summary>Subrelatorio: campo do dataset de DETALHE comparado a
    ///  MasterKeyExpr. Vazio = sem filtro (itera todo o detalhe por linha-master).</summary>
    property DetailKeyField: string read FDetailKeyField write FDetailKeyField;
    property Objects: TrhObjectList read FObjects;
  end;

  TrhBandList = class(TObjectList<TrhBand>)
  public
    constructor Create;
    function AddBand(ABandType: TrhBandType): TrhBand;
    procedure SaveToJSON(Arr: TJSONArray);
    procedure LoadFromJSON(Arr: TJSONArray);
  end;

implementation

uses
  rh.Serialization;

{ TrhBand }

constructor TrhBand.Create;
begin
  inherited Create;
  FObjects := TrhObjectList.Create;
  FBandType := rhbtMasterData;
  FVisible := True;
  FHeight := 100; // 10 mm
end;

destructor TrhBand.Destroy;
begin
  FObjects.Free;
  inherited Destroy;
end;

procedure TrhBand.Assign(Source: TPersistent);
var
  Src: TrhBand;
  Obj: TrhReportObject;
  Clone: TrhReportObject;
begin
  if Source is TrhBand then
  begin
    Src := TrhBand(Source);
    FBandType := Src.FBandType;
    FName := Src.FName;
    FHeight := Src.FHeight;
    FVisible := Src.FVisible;
    FCanGrow := Src.FCanGrow;
    FCanShrink := Src.FCanShrink;
    FPrintIfEmpty := Src.FPrintIfEmpty;
    FDataSetName := Src.FDataSetName;
    FGroupExpression := Src.FGroupExpression;
    FMasterKeyExpr := Src.FMasterKeyExpr;
    FDetailKeyField := Src.FDetailKeyField;
    FObjects.Clear;
    for Obj in Src.FObjects do
    begin
      Clone := CreateReportObject(Obj.ObjectType);
      if Clone <> nil then
      begin
        Clone.Assign(Obj);
        FObjects.Add(Clone);
      end;
    end;
  end
  else
    inherited Assign(Source);
end;

procedure TrhBand.SaveToJSON(O: TJSONObject);
var
  Arr: TJSONArray;
begin
  O.AddPair('bandType', BandTypeToStr(FBandType));
  O.AddPair('name', FName);
  O.AddPair('height', TJSONNumber.Create(FHeight));
  O.AddPair('visible', TJSONBool.Create(FVisible));
  O.AddPair('canGrow', TJSONBool.Create(FCanGrow));
  O.AddPair('canShrink', TJSONBool.Create(FCanShrink));
  O.AddPair('printIfEmpty', TJSONBool.Create(FPrintIfEmpty));
  O.AddPair('dataSetName', FDataSetName);
  O.AddPair('groupExpression', FGroupExpression);
  O.AddPair('masterKeyExpr', FMasterKeyExpr);
  O.AddPair('detailKeyField', FDetailKeyField);
  Arr := TJSONArray.Create;
  FObjects.SaveToJSON(Arr);
  O.AddPair('objects', Arr);
end;

procedure TrhBand.LoadFromJSON(O: TJSONObject);
begin
  if O = nil then Exit;
  FBandType := StrToBandType(JGetStr(O, 'bandType', 'masterData'));
  FName := JGetStr(O, 'name', '');
  FHeight := JGetInt(O, 'height', 100);
  FVisible := JGetBool(O, 'visible', True);
  FCanGrow := JGetBool(O, 'canGrow', False);
  FCanShrink := JGetBool(O, 'canShrink', False);
  FPrintIfEmpty := JGetBool(O, 'printIfEmpty', False);
  FDataSetName := JGetStr(O, 'dataSetName', '');
  FGroupExpression := JGetStr(O, 'groupExpression', '');
  FMasterKeyExpr := JGetStr(O, 'masterKeyExpr', '');
  FDetailKeyField := JGetStr(O, 'detailKeyField', '');
  FObjects.LoadFromJSON(JGetArr(O, 'objects'));
end;

{ TrhBandList }

constructor TrhBandList.Create;
begin
  inherited Create(True); // OwnsObjects
end;

function TrhBandList.AddBand(ABandType: TrhBandType): TrhBand;
begin
  Result := TrhBand.Create;
  Result.BandType := ABandType;
  Add(Result);
end;

procedure TrhBandList.SaveToJSON(Arr: TJSONArray);
var
  Band: TrhBand;
  JO: TJSONObject;
begin
  for Band in Self do
  begin
    JO := TJSONObject.Create;
    Band.SaveToJSON(JO);
    Arr.AddElement(JO);
  end;
end;

procedure TrhBandList.LoadFromJSON(Arr: TJSONArray);
var
  I: Integer;
  Band: TrhBand;
begin
  Clear;
  if Arr = nil then Exit;
  for I := 0 to Arr.Count - 1 do
    if Arr.Items[I] is TJSONObject then
    begin
      Band := TrhBand.Create;
      Band.LoadFromJSON(TJSONObject(Arr.Items[I]));
      Add(Band);
    end;
end;

end.
