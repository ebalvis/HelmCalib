unit uRemote;

{ Servidor TCP de texto para control remoto de HelmCalib (mismo estilo que el de
  HelmMagControl): una línea por comando, respuesta 'OK ...' / 'ERROR ...', UTF-8.

  El servidor solo hace de transporte: por cada línea recibida invoca OnCommand
  EN EL HILO PRINCIPAL (TThread.Synchronize), de modo que el manejador puede tocar
  con seguridad los mismos objetos (bobinas/sensor/calibración) que usa la GUI.

  Port a Delphi (VCL/Win64): Indy 10 (TIdTCPServer). }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs,
  IdContext, IdTCPServer, IdGlobal;

type
  TRemoteCommandFunc = reference to function(const Cmd: string): string;

  TRemoteServer = class
  private
    FServer: TIdTCPServer;
    FOnCommand: TRemoteCommandFunc;
    procedure DoConnect(AContext: TIdContext);
    procedure DoExecute(AContext: TIdContext);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(APort: Integer);
    procedure Stop;
    function Active: Boolean;
    property OnCommand: TRemoteCommandFunc read FOnCommand write FOnCommand;
  end;

implementation

constructor TRemoteServer.Create;
begin
  inherited Create;
  FServer := TIdTCPServer.Create(nil);
  FServer.OnConnect := DoConnect;
  FServer.OnExecute := DoExecute;
  FServer.TerminateWaitTime := 2000;
end;

destructor TRemoteServer.Destroy;
begin
  Stop;
  FServer.Free;
  inherited Destroy;
end;

procedure TRemoteServer.Start(APort: Integer);
begin
  if FServer.Active then FServer.Active := False;
  FServer.DefaultPort := APort;
  FServer.Active := True;
end;

procedure TRemoteServer.Stop;
begin
  if FServer.Active then FServer.Active := False;
end;

function TRemoteServer.Active: Boolean;
begin
  Result := FServer.Active;
end;

procedure TRemoteServer.DoConnect(AContext: TIdContext);
begin
  AContext.Connection.IOHandler.DefStringEncoding := IndyTextEncoding_UTF8;
end;

procedure TRemoteServer.DoExecute(AContext: TIdContext);
var
  cmd, resp: string;
begin
  cmd := AContext.Connection.IOHandler.ReadLn;
  resp := '';
  // procesa el comando en el hilo principal (acceso seguro al estado de la GUI)
  TThread.Synchronize(nil,
    procedure
    begin
      if Assigned(FOnCommand) then
        try
          resp := FOnCommand(Trim(cmd));
        except
          on E: Exception do
            resp := 'ERROR ' + E.ClassName + ': ' + E.Message;
        end
      else
        resp := 'ERROR NoHandler';
    end);
  AContext.Connection.IOHandler.WriteLn(resp);
end;

end.
