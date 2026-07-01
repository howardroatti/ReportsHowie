{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Nos da arvore de expressao e a interface de contexto de avaliacao.
///   Valores usam Variant (a RTL cuida de coercao e operadores). Nos de
///   agregacao (SUM/AVG/...) delegam ao contexto, que na Fase 4 mantera os
///   acumuladores por escopo de banda.
/// </summary>
unit rh.Expr.Nodes;

interface

uses
  System.Generics.Collections;

type
  TrhExprNode = class;

  /// <summary>Contexto de avaliacao: resolve campos/variaveis/pseudo e agregados.</summary>
  IrhEvalContext = interface
    ['{3B1D9F4A-6C2E-4E7A-9A1C-2F0E8B7A5D31}']
    /// <summary>Resolve [Campo] ou identificador (variavel/pseudo). False se desconhecido.</summary>
    function GetValue(const Name: string; out Value: Variant): Boolean;
    /// <summary>Valor acumulado de uma agregacao para o no informado (Fase 4).</summary>
    function EvalAggregate(const FuncName: string; Arg: TrhExprNode): Variant;
  end;

  TrhUnaryOp = (rhuNeg, rhuNot);
  TrhBinaryOp = (rhbAdd, rhbSub, rhbMul, rhbDiv, rhbMod,
                 rhbEq, rhbNe, rhbLt, rhbLe, rhbGt, rhbGe, rhbAnd, rhbOr);

  TrhExprNode = class
  public
    function Evaluate(const Ctx: IrhEvalContext): Variant; virtual; abstract;
  end;

  TrhLiteralNode = class(TrhExprNode)
  private
    FValue: Variant;
  public
    constructor Create(const AValue: Variant);
    function Evaluate(const Ctx: IrhEvalContext): Variant; override;
  end;

  /// <summary>Referencia a [Campo] ou variavel — resolve via contexto.</summary>
  TrhRefNode = class(TrhExprNode)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    function Evaluate(const Ctx: IrhEvalContext): Variant; override;
  end;

  TrhUnaryNode = class(TrhExprNode)
  private
    FOp: TrhUnaryOp;
    FOperand: TrhExprNode;
  public
    constructor Create(AOp: TrhUnaryOp; AOperand: TrhExprNode);
    destructor Destroy; override;
    function Evaluate(const Ctx: IrhEvalContext): Variant; override;
  end;

  TrhBinaryNode = class(TrhExprNode)
  private
    FOp: TrhBinaryOp;
    FLeft, FRight: TrhExprNode;
  public
    constructor Create(AOp: TrhBinaryOp; ALeft, ARight: TrhExprNode);
    destructor Destroy; override;
    function Evaluate(const Ctx: IrhEvalContext): Variant; override;
  end;

  TrhFuncNode = class(TrhExprNode)
  private
    FName: string;
    FArgs: TObjectList<TrhExprNode>;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;
    procedure AddArg(Node: TrhExprNode);
    function Evaluate(const Ctx: IrhEvalContext): Variant; override;
  end;

  /// <summary>Agregacao SUM/AVG/COUNT/MIN/MAX(arg) — avaliada pelo contexto.</summary>
  TrhAggregateNode = class(TrhExprNode)
  private
    FFuncName: string;
    FArg: TrhExprNode;
  public
    constructor Create(const AFuncName: string; AArg: TrhExprNode);
    destructor Destroy; override;
    function Evaluate(const Ctx: IrhEvalContext): Variant; override;
    property FuncName: string read FFuncName;
    property Arg: TrhExprNode read FArg;
  end;

function AsBoolean(const V: Variant): Boolean;

implementation

uses
  System.Variants, System.SysUtils, rh.Expr.Functions;

function AsBoolean(const V: Variant): Boolean;
begin
  if VarIsNull(V) or VarIsEmpty(V) then
    Result := False
  else
    Result := V; // conversao implicita Variant -> Boolean
end;

{ TrhLiteralNode }

constructor TrhLiteralNode.Create(const AValue: Variant);
begin
  inherited Create;
  FValue := AValue;
end;

function TrhLiteralNode.Evaluate(const Ctx: IrhEvalContext): Variant;
begin
  Result := FValue;
end;

{ TrhRefNode }

constructor TrhRefNode.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

function TrhRefNode.Evaluate(const Ctx: IrhEvalContext): Variant;
begin
  if (Ctx = nil) or not Ctx.GetValue(FName, Result) then
    Result := Null;
end;

{ TrhUnaryNode }

constructor TrhUnaryNode.Create(AOp: TrhUnaryOp; AOperand: TrhExprNode);
begin
  inherited Create;
  FOp := AOp;
  FOperand := AOperand;
end;

destructor TrhUnaryNode.Destroy;
begin
  FOperand.Free;
  inherited Destroy;
end;

function TrhUnaryNode.Evaluate(const Ctx: IrhEvalContext): Variant;
var
  V: Variant;
begin
  V := FOperand.Evaluate(Ctx);
  case FOp of
    rhuNeg: Result := -V;
    rhuNot: Result := not AsBoolean(V);
  else
    Result := Null;
  end;
end;

{ TrhBinaryNode }

constructor TrhBinaryNode.Create(AOp: TrhBinaryOp; ALeft, ARight: TrhExprNode);
begin
  inherited Create;
  FOp := AOp;
  FLeft := ALeft;
  FRight := ARight;
end;

destructor TrhBinaryNode.Destroy;
begin
  FLeft.Free;
  FRight.Free;
  inherited Destroy;
end;

function TrhBinaryNode.Evaluate(const Ctx: IrhEvalContext): Variant;
var
  L, R: Variant;
  LI, RI: Int64;
begin
  L := FLeft.Evaluate(Ctx);
  // curto-circuito para AND/OR
  if FOp = rhbAnd then
  begin
    if not AsBoolean(L) then Exit(False);
    Exit(AsBoolean(FRight.Evaluate(Ctx)));
  end;
  if FOp = rhbOr then
  begin
    if AsBoolean(L) then Exit(True);
    Exit(AsBoolean(FRight.Evaluate(Ctx)));
  end;

  R := FRight.Evaluate(Ctx);
  case FOp of
    rhbAdd: Result := L + R;
    rhbSub: Result := L - R;
    rhbMul: Result := L * R;
    rhbDiv: Result := L / R;
    rhbMod:
      begin
        LI := L; RI := R;
        Result := LI mod RI;
      end;
    rhbEq:  Result := VarCompareValue(L, R) = vrEqual;
    rhbNe:  Result := VarCompareValue(L, R) <> vrEqual;
    rhbLt:  Result := VarCompareValue(L, R) = vrLessThan;
    rhbLe:  Result := VarCompareValue(L, R) in [vrLessThan, vrEqual];
    rhbGt:  Result := VarCompareValue(L, R) = vrGreaterThan;
    rhbGe:  Result := VarCompareValue(L, R) in [vrGreaterThan, vrEqual];
  else
    Result := Null;
  end;
end;

{ TrhFuncNode }

constructor TrhFuncNode.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FArgs := TObjectList<TrhExprNode>.Create(True);
end;

destructor TrhFuncNode.Destroy;
begin
  FArgs.Free;
  inherited Destroy;
end;

procedure TrhFuncNode.AddArg(Node: TrhExprNode);
begin
  FArgs.Add(Node);
end;

function TrhFuncNode.Evaluate(const Ctx: IrhEvalContext): Variant;
var
  Vals: TArray<Variant>;
  I: Integer;
begin
  SetLength(Vals, FArgs.Count);
  for I := 0 to FArgs.Count - 1 do
    Vals[I] := FArgs[I].Evaluate(Ctx);
  if not rhExprCallFunction(FName, Vals, Result) then
    raise Exception.CreateFmt('ReportsHowie: funcao desconhecida "%s".', [FName]);
end;

{ TrhAggregateNode }

constructor TrhAggregateNode.Create(const AFuncName: string; AArg: TrhExprNode);
begin
  inherited Create;
  FFuncName := AFuncName;
  FArg := AArg;
end;

destructor TrhAggregateNode.Destroy;
begin
  FArg.Free;
  inherited Destroy;
end;

function TrhAggregateNode.Evaluate(const Ctx: IrhEvalContext): Variant;
begin
  if Ctx <> nil then
    Result := Ctx.EvalAggregate(FFuncName, Self)
  else
    Result := Null;
end;

end.
