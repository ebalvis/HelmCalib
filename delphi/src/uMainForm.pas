unit uMainForm;

{ Formulario principal de HelmCalib: pestañas Conexión · Calibración ·
  Programar campo · Vista 3D.

  Port a Delphi (VCL/Win64). }

interface

uses
  System.Classes, System.SysUtils, System.StrUtils, System.UITypes,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.ExtCtrls, uMatrix, uCoils, uSensor, uCalib, uField, uView3D, uRemote;

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
    // --- Servidor remoto ---
    gbRemote: TGroupBox;
    lblRemotePort: TLabel;
    edtRemotePort: TEdit;
    chkRemote: TCheckBox;
    lblRemoteStatus: TLabel;
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
    procedure chkRemoteClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    FCoils: TCoilClient;
    FSensor: TSensorClient;
    FView3D: TView3DPanel;
    FCalib: TCalibration;
    FLastSol: TFieldSolution;
    FHasSol: Boolean;
    FRemote: TRemoteServer;
    FSweep: array of TVec3;
    FSweepIdx: Integer;
    FSweeping: Boolean;
    function ProcessRemoteCommand(const Cmd: string): string;
    procedure StartSensor(const ip: string; tx, rx: Integer);
    procedure StopSensor;
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
var
  port: string;
begin
  FCoils := TCoilClient.Create(2000);
  FSensor := nil;

  FView3D := TView3DPanel.Create(Self);
  FView3D.Parent := tabView;
  FView3D.Align := alClient;

  FCalib := TCalibration.Create(cmModelA);
  FCalib.SetNominalModel;   // usable de inmediato con ganancias de catálogo
  FHasSol := False;

  FRemote := TRemoteServer.Create;
  FRemote.OnCommand := ProcessRemoteCommand;

  // controles del servidor remoto (creados en código, al pie de la pestaña Conexión)
  gbRemote := TGroupBox.Create(Self);
  gbRemote.Parent := tabConn;
  gbRemote.SetBounds(8, 428, 816, 56);
  gbRemote.Caption := ' Control remoto (TCP — texto, igual estilo que HelmMagControl) ';
  lblRemotePort := TLabel.Create(Self);
  lblRemotePort.Parent := gbRemote;
  lblRemotePort.SetBounds(16, 24, 44, 15);
  lblRemotePort.Caption := 'Puerto:';
  edtRemotePort := TEdit.Create(Self);
  edtRemotePort.Parent := gbRemote;
  edtRemotePort.SetBounds(66, 20, 70, 23);
  edtRemotePort.Text := '4445';
  chkRemote := TCheckBox.Create(Self);
  chkRemote.Parent := gbRemote;
  chkRemote.SetBounds(160, 22, 200, 19);
  chkRemote.Caption := 'Activar servidor remoto';
  chkRemote.OnClick := chkRemoteClick;
  lblRemoteStatus := TLabel.Create(Self);
  lblRemoteStatus.Parent := gbRemote;
  lblRemoteStatus.SetBounds(380, 24, 60, 15);
  lblRemoteStatus.Caption := 'Parado';
  lblRemoteStatus.Font.Color := clRed;

  PageControl1.ActivePage := tabConn;
  UpdateCoilsUI;
  UpdateSensorUI;
  UpdateModelStatus;
  RefreshPointList;

  // arranque automático del servidor remoto con --remote (puerto opcional --port=N)
  if FindCmdLineSwitch('remote', True) then
  begin
    if FindCmdLineSwitch('port', port) then
      edtRemotePort.Text := port.Trim;
    chkRemote.Checked := True;
    chkRemoteClick(nil);
  end;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  Timer1.Enabled := False;
  SweepTimer.Enabled := False;
  if Assigned(FRemote) then
  begin
    FRemote.Stop;
    FreeAndNil(FRemote);
  end;
  if Assigned(FCoils) and FCoils.Connected then FCoils.AllOff;
  StopSensor;
  FreeAndNil(FCoils);
  FreeAndNil(FCalib);
