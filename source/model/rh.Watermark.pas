{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Marca d'agua do relatorio: um texto (tipicamente diagonal e em tom claro,
///   ex.: "CONFIDENCIAL" / "RASCUNHO" / "COPIA") desenhado ao FUNDO de cada
///   pagina, atras do conteudo. E emitida pelo motor como um op de texto com
///   angulo de rotacao -> aparece em preview e em todos os exports.
///
///   O texto aceita ilhas [expr] (ex.: [DATE], [PAGE]) quando ha contexto.
///   Visible = False por padrao (relatorios existentes nao mudam).
/// </summary>
unit rh.Watermark;

interface

uses
  System.Classes, System.JSON, Vcl.Graphics;

type
  TrhWatermark = class(TPersistent)
  private
    FText: string;
    FFont: TFont;
    FAngle: Double;
    FVisible: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    procedure SaveToJSON(O: TJSONObject);
    procedure LoadFromJSON(O: TJSONObject);
  published
    property Text: string read FText write FText;
    property Font: TFont read FFont;
    /// <summary>Angulo em graus (positivo = anti-horario). 45 = diagonal classica.</summary>
    property Angle: Double read FAngle write FAngle;
    property Visible: Boolean read FVisible write FVisible default False;
  end;

implementation

uses
  rh.Serialization;

constructor TrhWatermark.Create;
begin
  inherited Create;
  FFont := TFont.Create;
  FFont.Name := 'Arial';
  FFont.Size := 72;
  FFont.Color := clSilver;   // cinza claro para nao cobrir o conteudo
  FFont.Style := [fsBold];
  FAngle := 45;
  FVisible := False;
end;

destructor TrhWatermark.Destroy;
begin
  FFont.Free;
  inherited Destroy;
end;

procedure TrhWatermark.Assign(Source: TPersistent);
var
  Src: TrhWatermark;
begin
  if Source is TrhWatermark then
  begin
    Src := TrhWatermark(Source);
    FText := Src.FText;
    FFont.Assign(Src.FFont);
    FAngle := Src.FAngle;
    FVisible := Src.FVisible;
  end
  else
    inherited Assign(Source);
end;

procedure TrhWatermark.SaveToJSON(O: TJSONObject);
var
  FontObj: TJSONObject;
begin
  O.AddPair('visible', TJSONBool.Create(FVisible));
  O.AddPair('text', FText);
  O.AddPair('angle', TJSONNumber.Create(FAngle));
  FontObj := TJSONObject.Create;
  FontToJSON(FFont, FontObj);
  O.AddPair('font', FontObj);
end;

procedure TrhWatermark.LoadFromJSON(O: TJSONObject);
begin
  if O = nil then Exit;
  FVisible := JGetBool(O, 'visible', False);
  FText := JGetStr(O, 'text', '');
  FAngle := JGetFloat(O, 'angle', 45);
  FontFromJSON(JGetObj(O, 'font'), FFont);
end;

end.
