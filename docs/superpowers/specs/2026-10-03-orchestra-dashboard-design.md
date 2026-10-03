# Orchestra — the parallel-phases dashboard — Design

**Date:** 2026-10-03
**Status:** Approved in brainstorming (sections 1–3), pending written-spec review.
**Builds on:** `docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md` (the conductor, phase
orchestrators, ledger, merge queue and escalations) and its tooling in `scripts/orchestration/`
(`ledger.py`, `launch-phase.sh`, `teardown-phase.sh`, `stream-env.sh`, `CONDUCTOR.md`, `PHASE_PROMPT.md`).

## 1. Goal

One local page where the owner sees the whole parallel build and controls it: every phase, slot, slice,
the merge queue, escalations, shared decisions, claims, CI, and each Claude session's live output — and
can launch phases, start/stop/restart sessions, answer escalations, move slots, drive the queue and tear
phases down, without five terminals.

## 2. Decisions

| # | Decision |
|---|---|
| OR-1 | **Full control (owner).** Everything the conductor can do through the ledger and scripts is available in the UI, plus session control. Merging PRs stays with the conductor. |
| OR-2 | **React web app + Python standard-library API (owner chose B).** `orchestra/web` uses the dashboard's stack (React 19, Vite 8, TanStack Query 5, Tailwind 4, `@etqan/tokens`, lucide, vitest, Biome); `orchestra/server` is Python 3 standard library only and imports `scripts/orchestration/ledger.py`. |
| OR-3 | **Sessions are Claude Code background sessions** (`claude --bg`), managed with `claude agents --json`, `claude logs`, `claude stop`, `claude respawn`; the owner can take one over with `claude attach <id>`. |
| OR-4 | **Local only.** Binds `127.0.0.1:7700`; checks `Host`/`Origin`; writes need a per-process token. No login, no remote access. |
| OR-5 | **No state of its own.** The ledger, `claude agents` and git are the truth; restarting the server loses nothing. |
| OR-6 | Out of scope: remote access, editing prompts, merging PRs from the UI, production, notifications outside the page. |

## 3. Layout

```
orchestra/
  server/            Python 3 stdlib package `orchestra_server`
    app.py           ThreadingHTTPServer, routing, static files, guards
    ledger_api.py    reads/writes through scripts/orchestration/ledger.py (in-process)
    sessions.py      claude --bg / agents --json / logs / stop / respawn
    commands.py      fixed argv templates for launch/teardown/stream-env/just/gh
    events.py        SSE hub: ledger commits, session changes, log tails
    ci.py            gh run list / gh pr checks, cached 60 s
    tests/           unittest, fake claude/gh/just on PATH, temp ledger repos
  web/               Vite app (base "/"), built to web/dist and served by app.py
```

`just orchestra` builds `web/` (when `dist/` is older than `src/`) and starts the server;
`just orchestra-dev` runs Vite on 5174 with `/api` proxied to the server. A CI job `orchestra` runs the
server tests, the web tests with coverage (lines/statements ≥ 80, branches/functions ≥ 70), `tsc`, Biome
and the build.

## 4. Server

### 4.1 Guards
- Listens only on `127.0.0.1:7700` (port overridable by `ORCHESTRA_PORT`).
- Every request: `Host` must be `127.0.0.1:<port>` or `localhost:<port>`; if `Origin` is present it must
  be `http://` + one of those. Otherwise 403.
- Every non-GET request needs header `X-Orchestra-Token` equal to a random token generated at start and
  embedded in the served `index.html` (`<meta name="orchestra-token">`). Otherwise 403.
- Inputs are validated before any call: phase codes ∈ `ledger.PHASES`; slots 1–4 (0 = release where the
  ledger allows); slice ids `^B\d+[a-z]+$`; branch suffixes as `launch-phase.sh` validates; permission
  modes ∈ {`auto`, `acceptEdits`, `manual`, `plan`, `dontAsk`} (never `bypassPermissions`); model and
  effort from fixed lists. Free text goes only into ledger data or one argv element; nothing is ever run
  through a shell.
