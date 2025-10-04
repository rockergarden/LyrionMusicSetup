#!/bin/bash
set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables de configuración
LMS_USER="lyrion"
LMS_HOME="/opt/lyrion"
MUSIC_DIRS=("/home/cristian/Disks/HDD3" "/home/cristian/Disks/HDD5")

echo -e "${GREEN}=== Instalación de Lyrion Music Server ===${NC}"

# Verificar si se ejecuta como root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}No ejecutar como root${NC}" 
   exit 1
fi

# Actualizar sistema
echo -e "${YELLOW}Actualizando sistema...${NC}"
sudo apt update && sudo apt upgrade -y

# Instalar dependencias
echo -e "${YELLOW}Instalando dependencias...${NC}"
sudo apt install -y wget curl perl libio-socket-ssl-perl \
    libcrypt-openssl-rsa-perl libcrypt-openssl-random-perl \
    libcrypt-openssl-bignum-perl libjson-xs-perl libcommon-sense-perl \
    libstring-crc32-perl libarchive-zip-perl libdigest-sha-perl \
    libgd-graph-perl libimage-scale-perl libaudio-scan-perl \
    libxml-parser-perl libyaml-libyaml-perl libsub-name-perl \
    squeezelite alsa-utils pulseaudio-utils

# Crear usuario del sistema para LMS
echo -e "${YELLOW}Creando usuario del sistema...${NC}"
sudo useradd -r -s /bin/false -d $LMS_HOME $LMS_USER || echo "Usuario ya existe"

# Descargar e instalar LMS
echo -e "${YELLOW}Descargando Lyrion Music Server...${NC}"
LMS_VERSION=$(curl -s https://api.github.com/repos/LMS-Community/slimserver/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
LMS_DEB_URL="https://github.com/LMS-Community/slimserver/releases/download/${LMS_VERSION}/logitechmediaserver_${LMS_VERSION}_all.deb"

wget -O /tmp/lms.deb $LMS_DEB_URL
sudo dpkg -i /tmp/lms.deb || sudo apt-get install -f -y

# Configurar permisos de directorios de música
echo -e "${YELLOW}Configurando permisos...${NC}"
bash scripts/setup-permissions.sh

# Configurar servicios
echo -e "${YELLOW}Configurando servicios...${NC}"
sudo cp services/lyrion-music-server.service /etc/systemd/system/
sudo cp services/squeezelite.service /etc/systemd/system/
sudo systemctl daemon-reload

# Configurar audio
echo -e "${YELLOW}Configurando audio...${NC}"
bash scripts/configure-audio.sh

# Habilitar e iniciar servicios
echo -e "${YELLOW}Habilitando servicios...${NC}"
sudo systemctl enable logitechmediaserver
sudo systemctl enable squeezelite
sudo systemctl start logitechmediaserver
sudo systemctl start squeezelite

# Instalar plugin de Airplay
echo -e "${YELLOW}Instalando plugin de Airplay...${NC}"
sleep 10 # Esperar que LMS inicie completamente
bash scripts/install-airplay-plugin.sh

echo -e "${GREEN}¡Instalación completada!${NC}"
echo -e "${GREEN}Accede a LMS en: http://localhost:9000${NC}"
echo -e "${GREEN}Configuración de audio completada para DAC USB${NC}"