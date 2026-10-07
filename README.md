# brillipoint-ops

Punto central de los cuatro repos de Brillipoint. Aquí no vive código de producto.

## Qué hay

| | |
|---|---|
| `docs/ports.md` | **Canónico.** Qué cuenta como puerto. |
| `docs/system-yaml-spec.md` | Schema del `system.yaml` que vive en cada repo |
| `plan.md` | Fases, criterios de salida, puntos de corte |
| `AGENTS.md` | Contexto para agentes. Tarea abierta. |
| Issues | Inbox de ideas. Cross-repo. |

## Las dos capas

**Declarado** (`system.yaml`, uno por repo) — lo que dijimos que existe.
**Real** (Graphify sobre los 4 repos) — lo que el código realmente hace.

La comparación entre las dos es la alarma de drift. Sin ella, `system.yaml` es documentación que se cree y el grafo es un dibujo bonito. Con ella, se vigilan mutuamente.

## Issues, no notas

Un `.md` no tiene estado. Un Issue abierto desde hace 90 días te grita. Por eso el inbox son Issues y no archivos.

Los Issues son lo que **estamos considerando**. El grafo es lo que **existe**. No se mezclan.

## Empezar

Fase 0 en `plan.md`: cerrar `docs/ports.md`. Es lo único que no se puede corregir después sin reprocesar los cuatro repos.
