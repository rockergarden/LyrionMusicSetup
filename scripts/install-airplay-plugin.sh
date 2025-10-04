#!/bin/bash
set -e
PLUGIN_DIR="/var/lib/squeezeboxserver/Plugins"
TMPDIR=$(mktemp -d)
LMS_USER="lyrion"

echo "Instalando plugin AirPlay (si está disponible)..."
cd "$TMPDIR"
if command -v git &>/dev/null; then
  git clone https://github.com/lms-community/lms-plugin-airplay.git airplay || true
  if [ -d "airplay" ]; then
    sudo mkdir -p "$PLUGIN_DIR"
    sudo rsync -a airplay/ "$PLUGIN_DIR/AirPlay/"
    sudo chown -R "$LMS_USER":"$LMS_USER" "$PLUGIN_DIR/AirPlay"
    sudo systemctl restart logitechmediaserver 2>/dev/null || true
    echo "Plugin AirPlay instalado en $PLUGIN_DIR/AirPlay"
  else
    echo "Repositorio AirPlay no disponible, omitiendo."
  fi
else
  echo "git no instalado. Instale git e intente de nuevo."
fi
rm -rf "$TMPDIR"