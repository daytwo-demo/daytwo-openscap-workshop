# OpenSCAP Workshop — RHEL 9 y RHEL 10

Workshop práctico para entender cómo se **mide** y se **ajusta** una línea base
CIS con las herramientas que ya vienen en RHEL. Sin Satellite, sin fork y sin
escribir XML a mano.

Al terminar vas a haber hecho, de punta a punta:

1. escaneado un RHEL contra CIS nivel 1 servidor,
2. leído el reporte y entendido qué significa cada resultado,
3. generado un archivo de ajustes que **quita** los controles que no aplican,
4. remediado el sistema,
5. verificado con un reporte en cero fallas y las excepciones declaradas.

---

## Antes de empezar

- **VM desechable.** El paso de remediación toca `sshd`, PAM y `sudo`.
- **Snapshot tomado.** Si algo sale mal, se revierte en un minuto.
- **Consola de la VM, no SSH.** Si la configuración de acceso se rompe, la
  consola te deja entrar igual.
- **Nada de esto va a producción** sin revisar las excepciones con el equipo.

Requisitos:

- RHEL 9.x o 10.x.
- Los paquetes `openscap-scanner`, `openscap-utils` y `scap-security-guide`.
- 2 GB libres en `/tmp` (los reportes pesan).

Si la VM no tiene internet, el ISO de instalación alcanza: ver
`scripts/01-instalar.sh`, que soporta las dos vías.

---

## Conceptos en cinco minutos

Cinco piezas, y cada una hace una sola cosa:

| Pieza | Qué es | Quién lo produce |
|---|---|---|
| **Datastream** | un archivo XML con todo el contenido: reglas, perfiles y chequeos | el paquete `scap-security-guide` |
| **Perfil** | una lista: qué reglas entran y con qué valores | el mismo datastream |
| **Regla** | una verificación concreta ("root no entra por SSH") | el contenido |
| **Chequeo** | el código que mide esa regla (OVAL) | el contenido |
| **Tailoring** | un archivo aparte con un perfil derivado: "CIS, pero sin estas reglas" | vos, con `autotailor` |

Y la frase que ordena todo:

> **El perfil elige. La regla define. El chequeo mide. El fix escribe.**

El datastream **no se edita**. El tailoring **no modifica** el datastream: crea
un perfil hijo que lo referencia.

---

## Parte 1 — Happy path

Instalar y ver qué hay:

```bash
sudo dnf install -y openscap-scanner openscap-utils scap-security-guide

# el datastream de tu versión
DS=/usr/share/xml/scap/ssg/content/ssg-rhel$(rpm -E %{rhel})-ds.xml
echo $DS

# perfiles disponibles
oscap info "$DS" | sed -n '/Profiles:/,/^$/p'
```

Los perfiles CIS que nos importan:

| Perfil | Qué es |
|---|---|
| `cis_server_l1` | CIS nivel 1 servidor |
| `cis` | CIS nivel 2 servidor (ojo: en RHEL 9 y 10 **no** se llama `cis_server_l2`) |
| `cis_workstation_l1` | CIS nivel 1 escritorio |

Escaneo base:

```bash
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --results /tmp/base.xml --report /tmp/base.html \
  "$DS"
```

Abre `/tmp/base.html` en el navegador de la VM. Ese es el punto de partida.

> En una RHEL 10.3 recién instalada, el orden de magnitud es: ~284 pass,
> ~9 fail, ~31 no aplica, ~750 fuera del perfil. Los números cambian según
> versión y perfil; lo que importa es el método.

---

## Parte 2 — Leer el reporte

Cada regla termina en uno de cuatro estados:

| Estado | Significa | Qué hacer |
|---|---|---|
| `pass` | cumple | nada |
| `fail` | no cumple | remediar o excluir con motivo |
| `notapplicable` | no aplica al sistema (GDM en un server, wireless) | nada |
| `notselected` | no está en el perfil, o la excluiste | nada |

Conteo rápido, sin abrir el HTML:

```bash
grep -o 'result>[a-z]*<' /tmp/base.xml | sort | uniq -c
```

Y la lista de lo que falla:

