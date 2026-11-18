#!/usr/bin/env bash
# Base de datos local poblada y sanitizada para un worktree de bookandsign-api.
#
#   scripts/wt-db.sh create <issue>   crea bookandsign_dev_issue_<n>, corre migraciones y el seeder
#   scripts/wt-db.sh drop <issue>     borra esa base
#   scripts/wt-db.sh status <issue>   cuenta filas de tablas clave
#
# La credencial de solo lectura de producción se toma de la clave SEED_SOURCE_DATABASE_URL
# en bookandsign-api/.env.prod. Este script nunca la imprime; quien lo invoca (persona o
# agente) no necesita verla ni leer los datos de origen.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

cmd="${1:-}"; n="${2:-}"
[[ "$cmd" =~ ^(create|drop|status)$ && "$n" =~ ^[0-9]+$ ]] \
  || die "uso: scripts/wt-db.sh create|drop|status <issue>"

root="$(cd "$(dirname "$0")/.." && pwd)"
parent="$(dirname "$root")"
api_main="$parent/bookandsign-api"
port=$((4000 + n))
wt="$parent/bookandsign-api-worktrees/issue-$n-port-$port"
db="bookandsign_dev_issue_$n"
container="bookandsign-postgres-dev"

psql_in() { docker exec "$container" psql -U postgres -v ON_ERROR_STOP=1 "$@"; }

# Nunca tocar otra base que no sea la de este worktree.
[[ "$db" == "bookandsign_dev_issue_$n" && "$db" != "bookandsign_dev" ]] || die "nombre de base inesperado"

case "$cmd" in
  drop)
    psql_in -c "DROP DATABASE IF EXISTS \"$db\" WITH (FORCE)"
    ;;

  status)
    for t in users contracts events bookings sessions photos migrations; do
      printf '%s: ' "$t"
      psql_in -d "$db" -tAc "select count(*) from $t"
    done
    ;;

  create)
    [[ -f "$wt/package.json" ]] || die "no existe el worktree $wt"
    node_dir="$HOME/.nvm/versions/node/$(tr -d '[:space:]' < "$wt/.nvmrc")/bin"
    [[ -x "$node_dir/node" ]] || die "falta Node de .nvmrc en $node_dir (nvm install)"
    export PATH="$node_dir:$PATH"

    src_url="$(grep -E '^SEED_SOURCE_DATABASE_URL=' "$api_main/.env.prod" | head -1 | cut -d= -f2- \
      | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" || true)"
    [[ -n "$src_url" ]] || die "falta SEED_SOURCE_DATABASE_URL en $api_main/.env.prod"

    if ! psql_in -tAc "select 1 from pg_database where datname='$db'" | grep -q 1; then
      psql_in -c "CREATE DATABASE \"$db\""
    fi

    redact() { while IFS= read -r line; do printf '%s\n' "${line//"$src_url"/<redacted>}"; done; }

    target_env=(env -u SUPABASE_DB_URL NODE_ENV=local DB_HOST=localhost DB_PORT=5432
      DB_USERNAME=postgres DB_PASSWORD=postgres DB_NAME="$db")

    echo "== migraciones en $db"
    (cd "$wt" && "${target_env[@]}" pnpm run db:run) 2>&1 | redact

    echo "== seed sanitizado en $db"
    local_pw="${SEED_LOCAL_PASSWORD:-brillipoint-local}"
    (cd "$wt" && "${target_env[@]}" \
      SEED_SOURCE_DATABASE_URL="$src_url" SEED_LOCAL_PASSWORD="$local_pw" SEED_CONFIRM_TARGET="$db" \
      pnpm run db:seed:from-production) 2>&1 | redact

    echo
    echo "Listo. Usuario admin para entrar: dev@brillipoint.test / $local_pw"
    echo "(los usuarios copiados de prod tienen email user-<id>@example.test y la misma contraseña)"
    echo "Levantar la API de este worktree:"
    echo "  cd $wt && DB_NAME=$db DB_HOST=localhost DB_PORT=5432 NODE_ENV=local PORT=$port pnpm dev"
    ;;
esac
