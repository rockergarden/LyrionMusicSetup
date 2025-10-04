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

echo "Instalando dependencias para RAOP (avahi / compat)..."
sudo apt update -y || true
sudo apt install -y avahi-daemon libavahi-compat-libdnssd1 unzip || true

echo "Asegurando avahi-daemon activo..."
sudo systemctl enable --now avahi-daemon || true

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
          cd unpack || true
        fi
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
sudo chmod -R u+rwX,g+rX,o-rwx "$PLUGIN_DIR/RAOP"

# abrir puertos mDNS/RAOP si ufw está habilitado
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  echo "Abriendo puertos mDNS (5353/udp) y RAOP (5000/tcp) en ufw..."
  sudo ufw allow 5353/udp || true
  sudo ufw allow 5000/tcp || true
fi

# Reiniciar avahi y reiniciar cualquier unidad LMS conocida si existe
echo "Reiniciando avahi-daemon y servicios LMS para que detecten el plugin..."
sudo systemctl restart avahi-daemon || true

RESTART_UNITS=(lyrionmusicserver logitechmediaserver squeezeboxserver lyrion-music-server)
for u in "${RESTART_UNITS[@]}"; do
  unit="${u}.service"
  # Desmascarar antes para permitir restart
  sudo systemctl unmask "$unit" 2>/dev/null || true
  if systemctl list-unit-files | grep -qw "$unit"; then
    echo "Reiniciando $unit"
    sudo systemctl restart "$unit" 2>/dev/null || sudo systemctl start "$unit" 2>/dev/null || true
  else
    echo "Unidad $unit no encontrada, omitiendo."
  fi
done

echo "Plugin RAOP instalado en $PLUGIN_DIR/RAOP"
echo "Esperando 5s para que avahi anuncie servicios..."
sleep 5

# comprobaciones rápidas
echo "Comprobación rápida de anuncio mDNS (avahi-browse):"
if command -v avahi-browse >/dev/null 2>&1; then
  avahi-browse -a -t | egrep 'raop|_raop|AirPlay' || true
else
  echo "avahi-browse no disponible. Ejecuta: avahi-browse -a -t"
fi

cd - >/dev/null 2>&1 || true
rm -rf "$TMPDIR"