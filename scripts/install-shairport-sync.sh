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

# Crear wrapper script que para LMS ANTES de ejecutar shairport-sync
echo -e "${YELLOW}Creando wrapper script /usr/local/bin/shairport-sync-wrapper.sh${NC}"
WRAPPER_SCRIPT="/usr/local/bin/shairport-sync-wrapper.sh"
TMP_WRAPPER="$(mktemp)"
cat > "$TMP_WRAPPER" <<'EOFWRAPPER'
#!/bin/bash
set -e

# Wrapper para shairport-sync que libera ALSA antes de arrancar
LMS_UNIT="lyrionmusicserver.service"
MAX_WAIT=25

log() { echo "[shairport-wrapper] $*"; }

# Parar LMS y procesos que retengan ALSA
log "Parando ${LMS_UNIT} y procesos relacionados"
systemctl stop "${LMS_UNIT}" 2>/dev/null || true
pkill -f squeezeboxserver 2>/dev/null || true
pkill -f logitechmediaserver 2>/dev/null || true
pkill -f slimserver 2>/dev/null || true
pkill -f squeezelite 2>/dev/null || true  # CRÍTICO: matar squeezelite

# Esperar hasta que /dev/snd esté libre
count=0
while fuser -s /dev/snd/* 2>/dev/null; do
  log "Esperando a que /dev/snd se libere... (intento $count/$MAX_WAIT)"
  
  # Si después de 5 intentos sigue ocupado, forzar kill más agresivo
  if [ "$count" -eq 5 ]; then
    log "Forzando kill de procesos ALSA..."
    pkill -9 -f squeezelite 2>/dev/null || true
    fuser -k /dev/snd/* 2>/dev/null || true
  fi
  
  sleep 1
  count=$((count+1))
  if [ "$count" -ge "$MAX_WAIT" ]; then
    log "WARN: Timeout esperando /dev/snd libre. Intentando arrancar shairport-sync de todos modos."
    break
  fi
done
log "/dev/snd libre (o timeout). Arrancando shairport-sync real."

# Ejecutar shairport-sync real (reemplazar proceso actual con exec)
exec /usr/bin/shairport-sync "$@"
EOFWRAPPER

# Reemplazar LMS_UNIT con valor detectado
sed -i.bak "s/LMS_UNIT=\"lyrionmusicserver.service\"/LMS_UNIT=\"${LMS_UNIT}\"/" "$TMP_WRAPPER" || true
sudo mv "$TMP_WRAPPER" "$WRAPPER_SCRIPT"
sudo chmod 755 "$WRAPPER_SCRIPT"  # FIX: cambiar a 755 para que sea legible y ejecutable
sudo chown root:root "$WRAPPER_SCRIPT"  # FIX: asegurar que pertenece a root

# Override del servicio systemd para usar el wrapper en lugar del binario directo
DROPIN_DIR="/etc/systemd/system/shairport-sync.service.d"
echo -e "${YELLOW}Creando override systemd para usar wrapper${NC}"
sudo mkdir -p "$DROPIN_DIR"
TMP_DROPIN="$(mktemp)"
cat > "$TMP_DROPIN" <<EOF
[Service]
# Limpiar ExecStart original y reemplazar con wrapper
ExecStart=
ExecStart=${WRAPPER_SCRIPT}
# Al parar shairport-sync, reiniciar LMS (con /bin/systemctl en lugar de sudo)
ExecStopPost=/bin/systemctl start ${LMS_UNIT}
ExecStopPost=/bin/sh -c 'if command -v alsactl >/dev/null 2>&1; then alsactl restore 2>/dev/null || true; fi'
# Reintentar si falla al arrancar (por si ALSA no se libera a tiempo)
Restart=on-failure
RestartSec=5s
StartLimitBurst=3
EOF
sudo mv "$TMP_DROPIN" "${DROPIN_DIR}/lyrion-bridge.conf"
sudo chmod 644 "${DROPIN_DIR}/lyrion-bridge.conf"

# Recargar systemd y (re)iniciar shairport-sync
sudo systemctl daemon-reload

# IMPORTANTE: parar el servicio antes de reiniciar para que use el wrapper
echo -e "${YELLOW}Parando shairport-sync existente (si está corriendo)...${NC}"
sudo systemctl stop shairport-sync.service 2>/dev/null || true
sleep 2

# Ahora sí, iniciar con el wrapper
echo -e "${YELLOW}Iniciando shairport-sync con wrapper...${NC}"
sudo systemctl enable shairport-sync.service
sudo systemctl start shairport-sync.service || true
sleep 3

if systemctl is-active --quiet shairport-sync.service; then
  echo -e "${GREEN}Shairport‑Sync activo y escuchando (AirPlay).${NC}"
else
  echo -e "${RED}No se pudo arrancar Shairport‑Sync. Revisa: sudo journalctl -u shairport-sync -n 200${NC}"
fi

echo -e "${GREEN}Instalación completada. Puntos importantes:${NC}"
echo "- /etc/shairport-sync.conf configurado para DAC: ${DAC_DEVICE} (mixer_enabled=no)"
echo "- Wrapper script creado: ${WRAPPER_SCRIPT}"
echo "- Systemd override: ${DROPIN_DIR}/lyrion-bridge.conf"
echo "- Al conectar AirPlay, el wrapper parará ${LMS_UNIT} automáticamente"
echo "- Al desconectar AirPlay, ${LMS_UNIT} se reiniciará automáticamente"
echo
echo -e "${YELLOW}Verificaciones recomendadas:${NC}"
echo "  sudo journalctl -u shairport-sync -f   # ver logs en tiempo real"
echo "  sudo journalctl -u ${LMS_UNIT} -f"
echo "  sudo fuser -v /dev/snd/*   # ver qué procesos usan el DAC"
echo "  aplay -l   # listar dispositivos"
echo
echo -e "${YELLOW}Para cambiar DAC: export DAC_DEVICE=\"plughw:1,0\" && bash scripts/install-shairport-sync.sh${NC}"