{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Registro de design-time. Esta unidade SO pode ser compilada no pacote
///   design-time (ReportsHowieDT), pois referencia DesignIntf. Nunca deve ser
///   linkada no EXE do usuario final.
///
///   FASE 0: registra apenas o componente TrhReport na paleta. O component
///   editor (que abre o designer modal) e os property editors entram na Fase 5.
/// </summary>
unit rh.Reg;

interface

procedure Register;

implementation

uses
  System.Classes,
  DesignIntf,
  rh.Consts,
  rh.Report,
  rh.Design.ComponentEditor;

procedure Register;
begin
  RegisterComponents(RH_PALETTE_PAGE, [TrhReport]);
  // Fase 5: duplo-clique / verbos abrem o designer visual.
  RegisterComponentEditor(TrhReport, TrhReportComponentEditor);
end;

end.
