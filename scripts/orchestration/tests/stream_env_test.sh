#!/usr/bin/env bash
# stream-env.sh writes one stream's ports (spec 2026-10-02 §3.3).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../stream-env.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

bash "$script" b3 1 "$tmp"
env_file="$tmp/.env.stream"
expect() { grep -qx "$1" "$env_file" || fail "missing '$1' in: $(cat "$env_file")"; }
expect "COMPOSE_PROJECT_NAME=etqan-b3"
expect "ETQAN_HTTP_PORT=8180"
expect "ETQAN_API_PORT=8100"
expect "ETQAN_PG_PORT=5532"
expect "ETQAN_REDIS_PORT=6479"
expect "ETQAN_FLOWER_PORT=5655"
expect "ETQAN_MAIL_UI_PORT=8125"
expect "ETQAN_SMTP_PORT=1125"
expect "ETQAN_URL_PORT_SUFFIX=:8180"
expect "E2E_APP_URL=http://demo.etqan.localhost:8180"
expect "E2E_DEMO_URL=http://demo.etqan.localhost:8180"
expect "E2E_OTHER_URL=http://other.etqan.localhost:8180"
# The e2e suite and host-side manage.py reach this stream's stack, never the
# main one on :80/:5432 (final review I1).
expect "E2E_BASE_URL=http://etqan.localhost:8180"
expect "E2E_MAILPIT_URL=http://localhost:8125"
expect "DATABASE_URL=postgres://etqan:etqan@localhost:5532/etqan"
expect "CELERY_BROKER_URL=redis://localhost:6479/0"
[ "$(grep -c . "$env_file")" -eq 16 ] || fail "unexpected lines in: $(cat "$env_file")"

# A backend/.env already in <dir> (launch-phase.sh copies the main one) gets
# the stream's database and broker; every other line is kept as it was.
mkdir -p "$tmp/backend"
printf 'DATABASE_URL=postgres://etqan:etqan@localhost:5432/etqan\nSECRET=1\nCELERY_BROKER_URL=redis://localhost:6379/0\n' >"$tmp/backend/.env"
bash "$script" b3 2 "$tmp"
[ "$(cat "$tmp/backend/.env")" = "$(printf 'SECRET=1\nDATABASE_URL=postgres://etqan:etqan@localhost:5632/etqan\nCELERY_BROKER_URL=redis://localhost:6579/0')" ] \
  || fail "backend/.env not rewritten for slot 2: $(cat "$tmp/backend/.env")"
rm -rf "$tmp/backend"

# No port is shared between any two slots, nor with the main stack (slot 0).
ports() { grep -E '^ETQAN_[A-Z_]+_PORT=' "$1" | cut -d= -f2; }
main_ports="80 8000 5432 6379 5555 8025 1025"
all="$main_ports"
for slot in 1 2 3 4; do
  bash "$script" "s$slot" "$slot" "$tmp"
  all="$all $(ports "$tmp/.env.stream" | tr '\n' ' ')"
done
dupes="$(tr ' ' '\n' <<<"$all" | grep -v '^$' | sort | uniq -d)"
[ -z "$dupes" ] || fail "ports shared between slots: $dupes"

# Bad arguments exit 2 and write nothing.
rm -f "$tmp/.env.stream"
for args in "b3 0" "b3 5" "B3 1" "b3 x" "b3"; do
  # shellcheck disable=SC2086
  if bash "$script" $args "$tmp" 2>/dev/null; then fail "accepted: $args"; fi
  [ ! -e "$tmp/.env.stream" ] || fail "wrote a file for: $args"
done
echo "stream_env_test: ok"
