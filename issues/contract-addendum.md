feat(contracts): contract addendum that supersedes the previous snapshot and shows the client what changed

### Problem

Ya nos está pasando que las condiciones de un contrato cambian después de crearlo (se agrega o quita un paquete o un extra, cambia una cantidad o un precio). Hoy no hay una forma formal de hacerlo: el snapshot del contrato se edita en sitio, sin historial, o directamente no se puede editar.

Necesitamos un **addendum**: una modificación que deja **cancelado (reemplazado) el snapshot anterior** y crea uno nuevo. El cambio se tiene que ver en la página de reservas del cliente y el staff necesita una sección nueva de **editar contrato**. El cliente ve siempre los productos y precios vigentes (la última modificación); lo anterior queda guardado como reemplazado, no se sobrescribe.

**Estado actual (verificado en el código, `bookandsign-api` y `bookandsign-front`, rama `main`):**

- **Snapshot del contrato:**
  - Son las filas de `contract_packages`, `contract_extras` y `contract_promotions` (`src/contracts/entities/contract.entity.ts:123-139`). Guardan `name_snapshot`, `base_price_snapshot`, `discount_percentage_snapshot`, `final_price_snapshot` e `items_snapshot` (los extras además `is_gift`).
  - `subtotal`, `discount_total` y `total` los recalcula el servidor a partir de esas filas (`recalculateTotals`, `src/contracts/contracts.service.ts:118-158`).
  - El transporte vive fuera del snapshot (`contract.entity.ts:76-96`) y se suma al saldo (`computeBalanceDue`, `contracts.service.ts:626-632`).
- **No hay versiones del snapshot.** Lo que existe edita en sitio y sin historial:
  - `PATCH /contracts/:id/items/:itemId` cambia `quantity` y recalcula (`contracts.service.ts:553-582`).
  - `DELETE /contracts/:id/items/:itemId` hace soft delete del paquete (`contracts.service.ts:584-605`).
  - `POST /contracts/:id/items` es un stub que solo hace `console.log` (`contracts.service.ts:391-392`, `contracts.controller.ts:200-208`).
  - No hay endpoints para editar extras ni promociones de un contrato ya creado.
  - Esas operaciones reciben `actorUserId` pero lo descartan (`void actorUserId`): no queda registro de quién cambió qué.
- **Estados del contrato:** `confirmed`, `cancelled`, `active`, `inactive`, `finalized` (`src/contracts/types/contract-status.types.ts`). `cancel` y `reopen` cambian el estado del contrato completo (`contracts.service.ts:721-757`); no hay nada a nivel de snapshot.
- **Aceptación del cliente:** no encontré campos de firma o aceptación en `src/contracts`. La página pública dice que el contrato es una "vista previa" hasta que se registra el primer pago (`bookandsign-front/src/features/booking/components/ReservationPreviewNotice.tsx:8-14`).
- **Términos y condiciones** no forman parte del snapshot: la página de reservas los pide en vivo (global, marca y paquete) (`bookandsign-front/src/features/booking/pages/ReservationPublicPage.tsx:110-142`).
- **Front:**
  - Página de reservas del cliente: `src/pages/reserva/[token].tsx` → `ReservationPublicPage` (`src/features/booking/pages/ReservationPublicPage.tsx:48`). La sección "Resumen" muestra servicios, extras y finanzas (`:186-206`) y lee `GET /contracts/get-by-token/:token` (`getDetailByToken`, `contracts.service.ts:822-870`).
  - Staff: lista de contratos en `src/pages/contracts/index.tsx` (enlaza a `/reserva/<token>`, `:168`) y creación en `src/features/contracts-add/pages/CreateContractPage.tsx`. **No existe pantalla de edición de contrato** y el front no llama a los endpoints de items (no aparecen en `src/api/services/contractService.ts`).

**Relacionado:** #15 (invitados en el contrato, también sin `PATCH` general de contratos) y la idea pendiente de cargos libres en el snapshot (IVA, comisión), que todavía no es issue.

### Proposal

Punto de partida; la planeación lo afina.

**Decisiones tomadas con el usuario (2026-11-11):**

- El addendum es **informativo**: el cliente no lo acepta ni lo firma. Descartado: aceptación con fecha y hora en la página de reservas, porque ya hubo firmas y la gente no firmaba, y en la práctica el documento funciona como recibo.
- La página de reservas muestra **solo la revisión activa** (productos y precios de la última modificación). Descartado: mostrarle al cliente el antes y después línea por línea; fue un malentendido del planteamiento original.
- Las revisiones reemplazadas **se guardan siempre**; la pantalla para que el staff consulte el historial **queda fuera de este issue**. Mientras tanto se consulta en la base de datos, y con eso el staff puede responderle al cliente qué se agregó y cómo era el contrato original.
- **Alcance del addendum:** solo lo que vive en el snapshot: paquetes, extras, cantidades, regalos y promociones. Fechas (`POST /bookings/:id/reschedule`), transporte (`PATCH /contracts/:id/transport`), términos y datos del cliente quedan fuera, porque se modifican sin tocar el snapshot.
- **Tentativo:** los costos por servicio, que se definen en otro issue que sale antes y todavía no está definido. Si terminan guardándose en el snapshot, el addendum también los versiona.
- **Precios de lo nuevo:** las líneas que agrega un addendum se calculan como al crear el contrato: precio del catálogo del paquete o extra y la promoción activa de la marca al momento del addendum. Descartado: precio fijado a mano por el staff y heredar la promoción original del contrato. Lo normal es agregar o quitar un servicio o un extra.
- **Precios de lo que no cambia:** las líneas que siguen igual conservan el precio y el descuento de A; no se recalculan aunque el catálogo o la promoción hayan cambiado. Descartado: recalcular B completo como contrato nuevo, porque el cliente vería subir algo que nadie tocó. Las promociones no se crean a la ligera; si una da problemas, el staff la desactiva a mano en promociones.
- **(2026-11-12) Total menor a lo pagado:** se permite. Si el cálculo de saldo da negativo, la reserva muestra "Saldo a favor" con la diferencia, al cliente y al staff. Qué se hace con ese dinero se resuelve fuera del sistema. Es raro, porque el finiquito se paga el día del evento, pero tiene sentido en la lógica de negocio. Descartado: bloquear el addendum, porque impediría registrar que se quitó un servicio.
- **(2026-11-12) Un solo camino para cambiar el snapshot:** se retiran `PATCH /contracts/:id/items/:itemId`, `DELETE /contracts/:id/items/:itemId` y el stub `POST /contracts/:id/items`; todo cambio a paquetes y extras pasa por `POST /contracts/:id/addenda`. Ningún cliente los consume (ni el front, ni el Photobook, ni el print server). Los demás endpoints del contrato (pagos, transporte, cancelar, reabrir, finalizar, slots) siguen igual.

