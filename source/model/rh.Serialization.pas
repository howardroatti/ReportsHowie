{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Helpers de serializacao JSON de baixo nivel (leitura tolerante com
///   valores padrao) e conversores para TFont, TColor e TPicture (base64).
///   NAO depende das classes do modelo — quebra qualquer ciclo de units.
/// </summary>
unit rh.Serialization;

interface

uses
  System.JSON, Vcl.Graphics;

// --- leitura tolerante: retorna Default se a chave nao existir/tipo errado ---
function JGetStr(O: TJSONObject; const Name: string; const Default: string = ''): string;
function JGetInt(O: TJSONObject; const Name: string; Default: Integer = 0): Integer;
function JGetBool(O: TJSONObject; const Name: string; Default: Boolean = False): Boolean;
function JGetObj(O: TJSONObject; const Name: string): TJSONObject;   // nil se ausente
function JGetArr(O: TJSONObject; const Name: string): TJSONArray;    // nil se ausente

// --- TFont ---
procedure FontToJSON(Font: TFont; O: TJSONObject);
procedure FontFromJSON(O: TJSONObject; Font: TFont);

// --- TPicture <-> base64 (PNG/BMP conforme o grafico) ---
function PictureToBase64(Pic: TPicture): string;
procedure Base64ToPicture(const S: string; Pic: TPicture);

implementation

uses
  System.SysUtils, System.Classes, System.NetEncoding,
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg;

function JGetStr(O: TJSONObject; const Name, Default: string): string;
var
  V: TJSONValue;
begin
  if O = nil then Exit(Default);
  V := O.Values[Name];
  if V is TJSONString then
    Result := TJSONString(V).Value
  else if (V <> nil) and not (V is TJSONNull) then
    Result := V.Value
  else
    Result := Default;
end;

function JGetInt(O: TJSONObject; const Name: string; Default: Integer): Integer;
var
  V: TJSONValue;
begin
  if O = nil then Exit(Default);
  V := O.Values[Name];
  if V is TJSONNumber then
    Result := TJSONNumber(V).AsInt
  else
    Result := Default;
end;

function JGetBool(O: TJSONObject; const Name: string; Default: Boolean): Boolean;
var
  V: TJSONValue;
begin
  if O = nil then Exit(Default);
  V := O.Values[Name];
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean
  else
    Result := Default;
end;

function JGetObj(O: TJSONObject; const Name: string): TJSONObject;
var
  V: TJSONValue;
begin
  Result := nil;
  if O = nil then Exit;
  V := O.Values[Name];
  if V is TJSONObject then
    Result := TJSONObject(V);
end;

function JGetArr(O: TJSONObject; const Name: string): TJSONArray;
var
  V: TJSONValue;
begin
  Result := nil;
  if O = nil then Exit;
  V := O.Values[Name];
  if V is TJSONArray then
    Result := TJSONArray(V);
end;

procedure FontToJSON(Font: TFont; O: TJSONObject);
var
  StyleStr: string;
begin
  StyleStr := '';
  if fsBold in Font.Style then StyleStr := StyleStr + 'B';
  if fsItalic in Font.Style then StyleStr := StyleStr + 'I';
  if fsUnderline in Font.Style then StyleStr := StyleStr + 'U';
  if fsStrikeOut in Font.Style then StyleStr := StyleStr + 'S';
  O.AddPair('name', Font.Name);
  O.AddPair('size', TJSONNumber.Create(Font.Size));
  O.AddPair('color', TJSONNumber.Create(Integer(Font.Color)));
  O.AddPair('style', StyleStr);
end;

procedure FontFromJSON(O: TJSONObject; Font: TFont);
var
  StyleStr: string;
  St: TFontStyles;
begin
  if O = nil then Exit;
  Font.Name := JGetStr(O, 'name', Font.Name);
  Font.Size := JGetInt(O, 'size', Font.Size);
  Font.Color := TColor(JGetInt(O, 'color', Integer(Font.Color)));
  StyleStr := UpperCase(JGetStr(O, 'style', ''));
  St := [];
  if Pos('B', StyleStr) > 0 then Include(St, fsBold);
  if Pos('I', StyleStr) > 0 then Include(St, fsItalic);
  if Pos('U', StyleStr) > 0 then Include(St, fsUnderline);
  if Pos('S', StyleStr) > 0 then Include(St, fsStrikeOut);
  Font.Style := St;
end;

function PictureToBase64(Pic: TPicture): string;
var
  MS: TMemoryStream;
begin
  Result := '';
  if (Pic = nil) or (Pic.Graphic = nil) or Pic.Graphic.Empty then Exit;
  MS := TMemoryStream.Create;
  try
    Pic.Graphic.SaveToStream(MS);
    MS.Position := 0;
    Result := TNetEncoding.Base64.EncodeBytesToString(MS.Memory, Integer(MS.Size));
  finally
    MS.Free;
  end;
end;

procedure Base64ToPicture(const S: string; Pic: TPicture);
var
  Bytes: TBytes;
  MS: TMemoryStream;
begin
  if Trim(S) = '' then
  begin
    Pic.Graphic := nil;
    Exit;
  end;
  Bytes := TNetEncoding.Base64.DecodeStringToBytes(S);
  MS := TMemoryStream.Create;
  try
    if Length(Bytes) > 0 then
      MS.WriteBuffer(Bytes[0], Length(Bytes));
    MS.Position := 0;
    // LoadFromStream detecta o formato pelo cabecalho do grafico registrado
    Pic.LoadFromStream(MS);
  finally
    MS.Free;
  end;
end;

end.
