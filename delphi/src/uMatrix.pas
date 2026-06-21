unit uMatrix;

{ Álgebra lineal 3x3 / 4x4 sin dependencias externas, para HelmCalib.

  Cubre lo que necesita la calibración B = M·I + b:
    - Operaciones básicas con vectores y matrices 3x3 / 4x4.
    - Inversa 3x3 (cofactores) y 4x4 (Gauss-Jordan con pivoteo).
    - Mínimos cuadrados afín: ajusta [M|b] a partir de N puntos (I_k, B_k)
      por ecuaciones normales  A = (Σ B·xᵀ)·(Σ x·xᵀ)⁻¹.
    - Eigendescomposición de matriz simétrica 3x3 (Jacobi cíclico).
    - Descomposición polar M = R·G  (R rotación coil→sensor, G ganancia simétrica)
      y SVD 3x3 derivada de ella.

  Convención de índices: M[fila, columna].

  Port a Delphi (VCL/Win64). Idéntico a la versión FPC salvo el modo de compilación. }

interface

type
  TVec3 = array[0..2] of Double;
  TVec4 = array[0..3] of Double;
  TMat3 = array[0..2, 0..2] of Double;
  TMat4 = array[0..3, 0..3] of Double;
  TMat34 = array[0..2, 0..3] of Double;  // [M | b]

{ Vectores 3 }
function Vec3(const x, y, z: Double): TVec3;
function Vec3Add(const a, b: TVec3): TVec3;
function Vec3Sub(const a, b: TVec3): TVec3;
function Vec3Scale(const a: TVec3; const s: Double): TVec3;
function Vec3Dot(const a, b: TVec3): Double;
function Vec3Cross(const a, b: TVec3): TVec3;
function Vec3Norm(const a: TVec3): Double;

{ Matrices 3x3 }
function Mat3Identity: TMat3;
function Mat3Mult(const a, b: TMat3): TMat3;
function Mat3MulVec(const m: TMat3; const v: TVec3): TVec3;
function Mat3Transpose(const m: TMat3): TMat3;
function Mat3Det(const m: TMat3): Double;
function Mat3Inverse(const m: TMat3; out inv: TMat3): Boolean;

{ Matrices 4x4 }
function Mat4Identity: TMat4;
function Mat4Mult(const a, b: TMat4): TMat4;
function Mat4Inverse(const m: TMat4; out inv: TMat4): Boolean;

{ Mínimos cuadrados afín: I[k], B[k] (k = 0..N-1, N >= 4 no coplanares + I=0).
  Devuelve M (3x3, µT/A) y b (3x1, µT). False si Σ x·xᵀ es singular. }
function SolveAffine(const Iarr, Barr: array of TVec3; out M: TMat3; out b: TVec3): Boolean;

{ Eigendescomposición de A simétrica 3x3 (Jacobi). d = eigenvalores,
  V columnas = eigenvectores (V[*,j] es el autovector de d[j]). A = V·diag(d)·Vᵀ. }
function JacobiEig3(const Asym: TMat3; out d: TVec3; out V: TMat3): Boolean;

{ Descomposición polar M = R·G. R rotación (ortonormal, det +1 si M no degenerada),
  G simétrica positiva (ganancia). False si M es singular. }
function PolarDecomp(const M: TMat3; out R, G: TMat3): Boolean;

{ SVD 3x3: M = U·diag(S)·Vᵀ, S ordenados descendente (>= 0). Derivada del polar. }
function SVD3(const M: TMat3; out U: TMat3; out S: TVec3; out V: TMat3): Boolean;

implementation

uses Math;

{ ----------------------------- Vectores ----------------------------- }

function Vec3(const x, y, z: Double): TVec3;
begin
  Result[0] := x; Result[1] := y; Result[2] := z;
end;

function Vec3Add(const a, b: TVec3): TVec3;
begin
  Result[0] := a[0] + b[0]; Result[1] := a[1] + b[1]; Result[2] := a[2] + b[2];
end;

function Vec3Sub(const a, b: TVec3): TVec3;
begin
  Result[0] := a[0] - b[0]; Result[1] := a[1] - b[1]; Result[2] := a[2] - b[2];
end;

function Vec3Scale(const a: TVec3; const s: Double): TVec3;
begin
  Result[0] := a[0] * s; Result[1] := a[1] * s; Result[2] := a[2] * s;
end;

function Vec3Dot(const a, b: TVec3): Double;
begin
  Result := a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
