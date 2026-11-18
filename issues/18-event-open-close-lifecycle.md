feat(print-server): explicit event open/close with an empty state

### Problem

El print server (BPS) no distingue entre "el iPad está vivo" y "el evento está abierto". Por eso no hay un estado vacío real: un evento cerrado sigue apareciendo como el evento actual, y el panel no tiene forma de cerrar un evento.

Esto bloquea el borrado de eventos (#17). Para borrar con seguridad hace falta saber qué evento está abierto y qué muestra el panel cuando no hay ninguno.

**Cómo se usa en la operación:** al llegar a montar, el operador conecta el iPad con el evento, prende la impresora y prueba que todo funcione. Conectar el iPad es justamente la forma de obligar al BPS a tomar ese evento. En ese momento no hay impresiones en curso ni otro iPad.

**Estado actual (verificado en el código, `brillipoint-print-server` en `main`, `3565b79`, y `BrillipointPhotobook` en `main`):**

- **`sessions.connected` hace dos trabajos: indica que el iPad está vivo y que el evento está abierto.**
  - `heartbeat_session` pone `connected = True` en cualquier sesión que exista, aunque esté cerrada (`app/queue/manager.py:395-411`).
  - `_sweep_stale_session` marca desconectada la sesión cuando vence el heartbeat (`app/queue/manager.py:604`), y el siguiente heartbeat la vuelve a conectar.
  - `close_session` pone `connected = False` (`app/queue/manager.py:413-423`). Su docstring dice "return BPS to the waiting-for-connection state", pero el panel no tiene ese estado.
- **"Evento actual" es la fila de `sessions` más reciente, esté conectada o no** (`get_latest_session`, `app/queue/store.py:801-810`). La usan:
  - El dashboard (`app/api/ui_routes.py:142`).
  - El panel de configuración del evento (`app/api/ui_routes.py:269`).
  - Mini Book, como respaldo de `get_active_session` (`app/api/ui_routes.py:738-739`).
  - Recovery (`app/dashboard/recovery.py:639`) y `app/api/template_routes.py:630`.
  - Por eso, después de cerrar, todo el panel sigue mostrando el último evento.
- **`get_active_session`** solo toma filas con `connected = 1` (`app/queue/store.py:789-799`); la usan `app/api/routes.py:858` y Mini Book.
- **`POST /session`** (`app/api/routes.py:189-294`) hace un upsert de `event_{id}` y lo vuelve el evento actual. No cierra el evento que estaba abierto.
- **El panel del BPS no tiene una acción para cerrar el evento.** El único cierre es `POST /session/close` (`app/api/routes.py:748`), que llama el iPad.
- **Pestañas del panel:** En vivo · Historial · Upsell · Templates (`app/ui/templates/base.html:72-75`).
  - Upsell es Mini Book (`GET /mini-book`). Sin evento conectado cae al último evento, y si no hay ninguno, al último con fotos en disco (`app/api/ui_routes.py:738-752`).
  - Historial tiene su propio selector de eventos y marca como activo al último evento (`app/dashboard/recovery.py:631-650`).
  - Templates no depende del evento. Solo usa el último evento para no dejar borrar los templates de su política (`app/api/template_routes.py:619-637`).
- **`POST /session` rechaza reabrir un evento si un template de su política ya no existe** (`app/api/routes.py:222-237`).
- **iPad:**
  - Ya tiene la acción "Cerrar sesión" del operador (`BrillipointPhotobook/Views/OperatorConsole/ImpresoraTabView.swift:301`). Llama a `closeEventSession` (`BrillipointPhotobook/PrintServer/PrintServerConnectionStore.swift:282-340`), que manda `POST /session/close`.
  - Abre el evento en `openEventSessionIfNeeded` (`PrintServerConnectionStore.swift:438`). Ese `POST /session` sale al conectar y también en cada envío a imprimir.
  - Manda un heartbeat cada 30 s; sus fallas solo se registran en el log (`PrintServerConnectionStore.swift:668-680`).

### Decisiones

- **2026-11-10:** el BPS muestra un estado vacío hasta que el iPad se conecta, y "Cerrar sesión" lo regresa a ese estado.
- **2026-11-10 (reemplaza la confirmación del cambio de evento):** el iPad es la fuente de verdad. Si el iPad se conecta con otro evento, el BPS cierra el que tenía abierto y abre el nuevo, sin preguntar.
  - Descartado: responder `409 another_event_open` y confirmar en el iPad. Conectar el iPad ya es la forma de obligar al BPS a tomar el evento, y en el montaje no hay impresiones en curso ni otro iPad. La confirmación solo agrega un paso y cambia el contrato con el iPad.
  - Descartado: confirmar el cambio en el panel del BPS, por la misma razón y porque el operador está en el iPad.
- **2026-11-10:** un evento se cierra de tres formas:
  1. El iPad se conecta con otro evento.
  2. Desde el panel del BPS, con una acción nueva "Cerrar evento".
  3. Desde el iPad, con "Cerrar sesión" (ya existe).
- **2026-11-10:** "Cerrar evento" en el panel pide confirmación con un modal. Si el iPad está conectado, el modal lo avisa: "El iPad está conectado. ¿Seguro que quieres cerrar el evento?".
- **2026-11-10:** si el panel cierra el evento y el iPad sigue en él, el heartbeat no lo reabre. El siguiente `POST /session` del iPad sí lo reabre.
- **2026-11-10:** Mini Book (pestaña Upsell) solo trabaja sobre el evento abierto. Se quitan los respaldos al último evento y al último evento con fotos en disco.
- **2026-11-10:** sin evento abierto no se deshabilita ninguna pestaña. En vivo muestra el estado vacío, Historial y Templates funcionan igual, y Upsell muestra el estado vacío sin dejar hacer nada.
  - Descartado: dejar solo Templates. En vivo es donde se ve el estado vacío, y en Historial #17 borra los eventos cerrados.
  - Descartado: deshabilitar Upsell. Basta con que muestre el estado vacío.
- **2026-11-10:** las filas que ya existen en `sessions` arrancan cerradas. Después de la limpieza inicial de #17 no queda ningún evento abierto: el BPS cae en el estado vacío y desde ahí se conecta el primer evento.

### Proposal

Punto de partida; la planeación lo afina.

1. **Separar "evento abierto" de "iPad conectado".**
   - Cada evento tiene un estado explícito: abierto o cerrado. Hay como mucho un evento abierto.
   - Las filas que ya existen arrancan cerradas.
   - El heartbeat solo actualiza la conexión del iPad. Nunca reabre un evento cerrado.
   - Si el heartbeat vence, el iPad aparece desconectado, pero el evento sigue abierto.
2. **El evento actual es el evento abierto, o ninguno.**
   - Dashboard, configuración del evento, Mini Book, recovery y la protección de templates usan esa regla.
   - Mini Book sin evento abierto muestra el estado vacío y no deja hacer nada. Ninguna pestaña se deshabilita.
   - Sin evento abierto, el dashboard muestra un estado vacío, por ejemplo: "Esperando la conexión del photobooth".
3. **Abrir:** un `POST /session` siempre deja abierto el evento que manda el iPad.
   - Si había otro evento abierto, lo cierra primero.
   - Si es el mismo evento abierto, lo reanuda igual que hoy, incluido el cambio de `photo_count` al reconectar (decisión 8).
   - Si el evento estaba cerrado, lo reabre.
4. **Cerrar:**
   - El `POST /session/close` que ya manda el iPad cierra el evento y deja el BPS en el estado vacío.
   - El panel del BPS agrega "Cerrar evento". Pide confirmación con un modal, que avisa si el iPad está conectado, y deja el BPS en el estado vacío.
   - Si el panel cierra el evento y el iPad sigue en él, el heartbeat no lo reabre. El siguiente `POST /session` del iPad (reconectar o imprimir) sí lo reabre, porque el iPad manda.
5. **El iPad no cambia.** Ya manda `POST /session` al conectar y `POST /session/close` al cerrar, y el contrato de las dos respuestas se mantiene.

**Orden:** va antes de #17, porque #17 solo debe dejar borrar eventos cerrados. Es independiente de #19 (resumen de hojas), y pueden ir en paralelo.

### Acceptance criteria

- **Estado vacío:**
  - Un BPS sin evento abierto muestra el estado vacío en el dashboard y no presenta el último evento como el actual.
  - Al actualizar el BPS, las filas que ya existen en `sessions` quedan cerradas y el dashboard muestra el estado vacío hasta que el iPad se conecta.
  - Al tocar "Cerrar sesión" en el iPad, el BPS pasa al estado vacío de inmediato.
  - Al usar "Cerrar evento" en el panel y confirmar, el BPS pasa al estado vacío. Con el iPad conectado, el modal lo avisa antes de cerrar.
  - Sin evento abierto, las cuatro pestañas siguen disponibles. Mini Book muestra el estado vacío y no muestra el último evento ni el último con fotos en disco.
- **Heartbeat:**
  - Un heartbeat tardío de un evento cerrado no lo reabre.
  - Si el heartbeat vence, el iPad aparece desconectado y el evento sigue abierto. Cuando vuelve el heartbeat, el iPad aparece conectado otra vez.
- **Cambio de evento:** con el evento A abierto, el iPad se conecta con el evento B. A queda cerrado, B queda abierto y el iPad no ve ningún error ni pregunta.
- **Reapertura:** con el evento A cerrado desde el panel, el siguiente `POST /session` del iPad con A lo vuelve a abrir.
- **Compatibilidad:** reconectar con el mismo evento abierto funciona igual que hoy, incluido el cambio de `photo_count`. La versión actual de la app del iPad funciona sin cambios.
- Todo funciona sin conexión a internet.

### Open questions

Ninguna. Todas quedaron resueltas en **Decisiones**.

**Riesgos aceptados:**

- Si el iPad cambia de evento mientras el anterior todavía tiene impresiones o subidas en curso, ese evento ya quedó cerrado. Se acepta: en el montaje no pasa, según la operación descrita arriba.
- Sin evento abierto, Templates deja borrar los templates del último evento. Si después se reabre ese evento, `POST /session` lo rechaza porque falta un template de su política. Hoy ya pasa con cualquier evento anterior al último.
  - Se acepta (2026-11-10): no se regresa a un evento anterior. Para imprimir fotos de un evento pasado, se agregan en la edición del template y se imprime desde ahí.
  - Posible issue aparte, sin prioridad: que el evento deje de estar amarrado a los templates.

### Contexto en Engram

Proyecto `brillipoint-ops`, `topic_key` `issue/brillipoint-ops#18` (`mem_search`, luego `mem_get_observation`). Si contradice este issue, manda el issue.

### Affected repositories (hint)

brillipoint-print-server. `BrillipointPhotobook` no cambia, solo se verifica que la versión actual siga funcionando.
