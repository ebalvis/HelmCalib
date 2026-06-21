# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Changed

- **3D view** (`uView3D`, both versions): now draws **square coils** (thick, copper,
  2 per axis) inside a **cubic support structure** (faint gray aluminium) to resemble
  the real hardware (Bartington BHC2000), instead of circular rings. When programming
  a field, the coils of the axes that dominate the target vector are **highlighted in
  orange**.

### Added

- **MIT license** (`LICENSE`) and an animated 3D preview + per-tab screenshots in the README.
- **Delphi (VCL / Win64) port** in `delphi/`, tested with RAD Studio Athens
  (Delphi 37.0). Same architecture and units; platform dependencies adapted:
  networking with **Indy 10** (`TIdTCPClient`/`TIdUDPClient`), JSON with
  **System.JSON**, UI/3D in **VCL** with `.dfm`. Logic verified with the same
  115 console assertions; GUI and 3D view verified on Win64. `build.sh` and
  `tests/run.sh` scripts, and a `HelmCalib.dproj` project for the IDE.

## [0.1.0] - 2026-06-21

First working version in Lazarus/FPC. All four tabs operational and the logic
covered by console tests with synthetic data.

### Added

- **`uMatrix`** — dependency-free 3×3/4×4 linear algebra: vectors, 3×3 inverse
  (cofactors) and 4×4 inverse (Gauss-Jordan with pivoting), affine least squares
  (`SolveAffine`), symmetric eigendecomposition (`JacobiEig3`), polar decomposition
  (`PolarDecomp`) and SVD. 25 tests.
- **`uCoils`** — TCP client for the HelmMagControl protocol: pure protocol logic
  (command formatting, `OK`/`ERROR` parsing, `GET`, `READ ALL`) and a socket-based
  `TCoilClient` (persistent connection, CRLF/LF, timeout). 21 tests.
- **`uSensor`** — UDP client for SensorCast: `ParseSensorJSON` (magnetometer
  required, accelerometer optional) and a threaded `TSensorClient` (sends `HOLA`,
  keeps the latest sample + K-average, mutex). 14 tests.
- **`uCalib`** — `B=M·I+b` model: point accumulation, fit, polar decomposition,
  RMS residual, JSON profile (save/load), and nominal/manual model. 38 tests.
- **`uField`** — open-loop field programming: inverse `I=G⁻¹·(B−Rᵀ·b)`, per-axis
  clamping with saturation warnings, achieved field, and sending to the supplies. 17 tests.
- **`uView3D`** — `TView3DPanel`: wireframe 3D view of the coils + B-vector arrow
  on `Canvas`, mouse rotation and zoom; offline PNG rendering.
- **GUI** (`uMainForm`, Lazarus project): Connection, Calibration, Program field,
  and 3D view tabs.
  - Connection: TCP to HelmMagControl (Ping, live `READ ALL`) and UDP to SensorCast.
  - Calibration: automatic sweep wizard, manual capture, point list, fit, and profile save.
  - Program field: target B → currents/clamp/achieved field, send to supplies.
  - 3D view of the target vector.
- **Build/tests**: `build.sh` (generates the `.res` with a manifest and compiles with
  `lazbuild`) and `tests/run.sh` (compiles and runs the console test programs).

[Unreleased]: https://github.com/ebalvis/HelmCalib/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ebalvis/HelmCalib/releases/tag/v0.1.0
