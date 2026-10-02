#!/usr/bin/env bash
# Write <dir>/.env.stream for one orchestration stream (spec 2026-10-02 §3.3).
# `just` loads it (dotenv), so docker compose gets its own project name and
# ports, and the URLs (Vite/Astro HMR, emailed links, e2e) follow the port.
# DATABASE_URL/CELERY_BROKER_URL point host-side processes (manage.py, e2e)
# at this stream's Postgres and Redis; containers keep their own values.
# If <dir>/backend/.env exists (launch-phase.sh copies the main one), its
# DATABASE_URL and CELERY_BROKER_URL lines are replaced with the stream's.
# Rerun it with another slot to move a stopped stream (CONDUCTOR.md).
# Slot 0 is the main checkout, which has no .env.stream.
set -euo pipefail
usage() { echo "usage: stream-env.sh <phase> <slot 1-4> [dir]" >&2; exit 2; }
[ $# -ge 2 ] && [ $# -le 3 ] || usage
phase="$1"; slot="$2"; dir="${3:-.}"
[[ "$phase" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "phase must be lowercase letters, digits and dashes: $phase" >&2; exit 2; }
[[ "$slot" =~ ^[1-4]$ ]] || { echo "slot must be 1-4: $slot" >&2; exit 2; }
off=$((slot * 100))
http=$((8080 + off))
database_url="postgres://etqan:etqan@localhost:$((5432 + off))/etqan"
broker_url="redis://localhost:$((6379 + off))/0"
cat >"$dir/.env.stream" <<EOF
COMPOSE_PROJECT_NAME=etqan-$phase
ETQAN_HTTP_PORT=$http
ETQAN_API_PORT=$((8000 + off))
ETQAN_PG_PORT=$((5432 + off))
ETQAN_REDIS_PORT=$((6379 + off))
ETQAN_FLOWER_PORT=$((5555 + off))
ETQAN_MAIL_UI_PORT=$((8025 + off))
ETQAN_SMTP_PORT=$((1025 + off))
ETQAN_URL_PORT_SUFFIX=:$http
E2E_APP_URL=http://demo.etqan.localhost:$http
E2E_DEMO_URL=http://demo.etqan.localhost:$http
E2E_OTHER_URL=http://other.etqan.localhost:$http
E2E_BASE_URL=http://etqan.localhost:$http
E2E_MAILPIT_URL=http://localhost:$((8025 + off))
DATABASE_URL=$database_url
CELERY_BROKER_URL=$broker_url
EOF
backend_env="$dir/backend/.env"
if [ -f "$backend_env" ]; then
  kept="$(grep -vE '^(DATABASE_URL|CELERY_BROKER_URL)=' "$backend_env" || true)"
  {
    [ -z "$kept" ] || printf '%s\n' "$kept"
    printf 'DATABASE_URL=%s\nCELERY_BROKER_URL=%s\n' "$database_url" "$broker_url"
  } >"$backend_env"
fi
echo "wrote $dir/.env.stream (slot $slot, http://demo.etqan.localhost:$http/)"
