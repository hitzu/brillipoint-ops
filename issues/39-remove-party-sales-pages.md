chore(front): remove the deprecated /party, /part, /sales and /calendar pages and the photo editor

### What

Eliminar del front las páginas que ya no se usan: la página vieja de party (`/party/[token]` y su alias `/part/[token]`) y las páginas de ventas (`/sales` y su versión vieja, `/calendar`). Con la página de party se va la edición de fotos que solo vivía ahí (personalizar y dedicar, con stickers y frases), y en la API, los dos endpoints de subida que solo usaba esa edición.

Los invitados no notan nada: el QR del booth lleva a `/fiesta` y `/mis-fotos`, que siguen igual.

### Why

- La página de party se reemplazó por `/fiesta` y `/mis-fotos`, que es lo que ven hoy los invitados. La edición de fotos se desechó y no va a volver (usuario).
- Las páginas de ventas tampoco se usan (usuario).
- El código muerto estorba en la migración de storage (#25). Las subidas de la edición son las únicas que dejan al cliente elegir el bucket (`storageEnv`, con `NEXT_PUBLIC_SUPABASE_STORAGE_ENV`). Y las páginas de ventas traen 138 URLs fijas a Supabase.

#### Decisiones (2026-11-27)

1. **Se eliminan `/party/[token]`, `/part/[token]` y `/sales`, sin redirección** (usuario). Los eventos que usaban `/party` son viejos: sus links y QR pasan a dar 404.
2. **Se elimina la edición de fotos** (personalizar y dedicar, con stickers y frases) **y sus dos endpoints de subida en la API** (usuario). Los stickers no se migran a R2 (Decisión 19 del #25).
3. **Las fotos del portafolio se eliminan con las páginas** (usuario): `mediaManifest.ts` y sus 138 URLs. No se migran a R2.
4. **`/calendar` también se elimina** (usuario): era la versión vieja de `/sales`. Se va con su copia en `src/template-examples/pages/calendar.tsx`.

#### Estado actual verificado (2026-11-27; `bookandsign-front` `4b11951`, `bookandsign-api` `origin/main` `dff5f5b`, `BrillipointPhotobook-` `main` `2c164b7`)

**Party.**

- `src/pages/party/[token].tsx` y `src/pages/part/[token].tsx` renderizan `PartyPublicPage`. El propio código marca `/party/[token]` como deprecated.
- El QR del iPad arma `/fiesta/...` y `/mis-fotos/...` (`LandingConfig.swift`). Ni la API, ni el iPad, ni el print-server generan links a `/party` o `/part`.
- La edición: `PartyPublicPage` le pasa `onPersonalize` y `onDedicate` a `PhotoViewerLightbox`, que muestra los botones y abre `PersonalizePhotoModal` y `DedicatePhotoModal` (con `PersonalizeCanvas`, `StepCustomizePhoto`, `StepDedicate` y las bandejas de stickers y frases).
- Las subidas de la edición pasan por `uploadPersonalizedPhoto` y `uploadDevotedPhoto`, que usan `partyPersonalizedPhotoService` y `partyDevotedPhotoService`. Estos llaman a `POST photos/event/:eventToken/personalized/upload-url` y `POST photos/event/:eventToken/devoted/upload-url` (`photos.controller.ts`). Son los únicos que usan esos endpoints y `NEXT_PUBLIC_SUPABASE_STORAGE_ENV`.
- **Lo que se queda:**
  - `features/party/` lo comparte `/fiesta`: temas, CTA social, confetti, `LocaleProvider` y `themeVars`.
  - `PhotoViewerLightbox` también lo usa `FiestaPage`: se le quitan los botones de personalizar y dedicar, no se borra.
  - `GET /photos/event/:token` lo usan también `photos-list` y `lib/api.ts`.

**Ventas.**

- `src/pages/sales.tsx` arma secciones de `src/views/Sales/`: calendario, tarifa de traslado y fotos.
- `src/pages/calendar.tsx` (984 líneas) es otra página pública con el mismo estilo (`calendar.module.css`), y también usa `MEDIA_MANIFEST`.
- `src/media/mediaManifest.ts` tiene 138 URLs fijas a Supabase: 68 fotos de "glitter bar" y 70 de "make up".
- Ninguna página del front enlaza a `/sales` ni a `/calendar`.
- `src/template-examples/pages/calendar.tsx` es una copia que también importa el manifiesto. `tsconfig.json` compila todo `**/*.tsx`, así que esa copia rompe el build si el manifiesto se borra y ella queda.

### Scope

**Entra:**

1. Front: borrar las rutas `/party` y `/part`, `PartyPublicPage` y todo lo que solo ella usa, incluida la edición de fotos con sus servicios y utilidades de subida.
2. Front: quitar los botones de personalizar y dedicar de `PhotoViewerLightbox`, y `NEXT_PUBLIC_SUPABASE_STORAGE_ENV`.
3. Front: borrar `/sales` y `/calendar` (`src/pages/sales.tsx`, `src/views/Sales/`, `src/pages/calendar.tsx` y la copia `src/template-examples/pages/calendar.tsx`), `mediaManifest.ts`, y lo que solo usan esas páginas, como los estilos que queden sin uso.
4. API: borrar los dos endpoints de subida de party y el código que solo usan ellos, incluido `storageEnv`.
5. Tests: borrar los que prueban lo eliminado y mantener los que cubren `/fiesta` y `/mis-fotos`.

**No entra:**

- Borrar filas de fotos o archivos ya guardados. El archivo y borrado de eventos sigue como hoy.
- Endpoints de la API que usaban `/sales` o `/calendar` (por ejemplo, los slots): también los usan otras páginas.
- La migración de storage (#25).

#### Criterios de aceptación

- `/party/<token>`, `/part/<token>`, `/sales` y `/calendar` responden 404.
- No queda `mediaManifest.ts`, ni ninguna URL fija al proyecto de Supabase en `src/` (los fixtures de tests con dominios inventados no cuentan).
- `/fiesta/[eventToken]` y `/mis-fotos/[sessionToken]` funcionan igual, incluido el visor de fotos en el celular (descargar y compartir), ahora sin los botones de personalizar y dedicar.
- No quedan en el front la edición de fotos, los stickers, las frases ni `NEXT_PUBLIC_SUPABASE_STORAGE_ENV`.
- La API ya no expone `POST photos/event/:eventToken/personalized/upload-url` ni `.../devoted/upload-url`, y `storageEnv` no aparece en su código.
- El front construye y pasan `yarn test` y `yarn test:party`. La API compila y sus tests pasan.

#### Preguntas abiertas

1. ~~¿`/calendar` también está muerta?~~ Sí (Decisión 4).

#### Riesgos

- **Borrar de más en `features/party/`:** `/fiesta` comparte esa carpeta. Se borra solo lo que deja de tener quién lo use, y se prueban `/fiesta` y `/mis-fotos`.
- Los links o QR viejos a `/party` dan 404. Riesgo aceptado (usuario).

#### Relación

- #25 migración de storage: con esto los stickers no se migran (Decisión 19) y desaparece la parte del paso 0b en la que el front elige el bucket. Se cierra su pregunta 4: las fotos del portafolio no se migran. Este issue va antes del paso 0b del #25.
- #33 e2e: lista `/party` y `/part` entre las rutas a probar. Hay que quitarlas.

### Affected repositories (hint)

brillipoint-front
brillipoint-api

### Cierre

Se eliminaron del front `/party`, `/part`, `/sales` y `/calendar` (404, sin redirección), la edición de fotos con stickers y frases, `mediaManifest.ts` y `NEXT_PUBLIC_SUPABASE_STORAGE_ENV`; en la API se quitaron los dos endpoints `upload-url` de party y `storageEnv`. Se implementó sin Guías (el issue seguía en `needs-plan`), por decisión del usuario, en ramas normales sin worktrees.
Desvíos: también se borraron dos plantillas sin ruta (`template-examples/pages/sales.tsx` y `template-examples/application/contract-edit/[sku].tsx`, esta importaba `views/Sales`), `slotsService.ts` del front (quedó sin uso) y el redirect `/pages/sales` de `next.config.js`.
Verificado: front `tsc`, `yarn test` 820/820, `test:party` 179/179 y `next build`; API jest 956/956. `/fiesta` y `/mis-fotos` se probaron en viewport de celular con la API simulada. No se probó descargar y compartir en un celular real.
Integrado a `main`: `bookandsign-front` `a4b4918` y `bookandsign-api` `f0879c8`.
Contexto en Engram: `issue/brillipoint-ops#39`, proyecto `brillipoint-ops`.

