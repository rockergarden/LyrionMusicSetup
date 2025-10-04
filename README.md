LyrionMusicSetup - scripts para instalar/configurar LMS y Squeezelite en Ubuntu

Archivos principales:
- install.sh
- uninstall.sh (mejorado)
- scripts/setup-permissions.sh
- scripts/install-airplay-plugin.sh
- scripts/configure-audio.sh
- services/*.service
- config/*.conf

Uso:
1. Revisar config/lms-permissions.conf y config/squeezelite.conf
2. Hacer ejecutables: chmod +x scripts/*.sh install.sh uninstall.sh
3. Ejecutar instalación: ./install.sh
4. Desinstalar: ./uninstall.sh

Notas:
- Verificar que el DAC USB sea hw:1 (aplay -l)
- Los scripts usan el usuario 'lyrion'; ajusta si es necesario.