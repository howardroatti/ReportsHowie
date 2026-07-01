{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Parser descendente-recursivo (precedence climbing) que constroi a arvore
///   de expressao a partir dos tokens. Precedencia (menor -> maior):
///   OR, AND, comparacao, aditivo, multiplicativo, unario, primario.
/// </summary>
unit rh.Expr.Parser;

interface

uses
  rh.Expr.Nodes;

type
  TrhExprParser = class
  public
    /// <summary>Compila a expressao numa arvore. O chamador e dono do resultado.</summary>
    class function Parse(const Source: string): TrhExprNode;
  end;

implementation

uses
  System.SysUtils, System.Variants, System.Math, System.Generics.Collections,
  rh.Expr.Lexer;

type
  TParserState = class
  private
    FTokens: TList<TrhToken>;
    FIdx: Integer;
    function Cur: TrhToken;
    procedure Advance;
    procedure Expect(Kind: TrhTokenKind; const What: string);
    function IsAggregate(const Name: string): Boolean;
    function ParseExpr: TrhExprNode;
    function ParseOr: TrhExprNode;
    function ParseAnd: TrhExprNode;
    function ParseCmp: TrhExprNode;
    function ParseAdd: TrhExprNode;
    function ParseMul: TrhExprNode;
    function ParseUnary: TrhExprNode;
    function ParsePrimary: TrhExprNode;
  public
    constructor Create(const Source: string);
    destructor Destroy; override;
    function Run: TrhExprNode;
  end;

{ TParserState }

constructor TParserState.Create(const Source: string);
var
  Lex: TrhLexer;
  Tok: TrhToken;
begin
  inherited Create;
  FTokens := TList<TrhToken>.Create;
  FIdx := 0;
  Lex := TrhLexer.Create(Source);
  try
    repeat
      Tok := Lex.NextToken;
      FTokens.Add(Tok);
    until Tok.Kind = tkEOF;
  finally
    Lex.Free;
  end;
end;

destructor TParserState.Destroy;
begin
  FTokens.Free;
  inherited Destroy;
end;

function TParserState.Cur: TrhToken;
begin
  Result := FTokens[FIdx];
end;

procedure TParserState.Advance;
begin
  if FIdx < FTokens.Count - 1 then Inc(FIdx);
end;

procedure TParserState.Expect(Kind: TrhTokenKind; const What: string);
begin
  if Cur.Kind <> Kind then
    raise Exception.CreateFmt('ReportsHowie: esperado %s na posicao %d.', [What, Cur.Pos]);
  Advance;
end;

function TParserState.IsAggregate(const Name: string): Boolean;
begin
  Result := SameText(Name, 'SUM') or SameText(Name, 'AVG') or SameText(Name, 'COUNT')
    or SameText(Name, 'MIN') or SameText(Name, 'MAX')
    or SameText(Name, 'FIRST') or SameText(Name, 'LAST');
end;

function TParserState.Run: TrhExprNode;
begin
  Result := ParseExpr;
  if Cur.Kind <> tkEOF then
  begin
    Result.Free;
    raise Exception.CreateFmt('ReportsHowie: token inesperado na posicao %d.', [Cur.Pos]);
  end;
end;

function TParserState.ParseExpr: TrhExprNode;
begin
  Result := ParseOr;
end;

function TParserState.ParseOr: TrhExprNode;
begin
  Result := ParseAnd;
  while Cur.Kind = tkOr do
  begin
    Advance;
    Result := TrhBinaryNode.Create(rhbOr, Result, ParseAnd);
  end;
end;

function TParserState.ParseAnd: TrhExprNode;
begin
  Result := ParseCmp;
  while Cur.Kind = tkAnd do
  begin
    Advance;
    Result := TrhBinaryNode.Create(rhbAnd, Result, ParseCmp);
  end;
end;

function TParserState.ParseCmp: TrhExprNode;
var
  Op: TrhBinaryOp;
begin
  Result := ParseAdd;
  case Cur.Kind of
    tkEq: Op := rhbEq;
    tkNe: Op := rhbNe;
    tkLt: Op := rhbLt;
    tkLe: Op := rhbLe;
    tkGt: Op := rhbGt;
    tkGe: Op := rhbGe;
  else
    Exit;
  end;
  Advance;
  Result := TrhBinaryNode.Create(Op, Result, ParseAdd);
end;

function TParserState.ParseAdd: TrhExprNode;
var
  Op: TrhBinaryOp;
begin
  Result := ParseMul;
  while Cur.Kind in [tkPlus, tkMinus] do
  begin
    if Cur.Kind = tkPlus then Op := rhbAdd else Op := rhbSub;
    Advance;
    Result := TrhBinaryNode.Create(Op, Result, ParseMul);
  end;
end;

function TParserState.ParseMul: TrhExprNode;
var
  Op: TrhBinaryOp;
begin
  Result := ParseUnary;
  while Cur.Kind in [tkMul, tkDiv, tkMod] do
  begin
    case Cur.Kind of
      tkMul: Op := rhbMul;
      tkDiv: Op := rhbDiv;
    else
      Op := rhbMod;
    end;
    Advance;
    Result := TrhBinaryNode.Create(Op, Result, ParseUnary);
  end;
end;

function TParserState.ParseUnary: TrhExprNode;
begin
  case Cur.Kind of
    tkMinus:
      begin Advance; Result := TrhUnaryNode.Create(rhuNeg, ParseUnary); end;
    tkNot:
      begin Advance; Result := TrhUnaryNode.Create(rhuNot, ParseUnary); end;
    tkPlus:
      begin Advance; Result := ParseUnary; end;
  else
    Result := ParsePrimary;
  end;
end;

function TParserState.ParsePrimary: TrhExprNode;
var
  Name: string;
  Func: TrhFuncNode;
  Arg: TrhExprNode;
begin
  case Cur.Kind of
    tkNum:
      begin Result := TrhLiteralNode.Create(Cur.Num); Advance; end;
    tkStr:
      begin Result := TrhLiteralNode.Create(Cur.Str); Advance; end;
    tkField:
      begin Result := TrhRefNode.Create(Cur.Str); Advance; end;
    tkLParen:
      begin
        Advance;
        Result := ParseExpr;
        Expect(tkRParen, '")"');
      end;
    tkIdent:
      begin
        Name := Cur.Str;
        Advance;
        if Cur.Kind = tkLParen then
        begin
          Advance; // consome '('
          if IsAggregate(Name) then
          begin
            Arg := ParseExpr;
            Expect(tkRParen, '")"');
            Result := TrhAggregateNode.Create(Name, Arg);
          end
          else
          begin
            Func := TrhFuncNode.Create(Name);
            if Cur.Kind <> tkRParen then
            begin
              Func.AddArg(ParseExpr);
              while Cur.Kind = tkComma do
              begin
                Advance;
                Func.AddArg(ParseExpr);
              end;
            end;
            Expect(tkRParen, '")"');
            Result := Func;
          end;
        end
        else if SameText(Name, 'TRUE') then
          Result := TrhLiteralNode.Create(True)
        else if SameText(Name, 'FALSE') then
          Result := TrhLiteralNode.Create(False)
        else if SameText(Name, 'NULL') then
          Result := TrhLiteralNode.Create(Null)
        else if SameText(Name, 'PI') then
          Result := TrhLiteralNode.Create(Pi)
        else
          Result := TrhRefNode.Create(Name);
      end;
  else
    raise Exception.CreateFmt('ReportsHowie: expressao invalida na posicao %d.', [Cur.Pos]);
  end;
end;

{ TrhExprParser }

class function TrhExprParser.Parse(const Source: string): TrhExprNode;
var
  State: TParserState;
begin
  State := TParserState.Create(Source);
  try
    Result := State.Run;
  finally
    State.Free;
  end;
end;

end.
