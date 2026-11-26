feat(booking): barra fija de selección con estado de guardado y recorte de imágenes en la pestaña "Tatuajes"

### Problem

En pruebas internas de la pestaña "Tatuajes" de la reserva pública (#20, #21, #22) salieron tres quejas y una petición:

- **No se nota que se guarda.** Cada acción (subir, elegir del catálogo, quitar) ya se guarda sola, pero el único aviso es un "Guardando..." al fondo de la tarjeta que no se ve si la clienta está arriba, y nunca dice "Guardado". Parece que no pasó nada.
- **No saben cuántos llevan.** Los contadores "N de 10" están en los encabezados de cada lista; al hacer scroll por el catálogo se pierden.
- **Falta un resumen** de lo que ya eligieron. Como la idea es que la clienta entre y salga en varias sesiones hasta el cierre (7 días antes del evento), el resumen no puede sonar a "ya terminaste".
- **Recortar.** Quieren subir solo una parte de una imagen (por ejemplo, la cara de una selfie o un elemento de un diseño), no la imagen completa.

### Proposal

**1. Barra fija de selección** (viaja con el scroll dentro de la pestaña, visible después del gate de celular):

- Contadores: "Subidas N de 10 · Templates N de 10".
- Estado de guardado: "Tus cambios se guardan solos" (antes de la primera acción), "Guardando…" (mientras se sube, elige o quita), "Guardado ✓" (al terminar bien), aviso de error si falla, y "Cerrado: ya no se pueden modificar" en solo lectura.
- Botón **"Ver seleccionado"** que abre el resumen.
- Sustituye al "Guardando..." que hoy está al fondo de la tarjeta.

**2. Resumen ("Ver seleccionado")** como **vista, no como paso**:

- Miniaturas de lo subido y de los templates elegidos, con sus contadores.
- El aviso de impresión existente (solo se imprimen 5, con su prioridad).
- "Puedes hacer cambios hasta el <fecha de cierre>" (cuando hay fecha de evento).
- **Sin** botón "Enviar" o "Finalizar": cerrarlo no bloquea nada. El cierre sigue siendo el de 7 días antes del evento.

**3. Recorte antes de subir**:

- Al elegir imágenes en el dropzone, **cada una pasa siempre** por el recorte, una por una, antes de subirse, con el indicador "Imagen N de M".
- Es ligero: el recuadro empieza cubriendo la **imagen completa**. Si no se mueve, "Listo" sube la imagen tal cual (sin volver a codificarla); quien no quiere recortar avanza con un toque por imagen.
- Opciones: "Listo" y "Omitir esta imagen" (no la sube y sigue con las demás).
- Se sube **solo** el resultado (el recorte, o la imagen completa si no movió el recuadro). El original de un recorte nunca se sube.
- Para recortar de nuevo algo ya subido: se quita y se vuelve a subir.

### Acceptance criteria

- [ ] Después del gate de celular, la barra queda visible mientras se hace scroll por toda la pestaña y muestra "Subidas N de 10" y "Templates N de 10", actualizados al subir, elegir y quitar.
- [ ] Antes de la primera acción, la barra dice "Tus cambios se guardan solos".
- [ ] Durante cualquier subida, elección o quitado, la barra dice "Guardando…"; al terminar bien, "Guardado ✓"; si falla, muestra el error (el mensaje actual de la tarjeta se conserva).
- [ ] Ya no aparece el "Guardando..." al fondo de la tarjeta.
- [ ] En solo lectura (cierre a 7 días o 409), la barra dice "Cerrado: ya no se pueden modificar" y no hay controles de edición (igual que hoy).
- [ ] "Ver seleccionado" abre el resumen con las miniaturas de subidas y templates, el aviso de impresión y la fecha límite cuando existe. No tiene botón de enviar ni de finalizar.
- [ ] Al elegir una o varias imágenes, cada una abre el recorte antes de subirse, con "Imagen N de M".
- [ ] El recuadro empieza en la imagen completa: "Listo" sin moverlo sube el archivo original sin recodificar; con el recuadro ajustado sube solo el recorte.
- [ ] "Omitir esta imagen" no la sube y continúa con las siguientes.
- [ ] Un recorte de un PNG conserva la transparencia.
- [ ] El tope de 10 subidas se valida antes del recorte (igual que hoy).
- [ ] El recorte se puede manejar con el dedo a 390 px de ancho; los botones miden al menos 44 px.
- [ ] Si una imagen no se puede abrir en el recorte (por ejemplo, HEIC en un navegador que no lo soporta), solo se ofrece subirla completa u omitirla.
- [ ] Las pruebas de `TattooDesignsView` y `TattooDesignsSection` se ajustan y cubren la barra (contadores y estados) y el flujo de recorte.

### Estado actual verificado

- `bookandsign-front/src/features/booking/components/TattooDesignsSection.tsx`: toda mutación pasa por `saveDesigns` (`PUT .../prep-profile/tattoo-designs`) dentro de `addFiles`, `toggleCatalogDesign` y `removeDesign`, envuelta en `isBusy`; los errores pasan por `failWith` (409 → `locked`). Ya calcula la fecha de cierre (`getTattooClosingDay(eventDate)` → `closingDayLabel`).
- `bookandsign-front/src/features/booking/components/TattooDesignsView.tsx`: el "Guardando..." se muestra al final de la tarjeta; los contadores viven en `SectionHeading`; ya usa `Modal` de `react-bootstrap` para el modal de ejemplos de fotos.
- `react-cropper` ya es dependencia del front (`package.json`); su único uso es una demo de plantilla (`src/views/Forms/ImageCropper/FormImageCropper.tsx`), no reutilizable.
- API sin cambios: `createPublicPrepProfileUploadUrl` acepta cualquier `image/*` (`bookandsign-api/src/contracts/preparation-profile/prep-profile-uploads.service.ts`).

### Open questions

Ninguna que cambie el alcance.

Riesgos aceptados:

- **HEIC en navegadores de escritorio** que no lo decodifican: no se puede recortar; se sube completa.
- **Recortar de nuevo** algo ya subido exige quitarlo y subirlo otra vez (el original no se guarda).
- El recorte de fotos (no PNG) se exporta como JPEG; puede perder algo de calidad frente al original.

### Decisiones

- **2026-11-24** Alcance: barra fija (contadores + estado de guardado + "Ver seleccionado") y recorte antes de subir, en un solo issue. Solo front.
- **2026-11-24** No hay botón "Guardar": el guardado sigue automático por acción y la barra lo hace visible. Descartado: botón "Guardar" (haría creer que sin tocarlo se pierde lo hecho).
- **2026-11-24** El resumen es una vista, no un paso: sin "Enviar" ni "Finalizar". El cierre sigue siendo el de 7 días antes del evento. Descartado: resumen como confirmación final (choca con entrar y salir en varias sesiones).
- **2026-11-24** Solo se guarda lo recortado; el original no se sube. Sin cambios de API ni de modelo de datos. Descartado: guardar original + recorte (cambia el modelo de datos; no se necesita hoy).
- **2026-11-24** Toda imagen pasa por el recorte, pero el recuadro empieza en la imagen completa y un toque ("Listo") la sube sin cambios. Descartado: botón "Recortar" en la miniatura ya subida (el original ya estaría subido, contradice "solo se guarda lo recortado"); bandeja de "por subir" con botón de envío (agrega un paso y choca con el guardado automático).

### Affected repositories (hint)

- `bookandsign-front`
