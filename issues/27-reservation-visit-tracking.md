feat(booking): measure client visits and interactions on the public reservation page

### Problem

Queremos usar `/reserva/<token>` como punto de venta (por ejemplo, que el cliente agregue extras desde ahí). Antes de decidir cómo, hace falta saber **si el cliente regresa** a esa página o si solo la abre una vez:

- Si entra una sola vez, vender ahí obliga a ser muy insistentes en esa única visita.
- Si regresa, hay que saber qué lo hace regresar para reforzarlo.

Es buen momento para medir. Ya hay varios contratos vendidos para el próximo año, y está por liberarse el autoservicio de tatuajes, que es una razón nueva para volver. Si la medición sale antes que los tatuajes, tendremos datos de antes y de después.

Hoy esa página no registra nada.

**Estado actual verificado (2026-11-20; `bookandsign-api` `main` `3542646`, `bookandsign-front` `main` `1076b95`; revisado 2026-11-23 con `bookandsign-front` `main` `3761a82`):**

- **La página funciona por pestañas.** Se ve una sola a la vez: `resume`, `prep_bride`, `prep_social`, `tattoos` y `terms` (`SectionId` en `ReservationPublicPage.tsx`). Todo cambio de pestaña pasa por `selectSection`. La pestaña no queda en la URL, así que cada visita empieza en "Resumen". "Resumen" apila bloques: cliente, fechas, servicios, extras contratados (`ReservationExtrasSection`), pagos y notas.
- **Los términos son una sola lista larga.** `TermsAndConditions.tsx` muestra juntos los términos globales, de marca y de paquete, sin colapsar.
- **La página no registra nada.** `ReservationPublicPage` (`src/features/booking/pages/ReservationPublicPage.tsx`) carga el contrato con `getContractByToken(token)` (`:99`), que llama a `GET /contracts/get-by-token/:token` (`src/contracts/contracts.controller.ts:95`). Ningún archivo de `src/features/booking` ni de `src/pages/reserva` llama a `trackEvent`.
- **Lo que la página ya ofrece (razones para volver):**
  - Un aviso de vista previa mientras el contrato no tiene pagos (`src/features/booking/components/ReservationPreviewNotice.tsx:9`). El cliente revisa el contrato, sobre todo los términos, antes del primer pago.
  - El cuestionario de preparación (`PreparationSection.tsx`). Se guarda por contrato con `/contracts/public/:token/prep-profile/...` (`contracts.controller.ts:105-193`).
  - Los pagos con recibo PDF (`ReservationFinanceSection.tsx:162-169`, de #24).
  - Los tatuajes. Hoy solo aparecen con `?tatuajes=true` (`TATTOO_PREVIEW_QUERY_PARAM`, `src/features/booking/utils/tattooDesigns.ts:24`, leído en `ReservationPublicPage.tsx:171-173`). Para subir diseños hay que verificar el teléfono (`usePublicContractPhoneGate`, `TattooDesignsSection.tsx:75`).
- **La analítica que ya existe no sirve tal cual.**
  - `event_analytics` depende del evento: `event_token` es FK a `events.token` con `onDelete: 'CASCADE'` (`src/events/entities/event-analytic.entity.ts:9-14`).
  - Un contrato no tiene evento hasta que el staff lo crea con `POST /events` (`src/events/events.service.ts:68`). Nada en `contracts` ni en `bookings` crea el evento. Los contratos del próximo año probablemente todavía no tienen evento.
  - `POST /event-analytics/track` exige un `eventToken` UUID y una `action` del enum cerrado `AnalyticsAction` (`src/events/analytics/dto/track-action.dto.ts:6-7`).
  - Lo demás ya cabe en la tabla. `action` es `varchar(64)` y `source` es `varchar(32)`, así que las acciones y fuentes nuevas solo tocan los enums del DTO, sin migración. Ya existen `session_id` (`uuid`), `surface` (`varchar(64)`), `metadata` (`jsonb`) y `user_agent`.
  - Todas las consultas actuales filtran por `event_token` (`getSummary`, `getActions`, `getSourceSummary` y `getExpired` en `event-analytics.service.ts`). Las filas de contrato sin evento no se mezclan con las métricas de invitados.
  - El seeder sanitizado no copia `event_analytics` (`EXCLUDED_TABLES` en `src/database/seeds/production-seed.ts`).
- **El cliente del front se puede reusar como patrón.** `trackEvent` (`src/api/services/eventAnalyticsService.ts:17-41`) no espera la respuesta, ignora los errores y usa axios sin token.
- **Visitas del staff.** El staff suele abrir el link del cliente para revisarlo o mandarlo. El front guarda la sesión en `localStorage` como `authToken` (`src/hooks/useAuthToken.ts:15`). Solo el login del staff guarda ese token (`src/pages/login.tsx`). Se borra al cerrar sesión (`src/stores/authStore.ts`) y cuando una petición autenticada responde `401` (`src/api/config/axiosConfig.ts`).
- **El staff ya se separa en Fiesta, pero registrándolo.** La lista de eventos abre `/fiesta/<token>?source=admin_page` (`src/pages/event-list.tsx`), para excluir esas visitas en las consultas. `trackEvent` se llama en 19 lugares (Fiesta, galería, fotobooth, Inspiración, evento expirado, partners), y algunos se disparan al cargar la página (`GALLERY_OPENED` en un `useEffect` de `FiestaPage.tsx`).
- **Ya hay una señal histórica.** `contract_preparation_profiles` hereda `created_at` y `updated_at` de `BaseTimeEntity` (`contract-preparation-profile.entity.ts:10`). Junto con `answers`, dice qué contratos ya usaron el cuestionario. Sirve como base parcial sin esperar a la medición nueva.

### Proposal

**API:**

- Extender `event_analytics` para que una fila pertenezca a un evento o a un contrato:
  - `event_token` pasa a nullable. Solo se quita el `NOT NULL`: no cambian el tipo, el largo, la FK ni el `CASCADE`.
  - Columna nueva `contract_id`, nullable, FK a `contracts` y con índice.
  - Un `CHECK` que exige `event_token` o `contract_id`.
  - Lo demás va en columnas que ya existen: `session_id`, `source` (valor nuevo `reservation`), `surface` (la pestaña o el bloque), `metadata` y `user_agent`.
- Un endpoint público `POST /contracts/public/:token/track`, igual que los de prep-profile. Resuelve el contrato por el token, acepta solo acciones de una lista cerrada y no bloquea la página.
- Sin endpoint de lectura ni pantalla en esta versión. Las preguntas se responden con consultas SQL sobre `event_analytics`.

**Acciones (tentativas):**

| Acción | Cuándo | `surface` / `metadata` |
|---|---|---|
| `reservation_viewed` | Al cargar la página o cuando vuelve a quedar visible | `entry`: `navigate`, `reload`, `back_forward` o `resume`. En `resume`, `hiddenMs`. Además `visitorId`, `hasPayments`, `daysToEvent` |
| `reservation_section_viewed` | Al cargar (pestaña inicial) y en cada cambio de pestaña | `surface`: la pestaña. `trigger`: `landing` o `click` |
| `reservation_section_left` | Al cambiar de pestaña o al salir de la página | `visibleMs`, solo el tiempo con la pestaña del navegador visible. En `terms`, además `maxScrollPct`, `reachedEnd` y `wordCount` |
| `reservation_block_viewed` | Cuando un bloque de "Resumen" entra en pantalla, una vez por sesión | `surface`: el bloque (`services`, `extras`, `finance`, `notes`…) |
| `reservation_receipt_opened` | Al abrir un recibo | — |
| `reservation_prep_answered` | Al guardar el cuestionario | — |
| `reservation_tattoo_uploaded`, `reservation_tattoo_selected` | Al subir o elegir un diseño | — |

**Preguntas que responde la medición.** El front manda datos crudos. Los umbrales (qué es una visita, qué es "leyó") se aplican en las consultas SQL, así que se pueden ajustar sin volver a desplegar.

1. **¿Cuántas veces regresa el cliente?** Una visita nueva es una entrada que no es `reload` y llega al menos 10 minutos después de la actividad anterior del mismo visitante. Los regresos son las visitas después de la primera. Los 10 minutos son un parámetro de la consulta.
2. **¿A dónde entra más?** Pestañas abiertas con `trigger: click` y su `visibleMs`. `landing` no cuenta como elección, porque toda carga de la página empieza en "Resumen".
3. **¿Lee los términos?** Abrió "Términos" y los tuvo visibles al menos ~20 s.
4. **¿Los lee completos?** `reachedEnd` y un `visibleMs` de al menos ~30 % del tiempo estimado de lectura (`wordCount / 230` palabras por minuto). Esto mide exposición, no lectura.
5. **¿Dónde conviene el upsell?** Se cruzan tres datos de las visitas de regreso: la primera pestaña o acción (qué lo trae), dónde pasa más tiempo y el `daysToEvent` (cuándo regresa).

Todo se puede cruzar con `hasPayments` para separar la vista previa de las visitas después del primer pago.

**Front:**

- Un `visitor_id` anónimo en `localStorage`. Distingue "la misma persona regresó" de "otra persona abrió el link" (por ejemplo, la pareja).
- Cada entrada se registra con su tipo. `navigate`, `reload` y `back_forward` salen de `PerformanceNavigationTiming.type`. `resume` es la página que vuelve a quedar visible sin recargar, por ejemplo, una pestaña que quedó abierta. Sin `resume`, ese regreso no deja rastro.
- Un `session_id` por carga de la página, para agrupar los eventos de esa carga. No define la visita.
- Si el navegador tiene `authToken` en `localStorage` (sesión de Brillipoint), no se manda ningún evento.

**Liberar los tatuajes (quitar el flag):**

- Hoy el flag es solo el parámetro `?tatuajes=true`. Se lee en un único lugar, `ReservationPublicPage.tsx:171-175`, junto con `hasTattooDesignsInContract` (`src/features/booking/utils/tattooDesigns.ts:73`).
- Al quitarlo, la sección de tatuajes aparece sola en los contratos que incluyen tatuajes y en ningún otro. Se borran `TATTOO_PREVIEW_QUERY_PARAM` e `isTattooPreviewEnabled` (`tattooDesigns.ts:24-27`) y se actualizan sus tests.

**Fuera de este issue:** una sección de medición para el staff, con las visitas por contrato y reportes agregados (% de contratos que regresan, mediana de visitas, pestañas de las visitas de regreso). Va en otro issue.

### Acceptance criteria

- Abrir `/reserva/<token>` registra una visita del contrato, aunque el contrato todavía no tenga evento.
- Cada entrada queda registrada con su tipo (`navigate`, `reload`, `back_forward` o `resume`). Las consultas no cuentan una recarga como visita nueva, y sí cuentan un regreso a una pestaña que quedó abierta. El mismo navegador cuenta como el mismo visitante.
- Un navegador con `authToken` en `localStorage` no registra ningún evento, ni en `/reserva` ni en las páginas que usan `trackEvent` (Fiesta, Mis fotos, Inspiración…). Tampoco el primero que se dispara al cargar la página. Un navegador sin token registra igual que hoy.
- Si el registro falla, la página funciona igual.
- Las consultas SQL que responden las cinco preguntas de la propuesta se entregan versionadas y se prueban contra la base del worktree.
- Las visitas anteriores al primer pago (vista previa) se distinguen de las posteriores.
- La medición y la liberación de los tatuajes salen en el mismo deploy. Ninguna de las dos llega a producción sin la otra.
- Sin `?tatuajes=true`, la sección de tatuajes aparece en un contrato que incluye tatuajes y no aparece en uno que no los incluye.
- La visita no guarda teléfono, IP ni otros datos personales del cliente.
- Al salir de una pestaña queda registrado cuánto tiempo estuvo visible. En "Términos" queda además hasta dónde bajó y si llegó al final.
- La migración solo contiene estos cambios: el `DROP NOT NULL` de `event_token`, el `ADD COLUMN` de `contract_id`, su FK, su índice y el `CHECK`. No tiene `DROP COLUMN`, no recrea ninguna columna existente y no cambia ningún tipo ni largo. `down()` es el inverso exacto. Después de aplicarla, `pnpm run db:gen` responde que no hay cambios.
- Fuera de las visitas del staff, las métricas de invitados no cambian. Los resúmenes por evento siguen filtrando por `event_token` y los tests de `event-analytics.service` siguen pasando.
- Tests de la API: el registro con token válido funciona; un token inexistente responde `404` y no guarda nada; una acción fuera de la lista responde `400`.
- `pnpm run build` y los tests de la API pasan; el front construye.

### Open questions

Ninguna.

**Riesgos:**

- El link se comparte (pareja, familia). Los visitantes únicos son las personas que abrieron el link, no las personas del contrato.
- `visitor_id` en `localStorage` se pierde en modo incógnito o al cambiar de navegador. La misma persona puede contar como dos visitantes.
- `event_analytics` va a tener filas sin `event_token`. Una consulta nueva de invitados que no filtre por evento las mezclaría con las del contrato.
- Revertir la migración cuando ya hay visitas falla: el `SET NOT NULL` de `down()` choca con las filas de contrato. Habría que borrar esas filas antes, y eso borra la medición.
- TypeORM borra y vuelve a crear una columna, con pérdida de datos, cuando cambia su tipo, su largo o si es array (`changeColumn` en `typeorm/driver/postgres/PostgresQueryRunner.js`, v0.3.27). Si solo cambia `nullable`, genera un `ALTER COLUMN ... DROP NOT NULL`. Por eso la entidad no debe tocar el tipo ni el largo de `event_token`.
- **Riesgo aceptado (2026-11-23):** `POST /contracts/public/:token/track` es público. Cualquiera con el link puede inflar las visitas de ese contrato. La protección contra abuso queda fuera de este issue.
- **Riesgo aceptado (2026-11-23):** un dispositivo del staff sin token (cerró sesión, recibió un `401` o nunca inició sesión) registra eventos como si fuera cliente o invitado. Descartado: marcar para siempre en `localStorage` el navegador que alguna vez tuvo sesión.
- **Riesgo aceptado (2026-11-20):** como la medición y los tatuajes salen juntos, no habrá datos de cómo se usaba la página sin tatuajes. La única referencia anterior es la base parcial del cuestionario de preparación.

**Relación:** va antes de vender extras desde `/reserva` (borrador `issues/contract-addendum.md`). Mide el efecto del autoservicio de tatuajes (#20, #21, #22).

### Decisiones

- **2026-11-20:** el autoservicio de tatuajes no se libera antes de que la medición esté en producción.
- **2026-11-20:** quitar el flag de tatuajes (`?tatuajes=true`) entra en este issue, para que la liberación quede atada a la medición.
- **2026-11-20:** la medición y la liberación de los tatuajes salen en el mismo deploy. Se aceptó perder los datos de antes. Descartado: medir primero y quitar el flag unas dos semanas después, porque se prefiere asegurar que salgan juntos.
- **2026-11-23:** se extiende `event_analytics`: `event_token` pasa a nullable y se agrega `contract_id`. Descartado: una tabla nueva `contract_page_events`, porque el nombre de la tabla ya describe lo que guarda y el volumen esperado no justifica separarlas.
- **2026-11-23:** esta versión mide dónde conviene colocar el upsell: atención por pestaña y bloque, y qué hace regresar al cliente. Medir la intención de compra (por ejemplo, una tarjeta de extras que solo registra el clic) queda fuera de este issue.
- **2026-11-23:** la migración no puede borrar ni recrear columnas existentes. El archivo que genere `pnpm run db:gen` se revisa completo antes de aplicarlo y se descarta si trae cualquier otro cambio.
- **2026-11-23:** se registra cada entrada a la página sin agruparla en el front, y la visita se calcula en la consulta. Se aceptó que las recargas lleguen a la tabla, porque se detectan al consultar. Descartado: una sesión de 30 minutos en el front, porque la pantalla inicial se revisa en unos 2 minutos y esa ventana juntaría regresos reales (por ejemplo, el cliente comenta algo por WhatsApp y vuelve).
- **2026-11-23:** se registran las entradas `resume`. Un regreso a una pestaña que quedó abierta no recarga la página y, sin este evento, no deja rastro.
- **2026-11-23:** esta versión no tiene endpoint de lectura ni pantalla para el staff: las preguntas se responden con SQL. Una sección de medición va en otro issue. Descartado: mostrar las visitas en el detalle del contrato, porque todavía no existe una sección de medición donde ponerlas.
- **2026-11-23:** un dispositivo con sesión de Brillipoint (`authToken` en `localStorage`) no registra eventos en `/reserva`. Descartado: registrar la visita marcada como staff y excluirla en SQL, porque se prefiere no guardar esas visitas.
- **2026-11-23:** la misma regla aplica a las páginas de invitados que usan `trackEvent`. `?source=admin_page` existía para excluir al staff en las consultas; es mejor no registrarlo. Consecuencia aceptada: también dejan de contar las visitas del staff que no llegaban con `admin_page` (por QR o link directo), así que los números de invitados bajan un poco desde el deploy.

### Contexto en Engram

- Proyecto: `brillipoint-ops`
- `topic_key`: `issue/brillipoint-ops#27`

### Affected repositories (hint)

brillipoint-api
brillipoint-front
