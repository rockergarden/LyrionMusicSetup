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
sudo apt install -y shairport-sync avahi-daemon alsa-utils libsoxr0 psmisc || true

# Asegurar que el demonio Avahi esté activo (mDNS)
sudo systemctl enable --now avahi-daemon.service || true

# Generar configuración /etc/shairport-sync.conf apuntando al DAC USB (card 1 device 0)
# IMPORTANTE: mixer_enabled = "no" para no interferir con el control de volumen de LMS
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
  mixer_enabled = "no";  // No controlar mezclador para evitar conflictos con LMS
  mixer_device = "default";
};

statistics = {
  log_verbosity = 1;
};
EOF

# Asegurar usuario del servicio tenga acceso al grupo audio
DAEMON_USER=$(getent passwd shairport-sync | cut -d: -f1 2>/dev/null || true)
if [ -z "$DAEMON_USER" ]; then
  DAEMON_USER="shairport-sync"
fi
if id -u "$DAEMON_USER" >/dev/null 2>&1; then
  sudo usermod -aG audio "$DAEMON_USER" || true
else
  sudo usermod -aG audio "$(whoami)" || true
fi

# Crear hook script robusto que para LMS y espera a que /dev/snd esté libre
echo -e "${YELLOW}Creando hook script /usr/local/bin/lyrion-shairport-hook.sh${NC}"
HOOK_SCRIPT="/usr/local/bin/lyrion-shairport-hook.sh"
TMP_HOOK="$(mktemp)"
cat > "$TMP_HOOK" <<'EOFHOOK'
#!/bin/bash
set -e

# Hook para systemd drop-in de shairport-sync
# Usage: /usr/local/bin/lyrion-shairport-hook.sh start|stop

LMS_UNIT="${LMS_UNIT:-lyrionmusicserver.service}"
MAX_WAIT=${MAX_WAIT:-25}

log() { echo "[lyrion-hook] $*"; }

wait_for_snd_free() {
  local count=0
  while fuser -s /dev/snd/* 2>/dev/null; do
    sleep 1
    count=$((count+1))
    if [ "$count" -ge "$MAX_WAIT" ]; then
      log "Timeout esperando /dev/snd libre"
      break
    fi
  done
}

stop_lms_and_holders() {
  log "Parando unidad systemd ${LMS_UNIT}"
  if systemctl list-unit-files | grep -qw "${LMS_UNIT}"; then
    systemctl stop "${LMS_UNIT}" 2>/dev/null || true
  fi

  # Matar procesos conocidos de LMS que puedan retener ALSA
  log "Matando procesos LMS conocidos (squeezeboxserver/logitechmediaserver)"
  pkill -f squeezeboxserver 2>/dev/null || true
  pkill -f logitechmediaserver 2>/dev/null || true
  pkill -f slimserver 2>/dev/null || true

  # Esperar hasta que /dev/snd esté libre
  wait_for_snd_free
  log "/dev/snd libre (o timeout alcanzado)"
}

start_lms_and_restore_alsa() {
  log "Iniciando unidad systemd ${LMS_UNIT}"
  if systemctl list-unit-files | grep -qw "${LMS_UNIT}"; then
    systemctl start "${LMS_UNIT}" 2>/dev/null || true
  fi

  # Intentar restaurar estado ALSA para que LMS pueda controlar DAC de nuevo
  log "Restaurando ALSA"
  if systemctl list-unit-files | grep -qw "alsa-restore.service"; then
    systemctl restart alsa-restore.service 2>/dev/null || true
  fi
  
  # Forzar reinicio del dispositivo ALSA si existe alsactl
  if command -v alsactl >/dev/null 2>&1; then
    alsactl restore 2>/dev/null || true
  fi

  sleep 2
  log "Hook start completado"
}

case "$1" in
  start) stop_lms_and_holders ;;
  stop)  start_lms_and_restore_alsa ;;
  *) echo "Usage: $0 start|stop"; exit 2 ;;
esac
EOFHOOK

# Reemplazar variable LMS_UNIT en el hook con valor detectado
sed -i.bak "s/LMS_UNIT=\${LMS_UNIT:-lyrionmusicserver.service}/LMS_UNIT=\${LMS_UNIT:-${LMS_UNIT}}/" "$TMP_HOOK" || true
sudo mv "$TMP_HOOK" "$HOOK_SCRIPT"
sudo chmod +x "$HOOK_SCRIPT"

# Crear drop-in systemd para conmutar entre LMS y Shairport‑Sync usando el hook
DROPIN_DIR="/etc/systemd/system/shairport-sync.service.d"
echo -e "${YELLOW}Creando drop-in systemd para usar hook al iniciar/parar Shairport${NC}"
sudo mkdir -p "$DROPIN_DIR"
TMP_DROPIN="$(mktemp)"
cat > "$TMP_DROPIN" <<EOF
[Service]
# Antes de arrancar Shairport‑Sync: ejecutar hook que para LMS y espera /dev/snd libre
ExecStartPre=${HOOK_SCRIPT} start
# Al parar Shairport‑Sync: ejecutar hook que arranca LMS y restaura ALSA
ExecStopPost=${HOOK_SCRIPT} stop
EOF
sudo mv "$TMP_DROPIN" "${DROPIN_DIR}/lyrion-bridge.conf"
sudo chmod 644 "${DROPIN_DIR}/lyrion-bridge.conf"

# Recargar systemd y (re)iniciar shairport-sync
sudo systemctl daemon-reload
sudo systemctl enable --now shairport-sync.service || sudo systemctl restart shairport-sync.service || true
sleep 2

if systemctl is-active --quiet shairport-sync.service; then
  echo -e "${GREEN}Shairport‑Sync activo y escuchando (AirPlay).${NC}"
else
  echo -e "${RED}No se pudo arrancar Shairport‑Sync. Revisa: sudo journalctl -u shairport-sync -n 200${NC}"
fi

echo -e "${GREEN}Instalación completada. Puntos importantes:${NC}"
echo "- /etc/shairport-sync.conf configurado para DAC: ${DAC_DEVICE} (mixer_enabled=no)"
echo "- Hook script creado: ${HOOK_SCRIPT}"
echo "- Systemd drop-in: ${DROPIN_DIR}/lyrion-bridge.conf"
echo "- Al conectar AirPlay, el servicio ${LMS_UNIT} será detenido automáticamente"
echo "- Al desconectar AirPlay, ${LMS_UNIT} se reiniciará automáticamente"
echo
echo -e "${YELLOW}Verificaciones recomendadas:${NC}"
echo "  sudo journalctl -u shairport-sync -f   # ver logs en tiempo real"
echo "  sudo journalctl -u ${LMS_UNIT} -f"
echo "  sudo fuser -v /dev/snd/*   # ver qué procesos usan el DAC"
echo "  aplay -l   # listar dispositivos"
echo
echo -e "${YELLOW}Para cambiar DAC: export DAC_DEVICE=\"plughw:1,0\" && bash scripts/install-shairport-sync.sh${NC}"