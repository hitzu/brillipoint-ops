feat(photobook): retoque automático e invisible de las fotos ("fotos profesionales")

### Problem

Nuestro slogan promete **fotos profesionales**. Hoy las fotos salen tal como las toma la cámara, y la calidad depende de la luz del lugar, del fondo y del encuadre. Queremos mejorarlas automáticamente **sin que se note**: la foto debe verse como la tomó un buen fotógrafo, no retocada ni generada por IA.

**Prioridad baja (2026-11-22).** Va después de la prueba del extra temático (#29).

**Estado actual (verificado en el código, `BrillipointPhotobook` en `main`, `a097e10`):**

- **Aprobación:** al aprobar una captura (`ViewModels/AppViewModel.swift:497-581`), la app solo agrega una marca de agua a la copia que va al backend (`:505-507`). No aplica ningún ajuste de imagen.
- **Impresión:** se mandan las capturas crudas locales (`ViewModels/SessionResultActions.swift:105-106`). El print server compone la plantilla.
- **Frameworks:** la app no usa Core Image para ajustes automáticos ni Vision para segmentar a la persona en el flujo de sesión.

### Proposal

Punto de partida; la planeación lo afina.

- Aplicar en el iPad, antes de guardar, subir e imprimir, ajustes que no generan contenido nuevo:
  - **Core Image:** ajuste automático de exposición, color y contraste (`autoAdjustmentFilters`).
  - **Look de marca:** una curva de color fija y suave, para que todas las fotos se vean consistentes.
  - **Opcional, Vision:** segmentación de persona para un desenfoque leve del fondo, tipo cámara de retrato.
- Activarlo por evento o por dispositivo, apagado por defecto mientras se valida.
- Sin generación con IA: la foto sigue siendo la foto real.

### Acceptance criteria

- **Apagado:** sin el ajuste activo, las fotos salen exactamente igual que hoy.
- **Encendido:** con el ajuste activo, la foto guardada, la subida y la impresa llevan el mismo ajuste.
- **Prueba a ciegas:** en una comparación antes/después con fotos reales de eventos, el equipo prefiere la ajustada y no la identifica como retocada.
- **Tiempo:** procesar no retrasa de forma perceptible la revisión ni la impresión de la sesión.

### Open questions

- ¿Se activa por evento (desde la API y el front) o como ajuste local del iPad?
- ¿Se ajusta la foto antes de la revisión del invitado, o solo la que se guarda?
- ¿Basta con ajustes de Core Image, o hace falta un modelo de retoque en servidor (con costo por foto y que necesita internet)?

### Affected repositories (hint)

BrillipointPhotobook-
