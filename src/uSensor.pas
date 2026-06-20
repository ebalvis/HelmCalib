unit uSensor;

{ Cliente UDP de SensorCast (magnetómetro del móvil en el centro de las bobinas).

  Protocolo: el cliente envía el texto 'HOLA' a IP_móvil:51042; el móvil registra
  al cliente y le envía cada ~200 ms a :51043 un JSON con dos objetos:
    "accelerometer": x, y, z   y   "magnetometer": x, y, z
  Usamos magnetometer (µT). El acelerómetro es opcional (orientación del móvil).

  ParseSensorJSON es pura (testeable sin red). El I/O UDP vive en un hilo
  (TSensorClient) que mantiene la última muestra y un historial para promediar K. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, SyncObjs, Sockets, uMatrix;

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
    FSock: LongInt;
    FLock: TCriticalSection;
    FLast: TSensorSample;
    FLastTime: TDateTime;
    FHasSample: Boolean;
    FHist: array of TVec3;     // historial de magnetómetro (anillo)
    FHistCap, FHistCount, FHistPos: Integer;
    procedure StoreSample(const s: TSensorSample);
    function SetupSocket: Boolean;
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
  fpjson, jsonparser;

{ ---- Parser puro ---- }

function ReadVec3(obj: TJSONObject; const name: string; out v: TVec3): Boolean;
var sub: TJSONData; o: TJSONObject;
begin
  v[0] := 0; v[1] := 0; v[2] := 0;
  sub := obj.Find(name);
  if (sub = nil) or not (sub is TJSONObject) then Exit(False);
  o := TJSONObject(sub);
  if (o.Find('x') = nil) or (o.Find('y') = nil) or (o.Find('z') = nil) then Exit(False);
  try
    v[0] := o.Floats['x'];
    v[1] := o.Floats['y'];
    v[2] := o.Floats['z'];
  except
    Exit(False);
  end;
  Result := True;
end;

function ParseSensorJSON(const s: string; out sample: TSensorSample): Boolean;
var
  j: TJSONData;
  o: TJSONObject;
begin
  sample.HasAcc := False;
  FillChar(sample.Acc, SizeOf(sample.Acc), 0);
  FillChar(sample.Mag, SizeOf(sample.Mag), 0);
  j := nil;
  try
    try
      j := GetJSON(s);
    except
      Exit(False);
    end;
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
  FSock := -1;
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
  if not Suspended then
    WaitFor;
  FLock.Free;
  inherited Destroy;
end;

procedure TSensorClient.StartClient;
begin
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

function TSensorClient.SetupSocket: Boolean;
var
  addr: TInetSockAddr;
{$IFDEF WINDOWS}
  tv: DWord;
{$ELSE}
  tv: TTimeVal;
{$ENDIF}
begin
  FSock := fpSocket(AF_INET, SOCK_DGRAM, 0);
  if FSock < 0 then Exit(False);

  addr.sin_family := AF_INET;
  addr.sin_port := htons(FRecvPort);
  addr.sin_addr.s_addr := 0;  // INADDR_ANY
  if fpBind(FSock, @addr, SizeOf(addr)) <> 0 then
  begin
    CloseSocket(FSock);
    FSock := -1;
    Exit(False);
  end;

  // timeout de recepción ~500 ms para poder revisar Terminated
{$IFDEF WINDOWS}
  tv := 500;
  fpSetSockOpt(FSock, SOL_SOCKET, SO_RCVTIMEO, @tv, SizeOf(tv));
{$ELSE}
  tv.tv_sec := 0;
  tv.tv_usec := 500 * 1000;
  fpSetSockOpt(FSock, SOL_SOCKET, SO_RCVTIMEO, @tv, SizeOf(tv));
{$ENDIF}
  Result := True;
end;

procedure TSensorClient.Execute;
var
  dest: TInetSockAddr;
  fromAddr: TInetSockAddr;
  fromLen: TSockLen;
  buf: array[0..2047] of Byte;
  n: Integer;
  pkt: string;
  sample: TSensorSample;
  hello: AnsiString;
  lastHello: TDateTime;
  firstSent: Boolean;
begin
  if not SetupSocket then Exit;
  try
    dest.sin_family := AF_INET;
    dest.sin_port := htons(FSendPort);
    dest.sin_addr := StrToNetAddr(FPhoneIP);
    hello := 'HOLA';
    lastHello := 0;
    firstSent := False;

    while not Terminated do
    begin
      // (re)registro: HOLA al arrancar y luego cada ~1 s
      if (not firstSent) or (MilliSecondsBetween(Now, lastHello) >= 1000) then
      begin
        fpSendTo(FSock, @hello[1], Length(hello), 0, @dest, SizeOf(dest));
        lastHello := Now;
        firstSent := True;
      end;

      fromLen := SizeOf(fromAddr);
      n := fpRecvFrom(FSock, @buf[0], SizeOf(buf), 0, @fromAddr, @fromLen);
      if n > 0 then
      begin
        SetString(pkt, PAnsiChar(@buf[0]), n);
        if ParseSensorJSON(pkt, sample) then
          StoreSample(sample);
      end;
      // n <= 0: timeout o error -> volver a comprobar Terminated
    end;
  finally
    if FSock >= 0 then
    begin
      CloseSocket(FSock);
      FSock := -1;
    end;
  end;
end;

end.
