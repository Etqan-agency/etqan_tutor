# Plan 31 — Archives and the Simplified Sessions View (slice B2d) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B2a, B2b, B2c (B2's own; no other phase's slice).
**Slice:** B2d · **Phase spec:** docs/superpowers/specs/2026-10-03-b2-scheduling-depth-design.md

**Goal:** The office can archive ended subscriptions (with their sessions) and finished sessions — they leave the office's everyday lists and the Today board, keep counting everywhere, show on their own archive screens and come back with one click — and gets a compact, phone-first simplified sessions view; three per-academy switches, off by default.

**Architecture:**
- **Data.** Four nullable / defaulted columns (spec §3): `Subscription.archived_at`, `Subscription.archived_by`, `Session.archived_at`, `Session.archived_with_subscription`; `SessionActivity.Action` gains four values. One additive migration `0009_archives`. No data rewritten.
- **Rules** (`services/rules.py`). The shared predicates every caller needs without import circles: the switch names, `ENDED`, `refuse_if_archived`, `refuse_if_session_archived`, `due_sessions`, `archivable`, `ARCHIVED_MODES`, `filter_subscriptions` (moved out of `api/views.py`, spec §4.4) and `filter_sessions(archived=…)`. `subscriptions_queryset()` annotates `has_due_sessions` and joins `archived_by`.
- **Services** (new `services/archive.py`). `archive_subscription`, `restore_subscription` (lock the subscription, then its sessions; cascade by one `.update()` logged with `record_many`), `archive_session`, `unarchive_session` (lock the session; `track` then refuse), `archive_sessions`, `unarchive_sessions` (≤ 200 ids locked up front, one savepoint each).
- **Refusals** (D-7). `refuse_if_archived` after the subscription's lock in `renew_subscription`, the three hand-added session services and the three slot services; `postpone_session` refuses an archived session; `can_postpone` is false for one. Each only while its switch is on.
- **Activity log** (B2c). `archived_at` joins `LOGGED_FIELDS`; `archive` / `unarchive` are revertible (each other's inverse); the cascade is `subscription_archived` / `subscription_restored` through `record_many` (not revertible); each new action shows only while its switch is on.
- **Reads.** The office's default lists (subscriptions, sessions, their CSVs) hide archived rows while the entity's switch is on; `archived=exclude|only|include` (and `archived_from` / `archived_to`) is the office's alone, 404 otherwise or while off. The Today board drops a row whose session is archived. Payloads add `archived_at` (+ `can_archive`, `archived_by` for subscriptions; `ends_at` for sessions), office only, while the switch is on.
- **API.** `POST|DELETE subscriptions/<id>/archive/`, `POST sessions/archive/`, `POST sessions/unarchive/`; non-office 404 before the code check.
- **Dashboard.** Archive and Restore actions, archive screens for subscriptions and sessions (the list components in an `archive` mode), banners on an archived subscription and session, an "Archived" badge in a subscription's sessions panel, the invoice form's picker including archived subscriptions, and the simplified view `/app/scheduling/sessions/simple`. Strings in a new area file `archives.json`.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), i18next, Radix UI; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-03-b2d-archives-design.md` (slice B2d of the phase spec). It builds on Plan 4 (subscription statuses, `delete_subscription`, renewal, the Today board), Plan 5 (sessions list, bulk), Plan 12a (codes and verbs), Plan 13 (switches, FT-4), B2a (`…/2026-10-03-b2a-session-classes-design.md`, Plan 17: session classes, lock order), B2b (Plan 21: postponement, board rows), B2c (`…/2026-10-03-b2c-activity-log-design.md`, Plan 25: `track`, `record_many`, `LOGGED_FIELDS`, the inverse table). Ledger decision **D14**: archived rows are the same rows; other apps never filter on `archived_at`. Where this plan fills a gap in the spec, the Decisions below say so.

## Global Constraints

**Repos and branches**
- Meta worktree: `/home/abdulkhalek/Projects/etqan_tutor-wt/b2` (`$W`). Meta, `backend/` and `dashboard/` are on `feat/b2d-archives`, created by the controller off `origin/master` (meta) and `origin/main` (submodules) after B2c merged. `marketing/` is untouched.
- Commit in the submodule that owns the file (`git -C $W/backend …`, `git -C $W/dashboard …`). Never run `git submodule update` (or any writing `git submodule` subcommand) in this worktree.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` (this overrides any attribution line a harness suggests).
- Never edit `STATE.md`, CI workflows, Caddyfiles, or meta's submodule pointers.

**Commands (the slot-1 stack must be up: `just dev-backend`)**
- From `$W`, load the stream's environment first: `cd /home/abdulkhalek/Projects/etqan_tutor-wt/b2; set -a; . ./.env.stream; set +a`. Then run docker compose **directly** (a `$DC` variable does not word-split in zsh). `…` below stands for `docker compose -f docker-compose.local.yml`:
  - Backend tests: `… exec -T django pytest -q <paths>` (add `--create-db` once after the migration).
  - Backend format: `… exec -T django ruff check --fix .` then `… exec -T django ruff format .`
  - Backend verify: `… exec -T django ruff check .`, `… exec -T django ruff format --check .`, `… exec -T django lint-imports`, `… exec -T django pytest -q --cov=etqan`
  - Migration: `… exec -T django python manage.py makemigrations scheduling --name archives` (Task 1). Trunk's scheduling leaf after B2c is `0008_session_activity`, so this is `0009_archives`.
  - Dashboard tests: `… exec -T dashboard pnpm exec vitest run <paths>`; verify: `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`, `… exec -T dashboard pnpm test:coverage`. Format first with `… exec -T dashboard pnpm exec biome check --write src e2e`.
  - New route files: regenerate `src/routeTree.gen.ts` with `… exec -T dashboard pnpm exec vite build` before `tsc` (generated: never hand-edit, never hand-merge).
  - Seeding this stream: `just _stack-manage migrate_schemas`, `just _stack-manage seed_dev`. E2E only through `just e2e …` (it runs `--workers=1 --retries=1`).
  - Slice gates: `just test` (its backend recipe blanks `DJANGO_EMAIL_SUBJECT_PREFIX`), `just lint`, `just e2e`.
- There is no host `.venv` or `node_modules`; never run `manage.py`, `migrate` or pytest against any other database.
- Ruff selects `PL`, `FBT`, `DTZ`, `BLE`, `ERA`, `SLF`, `C901` (10), `E501` (88). Long keyword-only signatures carry `# noqa: PLR0913 -- keyword-only; mirrors the list's query (spec §6.1)`. Imports are one per line (`from x import a` / `from x import b`), as every trunk file does.
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`: semantic colour tokens only (`bg-secondary`, `text-muted-foreground`, `border-border`, `text-primary-text` …), never a literal colour — the checker also rejects `"#123456"`-like literals inside tests. Biome rejects `role="group"` on a div (use `<fieldset>` + `<legend>`) and an implicit-`any` `let` (write `let body: ReactNode;`).

**TDD and reports (lessons from Plans 21 and 25)**
- Every task runs its new tests before the implementation and keeps the failing output (RED) for the report, then the passing output (GREEN). A report without RED evidence is sent back.
- Trunk helper names: `identity_services.link_guardian(parent, student)` (positional Users), the root `staff_for(*codes)` fixture (an `APIClient`; the user is `client.user`), `api_for("admin")`, `set_features(**switches)` (also `academy=`), `tenants.other`; scheduling's conftest: `clock` (`clock.set(datetime)`), `world`, `subscribe(**overrides)`, `make_admin`, `make_teacher`, `make_student`, `hand_session(sub, *, occurs_on, start=time(10, 0), **fields)`, `two_slots()`, `build_world()`, `subscription_for(world, **o)`, `until_pk_exceeds`, `as_user(user)`, `supervisor(name)`, `postponed(sub, to=, on=)`. `rules.acts_as_office` exists: never re-define it. Shared test helpers go once in scheduling's conftest (Plan 25 ruling Q4), never copied between files.
- `etqan/platform/tests/test_features.py`'s `BUILT` dict lists every built switch **in registry order**: `subscription_archive` and `session_archive` are flipped **in place** in the registry (they sit after `contracts`, before `# ── phase B2 ──`), so their `BUILT` keys go right after `"contracts": False` (after whichever key is the last built one before them in registry order at build time); `simplified_sessions` goes under the B2 marker after `"activity_log": False`. Same commit.
- `etqan/access/tests/test_routes.py`: every new route joins `ROUTES` and `FEATURES`; `FEATURE_WORDS` gets the words that catch new session archive routes. The registry's `IN_USE` must equal the codes the routes declare (`subscription.restore`, `session.restore` become in use).
- Non-office callers get 404 from `OfficeOr404` (B2c's, in `api/activity_views.py`) listed **before** `HasCode`; a switched-off feature answers 404 **after** the permission check (`FeatureOn` last).
- A list or read that renders rows carries a query-count test (same count for 1 and 5 rows).
- Scheduling tests may not import `etqan.identity.models` (import-linter); go through `identity_services`.
- The dashboard never restates a server rule: what may be archived is the server's `can_archive`; what may be postponed is `can_postpone`; attendance closes by the one `attendanceClosed` helper the existing controls use; a refused write shows the translated 409 code.
- Outside the app shell every switch counts as on and every code is held (`useHasFeature` / `useCan` allow all): a test rendering a touched page must mock every API call that page now makes.

**Coverage and dev data**
- Gates: backend ≥ 80 %; dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`; `demo` admin `admin@demo.test`.

**Orchestration rules**
- Shared lists: lines only under `── phase B2 ──` (feature registry for `simplified_sessions`, `test_features.BUILT`'s B2 block, `seed_dev`'s B2 block calls `etqan/tenants/seeds/b2.py`); the two archive lines are B2's own registry lines, flipped in place (phase spec §4). Widening `in_use` on the `subscription` and `session` resource lines is a B2 edit to B2-owned resources (phase spec §4).
- One file outside `etqan.scheduling` / the scheduling dashboard feature is touched: `dashboard/src/features/billing/InvoiceForm.tsx` (+ its test), one line the spec requires (§4.4, §7). B3 owns billing: Task 12 takes a ledger claim before the edit and releases it after the commit.
- New translation area: `dashboard/src/locales/{en,ar}/archives.json`, holding its keys directly (the catalogue wraps the file under `archives`). `errors.scheduling` codes and `sessionActivity.json` are B2's and edited in place. No `es` file (ledger D22: later areas need none).
- New e2e spec: `dashboard/e2e/b2-archive.spec.ts`, owning its stamped data, safe to run twice on one database, no faked time.
- Migrations are additive (phase B2-16). Never `makemigrations --merge`; on a clash after a rebase, delete this plan's migration and regenerate it.
- Service signature changes are additive only (keyword arguments with defaults that keep today's behaviour).

**Lock order (binding, from Plan 4 / B2a)**
- Subscriptions before sessions; sessions in pk order. `archive_subscription` / `restore_subscription` lock the subscription, then its sessions (one `FOR UPDATE … ORDER BY id`). `archive_session` / `unarchive_session` lock only the session (B2a's `lock`); `unarchive_session` reads the subscription's `archived_at` unlocked, after the session lock — a session write never locks a subscription after a session. The bulk forms lock every requested row up front in pk order, then call the single service per row in its own savepoint.

**API and data rules (spec values verbatim)**
- 409 bodies `{detail, code}`. New codes: `scheduling.archived`, `scheduling.not_archived`, `scheduling.has_upcoming_sessions`; existing `scheduling.not_allowed_in_status` for a wrong status and a still-to-come session.
- Switches (all built, off by default, group `teaching`): `subscription_archive`, `session_archive`, `simplified_sessions`.
- Routes: `POST subscriptions/<id>/archive/` (code `subscription.delete`), `DELETE subscriptions/<id>/archive/` (code `subscription.restore`) — feature `subscription_archive`, answer the subscription detail. `POST sessions/archive/` (code `session.delete`), `POST sessions/unarchive/` (code `session.restore`) — feature `session_archive`, body `{ids}` (1–200), answer `{done: [id], skipped: [{id, code}]}`. Teachers, students and parents: 404.
- `archived`: `exclude` · `only` · `include`. Office default: `exclude` while the entity's switch is on, else `include`. Everyone else: `include`.
- `archived_at` is an ISO UTC instant or null; it and every archive field are left out of payloads while the entity's switch is off (FT-4).

### Decisions this plan makes where the spec is silent or leaves a choice

- **D1 — Shared predicates live in `rules.py`; the six archive services in a new `services/archive.py`.** `subscriptions.py`, `manual.py`, `postpone.py` and `board.py` already import `rules`, so `refuse_if_archived`, `refuse_if_session_archived`, `due_sessions`, `archivable`, `filter_subscriptions` and the switch names go there and no module imports in a circle. `archive.py` imports `rules`, `activity` and `attendance` (for `lock`, `has_started`, `BulkResult`, `MAX_BULK`); `revert.py` imports `archive` for the inverses.
- **D2 — The dashboard learns what may be archived from `can_archive`.** "Ended, not archived, nothing due" is a server rule; the subscription payload (office, `subscription_archive` on) carries `can_archive`. It reads a `has_due_sessions` `Exists` annotation that `subscriptions_queryset()` adds, so a list costs no query per row. Sessions get no such flag: their archive is a bulk action whose refusals come back as skip codes, and the banner's Restore shows the refusal as a translated toast.
- **D3 — The slot services take the subscription's row lock.** Spec §4.1 calls `refuse_if_archived` "after the subscription's lock" in `add_slots`, `update_slot` and `delete_slot`, which lock nothing today. Each now locks the subscription row first (`_lock_unarchived`), then refuses; Plan 4's order (subscription, then sessions) holds, and generation re-locks the same row in the same transaction. `delete_slot` becomes `@transaction.atomic`.
- **D4 — The new actions are shown by action, not by field.** `archived_at` is not in `FIELD_FEATURES` (always a visible field); `activity.ACTION_FEATURES` maps `archive` / `unarchive` → `session_archive` and `subscription_archived` / `subscription_restored` → `subscription_archive`, and the read leaves out, in SQL before the 200 cap, the entries whose action's switch is off. A revert of `archive` / `unarchive` also needs `session_archive` on (its inverse's switch) and the inverse's code (`session.restore` / `session.delete`, spec §4.3).
- **D5 — The archive parameters.** `archived`, `archived_from` and `archived_to` are the archive's parameters: any of them from a non-office caller is 404, and while the switch is off 404 `{"detail": FEATURE_OFF}`; an unknown `archived` value is 400 on `archived`. `created_from` / `created_to` are plain filters anyone may send (they reveal nothing). All four dates are academy dates, turned into a UTC range on the instant (`[day 00:00, next day 00:00)` on the academy's clock). `archived=only` lists subscriptions newest-archived first; sessions keep the list's order.
- **D6 — Session `ends_at` and `archived_at` join the payload and the CSV only while `session_archive` is on** (office only). The CSV already has `kind`; spec §6.1's other two columns follow the switch, so the CSV and the payload are byte-for-byte today's while the switch is off (FT-4) and every existing CSV test holds.
- **D7 — Bulk restore of subscriptions is one `DELETE …/archive/` per chosen row**, sent together (`Promise.allSettled`: each locks only its own subscription), then one summary toast ("Restored 2 of 3." plus the first refusal). Spec §6 defines no bulk subscription route, so none is added.
- **D8 — The session page's Restore uses `POST sessions/unarchive/` with one id** (spec §6 has no single-session route); a skipped id shows its translated code as a toast.
- **D9 — Seeds own their data.** Demo has no expired subscription and its live ones feed other specs, so `seed_archives` creates its own past subscription (Aisha Omar · Tajweed · Ustadh Bilal · "Two-week intensive", starting 45 days ago, Monday and Thursday 19:00), generates its past sessions, expires it through `run_lifecycle` (the hourly job's own step), cancels its first session and archives that one **on its own**, then archives the subscription — so restoring the subscription leaves that session archived (D-4 shown in the data). It acts as the system (`by=None`), as B2a's and B2b's seeds do, so B2c's seed marker (the demo admin's entries) is untouched. The marker is "a Tajweed subscription of Aisha Omar exists"; the whole step is one transaction; it runs only while both archive switches are on. Four earlier seed tests that count every scheduling row (three in `test_seed_dev.py`, one in `test_seed_b2.py`) read only the everyday (not archived) rows: the archive's own data is exactly what they should not count. No other app's code filters on `archived_at` (ledger D14).
- **D10 — The dashboard hides Renew on an archived subscription** the way it already hides it on a cancelled one (by the row's own state); the server refuses with `scheduling.archived` anyway.
- **D11 — The simplified view.** An infinite query over the existing sessions list (`from` = `to` = the chosen academy day, default today), "More" loads the next page; Present / Absent are two buttons per row that call the existing attendance route and close by `attendanceClosed(session)`, extracted from `AttendanceControls` (no rule copied), plus the student's attendance closing on `at_disposal` and without `attendance.update`, exactly as the controls do.
- **D12 — Non-office `archived=` is 404** (spec §5's table), although spec §4.4's aside says "as `?format=csv` does" and the CSV answers 403. §5 is the access table, so it wins; the CSV keeps its 403.
- **D13 — `_lock_live` leaves archived subscriptions out** (D-3 "never generates"). An archived subscription is always ended, so this changes nothing today; it is a guard, pinned by one test.
- **D14 — The invoice form asks `archived=include` only while `subscription_archive` is on** (with the switch off the parameter 404s and every subscription is already included).
- **D15 — "A future scheduled session" is `scheduled` with `has_started` false** (B2a's start-time gate: a session starting this instant counts as past).
- **D16 — Messages.** `scheduling.archived`: "This is archived. Restore it first."; `scheduling.not_archived`: "This isn't archived."; `scheduling.has_upcoming_sessions`: "A session of this subscription is still to come. Cancel or delete it first."; a still-to-come session: "A session still to come can't be archived." (`scheduling.not_allowed_in_status`).

## Review Focus

- **A cancelled subscription that still has a future make-up, extra or postponed session.** Expected: Archive is refused with 409 `scheduling.has_upcoming_sessions` and nothing changes; once those sessions are cancelled or deleted it archives. Test: Task 3 `test_a_session_still_to_come_blocks_the_archive` (parametrised over the three kinds).
- **Restoring a subscription whose sessions were partly archived before it.** Expected: only the sessions archived *with* it come back; one archived on its own stays archived. Test: Task 3 `test_restore_brings_back_only_what_came_with_it`.
- **Switching an archive off after archiving.** Expected: archived rows are back in the default lists and the Today board, `archived=` and the routes 404, renewal and slot edits work again, `archived_at` is gone from payloads; switching it on again hides them again. Tests: Task 5 `test_the_refusals_stop_while_the_switch_is_off`, Task 7 `test_switching_the_archive_off_shows_everything_again`, Task 6 `test_an_archived_session_shows_again_while_the_switch_is_off`.
- **Restoring a session whose subscription is archived.** Expected: 409 `scheduling.archived` while `subscription_archive` is on (restore the subscription first); allowed, and `archived_with_subscription` cleared, while it is off. Test: Task 4 `test_unarchive_under_an_archived_subscription`.
- **A slot whose session today is archived.** Expected: the Today board leaves the whole row out (no "missing" row inviting a regeneration), for B2b's postponed and session-only rows too. Test: Task 6 `test_a_slot_whose_session_is_archived_is_left_out`.

---

## File Structure

```
backend/
  etqan/platform/features.py                       two archive lines flipped in place; simplified_sessions
                                                   under ── phase B2 ── (Task 1)
  etqan/platform/tests/test_features.py            BUILT (Task 1)
  etqan/access/registry.py                         subscription / session in_use + restore (Task 8)
  etqan/scheduling/
    models.py                                       archive columns; four Action values (Task 1)
    migrations/0009_archives.py                     generated (Task 1)
    services/rules.py                               switch names, ENDED, ARCHIVED_MODES, refuse_if_archived,
                                                    refuse_if_session_archived, due_sessions, archivable,
                                                    filter_subscriptions, filter_sessions(archived…),
                                                    subscriptions_queryset annotations (Task 2)
    services/generation.py                          _lock_live leaves archived out (Task 2)
    services/activity.py                            archived_at logged; ACTION_FEATURES, hidden_actions (Task 3)
    services/archive.py                             NEW: archive_subscription, restore_subscription (Task 3);
                                                    archive_session, unarchive_session, archive_sessions,
                                                    unarchive_sessions (Task 4)
    services/revert.py activity_feed.py             inverses; hidden actions left out (Task 4)
    services/subscriptions.py manual.py             refuse_if_archived callers; _lock_unarchived (Task 5)
    services/postpone.py                            archived refusal; can_postpone (Task 5)
    services/board.py                               archived rows left out (Task 6)
    services/__init__.py                            exports (Tasks 2–4)
    api/archived.py                                 NEW: archived_mode (Task 7)
    api/views.py session_views.py payloads.py       archive param, filters, payload fields, CSV (Task 7)
    api/serializers.py                              SessionFilterInput dates; ArchiveInput (Tasks 7, 8)
    api/archive_views.py urls.py                    NEW routes (Task 8)
    tests/conftest.py                               ARCHIVED_AT, stamp_archived, archives_on (Task 2);
                                                    the ended fixture (Task 3)
    tests/test_archive_*.py test_api_archive_*.py   NEW (Tasks 1–8)
  etqan/access/tests/test_routes.py                 ROUTES, FEATURES, FEATURE_WORDS (Task 8)
  etqan/tenants/seeds/b2.py tests/test_seed_b2.py   seed_archives (Task 9)
  etqan/tenants/tests/test_seed_dev.py              three tests read the everyday rows (Task 9)
  etqan/tenants/management/commands/seed_dev.py     one call in the B2 block (Task 9)
dashboard/
  src/features/identity/schemas.ts                  FeatureCode + 3 codes (Task 10)
  src/features/scheduling/
    schemas.ts api.ts queries.ts (+api.test.ts)     archive fields, routes, useSessionPages (Task 10)
    activityFormat.ts                               archived_at is an instant (Task 10)
    ArchiveActions.tsx (+test)                      NEW: ArchiveSubscriptionButton, ArchivedSubscriptionBanner,
                                                    ArchivedSessionBanner, ArchivedBadge (Tasks 11–13)
    SubscriptionsList.tsx (+test)                   header link, row Archive, archive mode (Task 11)
    SubscriptionDetail.tsx SubscriptionActions.tsx  banner, Archive action, Renew hidden (Task 12)
    SessionsPanel.tsx (+test)                       Archived badge (Task 12)
    SessionsList.tsx SessionBulkBar.tsx (+tests)    header links, bulk Archive, archive mode (Task 13)
    SessionPage.tsx (+test)                         archived banner (Task 13)
    AttendanceControls.tsx                          attendanceClosed exported (Task 14)
    SimpleSessions.tsx (+test)                      NEW (Task 14)
    index.ts                                        exports (Tasks 11, 13, 14)
  src/features/billing/InvoiceForm.tsx (+test)      archived=include while on (Task 12, under a claim)
  src/routes/_authed/scheduling.subscriptions.archive.tsx   NEW (Task 11)
  src/routes/_authed/scheduling.sessions.archive.tsx        NEW (Task 13)
  src/routes/_authed/scheduling.sessions.simple.tsx         NEW (Task 14)
  src/routes/permissions.test.ts                    FEATURE_SCREENS, FEATURE_WORDS (Tasks 11, 13, 14)
  src/routeTree.gen.ts                              regenerated (Tasks 11, 13, 14)
  src/locales/{en,ar}/archives.json                 NEW (Task 10)
  src/locales/{en,ar}/errors.json sessionActivity.json      codes; new actions and field (Task 10)
  e2e/b2-archive.spec.ts                            NEW (Task 15)
```

---
### Task 1: The switches, the archive columns and the migration

**Files:**
- Modify: `backend/etqan/platform/features.py` (flip `subscription_archive` and `session_archive` in place; add `simplified_sessions` under `# ── phase B2 ──`, after B2c's `activity_log`)
- Modify: `backend/etqan/platform/tests/test_features.py` (`BUILT`)
- Modify: `backend/etqan/scheduling/models.py` (`Subscription`, `Session`, `SessionActivity.Action`)
- Create: `backend/etqan/scheduling/migrations/0009_archives.py` (generated)
- Test: `backend/etqan/scheduling/tests/test_archive_model.py`

**Interfaces:**
- Produces: feature codes `subscription_archive`, `session_archive`, `simplified_sessions` (built, default off, group `teaching`). `Subscription.archived_at` (datetime, null), `Subscription.archived_by` (→ User, null, `SET_NULL`, `related_name="+"`), `Session.archived_at` (datetime, null), `Session.archived_with_subscription` (bool, `default=False`, `db_default=False`). `SessionActivity.Action.ARCHIVE = "archive"`, `.UNARCHIVE = "unarchive"`, `.SUBSCRIPTION_ARCHIVED = "subscription_archived"`, `.SUBSCRIPTION_RESTORED = "subscription_restored"`.

- [ ] **Step 1: Write the failing tests** (`test_archive_model.py`)

```python
"""Slice B2d §3, D-13: the three switches and the archive columns."""

import pytest

from etqan.platform import features
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
SWITCHES = ("subscription_archive", "session_archive", "simplified_sessions")


@pytest.mark.parametrize("code", SWITCHES)
def test_the_three_switches_are_built_and_off_by_default(code):
    feature = features.get(code)
    assert (feature.built, feature.default, feature.group) == (True, False, "teaching")
    assert features.is_on(code, {}) is False


def test_the_archive_lines_stay_in_place_and_the_view_follows_b2c():
    codes = [feature.code for feature in features.REGISTRY]
    assert codes.index("contracts") < codes.index("subscription_archive")
    assert codes.index("subscription_archive") + 1 == codes.index("session_archive")
    assert codes.index("session_archive") < codes.index("manual_sessions")
    assert codes.index("activity_log") + 1 == codes.index("simplified_sessions")


def test_new_rows_are_not_archived(subscribe):
    sub = subscribe(slots=two_slots())
    sub.refresh_from_db()
    session = Session.objects.filter(subscription=sub).first()
    assert (sub.archived_at, sub.archived_by_id) == (None, None)
    assert (session.archived_at, session.archived_with_subscription) == (None, False)


def test_the_log_knows_the_four_archive_actions():
    values = set(SessionActivity.Action.values)
    assert {
        "archive",
        "unarchive",
        "subscription_archived",
        "subscription_restored",
    } <= values
    assert max(len(value) for value in values) <= 24
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_archive_model.py`
Expected: FAIL (`KeyError`/`AssertionError` on `built`, `AttributeError: 'Subscription' object has no attribute 'archived_at'`). Keep the output for the report.

- [ ] **Step 3: Flip the two registry lines in place and add the third switch**

In `backend/etqan/platform/features.py`, replace the two `_later(...)` lines for the archives (they sit after `contracts`) with:

```python
    # Slice B2d (Plan 31): flipped to built in place, off by default.
    Feature(
        "subscription_archive",
        "Subscription archive",
        "أرشيف الاشتراكات",
        "teaching",
        built=True,
    ),
    Feature(
        "session_archive",
        "Session archive",
        "أرشيف الحصص",
        "teaching",
        built=True,
    ),
```

Under `# ── phase B2 ──`, right after B2c's `activity_log` entry and before `# ── phase B3 ──`:

```python
    # Slice B2d (Plan 31): the simplified sessions view, off by default.
    Feature(
        "simplified_sessions",
        "Simplified sessions view",
        "عرض الحصص المبسّط",
        "teaching",
        built=True,
    ),
```

In `backend/etqan/platform/tests/test_features.py`, `BUILT` follows the registry's order. Right after `"contracts": False,` (the last built key whose registry line comes before the archives; if another phase has flipped a line between `contracts` and `subscription_archive` by build time, insert after that one instead) add the two flipped lines, and extend the comment above them:

```python
    # Flipped in place, in registry order: B9a's file_uploads, B8's
    # url_redirects and articles, B3's donations, B9a's contracts, B2d's
    # subscription_archive and session_archive.
    ...
    "contracts": False,
    "subscription_archive": False,
    "session_archive": False,
```

and after `"activity_log": False,`:

```python
    "simplified_sessions": False,
```

- [ ] **Step 4: Add the columns and the actions** (`backend/etqan/scheduling/models.py`)

In `Subscription`, after `expired_at`:

```python
    # Slice B2d (spec §3, D-2): put away by the office — the same row, hidden
    # from the office's everyday lists while the subscription archive is on.
    archived_at = models.DateTimeField(null=True, blank=True)
    archived_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
```

In `Session`, after `postponed_at`:

```python
    # Slice B2d (spec §3): archived, and whether its subscription's archive
    # archived it (D-4: restoring the subscription brings back only those).
    archived_at = models.DateTimeField(null=True, blank=True)
    archived_with_subscription = models.BooleanField(default=False, db_default=False)
```

In `SessionActivity.Action`, after `SUBSCRIPTION_SUPERVISOR`:

```python
        # Slice B2d §4.3.
        ARCHIVE = "archive", "Archived"
        UNARCHIVE = "unarchive", "Restored from the archive"
        SUBSCRIPTION_ARCHIVED = "subscription_archived", "Archived with its subscription"
        SUBSCRIPTION_RESTORED = "subscription_restored", "Restored with its subscription"
```

- [ ] **Step 5: Generate the migration**

Run: `… exec -T django python manage.py makemigrations scheduling --name archives`
Expected: `0009_archives.py` depending on `0008_session_activity`, with four `AddField` (the two `archived_at`, `archived_by`, `archived_with_subscription` with `db_default=False`) and one `AlterField` on `sessionactivity.action` (choices only); no `RunPython`.

- [ ] **Step 6: Run the tests**

Run: `… exec -T django pytest -q --create-db etqan/scheduling/tests/test_archive_model.py etqan/platform/tests/test_features.py etqan/academy/tests/test_features_api.py`
Expected: PASS.

- [ ] **Step 7: Lint and commit**

Run: `… exec -T django ruff check . && … exec -T django ruff format --check .`

```bash
git -C backend add etqan/platform/features.py etqan/platform/tests/test_features.py etqan/scheduling/models.py etqan/scheduling/migrations/0009_archives.py etqan/scheduling/tests/test_archive_model.py
git -C backend commit -m "feat(scheduling): archive columns and the three B2d switches (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The shared rules — refusals, what is due, what may be archived, the filters

**Files:**
- Modify: `backend/etqan/scheduling/services/rules.py` (archive section after `require_status`; `subscriptions_queryset`; `filter_subscriptions` new; `filter_sessions` gains three keywords)
- Modify: `backend/etqan/scheduling/services/generation.py` (`_lock_live`)
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Modify: `backend/etqan/scheduling/tests/conftest.py` (`ARCHIVED_AT`, `stamp_archived`, the `archives_on` fixture)
- Test: `backend/etqan/scheduling/tests/test_archive_rules.py`

**Interfaces:**
- Consumes: Task 1's columns.
- Produces (module `rules`, re-exported from `services` where marked *):
  - `SUBSCRIPTION_ARCHIVE = "subscription_archive"`, `SESSION_ARCHIVE = "session_archive"`, `ENDED = (EXPIRED, CANCELLED)`, `ARCHIVED_MODES* = ("exclude", "only", "include")`, `ARCHIVED` (message).
  - `refuse_if_archived(subscription) -> None` (409 `scheduling.archived` while `subscription_archive` is on); `refuse_if_session_archived(session) -> None` (same, `session_archive`).
  - `due_sessions(**filters) -> QuerySet[Session]` (scheduled, `starts_at > now`).
  - `archivable*(subscription) -> bool` (reads `has_due_sessions` when present).
  - `filter_subscriptions*(qs, *, status="", student=None, teacher=None, course=None, q="", archived="include", archived_from=None, archived_to=None, created_from=None, created_to=None)`.
  - `filter_sessions*(…, archived="include", archived_from=None, archived_to=None)` (additive).
  - `subscriptions_queryset()` rows carry `has_due_sessions` (bool) and `archived_by` (joined).
- Test helpers (conftest): `ARCHIVED_AT = datetime(2026, 6, 2, 21, 30, tzinfo=UTC)`; `stamp_archived(obj, when=ARCHIVED_AT)` (writes `archived_at` straight to a subscription or session row and refreshes it); fixture `archives_on` (both archive switches on).

- [ ] **Step 1: Add the test helpers to scheduling's conftest** (after `as_user`)

```python
# Slice B2d: an instant the archive tests stamp rows with.
ARCHIVED_AT = datetime(2026, 6, 2, 21, 30, tzinfo=UTC)


def stamp_archived(obj, when=ARCHIVED_AT):
    """Mark a subscription or a session archived straight in the table, for
    tests whose subject is not the archive services (slice B2d)."""
    type(obj).objects.filter(pk=obj.pk).update(archived_at=when)
    obj.refresh_from_db()
    return obj


@pytest.fixture
def archives_on(set_features):
    """Slice B2d: both archive switches on (they are off by default)."""
    set_features(subscription_archive=True, session_archive=True)
```

- [ ] **Step 2: Write the failing tests** (`test_archive_rules.py`)

```python
"""Slice B2d §4.1, §4.4, §6.1, D-3, D-13: the rules the archive shares."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

import pytest

from etqan.academy import services as academy_services
from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.services import rules
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import stamp_archived
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db


def test_refuse_if_archived_only_while_the_switch_is_on(
    subscribe, set_features, archives_on
):
    sub = subscribe(slots=two_slots())
    rules.refuse_if_archived(sub)  # not archived: nothing
    stamp_archived(sub)
    with pytest.raises(ConflictError) as err:
        rules.refuse_if_archived(sub)
    assert err.value.code == "scheduling.archived"
    set_features(subscription_archive=False)
    rules.refuse_if_archived(sub)


def test_refuse_if_session_archived_only_while_the_switch_is_on(
    subscribe, set_features, archives_on
):
    session = Session.objects.filter(subscription=subscribe(slots=two_slots())).first()
    rules.refuse_if_session_archived(session)
    stamp_archived(session)
    with pytest.raises(ConflictError) as err:
        rules.refuse_if_session_archived(session)
    assert err.value.code == "scheduling.archived"
    set_features(session_archive=False)
    rules.refuse_if_session_archived(session)


def test_due_sessions_are_scheduled_ones_still_to_come(subscribe, clock):
    sub = subscribe(slots=two_slots())  # Mon 1, Wed 3, Mon 8, Wed 10, Mon 15 June
    clock.set(datetime(2026, 6, 3, 18, 0, tzinfo=UTC))  # Wednesday's starts now
    _mon, wed, next_mon, *rest = Session.objects.filter(subscription=sub).order_by(
        "starts_at"
    )
    Session.objects.filter(pk=next_mon.pk).update(status="cancelled")
    due = set(rules.due_sessions(subscription=sub).values_list("pk", flat=True))
    assert due == {session.pk for session in rest}
    assert wed.pk not in due  # starting this instant: no longer due (plan D15)


def test_archivable_is_ended_not_archived_and_nothing_due(subscribe):
    sub = subscribe(slots=two_slots())
    assert rules.archivable(sub) is False  # active
    services.cancel_subscription(sub)  # its future regular sessions go
    sub.refresh_from_db()
    assert rules.archivable(sub) is True
    extra = hand_session(sub, occurs_on=date(2026, 6, 20), kind="extra")
    assert rules.archivable(sub) is False
    row = services.subscriptions_queryset().get(pk=sub.pk)
    assert (row.has_due_sessions, services.archivable(row)) == (True, False)
    Session.objects.filter(pk=extra.pk).update(status="cancelled")
    assert services.archivable(services.subscriptions_queryset().get(pk=sub.pk))
    stamp_archived(sub)
    assert rules.archivable(sub) is False


def test_the_list_filters_subscriptions_by_archive_mode(subscribe):
    live, newer, older = (subscribe() for _ in range(3))
    stamp_archived(newer, datetime(2026, 6, 2, 9, 0, tzinfo=UTC))
    stamp_archived(older, datetime(2026, 6, 1, 9, 0, tzinfo=UTC))
    every = Subscription.objects.all()

    def ids(**query):
        return list(
            services.filter_subscriptions(every, **query).values_list("pk", flat=True)
        )

    assert ids(archived="exclude") == [live.pk]
    assert ids(archived="only") == [newer.pk, older.pk]  # newest archived first
    assert set(ids()) == {live.pk, newer.pk, older.pk}
    assert ids(archived="only", status="active") == [newer.pk, older.pk]
    assert ids(archived="exclude", q="yus") == [live.pk]


def test_archive_and_creation_days_are_academy_days(subscribe):
    academy_services.update_settings(timezone="Asia/Riyadh")  # UTC+3
    second, third = subscribe(), subscribe()
    stamp_archived(second, datetime(2026, 6, 2, 20, 30, tzinfo=UTC))  # 2 June there
    stamp_archived(third, datetime(2026, 6, 2, 21, 30, tzinfo=UTC))  # 3 June there
    every = Subscription.objects.all()

    def ids(**query):
        return set(
            services.filter_subscriptions(every, archived="only", **query).values_list(
                "pk", flat=True
            )
        )

    assert ids(archived_from=date(2026, 6, 3)) == {third.pk}
    assert ids(archived_to=date(2026, 6, 2)) == {second.pk}
    assert ids(archived_from=date(2026, 6, 2), archived_to=date(2026, 6, 3)) == {
        second.pk,
        third.pk,
    }
    Subscription.objects.filter(pk=second.pk).update(
        created_at=datetime(2026, 5, 31, 22, 0, tzinfo=UTC)  # 1 June there
    )
    Subscription.objects.filter(pk=third.pk).update(
        created_at=datetime(2026, 5, 31, 20, 0, tzinfo=UTC)  # 31 May there
    )
    assert ids(created_from=date(2026, 6, 1), created_to=date(2026, 6, 1)) == {
        second.pk
    }


def test_the_list_filters_sessions_by_archive_mode_and_day(subscribe):
    sub = subscribe(slots=two_slots())
    first, second, *rest = Session.objects.filter(subscription=sub).order_by(
        "starts_at"
    )
    stamp_archived(first, datetime(2026, 6, 1, 19, 0, tzinfo=UTC))
    stamp_archived(second, datetime(2026, 6, 3, 19, 0, tzinfo=UTC))
    every = Session.objects.filter(subscription=sub)

    def ids(**query):
        return [session.pk for session in services.filter_sessions(every, **query)]

    assert ids(archived="exclude") == [session.pk for session in rest]
    assert ids(archived="only") == [first.pk, second.pk]
    assert ids(archived="only", archived_from=date(2026, 6, 2)) == [second.pk]
    assert ids(archived="only", archived_to=date(2026, 6, 1)) == [first.pk]
    assert len(ids()) == 2 + len(rest)


def test_an_archived_subscription_never_generates(subscribe):
    """D-3 / plan D13: a guard — the services never archive a live one."""
    sub = subscribe()
    stamp_archived(sub)
    ScheduleSlot.objects.create(
        subscription=sub, weekday=0, start_time=time(18, 0), minutes=45
    )
    result = services.generate(date(2026, 6, 1), date(2026, 6, 14), subscription=sub)
    assert result.created == 0
    assert not Session.objects.filter(subscription=sub).exists()
```

- [ ] **Step 3: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_archive_rules.py`
Expected: FAIL (`AttributeError: module 'etqan.scheduling.services.rules' has no attribute 'refuse_if_archived'`). Keep the output.

- [ ] **Step 4: Implement the rules** (`services/rules.py`)

Add `from datetime import time` and `from etqan.platform import features` to the imports (one per line, sorted). After `require_status`:

```python
# ── Archives (slice B2d) ─────────────────────────────────────────────────────

SUBSCRIPTION_ARCHIVE = "subscription_archive"
SESSION_ARCHIVE = "session_archive"
# D-3: only an ended subscription is archived.
ENDED = (Subscription.Status.EXPIRED, Subscription.Status.CANCELLED)
# §4.4: what a list does with archived rows.
ARCHIVED_MODES = ("exclude", "only", "include")
ARCHIVED = "This is archived. Restore it first."


def refuse_if_archived(subscription: Subscription) -> None:
    """D-7: an archived subscription takes no renewal, no session added
    against it and no slot change — only while the subscription archive is
    on (D-13). Call it on the locked row."""
    if subscription.archived_at is not None and features.enabled(
        SUBSCRIPTION_ARCHIVE
    ):
        raise ConflictError(ARCHIVED, code="scheduling.archived")


def refuse_if_session_archived(session: Session) -> None:
    """D-7: an archived session is never postponed (it would become a hidden
    future session) — only while the session archive is on. On the locked
    row."""
    if session.archived_at is not None and features.enabled(SESSION_ARCHIVE):
        raise ConflictError(ARCHIVED, code="scheduling.archived")


def due_sessions(**filters) -> QuerySet[Session]:
    """D-3: sessions still due — scheduled and starting in the future,
    whatever their kind (a cancel or an expiry leaves make-ups, extras and
    postponed sessions behind). A session starting this instant has started
    (plan D15)."""
    return Session.objects.filter(
        status=Session.Status.SCHEDULED, starts_at__gt=dates.now(), **filters
    )


def archivable(subscription: Subscription) -> bool:
    """D-3, as the office's Archive action asks it (plan D2): ended, not
    archived, nothing due. Reads ``has_due_sessions`` when the row carries
    it (`subscriptions_queryset`), else asks once."""
    if subscription.status not in ENDED or subscription.archived_at is not None:
        return False
    due = getattr(subscription, "has_due_sessions", None)
    if due is None:
        due = due_sessions(subscription=subscription).exists()
    return not due
```

In `subscriptions_queryset`, join `archived_by` and annotate:

```python
    return (
        Subscription.objects.select_related(
            "student__user",
            "teacher__user",
            "course",
            "package",
            "supervisor",
            "archived_by",
        )
        .annotate(
            renewal_id=Subquery(live_renewals.values("pk")[:1]),
            # Slice B2d (plan D2): whether a session is still due.
            has_due_sessions=Exists(due_sessions(subscription=OuterRef("pk"))),
        )
        .prefetch_related("pauses")
    )
```

Before `filter_sessions`, the shared helpers and the moved subscription filter:

```python
def _archived(queryset: QuerySet, archived: str) -> QuerySet:
    """§4.4: ``exclude`` · ``only`` · ``include`` (the view decides which)."""
    if archived == "exclude":
        return queryset.filter(archived_at__isnull=True)
    if archived == "only":
        return queryset.filter(archived_at__isnull=False)
    return queryset


def _within_days(queryset: QuerySet, **ranges) -> QuerySet:
    """Plan 31 D5: ``field=(first, last)`` academy days as a UTC range on the
    instant ``field``, from ``first`` 00:00 to the midnight after ``last``
    on the academy's clock. The timezone is read once, only when a day is
    given."""
    wanted = {name: pair for name, pair in ranges.items() if pair != (None, None)}
    if not wanted:
        return queryset
    zone = settings().timezone
    bounds = {}
    for name, (first, last) in wanted.items():
        if first is not None:
            bounds[f"{name}__gte"] = dates.to_utc(first, time(0), zone)
        if last is not None:
            bounds[f"{name}__lt"] = dates.to_utc(
                last + timedelta(days=1), time(0), zone
            )
    return queryset.filter(**bounds)


def filter_subscriptions(  # noqa: PLR0913 -- keyword-only; mirrors the list's query (spec §6.1)
    subscriptions: QuerySet[Subscription],
    *,
    status: str = "",
    student: int | None = None,
    teacher: int | None = None,
    course: int | None = None,
    q: str = "",
    archived: str = "include",
    archived_from: date | None = None,
    archived_to: date | None = None,
    created_from: date | None = None,
    created_to: date | None = None,
) -> QuerySet[Subscription]:
    """The subscriptions list's filters (Plan 4 §5, moved out of the view by
    slice B2d §4.4; §6.1's new ones). People are User ids; days are the
    academy's. ``archived`` is one of `ARCHIVED_MODES`: the view decides it.
    The archive lists the most recently archived first."""
    exact = {
        "status": status,
        "student__user_id": student,
        "teacher__user_id": teacher,
        "course_id": course,
    }
    subscriptions = subscriptions.filter(
        **{key: value for key, value in exact.items() if value not in (None, "")}
    )
    if q := q.strip():
        subscriptions = subscriptions.filter(student__user__full_name__icontains=q)
    subscriptions = _within_days(
        _archived(subscriptions, archived),
        archived_at=(archived_from, archived_to),
        created_at=(created_from, created_to),
    )
    if archived == "only":
        subscriptions = subscriptions.order_by("-archived_at", "-id")
    return subscriptions
```

`filter_sessions` gains three keyword arguments (after `q`) and applies them before `_when` — the whole function:

```python
def filter_sessions(  # noqa: PLR0913 -- keyword-only; mirrors the list's query (spec §5)
    sessions: QuerySet[Session],
    *,
    when: str = "",
    from_date: date | None = None,
    to_date: date | None = None,
    status: str = "",
    kind: str = "",
    student_attendance: str = "",
    teacher: int | None = None,
    student: int | None = None,
    course: int | None = None,
    subscription: int | None = None,
    q: str = "",
    archived: str = "include",
    archived_from: date | None = None,
    archived_to: date | None = None,
) -> QuerySet[Session]:
    """The session list's filters (spec §5). ``from_date``/``to_date`` are
    academy-local dates; people are User ids, as everywhere in the API.
    Slice B2a: ``kind``. Slice B2d: ``archived`` (one of `ARCHIVED_MODES`)
    and the archive's days."""
    exact = {
        "occurs_on__gte": from_date,
        "occurs_on__lte": to_date,
        "status": status,
        "kind": kind,
        "student_attendance": student_attendance,
        "teacher__user_id": teacher,
        "student__user_id": student,
        "course_id": course,
        "subscription_id": subscription,
    }
    sessions = sessions.filter(
        **{key: value for key, value in exact.items() if value not in (None, "")}
    )
    if q := q.strip():
        sessions = sessions.filter(student__user__full_name__icontains=q)
    sessions = _within_days(
        _archived(sessions, archived), archived_at=(archived_from, archived_to)
    )
    return _when(sessions, when)
```

`services/generation.py`, `_lock_live` (D-3, plan D13):

```python
    live = Subscription.objects.filter(status__in=rules.LIVE, archived_at__isnull=True)
```

and add a sentence to its docstring: "An archived subscription never generates (slice B2d D-3)."

`services/__init__.py`: import and list in `__all__` (alphabetical, as the file is): `ARCHIVED_MODES`, `archivable`, `filter_subscriptions` from `rules`.

- [ ] **Step 5: Run the tests, then the suites that read subscriptions and sessions**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_archive_rules.py etqan/scheduling/tests/test_api_subscriptions.py etqan/scheduling/tests/test_api_sessions.py etqan/scheduling/tests/test_generation.py etqan/scheduling/tests/test_today.py`
Expected: PASS (the query-count tests too: the annotation is a subquery and `archived_by` a join).

- [ ] **Step 6: Lint and commit**

```bash
git -C backend add etqan/scheduling/services/rules.py etqan/scheduling/services/generation.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/conftest.py etqan/scheduling/tests/test_archive_rules.py
git -C backend commit -m "feat(scheduling): archive rules, filters and what may be archived (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 3: Archiving and restoring a subscription; the log learns the archive

**Files:**
- Create: `backend/etqan/scheduling/services/archive.py` (the subscription half; Task 4 adds the session half)
- Modify: `backend/etqan/scheduling/services/activity.py` (`LOGGED_FIELDS`, `INSTANTS`, `ACTION_FEATURES`, `hidden_actions`)
- Modify: `backend/etqan/scheduling/services/activity_feed.py` (`session_activity` leaves hidden actions out)
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Modify: `backend/etqan/scheduling/tests/conftest.py` (the `ended` fixture)
- Test: `backend/etqan/scheduling/tests/test_archive_subscriptions.py`

**Interfaces:**
- Consumes: Task 2 (`rules.ENDED`, `rules.ARCHIVED`, `rules.due_sessions`, `rules.require_status`), B2c's `activity.record_many`.
- Produces:
  - `services.archive_subscription(subscription, *, by) -> Subscription` and `services.restore_subscription(subscription, *, by) -> Subscription` (both `@transaction.atomic`; the returned row is the locked one, already saved).
  - `archive.NOT_ARCHIVED`, `archive.STILL_TO_COME` (messages); private `_archived()`, `_not_archived()` (Task 4 reuses them).
  - `activity.LOGGED_FIELDS` ends with `"archived_at"`; `"archived_at" in activity.INSTANTS`; `activity.ACTION_FEATURES: dict[str, str]`; `activity.hidden_actions() -> list[str]` (sorted action values whose switch is off; no query).
  - Conftest fixture `ended` → a cancelled subscription (cancelled on Thursday 4 June 08:00 UTC, the clock left there) whose Monday 1 and Wednesday 3 June sessions are past, unmarked and kept, nothing due.

- [ ] **Step 1: Add the `ended` fixture to scheduling's conftest** (after `archives_on`)

```python
@pytest.fixture
def ended(subscribe, clock):
    """Slice B2d: a subscription cancelled on Thursday 4 June 08:00 UTC (the
    clock stays there). Its Monday 1 and Wednesday 3 June sessions are past,
    unmarked and kept; its later ones went with the cancel, so nothing is
    due."""
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 4, 8, 0, tzinfo=UTC))
    services.cancel_subscription(sub)
    sub.refresh_from_db()
    return sub
