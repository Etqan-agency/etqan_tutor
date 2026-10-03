# Plan 15 — Orchestra, the parallel-phases dashboard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A local web app (`just orchestra` → `http://127.0.0.1:7700`) that shows the whole parallel build and controls it: phases, sessions, slots, merge queue, escalations, coordination, CI and live session output.

**Architecture:** A Python standard-library HTTP server (`orchestra/server/orchestra_server`) imports `scripts/orchestration/ledger.py` for every ledger read and write, runs the orchestration scripts and the `claude`/`gh`/`just` CLIs from fixed argv lists, and pushes `ledger`/`sessions` events over SSE. A React app (`orchestra/web`, the dashboard's stack) renders five screens and sends every change with a per-process token. Sessions are Claude Code background sessions started by one shared script, `scripts/orchestration/start-session.sh`.

**Tech Stack:** Python 3 stdlib (`http.server`, `subprocess`, `threading`, `unittest`), bash, React 19, Vite 8, TanStack Query 5 / Router 1, Tailwind 4 + `@etqan/tokens`, lucide-react, `@xterm/xterm`, vitest + Testing Library, Biome.

**Spec:** `docs/superpowers/specs/2026-10-03-orchestra-dashboard-design.md` (and the orchestration spec it builds on, `docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md`).

**Branch:** meta `feat/orchestra` (holds the spec). Only the meta repo changes.

## Global Constraints

- Server: Python 3 standard library only; binds `127.0.0.1` only, port `ORCHESTRA_PORT` (default 7700).
- Every request: `Host` ∈ {`127.0.0.1:<port>`, `localhost:<port>`}; `Origin`, when present, `http://` + one of those; else 403.
- Every non-GET request: header `X-Orchestra-Token` = the process's random token (embedded in the served `index.html` as `<meta name="orchestra-token">`); else 403.
- Nothing runs through a shell: every subprocess is an argv list from a fixed template; free text is only ledger data or one argv element.
- Permission modes offered: `auto` (default), `acceptEdits`, `manual`, `plan`, `dontAsk` — never `bypassPermissions`.
- Session names: `etqan-<CODE>` (e.g. `etqan-B3`) and `etqan-conductor`.
- Ledger commits made by the server read `ledger (orchestra): <message>`.
- A failed command answers `{"ok": false, "exit_code": n, "output_tail": "<last 50 lines>"}`; a `LedgerError` answers 409 `{"error": "<message>"}`; a bad input 400 `{"error": …}`.
- Web: React 19 / Vite 8 / TanStack Query 5 / TanStack Router 1 / Tailwind 4 / `@etqan/tokens` v0.3.0 / lucide / vitest — the same versions as `dashboard/package.json`; semantic token utilities only (`bg-card`, `text-muted-foreground`, `border-border`, `bg-destructive`, `text-success`, …), no palette colours.
- Web coverage: lines/statements ≥ 80, branches/functions ≥ 70. English UI; laptop width.
- Commit trailer: `Co-Authored-By: <implementing model> <noreply@anthropic.com>`.

## Review Focus

- Two writers at once (the conductor session and a click) — the server must take the ledger lock for the whole read-modify-write, so neither loses the other's change (Task 3, a concurrent-write test).
- A command that hangs or prints megabytes (`just dev-backend` building images, `claude logs` of a long session) — the request must finish with a bounded tail, not exhaust memory (Task 4 caps output; Task 5 caps log text).
- A browser tab on another site POSTing to `127.0.0.1:7700` — refused by Origin/token even though it reaches the port (Task 3 guard tests).
- A session that exited, was removed, or was started by hand under the same name — the page must show the right state and Restart must do the right thing for each (Task 4 reconcile/restart tests).
- The server restarted while sessions keep running — the page shows them again from `claude agents` and the ledger with nothing lost (Task 4 reconcile test from a fresh process state).

---

### Task 1: Ledger additions for the dashboard

**Files:**
- Modify: `scripts/orchestration/ledger.py`
- Test: `scripts/orchestration/tests/test_ledger.py`

**Interfaces:**
- Produces (Python): `CLEAR` (sentinel clearing a field in `set_phase`); `set_phase(..., session=…)`; `set_conductor_session(data, session_id_or_CLEAR)`; `reorder(data, sid, direction)` (`"up"`/`"down"`); `request_done(data, rid)`; `force_release(data, target)`; `save(directory, data, message, *, source=None)` (subject `ledger (<source>): <message>` when given); `load()` backfills `session` on every phase and top-level `conductor_session`.
- Produces (CLI): `phase <code> --session <id|none>`, `--worktree none`, `--branch none`; `conductor --session <id|none>`; `reorder <id> up|down`; `request-done <id>`; `release-claim <target>`.

- [ ] **Step 1: Write the failing tests** — append to `test_ledger.py` (before `if __name__ == "__main__":`):

```python
class OrchestraAdditions(unittest.TestCase):
    def _queued(self, *sids):
        data = L.empty()
        for sid in sids:
            L.add_slice(data, sid, phase="B3", requires=[])
            L.enqueue(data, sid)
        return data

    def test_reorder_moves_a_queued_slice(self):
        data = self._queued("B3a", "B3b", "B3c")
        L.reorder(data, "B3c", "up")
        self.assertEqual(data["queue"], ["B3a", "B3c", "B3b"])
        L.reorder(data, "B3a", "down")
        self.assertEqual(data["queue"], ["B3c", "B3a", "B3b"])

    def test_reorder_refuses_edges_unqueued_and_bad_directions(self):
        data = self._queued("B3a")
        L.add_slice(data, "B3b", phase="B3", requires=[])
        with self.assertRaisesRegex(L.LedgerError, "already first"):
            L.reorder(data, "B3a", "up")
        with self.assertRaisesRegex(L.LedgerError, "already last"):
            L.reorder(data, "B3a", "down")
        with self.assertRaisesRegex(L.LedgerError, "B3b is not queued"):
            L.reorder(data, "B3b", "up")
        with self.assertRaisesRegex(L.LedgerError, "up or down"):
            L.reorder(data, "B3a", "sideways")

    def test_request_done(self):
        data = L.empty()
        rid = L.request(data, "B4", "scheduling", "a field")
        L.request_done(data, rid)
        self.assertEqual(data["requests"][0]["status"], "done")
        with self.assertRaisesRegex(L.LedgerError, "already done"):
            L.request_done(data, rid)
        with self.assertRaisesRegex(L.LedgerError, "unknown request R9"):
            L.request_done(data, "R9")

    def test_force_release_ignores_the_holder(self):
        data = L.empty()
        L.claim(data, "B3", "etqan.catalogue.models", "price")
        L.force_release(data, "etqan.catalogue.models")
        self.assertEqual(data["claims"], [])
        with self.assertRaisesRegex(L.LedgerError, "no claim on x"):
            L.force_release(data, "x")

    def test_clear_empties_a_field_and_the_phase_is_eligible_again(self):
        data = L.empty()
        L.set_phase(data, "B2", status="spec", slot=1, worktree="/w/b2", branch="feat/b2a-x", session="ab12")
        self.assertEqual(data["phases"]["B2"]["session"], "ab12")
        L.set_phase(data, "B2", status="waiting-deps", slot=0, worktree=L.CLEAR, branch=L.CLEAR, session=L.CLEAR)
        phase = data["phases"]["B2"]
        self.assertEqual([phase[k] for k in ("slot", "worktree", "branch", "session")], [None] * 4)
        self.assertIn("B2", L.eligible(data)[1])

    def test_conductor_session(self):
        data = L.empty()
        self.assertIsNone(data["conductor_session"])
        L.set_conductor_session(data, "cd34")
        self.assertEqual(data["conductor_session"], "cd34")
        L.set_conductor_session(data, L.CLEAR)
        self.assertIsNone(data["conductor_session"])

    def test_load_backfills_an_older_ledger(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            old = L.empty()
            del old["conductor_session"]
            for phase in old["phases"].values():
                del phase["session"]
            (directory / "orchestration").mkdir()
            (directory / "orchestration" / "ledger.json").write_text(json.dumps(old))
            data = L.load(directory)
            self.assertIsNone(data["conductor_session"])
            self.assertTrue(all(p["session"] is None for p in data["phases"].values()))

    def test_save_names_its_source_in_the_commit(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            subprocess.run(["git", "init", "-q", "-b", "orchestration", tmp], check=True)
            for key, value in (("user.name", "t"), ("user.email", "t@t")):
                subprocess.run(["git", "-C", tmp, "config", key, value], check=True)
            L.save(directory, L.empty(), "init", source="orchestra")
            subject = subprocess.run(
                ["git", "-C", tmp, "log", "-1", "--format=%s"], capture_output=True, text=True
            ).stdout.strip()
            self.assertEqual(subject, "ledger (orchestra): init")


class OrchestraCli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        subprocess.run(["git", "init", "-q", "-b", "orchestration", str(self.dir)], check=True)
        for key, value in (("user.name", "t"), ("user.email", "t@t")):
            subprocess.run(["git", "-C", str(self.dir), "config", key, value], check=True)
        cli(self.dir, "init")

    def tearDown(self):
        self.tmp.cleanup()

    def _data(self):
        return json.loads((self.dir / "orchestration/ledger.json").read_text())

    def test_phase_session_and_none_clearing(self):
        self.assertEqual(cli(self.dir, "phase", "B2", "--status", "spec", "--slot", "1",
                             "--worktree", "/w", "--branch", "feat/b2a-x", "--session", "ab12").returncode, 0)
        result = cli(self.dir, "phase", "B2", "--status", "waiting-deps", "--slot", "0",
                     "--worktree", "none", "--branch", "none", "--session", "none")
        self.assertEqual(result.returncode, 0, result.stderr)
        phase = self._data()["phases"]["B2"]
        self.assertEqual([phase[k] for k in ("worktree", "branch", "session")], [None] * 3)

    def test_conductor_reorder_request_done_release_claim(self):
        self.assertEqual(cli(self.dir, "conductor", "--session", "cd34").returncode, 0)
        self.assertEqual(self._data()["conductor_session"], "cd34")
        for sid in ("B3a", "B3b"):
            cli(self.dir, "slice", sid, "--phase", "B3")
            cli(self.dir, "queue", sid)
        self.assertEqual(cli(self.dir, "reorder", "B3b", "up").returncode, 0)
        self.assertEqual(self._data()["queue"], ["B3b", "B3a"])
        cli(self.dir, "request", "B4", "scheduling", "a field")
        self.assertEqual(cli(self.dir, "request-done", "R1").returncode, 0)
        cli(self.dir, "claim", "B3", "t", "--reason", "r")
        self.assertEqual(cli(self.dir, "release-claim", "t").returncode, 0)
        self.assertEqual(self._data()["claims"], [])
        self.assertNotEqual(cli(self.dir, "reorder", "B3a", "left").returncode, 0)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `python3 -m unittest discover -s scripts/orchestration/tests -v 2>&1 | tail -15`
Expected: the new tests ERROR/FAIL (`module 'ledger' has no attribute 'reorder'`, `KeyError: 'conductor_session'`, CLI exits 2 for unknown commands); the existing 38 pass.

- [ ] **Step 3: Implement**

In `ledger.py`:

1. After `MAX_BOUNCES = 3` add:

```python
# Passed for a field (CLI: the word `none`) to clear it; plain None means "leave as is".
CLEAR = object()
```

2. In `empty()`, add `"session": None,` after `"current_task": None,` in each phase, and `"conductor_session": None,` after `"escalations": [],`.

3. In `set_phase`, replace the line building `updated` with:

```python
    updated = {
        **phase,
        **{key: (None if value is CLEAR else value) for key, value in fields.items() if value is not None},
    }
```

4. Add after `resolve`:

```python
def set_conductor_session(data: dict, session) -> None:
    data["conductor_session"] = None if session is CLEAR else session


def reorder(data: dict, sid: str, direction: str) -> None:
    """Move a queued slice one place; the in-flight slice is not in the queue."""
    if direction not in ("up", "down"):
        raise LedgerError("direction must be up or down")
    queue = data["queue"]
    if sid not in queue:
        raise LedgerError(f"{sid} is not queued")
    index = queue.index(sid)
    other = index - 1 if direction == "up" else index + 1
    if other < 0:
        raise LedgerError(f"{sid} is already first")
    if other >= len(queue):
        raise LedgerError(f"{sid} is already last")
    queue[index], queue[other] = queue[other], queue[index]


def request_done(data: dict, rid: str) -> None:
    for item in data["requests"]:
        if item["id"] == rid:
            if item["status"] == "done":
                raise LedgerError(f"{rid} is already done")
            item["status"] = "done"
            return
    raise LedgerError(f"unknown request {rid}")


def force_release(data: dict, target: str) -> None:
    """The conductor's (or the owner's) release, whoever holds the claim."""
    for held in data["claims"]:
        if held["target"] == target:
            data["claims"].remove(held)
            return
    raise LedgerError(f"no claim on {target}")
```

5. In `load`, replace the final `return json.loads(...)` with:

```python
    data = json.loads(path.read_text(encoding="utf-8"))
    # Ledgers written before the dashboard (Plan 15) lack the session fields.
    data.setdefault("conductor_session", None)
    for phase in data["phases"].values():
        phase.setdefault("session", None)
    return data
```

6. `save` gains a keyword: change the signature to `def save(directory: Path, data: dict, message: str, *, source: str | None = None) -> None:` and the commit message to `subject = f"ledger ({source}): {message}" if source else f"ledger: {message}"` used in place of `f"ledger: {message}"`.

7. `render`: add a `Session` column to the Phases table (header `"Session"` after `"Spec"`, cell `p.get("session")`), and append `· Conductor: {data.get('conductor_session') or '—'}` to the "In flight" line.

8. `parser()`: in the `phase` subparser loop add `"session"` to `("status", "worktree", "branch", "spec", "slice", "task")`; then add:

```python
    co = sub.add_parser("conductor")
    co.add_argument("--session", required=True)
    ro = sub.add_parser("reorder")
    ro.add_argument("id")
    ro.add_argument("direction", choices=("up", "down"))
    sub.add_parser("request-done").add_argument("id")
    sub.add_parser("release-claim").add_argument("target")
```

9. `run()`: add a helper above it `def _field(value): return CLEAR if value == "none" else value`; in the `phase` branch pass `worktree=_field(args.worktree), branch=_field(args.branch), session=_field(args.session)`; and add branches before `save(...)`:

```python
        elif c == "conductor":
            set_conductor_session(data, _field(args.session))
            message = "conductor session"
        elif c == "reorder":
            reorder(data, args.id, args.direction)
            message = f"reorder {args.id} {args.direction}"
        elif c == "request-done":
            request_done(data, args.id)
            message = f"request {args.id} done"
        elif c == "release-claim":
            force_release(data, args.target)
            message = f"release {args.target} (forced)"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s scripts/orchestration/tests -v 2>&1 | tail -4`
Expected: `OK` (38 existing + 10 new = 48). Also `bash scripts/orchestration/tests/launch_phase_test.sh` → `launch_phase_test: ok`.

- [ ] **Step 5: Commit**

```bash
git add scripts/orchestration/ledger.py scripts/orchestration/tests/test_ledger.py
git commit -m "feat(orchestration): ledger sessions, reorder, request-done, forced release, clearing fields

Co-Authored-By: <implementing model> <noreply@anthropic.com>"
```

---

### Task 2: One way to start a session — `start-session.sh`

**Files:**
- Create: `scripts/orchestration/start-session.sh`
- Create: `scripts/orchestration/tests/start_session_test.sh`
- Modify: `scripts/orchestration/CONDUCTOR.md` (step 1), `.github/workflows/ci.yml` (`infra-scripts` job)

**Interfaces:**
- Consumes: Task 1's `ledger.py phase <CODE> --session <id>` and `ledger.py conductor --session <id>`; `ledger.py show --json`.
- Produces: `bash scripts/orchestration/start-session.sh <B2…B11|conductor> [--mode m] [--model x] [--effort e]` → runs `claude --bg --name etqan-<CODE> --permission-mode <mode> [--model x] [--effort e] "<prompt>"` from the phase worktree (main checkout for the conductor), prints the session id, records it in the ledger. Exit 2 on bad arguments; exit 1 when the phase has no worktree/slot or the id can't be read (nothing recorded).

- [ ] **Step 1: Write the failing test** — `scripts/orchestration/tests/start_session_test.sh`:

```bash
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
expected=$'--bg\n--name\netqan-B3\n--permission-mode\nauto\n--model\nclaude-sonnet-5\n--effort\nhigh\nphase B3 slot 2'
[ "$(sed -n '2,$p' "$tmp/claude.log")" = "$expected" ] || fail "argv: $(sed -n '2,$p' "$tmp/claude.log")"
[ "$(session_of B3)" = ab12cd34 ] || fail "ledger session: $(session_of B3)"

# The conductor: from the main checkout, the CONDUCTOR.md prompt, recorded top-level.
FAKE_CLAUDE_OUT="backgrounded · cd56ef78 · etqan-conductor" bash "$script" conductor --mode plan >/dev/null
main="$(cd "$here/../../.." && pwd)"
[ "$(sed -n 1p "$tmp/claude.log")" = "$main" ] || fail "conductor cwd"
grep -qx -- "etqan-conductor" "$tmp/claude.log" || fail "conductor name"
grep -qx -- "plan" "$tmp/claude.log" || fail "conductor mode"
[ "$(session_of conductor)" = cd56ef78 ] || fail "conductor session"

# Refusals: bad arguments exit 2; no worktree or no id exit 1; nothing recorded.
for args in "B3 --mode bypassPermissions" "B12" "B3 --effort huge" "B3 --model 'x y'" "B3 --what"; do
  # shellcheck disable=SC2086
  if bash "$script" $args >/dev/null 2>&1; then fail "accepted: $args"; fi
done
bash "$script" B3 --mode bypassPermissions >/dev/null 2>&1 || [ $? -eq 2 ] || fail "bad mode is not exit 2"
if bash "$script" B2 >/dev/null 2>&1; then fail "B2 has no worktree"; fi
if FAKE_CLAUDE_OUT="something else" bash "$script" B3 >/dev/null 2>&1; then fail "no id accepted"; fi
[ "$(session_of B3)" = ab12cd34 ] || fail "a failed start changed the ledger"
echo "start_session_test: ok"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/orchestration/tests/start_session_test.sh`
Expected: FAIL — `start-session.sh: No such file or directory` (non-zero exit).

- [ ] **Step 3: Write `start-session.sh`** (and `chmod +x`):

```bash
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
```

- [ ] **Step 4: Run the test to verify it passes; shellcheck**

Run: `bash scripts/orchestration/tests/start_session_test.sh`
Expected: `start_session_test: ok`
Run: `docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.11.0 scripts/orchestration/start-session.sh scripts/orchestration/tests/start_session_test.sh`
Expected: no output.

- [ ] **Step 5: The conductor starts sessions itself; CI runs the test**

`scripts/orchestration/CONDUCTOR.md` step 1: replace the clause `and tell the owner the printed command to start the session in a new terminal.` with `then start its session with \`bash scripts/orchestration/start-session.sh <CODE>\` (it records the session id; never hand the owner commands to paste).` Add at the end of the file:

```markdown
The owner may act through Orchestra (`just orchestra`) at the same time; it uses the same ledger
and scripts. A ledger refusal caused by such a clash (for example "B3a is in flight") is normal:
re-read the ledger and carry on.
```

Also replace the remaining sentence in step 1 `and tell it to \`just dev-backend\`` with `and start its stack with \`just dev-backend\` in its worktree`.

`.github/workflows/ci.yml`, `infra-scripts` job, the `orchestration scripts` step: add `bash scripts/orchestration/tests/start_session_test.sh` after the `launch_phase_test.sh` line.

- [ ] **Step 6: Commit**

```bash
git add scripts/orchestration/start-session.sh scripts/orchestration/tests/start_session_test.sh scripts/orchestration/CONDUCTOR.md .github/workflows/ci.yml
git commit -m "feat(orchestration): start-session.sh, the one way to start a session

Co-Authored-By: <implementing model> <noreply@anthropic.com>"
```

---
### Task 3: Server core — guards, static page, ledger routes

**Files:**
- Create: `orchestra/server/ruff.toml`, `orchestra/server/orchestra_server/__init__.py` (empty docstring module), `__main__.py`, `config.py`, `errors.py`, `routing.py`, `ledger_api.py`, `validate.py`, `app.py`, `routes_ledger.py`
- Create: `orchestra/server/tests/__init__.py` (empty), `orchestra/server/tests/fakes.py`, `orchestra/server/tests/support.py`, `orchestra/server/tests/test_app.py`, `orchestra/server/tests/test_ledger_routes.py`

**Interfaces:**
- Consumes: Task 1's ledger API (`L.CLEAR`, `L.reorder`, `L.request_done`, `L.force_release`, `L.save(..., source=)`).
- Produces: `config.MAIN`, `config.SCRIPTS`, `config.scripts()`, `config.web_dist()`, `config.wt_root()`, `config.repo()`, `config.port()`, `config.poll_seconds()`; `errors.HttpError(status, payload)`, `BadRequest`, `Forbidden`, `NotFound`; `routing.route(method, pattern)` decorator, `routing.Request` (`.params`, `.query`, `.body`, `.handler`), `routing.STREAMED`; `ledger_api.L`, `ledger_api.read()`, `ledger_api.write(message, change)`; `validate.*`; `app.make_server(port, token) -> OrchestraServer` (`.token`, `.server_port`), `app.main()`; `routes_ledger.build_state(data) -> dict` (Task 4 extends it). Tests: `tests.support.ServerCase` (`request(method, path, body=None, headers=None, token=True) -> (status, data)`, `ledger()`, `last_subject()`, `self.base`).

- [ ] **Step 1: Write the test support and the failing tests**

`orchestra/server/tests/support.py`:

```python
"""A real server on a free port against a throwaway ledger repo (spec 2026-10-03 §6)."""

import http.client
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

SERVER_ROOT = Path(__file__).resolve().parents[1]
if str(SERVER_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVER_ROOT))

from orchestra_server import app, ledger_api  # noqa: E402
from tests import fakes  # noqa: E402


class ServerCase(unittest.TestCase):
    token = "test-token"
    extra_env: dict = {}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.ledger_dir = self.base / "ledger"
        subprocess.run(["git", "init", "-q", "-b", "orchestration", str(self.ledger_dir)], check=True)
        for key, value in (("user.name", "t"), ("user.email", "t@t")):
            subprocess.run(["git", "-C", str(self.ledger_dir), "config", key, value], check=True)
        (self.base / "dist").mkdir()
        # Fakes always: no test ever reaches the real claude, docker, gh or scripts.
        self.agents_file = self.base / "agents.json"
        self.agents_file.write_text("[]")
        env = {
            **fakes.install(self.base),
            "FAKE_AGENTS": str(self.agents_file),
            "ETQAN_LEDGER_DIR": str(self.ledger_dir),
            "ETQAN_WT_ROOT": str(self.base / "wt"),
            "ORCHESTRA_WEB_DIST": str(self.base / "dist"),
            "ORCHESTRA_POLL": "0.1",
            **self.extra_env,
        }
        self.env_values = env
        self.env = mock.patch.dict(os.environ, env)
        self.env.start()
        ledger_api.L.save(self.ledger_dir, ledger_api.L.empty(), "init")
        self.server = app.make_server(0, self.token)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_port

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.env.stop()
        self.tmp.cleanup()

    def request(self, method, path, body=None, *, headers=None, token=True):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=20)
        sent = {"Host": f"127.0.0.1:{self.port}"}
        if token and method != "GET":
            sent["X-Orchestra-Token"] = self.token
        payload = None
        if body is not None:
            sent["Content-Type"] = "application/json"
            payload = body if isinstance(body, (bytes, str)) else json.dumps(body)
        sent.update(headers or {})
        conn.request(method, path, body=payload, headers=sent)
        response = conn.getresponse()
        raw = response.read()
        conn.close()
        try:
            data = json.loads(raw)
        except ValueError:
            data = raw.decode(errors="replace")
        return response.status, data

    def ledger(self):
        return ledger_api.read()

    def change_ledger(self, change):
        return ledger_api.write("test setup", change)

    def last_subject(self):
        return subprocess.run(
            ["git", "-C", str(self.ledger_dir), "log", "-1", "--format=%s"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
```

`orchestra/server/tests/fakes.py`:

```python
"""Fake claude/just/docker and fake orchestration scripts on PATH. Each records
{"cmd", "cwd", "argv"} as one JSON line in $FAKE_LOG and answers from env:
FAKE_FAIL=<cmd> (exit 3, 'boom' + 200 lines), FAKE_AGENTS (a file of JSON),
FAKE_ID (the id claude --bg / start-session print), FAKE_LOGS (a file of log text),
FAKE_DOCKER (lines `docker ps` prints)."""

import json
import os
import stat
from pathlib import Path

FAKE = r'''#!/usr/bin/env python3
import json, os, sys
name, args = os.path.basename(sys.argv[0]), sys.argv[1:]
if name == "bash":  # the scripts are run as `bash <script> args…`: recorded as the script
    name, args = os.path.basename(args[0]), args[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write(json.dumps({"cmd": name, "cwd": os.getcwd(), "argv": sys.argv[1:]}) + "\n")
if os.environ.get("FAKE_FAIL") == name:
    print("\n".join(f"line {n}" for n in range(200)))
    print("boom", file=sys.stderr)
    sys.exit(3)
if name == "claude" and args[:1] == ["agents"]:
    path = os.environ.get("FAKE_AGENTS")
    print(open(path).read() if path and os.path.exists(path) else "[]")
elif name == "claude" and args[:1] == ["logs"]:
    path = os.environ.get("FAKE_LOGS")
    print(open(path).read() if path else "")
elif name == "claude" and "--bg" in args:
    print(f"backgrounded · {os.environ.get('FAKE_ID', 'ab12cd34')} · {args[args.index('--name') + 1]}")
elif name == "start-session.sh":
    print(os.environ.get("FAKE_ID", "ab12cd34"))
elif name == "docker":
    print(os.environ.get("FAKE_DOCKER", ""))
'''


def install(base: Path) -> dict:
    """Create the fakes under `base`; return the env to apply."""
    bin_dir = base / "bin"
    scripts = base / "scripts"
    bin_dir.mkdir()
    scripts.mkdir()
    for directory, names in ((bin_dir, ("claude", "just", "docker", "gh", "bash")),
                             (scripts, ("launch-phase.sh", "teardown-phase.sh", "stream-env.sh", "start-session.sh"))):
        for name in names:
            path = directory / name
            path.write_text(FAKE)
            path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return {
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        "ORCHESTRA_SCRIPTS": str(scripts),
        "FAKE_LOG": str(base / "fake.log"),
    }


def calls(base: Path) -> list[dict]:
    log = base / "fake.log"
    if not log.exists():
        return []
    return [json.loads(line) for line in log.read_text().splitlines()]
```

The fake `bash` receives `bash <script> args…` (the server runs scripts as `["bash", path, …]`), records the call under the script's name with `argv` = `[path, args…]`, and answers as that script.

`orchestra/server/tests/test_app.py`:

```python
"""Guards and the static page (spec 2026-10-03 §4.1)."""

import os
from unittest import mock

from tests.support import ServerCase


class Guards(ServerCase):
    def test_a_foreign_host_is_refused(self):
        status, data = self.request("GET", "/api/state", headers={"Host": f"evil.example:{self.port}"})
        self.assertEqual((status, data), (403, {"error": "bad host"}))

    def test_localhost_is_allowed(self):
        status, _ = self.request("GET", "/api/state", headers={"Host": f"localhost:{self.port}"})
        self.assertEqual(status, 200)

    def test_a_foreign_origin_is_refused_even_for_reads(self):
        status, data = self.request("GET", "/api/state", headers={"Origin": "http://evil.example"})
        self.assertEqual((status, data), (403, {"error": "bad origin"}))
        status, _ = self.request("GET", "/api/state", headers={"Origin": f"http://127.0.0.1:{self.port}"})
        self.assertEqual(status, 200)

    def test_writes_need_the_token(self):
        body = {"status": "paused"}
        self.assertEqual(self.request("POST", "/api/phases/B2/status", body, token=False)[0], 403)
        status, data = self.request("POST", "/api/phases/B2/status", body,
                                    headers={"X-Orchestra-Token": "wrong"}, token=False)
        self.assertEqual((status, data), (403, {"error": "bad token"}))
        self.assertEqual(self.request("POST", "/api/phases/B2/status", body)[0], 200)

    def test_unknown_routes_and_bad_bodies(self):
        self.assertEqual(self.request("GET", "/api/nothing")[0], 404)
        self.assertEqual(self.request("POST", "/api/phases/B2/status", b"not json")[0], 400)
        self.assertEqual(self.request("POST", "/api/phases/B2/status", [1, 2])[0], 400)

    def test_the_dev_token_route_exists_only_in_dev(self):
        self.assertEqual(self.request("GET", "/api/token")[0], 404)
        with mock.patch.dict(os.environ, {"ORCHESTRA_DEV": "1"}):
            self.assertEqual(self.request("GET", "/api/token"), (200, {"token": self.token}))


class StaticPage(ServerCase):
    def test_index_carries_the_token_and_serves_every_page_path(self):
        (self.base / "dist" / "index.html").write_text("<html><head><title>O</title></head><body></body></html>")
        for path in ("/", "/phase/B3", "/queue"):
            status, body = self.request("GET", path)
            self.assertEqual(status, 200)
            self.assertIn(f'<meta name="orchestra-token" content="{self.token}"></head>', body)

    def test_assets_are_served_and_traversal_falls_back_to_index(self):
        (self.base / "dist" / "index.html").write_text("<html><head></head></html>")
        (self.base / "dist" / "assets").mkdir()
        (self.base / "dist" / "assets" / "app.js").write_text("console.log(1)")
        self.assertEqual(self.request("GET", "/assets/app.js"), (200, "console.log(1)"))
        status, body = self.request("GET", "/../../../etc/passwd")
        self.assertEqual(status, 200)
        self.assertIn("orchestra-token", body)

    def test_an_unbuilt_web_app_says_so(self):
        status, body = self.request("GET", "/")
        self.assertEqual(status, 503)
        self.assertIn("just orchestra", body)
```

`orchestra/server/tests/test_ledger_routes.py`:

```python
"""Ledger-only routes (spec 2026-10-03 §4.2)."""

import threading

from orchestra_server.ledger_api import L
from tests.support import ServerCase


class State(ServerCase):
    def test_state_has_the_ledger_and_the_eligible_phases(self):
        status, data = self.request("GET", "/api/state")
        self.assertEqual(status, 200)
        self.assertEqual(data["eligible"], {"free": 4, "phases": ["B2", "B3", "B8", "B9"]})
        self.assertIn("B11", data["ledger"]["phases"])


class PhaseStatus(ServerCase):
    def test_status_is_written_and_attributed(self):
        self.assertEqual(self.request("POST", "/api/phases/B2/status", {"status": "paused"}), (200, {"ok": True}))
        self.assertEqual(self.ledger()["phases"]["B2"]["status"], "paused")
        self.assertEqual(self.last_subject(), "ledger (orchestra): phase B2 status paused")

    def test_bad_inputs(self):
        self.assertEqual(self.request("POST", "/api/phases/B99/status", {"status": "paused"})[0], 400)
        self.assertEqual(self.request("POST", "/api/phases/B2/status", {"status": "done"})[0], 400)
        self.assertEqual(self.request("POST", "/api/phases/B2/status", {})[0], 400)


class Queue(ServerCase):
    def setUp(self):
        super().setUp()

        def seed(d):
            for sid in ("B3a", "B3b"):
                L.add_slice(d, sid, phase="B3", requires=[])
                L.enqueue(d, sid)

        self.change_ledger(seed)

    def test_next_reorder_bounce_merged(self):
        self.assertEqual(self.request("POST", "/api/queue/reorder", {"slice": "B3b", "direction": "up"})[0], 200)
        self.assertEqual(self.ledger()["queue"], ["B3b", "B3a"])
        self.assertEqual(self.request("POST", "/api/queue/next"), (200, {"ok": True, "in_flight": "B3b"}))
        status, data = self.request("POST", "/api/queue/next")
        self.assertEqual((status, data), (409, {"error": "B3b is in flight"}))
        self.assertEqual(self.request("POST", "/api/queue/bounce", {"slice": "B3b", "reason": ""})[0], 400)
        self.assertEqual(self.request("POST", "/api/queue/bounce", {"slice": "B3b", "reason": "CI red"})[0], 200)
        self.request("POST", "/api/queue/next")
        bad = {"slice": "B3a", "heads": {"backend": "not-a-sha"}}
        self.assertEqual(self.request("POST", "/api/queue/merged", bad)[0], 400)
        good = {"slice": "B3a", "heads": {"backend": "abc1234", "meta": "def5678"}}
        self.assertEqual(self.request("POST", "/api/queue/merged", good)[0], 200)
        self.assertEqual(self.ledger()["slices"]["B3a"]["status"], "merged")
        self.assertEqual(self.ledger()["main_heads"], {"backend": "abc1234", "meta": "def5678"})


class Coordination(ServerCase):
    def test_resolve_decide_release_done(self):
        def seed(d):
            L.escalate(d, "B3", "money", "live keys?")
            L.claim(d, "B3", "etqan.catalogue.models", "price")
            L.request(d, "B4", "scheduling", "a field")

        self.change_ledger(seed)
        self.assertEqual(self.request("POST", "/api/escalations/E1/resolve", {"answer": "test keys"})[0], 200)
        self.assertEqual(self.ledger()["escalations"][0]["answer"], "test keys")
        self.assertEqual(self.request("POST", "/api/escalations/E1/resolve", {"answer": "  "})[0], 400)
        decision = {"phase": "B3", "text": "wallet on Student", "affects": ["B4"], "source": "audit §2"}
        self.assertEqual(self.request("POST", "/api/decisions", decision), (200, {"ok": True, "id": "D1"}))
        self.assertEqual(self.request("POST", "/api/decisions", {**decision, "affects": ["B99"]})[0], 400)
        self.assertEqual(self.request("POST", "/api/claims/release", {"target": "etqan.catalogue.models"})[0], 200)
        self.assertEqual(self.ledger()["claims"], [])
        self.assertEqual(self.request("POST", "/api/requests/R1/done")[0], 200)
        self.assertEqual(self.request("POST", "/api/requests/R1/done")[0], 409)

    def test_concurrent_writes_lose_nothing(self):
        decision = {"phase": "B3", "text": "x", "affects": [], "source": "s"}
        threads = [threading.Thread(target=self.request, args=("POST", "/api/decisions", decision)) for _ in range(10)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        ids = [d["id"] for d in self.ledger()["shared_decisions"]]
        self.assertEqual(sorted(ids, key=lambda i: int(i[1:])), [f"D{n}" for n in range(1, 11)])
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd orchestra/server && python3 -m unittest discover -s tests -t . -v 2>&1 | tail -5`
Expected: ERROR — `ModuleNotFoundError: No module named 'orchestra_server'`.

- [ ] **Step 3: Write the server core**

`orchestra/server/ruff.toml` (the backend's Ruff rules are Django/pytest ones — e.g. they forbid unittest asserts — so the server has its own):

```toml
# Orchestra's server: Python 3 standard library and unittest (not the backend's
# Django/pytest rules).
line-length = 120
target-version = "py312"

[lint]
select = ["E", "F", "W", "I", "B", "UP", "SIM", "BLE", "S"]
ignore = [
    "S603",  # subprocess with argv lists is the design (spec §4.1): never a shell
    "S607",  # programs are found on PATH on purpose (claude, gh, just, docker, git)
    "S101",  # tests
    "S108",  # tests use temp dirs
]
```

`orchestra/server/orchestra_server/__init__.py`:

```python
"""Orchestra: the local dashboard for the parallel phases (spec 2026-10-03)."""
```

`__main__.py`:

```python
from .app import main

main()
```

`config.py`:

```python
"""Where things are (spec 2026-10-03 §3). Functions, so tests can point them elsewhere."""

import os
from pathlib import Path

MAIN = Path(__file__).resolve().parents[3]  # the meta checkout
SCRIPTS = MAIN / "scripts" / "orchestration"  # ledger.py is imported from here, always


def scripts() -> Path:
    """The scripts the server runs (tests substitute fakes)."""
    return Path(os.environ.get("ORCHESTRA_SCRIPTS", SCRIPTS))


def web_dist() -> Path:
    return Path(os.environ.get("ORCHESTRA_WEB_DIST", MAIN / "orchestra" / "web" / "dist"))


def wt_root() -> Path:
    return Path(os.environ.get("ETQAN_WT_ROOT", MAIN.parent / "etqan_tutor-wt"))


def repo() -> str:
    return os.environ.get("ORCHESTRA_REPO", "Etqan-agency/etqan_tutor")


def port() -> int:
    return int(os.environ.get("ORCHESTRA_PORT", "7700"))


def poll_seconds() -> float:
    return float(os.environ.get("ORCHESTRA_POLL", "2"))


def dev() -> bool:
    return os.environ.get("ORCHESTRA_DEV") == "1"
```

`errors.py`:

```python
"""Errors a route raises; the app turns them into JSON responses."""


class HttpError(Exception):
    def __init__(self, status: int, payload: dict):
        super().__init__(payload.get("error", status))
        self.status = status
        self.payload = payload


class BadRequest(HttpError):
    def __init__(self, message: str):
        super().__init__(400, {"error": message})


class Forbidden(HttpError):
    def __init__(self, message: str):
        super().__init__(403, {"error": message})


class NotFound(HttpError):
    def __init__(self, message: str = "no such route"):
        super().__init__(404, {"error": message})
```

`routing.py`:

```python
"""The route table: modules register handlers with @route on import."""

import re
from collections.abc import Callable

ROUTES: list[tuple[str, re.Pattern, Callable]] = []
STREAMED = object()  # a handler that wrote its own response returns this


def route(method: str, pattern: str):
    def register(handler: Callable) -> Callable:
        ROUTES.append((method, re.compile(f"^{pattern}$"), handler))
        return handler

    return register


class Request:
    def __init__(self, handler, params: dict, query: dict, body: dict):
        self.handler = handler
        self.params = params
        self.query = query
        self.body = body
```

`ledger_api.py`:

```python
"""Every ledger read and write goes through scripts/orchestration/ledger.py itself,
under its lock, so the dashboard and the sessions follow one set of rules."""

import sys
from collections.abc import Callable
from typing import Any

from . import config

if str(config.SCRIPTS) not in sys.path:
    sys.path.insert(0, str(config.SCRIPTS))

import ledger as L  # noqa: E402

LedgerError = L.LedgerError
SOURCE = "orchestra"


def read() -> dict:
    directory = L.default_dir()
    with L.locked(directory, write=False):
        return L.load(directory)


def write(message: str, change: Callable[[dict], Any]) -> Any:
    """Load, change and commit under one exclusive lock: no lost updates."""
    directory = L.default_dir()
    with L.locked(directory, write=True):
        data = L.load(directory)
        result = change(data)
        L.save(directory, data, message, source=SOURCE)
        return result
```

`validate.py`:

```python
"""Every input is checked before anything runs (spec 2026-10-03 §4.1)."""

import re

from .errors import BadRequest
from .ledger_api import L

MODES = ("auto", "acceptEdits", "manual", "plan", "dontAsk")
EFFORTS = ("low", "medium", "high", "xhigh", "max")
_SLICE = re.compile(r"^B\d+[a-z]+$")
_SUFFIX = re.compile(r"^[a-z0-9][a-z0-9-]*$")
_MODEL = re.compile(r"^[a-z0-9][a-z0-9.-]*$")
_SHA = re.compile(r"^[0-9a-f]{7,40}$")
_REPO = re.compile(r"^[a-z0-9_-]+$")
MAX_TEXT = 4000


def phase(code) -> str:
    if code not in L.PHASES:
        raise BadRequest(f"unknown phase {code}")
    return code


def who(value) -> str:
    return "conductor" if value == "conductor" else phase(value)


def slot(value, *, allow_zero: bool = False) -> int:
    low = 0 if allow_zero else 1
    if not isinstance(value, int) or isinstance(value, bool) or not low <= value <= L.SLOTS:
        raise BadRequest(f"slot must be {low}-{L.SLOTS}")
    return value


def slice_id(value) -> str:
    if not isinstance(value, str) or not _SLICE.match(value):
        raise BadRequest(f"not a slice id: {value}")
    return value


def suffix(value) -> str:
    if not isinstance(value, str) or not _SUFFIX.match(value) or len(value) > 60:
        raise BadRequest(f"not a branch suffix: {value}")
    return value


def mode(value) -> str:
    value = value or "auto"
    if value not in MODES:
        raise BadRequest(f"mode must be one of {', '.join(MODES)}")
    return value


def model(value) -> str | None:
    if value in (None, ""):
        return None
    if not isinstance(value, str) or not _MODEL.match(value):
        raise BadRequest(f"not a model id: {value}")
    return value


def effort(value) -> str | None:
    if value in (None, ""):
        return None
    if value not in EFFORTS:
        raise BadRequest(f"effort must be one of {', '.join(EFFORTS)}")
    return value


def status(value) -> str:
    if value not in L.STATUSES:
        raise BadRequest(f"status must be one of {', '.join(L.STATUSES)}")
    return value


def text(value, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise BadRequest(f"{name} is required")
    if len(value) > MAX_TEXT:
        raise BadRequest(f"{name} is longer than {MAX_TEXT} characters")
    return value.strip()


def direction(value) -> str:
    if value not in ("up", "down"):
        raise BadRequest("direction must be up or down")
    return value


def heads(value) -> dict[str, str]:
    if not isinstance(value, dict) or not value:
        raise BadRequest("heads must map repo to commit")
    for repo, sha in value.items():
        if not isinstance(repo, str) or not _REPO.match(repo) or not isinstance(sha, str) or not _SHA.match(sha):
            raise BadRequest(f"bad head {repo}={sha}")
    return value


def phases(value) -> list[str]:
    if not isinstance(value, list):
        raise BadRequest("affects must be a list of phases")
    return [phase(code) for code in value]
```

`app.py`:

```python
"""The HTTP server: guards, routing, JSON and the built web page (spec 2026-10-03 §4)."""

import json
import mimetypes
import secrets
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

from . import config
from .errors import BadRequest, Forbidden, HttpError, NotFound
from .ledger_api import LedgerError
from .routing import ROUTES, STREAMED, Request, route

MAX_BODY = 1_000_000


@route("GET", "/api/token")
def dev_token(req):
    """Only for `just orchestra-dev`, where Vite (not the server) serves index.html."""
    if not config.dev():
        raise NotFound()
    return {"token": req.handler.server.token}


class Handler(BaseHTTPRequestHandler):
    server_version = "Orchestra"

    def log_message(self, format, *args):  # noqa: A002 — quiet; the page shows errors
        pass

    def do_GET(self):  # noqa: N802
        self._dispatch("GET")

    def do_POST(self):  # noqa: N802
        self._dispatch("POST")

    def _guard(self, method: str) -> None:
        port = self.server.server_port
        hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
        if self.headers.get("Host") not in hosts:
            raise Forbidden("bad host")
        origin = self.headers.get("Origin")
        if origin is not None and origin not in {f"http://{host}" for host in hosts}:
            raise Forbidden("bad origin")
        sent = self.headers.get("X-Orchestra-Token", "")
        if method != "GET" and not secrets.compare_digest(sent, self.server.token):
            raise Forbidden("bad token")

    def _dispatch(self, method: str) -> None:
        url = urlsplit(self.path)
        try:
            self._guard(method)
            if not url.path.startswith("/api/"):
                if method != "GET":
                    raise NotFound()
                self._static(url.path)
                return
            for wanted, pattern, handler in ROUTES:
                match = pattern.match(url.path)
                if match and wanted == method:
                    body = self._body() if method == "POST" else {}
                    result = handler(Request(self, match.groupdict(), parse_qs(url.query), body))
                    if result is not STREAMED:
                        self._json(200, result)
                    return
            raise NotFound()
        except HttpError as error:
            self._json(error.status, error.payload)
        except LedgerError as error:
            self._json(409, {"error": str(error)})
        except Exception as error:  # noqa: BLE001 — shown on the page, never swallowed
            self._json(500, {"error": f"{type(error).__name__}: {error}"})

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            raise BadRequest("body too large")
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            raise BadRequest("body is not JSON") from None
        if not isinstance(body, dict):
            raise BadRequest("body must be a JSON object")
        return body

    def _send(self, status: int, content_type: str, data: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, status: int, payload) -> None:
        self._send(status, "application/json", json.dumps(payload).encode())

    def _static(self, path: str) -> None:
        root = config.web_dist().resolve()
        index = root / "index.html"
        target = (root / path.lstrip("/")).resolve()
        if not target.is_relative_to(root) or not target.is_file():
            target = index
        if not target.is_file():
            self._send(503, "text/plain; charset=utf-8",
                       b"The web app is not built: start Orchestra with `just orchestra`.")
            return
        data = target.read_bytes()
        content_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        if target == index:
            meta = f'<meta name="orchestra-token" content="{self.server.token}">'.encode()
            data = data.replace(b"</head>", meta + b"</head>", 1)
            content_type = "text/html; charset=utf-8"
        self._send(200, content_type, data)


class OrchestraServer(ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False  # open SSE streams must not hold a shutdown

    def __init__(self, port: int, token: str):
        super().__init__(("127.0.0.1", port), Handler)
        self.token = token


def make_server(port: int, token: str) -> OrchestraServer:
    from . import routes_ledger  # noqa: F401 — registers its routes

    return OrchestraServer(port, token)


def main() -> None:
    server = make_server(config.port(), secrets.token_urlsafe(32))
    print(f"Orchestra: http://127.0.0.1:{server.server_port}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
```

`routes_ledger.py`:

```python
"""Routes that only read or write the ledger (spec 2026-10-03 §4.2)."""

from . import validate as v
from .ledger_api import L, read, write
from .routing import route

OK = {"ok": True}


def build_state(data: dict) -> dict:
    free, codes = L.eligible(data)
    return {"ledger": data, "eligible": {"free": free, "phases": codes}}


@route("GET", "/api/state")
def state(req):
    return build_state(read())


@route("POST", r"/api/phases/(?P<code>B\d+)/status")
def phase_status(req):
    code = v.phase(req.params["code"])
    status = v.status(req.body.get("status"))
    write(f"phase {code} status {status}", lambda d: L.set_phase(d, code, status=status))
    return OK


@route("POST", "/api/queue/next")
def queue_next(req):
    return {"ok": True, "in_flight": write("queue next", L.take_next)}


@route("POST", "/api/queue/bounce")
def queue_bounce(req):
    sid = v.slice_id(req.body.get("slice"))
    reason = v.text(req.body.get("reason"), "reason")
    write(f"bounce {sid}", lambda d: L.bounce(d, sid, reason))
    return OK


@route("POST", "/api/queue/merged")
def queue_merged(req):
    sid = v.slice_id(req.body.get("slice"))
    heads = v.heads(req.body.get("heads"))
    write(f"merged {sid}", lambda d: L.mark_merged(d, sid, heads))
    return OK


@route("POST", "/api/queue/reorder")
def queue_reorder(req):
    sid = v.slice_id(req.body.get("slice"))
    direction = v.direction(req.body.get("direction"))
    write(f"reorder {sid} {direction}", lambda d: L.reorder(d, sid, direction))
    return OK


@route("POST", r"/api/escalations/(?P<id>E\d+)/resolve")
def resolve(req):
    eid = req.params["id"]
    answer = v.text(req.body.get("answer"), "answer")
    write(f"resolve {eid}", lambda d: L.resolve(d, eid, answer))
    return OK


@route("POST", "/api/decisions")
def decide(req):
    body = req.body
    phase = v.phase(body.get("phase"))
    text = v.text(body.get("text"), "text")
    affects = v.phases(body.get("affects", []))
    source = v.text(body.get("source"), "source")
    return {"ok": True, "id": write("decision", lambda d: L.decide(d, phase, text, affects, source))}


@route("POST", "/api/claims/release")
def release_claim(req):
    target = v.text(req.body.get("target"), "target")
    write(f"release {target} (forced)", lambda d: L.force_release(d, target))
    return OK


@route("POST", r"/api/requests/(?P<id>R\d+)/done")
def request_done(req):
    rid = req.params["id"]
    write(f"request {rid} done", lambda d: L.request_done(d, rid))
    return OK
```

- [ ] **Step 4: Run the tests to verify they pass; lint**

Run: `cd orchestra/server && python3 -m unittest discover -s tests -t . -v 2>&1 | tail -4`
Expected: `OK`, every test passing.
Run (from the meta root; Ruff picks up `orchestra/server/ruff.toml`): `backend/.venv/bin/ruff check --fix orchestra/server && backend/.venv/bin/ruff format orchestra/server && backend/.venv/bin/ruff check orchestra/server`
Expected: clean. Fix what `--fix` leaves by hand without changing behaviour (e.g. `contextlib.suppress` for a `try/except/pass`, `# noqa: S105` on the test token, wrapping a long line), then re-run the tests.

- [ ] **Step 5: Commit**

```bash
git add orchestra/server
git commit -m "feat(orchestra): the server core — guards, page, ledger routes

Co-Authored-By: <implementing model> <noreply@anthropic.com>"
```

---

### Task 4: Server — sessions, stacks and phase commands

**Files:**
- Create: `orchestra/server/orchestra_server/commands.py`, `sessions.py`, `phases.py`, `routes_actions.py`
- Modify: `orchestra/server/orchestra_server/app.py` (`make_server` imports `routes_actions`), `routes_ledger.py` (`build_state` adds sessions and stacks)
- Create: `orchestra/server/tests/test_sessions.py`, `orchestra/server/tests/test_actions.py`

**Interfaces:**
- Consumes: Task 3's `routing.route`, `ledger_api.read/write/L`, `validate`, `errors`; Task 2's `start-session.sh` (argv `<who> --mode m [--model x] [--effort e]`, prints the id last).
- Produces: `commands.run(argv, *, cwd=None, timeout=1800, ok_codes=(0,)) -> str`, `commands.script(name, *args) -> list[str]`, `commands.tail(text, lines=50)`, `commands.CommandFailed(argv, exit_code, tail)` (an `HttpError` 500 with `{"ok": False, "exit_code", "output_tail"}`); `sessions.agents() -> list[dict]`, `sessions.reconcile(data, agents) -> (view, adopt)`, `sessions.snapshot() -> dict[who, {"id","state",…}]` (states `busy|idle|exited|gone|none`), `sessions.start(who, mode, model=None, effort=None) -> str`, `sessions.stop(who)`, `sessions.restart(who, mode) -> str`, `sessions.log(who) -> str`, `sessions.stacks(data) -> dict[code, bool]`; `phases.launch/move_slot/stack/teardown`. `build_state` now returns `{"ledger", "eligible", "sessions", "stacks"}`.

- [ ] **Step 1: Write the fakes and the failing tests**

`orchestra/server/tests/test_sessions.py`:

```python
"""Reconciling the ledger with `claude agents` (spec 2026-10-03 §4.3)."""

import json
import unittest

from orchestra_server import sessions
from orchestra_server.ledger_api import L
from tests.support import ServerCase


def agent(id_, name, *, state="running", status="idle", pid=True):
    a = {"id": id_, "name": name, "kind": "background", "state": state, "status": status,
         "sessionId": f"{id_}-uuid", "cwd": "/w"}
    if pid:
        a["pid"] = 1
    return a


class Reconcile(unittest.TestCase):
    def setUp(self):
        self.data = L.empty()

    def test_states(self):
        L.set_phase(self.data, "B2", session="aa")
        L.set_phase(self.data, "B3", session="bb")
        L.set_phase(self.data, "B8", session="cc")
        L.set_phase(self.data, "B9", session="dd")  # recorded, not listed at all
        items = [agent("aa", "etqan-B2", status="busy"), agent("bb", "etqan-B3"),
                 agent("cc", "etqan-B8", state="done", pid=False)]
        view, adopt = sessions.reconcile(self.data, items)
        self.assertEqual([view[c]["state"] for c in ("B2", "B3", "B8", "B9", "B4")],
                         ["busy", "idle", "exited", "gone", "none"])
        self.assertEqual(adopt, {})

    def test_a_running_named_session_without_an_id_is_adopted(self):
        items = [agent("ee", "etqan-B6"), agent("ff", "etqan-conductor"),
                 agent("gg", "etqan-B5", state="done", pid=False)]
        view, adopt = sessions.reconcile(self.data, items)
        self.assertEqual(adopt, {"B6": "ee", "conductor": "ff"})
        self.assertEqual(view["B6"]["state"], "idle")
        self.assertEqual(view["B5"]["state"], "none")


class Snapshot(ServerCase):
    def test_state_shows_sessions_and_adopts(self):
        self.agents_file.write_text(json.dumps([agent("ee", "etqan-B6")]))
        status, data = self.request("GET", "/api/state")
        self.assertEqual(status, 200)
        self.assertEqual(data["sessions"]["B6"]["state"], "idle")
        self.assertEqual(self.ledger()["phases"]["B6"]["session"], "ee")

    def test_a_fresh_server_shows_the_same_sessions(self):
        self.change_ledger(lambda d: L.set_phase(d, "B2", session="aa"))
        self.agents_file.write_text(json.dumps([agent("aa", "etqan-B2", status="busy")]))
        first = self.request("GET", "/api/state")[1]["sessions"]
        self.server.shutdown()
        self.server.server_close()
        from orchestra_server import app
        import threading
        self.server = app.make_server(0, self.token)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.port = self.server.server_port
        self.assertEqual(self.request("GET", "/api/state")[1]["sessions"], first)
```

`orchestra/server/tests/test_actions.py`:

```python
"""Commands behind the phase, session and stack routes (spec 2026-10-03 §4.2)."""

import json
import os
from pathlib import Path

from orchestra_server.ledger_api import L
from tests import fakes
from tests.support import ServerCase


class ActionCase(ServerCase):
    def calls(self, cmd=None):
        return [c for c in fakes.calls(self.base) if cmd is None or c["cmd"] == cmd]

    def launched(self, code="B3", slot=2):
        wt = str(self.base / "wt" / code.lower())
        Path(wt).mkdir(parents=True, exist_ok=True)
        self.change_ledger(lambda d: L.set_phase(d, code, status="build", slot=slot, worktree=wt,
                                                 branch=f"feat/{code.lower()}a-x"))
        return wt


class Launch(ActionCase):
    def test_launch_runs_the_script_records_and_starts_the_session(self):
        status, data = self.request("POST", "/api/phases/B3/launch", {"suffix": "b3a-money", "slot": 2})
        self.assertEqual(status, 200, data)
        self.assertEqual(data["session"], "ab12cd34")
        launch = self.calls("launch-phase.sh")[0]
        self.assertEqual(launch["argv"][1:], ["B3", "b3a-money", "2"])
        phase = self.ledger()["phases"]["B3"]
        self.assertEqual((phase["status"], phase["slot"], phase["branch"]), ("spec", 2, "feat/b3a-money"))
        self.assertEqual(phase["worktree"], str(self.base / "wt" / "b3"))
        self.assertEqual(self.calls("start-session.sh")[0]["argv"][1:], ["B3", "--mode", "auto"])

    def test_launch_refusals(self):
        self.assertEqual(self.request("POST", "/api/phases/B6/launch", {"suffix": "b6a-x", "slot": 1})[0], 409)
        self.assertEqual(self.request("POST", "/api/phases/B3/launch", {"suffix": "B3 x", "slot": 1})[0], 400)
        self.assertEqual(self.request("POST", "/api/phases/B3/launch", {"suffix": "b3a-x", "slot": 5})[0], 400)
        self.launched("B2", slot=1)
        status, data = self.request("POST", "/api/phases/B3/launch", {"suffix": "b3a-x", "slot": 1})
        self.assertEqual((status, data), (409, {"error": "slot 1 is held by B2"}))
        self.assertEqual(self.calls("launch-phase.sh"), [])

    def test_a_failing_script_reports_its_tail_and_changes_nothing(self):
        os.environ["FAKE_FAIL"] = "launch-phase.sh"
        status, data = self.request("POST", "/api/phases/B3/launch", {"suffix": "b3a-x", "slot": 2})
        self.assertEqual(status, 500)
        self.assertEqual((data["ok"], data["exit_code"]), (False, 3))
        self.assertEqual(len(data["output_tail"].splitlines()), 50)
        self.assertTrue(data["output_tail"].endswith("boom"))
        self.assertIsNone(self.ledger()["phases"]["B3"]["worktree"])


class Sessions(ActionCase):
    def test_start_validates_and_passes_options(self):
        self.launched()
        self.assertEqual(self.request("POST", "/api/phases/B3/session/start", {"mode": "bypassPermissions"})[0], 400)
        self.assertEqual(self.request("POST", "/api/phases/B3/session/start", {"model": "x y"})[0], 400)
        body = {"mode": "plan", "model": "claude-sonnet-5", "effort": "high"}
        self.assertEqual(self.request("POST", "/api/phases/B3/session/start", body), (200, {"ok": True, "id": "ab12cd34"}))
        self.assertEqual(self.calls("start-session.sh")[0]["argv"][1:],
                         ["B3", "--mode", "plan", "--model", "claude-sonnet-5", "--effort", "high"])

    def test_stop_needs_a_session(self):
        self.assertEqual(self.request("POST", "/api/phases/B3/session/stop")[0], 400)
        self.change_ledger(lambda d: L.set_phase(d, "B3", session="aa"))
        self.assertEqual(self.request("POST", "/api/phases/B3/session/stop")[0], 200)
        self.assertEqual(self.calls("claude")[-1]["argv"], ["stop", "aa"])

    def test_restart_respawns_resumes_or_starts(self):
        self.launched()
        self.change_ledger(lambda d: L.set_phase(d, "B3", session="aa"))
        self.agents_file.write_text(json.dumps([{"id": "aa", "name": "etqan-B3", "kind": "background",
                                                 "pid": 1, "state": "running", "status": "idle"}]))
        self.assertEqual(self.request("POST", "/api/phases/B3/session/restart")[1], {"ok": True, "id": "aa"})
        self.assertEqual(self.calls("claude")[-1]["argv"], ["respawn", "aa"])

        self.agents_file.write_text(json.dumps([{"id": "aa", "name": "etqan-B3", "kind": "background",
                                                 "state": "done", "sessionId": "aa-uuid", "cwd": str(self.base)}]))
        os.environ["FAKE_ID"] = "bb"
        self.assertEqual(self.request("POST", "/api/phases/B3/session/restart")[1], {"ok": True, "id": "bb"})
        resume = self.calls("claude")[-1]
        self.assertEqual(resume["argv"][:3], ["--bg", "--resume", "aa-uuid"])
        self.assertIn("etqan-B3", resume["argv"])
        self.assertEqual(resume["cwd"], str(self.base))
        self.assertEqual(self.ledger()["phases"]["B3"]["session"], "bb")

        self.agents_file.write_text("[]")
        self.request("POST", "/api/phases/B3/session/restart")
        self.assertEqual(self.calls()[-1]["cmd"], "start-session.sh")

    def test_conductor_sessions(self):
        self.assertEqual(self.request("POST", "/api/conductor/session/start", {"mode": "auto"})[0], 200)
        self.assertEqual(self.calls("start-session.sh")[0]["argv"][1:], ["conductor", "--mode", "auto"])

    def test_logs_are_capped(self):
        logs = self.base / "logs.txt"
        logs.write_text("x" * 300_000)
        os.environ["FAKE_LOGS"] = str(logs)
        self.change_ledger(lambda d: L.set_phase(d, "B3", session="aa"))
        status, data = self.request("GET", "/api/phases/B3/log")
        self.assertEqual(status, 200)
        self.assertEqual(len(data["text"]), 200_000)
        self.assertEqual(self.request("GET", "/api/phases/B2/log"), (200, {"text": ""}))


class Slots(ActionCase):
    def test_moving_to_a_free_slot(self):
        wt = self.launched("B3", slot=2)
        self.assertEqual(self.request("POST", "/api/phases/B3/slot", {"slot": 4})[0], 200)
        sequence = [(c["cmd"], c["argv"]) for c in self.calls() if c["cmd"] != "claude"]
        self.assertEqual(sequence, [
            ("just", ["stop"]),
            ("stream-env.sh", [sequence[1][1][0], "b3", "4", wt]),
            ("just", ["dev-backend"]),
        ])
        self.assertTrue(all(c["cwd"] == wt for c in self.calls("just")))
        self.assertEqual(self.ledger()["phases"]["B3"]["slot"], 4)

    def test_a_held_slot_is_refused_before_anything_runs(self):
        self.launched("B2", slot=1)
        self.launched("B3", slot=2)
        self.assertEqual(self.request("POST", "/api/phases/B3/slot", {"slot": 1}),
                         (409, {"error": "slot 1 is held by B2"}))
        self.assertEqual(self.calls("just"), [])

    def test_releasing(self):
        self.launched("B3", slot=2)
        self.assertEqual(self.request("POST", "/api/phases/B3/slot", {"slot": 0})[0], 200)
        phase = self.ledger()["phases"]["B3"]
        self.assertEqual((phase["slot"], phase["status"]), (None, "paused"))

    def test_stack_up_and_down(self):
        wt = self.launched()
        self.request("POST", "/api/phases/B3/stack", {"up": True})
        self.request("POST", "/api/phases/B3/stack", {"up": False})
        self.assertEqual([(c["argv"], c["cwd"]) for c in self.calls("just")], [(["dev-backend"], wt), (["stop"], wt)])
        self.assertEqual(self.request("POST", "/api/phases/B2/stack", {"up": True})[0], 400)

    def test_stacks_in_state(self):
        self.launched("B3")
        os.environ["FAKE_DOCKER"] = "etqan-b3\netqan_tutor"
        self.assertEqual(self.request("GET", "/api/state")[1]["stacks"], {"B3": True})


class Teardown(ActionCase):
    def test_confirm_must_match(self):
        self.launched()
        self.assertEqual(self.request("POST", "/api/phases/B3/teardown", {"confirm": "B2"})[0], 400)
        self.assertEqual(self.calls(), [])

    def test_an_unfinished_phase_returns_to_waiting(self):
        self.launched()
        self.change_ledger(lambda d: (L.set_phase(d, "B3", session="aa"),
                                      L.add_slice(d, "B3a", phase="B3", requires=[])))
        os.environ["FAKE_FAIL"] = "claude"  # its session is already gone: ignored
        self.assertEqual(self.request("POST", "/api/phases/B3/teardown", {"confirm": "B3"})[0], 200)
        self.assertEqual(self.calls("teardown-phase.sh")[0]["argv"][1:], ["B3"])
        phase = self.ledger()["phases"]["B3"]
        self.assertEqual([phase[k] for k in ("status", "slot", "worktree", "branch", "session")],
                         ["waiting-deps", None, None, None, None])
        self.assertIn("B3", self.request("GET", "/api/state")[1]["eligible"]["phases"])

    def test_a_finished_phase_is_merged(self):
        self.launched()

        def finish(d):
            L.add_slice(d, "B3a", phase="B3", requires=[])
            L.enqueue(d, "B3a")
            L.take_next(d)
            L.mark_merged(d, "B3a", {})

        self.change_ledger(finish)
        self.request("POST", "/api/phases/B3/teardown", {"confirm": "B3"})
        self.assertEqual(self.ledger()["phases"]["B3"]["status"], "merged")
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd orchestra/server && python3 -m unittest discover -s tests -t . 2>&1 | tail -5`
Expected: errors — `cannot import name 'sessions'`, and the new routes answer 404.

- [ ] **Step 3: Implement**

`commands.py`:

```python
"""Every subprocess the server runs: an argv list from a fixed template, never a
shell (spec 2026-10-03 §4.1); a failure carries its last 50 lines to the page."""

import subprocess
from pathlib import Path

from . import config
from .errors import HttpError

TAIL_LINES = 50
MAX_OUTPUT = 2_000_000  # characters kept from a command's output


class CommandFailed(HttpError):
    def __init__(self, argv: list[str], exit_code: int, output_tail: str):
        super().__init__(500, {"ok": False, "exit_code": exit_code, "output_tail": output_tail})
        self.argv = argv


def _text(value) -> str:
    if value is None:
        return ""
    return value.decode(errors="replace") if isinstance(value, bytes) else value


def tail(text: str, lines: int = TAIL_LINES) -> str:
    return "\n".join(text[-MAX_OUTPUT:].splitlines()[-lines:])


def run(argv: list[str], *, cwd: Path | str | None = None, timeout: float = 1800,
        ok_codes: tuple[int, ...] = (0,)) -> str:
    try:
        proc = subprocess.run(argv, cwd=cwd, capture_output=True, text=True,
                              errors="replace", timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        output = _text(error.stdout) + _text(error.stderr)
        raise CommandFailed(argv, -1, tail(f"{output}\n(timed out after {timeout:.0f}s)")) from None
    except FileNotFoundError:
        raise CommandFailed(argv, 127, f"{argv[0]}: not found") from None
    output = (proc.stdout or "")[-MAX_OUTPUT:] + (proc.stderr or "")[-MAX_OUTPUT:]
    if proc.returncode not in ok_codes:
        raise CommandFailed(argv, proc.returncode, tail(output))
    return output


def script(name: str, *args: str) -> list[str]:
    return ["bash", str(config.scripts() / name), *args]
```

`sessions.py`:

```python
"""Claude Code background sessions (spec 2026-10-03 §4.3): reconcile the ledger with
`claude agents --json --all`, start through start-session.sh, stop, restart, logs."""

import json
import re
from pathlib import Path

from . import commands, config
from .errors import BadRequest
from .ledger_api import L, read, write

ID = re.compile(r"backgrounded · ([0-9a-f]+) · ")
ENDED = ("done", "stopped", "exited", "failed", "killed")
LOG_CHARS = 200_000


def name_of(who: str) -> str:
    return "etqan-conductor" if who == "conductor" else f"etqan-{who}"


def recorded(data: dict, who: str) -> str | None:
    return data.get("conductor_session") if who == "conductor" else data["phases"][who].get("session")


def agents() -> list[dict]:
    try:
        output = commands.run(["claude", "agents", "--json", "--all"], timeout=30)
        items = json.loads(output)
    except (commands.CommandFailed, ValueError):
        return []
    return [a for a in items if isinstance(a, dict) and a.get("kind") == "background" and a.get("id")]


def _state(agent: dict) -> str:
    if agent.get("state") in ENDED or "pid" not in agent:
        return "exited"
    return "busy" if agent.get("status") == "busy" else "idle"


def reconcile(data: dict, items: list[dict]) -> tuple[dict, dict]:
    """Each session's view, and running `etqan-<who>` sessions the ledger has no id for."""
    by_id = {a["id"]: a for a in items}
    live_by_name = {a.get("name"): a for a in items if _state(a) != "exited"}
    view, adopt = {}, {}
    for who in [*data["phases"], "conductor"]:
        sid = recorded(data, who)
        agent = by_id.get(sid) if sid else None
        if agent is None and not sid and name_of(who) in live_by_name:
            agent = live_by_name[name_of(who)]
            adopt[who] = agent["id"]
        if agent is None:
            view[who] = {"id": sid, "state": "gone" if sid else "none"}
        else:
            view[who] = {"id": agent["id"], "session_id": agent.get("sessionId"),
                         "state": _state(agent), "cwd": agent.get("cwd")}
    return view, adopt


def record(who: str, session) -> None:
    def change(data):
        if who == "conductor":
            L.set_conductor_session(data, session)
        else:
            L.set_phase(data, who, session=session)

    shown = "cleared" if session is L.CLEAR else session
    write(f"session {who} {shown}", change)


def snapshot() -> dict:
    view, adopt = reconcile(read(), agents())
    for who, sid in adopt.items():
        record(who, sid)
    return view


def start(who: str, mode: str, model: str | None = None, effort: str | None = None) -> str:
    argv = commands.script("start-session.sh", who, "--mode", mode)
    if model:
        argv += ["--model", model]
    if effort:
        argv += ["--effort", effort]
    output = commands.run(argv, cwd=config.MAIN, timeout=120)
    return output.strip().splitlines()[-1]


def stop(who: str) -> None:
    sid = recorded(read(), who)
    if not sid:
        raise BadRequest(f"{who} has no session")
    commands.run(["claude", "stop", sid], timeout=60)


def restart(who: str, mode: str) -> str:
    sid = recorded(read(), who)
    agent = next((a for a in agents() if a["id"] == sid), None) if sid else None
    if agent and _state(agent) != "exited":
        commands.run(["claude", "respawn", sid], timeout=120)
        return sid
    if agent and agent.get("sessionId") and agent.get("cwd"):
        argv = ["claude", "--bg", "--resume", agent["sessionId"], "--name", name_of(who), "--permission-mode", mode]
        output = commands.run(argv, cwd=Path(agent["cwd"]), timeout=120)
        match = ID.search(output)
        if not match:
            raise commands.CommandFailed(argv, 0, commands.tail(output))
        record(who, match.group(1))
        return match.group(1)
    return start(who, mode)


def log(who: str) -> str:
    sid = recorded(read(), who)
    if not sid:
        return ""
    try:
        return commands.run(["claude", "logs", sid], timeout=30)[-LOG_CHARS:]
    except commands.CommandFailed as error:
        return error.payload["output_tail"]


def stacks(data: dict) -> dict[str, bool]:
    """Which launched phases have containers up (their compose project etqan-<code>)."""
    launched = [code for code, p in data["phases"].items() if p["worktree"]]
    if not launched:
        return {}
    try:
        output = commands.run(["docker", "ps", "--format", '{{.Label "com.docker.compose.project"}}'], timeout=30)
    except commands.CommandFailed:
        return {}
    projects = set(output.split())
    return {code: f"etqan-{code.lower()}" in projects for code in launched}
```

`phases.py`:

```python
"""The commands behind a phase's launch, slot, stack and teardown (spec 2026-10-03 §4.2)."""

from pathlib import Path

from . import commands, config, sessions
from .errors import BadRequest
from .ledger_api import L, LedgerError, read, write


def _worktree(data: dict, code: str) -> str:
    worktree = data["phases"][code]["worktree"]
    if not worktree:
        raise BadRequest(f"{code} has no worktree")
    return worktree


def _slot_holder(data: dict, code: str, slot: int) -> str | None:
    for other, phase in data["phases"].items():
        if other != code and phase["slot"] == slot and phase["status"] != "merged":
            return other
    return None


def launch(code: str, suffix: str, slot: int, mode: str) -> dict:
    data = read()
    if code not in L.eligible(data)[1]:
        raise LedgerError(f"{code} is not eligible to launch")
    holder = _slot_holder(data, code, slot)
    if holder:
        raise LedgerError(f"slot {slot} is held by {holder}")
    commands.run(commands.script("launch-phase.sh", code, suffix, str(slot)), cwd=config.MAIN, timeout=900)
    worktree = str(config.wt_root() / code.lower())
    write(f"launch {code}", lambda d: L.set_phase(d, code, status="spec", slot=slot,
                                                   worktree=worktree, branch=f"feat/{suffix}"))
    return {"ok": True, "worktree": worktree, "session": sessions.start(code, mode)}


def move_slot(code: str, slot: int) -> dict:
    data = read()
    worktree = _worktree(data, code)
    if slot == 0:
        commands.run(["just", "stop"], cwd=worktree)
        write(f"phase {code} releases its slot", lambda d: L.set_phase(d, code, slot=0, status="paused"))
        return {"ok": True}
    holder = _slot_holder(data, code, slot)
    if holder:
        raise LedgerError(f"slot {slot} is held by {holder}")
    commands.run(["just", "stop"], cwd=worktree)
    write(f"phase {code} to slot {slot}", lambda d: L.set_phase(d, code, slot=slot))
    commands.run(commands.script("stream-env.sh", code.lower(), str(slot), worktree))
    commands.run(["just", "dev-backend"], cwd=worktree)
    return {"ok": True}


def stack(code: str, up: bool) -> dict:
    worktree = _worktree(read(), code)
    commands.run(["just", "dev-backend"] if up else ["just", "stop"], cwd=worktree)
    return {"ok": True}


def teardown(code: str, confirm) -> dict:
    if confirm != code:
        raise BadRequest(f"type {code} to confirm")
    data = read()
    _worktree(data, code)
    sid = data["phases"][code]["session"]
    if sid:
        try:
            commands.run(["claude", "stop", sid], timeout=60)
        except commands.CommandFailed:
            pass  # already stopped or removed
    commands.run(commands.script("teardown-phase.sh", code), cwd=config.MAIN, timeout=900)
    slices = [s for s in data["slices"].values() if s["phase"] == code]
    finished = bool(slices) and all(s["status"] == "merged" for s in slices)

    def change(d):
        if finished:
            L.set_phase(d, code, status="merged", worktree=L.CLEAR, session=L.CLEAR)
        else:
            L.set_phase(d, code, status="waiting-deps", slot=0, worktree=L.CLEAR,
                        branch=L.CLEAR, session=L.CLEAR)

    write(f"teardown {code}", change)
    return {"ok": True, "status": "merged" if finished else "waiting-deps"}
```

`routes_actions.py`:

```python
"""Routes that run commands (spec 2026-10-03 §4.2)."""

from . import phases, sessions
from . import validate as v
from .routing import route

PHASE = r"/api/phases/(?P<code>B\d+)"


@route("POST", PHASE + "/launch")
def launch(req):
    code = v.phase(req.params["code"])
    return phases.launch(code, v.suffix(req.body.get("suffix")), v.slot(req.body.get("slot")),
                         v.mode(req.body.get("mode")))


@route("POST", r"/api/(?:phases/(?P<code>B\d+)|(?P<conductor>conductor))/session/(?P<action>start|stop|restart)")
def session(req):
    who = "conductor" if req.params.get("conductor") else v.phase(req.params["code"])
    action = req.params["action"]
    if action == "stop":
        sessions.stop(who)
        return {"ok": True}
    mode = v.mode(req.body.get("mode"))
    if action == "restart":
        return {"ok": True, "id": sessions.restart(who, mode)}
    return {"ok": True, "id": sessions.start(who, mode, v.model(req.body.get("model")),
                                             v.effort(req.body.get("effort")))}


@route("GET", r"/api/(?:phases/(?P<code>B\d+)|(?P<conductor>conductor))/log")
def log(req):
    who = "conductor" if req.params.get("conductor") else v.phase(req.params["code"])
    return {"text": sessions.log(who)}


@route("POST", PHASE + "/slot")
def slot(req):
    return phases.move_slot(v.phase(req.params["code"]), v.slot(req.body.get("slot"), allow_zero=True))


@route("POST", PHASE + "/stack")
def stack(req):
    up = req.body.get("up")
    if not isinstance(up, bool):
        from .errors import BadRequest

        raise BadRequest("up must be true or false")
    return phases.stack(v.phase(req.params["code"]), up)


@route("POST", PHASE + "/teardown")
def teardown(req):
    return phases.teardown(v.phase(req.params["code"]), req.body.get("confirm"))
```

(Move the `BadRequest` import to the module top; it is inline above only to keep the snippet short — Ruff will flag it.)

`routes_ledger.py`: `build_state` becomes

```python
def build_state(data: dict) -> dict:
    from . import sessions

    free, codes = L.eligible(data)
    view = sessions.snapshot()
    return {"ledger": read(), "eligible": {"free": free, "phases": codes},
            "sessions": view, "stacks": sessions.stacks(data)}
```

(`read()` again because `snapshot()` may have adopted a session; import `sessions` at module top — there is no import cycle.)

`app.py`, `make_server`: `from . import routes_actions, routes_ledger  # noqa: F401`.

- [ ] **Step 4: Run all server tests; lint**

Run: `cd orchestra/server && python3 -m unittest discover -s tests -t . -v 2>&1 | tail -4`
Expected: `OK` — Task 3's tests and the new ones all pass.
Run: the Ruff commands from Task 3 Step 4 → clean; re-run the tests after any fix.

- [ ] **Step 5: Commit**

```bash
git add orchestra/server
git commit -m "feat(orchestra): sessions, slots, stacks, launch and teardown

Co-Authored-By: <implementing model> <noreply@anthropic.com>"
```

---

### Task 5: Server — live events and CI

**Files:**
- Create: `orchestra/server/orchestra_server/events.py`, `ci.py`, `routes_live.py`
- Modify: `orchestra/server/orchestra_server/app.py` (`make_server` imports `routes_live`)
- Create: `orchestra/server/tests/test_live.py`

**Interfaces:**
- Consumes: `sessions.agents()`, `commands.run(..., ok_codes=)`, `ledger_api.L.default_dir()`, `config.poll_seconds()`, `config.repo()`.
- Produces: `GET /api/events` (SSE: `event: ledger`, `event: sessions`, `: ping` every 15 s); `GET /api/ci` → `{"master": {...}|{"error"}|null, "prs": [{"slice","repo","number","url","checks"}]}`, cached 60 s; `events.HUB`.

- [ ] **Step 1: Write the failing tests** — `orchestra/server/tests/test_live.py`:

```python
"""Server-sent events and CI (spec 2026-10-03 §4.2)."""

import http.client
import json
import os
import threading
import time

from orchestra_server import ci
from orchestra_server.ledger_api import L
from tests import fakes
from tests.support import ServerCase


class LiveCase(ServerCase):
    def setUp(self):
        super().setUp()
        ci.clear_cache()

    def wait_for(self, event, trigger, timeout=10):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=timeout)
        conn.request("GET", "/api/events", headers={"Host": f"127.0.0.1:{self.port}"})
        response = conn.getresponse()
        self.assertEqual(response.getheader("Content-Type"), "text/event-stream")
        self.assertEqual(response.fp.readline(), b": connected\n")
        threading.Timer(0.5, trigger).start()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            line = response.fp.readline().decode()
            if line == f"event: {event}\n":
                conn.close()
                return True
        conn.close()
        return False


class Events(LiveCase):
    def test_a_ledger_commit_is_pushed(self):
        self.assertTrue(self.wait_for("ledger", lambda: self.change_ledger(
            lambda d: L.set_phase(d, "B2", status="paused"))))

    def test_a_session_change_is_pushed(self):
        agent = [{"id": "aa", "name": "etqan-B2", "kind": "background", "pid": 1, "state": "running"}]
        self.assertTrue(self.wait_for("sessions", lambda: self.agents_file.write_text(json.dumps(agent))))


class Ci(LiveCase):
    def write_gh(self, run_list, checks, checks_exit=0):
        gh = self.base / "bin" / "gh"
        gh.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "open(os.environ['FAKE_LOG'], 'a').write(json.dumps({'cmd': 'gh', 'cwd': os.getcwd(), 'argv': sys.argv[1:]}) + '\\n')\n"
            f"if sys.argv[1:3] == ['run', 'list']: print({json.dumps(json.dumps(run_list))})\n"
            f"else:\n    print({json.dumps(json.dumps(checks))}); sys.exit({checks_exit})\n"
        )

    def test_master_and_pr_checks_with_pending_exit_8(self):
        run = [{"status": "completed", "conclusion": "success", "headSha": "abc", "url": "u", "createdAt": "t"}]
        checks = [{"name": "e2e", "state": "PENDING", "bucket": "pending", "link": "l"}]
        self.write_gh(run, checks, checks_exit=8)
        self.change_ledger(lambda d: (L.add_slice(d, "B3a", phase="B3", requires=[]),
                                      L.set_slice(d, "B3a", prs="https://github.com/Etqan-agency/etqan_tutor/pull/9")))
        status, data = self.request("GET", "/api/ci")
        self.assertEqual(status, 200)
        self.assertEqual(data["master"]["conclusion"], "success")
        self.assertEqual(data["prs"], [{"slice": "B3a", "repo": "Etqan-agency/etqan_tutor", "number": 9,
                                        "url": "https://github.com/Etqan-agency/etqan_tutor/pull/9", "checks": checks}])
        before = len(fakes.calls(self.base))
        self.request("GET", "/api/ci")
        self.assertEqual(len(fakes.calls(self.base)), before)  # cached

    def test_gh_failing_is_reported_not_a_500(self):
        os.environ["FAKE_FAIL"] = "gh"
        status, data = self.request("GET", "/api/ci")
        self.assertEqual(status, 200)
        self.assertIn("error", data["master"])
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd orchestra/server && python3 -m unittest tests.test_live -v 2>&1 | tail -5`
Expected: ERROR — `cannot import name 'ci'`.

- [ ] **Step 3: Implement**

`events.py`:

```python
"""Server-sent events: one poller notices ledger commits and session changes and
tells every open page (spec 2026-10-03 §4.2)."""

import hashlib
import json
import queue
import subprocess
import threading
import time

from . import config, sessions
from .ledger_api import L

SESSIONS_EVERY = 2.5  # × the poll interval (2 s → 5 s)


def _ledger_head() -> str:
    proc = subprocess.run(["git", "-C", str(L.default_dir()), "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=False)
    return proc.stdout.strip()


def _sessions_digest() -> str:
    return hashlib.sha256(json.dumps(sessions.agents(), sort_keys=True).encode()).hexdigest()


class Hub:
    def __init__(self):
        self._subscribers: set[queue.Queue] = set()
        self._lock = threading.Lock()
        self._poller: threading.Thread | None = None

    def subscribe(self) -> queue.Queue:
        q: queue.Queue = queue.Queue(maxsize=100)
        with self._lock:
            self._subscribers.add(q)
            if self._poller is None or not self._poller.is_alive():
                self._poller = threading.Thread(target=self._poll, daemon=True)
                self._poller.start()
        return q

    def unsubscribe(self, q: queue.Queue) -> None:
        with self._lock:
            self._subscribers.discard(q)

    def publish(self, event: str) -> None:
        with self._lock:
            subscribers = list(self._subscribers)
        for q in subscribers:
            try:
                q.put_nowait(event)
            except queue.Full:
                pass

    def _poll(self) -> None:
        head, digest, next_sessions = _ledger_head(), _sessions_digest(), 0.0
        while True:
            with self._lock:
                if not self._subscribers:
                    self._poller = None
                    return
            time.sleep(config.poll_seconds())
            now_head = _ledger_head()
            if now_head != head:
                head = now_head
                self.publish("ledger")
            if time.monotonic() >= next_sessions:
                next_sessions = time.monotonic() + config.poll_seconds() * SESSIONS_EVERY
                now_digest = _sessions_digest()
                if now_digest != digest:
                    digest = now_digest
                    self.publish("sessions")


HUB = Hub()
```

`ci.py`:

```python
"""CI as `gh` reports it, cached for a minute (spec 2026-10-03 §4.2)."""

import json
import re
import threading
import time

from . import commands, config

CACHE_SECONDS = 60
PR = re.compile(r"https://github\.com/([\w.-]+/[\w.-]+)/pull/(\d+)")
_cache: dict = {"at": 0.0, "value": None}
_lock = threading.Lock()


def clear_cache() -> None:
    with _lock:
        _cache.update(at=0.0, value=None)


def _gh(argv: list[str], *, ok_codes=(0,)):
    try:
        return json.loads(commands.run(argv, timeout=60, ok_codes=ok_codes))
    except commands.CommandFailed as error:
        return {"error": error.payload["output_tail"] or f"exit {error.payload['exit_code']}"}
    except ValueError:
        return {"error": "gh printed something that is not JSON"}


def collect(data: dict) -> dict:
    runs = _gh(["gh", "run", "list", "-R", config.repo(), "--branch", "master", "--workflow", "CI",
                "--limit", "1", "--json", "databaseId,status,conclusion,headSha,url,createdAt"])
    master = runs[0] if isinstance(runs, list) and runs else (runs if isinstance(runs, dict) else None)
    prs = []
    for sid, entry in data["slices"].items():
        if entry["status"] == "merged":
            continue
        for repo, number in PR.findall(entry.get("prs") or ""):
            # `gh pr checks` exits 8 while checks are pending; its JSON is still complete.
            checks = _gh(["gh", "pr", "checks", number, "-R", repo, "--json", "name,state,bucket,link"],
                         ok_codes=(0, 8))
            prs.append({"slice": sid, "repo": repo, "number": int(number),
                        "url": f"https://github.com/{repo}/pull/{number}", "checks": checks})
    return {"master": master, "prs": prs}


def cached(data: dict) -> dict:
    with _lock:
        if _cache["value"] is not None and time.monotonic() - _cache["at"] < CACHE_SECONDS:
            return _cache["value"]
    value = collect(data)
    with _lock:
        _cache.update(at=time.monotonic(), value=value)
    return value
```

`routes_live.py`:

```python
"""The event stream and CI (spec 2026-10-03 §4.2)."""

import queue

from . import ci
from .events import HUB
from .ledger_api import read
from .routing import STREAMED, route

PING_SECONDS = 15


@route("GET", "/api/events")
def events(req):
    handler = req.handler
    handler.send_response(200)
    handler.send_header("Content-Type", "text/event-stream")
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    q = HUB.subscribe()
    try:
        handler.wfile.write(b": connected\n\n")
        handler.wfile.flush()
        while True:
            try:
                handler.wfile.write(f"event: {q.get(timeout=PING_SECONDS)}\ndata: {{}}\n\n".encode())
            except queue.Empty:
                handler.wfile.write(b": ping\n\n")
            handler.wfile.flush()
    except OSError:
        pass  # the page went away
    finally:
        HUB.unsubscribe(q)
    return STREAMED


@route("GET", "/api/ci")
def ci_status(req):
    return ci.cached(read())
```

`app.py`, `make_server`: `from . import routes_actions, routes_ledger, routes_live  # noqa: F401`.

- [ ] **Step 4: Run all server tests; lint**

Run: `cd orchestra/server && python3 -m unittest discover -s tests -t . -v 2>&1 | tail -4`
Expected: `OK`, the whole suite finishing in under a minute.
Run: the Ruff commands from Task 3 Step 4 → clean; re-run the tests after any fix.

- [ ] **Step 5: Commit**

```bash
git add orchestra/server
git commit -m "feat(orchestra): live events and CI

Co-Authored-By: <implementing model> <noreply@anthropic.com>"
```

---
### Task 6: Web — scaffold, API layer, layout and the Overview

**Files (all under `orchestra/web/`):**
- Create: `package.json`, `tsconfig.json`, `vite.config.ts`, `vitest.config.ts`, `biome.json`, `index.html`, `.gitignore` (`node_modules/`, `dist/`, `coverage/` — Biome's VCS integration needs an ignore file beside its config, as the dashboard has)
- Create: `src/main.tsx`, `src/index.css`, `src/router.tsx`, `src/Layout.tsx`
- Create: `src/api/types.ts`, `src/api/client.ts`, `src/api/queries.ts`, `src/api/events.ts`
- Create: `src/ui/Button.tsx`, `src/ui/Badge.tsx`, `src/ui/Card.tsx`, `src/ui/Field.tsx`, `src/ui/ErrorBox.tsx`, `src/ui/ActionDialog.tsx`, `src/ui/tones.ts`
- Create: `src/components/SessionControls.tsx`, `SlotCards.tsx`, `ConductorCard.tsx`, `QueueStrip.tsx`, `CiPanel.tsx`, `EligiblePhases.tsx`
- Create: `src/pages/Overview.tsx`, and the four pages Tasks 7–8 fill in: `src/pages/PhasePage.tsx`, `QueuePage.tsx`, `EscalationsPage.tsx`, `CoordinationPage.tsx` (each, for now, exactly: `export function PhasePage() { return <h1 className="text-xl font-semibold">Phase</h1>; }` with its own name and heading)
- Create: `src/test/setup.ts`, `src/test/api.ts`, `src/test/fixtures.ts`, `src/test/render.tsx`
- Test: `src/api/client.test.ts`, `src/pages/Overview.test.tsx`, `src/Layout.test.tsx`

**Interfaces:**
- Consumes: the server API (Tasks 3–5): `GET /api/state` → `State`, `GET /api/ci` → `Ci`, `GET /api/events`, the POST routes.
- Produces (later tasks import these): `src/api/types.ts` (`State`, `Ledger`, `Phase`, `PhaseStatus`, `Slice`, `Session`, `SessionState`, `Escalation`, `Decision`, `Claim`, `LedgerRequest`, `Ci`); `client.ts` (`get<T>(path)`, `post<T>(path, body?)`, `ApiError {status, message, outputTail?, exitCode?}`, `resetToken()`); `queries.ts` (`keys`, `useOrchestraState()`, `useCi()`, `useLog(who, enabled)`, `freeSlots(ledger)`); `ui/*` (`Button {variant: primary|secondary|destructive|ghost, size: sm|md}`, `Badge {tone}`, `Card {title?, aside?}`, `Field {label}`, `inputClass`, `ErrorBox {error}`, `ActionDialog {label, title, command, run, confirmWord?, variant?, disabled?, warning?, canSubmit?, children?}`, `phaseTone`, `sessionTone`); `SessionControls {who, session}`; tests: `mockApi(routes) -> calls`, `makeState(patch?)`, `renderAt(path)`.

- [ ] **Step 1: Scaffold the project**

`orchestra/web/package.json` (every shared version is the dashboard's):

```json
{
	"name": "etqan_orchestra",
	"private": true,
	"version": "0.0.0",
	"type": "module",
	"scripts": {
		"dev": "vite",
		"build": "tsc --noEmit && vite build",
		"test": "vitest run",
		"test:coverage": "vitest run --coverage",
		"lint": "biome ci ."
	},
	"dependencies": {
		"@etqan/tokens": "github:Etqan-agency/etqan_tutor_tokens#v0.3.0",
		"@tanstack/react-query": "^5.99.0",
		"@tanstack/react-router": "^1.168.18",
		"@xterm/xterm": "^6.0.0",
		"lucide-react": "^1.18.0",
		"react": "^19.2.5",
		"react-dom": "^19.2.5"
	},
	"devDependencies": {
		"@biomejs/biome": "^2.4.11",
		"@tailwindcss/vite": "^4.2.2",
		"@testing-library/dom": "^10.4.1",
		"@testing-library/jest-dom": "^6.9.1",
		"@testing-library/react": "^16.3.2",
		"@testing-library/user-event": "^14.6.1",
		"@types/react": "^19.2.14",
		"@types/react-dom": "^19.2.3",
		"@vitejs/plugin-react-swc": "^4.3.0",
		"@vitest/coverage-v8": "^3.2.7",
		"jsdom": "^29.1.1",
		"tailwindcss": "^4.2.2",
		"typescript": "~6.0.2",
		"vite": "^8.0.4",
		"vitest": "^3.2.6"
	}
}
```

`tsconfig.json`: copy `dashboard/tsconfig.json` exactly (same compiler options, `paths` `@/*` → `./src/*`, `include: ["src"]`) and add `"types": ["vite/client", "vitest/globals", "@testing-library/jest-dom"]`.

`vite.config.ts`:

```ts
import path from "node:path";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react-swc";
import { defineConfig } from "vite";

// `just orchestra-dev`: Vite on 5174, the API proxied to the server. The server
// refuses foreign Origins, so the proxy drops the page's (localhost:5174) Origin.
const api = process.env.ORCHESTRA_API ?? "http://127.0.0.1:7700";

export default defineConfig({
	plugins: [react(), tailwindcss()],
	resolve: { alias: { "@": path.resolve(__dirname, "./src") } },
	server: {
		port: 5174,
		strictPort: true,
		proxy: {
			"/api": {
				target: api,
				changeOrigin: true,
				configure: (proxy) => {
					proxy.on("proxyReq", (request) => request.removeHeader("origin"));
				},
			},
		},
	},
});
```

`vitest.config.ts`:

```ts
import path from "node:path";
import react from "@vitejs/plugin-react-swc";
import { defineConfig } from "vitest/config";

export default defineConfig({
	plugins: [react()],
	resolve: { alias: { "@": path.resolve(__dirname, "./src") } },
	test: {
		environment: "jsdom",
		globals: true,
		setupFiles: ["./src/test/setup.ts"],
		coverage: {
			provider: "v8",
			all: true,
			include: ["src/**/*.{ts,tsx}"],
			exclude: ["src/main.tsx", "src/test/**", "**/*.test.{ts,tsx}", "**/*.d.ts"],
			reporter: ["text-summary", "text"],
			thresholds: { lines: 80, statements: 80, branches: 70, functions: 70 },
		},
	},
});
```

`biome.json`: copy `dashboard/biome.json`, with `"files": { "includes": ["src/**", "*.ts", "*.json"] }`.

`index.html`:

```html
<!doctype html>
<html lang="en">
	<head>
		<meta charset="UTF-8" />
		<meta name="viewport" content="width=device-width, initial-scale=1.0" />
		<title>Orchestra</title>
	</head>
	<body>
		<div id="root"></div>
		<script type="module" src="/src/main.tsx"></script>
	</body>
</html>
```

`src/index.css`:

```css
@import "tailwindcss";
@import "@etqan/tokens/tokens.css";
@import "@etqan/tokens/theme.css";
@import "@xterm/xterm/css/xterm.css";

body {
	background: var(--color-background);
	color: var(--color-foreground);
}
```

Run: `cd orchestra/web && npx pnpm@10 install` (the private tokens package installs through your GitHub credentials, as the dashboard's does). Commit `pnpm-lock.yaml` with the task.

- [ ] **Step 2: Write the test helpers and the failing tests**

`src/test/setup.ts`:

```ts
import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach, beforeEach, vi } from "vitest";
import { resetToken } from "@/api/client";

/** A controllable EventSource: tests call `FakeEventSource.last.emit("ledger")`. */
export class FakeEventSource {
	static last: FakeEventSource | null = null;
	onopen: (() => void) | null = null;
	onerror: (() => void) | null = null;
	private listeners = new Map<string, Array<() => void>>();
	readonly url: string;
	constructor(url: string) {
		this.url = url;
		FakeEventSource.last = this;
	}
	addEventListener(type: string, listener: () => void) {
		this.listeners.set(type, [...(this.listeners.get(type) ?? []), listener]);
	}
	emit(type: string) {
		for (const listener of this.listeners.get(type) ?? []) listener();
	}
	close() {}
}

beforeEach(() => {
	vi.stubGlobal("EventSource", FakeEventSource);
	const meta = document.createElement("meta");
	meta.name = "orchestra-token";
	meta.content = "test-token";
	document.head.append(meta);
	resetToken();
});

afterEach(() => {
	cleanup();
	document.head.querySelector('meta[name="orchestra-token"]')?.remove();
	vi.unstubAllGlobals();
	vi.restoreAllMocks();
});
```

`src/test/api.ts`:

```ts
import { vi } from "vitest";

type Result = { status?: number; body: unknown };
type Route = Result | ((body: unknown) => Result);
export type Call = { method: string; path: string; body: unknown; headers: Record<string, string> };

/** Replace fetch with a table of `"METHOD /path"` → response; returns the calls made. */
export function mockApi(routes: Record<string, Route>): Call[] {
	const calls: Call[] = [];
	vi.stubGlobal(
		"fetch",
		vi.fn(async (input: RequestInfo | URL, init: RequestInit = {}) => {
			const method = (init.method ?? "GET").toUpperCase();
			const path = String(input);
			const body = init.body ? JSON.parse(String(init.body)) : undefined;
			calls.push({ method, path, body, headers: Object.fromEntries(new Headers(init.headers).entries()) });
			const route = routes[`${method} ${path}`];
			if (route === undefined) {
				return new Response(JSON.stringify({ error: `no mock for ${method} ${path}` }), { status: 404 });
			}
			const result = typeof route === "function" ? route(body) : route;
			return new Response(JSON.stringify(result.body), {
				status: result.status ?? 200,
				headers: { "Content-Type": "application/json" },
			});
		}),
	);
	return calls;
}

/** The last write: after a successful action the page refetches, so the last call is a GET. */
export const lastPost = (calls: Call[]) => calls.filter((c) => c.method === "POST").at(-1);
```

`src/test/fixtures.ts`:

```ts
import type { Ledger, Phase, State } from "@/api/types";

const TITLES: Record<string, [string, string[]]> = {
	B2: ["Scheduling depth", []],
	B3: ["Money depth", []],
	B4: ["Payroll depth", ["B2", "B3"]],
	B5: ["Communication", ["B2"]],
	B6: ["Learning", ["B2"]],
	B7: ["Add-on sales", ["B3"]],
	B8: ["Marketing extras", []],
	B9: ["Platform extras", []],
	B10: ["AI", ["B6"]],
	B11: ["Apps", ["B2", "B3", "B4", "B5"]],
};

export function makeLedger(): Ledger {
	const phases: Record<string, Phase> = {};
	for (const [code, [title, requires]] of Object.entries(TITLES)) {
		phases[code] = {
			title, requires, status: "waiting-deps", slot: null, worktree: null, branch: null,
			spec: null, current_slice: null, current_task: null, session: null,
		};
	}
	return {
		phases, slices: {}, next_plan_number: 15, ownership: { scheduling: "B2" }, claims: [],
		shared_decisions: [], requests: [], queue: [], in_flight: null, main_heads: {},
		escalations: [], conductor_session: null,
	};
}

/** A state; `edit` changes its ledger in place. */
export function makeState(edit?: (ledger: Ledger) => void, extra: Partial<State> = {}): State {
	const ledger = makeLedger();
	edit?.(ledger);
	return {
		ledger,
		eligible: { free: 4, phases: ["B2", "B3", "B8", "B9"] },
		sessions: { conductor: { id: null, state: "none" } },
		stacks: {},
		...extra,
	};
}
```

(Biome will reformat the object literals; keep its formatting.)

`src/test/render.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createMemoryHistory, RouterProvider } from "@tanstack/react-router";
import { render } from "@testing-library/react";
import { makeRouter } from "@/router";

export function renderAt(path: string) {
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	const router = makeRouter(createMemoryHistory({ initialEntries: [path] }));
	const utils = render(
		<QueryClientProvider client={client}>
			<RouterProvider router={router} />
		</QueryClientProvider>,
	);
	return { ...utils, client, router };
}
```

`src/api/client.test.ts`:

```ts
import { ApiError, get, post, resetToken } from "./client";
import { mockApi } from "@/test/api";

describe("client", () => {
	it("sends the page's token with every write", async () => {
		const calls = mockApi({ "POST /api/queue/next": { body: { ok: true } } });
		await post("/api/queue/next");
		expect(calls[0].headers["x-orchestra-token"]).toBe("test-token");
		expect(calls[0].headers["content-type"]).toBe("application/json");
	});

	it("asks the dev server for a token when the page has none", async () => {
		document.head.querySelector('meta[name="orchestra-token"]')?.remove();
		resetToken();
		const calls = mockApi({
			"GET /api/token": { body: { token: "dev-token" } },
			"POST /api/queue/next": { body: { ok: true } },
		});
		await post("/api/queue/next");
		expect(calls[1].headers["x-orchestra-token"]).toBe("dev-token");
	});

	it("turns a ledger refusal and a failed command into ApiError", async () => {
		mockApi({
			"POST /api/queue/next": { status: 409, body: { error: "B3a is in flight" } },
			"POST /api/phases/B3/stack": { status: 500, body: { ok: false, exit_code: 3, output_tail: "boom" } },
		});
		await expect(post("/api/queue/next")).rejects.toMatchObject({ status: 409, message: "B3a is in flight" });
		const failure = await post("/api/phases/B3/stack", { up: true }).catch((e: ApiError) => e);
		expect(failure).toBeInstanceOf(ApiError);
		expect(failure).toMatchObject({ message: "command failed (exit 3)", outputTail: "boom", exitCode: 3 });
	});

	it("reads JSON", async () => {
		mockApi({ "GET /api/ci": { body: { master: null, prs: [] } } });
		expect(await get("/api/ci")).toEqual({ master: null, prs: [] });
	});
});
```

`src/Layout.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import { mockApi } from "@/test/api";
import { makeState } from "@/test/fixtures";
import { renderAt } from "@/test/render";
import { FakeEventSource } from "@/test/setup";

describe("Layout", () => {
	it("counts open escalations and shows the live connection", async () => {
		const state = makeState((l) => {
			l.escalations.push(
				{ id: "E1", phase: "B3", kind: "money", question: "keys?", status: "open", answer: null },
				{ id: "E2", phase: "B3", kind: "money", question: "x", status: "resolved", answer: "y" },
			);
		});
		mockApi({ "GET /api/state": { body: state }, "GET /api/ci": { body: { master: null, prs: [] } } });
		renderAt("/");
		expect(await screen.findByRole("link", { name: /Escalations 1/ })).toBeInTheDocument();
		expect(screen.getByText("Reconnecting…")).toBeInTheDocument();
		FakeEventSource.last?.onopen?.();
		expect(await screen.findByText("Live")).toBeInTheDocument();
	});

	it("refetches the state when the server says the ledger changed", async () => {
		const calls = mockApi({ "GET /api/state": { body: makeState() }, "GET /api/ci": { body: { master: null, prs: [] } } });
		renderAt("/");
		await screen.findByText("Slot 1");
		const before = calls.filter((c) => c.path === "/api/state").length;
		FakeEventSource.last?.emit("ledger");
		await waitFor(() => expect(calls.filter((c) => c.path === "/api/state").length).toBeGreaterThan(before));
	});
});
```

`src/pages/Overview.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { lastPost, mockApi } from "@/test/api";
import { makeState } from "@/test/fixtures";
import { renderAt } from "@/test/render";

const ci = { master: { status: "completed", conclusion: "success", headSha: "abc1234", url: "u", createdAt: "t" }, prs: [] };

function launchedState() {
	return makeState(
		(l) => {
			Object.assign(l.phases.B3, { status: "build", slot: 2, worktree: "/wt/b3", current_slice: "B3a", current_task: "Task 4", session: "ab12" });
			l.queue.push("B3b");
			l.in_flight = "B3a";
		},
		{
			eligible: { free: 3, phases: ["B2", "B8", "B9"] },
			sessions: { B3: { id: "ab12", state: "busy" }, conductor: { id: null, state: "none" } },
			stacks: { B3: true },
		},
	);
}

describe("Overview", () => {
	it("shows each slot, the conductor, the queue and CI", async () => {
		mockApi({ "GET /api/state": { body: launchedState() }, "GET /api/ci": { body: ci } });
		renderAt("/");
		const slot2 = (await screen.findByRole("link", { name: "B3 · Money depth" })).closest("section") as HTMLElement;
		expect(within(slot2).getByText("build")).toBeInTheDocument();
		expect(within(slot2).getByText("session busy")).toBeInTheDocument();
		expect(within(slot2).getByText("stack up")).toBeInTheDocument();
		expect(within(slot2).getByText("Task 4")).toBeInTheDocument();
		expect(screen.getAllByText("Free")).toHaveLength(3);
		expect(screen.getByText("In flight: B3a")).toBeInTheDocument();
		expect(screen.getByText("B3b")).toBeInTheDocument();
		expect(await screen.findByText("success")).toBeInTheDocument();
	});

	it("starts the conductor with the chosen mode", async () => {
		const calls = mockApi({
			"GET /api/state": { body: makeState() },
			"GET /api/ci": { body: ci },
			"POST /api/conductor/session/start": { body: { ok: true, id: "cd34" } },
		});
		renderAt("/");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Start conductor" }));
		const dialog = screen.getByRole("dialog");
		expect(within(dialog).getByText("start-session.sh conductor --mode auto")).toBeInTheDocument();
		await user.selectOptions(within(dialog).getByLabelText("Permission mode"), "plan");
		expect(within(dialog).queryByRole("option", { name: "bypassPermissions" })).toBeNull();
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		const start = calls.find((c) => c.method === "POST");
		expect(start?.body).toEqual({ mode: "plan", model: "", effort: "" });
		expect(screen.queryByRole("dialog")).toBeNull();
	});

	it("launches an eligible phase into a free slot and shows a failure's output", async () => {
		const calls = mockApi({
			"GET /api/state": { body: launchedState() },
			"GET /api/ci": { body: ci },
			"POST /api/phases/B8/launch": { status: 500, body: { ok: false, exit_code: 3, output_tail: "fatal: boom" } },
		});
		renderAt("/");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Launch B8" }));
		const dialog = screen.getByRole("dialog");
		expect(within(dialog).getByLabelText("Branch suffix")).toHaveValue("b8a-marketing-extras");
		const slots = within(within(dialog).getByLabelText("Slot")).getAllByRole("option").map((o) => o.textContent);
		expect(slots).toEqual(["1", "3", "4"]);
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() => expect(lastPost(calls)?.body).toEqual({ suffix: "b8a-marketing-extras", slot: 1, mode: "auto" }));
		expect(await within(dialog).findByRole("alert")).toHaveTextContent("fatal: boom");
	});
});
```

- [ ] **Step 3: Run them to verify they fail**

Run: `cd orchestra/web && npx pnpm@10 test 2>&1 | tail -8`
Expected: FAIL — cannot resolve `@/api/client`, `@/router`.

- [ ] **Step 4: Write the app**

`src/api/types.ts`:

```ts
export type PhaseStatus = "waiting-deps" | "spec" | "plan" | "build" | "review" | "queued" | "merged" | "paused";
export const PHASE_STATUSES: PhaseStatus[] = ["waiting-deps", "spec", "plan", "build", "review", "queued", "merged", "paused"];

export type Phase = {
	title: string;
	status: PhaseStatus;
	requires: string[];
	slot: number | null;
	worktree: string | null;
	branch: string | null;
	spec: string | null;
	current_slice: string | null;
	current_task: string | null;
	session: string | null;
};

export type Slice = {
	phase: string;
	status: "spec" | "plan" | "build" | "review" | "queued" | "in-flight" | "merged";
	requires: string[];
	plan_number: number | null;
	spec: string | null;
	plan: string | null;
	prs: string | null;
	bounces: number;
	last_bounce?: string;
};

export type Escalation = { id: string; phase: string; kind: string; question: string; status: "open" | "resolved"; answer: string | null };
export type Decision = { id: string; phase: string; decision: string; affects: string[]; source: string };
export type Claim = { target: string; phase: string; reason: string; since: string };
export type LedgerRequest = { id: string; from: string; app: string; to_owner: string; what: string; status: "open" | "done" };

export type Ledger = {
	phases: Record<string, Phase>;
	slices: Record<string, Slice>;
	next_plan_number: number;
	ownership: Record<string, string>;
	claims: Claim[];
	shared_decisions: Decision[];
	requests: LedgerRequest[];
	queue: string[];
	in_flight: string | null;
	main_heads: Record<string, string>;
	escalations: Escalation[];
	conductor_session: string | null;
};

export type SessionState = "busy" | "idle" | "exited" | "gone" | "none";
export type Session = { id: string | null; state: SessionState; session_id?: string | null; cwd?: string | null };

export type State = {
	ledger: Ledger;
	eligible: { free: number; phases: string[] };
	sessions: Record<string, Session>;
	stacks: Record<string, boolean>;
};

export type Check = { name: string; state: string; bucket: string; link: string };
export type Failure = { error: string };
export type Ci = {
	master: { status: string; conclusion: string; headSha: string; url: string; createdAt: string } | Failure | null;
	prs: { slice: string; repo: string; number: number; url: string; checks: Check[] | Failure }[];
};
```

`src/api/client.ts`:

```ts
export class ApiError extends Error {
	readonly status: number;
	readonly outputTail?: string;
	readonly exitCode?: number;

	constructor(status: number, message: string, outputTail?: string, exitCode?: number) {
		super(message);
		this.name = "ApiError";
		this.status = status;
		this.outputTail = outputTail;
		this.exitCode = exitCode;
	}
}

let tokenPromise: Promise<string> | null = null;

/** The server puts its token in index.html; under `just orchestra-dev` Vite serves
 * the page, so the dev server's /api/token supplies it instead. */
function token(): Promise<string> {
	if (!tokenPromise) {
		const meta = document.querySelector<HTMLMetaElement>('meta[name="orchestra-token"]');
		tokenPromise = meta
			? Promise.resolve(meta.content)
			: get<{ token: string }>("/api/token").then((body) => body.token);
	}
	return tokenPromise;
}

export function resetToken() {
	tokenPromise = null;
}

async function parse<T>(response: Response): Promise<T> {
	const body = await response.json().catch(() => ({}));
	if (!response.ok) {
		const message =
			body.error ?? (body.exit_code !== undefined ? `command failed (exit ${body.exit_code})` : `HTTP ${response.status}`);
		throw new ApiError(response.status, message, body.output_tail, body.exit_code);
	}
	return body as T;
}

export async function get<T>(path: string): Promise<T> {
	return parse<T>(await fetch(path, { headers: { Accept: "application/json" } }));
}

export async function post<T = { ok: boolean }>(path: string, body: unknown = {}): Promise<T> {
	const response = await fetch(path, {
		method: "POST",
		headers: { "Content-Type": "application/json", "X-Orchestra-Token": await token() },
		body: JSON.stringify(body),
	});
	return parse<T>(response);
}
```

`src/api/queries.ts`:

```ts
import { useQuery } from "@tanstack/react-query";
import { get } from "./client";
import type { Ci, Ledger, State } from "./types";

export const keys = {
	state: ["state"] as const,
	ci: ["ci"] as const,
	log: (who: string) => ["log", who] as const,
};

export const useOrchestraState = () => useQuery({ queryKey: keys.state, queryFn: () => get<State>("/api/state") });

export const useCi = () =>
	useQuery({ queryKey: keys.ci, queryFn: () => get<Ci>("/api/ci"), refetchInterval: 60_000 });

export const useLog = (who: string, enabled: boolean) =>
	useQuery({
		queryKey: keys.log(who),
		queryFn: () => get<{ text: string }>(who === "conductor" ? "/api/conductor/log" : `/api/phases/${who}/log`),
		refetchInterval: enabled ? 3000 : false,
	});

export const SLOTS = [1, 2, 3, 4];

export function freeSlots(ledger: Ledger): number[] {
	const held = new Set(
		Object.values(ledger.phases)
			.filter((p) => p.slot !== null && p.status !== "merged")
			.map((p) => p.slot),
	);
	return SLOTS.filter((slot) => !held.has(slot));
}
```

`src/api/events.ts`:

```ts
import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { keys } from "./queries";

/** The server's event stream: a ledger commit or a session change refetches the state. */
export function useLiveUpdates(): boolean {
	const client = useQueryClient();
	const [connected, setConnected] = useState(false);
	useEffect(() => {
		const source = new EventSource("/api/events");
		source.onopen = () => setConnected(true);
		source.onerror = () => setConnected(false);
		const refresh = () => client.invalidateQueries({ queryKey: keys.state });
		source.addEventListener("ledger", refresh);
		source.addEventListener("sessions", refresh);
		return () => source.close();
	}, [client]);
	return connected;
}
```

`src/ui/tones.ts`:

```ts
import type { PhaseStatus, SessionState } from "@/api/types";

export type Tone = "neutral" | "success" | "warning" | "destructive" | "info";

export const phaseTone: Record<PhaseStatus, Tone> = {
	"waiting-deps": "neutral", spec: "info", plan: "info", build: "info",
	review: "warning", queued: "warning", merged: "success", paused: "neutral",
};

export const sessionTone: Record<SessionState, Tone> = {
	busy: "success", idle: "info", exited: "warning", gone: "destructive", none: "neutral",
};
```

`src/ui/Badge.tsx`:

```tsx
import type { ReactNode } from "react";
import type { Tone } from "./tones";

const TONES: Record<Tone, string> = {
	neutral: "bg-muted text-muted-foreground",
	success: "bg-success text-success-foreground",
	warning: "bg-warning text-warning-foreground",
	destructive: "bg-destructive text-destructive-foreground",
	info: "bg-info text-info-foreground",
};

export function Badge({ tone = "neutral", children }: { tone?: Tone; children: ReactNode }) {
	return <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${TONES[tone]}`}>{children}</span>;
}
```

`src/ui/Button.tsx`:

```tsx
import type { ButtonHTMLAttributes } from "react";

type Variant = "primary" | "secondary" | "destructive" | "ghost";
const VARIANTS: Record<Variant, string> = {
	primary: "bg-primary text-primary-foreground hover:opacity-90",
	secondary: "bg-secondary text-secondary-foreground hover:opacity-90",
	destructive: "bg-destructive text-destructive-foreground hover:opacity-90",
	ghost: "bg-transparent text-foreground hover:bg-muted",
};

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; size?: "sm" | "md" };

export function Button({ variant = "primary", size = "md", className = "", ...props }: ButtonProps) {
	const sizing = size === "sm" ? "px-2.5 py-1 text-xs" : "px-3.5 py-2 text-sm";
	return (
		<button
			type="button"
			className={`inline-flex items-center gap-1.5 rounded-md font-medium focus-visible:outline-2 focus-visible:outline-ring disabled:cursor-not-allowed disabled:opacity-50 ${sizing} ${VARIANTS[variant]} ${className}`}
			{...props}
		/>
	);
}
```

`src/ui/Card.tsx`:

```tsx
import type { ReactNode } from "react";

export function Card({ title, aside, children }: { title?: ReactNode; aside?: ReactNode; children: ReactNode }) {
	return (
		<section className="rounded-lg border border-border bg-card p-4 text-card-foreground">
			{(title || aside) && (
				<header className="mb-3 flex items-baseline justify-between gap-3">
					{title && <h2 className="font-semibold">{title}</h2>}
					{aside && <span className="text-xs text-muted-foreground">{aside}</span>}
				</header>
			)}
			{children}
		</section>
	);
}
```

`src/ui/Field.tsx`:

```tsx
import type { ReactNode } from "react";

export const inputClass =
	"w-full rounded-md border border-input bg-background px-2.5 py-1.5 text-sm focus-visible:outline-2 focus-visible:outline-ring";

/** A label wrapping its control, so getByLabelText finds it. */
export function Field({ label, children }: { label: string; children: ReactNode }) {
	return (
		// biome-ignore lint/a11y/noLabelWithoutControl: the control is the child passed in, which the rule cannot see
		<label className="block text-sm">
			<span className="mb-1 block font-medium">{label}</span>
			{children}
		</label>
	);
}
```

`src/ui/ErrorBox.tsx`:

```tsx
import { ApiError } from "@/api/client";

export function ErrorBox({ error }: { error: unknown }) {
	const message = error instanceof Error ? error.message : String(error);
	const tail = error instanceof ApiError ? error.outputTail : undefined;
	return (
		<div role="alert" className="mt-3 rounded-md border border-destructive p-3 text-sm">
			<p className="font-medium text-destructive">{message}</p>
			{tail && <pre className="mt-2 max-h-64 overflow-auto whitespace-pre-wrap font-mono text-xs">{tail}</pre>}
		</div>
	);
}
```

`src/ui/ActionDialog.tsx`:

```tsx
import { useQueryClient } from "@tanstack/react-query";
import { type ReactNode, useEffect, useId, useState } from "react";
import { Button } from "./Button";
import { ErrorBox } from "./ErrorBox";
import { Field, inputClass } from "./Field";

type Props = {
	label: string;
	title: string;
	/** Exactly what will run or change, shown before confirming. */
	command: string;
	run: () => Promise<unknown>;
	confirmWord?: string;
	variant?: "primary" | "secondary" | "destructive";
	disabled?: boolean;
	warning?: string;
	canSubmit?: boolean;
	children?: ReactNode;
};

/** Every change goes through one of these: a button, then a dialog naming the command. */
export function ActionDialog({ label, title, command, run, confirmWord, variant = "secondary", disabled, warning, canSubmit = true, children }: Props) {
	const client = useQueryClient();
	const id = useId();
	const [open, setOpen] = useState(false);
	const [typed, setTyped] = useState("");
	const [pending, setPending] = useState(false);
	const [error, setError] = useState<unknown>(null);

	const close = () => {
		setOpen(false);
		setTyped("");
		setError(null);
	};

	useEffect(() => {
		if (!open) return;
		const onKey = (event: KeyboardEvent) => event.key === "Escape" && !pending && close();
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	});

	async function submit() {
		setPending(true);
		setError(null);
		try {
			await run();
			await client.invalidateQueries();
			close();
		} catch (caught) {
			setError(caught);
		} finally {
			setPending(false);
		}
	}

	const ready = canSubmit && (!confirmWord || typed === confirmWord) && !pending;
	return (
		<>
			<Button variant={variant === "destructive" ? "destructive" : "secondary"} size="sm" disabled={disabled} onClick={() => setOpen(true)}>
				{label}
			</Button>
			{open && (
				<div className="fixed inset-0 z-50 flex items-center justify-center bg-overlay p-4">
					<div role="dialog" aria-modal="true" aria-labelledby={id} className="w-full max-w-lg rounded-lg border border-border bg-card p-5 text-card-foreground shadow-lg">
						<h2 id={id} className="text-lg font-semibold">{title}</h2>
						{warning && <p className="mt-2 rounded-md bg-warning p-2 text-sm text-warning-foreground">{warning}</p>}
						<p className="mt-3 text-sm text-muted-foreground">This will run:</p>
						<pre className="mt-1 whitespace-pre-wrap rounded-md bg-muted p-2 font-mono text-xs">{command}</pre>
						{children && <div className="mt-4 space-y-3">{children}</div>}
						{confirmWord && (
							<div className="mt-4">
								<Field label={`Type ${confirmWord} to confirm`}>
									<input className={inputClass} value={typed} onChange={(e) => setTyped(e.target.value)} />
								</Field>
							</div>
						)}
						{error !== null && <ErrorBox error={error} />}
						<div className="mt-5 flex justify-end gap-2">
							<Button variant="ghost" onClick={close} disabled={pending}>Cancel</Button>
							<Button variant={variant === "destructive" ? "destructive" : "primary"} disabled={!ready} onClick={submit}>
								{pending ? "Working…" : "Confirm"}
							</Button>
						</div>
					</div>
				</div>
			)}
		</>
	);
}
```

`src/components/SessionControls.tsx`:

```tsx
import { useState } from "react";
import { post } from "@/api/client";
import type { Session } from "@/api/types";
import { ActionDialog } from "@/ui/ActionDialog";
import { Button } from "@/ui/Button";
import { Field, inputClass } from "@/ui/Field";

const MODES = ["auto", "acceptEdits", "manual", "plan", "dontAsk"];
const EFFORTS = ["", "low", "medium", "high", "xhigh", "max"];

function base(who: string) {
	return who === "conductor" ? "/api/conductor/session" : `/api/phases/${who}/session`;
}

export function ModeField({ value, onChange }: { value: string; onChange: (mode: string) => void }) {
	return (
		<Field label="Permission mode">
			<select className={inputClass} value={value} onChange={(e) => onChange(e.target.value)}>
				{MODES.map((m) => <option key={m}>{m}</option>)}
			</select>
		</Field>
	);
}

/** Start / Stop / Restart a phase's (or the conductor's) background session. */
export function SessionControls({ who, session }: { who: string; session: Session | undefined }) {
	const [mode, setMode] = useState("auto");
	const [model, setModel] = useState("");
	const [effort, setEffort] = useState("");
	const state = session?.state ?? "none";
	const running = state === "busy" || state === "idle";
	const name = who === "conductor" ? "conductor" : who;
	const flags = [`--mode ${mode}`, model && `--model ${model}`, effort && `--effort ${effort}`].filter(Boolean).join(" ");
	return (
		<div className="flex flex-wrap items-center gap-2">
			<ActionDialog label={`Start ${name}`} title={`Start the ${name} session`} variant="primary" disabled={running}
				command={`start-session.sh ${who} ${flags}`} run={() => post(`${base(who)}/start`, { mode, model, effort })}>
				<ModeField value={mode} onChange={setMode} />
				<Field label="Model (optional)">
					<input className={inputClass} value={model} placeholder="session default" onChange={(e) => setModel(e.target.value.trim())} />
				</Field>
				<Field label="Effort (optional)">
					<select className={inputClass} value={effort} onChange={(e) => setEffort(e.target.value)}>
						{EFFORTS.map((e) => <option key={e} value={e}>{e || "session default"}</option>)}
					</select>
				</Field>
			</ActionDialog>
			<ActionDialog label={`Stop ${name}`} title={`Stop the ${name} session`} variant="destructive" disabled={!running}
				command={`claude stop ${session?.id ?? ""}`} run={() => post(`${base(who)}/stop`)} />
			<ActionDialog label={`Restart ${name}`} title={`Restart the ${name} session`} disabled={state === "none"}
				command={running ? `claude respawn ${session?.id}` : `claude --bg --resume … (or start-session.sh ${who})`}
				run={() => post(`${base(who)}/restart`, { mode })}>
				<ModeField value={mode} onChange={setMode} />
			</ActionDialog>
			{session?.id && (
				<Button variant="ghost" size="sm" onClick={() => navigator.clipboard?.writeText(`claude attach ${session.id}`)}>
					Copy attach command
				</Button>
			)}
		</div>
	);
}
```

`src/components/SlotCards.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import type { Phase, Session, State } from "@/api/types";
import { SLOTS } from "@/api/queries";
import { Badge } from "@/ui/Badge";
import { Card } from "@/ui/Card";
import { phaseTone, sessionTone } from "@/ui/tones";

function SlotCard({ slot, code, phase, session, stackUp }: { slot: number; code: string; phase: Phase; session?: Session; stackUp: boolean }) {
	const state = session?.state ?? "none";
	return (
		<Card title={<Link to="/phase/$code" params={{ code }} className="hover:underline">{`${code} · ${phase.title}`}</Link>} aside={`Slot ${slot}`}>
			<div className="flex flex-wrap gap-2">
				<Badge tone={phaseTone[phase.status]}>{phase.status}</Badge>
				<Badge tone={sessionTone[state]}>{`session ${state}`}</Badge>
				<Badge tone={stackUp ? "success" : "neutral"}>{`stack ${stackUp ? "up" : "down"}`}</Badge>
			</div>
			<dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
				<dt className="text-muted-foreground">Slice</dt>
				<dd>{phase.current_slice ?? "—"}</dd>
				<dt className="text-muted-foreground">Task</dt>
				<dd>{phase.current_task ?? "—"}</dd>
			</dl>
		</Card>
	);
}

export function SlotCards({ state }: { state: State }) {
	const bySlot = new Map<number, string>();
	for (const [code, phase] of Object.entries(state.ledger.phases)) {
		if (phase.slot !== null && phase.status !== "merged") bySlot.set(phase.slot, code);
	}
	return (
		<div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
			{SLOTS.map((slot) => {
				const code = bySlot.get(slot);
				return code ? (
					<SlotCard key={slot} slot={slot} code={code} phase={state.ledger.phases[code]} session={state.sessions[code]} stackUp={state.stacks[code] ?? false} />
				) : (
					<Card key={slot} title={`Slot ${slot}`}>
						<p className="text-sm text-muted-foreground">Free</p>
					</Card>
				);
			})}
		</div>
	);
}
```

`src/components/ConductorCard.tsx`:

```tsx
import type { State } from "@/api/types";
import { Badge } from "@/ui/Badge";
import { Card } from "@/ui/Card";
import { sessionTone } from "@/ui/tones";
import { SessionControls } from "./SessionControls";

export function ConductorCard({ state }: { state: State }) {
	const session = state.sessions.conductor;
	const current = session?.state ?? "none";
	return (
		<Card title="Conductor" aside={<Badge tone={sessionTone[current]}>{`session ${current}`}</Badge>}>
			<p className="mb-3 text-sm text-muted-foreground">Merges the queue and starts eligible phases on its own.</p>
			<SessionControls who="conductor" session={session} />
		</Card>
	);
}
```

`src/components/QueueStrip.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import type { Ledger } from "@/api/types";
import { Card } from "@/ui/Card";

export function QueueStrip({ ledger }: { ledger: Ledger }) {
	return (
		<Card title="Merge queue" aside={<Link to="/queue" className="hover:underline">Open queue</Link>}>
			<p className="text-sm font-medium">{`In flight: ${ledger.in_flight ?? "—"}`}</p>
			{ledger.queue.length === 0 ? (
				<p className="mt-2 text-sm text-muted-foreground">Nothing queued.</p>
			) : (
				<ol className="mt-2 flex flex-wrap gap-2 text-sm">
					{ledger.queue.map((sid) => <li key={sid} className="rounded-md bg-muted px-2 py-0.5">{sid}</li>)}
				</ol>
			)}
		</Card>
	);
}
```

`src/components/CiPanel.tsx`:

```tsx
import { useCi } from "@/api/queries";
import type { Check, Failure } from "@/api/types";
import { Badge } from "@/ui/Badge";
import { Card } from "@/ui/Card";

const isFailure = (value: unknown): value is Failure => typeof value === "object" && value !== null && "error" in value;

function summary(checks: Check[]) {
	const count = (bucket: string) => checks.filter((c) => c.bucket === bucket).length;
	return `${count("pass")} passed · ${count("fail")} failed · ${count("pending")} pending`;
}

export function CiPanel() {
	const { data } = useCi();
	const master = data?.master;
	return (
		<Card title="CI">
			{!data ? (
				<p className="text-sm text-muted-foreground">Loading…</p>
			) : (
				<div className="space-y-2 text-sm">
					<p className="flex items-center gap-2">
						<span>master</span>
						{isFailure(master) ? (
							<span className="text-destructive">{master.error}</span>
						) : master ? (
							<a href={master.url} target="_blank" rel="noreferrer">
								<Badge tone={master.conclusion === "success" ? "success" : master.status === "completed" ? "destructive" : "info"}>
									{master.conclusion || master.status}
								</Badge>
							</a>
						) : (
							<span className="text-muted-foreground">no runs</span>
						)}
					</p>
					{data.prs.map((pr) => (
						<p key={pr.url}>
							<a className="hover:underline" href={pr.url} target="_blank" rel="noreferrer">{`${pr.slice} · #${pr.number}`}</a>{" "}
							<span className="text-muted-foreground">{isFailure(pr.checks) ? pr.checks.error : summary(pr.checks)}</span>
						</p>
					))}
				</div>
			)}
		</Card>
	);
}
```

`src/components/EligiblePhases.tsx`:

```tsx
import { useState } from "react";
import { post } from "@/api/client";
import { freeSlots } from "@/api/queries";
import type { State } from "@/api/types";
import { ActionDialog } from "@/ui/ActionDialog";
import { Card } from "@/ui/Card";
import { Field, inputClass } from "@/ui/Field";
import { ModeField } from "./SessionControls";

const slug = (text: string) => text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

function LaunchDialog({ code, title, slots }: { code: string; title: string; slots: number[] }) {
	const [suffix, setSuffix] = useState(`${code.toLowerCase()}a-${slug(title)}`);
	const [slot, setSlot] = useState(slots[0]);
	const [mode, setMode] = useState("auto");
	return (
		<ActionDialog label={`Launch ${code}`} title={`Launch ${code} · ${title}`} variant="primary"
			command={`launch-phase.sh ${code} ${suffix} ${slot}\nstart-session.sh ${code} --mode ${mode}`}
			canSubmit={/^[a-z0-9][a-z0-9-]*$/.test(suffix)}
			run={() => post(`/api/phases/${code}/launch`, { suffix, slot, mode })}>
			<Field label="Branch suffix">
				<input className={inputClass} value={suffix} onChange={(e) => setSuffix(e.target.value.trim())} />
			</Field>
			<Field label="Slot">
				<select className={inputClass} value={slot} onChange={(e) => setSlot(Number(e.target.value))}>
					{slots.map((s) => <option key={s} value={s}>{s}</option>)}
				</select>
			</Field>
			<ModeField value={mode} onChange={setMode} />
		</ActionDialog>
	);
}

export function EligiblePhases({ state }: { state: State }) {
	const slots = freeSlots(state.ledger);
	const codes = state.eligible.phases;
	return (
		<Card title="Ready to launch" aside={`${slots.length} free slot${slots.length === 1 ? "" : "s"}`}>
			{codes.length === 0 ? (
				<p className="text-sm text-muted-foreground">No phase is ready, or no slot is free.</p>
			) : (
				<ul className="space-y-2">
					{codes.map((code) => (
						<li key={code} className="flex items-center justify-between gap-3 text-sm">
							<span>{`${code} · ${state.ledger.phases[code].title}`}</span>
							<LaunchDialog code={code} title={state.ledger.phases[code].title} slots={slots} />
						</li>
					))}
				</ul>
			)}
		</Card>
	);
}
```

`src/pages/Overview.tsx`:

```tsx
import { CiPanel } from "@/components/CiPanel";
import { ConductorCard } from "@/components/ConductorCard";
import { EligiblePhases } from "@/components/EligiblePhases";
import { QueueStrip } from "@/components/QueueStrip";
import { SlotCards } from "@/components/SlotCards";
import { useOrchestraState } from "@/api/queries";
import { ErrorBox } from "@/ui/ErrorBox";

export function Overview() {
	const { data, error } = useOrchestraState();
	if (error) return <ErrorBox error={error} />;
	if (!data) return <p className="text-sm text-muted-foreground">Loading…</p>;
	return (
		<div className="space-y-6">
			<SlotCards state={data} />
			<div className="grid gap-4 lg:grid-cols-3">
				<ConductorCard state={data} />
				<QueueStrip ledger={data.ledger} />
				<CiPanel />
			</div>
			<EligiblePhases state={data} />
		</div>
	);
}
```

`src/Layout.tsx`:

```tsx
import { Link, Outlet } from "@tanstack/react-router";
import { useLiveUpdates } from "@/api/events";
import { useOrchestraState } from "@/api/queries";
import { Badge } from "@/ui/Badge";

const linkClass = "text-muted-foreground hover:text-foreground";
const active = { className: "font-semibold text-foreground" };

export function Layout() {
	const connected = useLiveUpdates();
	const { data } = useOrchestraState();
	const open = data?.ledger.escalations.filter((e) => e.status === "open").length ?? 0;
	return (
		<div className="min-h-screen bg-background text-foreground">
			<header className="border-b border-border bg-card">
				<div className="mx-auto flex max-w-7xl items-center gap-6 px-4 py-3">
					<span className="font-semibold">Orchestra</span>
					<nav className="flex items-center gap-4 text-sm">
						<Link to="/" className={linkClass} activeProps={active} activeOptions={{ exact: true }}>Overview</Link>
						<Link to="/queue" className={linkClass} activeProps={active}>Queue</Link>
						<Link to="/escalations" className={linkClass} activeProps={active}>
							Escalations <Badge tone={open ? "destructive" : "neutral"}>{open}</Badge>
						</Link>
						<Link to="/coordination" className={linkClass} activeProps={active}>Coordination</Link>
					</nav>
					<span className="ml-auto flex items-center gap-2 text-xs text-muted-foreground">
						<span aria-hidden="true" className={`size-2 rounded-full ${connected ? "bg-success" : "bg-destructive"}`} />
						{connected ? "Live" : "Reconnecting…"}
					</span>
				</div>
			</header>
			<main className="mx-auto max-w-7xl px-4 py-6">
				<Outlet />
			</main>
		</div>
	);
}
```

`src/router.tsx`:

```tsx
import { createRootRoute, createRoute, createRouter, type RouterHistory } from "@tanstack/react-router";
import { Layout } from "./Layout";
import { CoordinationPage } from "./pages/CoordinationPage";
import { EscalationsPage } from "./pages/EscalationsPage";
import { Overview } from "./pages/Overview";
import { PhasePage } from "./pages/PhasePage";
import { QueuePage } from "./pages/QueuePage";

const root = createRootRoute({ component: Layout });
const routeTree = root.addChildren([
	createRoute({ getParentRoute: () => root, path: "/", component: Overview }),
	createRoute({ getParentRoute: () => root, path: "/phase/$code", component: PhasePage }),
	createRoute({ getParentRoute: () => root, path: "/queue", component: QueuePage }),
	createRoute({ getParentRoute: () => root, path: "/escalations", component: EscalationsPage }),
	createRoute({ getParentRoute: () => root, path: "/coordination", component: CoordinationPage }),
]);

export function makeRouter(history?: RouterHistory) {
	return createRouter({ routeTree, history });
}

export const router = makeRouter();

declare module "@tanstack/react-router" {
	interface Register {
		router: typeof router;
	}
}
```

`src/main.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { RouterProvider } from "@tanstack/react-router";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { router } from "./router";
import "./index.css";

const client = new QueryClient({ defaultOptions: { queries: { staleTime: 2000 } } });
const root = document.getElementById("root");
if (root) {
	createRoot(root).render(
		<StrictMode>
			<QueryClientProvider client={client}>
				<RouterProvider router={router} />
			</QueryClientProvider>
		</StrictMode>,
	);
}
```

`PhasePage` reads its param later; for now the four page files are the one-line headings named in **Files**.

- [ ] **Step 5: Run the tests, types, lint and build**

Run (from `orchestra/web`): `npx pnpm@10 exec biome check --write . && npx pnpm@10 test && npx pnpm@10 build && npx pnpm@10 lint`
Expected: tests pass; `tsc` clean; `dist/` built; Biome clean. (Coverage is enforced from Task 8, when every page exists.)

- [ ] **Step 6: Commit**

```bash
git add orchestra/web
git commit -m "feat(orchestra): the web app — API layer, layout and Overview

Co-Authored-By: <implementing model> <noreply@anthropic.com>"
```

---

### Task 7: Web — the phase page and its live log

**Files:**
- Create: `orchestra/web/src/components/SessionLog.tsx`, `SlicesTable.tsx`, `PhaseControls.tsx`
- Modify: `orchestra/web/src/pages/PhasePage.tsx` (replace the heading-only page)
- Test: `orchestra/web/src/pages/PhasePage.test.tsx`

**Interfaces:**
- Consumes: Task 6's `useOrchestraState`, `useLog(who, enabled)`, `freeSlots`, `post`, `ActionDialog`, `SessionControls`, `Card`, `Badge`, `Field`, `inputClass`, `phaseTone`, `sessionTone`, `PHASE_STATUSES`, test helpers.
- Produces: `SessionLog {who}` (Task 8 does not use it; the conductor's log is on the Overview only through its card — the phase page is per phase).

- [ ] **Step 1: Write the failing tests** — `src/pages/PhasePage.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { vi } from "vitest";
import { lastPost, mockApi } from "@/test/api";
import { makeState } from "@/test/fixtures";
import { renderAt } from "@/test/render";

const writes: string[] = [];
vi.mock("@xterm/xterm", () => ({
	Terminal: class {
		open() {}
		reset() { writes.length = 0; }
		write(text: string) { writes.push(text); }
		dispose() {}
	},
}));

function state() {
	return makeState(
		(l) => {
			Object.assign(l.phases.B3, { status: "build", slot: 2, worktree: "/wt/b3", branch: "feat/b3a-money", session: "ab12" });
			Object.assign(l.phases.B2, { status: "build", slot: 1, worktree: "/wt/b2" });
			l.slices.B3a = { phase: "B3", status: "merged", requires: [], plan_number: 16, spec: null, plan: null, prs: "https://github.com/x/y/pull/9", bounces: 0 };
			l.slices.B3b = { phase: "B3", status: "build", requires: ["B3a", "B2a"], plan_number: 17, spec: null, plan: null, prs: null, bounces: 1 };
		},
		{ sessions: { B3: { id: "ab12", state: "busy" }, conductor: { id: null, state: "none" } }, stacks: { B3: true } },
	);
}

const routes = (extra = {}) => ({
	"GET /api/state": { body: state() },
	"GET /api/ci": { body: { master: null, prs: [] } },
	"GET /api/phases/B3/log": { body: { text: "\u001b[1mhello\u001b[0m" } },
	...extra,
});

describe("PhasePage", () => {
	it("shows the phase, its slices with their requirements, and its live log", async () => {
		mockApi(routes());
		renderAt("/phase/B3");
		expect(await screen.findByRole("heading", { name: "B3 · Money depth" })).toBeInTheDocument();
		expect(screen.getByText("feat/b3a-money")).toBeInTheDocument();
		const b3b = screen.getByRole("row", { name: /B3b/ });
		expect(within(b3b).getByText("B3a ✓")).toBeInTheDocument();
		expect(within(b3b).getByText("B2a ✗")).toBeInTheDocument();
		expect(screen.getByRole("link", { name: "#9" })).toHaveAttribute("href", "https://github.com/x/y/pull/9");
		await vi.waitFor(() => expect(writes.join("")).toContain("hello"));
	});

	it("moves the phase to a free slot", async () => {
		const calls = mockApi(routes({ "POST /api/phases/B3/slot": { body: { ok: true } } }));
		renderAt("/phase/B3");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Move slot" }));
		const dialog = screen.getByRole("dialog");
		const options = within(within(dialog).getByLabelText("New slot")).getAllByRole("option").map((o) => o.textContent);
		expect(options).toEqual(["Release the slot", "3", "4"]);
		await user.selectOptions(within(dialog).getByLabelText("New slot"), "4");
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() => expect(lastPost(calls)).toMatchObject({ path: "/api/phases/B3/slot", body: { slot: 4 } }));
	});

	it("tears down only after the phase code is typed", async () => {
		const calls = mockApi(routes({ "POST /api/phases/B3/teardown": { body: { ok: true, status: "waiting-deps" } } }));
		renderAt("/phase/B3");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Tear down" }));
		const dialog = screen.getByRole("dialog");
		const confirm = within(dialog).getByRole("button", { name: "Confirm" });
		expect(confirm).toBeDisabled();
		await user.type(within(dialog).getByLabelText("Type B3 to confirm"), "B3");
		await user.click(confirm);
		await waitFor(() => expect(lastPost(calls)).toMatchObject({ path: "/api/phases/B3/teardown", body: { confirm: "B3" } }));
	});

	it("pauses, sets status and switches the stack", async () => {
		const calls = mockApi(routes({
			"POST /api/phases/B3/status": { body: { ok: true } },
			"POST /api/phases/B3/stack": { body: { ok: true } },
		}));
		renderAt("/phase/B3");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Pause" }));
		await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Confirm" }));
		await waitFor(() => expect(lastPost(calls)?.body).toEqual({ status: "paused" }));
		await user.click(screen.getByRole("button", { name: "Stack down" }));
		await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Confirm" }));
		await waitFor(() => expect(lastPost(calls)).toMatchObject({ path: "/api/phases/B3/stack", body: { up: false } }));
	});

	it("says so for an unknown phase", async () => {
		mockApi(routes());
		renderAt("/phase/B99");
		expect(await screen.findByText("No phase B99.")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd orchestra/web && npx pnpm@10 vitest run src/pages/PhasePage.test.tsx`
Expected: FAIL — the page renders only its heading.

- [ ] **Step 3: Write the components and the page**

`src/components/SessionLog.tsx`:

```tsx
import { Terminal } from "@xterm/xterm";
import { useEffect, useRef, useState } from "react";
import { useLog } from "@/api/queries";
import { Button } from "@/ui/Button";

/** `claude logs` is the session's raw terminal output: a terminal renders it as it looked. */
export function SessionLog({ who }: { who: string }) {
	const host = useRef<HTMLDivElement>(null);
	const terminal = useRef<Terminal | null>(null);
	const [paused, setPaused] = useState(false);
	const { data } = useLog(who, !paused);

	useEffect(() => {
		if (!host.current) return;
		const term = new Terminal({ cols: 200, rows: 50, disableStdin: true, scrollback: 5000, fontSize: 12 });
		term.open(host.current);
		terminal.current = term;
		return () => term.dispose();
	}, []);

	useEffect(() => {
		if (!terminal.current || data === undefined) return;
		terminal.current.reset();
		terminal.current.write(data.text);
	}, [data]);

	return (
		<div>
			<div className="mb-2 flex items-center justify-between">
				<h2 className="font-semibold">Session output</h2>
				<Button variant="ghost" size="sm" onClick={() => setPaused((p) => !p)}>
					{paused ? "Resume updates" : "Pause updates"}
				</Button>
			</div>
			<div ref={host} className="overflow-auto rounded-md border border-border bg-muted p-2" />
		</div>
	);
}
```

`src/components/SlicesTable.tsx`:

```tsx
import type { Ledger } from "@/api/types";
import { Badge } from "@/ui/Badge";

const PR = /https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/(\d+)/g;

export function SlicesTable({ ledger, code }: { ledger: Ledger; code: string }) {
	const slices = Object.entries(ledger.slices).filter(([, s]) => s.phase === code);
	if (slices.length === 0) return <p className="text-sm text-muted-foreground">No slices yet.</p>;
	return (
		<table className="w-full text-sm">
			<thead className="text-left text-muted-foreground">
				<tr><th className="py-1">Slice</th><th>Status</th><th>Plan</th><th>Requires</th><th>PRs</th><th>Bounces</th></tr>
			</thead>
			<tbody>
				{slices.map(([sid, slice]) => (
					<tr key={sid} className="border-t border-border">
						<td className="py-1 font-medium">{sid}</td>
						<td><Badge tone={slice.status === "merged" ? "success" : "info"}>{slice.status}</Badge></td>
						<td>{slice.plan_number ?? "—"}</td>
						<td className="space-x-2">
							{slice.requires.length === 0 ? "—" : slice.requires.map((need) => (
								<span key={need}>{`${need} ${ledger.slices[need]?.status === "merged" ? "✓" : "✗"}`}</span>
							))}
						</td>
						<td className="space-x-2">
							{[...(slice.prs ?? "").matchAll(PR)].map((match) => (
								<a key={match[0]} className="hover:underline" href={match[0]} target="_blank" rel="noreferrer">{`#${match[1]}`}</a>
							))}
						</td>
						<td>{slice.bounces}</td>
					</tr>
				))}
			</tbody>
		</table>
	);
}
```

`src/components/PhaseControls.tsx`:

```tsx
import { useState } from "react";
import { post } from "@/api/client";
import { freeSlots } from "@/api/queries";
import { type Ledger, PHASE_STATUSES } from "@/api/types";
import { ActionDialog } from "@/ui/ActionDialog";
import { Field, inputClass } from "@/ui/Field";

export function PhaseControls({ code, ledger, stackUp }: { code: string; ledger: Ledger; stackUp: boolean }) {
	const phase = ledger.phases[code];
	const slots = freeSlots(ledger);
	const [slot, setSlot] = useState(0);
	const [status, setStatus] = useState(phase.status);
	const launched = phase.worktree !== null;
	const lower = code.toLowerCase();
	return (
		<div className="flex flex-wrap gap-2">
			{phase.status === "paused" ? (
				<ActionDialog label="Resume" title={`Resume ${code}`} command={`ledger.py phase ${code} --status build`}
					run={() => post(`/api/phases/${code}/status`, { status: "build" })} />
			) : (
				<ActionDialog label="Pause" title={`Pause ${code}`} command={`ledger.py phase ${code} --status paused`}
					run={() => post(`/api/phases/${code}/status`, { status: "paused" })} />
			)}
			<ActionDialog label="Set status" title={`Set ${code}'s status`} command={`ledger.py phase ${code} --status ${status}`}
				run={() => post(`/api/phases/${code}/status`, { status })}>
				<Field label="Status">
					<select className={inputClass} value={status} onChange={(e) => setStatus(e.target.value as typeof status)}>
						{PHASE_STATUSES.map((s) => <option key={s}>{s}</option>)}
					</select>
				</Field>
			</ActionDialog>
			<ActionDialog label="Move slot" title={`Move ${code} to another slot`} disabled={!launched}
				command={slot === 0
					? `just stop (in ${phase.worktree})\nledger.py phase ${code} --slot 0 --status paused`
					: `just stop (in ${phase.worktree})\nledger.py phase ${code} --slot ${slot}\nstream-env.sh ${lower} ${slot} ${phase.worktree}\njust dev-backend`}
				run={() => post(`/api/phases/${code}/slot`, { slot })}>
				<Field label="New slot">
					<select className={inputClass} value={slot} onChange={(e) => setSlot(Number(e.target.value))}>
						<option value={0}>Release the slot</option>
						{slots.map((s) => <option key={s} value={s}>{s}</option>)}
					</select>
				</Field>
			</ActionDialog>
			<ActionDialog label={stackUp ? "Stack down" : "Stack up"} title={`${stackUp ? "Stop" : "Start"} ${code}'s stack`} disabled={!launched}
				command={`just ${stackUp ? "stop" : "dev-backend"} (in ${phase.worktree})`}
				run={() => post(`/api/phases/${code}/stack`, { up: !stackUp })} />
			<ActionDialog label="Tear down" title={`Tear down ${code}`} variant="destructive" disabled={!launched} confirmWord={code}
				warning="Stops the session, removes the stack (volumes too), the worktrees and the phase's local branches."
				command={`claude stop ${phase.session ?? ""}\nteardown-phase.sh ${code}`}
				run={() => post(`/api/phases/${code}/teardown`, { confirm: code })} />
		</div>
	);
}
```

`src/pages/PhasePage.tsx`:

```tsx
import { useParams } from "@tanstack/react-router";
import { useOrchestraState } from "@/api/queries";
import { PhaseControls } from "@/components/PhaseControls";
import { SessionControls } from "@/components/SessionControls";
import { SessionLog } from "@/components/SessionLog";
import { SlicesTable } from "@/components/SlicesTable";
import { Badge } from "@/ui/Badge";
import { Button } from "@/ui/Button";
import { Card } from "@/ui/Card";
import { ErrorBox } from "@/ui/ErrorBox";
import { phaseTone, sessionTone } from "@/ui/tones";

export function PhasePage() {
	const { code } = useParams({ from: "/phase/$code" });
	const { data, error } = useOrchestraState();
	if (error) return <ErrorBox error={error} />;
	if (!data) return <p className="text-sm text-muted-foreground">Loading…</p>;
	const phase = data.ledger.phases[code];
	if (!phase) return <p>{`No phase ${code}.`}</p>;
	const session = data.sessions[code];
	return (
		<div className="space-y-6">
			<header className="space-y-2">
				<h1 className="text-xl font-semibold">{`${code} · ${phase.title}`}</h1>
				<div className="flex flex-wrap items-center gap-2 text-sm">
					<Badge tone={phaseTone[phase.status]}>{phase.status}</Badge>
					<Badge tone={sessionTone[session?.state ?? "none"]}>{`session ${session?.state ?? "none"}`}</Badge>
					<span>{`Slot ${phase.slot ?? "—"}`}</span>
					{phase.branch && <span className="font-mono">{phase.branch}</span>}
					{phase.worktree && (
						<Button variant="ghost" size="sm" onClick={() => navigator.clipboard?.writeText(phase.worktree ?? "")}>
							{`Copy path ${phase.worktree}`}
						</Button>
					)}
				</div>
			</header>
			<Card title="Session"><SessionControls who={code} session={session} /></Card>
			<Card title="Phase"><PhaseControls code={code} ledger={data.ledger} stackUp={data.stacks[code] ?? false} /></Card>
			<Card title="Slices"><SlicesTable ledger={data.ledger} code={code} /></Card>
			<Card><SessionLog who={code} /></Card>
		</div>
	);
}
```

- [ ] **Step 4: Run the tests and checks**

Run: `cd orchestra/web && npx pnpm@10 exec biome check --write . && npx pnpm@10 test && npx pnpm@10 build && npx pnpm@10 lint`
Expected: all pass; `tsc` and Biome clean.

- [ ] **Step 5: Commit**

```bash
git add orchestra/web
git commit -m "feat(orchestra): the phase page, its controls and live log

Co-Authored-By: <implementing model> <noreply@anthropic.com>"
```

---

### Task 8: Web — queue, escalations and coordination

**Files:**
- Modify: `orchestra/web/src/pages/QueuePage.tsx`, `EscalationsPage.tsx`, `CoordinationPage.tsx` (replace the heading-only pages)
- Test: `orchestra/web/src/pages/QueuePage.test.tsx`, `EscalationsPage.test.tsx`, `CoordinationPage.test.tsx`

**Interfaces:**
- Consumes: Task 6's `useOrchestraState`, `post`, `ActionDialog`, `Card`, `Badge`, `Field`, `inputClass`, `ErrorBox`, test helpers.

- [ ] **Step 1: Write the failing tests**

`src/pages/QueuePage.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { lastPost, mockApi } from "@/test/api";
import { makeState } from "@/test/fixtures";
import { renderAt } from "@/test/render";

function state(conductor: "busy" | "none" = "none") {
	return makeState(
		(l) => {
			for (const sid of ["B3a", "B3b", "B8a"]) {
				l.slices[sid] = { phase: sid.slice(0, 2), status: "queued", requires: [], plan_number: null, spec: null, plan: null, prs: null, bounces: 0 };
			}
			l.slices.B3a.status = "in-flight";
			l.slices.B3a.prs = "https://github.com/x/y/pull/9";
			l.in_flight = "B3a";
			l.queue = ["B3b", "B8a"];
		},
		{ sessions: { conductor: { id: conductor === "busy" ? "cd" : null, state: conductor } } },
	);
}

const base = { "GET /api/state": { body: state() }, "GET /api/ci": { body: { master: null, prs: [] } } };

describe("QueuePage", () => {
	it("lists in flight then queued, and moves a slice up", async () => {
		const calls = mockApi({ ...base, "POST /api/queue/reorder": { body: { ok: true } } });
		renderAt("/queue");
		expect(await screen.findByText("In flight: B3a")).toBeInTheDocument();
		const rows = screen.getAllByRole("listitem").map((li) => li.textContent);
		expect(rows[0]).toContain("B3b");
		const user = userEvent.setup();
		await user.click(within(screen.getByRole("listitem", { name: "B8a" })).getByRole("button", { name: "Move up" }));
		await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Confirm" }));
		await waitFor(() => expect(lastPost(calls)).toMatchObject({ path: "/api/queue/reorder", body: { slice: "B8a", direction: "up" } }));
	});

	it("bounces with a reason and marks merged after typing the slice", async () => {
		const calls = mockApi({ ...base, "POST /api/queue/bounce": { body: { ok: true } }, "POST /api/queue/merged": { body: { ok: true } } });
		renderAt("/queue");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Bounce" }));
		let dialog = screen.getByRole("dialog");
		expect(within(dialog).getByRole("button", { name: "Confirm" })).toBeDisabled();
		await user.type(within(dialog).getByLabelText("Reason"), "e2e red");
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() => expect(lastPost(calls)?.body).toEqual({ slice: "B3a", reason: "e2e red" }));

		await user.click(screen.getByRole("button", { name: "Mark merged" }));
		dialog = screen.getByRole("dialog");
		await user.type(within(dialog).getByLabelText("backend head"), "abc1234");
		await user.type(within(dialog).getByLabelText("Type B3a to confirm"), "B3a");
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() => expect(lastPost(calls)?.body).toEqual({ slice: "B3a", heads: { backend: "abc1234" } }));
	});

	it("warns while the conductor is running", async () => {
		mockApi({ ...base, "GET /api/state": { body: state("busy") } });
		renderAt("/queue");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Bounce" }));
		expect(screen.getByRole("dialog")).toHaveTextContent("The conductor is running and may act on this too.");
	});
});
```

`src/pages/EscalationsPage.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { lastPost, mockApi } from "@/test/api";
import { makeState } from "@/test/fixtures";
import { renderAt } from "@/test/render";

describe("EscalationsPage", () => {
	it("lists open ones first and answers one", async () => {
		const state = makeState((l) => {
			l.escalations.push(
				{ id: "E1", phase: "B3", kind: "money", question: "Old?", status: "resolved", answer: "Yes" },
				{ id: "E2", phase: "B3", kind: "money", question: "Live Stripe keys?", status: "open", answer: null },
			);
		});
		const calls = mockApi({
			"GET /api/state": { body: state },
			"GET /api/ci": { body: { master: null, prs: [] } },
			"POST /api/escalations/E2/resolve": { body: { ok: true } },
		});
		renderAt("/escalations");
		const open = await screen.findByRole("region", { name: "Open" });
		expect(within(open).getByText("Live Stripe keys?")).toBeInTheDocument();
		expect(within(screen.getByRole("region", { name: "Resolved" })).getByText("Yes")).toBeInTheDocument();
		const user = userEvent.setup();
		await user.click(within(open).getByRole("button", { name: "Answer" }));
		await user.type(within(screen.getByRole("dialog")).getByLabelText("Your answer"), "Use test keys");
		await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Confirm" }));
		await waitFor(() => expect(lastPost(calls)?.body).toEqual({ answer: "Use test keys" }));
	});
});
```

`src/pages/CoordinationPage.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { lastPost, mockApi } from "@/test/api";
import { makeState } from "@/test/fixtures";
import { renderAt } from "@/test/render";

describe("CoordinationPage", () => {
	it("adds a decision, force-releases a claim and closes a request", async () => {
		const state = makeState((l) => {
			l.shared_decisions.push({ id: "D1", phase: "B2", decision: "R7 dropped", affects: ["B4"], source: "PO-2" });
			l.claims.push({ target: "etqan.catalogue.models", phase: "B3", reason: "price", since: "2026-10-03T10:00:00+00:00" });
			l.requests.push({ id: "R1", from: "B4", app: "scheduling", to_owner: "B2", what: "a field", status: "open" });
		});
		const calls = mockApi({
			"GET /api/state": { body: state },
			"GET /api/ci": { body: { master: null, prs: [] } },
			"POST /api/decisions": { body: { ok: true, id: "D2" } },
			"POST /api/claims/release": { body: { ok: true } },
			"POST /api/requests/R1/done": { body: { ok: true } },
		});
		renderAt("/coordination");
		expect(await screen.findByText("R7 dropped")).toBeInTheDocument();
		expect(screen.getByText("scheduling → B2")).toBeInTheDocument();
		const user = userEvent.setup();

		await user.click(screen.getByRole("button", { name: "Add decision" }));
		let dialog = screen.getByRole("dialog");
		await user.selectOptions(within(dialog).getByLabelText("Phase"), "B3");
		await user.type(within(dialog).getByLabelText("Decision"), "Wallet on Student");
		await user.click(within(dialog).getByRole("checkbox", { name: "B4" }));
		await user.type(within(dialog).getByLabelText("Source"), "audit §2");
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() => expect(lastPost(calls)?.body).toEqual({ phase: "B3", text: "Wallet on Student", affects: ["B4"], source: "audit §2" }));

		await user.click(screen.getByRole("button", { name: "Force release" }));
		dialog = screen.getByRole("dialog");
		await user.type(within(dialog).getByLabelText("Type etqan.catalogue.models to confirm"), "etqan.catalogue.models");
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() => expect(lastPost(calls)?.body).toEqual({ target: "etqan.catalogue.models" }));

		await user.click(screen.getByRole("button", { name: "Mark done" }));
		await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Confirm" }));
		await waitFor(() => expect(lastPost(calls)?.path).toBe("/api/requests/R1/done"));
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd orchestra/web && npx pnpm@10 vitest run src/pages/QueuePage.test.tsx src/pages/EscalationsPage.test.tsx src/pages/CoordinationPage.test.tsx`
Expected: FAIL — the pages are headings only.

- [ ] **Step 3: Write the pages**

`src/pages/QueuePage.tsx`:

```tsx
import { useState } from "react";
import { post } from "@/api/client";
import { useOrchestraState } from "@/api/queries";
import { ActionDialog } from "@/ui/ActionDialog";
import { Card } from "@/ui/Card";
import { ErrorBox } from "@/ui/ErrorBox";
import { Field, inputClass } from "@/ui/Field";

const REPOS = ["backend", "dashboard", "marketing", "meta"];
const SHA = /^[0-9a-f]{7,40}$/;

function Bounce({ sid, warning }: { sid: string; warning?: string }) {
	const [reason, setReason] = useState("");
	return (
		<ActionDialog label="Bounce" title={`Bounce ${sid}`} warning={warning} command={`ledger.py bounce ${sid} --reason "${reason}"`}
			canSubmit={reason.trim() !== ""} run={() => post("/api/queue/bounce", { slice: sid, reason })}>
			<Field label="Reason"><input className={inputClass} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
		</ActionDialog>
	);
}

function MarkMerged({ sid, warning }: { sid: string; warning?: string }) {
	const [heads, setHeads] = useState<Record<string, string>>({});
	const given = Object.fromEntries(Object.entries(heads).filter(([, sha]) => sha !== ""));
	const valid = Object.keys(given).length > 0 && Object.values(given).every((sha) => SHA.test(sha));
	return (
		<ActionDialog label="Mark merged" title={`Mark ${sid} merged`} variant="primary" warning={warning} confirmWord={sid}
			command={`ledger.py merged ${sid} ${Object.entries(given).map(([r, s]) => `--head ${r}=${s}`).join(" ")}`}
			canSubmit={valid} run={() => post("/api/queue/merged", { slice: sid, heads: given })}>
			{REPOS.map((repo) => (
				<Field key={repo} label={`${repo} head`}>
					<input className={inputClass} value={heads[repo] ?? ""} placeholder="merged commit (leave empty if untouched)"
						onChange={(e) => setHeads({ ...heads, [repo]: e.target.value.trim() })} />
				</Field>
			))}
		</ActionDialog>
	);
}

export function QueuePage() {
	const { data, error } = useOrchestraState();
	if (error) return <ErrorBox error={error} />;
	if (!data) return <p className="text-sm text-muted-foreground">Loading…</p>;
	const { ledger } = data;
	const conductor = data.sessions.conductor?.state;
	const warning = conductor === "busy" || conductor === "idle" ? "The conductor is running and may act on this too." : undefined;
	const inFlight = ledger.in_flight;
	return (
		<div className="space-y-6">
			<Card title={`In flight: ${inFlight ?? "—"}`}>
				{inFlight ? (
					<div className="space-y-3 text-sm">
						<p className="text-muted-foreground">{ledger.slices[inFlight]?.prs ?? "No PRs recorded yet."}</p>
						<div className="flex gap-2"><MarkMerged sid={inFlight} warning={warning} /><Bounce sid={inFlight} warning={warning} /></div>
					</div>
				) : (
					<ActionDialog label="Next" title="Put the next slice in flight" warning={warning} command="ledger.py next"
						disabled={ledger.queue.length === 0} run={() => post("/api/queue/next")} />
				)}
			</Card>
			<Card title="Queued">
				{ledger.queue.length === 0 ? (
					<p className="text-sm text-muted-foreground">Nothing queued.</p>
				) : (
					<ol className="space-y-2">
						{ledger.queue.map((sid, index) => (
							<li key={sid} aria-label={sid} className="flex items-center justify-between gap-3 text-sm">
								<span>{`${index + 1}. ${sid}`}</span>
								<span className="flex gap-2">
									<ActionDialog label="Move up" title={`Move ${sid} up`} warning={warning} disabled={index === 0}
										command={`ledger.py reorder ${sid} up`} run={() => post("/api/queue/reorder", { slice: sid, direction: "up" })} />
									<ActionDialog label="Move down" title={`Move ${sid} down`} warning={warning} disabled={index === ledger.queue.length - 1}
										command={`ledger.py reorder ${sid} down`} run={() => post("/api/queue/reorder", { slice: sid, direction: "down" })} />
								</span>
							</li>
						))}
					</ol>
				)}
			</Card>
		</div>
	);
}
```

`src/pages/EscalationsPage.tsx`:

```tsx
import { useState } from "react";
import { post } from "@/api/client";
import { useOrchestraState } from "@/api/queries";
import type { Escalation } from "@/api/types";
import { ActionDialog } from "@/ui/ActionDialog";
import { Badge } from "@/ui/Badge";
import { ErrorBox } from "@/ui/ErrorBox";
import { Field, inputClass } from "@/ui/Field";

function Answer({ escalation }: { escalation: Escalation }) {
	const [answer, setAnswer] = useState("");
	return (
		<ActionDialog label="Answer" title={`Answer ${escalation.id}`} variant="primary" canSubmit={answer.trim() !== ""}
			command={`ledger.py resolve ${escalation.id} "${answer}"`}
			run={() => post(`/api/escalations/${escalation.id}/resolve`, { answer })}>
			<p className="text-sm">{escalation.question}</p>
			<Field label="Your answer">
				<textarea className={inputClass} rows={4} value={answer} onChange={(e) => setAnswer(e.target.value)} />
			</Field>
		</ActionDialog>
	);
}

function Row({ escalation, children }: { escalation: Escalation; children?: React.ReactNode }) {
	return (
		<li className="rounded-md border border-border p-3 text-sm">
			<div className="flex items-center gap-2">
				<span className="font-medium">{escalation.id}</span>
				<Badge>{escalation.phase}</Badge>
				<Badge tone="warning">{escalation.kind}</Badge>
				<span className="ml-auto">{children}</span>
			</div>
			<p className="mt-2">{escalation.question}</p>
			{escalation.answer && <p className="mt-1 text-muted-foreground">{escalation.answer}</p>}
		</li>
	);
}

export function EscalationsPage() {
	const { data, error } = useOrchestraState();
	if (error) return <ErrorBox error={error} />;
	if (!data) return <p className="text-sm text-muted-foreground">Loading…</p>;
	const open = data.ledger.escalations.filter((e) => e.status === "open");
	const resolved = data.ledger.escalations.filter((e) => e.status === "resolved");
	return (
		<div className="space-y-6">
			<section aria-label="Open">
				<h1 className="mb-3 text-xl font-semibold">Open</h1>
				{open.length === 0 ? <p className="text-sm text-muted-foreground">Nothing is waiting for you.</p> : (
					<ul className="space-y-2">{open.map((e) => <Row key={e.id} escalation={e}><Answer escalation={e} /></Row>)}</ul>
				)}
			</section>
			<section aria-label="Resolved">
				<h2 className="mb-3 font-semibold">Resolved</h2>
				<ul className="space-y-2">{resolved.map((e) => <Row key={e.id} escalation={e} />)}</ul>
			</section>
		</div>
	);
}
```

(Import `type ReactNode` from `react` and use it for `children` instead of `React.ReactNode`.)

`src/pages/CoordinationPage.tsx`:

```tsx
import { useState } from "react";
import { post } from "@/api/client";
import { useOrchestraState } from "@/api/queries";
import { ActionDialog } from "@/ui/ActionDialog";
import { Card } from "@/ui/Card";
import { ErrorBox } from "@/ui/ErrorBox";
import { Field, inputClass } from "@/ui/Field";

function AddDecision({ codes }: { codes: string[] }) {
	const [phase, setPhase] = useState(codes[0]);
	const [text, setText] = useState("");
	const [affects, setAffects] = useState<string[]>([]);
	const [source, setSource] = useState("");
	const toggle = (code: string) => setAffects(affects.includes(code) ? affects.filter((c) => c !== code) : [...affects, code]);
	return (
		<ActionDialog label="Add decision" title="Record a shared decision" variant="primary"
			command={`ledger.py decide ${phase} "${text}" --affects ${affects.join(",")} --source "${source}"`}
			canSubmit={text.trim() !== "" && source.trim() !== ""}
			run={() => post("/api/decisions", { phase, text, affects, source })}>
			<Field label="Phase">
				<select className={inputClass} value={phase} onChange={(e) => setPhase(e.target.value)}>
					{codes.map((c) => <option key={c}>{c}</option>)}
				</select>
			</Field>
			<Field label="Decision"><textarea className={inputClass} rows={3} value={text} onChange={(e) => setText(e.target.value)} /></Field>
			<fieldset className="text-sm">
				<legend className="mb-1 font-medium">Affects</legend>
				<div className="flex flex-wrap gap-3">
					{codes.map((c) => (
						<label key={c} className="flex items-center gap-1">
							<input type="checkbox" checked={affects.includes(c)} onChange={() => toggle(c)} />{c}
						</label>
					))}
				</div>
			</fieldset>
			<Field label="Source"><input className={inputClass} value={source} onChange={(e) => setSource(e.target.value)} /></Field>
		</ActionDialog>
	);
}

export function CoordinationPage() {
	const { data, error } = useOrchestraState();
	if (error) return <ErrorBox error={error} />;
	if (!data) return <p className="text-sm text-muted-foreground">Loading…</p>;
	const { ledger } = data;
	const codes = Object.keys(ledger.phases);
	return (
		<div className="grid gap-4 lg:grid-cols-2">
			<Card title="Shared decisions" aside={<AddDecision codes={codes} />}>
				<ul className="space-y-2 text-sm">
					{ledger.shared_decisions.map((d) => (
						<li key={d.id}><span className="font-medium">{`${d.id} · ${d.phase}`}</span> <span>{d.decision}</span>
							<span className="block text-muted-foreground">{`affects ${d.affects.join(", ") || "—"} · ${d.source}`}</span></li>
					))}
				</ul>
			</Card>
			<Card title="Claims">
				<ul className="space-y-2 text-sm">
					{ledger.claims.map((c) => (
						<li key={c.target} className="flex items-center justify-between gap-3">
							<span><span className="font-mono">{c.target}</span>{` · ${c.phase} · ${c.reason} · since ${c.since}`}</span>
							<ActionDialog label="Force release" title={`Release ${c.target}`} variant="destructive" confirmWord={c.target}
								command={`ledger.py release-claim ${c.target}`} run={() => post("/api/claims/release", { target: c.target })} />
						</li>
					))}
				</ul>
			</Card>
			<Card title="Requests">
				<ul className="space-y-2 text-sm">
					{ledger.requests.map((r) => (
						<li key={r.id} className="flex items-center justify-between gap-3">
							<span>{`${r.id} · ${r.from} → ${r.to_owner} · ${r.app}: ${r.what} (${r.status})`}</span>
							{r.status === "open" && (
								<ActionDialog label="Mark done" title={`Mark ${r.id} done`} command={`ledger.py request-done ${r.id}`}
									run={() => post(`/api/requests/${r.id}/done`)} />
							)}
						</li>
					))}
				</ul>
			</Card>
			<Card title="Ownership">
				<ul className="space-y-1 text-sm">
					{Object.entries(ledger.ownership).map(([app, owner]) => <li key={app}>{`${app} → ${owner}`}</li>)}
				</ul>
			</Card>
		</div>
	);
}
```

- [ ] **Step 4: Run every web check, coverage included**

Run: `cd orchestra/web && npx pnpm@10 exec biome check --write . && npx pnpm@10 test:coverage && npx pnpm@10 build && npx pnpm@10 lint`
Expected: all tests pass; coverage lines/statements ≥ 80, branches/functions ≥ 70 (add a focused test for any component below the gate rather than lowering it); build and Biome clean.

- [ ] **Step 5: Commit**

```bash
git add orchestra/web
git commit -m "feat(orchestra): queue, escalations and coordination pages

Co-Authored-By: <implementing model> <noreply@anthropic.com>"
```

---

### Task 9: Running it — `just orchestra`, CI, docs

**Files:**
- Modify: `justfile` (recipes `orchestra`, `orchestra-dev`, `orchestra-test`), `.github/workflows/ci.yml` (job `orchestra`; `infra-scripts` shellcheck list), `CLAUDE.md` (Parallel phases section), `STATE.md` ("Next")
- Create: `orchestra/README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: `just orchestra` (build web if needed, start the server, print the URL), `just orchestra-dev`, `just orchestra-test`.

- [ ] **Step 1: Recipes** — append to `justfile`:

```just
# ─── Orchestra (the parallel-phases dashboard) ────────────────

# Build the web app when its sources changed, then serve http://127.0.0.1:7700
orchestra:
    #!/usr/bin/env bash
    set -euo pipefail
    cd orchestra/web
    [ -d node_modules ] || npx pnpm@10 install --frozen-lockfile
    if [ ! -f dist/index.html ] || [ -n "$(find src index.html package.json -newer dist/index.html -print -quit)" ]; then
      npx pnpm@10 build
    fi
    cd ../server
    exec python3 -m orchestra_server

# Work on the UI: the server plus Vite on :5174 with /api proxied
orchestra-dev:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd orchestra/server && ORCHESTRA_DEV=1 exec python3 -m orchestra_server) &
    trap 'kill %1' EXIT
    cd orchestra/web && npx pnpm@10 dev

# Orchestra's tests: server, web, types and lint
orchestra-test:
    cd orchestra/server && python3 -m unittest discover -s tests -t .
    cd orchestra/web && npx pnpm@10 test:coverage && npx pnpm@10 build && npx pnpm@10 lint
```

Run: `just --list | grep orchestra` → three recipes. Run: `just orchestra-test` → passes.

- [ ] **Step 2: Prove it end to end (manual)**

Run `just orchestra` in one terminal. In a browser open `http://127.0.0.1:7700/`:
- the Overview shows wave 1's four launched phases (B2, B3, B8, B9) in slots 1–4 with `session none`, the conductor card, an empty queue and the latest `master` CI run;
- `curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:7700/api/queue/next` → `403` (no token);
- `curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example:7700' http://127.0.0.1:7700/api/state` → `403`.
Do **not** start sessions or change anything in this check; it reads only. Stop the server with Ctrl-C.

- [ ] **Step 3: CI** — in `.github/workflows/ci.yml` add a job (and add `orchestra` to the final job's `needs:` list next to `infra-scripts`):

```yaml
  orchestra:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: pnpm/action-setup@v6
        with: { version: 10 }
      - uses: actions/setup-node@v7
        with: { node-version: "${{ env.NODE_VERSION }}", cache: pnpm, cache-dependency-path: orchestra/web/pnpm-lock.yaml }
      - name: Configure git auth for private @etqan/tokens
        run: |
          git config --global url."https://x-access-token:${{ secrets.TOKENS_REPO_TOKEN }}@github.com/".insteadOf "https://github.com/"
          git config --global --add url."https://x-access-token:${{ secrets.TOKENS_REPO_TOKEN }}@github.com/".insteadOf "git@github.com:"
          git config --global --add url."https://x-access-token:${{ secrets.TOKENS_REPO_TOKEN }}@github.com/".insteadOf "ssh://git@github.com/"
      - name: Server tests
        working-directory: orchestra/server
        run: python3 -m unittest discover -s tests -t . -v
      - name: Web tests, types, lint and build
        working-directory: orchestra/web
        run: |
          pnpm install --frozen-lockfile
          pnpm test:coverage
          pnpm build
          pnpm lint
```

In the `infra-scripts` job's shellcheck file list, `scripts/orchestration/*.sh scripts/orchestration/tests/*.sh` already covers `start-session.sh` and its test.

- [ ] **Step 4: Docs**

`orchestra/README.md`:

```markdown
# Orchestra

The local dashboard for the parallel phases
(`docs/superpowers/specs/2026-10-03-orchestra-dashboard-design.md`).

- `just orchestra` — build the web app if needed and serve `http://127.0.0.1:7700`.
- `just orchestra-dev` — work on the UI (Vite on :5174, the API proxied).
- `just orchestra-test` — server and web tests, types, lint, build.

It listens on 127.0.0.1 only, refuses other Hosts and Origins, and every change needs the
token the server puts in the page. It keeps no state: the ledger
(`scripts/orchestration/ledger.py`), `claude agents` and git are the truth, so restarting it
loses nothing. Sessions are Claude Code background sessions started by
`scripts/orchestration/start-session.sh`; take one over in a terminal with `claude attach <id>`.
```

`CLAUDE.md`, the "Parallel phases" section: add the sentence `Orchestra (\`just orchestra\`, \`orchestra/\`) shows and controls all of it at http://127.0.0.1:7700; sessions start only through \`scripts/orchestration/start-session.sh\`.`

`STATE.md`, "Next": add `Run \`just orchestra\` and start the conductor and the wave-1 sessions from it (or \`bash scripts/orchestration/start-session.sh <CODE|conductor>\`).` as the first sentence.

- [ ] **Step 5: Commit**

```bash
git add justfile .github/workflows/ci.yml CLAUDE.md STATE.md orchestra/README.md
git commit -m "feat(orchestra): just orchestra, CI and docs

Co-Authored-By: <implementing model> <noreply@anthropic.com>"
```
