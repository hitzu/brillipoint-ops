feat(booking): rediseño UX de la pestaña "Tatuajes" de la reserva pública (subir primero, catálogo después)

### Problem

La pestaña "Tatuajes" (#20 subida, #21 catálogo) ya funciona, pero la UI actual mezcla todo en una sola tarjeta: texto, contador, miniaturas, catálogo y dropzone sin un orden claro. Para una clienta que entra desde el celular a "subir sus diseños" no es obvio que **subir** es el camino principal y que el **catálogo** es la alternativa si no le alcanza el tiempo, ni cuántos lugares le quedan.

Es solo **diseño/UX**: no cambia reglas de negocio, API ni modelo de datos.

Diseño de referencia (canvas "Diseños de tatuajes – UX"): https://claude.ai/artifact/TMauMUZUKcZ8Sfh1DQztBj (artboards `1 · Validar celular` y `2 · Diseños de tatuajes`).

### Proposal

Rediseñar la presentación de `TattooDesignsView` (y la pantalla del phone gate) siguiendo el artifact:

**Pantalla 1 · Validar celular**
- Tarjeta centrada con candado, título "Confirma tu número de celular", texto explicando que la sección está protegida.
- Campo "Celular del contrato (10 dígitos)" con `type="tel"`, `inputmode="numeric"`, solo dígitos, máximo 10.
- Botón "Continuar" deshabilitado hasta tener 10 dígitos.
- Pista del número: se reutiliza el hint que ya existe ("Número registrado en el contrato: ******1234", últimos 4 dígitos), no el "••31" del mockup.
- Nota: "¿Ya no tienes ese número? Escríbenos por WhatsApp y lo actualizamos."

**Pantalla 2 · Diseños de tatuajes**
- Encabezado: "Puedes **subir hasta 5 imágenes** de los diseños que quieres. Si no te da el tiempo, puedes **elegir de nuestro catálogo** más abajo." + dos chips: "Subidas + catálogo = máximo 5" y "Nuestro equipo necesita una semana para trabajarlos".
- **Paso 1 · Sube tus diseños**: dropzone grande, "Arrastra tus imágenes aquí o pulsa para seleccionarlas", "JPG o PNG · te quedan N lugares". Con 5 usados el dropzone se reemplaza por el aviso "Ya tienes tus 5 diseños. Quita uno de abajo para agregar otro."
- **Tus diseños · N de 5**: cuadrícula de **5 lugares fijos**; cada uno lleno (miniatura + etiqueta "Subido"/"Catálogo" + nombre + botón "Quitar" de 44 px) o vacío ("Lugar libre" con su número).
- **Paso 2 · ¿Sin tiempo? Elige de nuestro catálogo**: "Toca un diseño para agregarlo a tus 5 lugares. Toca otra vez para quitarlo." Tarjetas más grandes (≈200 px) con nombre, palomita verde y borde grueso al estar seleccionado, hint "Toca para elegir" / "Seleccionado" / "Sin lugares libres" (atenuado y deshabilitado cuando están los 5 lugares ocupados y no está seleccionado).
- Accesibilidad: `aria-pressed` en las tarjetas de catálogo, `aria-label` en "Quitar", contador con `aria-live="polite"`, foco visible, objetivos táctiles ≥ 44 px.

### Acceptance criteria

- [ ] El orden de la pestaña es: encabezado → paso 1 (subir) → "Tus diseños N de 5" (5 lugares) → paso 2 (catálogo).
- [ ] La cuadrícula siempre muestra 5 lugares; los libres dicen "Lugar libre".
- [ ] Con 5 diseños (subidos + catálogo) el dropzone se sustituye por el aviso y las tarjetas del catálogo no seleccionadas quedan deshabilitadas con "Sin lugares libres".
- [ ] El catálogo muestra estado seleccionado (borde + palomita + "Seleccionado") y permite quitar tocando de nuevo.
- [ ] Cada diseño lleno indica su origen ("Subido" / "Catálogo") y tiene botón "Quitar" accesible.
- [ ] Modo solo lectura (tras el cierre, 7 días antes del evento) conserva el aviso actual y no muestra controles de edición.
- [ ] Si el catálogo no tiene filas activas, el paso 2 no se muestra (igual que hoy).
- [ ] La pantalla de celular cumple la especificación de arriba y sigue usando el mismo gate (`usePublicContractPhoneGate`, mismo key de sesión que `PreparationSection`).
- [ ] Sin cambios en API, reglas (5 máx., cierre a 7 días, 409/422) ni en la vista de staff.
- [ ] Se ve y funciona bien a 390 px de ancho (el mockup está a 1000 px; hay que adaptar la cuadrícula de 5 lugares).

### Estado actual verificado

- `bookandsign-front/src/features/booking/components/TattooDesignsView.tsx`: una sola `section` con título, texto, contador "N de 5 diseños", cuadrícula `auto-fill` de miniaturas subidas y elegidas (botón "Eliminar"), catálogo `auto-fill minmax(110px)` **antes** del dropzone, y aviso al llegar a 5. No hay lugares fijos ni numeración de pasos.
- `bookandsign-front/src/features/booking/components/TattooDesignsSection.tsx`: contiene el phone gate (`usePublicContractPhoneGate`, key `prep-profile:phone:<token>`, `authorizePhone`, normaliza a dígitos). La pantalla de celular ya existe; el diseño la restyliza.
- Hay tests en `TattooDesignsView.test.tsx` y `TattooDesignsSection.test.tsx` que habrá que ajustar al nuevo markup.
- API (#20/#21) sin cambios: `PUT /contracts/public/:token/prep-profile/tattoo-designs`.

### Open questions

Ninguna que cambie el alcance.

- **Nombres del catálogo.** El mockup usa nombres de ejemplo repetidos ("triangulo"); es dato de prueba, no se diseña nada con eso.

### Decisiones

- **2026-11-16** La pista del celular reutiliza el hint enmascarado existente (`TattooDesignsSection.tsx`, últimos 4 dígitos); se descarta el "••31" del mockup.

### Riesgos aceptados

- Drag & drop: `FormDropzone` usa `onDrop` (react-dropzone), ya soporta arrastrar; se conserva el texto del mockup.
- El enmascarado se calcula en el front desde `data.contract.clientPhone`: el teléfono completo ya llega a la página pública. Es previo a este issue y queda fuera de alcance.

### Affected repositories (hint)

- `bookandsign-front`