```

- [ ] **Step 2: Write the failing tests** (`test_archive_subscriptions.py`)

```python
"""Slice B2d §4.1, §4.3, D-3, D-4: archiving and restoring a subscription."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.services import activity
from etqan.scheduling.services import rules
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import stamp_archived
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
NOW = datetime(2026, 6, 4, 8, 0, tzinfo=UTC)  # the `ended` fixture's clock
OWN = datetime(2026, 6, 3, 20, 0, tzinfo=UTC)


@pytest.fixture
def admin():
    return make_admin()


def sessions_of(sub):
    return list(Session.objects.filter(subscription=sub).order_by("pk"))


def first_table(sql: str) -> str:
    return sql.split(" FROM ", 1)[1].split()[0]


def test_archiving_stamps_the_subscription_and_its_sessions(ended, admin):
    services.archive_subscription(ended, by=admin)
    ended.refresh_from_db()
    assert (ended.archived_at, ended.archived_by_id) == (NOW, admin.pk)
    rows = sessions_of(ended)
    assert len(rows) == 2
    assert all(s.archived_at == NOW and s.archived_with_subscription for s in rows)


def test_an_expired_subscription_archives_too(subscribe, clock, admin):
    sub = subscribe(slots=two_slots())
    clock.set(NOW)
    rules.expire([sub.pk])
    sub.refresh_from_db()
    assert services.archive_subscription(sub, by=admin).archived_at == NOW


def test_refusals_come_in_their_order(ended, subscribe, admin):
    live = subscribe(slots=two_slots())  # active, with sessions still to come
    with pytest.raises(ConflictError) as err:
        services.archive_subscription(live, by=admin)
    assert err.value.code == "scheduling.not_allowed_in_status"  # before "due"
    stamp_archived(live)
    with pytest.raises(ConflictError) as err:
        services.archive_subscription(live, by=admin)
    assert err.value.code == "scheduling.archived"  # before the status
    services.archive_subscription(ended, by=admin)
    with pytest.raises(ConflictError) as err:
        services.archive_subscription(ended, by=admin)
    assert err.value.code == "scheduling.archived"


@pytest.mark.parametrize("kind", ["extra", "compensation", "postponed"])
def test_a_session_still_to_come_blocks_the_archive(ended, admin, kind):
    past = sessions_of(ended)[0]
    fields = {
        "extra": {"kind": "extra"},
        "compensation": {"kind": "compensation", "compensates": past},
        "postponed": {"postponed_at": NOW},
    }[kind]
    leftover = hand_session(ended, occurs_on=date(2026, 6, 10), **fields)
    with pytest.raises(ConflictError) as err:
        services.archive_subscription(ended, by=admin)
    assert err.value.code == "scheduling.has_upcoming_sessions"
    ended.refresh_from_db()
    assert ended.archived_at is None
    assert not Session.objects.filter(archived_at__isnull=False).exists()
    Session.objects.filter(pk=leftover.pk).update(status="cancelled")
    assert services.archive_subscription(ended, by=admin).archived_at == NOW


def test_the_cascade_leaves_a_session_archived_on_its_own_as_it_was(ended, admin):
    own, other = sessions_of(ended)
    stamp_archived(own, OWN)
    services.archive_subscription(ended, by=admin)
    own.refresh_from_db()
    other.refresh_from_db()
    assert (own.archived_at, own.archived_with_subscription) == (OWN, False)
    assert (other.archived_at, other.archived_with_subscription) == (NOW, True)


def test_restore_brings_back_only_what_came_with_it(ended, admin):
    own, other = sessions_of(ended)
    stamp_archived(own, OWN)
    services.archive_subscription(ended, by=admin)
    services.restore_subscription(ended, by=admin)
    ended.refresh_from_db()
    own.refresh_from_db()
    other.refresh_from_db()
    assert (ended.archived_at, ended.archived_by_id) == (None, None)
    assert own.archived_at == OWN
    assert (other.archived_at, other.archived_with_subscription) == (None, False)


def test_restoring_what_is_not_archived_is_refused(ended, admin):
    with pytest.raises(ConflictError) as err:
        services.restore_subscription(ended, by=admin)
    assert err.value.code == "scheduling.not_archived"


@pytest.mark.parametrize("step", ["archive", "restore"])
def test_the_subscription_is_locked_before_its_sessions(ended, admin, step):
    if step == "restore":
        services.archive_subscription(ended, by=admin)
    run = {
        "archive": services.archive_subscription,
        "restore": services.restore_subscription,
    }[step]
    with CaptureQueriesContext(connection) as ctx:
        run(ended, by=admin)
    locks = [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]
    assert [first_table(sql) for sql in locks[:2]] == [
        '"scheduling_subscription"',
        '"scheduling_session"',
    ]
    assert 'ORDER BY "scheduling_session"."id"' in locks[1]


def test_the_cascade_is_logged_per_session_and_never_reverted(
    ended, admin, set_features
):
    set_features(activity_log=True, subscription_archive=True)
    services.archive_subscription(ended, by=admin)
    entries = list(
        SessionActivity.objects.filter(action="subscription_archived").order_by(
            "session_id"
        )
    )
    assert [e.session_id for e in entries] == [s.pk for s in sessions_of(ended)]
    assert entries[0].changes == {"archived_at": [None, "2026-06-04T08:00:00Z"]}
    assert (entries[0].actor_id, entries[0].actor_kind) == (admin.pk, "user")
    assert services.revert_refusal(entries[0], admin) == "not_revertible"
    services.restore_subscription(ended, by=admin)
    restored = SessionActivity.objects.filter(action="subscription_restored")
    assert {tuple(e.changes["archived_at"]) for e in restored} == {
        ("2026-06-04T08:00:00Z", None)
    }


def test_the_cascade_shows_only_while_the_subscription_archive_is_on(
    ended, admin, set_features
):
    set_features(activity_log=True, subscription_archive=True)
    services.archive_subscription(ended, by=admin)
    row = services.sessions_queryset().get(pk=sessions_of(ended)[0].pk)
    shown = services.session_activity(row, admin).entries
    assert [s.entry.action for s in shown] == ["subscription_archived"]
    assert shown[0].changes == [
        {"field": "archived_at", "before": None, "after": "2026-06-04T08:00:00Z"}
    ]
    set_features(subscription_archive=False)
    assert services.session_activity(row, admin).entries == []


def test_the_log_reads_archived_at_as_an_instant(set_features):
    assert activity.LOGGED_FIELDS[-1] == "archived_at"
    assert activity.from_json("archived_at", "2026-06-04T08:00:00Z") == NOW
    set_features(session_archive=True, subscription_archive=False)
    assert activity.hidden_actions() == [
        "subscription_archived",
        "subscription_restored",
    ]
```

- [ ] **Step 3: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_archive_subscriptions.py`
Expected: FAIL (`AttributeError: module 'etqan.scheduling.services' has no attribute 'archive_subscription'`). Keep the output.

- [ ] **Step 4: The log learns the archive** (`services/activity.py`)

Append `"archived_at"` as the last entry of `LOGGED_FIELDS` (it is shown last), add `"archived_at"` to `INSTANTS`, and after `FIELD_FEATURES`:

```python
# Slice B2d §4.3 (Plan 31 D4): these actions show — and revert — only while
# their own switch is on; `archived_at` itself is not in FIELD_FEATURES, so
# every other action that ever touched it would still show.
ACTION_FEATURES = {
    Action.ARCHIVE: "session_archive",
    Action.UNARCHIVE: "session_archive",
    Action.SUBSCRIPTION_ARCHIVED: "subscription_archive",
    Action.SUBSCRIPTION_RESTORED: "subscription_archive",
}
```

and after `visible_fields`:

```python
def hidden_actions() -> list[str]:
    """The actions whose own switch is off (Plan 31 D4), sorted. No query."""
    return sorted(
        str(action)
        for action, code in ACTION_FEATURES.items()
        if not features.enabled(code)
    )
```

In `services/activity_feed.py`, `session_activity` leaves those out before the cap (one filter, no extra query):

```python
def session_activity(session: Session, viewer) -> ActivityFeed:
    """§4.3. ``session`` is read from `sessions_queryset()`. An entry whose
    every field is switched off is left out before the cap (Plan 25 D9).
    Slice B2d: an entry whose action's switch is off is left out too."""
    rows = list(
        activity_of(session)
        .filter(changes__has_any_keys=sorted(activity.visible_fields()))
        .exclude(action__in=activity.hidden_actions())
        .select_related("actor")
        .prefetch_related(
            Prefetch("reverted_by", queryset=SessionActivity.objects.order_by("id"))
        )[: MAX_ENTRIES + 1]
    )
    return ActivityFeed(
        session=session,
        entries=describe_activity(rows[:MAX_ENTRIES], session, viewer),
        truncated=len(rows) > MAX_ENTRIES,
    )
```

- [ ] **Step 5: Implement `services/archive.py`** (the subscription half)

```python
"""Archives (slice B2d §4.1–§4.2): the office puts an ended subscription or a
finished session away and brings it back. The same rows with `archived_at`
set (D-2): nothing is deleted or moved, and no other app filters on it, so
every count, invoice, payroll run and consumption number keeps including
them (ledger D14). Locks: a subscription, then its sessions in id order
(Plan 4); a session alone (B2a)."""

from django.db import transaction

from etqan.platform.exceptions import ConflictError
from etqan.scheduling import dates
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.services import activity
from etqan.scheduling.services import rules

NOT_ARCHIVED = "This isn't archived."
STILL_TO_COME = (
    "A session of this subscription is still to come. Cancel or delete it first."
)


def _archived() -> ConflictError:
    return ConflictError(rules.ARCHIVED, code="scheduling.archived")


def _not_archived() -> ConflictError:
    return ConflictError(NOT_ARCHIVED, code="scheduling.not_archived")


def _lock_with_sessions(
    subscription: Subscription, **filters
) -> tuple[Subscription, list[int]]:
    """Plan 4's order: the subscription's row, then its sessions' (narrowed by
    ``filters``) in one statement, in id order."""
    locked = Subscription.objects.select_for_update().get(pk=subscription.pk)
    ids = list(
        Session.objects.select_for_update()
        .filter(subscription=locked, **filters)
        .order_by("pk")
        .values_list("pk", flat=True)
    )
    return locked, ids


