chore(api): global rate limiting

### What

Agregar rate limiting a la API: un límite global para todas las rutas y límites más estrictos en las rutas sensibles. Cuando un cliente pasa el límite, la API responde `429 Too Many Requests` y el front muestra un mensaje claro.

### Why

La API recibe tráfico público: la página de reserva, la fiesta, las fotos de los invitados y el photobooth. Hoy nada limita cuántas peticiones puede hacer un mismo cliente. Un script o un error en un cliente puede saturar la API, subir el costo de storage o ensuciar las métricas (#27).

#### Estado actual verificado (2026-11-23; `bookandsign-api` `main` `3542646`)

- **La API no tiene rate limiting** (ni `@nestjs/throttler` ni un equivalente).
- **Corre en Render, detrás de un proxy** (`.github/workflows/pipeline-main.yml`, job `deploy`). Express no está configurado para leer la IP real del cliente (`src/main.ts`).
- **`ioredis` está en `package.json` pero ningún archivo de `src` lo usa.** Redis solo existe en `docker-compose.yml` para desarrollo.
- **Render corre una sola instancia de la API.**
- **La fiesta consulta la API cada 4 segundos mientras espera fotos** (`bookandsign-front` `main` `3761a82`): `FiestaPage` pide la galería del evento mientras está vacía y `MisFotosPage` pide la sesión hasta que tenga fotos. Cada celular hace unas 15 peticiones por minuto a la misma ruta.
- **Los repos son públicos.** El detalle de qué rutas reciben qué límite se planea fuera de este issue (Engram).

### Scope

**Entra:**

- Límite global en la API y límites por ruta para las rutas sensibles.
- Contar por la IP real del cliente, no por la IP del proxy de Render.
- Un header con secreto que identifica al photobooth y lo exenta del límite.
- Respuesta `429` con el header `Retry-After`.
- Manejo del `429` en el front.

**No entra:**

- Protección a nivel de red (WAF, Cloudflare).
- Bloqueo permanente de IPs o listas negras.

#### Propuesta (punto de partida)

- `@nestjs/throttler` como guard global con el límite por defecto, y `@Throttle` para subirlo en las dos rutas de la fiesta (punto de partida: 300 por minuto, unos 20 celulares por IP).
- `trust proxy` en Express para que `req.ip` sea la IP del cliente.
- Contadores en memoria, porque Render corre una sola instancia.
- El photobooth manda un header con un secreto en todas sus llamadas a la API: subidas, analytics y el resto. La API lo compara con una variable de entorno y, si coincide, no le aplica el límite (`skipIf` de `@nestjs/throttler`). El header no da ningún otro permiso.

#### Criterios de aceptación

- Un cliente que pasa el límite de una ruta recibe `429` con `Retry-After`. Los demás clientes siguen respondiendo normal.
- Dos clientes con IPs distintas detrás del proxy de Render tienen contadores separados.
- Una fiesta con muchos invitados en el mismo Wi-Fi (misma IP pública) puede ver y bajar sus fotos sin recibir `429`.
- El photobooth puede subir las fotos de un evento en ráfaga sin recibir `429`, incluso al vaciar una cola de sesiones atrasadas cuando vuelve la conexión.
- Un cliente que manda el header sin el secreto correcto sigue limitado.
- El secreto no está en el código de la API: vive en una variable de entorno de Render.
- El front muestra un mensaje entendible ante un `429`, en lugar de un error genérico.
- Hay tests del guard: pasa bajo el límite, responde `429` arriba del límite y respeta las rutas excluidas.
- `pnpm run build` y los tests de la API pasan; el front construye.

#### Preguntas abiertas

Ninguna.

#### Riesgos

- Un límite mal calibrado bloquea a clientes reales en plena fiesta o a la mitad de una reserva.
- Sin `trust proxy`, todos los clientes comparten un solo contador y el límite bloquea a todos a la vez.
- Si Render pasa a varias instancias, los contadores en memoria multiplican el límite real por el número de instancias.

#### Relación

- #27 aceptó el riesgo de que se inflen las visitas por abuso; este issue lo cubre.
- #34 (Sentry) ayudaría a ver los `429` en producción.

### Decisiones

- **2026-11-23:** Contadores en memoria, sin Redis. Render corre una sola instancia.
- **2026-11-23:** El iPad no maneja `429`. El photobooth queda exento del límite.
- **2026-11-23:** Los límites arrancan bajos, alrededor de 50 peticiones por minuto. Se ajustan con datos.
- **2026-11-23:** Un límite por defecto para todas las rutas y uno más alto solo en las dos rutas que la fiesta consulta cada 4 segundos (galería del evento y sesión de "mis fotos"). Así un salón con muchos invitados en el mismo Wi-Fi no recibe `429`.
- **2026-11-23:** El photobooth se identifica con un header propio con secreto, no con la cuenta de usuario. El header solo sirve para quedar exento del límite.

### Affected repositories (hint)

brillipoint-api
brillipoint-front
BrillipointPhotobook-