- A successful command returns `{ok: true, ...}` (no `exit_code`/`output_tail`); a failed one is a 500
  carrying `{ok: false, exit_code, output_tail}` (last 50 lines); a `LedgerError` returns 409 with its
  message (amended after final review: ships as the shape above, not `{ok, exit_code, output_tail}` on
  every response).

### 4.2 API (all JSON under `/api`)

| Method & path | Does |
|---|---|
| `GET /api/state` | ledger JSON + reconciled sessions + eligible phases + queue + open escalations count |
| `GET /api/ci` | latest `master` CI run and checks of open PRs named in the ledger (cached 60 s) |
| `GET /api/events` | SSE: `ledger` (on a new ledger commit), `sessions` (on a change in `claude agents --json`, polled 5 s). Logs are not pushed: the phase page polls `GET /api/phases/<code>/log` every 3 s while open (amended in planning — one viewer, same effect, far simpler). |
| `GET /api/phases/<code>/log` | `claude logs <id>` tail, the latest ≤200 000 characters (amended after final review: no `?lines` param) |
| `POST /api/phases/<code>/launch` `{suffix, slot}` | `launch-phase.sh`, ledger `phase --status spec --slot --worktree --branch`, then start its session |
| `POST /api/phases/<code>/session/start` `{mode, model?, effort?}` | `start-session.sh <code>` (§4.3) and record the id |
| `POST /api/phases/<code>/session/stop` · `/restart` | `claude stop` · `claude respawn` (or a fresh start when the session is gone) |
| `POST /api/phases/<code>/status` `{status}` | ledger `phase --status` (pause/resume included) |
| `POST /api/phases/<code>/slot` `{slot}` | the lending flow: `just stop` in the worktree → ledger set slot (0 = release, status `paused`, and stop there) → else `stream-env.sh` for the new slot → `just dev-backend` (amended after final review: the ledger write for the new slot happens before `stream-env.sh`, not after) |
| `POST /api/phases/<code>/stack` `{up: bool}` | `just dev-backend` / `just stop` in the worktree |
| `POST /api/phases/<code>/teardown` `{confirm: "<CODE>"}` | stop session, `teardown-phase.sh`, ledger `--status merged` if every slice is merged, else `--status waiting-deps --slot 0 --worktree none --branch none --session none` (slot released, worktree cleared, so `eligible` offers it for launch again) |
| `POST /api/conductor/session/start|stop|restart` | the conductor's session, prompt `CONDUCTOR.md` |
| `POST /api/queue/next` · `/bounce` `{slice, reason}` · `/merged` `{slice, heads}` · `/reorder` `{slice, direction}` | ledger `next` / `bounce` / `merged` / `reorder` |
| `POST /api/escalations/<id>/resolve` `{answer}` | ledger `resolve` |
| `POST /api/decisions` `{phase, text, affects, source}` | ledger `decide` |
| `POST /api/claims/release` `{target}` | ledger `release-claim` (forced) |
| `POST /api/requests/<id>/done` | ledger `request-done` |
| `GET /*` | `web/dist` files; unknown paths serve `index.html` |

Ledger writes from the server use the commit message prefix `ledger (orchestra): `.

### 4.3 Sessions
- The ledger gains `phases.<code>.session` (background id or null) and top-level `conductor_session`;
  `ledger.py phase <code> --session <id|none>` and `ledger.py conductor --session <id|none>` set them.
- `scripts/orchestration/start-session.sh <PHASE|conductor> [--mode m] [--model x] [--effort e]` is the
  one way to start a session, used by the server and by the conductor: from the phase worktree (or the main
  checkout for the conductor) it runs `claude --bg --name etqan-<code> --permission-mode <mode> [--model]
  [--effort] "<prompt>"` with `PHASE_PROMPT.md` (placeholders filled) or `CONDUCTOR.md`, prints the id,
  and records it in the ledger.
- Reconciliation states, as shown (amended after final review — ships as `busy`/`idle`/`exited`/`gone`/
  `none`, not running/idle/waiting/exited): a recorded id present in `claude agents --json` → `busy` or
  `idle`; present but ended → `exited`; no longer listed at all (the agent fell out of `claude agents`'
  window) → `gone`; no id ever recorded → `none`. A running `etqan-<code>` session with no recorded id is
  adopted (recorded) and shown.
