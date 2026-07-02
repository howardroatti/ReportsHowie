{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Envio do relatorio por e-mail (SMTP via Indy). O relatorio e renderizado
///   no formato pedido (PDF/HTML/XLSX/DOCX) a partir da MESMA display list dos
///   exportadores, gravado num arquivo temporario e anexado a mensagem.
///
///   TLS desacoplado: para manter o principio "zero dependencias externas", esta
///   unit NAO referencia nenhuma implementacao de SSL. Quando um transporte
///   seguro e pedido (StartTLS/Implicit), a aplicacao deve atribuir um IOHandler
///   SSL ao TIdSMTP pelo evento OnConfigureSMTP (ex.: TIdSSLIOHandlerSocketOpenSSL
///   ou um IOHandler SChannel). Assim o componente compila em qualquer maquina e
///   o usuario escolhe a pilha TLS que preferir.
/// </summary>
unit rh.Email;

interface

uses
  System.Classes, System.SysUtils,
  IdSMTP,
  rh.Report;

type
  /// <summary>Formato do anexo gerado.</summary>
  TrhReportFormat = (rrfPDF, rrfHTML, rrfXLSX, rrfDOCX);

  /// <summary>Modo de seguranca do transporte SMTP.</summary>
  TrhSMTPSecurity = (
    rssNone,        // sem TLS (porta 25 tipica / servidor local)
    rssStartTLS,    // STARTTLS / TLS explicito (porta 587 tipica)
    rssImplicitTLS  // TLS implicito / SSL direto (porta 465 tipica)
  );

  /// <summary>Configuracao do servidor SMTP e do remetente (passada em runtime).</summary>
  TrhSMTPSettings = record
    Host: string;
    Port: Integer;
    Username: string;
    Password: string;
    Security: TrhSMTPSecurity;
    FromName: string;
    FromAddress: string;
    class function Create(const AHost: string; APort: Integer;
      const AUser, APass, AFromAddress: string;
      ASecurity: TrhSMTPSecurity = rssStartTLS;
      const AFromName: string = ''): TrhSMTPSettings; static;
  end;

  /// <summary>Deixa a aplicacao plugar o IOHandler SSL e/ou ajustar o TIdSMTP
  ///  antes de conectar. Mantem esta unit livre de dependencia de TLS.</summary>
  TrhConfigureSMTPEvent = procedure(Sender: TObject; SMTP: TIdSMTP) of object;

  ErhEmail = class(Exception);

  TrhMailer = class(TComponent)
  private
    FTimeout: Integer;
    FOnConfigureSMTP: TrhConfigureSMTPEvent;
    procedure RenderReportToFile(Report: TrhReport; Fmt: TrhReportFormat;
      const FileName: string);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Renderiza o relatorio no formato pedido, anexa e envia por SMTP.
    ///  Datasets do relatorio devem ter sido ligados antes (SetDataSet).</summary>
    procedure SendReport(Report: TrhReport; Fmt: TrhReportFormat;
      const Recipients: array of string; const Subject, Body: string;
      const Settings: TrhSMTPSettings; const AttachmentName: string = '');
  published
    /// <summary>Timeout de conexao/leitura em milissegundos.</summary>
    property Timeout: Integer read FTimeout write FTimeout default 30000;
    property OnConfigureSMTP: TrhConfigureSMTPEvent read FOnConfigureSMTP write FOnConfigureSMTP;
  end;

/// <summary>Extensao de arquivo padrao do formato (com ponto).</summary>
function rhReportFormatExt(Fmt: TrhReportFormat): string;
/// <summary>Content-Type (MIME) do formato.</summary>
function rhReportFormatMime(Fmt: TrhReportFormat): string;

implementation

uses
  System.IOUtils,
  IdMessage, IdText, IdAttachmentFile, IdExplicitTLSClientServerBase,
  rh.Render.Intf, rh.Data.Pipeline,
  rh.Export.HTML, rh.Export.PDF, rh.Export.XLSX, rh.Export.DOCX;

function rhReportFormatExt(Fmt: TrhReportFormat): string;
begin
  case Fmt of
    rrfPDF:  Result := '.pdf';
    rrfHTML: Result := '.html';
    rrfXLSX: Result := '.xlsx';
    rrfDOCX: Result := '.docx';
  else
    Result := '.dat';
  end;
end;

function rhReportFormatMime(Fmt: TrhReportFormat): string;
begin
  case Fmt of
    rrfPDF:  Result := 'application/pdf';
    rrfHTML: Result := 'text/html; charset=utf-8';
    rrfXLSX: Result := 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    rrfDOCX: Result := 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  else
    Result := 'application/octet-stream';
  end;
end;

function DefaultAttachmentName(Report: TrhReport; Fmt: TrhReportFormat): string;
var
  Base: string;
  C: Char;
begin
  Base := 'relatorio';
  if (Report <> nil) and (Report.Title <> '') then
    Base := Report.Title;
  // troca caracteres invalidos de nome de arquivo por '_'
  for C in TPath.GetInvalidFileNameChars do
    Base := StringReplace(Base, C, '_', [rfReplaceAll]);
  Result := Base + rhReportFormatExt(Fmt);
end;

{ TrhSMTPSettings }

class function TrhSMTPSettings.Create(const AHost: string; APort: Integer;
  const AUser, APass, AFromAddress: string; ASecurity: TrhSMTPSecurity;
  const AFromName: string): TrhSMTPSettings;
begin
  Result.Host := AHost;
  Result.Port := APort;
  Result.Username := AUser;
  Result.Password := APass;
  Result.FromAddress := AFromAddress;
  Result.Security := ASecurity;
  if AFromName <> '' then
    Result.FromName := AFromName
  else
    Result.FromName := AFromAddress;
end;

{ TrhMailer }

constructor TrhMailer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTimeout := 30000;
end;

procedure TrhMailer.RenderReportToFile(Report: TrhReport; Fmt: TrhReportFormat;
  const FileName: string);
var
  Doc: TrhRenderedDocument;
begin
  Doc := TrhDataPipeline.BuildDocument(Report);
  try
    case Fmt of
      rrfPDF:  TrhPdfExporter.ExportToFile(Doc, FileName);
      rrfHTML: TrhHtmlExporter.ExportToFile(Doc, FileName, Report.Title);
      rrfXLSX: TrhXlsxExporter.ExportToFile(Doc, FileName);
      rrfDOCX: TrhDocxExporter.ExportToFile(Doc, FileName);
    end;
  finally
    Doc.Free;
  end;
end;

procedure TrhMailer.SendReport(Report: TrhReport; Fmt: TrhReportFormat;
  const Recipients: array of string; const Subject, Body: string;
  const Settings: TrhSMTPSettings; const AttachmentName: string);
var
  SMTP: TIdSMTP;
  Msg: TIdMessage;
  Txt: TIdText;
  Att: TIdAttachmentFile;
  Temp, DispName: string;
  I: Integer;
begin
  if Report = nil then
    raise ErhEmail.Create('SendReport: relatorio nulo.');
  if Length(Recipients) = 0 then
    raise ErhEmail.Create('SendReport: informe ao menos um destinatario.');
  if Settings.Host = '' then
    raise ErhEmail.Create('SendReport: Host SMTP nao informado.');
  if Settings.FromAddress = '' then
    raise ErhEmail.Create('SendReport: FromAddress (remetente) nao informado.');

  Temp := TPath.GetTempFileName; // cria um arquivo temporario unico
  try
    RenderReportToFile(Report, Fmt, Temp);

    Msg := TIdMessage.Create(nil);
    SMTP := TIdSMTP.Create(nil);
    try
      // ---- mensagem ----
      Msg.From.Address := Settings.FromAddress;
      Msg.From.Name := Settings.FromName;
      for I := 0 to High(Recipients) do
        Msg.Recipients.Add.Address := Recipients[I];
      Msg.Subject := Subject;
      Msg.ContentType := 'multipart/mixed';

      // corpo em texto simples
      Txt := TIdText.Create(Msg.MessageParts, nil);
      Txt.ContentType := 'text/plain; charset=utf-8';
      Txt.CharSet := 'utf-8';
      Txt.Body.Text := Body;

      // anexo (nome exibido independe do arquivo .tmp fisico)
      DispName := AttachmentName;
      if DispName = '' then
        DispName := DefaultAttachmentName(Report, Fmt);
      Att := TIdAttachmentFile.Create(Msg.MessageParts, Temp);
      Att.FileName := DispName;
      Att.ContentType := rhReportFormatMime(Fmt);

      // ---- transporte ----
      SMTP.Host := Settings.Host;
      SMTP.Port := Settings.Port;
      if Settings.Username <> '' then
      begin
        SMTP.Username := Settings.Username;
        SMTP.Password := Settings.Password;
        SMTP.AuthType := satDefault;
      end
      else
        SMTP.AuthType := satNone;
      SMTP.ConnectTimeout := FTimeout;
      SMTP.ReadTimeout := FTimeout;

      case Settings.Security of
        rssNone:        SMTP.UseTLS := utNoTLSSupport;
        rssStartTLS:    SMTP.UseTLS := utUseExplicitTLS;
        rssImplicitTLS: SMTP.UseTLS := utUseImplicitTLS;
      end;

      // a app pluga o IOHandler SSL (OpenSSL/SChannel) e/ou ajusta o SMTP
      if Assigned(FOnConfigureSMTP) then
        FOnConfigureSMTP(Self, SMTP);

      if (Settings.Security <> rssNone) and (SMTP.IOHandler = nil) then
        raise ErhEmail.Create(
          'TLS foi solicitado mas nenhum IOHandler SSL foi atribuido. Use o evento ' +
          'OnConfigureSMTP para atribuir SMTP.IOHandler (ex.: TIdSSLIOHandlerSocketOpenSSL ' +
          'ou um IOHandler SChannel).');

      SMTP.Connect;
      try
        SMTP.Send(Msg);
      finally
        if SMTP.Connected then
          SMTP.Disconnect;
      end;
    finally
      SMTP.Free;
      Msg.Free;
    end;
  finally
    System.SysUtils.DeleteFile(Temp);
  end;
end;

end.
