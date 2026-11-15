#!/usr/bin/env bash
# Genera el archivo de ajustes con las excepciones de tailoring/excepciones.tsv.
# El tailoring crea un PERFIL NUEVO: el ID queda en $PROFILE_FILE.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh
need_ds

TSV=tailoring/excepciones.tsv
[ -f "$TSV" ] || { echo "falta $TSV"; exit 1; }

args=()
echo "excepciones:"
while IFS=$'\t' read -r rule motivo; do
    [ -z "${rule:-}" ] && continue
    case "$rule" in \#*) continue ;; esac
    if grep -q "content_rule_${rule}\"" "$DS"; then
        args+=(--unselect "xccdf_org.ssgproject.content_rule_${rule}")
        printf '  + %-58s %s\n' "$rule" "${motivo:-}"
    else
        printf '  ! %-58s no existe en este datastream, se omite\n' "$rule"
    fi
done < "$TSV"

[ ${#args[@]} -gt 0 ] || { echo "no hay excepciones válidas para este datastream"; exit 1; }

autotailor "${args[@]}" -o "$TAILORING" "$DS" "$BASE_PROFILE"

ID=$(oscap info "$TAILORING" | sed -n '/Profiles:/,+3p' | grep -o 'xccdf_org[^ ]*' | head -1)
echo "$ID" > "$PROFILE_FILE"
echo
echo "ajuste:  $TAILORING"
echo "perfil:  $ID"
