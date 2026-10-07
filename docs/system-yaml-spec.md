# Spec: `system.yaml`

Vive en la **raíz de cada repo**, no en `brillipoint-ops`. Se versiona junto al código que describe, y cambia en el mismo PR que cambia el puerto.

`brillipoint-ops` solo agrega y valida. No es dueño de ningún `system.yaml`.

---

## Ejemplo completo

```yaml
# Identidad del componente. Estable, nunca cambia.
id: bps
name: Brillipoint Sistema (leads y reservas)
repo: Gingiris/bps

# Puertos que este repo PUBLICA. Esto es la verdad.
exposes:
  - id: bps.leads.create
    http: POST /api/leads
    contract: ./contracts/leads.create.json   # obligatorio
    consumers: [pb]                            # informativo, ayuda al blast radius
    since: ADR-0003                            # opcional

  - id: bps.leads.status
    http: GET /api/leads/:id/status
    contract: ./contracts/leads.status.json
    consumers: [pb, partners]

# Puertos de OTROS repos que este consume. Esto es intención.
consumes:
  - port: pb.gallery.publish
    since: ADR-0007        # la decisión que autorizó esta arista

# Terceros. Declarados pero fuera del drift check.
external:
  - service: stripe
    endpoints:
      - POST /v1/payment_intents
  - service: whatsapp-cloud
    endpoints:
      - POST /v1/messages
```

---

## Campos

### Raíz

| Campo | Obligatorio | Notas |
|---|---|---|
| `id` | sí | Corto, estable, minúsculas. Prefijo de los ids de puerto. |
| `name` | sí | Legible para humanos |
| `repo` | sí | `owner/repo` en GitHub |
| `exposes` | sí | Lista, puede ir vacía |
| `consumes` | sí | Lista, puede ir vacía |
| `external` | no | Omitir si no hay |

### `exposes[]`

| Campo | Obligatorio | Notas |
|---|---|---|
| `id` | sí | `<repo>.<dominio>.<acción>`. Sobrevive al rename de ruta. |
| `http` | sí | `MÉTODO /ruta`. Es atributo, no identidad. |
| `contract` | **sí** | Path relativo. Sin esto el puerto no está declarado de verdad. |
| `consumers` | no | Quién lo usa hoy. Informativo. |
| `since` | no | ADR que lo introdujo |
| `deprecated` | no | Fecha objetivo de retiro |

### `consumes[]`

| Campo | Obligatorio | Notas |
|---|---|---|
| `port` | sí | Id completo del puerto ajeno |
| `since` | no | **ADR que autorizó la arista.** Este campo es el que conecta el grafo técnico con la capa de decisiones. Ponerlo siempre que exista. |

---

## Validaciones del check central

Corre en `brillipoint-ops`. Falla si:

1. Algún `consumes[].port` no resuelve a un `exposes[].id` existente en otro repo → **break**
2. Algún `exposes[]` no tiene `contract`, o el archivo no existe → **declaración incompleta**
3. Dos repos declaran el mismo `exposes[].id` → **colisión**
4. Graphify detecta una llamada cross-repo que no está en ningún `consumes` → **drift**
5. Un `consumes[].since` apunta a un ADR con estado `superseded` o `rejected` → **arista huérfana**

Las primeras tres son errores duros. La 4 y la 5 son warnings semanales, no bloquean PRs.
