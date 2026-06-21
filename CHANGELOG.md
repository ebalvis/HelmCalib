# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/).

## [Unreleased]

### Cambiado

- **Vista 3D** (`uView3D`, ambas versiones): ahora dibuja **bobinas cuadradas** de
  cobre (2 por eje) dentro de una **estructura cúbica de soporte** de aluminio, para
  parecerse al hardware real (Bartington BHC2000), en vez de los anillos circulares.

### Añadido

- **Port a Delphi (VCL / Win64)** en `delphi/`, probado con RAD Studio Athens
  (Delphi 37.0). Misma arquitectura y unidades; dependencias de plataforma
  adaptadas: red con **Indy 10** (`TIdTCPClient`/`TIdUDPClient`), JSON con
  **System.JSON**, UI/3D en **VCL** con `.dfm`. Lógica verificada con los mismos
  115 asserts de consola; GUI y vista 3D verificadas en Win64. Scripts `build.sh`
  y `tests/run.sh`, proyecto `HelmCalib.dproj` para el IDE.

## [0.1.0] - 2026-06-21

Primera versión funcional en Lazarus/FPC. Las cuatro pestañas operativas y la
lógica cubierta por tests de consola con datos sintéticos.

### Añadido

- **`uMatrix`** — álgebra 3×3/4×4 sin dependencias: vectores, inversa 3×3
  (cofactores) y 4×4 (Gauss-Jordan con pivoteo), mínimos cuadrados afín
  (`SolveAffine`), eigendescomposición simétrica (`JacobiEig3`), descomposición
  polar (`PolarDecomp`) y SVD. 25 tests.
- **`uCoils`** — cliente TCP del protocolo de HelmMagControl: lógica de protocolo
  pura (formato de comandos, parseo de `OK`/`ERROR`, `GET`, `READ ALL`) y
  `TCoilClient` sobre sockets (conexión persistente, CRLF/LF, timeout). 21 tests.
- **`uSensor`** — cliente UDP de SensorCast: `ParseSensorJSON` (magnetómetro
  obligatorio, acelerómetro opcional) y `TSensorClient` en hilo (envía `HOLA`,
  última muestra + media de K, mutex). 14 tests.
- **`uCalib`** — modelo `B=M·I+b`: acumulación de puntos, ajuste, descomposición
  polar, residuo RMS, perfil JSON (guardar/cargar) y modelo nominal/manual. 38 tests.
- **`uField`** — programación de campo en lazo abierto: inversa `I=G⁻¹·(B−Rᵀ·b)`,
  *clamp* por eje con avisos de saturación, campo logrado y envío a las fuentes. 17 tests.
- **`uView3D`** — `TView3DPanel`: vista 3D wireframe de las bobinas + flecha del
  vector B sobre `Canvas`, rotación con ratón y zoom; render offline a PNG.
- **GUI** (`uMainForm`, proyecto Lazarus): pestañas Conexión, Calibración,
  Programar campo y Vista 3D.
  - Conexión: TCP a HelmMagControl (Ping, `READ ALL` en vivo) y UDP a SensorCast.
  - Calibración: asistente de barrido automático, captura manual, lista de puntos,
    ajuste y guardado de perfil.
  - Programar campo: objetivo B → corrientes/clamp/campo logrado, envío a fuentes.
  - Vista 3D del vector objetivo.
- **Build/tests**: `build.sh` (genera `.res` con manifest y compila con `lazbuild`)
  y `tests/run.sh` (compila y ejecuta los programas de test de consola).

[0.1.0]: https://github.com/ebalvis/HelmCalib/releases/tag/v0.1.0
