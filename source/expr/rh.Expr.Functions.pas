{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Registro de funcoes do motor de expressoes. Recebe argumentos ja
///   avaliados (TArray&lt;Variant&gt;) e retorna Variant. Extensivel via
///   rhExprRegisterFunction (permite funcoes de usuario).
/// </summary>
unit rh.Expr.Functions;

interface

type
  TrhFunctionProc = reference to function(const Args: TArray<Variant>): Variant;

/// <summary>Registra/substitui uma funcao (nome case-insensitive).</summary>
procedure rhExprRegisterFunction(const Name: string; const Proc: TrhFunctionProc);

/// <summary>Chama a funcao pelo nome. False se nao existir.</summary>
function rhExprCallFunction(const Name: string; const Args: TArray<Variant>;
  out Res: Variant): Boolean;

/// <summary>Nomes das funcoes registradas (maiusculas), em ordem alfabetica.
///  Util para UIs (editor de expressao) e para o list_functions do MCP.</summary>
function rhExprFunctionNames: TArray<string>;

implementation

uses
  System.SysUtils, System.Variants, System.Math, System.StrUtils,
  System.Generics.Collections, System.Classes;

var
  GFunctions: TDictionary<string, TrhFunctionProc>;

procedure rhExprRegisterFunction(const Name: string; const Proc: TrhFunctionProc);
begin
  GFunctions.AddOrSetValue(UpperCase(Name), Proc);
end;

function rhExprCallFunction(const Name: string; const Args: TArray<Variant>;
  out Res: Variant): Boolean;
var
  Proc: TrhFunctionProc;
begin
  Result := GFunctions.TryGetValue(UpperCase(Name), Proc);
  if Result then
    Res := Proc(Args);
end;

function rhExprFunctionNames: TArray<string>;
var
  Names: TStringList;
  Key: string;
begin
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    Names.Duplicates := dupIgnore;
    for Key in GFunctions.Keys do
      Names.Add(Key);
    Result := Names.ToStringArray;
  finally
    Names.Free;
  end;
end;

procedure NeedArgs(const FuncName: string; const Args: TArray<Variant>; MinN, MaxN: Integer);
begin
  if (Length(Args) < MinN) or ((MaxN >= 0) and (Length(Args) > MaxN)) then
    raise Exception.CreateFmt('ReportsHowie: numero de argumentos invalido para %s.', [FuncName]);
end;

function ArgBool(const V: Variant): Boolean;
begin
  if VarIsNull(V) or VarIsEmpty(V) then Result := False else Result := V;
end;

// mantem so os digitos (util para CNPJ/CPF/chave de acesso antes de mascarar)
function StrOnlyDigits(const S: string): string;
var
  C: Char;
begin
  Result := '';
  for C in S do
    if CharInSet(C, ['0'..'9']) then
      Result := Result + C;
end;

// aplica uma mascara onde cada '#' consome um caractere de Value; o resto e
// literal. Ex.: MASK('12345678000199','##.###.###/####-##') -> CNPJ formatado.
function StrApplyMask(const Value, MaskStr: string): string;
var
  I, Vi: Integer;
begin
  Result := '';
  Vi := 1;
  for I := 1 to Length(MaskStr) do
    if MaskStr[I] = '#' then
    begin
      if Vi <= Length(Value) then
      begin
        Result := Result + Value[Vi];
        Inc(Vi);
      end;
    end
    else
      Result := Result + MaskStr[I];
end;

// Title Case: primeira letra de cada palavra (delimitada por espaco) em maiuscula
function StrProper(const S: string): string;
var
  I: Integer;
  AtStart: Boolean;
begin
  Result := LowerCase(S);
  AtStart := True;
  for I := 1 to Length(Result) do
    if Result[I] = ' ' then
      AtStart := True
    else
    begin
      if AtStart then
        Result[I] := UpperCase(Result[I])[1]; // Unicode-aware (acentos)
      AtStart := False;
    end;
end;

function StrPadLeft(const S: string; N: Integer; Ch: Char): string;
begin
  Result := S;
  while Length(Result) < N do
    Result := Ch + Result;
end;

function StrPadRight(const S: string; N: Integer; Ch: Char): string;
begin
  Result := S;
  while Length(Result) < N do
    Result := Result + Ch;
end;

function ArgChar(const V: Variant; Default: Char): Char;
var
  S: string;
begin
  S := VarToStr(V);
  if S = '' then Result := Default else Result := S[1];
end;

procedure RegisterBuiltins;
begin
  rhExprRegisterFunction('UPPER',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('UPPER', A, 1, 1); Result := UpperCase(VarToStr(A[0])); end);

  rhExprRegisterFunction('LOWER',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('LOWER', A, 1, 1); Result := LowerCase(VarToStr(A[0])); end);

  rhExprRegisterFunction('TRIM',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('TRIM', A, 1, 1); Result := Trim(VarToStr(A[0])); end);

  rhExprRegisterFunction('LEN',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('LEN', A, 1, 1); Result := Length(VarToStr(A[0])); end);

  rhExprRegisterFunction('COPY',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('COPY', A, 3, 3); Result := Copy(VarToStr(A[0]), Integer(A[1]), Integer(A[2])); end);

  rhExprRegisterFunction('POS',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('POS', A, 2, 2); Result := Pos(VarToStr(A[0]), VarToStr(A[1])); end);

  rhExprRegisterFunction('LEFT',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('LEFT', A, 2, 2); Result := LeftStr(VarToStr(A[0]), Integer(A[1])); end);

  rhExprRegisterFunction('RIGHT',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('RIGHT', A, 2, 2); Result := RightStr(VarToStr(A[0]), Integer(A[1])); end);

  rhExprRegisterFunction('REPLACE',
    function(const A: TArray<Variant>): Variant
    begin
      NeedArgs('REPLACE', A, 3, 3);
      Result := ReplaceStr(VarToStr(A[0]), VarToStr(A[1]), VarToStr(A[2]));
    end);

  rhExprRegisterFunction('REPLICATE',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('REPLICATE', A, 2, 2); Result := DupeString(VarToStr(A[0]), Integer(A[1])); end);

  rhExprRegisterFunction('PADLEFT',
    function(const A: TArray<Variant>): Variant
    var Ch: Char;
    begin
      NeedArgs('PADLEFT', A, 2, 3);
      if Length(A) = 3 then Ch := ArgChar(A[2], ' ') else Ch := ' ';
      Result := StrPadLeft(VarToStr(A[0]), Integer(A[1]), Ch);
    end);

  rhExprRegisterFunction('PADRIGHT',
    function(const A: TArray<Variant>): Variant
    var Ch: Char;
    begin
      NeedArgs('PADRIGHT', A, 2, 3);
      if Length(A) = 3 then Ch := ArgChar(A[2], ' ') else Ch := ' ';
      Result := StrPadRight(VarToStr(A[0]), Integer(A[1]), Ch);
    end);

  rhExprRegisterFunction('PROPER',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('PROPER', A, 1, 1); Result := StrProper(VarToStr(A[0])); end);

  rhExprRegisterFunction('CONCAT',
    function(const A: TArray<Variant>): Variant
    var I: Integer;
    begin
      Result := '';
      for I := 0 to High(A) do
        Result := VarToStr(Result) + VarToStr(A[I]);
    end);

  rhExprRegisterFunction('CONTAINS',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('CONTAINS', A, 2, 2); Result := ContainsStr(VarToStr(A[0]), VarToStr(A[1])); end);

  rhExprRegisterFunction('STARTSWITH',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('STARTSWITH', A, 2, 2); Result := StartsStr(VarToStr(A[1]), VarToStr(A[0])); end);

  rhExprRegisterFunction('ENDSWITH',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('ENDSWITH', A, 2, 2); Result := EndsStr(VarToStr(A[1]), VarToStr(A[0])); end);

  rhExprRegisterFunction('ONLYDIGITS',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('ONLYDIGITS', A, 1, 1); Result := StrOnlyDigits(VarToStr(A[0])); end);

  rhExprRegisterFunction('MASK',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('MASK', A, 2, 2); Result := StrApplyMask(VarToStr(A[0]), VarToStr(A[1])); end);

  rhExprRegisterFunction('CHR',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('CHR', A, 1, 1); Result := string(Char(Integer(A[0]))); end);

  rhExprRegisterFunction('ASC',
    function(const A: TArray<Variant>): Variant
    var S: string;
    begin
      NeedArgs('ASC', A, 1, 1);
      S := VarToStr(A[0]);
      if S = '' then Result := 0 else Result := Ord(S[1]);
    end);

  rhExprRegisterFunction('IIF',
    function(const A: TArray<Variant>): Variant
    begin
      NeedArgs('IIF', A, 3, 3);
      if ArgBool(A[0]) then Result := A[1] else Result := A[2];
    end);

  rhExprRegisterFunction('COALESCE',
    function(const A: TArray<Variant>): Variant
    var I: Integer;
    begin
      Result := Null;
      for I := 0 to High(A) do
        if not (VarIsNull(A[I]) or VarIsEmpty(A[I])) then Exit(A[I]);
    end);

  rhExprRegisterFunction('ROUND',
    function(const A: TArray<Variant>): Variant
    var D: Integer;
    begin
      NeedArgs('ROUND', A, 1, 2);
      if Length(A) = 2 then D := Integer(A[1]) else D := 0;
      Result := RoundTo(Double(A[0]), -D);
    end);

  rhExprRegisterFunction('TRUNC',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('TRUNC', A, 1, 1); Result := Trunc(Double(A[0])); end);

  rhExprRegisterFunction('INT',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('INT', A, 1, 1); Result := Int(Double(A[0])); end);

  rhExprRegisterFunction('ABS',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('ABS', A, 1, 1); Result := Abs(Double(A[0])); end);

  rhExprRegisterFunction('FORMATFLOAT',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('FORMATFLOAT', A, 2, 2); Result := FormatFloat(VarToStr(A[0]), Double(A[1])); end);

  rhExprRegisterFunction('FORMATDATETIME',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('FORMATDATETIME', A, 2, 2); Result := FormatDateTime(VarToStr(A[0]), TDateTime(A[1])); end);

  rhExprRegisterFunction('DATETOSTR',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('DATETOSTR', A, 1, 1); Result := DateToStr(TDateTime(A[0])); end);

  rhExprRegisterFunction('STR',
    function(const A: TArray<Variant>): Variant
    begin NeedArgs('STR', A, 1, 1); Result := VarToStr(A[0]); end);

  rhExprRegisterFunction('NOW',
    function(const A: TArray<Variant>): Variant
    begin Result := Now; end);
end;

initialization
  GFunctions := TDictionary<string, TrhFunctionProc>.Create;
  RegisterBuiltins;

finalization
  GFunctions.Free;

end.
