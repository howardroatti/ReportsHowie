{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Inspetor de propriedades proprio, dirigido por RTTI (System.TypInfo). Lista
///   as propriedades PUBLICADAS do objeto/banda selecionado e oferece editores
///   conforme o tipo: string, inteiro, geometria em mm (Left/Top/Width/Height),
///   enumeracao (combo), booleano (combo), cor (dialogo) e fonte (dialogo).
///   E VCL puro (sem DesignIntf) — reutilizavel no designer runtime da Fase 10.
/// </summary>
unit rh.Design.Inspector;

interface

uses
  System.Classes, System.SysUtils, System.TypInfo, System.Generics.Collections,
  Winapi.Windows, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  Vcl.Dialogs, Vcl.ExtDlgs, Vcl.Forms;

type
  TrhInspKind = (ikStr, ikInt, ikGeom, ikColor, ikEnum, ikBool, ikFont,
    ikPicture, ikExpr);

  TrhInspRow = record
    Prop: PPropInfo;
    Kind: TrhInspKind;
    Ctrl: TControl;
    EnumMin: Integer;
  end;

  TrhInspector = class(TScrollBox)
  private
    FObj: TPersistent;
    FRows: TList<TrhInspRow>;
    FOwned: TList<TControl>;
    FLoading: Boolean;
    FFields: TStringList;   // campos oferecidos ao editor de expressao
    FOnChanged: TNotifyEvent;
    FOnBeforeChange: TNotifyEvent;
    procedure ClearRows;
    procedure DoBeforeChange;
    function NewLabel(const ACaption: string; Y: Integer): TLabel;
    procedure AddRow(P: PPropInfo; var Y: Integer);
    function DisplayValue(const Row: TrhInspRow): string;
    procedure ApplyRow(const Row: TrhInspRow);
    procedure EditExit(Sender: TObject);
    procedure ComboChange(Sender: TObject);
    procedure ColorClick(Sender: TObject);
    procedure FontClick(Sender: TObject);
    procedure PictureClick(Sender: TObject);
    procedure ExprClick(Sender: TObject);
    procedure DoChanged;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Inspect(AObj: TPersistent);
    procedure RefreshValues;
    /// <summary>Define os campos oferecidos no editor de expressao (botao "...").</summary>
    procedure SetFields(AFields: TStrings);
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    /// <summary>Disparado ANTES de aplicar cada mudanca (para snapshot de undo).</summary>
    property OnBeforeChange: TNotifyEvent read FOnBeforeChange write FOnBeforeChange;
  end;

implementation

uses
  rh.Design.ExprEditor;

const
  ROWH   = 26;
  LABELW = 92;
  PAD    = 6;
  EXPRBTNW = 24;   // largura do botao "..." do editor de expressao

function IsGeometry(const Name: string): Boolean;
begin
  Result := SameText(Name, 'Left') or SameText(Name, 'Top') or
            SameText(Name, 'Width') or SameText(Name, 'Height');
end;

// Propriedades string que sao expressoes (ganham o botao "..." do editor).
function IsExprProp(const Name: string): Boolean;
begin
  Result := SameText(Name, 'Text') or SameText(Name, 'GroupExpression') or
            SameText(Name, 'CategoryExpr') or SameText(Name, 'ValueExpr') or
            SameText(Name, 'MasterKeyExpr');
end;

// Modo ilha (texto com [expr]) vs. expressao unica.
function IsIslandProp(const Name: string): Boolean;
begin
  Result := SameText(Name, 'Text');
end;

{ TrhInspector }

constructor TrhInspector.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRows := TList<TrhInspRow>.Create;
  FOwned := TList<TControl>.Create;
  FFields := TStringList.Create;
  BorderStyle := bsNone;
  Color := clWindow;
  ParentColor := False;
  VertScrollBar.Tracking := True;
end;

destructor TrhInspector.Destroy;
begin
  ClearRows;
  FFields.Free;
  FOwned.Free;
  FRows.Free;
  inherited Destroy;
end;

procedure TrhInspector.SetFields(AFields: TStrings);
begin
  FFields.Clear;
  if AFields <> nil then
    FFields.Assign(AFields);
end;

procedure TrhInspector.ClearRows;
var
  C: TControl;
begin
  for C in FOwned do
    C.Free;
  FOwned.Clear;
  FRows.Clear;
end;

function TrhInspector.NewLabel(const ACaption: string; Y: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(PAD, Y + 5, LABELW - PAD, ROWH - 6);
  Result.Caption := ACaption;
  Result.Transparent := True;
  FOwned.Add(Result);
end;

procedure TrhInspector.Inspect(AObj: TPersistent);
var
  PropList: PPropList;
  Count, I, Y: Integer;
  Header: TLabel;
begin
  ClearRows;
  FObj := AObj;
  if FObj = nil then Exit;

  FLoading := True;
  try
    Y := 4;
    Header := NewLabel(FObj.ClassName, Y);
    Header.Font.Style := [fsBold];
    Header.Width := Width - 2 * PAD;
    Inc(Y, ROWH);

    Count := GetPropList(FObj, PropList);
    try
      for I := 0 to Count - 1 do
        AddRow(PropList^[I], Y);
    finally
      if PropList <> nil then
        FreeMem(PropList);
    end;
  finally
    FLoading := False;
  end;
end;

procedure TrhInspector.AddRow(P: PPropInfo; var Y: Integer);
var
  Row: TrhInspRow;
  Kind: TTypeKind;
  TypeName, PName: string;
  Edit: TEdit;
  Combo: TComboBox;
  Panel: TPanel;
  Btn: TButton;
  TD: PTypeData;
  I: Integer;
  Editable: Boolean;
begin
  Kind := P^.PropType^.Kind;
  PName := string(P^.Name);
  TypeName := string(P^.PropType^.Name);
  Editable := P^.SetProc <> nil;

  Row.Prop := P;
  Row.EnumMin := 0;
  Row.Ctrl := nil;

  // decidir tipo de editor
  if Kind in [tkString, tkLString, tkUString, tkWString] then
  begin
    if IsExprProp(PName) then Row.Kind := ikExpr else Row.Kind := ikStr;
  end
  else if Kind = tkInteger then
  begin
    if SameText(TypeName, 'TColor') then Row.Kind := ikColor
    else if IsGeometry(PName) then Row.Kind := ikGeom
    else Row.Kind := ikInt;
  end
  else if Kind = tkEnumeration then
  begin
    if SameText(TypeName, 'Boolean') then Row.Kind := ikBool
    else Row.Kind := ikEnum;
  end
  else if (Kind = tkClass) and SameText(TypeName, 'TFont') then
    Row.Kind := ikFont
  else if (Kind = tkClass) and SameText(TypeName, 'TPicture') then
    Row.Kind := ikPicture
  else
    Exit; // tipo nao suportado (sets, outras classes) — ignora

  NewLabel(PName, Y);

  case Row.Kind of
    ikColor:
      begin
        Panel := TPanel.Create(Self);
        Panel.Parent := Self;
        Panel.SetBounds(LABELW, Y + 3, Width - LABELW - PAD, ROWH - 6);
        Panel.Anchors := [akLeft, akTop, akRight];
        Panel.BevelOuter := bvLowered;
        Panel.ParentBackground := False;
        Panel.Font.Color := clBlack;
        Panel.Cursor := crHandPoint;
        Panel.OnClick := ColorClick;
        Row.Ctrl := Panel;
      end;
    ikFont, ikPicture:
      begin
        Btn := TButton.Create(Self);
        Btn.Parent := Self;
        Btn.SetBounds(LABELW, Y + 2, Width - LABELW - PAD, ROWH - 4);
        Btn.Anchors := [akLeft, akTop, akRight];
        if Row.Kind = ikFont then
          Btn.OnClick := FontClick
        else
          Btn.OnClick := PictureClick;
        Row.Ctrl := Btn;
      end;
    ikEnum, ikBool:
      begin
        Combo := TComboBox.Create(Self);
        Combo.Parent := Self;
        Combo.SetBounds(LABELW, Y + 2, Width - LABELW - PAD, ROWH - 4);
        Combo.Anchors := [akLeft, akTop, akRight];
        Combo.Style := csDropDownList;
        Combo.Enabled := Editable;
        if Row.Kind = ikBool then
        begin
          Combo.Items.Add('False');
          Combo.Items.Add('True');
        end
        else
        begin
          TD := GetTypeData(P^.PropType^);
          Row.EnumMin := TD^.MinValue;
          for I := TD^.MinValue to TD^.MaxValue do
            Combo.Items.Add(GetEnumName(P^.PropType^, I));
        end;
        Combo.OnChange := ComboChange;
        Row.Ctrl := Combo;
      end;
    ikExpr:
      begin
        // edit reduzido + botao "..." que abre o editor de expressao
        Edit := TEdit.Create(Self);
        Edit.Parent := Self;
        Edit.SetBounds(LABELW, Y + 2, Width - LABELW - PAD - EXPRBTNW - 2, ROWH - 4);
        Edit.Anchors := [akLeft, akTop, akRight];
        Edit.Enabled := Editable;
        Edit.OnExit := EditExit;

        Btn := TButton.Create(Self);
        Btn.Parent := Self;
        Btn.SetBounds(Width - PAD - EXPRBTNW, Y + 2, EXPRBTNW, ROWH - 4);
        Btn.Anchors := [akTop, akRight];
        Btn.Caption := '...';
        Btn.Hint := 'Editor de expressao (campos, funcoes, validacao)';
        Btn.ShowHint := True;
        Btn.Enabled := Editable;
        Btn.Tag := FRows.Count; // aponta para o row que sera adicionado a seguir
        Btn.OnClick := ExprClick;
        FOwned.Add(Btn);

        Row.Ctrl := Edit;
      end;
  else
    // ikStr, ikInt, ikGeom
    Edit := TEdit.Create(Self);
    Edit.Parent := Self;
    Edit.SetBounds(LABELW, Y + 2, Width - LABELW - PAD, ROWH - 4);
    Edit.Anchors := [akLeft, akTop, akRight];
    Edit.Enabled := Editable;
    Edit.OnExit := EditExit;
    Row.Ctrl := Edit;
  end;

  Row.Ctrl.Tag := FRows.Count;
  FOwned.Add(Row.Ctrl);
  FRows.Add(Row);
  // preencher valor exibido
  case Row.Kind of
    ikColor:
      begin
        TPanel(Row.Ctrl).Color := TColor(GetOrdProp(FObj, P));
        TPanel(Row.Ctrl).Caption := DisplayValue(Row);
      end;
    ikFont, ikPicture:
      TButton(Row.Ctrl).Caption := DisplayValue(Row);
    ikEnum:
      TComboBox(Row.Ctrl).ItemIndex := GetOrdProp(FObj, P) - Row.EnumMin;
    ikBool:
      TComboBox(Row.Ctrl).ItemIndex := GetOrdProp(FObj, P);
  else
    TEdit(Row.Ctrl).Text := DisplayValue(Row);
  end;

  Inc(Y, ROWH);
end;

function TrhInspector.DisplayValue(const Row: TrhInspRow): string;
var
  RGB: Longint;
  F: TFont;
begin
  case Row.Kind of
    ikStr, ikExpr:  Result := GetStrProp(FObj, Row.Prop);
    ikInt:  Result := IntToStr(GetOrdProp(FObj, Row.Prop));
    ikGeom: Result := FormatFloat('0.0', GetOrdProp(FObj, Row.Prop) / 10);
    ikColor:
      begin
        RGB := ColorToRGB(TColor(GetOrdProp(FObj, Row.Prop)));
        Result := Format('#%.2X%.2X%.2X', [GetRValue(RGB), GetGValue(RGB), GetBValue(RGB)]);
      end;
    ikFont:
      begin
        F := TFont(GetObjectProp(FObj, Row.Prop));
        if F <> nil then
          Result := Format('%s, %dpt', [F.Name, F.Size])
        else
          Result := '(fonte)';
      end;
    ikPicture:
      begin
        if (TPicture(GetObjectProp(FObj, Row.Prop)) <> nil) and
           (TPicture(GetObjectProp(FObj, Row.Prop)).Graphic <> nil) and
           (not TPicture(GetObjectProp(FObj, Row.Prop)).Graphic.Empty) then
          Result := 'Trocar imagem...'
        else
          Result := 'Carregar imagem...';
      end;
  else
    Result := '';
  end;
end;

procedure TrhInspector.ApplyRow(const Row: TrhInspRow);
var
  Edit: TEdit;
  Combo: TComboBox;
begin
  case Row.Kind of
    ikStr, ikExpr:
      SetStrProp(FObj, Row.Prop, TEdit(Row.Ctrl).Text);
    ikInt:
      begin
        Edit := TEdit(Row.Ctrl);
        SetOrdProp(FObj, Row.Prop, StrToIntDef(Edit.Text, GetOrdProp(FObj, Row.Prop)));
      end;
    ikGeom:
      begin
        Edit := TEdit(Row.Ctrl);
        SetOrdProp(FObj, Row.Prop,
          Round(StrToFloatDef(Edit.Text, GetOrdProp(FObj, Row.Prop) / 10) * 10));
      end;
    ikEnum:
      begin
        Combo := TComboBox(Row.Ctrl);
        if Combo.ItemIndex >= 0 then
          SetOrdProp(FObj, Row.Prop, Combo.ItemIndex + Row.EnumMin);
      end;
    ikBool:
      begin
        Combo := TComboBox(Row.Ctrl);
        if Combo.ItemIndex >= 0 then
          SetOrdProp(FObj, Row.Prop, Combo.ItemIndex);
      end;
  end;
end;

procedure TrhInspector.EditExit(Sender: TObject);
var
  Row: TrhInspRow;
begin
  if FLoading then Exit;
  Row := FRows[TEdit(Sender).Tag];
  if TEdit(Sender).Text = DisplayValue(Row) then Exit; // nada mudou
  DoBeforeChange;
  ApplyRow(Row);
  DoChanged;
end;

procedure TrhInspector.ComboChange(Sender: TObject);
begin
  if FLoading then Exit;
  DoBeforeChange;
  ApplyRow(FRows[TComboBox(Sender).Tag]);
  DoChanged;
end;

procedure TrhInspector.ColorClick(Sender: TObject);
var
  Row: TrhInspRow;
  Dlg: TColorDialog;
begin
  if FLoading then Exit;
  Row := FRows[TPanel(Sender).Tag];
  if Row.Prop^.SetProc = nil then Exit;
  Dlg := TColorDialog.Create(nil);
  try
    Dlg.Color := TColor(GetOrdProp(FObj, Row.Prop));
    if Dlg.Execute then
    begin
      DoBeforeChange;
      SetOrdProp(FObj, Row.Prop, Integer(Dlg.Color));
      TPanel(Sender).Color := Dlg.Color;
      TPanel(Sender).Caption := DisplayValue(Row);
      DoChanged;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TrhInspector.FontClick(Sender: TObject);
var
  Row: TrhInspRow;
  Dlg: TFontDialog;
  F: TFont;
begin
  if FLoading then Exit;
  Row := FRows[TButton(Sender).Tag];
  F := TFont(GetObjectProp(FObj, Row.Prop));
  if F = nil then Exit;
  Dlg := TFontDialog.Create(nil);
  try
    Dlg.Font.Assign(F);
    if Dlg.Execute then
    begin
      DoBeforeChange;
      F.Assign(Dlg.Font);
      TButton(Sender).Caption := DisplayValue(Row);
      DoChanged;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TrhInspector.PictureClick(Sender: TObject);
var
  Row: TrhInspRow;
  Dlg: TOpenPictureDialog;
  Pic: TPicture;
begin
  if FLoading then Exit;
  Row := FRows[TButton(Sender).Tag];
  Pic := TPicture(GetObjectProp(FObj, Row.Prop));
  if Pic = nil then Exit;
  Dlg := TOpenPictureDialog.Create(nil);
  try
    if Dlg.Execute then
    begin
      DoBeforeChange;
      Pic.LoadFromFile(Dlg.FileName);
      TButton(Sender).Caption := DisplayValue(Row);
      DoChanged;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TrhInspector.ExprClick(Sender: TObject);
var
  Row: TrhInspRow;
  Edit: TEdit;
  PName, Res: string;
begin
  if FLoading then Exit;
  Row := FRows[TButton(Sender).Tag];
  if Row.Prop^.SetProc = nil then Exit;
  Edit := TEdit(Row.Ctrl);
  PName := string(Row.Prop^.Name);
  if TrhExprEditorForm.Execute(PName, Edit.Text, FFields, IsIslandProp(PName), Res) then
  begin
    if Res = Edit.Text then Exit; // nada mudou
    DoBeforeChange;
    Edit.Text := Res;
    ApplyRow(Row);
    DoChanged;
  end;
end;

procedure TrhInspector.RefreshValues;
var
  Row: TrhInspRow;
begin
  if FObj = nil then Exit;
  FLoading := True;
  try
    for Row in FRows do
      case Row.Kind of
        ikColor:
          begin
            TPanel(Row.Ctrl).Color := TColor(GetOrdProp(FObj, Row.Prop));
            TPanel(Row.Ctrl).Caption := DisplayValue(Row);
          end;
        ikFont, ikPicture:
          TButton(Row.Ctrl).Caption := DisplayValue(Row);
        ikEnum:
          TComboBox(Row.Ctrl).ItemIndex := GetOrdProp(FObj, Row.Prop) - Row.EnumMin;
        ikBool:
          TComboBox(Row.Ctrl).ItemIndex := GetOrdProp(FObj, Row.Prop);
      else
        TEdit(Row.Ctrl).Text := DisplayValue(Row);
      end;
  finally
    FLoading := False;
  end;
end;

procedure TrhInspector.DoChanged;
begin
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TrhInspector.DoBeforeChange;
begin
  if Assigned(FOnBeforeChange) then FOnBeforeChange(Self);
end;

end.
