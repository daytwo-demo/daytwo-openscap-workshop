#!/usr/bin/env bash
# Escaneo base: CIS nivel 1 servidor, sin ajustes.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh
need_root
need_ds

echo "escaneando con el perfil base..."
oscap xccdf eval \
    --profile "$BASE_PROFILE" \
    --results "$OUT/base.xml" \
    --report "$OUT/base.html" \
    "$DS" || true

echo
echo "resumen:"
grep -o 'result>[a-z]*<' "$OUT/base.xml" | sort | uniq -c

echo
echo "reglas que fallan:"
python3 - "$OUT/base.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = '{http://checklists.nist.gov/xccdf/1.2}'
for r in ET.parse(sys.argv[1]).getroot().iter(ns + 'rule-result'):
    e = r.find(ns + 'result')
    if e is not None and e.text == 'fail':
        print('  -', r.get('idref', '').replace('xccdf_org.ssgproject.content_rule_', ''))
PY

echo
echo "reporte: $OUT/base.html"
