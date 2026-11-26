feat(bookings): import personal events from the shared Google Calendar into bookings

### Problem

Los eventos personales de Roberto y Ale (conciertos, citas médicas) se capturan en Google Calendar porque es más rápido. Van en un calendario secundario que los dos comparten. Brillipoint no se entera, así que la fecha aparece libre en la agenda y en el calendario público aunque uno de los dos no esté disponible. Hoy hay que volver a capturarlos a mano como reservas privadas.

Volumen: unos 10 eventos al mes. Los contratos y las reservas de negocio siguen naciendo en Brillipoint; #4 los refleja hacia Google.

**Estado actual (verificado en `bookandsign-api`, `main`, `aed5bcc`):**

- **Las reservas bloquean la agenda** por la revisión de empalmes: `assertNoOverlap` en `src/bookings/bookings.service.ts:43` y `:193`. El comentario en `src/contracts/contracts.service.ts:966` lo explica.
- **El calendario de disponibilidad es público** (`GET /bookings/calendar`, `src/bookings/bookings.controller.ts:83-84`). Un evento que solo existe en Google deja la fecha como libre para los clientes.
- **Una reserva privada** es una reserva sin `contractId`. `purpose` y `title` son opcionales (`src/bookings/dto/create-booking.dto.ts`).
- **No se puede cancelar ni borrar una reserva.** Solo existen `POST /bookings` y `POST /bookings/:id/reschedule` (`bookings.controller.ts:47`, `:132`), y `BOOKING_STATUS` solo tiene `confirmed`.
- **Depende de #4** (todavía sin implementar): la service account, `googleapis` y el puerto `CalendarMirror`.

### Proposal

Punto de partida; la planeación lo afina.

**Fuente de verdad según dónde nace el evento:**

- **Nace en Brillipoint** (contratos, reservas de negocio): manda Brillipoint, y #4 lo refleja a Google.
- **Nace en el calendario compartido** (personal): manda Google. Brillipoint lo importa como reserva privada y lo concilia a mano.

1. **Fuente.** Se lee solo el calendario secundario compartido de Roberto y Ale, por su Calendar ID (nombre sugerido: `GOOGLE_INBOX_CALENDAR_ID`).
   - El dueño lo comparte con la service account de #4 con permiso "Ver todos los detalles de los eventos", que es solo lectura.
   - La API nunca escribe en ese calendario.
2. **Tabla bandeja `google_inbox_events`.** Columnas:
   - `google_event_id` (único)
   - `title`
   - `starts_at`, `ends_at`, `all_day`
   - `google_updated_at`
   - `status`: `pending`, `converted`, `changed`, `dismissed` o `cancelled`
   - `booking_id` (nullable)
3. **Traer:** `POST /bookings/google-inbox/pull` lee los eventos futuros y actualiza la tabla.
   - Evento nuevo → `pending`.
   - Ya `converted` y cambió el horario → `changed`.
   - Borrado en Google → `cancelled`.
   - Las filas `dismissed` se quedan así.
4. **Listar:** `GET /bookings/google-inbox?status=...`.
5. **Convertir:** `POST /bookings/google-inbox/:id/convert`.
   - En una fila `pending`, crea una reserva privada con el título y el horario. `eventDate` es la fecha civil en `EVENT_DISPLAY_TIMEZONE`.
   - En una fila `changed`, reagenda la reserva ligada con el horario de Google.
   - Pasa por la misma revisión de empalmes. Si sale bien, la fila queda `converted` con su `booking_id`.
6. **Descartar:** `POST /bookings/google-inbox/:id/dismiss`, para el ruido.
7. **Todo es manual:** sin cron y sin webhooks ni watch channels. A este volumen basta con conciliar a mano.

### Acceptance criteria

- Traer con un evento nuevo en el calendario compartido crea exactamente una fila `pending`. Traer otra vez no la duplica.
- La API nunca lee eventos de otros calendarios.
- Convertir una fila `pending` crea una reserva privada con su título y horario. Esa fecha aparece ocupada en la agenda y en `GET /bookings/calendar`.
- Convertir un evento que se empalma con otra reserva falla con el error de empalme actual, y la fila sigue `pending`.
- Si se cambia en Google el horario de un evento convertido, la siguiente traída lo marca `changed`. Convertirlo de nuevo reagenda la misma reserva, sin crear otra.
- Si se borra en Google un evento convertido, la siguiente traída lo marca `cancelled`.
- Una fila `dismissed` nunca vuelve a `pending`.
- Sin Calendar ID o sin credenciales, traer responde `enabled: false` y no llama a Google.
- Los tests nunca llaman a Google; usan el adaptador fake de #4.

### Open questions

- **Cancelar reservas:** ¿el endpoint de cancelación va en este issue o en uno aparte? Hoy no existe, así que sin él un concierto cancelado sigue bloqueando la fecha. Debe poner `google_calendar_synced = false`, como quedó anotado en #4.
- **Doble aparición:** #4 refleja la reserva importada al calendario Brillipoint, así que el evento se ve dos veces (en el compartido y en Brillipoint). ¿Se excluyen del espejo las reservas que vienen de la bandeja?
- **Calendario destino de #4:** ¿un calendario "Brillipoint" nuevo o este mismo calendario compartido? Si es el mismo, la traída tiene que saltarse los ids que empiezan con `brillipoint`.
- **Eventos de día completo:** las reservas exigen horario exacto (`CHK_bookings_service_ends_after_starts`, `scheduleType: 'exact'`). ¿Se convierten a un rango fijo o no se pueden convertir?
- **Ventana de la traída:** ¿solo eventos futuros? ¿Hasta cuántos meses adelante?
- **Interfaz:** ¿solo endpoints, como en #4, o una vista en la agenda?

### Riesgos

- **Privacidad:** la service account ve todos los detalles de ese calendario compartido, y solo de ese.
- **Orden:** no se puede implementar antes que #4.

### Affected repositories (hint)

brillipoint-api
