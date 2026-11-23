# CLAUDE.md — brillipoint-ops

## Para qué existe este repo

Aquí **no se implementa nada**. Este repo convierte ideas en issues de GitHub.

El usuario trae una idea (una funcionalidad, un bug, una tarea). Tu trabajo es producir el **markdown del issue**, listo para pegar o publicar, con el contexto suficiente para que otro agente planee e implemente en el repo correcto.

Los repos de producto son hermanos de este (`../bookandsign-api`, `../bookandsign-front`, `../brillipoint-print-server`, `../BrillipointPhotobook`). Puedes **leerlos** para fundamentar el issue. No los modifiques salvo que el usuario lo pida explícitamente.

## Flujo

1. Entiende la idea. Si falta algo que cambia el alcance, haz **una** pregunta y espera.
2. Investiga lo mínimo en los repos afectados: qué existe ya (endpoints, pantallas, entidades), qué falta, qué restricciones hay. Cita paths reales. No inventes.
3. Elige el tipo de issue según `.github/ISSUE_TEMPLATE/` (`feature.yml`, `bug.yml`, `chore.yml`) y respeta sus secciones y su prefijo de título (`feat: `, etc.).
4. Genera el `.md` del issue. Si el usuario lo pide, publícalo con `gh issue create` en el repo indicado. Un issue nuevo nace con `needs-plan`.
5. **Planeación obligatoria.** Con el usuario, resuelve cada pregunta abierta hasta que no quede ningún hueco que cambie el alcance, el contrato entre repos o el modelo de datos. Son dos discusiones, en este orden:
   1. **Producto (PRD, en el issue):** problema, alcance y criterios de aceptación. Cada decisión se escribe en el issue (sección **Decisiones**, con fecha) y lo descartado se anota con su razón.
   2. **Técnica (TDD, en Engram):** cómo se construye, escrito como **Guías** (ver "Decisiones y Guías"). Muéstrale las Guías al usuario en el chat y ajústalas con él antes de guardarlas.

   En **bugs** la discusión técnica es opcional: basta la causa verificada y dónde se corrige. Si el fix toca una Decisión (modelo de datos, migraciones o contrato entre repos), se planea igual que un feature.
6. **Marcar como listo.** Solo cuando no queden huecos y el usuario lo confirme:
   1. Guarda el artefacto de Engram del issue con las Guías aprobadas (ver abajo).
   2. Agrega al cuerpo del issue la sección **Contexto en Engram** con el `topic_key` y el proyecto.
   3. Cambia el label `needs-plan` por `ready-to-implement`.

## Iniciar la implementación de un issue (worktrees)

Solo aplica a un issue `ready-to-implement` y con autorización explícita. El contrato completo vive en `docs/executor.md`; esto es lo esencial para arrancar:

- **Nunca en el checkout principal** de un repo hermano: puede tener trabajo sin commitear. Un worktree por repo afectado.
- **Ruta y nombre:** `<repo>-worktrees/issue-<n>-port-<puerto>`, rama `feat/issue-<n>-<slug>`. El puerto es determinista, `4000 + <n>` (issue 3 → `4003`), y es el `PORT` del servidor de ese worktree; así quien entra al worktree sabe cómo conectarse.
- **Base de datos propia por worktree** (API): `bookandsign_test_issue_<n>` dentro del Postgres de pruebas (`localhost:5433`), pasada con `DB_NAME=...`. Los tests borran el schema de la base que usen: jamás apuntarlos a `bookandsign_dev`.
- Un worktree nuevo no trae `.env*` ni `node_modules`: copiar `.env.test` desde el checkout principal (sin mostrarlo) y correr `pnpm install --frozen-lockfile` (API; Node de `.nvmrc` vía nvm; el front usa yarn).
- **Base poblada y sanitizada (paso obligatorio del flujo):** `scripts/wt-db.sh create <n>` crea `bookandsign_dev_issue_<n>` en el Postgres de desarrollo, corre las migraciones y el seeder sanitizado. La credencial de solo lectura (`SEED_SOURCE_DATABASE_URL` en `bookandsign-api/.env.prod`) la lee el script; el agente no abre `.env.prod`, no ve la credencial ni los datos de origen, y no llama a `db:seed:from-production` directamente. `drop <n>` la borra al terminar. Sirve para validar desde el front y para e2e.
- **Sin push ni PR** mientras `docs/executor.md` mantenga el "modo local".

