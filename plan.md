# Plan de arranque — brillipoint-ops

**Fecha:** 2026-09-12

## Qué estamos construyendo

Un punto central que sepa el estado "casi real" de los 4 repos, para que cuando rebote ideas después de un evento el agente pueda contestar no solo *"¿se puede conectar BPS con PB?"* sino *"¿deberíamos?"*.

Tres piezas, tres momentos distintos:

| Pieza | Cuándo corre | Qué hace |
|---|---|---|
| Skill de PR | Al cambiar un puerto | Actualiza `system.yaml` del repo |
| Drift check | Semanal, en CI | Compara declarado vs real |
| `event-interview` | Post-evento, 10 min | Saca ideas estructuradas a Issues |

---

## Dependencia que hay que nombrar

Crear `brillipoint-ops` **requiere tocar los otros cuatro repos**. Los `system.yaml` viven ahí, no aquí. Esto no es un proyecto de un repo.

---

## Fase 0 — Definición (bloqueante)

`docs/ports.md` cerrado y aprobado.

Es lo único que no se puede corregir después sin reprocesar los cuatro repos. Todo lo demás es refactorizable.

**Salida:** documento firmado.

---

## Fase 1 — Inventario

Un agente lee los cuatro repos y genera los `system.yaml` iniciales aplicando la definición de puerto.

**El entregable no es el archivo, es el descubrimiento.** Vas a encontrar puertos que no sabías que existían, consumidores no documentados, y al menos un acoplamiento que no habrías aprobado. Ese hallazgo vale más que toda la automatización posterior.

Tarea mecánica y perfecta para delegar. Ver `AGENTS.md`.

**Salida:**
- 4 × `system.yaml` en la raíz de cada repo
- 4 × PR con los contratos faltantes creados
- Lista de sorpresas encontradas, en Issues

**Criterio de corte:** si la Fase 1 revela menos de ~8 puertos en total entre los cuatro repos, **detente aquí**. Con esa superficie, los cuatro `system.yaml` y un README de arquitectura te alcanzan. Las fases 2-4 no se pagan.

---

## Fase 2 — Drift check

El check central en CI de `brillipoint-ops`. Checkout de los 4 repos en un directorio, corre Graphify una vez, compara contra lo declarado.

Se hace antes que el skill de PR **a propósito**: es lo que enforza, y funciona aunque nadie use nunca el skill. El skill solo reduce fricción.

**Salida:**
- Workflow semanal + en push a main de cualquier repo
- `graph.json` agregado, commiteado
- Reporte de drift como Issue automático

---

## Fase 3 — Skill de PR

Lee el diff, propone el parche de `system.yaml` ya escrito. Aprobar o corregir.

**Regla dura:** nunca pregunta algo que está en el diff. Máximo dos preguntas, ambas sobre intención:
1. ¿Permanente o temporal? → decide si además necesita ADR
2. ¿Quién puede consumirlo? → público vs interno

El CI es el gate. El skill es la comodidad. Si el skill es el gate, lo vas a saltar.

---

## Fase 4 — `event-interview`

Depende de que el grafo tenga nodos de ADR, o sea de que las fases 1-2 estén corriendo.

Consulta el grafo antes de preguntar. En vez de *"¿qué componentes toca esto?"* propone *"esto tocaría BPS y PB, y ADR-0007 restringe esa ruta, ¿sigue aplicando?"*.

Salida: Issue en `brillipoint-ops` con labels de repo destino ya puestos.

**Señal de salud:** la entrevista se acorta con el tiempo, porque el grafo sabe más. Si a los tres meses sigue haciendo las mismas cuatro preguntas, el grafo no está pagando. Córtalo.

---

## Higiene

- Action que marca `stale` a los 60 días y cierra a los 90
- Triage de 15 min los viernes: cada Issue del inbox sale por una puerta (se mueve a un repo con fecha, se vuelve ADR, o se cierra). Nada se queda dos semanas seguidas.

---

## Cómo sabemos que valió la pena

Antes de Fase 2, anota cuánto te toma hoy contestar con confianza: *"si cambio X en PB, ¿qué se rompe?"*

Si en tres meses no bajó de forma obvia, apaga las fases 2-4 y quédate con los `system.yaml`. Graphify no es una ganancia automática en repos pequeños, y cuatro repos están en la frontera.

---

## Lo que NO va en este repo

- Código de producto
- Los `system.yaml` (viven en cada repo)
- Notas personales que nadie va a releer

Los Issues son lo que **estamos considerando**. El grafo es lo que **existe**. Mezclarlos devuelve el cementerio.
