#!/usr/bin/env bash
# Compila la aplicación GUI HelmCalib (Delphi VCL / Win64) con dcc64.
# Genera el recurso de proyecto (manifest: temas + DPI) y enlaza el ejecutable.
# Uso: bash build.sh
set -e

BDS="${BDS:-/c/Program Files (x86)/Embarcadero/Studio/37.0}"
DCC="$BDS/bin/dcc64.exe"
BRCC="$BDS/bin/brcc32.exe"
NS="-NSSystem;Vcl;Vcl.Imaging;Winapi;System.Win;Data;Soap;Xml"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# Recurso de proyecto (manifest). No se versiona (*.res en .gitignore); se regenera.
if [ ! -f HelmCalib.res ] || [ HelmCalib.rc -nt HelmCalib.res ] || [ HelmCalib.manifest -nt HelmCalib.res ]; then
  echo "Generando HelmCalib.res..."
  "$BRCC" -foHelmCalib.res HelmCalib.rc >/dev/null
fi

mkdir -p dcu
"$DCC" -B "$NS" "-Usrc" "-NUdcu" HelmCalib.dpr
echo "OK -> HelmCalib.exe"