@transaction.atomic
def archive_subscription(subscription: Subscription, *, by) -> Subscription:
    """§4.1. Refusals in order: already archived, not ended (D-3), a session
    still to come. Then the subscription and those of its sessions not
    archived yet take the same instant, the sessions marked as archived with
    it (D-4), in one `.update()` logged as `subscription_archived`."""
    locked, ids = _lock_with_sessions(subscription)
    if locked.archived_at is not None:
        raise _archived()
    rules.require_status(locked, rules.ENDED)
    if rules.due_sessions(pk__in=ids).exists():
        raise ConflictError(STILL_TO_COME, code="scheduling.has_upcoming_sessions")
    now = dates.now()
    locked.archived_at = now
    locked.archived_by = by
    locked.save(update_fields=["archived_at", "archived_by", "updated_at"])
    cascade = list(
        Session.objects.filter(pk__in=ids, archived_at__isnull=True).values_list(
            "pk", flat=True
        )
    )
    Session.objects.filter(pk__in=cascade).update(
        archived_at=now, archived_with_subscription=True, updated_at=now
    )
    activity.record_many(
        [(pk, {"archived_at": (None, now)}) for pk in cascade],
        by,
        activity.Action.SUBSCRIPTION_ARCHIVED,
    )
    return locked


@transaction.atomic
def restore_subscription(subscription: Subscription, *, by) -> Subscription:
    """§4.1: back in the lists, with the sessions archived *with* it (D-4);
    one archived on its own stays archived. Logged as `subscription_restored`
    from each session's archive instant, read under the lock."""
    locked, ids = _lock_with_sessions(subscription, archived_with_subscription=True)
    if locked.archived_at is None:
        raise _not_archived()
    before = dict(
        Session.objects.filter(pk__in=ids).values_list("pk", "archived_at")
    )
    locked.archived_at = None
    locked.archived_by = None
    locked.save(update_fields=["archived_at", "archived_by", "updated_at"])
    Session.objects.filter(pk__in=ids).update(
        archived_at=None, archived_with_subscription=False, updated_at=dates.now()
    )
    activity.record_many(
        [(pk, {"archived_at": (before[pk], None)}) for pk in ids],
        by,
        activity.Action.SUBSCRIPTION_RESTORED,
    )
    return locked
```

(`rules.due_sessions(pk__in=ids)`: the rows just locked are every session of the subscription.)

`services/__init__.py`: `from etqan.scheduling.services.archive import archive_subscription` and `… import restore_subscription`, both in `__all__`.

- [ ] **Step 6: Run the tests, then B2c's suites**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_archive_subscriptions.py etqan/scheduling/tests/test_activity_writers.py etqan/scheduling/tests/test_activity_feed.py etqan/scheduling/tests/test_activity_revert.py etqan/scheduling/tests/test_api_activity.py`
Expected: PASS. Then `… ruff check . && … ruff format --check . && … lint-imports`.

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/scheduling/services/archive.py etqan/scheduling/services/activity.py etqan/scheduling/services/activity_feed.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/conftest.py etqan/scheduling/tests/test_archive_subscriptions.py
git -C backend commit -m "feat(scheduling): archive and restore a subscription with its sessions (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Archiving sessions on their own, in bulk, and reverting it; nothing stops counting

**Files:**
- Modify: `backend/etqan/scheduling/services/archive.py` (the session half)
- Modify: `backend/etqan/scheduling/services/revert.py` (two inverses)
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Test: `backend/etqan/scheduling/tests/test_archive_sessions.py`, `backend/etqan/scheduling/tests/test_archive_counting.py`

**Interfaces:**
- Consumes: Task 3 (`_archived`, `_not_archived`, `ended`), B2a's `attendance.lock`, `attendance.has_started`, `attendance.BulkResult`, `attendance.MAX_BULK`, B2c's `activity.track`, `revert.Inverse`, `revert._codes`, `revert._switches`.
- Produces:
  - `services.archive_session(session, *, by) -> Session`; `services.unarchive_session(session, *, by) -> Session` (`@transaction.atomic`, `track` entered right after the lock, refusals inside it).
  - `services.archive_sessions(ids: Iterable[int], *, by) -> BulkResult`; `services.unarchive_sessions(ids, *, by) -> BulkResult` (`done: list[int]`, `skipped: list[tuple[int, str]]`; 1–200 ids else `ValidationError` on `ids`; an id this academy lacks is skipped as `not_found`).
  - `revert.INVERSES[Action.ARCHIVE]` (runs `unarchive_session`; needs `session.restore` and `session_archive`); `revert.INVERSES[Action.UNARCHIVE]` (runs `archive_session`; needs `session.delete` and `session_archive`).

- [ ] **Step 1: Write the failing tests** (`test_archive_sessions.py`)

```python
"""Slice B2d §4.2, §4.3, D-5: a session archived on its own, in bulk, and
the B2c log of it."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
NOW = datetime(2026, 6, 3, 19, 0, tzinfo=UTC)  # Mon 1 and Wed 3 have started


@pytest.fixture
def admin():
    return make_admin()


@pytest.fixture
def sessions(subscribe, clock):
    sub = subscribe(slots=two_slots())
    clock.set(NOW)
    return list(Session.objects.filter(subscription=sub).order_by("starts_at"))


@pytest.mark.parametrize("status", ["scheduled", "completed", "cancelled", "at_disposal"])
def test_a_session_no_longer_due_is_archived(sessions, admin, status):
    first = sessions[0]
    Session.objects.filter(pk=first.pk).update(status=status)
    archived = services.archive_session(first, by=admin)
    assert (archived.archived_at, archived.archived_with_subscription) == (NOW, False)


def test_a_session_still_to_come_is_refused_unless_it_is_cancelled(sessions, admin):
    later = sessions[2]  # Monday 8 June
    with pytest.raises(ConflictError) as err:
        services.archive_session(later, by=admin)
    assert err.value.code == "scheduling.not_allowed_in_status"
    Session.objects.filter(pk=later.pk).update(status="cancelled")
    assert services.archive_session(later, by=admin).archived_at == NOW


def test_archiving_twice_and_restoring_what_is_not_archived_are_refused(
    sessions, admin
):
    first = sessions[0]
    with pytest.raises(ConflictError) as err:
        services.unarchive_session(first, by=admin)
    assert err.value.code == "scheduling.not_archived"
    services.archive_session(first, by=admin)
    with pytest.raises(ConflictError) as err:
        services.archive_session(first, by=admin)
    assert err.value.code == "scheduling.archived"
    back = services.unarchive_session(first, by=admin)
    assert (back.archived_at, back.archived_with_subscription) == (None, False)


def test_paid_and_compensated_sessions_archive_and_no_number_moves(sessions, admin):
    first, second = sessions[0], sessions[1]
    services.mark_attendance(first, by=admin, student_attendance="present")
    services.lock_sessions([first.pk])
    Session.objects.filter(pk=second.pk).update(status="cancelled", compensated=True)
    sub_id = first.subscription_id

    def numbers():
        sub = services.subscriptions_queryset().get(pk=sub_id)
        payroll = services.payroll_sessions(date(2026, 6, 1), date(2026, 6, 30))
        return services.derived(sub), list(payroll.values_list("pk", flat=True))

    before = numbers()
    services.archive_session(first, by=admin)
    services.archive_session(second, by=admin)
    assert numbers() == before
    assert before[0].sessions_used == 1


def test_unarchive_under_an_archived_subscription(ended, admin, set_features):
    set_features(subscription_archive=True)
    services.archive_subscription(ended, by=admin)
    first = Session.objects.filter(subscription=ended).order_by("pk").first()
    with pytest.raises(ConflictError) as err:
        services.unarchive_session(first, by=admin)
    assert err.value.code == "scheduling.archived"
    set_features(subscription_archive=False)
    back = services.unarchive_session(first, by=admin)
    assert (back.archived_at, back.archived_with_subscription) == (None, False)


def test_an_archived_session_still_takes_attendance_and_stays_archived(
    sessions, admin
):
    """D-7, spec §10: the archive screen's marks work on archived sessions,
    which stay archived."""
    first = sessions[0]
    services.archive_session(first, by=admin)
    marked = services.mark_attendance(first, by=admin, student_attendance="present")
    assert (marked.status, marked.archived_at) == ("completed", NOW)
    result = services.bulk_sessions([first.pk], action="cancel", by=admin, reason="Eid")
    assert result.done == [first.pk]
    first.refresh_from_db()
    assert (first.status, first.archived_at) == ("cancelled", NOW)


def test_bulk_archives_what_it_may_and_says_why_it_skipped_the_rest(sessions, admin):
    first, second, later = sessions[0], sessions[1], sessions[2]
    services.archive_session(second, by=admin)
    result = services.archive_sessions(
        [later.pk, 999999, first.pk, second.pk, first.pk], by=admin
    )
    assert result.done == [first.pk]
    assert result.skipped == [
        (second.pk, "scheduling.archived"),
        (later.pk, "scheduling.not_allowed_in_status"),
        (999999, "not_found"),
    ]
    back = services.unarchive_sessions([first.pk, later.pk], by=admin)
    assert (back.done, back.skipped) == (
        [first.pk],
        [(later.pk, "scheduling.not_archived")],
    )


@pytest.mark.parametrize("ids", [[], list(range(1, 202))])
def test_bulk_takes_from_1_to_200_ids(admin, ids):
    for run in (services.archive_sessions, services.unarchive_sessions):
        with pytest.raises(ValidationError) as err:
            run(ids, by=admin)
        assert err.value.field == "ids"


# ── The activity log (B2c) ───────────────────────────────────────────────────


@pytest.fixture
def logged(set_features):
    set_features(activity_log=True, session_archive=True)


def test_archive_and_unarchive_are_logged_and_revert_each_other(
    sessions, admin, logged
):
    first = sessions[0]
    services.archive_session(first, by=admin)
    entry = SessionActivity.objects.get(session=first, action="archive")
    assert entry.changes == {"archived_at": [None, "2026-06-03T19:00:00Z"]}
    undone = services.revert_activity(entry, by=admin)
    assert undone.session.archived_at is None
    assert (undone.entry.action, undone.entry.reverts_id) == ("unarchive", entry.pk)
    redone = services.revert_activity(undone.entry, by=admin)
    assert redone.session.archived_at == NOW
    assert redone.entry.action == "archive"


def test_a_refused_archive_writes_no_entry(sessions, admin, logged):
    with pytest.raises(ConflictError):
        services.archive_session(sessions[2], by=admin)
    assert not SessionActivity.objects.exists()


def test_reverting_needs_the_inverse_code_and_the_switch(
    sessions, admin, logged, staff_for, set_features
):
    first = sessions[0]
    services.archive_session(first, by=admin)
    archived = SessionActivity.objects.get(session=first, action="archive")
    updater = staff_for("session.update").user
    assert services.revert_refusal(archived, updater) == "forbidden"
    restorer = staff_for("session.update", "session.restore").user
    assert services.revert_refusal(archived, restorer) is None
    services.unarchive_session(first, by=admin)
    unarchived = SessionActivity.objects.get(session=first, action="unarchive")
    assert services.revert_refusal(unarchived, restorer) == "forbidden"
    deleter = staff_for("session.update", "session.delete").user
    assert services.revert_refusal(unarchived, deleter) is None
    set_features(session_archive=False)
    assert services.revert_refusal(unarchived, admin) == "not_revertible"


def test_archive_entries_show_only_while_the_session_archive_is_on(
    sessions, admin, logged, set_features
):
    first = sessions[0]
    services.archive_session(first, by=admin)
    row = services.sessions_queryset().get(pk=first.pk)
    feed = services.session_activity(row, admin).entries
    assert [(s.entry.action, s.can_revert) for s in feed] == [("archive", True)]
    set_features(session_archive=False)
    assert services.session_activity(row, admin).entries == []
```

`test_archive_counting.py` (spec §9 Counting, BR-46, ledger D14):

```python
"""Slice B2d §9 Counting (BR-46, ledger D14): archiving changes no number —
consumption across a renewal chain, payroll's sessions, an invoice for the
subscription and the missing-reports queue are the same before and after."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.billing import services as billing_services
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.services import rules
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db


def test_archiving_changes_no_number_anywhere(subscribe, clock, archives_on):
    admin = make_admin()
    old = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 4, 8, 0, tzinfo=UTC))
    for session in Session.objects.filter(subscription=old).order_by("starts_at")[:2]:
        services.mark_attendance(session, by=admin, student_attendance="present")
    # One session in the package: the second one is an extra the renewal
    # carries over (Plan 4's carried_over_sessions).
    Subscription.objects.filter(pk=old.pk).update(sessions_total=1)
    renewal = services.renew_subscription(old, starts_on=date(2026, 6, 8))
    clock.set(datetime(2026, 6, 9, 8, 0, tzinfo=UTC))
    rules.expire([old.pk])
    old.refresh_from_db()

    def numbers():
        subs = services.subscriptions_queryset().filter(pk__in=[old.pk, renewal.pk])
        payroll = services.payroll_sessions(date(2026, 6, 1), date(2026, 6, 30))
        return (
            services.derive(subs),
            list(payroll.values_list("pk", flat=True)),
            list(services.missing_reports().values_list("pk", flat=True)),
        )

    before = numbers()
    assert before[0][renewal.pk].carried_over_sessions == 1
    assert len(before[2]) == 2
    services.archive_subscription(old, by=admin)
    assert Session.objects.filter(subscription=old, archived_at__isnull=True).count() == 0
    assert numbers() == before
    invoice = billing_services.create_invoice(
        student_id=old.student.user_id,
        amount_minor=1000,
        due_on=date(2026, 6, 20),
        description="Late fee",
        by=admin,
        subscription_id=old.pk,
    )
    assert invoice.subscription_id == old.pk
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_archive_sessions.py etqan/scheduling/tests/test_archive_counting.py`
Expected: `test_archive_sessions.py` FAILS (`AttributeError: … has no attribute 'archive_session'`). `test_archive_counting.py` already PASSES (it needs only Task 3): it is a guard pinning ledger D14 — no other code may start filtering on `archived_at` — so its RED evidence is a deliberate mutation: temporarily add `.filter(archived_at__isnull=True)` to `paylock.payroll_sessions`, run it, see it FAIL on `numbers() == before`, and revert. Keep both outputs for the report.

- [ ] **Step 3: Implement the session half of `services/archive.py`**

Add to the imports (one per line): `from collections.abc import Callable`, `from collections.abc import Iterable`, `from etqan.platform import features`, `from etqan.platform.exceptions import ValidationError`, `from etqan.scheduling.services.attendance import MAX_BULK`, `from etqan.scheduling.services.attendance import BulkResult`, `from etqan.scheduling.services.attendance import has_started`, `from etqan.scheduling.services.attendance import lock`. Then:

```python
STILL_AHEAD = "A session still to come can't be archived."


@transaction.atomic
def archive_session(session: Session, *, by) -> Session:
    """§4.2, D-5: a session no longer due — completed, cancelled, at the
    administration's disposal, or scheduled and started (Plan 31 D15).
    Payroll-locked and compensated sessions too: archiving changes no number.
    Logged as `archive`, whose inverse is `unarchive_session`."""
    locked = lock(session)
    with activity.track(locked, by, activity.Action.ARCHIVE):
        if locked.archived_at is not None:
            raise _archived()
        if locked.status == Session.Status.SCHEDULED and not has_started(locked):
            raise ConflictError(STILL_AHEAD, code="scheduling.not_allowed_in_status")
        locked.archived_at = dates.now()
        locked.save(update_fields=["archived_at", "updated_at"])
    return locked


@transaction.atomic
def unarchive_session(session: Session, *, by) -> Session:
    """§4.2: back in the lists. While the subscription archive is on, a
    session whose subscription is archived is refused (restore the
    subscription); the subscription is read after the session's lock, never
    locked (a session write never locks a subscription after a session).
    It also forgets it came with its subscription (D-13). Logged as
    `unarchive`, whose inverse is `archive_session`."""
    locked = lock(session)
    with activity.track(locked, by, activity.Action.UNARCHIVE):
        if locked.archived_at is None:
            raise _not_archived()
        if (
            features.enabled(rules.SUBSCRIPTION_ARCHIVE)
            and Subscription.objects.filter(
                pk=locked.subscription_id, archived_at__isnull=False
            ).exists()
        ):
            raise _archived()
        locked.archived_at = None
        locked.archived_with_subscription = False
        locked.save(
            update_fields=["archived_at", "archived_with_subscription", "updated_at"]
        )
    return locked


def _bulk(ids: Iterable[int], by, one: Callable[..., Session]) -> BulkResult:
    """As `bulk_sessions`: every requested row locked up front in id order,
    then ``one`` per row in its own savepoint; a refusal's code is its skip
    code, an id this academy lacks is `not_found`."""
    ids = sorted(set(ids))
    if not 1 <= len(ids) <= MAX_BULK:
        raise ValidationError(f"Choose from 1 to {MAX_BULK} sessions.", field="ids")
    locked = set(
        Session.objects.select_for_update()
        .filter(pk__in=ids)
        .order_by("pk")
        .values_list("pk", flat=True)
    )
    result = BulkResult()
    for pk in ids:
        if pk not in locked:
            result.skipped.append((pk, "not_found"))
            continue
        try:
            with transaction.atomic():
                one(Session(pk=pk), by=by)
        except ConflictError as exc:
            result.skipped.append((pk, exc.code))
        else:
            result.done.append(pk)
    return result


@transaction.atomic
def archive_sessions(ids: Iterable[int], *, by) -> BulkResult:
    """§4.2: up to `MAX_BULK` sessions archived on their own."""
    return _bulk(ids, by, archive_session)


@transaction.atomic
def unarchive_sessions(ids: Iterable[int], *, by) -> BulkResult:
    """§4.2: up to `MAX_BULK` sessions back in the lists."""
    return _bulk(ids, by, unarchive_session)
```

- [ ] **Step 4: The inverses** (`services/revert.py`)

Import `from etqan.scheduling.services import archive` (with the other service imports). Before `# ── What each revert also needs`:

```python
def _unarchive(session, _entry, by) -> None:
    archive.unarchive_session(session, by=by)


def _rearchive(session, _entry, by) -> None:
    # Archived again now: the entry's instant is a record, not a value to
    # write back (C-5).
    archive.archive_session(session, by=by)
```

In `INVERSES` (and change the comment above it to "The five actions changed in bulk — three subscription-wide, the archive's two cascades — have no inverse (C-8, slice B2d §4.3)."):

```python
    # Slice B2d §4.3.
    Action.ARCHIVE: Inverse(
        _unarchive, _codes("session.restore"), _switches("session_archive")
    ),
    Action.UNARCHIVE: Inverse(
        _rearchive, _codes("session.delete"), _switches("session_archive")
    ),
```

`services/__init__.py`: export `archive_session`, `archive_sessions`, `unarchive_session`, `unarchive_sessions`.

- [ ] **Step 5: Run the tests, then the suites that count**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_archive_sessions.py etqan/scheduling/tests/test_archive_counting.py etqan/scheduling/tests/test_activity_revert.py etqan/scheduling/tests/test_paylock.py etqan/scheduling/tests/test_reports.py etqan/payroll etqan/billing`
Expected: PASS. Then `… ruff check . && … ruff format --check . && … lint-imports`.

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/scheduling/services/archive.py etqan/scheduling/services/revert.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_archive_sessions.py etqan/scheduling/tests/test_archive_counting.py
git -C backend commit -m "feat(scheduling): archive sessions on their own and in bulk, revertible (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 5: What an archived subscription or session refuses (D-7)

**Files:**
- Modify: `backend/etqan/scheduling/services/subscriptions.py` (`_lock_unarchived`; `renew_subscription`, `add_slots`, `update_slot`, `delete_slot`)
- Modify: `backend/etqan/scheduling/services/manual.py` (`create_regular_session`, `create_extra_session`, `create_compensation`)
- Modify: `backend/etqan/scheduling/services/postpone.py` (`postpone_session`, `can_postpone`)
- Test: `backend/etqan/scheduling/tests/test_archive_refusals.py`

**Interfaces:**
- Consumes: Task 2 (`rules.refuse_if_archived`, `rules.refuse_if_session_archived`, `rules.SESSION_ARCHIVE`), Task 3 (`ended`, `archive_subscription`), Task 4 (`archive_session`).
- Produces: no new names. Behaviour: while `subscription_archive` is on, an archived subscription answers 409 `scheduling.archived` — after its row lock, before any other refusal — to `renew_subscription`, `create_regular_session`, `create_extra_session` (when a subscription is given), `create_compensation` (on the original's subscription), `add_slots`, `update_slot`, `delete_slot`. While `session_archive` is on, `postpone_session` answers 409 `scheduling.archived` for an archived session (after its locks, before its status checks) and `can_postpone` is false. Off: today's behaviour.

- [ ] **Step 1: Write the failing tests** (`test_archive_refusals.py`)

```python
"""Slice B2d D-7, D-13: what an archived subscription or session refuses,
and only while its switch is on."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

import pytest

from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.services import rules
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db


@pytest.fixture
def admin():
    return make_admin()


@pytest.fixture
def archived(ended, admin, archives_on):
    services.archive_subscription(ended, by=admin)
    ended.refresh_from_db()
    return ended


def refused(call):
    with pytest.raises(ConflictError) as err:
        call()
    return err.value.code


def extra_for(archived, world, admin):
    return services.create_extra_session(
        by=admin,
        student_id=world.student.id,
        course_id=world.course.id,
        teacher_id=world.teacher.id,
        occurs_on=date(2026, 6, 10),
        start_time=time(10, 0),
        minutes=45,
        subscription_id=archived.pk,
    )


def test_no_session_is_added_against_it(archived, admin, world):
    past = Session.objects.filter(subscription=archived).order_by("pk").first()
    Session.objects.filter(pk=past.pk).update(status="cancelled")
    calls = [
        lambda: services.create_regular_session(
            by=admin,
            subscription_id=archived.pk,
            occurs_on=date(2026, 6, 10),
            start_time=time(10, 0),
        ),
        lambda: extra_for(archived, world, admin),
        lambda: services.create_compensation(
            by=admin,
            compensates_id=past.pk,
            occurs_on=date(2026, 6, 10),
            start_time=time(10, 0),
        ),
    ]
    assert [refused(call) for call in calls] == ["scheduling.archived"] * 3


def test_its_slots_take_no_change(archived):
    slot = archived.slots.first()
    calls = [
        lambda: services.add_slots(archived, weekdays=[4], start_time=time(9, 0)),
        lambda: services.update_slot(slot, is_active=False),
        lambda: services.delete_slot(slot),
    ]
    assert [refused(call) for call in calls] == ["scheduling.archived"] * 3


def test_an_archived_expired_subscription_is_not_renewed(
    subscribe, clock, admin, set_features, archives_on
):
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 4, 8, 0, tzinfo=UTC))
    rules.expire([sub.pk])
    services.archive_subscription(sub, by=admin)
    sub.refresh_from_db()
    # An expired subscription is renewable (Plan 4): the archive refuses first.
    assert refused(lambda: services.renew_subscription(sub)) == "scheduling.archived"
    set_features(subscription_archive=False)
    assert services.renew_subscription(sub).renewed_from_id == sub.pk


def test_the_refusals_stop_while_the_switch_is_off(
    archived, admin, world, set_features
):
    set_features(subscription_archive=False)
    services.update_slot(archived.slots.first(), is_active=False)
    assert extra_for(archived, world, admin).session.subscription_id == archived.pk
    # A cancelled one is never renewed: Plan 4's own rule, not the archive's.
    assert (
        refused(lambda: services.renew_subscription(archived))
        == "scheduling.not_allowed_in_status"
    )


def test_an_archived_session_is_not_postponed_while_the_switch_is_on(
    subscribe, clock, admin, set_features
):
    set_features(session_archive=True)
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 3, 19, 0, tzinfo=UTC))
    first = Session.objects.filter(subscription=sub).order_by("starts_at").first()
    services.archive_session(first, by=admin)
    row = services.sessions_queryset().get(pk=first.pk)
    assert services.can_postpone(row, admin, limit_minutes=0) is False

    def move():
        return services.postpone_session(
            first, by=admin, occurs_on=date(2026, 6, 5), start_time=time(20, 0)
        )

    assert refused(move) == "scheduling.archived"
    set_features(session_archive=False)
    row = services.sessions_queryset().get(pk=first.pk)
    assert services.can_postpone(row, admin, limit_minutes=0) is True
    assert move().session.occurs_on == date(2026, 6, 5)
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_archive_refusals.py`
Expected: FAIL (`scheduling.not_allowed_in_status` / `slot_has_sessions` where `scheduling.archived` is expected; the regular session is refused by status, the extra one is created; the postponement goes through). Keep the output.

- [ ] **Step 3: Subscriptions and slots** (`services/subscriptions.py`)

After `_refuse_if_marked`:

```python
def _lock_unarchived(subscription_id: int) -> Subscription:
    """Slice B2d §4.1 (Plan 31 D3): the subscription's row, locked first
    (Plan 4's order: generation re-locks it in the same transaction), and
    refused while archived."""
    locked = Subscription.objects.select_for_update().get(pk=subscription_id)
    rules.refuse_if_archived(locked)
    return locked
```

`add_slots` — first line of the body:

```python
    _lock_unarchived(subscription.pk)
    rules.require_status(subscription)
```

`update_slot` — right after `if not changes: return slot` and `subscription = slot.subscription`:

```python
    _lock_unarchived(subscription.pk)
```

`delete_slot` — becomes atomic and locks first:

```python
@transaction.atomic
def delete_slot(slot: ScheduleSlot) -> None:
    _lock_unarchived(slot.subscription_id)
    # Slice B2b: a session postponed from it remembers it too.
    if slot.sessions.exists() or slot.postponed_sessions.exists():
        raise ConflictError(
            "This slot has sessions. Deactivate it instead.",
            code="scheduling.slot_has_sessions",
        )
    slot.delete()
```

`renew_subscription` — after `old = Subscription.objects.select_for_update().get(pk=subscription.pk)`, before `rules.require_status(...)`:

```python
    # Slice B2d D-7: an archived subscription is restored before it renews.
    rules.refuse_if_archived(old)
```

- [ ] **Step 4: Sessions added by hand** (`services/manual.py`)

`create_regular_session` — after the `if sub is None:` refusal, before `rules.require_status(sub)`:

```python
    rules.refuse_if_archived(sub)  # slice B2d D-7
```

`create_extra_session` — inside `if subscription_id is not None:`, after its `if subscription is None:` refusal:

```python
        rules.refuse_if_archived(subscription)  # slice B2d D-7
```

`create_compensation` — replace `list(Subscription.objects.select_for_update().filter(pk=subscription_id))` with:

```python
    if subscription_id is not None:
        locked_sub = (
            Subscription.objects.select_for_update().filter(pk=subscription_id).first()
        )
        if locked_sub is not None:
            # Slice B2d D-7: no make-up against an archived subscription.
            rules.refuse_if_archived(locked_sub)
```

(the lock is the same row, taken at the same point, so B2a's lock order is unchanged).

- [ ] **Step 5: Postponement** (`services/postpone.py`)

Import `from etqan.platform import features`. In `postpone_session`, inside `with activity.track(...)`, as its first line (before `office = …`):

```python
        rules.refuse_if_session_archived(locked)  # slice B2d D-7
```

In `can_postpone`, after `if not office and _too_late(...)`:

```python
    if session.archived_at is not None and features.enabled(rules.SESSION_ARCHIVE):
        return False  # slice B2d D-7: postponing an archived session is refused
```

- [ ] **Step 6: Run the tests, then the suites of every touched service**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_archive_refusals.py etqan/scheduling/tests/test_subscriptions.py etqan/scheduling/tests/test_renewal.py etqan/scheduling/tests/test_session_classes_manual.py etqan/scheduling/tests/test_times_postponement_postpone.py etqan/scheduling/tests/test_api_subscriptions.py`
Expected: PASS (B2b's lock-capture tests count `FOR UPDATE` statements of `postpone_session` only; the slot services' new lock is a subscription row taken first). If a B2a/B2b SQL-capture test counts the slot services' locks, it now sees one more subscription lock first: update that assertion and say so in the report.

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/scheduling/services/subscriptions.py etqan/scheduling/services/manual.py etqan/scheduling/services/postpone.py etqan/scheduling/tests/test_archive_refusals.py
git -C backend commit -m "feat(scheduling): an archived subscription or session refuses changes while on (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The Today board leaves archived sessions out

**Files:**
- Modify: `backend/etqan/scheduling/services/board.py`
- Test: `backend/etqan/scheduling/tests/test_archive_board.py`

**Interfaces:**
- Consumes: Task 2 (`rules.SESSION_ARCHIVE`), Task 4 (`archive_session`), conftest `postponed`.
- Produces: `today_board(day)` unchanged in shape. While `session_archive` is on: an archived session never makes a slot "have a session" that day, a slot row whose session (or B2b's postponed-away session) is archived is left out entirely, and an archived session postponed into the day gets no session-only row. Off: today's board.

- [ ] **Step 1: Write the failing tests** (`test_archive_board.py`)

```python
"""Slice B2d §4.4 Today board: a row whose session is archived is left out
(a row with no session would read `missing` and invite generating a slot
date that exists); B2b's postponed and session-only rows follow suit."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import postponed
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
MONDAY = date(2026, 6, 1)


@pytest.fixture
def admin():
    return make_admin()


def board(day=MONDAY):
    return services.today_board(day)


def test_a_slot_whose_session_is_archived_is_left_out(
    subscribe, clock, admin, archives_on
):
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 1, 19, 0, tzinfo=UTC))
    monday = Session.objects.get(subscription=sub, occurs_on=MONDAY)
    assert [(r.session.pk, r.state) for r in board()] == [(monday.pk, "generated")]
    services.archive_session(monday, by=admin)
    assert board() == []


