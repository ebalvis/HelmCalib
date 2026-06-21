program RenderGif;

{ Genera un GIF animado de la vista 3D rotando (yaw 0..360).
  Uso: RenderGif [salida.gif] }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Math, Vcl.Graphics, Vcl.Imaging.GIFImg,
  uMatrix, uView3D;

const
  FRAMES = 24;
  W = 460;
  H = 380;

var
  view: TView3DPanel;
  gif: TGIFImage;
  bmp: TBitmap;
  frame: TGIFFrame;
  i: Integer;
  outFile: string;
begin
  if ParamCount >= 1 then outFile := ParamStr(1) else outFile := 'view3d.gif';

  view := TView3DPanel.Create(nil);
  gif := TGIFImage.Create;
  try
    view.SetTarget(Vec3(40, 20, 60));
    for i := 0 to FRAMES - 1 do
    begin
      view.SetView(2 * Pi * i / FRAMES, 0.35, 1.0);
      bmp := TBitmap.Create;
      try
        bmp.SetSize(W, H);
        bmp.PixelFormat := pf24bit;
        view.RenderTo(bmp.Canvas, W, H);
        frame := gif.Add(bmp);
      finally
        bmp.Free;
      end;
      with TGIFGraphicControlExtension.Create(frame) do
      begin
        Delay := 6;                  // 1/100 s por fotograma
        Disposal := dmBackground;
      end;
    end;
    // bucle infinito
    TGIFAppExtNSLoop.Create(gif.Images.Frames[0]).Loops := 0;
    gif.SaveToFile(outFile);
    WriteLn(Format('GIF guardado: %s (%d fotogramas)', [outFile, FRAMES]));
  finally
    gif.Free;
    view.Free;
  end;
end.
