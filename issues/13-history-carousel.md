feat(print-server): history with a per-session carousel and one-click reprint

### Problem

El Historial del evento (`/recovery`) quedó atrasado. Sigue cargando acciones que ya se fueron a la pantalla Upsell (selección con checkboxes y la barra "Con plantilla" / "Por tamaño"), y sus miniaturas son chicas: cuando un invitado pide su foto, al operador le cuesta reconocer a las personas para encontrar la impresión correcta y reimprimirla.

**Estado actual verificado** (print server, rama `feat/flow-remap-pr9`, 57 commits por delante de `main`, sin mergear; 2026-11-09):

- Una tarjeta por sesión con dos grupos: "Impresiones" (el template armado, `app/ui/templates/recovery.html:99-136`) y debajo "Fotos" (las capturas, `recovery.html:138-166`). Cada elemento tiene un checkbox `data-history-select`.
- Barra fija de acciones sobre la selección: "Reimprimir igual", "Con plantilla", "Por tamaño", "Quitar selección" (`recovery.html:174-182`), con los modales "Por tamaño" (`recovery.html:189-225`, `app/ui/static/history_size.js`) y "Con plantilla" (`recovery.html:227-252`, `app/ui/static/history_template.js`).
- Upsell (`/mini-book`, `app/ui/templates/mini_book.html`) ya cubre "Por tamaño" y "Por template" (`odd/tasks/panel-v2.md`, S5 y P4).
- La reimpresión por impresión ya existe: botón `data-history-reprint-row` (`recovery.html:129-131`, `app/ui/static/history.js:430`) → `POST /jobs/{job_id}/reprint` (`app/api/routes.py:958`).
- El modal que muestra la imagen seleccionada existe: `#recovery-preview-modal` (`recovery.html:254`), abierto por `data-recovery-original-trigger`.
- Miniaturas: `.event-history-thumb` en rejilla, `object-fit: contain` (`app/ui/static/style.css:2321-2333`).
- Datos: `project_recovery` (`app/dashboard/recovery.py:477`) ya entrega por sesión `prints` (`preview_url`, `reprint_job_id`) y `captures` (`url`). El carrusel no debería necesitar datos nuevos del backend.

### Proposal

Punto de partida:

- **Un registro (tarjeta) por template armado**, no por sesión: cada uno con su propio botón "Reimprimir". Así, cuando llega la persona con su tira y pide una copia de ese template, el operador encuentra su registro y reimprime (ver **Decisiones**).
- Cada tarjeta muestra un **carrusel grande**: primero el template de esa tarjeta, después Foto 1 y Foto 2 de la sesión. Las fotos se repiten en las tarjetas de una misma sesión para reutilizar el mismo componente.
- **Las sesiones se acomodan en una rejilla responsiva**, una junto a la otra, que se ajusta sola al ancho de pantalla (hoy `.event-history-sessions` es de una sola columna, `app/ui/static/style.css:2272`, y cada tarjeta ocupa todo el ancho con miniaturas chicas). Cada tarjeta crece y el carrusel ocupa casi todo su ancho.
- **Quitar la rejilla "Fotos"** que hoy aparece debajo de cada sesión; esas fotos pasan al carrusel.
- **Botón de reimpresión rápida** visible en la tarjeta, reutilizando `POST /jobs/{job_id}/reprint`, con la confirmación en línea que ya existe ("Sí, reimprimir") para evitar reimpresiones por un toque accidental.
- **Mantener el modal** que muestra la imagen seleccionada al tocar una diapositiva.
- **Quitar del historial toda la selección y operaciones sobre fotos**, porque esa funcionalidad se fue a Upsell: checkboxes, barra de acciones (incluido "Reimprimir igual" en lote) y los modales "Con plantilla" y "Por tamaño". El historial queda como consulta + reimpresión por template.
- Filtros de ventana y orden, y el selector de evento, se quedan como están.

### Acceptance criteria

