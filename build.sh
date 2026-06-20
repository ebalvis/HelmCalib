#!/usr/bin/env bash
# Compila la aplicación GUI HelmCalib.
# Genera el recurso de proyecto (manifest, themes/DPI) y llama a lazbuild.
# Uso: bash build.sh
set -e

BIN="${FPCBIN:-/c/lazarus/fpc/3.2.2/bin/x86_64-win64}"
LAZBUILD="${LAZBUILD:-/c/lazarus/lazbuild.exe}"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# El .res del proyecto (manifest) no se versiona (*.res está en .gitignore).
# Se regenera desde HelmCalib.rc -> HelmCalib.manifest con fpcres.
if [ ! -f HelmCalib.res ] || [ HelmCalib.rc -nt HelmCalib.res ] || [ HelmCalib.manifest -nt HelmCalib.res ]; then
  echo "Generando HelmCalib.res..."
  "$BIN/fpcres.exe" -of res -o HelmCalib.res HelmCalib.rc
fi

"$LAZBUILD" HelmCalib.lpi
echo "OK -> lib/x86_64-win64/HelmCalib.exe"
