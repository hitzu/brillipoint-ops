### What

Hacer tolerante al seeder de la API (`npm`/`pnpm run db:seed:from-production`) a un origen (producción) que va **atrás** del schema local, para poder poblar una base local sanitizada sin desplegar migraciones a producción.

### Why

El objetivo del seeder es traer datos de producción a una base local, justo cuando el código local ya tiene migraciones que producción no tiene. Hoy `assertCompatibleSchemas` (`src/database/seeds/seed-from-production.ts`) exige columnas idénticas en las 30 tablas y aborta. Caso real (2026-11-06), al poblar la base del worktree del #3:

```
Source and target columns differ for "brands".
Target-only: [expo_monthly_risk_enabled, min_amount_hold_slot]
```

Cada tabla o columna nueva rompe el seeder hasta que se despliega a producción, lo que le quita el sentido para trabajar en features. Seguimiento de #7.

### Estado actual verificado (2026-11-06)

- `readSchema` y `assertCompatibleSchemas`: `seed-from-production.ts:184-229`. Lanza si una tabla falta en origen o destino, o si hay diferencia de columnas en cualquier sentido (`compareSchemaColumns`, `production-seed.ts`).
- El destino se trunca con `ALL_TABLES` (`seed-from-production.ts:510`) y se inserta solo con `INCLUDED_TABLES` (`:514`).
- `readSchema` consulta `information_schema.columns`, que solo lista tablas sobre las que el rol conectado tiene algún privilegio: una tabla sin permiso en origen es indistinguible de una tabla que no existe.
- El rol de origen es de solo lectura (`SEED_SOURCE_DATABASE_URL`, creado por el equipo). Sus permisos los administra una persona, no el agente.
- Hay `production-seed.spec.ts` con pruebas de políticas y de `compareSchemaColumns`.

### Propuesta (punto de partida)

1. **Columnas solo en destino** (target-only): permitidas si la columna es `NULL`able o tiene `DEFAULT` en el destino (se consulta `information_schema.columns` del destino); el insert no las menciona y la base pone el valor. Si es `NOT NULL` sin default, error que nombra tabla y columna.
2. **Tabla ausente en el origen** (o invisible por permisos): se omite con una advertencia visible; no se copia, pero el destino igual se trunca. Resumen final con la lista de tablas omitidas.
3. **Columnas solo en origen** (origen más nuevo que el local): se mantiene el error actual; el local debe tener al menos el schema de producción ("corre las mismas migraciones").
4. Resumen al terminar: tablas omitidas y columnas rellenadas por default.
5. Tests en `production-seed.spec.ts` para cada regla (1 a 3). Los casos de las reglas existentes que no cambian conservan su comportamiento.
6. Documentar en la ayuda del seeder (`printHelp`) el privilegio que necesita el rol de origen: `SELECT` en las tablas incluidas y al menos `REFERENCES` en las excluidas.

### Decisiones (2026-11-06)

1. **El seeder debe funcionar contra un origen atrasado**; no se resuelve desplegando migraciones a producción: haría inútil el seeder para trabajar features (usuario).
2. Origen más nuevo que el local sigue siendo error (propuesta del agente, aceptada por defecto; revisar si estorba).

### Criterios de aceptación

- Contra un origen sin `expo_monthly_risk_enabled` ni `min_amount_hold_slot` en `brands`, el seed termina y esas columnas quedan con su default en el destino.
- Una tabla ausente del origen produce una advertencia y el seed continúa.
- Una columna `NOT NULL` sin default solo en destino produce un error que nombra tabla y columna.
- Una columna solo en origen sigue abortando.
- `pnpm run build` y `pnpm test` pasan.

### Restricciones

- El agente trabaja en un worktree de `bookandsign-api` con su base de pruebas propia (`CLAUDE.md`, "Iniciar la implementación de un issue").
- **No ejecuta** el seeder contra producción ni abre `.env.prod`. Para probar usa un origen local construido con factories o dos bases locales con schemas distintos.
- La verificación contra producción real la hace una persona con `scripts/wt-db.sh create <n>`.

### Preguntas abiertas

Ninguna.

### Contexto en Engram

Proyecto `brillipoint-ops`, `topic_key` `issue/brillipoint-ops#8` (`mem_search`, luego `mem_get_observation`). Si contradice este issue, manda el issue.

### Repositorios afectados (pista)

bookandsign-api
