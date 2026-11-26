feat(bookings): mirror bookings to Google Calendar (one-way sync)

### Problem

Las reservas de `brillipoint-api` son la fuente de verdad de la agenda, pero el equipo usa Google Calendar para verla rápido (teléfono, widgets, compartir). Hoy no se refleja nada: el calendario se lleva a mano y se desfasa.

Volumen actual: unas 5 reservas al mes. El diseño está dimensionado para eso; reintentos automáticos y colas quedan para una fase 2.

**Estado actual (verificado en `bookandsign-api`, `main`, `aed5bcc`):**

- **Entidad** `Booking` (`src/bookings/entities/booking.entity.ts`): `purpose` (nullable), `eventDate`, `serviceStartsAt`, `serviceEndsAt` (`timestamptz`), `title` (nullable), `venueName`, `mapsUrl`, `contractId` (nullable). Hereda soft delete (`deleted_at`) de `src/common/entities/base-time.entity.ts`.
- **`BOOKING_STATUS`** solo tiene `confirmed`; no hay endpoint de cancelación.
- **Rutas de escritura:**
  - `POST /bookings` (`src/bookings/bookings.controller.ts:47`, `src/bookings/bookings.service.ts:36`).
  - `POST /bookings/:id/reschedule` (`bookings.controller.ts:132`, `bookings.service.ts:116`; guarda con `bookingsRepository.save`).
  - **Borrar ya ocurre hoy:** `removeContract` hace soft delete de todas las reservas del contrato (`src/contracts/contracts.service.ts:968`).
- **`title` y `purpose` son opcionales** al crear (`src/bookings/dto/create-booking.dto.ts`).
- **SKU:** vive en el contrato (`src/contracts/entities/contract.entity.ts:102`). La agenda ya lo expone (`src/bookings/bookings-agenda.service.ts:149`).
- **Zona horaria:** `EVENT_DISPLAY_TIMEZONE`, con default `America/Mexico_City` (`src/photos/sessions.service.ts:612`).
- **Auth:** los endpoints requieren autenticación por defecto; `@Public()` es la excepción (`bookings.controller.ts:26`).
- No hay dependencia de Google (`googleapis` no está en `package.json`).

### Proposal

**Sincronización en un solo sentido**, reserva → Google Calendar. Es una integración saliente contra la API de Calendar, no un webhook. Las reservas mandan; el calendario es un espejo de solo lectura.

1. **Prerequisitos manuales** (fuera del código; los hace Roberto antes de probar en prod)
   - Proyecto gratuito en Google Cloud Console con la Calendar API habilitada. No se hospeda nada en GCP.
   - Service account con llave JSON.
   - Calendario dedicado "Brillipoint", compartido con la service account con permiso "Hacer cambios en los eventos".
   - El mismo calendario compartido con Aletvia y Roberto, para que se sobreponga a su Google Calendar personal.
   - Variables en prod (nombres sugeridos): `GOOGLE_CALENDAR_ID` y `GOOGLE_SERVICE_ACCOUNT_JSON`. Nunca en el repo.
