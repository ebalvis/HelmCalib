unit uMainForm;

{ Formulario principal de HelmCalib: pestañas Conexión · Calibración ·
  Programar campo · Vista 3D. En esta fase la pestaña Conexión está operativa
  (TCP a HelmMagControl + UDP a SensorCast con lecturas en vivo); las demás son
  marcadores de posición. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls,
  ExtCtrls, uMatrix, uCoils, uSensor;

type

  { TfrmMain }

  TfrmMain = class(TForm)
    PageControl1: TPageControl;
    tabConn: TTabSheet;
    tabCalib: TTabSheet;
    tabField: TTabSheet;
    tabView: TTabSheet;
    Timer1: TTimer;
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
    // --- placeholders ---
    lblCalibTodo: TLabel;
    lblFieldTodo: TLabel;
    lblViewTodo: TLabel;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnCoilsConnClick(Sender: TObject);
    procedure btnPingClick(Sender: TObject);
    procedure btnSensorConnClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    FCoils: TCoilClient;
    FSensor: TSensorClient;
    procedure UpdateCoilsUI;
    procedure UpdateSensorUI;
    procedure RefreshCoils;
    procedure RefreshSensor;
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FCoils := TCoilClient.Create(2000);
  FSensor := nil;
  PageControl1.ActivePage := tabConn;
  UpdateCoilsUI;
  UpdateSensorUI;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  Timer1.Enabled := False;
  if Assigned(FSensor) then
  begin
    FSensor.Terminate;
    FSensor.WaitFor;
    FreeAndNil(FSensor);
  end;
  FreeAndNil(FCoils);
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
var
  data: TCoilReadAll;
  ch: Integer;
  ejes: array[1..3] of string = ('X', 'Y', 'Z');
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
         BoolToStr(data[ch].Output, 'ON', 'OFF')]);
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

procedure TfrmMain.Timer1Timer(Sender: TObject);
begin
  RefreshCoils;
  RefreshSensor;
end;

end.
