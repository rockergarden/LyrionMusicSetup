#!/bin/bash
set -e

PLUGIN_DIR="/var/lib/squeezeboxserver/Plugins"
TMPDIR=$(mktemp -d)
CFG="config/lms-permissions.conf"
LMS_USER="lyrion"

if [ -f "$CFG" ]; then
  # shellcheck disable=SC1091
  source "$CFG"
fi
: "${LMS_USER:=lyrion}"

echo "Instalando plugin AirPlay (si está disponible)..."

# Asegurar git
if ! command -v git &>/dev/null; then
  echo "git no está instalado. Instalando git..."
  sudo apt update && sudo apt install -y git
fi

cd "$TMPDIR"
# repo conocido de ejemplo (ajustar si quieres otro)
if git clone https://github.com/lms-community/lms-plugin-airplay.git airplay 2>/dev/null; then
  sudo mkdir -p "$PLUGIN_DIR"
  sudo rsync -a airplay/ "$PLUGIN_DIR/AirPlay/"
  sudo chown -R "$LMS_USER":"$LMS_USER" "$PLUGIN_DIR/AirPlay"
  # Reiniciar LMS si está instalado como servicio
  if systemctl list-unit-files | grep -qw logitechmediaserver.service; then
    sudo systemctl restart logitechmediaserver || true
  fi
  echo "Plugin AirPlay instalado en $PLUGIN_DIR/AirPlay"
else
  echo "No se pudo clonar repo AirPlay, omitiendo."
fi

cd - >/dev/null 2>&1 || true
rm -rf "$TMPDIR"