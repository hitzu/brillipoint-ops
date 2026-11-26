feat(photobook): activar las poses rápido desde la cámara y aplicarlas a la sesión en curso

### Problem

Ocultar poses ya funciona, pero en el evento cuesta usarlo. El caso típico: al llegar al evento dejamos listas 4 opciones de poses y las dejamos apagadas. Llega una pareja que no sabe posar y queremos prenderlas en ese momento con la selección que ya teníamos. Hoy eso no se puede hacer rápido:

- El interruptor y la lista de poses están en la pestaña Evento de la consola del operador, lejos de la cámara.
- La lista muestra siempre las 7 opciones abiertas y con nombres que no dicen nada ("Indice 1.1"), así que cuesta saber cuál es cuál.
- Aunque se prendan, **no aparecen para la pareja que ya está frente a la cámara**: el cambio aplica hasta la siguiente sesión.

**Estado actual (verificado en el código, `BrillipointPhotobook` en `main`, `a097e10`):**

- **La configuración vive en el iPad:** `PoseSettings` (`BrillipointPhotobook/Models/PoseSettings.swift`) se guarda en UserDefaults con `PoseSettingsStore` (llave `poseSettings`). Campos: `isEnabled`, `hiddenOptionIDs`, `selectionMode` (`automatic` / `manualOnly`), `assistPanelVisibleByDefault`.
- **La selección ya se conserva al apagar:** `isEnabled = false` no borra `hiddenOptionIDs`. Al volver a prender, se recupera la misma selección.
- **La UI de poses solo existe en la consola:** `PoseSettingsSection` (`Views/OperatorConsole/PoseSettingsSection.swift`) aparece dentro de `EventoTabView`. Muestra el toggle "Poses habilitadas", el modo de selección, "Panel visible al iniciar" y, abajo, una fila por cada opción con el texto "Indice \(option.label)", un botón para ver las poses y su toggle. Ninguna parte va colapsada.
- **Los ajustes de cámara no tienen poses:** `CameraSettingsView` (la hoja que se abre con el engrane en `CameraView`) solo trae las secciones de cámara, Smart Framing, luz y subida.
- **La sesión copia la configuración al empezar:** `SessionViewModel` la guarda en `let poseSettings` dentro de `init` (`PoseSettingsStore.load()`). Se crea una sesión nueva en cada `AppViewModel.startNewSession` / `startEvent`. Por eso el footer dice "Aplica desde la proxima sesion". El botón de poses (`PoseAssistToggleButton`) y el panel (`PoseAssistPanelOverlay`) solo aparecen si `sessionVM.posesEnabled`, que lee esa copia.
- **Las opciones están en el código:** `SessionViewModel.availablePoseOptions` define 7 opciones (`1`, `1_1`, `2`, `2_1`, `3`, `4`, `5`), cada una con `id`, `label` y `personCount`.
- **El `id` sirve para dos cosas:**
  - Elegir la pose en automático: `PoseSettings.resolveOption` busca `$0.id == String(count)`.
  - Buscar las imágenes en el catálogo: `SessionViewModel.loadPoseImage` arma el nombre `inspiration/<id>/pose_<id>_<n>`.

### Proposal

Punto de partida; la planeación lo afina.

- **Check rápido en los ajustes de cámara:** agregar a `CameraSettingsView` un toggle "Poses" que cambie el mismo `isEnabled` de `PoseSettingsStore`. No duplica la configuración: prende y apaga con la selección que ya está guardada.
- **Que aplique a la sesión en curso:** prender o apagar ese toggle cambia la sesión abierta sin esperar a la siguiente. Al prender, aparecen el botón y el panel de poses con las opciones visibles. En automático, se elige la pose según las personas detectadas en ese momento. Al apagar, desaparecen.
- **Lista colapsable en la consola:** dentro de `PoseSettingsSection`, poner las filas de cada opción en un bloque colapsable, cerrado por defecto, con un resumen como "4 de 7 visibles". El toggle general y el modo de selección quedan fuera del bloque.
- **Nombre visible para cada opción:** agregar a `PoseOption` un nombre corto y descriptivo, aparte del `id`, que se muestre en la consola en lugar de "Indice 1.1". El `id`, las carpetas y los nombres de los assets no cambian.
- Sin cambios en `bookandsign-api`, `bookandsign-front` ni `brillipoint-print-server`.

### Acceptance criteria

- En los ajustes de cámara hay un toggle de poses que refleja el estado actual y lo cambia.
- Con poses apagadas y 4 opciones visibles guardadas, prender el toggle desde la cámara durante una sesión hace aparecer el botón y el panel de poses en esa misma sesión, solo con esas 4 opciones.
- Apagar el toggle durante una sesión esconde el botón y el panel en esa misma sesión.
- Prender y apagar varias veces no cambia qué opciones están visibles u ocultas.
- El toggle de la cámara y el "Poses habilitadas" de la consola siempre muestran el mismo valor.
- En la pestaña Evento, la lista de opciones está colapsada por defecto y muestra cuántas están visibles. Al abrirla se puede ver y cambiar cada opción como hoy.
- Cada opción se muestra con su nombre descriptivo en la consola.
- La selección automática por número de personas funciona igual que antes, incluyendo usar la opción visible más cercana cuando la detectada está oculta.
- El texto del footer ya no dice que el cambio aplica hasta la siguiente sesión.

### Open questions

- **Nombres de las opciones:** ¿se dejan fijos en el código, junto a `availablePoseOptions`, o el operador los puede editar en el iPad? Fijos en el código es más simple: agregar una pose nueva ya requiere una build nueva porque los assets vienen en la app, así que el nombre se pone ahí mismo. Falta definir los nombres de las 7 opciones.
- **¿El invitado también ve el nombre?** Hoy el selector del invitado muestra `option.label` dentro de un círculo chico (`PoseAssistFloatingView`, letra de 9 a 13 pt) y en el título del carrusel (`PoseCarouselModalView`). Un nombre largo no cabe en el círculo. La propuesta es mostrar el nombre solo al operador y dejar al invitado como está.
- **Panel al prender en vivo:** ¿al prender desde la cámara el panel se abre siempre, o respeta "Panel visible al iniciar"? En el caso de la pareja, lo lógico es que se abra.
- **Modo de selección en la cámara:** ¿el check rápido también deja cambiar entre automático y manual, o solo prende y apaga?
- **Riesgo:** cambiar la configuración a mitad de sesión no debe mover una foto que ya se tomó ni la pose elegida a mano (`hasManualPoseOverride`). Hay que revisar esos casos al planear.

### Decisiones

- **2026-11-23 — La configuración de poses se queda en el iPad** (UserDefaults, como hoy). No se mueve al evento en el backend ni al snapshot. Solo cambia el Photobook. Consecuencia aceptada: la selección pasa al siguiente evento hasta que el operador la cambie.
- **2026-11-23 — Descartado: renombrar las carpetas de las poses.** El `id` de cada opción decide la pose automática por número de personas y también arma el nombre de las imágenes. Renombrar las carpetas rompería la detección automática. Por eso el nombre visible va en un campo aparte.

### Affected repositories (hint)

BrillipointPhotobook-
