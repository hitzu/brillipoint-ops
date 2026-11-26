chore(observability): error tracking with Sentry for the API and the front

### What

Reportar los errores de producción de la API y del front a Sentry, con el stack legible, el commit que los causó y sin datos personales. En una segunda fase, convertir los errores nuevos en issues `needs-plan` para que entren al flujo de este repo.

### Why

Hoy un error en producción solo se descubre cuando un cliente o un invitado avisa. No sabemos cuántos errores hay, desde cuándo ni con qué cambio empezaron. Para que los agentes arreglen bugs, primero alguien tiene que verlos.

El plan gratuito de Sentry (Developer) incluye 1 usuario y 5,000 errores al mes. Alcanza para nuestro volumen si se controla el ruido.

#### Estado actual verificado (2026-11-22; `bookandsign-api` `main` `3542646`, `bookandsign-front` `main` `1076b95`)

- **Ningún repo tiene seguimiento de errores** (ni Sentry ni otro servicio).
- **API:** NestJS en Render. Registra logs con `nestjs-pino` (`src/main.ts:5`, `:26`). Los logs se quedan en Render y nadie los revisa de forma sistemática.
- **Front:** Next 14 en Vercel (`vercel.json`, `.github/workflows/ci-cd.yml`).
- **App del iPad:** usa `os_log` en 3 archivos. Sin reporte de errores.
- **Print server:** usa `logging` de Python en 18 archivos. Corre local en cada evento, muchas veces sin buena conexión.
- **Las URLs públicas llevan tokens de acceso:** `/reserva/<token>`, `/fiesta/<eventToken>`, `/party/<token>`, `/part/<token>` y `/mis-fotos/<sessionToken>`. Sentry guarda la URL de cada error por defecto.
- **Los repos son públicos** (`brillipoint-ops`, `brillipoint-api`). Lo que se publique en un issue lo puede leer cualquiera.

### Scope

**Entra:**

- SDK de Sentry en la API y en el front.
- Source maps del front y releases con el SHA del commit, subidos desde el CI.
- Limpieza de datos personales antes de enviar: tokens de las URLs, teléfonos, correos, nombres y headers de autorización.
- Alertas por correo para errores nuevos.

**No entra (fases siguientes):**

- La app del iPad y el print server.
- Monitoreo de performance o trazas.

#### Propuesta (punto de partida)

- **Fase 1:** `@sentry/nestjs` en la API y `@sentry/nextjs` en el front. El DSN va por variable de ambiente y el token para subir source maps solo como secret del CI. Un `beforeSend` reemplaza los tokens de las URLs por `<token>` y quita los datos personales.
- **Fase 2:** los errores nuevos crean un issue `needs-plan` con un título limpio y el link al error en Sentry. **El issue no lleva stack trace, URL ni datos del error**, porque el repo es público.
- **Fase 3 (por decidir):** el iPad (`sentry-cocoa`) y el print server, con los errores guardados en la compu mientras no haya conexión.

#### Criterios de aceptación

- Un error provocado en la API de producción aparece en Sentry con su stack, el entorno y el release (SHA del commit).
- Un error provocado en el front aparece con el stack legible (source maps) y el release.
- Ningún evento que llega a Sentry contiene tokens de `/reserva`, `/fiesta`, `/party`, `/part` o `/mis-fotos`, teléfonos, correos ni headers de autorización. Hay un test del `beforeSend` que lo comprueba.
- El DSN y el token de source maps no están en el código. El token no aparece en variables `NEXT_PUBLIC_*`.
- Un error que se repite mucho no agota la cuota del mes (agrupación, muestreo o límite de eventos).
- Si Sentry no responde, la API y el front funcionan igual.
- `pnpm run build` y los tests de la API pasan; el front construye.

#### Preguntas abiertas

1. **¿La fase 1 es solo API y front?** ¿Cuándo entran el iPad y el print server?
2. **¿Hacemos la fase 2 (error → issue)?** Si sí, ¿en este repo público con un issue mínimo, o en un lugar privado?
3. **¿Quién recibe las alertas** y por qué canal (correo, WhatsApp)?
4. **¿Sentry o una alternativa?** Por ejemplo, GlitchTip (compatible con los SDKs de Sentry, se puede alojar nosotros mismos). Sentry gratis tiene 1 solo usuario.
5. **¿Ambientes separados** para producción y sandbox?

#### Riesgos

- Los límites del plan gratuito cambian y las fuentes no coinciden en cuántos días guarda los datos (14 o 30). Hay que confirmarlo en la página oficial de precios antes de decidir.
- Si la limpieza de datos falla, se envían tokens de acceso o datos de clientes a un tercero.
- Un issue automático mal filtrado en un repo público expone información interna.

#### Relación

- Alimenta el flujo de issues de este repo (`needs-plan` → `ready-to-implement`).
- #33 (suite e2e de reserva, dinero y fiesta) cubre los mismos flujos desde los tests. Sentry los cubre en producción.

### Decisiones

Se llenan durante la planeación.

### Affected repositories (hint)

brillipoint-api
brillipoint-front
