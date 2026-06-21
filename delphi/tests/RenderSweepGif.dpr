program RenderSweepGif;

{ GIF animado del barrido de calibración: recorre las 13 combinaciones de corriente
  del asistente y, en cada punto, muestra los ejes energizados (bobinas resaltadas)
  y el vector B resultante (modelo nominal de catálogo), con su rótulo.
  Uso: RenderSweepGif [salida.gif] }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Math, Vcl.Graphics, Vcl.Imaging.GIFImg,
  uMatrix, uView3D;

const
  W = 460;
  H = 380;
  I0 = 4.0;                                   // amplitud del barrido (A)
  K: array[0..2] of Double = (24.8, 25.3, 25.1);  // µT/A nominal (modelo A)
  COMB: array[0..12, 0..2] of Double = (
    ( 0,  0,  0),
    ( 1,  0,  0), (-1,  0,  0),
    ( 0,  1,  0), ( 0, -1,  0),
    ( 0,  0,  1), ( 0,  0, -1),
    ( 1,  1,  0), ( 1,  0,  1), ( 0,  1,  1),
    ( 1,  1,  1), (-1,  1, -1), ( 1, -1,  1));

var
  view: TView3DPanel;
  gif: TGIFImage;
  bmp: TBitmap;
  frame: TGIFFrame;
  i, ax: Integer;
  cur, b: TVec3;
  outFile: string;
begin
  if ParamCount >= 1 then outFile := ParamStr(1) else outFile := 'calib-sweep.gif';

  view := TView3DPanel.Create(nil);
  gif := TGIFImage.Create;
  try
    view.BmaxRef := 220;                       // escala de la flecha B
    for i := 0 to High(COMB) do
    begin
      for ax := 0 to 2 do
      begin
        cur[ax] := COMB[i, ax] * I0;
        b[ax] := K[ax] * cur[ax];              // B nominal = diag(k)·I
      end;
      view.SetView(0.6 + i * 0.05, 0.35, 1.0); // gira lento mientras barre
      if (Abs(b[0]) + Abs(b[1]) + Abs(b[2])) < 1e-9 then
        view.ClearTarget
      else
        view.SetTarget(b);

      bmp := TBitmap.Create;
      try
        bmp.SetSize(W, H);
        bmp.PixelFormat := pf24bit;
        view.RenderTo(bmp.Canvas, W, H);
        // rótulo del punto y la corriente
        bmp.Canvas.Brush.Style := bsClear;
        bmp.Canvas.Font.Color := clWhite;
        bmp.Canvas.TextOut(8, 8, Format('Barrido  %d/%d', [i + 1, Length(COMB)]));
        bmp.Canvas.Font.Color := TColor($000AA0FF);
        bmp.Canvas.TextOut(8, 26, Format('I = (%.0f, %.0f, %.0f) A',
          [cur[0], cur[1], cur[2]]));
        frame := gif.Add(bmp);
      finally
        bmp.Free;
      end;
      with TGIFGraphicControlExtension.Create(frame) do
      begin
        Delay := 42;                           // ~0,42 s por punto
        Disposal := dmBackground;
      end;
    end;
    TGIFAppExtNSLoop.Create(gif.Images.Frames[0]).Loops := 0;
    gif.SaveToFile(outFile);
    WriteLn(Format('GIF guardado: %s (%d puntos)', [outFile, Length(COMB)]));
  finally
    gif.Free;
    view.Free;
  end;
end.
