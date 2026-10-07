# Definición de Puerto

**Estado:** canónico. Todo lo demás en este repo depende de esta definición.
**Última revisión:** 2026-09-12

Este documento define qué es un puerto en Brillipoint. Si esta definición cambia, hay que reprocesar los `system.yaml` de los cuatro repos. Cambiarla es caro. Por eso vive aquí y no dentro de un skill.

---

## Definición

> Un **puerto** es una interfaz HTTP que un repo expone y que **otro repo** consume.

Dos condiciones, ambas necesarias:

1. Es HTTP (todo nuestro tráfico entre sistemas lo es).
2. El consumidor vive en **otro repositorio**.

Red local o internet es irrelevante. Eso es despliegue, no arquitectura.

---

## Un puerto es la ruta MÁS la forma

Esta es la parte que no se puede omitir.

El break cross-repo más común no cambia la URL. Alguien le quita un campo al response de `POST /api/leads`, el endpoint sigue existiendo idéntico, y el consumidor truena en producción.

Por eso cada puerto apunta a un **archivo de contrato** (JSON Schema, OpenAPI fragment, o el tipo TypeScript exportado), y el trigger dispara si cambia la ruta **o** si cambia ese archivo.

Sin contrato, `system.yaml` documenta direcciones. Con contrato, documenta compatibilidad, que es lo que importa.

---

## Qué NO es puerto

Como todo es HTTP, sin filtro el skill se dispara siempre. Estos casos quedan fuera:

| Caso | Por qué no |
|---|---|
| Frontend de BPS llamando API de BPS | Mismo repo. Tráfico interno. |
| Refactor interno que no toca rutas declaradas | No cambia la superficie |
| Health checks, métricas, endpoints de infra | Nadie construye lógica sobre ellos |
| Rutas detrás de feature flag apagado | Todavía no son superficie pública |

**Regla ante la duda: no dispara.** El drift check semanal contra Graphify cacha los falsos negativos y no cuesta nada. Un falso positivo sí cuesta: te enseña a ignorar el skill, y a las tres semanas lo desinstalas.

---

## Terceros

Servicios externos (Stripe, WhatsApp, Google) se declaran como `external`.

- **Sí** se declaran: cuando Stripe deprecie algo, quieres preguntarle al grafo quién lo toca.
- **No** entran al drift check: no controlas su lado, no puedes validar el contrato.

Cuesta una línea por servicio.

---

## Identidad estable

Las rutas se renombran. Si el id del puerto es `POST /api/leads`, el día que pase a `/api/v2/leads` el grafo lo lee como borrar un nodo y crear otro, y los ADRs que lo referenciaban apuntan a un fantasma.

**El id es semántico y sobrevive al rename.** El método y la ruta son atributos.

```
✅ bps.leads.create
❌ POST /api/leads
```

Formato: `<repo>.<dominio>.<acción>`

---

## Las dos direcciones

Cada puerto se declara dos veces, en repos distintos:

- **`exposes`** — lo declara quien lo publica. Es la **verdad**.
- **`consumes`** — lo declara quien lo usa. Es la **intención**.

Esto hace que el check central sea una sola aserción:

> Todo `consumes` tiene que resolver a un `exposes` que exista.

Un consumer apuntando a un puerto que nadie expone es un break, y lo cachas sin desplegar nada.

---

## Reglas del trigger

El skill de PR dispara si y solo si el diff:

1. Toca el archivo que define una ruta declarada en `exposes`, **o**
2. Cambia un archivo de contrato referenciado por un puerto, **o**
3. Introduce una llamada HTTP a un host que no es el propio

No dispara en ningún otro caso.
