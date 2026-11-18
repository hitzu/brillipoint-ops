feat(print-server): group each event's files in one folder, reconcile orphans and delete events

### Problem

Cada evento deja en el print server (BPS) fotos, sesiones, renders y PDFs que se acumulan. Cuando el evento termina ya no sirven: el photobooth (iPad) guarda su propia copia, así que una sesión se puede volver a imprimir desde ahí.

Hoy no hay forma de borrar un evento. Además, sus archivos están repartidos en carpetas compartidas con los demás eventos: para borrar uno hay que averiguar archivo por archivo quién más lo usa, y lo que nadie referencia (vistas previas, carpetas legacy) se queda para siempre.

**Estado actual (verificado en el código, `brillipoint-print-server` en `main`, `3565b79`):**

- **No hay tabla de eventos ni carpeta por evento.** Un evento es la fila de `sessions` con id `event_{id}`, que crea el `POST /session` del iPad (`app/api/routes.py:189-294`), más las `template_sessions` agrupadas por `event_id` (`TemplateStore.list_events`, `app/templates/store.py:621-654`).
- **Una sola base:** `storage/jobs.db` (WAL), compartida por la cola y `TemplateStore`. El DDL está en `app/queue/store.py:17-365`. Hay llaves foráneas declaradas, pero `PRAGMA foreign_keys` nunca se activa y no hay `ON DELETE`: nada se borra en cascada.
  - Con `event_id`: `sessions`, `jobs`, `template_sessions`, `local_sessions`, `event_print_policy_heads`/`revisions`/`items`, `photobooth_audit`, `restart_history`, `reception_events`. Legacy sin escritores: `reception_photos`, `reception_batches`, `bps_sessions.external_event_id`.
  - Por sesión o trabajo: `template_captures`, `template_renders`, `session_authorizations`, `session_action_requests`, `authorization_templates`, `dispatch_intents`, `work_provenance`.
- **Archivos repartidos en carpetas compartidas** (todo bajo `storage/`):
  - Capturas guardadas por contenido: `templates/captures/<sha256>.jpg` (`app/templates/service.py:2666-2667`). Un archivo que ya existe se reutiliza (`app/templates/service.py:2000-2005`), y el upsell "Con plantilla" crea filas nuevas que apuntan al mismo archivo. Varias sesiones pueden compartir una captura.
  - Renders por sesión: `templates/renders/<session_id>/` (`app/templates/service.py:2315`).
  - Reimpresiones: `templates/renders/reprints/<uuid>.png` (`app/templates/service.py:2621`). Solo las enlaza el `original_path` del trabajo.
  - Vistas previas "Con plantilla": `templates/renders/previews/<uuid>.png`, `.json` y `<uuid>-fillers/` (`app/templates/service.py:1548-1549`, `app/api/template_routes.py:235`), sin enlace en la base.
  - PDFs del Mini Book: `mini_book/dnp-<event_id>-<ts>.pdf` (`app/mini_book/service.py:171-176`).
  - Registros de impresión: `templates/prints/<YYYY-MM>.jsonl`, un archivo por mes que mezcla eventos (`app/templates/records.py:320-338`). Los leen `index_print_record_job_ids` y `find_record_by_job_id`, que recorren todos los archivos del mes (`app/templates/records.py:342-385`), la reimpresión y la conciliación de registros faltantes al arrancar (`reconcile_missing_print_records`, `app/templates/service.py:2493`, llamada desde `app/main.py:238`).
  - No son de un evento: impresiones de prueba en `templates/renders/test_prints/` (`app/templates/service.py:1691`) y renders del catálogo en `templates/renders/catalog/<template_id>/` (`app/templates/service.py:761`).
  - Carpetas legacy sin escritores: `originals/`, `previews/`, `processed/`, `reception/`.
- **No existe ningún borrado ni purga** de eventos, sesiones, trabajos o archivos. `templates.records_retention_months: 24` está declarado (`app/core/config.py:185`), pero nadie lo lee.
- **Dónde encaja:** el selector de "Historial del evento" en `/recovery` (`app/ui/templates/recovery.html:26-40`, `app/api/ui_routes.py:510-562`). Las rutas vecinas de la API son `GET /events` y `/events/{event_id}/...` (`app/api/routes.py:317-517`).

### Proposal

Punto de partida; la planeación lo afina.

**Decisiones tomadas con el usuario (2026-11-10):**

- El BPS funciona 100% sin internet: no se conecta al backend y el iPad no participa en el borrado. El resguardo antes de borrar es una persona del staff.
- Limpieza inicial de una sola vez: los eventos que existen hoy se borran sin resumen ni respaldo.
- **Alcance de este issue:** conciliar los eventos, borrar las carpetas que nadie referencia, un botón o comando de limpieza total, y agrupar los archivos de cada evento para que sea fácil borrarlos.
- **Se separó a otros issues:** el resumen de hojas y la reimpresión de 1 copia pasan a #19; el evento abierto/cerrado, el estado vacío y la confirmación al cambiar de evento pasan a #18.

**1. Una carpeta por evento.** Todo lo que genera un evento vive en `storage/events/<event_id>/`:

| Subcarpeta o archivo | Qué guarda |
| --- | --- |
| `captures/<sha256>.jpg` | Capturas del evento |
| `renders/<session_id>/` | Renders por sesión |
| `reprints/<uuid>.png` | Reimpresiones |
| `mini_book/*.pdf` | PDFs del Mini Book |
| `prints.jsonl` | Registros de impresión del evento |

