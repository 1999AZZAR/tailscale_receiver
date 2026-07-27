# Tailscale Receiver v3 (Go)

![Blotcat effortlessly catching files falling from a secure network portal into a neatly labeled target bucket](assets/blotcat-hero.jpg)
Un Receptor de Archivos de Tailscale enfocado en la estabilidad y la eficiencia de recursos. Esta versión reemplaza la implementación anterior basada en shell script para reducir la carga del sistema.

## Características Técnicas

![Blotcat peacefully meditating on top of a tiny, hyper-efficient, single-block engine representing the Go static binary](assets/blotcat-efficiency.jpg)
- **Eficiencia de Recursos**: Uso de memoria constante en el rango de ~2MB.
- **Fiabilidad**: Utiliza `signal.NotifyContext` para un manejo de terminación limpio.
- **Sondeo Optimizado**: Validación del estado de Tailscale a través de la API JSON antes de ejecutar la transferencia de archivos.
- **Binario Estático**: Distribución en forma de binario único sin dependencias de tiempo de ejecución externas.

## Instalación
1. Clonar el repositorio:
   ```bash
   git clone https://github.com/1999AZZAR/tailscale_receiver
   cd tailscale_receiver
   ```
2. Ejecutar el instalador:
   ```bash
   chmod +x install-go.sh
   ./install-go.sh
   ```
3. Activar el servicio:
   ```bash
   sudo systemctl enable --now tailscale-receive-go
   ```

## Configuración

![Blotcat checking a mailbox with a clipboard and a timer](assets/blotcat-polling.jpg)
La configuración se gestiona a través del archivo `/etc/default/tailscale-receive` con las siguientes variables:
- `TARGET_DIR`: Directorio de destino (por defecto: `~/Downloads/tailscale`).
- `TARGET_USER`: Usuario propietario de los archivos transferidos.
- `POLL_INTERVAL`: Intervalo de comprobación (por defecto: `15s`).
- `ARCHIVE_DAYS`: Retención de archivos antiguos en el directorio `archive/` (por defecto: `14`).

## Legado
La implementación basada en shell script ha sido movida al directorio `legacy/` como referencia.

---
Mantenido por Mema (Multi-Euristic Mind Automaton)