end;

procedure TfrmMain.StartSensor(const ip: string; tx, rx: Integer);
begin
  StopSensor;
  FSensor := TSensorClient.Create(ip, tx, rx);
  FSensor.StartClient;
end;

procedure TfrmMain.StopSensor;
begin
  if Assigned(FSensor) then
  begin
    FSensor.Terminate;
    FSensor.WaitFor;
    FreeAndNil(FSensor);
  end;
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
    StopSensor;
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
  StartSensor(Trim(edtIP.Text), tx, rx);
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

{ ---- Servidor remoto ---- }

procedure TfrmMain.chkRemoteClick(Sender: TObject);
var port: Integer;
begin
  if chkRemote.Checked then
  begin
    port := StrToIntDef(Trim(edtRemotePort.Text), 4445);
    try
      FRemote.Start(port);
      lblRemoteStatus.Caption := Format('Escuchando en :%d', [port]);
      lblRemoteStatus.Font.Color := clGreen;
      edtRemotePort.Enabled := False;
    except
      on E: Exception do
      begin
        chkRemote.Checked := False;
        ShowMessage('No se pudo abrir el puerto ' + IntToStr(port) + ': ' + E.Message);
      end;
    end;
  end
  else
  begin
    FRemote.Stop;
    lblRemoteStatus.Caption := 'Parado';
    lblRemoteStatus.Font.Color := clRed;
    edtRemotePort.Enabled := True;
  end;
end;

function TfrmMain.ProcessRemoteCommand(const Cmd: string): string;
var
  inv: TFormatSettings;
  t: TArray<string>;
  up, verb, rest: string;
  sol: TFieldSolution;
  data: TCoilReadAll;
  smp: TSensorSample;
  v, b: TVec3;
  ctrl: TFieldController;
  age, k, port, ch: Integer;
  mk: TCoilModelKind;

  function FF(const d: Double): string;
  begin
    Result := FloatToStrF(d, ffGeneral, 7, 0, inv);
  end;

  function V3(const w: TVec3): string;
  begin
    Result := FF(w[0]) + ' ' + FF(w[1]) + ' ' + FF(w[2]);
  end;

  function OnOff(b: Boolean): string;
  begin
    if b then Result := 'on' else Result := 'off';
  end;

  function ArgF(i: Integer): Double;
  begin
    Result := ParseFloatDot(t[i]);
  end;

