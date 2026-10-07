# Contexto para agentes — brillipoint-ops

## Qué es este repo

El punto central de cuatro repos. No contiene código de producto. Contiene la definición de cómo se conectan los sistemas, el grafo agregado, y el inbox de ideas.

## Orden de lectura

1. `docs/ports.md` — **canónico**. Qué cuenta como puerto. No lo contradigas.
2. `docs/system-yaml-spec.md` — el schema
3. `plan.md` — en qué fase estamos

## Reglas

**El código es la fuente de verdad. El grafo es un índice sobre él.**
Graphify puede estar desactualizado, incompleto o ruidoso. Úsalo para acotar la pregunta, después verifica contra el código. Nunca presentes algo derivado del grafo como si estuviera escrito explícitamente en la fuente.

**El grafo contesta "se puede", no "se debe".**
Una ruta técnicamente viable puede estar prohibida por un ADR. Antes de validar una conexión nueva, busca ADRs que toquen ambos componentes. Si hay uno con estado `accepted` que restringe la arista, dilo aunque el camino técnico exista.

**Nunca edites `graph.json` ni `GRAPH_REPORT.md` a mano.** Son derivados. Se regeneran.

**Nunca inventes una arista.** Si no puedes rastrear la llamada hasta código real, no la declares. Un `system.yaml` con aristas supuestas es peor que uno incompleto.

---

## Tarea abierta: Fase 1 — Inventario

Para cada uno de los 4 repos:

1. Encuentra todas las rutas HTTP expuestas (handlers, routers, definiciones de API).
2. Filtra con `docs/ports.md`. **El discriminador es si el consumidor vive en otro repo.** Frontend de BPS llamando API de BPS no es puerto.
3. Encuentra todas las llamadas HTTP salientes a hosts que no son el propio.
4. Genera `system.yaml` en la raíz según el spec.
5. Donde falte archivo de contrato, créalo a partir de la forma real del response. Si la forma no se puede derivar con certeza, marca `contract: TODO` y abre un Issue. **No inventes el schema.**
6. Abre un PR por repo.

**El entregable importante no son los archivos.** Es la lista de sorpresas: puertos que no sabíamos que existían, consumidores no documentados, acoplamientos que nadie aprobó. Repórtalos como Issues separados, uno por hallazgo, con el path del código.

Al terminar, reporta el conteo total de puertos. Si son menos de 8 entre los cuatro repos, dilo explícitamente: hay un criterio de corte en `plan.md` que aplica.
