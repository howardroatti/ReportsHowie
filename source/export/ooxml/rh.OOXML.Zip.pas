{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Empacotador OOXML minimo sobre System.Zip. Um pacote OOXML (.xlsx/.docx)
///   e apenas um ZIP com "parts" (XML) em caminhos convencionados. Esta unit
///   acumula parts (texto UTF-8 ou bytes) e grava o ZIP. Reutilizada pelos
///   exportadores XLSX e DOCX. Zero dependencias externas.
/// </summary>
unit rh.OOXML.Zip;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Zip;

type
  TrhOoxmlPackage = class
  private
    FNames: TList<string>;
    FData: TList<TBytes>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Adiciona uma part XML (gravada como UTF-8 sem BOM).</summary>
    procedure AddXml(const PartName, Xml: string);
    /// <summary>Adiciona uma part binaria (imagens, etc.).</summary>
    procedure AddBytes(const PartName: string; const Data: TBytes);
    /// <summary>Grava o pacote ZIP no arquivo indicado.</summary>
    procedure SaveToFile(const FileName: string);
  end;

/// <summary>Escapa texto para conteudo XML (&amp; &lt; &gt; &quot;), removendo controles invalidos.</summary>
function XmlEscape(const S: string): string;

implementation

function XmlEscape(const S: string): string;
var
  I: Integer;
  C: Char;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create(Length(S) + 16);
  try
    for I := 1 to Length(S) do
    begin
      C := S[I];
      case C of
        '&': SB.Append('&amp;');
        '<': SB.Append('&lt;');
        '>': SB.Append('&gt;');
        '"': SB.Append('&quot;');
        #9, #10, #13: SB.Append(C);
      else
        if C >= ' ' then
          SB.Append(C); // descarta controles < espaco (invalidos em XML 1.0)
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TrhOoxmlPackage }

constructor TrhOoxmlPackage.Create;
begin
  inherited Create;
  FNames := TList<string>.Create;
  FData := TList<TBytes>.Create;
end;

destructor TrhOoxmlPackage.Destroy;
begin
  FData.Free;
  FNames.Free;
  inherited Destroy;
end;

procedure TrhOoxmlPackage.AddXml(const PartName, Xml: string);
begin
  AddBytes(PartName, TEncoding.UTF8.GetBytes(Xml));
end;

procedure TrhOoxmlPackage.AddBytes(const PartName: string; const Data: TBytes);
begin
  FNames.Add(PartName);
  FData.Add(Data);
end;

procedure TrhOoxmlPackage.SaveToFile(const FileName: string);
var
  Zip: TZipFile;
  I: Integer;
begin
  Zip := TZipFile.Create;
  try
    Zip.Open(FileName, zmWrite);
    for I := 0 to FNames.Count - 1 do
      Zip.Add(FData[I], FNames[I], zcDeflate);
    Zip.Close;
  finally
    Zip.Free;
  end;
end;

end.
