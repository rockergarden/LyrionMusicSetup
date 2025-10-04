#!/bin/bash
set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables de configuración (valores por defecto; se pueden override en config)
LMS_USER="lyrion"
LMS_HOME="/opt/lyrion"

# Cargar configuraciones desde config si existen
if [ -f "config/lms-permissions.conf" ]; then
  # shellcheck disable=SC1091
  source "config/lms-permissions.conf"
fi
if [ -f "config/squeezelite.conf" ]; then
  # shellcheck disable=SC1091
  source "config/squeezelite.conf"
fi

# Asegurar variable MUSIC_DIRS venga de config o usar default
: "${MUSIC_DIRS:=("/home/cristian/Disks/HDD3" "/home/cristian/Disks/HDD5")}"

echo -e "${GREEN}=== Instalación de Lyrion Music Server ===${NC}"

# Verificar si se ejecuta como root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}No ejecutar como root${NC}"
   exit 1
fi

# Hacer scripts ejecutables
echo -e "${YELLOW}Asegurando permisos de ejecución en scripts...${NC}"
chmod +x scripts/*.sh || true

# Actualizar sistema
echo -e "${YELLOW}Actualizando sistema...${NC}"
sudo apt update && sudo apt upgrade -y

# Instalar dependencias mínimas (incluye git si falta)
echo -e "${YELLOW}Instalando dependencias...${NC}"
sudo apt install -y wget curl perl git libio-socket-ssl-perl \
    libcrypt-openssl-rsa-perl libcrypt-openssl-random-perl \
    libcrypt-openssl-bignum-perl libjson-xs-perl libcommon-sense-perl \
    libstring-crc32-perl libarchive-zip-perl libdigest-sha-perl \
    libgd-graph-perl libimage-scale-perl libaudio-scan-perl \
    libxml-parser-perl libyaml-libyaml-perl libsub-name-perl \
    squeezelite alsa-utils pulseaudio-utils

# Crear usuario del sistema para LMS si no existe
echo -e "${YELLOW}Creando/asegurando usuario del sistema...${NC}"
if ! id -u "${LMS_USER}" >/dev/null 2>&1; then
  sudo useradd -r -s /usr/sbin/nologin -m -d "${LMS_HOME}" "${LMS_USER}"
  echo "Usuario ${LMS_USER} creado"
else
  echo "Usuario ${LMS_USER} ya existe"
fi

# Descargar e instalar LMS (paquete oficial Lyrion)
echo -e "${YELLOW}Descargando e instalando Lyrion Music Server (paquete oficial)...${NC}"
LYRION_URL="https://downloads.lms-community.org/LyrionMusicServer_v9.0.3/lyrionmusicserver_9.0.3_amd64.deb"
TMP_DEB="/tmp/lyrionmusicserver_9.0.3_amd64.deb"

if curl -fsSL "$LYRION_URL" -o "$TMP_DEB"; then
  echo "Paquete descargado: $TMP_DEB"
  sudo dpkg -i "$TMP_DEB" || sudo apt-get install -f -y
  sudo rm -f "$TMP_DEB" || true
  sudo systemctl daemon-reload
else
  echo -e "${RED}No se pudo descargar $LYRION_URL${NC}"
  echo "Intentando instalar desde repositorios locales/apt..."
  sudo apt update || true
  sudo apt install -y lyrionmusicserver 2>/dev/null || echo "lyrionmusicserver no disponible en repositorios"
fi

# Copiar/añadir unit files del repo si tienes overrides
echo -e "${YELLOW}Instalando unit files personalizados (si existen) ...${NC}"
if [ -f "services/lyrion-music-service.service" ]; then
  sudo cp services/lyrion-music-service.service /etc/systemd/system/ || true
fi
if [ -f "services/squeezelite.service" ]; then
  sudo cp services/squeezelite.service /etc/systemd/system/ || true
fi
sudo systemctl daemon-reload

# Detectar unidades LMS instaladas (no conjeturas: buscar .service reales)
echo -e "${YELLOW}Buscando unidad systemd generada por el paquete LMS...${NC}"
FOUND_UNITS="$(sudo find /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system -type f -name '*.service' 2>/dev/null \
  | xargs -r -n1 basename \
  | egrep -i 'lyrion|logitech|squeezebox|slimserver|lyrionmusicserver' || true)"

if [ -n "$FOUND_UNITS" ]; then
  echo "Unidades detectadas: $FOUND_UNITS"
  while read -r unit; do
    [ -z "$unit" ] && continue
    echo "Desmascarando, habilitando y arrancando $unit ..."
    sudo systemctl unmask "$unit" 2>/dev/null || true
    sudo systemctl enable --now "$unit" 2>/dev/null || sudo systemctl restart "$unit" 2>/dev/null || true
  done <<< "$FOUND_UNITS"
else
  echo "No se detectó unidad LMS entre los servicios del sistema."
  echo "Intentando localizar unidades por nombre conocido alternativo..."
  # Intentar nombres comunes por compatibilidad
  CANDIDATES=(lyrionmusicserver logitechmediaserver squeezeboxserver slimserver)
  for name in "${CANDIDATES[@]}"; do
    unit="${name}.service"
    if systemctl list-unit-files | grep -qw "$unit"; then
      echo "Found unit $unit, enabling..."
      sudo systemctl unmask "$unit" 2>/dev/null || true
      sudo systemctl enable --now "$unit" 2>/dev/null || sudo systemctl restart "$unit" 2>/dev/null || true
      FOUND_UNITS="$unit"
      break
    fi
  done
fi

# Siempre habilitar/arrancar squeezelite si está disponible
if systemctl list-unit-files | grep -qw squeezelite.service; then
  echo "Enabling and starting squeezelite.service"
  sudo systemctl unmask squeezelite.service 2>/dev/null || true
  sudo systemctl enable --now squeezelite.service 2>/dev/null || sudo systemctl restart squeezelite.service 2>/dev/null || true
fi

# Esperar LMS up antes de instalar plugins
echo -e "${YELLOW}Esperando a que LMS esté accesible (hasta 60s)...${NC}"
for i in {1..12}; do
  if curl -sSf "http://localhost:9000" >/dev/null 2>&1; then
    echo "LMS disponible"
    break
  fi
  sleep 5
done

# Instalar plugin de Airplay (script se asegura de git y permisos)
echo -e "${YELLOW}Instalando plugin de Airplay...${NC}"
bash scripts/install-airplay-plugin.sh

# Configurar y habilitar Squeezelite (systemd)
echo -e "${YELLOW}Configurando y habilitando Squeezelite (systemd)...${NC}"
chmod +x scripts/setup-squeezelite-systemd.sh
sudo bash scripts/setup-squeezelite-systemd.sh

echo -e "${GREEN}¡Instalación completada!${NC}"
echo -e "${GREEN}Accede a LMS en: http://localhost:9000${NC}"
echo -e "${GREEN}Configuración de audio completada para DAC USB${NC}"

# === NUEVO BLOQUE: detectar usuario del servicio LMS y asegurar dirs/permisos ===
echo -e "${YELLOW}Determinando usuario que ejecutará LMS y asegurando permisos...${NC}"
# Intentar obtener User directamente de la unidad conocida
SERVICE_USER=$(sudo systemctl show -p User --value lyrionmusicserver.service 2>/dev/null || true)
# Si no está, buscar fichero .service que invoque el binario y leer su User
if [ -z "$SERVICE_USER" ]; then
  UNIT_FILE=$(sudo grep -Il "/usr/sbin/squeezeboxserver" /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system 2>/dev/null | head -n1 || true)
  if [ -n "$UNIT_FILE" ]; then
    UNIT_NAME=$(basename "$UNIT_FILE")
    SERVICE_USER=$(sudo systemctl show -p User --value "$UNIT_NAME" 2>/dev/null || true)
  fi
fi
# Fallback razonable si no se detecta
SERVICE_USER=${SERVICE_USER:-squeezeboxserver}
LMS_USER="$SERVICE_USER"
echo "Usando usuario de servicio: $LMS_USER"

# Crear usuario de sistema solo si realmente falta (normalmente el paquete ya lo crea)
if ! id -u "$LMS_USER" >/dev/null 2>&1; then
  echo "Creando usuario de sistema $LMS_USER"
  sudo useradd -r -s /usr/sbin/nologin -m -d "${LMS_HOME}" "$LMS_USER" || true
fi

# Asegurar directorios y permisos que LMS requiere
sudo mkdir -p /var/lib/squeezeboxserver/prefs /var/lib/squeezeboxserver/cache /var/log/squeezeboxserver
# chown al usuario detectado; si el grupo no existe, intentar con nogroup
if sudo chown -R "$LMS_USER":"$LMS_USER" /var/lib/squeezeboxserver /var/log/squeezeboxserver 2>/dev/null; then
  true
else
  sudo chown -R "$LMS_USER":nogroup /var/lib/squeezeboxserver /var/log/squeezeboxserver || true
fi
sudo chmod -R 750 /var/lib/squeezeboxserver /var/log/squeezeboxserver
# === FIN BLOQUE ===