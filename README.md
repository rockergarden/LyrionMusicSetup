# LyrionMusicSetup

Descripción
-----------
Colección de scripts para instalar y configurar Lyrion Music Server (LMS, fork de Logitech Media Server) y Squeezelite en Ubuntu. Automatiza:
- Instalación de LMS y Squeezelite.
- Configuración de permisos para las bibliotecas musicales en:
  - /home/cristian/Disks/HDD3
  - /home/cristian/Disks/HDD5
- Activación de un plugin de AirPlay.
- Configuración de salida de audio a un DAC USB.
- Creación de servicios systemd que se reinician automáticamente en caso de caída.

Para qué sirve (casos prácticos)
-------------------------------
- Servir una biblioteca musical centralizada desde varios discos.
- Reproducir en red con clientes Squeezebox y Squeezelite.
- Usar un DAC USB local conectado al servidor como salida de audio.
- Recibir audio desde dispositivos Apple vía AirPlay (vía plugin).
- Mantener LMS siempre activo en un servidor doméstico o RPi/miniPC con Ubuntu.

Antes de ejecutar
-----------------
1. Verifica que los discos estén montados y accesibles:
   - aplay -l (para identificar la tarjeta DAC)
   - ls -la /home/cristian/Disks/HDD3 /home/cristian/Disks/HDD5
2. Revisa y adapta:
   - config/lms-permissions.conf (usuario LMS, rutas)
   - config/squeezelite.conf (nombre y tarjeta de audio)
3. Ejecutables:
   - chmod +x install.sh uninstall.sh scripts/*.sh

Instalación rápida
------------------
1. Ejecutar (con tu usuario; los scripts usarán sudo cuando haga falta):
   ./install.sh
2. Acceder a la interfaz web de LMS:
   http://localhost:9000
3. Si usas el DAC USB, confirma la tarjeta (hw:X) y ajusta config/squeezelite.conf.

Desinstalación
--------------
- ./uninstall.sh
  El script intentará detener servicios, eliminar paquetes y el usuario `lyrion`. Conserva datos a menos que confirmes su eliminación.

Gestión de servicios
--------------------
- Ver estado:
  sudo systemctl status logitechmediaserver
  sudo systemctl status squeezelite
- Logs:
  sudo journalctl -u logitechmediaserver -f
  sudo journalctl -u squeezelite -f
- Reiniciar:
  sudo systemctl restart logitechmediaserver
  sudo systemctl restart squeezelite

Resolución de problemas (rápida)
-------------------------------
- LMS no inicia: revisar /var/log/squeezeboxserver y journalctl.
- Música no aparece: comprobar permisos y ACLs; volver a ejecutar scripts/setup-permissions.sh.
- DAC no es hw:1: ejecutar aplay -l y actualizar config/squeezelite.conf y ~/.asoundrc.
- Plugin AirPlay no funciona: verificar /var/lib/squeezeboxserver/Plugins y permisos (propietario `lyrion`).

Buenas prácticas
----------------
- Probar en una máquina de laboratorio antes de producción.
- Hacer backup de /var/lib/squeezeboxserver antes de cambios mayores.
- Revisar y adaptar los nombres de servicios si ya existen instancias previas de LMS.

Contribuir / Ajustes
--------------------
- Añadir/editar servicios en services/
- Ajustar scripts en scripts/
- Actualizar variables en config/*.conf

Licencia y notas
----------------
- Scripts para uso personal. Revisar y adaptar permisos y rutas a tu entorno.