## Estados del issue

- `needs-plan`: idea capturada, todavía con huecos. **Ningún agente la implementa.**
- `ready-to-implement`: planeada, sin huecos, con artefacto de Engram. Es lo único que un agente (o el cron) puede tomar para implementar.
- Si una **Decisión** no cuadra con el código, el agente que implementa regresa el issue a `needs-plan` con un comentario que explique el hueco. No improvisa. Si lo que no cuadra es una **Guía**, se desvía y lo justifica en el PR.

## Decisiones y Guías

El plan tiene dos niveles de compromiso. Quien planea investiga a fondo y deja el mapa; quien implementa lo verifica contra el código, no lo transcribe.

- **Decisiones (vinculantes, en el issue):** lo caro de revertir: alcance, modelo de datos, migraciones y contrato entre repos. El ejecutor no las cambia.
- **Guías (hipótesis, en Engram):** el cómo local: dónde va el cambio, qué forma darle, qué reutilizar. El ejecutor las verifica y puede desviarse si lo justifica.

Formato de cada Guía:

```
G<n> · confianza: alta (leída en el código) | media (inferida) | baja (supuesta)
Propongo: <qué cambiar> en <archivo> / <símbolo>
Por qué ahí: <evidencia> (leído en <repo>@<commit>)
La invalida: <qué tendría que encontrar el ejecutor para descartarla>
```

- Ancla por símbolo (función, clase, componente), no por número de línea: las líneas cambian entre planear e implementar.
- Una Guía no trae el código hecho. Si para escribirla hace falta implementar, es demasiado detallada.
- "Puerto" significa lo que define `docs/ports.md` (HTTP entre repos). Para arquitectura hexagonal usa "interfaz de dominio" y "adapter".

## Artefacto de Engram

Es el contexto que el agente que implemente no puede reconstruir solo leyendo el issue y el código: por qué se decidió cada cosa, qué se descartó y qué se verificó.

- Proyecto: `brillipoint-ops`. `topic_key`: `issue/brillipoint-ops#<número>` (por ejemplo, `issue/brillipoint-ops#3`). Si el issue cambia después, actualiza el mismo `topic_key`; no crees otro.
- Contenido:
  - Enlace al issue.
  - La razón de cada Decisión (la Decisión vive en el issue; aquí va el porqué).
  - Las Guías (TDD), en el formato de "Decisiones y Guías".
  - Alternativas descartadas y por qué.
  - Evidencia verificada (paths y símbolos en cada repo, commit base con el que se planeó, branches relevantes).
  - Riesgos aceptados.
  - Orden sugerido entre repos.
- El agente que tome el issue primero busca ese `topic_key` en Engram (`mem_search`, luego `mem_get_observation`) y después lee el issue. Si hay contradicción, manda el issue.

## Qué debe tener un buen issue

- **Problema / contexto de negocio**, no solo la solución.
- **Propuesta** como punto de partida, no como decisión final.
- **Criterios de aceptación** observables.
- **Estado actual verificado**: qué ya existe en el código (con path) y qué falta. Ejemplo: "la API de promociones ya expone CRUD completo; el front solo tiene el listado".
- **Preguntas abiertas** y riesgos.
- **Decisiones** (se llenan al planear, con fecha). Las Guías técnicas no van en el issue: van en Engram.
- **Repos afectados** (pista; el agente que planee decide la lista final con cada `system.yaml`).

## Reglas

- **No implementes la funcionalidad** aquí ni en los repos hermanos por iniciativa propia. Una idea es un issue, no un PR. Única excepción: un issue `ready-to-implement` que el usuario autorizó, trabajado en worktrees según la sección anterior.
- **Nunca marques `ready-to-implement` un issue con preguntas abiertas** que cambien el alcance. Las que no lo cambian se mueven a riesgos aceptados.
- El código es la fuente de verdad. Verifica contra el código antes de afirmar qué existe.
- Una idea = un issue. Si son varias, sepáralas y enlázalas.
- Lee `AGENTS.md` (reglas del grafo, puertos y la Fase 1) y `docs/ports.md` antes de tocar nada de arquitectura. No contradigas `docs/ports.md`.
- Nunca edites `graph.json` ni `GRAPH_REPORT.md` a mano.
- Los issues se escriben en el idioma del proyecto (español para el contexto de negocio; identificadores y paths tal cual están en el código).
- Commits con conventional commits, sin atribución de IA.
