{******************************************************************************}
{  ReportsHowie - rhtool CLI (Fase 12.a)                                       }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{                                                                              }
{  Ferramenta de linha de comando para validar, inspecionar e exportar         }
{  templates .rhr sem abrir o IDE. Base "headless" para o servidor MCP (12.b). }
{                                                                              }
{  Community NAO compila por linha de comando: abra este .dpr no IDE e de       }
{  Build (o IDE gera o .dproj). Linka os fontes rh.* estaticamente.            }
{******************************************************************************}
program rhtool;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  System.IOUtils,
  System.JSON,
  Vcl.Graphics,
  Data.DB,
  Datasnap.DBClient,
  MidasLib,
  rh.Types in '..\..\source\core\rh.Types.pas',
  rh.Consts in '..\..\source\core\rh.Consts.pas',
  rh.Classes in '..\..\source\core\rh.Classes.pas',
  rh.Model.Types in '..\..\source\model\rh.Model.Types.pas',
  rh.Serialization in '..\..\source\model\rh.Serialization.pas',
  rh.Objects in '..\..\source\model\rh.Objects.pas',
  rh.Bands in '..\..\source\model\rh.Bands.pas',
  rh.Page in '..\..\source\model\rh.Page.pas',
  rh.Report in '..\..\source\model\rh.Report.pas',
  rh.Expr.Lexer in '..\..\source\expr\rh.Expr.Lexer.pas',
  rh.Expr.Nodes in '..\..\source\expr\rh.Expr.Nodes.pas',
  rh.Expr.Functions in '..\..\source\expr\rh.Expr.Functions.pas',
  rh.Expr.Parser in '..\..\source\expr\rh.Expr.Parser.pas',
  rh.Expr in '..\..\source\expr\rh.Expr.pas',
  rh.Render.Intf in '..\..\source\render\rh.Render.Intf.pas',
  rh.Render.Engine in '..\..\source\render\rh.Render.Engine.pas',
  rh.Render.VCLCanvas in '..\..\source\render\rh.Render.VCLCanvas.pas',
  rh.Preview.Form in '..\..\source\preview\rh.Preview.Form.pas',
  rh.Data.Pipeline in '..\..\source\data\rh.Data.Pipeline.pas',
  rh.Export.HTML in '..\..\source\export\html\rh.Export.HTML.pas',
  rh.Export.PDF in '..\..\source\export\pdf\rh.Export.PDF.pas',
  rh.OOXML.Zip in '..\..\source\export\ooxml\rh.OOXML.Zip.pas',
  rh.Export.XLSX in '..\..\source\export\ooxml\rh.Export.XLSX.pas',
  rh.Export.DOCX in '..\..\source\export\ooxml\rh.Export.DOCX.pas';

procedure PrintUsage;
begin
  Writeln('rhtool - ReportsHowie CLI (', TrhReport.LibraryVersion, ')');
  Writeln('');
  Writeln('Uso:');
  Writeln('  rhtool validate <arquivo.rhr>              valida o template (parse do modelo)');
  Writeln('  rhtool info <arquivo.rhr>                  mostra a estrutura (paginas/bandas/objetos)');
  Writeln('  rhtool export <arquivo.rhr> <saida.ext> [--data <dados.json>]');
  Writeln('                                            exporta (.pdf/.html/.xlsx/.docx)');
  Writeln('  rhtool version');
  Writeln('  rhtool help');
  Writeln('');
  Writeln('Dados (--data): JSON no formato { "NomeDataset": [ {campo: valor, ...}, ... ] }.');
  Writeln('      O nome do dataset casa com o dataSetName das bandas. Sem --data, as');
  Writeln('      bandas de dados nao produzem linhas (bandas estaticas saem normal).');
end;

function LoadReport(const FileName: string): TrhReport;
begin
  if not FileExists(FileName) then
    raise Exception.CreateFmt('arquivo nao encontrado: %s', [FileName]);
  Result := TrhReport.Create(nil);
  try
    Result.LoadFromFile(FileName);
  except
    Result.Free;
    raise;
  end;
end;

procedure CmdValidate(const FileName: string);
var
  R: TrhReport;
begin
  R := LoadReport(FileName);
  try
    Writeln(Format('OK: "%s" valido (%d pagina(s)).', [FileName, R.Pages.Count]));
  finally
    R.Free;
  end;
end;

procedure CmdInfo(const FileName: string);
var
  R: TrhReport;
  Page: TrhPage;
  Band: TrhBand;
  Pi: Integer;
