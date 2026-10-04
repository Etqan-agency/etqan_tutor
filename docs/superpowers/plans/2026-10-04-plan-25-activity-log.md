# Plan 25 — Session Activity Log (slice B2c) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B2a, B2b (both B2's own; no other phase's slice).
**Slice:** B2c · **Phase spec:** docs/superpowers/specs/2026-10-03-b2-scheduling-depth-design.md

**Goal:** The office opens a session and sees every change people and the system made to it — who, what, when, each field before and after — and can revert one entry through the same rules that govern the change itself, unless something changed it since; behind a per-academy switch that is off by default.

**Architecture:**
- **Data.** One new table `scheduling.SessionActivity` (session, actor, actor kind, action, `changes` JSON `{field: [before, after]}`, `reverts` → self, `created_at`). One additive migration `0008_session_activity`. No change to existing rows.
- **Writers.** New `services/activity.py`: `track(session, by, action)` — a context manager every single-session service enters right after it locks the row — and `record_many(rows, by, action)` for the three subscription-wide `.update()`s. Both write nothing while `activity_log` is off. `reverting(entry)` sets a contextvar the inverse's own `track` reads to refuse a change made since (`scheduling.changed_since`).
- **Hooks.** `attendance.py` (mark, cancel, restore, disposal, bulk through them), `manual.set_pays_teacher`, `supervision.py` (session PATCH, supervisor's own mark, subscription supervisor), `times.record_times`, `postpone.postpone_session`, `subscriptions.py` (teacher change, renewal move). Additive keywords: `by=None` on `restore_session`, `place_at_disposal`, `set_pays_teacher`, `update_subscription`, `renew_subscription`, `set_subscription_supervisor`; `restore_session(to_disposal=False)`; `cancel_session(disposal_reason=None)`; `postpone_session(starts_at=None)`.
- **Revert.** New `services/revert.py`: `revert_refusal(entry, by)` (§4.2 step 1) and `revert_activity(entry, *, by)`, which runs the inverse service as `by` inside `reverting(entry)` and takes no lock of its own.
- **Read.** New `services/activity_feed.py`: `session_activity(session, viewer)` — the newest 200 visible entries, names resolved with one query per related model, `can_revert` per entry.
- **API.** `GET sessions/<id>/activity/`, `POST sessions/<id>/activity/<entry_id>/revert/` (`activity_log`), office only (404 for everyone else, before the code check).
- **Dashboard.** An Activity section on the session page with a field / before / after table, badges, and a Revert confirm dialog; strings in a new area file `sessionActivity.json`.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18 (JSONField `has_any_keys`); React 19 + TanStack Router/Query + Vite (base `/app/`), i18next, Radix UI; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-03-b2c-activity-log-design.md` (slice B2c of the phase spec). It builds on B2a (`…/2026-10-03-b2a-session-classes-design.md`, Plan 17: disposal, `pays_teacher`, make-ups, lock order), B2b (`…/2026-10-03-b2b-times-postponement-design.md`, Plan 21: `record_times`, `postpone_session`, teacher change and renewal moves, ruling P4b `scheduling.session_moved`, ruling P15), Plan 5 (attendance, cancel, restore, bulk), Plan 7 (payroll lock), Plan 12a/b (codes, supervision), Plan 13 (switches, FT-4). Where this plan fills a gap in the spec, the Decisions below say so.

## Global Constraints

**Repos and branches**
- Meta worktree: `/home/abdulkhalek/Projects/etqan_tutor-wt/b2` (`$W`). Meta, `backend/` and `dashboard/` are on `feat/b2c-activity-log`, created by the controller off `origin/master` (meta) and `origin/main` (submodules) after B2b merged. `marketing/` is untouched.
- Commit in the submodule that owns the file (`git -C $W/backend …`, `git -C $W/dashboard …`). Never run `git submodule update` (or any writing `git submodule` subcommand) in this worktree.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` (this overrides any attribution line a harness suggests).
- Never edit `STATE.md`, CI workflows, Caddyfiles, or meta's submodule pointers.

**Commands (the slot-1 stack must be up: `just dev-backend`)**
- From `$W`, load the stream's environment first: `cd /home/abdulkhalek/Projects/etqan_tutor-wt/b2; set -a; . ./.env.stream; set +a`. Then run docker compose **directly** (a `$DC` variable does not word-split in zsh):
  - Backend tests: `docker compose -f docker-compose.local.yml exec -T django pytest -q <paths>` (add `--create-db` once after a migration).
  - Backend format: `docker compose -f docker-compose.local.yml exec -T django ruff check --fix .` then `… exec -T django ruff format .`
  - Backend verify: `… exec -T django ruff check .`, `… exec -T django ruff format --check .`, `… exec -T django lint-imports`, `… exec -T django pytest -q --cov=etqan`
  - Migration: `… exec -T django python manage.py makemigrations scheduling --name session_activity` (Task 1). Trunk's scheduling leaf after B2b is `0007_times_postponement`, so this is `0008_session_activity`.
  - Dashboard tests: `… exec -T dashboard pnpm exec vitest run <paths>`; verify: `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`, `… exec -T dashboard pnpm test:coverage`.
  - Seeding this stream: `just _stack-manage migrate_schemas`, `just _stack-manage seed_dev`. E2E only through `just e2e …`.
  - Slice gates: `just test` (its backend recipe blanks `DJANGO_EMAIL_SUBJECT_PREFIX`), `just lint`, `just e2e`.
- There is no host `.venv` or `node_modules`; never run `manage.py`, `migrate` or pytest against any other database.
- Ruff selects `PL`, `FBT`, `DTZ`, `BLE`, `ERA`, `SLF`, `C901` (10), `E501` (88). Long keyword-only signatures carry `# noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)`. Imports are one per line (`from x import a` / `from x import b`), as every trunk file does.
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`: semantic colour tokens only. Biome rejects `role="group"` on a div: use `<fieldset>` + `<legend>`.

**TDD and reports (lessons from Plan 21's build)**
- Every task runs its new tests before the implementation and keeps the failing output (RED) for the report, then the passing output (GREEN). A report without RED evidence is sent back.
- Trunk helper names (Plan 21 ruling P13): `identity_services.link_guardian(parent, student)` (positional Users), the root `staff_for(*codes)` fixture (an `APIClient`; the user is `client.user`), `api_for("admin")`, `set_features(**switches)`, scheduling's `make_admin`, `make_teacher`, `make_student`, `hand_session`, `two_slots`, `build_world`, `subscription_for`, `until_pk_exceeds`, `clock`. `rules.acts_as_office(by)` already exists (Plan 21 ruling P2): never re-define it.
- `platform/tests/test_features.py`'s `BUILT` dict lists every built switch in registry order: a new switch goes there in the same commit (Plan 21 ruling P1).
- A list or read that renders rows carries a query-count test (same count for 1 and 5 rows).
- Scheduling tests may not import `etqan.identity.models` (import-linter); go through `identity_services`.

**Coverage and dev data**
- Gates: backend ≥ 80 %; dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`; `demo` admin `admin@demo.test`.

**Orchestration rules**
- Shared lists: lines only under `── phase B2 ──` (feature registry, `test_features.BUILT`, `seed_dev`'s B2 block calls `etqan/tenants/seeds/b2.py`). The access `RESOURCES` line for `session` already carries `view` and `update`: no new resource or verb.
- No unowned app is touched (no ledger claim needed): everything is in `etqan.scheduling`, `etqan.tenants.seeds`/`seed_dev`'s B2 block, `etqan.platform.features` (B2 marker) and `etqan.access/tests/test_routes.py` (B2 lines).
- New translation area: `dashboard/src/locales/{en,ar}/sessionActivity.json`, holding its keys directly (the catalogue globs the folder and wraps the file under `sessionActivity`). The `errors.scheduling` codes are B2's and edited in place.
- New e2e spec: `dashboard/e2e/b2-activity.spec.ts`, owning its data (as `b2-session-classes.spec.ts`).
- Migrations are additive (phase B2-16). Never `makemigrations --merge`; on a clash after a rebase, delete this plan's migration and regenerate it.
- Service signature changes are additive only (keyword arguments with defaults that keep today's behaviour).

**Lock order (binding, from B2a / Plan 4)**
- Subscriptions before sessions; sessions in pk order. `track` takes no lock; `revert_activity` takes no lock of its own, so a revert locks exactly as the inverse service does. B2b ruling P4b stays: `postpone_session` refuses a session whose subscription changed between its unlocked read and its lock with 409 `scheduling.session_moved` (no retry); a revert of a postponement inherits that refusal unchanged.

**API and data rules (spec values verbatim)**
- 409 bodies `{detail, code}`. New codes: `scheduling.changed_since`, `scheduling.not_revertible`. Propagated unchanged from the inverses: `payroll.payslip_issued`, `scheduling.has_compensation`, `scheduling.not_allowed_in_status`, `scheduling.session_cancelled`, `scheduling.not_started`, `scheduling.session_moved`, `scheduling.already_compensated`, `scheduling.not_compensable`; B2b's postponement 400s; a 400 on `supervisor_id` for a former supervisor.
- A switched-off feature's routes answer `404 {"detail": "This feature is not enabled for this academy."}` after the permission check.
- Routes: `GET sessions/<id>/activity/` (code `session.view`; feature `activity_log`; `{results, truncated, created: {at, by, kind, generated}}`); `POST sessions/<id>/activity/<entry_id>/revert/` (code `session.update` plus the inverse's codes; feature `activity_log`; `200 {session, entry}`). Teachers, students and parents: 404 on both, before the code check.
- `action` max 24 characters; the read returns the newest 200.

### Decisions this plan makes where the spec is silent or leaves a choice

- **D1 — Three modules, so nothing imports in a circle.** `services/activity.py` holds the writers and imports only models and the platform; every hooked service imports it. `services/revert.py` imports the hooked services (the inverses). `services/activity_feed.py` reads and imports `revert` for `revert_refusal`.
- **D2 — `track` diffs the locked row in memory.** Every hooked service mutates and saves the very object it locked, so `track` snapshots `LOGGED_FIELDS` from that object before and after (no extra query). Values are compared and stored in their JSON form: instants as ISO UTC with a `Z` (`2026-06-01T18:00:00Z`), dates as ISO dates, ids as ints, strings and bools as themselves. `changed_since` compares the same JSON forms.
- **D3 — The revert contextvar is claimed once.** `reverting(entry)` sets a state object; the first `track` entered on the entry's session claims it, runs the `changed_since` check, and records its own new entry on it (`reverts = entry`). Any later `track` in the same revert is an ordinary entry. `revert_activity` answers with the claimed entry.
- **D4 — `revert_activity(entry, *, by)` also refuses while `activity_log` is off** (409 `scheduling.not_revertible`; the route already 404s first) so the inverse always writes its entry, and refuses a non-office `by` with 403 like a missing code.
- **D5 — `set_subscription_supervisor` gains `by=None` too.** The spec's additive list names five services; this sixth `record_many` writer needs an actor, and the subscription PATCH passes `request.user`. Seeds pass nothing (system).
- **D6 — `postpone_session(occurs_on=None, start_time=None, starts_at=None)`.** Callers pass either the day and wall-clock time (as today) or `starts_at`, an exact UTC instant from which `occurs_on` and `start_time` are derived on the academy's clock (no local round trip, so an ambiguous DST hour is kept). Neither → 400 on `occurs_on`. B2b's re-attach rule, P4b and P15 apply unchanged.
- **D7 — `restore_session(to_disposal=True)` only from `cancelled`;** from any other status it is 409 `scheduling.not_allowed_in_status`. It keeps `disposal_reason`. `cancel_session(disposal_reason=…)` writes the value verbatim (it was stored stripped).
- **D8 — Activity references are `{id, name}` throughout** (spec §4.3): the actor, the creation line's `by`, and resolved ids in `changes`. Subscriptions have no code column, so a `subscription_id` value is `{id, name: null}` and the dashboard shows `#<id>`; a teacher or supervisor that no longer exists is `{id, name: null}` too.
- **D9 — The visibility filter runs in SQL** (`changes__has_any_keys` = the fields whose switch is on), so the 200 cap counts visible entries only; `truncated` is the presence of a 201st row.
- **D10 — "Two concurrent reverts" is pinned without threads.** The codebase has no transactional (threaded) tests. The rule rests on three facts: `track` receives the very object the inverse just read `FOR UPDATE` (by construction, Tasks 3–4), a revert takes exactly the inverse's locks and none of its own (SQL capture, Task 6), and a second revert of the same entry is 409 `changed_since` and writes nothing (Task 6).
- **D11 — `mark_supervisor_attendance` enters `track` after `_own`.** Its refusals live inside its lock helper; it is never an inverse, so the "check before the inverse's refusals" order does not apply to it.
- **D12 — Seeds mark themselves by author.** Demo's `features.BUILT` turns `activity_log` on before `seed_attendance` runs, so its teacher marks already log an entry on every past session: "skipped when the session already has entries" cannot be the marker. `seed_activity` is skipped when the demo admin has any entry; it works on the latest unpaid, uncompensated completed session (flip the student's attendance, cancel, revert the cancel) inside one transaction, so a refused step leaves nothing and is retried on the next run.
- **D13 — `OfficeOr404` lives in `scheduling/api/activity_views.py`.** It raises 404 for a signed-in non-office user and lets an anonymous caller fall through to the usual refusal; `HasCode` and `FeatureOn` follow it.
- **D14 — Dashboard gates.** The Activity section shows when `hasFeature("activity_log") && can("session.view")`; Revert shows only on `can_revert` (the server already weighed codes and switches). The activity query lives under `schedulingKey`, so every scheduling write — a revert included — reloads it. Action labels are sentences ("Session cancelled") distinct from value labels ("Cancelled"). An entry with `actor_kind: "user"` and no actor reads "A removed account".
- **D15 — `created_at` is `auto_now_add`** (the real clock, as every other table); entries order by `-created_at, -id`.

## Review Focus

- **A cancel of a session at the administration's disposal, reverted.** Expected: back to `at_disposal` with its disposal reason, not to `scheduled`. Test: Task 6 `test_a_cancel_from_disposal_reverts_to_disposal_keeping_its_reason`.
- **A staff member who may update sessions but not attendance, on an attendance entry.** Expected: no Revert in the read and 403 if they send it anyway; with `attendance.update` it works. Tests: Task 6 `test_the_inverses_codes_are_needed`, Task 7 `test_can_revert_follows_the_rules`.
- **A field whose own switch is off.** Expected: hidden from the read, its entry not revertible, both back when the switch is on again. Test: Task 7 `test_hidden_fields_are_left_out_and_block_the_revert`.
- **Bulk with a skipped session.** Expected: one entry per done session, none for the skipped one, the skipped one's earlier entries untouched. Test: Task 3 `test_bulk_logs_one_entry_per_done_session_and_none_for_skipped`.
- **Revert pressed twice (two tabs, a double click).** Expected: the second answer is 409 `scheduling.changed_since` and writes nothing. Test: Task 6 `test_reverting_twice_is_a_conflict_the_second_time`.

---

## File Structure

```
backend/
  etqan/platform/features.py                       activity_log under ── phase B2 ── (Task 1)
  etqan/platform/tests/test_features.py            BUILT + activity_log (Task 1)
  etqan/scheduling/
    models.py                                       SessionActivity (Task 1)
    migrations/0008_session_activity.py             generated (Task 1)
    services/activity.py                            NEW: LOGGED_FIELDS, FIELD_FEATURES, track,
                                                    record_many, reverting, snapshot (Task 2)
    services/attendance.py                          track in mark/cancel/restore/disposal;
                                                    restore(by, to_disposal), cancel(disposal_reason),
                                                    place_at_disposal(by) (Task 3)
    services/manual.py                              set_pays_teacher(by) + track (Task 3)
    services/supervision.py                         track in the PATCH and the supervisor's mark (Task 4);
                                                    set_subscription_supervisor(by) + record_many (Task 5)
    services/times.py                               track (Task 4)
    services/postpone.py                            track, starts_at= (Task 4)
    services/subscriptions.py                       update_subscription(by), renew_subscription(by),
                                                    record_many (Task 5)
    services/revert.py                              NEW: INVERSES, revert_refusal, revert_activity (Task 6)
    services/activity_feed.py                       NEW: session_activity, describe_activity,
                                                    activity_of, activity_by, get_activity_entry (Task 7)
    services/__init__.py                            exports (Tasks 2, 6, 7)
    api/session_views.py views.py                   pass request.user (Tasks 3, 5)
    api/activity_views.py                           NEW: OfficeOr404, the two views (Task 8)
    api/payloads.py urls.py                         activity_feed, activity_entry, routes (Task 8)
    tests/test_activity_*.py test_api_activity.py   NEW (Tasks 1–8)
  etqan/access/tests/test_routes.py                 ROUTES, FEATURES, FEATURE_WORDS (Task 8)
  etqan/tenants/seeds/b2.py tests/test_seed_b2.py   seed_activity (Task 9)
  etqan/tenants/management/commands/seed_dev.py     one call in the B2 block (Task 9)
dashboard/
  src/features/identity/schemas.ts                  FeatureCode + "activity_log" (Task 10)
  src/features/scheduling/
    schemas.ts api.ts queries.ts                    activity types, API, query (Task 10)
    activityFormat.ts (+test)                       NEW: value, actor, action and creation-line text (Task 10)
    SessionActivity.tsx (+test)                     NEW: the section (Task 11)
    SessionPage.tsx (+test)                         the section, gated (Task 11)
    RevertDialog.tsx (+test)                        NEW (Task 12); SessionActivity renders it
    SessionPage.test.tsx SupervisorFields.test.tsx  mock the activity read (Task 11)
  src/test/scheduling-fixtures.ts                   activityEntry, activityLog (Task 10)
  src/locales/{en,ar}/sessionActivity.json          NEW (Task 10)
  src/locales/{en,ar}/errors.json                   changed_since, not_revertible (Task 10)
  e2e/b2-activity.spec.ts                           NEW (Task 13)
```

---

### Task 1: The switch, the `SessionActivity` table and the migration

**Files:**
- Modify: `backend/etqan/platform/features.py` (under `# ── phase B2 ──`, after B2b's `postponement`)
- Modify: `backend/etqan/platform/tests/test_features.py` (`BUILT`, after `"postponement": False`)
- Modify: `backend/etqan/scheduling/models.py` (append `SessionActivity` after `SessionReport`)
- Create: `backend/etqan/scheduling/migrations/0008_session_activity.py` (generated)
- Test: `backend/etqan/scheduling/tests/test_activity_model.py`

**Interfaces:**
- Produces: feature code `activity_log` (built, default off, group `teaching`). Model `SessionActivity` with `session` (→ Session, CASCADE, `related_name="activity"`), `actor` (→ User, nullable, SET_NULL), `actor_kind` (`SessionActivity.ActorKind.USER | SYSTEM`), `action` (`SessionActivity.Action`, max 24), `changes` (JSON), `reverts` (→ self, nullable, SET_NULL, `related_name="reverted_by"`), `created_at`; default ordering `-created_at, -id`; index `(session, created_at)`.

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2c §3.1: the switch and the SessionActivity table."""

from datetime import date

import pytest

from etqan.platform import features
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
CANCEL = {"status": ["scheduled", "cancelled"]}


def test_activity_log_is_a_built_switch_off_by_default():
    feature = features.get("activity_log")
    assert (feature.built, feature.default, feature.group) == (True, False, "teaching")
    assert features.is_on("activity_log", {}) is False


def test_it_follows_b2bs_switches():
    codes = [feature.code for feature in features.REGISTRY]
    assert codes.index("postponement") + 1 == codes.index("activity_log")


def entry(session, **fields):
    return SessionActivity.objects.create(
        session=session, actor_kind="system", action="cancel", changes=CANCEL, **fields
    )


def first_session(subscribe):
    sub = subscribe(slots=two_slots())
    return sub, Session.objects.filter(subscription=sub).first()


def test_entries_read_newest_first(subscribe):
    _sub, session = first_session(subscribe)
    older = entry(session)
    newer = entry(session)
    assert list(SessionActivity.objects.filter(session=session)) == [newer, older]
    assert list(session.activity.all()) == [newer, older]


def test_an_entry_keeps_its_json_and_kind(subscribe):
    _sub, session = first_session(subscribe)
    stored = SessionActivity.objects.get(pk=entry(session).pk)
    assert (stored.actor_id, stored.actor_kind, stored.changes) == (None, "system", CANCEL)


def test_deleting_the_session_deletes_its_entries(subscribe):
    sub, _session = first_session(subscribe)
    hand = hand_session(sub, occurs_on=date(2026, 6, 5))
    entry(hand)
    hand.delete()
    assert not SessionActivity.objects.exists()


def test_deleting_a_reverted_entry_leaves_its_revert(subscribe):
    _sub, session = first_session(subscribe)
    reverted = entry(session)
    revert = entry(session, reverts=reverted)
    assert list(reverted.reverted_by.all()) == [revert]
    reverted.delete()
    revert.refresh_from_db()
    assert revert.reverts_id is None
```

- [ ] **Step 2: Run them to see them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest -q etqan/scheduling/tests/test_activity_model.py`
Expected: FAIL (`ImportError: cannot import name 'SessionActivity'`). Keep the output for the report.

- [ ] **Step 3: Register the switch**

In `backend/etqan/platform/features.py`, right after B2b's `postponement` entry and before `# ── phase B3 ──`:

```python
    # Slice B2c (Plan 25): the session activity log with revert, off by default.
    Feature(
        "activity_log",
        "Session activity log",
        "سجل نشاط الحصص",
        "teaching",
        built=True,
    ),
```

In `backend/etqan/platform/tests/test_features.py`, in `BUILT`, after `"postponement": False,`:

```python
    "activity_log": False,
```

- [ ] **Step 4: Add the model**

Append to `backend/etqan/scheduling/models.py`:

```python
class SessionActivity(models.Model):
    """Slice B2c §3.1: one change a scheduling service made to a session —
    who (null: the system, or a deleted account), what, when, and each changed
    field's value before and after. Written only by `services.activity`, inside
    the service's own transaction, never by model signals (C-4)."""

    class ActorKind(models.TextChoices):
        USER = "user", "User"
        SYSTEM = "system", "System"

    class Action(models.TextChoices):
        """§4.1's actions, one per writing service."""

        ATTENDANCE = "attendance", "Attendance"
        CANCEL = "cancel", "Cancel"
        RESTORE = "restore", "Restore"
        DISPOSAL = "disposal", "At the administration's disposal"
        PAYS_TEACHER = "pays_teacher", "Pays the teacher"
        SUPERVISION = "supervision", "Supervision"
        SUPERVISOR_ATTENDANCE = "supervisor_attendance", "Supervisor attendance"
        TIMES = "times", "Times"
        POSTPONE = "postpone", "Postpone"
        TEACHER_MOVED = "teacher_moved", "Teacher changed"
        RENEWAL_MOVED = "renewal_moved", "Moved to the renewal"
        SUBSCRIPTION_SUPERVISOR = "subscription_supervisor", "Subscription supervisor"

    session = models.ForeignKey(
        Session, on_delete=models.CASCADE, related_name="activity"
    )
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    actor_kind = models.CharField(max_length=6, choices=ActorKind.choices)
    action = models.CharField(max_length=24, choices=Action.choices)
    # {field: [before, after]}, only fields whose value changed (C-2).
    changes = models.JSONField(default=dict)
    reverts = models.ForeignKey(
        "self",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="reverted_by",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        indexes = [models.Index(fields=["session", "created_at"])]

    def __str__(self):
        return f"SessionActivity<{self.session_id} {self.action}>"
```

- [ ] **Step 5: Generate the migration**

Run: `docker compose -f docker-compose.local.yml exec -T django python manage.py makemigrations scheduling --name session_activity`
Expected: `0008_session_activity.py` depending on `0007_times_postponement`, with one `CreateModel` (the index in its options or one `AddIndex`), no `RunPython`, no change to existing tables.

- [ ] **Step 6: Run the tests**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest -q --create-db etqan/scheduling/tests/test_activity_model.py etqan/platform/tests/test_features.py etqan/academy/tests/test_features_api.py`
Expected: PASS.

- [ ] **Step 7: Lint and commit**

Run: `… exec -T django ruff check . && … exec -T django ruff format --check .`

```bash
git -C backend add etqan/platform/features.py etqan/platform/tests/test_features.py etqan/scheduling/models.py etqan/scheduling/migrations/0008_session_activity.py etqan/scheduling/tests/test_activity_model.py
git -C backend commit -m "feat(scheduling): the session activity table behind the activity_log switch (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The writers (`services/activity.py`)

**Files:**
- Create: `backend/etqan/scheduling/services/activity.py`
- Test: `backend/etqan/scheduling/tests/test_activity_writers.py`

**Interfaces:**
- Consumes: Task 1's `SessionActivity`.
- Produces (module `etqan.scheduling.services.activity`, imported by the hooked services as `from etqan.scheduling.services import activity`):
  - `FEATURE = "activity_log"`; `Action = SessionActivity.Action`; `CHANGED_SINCE` (message).
  - `LOGGED_FIELDS: tuple[str, ...]` (§3.2, display order); `FIELD_FEATURES: dict[str, str]` (field → switch, §3.1); `INSTANTS: frozenset[str]`.
  - `to_json(value) -> str | int | bool | None`; `from_json(field: str, value) -> object` (ISO strings back to `datetime` / `date`).
  - `snapshot(session: Session) -> dict[str, object]` (JSON forms of `LOGGED_FIELDS`); `diff(before: dict, after: dict) -> dict[str, list]`.
  - `visible_fields() -> frozenset[str]` (fields whose switch is on; no query).
  - `track(session: Session, by, action: str)` — context manager.
  - `record_many(rows: Iterable[tuple[int, dict[str, tuple]]], by, action: str) -> None` — each row is `(session_id, {field: (before, after)})` in Python values.
  - `Reverting` (dataclass: `entry`, `claimed: bool`, `written: SessionActivity | None`); `reverting(entry: SessionActivity)` — context manager yielding the `Reverting`; `refuse_if_changed(entry, session) -> None` (409 `scheduling.changed_since`).

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2c §4.1, §4.2 step 2: the log's writers — `track`, `record_many`
and the revert's `changed_since` check."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import transaction

from etqan.platform.exceptions import ConflictError
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.services import activity
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db


@pytest.fixture
def on(set_features):
    set_features(activity_log=True)


@pytest.fixture
def session(subscribe, on):
    """Monday 1 June 2026, 18:00 UTC."""
    sub = subscribe(slots=two_slots())
    return Session.objects.filter(subscription=sub).order_by("starts_at").first()


def entries(session):
    return list(SessionActivity.objects.filter(session=session).order_by("id"))


def cancel_in(session, by, reason="Eid"):
    with activity.track(session, by, activity.Action.CANCEL):
        session.status = Session.Status.CANCELLED
        session.cancel_reason = reason
        session.save()


def restore_in(session, by=None):
    with activity.track(session, by, activity.Action.RESTORE):
        session.status = Session.Status.SCHEDULED
        session.cancel_reason = ""
        session.save()


def refused_cancel(session):
    with activity.track(session, None, activity.Action.CANCEL):
        session.status = Session.Status.CANCELLED
        session.save()
        raise ConflictError("Refused.", code="scheduling.not_allowed_in_status")


def test_track_writes_one_entry_with_only_the_changed_fields(session):
    admin = make_admin()
    cancel_in(session, admin)
    (entry,) = entries(session)
    assert (entry.action, entry.actor_id, entry.actor_kind) == ("cancel", admin.pk, "user")
    assert entry.changes == {
        "status": ["scheduled", "cancelled"],
        "cancel_reason": ["", "Eid"],
    }
    assert entry.reverts_id is None


def test_a_call_that_changes_nothing_writes_nothing(session):
    with activity.track(session, make_admin(), activity.Action.CANCEL):
        session.save()
    assert entries(session) == []


def test_by_none_is_the_system(session):
    cancel_in(session, None)
    (entry,) = entries(session)
    assert (entry.actor_id, entry.actor_kind) == (None, "system")


def test_nothing_is_written_while_the_switch_is_off(session, set_features):
    set_features(activity_log=False)
    cancel_in(session, make_admin())
    assert entries(session) == []


def test_an_exception_writes_nothing(session):
    with pytest.raises(ConflictError), transaction.atomic():
        refused_cancel(session)
    assert entries(session) == []


def test_values_are_stored_in_their_json_form(session):
    moved = datetime(2026, 6, 4, 20, 0, tzinfo=UTC)
    with activity.track(session, None, activity.Action.POSTPONE):
        session.occurs_on = date(2026, 6, 4)
        session.starts_at = moved
        session.save()
    (entry,) = entries(session)
    assert entry.changes == {
        "occurs_on": ["2026-06-01", "2026-06-04"],
        "starts_at": ["2026-06-01T18:00:00Z", "2026-06-04T20:00:00Z"],
    }
    assert activity.from_json("starts_at", "2026-06-04T20:00:00Z") == moved
    assert activity.from_json("occurs_on", "2026-06-04") == date(2026, 6, 4)
    assert activity.from_json("actual_minutes", None) is None
    assert activity.from_json("status", "cancelled") == "cancelled"


def test_visible_fields_follow_their_switches(session, set_features):
    set_features(supervision=False, session_times=True)
    shown = activity.visible_fields()
    assert "status" in shown
    assert "teacher_in_at" in shown
    assert "supervisor_id" not in shown


def test_record_many_writes_one_entry_per_changed_session(session):
    other = Session.objects.exclude(pk=session.pk).first()
    activity.record_many(
        [
            (session.pk, {"teacher_id": (1, 2)}),
            (other.pk, {"teacher_id": (3, 3)}),
        ],
        None,
        activity.Action.TEACHER_MOVED,
    )
    (entry,) = SessionActivity.objects.all()
    assert (entry.session_id, entry.action, entry.actor_kind) == (
        session.pk,
        "teacher_moved",
        "system",
    )
    assert entry.changes == {"teacher_id": [1, 2]}


def test_record_many_writes_nothing_while_off(session, set_features):
    set_features(activity_log=False)
    activity.record_many(
        [(session.pk, {"teacher_id": (1, 2)})], None, activity.Action.TEACHER_MOVED
    )
    assert not SessionActivity.objects.exists()


def test_a_revert_refuses_a_field_that_moved_on(session):
    cancel_in(session, None)
    (entry,) = entries(session)
    session.cancel_reason = "Rain"
    session.save()
    with pytest.raises(ConflictError) as err, activity.reverting(entry):
        restore_in(session)
    assert err.value.code == "scheduling.changed_since"


def test_the_inverse_entry_points_at_the_reverted_one_once(session):
    cancel_in(session, None)
    (entry,) = entries(session)
    with activity.reverting(entry) as state:
        restore_in(session)
        cancel_in(session, None, reason="Again")
    _first, second, third = entries(session)
    assert second.reverts_id == entry.pk
    assert state.written == second
    assert third.reverts_id is None
```

- [ ] **Step 2: Run them to see them fail**

Run: `… pytest -q etqan/scheduling/tests/test_activity_writers.py`
Expected: FAIL (`ImportError: cannot import name 'activity'`). Keep the output.

- [ ] **Step 3: Implement `services/activity.py`**

```python
"""The session activity log's writers (slice B2c §4.1).

A scheduling service that changes one session enters `track` right after it
locks the row; one that changes many rows with `.update()` hands what it read
under its own lock to `record_many`. Both write nothing while the
`activity_log` switch is off, and `by=None` is the system (C-2, C-11). Entries
are never written by model signals, so a change made outside the services is
not logged (C-4). A revert runs inside `reverting(entry)`: the inverse's own
`track` then refuses, right after the inverse's lock, a field that moved on
since the entry (§4.2 step 2)."""

from collections.abc import Iterable
from collections.abc import Iterator
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass
from datetime import UTC
from datetime import date
from datetime import datetime

from etqan.platform import features
from etqan.platform.exceptions import ConflictError
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity

FEATURE = "activity_log"
Action = SessionActivity.Action
CHANGED_SINCE = "This changed after that entry. Reload to see what it is now."
# §3.2: the fields the log follows, in the order the log shows them. A field
# no service changes is not here.
LOGGED_FIELDS = (
    "status",
    "student_attendance",
    "teacher_attendance",
    "supervisor_attendance",
    "cancel_reason",
    "disposal_reason",
    "pays_teacher",
    "supervisor_id",
    "teacher_id",
    "subscription_id",
    "occurs_on",
    "starts_at",
    "teacher_in_at",
    "teacher_out_at",
    "student_in_at",
    "student_out_at",
    "actual_minutes",
)
# §3.1, C-10: a field shows, and an entry holding it reverts, only while its
# own switch is on. A field not listed always shows.
FIELD_FEATURES = {
    "supervisor_id": "supervision",
    "supervisor_attendance": "supervision",
    "teacher_in_at": "session_times",
    "teacher_out_at": "session_times",
    "student_in_at": "session_times",
    "student_out_at": "session_times",
    "actual_minutes": "session_times",
    "occurs_on": "postponement",
    "starts_at": "postponement",
    "pays_teacher": "extra_sessions",
}
INSTANTS = frozenset(
    {
        "starts_at",
        "teacher_in_at",
        "teacher_out_at",
        "student_in_at",
        "student_out_at",
    }
)


def to_json(value):
    """§3.2 (plan D2): instants as ISO UTC with a Z, dates as ISO dates;
    strings, bools, ints and None as they are."""
    if isinstance(value, datetime):
        return value.astimezone(UTC).isoformat().replace("+00:00", "Z")
    if isinstance(value, date):
        return value.isoformat()
    return value


def from_json(field: str, value):
    """A stored value back in the type the services take (§4.2)."""
    if value is None:
        return None
    if field in INSTANTS:
        return datetime.fromisoformat(value)
    if field == "occurs_on":
        return date.fromisoformat(value)
    return value


def snapshot(session: Session) -> dict:
    return {field: to_json(getattr(session, field)) for field in LOGGED_FIELDS}


def diff(before: dict, after: dict) -> dict:
    return {
        field: [before[field], after[field]]
        for field in LOGGED_FIELDS
        if before[field] != after[field]
    }


def visible_fields() -> frozenset[str]:
    """The logged fields whose own switch is on (C-10). No query."""
    return frozenset(
        field
        for field in LOGGED_FIELDS
        if field not in FIELD_FEATURES or features.enabled(FIELD_FEATURES[field])
    )


def _kind(by) -> str:
    kinds = SessionActivity.ActorKind
    return kinds.SYSTEM if by is None else kinds.USER


@dataclass
class Reverting:
    """Plan D3: the entry being reverted, whether a `track` has claimed it,
    and the entry that `track` wrote."""

    entry: SessionActivity
    claimed: bool = False
    written: SessionActivity | None = None


_REVERTING: ContextVar[Reverting | None] = ContextVar(
    "scheduling_reverting", default=None
)


@contextmanager
def reverting(entry: SessionActivity) -> Iterator[Reverting]:
    state = Reverting(entry)
    token = _REVERTING.set(state)
    try:
        yield state
    finally:
        _REVERTING.reset(token)


def _claim(session: Session) -> Reverting | None:
    state = _REVERTING.get()
    if state is None or state.claimed or state.entry.session_id != session.pk:
        return None
    state.claimed = True
    return state


def refuse_if_changed(entry: SessionActivity, session: Session) -> None:
    """C-6: every field the entry changed must still hold its after-value."""
    now = snapshot(session)
    if any(now[field] != after for field, (_before, after) in entry.changes.items()):
        raise ConflictError(CHANGED_SINCE, code="scheduling.changed_since")


@contextmanager
def track(session: Session, by, action: str) -> Iterator[None]:
    """Enter right after locking ``session`` (before the service's refusals)
    and save inside. On a clean exit, one entry holds the fields that differ;
    none differ, or the switch is off, or the body raises: no entry."""
    revert = _claim(session)
    if revert is not None:
        refuse_if_changed(revert.entry, session)
    if not features.enabled(FEATURE):
        yield
        return
    before = snapshot(session)
    yield
    changes = diff(before, snapshot(session))
    if not changes:
        return
    entry = SessionActivity.objects.create(
        session_id=session.pk,
        actor=by,
        actor_kind=_kind(by),
        action=action,
        changes=changes,
        reverts=revert.entry if revert is not None else None,
    )
    if revert is not None:
        revert.written = entry


def record_many(rows: Iterable[tuple[int, dict]], by, action: str) -> None:
    """One `bulk_create` for a service that changed many rows with
    `.update()`. Each row is ``(session_id, {field: (before, after)})`` in
    Python values, read under the service's own lock; unchanged pairs and
    rows are dropped."""
    if not features.enabled(FEATURE):
        return
    entries = []
    for session_id, pairs in rows:
        changes = {
            field: [to_json(before), to_json(after)]
            for field, (before, after) in pairs.items()
            if to_json(before) != to_json(after)
        }
        if changes:
            entries.append(
                SessionActivity(
                    session_id=session_id,
                    actor=by,
                    actor_kind=_kind(by),
                    action=action,
                    changes=changes,
                )
            )
    SessionActivity.objects.bulk_create(entries)
```

(The module is imported by the hooked services directly — `from etqan.scheduling.services import activity` — and is not re-exported from `services/__init__.py`.)

- [ ] **Step 4: Run the tests**

Run: `… pytest -q etqan/scheduling/tests/test_activity_writers.py` → PASS. Then `… ruff check . && … ruff format --check . && … lint-imports`.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/scheduling/services/activity.py etqan/scheduling/tests/test_activity_writers.py
git -C backend commit -m "feat(scheduling): activity log writers — track, record_many, reverting (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Attendance, cancel, restore, disposal, bulk and `pays_teacher` write entries

**Files:**
- Modify: `backend/etqan/scheduling/services/attendance.py` (`mark_attendance`, `cancel_session`, `restore_session`, `place_at_disposal`; `bulk_sessions` unchanged — it reaches `track` through the two services it calls)
- Modify: `backend/etqan/scheduling/services/manual.py` (`set_pays_teacher`)
- Modify: `backend/etqan/scheduling/api/session_views.py` (`SessionRestoreView`, `DisposalView`, `PaysTeacherView` pass `by=request.user`)
- Test: `backend/etqan/scheduling/tests/test_activity_tracking.py`

**Interfaces:**
- Consumes: Task 2's `activity.track`, `activity.Action`.
- Produces (additive signatures, every existing caller unchanged):
  - `mark_attendance(session, *, by, student_attendance=None, teacher_attendance=None)` — unchanged signature, action `attendance`.
  - `cancel_session(session, *, by, reason, disposal_reason: str | None = None)` — action `cancel`; `disposal_reason`, when given, is written verbatim.
  - `restore_session(session, *, by=None, to_disposal: bool = False)` — action `restore`; `to_disposal=True` returns a cancelled session to `at_disposal` keeping `disposal_reason` (plan D7).
  - `place_at_disposal(session, *, reason="", by=None)` — action `disposal`.
  - `set_pays_teacher(session, *, pays_teacher, by=None)` — action `pays_teacher`.

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2c §4.1 and §9: every single-session service in attendance.py and
manual.py writes exactly one entry holding exactly the fields it changed;
bulk writes one per done session; a refused change writes nothing."""

from datetime import timedelta

import pytest
from rest_framework.test import APIClient

from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db


@pytest.fixture
def on(set_features):
    set_features(activity_log=True, teacher_attendance=True)


@pytest.fixture
def sub(subscribe, on):
    return subscribe(slots=two_slots())


@pytest.fixture
def started(sub, clock):
    """Monday 1 June 2026, 18:00 UTC, five minutes in."""
    session = Session.objects.filter(subscription=sub).order_by("starts_at").first()
    clock.set(session.starts_at + timedelta(minutes=5))
    return session


@pytest.fixture
def admin():
    return make_admin()


def changes(session):
    return [
        (entry.action, entry.changes)
        for entry in SessionActivity.objects.filter(session=session).order_by("id")
    ]


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


def test_a_student_mark_logs_the_attendance_and_the_status(started, admin):
    services.mark_attendance(started, by=admin, student_attendance="present")
    assert changes(started) == [
        (
            "attendance",
            {
                "status": ["scheduled", "completed"],
                "student_attendance": ["not_set", "present"],
            },
        )
    ]


def test_a_teachers_own_mark_logs_only_the_teacher_attendance(started):
    teacher = started.teacher.user
    services.mark_attendance(started, by=teacher, teacher_attendance="present")
    entry = SessionActivity.objects.get(session=started)
    assert (entry.actor_id, entry.changes) == (
        teacher.pk,
        {"teacher_attendance": ["not_set", "present"]},
    )


def test_marking_the_same_value_again_logs_nothing_new(started, admin):
    services.mark_attendance(started, by=admin, student_attendance="present")
    services.mark_attendance(started, by=admin, student_attendance="present")
    assert len(changes(started)) == 1


def test_cancel_logs_status_and_reason(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    assert changes(started) == [
        ("cancel", {"status": ["scheduled", "cancelled"], "cancel_reason": ["", "Eid"]})
    ]


def test_a_cancel_from_disposal_leaves_the_kept_reason_out(started, admin):
    services.place_at_disposal(started, by=admin, reason="Teacher sick")
    services.cancel_session(started, by=admin, reason="Eid")
    assert changes(started)[1] == (
        "cancel",
        {"status": ["at_disposal", "cancelled"], "cancel_reason": ["", "Eid"]},
    )


def test_cancel_writes_a_given_disposal_reason(started, admin):
    services.cancel_session(
        started, by=admin, reason="Eid", disposal_reason="Teacher sick"
    )
    started.refresh_from_db()
    assert started.disposal_reason == "Teacher sick"
    assert changes(started)[0][1]["disposal_reason"] == ["", "Teacher sick"]


def test_restore_without_by_is_the_system(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    services.restore_session(started)
    entry = SessionActivity.objects.filter(session=started).latest("id")
    assert (entry.action, entry.actor_kind, entry.actor_id) == ("restore", "system", None)
    assert entry.changes == {
        "status": ["cancelled", "scheduled"],
        "cancel_reason": ["Eid", ""],
    }


def test_restore_from_disposal_logs_the_cleared_reason(started, admin):
    services.place_at_disposal(started, by=admin, reason="Teacher sick")
    services.restore_session(started, by=admin)
    assert changes(started)[1] == (
        "restore",
        {"status": ["at_disposal", "scheduled"], "disposal_reason": ["Teacher sick", ""]},
    )


def test_restore_to_disposal_keeps_the_reason_the_cancel_kept(started, admin):
    services.place_at_disposal(started, by=admin, reason="Teacher sick")
    services.cancel_session(started, by=admin, reason="Eid")
    restored = services.restore_session(started, by=admin, to_disposal=True)
    assert (restored.status, restored.disposal_reason, restored.cancel_reason) == (
        "at_disposal",
        "Teacher sick",
        "",
    )


def test_restore_to_disposal_is_only_from_cancelled(started, admin):
    services.place_at_disposal(started, by=admin)
    with pytest.raises(ConflictError) as err:
        services.restore_session(started, by=admin, to_disposal=True)
    assert err.value.code == "scheduling.not_allowed_in_status"


def test_disposal_logs_status_and_reason(started, admin):
    services.place_at_disposal(started, by=admin, reason="Teacher sick")
    assert changes(started) == [
        (
            "disposal",
            {"status": ["scheduled", "at_disposal"], "disposal_reason": ["", "Teacher sick"]},
        )
    ]


def test_pays_teacher_logs_the_flag_once(started, admin):
    services.set_pays_teacher(started, pays_teacher=False, by=admin)
    services.set_pays_teacher(started, pays_teacher=False, by=admin)
    assert changes(started) == [("pays_teacher", {"pays_teacher": [True, False]})]


def test_bulk_logs_one_entry_per_done_session_and_none_for_skipped(sub, clock, admin):
    monday, wednesday = Session.objects.filter(subscription=sub).order_by("starts_at")[:2]
    clock.set(wednesday.starts_at + timedelta(minutes=5))
    services.cancel_session(monday, by=admin, reason="Eid")
    result = services.bulk_sessions([monday.pk, wednesday.pk], action="present", by=admin)
    assert result.done == [wednesday.pk]
    assert [action for action, _c in changes(monday)] == ["cancel"]
    assert [action for action, _c in changes(wednesday)] == ["attendance"]


def test_a_refused_change_writes_nothing(started, admin):
    Session.objects.filter(pk=started.pk).update(payroll_locked=True)
    with pytest.raises(ConflictError):
        services.cancel_session(started, by=admin, reason="Eid")
    assert changes(started) == []


def test_nothing_is_logged_while_the_switch_is_off(started, admin, set_features):
    set_features(activity_log=False)
    services.cancel_session(started, by=admin, reason="Eid")
    services.restore_session(started, by=admin)
    assert changes(started) == []


@pytest.mark.parametrize(
    ("path", "body", "action"),
    [
        ("disposal/", {"reason": "Sick"}, "disposal"),
        ("pays-teacher/", {"pays_teacher": False}, "pays_teacher"),
    ],
)
def test_the_views_name_the_person(started, admin, set_features, path, body, action):
    set_features(disposal_status=True, extra_sessions=True)
    response = as_user(admin).post(
        f"/api/v1/sessions/{started.pk}/{path}", body, format="json"
    )
    assert response.status_code == 200
    entry = SessionActivity.objects.get(session=started)
    assert (entry.action, entry.actor_id) == (action, admin.pk)


def test_the_restore_view_names_the_person(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    huda = make_admin("Huda")
    response = as_user(huda).post(f"/api/v1/sessions/{started.pk}/restore/")
    assert response.status_code == 200
    assert SessionActivity.objects.filter(session=started).latest("id").actor_id == huda.pk
```

- [ ] **Step 2: Run them to see them fail**

Run: `… pytest -q etqan/scheduling/tests/test_activity_tracking.py`
Expected: FAIL (no entries written; `TypeError: restore_session() got an unexpected keyword argument 'by'`). Keep the output.

- [ ] **Step 3: Hook `attendance.py`**

Add the import (alphabetical with the other scheduling imports):

```python
from etqan.scheduling.services import activity
```

Replace `mark_attendance`'s body from `locked = lock(session)` to the end with:

```python
    locked = lock(session)
    # Slice B2c: entered right after the lock, before the refusals (§4.1).
    with activity.track(locked, by, activity.Action.ATTENDANCE):
        refuse_if_paid(locked)
        refuse_if_compensated(locked)
        if locked.status == CANCELLED:
            raise ConflictError(
                "This session was cancelled.", code="scheduling.session_cancelled"
            )
        if student_attendance is not None and locked.status == AT_DISPOSAL:
            # Slice B2a A-11: its teacher's attendance is taken; its student's not.
            raise _not_allowed(locked)
        if not has_started(locked):
            raise ConflictError(
                "Attendance opens when the session starts.",
                code="scheduling.not_started",
            )
        if NOT_SET in (student_attendance, teacher_attendance) and not is_office(by):
            raise PermissionDeniedError("clear attendance")
        fields = ["marked_by", "marked_at", "updated_at"]
        if student_attendance is not None:
            locked.student_attendance = student_attendance
            locked.status = SCHEDULED if student_attendance == NOT_SET else COMPLETED
            fields += ["student_attendance", "status"]
        if teacher_attendance is not None:
            locked.teacher_attendance = teacher_attendance
            fields.append("teacher_attendance")
        locked.marked_by = by
        locked.marked_at = dates.now()
        locked.save(update_fields=fields)
    return locked
```

Replace `cancel_session` with:

```python
@transaction.atomic
def cancel_session(
    session: Session, *, by, reason: str, disposal_reason: str | None = None
) -> Session:
    """Spec §4.3: from scheduled, or from completed (it stops counting).
    Attendance and any report are kept, for the record. Never once an issued
    payslip pays the session (Plan 7 spec §4.5). Slice B2a: also from
    at_disposal, keeping `disposal_reason` for the record. Slice B2c:
    ``disposal_reason``, when given, is written too (a revert of a restore
    puts back the reason the restore cleared)."""
    reason = (reason or "").strip()
    if not reason:
        raise ValidationError("Give a reason.", field="reason")
    locked, _original = lock_with_original(session)
    with activity.track(locked, by, activity.Action.CANCEL):
        refuse_if_paid(locked)
        refuse_if_compensated(locked)
        if locked.status not in (SCHEDULED, COMPLETED, AT_DISPOSAL):
            raise _not_allowed(locked)
        locked.status = CANCELLED
        locked.cancel_reason = reason
        locked.cancelled_by = by
        locked.cancelled_at = dates.now()
        fields = ["status", "cancel_reason", "cancelled_by", "cancelled_at"]
        if disposal_reason is not None:
            locked.disposal_reason = disposal_reason
            fields.append("disposal_reason")
        locked.save(update_fields=[*fields, "updated_at"])
        release_original(locked)
    return locked
```

Replace `restore_session` with:

```python
def _restored_status(session: Session, *, to_disposal: bool) -> str:
    if to_disposal:
        return AT_DISPOSAL
    return SCHEDULED if session.student_attendance == NOT_SET else COMPLETED


@transaction.atomic
def restore_session(
    session: Session, *, by=None, to_disposal: bool = False
) -> Session:
    """Spec §4.3: back to scheduled, or to completed when the student's
    attendance is set; the cancel fields are cleared. A session an issued
    payslip pays is refused before its status is looked at (Plan 7 spec
    §4.5). Slice B2a: a compensated original is frozen (A-4); restoring a
    cancelled compensation re-checks and marks its original (§4.6). Also
    from at_disposal, back to scheduled; any restore clears `disposal_reason`
    (plan D3). Slice B2c: ``to_disposal`` returns a cancelled session to
    at_disposal and keeps its `disposal_reason` (Plan 25 D7); ``by`` is who
    restored it (None: the system)."""
    locked, original = lock_with_original(session)
    with activity.track(locked, by, activity.Action.RESTORE):
        refuse_if_paid(locked)
        refuse_if_compensated(locked)
        if locked.status == CANCELLED:
            if original is not None:
                _reclaim_original(original)
            locked.status = _restored_status(locked, to_disposal=to_disposal)
        elif locked.status == AT_DISPOSAL and not to_disposal:
            locked.status = SCHEDULED
        else:
            raise _not_allowed(locked)
        if not to_disposal:
            locked.disposal_reason = ""
        locked.cancel_reason = ""
        locked.cancelled_by = None
        locked.cancelled_at = None
        locked.save(
            update_fields=[
                "status",
                "cancel_reason",
                "cancelled_by",
                "cancelled_at",
                "disposal_reason",
                "updated_at",
            ]
        )
    return locked
```

Replace `place_at_disposal` with:

```python
@transaction.atomic
def place_at_disposal(session: Session, *, reason: str = "", by=None) -> Session:
    """Slice B2a A-11: a scheduled session whose student attendance is not
    set goes to the administration's disposal. It never consumes, payroll
    does not pay it, and the system never deletes it (it is not untouched).
    Slice B2c: ``by`` is who placed it (None: the system)."""
    locked = lock(session)
    with activity.track(locked, by, activity.Action.DISPOSAL):
        refuse_if_paid(locked)
        refuse_if_compensated(locked)
        if locked.status != SCHEDULED or locked.student_attendance != NOT_SET:
            raise _not_allowed(locked)
        locked.status = AT_DISPOSAL
        locked.disposal_reason = (reason or "").strip()
        locked.save(update_fields=["status", "disposal_reason", "updated_at"])
    return locked
```

- [ ] **Step 4: Hook `manual.set_pays_teacher`**

Add `from etqan.scheduling.services import activity` to `manual.py`'s imports and replace `set_pays_teacher` with:

```python
@transaction.atomic
def set_pays_teacher(session: Session, *, pays_teacher: bool, by=None) -> Session:
    """§4.7: the office switches whether the session pays its teacher, until
    an issued payslip pays it. Slice B2c: ``by`` is who switched it."""
    locked = attendance.lock(session)
    with activity.track(locked, by, activity.Action.PAYS_TEACHER):
        refuse_if_paid(locked)
        locked.pays_teacher = pays_teacher
        locked.save(update_fields=["pays_teacher", "updated_at"])
    return locked
```

- [ ] **Step 5: The views pass the person** (`api/session_views.py`)

```python
class SessionRestoreView(APIView):
    permission_classes = [HasCode]
    permission_codes = {"POST": "session.update"}

    def post(self, request, pk):
        services.restore_session(session_or_404(request, pk), by=request.user)
        return Response(session_payload(request, pk))
```

In `DisposalView.post`: `services.place_at_disposal(session, by=request.user, **body.validated_data)`. In `PaysTeacherView.post`: `services.set_pays_teacher(session, by=request.user, **body.validated_data)`.

- [ ] **Step 6: Run the new tests, then the existing suites**

Run: `… pytest -q etqan/scheduling/tests/test_activity_tracking.py` → PASS.
Run: `… pytest -q etqan/scheduling etqan/payroll etqan/notifications etqan/access` → PASS (existing suites unchanged: the switch is off by default). Ruff, format, lint-imports clean.

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/scheduling/services/attendance.py etqan/scheduling/services/manual.py etqan/scheduling/api/session_views.py etqan/scheduling/tests/test_activity_tracking.py
git -C backend commit -m "feat(scheduling): attendance, cancel, restore, disposal and pay flag write activity (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Supervision, times and postponement write entries; `postpone_session(starts_at=)`

**Files:**
- Modify: `backend/etqan/scheduling/services/supervision.py` (`update_session_supervision`, `mark_supervisor_attendance`)
- Modify: `backend/etqan/scheduling/services/times.py` (`record_times`)
- Modify: `backend/etqan/scheduling/services/postpone.py` (`postpone_session`, new `_when`)
- Test: `backend/etqan/scheduling/tests/test_activity_tracking_more.py`

**Interfaces:**
- Consumes: Task 2's `activity.track`.
- Produces:
  - `update_session_supervision(session, *, fields, by)` — unchanged signature; action `supervision`. A reassignment's reset of `supervisor_attendance` lands in the same entry.
  - `mark_supervisor_attendance(session, *, by, status)` — unchanged; action `supervisor_attendance`.
  - `record_times(session, *, by, fields)` — unchanged; action `times`.
  - `postpone_session(session, *, by, occurs_on: date | None = None, start_time: time | None = None, starts_at: datetime | None = None) -> Postponed` — action `postpone` (only `occurs_on` and `starts_at` are logged; slot and origin columns are not). With `starts_at`, `occurs_on` and `start_time` are derived on the academy's clock (plan D6); neither → `ValidationError(field="occurs_on")`.

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2c §4.1: supervision, times and postponement write their entries;
`postpone_session(starts_at=)` takes an exact instant (plan D6)."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta

import pytest

from etqan.academy import services as academy_services
from etqan.access import services as access_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import dates
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db


def supervisor(name):
    """An active staff account that may supervise (Plan 12b)."""
    role = access_services.create_role(
        name_en=f"Watch {name}",
        name_ar=f"مراقبة {name}",
        permissions=["session.supervise"],
        by=None,
    )
    user = identity_services.create_person(
        "staff", full_name=name, email=f"{name.lower()}@x.test"
    )
    user.staff_roles.set([role])
    return user


@pytest.fixture
def on(set_features):
    set_features(activity_log=True, teacher_attendance=True)


@pytest.fixture
def sub(subscribe, on):
    return subscribe(slots=two_slots())


def nth(sub, index):
    return Session.objects.filter(subscription=sub).order_by("starts_at")[index]


def entries(session):
    return list(SessionActivity.objects.filter(session=session).order_by("id"))


def test_a_reassignment_logs_the_supervisor_and_the_reset_attendance(sub):
    admin = make_admin()
    session = nth(sub, 1)
    sara, huda = supervisor("Sara"), supervisor("Huda")
    patch = services.update_session_supervision
    patch(session, fields={"supervisor_id": sara.pk}, by=admin)
    patch(session, fields={"supervisor_attendance": "present"}, by=admin)
    patch(session, fields={"supervisor_id": huda.pk}, by=admin)
    assert [(e.action, e.changes) for e in entries(session)] == [
        ("supervision", {"supervisor_id": [None, sara.pk]}),
        ("supervision", {"supervisor_attendance": ["not_set", "present"]}),
        (
            "supervision",
            {
                "supervisor_id": [sara.pk, huda.pk],
                "supervisor_attendance": ["present", "not_set"],
            },
        ),
    ]


def test_the_supervisors_own_mark_is_logged_as_theirs(sub, clock):
    session = nth(sub, 0)
    sara = supervisor("Sara")
    services.update_session_supervision(
        session, fields={"supervisor_id": sara.pk}, by=make_admin()
    )
    clock.set(session.starts_at)
    services.mark_supervisor_attendance(session, by=sara, status="present")
    entry = entries(session)[-1]
    assert (entry.action, entry.actor_id, entry.changes) == (
        "supervisor_attendance",
        sara.pk,
        {"supervisor_attendance": ["not_set", "present"]},
    )


def test_times_log_the_instants_and_the_minutes_that_follow(sub, clock):
    session = nth(sub, 0)  # Monday 1 June, 18:00 UTC
    clock.set(session.starts_at + timedelta(minutes=50))
    teacher = session.teacher.user
    services.record_times(
        session, by=teacher, fields={"teacher_in_at": session.starts_at}
    )
    services.record_times(
        session,
        by=teacher,
        fields={"teacher_out_at": session.starts_at + timedelta(minutes=45)},
    )
    assert [e.changes for e in entries(session)] == [
        {"teacher_in_at": [None, "2026-06-01T18:00:00Z"]},
        {"teacher_out_at": [None, "2026-06-01T18:45:00Z"], "actual_minutes": [None, 45]},
    ]


def test_a_postponement_logs_the_day_and_the_start_only(sub):
    session = nth(sub, 1)  # Wednesday 3 June, 18:00 UTC
    services.postpone_session(
        session, by=make_admin(), occurs_on=date(2026, 6, 4), start_time=time(20, 0)
    )
    (entry,) = entries(session)
    assert (entry.action, entry.changes) == (
        "postpone",
        {
            "occurs_on": ["2026-06-03", "2026-06-04"],
            "starts_at": ["2026-06-03T18:00:00Z", "2026-06-04T20:00:00Z"],
        },
    )


def test_postpone_takes_an_exact_instant_on_an_ambiguous_hour(sub):
    academy_services.update_settings(timezone="Europe/Berlin")
    # 02:30 on 25 October 2026 happens twice in Berlin; 01:30 UTC is the second.
    second = datetime(2026, 10, 25, 1, 30, tzinfo=UTC)
    extra = hand_session(
        sub,
        occurs_on=date(2026, 10, 24),
        kind="extra",
        starts_at=datetime(2026, 10, 24, 10, 0, tzinfo=UTC),
    )
    moved = services.postpone_session(extra, by=None, starts_at=second).session
    assert (moved.starts_at, moved.occurs_on) == (second, date(2026, 10, 25))
    # The wall-clock path would have taken the first 02:30 instead.
    assert dates.to_utc(date(2026, 10, 25), time(2, 30), "Europe/Berlin") != second


def test_postpone_needs_a_day_and_a_time_or_an_instant(sub):
    with pytest.raises(ValidationError) as err:
        services.postpone_session(nth(sub, 1), by=None)
    assert err.value.field == "occurs_on"
```

- [ ] **Step 2: Run them to see them fail**

Run: `… pytest -q etqan/scheduling/tests/test_activity_tracking_more.py`
Expected: FAIL (no entries; `TypeError: postpone_session() got an unexpected keyword argument 'starts_at'` / missing `occurs_on`). Keep the output.

- [ ] **Step 3: Hook `supervision.py`**

Add `from etqan.scheduling.services import activity`. Replace `update_session_supervision`'s body from `locked = lock(session)` with:

```python
    locked = lock(session)
    with activity.track(locked, by, activity.Action.SUPERVISION):
        changed = []
        if "supervisor_id" in fields:
            changed += _reassign(locked, fields["supervisor_id"])
        if "supervisor_attendance" in fields:
            changed += _set_attendance(locked, fields["supervisor_attendance"])
        if changed:
            locked.save(update_fields=[*dict.fromkeys(changed), "updated_at"])
    return locked
```

Replace `mark_supervisor_attendance`'s body after the `status` check with:

```python
    locked = _own(session, by=by)
    # Plan 25 D11: after `_own`'s refusals; this service is never an inverse.
    with activity.track(locked, by, activity.Action.SUPERVISOR_ATTENDANCE):
        locked.supervisor_attendance = status
        locked.save(update_fields=["supervisor_attendance", "updated_at"])
    return locked
```

- [ ] **Step 4: Hook `times.py`**

Add `from etqan.scheduling.services import activity`. Replace `record_times`'s body from `locked = lock(session)` with:

```python
    locked = lock(session)
    with activity.track(locked, by, activity.Action.TIMES):
        refuse_if_paid(locked)
        if locked.status == Session.Status.CANCELLED:
            raise ConflictError(
                "This session was cancelled.", code="scheduling.session_cancelled"
            )
        _gate(locked, fields, office=office)
        for name, value in fields.items():
            setattr(locked, name, value)
        _check_pairs(locked)
        if (
            "actual_minutes" not in fields
            and locked.actual_minutes is None
            and locked.teacher_in_at is not None
            and locked.teacher_out_at is not None
        ):
            seconds = (locked.teacher_out_at - locked.teacher_in_at).total_seconds()
            locked.actual_minutes = max(1, round(seconds / SECONDS_PER_MINUTE))
        locked.save(update_fields=[*ALL_FIELDS, "updated_at"])
    return locked
```

- [ ] **Step 5: Hook `postpone.py` and add `starts_at`**

Add the imports:

```python
from zoneinfo import ZoneInfo

from etqan.scheduling.services import activity
```

Add above `postpone_session`:

```python
def _when(
    occurs_on: date | None, start_time: time | None, starts_at: datetime | None, zone: str
) -> tuple[date, time, datetime]:
    """Plan 25 D6: an exact instant (a revert keeps an ambiguous DST hour) or
    the academy's wall clock (Plan 4's single conversion)."""
    if starts_at is not None:
        local = starts_at.astimezone(ZoneInfo(zone))
        return local.date(), local.time(), starts_at
    if occurs_on is None or start_time is None:
        raise ValidationError("Choose a day and a time.", field="occurs_on")
    return occurs_on, start_time, dates.to_utc(occurs_on, start_time, zone)
```

Replace `postpone_session` with:

```python
@transaction.atomic
def postpone_session(
    session: Session,
    *,
    by,
    occurs_on: date | None = None,
    start_time: time | None = None,
    starts_at: datetime | None = None,
) -> Postponed:
    """Spec §4.2, refusals in its order. ``by=None`` is the system, which
    acts as the office (Plan 21 D1). Slice B2c: ``starts_at`` is an exact
    UTC instant (a revert's); ``occurs_on`` and ``start_time`` then follow
    from it on the academy's clock."""
    locked, sub = _lock(session)
    with activity.track(locked, by, activity.Action.POSTPONE):
        office = rules.acts_as_office(by)
        academy = rules.settings()
        _refuse_state(locked, sub)
        occurs_on, start_time, start = _when(
            occurs_on, start_time, starts_at, academy.timezone
        )
        _refuse_date(locked, sub, occurs_on, start, academy.renewal_grace_days)
        if not office:
            _refuse_for_family_or_teacher(
                locked, start, academy.postpone_limit_minutes
            )
        if _reattach(locked, occurs_on, start_time):
            locked.slot = locked.original_slot
            locked.original_slot = None
            locked.original_on = None
            locked.original_starts_at = None
            locked.postponed_by = None
            locked.postponed_at = None
        else:
            if locked.slot_id is not None:
                locked.original_slot_id = locked.slot_id
                locked.original_on = locked.occurs_on
                locked.slot = None
            if locked.original_starts_at is None:
                locked.original_starts_at = locked.starts_at
            locked.postponed_by = by
            locked.postponed_at = dates.now()
        locked.occurs_on = occurs_on
        locked.starts_at = start
        locked.save(
            update_fields=[
                "slot",
                "original_slot",
                "original_on",
                "original_starts_at",
                "postponed_by",
                "postponed_at",
                "occurs_on",
                "starts_at",
                "updated_at",
            ]
        )
    fresh = rules.sessions_queryset().get(pk=locked.pk)
    return Postponed(fresh, generation.conflicts([fresh]) if office else [])
```

(If ruff reports C901 on `postpone_session`, move the re-attach / detach block into `_move(locked, by, occurs_on, start_time, start) -> None` called inside the `with`; behaviour stays identical.)

- [ ] **Step 6: Run the new tests and B2b's suites**

Run: `… pytest -q etqan/scheduling/tests/test_activity_tracking_more.py etqan/scheduling/tests/test_times_postponement_postpone.py etqan/scheduling/tests/test_times_postponement_times.py etqan/scheduling/tests/test_supervision.py etqan/scheduling/tests/test_api_times_postponement.py etqan/scheduling/tests/test_api_supervision.py` → PASS. Ruff, format, lint-imports clean.

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/scheduling/services/supervision.py etqan/scheduling/services/times.py etqan/scheduling/services/postpone.py etqan/scheduling/tests/test_activity_tracking_more.py
git -C backend commit -m "feat(scheduling): supervision, times and postponement write activity; postpone takes an exact instant (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The three subscription-wide changes log through `record_many`

**Files:**
- Modify: `backend/etqan/scheduling/services/subscriptions.py` (`update_subscription`, `renew_subscription`, new `_move_postponed_teacher`)
- Modify: `backend/etqan/scheduling/services/supervision.py` (`set_subscription_supervisor`)
- Modify: `backend/etqan/scheduling/api/views.py` (`SubscriptionDetailView.patch`, `RenewView.post` pass `by=request.user`)
- Test: `backend/etqan/scheduling/tests/test_activity_subscription_wide.py`

**Interfaces:**
- Consumes: Task 2's `activity.record_many`.
- Produces (additive):
  - `update_subscription(subscription, *, teacher_id=None, price_minor=None, notes=None, starts_on=None, by=None)` — the teacher change logs `teacher_moved` `{teacher_id: [before, after]}` (teacher profile ids) per postponed session moved.
  - `renew_subscription(subscription, *, starts_on=None, teacher_id=None, package_id=None, price_minor=None, course_id=None, by=None)` — logs `renewal_moved` `{subscription_id: [old, renewal]}` per postponed session moved onto the renewal.
  - `set_subscription_supervisor(subscription, *, supervisor_id, by=None)` (plan D5) — logs `subscription_supervisor` `{supervisor_id, supervisor_attendance}` per unstarted session it changed.

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2c §4.1: the three subscription-wide changes log one entry per
session they move, through `record_many` (no inverse, C-8)."""

from datetime import date
from datetime import time
from datetime import timedelta

import pytest
from rest_framework.test import APIClient

from etqan.access import services as access_services
from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
WED = date(2026, 6, 3)


@pytest.fixture
def on(set_features):
    set_features(activity_log=True, supervision=True)


@pytest.fixture
def sub(subscribe, on):
    return subscribe(slots=two_slots())


def postponed(sub, to=date(2026, 6, 4), on=WED):
    session = Session.objects.get(subscription=sub, occurs_on=on)
    return services.postpone_session(
        session, by=None, occurs_on=to, start_time=time(20, 0)
    ).session


def course_teacher(world, name="Hamza"):
    """Another teacher of the course (a subscription's teacher must teach it)."""
    teacher = make_teacher(name)
    catalogue_services.update_course(
        world.course, teacher_ids=[world.teacher.id, teacher.id]
    )
    return teacher


def supervisor(name):
    role = access_services.create_role(
        name_en=f"Watch {name}",
        name_ar=f"مراقبة {name}",
        permissions=["session.supervise"],
        by=None,
    )
    user = identity_services.create_person(
        "staff", full_name=name, email=f"{name.lower()}@x.test"
    )
    user.staff_roles.set([role])
    return user


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


def test_a_teacher_change_logs_each_postponed_session_it_moves(sub, world):
    moved = postponed(sub)
    before = moved.teacher_id
    hamza = course_teacher(world)
    admin = make_admin()
    services.update_subscription(sub, teacher_id=hamza.id, by=admin)
    entry = SessionActivity.objects.get(session=moved, action="teacher_moved")
    assert entry.actor_id == admin.pk
    assert entry.changes == {"teacher_id": [before, hamza.teacher_profile.pk]}


def test_a_renewal_logs_each_postponed_session_it_takes(sub):
    moved = postponed(sub, to=date(2026, 7, 2))
    renewal = services.renew_subscription(
        sub, starts_on=date(2026, 7, 1), by=make_admin()
    )
    entry = SessionActivity.objects.get(session=moved, action="renewal_moved")
    assert entry.changes == {"subscription_id": [sub.pk, renewal.pk]}


def test_a_subscription_supervisor_change_logs_each_unstarted_session(sub, clock):
    first, second = Session.objects.filter(subscription=sub).order_by("starts_at")[:2]
    clock.set(first.starts_at + timedelta(minutes=1))
    sara = supervisor("Sara")
    services.set_subscription_supervisor(sub, supervisor_id=sara.pk, by=make_admin())
    assert not SessionActivity.objects.filter(session=first).exists()
    entry = SessionActivity.objects.get(session=second)
    assert (entry.action, entry.changes) == (
        "subscription_supervisor",
        {"supervisor_id": [None, sara.pk]},
    )
    unstarted = Session.objects.filter(
        subscription=sub, starts_at__gt=first.starts_at + timedelta(minutes=1)
    ).count()
    assert SessionActivity.objects.filter(action="subscription_supervisor").count() == (
        unstarted
    )


def test_none_of_them_log_while_the_switch_is_off(sub, world, set_features):
    postponed(sub)
    set_features(activity_log=False)
    services.update_subscription(sub, teacher_id=course_teacher(world).id)
    services.set_subscription_supervisor(sub, supervisor_id=supervisor("Sara").pk)
    assert not SessionActivity.objects.exclude(action="postpone").exists()


def test_the_subscription_routes_name_the_person(sub):
    moved = postponed(sub, to=date(2026, 7, 2))
    admin = make_admin()
    sara = supervisor("Sara")
    client = as_user(admin)
    patched = client.patch(
        f"/api/v1/subscriptions/{sub.pk}/", {"supervisor_id": sara.pk}, format="json"
    )
    assert patched.status_code == 200
    renewed = client.post(
        f"/api/v1/subscriptions/{sub.pk}/renew/", {"starts_on": "2026-07-01"}, format="json"
    )
    assert renewed.status_code == 201
    kinds = SessionActivity.objects.exclude(action="postpone").values_list(
        "action", "actor_id"
    )
    assert {actor for _action, actor in kinds} == {admin.pk}
    assert SessionActivity.objects.filter(session=moved, action="renewal_moved").exists()
```

- [ ] **Step 2: Run them to see them fail**

Run: `… pytest -q etqan/scheduling/tests/test_activity_subscription_wide.py`
Expected: FAIL (`TypeError: … unexpected keyword argument 'by'`). Keep the output.

- [ ] **Step 3: `subscriptions.py`**

Add `from etqan.scheduling.services import activity`. Add after `_postponed_unmarked`:

```python
def _move_postponed_teacher(subscription: Subscription, *, by) -> None:
    """B2b B-9: postponed lessons go with the subscription's teacher. Slice
    B2c: each move is logged (`teacher_moved`), from the teacher each row
    had, read under the lock `_postponed_unmarked` took."""
    ids = _postponed_unmarked(subscription)
    before = dict(Session.objects.filter(pk__in=ids).values_list("pk", "teacher_id"))
    Session.objects.filter(pk__in=ids).update(
        teacher=subscription.teacher, updated_at=dates.now()
    )
    activity.record_many(
        [(pk, {"teacher_id": (before[pk], subscription.teacher_id)}) for pk in ids],
        by,
        activity.Action.TEACHER_MOVED,
    )
```

`update_subscription`: signature gains `by=None` (add `# noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)` on the `def` line) and the docstring a line "Slice B2c: ``by`` is who changed it (None: the system)."; replace the teacher block with:

```python
    if {"teacher", "starts_on"} & set(changed):
        if "teacher" in changed:
            _move_postponed_teacher(locked, by=by)
        _regenerate(locked)
    return locked
```

`renew_subscription`: signature gains `by=None` after `course_id`; replace its move with:

```python
    # B2b B-5 (Plan 21 D6): postponed lessons now in the renewal's period go
    # with it, before the old subscription's expiry could remove them.
    moved = _postponed_unmarked(old, occurs_on__gte=starts_on)
    Session.objects.filter(pk__in=moved).update(
        subscription=renewal, updated_at=dates.now()
    )
    activity.record_many(
        [(pk, {"subscription_id": (old.pk, renewal.pk)}) for pk in moved],
        by,
        activity.Action.RENEWAL_MOVED,
    )
    if expire_now:
        rules.expire([old.pk])
    return renewal
```

- [ ] **Step 4: `supervision.set_subscription_supervisor`** (plan D5)

```python
@transaction.atomic
def set_subscription_supervisor(
    subscription: Subscription, *, supervisor_id: int | None, by=None
) -> Subscription:
    """§3.5: the subscription's supervisor, and that of its sessions that
    have not started (a per-session override among them too). Sessions that
    have started keep theirs. Locked and re-read like every subscription
    change, and only while it is active or paused. Slice B2c: each session
    it changes is logged (`subscription_supervisor`) for ``by``."""
    supervisor = supervisor_for(supervisor_id)
    locked = Subscription.objects.select_for_update().get(pk=subscription.pk)
    rules.require_status(locked)
    new_id = supervisor.pk if supervisor else None
    if locked.supervisor_id == new_id:
        return locked
    locked.supervisor = supervisor
    locked.save(update_fields=["supervisor", "updated_at"])
    rows = list(
        Session.objects.filter(subscription=locked, starts_at__gt=dates.now())
        .exclude(supervisor=supervisor)
        .order_by("pk")
        .select_for_update()
        .values_list("pk", "supervisor_id", "supervisor_attendance")
    )
    Session.objects.filter(pk__in=[pk for pk, _old, _mark in rows]).update(
        supervisor=supervisor, updated_at=dates.now(), **_unassigned()
    )
    activity.record_many(
        [
            (pk, {"supervisor_id": (old, new_id), "supervisor_attendance": (mark, NOT_SET)})
            for pk, old, mark in rows
        ],
        by,
        activity.Action.SUBSCRIPTION_SUPERVISOR,
    )
    return locked
```

- [ ] **Step 5: The subscription views pass the person** (`api/views.py`)

In `SubscriptionDetailView.patch`: `services.update_subscription(sub, by=request.user, **data)` and `services.set_subscription_supervisor(sub, by=request.user, **supervisor)`. In `RenewView.post`: `new = services.renew_subscription(sub, by=request.user, **_ids(body.validated_data))`.

- [ ] **Step 6: Run the new tests and the suites that touch subscriptions**

Run: `… pytest -q etqan/scheduling etqan/billing etqan/payroll etqan/notifications` → PASS (the B2b lock-order tests for the teacher change and renewal still see exactly one `FOR UPDATE` on the moved sessions: the extra `teacher_id` read is unlocked, under the lock already held). Ruff, format, lint-imports clean.

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/scheduling/services/subscriptions.py etqan/scheduling/services/supervision.py etqan/scheduling/api/views.py etqan/scheduling/tests/test_activity_subscription_wide.py
git -C backend commit -m "feat(scheduling): teacher change, renewal and subscription supervisor log each moved session (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Reverting an entry (`services/revert.py`)

**Files:**
- Create: `backend/etqan/scheduling/services/revert.py`
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Test: `backend/etqan/scheduling/tests/test_activity_revert.py`

**Interfaces:**
- Consumes: Tasks 2–5 (every hooked service and its additive keywords), `activity.reverting`, `activity.from_json`, `activity.FIELD_FEATURES`, `supervision.SESSION_FIELDS`, `times.ALL_FIELDS`, `platform.permissions.codes_of`, `is_office`.
- Produces (exported from `etqan.scheduling.services`):
  - `Reverted` — frozen dataclass `(session: Session, entry: SessionActivity)`; `session` read from `sessions_queryset()`, `entry` the inverse's own entry (`reverts` = the reverted one).
  - `revert_refusal(entry: SessionActivity, by) -> str | None` — §4.2 step 1 without raising: `"not_revertible"` (no inverse, `activity_log` off, or an action or field switch off), `"forbidden"` (not office, or a code missing), else `None`. No query beyond `codes_of` (cached per user object).
  - `revert_activity(entry: SessionActivity, *, by) -> Reverted` — raises `ConflictError("scheduling.not_revertible")`, `PermissionDeniedError` (403), then whatever the inverse raises (`scheduling.changed_since` first).
  - `INVERSES: dict[str, Inverse]` (module-level; `Inverse(run, codes, switches)`).

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2c §4.2 and §9: reverting an entry runs the inverse service as the
person reverting, so every rule applies as for a fresh change."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.academy import services as academy_services
from etqan.access import services as access_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import PermissionDeniedError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
SWITCHES = {
    "activity_log": True,
    "teacher_attendance": True,
    "supervision": True,
    "session_times": True,
    "postponement": True,
    "extra_sessions": True,
    "disposal_status": True,
}


def supervisor(name):
    role = access_services.create_role(
        name_en=f"Watch {name}",
        name_ar=f"مراقبة {name}",
        permissions=["session.supervise"],
        by=None,
    )
    user = identity_services.create_person(
        "staff", full_name=name, email=f"{name.lower()}@x.test"
    )
    user.staff_roles.set([role])
    return user


@pytest.fixture
def on(set_features):
    set_features(**SWITCHES)


@pytest.fixture
def sub(subscribe, on):
    return subscribe(slots=two_slots())


@pytest.fixture
def admin():
    return make_admin()


def nth(sub, index=0):
    return Session.objects.filter(subscription=sub).order_by("starts_at")[index]


@pytest.fixture
def started(sub, clock):
    """Monday 1 June 2026, 18:00 UTC, five minutes in."""
    session = nth(sub)
    clock.set(session.starts_at + timedelta(minutes=5))
    return session


def last(session):
    return SessionActivity.objects.filter(session=session).latest("id")


def fresh(session):
    return Session.objects.get(pk=session.pk)


def revert(session, by):
    return services.revert_activity(last(session), by=by)


def count(session):
    return SessionActivity.objects.filter(session=session).count()


# ── Each action's inverse ────────────────────────────────────────────────────


def test_an_attendance_mark_reverts_to_not_set(started, admin):
    services.mark_attendance(started, by=admin, student_attendance="present")
    entry = last(started)
    result = services.revert_activity(entry, by=admin)
    assert (result.session.student_attendance, result.session.status) == (
        "not_set",
        "scheduled",
    )
    assert (result.entry.action, result.entry.reverts_id, result.entry.actor_id) == (
        "attendance",
        entry.pk,
        admin.pk,
    )


def test_a_teacher_only_mark_on_a_disposal_session_reverts_alone(started, admin):
    services.place_at_disposal(started, by=admin, reason="Teacher sick")
    teacher = started.teacher.user
    services.mark_attendance(started, by=teacher, teacher_attendance="present")
    revert(started, admin)
    after = fresh(started)
    assert (after.teacher_attendance, after.status, after.student_attendance) == (
        "not_set",
        "at_disposal",
        "not_set",
    )


def test_a_cancel_reverts_to_scheduled(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    revert(started, admin)
    after = fresh(started)
    assert (after.status, after.cancel_reason) == ("scheduled", "")


def test_a_cancel_from_disposal_reverts_to_disposal_keeping_its_reason(started, admin):
    services.place_at_disposal(started, by=admin, reason="Teacher sick")
    services.cancel_session(started, by=admin, reason="Eid")
    revert(started, admin)
    after = fresh(started)
    assert (after.status, after.disposal_reason, after.cancel_reason) == (
        "at_disposal",
        "Teacher sick",
        "",
    )


def test_a_restore_reverts_to_cancelled_with_both_reasons(started, admin):
    services.place_at_disposal(started, by=admin, reason="Teacher sick")
    services.cancel_session(started, by=admin, reason="Eid")
    services.restore_session(started, by=admin)
    revert(started, admin)
    after = fresh(started)
    assert (after.status, after.cancel_reason, after.disposal_reason) == (
        "cancelled",
        "Eid",
        "Teacher sick",
    )


def test_a_restore_from_disposal_reverts_to_disposal(started, admin):
    services.place_at_disposal(started, by=admin, reason="Teacher sick")
    services.restore_session(started, by=admin)
    revert(started, admin)
    after = fresh(started)
    assert (after.status, after.disposal_reason) == ("at_disposal", "Teacher sick")


def test_a_disposal_reverts_to_scheduled(started, admin):
    services.place_at_disposal(started, by=admin, reason="Teacher sick")
    revert(started, admin)
    after = fresh(started)
    assert (after.status, after.disposal_reason) == ("scheduled", "")


def test_the_pay_flag_reverts(started, admin):
    services.set_pays_teacher(started, pays_teacher=False, by=admin)
    revert(started, admin)
    assert fresh(started).pays_teacher is True


def test_a_reassignment_reverts_with_the_attendance_it_reset(sub, admin):
    session = nth(sub, 1)
    sara, huda = supervisor("Sara"), supervisor("Huda")
    patch = services.update_session_supervision
    patch(session, fields={"supervisor_id": sara.pk}, by=admin)
    patch(session, fields={"supervisor_attendance": "present"}, by=admin)
    patch(session, fields={"supervisor_id": huda.pk}, by=admin)
    revert(session, admin)
    after = fresh(session)
    assert (after.supervisor_id, after.supervisor_attendance) == (sara.pk, "present")


def test_the_supervisors_own_mark_reverts_through_the_patch(started, admin):
    sara = supervisor("Sara")
    services.update_session_supervision(
        started, fields={"supervisor_id": sara.pk}, by=admin
    )
    services.mark_supervisor_attendance(started, by=sara, status="present")
    revert(started, admin)
    assert fresh(started).supervisor_attendance == "not_set"


def test_minutes_cleared_by_a_revert_stay_empty(started, admin, clock):
    clock.set(started.starts_at + timedelta(minutes=50))
    services.record_times(
        started,
        by=admin,
        fields={
            "teacher_in_at": started.starts_at,
            "teacher_out_at": started.starts_at + timedelta(minutes=45),
        },
    )
    services.record_times(started, by=admin, fields={"actual_minutes": None})
    services.record_times(started, by=admin, fields={"actual_minutes": 30})
    revert(started, admin)
    # B2b B-3: the minutes key is sent as None, so it is not recomputed to 45.
    assert fresh(started).actual_minutes is None


def test_a_postponement_reverts_onto_its_slot(sub, admin):
    session = nth(sub, 1)  # Wednesday 3 June, 18:00 UTC
    slot_id = session.slot_id
    services.postpone_session(
        session, by=admin, occurs_on=date(2026, 6, 4), start_time=time(20, 0)
    )
    revert(session, admin)
    after = fresh(session)
    assert (after.slot_id, after.occurs_on, after.starts_at, after.postponed_at) == (
        slot_id,
        date(2026, 6, 3),
        datetime(2026, 6, 3, 18, 0, tzinfo=UTC),
        None,
    )


def test_a_postponement_from_an_ambiguous_hour_reverts_to_the_exact_instant(
    sub, admin
):
    academy_services.update_settings(timezone="Europe/Berlin")
    second = datetime(2026, 10, 25, 1, 30, tzinfo=UTC)  # the second 02:30 in Berlin
    extra = hand_session(
        sub, occurs_on=date(2026, 10, 25), kind="extra", starts_at=second
    )
    services.postpone_session(
        extra, by=admin, occurs_on=date(2026, 10, 26), start_time=time(10, 0)
    )
    revert(extra, admin)
    assert (fresh(extra).starts_at, fresh(extra).occurs_on) == (
        second,
        date(2026, 10, 25),
    )


def test_a_revert_can_itself_be_reverted(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    first = services.revert_activity(last(started), by=admin).entry
    again = services.revert_activity(first, by=admin)
    assert (again.session.status, again.session.cancel_reason) == ("cancelled", "Eid")
    assert (again.entry.action, again.entry.reverts_id) == ("cancel", first.pk)


# ── Refusals before the inverse (§4.2 step 1) ────────────────────────────────


def test_subscription_wide_moves_are_not_revertible(sub, admin):
    session = nth(sub, 1)
    services.set_subscription_supervisor(
        sub, supervisor_id=supervisor("Sara").pk, by=admin
    )
    with pytest.raises(ConflictError) as err:
        revert(session, admin)
    assert err.value.code == "scheduling.not_revertible"


@pytest.mark.parametrize("switch", ["disposal_status", "activity_log"])
def test_a_switched_off_feature_makes_an_entry_not_revertible(
    started, admin, set_features, switch
):
    services.place_at_disposal(started, by=admin, reason="Sick")
    set_features(**{switch: False})
    with pytest.raises(ConflictError) as err:
        revert(started, admin)
    assert err.value.code == "scheduling.not_revertible"


def test_a_field_whose_switch_is_off_makes_the_entry_not_revertible(
    sub, admin, set_features
):
    session = nth(sub, 1)
    services.update_session_supervision(
        session, fields={"supervisor_id": supervisor("Sara").pk}, by=admin
    )
    set_features(supervision=False)
    with pytest.raises(ConflictError) as err:
        revert(session, admin)
    assert err.value.code == "scheduling.not_revertible"


def test_the_inverses_codes_are_needed(started, admin, staff_for):
    services.mark_attendance(started, by=admin, student_attendance="present")
    clerk = staff_for("session.update").user
    with pytest.raises(PermissionDeniedError):
        revert(started, clerk)
    allowed = staff_for("session.update", "attendance.update").user
    assert revert(started, allowed).session.student_attendance == "not_set"


def test_a_teacher_may_not_revert(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    with pytest.raises(PermissionDeniedError):
        revert(started, started.teacher.user)


# ── Changed since (§4.2 step 2) ──────────────────────────────────────────────


def test_a_field_that_moved_on_is_a_conflict(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    cancel = last(started)
    services.restore_session(started, by=admin)
    services.cancel_session(started, by=admin, reason="Rain")
    with pytest.raises(ConflictError) as err:
        services.revert_activity(cancel, by=admin)
    assert err.value.code == "scheduling.changed_since"


def test_reverting_twice_is_a_conflict_the_second_time(started, admin):
    """Two reverts of one entry (two tabs, a double click; plan D10): the
    second waits on the inverse's lock, then finds the fields moved on."""
    services.cancel_session(started, by=admin, reason="Eid")
    cancel = last(started)
    services.revert_activity(cancel, by=admin)
    written = count(started)
    with pytest.raises(ConflictError) as err:
        services.revert_activity(cancel, by=admin)
    assert err.value.code == "scheduling.changed_since"
    assert count(started) == written


# ── The inverse's own refusals propagate (§4.2 step 3) ───────────────────────


def test_a_paid_session_refuses_the_revert_and_writes_nothing(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    Session.objects.filter(pk=started.pk).update(payroll_locked=True)
    with pytest.raises(ConflictError) as err:
        revert(started, admin)
    assert err.value.code == "payroll.payslip_issued"
    assert count(started) == 1


def test_a_restore_whose_cancel_is_now_impossible_is_refused(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    services.restore_session(started, by=admin)
    Session.objects.filter(pk=started.pk).update(compensated=True)
    with pytest.raises(ConflictError) as err:
        revert(started, admin)
    assert err.value.code == "scheduling.has_compensation"


def test_a_former_supervisor_is_a_400(sub, admin):
    session = nth(sub, 1)
    sara, huda = supervisor("Sara"), supervisor("Huda")
    patch = services.update_session_supervision
    patch(session, fields={"supervisor_id": sara.pk}, by=admin)
    patch(session, fields={"supervisor_id": huda.pk}, by=admin)
    identity_services.deactivate(sara, by=None)
    with pytest.raises(ValidationError) as err:
        revert(session, admin)
    assert err.value.field == "supervisor_id"


def test_a_postponement_whose_first_start_has_passed_is_refused(sub, admin, clock):
    session = nth(sub, 1)
    services.postpone_session(
        session, by=admin, occurs_on=date(2026, 6, 4), start_time=time(20, 0)
    )
    clock.set(datetime(2026, 6, 3, 19, 0, tzinfo=UTC))
    with pytest.raises(ValidationError) as err:
        revert(session, admin)
    assert err.value.field == "occurs_on"


def test_an_early_stamp_reverted_before_the_start_waits_for_it(sub, admin, clock):
    session = nth(sub)
    early = session.starts_at - timedelta(minutes=10)
    clock.set(early)
    services.record_times(
        session, by=session.teacher.user, fields={"teacher_in_at": early}
    )
    with pytest.raises(ConflictError) as err:
        revert(session, admin)
    assert err.value.code == "scheduling.not_started"


# ── Locks (§4.2 step 2) ──────────────────────────────────────────────────────


def table(sql):
    return sql.split(" FROM ")[1].split()[0]


def test_a_revert_takes_the_inverses_locks_and_none_of_its_own(sub, admin):
    session = nth(sub, 1)
    services.postpone_session(
        session, by=admin, occurs_on=date(2026, 6, 4), start_time=time(20, 0)
    )
    entry = last(session)
    with CaptureQueriesContext(connection) as ctx:
        services.revert_activity(entry, by=admin)
    locks = [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]
    assert [table(sql) for sql in locks[:2]] == [
        '"scheduling_subscription"',
        '"scheduling_session"',
    ]
    assert all(table(sql) != '"scheduling_sessionactivity"' for sql in locks)
```


- [ ] **Step 2: Run them to see them fail**

Run: `… pytest -q etqan/scheduling/tests/test_activity_revert.py`
Expected: FAIL (`AttributeError: module 'etqan.scheduling.services' has no attribute 'revert_activity'`). Keep the output.

- [ ] **Step 3: Implement `services/revert.py`**

```python
"""Reverting one activity entry (slice B2c §4.2). The inverse service runs as
the person reverting, with the entry's before-values, so every rule — the
payslip lock, the frozen original, the status rules, the postponement window
— applies as for a fresh change (C-5); field values are never written back
directly. `revert_activity` takes no lock of its own: the inverse locks in the
order it always does, and its `track` refuses a field that moved on since the
entry (C-6), so of two reverts of one entry the second sees
`scheduling.changed_since` (Plan 25 D10)."""

from collections.abc import Callable
from dataclasses import dataclass

from django.db import transaction

from etqan.platform import features
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import PermissionDeniedError
from etqan.platform.permissions import codes_of
from etqan.platform.permissions import is_office
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.services import activity
from etqan.scheduling.services import attendance
from etqan.scheduling.services import manual
from etqan.scheduling.services import postpone
from etqan.scheduling.services import rules
from etqan.scheduling.services import supervision
from etqan.scheduling.services import times

Action = SessionActivity.Action
AT_DISPOSAL = Session.Status.AT_DISPOSAL
ATTENDANCE_FIELDS = ("student_attendance", "teacher_attendance")
SUPERVISION_FIELDS = ("supervisor_id", "supervisor_attendance")
NOT_REVERTIBLE = "This change can't be reverted."
# `revert_refusal`'s answers (§4.2 step 1).
REFUSED = "not_revertible"
FORBIDDEN = "forbidden"


@dataclass(frozen=True)
class Reverted:
    session: Session
    entry: SessionActivity


def _before(entry: SessionActivity, field: str):
    return activity.from_json(field, entry.changes[field][0])


def _only(entry: SessionActivity, fields) -> dict:
    """The before-values of exactly those ``fields`` the entry changed."""
    return {field: _before(entry, field) for field in fields if field in entry.changes}


def _before_status(entry: SessionActivity) -> str | None:
    pair = entry.changes.get("status")
    return pair[0] if pair else None


# ── The inverses (§4.1's table) ──────────────────────────────────────────────


def _unmark(session, entry, by) -> None:
    # Only the attendance fields in the entry; the status is derived, never
    # passed, so a teacher-only entry on an at_disposal session passes only
    # the teacher's attendance (B2a A-11).
    attendance.mark_attendance(session, by=by, **_only(entry, ATTENDANCE_FIELDS))


def _uncancel(session, entry, by) -> None:
    from_disposal = _before_status(entry) == AT_DISPOSAL
    attendance.restore_session(session, by=by, to_disposal=from_disposal)


def _unrestore(session, entry, by) -> None:
    reasons = _only(entry, ("cancel_reason", "disposal_reason"))
    if _before_status(entry) == AT_DISPOSAL:
        attendance.place_at_disposal(
            session, by=by, reason=reasons.get("disposal_reason", "")
        )
        return
    attendance.cancel_session(
        session,
        by=by,
        reason=reasons.get("cancel_reason", ""),
        disposal_reason=reasons.get("disposal_reason"),
    )


def _undispose(session, _entry, by) -> None:
    attendance.restore_session(session, by=by)


def _unpay(session, entry, by) -> None:
    manual.set_pays_teacher(
        session, pays_teacher=_before(entry, "pays_teacher"), by=by
    )


def _unsupervise(session, entry, by) -> None:
    supervision.update_session_supervision(
        session, fields=_only(entry, SUPERVISION_FIELDS), by=by
    )


def _untime(session, entry, by) -> None:
    # B2b B-3: a minutes key sent as None counts as sent: not recomputed.
    times.record_times(session, by=by, fields=_only(entry, times.ALL_FIELDS))


def _unpostpone(session, entry, by) -> None:
    # The exact earlier instant (Plan 25 D6); office rules; B2b's move-back
    # rule re-attaches the slot. P4b's `session_moved` propagates.
    postpone.postpone_session(session, by=by, starts_at=_before(entry, "starts_at"))


# ── What each revert also needs (§4.1's last column) ─────────────────────────


def _codes(*extra: str) -> Callable[[SessionActivity], set[str]]:
    def codes(_entry) -> set[str]:
        return {"session.update", *extra}

    return codes


def _supervision_codes(entry: SessionActivity) -> set[str]:
    fields = (f for f in SUPERVISION_FIELDS if f in entry.changes)
    return {"session.update", *(supervision.SESSION_FIELDS[f] for f in fields)}


def _switches(*codes: str) -> Callable[[SessionActivity], set[str]]:
    def switches(_entry) -> set[str]:
        return set(codes)

    return switches


def _disposal_when_from_it(entry: SessionActivity) -> set[str]:
    return {"disposal_status"} if _before_status(entry) == AT_DISPOSAL else set()


def _disposal_when_touched(entry: SessionActivity) -> set[str]:
    touched = "disposal_reason" in entry.changes or _before_status(entry) == AT_DISPOSAL
    return {"disposal_status"} if touched else set()


@dataclass(frozen=True)
class Inverse:
    run: Callable[[Session, SessionActivity, object], None]
    codes: Callable[[SessionActivity], set[str]]
    switches: Callable[[SessionActivity], set[str]]


# The three subscription-wide actions have no inverse (C-8).
INVERSES = {
    Action.ATTENDANCE: Inverse(_unmark, _codes("attendance.update"), _switches()),
    Action.CANCEL: Inverse(_uncancel, _codes(), _disposal_when_from_it),
    Action.RESTORE: Inverse(_unrestore, _codes(), _disposal_when_touched),
    Action.DISPOSAL: Inverse(_undispose, _codes(), _switches("disposal_status")),
    Action.PAYS_TEACHER: Inverse(_unpay, _codes(), _switches("extra_sessions")),
    Action.SUPERVISION: Inverse(
        _unsupervise, _supervision_codes, _switches("supervision")
    ),
    Action.SUPERVISOR_ATTENDANCE: Inverse(
        _unsupervise, _codes("attendance.update"), _switches("supervision")
    ),
    Action.TIMES: Inverse(
        _untime, _codes("attendance.update"), _switches("session_times")
    ),
    Action.POSTPONE: Inverse(_unpostpone, _codes(), _switches("postponement")),
}


def revert_refusal(entry: SessionActivity, by) -> str | None:
    """§4.2 step 1, in its order, without raising: no inverse or a switch
    off (the log's, the action's, or a changed field's, C-10) is
    `not_revertible`; a non-office ``by`` or a missing code is `forbidden`."""
    inverse = INVERSES.get(entry.action)
    if inverse is None or not features.enabled(activity.FEATURE):
        return REFUSED
    fields = {
        activity.FIELD_FEATURES[field]
        for field in entry.changes
        if field in activity.FIELD_FEATURES
    }
    if not all(features.enabled(code) for code in inverse.switches(entry) | fields):
        return REFUSED
    if not is_office(by) or not inverse.codes(entry) <= codes_of(by):
        return FORBIDDEN
    return None


@transaction.atomic
def revert_activity(entry: SessionActivity, *, by) -> Reverted:
    """§4.2: refusals first (409 `scheduling.not_revertible`, 403), then the
    inverse as ``by`` inside `reverting(entry)`; its own `track` refuses a
    field that moved on (409 `scheduling.changed_since`) and writes the new
    entry, which points at ``entry``."""
    refused = revert_refusal(entry, by)
    if refused == FORBIDDEN:
        raise PermissionDeniedError("revert this change")
    if refused is not None:
        raise ConflictError(NOT_REVERTIBLE, code="scheduling.not_revertible")
    with activity.reverting(entry) as state:
        INVERSES[entry.action].run(Session(pk=entry.session_id), entry, by)
    if state.written is None:  # pragma: no cover -- step 2 makes it change
        raise ConflictError(activity.CHANGED_SINCE, code="scheduling.changed_since")
    return Reverted(rules.sessions_queryset().get(pk=entry.session_id), state.written)
```

Export from `services/__init__.py` (one import per line, `__all__` alphabetical):

```python
from etqan.scheduling.services.revert import Reverted
from etqan.scheduling.services.revert import revert_activity
from etqan.scheduling.services.revert import revert_refusal
```

- [ ] **Step 4: Run the tests**

Run: `… pytest -q etqan/scheduling/tests/test_activity_revert.py` → PASS; then `… pytest -q etqan/scheduling` → PASS. Ruff, format, lint-imports clean.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/scheduling/services/revert.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_activity_revert.py
git -C backend commit -m "feat(scheduling): revert an activity entry through its inverse service (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Reading the log (`services/activity_feed.py`)

**Files:**
- Create: `backend/etqan/scheduling/services/activity_feed.py`
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Test: `backend/etqan/scheduling/tests/test_activity_feed.py`

**Interfaces:**
- Consumes: Task 2 (`LOGGED_FIELDS`, `visible_fields`, `snapshot`), Task 6 (`revert_refusal`), `identity_services.get_users(ids) -> dict[int, User]`, `identity_services.teacher_profiles_by_id(ids) -> dict[int, TeacherProfile]`.
- Produces (exported):
  - `ShownEntry` — frozen dataclass `(entry: SessionActivity, changes: list[dict], can_revert: bool, reverted_by: list[int])`; each change is `{"field", "before", "after"}`, visible fields only, in `LOGGED_FIELDS` order; `supervisor_id` / `teacher_id` / `subscription_id` values become `{"id", "name"}` (name `None` when the record is gone, always `None` for a subscription, plan D8).
  - `ActivityFeed` — frozen dataclass `(session: Session, entries: list[ShownEntry], truncated: bool)`.
  - `session_activity(session: Session, viewer) -> ActivityFeed` — ``session`` from `sessions_queryset()`; newest 200 visible entries; `MAX_ENTRIES = 200`.
  - `describe_activity(entries: list[SessionActivity], session: Session, viewer) -> list[ShownEntry]`.
  - `activity_of(session) -> QuerySet[SessionActivity]` (newest first), `activity_by(user) -> QuerySet[SessionActivity]`, `get_activity_entry(session, entry_id: int) -> SessionActivity` (`NotFoundError` for another session's).

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2c §4.3: reading a session's log."""

from datetime import timedelta

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.access import services as access_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
CANCEL = {"status": ["scheduled", "cancelled"]}


def supervisor(name):
    role = access_services.create_role(
        name_en=f"Watch {name}",
        name_ar=f"مراقبة {name}",
        permissions=["session.supervise"],
        by=None,
    )
    user = identity_services.create_person(
        "staff", full_name=name, email=f"{name.lower()}@x.test"
    )
    user.staff_roles.set([role])
    return user


@pytest.fixture
def on(set_features):
    set_features(activity_log=True, supervision=True)


@pytest.fixture
def sub(subscribe, on):
    return subscribe(slots=two_slots())


@pytest.fixture
def started(sub, clock):
    session = Session.objects.filter(subscription=sub).order_by("starts_at").first()
    clock.set(session.starts_at + timedelta(minutes=5))
    return session


@pytest.fixture
def admin():
    return make_admin()


def feed(session, viewer):
    row = services.sessions_queryset().get(pk=session.pk)
    return services.session_activity(row, viewer)


def entry(session, changes=None, action="cancel", **fields):
    fields.setdefault("actor_kind", "system")
    return SessionActivity.objects.create(
        session=session, action=action, changes=changes or CANCEL, **fields
    )


def test_newest_first(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    services.restore_session(started, by=admin)
    assert [s.entry.action for s in feed(started, admin).entries] == [
        "restore",
        "cancel",
    ]


def test_the_newest_200_are_read_and_truncated_says_so(started, admin):
    SessionActivity.objects.bulk_create(
        [
            SessionActivity(
                session=started, actor_kind="system", action="cancel", changes=CANCEL
            )
            for _ in range(201)
        ]
    )
    read = feed(started, admin)
    oldest = SessionActivity.objects.filter(session=started).order_by("id").first()
    assert (len(read.entries), read.truncated) == (200, True)
    assert oldest.pk not in {s.entry.pk for s in read.entries}


def test_200_exactly_is_not_truncated(started, admin):
    SessionActivity.objects.bulk_create(
        [
            SessionActivity(
                session=started, actor_kind="system", action="cancel", changes=CANCEL
            )
            for _ in range(200)
        ]
    )
    assert feed(started, admin).truncated is False


def test_hidden_fields_are_left_out_and_block_the_revert(started, admin, set_features):
    entry(started, {"supervisor_id": [None, admin.pk]}, action="supervision")
    mixed = entry(
        started,
        {"status": ["cancelled", "scheduled"], "supervisor_id": [admin.pk, None]},
        action="restore",
    )
    set_features(supervision=False)
    read = feed(started, admin)
    assert [s.entry.pk for s in read.entries] == [mixed.pk]
    (shown,) = read.entries
    assert [c["field"] for c in shown.changes] == ["status"]
    assert shown.can_revert is False
    set_features(supervision=True)
    again = feed(started, admin)
    assert len(again.entries) == 2
    assert again.entries[0].can_revert is True


def test_ids_resolve_to_names_and_a_missing_record_to_its_id(started, admin, sub):
    sara = supervisor("Sara")
    entry(
        started,
        {
            "supervisor_id": [None, sara.pk],
            "teacher_id": [started.teacher_id, 999999],
            "subscription_id": [sub.pk, None],
        },
        action="teacher_moved",
    )
    (shown,) = feed(started, admin).entries
    by_field = {c["field"]: c for c in shown.changes}
    assert [c["field"] for c in shown.changes] == [
        "supervisor_id",
        "teacher_id",
        "subscription_id",
    ]
    assert by_field["supervisor_id"]["after"] == {"id": sara.pk, "name": "Sara"}
    assert by_field["teacher_id"]["before"] == {"id": started.teacher_id, "name": "Bilal"}
    assert by_field["teacher_id"]["after"] == {"id": 999999, "name": None}
    assert by_field["subscription_id"]["before"] == {"id": sub.pk, "name": None}
    assert by_field["subscription_id"]["after"] is None
    assert shown.can_revert is False  # a subscription-wide move (C-8)


def test_can_revert_follows_the_rules(started, admin, staff_for):
    services.mark_attendance(started, by=admin, student_attendance="present")
    assert feed(started, admin).entries[0].can_revert is True
    clerk = staff_for("session.view", "session.update").user
    assert feed(started, clerk).entries[0].can_revert is False
    services.mark_attendance(started, by=admin, student_attendance="absent")
    assert [s.can_revert for s in feed(started, admin).entries] == [True, False]


def test_reverts_and_reverted_by_link_both_ways(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    cancel = SessionActivity.objects.get(session=started)
    result = services.revert_activity(cancel, by=admin)
    newest, oldest = feed(started, admin).entries
    assert newest.entry.reverts_id == cancel.pk
    assert oldest.reverted_by == [result.entry.pk]


def test_an_entry_of_another_session_is_not_found(sub, started):
    other = Session.objects.filter(subscription=sub).exclude(pk=started.pk).first()
    mine = entry(started)
    assert services.get_activity_entry(started, mine.pk) == mine
    with pytest.raises(NotFoundError):
        services.get_activity_entry(other, mine.pk)


def test_activity_by_lists_a_persons_entries(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    services.restore_session(started)
    assert [e.action for e in services.activity_by(admin)] == ["cancel"]


def test_the_read_costs_the_same_for_1_and_5_entries(sub, admin):
    one, five = Session.objects.filter(subscription=sub).order_by("starts_at")[:2]
    sara = supervisor("Sara")
    for session, size in ((one, 1), (five, 5)):
        for n in range(size):
            entry(
                session,
                {
                    "supervisor_id": [None, sara.pk],
                    "teacher_id": [session.teacher_id, 900000 + n],
                },
                action="teacher_moved",
                actor=admin,
                actor_kind="user",
            )

    def queries(session):
        row = services.sessions_queryset().get(pk=session.pk)
        with CaptureQueriesContext(connection) as ctx:
            services.session_activity(row, admin)
        return len(ctx.captured_queries)

    queries(one)  # warms the admin's codes
    assert queries(one) == queries(five)
```

- [ ] **Step 2: Run them to see them fail**

Run: `… pytest -q etqan/scheduling/tests/test_activity_feed.py`
Expected: FAIL (`AttributeError: … has no attribute 'session_activity'`). Keep the output.

- [ ] **Step 3: Implement `services/activity_feed.py`**

```python
"""Reading a session's activity log (slice B2c §4.3): the newest 200 entries
with a visible field, newest first, ids resolved to names with one query per
related model for the whole page, and whether the viewer may revert each."""

from dataclasses import dataclass

from django.db.models import Prefetch
from django.db.models import QuerySet

from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.services import activity
from etqan.scheduling.services.revert import revert_refusal

MAX_ENTRIES = 200
# Logged ids and what they name: a user (supervisor), a teacher profile, a
# subscription (no code column: its id is shown, Plan 25 D8).
REFERENCES = ("supervisor_id", "teacher_id", "subscription_id")


@dataclass(frozen=True)
class ShownEntry:
    entry: SessionActivity
    changes: list[dict]
    can_revert: bool
    reverted_by: list[int]


@dataclass(frozen=True)
class ActivityFeed:
    session: Session
    entries: list[ShownEntry]
    truncated: bool


def activity_of(session: Session) -> QuerySet[SessionActivity]:
    """The session's entries, newest first."""
    return SessionActivity.objects.filter(session_id=session.pk).order_by(
        "-created_at", "-id"
    )


def activity_by(user) -> QuerySet[SessionActivity]:
    """Every entry ``user`` wrote in this academy (the seeds' marker)."""
    return SessionActivity.objects.filter(actor=user).order_by("id")


def get_activity_entry(session: Session, entry_id: int) -> SessionActivity:
    """One of the session's entries; another session's is a 404 (§6)."""
    entry = (
        SessionActivity.objects.select_related("actor")
        .filter(session_id=session.pk, pk=entry_id)
        .first()
    )
    if entry is None:
        raise NotFoundError("Activity entry", entry_id)
    return entry


def session_activity(session: Session, viewer) -> ActivityFeed:
    """§4.3. ``session`` is read from `sessions_queryset()`. An entry whose
    every field is switched off is left out before the cap (Plan 25 D9)."""
    rows = list(
        activity_of(session)
        .filter(changes__has_any_keys=sorted(activity.visible_fields()))
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


def describe_activity(entries, session: Session, viewer) -> list[ShownEntry]:
    """Each entry as ``viewer`` reads it; ``session`` is the row as it is
    now. `can_revert`: §4.2 step 1 passes for the viewer and every field
    still holds its after-value; the inverse's other rules are checked only
    when the revert is sent."""
    shown = activity.visible_fields()
    now = activity.snapshot(session)
    names = _names(entries)
    return [
        ShownEntry(
            entry=entry,
            changes=_changes(entry, shown, names),
            can_revert=revert_refusal(entry, viewer) is None
            and _holds_after(entry, now),
            reverted_by=[later.pk for later in entry.reverted_by.all()],
        )
        for entry in entries
    ]


def _changes(entry: SessionActivity, shown, names) -> list[dict]:
    rows = []
    for field in activity.LOGGED_FIELDS:
        if field in entry.changes and field in shown:
            before, after = entry.changes[field]
            rows.append(
                {
                    "field": field,
                    "before": _value(field, before, names),
                    "after": _value(field, after, names),
                }
            )
    return rows


def _holds_after(entry: SessionActivity, now: dict) -> bool:
    return all(now[field] == after for field, (_before, after) in entry.changes.items())


def _ids(entries, field: str) -> set[int]:
    return {
        value
        for entry in entries
        for value in entry.changes.get(field, ())
        if value is not None
    }


def _names(entries) -> dict[str, dict[int, str]]:
    """One query per related model for the whole page (§4.3)."""
    users = _ids(entries, "supervisor_id")
    teachers = _ids(entries, "teacher_id")
    user_names = (
        {pk: user.full_name for pk, user in identity_services.get_users(users).items()}
        if users
        else {}
    )
    teacher_names = (
        {
            pk: profile.user.full_name
            for pk, profile in identity_services.teacher_profiles_by_id(teachers).items()
        }
        if teachers
        else {}
    )
    return {"supervisor_id": user_names, "teacher_id": teacher_names, "subscription_id": {}}


def _value(field: str, value, names: dict):
    if value is None or field not in REFERENCES:
        return value
    return {"id": value, "name": names[field].get(value)}
```

Export from `services/__init__.py` (one per line, `__all__` alphabetical):

```python
from etqan.scheduling.services.activity_feed import ActivityFeed
from etqan.scheduling.services.activity_feed import ShownEntry
from etqan.scheduling.services.activity_feed import activity_by
from etqan.scheduling.services.activity_feed import activity_of
from etqan.scheduling.services.activity_feed import describe_activity
from etqan.scheduling.services.activity_feed import get_activity_entry
from etqan.scheduling.services.activity_feed import session_activity
```

- [ ] **Step 4: Run the tests**

Run: `… pytest -q etqan/scheduling/tests/test_activity_feed.py` → PASS. Ruff, format, lint-imports clean.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/scheduling/services/activity_feed.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_activity_feed.py
git -C backend commit -m "feat(scheduling): read a session's activity with names and can_revert (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The API — routes, payload, route table

**Files:**
- Create: `backend/etqan/scheduling/api/activity_views.py`
- Modify: `backend/etqan/scheduling/api/payloads.py` (`_ref`, `activity_entry`, `activity_feed`), `backend/etqan/scheduling/api/urls.py`
- Modify: `backend/etqan/access/tests/test_routes.py` (`ROUTES`, `FEATURES`, `FEATURE_WORDS`, under the B2 lines)
- Test: `backend/etqan/scheduling/tests/test_api_activity.py`

**Interfaces:**
- Consumes: Task 6 (`revert_activity`, `Reverted`), Task 7 (`session_activity`, `describe_activity`, `get_activity_entry`, `ShownEntry`, `ActivityFeed`), `session_views.session_or_404`, `session_views.session_payload`.
- Produces:
  - `GET /api/v1/sessions/<id>/activity/` → `{"results": [entry…], "truncated": bool, "created": {"at", "by": {"id","name"} | null, "kind", "generated"}}`.
  - `POST /api/v1/sessions/<id>/activity/<entry_id>/revert/` → `200 {"session": <session payload>, "entry": entry}`.
  - Entry payload: `{"id", "action", "actor": {"id","name"} | null, "actor_kind", "created_at", "changes": [{"field","before","after"}], "reverts": int | null, "reverted_by": [int], "can_revert": bool}`.
  - `OfficeOr404` permission (plan D13).

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2c §5–§6: the activity routes, their payload and who reaches them."""

from datetime import timedelta

import pytest
from django.db import connection
from django.db.models import Max
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.identity import services as identity_services
from etqan.platform.permissions import FEATURE_OFF
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots
from etqan.scheduling.tests.conftest import until_pk_exceeds

pytestmark = pytest.mark.django_db
URL = "/api/v1/sessions/"


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


@pytest.fixture
def on(set_features):
    set_features(activity_log=True, parents=True)


@pytest.fixture
def sub(subscribe, on):
    return subscribe(slots=two_slots())


@pytest.fixture
def started(sub, clock):
    session = Session.objects.filter(subscription=sub).order_by("starts_at").first()
    clock.set(session.starts_at + timedelta(minutes=5))
    return session


@pytest.fixture
def admin():
    return make_admin()


def read(client, session):
    return client.get(f"{URL}{session.pk}/activity/")


def revert_path(session, entry):
    return f"{URL}{session.pk}/activity/{entry.pk}/revert/"


def parent_of(session):
    parent = identity_services.create_person("parent", full_name="Omar")
    identity_services.link_guardian(parent, session.student.user)
    return parent


# ── Reading ──────────────────────────────────────────────────────────────────


def test_the_office_reads_the_log_newest_first_with_the_creation_line(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    services.restore_session(started, by=admin)
    body = read(as_user(admin), started).json()
    assert [e["action"] for e in body["results"]] == ["restore", "cancel"]
    assert body["truncated"] is False
    created = body["created"]
    assert (created["by"], created["kind"], created["generated"]) == (
        None,
        "regular",
        True,
    )
    assert created["at"]
    cancel = body["results"][1]
    assert cancel["actor"] == {"id": admin.pk, "name": "Amina"}
    assert cancel["actor_kind"] == "user"
    assert cancel["created_at"]
    assert cancel["changes"] == [
        {"field": "status", "before": "scheduled", "after": "cancelled"},
        {"field": "cancel_reason", "before": "", "after": "Eid"},
    ]
    assert (cancel["reverts"], cancel["reverted_by"]) == (None, [])
    assert cancel["can_revert"] is False  # the restore moved its fields on
    assert body["results"][0]["can_revert"] is True


def test_a_hand_added_session_names_who_added_it(sub, admin):
    from datetime import date  # noqa: PLC0415

    hand = hand_session(sub, occurs_on=date(2026, 6, 5), created_by=admin)
    created = read(as_user(admin), hand).json()["created"]
    assert (created["by"], created["generated"]) == (
        {"id": admin.pk, "name": "Amina"},
        False,
    )


def test_an_entry_whose_account_is_gone_is_not_the_system(started, admin):
    SessionActivity.objects.create(
        session=started,
        actor=None,
        actor_kind="user",
        action="cancel",
        changes={"status": ["scheduled", "cancelled"]},
    )
    (entry,) = read(as_user(admin), started).json()["results"]
    assert (entry["actor"], entry["actor_kind"]) == (None, "user")


def test_reading_costs_the_same_for_1_and_5_entries(sub, admin):
    one, five = Session.objects.filter(subscription=sub).order_by("starts_at")[:2]
    for session, size in ((one, 1), (five, 5)):
        SessionActivity.objects.bulk_create(
            [
                SessionActivity(
                    session=session,
                    actor=admin,
                    actor_kind="user",
                    action="teacher_moved",
                    changes={
                        "supervisor_id": [None, admin.pk],
                        "teacher_id": [session.teacher_id, 900000 + n],
                    },
                )
                for n in range(size)
            ]
        )
    client = as_user(admin)

    def queries(session):
        with CaptureQueriesContext(connection) as ctx:
            assert read(client, session).status_code == 200
        return len(ctx.captured_queries)

    assert queries(one) == queries(five)


# ── Reverting ────────────────────────────────────────────────────────────────


def test_reverting_answers_the_session_and_the_new_entry(started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    entry = SessionActivity.objects.get(session=started)
    response = as_user(admin).post(revert_path(started, entry))
    assert response.status_code == 200
    body = response.json()
    assert body["session"]["status"] == "scheduled"
    assert (body["entry"]["action"], body["entry"]["reverts"]) == ("restore", entry.pk)
    assert body["entry"]["actor"] == {"id": admin.pk, "name": "Amina"}
    assert body["entry"]["can_revert"] is True


def test_another_sessions_entry_is_404(sub, started, admin):
    services.cancel_session(started, by=admin, reason="Eid")
    entry = SessionActivity.objects.get(session=started)
    other = Session.objects.filter(subscription=sub).exclude(pk=started.pk).first()
    assert as_user(admin).post(revert_path(other, entry)).status_code == 404


def test_refusals_reach_the_api(started, admin, staff_for):
    services.mark_attendance(started, by=admin, student_attendance="present")
    entry = SessionActivity.objects.get(session=started)
    assert staff_for("session.update").post(revert_path(started, entry)).status_code == 403
    services.mark_attendance(started, by=admin, student_attendance="absent")
    moved_on = as_user(admin).post(revert_path(started, entry))
    assert (moved_on.status_code, moved_on.json()["code"]) == (
        409,
        "scheduling.changed_since",
    )
    wide = SessionActivity.objects.create(
        session=started,
        actor_kind="system",
        action="teacher_moved",
        changes={"teacher_id": [1, started.teacher_id]},
    )
    refused = as_user(admin).post(revert_path(started, wide))
    assert (refused.status_code, refused.json()["code"]) == (
        409,
        "scheduling.not_revertible",
    )


# ── Who reaches it (§5) ──────────────────────────────────────────────────────


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_teachers_students_and_parents_never_see_it(started, admin, role):
    services.cancel_session(started, by=admin, reason="Eid")
    entry = SessionActivity.objects.get(session=started)
    user = {
        "teacher": started.teacher.user,
        "student": started.student.user,
        "parent": parent_of(started),
    }[role]
    client = as_user(user)
    assert read(client, started).status_code == 404
    assert client.post(revert_path(started, entry)).status_code == 404


def test_staff_need_session_view_to_read(started, staff_for):
    assert read(staff_for("session.view_any"), started).status_code == 403
    assert read(staff_for("session.view"), started).status_code == 200


def test_switched_off_both_routes_404_after_the_permission_check(
    started, admin, set_features, staff_for
):
    services.cancel_session(started, by=admin, reason="Eid")
    entry = SessionActivity.objects.get(session=started)
    set_features(activity_log=False)
    office = as_user(admin)
    for response in (read(office, started), office.post(revert_path(started, entry))):
        assert (response.status_code, response.json()) == (404, {"detail": FEATURE_OFF})
    assert read(staff_for("session.view_any"), started).status_code == 403
    assert read(as_user(started.teacher.user), started).status_code == 404


def test_turning_it_back_on_shows_the_earlier_entries(started, admin, set_features):
    services.cancel_session(started, by=admin, reason="Eid")
    set_features(activity_log=False)
    services.restore_session(started, by=admin)  # not logged while off
    set_features(activity_log=True)
    actions = [e["action"] for e in read(as_user(admin), started).json()["results"]]
    assert actions == ["cancel"]


def test_another_academys_session_is_404(started, admin, tenants, set_features):
    ceiling = Session.objects.aggregate(m=Max("pk"))["m"]
    with tenant_context(tenants.other):
        set_features(academy=tenants.other, activity_log=True)
        other = build_world()
        sub = until_pk_exceeds(
            Session, ceiling, lambda: subscription_for(other, slots=two_slots())
        )
        theirs = Session.objects.filter(subscription=sub).order_by("pk").first()
    assert theirs.pk > ceiling
    assert read(as_user(admin), theirs).status_code == 404
```

(Move the `date` import in `test_a_hand_added_session_names_who_added_it` to the module's imports if ruff's import rules prefer it; the function-level import is only to keep the snippet self-contained.)

- [ ] **Step 2: Run them to see them fail**

Run: `… pytest -q etqan/scheduling/tests/test_api_activity.py`
Expected: FAIL (404 for every route: they don't exist yet). Keep the output.

- [ ] **Step 3: Payloads** (`api/payloads.py`, after `report_payload`)

```python
def _ref(user) -> dict | None:
    """Slice B2c §4.3 (Plan 25 D8): a person the log names."""
    return None if user is None else {"id": user.pk, "name": user.full_name}


def activity_entry(shown: services.ShownEntry) -> dict:
    """Slice B2c §4.3: one entry as the office reads it."""
    entry = shown.entry
    return {
        "id": entry.pk,
        "action": entry.action,
        "actor": _ref(entry.actor),
        "actor_kind": entry.actor_kind,
        "created_at": entry.created_at,
        "changes": shown.changes,
        "reverts": entry.reverts_id,
        "reverted_by": shown.reverted_by,
        "can_revert": shown.can_revert,
    }


def activity_feed(feed: services.ActivityFeed) -> dict:
    """§6: the entries, whether older ones exist, and the creation line built
    from the session row itself (C-3: creation is not a stored entry)."""
    session = feed.session
    return {
        "results": [activity_entry(shown) for shown in feed.entries],
        "truncated": feed.truncated,
        "created": {
            "at": session.created_at,
            "by": _ref(session.created_by),
            "kind": session.kind,
            "generated": session.generated,
        },
    }
```

- [ ] **Step 4: Views** (`api/activity_views.py`)

```python
"""Slice B2c §5–§6: a session's activity log and reverting one entry. The
office only: everyone else gets 404, before the code check (§5)."""

from rest_framework.exceptions import NotFound
from rest_framework.permissions import BasePermission
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.platform.permissions import is_office
from etqan.platform.permissions import role_of
from etqan.scheduling import services
from etqan.scheduling.api import payloads
from etqan.scheduling.api.session_views import session_or_404
from etqan.scheduling.api.session_views import session_payload


class OfficeOr404(BasePermission):
    """Plan 25 D13: a teacher, student or parent never learns the log exists
    (404, as the report views answer); an anonymous caller gets the usual
    refusal. List it before `HasCode`, which would answer 403."""

    def has_permission(self, request, view):
        if role_of(request.user) is None:
            return False
        if not is_office(request.user):
            raise NotFound
        return True


class SessionActivityView(APIView):
    permission_classes = [OfficeOr404, HasCode, FeatureOn]
    permission_codes = {"GET": "session.view"}
    feature = "activity_log"

    def get(self, request, pk):
        session = session_or_404(request, pk)
        feed = services.session_activity(session, request.user)
        return Response(payloads.activity_feed(feed))


class ActivityRevertView(APIView):
    """§4.2: `session.update` here; the inverse's own codes in the service."""

    permission_classes = [OfficeOr404, HasCode, FeatureOn]
    permission_codes = {"POST": "session.update"}
    feature = "activity_log"

    def post(self, request, pk, entry_id):
        session = session_or_404(request, pk)
        entry = services.get_activity_entry(session, entry_id)
        result = services.revert_activity(entry, by=request.user)
        (shown,) = services.describe_activity(
            [result.entry], result.session, request.user
        )
        return Response(
            {
                "session": session_payload(request, pk),
                "entry": payloads.activity_entry(shown),
            }
        )
```

`api/urls.py`: import `activity_views` next to the other view modules and add after B2b's session routes:

```python
    # Slice B2c (spec §6).
    path(
        "sessions/<int:pk>/activity/",
        activity_views.SessionActivityView.as_view(),
        name="session-activity",
    ),
    path(
        "sessions/<int:pk>/activity/<int:entry_id>/revert/",
        activity_views.ActivityRevertView.as_view(),
        name="session-activity-revert",
    ),
```

- [ ] **Step 5: Route table** (`access/tests/test_routes.py`)

In `ROUTES`, after B2b's two lines:

```python
    # Slice B2c.
    ("GET", f"/api/v1/sessions/{N}/activity/", "session.view"),
    ("POST", f"/api/v1/sessions/{N}/activity/{N}/revert/", "session.update"),
```

In `FEATURES`, after B2b's two lines:

```python
    # Slice B2c.
    ("GET", f"/api/v1/sessions/{N}/activity/"): "activity_log",
    ("POST", f"/api/v1/sessions/{N}/activity/{N}/revert/"): "activity_log",
```

In `FEATURE_WORDS`, after B2b's two lines:

```python
    # Slice B2c.
    "/activity/": "activity_log",
```

- [ ] **Step 6: Run the API tests, the route table and the whole backend once**

Run: `… pytest -q etqan/scheduling/tests/test_api_activity.py etqan/access` → PASS. Then the full verify: `… pytest -q --cov=etqan` (≥ 80 %), `… ruff check .`, `… ruff format --check .`, `… lint-imports`.

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/scheduling/api/activity_views.py etqan/scheduling/api/payloads.py etqan/scheduling/api/urls.py etqan/access/tests/test_routes.py etqan/scheduling/tests/test_api_activity.py
git -C backend commit -m "feat(scheduling): activity log and revert routes, office only (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Demo seeds

**Files:**
- Modify: `backend/etqan/tenants/seeds/b2.py`, `backend/etqan/tenants/management/commands/seed_dev.py` (B2 block only)
- Test: `backend/etqan/tenants/tests/test_seed_b2.py` (append)

**Interfaces:**
- Consumes: `scheduling_services.mark_attendance`, `cancel_session`, `activity_of`, `activity_by`, `revert_activity`, `sessions_queryset`; `identity_services.get_user_by_email`.
- Produces: `b2.seed_activity(subdomain: str) -> None`; `ACTIVITY = {"demo": {...}}`.

- [ ] **Step 1: Failing test** (append to `test_seed_b2.py`; add `from etqan.identity import services as identity_services` to its imports)

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_demo_gets_an_admin_change_and_a_reverted_cancel_once():
    """Slice B2c §8 (Plan 25 D12)."""
    call_command("seed_dev")
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        assert features.enabled("activity_log")
        admin = identity_services.get_user_by_email("admin@demo.test")
        mine = list(scheduling_services.activity_by(admin))
        assert [e.action for e in mine] == ["attendance", "cancel", "restore"]
        assert len({e.session_id for e in mine}) == 1
        assert mine[2].reverts_id == mine[1].pk
        session = scheduling_services.sessions_queryset().get(pk=mine[0].session_id)
        assert session.status == "completed"
    with tenant_context(other):
        assert not features.enabled("activity_log")
        admin = identity_services.get_user_by_email("admin@other.test")
        assert not scheduling_services.activity_by(admin).exists()
```

- [ ] **Step 2: Run to see it fail**

Run: `… pytest -q etqan/tenants/tests/test_seed_b2.py -k reverted_cancel`
Expected: FAIL (`assert [] == ['attendance', 'cancel', 'restore']`). Keep the output.

- [ ] **Step 3: Implement** in `seeds/b2.py` (add `from django.db import transaction`, `from etqan.platform.exceptions import NotFoundError`, `from etqan.platform.exceptions import PermissionDeniedError` to the imports):

```python
# Slice B2c (spec §8): in demo, the demo admin changes the student's
# attendance on the latest unpaid completed session, cancels it, and reverts
# the cancel through `revert_activity`. Other academies get nothing.
ACTIVITY = {
    "demo": {"admin": "admin@demo.test", "reason": "Seeded: cancelled by mistake"}
}


def seed_activity(subdomain: str) -> None:
    """Idempotent by author (Plan 25 D12): seed_attendance's teacher marks
    already log an entry on every past session, so the step is skipped once
    the demo admin has any entry. The three steps run in one transaction: a
    refused step leaves nothing and is retried on the next run."""
    spec = ACTIVITY.get(subdomain)
    if spec is None:
        return
    try:
        admin = identity_services.get_user_by_email(spec["admin"])
    except NotFoundError:
        print("skip: activity — the demo admin was not found")  # noqa: T201
        return
    if scheduling_services.activity_by(admin).exists():
        return
    session = (
        scheduling_services.sessions_queryset()
        .filter(status="completed", payroll_locked=False, compensated=False)
        .order_by("-starts_at", "-id")
        .first()
    )
    if session is None:
        print("skip: activity — no unpaid completed session")  # noqa: T201
        return
    flipped = "absent" if session.student_attendance == "present" else "present"
    try:
        with transaction.atomic():
            scheduling_services.mark_attendance(
                session, by=admin, student_attendance=flipped
            )
            scheduling_services.cancel_session(
                session, by=admin, reason=spec["reason"]
            )
            cancel = (
                scheduling_services.activity_of(session).filter(action="cancel").first()
            )
            if cancel is None:
                print("skip: activity — the log is off")  # noqa: T201
                return
            scheduling_services.revert_activity(cancel, by=admin)
    except (ValidationError, ConflictError, PermissionDeniedError) as exc:
        print(f"skip: activity on session {session.pk} — {exc}")  # noqa: T201
```

(A `return` inside `transaction.atomic()` commits the two writes made so far only when the log is off, which demo never is; that branch exists so a misconfigured academy does not crash the seed.)

In `seed_dev.py`'s B2 block, after `b2.seed_times_postponement(subdomain)`:

```python
        b2.seed_activity(subdomain)
```

- [ ] **Step 4: Run** `… pytest -q etqan/tenants/tests/test_seed_b2.py etqan/tenants/tests/test_seed_dev.py` → PASS; then on this stream: `just _stack-manage migrate_schemas` and `just _stack-manage seed_dev` twice (no errors, no duplicate admin entries). Ruff, format, lint-imports clean.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/tenants/seeds/b2.py etqan/tenants/management/commands/seed_dev.py etqan/tenants/tests/test_seed_b2.py
git -C backend commit -m "feat(seeds): an admin change and a reverted cancel in demo's activity log (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Dashboard foundations — types, API, query, strings, the format helpers

**Files:**
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode` + `"activity_log"` right after B2b's `"postponement"`, before the `// Phase B3` marker)
- Modify: `dashboard/src/features/scheduling/schemas.ts`, `api.ts` (+ `api.test.ts`), `queries.ts`
- Create: `dashboard/src/features/scheduling/activityFormat.ts` (+ `activityFormat.test.ts`)
- Create: `dashboard/src/locales/en/sessionActivity.json`, `dashboard/src/locales/ar/sessionActivity.json`
- Modify: `dashboard/src/locales/{en,ar}/errors.json` (`scheduling.changed_since`, `scheduling.not_revertible`)
- Modify: `dashboard/src/test/scheduling-fixtures.ts` (`activityEntry`, `activityLog`)

**Interfaces:**
- Consumes: Task 8's payloads (`entry`: `{id, action, actor: {id, name} | null, actor_kind, created_at, changes: [{field, before, after}], reverts, reverted_by, can_revert}`; feed: `{results, truncated, created: {at, by: {id, name} | null, kind, generated}}`; revert: `{session, entry}`).
- Produces:
  - `schemas.ts`: `ACTIVITY_ACTIONS` (the twelve backend actions, as a const tuple) and `ActivityAction`; `ACTIVITY_FIELDS` (the seventeen `LOGGED_FIELDS`, in their order) and `ActivityField`; `ActivityPerson = { id: number; name: string }`; `ActivityRef = { id: number; name: string | null }` (a supervisor, teacher or subscription value, plan D8); `ActivityValue = string | number | boolean | null | ActivityRef`; `ActivityChange = { field: ActivityField; before: ActivityValue; after: ActivityValue }`; `ActivityEntry` (the payload above, `actor_kind: "user" | "system"`); `ActivityCreated = { at: string; by: ActivityPerson | null; kind: SessionKind; generated: boolean }`; `ActivityLog = { results: ActivityEntry[]; truncated: boolean; created: ActivityCreated }`; `RevertedActivity = { session: Session; entry: ActivityEntry }`.
  - `schedulingApi.activity(id: number): Promise<ActivityLog>` (`GET sessions/<id>/activity/`); `schedulingApi.revertActivity({ id, entryId }): Promise<RevertedActivity>` (`POST sessions/<id>/activity/<entryId>/revert/`).
  - `useSessionActivity(id: number, enabled: boolean)` — key `[...schedulingKey, "activity", id]`, so every scheduling write (a revert, an attendance mark) reloads it (plan D14).
  - `activityFormat.ts`: `FormatContext = { t: TFunction; language: string; academyZone: string; studentZone: string }`; `activityValue(field, value, ctx): string`; `activityWhen(iso, ctx): string`; `activityActor(entry, ctx): string`; `activityAction(action, ctx): string`; `createdLine(created, ctx): string`; `useActivityFormat(academyZone, studentZone): FormatContext`.
  - i18n `sessionActivity.*` (below).

- [ ] **Step 1: Write the failing tests**

`activityFormat.test.ts` (pure functions, fixed `t` per language, so no component is rendered):

```ts
import { describe, expect, it } from "vitest";
import i18n from "@/lib/i18n";
import { activityEntry } from "@/test/scheduling-fixtures";
import {
	activityAction,
	activityActor,
	activityValue,
	activityWhen,
	createdLine,
	type FormatContext,
} from "./activityFormat";
import { ACTIVITY_ACTIONS, ACTIVITY_FIELDS } from "./schemas";

const ctx = (language = "en", studentZone = "Asia/Riyadh"): FormatContext => ({
	t: i18n.getFixedT(language),
	language,
	academyZone: "UTC",
	studentZone,
});

describe("activityValue", () => {
	it("shows an empty value as a dash", () => {
		expect(activityValue("cancel_reason", "", ctx())).toBe("—");
		expect(activityValue("actual_minutes", null, ctx())).toBe("—");
	});

	it("translates statuses, attendance and yes / no", () => {
		expect(activityValue("status", "at_disposal", ctx())).toBe(
			"At the administration's disposal",
		);
		expect(activityValue("student_attendance", "not_set", ctx())).toBe("Not set");
		expect(activityValue("supervisor_attendance", "present", ctx())).toBe("Present");
		expect(activityValue("pays_teacher", true, ctx())).toBe("Yes");
		expect(activityValue("pays_teacher", false, ctx())).toBe("No");
		expect(activityValue("pays_teacher", false, ctx("ar"))).toBe("لا");
	});

	it("shows free text as it is", () => {
		expect(activityValue("cancel_reason", "Eid", ctx())).toBe("Eid");
	});

	it("shows a day as a date and an instant in academy time, with the student's when it differs", () => {
		expect(activityValue("occurs_on", "2026-06-04", ctx())).toBe("Jun 4, 2026");
		expect(activityValue("starts_at", "2026-06-04T20:00:00Z", ctx())).toBe(
			"Jun 4, 2026 20:00 (student: 23:00)",
		);
		expect(activityValue("teacher_in_at", "2026-06-04T20:00:00Z", ctx("en", "UTC"))).toBe(
			"Jun 4, 2026 20:00",
		);
	});

	it("shows minutes with their unit", () => {
		expect(activityValue("actual_minutes", 45, ctx())).toBe("45 min");
	});

	it("shows a person by name, and a record that is gone (or has no name) by its id", () => {
		expect(activityValue("supervisor_id", { id: 50, name: "Sara" }, ctx())).toBe("Sara");
		expect(activityValue("teacher_id", { id: 999999, name: null }, ctx())).toBe("#999999");
		expect(activityValue("subscription_id", { id: 7, name: null }, ctx())).toBe("#7");
	});
});

describe("the sentences around an entry", () => {
	it("names the actor, the system, and a removed account", () => {
		expect(activityActor(activityEntry(), ctx())).toBe("Amina");
		expect(
			activityActor(activityEntry({ actor: null, actor_kind: "system" }), ctx()),
		).toBe("System");
		expect(
			activityActor(activityEntry({ actor: null, actor_kind: "user" }), ctx()),
		).toBe("A removed account");
	});

	it("labels an action as a sentence", () => {
		expect(activityAction("cancel", ctx())).toBe("Session cancelled");
		expect(activityAction("attendance", ctx("ar"))).toBe("تسجيل الحضور");
	});

	it("gives every action and field a label in both languages", () => {
		for (const lng of ["en", "ar"]) {
			for (const action of ACTIVITY_ACTIONS) {
				expect(i18n.exists(`sessionActivity.actions.${action}`, { lng })).toBe(true);
			}
			for (const field of ACTIVITY_FIELDS) {
				expect(i18n.exists(`sessionActivity.fields.${field}`, { lng })).toBe(true);
			}
		}
	});

	it("writes the time in academy time", () => {
		expect(activityWhen("2026-06-01T18:10:00Z", ctx())).toBe("Jun 1, 2026 18:10");
	});

	it("writes the creation line", () => {
		const at = "2026-05-20T09:00:00Z";
		const base = { at, kind: "regular" as const };
		expect(
			createdLine({ ...base, by: { id: 51, name: "Amina" }, generated: false }, ctx()),
		).toBe("Created by Amina");
		expect(createdLine({ ...base, by: null, generated: true }, ctx())).toBe(
			"Generated from the weekly timetable",
		);
		expect(createdLine({ ...base, by: null, generated: false }, ctx())).toBe(
			"Created by System",
		);
	});
});
```

`api.test.ts` (append inside the existing "writes to the spec routes" style, using the file's mocked `api`):

```ts
	it("reads a session's activity and reverts one entry (B2c §6)", async () => {
		await schedulingApi.activity(41);
		expect(api.get).toHaveBeenLastCalledWith("sessions/41/activity/");
		await schedulingApi.revertActivity({ id: 41, entryId: 9 });
		expect(api.post).toHaveBeenLastCalledWith("sessions/41/activity/9/revert/");
	});
```

`scheduling-fixtures.ts` (the test's imports need it; write it with the tests):

```ts
export function activityEntry(overrides: Partial<ActivityEntry> = {}): ActivityEntry {
	return {
		id: 1,
		action: "cancel",
		actor: { id: 51, name: "Amina" },
		actor_kind: "user",
		created_at: "2026-06-01T18:10:00Z",
		changes: [
			{ field: "status", before: "scheduled", after: "cancelled" },
			{ field: "cancel_reason", before: "", after: "Eid" },
		],
		reverts: null,
		reverted_by: [],
		can_revert: false,
		...overrides,
	};
}

/** The read of an empty log: a generated session, nothing changed yet. */
export function activityLog(overrides: Partial<ActivityLog> = {}): ActivityLog {
	return {
		results: [],
		truncated: false,
		created: {
			at: "2026-05-20T09:00:00Z",
			by: null,
			kind: "regular",
			generated: true,
		},
		...overrides,
	};
}
```

Also in the failing set: the existing `locales.test.ts` (ar and en key-for-key, one area file each) fails until both `sessionActivity.json` files exist and match.

- [ ] **Step 2: Run them to see them fail**

Run: `docker compose -f docker-compose.local.yml exec -T dashboard pnpm exec vitest run src/features/scheduling/activityFormat.test.ts src/features/scheduling/api.test.ts src/locales`
Expected: FAIL (`Failed to resolve import "./activityFormat"`, `schedulingApi.activity is not a function`). Keep the output for the report.

- [ ] **Step 3: Implement**

`identity/schemas.ts`: after `| "postponement"` add
```ts
	// Slice B2c (Plan 25).
	| "activity_log"
```

`schemas.ts` (after `Session`):

```ts
/** Slice B2c §4.1's actions and §3.2's logged fields, in the backend's order. */
export const ACTIVITY_ACTIONS = [
	"attendance", "cancel", "restore", "disposal", "pays_teacher", "supervision",
	"supervisor_attendance", "times", "postpone", "teacher_moved", "renewal_moved",
	"subscription_supervisor",
] as const;
export type ActivityAction = (typeof ACTIVITY_ACTIONS)[number];
export const ACTIVITY_FIELDS = [
	"status", "student_attendance", "teacher_attendance", "supervisor_attendance",
	"cancel_reason", "disposal_reason", "pays_teacher", "supervisor_id", "teacher_id",
	"subscription_id", "occurs_on", "starts_at", "teacher_in_at", "teacher_out_at",
	"student_in_at", "student_out_at", "actual_minutes",
] as const;
export type ActivityField = (typeof ACTIVITY_FIELDS)[number];

export interface ActivityPerson { id: number; name: string }
/** A supervisor, teacher or subscription a change names; `name` is null when
 * the record is gone and always for a subscription (plan D8): show `#id`. */
export interface ActivityRef { id: number; name: string | null }
export type ActivityValue = string | number | boolean | null | ActivityRef;
export interface ActivityChange { field: ActivityField; before: ActivityValue; after: ActivityValue }
export interface ActivityEntry {
	id: number;
	action: ActivityAction;
	actor: ActivityPerson | null;
	actor_kind: "user" | "system";
	created_at: string;
	changes: ActivityChange[];
	reverts: number | null;
	reverted_by: number[];
	can_revert: boolean;
}
export interface ActivityCreated {
	at: string;
	by: ActivityPerson | null;
	kind: SessionKind;
	generated: boolean;
}
export interface ActivityLog {
	results: ActivityEntry[];
	truncated: boolean;
	created: ActivityCreated;
}
export interface RevertedActivity { session: Session; entry: ActivityEntry }
```
(Format it the way Biome does: `pnpm exec biome format --write src/features/scheduling/schemas.ts`.)

`api.ts`: import `ActivityLog` and `RevertedActivity`; after `postpone`:

```ts
	// Slice B2c (spec §6).
	activity: async (id: number) =>
		(await api.get<ActivityLog>(`${SE}${id}/activity/`)).data,
	revertActivity: async ({ id, entryId }: { id: number; entryId: number }) =>
		(await api.post<RevertedActivity>(`${SE}${id}/activity/${entryId}/revert/`))
			.data,
```

`queries.ts`:

```ts
/** A session's activity log (slice B2c). Under `schedulingKey`, so every
 * scheduling write reloads it; only fetched while the section shows. */
export function useSessionActivity(id: number, enabled: boolean) {
	return useQuery({
		queryKey: [...schedulingKey, "activity", id],
		queryFn: () => schedulingApi.activity(id),
		enabled,
	});
}
```

`activityFormat.ts`:

```ts
import type { TFunction } from "i18next";
import { useTranslation } from "react-i18next";
import { dayIn, formatDay, otherZoneTime, wallTime } from "@/lib/zoned-time";
import type {
	ActivityCreated,
	ActivityEntry,
	ActivityField,
	ActivityValue,
} from "./schemas";

export interface FormatContext {
	t: TFunction;
	language: string;
	academyZone: string;
	studentZone: string;
}

const INSTANTS: readonly ActivityField[] = [
	"starts_at", "teacher_in_at", "teacher_out_at", "student_in_at", "student_out_at",
];
const ATTENDANCE: readonly ActivityField[] = [
	"student_attendance", "teacher_attendance", "supervisor_attendance",
];

/** An instant as "Jun 1, 2026 18:00" on the academy's clock. */
export function activityWhen(iso: string, ctx: FormatContext): string {
	const instant = new Date(iso);
	return ctx.t("sessionActivity.when", {
		day: dayIn(instant, ctx.academyZone, ctx.language),
		time: wallTime(instant, ctx.academyZone, ctx.language),
	});
}

/** One logged value as text (spec §7): translated statuses, attendance and
 * yes / no, dates, instants in academy time plus the student's when their
 * clock differs, ids as names (or `#id`), empty values as a dash. */
export function activityValue(
	field: ActivityField,
	value: ActivityValue,
	ctx: FormatContext,
): string {
	const { t, language } = ctx;
	if (value === null || value === "") return t("sessionActivity.none");
	if (typeof value === "object") {
		return value.name ?? t("sessionActivity.ref", { id: value.id });
	}
	if (field === "status") return t(`scheduling.sessions.status.${value}`);
	if (ATTENDANCE.includes(field)) return t(`scheduling.attendance.${value}`);
	if (field === "pays_teacher") {
		return t(value ? "sessionActivity.yes" : "sessionActivity.no");
	}
	if (field === "occurs_on") return formatDay(String(value), language);
	if (field === "actual_minutes") return t("sessionActivity.minutes", { minutes: value });
	if (INSTANTS.includes(field)) {
		const instant = new Date(String(value));
		const theirs = otherZoneTime(instant, ctx.studentZone, ctx.academyZone, language);
		const when = activityWhen(String(value), ctx);
		return theirs ? t("sessionActivity.withStudent", { when, time: theirs }) : when;
	}
	return String(value);
}

export function activityActor(entry: ActivityEntry, ctx: FormatContext): string {
	if (entry.actor) return entry.actor.name;
	// A user whose account was deleted is not the system (plan D14).
	return ctx.t(
		entry.actor_kind === "user" ? "sessionActivity.removedAccount" : "sessionActivity.system",
	);
}

export function activityAction(action: string, ctx: FormatContext): string {
	return ctx.t(`sessionActivity.actions.${action}`, { defaultValue: action });
}

/** Spec §7's creation line. */
export function createdLine(created: ActivityCreated, ctx: FormatContext): string {
	if (created.by) return ctx.t("sessionActivity.created.by", { name: created.by.name });
	return ctx.t(created.generated ? "sessionActivity.created.generated" : "sessionActivity.created.system");
}

export function useActivityFormat(academyZone: string, studentZone: string): FormatContext {
	const { t, i18n } = useTranslation();
	return { t, language: i18n.language, academyZone, studentZone };
}
```

`sessionActivity.json` (en):

```json
{
	"title": "Activity",
	"empty": "No changes have been logged on this session yet.",
	"loadError": "Couldn't load the activity.",
	"truncated": "Earlier changes are not shown.",
	"system": "System",
	"removedAccount": "A removed account",
	"none": "—",
	"yes": "Yes",
	"no": "No",
	"minutes": "{{minutes}} min",
	"ref": "#{{id}}",
	"when": "{{day}} {{time}}",
	"withStudent": "{{when}} (student: {{time}})",
	"meta": "{{actor}} · {{when}}",
	"created": {
		"by": "Created by {{name}}",
		"system": "Created by System",
		"generated": "Generated from the weekly timetable"
	},
	"columns": { "field": "Field", "before": "Before", "after": "After" },
	"badges": { "reverted": "Reverted", "reverts": "Reverts an earlier change" },
	"actions": {
		"attendance": "Attendance marked",
		"cancel": "Session cancelled",
		"restore": "Session restored",
		"disposal": "Placed at the administration's disposal",
		"pays_teacher": "Pays-the-teacher changed",
		"supervision": "Supervision changed",
		"supervisor_attendance": "Supervisor's attendance marked",
		"times": "Times recorded",
		"postpone": "Session postponed",
		"teacher_moved": "Teacher changed (subscription)",
		"renewal_moved": "Moved to the renewal",
		"subscription_supervisor": "Subscription supervisor changed"
	},
	"fields": {
		"status": "Status",
		"student_attendance": "Student attendance",
		"teacher_attendance": "Teacher attendance",
		"supervisor_attendance": "Supervisor attendance",
		"cancel_reason": "Cancel reason",
		"disposal_reason": "Disposal reason",
		"pays_teacher": "Pays the teacher",
		"supervisor_id": "Supervisor",
		"teacher_id": "Teacher",
		"subscription_id": "Subscription",
		"occurs_on": "Day",
		"starts_at": "Start",
		"teacher_in_at": "Teacher in",
		"teacher_out_at": "Teacher out",
		"student_in_at": "Student in",
		"student_out_at": "Student out",
		"actual_minutes": "Minutes taught"
	},
	"revert": {
		"button": "Revert",
		"buttonFor": "Revert: {{action}}",
		"title": "Revert this change",
		"body": "“{{action}}” by {{actor}} will be undone, by the same rules as any new change. If something changed after it, the revert is refused.",
		"confirm": "Revert",
		"keep": "Keep the change",
		"done": "Change reverted."
	}
}
```

`ar/sessionActivity.json` (same keys, one for one):

```json
{
	"title": "النشاط",
	"empty": "لم يُسجَّل أي تغيير على هذه الحصة بعد.",
	"loadError": "تعذّر تحميل النشاط.",
	"truncated": "التغييرات الأقدم غير معروضة.",
	"system": "النظام",
	"removedAccount": "حساب محذوف",
	"none": "—",
	"yes": "نعم",
	"no": "لا",
	"minutes": "{{minutes}} دقيقة",
	"ref": "#{{id}}",
	"when": "{{day}} {{time}}",
	"withStudent": "{{when}} (عند الطالب: {{time}})",
	"meta": "{{actor}} · {{when}}",
	"created": {
		"by": "أنشأها {{name}}",
		"system": "أنشأها النظام",
		"generated": "أُنشئت من الجدول الأسبوعي"
	},
	"columns": { "field": "الحقل", "before": "قبل", "after": "بعد" },
	"badges": { "reverted": "تم التراجع عنه", "reverts": "يتراجع عن تغيير سابق" },
	"actions": {
		"attendance": "تسجيل الحضور",
		"cancel": "إلغاء الحصة",
		"restore": "استرجاع الحصة",
		"disposal": "وضعها تحت تصرف الإدارة",
		"pays_teacher": "تغيير دفع أجر المعلم",
		"supervision": "تغيير الإشراف",
		"supervisor_attendance": "تسجيل حضور المشرف",
		"times": "تسجيل الأوقات",
		"postpone": "تأجيل الحصة",
		"teacher_moved": "تغيير المعلم (الاشتراك)",
		"renewal_moved": "نقلها إلى التجديد",
		"subscription_supervisor": "تغيير مشرف الاشتراك"
	},
	"fields": {
		"status": "الحالة",
		"student_attendance": "حضور الطالب",
		"teacher_attendance": "حضور المعلم",
		"supervisor_attendance": "حضور المشرف",
		"cancel_reason": "سبب الإلغاء",
		"disposal_reason": "سبب وضعها تحت التصرف",
		"pays_teacher": "تدفع أجر المعلم",
		"supervisor_id": "المشرف",
		"teacher_id": "المعلم",
		"subscription_id": "الاشتراك",
		"occurs_on": "اليوم",
		"starts_at": "البدء",
		"teacher_in_at": "دخول المعلم",
		"teacher_out_at": "خروج المعلم",
		"student_in_at": "دخول الطالب",
		"student_out_at": "خروج الطالب",
		"actual_minutes": "الدقائق المُدرَّسة"
	},
	"revert": {
		"button": "تراجع",
		"buttonFor": "تراجع: {{action}}",
		"title": "التراجع عن هذا التغيير",
		"body": "سيُلغى «{{action}}» الذي أجراه {{actor}} وفق القواعد نفسها التي تحكم أي تغيير جديد. إذا تغيّر شيء بعده فسيُرفض التراجع.",
		"confirm": "تراجع",
		"keep": "إبقاء التغيير",
		"done": "تم التراجع عن التغيير."
	}
}
```

`errors.json` (`scheduling` group, after `session_moved`; note `session_moved` gets a trailing comma): en `"changed_since": "This changed after that entry. Reload to see what it is now."`, `"not_revertible": "This change can't be reverted."`; ar `"changed_since": "تغيّر هذا بعد ذلك السجل. أعد التحميل لترى حالته الآن."`, `"not_revertible": "لا يمكن التراجع عن هذا التغيير."`. The inverse's own codes (`payroll.payslip_issued`, `scheduling.has_compensation`, `scheduling.not_allowed_in_status`, `scheduling.session_cancelled`, `scheduling.not_started`, `scheduling.session_moved`, `scheduling.already_compensated`, `scheduling.not_compensable`, B2b's `too_late_to_postpone` / `teacher_busy`) are already translated in both files; Task 12's test pins that.

- [ ] **Step 4: Run, then verify**

Run: the Step 2 command → PASS. Then `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint` (Biome format first: `… exec -T dashboard pnpm exec biome check --write src`), `… exec -T dashboard pnpm test:coverage` (gates: lines/statements 80, branches/functions 70).

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src/features/identity/schemas.ts src/features/scheduling/schemas.ts src/features/scheduling/api.ts src/features/scheduling/api.test.ts src/features/scheduling/queries.ts src/features/scheduling/activityFormat.ts src/features/scheduling/activityFormat.test.ts src/locales/en/sessionActivity.json src/locales/ar/sessionActivity.json src/locales/en/errors.json src/locales/ar/errors.json src/test/scheduling-fixtures.ts
git -C dashboard commit -m "feat(scheduling): activity log types, API, strings and format helpers (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: The Activity section on the session page

**Files:**
- Create: `dashboard/src/features/scheduling/SessionActivity.tsx` (+ `SessionActivity.test.tsx`)
- Modify: `dashboard/src/features/scheduling/SessionPage.tsx` (+ `SessionPage.test.tsx`)
- Modify: `dashboard/src/features/scheduling/SupervisorFields.test.tsx` and every other test file that renders `<SessionPage>` (`grep -rln "SessionPage" src`): mock `schedulingApi.activity`

**Interfaces:**
- Consumes: Task 10 (`useSessionActivity`, `useActivityFormat`, the format functions, `activityLog`, `activityEntry`), `useCan`, `useHasFeature`, `StatusChip`.
- Produces: `<SessionActivity session={Session} academyZone={string} />` — a Card titled "Activity" holding an ordered list (`aria-label` = the title): one `<li>` per entry, newest first, then the "Earlier changes are not shown." note when `truncated`, then the creation line as the last `<li>`. An entry shows the action's sentence, `actor · time`, the "Reverted" badge when `reverted_by` is not empty and "Reverts an earlier change" when `reverts` is set, and a Field / Before / After table whose cells carry `data-label` (the phone layout). The section shows in `SessionPage` only when `hasFeature("activity_log") && can("session.view")`; the query is not sent otherwise. No rule is restated here: what the server sent (`changes`, `can_revert`) is all that is shown.

- [ ] **Step 1: Write the failing tests**

`SessionActivity.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { activityEntry, activityLog, sessionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SessionActivity } from "./SessionActivity";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, schedulingApi: { ...actual.schedulingApi, activity: vi.fn() } };
});

const cancel = activityEntry({ id: 1, reverted_by: [2] });
const restore = activityEntry({
	id: 2,
	action: "restore",
	created_at: "2026-06-01T18:20:00Z",
	changes: [
		{ field: "status", before: "cancelled", after: "scheduled" },
		{ field: "cancel_reason", before: "Eid", after: "" },
	],
	reverts: 1,
});

function show() {
	// Yusuf is in Riyadh (UTC+3); the academy is on UTC.
	renderWithRouter(<SessionActivity session={sessionRow()} academyZone="UTC" />);
}
const items = async () =>
	within(await screen.findByRole("list", { name: "Activity" })).getAllByRole("listitem");

describe("SessionActivity", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(schedulingApi.activity).mockResolvedValue(
			activityLog({ results: [restore, cancel] }),
		);
	});

	it("lists the entries newest first, then the creation line", async () => {
		show();
		const [first, second, created] = await items();
		expect(schedulingApi.activity).toHaveBeenCalledWith(41);
		expect(first).toHaveTextContent("Session restored");
		expect(first).toHaveTextContent("Amina · Jun 1, 2026 18:20");
		expect(second).toHaveTextContent("Session cancelled");
		expect(created).toHaveTextContent("Generated from the weekly timetable");
		expect(created).toHaveTextContent("May 20, 2026 09:00");
	});

	it("shows each change as field, before and after, translated", async () => {
		show();
		const [, second] = await items();
		const rows = within(within(second).getByRole("table")).getAllByRole("row");
		// header, then one row per change
		expect(within(rows[0]).getAllByRole("columnheader").map((c) => c.textContent)).toEqual([
			"Field", "Before", "After",
		]);
		expect(within(rows[1]).getAllByRole("cell").map((c) => c.textContent)).toEqual([
			"Status", "Scheduled", "Cancelled",
		]);
		expect(within(rows[2]).getAllByRole("cell").map((c) => c.textContent)).toEqual([
			"Cancel reason", "—", "Eid",
		]);
	});

	it("labels every cell for the phone layout", async () => {
		show();
		const [, second] = await items();
		const cells = within(second).getAllByRole("cell");
		expect(cells.map((c) => c.getAttribute("data-label"))).toEqual([
			"Field", "Before", "After", "Field", "Before", "After",
		]);
	});

	it("marks a reverted entry and a revert", async () => {
		show();
		const [first, second] = await items();
		expect(within(first).getByText("Reverts an earlier change")).toBeInTheDocument();
		expect(within(first).queryByText("Reverted", { exact: true })).toBeNull();
		expect(within(second).getByText("Reverted", { exact: true })).toBeInTheDocument();
		expect(within(second).queryByText("Reverts an earlier change")).toBeNull();
	});

	it("formats instants, days, minutes, people and yes / no", async () => {
		vi.mocked(schedulingApi.activity).mockResolvedValue(
			activityLog({
				results: [
					activityEntry({
						action: "postpone",
						changes: [
							{ field: "occurs_on", before: "2026-06-01", after: "2026-06-04" },
							{ field: "starts_at", before: "2026-06-01T18:00:00Z", after: "2026-06-04T20:00:00Z" },
							{ field: "supervisor_id", before: null, after: { id: 9, name: null } },
							{ field: "pays_teacher", before: true, after: false },
							{ field: "actual_minutes", before: null, after: 45 },
						],
					}),
				],
			}),
		);
		show();
		const [entry] = await items();
		const text = within(entry).getByRole("table").textContent ?? "";
		for (const wanted of [
			"Jun 1, 2026", "Jun 4, 2026",
			"Jun 4, 2026 20:00 (student: 23:00)",
			"#9", "Yes", "No", "45 min",
		]) {
			expect(text).toContain(wanted);
		}
	});

	it("names the system and a removed account", async () => {
		vi.mocked(schedulingApi.activity).mockResolvedValue(
			activityLog({
				results: [
					activityEntry({ id: 4, actor: null, actor_kind: "system" }),
					activityEntry({ id: 3, actor: null, actor_kind: "user" }),
				],
			}),
		);
		show();
		const [system, removed] = await items();
		expect(system).toHaveTextContent("System ·");
		expect(removed).toHaveTextContent("A removed account ·");
	});

	it("writes the creation line for a named creator and for the system", async () => {
		const created = (by: { id: number; name: string } | null, generated: boolean) =>
			activityLog({ created: { at: "2026-05-20T09:00:00Z", by, kind: "extra", generated } });
		vi.mocked(schedulingApi.activity).mockResolvedValueOnce(
			created({ id: 51, name: "Amina" }, false),
		);
		const { unmount } = renderWithRouter(
			<SessionActivity session={sessionRow()} academyZone="UTC" />,
		);
		expect(await screen.findByText("Created by Amina", { exact: false })).toBeInTheDocument();
		unmount();
		vi.mocked(schedulingApi.activity).mockResolvedValueOnce(created(null, false));
		show();
		expect(await screen.findByText("Created by System", { exact: false })).toBeInTheDocument();
	});

	it("says when older entries exist, and only then", async () => {
		vi.mocked(schedulingApi.activity).mockResolvedValue(
			activityLog({ results: [cancel], truncated: true }),
		);
		const { unmount } = renderWithRouter(
			<SessionActivity session={sessionRow()} academyZone="UTC" />,
		);
		expect(await screen.findByText("Earlier changes are not shown.")).toBeInTheDocument();
		unmount();
		vi.mocked(schedulingApi.activity).mockResolvedValue(activityLog({ results: [cancel] }));
		show();
		await items();
		expect(screen.queryByText("Earlier changes are not shown.")).toBeNull();
	});

	it("says so when nothing has changed, keeping the creation line", async () => {
		vi.mocked(schedulingApi.activity).mockResolvedValue(activityLog());
		show();
		expect(
			await screen.findByText("No changes have been logged on this session yet."),
		).toBeInTheDocument();
		expect(screen.getByText("Generated from the weekly timetable")).toBeInTheDocument();
	});

	it("says when the log can't be loaded", async () => {
		vi.mocked(schedulingApi.activity).mockRejectedValue(new AxiosError("no"));
		show();
		expect(await screen.findByText("Couldn't load the activity.")).toBeInTheDocument();
	});
});
```

`SessionPage.test.tsx` (append a `describe("activity (B2c)")`, and add `activity: vi.fn()` to the file's `schedulingApi` mock with `vi.mocked(schedulingApi.activity).mockResolvedValue(activityLog())` in the top `beforeEach`; import `activityLog` and `staffMe`'s siblings as the file already does):

```tsx
	describe("activity (B2c)", () => {
		it("shows the Activity section with the switch on and session.view", async () => {
			renderWithRouter(
				<CanProvider me={adminWith("activity_log")}>
					<SessionPage sessionId="41" />
				</CanProvider>,
			);
			expect(await screen.findByText("Activity", { exact: true })).toBeInTheDocument();
			await waitFor(() => expect(schedulingApi.activity).toHaveBeenCalledWith(41));
		});

		it("shows nothing and reads nothing with the switch off", async () => {
			renderWithRouter(
				<CanProvider me={adminWith("teacher_attendance")}>
					<SessionPage sessionId="41" />
				</CanProvider>,
			);
			expect(await screen.findByText("Bring the book")).toBeInTheDocument();
			expect(screen.queryByText("Activity", { exact: true })).toBeNull();
			expect(schedulingApi.activity).not.toHaveBeenCalled();
		});

		it("shows nothing and reads nothing without session.view", async () => {
			renderWithRouter(
				<CanProvider me={staffMe("attendance.update")}>
					<SessionPage sessionId="41" />
				</CanProvider>,
			);
			expect(await screen.findByText("Bring the book")).toBeInTheDocument();
			expect(screen.queryByText("Activity", { exact: true })).toBeNull();
			expect(schedulingApi.activity).not.toHaveBeenCalled();
		});
	});
```

(`staffMe("attendance.update")` carries no `features`, so the switch counts as on there: the missing `session.view` is what hides the section.)

`SupervisorFields.test.tsx` and any other file that renders `SessionPage` outside a provider (the shell-less default counts every switch as on, so the section now reads the log): add `activity: vi.fn()` to its `schedulingApi` mock and `vi.mocked(schedulingApi.activity).mockResolvedValue(activityLog())` to its `beforeEach`, so they never reach the network.

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/SessionActivity.test.tsx src/features/scheduling/SessionPage.test.tsx src/features/scheduling/SupervisorFields.test.tsx`
Expected: FAIL (`Failed to resolve import "./SessionActivity"`; the SessionPage "shows the section" case never finds "Activity"). Keep the output.

- [ ] **Step 3: Implement**

`SessionActivity.tsx` (semantic tokens only; logical properties only, so Arabic mirrors for free: `ms-`, `ps-`, `text-start`, never `ml-`, `pl-`, `text-left`):

```tsx
import { useTranslation } from "react-i18next";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
	StatusChip,
} from "@/ui";
import {
	activityAction,
	activityActor,
	activityValue,
	activityWhen,
	createdLine,
	type FormatContext,
	useActivityFormat,
} from "./activityFormat";
import { useSessionActivity } from "./queries";
import type { ActivityEntry, Session } from "./schemas";

// A phone shows each cell as "Label  value" in a stack; from `sm` up it is a
// table (the header row is for screen readers below that).
const CELL =
	"block py-0.5 before:block before:text-xs before:text-muted-foreground before:content-[attr(data-label)] sm:table-cell sm:px-2 sm:py-1.5 sm:before:hidden";

function ChangesTable({ entry, format }: { entry: ActivityEntry; format: FormatContext }) {
	const { t } = format;
	const label = (key: "field" | "before" | "after") => t(`sessionActivity.columns.${key}`);
	return (
		<table className="block w-full text-sm sm:table">
			<thead className="sr-only sm:not-sr-only sm:table-header-group">
				<tr className="sm:border-b sm:border-border">
					{(["field", "before", "after"] as const).map((key) => (
						<th key={key} scope="col" className="px-2 py-1 text-start text-xs font-normal text-muted-foreground">
							{label(key)}
						</th>
					))}
				</tr>
			</thead>
			<tbody className="block sm:table-row-group">
				{entry.changes.map((change) => (
					<tr key={change.field} className="block border-b border-border py-1 last:border-b-0 sm:table-row">
						<td data-label={label("field")} className={`${CELL} font-medium`}>
							{t(`sessionActivity.fields.${change.field}`)}
						</td>
						<td data-label={label("before")} className={CELL}>
							<bdi>{activityValue(change.field, change.before, format)}</bdi>
						</td>
						<td data-label={label("after")} className={CELL}>
							<bdi>{activityValue(change.field, change.after, format)}</bdi>
						</td>
					</tr>
				))}
			</tbody>
		</table>
	);
}

function EntryItem({ entry, format }: { entry: ActivityEntry; format: FormatContext }) {
	const { t } = format;
	return (
		<li className="flex flex-col gap-2 border-b border-border pb-4 last:border-b-0">
			<div className="flex flex-wrap items-center justify-between gap-2">
				<div>
					<p className="font-medium">{activityAction(entry.action, format)}</p>
					<p className="text-xs text-muted-foreground">
						{t("sessionActivity.meta", {
							actor: activityActor(entry, format),
							when: activityWhen(entry.created_at, format),
						})}
					</p>
				</div>
				<span className="flex flex-wrap items-center gap-1">
					{entry.reverts !== null ? (
						<StatusChip>{t("sessionActivity.badges.reverts")}</StatusChip>
					) : null}
					{entry.reverted_by.length > 0 ? (
						<StatusChip>{t("sessionActivity.badges.reverted")}</StatusChip>
					) : null}
				</span>
			</div>
			<ChangesTable entry={entry} format={format} />
		</li>
	);
}

/** Slice B2c §7 (office): every change made to the session, newest first, with
 * the creation line last. Whatever the server sent is shown as sent. */
export function SessionActivity({ session, academyZone }: { session: Session; academyZone: string }) {
	const { t } = useTranslation();
	const format = useActivityFormat(academyZone, session.student.timezone);
	const { data, isError } = useSessionActivity(session.id, true);
	let body;
	if (isError) {
		body = (
			<Alert variant="destructive">
				<AlertDescription>{t("sessionActivity.loadError")}</AlertDescription>
			</Alert>
		);
	} else if (!data) {
		body = <Spinner />;
	} else {
		body = (
			<>
				{data.results.length === 0 ? (
					<p className="text-sm text-muted-foreground">{t("sessionActivity.empty")}</p>
				) : null}
				<ol aria-label={t("sessionActivity.title")} className="flex flex-col gap-4">
					{data.results.map((entry) => (
						<EntryItem key={entry.id} entry={entry} format={format} />
					))}
					{data.truncated ? (
						<li className="text-sm text-muted-foreground">{t("sessionActivity.truncated")}</li>
					) : null}
					<li className="text-sm text-muted-foreground">
						{createdLine(data.created, format)}
						<span className="block text-xs">{activityWhen(data.created.at, format)}</span>
					</li>
				</ol>
			</>
		);
	}
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("sessionActivity.title")}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-4">{body}</CardContent>
		</Card>
	);
}
```

(The "Earlier changes are not shown." note and the creation line are `<li>`s of the same list; the empty-state test above reads them by text, the order test by position. If `getAllByRole("listitem")` in the order test also returns the truncation `<li>` for a truncated fixture, those tests use untruncated logs, as written.)

`SessionPage.tsx`: import `SessionActivity` and, right after the `SessionClasses` block's sibling — after the report card, as the last section — add

```tsx
			{hasFeature("activity_log") && can("session.view") ? (
				<SessionActivity session={session} academyZone={academy.timezone} />
			) : null}
```

- [ ] **Step 4: Run, then verify**

Run: the Step 2 command → PASS; then `… exec -T dashboard pnpm exec vitest run src/features/scheduling` (nothing else broke). Check the layout rules: `grep -nE "\b(ml|mr|pl|pr|left|right)-|text-(left|right)" dashboard/src/features/scheduling/SessionActivity.tsx` prints nothing (RTL: logical properties only). Then `tsc --noEmit`, `pnpm lint` (Biome and `check-colors`: semantic tokens only), `pnpm test:coverage`.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src/features/scheduling/SessionActivity.tsx src/features/scheduling/SessionActivity.test.tsx src/features/scheduling/SessionPage.tsx src/features/scheduling/SessionPage.test.tsx src/features/scheduling/SupervisorFields.test.tsx
git -C dashboard commit -m "feat(scheduling): the Activity section on the session page (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

(Add any other test file `grep` found to the `git add`.)

---

### Task 12: The Revert dialog

**Files:**
- Create: `dashboard/src/features/scheduling/RevertDialog.tsx` (+ `RevertDialog.test.tsx`)
- Modify: `dashboard/src/features/scheduling/SessionActivity.tsx` (+ `SessionActivity.test.tsx`), `SessionPage.test.tsx`

**Interfaces:**
- Consumes: Task 10 (`schedulingApi.revertActivity`, `schedulingKey`, `activityAction`, `activityActor`), Task 11's `SessionActivity`, `errorText`, `toast`.
- Produces: `<RevertDialog sessionId={number} entry={ActivityEntry} format={FormatContext} />` — a Revert button named "Revert: {action}" (one per entry with `can_revert`, the server's flag and nothing else), which opens a confirm dialog (title "Revert this change", the entry's action and actor in the body, **Keep the change** and **Revert**). On success: the toast "Change reverted.", the dialog closes, and every scheduling query reloads (so the session and the log are fresh, `useSchedulingMutation`). On a refusal: the dialog stays open with the translated sentence in an alert (a 409's `errors.<code>`, else the server's message, else a field's own 400 message such as B2b's `occurs_on`), and the queries reload too, so an entry that is no longer revertible loses its button.

- [ ] **Step 1: Write the failing tests**

`RevertDialog.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { activityEntry, sessionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { RevertDialog } from "./RevertDialog";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, schedulingApi: { ...actual.schedulingApi, revertActivity: vi.fn() } };
});

const entry = activityEntry({ id: 9, can_revert: true });
const format = { t: i18n.t.bind(i18n), language: "en", academyZone: "UTC", studentZone: "UTC" };

function refusal(status: number, data: Record<string, unknown>) {
	return new AxiosError("refused", String(status), undefined, undefined, {
		status,
		data,
	} as never);
}

async function open() {
	const user = userEvent.setup();
	const view = renderWithRouter(<RevertDialog sessionId={41} entry={entry} format={format} />);
	await user.click(await screen.findByRole("button", { name: "Revert: Session cancelled" }));
	return { user, dialog: screen.getByRole("dialog"), ...view };
}

describe("RevertDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(schedulingApi.revertActivity).mockResolvedValue({
			session: sessionRow(),
			entry: activityEntry({ id: 10, action: "restore", reverts: 9 }),
		});
	});

	it("asks first, naming the change and who made it", async () => {
		const { dialog } = await open();
		expect(within(dialog).getByText("Revert this change")).toBeInTheDocument();
		expect(dialog).toHaveTextContent("“Session cancelled” by Amina will be undone");
		expect(schedulingApi.revertActivity).not.toHaveBeenCalled();
	});

	it("keeping the change sends nothing", async () => {
		const { user, dialog } = await open();
		await user.click(within(dialog).getByRole("button", { name: "Keep the change" }));
		expect(schedulingApi.revertActivity).not.toHaveBeenCalled();
		await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
	});

	it("reverts, says so, closes and reloads every scheduling query", async () => {
		const { user, dialog, client } = await open();
		const invalidate = vi.spyOn(client, "invalidateQueries");
		await user.click(within(dialog).getByRole("button", { name: "Revert" }));
		expect(schedulingApi.revertActivity).toHaveBeenCalledWith({ id: 41, entryId: 9 });
		expect(await screen.findByText("Change reverted.")).toBeInTheDocument();
		await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
		expect(invalidate).toHaveBeenCalledWith({ queryKey: ["scheduling"] });
	});

	it.each([
		["scheduling.changed_since", "This changed after that entry. Reload to see what it is now."],
		["scheduling.not_revertible", "This change can't be reverted."],
		["payroll.payslip_issued", "This session is on an issued payslip, so it can't change."],
		["scheduling.has_compensation", "This session has a make-up session, so it can't be changed or deleted."],
		["scheduling.not_allowed_in_status", "That isn't possible in the current status."],
		["scheduling.session_cancelled", "This session was cancelled."],
		["scheduling.not_started", "Attendance opens when the session starts."],
		["scheduling.session_moved", "This session changed meanwhile. Try again."],
		["scheduling.already_compensated", "This session already has a make-up session."],
		["scheduling.not_compensable", "Only a session that did not use up the package can be made up."],
	])("translates the 409 %s and keeps the dialog open", async (code, sentence) => {
		vi.mocked(schedulingApi.revertActivity).mockRejectedValue(refusal(409, { detail: "x", code }));
		const { user, dialog, client } = await open();
		const invalidate = vi.spyOn(client, "invalidateQueries");
		await user.click(within(dialog).getByRole("button", { name: "Revert" }));
		expect(await within(dialog).findByText(sentence)).toBeInTheDocument();
		expect(screen.getByRole("dialog")).toBeInTheDocument();
		expect(screen.queryByText("Change reverted.")).toBeNull();
		// the log reloads, so a stale entry loses its button
		expect(invalidate).toHaveBeenCalledWith({ queryKey: ["scheduling"] });
	});

	it("shows a 400 on a field (a postponement the clock has passed) in the dialog", async () => {
		vi.mocked(schedulingApi.revertActivity).mockRejectedValue(
			refusal(400, { occurs_on: ["That time has passed."] }),
		);
		const { user, dialog } = await open();
		await user.click(within(dialog).getByRole("button", { name: "Revert" }));
		expect(await within(dialog).findByText("That time has passed.")).toBeInTheDocument();
	});

	it("speaks Arabic", async () => {
		await i18n.changeLanguage("ar");
		try {
			const user = userEvent.setup();
			renderWithRouter(
				<RevertDialog sessionId={41} entry={entry} format={{ ...format, t: i18n.t.bind(i18n), language: "ar" }} />,
			);
			await user.click(await screen.findByRole("button", { name: "تراجع: إلغاء الحصة" }));
			expect(screen.getByText("التراجع عن هذا التغيير")).toBeInTheDocument();
		} finally {
			await i18n.changeLanguage("en");
		}
	});
});
```

`SessionActivity.test.tsx` (append): with `results: [{...restore, can_revert: true}, {...cancel, can_revert: false}]` there is exactly one button matching `/^Revert:/`, inside the first item; with none flagged there is none (the component never infers it from the entry's fields).

`SessionPage.test.tsx` (append to the activity describe): the integration the spec asks for ("after success the session and the log reload"): with `adminWith("activity_log", "teacher_attendance")`, `session` resolves to a completed session (`student_attendance: "present"`, `status: "completed"`, `has_started: true`) the first time and to `sessionRow()` after, `activity` resolves to `[attendance entry, can_revert: true]` first and then to two entries (the revert, `reverts: 1`, and the old one with `reverted_by: [2]`, neither revertible); clicking "Revert: Attendance marked" and then "Revert" calls `revertActivity({ id: 41, entryId: 1 })`, and then `schedulingApi.session` and `schedulingApi.activity` are each called twice, the student attendance select shows "Not set", and the badge "Reverts an earlier change" appears.

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/RevertDialog.test.tsx src/features/scheduling/SessionActivity.test.tsx src/features/scheduling/SessionPage.test.tsx`
Expected: FAIL (`Failed to resolve import "./RevertDialog"`; no "Revert: …" button). Keep the output.

- [ ] **Step 3: Implement**

`RevertDialog.tsx` (modelled on `DisposalDialog`; a plain `Dialog`, not `Confirm`, because a refusal must show inside it and keep it open):

```tsx
import { useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { errorText } from "@/lib/form-errors";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	SubmitButton,
	toast,
} from "@/ui";
import { activityAction, activityActor, type FormatContext } from "./activityFormat";
import { schedulingApi } from "./api";
import { schedulingKey, useSchedulingMutation } from "./queries";
import type { ActivityEntry } from "./schemas";

/** Slice B2c §7: revert one entry. Shown only for `can_revert` (the server
 * weighed the codes, switches and the fields' current values); every other
 * rule is the server's, and its refusal is shown here, translated. */
export function RevertDialog({
	sessionId,
	entry,
	format,
}: {
	sessionId: number;
	entry: ActivityEntry;
	format: FormatContext;
}) {
	const { t } = format;
	const qc = useQueryClient();
	const revert = useSchedulingMutation(schedulingApi.revertActivity);
	const [open, setOpen] = useState(false);
	const [refusal, setRefusal] = useState<string | null>(null);
	const action = activityAction(entry.action, format);

	async function confirm() {
		setRefusal(null);
		try {
			await revert.mutateAsync({ id: sessionId, entryId: entry.id });
			toast({ description: t("sessionActivity.revert.done") });
			setOpen(false);
		} catch (error) {
			setRefusal(errorText(error, t));
			// Whatever refused it, what the page shows may be stale.
			await qc.invalidateQueries({ queryKey: schedulingKey });
		}
	}

	return (
		<Dialog
			open={open}
			onOpenChange={(next) => {
				setOpen(next);
				if (!next) setRefusal(null);
			}}
		>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline" aria-label={t("sessionActivity.revert.buttonFor", { action })}>
					{t("sessionActivity.revert.button")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("sessionActivity.revert.title")}</DialogTitle>
				<DialogDescription>
					{t("sessionActivity.revert.body", { action, actor: activityActor(entry, format) })}
				</DialogDescription>
				{refusal ? (
					<Alert variant="destructive">
						<AlertDescription>{refusal}</AlertDescription>
					</Alert>
				) : null}
				<DialogFooter>
					<DialogClose asChild>
						<Button type="button" variant="outline">
							{t("sessionActivity.revert.keep")}
						</Button>
					</DialogClose>
					<SubmitButton type="button" pending={revert.isPending} onClick={confirm}>
						{t("sessionActivity.revert.confirm")}
					</SubmitButton>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
```

(Check `SubmitButton`'s props in `src/ui/submit-button.tsx`; if it only renders `type="submit"`, use `<Button type="button" disabled={revert.isPending} onClick={confirm}>` instead. The Revert button's `aria-label` keeps the visible text "Revert" while naming the entry for screen readers, so a list of buttons is distinguishable.)

`SessionActivity.tsx`: import `RevertDialog` and, in `EntryItem`, take `sessionId` and render under the table

```tsx
			{entry.can_revert ? (
				<div className="flex justify-end">
					<RevertDialog sessionId={sessionId} entry={entry} format={format} />
				</div>
			) : null}
```

passing `sessionId={session.id}` from `SessionActivity` to each `EntryItem`.

- [ ] **Step 4: Run, then verify**

Run: the Step 2 command → PASS; then the whole `src/features/scheduling` folder. Then `tsc --noEmit`, `pnpm lint`, `pnpm test:coverage`.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src/features/scheduling/RevertDialog.tsx src/features/scheduling/RevertDialog.test.tsx src/features/scheduling/SessionActivity.tsx src/features/scheduling/SessionActivity.test.tsx src/features/scheduling/SessionPage.test.tsx
git -C dashboard commit -m "feat(scheduling): revert an activity entry from the session page (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: End-to-end through Caddy, and the slice gates

**Files:**
- Create: `dashboard/e2e/b2-activity.spec.ts`

- [ ] **Step 1: Write the spec** — model it on `dashboard/e2e/b2-postpone.spec.ts` (read it first: its stamped people and catalogue steps, `inDays`, `startedTime`, `dismissDone`, the Add session dialog). The spec owns its data (a stamped teacher, course and student; no subscription and no package are needed: an extra session stands alone) and fakes no time: to mark attendance it needs a session that has started, so the admin adds an **extra** session that started ten minutes ago (B2a lets a hand-added session start in the past), as Plan 21's e2e did.

```ts
import { expect, type Page, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { manage } from "./manage";

const SWITCHES = ["activity_log", "extra_sessions"];

/** The date `days` from now in UTC (demo's academy clock), as the date input takes it. */
function inDays(days: number): string {
	return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
}

/** Ten minutes ago on the demo academy's clock (UTC), or midnight in the
 * first ten minutes of the day, so the session has already started. */
function startedTime(now = new Date()): string {
	const earlier = new Date(now.getTime() - 10 * 60_000);
	if (earlier.getUTCDate() !== now.getUTCDate()) return "00:00";
	return earlier.toISOString().slice(11, 16);
}

/** Close the result dialog when the new session overlapped another one. */
async function dismissDone(page: Page) {
	const done = page.getByRole("button", { name: "Done" });
	if (await done.isVisible()) await done.click();
}

// Slice B2c spec §9: the admin marks attendance on a started session, sees the
// entry in its Activity section, reverts it, and sees the attendance back to
// "Not set" with a revert entry. Stamped data, so a second run on the same
// database never meets the first run's rows.
test("the admin marks attendance, sees the entry and reverts it", async ({ page }) => {
	test.setTimeout(120_000);
	const stamp = Date.now();
	const teacher = `E2E Tutor ${stamp}`;
	const student = `E2E Learner ${stamp}`;
	const course = `E2E Recitation ${stamp}`;
	manage("set_features", "demo", "--on", ...SWITCHES);
	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// Own teacher, course and student (the same form steps as b2-postpone.spec.ts:
	// teacher with email and gender, course taught by the teacher, student)
	// ... copy those three blocks, with `${stamp}` in every name and email ...

	// An extra session for them that started ten minutes ago
	await page.goto(`${DEMO_URL}/app/scheduling/sessions`);
	await page.getByRole("button", { name: "Add session" }).click();
	const add = page.getByRole("dialog");
	await add.getByLabel(/^Kind/).selectOption("extra");
	await add.getByLabel(/^Student/).selectOption({ label: student });
	await add.getByLabel(/^Course/).selectOption({ label: course });
	await add.getByLabel(/^Teacher/).selectOption({ label: teacher });
	await add.getByLabel(/^Date/).fill(inDays(0));
	await add.getByLabel(/^Start time/).fill(startedTime());
	await add.getByLabel(/^Minutes/).fill("60");
	await add.getByRole("button", { name: "Add session" }).click();
	await expect(page.getByText("Session added.", { exact: true })).toBeVisible();
	await dismissDone(page);

	// Open it: nothing is logged yet, and the creation line names the admin
	await page
		.getByRole("group", { name: "Session kind" })
		.getByRole("button", { name: "Extra" })
		.click();
	await page.getByRole("searchbox").fill(student);
	await page
		.getByRole("row", { name: new RegExp(student) })
		.getByRole("link", { name: student, exact: true })
		.click();
	await expect(page).toHaveURL(/\/app\/scheduling\/sessions\/\d+$/);
	await expect(page.getByText("Activity", { exact: true })).toBeVisible();
	await expect(
		page.getByText("No changes have been logged on this session yet."),
	).toBeVisible();
	await expect(page.getByText(/^Created by /)).toBeVisible();

	// Mark the student present: the entry shows who, what, before and after
	const mark = page.getByRole("combobox", { name: `Student attendance for ${student}` });
	await mark.selectOption("present");
	await expect(mark).toHaveValue("present");
	const log = page.getByRole("list", { name: "Activity" });
	const entry = log.getByRole("listitem").first();
	await expect(entry).toContainText("Attendance marked");
	await expect(entry).toContainText("Student attendance");
	await expect(entry.getByRole("row", { name: /Student attendance/ })).toContainText("Not set");
	await expect(entry.getByRole("row", { name: /Student attendance/ })).toContainText("Present");
	await expect(entry.getByRole("row", { name: /^Status/ })).toContainText("Completed");

	// Revert it: attendance goes back, and the log gains a revert entry
	await entry.getByRole("button", { name: /^Revert:/ }).click();
	const confirm = page.getByRole("dialog");
	await expect(confirm).toContainText("Revert this change");
	await confirm.getByRole("button", { name: "Revert", exact: true }).click();
	await expect(page.getByText("Change reverted.", { exact: true })).toBeVisible();
	await expect(mark).toHaveValue("not_set");
	await expect(log.getByText("Reverts an earlier change")).toBeVisible();
	await expect(log.getByText("Reverted", { exact: true })).toBeVisible();
	// only the newest entry can still be reverted: the older one's fields moved on
	await expect(log.getByRole("button", { name: /^Revert:/ })).toHaveCount(1);

	// Phone width: the table stacks, nothing scrolls sideways
	await page.setViewportSize({ width: 375, height: 800 });
	await expect(log.getByText("Student attendance").first()).toBeVisible();
	expect(
		await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
	).toBe(true);

	// Arabic: the section reads right to left
	await page.evaluate(() => localStorage.setItem("etqan-locale", "ar"));
	await page.reload();
	await expect(page.getByText("النشاط", { exact: true })).toBeVisible();
});
```

(The "copy those three blocks" comment is a pointer for the implementer, not output: write the teacher, course and student steps out in full, with the b2-postpone.spec.ts selectors, before running.)

- [ ] **Step 2: Run it twice on one database**

Run: `just e2e e2e/b2-activity.spec.ts` and again `just e2e e2e/b2-activity.spec.ts` (no reset between) → PASS both times. Keep the Playwright output for the report. (No clock is faked and `manage` only sets switches; a failure at "Mark the student present" means the extra session had not started: check `startedTime()` against the container's clock.)

- [ ] **Step 3: Run the slice gates**

Run, in order: `just test` (backend ≥ 80 %, dashboard lines/statements ≥ 80, branches/functions ≥ 70), `just lint`, `just e2e`. Locally the families spec can race the features spec when specs run in parallel: rerun a lone failure by itself before reporting it. The seeded demo (`just _stack-manage seed_dev`) must show the admin's attendance change and the reverted cancel on its latest unpaid completed session when its Activity section is opened (Task 9) — open one in the browser once as a smoke check.

- [ ] **Step 4: Commit**

```bash
git -C dashboard add e2e/b2-activity.spec.ts
git -C dashboard commit -m "test(e2e): the admin marks attendance, sees the entry and reverts it (B2c)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Self-review (done while writing)

- **Spec coverage:** §1 goal → Tasks 2–8 (+ 10–13 for what the office sees). §2: C-1 (sessions only; no subscription route) → Task 8's two routes; C-2 → Tasks 2–3 (`track` diff, no-op writes nothing); C-3 → Task 8 (`created`) and Task 11 (the creation line); C-4 → Tasks 3–5 (services only, no signals); C-5 → Task 6; C-6 → Tasks 2, 6, 7; C-7 → Tasks 2, 6, 7 (+ Task 11's badges, Task 13's e2e); C-8 → Tasks 5, 6, 7; C-9 → Task 2's `LOGGED_FIELDS`; C-10 → Tasks 6, 7, 8 (the dashboard gates on `session.view` and `can_revert`, Task 11–12); C-11 → Tasks 1, 3, 8; C-12 → Task 7. §3.1 → Task 1; §3.2 → Task 2. §4.1 → Tasks 3–5; §4.2 → Task 6; §4.3 → Tasks 7–8. §5 → Task 8. §6 → Task 8 (+ Task 10's `schedulingApi`). §7 → Task 10 (types, strings, formats), Task 11 (section, table, translated names and values, academy and student time, badges, truncated note, creation line, phone stacking, RTL), Task 12 (Revert, confirm, reload, 409 codes). §8 → Task 9. §9: Tracking → Tasks 3–5; Revert → Task 6; Reading → Task 7; Access → Task 8; Existing suites → the full runs in Tasks 3, 5, 6, 8, 13; Dashboard → Tasks 10–12; e2e → Task 13. §10 known limits and §11 out of scope: no code, nothing to build.
- **Spec values this plan changes on purpose** (each in the Decisions): §4.3's "subscription → its code" is `#<id>` because subscriptions have no code column (D8); §8's "skipped when the session already has entries" is "skipped when the demo admin has any entry" because demo's teacher marks already log (D12); the spec's five additive `by` services gain a sixth, `set_subscription_supervisor` (D5).
- **Placeholders:** none. The one pointer in Task 13 (the teacher, course and student steps are those of `b2-postpone.spec.ts`) names the file to copy from and what to change (the stamp in every name), and says it must be written out before running.
- **Type consistency:** backend payload keys (`results`, `truncated`, `created{at,by,kind,generated}`; entry `id, action, actor{id,name}, actor_kind, created_at, changes[{field,before,after}], reverts, reverted_by, can_revert`; revert `{session, entry}`) match Task 10's `ActivityLog`, `ActivityEntry`, `ActivityCreated`, `RevertedActivity`; the twelve actions and seventeen fields match Task 2's `Action` and `LOGGED_FIELDS`; the 409 codes `scheduling.changed_since` and `scheduling.not_revertible` are Task 6's and Task 10's `errors.json` keys, and every inverse code Task 12 tests is an existing key. Names used across Tasks 10–13: `useSessionActivity`, `useActivityFormat`, `FormatContext`, `activityValue`, `activityWhen`, `activityActor`, `activityAction`, `createdLine`, `SessionActivity`, `RevertDialog`, `schedulingApi.activity`, `schedulingApi.revertActivity`, `activityEntry`, `activityLog`.
- **Review Focus:** five lines, each with its test in the owning task (Tasks 3, 6, 7); the dashboard half of the last one (a second press) is Task 12's "translates the 409 `scheduling.changed_since` and keeps the dialog open".