```bash
python3 - <<'PY'
import xml.etree.ElementTree as ET
ns='{http://checklists.nist.gov/xccdf/1.2}'
for r in ET.parse('/tmp/base.xml').getroot().iter(ns+'rule-result'):
    e=r.find(ns+'result')
    if e is not None and e.text=='fail':
        print(r.get('idref').replace('xccdf_org.ssgproject.content_rule_',''))
PY
```

---

## Parte 3 — Tailoring: quitar lo que no aplica

Un `fail` tiene tres salidas posibles:

1. **Se arregla** (el fix lo hace).
2. **Se decide** (política: quién entra por SSH, journald o rsyslog).
3. **No aplica** (no hay partición separada, no hay colector de logs).

Las 2 y 3 se resuelven con un **archivo de ajustes**: un perfil derivado que
declara esas reglas fuera de alcance. No se edita el datastream, no se toca CIS.

### Generarlo

Las reglas están en `tailoring/excepciones.tsv`, una por línea con su motivo.
El script las valida contra tu datastream (por si alguna no existe en tu
versión) y genera el archivo:

```bash
sudo ./scripts/03-tailoring.sh
```

Por dentro hace esto:

```bash
autotailor \
  --unselect xccdf_org.ssgproject.content_rule_partition_for_tmp \
  --unselect xccdf_org.ssgproject.content_rule_grub2_password \
  -o /tmp/openscap-workshop/tailoring.xml \
  "$DS" xccdf_org.ssgproject.content_profile_cis_server_l1
```

### El detalle que rompe todo

El tailoring **crea un perfil nuevo**. Si escaneás con el perfil base y le
pasás el archivo, el ajuste **no se aplica**:

```bash
# MAL: perfil base + tailoring
oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --tailoring-file /tmp/openscap-workshop/tailoring.xml "$DS"

# BIEN: el perfil que define el tailoring
oscap info /tmp/openscap-workshop/tailoring.xml | sed -n '/Profiles:/,+3p'
oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1_customized \
  --tailoring-file /tmp/openscap-workshop/tailoring.xml "$DS"
```

`scripts/03-tailoring.sh` extrae el ID solo y lo deja en
`/tmp/openscap-workshop/perfil-tailoring.txt` para que no haya que copiarlo.

---

## Parte 4 — Remediar

Dos comandos distintos que se confunden todo el tiempo:

| Comando | Qué hace |
|---|---|
| `oscap xccdf generate fix` | **solo escribe un archivo**. No aplica nada |
| `ansible-playbook fix.yml` o `bash fix.sh` | **aplica** los cambios |

El script genera el fix **con el perfil del tailoring** (si usás el perfil base,
aplicás la política base):

```bash
sudo ./scripts/04-fix.sh
```

Genera `/tmp/openscap-workshop/fix.sh` y te pide confirmación antes de correrlo.
Corrélo desde la consola de la VM.

Si preferís Ansible, `generate fix --fix-type ansible` produce un playbook, pero
`ansible-core` no trae las colecciones que usa (`community.general`,
`ansible.posix`). Para el workshop, bash es suficiente; en producción se
instalan las colecciones o se usa el paquete `rhc-worker-playbook`.

Después de aplicar, puede hacer falta un reinicio para lo que depende del
arranque (módulos de kernel, parámetros de kernel).

---

## Parte 5 — Verificar

```bash
sudo ./scripts/05-verificar.sh
```

Vas a ver algo así:

```
pass:           284
fail:             0
notapplicable:   31
notselected:    758
```

Cero fallas **no significa que todo esté configurado**: significa que todo lo
que el perfil mide está en verde, y que las excepciones están declaradas. La
lista de excepciones con su motivo es la evidencia.

---

## Las excepciones del ejemplo

Estas son las que aparecieron en una RHEL 10.3 limpia. Cada una tiene un motivo
distinto: no son "reglas difíciles", son **decisiones**.

