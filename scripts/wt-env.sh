#!/usr/bin/env bash
# Deja listo el entorno de un worktree de bookandsign-api: copia los .env y los aísla.
#
#   scripts/wt-env.sh <issue>
#
# Copia .env.local y .env.test del checkout principal al worktree
# <repo-padre>/bookandsign-api-worktrees/issue-<n>-port-<4000+n> sin imprimir su contenido
# (el agente invoca este script y no necesita leer los archivos). En las copias:
#   - quita SUPABASE_DB_URL, SEED_SOURCE_DATABASE_URL (la credencial de lectura de producción
#     la pasa wt-db.sh por su cuenta) y las claves DB_*, PORT y STORAGE_PRIVATE_BUCKET de origen;
#   - fija la base y el puerto de este worktree, y el bucket privado de pruebas (local-priv).
# Nunca modifica los archivos del checkout principal. Crea la base de pruebas del worktree.
# Es idempotente: se puede volver a correr y reescribe las copias.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

n="${1:-}"
[[ "$n" =~ ^[0-9]+$ ]] || die "uso: scripts/wt-env.sh <issue>"

root="$(cd "$(dirname "$0")/.." && pwd)"
parent="$(dirname "$root")"
api_main="$parent/bookandsign-api"
port=$((4000 + n))
wt="$parent/bookandsign-api-worktrees/issue-$n-port-$port"
dev_db="bookandsign_dev_issue_$n"
test_db="bookandsign_test_issue_$n"
private_bucket="local-priv"

[[ -f "$wt/package.json" ]] || die "no existe el worktree $wt"
[[ "$wt" != "$api_main" ]] || die "el destino no puede ser el checkout principal"
[[ "$dev_db" != "bookandsign_dev" && "$test_db" != "bookandsign_test" ]] || die "nombre de base inesperado"

# Copia $1 -> $wt/$1 quitando las claves $2 (regex) y agregando las líneas restantes.
copy_env() {
  local name="$1" strip="$2"; shift 2
  local src="$api_main/$name" dst="$wt/$name" tmp
  [[ -f "$src" ]] || die "falta $src"
  tmp="$(mktemp)"
  grep -Ev "^(${strip})=" "$src" > "$tmp" || true
  printf '%s\n' "$@" >> "$tmp"
  mv "$tmp" "$dst"
  chmod 600 "$dst"
  # Solo nombres de claves, nunca valores.
  echo "$name -> $(cut -d= -f1 "$dst" | grep -E '^[A-Z_]+$' | sort -u | tr '\n' ' ')"
}

copy_env .env.local 'SUPABASE_DB_URL|SEED_SOURCE_DATABASE_URL|DB_HOST|DB_PORT|DB_NAME|PORT|STORAGE_PRIVATE_BUCKET' \
  "DB_HOST=localhost" "DB_PORT=5432" "DB_NAME=$dev_db" "PORT=$port" \
  "STORAGE_PRIVATE_BUCKET=$private_bucket"

copy_env .env.test 'SUPABASE_DB_URL|SEED_SOURCE_DATABASE_URL|DB_HOST|DB_PORT|DB_NAME|STORAGE_PRIVATE_BUCKET' \
  "DB_HOST=localhost" "DB_PORT=5433" "DB_NAME=$test_db" \
  "STORAGE_PRIVATE_BUCKET=$private_bucket"

# Base de pruebas propia del worktree (los tests borran su schema).
test_container="bookandsign-postgres-test"
if ! docker exec "$test_container" psql -U postgres -tAc "select 1 from pg_database where datname='$test_db'" | grep -q 1; then
  docker exec "$test_container" psql -U postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$test_db\"" >/dev/null
fi

echo "worktree issue $n listo: dev=$dev_db (5432), test=$test_db (5433), API en $port, bucket privado $private_bucket"
echo "falta: (cd $wt && pnpm install --frozen-lockfile) y scripts/wt-db.sh create $n"
