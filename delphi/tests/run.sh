#!/usr/bin/env bash
# Compila y ejecuta los tests de consola de HelmCalib (Delphi / Win64).
# Uso: bash tests/run.sh   (desde delphi/ o desde delphi/tests/)
set -e

BDS="${BDS:-/c/Program Files (x86)/Embarcadero/Studio/37.0}"
DCC="$BDS/bin/dcc64.exe"
NS="-NSSystem;Vcl;Vcl.Imaging;Winapi;System.Win;Data;Soap;Xml"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

run_one() {
  local prog="$1"
  echo "=== $prog ==="
  "$DCC" -B "$NS" "-U../src" "-E." "-NUdcu" "$prog.dpr" >/dev/null
  "./$prog.exe"
}

run_one TestMatrix
run_one TestCoils
run_one TestSensor
run_one TestCalib
run_one TestField
