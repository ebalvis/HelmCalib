# HelmCalib

Calibración de campo magnético y **programación en lazo abierto** para bobinas de
Helmholtz de 3 ejes (Bartington **BHC2000**), con vista 3D del vector generado.

La app manda corrientes a las 3 bobinas a través de
[HelmMagControl](../HelmMagControl) (TCP) y mide el campo resultante con el
magnetómetro de un móvil que emite por UDP con
[SensorCast](https://github.com/ebalvis/SensorCast). Con esos datos ajusta el
modelo afín `B = M·I + b` y, una vez calibrado, calcula las corrientes necesarias
para generar un campo objetivo.

> Aplicación de laboratorio. Versión principal en **Lazarus / Free Pascal** (LCL),
> multiplataforma, sin dependencias externas (UI y 3D sobre `Canvas`, red con
> sockets de la RTL, JSON con `fpjson`). Hay también un **port a Delphi (VCL)** en
> [`delphi/`](delphi/) — ver más abajo.

## Características

- **Conexión** en vivo: cliente TCP de HelmMagControl (lecturas `READ ALL`) y
  cliente UDP de SensorCast (magnetómetro + media de K muestras).
- **Calibración** por asistente: barrido automático de corrientes → asentamiento →
  promedio de K muestras → ajuste por mínimos cuadrados. Captura manual de puntos,
  residuo RMS y guardado/carga de perfil (JSON).
- **Programar campo** en lazo abierto: dado un vector B objetivo (marco bobina),
  calcula las corrientes con *clamp* a los límites y avisa de saturación; muestra
  el campo realmente logrado. Modelo nominal de catálogo si aún no se ha calibrado.
- **Vista 3D**: wireframe de los 3 pares de bobinas a escala + flecha del vector B,
  rotable con el ratón y zoom con la rueda, dibujado sobre `Canvas` sin librerías 3D.

## Modelo matemático

Marco del sensor: `B = M·I + b`, con `M` 3×3 (µT/A) y `b` 3×1 (µT, campo ambiente).

- **Ajuste** (mínimos cuadrados, ecuaciones normales):
  `A = [M|b] = (Σ Bₖ·xₖᵀ)·(Σ xₖ·xₖᵀ)⁻¹`, con `xₖ = [Iₖ; 1]`. Requiere ≥ 4 puntos
  no coplanares (incluido I = 0).
- **Descomposición polar** `M = R·G` (Jacobi sobre `MᵀM`): `R` rotación bobina→sensor,
  `G` ganancia simétrica ≈ diag(kₓ, k_y, k_z).
- **Lazo abierto**: `I = G⁻¹·(B_objetivo − Rᵀ·b)`, con *clamp* a ±I_max por eje.

## Arquitectura

| Unit | Responsabilidad |
| --- | --- |
| `uMatrix` | Álgebra 3×3/4×4: inversas, mínimos cuadrados, Jacobi, descomposición polar/SVD. |
| `uCoils`  | Cliente TCP del protocolo de texto de HelmMagControl (lógica de protocolo pura + `TCoilClient`). |
| `uSensor` | Cliente UDP de SensorCast (`ParseSensorJSON` puro + `TSensorClient` en hilo). |
| `uCalib`  | Modelo `B=M·I+b`: puntos, ajuste, polar, residuo RMS, perfil JSON, modelo nominal/manual. |
| `uField`  | Programación de campo en lazo abierto: inversa + *clamp* + campo logrado + envío. |
| `uView3D` | `TView3DPanel`: vista 3D wireframe sobre `Canvas`. |
| `uMainForm` | Formulario principal con las 4 pestañas. |

## Compilar y probar

Requiere **Lazarus / FPC 3.2.2** (en esta máquina, `C:\lazarus`).

```sh
# Aplicación GUI -> lib/x86_64-win64/HelmCalib.exe
bash build.sh

# Tests de consola de la lógica (105+ asserts, exit = nº de fallos)
bash tests/run.sh
```

`build.sh` genera el recurso de proyecto (`HelmCalib.res`, con manifest para temas/DPI)
mediante `fpcres` antes de invocar `lazbuild`. También puedes abrir `HelmCalib.lpi`
directamente en el IDE de Lazarus.

## Port a Delphi (VCL)

En [`delphi/`](delphi/) hay una versión equivalente en **Delphi (VCL, Win64)**,
probada con **RAD Studio Athens (Delphi 37.0)**. Misma arquitectura y las mismas
unidades; cambian solo las dependencias de plataforma:

- Red: **Indy 10** (`TIdTCPClient`, `TIdUDPClient`) en vez de los sockets de la RTL.
- JSON: **System.JSON** en vez de `fpjson`.
- UI/3D: **VCL** (`Vcl.*`) y `.dfm` en vez de LCL/`.lfm`.

```sh
cd delphi
bash build.sh          # GUI -> delphi/HelmCalib.exe (o abre HelmCalib.dproj en el IDE)
bash tests/run.sh      # 115 asserts de la lógica, exit = nº de fallos
```

La lógica está cubierta por los mismos tests de consola (115 asserts) y la GUI/3D
se ha verificado en Win64. La capa de cálculo es idéntica byte a byte en su
comportamiento a la de Lazarus (verificado con los mismos datos sintéticos).

## Hardware de referencia

- **Bobinas:** Bartington BHC2000 (3 pares ortogonales). Modelo A: ~25 µT/A, 1.0 mT/eje,
  40 A. Modelo B: ~15 µT/A, 240 µT/eje, 16 A.
- **Actuador:** fuentes Wanptek vía HelmMagControl, protocolo TCP de texto (puerto 4444).
- **Sensor:** móvil Android con SensorCast en el centro de las bobinas (UDP, JSON cada 200 ms).

## Estado

Las cuatro pestañas (Conexión · Calibración · Programar campo · Vista 3D) están
operativas. La lógica está cubierta por tests de consola con datos sintéticos. El
I/O de red compila y se ha verificado la lógica de protocolo/parseo; la prueba de
extremo a extremo con el hardware real queda para la puesta en marcha.

Ver [CHANGELOG.md](CHANGELOG.md) para el detalle por versión.
