# Parallel Phase Orchestration — Design

**Date:** 2026-10-02
**Status:** Approved in brainstorming (sections 1–5), pending written-spec review.
**Scope:** How the rest of the parity roadmap (finishing Plan 13, then phases B2–B11) is built by
several Claude Code sessions at once, each owning one phase, without breaking each other's work.

**Builds on:**
- `docs/superpowers/specs/2026-09-24-parity-roadmap-design.md` — the phases, their scope and dependencies.
- `docs/superpowers/specs/2026-09-30-feature-toggles-design.md` (Plan 13, branch `feat/features`) — every
  new feature registers a switch there, off by default.
- The existing per-plan cycle: brainstorming → spec → writing-plans → subagent-driven development →
  final review → PRs → submodule bump.

## 1. Goal

Run up to four phase orchestrators in parallel, each driving its phase from spec to merged code on its
own, while a conductor keeps `main`/`master` green, resolves the order in which work depends on other
work, and merges one slice at a time. The owner is interrupted only for the escalations in §8.

## 2. Decisions

| # | Decision |
|---|---|
| PO-1 | **Approach A (owner decision):** one conductor session plus one Claude Code session per active phase, each in its own git worktree with its own dev stack. Not a single Workflow run (XL phases do not fit one agent turn) and not cloud sessions (they cannot report back; e2e needs the local Caddy edge). |
| PO-2 | **Checkpoint R7 is dropped (owner decision).** B2 and later phases are designed from `docs/PHASE_1_SYSTEM_AUDIT.md` and `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` alone; anything those do not show is marked `[assumed]` in the spec's decisions table. This supersedes roadmap R7. |
| PO-3 | **Fully autonomous (owner decision).** Orchestrators answer their own brainstorming questions, approve their own specs after an independent spec review, choose subagent-driven execution, and merge through the conductor's queue without owner approval. This overrides the "nothing merges without the user's approval" rule for work that passes every gate in §7. |
| PO-4 | **As many streams as dependencies allow (owner decision), capped at 4** by the machine (28 cores, 31 GB, one dev stack per stream). |
| PO-5 | **Every new feature ships switched off**, registered in Plan 13's feature registry. Merging work that is not yet complete for users is therefore safe. |
| PO-6 | Out of scope: production deploy, monitoring, backups and restore drills. Merged work reaches staging only; production stays an owner action. |

## 3. Roles and topology

### 3.1 Conductor

One session in the main checkout (`etqan_tutor/`, on `master` or `orchestration`). It never writes
product code after wave 0. It:

1. Runs wave 0 (§6.1).
2. Creates each phase's worktrees and branches with `scripts/orchestration/launch-phase.sh <phase>` and
   prints the command that starts the phase session.
3. Allocates stack slots in the ledger. Amended after the final review: a phase allocates its own plan
   numbers (`ledger.py alloc-plan`); the ledger's lock makes that safe.
4. Runs the merge queue (§5).
5. Starts a phase when its dependencies allow (§4.2) and a slot is free.
6. Settles shared-decision conflicts from the audits, or escalates.
7. Is the only writer of `STATE.md`, submodule pointers, CI workflows, Caddyfiles and `orchestration/MERGES.md`.

### 3.2 Phase orchestrator

One session per active phase, working in `../etqan_tutor-wt/<phase>/` — a meta worktree on
`feat/<phase>-<slice>` (for example `feat/b3a-pricing`) with `backend/`, `dashboard/` and `marketing/`
worktrees on the same branch name (repos it does not touch stay on `main`). It runs, for each slice:

1. **Brainstorm alone:** every question is answered from the audits, then earlier specs, then the
   ledger's shared decisions; each answer is recorded with its source (`audit §x`, `spec <file>`,
   `[assumed]`). The phase's first slice also writes the phase spec that splits the phase into slices.
2. **Spec**, reviewed by a fresh spec-reviewer subagent against the audits and shared decisions;
   fixes applied; then self-approved.
3. **Plan** (writing-plans), with a `Requires:` header naming the other phases' slices it needs.
4. **Build** with subagent-driven development (TDD, per-task spec and quality review).
5. **Final review** of the whole slice by a fresh reviewer.
6. **Queue** the slice (§5).

It writes only its own worktrees, `orchestration/phases/<phase>.md`, and its own rows in the ledger.

### 3.3 Dev-stack isolation

