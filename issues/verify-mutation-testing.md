chore(executor): mutation testing in the verify step (Stryker in the front, LLM mutants in the API)

### What

Agregar al paso **Verificar** del ejecutor (`docs/executor.md`) una comprobación de que los tests realmente detectan fallas, no solo que pasan:

- **Front:** Stryker sobre los archivos que cambió el issue.
- **API:** un paso validador que se aplica solo en los puntos delicados que señala el ejecutor ("si esto falla, tenemos problemas"). Un modelo barato, distinto del que implementó, introduce mutantes (bugs realistas). Se corren los tests y el mutante se descarta siempre.

La regla de lectura es la misma en los dos repos:

| Tests con el mutante | Significado | Acción |
|---|---|---|
| Fallan | El test protege ese comportamiento | Se descarta el mutante |
| Siguen en verde | **Hallazgo:** ningún test cuida ese comportamiento | Se descarta el mutante y se reporta en el PR |

### Why

El ejecutor escribe el código y también sus tests. Un test en verde no demuestra que proteja algo: puede tener asserts que no comprueban nada (por ejemplo, sobre un mock que el mismo test configuró), un assert existente que se aflojó o un `.skip`. El coverage no lo detecta, porque mide qué líneas se ejecutaron, no qué se comprobó. Hoy la única defensa es la instrucción en prosa, y un agente presionado a dejar los tests en verde puede cumplirla sin probar nada.

El mutation testing invierte la pregunta: rompe el código a propósito y revisa si algún test se da cuenta.

#### Estado actual verificado (2026-11-25; `bookandsign-api` `main` `dff5f5b`, `bookandsign-front` `main` `4197024`)

