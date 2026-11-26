feat(photobook): disparar la foto con un control remoto Bluetooth

### Problem

Hoy la única forma de tomar la foto es presionar el botón en la pantalla del iPad. Alguien tiene que estar parado frente a la cámara: el operador sale en la foto o se mete en el encuadre, y los invitados tienen que acercarse a la pantalla y regresar a su lugar antes de que termine la cuenta regresiva.

Con un control remoto en la mano, el operador dispara desde lejos o los invitados se toman la foto ellos mismos. Se ve más profesional que hacerlo desde el celular o desde la pantalla.

**Estado actual (verificado en el código, `BrillipointPhotobook` en `main`, `7ae36f8`):**

- **La foto se dispara por un solo camino:** el `CameraShutterButton` llama a `startCapture()` (`BrillipointPhotobook/Views/CameraView.swift:255-256`). `startCapture()` (`:373`) arranca la cuenta regresiva con `viewModel.timerSeconds` y al final llama a `capturePhoto()` (`:425`).
- **El botón se deshabilita** con `.disabled(isCountingDown || isCapturingPhoto || isShowingSessionReview)` (`CameraView.swift:259`). Pero `startCapture()` por sí solo revisa únicamente `isCapturingPhoto` (`:374`). Las otras protecciones existen solo porque el botón está deshabilitado.
- **No hay soporte de hardware para disparar:** el repo no usa `onCameraCaptureEvent`, `AVCaptureEventInteraction`, `GCController`, atajos de teclado ni Multipeer.
- **La app pide iOS 26.1** (`IPHONEOS_DEPLOYMENT_TARGET`), así que puede usar `onCameraCaptureEvent` / `AVCaptureEventInteraction` (iOS 17.2+, botones físicos como captura).

### Proposal

Punto de partida; la planeación lo afina.

**Decisión tomada con el usuario (2026-11-20):** el control remoto solo dispara la foto. No maneja la revisión de la sesión (repetir o confirmar) ni ninguna otra pantalla.

- Escuchar los botones físicos de captura en la pantalla de cámara con `onCameraCaptureEvent` (SwiftUI) o `AVCaptureEventInteraction`. Los controles Bluetooth de selfie genéricos se presentan como la tecla "subir volumen", así que deberían llegar por el mismo evento sin emparejar nada dentro de la app.
- Disparar al soltar (fase `ended`) para que una sola pulsación no dispare dos veces.
- Que el control entre por el mismo `startCapture()` del botón, con la cuenta regresiva y la pantalla de revisión de siempre.
- Mover a `startCapture()` (o a una regla que se pueda probar) las mismas condiciones que hoy deshabilitan el botón. Así ninguna entrada, botón o control, puede arrancar una cuenta encima de otra ni disparar durante la revisión.
- Sin cambios en `bookandsign-api`, `bookandsign-front` ni `brillipoint-print-server`.

### Acceptance criteria

- Con la pantalla de cámara abierta, una pulsación del control remoto Bluetooth hace lo mismo que tocar el botón: arranca la cuenta regresiva configurada y toma la foto.
- Una pulsación dispara una sola vez.
- Los botones de volumen del iPad también disparan la foto en esa pantalla.
- El control se ignora en los mismos casos en que el botón no se puede presionar: cuenta regresiva en curso, foto en curso, revisión de la sesión, o con un panel abierto encima de la cámara (ajustes de cámara, QR de la galería).
- El control no hace nada en la pantalla de revisión ni fuera de la pantalla de cámara.
- Tocar el botón en pantalla funciona igual que antes.
- Probado en el iPad del evento con el modelo de control que se vaya a usar.

### Open questions

- **Falta probar en el hardware real:** que un control Bluetooth genérico llegue como evento de captura dentro de la app en el iPad. Si no llega, el plan B es leerlo como tecla de hardware (`pressesBegan` / `UIKeyCommand`).
- **Qué control comprar:** hay que elegir el modelo y verificarlo antes de comprar varios.
- **Riesgo aceptado:** mientras la cámara está abierta, los botones de volumen del iPad dejan de cambiar el volumen.

### Affected repositories (hint)

BrillipointPhotobook-
