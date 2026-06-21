program HelmCalib;

uses
  Vcl.Forms,
  uMatrix in 'src\uMatrix.pas',
  uCoils in 'src\uCoils.pas',
  uSensor in 'src\uSensor.pas',
  uCalib in 'src\uCalib.pas',
  uField in 'src\uField.pas',
  uView3D in 'src\uView3D.pas',
  uMainForm in 'src\uMainForm.pas' {frmMain};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'HelmCalib';
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
