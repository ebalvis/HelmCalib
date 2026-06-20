#!/usr/bin/env bash
# Compila y ejecuta los tests de consola de HelmCalib.
# Uso: bash tests/run.sh   (desde la raíz del repo o desde tests/)
set -e

FPC="${FPC:-/c/lazarus/fpc/3.2.2/bin/x86_64-win64/fpc.exe}"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

run_one() {
  local prog="$1"
  echo "=== $prog ==="
  "$FPC" -Fu../src -FE. "$prog.lpr"
  "./$prog.exe"
}

run_one TestMatrix
run_one TestCoils
run_one TestSensor
run_one TestCalib
run_one TestField
