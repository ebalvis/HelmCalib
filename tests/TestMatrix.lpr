program TestMatrix;

{ Tests de uMatrix con datos sintéticos (M, b, R, G conocidos).
  Compilar:  fpc -Fu../src TestMatrix.lpr   (o ver tests/run.sh)
  Exit code = nº de tests fallidos. }

{$mode objfpc}{$H+}

uses
  SysUtils, Math, uMatrix;

var
  gFail: Integer = 0;
  gPass: Integer = 0;

procedure Check(const name: string; cond: Boolean);
begin
  if cond then
  begin
    Inc(gPass);
    WriteLn('  ok   ', name);
  end
  else
  begin
    Inc(gFail);
    WriteLn('  FAIL ', name);
  end;
end;

function Near(const a, b: Double; const eps: Double = 1e-9): Boolean;
begin
  Result := Abs(a - b) <= eps;
end;

function Mat3Near(const a, b: TMat3; const eps: Double = 1e-9): Boolean;
var i, j: Integer;
begin
  for i := 0 to 2 do
    for j := 0 to 2 do
      if not Near(a[i, j], b[i, j], eps) then Exit(False);
  Result := True;
end;

function Mat3FromRows(const a, b, c, d, e, f, g, h, i: Double): TMat3;
begin
  Result[0, 0] := a; Result[0, 1] := b; Result[0, 2] := c;
  Result[1, 0] := d; Result[1, 1] := e; Result[1, 2] := f;
  Result[2, 0] := g; Result[2, 1] := h; Result[2, 2] := i;
end;

{ Rotación 3x3 ZYX para tests de polar/SVD }
function RotZYX(const rz, ry, rx: Double): TMat3;
var Rz_, Ry_, Rx_: TMat3;
begin
  Rz_ := Mat3FromRows(Cos(rz), -Sin(rz), 0,  Sin(rz), Cos(rz), 0,  0, 0, 1);
  Ry_ := Mat3FromRows(Cos(ry), 0, Sin(ry),  0, 1, 0,  -Sin(ry), 0, Cos(ry));
  Rx_ := Mat3FromRows(1, 0, 0,  0, Cos(rx), -Sin(rx),  0, Sin(rx), Cos(rx));
  Result := Mat3Mult(Mat3Mult(Rz_, Ry_), Rx_);
end;

{ --------------------------- Tests --------------------------- }

procedure TestInverse3;
var m, inv, prod: TMat3; ok: Boolean;
begin
  WriteLn('Inversa 3x3:');
  m := Mat3FromRows(2, -1, 0,  -1, 2, -1,  0, -1, 2);
  ok := Mat3Inverse(m, inv);
  Check('det != 0', ok);
  prod := Mat3Mult(m, inv);
  Check('M*M^-1 = I', Mat3Near(prod, Mat3Identity));
  // singular
  m := Mat3FromRows(1, 2, 3,  2, 4, 6,  1, 1, 1);
  Check('singular -> False', not Mat3Inverse(m, inv));
end;

procedure TestInverse4;
var m, inv, prod, id: TMat4; ok: Boolean; i, j, k: Integer; s: Double;
begin
  WriteLn('Inversa 4x4:');
  m[0, 0] := 4; m[0, 1] := 1; m[0, 2] := 0; m[0, 3] := 2;
  m[1, 0] := 1; m[1, 1] := 3; m[1, 2] := 1; m[1, 3] := 0;
  m[2, 0] := 0; m[2, 1] := 1; m[2, 2] := 5; m[2, 3] := 1;
  m[3, 0] := 2; m[3, 1] := 0; m[3, 2] := 1; m[3, 3] := 6;
  ok := Mat4Inverse(m, inv);
  Check('det != 0', ok);
  prod := Mat4Mult(m, inv);
  id := Mat4Identity;
  s := 0;
  for i := 0 to 3 do for j := 0 to 3 do s := s + Abs(prod[i, j] - id[i, j]);
  Check('M*M^-1 = I', s < 1e-9);
  k := 0; // evita warning de variable sin usar en algunos modos
  if k = 0 then ;
end;

procedure TestSolveAffine;
const N = 13;
var
  M0, M: TMat3; b0, b: TVec3;
  Ipts, Bpts: array[0..N-1] of TVec3;
  i: Integer; ok: Boolean;
  amps: array[0..N-1] of TVec3;
