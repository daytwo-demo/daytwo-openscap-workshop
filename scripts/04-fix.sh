#!/usr/bin/env bash
# Genera el fix con el PERFIL DEL TAILORING y lo aplica tras confirmación.
# Corre esto desde la consola de la VM, no por SSH.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh
need_root
need_ds

PROFILE=$(tailor_profile)
FIX="$OUT/fix.sh"

echo "generando fix para: $PROFILE"
oscap xccdf generate fix \
    --fix-type bash \
    --profile "$PROFILE" \
    --tailoring-file "$TAILORING" \
    -o "$FIX" "$DS"

echo "generado: $FIX ($(wc -l < "$FIX") líneas)"
echo
echo "ADVERTENCIA: esto modifica sshd, PAM y sudo."
echo "Tené la consola de la VM abierta y el snapshot hecho."
read -r -p "escribe SI para aplicar: " r
[ "$r" = "SI" ] || { echo "no se aplicó"; exit 0; }

bash "$FIX"
echo
echo "listo. puede hacer falta reiniciar para módulos y parámetros de kernel."
