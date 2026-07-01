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

implementation

uses
  System.SysUtils, System.Variants, System.Math, System.Generics.Collections;

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

procedure NeedArgs(const FuncName: string; const Args: TArray<Variant>; MinN, MaxN: Integer);
begin
  if (Length(Args) < MinN) or ((MaxN >= 0) and (Length(Args) > MaxN)) then
    raise Exception.CreateFmt('ReportsHowie: numero de argumentos invalido para %s.', [FuncName]);
end;

function ArgBool(const V: Variant): Boolean;
begin
  if VarIsNull(V) or VarIsEmpty(V) then Result := False else Result := V;
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
