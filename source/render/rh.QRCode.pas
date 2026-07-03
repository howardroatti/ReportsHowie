{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Gerador de QR Code em PURO PASCAL (zero dependencias). Modo BYTE (UTF-8),
///   nivel de correcao M, versoes 1..10 (auto-seleciona a menor que couber) e
///   escolha automatica da mascara pela pontuacao de penalidade padrao.
///
///   Componentes: codificacao byte + Reed-Solomon em GF(256) + posicionamento
///   na matriz (finders/timing/alinhamento/formato/versao) + 8 mascaras. O
///   algoritmo foi validado modulo-a-modulo contra a biblioteca de referencia
///   'segno' e por leitura com um scanner real (todas as versoes 1..10).
///
///   O motor de render expande os modulos escuros em retangulos (rhdkRect),
///   entao o QR aparece em preview e em todos os exports, como o codigo 1D.
/// </summary>
unit rh.QRCode;

interface

type
  /// <summary>Matriz quadrada de modulos. Size=0 => vazio ou grande demais.</summary>
  TrhQRMatrix = record
    Size: Integer;
    Modules: TArray<Boolean>;   // row-major: indice R*Size+C; True = escuro
    function IsDark(R, C: Integer): Boolean;
  end;

/// <summary>Codifica S (UTF-8) num QR nivel M. Size=0 se vazio ou > ~213 bytes.</summary>
function rhEncodeQR(const S: string): TrhQRMatrix;

implementation

uses
  System.SysUtils, System.Math;

var
  GEXP: array[0..511] of Integer;
  GLOG: array[0..255] of Integer;

procedure InitGF;
var
  I, X: Integer;
begin
  X := 1;
  for I := 0 to 254 do
  begin
    GEXP[I] := X;
    GLOG[X] := I;
    X := X shl 1;
    if (X and $100) <> 0 then X := X xor $11D;
  end;
  for I := 255 to 511 do
    GEXP[I] := GEXP[I - 255];
end;

function GMul(A, B: Integer): Integer;
begin
  if (A = 0) or (B = 0) then Exit(0);
  Result := GEXP[GLOG[A] + GLOG[B]];
end;

function RSGen(Deg: Integer): TArray<Integer>;
var
  I, J: Integer;
  G, NG: TArray<Integer>;
begin
  SetLength(G, 1); G[0] := 1;
  for I := 0 to Deg - 1 do
  begin
    SetLength(NG, Length(G) + 1);
    for J := 0 to High(NG) do NG[J] := 0;
    for J := 0 to High(G) do
    begin
      NG[J] := NG[J] xor G[J];
      NG[J + 1] := NG[J + 1] xor GMul(G[J], GEXP[I]);
    end;
    G := Copy(NG);
  end;
  Result := G;
end;

function RSEc(const Data: TArray<Byte>; EcLen: Integer): TArray<Byte>;
var
  G: TArray<Integer>;
  Res: TArray<Integer>;
  I, J, F: Integer;
begin
  G := RSGen(EcLen);
  SetLength(Res, EcLen);
  for I := 0 to EcLen - 1 do Res[I] := 0;
  for I := 0 to High(Data) do
  begin
    F := Data[I] xor Res[0];
    for J := 0 to EcLen - 2 do Res[J] := Res[J + 1];
    Res[EcLen - 1] := 0;
    for J := 0 to EcLen - 1 do
      Res[J] := Res[J] xor GMul(G[J + 1], F);
  end;
  SetLength(Result, EcLen);
  for I := 0 to EcLen - 1 do Result[I] := Byte(Res[I]);
end;

const
  // nivel M, v1..10: correcao por bloco
  QR_ECPB: array[1..10] of Integer = (10, 16, 26, 18, 24, 16, 18, 22, 22, 26);
  // blocos: (g1_blocos, g1_dados, g2_blocos, g2_dados)
  QR_BLK: array[1..10, 0..3] of Integer = (
    (1, 16, 0, 0), (1, 28, 0, 0), (1, 44, 0, 0), (2, 32, 0, 0), (2, 43, 0, 0),
    (4, 27, 0, 0), (4, 31, 0, 0), (2, 38, 2, 39), (3, 36, 2, 37), (4, 43, 1, 44));
  // centros dos padroes de alinhamento (-1 = ausente)
  QR_ALIGN: array[1..10, 0..2] of Integer = (
    (-1, -1, -1), (6, 18, -1), (6, 22, -1), (6, 26, -1), (6, 30, -1), (6, 34, -1),
    (6, 22, 38), (6, 24, 42), (6, 26, 46), (6, 28, 50));

function DataCodewords(V: Integer): Integer;
begin
  Result := QR_BLK[V, 0] * QR_BLK[V, 1] + QR_BLK[V, 2] * QR_BLK[V, 3];
end;

function CountBits(V: Integer): Integer;
begin
  if V <= 9 then Result := 8 else Result := 16;
end;

function DataCapBytes(V: Integer): Integer;
begin
  Result := (DataCodewords(V) * 8 - 4 - CountBits(V)) div 8;
end;

// Codifica dados -> codewords finais (dados intercalados + EC intercalado).
function EncodeCodewords(const Data: TBytes; V: Integer): TArray<Byte>;
var
  DC, TotalBits, Pos, Term, PadIdx, I, J, K, MaxD, NBlocks: Integer;
  Bits: TArray<Byte>;
  CW: TArray<Byte>;
  Blocks: array of TArray<Byte>;
  ECBlocks: array of TArray<Byte>;
  BlkData: array[0..3] of Integer;
  Pads: array[0..1] of Integer;
  Idx, OutPos, B: Integer;

  procedure Push(Val, N: Integer);
  var
    Bi: Integer;
  begin
    for Bi := N - 1 downto 0 do
    begin
      Bits[Pos] := (Val shr Bi) and 1;
      Inc(Pos);
    end;
  end;

begin
  DC := DataCodewords(V);
  TotalBits := DC * 8;
  SetLength(Bits, TotalBits);
  Pos := 0;
  Push($4, 4);                       // indicador de modo byte
  Push(Length(Data), CountBits(V));  // contagem de caracteres
  for I := 0 to High(Data) do Push(Data[I], 8);
  // terminador
  Term := Min(4, TotalBits - Pos);
  for I := 1 to Term do begin Bits[Pos] := 0; Inc(Pos); end;
  // alinha em byte
  while (Pos mod 8) <> 0 do begin Bits[Pos] := 0; Inc(Pos); end;
  // bytes de preenchimento
  Pads[0] := $EC; Pads[1] := $11; PadIdx := 0;
  while Pos < TotalBits do
  begin
    Push(Pads[PadIdx], 8);
    PadIdx := 1 - PadIdx;
  end;
  // empacota em codewords
  SetLength(CW, DC);
  for I := 0 to DC - 1 do
  begin
    B := 0;
    for J := 0 to 7 do B := (B shl 1) or Bits[I * 8 + J];
    CW[I] := Byte(B);
  end;
  // divide em blocos (g1 depois g2)
  NBlocks := QR_BLK[V, 0] + QR_BLK[V, 2];
  SetLength(Blocks, NBlocks);
  SetLength(ECBlocks, NBlocks);
  BlkData[0] := QR_BLK[V, 0]; BlkData[1] := QR_BLK[V, 1];
  BlkData[2] := QR_BLK[V, 2]; BlkData[3] := QR_BLK[V, 3];
  Idx := 0; K := 0;
  for I := 0 to 1 do
    for J := 1 to BlkData[I * 2] do
    begin
      SetLength(Blocks[K], BlkData[I * 2 + 1]);
      Move(CW[Idx], Blocks[K][0], BlkData[I * 2 + 1]);
      Inc(Idx, BlkData[I * 2 + 1]);
      ECBlocks[K] := RSEc(Blocks[K], QR_ECPB[V]);
      Inc(K);
    end;
  // intercala dados e depois EC
  MaxD := 0;
  for I := 0 to NBlocks - 1 do MaxD := Max(MaxD, Length(Blocks[I]));
  SetLength(Result, DC + QR_ECPB[V] * NBlocks);
  OutPos := 0;
  for I := 0 to MaxD - 1 do
    for J := 0 to NBlocks - 1 do
      if I < Length(Blocks[J]) then
      begin
        Result[OutPos] := Blocks[J][I]; Inc(OutPos);
      end;
  for I := 0 to QR_ECPB[V] - 1 do
    for J := 0 to NBlocks - 1 do
    begin
      Result[OutPos] := ECBlocks[J][I]; Inc(OutPos);
    end;
end;

function MaskBit(Mask, R, C: Integer): Boolean;
begin
  case Mask of
    0: Result := (R + C) mod 2 = 0;
    1: Result := R mod 2 = 0;
    2: Result := C mod 3 = 0;
    3: Result := (R + C) mod 3 = 0;
    4: Result := (R div 2 + C div 3) mod 2 = 0;
    5: Result := (R * C) mod 2 + (R * C) mod 3 = 0;
    6: Result := ((R * C) mod 2 + (R * C) mod 3) mod 2 = 0;
  else
    Result := ((R + C) mod 2 + (R * C) mod 3) mod 2 = 0;
  end;
end;

type
  TIntGrid = TArray<TArray<Integer>>;
  TBoolGrid = TArray<TArray<Boolean>>;

// Constroi a matriz completa (modulos 0/1) para uma versao e mascara.
function BuildMatrix(const Data: TBytes; V, Mask: Integer): TIntGrid;
var
  Size, I, J, R, C, Last, DR, DC2, RR, CC, Col, Row, Bi: Integer;
  M: TIntGrid;
  Fn: TBoolGrid;
  AC: array[0..2] of Integer;
  Stream: TArray<Byte>;
  BitLen, Fmt, Rem, Fmt15, VInfo, Bit: Integer;
  Up, OnMod: Boolean;

  procedure Finder(Fr, Fc: Integer);
  var
    Dr, Dc: Integer;
    RR2, CC2: Integer;
    On2: Boolean;
  begin
    for Dr := -1 to 7 do
      for Dc := -1 to 7 do
      begin
        RR2 := Fr + Dr; CC2 := Fc + Dc;
        if (RR2 >= 0) and (RR2 < Size) and (CC2 >= 0) and (CC2 < Size) then
        begin
          On2 := (Dr >= 0) and (Dr <= 6) and (Dc >= 0) and (Dc <= 6) and
                 ((Dr = 0) or (Dr = 6) or (Dc = 0) or (Dc = 6) or
                  ((Dr >= 2) and (Dr <= 4) and (Dc >= 2) and (Dc <= 4)));
          if On2 then M[RR2][CC2] := 1 else M[RR2][CC2] := 0;
          Fn[RR2][CC2] := True;
        end;
      end;
  end;

  function BitOf(Val, Ix: Integer): Integer;
  begin
    Result := (Val shr Ix) and 1;
  end;

begin
  Size := 17 + 4 * V;
  SetLength(M, Size, Size);
  SetLength(Fn, Size, Size);
  for I := 0 to Size - 1 do
    for J := 0 to Size - 1 do begin M[I][J] := -1; Fn[I][J] := False; end;

  Finder(0, 0); Finder(0, Size - 7); Finder(Size - 7, 0);
  // timing
  for I := 0 to Size - 1 do
  begin
    if M[6][I] = -1 then
    begin
      if I mod 2 = 0 then M[6][I] := 1 else M[6][I] := 0;
      Fn[6][I] := True;
    end;
    if M[I][6] = -1 then
    begin
      if I mod 2 = 0 then M[I][6] := 1 else M[I][6] := 0;
      Fn[I][6] := True;
    end;
  end;
  // alinhamento
  AC[0] := QR_ALIGN[V, 0]; AC[1] := QR_ALIGN[V, 1]; AC[2] := QR_ALIGN[V, 2];
  Last := 0;
  for I := 0 to 2 do if AC[I] >= 0 then Last := AC[I];
  for I := 0 to 2 do
    if AC[I] >= 0 then
      for J := 0 to 2 do
        if AC[J] >= 0 then
        begin
          R := AC[I]; C := AC[J];
          // exclui apenas os 3 centros sobre os finders
          if ((R = 6) and (C = 6)) or ((R = 6) and (C = Last)) or
             ((R = Last) and (C = 6)) then Continue;
          for DR := -2 to 2 do
            for DC2 := -2 to 2 do
            begin
              OnMod := (DR = -2) or (DR = 2) or (DC2 = -2) or (DC2 = 2) or
                       ((DR = 0) and (DC2 = 0));
              if OnMod then M[R + DR][C + DC2] := 1 else M[R + DR][C + DC2] := 0;
              Fn[R + DR][C + DC2] := True;
            end;
        end;
  // modulo escuro
  M[Size - 8][8] := 1; Fn[Size - 8][8] := True;
  // reserva formato
  for I := 0 to 8 do
  begin
    if not Fn[8][I] then begin Fn[8][I] := True; M[8][I] := 0; end;
    if not Fn[I][8] then begin Fn[I][8] := True; M[I][8] := 0; end;
  end;
  for I := 0 to 7 do
  begin
    if not Fn[Size - 1 - I][8] then begin Fn[Size - 1 - I][8] := True; M[Size - 1 - I][8] := 0; end;
    if not Fn[8][Size - 1 - I] then begin Fn[8][Size - 1 - I] := True; M[8][Size - 1 - I] := 0; end;
  end;
  // reserva versao (v>=7)
  if V >= 7 then
    for I := 0 to 5 do
      for J := 0 to 2 do
      begin
        Fn[I][Size - 11 + J] := True; M[I][Size - 11 + J] := 0;
        Fn[Size - 11 + J][I] := True; M[Size - 11 + J][I] := 0;
      end;

  // fluxo de bits (codewords -> bits, MSB primeiro)
  Stream := EncodeCodewords(Data, V);
  BitLen := Length(Stream) * 8;
  // posiciona dados em ziguezague
  Bi := 0; Col := Size - 1; Up := True;
  while Col > 0 do
  begin
    if Col = 6 then Dec(Col);
    for Row := 0 to Size - 1 do
    begin
      if Up then RR := Size - 1 - Row else RR := Row;
      for J := 0 to 1 do
      begin
        CC := Col - J;
        if not Fn[RR][CC] then
        begin
          if Bi < BitLen then
            Bit := (Stream[Bi shr 3] shr (7 - (Bi and 7))) and 1
          else
            Bit := 0;
          Inc(Bi);
          if MaskBit(Mask, RR, CC) then Bit := Bit xor 1;
          M[RR][CC] := Bit;
        end;
      end;
    end;
    Up := not Up;
    Dec(Col, 2);
  end;

  // info de formato (nivel M = 00), 15 bits, MSB primeiro
  Fmt := (0 shl 3) or Mask;
  Rem := Fmt shl 10;
  for I := 14 downto 10 do
    if (Rem and (1 shl I)) <> 0 then Rem := Rem xor ($537 shl (I - 10));
  Fmt15 := ((Fmt shl 10) or Rem) xor $5412;
  // copia 1
  for I := 0 to 5 do M[8][I] := BitOf(Fmt15, 14 - I);
  M[8][7] := BitOf(Fmt15, 14 - 6);
  M[8][8] := BitOf(Fmt15, 14 - 7);
  M[7][8] := BitOf(Fmt15, 14 - 8);
  for I := 9 to 14 do M[14 - I][8] := BitOf(Fmt15, 14 - I);
  // copia 2
  for I := 0 to 6 do M[Size - 1 - I][8] := BitOf(Fmt15, 14 - I);
  M[8][Size - 8] := BitOf(Fmt15, 14 - 7);
  for I := 8 to 14 do M[8][Size - 15 + I] := BitOf(Fmt15, 14 - I);

  // info de versao (v>=7), 18 bits, LSB primeiro
  if V >= 7 then
  begin
    Rem := V shl 12;
    for I := 17 downto 12 do
      if (Rem and (1 shl I)) <> 0 then Rem := Rem xor ($1F25 shl (I - 12));
    VInfo := (V shl 12) or Rem;
    for I := 0 to 17 do
    begin
      Bit := BitOf(VInfo, I);
      R := I div 3; C := I mod 3;
      M[R][Size - 11 + C] := Bit;
      M[Size - 11 + C][R] := Bit;
    end;
  end;

  Result := M;
end;

function Penalty(const M: TIntGrid): Integer;
var
  Size, R, C, I, Run, P, Dark, Total, Ratio: Integer;

  function LineVal(IsRow: Boolean; K, Idx: Integer): Integer;
  begin
    if IsRow then Result := M[K][Idx] else Result := M[Idx][K];
  end;

  procedure ScanRuns(IsRow: Boolean);
  var
    K, Idx, Rn, Prev: Integer;
  begin
    for K := 0 to Size - 1 do
    begin
      Rn := 1; Prev := LineVal(IsRow, K, 0);
      for Idx := 1 to Size - 1 do
      begin
        if LineVal(IsRow, K, Idx) = Prev then Inc(Rn)
        else
        begin
          if Rn >= 5 then P := P + 3 + (Rn - 5);
          Rn := 1; Prev := LineVal(IsRow, K, Idx);
        end;
      end;
      if Rn >= 5 then P := P + 3 + (Rn - 5);
    end;
  end;

  function MatchPat(IsRow: Boolean; K, Idx: Integer; const Pat: array of Integer): Boolean;
  var
    T: Integer;
  begin
    for T := 0 to 10 do
      if LineVal(IsRow, K, Idx + T) <> Pat[T] then Exit(False);
    Result := True;
  end;

const
  PAT1: array[0..10] of Integer = (1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0);
  PAT2: array[0..10] of Integer = (0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1);
begin
  Size := Length(M);
  P := 0;
  // regra 1
  ScanRuns(True); ScanRuns(False);
  // regra 2
  for R := 0 to Size - 2 do
    for C := 0 to Size - 2 do
      if (M[R][C] = M[R][C + 1]) and (M[R][C] = M[R + 1][C]) and
         (M[R][C] = M[R + 1][C + 1]) then P := P + 3;
  // regra 3
  for R := 0 to Size - 1 do
    for C := 0 to Size - 11 do
    begin
      if MatchPat(True, R, C, PAT1) or MatchPat(True, R, C, PAT2) then P := P + 40;
      if MatchPat(False, R, C, PAT1) or MatchPat(False, R, C, PAT2) then P := P + 40;
    end;
  // regra 4
  Dark := 0; Total := Size * Size;
  for R := 0 to Size - 1 do
    for C := 0 to Size - 1 do Dark := Dark + M[R][C];
  Ratio := Dark * 100 div Total;
  P := P + 10 * (Abs(Ratio - 50) div 5);
  Result := P;
end;

function rhEncodeQR(const S: string): TrhQRMatrix;
var
  Data: TBytes;
  V, BestMask, BestPen, Mask, Pen, I, J, Size: Integer;
  M: TIntGrid;
begin
  Result.Size := 0;
  Result.Modules := nil;
  if S = '' then Exit;
  Data := TEncoding.UTF8.GetBytes(S);
  V := -1;
  for I := 1 to 10 do
    if Length(Data) <= DataCapBytes(I) then begin V := I; Break; end;
  if V < 0 then Exit; // grande demais para v1..10

  BestMask := 0; BestPen := MaxInt;
  for Mask := 0 to 7 do
  begin
    Pen := Penalty(BuildMatrix(Data, V, Mask));
    if Pen < BestPen then begin BestPen := Pen; BestMask := Mask; end;
  end;
  M := BuildMatrix(Data, V, BestMask);
  Size := 17 + 4 * V;
  Result.Size := Size;
  SetLength(Result.Modules, Size * Size);
  for I := 0 to Size - 1 do
    for J := 0 to Size - 1 do
      Result.Modules[I * Size + J] := M[I][J] = 1;
end;

{ TrhQRMatrix }

function TrhQRMatrix.IsDark(R, C: Integer): Boolean;
begin
  Result := (R >= 0) and (R < Size) and (C >= 0) and (C < Size) and
            Modules[R * Size + C];
end;

initialization
  InitGF;

end.
