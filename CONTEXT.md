# CONTEXT.md — HelmCalib

Última actualización: 2026-06-20

Calibración de N puntos y **programación de campo magnético en lazo abierto**
para las bobinas de Helmholtz de 3 ejes (Bartington BHC2000), más una vista 3D
del vector generado. Proyecto **nuevo** (aún sin código); este documento es el
diseño aprobado para empezar a implementar.

## Objetivo

1. **Calibrar** N puntos: mandar corrientes a las 3 bobinas y medir el campo B
   resultante con un magnetómetro, para ajustar el modelo `B = M·I + b`.
2. **Programar campo en lazo abierto** (sin realimentación del magnetómetro): el
   usuario pide un vector B (módulo + dirección) y la app calcula las corrientes
   con el modelo calibrado y las manda a las fuentes.
3. **Vista 3D** de los 3 pares de bobinas y del vector B que se va a generar.

## Stack

- **Lenguaje/IDE:** Lazarus / Free Pascal (LCL), multiplataforma (Windows/Linux/macOS).
- Build: `lazbuild HelmCalib.lpi` (FPC 3.2.2 en `C:\lazarus` en esta máquina).
- Sin dependencias externas (UI y 3D sobre `Canvas`; red con `ssockets`/sockets de FPC).
- App **independiente**, hermana de `HelmMagControl` (no se integra dentro).

## Decisiones tomadas

- **App nueva en Lazarus**, desacoplada: habla con las bobinas por el **protocolo
  TCP de HelmMagControl** y con el móvil por **UDP de SensorCast**.
- **Modelo de calibración: afín 3×3 + offset** `B = M·I + b` (M capta ganancia por
  eje + acoplo cruzado + rotación sensor↔bobina; b = campo ambiente/Tierra).
- **Marco de referencia del campo objetivo: el de las bobinas (X/Y/Z)**. La
  rotación sensor↔bobina se recupera de la calibración (descomposición polar de M),
  así el móvil puede estar en cualquier orientación.
- **Calibración por asistente automático** (barrido de combinaciones de corriente),
  con opción de añadir/rehacer puntos a mano.
- **Vista 3D: wireframe propio sobre Canvas** (rotable con ratón), sin librerías 3D.

## Hardware de referencia

### Bobinas — Bartington BHC2000 (datasheet: `../HelmMagControl/Documentation/DS4755.pdf`)
- 3 pares de bobinas ortogonales (X/Y/Z). Cada eje genera campo homogéneo en su dirección.
- **Relación campo/corriente (≈ k por eje), lineal:**
  - Modelo A: X 24.8, Y 25.3, Z 25.1 µT/A (devanados en paralelo). Campo máx **1.0 mT/eje**, corriente máx **40 A** (o 20 A por circuito).
  - Modelo B: X 14.4, Y 14.7, Z 15.1 µT/A. Campo máx **240 µT/eje**, corriente máx **16 A** (u 8 A por circuito).
- Acoplo cruzado pequeño (campo secundario ~0.82 µT/A). Volumen homogéneo cúbico ~48 cm (±1%).
- Diámetros nominales: **X 2046 mm, Y 2000 mm, Z 1954 mm** (para la vista 3D, a escala).

### Actuador — fuentes Wanptek vía HelmMagControl (protocolo TCP de texto)
Cliente TCP a `HelmMagControl` (por defecto puerto **4444**). Comandos (una línea, respuesta `OK …`/`ERROR …`), canales **1..3** = ejes X/Y/Z:
- `PING` → `OK PONG`
- `SET I<n> <amp>` / `SET V<n> <volt>` (separador decimal **punto**)
- `OUT <n> ON|OFF`, `ALL OFF`
- `GET I<n>` / `GET V<n>` / `GET P<n>`, `STATUS <n>`
- `READ ALL` → `OK CH1 V=.. I=.. OUT=.. | CH2 … | CH3 …`

> Nota: las fuentes son de tensión/corriente; para fijar **corriente** por eje se
> usa `SET I<n>` con la salida en modo de limitación de corriente (CC). Revisar en
> la puesta en marcha que el lazo de corriente de la Wanptek responde como se espera.

### Sensor — SensorCast (app Android B4A, repo: github.com/ebalvis/SensorCast)
- El móvil (en el **centro** de las bobinas) emite el magnetómetro 3 ejes.
- Protocolo UDP: el cliente envía el texto **`HOLA`** a `IP_móvil:51042`; el móvil
  registra al cliente y le envía cada **200 ms** a `:51043` un JSON:
  ```json
  { "accelerometer": {"x":.., "y":.., "z":..}, "magnetometer": {"x":.., "y":.., "z":..} }
  ```
- Usamos `magnetometer` (µT). El acelerómetro puede servir para detectar/registrar
  la orientación del móvil (opcional).

## Arquitectura (units planificadas)

