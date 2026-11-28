chore(test): Playwright e2e for the reservation, payment and party flows

### What

Una suite end-to-end con Playwright que cubra los flujos que dejan dinero:

1. **Reserva:** el cliente abre `/reserva/<token>` y ve su contrato, los términos, los pagos con su recibo, el cuestionario de preparación y los tatuajes.
2. **Dinero:** el staff crea un contrato y registra un pago, y el pago con su recibo aparece en la reserva del cliente.
3. **Fiesta:** el invitado abre la galería del evento, ve y descarga fotos, y llega al CTA de WhatsApp.

### Why

Estos flujos son los que generan ingresos o traen clientes nuevos. Hoy ningún test los recorre en un navegador, y el CI del front no corre ningún test antes de desplegar. Un cambio en la API o en el front puede romper la reserva o la galería sin que nadie se entere hasta que un cliente avise.

También es la red que necesitan los agentes que implementan issues: con un smoke por flujo, el agente demuestra que su cambio no rompió lo que cobra.

#### Estado actual verificado (2026-11-22; `bookandsign-api` `main` `3542646`, `bookandsign-front` `main` `1076b95`)

- **Front:**
  - Next 14 con pages router. Tests con `vitest` (`yarn test`) y un runner propio para la fiesta (`yarn test:party`, `scripts/run-party-tests.mjs`). No hay Playwright ni Cypress.
  - El CI (`.github/workflows/ci-cd.yml`) corre en push y en PR: instala, construye y despliega a Vercel. **No corre ningún test.**
  - Rutas de los flujos: `src/pages/reserva/[token].tsx`, `src/pages/contracts-add.tsx`, `src/pages/contracts/index.tsx` (con `PaymentsModal`), `src/pages/fiesta/[eventToken].tsx` y `src/pages/mis-fotos/[sessionToken].tsx` (`/party` y `/part` se eliminaron en #39).
- **API:**
  - Jest unitario (`pnpm run test`), e2e con Jest (`pnpm run test:e2e`, `test/contracts.e2e-spec.ts`) y e2e con Bruno (`pnpm run test:e2e:bruno`, `scripts/run-bruno-e2e.sh`).
  - El CI (`.github/workflows/pipeline-main.yml`) levanta `postgres:17-alpine`, corre las migraciones, construye y corre los tests unitarios.
- **Datos:** `scripts/wt-db.sh` (en este repo) crea una base poblada y sanitizada por worktree. Los tests de la API borran el schema de la base que usan.

### Scope

**Entra:**

- Playwright en `brillipoint-front`, con al menos un smoke por flujo (reserva, dinero, fiesta).
- Viewport de celular para la reserva y la fiesta, que es donde los abren los clientes e invitados.
- Datos de prueba deterministas, creados por la propia suite.
- Correr la suite en el CI.

**No entra:**

- Cubrir cada pantalla del staff.
- Pruebas visuales (comparar screenshots).
- La app del iPad y el print server.

#### Propuesta (punto de partida)

- La suite levanta la API (con su base de pruebas) y el front, y crea sus datos con la API: un contrato con paquete, extras, tatuajes y un pago.
- Para la fiesta: un evento con fotos de prueba. Las imágenes pueden ser fixtures pequeños en un bucket de pruebas o un storage simulado.
- Un comando local (`yarn e2e`) y un job de CI.

#### Criterios de aceptación

- `yarn e2e` corre la suite completa en local contra la API y el front locales.
- Reserva: el test abre `/reserva/<token>` en viewport de celular y ve el total, los pagos, el recibo, el cuestionario y la sección de tatuajes.
- Dinero: el test inicia sesión como staff, crea un contrato, registra un pago y verifica que aparece en la reserva del cliente.
- Fiesta: el test abre la galería de un evento, abre una foto, la descarga y ve el CTA de WhatsApp.
- La suite crea sus propios datos y no depende de datos de producción ni del seed sanitizado.
- Un PR al front que rompe cualquiera de los tres flujos falla en el CI.
- La suite corre con `--trace off` por defecto.

#### Preguntas abiertas

1. **¿Dónde corre la API en el CI del front?** Hacer checkout del repo de la API en el job del front, usar una imagen publicada de la API, o correr la suite en un job programado (nightly).
2. **¿Datos creados por la suite o seed sanitizado?** Propuesta: creados por la suite, para que sean deterministas.
3. **¿Qué hacemos con el storage de las fotos en la fiesta?** Bucket de pruebas real o storage simulado.
4. **¿La suite bloquea el despliegue** o solo avisa al principio?
5. **¿Agregamos los tests del front que ya existen (`yarn test`, `yarn test:party`) al CI** en el mismo cambio?

#### Riesgos

- Un e2e que falla al azar es peor que no tener e2e: los agentes y las personas aprenden a ignorarlo. Ya pasa con #9 en la API.
- Levantar la API dentro del CI del front acopla los dos repos. Un cambio de la API puede romper el CI del front.

#### Relación

- #27 cambia la reserva (quita el flag de tatuajes y agrega la medición). Conviene que la suite cubra la reserva ya con tatuajes.
- #9 (tests intermitentes de la API).
- #34 (Sentry) cubre los mismos flujos en producción.

### Decisiones

Se llenan durante la planeación.

### Affected repositories (hint)

brillipoint-front
brillipoint-api
