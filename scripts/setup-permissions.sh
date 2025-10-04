#!/bin/bash
set -e

# Cargar configuración
CFG="$(dirname "$0")/../config/lms-permissions.conf"
if [ -f "$CFG" ]; then
  # shellcheck disable=SC1091
  source "$CFG"
fi

# Valores por defecto
: "${LMS_USER:=lyrion}"
# Determinar HOST_USER si no está establecido en config
if [ -z "${HOST_USER:-}" ]; then
  HOST_USER=$(logname 2>/dev/null || echo "$SUDO_USER" || echo "$USER")
fi

echo "Aplicando permisos a directorios de música..."

# Verificar que el usuario LMS exista
if ! id "$LMS_USER" &>/dev/null; then
  echo "Usuario $LMS_USER no existe. Creando usuario sistema..."
  sudo useradd -r -s /usr/sbin/nologin -m -d "/opt/$LMS_USER" "$LMS_USER" || true
fi

for dir in "${MUSIC_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    echo "Config: $dir"
    # Mantener propietario del host (ej: cristian) y dar lectura al grupo
    sudo chown -R "$HOST_USER":"$HOST_USER" "$dir" || true
    sudo chmod -R g+r "$dir" || true
    sudo find "$dir" -type d -exec chmod g+x {} \; || true
    # ACL para usuario LMS
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