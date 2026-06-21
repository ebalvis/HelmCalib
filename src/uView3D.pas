unit uView3D;

{ Vista 3D wireframe sobre Canvas (sin librerías 3D).

  Dibuja la estructura cúbica de soporte (aluminio) y los 3 pares de bobinas
  cuadradas de Helmholtz (cobre, a escala) tipo BHC2000, más la flecha del vector
  B (objetivo y, opcional, medido) desde el centro.
  Proyección perspectiva propia; la escena se rota arrastrando con el ratón y se
  hace zoom con la rueda.

  TView3DPanel es un TCustomControl autónomo: se crea en código y se asigna Parent
  y Align. SetTarget/SetMeasured fijan los vectores (µT, marco bobina X/Y/Z). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, LCLType, uMatrix;

type
  TView3DPanel = class(TCustomControl)
  private
    FYaw, FPitch: Double;       // rad
    FZoom: Double;
    FDragging: Boolean;
    FLastX, FLastY: Integer;
    FTarget: TVec3;  FHasTarget: Boolean;
    FMeasured: TVec3; FHasMeasured: Boolean;
    FBmaxRef: Double;           // µT que corresponde a la longitud "1 radio"
    FRot: TMat3;
    FCanvas: TCanvas;           // destino de dibujo actual (control o bitmap)
    FRW, FRH: Integer;          // dimensiones del destino actual
    procedure DoRender;
    function Project(const w: TVec3): TPoint;
    procedure DrawSquareCoil(axis: Integer; half, offset: Double; col: TColor; w: Integer);
    procedure DrawCube(s: Double; col: TColor);
    procedure DrawArrow(const v: TVec3; col: TColor; const txt: string);
    procedure DrawAxis(const dir: TVec3; col: TColor; const lbl: string);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Dibuja la escena en un Canvas arbitrario (control o bitmap offline). }
    procedure RenderTo(ACanvas: TCanvas; AWidth, AHeight: Integer);
    procedure SetTarget(const v: TVec3);
    procedure ClearTarget;
    procedure SetMeasured(const v: TVec3);
    procedure ClearMeasured;
    property BmaxRef: Double read FBmaxRef write FBmaxRef;
  end;

implementation

const
  DIAM: array[0..2] of Double = (2046, 2000, 1954);  // mm: X, Y, Z
  MAXDIAM = 2046.0;
  FOCAL = 2.6;
  CAMDIST = 3.2;

function RotY(a: Double): TMat3;
begin
  Result := Mat3Identity;
  Result[0,0] := Cos(a);  Result[0,2] := Sin(a);
  Result[2,0] := -Sin(a); Result[2,2] := Cos(a);
end;

function RotX(a: Double): TMat3;
begin
  Result := Mat3Identity;
  Result[1,1] := Cos(a);  Result[1,2] := -Sin(a);
  Result[2,1] := Sin(a);  Result[2,2] := Cos(a);
end;

constructor TView3DPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DoubleBuffered := True;
  FYaw := 0.6;
  FPitch := 0.35;
  FZoom := 1.0;
  FBmaxRef := 100.0;  // µT -> longitud de 1 radio (campo terrestre ~50 µT se ve a media escala)
  FHasTarget := False;
  FHasMeasured := False;
  ControlStyle := ControlStyle + [csOpaque];
end;

procedure TView3DPanel.SetTarget(const v: TVec3);
begin
  FTarget := v; FHasTarget := True; Invalidate;
end;

procedure TView3DPanel.ClearTarget;
begin
  FHasTarget := False; Invalidate;
end;

procedure TView3DPanel.SetMeasured(const v: TVec3);
begin
  FMeasured := v; FHasMeasured := True; Invalidate;
end;

procedure TView3DPanel.ClearMeasured;
begin
  FHasMeasured := False; Invalidate;
end;

function TView3DPanel.Project(const w: TVec3): TPoint;
var
  r: TVec3;
  f, scale: Double;
  cx, cy: Integer;