- Las capturas se reutilizan dentro del evento, como hoy (el upsell "Con plantilla" sigue apuntando al mismo archivo). Entre eventos ya no se comparten.
- Los registros de impresión pasan de un archivo por mes a uno por evento. Cambian sus lectores: la búsqueda de la reimpresión, `index_print_record_job_ids` y la conciliación al arrancar.
- Con esto, borrar un evento ya no obliga a reescribir archivos de registros compartidos con otros eventos.
- Lo que no es de un evento se queda fuera: plantillas, bundles, `templates/renders/catalog/`, impresiones de prueba y configuración.
- **No hay migración:** la limpieza inicial borra los eventos de hoy, así que la estructura nueva arranca vacía.

**2. Conciliación de eventos.** Compara la base con el disco:

- Una carpeta en `storage/events/` sin evento en la base es huérfana.
- Fuera de `storage/events/`, también son huérfanas las carpetas legacy (`originals/`, `previews/`, `processed/`, `reception/`), las capturas y renders con la estructura vieja y las vistas previas sin evento.
- Primero muestra qué va a borrar (lista y tamaño) y borra al confirmar.

**3. Borrar un evento cerrado desde el Historial.**

- El botón "Borrar evento" abre un modal con:
  - El resumen de hojas del evento (#19).
  - El recordatorio: "Captura el total (56 hojas) en el evento del backend antes de borrar".
  - Un check "Ya actualicé el evento", que habilita el botón de borrar.
- Se rechaza el borrado si:
  - El evento está abierto (#18).
  - Tiene trabajos en `queued`, `processing` o `printing`.
- Se borra:
  - Las filas de todas las tablas con ese `event_id`, más las que cuelgan de sus sesiones y trabajos.
  - La carpeta `storage/events/<event_id>/`.
- No se toca: plantillas y bundles, configuración, contador de la DNP ni la cola de CUPS.

**4. Limpieza total.**

- Borra todos los eventos cerrados con el mismo borrado del punto 3, y después corre la conciliación.
- La primera vez, borra todos los eventos que existen hoy y sus archivos con la estructura vieja, sin resumen.
- Se borran filas, nunca el archivo `jobs.db`, porque ahí también vive el estado de las plantillas.

**Orden:** va después de #18 (saber qué evento está abierto) y de #19 (el resumen del modal).

### Acceptance criteria

- **Agrupación:**
  - Las capturas, renders, reimpresiones, PDFs del Mini Book y registros de impresión de un evento nuevo quedan bajo `storage/events/<event_id>/`.
  - El upsell "Con plantilla" reutiliza la captura del evento sin duplicarla.
  - La reimpresión desde el Historial y desde "Impresiones recientes" sigue funcionando.
  - La conciliación de registros faltantes al arrancar sigue reconstruyendo un registro que falta.
- **Conciliación:**
  - Una carpeta de evento sin fila en la base aparece en la lista y se borra al confirmar.
  - Las carpetas legacy y las vistas previas sin evento se borran.
  - Plantillas, bundles, el catálogo de renders y la configuración quedan intactos.
- **El modal protege el borrado:** muestra el resumen y el recordatorio, y el botón de borrar está deshabilitado hasta marcar "Ya actualicé el evento".
- **Los rechazos funcionan:**
  - Borrar el evento abierto se rechaza con un mensaje claro.
  - Borrar un evento con un trabajo en cola o imprimiéndose se rechaza con un mensaje claro.
  - En ambos casos no se borra nada.
- **Después de borrar un evento:**
  - El evento no aparece en el selector del Historial.
  - No queda ninguna fila con su `event_id` ni de sus sesiones o trabajos.
  - No queda su carpeta `storage/events/<event_id>/`.
  - Otro evento conserva su resumen, su historial y su reimpresión, sin cambios.
- **La limpieza total deja el BPS sin eventos cerrados** y con las plantillas publicadas. La siguiente conexión del iPad crea su evento normalmente.
- Todo el flujo funciona sin conexión a internet.

### Open questions

1. ¿Borrar evento por evento desde el Historial, limpieza total de todos los eventos cerrados, o las dos? Propuesta: las dos; la total reutiliza el borrado por evento.
2. **Limpieza total:** ¿botón en el panel, comando con el servidor detenido, o los dos?
3. ¿Dónde viven los registros y renders de las impresiones de prueba (`event_id = None`)? Propuesta: fuera de `storage/events/`, como hoy.
4. **Vistas previas "Con plantilla":** ¿se guardan en la carpeta del evento, o son temporales y la conciliación las borra?
5. Las tablas legacy (`reception_*`, `bps_sessions`) tienen el comentario "Never DROP or rename them". La propuesta es borrar sus filas y conservar las tablas; falta confirmarlo.
6. ¿El `event_id` que manda el photobooth es el `id` del evento en `bookandsign-api`? Si lo es, el modal puede decir "Evento #<id>" para encontrarlo en "Editar evento" del front.

**Riesgos:**

- Cambiar las rutas toca la reimpresión, recovery, Mini Book y la conciliación al arrancar. Un lector que siga buscando en la ruta vieja no encuentra el archivo; cada uno necesita una prueba.

### Affected repositories (hint)

brillipoint-print-server
