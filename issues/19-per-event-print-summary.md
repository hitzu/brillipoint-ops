feat(print-server): per-event print summary in sheets and single-copy reprints

### Problem

Queremos saber cuántas hojas imprime cada evento para medirlo contra otros datos del evento, empezando por los invitados (#15). Hoy solo existe el contador global de la DNP (#11): el BPS no muestra cuántas hojas imprimió un evento.

El BPS funciona sin internet, así que el staff copia ese total a mano en el backend (`events.print_count`, #15). El modal de borrado de #17 también muestra este resumen antes de borrar.

**Estado actual (verificado en el código, `brillipoint-print-server` en `main`, `3565b79`):**

- **Registros de impresión:**
  - Cada registro trae `event_id`, `session_id`, `reprint_of`, `cut` y `forced` (`app/templates/records.py:292-312`), pero no `copies`.
  - Se guardan en `storage/templates/prints/<YYYY-MM>.jsonl`, un archivo por mes que mezcla eventos (`app/templates/records.py:320-338`).
  - El registro se escribe al mandar el trabajo a CUPS.
- **Reimpresión:**
  - El Historial y "Impresiones recientes" reimprimen siempre 1 copia (`app/ui/static/history.js:156`, `app/ui/static/recent_prints.js:119`).
  - El modal de reimpresión del dashboard todavía tiene un campo "Copias" (`app/ui/templates/dashboard.html:311-320`, `app/ui/static/ws.js:1380-1398`).
  - Ese valor llega a `POST /jobs/{id}/reprint`, que acepta cualquier número desde 1 (`copies: Form(ge=1)`, `app/api/routes.py:963`), y se manda como `lp -o copies=` (`app/cups/bridge.py:324`).
- **Mini Book no escribe registro de impresión:**
  - `_run_job` solo llama a `record_print` cuando el trabajo trae `template_id`, y Mini Book lo deja en `None` (`app/mini_book/service.py:160-165`).
  - Queda como fila de `jobs` con `metadata.source = "mini_book"` (`app/mini_book/service.py:173`).
  - Su PDF tiene varias hojas, y el `page_count` de la composición (`app/mini_book/composer.py:37`) no se guarda.
- **Otros casos:**
  - El upsell "Con plantilla" es una sesión `upsell_<sha12>` con registros normales (`app/api/routes.py:430-445`).
  - Las impresiones de prueba de plantilla van con `event_id = None` (`app/templates/service.py:1726`).
- **Dónde encaja:** el Historial del evento en `/recovery` (`app/ui/templates/recovery.html:26-40`, `app/api/ui_routes.py:510-562`). Ya existe `GET /events/{event_id}/recent-prints` (`app/api/routes.py:357`).

### Proposal

Punto de partida; la planeación lo afina.

**Decisiones tomadas con el usuario (2026-11-10):**

- Un evento es el `event_id` que manda el photobooth y todo lo que pasa bajo él: recepción de fotos, impresión (automática o confirmada), upsell (una foto o un conjunto) y reimpresión.
- La unidad del conteo es la **hoja de la DNP**: un Mini Book de 4 hojas suma 4, y una hoja con corte 2×6 suma 1.
- Una reimpresión es siempre de 1 copia. Se quita el campo "Copias" del dashboard para prevenir errores y para que no parezca fácil sacar N copias. Así, cada registro de impresión es una hoja.
- Este trabajo se separó de #17 (2026-11-10): #17 queda para agrupar y borrar los archivos de cada evento.

**1. Resumen de impresiones por evento, en hojas.** Se muestra en el Historial del evento seleccionado:

| Categoría | Qué cuenta |
| --- | --- |
| Impresiones | Sesiones normales del evento, automáticas o confirmadas, incluidas las forzadas |
| Reimpresiones | Registros con `reprint_of` |
| Upsell "Con plantilla" | Sesiones `upsell_*` |
| Upsell Mini Book | Trabajos DNP de Mini Book terminados; hojas = páginas del PDF |
| **Total** | Suma de las cuatro |

- Ejemplo: 50 impresiones + 2 reimpresiones + 3 hojas de Mini Book + 1 "Con plantilla" = **56**.
- Para contar el Mini Book hay que guardar su `page_count` en el trabajo.
- Las impresiones de prueba (`event_id = None`) no cuentan.
- El conteo se expone en un solo lugar (una función y un endpoint), para que el modal de borrado de #17 lo reutilice.
- El conteo lee los registros a través de las funciones de `app/templates/records.py`, no directo de los archivos. Así, cuando #17 cambie dónde viven los registros, el conteo no se toca.

**2. Reimpresión de una sola copia.**

- Quitar el campo "Copias" del modal de reimpresión del dashboard.
- Que `POST /jobs/{id}/reprint` rechace `copies` distinto de 1, para que el conteo no dependa de la interfaz.

**Orden:** va antes de #17, que muestra este resumen en su modal de borrado. #15 lo necesita para tener el número que el staff captura. Es independiente de #18, y pueden ir en paralelo.

### Acceptance criteria

- **El resumen suma bien:**
  - Un evento con 50 impresiones, 2 reimpresiones, un Mini Book de 3 hojas y 1 impresión "Con plantilla" muestra esas cifras y un total de 56.
  - Una hoja con corte 2×6 suma 1.
  - Una impresión de prueba de plantilla no suma en ningún evento.
  - El resumen de un evento no cambia al imprimir en otro evento.
- **La reimpresión es de una copia:**
  - El modal de reimpresión del dashboard ya no muestra el campo "Copias" y reimprime 1 copia.
  - `POST /jobs/{id}/reprint` con `copies=2` se rechaza y no encola nada.
  - El Historial y "Impresiones recientes" siguen reimprimiendo igual que antes.
- Todo funciona sin conexión a internet.

### Open questions

1. Una reimpresión de una sesión upsell o de un Mini Book, ¿cuenta como reimpresión o como upsell? Propuesta: como reimpresión, y para el Mini Book con sus hojas.
2. ¿El endpoint rechaza `copies` distinto de 1, o basta con quitar el campo de la interfaz? Propuesta: rechazarlo. Es una ruta interna del panel, y así el conteo siempre cuadra.
3. Un Mini Book que falla a la mitad, ¿cuenta sus hojas? La propuesta solo cuenta trabajos terminados.

**Riesgos:**

- El registro de impresión se escribe al mandar el trabajo a CUPS, así que una hoja que se atasca después cuenta igual.

### Affected repositories (hint)

brillipoint-print-server
