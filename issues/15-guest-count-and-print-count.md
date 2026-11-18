feat(api): optional guest count on contracts and print total on events

### Problem

Queremos medir cuántas hojas imprime cada evento contra otros datos del evento; el primero es la cantidad de invitados. El print server (BPS) calcula el total de hojas por evento y lo muestra antes de borrarlo (issue del BPS relacionado). Como el BPS funciona sin internet, el staff copia ese total a mano en el backend. Hoy no hay dónde guardarlo.

La cantidad de invitados la conocemos desde que cotizamos y aplica a todas las marcas, pero tampoco hay dónde guardarla.

**Estado actual (verificado en el código, `bookandsign-api` y `bookandsign-front`):**

- **Contrato:**
  - `Contract` (`src/contracts/entities/contract.entity.ts:28`) tiene `brand_id`, los datos del cliente y los montos, pero no invitados.
  - No existe un `PATCH` general de contratos. Solo hay endpoints de items, payments, transport, cancel, reopen y finalize (`src/contracts/contracts.controller.ts:200-289`). El contrato se crea con `POST` (`:62`) usando `src/contracts/dto/create-contract-from-slots.dto.ts`.
- **Evento:**
  - `Event` (`src/events/entities/event.entity.ts:25`) tiene `photo_count` (`:67`) y `print_templates` (`:82`), pero ningún total de impresiones.
  - Se edita con `PATCH /events/:id` (`UpdateEventDto`, `src/events/dto/update-event.dto.ts`).
- **Front:**
  - "Editar evento" vive en `src/pages/event-edit/[id].tsx` y guarda con `updateEventById` (`src/api/services/eventsService.ts:43-48`).
  - No encontré ningún campo de invitados en `src/features/contracts`, `src/features/contracts-add` ni `src/features/booking`.

### Proposal

Punto de partida; la planeación lo afina.

**Decisiones tomadas con el usuario (2026-11-10):**

- Los invitados son un dato del **contrato**: se conocen desde la cotización y aplican a todas las marcas.
- El total de impresiones es un dato del **evento**, no del contrato.
- El staff captura el total a mano, con el resumen que muestra el BPS antes de borrar el evento. No hay integración entre el BPS y el backend.

**Cambios:**

- `contracts.guest_count`: entero, nulo permitido. Se captura al cotizar o crear el contrato y se puede editar después.
- `events.print_count`: entero, nulo permitido. Es el total de hojas impresas del evento, en la misma unidad que el resumen del BPS.
- Front:
  - Un campo "Invitados" en la creación del contrato, editable después.
  - Un campo "Impresiones (hojas)" en "Editar evento".
- Las migraciones solo agregan columnas que aceptan nulo.

### Acceptance criteria

- **Contrato:**
  - Se puede crear con invitados y sin invitados; los dos casos son válidos.
  - Se pueden editar los invitados de un contrato existente, y el valor se ve al volver a abrirlo.
- **Evento:**
  - En "Editar evento", capturar 56 en impresiones lo guarda, y el valor se ve al volver a abrir el evento.
  - Dejar el campo vacío está permitido.
- **Validación:** un valor negativo o que no es entero se rechaza con 400 en los dos campos.
- **Compatibilidad:** las respuestas de contratos y eventos que ya existen siguen iguales, salvo por los dos campos nuevos. Los registros existentes quedan con `null`.

### Open questions

1. ¿Dónde edita el staff los invitados de un contrato que ya existe? No hay un `PATCH` general de contratos: ¿se agrega `PATCH /contracts/:id` o va en una pantalla existente?
2. ¿En qué paso de la cotización se captura (`contracts-add`, `booking`)?
3. Mostrar o graficar `print_count` contra invitados queda fuera de este issue. Falta confirmarlo.

### Affected repositories (hint)

brillipoint-api, brillipoint-front
