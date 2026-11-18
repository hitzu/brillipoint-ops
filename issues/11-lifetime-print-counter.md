feat(print-server): lifetime print counter on the live panel

### Problem

El operador quiere ver en el panel inicial (En vivo, `/`) cuántas impresiones ha hecho la impresora "desde el inicio de los tiempos", sin abrir el historial evento por evento.

**Estado actual verificado** (print server, rama `feat/flow-remap-pr9`, 2026-11-09):

- El panel `/` solo muestra "Últimas impresiones" del evento activo, 3 tarjetas: `app/ui/templates/dashboard.html:200-211`, `app/ui/static/recent_prints.js:14`.
- No existe ningún contador acumulado, ni en la API ni en la UI. `GET /status` (`app/api/routes.py:850`) trae impresora, cola y sesión; `GET /jobs` (`app/api/routes.py:879`) es un listado paginado.
- CUPS no expone contadores: `CupsBridge.get_printer_status` (`app/cups/bridge.py:187-204`) documenta que el driver Gutenprint de la DNP no reporta niveles (el PPD no declara atributos marker/supply).
- La cola de la DNP RX1HS usa el backend de Gutenprint `dnpds40` (`tutorial-instalacion.md:162`: `gutenprint52+usb://…&backend=dnpds40`). Ese backend, ejecutado fuera de CUPS, tiene una consulta de contadores (`-n`) y un modo de estadísticas en JSON (`BACKEND_STATS_ONLY=2`); en una DS80 reporta `Lifetime Counter`. **No verificado en la RX1HS.** Fuentes: [gimp-print feature request 734](https://sourceforge.net/p/gimp-print/feature-requests/734), [launchpad bug 1297326](https://launchpad.net/ubuntu/+source/gutenprint/+bug/1297326/comments/14).
- CUPS corre en su propio contenedor privilegiado con el bus USB (`docker-compose.yml:2-23`, imagen `lionep/dnp-cups`); la app solo le habla por red (`CUPS_HOST`, `docker-compose.yml:35-36`). Hoy la app no tiene acceso directo al USB ni al binario del backend.
- Mientras imprime, el backend tiene el USB abierto y nadie más lo puede consultar (`app/cups/bridge.py:225-236`, `_presence_is_fresh`).

### Decisiones (2026-11-09)

1. **Se muestra el contador físico de la DNP.** "Desde el inicio de los tiempos" incluye lo impreso antes del BPS o desde otra máquina.
   - Descartado: contar desde la base local del BPS (jobs `DONE` × copias). Solo cubre lo que imprimió este servidor y vuelve a cero si la base se reinstala.

2. **La consulta corre en el contenedor `cups` y la app la pide por red a un servicio HTTP mínimo** (2026-11-09). El contenedor `cups` es el único con el USB y el backend `dnpds40`; la app (`bps`) solo le habla por red, igual que hoy con CUPS.
   - Descartado: montar `/var/run/docker.sock` en `bps` para hacer `docker exec`. Daría a la app control de todo el host Docker.
   - Descartado: darle a `bps` acceso al USB y al binario del backend. Dos procesos pelearían por el USB y rompería el límite actual entre contenedores.
   - Restricciones del servicio (no negociables):
     - Solo ejecuta la consulta `-n` (contadores) con `BACKEND=dnpds40`. No acepta argumentos del cliente ni expone `-N`, `-p`, `-k`, `-K`, `-x` (escriben en la impresora).
     - Un solo cálculo a la vez, con timeout; si el USB está ocupado o la consulta falla, responde un error claro (nunca un cero) y no reintenta en bucle.
     - El serial no se hardcodea (`CB2D5C208466` es el de la máquina de pruebas): se obtiene de la URI del dispositivo (`lpinfo -v`) o de configuración.
     - Solo accesible desde el propio host: el puerto se publica en `127.0.0.1:<puerto>` en `docker-compose.yml` (`bps` usa `network_mode: host` y llega por `localhost`) y no se abre a la red del evento.

### Evidencia en la RX1HS real (2026-11-09)

Dentro del contenedor `cups` (servicio `cups` de `docker-compose.yml`), con la cola libre. El backend se elige con la variable `BACKEND` y el serial con `-S`:

```bash
docker compose exec -T -e BACKEND=dnpds40 cups \
  /usr/lib/cups/backend/gutenprint52+usb -S CB2D5C208466 -n </dev/null
```

Salida (stderr, líneas `INFO:`; el exit code no se registró):

```
INFO: Lifetime Counter: '0000212'
INFO: A Counter: '0000199'
INFO: B Counter: '0000199'
INFO: P Counter: '0000000'
INFO: M Counter: '0000000'
INFO: Matte Counter: '0000000'
```

- Backend `dnpds40` versión 0.61.2 (multi-call 0.63G); URI de la cola: `gutenprint52+usb://Dai+Nippon+Printing/DS-RX1?serial=CB2D5C208466&backend=dnpds40`.
- La consulta es de solo lectura. `-s` (estado) e `-i` (info) también responden por el mismo camino: `Printer Status: 0 => Idle`, `Prints Remaining on Media: '500'`, firmware `DS-RX1 02.21`.
- **No usar** `-N` (borra un contador), `-p`, `-k`, `-K`, `-x`: escriben en la impresora.
- `BACKEND_STATS_ONLY=2` y `-n` sin `BACKEND=dnpds40` no devuelven contadores (probados): era el modo de la DS80, no el de la RX1HS.
- Sin la variable, el backend pide 5 o 6 argumentos de CUPS y, con argumentos de relleno, arranca un trabajo vacío ("Printing started"). Las consultas deben llevar `BACKEND=dnpds40`, `-S <serial>` y `</dev/null`.

### Hechos verificados de la imagen `lionep/dnp-cups` (2026-11-09)

Comprobado con `docker run --rm --entrypoint sh lionep/dnp-cups -c 'command -v …'`:

- Ubuntu 16.04.3 LTS (Xenial).
- Tiene `python3` (`/usr/bin/python3`, versión no registrada: Xenial trae 3.5, hay que comprobarla antes de usar f-strings o `asyncio.run`), `perl` y `curl`.
- **No tiene** `python` (sin el 3), `nc`, `socat` ni `busybox`.
- El servicio puede ser un script de `python3` con la biblioteca estándar (`http.server`) montado como volumen en `cups`, o una imagen derivada. La elección es de quien implementa, siempre dentro de las restricciones de la decisión 2.
- `docker-compose.yml`: `cups` publica `631:631` y es `privileged` con `/dev/bus/usb`; `bps` usa `network_mode: host` y `CUPS_HOST=localhost`.

### Contexto para quien implementa (sin Engram)

Este issue es la única fuente: la máquina que lo implemente no tiene la memoria (Engram) de quien lo planeó. Todo lo decidido, descartado y verificado está arriba. Lo no verificado está marcado como tal en *Open questions*.

### Proposal

Punto de partida:

- Leer el contador de por vida de la DNP con `-n` del backend `dnpds40` (comando exacto en *Evidencia*), a través del servicio de la decisión 2, y mostrarlo en una tarjeta "Impresiones totales" en el panel `/`.
- Consultarlo solo con la cola libre (al arrancar y después de cada `job_done`) y guardar el último valor leído con su hora, para mostrarlo mientras la impresora está ocupada o desconectada.
- Exponerlo como campo nuevo y aditivo en `GET /status`, o en un endpoint propio; el panel se actualiza por `/ws`, como "Últimas impresiones" (`recent_prints.js:15-18`).
- La impresora simulada (`app/cups/stub.py`) devuelve un contador de prueba para desarrollo.

### Acceptance criteria

- [ ] El panel `/` muestra "Impresiones totales" con el contador de por vida que reporta la DNP.
- [ ] El valor coincide con la consulta manual del backend contra la RX1HS real.
- [ ] Al terminar una impresión, el número se actualiza sin recargar en cuanto la impresora queda libre.
- [ ] Si la impresora no está conectada o no responde, se muestra el último valor conocido con su fecha (o "sin dato"), nunca un error ni un cero.
- [ ] Consultar el contador nunca bloquea, retrasa ni hace fallar un trabajo de impresión.
- [ ] Con la impresora simulada, el panel muestra un contador de prueba.
- [ ] El servicio de contadores solo puede ejecutar `-n` y solo es accesible desde `127.0.0.1` del host.

### Open questions

1. ~~**(Bloqueaba el plan)** Correr la consulta de contadores contra la RX1HS real.~~ **Resuelta 2026-11-09:** ver *Evidencia en la RX1HS real*.
2. ~~**(Cambiaba la arquitectura)** ¿Dónde corre la consulta?~~ **Resuelta 2026-11-09:** decisión 2 (servicio HTTP mínimo en el contenedor `cups`).
3. ¿Qué contador se muestra: `Lifetime Counter` o uno de los reseteables (`A`/`B`)? Los reseteables podrían servir para un total por evento.
4. ¿Se muestra también el total del evento activo junto al de por vida?
5. ¿Cómo cuenta la DNP una hoja 6×4 cortada en dos (cola `corte2`): 1 o 2 impresiones?

Relacionado: #13 (rediseño del historial).

### Affected repositories (hint)

brillipoint-print-server