2. **Persistencia:** columna `google_calendar_synced boolean NOT NULL DEFAULT false` en `bookings`. Requiere migración.
   - `true` significa "Google coincide con esta fila".
   - El id del evento se deriva de la reserva: `brillipoint<bookingId>`. Google acepta ids propios con caracteres `a-v` y `0-9`, de 5 a 1024 caracteres, únicos por calendario ([events reference](https://developers.google.com/workspace/calendar/api/v3/reference/events)). Por eso no hace falta guardar el id.
3. **Puerto `CalendarMirror`** en el módulo de bookings, con tres adaptadores:
   - **Google** (`googleapis`).
   - **No-op:** se usa cuando falta alguna variable; no llama a Google.
   - **Fake:** para tests.
4. **Sincronizar una reserva** (`syncBooking(id)`)
   - Lee la reserva incluyendo las borradas (`withDeleted`).
   - **Borrada:** borra el evento; un `404` o `410` cuenta como hecho.
   - **Viva:** hace `get` del id. Si existe, `update` con `status: confirmed`; si da `404`, `insert` con ese id.
   - Se usa `get` antes de escribir porque Google advierte: "we cannot guarantee that ID collisions will be detected at event creation time".
   - **Éxito:** marca `google_calendar_synced = true`. **Error:** queda en log y la fila se queda en `false`.
5. **Disparadores** (Google nunca hace fallar ni revierte el request)
   - **Create:** la fila nace en `false` por el default.
   - **Reschedule:** pone `false` en el mismo `save`.
   - **`removeContract`:** pone `false` en las reservas del contrato antes del soft delete, dentro de la misma transacción.
   - En los tres casos, después del commit se llama a `syncBooking` sin esperar el resultado.
6. **Endpoint `POST /bookings/calendar-sync`** (autenticado, sin `@Public()`)
   - Procesa las reservas en `false` con `service_ends_at >= now()`, incluidas las borradas.
   - Responde `{ enabled, synced, failed, failures: [{ bookingId, error }] }`.
   - Es el destrabe manual para un usuario técnico y también el backfill: la migración deja todo en `false`, así que la primera llamada refleja las reservas futuras.
7. **Contenido del evento**
   - **Título:** `<prefijo> · <cuerpo>`.
     - Prefijo: la etiqueta del `purpose` (Evento, Scouting, Junta, Prueba de maquillaje, Prueba de peinado, Prueba de uñas, Otro). Sin `purpose`: "Reserva" si tiene contrato, "Privado" si no.
     - Cuerpo: `title`, o `#<id>` si no hay título.
   - **Ubicación:** `venueName`.
   - **Descripción:** `SKU: <sku>` si tiene contrato; el `mapsUrl` si existe.
   - **Horario:** `serviceStartsAt` y `serviceEndsAt`, con `timeZone` tomado de `EVENT_DISPLAY_TIMEZONE`.
   - Sin invitados, sin color, sin link de regreso y sin datos personales del cliente.

### Acceptance criteria

- Crear una reserva (cualquier `purpose`, con o sin contrato) crea exactamente un evento en el calendario Brillipoint y deja `google_calendar_synced = true`.
- Reagendar actualiza ese mismo evento (mismo id). No hay duplicados.
- Eliminar un contrato borra los eventos de sus reservas.
- Si Google falla (fake que lanza error):
  - create, reschedule y `removeContract` responden igual que hoy;
  - la fila queda en `false`;
  - el error queda en el log.
- `POST /bookings/calendar-sync`:
  - sincroniza las reservas futuras pendientes y reporta `synced` y `failed`;
  - llamarlo dos veces seguidas no duplica eventos;
  - sin pendientes, responde `synced: 0`.
- Sin las variables de Google completas, el adaptador no-op no llama a Google y el endpoint responde `enabled: false`. Dev, worktrees y tests nunca escriben en el calendario real.
- Las credenciales solo se leen de env/secrets.
- Hay un test por ruta de escritura (create, reschedule, `removeContract`) que verifica la marca en `false` y la llamada a `syncBooking`. Ningún test llama a Google.

### Decisiones

Tomadas con el usuario el 2026-11-18 (las del 2026-10-11 siguen vigentes):

- **Alcance:** se reflejan **todas** las reservas: cualquier `purpose` y también las privadas (sin `contractId`).
- **Mecanismo:** marca `google_calendar_synced` en la misma fila de `bookings`, intento después del commit y endpoint manual para destrabar. A este volumen, la marca en la misma fila da la misma atomicidad que un outbox sin una tabla nueva.
- **Destrabe:** solo el endpoint. Si se empiezan a quedar reservas trabadas seguido, se agrega un botón en la agenda.
- **Contenido:** solo datos de la reserva, más SKU y `mapsUrl` cuando existan. Sin datos personales del cliente.
- **Sin link** de regreso al front: hoy no existe un deep link por reserva (la agenda es `/agenda` y el detalle es un diálogo, `bookandsign-front/src/features/booking-agenda`).
- **Sin colores** por `purpose`: el prefijo del título basta.
- **Entornos:** solo prod escribe en Google. Sin variables completas, el sincronizador es un no-op.
- **Sin reintentos automáticos ni circuit breaker** en esta fase.
- **Del 2026-10-11:** service account con calendario compartido; sin invitados (las service accounts necesitan delegación de dominio para agregar asistentes).

### Alternativas descartadas

- **Outbox por integración (`calendar_sync_jobs`)**. Se eligió primero y se descartó el mismo día: a ~5 reservas al mes no aporta sobre la marca en la fila, y el historial de intentos no hace falta.
- **Tabla general `outbox_events`, tipo Oban.** Es la forma correcta cuando aparezca una segunda integración asíncrona o crezca el volumen; se retoma entonces.
- **pg-boss.** Dependencia nueva con schema y migraciones propias fuera de TypeORM.
- **Reconciliación por cron** (`updated_at` contra `synced_at`). No hace falta con un destrabe manual a este volumen.
- **Botón en la agenda.** Por ahora basta el endpoint.
- **Columna `google_calendar_event_id`.** El id se deriva de la reserva.
- **Calendario de pruebas para dev.** Aumenta la configuración y el riesgo de confundir ids.
- **Link de regreso, colores, datos del cliente.** Ver Decisiones.
- **OAuth** (2026-10-11). También requiere un proyecto en Cloud Console, más un refresh token que puede expirar o revocarse.

### Riesgos aceptados

- **Ediciones manuales en Google** se sobrescriben la próxima vez que se sincroniza esa reserva. Las reservas mandan.
- **Si el proceso muere** entre el commit y la llamada a Google, la reserva se queda en `false` hasta que alguien llame al endpoint. Se revisa a mano.
- **Duplicado por concurrencia:** si el intento después del commit y el endpoint procesan la misma reserva al mismo tiempo, los dos pueden recibir `404` e insertar, y Google no garantiza detectar el choque de ids. Es muy improbable a este volumen.
- **Cancelación futura:** cuando exista un endpoint de cancelación, debe poner la marca en `false`, igual que `removeContract`.
- **Dependencia nueva** (`googleapis`) en la API.

### Fase 2 (otro issue, no ahora)

Reintentos con backoff, circuit breaker, botón en la agenda y, si aparece otra integración, la tabla general `outbox_events`.

### Orden sugerido

Solo `brillipoint-api`:

1. Migración.
2. Puerto y adaptadores (Google, no-op, fake).
3. `syncBooking`.
4. Disparadores en create, reschedule y `removeContract`.
5. Endpoint `POST /bookings/calendar-sync`.

Lleva migración, así que se trabaja en un worktree con base propia (`scripts/wt-db.sh create 4`).

### Contexto en Engram

- Proyecto: `brillipoint-ops`
- `topic_key`: `issue/brillipoint-ops#4`

Busca ese `topic_key` (`mem_search`, luego `mem_get_observation`) antes de implementar. Si contradice este issue, manda el issue.

### Affected repositories (hint)

brillipoint-api
