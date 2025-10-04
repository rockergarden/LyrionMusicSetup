#!/bin/bash
set -euo pipefail

PLUGIN_DIR="/var/lib/squeezeboxserver/Plugins"
TMPDIR=$(mktemp -d)
CFG="config/lms-permissions.conf"
GIT_REPO="${GIT_REPO:-https://github.com/philippe44/LMS-Raop.git}"
QUIET=0

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

log() { echo "[airplay] $*"; }

# Cargar config y respetar LMS_USER exportado desde install.sh
if [ -f "$CFG" ]; then
  # shellcheck disable=SC1090
  source "$CFG"
fi

# Comprueba internet/DNS rápido
has_network() {
  # intenta resolver github, y ping a 1.1.1.1 como respaldo
  getent hosts github.com >/dev/null 2>&1 && return 0
  ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 && return 0
  return 1
}

# Determinar TARGET_USER: preferir variable exportada, luego systemd unit owner, luego common users
determine_target_user() {
  if [ -n "${LMS_USER:-}" ]; then
    echo "$LMS_USER"
    return
  fi

  for unit in logitechmediaserver lyrionmusicserver squeezeboxserver lyrion-music-service lyrion-music-server; do
    if systemctl list-unit-files | grep -qw "${unit}.service"; then
      u="$(systemctl show -p User --value "${unit}.service" 2>/dev/null || true)"
      if [ -n "$u" ]; then
        echo "$u"
        return
      fi
    fi
  done

  for u in squeezeboxserver squeezelite lyrion nobody; do
    if id -u "$u" >/dev/null 2>&1; then
      echo "$u"
      return
    fi
  done

  # fallback
  echo "root"
}

TARGET_USER="$(determine_target_user)"
log "Usuario objetivo para plugin: ${TARGET_USER}"

# Instala dependencias solo si hay red; no fallar si apt tiene problemas en sources
if has_network; then
  log "Red detectada: intentando instalar dependencias (avahi/unzip)..."
  sudo apt-get update -o Acquire::Retries=3 || log "apt update devolvió errores, se continúa de todos modos"
  sudo apt-get install -y avahi-daemon libavahi-compat-libdnssd1 unzip || true
  sudo systemctl enable --now avahi-daemon || true
else
  log "Sin conectividad de red detectada: se omite instalación de dependencias"
fi

log "Instalando plugin RAOP (LMS-Raop) en ${PLUGIN_DIR} ..."

cd "$TMPDIR"

# Si el plugin ya existe y es un repo git, hacer pull; si existe y no es git, hacer backup y reemplazar
if [ -d "${PLUGIN_DIR}/RAOP" ]; then
  if [ -d "${PLUGIN_DIR}/RAOP/.git" ]; then
    log "RAOP ya existe y es repo git: intentando git pull (como ${TARGET_USER})"
    sudo -u "$TARGET_USER" bash -c "cd '${PLUGIN_DIR}/RAOP' && git pull --ff-only" || log "git pull falló, se continuará"
    log "Actualización completada"
    exit 0
  else
    log "RAOP ya existe (no es git). Se hará copia de seguridad y se reemplazará si la descarga tiene éxito."
    sudo mv "${PLUGIN_DIR}/RAOP" "${PLUGIN_DIR}/RAOP.bak.$(date +%s)" || true
  fi
fi

# Intentar git clone si hay red y git disponible
CLONED=0
if has_network && command -v git >/dev/null 2>&1; then
  GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$GIT_REPO" raop 2>/dev/null && CLONED=1 || CLONED=0
fi

# Si no se clonó, intentar descargar zip (si hay red)
if [ "$CLONED" -eq 0 ] && has_network; then
  for branch in main master; do
    ZIPURL="${GIT_REPO%.git}/archive/refs/heads/${branch}.zip"
    if command -v curl >/dev/null 2>&1; then
      if curl -fsSL "$ZIPURL" -o plugin.zip; then
        if command -v unzip >/dev/null 2>&1; then
          unzip -q plugin.zip || true
          sub=$(find . -maxdepth 1 -type d -name "*LMS-Raop*" | head -n1 || true)
          if [ -n "$sub" ]; then mv "$sub" raop; fi
        else
          log "unzip no disponible, intentando tar (puede fallar)"
          mkdir -p unpack && tar -C unpack -xf plugin.zip 2>/dev/null || true
          sub=$(find unpack -maxdepth 1 -type d -name "*LMS-Raop*" | head -n1 || true)
          [ -n "$sub" ] && mv "unpack/$sub" raop
        fi
        break
      fi
    fi
  done
fi

if [ ! -d "raop" ]; then
  log "No se pudo obtener LMS-Raop (git/zip fallaron). Restaurando backup si existe y saliendo."
  if [ -d "${PLUGIN_DIR}/RAOP.bak"* ]; then
    log "Backup detectado. Manteniendo backup."
  fi
  exit 0
fi

# Instalar en Plugins/RAOP de forma idempotente
sudo mkdir -p "$PLUGIN_DIR"
sudo rsync -a --delete raop/ "$PLUGIN_DIR/RAOP/"
# Aplicar propietario seguro
if sudo chown -R "${TARGET_USER}:${TARGET_USER}" "$PLUGIN_DIR/RAOP" 2>/dev/null; then
  true
else
  sudo chown -R "${TARGET_USER}:nogroup" "$PLUGIN_DIR/RAOP" 2>/dev/null || true
fi
sudo chmod -R u+rwX,g+rX,o-rwx "$PLUGIN_DIR/RAOP"

# ufw: agregar reglas solo si está activo y no existen
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  if ! sudo ufw status numbered | grep -q "5353.*udp"; then
    sudo ufw allow 5353/udp || true
  fi
  if ! sudo ufw status numbered | grep -q "5000/tcp"; then
    sudo ufw allow 5000/tcp || true
  fi
fi

# Reiniciar avahi y las unidades LMS detectadas
sudo systemctl restart avahi-daemon || true
for u in logitechmediaserver lyrionmusicserver squeezeboxserver lyrion-music-server; do
  unit="${u}.service"
  sudo systemctl unmask "$unit" 2>/dev/null || true
  if systemctl list-unit-files | grep -qw "$unit"; then
    sudo systemctl restart "$unit" 2>/dev/null || sudo systemctl start "$unit" 2>/dev/null || true
  fi
done

log "Plugin RAOP instalado en ${PLUGIN_DIR}/RAOP"
sleep 2
if command -v avahi-browse >/dev/null 2>&1; then
  avahi-browse -a -t | egrep 'raop|_raop|AirPlay' || true
else
  log "avahi-browse no disponible: ejecutar 'avahi-browse -a -t' para comprobar anuncios mDNS"
fi

exit 0