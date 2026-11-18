feat(print-server): hide the Epson A4 option in Mini Book

### Problem

Ya no usamos la Epson. El Mini Book todavía ofrece "PDF A4 (Epson)", y sus mensajes de error mandan al operador a la Epson. Esa salida tampoco pasa por la cola del BPS, así que no aparece en el conteo de hojas por evento.

**Estado actual (verificado en el código, `brillipoint-print-server` en `main`, `185c5d1`):**

- **El botón** `mini-book-epson` está en `app/ui/templates/mini_book.html:61`. Se conecta en `app/ui/static/mini_book.js:17`, `:190`, `:530` y `:550-551`.
- **El mensaje de éxito** "PDF A4 descargado. Imprímelo en la Epson." está en `mini_book.js:367`.
- **Dos errores de la cola DNP recomiendan la Epson:** `print_queue_not_configured` y `print_queue_unavailable` (`mini_book.js:61-62`).
- **La API acepta `target="epson"`** para descargar el PDF A4 (`app/api/mini_book_routes.py:30-31`).

### Proposal

Punto de partida; la planeación lo afina.

**Decisión tomada con el usuario (2026-11-10):** se quita solo la opción de la interfaz. El código se queda: `compose_a4` y `target="epson"` en la API.

- Quitar el botón "PDF A4 (Epson)" de `/mini-book`.
- Reescribir los errores de la cola DNP para que no mencionen la Epson. Por ejemplo: "No hay cola de impresión DNP configurada. Revisa config.yaml." y "La cola DNP no responde o no tiene papel 6x4 cargado."

### Acceptance criteria

- `/mini-book` no muestra la opción "PDF A4 (Epson)" en ningún modo.
- Los errores de la cola DNP no mencionan la Epson.
- Imprimir un Mini Book en la DNP funciona igual que antes.
- La API sigue aceptando `target="epson"` sin cambios.

### Open questions

_No response_

### Affected repositories (hint)

brillipoint-print-server
