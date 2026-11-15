#!/usr/bin/env bash
# Verifica versión, paquetes y datastream antes de empezar.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

echo "RHEL:        $(. /etc/os-release; echo "$PRETTY_NAME")"
echo "datastream:  $DS"
[ -f "$DS" ] && echo "  ok" || echo "  FALTA: instala scap-security-guide"

for p in openscap-scanner openscap-utils scap-security-guide; do
    printf '%-24s %s\n' "$p" "$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "$p" 2>/dev/null || echo 'NO INSTALADO')"
done

echo
echo "perfiles CIS disponibles:"
[ -f "$DS" ] && oscap info "$DS" | grep -o 'xccdf_org.ssgproject.content_profile_cis[a-z0-9_-]*' | sort -u || true

echo
echo "salida del workshop: $OUT"