- [ ] Cada sesión muestra un carrusel con sus capturas y su template armado, con imágenes claramente más grandes que hoy, de forma que se reconozcan las caras.
- [ ] Las sesiones se muestran en varias columnas, una junto a la otra, y el número de columnas se ajusta solo al ancho de pantalla, sin espacio muerto entre sesiones.
- [ ] Cada template armado genera su propio registro con su botón "Reimprimir"; una sesión con N templates muestra N registros.
- [ ] La primera diapositiva de cada carrusel es el template de ese registro; después van las fotos de la sesión (repetidas entre los registros de la misma sesión).
- [ ] Debajo de cada sesión ya no aparece la rejilla "Fotos".
- [ ] "Reimprimir" pide una confirmación en línea ("Sí, reimprimir") y, al confirmar, encola 1 copia de esa impresión y lo indica en la tarjeta ("En cola"); no hay botón cuando no hay `reprint_job_id`.
- [ ] Tocar una diapositiva abre el modal con esa imagen, como hoy.
- [ ] El historial ya no ofrece selección de fotos ni operaciones sobre ellas ("Reimprimir igual" en lote, "Con plantilla", "Por tamaño"); siguen disponibles en Upsell las que ya viven ahí.
- [ ] Filtros de ventana/orden y selector de evento siguen funcionando.
- [ ] El carrusel se puede deslizar con el dedo en la tablet del operador.

### Open questions

Ninguna. Todas se resolvieron en **Decisiones**.

### Decisiones

- 2026-11-09 — **Orden del carrusel:** primero el template armado, después las fotos de la sesión (Foto 1, Foto 2). Descartado: template al final. Razón: el template es lo que se reimprime y es lo que el operador busca primero.
- 2026-11-09 — **Layout:** las sesiones van una junto a la otra en una rejilla que se ajusta sola al ancho de pantalla. Descartado: número fijo de columnas (p. ej. 2). Razón: hoy se desperdicia mucho espacio entre sesión y sesión; el objetivo es agrandar cada sesión y ver más imágenes a la vez.
- 2026-11-09 — **Un registro por template (fan-out):** cada template armado genera su propia tarjeta con su "Reimprimir", porque en el evento la persona llega con su tira y pide copia de ese template. Las fotos de la sesión se repiten en cada tarjeta para reutilizar el mismo componente de carrusel. Descartado: una tarjeta por sesión con varios botones; fotos una sola vez por sesión. Verificado: `project_recovery` ya entrega `prints` por render y una lista plana `cards` por salida (`app/dashboard/recovery.py:16`, `:335-337`), sin datos nuevos.
- 2026-11-09 — **Se quita toda la selección y operaciones sobre fotos** (incluido "Reimprimir igual" en lote). Razón: esa funcionalidad se fue a Upsell.
- 2026-11-09 — **Reimpresión rápida = siempre 1 copia**, sin preguntar cuántas (como "Últimas impresiones", `app/ui/static/recent_prints.js:119`). Descartado: selector de copias y reimpresión en lote. Razón: la impresión en lote está en prueba, no hay un caso de uso que la pida y cada impresión cuesta.
- 2026-11-09 — **Base de trabajo:** se implementa sobre `feat/flow-remap-pr9` (no espera a que llegue a `main`), porque sigue siendo parte del reflow. Descartado: esperar el merge a `main`.

### Contexto en Engram

- Proyecto: `brillipoint-ops`
- `topic_key`: `issue/brillipoint-ops#13`
- 2026-11-09 — **Se mantiene la confirmación en línea** del botón "Reimprimir" (dos pasos: Reimprimir → Sí, reimprimir), aunque el borrador decía "un clic". Razón: cada impresión cuesta y un toque accidental en la tablet no debe gastar papel.

Relacionados: #11 (contador de impresiones en el panel inicial), #12 (la foto no llena la hoja 6×4 en "Por tamaño" y en templates).

### Affected repositories (hint)

brillipoint-print-server
