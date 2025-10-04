#!/bin/bash
set -e
# Cargar configuración
source "$(dirname "$0")/../config/lms-permissions.conf"

echo "Aplicando permisos a directorios de música..."
if ! id "$LMS_USER" &>/dev/null; then
  echo "Usuario $LMS_USER no existe. Créalo antes o ajusta config/lms-permissions.conf"
  exit 1
fi

for dir in "${MUSIC_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    echo "Config: $dir"
    sudo chown -R "$HOST_USER":"$HOST_USER" "$dir" || true
    # Dar lectura/ejecución al grupo y ACL para el usuario LMS
    sudo chmod -R g+r "$dir" || true
    sudo find "$dir" -type d -exec chmod g+x {} \; || true
    sudo setfacl -R -m u:"$LMS_USER":rX "$dir" 2>/dev/null || true
  else
    echo "Advertencia: $dir no existe"
  fi
done

# Directorios de LMS
sudo mkdir -p /var/lib/squeezeboxserver /var/log/squeezeboxserver
sudo chown -R "$LMS_USER":"$LMS_USER" /var/lib/squeezeboxserver /var/log/squeezeboxserver

# Añadir al grupo audio
sudo usermod -a -G audio "$LMS_USER" 2>/dev/null || true

echo "Permisos aplicados."