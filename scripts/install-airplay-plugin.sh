#!/bin/bash
set -e

PLUGIN_DIR="/var/lib/squeezeboxserver/Plugins"
TMPDIR=$(mktemp -d)
CFG="config/lms-permissions.conf"
LMS_USER="lyrion"
# usar el plugin recomendado por lyrion.org
GIT_REPO="${GIT_REPO:-https://github.com/philippe44/LMS-Raop.git}"

if [ -f "$CFG" ]; then
  # shellcheck disable=SC1091
  source "$CFG"
fi
: "${LMS_USER:=lyrion}"

echo "Instalando plugin RAOP (LMS-Raop) ..."

cd "$TMPDIR"

# intentar git clone sin prompts
if command -v git >/dev/null 2>&1; then
  echo "Intentando git clone (no-interactive)..."
  GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$GIT_REPO" raop 2>/dev/null || true
fi

# si no hay directorio 'raop', intentar descargar ZIP (main o master)
if [ ! -d "raop" ]; then
  echo "git clone falló o no disponible. Intentando descargar ZIP desde GitHub..."
  for branch in main master; do
    ZIPURL="${GIT_REPO%.git}/archive/refs/heads/${branch}.zip"
    if command -v curl >/dev/null 2>&1; then
      if curl -fsSL "$ZIPURL" -o plugin.zip; then
        if command -v unzip >/dev/null 2>&1; then
          unzip -q plugin.zip || true
        else
          mkdir -p unpack && tar -C unpack -xf plugin.zip 2>/dev/null || true
        fi
        # detectar subdir creado por unzip
        subdir=$(ls -d */ | grep -i 'LMS-Raop' | head -n1 | sed 's:/$::' || true)
        if [ -n "$subdir" ]; then
          mv "$subdir" raop
        else
          first=$(find . -maxdepth 1 -type d -name "*LMS-Raop*" | head -n1 || true)
          if [ -n "$first" ]; then mv "$first" raop; fi
        fi
        break
      fi
    fi
  done
fi

# si aún no hay plugin, abortar sin pedir credenciales
if [ ! -d "raop" ]; then
  echo "No se pudo obtener LMS-Raop (git y descarga ZIP fallaron). Omitiendo."
  cd - >/dev/null 2>&1 || true
  rm -rf "$TMPDIR"
  exit 0
fi

# instalar en Plugins/RAOP (idempotente)
sudo mkdir -p "$PLUGIN_DIR"
sudo rsync -a raop/ "$PLUGIN_DIR/RAOP/"
sudo chown -R "$LMS_USER":"$LMS_USER" "$PLUGIN_DIR/RAOP"

# Reiniciar cualquier unidad LMS conocida si existe
RESTART_UNITS=(logitechmediaserver squeezeboxserver lyrion-music-server)
for u in "${RESTART_UNITS[@]}"; do
  unit="${u}.service"
  if systemctl list-unit-files | grep -qw "$unit"; then
    echo "Reiniciando $unit"
    sudo systemctl restart "$unit" || true
  fi
done

echo "Plugin RAOP instalado en $PLUGIN_DIR/RAOP"

cd - >/dev/null 2>&1 || true
rm -rf "$TMPDIR"