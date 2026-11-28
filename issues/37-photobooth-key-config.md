chore(api): load the photobooth key from configuration

### What

Mover la llave del photobooth (header `x-photobooth-key`) a configuración, en la API y en el iPad, y generar un valor nuevo al moverla.

### Why

Hoy el valor de la llave vive en el código de la API y en el del iPad. Cambiarlo exige tocar código en los dos repos, no se puede tener un valor distinto por ambiente y nada obliga a que esté configurado. Además, el issue de rate limiting va a usar esta misma llave para exentar al photobooth del límite.

#### Estado actual verificado (2026-11-26; `bookandsign-api` `main` `3542646`, `BrillipointPhotobook-` `main` `2c164b7`)

- **La API compara el header con un valor escrito en el código.** No lo lee de la configuración, y `.env.example` no lista ninguna variable para la llave.
- **El iPad lee `PHOTOBOOTH_API_KEY` del entorno del proceso y, si no existe, usa un valor escrito en el código.** En una app instalada (no corriendo desde Xcode) esa variable no existe, así que siempre usa el valor del código.
- El detalle con paths está en Engram (`issue/brillipoint-ops#37`).

### Scope

**Entra:**

- La API lee la llave de la variable de entorno `PHOTOBOOTH_API_KEY`.
- La comparación del header se hace en tiempo constante.
- El iPad lee la llave de un archivo de configuración que no se versiona.
- Un valor nuevo, generado por una persona y cargado en Render y en el iPad.
- `.env.example` documenta la variable, sin valor.

**No entra:**

- Rate limiting (issue aparte).
- Otros cambios en cómo se autentica el iPad.

#### Propuesta (punto de partida)

- El header sigue llamándose `x-photobooth-key`. El iPad no cambia cómo lo manda, solo de dónde saca el valor.
- Sin valor de respaldo: si la variable falta o está vacía, la API rechaza toda petición que necesite la llave.
- Sin periodo de transición: en cuanto se despliega la API, el valor anterior deja de aceptarse.
- El valor lo genera y lo carga una persona. El agente que implementa no lo ve ni lo imprime.

#### Criterios de aceptación

- Con la variable configurada: el valor correcto pasa, y un valor incorrecto o la falta de header reciben `401`.
- Sin la variable, la API no acepta ningún valor.
- En producción, el valor anterior ya no se acepta.
- El valor no aparece en el código de la API ni del iPad, ni en los logs.
- El iPad instalado (no corriendo desde Xcode) manda el valor nuevo y el flujo del photobooth que usa la llave funciona.
- Hay tests del guard para los casos: sin header, valor incorrecto, valor correcto y variable ausente.
- `pnpm run build` y los tests de la API pasan; el iPad compila.

#### Pasos humanos

1. Generar el valor nuevo (por ejemplo, `openssl rand -hex 32`).
2. Cargarlo como `PHOTOBOOTH_API_KEY` en Render y en el `.env.local` de desarrollo.
3. Ponerlo en el archivo de configuración del iPad y compilar.

#### Riesgos

- Entre el deploy de la API y la instalación del iPad nuevo, el flujo del photobooth que usa la llave responde `401`.
- Si la variable no se carga en Render antes del deploy, ese flujo queda rechazado hasta que se cargue.

### Decisiones

Se llenan durante la planeación.

### Affected repositories (hint)

brillipoint-api
BrillipointPhotobook-
