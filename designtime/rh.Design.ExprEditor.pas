{******************************************************************************}
{  ReportsHowie - Gerador de Relatorios para Delphi (VCL)                      }
{  https://github.com/howardroatti/ReportsHowie                                }
{  Copyright (C) 2026 Howard Roatti e contribuidores - Licenca LGPL-3.0        }
{******************************************************************************}

/// <summary>
///   Dialogo de edicao de expressao. Construido em codigo e LIVRE de DesignIntf
///   (mesmo padrao do designer), para ser aberto pelo inspetor no IDE e reusado
///   no designer runtime (Fase 10).
///
///   Oferece: area de texto, listas de CAMPOS e FUNCOES (duplo-clique insere) e
///   VALIDACAO via o proprio motor de expressoes (parse sem avaliar). Dois modos:
///     - Expressao inteira (GroupExpression/CategoryExpr/ValueExpr): o texto todo
///       precisa ser uma expressao valida.
///     - Texto com ilhas (Text): apenas o conteudo de cada [ ... ] e validado; o
///       texto literal fora das ilhas fica livre.
/// </summary>
unit rh.Design.ExprEditor;

interface

uses
  System.Classes, System.SysUtils,
  Winapi.Windows, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Dialogs;

type
  TrhExprEditorForm = class(TForm)
  private
    FIslandMode: Boolean;
    FMemo: TMemo;
    FFieldList: TListBox;
    FFuncList: TListBox;
    FStatus: TLabel;
    procedure BuildUI;
    procedure FieldDblClick(Sender: TObject);
    procedure FuncDblClick(Sender: TObject);
    procedure DoValidate(Sender: TObject);
    procedure DoOK(Sender: TObject);
    procedure DoCancel(Sender: TObject);
    procedure MemoChange(Sender: TObject);
    procedure InsertIntoMemo(const AText: string; ACaretBack: Integer);
    procedure PopulateFunctions;
    function ValidateText(out AError: string): Boolean;
  public
    /// <summary>Abre o dialogo. Retorna True (OK) com AResult preenchido; False
    ///  no Cancelar. AIslandMode=True para propriedades de texto com ilhas.</summary>
    class function Execute(const ATitle, AInitial: string; AFields: TStrings;
      AIslandMode: Boolean; out AResult: string): Boolean;
  end;

implementation

uses
  rh.Expr, rh.Expr.Functions;

const
  // Pseudo-variaveis resolvidas pelo contexto (nao sao funcoes).
  PSEUDO_VARS: array[0..4] of string = ('PAGE', 'TOTALPAGES', 'DATE', 'TIME', 'NOW');
  // Agregados sao tratados no parser (nao entram em GFunctions).
  AGGREGATES: array[0..4] of string = ('SUM', 'AVG', 'COUNT', 'MIN', 'MAX');

{ TrhExprEditorForm }

class function TrhExprEditorForm.Execute(const ATitle, AInitial: string;
  AFields: TStrings; AIslandMode: Boolean; out AResult: string): Boolean;
var
  Frm: TrhExprEditorForm;
  I: Integer;
begin
  AResult := AInitial;
  Frm := TrhExprEditorForm.CreateNew(nil);
  try
    Frm.FIslandMode := AIslandMode;
    Frm.BuildUI;
    if ATitle <> '' then
      Frm.Caption := 'Expressao - ' + ATitle;
    Frm.FMemo.Text := AInitial;

    // pseudo-variaveis primeiro, depois os campos do(s) dataset(s)
    for I := Low(PSEUDO_VARS) to High(PSEUDO_VARS) do
      Frm.FFieldList.Items.Add(PSEUDO_VARS[I]);
    if AFields <> nil then
      for I := 0 to AFields.Count - 1 do
        if Trim(AFields[I]) <> '' then
          Frm.FFieldList.Items.Add(AFields[I]);

    Frm.PopulateFunctions;
    Frm.DoValidate(nil); // status inicial

    Result := Frm.ShowModal = mrOk;
    if Result then
      AResult := Frm.FMemo.Text;
  finally
    Frm.Free;
  end;
end;

procedure TrhExprEditorForm.BuildUI;
var
  Right: TPanel;
  Bottom: TPanel;
  LblFields, LblFuncs, LblHint: TLabel;
  Split: TSplitter;
  BtnOK, BtnCancel, BtnVal: TButton;
begin
  Caption := 'Expressao';
  Position := poScreenCenter;
  Width := 660;
  Height := 460;
  BorderStyle := bsSizeable;

  // ---- rodape: status + Validar/OK/Cancelar ----
  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 44;
  Bottom.BevelOuter := bvNone;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Bottom;
  FStatus.SetBounds(10, 14, 360, 18);
  FStatus.Anchors := [akLeft, akTop, akRight];
  FStatus.Transparent := True;
  FStatus.Caption := '';

  BtnCancel := TButton.Create(Self);
  BtnCancel.Parent := Bottom;
  BtnCancel.Caption := 'Cancelar';
  BtnCancel.SetBounds(Bottom.Width - 110, 7, 100, 30);
  BtnCancel.Anchors := [akTop, akRight];
  BtnCancel.Cancel := True;
  BtnCancel.OnClick := DoCancel;

  BtnOK := TButton.Create(Self);
  BtnOK.Parent := Bottom;
  BtnOK.Caption := 'OK';
  BtnOK.SetBounds(Bottom.Width - 220, 7, 100, 30);
  BtnOK.Anchors := [akTop, akRight];
  BtnOK.Default := True;
  BtnOK.OnClick := DoOK;

  BtnVal := TButton.Create(Self);
  BtnVal.Parent := Bottom;
  BtnVal.Caption := 'Validar';
  BtnVal.SetBounds(Bottom.Width - 330, 7, 100, 30);
  BtnVal.Anchors := [akTop, akRight];
  BtnVal.OnClick := DoValidate;

  // ---- painel direito: Campos (topo) + Funcoes (baixo) ----
  Right := TPanel.Create(Self);
  Right.Parent := Self;
  Right.Align := alRight;
  Right.Width := 200;
  Right.BevelOuter := bvNone;

  LblFields := TLabel.Create(Self);
  LblFields.Parent := Right;
  LblFields.Align := alTop;
  LblFields.Height := 20;
  LblFields.Caption := ' Campos (duplo-clique insere [campo])';
  LblFields.Layout := tlCenter;

  FFieldList := TListBox.Create(Self);
  FFieldList.Parent := Right;
  FFieldList.Align := alTop;
  FFieldList.Height := 170;
  FFieldList.OnDblClick := FieldDblClick;

  Split := TSplitter.Create(Self);
  Split.Parent := Right;
  Split.Align := alTop;
  Split.Height := 4;
  Split.MinSize := 60;

  LblFuncs := TLabel.Create(Self);
  LblFuncs.Parent := Right;
  LblFuncs.Align := alTop;
  LblFuncs.Height := 20;
  LblFuncs.Caption := ' Funcoes / agregados (duplo-clique)';
  LblFuncs.Layout := tlCenter;

  FFuncList := TListBox.Create(Self);
  FFuncList.Parent := Right;
  FFuncList.Align := alClient;
  FFuncList.OnDblClick := FuncDblClick;

  Split := TSplitter.Create(Self);
  Split.Parent := Self;
  Split.Align := alRight;
  Split.Width := 4;

  // ---- dica + memo (area principal) ----
  LblHint := TLabel.Create(Self);
  LblHint.Parent := Self;
  LblHint.Align := alTop;
  LblHint.Height := 22;
  LblHint.Layout := tlCenter;
  if FIslandMode then
    LblHint.Caption := '  Texto com ilhas [expr] - o texto fora dos colchetes e literal.'
  else
    LblHint.Caption := '  Expressao unica - todo o conteudo deve ser uma expressao valida.';

  FMemo := TMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.Align := alClient;
  FMemo.ScrollBars := ssBoth;
  FMemo.WordWrap := False;
  FMemo.Font.Name := 'Consolas';
  FMemo.Font.Size := 10;
  FMemo.OnChange := MemoChange;
end;

procedure TrhExprEditorForm.PopulateFunctions;
var
  Name: string;
begin
  for Name in AGGREGATES do
    FFuncList.Items.Add(Name);
  for Name in rhExprFunctionNames do
    FFuncList.Items.Add(Name);
end;

procedure TrhExprEditorForm.InsertIntoMemo(const AText: string; ACaretBack: Integer);
begin
  FMemo.SelText := AText;
  FMemo.SelStart := FMemo.SelStart - ACaretBack;
  FMemo.SelLength := 0;
  FMemo.SetFocus;
end;

procedure TrhExprEditorForm.FieldDblClick(Sender: TObject);
begin
  if FFieldList.ItemIndex < 0 then Exit;
  // campos e pseudo-vars entram como [nome] (sintaxe valida em ilha e em expressao)
  InsertIntoMemo('[' + FFieldList.Items[FFieldList.ItemIndex] + ']', 0);
end;

procedure TrhExprEditorForm.FuncDblClick(Sender: TObject);
begin
  if FFuncList.ItemIndex < 0 then Exit;
  // insere NOME() com o cursor entre os parenteses
  InsertIntoMemo(FFuncList.Items[FFuncList.ItemIndex] + '()', 1);
end;

procedure TrhExprEditorForm.MemoChange(Sender: TObject);
begin
  FStatus.Caption := '';
end;

// Valida o texto conforme o modo. Retorna True e AError='' se ok.
function TrhExprEditorForm.ValidateText(out AError: string): Boolean;

  function TryParse(const AExpr: string; out AMsg: string): Boolean;
  var
    E: TrhExpression;
  begin
    Result := True; AMsg := '';
    if Trim(AExpr) = '' then Exit;
    try
      E := TrhExpression.Create(AExpr);
      E.Free;
    except
      on Ex: Exception do begin Result := False; AMsg := Ex.Message; end;
    end;
  end;

var
  S, Island, Msg: string;
  I, J, N, Depth: Integer;
begin
  AError := '';
  S := FMemo.Text;

  if not FIslandMode then
    Exit(TryParse(S, AError));

  // modo ilha: valida so o conteudo de cada [ ... ] (colchetes balanceados)
  I := 1; N := Length(S);
  while I <= N do
  begin
    if S[I] = '[' then
    begin
      Depth := 1; J := I + 1;
      while (J <= N) and (Depth > 0) do
      begin
        if S[J] = '[' then Inc(Depth)
        else if S[J] = ']' then
        begin
          Dec(Depth);
          if Depth = 0 then Break;
        end;
        Inc(J);
      end;
      if Depth <> 0 then
      begin
        AError := 'Colchete "[" sem fechamento.';
        Exit(False);
      end;
      Island := Copy(S, I + 1, J - I - 1);
      if not TryParse(Island, Msg) then
      begin
        AError := Format('Ilha [%s]: %s', [Island, Msg]);
        Exit(False);
      end;
      I := J + 1;
    end
    else
      Inc(I);
  end;
  Result := True;
end;

procedure TrhExprEditorForm.DoValidate(Sender: TObject);
var
  Err: string;
begin
  if ValidateText(Err) then
  begin
    FStatus.Font.Color := clGreen;
    FStatus.Caption := 'Expressao valida.';
  end
  else
  begin
    FStatus.Font.Color := clRed;
    FStatus.Caption := Err;
  end;
end;

procedure TrhExprEditorForm.DoOK(Sender: TObject);
var
  Err: string;
begin
  if ValidateText(Err) then
    ModalResult := mrOk
  else if MessageDlg('Expressao invalida:'#13#10 + Err + #13#10#13#10 +
    'Salvar assim mesmo?', mtWarning, [mbYes, mbNo], 0) = mrYes then
    ModalResult := mrOk
  else
    DoValidate(nil); // mostra o erro e continua editando
end;

procedure TrhExprEditorForm.DoCancel(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

end.
