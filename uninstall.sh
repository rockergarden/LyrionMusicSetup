#!/bin/bash
set -e

# Improved, idempotent uninstall that removes services, packages, configs and optional data.
# Usage:
#   ./uninstall.sh        -> interactive (asks to remove data)
#   ./uninstall.sh -y     -> non-interactive, remove everything
#   ./uninstall.sh --keep-data -> uninstall software but keep /var/lib & /var/log data

YES=false
KEEP_DATA=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) YES=true; shift ;;
    --keep-data) KEEP_DATA=true; shift ;;
    -h|--help)
      cat <<EOF
Usage: $0 [-y|--yes] [--keep-data]
  -y, --yes       non-interactive: confirm all removals
  --keep-data     keep /var/lib/squeezeboxserver and /var/log/squeezeboxserver
EOF
      exit 0
      ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo "Iniciando desinstalación completa de Lyrion Music Server y Squeezelite..."

# Load config if present to know LMS_USER and HOST_USER
if [ -f "config/lms-permissions.conf" ]; then
  # shellcheck disable=SC1091
  source "config/lms-permissions.conf"
fi
LMS_USER=${LMS_USER:-lyrion}
HOST_USER=${HOST_USER:-$(logname 2>/dev/null || echo "$SUDO_USER" || echo "$USER")}

# What will be removed
echo
echo "Elementos que se eliminarán:"
echo "- Servicios systemd relacionados: logitechmediaserver, lyrion-music-server, lyrion-music-service, squeezelite"
echo "- Paquetes: logitechmediaserver (si existe), squeezelite (si existe)"
echo "- Archivos de configuración: /etc/asound.conf, /etc/default/squeezelite"
echo "- Plugins: /var/lib/squeezeboxserver/Plugins"
echo "- Directorios de datos: /var/lib/squeezeboxserver, /var/log/squeezeboxserver (salvo --keep-data)"
echo "- Usuario del sistema: ${LMS_USER}"
echo "- Archivos de configuración locales creados por este repo (si existen): /etc/systemd/system/* (servicios copiados), /etc/asound.conf, /home/${HOST_USER}/.asoundrc"
echo

if ! $YES ; then
  read -p "Continuar y eliminar lo anterior? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Abortando desinstalación."
    exit 0
  fi
fi

# Stop, disable, unmask and remove unit files
SERVICES=(logitechmediaserver lyrion-music-server lyrion-music-service squeezelite logitechmediaserver.service)
for svc in "${SERVICES[@]}"; do
  svcname="${svc}"
  # normalize to .service
  [[ "$svcname" != *.service ]] && svcname="${svcname}.service"
  if systemctl list-unit-files | grep -qw "${svcname}"; then
    echo "Stopping ${svcname}..."
    sudo systemctl stop "${svcname}" 2>/dev/null || true
    sudo systemctl disable "${svcname}" 2>/dev/null || true
    sudo systemctl mask "${svcname}" 2>/dev/null || true
  fi
  # remove any local unit files we might have installed
  for path in "/etc/systemd/system/${svcname}" "/lib/systemd/system/${svcname}" "/usr/lib/systemd/system/${svcname}"; do
    if [ -f "${path}" ]; then
      echo "Removing unit file ${path}"
      sudo rm -f "${path}" || true
    fi
  done
done

sudo systemctl daemon-reload || true

# Remove packages if installed
PKGS=(logitechmediaserver squeezelite)
for pkg in "${PKGS[@]}"; do
  if dpkg -l 2>/dev/null | grep -qw "${pkg}"; then
    echo "Purging package: ${pkg}"
    sudo apt-get remove --purge -y "${pkg}" || true
    sudo apt-get autoremove -y || true
  else
    echo "Package ${pkg} not installed, skipping."
  fi
done

# Remove default files
FILES_TO_REMOVE=(/etc/asound.conf /etc/default/squeezelite)
for f in "${FILES_TO_REMOVE[@]}"; do
  if [ -f "$f" ]; then
    echo "Removing $f"
    sudo rm -f "$f" || true
  fi
done

# Remove project-installed unit files directory entries (if any)
if [ -d "/etc/systemd/system" ]; then
  # remove any unit files we may have created with known prefixes
  sudo find /etc/systemd/system -maxdepth 1 -type f \( -name "logitechmediaserver*.service" -o -name "lyrion-*.service" -o -name "squeezelite*.service" \) -exec rm -f {} \; || true
fi
sudo systemctl daemon-reload || true

