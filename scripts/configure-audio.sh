#!/bin/bash

echo "Configurando audio para DAC USB..."

# Detectar DAC USB
echo "Dispositivos de audio disponibles:"
aplay -l

# Crear configuración para squeezelite
sudo tee /etc/default/squeezelite > /dev/null <<EOF
# Squeezelite configuration
SL_NAME="SqueezePlayer"
SL_SOUNDCARD="default:CARD=1"
SL_EXTRA_ARGS="-a 80:4::0 -b 500:2000 -C 5 -r 44100-192000"
EOF

# Configurar ALSA para DAC USB (asumiendo que es la tarjeta 1)
sudo tee /home/cristian/.asoundrc > /dev/null <<EOF
pcm.!default {
    type hw
    card 1
    device 0
}
ctl.!default {
    type hw
    card 1
}
EOF

# Agregar usuario lyrion al grupo audio
sudo usermod -a -G audio lyrion

echo "Configuración de audio completada"