#!/usr/bin/env bash
# start-session.sh with a fake `claude` (spec 2026-10-03 §4.3).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../start-session.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# A throwaway ledger and a fake phase worktree holding a prompt with placeholders.
export ETQAN_LEDGER_DIR="$tmp/ledger"
git init -q -b orchestration "$ETQAN_LEDGER_DIR"
python3 "$here/../ledger.py" init >/dev/null
mkdir -p "$tmp/wt/b3/scripts/orchestration"
printf 'phase {{PHASE}} slot {{SLOT}}\n' >"$tmp/wt/b3/scripts/orchestration/PHASE_PROMPT.md"
echo '{"mcpServers": {}}' >"$tmp/wt/b3/.mcp.json"
python3 "$here/../ledger.py" phase B3 --status spec --slot 2 --worktree "$tmp/wt/b3" --branch feat/b3a-x >/dev/null

# A fake claude: records its cwd and argv, prints what `claude --bg` prints.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
{ pwd; printf '%s\n' "$@"; } >"$FAKE_CLAUDE_LOG"
echo "${FAKE_CLAUDE_OUT:-backgrounded · ab12cd34 · $3}"
EOF
chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH" FAKE_CLAUDE_LOG="$tmp/claude.log"
session_of() { python3 "$here/../ledger.py" show --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["conductor_session"] if sys.argv[1]=="conductor" else d["phases"][sys.argv[1]]["session"])' "$1"; }

# A phase: run from its worktree, the prompt filled in, the id recorded and printed.
out="$(bash "$script" B3 --model claude-sonnet-5 --effort high)"
[ "$out" = ab12cd34 ] || fail "printed: $out"
[ "$(sed -n 1p "$tmp/claude.log")" = "$tmp/wt/b3" ] || fail "cwd: $(sed -n 1p "$tmp/claude.log")"
expected=$'--bg\n--name\netqan-B3\n--permission-mode\nauto\n--mcp-config\n'"$tmp/wt/b3/.mcp.json"$'\n--strict-mcp-config\n--model\nclaude-sonnet-5\n--effort\nhigh\nphase B3 slot 2'
[ "$(sed -n '2,$p' "$tmp/claude.log")" = "$expected" ] || fail "argv: $(sed -n '2,$p' "$tmp/claude.log")"
[ "$(session_of B3)" = ab12cd34 ] || fail "ledger session: $(session_of B3)"

# The conductor: from the main checkout, the CONDUCTOR.md prompt, recorded top-level.
FAKE_CLAUDE_OUT="backgrounded · cd56ef78 · etqan-conductor" bash "$script" conductor --mode plan >/dev/null
main="$(cd "$here/../../.." && pwd)"
[ "$(sed -n 1p "$tmp/claude.log")" = "$main" ] || fail "conductor cwd"
grep -qx -- "etqan-conductor" "$tmp/claude.log" || fail "conductor name"
grep -qx -- "plan" "$tmp/claude.log" || fail "conductor mode"
[ "$(session_of conductor)" = cd56ef78 ] || fail "conductor session"
grep -qx -- "--strict-mcp-config" "$tmp/claude.log" || fail "conductor: no --strict-mcp-config"
grep -qx -- "$main/.mcp.json" "$tmp/claude.log" || fail "conductor: not the main checkout's .mcp.json"

# A worktree with no .mcp.json still gets no project MCP servers, so no approval prompt can block it.
rm "$tmp/wt/b3/.mcp.json"
bash "$script" B3 >/dev/null
grep -qx -- "--strict-mcp-config" "$tmp/claude.log" || fail "no --strict-mcp-config without .mcp.json"
if grep -qx -- "--mcp-config" "$tmp/claude.log"; then fail "--mcp-config passed without a .mcp.json"; fi

# Refusals: bad arguments exit 2; no worktree or no id exit 1; nothing recorded.
# shellcheck disable=SC2089
for args in "B3 --mode bypassPermissions" "B12" "B3 --effort huge" "B3 --model 'x y'" "B3 --what"; do
  # shellcheck disable=SC2086,SC2090
  if bash "$script" $args >/dev/null 2>&1; then fail "accepted: $args"; fi
done
bash "$script" B3 --mode bypassPermissions >/dev/null 2>&1 || [ $? -eq 2 ] || fail "bad mode is not exit 2"
if bash "$script" B2 >/dev/null 2>&1; then fail "B2 has no worktree"; fi
if FAKE_CLAUDE_OUT="something else" bash "$script" B3 >/dev/null 2>&1; then fail "no id accepted"; fi
[ "$(session_of B3)" = ab12cd34 ] || fail "a failed start changed the ledger"
echo "start_session_test: ok"
