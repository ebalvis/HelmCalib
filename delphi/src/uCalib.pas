unit uCalib;

{ Modelo de calibración B = M·I + b (marco del sensor).

  - Acumula puntos (I_k [A], B_k [µT]) medidos en la calibración.
  - Ajusta [M|b] por mínimos cuadrados (uMatrix.SolveAffine).
  - Descomposición polar M = R·G (R rotación coil→sensor, G ganancia simétrica
    ≈ diag(k_x,k_y,k_z)); guarda G⁻¹ para el lazo abierto (uField).
  - Calidad del ajuste: residuo RMS en µT.
  - Persistencia del perfil en JSON (M, b, modelo de bobina, fecha, residuo, puntos).

  La inversa para programar campo y el clamp de corriente viven en uField.

  Port a Delphi (VCL/Win64): persistencia con System.JSON. }

interface

uses
  System.Classes, System.SysUtils, uMatrix;

type
  TCoilModelKind = (cmModelA, cmModelB);

  TCoilModelInfo = record
    Kind: TCoilModelKind;
    Name: string;
    IMaxPerAxis: Double;   // A
    BMaxPerAxis: Double;   // µT
    KNominal: TVec3;       // µT/A nominal por eje (referencia/sanity)
  end;

  TCalibPoint = record
    I: TVec3;   // A
    B: TVec3;   // µT (marco sensor)
  end;

  TCalibration = class
  private
    FPoints: array of TCalibPoint;
    FModel: TCoilModelInfo;
    FFitted: Boolean;
    FM, FR, FG, FGinv: TMat3;
    Fb: TVec3;
    FResidualRMS: Double;
    FFitDateStr: string;
    function GetPointCount: Integer;
  public
    constructor Create(Kind: TCoilModelKind = cmModelA);
    procedure SetModel(Kind: TCoilModelKind);

    { Puntos }
    procedure AddPoint(const I, B: TVec3);
    procedure ClearPoints;
    function RemovePoint(idx: Integer): Boolean;
    function GetPoint(idx: Integer; out p: TCalibPoint): Boolean;
    property PointCount: Integer read GetPointCount;

    { Ajuste. Requiere >= 4 puntos no coplanares (incluir I=0). False si singular. }
    function Fit: Boolean;
    function Predict(const I: TVec3): TVec3;  // M·I + b (requiere Fitted)

    { Fija un modelo M, b directamente (sin ajustar puntos): recomputa R/G/Ginv. }
    function SetManualModel(const AM: TMat3; const Ab: TVec3): Boolean;
    { Modelo nominal de catálogo: M = diag(KNominal del modelo de bobina), b = 0. }
    function SetNominalModel: Boolean;

    property Fitted: Boolean read FFitted;
    property M: TMat3 read FM;
    property b: TVec3 read Fb;
    property R: TMat3 read FR;
    property G: TMat3 read FG;
    property Ginv: TMat3 read FGinv;
    property ResidualRMS: Double read FResidualRMS;
    property Model: TCoilModelInfo read FModel;
    property FitDateStr: string read FFitDateStr;

    { Persistencia }
    function SaveToJSON: string;
    function LoadFromJSON(const s: string): Boolean;
    function SaveToFile(const path: string): Boolean;
    function LoadFromFile(const path: string): Boolean;
  end;

function CoilModelInfo(Kind: TCoilModelKind): TCoilModelInfo;
function CoilModelKindToStr(Kind: TCoilModelKind): string;
function StrToCoilModelKind(const s: string; out Kind: TCoilModelKind): Boolean;

implementation

uses
  System.Generics.Collections, System.JSON;

function CoilModelInfo(Kind: TCoilModelKind): TCoilModelInfo;
begin
  Result.Kind := Kind;
  case Kind of
    cmModelA:
      begin
        Result.Name := 'A (paralelo, 1.0 mT/eje, 40 A)';
        Result.IMaxPerAxis := 40.0;
        Result.BMaxPerAxis := 1000.0;
        Result.KNominal := Vec3(24.8, 25.3, 25.1);
      end;
    cmModelB:
      begin
        Result.Name := 'B (240 µT/eje, 16 A)';
        Result.IMaxPerAxis := 16.0;
        Result.BMaxPerAxis := 240.0;
        Result.KNominal := Vec3(14.4, 14.7, 15.1);
      end;
  end;
end;

function CoilModelKindToStr(Kind: TCoilModelKind): string;
begin
  if Kind = cmModelB then Result := 'B' else Result := 'A';
end;

function StrToCoilModelKind(const s: string; out Kind: TCoilModelKind): Boolean;
begin
  if SameText(Trim(s), 'A') then begin Kind := cmModelA; Exit(True); end;
  if SameText(Trim(s), 'B') then begin Kind := cmModelB; Exit(True); end;
  Kind := cmModelA;
  Result := False;