begin
  R := LoadReport(FileName);
  try
    Writeln('Arquivo : ', FileName);
    Writeln('Titulo  : ', R.Title);
    Writeln('Autor   : ', R.Author);
    Writeln('Paginas : ', R.Pages.Count);
    for Pi := 0 to R.Pages.Count - 1 do
    begin
      Page := R.Pages[Pi];
      Writeln(Format('  Pagina %d: %d x %d (0,1mm), %d banda(s)',
        [Pi + 1, Page.PaperWidth, Page.PaperHeight, Page.Bands.Count]));
      for Band in Page.Bands do
        Writeln(Format('    [%-11s] altura=%-4d objetos=%-2d dataset="%s" grupo="%s"',
          [BandTypeToStr(Band.BandType), Band.Height, Band.Objects.Count,
           Band.DataSetName, Band.GroupExpression]));
    end;
  finally
    R.Free;
  end;
end;

/// <summary>Cria datasets em memoria (TClientDataSet) a partir de um JSON
///  { "NomeDataset": [ {campo: valor, ...}, ... ], ... } e os liga ao relatorio
///  via SetDataSet, para que as bandas de dados produzam linhas. Retorna quantos
///  datasets foram carregados. Os TClientDataSet pertencem a Owner (liberados junto).</summary>
function BuildDataSets(R: TrhReport; const DataFile: string; Owner: TComponent): Integer;
var
  JRoot: TJSONValue;
  Root: TJSONObject;
  DsPair, VPair: TJSONPair;
  Arr: TJSONArray;
  Rec: TJSONObject;
  Cds: TClientDataSet;
  I, K, MaxLen: Integer;
  Names: array of string;
  Types: array of TFieldType;
  Sizes: array of Integer;
  JV: TJSONValue;
  SawStr, SawNum, SawBool: Boolean;

  function IndexOfName(const AName: string): Integer;
  var
    N: Integer;
  begin
    for N := 0 to High(Names) do
      if SameText(Names[N], AName) then
        Exit(N);
    Result := -1;
  end;

begin
  Result := 0;
  if not FileExists(DataFile) then
    raise Exception.CreateFmt('arquivo de dados nao encontrado: %s', [DataFile]);
  JRoot := TJSONObject.ParseJSONValue(TFile.ReadAllText(DataFile, TEncoding.UTF8));
  if not (JRoot is TJSONObject) then
  begin
    JRoot.Free;
    raise Exception.Create(
      'JSON de dados invalido: esperado um objeto { "Dataset": [registros] }.');
  end;
  Root := TJSONObject(JRoot);
  try
    for DsPair in Root do
    begin
      if not (DsPair.JsonValue is TJSONArray) then
        Continue;
      Arr := TJSONArray(DsPair.JsonValue);

      // 1) descobre os campos (uniao das chaves, preservando a ordem)
      SetLength(Names, 0);
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
          for VPair in TJSONObject(Arr.Items[I]) do
            if IndexOfName(VPair.JsonString.Value) < 0 then
            begin
              SetLength(Names, Length(Names) + 1);
              Names[High(Names)] := VPair.JsonString.Value;
            end;
      SetLength(Types, Length(Names));
      SetLength(Sizes, Length(Names));

      // 2) infere o tipo de cada campo (numero->float, bool->boolean, resto->string)
      for K := 0 to High(Names) do
      begin
        SawStr := False; SawNum := False; SawBool := False; MaxLen := 0;
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            JV := TJSONObject(Arr.Items[I]).GetValue(Names[K]);
            if (JV = nil) or (JV is TJSONNull) then
              Continue;
            if JV is TJSONNumber then
              SawNum := True
            else if JV is TJSONBool then
              SawBool := True
            else
            begin
              SawStr := True;
              if JV is TJSONString then
                if Length(TJSONString(JV).Value) > MaxLen then
                  MaxLen := Length(TJSONString(JV).Value);
            end;
          end;
        if SawStr then
        begin
          Types[K] := ftWideString;
          if MaxLen < 20 then MaxLen := 20;
          if MaxLen > 8192 then MaxLen := 8192;
          Sizes[K] := MaxLen;
        end
        else if SawBool and not SawNum then
        begin
          Types[K] := ftBoolean; Sizes[K] := 0;
        end
        else if SawNum then
        begin
          Types[K] := ftFloat; Sizes[K] := 0;
        end
        else
        begin
          Types[K] := ftWideString; Sizes[K] := 20;
        end;
      end;

      // 3) cria o dataset em memoria e popula
      Cds := TClientDataSet.Create(Owner);
      for K := 0 to High(Names) do
        Cds.FieldDefs.Add(Names[K], Types[K], Sizes[K]);
      Cds.CreateDataSet;

      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Rec := TJSONObject(Arr.Items[I]);
          Cds.Append;
          for K := 0 to High(Names) do
          begin
            JV := Rec.GetValue(Names[K]);
            if (JV = nil) or (JV is TJSONNull) then
              Continue;
            case Types[K] of
              ftBoolean:
                if JV is TJSONBool then
                  Cds.Fields[K].AsBoolean := TJSONBool(JV).AsBoolean;
              ftFloat:
                if JV is TJSONNumber then
                  Cds.Fields[K].AsFloat := TJSONNumber(JV).AsDouble;
            else
              if JV is TJSONString then
                Cds.Fields[K].AsString := TJSONString(JV).Value
              else
                Cds.Fields[K].AsString := JV.Value;
            end;
          end;
          Cds.Post;
        end;
      Cds.First;

      R.SetDataSet(DsPair.JsonString.Value, Cds);
      Inc(Result);
    end;
  finally
    Root.Free;
  end;