end;

function Vec3Cross(const a, b: TVec3): TVec3;
begin
  Result[0] := a[1] * b[2] - a[2] * b[1];
  Result[1] := a[2] * b[0] - a[0] * b[2];
  Result[2] := a[0] * b[1] - a[1] * b[0];
end;

function Vec3Norm(const a: TVec3): Double;
begin
  Result := Sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
end;

{ ----------------------------- 3x3 ----------------------------- }

function Mat3Identity: TMat3;
var i, j: Integer;
begin
  for i := 0 to 2 do
    for j := 0 to 2 do
      if i = j then Result[i, j] := 1 else Result[i, j] := 0;
end;

function Mat3Mult(const a, b: TMat3): TMat3;
var i, j, k: Integer; s: Double;
begin
  for i := 0 to 2 do
    for j := 0 to 2 do
    begin
      s := 0;
      for k := 0 to 2 do s := s + a[i, k] * b[k, j];
      Result[i, j] := s;
    end;
end;

function Mat3MulVec(const m: TMat3; const v: TVec3): TVec3;
var i: Integer;
begin
  for i := 0 to 2 do
    Result[i] := m[i, 0] * v[0] + m[i, 1] * v[1] + m[i, 2] * v[2];
end;

function Mat3Transpose(const m: TMat3): TMat3;
var i, j: Integer;
begin
  for i := 0 to 2 do
    for j := 0 to 2 do
      Result[i, j] := m[j, i];
end;

function Mat3Det(const m: TMat3): Double;
begin
  Result := m[0, 0] * (m[1, 1] * m[2, 2] - m[1, 2] * m[2, 1])
          - m[0, 1] * (m[1, 0] * m[2, 2] - m[1, 2] * m[2, 0])
          + m[0, 2] * (m[1, 0] * m[2, 1] - m[1, 1] * m[2, 0]);
end;

function Mat3Inverse(const m: TMat3; out inv: TMat3): Boolean;
var det, idet: Double;
begin
  det := Mat3Det(m);
  if Abs(det) < 1e-300 then Exit(False);
  idet := 1.0 / det;
  inv[0, 0] :=  (m[1, 1] * m[2, 2] - m[1, 2] * m[2, 1]) * idet;
  inv[0, 1] := -(m[0, 1] * m[2, 2] - m[0, 2] * m[2, 1]) * idet;
  inv[0, 2] :=  (m[0, 1] * m[1, 2] - m[0, 2] * m[1, 1]) * idet;
  inv[1, 0] := -(m[1, 0] * m[2, 2] - m[1, 2] * m[2, 0]) * idet;
  inv[1, 1] :=  (m[0, 0] * m[2, 2] - m[0, 2] * m[2, 0]) * idet;
  inv[1, 2] := -(m[0, 0] * m[1, 2] - m[0, 2] * m[1, 0]) * idet;
  inv[2, 0] :=  (m[1, 0] * m[2, 1] - m[1, 1] * m[2, 0]) * idet;
  inv[2, 1] := -(m[0, 0] * m[2, 1] - m[0, 1] * m[2, 0]) * idet;
  inv[2, 2] :=  (m[0, 0] * m[1, 1] - m[0, 1] * m[1, 0]) * idet;
  Result := True;
end;

{ ----------------------------- 4x4 ----------------------------- }

function Mat4Identity: TMat4;
var i, j: Integer;
begin
  for i := 0 to 3 do
    for j := 0 to 3 do
      if i = j then Result[i, j] := 1 else Result[i, j] := 0;
end;

function Mat4Mult(const a, b: TMat4): TMat4;
var i, j, k: Integer; s: Double;
begin
  for i := 0 to 3 do
    for j := 0 to 3 do
    begin
      s := 0;
      for k := 0 to 3 do s := s + a[i, k] * b[k, j];
      Result[i, j] := s;
    end;
end;

function Mat4Inverse(const m: TMat4; out inv: TMat4): Boolean;
var
  a: array[0..3, 0..7] of Double;  // [m | I] aumentada
  i, j, k, piv: Integer;
  maxv, f, tmp: Double;
