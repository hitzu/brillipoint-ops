feat(print-server): physical 2x6 cut for templates

### Problem

Necesitamos templates que salgan como **dos tiras de 2×6"** en lugar de una foto de 4×6". El corte es una función nativa de la DNP: la impresora corta la hoja, no el software. Hoy un template marcado con corte se imprime **sin cortar**, y en los selectores de templates no hay forma de saber cuál corta.

**Estado actual (verificado en el código, `brillipoint-print-server` en `main`, `fd81d5f`):**

Lo que **ya existe**:

- **Flag por template:** el editor tiene el check "Aplica corte físico" (`app/ui/templates/design_editor.html:61-64`) y el documento lo guarda como `cut: bool` (`app/templates/schema.py:258`, `:339`).
- **Línea de corte en el diseño:** el corte va a 2 in sobre el lado corto de la hoja (`CUT_AXIS_POSITION_IN = 2.0` y `resolve_cut_axis`, `app/templates/render/geometry.py:24`, `:147`). La validación rechaza elementos que crucen el eje o caigan en su margen de tolerancia (`app/templates/catalog.py:268-308`). El editor pinta esa zona (`app/ui/static/design_editor.js:1512-1617`).
- **Selección de cola por flag:** `CupsConfig.resolve_queue` / `resolve_queue_key(cut)` (`app/core/config.py:115-138`) elige la cola según el `cut` del template (`app/templates/service.py:437`, `:1508`). Hay dos claves en la configuración: `plain` (`cut: false`) y `cut2` (`cut: true`).
- **Simulador:** la impresora simulada ya marca "con corte 2x6", pone el badge `2x6` y puede separar las tiras (`app/ui/static/simulated_printer.js:123`, `:189`, `:382`; control "Separar tiras 2x6" en `app/ui/templates/simulated_printer.html:54-57`). El dato sale del `cut` de la cola en la configuración (`app/cups/stub.py:326`).
- **Tiras repetidas:** dos slots pueden usar el mismo `capture_number` (`required_capture_count` toma el máximo, `app/templates/schema.py:395-400`), así que ya se pueden diseñar dos tiras iguales con las mismas fotos.

Lo que **falta**:

1. **La DNP nunca recibe la orden de cortar.** `cut2` apunta a la misma cola CUPS `DNP` que `plain`. El contenedor `cups` solo crea esa cola, y `config.yaml.example:32-41` lo dice: "until you create a second CUPS queue and name it here, `cut2` prints on the same media as `plain` — i.e. uncut". El medio sale del `*DefaultPageSize` del PPD de la cola (`app/templates/ppd.py:118-122`) y se manda como `lp -o media=<media_name>` (`app/cups/bridge.py:319-324`). El driver expone el corte como el tamaño de página `w288h432-div2` (verificado en la impresora, ver Evidencia en la impresora), pero ninguna cola lo usa. La tabla de `docs/features-plan/printer/hardening-design.md:57` sigue en `_pending (2-inch cut)_`.
2. **Los selectores no dicen que un template corta.** `published_template_choices` (`app/api/ui_routes.py:207-247`) arma la lista para el selector de la configuración del evento (`app/ui/templates/partials/event_config.html:70-98`) y para "Por template" en Upsell e Historial (`GET /events/{id}/templates`, `app/api/routes.py:382-396`, que pinta `app/ui/static/mini_book.js:219`). Esa lista no incluye `cut`. El catálogo de `/design` (`app/ui/templates/partials/design_template_row.html:14-31`) tampoco lo muestra, aunque el resumen de `list_templates` sí lo trae (`app/templates/service.py:736`).
3. **El simulador indica un corte que la impresora real no hace.** Mientras la falta 1 siga abierta, el simulador dice "con corte" y la DNP imprime la hoja entera.

### Proposal

Punto de partida; la planeación lo afina.

