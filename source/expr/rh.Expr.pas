{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Fachada do motor de expressoes:
///     - TrhExpression: compila uma expressao e avalia contra um contexto.
///     - rhEvalText: processa um texto com ilhas [expr] (ex.: um TrhTextObject),
///       substituindo cada ilha pelo valor calculado. Colchetes sao balanceados,
///       entao campos [Campo] podem aparecer dentro de funcoes/agregacoes.
///     - TrhDictContext: contexto simples (dicionario) para testes/uso avulso.
/// </summary>
unit rh.Expr;

interface

uses
  System.Generics.Collections, rh.Expr.Nodes;

type
  TrhExpression = class
  private
    FRoot: TrhExprNode;
  public
    constructor Create(const Source: string);
    destructor Destroy; override;
    function Evaluate(const Ctx: IrhEvalContext): Variant;
    function EvaluateToStr(const Ctx: IrhEvalContext): string;
  end;

  /// <summary>Contexto de avaliacao baseado em dicionario (fields/variaveis).</summary>
  TrhDictContext = class(TInterfacedObject, IrhEvalContext)
  private
    FValues: TDictionary<string, Variant>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetValue(const Name: string; const Value: Variant);
    // IrhEvalContext
    function GetValue(const Name: string; out Value: Variant): Boolean;
    function EvalAggregate(const FuncName: string; Arg: TrhExprNode): Variant;
  end;

/// <summary>Compila, avalia e libera — atalho para uma unica avaliacao.</summary>
function rhEvalExpr(const Source: string; const Ctx: IrhEvalContext): Variant;

/// <summary>Processa um texto com ilhas [expr], retornando o texto final.</summary>
function rhEvalText(const S: string; const Ctx: IrhEvalContext): string;

implementation

uses
  System.SysUtils, System.Variants, rh.Expr.Parser;

{ TrhExpression }

constructor TrhExpression.Create(const Source: string);
begin
  inherited Create;
  FRoot := TrhExprParser.Parse(Source);
end;

destructor TrhExpression.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

function TrhExpression.Evaluate(const Ctx: IrhEvalContext): Variant;
begin
  Result := FRoot.Evaluate(Ctx);
end;

function TrhExpression.EvaluateToStr(const Ctx: IrhEvalContext): string;
begin
  Result := VarToStr(Evaluate(Ctx));
end;

{ funcoes utilitarias }

function rhEvalExpr(const Source: string; const Ctx: IrhEvalContext): Variant;
var
  Expr: TrhExpression;
begin
  Expr := TrhExpression.Create(Source);
  try
    Result := Expr.Evaluate(Ctx);
  finally
    Expr.Free;
  end;
end;

function rhEvalText(const S: string; const Ctx: IrhEvalContext): string;
var
  I, J, N, Depth: Integer;
  ExprText: string;
begin
  Result := '';
  I := 1;
  N := Length(S);
  while I <= N do
  begin
    if S[I] = '[' then
    begin
      Depth := 1;
      J := I + 1;
      while (J <= N) and (Depth > 0) do
      begin
        if S[J] = '[' then Inc(Depth)
        else if S[J] = ']' then
        begin
          Dec(Depth);
          if Depth = 0 then Break;
        end;
        Inc(J);
      end;
      if Depth = 0 then
      begin
        ExprText := Copy(S, I + 1, J - I - 1);
        try
          Result := Result + VarToStr(rhEvalExpr(ExprText, Ctx));
        except
          Result := Result + Copy(S, I, J - I + 1); // erro -> mantem literal
        end;
        I := J + 1;
      end
      else
      begin
        Result := Result + Copy(S, I, N - I + 1); // sem fechamento -> literal
        Break;
      end;
    end
    else
    begin
      Result := Result + S[I];
      Inc(I);
    end;
  end;
end;

{ TrhDictContext }

constructor TrhDictContext.Create;
begin
  inherited Create;
  FValues := TDictionary<string, Variant>.Create;
end;

destructor TrhDictContext.Destroy;
begin
  FValues.Free;
  inherited Destroy;
end;

procedure TrhDictContext.SetValue(const Name: string; const Value: Variant);
begin
  FValues.AddOrSetValue(UpperCase(Name), Value);
end;

function TrhDictContext.GetValue(const Name: string; out Value: Variant): Boolean;
begin
  Result := FValues.TryGetValue(UpperCase(Name), Value);
  if Result then Exit;
  // pseudo-variaveis
  if SameText(Name, 'DATE') or SameText(Name, 'TODAY') then
  begin Value := Date; Exit(True); end;
  if SameText(Name, 'TIME') then
  begin Value := Time; Exit(True); end;
  if SameText(Name, 'NOW') then
  begin Value := Now; Exit(True); end;
  Value := Null;
end;

function TrhDictContext.EvalAggregate(const FuncName: string; Arg: TrhExprNode): Variant;
begin
  // Agregacoes ganham vida na Fase 4 (pipeline de dados com acumuladores).
  Result := Null;
end;

end.