begin
  r := Mat3MulVec(FRot, w);
  cx := FRW div 2;
  cy := FRH div 2;
  scale := FZoom * 0.45 * Min(FRW, FRH);
  f := FOCAL / (CAMDIST - r[2]);
  Result.X := cx + Round(r[0] * f * scale);
  Result.Y := cy - Round(r[1] * f * scale);
end;

{ Bobina cuadrada perpendicular al eje 'axis', lado 2*half, a 'offset' en ese eje. }
procedure TView3DPanel.DrawSquareCoil(axis: Integer; half, offset: Double; col: TColor; w: Integer);
var
  c: array[0..4] of TVec3;
  pts: array[0..4] of TPoint;
  i: Integer;
begin
  case axis of
    0: begin  // plano YZ
      c[0] := Vec3(offset, -half, -half); c[1] := Vec3(offset,  half, -half);
      c[2] := Vec3(offset,  half,  half); c[3] := Vec3(offset, -half,  half);
    end;
    1: begin  // plano XZ
      c[0] := Vec3(-half, offset, -half); c[1] := Vec3( half, offset, -half);
      c[2] := Vec3( half, offset,  half); c[3] := Vec3(-half, offset,  half);
    end;
  else begin  // plano XY
      c[0] := Vec3(-half, -half, offset); c[1] := Vec3( half, -half, offset);
      c[2] := Vec3( half,  half, offset); c[3] := Vec3(-half,  half, offset);
    end;
  end;
  c[4] := c[0];
  for i := 0 to 4 do pts[i] := Project(c[i]);
  FCanvas.Pen.Color := col;
  FCanvas.Pen.Width := w;
  FCanvas.Polyline(pts);
  FCanvas.Pen.Width := 1;
end;

{ Estructura cúbica de soporte (12 aristas) de semilado 's'. }
procedure TView3DPanel.DrawCube(s: Double; col: TColor);
const
  EDG: array[0..11, 0..1] of Integer = (
    (0,1),(0,2),(0,4),(1,3),(1,5),(2,3),(2,6),(3,7),(4,5),(4,6),(5,7),(6,7));
var
  v: array[0..7] of TVec3;
  i: Integer;
  a, b: TPoint;
begin
  for i := 0 to 7 do
    v[i] := Vec3(((i and 1) * 2 - 1) * s,
                 (((i shr 1) and 1) * 2 - 1) * s,
                 (((i shr 2) and 1) * 2 - 1) * s);
  FCanvas.Pen.Color := col;
  FCanvas.Pen.Width := 1;
  for i := 0 to 11 do
  begin
    a := Project(v[EDG[i, 0]]);
    b := Project(v[EDG[i, 1]]);
    FCanvas.MoveTo(a.X, a.Y);
    FCanvas.LineTo(b.X, b.Y);
  end;
end;

procedure TView3DPanel.DrawAxis(const dir: TVec3; col: TColor; const lbl: string);
var p0, p1: TPoint;
begin
  p0 := Project(Vec3(0, 0, 0));
  p1 := Project(Vec3Scale(dir, 0.75));
  FCanvas.Pen.Color := col;
  FCanvas.Pen.Width := 1;
  FCanvas.MoveTo(p0.X, p0.Y);
  FCanvas.LineTo(p1.X, p1.Y);
  FCanvas.Font.Color := col;
  FCanvas.TextOut(p1.X + 3, p1.Y - 6, lbl);
end;

procedure TView3DPanel.DrawArrow(const v: TVec3; col: TColor; const txt: string);
var
  vis: TVec3;
  m, L: Double;
  p0, p1: TPoint;
  ang, ah: Double;
  dx, dy: Double;
