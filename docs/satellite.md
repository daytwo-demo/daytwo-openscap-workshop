# Satellite: escaneo y mitigación

Cómo se lleva el ajuste local al Satellite y cómo se remedia desde ahí, con REX
y sin REX.

## Lo que Satellite necesita

Tres objetos:

1. el **contenido**: el datastream (`ssg-rhel10-ds.xml`),
2. el **ajuste**: el tailoring (`daytwo-rhel10-tailoring.xml`),
3. la **política**: perfil + ajuste + hostgroup.

```bash
# contenido
hammer scap-content bulk-upload --type directory \
  --directory /usr/share/xml/scap/ssg/content/ \
  --organization "DayTwo" --location "Default Location"

# ajuste
hammer tailoring-file create \
  --name "DayTwo CIS L1" \
  --scap-file daytwo-rhel10-tailoring.xml \
  --organization "DayTwo" --location "Default Location"
```

Los IDs se ven con `hammer scap-content list`, `hammer tailoring-file list` y
en la UI.

## Crear la política

La diferencia entre los dos flujos es `--deploy-by`.

**Con REX:**

```bash
hammer policy create \
  --name "DayTwo CIS L1 - RHEL 10" \
  --scap-content-id <ID> \
  --scap-content-profile-id <ID> \
  --tailoring-file-id <ID> \
  --deploy-by ansible \
  --period weekly --weekday monday \
  --hostgroup-ids <ID> \
  --organization "DayTwo" --location "Default Location"
```

**Sin REX:**

```bash
hammer policy create ... --deploy-by manual ...
```

`--deploy-by` dice quién instala el cliente en el host, no cómo se escanea.

## Escaneo con REX

1. Al hostgroup se le asigna el rol `theforeman.foreman_scap_client`, la política
   y el proxy de OpenSCAP.
2. Se corre el rol:

```bash
hammer hostgroup ansible-roles play --name demo-rhel9
```

3. Satellite deja en el host el `config.yaml` con el servidor, el puerto 9090 y
   el `policy_id`, y la entrada de cron.
4. El host escanea por cron y sube el reporte al proxy.
5. Reporte en **Hosts → Reports**.

Para escanear en el momento:

```bash
hammer job-invocation create \
  --job-template "Run OpenSCAP scan" \
  --search "name = demo-rhel9-1"
```

## Escaneo sin REX

1. El cliente se instala por fuera: imagen, AAP/Ansible desde un bastión o a mano
   con el RPM `foreman_scap_client`.
2. El config es el mismo:

```yaml
:server: satellite.daytwodemo.com
:port: 9090
:host_cert: /etc/pki/consumer/cert.pem
:host_key: /etc/pki/consumer/key.pem
:policy_id: 3
```

3. El cron escanea y el host sube el reporte.
4. Para escanear en el momento:

```bash
sudo foreman_scap_client 3
```

## Mitigación con REX

Desde el reporte de un host, el botón **Remediate** lanza un job template de
OpenSCAP:

- **Run OpenSCAP remediation - Ansible**
- **Run OpenSCAP remediation - Script**

Por CLI:

```bash
hammer job-invocation create \
  --job-template "Run OpenSCAP remediation - Ansible" \
  --search "name = demo-rhel9-1"
```

Ese playbook aplica los fixes del **perfil de la política**, que ya incluye el
tailoring. No usa el perfil base.

Después de remediar, se vuelve a escanear y se compara el reporte.

## Mitigación sin REX

Satellite no puede entrar al host, así que el reporte se usa como entrada para
el equipo que remedia:

1. Se descarga el reporte (HTML o ARF) o se consulta en Satellite.
2. Se genera el fix con el **mismo perfil y el mismo tailoring**:

```bash
DS=/usr/share/xml/scap/ssg/content/ssg-rhel10-ds.xml
ID=$(oscap info daytwo-rhel10-tailoring.xml | sed -n '/Profiles:/,+3p' | grep -o 'xccdf_org[^ ]*' | head -1)

oscap xccdf generate fix --fix-type ansible \
  --profile "$ID" \
  --tailoring-file daytwo-rhel10-tailoring.xml \
  -o fix.yml "$DS"
```

3. Se corre con AAP o Ansible desde el bastión.

Para remediar solo lo que falló, se genera el fix desde el resultado del scan:

```bash
oscap xccdf generate fix --result-id <testresult-id> \
  --fix-type ansible -o fix.yml resultado.xml
```

Y se vuelve a escanear.

## El contrato entre equipos

Si el escaneo y la remediación los hace gente distinta:

- **El que reporta no arregla; el que arregla no reporta.**
- Los dos usan el **mismo perfil y el mismo tailoring**.
- **Excluir del fix no es excluir del reporte.** Si `sshd` lo maneja el equipo
  de remediación, el fix no lo toca, pero el reporte sí lo mide: es la evidencia
  de que cumplieron.
- **Un dueño por directiva.** Si un System Role escribe `sshd`, el fix de
  OpenSCAP no debe escribir las mismas líneas.

## El detalle del hash

Al cambiar el datastream o el tailoring, cambia el hash del contenido. El host
sigue apuntando al hash viejo hasta que se actualiza su `config.yaml`.

- Con REX: lo hace el rol cuando se vuelve a correr.
- Sin REX: lo hace el mecanismo de configuración del equipo de remediación.

Si no se actualiza, el host escanea con reglas viejas y el reporte parece
válido.
