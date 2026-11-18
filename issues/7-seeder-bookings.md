### What

Actualizar el seeder de la API (`npm run db:seed:from-production`) para que el snapshot local sanitizado de producción cubra el modelo de datos actual.

### Why

Quien desarrolla (persona o agente) necesita una base local con datos realistas **sin datos personales de clientes**. El seeder se tocó por última vez el 2026-10-04 y la API ya cambió: el snapshot local no incluye reservas, que es la base de los eventos privados y de la sincronización con Calendar (#4).

### Estado actual verificado (2026-11-06)

- Listas de tablas: `src/database/seeds/production-seed.ts` (`INCLUDED_TABLES`, `EXCLUDED_TABLES`). Entre las 31 entidades de `src/**/entities/*.entity.ts`, **`bookings` y `extra_products` no están en ninguna lista**.
- `bookings` (`src/bookings/entities/booking.entity.ts`): `status`, `purpose`, `event_date`, `service_starts_at/ends_at`, `title` (texto libre), `venue_name`, `maps_url`, `contract_id` (FK a `contracts`, `ON DELETE SET NULL`).
- `extra_products` (`src/extras/entities/extra-product.entity.ts`): catálogo (`extra_id`, `product_id`, `quantity`, `action`). Sin datos personales.
- Sanitización existente: `sanitizeRow` en `production-seed.ts` cubre `users`, `brands`, `contracts`, `event_themes`, `slots`, `events`.
- El seeder ya compara columnas contra el schema en ejecución (`compareSchemaColumns`) y tiene `production-seed.spec.ts`; no avisa de tablas que falten en las listas.
- El seeder lee el origen con el usuario de solo lectura definido en `.env.prod` (creado por el equipo, 2026-11-06). El agente que implemente **no** corre el seeder contra producción; ver "Restricciones".

### Propuesta (punto de partida)

1. Agregar `extra_products` a `INCLUDED_TABLES` sin sanitización.
2. Agregar `bookings` a `INCLUDED_TABLES` con sanitización: `title` → `Local Booking <id>`, `venue_name` y `maps_url` → `null` (en eventos privados pueden ser el domicilio de una persona). `contract_id` y fechas se conservan; las fechas se desplazan igual que en `slots` (`dateShiftDays`).
3. Respetar el orden de inserción (`bookings` después de `contracts`).
4. Cubrir con tests de `production-seed.spec.ts`: ambas tablas están en las listas, `sanitizeRow` no deja pasar `title`/`venue_name`/`maps_url`, y un test que **falle si una entidad nueva no está en ninguna de las dos listas** (para que no vuelva a desactualizarse).
5. Revisar el resto de `sanitizeRow` contra las columnas actuales de `users`, `contracts`, `events` y `brands` y reportar lo que encuentre.

### Criterios de aceptación

- Un seed local contra una base de origen de prueba incluye `bookings` y `extra_products`, y ningún `title`, `venue_name` ni `maps_url` original.
- El test de cobertura de entidades falla si se agrega una entidad sin clasificar.
- `npm run build` y `npm test` pasan.
- El PR lista cualquier columna con datos personales que `sanitizeRow` no cubra.

### Restricciones

- El agente que implemente trabaja en un worktree de `bookandsign-api` con su base de pruebas propia (ver `CLAUDE.md`, "Iniciar la implementación de un issue").
- **No ejecuta** `db:seed:from-production` contra producción. Para probar el seeder usa una base de origen local con datos de factories.
- No cambia el schema de la API ni migraciones.

### Decisiones (2026-11-06)

1. **`bookings` se sanitiza como propone el punto 2.** `title` es texto libre y puede contener el nombre de una persona; `venue_name` y `maps_url` pueden ser un domicilio. Los tres se reemplazan o se anulan.
2. `extra_products` entra sin sanitizar (catálogo).

### Preguntas abiertas

Ninguna.

### Contexto en Engram

Proyecto `brillipoint-ops`, `topic_key` `issue/brillipoint-ops#7` (`mem_search`, luego `mem_get_observation`). Si contradice este issue, manda el issue.

### Repositorios afectados (pista)

bookandsign-api
