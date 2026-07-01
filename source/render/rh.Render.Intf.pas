{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Display list (documento renderizado) — o formato intermediario que o
///   motor de renderizacao produz e que TODAS as saidas (preview, PDF, HTML,
///   OOXML) consomem. Isso garante que a tela e os exports sejam identicos e
///   da paginacao/total-de-paginas de graca.
///
///   Coordenadas dos ops sao ABSOLUTAS na pagina, em unidades de relatorio
///   (0,1 mm). O renderizador de cada alvo faz a conversao final.
/// </summary>
unit rh.Render.Intf;

interface

uses
  System.Generics.Collections, System.UITypes, Vcl.Graphics,
  rh.Types, rh.Model.Types;

type
  TrhDrawKind = (rhdkText, rhdkLine, rhdkRect, rhdkEllipse, rhdkImage);

  /// <summary>Uma primitiva de desenho posicionada na pagina.</summary>
  TrhDrawOp = class
  public
    Kind: TrhDrawKind;
    Rect: TrhRectU;              // coords absolutas na pagina (0,1 mm)

    // --- texto ---
    Text: string;
    FontName: string;
    FontSize: Integer;           // pontos
    FontStyle: TFontStyles;
    FontColor: TColor;
    HAlign: TrhHAlign;
    VAlign: TrhVAlign;
    WordWrap: Boolean;
    BackColor: TColor;
    Transparent: Boolean;

    // --- moldura (texto) ---
    FrameSides: TrhFrameSides;
    FrameColor: TColor;
    FrameWidth: TrhUnit;

    // --- pen/brush (linha, rect, ellipse) ---
    PenColor: TColor;
    PenWidth: TrhUnit;
    BrushColor: TColor;
    BrushTransparent: Boolean;
    RoundRect: Boolean;

    // --- imagem (referencia nao-propria ao grafico do objeto) ---
    Graphic: TGraphic;
    Stretch: Boolean;
    KeepAspect: Boolean;
    Center: Boolean;

    constructor Create;
  end;

  /// <summary>Uma pagina fisica renderizada: tamanho + lista de primitivas.</summary>
  TrhRenderedPage = class
  private
    FOps: TObjectList<TrhDrawOp>;
    FWidth: TrhUnit;
    FHeight: TrhUnit;
  public
    constructor Create(AWidth, AHeight: TrhUnit);
    destructor Destroy; override;
    function AddOp(AKind: TrhDrawKind): TrhDrawOp;
    property Ops: TObjectList<TrhDrawOp> read FOps;
    property Width: TrhUnit read FWidth;
    property Height: TrhUnit read FHeight;
  end;

  /// <summary>Documento paginado pronto para exibir/exportar.</summary>
  TrhRenderedDocument = class
  private
    FPages: TObjectList<TrhRenderedPage>;
  public
    constructor Create;
    destructor Destroy; override;
    function AddPage(AWidth, AHeight: TrhUnit): TrhRenderedPage;
    function PageCount: Integer;
    property Pages: TObjectList<TrhRenderedPage> read FPages;
  end;

implementation

{ TrhDrawOp }

constructor TrhDrawOp.Create;
begin
  inherited Create;
  FontColor := clWindowText;
  BackColor := clWhite;
  Transparent := True;
  PenColor := clBlack;
  PenWidth := 2;
  BrushColor := clWhite;
  BrushTransparent := False;
  FrameColor := clBlack;
  FrameWidth := 2;
  Stretch := True;
  KeepAspect := True;
  Center := True;
end;

{ TrhRenderedPage }

constructor TrhRenderedPage.Create(AWidth, AHeight: TrhUnit);
begin
  inherited Create;
  FOps := TObjectList<TrhDrawOp>.Create(True);
  FWidth := AWidth;
  FHeight := AHeight;
end;

destructor TrhRenderedPage.Destroy;
begin
  FOps.Free;
  inherited Destroy;
end;

function TrhRenderedPage.AddOp(AKind: TrhDrawKind): TrhDrawOp;
begin
  Result := TrhDrawOp.Create;
  Result.Kind := AKind;
  FOps.Add(Result);
end;

{ TrhRenderedDocument }

constructor TrhRenderedDocument.Create;
begin
  inherited Create;
  FPages := TObjectList<TrhRenderedPage>.Create(True);
end;

destructor TrhRenderedDocument.Destroy;
begin
  FPages.Free;
  inherited Destroy;
end;

function TrhRenderedDocument.AddPage(AWidth, AHeight: TrhUnit): TrhRenderedPage;
begin
  Result := TrhRenderedPage.Create(AWidth, AHeight);
  FPages.Add(Result);
end;

function TrhRenderedDocument.PageCount: Integer;
begin
  Result := FPages.Count;
end;

end.
