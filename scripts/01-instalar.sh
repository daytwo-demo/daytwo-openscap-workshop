#!/usr/bin/env bash
# Instala las herramientas. Sin argumentos usa dnf; con --iso usa el DVD local.
#   ./scripts/01-instalar.sh
#   ./scripts/01-instalar.sh --iso /dev/sr0
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh
need_root

PAQUETES=(openscap-scanner openscap-utils scap-security-guide)

install_from_iso() {
    local dev="$1" mnt=/mnt/iso
    mkdir -p "$mnt"
    mountpoint -q "$mnt" || mount -o loop "$dev" "$mnt"
    cat > /etc/yum.repos.d/openscap-workshop-iso.repo <<'EOF'
[workshop-baseos]
name=Workshop BaseOS (ISO)
baseurl=file:///mnt/iso/BaseOS
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
enabled=1

[workshop-appstream]
name=Workshop AppStream (ISO)
baseurl=file:///mnt/iso/AppStream
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
enabled=1
EOF
    dnf -y --disablerepo='*' --enablerepo='workshop-*' install "${PAQUETES[@]}"
}

if [ "${1:-}" = "--iso" ]; then
    install_from_iso "${2:-/dev/sr0}"
else
    if ! dnf -y install "${PAQUETES[@]}"; then
        echo "dnf falló (¿sin internet?). Prueba: $0 --iso /dev/sr0"
        exit 1
    fi
fi

echo
echo "instalado. datastream: $DS"
