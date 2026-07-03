{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Codificadores de codigo de barras 1D em PURO PASCAL (zero dependencias).
///   Cada simbologia produz um "run-length pattern": um vetor de larguras de
///   elementos em MODULOS, alternando BARRA, espaco, BARRA, espaco... sempre
///   comecando por barra (indice par = barra). O motor de renderizacao expande
///   isso em retangulos (rhdkRect) na display list -> funciona em preview e em
///   TODOS os exports (PDF/HTML/...) sem codigo extra.
///
///   Simbologias:
///     - Code 128 (Code Set B): todo ASCII imprimivel (32..126). Digito de
///       verificacao modulo 103. Tabela conferida contra a lib python-barcode.
///     - Code 39: 0-9 A-Z e - . espaco $ / + % (delimitado por '*'). Sem
///       digito verificador (auto-verificavel). Idem conferido.
/// </summary>
unit rh.Barcode;

interface

uses
  rh.Model.Types;

type
  /// <summary>Larguras de elementos em modulos: [barra, espaco, barra, ...].</summary>
  TrhBarPattern = TArray<Integer>;

/// <summary>Codifica Data na simbologia dada. Retorna [] se vazio/invalido.</summary>
function rhEncodeBarcode(Sym: TrhBarcodeSymbology; const Data: string): TrhBarPattern;

/// <summary>Soma das larguras (total de modulos) - usado para escalar a largura.</summary>
function rhBarPatternModules(const P: TrhBarPattern): Integer;

implementation

uses
  System.SysUtils;

{ ===== Code 128 (Code Set B) ===== }

const
  // Padroes 0..106 (larguras dos 6 elementos; o 106/STOP tem 7). Tabela canonica.
  C128_START_B = 104;
  C128_STOP    = 106;
  C128: array[0..106] of string = (
    '212222','222122','222221','121223','121322','131222','122213','122312','132212','221213',
    '221312','231212','112232','122132','122231','113222','123122','123221','223211','221132',
    '221231','213212','223112','312131','311222','321122','321221','312212','322112','322211',
    '212123','212321','232121','111323','131123','131321','112313','132113','132311','211313',
    '231113','231311','112133','112331','132131','113123','113321','133121','313121','211331',
    '231131','213113','213311','213131','311123','311321','331121','312113','312311','332111',
    '314111','221411','431111','111224','111422','121124','121421','141122','141221','112214',
    '112412','122114','122411','142112','142211','241211','221114','413111','241112','134111',
    '111242','121142','121241','114212','124112','124211','411212','421112','421211','212141',
    '214121','412121','111143','111341','131141','114113','114311','411113','411311','113141',
    '114131','311141','411131','211412','211214','211232','2331112');

// Converte a string de larguras '212222' (digitos) em elementos no fim de P.
procedure AppendWidths(var P: TrhBarPattern; var N: Integer; const S: string);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
  begin
    P[N] := Ord(S[I]) - Ord('0');
    Inc(N);
  end;
end;

// Idem para padroes 'n'/'w' do Code 39 (n=estreito=1, w=largo=3).
procedure AppendWidths39(var P: TrhBarPattern; var N: Integer; const S: string);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
  begin
    if S[I] = 'w' then P[N] := 3 else P[N] := 1;
    Inc(N);
  end;
end;

function EncodeCode128B(const Data: string): TrhBarPattern;
var
  Vals: TArray<Integer>;
  I, V, Sum, Chk, N, Cap: Integer;
begin
  if Data = '' then Exit(nil);

  SetLength(Vals, Length(Data));
  Sum := C128_START_B; // Start B tem peso 1
  for I := 1 to Length(Data) do
  begin
    V := Ord(Data[I]) - 32;         // Set B: ASCII 32..126 -> valor 0..94
    if (V < 0) or (V > 94) then
      V := 0;                        // fora do alcance -> espaco (' ')
    Vals[I - 1] := V;
    Sum := Sum + V * I;              // posicao 1-based
  end;
  Chk := Sum mod 103;

  // capacidade: (Start + dados + Chk) * 6 + Stop(7)
  Cap := (2 + Length(Vals)) * 6 + 7;
  SetLength(Result, Cap);
  N := 0;
  AppendWidths(Result, N, C128[C128_START_B]);
  for I := 0 to High(Vals) do
    AppendWidths(Result, N, C128[Vals[I]]);
  AppendWidths(Result, N, C128[Chk]);
  AppendWidths(Result, N, C128[C128_STOP]);
  SetLength(Result, N);
end;

{ ===== Code 39 ===== }

const
  // Ordem dos caracteres casada 1:1 com C39PAT (n=estreito, w=largo).
  C39_CHARS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. *$/+%';
  C39_PAT: array[0..43] of string = (
    'nnnwwnwnn','wnnwnnnnw','nnwwnnnnw','wnwwnnnnn','nnnwwnnnw', // 0-4
    'wnnwwnnnn','nnwwwnnnn','nnnwnnwnw','wnnwnnwnn','nnwwnnwnn', // 5-9
    'wnnnnwnnw','nnwnnwnnw','wnwnnwnnn','nnnnwwnnw','wnnnwwnnn', // A-E
    'nnwnwwnnn','nnnnnwwnw','wnnnnwwnn','nnwnnwwnn','nnnnwwwnn', // F-J
    'wnnnnnnww','nnwnnnnww','wnwnnnnwn','nnnnwnnww','wnnnwnnwn', // K-O
    'nnwnwnnwn','nnnnnnwww','wnnnnnwwn','nnwnnnwwn','nnnnwnwwn', // P-T
    'wwnnnnnnw','nwwnnnnnw','wwwnnnnnn','nwnnwnnnw','wwnnwnnnn', // U-Y
    'nwwnwnnnn',                                                  // Z
    'nwnnnnwnw','wwnnnnwnn','nwwnnnwnn','nwnnwnwnn',              // - . space *
    'nwnwnwnnn','nwnwnnnwn','nwnnnwnwn','nnnwnwnwn');             // $ / + %

function EncodeCode39(const Data: string): TrhBarPattern;
const
  C39_STAR = 39; // indice de '*' em C39_CHARS
var
  Up: string;
  Chars: array of Integer; // indices na tabela (com '*' de inicio/fim)
  I, K, Idx, N: Integer;
  C: Char;
begin
  if Data = '' then Exit(nil);
  Up := UpperCase(Data);

  // resolve indices dos caracteres validos; ignora invalidos e '*' do usuario
  SetLength(Chars, Length(Up) + 2);
  N := 0;
  Chars[N] := C39_STAR; Inc(N); // '*' de inicio
  for I := 1 to Length(Up) do
  begin
    C := Up[I];
    if C = '*' then Continue;
    Idx := Pos(C, C39_CHARS) - 1; // 0-based; -1 se ausente
    if Idx >= 0 then
    begin
      Chars[N] := Idx;
      Inc(N);
    end;
  end;
  Chars[N] := C39_STAR; Inc(N); // '*' de fim
  SetLength(Chars, N);

  // cada caractere = 9 elementos; entre caracteres 1 espaco estreito (1 elemento)
  SetLength(Result, N * 9 + (N - 1));
  K := 0;
  for I := 0 to High(Chars) do
  begin
    AppendWidths39(Result, K, C39_PAT[Chars[I]]);
    if I < High(Chars) then
    begin
      Result[K] := 1; // espaco estreito inter-caractere
      Inc(K);
    end;
  end;
  SetLength(Result, K);
end;

{ ===== API ===== }

function rhBarPatternModules(const P: TrhBarPattern): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(P) do
    Result := Result + P[I];
end;

function rhEncodeBarcode(Sym: TrhBarcodeSymbology; const Data: string): TrhBarPattern;
begin
  case Sym of
    rhbcCode39: Result := EncodeCode39(Data);
  else
    Result := EncodeCode128B(Data);
  end;
end;

end.
