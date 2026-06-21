program RenderFieldGif;

{ GIF animado de "Programar campo": para una secuencia de campos objetivo B,
  calcula las corrientes con uField (modelo nominal de catálogo) y muestra el
  vector B, los ejes energizados y las corrientes resultantes.
  Uso: RenderFieldGif [salida.gif] }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Math, Vcl.Graphics, Vcl.Imaging.GIFImg,
  uMatrix, uCalib, uField, uView3D;

const
  FRAMES = 32;
  W = 460;
  H = 380;
  MAG = 500.0;   // módulo del campo objetivo (µT)

var
  view: TView3DPanel;
  cal: TCalibration;
  sol: TFieldSolution;
  gif: TGIFImage;
  bmp: TBitmap;
  frame: TGIFFrame;
  i: Integer;
  a: Double;
  target: TVec3;
  outFile: string;
begin
  if ParamCount >= 1 then outFile := ParamStr(1) else outFile := 'program-field.gif';

  view := TView3DPanel.Create(nil);
  cal := TCalibration.Create(cmModelA);
  gif := TGIFImage.Create;
  try
    cal.SetNominalModel;            // modelo de catálogo: G=diag(k), b=0
    view.BmaxRef := MAG * 1.15;     // escala de la flecha

    for i := 0 to FRAMES - 1 do
    begin
      a := 2 * Pi * i / FRAMES;
      // trayectoria 3D que recorre varias direcciones
      target[0] := MAG * Cos(a);
      target[1] := MAG * 0.55 * Sin(a);
      target[2] := MAG * Sin(2 * a) * 0.8;

      FieldSolveCal(cal, target, sol);
      view.SetView(0.6 + a * 0.15, 0.32, 1.0);
      view.SetTarget(target);

      bmp := TBitmap.Create;
      try
        bmp.SetSize(W, H);
        bmp.PixelFormat := pf24bit;
        view.RenderTo(bmp.Canvas, W, H);
        bmp.Canvas.Brush.Style := bsClear;
        bmp.Canvas.Font.Color := clWhite;
        bmp.Canvas.TextOut(8, 8, 'Programar campo (lazo abierto)');
        bmp.Canvas.Font.Color := clYellow;
        bmp.Canvas.TextOut(8, 28, Format('B = (%4.0f, %4.0f, %4.0f) µT',
          [target[0], target[1], target[2]]));
        bmp.Canvas.Font.Color := TColor($000AA0FF);
        bmp.Canvas.TextOut(8, 46, Format('I = (%5.1f, %5.1f, %5.1f) A',
          [sol.I[0], sol.I[1], sol.I[2]]));
        frame := gif.Add(bmp);
      finally
        bmp.Free;
      end;
      with TGIFGraphicControlExtension.Create(frame) do
      begin
        Delay := 13;
        Disposal := dmBackground;
      end;
    end;
    TGIFAppExtNSLoop.Create(gif.Images.Frames[0]).Loops := 0;
    gif.SaveToFile(outFile);
    WriteLn(Format('GIF guardado: %s (%d fotogramas)', [outFile, FRAMES]));
  finally
    gif.Free;
    cal.Free;
    view.Free;
  end;
end.
