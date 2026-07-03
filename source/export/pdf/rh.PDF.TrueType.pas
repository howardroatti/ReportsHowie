{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Leitor minimo de fontes TrueType/OpenType (puro Pascal), usado pelo
///   exportador PDF para EMBUTIR a fonte e mapear Unicode -> glyph index (GID).
///
///   Le apenas o que o PDF precisa: head (unitsPerEm/bbox), hhea (asc/desc/
///   numHMetrics), maxp (numGlyphs), hmtx (larguras), cmap (Unicode->GID,
///   formatos 4 e 12) e post (italic angle / fixed pitch). NAO interpreta glyf/
///   loca: os bytes da fonte inteira sao embutidos como FontFile2.
///
///   Todas as metricas expostas ja vem escaladas para o espaco de glifo do PDF
///   (1000 unidades por em). GID e codepoint sao tratados no plano BMP (<= U+FFFF).
/// </summary>
unit rh.PDF.TrueType;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TrhTrueTypeFont = class
  private
    FData: TBytes;
    FBase: Cardinal;                        // inicio da offset table (0 p/ TTF puro)
    FTables: TDictionary<string, Cardinal>; // tag -> offset absoluto
    FTableLen: TDictionary<string, Cardinal>;
    FUnitsPerEm: Integer;
    FNumGlyphs: Integer;
    FNumHMetrics: Integer;
    FHmtxOff: Cardinal;
    FHasHmtx: Boolean;
    FCodeToGID: TDictionary<Word, Word>;
    FGIDToCode: TDictionary<Word, Word>;
    FAscent, FDescent, FCapHeight, FItalicAngle, FFlags: Integer;
    FBBox: array[0..3] of Integer;
    function U8(O: Cardinal): Byte;
    function U16(O: Cardinal): Word;
    function I16(O: Cardinal): SmallInt;
    function U32(O: Cardinal): Cardinal;
    function TagStr(O: Cardinal): string;
    function Scale(V: Integer): Integer;     // font units -> 1000 em
    procedure AddMap(Code, GID: Word);
    procedure ParseOffsetTable;
    procedure ParseHead;
    procedure ParseHhea;
    procedure ParseMaxp;
    procedure ParsePostOS2(AItalicRequested: Boolean);
    procedure ParseCmap;
    procedure ParseCmap4(Base: Cardinal);
    procedure ParseCmap12(Base: Cardinal);
    procedure ParseAll(AItalicRequested: Boolean);
  public
    /// <summary>Carrega a partir dos bytes de uma fonte TTF/OTF/TTC.</summary>
    constructor Create(const AData: TBytes; AItalicRequested: Boolean = False);
    /// <summary>Obtem os bytes da fonte instalada (via GDI GetFontData) e carrega.
    ///  Levanta excecao se a fonte nao for TrueType/OpenType.</summary>
    constructor CreateFromFont(const AName: string; ABold, AItalic: Boolean);
    destructor Destroy; override;
    /// <summary>Glyph index para o codepoint BMP; 0 (.notdef) se nao mapeado.</summary>
    function GlyphIndex(CP: Word): Word;
    /// <summary>Largura de avanco do glifo (espaco 1000/em).</summary>
    function AdvanceWidth1000(GID: Word): Integer;
    function BBox(I: Integer): Integer;
    property FontData: TBytes read FData;
    property UnitsPerEm: Integer read FUnitsPerEm;
    property NumGlyphs: Integer read FNumGlyphs;
    property Ascent: Integer read FAscent;
    property Descent: Integer read FDescent;
    property CapHeight: Integer read FCapHeight;
    property ItalicAngle: Integer read FItalicAngle;
    property Flags: Integer read FFlags;
    /// <summary>Mapa GID -> codepoint (para gerar o CMap ToUnicode).</summary>
    property GIDToCode: TDictionary<Word, Word> read FGIDToCode;
  end;

implementation

uses
  Winapi.Windows;

{ TrhTrueTypeFont }

constructor TrhTrueTypeFont.Create(const AData: TBytes; AItalicRequested: Boolean);
begin
  inherited Create;
  FData := AData;
  FTables := TDictionary<string, Cardinal>.Create;
  FTableLen := TDictionary<string, Cardinal>.Create;
  FCodeToGID := TDictionary<Word, Word>.Create;
  FGIDToCode := TDictionary<Word, Word>.Create;
  FUnitsPerEm := 1000;
  ParseAll(AItalicRequested);
end;

constructor TrhTrueTypeFont.CreateFromFont(const AName: string; ABold, AItalic: Boolean);
var
  DC: HDC;
  HF, Old: HFONT;
  Size: DWORD;
  Weight: Integer;
  Buf: TBytes;
begin
  if ABold then Weight := FW_BOLD else Weight := FW_NORMAL;
  HF := CreateFont(-1000, 0, 0, 0, Weight, Cardinal(Ord(AItalic)), 0, 0,
    DEFAULT_CHARSET, OUT_TT_ONLY_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
    DEFAULT_PITCH, PChar(AName));
  if HF = 0 then
    raise Exception.CreateFmt('ReportsHowie: nao criou HFONT para "%s".', [AName]);
  DC := CreateCompatibleDC(0);
  try
    Old := SelectObject(DC, HF);
    try
      Size := GetFontData(DC, 0, 0, nil, 0);
      if (Size = GDI_ERROR) or (Size = 0) then
        raise Exception.CreateFmt('ReportsHowie: "%s" nao e TrueType/OpenType.', [AName]);
      SetLength(Buf, Size);
      if GetFontData(DC, 0, 0, @Buf[0], Size) = GDI_ERROR then
        raise Exception.CreateFmt('ReportsHowie: GetFontData falhou para "%s".', [AName]);
    finally
      SelectObject(DC, Old);
    end;
  finally
    DeleteDC(DC);
    DeleteObject(HF);
  end;
  // reusa o caminho de bytes
  Create(Buf, AItalic);
end;

destructor TrhTrueTypeFont.Destroy;
begin
  FGIDToCode.Free;
  FCodeToGID.Free;
  FTableLen.Free;
  FTables.Free;
  inherited Destroy;
end;

// --- leitura big-endian com limites (fora do buffer => 0) ---

function TrhTrueTypeFont.U8(O: Cardinal): Byte;
begin
  if O < Cardinal(Length(FData)) then Result := FData[O] else Result := 0;
end;

function TrhTrueTypeFont.U16(O: Cardinal): Word;
begin
  Result := (Word(U8(O)) shl 8) or U8(O + 1);
end;

function TrhTrueTypeFont.I16(O: Cardinal): SmallInt;
begin
  Result := SmallInt(U16(O));
end;

function TrhTrueTypeFont.U32(O: Cardinal): Cardinal;
begin
  Result := (Cardinal(U16(O)) shl 16) or U16(O + 2);
end;

function TrhTrueTypeFont.TagStr(O: Cardinal): string;
begin
  Result := Chr(U8(O)) + Chr(U8(O + 1)) + Chr(U8(O + 2)) + Chr(U8(O + 3));
end;

function TrhTrueTypeFont.Scale(V: Integer): Integer;
begin
  if FUnitsPerEm <= 0 then Exit(V);
  Result := Round(V * 1000 / FUnitsPerEm);
end;

function TrhTrueTypeFont.BBox(I: Integer): Integer;
begin
  if (I >= 0) and (I <= 3) then Result := FBBox[I] else Result := 0;
end;

procedure TrhTrueTypeFont.AddMap(Code, GID: Word);
begin
  if GID = 0 then Exit;
  FCodeToGID.AddOrSetValue(Code, GID);
  if not FGIDToCode.ContainsKey(GID) then
    FGIDToCode.Add(GID, Code);
end;

procedure TrhTrueTypeFont.ParseOffsetTable;
var
  N, I: Integer;
  Rec: Cardinal;
  Tag: string;
begin
  FBase := 0;
  // TrueType Collection ('ttcf'): usa a offset table da 1a subfonte
  if (Length(FData) >= 4) and (U8(0) = $74) and (U8(1) = $74) and
     (U8(2) = $63) and (U8(3) = $66) then
    FBase := U32(12);

  N := U16(FBase + 4); // numTables
  for I := 0 to N - 1 do
  begin
    Rec := FBase + 12 + Cardinal(I) * 16;
    Tag := TagStr(Rec);
    FTables.AddOrSetValue(Tag, U32(Rec + 8));    // offset absoluto do arquivo
    FTableLen.AddOrSetValue(Tag, U32(Rec + 12));
  end;
end;

procedure TrhTrueTypeFont.ParseHead;
var
  O: Cardinal;
begin
  if not FTables.TryGetValue('head', O) then Exit;
  FUnitsPerEm := U16(O + 18);
  if FUnitsPerEm <= 0 then FUnitsPerEm := 1000;
  FBBox[0] := Scale(I16(O + 36)); // xMin
  FBBox[1] := Scale(I16(O + 38)); // yMin
  FBBox[2] := Scale(I16(O + 40)); // xMax
  FBBox[3] := Scale(I16(O + 42)); // yMax
end;

procedure TrhTrueTypeFont.ParseHhea;
var
  O: Cardinal;
begin
  if not FTables.TryGetValue('hhea', O) then Exit;
  FAscent := Scale(I16(O + 4));
  FDescent := Scale(I16(O + 6));
  FNumHMetrics := U16(O + 34);
end;

procedure TrhTrueTypeFont.ParseMaxp;
var
  O: Cardinal;
begin
  if FTables.TryGetValue('maxp', O) then
    FNumGlyphs := U16(O + 4);
end;

procedure TrhTrueTypeFont.ParsePostOS2(AItalicRequested: Boolean);
var
  O: Cardinal;
  Cap: Integer;
begin
  FItalicAngle := 0;
  FFlags := 32; // Nonsymbolic
  if FTables.TryGetValue('post', O) then
  begin
    FItalicAngle := I16(O + 4); // parte inteira do Fixed 16.16 do italicAngle
    if U32(O + 12) <> 0 then    // isFixedPitch
      FFlags := FFlags or 1;    // FixedPitch
  end;
  if AItalicRequested or (FItalicAngle <> 0) then
    FFlags := FFlags or 64;     // Italic

  // CapHeight: OS/2 v2+ (sCapHeight em O+88); senao aproxima pelo ascent
  FCapHeight := FAscent;
  if FTables.TryGetValue('OS/2', O) then
  begin
    if (U16(O) >= 2) and (FTableLen.ContainsKey('OS/2')) and
       (FTableLen['OS/2'] >= 90) then
    begin
      Cap := I16(O + 88);
      if Cap <> 0 then FCapHeight := Scale(Cap);
    end;
  end;
end;

function TrhTrueTypeFont.AdvanceWidth1000(GID: Word): Integer;
var
  Idx: Integer;
begin
  if (not FHasHmtx) or (FNumHMetrics <= 0) then Exit(Scale(FUnitsPerEm div 2));
  Idx := GID;
  if Idx >= FNumHMetrics then Idx := FNumHMetrics - 1;
  Result := Scale(U16(FHmtxOff + Cardinal(Idx) * 4)); // advanceWidth (u16)
end;

function TrhTrueTypeFont.GlyphIndex(CP: Word): Word;
begin
  if not FCodeToGID.TryGetValue(CP, Result) then
    Result := 0;
end;

procedure TrhTrueTypeFont.ParseCmap4(Base: Cardinal);
var
  SegX2, SegCount, S, C: Integer;
  EndOff, StartOff, DeltaOff, RangeOff, GAddr: Cardinal;
  EndC, StartC, RO: Word;
  Delta: SmallInt;
  G: Word;
begin
  SegX2 := U16(Base + 6);
  SegCount := SegX2 div 2;
  EndOff := Base + 14;
  StartOff := EndOff + Cardinal(SegX2) + 2; // + reservedPad(2)
  DeltaOff := StartOff + Cardinal(SegX2);
  RangeOff := DeltaOff + Cardinal(SegX2);
  for S := 0 to SegCount - 1 do
  begin
    EndC := U16(EndOff + Cardinal(S) * 2);
    StartC := U16(StartOff + Cardinal(S) * 2);
    Delta := I16(DeltaOff + Cardinal(S) * 2);
    RO := U16(RangeOff + Cardinal(S) * 2);
    if StartC > EndC then Continue;
    for C := StartC to EndC do
    begin
      if C = $FFFF then Break; // sentinela
      if RO = 0 then
        G := Word((C + Delta) and $FFFF)
      else
      begin
        GAddr := RangeOff + Cardinal(S) * 2 + RO + Cardinal(2 * (C - StartC));
        G := U16(GAddr);
        if G <> 0 then G := Word((G + Delta) and $FFFF);
      end;
      AddMap(Word(C), G);
    end;
  end;
end;

procedure TrhTrueTypeFont.ParseCmap12(Base: Cardinal);
var
  NGroups, I: Cardinal;
  GOff: Cardinal;
  SC, EC, SG, CP: Cardinal;
begin
  NGroups := U32(Base + 12);
  GOff := Base + 16;
  for I := 0 to NGroups - 1 do
  begin
    SC := U32(GOff);
    EC := U32(GOff + 4);
    SG := U32(GOff + 8);
    Inc(GOff, 12);
    if SC > $FFFF then Continue;      // fora do BMP (nao suportado nesta versao)
    if EC > $FFFF then EC := $FFFF;
    CP := SC;
    while CP <= EC do
    begin
      AddMap(Word(CP), Word(SG + (CP - SC)));
      Inc(CP);
    end;
  end;
end;

procedure TrhTrueTypeFont.ParseCmap;
var
  CmapOff, SubOff, Best: Cardinal;
  NSub, I, Score, BestScore: Integer;
  Plat, Enc: Word;
  Fmt: Word;
begin
  if not FTables.TryGetValue('cmap', CmapOff) then Exit;
  NSub := U16(CmapOff + 2);
  Best := 0; BestScore := -1;
  for I := 0 to NSub - 1 do
  begin
    Plat := U16(CmapOff + 4 + Cardinal(I) * 8);
    Enc := U16(CmapOff + 4 + Cardinal(I) * 8 + 2);
    SubOff := U32(CmapOff + 4 + Cardinal(I) * 8 + 4);
    Score := -1;
    if (Plat = 3) and (Enc = 10) then Score := 5       // Windows UCS-4 (fmt 12)
    else if (Plat = 3) and (Enc = 1) then Score := 4    // Windows BMP (fmt 4)
    else if (Plat = 0) then Score := 3;                 // Unicode
    if Score > BestScore then
    begin
      BestScore := Score;
      Best := CmapOff + SubOff;
    end;
  end;
  if BestScore < 0 then Exit;
  Fmt := U16(Best);
  if Fmt = 4 then ParseCmap4(Best)
  else if Fmt = 12 then ParseCmap12(Best);
end;

procedure TrhTrueTypeFont.ParseAll(AItalicRequested: Boolean);
begin
  ParseOffsetTable;
  ParseHead;
  ParseHhea;
  ParseMaxp;
  FHasHmtx := FTables.TryGetValue('hmtx', FHmtxOff);
  ParsePostOS2(AItalicRequested);
  ParseCmap;
end;

end.
