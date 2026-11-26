feat(storage): storage usage widget with an alert on the staff home screen

### Problem

Con el storage en Cloudflare R2 (#25), el free tier es de 10 GB-mes. Después se cobra $0.015/GB-mes y **no hay tope de gasto**.

Los eventos duran 30 días. Al vencer, el staff copia los archivos del evento a nuestro servidor de almacenamiento y los borra **a mano**. Hoy nadie ve cuánto espacio se usa, así que no hay forma de saber cuándo toca archivar hasta que llega el cobro.

Hace falta ver el uso de un vistazo en la pantalla principal, y una alerta cuando se acerque al límite.

**Estado actual verificado (2026-11-18; `bookandsign-api` `main` `aed5bcc`, `bookandsign-front` `main` `04e24d4`):**

- **Pantalla principal del staff:** después del login se va a `/` (`src/pages/login.tsx:30`), que redirige a `/agenda` (`next.config.js:44-45`). `src/pages/agenda.tsx` renderiza `AgendaPage` (`src/features/booking-agenda/pages/AgendaPage/index.tsx:20-136`): header con el botón "Nuevo evento", `AgendaNavigation`, `BookingCalendar`, `BookingDetails` y `BookingForm`.
- **Roles:**
  - Existe el enum `USER_ROLE` con `admin` y `sales_agent` (`src/users/constants/user_role.enum.ts`), y los usuarios tienen columna `role`.
  - **No hay `RolesGuard` ni `@Roles`.** Los guards globales son `AuthGuard` y `PhotoboothGuard` (`src/app.module.ts:67-74`).
  - El front no filtra nada por rol.
- **Endpoints de infra:** solo existe `GET /health` (`src/app.controller.ts:15-17`). `POST /admin/reconcile` (`src/reconciliation/reconciliation.controller.ts:6`, `:11`) solo pide sesión. No hay endpoint de estadísticas.
- **Rutas de archivos por evento:** `photobooth/{eventId}/...` (`src/photos/sessions.service.ts:483-484`), legacy `{eventId}/...` (`:208`) y party `{personalized|devoted}/event_{id}/...` (`src/photos/photos.service.ts:234`). Prep-profile va por contrato y los temas por dueño.
- **La base no guarda el tamaño de los archivos:** `Photo` no tiene columna de tamaño (`src/photos/entities/photo.entity.ts`).
- **Fuente de datos en R2:** la GraphQL Analytics API de Cloudflare, dataset `r2StorageAdaptiveGroups`, con `payloadSize`, `metadataSize` y `objectCount` por bucket. Son los mismos datos del dashboard. También existe un endpoint REST de métricas por bucket. Las dos fuentes dan el total del bucket, no el detalle por carpeta.

### Proposal

**API:**

- `GET /admin/storage/usage` (nombre tentativo), solo para `admin`. Requiere un guard de roles mínimo sobre la columna `role` que ya existe.
- Consulta `r2StorageAdaptiveGroups` (`max { payloadSize metadataSize objectCount }`, filtrado por `bucketName`, últimas 24 h) para cada bucket.
- Devuelve, por bucket y en total: bytes y número de objetos, más el límite del free tier y un nivel (`ok`, `warning` o `critical`).
- El token de Cloudflare (permiso de solo lectura de analytics) vive solo en el ambiente de la API. La respuesta se cachea unos minutos para no pegarle a Cloudflare en cada carga de la agenda.

**Front:**

- Un widget compacto en el header de `AgendaPage`, por ejemplo "4.2 GB de 10 GB · 1,830 archivos", con una barra de progreso.
- Amarillo desde el 80%, rojo desde el 100%.
- Solo lo ve `admin`.

**Fase 2 (por decidir):** la lista de eventos vencidos que todavía tienen archivos, con lo que pesa cada uno. Ayuda con el archivado manual. Se puede sacar listando cada carpeta del evento (`ListObjectsV2` sobre `photobooth/{eventId}/`; son operaciones Class A, con 1M gratis al mes) o guardando el tamaño en la base al confirmar cada subida.

### Acceptance criteria

- Un `admin` ve el widget en `/agenda` con el uso de los buckets de producción, y coincide con el dashboard de Cloudflare.
- Un `sales_agent` no ve el widget, y el endpoint le responde `403`.
- Al llegar al 80% del límite, el widget muestra la advertencia; al llegar al 100%, el estado crítico.
- Si Cloudflare falla o falta el token, el widget muestra "Uso no disponible" y la agenda funciona normal. Nunca bloquea la pantalla.
- El token de Cloudflare no aparece en ninguna respuesta ni en variables `NEXT_PUBLIC_*`.
- Hay tests del endpoint con el cliente de Cloudflare simulado: niveles `ok`, `warning`, `critical`, falla de Cloudflare y `403` por rol.
- `pnpm run build` y los tests de la API pasan; el front construye.

### Open questions

1. **Umbrales:** ¿80% y 100% de 10 GB?
2. **¿El total incluye el bucket de sandbox?** Si el free tier es por cuenta (falta verificarlo), sandbox también consume.
3. **¿La alerta vive solo en la pantalla, o también avisa por correo o WhatsApp al cruzar el umbral?** Esto último necesita un cron; la API ya usa `@nestjs/schedule`.
4. **¿La lista de eventos vencidos con su peso entra en la v1 o queda para la fase 2?**
5. **¿Lo ve solo `admin`?**

**Riesgos:**

- La métrica viene de analytics, no es un contador en vivo. Hay que verificar cada cuánto se actualiza.
- El cobro es por GB-mes (promedio del mes), y el widget muestra lo guardado ahora. Un pico de unos días puede superar los 10 GB sin que se cobre. El texto del widget no debe dar a entender lo contrario.
- El guard de roles nuevo toca autenticación. Tiene que ser mínimo y con tests, y no cambiar el acceso de las rutas que ya existen.
- Depende de la migración a R2: sin ella no hay de dónde leer el uso.

**Relación:** depende de #25 (migración del storage a R2).

### Affected repositories (hint)

brillipoint-api
brillipoint-front
