#!/usr/bin/env bash
# Apunta el front de un worktree al API del worktree activo del mismo issue.
#
#   scripts/wt-front-env.sh <issue>
#
# Busca el worktree de la API en <repo-padre>/bookandsign-api-worktrees/issue-<n>-port-<4000+n>
# y comprueba si algo escucha en ese puerto. Si es así escribe NEXT_PUBLIC_API_URL en el
# .env.local del worktree del front (<repo-padre>/bookandsign-front-worktrees/issue-<n>-port-<5000+n>);
# si no, avisa y usa http://localhost:3000 (la API principal).
# .env.local gana sobre .env en Next, así que .env no se toca ni se lee.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

n="${1:-}"
[[ "$n" =~ ^[0-9]+$ ]] || die "uso: scripts/wt-front-env.sh <issue>"

root="$(cd "$(dirname "$0")/.." && pwd)"
parent="$(dirname "$root")"
api_port=$((4000 + n))
front_port=$((5000 + n))
api_wt="$parent/bookandsign-api-worktrees/issue-$n-port-$api_port"
front_wt="$parent/bookandsign-front-worktrees/issue-$n-port-$front_port"

[[ -d "$front_wt" ]] || die "no existe el worktree del front: $front_wt"

api_url="http://localhost:3000"
if [[ ! -d "$api_wt" ]]; then
  echo "aviso: no hay worktree de la API para el issue $n; uso $api_url" >&2
elif lsof -nP -iTCP:"$api_port" -sTCP:LISTEN >/dev/null 2>&1; then
  api_url="http://localhost:$api_port"
else
  echo "aviso: el worktree de la API existe pero no escucha en $api_port; arráncalo con" >&2
  echo "       (cd $api_wt && PORT=$api_port DB_NAME=bookandsign_dev_issue_$n pnpm dev)" >&2
  echo "       uso $api_url por ahora" >&2
fi

env_file="$front_wt/.env.local"
tmp="$(mktemp)"
[[ -f "$env_file" ]] && grep -v '^NEXT_PUBLIC_API_URL=' "$env_file" > "$tmp" || true
echo "NEXT_PUBLIC_API_URL=$api_url" >> "$tmp"
mv "$tmp" "$env_file"

echo "front issue $n -> API $api_url (front: yarn dev -p $front_port)"
