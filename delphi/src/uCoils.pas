unit uCoils;

{ Cliente TCP del protocolo de texto de HelmMagControl (actuador = fuentes Wanptek).

  Protocolo (una línea por comando, respuesta 'OK ...' / 'ERROR ...'; separador
  decimal '.'; canales 1..3 = ejes X/Y/Z):
    PING                 -> OK PONG
    SET I<n> <amp>       -> OK SET I<n>=<val>
    SET V<n> <volt>      -> OK SET V<n>=<val>
    OUT <n> ON|OFF       -> OK OUT <n> ON|OFF
    ALL OFF              -> OK ALL OFF
    GET I<n>/V<n>/P<n>   -> OK I<n>=<val> / V<n>=.. / P<n>=..
    STATUS <n>           -> OK STATUS <n> ON|OFF [extra]
    READ ALL             -> OK CH1 V=.. I=.. OUT=ON | CH2 .. | CH3 ..

  La lógica de protocolo (formato de comandos y parseo de respuestas) está en
  funciones puras testeables sin red. El I/O TCP se aísla en TCoilClient.

  Port a Delphi (VCL/Win64): transporte TCP con Indy 10 (TIdTCPClient). }

interface

uses
  System.Classes, System.SysUtils, IdTCPClient, IdGlobal;

type
  TStringArray = array of string;

  TCoilChannel = record
    Valid: Boolean;
    Volt, Curr: Double;
    Output: Boolean;
  end;
  TCoilReadAll = array[1..3] of TCoilChannel;

{ ---- Lógica de protocolo (pura, sin red) ---- }

{ Formatea comandos con separador decimal '.' (invariante). }
function CoilFmtSetI(ch: Integer; amp: Double): string;
function CoilFmtSetV(ch: Integer; volt: Double): string;
function CoilFmtOut(ch: Integer; AOn: Boolean): string;

{ True si la respuesta es afirmativa ('OK ...'). }
function CoilRespOK(const resp: string): Boolean;

{ Extrae el valor numérico de una respuesta tipo 'OK I1=1.234560'.
  key p.ej. 'I1', 'V2', 'P3'. False si no aparece 'key=' o no es número. }
function CoilParseValue(const resp, key: string; out v: Double): Boolean;

{ Parsea 'OK CH1 V=.. I=.. OUT=ON | CH2 .. | CH3 ..'. Marca Valid por canal. }
function CoilParseReadAll(const resp: string; out data: TCoilReadAll): Boolean;

type
  { Cliente TCP. Conexión persistente; cada comando manda una línea (CRLF) y
    lee la respuesta hasta LF (tolera CR). Errores de transporte -> False. }
  TCoilClient = class
  private
    FTcp: TIdTCPClient;
    FTimeoutMs: Integer;
    function ReadLine(out line: string): Boolean;
    function WriteLine(const s: string): Boolean;
  public
    constructor Create(ATimeoutMs: Integer = 3000);
    destructor Destroy; override;
    function Connect(const Host: string; Port: Word): Boolean;
    procedure Disconnect;
    function Connected: Boolean;
    { Envía Cmd y devuelve la respuesta cruda. False si falla el transporte. }
    function SendCommand(const Cmd: string; out Resp: string): Boolean;
    function Ping: Boolean;
    function SetCurrent(ch: Integer; amp: Double): Boolean;
    function SetVoltage(ch: Integer; volt: Double): Boolean;
    function Output(ch: Integer; AOn: Boolean): Boolean;
    function AllOff: Boolean;
    function ReadAll(out data: TCoilReadAll): Boolean;
  end;

implementation

var
  gFS: TFormatSettings;  // invariante para el protocolo

{ ---- helpers ---- }

function SplitTokens(const s: string; sep: Char): TStringArray;
var
  sl: TStringList;
  i: Integer;
begin
  Result := nil;
  sl := TStringList.Create;
  try
    sl.Delimiter := sep;
    sl.StrictDelimiter := True;
    sl.DelimitedText := s;
    SetLength(Result, sl.Count);
    for i := 0 to sl.Count - 1 do Result[i] := Trim(sl[i]);
  finally
    sl.Free;
  end;
end;

{ ---- Lógica de protocolo ---- }

function CoilFmtSetI(ch: Integer; amp: Double): string;
begin
  Result := Format('SET I%d %.6f', [ch, amp], gFS);
end;

function CoilFmtSetV(ch: Integer; volt: Double): string;
begin
  Result := Format('SET V%d %.6f', [ch, volt], gFS);
end;

function CoilFmtOut(ch: Integer; AOn: Boolean): string;
begin
  if AOn then
    Result := Format('OUT %d ON', [ch])
  else
    Result := Format('OUT %d OFF', [ch]);
end;

function CoilRespOK(const resp: string): Boolean;
var t: string;
begin
  t := Trim(resp);
  Result := (Length(t) >= 2) and SameText(Copy(t, 1, 2), 'OK')
            and ((Length(t) = 2) or (t[3] = ' '));
end;

function CoilParseValue(const resp, key: string; out v: Double): Boolean;
var
  p, q: Integer;
  num: string;
