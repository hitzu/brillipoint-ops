chore(storage): migrate file storage from Supabase to Cloudflare R2 with Terraform

### What

Mover el almacenamiento de archivos de Supabase Storage a Cloudflare R2 (API compatible con S3). La infraestructura (buckets, tokens, CORS, dominio) se define en Terraform, con dos ambientes: sandbox y producción.

La migración es escalonada: cuatro pasos que se despliegan por separado (Decisión 5). Al terminar, el storage queda detrás de un puerto, y cambiar de proveedor se reduce a escribir un adaptador y cambiar la configuración.

No cambia el comportamiento para el staff, los clientes ni el booth: los mismos archivos se suben y se ven igual, solo cambia dónde viven.

### Why

- Estamos cargando más catálogos y vienen los videos (#3). El free tier de Supabase (~1 GB de archivos, 5 GB de salida al mes) no va a alcanzar, y el plan Pro cuesta $25/mes.
- R2 da 10 GB-mes gratis y después cobra $0.015/GB-mes. **La salida es gratis.** Con video, lo que más crece es la descarga (cada vez que un cliente ve o baja un video), y en S3 o Supabase esa salida se cobra a ~$0.09/GB.
- Los eventos duran 30 días. Después, el staff copia los archivos a nuestro servidor de almacenamiento y los borra a mano. Con ese ciclo, el uso se mantiene cerca de los 10 GB. El monitoreo de uso va en un issue aparte (ver "Relación").
- Terraform permite tener sandbox y producción idénticos, y la infraestructura queda versionada.

#### Decisiones (2026-11-18)

1. **Proveedor: Cloudflare R2.** Por la salida gratis y el free tier de 10 GB (usuario).
2. **Infraestructura en Terraform, con sandbox y producción** (usuario).
3. **El borrado de los archivos de eventos sigue siendo manual**, después de archivarlos en nuestro servidor. **No se usan lifecycle rules** sobre los archivos de eventos: podrían borrar un evento antes de archivarlo (usuario).
4. **API y Postgres se quedan en Render; el front, en Vercel.** Se evaluó migrar todo a AWS (Lambda + RDS + S3) y se descartó por ahora:
   - Por costo: RDS `db.t4g.micro` ~$12–15/mes, RDS Proxy ~$22/mes mínimo, NAT Gateway ~$32/mes. Sale igual o más caro que hoy.
   - Por el runtime: el `@Cron('*/5 * * * *')` de `src/reconciliation/reconciliation.service.ts:29` no corre en Lambda, y cada contenedor abriría su propio pool de TypeORM contra una RDS chica.

#### Decisiones (2026-11-20)

5. **Migración escalonada en cuatro pasos** (usuario). Cada paso se despliega solo y deja el sistema funcionando:
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
| Fotos de sesión (legacy) | `{eventId}/{uuid}.{ext}` | `sessions.service.ts:208` |
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
- `next.config.js:55-65` permite imágenes de `*.storage.supabase.co` y `*.supabase.co`.
- `src/media/mediaManifest.ts` tiene **138 URLs absolutas** a un bucket `media` de Supabase (desde la línea `:26`). Son assets estáticos del front.
- `personalizeStickers.ts:8-9` trae una URL base de stickers por default (se puede cambiar con `NEXT_PUBLIC_STICKER_BASE_URL`).
- `NEXT_PUBLIC_SUPABASE_STORAGE_ENV` elige el bucket `local`/`prod` (`uploadDevotedPhoto.ts:45`, `uploadPersonalizedPhoto.ts:45`).
- `calendar.tsx:323` desactiva el optimizador de imágenes de Next para las URLs de Supabase.

**Photobook.**

- El flujo actual pasa por la API: `SessionPhotoUploader.swift` pide URLs firmadas, hace PUT del original y del minimizado, y confirma (`:116`, `:513-516`, `:700`, `:721`, `:790`).
- **Sigue existiendo un camino viejo que sube directo a Supabase**, sin pasar por la API: `SupabasePhotoService.swift:445-464`. Todavía es el servicio de fotos por default (`AppViewModel.swift:160`), y su worker arranca para vaciar una cola guardada (`:215`). `enqueueUpload` no tiene llamadas externas.

**No afectados:** `brillipoint-print-server` (guarda en disco local) y `photos-scripts` (solo procesa imágenes localmente).

**Infraestructura.**

- No hay Terraform ni otra IaC en ningún repo. El deploy de la API es un webhook de Render (`.github/workflows/pipeline-main.yml`, `RENDER_DEPLOY_HOOK_URL`).
- `brillipoint.com` usa el DNS de Vercel (`ns1.vercel-dns.com`, `ns2.vercel-dns.com`; consultado el 2026-11-20).
- Para que R2 sirva desde un dominio propio, ese dominio tiene que ser una zona en la misma cuenta de Cloudflare. La configuración parcial (CNAME), que deja el DNS en otro proveedor, solo existe en los planes Business y Enterprise ([docs](https://developers.cloudflare.com/r2/buckets/public-buckets/)).

### Scope

**Entra:**

1. **Terraform para R2:** buckets por ambiente (sandbox y prod), públicos y privados; CORS para los orígenes del front; tokens de API con permiso solo sobre los buckets de su ambiente; dominio propio para los buckets públicos; state remoto.
2. **API, puerto de storage (paso 0):** un puerto con las operaciones de hoy (subida firmada, lectura firmada, URL pública, listado y borrado) y un adaptador de Supabase que lo implementa. `PhotosService` y la reconciliación dejan su propio cliente. El bucket sale de la configuración del ambiente. Se unifica `STAGE`/`NODE_ENV`.
3. **API, adaptador de R2 (paso 1):** compatible con S3 (`@aws-sdk/client-s3` y `@aws-sdk/s3-request-presigner`).
4. **Rutas relativas (paso 2, Decisión 7):** fotos, imágenes de temas, prep-profile y comprobantes guardan la ruta, y la URL se arma al leer.
5. **Migración de datos:** copiar los objetos a R2 conservando las rutas, y reescribir las URLs de Supabase de `brands.logo_url` y `carousels.image_url`, que no tienen ruta.
6. **Front:** `remotePatterns`, el bucket `media` de `mediaManifest.ts`, la URL base de stickers, quitar `NEXT_PUBLIC_SUPABASE_STORAGE_ENV` y revisar `calendar.tsx:323`.
7. **Photobook:** verificar el PUT firmado contra R2 y retirar `SupabasePhotoService` (después de confirmar que su cola está vacía).
8. **Buckets privados de comprobantes** (`local-priv` y `prod-priv`, creados en #24): se migran igual que el resto.
9. Documentar las variables nuevas en `.env.example`.

**No entra:**

- Mover la API o Postgres fuera de Render. Vercel no cambia.
- El widget de uso con alerta (issue aparte).
- El borrado automático de archivos de eventos (Decisión 3).
- Sippy (Decisión 8).

#### Propuesta (punto de partida)

**Paso 0: puerto de storage (sin cambio de comportamiento, sigue Supabase).**

1. Un puerto con las operaciones de hoy. Los servicios dependen del puerto, no de un SDK.
2. Un adaptador de Supabase que lo implementa. `PhotosService` y la reconciliación pasan a usarlo.
3. El bucket sale de la configuración del ambiente, por rol (por ejemplo: público y privado). `storageEnv` deja de decidir el bucket y `resolvePhotoBucket` desaparece. El contrato con el front y el Photobook todavía no cambia.
4. `STAGE`/`NODE_ENV` se resuelven en una sola función.
5. Los tests del puerto se escriben de forma que después corran igual contra el adaptador de R2 en sandbox.

**Paso 1: redirigir las subidas a R2.**

1. Terraform crea los buckets, CORS, tokens y el dominio.
2. Adaptador de R2. En sandbox se prueba: el PUT firmado desde el front y desde el Photobook (con el `Content-Type` que mandan hoy), el GET firmado, el listado y el borrado.
3. Antes del cambio:
   - Se retira `SupabasePhotoService` del Photobook, con su cola vacía.
   - Se agrega el dominio de R2 a `remotePatterns`, sin quitar el de Supabase.
4. Se copian a mano los objetos de prep-profile y de comprobantes.
5. Se cambia la configuración de la API a R2, en una ventana sin evento activo (la reconciliación lista un solo proveedor).
6. Se vuelven a copiar los de prep-profile y comprobantes subidos entre la copia y el cambio.

Resultado: lo nuevo nace en R2, con URL absoluta de R2, y lo viejo se sigue viendo desde Supabase. Mientras dure este paso, borrar una foto la borra en los dos proveedores, para no copiar huérfanos en el paso 2.

**Paso 2: copiar lo existente y volver relativas las rutas.**

1. Copiar el resto con `rclone` (Supabase Storage expone protocolo S3), conservando las rutas. Como todo lo nuevo ya nace en R2, basta una copia.
2. Conteo en seco antes de cambiar la lectura:
   - Fotos de prod cuyo `public_url` no esté en el bucket del ambiente.
   - `brands.logo_url` y `carousels.image_url`, por dominio.
3. La API deja de leer `public_url`, `minimized_public_url` y el `url` de las imágenes de temas. Arma la URL desde la ruta. Las respuestas siguen trayendo la URL.
4. Se reescriben a R2 las URLs de Supabase de `brands.logo_url` y `carousels.image_url`, con respaldo antes.
5. Front: `mediaManifest.ts` y la URL base de stickers (según la pregunta 4).

**Paso 3: quitar Supabase.**

1. Se borra el adaptador de Supabase, `@supabase/supabase-js` y las variables `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_STORAGE_BUCKET` y `NEXT_PUBLIC_SUPABASE_STORAGE_ENV`.
2. Se quitan del front el dominio de Supabase en `remotePatterns` y la excepción de `calendar.tsx:323`.
3. Se quitan del contrato `storageEnv` y el `{bucket}/` de `photoPath`. Se borra `SupabasePhotoService`.
4. Se eliminan las columnas `public_url` y `minimized_public_url` con una migración, con respaldo antes.
5. Los buckets de Supabase quedan intactos un tiempo como respaldo (pregunta 10). Después se vacían.

#### Criterios de aceptación

- Cada tipo de subida cae en el bucket de R2 de su ambiente y se ve igual que hoy: fotos del booth (original y minimizada), fotos de party (personalized y devoted), assets de temas, prep-profile y tatuajes, y comprobantes.
- Durante el paso 1, las fotos viejas se siguen viendo desde Supabase y las nuevas desde R2.
- Después de la migración, las fotos, imágenes de temas, logos, carruseles y assets estáticos existentes se ven desde R2.
- Ninguna respuesta de la API ni fila de la base apunta a una URL de storage de Supabase. Una consulta de conteo por el dominio de Supabase en las columnas afectadas da `0`.
- Fuera de los adaptadores, ningún archivo de la API importa `@supabase/supabase-js` ni `@aws-sdk/*`.
- Borrar una foto funciona sin leer el bucket de la URL.
- El cron de reconciliación lista R2 y reconcilia igual que hoy.
- El token de sandbox no puede leer ni escribir en los buckets de producción.
- `terraform plan` después de `apply` no muestra cambios en ninguno de los dos ambientes.
- El Photobook sube a R2 por el flujo firmado, incluida la cola offline (#6).
- Las páginas públicas cargan las imágenes por el optimizador de Next con el dominio nuevo.
- `pnpm run build` y los tests de la API pasan; el front construye.

#### Preguntas abiertas

1. **¿Dónde vive el Terraform?** Opciones: un repo nuevo (por ejemplo `brillipoint-infra`), una carpeta en `bookandsign-api`, o este repo (que por regla no implementa nada).
2. **Dominio para R2.** `brillipoint.com` está en el DNS de Vercel, y R2 necesita que el dominio sea una zona de Cloudflare (ver "Infraestructura"). El subdominio `r2.dev` tiene límite de requests y Cloudflare dice que no es para producción. Opciones:
   - Mover los nameservers de `brillipoint.com` a Cloudflare (plan gratis). Hay que recrear los registros de Vercel y los del correo.
   - Usar otro dominio, solo para archivos.
3. ~~URLs guardadas~~. Resuelta en la Decisión 7.
4. **Assets estáticos (`media`, 138 URLs):** ¿a un bucket público de R2 o a `public/` del front en Vercel?
5. **Sandbox:** hoy existen `local` y `prod`. ¿Sandbox es el actual `local` (desarrollo y worktrees) o un ambiente nuevo hospedado?
6. **Postgres:** la variable se llama `SUPABASE_DB_URL` (`src/config/database/index.ts:15`), pero el usuario dice que la base está en Render. Hay que confirmar dónde vive. Solo importa para saber si se puede dar de baja el proyecto de Supabase al terminar.
7. **Orden con el #3 (video):** ¿se migra antes de la fase 4 del video, para que los videos nazcan en R2?
8. **Cola vieja del Photobook:** ¿algún dispositivo tiene pendientes en la cola de `SupabasePhotoService`?
9. **Buckets en R2:** ¿los mismos que en Supabase (`local`, `prod`, `public`, `local-priv` y `prod-priv`) o uno público y uno privado por ambiente? Sin Sippy ya no hace falta mantenerlos 1 a 1.
10. **Respaldo:** ¿cuánto tiempo quedan intactos los buckets de Supabase después del paso 2?

#### Riesgos

- **Cambios de datos difíciles de revertir:** reescribir `brands.logo_url` y `carousels.image_url` (paso 2) y eliminar `public_url` y `minimized_public_url` (paso 3). Hace falta respaldo antes y una corrida en seco que cuente las filas afectadas.
- **Los PUT firmados de S3 son estrictos con los headers:** si la firma incluye `Content-Type`, el cliente tiene que mandar exactamente ese valor. El front manda `params.mime` o `application/octet-stream`; falta verificar lo que manda el Photobook.
- R2 no es 100% compatible con S3. Antes del paso 1 hay que probar en sandbox las operaciones que usamos: PUT y GET firmados, listado y borrado.
- R2 no tiene tope de gasto: pasado el free tier, cobra. Falta verificar si los 10 GB son por cuenta o por bucket. Lo conservador es asumir que sandbox y prod los comparten.
- **Volver atrás desde el paso 1 no es gratis.** Si la configuración regresa a Supabase, lo nuevo con URL absoluta de R2 se sigue viendo, pero prep-profile y comprobantes nuevos (solo guardan la ruta) dejan de verse.
- La reconciliación lista un solo proveedor. Si hay un evento activo durante el cambio, pueden quedar fotos en `PROCESSING`. Por eso el cambio va en una ventana sin evento activo.
- Lo que se suba a prep-profile o comprobantes entre la copia manual y el cambio se recupera con la segunda copia. Si se salta ese paso, se pierden archivos.
- La inconsistencia `NODE_ENV` vs `STAGE` puede hacer que la reconciliación lea el bucket equivocado. Se unifica en el paso 0.

#### Relación

- El widget de uso con alerta va en un issue aparte que depende de este.
- #3 video end to end, por el orden de la fase 4.
- #6 cola de subida diferida del booth.
- #24 comprobantes de pago: creó los buckets privados `local-priv` y `prod-priv`, que se migran aquí.

### Affected repositories (hint)

brillipoint-api
brillipoint-front
BrillipointPhotobook-
