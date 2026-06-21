unit uSensor;

{ Cliente UDP de SensorCast (magnetómetro del móvil en el centro de las bobinas).

  Protocolo: el cliente envía el texto 'HOLA' a IP_móvil:51042; el móvil registra
  al cliente y le envía cada ~200 ms a :51043 un JSON con dos objetos:
    "accelerometer": x, y, z   y   "magnetometer": x, y, z
  Usamos magnetometer (µT). El acelerómetro es opcional (orientación del móvil).

  ParseSensorJSON es pura (testeable sin red). El I/O UDP vive en un hilo
  (TSensorClient) que mantiene la última muestra y un historial para promediar K.

  Port a Delphi (VCL/Win64): UDP con Indy 10 (TIdUDPClient), JSON con System.JSON. }

interface

uses
  System.Classes, System.SysUtils, System.DateUtils, System.SyncObjs,
  IdUDPClient, IdGlobal, uMatrix;

type
  TSensorSample = record
    HasAcc: Boolean;
    Acc: TVec3;     // m/s² (opcional)
    Mag: TVec3;     // µT
  end;

{ Parsea un paquete JSON de SensorCast. True solo si 'magnetometer' está presente
  y es numérico. 'accelerometer' es opcional (HasAcc indica si se obtuvo). }
function ParseSensorJSON(const s: string; out sample: TSensorSample): Boolean;

type
  TSensorClient = class(TThread)
  private
    FPhoneIP: string;
    FSendPort, FRecvPort: Word;
    FLock: TCriticalSection;
    FLast: TSensorSample;
    FLastTime: TDateTime;
    FHasSample: Boolean;
    FStarted: Boolean;
    FHist: array of TVec3;     // historial de magnetómetro (anillo)
    FHistCap, FHistCount, FHistPos: Integer;
    procedure StoreSample(const s: TSensorSample);
  protected
    procedure Execute; override;
  public
    constructor Create(const PhoneIP: string; ASendPort: Word = 51042;
      ARecvPort: Word = 51043; AHistCap: Integer = 128);
    destructor Destroy; override;
    { Última muestra y su antigüedad en ms. False si aún no hay ninguna. }
    function GetLatest(out s: TSensorSample; out ageMs: Integer): Boolean;
    { Media de las últimas K muestras de magnetómetro. False si no hay datos. }
    function GetAveragedMag(K: Integer; out mag: TVec3): Boolean;
    procedure StartClient;
  end;

implementation

uses
  System.JSON;

{ ---- Parser puro ---- }

function ReadVec3(obj: TJSONObject; const name: string; out v: TVec3): Boolean;
var sub: TJSONValue; o: TJSONObject; nx, ny, nz: TJSONValue;
begin
  v[0] := 0; v[1] := 0; v[2] := 0;
  sub := obj.GetValue(name);
  if not (sub is TJSONObject) then Exit(False);
  o := TJSONObject(sub);
  nx := o.GetValue('x'); ny := o.GetValue('y'); nz := o.GetValue('z');
  if not ((nx is TJSONNumber) and (ny is TJSONNumber) and (nz is TJSONNumber)) then
    Exit(False);
  v[0] := TJSONNumber(nx).AsDouble;
  v[1] := TJSONNumber(ny).AsDouble;
  v[2] := TJSONNumber(nz).AsDouble;
  Result := True;
end;

function ParseSensorJSON(const s: string; out sample: TSensorSample): Boolean;
var
  j: TJSONValue;
  o: TJSONObject;
begin
  sample.HasAcc := False;
  FillChar(sample.Acc, SizeOf(sample.Acc), 0);
  FillChar(sample.Mag, SizeOf(sample.Mag), 0);
  j := TJSONObject.ParseJSONValue(s);
  if j = nil then Exit(False);
  try
    if not (j is TJSONObject) then Exit(False);
    o := TJSONObject(j);
    if not ReadVec3(o, 'magnetometer', sample.Mag) then Exit(False);
    sample.HasAcc := ReadVec3(o, 'accelerometer', sample.Acc);
    Result := True;
  finally
    j.Free;
  end;
end;