begin
  inv := TFormatSettings.Invariant;
  if Cmd = '' then Exit('ERROR Empty');
  t := Cmd.Split([' '], TStringSplitOptions.ExcludeEmpty);
  up := UpperCase(Cmd);
  verb := UpperCase(t[0]);

  if verb = 'PING' then Exit('OK PONG HelmCalib 0.1');

  if verb = 'HELP' then
    Exit('OK PING|STATUS|CONNECT COILS h p|CONNECT SENSOR ip [tx rx]|DISCONNECT COILS|'
      + 'SENSOR|GET MAG|GET MAGAVG k|READALL|MODEL NOMINAL A|B|LOAD PROFILE path|'
      + 'SAVE PROFILE path|GET MODEL|SOLVE bx by bz|SETFIELD bx by bz|'
      + 'SETCURRENTS i1 i2 i3|FIELDOFF|CALIB CLEAR|CALIB ADD ix iy iz bx by bz|'
      + 'CALIB COUNT|CALIB FIT');

  if verb = 'STATUS' then
  begin
    if FCalib.Fitted then
      verb := 'ready(' + CoilModelKindToStr(FCalib.Model.Kind) + ')'
    else
      verb := 'none';
    Exit(Format('OK COILS %s SENSOR %s MODEL %s RMS %s',
      [OnOff(FCoils.Connected), OnOff(Assigned(FSensor)), verb, FF(FCalib.ResidualRMS)]));
  end;

  // CONNECT COILS host port  |  CONNECT SENSOR ip [tx] [rx]
  if (verb = 'CONNECT') and (Length(t) >= 2) then
  begin
    if SameText(t[1], 'COILS') then
    begin
      if Length(t) < 4 then Exit('ERROR Usage: CONNECT COILS host port');
      port := StrToIntDef(t[3], 4444);
      if FCoils.Connect(t[2], port) then
      begin UpdateCoilsUI; Exit('OK COILS connected'); end
      else Exit('ERROR ConnectFailed');
    end;
    if SameText(t[1], 'SENSOR') then
    begin
      if Length(t) < 3 then Exit('ERROR Usage: CONNECT SENSOR ip [tx] [rx]');
      StartSensor(t[2], StrToIntDef(t[3], 51042), StrToIntDef(t[4], 51043));
      UpdateSensorUI;
      Exit('OK SENSOR listening');
    end;
    Exit('ERROR Usage: CONNECT COILS|SENSOR ...');
  end;

  if (verb = 'DISCONNECT') and (Length(t) >= 2) then
  begin
    if SameText(t[1], 'COILS') then begin FCoils.Disconnect; UpdateCoilsUI; Exit('OK'); end;
    if SameText(t[1], 'SENSOR') then begin StopSensor; UpdateSensorUI; Exit('OK'); end;
    Exit('ERROR Usage: DISCONNECT COILS|SENSOR');
  end;

  // GET MAG | GET MAGAVG k
  if (verb = 'GET') and (Length(t) >= 2) and SameText(t[1], 'MAG') then
  begin
    if not Assigned(FSensor) then Exit('ERROR NoSensor');
    if not FSensor.GetLatest(smp, age) then Exit('ERROR NoSample');
    Exit('OK MAG ' + V3(smp.Mag));
  end;
  if (verb = 'GET') and (Length(t) >= 3) and SameText(t[1], 'MAGAVG') then
  begin
    if not Assigned(FSensor) then Exit('ERROR NoSensor');
    k := StrToIntDef(t[2], 10);
    if not FSensor.GetAveragedMag(k, v) then Exit('ERROR NoSample');
    Exit('OK MAGAVG ' + V3(v));
  end;
  if (verb = 'GET') and (Length(t) >= 2) and SameText(t[1], 'MODEL') then
    Exit(Format('OK M %s %s %s %s %s %s %s %s %s B %s RMS %s FITTED %d',
      [FF(FCalib.M[0,0]), FF(FCalib.M[0,1]), FF(FCalib.M[0,2]),
       FF(FCalib.M[1,0]), FF(FCalib.M[1,1]), FF(FCalib.M[1,2]),
       FF(FCalib.M[2,0]), FF(FCalib.M[2,1]), FF(FCalib.M[2,2]),
       V3(FCalib.b), FF(FCalib.ResidualRMS), Ord(FCalib.Fitted)]));

  if verb = 'READALL' then
  begin
    if not FCoils.Connected then Exit('ERROR CoilsNotConnected');
    if not FCoils.ReadAll(data) then Exit('ERROR ReadFailed');
    Exit(Format('OK CH1 V=%s I=%s OUT=%s CH2 V=%s I=%s OUT=%s CH3 V=%s I=%s OUT=%s',
      [FF(data[1].Volt), FF(data[1].Curr), OnOff(data[1].Output),
       FF(data[2].Volt), FF(data[2].Curr), OnOff(data[2].Output),
       FF(data[3].Volt), FF(data[3].Curr), OnOff(data[3].Output)]));
  end;

  // MODEL NOMINAL A|B
  if (verb = 'MODEL') and (Length(t) >= 3) and SameText(t[1], 'NOMINAL') then
  begin
    if SameText(t[2], 'B') then mk := cmModelB else mk := cmModelA;
    FCalib.SetModel(mk);
    FCalib.SetNominalModel;
    UpdateModelStatus;
    Exit('OK MODEL nominal' + CoilModelKindToStr(mk));
  end;

  // LOAD/SAVE PROFILE <path con posibles espacios>
  if (verb = 'LOAD') and (Length(t) >= 3) and SameText(t[1], 'PROFILE') then
  begin
    rest := Trim(Copy(Cmd, Pos('PROFILE', up) + 8, MaxInt));
    if FCalib.LoadFromFile(rest) then
    begin UpdateModelStatus; RefreshPointList; Exit('OK loaded'); end
    else Exit('ERROR LoadFailed');
  end;
  if (verb = 'SAVE') and (Length(t) >= 3) and SameText(t[1], 'PROFILE') then
  begin
    rest := Trim(Copy(Cmd, Pos('PROFILE', up) + 8, MaxInt));
    if FCalib.SaveToFile(rest) then Exit('OK saved') else Exit('ERROR SaveFailed');
  end;

  // SOLVE / SETFIELD bx by bz
  if (verb = 'SOLVE') or (verb = 'SETFIELD') then
  begin
    if Length(t) < 4 then Exit('ERROR Usage: ' + verb + ' bx by bz');
    b := Vec3(ArgF(1), ArgF(2), ArgF(3));
    if not FieldSolveCal(FCalib, b, sol) then Exit('ERROR NoModel');
    FView3D.SetTarget(b);
    if verb = 'SETFIELD' then
    begin
      if not FCoils.Connected then Exit('ERROR CoilsNotConnected');
      ctrl := TFieldController.Create(FCalib, FCoils);
      try
        if not ctrl.Apply(sol) then Exit('ERROR SendFailed');
      finally
        ctrl.Free;
      end;
    end;
    Exit(Format('OK I %s SAT %d ACHIEVED %s',
      [V3(sol.I), Ord(sol.AnySat), V3(sol.Achieved)]));
  end;

  if verb = 'SETCURRENTS' then
  begin
    if Length(t) < 4 then Exit('ERROR Usage: SETCURRENTS i1 i2 i3');
    if not FCoils.Connected then Exit('ERROR CoilsNotConnected');
    for ch := 1 to 3 do
    begin
      FCoils.SetCurrent(ch, ArgF(ch));
      FCoils.Output(ch, True);
    end;
    Exit('OK');
  end;

  if verb = 'FIELDOFF' then
  begin
    if not FCoils.Connected then Exit('ERROR CoilsNotConnected');
    if FCoils.AllOff then Exit('OK') else Exit('ERROR');
  end;

  // CALIB ...
  if verb = 'CALIB' then
  begin
    if (Length(t) >= 2) and SameText(t[1], 'CLEAR') then
    begin FCalib.ClearPoints; RefreshPointList; UpdateModelStatus; Exit('OK COUNT 0'); end;
    if (Length(t) >= 2) and SameText(t[1], 'COUNT') then
      Exit(Format('OK COUNT %d', [FCalib.PointCount]));
    if (Length(t) >= 2) and SameText(t[1], 'ADD') then
    begin
      if Length(t) < 8 then Exit('ERROR Usage: CALIB ADD ix iy iz bx by bz');
      v := Vec3(ArgF(2), ArgF(3), ArgF(4));
      b := Vec3(ArgF(5), ArgF(6), ArgF(7));
      FCalib.AddPoint(v, b);
      RefreshPointList;
      Exit(Format('OK COUNT %d', [FCalib.PointCount]));
    end;
    if (Length(t) >= 2) and SameText(t[1], 'FIT') then
    begin
      if FCalib.Fit then
      begin UpdateModelStatus; Exit('OK RMS ' + FF(FCalib.ResidualRMS)); end
      else Exit('ERROR FitFailed');
    end;
    Exit('ERROR Usage: CALIB CLEAR|ADD|COUNT|FIT');
  end;

  Result := 'ERROR UnknownCommand';
end;

procedure TfrmMain.Timer1Timer(Sender: TObject);
begin
  RefreshCoils;
  RefreshSensor;
  RefreshView3D;
end;

end.
