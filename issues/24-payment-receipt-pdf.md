feat(payments): PDF receipts, edit and delete for contract payments

### Problem

Cuando el dinero de un pago con tarjeta o transferencia llega a la cuenta, generamos un PDF de comprobante. Hoy ese PDF vive fuera del sistema: se puede perder y no queda ligado al pago ni al contrato.

Además, un pago registrado no se puede corregir ni borrar. Si el monto, el método o la fecha quedaron mal, o si el PDF llega después de registrar el pago, el staff no tiene cómo arreglarlo.

**Estado actual (verificado en el código: `bookandsign-api` en `main`, `aed5bcc`; `bookandsign-front` en `main`, `04e24d4`):**

- **API, modelo:**
  - `payments` tiene `note` y `reference` (`text`, nullable), sin campo de archivo (`src/payments/entities/payment.entity.ts:29-33`). `CreatePaymentDto.reference` es opcional (`src/payments/dto/create-payment.dto.ts:27-29`).
  - `Payment` hereda `deletedAt` de `BaseTimeEntity` (`src/common/entities/base-time.entity.ts`), así que ya admite borrado suave. Al borrar un contrato, sus pagos se borran así (`src/contracts/contracts.service.ts:965`).
- **API, rutas:** solo `POST` y `GET /contracts/:id/payments` (`src/contracts/contracts.controller.ts:284-301`). No hay edición ni borrado de pagos. Crear un pago en un contrato cancelado da `409` (`contracts.service.ts:607-624`).
- **API, saldo:** `balanceDue` se calcula al leer, sumando los pagos vivos (`sumPayments` y `computeBalanceDue`, `contracts.service.ts:626-632`, `:664-667`). No encontré otra lógica en la API que dependa del total pagado, así que editar o borrar un pago solo mueve el saldo.
- **API, ruta pública:** `GET /contracts/get-by-token/:token` es `@Public()` (`contracts.controller.ts:92-99`) y su detalle incluye `payments` (`contracts.service.ts:678-708`). Esa ruta alimenta la página pública de la reserva.
- **API, almacenamiento:** ya existe Supabase Storage en `StorageService`: subida firmada, URL pública y URL de lectura firmada (`src/common/storage/storage.service.ts:40-85`). Usa un solo bucket, `SUPABASE_STORAGE_BUCKET`, con default `'public'` (`:40-42`). El patrón a seguir es `PrepProfileUploadsService.createSignedUploadUrl` (`src/contracts/preparation-profile/prep-profile-uploads.service.ts:59-140`): valida, arma el path `<contractId>/<questionId>/<uuid>_<name>` y devuelve `signedUrl`, `token` y `publicUrl`.
- **API, permisos:** no encontré guard de roles (`RolesGuard`, `@Roles`). Cualquier usuario del staff con sesión puede usar las rutas de contratos.
- **Front, staff:** el modal "Pagos del contrato" (`src/features/contracts/components/PaymentsModal/PaymentsModal.tsx`) tiene:
  - `PaymentsList`, solo lectura, con la columna "Referencia / Nota" (`PaymentsList.tsx:60`, `:77-79`).
  - `PaymentForm`, solo para crear, con un campo de texto "Referencia" requerido para transferencia y opcional para tarjeta (`PaymentForm.tsx:20-24`, `:143-161`).
  - `usePayments.addPayment`, que después de crear vuelve a pedir los pagos y el saldo (`usePayments.ts:110-127`).
- **Front, cliente:** "Ver histórico de pagos" está en `ReservationFinanceSection` (`src/features/booking/components/ReservationFinanceSection.tsx:145-166`), dentro de `ReservationPublicPage`, que carga el contrato con `getContractByToken` (`src/features/booking/pages/ReservationPublicPage.tsx:99`, `:218`). Es la vista **del cliente**, no del staff. Hoy muestra `Referencia: <texto>`.
- **Anticipo:** los pagos que nacen junto con el contrato salen de `useCreateContractForm.ts:326` y `expo-bebe/.../useContractForm.ts:494`, sin campo de referencia.

### Proposal

Punto de partida; la planeación lo afina.

**Decisiones tomadas con el usuario (2026-11-18):**