begin
  WriteLn('Mínimos cuadrados (B = M·I + b):');
  // modelo verdadero: ganancia + acoplo cruzado + offset ambiente
  M0 := Mat3FromRows(24.8, 0.8, 0.5,   0.4, 25.3, 0.7,   0.6, 0.3, 25.1);
  b0 := Vec3(30.0, -12.0, 45.0);

  // 13 corrientes: 0, ±I0 por eje (6), combinaciones (6)
  amps[0]  := Vec3( 0,  0,  0);
  amps[1]  := Vec3( 5,  0,  0);  amps[2]  := Vec3(-5,  0,  0);
  amps[3]  := Vec3( 0,  5,  0);  amps[4]  := Vec3( 0, -5,  0);
  amps[5]  := Vec3( 0,  0,  5);  amps[6]  := Vec3( 0,  0, -5);
  amps[7]  := Vec3( 4,  4,  0);  amps[8]  := Vec3( 4,  0,  4);
  amps[9]  := Vec3( 0,  4,  4);  amps[10] := Vec3( 3,  3,  3);
  amps[11] := Vec3(-3,  2, -4);  amps[12] := Vec3( 2, -3,  4);

  for i := 0 to N - 1 do
  begin
    Ipts[i] := amps[i];
    Bpts[i] := Vec3Add(Mat3MulVec(M0, amps[i]), b0);
  end;

  ok := SolveAffine(Ipts, Bpts, M, b);
  Check('resuelve', ok);
  Check('M recuperada', Mat3Near(M, M0, 1e-6));
  Check('b recuperado', Near(b[0], b0[0], 1e-6) and Near(b[1], b0[1], 1e-6)
                        and Near(b[2], b0[2], 1e-6));

  // datos coplanares (todas las I con z=0, sin variar z) -> singular
  for i := 0 to N - 1 do
  begin
    Ipts[i] := Vec3(amps[i, 0], amps[i, 1], 0);
    Bpts[i] := Vec3Add(Mat3MulVec(M0, Ipts[i]), b0);
  end;
  Check('coplanar -> False', not SolveAffine(Ipts, Bpts, M, b));
end;

procedure TestJacobi;
var A, V, recon, Vt, dg: TMat3; d: TVec3; i, j: Integer; ok: Boolean;
begin
  WriteLn('Jacobi (eigen simétrica 3x3):');
  A := Mat3FromRows(2, -1, 0,  -1, 2, -1,  0, -1, 2);  // eigenvalores 2, 2±√2
  ok := JacobiEig3(A, d, V);
  Check('converge', ok);
  // reconstrucción V·diag(d)·Vᵀ = A
  for i := 0 to 2 do for j := 0 to 2 do if i = j then dg[i, j] := d[i] else dg[i, j] := 0;
  Vt := Mat3Transpose(V);
  recon := Mat3Mult(Mat3Mult(V, dg), Vt);
  Check('V·D·Vᵀ = A', Mat3Near(recon, A, 1e-8));
  // V ortonormal
  Check('VᵀV = I', Mat3Near(Mat3Mult(Vt, V), Mat3Identity, 1e-8));
  // suma de eigenvalores = traza
  Check('Σλ = traza', Near(d[0] + d[1] + d[2], 6.0, 1e-8));
end;

procedure TestPolar;
var
  R0, G0, M, R, G, recon, RtR: TMat3;
begin
  WriteLn('Descomposición polar M = R·G:');
  R0 := RotZYX(0.3, -0.2, 0.5);
  G0 := Mat3FromRows(24.8, 0.5, 0.3,  0.5, 25.3, 0.2,  0.3, 0.2, 25.1); // simétrica PD
  M := Mat3Mult(R0, G0);

  Check('descompone', PolarDecomp(M, R, G));
  recon := Mat3Mult(R, G);
  Check('R·G = M', Mat3Near(recon, M, 1e-7));
  RtR := Mat3Mult(Mat3Transpose(R), R);
  Check('RᵀR = I (R ortonormal)', Mat3Near(RtR, Mat3Identity, 1e-7));
  Check('det(R) ~ +1', Near(Mat3Det(R), 1.0, 1e-7));
  Check('G simétrica', Near(G[0, 1], G[1, 0], 1e-9) and Near(G[0, 2], G[2, 0], 1e-9)
                      and Near(G[1, 2], G[2, 1], 1e-9));
  Check('R recuperada', Mat3Near(R, R0, 1e-6));
  Check('G recuperada', Mat3Near(G, G0, 1e-6));
end;

procedure TestSVD;
var
  M, U, V, recon, dg, Ut: TMat3; S: TVec3; i, j: Integer;
begin
  WriteLn('SVD 3x3:');
  M := Mat3FromRows(24.8, 0.8, 0.5,  0.4, 25.3, 0.7,  0.6, 0.3, 25.1);
  Check('descompone', SVD3(M, U, S, V));
  for i := 0 to 2 do for j := 0 to 2 do if i = j then dg[i, j] := S[i] else dg[i, j] := 0;
  recon := Mat3Mult(Mat3Mult(U, dg), Mat3Transpose(V));
  Check('U·Σ·Vᵀ = M', Mat3Near(recon, M, 1e-7));
  Ut := Mat3Transpose(U);
  Check('UᵀU = I', Mat3Near(Mat3Mult(Ut, U), Mat3Identity, 1e-7));
  Check('VᵀV = I', Mat3Near(Mat3Mult(Mat3Transpose(V), V), Mat3Identity, 1e-7));
  Check('S ordenado desc', (S[0] >= S[1]) and (S[1] >= S[2]) and (S[2] >= 0));
end;

begin
  WriteLn('=== Tests uMatrix ===');
  TestInverse3;
  TestInverse4;
  TestSolveAffine;
  TestJacobi;
  TestPolar;
  TestSVD;
  WriteLn;
  WriteLn(Format('Resultado: %d ok, %d fallos', [gPass, gFail]));
  Halt(gFail);
end.
