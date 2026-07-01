{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Lexer (tokenizador) do motor de expressoes. Transforma o texto de uma
///   expressao numa sequencia de tokens. Campos sao escritos como [Nome];
///   strings entre aspas simples ou duplas; AND/OR/NOT sao operadores.
/// </summary>
unit rh.Expr.Lexer;

interface

type
  TrhTokenKind = (
    tkEOF, tkNum, tkStr, tkIdent, tkField,
    tkLParen, tkRParen, tkComma,
    tkPlus, tkMinus, tkMul, tkDiv, tkMod,
    tkEq, tkNe, tkLt, tkLe, tkGt, tkGe,
    tkAnd, tkOr, tkNot
  );

  TrhToken = record
    Kind: TrhTokenKind;
    Str: string;   // ident/field/string
    Num: Double;   // numero
    Pos: Integer;  // posicao no texto (1-based)
  end;

  TrhLexer = class
  private
    FSrc: string;
    FLen: Integer;
    FPos: Integer;
    function CurCh: Char;
    function NextCh: Char;
    procedure Skip;
  public
    constructor Create(const ASource: string);
    function NextToken: TrhToken;
  end;

implementation

uses
  System.SysUtils;

function IsAlphaCh(C: Char): Boolean; inline;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or (C = '_');
end;

function IsDigitCh(C: Char): Boolean; inline;
begin
  Result := (C >= '0') and (C <= '9');
end;

{ TrhLexer }

constructor TrhLexer.Create(const ASource: string);
begin
  inherited Create;
  FSrc := ASource;
  FLen := Length(FSrc);
  FPos := 1;
end;

function TrhLexer.CurCh: Char;
begin
  if FPos <= FLen then Result := FSrc[FPos] else Result := #0;
end;

function TrhLexer.NextCh: Char;
begin
  if FPos + 1 <= FLen then Result := FSrc[FPos + 1] else Result := #0;
end;

procedure TrhLexer.Skip;
begin
  while (FPos <= FLen) and (FSrc[FPos] <= ' ') do
    Inc(FPos);
end;

function TrhLexer.NextToken: TrhToken;
var
  StartPos: Integer;
  Quote: Char;
  S: string;
  FS: TFormatSettings;
begin
  Skip;
  Result.Str := '';
  Result.Num := 0;
  Result.Pos := FPos;

  if FPos > FLen then
  begin
    Result.Kind := tkEOF;
    Exit;
  end;

  // --- campo [Nome] ---
  if CurCh = '[' then
  begin
    Inc(FPos);
    StartPos := FPos;
    while (FPos <= FLen) and (FSrc[FPos] <> ']') do
      Inc(FPos);
    Result.Str := Copy(FSrc, StartPos, FPos - StartPos);
    if CurCh = ']' then Inc(FPos);
    Result.Kind := tkField;
    Exit;
  end;

  // --- string 'x' ou "x" ---
  if (CurCh = '''') or (CurCh = '"') then
  begin
    Quote := CurCh;
    Inc(FPos);
    S := '';
    while FPos <= FLen do
    begin
      if FSrc[FPos] = Quote then
      begin
        if NextCh = Quote then // aspa dobrada = literal
        begin
          S := S + Quote;
          Inc(FPos, 2);
          Continue;
        end
        else
        begin
          Inc(FPos);
          Break;
        end;
      end;
      S := S + FSrc[FPos];
      Inc(FPos);
    end;
    Result.Kind := tkStr;
    Result.Str := S;
    Exit;
  end;

  // --- numero ---
  if IsDigitCh(CurCh) or ((CurCh = '.') and IsDigitCh(NextCh)) then
  begin
    StartPos := FPos;
    while (FPos <= FLen) and IsDigitCh(FSrc[FPos]) do Inc(FPos);
    if CurCh = '.' then
    begin
      Inc(FPos);
      while (FPos <= FLen) and IsDigitCh(FSrc[FPos]) do Inc(FPos);
    end;
    if (CurCh = 'e') or (CurCh = 'E') then
    begin
      Inc(FPos);
      if (CurCh = '+') or (CurCh = '-') then Inc(FPos);
      while (FPos <= FLen) and IsDigitCh(FSrc[FPos]) do Inc(FPos);
    end;
    S := Copy(FSrc, StartPos, FPos - StartPos);
    FS := TFormatSettings.Invariant;
    Result.Kind := tkNum;
    Result.Num := StrToFloat(S, FS);
    Exit;
  end;

  // --- identificador / palavra-chave ---
  if IsAlphaCh(CurCh) then
  begin
    StartPos := FPos;
    while (FPos <= FLen) and (IsAlphaCh(FSrc[FPos]) or IsDigitCh(FSrc[FPos])) do
      Inc(FPos);
    S := Copy(FSrc, StartPos, FPos - StartPos);
    if SameText(S, 'and') then Result.Kind := tkAnd
    else if SameText(S, 'or') then Result.Kind := tkOr
    else if SameText(S, 'not') then Result.Kind := tkNot
    else if SameText(S, 'mod') then Result.Kind := tkMod
    else
    begin
      Result.Kind := tkIdent;
      Result.Str := S;
    end;
    Exit;
  end;

  // --- operadores e pontuacao ---
  case CurCh of
    '(': begin Inc(FPos); Result.Kind := tkLParen; Exit; end;
    ')': begin Inc(FPos); Result.Kind := tkRParen; Exit; end;
    ',': begin Inc(FPos); Result.Kind := tkComma; Exit; end;
    '+': begin Inc(FPos); Result.Kind := tkPlus; Exit; end;
    '-': begin Inc(FPos); Result.Kind := tkMinus; Exit; end;
    '*': begin Inc(FPos); Result.Kind := tkMul; Exit; end;
    '/': begin Inc(FPos); Result.Kind := tkDiv; Exit; end;
    '%': begin Inc(FPos); Result.Kind := tkMod; Exit; end;
    '=': begin Inc(FPos); Result.Kind := tkEq; Exit; end;
    '<':
      begin
        Inc(FPos);
        if CurCh = '=' then begin Inc(FPos); Result.Kind := tkLe; end
        else if CurCh = '>' then begin Inc(FPos); Result.Kind := tkNe; end
        else Result.Kind := tkLt;
        Exit;
      end;
    '>':
      begin
        Inc(FPos);
        if CurCh = '=' then begin Inc(FPos); Result.Kind := tkGe; end
        else Result.Kind := tkGt;
        Exit;
      end;
  end;

  raise Exception.CreateFmt('ReportsHowie: caractere inesperado "%s" na posicao %d.',
    [CurCh, FPos]);
end;

end.