def test_an_ended_subscriptions_slot_goes_with_its_archived_session(
    subscribe, clock, admin, archives_on
):
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 1, 19, 0, tzinfo=UTC))
    services.cancel_subscription(sub)  # Monday's has started: it stays
    assert [r.state for r in board()] == ["generated"]
    services.archive_session(Session.objects.get(subscription=sub), by=admin)
    assert board() == []


def test_b2bs_postponed_rows_follow_the_same_rule(
    subscribe, clock, admin, archives_on
):
    sub = subscribe(slots=two_slots())
    moved = postponed(sub)  # Wednesday 3 → Thursday 4 June, 20:00
    assert [r.state for r in board(date(2026, 6, 3))] == ["postponed"]
    assert [r.session.pk for r in board(date(2026, 6, 4))] == [moved.pk]
    clock.set(datetime(2026, 6, 4, 21, 0, tzinfo=UTC))
    services.archive_session(moved, by=admin)
    assert board(date(2026, 6, 3)) == []
    assert board(date(2026, 6, 4)) == []


def test_an_archived_session_shows_again_while_the_switch_is_off(
    subscribe, clock, admin, archives_on, set_features
):
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 1, 19, 0, tzinfo=UTC))
    monday = Session.objects.get(subscription=sub, occurs_on=MONDAY)
    services.archive_session(monday, by=admin)
    set_features(session_archive=False)
    assert [(r.session.pk, r.state) for r in board()] == [(monday.pk, "generated")]
    set_features(session_archive=True)
    assert board() == []
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_archive_board.py`
Expected: FAIL (the archived rows are still on the board). Keep the output.

- [ ] **Step 3: Implement** (`services/board.py`)

Import `from etqan.platform import features`. In `today_board`, right after `zone = ZoneInfo(academy.timezone)`:

```python
    # Slice B2d §4.4: while the session archive is on, an archived session is
    # not the slot's session that day, and its row is left out (FT-4: off,
    # the board is as before).
    shown = {"archived_at__isnull": True} if features.enabled(rules.SESSION_ARCHIVE) else {}
    has_session = Exists(
        Session.objects.filter(slot=OuterRef("pk"), occurs_on=day, **shown)
    )
    moved_away = Exists(
        Session.objects.filter(original_slot=OuterRef("pk"), original_on=day, **shown)
    )
```

`moved_in`'s `.filter(...)` gains `**shown`. In the slot loop, right after `postponed = away.get(slot.pk) if session is None else None`:

```python
        if shown and _archived(session or postponed):
            continue
```

and, below `STATES`:

```python
def _archived(session: Session | None) -> bool:
    return session is not None and session.archived_at is not None
```

(The `sessions` and `away` maps still read every session of the slots, archived ones included: an archived session must drop its row, not turn it into `missing`.) If ruff's C901 flags `today_board`, move the slot loop into `_slot_rows(slots, day, sessions, away, derived, academy, shown) -> list[TodayRow]` unchanged.

- [ ] **Step 4: Run the tests and the board's suites**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_archive_board.py etqan/scheduling/tests/test_today.py etqan/scheduling/tests/test_times_postponement_board.py etqan/scheduling/tests/test_api_schedule.py`
Expected: PASS (their query counts unchanged: the filter is inside the same statements).

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/scheduling/services/board.py etqan/scheduling/tests/test_archive_board.py
git -C backend commit -m "feat(scheduling): the Today board leaves archived sessions out (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 7: The lists — the `archived` parameter, the new filters, payload fields and CSV columns

**Files:**
- Create: `backend/etqan/scheduling/api/archived.py`
- Modify: `backend/etqan/scheduling/api/views.py` (`subscription_filters`, `_as_date`; `SubscriptionListView.get` and `csv_columns`; the old `filter_subscriptions` goes)
- Modify: `backend/etqan/scheduling/api/session_views.py` (`SessionListView.get` and `csv_columns`)
- Modify: `backend/etqan/scheduling/api/serializers.py` (`SessionFilterInput`)
- Modify: `backend/etqan/scheduling/api/payloads.py` (`subscription_row`, `subscription_detail`, `session_row`)
- Test: `backend/etqan/scheduling/tests/test_api_archive_lists.py`

**Interfaces:**
- Consumes: Task 2 (`services.filter_subscriptions`, `services.filter_sessions(archived=…)`, `services.archivable`, `services.ARCHIVED_MODES`), Tasks 3–4 (to build fixtures).
- Produces:
  - `api.archived.archived_mode(request, feature: str) -> str` (`"exclude" | "only" | "include"`; raises DRF `NotFound` / `ValidationError`).
  - `api.views.subscription_filters(params) -> dict` (the keyword arguments of `filter_subscriptions` but `archived`).
  - Subscription row (office, `subscription_archive` on): `archived_at: str | null`, `can_archive: bool`; detail adds `archived_by: {id, full_name} | null`. Session row (office, `session_archive` on): `archived_at: str | null`, `ends_at: str`. Subscriptions CSV adds `("archived_at", "Archived at (UTC)")` last while on; sessions CSV adds `("ends_at", "Ends at (UTC)")` after `starts_at` and `("archived_at", "Archived at (UTC)")` last while on.

- [ ] **Step 1: Write the failing tests** (`test_api_archive_lists.py`)

```python
"""Slice B2d §4.4, §5, §6.1: the office's lists, the archive's parameters,
the new filters, the payload fields and the CSV columns."""

import csv
import io
from datetime import UTC
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.platform.permissions import FEATURE_OFF
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import as_user
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
SUBS = "/api/v1/subscriptions/"
SESSIONS = "/api/v1/sessions/"
NOW = "2026-06-04T08:00:00Z"  # the `ended` fixture's clock


@pytest.fixture
def admin():
    return make_admin()


@pytest.fixture
def archived(ended, admin, archives_on):
    services.archive_subscription(ended, by=admin)
    return ended


def ids(response):
    assert response.status_code == 200, response.content
    return [row["id"] for row in response.json()["results"]]


def table(response):
    assert response.status_code == 200, response.content
    return list(csv.reader(io.StringIO(response.content.decode("utf-8-sig"))))


def cost(client, url, query):
    with CaptureQueriesContext(connection) as ctx:
        rows = client.get(url, query).json()["results"]
    return len(rows), len(ctx.captured_queries)


def test_the_office_lists_leave_archived_rows_out(archived, subscribe, admin):
    live = subscribe(slots=two_slots())
    office = as_user(admin)
    assert ids(office.get(SUBS)) == [live.pk]
    only = office.get(SUBS, {"archived": "only"}).json()["results"]
    assert [row["id"] for row in only] == [archived.pk]
    assert (only[0]["archived_at"], only[0]["can_archive"]) == (NOW, False)
    assert set(ids(office.get(SUBS, {"archived": "include"}))) == {
        live.pk,
        archived.pk,
    }
    gone = set(
        Session.objects.filter(subscription=archived).values_list("pk", flat=True)
    )
    shown = set(ids(office.get(SESSIONS)))
    assert shown
    assert not shown & gone
    assert set(ids(office.get(SESSIONS, {"archived": "only"}))) == gone


def test_can_archive_says_what_the_archive_would_take(
    ended, subscribe, admin, archives_on
):
    live = subscribe(slots=two_slots())
    rows = {row["id"]: row for row in as_user(admin).get(SUBS).json()["results"]}
    assert (rows[ended.pk]["can_archive"], rows[live.pk]["can_archive"]) == (
        True,
        False,
    )


def test_the_detail_names_who_archived_it(archived, admin):
    body = as_user(admin).get(f"{SUBS}{archived.pk}/").json()
    assert body["archived_at"] == NOW
    assert body["archived_by"] == {"id": admin.pk, "full_name": "Amina"}


def test_a_subscriptions_own_sessions_keep_their_archived_rows(archived, admin):
    rows = as_user(admin).get(f"{SUBS}{archived.pk}/sessions/").json()["results"]
    assert len(rows) == 2
    assert {row["archived_at"] for row in rows} == {NOW}
    assert rows[0]["ends_at"]


@pytest.mark.parametrize("param", ["archived", "archived_from", "archived_to"])
def test_only_the_office_asks_about_the_archive(archived, world, param):
    value = "only" if param == "archived" else "2026-06-01"
    for user in (world.student, world.teacher):
        client = as_user(user)
        assert client.get(SUBS, {param: value}).status_code == 404
        assert client.get(SESSIONS, {param: value}).status_code == 404
    rows = as_user(world.student).get(SUBS).json()["results"]
    assert [row["id"] for row in rows] == [archived.pk]
    assert "archived_at" not in rows[0]
    sessions = as_user(world.teacher).get(SESSIONS).json()["results"]
    assert len(sessions) == 2
    assert "archived_at" not in sessions[0]


def test_switching_the_archive_off_shows_everything_again(
    archived, admin, set_features
):
    office = as_user(admin)
    set_features(subscription_archive=False, session_archive=False)
    rows = office.get(SUBS).json()["results"]
    assert [row["id"] for row in rows] == [archived.pk]
    assert "archived_at" not in rows[0]
    assert "can_archive" not in rows[0]
    assert "archived_by" not in office.get(f"{SUBS}{archived.pk}/").json()
    sessions = office.get(SESSIONS).json()["results"]
    assert len(sessions) == 2
    assert "archived_at" not in sessions[0]
    for url in (SUBS, SESSIONS):
        response = office.get(url, {"archived": "only"})
        assert (response.status_code, response.json()) == (404, {"detail": FEATURE_OFF})
    set_features(subscription_archive=True, session_archive=True)
    assert ids(office.get(SUBS)) == []
    assert ids(office.get(SESSIONS)) == []


def test_an_unknown_mode_is_a_field_error(archived, admin):
    for url in (SUBS, SESSIONS):
        response = as_user(admin).get(url, {"archived": "all"})
        assert response.status_code == 400
        assert "archived" in response.json()


def test_the_archive_filters_reach_the_lists(archived, admin):
    office = as_user(admin)
    only = {"archived": "only"}
    assert ids(office.get(SUBS, {**only, "archived_from": "2026-06-04"})) == [
        archived.pk
    ]
    assert ids(office.get(SUBS, {**only, "archived_to": "2026-06-03"})) == []
    assert ids(office.get(SUBS, {**only, "created_from": "2099-01-01"})) == []
    assert len(ids(office.get(SESSIONS, {**only, "archived_from": "2026-06-04"}))) == 2
    assert ids(office.get(SESSIONS, {**only, "archived_to": "2026-06-03"})) == []
    bad = office.get(SESSIONS, {**only, "archived_from": "soon"})
    assert bad.status_code == 400
    assert "archived_from" in bad.json()


def test_the_csvs_add_the_archive_columns_only_while_on(
    archived, admin, set_features
):
    office = as_user(admin)
    subs = table(office.get(SUBS, {"format": "csv", "archived": "only"}))
    assert (subs[0][-1], subs[1][-1]) == (
        "Archived at (UTC)",
        "2026-06-04 08:00:00+00:00",
    )
    sessions = table(office.get(SESSIONS, {"format": "csv", "archived": "only"}))
    header = sessions[0]
    assert header[header.index("Starts at (UTC)") + 1] == "Ends at (UTC)"
    assert "Kind" in header
    assert header[-1] == "Archived at (UTC)"
    assert sessions[1][header.index("Ends at (UTC)")] == "2026-06-01 18:45:00+00:00"
    set_features(subscription_archive=False, session_archive=False)
    assert "Archived at (UTC)" not in table(office.get(SUBS, {"format": "csv"}))[0]
    header = table(office.get(SESSIONS, {"format": "csv"}))[0]
    assert "Ends at (UTC)" not in header
    assert "Archived at (UTC)" not in header


def test_the_subscription_archive_costs_the_same_for_1_and_5_rows(
    world, admin, archives_on
):
    for _ in range(5):
        sub = subscription_for(world)
        services.cancel_subscription(sub)
        services.archive_subscription(sub, by=admin)
    office = as_user(admin)
    one = cost(office, SUBS, {"archived": "only", "page_size": 1})
    five = cost(office, SUBS, {"archived": "only"})
    assert (one[0], five[0]) == (1, 5)
    assert one[1] == five[1]


def test_the_session_archive_costs_the_same_for_1_and_5_rows(
    subscribe, clock, admin, archives_on
):
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 16, 8, 0, tzinfo=UTC))  # all five have started
    pks = list(Session.objects.filter(subscription=sub).values_list("pk", flat=True))
    assert services.archive_sessions(pks, by=admin).done == sorted(pks)
    office = as_user(admin)
    one = cost(office, SESSIONS, {"archived": "only", "page_size": 1})
    five = cost(office, SESSIONS, {"archived": "only"})
    assert (one[0], five[0]) == (1, 5)
    assert one[1] == five[1]
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_archive_lists.py`
Expected: FAIL (archived rows in the default lists; `KeyError: 'archived_at'`; 200 where 404 is expected). Keep the output.

- [ ] **Step 3: `api/archived.py`**

```python
"""Slice B2d §4.4, §5: what a list does with archived rows, decided per
caller in the views that serve every role."""

from rest_framework.exceptions import NotFound
from rest_framework.exceptions import ValidationError

from etqan.platform import features
from etqan.platform.permissions import FEATURE_OFF
from etqan.platform.permissions import is_office
from etqan.scheduling import services

# Plan 31 D5: the archive's own parameters.
ARCHIVE_PARAMS = ("archived", "archived_from", "archived_to")


def archived_mode(request, feature: str) -> str:
    """The office's default leaves archived rows out while ``feature`` is
    on; everyone else sees their own rows as before. The archive's
    parameters are the office's alone (404 for anyone else, §5, Plan 31
    D12) and exist only while ``feature`` is on (404, FT-4)."""
    params = request.query_params
    asked = any(name in params for name in ARCHIVE_PARAMS)
    office = is_office(request.user)
    on = features.enabled(feature)
    if asked and not office:
        raise NotFound
    if asked and not on:
        raise NotFound(FEATURE_OFF)
    if not (office and on):
        return "include"
    mode = params.get("archived", "exclude")
    if mode not in services.ARCHIVED_MODES:
        raise ValidationError({"archived": ["Choose exclude, only or include."]})
    return mode
```

- [ ] **Step 4: The subscriptions list** (`api/views.py`)

Delete the view's `filter_subscriptions` (its logic now lives in `rules.filter_subscriptions`) and the `Q` import if nothing else uses it. Add `from datetime import date` and `from etqan.scheduling.api.archived import archived_mode`. Then:

```python
ARCHIVE_COLUMN = ("archived_at", "Archived at (UTC)")
DAY_FILTERS = ("archived_from", "archived_to", "created_from", "created_to")


def _as_date(value: str) -> date | None:
    """A day the list can read, else None (ignored, like a bad id)."""
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def subscription_filters(params) -> dict:
    """The list's query as `filter_subscriptions` takes it, but `archived`
    (`archived_mode` decides it). A value it can't read is ignored, as the
    list always did (Plan 4)."""
    status = params.get("status")
    return {
        "status": status if status in STATUSES else "",
        "student": _as_int(params.get("student", "")),
        "teacher": _as_int(params.get("teacher", "")),
        "course": _as_int(params.get("course", "")),
        "q": params.get("q", ""),
        **{key: _as_date(params.get(key, "")) for key in DAY_FILTERS},
    }
```

In `SubscriptionListView`:

```python
    @property
    def csv_columns(self):
        columns = CSV_COLUMNS
        if not features.enabled("invoices"):
            columns = tuple(c for c in columns if c[0] not in INVOICE_COLUMNS)
        if features.enabled("subscription_archive"):
            columns = (*columns, ARCHIVE_COLUMN)  # slice B2d §6.1
        return columns

    def get(self, request):
        queryset = services.filter_subscriptions(
            subscriptions_in_scope(request),
            archived=archived_mode(request, "subscription_archive"),
            **subscription_filters(request.query_params),
        )
        if self.wants_csv():
            # CSV export is office (admin or staff) only (controller ruling):
            # anyone else asking for ?format=csv is refused, never handed a
            # CSV body.
            # Raised (not returned) so CSVExportMixin.finalize_response swaps
            # the renderer back to JSON for the error body.
            if not _is_office(request):
                raise PermissionDenied("CSV export is for admins and staff only.")
            rows = payloads.subscription_rows(
                queryset, is_admin=True, supervision=False
            )
            return self.csv_response(rows)
        page = self.paginate_queryset(queryset)
        rows = payloads.subscription_rows(
            page,
            is_admin=_is_office(request),
            supervision=payloads.shows_supervision(request.user),
        )
        return self.get_paginated_response(rows)
```

- [ ] **Step 5: The sessions list** (`api/session_views.py`, `api/serializers.py`)

`SessionFilterInput` gains, after `q`:

```python
    # Slice B2d §6.1: the archive's days (academy dates); `archived` itself
    # is read by `archived_mode`.
    archived_from = serializers.DateField(required=False)
    archived_to = serializers.DateField(required=False)
```

In `session_views.py`, import `from etqan.scheduling.api.archived import archived_mode`; add the columns and use them:

```python
# Slice B2d §6.1 (Plan 31 D6): while the session archive is on; `kind` is
# already a column.
ENDS_COLUMN = ("ends_at", "Ends at (UTC)")
ARCHIVE_COLUMN = ("archived_at", "Archived at (UTC)")
```

```python
    @property
    def csv_columns(self):
        columns = CSV_COLUMNS
        if not features.enabled("session_reports"):
            columns = tuple(c for c in columns if c[0] not in REPORT_COLUMNS)
        if features.enabled("session_archive"):
            at = [key for key, _ in columns].index("starts_at") + 1
            columns = (*columns[:at], ENDS_COLUMN, *columns[at:], ARCHIVE_COLUMN)
        return columns

    def get(self, request):
        # CSV export is office (admin or staff) only (controller ruling):
        # checked before the filter is validated, so a bad filter plus csv
        # from anyone else is still 403, not 400.
        if self.wants_csv() and not is_office(request.user):
            raise PermissionDenied("CSV export is for admins and staff only.")
        # Slice B2d §4.4: the office's default hides archived sessions.
        archived = archived_mode(request, "session_archive")
        query = SessionFilterInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        sessions = services.filter_sessions(
            sessions_in_scope(request), archived=archived, **query.validated_data
        )
        viewer = request.user
        limit = payloads.postpone_limit_for(viewer)
        if self.wants_csv():
            return self.csv_response(
                [
                    payloads.session_row(
                        s, viewer=viewer, supervision=False, postpone_limit=limit
                    )
                    for s in sessions
                ]
            )
        shown = payloads.shows_supervision(viewer)
        page = self.paginate_queryset(sessions)
        return self.get_paginated_response(
            [
                payloads.session_row(
                    s, viewer=viewer, supervision=shown, postpone_limit=limit
                )
                for s in page
            ]
        )
```

- [ ] **Step 6: The payload fields** (`api/payloads.py`)

In `subscription_row`, after the `if supervision:` block:

```python
    if is_admin and features.enabled("subscription_archive"):
        # Slice B2d §6.1, plan D2: the office's, while the archive is on.
        row["archived_at"] = sub.archived_at
        row["can_archive"] = services.archivable(sub)
```

In `subscription_detail`, before `if not is_admin:`:

```python
    if is_admin and features.enabled("subscription_archive"):
        detail["archived_by"] = _user(sub.archived_by)
```

In `session_row`, after `_add_times_and_postponement(...)`:

```python
    if is_office(viewer) and features.enabled("session_archive"):
        # Slice B2d §6.1 (Plan 31 D6): the office's, while the archive is on.
        row["archived_at"] = session.archived_at
        row["ends_at"] = session.starts_at + timedelta(minutes=session.minutes)
```

- [ ] **Step 7: Run the tests and every list's suite**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_archive_lists.py etqan/scheduling/tests/test_api_subscriptions.py etqan/scheduling/tests/test_api_sessions.py etqan/scheduling/tests/test_api_session_classes.py etqan/scheduling/tests/test_api_supervision.py etqan/billing`
Expected: PASS. Then `… ruff check . && … ruff format --check . && … lint-imports`.

- [ ] **Step 8: Commit**

```bash
git -C backend add etqan/scheduling/api/archived.py etqan/scheduling/api/views.py etqan/scheduling/api/session_views.py etqan/scheduling/api/serializers.py etqan/scheduling/api/payloads.py etqan/scheduling/tests/test_api_archive_lists.py
git -C backend commit -m "feat(scheduling): office lists hide archived rows; archive filters and columns (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The archive routes, the codes in use and the route table

**Files:**
- Create: `backend/etqan/scheduling/api/archive_views.py`
- Modify: `backend/etqan/scheduling/api/serializers.py` (`ArchiveInput`), `backend/etqan/scheduling/api/urls.py`
- Modify: `backend/etqan/access/registry.py` (`subscription` and `session` `in_use` + `restore`)
- Modify: `backend/etqan/access/tests/test_routes.py` (`ROUTES`, `FEATURES`, `FEATURE_WORDS`)
- Test: `backend/etqan/scheduling/tests/test_api_archive_routes.py`

**Interfaces:**
- Consumes: Tasks 3–4's services, B2c's `OfficeOr404` (`api/activity_views.py`), `views.detail`, `views.subscription_or_404`, `payloads.bulk_result`.
- Produces: `POST|DELETE /api/v1/subscriptions/<pk>/archive/` → `200` subscription detail; `POST /api/v1/sessions/archive/` and `/api/v1/sessions/unarchive/` with `{"ids": [int]}` → `200 {"done": [int], "skipped": [{"id", "code"}]}`. Codes in use: `subscription.restore`, `session.restore`.

- [ ] **Step 1: Write the failing tests** (`test_api_archive_routes.py`)

```python
"""Slice B2d §5–§6: the archive routes and who reaches them."""

import pytest
from django.db.models import Max
from django_tenants.utils import tenant_context

from etqan.identity import services as identity_services
from etqan.platform.permissions import FEATURE_OFF
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.tests.conftest import as_user
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots
from etqan.scheduling.tests.conftest import until_pk_exceeds

pytestmark = pytest.mark.django_db
SUBS = "/api/v1/subscriptions/"
ARCHIVE = "/api/v1/sessions/archive/"
UNARCHIVE = "/api/v1/sessions/unarchive/"
NOW = "2026-06-04T08:00:00Z"


@pytest.fixture
def admin():
    return make_admin()


def archive_url(sub):
    return f"{SUBS}{sub.pk}/archive/"


def past_sessions(sub):
    return list(Session.objects.filter(subscription=sub).order_by("pk"))


def test_the_office_archives_and_restores_a_subscription(ended, admin, archives_on):
    office = as_user(admin)
    response = office.post(archive_url(ended))
    assert response.status_code == 200
    body = response.json()
    assert (body["id"], body["archived_at"], body["archived_by"]) == (
        ended.pk,
        NOW,
        {"id": admin.pk, "full_name": "Amina"},
    )
    restored = office.delete(archive_url(ended))
    assert restored.status_code == 200
    assert (restored.json()["archived_at"], restored.json()["archived_by"]) == (
        None,
        None,
    )


def test_the_refusals_reach_the_api(ended, subscribe, admin, archives_on):
    office = as_user(admin)
    live = subscribe(slots=two_slots())
    for response, code in (
        (office.post(archive_url(live)), "scheduling.not_allowed_in_status"),
        (office.delete(archive_url(ended)), "scheduling.not_archived"),
    ):
        assert (response.status_code, response.json()["code"]) == (409, code)


def test_the_office_archives_and_restores_sessions_in_bulk(ended, admin, archives_on):
    first, second = past_sessions(ended)
    office = as_user(admin)
    done = office.post(ARCHIVE, {"ids": [first.pk, 999999]}, format="json")
    assert done.json() == {
        "done": [first.pk],
        "skipped": [{"id": 999999, "code": "not_found"}],
    }
    back = office.post(UNARCHIVE, {"ids": [first.pk, second.pk]}, format="json")
    assert back.json() == {
        "done": [first.pk],
        "skipped": [{"id": second.pk, "code": "scheduling.not_archived"}],
    }
    assert office.post(ARCHIVE, {"ids": []}, format="json").status_code == 400


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_teachers_students_and_parents_get_404(ended, world, archives_on, role):
    if role == "parent":
        user = identity_services.create_person("parent", full_name="Omar")
        identity_services.link_guardian(user, world.student)
    else:
        user = {"teacher": world.teacher, "student": world.student}[role]
    client = as_user(user)
    ids = {"ids": [past_sessions(ended)[0].pk]}
    for response in (
        client.post(archive_url(ended)),
        client.delete(archive_url(ended)),
        client.post(ARCHIVE, ids, format="json"),
        client.post(UNARCHIVE, ids, format="json"),
    ):
        assert response.status_code == 404
    ended.refresh_from_db()
    assert ended.archived_at is None


def test_staff_need_the_code_of_each_way(ended, staff_for, archives_on):
    archiver = staff_for("subscription.delete")
    assert archiver.post(archive_url(ended)).status_code == 200
    assert archiver.delete(archive_url(ended)).status_code == 403
    assert staff_for("subscription.restore").delete(archive_url(ended)).status_code == 200
    ids = {"ids": [past_sessions(ended)[0].pk]}
    assert staff_for("session.restore").post(ARCHIVE, ids, format="json").status_code == 403
    assert staff_for("session.delete").post(ARCHIVE, ids, format="json").status_code == 200


def test_switched_off_the_routes_404_after_the_permission_check(
    ended, admin, staff_for
):
    office = as_user(admin)
    for response in (
        office.post(archive_url(ended)),
        office.post(ARCHIVE, {"ids": [1]}, format="json"),
    ):
        assert (response.status_code, response.json()) == (404, {"detail": FEATURE_OFF})
    assert staff_for("session.view_any").post(archive_url(ended)).status_code == 403


def test_permanent_delete_keeps_plan_4s_rule_from_the_archive(
    ended, admin, archives_on
):
    office = as_user(admin)
    office.post(archive_url(ended))
    first = past_sessions(ended)[0]
    services.mark_attendance(first, by=admin, student_attendance="present")
    refused = office.delete(f"{SUBS}{ended.pk}/")
    assert (refused.status_code, refused.json()["code"]) == (
        409,
        "scheduling.has_marked_sessions",
    )
    services.mark_attendance(first, by=admin, student_attendance="not_set")
    assert office.delete(f"{SUBS}{ended.pk}/").status_code == 204
    assert not Subscription.objects.filter(pk=ended.pk).exists()


