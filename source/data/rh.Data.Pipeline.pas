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
    FTitle, FPageHeader, FPageFooter, FSummary, FMaster,
    FGroupHeader, FGroupFooter: TrhBand;
    FGroupExpr: string;
    procedure Classify;
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
begin
  FTitle := nil; FPageHeader := nil; FPageFooter := nil;
  FSummary := nil; FMaster := nil; FGroupHeader := nil; FGroupFooter := nil;
  for Band in FPage.Bands do
  begin
    if not Band.Visible then Continue;
    case Band.BandType of
      rhbtReportTitle: if FTitle = nil then FTitle := Band;
      rhbtPageHeader:  if FPageHeader = nil then FPageHeader := Band;
      rhbtPageFooter:  if FPageFooter = nil then FPageFooter := Band;
      rhbtGroupHeader: if FGroupHeader = nil then FGroupHeader := Band;
      rhbtGroupFooter: if FGroupFooter = nil then FGroupFooter := Band;
      rhbtMasterData:  if FMaster = nil then FMaster := Band;
      rhbtSummary:     if FSummary = nil then FSummary := Band;
    end;
  end;
  if FGroupHeader <> nil then
    FGroupExpr := FGroupHeader.GroupExpression
  else if FGroupFooter <> nil then
    FGroupExpr := FGroupFooter.GroupExpression
  else
    FGroupExpr := '';
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
  First: Boolean;
  CurGroup, PrevGroup: Variant;
  HasGroup: Boolean;
begin
  HasGroup := (FGroupHeader <> nil) or (FGroupFooter <> nil);
  First := True;
  PrevGroup := Null;

  DS.DisableControls;
  try
    DS.First;
    while not DS.Eof do
    begin
      FCtxObj.DataSet := DS;

      if HasGroup then
      begin
        CurGroup := rhEvalExpr(FGroupExpr, FCtx);
        if First or not VarSameValue(CurGroup, PrevGroup) then
        begin
          if not First and (FGroupFooter <> nil) then
          begin
            FCtxObj.ClearGroupFilters;
            FCtxObj.AddGroupFilter(FGroupExpr, PrevGroup);
            DS.Prior; // ultima linha do grupo que terminou (rotulos leem o grupo certo)
            EmitFlow(FGroupFooter);
            DS.Next;  // volta para a linha de quebra (1a do novo grupo)
            FCtxObj.ClearGroupFilters;
          end;
          PrevGroup := CurGroup;
          FCtxObj.DataSet := DS;
          if FGroupHeader <> nil then
            EmitFlow(FGroupHeader);
        end;
      end;

      FCtxObj.DataSet := DS;
      EmitFlow(FMaster);
      DS.Next;
      First := False;
    end;

    if (not First) and (FGroupFooter <> nil) then
    begin
      FCtxObj.ClearGroupFilters;
      FCtxObj.AddGroupFilter(FGroupExpr, PrevGroup);
      if DS.Eof then DS.Last; // ultima linha do ultimo grupo (rotulo correto)
      FCtxObj.DataSet := DS;
      EmitFlow(FGroupFooter);
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
