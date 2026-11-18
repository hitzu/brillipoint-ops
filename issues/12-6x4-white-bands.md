fix(print-server): 6x4 prints do not fill the sheet (white bands)

### What happened

La foto no llena la hoja 6×4 en dos caminos distintos:

1. **"Por tamaño" → "6×4 vertical"** (Historial y Upsell): la impresión sale con líneas blancas.
2. **Template con un slot de foto en x=0, y=0, ancho 6, alto 4:** la foto no llena el template completo.

### Steps to reproduce

**Camino 1**
1. Abrir Historial o Upsell y seleccionar una foto.
2. Elegir "Por tamaño" → "6×4 vertical" → "Enviar a cola DNP".
3. La hoja sale con franjas blancas arriba y abajo.

**Camino 2**
1. En el editor de templates, crear un template horizontal (6×4).
2. Agregar un slot de foto con x=0, y=0, ancho 6 in, alto 4 in.
3. Ver la vista previa o imprimir: queda un borde sin foto alrededor.

### Expected behavior

La foto cubre toda la hoja recortada de 6×4 in, sin bordes blancos, en los dos caminos.

Dirección de arreglo (punto de partida, a decidir en la planeación):

- **Camino 1:** encajar la foto con *cover* (recortar usando el punto focal que el Upsell ya manda, `focal_x`/`focal_y`) en lugar de *contain*. Costo: una captura 3:4 en una hoja 2:3 pierde ~11 % del ancho.
- **Camino 2:** cuando un slot toca un borde del lienzo de diseño, extenderlo al sangrado del raster del PPD, para que la foto llegue hasta donde imprime la DNP.

### Environment

Print server en la rama `feat/flow-remap-pr9`, impresora DNP con cola 4×6 (raster del PPD: 1241×1845 px a 300 dpi = 4.137×6.150 in). Por confirmar si pasa igual en el evento real.

### Evidence

**Causa (verificada en el código; falta confirmarla con una impresión física):**

**Camino 1, encaje contain:** `render_dnp_full_pages` (`app/mini_book/composer.py:141-169`) usa `contain_placement`, que nunca recorta. Su propio docstring lo avisa: una captura 3:4 en una hoja 2:3 deja una franja blanca arriba y abajo. Además encaja contra todo el raster del PPD (4.137×6.150 in, `app/mini_book/service.py:24-31`), no contra el 4×6 que queda después del corte. Cuenta: la foto ocupa 1241 px de ancho → 1655 px de alto → 95 px (~0.32 in) de blanco arriba y abajo; el corte de la DNP quita ~22 px por lado y quedan ~0.24 in de blanco visible en cada extremo.

**Camino 2, el espacio de diseño no cubre el sangrado:** `Canvas` (`app/templates/render/geometry.py:303`) centra el espacio de diseño de 6×4 in dentro del raster más grande del PPD (la DNP imprime de más y el cortador recorta a 4×6). En horizontal el lienzo de trabajo es 1845×1241 px y el diseño 1800×1200 px, con origen en (22, 20) px. Un slot 0,0,6,4 cubre exactamente 1800×1200 y deja ~22 px (0.075 in) a los lados y ~20 px (0.068 in) arriba y abajo con solo el fondo, que `_paint_background` sí estira a todo el raster (`app/templates/render/pipeline.py:139-161`). La validación no deja dibujar fuera del 6×4 (`app/templates/catalog.py:285-286`, `SlotOutsideCanvasError` en `:320`), así que el operador no puede llevar la foto al sangrado. La vista previa enmascara justo esa franja (`_design_area_in_png`, `app/templates/service.py:308-329`). Si el corte no cae perfectamente centrado, la franja sale como una línea blanca. Una calibración con offsets o escala distinta de 1 (`Canvas.len_px`) la puede ensanchar de un lado.

### Decisiones (2026-11-09)

1. **Camino 1: se quita la opción "6×4 vertical" del menú de tamaños** (Historial y Upsell). No se arregla el encaje.
   - Descartado: *cover* con punto focal. Recortar ~11 % del ancho pierde información de la foto.
   - La foto que llene la hoja 6×4 sin bordes se resolverá con un template en formato polaroid grande, a cargo del diseñador (fuera de este issue).
2. **El selector de tamaño se queda**, aunque por ahora solo tenga Minibook: se van a agregar más tamaños y quitarlo obligaría a rehacerlo.
3. **Se borra el layout `full` completo**, no solo la opción del menú: UI (`mini_book.html`, `mini_book.js`), API (`MiniBookLayout` en `app/api/mini_book_routes.py`, `per_sheet` en `app/api/ui_routes.py`) y composer (`render_dnp_full_pages` en `app/mini_book/composer.py`, `LAYOUT_FULL` en `app/mini_book/service.py`). Evita dejar código muerto con el bug; el único consumidor es esta UI.
4. **Camino 2: no se toca el código.** El diseñador lo resuelve con el fondo del template (el fondo ya se estira a todo el raster, `_paint_background`). Descartado: extender los slots que tocan el borde al sangrado y relajar `SlotOutsideCanvasError`.

### Contexto en Engram

- Proyecto: `brillipoint-ops`
- `topic_key`: `issue/brillipoint-ops#12`

### Affected repositories (hint)

brillipoint-print-server
