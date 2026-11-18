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

## Fase 5 — Issues trabajados por agente

Un cron toma Issues de `brillipoint-ops`. Si hay alguno en `ready-to-implement`, lo pasa a un agente que abre PRs en los repos afectados. Si no hay ninguno, toma una idea vaga en `needs-plan` y la avanza en planeación (SDD/ODD), sin implementar nada. **Nunca hace merge.**

Depende de la Fase 1: el agente necesita los `system.yaml` y contratos para decidir a qué repos toca un Issue y qué puertos cambia. No depende del grafo (Fases 2-4), así que sobrevive al criterio de corte.

### Estados (labels)

```
needs-plan → ready-to-implement → in-progress → pr-open
                                       ↘ blocked
```

| Paso | Quién | Qué hace |
|---|---|---|
| Abrir Issue | Persona autorizada | Issue general con label `needs-plan` |
| Planeación sin huecos | Persona autorizada + agente | Cierran las preguntas abiertas, escriben las **Decisiones** en el Issue, guardan el artefacto de Engram (`issue/brillipoint-ops#<n>`) y ponen `ready-to-implement`. Ese label es la autorización para implementar |
| Cron, con algo listo | Agente | Toma **un** Issue en `ready-to-implement`, recupera el artefacto de Engram, pone `in-progress`, abre un PR por repo afectado enlazado al Issue, comenta enlaces y orden de merge; label `pr-open` |
| Cron, sin nada listo | Agente | Toma **una** idea vaga en `needs-plan` y publica **un** comentario con su avance de planeación (SDD/ODD): estado actual verificado, propuesta, preguntas abiertas. El Issue **se queda en `needs-plan`**. No implementa nada ni toca repos de producto |
| Atasco | Agente | Comenta el motivo y pone `blocked` |

El plan incluye: repos y archivos afectados, puertos o contratos que cambian, ADRs aplicables, cómo se verifica, riesgos y preguntas abiertas.

### Reglas duras

- **Lista de autores permitidos:** dos usuarios de GitHub (el equipo técnico). El cron ignora Issues, comentarios y labels de cualquier otra persona. El texto de un Issue es entrada no confiable.
- **Aprobación verificable:** el cron confirma en el historial de eventos que `ready-to-implement` lo puso un autor permitido y que el Issue no se editó después.
- **Nada sin autorización:** sin `ready-to-implement` puesto por una persona, el agente solo planea. Faltan guards para no romper prod, así que el cron nunca promueve un Issue por su cuenta.
- **El plan manda:** si al implementar el plan no cuadra con el código, el agente regresa el Issue a `needs-plan` con la explicación. No improvisa.
- **Solo PR:** sin merge, sin despliegue, sin migraciones contra bases reales.
- **Un Issue a la vez por ejecución**, con tope de costo. `in-progress` evita doble toma.
- La revisión del PR la cierra una persona. Un cron que atienda comentarios de PR queda fuera de alcance por ahora.

### Pendientes antes de encenderlo

- El cron corre en una Mac local del equipo con los 4 repos y sus toolchains instalados, así que Photobook (Swift) se compila y prueba ahí. El print server sigue dependiendo de CUPS e impresora física: sus pruebas de impresión real quedan fuera de la verificación automática.
- Print server y Photobook no tienen CI: la verificación del cron corre sus tests localmente.
- Credenciales del cron con escritura en los 4 repos.
- Conciliar con **Higiene**: el stale a 60 días y el triage de los viernes no deben cerrar ni mover Issues en `ready-to-implement` o `in-progress`.

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