- La edición y el borrado de pagos van en este mismo issue, dentro del modal "Pagos del contrato" que ya existe. No se crea una pantalla nueva de pagos.
- El cliente ve su comprobante en "Ver histórico de pagos" de la página pública de la reserva. El botón abre el PDF.
- Los comprobantes van en un **bucket privado** y se leen solo con URL firmada temporal.
  - Descartado: dejarlos en el bucket público y entregar solo URLs firmadas. En un bucket público, cualquiera con la URL lee el archivo y RLS no aplica a las descargas ([Supabase, bucket fundamentals](https://supabase.com/docs/guides/storage/buckets/fundamentals)). La URL firmada trae el bucket y el path (`/storage/v1/object/sign/<bucket>/<path>?token=...`, ejemplo en `@supabase/storage-js`, `dist/index.d.cts:993`), así que quien la tenga arma la URL pública y el vencimiento no sirve.
  - Descartado: cambiar opciones o metadatos en la subida. Lo público o privado se define por bucket, no por archivo.
- Los buckets privados ya existen, según el usuario: `local-priv` para desarrollo local y `prod-priv` para producción. Hay un solo proyecto de Supabase, así que el ambiente se distingue por el nombre del bucket. No hay que crear ninguno.
- El comprobante es **opcional**, también en transferencia. Razón: en la expo el contrato se genera en el momento y el cliente solo enseña la transferencia o el cobro de tarjeta; el PDF se genera después y se adjunta con "Editar".
- La **referencia** de texto se queda, también opcional, al lado del botón del PDF. Cualquiera de los dos sirve como respaldo del pago, y ninguno es obligatorio. En la expo se anota el folio que enseña el cliente y el PDF se adjunta después.
  - Descartado: quitar el campo de referencia. Con el PDF opcional, un pago por transferencia en la expo quedaría sin ningún dato de respaldo.
- El comprobante es **solo PDF**, porque es lo que entrega Mercado Pago.
  - Descartado: aceptar imágenes (capturas de la transferencia).
- **Cualquiera del staff** con sesión puede editar y borrar pagos, igual que el resto del modal. Razón: hoy hay un solo usuario de staff.
  - Descartado: agregar roles en este issue. Si hace falta restringirlo, va en su propio issue.
- **No se guarda autor** de creación, edición ni borrado de pagos. Razón: hay un solo usuario de staff, y el borrado suave conserva el registro.
- **Los PDF nunca se borran** de Supabase, ni al reemplazar un comprobante ni al borrar un pago. Solo se eliminan a mano, si hace falta espacio. Razón: es coherente con el borrado suave; si un pago se restaura a mano, su PDF sigue ahí.

**1. Comprobante PDF**

- **Modelo:** nueva columna `payments.receipt_path` (`text`, nullable), con migración. Se guarda el path del objeto, no la URL; la URL se arma al leer. `reference` no cambia.
- **Subida:** endpoint del staff `POST /contracts/:id/payments/receipt-upload-url`, mismo patrón que prep-profile. Valida que el archivo sea PDF (`application/pdf`, máximo 10 MB) y devuelve `signedUrl`, `token` y `path` (`payments/<contractId>/<uuid>_<name>.pdf`). Crear y editar aceptan un `receiptPath` opcional, y la API rechaza un path que no sea de ese contrato.
- **Bucket privado:** el nombre llega por una variable de entorno nueva (`local-priv` en local y en los worktrees, `prod-priv` en producción). Hoy `StorageService` conoce un solo bucket (`get bucket()`, `storage.service.ts:40-42`), así que sus métodos tienen que aceptar el bucket como parámetro. El cliente de Supabase ya usa la service role key (`storage.service.ts:19-38`), así que la API puede firmar en un bucket privado.
- **Lectura:** `PaymentDto` expone `receiptUrl: string | null` en la ruta del staff y en la ruta pública por token. Es una URL firmada que la API genera en cada lectura con `createSignedReadUrl`, con vigencia de 1 hora (propuesta). Nunca se devuelve la URL pública.
- **Solo tarjeta y transferencia:** un pago en efectivo no lleva comprobante. Si se edita a efectivo, el comprobante se quita.

**2. Edición y borrado**

- `PATCH /contracts/:id/payments/:paymentId`: cambia monto, método, fecha, nota, referencia y comprobante (`receiptPath: null` lo quita).
- `DELETE /contracts/:id/payments/:paymentId`: borrado suave (`deletedAt`). El pago deja de salir en las listas y de sumar al saldo.
- Las dos rutas dan `404` si el pago no es de ese contrato, y `409` si el contrato está cancelado, igual que crear.

**3. Front del staff (modal "Pagos del contrato")**

- En `PaymentForm`, para tarjeta y transferencia: el campo "Referencia" queda como texto opcional (deja de ser requerido en transferencia, `PaymentForm.tsx:20-24`) y se suma un botón "Subir comprobante (PDF)", también opcional.
- Cada fila de `PaymentsList` tiene "Ver comprobante" (si hay comprobante; abre el PDF en una pestaña nueva), "Editar" y "Eliminar".
- "Editar" abre el mismo formulario con los datos del pago; ahí se adjunta, cambia o quita el comprobante. Así se le pone comprobante a un pago viejo o al anticipo.
- "Eliminar" pide confirmación.
- Después de editar o eliminar, el modal vuelve a pedir los pagos y el saldo, como ya hace al crear.

**4. Front del cliente**

- En "Ver histórico de pagos", un botón "Ver comprobante" cuando el pago tiene `receiptUrl`. Abre el PDF en una pestaña nueva, donde el cliente lo puede ver o guardar. La referencia se sigue mostrando como hoy cuando existe.

**Orden:** API (migración y endpoints) → front.

### Acceptance criteria

- **Comprobante:**
  - El staff registra un pago por transferencia con un PDF: el pago queda con comprobante y la fila muestra "Ver comprobante".
  - Lo mismo con tarjeta.
  - Un pago por transferencia o tarjeta se registra con solo referencia, con solo PDF, con los dos o con ninguno.
  - Con efectivo no aparece el botón de carga.
  - Un archivo que no es PDF se rechaza, en el front y en la API.
  - Un `receiptPath` de otro contrato se rechaza, al crear y al editar.
  - El PDF queda en el bucket privado: su URL pública (`/storage/v1/object/public/...`) no lo devuelve, y la URL firmada deja de servir al vencer.
- **Edición:**
  - El staff cambia el monto de un pago y el saldo del modal se actualiza.
  - El staff adjunta un PDF a un pago que no tenía, y después lo quita.
  - Un pago con comprobante editado a efectivo queda sin comprobante.
  - Editar un pago de otro contrato da `404`; editar en un contrato cancelado da `409`.
- **Borrado:**
  - El staff elimina un pago después de confirmar: desaparece del modal y de la página del cliente, y el saldo sube por ese monto.
  - El registro queda en la base con `deleted_at`.
  - Borrar en un contrato cancelado da `409`.
- **Cliente:**
  - En la página pública de la reserva, "Ver histórico de pagos" muestra "Ver comprobante" solo en los pagos que tienen comprobante.
  - El botón abre el PDF en una pestaña nueva.
- **Compatibilidad:**
  - Los pagos con `reference` siguen mostrando su referencia en las dos vistas, tengan o no comprobante.
  - Adjuntar o quitar un comprobante no cambia el saldo.

### Open questions

Ninguna. Todas se resolvieron con el usuario el 2026-11-18 (ver Decisiones en Proposal).

**Riesgos:**

- La subida es en dos pasos: si el PDF sube y el registro del pago falla, queda un archivo huérfano en Supabase.
- Con subida firmada, el archivo va directo del navegador a Supabase: la API solo valida el tipo y el tamaño que declara el front. Para que el límite se cumpla de verdad hay que revisar si `local-priv` y `prod-priv` tienen configurados tipos permitidos y tamaño máximo (por verificar en la implementación).
- La ruta pública por token expone los comprobantes a cualquiera que tenga el link de la reserva, igual que hoy expone el resto del contrato.
- Una URL firmada no se puede revocar antes de que venza; solo se invalida moviendo o borrando el archivo ([Supabase, downloads](https://supabase.com/docs/guides/storage/serving/downloads)).
- Si falta la variable del bucket privado en un ambiente, la subida falla. Hay que agregarla en producción antes de desplegar.
- `local-priv` y `prod-priv` viven en el mismo proyecto de Supabase: una variable mal puesta en local escribiría en el bucket de producción.
- Un pago borrado por error solo se recupera a mano en la base.

### Affected repositories (hint)

brillipoint-api
brillipoint-front

### Contexto en Engram

- Proyecto: `brillipoint-ops`
- `topic_key`: `issue/brillipoint-ops#24`

Busca ese `topic_key` (`mem_search`, luego `mem_get_observation`) antes de implementar. Si contradice este issue, manda el issue.
