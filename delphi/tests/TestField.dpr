program TestField;

{ Tests de uField: inversa de lazo abierto, clamp y campo logrado (núcleo puro). }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Math, uMatrix, uCalib, uField;

var
  gFail: Integer = 0;
  gPass: Integer = 0;

procedure Check(const name: string; cond: Boolean);
begin
  if cond then begin Inc(gPass); WriteLn('  ok   ', name); end
          else begin Inc(gFail); WriteLn('  FAIL ', name); end;
end;

function Near(const a, b: Double; const eps: Double = 1e-6): Boolean;
begin
  Result := Abs(a - b) <= eps;
end;

function Vec3Near(const a, b: TVec3; const eps: Double = 1e-6): Boolean;
begin
  Result := Near(a[0], b[0], eps) and Near(a[1], b[1], eps) and Near(a[2], b[2], eps);
end;

function Mat3FromRows(const a, b, c, d, e, f, g, h, i: Double): TMat3;
begin
  Result[0,0]:=a; Result[0,1]:=b; Result[0,2]:=c;
  Result[1,0]:=d; Result[1,1]:=e; Result[1,2]:=f;
  Result[2,0]:=g; Result[2,1]:=h; Result[2,2]:=i;
end;

function RotZYX(const rz, ry, rx: Double): TMat3;
var Rz_, Ry_, Rx_: TMat3;
begin
  Rz_ := Mat3FromRows(Cos(rz), -Sin(rz), 0,  Sin(rz), Cos(rz), 0,  0, 0, 1);
  Ry_ := Mat3FromRows(Cos(ry), 0, Sin(ry),  0, 1, 0,  -Sin(ry), 0, Cos(ry));
  Rx_ := Mat3FromRows(1, 0, 0,  0, Cos(rx), -Sin(rx),  0, Sin(rx), Cos(rx));
  Result := Mat3Mult(Mat3Mult(Rz_, Ry_), Rx_);
end;

var
  R0, G0, M0: TMat3;
  b0: TVec3;
  amps: array[0..12] of TVec3;
  cal: TCalibration;
  i: Integer;
  sol: TFieldSolution;
  target, Iexp: TVec3;
  G, Ginv, Rid: TMat3;

begin
  WriteLn('=== Tests uField ===');

  R0 := RotZYX(0.25, -0.15, 0.4);
  G0 := Mat3FromRows(24.8, 0.5, 0.3,  0.5, 25.3, 0.2,  0.3, 0.2, 25.1);
  M0 := Mat3Mult(R0, G0);
  b0 := Vec3(30.0, -12.0, 45.0);

  amps[0]  := Vec3( 0,  0,  0);
  amps[1]  := Vec3( 5,  0,  0);  amps[2]  := Vec3(-5,  0,  0);
  amps[3]  := Vec3( 0,  5,  0);  amps[4]  := Vec3( 0, -5,  0);
  amps[5]  := Vec3( 0,  0,  5);  amps[6]  := Vec3( 0,  0, -5);
  amps[7]  := Vec3( 4,  4,  0);  amps[8]  := Vec3( 4,  0,  4);
  amps[9]  := Vec3( 0,  4,  4);  amps[10] := Vec3( 3,  3,  3);
  amps[11] := Vec3(-3,  2, -4);  amps[12] := Vec3( 2, -3,  4);

  cal := TCalibration.Create(cmModelA);   // Imax 40 A
  try
    WriteLn('Sin ajustar:');
    Check('FieldSolveCal -> false', not FieldSolveCal(cal, Vec3(100, 0, 0), sol));

    for i := 0 to 12 do
      cal.AddPoint(amps[i], Vec3Add(Mat3MulVec(M0, amps[i]), b0));
    Check('ajusta', cal.Fit);

    WriteLn('Objetivo alcanzable (sin saturar):');
    // objetivo = campo que generaría I=(2,-1,1.5) A  -> debe recuperar esa I
    Iexp := Vec3(2.0, -1.0, 1.5);
    target := Vec3Add(Mat3MulVec(M0, Iexp), b0);   // B en marco SENSOR...
    // ...lo paso a marco bobina: B_coil = Rᵀ·B_s
    target := Mat3MulVec(Mat3Transpose(R0), target);
    Check('resuelve', FieldSolveCal(cal, target, sol));
    Check('I = corriente esperada', Vec3Near(sol.I, Iexp, 1e-6));
    Check('sin saturación', not sol.AnySat);
    Check('B logrado = objetivo', Vec3Near(sol.Achieved, target, 1e-6));

    WriteLn('Objetivo que satura (campo enorme):');
    Check('resuelve', FieldSolveCal(cal, Vec3(1e6, 0, 0), sol));
    Check('satura algún eje', sol.AnySat);
    Check('|I| <= Imax por eje',
      (Abs(sol.I[0]) <= cal.Model.IMaxPerAxis + 1e-9) and
      (Abs(sol.I[1]) <= cal.Model.IMaxPerAxis + 1e-9) and
      (Abs(sol.I[2]) <= cal.Model.IMaxPerAxis + 1e-9));
    Check('B logrado != objetivo', not Vec3Near(sol.Achieved, Vec3(1e6, 0, 0), 1.0));
  finally
    cal.Free;
  end;

  WriteLn('Núcleo puro (clamp simétrico, sin offset/rotación):');
  Rid := Mat3Identity;
  G := Mat3FromRows(10, 0, 0,  0, 10, 0,  0, 0, 10);   // 10 µT/A diagonal
  Mat3Inverse(G, Ginv);
  // objetivo 50 µT en X -> 5 A (dentro de 40); -500 µT en Y -> -50 -> clamp a -40
  sol := FieldSolve(G, Ginv, Rid, Vec3(0, 0, 0), 40.0, Vec3(50, -500, 0));
  Check('X: 5 A', Near(sol.I[0], 5.0));
  Check('X no satura', not sol.Sat[0]);
  Check('Y: clamp a -40 A', Near(sol.I[1], -40.0));
  Check('Y satura', sol.Sat[1]);
  Check('Z: 0 A', Near(sol.I[2], 0.0));
  Check('Achieved X = 50', Near(sol.Achieved[0], 50.0));
  Check('Achieved Y = -400 (saturado)', Near(sol.Achieved[1], -400.0));

  WriteLn;
  WriteLn(Format('Resultado: %d ok, %d fallos', [gPass, gFail]));
  Halt(gFail);
end.
