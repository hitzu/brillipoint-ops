feat(ops): centralized event checklists in the staff app

### Problem

Las listas de qué revisar antes, durante y después de un evento están repartidas en varios lugares: archivos markdown en los repos, el manual de marca y otros lugares fuera del código. Esto causa tres problemas:

- **Nadie sabe quién revisó qué.** Una lista en un markdown no registra quién la marcó ni cuándo.
- **El conocimiento depende de quien lo explique.** Quien entra nuevo aprende la operación de boca en boca.
- **Las listas no mejoran.** Cuando algo falla en un evento, no hay un lugar único donde agregar "la próxima vez, revisar X".

Centralizarlas en la app es también una forma de vaciar el conocimiento operativo en el sistema, donde lo pueden usar el staff y los agentes.

**Estado actual verificado (2026-11-22; `bookandsign-api` `main` `3542646`, `bookandsign-front` `main` `1076b95`, `brillipoint-print-server` `main` `a9d24e1`):**

- **Listas en markdown (print server):**
  - `checklist-evento.md`: antes de prender la compu (DNP, USB, papel y ribbon), correr el doctor, levantar el stack, confirmar en el panel, fallas comunes y qué hacer si algo se rompe durante el evento.
  - `tutorial-instalacion.md`: 7 pasos para instalar el print server en una compu nueva.
- **Lista en el front:** el manual de marca tiene un "Checklist de imprenta" (`src/features/brand-manual/components/sections/PrintSection/index.tsx:10-17`), con los puntos fijos en código (`PRINT_CHECKS`, `usePrintChecklist.ts:6`). Es para piezas impresas de marca, no para eventos.
- **No hay una entidad de checklist en la API.** Lo más cercano:
  - `notes` (`scope`, `targetId`, `kind`, `content`, `createdBy`): notas internas ligadas a un contrato u otro objetivo.
  - `contract_preparation_profiles`: el cuestionario que llena **el cliente** en `/reserva`, no el staff.
- **No hay staff asignado a un evento.** Ninguna entidad de bookings ni de eventos tiene operador asignado. Los roles son `admin` y `sales_agent` (`src/users/constants/user_role.enum.ts`).

### Proposal

- **Plantillas:** listas reutilizables por momento (por ejemplo: preparación, montaje en el venue, durante el evento, cierre). Posiblemente también por tipo de servicio (cabina, glitter bar). Las edita un `admin`.
- **Instancias:** al acercarse un evento, se crea su checklist a partir de las plantillas que le aplican.
- **Marcar ítems:** cada ítem guarda quién lo marcó y cuándo. Se usa desde el celular en el venue.
- **Contenido inicial:** el contenido de `checklist-evento.md` se carga como la primera plantilla.
- **Visibilidad:** en la agenda se ve qué eventos próximos tienen la checklist incompleta.
- **Fase 2 (por decidir):** después de cada evento, lo que salió mal alimenta las plantillas (se relaciona con la idea del post-mortem de evento con un agente).

### Acceptance criteria

- Un `admin` crea y edita plantillas de checklist con ítems ordenados.
- Cada evento próximo tiene su checklist, creada a partir de las plantillas que le aplican.
- Desde el celular, el staff marca ítems y cada marca guarda el usuario y la hora.
- Editar una plantilla no cambia las checklists de eventos ya pasados.
- En la agenda se distingue un evento con checklist completa de uno incompleto.
- El contenido de `checklist-evento.md` existe como plantilla en la app.
- Tests de la API: crear plantilla, crear instancia desde plantilla, marcar y desmarcar ítem, y que editar la plantilla no altere instancias pasadas.
- `pnpm run build` y los tests de la API pasan; el front construye.

### Open questions

1. **¿Dónde viven las otras checklists que hoy están fuera del código?** (WhatsApp, notas, papel, etc.) Hay que juntarlas para armar las plantillas iniciales.
2. **¿La checklist es por evento, por reserva (booking) o por servicio?** Un mismo contrato puede tener cabina y glitter bar.
3. **¿Qué momentos existen?** Por ejemplo: un día antes, al cargar el equipo, en el venue, al cerrar.
4. **¿Hay ítems obligatorios que bloqueen algo** (por ejemplo, cerrar el evento) o la checklist es solo informativa?
5. **¿Se necesita usar sin internet en el venue?**
6. **¿El "Checklist de imprenta" del manual de marca entra en este sistema** o se queda como está?
7. **¿Quién puede editar plantillas?** ¿Solo `admin`?

**Riesgos:**

- Sin staff asignado a cada evento, no hay a quién recordarle una checklist incompleta. Puede requerir el issue de asignar operador a evento.
- Si las plantillas cambian seguido, hay que decidir si una checklist en curso se actualiza o se queda con la versión con la que se creó.

### Affected repositories (hint)

brillipoint-api
brillipoint-front