end;

{ ---- TCalibration ---- }

constructor TCalibration.Create(Kind: TCoilModelKind);
begin
  inherited Create;
  SetModel(Kind);
  FFitted := False;
  FResidualRMS := 0;
  FFitDateStr := '';
end;

procedure TCalibration.SetModel(Kind: TCoilModelKind);
begin
  FModel := CoilModelInfo(Kind);
end;

function TCalibration.GetPointCount: Integer;
begin
  Result := Length(FPoints);
end;

procedure TCalibration.AddPoint(const I, B: TVec3);
var n: Integer;
begin
  n := Length(FPoints);
  SetLength(FPoints, n + 1);
  FPoints[n].I := I;
  FPoints[n].B := B;
  FFitted := False;  // los puntos cambiaron
end;

procedure TCalibration.ClearPoints;
begin
  SetLength(FPoints, 0);
  FFitted := False;
end;

function TCalibration.RemovePoint(idx: Integer): Boolean;
var i: Integer;
begin
  if (idx < 0) or (idx >= Length(FPoints)) then Exit(False);
  for i := idx to High(FPoints) - 1 do
    FPoints[i] := FPoints[i + 1];
  SetLength(FPoints, Length(FPoints) - 1);
  FFitted := False;
  Result := True;
end;

function TCalibration.GetPoint(idx: Integer; out p: TCalibPoint): Boolean;
begin
  if (idx < 0) or (idx >= Length(FPoints)) then Exit(False);
  p := FPoints[idx];
  Result := True;
end;

function TCalibration.Fit: Boolean;
var
  Iarr, Barr: array of TVec3;
  k: Integer;
  res: TVec3;
  sumsq: Double;
begin
  FFitted := False;
  if Length(FPoints) < 4 then Exit(False);

  SetLength(Iarr, Length(FPoints));
  SetLength(Barr, Length(FPoints));
  for k := 0 to High(FPoints) do
  begin
    Iarr[k] := FPoints[k].I;
    Barr[k] := FPoints[k].B;
  end;

  if not SolveAffine(Iarr, Barr, FM, Fb) then Exit(False);
  if not (PolarDecomp(FM, FR, FG) and Mat3Inverse(FG, FGinv)) then Exit(False);

  // residuo RMS = sqrt( mean_k |B_k - (M·I_k + b)|² )
  sumsq := 0;
  for k := 0 to High(FPoints) do
  begin
    res := Vec3Sub(FPoints[k].B, Vec3Add(Mat3MulVec(FM, FPoints[k].I), Fb));
    sumsq := sumsq + Vec3Dot(res, res);
  end;
  FResidualRMS := Sqrt(sumsq / Length(FPoints));

  FFitDateStr := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
  FFitted := True;
  Result := True;
end;

function TCalibration.Predict(const I: TVec3): TVec3;
begin
  Result := Vec3Add(Mat3MulVec(FM, I), Fb);
end;

function TCalibration.SetManualModel(const AM: TMat3; const Ab: TVec3): Boolean;
begin
  FM := AM;
  Fb := Ab;
  FResidualRMS := 0;
  if PolarDecomp(FM, FR, FG) and Mat3Inverse(FG, FGinv) then
  begin
    FFitDateStr := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
    FFitted := True;
  end
  else
    FFitted := False;
  Result := FFitted;
end;

function TCalibration.SetNominalModel: Boolean;
var mm: TMat3; i, j: Integer;
begin
  for i := 0 to 2 do for j := 0 to 2 do mm[i, j] := 0;
  mm[0, 0] := FModel.KNominal[0];
  mm[1, 1] := FModel.KNominal[1];
  mm[2, 2] := FModel.KNominal[2];
  Result := SetManualModel(mm, Vec3(0, 0, 0));
end;

{ ---- JSON (System.JSON) ---- }

function Vec3ToJSON(const v: TVec3): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(v[0]); Result.Add(v[1]); Result.Add(v[2]);
end;

function Mat3ToJSON(const m: TMat3): TJSONArray;
var i, j: Integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to 2 do
    for j := 0 to 2 do
      Result.Add(m[i, j]);  // row-major
end;

function JSONNum(a: TJSONValue; out d: Double): Boolean;
begin
  d := 0;
  if a is TJSONNumber then
  begin
    d := TJSONNumber(a).AsDouble;
    Exit(True);
  end;
  Result := False;
end;

function JSONToVec3(a: TJSONValue; out v: TVec3): Boolean;
var arr: TJSONArray;
begin
  v[0] := 0; v[1] := 0; v[2] := 0;
  if not (a is TJSONArray) then Exit(False);
  arr := TJSONArray(a);
  if arr.Count <> 3 then Exit(False);
  Result := JSONNum(arr.Items[0], v[0]) and JSONNum(arr.Items[1], v[1])
            and JSONNum(arr.Items[2], v[2]);
