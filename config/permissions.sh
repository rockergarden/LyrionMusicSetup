#!/bin/bash

LMS_USER="lyrion"
MUSIC_DIRS=("/home/cristian/Disks/HDD3" "/home/cristian/Disks/HDD5")

echo "Configurando permisos para directorios de música..."

# Agregar usuario lyrion al grupo del usuario cristian
sudo usermod -a -G cristian $LMS_USER

# Configurar permisos para directorios de música
for dir in "${MUSIC_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "Configurando permisos para: $dir"
        # Dar permisos de lectura al grupo
        sudo chmod -R g+r "$dir"
        # Asegurar que los directorios tengan permisos de ejecución
        sudo find "$dir" -type d -exec chmod g+x {} \;
        # Crear archivo de configuración ACL si es necesario
        sudo setfacl -R -m g:$LMS_USER:r-x "$dir" 2>/dev/null || true
    else
        echo "Advertencia: El directorio $dir no existe"
    fi
done

# Configurar directorio de cache de LMS
sudo mkdir -p /var/lib/squeezeboxserver/cache
sudo chown -R $LMS_USER:$LMS_USER /var/lib/squeezeboxserver