- **Ningún repo tiene mutation testing:** no hay Stryker, mutmut ni equivalente en `bookandsign-api/package.json`, `bookandsign-front/package.json` ni `brillipoint-print-server/pyproject.toml`.
- **Ejecutor:** el paso 7 de `docs/executor.md` solo corre build y tests (tabla "Verificación por repo"). Nada comprueba que los tests detecten una falla.
- **Front:** vitest `4.1.8` (`vitest.config.ts`), 144 archivos de test en `src/`. `src/features/party/**` está excluido de vitest porque usa `node:test` (`yarn test:party`). El CI (`.github/workflows/ci-cd.yml`) corre `yarn build`, no `yarn test`.
- **Stryker:** `@stryker-mutator/vitest-runner` `10.1.1` declara `vitest >=2.0.0` como peer dependency. No se ha probado con nuestra config (aliases de Next, entorno `node` por defecto, `jsdom` por archivo).
- **API:** jest con `maxWorkers: 1` ("Run tests serially to avoid database deadlocks", `jest.config.ts`) y `dropSchema: isTest` (`src/config/database/data-source.ts`): los tests borran el schema de la base que usan. Con Stryker, los workers en paralelo sobre la misma base se pisarían. En serie, cientos de mutantes sintácticos equivalen a cientos de corridas con Postgres, y eso no es viable.
- **Antecedente:** Meta usa mutantes generados por LLM para medir y endurecer tests (ACH, [arXiv 2501.12862](https://arxiv.org/abs/2501.12862)). Ese trabajo necesitó un detector de mutantes equivalentes (cambios que no alteran el comportamiento) para evitar falsas alarmas.

### Scope

**Entra:**

- Stryker como devDependency de `bookandsign-front`, limitado a los archivos que cambia el issue.
- Paso validador de mutantes con LLM para la API, solo en los puntos delicados que señala el ejecutor.
- Reporte en el PR: por cada mutante, el comportamiento que rompe y su resultado (muerto / sobrevivió / no compila).
- Cambios en `docs/executor.md` (paso Verificar y tabla por repo).

**No entra:**

- `brillipoint-print-server` (Python) y `BrillipointPhotobook` (Swift).
- Tests de `src/features/party/**` (runner `node:test`, fuera de vitest).
- Correr mutation testing en el CI.
- Bloquear el PR por el resultado (ver preguntas abiertas).

#### Propuesta (punto de partida)

- **Front:** `@stryker-mutator/core` y `@stryker-mutator/vitest-runner`. El ejecutor le pasa a Stryker (`mutate`) la lista de archivos de `src/` que cambió el issue, sin incluir tests. El reporte resume el score y los mutantes sobrevivientes.
- **API:**
  1. El ejecutor lista los puntos delicados (función o símbolo) con una línea de por qué.
  2. Un modelo barato, sin ver los tests, genera pocos mutantes por punto. Cada uno es un patch con una frase que dice qué comportamiento rompe.
  3. Cada mutante se aplica en una copia descartable, nunca en el worktree del issue. Primero se compila y luego se corre `jest --findRelatedTests <archivos>` en serie contra `bookandsign_test_issue_<n>`.
  4. Los patches se guardan para poder reproducir el resultado, porque un LLM no genera lo mismo dos veces.
- **Sobrevivientes:** el implementador tiene una ronda para escribir el test que mata cada uno y se vuelve a correr ese mutante. Lo que siga vivo va al PR como pendiente humano.

#### Criterios de aceptación

- `docs/executor.md` describe el paso de mutación para el front y para la API: cuándo aplica, qué comandos corre y cómo se reporta.
- **Front:** en un issue que cambia archivos de `src/`, el ejecutor corre Stryker solo sobre esos archivos y el PR muestra el score y los mutantes sobrevivientes.
- **API:** en un issue con puntos delicados, el PR lista cada punto con su razón y cada mutante con el comportamiento que rompe y su resultado.
- **Prueba de humo, en los dos repos:** un test con un assert débil deja sobrevivir a un mutante y el reporte lo muestra. Al corregir el test, el mismo mutante muere.
- Después del paso, el worktree del issue no contiene código mutado, aunque la corrida se haya interrumpido: `git status` y `git diff` son iguales a como estaban antes del paso.
- Los patches de los mutantes quedan guardados y se pueden volver a aplicar.
- En el front siguen pasando `yarn lint`, `yarn test` y `yarn build`. En la API sigue pasando `pnpm test` sin cambios.

#### Preguntas abiertas

1. **¿Bloquea o solo reporta?** Propuesta: solo reportar hasta tener una línea base de varios issues, y después decidir un umbral.
2. **¿El planeador también puede marcar puntos delicados obligatorios** en el artefacto de Engram, además de los que propone el ejecutor?
3. **¿Cuántos mutantes por punto y cuánto tiempo máximo** para todo el paso?
4. **¿Quién revisa los mutantes equivalentes** que sobreviven: el humano en el PR, o un filtro previo con el mismo modelo barato?
5. **¿Stryker en el CI del front** más adelante? Hoy ese CI no corre `yarn test`.

#### Riesgos

- **Conflicto de interés:** el ejecutor elige dónde se le mide. Puede no señalar justo el código que menos domina.
- **Mutantes equivalentes:** cambios que no alteran el comportamiento sobreviven y generan falsas alarmas.
- **Costo:** cada mutante de la API es una corrida con Postgres. Sin un tope, el paso puede durar más que la implementación.
- **Compatibilidad:** Stryker con vitest 4 y los aliases de Next no está probado.
- **Código mutado en la rama:** si el paso se corta a la mitad y el mutante se aplicó en el worktree del issue, el código roto queda en la rama. Por eso la copia descartable es obligatoria.

### Decisiones

- **2026-11-25:** el front usa Stryker, limitado a los archivos que cambia el issue.
- **2026-11-25:** la API no usa Stryker. Usa un paso validador con mutantes generados por un modelo barato (por ejemplo, Haiku), distinto del que implementó. El mutante se descarta siempre; si sobrevive, es un hallazgo.
- **2026-11-25:** el ejecutor propone los puntos delicados ("si esto falla, tenemos problemas"). Esos son los candidatos para el paso de mutación de la API.

### Repos afectados (pista)

- `brillipoint-ops`: `docs/executor.md`.
- `bookandsign-front`: devDependency, config de Stryker y script.
- `bookandsign-api`: sin cambios de código previstos; los tests y `jest --findRelatedTests` ya existen.

#### Relación

- #33 (e2e de flujos de dinero): los flujos de pago son el caso típico de punto delicado.
