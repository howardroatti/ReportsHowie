{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Pipeline de dados: percorre um TDataSet (generico) emitindo a banda de
///   dados por registro, com grupo (header/footer) e agregacoes. As agregacoes
///   (SUM/AVG/COUNT/MIN/MAX) sao calculadas re-varrendo o dataset com filtro de
///   grupo, salvando/restaurando a posicao via bookmark — sem acumuladores.
///
///   FASE 4: banda master + 1 nivel de grupo + agregacoes (grupo e geral) +
///   cabecalho/rodape de pagina + total de paginas (2 passagens). Master-detail
///   com dataset aninhado e multiplos niveis de grupo ficam para uma evolucao.
/// </summary>
unit rh.Data.Pipeline;

interface

uses
  rh.Report, rh.Render.Intf;

type
  TrhDataPipeline = class
  public
    /// <summary>Constroi o documento com dados. O chamador e dono do resultado.</summary>
    class function BuildDocument(Report: TrhReport): TrhRenderedDocument;
  end;

  /// <summary>Atalho: preview com dados ligados via TrhReport.SetDataSet.</summary>
  TrhReportDataHelper = class helper for TrhReport
  public
    procedure ShowDataPreview;
  end;

implementation

uses
  System.Classes, System.SysUtils, System.Variants, System.Generics.Collections, Data.DB,
  Vcl.Forms,
  rh.Types, rh.Model.Types, rh.Page, rh.Bands,
  rh.Expr, rh.Expr.Nodes, rh.Render.Engine, rh.Preview.Form;

type
  TrhReportContext = class(TInterfacedObject, IrhEvalContext)
  private
    FDataSet: TDataSet;
    FPageNo: Integer;
    FTotalPages: Integer;
    FGroupExprs: TList<string>;
    FGroupVals: TList<Variant>;
    function ToFloat(const V: Variant; out D: Double): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    // IrhEvalContext
    function GetValue(const Name: string; out Value: Variant): Boolean;
    function EvalAggregate(const FuncName: string; Arg: TrhExprNode): Variant;
    // configuracao pelo pipeline
    procedure ClearGroupFilters;
    procedure AddGroupFilter(const Expr: string; const Val: Variant);
    property DataSet: TDataSet read FDataSet write FDataSet;
    property PageNo: Integer read FPageNo write FPageNo;
    property TotalPages: Integer read FTotalPages write FTotalPages;
  end;

{ TrhReportContext }

constructor TrhReportContext.Create;
begin
  inherited Create;
  FGroupExprs := TList<string>.Create;
  FGroupVals := TList<Variant>.Create;
end;

destructor TrhReportContext.Destroy;
begin
  FGroupExprs.Free;
  FGroupVals.Free;
  inherited Destroy;
end;

procedure TrhReportContext.ClearGroupFilters;
begin
  FGroupExprs.Clear;
  FGroupVals.Clear;
end;

procedure TrhReportContext.AddGroupFilter(const Expr: string; const Val: Variant);
begin
  FGroupExprs.Add(Expr);
  FGroupVals.Add(Val);
end;

function TrhReportContext.ToFloat(const V: Variant; out D: Double): Boolean;
begin
  Result := False;
  if VarIsNull(V) or VarIsEmpty(V) then Exit;
  try
    D := V;
    Result := True;
  except
    Result := False;
  end;
end;

function TrhReportContext.GetValue(const Name: string; out Value: Variant): Boolean;
var
  Fld: TField;
begin
  if FDataSet <> nil then
  begin
    Fld := FDataSet.FindField(Name);
    if Fld <> nil then
    begin
      Value := Fld.Value;
      Exit(True);
    end;
  end;
  if SameText(Name, 'PAGE') then begin Value := FPageNo; Exit(True); end;
  if SameText(Name, 'TOTALPAGES') then begin Value := FTotalPages; Exit(True); end;
  if SameText(Name, 'DATE') or SameText(Name, 'TODAY') then begin Value := Date; Exit(True); end;
  if SameText(Name, 'TIME') then begin Value := Time; Exit(True); end;
  if SameText(Name, 'NOW') then begin Value := Now; Exit(True); end;
  Value := Null;
  Result := False;
end;

function TrhReportContext.EvalAggregate(const FuncName: string; Arg: TrhExprNode): Variant;
var
  BM: TBookmark;
  Cnt, I: Integer;
  Sum, D, MinV, MaxV: Double;
  HasMinMax, Match: Boolean;
  V, GV: Variant;
begin
  Result := Null;
  if (FDataSet = nil) or (Arg = nil) or (not FDataSet.Active) then Exit;

  Cnt := 0; Sum := 0; MinV := 0; MaxV := 0; HasMinMax := False;
  FDataSet.DisableControls;
  BM := FDataSet.Bookmark;
  try
    FDataSet.First;
    while not FDataSet.Eof do
    begin
      Match := True;
      for I := 0 to FGroupExprs.Count - 1 do
      begin
        GV := rhEvalExpr(FGroupExprs[I], Self);
        if not VarSameValue(GV, FGroupVals[I]) then
        begin
          Match := False;
          Break;
        end;
      end;
      if Match then
      begin
        V := Arg.Evaluate(Self);
        if not (VarIsNull(V) or VarIsEmpty(V)) then
        begin
          Inc(Cnt);
          if ToFloat(V, D) then
          begin
            Sum := Sum + D;
            if not HasMinMax then
            begin
              MinV := D; MaxV := D; HasMinMax := True;
            end
            else
            begin
              if D < MinV then MinV := D;
              if D > MaxV then MaxV := D;
            end;
          end;
        end;
      end;
      FDataSet.Next;
    end;
  finally
    if FDataSet.BookmarkValid(BM) then
      FDataSet.Bookmark := BM;
    FDataSet.EnableControls;
  end;

  if SameText(FuncName, 'COUNT') then Result := Cnt
  else if SameText(FuncName, 'SUM') then Result := Sum
  else if SameText(FuncName, 'AVG') then
  begin
    if Cnt > 0 then Result := Sum / Cnt else Result := Null;
  end
  else if SameText(FuncName, 'MIN') then
  begin
    if HasMinMax then Result := MinV else Result := Null;
  end
  else if SameText(FuncName, 'MAX') then
  begin
    if HasMinMax then Result := MaxV else Result := Null;
  end;
end;

// ---------------------------------------------------------------------------

type
  // Um nivel de agrupamento: par cabecalho/rodape identificado pela expressao.
  // A ordem dos cabecalhos na pagina define o aninhamento (topo = mais externo).
  TrhGroupLevel = record
    Expr: string;
    Header: TrhBand;
    Footer: TrhBand;
    PrevVal: Variant;
  end;

  TPipeline = class
  private
    FReport: TrhReport;
    FDoc: TrhRenderedDocument;
    FPage: TrhPage;
    FRP: TrhRenderedPage;
    FCurY: TrhUnit;
    FBodyBottom: TrhUnit;
    FCtx: IrhEvalContext;
    FCtxObj: TrhReportContext;
    FTitle, FPageHeader, FPageFooter, FSummary, FMaster: TrhBand;
    FLevels: TArray<TrhGroupLevel>; // grupos aninhados (indice 0 = mais externo)
    procedure Classify;
    procedure SetGroupFiltersUpTo(Level: Integer);
    procedure StartPage;
    procedure FinishPage;
    procedure EmitFlow(Band: TrhBand);
    procedure RunData(DS: TDataSet);
  public
    constructor Create(AReport: TrhReport);
    destructor Destroy; override;
    function Run(ATotalPages: Integer): TrhRenderedDocument;
  end;

constructor TPipeline.Create(AReport: TrhReport);
begin
  inherited Create;
  FReport := AReport;
  FCtxObj := TrhReportContext.Create;
  FCtx := FCtxObj; // interface gerencia o tempo de vida
end;

destructor TPipeline.Destroy;
begin
  FCtx := nil;
  inherited Destroy;
end;

procedure TPipeline.Classify;
var
  Band: TrhBand;
  I, N: Integer;
  Matched: Boolean;
begin
  FTitle := nil; FPageHeader := nil; FPageFooter := nil;
  FSummary := nil; FMaster := nil;
  SetLength(FLevels, 0);

  // 1a passada: cada GroupHeader (na ordem do topo p/ baixo) vira um nivel.
  for Band in FPage.Bands do
  begin
    if not Band.Visible then Continue;
    case Band.BandType of
      rhbtReportTitle: if FTitle = nil then FTitle := Band;
      rhbtPageHeader:  if FPageHeader = nil then FPageHeader := Band;
      rhbtPageFooter:  if FPageFooter = nil then FPageFooter := Band;
      rhbtMasterData:  if FMaster = nil then FMaster := Band;
      rhbtSummary:     if FSummary = nil then FSummary := Band;
      rhbtGroupHeader:
        begin
          N := Length(FLevels);
          SetLength(FLevels, N + 1);
          FLevels[N].Expr := Band.GroupExpression;
          FLevels[N].Header := Band;
          FLevels[N].Footer := nil;
          FLevels[N].PrevVal := Null;
        end;
    end;
  end;

  // 2a passada: casa cada GroupFooter ao nivel de mesma expressao; se nao houver
  // header correspondente (agrupamento so-rodape), cria um nivel novo.
  for Band in FPage.Bands do
  begin
    if (not Band.Visible) or (Band.BandType <> rhbtGroupFooter) then Continue;
    Matched := False;
    for I := 0 to High(FLevels) do
      if (FLevels[I].Footer = nil) and
         SameText(Trim(FLevels[I].Expr), Trim(Band.GroupExpression)) then
      begin
        FLevels[I].Footer := Band;
        Matched := True;
        Break;
      end;
    if not Matched then
    begin
      N := Length(FLevels);
      SetLength(FLevels, N + 1);
      FLevels[N].Expr := Band.GroupExpression;
      FLevels[N].Header := nil;
      FLevels[N].Footer := Band;
      FLevels[N].PrevVal := Null;
    end;
  end;
end;

// Ativa os filtros de agregacao para o escopo do nivel: todos os niveis
// externos ate 'Level' (inclusive), com os valores do grupo corrente. Assim um
// rodape de Categoria dentro de Cliente soma so as linhas daquele cliente+categoria.
procedure TPipeline.SetGroupFiltersUpTo(Level: Integer);
var
  I: Integer;
begin
  FCtxObj.ClearGroupFilters;
  for I := 0 to Level do
    FCtxObj.AddGroupFilter(FLevels[I].Expr, FLevels[I].PrevVal);
end;

procedure TPipeline.StartPage;
begin
  FRP := FDoc.AddPage(FPage.EffectiveWidth, FPage.EffectiveHeight);
  FCtxObj.PageNo := FDoc.PageCount;
  FCurY := FPage.MarginTop;
  if FPageHeader <> nil then
  begin
    TrhRenderEngine.EmitBand(FRP, FPageHeader, FPage.MarginLeft, FCurY, FCtx);
    FCurY := FCurY + FPageHeader.Height;
  end;
end;

procedure TPipeline.FinishPage;
begin
  if FPageFooter <> nil then
    TrhRenderEngine.EmitBand(FRP, FPageFooter, FPage.MarginLeft,
      FPage.MarginTop + FPage.ContentHeight - FPageFooter.Height, FCtx);
end;

procedure TPipeline.EmitFlow(Band: TrhBand);
begin
  if Band = nil then Exit;
  if (FCurY + Band.Height > FBodyBottom) and (FCurY > FPage.MarginTop) then
  begin
    FinishPage;
    StartPage;
  end;
  TrhRenderEngine.EmitBand(FRP, Band, FPage.MarginLeft, FCurY, FCtx);
  FCurY := FCurY + Band.Height;
end;

procedure TPipeline.RunData(DS: TDataSet);
var
  First, HasGroup: Boolean;
  nLevels, I, ChangeLevel: Integer;
  CurKeys: array of Variant;
begin
  nLevels := Length(FLevels);
  HasGroup := nLevels > 0;
  SetLength(CurKeys, nLevels);
  First := True;

  DS.DisableControls;
  try
    DS.First;
    while not DS.Eof do
    begin
      FCtxObj.DataSet := DS;

      if HasGroup then
      begin
        for I := 0 to nLevels - 1 do
          CurKeys[I] := rhEvalExpr(FLevels[I].Expr, FCtx);

        // nivel mais externo cuja chave mudou (nLevels = nenhum mudou)
        if First then
          ChangeLevel := 0
        else
        begin
          ChangeLevel := nLevels;
          for I := 0 to nLevels - 1 do
            if not VarSameValue(CurKeys[I], FLevels[I].PrevVal) then
            begin
              ChangeLevel := I;
              Break;
            end;
        end;

        if ChangeLevel < nLevels then
        begin
          // fecha rodapes dos grupos que terminaram: interno -> ChangeLevel,
          // lendo os rotulos na ULTIMA linha do grupo anterior.
          if not First then
          begin
            DS.Prior;
            for I := nLevels - 1 downto ChangeLevel do
              if FLevels[I].Footer <> nil then
              begin
                SetGroupFiltersUpTo(I);      // usa PrevVal (= grupo que terminou)
                FCtxObj.DataSet := DS;
                EmitFlow(FLevels[I].Footer);
              end;
            FCtxObj.ClearGroupFilters;
            DS.Next; // volta para a 1a linha do novo grupo
          end;

          // abre cabecalhos externo -> interno e atualiza os valores do grupo
          FCtxObj.DataSet := DS;
          for I := ChangeLevel to nLevels - 1 do
          begin
            FLevels[I].PrevVal := CurKeys[I];
            if FLevels[I].Header <> nil then
              EmitFlow(FLevels[I].Header);
          end;
        end;
      end;

      FCtxObj.DataSet := DS;
      EmitFlow(FMaster);
      DS.Next;
      First := False;
    end;

    // fim dos dados: fecha todos os rodapes do ultimo registro (interno -> externo)
    if (not First) and HasGroup then
    begin
      if DS.Eof then DS.Last;
      for I := nLevels - 1 downto 0 do
        if FLevels[I].Footer <> nil then
        begin
          SetGroupFiltersUpTo(I);
          FCtxObj.DataSet := DS;
          EmitFlow(FLevels[I].Footer);
        end;
      FCtxObj.ClearGroupFilters;
    end;
  finally
    DS.EnableControls;
  end;
end;

function TPipeline.Run(ATotalPages: Integer): TrhRenderedDocument;
var
  DSComp: TComponent;
  DS: TDataSet;
  FooterH: TrhUnit;
begin
  FDoc := TrhRenderedDocument.Create;
  FCtxObj.TotalPages := ATotalPages;

  if FReport.Pages.Count = 0 then Exit(FDoc);
  FPage := FReport.Pages[0];
  Classify;

  DS := nil;
  if FMaster <> nil then
  begin
    DSComp := FReport.FindDataSet(FMaster.DataSetName);
    if DSComp is TDataSet then DS := TDataSet(DSComp);
  end;

  if FPageFooter <> nil then FooterH := FPageFooter.Height else FooterH := 0;
  FBodyBottom := FPage.MarginTop + FPage.ContentHeight - FooterH;

  StartPage;
  if FTitle <> nil then
    EmitFlow(FTitle);

  if (DS <> nil) and DS.Active then
    RunData(DS)
  else if FMaster <> nil then
    EmitFlow(FMaster); // sem dados: emite a banda uma vez (template)

  if FSummary <> nil then
  begin
    FCtxObj.ClearGroupFilters; // escopo geral
    EmitFlow(FSummary);
  end;

  FinishPage;
  Result := FDoc;
end;

{ TrhDataPipeline }

class function TrhDataPipeline.BuildDocument(Report: TrhReport): TrhRenderedDocument;
var
  Pass1: TPipeline;
  Doc1: TrhRenderedDocument;
  Total: Integer;
  Pass2: TPipeline;
begin
  // Passagem 1: contar paginas (para TOTALPAGES)
  Pass1 := TPipeline.Create(Report);
  try
    Doc1 := Pass1.Run(0);
    Total := Doc1.PageCount;
    Doc1.Free;
  finally
    Pass1.Free;
  end;
  // Passagem 2: render final com TOTALPAGES conhecido
  Pass2 := TPipeline.Create(Report);
  try
    Result := Pass2.Run(Total);
  finally
    Pass2.Free;
  end;
end;

{ TrhReportDataHelper }

procedure TrhReportDataHelper.ShowDataPreview;
var
  Doc: TrhRenderedDocument;
  Frm: TrhPreviewForm;
begin
  Doc := TrhDataPipeline.BuildDocument(Self);
  Frm := TrhPreviewForm.CreateWithDocument(Application, Doc, True, Self.Title);
  try
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

end.