begin
  m := Vec3Norm(v);
  if m < 1e-9 then Exit;
  // longitud visual proporcional a |B|/BmaxRef, en unidades de "radio", con tope
  L := (m / FBmaxRef);
  if L > 1.2 then L := 1.2;
  vis := Vec3Scale(v, (L / m));   // dirección de v, módulo L (en unidades escena)

  p0 := Project(Vec3(0, 0, 0));
  p1 := Project(vis);
  FCanvas.Pen.Color := col;
  FCanvas.Pen.Width := 2;
  FCanvas.MoveTo(p0.X, p0.Y);
  FCanvas.LineTo(p1.X, p1.Y);

  // cabeza de flecha en 2D
  dx := p1.X - p0.X; dy := p1.Y - p0.Y;
  if (dx <> 0) or (dy <> 0) then
  begin
    ang := ArcTan2(dy, dx);
    ah := 11;
    FCanvas.MoveTo(p1.X, p1.Y);
    FCanvas.LineTo(p1.X - Round(ah * Cos(ang - 0.4)), p1.Y - Round(ah * Sin(ang - 0.4)));
    FCanvas.MoveTo(p1.X, p1.Y);
    FCanvas.LineTo(p1.X - Round(ah * Cos(ang + 0.4)), p1.Y - Round(ah * Sin(ang + 0.4)));
  end;
  FCanvas.Font.Color := col;
  FCanvas.TextOut(p1.X + 5, p1.Y + 2, txt);
end;

procedure TView3DPanel.DoRender;
const
  axisCol: array[0..2] of TColor = (clRed, clLime, clBlue);
  COPPER  = TColor($00295C8C);   // cobre (BBGGRR) para los devanados
  FRAMECOL = TColor($00777777);  // gris aluminio para la estructura
var
  axis: Integer;
  half, sep: Double;
begin
  FRot := Mat3Mult(RotX(FPitch), RotY(FYaw));

  FCanvas.Brush.Style := bsSolid;
  FCanvas.Brush.Color := clBlack;
  FCanvas.FillRect(0, 0, FRW, FRH);
  FCanvas.Brush.Style := bsClear;

  // estructura cúbica de soporte (aluminio), algo mayor que las bobinas
  DrawCube(0.62, FRAMECOL);

  // 3 pares de bobinas CUADRADAS (Helmholtz) tipo BHC2000, en cobre
  for axis := 0 to 2 do
  begin
    half := (DIAM[axis] / 2) / MAXDIAM * 0.92;   // tamaño a escala del eje
    sep := half * 0.55;                          // separación del par
    DrawSquareCoil(axis, half, -sep, COPPER, 4);
    DrawSquareCoil(axis, half,  sep, COPPER, 4);
  end;

  // ejes del marco bobina (cortos, para orientación)
  DrawAxis(Vec3(1, 0, 0), axisCol[0], 'X');
  DrawAxis(Vec3(0, 1, 0), axisCol[1], 'Y');
  DrawAxis(Vec3(0, 0, 1), axisCol[2], 'Z');

  // vectores
  if FHasMeasured then
    DrawArrow(FMeasured, clAqua, 'medido');
  if FHasTarget then
    DrawArrow(FTarget, clYellow, Format('B=%.1f µT', [Vec3Norm(FTarget)]));

  // ayuda
  FCanvas.Font.Color := clGray;
  FCanvas.TextOut(6, FRH - 18, 'Arrastra: rotar · Rueda: zoom');
end;

procedure TView3DPanel.Paint;
begin
  FCanvas := Canvas;
  FRW := ClientWidth;
  FRH := ClientHeight;
  DoRender;
end;

procedure TView3DPanel.RenderTo(ACanvas: TCanvas; AWidth, AHeight: Integer);
begin
  FCanvas := ACanvas;
  FRW := AWidth;
  FRH := AHeight;
  DoRender;
end;

procedure TView3DPanel.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := True;
    FLastX := X; FLastY := Y;
  end;
end;

procedure TView3DPanel.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then
  begin
    FYaw := FYaw + (X - FLastX) * 0.01;
    FPitch := FPitch + (Y - FLastY) * 0.01;
    if FPitch > 1.5 then FPitch := 1.5;
    if FPitch < -1.5 then FPitch := -1.5;
    FLastX := X; FLastY := Y;
    Invalidate;
  end;
end;

procedure TView3DPanel.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then FDragging := False;
end;

function TView3DPanel.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FZoom := FZoom * (1.0 + WheelDelta / 1200.0);
  if FZoom < 0.2 then FZoom := 0.2;
  if FZoom > 5.0 then FZoom := 5.0;
  Invalidate;
  Result := True;
end;

end.
