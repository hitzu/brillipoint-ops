chore(photobook): remove Supabase and the dead GIF feature from the Photobook

### What

Quitar del Photobook todo lo que habla con Supabase o lo nombra: el GIF (funcionalidad muerta), la cola vieja de subidas directas a Supabase, la configuración del proyecto de Supabase y el paquete `supabase-swift`. Renombrar el cliente de la API, que hoy se llama `SupabaseService` aunque no habla con Supabase.

Es el **paso 0a** de la migración de storage a R2 (#25, Decisiones 11 y 14). Solo toca el Photobook y se despliega solo.

No cambia nada para el staff ni para los clientes: las fotos y los videos se siguen subiendo por el flujo firmado de la API, igual que hoy.

### Why

- En el #25, las subidas nuevas van a ir a R2 (paso 1). El Photobook todavía arma la URL del GIF con el formato de Supabase, y tiene un camino viejo que sube directo a Supabase. Los dos tienen que desaparecer antes de ese paso.
- El Photobook no debe conocer al proveedor de storage (Decisión 11 del #25): sube con las URLs firmadas que le da la API y nada más.
- Las dos cosas que tocan Supabase están muertas: el GIF dejó de usarse hace tiempo, y la cola vieja no recibe trabajos desde hace meses (usuario).

#### Decisiones (2026-11-27)

1. **El GIF se elimina completo** (usuario): generación, subida y estado. No se reemplaza.
2. **La cola vieja de `SupabasePhotoService` se borra sin migrar sus trabajos** (usuario). Está vacía y lleva meses sin usarse. Resuelve la pregunta 8 del #25.
3. **Sin cambios de contrato con la API.** El GIF usaba los mismos endpoints que las fotos de sesión, que siguen igual.

#### Estado actual verificado (2026-11-27; `BrillipointPhotobook-` `main` `2c164b7`)

- **GIF:** `AppViewModel.startGIFGeneration` no tiene llamadas. Es el único usuario de `GIFGenerator` y de `SessionPhotoUploader.uploadGIF`, que arma la URL pública con el formato de Supabase (`publicURL(from:)` con `SupabaseEnv.url`). El estado del GIF vive en `SessionViewModel` y nadie más lo lee.
- **Cola vieja:** `SupabasePhotoService` sube directo a Supabase Storage. Nadie le agrega trabajos, pero `AppViewModel` arranca su worker al abrir la app, suma sus pendientes al contador de la consola y la incluye en "Reintentar fallidas". `PhotoService.swift` (protocolo y tipos) solo lo usa ese servicio.
- **Configuración:** `SupabaseEnv` (URL y key del proyecto) la usan `SupabasePhotoService`, `SupabaseClientProvider` y `publicURL(from:)`. `SupabaseClientProvider` no tiene usos.
- **Paquete:** `supabase-swift` está en `project.pbxproj` y en `Package.resolved`.
- **`SupabaseService` es el cliente de la API:** `fetchEvent(byKey:)` llama a `/v2/events/by-key`. Solo el nombre es de Supabase.
- El detalle con símbolos está en Engram.

### Scope

**Entra:**

1. Eliminar el GIF completo.
2. Eliminar `SupabasePhotoService`, `PhotoService.swift` y su uso en `AppViewModel` (worker, contador y reintento).
3. Eliminar `SupabaseClientProvider`, `SupabaseEnv`, `SupabaseEnv.example` y el paquete `supabase-swift`.
4. Renombrar `SupabaseService` con un nombre que no mencione al proveedor, y actualizar los comentarios que nombran a Supabase.

**No entra:**

- Cambios en la API o en el front.
- La cola actual de subidas (`SessionPhotoUploader`, `SessionVideoUploader`) y la generación de variantes (minimizada y poster), que se quedan en el iPad (Decisión 13 del #25).

#### Criterios de aceptación

- Una búsqueda de `supabase` (sin distinguir mayúsculas) en el código del Photobook no encuentra nada. `supabase-swift` ya no está en `project.pbxproj` ni en `Package.resolved`.
- No queda código del GIF: ni `GIFGenerator`, ni `uploadGIF`, ni su estado en `SessionViewModel`.
- Las fotos y los videos de una sesión se suben igual que hoy, incluida la cola diferida.
- El contador de pendientes y "Reintentar fallidas" de la consola del operador funcionan con la cola actual.
- La carga del evento por llave funciona igual.
- El proyecto compila y los tests del scheme `BrillipointPhotobook` pasan.

#### Riesgos

- Si la cola vieja tuviera trabajos, sus fotos quedarían en el disco del iPad sin subir. Riesgo aceptado: el usuario confirma que está vacía.
- Quitar el paquete a mano puede dejar referencias rotas en `project.pbxproj`. Se quita desde Xcode y se confirma compilando.

#### Relación

- #25 migración de storage a R2: este issue es su paso 0a (Decisiones 11 y 14) y debe estar integrado antes de su paso 1.

### Affected repositories (hint)

BrillipointPhotobook-

### Contexto en Engram

- Proyecto: `brillipoint-ops`
- `topic_key`: `issue/brillipoint-ops#38`

### Cierre

- Commit `30383a2` en `BrillipointPhotobook-` `main`. Ver el cuerpo del issue #38 en GitHub.
