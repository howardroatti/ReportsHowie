{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   TrhReport: o componente que o usuario solta no form. Raiz do modelo de
///   relatorio e ponto de entrada da API publica (preview/export/email).
///
///   FASE 0: esqueleto instalavel. As colecoes de paginas/bandas/objetos, a
///   persistencia JSON (.rhr) e o streaming DFM via DefineProperties entram
///   na Fase 1; preview/export/email nas fases seguintes.
/// </summary>
unit rh.Report;

interface

uses
  System.Classes,
  rh.Consts;

type
  TrhReport = class(TComponent)
  private
    FTitle: string;
    FFormatVersion: Integer;
  protected
    // Fase 1: procedure DefineProperties(Filer: TFiler); override;
  public
    constructor Create(AOwner: TComponent); override;

    /// <summary>Retorna a versao do ReportsHowie em runtime.</summary>
    class function LibraryVersion: string;
  published
    /// <summary>Titulo logico do relatorio (aparece em metadados de export).</summary>
    property Title: string read FTitle write FTitle;
    /// <summary>Versao do formato de serializacao deste relatorio (somente leitura em runtime).</summary>
    property FormatVersion: Integer read FFormatVersion write FFormatVersion default RH_FORMAT_VERSION;
  end;

implementation

{ TrhReport }

constructor TrhReport.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFormatVersion := RH_FORMAT_VERSION;
end;

class function TrhReport.LibraryVersion: string;
begin
  Result := RH_VERSION;
end;

end.