begin
  for i := 0 to 3 do
    for j := 0 to 3 do
    begin
      a[i, j] := m[i, j];
      if i = j then a[i, j + 4] := 1 else a[i, j + 4] := 0;
    end;

  for k := 0 to 3 do
  begin
    // pivoteo parcial
    piv := k; maxv := Abs(a[k, k]);
    for i := k + 1 to 3 do
      if Abs(a[i, k]) > maxv then begin maxv := Abs(a[i, k]); piv := i; end;
    if maxv < 1e-300 then Exit(False);
    if piv <> k then
      for j := 0 to 7 do
      begin tmp := a[k, j]; a[k, j] := a[piv, j]; a[piv, j] := tmp; end;
    // normaliza fila pivote
    f := a[k, k];
    for j := 0 to 7 do a[k, j] := a[k, j] / f;
    // elimina resto
    for i := 0 to 3 do
      if i <> k then
      begin
        f := a[i, k];
        for j := 0 to 7 do a[i, j] := a[i, j] - f * a[k, j];
      end;
  end;

  for i := 0 to 3 do
    for j := 0 to 3 do
      inv[i, j] := a[i, j + 4];
  Result := True;
end;

{ ----------------------------- Mínimos cuadrados ----------------------------- }

function SolveAffine(const Iarr, Barr: array of TVec3; out M: TMat3; out b: TVec3): Boolean;
var
  S: TMat4;          // Σ x·xᵀ, x = [Ix, Iy, Iz, 1]
  Sinv: TMat4;
  P: TMat34;         // Σ B·xᵀ  (3x4)
  A: TMat34;         // [M | b] = P·Sinv
  x: TVec4;
  k, r, c, j: Integer; acc: Double;
begin
  if Length(Iarr) <> Length(Barr) then Exit(False);
  if Length(Iarr) < 4 then Exit(False);

  for r := 0 to 3 do for c := 0 to 3 do S[r, c] := 0;
  for r := 0 to 2 do for c := 0 to 3 do P[r, c] := 0;

  for k := 0 to High(Iarr) do
  begin
    x[0] := Iarr[k, 0]; x[1] := Iarr[k, 1]; x[2] := Iarr[k, 2]; x[3] := 1;
    for r := 0 to 3 do
      for c := 0 to 3 do
        S[r, c] := S[r, c] + x[r] * x[c];
    for r := 0 to 2 do
      for c := 0 to 3 do
        P[r, c] := P[r, c] + Barr[k, r] * x[c];
  end;

  if not Mat4Inverse(S, Sinv) then Exit(False);

  // A = P · Sinv  (3x4 = 3x4 · 4x4)
  for r := 0 to 2 do
    for c := 0 to 3 do
    begin
      acc := 0;
      for j := 0 to 3 do acc := acc + P[r, j] * Sinv[j, c];
      A[r, c] := acc;
    end;

  for r := 0 to 2 do
  begin
    for c := 0 to 2 do M[r, c] := A[r, c];
    b[r] := A[r, 3];
  end;
  Result := True;
end;

{ ----------------------------- Jacobi (simétrica 3x3) ----------------------------- }

function JacobiEig3(const Asym: TMat3; out d: TVec3; out V: TMat3): Boolean;
const N = 3;
var
  a: TMat3;
  bb, z: TVec3;
  ip, iq, j, sweep: Integer;
  sm, thresh, g, h, t, theta, c, s, tau, aij: Double;

  procedure Rot(var mm: TMat3; const i1, j1, i2, j2: Integer);
  var gg, hh: Double;
  begin
    gg := mm[i1, j1]; hh := mm[i2, j2];
    mm[i1, j1] := gg - s * (hh + gg * tau);
    mm[i2, j2] := hh + s * (gg - hh * tau);
  end;

