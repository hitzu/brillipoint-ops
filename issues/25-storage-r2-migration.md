chore(storage): migrate file storage from Supabase to Cloudflare R2

### What

Mover el almacenamiento de archivos de Supabase Storage a Cloudflare R2 (API compatible con S3). Los buckets, su CORS y el dominio se crean con un script de wrangler, en dos ambientes: `local` y `prod` (Decisiones 15 y 16).

La migración es escalonada: cuatro pasos que se despliegan por separado (Decisión 5). Al terminar, el storage queda detrás de un puerto, y cambiar de proveedor se reduce a escribir un adaptador y cambiar la configuración.

No cambia el comportamiento para el staff, los clientes ni el booth: los mismos archivos se suben y se ven igual, solo cambia dónde viven.

### Why

- Estamos cargando más catálogos y vienen los videos (#3). El free tier de Supabase (~1 GB de archivos, 5 GB de salida al mes) no va a alcanzar, y el plan Pro cuesta $25/mes.
- R2 da 10 GB-mes gratis y después cobra $0.015/GB-mes. **La salida es gratis.** Con video, lo que más crece es la descarga (cada vez que un cliente ve o baja un video), y en S3 o Supabase esa salida se cobra a ~$0.09/GB.
- Los eventos duran 30 días. Después, el staff copia los archivos a nuestro servidor de almacenamiento y los borra a mano. Con ese ciclo, el uso se mantiene cerca de los 10 GB. El monitoreo de uso va en un issue aparte (ver "Relación").
- Un script idempotente de wrangler deja `local` y `prod` iguales y versionados, sin la carga de Terraform para 4 buckets fijos.

#### Decisiones (2026-11-18)

1. **Proveedor: Cloudflare R2.** Por la salida gratis y el free tier de 10 GB (usuario).
2. **Infraestructura en Terraform, con sandbox y producción** (usuario). Reemplazada por la Decisión 15 (2026-11-27).
3. **El borrado de los archivos de eventos sigue siendo manual**, después de archivarlos en nuestro servidor. **No se usan lifecycle rules** sobre los archivos de eventos: podrían borrar un evento antes de archivarlo (usuario).
4. **API y Postgres se quedan en Render; el front, en Vercel.** Se evaluó migrar todo a AWS (Lambda + RDS + S3) y se descartó por ahora:
   - Por costo: RDS `db.t4g.micro` ~$12–15/mes, RDS Proxy ~$22/mes mínimo, NAT Gateway ~$32/mes. Sale igual o más caro que hoy.
   - Por el runtime: el `@Cron('*/5 * * * *')` de `src/reconciliation/reconciliation.service.ts:29` no corre en Lambda, y cada contenedor abriría su propio pool de TypeORM contra una RDS chica.

#### Decisiones (2026-11-20)

5. **Migración escalonada en cuatro pasos** (usuario). Cada paso se despliega solo y deja el sistema funcionando. El paso 0 se parte en dos (Decisión 14):
   0. Puerto de storage, sin cambio de comportamiento (sigue Supabase).
   1. Redirigir las subidas a R2.
   2. Copiar lo existente y volver relativas las rutas.
   3. Quitar Supabase.
6. **El storage pasa a ser un puerto con adaptadores** (usuario). Hoy no lo es: `StorageService` es una clase concreta cuyo contrato expone conceptos de Supabase, y `PhotosService` tiene su propio cliente (ver "Estado actual"). El bucket sale de la configuración del ambiente, nunca del cliente ni de la URL guardada.
7. **Rutas relativas** (resuelve la pregunta 3; usuario). La base guarda solo la ruta y la URL se arma al leer, con una sola función del adaptador.
   - Se hace en el paso 2, **después** de copiar todo a R2. Con una sola URL base, el cambio de lectura aplica a todas las filas a la vez.
   - Durante el paso 1 se siguen guardando URLs absolutas, para que cada fila apunte al proveedor donde vive su archivo.
8. **Sin Sippy** (usuario). Se descartó Sippy, la migración bajo demanda de R2: sirve desde R2 y copia del origen lo que todavía falta.
   - Solo hacía falta para lo que guarda únicamente la ruta: prep-profile, que casi no tiene archivos, y comprobantes, que son pocos. Esos se copian a mano antes del paso 1.
   - Cloudflare no lo probó con Supabase como origen.

#### Decisiones (2026-11-27)

9. **Variables agnósticas del proveedor** (usuario). Las variables de storage usan el prefijo `MEDIA_STORAGE_` (en el front, `NEXT_PUBLIC_MEDIA_STORAGE_`). Ningún nombre menciona al proveedor.
   - Nacen en el paso 0b. Los nombres de bucket (`SUPABASE_STORAGE_BUCKET`, `STORAGE_PRIVATE_BUCKET`) pasan a `MEDIA_STORAGE_*` ahí mismo.
   - `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` quedan solo como configuración del adaptador de Supabase y se borran con él en el paso 3.
10. **Los secretos de storage viven solo en Render** (usuario). El front y el Photobook nunca reciben credenciales del proveedor: suben y leen con las URLs firmadas que emite la API.
11. **El Photobook queda sin Supabase** (usuario): ni código, ni configuración, ni el paquete `supabase-swift`. El Photobook no conoce al proveedor ni arma URLs de storage.
    - Va **antes del paso 1**, no en el 3: hoy el Photobook arma la URL del GIF con el formato de Supabase (ver "Estado actual"). Si las subidas ya van a R2, esa URL apunta a un archivo que no existe.
    - **El GIF se elimina completo** (usuario): la funcionalidad murió hace tiempo, y `startGIFGeneration` ya no tiene llamadas. Así no hace falta cambiar el contrato para devolver su URL.
12. **Operaciones de Cloudflare con costo controlado** (usuario). R2 cobra por operación pasado el free tier y no tiene tope de gasto.
    - Ningún proceso se dispara por escrituras en un bucket: este issue no usa event notifications ni Workers. Un proceso que escribe donde se dispara se vuelve a llamar, y cada vuelta cobra operaciones.
13. **Las variantes se quedan en el iPad** (usuario). La minimizada y el poster del video los sigue generando el iPad. No se usa Cloudflare (Workers, Queues, event notifications ni transformaciones) para procesar archivos.
    - En el iPad cuestan casi nada: el poster es el primer cuadro, que ya está en memoria mientras se compone el MP4.
    - Un trigger del bucket arriesga recursión y cobra operaciones. Las transformaciones gratis se acaban en 5,000 al mes y, pasado el tope, las nuevas fallan.
14. **Orden de trabajo** (usuario). El paso 0 se parte en dos, y cada parte se despliega sola:
    - **0a. Photobook sin Supabase.** Solo toca el Photobook.
    - **0b. API y front.** El puerto de storage y las variables `MEDIA_STORAGE_*`; el front deja de elegir el bucket. Sigue Supabase.
      - 2026-11-27: la parte del front la absorbe el #39, que va antes. El 0b queda solo en la API.
    - Después, el paso 1: lo nuevo se guarda en R2 mientras se migra lo viejo.

#### Decisiones (2026-11-27, segunda parte)

15. **Sin Terraform: los buckets se crean con un script de wrangler** (usuario). Reemplaza la Decisión 2.
    - Son 4 buckets fijos, con su CORS y un dominio, que casi no cambian. Terraform (state remoto, provider y, como `bookandsign-api` es público, un repo privado aparte) cuesta más de lo que aporta.
    - El script vive en `bookandsign-api/scripts/` y es idempotente: se puede correr varias veces sin cambiar nada. No contiene secretos: se autentica con la sesión local de wrangler.
    - Los tokens de la API (uno por stage, limitado a sus buckets) se crean a mano en el dashboard y van directo a Render. No pasan por el script ni por el repo.
    - Si la infraestructura crece (zona DNS, Vercel, Render), se reconsidera Terraform en un repo privado.
16. **Dos buckets por stage: uno público y uno privado** (usuario): `brillipoint-local-public`, `brillipoint-local-private`, `brillipoint-prod-public` y `brillipoint-prod-private`. R2 no acepta guiones bajos en los nombres.
    - `local` es el ambiente de desarrollo y worktrees; no hay un sandbox hospedado aparte.
    - Público: fotos del booth y de party, videos, temas, prep-profile y tatuajes, carruseles y logos, separados por prefijo. Privado: comprobantes. El privado no tiene dominio ni `r2.dev`: solo se lee con URL firmada.
    - R2 no tiene permisos por archivo: público o privado es una propiedad del bucket.
    - El código pide el bucket por rol (eventos, assets y privado) y la configuración da el nombre. En Supabase, las fotos y los assets viven en buckets distintos; en R2, los roles de eventos y assets apuntan al mismo bucket público.
    - Los archivos de eventos se borran a mano por sus prefijos (`photobooth/{id}/`, `personalized/event_{id}/` y `devoted/event_{id}/`), nunca por `{número}/`: prep-profile usa `{contractId}/` en la raíz del mismo bucket.
17. **Logos y carruseles: key con fallback** (usuario). `brands.logo_url` y `carousels.image_url` no tienen ruta. Se les agrega una columna de key que puede quedar vacía, se llena al copiar el archivo, y la lectura usa la key y cae a la URL guardada si no hay.
    - Reemplaza la reescritura de esas URLs: no pisa ningún dato, y volver atrás es ignorar la columna.
    - En fotos y temas no aplica: la ruta ya existe en todas las filas (`photos.storage_path` es `NOT NULL`), así que tener key no indica en qué proveedor vive el archivo. Ahí sigue la Decisión 7.
18. **El DNS de `brillipoint.com` se muda a Cloudflare (plan gratis); la app sigue en Vercel** (usuario). Resuelve la pregunta 2.
    - El bucket público de prod se sirve en `media.brillipoint.com`. `r2.dev` queda solo para `local`.
    - Solo se mueve el DNS: los registros que hoy apuntan a Vercel se recrean en Cloudflare en modo "DNS only", y la app, los deploys y el SSL siguen en Vercel. La API sigue en el dominio de Render.
    - Se descartó guardar todo en el bucket privado y leerlo con URLs firmadas: las URLs vencen, cambian con cada firma (se pierde la caché del navegador y la de Next) y no hay CDN. Tampoco ahorra dinero: el dominio también es gratis.
19. **Los stickers no se migran** (usuario, 2026-11-27). Se agregaron para la edición de fotos, que fue desechada, y se eliminan junto con ella.
    - Viven en `media/stickers/` del Supabase actual (`personalizeStickers.ts`). No se copian a R2.
    - Ojo: la edición sigue montada. En la página pública de party (`PartyPublicPage`), el lightbox de fotos en móvil (`PhotoViewerLightbox`) muestra los botones de personalizar y dedicar, que abren `PersonalizePhotoModal` y `DedicatePhotoModal`. Solo se llega desde la ruta vieja `/party/[token]`: el QR lleva a `/fiesta` y `/mis-fotos`. Se elimina en el #39.

#### Estado actual verificado (2026-11-18, actualizado 2026-11-20)

Commits leídos, todos en `main`: `bookandsign-api` `3542646` (incluye #24), `bookandsign-front` `1076b95`, `BrillipointPhotobook` `7ae36f8`, `brillipoint-print-server` `fe780f6`, `photos-scripts` `e9bebea`.

**API: hay dos clientes de Supabase, y ninguno es un puerto.**

- `StorageService` (`src/common/storage/storage.service.ts`) es una clase concreta, sin interfaz ni token de inyección. La inyectan directo prep-profile, theme-assets y payments.
  - Lee `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` (`:19-38`).
  - Bucket público: `SUPABASE_STORAGE_BUCKET`, con default `'public'` (`:40-43`). Bucket privado: `STORAGE_PRIVATE_BUCKET`, que falla si no está configurado (`:50-60`). Payments lo usa para los comprobantes (`src/payments/payments.service.ts:84-100`).
  - `getPublicUrl` arma la URL con el formato de Supabase, `/storage/v1/object/public/<bucket>/<path>` (`:62-70`).
  - `createSignedReadUrl` (`:72-88`) y `createSignedUploadUrl` (`:90-105`). Esta última devuelve un `token` propio de Supabase. No se encontró ningún cliente que lo lea.
  - No tiene método para borrar.
- `PhotosService` crea **su propio cliente** con las mismas variables (`src/photos/photos.service.ts:56-74`):
  - `createStorageUploadUrl` (`:76-87`), `getPublicUrl` (`:89-99`), `listFiles` (`:312-318`) y `removeFromStorage` (`:373-393`).
  - `resolvePhotoBucket` **saca el nombre del bucket de la URL guardada** con una regex (`:396-407`). Esto se rompe cuando cambie el formato de la URL.
  - `bulkSeed` (solo para pruebas) tiene fija la URL del proyecto de Supabase (`:270-273`).

**API: hay tres esquemas para elegir el bucket.**

- `SUPABASE_STORAGE_BUCKET`, para prep-profile (incluye tatuajes) y assets de temas.
- `local` / `prod`, derivado de `STAGE`/`NODE_ENV`, para las fotos del booth (`src/photos/sessions.service.ts:603-610`). La reconciliación usa solo `NODE_ENV` (`src/reconciliation/reconciliation.service.ts:88-91`), y eso es inconsistente con lo anterior.
- Para las fotos de party, **el cliente manda el nombre del bucket** en `storageEnv` (`photos.service.ts:228-233`).
- El Photobook recibe el bucket en el contrato: `photoPath` llega como `{bucket}/{path}` (`sessions.service.ts:507`, `:511`).

**API: rutas de los objetos.**

| Tipo | Ruta | Evidencia |
|---|---|---|
| Fotos del booth (v2) | `photobooth/{eventId}/{uuid}.jpg` y `photobooth/{eventId}/minimized/{uuid}.jpg` | `sessions.service.ts:483-484` |
| Fotos de sesión (legacy) | `{eventId}/{uuid}.{ext}` | `sessions.service.ts:208`; `SessionsService.createUploadUrl` ya no tiene endpoint ni llamadas (`origin/main` `dff5f5b`, 2026-11-27) |
| Fotos de party | `{personalized\|devoted}/event_{id}/{uuid}.jpg` | `photos.service.ts:234` |
| Prep-profile y tatuajes | `{contractId}/{questionId}/{uuid}_{name}` | `src/contracts/preparation-profile/prep-profile-uploads.service.ts:123` |
| Assets de temas | `themes/{folder}/{ownerId}/{slot}/{uuid}_{name}` | `theme-asset-uploads.service.ts:68` |

- El cron de reconciliación corre cada 5 minutos y lista `photobooth/{eventId}` (`reconciliation.service.ts:29-37`).

**API: la base guarda URLs absolutas de Supabase.**

- `photos.public_url` y `photos.minimized_public_url` (`src/photos/entities/photo.entity.ts`), junto a `storage_path` y `minimized_storage_path`.
  - Se escriben en `sessions.service.ts:244`, `:526-527` y en `reconciliation.service.ts:52`. `photos.service.ts:199` guarda la URL que manda el cliente.
  - Las respuestas de galería y sesión devuelven esas URLs tal cual (`sessions.service.ts:125`, `:175`, `:574-580`).
  - `storage_path` y `minimized_storage_path` **ya son relativas al bucket**. `public_url` es la URL base, más el bucket del ambiente, más esa ruta. Por eso volver relativas las fotos no exige reescribir datos, solo dejar de leer `public_url`.
- Imágenes de temas: `ThemeImageAssetDto` exige `path` **y** `url` absoluta (`src/events/dto/event-theme/theme-images.dto.ts:51`, `:60`). Se guardan en el jsonb `event_themes.images` y en `events.theme_overrides`. Como el `path` ya existe, el `url` se puede armar al leer.
- Prep-profile guarda solo `{path, mime}`, y la URL se arma al leer (`prep-profile-assets.mapper.ts:34-38`). **Ese patrón ya resuelve el problema.** Los comprobantes también guardan solo la ruta, en el bucket privado.
- `brands.logo_url` (`src/brands/entities/brand.entity.ts:15-16`) y `carousels.image_url` (`src/carousels/entities/carousel.entity.ts:32-33`) guardan solo la URL, sin ruta. El front no tiene una pantalla para subirlos. Falta ver qué dominio tienen los datos.
- Las variables de storage no están en `.env.example`. Solo aparecen en el código.

**Front (Next.js 14, en Vercel).**

- Todas las subidas son un `fetch` PUT a la URL firmada con `Content-Type`, sin `@supabase/supabase-js`: `partyPersonalizedPhotoService.ts:25-26`, `partyDevotedPhotoService.ts:25-26`, `themeAssetsService.ts:22-23`, `prepProfileService.ts:85-86` y `paymentService.ts:104-105`. Es la misma forma que pide un PUT firmado de S3.
- Verificado de nuevo el 2026-11-27 (`4b11951`): `package.json` no trae SDKs de storage y el front no tiene ninguna key de storage. De Supabase solo quedan lecturas públicas (`mediaManifest.ts` y stickers) y la elección del bucket con `NEXT_PUBLIC_SUPABASE_STORAGE_ENV`.
- `next.config.js:55-65` permite imágenes de `*.storage.supabase.co` y `*.supabase.co`.
- `src/media/mediaManifest.ts` tiene **138 URLs absolutas** a un bucket `media` de Supabase (desde la línea `:26`). Son assets estáticos del front.
- `personalizeStickers.ts:8-9` trae una URL base de stickers por default (se puede cambiar con `NEXT_PUBLIC_STICKER_BASE_URL`).
- `NEXT_PUBLIC_SUPABASE_STORAGE_ENV` elige el bucket `local`/`prod` (`uploadDevotedPhoto.ts:45`, `uploadPersonalizedPhoto.ts:45`).
- `calendar.tsx:323` desactiva el optimizador de imágenes de Next para las URLs de Supabase.

**Photobook.**

- El flujo actual pasa por la API: `SessionPhotoUploader.swift` pide URLs firmadas, hace PUT del original y del minimizado, y confirma (`:116`, `:513-516`, `:700`, `:721`, `:790`).
- **Sigue existiendo un camino viejo que sube directo a Supabase**, sin pasar por la API: `SupabasePhotoService.swift:445-464`. Todavía es el servicio de fotos por default (`AppViewModel.swift:160`), y su worker arranca para vaciar una cola guardada (`:215`). `enqueueUpload` no tiene llamadas externas.
- Revisado de nuevo el 2026-11-27, en `main` `2c164b7` (ya incluye el video de #3):
  - `SessionPhotoUploader.publicURL(from:)` arma la URL del GIF con el formato de Supabase, a partir de `SupabaseEnv.url` y del `{bucket}/{path}` que devuelve la API.
  - El GIF es código muerto: `AppViewModel.startGIFGeneration` no tiene llamadas. `SupabaseClientProvider` tampoco tiene usos.
  - La cola vieja de `SupabasePhotoService` no recibe trabajos nuevos, pero su worker arranca al abrir la app y sube directo a Supabase lo que tenga guardado. La pantalla solo muestra sus pendientes: sus fallidos no aparecen en ningún contador (`pendingCount()` y `failedUploadsCount`).
  - `SupabaseEnv` (URL y key del proyecto) lo usan `SupabasePhotoService`, `SupabaseClientProvider` y `publicURL(from:)`.
  - `SupabaseService` no habla con Supabase: es el cliente de la API (`fetchEvent(byKey:)` llama a `/v2/events/by-key`). Solo el nombre es de Supabase.
  - El paquete `supabase-swift` está en `project.pbxproj` y en `Package.resolved`.
  - El iPad genera hoy las variantes: la minimizada en `PhotoVariantGenerator` (lado largo 1080, calidad 0.5) y el poster del video en `VideoClipComposer` (el primer cuadro, mientras compone el MP4). `SessionVideoUploader` sube el MP4 y el poster.

**No afectados:** `brillipoint-print-server` (guarda en disco local) y `photos-scripts` (solo procesa imágenes localmente).

**Infraestructura.**

- No hay Terraform ni otra IaC en ningún repo. El deploy de la API es un webhook de Render (`.github/workflows/pipeline-main.yml`, `RENDER_DEPLOY_HOOK_URL`), que corre en cada push a `main`.
- `bookandsign-api` es un repo público.
- DNS público de `brillipoint.com` (consultado el 2026-11-27): registrador Name.com; el dominio raíz y `www` apuntan a Vercel, y hay un comodín `*` que también apunta a Vercel. No hay MX (no hay correo en el dominio) ni DNSSEC. Los CAA autorizan a `pki.goog`, `sectigo.com` y `letsencrypt.org`. El front no enruta por subdominio: el host solo se usa para armar la URL absoluta de la landing de partners.
- `brillipoint.com` usa el DNS de Vercel (`ns1.vercel-dns.com`, `ns2.vercel-dns.com`; consultado el 2026-11-20).
- Para que R2 sirva desde un dominio propio, ese dominio tiene que ser una zona en la misma cuenta de Cloudflare. La configuración parcial (CNAME), que deja el DNS en otro proveedor, solo existe en los planes Business y Enterprise ([docs](https://developers.cloudflare.com/r2/buckets/public-buckets/)).

### Scope

**Entra:**

1. **Script de wrangler para R2 (Decisiones 15 y 16):** `bookandsign-api/scripts/r2-setup.sh <local|prod>`, idempotente. Crea los dos buckets del stage, aplica el CORS para los orígenes del front, y configura `r2.dev` y el dominio de cada bucket. Los tokens se crean a mano.
2. **API, puerto de storage (paso 0b):** un puerto con las operaciones de hoy (subida firmada, lectura firmada, URL pública, listado y borrado) y un adaptador de Supabase que lo implementa. `PhotosService` y la reconciliación dejan su propio cliente. El bucket sale de la configuración del ambiente. Se unifica `STAGE`/`NODE_ENV`.
3. **API, adaptador de R2 (paso 1):** compatible con S3 (`@aws-sdk/client-s3` y `@aws-sdk/s3-request-presigner`).
4. **Rutas relativas (paso 2, Decisión 7):** fotos, imágenes de temas, prep-profile y comprobantes guardan la ruta, y la URL se arma al leer.
5. **Migración de datos:** copiar los objetos a R2 conservando las rutas. `brands.logo_url` y `carousels.image_url` reciben una key con fallback (Decisión 17).
6. **Front:** `remotePatterns`. El manifiesto `media` (`mediaManifest.ts`), los stickers, `NEXT_PUBLIC_SUPABASE_STORAGE_ENV` y `calendar.tsx` se eliminan en el #39.
7. **Photobook sin Supabase (Decisión 11):** eliminar el GIF completo; retirar `SupabasePhotoService` (después de confirmar que su cola está vacía), `SupabaseClientProvider`, `SupabaseEnv` y el paquete `supabase-swift`; renombrar `SupabaseService`; verificar el PUT firmado contra R2.
8. **Buckets privados de comprobantes** (`local-priv` y `prod-priv`, creados en #24): se migran igual que el resto.
9. Variables `MEDIA_STORAGE_*` (Decisión 9), documentadas en `.env.example`.

**No entra:**

- Mover la API o Postgres fuera de Render. Vercel no cambia.
- El widget de uso con alerta (issue aparte).
- El borrado automático de archivos de eventos (Decisión 3).
- Sippy (Decisión 8).
- Terraform (Decisión 15).
- Renombrar `SUPABASE_DB_URL`: es configuración de la base, no de storage. Va en un issue aparte.
- Los stickers y la edición de fotos que los usa (Decisión 19): se limpian en el #39.
- Event notifications, Workers y cualquier proceso disparado por el bucket (Decisión 12).
- Generar en el servidor las variantes que hoy hace el iPad (minimizada y poster de video). Descartado (Decisión 13).

#### Propuesta (punto de partida)

**Paso 0a: Photobook sin Supabase (Decisiones 11 y 14; solo el Photobook). Va en su propio issue, #38.**

1. Eliminar el GIF completo.
2. Retirar `SupabasePhotoService`, `SupabaseClientProvider`, `SupabaseEnv` y el paquete `supabase-swift`. Renombrar `SupabaseService`, que es el cliente de la API.

**Paso 0b: puerto de storage y front (sin cambio de comportamiento, sigue Supabase).**

1. Un puerto con las operaciones de hoy. Los servicios dependen del puerto, no de un SDK.
2. Un adaptador de Supabase que lo implementa. `PhotosService` y la reconciliación pasan a usarlo.
3. El bucket sale de la configuración del ambiente, por rol (por ejemplo: público y privado). `storageEnv` deja de decidir el bucket y `resolvePhotoBucket` desaparece. El contrato con el front y el Photobook todavía no cambia.
4. `STAGE`/`NODE_ENV` se resuelven en una sola función.
5. Los tests del puerto se escriben de forma que después corran igual contra el adaptador de R2 en `local`.
6. Variables `MEDIA_STORAGE_*` (Decisión 9). Se dan de alta en Render antes del deploy.
7. Nada del front: `storageEnv` y `NEXT_PUBLIC_SUPABASE_STORAGE_ENV` desaparecen con el #39.

**Paso 1: redirigir las subidas a R2.**

1. Con el DNS ya en Cloudflare (Decisión 18), el script crea los buckets, el CORS y el dominio `media.brillipoint.com`. Los tokens se crean a mano y se cargan en Render.
2. Adaptador de R2. En `local` se prueba: el PUT firmado desde el front y desde el Photobook (con el `Content-Type` que mandan hoy), el GET firmado, el listado y el borrado.
3. Antes del cambio:
   - El Photobook ya no tiene Supabase (paso 0a).
   - Se agrega el dominio de R2 a `remotePatterns`, sin quitar el de Supabase.
4. Se copian a mano los objetos de prep-profile y de comprobantes.
5. Se cambia la configuración de la API a R2, en una ventana sin evento activo (la reconciliación lista un solo proveedor).
6. Se vuelven a copiar los de prep-profile y comprobantes subidos entre la copia y el cambio.

Resultado: lo nuevo nace en R2, con URL absoluta de R2, y lo viejo se sigue viendo desde Supabase. Mientras dure este paso, borrar una foto la borra en los dos proveedores, para no copiar huérfanos en el paso 2.

**Paso 2: copiar lo existente y volver relativas las rutas.**

1. Antes de copiar, contar las fotos cuyo `storage_path` no empiece con `photobooth/`, `personalized/` o `devoted/` (restos del camino viejo). Compartirían la raíz del bucket con prep-profile (Decisión 16): si hay, se archivan y se borran, o se mueve prep-profile bajo un prefijo.
2. Copiar el resto con `rclone` (Supabase Storage expone protocolo S3), conservando las rutas. Fotos, temas y prep-profile van al bucket público del stage; los comprobantes, al privado. Como todo lo nuevo ya nace en R2, basta una copia.
3. Conteo en seco antes de cambiar la lectura:
   - Fotos de prod cuyo `public_url` no esté en el bucket del ambiente.
   - `brands.logo_url` y `carousels.image_url`, por dominio.
4. La API deja de leer `public_url`, `minimized_public_url` y el `url` de las imágenes de temas. Arma la URL desde la ruta. Las respuestas siguen trayendo la URL.
5. Logos y carruseles: se llena su key al copiar el archivo; la lectura usa la key y cae a la URL guardada si no hay (Decisión 17).

**Paso 3: quitar Supabase.**

1. Se borra el adaptador de Supabase, `@supabase/supabase-js` y las variables `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`.
2. Se quita del front el dominio de Supabase en `remotePatterns`.
3. Se quita del contrato el `{bucket}/` de `photoPath`. `storageEnv` ya lo quitó el #39.
4. Se eliminan las columnas `public_url` y `minimized_public_url` con una migración, con respaldo antes.
5. Los buckets de Supabase quedan intactos 3 días como respaldo (pregunta 10). Después se vacían y se da de baja el proyecto de Supabase: la base vive en Render (pregunta 6).

#### Criterios de aceptación

- Cada tipo de subida cae en el bucket de R2 de su ambiente y se ve igual que hoy: fotos del booth (original y minimizada), fotos de party (personalized y devoted), assets de temas, prep-profile y tatuajes, y comprobantes.
- Durante el paso 1, las fotos viejas se siguen viendo desde Supabase y las nuevas desde R2.
- Después de la migración, las fotos, imágenes de temas, logos y carruseles existentes se ven desde R2.
- Ninguna respuesta de la API ni fila de la base apunta a una URL de storage de Supabase. Una consulta de conteo por el dominio de Supabase en las columnas afectadas da `0`.
- Fuera de los adaptadores, ningún archivo de la API importa `@supabase/supabase-js` ni `@aws-sdk/*`.
- Ninguna variable de storage de la API ni del front menciona al proveedor; todas usan `MEDIA_STORAGE_`.
- El Photobook no tiene referencias a Supabase (código, configuración ni paquete) y no arma URLs de storage.
- Ningún proceso se dispara por escrituras en un bucket de R2.
- Borrar una foto funciona sin leer el bucket de la URL.
- El cron de reconciliación lista R2 y reconcilia igual que hoy.
- El token de `local` no puede leer ni escribir en los buckets de `prod`.
- Correr `r2-setup.sh` dos veces seguidas no cambia nada, en los dos stages. El bucket privado no responde ni por `r2.dev` ni por un dominio.
- El Photobook sube a R2 por el flujo firmado, incluida la cola offline (#6).
- Las páginas públicas cargan las imágenes por el optimizador de Next con el dominio nuevo.
- `pnpm run build` y los tests de la API pasan; el front construye.

#### Preguntas abiertas

1. ~~¿Dónde vive el Terraform?~~ No hay Terraform (Decisión 15). El script vive en `bookandsign-api/scripts/`.
2. ~~Dominio para R2~~. Resuelta en la Decisión 18 (2026-11-27). Contexto original: `brillipoint.com` está en el DNS de Vercel, y R2 necesita que el dominio sea una zona de Cloudflare (ver "Infraestructura"). El subdominio `r2.dev` tiene límite de requests y Cloudflare dice que no es para producción. Opciones:
   - Mover los nameservers de `brillipoint.com` a Cloudflare (plan gratis). Hay que recrear los registros de Vercel y los del correo.
   - Usar otro dominio, solo para archivos.
   - Usar `r2.dev` también en prod, aceptando su límite de requests.
   - 2026-11-27 (usuario): el DNS no se muda por ahora. `brillipoint.com` apunta a Vercel y la API usa el dominio de Render, sin un `api.` propio. Se decide antes del paso 1 en prod: los pasos 0a y 0b no necesitan dominio, y `local` usa `r2.dev`. Más tarde, el mismo día, se decidió mudar solo el DNS, al aclarar que la app no se mueve de Vercel (Decisión 18).
3. ~~URLs guardadas~~. Resuelta en la Decisión 7.
4. ~~Assets estáticos (`media`, 138 URLs)~~. No se migran: se eliminan con `/sales` y `/calendar` en el #39 (usuario, 2026-11-27). Eran 68 fotos de "glitter bar" y 70 de "make up" (portafolio).
5. ~~Sandbox~~. Es `local`: desarrollo y worktrees (Decisión 16).
6. ~~Postgres~~. La base vive en Render (usuario, 2026-11-27); `SUPABASE_DB_URL` es solo un nombre heredado. La API usa Supabase únicamente para storage (`storage.service.ts` y `photos.service.ts`), así que el proyecto de Supabase se puede dar de baja al terminar. Renombrar la variable va en un issue aparte.
7. ~~Orden con el #3 (video)~~. El #3 se cerró el 2026-11-20, antes de esta migración: los videos que ya existan se copian en el paso 2, como el resto.
8. ~~Cola vieja del Photobook~~. Está vacía y lleva meses sin usarse (usuario, 2026-11-27). Se borra sin migrar sus trabajos (#38).
9. ~~Buckets en R2~~. Uno público y uno privado por stage (Decisión 16).
10. ~~Respaldo~~. 3 días (usuario, 2026-11-27): no hay nada crítico ahí.

#### Riesgos

- **Cambios de datos difíciles de revertir:** eliminar `public_url` y `minimized_public_url` (paso 3). Hace falta respaldo antes y una corrida en seco que cuente las filas afectadas.
- **Los PUT firmados de S3 son estrictos con los headers:** si la firma incluye `Content-Type`, el cliente tiene que mandar exactamente ese valor. El front manda `params.mime` o `application/octet-stream`; falta verificar lo que manda el Photobook.
- R2 no es 100% compatible con S3. Antes del paso 1 hay que probar en `local` las operaciones que usamos: PUT y GET firmados, listado y borrado.
- R2 no tiene tope de gasto: pasado el free tier, cobra. Falta verificar si los 10 GB son por cuenta o por bucket. Lo conservador es asumir que `local` y `prod` los comparten.
- **Volver atrás desde el paso 1 no es gratis.** Si la configuración regresa a Supabase, lo nuevo con URL absoluta de R2 se sigue viendo, pero prep-profile y comprobantes nuevos (solo guardan la ruta) dejan de verse.
- La reconciliación lista un solo proveedor. Si hay un evento activo durante el cambio, pueden quedar fotos en `PROCESSING`. Por eso el cambio va en una ventana sin evento activo.
- Lo que se suba a prep-profile o comprobantes entre la copia manual y el cambio se recupera con la segunda copia. Si se salta ese paso, se pierden archivos.
- La inconsistencia `NODE_ENV` vs `STAGE` puede hacer que la reconciliación lea el bucket equivocado. Se unifica en el paso 0b.
- **Renombrar variables en Render:** si el deploy del paso 0b sale antes de dar de alta las `MEDIA_STORAGE_*`, la API arranca sin bucket. Se dan de alta primero.
- Prep-profile guarda en `{contractId}/`, en la raíz del bucket público. Riesgo aceptado (usuario, 2026-11-27): tiene pocos archivos, y si estorba se mueve bajo un prefijo sin problema.
- Cambiar el CORS de un bucket con dominio propio puede dejar respuestas viejas en la caché de Cloudflare. Después de cambiarlo, se purga la caché de ese dominio.

#### Relación

- El widget de uso con alerta va en un issue aparte que depende de este.
- #3 video end to end, por el orden de la fase 4.
- #6 cola de subida diferida del booth.
- #38 Photobook sin Supabase: es el paso 0a.
- #39 elimina `/party`, `/part`, `/sales`, `/calendar` y la edición de fotos. Va antes del paso 0b. Con eso desaparece la parte del paso 0b en la que el front elige el bucket (`storageEnv`), y se cierra la pregunta 4: las fotos del portafolio no se migran.
- #24 comprobantes de pago: creó los buckets privados `local-priv` y `prod-priv`, que se migran aquí.
- Generar en el servidor las variantes que hoy hace el iPad: descartado (Decisión 13). No se abre issue.

### Affected repositories (hint)

brillipoint-api
brillipoint-front
BrillipointPhotobook-
