feat(booking): copy en pasos, confirmación visible de guardado y botón "Ver seleccionado" llamativo en la pestaña "Tatuajes"

### Problem

Seguimiento de #35, tras revisar la pestaña "Tatuajes" de la reserva pública:

- **El texto de ayuda pasa desapercibido.** "Puedes subir hasta 10 fotos o diseños tuyos y elegir hasta 10 diseños de nuestro catálogo. Tus cambios se guardan automáticamente. Puedes cambiar tus elecciones hasta el 11 de diciembre." es un párrafo suelto, lejos del aviso de impresión, y mezcla límites, autoguardado y fecha.
- **Expectativa falsa.** La clienta puede subir y elegir hasta 10 + 10, pero solo se imprimen 5 y la selección final es nuestra. El texto no lo dice junto a los límites.
- **El guardado no se nota.** La barra de #35 ya cambia a "Guardado ✓", pero es un texto pequeño que se pierde.
- **"Ver seleccionado" no se descubre.** Es un botón secundario más; nadie sabe que existe hasta que ya hay algo guardado.

### Proposal

1. **Copy en pasos, dentro del componente que explica cómo funciona** (`TattooPrintNotice`, hoy "Imprimimos 5 tatuajes"), para que gane relevancia:
   1. Sube hasta 10 fotos o diseños tuyos.
   2. Elige hasta 10 diseños de nuestro catálogo.
   3. Nosotros escogemos 5 de tus favoritos para imprimir.
   - Pie discreto: "Todo se guarda solo. Puedes cambiar tus elecciones hasta el <fecha de cierre>." (la fecha solo si hay fecha de evento, como hoy).
   - Se elimina el párrafo suelto actual de `TattooDesignsView`.
2. **Confirmación de guardado**: al terminar bien cada guardado (subir, elegir, quitar) aparece un aviso con una palomita verde que desaparece solo a los pocos segundos. La barra conserva su estado "Guardado ✓".
3. **Botón "Ver seleccionado" de dos estados** (`TattooSelectionBar`):
   - Sin nada guardado ni seleccionado: deshabilitado y gris.
   - En el **primer guardado**: pasa a verde llamativo con un brinco de un solo uso para que se note que existe. Después queda en verde, sin repetir la animación.

### Acceptance criteria

- [ ] El texto de cómo funciona muestra los tres pasos (subir 10, elegir 10, "nosotros escogemos 5") dentro del componente del aviso de impresión, y el párrafo suelto anterior ya no aparece.
- [ ] El pie muestra "Todo se guarda solo" y la fecha límite cuando existe fecha de evento; sin fecha, solo la primera parte.
- [ ] Tras cada subida, elección o quitado exitoso aparece el aviso con palomita verde y se oculta solo; no aparece si el guardado falla (se conserva el error actual).
- [ ] El aviso no tapa los controles ni bloquea la interacción, y es anunciado a lectores de pantalla (`aria-live`).
- [ ] "Ver seleccionado" está deshabilitado y gris mientras no haya nada guardado ni seleccionado.
- [ ] Cuando el botón pasa de deshabilitado a habilitado en la visita actual (primer guardado, o al cargar la pestaña con una selección ya guardada), se pone verde y reproduce el brinco una sola vez; no se repite en guardados posteriores de esa misma visita.
- [ ] Con `prefers-reduced-motion`, el botón cambia de color sin animación.
- [ ] En solo lectura (cierre o 409) el comportamiento actual se mantiene.
- [ ] Las pruebas de `TattooDesignsView`, `TattooSelectionBar` y `TattooPrintNotice` cubren el nuevo copy, el aviso de guardado y los dos estados del botón.

### Estado actual verificado

- `bookandsign-front/src/features/booking/components/TattooPrintNotice.tsx`: "Imprimimos {TATTOO_PRINT_MAX} tatuajes" y la lista de prioridad; no menciona los límites de subida ni de catálogo.
- `bookandsign-front/src/features/booking/components/TattooDesignsView.tsx`: el párrafo "Puedes subir hasta {TATTOO_UPLOADS_MAX} fotos o diseños tuyos..." junto a `<TattooPrintNotice />`, con `closingDayLabel`.
- `bookandsign-front/src/features/booking/components/TattooSelectionBar.tsx`: botón "Ver seleccionado" con `styles.btnSecondary`, siempre habilitado; estado de guardado vía `TATTOO_SAVE_STATUS_TEXT` (`utils/tattooSaveStatus.ts`).
- Sin cambios de API ni de modelo de datos.

### Open questions

Ninguna que cambie el alcance.

### Decisiones

- **2026-11-24** Solo front; copy, aviso y botón. Sin cambios de API ni de datos.
- **2026-11-24** Se imprimen 5 y la selección es nuestra; la clienta puede subir y elegir hasta 10 + 10. El copy lo dice sin prometer cuáles se imprimen.
- **2026-11-24** El guardado se evidencia con un aviso con palomita verde que se oculta solo. Descartado: dejar solo el texto de la barra (ya existe y no se nota).
- **2026-11-24** El brinco se da una vez por visita: también cuando la clienta regresa otro día con selección ya guardada. Descartado: brincar solo en el primer guardado de toda la reserva.
- **2026-11-24** "Ver seleccionado" arranca deshabilitado y gris, y en el primer guardado pasa a verde llamativo con un brinco único. Descartado: confeti.

### Affected repositories (hint)

- `bookandsign-front`

### Contexto en Engram

- Proyecto: `brillipoint-ops`
- `topic_key`: `issue/brillipoint-ops#36`
