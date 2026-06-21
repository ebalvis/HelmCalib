unit uRemote;

{ Servidor TCP de texto para control remoto de HelmCalib (mismo estilo que el de
  HelmMagControl): una línea por comando, respuesta 'OK ...' / 'ERROR ...', UTF-8.

  El comando se procesa EN EL HILO PRINCIPAL (TThread.Synchronize) para tocar con
  seguridad los mismos objetos (bobinas/sensor/calibración) que usa la GUI.

  Versión Lazarus/FPC: servidor con ssockets (TInetServer) en un hilo. Un cliente
  a la vez (suficiente para una interfaz de control). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ssockets;

type
  TRemoteCommandFunc = function(const Cmd: string): string of object;

  TRemoteServer = class
  private
    FPort: Integer;
    FServer: TInetServer;
    FThread: TThread;
    FOnCommand: TRemoteCommandFunc;
    FCurCmd, FCurResp: string;
    FRunning: Boolean;
    procedure DoConnect(Sender: TObject; Data: TSocketStream);
    procedure DoProcess;     // se ejecuta en el hilo principal
    procedure ThreadRun;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(APort: Integer);
    procedure Stop;
    function Active: Boolean;
    property OnCommand: TRemoteCommandFunc read FOnCommand write FOnCommand;
  end;

implementation

type
  TRemoteThread = class(TThread)
  private
    FOwner: TRemoteServer;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TRemoteServer);
  end;

constructor TRemoteThread.Create(AOwner: TRemoteServer);
begin
  FOwner := AOwner;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TRemoteThread.Execute;
begin
  FOwner.ThreadRun;
end;

{ TRemoteServer }

constructor TRemoteServer.Create;
begin
  inherited Create;
  FRunning := False;
end;

destructor TRemoteServer.Destroy;
begin
  Stop;
  inherited Destroy;
end;

procedure TRemoteServer.Start(APort: Integer);
begin
  if FRunning then Stop;
  FPort := APort;
  FRunning := True;
  FThread := TRemoteThread.Create(Self);   // arranca y llama a ThreadRun
end;

procedure TRemoteServer.Stop;
begin
  FRunning := False;
  if Assigned(FServer) then
    try
      FServer.StopAccepting(True);
    except
    end;
  FThread := nil;   // el hilo es FreeOnTerminate; se autolibera al salir del accept
end;

function TRemoteServer.Active: Boolean;
begin
  Result := FRunning;
end;

procedure TRemoteServer.ThreadRun;
var srv: TInetServer;
begin
  srv := nil;
  try
    srv := TInetServer.Create(FPort);
    srv.ReuseAddress := True;
    srv.OnConnect := @DoConnect;
    FServer := srv;            // visible para Stop (StopAccepting)
    srv.StartAccepting;        // bloquea hasta StopAccepting o error
  except
    // puerto ocupado, socket cerrado al parar, etc.: termina el hilo
  end;
  if FServer = srv then FServer := nil;  // no pisar el servidor de otro arranque
  srv.Free;
end;

procedure TRemoteServer.DoProcess;
begin
  if Assigned(FOnCommand) then
    try
      FCurResp := FOnCommand(FCurCmd);
    except
      on E: Exception do
        FCurResp := 'ERROR ' + E.ClassName + ': ' + E.Message;
    end
  else
    FCurResp := 'ERROR NoHandler';
end;

procedure TRemoteServer.DoConnect(Sender: TObject; Data: TSocketStream);
var
  b: Byte;
  n: Integer;
  s, r: RawByteString;
  alive: Boolean;
begin
  alive := True;
  while FRunning and alive do
  begin
    // leer una línea (hasta LF; ignora CR)
    s := '';
    repeat
      n := Data.Read(b, 1);
      if n <= 0 then begin alive := False; Break; end;
      if b = 10 then Break;
      if b <> 13 then s := s + AnsiChar(b);
    until False;
    if not alive then Break;

    FCurCmd := Trim(string(s));
    TThread.Synchronize(FThread, @DoProcess);

    r := RawByteString(FCurResp) + #13#10;
    try
      Data.Write(r[1], Length(r));
    except
      alive := False;
    end;
  end;
end;

end.
