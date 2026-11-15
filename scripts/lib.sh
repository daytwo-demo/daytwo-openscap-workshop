#!/usr/bin/env bash
# Variables y helpers compartidos por los scripts del workshop.
set -euo pipefail

MAJOR=$(rpm -E %{rhel})
DS="/usr/share/xml/scap/ssg/content/ssg-rhel${MAJOR}-ds.xml"
OUT="${OUT:-/tmp/openscap-workshop}"

BASE_PROFILE="xccdf_org.ssgproject.content_profile_cis_server_l1"
TAILORING="$OUT/tailoring.xml"
PROFILE_FILE="$OUT/perfil-tailoring.txt"
RESULT="$OUT/resultado.xml"
REPORT="$OUT/resultado.html"

mkdir -p "$OUT"

need_root() {
    [ "$(id -u)" -eq 0 ] || { echo "corre este script con sudo"; exit 1; }
}

need_ds() {
    [ -f "$DS" ] || { echo "no existe $DS"; echo "instala scap-security-guide (scripts/01-instalar.sh)"; exit 1; }
}

tailor_profile() {
    [ -f "$TAILORING" ] || { echo "no existe $TAILORING (scripts/03-tailoring.sh)"; exit 1; }
    if [ -f "$PROFILE_FILE" ]; then
        cat "$PROFILE_FILE"
        return
    fi
    oscap info "$TAILORING" | sed -n '/Profiles:/,+3p' | grep -o 'xccdf_org[^ ]*' | head -1
}
