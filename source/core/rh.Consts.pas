{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Constantes globais: versao, identificacao de paleta, nomes de formato.
/// </summary>
unit rh.Consts;

interface

const
  /// <summary>Versao semantica do ReportsHowie.</summary>
  RH_VERSION = '0.1.0-dev';

  /// <summary>Nome da pagina de paleta onde os componentes sao registrados.</summary>
  RH_PALETTE_PAGE = 'ReportsHowie';

  /// <summary>Extensao do arquivo de template de relatorio.</summary>
  RH_TEMPLATE_EXT = '.rhr';

  /// <summary>Versao do formato de serializacao (campo "formatVersion" no JSON).</summary>
  RH_FORMAT_VERSION = 1;

resourcestring
  SrhReportDesignerVerb = 'Design Report...';
  SrhReportLoadVerb     = 'Carregar .rhr...';
  SrhReportSaveVerb     = 'Salvar .rhr...';
  SrhReportAboutVerb    = 'Sobre o ReportsHowie...';

implementation

end.
