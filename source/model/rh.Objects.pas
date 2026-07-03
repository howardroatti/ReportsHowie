{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Objetos de relatorio: dados puros (nao sao TControl). O designer e os
///   renderizadores os desenham. Todos descendem de TrhReportObject e sabem
///   se (de)serializar em JSON. A colecao TrhObjectList e polimorfica: usa a
///   fabrica CreateReportObject para instanciar a subclasse certa na carga.
/// </summary>
unit rh.Objects;

interface

uses
  System.Classes, System.Generics.Collections, System.JSON, Vcl.Graphics,
  rh.Types, rh.Model.Types;

type
  /// <summary>Moldura opcional ao redor de um objeto.</summary>
  TrhFrame = class(TPersistent)
  private
    FSides: TrhFrameSides;
    FColor: TColor;
    FWidth: TrhUnit;
  public
    constructor Create;
    procedure Assign(Source: TPersistent); override;
    procedure SaveToJSON(O: TJSONObject);
    procedure LoadFromJSON(O: TJSONObject);
  published
    property Sides: TrhFrameSides read FSides write FSides default [];
    property Color: TColor read FColor write FColor default clBlack;
    property Width: TrhUnit read FWidth write FWidth default 2; // 0,2 mm
  end;

  /// <summary>Base de todo objeto posicionavel do relatorio. Geometria em unidades de relatorio (0,1 mm).</summary>
  TrhReportObject = class(TPersistent)
  private
    FName: string;
    FLeft: TrhUnit;
    FTop: TrhUnit;
    FWidth: TrhUnit;
    FHeight: TrhUnit;
    FVisible: Boolean;
    FVisibleExpr: string;
    FFrame: TrhFrame;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;

    /// <summary>Discriminador estavel usado no JSON (ex.: 'text', 'image').</summary>
    class function ObjectType: string; virtual; abstract;

    procedure SaveToJSON(O: TJSONObject); virtual;
    procedure LoadFromJSON(O: TJSONObject); virtual;

    function BoundsRect: TrhRectU;
  published
    property Name: string read FName write FName;
    property Left: TrhUnit read FLeft write FLeft;
    property Top: TrhUnit read FTop write FTop;
    property Width: TrhUnit read FWidth write FWidth;
    property Height: TrhUnit read FHeight write FHeight;
    property Visible: Boolean read FVisible write FVisible default True;
    /// <summary>Visibilidade condicional por expressao (issue #24). Vazio =
    ///  comportamento estatico de Visible. Quando preenchida, e avaliada por
    ///  linha no motor de expressoes; se der falso, o objeto nao e emitido.
    ///  Ex.: "[exibe_valor]='S'". Resolve campos, params (SetParam) e pseudo-vars.</summary>
    property VisibleExpr: string read FVisibleExpr write FVisibleExpr;
    property Frame: TrhFrame read FFrame;
  end;

  TrhReportObjectClass = class of TrhReportObject;

  /// <summary>Objeto de texto com expressoes [ilha]. Base ou valor de campo.</summary>
  TrhTextObject = class(TrhReportObject)
  private
    FText: string;
    FDataField: string;
    FFont: TFont;
    FHAlign: TrhHAlign;
    FVAlign: TrhVAlign;
    FWordWrap: Boolean;
    FColor: TColor;         // fundo
    FTransparent: Boolean;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    class function ObjectType: string; override;
    procedure SaveToJSON(O: TJSONObject); override;
    procedure LoadFromJSON(O: TJSONObject); override;
    /// <summary>Expressao efetiva a avaliar: se DataField estiver preenchido,
    ///  vale '[DataField]' (bind simples estilo DB-aware); senao, usa Text (que
    ///  pode conter varias ilhas [expr]). Um unico motor para os dois modos.</summary>
    function DisplayExpression: string;
  published
    property Text: string read FText write FText;
    /// <summary>Bind direto a um campo do dataset da banda (modo simples). Quando
    ///  preenchido, tem precedencia sobre Text. Vazio = usa Text com [expr].</summary>
    property DataField: string read FDataField write FDataField;
    property Font: TFont read FFont;
    property HAlign: TrhHAlign read FHAlign write FHAlign default rhhaLeft;
    property VAlign: TrhVAlign read FVAlign write FVAlign default rhvaTop;
    property WordWrap: Boolean read FWordWrap write FWordWrap default True;
    property Color: TColor read FColor write FColor default clWhite;
    property Transparent: Boolean read FTransparent write FTransparent default True;
  end;

  /// <summary>Imagem estatica (Picture) ou vinda de um campo (DataField).</summary>
  TrhImageObject = class(TrhReportObject)
  private
    FPicture: TPicture;
    FDataField: string;
    FStretch: Boolean;
    FKeepAspect: Boolean;
    FCenter: Boolean;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    class function ObjectType: string; override;
    procedure SaveToJSON(O: TJSONObject); override;
    procedure LoadFromJSON(O: TJSONObject); override;
  published
    property Picture: TPicture read FPicture;
    property DataField: string read FDataField write FDataField;
    property Stretch: Boolean read FStretch write FStretch default True;
    property KeepAspect: Boolean read FKeepAspect write FKeepAspect default True;
    property Center: Boolean read FCenter write FCenter default True;
  end;

  /// <summary>Linha reta. Se Height = 0 e horizontal; se Width = 0 e vertical; senao diagonal do bounds.</summary>
  TrhLineObject = class(TrhReportObject)
  private
    FPenColor: TColor;
    FPenWidth: TrhUnit;
  public
    constructor Create; override;
    procedure Assign(Source: TPersistent); override;
    class function ObjectType: string; override;
    procedure SaveToJSON(O: TJSONObject); override;
    procedure LoadFromJSON(O: TJSONObject); override;
  published
    property PenColor: TColor read FPenColor write FPenColor default clBlack;
    property PenWidth: TrhUnit read FPenWidth write FPenWidth default 2;
  end;

  /// <summary>Forma geometrica (retangulo, retangulo arredondado ou elipse).</summary>
  TrhShapeObject = class(TrhReportObject)
  private
    FKind: TrhShapeKind;
    FPenColor: TColor;
    FPenWidth: TrhUnit;
    FBrushColor: TColor;
    FTransparent: Boolean;
  public
    constructor Create; override;
    procedure Assign(Source: TPersistent); override;
    class function ObjectType: string; override;
    procedure SaveToJSON(O: TJSONObject); override;
    procedure LoadFromJSON(O: TJSONObject); override;
  published
    property Kind: TrhShapeKind read FKind write FKind default rhskRectangle;
    property PenColor: TColor read FPenColor write FPenColor default clBlack;
    property PenWidth: TrhUnit read FPenWidth write FPenWidth default 2;
    property BrushColor: TColor read FBrushColor write FBrushColor default clWhite;
    property Transparent: Boolean read FTransparent write FTransparent default False;
  end;

  /// <summary>Codigo de barras 1D (Code128 / Code39). O texto pode conter ilhas
  ///  [expr] ou vir de DataField (igual ao TrhTextObject). O motor de render
  ///  expande as barras em retangulos, entao funciona em preview e em todos os
  ///  exports. ModuleWidth = 0 => a largura da barra estreita e auto-ajustada
  ///  para preencher Width; &gt; 0 fixa a largura do modulo (em 0,1 mm).</summary>
  TrhBarcodeObject = class(TrhReportObject)
  private
    FSymbology: TrhBarcodeSymbology;
    FText: string;
    FDataField: string;
    FBarColor: TColor;
    FShowText: Boolean;
    FModuleWidth: TrhUnit;
    FFont: TFont;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    class function ObjectType: string; override;
    procedure SaveToJSON(O: TJSONObject); override;
    procedure LoadFromJSON(O: TJSONObject); override;
    /// <summary>Valor a codificar: '[DataField]' se preenchido, senao Text.</summary>
    function DisplayExpression: string;
  published
    property Symbology: TrhBarcodeSymbology read FSymbology write FSymbology default rhbcCode128;
    property Text: string read FText write FText;
    property DataField: string read FDataField write FDataField;
    property BarColor: TColor read FBarColor write FBarColor default clBlack;
    property ShowText: Boolean read FShowText write FShowText default True;
    property ModuleWidth: TrhUnit read FModuleWidth write FModuleWidth default 0;
    property Font: TFont read FFont;
  end;

  /// <summary>Um ponto da serie do grafico (categoria + valor agregado).</summary>
  TrhChartPoint = record
    Category: string;
    Value: Double;
  end;

  /// <summary>Grafico (barras/linhas/pizza). A serie e AGREGADA do dataset da
  ///  banda pelo pipeline: agrupa por CategoryExpr e aplica Aggregate sobre
  ///  ValueExpr. O motor de render desenha via primitivas (rect/linha/poligono),
  ///  entao aparece em preview e em todos os exports. Coloque o grafico numa
  ///  banda emitida APOS os dados (Summary ou GroupFooter) para a serie estar
  ///  completa.</summary>
  TrhChartObject = class(TrhReportObject)
  private
    FChartType: TrhChartType;
    FAggregate: TrhChartAggregate;
    FDataSetName: string;
    FCategoryExpr: string;
    FValueExpr: string;
    FTitle: string;
    FShowValues: Boolean;
    FShowLegend: Boolean;
    FBarColor: TColor;
    FFont: TFont;
    FSeries: TArray<TrhChartPoint>;   // transiente: preenchido pelo pipeline
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    class function ObjectType: string; override;
    procedure SaveToJSON(O: TJSONObject); override;
    procedure LoadFromJSON(O: TJSONObject); override;
    /// <summary>Serie agregada (nao serializada). O pipeline escreve; o motor le.</summary>
    property Series: TArray<TrhChartPoint> read FSeries write FSeries;
  published
    property ChartType: TrhChartType read FChartType write FChartType default rhctBar;
    property Aggregate: TrhChartAggregate read FAggregate write FAggregate default rhcaSum;
    property DataSetName: string read FDataSetName write FDataSetName;
    property CategoryExpr: string read FCategoryExpr write FCategoryExpr;
    property ValueExpr: string read FValueExpr write FValueExpr;
    property Title: string read FTitle write FTitle;
    property ShowValues: Boolean read FShowValues write FShowValues default True;
    property ShowLegend: Boolean read FShowLegend write FShowLegend default False;
    property BarColor: TColor read FBarColor write FBarColor default clSkyBlue;
    property Font: TFont read FFont;
  end;

  /// <summary>Colecao polimorfica de objetos, dona dos itens.</summary>
  TrhObjectList = class(TObjectList<TrhReportObject>)
  public
    constructor Create;
    /// <summary>Cria, adiciona e retorna um objeto do tipo T (ex.: AddNew&lt;TrhTextObject&gt;).</summary>
    function AddNew<T: TrhReportObject, constructor>: T;
    procedure SaveToJSON(Arr: TJSONArray);
    procedure LoadFromJSON(Arr: TJSONArray);
  end;

/// <summary>Instancia a subclasse de TrhReportObject correspondente ao discriminador.</summary>
function CreateReportObject(const AType: string): TrhReportObject;

/// <summary>Registra uma classe de objeto na fabrica (permite extensoes de terceiros).</summary>
procedure RegisterReportObject(AClass: TrhReportObjectClass);

implementation

uses
  System.SysUtils, rh.Serialization;

var
  GObjectClasses: TList<TrhReportObjectClass>;

procedure RegisterReportObject(AClass: TrhReportObjectClass);
begin
  if GObjectClasses.IndexOf(AClass) < 0 then
    GObjectClasses.Add(AClass);
end;

function CreateReportObject(const AType: string): TrhReportObject;
var
  C: TrhReportObjectClass;
begin
  Result := nil;
  for C in GObjectClasses do
    if SameText(C.ObjectType, AType) then
      Exit(C.Create);
end;

{ TrhFrame }

constructor TrhFrame.Create;
begin
  inherited Create;
  FSides := [];
  FColor := clBlack;
  FWidth := 2;
end;

procedure TrhFrame.Assign(Source: TPersistent);
begin
  if Source is TrhFrame then
  begin
    FSides := TrhFrame(Source).FSides;
    FColor := TrhFrame(Source).FColor;
    FWidth := TrhFrame(Source).FWidth;
  end
  else
    inherited Assign(Source);
end;

procedure TrhFrame.SaveToJSON(O: TJSONObject);
begin
  O.AddPair('sides', FrameSidesToStr(FSides));
  O.AddPair('color', TJSONNumber.Create(Integer(FColor)));
  O.AddPair('width', TJSONNumber.Create(FWidth));
end;

procedure TrhFrame.LoadFromJSON(O: TJSONObject);
begin
  if O = nil then Exit;
  FSides := StrToFrameSides(JGetStr(O, 'sides', ''));
  FColor := TColor(JGetInt(O, 'color', Integer(clBlack)));
  FWidth := JGetInt(O, 'width', 2);
end;

{ TrhReportObject }

constructor TrhReportObject.Create;
begin
  inherited Create;
  FFrame := TrhFrame.Create;
  FVisible := True;
end;

destructor TrhReportObject.Destroy;
begin
  FFrame.Free;
  inherited Destroy;
end;

procedure TrhReportObject.Assign(Source: TPersistent);
var
  Src: TrhReportObject;
begin
  if Source is TrhReportObject then
  begin
    Src := TrhReportObject(Source);
    FName := Src.FName;
    FLeft := Src.FLeft;
    FTop := Src.FTop;
    FWidth := Src.FWidth;
    FHeight := Src.FHeight;
    FVisible := Src.FVisible;
    FVisibleExpr := Src.FVisibleExpr;
    FFrame.Assign(Src.FFrame);
  end
  else
    inherited Assign(Source);
end;

function TrhReportObject.BoundsRect: TrhRectU;
begin
  Result := TrhRectU.Create(FLeft, FTop, FWidth, FHeight);
end;

procedure TrhReportObject.SaveToJSON(O: TJSONObject);
var
  FrameObj: TJSONObject;
begin
  O.AddPair('type', ObjectType);
  O.AddPair('name', FName);
  O.AddPair('left', TJSONNumber.Create(FLeft));
  O.AddPair('top', TJSONNumber.Create(FTop));
  O.AddPair('width', TJSONNumber.Create(FWidth));
  O.AddPair('height', TJSONNumber.Create(FHeight));
  O.AddPair('visible', TJSONBool.Create(FVisible));
  if FVisibleExpr <> '' then
    O.AddPair('visibleExpr', FVisibleExpr);
  FrameObj := TJSONObject.Create;
  FFrame.SaveToJSON(FrameObj);
  O.AddPair('frame', FrameObj);
end;

procedure TrhReportObject.LoadFromJSON(O: TJSONObject);
begin
  if O = nil then Exit;
  FName := JGetStr(O, 'name', FName);
  FLeft := JGetInt(O, 'left', FLeft);
  FTop := JGetInt(O, 'top', FTop);
  FWidth := JGetInt(O, 'width', FWidth);
  FHeight := JGetInt(O, 'height', FHeight);
  FVisible := JGetBool(O, 'visible', True);
  FVisibleExpr := JGetStr(O, 'visibleExpr', '');
  FFrame.LoadFromJSON(JGetObj(O, 'frame'));
end;

{ TrhTextObject }

constructor TrhTextObject.Create;
begin
  inherited Create;
  FFont := TFont.Create;
  FFont.Name := 'Segoe UI';
  FFont.Size := 10;
  FHAlign := rhhaLeft;
  FVAlign := rhvaTop;
  FWordWrap := True;
  FColor := clWhite;
  FTransparent := True;
end;

destructor TrhTextObject.Destroy;
begin
  FFont.Free;
  inherited Destroy;
end;

procedure TrhTextObject.Assign(Source: TPersistent);
var
  Src: TrhTextObject;
begin
  inherited Assign(Source);
  if Source is TrhTextObject then
  begin
    Src := TrhTextObject(Source);
    FText := Src.FText;
    FDataField := Src.FDataField;
    FFont.Assign(Src.FFont);
    FHAlign := Src.FHAlign;
    FVAlign := Src.FVAlign;
    FWordWrap := Src.FWordWrap;
    FColor := Src.FColor;
    FTransparent := Src.FTransparent;
  end;
end;

class function TrhTextObject.ObjectType: string;
begin
  Result := 'text';
end;

function TrhTextObject.DisplayExpression: string;
begin
  if FDataField <> '' then
    Result := '[' + FDataField + ']'
  else
    Result := FText;
end;

procedure TrhTextObject.SaveToJSON(O: TJSONObject);
var
  FontObj: TJSONObject;
begin
  inherited SaveToJSON(O);
  O.AddPair('text', FText);
  O.AddPair('dataField', FDataField);
  FontObj := TJSONObject.Create;
  FontToJSON(FFont, FontObj);
  O.AddPair('font', FontObj);
  O.AddPair('hAlign', HAlignToStr(FHAlign));
  O.AddPair('vAlign', VAlignToStr(FVAlign));
  O.AddPair('wordWrap', TJSONBool.Create(FWordWrap));
  O.AddPair('color', TJSONNumber.Create(Integer(FColor)));
  O.AddPair('transparent', TJSONBool.Create(FTransparent));
end;

procedure TrhTextObject.LoadFromJSON(O: TJSONObject);
begin
  inherited LoadFromJSON(O);
  FText := JGetStr(O, 'text', '');
  FDataField := JGetStr(O, 'dataField', '');
  FontFromJSON(JGetObj(O, 'font'), FFont);
  FHAlign := StrToHAlign(JGetStr(O, 'hAlign', 'left'));
  FVAlign := StrToVAlign(JGetStr(O, 'vAlign', 'top'));
  FWordWrap := JGetBool(O, 'wordWrap', True);
  FColor := TColor(JGetInt(O, 'color', Integer(clWhite)));
  FTransparent := JGetBool(O, 'transparent', True);
end;

{ TrhImageObject }

constructor TrhImageObject.Create;
begin
  inherited Create;
  FPicture := TPicture.Create;
  FStretch := True;
  FKeepAspect := True;
  FCenter := True;
end;

destructor TrhImageObject.Destroy;
begin
  FPicture.Free;
  inherited Destroy;
end;

procedure TrhImageObject.Assign(Source: TPersistent);
var
  Src: TrhImageObject;
begin
  inherited Assign(Source);
  if Source is TrhImageObject then
  begin
    Src := TrhImageObject(Source);
    FPicture.Assign(Src.FPicture);
    FDataField := Src.FDataField;
    FStretch := Src.FStretch;
    FKeepAspect := Src.FKeepAspect;
    FCenter := Src.FCenter;
  end;
end;

class function TrhImageObject.ObjectType: string;
begin
  Result := 'image';
end;

procedure TrhImageObject.SaveToJSON(O: TJSONObject);
begin
  inherited SaveToJSON(O);
  O.AddPair('dataField', FDataField);
  O.AddPair('stretch', TJSONBool.Create(FStretch));
  O.AddPair('keepAspect', TJSONBool.Create(FKeepAspect));
  O.AddPair('center', TJSONBool.Create(FCenter));
  O.AddPair('picture', PictureToBase64(FPicture));
end;

procedure TrhImageObject.LoadFromJSON(O: TJSONObject);
begin
  inherited LoadFromJSON(O);
  FDataField := JGetStr(O, 'dataField', '');
  FStretch := JGetBool(O, 'stretch', True);
  FKeepAspect := JGetBool(O, 'keepAspect', True);
  FCenter := JGetBool(O, 'center', True);
  Base64ToPicture(JGetStr(O, 'picture', ''), FPicture);
end;

{ TrhLineObject }

constructor TrhLineObject.Create;
begin
  inherited Create;
  FPenColor := clBlack;
  FPenWidth := 2;
end;

procedure TrhLineObject.Assign(Source: TPersistent);
var
  Src: TrhLineObject;
begin
  inherited Assign(Source);
  if Source is TrhLineObject then
  begin
    Src := TrhLineObject(Source);
    FPenColor := Src.FPenColor;
    FPenWidth := Src.FPenWidth;
  end;
end;

class function TrhLineObject.ObjectType: string;
begin
  Result := 'line';
end;

procedure TrhLineObject.SaveToJSON(O: TJSONObject);
begin
  inherited SaveToJSON(O);
  O.AddPair('penColor', TJSONNumber.Create(Integer(FPenColor)));
  O.AddPair('penWidth', TJSONNumber.Create(FPenWidth));
end;

procedure TrhLineObject.LoadFromJSON(O: TJSONObject);
begin
  inherited LoadFromJSON(O);
  FPenColor := TColor(JGetInt(O, 'penColor', Integer(clBlack)));
  FPenWidth := JGetInt(O, 'penWidth', 2);
end;

{ TrhShapeObject }

constructor TrhShapeObject.Create;
begin
  inherited Create;
  FKind := rhskRectangle;
  FPenColor := clBlack;
  FPenWidth := 2;
  FBrushColor := clWhite;
  FTransparent := False;
end;

procedure TrhShapeObject.Assign(Source: TPersistent);
var
  Src: TrhShapeObject;
begin
  inherited Assign(Source);
  if Source is TrhShapeObject then
  begin
    Src := TrhShapeObject(Source);
    FKind := Src.FKind;
    FPenColor := Src.FPenColor;
    FPenWidth := Src.FPenWidth;
    FBrushColor := Src.FBrushColor;
    FTransparent := Src.FTransparent;
  end;
end;

class function TrhShapeObject.ObjectType: string;
begin
  Result := 'shape';
end;

procedure TrhShapeObject.SaveToJSON(O: TJSONObject);
begin
  inherited SaveToJSON(O);
  O.AddPair('kind', ShapeKindToStr(FKind));
  O.AddPair('penColor', TJSONNumber.Create(Integer(FPenColor)));
  O.AddPair('penWidth', TJSONNumber.Create(FPenWidth));
  O.AddPair('brushColor', TJSONNumber.Create(Integer(FBrushColor)));
  O.AddPair('transparent', TJSONBool.Create(FTransparent));
end;

procedure TrhShapeObject.LoadFromJSON(O: TJSONObject);
begin
  inherited LoadFromJSON(O);
  FKind := StrToShapeKind(JGetStr(O, 'kind', 'rectangle'));
  FPenColor := TColor(JGetInt(O, 'penColor', Integer(clBlack)));
  FPenWidth := JGetInt(O, 'penWidth', 2);
  FBrushColor := TColor(JGetInt(O, 'brushColor', Integer(clWhite)));
  FTransparent := JGetBool(O, 'transparent', False);
end;

{ TrhBarcodeObject }

constructor TrhBarcodeObject.Create;
begin
  inherited Create;
  FSymbology := rhbcCode128;
  FBarColor := clBlack;
  FShowText := True;
  FModuleWidth := 0; // auto-ajusta a largura
  FFont := TFont.Create;
  FFont.Name := 'Segoe UI';
  FFont.Size := 8;
end;

destructor TrhBarcodeObject.Destroy;
begin
  FFont.Free;
  inherited Destroy;
end;

procedure TrhBarcodeObject.Assign(Source: TPersistent);
var
  Src: TrhBarcodeObject;
begin
  inherited Assign(Source);
  if Source is TrhBarcodeObject then
  begin
    Src := TrhBarcodeObject(Source);
    FSymbology := Src.FSymbology;
    FText := Src.FText;
    FDataField := Src.FDataField;
    FBarColor := Src.FBarColor;
    FShowText := Src.FShowText;
    FModuleWidth := Src.FModuleWidth;
    FFont.Assign(Src.FFont);
  end;
end;

class function TrhBarcodeObject.ObjectType: string;
begin
  Result := 'barcode';
end;

function TrhBarcodeObject.DisplayExpression: string;
begin
  if FDataField <> '' then
    Result := '[' + FDataField + ']'
  else
    Result := FText;
end;

procedure TrhBarcodeObject.SaveToJSON(O: TJSONObject);
var
  FontObj: TJSONObject;
begin
  inherited SaveToJSON(O);
  O.AddPair('symbology', BarcodeSymbologyToStr(FSymbology));
  O.AddPair('text', FText);
  O.AddPair('dataField', FDataField);
  O.AddPair('barColor', TJSONNumber.Create(Integer(FBarColor)));
  O.AddPair('showText', TJSONBool.Create(FShowText));
  O.AddPair('moduleWidth', TJSONNumber.Create(FModuleWidth));
  FontObj := TJSONObject.Create;
  FontToJSON(FFont, FontObj);
  O.AddPair('font', FontObj);
end;

procedure TrhBarcodeObject.LoadFromJSON(O: TJSONObject);
begin
  inherited LoadFromJSON(O);
  FSymbology := StrToBarcodeSymbology(JGetStr(O, 'symbology', 'code128'));
  FText := JGetStr(O, 'text', '');
  FDataField := JGetStr(O, 'dataField', '');
  FBarColor := TColor(JGetInt(O, 'barColor', Integer(clBlack)));
  FShowText := JGetBool(O, 'showText', True);
  FModuleWidth := JGetInt(O, 'moduleWidth', 0);
  FontFromJSON(JGetObj(O, 'font'), FFont);
end;

{ TrhChartObject }

constructor TrhChartObject.Create;
begin
  inherited Create;
  FChartType := rhctBar;
  FAggregate := rhcaSum;
  FShowValues := True;
  FShowLegend := False;
  FBarColor := clSkyBlue;
  FFont := TFont.Create;
  FFont.Name := 'Segoe UI';
  FFont.Size := 8;
end;

destructor TrhChartObject.Destroy;
begin
  FFont.Free;
  inherited Destroy;
end;

procedure TrhChartObject.Assign(Source: TPersistent);
var
  Src: TrhChartObject;
begin
  inherited Assign(Source);
  if Source is TrhChartObject then
  begin
    Src := TrhChartObject(Source);
    FChartType := Src.FChartType;
    FAggregate := Src.FAggregate;
    FDataSetName := Src.FDataSetName;
    FCategoryExpr := Src.FCategoryExpr;
    FValueExpr := Src.FValueExpr;
    FTitle := Src.FTitle;
    FShowValues := Src.FShowValues;
    FShowLegend := Src.FShowLegend;
    FBarColor := Src.FBarColor;
    FFont.Assign(Src.FFont);
  end;
end;

class function TrhChartObject.ObjectType: string;
begin
  Result := 'chart';
end;

procedure TrhChartObject.SaveToJSON(O: TJSONObject);
var
  FontObj: TJSONObject;
begin
  inherited SaveToJSON(O);
  O.AddPair('chartType', ChartTypeToStr(FChartType));
  O.AddPair('aggregate', ChartAggregateToStr(FAggregate));
  O.AddPair('dataSetName', FDataSetName);
  O.AddPair('categoryExpr', FCategoryExpr);
  O.AddPair('valueExpr', FValueExpr);
  O.AddPair('title', FTitle);
  O.AddPair('showValues', TJSONBool.Create(FShowValues));
  O.AddPair('showLegend', TJSONBool.Create(FShowLegend));
  O.AddPair('barColor', TJSONNumber.Create(Integer(FBarColor)));
  FontObj := TJSONObject.Create;
  FontToJSON(FFont, FontObj);
  O.AddPair('font', FontObj);
end;

procedure TrhChartObject.LoadFromJSON(O: TJSONObject);
begin
  inherited LoadFromJSON(O);
  FChartType := StrToChartType(JGetStr(O, 'chartType', 'bar'));
  FAggregate := StrToChartAggregate(JGetStr(O, 'aggregate', 'sum'));
  FDataSetName := JGetStr(O, 'dataSetName', '');
  FCategoryExpr := JGetStr(O, 'categoryExpr', '');
  FValueExpr := JGetStr(O, 'valueExpr', '');
  FTitle := JGetStr(O, 'title', '');
  FShowValues := JGetBool(O, 'showValues', True);
  FShowLegend := JGetBool(O, 'showLegend', False);
  FBarColor := TColor(JGetInt(O, 'barColor', Integer(clSkyBlue)));
  FontFromJSON(JGetObj(O, 'font'), FFont);
end;

{ TrhObjectList }

constructor TrhObjectList.Create;
begin
  inherited Create(True); // OwnsObjects
end;

function TrhObjectList.AddNew<T>: T;
begin
  Result := T.Create;
  inherited Add(Result);
end;

procedure TrhObjectList.SaveToJSON(Arr: TJSONArray);
var
  Obj: TrhReportObject;
  JO: TJSONObject;
begin
  for Obj in Self do
  begin
    JO := TJSONObject.Create;
    Obj.SaveToJSON(JO);
    Arr.AddElement(JO);
  end;
end;

procedure TrhObjectList.LoadFromJSON(Arr: TJSONArray);
var
  I: Integer;
  JO: TJSONObject;
  Obj: TrhReportObject;
begin
  Clear;
  if Arr = nil then Exit;
  for I := 0 to Arr.Count - 1 do
    if Arr.Items[I] is TJSONObject then
    begin
      JO := TJSONObject(Arr.Items[I]);
      Obj := CreateReportObject(JGetStr(JO, 'type', ''));
      if Obj <> nil then
      begin
        Obj.LoadFromJSON(JO);
        inherited Add(Obj);
      end;
    end;
end;

initialization
  GObjectClasses := TList<TrhReportObjectClass>.Create;
  RegisterReportObject(TrhTextObject);
  RegisterReportObject(TrhImageObject);
  RegisterReportObject(TrhLineObject);
  RegisterReportObject(TrhShapeObject);
  RegisterReportObject(TrhBarcodeObject);
  RegisterReportObject(TrhChartObject);

finalization
  GObjectClasses.Free;

end.
