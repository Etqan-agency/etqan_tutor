#!/usr/bin/env bash
# Start one orchestration session as a Claude Code background session and record
# its id in the ledger — the one way sessions start, used by the conductor and by
# Orchestra (docs/superpowers/specs/2026-10-03-orchestra-dashboard-design.md §4.3).
#   start-session.sh <B2..B11|conductor> [--mode m] [--model x] [--effort e]
set -euo pipefail
usage() { echo "usage: start-session.sh <B2..B11|conductor> [--mode m] [--model x] [--effort e]" >&2; exit 2; }
[ $# -ge 1 ] || usage
who="$1"; shift
mode=auto; model=""; effort=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) [ $# -ge 2 ] || usage; mode="$2"; shift 2 ;;
    --model) [ $# -ge 2 ] || usage; model="$2"; shift 2 ;;
    --effort) [ $# -ge 2 ] || usage; effort="$2"; shift 2 ;;
    *) usage ;;
  esac
done
case "$mode" in auto|acceptEdits|manual|plan|dontAsk) ;; *) echo "mode must be auto, acceptEdits, manual, plan or dontAsk: $mode" >&2; exit 2 ;; esac
[[ -z "$model" || "$model" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || { echo "not a model id: $model" >&2; exit 2; }
case "$effort" in ""|low|medium|high|xhigh|max) ;; *) echo "effort must be low, medium, high, xhigh or max: $effort" >&2; exit 2 ;; esac
[[ "$who" == conductor || "$who" =~ ^B([2-9]|1[01])$ ]] || { echo "who must be B2..B11 or conductor: $who" >&2; exit 2; }

here="$(cd "$(dirname "$0")" && pwd)"
main="$(cd "$(dirname "$(git -C "$here" rev-parse --path-format=absolute --git-common-dir)")" && pwd)"
ledger=(python3 "$here/ledger.py")
if [ "$who" = conductor ]; then
  dir="$main"; name="etqan-conductor"
  prompt="$(cat "$here/CONDUCTOR.md")"
else
  IFS='|' read -r dir slot < <("${ledger[@]}" show --json | python3 -c \
    'import json,sys; p=json.load(sys.stdin)["phases"][sys.argv[1]]; print((p["worktree"] or "") + "|" + str(p["slot"] or ""))' "$who")
  [ -n "$dir" ] && [ -d "$dir" ] || { echo "$who has no worktree; launch it first" >&2; exit 1; }
  [ -n "$slot" ] || { echo "$who holds no slot" >&2; exit 1; }
  name="etqan-$who"
  prompt="$(sed -e "s/{{PHASE}}/$who/g" -e "s/{{SLOT}}/$slot/g" "$dir/scripts/orchestration/PHASE_PROMPT.md")"
fi
args=(--bg --name "$name" --permission-mode "$mode")
# A background session cannot answer Claude Code's "new MCP server found in this
# project" prompt, which blocks it forever. Load exactly the checkout's own
# .mcp.json (codegraph) as explicit config, and nothing else, so no prompt appears.
if [ -f "$dir/.mcp.json" ]; then args+=(--mcp-config "$dir/.mcp.json"); fi
args+=(--strict-mcp-config)
[ -z "$model" ] || args+=(--model "$model")
[ -z "$effort" ] || args+=(--effort "$effort")
out="$(cd "$dir" && claude "${args[@]}" "$prompt")"
id="$(sed -n 's/^backgrounded · \([0-9a-f]\{1,\}\) · .*/\1/p' <<<"$out" | head -n 1)"
[ -n "$id" ] || { echo "could not read the session id from: $out" >&2; exit 1; }
if [ "$who" = conductor ]; then
  "${ledger[@]}" conductor --session "$id" >/dev/null
else
  "${ledger[@]}" phase "$who" --session "$id" >/dev/null
fi
echo "$id"
