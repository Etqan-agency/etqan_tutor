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
