{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   TrhReport: o componente que o usuario solta no form e raiz do modelo.
///   Dono das paginas/bandas/objetos e ponto de entrada da persistencia.
///
///   Persistencia (um serializador canonico, dois envelopes):
///     - Arquivo .rhr (runtime) via SaveToFile/LoadFromFile -> JSON.
///     - Streaming no DFM (design-time) via DefineProperties -> o MESMO JSON
///       gravado como blob binario ('ReportData'), fazendo o relatorio fazer
///       round-trip pelo .dfm do form.
/// </summary>
unit rh.Report;

interface

uses
  System.Classes, System.JSON, System.Generics.Collections,
  rh.Consts, rh.Page, rh.Watermark;

type
  TrhReport = class(TComponent)
  private
    FTitle: string;
    FAuthor: string;
    FFormatVersion: Integer;
    FPages: TrhPageList;
    FWatermark: TrhWatermark;
    FDataSets: TDictionary<string, TComponent>; // binding runtime (nao serializado)
    procedure ReadReportData(Stream: TStream);
    procedure WriteReportData(Stream: TStream);
  protected
    procedure DefineProperties(Filer: TFiler); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    /// <summary>Esvazia o relatorio (remove todas as paginas).</summary>
    procedure Clear;
    /// <summary>Garante ao menos uma pagina e a retorna.</summary>
    function EnsurePage: TrhPage;

    /// <summary>Liga (em runtime) um TDataSet a um nome usado por bandas de dados.</summary>
    procedure SetDataSet(const Name: string; DataSet: TComponent);
    /// <summary>Resolve o TDataSet ligado ao nome (nil se nao houver). Cast para TDataSet no uso.</summary>
    function FindDataSet(const Name: string): TComponent;

    // --- serializacao ---
    function ToJSONString(Pretty: Boolean = True): string;
    procedure LoadFromJSONString(const S: string);
    procedure SaveToStream(Stream: TStream);
    procedure LoadFromStream(Stream: TStream);
    procedure SaveToFile(const FileName: string);
    procedure LoadFromFile(const FileName: string);

    class function LibraryVersion: string;

    property Pages: TrhPageList read FPages;
    /// <summary>Marca d'agua opcional (texto diagonal ao fundo de cada pagina).</summary>
    property Watermark: TrhWatermark read FWatermark;
  published
    property Title: string read FTitle write FTitle;
    property Author: string read FAuthor write FAuthor;
    property FormatVersion: Integer read FFormatVersion write FFormatVersion default RH_FORMAT_VERSION;
  end;

implementation

uses
  System.SysUtils;

{ TrhReport }

constructor TrhReport.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFormatVersion := RH_FORMAT_VERSION;
  FPages := TrhPageList.Create;
  FPages.AddPage; // um relatorio novo ja nasce com uma pagina
  FWatermark := TrhWatermark.Create;
  FDataSets := TDictionary<string, TComponent>.Create;
end;

destructor TrhReport.Destroy;
begin
  FDataSets.Free;
  FWatermark.Free;
  FPages.Free;
  inherited Destroy;
end;

procedure TrhReport.SetDataSet(const Name: string; DataSet: TComponent);
begin
  FDataSets.AddOrSetValue(UpperCase(Name), DataSet);
end;

function TrhReport.FindDataSet(const Name: string): TComponent;
begin
  if not FDataSets.TryGetValue(UpperCase(Name), Result) then
    Result := nil;
end;

procedure TrhReport.Clear;
begin
  FPages.Clear;
end;

function TrhReport.EnsurePage: TrhPage;
begin
  if FPages.Count = 0 then
    FPages.AddPage;
  Result := FPages[0];
end;

class function TrhReport.LibraryVersion: string;
begin
  Result := RH_VERSION;
end;

function TrhReport.ToJSONString(Pretty: Boolean): string;
var
  Root: TJSONObject;
  Pages: TJSONArray;
  WmObj: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('formatVersion', TJSONNumber.Create(FFormatVersion));
    Root.AddPair('generator', 'ReportsHowie ' + RH_VERSION);
    Root.AddPair('title', FTitle);
    Root.AddPair('author', FAuthor);
    if FWatermark.Visible then
    begin
      WmObj := TJSONObject.Create;
      FWatermark.SaveToJSON(WmObj);
      Root.AddPair('watermark', WmObj);
    end;
    Pages := TJSONArray.Create;
    FPages.SaveToJSON(Pages);
    Root.AddPair('pages', Pages);
    if Pretty then
      Result := Root.Format(2)
    else
      Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure TrhReport.LoadFromJSONString(const S: string);
var
  Value: TJSONValue;
  Root: TJSONObject;
  PagesArr: TJSONArray;
begin
  if Trim(S) = '' then
  begin
    Clear;
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(S);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    raise Exception.Create('ReportsHowie: JSON de relatorio invalido.');
  end;
  Root := TJSONObject(Value);
  try
    if Root.Values['formatVersion'] is TJSONNumber then
      FFormatVersion := TJSONNumber(Root.Values['formatVersion']).AsInt;
    if Root.Values['title'] is TJSONString then
      FTitle := TJSONString(Root.Values['title']).Value;
    if Root.Values['author'] is TJSONString then
      FAuthor := TJSONString(Root.Values['author']).Value;
    if Root.Values['watermark'] is TJSONObject then
      FWatermark.LoadFromJSON(TJSONObject(Root.Values['watermark']))
    else
      FWatermark.Visible := False;
    if Root.Values['pages'] is TJSONArray then
      PagesArr := TJSONArray(Root.Values['pages'])
    else
      PagesArr := nil;
    FPages.LoadFromJSON(PagesArr);
  finally
    Root.Free;
  end;
end;

procedure TrhReport.SaveToStream(Stream: TStream);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(ToJSONString(True));
  if Length(Bytes) > 0 then
    Stream.WriteBuffer(Bytes[0], Length(Bytes));
end;

procedure TrhReport.LoadFromStream(Stream: TStream);
var
  Bytes: TBytes;
  Size: Int64;
begin
  Size := Stream.Size - Stream.Position;
  SetLength(Bytes, Size);
  if Length(Bytes) > 0 then
    Stream.ReadBuffer(Bytes[0], Length(Bytes));
  LoadFromJSONString(TEncoding.UTF8.GetString(Bytes));
end;

procedure TrhReport.SaveToFile(const FileName: string);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(FileName, fmCreate);
  try
    SaveToStream(FS);
  finally
    FS.Free;
  end;
end;

procedure TrhReport.LoadFromFile(const FileName: string);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    LoadFromStream(FS);
  finally
    FS.Free;
  end;
end;

// --- streaming DFM: grava/le o mesmo JSON como blob binario ---

procedure TrhReport.DefineProperties(Filer: TFiler);
begin
  inherited DefineProperties(Filer);
  Filer.DefineBinaryProperty('ReportData', ReadReportData, WriteReportData, True);
end;

procedure TrhReport.WriteReportData(Stream: TStream);
begin
  SaveToStream(Stream);
end;

procedure TrhReport.ReadReportData(Stream: TStream);
begin
  LoadFromStream(Stream);
end;

end.
