#!/usr/bin/env bash
# Escaneo final con el perfil del tailoring. Cuenta y muestra fallas.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh
need_root
need_ds

PROFILE=$(tailor_profile)
echo "perfil: $PROFILE"

oscap xccdf eval \
    --profile "$PROFILE" \
    --tailoring-file "$TAILORING" \
    --results "$RESULT" \
    --report "$REPORT" \
    "$DS" || true

echo
echo "resumen:"
grep -o 'result>[a-z]*<' "$RESULT" | sort | uniq -c

echo
echo "fallas:"
python3 - "$RESULT" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = '{http://checklists.nist.gov/xccdf/1.2}'
n = 0
for r in ET.parse(sys.argv[1]).getroot().iter(ns + 'rule-result'):
    e = r.find(ns + 'result')
    if e is not None and e.text == 'fail':
        n += 1
        print('  -', r.get('idref', '').replace('xccdf_org.ssgproject.content_rule_', ''))
print('  (ninguna)' if n == 0 else '')
PY

echo
echo "estado de las excepciones:"
python3 - "$RESULT" tailoring/excepciones.tsv <<'PY'
import sys, xml.etree.ElementTree as ET
ns = '{http://checklists.nist.gov/xccdf/1.2}'
estado = {}
for r in ET.parse(sys.argv[1]).getroot().iter(ns + 'rule-result'):
    e = r.find(ns + 'result')
    estado[(r.get('idref') or '').split('content_rule_')[-1]] = e.text if e is not None else '?'
for line in open(sys.argv[2]):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    rule = line.split('\t')[0]
    print(f"  {rule:58} -> {estado.get(rule, 'no aparece')}")
PY

echo
echo "reporte: $REPORT"