- `docker-compose.local.yml`: Caddy's `"80:80"` becomes `"${ETQAN_HTTP_PORT:-80}:80"` (the other ports
  are already overridable).
- Each worktree has a git-ignored `.env.stream` setting `COMPOSE_PROJECT_NAME=etqan-<phase>` and every
  `ETQAN_*_PORT` to its default plus `100 × slot` (conductor slot 0, streams 1–4). `just` loads it.
  Amended in planning: the HTTP edge is `8080 + 100 × slot` (slot 1 → 8180), not `80 + 100 × slot`,
  which would fall below 1024 and clash with common ports.
- The existing `just dev-backend` / `just stop` start and stop that worktree's stack; `just test`,
  `just lint` and `just e2e` use it. Amended after the final review: two recipes were added —
  `just e2e` (the dashboard's Playwright suite against the current checkout's stack, its management
  commands run in that stack's django container; unchanged behaviour in the main checkout) and
  `just stream-down` (§9).
- The Vite and Astro HMR client ports, the emailed academy URLs (`DJANGO_TENANT_URL_TEMPLATE`) and the
  e2e base URLs (`E2E_APP_URL`, `E2E_DEMO_URL`, `E2E_OTHER_URL`, `E2E_BASE_URL`, and `E2E_MAILPIT_URL`
  for the stream's Mailpit) read the port from the same file. It also sets `DATABASE_URL` and
  `CELERY_BROKER_URL` on the stream's Postgres and Redis ports, and `launch-phase.sh` rewrites those two
  lines in the phase's copy of `backend/.env`, so no host-side `manage.py` in a phase reaches the main
  checkout's database.
- Amended in planning: a phase worktree's submodules are `git worktree`s of the main checkout's
  submodules, checked out into the meta worktree's empty submodule directories (verified to work).

## 4. The ledger

### 4.1 Storage and locking

On the meta repo's long-lived `orchestration` branch, checked out in a dedicated worktree
`../etqan_tutor-wt/_ledger/` that every session shares:

- `orchestration/ledger.json` — the source of truth (schema below).
- `orchestration/LEDGER.md` — a human dashboard the conductor regenerates from the JSON.
- `orchestration/phases/<phase>.md` — each phase's running notes, deferred findings and current task.
- `orchestration/MERGES.md` — one paragraph per merge.

Every write goes through `scripts/orchestration/ledger.py`, which takes an exclusive file lock
(`fcntl.flock` on `_ledger/.lock`), applies the edit, re-renders `LEDGER.md` and commits on the
`orchestration` branch. Amended in planning: every session runs on the same machine and shares the one
`_ledger` worktree, so a local lock replaces the pull/push retry; the conductor pushes `orchestration`
to `origin` after each merge as a backup. Amended after the final review: phase notes and `MERGES.md` are
committed by their writers under the same lock (`flock _ledger/.lock`), each commit naming only its
own file, and `ledger.py` commits only `ledger.json`, `LEDGER.md` and `.gitignore`.

`ledger.json` holds:

| Key | Contents |
|---|---|
| `phases` | per phase: `status` (`waiting-deps · spec · plan · build · review · queued · merged · paused`), `slot`, `worktree`, `branch`, `current_slice`, `current_task`, `requires` |
| `slices` | per slice: `id` (e.g. `B3a`), `phase`, `plan_number`, `spec`, `plan`, `requires`, `status` |
| `next_plan_number` | the next free plan number (allocated by the conductor) |
| `ownership` | app → owning phase (§4.3) |
| `claims` | short leases: `{path_or_app, phase, reason, since}` |
| `shared_decisions` | `{id, phase, decision, affects: [phases], source}` |
| `requests` | cross-phase change requests: `{from, to_owner, what, status}` |
| `queue` | ordered slice ids awaiting merge, plus the one `in_flight` |
| `main_heads` | the last merged commit per repo |
| `escalations` | `{id, phase, kind (§8), question, status}` |

### 4.2 Dependencies

Dependencies are at slice level, not phase level:

- A phase may **write its spec** once every phase it depends on has its phase spec recorded in the ledger;
  it designs against those specs.
- A plan's task may **start building** only once every slice in that plan's `Requires:` header is
  `merged`. The orchestrator builds tasks whose requirements are met first; if none are, it marks itself
  `waiting-deps` and the conductor may lend its slot to another phase.

### 4.3 Ownership of existing apps

| Phase | Owns |
|---|---|
| B2 | `scheduling` |
| B3 | `billing`, and pricing fields in `catalogue` |
| B4 | `payroll` |
| B5 | `notifications` |
| B8 | `site` |
| B9 | `identity` (authentication) |

Ownership lasts while the phase is active and passes to the conductor when it is merged. New business
areas go in **new apps** (`etqan.wallet`, `etqan.learning`, `etqan.chat`, …), added to `TENANT_APPS` and
given import-boundary contracts.

## 5. Merge queue

Slices merge one at a time, in queue order:

1. A phase queues a slice when its final review has no open critical or important finding and
   `just test`, `just lint` and the local e2e suite pass.
2. At the head of the queue the conductor marks it `in_flight` and tells the phase to rebase. The phase
   rebases every touched repo onto `main`/`master`, resolves conflicts by §6.2's rules, regenerates
   generated files, and reruns `just test`, `just lint` and e2e.
3. The phase opens the PRs: backend, dashboard, marketing → `main`; meta → `master`, with pointers at the
   PR branches. Meta CI runs (tests, coverage gates, import boundaries, e2e, staging simulation).
4. Green: the conductor merges backend → dashboard → marketing, then merges the meta PR (its pointers
   are the PR branch tips, which the `--merge` merges keep reachable), then bumps `master`'s submodule
   pointers to the merge commits on `main` and pushes `master`, updates `main_heads`, writes the merge
   note, and moves the next item in. Amended after the final review: bumping `master` before merging
   the meta PR makes the PR's gitlinks conflict with `master`'s, and GitHub cannot resolve a submodule
   conflict.
5. Red: the slice leaves the queue with its CI log; the phase fixes and re-queues at the back.
6. `master` CI red after a merge: the conductor reverts that merge in every repo, bumps the pointers, and
   returns the slice. No fixing forward on a red trunk.

Other phases rebase at their next task boundary after `main_heads` moves, and always before queuing.

Amended 2026-10-10 (owner decision: "Merge two slices at a time"): the queue has a second slot. The
ledger keeps `in_flight` (always the older slice, so ledger code that predates the slot still reads it)
and adds `in_flight_extra`; a slice in either is `in-flight`. `ledger.py next --parallel` fills the
second slot only while the first is taken; plain `next` refuses as before, and a third is refused.
`merged` and `bounce` take either; when the older leaves, the extra is promoted to `in_flight`. The
conductor takes a second slice only when the two touch disjoint backend apps, migration apps, dashboard
feature folders and shared list blocks, and do not both migrate one Django app. That phase rebases and
runs only its targeted tests locally; the meta PR's CI is the gate. Whichever goes green first merges;
the other merges `origin/master` into its meta branch, re-points its gitlinks and waits for green again.
A red `master` reverts the most recent merge first. Rules in `scripts/orchestration/CONDUCTOR.md` step 2.

## 6. Waves and conflict rules

### 6.1 Wave 0 — preparation (conductor, in order)

1. Finish **Plan 13** on `feat/features` (Task 1 committed; Task 2 in progress; Tasks 3–11) and merge it.
2. **Stack isolation** (§3.3).
3. **Split the shared lists** (Plan 14, merged before any phase branches). Amended in planning to the
   cheapest form that merges cleanly:
   - **Phase sections:** every shared list that is code (`TENANT_APPS`, `config/api_router.py`, the
     feature registry, the access `RESOURCES`, `seed_academy`'s steps, the platform import contract's
     forbidden list, the end of the import-linter contracts, the dashboard's `NAV_ITEMS` and
     `NavGroup`) gets one marker comment per phase, `── phase B2 ──` … `── phase B11 ──`. A phase adds
     its lines only under its own marker. Two branches inserting under neighbouring markers merge with
     no conflict (verified with git); a test keeps the markers present and in order.
   - **Per-area translation files:** the dashboard's single `common.json` per language becomes one file
     per top-level key (`locales/<lng>/<area>.json`), collected into the same `common` namespace, so
     no `t()` call changes and a new area is a new file. A test keeps `ar` and `en` key-for-key equal.
   - The 28 not-yet-built features are already one line each in the registry; a phase flips its own
     lines in place.
4. **Bootstrap orchestration:** the `orchestration` branch and ledger, `ledger.py`, `launch-phase.sh`,
   and the prompt files every session starts from (`scripts/orchestration/PHASE_PROMPT.md`,
   `scripts/orchestration/CONDUCTOR.md`).

### 6.2 Conflict rules

1. **Models of an app another phase owns:** record a `request`; the owner makes the change. A trivial
   additive field may instead be done by the requester under a `claim`, in one commit, then released.
2. **Migrations:** on a rebase that leaves two leaf migrations in one app, delete your own unmerged
   migration and regenerate it on top of `main`; never `makemigrations --merge`.
3. **Shared lists that stay single files** (`TENANT_APPS`, import-linter contracts): one line or block per
   app, in alphabetical order; conflicts are resolved at rebase.
4. **Generated files** (`routeTree.gen.ts`, generated API types): regenerate, never hand-merge.
5. **Cross-app service calls:** changes to an existing service's signature are additive only (new optional
   parameter or new function). A breaking change is a shared decision carried out by the owner.
6. **Meta files:** only the conductor writes them (§3.1). New e2e journeys go in per-phase spec files
   (`e2e/<phase>-*.spec.ts`).

### 6.3 Schedule

Wave 1 (4 slots): **B2** scheduling depth (XL), **B3** money depth (XL; gateways with test keys only),
**B8** marketing extras (M), **B9** platform extras (M–L).

When a slot frees, the next eligible phase starts, in this priority:

| Priority | Phase | Needs | Note |
|---|---|---|---|
| 1 | B6 learning | B2 | unblocks B10 |
| 2 | B5 communication | B2 | WhatsApp behind a provider interface, stubbed until the owner supplies an account |
| 3 | B4 payroll depth | B2 (session classes), B3 (expenses) | |
| 4 | B7 add-on sales | B3 (gateways) | |
| 5 | B10 AI | B6 | Claude API, `claude-sonnet-5` by default; off by default |
| 6 | B11 apps | B2–B5 APIs | new repo `etqan_tutor_mobile`; starts with a scope spike |

## 7. Quality gates (every slice, no exceptions)

- TDD; backend coverage ≥ 80 %; dashboard lines and statements ≥ 80, branches and functions ≥ 70.
- `lint-imports` and lint clean.
- Per-task spec-compliance and code-quality review; a final whole-slice review by a fresh reviewer.
- e2e through Caddy, and meta CI with the staging simulation.
- Only minor findings may be deferred, each logged in `orchestration/phases/<phase>.md`; any critical or
  important finding blocks queuing.

## 8. Escalations (the only stops for the owner)

Recorded in `ledger.json` and shown in `LEDGER.md`; the phase continues with other work while it waits.

1. Money or external accounts: live payment keys, a WhatsApp provider, app-store accounts, domains.
2. Irreversible data changes: a migration that drops or rewrites data in existing tables.
3. A shared-decision conflict the conductor cannot settle from the audits.
4. The same slice failing the merge queue three times.
5. Anything touching production, or TutorHamster's demo beyond read-only access.
6. A stream paused for making no progress in two queue rounds.

## 9. Recovery and cost

- All state is in git (ledger, phase notes, plan checkboxes), so any session can be killed and
  restarted; a new orchestrator reads its phase file, its plan, and the ledger, and carries on.
- `just stream-down`, run inside a phase worktree, stops that stream's stack and deletes its volumes,
  freeing its slot; it refuses to run in the main checkout. `scripts/orchestration/teardown-phase.sh
  <phase>` retires a merged phase: `just stream-down`, then the submodule worktrees, then the meta
  worktree (both with `git worktree remove --force`), then the phase's local `feat/<phase>…` branches in
  every repo, then a check that the main checkout's submodules still work. A waiting phase's slot is
  lent only explicitly: the conductor stops its stack (`just stop`) and releases the slot
  (`ledger.py phase <code> --slot 0`); the phase gets a slot back before it works again.
- Orchestrators use the session model for specs and reviews, and cheaper subagents for mechanical tasks.
- The conductor pauses a stream with no progress for two queue rounds (§8.6).

## 10. Success criteria

- Wave 0 merged; four phase sessions running in isolated worktrees and stacks.
- `master` CI never stays red past one revert.
- Each phase reaches `merged` slice by slice, with every new feature registered and off by default.
- The owner's only inputs are the §8 escalations and reading `LEDGER.md` / `MERGES.md`.