- **`uCoils`** — cliente TCP del protocolo HelmMagControl (conectar, `SET I`, `OUT`,
  `READ ALL`, `ALL OFF`). Aísla el actuador tras una interfaz simple.
- **`uSensor`** — cliente UDP de SensorCast: hilo que envía `HOLA`, recibe y parsea
  el JSON, mantiene la última lectura y permite **promediar K muestras** (para reducir ruido).
- **`uCalib`** — modelo `B = M·I + b`:
  - Acumula puntos `(I_k, B_k)`.
  - Ajuste por **mínimos cuadrados** (ver Matemática).
  - **Descomposición polar** `M = R·G` (R rotación coil→sensor, G ganancia simétrica).
  - Inversa para lazo abierto. Calidad del ajuste (residuos RMS).
  - Guardar/cargar **perfil** (JSON: M, b, modelo de bobina, fecha, residuos).
- **`uField`** — programar campo: dado `B_coil_target` (µT, dirección en marco bobina)
  → `I = G⁻¹·(B_coil_target − R^T·b)` → *clamp* a límites de corriente → manda por `uCoils`.
- **`uView3D`** — wireframe de los 3 pares de bobinas a escala + flecha del vector B
  (objetivo y, opcional, medido); proyección perspectiva propia, rotación con ratón.
- **`uMatrix`** — utilidades de álgebra 3×3/4×4: producto, inversa, normal equations
  o SVD/Jacobi (para mínimos cuadrados y descomposición polar). Sin dependencias.
- **`uMainForm`** — pestañas: **Conexión · Calibración · Programar campo · Vista 3D**.
- (Opcional) **`uLang`** — i18n ES/EN reusando el patrón de HelmMagControl.

## Matemática de calibración

Modelo (marco del sensor): `B_s = M·I + b`, con `M` 3×3 (µT/A), `b` 3×1 (µT,
ambiente + bias del sensor).

**Ajuste (mínimos cuadrados):** incógnita `A = [M | b]` (3×4); regresor `x_k = [I_k; 1]` (4×1);
`B_k = A·x_k`. Solución normal: `A = (Σ B_k·x_kᵀ)·(Σ x_k·x_kᵀ)⁻¹`.
Requiere `Σ x_k·x_kᵀ` (4×4) invertible → **N ≥ 4 puntos I no coplanares** (incluido
I=0 para `b`). Recomendado ~13: `0`, `±I0` en cada eje (6) y varias combinaciones
(p.ej. XY, XZ, YZ, XYZ). Mejor con **2 amplitudes** para verificar linealidad.

**Marco bobina (descomposición polar):** SVD `M = U·Σ·Vᵀ` → `R = U·Vᵀ` (rotación
coil→sensor), `G = V·Σ·Vᵀ` (ganancia simétrica, ≈ diag(k_x,k_y,k_z)).

**Lazo abierto (programar campo neto en el centro):**
`I = G⁻¹·(B_coil_target − b_coil)`, con `b_coil = Rᵀ·b`. Luego *clamp* por eje a
`±I_max` (40 A/16 A según modelo) y aviso si se satura (el campo logrado diferirá).

**Verificar (opcional, una lectura):** medir `B_s`, comparar con el objetivo en
marco sensor `R·B_coil_target` y mostrar el error (módulo y ángulo).

## Vista 3D

- 3 pares de bobinas (anillos/cuadrados) en los planos ⟂ a X/Y/Z, a escala de sus
  diámetros (2046/2000/1954 mm), en wireframe.
- Flecha del **vector B objetivo** desde el centro (y opcional el medido), color/escala
  por módulo. Rotación de la escena con arrastre del ratón; proyección perspectiva simple.
- Todo dibujado en `Canvas` (`TPaintBox`), sin dependencias.

## Persistencia y errores

- **Perfil de calibración** en JSON: `M`, `b`, modelo de bobina (A/B, límites), fecha,
  residuo RMS y nº de puntos. Cargar/guardar; avisar si el perfil no corresponde al
  modelo de bobina seleccionado.
- Manejo de errores: timeout de UDP (móvil sin enviar → aviso, no bloquear UI),
  TCP caído, `M` casi singular (puntos colineales/insuficientes → avisar), corriente
  fuera de rango (*clamp* + aviso), JSON malformado (ignorar paquete).

## Estado actual

- ✅ **`uMatrix`** (`src/uMatrix.pas`) — álgebra 3×3/4×4 sin dependencias:
  vectores, inversa 3×3 (cofactores) y 4×4 (Gauss-Jordan c/ pivoteo), mínimos
  cuadrados afín `SolveAffine` (ecuaciones normales), `JacobiEig3` (eigen simétrica),
  `PolarDecomp` (M=R·G) y `SVD3`. **25/25 tests OK** (`tests/TestMatrix.lpr`,
  datos sintéticos con M/b/R/G conocidos).