begin
  a := Asym;
  V := Mat3Identity;
  for ip := 0 to N - 1 do begin d[ip] := a[ip, ip]; bb[ip] := d[ip]; z[ip] := 0; end;

  for sweep := 1 to 100 do
  begin
    sm := Abs(a[0, 1]) + Abs(a[0, 2]) + Abs(a[1, 2]);
    if sm = 0 then Exit(True);  // convergido
    if sweep < 4 then thresh := 0.2 * sm / (N * N) else thresh := 0;

    for ip := 0 to N - 2 do
      for iq := ip + 1 to N - 1 do
      begin
        g := 100.0 * Abs(a[ip, iq]);
        if (sweep > 4) and (Abs(d[ip]) + g = Abs(d[ip]))
                       and (Abs(d[iq]) + g = Abs(d[iq])) then
          a[ip, iq] := 0
        else if Abs(a[ip, iq]) > thresh then
        begin
          h := d[iq] - d[ip];
          if Abs(h) + g = Abs(h) then
            t := a[ip, iq] / h
          else
          begin
            theta := 0.5 * h / a[ip, iq];
            t := 1.0 / (Abs(theta) + Sqrt(1.0 + theta * theta));
            if theta < 0 then t := -t;
          end;
          c := 1.0 / Sqrt(1.0 + t * t);
          s := t * c;
          tau := s / (1.0 + c);
          aij := a[ip, iq];
          h := t * aij;
          z[ip] := z[ip] - h; z[iq] := z[iq] + h;
          d[ip] := d[ip] - h; d[iq] := d[iq] + h;
          a[ip, iq] := 0;
          for j := 0 to ip - 1 do Rot(a, j, ip, j, iq);
          for j := ip + 1 to iq - 1 do Rot(a, ip, j, j, iq);
          for j := iq + 1 to N - 1 do Rot(a, ip, j, iq, j);
          for j := 0 to N - 1 do Rot(V, j, ip, j, iq);
        end;
      end;

    for ip := 0 to N - 1 do
    begin
      bb[ip] := bb[ip] + z[ip];
      d[ip] := bb[ip];
      z[ip] := 0;
    end;
  end;
  Result := False;  // no convergió en 100 barridos (no debería pasar para 3x3)
end;

{ ----------------------------- Descomposición polar / SVD ----------------------------- }

{ M = R·G con G = sqrt(MᵀM) simétrica positiva, R = M·G⁻¹.
  MᵀM = V·diag(λ)·Vᵀ ⇒ G = V·diag(√λ)·Vᵀ, G⁻¹ = V·diag(1/√λ)·Vᵀ. }
function PolarDecomp(const M: TMat3; out R, G: TMat3): Boolean;
var
  AtA, V, Vt, dg, dgi, Ginv: TMat3;
  lam: TVec3;
  i, j: Integer;
  sq: Double;
begin
  AtA := Mat3Mult(Mat3Transpose(M), M);
  if not JacobiEig3(AtA, lam, V) then Exit(False);
  for i := 0 to 2 do
    if lam[i] <= 1e-300 then Exit(False);  // M singular

  Vt := Mat3Transpose(V);
  for i := 0 to 2 do
    for j := 0 to 2 do
    begin
      dg[i, j] := 0; dgi[i, j] := 0;
    end;
  for i := 0 to 2 do
  begin
    sq := Sqrt(lam[i]);
    dg[i, i] := sq;
    dgi[i, i] := 1.0 / sq;
  end;

  G := Mat3Mult(Mat3Mult(V, dg), Vt);
  Ginv := Mat3Mult(Mat3Mult(V, dgi), Vt);
  R := Mat3Mult(M, Ginv);
  Result := True;
end;

function SVD3(const M: TMat3; out U: TMat3; out S: TVec3; out V: TMat3): Boolean;
var
  AtA, Vt: TMat3;
  lam: TVec3;
  idx: array[0..2] of Integer;
  i, j, ti: Integer;
  col: TVec3;
  invS: Double;
begin
  { MᵀM = V·diag(λ)·Vᵀ ⇒ S = √λ, U = M·V·diag(1/S). }
  AtA := Mat3Mult(Mat3Transpose(M), M);
  if not JacobiEig3(AtA, lam, V) then Exit(False);

  // orden descendente de valores singulares
  idx[0] := 0; idx[1] := 1; idx[2] := 2;
  for i := 0 to 1 do
    for j := i + 1 to 2 do
      if lam[idx[j]] > lam[idx[i]] then
      begin ti := idx[i]; idx[i] := idx[j]; idx[j] := ti; end;

  // reordena columnas de V y valores singulares
  Vt := V;
  for j := 0 to 2 do
  begin
    S[j] := Sqrt(Max(lam[idx[j]], 0));
    for i := 0 to 2 do V[i, j] := Vt[i, idx[j]];
  end;

  // U = M·V·diag(1/S), columna a columna
  U := Mat3Identity;
  for j := 0 to 2 do
  begin
    for i := 0 to 2 do col[i] := V[i, j];
    col := Mat3MulVec(M, col);
    if S[j] > 1e-300 then
    begin
      invS := 1.0 / S[j];
      for i := 0 to 2 do U[i, j] := col[i] * invS;
    end
    else
      for i := 0 to 2 do U[i, j] := 0;
  end;
  Result := True;
end;

end.
