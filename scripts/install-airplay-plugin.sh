#!/bin/bash
set -e

PLUGIN_DIR="/var/lib/squeezeboxserver/Plugins"
TMPDIR=$(mktemp -d)
CFG="config/lms-permissions.conf"
LMS_USER="lyrion"
GIT_REPO="${GIT_REPO:-https://github.com/lms-community/lms-plugin-airplay.git}"

if [ -f "$CFG" ]; then
  # shellcheck disable=SC1091
  source "$CFG"
fi
: "${LMS_USER:=lyrion}"

echo "Instalando plugin AirPlay (si está disponible)..."
cd "$TMPDIR"

# Preferir git clone sin prompt (no interactive credentials)
if command -v git >/dev/null 2>&1; then
  echo "Intentando git clone (no-interactive)..."
  # evitar prompts por credenciales: si requiere auth fallará inmediatamente
  GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$GIT_REPO" airplay 2>/dev/null || true
fi

# si no hay directorio 'airplay', intentar descargar ZIP (main o master)
if [ ! -d "airplay" ]; then
  echo "git clone falló o no disponible. Intentando descargar ZIP desde GitHub..."
  for branch in main master; do
    ZIPURL="${GIT_REPO%.git}/archive/refs/heads/${branch}.zip"
    if command -v curl >/dev/null 2>&1; then
      if curl -fsSL "$ZIPURL" -o plugin.zip; then
        unzip -q plugin.zip || true
        # unzip crea directory like lms-plugin-airplay-main
        subdir=$(ls -d */ | grep -i lms-plugin-airplay | head -n1 | sed 's:/$::' || true)
        if [ -n "$subdir" ]; then
          mv "$subdir" airplay
        else
          # fallback: try any folder name created
          first=$(find . -maxdepth 1 -type d -name "*lms-plugin-airplay*" | head -n1 || true)
          if [ -n "$first" ]; then mv "$first" airplay; fi
        fi
        break
      fi
    fi
  done
fi

# si aún no hay plugin, abortar sin pedir credenciales
if [ ! -d "airplay" ]; then
  echo "No se pudo obtener el plugin AirPlay (git y descarga ZIP fallaron). Omitiendo."
  cd - >/dev/null 2>&1 || true
  rm -rf "$TMPDIR"
  exit 0
fi

sudo mkdir -p "$PLUGIN_DIR"
sudo rsync -a airplay/ "$PLUGIN_DIR/AirPlay/"
sudo chown -R "$LMS_USER":"$LMS_USER" "$PLUGIN_DIR/AirPlay"

# Reiniciar LMS si está instalado como servicio
if systemctl list-unit-files | grep -qw logitechmediaserver.service; then
  sudo systemctl restart logitechmediaserver || true
fi

echo "Plugin AirPlay instalado en $PLUGIN_DIR/AirPlay"

cd - >/dev/null 2>&1 || true
rm -rf "$TMPDIR"