end;

procedure CmdExport(const FileName, OutFile, DataFile: string);
var
  R: TrhReport;
  Doc: TrhRenderedDocument;
  DataOwner: TComponent;
  Ext: string;
  N: Integer;
begin
  R := LoadReport(FileName);
  try
    DataOwner := TComponent.Create(nil);
    try
      if DataFile <> '' then
      begin
        N := BuildDataSets(R, DataFile, DataOwner);
        Writeln(Format('dados: %d dataset(s) carregado(s) de "%s".', [N, DataFile]));
      end;
      Doc := TrhDataPipeline.BuildDocument(R);
      try
        Ext := LowerCase(ExtractFileExt(OutFile));
        if Ext = '.pdf' then
          TrhPdfExporter.ExportToFile(Doc, OutFile)
        else if (Ext = '.html') or (Ext = '.htm') then
          TrhHtmlExporter.ExportToFile(Doc, OutFile, R.Title)
        else if Ext = '.xlsx' then
          TrhXlsxExporter.ExportToFile(Doc, OutFile)
        else if Ext = '.docx' then
          TrhDocxExporter.ExportToFile(Doc, OutFile)
        else
          raise Exception.CreateFmt(
            'formato nao suportado: "%s" (use .pdf/.html/.xlsx/.docx)', [Ext]);
        Writeln(Format('OK: exportado para "%s" (%d pagina(s)).', [OutFile, Doc.PageCount]));
      finally
        Doc.Free;
      end;
    finally
      DataOwner.Free; // libera os TClientDataSet criados
    end;
  finally
    R.Free;
  end;
end;

procedure RunCLI;
var
  Cmd, DataFile: string;
  I: Integer;
begin
  if ParamCount < 1 then
  begin
    PrintUsage;
    ExitCode := 1;
    Exit;
  end;
  Cmd := LowerCase(ParamStr(1));
  if (Cmd = 'help') or (Cmd = '-h') or (Cmd = '--help') then
    PrintUsage
  else if (Cmd = 'version') or (Cmd = '-v') or (Cmd = '--version') then
    Writeln('rhtool ', TrhReport.LibraryVersion)
  else if Cmd = 'validate' then
  begin
    if ParamCount < 2 then
      raise Exception.Create('uso: rhtool validate <arquivo.rhr>');
    CmdValidate(ParamStr(2));
  end
  else if Cmd = 'info' then
  begin
    if ParamCount < 2 then
      raise Exception.Create('uso: rhtool info <arquivo.rhr>');
    CmdInfo(ParamStr(2));
  end
  else if Cmd = 'export' then
  begin
    if ParamCount < 3 then
      raise Exception.Create(
        'uso: rhtool export <arquivo.rhr> <saida.ext> [--data <dados.json>]');
    DataFile := '';
    for I := 4 to ParamCount do
      if SameText(ParamStr(I), '--data') and (I < ParamCount) then
        DataFile := ParamStr(I + 1);
    CmdExport(ParamStr(2), ParamStr(3), DataFile);
  end
  else
    raise Exception.CreateFmt('comando desconhecido: "%s" (use "rhtool help").', [Cmd]);
end;

begin
  try
    RunCLI;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'erro: ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
