program TestCoils;

{ Tests de la lógica de protocolo de uCoils (sin red). }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, uCoils;

var
  gFail: Integer = 0;
  gPass: Integer = 0;

procedure Check(const name: string; cond: Boolean);
begin
  if cond then begin Inc(gPass); WriteLn('  ok   ', name); end
          else begin Inc(gFail); WriteLn('  FAIL ', name); end;
end;

function Near(const a, b: Double): Boolean;
begin
  Result := Abs(a - b) <= 1e-6;
end;

var
  d: TCoilReadAll;
  v: Double;

begin
  WriteLn('=== Tests uCoils ===');

  WriteLn('Formato de comandos:');
  Check('SET I1 1.5', CoilFmtSetI(1, 1.5) = 'SET I1 1.500000');
  Check('SET I2 -3.25', CoilFmtSetI(2, -3.25) = 'SET I2 -3.250000');
  Check('SET V3 12', CoilFmtSetV(3, 12) = 'SET V3 12.000000');
  Check('OUT 2 ON', CoilFmtOut(2, True) = 'OUT 2 ON');
  Check('OUT 3 OFF', CoilFmtOut(3, False) = 'OUT 3 OFF');

  WriteLn('Respuesta OK/ERROR:');
  Check('OK PONG -> ok', CoilRespOK('OK PONG'));
  Check('OK solo -> ok', CoilRespOK('OK'));
  Check('ERROR -> no', not CoilRespOK('ERROR UnknownCommand'));
  Check('OKAY no es OK', not CoilRespOK('OKAY foo'));

  WriteLn('Parseo de valor:');
  Check('GET I1=1.23456', CoilParseValue('OK I1=1.234560', 'I1', v) and Near(v, 1.23456));
  Check('GET V2 negativo', CoilParseValue('OK V2=-3.500000', 'V2', v) and Near(v, -3.5));
  Check('clave ausente -> no', not CoilParseValue('OK I1=1.0', 'P3', v));

  WriteLn('Parseo READ ALL:');
  Check('parsea', CoilParseReadAll(
    'OK CH1 V=1.000000 I=2.000000 OUT=ON | CH2 V=0.000000 I=0.000000 OUT=OFF | CH3 V=5.000000 I=-1.500000 OUT=ON', d));
  Check('CH1 V', Near(d[1].Volt, 1.0));
  Check('CH1 I', Near(d[1].Curr, 2.0));
  Check('CH1 OUT=ON', d[1].Output);
  Check('CH2 OUT=OFF', not d[2].Output);
  Check('CH3 I negativa', Near(d[3].Curr, -1.5));
  Check('CH3 OUT=ON', d[3].Output);
  Check('los 3 válidos', d[1].Valid and d[2].Valid and d[3].Valid);
  Check('ERROR -> no parsea', not CoilParseReadAll('ERROR NoBackend', d));

  WriteLn;
  WriteLn(Format('Resultado: %d ok, %d fallos', [gPass, gFail]));
  Halt(gFail);
end.