**Modelo: snapshot versionado dentro del mismo contrato.** El contrato conserva su `id`, su `token` (la misma URL de reserva) y sus pagos; lo que se versiona es el snapshot.

- Tabla nueva `contract_revisions`: `contract_id`, `revision_number`, `status` (`active` | `superseded`), `reason` (motivo visible para el cliente), `created_by_user_id`, `created_at` y los totales de esa revisión.
- `contract_packages`, `contract_extras` y `contract_promotions` agregan `revision_id`. Las filas de una revisión reemplazada no se modifican ni se borran.
- Migración: cada contrato existente recibe su revisión 1 con el snapshot actual.

**Operación de addendum (API):**

- `POST /contracts/:id/addenda` recibe el snapshot completo nuevo (paquetes, extras, cantidades, regalos) y el motivo. En una sola transacción: crea la revisión N+1 con filas nuevas, marca la N como `superseded`, recalcula los totales y deja la N+1 como activa.
- `GET /contracts/get-by-token/:token` devuelve solo la revisión activa, con la misma forma que hoy.
- La vista previa del staff (A → B antes de confirmar) usa un diff calculado en el servidor: agregado, eliminado, modificado y totales antes y después.
- Escalones de extras: un extra que se quita no mueve el descuento de los que quedan. Un extra nuevo toma la siguiente posición contando los extras que siguen en B bajo el mismo paquete y la misma promoción, que es la regla actual de `setExtras` (`contracts.service.ts:397-470`).
- Los pagos siguen en el contrato. El saldo se calcula contra el total de la revisión activa, más transporte, menos lo pagado. Hoy `computeBalanceDue` recorta a 0 (`contracts.service.ts:626-632`); el excedente se expone sin cambiar el significado de `balanceDue` (por ejemplo, un campo nuevo `creditBalance`), para no romper a quien ya lo consume.

**Front:**

- **Staff, "Editar contrato" (sección nueva):** precarga la revisión activa, permite editar paquetes, extras, cantidades y regalos, pide el motivo y muestra la vista previa A → B antes de confirmar.
- **Cliente, página de reservas:** sin cambios de diseño; muestra los productos, precios, total y saldo de la revisión activa.

### Acceptance criteria

- **Addendum:** sobre un contrato en revisión 1, confirmar un addendum crea la revisión 2 como activa y deja la 1 como `superseded`. Las filas de la revisión 1 conservan sus ids y valores.
- **Totales y pagos:** el `total` del contrato es el de la revisión activa. Los pagos anteriores se conservan y el saldo se recalcula con el total nuevo.
- **Saldo a favor:** con $8,000 pagados y un addendum que deja el total en $6,000, la reserva muestra saldo pendiente $0 y "Saldo a favor: $2,000".
- **Página de reservas:** en `/reserva/<token>`, después de un addendum el cliente ve solo los productos, precios, total y saldo de la revisión 2; nada de la revisión 1 aparece.
- **Sin addendum:** la página de reservas de un contrato sin modificaciones se ve igual que hoy.
- **Editar contrato:** la sección precarga la revisión activa y muestra la vista previa de cambios antes de confirmar. Confirmar sin ningún cambio se rechaza.
- **Endpoints retirados:** `PATCH` y `DELETE /contracts/:id/items/:itemId` y `POST /contracts/:id/items` ya no existen (404).
- **Concurrencia:** si dos addenda se confirman a la vez sobre la misma revisión, solo uno se aplica y el otro recibe 409.
- **Compatibilidad:** los contratos existentes quedan con su revisión 1 y sus respuestas actuales siguen iguales, salvo los campos nuevos.

### Open questions

1. **Vista previa:** un contrato sin pagos todavía no compromete nada. ¿También usa addendum o se edita directo?
2. **Estados:** ¿un contrato `cancelled` o `finalized` acepta addendum?
3. **Aviso al cliente:** ¿cómo se entera de que su contrato cambió? Una línea "Actualizado el <fecha>" en la página, un WhatsApp o correo, o se lo dice el staff.
4. **Quitar un paquete:** ¿sus extras ligados (`contract_extras.contract_package_id`) se quitan con él o se quedan sin paquete?

**Riesgos:** la migración agrega `revision_id` a las filas de snapshot de todos los contratos existentes (cambio de formato persistido); se necesita probarla contra una copia poblada.

**Dependencia:** el issue de costos por servicio sale antes; al planear este hay que confirmar dónde quedaron guardados.

### Affected repositories (hint)

brillipoint-api, brillipoint-front
