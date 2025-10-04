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

# Descargar e instalar LMS
echo -e "${YELLOW}Descargando Lyrion Music Server...${NC}"
LMS_VERSION=$(curl -s https://api.github.com/repos/LMS-Community/slimserver/releases/latest | grep -Po '"tag_name": "\K.*?(?=")') || true
if [ -z "$LMS_VERSION" ]; then
  echo "No se pudo obtener versión desde GitHub, intentando paquete por defecto..."
else
  LMS_DEB_URL="https://github.com/LMS-Community/slimserver/releases/download/${LMS_VERSION}/logitechmediaserver_${LMS_VERSION}_all.deb"
  wget -O /tmp/lms.deb "$LMS_DEB_URL" || true
  if [ -f /tmp/lms.deb ]; then
    sudo dpkg -i /tmp/lms.deb || sudo apt-get install -f -y
  else
    echo "Paquete .deb no descargado, omitiendo dpkg step"
  fi
fi

# Copiar/añadir servicios systemd (mapea a nombres esperados)
echo -e "${YELLOW}Configurando servicios systemd...${NC}"
# mapar custom service a nombre logitechmediaserver.service si es necesario
if [ -f "services/logitechmediaserver.service" ]; then
  sudo cp services/logitechmediaserver.service /etc/systemd/system/logitechmediaserver.service
elif [ -f "services/lyrion-music-service.service" ]; then
  sudo cp services/lyrion-music-service.service /etc/systemd/system/logitechmediaserver.service
else
  echo "Advertencia: no se encontró service de LMS en services/, el paquete instalado puede suministrarlo"
fi

if [ -f "services/squeezelite.service" ]; then
  sudo cp services/squeezelite.service /etc/systemd/system/squeezelite.service
fi

sudo systemctl daemon-reload

# Configurar permisos de directorios de música (usa scripts/setup-permissions.sh)
echo -e "${YELLOW}Configurando permisos...${NC}"
bash scripts/setup-permissions.sh

# Configurar audio: asound y /etc/default/squeezelite
echo -e "${YELLOW}Configurando audio...${NC}"
bash scripts/configure-audio.sh

# Habilitar e iniciar servicios (intenta nombres estándar)
echo -e "${YELLOW}Habilitando e iniciando servicios...${NC}"
if systemctl list-unit-files | grep -qw logitechmediaserver.service; then
  sudo systemctl enable logitechmediaserver
  sudo systemctl restart logitechmediaserver || true
else
  echo "logitechmediaserver.service no disponible en systemd"
fi

if systemctl list-unit-files | grep -qw squeezelite.service; then
  sudo systemctl enable squeezelite
  sudo systemctl restart squeezelite || true
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

echo -e "${GREEN}¡Instalación completada!${NC}"
echo -e "${GREEN}Accede a LMS en: http://localhost:9000${NC}"
echo -e "${GREEN}Configuración de audio completada para DAC USB${NC}"