end;

function JSONToMat3(a: TJSONValue; out m: TMat3): Boolean;
var arr: TJSONArray; i, j, idx: Integer;
begin
  FillChar(m, SizeOf(m), 0);
  if not (a is TJSONArray) then Exit(False);
  arr := TJSONArray(a);
  if arr.Count <> 9 then Exit(False);
  idx := 0;
  for i := 0 to 2 do
    for j := 0 to 2 do
    begin
      if not JSONNum(arr.Items[idx], m[i, j]) then Exit(False);
      Inc(idx);
    end;
  Result := True;
end;

function TCalibration.SaveToJSON: string;
var
  root, pt: TJSONObject;
  pts: TJSONArray;
  k: Integer;
begin
  root := TJSONObject.Create;
  try
    root.AddPair('version', TJSONNumber.Create(1));
    root.AddPair('coilModel', CoilModelKindToStr(FModel.Kind));
    root.AddPair('date', FFitDateStr);
    root.AddPair('fitted', TJSONBool.Create(FFitted));
    root.AddPair('residualRMS', TJSONNumber.Create(FResidualRMS));
    root.AddPair('pointCount', TJSONNumber.Create(Length(FPoints)));
    if FFitted then
    begin
      root.AddPair('M', Mat3ToJSON(FM));
      root.AddPair('b', Vec3ToJSON(Fb));
    end;
    pts := TJSONArray.Create;
    for k := 0 to High(FPoints) do
    begin
      pt := TJSONObject.Create;
      pt.AddPair('I', Vec3ToJSON(FPoints[k].I));
      pt.AddPair('B', Vec3ToJSON(FPoints[k].B));
      pts.AddElement(pt);
    end;
    root.AddPair('points', pts);
    Result := root.Format(2);
  finally
    root.Free;
  end;
end;

function TCalibration.LoadFromJSON(const s: string): Boolean;
var
  j: TJSONValue;
  root, pt: TJSONObject;
  pts: TJSONArray;
  jv: TJSONValue;
  kind: TCoilModelKind;
  sModel: string;
  k: Integer;
  vI, vB: TVec3;
  mTmp: TMat3;
  bTmp: TVec3;
  d: Double;
  hadModel: Boolean;
begin
  j := TJSONObject.ParseJSONValue(s);
  if j = nil then Exit(False);
  try
    if not (j is TJSONObject) then Exit(False);
    root := TJSONObject(j);

    // modelo de bobina
    sModel := 'A';
    jv := root.GetValue('coilModel');
    if jv is TJSONString then sModel := TJSONString(jv).Value;
    if StrToCoilModelKind(sModel, kind) then SetModel(kind) else SetModel(cmModelA);

    FFitDateStr := '';
    jv := root.GetValue('date');
    if jv is TJSONString then FFitDateStr := TJSONString(jv).Value;

    FResidualRMS := 0;
    if JSONNum(root.GetValue('residualRMS'), d) then FResidualRMS := d;

    // M, b (si el perfil estaba ajustado)
    hadModel := False;
    if JSONToMat3(root.GetValue('M'), mTmp) and JSONToVec3(root.GetValue('b'), bTmp) then
    begin
      FM := mTmp; Fb := bTmp;
      hadModel := True;
    end;

    // puntos
    ClearPoints;
    jv := root.GetValue('points');
    if jv is TJSONArray then
    begin
      pts := TJSONArray(jv);
      for k := 0 to pts.Count - 1 do
        if pts.Items[k] is TJSONObject then
        begin
          pt := TJSONObject(pts.Items[k]);
          if JSONToVec3(pt.GetValue('I'), vI) and JSONToVec3(pt.GetValue('B'), vB) then
            AddPoint(vI, vB);
        end;
    end;

    // si había modelo, recomputa R, G, Ginv para dejarlo operativo
    FFitted := False;
    if hadModel then
      if PolarDecomp(FM, FR, FG) and Mat3Inverse(FG, FGinv) then
        FFitted := True;

    Result := True;
  finally
    j.Free;
  end;
end;

function TCalibration.SaveToFile(const path: string): Boolean;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Text := SaveToJSON;
    try
      sl.SaveToFile(path);
      Result := True;
    except
      Result := False;
    end;
  finally
    sl.Free;
  end;
end;

function TCalibration.LoadFromFile(const path: string): Boolean;
var sl: TStringList;
begin
  if not FileExists(path) then Exit(False);
  sl := TStringList.Create;
  try
    try
      sl.LoadFromFile(path);
    except
      Exit(False);
    end;
    Result := LoadFromJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

end.
