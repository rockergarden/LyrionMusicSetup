#!/bin/bash
set -e

# Desinstalador independiente de Shairport‑Sync para LyrionMusicSetup
# Uso:
#   chmod +x scripts/uninstall-shairport-sync.sh
#   bash scripts/uninstall-shairport-sync.sh    # pedirá confirmación
#   bash scripts/uninstall-shairport-sync.sh --yes  # sin confirmación

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $EUID -eq 0 ]]; then
  echo -e "${RED}No ejecutar como root. El script usará sudo cuando haga falta.${NC}"
  exit 1
fi

AUTO_CONFIRM=0
if [ "$1" = "--yes" ] || [ "$1" = "-y" ]; then
  AUTO_CONFIRM=1
fi

echo -e "${YELLOW}Este script removerá la instalación de shairport-sync creada por LyrionMusicSetup.${NC}"
if [ $AUTO_CONFIRM -ne 1 ]; then
  read -rp "Continuar? [y/N]: " REPLY
  case "$REPLY" in
    [Yy]*) ;;
    *) echo "Abortando."; exit 0;;
  esac
fi

# Detectar unidad LMS para reactivar al final si fue previamente parada
CANDIDATES=(lyrionmusicserver logitechmediaserver squeezeboxserver slimserver)
LMS_UNIT=""
for name in "${CANDIDATES[@]}"; do
  if systemctl list-unit-files | grep -qw "${name}.service"; then
    LMS_UNIT="${name}.service"
    break
  fi
done

echo -e "${YELLOW}Parando y deshabilitando shairport-sync (si existe)...${NC}"
sudo systemctl stop shairport-sync.service 2>/dev/null || true
sudo systemctl disable shairport-sync.service 2>/dev/null || true

DROPIN_DIR="/etc/systemd/system/shairport-sync.service.d"
DROPIN_FILE="${DROPIN_DIR}/lyrion-bridge.conf"
if [ -f "$DROPIN_FILE" ]; then
  echo -e "${YELLOW}Eliminando drop-in systemd: ${DROPIN_FILE}${NC}"
  sudo rm -f "$DROPIN_FILE"
  # eliminar dir si quedó vacío
  if [ -d "$DROPIN_DIR" ]; then
    if [ -z "$(ls -A "$DROPIN_DIR")" ]; then
      sudo rmdir "$DROPIN_DIR" 2>/dev/null || true
    fi
  fi
  sudo systemctl daemon-reload
fi

# Hacer backup de la config y luego eliminar
SH_CONF="/etc/shairport-sync.conf"
if [ -f "$SH_CONF" ]; then
  echo -e "${YELLOW}Moviendo /etc/shairport-sync.conf a /tmp/shairport-sync.conf.backup${NC}"
  sudo mv -f "$SH_CONF" /tmp/shairport-sync.conf.backup || true
fi

# Intentar eliminar al usuario shairport-sync del grupo audio (seguro si existe)
if getent group audio >/dev/null 2>&1; then
  if getent passwd shairport-sync >/dev/null 2>&1; then
    echo -e "${YELLOW}Quitando shairport-sync del grupo audio...${NC}"
    sudo gpasswd -d shairport-sync audio 2>/dev/null || true
  fi
fi

# Desinstalar paquete y dependencias extra instaladas por apt
echo -e "${YELLOW}Desinstalando paquete shairport-sync (apt purge)...${NC}"
sudo apt update
sudo apt purge -y shairport-sync 2>/dev/null || true
sudo apt autoremove -y 2>/dev/null || true

# Intentar reiniciar LMS si existía
if [ -n "$LMS_UNIT" ]; then
  echo -e "${YELLOW}Intentando arrancar unidad LMS detectada: ${LMS_UNIT}${NC}"
  sudo systemctl start "$LMS_UNIT" 2>/dev/null || true
fi

echo -e "${GREEN}Operación completada.${NC}"
echo "- /etc/shairport-sync.conf movido a /tmp/shairport-sync.conf.backup (si existía)"
echo "- drop-in systemd ${DROPIN_FILE} eliminado (si existía)"
echo "- paquete shairport-sync intentado purgar (si estaba instalado)"
echo
echo -e "${YELLOW}Recomendación: verifica el estado de servicios y audio:${NC}"
echo "  sudo systemctl status shairport-sync"
if [ -n "$LMS_UNIT" ]; then
  echo "  sudo systemctl status ${LMS_UNIT}"
fi
echo "  aplay -l"