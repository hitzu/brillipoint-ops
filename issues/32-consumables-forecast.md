feat(ops): consumables forecast from upcoming bookings

### Problem

Quedarse sin papel o ribbon a mitad de un evento es lo peor que le puede pasar a la cabina. Comprar de más inmoviliza dinero. Hoy nadie sabe cuántas hojas van a hacer falta en las próximas semanas: se calcula a ojo.

Ya tenemos casi todos los datos para calcularlo: cuánto imprime cada evento (lo muestra el print server, BPS) y qué eventos vienen en la agenda. Falta guardarlos en la API y juntarlos.

**Estado actual verificado (2026-11-23; `bookandsign-api` `main` `3542646`, `bookandsign-front` `main` `1076b95`, `brillipoint-print-server` `main` `a9d24e1`):**

- **El BPS ya sabe cuánto imprime cada evento,** pero solo en la compu local, y funciona sin internet:
  - Resumen de hojas DNP por evento y por categoría: `prints`, `reprints`, `upsell_template` y `upsell_mini_book` (`app/dashboard/print_summary.py:28-56`, de #19). Se muestra antes de borrar el evento.
  - Contador de por vida de la DNP (`app/cups/bridge.py:462-471`, de #11).
  - Impresora: DNP RX1HS. El corte 2x6 usa el medio `w288h432-div2` (`config.yaml.example:36`).
  - No le manda nada a la API.
- **#15 está cerrado, pero sus campos nunca llegaron a la API.** Se cerró porque el total de hojas ya se ve en el BPS. Sin embargo, en `main`:
  - `Contract` (`src/contracts/entities/contract.entity.ts:28`) no tiene número de invitados.
  - `Event` (`src/events/entities/event.entity.ts:25`) tiene `photoCount` (`:68`) y `printTemplates`, pero no un total de impresiones.
  - Ningún commit, rama ni worktree lo implementa.
- **No existe un `PATCH` general de contratos.** El contrato se crea con `POST` (`src/contracts/contracts.controller.ts:68`). Después solo hay endpoints de items, payments, transport, prep-profile, cancel, reopen, finalize y slots (`:123-376`).
- **El evento se edita** con `PATCH /events/:id`. En el front, "Editar evento" vive en `src/pages/event-edit/[id].tsx` y guarda con `updateEventById` (`src/api/services/eventsService.ts:43`).
- **La agenda está en la API:** `bookings` tiene `eventDate`, `serviceStartsAt` y `serviceEndsAt`.
- **No hay inventario.** No existe ninguna tabla de stock ni de compras de consumibles.

### Proposal

**1. Guardar los datos en la API (alcance que viene de #15):**

- `contracts.guest_count`: entero, nulo permitido. Se captura al cotizar o crear el contrato y se puede editar después.
- `events.print_count`: entero, nulo permitido. Es el total de hojas impresas del evento, en la misma unidad que el resumen del BPS.
- Front: un campo "Invitados" al crear el contrato (editable después) y un campo "Impresiones (hojas)" en "Editar evento".
- El staff captura `print_count` a mano, con el resumen que muestra el BPS antes de borrar el evento.
- Las migraciones solo agregan columnas que aceptan nulo.

**2. Pronóstico:**

- Promedio de hojas por evento, y por invitado cuando el evento tenga los dos datos.
- Con la agenda de las próximas N semanas: hojas esperadas, convertidas a rollos y ribbons.
- Vista tentativa para el staff: "Próximas 2 semanas: 6 eventos · ~1,900 hojas · 3 rollos".

**3. Fase 2 (por decidir):** registrar el stock y las compras, para que el pronóstico diga cuándo comprar y cuánto.

### Acceptance criteria

- **Contrato:**
  - Se puede crear con invitados y sin invitados; los dos casos son válidos.
  - Se pueden editar los invitados de un contrato existente, y el valor se ve al volver a abrirlo.
- **Evento:**
  - En "Editar evento", capturar 56 en impresiones lo guarda, y el valor se ve al volver a abrir el evento.
  - Dejar el campo vacío está permitido.
- **Validación:** un valor negativo o que no es entero se rechaza con `400` en los dos campos.
- **Compatibilidad:** las respuestas de contratos y eventos que ya existen siguen iguales, salvo por los dos campos nuevos. Los registros existentes quedan con `null`.
- **Pronóstico:**
  - El staff ve el pronóstico de las próximas semanas: eventos, hojas esperadas y rollos equivalentes.
  - Usa el historial real (`print_count`). Si no hay historial suficiente, usa un valor por defecto configurable y lo indica.
  - Los eventos sin `print_count` no cuentan como cero en el promedio.
- Tests de la API: crear y editar `guest_count`, guardar `print_count`, rechazar valores inválidos, y calcular el pronóstico con y sin historial.
- `pnpm run build` y los tests de la API pasan; el front construye.

### Open questions

1. **¿Dónde edita el staff los invitados de un contrato que ya existe?** No hay un `PATCH` general de contratos: ¿se agrega `PATCH /contracts/:id` o va en una pantalla existente? (Viene de #15.)
2. **¿En qué paso de la cotización se capturan los invitados?** `contracts-add` o `booking`. (Viene de #15.)
3. **¿Qué consumibles entran?** Papel y ribbon de la DNP seguro. ¿También el papel de tatuajes, el glitter u otros?
4. **¿Cuántas hojas rinde cada rollo** según el tamaño (6x4, 2x6 con corte)? Hay que confirmarlo con el proveedor.
5. **¿`print_count` guarda solo el total o también las categorías del BPS** (prints, reprints, upsells)? El desglose sirve también para medir los upsells.
6. **¿Llevamos stock (fase 2) o solo el pronóstico de consumo?**
7. **¿Qué horizonte se necesita?** 2 semanas, un mes o hasta la siguiente compra.

**Riesgos:**

- La captura es manual: si el staff no copia el total antes de borrar el evento en el BPS, el dato se pierde. Puede ser un ítem de la checklist de cierre (#31).
- Los eventos pasados no tienen `print_count`. Al principio el pronóstico va a usar el valor por defecto.
- El consumo varía mucho por tipo de evento y por número de invitados. Al principio, el pronóstico va a ser aproximado.

**Relación:** absorbe el alcance pendiente de #15. Usa el resumen de impresiones de #19. Se apoya en la checklist de cierre de #31.

### Decisiones

- **2026-11-10 (heredadas de #15):**
  - Los invitados son un dato del **contrato**: se conocen desde la cotización y aplican a todas las marcas.
  - El total de impresiones es un dato del **evento**, no del contrato.
  - El staff captura el total a mano con el resumen del BPS. No hay integración entre el BPS y el backend, porque el BPS funciona sin internet.
- **2026-11-23:** #15 se cerró porque el total ya se ve en el BPS, pero los campos `contracts.guest_count` y `events.print_count` nunca se implementaron. Ese alcance (backend y front) pasa a este issue. Descartado: que el BPS mande su resumen a la API de forma automática, porque contradice la decisión del 2026-11-10.

### Affected repositories (hint)

brillipoint-api
brillipoint-front
