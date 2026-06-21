unit uMainForm;

{ Formulario principal de HelmCalib: pestañas Conexión · Calibración ·
  Programar campo · Vista 3D.

  Port a Delphi (VCL/Win64). }

interface

uses
  System.Classes, System.SysUtils, System.StrUtils, System.UITypes,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.ExtCtrls, uMatrix, uCoils, uSensor, uCalib, uField, uView3D;

type

  { TfrmMain }

  TfrmMain = class(TForm)
    PageControl1: TPageControl;
    tabConn: TTabSheet;
    tabCalib: TTabSheet;
    tabField: TTabSheet;
    tabView: TTabSheet;
    Timer1: TTimer;
    SweepTimer: TTimer;
    // --- Bobinas (TCP) ---
    gbCoils: TGroupBox;
    lblHost: TLabel;
    edtHost: TEdit;
    lblPort: TLabel;
    edtPort: TEdit;
    btnCoilsConn: TButton;
    btnPing: TButton;
    lblCoilsStatus: TLabel;
    mCoils: TMemo;
    // --- Sensor (UDP) ---
    gbSensor: TGroupBox;
    lblIP: TLabel;
    edtIP: TEdit;
    lblTx: TLabel;
    edtTx: TEdit;
    lblRx: TLabel;
    edtRx: TEdit;
    btnSensorConn: TButton;
    lblSensorStatus: TLabel;
    lblK: TLabel;
    edtK: TEdit;
    mSensor: TMemo;
    // --- Calibración (asistente) ---
    lblSweepHdr: TLabel;
    lblI0: TLabel;
    edtI0: TEdit;
    lblKc: TLabel;
    edtKc: TEdit;
    lblSettle: TLabel;
    edtSettle: TEdit;
    btnStartSweep: TButton;
    btnStopSweep: TButton;
    lblSweepProg: TLabel;
    lblManualHdr: TLabel;
    btnCapture: TButton;
    btnRemovePoint: TButton;
    btnClearPoints: TButton;
    btnFit: TButton;
    lblFitResult: TLabel;
    btnSaveProfile: TButton;
    lblCalStatus: TLabel;
    lblPointsHdr: TLabel;
    lstPoints: TListBox;
    // --- Programar campo ---
    lblModelHdr: TLabel;
    cmbModel: TComboBox;
    btnNominal: TButton;
    btnLoadProfile: TButton;
    lblModelStatus: TLabel;
    lblBHdr: TLabel;
    lblBX: TLabel;
    edtBX: TEdit;
    lblBY: TLabel;
    edtBY: TEdit;
    lblBZ: TLabel;
    edtBZ: TEdit;
    btnCalcField: TButton;
    btnSendField: TButton;
    btnFieldOff: TButton;
    mField: TMemo;
    // --- Vista 3D ---
    pnlViewCtrl: TPanel;
    lblViewHdr: TLabel;
    lblVX: TLabel;
    edtVX: TEdit;
    lblVY: TLabel;
    edtVY: TEdit;
    lblVZ: TLabel;
    edtVZ: TEdit;
    btnAplicarVec: TButton;
    chkVecSensor: TCheckBox;
    lblVMod: TLabel;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnCoilsConnClick(Sender: TObject);
    procedure btnPingClick(Sender: TObject);
    procedure btnSensorConnClick(Sender: TObject);
    procedure btnAplicarVecClick(Sender: TObject);
    procedure chkVecSensorClick(Sender: TObject);
    procedure btnNominalClick(Sender: TObject);
    procedure btnLoadProfileClick(Sender: TObject);
    procedure btnCalcFieldClick(Sender: TObject);
    procedure btnSendFieldClick(Sender: TObject);
    procedure btnFieldOffClick(Sender: TObject);
    procedure btnStartSweepClick(Sender: TObject);
    procedure btnStopSweepClick(Sender: TObject);
    procedure btnCaptureClick(Sender: TObject);
    procedure btnRemovePointClick(Sender: TObject);
    procedure btnClearPointsClick(Sender: TObject);
    procedure btnFitClick(Sender: TObject);
    procedure btnSaveProfileClick(Sender: TObject);
    procedure SweepTimerTimer(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    FCoils: TCoilClient;
    FSensor: TSensorClient;
    FView3D: TView3DPanel;
    FCalib: TCalibration;
    FLastSol: TFieldSolution;
    FHasSol: Boolean;
    FSweep: array of TVec3;
    FSweepIdx: Integer;
    FSweeping: Boolean;
    procedure UpdateCoilsUI;
    procedure UpdateSensorUI;
    procedure RefreshCoils;
    procedure RefreshSensor;
    procedure ApplyManualVector;
    procedure RefreshView3D;
    procedure UpdateModelStatus;
    function ReadTargetField: TVec3;
    procedure BuildSweep(I0: Double);
    procedure RefreshPointList;
    procedure SetSweepCurrents(const v: TVec3);
    procedure SweepSetUI(running: Boolean);
    function SensorAndCoilsReady: Boolean;
  public
  end;

function ParseFloatDot(const s: string; def: Double = 0): Double;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

function ParseFloatDot(const s: string; def: Double): Double;
var fs: TFormatSettings;
begin
  fs := TFormatSettings.Invariant;
  Result := StrToFloatDef(StringReplace(Trim(s), ',', '.', []), def, fs);
end;

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FCoils := TCoilClient.Create(2000);
  FSensor := nil;

  FView3D := TView3DPanel.Create(Self);
  FView3D.Parent := tabView;
  FView3D.Align := alClient;

  FCalib := TCalibration.Create(cmModelA);
  FCalib.SetNominalModel;   // usable de inmediato con ganancias de catálogo
  FHasSol := False;

  PageControl1.ActivePage := tabConn;
  UpdateCoilsUI;
  UpdateSensorUI;
  UpdateModelStatus;
  RefreshPointList;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  Timer1.Enabled := False;
  SweepTimer.Enabled := False;
  if Assigned(FCoils) and FCoils.Connected then FCoils.AllOff;
  if Assigned(FSensor) then
  begin
    FSensor.Terminate;
    FSensor.WaitFor;
    FreeAndNil(FSensor);
  end;
  FreeAndNil(FCoils);
  FreeAndNil(FCalib);
end;

procedure TfrmMain.UpdateCoilsUI;
begin
  if FCoils.Connected then
  begin
    lblCoilsStatus.Caption := 'Conectado';
    lblCoilsStatus.Font.Color := clGreen;
    btnCoilsConn.Caption := 'Desconectar';
    btnPing.Enabled := True;
  end
  else
  begin
    lblCoilsStatus.Caption := 'Desconectado';
    lblCoilsStatus.Font.Color := clRed;
    btnCoilsConn.Caption := 'Conectar';
    btnPing.Enabled := False;
    mCoils.Clear;
  end;
end;

procedure TfrmMain.UpdateSensorUI;
begin
  if Assigned(FSensor) then
  begin
    lblSensorStatus.Caption := 'Escuchando';
    lblSensorStatus.Font.Color := clGreen;
    btnSensorConn.Caption := 'Desconectar';
  end
  else
  begin
    lblSensorStatus.Caption := 'Desconectado';
    lblSensorStatus.Font.Color := clRed;
    btnSensorConn.Caption := 'Conectar';
    mSensor.Clear;
  end;
end;

procedure TfrmMain.btnCoilsConnClick(Sender: TObject);
var port: Integer;
begin
  if FCoils.Connected then
  begin
    FCoils.Disconnect;
    UpdateCoilsUI;
    Exit;
  end;
  port := StrToIntDef(Trim(edtPort.Text), 4444);
  if FCoils.Connect(Trim(edtHost.Text), port) then
  begin
    if not FCoils.Ping then
      ShowMessage('Conectado pero el PING no respondió OK PONG.');
  end
  else
    ShowMessage('No se pudo conectar a ' + edtHost.Text + ':' + IntToStr(port));
  UpdateCoilsUI;
end;

procedure TfrmMain.btnPingClick(Sender: TObject);
begin
  if FCoils.Ping then
    ShowMessage('PING OK')
  else
    ShowMessage('PING sin respuesta');
end;

procedure TfrmMain.btnSensorConnClick(Sender: TObject);
var tx, rx: Integer;
begin
  if Assigned(FSensor) then
  begin
    FSensor.Terminate;
    FSensor.WaitFor;
    FreeAndNil(FSensor);
    UpdateSensorUI;
    Exit;
  end;
  if Trim(edtIP.Text) = '' then
  begin
    ShowMessage('Indica la IP del móvil.');
    Exit;
  end;
  tx := StrToIntDef(Trim(edtTx.Text), 51042);
  rx := StrToIntDef(Trim(edtRx.Text), 51043);
  FSensor := TSensorClient.Create(Trim(edtIP.Text), tx, rx);
  FSensor.StartClient;
  UpdateSensorUI;
end;

procedure TfrmMain.RefreshCoils;
const
  ejes: array[1..3] of string = ('X', 'Y', 'Z');
var
  data: TCoilReadAll;
  ch: Integer;
  s: string;
begin
  if not FCoils.Connected then Exit;
  if not FCoils.ReadAll(data) then
  begin
    // se cayó la conexión
    FCoils.Disconnect;
    UpdateCoilsUI;
    Exit;
  end;
  s := '';
  for ch := 1 to 3 do
    if data[ch].Valid then
      s := s + Format('%s (CH%d):  V=%.3f V   I=%.3f A   OUT=%s'#13#10,
        [ejes[ch], ch, data[ch].Volt, data[ch].Curr,
         IfThen(data[ch].Output, 'ON', 'OFF')]);
  mCoils.Text := s;
end;

procedure TfrmMain.RefreshSensor;
var
  smp: TSensorSample;
  age: Integer;
  avg: TVec3;
  k: Integer;
  s: string;
begin
  if not Assigned(FSensor) then Exit;
  if not FSensor.GetLatest(smp, age) then
  begin
    mSensor.Text := 'Esperando datos del móvil…';
    Exit;
  end;
  k := StrToIntDef(Trim(edtK.Text), 10);
  s := Format('Magnetómetro (µT):  X=%.2f  Y=%.2f  Z=%.2f'#13#10,
    [smp.Mag[0], smp.Mag[1], smp.Mag[2]]);
  s := s + Format('|B| = %.2f µT'#13#10, [Vec3Norm(smp.Mag)]);
  if FSensor.GetAveragedMag(k, avg) then
    s := s + Format('Media K=%d:  X=%.2f  Y=%.2f  Z=%.2f'#13#10,
      [k, avg[0], avg[1], avg[2]]);
  if smp.HasAcc then
    s := s + Format('Acelerómetro:  X=%.2f  Y=%.2f  Z=%.2f'#13#10,
      [smp.Acc[0], smp.Acc[1], smp.Acc[2]]);
  s := s + Format('Antigüedad: %d ms', [age]);
  if age > 1500 then s := s + '  (¡sin datos recientes!)';
  mSensor.Text := s;
end;

procedure TfrmMain.ApplyManualVector;
var v: TVec3;
begin
  v[0] := ParseFloatDot(edtVX.Text);
  v[1] := ParseFloatDot(edtVY.Text);
  v[2] := ParseFloatDot(edtVZ.Text);
  FView3D.SetTarget(v);
  lblVMod.Caption := Format('|B| = %.1f µT', [Vec3Norm(v)]);
end;

procedure TfrmMain.btnAplicarVecClick(Sender: TObject);
begin
  chkVecSensor.Checked := False;
  ApplyManualVector;
end;

procedure TfrmMain.chkVecSensorClick(Sender: TObject);
begin
  edtVX.Enabled := not chkVecSensor.Checked;
  edtVY.Enabled := not chkVecSensor.Checked;
  edtVZ.Enabled := not chkVecSensor.Checked;
  btnAplicarVec.Enabled := not chkVecSensor.Checked;
  if not chkVecSensor.Checked then
    ApplyManualVector;
end;

procedure TfrmMain.RefreshView3D;
var avg: TVec3;
begin
  if not chkVecSensor.Checked then Exit;
  if not Assigned(FSensor) then Exit;
  if FSensor.GetAveragedMag(StrToIntDef(Trim(edtK.Text), 10), avg) then
  begin
    FView3D.SetTarget(avg);
    lblVMod.Caption := Format('|B| = %.1f µT', [Vec3Norm(avg)]);
    edtVX.Text := Format('%.1f', [avg[0]]);
    edtVY.Text := Format('%.1f', [avg[1]]);
    edtVZ.Text := Format('%.1f', [avg[2]]);
  end;
end;

procedure TfrmMain.UpdateModelStatus;
begin
  if FCalib.Fitted then
    lblModelStatus.Caption := Format(
      'Modelo: %s · residuo RMS=%.2f µT · I_max=%.0f A · B_max=%.0f µT',
      [FCalib.Model.Name, FCalib.ResidualRMS, FCalib.Model.IMaxPerAxis,
       FCalib.Model.BMaxPerAxis])
  else
    lblModelStatus.Caption := 'Modelo: sin definir (usa "Modelo nominal" o "Cargar perfil…")';
end;

function TfrmMain.ReadTargetField: TVec3;
begin
  Result[0] := ParseFloatDot(edtBX.Text);
  Result[1] := ParseFloatDot(edtBY.Text);
  Result[2] := ParseFloatDot(edtBZ.Text);
end;

procedure TfrmMain.btnNominalClick(Sender: TObject);
begin
  if cmbModel.ItemIndex = 1 then
    FCalib.SetModel(cmModelB)
  else
    FCalib.SetModel(cmModelA);
  FCalib.SetNominalModel;
  FHasSol := False;
  UpdateModelStatus;
end;

procedure TfrmMain.btnLoadProfileClick(Sender: TObject);
var dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := 'Perfil HelmCalib (*.json)|*.json|Todos (*.*)|*.*';
    dlg.DefaultExt := 'json';
    if not dlg.Execute then Exit;
    if FCalib.LoadFromFile(dlg.FileName) then
    begin
      if FCalib.Model.Kind = cmModelB then cmbModel.ItemIndex := 1
      else cmbModel.ItemIndex := 0;
      if not FCalib.Fitted then
        ShowMessage('Perfil cargado, pero sin modelo ajustado (M/b). '
          + 'Ajusta o usa modelo nominal.');
    end
    else
      ShowMessage('No se pudo cargar el perfil: ' + dlg.FileName);
    FHasSol := False;
    UpdateModelStatus;
  finally
    dlg.Free;
  end;
end;

procedure TfrmMain.btnCalcFieldClick(Sender: TObject);
const
  ejes: array[0..2] of string = ('X', 'Y', 'Z');
var
  target, errVec: TVec3;
  s: string;
  k: Integer;
begin
  if not FCalib.Fitted then
  begin
    ShowMessage('No hay modelo de calibración. Define uno primero.');
    Exit;
  end;
  target := ReadTargetField;
  if not FieldSolveCal(FCalib, target, FLastSol) then
  begin
    ShowMessage('No se pudo resolver (modelo singular).');
    Exit;
  end;
  FHasSol := True;
  FView3D.SetTarget(target);   // se verá en la pestaña Vista 3D

  s := Format('Objetivo B (bobina): X=%.2f  Y=%.2f  Z=%.2f µT  (|B|=%.2f)'#13#10#13#10,
    [target[0], target[1], target[2], Vec3Norm(target)]);
  s := s + 'Corrientes calculadas:'#13#10;
  for k := 0 to 2 do
    s := s + Format('  I%s = %+8.3f A  (ideal %+8.3f A)%s'#13#10,
      [ejes[k], FLastSol.I[k], FLastSol.IDeal[k],
       IfThen(FLastSol.Sat[k], '  ¡SATURADO!', '')]);
  if FLastSol.AnySat then
    s := s + #13#10'⚠ Algún eje satura: el campo logrado diferirá del objetivo.'#13#10;
  errVec := Vec3Sub(FLastSol.Achieved, target);
  s := s + Format(#13#10'Campo logrado (bobina): X=%.2f  Y=%.2f  Z=%.2f µT'#13#10,
    [FLastSol.Achieved[0], FLastSol.Achieved[1], FLastSol.Achieved[2]]);
  s := s + Format('Error vs objetivo: %.2f µT', [Vec3Norm(errVec)]);
  mField.Text := s;
  UpdateModelStatus;
end;

procedure TfrmMain.btnSendFieldClick(Sender: TObject);
var ctrl: TFieldController;
begin
  if not FHasSol then
  begin
    ShowMessage('Primero pulsa "Calcular".');
    Exit;
  end;
  if not FCoils.Connected then
  begin
    ShowMessage('Las bobinas no están conectadas (pestaña Conexión).');
    Exit;
  end;
  ctrl := TFieldController.Create(FCalib, FCoils);
  try
    if ctrl.Apply(FLastSol) then
      mField.Lines.Add(#13#10'→ Corrientes enviadas y salidas ON.')
    else
      mField.Lines.Add(#13#10'→ ERROR al enviar a las fuentes.');
  finally
    ctrl.Free;
  end;
end;

procedure TfrmMain.btnFieldOffClick(Sender: TObject);
begin
  if not FCoils.Connected then
  begin
    ShowMessage('Las bobinas no están conectadas.');
    Exit;
  end;
  if FCoils.AllOff then
    mField.Lines.Add(#13#10'→ ALL OFF: salidas desactivadas.')
  else
    mField.Lines.Add(#13#10'→ ERROR en ALL OFF.');
end;

{ ---- Calibración (asistente) ---- }

function TfrmMain.SensorAndCoilsReady: Boolean;
begin
  Result := True;
  if not FCoils.Connected then
  begin
    ShowMessage('Conecta las bobinas (pestaña Conexión).');
    Exit(False);
  end;
  if not Assigned(FSensor) then
  begin
    ShowMessage('Conecta el sensor (pestaña Conexión).');
    Exit(False);
  end;
end;

procedure TfrmMain.BuildSweep(I0: Double);
const
  COMB: array[0..12, 0..2] of Double = (
    ( 0,  0,  0),
    ( 1,  0,  0), (-1,  0,  0),
    ( 0,  1,  0), ( 0, -1,  0),
    ( 0,  0,  1), ( 0,  0, -1),
    ( 1,  1,  0), ( 1,  0,  1), ( 0,  1,  1),
    ( 1,  1,  1), (-1,  1, -1), ( 1, -1,  1));
var
  i, j: Integer;
  imax: Double;
begin
  imax := FCalib.Model.IMaxPerAxis;
  SetLength(FSweep, Length(COMB));
  for i := 0 to High(COMB) do
    for j := 0 to 2 do
    begin
      FSweep[i][j] := COMB[i][j] * I0;
      if FSweep[i][j] > imax then FSweep[i][j] := imax;
      if FSweep[i][j] < -imax then FSweep[i][j] := -imax;
    end;
end;

procedure TfrmMain.SetSweepCurrents(const v: TVec3);
var ch: Integer;
begin
  for ch := 1 to 3 do
  begin
    FCoils.SetCurrent(ch, v[ch - 1]);
    FCoils.Output(ch, True);
  end;
end;

procedure TfrmMain.RefreshPointList;
var
  k: Integer;
  p: TCalibPoint;
begin
  lstPoints.Items.BeginUpdate;
  try
    lstPoints.Clear;
    for k := 0 to FCalib.PointCount - 1 do
      if FCalib.GetPoint(k, p) then
        lstPoints.Items.Add(Format(
          '%2d  I=(%6.2f,%6.2f,%6.2f)  B=(%7.1f,%7.1f,%7.1f)',
          [k, p.I[0], p.I[1], p.I[2], p.B[0], p.B[1], p.B[2]]));
  finally
    lstPoints.Items.EndUpdate;
  end;
  lblManualHdr.Caption := Format('Puntos (%d)', [FCalib.PointCount]);
end;

procedure TfrmMain.SweepSetUI(running: Boolean);
begin
  FSweeping := running;
  btnStartSweep.Enabled := not running;
  btnStopSweep.Enabled := running;
  btnCapture.Enabled := not running;
  btnClearPoints.Enabled := not running;
  btnRemovePoint.Enabled := not running;
  btnFit.Enabled := not running;
  edtI0.Enabled := not running;
  edtKc.Enabled := not running;
  edtSettle.Enabled := not running;
end;

procedure TfrmMain.btnStartSweepClick(Sender: TObject);
var I0, settle: Double;
begin
  if not SensorAndCoilsReady then Exit;
  I0 := ParseFloatDot(edtI0.Text, 0);
  if I0 <= 0 then
  begin
    ShowMessage('Indica una amplitud I0 > 0.');
    Exit;
  end;
  settle := StrToIntDef(Trim(edtSettle.Text), 2000);
  if settle < 300 then settle := 300;

  if FCalib.PointCount > 0 then
    if MessageDlg(
      'Se descartarán los puntos actuales y se empezará un barrido nuevo. ¿Continuar?',
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;

  FCalib.ClearPoints;
  RefreshPointList;
  BuildSweep(I0);
  FSweepIdx := 0;
  SetSweepCurrents(FSweep[0]);
  SweepTimer.Interval := Round(settle);
  SweepTimer.Enabled := True;
  SweepSetUI(True);
  lblSweepProg.Caption := Format('Punto 1/%d (asentando…)', [Length(FSweep)]);
end;

procedure TfrmMain.SweepTimerTimer(Sender: TObject);
var
  mag: TVec3;
  k: Integer;
begin
  if not FSweeping then Exit;
  k := StrToIntDef(Trim(edtKc.Text), 10);
  if not Assigned(FSensor) or not FSensor.GetAveragedMag(k, mag) then
  begin
    SweepTimer.Enabled := False;
    FCoils.AllOff;
    SweepSetUI(False);
    lblSweepProg.Caption := 'Barrido abortado: sin datos del sensor.';
    Exit;
  end;

  FCalib.AddPoint(FSweep[FSweepIdx], mag);
  RefreshPointList;
  Inc(FSweepIdx);

  if FSweepIdx >= Length(FSweep) then
  begin
    SweepTimer.Enabled := False;
    FCoils.AllOff;
    SweepSetUI(False);
    lblSweepProg.Caption := Format('Barrido completo: %d puntos. Pulsa "Ajustar modelo".',
      [FCalib.PointCount]);
  end
  else
  begin
    SetSweepCurrents(FSweep[FSweepIdx]);
    lblSweepProg.Caption := Format('Punto %d/%d (asentando…)',
      [FSweepIdx + 1, Length(FSweep)]);
  end;
end;

procedure TfrmMain.btnStopSweepClick(Sender: TObject);
begin
  SweepTimer.Enabled := False;
  if FCoils.Connected then FCoils.AllOff;
  SweepSetUI(False);
  lblSweepProg.Caption := Format('Detenido (%d puntos).', [FCalib.PointCount]);
end;

procedure TfrmMain.btnCaptureClick(Sender: TObject);
var
  data: TCoilReadAll;
  mag, cur: TVec3;
  k: Integer;
begin
  if not SensorAndCoilsReady then Exit;
  if not FCoils.ReadAll(data) then
  begin
    ShowMessage('No se pudo leer la corriente de las fuentes.');
    Exit;
  end;
  k := StrToIntDef(Trim(edtKc.Text), 10);
  if not FSensor.GetAveragedMag(k, mag) then
  begin
    ShowMessage('Aún no hay lecturas del magnetómetro.');
    Exit;
  end;
  cur[0] := data[1].Curr; cur[1] := data[2].Curr; cur[2] := data[3].Curr;
  FCalib.AddPoint(cur, mag);
  RefreshPointList;
end;

procedure TfrmMain.btnRemovePointClick(Sender: TObject);
begin
  if lstPoints.ItemIndex < 0 then Exit;
  FCalib.RemovePoint(lstPoints.ItemIndex);
  RefreshPointList;
  lblFitResult.Caption := 'Sin ajustar';
  UpdateModelStatus;
end;

procedure TfrmMain.btnClearPointsClick(Sender: TObject);
begin
  FCalib.ClearPoints;
  RefreshPointList;
  lblFitResult.Caption := 'Sin ajustar';
  UpdateModelStatus;
end;

procedure TfrmMain.btnFitClick(Sender: TObject);
begin
  if FCalib.PointCount < 4 then
  begin
    ShowMessage('Hacen falta al menos 4 puntos no coplanares (incluido I=0).');
    Exit;
  end;
  if FCalib.Fit then
  begin
    lblFitResult.Caption := Format('Ajustado: residuo RMS = %.2f µT (%d puntos)',
      [FCalib.ResidualRMS, FCalib.PointCount]);
    UpdateModelStatus;
  end
  else
  begin
    lblFitResult.Caption := 'Ajuste fallido (puntos colineales o insuficientes).';
    ShowMessage('No se pudo ajustar: la matriz es casi singular. '
      + 'Asegura puntos en los 3 ejes y combinaciones.');
  end;
end;

procedure TfrmMain.btnSaveProfileClick(Sender: TObject);
var dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Filter := 'Perfil HelmCalib (*.json)|*.json';
    dlg.DefaultExt := 'json';
    dlg.FileName := 'helmcalib_perfil.json';
    if not dlg.Execute then Exit;
    if FCalib.SaveToFile(dlg.FileName) then
      lblCalStatus.Caption := 'Perfil guardado: ' + dlg.FileName
    else
      ShowMessage('No se pudo guardar el perfil.');
  finally
    dlg.Free;
  end;
end;

procedure TfrmMain.Timer1Timer(Sender: TObject);
begin
  RefreshCoils;
  RefreshSensor;
  RefreshView3D;
end;

end.
