{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Pagina do relatorio: geometria do papel (em unidades de relatorio 0,1 mm),
///   orientacao, margens e a lista de bandas. Um relatorio simples costuma ter
///   uma unica pagina/template.
/// </summary>
unit rh.Page;

interface

uses
  System.Classes, System.JSON, System.Generics.Collections,
  rh.Types, rh.Model.Types, rh.Bands;

const
  // A4 em unidades de relatorio (0,1 mm)
  RH_A4_WIDTH  = 2100; // 210 mm
  RH_A4_HEIGHT = 2970; // 297 mm
  RH_DEFAULT_MARGIN = 100; // 10 mm

type
  TrhPage = class(TPersistent)
  private
    FName: string;
    FPaperWidth: TrhUnit;
    FPaperHeight: TrhUnit;
    FOrientation: TrhOrientation;
    FMarginLeft: TrhUnit;
    FMarginTop: TrhUnit;
    FMarginRight: TrhUnit;
    FMarginBottom: TrhUnit;
    FBands: TrhBandList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    procedure SaveToJSON(O: TJSONObject);
    procedure LoadFromJSON(O: TJSONObject);

    /// <summary>Largura util (papel menos margens L/R), respeitando a orientacao.</summary>
    function ContentWidth: TrhUnit;
    /// <summary>Altura util (papel menos margens T/B), respeitando a orientacao.</summary>
    function ContentHeight: TrhUnit;
    /// <summary>Largura efetiva do papel considerando a orientacao.</summary>
    function EffectiveWidth: TrhUnit;
    /// <summary>Altura efetiva do papel considerando a orientacao.</summary>
    function EffectiveHeight: TrhUnit;
  published
    property Name: string read FName write FName;
    property PaperWidth: TrhUnit read FPaperWidth write FPaperWidth default RH_A4_WIDTH;
    property PaperHeight: TrhUnit read FPaperHeight write FPaperHeight default RH_A4_HEIGHT;
    property Orientation: TrhOrientation read FOrientation write FOrientation default rhoPortrait;
    property MarginLeft: TrhUnit read FMarginLeft write FMarginLeft default RH_DEFAULT_MARGIN;
    property MarginTop: TrhUnit read FMarginTop write FMarginTop default RH_DEFAULT_MARGIN;
    property MarginRight: TrhUnit read FMarginRight write FMarginRight default RH_DEFAULT_MARGIN;
    property MarginBottom: TrhUnit read FMarginBottom write FMarginBottom default RH_DEFAULT_MARGIN;
    property Bands: TrhBandList read FBands;
  end;

  TrhPageList = class(TObjectList<TrhPage>)
  public
    constructor Create;
    function AddPage: TrhPage;
    procedure SaveToJSON(Arr: TJSONArray);
    procedure LoadFromJSON(Arr: TJSONArray);
  end;

implementation

uses
  rh.Serialization;

{ TrhPage }

constructor TrhPage.Create;
begin
  inherited Create;
  FBands := TrhBandList.Create;
  FPaperWidth := RH_A4_WIDTH;
  FPaperHeight := RH_A4_HEIGHT;
  FOrientation := rhoPortrait;
  FMarginLeft := RH_DEFAULT_MARGIN;
  FMarginTop := RH_DEFAULT_MARGIN;
  FMarginRight := RH_DEFAULT_MARGIN;
  FMarginBottom := RH_DEFAULT_MARGIN;
end;

destructor TrhPage.Destroy;
begin
  FBands.Free;
  inherited Destroy;
end;

procedure TrhPage.Assign(Source: TPersistent);
var
  Src: TrhPage;
  Band, Clone: TrhBand;
begin
  if Source is TrhPage then
  begin
    Src := TrhPage(Source);
    FName := Src.FName;
    FPaperWidth := Src.FPaperWidth;
    FPaperHeight := Src.FPaperHeight;
    FOrientation := Src.FOrientation;
    FMarginLeft := Src.FMarginLeft;
    FMarginTop := Src.FMarginTop;
    FMarginRight := Src.FMarginRight;
    FMarginBottom := Src.FMarginBottom;
    FBands.Clear;
    for Band in Src.FBands do
    begin
      Clone := TrhBand.Create;
      Clone.Assign(Band);
      FBands.Add(Clone);
    end;
  end
  else
    inherited Assign(Source);
end;

function TrhPage.EffectiveWidth: TrhUnit;
begin
  if FOrientation = rhoLandscape then
    Result := FPaperHeight
  else
    Result := FPaperWidth;
end;

function TrhPage.EffectiveHeight: TrhUnit;
begin
  if FOrientation = rhoLandscape then
    Result := FPaperWidth
  else
    Result := FPaperHeight;
end;

function TrhPage.ContentWidth: TrhUnit;
begin
  Result := EffectiveWidth - FMarginLeft - FMarginRight;
end;

function TrhPage.ContentHeight: TrhUnit;
begin
  Result := EffectiveHeight - FMarginTop - FMarginBottom;
end;

procedure TrhPage.SaveToJSON(O: TJSONObject);
var
  Arr: TJSONArray;
begin
  O.AddPair('name', FName);
  O.AddPair('paperWidth', TJSONNumber.Create(FPaperWidth));
  O.AddPair('paperHeight', TJSONNumber.Create(FPaperHeight));
  O.AddPair('orientation', OrientationToStr(FOrientation));
  O.AddPair('marginLeft', TJSONNumber.Create(FMarginLeft));
  O.AddPair('marginTop', TJSONNumber.Create(FMarginTop));
  O.AddPair('marginRight', TJSONNumber.Create(FMarginRight));
  O.AddPair('marginBottom', TJSONNumber.Create(FMarginBottom));
  Arr := TJSONArray.Create;
  FBands.SaveToJSON(Arr);
  O.AddPair('bands', Arr);
end;

procedure TrhPage.LoadFromJSON(O: TJSONObject);
begin
  if O = nil then Exit;
  FName := JGetStr(O, 'name', '');
  FPaperWidth := JGetInt(O, 'paperWidth', RH_A4_WIDTH);
  FPaperHeight := JGetInt(O, 'paperHeight', RH_A4_HEIGHT);
  FOrientation := StrToOrientation(JGetStr(O, 'orientation', 'portrait'));
  FMarginLeft := JGetInt(O, 'marginLeft', RH_DEFAULT_MARGIN);
  FMarginTop := JGetInt(O, 'marginTop', RH_DEFAULT_MARGIN);
  FMarginRight := JGetInt(O, 'marginRight', RH_DEFAULT_MARGIN);
  FMarginBottom := JGetInt(O, 'marginBottom', RH_DEFAULT_MARGIN);
  FBands.LoadFromJSON(JGetArr(O, 'bands'));
end;

{ TrhPageList }

constructor TrhPageList.Create;
begin
  inherited Create(True); // OwnsObjects
end;

function TrhPageList.AddPage: TrhPage;
begin
  Result := TrhPage.Create;
  Add(Result);
end;

procedure TrhPageList.SaveToJSON(Arr: TJSONArray);
var
  Page: TrhPage;
  JO: TJSONObject;
begin
  for Page in Self do
  begin
    JO := TJSONObject.Create;
    Page.SaveToJSON(JO);
    Arr.AddElement(JO);
  end;
end;

procedure TrhPageList.LoadFromJSON(Arr: TJSONArray);
var
  I: Integer;
  Page: TrhPage;
begin
  Clear;
  if Arr = nil then Exit;
  for I := 0 to Arr.Count - 1 do
    if Arr.Items[I] is TJSONObject then
    begin
      Page := TrhPage.Create;
      Page.LoadFromJSON(TJSONObject(Arr.Items[I]));
      Add(Page);
    end;
end;

end.