def test_another_academys_rows_are_out_of_reach(
    ended, admin, tenants, set_features, archives_on
):
    sub_ceiling = Subscription.objects.aggregate(m=Max("pk"))["m"]
    session_ceiling = Session.objects.aggregate(m=Max("pk"))["m"]
    with tenant_context(tenants.other):
        set_features(
            academy=tenants.other, subscription_archive=True, session_archive=True
        )
        other = build_world()
        theirs = until_pk_exceeds(
            Session,
            session_ceiling,
            lambda: until_pk_exceeds(
                Subscription,
                sub_ceiling,
                lambda: subscription_for(other, slots=two_slots()),
            ),
        )
        their_session = Session.objects.filter(subscription=theirs).order_by("pk")[0]
    assert theirs.pk > sub_ceiling
    assert their_session.pk > session_ceiling
    office = as_user(admin)
    assert office.post(archive_url(theirs)).status_code == 404
    response = office.post(ARCHIVE, {"ids": [their_session.pk]}, format="json")
    assert response.json() == {
        "done": [],
        "skipped": [{"id": their_session.pk, "code": "not_found"}],
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_archive_routes.py`
Expected: FAIL (404 everywhere: the routes don't exist). Keep the output.

- [ ] **Step 3: The body** (`api/serializers.py`, after `BulkInput`)

```python
class ArchiveInput(serializers.Serializer):
    """Slice B2d §6: the sessions to archive or restore."""

    ids = serializers.ListField(child=_id(), allow_empty=False, max_length=200)
```

- [ ] **Step 4: The views** (`api/archive_views.py`)

```python
"""Slice B2d §5–§6: archiving and restoring subscriptions and sessions. The
office only: everyone else gets 404, before the code check (§5); a
switched-off archive's routes 404 after it."""

from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.scheduling import services
from etqan.scheduling.api import payloads
from etqan.scheduling.api.activity_views import OfficeOr404
from etqan.scheduling.api.serializers import ArchiveInput
from etqan.scheduling.api.views import detail
from etqan.scheduling.api.views import subscription_or_404


class SubscriptionArchiveView(APIView):
    """POST archives — `subscription.delete`, TutorHamster's "delete keeping
    records" (D-10); DELETE restores — `subscription.restore`."""

    permission_classes = [OfficeOr404, HasCode, FeatureOn]
    permission_codes = {
        "POST": "subscription.delete",
        "DELETE": "subscription.restore",
    }
    feature = "subscription_archive"

    def post(self, request, pk):
        sub = subscription_or_404(request, pk)
        services.archive_subscription(sub, by=request.user)
        return detail(pk, request)

    def delete(self, request, pk):
        sub = subscription_or_404(request, pk)
        services.restore_subscription(sub, by=request.user)
        return detail(pk, request)


class _SessionShelfView(APIView):
    permission_classes = [OfficeOr404, HasCode, FeatureOn]
    feature = "session_archive"
    service = None

    def post(self, request):
        body = ArchiveInput(data=request.data)
        body.is_valid(raise_exception=True)
        result = self.service(body.validated_data["ids"], by=request.user)
        return Response(payloads.bulk_result(result))


class SessionArchiveView(_SessionShelfView):
    permission_codes = {"POST": "session.delete"}
    service = staticmethod(services.archive_sessions)


class SessionUnarchiveView(_SessionShelfView):
    permission_codes = {"POST": "session.restore"}
    service = staticmethod(services.unarchive_sessions)
```

`api/urls.py`: import `archive_views` with the other view modules; after `subscriptions/<int:pk>/cancel/`:

```python
    # Slice B2d (spec §6).
    path(
        "subscriptions/<int:pk>/archive/",
        archive_views.SubscriptionArchiveView.as_view(),
        name="archive",
    ),
```

and after B2c's two session routes:

```python
    # Slice B2d (spec §6).
    path(
        "sessions/archive/",
        archive_views.SessionArchiveView.as_view(),
        name="session-archive",
    ),
    path(
        "sessions/unarchive/",
        archive_views.SessionUnarchiveView.as_view(),
        name="session-unarchive",
    ),
```

- [ ] **Step 5: The codes in use** (`access/registry.py`)

```python
    # Slice B2d: `restore` is in use (the archive).
    Resource(
        "subscription", "Subscriptions", "الاشتراكات", (*EDIT, "delete", "restore")
    ),
    Resource(
        "session",
        "Sessions",
        "الحصص",
        # Slice B2a: `delete` is in use (hand-added sessions); slice B2d:
        # `delete` also archives and `restore` brings back (D-10).
        (*EDIT, "delete", "restore", SUPERVISE[0]),
        verbs=(*ALL_VERBS, SUPERVISE[0]),
    ),
```

- [ ] **Step 6: The route table** (`access/tests/test_routes.py`)

In `ROUTES`, after B2c's two lines:

```python
    # Slice B2d.
    ("POST", f"/api/v1/subscriptions/{N}/archive/", "subscription.delete"),
    ("DELETE", f"/api/v1/subscriptions/{N}/archive/", "subscription.restore"),
    ("POST", "/api/v1/sessions/archive/", "session.delete"),
    ("POST", "/api/v1/sessions/unarchive/", "session.restore"),
```

In `FEATURES`, after B2c's two lines:

```python
    # Slice B2d.
    ("POST", f"/api/v1/subscriptions/{N}/archive/"): "subscription_archive",
    ("DELETE", f"/api/v1/subscriptions/{N}/archive/"): "subscription_archive",
    ("POST", "/api/v1/sessions/archive/"): "session_archive",
    ("POST", "/api/v1/sessions/unarchive/"): "session_archive",
```

In `FEATURE_WORDS`, after B2c's line:

```python
    # Slice B2d. ("/archive/" alone would also match the subscription route,
    # which FEATURES names.)
    "/sessions/archive/": "session_archive",
    "/unarchive/": "session_archive",
```

- [ ] **Step 7: Run the API tests, the route table and the whole backend once**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_archive_routes.py etqan/access` → PASS. Then the full verify: `… pytest -q --cov=etqan` (≥ 80 %), `… ruff check .`, `… ruff format --check .`, `… lint-imports`.

- [ ] **Step 8: Commit**

```bash
git -C backend add etqan/scheduling/api/archive_views.py etqan/scheduling/api/serializers.py etqan/scheduling/api/urls.py etqan/access/registry.py etqan/access/tests/test_routes.py etqan/scheduling/tests/test_api_archive_routes.py
git -C backend commit -m "feat(scheduling): archive and restore routes, office only (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 9: Demo seeds

**Files:**
- Modify: `backend/etqan/tenants/seeds/b2.py` (`ARCHIVES`, `ARCHIVE_SWITCHES`, `seed_archives`)
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (one call in the B2 block)
- Modify: `backend/etqan/tenants/tests/test_seed_b2.py` (new test; one B2c assertion reads only the everyday sessions)
- Modify: `backend/etqan/tenants/tests/test_seed_dev.py` (three scheduling-seed tests read only the everyday rows — plan D9)

**Interfaces:**
- Consumes: `scheduling_services.create_subscription`, `generate`, `run_lifecycle`, `sessions_of`, `cancel_session`, `archive_session`, `archive_subscription`, `subscriptions_queryset`, `today`; `catalogue_services.find_course`, `find_package`; `b2._person`.
- Produces: `b2.seed_archives(subdomain: str) -> None`; `b2.ARCHIVES = {"demo": {...}}`; `b2.ARCHIVE_SWITCHES = ("subscription_archive", "session_archive")`. Demo gains one expired, archived Tajweed subscription of Aisha Omar with four past sessions, all archived, the first cancelled and archived on its own (`archived_with_subscription` false). It acts as the system (`by=None`), as B2a's and B2b's seeds do, so B2c's "the demo admin's entries" marker is untouched.

- [ ] **Step 1: Failing test** (append to `test_seed_b2.py`)

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_demo_gets_an_archived_subscription_and_a_session_archived_alone_once():
    """Slice B2d §8 (Plan 31 D9)."""
    call_command("seed_dev")
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        assert all(
            features.enabled(code)
            for code in (*b2.ARCHIVE_SWITCHES, "simplified_sessions")
        )
        subs = scheduling_services.subscriptions_queryset()
        (sub,) = subs.filter(archived_at__isnull=False)
        assert (sub.status, sub.student.user.full_name, sub.course.name_en) == (
            "expired",
            "Aisha Omar",
            "Tajweed",
        )
        assert sub.archived_by_id is None  # the system
        sessions = list(scheduling_services.sessions_of(sub))
        assert len(sessions) == 4
        assert all(s.archived_at is not None for s in sessions)
        alone = [s for s in sessions if not s.archived_with_subscription]
        assert [(s.pk, s.status) for s in alone] == [(sessions[0].pk, "cancelled")]
        assert subs.filter(student__user_id=sub.student.user_id, course=sub.course).count() == 1
    with tenant_context(other):
        assert not scheduling_services.subscriptions_queryset().filter(
            archived_at__isnull=False
        ).exists()
        assert not scheduling_services.sessions_queryset().filter(
            archived_at__isnull=False
        ).exists()
```

- [ ] **Step 2: Run to see it fail**

Run: `… exec -T django pytest -q etqan/tenants/tests/test_seed_b2.py -k archived_alone`
Expected: FAIL (`AttributeError: module 'etqan.tenants.seeds.b2' has no attribute 'ARCHIVE_SWITCHES'`). Keep the output.

- [ ] **Step 3: Implement** in `seeds/b2.py` (it already imports `time`, `timedelta`, `transaction`, `catalogue_services`, `features`, `ConflictError`, `ValidationError`, `scheduling_services`):

```python
# Slice B2d (spec §8, Plan 31 D9): in demo, a past subscription of its own —
# demo's live ones feed other specs — expired by the hourly job's own step,
# its first session cancelled and archived on its own, then the subscription
# archived with the rest. Restoring the subscription leaves that one session
# archived (D-4). Other academies get nothing.
ARCHIVES = {
    "demo": {
        "student": "Aisha Omar",
        "course": "Tajweed",
        "teacher": "Ustadh Bilal",
        "package": "Two-week intensive",
        "starts_days_ago": 45,
        "slots": [{"weekdays": [0, 3], "start_time": time(19, 0)}],
        "reason": "Seeded: the student travelled",
    }
}
ARCHIVE_SWITCHES = ("subscription_archive", "session_archive")


def seed_archives(subdomain: str) -> None:
    """Idempotent: skipped once Aisha Omar has a Tajweed subscription, and
    while either archive switch is off (nothing is written then). One
    transaction, as the system: a refused step leaves nothing and is retried
    on the next run."""
    spec = ARCHIVES.get(subdomain)
    if spec is None or not all(features.enabled(c) for c in ARCHIVE_SWITCHES):
        return
    student = _person("student", spec["student"])
    teacher = _person("teacher", spec["teacher"])
    course = catalogue_services.find_course(spec["course"])
    package = catalogue_services.find_package(spec["package"])
    if None in (student, teacher, course, package):
        print("skip: archives — a seeded record was not found")  # noqa: T201
        return
    theirs = scheduling_services.subscriptions_queryset().filter(
        student__user_id=student.id, course_id=course.id
    )
    if theirs.exists():
        return
    starts_on = scheduling_services.today() - timedelta(days=spec["starts_days_ago"])
    try:
        with transaction.atomic():
            sub = scheduling_services.create_subscription(
                student_id=student.id,
                course_id=course.id,
                teacher_id=teacher.id,
                package_id=package.id,
                starts_on=starts_on,
                slots=spec["slots"],
            )
            scheduling_services.generate(
                starts_on, starts_on + timedelta(days=13), subscription=sub
            )
            # Its grace ended weeks ago: the hourly job's step expires it.
            scheduling_services.run_lifecycle()
            first = scheduling_services.sessions_of(sub).first()
            scheduling_services.cancel_session(first, by=None, reason=spec["reason"])
            scheduling_services.archive_session(first, by=None)
            scheduling_services.archive_subscription(sub, by=None)
    except (ValidationError, ConflictError) as exc:
        print(f"skip: archives — {exc}")  # noqa: T201
```

In `seed_dev.py`'s B2 block, after `b2.seed_activity(subdomain)`:

```python
        b2.seed_archives(subdomain)
```

- [ ] **Step 4: The earlier seed tests read the everyday rows** (plan D9)

The new archived subscription and its four past sessions (one cancelled, none marked) are demo data the archive puts away; the scheduling-seed tests written before it count every row. Narrow exactly these reads, nothing else:

`test_seed_dev.py`, `test_seed_dev_adds_subscriptions_once` — in `seeded()`:

```python
        subs = list(
            scheduling.subscriptions_queryset()
            .filter(archived_at__isnull=True)  # slice B2d: the archive's own
            .order_by("id")
        )
```

`test_seed_dev_skips_a_subscription_whose_teacher_was_deactivated` — the delete loop and the final read both use `scheduling.subscriptions_queryset().filter(archived_at__isnull=True)` (the archived one has a cancelled session, which Plan 4's delete refuses, and is not one of the four specs).

`test_seed_dev_marks_past_sessions_and_writes_reports_once` — in `state()`:

```python
        sessions = list(
            scheduling.sessions_queryset().filter(
                occurs_on__lt=scheduling.today(), archived_at__isnull=True
            )
        )
```

`test_seed_b2.py`, `test_seed_activity_writes_nothing_while_the_log_is_off` — its last line becomes:

```python
        assert not sessions.filter(status="cancelled", archived_at__isnull=True).exists()
```

- [ ] **Step 5: Run the seed suites, then seed this stream twice**

Run: `… exec -T django pytest -q etqan/tenants` → PASS. Then on this stream: `just _stack-manage migrate_schemas` and `just _stack-manage seed_dev` twice (no errors, no second archived subscription). Ruff, format, lint-imports clean.

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/tenants/seeds/b2.py etqan/tenants/management/commands/seed_dev.py etqan/tenants/tests/test_seed_b2.py etqan/tenants/tests/test_seed_dev.py
git -C backend commit -m "feat(seeds): an archived subscription and a session archived alone in demo (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 10: Dashboard foundations — switches, types, routes, the pages query, strings

**Files:**
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode` + 3, right after B2c's `"activity_log"`)
- Modify: `dashboard/src/features/scheduling/schemas.ts`, `api.ts` (+ `api.test.ts`), `queries.ts`, `activityFormat.ts` (+ `activityFormat.test.ts`)
- Create: `dashboard/src/locales/en/archives.json`, `dashboard/src/locales/ar/archives.json`
- Modify: `dashboard/src/locales/{en,ar}/errors.json` (three `scheduling` codes), `dashboard/src/locales/{en,ar}/sessionActivity.json` (four actions, one field)

**Interfaces:**
- Consumes: Tasks 7–8's payloads and routes.
- Produces:
  - `FeatureCode` gains `"subscription_archive" | "session_archive" | "simplified_sessions"`.
  - `Subscription` gains `archived_at?: string | null; can_archive?: boolean`; `SubscriptionDetail` gains `archived_by?: PersonRef | null`; `Session` gains `archived_at?: string | null; ends_at?: string`. `ACTIVITY_ACTIONS` gains `"archive", "unarchive", "subscription_archived", "subscription_restored"`; `ACTIVITY_FIELDS` gains `"archived_at"` (last, as the backend's `LOGGED_FIELDS`).
  - `schedulingApi.archive(id): Promise<SubscriptionDetail>` (`POST subscriptions/<id>/archive/`), `schedulingApi.restore(id): Promise<SubscriptionDetail>` (`DELETE subscriptions/<id>/archive/`), `schedulingApi.archiveSessions(ids: number[]): Promise<BulkResult>` (`POST sessions/archive/ {ids}`), `schedulingApi.unarchiveSessions(ids: number[]): Promise<BulkResult>` (`POST sessions/unarchive/ {ids}`).
  - `useSessionPages(params: QueryParams, enabled: boolean)` — an infinite query over `sessionList`, key `[...schedulingKey, "session-pages", params]`, next page = pages loaded + 1 while the last page has `next`.
  - `activityValue("archived_at", …)` formats an instant.
  - i18n `archives.*` (below) and `errors.scheduling.{archived,not_archived,has_upcoming_sessions}`.

- [ ] **Step 1: Write the failing tests**

`api.test.ts` (append inside `describe("schedulingApi")`):

```ts
	it("archives and restores subscriptions and sessions (B2d §6)", async () => {
		await schedulingApi.archive(7);
		expect(api.post).toHaveBeenLastCalledWith("subscriptions/7/archive/");
		await schedulingApi.restore(7);
		expect(api.delete).toHaveBeenLastCalledWith("subscriptions/7/archive/");
		await schedulingApi.archiveSessions([41, 42]);
		expect(api.post).toHaveBeenLastCalledWith("sessions/archive/", {
			ids: [41, 42],
		});
		await schedulingApi.unarchiveSessions([41]);
		expect(api.post).toHaveBeenLastCalledWith("sessions/unarchive/", {
			ids: [41],
		});
	});
```

`activityFormat.test.ts` (append inside `describe("activityValue")`):

```ts
	it("shows when a session was archived as an instant (B2d)", () => {
		expect(activityValue("archived_at", "2026-06-04T08:00:00Z", ctx())).toBe(
			"Jun 4, 2026 08:00 (student: 11:00)",
		);
		expect(activityValue("archived_at", null, ctx())).toBe("—");
	});
```

(The existing "gives every action and field a label in both languages" test now also fails until `sessionActivity.json` has the four new actions and the new field; `locales.test.ts` fails until both `archives.json` files exist with equal keys.)

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/api.test.ts src/features/scheduling/activityFormat.test.ts src/locales`
Expected: FAIL (`schedulingApi.archive is not a function`; `"2026-06-04T08:00:00Z"` returned as is). Keep the output.

- [ ] **Step 3: Types, routes and the pages query**

`identity/schemas.ts`, after `| "activity_log"`:

```ts
	// Slice B2d (Plan 31).
	| "subscription_archive"
	| "session_archive"
	| "simplified_sessions"
```

`scheduling/schemas.ts` — in `Subscription`, after `supervisor?`:

```ts
	// Slice B2d: the office's, while the subscription archive is on.
	// `can_archive` is the server's rule (ended, nothing due), never restated.
	archived_at?: string | null;
	can_archive?: boolean;
```

in `SubscriptionDetail`, after `pauses`:

```ts
	// Slice B2d: who archived it (null: the system).
	archived_by?: PersonRef | null;
```

in `Session`, after `postpone_until?`:

```ts
	// Slice B2d: the office's, while the session archive is on.
	archived_at?: string | null;
	ends_at?: string;
```

`ACTIVITY_ACTIONS` ends `…, "subscription_supervisor", "archive", "unarchive", "subscription_archived", "subscription_restored"`; `ACTIVITY_FIELDS` ends `…, "actual_minutes", "archived_at"`.

`api.ts`, after `cancel`:

```ts
	// Slice B2d (spec §6).
	archive: (id: number) => detail(api.post(`${S}${id}/archive/`)),
	restore: (id: number) => detail(api.delete(`${S}${id}/archive/`)),
```

and after `bulk`:

```ts
	archiveSessions: async (ids: number[]) =>
		(await api.post<BulkResult>(`${SE}archive/`, { ids })).data,
	unarchiveSessions: async (ids: number[]) =>
		(await api.post<BulkResult>(`${SE}unarchive/`, { ids })).data,
```

`queries.ts` — add `useInfiniteQuery` to the TanStack import, then:

```ts
/** Slice B2d (plan D11): the simplified view's pages of the sessions list;
 * "More" loads the next one while the last page says there is one. */
export function useSessionPages(params: QueryParams, enabled: boolean) {
	return useInfiniteQuery({
		queryKey: [...schedulingKey, "session-pages", params],
		queryFn: ({ pageParam }) =>
			schedulingApi.sessionList({ ...params, page: pageParam }),
		initialPageParam: 1,
		getNextPageParam: (last, all) => (last.next ? all.length + 1 : undefined),
		enabled,
	});
}
```

`activityFormat.ts` — `INSTANTS` gains `"archived_at"`.

- [ ] **Step 4: Strings**

`src/locales/en/archives.json`:

```json
{
	"links": "More views",
	"archive": "Archive",
	"back": "Back to the list",
	"simpleLink": "Simplified view",
	"badge": "Archived",
	"columns": {
		"archivedAt": "Archived",
		"actions": "Actions"
	},
	"filters": {
		"archivedFrom": "Archived from",
		"archivedTo": "Archived to",
		"createdFrom": "Created from",
		"createdTo": "Created to"
	},
	"subscriptions": {
		"title": "Subscription archive",
		"action": "Archive (delete keeping records)",
		"confirmTitle": "Archive subscription",
		"confirmBody": "It leaves the subscriptions list with its sessions and keeps counting in invoices, payroll and reports. You can restore it from the archive.",
		"done": "Subscription archived.",
		"empty": "No archived subscriptions match.",
		"banner": "Archived on {{date}} by {{name}}.",
		"bannerSystem": "Archived on {{date}}.",
		"restore": "Restore",
		"restored": "Subscription restored.",
		"restoredCount": "Restored {{done}} of {{total}}.",
		"restoredSome": "Restored {{done}} of {{total}}. {{reason}}",
		"select": "Select {{name}}'s subscription",
		"selectPage": "Select every subscription on this page",
		"bulk": "Archive actions",
		"selected": "{{count}} selected",
		"deleteAction": "Delete permanently",
		"deleteTitle": "Delete permanently",
		"deleteBody": "The subscription and its sessions are deleted for good. Not possible once a session is marked, completed or cancelled.",
		"deleted": "Subscription deleted."
	},
	"sessions": {
		"title": "Session archive",
		"action": "Archive",
		"restore": "Restore",
		"empty": "No archived sessions match.",
		"banner": "Archived on {{date}}.",
		"restored": "Session restored."
	},
	"simple": {
		"title": "Simplified sessions",
		"day": "Day",
		"list": "Sessions",
		"empty": "No sessions on this day.",
		"loadError": "Couldn't load the sessions.",
		"more": "More",
		"present": "Present",
		"absent": "Absent",
		"presentFor": "Mark {{name}} present",
		"absentFor": "Mark {{name}} absent"
	}
}
```

`src/locales/ar/archives.json` (same keys, one for one):

```json
{
	"links": "عروض أخرى",
	"archive": "الأرشيف",
	"back": "العودة إلى القائمة",
	"simpleLink": "العرض المبسّط",
	"badge": "مؤرشف",
	"columns": {
		"archivedAt": "تاريخ الأرشفة",
		"actions": "الإجراءات"
	},
	"filters": {
		"archivedFrom": "أُرشف من",
		"archivedTo": "أُرشف حتى",
		"createdFrom": "أُنشئ من",
		"createdTo": "أُنشئ حتى"
	},
	"subscriptions": {
		"title": "أرشيف الاشتراكات",
		"action": "أرشفة (حذف مع الاحتفاظ بالسجلات)",
		"confirmTitle": "أرشفة الاشتراك",
		"confirmBody": "يخرج الاشتراك وحصصه من قائمة الاشتراكات، ويبقى محسوبًا في الفواتير والرواتب والتقارير. يمكنك استرجاعه من الأرشيف.",
		"done": "أُرشف الاشتراك.",
		"empty": "لا توجد اشتراكات مؤرشفة مطابقة.",
		"banner": "أُرشف في {{date}} بواسطة {{name}}.",
		"bannerSystem": "أُرشف في {{date}}.",
		"restore": "استرجاع",
		"restored": "استُرجع الاشتراك.",
		"restoredCount": "استُرجع {{done}} من {{total}}.",
		"restoredSome": "استُرجع {{done}} من {{total}}. {{reason}}",
		"select": "تحديد اشتراك {{name}}",
		"selectPage": "تحديد كل الاشتراكات في هذه الصفحة",
		"bulk": "إجراءات الأرشيف",
		"selected": "المحدد: {{count}}",
		"deleteAction": "حذف نهائي",
		"deleteTitle": "حذف نهائي",
		"deleteBody": "يُحذف الاشتراك وحصصه نهائيًا. غير ممكن بعد تسجيل حضور أي حصة أو إكمالها أو إلغائها.",
		"deleted": "حُذف الاشتراك."
	},
	"sessions": {
		"title": "أرشيف الحصص",
		"action": "أرشفة",
		"restore": "استرجاع",
		"empty": "لا توجد حصص مؤرشفة مطابقة.",
		"banner": "أُرشفت في {{date}}.",
		"restored": "استُرجعت الحصة."
	},
	"simple": {
		"title": "الحصص (عرض مبسّط)",
		"day": "اليوم",
		"list": "الحصص",
		"empty": "لا توجد حصص في هذا اليوم.",
		"loadError": "تعذّر تحميل الحصص.",
		"more": "المزيد",
		"present": "حاضر",
		"absent": "غائب",
		"presentFor": "تسجيل {{name}} حاضرًا",
		"absentFor": "تسجيل {{name}} غائبًا"
	}
}
```

`errors.json`, `scheduling` group, after `not_revertible` (which gains a trailing comma): en `"archived": "This is archived. Restore it first."`, `"not_archived": "This isn't archived."`, `"has_upcoming_sessions": "A session of this subscription is still to come. Cancel or delete it first."`; ar `"archived": "هذا مؤرشف. استرجعه أولًا."`, `"not_archived": "هذا غير مؤرشف."`, `"has_upcoming_sessions": "ما زالت لهذا الاشتراك حصة قادمة. ألغها أو احذفها أولًا."`.

`sessionActivity.json`: `actions` gains en `"archive": "Session archived"`, `"unarchive": "Restored from the archive"`, `"subscription_archived": "Archived with its subscription"`, `"subscription_restored": "Restored with its subscription"`; ar `"archive": "أرشفة الحصة"`, `"unarchive": "استرجاعها من الأرشيف"`, `"subscription_archived": "أُرشفت مع اشتراكها"`, `"subscription_restored": "استُرجعت مع اشتراكها"`. `fields` gains en `"archived_at": "Archived at"`, ar `"archived_at": "تاريخ الأرشفة"`.

- [ ] **Step 5: Run, then verify**

Run: the Step 2 command → PASS. Then `… exec -T dashboard pnpm exec biome check --write src`, `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`, `… exec -T dashboard pnpm test:coverage`.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src/features/identity/schemas.ts src/features/scheduling/schemas.ts src/features/scheduling/api.ts src/features/scheduling/api.test.ts src/features/scheduling/queries.ts src/features/scheduling/activityFormat.ts src/features/scheduling/activityFormat.test.ts src/locales/en/archives.json src/locales/ar/archives.json src/locales/en/errors.json src/locales/ar/errors.json src/locales/en/sessionActivity.json src/locales/ar/sessionActivity.json
git -C dashboard commit -m "feat(scheduling): archive types, routes, pages query and strings (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 11: The subscriptions list's Archive action and the subscription archive screen

**Files:**
- Create: `dashboard/src/features/scheduling/ArchiveActions.tsx` (+ `ArchiveActions.test.tsx`)
- Modify: `dashboard/src/features/scheduling/SubscriptionsList.tsx` (+ `SubscriptionsList.test.tsx`)
- Create: `dashboard/src/routes/_authed/scheduling.subscriptions.archive.tsx`
- Modify: `dashboard/src/routes/permissions.test.ts` (`FEATURE_SCREENS`, `FEATURE_WORDS`), `dashboard/src/routeTree.gen.ts` (regenerated)

**Interfaces:**
- Consumes: Task 10 (`schedulingApi.archive`, `.restore`, `.remove`, `Subscription.archived_at`, `Subscription.can_archive`, `archives.*`), `Confirm`, `useSchedulingMutation`, `useAcademySettings({ enabled })`, `dayIn`.
- Produces (module `ArchiveActions.tsx`; Tasks 12–13 add to it):
  - `ArchivedBadge()` — a neutral `StatusChip` reading "Archived".
  - `ArchiveSubscriptionButton({ sub }: { sub: Subscription })` — `Confirm` with action "Archive (delete keeping records)", title "Archive subscription"; on success a "Subscription archived." toast; a refusal's translated code as a toast.
  - `DeleteForeverButton({ sub }: { sub: Subscription })` — `Confirm` "Delete permanently" calling `schedulingApi.remove`.
  - `RestoreSubscriptionsBar({ selected, onDone }: { selected: number[]; onDone: () => void })` — a region "Archive actions" with "N selected" and Restore: one `DELETE …/archive/` per chosen id, all sent together (`Promise.allSettled`), then one toast "Restored d of n." (or "Restored d of n. <first refusal>").
  - `SubscriptionsList({ archive = false }: { archive?: boolean })`. Normal: a "More views" nav with the "Archive" link (while `subscription_archive` is on), and per row an Archive button where `sub.can_archive` and `can("subscription.delete")`. Archive: `archived: "only"` in its params, status tabs All / Expired / Cancelled, four date filters (`archived_from`, `archived_to`, `created_from`, `created_to`), an "Archived" column (academy day), row checkboxes with the Restore bar (`subscription.restore`), and Delete permanently per row (`subscription.delete`); a "Back to the list" link; no "New subscription".
  - Route `/_authed/scheduling/subscriptions/archive` (`permission: "subscription.view_any"`, `feature: "subscription_archive"`).

- [ ] **Step 1: Write the failing tests**

`ArchiveActions.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { subscriptionDetail, subscriptionRow } from "@/test/scheduling-fixtures";
import {
	ArchiveSubscriptionButton,
	DeleteForeverButton,
	RestoreSubscriptionsBar,
} from "./ArchiveActions";
import { schedulingApi } from "./api";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			archive: vi.fn(),
			restore: vi.fn(),
			remove: vi.fn(),
		},
	};
});

function refusal(code: string) {
	return new AxiosError("refused", "409", undefined, undefined, {
		status: 409,
		data: { detail: "Refused.", code },
	} as never);
}

describe("ArchiveSubscriptionButton", () => {
	beforeEach(() => vi.clearAllMocks());

	it("archives after a confirm and says so", async () => {
		vi.mocked(schedulingApi.archive).mockResolvedValue(subscriptionDetail());
		const user = userEvent.setup();
		renderWithRouter(<ArchiveSubscriptionButton sub={subscriptionRow()} />);
		await user.click(
			screen.getByRole("button", { name: "Archive (delete keeping records)" }),
		);
		const dialog = screen.getByRole("alertdialog");
		expect(dialog).toHaveTextContent("keeps counting in invoices, payroll and reports");
		await user.click(
			within(dialog).getByRole("button", { name: "Archive subscription" }),
		);
		await waitFor(() => expect(schedulingApi.archive).toHaveBeenCalledWith(7));
		expect(await screen.findByText("Subscription archived.")).toBeInTheDocument();
	});

	it("translates a refusal", async () => {
		vi.mocked(schedulingApi.archive).mockRejectedValue(
			refusal("scheduling.has_upcoming_sessions"),
		);
		const user = userEvent.setup();
		renderWithRouter(<ArchiveSubscriptionButton sub={subscriptionRow()} />);
		await user.click(
			screen.getByRole("button", { name: "Archive (delete keeping records)" }),
		);
		await user.click(screen.getByRole("button", { name: "Archive subscription" }));
		expect(
			await screen.findByText(
				"A session of this subscription is still to come. Cancel or delete it first.",
			),
		).toBeInTheDocument();
	});
});

describe("DeleteForeverButton", () => {
	beforeEach(() => vi.clearAllMocks());

	it("deletes for good after a confirm", async () => {
		vi.mocked(schedulingApi.remove).mockResolvedValue(undefined);
		const user = userEvent.setup();
		renderWithRouter(<DeleteForeverButton sub={subscriptionRow()} />);
		await user.click(screen.getByRole("button", { name: "Delete permanently" }));
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Delete permanently",
			}),
		);
		await waitFor(() => expect(schedulingApi.remove).toHaveBeenCalledWith(7));
		expect(await screen.findByText("Subscription deleted.")).toBeInTheDocument();
	});
});

describe("RestoreSubscriptionsBar", () => {
	beforeEach(() => vi.clearAllMocks());

	it("shows nothing while nothing is chosen", () => {
		renderWithRouter(<RestoreSubscriptionsBar selected={[]} onDone={vi.fn()} />);
		expect(screen.queryByRole("region", { name: "Archive actions" })).toBeNull();
	});

	it("restores every chosen row and sums it up, the first refusal included", async () => {
		vi.mocked(schedulingApi.restore)
			.mockResolvedValueOnce(subscriptionDetail())
			.mockRejectedValueOnce(refusal("scheduling.not_archived"));
		const onDone = vi.fn();
		const user = userEvent.setup();
		renderWithRouter(<RestoreSubscriptionsBar selected={[7, 8]} onDone={onDone} />);
		const bar = screen.getByRole("region", { name: "Archive actions" });
		expect(bar).toHaveTextContent("2 selected");
		await user.click(within(bar).getByRole("button", { name: "Restore" }));
		expect(
			await screen.findByText("Restored 1 of 2. This isn't archived."),
		).toBeInTheDocument();
		expect(schedulingApi.restore).toHaveBeenCalledTimes(2);
		expect(onDone).toHaveBeenCalled();
	});
});
```

`SubscriptionsList.test.tsx` — add `archive`, `restore`, `remove` to the file's `schedulingApi` mock; add, next to the other module mocks:

```tsx
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
```

with the imports `import { academyApi } from "@/features/academy/api";` and `academySettings`, `subscriptionDetail` from the fixtures, then append inside `describe("SubscriptionsList")`:

```tsx
	it("links to the archive and offers Archive only where the server allows it (B2d)", async () => {
		vi.mocked(schedulingApi.list).mockResolvedValue(
			page([
				subscriptionRow({ status: "cancelled", can_archive: true }),
				subscriptionRow({
					id: 8,
					student: { id: 12, full_name: "Aisha", timezone: "UTC" },
					can_archive: false,
				}),
			]),
		);
		renderWithRouter(<SubscriptionsList />, {
			extraPaths: ["/scheduling/subscriptions/$subscriptionId"],
		});
		const table = await screen.findByRole("table");
		const name = "Archive (delete keeping records)";
		expect(
			within(within(table).getByRole("row", { name: /Yusuf/ })).getByRole("button", {
				name,
			}),
		).toBeInTheDocument();
		expect(
			within(within(table).getByRole("row", { name: /Aisha/ })).queryByRole(
				"button",
				{ name },
			),
		).toBeNull();
		expect(screen.getByRole("link", { name: "Archive" })).toHaveAttribute(
			"href",
			"/scheduling/subscriptions/archive",
		);
		expect(academyApi.get).not.toHaveBeenCalled();
	});

	it("hides the archive while it is off, and Archive without the code (B2d)", async () => {
		vi.mocked(schedulingApi.list).mockResolvedValue(
			page([subscriptionRow({ status: "cancelled", can_archive: true })]),
		);
		const { unmount } = renderWithRouter(
			<CanProvider me={adminWith("invoices")}>
				<SubscriptionsList />
			</CanProvider>,
			{ extraPaths: ["/scheduling/subscriptions/$subscriptionId"] },
		);
		await screen.findByRole("table");
		expect(screen.queryByRole("link", { name: "Archive" })).toBeNull();
		expect(
			screen.queryByRole("button", { name: "Archive (delete keeping records)" }),
		).toBeNull();
		unmount();
		renderWithRouter(
			<CanProvider me={staffMe("subscription.view_any")}>
				<SubscriptionsList />
			</CanProvider>,
			{ extraPaths: ["/scheduling/subscriptions/$subscriptionId"] },
		);
		await screen.findByRole("table");
		expect(screen.getByRole("link", { name: "Archive" })).toBeInTheDocument();
		expect(
			screen.queryByRole("button", { name: "Archive (delete keeping records)" }),
		).toBeNull();
	});

	it("is the archive: only archived rows, its filters, Restore and Delete permanently (B2d)", async () => {
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(schedulingApi.list).mockResolvedValue(
			page([
				subscriptionRow({
					status: "cancelled",
					archived_at: "2026-06-04T08:00:00Z",
				}),
			]),
		);
		vi.mocked(schedulingApi.restore).mockResolvedValue(subscriptionDetail());
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionsList archive />, {
			extraPaths: ["/scheduling/subscriptions/$subscriptionId"],
		});
		const table = await screen.findByRole("table");
		expect(lastParams()).toEqual({ page: 1, archived: "only" });
		expect(within(table).getByText("Jun 4, 2026")).toBeInTheDocument();
		expect(screen.getByRole("link", { name: "Back to the list" })).toHaveAttribute(
			"href",
			"/scheduling/subscriptions",
		);
		expect(screen.queryByRole("link", { name: "New subscription" })).toBeNull();
		expect(
			screen.getAllByRole("tab").map((tab) => tab.textContent),
		).toEqual(["All", "Expired", "Cancelled"]);
		await user.type(screen.getByLabelText("Archived from"), "2026-06-01");
		await user.type(screen.getByLabelText("Created to"), "2026-06-30");
		await waitFor(() =>
			expect(lastParams()).toEqual({
				page: 1,
				archived: "only",
				archived_from: "2026-06-01",
				created_to: "2026-06-30",
			}),
		);
		expect(
			within(table).getByRole("button", { name: "Delete permanently" }),
		).toBeInTheDocument();
		await user.click(screen.getByLabelText("Select Yusuf's subscription"));
		await user.click(
			within(screen.getByRole("region", { name: "Archive actions" })).getByRole(
				"button",
				{ name: "Restore" },
			),
		);
		await waitFor(() => expect(schedulingApi.restore).toHaveBeenCalledWith(7));
		expect(await screen.findByText("Restored 1 of 1.")).toBeInTheDocument();
	});
```

`permissions.test.ts`: in `FEATURE_SCREENS` add `"/_authed/scheduling/subscriptions/archive": "subscription_archive",` (under a `// Slice B2d` comment) and widen `FEATURE_WORDS` to `/families|parents|reports|invoices|supervision|expenses|donations|archive|website\/(faqs|ads|redirects|articles)/`.

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/ArchiveActions.test.tsx src/features/scheduling/SubscriptionsList.test.tsx src/routes/permissions.test.ts`
Expected: FAIL (`Failed to resolve import "./ArchiveActions"`; no "Archive" link; the route is missing from `FEATURE_SCREENS`'s comparison). Keep the output.

- [ ] **Step 3: `ArchiveActions.tsx`**

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { errorText } from "@/lib/form-errors";
import { Button, StatusChip, toast } from "@/ui";
import { schedulingApi } from "./api";
import { useSchedulingMutation } from "./queries";
import type { Subscription } from "./schemas";

/** Slice B2d: beside a session's status where archived rows show. */
export function ArchivedBadge() {
	const { t } = useTranslation();
	return <StatusChip tone="neutral">{t("archives.badge")}</StatusChip>;
}

function useFail() {
	const { t } = useTranslation();
	return (error: unknown) =>
		toast({ description: errorText(error, t), variant: "destructive" });
}

/** Spec §7: "Archive (delete keeping records)", behind a confirm. Shown only
 * where the server says the subscription may go (`can_archive`, plan D2). */
export function ArchiveSubscriptionButton({ sub }: { sub: Subscription }) {
	const { t } = useTranslation();
	const fail = useFail();
	const archive = useSchedulingMutation(schedulingApi.archive);
	return (
		<Confirm
			action={t("archives.subscriptions.action")}
			title={t("archives.subscriptions.confirmTitle")}
			body={t("archives.subscriptions.confirmBody")}
			onConfirm={() =>
				archive.mutate(sub.id, {
					onSuccess: () =>
						toast({
							description: t("archives.subscriptions.done"),
							variant: "success",
						}),
					onError: fail,
				})
			}
		/>
	);
}

/** Spec D-9: the archive's Delete permanently, by Plan 4's rule (the server
 * refuses a subscription with a marked, completed or cancelled session). */
export function DeleteForeverButton({ sub }: { sub: Subscription }) {
	const { t } = useTranslation();
	const fail = useFail();
	const remove = useSchedulingMutation(schedulingApi.remove);
	return (
		<Confirm
			action={t("archives.subscriptions.deleteAction")}
			title={t("archives.subscriptions.deleteTitle")}
			body={t("archives.subscriptions.deleteBody")}
			onConfirm={() =>
				remove.mutate(sub.id, {
					onSuccess: () =>
						toast({
							description: t("archives.subscriptions.deleted"),
							variant: "success",
						}),
					onError: fail,
				})
			}
		/>
	);
}

/** Plan 31 D7: one restore per chosen subscription, sent together, then one
 * summary with the first refusal. */
export function RestoreSubscriptionsBar({
	selected,
	onDone,
}: {
	selected: number[];
	onDone: () => void;
}) {
	const { t } = useTranslation();
	const restore = useSchedulingMutation(schedulingApi.restore);
	const [busy, setBusy] = useState(false);
	if (selected.length === 0) return null;

	async function run() {
		setBusy(true);
		const outcomes = await Promise.allSettled(
			selected.map((id) => restore.mutateAsync(id)),
		);
		setBusy(false);
		onDone();
		const done = outcomes.filter((o) => o.status === "fulfilled").length;
		const refused = outcomes.find(
			(o): o is PromiseRejectedResult => o.status === "rejected",
		);
		const counts = { done, total: outcomes.length };
		toast(
			refused
				? {
						description: t("archives.subscriptions.restoredSome", {
							...counts,
							reason: errorText(refused.reason, t),
						}),
						variant: "destructive",
					}
				: {
						description: t("archives.subscriptions.restoredCount", counts),
						variant: "success",
					},
		);
	}

	return (
		<section
			aria-label={t("archives.subscriptions.bulk")}
			className="flex flex-wrap items-center gap-2 rounded-lg border border-border bg-secondary p-3"
		>
			<span className="text-sm font-medium">
				{t("archives.subscriptions.selected", { count: selected.length })}
			</span>
			<Button size="sm" variant="outline" disabled={busy} onClick={run}>
				{t("archives.subscriptions.restore")}
			</Button>
		</section>
	);
}
```

- [ ] **Step 4: `SubscriptionsList.tsx`** (the whole component; what is new is marked "Slice B2d")

```tsx
import { Link } from "@tanstack/react-router";
import { CalendarClock, Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ExportButton } from "@/components/ExportButton";
import { Pager } from "@/components/Pager";
import { useAcademySettings } from "@/features/academy/queries";
import { type Course, useCatalogue } from "@/features/catalogue";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { usePeople } from "@/features/people";
import type { QueryParams } from "@/lib/api";
import { dayIn, formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	Checkbox,
	EmptyState,
	Input,
	Select,
	Spinner,
} from "@/ui";
import {
	ArchiveSubscriptionButton,
	DeleteForeverButton,
	RestoreSubscriptionsBar,
} from "./ArchiveActions";
import { subscriptionsCsvUrl } from "./api";
import {
	PaymentStatusChip,
	SubscriptionProgress,
	SubscriptionStatusChip,
	useLocalName,
} from "./bits";
import { useSubscriptions } from "./queries";
import { SUBSCRIPTION_STATUSES, type Subscription } from "./schemas";

// The backend paginates at 25 rows a page (StandardPagination).
const PAGE_SIZE = 25;
const TABS = ["all", ...SUBSCRIPTION_STATUSES] as const;
// Slice B2d (D-3): only an ended subscription is ever archived.
const ARCHIVE_TABS = ["all", "expired", "cancelled"] as const;
const ARCHIVE_DAYS = [
	["archived_from", "archives.filters.archivedFrom"],
	["archived_to", "archives.filters.archivedTo"],
	["created_from", "archives.filters.createdFrom"],
	["created_to", "archives.filters.createdTo"],
] as const;

/** Spec §6 Subscriptions. Slice B2d: Archive on the rows the server allows,
 * and, with `archive`, the subscription archive — `archived=only`, its own
 * filters, Restore for the chosen rows and Delete permanently. */
export function SubscriptionsList({ archive = false }: { archive?: boolean }) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const hasFeature = useHasFeature();
	// Plan 13: no Payment column while the academy has invoices off.
	const payments = hasFeature("invoices");
	const [params, setParams] = useState<QueryParams>(
		archive ? { page: 1, archived: "only" } : { page: 1 },
	);
	const [selected, setSelected] = useState<number[]>([]);
	const { data, isPending, isError } = useSubscriptions(params);
	// Slice B2d: the archive's "Archived" day is the academy's.
	const { data: academy } = useAcademySettings({ enabled: archive });
	// Plan 12a fix round 1: filters are fetched only when the viewer may list
	// teachers/courses themselves — never a 403 behind this screen's own
	// subscription.view_any (Important 1).
	const listTeachers = can("teacher.view_any");
	const listCourses = can("course.view_any");
	const { data: teachers } = usePeople(
		"teachers",
		{ page_size: 100 },
		{ enabled: listTeachers },
	);
	const { data: courses } = useCatalogue<Course>(
		"courses",
		{ page_size: 100 },
		{ enabled: listCourses },
	);
	const localName = useLocalName();
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const current = String(params.status ?? "all");
	// Slice B2d: who may do what here (the server still checks every call).
	const archiving =
		!archive && hasFeature("subscription_archive") && can("subscription.delete");
	const restoring = archive && can("subscription.restore");
	const deleting = archive && can("subscription.delete");
	const pageIds = rows.map((row) => row.id);
	const allChosen =
		pageIds.length > 0 && pageIds.every((id) => selected.includes(id));
	const update = (patch: QueryParams) => {
		setParams({ ...params, page: 1, ...patch });
		setSelected([]);
	};

	function toggle(id: number) {
		setSelected(
			selected.includes(id)
				? selected.filter((x) => x !== id)
				: [...selected, id],
		);
	}

	function ends(sub: Subscription) {
		const day = formatDay(
			sub.in_grace ? sub.grace_ends_on : sub.ends_on,
			i18n.language,
		);
		return sub.in_grace ? t("scheduling.inGraceUntil", { date: day }) : day;
	}

	function archivedOn(sub: Subscription) {
		if (!sub.archived_at || !academy) return "—";
		return dayIn(new Date(sub.archived_at), academy.timezone, i18n.language);
	}

	const columns = [
		"student",
		"course",
		"teacher",
		"progress",
		"status",
		...(payments ? (["payment"] as const) : []),
		"ends",
	] as const;

	return (
		<div className="flex flex-col gap-4">
			<nav aria-label={t("archives.links")} className="flex flex-wrap gap-3 text-sm">
				{archive ? (
					<Link
						to="/scheduling/subscriptions"
						className="font-medium text-primary-text underline-offset-4 hover:underline"
					>
						{t("archives.back")}
					</Link>
				) : hasFeature("subscription_archive") ? (
					<Link
						to="/scheduling/subscriptions/archive"
						className="font-medium text-primary-text underline-offset-4 hover:underline"
					>
						{t("archives.archive")}
					</Link>
				) : null}
			</nav>
			<div
				role="tablist"
				aria-label={t("scheduling.columns.status")}
				className="flex flex-wrap gap-2 border-b border-border pb-2"
			>
				{(archive ? ARCHIVE_TABS : TABS).map((tab) => (
					<button
						key={tab}
						type="button"
						role="tab"
						aria-selected={current === tab}
						onClick={() => update({ status: tab === "all" ? undefined : tab })}
						className="rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-secondary aria-selected:bg-secondary aria-selected:text-foreground"
					>
						{tab === "all"
							? t("scheduling.tabs.all")
							: t(`scheduling.status.${tab}`)}
					</button>
				))}
			</div>
			<div className="flex flex-wrap items-end gap-3">
				<div className="min-w-48 flex-1">
					<label htmlFor="subscriptions-search" className="sr-only">
						{t("scheduling.search")}
					</label>
					<Input
						id="subscriptions-search"
						type="search"
						placeholder={t("scheduling.search")}
						value={String(params.q ?? "")}
						onChange={(e) => update({ q: e.target.value })}
					/>
				</div>
				{listTeachers ? (
					<Select
						aria-label={t("scheduling.columns.teacher")}
						className="w-auto"
						value={String(params.teacher ?? "")}
						onChange={(e) => update({ teacher: e.target.value })}
					>
						<option value="">{t("scheduling.anyTeacher")}</option>
						{teachers?.results.map((p) => (
							<option key={p.id} value={p.id}>
								{p.user.full_name}
							</option>
						))}
					</Select>
				) : null}
				{listCourses ? (
					<Select
						aria-label={t("scheduling.columns.course")}
						className="w-auto"
						value={String(params.course ?? "")}
						onChange={(e) => update({ course: e.target.value })}
					>
						<option value="">{t("scheduling.anyCourse")}</option>
						{courses?.results.map((c) => (
							<option key={c.id} value={c.id}>
								{localName(c)}
							</option>
						))}
					</Select>
				) : null}
				{archive
					? ARCHIVE_DAYS.map(([key, label]) => (
							<div key={key} className="flex flex-col gap-1">
								<label htmlFor={`subscriptions-${key}`} className="text-xs">
									{t(label)}
								</label>
								<Input
									id={`subscriptions-${key}`}
									type="date"
									dir="ltr"
									className="w-auto"
									value={String(params[key] ?? "")}
									onChange={(e) => update({ [key]: e.target.value })}
								/>
							</div>
						))
					: null}
				<ExportButton href={subscriptionsCsvUrl(params)} />
				{!archive && can("subscription.create") ? (
					<Button asChild size="sm">
						<Link to="/scheduling/subscriptions/new">
							<Plus className="size-4" />
							{t("scheduling.new")}
						</Link>
					</Button>
				) : null}
			</div>
			{restoring ? (
				<RestoreSubscriptionsBar
					selected={selected}
					onDone={() => setSelected([])}
				/>
			) : null}
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("scheduling.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState
							icon={CalendarClock}
							title={t(
								archive ? "archives.subscriptions.empty" : "scheduling.empty",
							)}
						/>
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{restoring ? (
									<th scope="col" className="w-10 p-3">
										<Checkbox
											id="select-subscriptions"
											checked={allChosen}
											onCheckedChange={(on) =>
												setSelected(
													on
														? [...new Set([...selected, ...pageIds])]
														: selected.filter((id) => !pageIds.includes(id)),
												)
											}
										/>
										<label htmlFor="select-subscriptions" className="sr-only">
											{t("archives.subscriptions.selectPage")}
										</label>
									</th>
								) : null}
								{columns.map((key) => (
									<th
										key={key}
										scope="col"
										className="p-3 text-start font-medium"
									>
										{t(`scheduling.columns.${key}`)}
									</th>
								))}
								{archive ? (
									<th scope="col" className="p-3 text-start font-medium">
										{t("archives.columns.archivedAt")}
									</th>
								) : null}
								{archiving || deleting ? (
									<th scope="col" className="p-3 text-start font-medium">
										<span className="sr-only">{t("archives.columns.actions")}</span>
									</th>
								) : null}
							</tr>
						</thead>
						<tbody>
							{rows.map((sub) => (
								<tr key={sub.id} className="border-t border-border">
									{restoring ? (
										<td className="p-3">
											<Checkbox
												id={`select-subscription-${sub.id}`}
												checked={selected.includes(sub.id)}
												onCheckedChange={() => toggle(sub.id)}
											/>
											<label
												htmlFor={`select-subscription-${sub.id}`}
												className="sr-only"
											>
												{t("archives.subscriptions.select", {
													name: sub.student.full_name,
												})}
											</label>
										</td>
									) : null}
									<td className="p-3">
										<Link
											to="/scheduling/subscriptions/$subscriptionId"
											params={{ subscriptionId: String(sub.id) }}
											className="font-medium text-primary-text underline-offset-4 hover:underline"
										>
											{sub.student.full_name}
										</Link>
									</td>
									<td className="p-3">{localName(sub.course)}</td>
									<td className="p-3">{sub.teacher.full_name}</td>
									<td className="p-3">
										<SubscriptionProgress
											name={sub.student.full_name}
											used={sub.sessions_used}
											carried={sub.carried_over_sessions}
											total={sub.sessions_total}
											extra={sub.extra_sessions}
										/>
									</td>
									<td className="p-3">
										<SubscriptionStatusChip status={sub.status} />
									</td>
									{payments ? (
										<td className="p-3">
											{sub.payment_status ? (
												<PaymentStatusChip
													status={sub.payment_status}
													overdue={Boolean(sub.payment_overdue)}
												/>
											) : null}
										</td>
									) : null}
									<td className="p-3">{ends(sub)}</td>
									{archive ? <td className="p-3">{archivedOn(sub)}</td> : null}
									{archiving || deleting ? (
										<td className="p-3">
											{archiving && sub.can_archive ? (
												<ArchiveSubscriptionButton sub={sub} />
											) : null}
											{deleting ? <DeleteForeverButton sub={sub} /> : null}
										</td>
									) : null}
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			<Pager
				page={page}
				pages={pages}
				onChange={(next) => {
					setParams({ ...params, page: next });
					setSelected([]);
				}}
			/>
		</div>
	);
}
```

- [ ] **Step 5: The route** (`src/routes/_authed/scheduling.subscriptions.archive.tsx`)

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SubscriptionsList } from "@/features/scheduling";
import { PageHeader } from "@/ui";

// Slice B2d (spec §7): the subscription archive.
export const Route = createFileRoute("/_authed/scheduling/subscriptions/archive")({
	staticData: {
		permission: "subscription.view_any",
		feature: "subscription_archive",
	},
	component: function SubscriptionArchiveRoute() {
		const { t } = useTranslation();
		usePageTitle(t("archives.subscriptions.title"));
		return (
			<>
				<PageHeader title={t("archives.subscriptions.title")} />
				<SubscriptionsList archive />
			</>
		);
	},
});
```

Regenerate the route tree: `… exec -T dashboard pnpm exec vite build`.

- [ ] **Step 6: Run, then verify**

Run: the Step 2 command → PASS; then every suite that renders the list or the route tree: `… exec -T dashboard pnpm exec vitest run src/features/scheduling src/routes`. Then `… pnpm exec biome check --write src`, `… pnpm exec tsc --noEmit`, `… pnpm lint`, `… pnpm test:coverage`.

- [ ] **Step 7: Commit**

```bash
git -C dashboard add src/features/scheduling/ArchiveActions.tsx src/features/scheduling/ArchiveActions.test.tsx src/features/scheduling/SubscriptionsList.tsx src/features/scheduling/SubscriptionsList.test.tsx src/routes/_authed/scheduling.subscriptions.archive.tsx src/routes/permissions.test.ts src/routeTree.gen.ts
git -C dashboard commit -m "feat(scheduling): archive a subscription and the subscription archive screen (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 12: An archived subscription's page, its sessions panel, and the invoice form's picker

**Files:**
- Modify: `dashboard/src/features/scheduling/ArchiveActions.tsx` (+ test) — `ArchivedSubscriptionBanner`
- Modify: `dashboard/src/features/scheduling/SubscriptionDetail.tsx` (+ `SubscriptionDetail.test.tsx`), `SubscriptionActions.tsx` (+ `SubscriptionActions.test.tsx`), `SessionsPanel.tsx` (+ `SessionsPanel.test.tsx`)
- Modify (under a ledger claim, B3 owns billing): `dashboard/src/features/billing/InvoiceForm.tsx` (+ `InvoiceForm.test.tsx`)

**Interfaces:**
- Consumes: Task 10 (`schedulingApi.restore`, `SubscriptionDetail.archived_at`, `.archived_by`, `.can_archive`, `Session.archived_at`), Task 11 (`ArchiveSubscriptionButton`, `ArchivedBadge`, `useFail` inside the module).
- Produces: `ArchivedSubscriptionBanner({ sub, academyZone }: { sub: SubscriptionDetail; academyZone: string })` — nothing unless `sub.archived_at`; else "Archived on <academy day> by <name>." (or "Archived on <day>." for the system) and, with `subscription.restore`, a Restore button ("Subscription restored." toast). `SubscriptionDetail` renders it first. `SubscriptionActions` shows `ArchiveSubscriptionButton` when `sub.can_archive && can("subscription.delete")` and hides Renew on an archived subscription (plan D10). `SessionsPanel` shows `ArchivedBadge` beside an archived session's status. The invoice form's subscription picker asks `archived: "include"` while `subscription_archive` is on (plan D14).

- [ ] **Step 1: Take the claim on the billing file**

Run (from `$W`): `python3 scripts/orchestration/ledger.py claim --reason "B2d spec §4.4/§7: InvoiceForm's subscription picker includes archived subscriptions (one line)" B2 dashboard/src/features/billing/InvoiceForm.tsx`

- [ ] **Step 2: Write the failing tests**

`ArchiveActions.test.tsx` — import `ArchivedSubscriptionBanner`, `CanProvider` (`@/features/identity/permissions`) and `staffMe` (`@/test/access-fixtures`); append:

```tsx
describe("ArchivedSubscriptionBanner", () => {
	beforeEach(() => vi.clearAllMocks());

	const archived = subscriptionDetail({
		status: "cancelled",
		archived_at: "2026-06-04T22:30:00Z",
		archived_by: { id: 51, full_name: "Amina" },
	});

	it("says when and by whom, in the academy's calendar, and restores", async () => {
		vi.mocked(schedulingApi.restore).mockResolvedValue(subscriptionDetail());
		const user = userEvent.setup();
		renderWithRouter(
			<ArchivedSubscriptionBanner sub={archived} academyZone="Asia/Riyadh" />,
		);
		expect(
			screen.getByText("Archived on Jun 5, 2026 by Amina."),
		).toBeInTheDocument();
		await user.click(screen.getByRole("button", { name: "Restore" }));
		await waitFor(() => expect(schedulingApi.restore).toHaveBeenCalledWith(7));
		expect(await screen.findByText("Subscription restored.")).toBeInTheDocument();
	});

	it("names the system, hides Restore without the code, and shows nothing for a live one", () => {
		const { unmount } = renderWithRouter(
			<CanProvider me={staffMe("subscription.view")}>
				<ArchivedSubscriptionBanner
					sub={{ ...archived, archived_by: null }}
					academyZone="UTC"
				/>
			</CanProvider>,
		);
		expect(screen.getByText("Archived on Jun 4, 2026.")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Restore" })).toBeNull();
		unmount();
		renderWithRouter(
			<ArchivedSubscriptionBanner
				sub={subscriptionDetail({ archived_at: null })}
				academyZone="UTC"
			/>,
		);
		expect(screen.queryByText(/^Archived on/)).toBeNull();
	});
});
```

`SubscriptionActions.test.tsx` — add `archive: vi.fn()` to the file's `schedulingApi` mock; append inside its `describe`:

```tsx
	it("offers Archive where the server allows it and no Renew once archived (B2d)", () => {
		const { unmount } = renderWithRouter(
			<SubscriptionActions
				sub={subscriptionDetail({ status: "expired", can_archive: true })}
			/>,
		);
		expect(
			screen.getByRole("button", { name: "Archive (delete keeping records)" }),
		).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Renew" })).toBeInTheDocument();
		unmount();
		renderWithRouter(
			<SubscriptionActions
				sub={subscriptionDetail({
					status: "expired",
					can_archive: false,
					archived_at: "2026-06-04T08:00:00Z",
				})}
			/>,
		);
		expect(
			screen.queryByRole("button", { name: "Archive (delete keeping records)" }),
		).toBeNull();
		expect(screen.queryByRole("button", { name: "Renew" })).toBeNull();
	});

	it("hides Archive from staff without subscription.delete (B2d)", () => {
		renderWithRouter(
			<CanProvider me={staffMe("subscription.update")}>
				<SubscriptionActions
					sub={subscriptionDetail({ status: "expired", can_archive: true })}
				/>
			</CanProvider>,
		);
		expect(
			screen.queryByRole("button", { name: "Archive (delete keeping records)" }),
		).toBeNull();
	});
```

`SubscriptionDetail.test.tsx` — append:

```tsx
	it("opens an archived subscription with its banner (B2d)", async () => {
		vi.mocked(schedulingApi.get).mockResolvedValue(
			subscriptionDetail({
				status: "cancelled",
				archived_at: "2026-06-04T08:00:00Z",
				archived_by: { id: 51, full_name: "Amina" },
			}),
		);
		renderWithRouter(<SubscriptionDetail subscriptionId="7" />);
		expect(
			await screen.findByText("Archived on Jun 4, 2026 by Amina."),
		).toBeInTheDocument();
	});
```

`SessionsPanel.test.tsx` — append:

```tsx
	it("marks an archived session (B2d)", async () => {
		vi.mocked(schedulingApi.sessions).mockResolvedValue(
			page([sessionRow({ archived_at: "2026-06-04T08:00:00Z" })]),
		);
		renderWithRouter(<SessionsPanel subscriptionId={7} academyZone="UTC" />);
		const table = await screen.findByRole("table");
		expect(within(table).getByText("Archived")).toBeInTheDocument();
	});
```

`InvoiceForm.test.tsx` — the existing expectation `toHaveBeenCalledWith({ student: "11", page_size: 100 })` becomes `{ student: "11", page_size: 100, archived: "include" }` (outside the app shell every switch is on); add, with `CanProvider` and `adminWith` imported:

```tsx
	it("asks for archived subscriptions only while the archive is on (B2d)", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<CanProvider me={adminWith("invoices")}>
				<InvoiceForm />
			</CanProvider>,
			{ extraPaths: [DETAIL] },
		);
		await user.selectOptions(await screen.findByLabelText(/^Student/), "11");
		await waitFor(() =>
			expect(schedulingApi.list).toHaveBeenCalledWith({
				student: "11",
				page_size: 100,
			}),
		);
	});
```

- [ ] **Step 3: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/ArchiveActions.test.tsx src/features/scheduling/SubscriptionActions.test.tsx src/features/scheduling/SubscriptionDetail.test.tsx src/features/scheduling/SessionsPanel.test.tsx src/features/billing/InvoiceForm.test.tsx`
Expected: FAIL (`ArchivedSubscriptionBanner` is not exported; no Archive button; Renew still shown; no badge; the picker's call lacks `archived`). Keep the output.

- [ ] **Step 4: Implement**

`ArchiveActions.tsx` — add `import { useCan } from "@/features/identity/permissions";`, `import { dayIn } from "@/lib/zoned-time";`, `Alert` and `AlertDescription` to the `@/ui` import, and `SubscriptionDetail` to the type import; then:

```tsx
/** Spec §7: an archived subscription's detail says so, with Restore. The
 * day is the academy's (the server sends the instant). */
export function ArchivedSubscriptionBanner({
	sub,
	academyZone,
}: {
	sub: SubscriptionDetail;
	academyZone: string;
}) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const fail = useFail();
	const restore = useSchedulingMutation(schedulingApi.restore);
	if (!sub.archived_at) return null;
	const date = dayIn(new Date(sub.archived_at), academyZone, i18n.language);
	return (
		<Alert>
			<AlertDescription className="flex flex-wrap items-center justify-between gap-2">
				<p>
					{sub.archived_by
						? t("archives.subscriptions.banner", {
								date,
								name: sub.archived_by.full_name,
							})
						: t("archives.subscriptions.bannerSystem", { date })}
				</p>
				{can("subscription.restore") ? (
					<Button
						size="sm"
						variant="outline"
						disabled={restore.isPending}
						onClick={() =>
							restore.mutate(sub.id, {
								onSuccess: () =>
									toast({
										description: t("archives.subscriptions.restored"),
										variant: "success",
									}),
								onError: fail,
							})
						}
					>
						{t("archives.subscriptions.restore")}
					</Button>
				) : null}
			</AlertDescription>
		</Alert>
	);
}
```

`SubscriptionDetail.tsx` — import `ArchivedSubscriptionBanner` from `./ArchiveActions`; first child of the returned column:

```tsx
			<ArchivedSubscriptionBanner sub={sub} academyZone={academy.timezone} />
			<SubscriptionActions sub={sub} />
