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
  Vcl.Graphics,
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
  Writeln('  rhtool export <arquivo.rhr> <saida.ext>    exporta (.pdf/.html/.xlsx/.docx)');
  Writeln('  rhtool version');
  Writeln('  rhtool help');
  Writeln('');
  Writeln('Obs.: export renderiza o LAYOUT do template. Sem dados ligados, as');
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

procedure CmdExport(const FileName, OutFile: string);
var
  R: TrhReport;
  Doc: TrhRenderedDocument;
  Ext: string;
begin
  R := LoadReport(FileName);
  try
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
    R.Free;
  end;
end;

procedure RunCLI;
var
  Cmd: string;
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
      raise Exception.Create('uso: rhtool export <arquivo.rhr> <saida.ext>');
    CmdExport(ParamStr(2), ParamStr(3));
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