- `CONDUCTOR.md` step 1 changes: the conductor starts phase sessions with `start-session.sh` instead of
  handing the owner commands.
- Restart (amended after final review): when the recorded or an adopted same-named session is still live,
  it is respawned (`claude respawn <id>`), keeping its own mode. Start and restart both refuse to create a
  second live `etqan-<who>` session. Restarting an exited session that still has a `sessionId` resumes it
  with `claude --bg --resume <sessionId> "<continue prompt>"` and no other flags — passing `--name` or
  `--permission-mode` alongside `--resume` does not resume it; it starts an idle copy under a new id
  (confirmed against the real CLI) — otherwise it starts fresh.

### 4.4 Ledger additions (in `ledger.py`, with tests)
`reorder <slice> up|down` (within the queue; not the in-flight slice), `request-done <id>`,
`release-claim <target>` (any holder), `phase --session`, `conductor --session`, and `phase --worktree none` / `--branch none` / `--session none` clearing a field (today a missing value means "leave as is").

## 5. Web

Routes (TanStack Router): `/` Overview, `/phase/:code`, `/queue`, `/escalations`, `/coordination`.
Data with TanStack Query; the SSE stream invalidates `state` and `ci`; the open phase page polls its log every 3 s.

- **Overview:** four slot cards (phase, title, status, slice, task, session state, stack up/down, link to the
  phase page — amended in planning: no last log line or per-card age; the live log is on the phase page); a
  "Without a slot" card listing any launched, unmerged phase that currently holds no slot (released, or lent
  out per CONDUCTOR.md), each linked to its phase page, hidden when there is none (amended after final
  review: the slot cards alone cannot reach such a phase); the conductor card (state, Start/Stop/Restart,
  a "Show output" toggle that renders its live log, polling only while shown — amended after final review);
  merge-queue strip (in flight with PR checks, then queued); open-escalations badge; CI (`master` run, open
  PR checks); eligible phases with **Launch** (suffix and free slot pre-filled, editable).
- **Phase page:** header (status, slot, branch, worktree path with copy); slices table (status, plan,
  requirements with met ✓/✗, PRs, bounces); live log (auto-scroll, pause); session controls (Start with
  mode/model/effort, Stop, Restart, copy `claude attach <id>`); phase controls (Pause/Resume, Release slot,
  Move to slot N, status); stack up/down; Teardown (type the phase code).
- **Queue:** in flight and queued; Next, Bounce (reason required), Mark merged (heads typed by hand —
  amended after final review: merging is the conductor's job, and pre-filling them would need a fetch from
  a read route; typed confirm), Move up/down. While the conductor's session is running, a warning that it
  may act too.
- **Escalations:** open first; Answer (text → resolve); resolved history.
- **Coordination:** shared decisions (add), claims (force-release, typed confirm), requests (mark done),
  ownership.
- Every changing action opens a confirm dialog naming the exact command or ledger change; errors show the
  server's message and output tail verbatim. English UI; works at laptop width (no phone layout needed).

## 6. Testing
- Server (`unittest`): guards (bad Host/Origin/token → 403); validation (bad codes/slots/modes → 400);
  each route against a temp ledger repo and fake `claude`/`gh`/`just`/scripts on `PATH` recording argv;
  reconciliation states; SSE emits `ledger` after a ledger commit and `sessions` after a change; teardown
  confirm mismatch refused; no argv ever passes through a shell (fakes assert exact argv).
- Ledger additions: unit tests beside the existing 38.
- `start-session.sh`: bash test with a fake `claude` (prompt placeholders filled, id recorded).
- Web (vitest + Testing Library, fetch mocked): each screen renders state; each action sends the right
  request with the token and shows confirm and errors; SSE invalidation.

## 7. Success criteria
- `just orchestra` opens a page that shows wave 1 as it runs and controls every phase and the conductor.
- No action can run outside loopback, without the token, or through a shell.
- The conductor and the page can both act; the ledger serialises them and the history shows who did what.