| Regla | Por qué no se arregla sola | Qué hacer |
|---|---|---|
| `partition_for_tmp` | `/tmp` separado se define al instalar | excepción, o reinstalar con partición |
| `grub2_password` | poner password de GRUB puede dejarte afuera | decisión + procedimiento |
| `sshd_limit_user_access` | falta decidir **quién** entra (`AllowGroups`) | definir grupo y aplicar con cuidado |
| `ensure_journald_and_rsyslog_not_active_together` | elegir journald **o** rsyslog | decisión de arquitectura |
| `service_systemd-journal-upload_enabled` | no hay colector remoto de logs | no aplica sin esa infraestructura |
| `ensure_root_password_configured` | root bloqueado + sudo es válido | decisión de política |
| `no_files_or_dirs_ungroupowned` | hay archivos sin grupo | revisar y asignar a mano |
| `no_files_or_dirs_unowned_by_user` | hay archivos sin dueño | revisar y asignar a mano |
| `accounts_password_last_change_is_in_past` | las cuentas son nuevas | `chage -d` o excepción |

En tu organización la lista va a ser distinta. Lo importante es que **cada
excepción tenga motivo, dueño y fecha de revisión**.

---

## Errores comunes

| Síntoma | Causa | Solución |
|---|---|---|
| "Apliqué el fix y sigue fallando" | solo corriste `generate fix` | ejecutar el archivo generado |
| El tailoring no cambia nada | escaneaste con el perfil base | usar el ID del perfil del tailoring |
| `couldn't resolve module community.general.ini_file` | `ansible-core` sin colecciones | usar `--fix-type bash` o instalar colecciones |
| `partition_for_tmp` sigue en rojo | no se puede crear una partición en caliente | excepción |
| Todo sigue en rojo tras el fix | el playbook se salteó tareas (`when`) | revisar el recap (`skipped`/`failed`) |
| SCAP Workbench no existe | proyecto discontinuado (2024) | `autotailor` o `cockpit-scap` |
| Reglas SCE sin resultado | falta `openscap-engine-sce` en el host | instalar el motor |

---

## Lo que no hace falta

- **Fork de ComplianceAsCode**: solo si vas a **agregar reglas que no existen**.
  Para quitar reglas y cambiar valores, el tailoring alcanza.
- **SCAP Workbench**: está discontinuado. `autotailor` hace lo mismo por línea
  de comandos.
- **Escribir OVAL**: no se escribe a mano. Se usa una regla existente o una
  plantilla del contenido.
- **SCE**: es una extensión no estándar para scripts. Solo si OVAL no puede
  medir lo que necesitás, y con el motor instalado en cada host.

---

## Qué sigue

Este workshop se queda en **quitar** controles. Las siguientes etapas:

1. **Cambiar valores** (por ejemplo longitud de password a 24). Mismo archivo
   de ajustes, opción `--var-value`.
2. **Agregar controles propios**. Ahí sí entra el fork de ComplianceAsCode:
   una regla en YAML que usa una plantilla y se compila dentro del datastream.
3. **Llevarlo a Satellite**: subir datastream + tailoring, crear la política y
   dejar que Satellite programe y centralice los reportes. Pasos y mitigación
   en [`docs/satellite.md`](docs/satellite.md).

---

## Estructura del repo

```
.
├── README.md
├── docs/
│   └── satellite.md         # escaneo y mitigación desde Satellite
├── scripts/
│   ├── 00-entorno.sh        # verifica versión, paquetes y datastream
│   ├── 01-instalar.sh       # instala (dnf o ISO local)
│   ├── 02-escanear.sh       # escaneo base CIS L1
│   ├── 03-tailoring.sh      # genera el ajuste con las excepciones
│   ├── 04-fix.sh            # genera y aplica el fix (con confirmación)
│   └── 05-verificar.sh      # conteo y lista de fallas
└── tailoring/
    └── excepciones.tsv      # regla <TAB> motivo
```

Salidas en `/tmp/openscap-workshop/` (no se versionan).

---

## Glosario

- **Datastream**: archivo XML con reglas, perfiles y chequeos.
- **Perfil**: selección de reglas y valores.
- **Regla**: una verificación concreta.
- **OVAL**: el lenguaje en que se escribe el chequeo. Mide, no arregla.
- **Tailoring**: archivo aparte que crea un perfil derivado.
- **Fix**: código que aplica la corrección (bash o Ansible).
- **ARF**: formato del resultado del escaneo.
- **`notapplicable`**: la regla no aplica a este sistema.
- **`notselected`**: la regla no está en el perfil, o la excluiste.