```

`SubscriptionActions.tsx` — import `ArchiveSubscriptionButton`; the Renew branch becomes `) : sub.status !== "cancelled" && !sub.archived_at && editable ? (` (plan D10); before the Delete `Confirm`:

```tsx
			{/* Slice B2d: the server's `can_archive` (ended, nothing due). */}
			{sub.can_archive && can("subscription.delete") ? (
				<ArchiveSubscriptionButton sub={sub} />
			) : null}
```

`SessionsPanel.tsx` — import `ArchivedBadge`; the status cell becomes:

```tsx
										<td className="p-2">
											{t(`scheduling.sessions.status.${session.status}`)}
											<SessionKindChip kind={session.kind} />
											{session.archived_at ? <ArchivedBadge /> : null}
										</td>
```

`billing/InvoiceForm.tsx` — import `useHasFeature` from `@/features/identity/permissions`; in the component, before the `useSubscriptions` call:

```tsx
	const hasFeature = useHasFeature();
```

and the call becomes:

```tsx
	// Slice B2d §4.4: an archived subscription is still invoiced; asking for
	// it exists only while the archive is on (Plan 31 D14).
	const { data: subscriptions } = useSubscriptions(
		{
			student: chosen,
			page_size: 100,
			...(hasFeature("subscription_archive") ? { archived: "include" } : {}),
		},
		{ enabled: studentId !== undefined },
	);
```

- [ ] **Step 5: Run, then verify**

Run: the Step 3 command → PASS; then `… pnpm exec vitest run src/features/scheduling src/features/billing`, `… pnpm exec biome check --write src`, `… pnpm exec tsc --noEmit`, `… pnpm lint`, `… pnpm test:coverage`.

- [ ] **Step 6: Commit, then release the claim**

```bash
git -C dashboard add src/features/scheduling/ArchiveActions.tsx src/features/scheduling/ArchiveActions.test.tsx src/features/scheduling/SubscriptionDetail.tsx src/features/scheduling/SubscriptionDetail.test.tsx src/features/scheduling/SubscriptionActions.tsx src/features/scheduling/SubscriptionActions.test.tsx src/features/scheduling/SessionsPanel.tsx src/features/scheduling/SessionsPanel.test.tsx src/features/billing/InvoiceForm.tsx src/features/billing/InvoiceForm.test.tsx
git -C dashboard commit -m "feat(scheduling): archived subscription banner, Archive action, picker includes archived (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Run (from `$W`): `python3 scripts/orchestration/ledger.py release B2 dashboard/src/features/billing/InvoiceForm.tsx`

---
### Task 13: Archiving sessions from the list, the session archive screen, the session's banner

**Files:**
- Modify: `dashboard/src/features/scheduling/SessionBulkBar.tsx`, `SessionsList.tsx` (+ `SessionsList.test.tsx`)
- Modify: `dashboard/src/features/scheduling/ArchiveActions.tsx` (+ test) — `ArchivedSessionBanner`
- Modify: `dashboard/src/features/scheduling/SessionPage.tsx` (+ `SessionPage.test.tsx`)
- Create: `dashboard/src/routes/_authed/scheduling.sessions.archive.tsx`
- Modify: `dashboard/src/routes/permissions.test.ts` (`FEATURE_SCREENS`), `dashboard/src/routeTree.gen.ts` (regenerated)

**Interfaces:**
- Consumes: Task 10 (`schedulingApi.archiveSessions`, `.unarchiveSessions`, `Session.archived_at`), Task 11 (`ArchiveActions.tsx`'s `useFail`).
- Produces:
  - `SessionBulkBar({ selected, onDone, marks = true, shelf }: { selected: number[]; onDone: () => void; marks?: boolean; shelf?: "archive" | "unarchive" })` — Present / Absent / Cancel only with `marks`; an "Archive" (`shelf="archive"`) or "Restore" (`shelf="unarchive"`) button that posts the chosen ids; the same "Done: d. Skipped: s." summary with each skip's translated code.
  - `SessionsList({ archive = false }: { archive?: boolean })`. Normal: a "More views" nav with "Archive" (while `session_archive` is on); the bar gets `shelf="archive"` with `can("session.delete")` and the switch. Archive: params `{ page: 1, archived: "only" }` (period "All"), "Archived from" / "Archived to" filters, an "Archived" column (academy day), the bar with Present / Absent / Cancel (`session.update`) and `shelf="unarchive"` (`session.restore`), "Back to the list", no "Add session". Selection shows when any bar action is allowed.
  - `ArchivedSessionBanner({ session, academyZone })` — nothing unless `session.archived_at`; else "Archived on <academy day>." and, with `session.restore`, Restore (`unarchiveSessions([id])`; a skip shows its translated code, else "Session restored."). `SessionPage` renders it first; Postpone already hides itself (`can_postpone` is false, Task 5).
  - Route `/_authed/scheduling/sessions/archive` (`permission: "session.view_any"`, `feature: "session_archive"`).

- [ ] **Step 1: Write the failing tests**

`SessionsList.test.tsx` — add `archiveSessions: vi.fn()` and `unarchiveSessions: vi.fn()` to the file's `schedulingApi` mock; append inside `describe("SessionsList")`:

```tsx
	it("links to the archive and archives the chosen sessions (B2d)", async () => {
		vi.mocked(schedulingApi.archiveSessions).mockResolvedValue({
			done: [41],
			skipped: [{ id: 42, code: "scheduling.not_allowed_in_status" }],
		});
		const user = userEvent.setup();
		renderWithRouter(<SessionsList />);
		expect(await screen.findByRole("link", { name: "Archive" })).toHaveAttribute(
			"href",
			"/scheduling/sessions/archive",
		);
		await user.click(
			await screen.findByLabelText("Select every session on this page"),
		);
		const bar = screen.getByRole("region", { name: "Bulk actions" });
		await user.click(within(bar).getByRole("button", { name: "Archive" }));
		await waitFor(() =>
			expect(schedulingApi.archiveSessions).toHaveBeenCalledWith([41, 42]),
		);
		expect(await screen.findByText("Done: 1. Skipped: 1.")).toBeInTheDocument();
		expect(
			screen.getByText("Session 42: That isn't possible in the current status."),
		).toBeInTheDocument();
	});

	it("offers no archive while it is off (B2d)", async () => {
		renderWithRouter(
			<CanProvider me={adminWith()}>
				<SessionsList />
			</CanProvider>,
		);
		await selectPage();
		expect(screen.queryByRole("link", { name: "Archive" })).toBeNull();
		const bar = screen.getByRole("region", { name: "Bulk actions" });
		expect(within(bar).queryByRole("button", { name: "Archive" })).toBeNull();
		expect(within(bar).getByRole("button", { name: "Mark present" })).toBeVisible();
	});

	it("is the session archive: only archived rows, its filters, marks and Restore (B2d)", async () => {
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(
			page([sessionRow({ archived_at: "2026-06-04T08:00:00Z" })]),
		);
		vi.mocked(schedulingApi.unarchiveSessions).mockResolvedValue({
			done: [41],
			skipped: [],
		});
		const user = userEvent.setup();
		renderWithRouter(<SessionsList archive />);
		const table = await screen.findByRole("table");
		expect(lastParams()).toEqual({ page: 1, archived: "only" });
		expect(screen.getByLabelText("Period")).toHaveValue("all");
		expect(within(table).getByText("Jun 4, 2026")).toBeInTheDocument();
		expect(screen.getByRole("link", { name: "Back to the list" })).toHaveAttribute(
			"href",
			"/scheduling/sessions",
		);
		expect(screen.queryByRole("button", { name: "Add session" })).toBeNull();
		await user.type(screen.getByLabelText("Archived from"), "2026-06-01");
		await waitFor(() =>
			expect(lastParams()).toEqual({
				page: 1,
				archived: "only",
				archived_from: "2026-06-01",
			}),
		);
		await user.click(
			await screen.findByLabelText("Select Yusuf's session on Jun 1, 2026"),
		);
		const bar = screen.getByRole("region", { name: "Bulk actions" });
		expect(within(bar).getByRole("button", { name: "Mark present" })).toBeVisible();
		await user.click(within(bar).getByRole("button", { name: "Restore" }));
		await waitFor(() =>
			expect(schedulingApi.unarchiveSessions).toHaveBeenCalledWith([41]),
		);
		expect(await screen.findByText("Done: 1. Skipped: 0.")).toBeInTheDocument();
	});

	it("lets staff who may only restore choose rows in the archive, without the marks (B2d)", async () => {
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(
			page([sessionRow({ archived_at: "2026-06-04T08:00:00Z" })]),
		);
		const user = userEvent.setup();
		renderWithRouter(
			<CanProvider me={staffMe("session.view_any", "session.restore")}>
				<SessionsList archive />
			</CanProvider>,
		);
		await user.click(
			await screen.findByLabelText("Select Yusuf's session on Jun 1, 2026"),
		);
		const bar = screen.getByRole("region", { name: "Bulk actions" });
		expect(within(bar).getByRole("button", { name: "Restore" })).toBeVisible();
		expect(within(bar).queryByRole("button", { name: "Mark present" })).toBeNull();
	});
```

with this helper above the `describe` (the switch-off test needs a selection to see the bar):

```tsx
async function selectPage() {
	await userEvent.setup().click(
		await screen.findByLabelText("Select every session on this page"),
	);
}
```

`ArchiveActions.test.tsx` — add `unarchiveSessions: vi.fn()` to the mock, import `ArchivedSessionBanner` and `sessionRow`; append:

```tsx
describe("ArchivedSessionBanner", () => {
	beforeEach(() => vi.clearAllMocks());

	const archived = sessionRow({ archived_at: "2026-06-04T08:00:00Z" });

	it("says since when and restores", async () => {
		vi.mocked(schedulingApi.unarchiveSessions).mockResolvedValue({
			done: [41],
			skipped: [],
		});
		const user = userEvent.setup();
		renderWithRouter(<ArchivedSessionBanner session={archived} academyZone="UTC" />);
		expect(screen.getByText("Archived on Jun 4, 2026.")).toBeInTheDocument();
		await user.click(screen.getByRole("button", { name: "Restore" }));
		await waitFor(() =>
			expect(schedulingApi.unarchiveSessions).toHaveBeenCalledWith([41]),
		);
		expect(await screen.findByText("Session restored.")).toBeInTheDocument();
	});

	it("shows the server's refusal, and nothing for a session in the lists", async () => {
		vi.mocked(schedulingApi.unarchiveSessions).mockResolvedValue({
			done: [],
			skipped: [{ id: 41, code: "scheduling.archived" }],
		});
		const user = userEvent.setup();
		const { unmount } = renderWithRouter(
			<ArchivedSessionBanner session={archived} academyZone="UTC" />,
		);
		await user.click(screen.getByRole("button", { name: "Restore" }));
		expect(
			await screen.findByText("This is archived. Restore it first."),
		).toBeInTheDocument();
		unmount();
		renderWithRouter(<ArchivedSessionBanner session={sessionRow()} academyZone="UTC" />);
		expect(screen.queryByText(/^Archived on/)).toBeNull();
	});
});
```

`SessionPage.test.tsx` — add `unarchiveSessions: vi.fn()` to its `schedulingApi` mock; append:

```tsx
	it("shows an archived session's banner first (B2d)", async () => {
		vi.mocked(schedulingApi.session).mockResolvedValue(
			sessionRow({ archived_at: "2026-06-04T08:00:00Z", can_postpone: false }),
		);
		renderWithRouter(<SessionPage sessionId="41" />);
		expect(
			await screen.findByText("Archived on Jun 4, 2026."),
		).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Restore" })).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Postpone" })).toBeNull();
	});
```

`permissions.test.ts`: `FEATURE_SCREENS` gains `"/_authed/scheduling/sessions/archive": "session_archive",`.

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/SessionsList.test.tsx src/features/scheduling/ArchiveActions.test.tsx src/features/scheduling/SessionPage.test.tsx src/routes/permissions.test.ts`
Expected: FAIL (no "Archive" link or button; `ArchivedSessionBanner` is not exported; the route is missing). Keep the output.

- [ ] **Step 3: `SessionBulkBar.tsx`** (whole file)

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { codeKey, errorText } from "@/lib/form-errors";
import { Alert, AlertDescription, Button, toast } from "@/ui";
import { schedulingApi } from "./api";
import { CancelSessionDialog } from "./CancelSessionDialog";
import { useSchedulingMutation } from "./queries";
import type { BulkBody, BulkResult } from "./schemas";

/** Spec §4.4 / §6: present, absent or cancel (with a reason) for the chosen
 * sessions, then a summary of what was done and what was skipped, and why.
 * Slice B2d: `shelf` adds Archive or Restore for the chosen ones (§4.2);
 * `marks` false leaves the three marks out (a staff account that may only
 * archive or restore). */
export function SessionBulkBar({
	selected,
	onDone,
	marks = true,
	shelf,
}: {
	selected: number[];
	onDone: () => void;
	marks?: boolean;
	shelf?: "archive" | "unarchive";
}) {
	const { t } = useTranslation();
	const [result, setResult] = useState<BulkResult | null>(null);
	const bulk = useSchedulingMutation(schedulingApi.bulk);
	const shelve = useSchedulingMutation((ids: number[]) =>
		shelf === "unarchive"
			? schedulingApi.unarchiveSessions(ids)
			: schedulingApi.archiveSessions(ids),
	);
	const busy = bulk.isPending || shelve.isPending;
	const fail = (error: unknown) =>
		toast({ description: errorText(error, t), variant: "destructive" });

	async function show(outcome: Promise<BulkResult>) {
		setResult(await outcome);
		onDone();
	}

	const run = (body: BulkBody) => show(bulk.mutateAsync(body));
	const mark = (action: "present" | "absent") =>
		run({ ids: selected, action }).catch(fail);

	return (
		<>
			{selected.length > 0 ? (
				<section
					aria-label={t("scheduling.bulk.label")}
					className="flex flex-wrap items-center gap-2 rounded-lg border border-border bg-secondary p-3"
				>
					<span className="text-sm font-medium">
						{t("scheduling.bulk.selected", { count: selected.length })}
					</span>
					{marks ? (
						<>
							<Button
								size="sm"
								variant="outline"
								disabled={busy}
								onClick={() => mark("present")}
							>
								{t("scheduling.bulk.present")}
							</Button>
							<Button
								size="sm"
								variant="outline"
								disabled={busy}
								onClick={() => mark("absent")}
							>
								{t("scheduling.bulk.absent")}
							</Button>
							<CancelSessionDialog
								action={t("scheduling.bulk.cancel")}
								body={t("scheduling.bulk.cancelBody", {
									count: selected.length,
								})}
								onCancel={(reason) =>
									run({ ids: selected, action: "cancel", reason })
								}
							/>
						</>
					) : null}
					{shelf ? (
						<Button
							size="sm"
							variant="outline"
							disabled={busy}
							onClick={() => show(shelve.mutateAsync(selected)).catch(fail)}
						>
							{t(
								shelf === "unarchive"
									? "archives.sessions.restore"
									: "archives.sessions.action",
							)}
						</Button>
					) : null}
				</section>
			) : null}
			{result ? (
				<Alert>
					<AlertDescription>
						<p>
							{t("scheduling.bulk.result", {
								done: result.done.length,
								skipped: result.skipped.length,
							})}
						</p>
						{result.skipped.length > 0 ? (
							<ul className="mt-2 list-disc ps-5">
								{result.skipped.map((s) => (
									<li key={s.id}>
										{t("scheduling.bulk.skippedRow", {
											id: s.id,
											reason: t(codeKey(s.code)),
										})}
									</li>
								))}
							</ul>
						) : null}
					</AlertDescription>
				</Alert>
			) : null}
		</>
	);
}
```

- [ ] **Step 4: `SessionsList.tsx`** (whole component; what is new is marked "Slice B2d")

```tsx
import { Link } from "@tanstack/react-router";
import { CalendarClock } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ExportButton } from "@/components/ExportButton";
import { Pager } from "@/components/Pager";
import { useAcademySettings } from "@/features/academy/queries";
import { type Course, useCatalogue } from "@/features/catalogue";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { usePeople } from "@/features/people";
import type { QueryParams } from "@/lib/api";
import { dayIn, formatDay, otherZoneTime, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	Checkbox,
	EmptyState,
	Input,
	Select,
	Spinner,
} from "@/ui";
import { AddSessionDialog } from "./AddSessionDialog";
import { sessionsCsvUrl } from "./api";
import { SessionStatusChip, useLocalName } from "./bits";
import { useSessionList } from "./queries";
import { SessionBulkBar } from "./SessionBulkBar";
import { SessionKindChip } from "./SessionKindChip";
import { ATTENDANCE, SESSION_STATUSES, type Session } from "./schemas";

// The backend paginates at 25 rows a page (StandardPagination).
const PAGE_SIZE = 25;
const PERIODS = ["today", "week", "upcoming", "past", "all"] as const;
// Slice B2a: the kind tabs; make-up and extra wait for their switches.
const KIND_TABS = [
	["all", undefined, undefined],
	["regular", "regular", undefined],
	["compensation", "compensation", "compensation_sessions"],
	["extra", "extra", "extra_sessions"],
] as const;
// Slice B2d §6.1: the archive's own days.
const ARCHIVE_DAYS = [
	["archived_from", "archives.filters.archivedFrom"],
	["archived_to", "archives.filters.archivedTo"],
] as const;
const LINK =
	"font-medium text-primary-text underline-offset-4 hover:underline";

/** Spec §6 Sessions (admin): filters, search, paging, CSV and bulk actions.
 * Times are the academy's, with the student's when their clock differs.
 * Slice B2d: bulk Archive, and, with `archive`, the session archive —
 * `archived=only`, its days, the marks and Restore. */
export function SessionsList({ archive = false }: { archive?: boolean }) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const hasFeature = useHasFeature();
	// The marks are session updates; archiving needs `session.delete` and
	// restoring `session.restore` (spec §5). Without any of them, no selection.
	const marks = can("session.update");
	const shelf = archive
		? can("session.restore")
		: hasFeature("session_archive") && can("session.delete");
	const bulk = marks || shelf;
	const localName = useLocalName();
	const [params, setParams] = useState<QueryParams>(
		archive ? { page: 1, archived: "only" } : { when: "today", page: 1 },
	);
	const [selected, setSelected] = useState<number[]>([]);
	const { data: academy } = useAcademySettings();
	const { data, isPending, isError } = useSessionList(params);
	// Plan 12a fix round 1: filters are fetched only when the viewer may list
	// teachers/courses themselves — never a 403 behind this screen's own
	// session.view_any (Important 1).
	const listTeachers = can("teacher.view_any");
	const listCourses = can("course.view_any");
	const { data: teachers } = usePeople(
		"teachers",
		{ page_size: 100 },
		{ enabled: listTeachers },
	);
	const { data: courses } = useCatalogue<Course>(
		"courses",
		{ page_size: 100 },
		{ enabled: listCourses },
	);
	const rows = data?.results ?? [];
	const addKinds = (
		[
			["regular", "manual_sessions"],
			["extra", "extra_sessions"],
		] as const
	)
		.filter(([, feature]) => hasFeature(feature))
		.map(([kind]) => kind);
	// Plan 12b: a Supervisor column while general supervision is on.
	const supervision = academy?.supervision_enabled === true;
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const update = (patch: QueryParams) => {
		setParams({ ...params, page: 1, ...patch });
		setSelected([]);
	};
	const pageIds = rows.map((row) => row.id);
	const allChosen =
		pageIds.length > 0 && pageIds.every((id) => selected.includes(id));

	function toggle(id: number) {
		setSelected(
			selected.includes(id)
				? selected.filter((x) => x !== id)
				: [...selected, id],
		);
	}

	function archivedOn(session: Session) {
		if (!session.archived_at || !academy) return "—";
		return dayIn(new Date(session.archived_at), academy.timezone, i18n.language);
	}

	const choice = (
		key: string,
		label: string,
		any: string,
		options: { value: string | number; label: string }[],
	) => (
		<Select
			aria-label={label}
			className="w-auto"
			value={String(params[key] ?? "")}
			onChange={(e) => update({ [key]: e.target.value })}
		>
			<option value="">{any}</option>
			{options.map((o) => (
				<option key={o.value} value={o.value}>
					{o.label}
				</option>
			))}
		</Select>
	);

	return (
		<div className="flex flex-col gap-4">
			<nav aria-label={t("archives.links")} className="flex flex-wrap gap-3 text-sm">
				{archive ? (
					<Link to="/scheduling/sessions" className={LINK}>
						{t("archives.back")}
					</Link>
				) : hasFeature("session_archive") ? (
					<Link to="/scheduling/sessions/archive" className={LINK}>
						{t("archives.archive")}
					</Link>
				) : null}
			</nav>
			<fieldset className="flex flex-wrap gap-2">
				<legend className="sr-only">{t("sessionClasses.tabs.label")}</legend>
				{KIND_TABS.filter(
					([, , feature]) => !feature || hasFeature(feature),
				).map(([key, kind]) => (
					<Button
						key={key}
						size="sm"
						variant={params.kind === kind ? "primary" : "outline"}
						aria-pressed={params.kind === kind}
						onClick={() => update({ kind })}
					>
						{t(`sessionClasses.tabs.${key}`)}
					</Button>
				))}
			</fieldset>
			<div className="flex flex-wrap items-end gap-3">
				<Select
					aria-label={t("scheduling.list.period")}
					className="w-auto"
					value={String(params.when ?? "all")}
					onChange={(e) =>
						update({
							when: e.target.value === "all" ? undefined : e.target.value,
						})
					}
				>
					{PERIODS.map((period) => (
						<option key={period} value={period}>
							{t(`scheduling.list.periods.${period}`)}
						</option>
					))}
				</Select>
				<div className="flex flex-col gap-1">
					<label htmlFor="sessions-from" className="text-xs">
						{t("scheduling.list.from")}
					</label>
					<Input
						id="sessions-from"
						type="date"
						dir="ltr"
						className="w-auto"
						value={String(params.from ?? "")}
						onChange={(e) => update({ from: e.target.value })}
					/>
				</div>
				<div className="flex flex-col gap-1">
					<label htmlFor="sessions-to" className="text-xs">
						{t("scheduling.list.to")}
					</label>
					<Input
						id="sessions-to"
						type="date"
						dir="ltr"
						className="w-auto"
						value={String(params.to ?? "")}
						onChange={(e) => update({ to: e.target.value })}
					/>
				</div>
				{archive
					? ARCHIVE_DAYS.map(([key, label]) => (
							<div key={key} className="flex flex-col gap-1">
								<label htmlFor={`sessions-${key}`} className="text-xs">
									{t(label)}
								</label>
								<Input
									id={`sessions-${key}`}
									type="date"
									dir="ltr"
									className="w-auto"
									value={String(params[key] ?? "")}
									onChange={(e) => update({ [key]: e.target.value })}
								/>
							</div>
						))
					: null}
				{choice(
					"status",
					t("scheduling.columns.status"),
					t("scheduling.list.anyStatus"),
					// Always offered: records made while the switch was on stay findable
					// when it is off (A-13).
					SESSION_STATUSES.map((s) => ({
						value: s,
						label: t(`scheduling.sessions.status.${s}`),
					})),
				)}
				{choice(
					"student_attendance",
					t("scheduling.list.studentAttendance"),
					t("scheduling.list.anyAttendance"),
					ATTENDANCE.map((a) => ({
						value: a,
						label: t(`scheduling.attendance.${a}`),
					})),
				)}
				{listTeachers
					? choice(
							"teacher",
							t("scheduling.columns.teacher"),
							t("scheduling.anyTeacher"),
							(teachers?.results ?? []).map((p) => ({
								value: p.id,
								label: p.user.full_name,
							})),
						)
					: null}
				{listCourses
					? choice(
							"course",
							t("scheduling.columns.course"),
							t("scheduling.anyCourse"),
							(courses?.results ?? []).map((c) => ({
								value: c.id,
								label: localName(c),
							})),
						)
					: null}
				<div className="min-w-48 flex-1">
					<label htmlFor="sessions-search" className="sr-only">
						{t("scheduling.search")}
					</label>
					<Input
						id="sessions-search"
						type="search"
						placeholder={t("scheduling.search")}
						value={String(params.q ?? "")}
						onChange={(e) => update({ q: e.target.value })}
					/>
				</div>
				{!archive && can("session.create") && academy && addKinds.length > 0 ? (
					<AddSessionDialog
						kinds={[...addKinds]}
						academyZone={academy.timezone}
					/>
				) : null}
				<ExportButton href={sessionsCsvUrl(params)} />
			</div>
			{bulk ? (
				<SessionBulkBar
					selected={selected}
					onDone={() => setSelected([])}
					marks={marks}
					shelf={shelf ? (archive ? "unarchive" : "archive") : undefined}
				/>
			) : null}
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>
						{t("scheduling.sessions.loadError")}
					</AlertDescription>
				</Alert>
			) : isPending || !academy ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState
							icon={CalendarClock}
							title={t(
								archive ? "archives.sessions.empty" : "scheduling.list.empty",
							)}
						/>
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								<th scope="col" className="w-10 p-3" hidden={!bulk}>
									<Checkbox
										id="select-page"
										checked={allChosen}
										onCheckedChange={(on) =>
											setSelected(
												on
													? [...new Set([...selected, ...pageIds])]
													: selected.filter((id) => !pageIds.includes(id)),
											)
										}
									/>
									<label htmlFor="select-page" className="sr-only">
										{t("scheduling.list.selectPage")}
									</label>
								</th>
								{(
									[
										"date",
										"time",
										"student",
										"teacher",
										"course",
										"status",
										"attendance",
									] as const
								).map((key) => (
									<th
										key={key}
										scope="col"
										className="p-3 text-start font-medium"
									>
										{t(`scheduling.list.columns.${key}`)}
									</th>
								))}
								{supervision ? (
									<th scope="col" className="p-3 text-start font-medium">
										{t("scheduling.supervision.supervisor")}
									</th>
								) : null}
								{archive ? (
									<th scope="col" className="p-3 text-start font-medium">
										{t("archives.columns.archivedAt")}
									</th>
								) : null}
							</tr>
						</thead>
						<tbody>
							{rows.map((session) => {
								const instant = new Date(session.starts_at);
								const theirs = otherZoneTime(
									instant,
									session.student.timezone,
									academy.timezone,
									i18n.language,
								);
								return (
									<tr key={session.id} className="border-t border-border">
										<td className="p-3" hidden={!bulk}>
											<Checkbox
												id={`select-${session.id}`}
												checked={selected.includes(session.id)}
												onCheckedChange={() => toggle(session.id)}
											/>
											<label
												htmlFor={`select-${session.id}`}
												className="sr-only"
											>
												{t("scheduling.list.select", {
													name: session.student.full_name,
													date: formatDay(session.occurs_on, i18n.language),
												})}
											</label>
										</td>
										<td className="p-3">
											{formatDay(session.occurs_on, i18n.language)}
										</td>
										<td className="p-3">
											<span dir="ltr">
												{wallTime(instant, academy.timezone, i18n.language)}
											</span>
											{theirs ? (
												<span className="block text-xs text-muted-foreground">
													{t("scheduling.slots.studentTime", { time: theirs })}
												</span>
											) : null}
										</td>
										<td className="p-3">
											<Link
												to="/scheduling/sessions/$sessionId"
												params={{ sessionId: String(session.id) }}
												className={LINK}
											>
												{session.student.full_name}
											</Link>
										</td>
										<td className="p-3">{session.teacher.full_name}</td>
										<td className="p-3">{localName(session.course)}</td>
										<td className="p-3">
											<span className="flex flex-wrap items-center gap-1">
												<SessionStatusChip status={session.status} />
												<SessionKindChip kind={session.kind} />
											</span>
										</td>
										<td className="p-3 text-xs">
											{t("scheduling.list.attendanceCell", {
												student: t(
													`scheduling.attendance.${session.student_attendance}`,
												),
												teacher: t(
													`scheduling.attendance.${session.teacher_attendance}`,
												),
											})}
										</td>
										{supervision ? (
											<td className="p-3 text-xs">
												{session.supervisor
													? t("scheduling.supervision.cell", {
															name: session.supervisor.full_name,
															attendance: t(
																`scheduling.attendance.${session.supervisor_attendance ?? "not_set"}`,
															),
														})
													: "—"}
											</td>
										) : null}
										{archive ? (
											<td className="p-3">{archivedOn(session)}</td>
										) : null}
									</tr>
								);
							})}
						</tbody>
					</table>
				</div>
			)}
			<Pager
				page={page}
				pages={pages}
				onChange={(next) => {
					setParams({ ...params, page: next });
					setSelected([]);
				}}
			/>
		</div>
	);
}
```

- [ ] **Step 5: `ArchivedSessionBanner`** (`ArchiveActions.tsx`; add `codeKey` to the `@/lib/form-errors` import and `Session` to the type import)

```tsx
/** Spec §7: an archived session's page says so, with Restore (one id on the
 * bulk route, plan D8; a refusal comes back as a skip code). */
export function ArchivedSessionBanner({
	session,
	academyZone,
}: {
	session: Session;
	academyZone: string;
}) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const fail = useFail();
	const restore = useSchedulingMutation(schedulingApi.unarchiveSessions);
	if (!session.archived_at) return null;
	const date = dayIn(new Date(session.archived_at), academyZone, i18n.language);

	function run() {
		restore.mutate([session.id], {
			onSuccess: ({ skipped }) =>
				toast(
					skipped[0]
						? { description: t(codeKey(skipped[0].code)), variant: "destructive" }
						: { description: t("archives.sessions.restored"), variant: "success" },
				),
			onError: fail,
		});
	}

	return (
		<Alert>
			<AlertDescription className="flex flex-wrap items-center justify-between gap-2">
				<p>{t("archives.sessions.banner", { date })}</p>
				{can("session.restore") ? (
					<Button
						size="sm"
						variant="outline"
						disabled={restore.isPending}
						onClick={run}
					>
						{t("archives.sessions.restore")}
					</Button>
				) : null}
			</AlertDescription>
		</Alert>
	);
}
```

`SessionPage.tsx` — import `ArchivedSessionBanner`; first child of the returned column:

```tsx
			<ArchivedSessionBanner session={session} academyZone={academy.timezone} />
```

- [ ] **Step 6: The route** (`src/routes/_authed/scheduling.sessions.archive.tsx`)

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SessionsList } from "@/features/scheduling";
import { PageHeader } from "@/ui";

// Slice B2d (spec §7): the session archive.
export const Route = createFileRoute("/_authed/scheduling/sessions/archive")({
	staticData: { permission: "session.view_any", feature: "session_archive" },
	component: function SessionArchiveRoute() {
		const { t } = useTranslation();
		usePageTitle(t("archives.sessions.title"));
		return (
			<>
				<PageHeader title={t("archives.sessions.title")} />
				<SessionsList archive />
			</>
		);
	},
});
```

Regenerate the route tree: `… exec -T dashboard pnpm exec vite build`.

- [ ] **Step 7: Run, then verify**

Run: the Step 2 command → PASS; then every test file that renders `SessionsList`, `SessionBulkBar` or `SessionPage` (`grep -rln "SessionsList\|SessionBulkBar\|SessionPage" src --include=*.test.tsx`, which includes `SupervisorFields.test.tsx`), then `… pnpm exec biome check --write src`, `… pnpm exec tsc --noEmit`, `… pnpm lint`, `… pnpm test:coverage`.

- [ ] **Step 8: Commit**

```bash
git -C dashboard add src/features/scheduling/SessionBulkBar.tsx src/features/scheduling/SessionsList.tsx src/features/scheduling/SessionsList.test.tsx src/features/scheduling/ArchiveActions.tsx src/features/scheduling/ArchiveActions.test.tsx src/features/scheduling/SessionPage.tsx src/features/scheduling/SessionPage.test.tsx src/routes/_authed/scheduling.sessions.archive.tsx src/routes/permissions.test.ts src/routeTree.gen.ts
git -C dashboard commit -m "feat(scheduling): archive sessions in bulk, the session archive and its banner (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 14: The simplified sessions view

**Files:**
- Modify: `dashboard/src/features/scheduling/AttendanceControls.tsx` (export `attendanceClosed`; the controls use it)
- Create: `dashboard/src/features/scheduling/SimpleSessions.tsx` (+ `SimpleSessions.test.tsx`)
- Modify: `dashboard/src/features/scheduling/SessionsList.tsx` (+ test) — the "Simplified view" link
- Modify: `dashboard/src/features/scheduling/index.ts` (export `SimpleSessions`)
- Create: `dashboard/src/routes/_authed/scheduling.sessions.simple.tsx`
- Modify: `dashboard/src/routes/permissions.test.ts`, `dashboard/src/routeTree.gen.ts` (regenerated)

**Interfaces:**
- Consumes: Task 10 (`useSessionPages`, `archives.simple.*`), `schedulingApi.markAttendance`, `JoinLink`, `SessionStatusChip`, `useLocalName`, `todayIn`, `wallTime`, `otherZoneTime`.
- Produces:
  - `attendanceClosed(session: Session): boolean` — `!has_started || status === "cancelled" || compensated || payroll_locked` (the controls' one rule, unchanged).
  - `SimpleSessions()` — a "Day" date input (default: the academy's today), a list (`aria-label` "Sessions") with one item per session: academy time (+ the student's when it differs), status, the student (a link to the session), "teacher · course", the attendance line, Present / Absent buttons (`aria-label` "Mark <name> present|absent", `aria-pressed` on the current value; closed by `attendanceClosed`, `at_disposal` or no `attendance.update`) and the Join link; "More" while another page exists.
  - Route `/_authed/scheduling/sessions/simple` (`permission: "session.view_any"`, `feature: "simplified_sessions"`); `SessionsList` (normal mode) links to it while `simplified_sessions` is on.

- [ ] **Step 1: Write the failing tests**

`SimpleSessions.test.tsx`:

```tsx
import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import { todayIn } from "@/lib/zoned-time";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page, sessionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SimpleSessions } from "./SimpleSessions";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			sessionList: vi.fn(),
			markAttendance: vi.fn(),
		},
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const AISHA = sessionRow({
	id: 42,
	student: { id: 12, full_name: "Aisha", timezone: "UTC" },
	starts_at: "2026-06-01T19:00:00Z",
	has_started: false,
});

describe("SimpleSessions", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(
			page([sessionRow(), AISHA]),
		);
	});

	it("lists the academy's today compactly, one row per session", async () => {
		renderWithRouter(<SimpleSessions />);
		const list = await screen.findByRole("list", { name: "Sessions" });
		const today = todayIn("UTC");
		expect(schedulingApi.sessionList).toHaveBeenCalledWith({
			from: today,
			to: today,
			page: 1,
		});
		expect(screen.getByLabelText("Day")).toHaveValue(today);
		const yusuf = within(list).getAllByRole("listitem")[0];
		expect(within(yusuf).getByText("18:00")).toBeInTheDocument();
		expect(within(yusuf).getByText("Student's time: 21:00")).toBeInTheDocument();
		expect(within(yusuf).getByRole("link", { name: "Yusuf" })).toHaveAttribute(
			"href",
			"/scheduling/sessions/41",
		);
		expect(within(yusuf).getByText("Bilal · Tajweed")).toBeInTheDocument();
		expect(
			within(yusuf).getByRole("link", { name: "Join the session with Yusuf" }),
		).toBeInTheDocument();
	});

	it("loads the next page with More, and asks for the day chosen", async () => {
		vi.mocked(schedulingApi.sessionList)
			.mockResolvedValueOnce({
				count: 2,
				next: "/api/v1/sessions/?page=2",
				previous: null,
				results: [sessionRow()],
			})
			.mockResolvedValueOnce({
				count: 2,
				next: null,
				previous: "/api/v1/sessions/?page=1",
				results: [AISHA],
			});
		const user = userEvent.setup();
		renderWithRouter(<SimpleSessions />);
		await screen.findByRole("link", { name: "Yusuf" });
		await user.click(screen.getByRole("button", { name: "More" }));
		expect(await screen.findByRole("link", { name: "Aisha" })).toBeInTheDocument();
		expect(screen.getByRole("link", { name: "Yusuf" })).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "More" })).toBeNull();
		fireEvent.change(screen.getByLabelText("Day"), {
			target: { value: "2026-06-03" },
		});
		await waitFor(() =>
			expect(schedulingApi.sessionList).toHaveBeenLastCalledWith({
				from: "2026-06-03",
				to: "2026-06-03",
				page: 1,
			}),
		);
	});

	it("marks the student present or absent by the attendance controls' rule", async () => {
		vi.mocked(schedulingApi.markAttendance).mockResolvedValue(
			sessionRow({ status: "completed", student_attendance: "present" }),
		);
		const user = userEvent.setup();
		renderWithRouter(<SimpleSessions />);
		await user.click(
			await screen.findByRole("button", { name: "Mark Yusuf present" }),
		);
		await waitFor(() =>
			expect(schedulingApi.markAttendance).toHaveBeenCalledWith({
				id: 41,
				student_attendance: "present",
			}),
		);
		// Not started yet: closed, as on the session page.
		expect(screen.getByRole("button", { name: "Mark Aisha present" })).toBeDisabled();
		expect(screen.getByRole("button", { name: "Mark Aisha absent" })).toBeDisabled();
	});

	it("keeps the buttons closed for staff without attendance.update", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("session.view_any")}>
				<SimpleSessions />
			</CanProvider>,
		);
		expect(
			await screen.findByRole("button", { name: "Mark Yusuf present" }),
		).toBeDisabled();
	});

	it("says when the day has nothing, and when loading failed", async () => {
		vi.mocked(schedulingApi.sessionList).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<SimpleSessions />);
		expect(await screen.findByText("No sessions on this day.")).toBeInTheDocument();
		unmount();
		vi.mocked(schedulingApi.sessionList).mockRejectedValueOnce(new Error("x"));
		renderWithRouter(<SimpleSessions />);
		expect(
			await screen.findByText("Couldn't load the sessions."),
		).toBeInTheDocument();
	});
});
```

`SessionsList.test.tsx` — append:

```tsx
	it("links to the simplified view while it is on (B2d)", async () => {
		const { unmount } = renderWithRouter(<SessionsList />);
		expect(
			await screen.findByRole("link", { name: "Simplified view" }),
		).toHaveAttribute("href", "/scheduling/sessions/simple");
		unmount();
		renderWithRouter(
			<CanProvider me={adminWith("session_archive")}>
				<SessionsList />
			</CanProvider>,
		);
		await screen.findByRole("table");
		expect(screen.queryByRole("link", { name: "Simplified view" })).toBeNull();
	});
```

`permissions.test.ts`: `FEATURE_SCREENS` gains `"/_authed/scheduling/sessions/simple": "simplified_sessions",`; `FEATURE_WORDS` gains `sessions\/simple` (`…|donations|archive|sessions\/simple|website\/…`).

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/SimpleSessions.test.tsx src/features/scheduling/SessionsList.test.tsx src/features/scheduling/AttendanceControls.test.tsx src/routes/permissions.test.ts`
Expected: FAIL (`Failed to resolve import "./SimpleSessions"`; no "Simplified view" link; the route is missing). Keep the output.

- [ ] **Step 3: `attendanceClosed`** (`AttendanceControls.tsx`)

Above the component:

```tsx
/** The one rule that closes attendance (spec §4.1; Plan 7; B2a A-4): not
 * started, cancelled, frozen by a make-up, or paid by an issued payslip.
 * Slice B2d's simplified view reuses it (plan D11). */
export function attendanceClosed(session: Session): boolean {
	return (
		!session.has_started ||
		session.status === "cancelled" ||
		session.compensated === true ||
		session.payroll_locked === true
	);
}
```

and in the component, `const closed = attendanceClosed(session) || mark.isPending || readOnly;` (`paid` stays for its note).

- [ ] **Step 4: `SimpleSessions.tsx`**

```tsx
import { Link } from "@tanstack/react-router";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { useCan } from "@/features/identity/permissions";
import { errorText } from "@/lib/form-errors";
import { otherZoneTime, todayIn, wallTime } from "@/lib/zoned-time";
import { Alert, AlertDescription, Button, Input, Spinner, toast } from "@/ui";
import { attendanceClosed } from "./AttendanceControls";
import { schedulingApi } from "./api";
import { JoinLink, SessionStatusChip, useLocalName } from "./bits";
import { useSchedulingMutation, useSessionPages } from "./queries";
import type { Session } from "./schemas";

const MARKS = ["present", "absent"] as const;

/** Present / Absent for the student, by the attendance controls' own rule
 * (plan D11): the student's attendance also stays closed at the
 * administration's disposal and without `attendance.update`. */
function QuickMark({ session }: { session: Session }) {
	const { t } = useTranslation();
	const can = useCan();
	const mark = useSchedulingMutation(schedulingApi.markAttendance);
	const closed =
		attendanceClosed(session) ||
		session.status === "at_disposal" ||
		!can("attendance.update") ||
		mark.isPending;
	const name = session.student.full_name;
	return (
		<div className="flex gap-2">
			{MARKS.map((value) => (
				<Button
					key={value}
					size="sm"
					variant={session.student_attendance === value ? "primary" : "outline"}
					aria-pressed={session.student_attendance === value}
					aria-label={t(`archives.simple.${value}For`, { name })}
					disabled={closed}
					onClick={() =>
						mark.mutate(
							{ id: session.id, student_attendance: value },
							{
								onError: (error) =>
									toast({
										description: errorText(error, t),
										variant: "destructive",
									}),
							},
						)
					}
				>
					{t(`archives.simple.${value}`)}
				</Button>
			))}
		</div>
	);
}

/** Spec D-12: the office's compact, phone-first list of one day's sessions
 * — today by default — from the sessions list itself (so it follows the
 * archive's default), "More" loading the next page. */
export function SimpleSessions() {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	const { data: academy } = useAcademySettings();
	const [day, setDay] = useState("");
	const shown = day || (academy ? todayIn(academy.timezone) : "");
	const pages = useSessionPages({ from: shown, to: shown }, shown !== "");
	const rows = pages.data?.pages.flatMap((p) => p.results) ?? [];
	if (!academy) return <Spinner />;

	let body: ReactNode;
	if (pages.isError) {
		body = (
			<Alert variant="destructive">
				<AlertDescription>{t("archives.simple.loadError")}</AlertDescription>
			</Alert>
		);
	} else if (pages.isPending) {
		body = <Spinner />;
	} else if (rows.length === 0) {
		body = (
			<p className="text-sm text-muted-foreground">{t("archives.simple.empty")}</p>
		);
	} else {
		body = (
			<ul
				aria-label={t("archives.simple.list")}
				className="flex flex-col divide-y divide-border rounded-lg border border-border"
			>
				{rows.map((session) => {
					const instant = new Date(session.starts_at);
					const theirs = otherZoneTime(
						instant,
						session.student.timezone,
						academy.timezone,
						i18n.language,
					);
					return (
						<li key={session.id} className="flex flex-col gap-2 p-3">
							<div className="flex flex-wrap items-center justify-between gap-2">
								<span className="flex flex-col">
									<span className="font-medium" dir="ltr">
										{wallTime(instant, academy.timezone, i18n.language)}
									</span>
									{theirs ? (
										<span className="text-xs text-muted-foreground">
											{t("scheduling.slots.studentTime", { time: theirs })}
										</span>
									) : null}
								</span>
								<SessionStatusChip status={session.status} />
							</div>
							<Link
								to="/scheduling/sessions/$sessionId"
								params={{ sessionId: String(session.id) }}
								className="font-medium text-primary-text underline-offset-4 hover:underline"
							>
								{session.student.full_name}
							</Link>
							<p className="text-sm text-muted-foreground">
								{`${session.teacher.full_name} · ${localName(session.course)}`}
							</p>
							<p className="text-xs">
								{t("scheduling.list.attendanceCell", {
									student: t(`scheduling.attendance.${session.student_attendance}`),
									teacher: t(`scheduling.attendance.${session.teacher_attendance}`),
								})}
							</p>
							<div className="flex flex-wrap items-center gap-3">
								<QuickMark session={session} />
								<JoinLink session={session} />
							</div>
						</li>
					);
				})}
			</ul>
		);
	}

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-col gap-1">
				<label htmlFor="simple-day" className="text-xs">
					{t("archives.simple.day")}
				</label>
				<Input
					id="simple-day"
					type="date"
					dir="ltr"
					className="w-auto"
					value={shown}
					onChange={(e) => setDay(e.target.value)}
				/>
			</div>
			{body}
			{pages.hasNextPage ? (
				<Button
					variant="outline"
					disabled={pages.isFetchingNextPage}
					onClick={() => pages.fetchNextPage()}
				>
					{t("archives.simple.more")}
				</Button>
			) : null}
		</div>
	);
}
```

(Add `type ReactNode` to the `react` import: `import { type ReactNode, useState } from "react";`.)

`index.ts`: `export { SimpleSessions } from "./SimpleSessions";`.

`SessionsList.tsx` — in the "More views" nav, after the Archive link branch (normal mode only):

```tsx
				{!archive && hasFeature("simplified_sessions") ? (
					<Link to="/scheduling/sessions/simple" className={LINK}>
						{t("archives.simpleLink")}
					</Link>
				) : null}
```

- [ ] **Step 5: The route** (`src/routes/_authed/scheduling.sessions.simple.tsx`)

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SimpleSessions } from "@/features/scheduling";
import { PageHeader } from "@/ui";

// Slice B2d (D-12): the simplified sessions view, phone-first.
export const Route = createFileRoute("/_authed/scheduling/sessions/simple")({
	staticData: {
		permission: "session.view_any",
		feature: "simplified_sessions",
	},
	component: function SimpleSessionsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("archives.simple.title"));
		return (
			<>
				<PageHeader title={t("archives.simple.title")} />
				<SimpleSessions />
			</>
		);
	},
});
```

Regenerate the route tree: `… exec -T dashboard pnpm exec vite build`.

- [ ] **Step 6: Run, then verify**

Run: the Step 2 command → PASS; then `… pnpm exec vitest run src/features/scheduling src/routes`, `… pnpm exec biome check --write src`, `… pnpm exec tsc --noEmit`, `… pnpm lint`, `… pnpm test:coverage`.

- [ ] **Step 7: Commit**

```bash
git -C dashboard add src/features/scheduling/AttendanceControls.tsx src/features/scheduling/SimpleSessions.tsx src/features/scheduling/SimpleSessions.test.tsx src/features/scheduling/SessionsList.tsx src/features/scheduling/SessionsList.test.tsx src/features/scheduling/index.ts src/routes/_authed/scheduling.sessions.simple.tsx src/routes/permissions.test.ts src/routeTree.gen.ts
git -C dashboard commit -m "feat(scheduling): the simplified sessions view (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 15: End-to-end through Caddy, and the slice gates

**Files:**
- Create: `dashboard/e2e/b2-archive.spec.ts`

- [ ] **Step 1: Write the spec** (it owns its stamped teacher, course, package, student and subscription, as `b2-postpone.spec.ts` does; it fakes no time: the subscription's only slot is three days ahead, so cancelling it removes every session and nothing is due)

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { manage } from "./manage";

const SWITCHES = ["subscription_archive", "session_archive", "simplified_sessions"];

/** The date `days` from now in UTC (demo's academy clock). */
function inDays(days: number): string {
	return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
}

const weekday = (day: string) =>
	new Intl.DateTimeFormat("en", { weekday: "short", timeZone: "UTC" }).format(
		new Date(`${day}T00:00:00Z`),
	);

// Slice B2d spec §9: the admin cancels a subscription, archives it, finds it
// on the archive screen and not on the list, and restores it. Stamped data,
// so a second run on the same database never meets the first run's rows.
test("the admin archives a cancelled subscription and restores it", async ({
	page,
}) => {
	test.setTimeout(120_000);
	const stamp = Date.now();
	const teacher = `E2E Tutor ${stamp}`;
	const student = `E2E Learner ${stamp}`;
	const course = `E2E Recitation ${stamp}`;
	const pkg = `E2E Eight ${stamp}`;
	manage("set_features", "demo", "--on", ...SWITCHES);
	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// Own teacher, course, package and student
	await page.goto(`${DEMO_URL}/app/people/teachers/new`);
	await page.getByLabel(/^full name/i).fill(teacher);
	await page.getByLabel(/^gender/i).selectOption("male");
	await page.getByLabel(/^email/i).fill(`e2e-tutor-${stamp}@e2e.test`);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/teachers\/\d+$/);

	await page.goto(`${DEMO_URL}/app/catalogue/courses/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`تلاوة ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(course);
	await page.getByLabel(teacher, { exact: true }).click();
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/courses$/);

	await page.goto(`${DEMO_URL}/app/catalogue/packages/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`ثمان ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(pkg);
	await page.getByLabel("Sessions per week").fill("2");
	await page.getByLabel("Duration", { exact: true }).fill("1");
	await page.getByLabel("Duration unit").selectOption("month");
	await expect(page.getByText("8 sessions in total")).toBeVisible();
	await page.getByLabel("Price").fill("400");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/packages$/);

	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(student);
	await page.getByLabel(/^email/i).fill(`e2e-learner-${stamp}@e2e.test`);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);

	// A subscription whose one weekly slot is three days ahead
	await page.goto(`${DEMO_URL}/app/scheduling/subscriptions/new`);
	await page.getByLabel("Find a student").fill(student);
	await page.getByLabel(/^Student/).selectOption({ label: student });
	await page.getByLabel(/^Course/).selectOption({ label: course });
	await page.getByLabel(/^Teacher/).selectOption({ label: teacher });
	await page.getByLabel(/^Package/).selectOption({ label: pkg });
	await page.getByLabel(weekday(inDays(3)), { exact: true }).click();
	await page.getByLabel(/^Start time/).fill("10:00");
	await page.getByRole("button", { name: "Create subscription" }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/subscriptions\/\d+$/);

	// Cancel it: its future sessions go, so nothing is still to come
	await page.getByRole("button", { name: "Cancel subscription" }).click();
	await page
		.getByRole("alertdialog")
		.getByRole("button", { name: "Cancel subscription" })
		.click();
	await expect(
		page.getByText("Subscription cancelled.", { exact: true }),
	).toBeVisible();

	// Archive it (delete keeping records): the banner says so
	await page
		.getByRole("button", { name: "Archive (delete keeping records)" })
		.click();
	const confirm = page.getByRole("alertdialog");
	await expect(confirm).toContainText("keeps counting");
	await confirm.getByRole("button", { name: "Archive subscription" }).click();
	await expect(
		page.getByText("Subscription archived.", { exact: true }),
	).toBeVisible();
	await expect(
		page.getByText(/^Archived on .+ by Demo Academy Admin\.$/),
	).toBeVisible();

	// Gone from the list…
	await page.goto(`${DEMO_URL}/app/scheduling/subscriptions`);
	await page.getByRole("searchbox").fill(student);
	await expect(page.getByRole("row", { name: new RegExp(student) })).toHaveCount(0);

	// …and on the archive screen
	await page.getByRole("link", { name: "Archive", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/subscriptions\/archive$/);
	await page.getByRole("searchbox").fill(student);
	const row = page.getByRole("row", { name: new RegExp(student) });
	await expect(row).toBeVisible();
	await expect(row).toContainText("Cancelled");

	// Restore it: it leaves the archive and is back on the list
	await row.getByLabel(`Select ${student}'s subscription`).click();
	await page
		.getByRole("region", { name: "Archive actions" })
		.getByRole("button", { name: "Restore" })
		.click();
	await expect(page.getByText("Restored 1 of 1.", { exact: true })).toBeVisible();
	await expect(page.getByRole("row", { name: new RegExp(student) })).toHaveCount(0);
	await page.getByRole("link", { name: "Back to the list" }).click();
	await page.getByRole("searchbox").fill(student);
	await expect(page.getByRole("row", { name: new RegExp(student) })).toBeVisible();

	// The simplified view at phone width: nothing scrolls sideways
	await page.setViewportSize({ width: 375, height: 800 });
	await page.goto(`${DEMO_URL}/app/scheduling/sessions/simple`);
	await expect(page.getByLabel("Day")).toHaveValue(inDays(0));
	expect(
		await page.evaluate(
			() => document.documentElement.scrollWidth <= window.innerWidth,
		),
	).toBe(true);

	// Arabic: the archive screen reads right to left
	await page.evaluate(() => localStorage.setItem("etqan-locale", "ar"));
	await page.goto(`${DEMO_URL}/app/scheduling/subscriptions/archive`);
	await expect(
		page.getByRole("heading", { name: "أرشيف الاشتراكات" }),
	).toBeVisible();
});
```

(The demo admin is "Demo Academy Admin": `seed_dev.py` creates it as `admin_full_name=f"{name} Admin"` for "Demo Academy".)

- [ ] **Step 2: Run it twice on one database**

Run: `just e2e e2e/b2-archive.spec.ts` and again `just e2e e2e/b2-archive.spec.ts` (no reset between) → PASS both times. Keep the Playwright output for the report.

- [ ] **Step 3: Run the slice gates**

Run, in order: `just test` (backend ≥ 80 %, dashboard lines/statements ≥ 80, branches/functions ≥ 70), `just lint`, `just e2e` (`--workers=1 --retries=1`). Rerun a lone flaky failure by itself before reporting it. Smoke-check the seeded demo once in the browser (`just _stack-manage seed_dev`): the Subscription archive lists Aisha Omar's Tajweed subscription; restoring it leaves its first (cancelled) session on the Session archive; archive it again from its page.

- [ ] **Step 4: Commit**

```bash
git -C dashboard add e2e/b2-archive.spec.ts
git -C dashboard commit -m "test(e2e): the admin archives a cancelled subscription and restores it (B2d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
## Self-review (done while writing)

