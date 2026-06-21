program RenderView;

{ Render offline de la Vista 3D a un PNG, para verificar el dibujo sin abrir la GUI.
  Uso: RenderView [salida.png] }

{$APPTYPE CONSOLE}

uses
  System.Classes, System.SysUtils, Vcl.Graphics, Vcl.Imaging.pngimage,
  uMatrix, uView3D;

var
  view: TView3DPanel;
  bmp: TBitmap;
  png: TPngImage;
  outFile: string;
begin
  if ParamCount >= 1 then outFile := ParamStr(1)
  else outFile := 'view3d.png';

  view := TView3DPanel.Create(nil);
  bmp := TBitmap.Create;
  png := TPngImage.Create;
  try
    bmp.SetSize(640, 480);
    bmp.PixelFormat := pf24bit;
    view.SetTarget(Vec3(40, 20, 60));      // vector B de ejemplo (µT)
    view.RenderTo(bmp.Canvas, bmp.Width, bmp.Height);
    png.Assign(bmp);
    png.SaveToFile(outFile);
    WriteLn('Render guardado en: ', outFile);
  finally
    png.Free;
    bmp.Free;
    view.Free;
  end;
end.
