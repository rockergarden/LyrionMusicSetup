#!/bin/bash
set -e

# Instalador independiente de Shairport‑Sync para LyrionMusicSetup
# Uso: desde el repo:
#   chmod +x scripts/install-shairport-sync.sh
#   bash scripts/install-shairport-sync.sh
# Se puede overridear el DAC con: export DAC_DEVICE="plughw:1,0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# No ejecutar como root
if [[ $EUID -eq 0 ]]; then
  echo -e "${RED}No ejecutar como root. El script usará sudo cuando haga falta.${NC}"
  exit 1
fi

echo -e "${GREEN}=== Instalando y configurando Shairport‑Sync ===${NC}"

# Dispositivo ALSA por defecto: card 1 device 0 (USB HIFI Audio)
: "${DAC_DEVICE:=plughw:1,0}"

# Detectar unidad LMS a parar/reiniciar (intenta detectar servicios reales)
CANDIDATES=(lyrionmusicserver logitechmediaserver squeezeboxserver slimserver)
LMS_UNIT=""
for name in "${CANDIDATES[@]}"; do
  if systemctl list-unit-files | grep -qw "${name}.service"; then
    LMS_UNIT="${name}.service"
    break
  fi
done
LMS_UNIT=${LMS_UNIT:-lyrionmusicserver.service}
echo -e "${YELLOW}Unidad LMS detectada: ${LMS_UNIT}${NC}"

# Actualizar e instalar paquete (si no existe, intenta compilar/instalar dependencias mínimas)
echo -e "${YELLOW}Instalando shairport-sync y dependencias...${NC}"
sudo apt update
sudo apt install -y shairport-sync avahi-daemon alsa-utils libsoxr0 || true

# Asegurar que el demonio Avahi esté activo (mDNS)
sudo systemctl enable --now avahi-daemon.service || true

# Generar configuración /etc/shairport-sync.conf apuntando al DAC USB (card 1 device 0)
echo -e "${YELLOW}Escribiendo /etc/shairport-sync.conf usando DAC: ${DAC_DEVICE}${NC}"
sudo tee /etc/shairport-sync.conf >/dev/null <<EOF
general = {
  name = "Lyrion AirPlay";
  output_backend = "alsa";
  interpolation = "soxr";
  session_timeout = 60;
  latency = 220;
};

alsa = {
  output_device = "${DAC_DEVICE}";
  mixer_control_name = "PCM";
  mixer_device = "default";
  mixer_enabled = "yes";
};

statistics = {
  log_verbosity = 1;
};
EOF

# Asegurar usuario del servicio tenga acceso al grupo audio
DAEMON_USER=$(getent passwd shairport-sync | cut -d: -f1 || true)
if [ -z "$DAEMON_USER" ]; then
  # paquete puede crear otro usuario; intentar suponer shairport-sync o añadir el usuario actual
  DAEMON_USER="shairport-sync"
fi
if id -u "$DAEMON_USER" >/dev/null 2>&1; then
  sudo usermod -aG audio "$DAEMON_USER" || true
else
  sudo usermod -aG audio "$(whoami)" || true
fi

# Crear drop-in systemd para conmutar entre LMS y Shairport‑Sync
DROPIN_DIR="/etc/systemd/system/shairport-sync.service.d"
echo -e "${YELLOW}Creando drop-in systemd para detener ${LMS_UNIT} al iniciar Shairport y reiniciarlo al parar...${NC}"
sudo mkdir -p "$DROPIN_DIR"
TMP_DROPIN="$(mktemp)"
cat > "$TMP_DROPIN" <<EOF
[Service]
# Antes de arrancar Shairport‑Sync, parar la unidad LMS (bloqueante)
ExecStartPre=/bin/systemctl stop ${LMS_UNIT}
# Esperar hasta que /dev/snd esté libre (máx 15s) para asegurar liberación del dispositivo ALSA
ExecStartPre=/bin/sh -c 'count=0; max=15; while fuser -s /dev/snd/* 2>/dev/null; do sleep 1; count=\$((count+1)); if [ \$count -ge \$max ]; then echo "Timeout waiting for /dev/snd to be free" >&2; break; fi; done'
# Al parar Shairport‑Sync, intentar arrancar LMS de nuevo (bloqueante)
ExecStopPost=/bin/systemctl start ${LMS_UNIT}
EOF
sudo mv "$TMP_DROPIN" "${DROPIN_DIR}/lyrion-bridge.conf"
sudo chmod 644 "${DROPIN_DIR}/lyrion-bridge.conf"

# Recargar systemd y (re)iniciar shairport-sync
sudo systemctl daemon-reload
sudo systemctl enable --now shairport-sync.service || sudo systemctl restart shairport-sync.service || true
sleep 1

if systemctl is-active --quiet shairport-sync.service; then
  echo -e "${GREEN}Shairport‑Sync activo y escuchando (AirPlay).${NC}"
else
  echo -e "${RED}No se pudo arrancar Shairport‑Sync. Revisa: sudo journalctl -u shairport-sync -n 200${NC}"
fi

echo -e "${GREEN}Listo. Puntos importantes:${NC}"
echo "- /etc/shairport-sync.conf configurado para usar DAC USB (card 1 device 0): ${DAC_DEVICE}"
echo "- Systemd drop-in creado: ${DROPIN_DIR}/lyrion-bridge.conf"
echo "- Al iniciar Shairport, el servicio ${LMS_UNIT} será detenido; al parar Shairport, se intentará arrancar ${LMS_UNIT}."
echo
echo -e "${YELLOW}Para cambiar el DAC: export DAC_DEVICE=\"plughw:1,0\" (o hw:1,0) && bash scripts/install-shairport-sync.sh${NC}"