1. **Prueba física del corte (paso 0, bloquea lo demás).** El medio ya está verificado: `w288h432-div2` (ver Evidencia en la impresora). Falta imprimir en la DNP real una hoja de prueba de 4×6 con dos tiras usando ese medio, y confirmar que sale cortada en dos tiras de 2×6. La prueba incluye un trabajo con `copies > 1` (pregunta 3).
2. **Hacer que `cut2` corte de verdad (camino B, decidido):** `CupsQueueConfig` (`app/core/config.py:48-49`) gana un campo opcional `media`. `cut2` lo usa con `w288h432-div2` sobre la misma cola `DNP`, y `bridge.py` lo manda por trabajo en `lp -o media=` (`app/cups/bridge.py:321`). `PpdReader.resolve` acepta ese medio en lugar del `*DefaultPageSize` (hoy lo llaman `app/main.py:188`, `app/mini_book/service.py:121` y `app/templates/service.py:451`). Sin `media`, todo sigue igual que hoy. Hay que actualizar `config.yaml.example:32-41` y `tutorial-instalacion.md`.
3. **Indicar el corte en todos los selectores:** sumar `cut` a `published_template_choices`, tomado de la **versión publicada** y no del borrador (la misma regla que ya siguen `capture_count` y la vista previa en `ui_routes.py:230-240`), y mostrar un distintivo "Corte 2×6" en la configuración del evento, en "Por template" de Upsell e Historial y en el catálogo de `/design`.
4. **Corte solo en vertical:** el editor deshabilita "Aplica corte físico" cuando el template es horizontal (`app/ui/static/design_editor.js:39`, `:831`), y la validación del server rechaza `cut: true` con orientación `landscape` (junto a la del eje de corte, `app/templates/catalog.py:299`).
5. **Simulador:** mantener lo que ya hace y comprobar que refleje el corte de la cola real que use cada trabajo después del cambio.

### Acceptance criteria

- Un template con "Aplica corte físico" sale de la DNP real como **dos tiras de 2×6"** cortadas por la impresora. Uno sin el check sigue saliendo como una hoja de 4×6" sin cortar.
- En un template horizontal el check "Aplica corte físico" está deshabilitado, y el server rechaza un documento horizontal con `cut: true`.
- La impresión de prueba desde el editor (`POST /templates/{id}/test-print`) de un template con corte también sale cortada.
- La configuración del evento, "Por template" en Upsell e Historial y el catálogo de `/design` muestran que el template corta.
- El distintivo refleja la versión publicada: un borrador que activa o quita el corte no cambia lo que muestran los selectores hasta que se publica.
- La impresora simulada muestra "con corte 2x6" solo en los trabajos que la impresora real cortaría.
- Si el `media` configurado para `cut2` no existe en el PPD de la cola, el server lo rechaza (al arrancar o al abrir la sesión) en vez de imprimir sin cortar en silencio.
- Una configuración sin `media` en ninguna clave se comporta exactamente como hoy.
- Queda documentado en `tutorial-instalacion.md` / `checklist-evento.md` cómo comprobar el corte antes de un evento.

### Open questions

1. **¿El corte deja tira de desperdicio o descuadra las tiras?** El nombre del medio ya está verificado (ver Evidencia en la impresora). Esto solo se ve con la prueba física del paso 0.
2. **Calibración:** `cut_tolerance_in` de `cut2` es un valor sin medir (`README.md:95`, `:108`). ¿Se mide en la misma prueba física del paso 0?
3. **Riesgo: copias multiplicadas con el medio de corte.** Un bug viejo de Gutenprint en la DS-RX1 reporta que con `-div2` y varias copias salían de más ("2 request --> 4 copy printer (8 strips)"). Se cerró como desactualizado y se atribuyó a una instalación mezclada. `bridge.py:324` manda `-o copies=`, así que la prueba física del paso 0 tiene que incluir un trabajo con `copies > 1`.

**Evidencia en la impresora (compu del evento, 2026-11-09):** `lpoptions -p DNP -l` y `/etc/cups/ppd/DNP.ppd` dentro del contenedor `cups`.

