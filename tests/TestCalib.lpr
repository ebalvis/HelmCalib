program TestCalib;

{ Tests de uCalib: ajuste con datos sintéticos (M0=R0·G0, b0) y round-trip JSON. }

{$mode objfpc}{$H+}

uses
  SysUtils, Math, uMatrix, uCalib;

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

function Mat3Near(const a, b: TMat3; const eps: Double = 1e-6): Boolean;
var i, j: Integer;
begin
  for i := 0 to 2 do for j := 0 to 2 do
    if not Near(a[i, j], b[i, j], eps) then Exit(False);
  Result := True;
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
  cal, cal2: TCalibration;
  i: Integer;
  js, tmpFile: string;
  pred, Bk: TVec3;

begin
  WriteLn('=== Tests uCalib ===');

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

  cal := TCalibration.Create(cmModelA);
  try
    WriteLn('Modelo de bobina:');
    Check('A: Imax 40', Near(cal.Model.IMaxPerAxis, 40.0));
    Check('A: Bmax 1000', Near(cal.Model.BMaxPerAxis, 1000.0));

    WriteLn('Ajuste:');
    Check('<4 puntos -> no ajusta', not cal.Fit);
    for i := 0 to 12 do
      cal.AddPoint(amps[i], Vec3Add(Mat3MulVec(M0, amps[i]), b0));
    Check('13 puntos', cal.PointCount = 13);
    Check('ajusta', cal.Fit);
    Check('Fitted', cal.Fitted);
    Check('M recuperada', Mat3Near(cal.M, M0));
    Check('b recuperado', Near(cal.b[0], b0[0]) and Near(cal.b[1], b0[1]) and Near(cal.b[2], b0[2]));
    Check('R recuperada (polar)', Mat3Near(cal.R, R0));
    Check('G recuperada (polar)', Mat3Near(cal.G, G0));
    Check('G·Ginv = I', Mat3Near(Mat3Mult(cal.G, cal.Ginv), Mat3Identity));
    Check('residuo RMS ~ 0', cal.ResidualRMS < 1e-6);

    // Predict reproduce los datos
    pred := cal.Predict(amps[10]);
    Bk := Vec3Add(Mat3MulVec(M0, amps[10]), b0);
    Check('Predict = B', Near(pred[0], Bk[0]) and Near(pred[1], Bk[1]) and Near(pred[2], Bk[2]));

    WriteLn('Quitar punto invalida el ajuste:');
    Check('RemovePoint', cal.RemovePoint(0));
    Check('PointCount 12', cal.PointCount = 12);
    Check('ya no Fitted', not cal.Fitted);
    Check('reajusta', cal.Fit);  // 12 puntos siguen siendo no coplanares

    WriteLn('Round-trip JSON:');
    js := cal.SaveToJSON;
    Check('JSON no vacío', Length(js) > 0);
    cal2 := TCalibration.Create(cmModelB);
    try
      Check('carga JSON', cal2.LoadFromJSON(js));
      Check('modelo A restaurado', cal2.Model.Kind = cmModelA);
      Check('M igual', Mat3Near(cal2.M, cal.M));
      Check('b igual', Near(cal2.b[0], cal.b[0]) and Near(cal2.b[1], cal.b[1]) and Near(cal2.b[2], cal.b[2]));
      Check('R recomputada igual', Mat3Near(cal2.R, cal.R));
      Check('Fitted tras cargar', cal2.Fitted);
      Check('puntos restaurados', cal2.PointCount = cal.PointCount);

      WriteLn('Round-trip fichero:');
      tmpFile := GetTempDir + 'helmcalib_test_profile.json';
      Check('guarda fichero', cal.SaveToFile(tmpFile));
      Check('carga fichero', cal2.LoadFromFile(tmpFile));
      Check('M igual (fichero)', Mat3Near(cal2.M, cal.M));
      DeleteFile(tmpFile);

      WriteLn('JSON corrupto:');
      Check('corrupto -> no carga', not cal2.LoadFromJSON('{ esto no es json'));
    finally
      cal2.Free;
    end;
  finally
    cal.Free;
  end;

  WriteLn;
  WriteLn(Format('Resultado: %d ok, %d fallos', [gPass, gFail]));
  Halt(gFail);
end.