- **Spec coverage.** §1 goal → Tasks 3–8 (backend) and 11–14 (what the office sees). §2: D-1 one flag → Task 1; D-2 scoped view, other apps never filter (ledger D14) → Tasks 1, 4 (`test_archive_counting.py`), 9 (D9's note); D-3 → Tasks 2 (`ENDED`, `due_sessions`, `archivable`, `_lock_live`), 3; D-4 → Task 3 (cascade marks, restore brings back only those), Task 9 (seeded); D-5 → Task 4; D-6 manual only → no job is added (Tasks 3–4 are the only writers); D-7 → Task 5 (refusals) and Task 4 (`test_an_archived_session_still_takes_attendance_and_stays_archived`: archived sessions still take writes); D-8 → Tasks 6, 7; D-9 → Task 8 (`test_permanent_delete_keeps_plan_4s_rule_from_the_archive`), Task 11 (`DeleteForeverButton`); D-10 → Task 8 (codes, `in_use`); D-11 → Tasks 7 (filters, CSV), 11, 13 ("compensation only" and "completed only" are the list's existing kind tabs and status filter, kept on the archive screen); D-12 → Task 14; D-13 → Tasks 1 (switches), 2/5/6/7 (each refusal and default follows its switch), 10 (`FeatureCode`), 11/13/14 (screens and actions hidden while off); D-14 → Tasks 3 (`archived_at` logged, cascade via `record_many`), 4 (revertible pair). §3 → Task 1. §4.1 → Tasks 3, 5; §4.2 → Tasks 4, 5 (postpone); §4.3 → Tasks 3, 4, 10 (dashboard labels); §4.4 → Tasks 2, 6, 7, 12 (picker). §5 → Tasks 7, 8. §6 → Task 8; §6.1 → Tasks 2, 7. §7 → Tasks 10–14. §8 → Task 9. §9: Subscriptions → Tasks 3, 5, 8; Sessions → Tasks 4, 5; Counting → Task 4; Lists → Tasks 6, 7; B2c → Tasks 3, 4; Access → Task 8; Existing suites → the runs in every backend task's last step and Task 8's full run; Dashboard → Tasks 10–14; e2e → Task 15. §10 known limits and §11 out of scope: nothing to build (no job, no bulk delete on the session archive, no payment-method filter).
- **Spec values this plan reads one way on purpose** (each in the Decisions): non-office `archived=` is 404 although §4.4's aside compares it with the CSV's 403 (D12); `can_archive` added to the payload so the dashboard restates no rule (D2); the slot services take the subscription's lock the spec assumes (D3); the session CSV's two new columns, like every archive field, appear only while the switch is on (D6); the seed acts as the system and narrows four older seed tests to the everyday rows (D9).
- **Placeholders.** None: every code step carries its code; the two list components are given whole, existing JSX included.
- **Type and name consistency.** Backend: `archive_subscription` / `restore_subscription` / `archive_session` / `unarchive_session` / `archive_sessions` / `unarchive_sessions` (all `by=` keyword), `rules.refuse_if_archived`, `rules.refuse_if_session_archived`, `rules.due_sessions`, `rules.archivable` (exported as `services.archivable`), `rules.filter_subscriptions`, `rules.ARCHIVED_MODES`, `rules.ENDED`, `rules.SUBSCRIPTION_ARCHIVE` / `SESSION_ARCHIVE`, `activity.ACTION_FEATURES`, `activity.hidden_actions`, `api.archived.archived_mode`, `views.subscription_filters`; conftest `ARCHIVED_AT`, `stamp_archived`, `archives_on`, `ended`. Payload keys `archived_at`, `can_archive`, `archived_by`, `ends_at` match Task 10's `Subscription`, `SubscriptionDetail` and `Session` fields; the routes match `schedulingApi.archive` / `.restore` / `.archiveSessions` / `.unarchiveSessions`; the 409 codes `scheduling.archived`, `scheduling.not_archived`, `scheduling.has_upcoming_sessions` are Task 10's `errors.json` keys; the four actions and `archived_at` match `ACTIVITY_ACTIONS` / `ACTIVITY_FIELDS` and `sessionActivity.json`. Dashboard names across Tasks 11–14: `ArchivedBadge`, `ArchiveSubscriptionButton`, `DeleteForeverButton`, `RestoreSubscriptionsBar`, `ArchivedSubscriptionBanner`, `ArchivedSessionBanner`, `SessionBulkBar({ marks, shelf })`, `SubscriptionsList({ archive })`, `SessionsList({ archive })`, `attendanceClosed`, `SimpleSessions`, `useSessionPages`.
- **Review Focus.** Five lines, each pinned by a named test in its owning task (Tasks 3, 4, 5, 6, 7).
- **Lessons from Plan 25's build baked in.** `BUILT` in registry order with the two flipped lines placed after `contracts` (Task 1); `ROUTES` / `FEATURES` / `FEATURE_WORDS` and `IN_USE` (Task 8); `OfficeOr404` before `HasCode`, `FeatureOn` last (Task 8); RED evidence in every task (Task 4 says how for its guard test); query-count tests for both archive lists (Task 7); `let body: ReactNode` (Task 14); no `role="group"` (the kind tabs keep their `fieldset`); semantic tokens only; new API calls mocked wherever a touched page renders (InvoiceForm, SubscriptionsList, SessionsList, SessionPage tests); the e2e owns stamped data, runs twice, fakes no time.
