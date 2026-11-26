feat(photobook): prueba de Image Playground desde el buscador de sesiones

### Problem

Queremos vender un extra: a partir de la foto del invitado, generar una imagen ilustrada con un tema (Harry Potter, superhéroes, fútbol, el Mundial, etc.). Apple ofrece esto en el dispositivo con el framework **ImagePlayground** (`ImageCreator`, iOS 18.4+). Corre en el iPad, sin costo por imagen y sin que la foto salga del dispositivo.

Antes de diseñar la función completa (tema por evento, subida a la galería, impresión) necesitamos saber si el resultado sirve. Hay cuatro dudas:

- ¿Se parece al invitado?
- ¿Cuánto tarda en generarse?
- ¿Qué temas acepta Apple? Puede rechazar o diluir personajes y marcas con derechos.
- ¿Cómo se ve con fotos de grupo?

Esta es una **prueba acotada** para responder eso con fotos reales de eventos, sin tocar la API, el front ni el print server.

**Hardware verificado con el usuario (2026-11-20):** el iPad del photobooth es un iPad Air 5ª gen (`A2588`, chip M1) con iPadOS 27.2.1. Cumple el requisito de Apple Intelligence.

**Estado actual (verificado en el código, `BrillipointPhotobook` en `main`, `a097e10`):**

- **ImagePlayground:** la app no usa ImagePlayground ni Apple Intelligence en ningún lado. El deployment target es iOS 26.1 (`BrillipointPhotobook.xcodeproj/project.pbxproj:247`), suficiente para `ImageCreator`.
- **Buscador de sesiones:**
  - La sesión expandida es `Views/SessionFinder/SessionFinderExpandedCard.swift`. Muestra las fotos en `SessionFinderPhotoPagerView` (`:25`) y el botón "Reenviar a impresión" (`reprintButton`, `:126`).
  - Las fotos son locales (`photoURLs`), y las pasa `SessionFinderContentView.swift:109` desde `sessionStore.photoURLs(for: record)`.
- **Página visible:** la foto que se está viendo vive en un `@State` privado del pager (`currentIndex`, `SessionFinderPhotoPagerView.swift:16`). Para usar esa foto, la tarjeta necesita conocer el índice.
- **Flags de operador:** ya existe el patrón en `Services/VideoBetaSettings.swift` (guardado en `UserDefaults`, apagado por defecto), con su toggle en la consola del operador, pestaña Debug, sección "Modos de prueba" (`Views/OperatorConsole/DebugTabView.swift`).
- **SDK de Apple (verificado en Xcode 27.2, iPhoneOS 27.2 SDK, y en la documentación de Apple):**
  - `ImageCreator` (generación sin interfaz) **dejó de funcionar en iOS, iPadOS y macOS 27**. Apple lo anunció el 2026-06-11 y su `init()` lanza `notSupported` en 27+. Comprobado: da `notSupported` en el simulador y en una Mac con macOS 27.0.1. El iPad del photobooth tiene iPadOS 27.2.1.
  - Lo vigente es la hoja de Image Playground (`imagePlaygroundSheet(isPresented:concepts:sourceImageURL:onCompletion:onCancellation:)`): recibe la foto y el prompt, Apple maneja la interacción y devuelve la imagen a la app.
  - Estilos (`ImagePlaygroundStyle.all`): `any` (iOS 27, "estilo inferido del prompt"), `animation`, `illustration`, `sketch`, `emoji` y `externalProvider` (ChatGPT, la foto sale del dispositivo). `imagePlaygroundGenerationStyle(_:in:)` limita los estilos que la hoja muestra.
  - El simulador no corre Image Playground: solo se puede probar en el iPad.

### Decisions (2026-11-22)

1. **Dirección de marca: caricatura constante, no "cara de IA".**
   - El resultado debe verse como una caricatura con un estilo propio y consistente entre sesiones y eventos.
   - No debe verse como la típica imagen generada por IA. Todos meten IA a la fuerza y no queremos ir con todos.
   - El objetivo es algo gracioso y sorprendente, no presumir que usamos IA.