begin
  v := 0;
  p := Pos(UpperCase(key) + '=', UpperCase(resp));
  if p = 0 then Exit(False);
  Inc(p, Length(key) + 1);  // tras 'key='
  q := p;
  while (q <= Length(resp)) and CharInSet(resp[q], ['0'..'9', '+', '-', '.', 'e', 'E']) do
    Inc(q);
  num := Copy(resp, p, q - p);
  Result := TryStrToFloat(num, v, gFS);
end;

function CoilParseReadAll(const resp: string; out data: TCoilReadAll): Boolean;
var
  body, part: string;
  parts, toks: TStringArray;
  i, j, ch: Integer;
  d: Double;
begin
  for i := 1 to 3 do
  begin
    data[i].Valid := False;
    data[i].Volt := 0; data[i].Curr := 0; data[i].Output := False;
  end;
  if not CoilRespOK(resp) then Exit(False);

  body := Trim(resp);
  Delete(body, 1, 2);            // quita 'OK'
  body := Trim(body);

  parts := SplitTokens(body, '|');
  for i := 0 to High(parts) do
  begin
    part := parts[i];
    if part = '' then Continue;
    toks := SplitTokens(StringReplace(part, ' ', #9, [rfReplaceAll]), #9);
    // primer token: CHn
    if (Length(toks) = 0) or (Length(toks[0]) < 3)
       or not SameText(Copy(toks[0], 1, 2), 'CH') then Continue;
    ch := StrToIntDef(Copy(toks[0], 3, MaxInt), 0);
    if (ch < 1) or (ch > 3) then Continue;
    for j := 1 to High(toks) do
    begin
      if CoilParseValue(toks[j], 'V', d) then data[ch].Volt := d
      else if CoilParseValue(toks[j], 'I', d) then data[ch].Curr := d
      else if Pos('OUT=', UpperCase(toks[j])) = 1 then
        data[ch].Output := SameText(Trim(Copy(toks[j], 5, MaxInt)), 'ON');
    end;
    data[ch].Valid := True;
  end;
  Result := True;
end;

{ ---- TCoilClient ---- }

constructor TCoilClient.Create(ATimeoutMs: Integer);
begin
  inherited Create;
  FTimeoutMs := ATimeoutMs;
  FTcp := TIdTCPClient.Create(nil);
end;

destructor TCoilClient.Destroy;
begin
  Disconnect;
  FTcp.Free;
  inherited Destroy;
end;

function TCoilClient.Connected: Boolean;
begin
  Result := Assigned(FTcp) and FTcp.Connected;
end;

function TCoilClient.Connect(const Host: string; Port: Word): Boolean;
begin
  Disconnect;
  try
    FTcp.Host := Host;
    FTcp.Port := Port;
    FTcp.ConnectTimeout := FTimeoutMs;
    FTcp.ReadTimeout := FTimeoutMs;
    FTcp.Connect;
    Result := FTcp.Connected;
  except
    Result := False;
  end;
end;

procedure TCoilClient.Disconnect;
begin
  try
    if FTcp.Connected then FTcp.Disconnect;
  except
    // ignora errores al cerrar
  end;
end;

function TCoilClient.WriteLine(const s: string): Boolean;
begin
  if not Connected then Exit(False);
  try
    FTcp.IOHandler.WriteLn(s);   // Indy añade el terminador (compatible con el servidor Indy)
    Result := True;
  except
    Result := False;
  end;
end;

function TCoilClient.ReadLine(out line: string): Boolean;
begin
  line := '';
  if not Connected then Exit(False);
  try
    line := FTcp.IOHandler.ReadLn;   // lee hasta el terminador; respeta ReadTimeout
    Result := not FTcp.IOHandler.ReadLnTimedout;
  except
    Result := False;
  end;
end;

function TCoilClient.SendCommand(const Cmd: string; out Resp: string): Boolean;
begin
  Resp := '';
  if not Connected then Exit(False);
  if not WriteLine(Cmd) then Exit(False);
  Result := ReadLine(Resp);
end;

function TCoilClient.Ping: Boolean;
var r: string;
begin
  Result := SendCommand('PING', r) and CoilRespOK(r) and (Pos('PONG', UpperCase(r)) > 0);
end;

function TCoilClient.SetCurrent(ch: Integer; amp: Double): Boolean;
var r: string;
begin
  Result := SendCommand(CoilFmtSetI(ch, amp), r) and CoilRespOK(r);
end;

function TCoilClient.SetVoltage(ch: Integer; volt: Double): Boolean;
var r: string;
begin
  Result := SendCommand(CoilFmtSetV(ch, volt), r) and CoilRespOK(r);
end;

function TCoilClient.Output(ch: Integer; AOn: Boolean): Boolean;
var r: string;
begin
  Result := SendCommand(CoilFmtOut(ch, AOn), r) and CoilRespOK(r);
end;

function TCoilClient.AllOff: Boolean;
var r: string;
begin
  Result := SendCommand('ALL OFF', r) and CoilRespOK(r);
end;

function TCoilClient.ReadAll(out data: TCoilReadAll): Boolean;
var r: string;
begin
  Result := SendCommand('READ ALL', r) and CoilParseReadAll(r, data);
end;

initialization
  gFS := TFormatSettings.Invariant;   // separador decimal '.', sin miles

end.
