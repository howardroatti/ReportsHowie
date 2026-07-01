{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Classes base compartilhadas do modelo. Na Fase 0 fornece apenas a
///   raiz de persistencia; o modelo completo (bandas, objetos, colecoes)
///   e construido na Fase 1.
/// </summary>
unit rh.Classes;

interface

uses
  System.Classes;

type
  /// <summary>
  ///   Raiz de persistencia para elementos do modelo que nao sao componentes.
  ///   Descende de TPersistent para participar do streaming VCL padrao
  ///   (RTTI de propriedades publicadas) usado tanto pelo serializador JSON
  ///   quanto pelo streaming DFM.
  /// </summary>
  TrhPersistent = class(TPersistent)
  end;

implementation

end.