2. **No es retoque.** Mejorar la foto real sin que se note ("fotos profesionales") es otro producto y va en su propio issue, con baja prioridad. Image Playground genera imágenes nuevas e ilustradas, así que no sirve para eso.
3. **Detrás de un feature flag del iPad.** Toggle "Imagen IA (prueba)" en la consola del operador, pestaña Debug, sección "Modos de prueba", apagado por defecto. Con el flag apagado, el buscador de sesiones se ve igual que hoy.
4. **La foto no sale del iPad.** Se excluye el estilo `externalProvider` (ChatGPT). Solo se usan los estilos que generan en el dispositivo.
5. **Estilos permitidos:** `animation`, `illustration`, `sketch` y `emoji`. El operador elige el estilo dentro de la hoja de Apple. Se excluyen `externalProvider` (ChatGPT) y `any`, porque Apple no documenta dónde genera `any`. Se puede abrir después de la prueba.
6. **Hoja de Image Playground de Apple** (2026-11-22, reemplaza la decisión anterior de usar solo `ImageCreator`). `ImageCreator` dejó de funcionar en iPadOS 27, así que el botón del modal abre la hoja de Apple con la foto visible y el prompt, y el resultado vuelve al modal. Si las pruebas convencen, se decide cómo meterlo al flujo y cómo venderlo como upsell.

### Proposal

Punto de partida; la planeación lo afina.

- Con el flag encendido, en la sesión expandida del buscador, agregar un botón **"Probar imagen IA"** debajo de "Reenviar a impresión".
- El botón abre un modal con:
  - un campo de texto para el prompt (por ejemplo "mago de Hogwarts", "superhéroe", "jugador de la selección");
  - un botón **Abrir Image Playground**.
- **Abrir Image Playground** presenta la hoja de Apple con la foto que se está viendo en el pager y el texto del prompt. Al terminar, el resultado se muestra en el mismo modal.
- Se mide y muestra el tiempo desde que se abre la hoja hasta el resultado (incluye lo que el operador tarda dentro de la hoja).
- Si el dispositivo no soporta Image Playground o Apple Intelligence está apagado, el modal lo dice y no abre la hoja. Si Apple rechaza el prompt, lo muestra la propia hoja.
- **Nada se guarda, sube ni imprime.** La imagen solo vive en el modal.
- Sin cambios en `bookandsign-api`, `bookandsign-front` ni `brillipoint-print-server`.

### Acceptance criteria

- Con el flag apagado (valor por defecto), el buscador de sesiones se ve y funciona igual que hoy.
- Con el flag encendido, en la sesión expandida aparece el botón "Probar imagen IA". El resto de la tarjeta, incluido "Reenviar a impresión", funciona igual que antes.
- El modal pide un prompt, abre la hoja de Apple y, al terminar, muestra la imagen resultante y el tiempo que tardó.
- La hoja de Apple solo ofrece los estilos de la decisión 5.
- La imagen se genera a partir de la foto que estaba visible en el pager.
- Los errores (dispositivo no compatible, Apple Intelligence apagado, prompt rechazado) se muestran en el modal o en la hoja de Apple y no afectan la sesión.
- La sesión, sus fotos locales, la cola de subida y la impresión no cambian.
- Probado en el iPad del evento. Hay que anotar en el issue, para varios temas (con y sin nombres de marcas o personajes) y fotos de una y varias personas:
  - si Apple acepta el prompt;
  - si el resultado se parece al invitado;
  - el tiempo de generación;
  - si el estilo se mantiene constante entre sesiones y no parece "imagen de IA". Generar el mismo prompt con 3 o 4 sesiones distintas y compararlas lado a lado.

### Accepted risks

- **La interfaz de Apple queda en medio:** el operador interactúa con la hoja de Apple y el tiempo medido incluye esa interacción, no solo la generación.
- **Fuera de esta prueba: caricatura sin generación** con filtros deterministas de Core Image (por ejemplo `CIComicEffect`) sobre la foto real. Se evalúa solo si el resultado de Image Playground se ve "de IA" o inconsistente.
- **El simulador no corre Image Playground.** Solo valida el flag, el botón, el modal y el aviso de dispositivo no compatible; la generación, el parecido, los temas aceptados y los tiempos se miden en el iPad del evento, conectado a Xcode.

### Siguiente paso (fuera de este issue)

Si la prueba sale bien, se abre un issue aparte para la función completa: tema por evento configurado por el staff, generación automática al terminar la sesión, subida a la galería del invitado como extra (no cuenta en `photoCount`, nunca es portada) e impresión opcional.

Notas verificadas para ese issue:

- **API:** el presign de sesión solo acepta `image/jpeg` (`bookandsign-api/src/photos/dto/presigned-upload.dto.ts:19`).
- **Modelo:** `Photo` no tiene campo de origen.
- **Print server:** rechaza sesiones cuyo número de capturas no coincide con una plantilla (`brillipoint-print-server/app/api/routes.py:52`).

### Affected repositories (hint)

BrillipointPhotobook-

### Contexto en Engram

- Proyecto: `brillipoint-ops`
- `topic_key`: `issue/brillipoint-ops#29`

Busca ese `topic_key` (`mem_search`, luego `mem_get_observation`) antes de implementar. Si contradice este issue, manda el issue.
