# E-mail (SMTP)

`rh.Email.pas` — envio do relatório por e-mail (**Fase 9**).

- `TrhMailer.SendReport(Report, Formato, Destinatários, Assunto, Corpo, Settings)` renderiza o relatório (PDF/HTML/XLSX/DOCX) a partir da mesma display list dos exportadores, grava num arquivo temporário e anexa à mensagem (Indy `TIdSMTP` + `TIdMessage`).
- `TrhSMTPSettings` guarda host/porta/credenciais/remetente e o modo de segurança (`rssNone` / `rssStartTLS` / `rssImplicitTLS`).
- **TLS desacoplado:** esta unit não referencia nenhuma biblioteca de SSL. Para transporte seguro, a aplicação atribui um IOHandler (OpenSSL **ou** SChannel) ao `TIdSMTP` pelo evento `OnConfigureSMTP` — assim o componente mantém "zero dependências externas" e você escolhe a pilha TLS.

Ver o Manual (seção *E-mail*) para exemplos completos.