{ ---- TSensorClient ---- }

constructor TSensorClient.Create(const PhoneIP: string; ASendPort: Word;
  ARecvPort: Word; AHistCap: Integer);
begin
  inherited Create(True);   // suspendido
  FreeOnTerminate := False;
  FPhoneIP := PhoneIP;
  FSendPort := ASendPort;
  FRecvPort := ARecvPort;
  FLock := TCriticalSection.Create;
  FHasSample := False;
  FHistCap := AHistCap;
  SetLength(FHist, FHistCap);
  FHistCount := 0;
  FHistPos := 0;
end;

destructor TSensorClient.Destroy;
begin
  Terminate;
  if FStarted then
    WaitFor;
  FLock.Free;
  inherited Destroy;
end;

procedure TSensorClient.StartClient;
begin
  FStarted := True;
  Start;
end;

procedure TSensorClient.StoreSample(const s: TSensorSample);
begin
  FLock.Enter;
  try
    FLast := s;
    FLastTime := Now;
    FHasSample := True;
    FHist[FHistPos] := s.Mag;
    FHistPos := (FHistPos + 1) mod FHistCap;
    if FHistCount < FHistCap then Inc(FHistCount);
  finally
    FLock.Leave;
  end;
end;

function TSensorClient.GetLatest(out s: TSensorSample; out ageMs: Integer): Boolean;
begin
  FLock.Enter;
  try
    Result := FHasSample;
    if Result then
    begin
      s := FLast;
      ageMs := MilliSecondsBetween(Now, FLastTime);
    end
    else
      ageMs := -1;
  finally
    FLock.Leave;
  end;
end;

function TSensorClient.GetAveragedMag(K: Integer; out mag: TVec3): Boolean;
var
  i, n, idx: Integer;
  sx, sy, sz: Double;
begin
  mag[0] := 0; mag[1] := 0; mag[2] := 0;
  FLock.Enter;
  try
    if FHistCount = 0 then Exit(False);
    n := K;
    if n > FHistCount then n := FHistCount;
    if n < 1 then n := 1;
    sx := 0; sy := 0; sz := 0;
    // las n más recientes, retrocediendo desde FHistPos-1
    for i := 1 to n do
    begin
      idx := (FHistPos - i + FHistCap) mod FHistCap;
      sx := sx + FHist[idx, 0];
      sy := sy + FHist[idx, 1];
      sz := sz + FHist[idx, 2];
    end;
    mag[0] := sx / n; mag[1] := sy / n; mag[2] := sz / n;
    Result := True;
  finally
    FLock.Leave;
  end;
end;

procedure TSensorClient.Execute;
var
  udp: TIdUDPClient;
  buf: TIdBytes;
  n: Integer;
  pkt: string;
  sample: TSensorSample;
  lastHello: TDateTime;
  firstSent: Boolean;
begin
  udp := TIdUDPClient.Create(nil);
  try
    udp.BoundPort := FRecvPort;   // puerto local de escucha (:51043)
    try
      udp.Active := True;          // abre y bindea el socket
    except
      Exit;                        // puerto ocupado u otro error
    end;

    lastHello := 0;
    firstSent := False;
    SetLength(buf, 2048);

    while not Terminated do
    begin
      // (re)registro: HOLA al arrancar y luego cada ~1 s
      if (not firstSent) or (MilliSecondsBetween(Now, lastHello) >= 1000) then
      begin
        try
          udp.SendBuffer(FPhoneIP, FSendPort, ToBytes('HOLA', IndyTextEncoding_ASCII));
        except
          // si el móvil no está accesible, seguimos intentando
        end;
        lastHello := Now;
        firstSent := True;
      end;

      // recepción con timeout 500 ms para poder revisar Terminated
      try
        n := udp.ReceiveBuffer(buf, 500);
      except
        n := 0;
      end;
      if n > 0 then
      begin
        pkt := BytesToString(buf, 0, n, IndyTextEncoding_UTF8);
        if ParseSensorJSON(pkt, sample) then
          StoreSample(sample);
      end;
    end;
  finally
    udp.Active := False;
    udp.Free;
  end;
end;

end.
