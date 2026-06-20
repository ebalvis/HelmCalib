unit uField;

{ Programación de campo en lazo abierto (sin realimentación del magnetómetro).

  Dado un campo objetivo B en marco bobina (µT), y el modelo calibrado
  (G, Ginv, R, b de uCalib):
    b_coil = Rᵀ·b                         (offset ambiente en marco bobina)
    I_ideal = Ginv·(B_coil_target − b_coil)
    I = clamp(I_ideal, ±I_max)            (por eje; avisa si satura)
    B_logrado_coil = G·I + b_coil          (lo que realmente se generaría)

  El cálculo (FieldSolve/FieldSolveCal) es puro y testeable. El envío a las
  fuentes (TFieldController) usa uCoils. }

{$mode objfpc}{$H+}

interface

uses
  uMatrix, uCalib, uCoils;

type
  TFieldSolution = record
    Target: TVec3;              // B objetivo (marco bobina, µT)
    IDeal: TVec3;               // corrientes sin clamp (A)
    I: TVec3;                   // corrientes aplicadas tras clamp (A)
    Sat: array[0..2] of Boolean;// saturación por eje
    AnySat: Boolean;
    Achieved: TVec3;            // B logrado en marco bobina con I (µT)
  end;

{ Núcleo puro: modelo (G, Ginv, R, b) + límite de corriente por eje. }
function FieldSolve(const G, Ginv, R: TMat3; const b: TVec3; IMax: Double;
  const BcoilTarget: TVec3): TFieldSolution;

{ Sobre una calibración ajustada. False si cal no está Fitted. }
function FieldSolveCal(cal: TCalibration; const BcoilTarget: TVec3;
  out sol: TFieldSolution): Boolean;

type
  { Conecta la solución con las fuentes. No es dueño de cal ni coils. }
  TFieldController = class
  private
    FCal: TCalibration;
    FCoils: TCoilClient;
  public
    constructor Create(ACal: TCalibration; ACoils: TCoilClient);
    function Solve(const BcoilTarget: TVec3; out sol: TFieldSolution): Boolean;
    { Envía las corrientes de sol a los 3 ejes y activa salidas. }
    function Apply(const sol: TFieldSolution): Boolean;
    { Solve + Apply. }
    function ProgramField(const BcoilTarget: TVec3; out sol: TFieldSolution): Boolean;
    function AllOff: Boolean;
  end;

implementation

function ClampAxis(v, vmax: Double; out saturated: Boolean): Double;
begin
  saturated := False;
  if v > vmax then begin saturated := True; Exit(vmax); end;
  if v < -vmax then begin saturated := True; Exit(-vmax); end;
  Result := v;
end;

function FieldSolve(const G, Ginv, R: TMat3; const b: TVec3; IMax: Double;
  const BcoilTarget: TVec3): TFieldSolution;
var
  bcoil, rhs: TVec3;
  k: Integer;
begin
  Result.Target := BcoilTarget;
  bcoil := Mat3MulVec(Mat3Transpose(R), b);     // Rᵀ·b
  rhs := Vec3Sub(BcoilTarget, bcoil);
  Result.IDeal := Mat3MulVec(Ginv, rhs);

  Result.AnySat := False;
  for k := 0 to 2 do
  begin
    Result.I[k] := ClampAxis(Result.IDeal[k], IMax, Result.Sat[k]);
    if Result.Sat[k] then Result.AnySat := True;
  end;

  // campo realmente generado con la corriente aplicada (marco bobina)
  Result.Achieved := Vec3Add(Mat3MulVec(G, Result.I), bcoil);
end;

function FieldSolveCal(cal: TCalibration; const BcoilTarget: TVec3;
  out sol: TFieldSolution): Boolean;
begin
  if (cal = nil) or not cal.Fitted then Exit(False);
  sol := FieldSolve(cal.G, cal.Ginv, cal.R, cal.b, cal.Model.IMaxPerAxis, BcoilTarget);
  Result := True;
end;

{ ---- TFieldController ---- }

constructor TFieldController.Create(ACal: TCalibration; ACoils: TCoilClient);
begin
  inherited Create;
  FCal := ACal;
  FCoils := ACoils;
end;

function TFieldController.Solve(const BcoilTarget: TVec3; out sol: TFieldSolution): Boolean;
begin
  Result := FieldSolveCal(FCal, BcoilTarget, sol);
end;

function TFieldController.Apply(const sol: TFieldSolution): Boolean;
var ch: Integer; ok: Boolean;
begin
  if (FCoils = nil) or not FCoils.Connected then Exit(False);
  ok := True;
  for ch := 1 to 3 do
  begin
    ok := FCoils.SetCurrent(ch, sol.I[ch - 1]) and ok;
    ok := FCoils.Output(ch, True) and ok;
  end;
  Result := ok;
end;

function TFieldController.ProgramField(const BcoilTarget: TVec3;
  out sol: TFieldSolution): Boolean;
begin
  Result := Solve(BcoilTarget, sol) and Apply(sol);
end;

function TFieldController.AllOff: Boolean;
begin
  if (FCoils = nil) or not FCoils.Connected then Exit(False);
  Result := FCoils.AllOff;
end;

end.