# Remove plugins and runtime dirs
if [ -d /var/lib/squeezeboxserver ]; then
  if $KEEP_DATA ; then
    echo "Preservando datos en /var/lib/squeezeboxserver y /var/log/squeezeboxserver (--keep-data)"
  else
    echo "Removing /var/lib/squeezeboxserver and /var/log/squeezeboxserver"
    sudo rm -rf /var/lib/squeezeboxserver || true
    sudo rm -rf /var/log/squeezeboxserver || true
  fi
fi

# Remove plugin dir explicitly if present and not keeping data
if [ -d /var/lib/squeezeboxserver/Plugins ] && ! $KEEP_DATA ; then
  echo "Removing Plugins directory"
  sudo rm -rf /var/lib/squeezeboxserver/Plugins || true
fi

# Remove users and home created for LMS_USER
if id "${LMS_USER}" &>/dev/null; then
  echo "Removing user ${LMS_USER} and its home (if present)..."
  sudo userdel -r "${LMS_USER}" 2>/dev/null || true
else
  echo "User ${LMS_USER} not present, skipping userdel."
fi

# Remove potential repo-installed files inside /usr/local or /opt
CANDIDATES=(/opt/lyrion /opt/Logitech /usr/local/bin/squeezelite /usr/local/bin/logitechmediaserver)
for c in "${CANDIDATES[@]}"; do
  if [ -e "$c" ]; then
    echo "Removing $c"
    sudo rm -rf "$c" || true
  fi
done

# Remove local asoundrc for host user if ours
ASOUNDRC="/home/${HOST_USER}/.asoundrc"
if [ -f "$ASOUNDRC" ]; then
  echo "Removing $ASOUNDRC"
  sudo rm -f "$ASOUNDRC" || true
fi

# Remove project-installed /etc/default/squeezelite backup if any
if [ -f "/etc/default/squeezelite.bak" ]; then
  sudo rm -f /etc/default/squeezelite.bak || true
fi

# Final cleanup
sudo systemctl daemon-reload || true
sudo apt-get update -y || true

echo
echo "Desinstalación básica completada."

if $KEEP_DATA ; then
  echo "Nota: se preservaron los datos de /var/lib/squeezeboxserver y /var/log/squeezeboxserver."
else
  echo "Se eliminaron datos y configuraciones para permitir una reinstalación desde cero."
fi

echo "Puedes ahora volver a ejecutar ./install.sh para una instalación limpia."

# Forzar parada/limpieza adicional (procesos huérfanos y /etc/init.d)
echo "Forzando parada de procesos residuales y limpieza extra..."

# Parar y deshabilitar cualquier unidad conocida
KNOWN_UNITS=(logitechmediaserver squeezelite squeezeboxserver lyrion-music-server lyrion-music-service)
for u in "${KNOWN_UNITS[@]}"; do
  unit="${u}.service"
  sudo systemctl stop "${unit}" 2>/dev/null || true
  sudo systemctl disable "${unit}" 2>/dev/null || true
  sudo systemctl mask "${unit}" 2>/dev/null || true
  for path in "/etc/systemd/system/${unit}" "/lib/systemd/system/${unit}" "/usr/lib/systemd/system/${unit}"; do
    if [ -f "$path" ]; then
      echo "Removing unit file $path"
      sudo rm -f "$path" || true
    fi
  done
done
sudo systemctl daemon-reload || true

# Remove SysV init script if present
if [ -f /etc/init.d/squeezeboxserver ]; then
  echo "Removing /etc/init.d/squeezeboxserver"
  sudo /etc/init.d/squeezeboxserver stop 2>/dev/null || true
  sudo rm -f /etc/init.d/squeezeboxserver || true
fi
sudo rm -f /etc/default/squeezeboxserver 2>/dev/null || true

# Kill any remaining LMS-related processes (safe filters)
PATTERNS='squeezebox|slimserver|logitechmediaserver|server.pl|squeezelite'
pids="$(pgrep -f "$PATTERNS" || true)"
if [ -n "$pids" ]; then
  echo "Matando procesos encontrados: $pids"
  sudo pkill -f "$PATTERNS" || true
  sleep 1
  pids2="$(pgrep -f "$PATTERNS" || true)"
  if [ -n "$pids2" ]; then
    echo "Forzando kill -9: $pids2"
    sudo kill -9 $pids2 || true
  fi
fi

# remove leftover sockets/files that may keep service alive
sudo find /run -maxdepth 1 -type s -name '*squeez*' -exec rm -f {} \; 2>/dev/null || true
sudo find /tmp -maxdepth 1 -type s -name '*squeeze*' -exec rm -f {} \; 2>/dev/null || true