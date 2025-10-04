#!/bin/bash
set -e

echo "Desinstalando Lyrion Music Server..."

# Detener servicios
SERVICES=("logitechmediaserver" "lyrion-music-server" "lyrion-music-service" "squeezelite")
for svc in "${SERVICES[@]}"; do
  if systemctl list-unit-files | grep -qw "${svc}.service"; then
    echo "Deteniendo y deshabilitando ${svc}.service"
    sudo systemctl stop "${svc}.service" 2>/dev/null || true
    sudo systemctl disable "${svc}.service" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${svc}.service"
  fi
done

sudo systemctl daemon-reload

# Desinstalar paquetes si existen
PKGS=(logitechmediaserver squeezelite)
for pkg in "${PKGS[@]}"; do
  if dpkg -l | grep -qw "${pkg}"; then
    sudo apt remove --purge -y "${pkg}" || true
  fi
done

# Remover usuario del sistema
if id "lyrion" &>/dev/null; then
  echo "Eliminando usuario 'lyrion'"
  sudo userdel -r lyrion || true
else
  echo "Usuario 'lyrion' no existe, omitiendo userdel"
fi

# Remover directorios de datos (opcional)
read -p "¿Remover datos de LMS? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo rm -rf /var/lib/squeezeboxserver
    sudo rm -rf /var/log/squeezeboxserver
fi

echo "Desinstalación completada"