- `PageSize/Media Size: B7 *w288h432 w288h432-div2 w360h504 w432h576 w432h576-div4 w432h576-div2`. El corte se elige **solo con el tamaño de página**: el driver no tiene una opción de cortador aparte.
- `*PageSize w288h432-div2/2x6*2`, `*PaperDimension w288h432-div2/2x6*2: "298 461"` e `*ImageableArea w288h432-div2/2x6*2: "0 9 298 452"`. Son los mismos números que `w288h432` (citados en `app/templates/ppd.py:17-18`), así que el raster, el lienzo y el render del 4×6 no cambian; solo cambia el nombre del medio en `lp -o media=`.
- `*DefaultPageSize: w288h432`: la cola `DNP` imprime sin corte por defecto, lo que confirma la falta 1.
- Fuera de alcance: `w432h576-div4` (2x6*4) y `w432h576-div2` (4x6*2) son para medio de 6×8, no para el rollo de 4×6.

**Evidencia externa (verificada 2026-11-09):**

- Guía de Fotomaster para impresoras DNP: "FMX will send two 2x6 images side by side as a single 4x6 print job" y "The printer will cut the sheet in half, producing two individual 2x6 strips". https://support.fotomaster.com/articles/dnp-printer-guide
- Bug de Gutenprint #706: en una DS-RX1 se imprime con `media=w288h432-div2`, es decir, una página de 4×6 (288×432 pt) partida en dos. https://sourceforge.net/p/gimp-print/bugs/706
- Instrucciones del driver de DNP: el tamaño de papel queda en 4×6 y se activa "2 inch cut". https://imagingspectrum.com/blogs/blog/how-to-print-2x6-photo-booth-strips-with-a-dnp-ds40-or-dnp-rx1-photo-printer

**Fuera de alcance:** la app del iPad (`BrillipointPhotobook`) no consume la lista de templates (`PrintServerAPIClient.swift` no llama a `/templates`), así que no cambia.

### Decisiones (2026-11-09)

1. **El operador diseña las dos tiras en el 4×6 completo; el creador de templates no cambia.** La DNP no duplica: recibe una hoja de 4×6 que ya trae las dos tiras y la corta a la mitad (ver Evidencia externa). Para dos tiras iguales, el operador arma las dos mitades repitiendo `capture_number` en los slots, algo que el editor y `required_capture_count` ya soportan (`app/templates/schema.py:395-400`).
   - Descartado: un modo "diseñar una tira de 2×6 y que el render la repita en las dos mitades". Obliga a modificar el editor y el render, y la impresora no lo necesita. Si hace falta por comodidad, va en otro issue.
2. **Camino B: el corte se manda como medio por clave sobre la misma cola `DNP`.** `CupsQueueConfig` gana un campo opcional `media`; `cut2` usa `w288h432-div2`. El medio tiene las mismas dimensiones que el 4×6 (ver Evidencia en la impresora), así que la geometría no cambia.
   - Descartado: camino A, una segunda cola CUPS con `*DefaultPageSize: w288h432-div2`. No toca Python, pero son dos colas sobre el mismo dispositivo USB que pueden competir por él, la cola hay que recrearla en cada arranque del contenedor `cups`, y su estado no se ve en el panel (`status_queue` es `plain`).
3. **Por ahora, el corte solo aplica a templates verticales (4×6 → dos tiras de 2×6 paradas).** Es para empezar a probar. El editor deshabilita el check en horizontal y el server lo valida. Es una regla puntual, no un rediseño del creador (consistente con la decisión 1).
   - Descartado por ahora: corte en horizontal (dos tiras de 6×2 acostadas). `resolve_cut_axis` ya lo soporta (`app/templates/render/geometry.py:147`), así que se puede habilitar después quitando la regla.
   - Riesgo aceptado: un template horizontal con `cut: true` que ya exista en la compu del evento deja de validar. Hay que revisarlo antes de desplegar.
4. **El distintivo "Corte 2×6" va solo en los selectores:** configuración del evento, "Por template" en Upsell e Historial, y catálogo de `/design`.
   - Descartado: mostrarlo también en la fila de sesión pendiente (`app/ui/templates/partials/pending_session_row.html:41-43`) y en Recuperación. Ahí el template ya está elegido, así que el distintivo no ayuda a decidir.

### Affected repositories (hint)

brillipoint-print-server