- ✅ **`uCoils`** (`src/uCoils.pas`) — cliente TCP HelmMagControl. Lógica de protocolo
  pura/testeable (`CoilFmtSetI/SetV/Out`, `CoilRespOK`, `CoilParseValue`,
  `CoilParseReadAll`) + `TCoilClient` (ssockets, conexión persistente, CRLF al enviar /
  lee hasta LF, `Ping/SetCurrent/SetVoltage/Output/AllOff/ReadAll`). **21/21 tests OK**.
  Protocolo verificado contra `../HelmMagControl/Source/uTcpServerController.pas`.
- ✅ **`uSensor`** (`src/uSensor.pas`) — cliente UDP SensorCast. `ParseSensorJSON` puro
  (fpjson, magnetómetro obligatorio, acelerómetro opcional) + `TSensorClient` (TThread:
  envía `HOLA`, recibe en :51043 con timeout, última muestra + media de K, mutex). **14/14 tests OK**.
- ✅ **`uCalib`** (`src/uCalib.pas`) — modelo `B=M·I+b`. `TCalibration`: acumula puntos
  (`AddPoint/RemovePoint/ClearPoints`), `Fit` (≥4 pts → `SolveAffine` + `PolarDecomp` →
  M, b, R, G, Ginv, residuo RMS en µT), `Predict`, perfil JSON (`SaveToJSON/LoadFromJSON`,
  `SaveToFile/LoadFromFile`; al cargar recomputa R/G/Ginv). Modelos de bobina A/B con
  límites I/B (`CoilModelInfo`). **29/29 tests OK** (round-trip JSON y fichero incluidos).
- 🔧 Siguiente: `uField` (inversa lazo abierto `I=Ginv·(B_coil − Rᵀ·b)` + clamp + envío por uCoils).
- ✅ Diseño aprobado (este CONTEXT.md).

### Build / tests
- Tests de consola: `bash tests/run.sh` (compila con FPC y ejecuta los 4, exit=nº fallos). 89 asserts.
- ⚠️ `TCoilClient`/`TSensorClient`: I/O de red **no** testeado sin hardware (HelmMagControl/móvil);
  solo compila y se verifica la lógica pura. Probar en puesta en marcha.
- FPC en esta máquina: `C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe`; `lazbuild` en `C:\lazarus\`.
- ⚠️ Pascal es **case-insensitive**: cuidado con params tipo `B`/`b`, `S`/`s`, `A`/`a`.

## Archivos clave (planificados)

- `HelmCalib.lpr` / `HelmCalib.lpi` — programa y proyecto Lazarus.
- `src/uCoils.pas`, `src/uSensor.pas`, `src/uCalib.pas`, `src/uField.pas`,
  `src/uView3D.pas`, `src/uMatrix.pas`, `src/uMainForm.pas`.
- `CONTEXT.md` (este archivo).

## Mis preferencias (aprendidas — Eduardo)

- Responder en **español**, directo y técnico, código funcional sobre explicaciones largas.
- Lazarus: widgets propios sobre `Canvas` cuando no hay equivalente; aislar lo
  dependiente de plataforma tras interfaces (como `ISerialTransport` en HelmMagControl).
- Commits en español; **no** añadir `Co-Authored-By: Claude` (lo rechazó).
- Verificar compilando (`lazbuild`) y, cuando aplique, ejecutando.
- En esta máquina, traer la ventana al frente para capturas cuesta (foco): usar
  `AttachThreadInput` / `SetWindowPos TOPMOST` vía P/Invoke desde PowerShell.

## Próximos pasos (orden de implementación sugerido)

1. **`uMatrix`** + tests: inversa 3×3/4×4, mínimos cuadrados (normal equations),
   SVD/Jacobi para descomposición polar. Verificar con datos sintéticos (M,b conocidos).
2. **`uCoils`** (cliente TCP) y **`uSensor`** (cliente UDP) — probar contra
   HelmMagControl y un móvil con SensorCast (o un emulador de ambos).
3. **`uCalib`** — acumular puntos, ajustar, descomposición polar, guardar/cargar perfil.
4. **`uField`** — inversa + clamp + envío.
5. **`uMainForm`** — pestañas y asistente de calibración (barrido + asentamiento + promedio).
6. **`uView3D`** — wireframe + vector.
7. (Opcional) i18n ES/EN, verificación de campo, registro de orientación con el acelerómetro.

## Referencias

- Datasheet bobinas: `../HelmMagControl/Documentation/DS4755.pdf` (BHC2000).
- Protocolo TCP actuador: `../HelmMagControl/README.md` y `Source/uTcpServerController.pas`
  (o `lazarus/app/umainform.pas` → `ParseCmd`).
- SensorCast (UDP/JSON): github.com/ebalvis/SensorCast (README).
