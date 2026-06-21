program TestSensor;

{ Tests del parser JSON de uSensor (sin red). }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, uSensor;

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
  s: TSensorSample;

begin
  WriteLn('=== Tests uSensor ===');

  WriteLn('JSON completo:');
  Check('parsea', ParseSensorJSON(
    '{"accelerometer":{"x":0.1,"y":-0.2,"z":9.8},"magnetometer":{"x":12.5,"y":-30.0,"z":45.25}}', s));
  Check('mag x', Near(s.Mag[0], 12.5));
  Check('mag y', Near(s.Mag[1], -30.0));
  Check('mag z', Near(s.Mag[2], 45.25));
  Check('tiene acc', s.HasAcc);
  Check('acc z', Near(s.Acc[2], 9.8));

  WriteLn('Solo magnetómetro:');
  Check('parsea', ParseSensorJSON('{"magnetometer":{"x":1,"y":2,"z":3}}', s));
  Check('mag enteros', Near(s.Mag[0], 1) and Near(s.Mag[1], 2) and Near(s.Mag[2], 3));
  Check('sin acc', not s.HasAcc);

  WriteLn('Casos inválidos:');
  Check('sin magnetómetro -> no', not ParseSensorJSON('{"accelerometer":{"x":0,"y":0,"z":0}}', s));
  Check('mag incompleto -> no', not ParseSensorJSON('{"magnetometer":{"x":1,"y":2}}', s));
  Check('JSON corrupto -> no', not ParseSensorJSON('{"magnetometer":{"x":1,', s));
  Check('vacío -> no', not ParseSensorJSON('', s));
  Check('no objeto -> no', not ParseSensorJSON('[1,2,3]', s));

  WriteLn;
  WriteLn(Format('Resultado: %d ok, %d fallos', [gPass, gFail]));
  Halt(gFail);
end.
