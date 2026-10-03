# Plan 21 — Times and Postponement (slice B2b) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B2a (merged before this plan starts; no other phase's slice).
**Slice:** B2b · **Phase spec:** docs/superpowers/specs/2026-10-03-b2-scheduling-depth-design.md

**Goal:** Teachers and the office record in / out times and the minutes actually taught; a session can be postponed — by its student, a parent or its teacher until a set time before it starts, by the office at any time — and the weekly timetable never recreates it at the old time. Both behind per-academy switches that are off by default.

**Architecture:**
- **Data.** `scheduling.Session` gains the four in / out instants, `actual_minutes`, and the postponement origin (`original_slot`, `original_on`, `original_starts_at`, `postponed_by`, `postponed_at`). One additive migration `0007_times_postponement`. `academy.AcademySettings` gains `postpone_limit_minutes` (migration `academy 0007_postpone_limit`, under a ledger claim).
- **Rules.** One helper `rules.regenerable(**filters)` (untouched, generated, never postponed) replaces the regenerating callers' filters; cancel and expiry keep B2a's `kind=regular`. Generation adds a second "already taken" set `(original_slot, original_on)`. The Today board learns `postponed` and slotless rows.
- **Services.** New `services/times.py` (`record_times`) and `services/postpone.py` (`postpone_session`, `can_postpone`); `subscriptions.py` moves postponed sessions on a teacher change and onto a renewal.
- **API.** `POST sessions/<id>/times/` (`session_times`), `POST sessions/<id>/postpone/` (`postponement`), new payload fields, `postpone_limit_minutes` in `academy/settings/`, Today rows with an optional slot.
- **Dashboard.** A Times panel and a Postpone dialog on the session page; "I'm in" / "I'm out" and Postpone for teachers; Postpone for students and parents; the `postponed` board state; the limit in Settings → Academy.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next, Radix UI; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-03-b2b-times-postponement-design.md` (slice B2b of the phase spec). It builds on B2a (`docs/superpowers/specs/2026-10-03-b2a-session-classes-design.md`, Plan 17), Plan 4 (generation, untouched sessions, the board, lock order), Plan 5 (the start gate), Plan 7 (payroll lock), Plan 12a/b (codes, supervision), Plan 13 (switches). Where this plan fills a gap in the spec, the Decisions below say so.

## Global Constraints

**Repos and branches**
- Meta worktree: `/home/abdulkhalek/Projects/etqan_tutor-wt/b2` (`$W`). Meta, `backend/` and `dashboard/` are on `feat/b2b-postponement`, created by the controller off `origin/master` (meta) and `origin/main` (submodules) after B2a merged. `marketing/` is untouched.
- Commit in the submodule that owns the file (`git -C $W/backend …`, `git -C $W/dashboard …`). Never run `git submodule update` (or any writing `git submodule` subcommand) in this worktree.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Never edit `STATE.md`, CI workflows, Caddyfiles, or meta's submodule pointers.

**Commands (the slot-1 stack must be up: `just dev-backend`)**
- From `$W`, load the stream's environment first: `cd /home/abdulkhalek/Projects/etqan_tutor-wt/b2; set -a; . ./.env.stream; set +a`. Then run docker compose **directly** (a `$DC` variable does not word-split in zsh):
  - Backend tests: `docker compose -f docker-compose.local.yml exec -T django pytest -q <paths>` (add `--create-db` once after a migration).
  - Backend format: `docker compose -f docker-compose.local.yml exec -T django ruff check --fix .` then `… exec -T django ruff format .`
  - Backend verify: `… exec -T django ruff check .`, `… exec -T django ruff format --check .`, `… exec -T django lint-imports`, `… exec -T django pytest -q --cov=etqan`
  - Migrations: `… exec -T django python manage.py makemigrations scheduling --name times_postponement` (Task 1), `… makemigrations academy --name postpone_limit` (Task 2).
  - Dashboard tests: `… exec -T dashboard pnpm exec vitest run <paths>`; verify: `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`, `… exec -T dashboard pnpm test:coverage`.
  - Seeding this stream: `just _stack-manage migrate_schemas`, `just _stack-manage seed_dev`. E2E only through `just e2e …`.
  - Slice gates: `just test` (its backend recipe blanks `DJANGO_EMAIL_SUBJECT_PREFIX`), `just lint`, `just e2e`.
- There is no host `.venv` or `node_modules`; never run `manage.py`, `migrate` or pytest against any other database.
- Ruff selects `PL`, `FBT`, `DTZ`, `BLE`, `ERA`, `SLF`, `C901` (10), `E501` (88). Long keyword-only signatures carry `# noqa: PLR0913 -- keyword-only; mirrors the API body (spec §6)`.
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`: semantic colour tokens only. Biome rejects `role="group"` on a div: use `<fieldset>` + `<legend>`.

**Coverage and dev data**
- Gates: backend ≥ 80 %; dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`; `demo` admin `admin@demo.test`.

**Orchestration rules**
- Shared lists: lines only under `── phase B2 ──` (feature registry, `seed_dev`'s B2 block calls `etqan/tenants/seeds/b2.py`).
- `etqan.academy` is unowned: Task 2 holds a ledger claim for its one commit (exact commands in Task 2).
- New translation area: `dashboard/src/locales/{en,ar}/sessionTimes.json`, holding its keys directly (the catalogue wraps the file under `sessionTimes`). The `errors.scheduling` codes and `scheduling.today.state.*` labels are B2's and edited in place.
- New e2e spec: `dashboard/e2e/b2-postpone.spec.ts`, owning its data (as `b2-session-classes.spec.ts`).
- Migrations are additive (phase B2-16). Never `makemigrations --merge`; on a clash after a rebase, delete this plan's migration and regenerate it.
- Service signature changes are additive only.

**Lock order (binding, from B2a)**
- Subscriptions before sessions (Plan 4); sessions in pk order. A service that writes a session row referencing a subscription locks that subscription first (`manual.create_compensation` reads the id unlocked, locks the subscription, then the session, and re-checks the id).

**API and data rules (spec values verbatim)**
- 409 bodies `{detail, code}`. New codes: `scheduling.too_late_to_postpone`, `scheduling.teacher_busy`. Reused: `payroll.payslip_issued`, `scheduling.has_compensation`, `scheduling.not_allowed_in_status`, `scheduling.session_cancelled`, `scheduling.not_started`, `scheduling.slot_has_sessions`.
- A switched-off feature's routes answer `404 {"detail": "This feature is not enabled for this academy."}` after the permission check.
- Routes: `POST sessions/<id>/times/` (code `attendance.update` or the session's teacher; feature `session_times`); `POST sessions/<id>/postpone/` (code `session.update` or teacher / student / parent in scope; feature `postponement`; `200 {session, conflicts}`).
- `postpone_limit_minutes`: 0–10080, default 120.

### Decisions this plan makes where the spec is silent or leaves a choice

- **D1 — `by=None` is the system and acts as the office** (as B2a D4): the seeds call `record_times` and `postpone_session` with `by=None`.
- **D2 — `can_postpone` leaves the time limit to the dashboard.** The payload's `can_postpone` is every row-local B-6 / B-7 condition (role and scope, status, attendance, times, supervisor attendance, payroll lock, compensated, a regular session's subscription live). The time limit needs the academy's setting; reading it once per row would be one query per row, so the dashboard — which already loads `academy/settings/` for everyone — applies `now ≤ starts_at − postpone_limit_minutes` for non-office viewers. The server enforces everything on submit.
- **D3 — `postpone_limit_minutes` is always in `academy/settings/`**; Settings → Academy shows the field only with `postponement` on.
- **D4 — `SESSION_RELATED` gains `subscription`** so `can_postpone` reads the subscription's status without a query per row.
- **D5 — The Today board's `TodayRow` gains `start_time` and `minutes`** (local wall-clock and length of the row, from the slot or the session), so slotless rows need no slot; the payload reads them from the row. Slotless rows are only for postponed sessions with a subscription (an extra session without one has no board place, as before).
- **D6 — Renewal moves postponed sessions before expiring the old subscription.** `renew_subscription` used to expire the old subscription (when the renewal starts today or earlier) before creating the renewal; expiry deletes untouched regular sessions, postponed ones included. The order becomes: delete the old generated overlap, create the renewal, move the old subscription's postponed unmarked sessions dated on or after the renewal's start onto it, then expire the old one.
- **D7 — One helper for "the system may regenerate over this":** `rules.regenerable(**filters) = untouched_sessions(generated=True, postponed_at__isnull=True, **filters)`; `_regenerate`, `_refill`, `add_pause`, `update_slot` and the renewal overlap use it.
- **D8 — A postponement moved back re-attaches only when the slot is free** on `original_on` (an earlier release may have generated it); otherwise it stays postponed at that time (no 500).

## Review Focus

- **A postponed session around a renewal.** Expected: a regular session postponed inside the old term to a date on or after an early renewal's start moves onto the renewal, keeps its teacher and course, and survives the old subscription's expiry; one before the renewal's start stays and is removed only if untouched when the old subscription ends. Tests: Task 5 `test_a_renewal_takes_postponed_sessions_dated_from_its_start`, `test_an_immediate_renewal_moves_them_before_expiring_the_old_one`.
- **DST on the new time.** Expected: Plan 4's single conversion — a non-existent local time moves forward, an ambiguous one takes the first occurrence. Test: Task 4 `test_a_postponement_onto_a_clock_change_uses_plans_4_conversion`.
- **The limit boundary for each role.** Expected: at exactly `starts_at − limit` a student, a parent and the teacher may still postpone; one second later 409 `too_late_to_postpone`; the office any time. Test: Task 4 `test_the_limit_boundary_for_each_role` (parametrised).
- **An old-release duplicate on re-attach.** Expected: moving back to a slot date an older release already generated leaves the session postponed at that time, no IntegrityError. Test: Task 4 `test_moving_back_onto_a_regenerated_slot_date_stays_postponed`.
- **A move across a month boundary.** Expected: `occurs_on` follows the new date, so `payroll_sessions` for the new month includes it and the old month's doesn't. Test: Task 4 `test_payroll_reads_the_month_it_moved_into`.

---

## File Structure

```
backend/
  etqan/platform/features.py                    session_times, postponement under ── phase B2 ── (Task 1)
  etqan/scheduling/
    models.py                                    Session: times, actual_minutes, postponement origin (Task 1)
    migrations/0007_times_postponement.py        generated (Task 1)
    services/rules.py                            regenerable(), SESSION_RELATED + subscription,
                                                 slots_of counts postponed sessions (Tasks 5, 7)
    services/times.py                            NEW: record_times (Task 3)
    services/postpone.py                         NEW: postpone_session, can_postpone, Postponed (Task 4)
    services/generation.py                       the (original_slot, original_on) skip set (Task 5)
    services/subscriptions.py                    regenerable callers, delete_slot, teacher change,
                                                 renewal move (Task 5)
    services/board.py                            postponed state, slotless rows (Task 6)
    services/__init__.py                         exports (Tasks 3–6)
    api/serializers.py payloads.py session_views.py urls.py   (Tasks 6, 7)
    tests/test_times_postponement_*.py           NEW (Tasks 1, 3–7)
  etqan/academy/models.py services.py api/serializers.py migrations/0007_postpone_limit.py
    tests/test_api.py                            postpone_limit_minutes (Task 2)
  etqan/access/tests/test_routes.py              ROUTES, FEATURES, FEATURE_WORDS (Task 7)
  etqan/tenants/seeds/b2.py tests/test_seed_b2.py  seed_times_postponement (Task 8)
  etqan/tenants/management/commands/seed_dev.py  one call in the B2 block (Task 8)
dashboard/
  src/features/identity/schemas.ts               FeatureCode (Task 9)
  src/features/academy/api.ts AcademySettingsForm.tsx (+test)   the limit (Task 12)
  src/features/scheduling/
    schemas.ts api.ts                            times, postpone, TodayRow (Task 9)
    TodayBoard.tsx                               postponed state, slotless rows (Task 9)
    postponing.ts                                NEW: mayPostpone(session, me, limit, now) (Task 9)
    TimesPanel.tsx PostponeDialog.tsx            NEW (Task 10)
    SessionPage.tsx                              Times panel, Postpone, "Postponed from" (Task 10)
    TeacherSessionTable.tsx FamilySessions.tsx   I'm in / I'm out, Postpone (Task 11)
  src/test/scheduling-fixtures.ts                sessionRow / todayRow defaults (Task 9)
  src/locales/{en,ar}/sessionTimes.json          NEW (Task 9)
  src/locales/{en,ar}/scheduling.json errors.json academySettings.json   (Tasks 9, 12)
  e2e/b2-postpone.spec.ts                        NEW (Task 13)
```

---

### Task 1: The switches, the Session columns and the migration

**Files:**
- Modify: `backend/etqan/platform/features.py` (under `# ── phase B2 ──`, after B2a's four)
- Modify: `backend/etqan/scheduling/models.py` (`Session`)
- Create: `backend/etqan/scheduling/migrations/0007_times_postponement.py` (generated)
- Test: `backend/etqan/scheduling/tests/test_times_postponement_model.py`

**Interfaces:**
- Produces: feature codes `session_times`, `postponement` (built, default off, group `teaching`). Session fields `teacher_in_at`, `teacher_out_at`, `student_in_at`, `student_out_at`, `actual_minutes`, `original_slot` / `original_slot_id` (reverse `postponed_sessions` on ScheduleSlot), `original_on`, `original_starts_at`, `postponed_by`, `postponed_at`. Constraints `scheduling_teacher_out_after_in`, `scheduling_student_out_after_in`, `scheduling_postponed_origin_pair`, `scheduling_postponed_origin_unique`.

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2b §3.1 and B-14: the switches, the new Session columns and their
constraints."""

from datetime import date
from datetime import timedelta

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.platform import features
from etqan.scheduling import dates
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import START
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
B2B = ("session_times", "postponement")


@pytest.mark.parametrize("code", B2B)
def test_each_is_a_built_switch_off_by_default(code):
    feature = features.get(code)
    assert (feature.built, feature.default, feature.group) == (True, False, "teaching")
    assert features.is_on(code, {}) is False


def test_they_follow_b2as_switches():
    codes = [feature.code for feature in features.REGISTRY]
    assert codes.index("disposal_status") < codes.index("session_times")
    assert codes.index("session_times") < codes.index("postponement")


def _one(subscribe):
    sub = subscribe(slots=two_slots())
    return sub, Session.objects.filter(subscription=sub).order_by("starts_at").first()


def test_new_columns_default_to_empty(subscribe):
    _sub, session = _one(subscribe)
    assert session.teacher_in_at is None
    assert session.actual_minutes is None
    assert session.original_slot_id is None
    assert session.postponed_at is None


@pytest.mark.parametrize("who", ["teacher", "student"])
def test_out_before_in_is_refused_by_the_database(subscribe, who):
    _sub, session = _one(subscribe)
    setattr(session, f"{who}_in_at", START)
    setattr(session, f"{who}_out_at", START - timedelta(minutes=1))
    with pytest.raises(IntegrityError), transaction.atomic():
        session.save()


def test_origin_slot_and_date_go_together(subscribe):
    _sub, session = _one(subscribe)
    session.original_slot = session.slot
    with pytest.raises(IntegrityError), transaction.atomic():
        session.save()


def test_one_postponed_session_per_slot_date(subscribe):
    sub, first = _one(subscribe)
    second = Session.objects.filter(subscription=sub).order_by("starts_at")[1]
    day = date(2026, 6, 1)
    first.original_slot, first.original_on, first.slot = first.slot, day, None
    first.postponed_at = dates.now()
    first.save()
    second.original_slot, second.original_on, second.slot = first.original_slot, day, None
    with pytest.raises(IntegrityError), transaction.atomic():
        second.save()
```

- [ ] **Step 2: Run them to see them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest -q etqan/scheduling/tests/test_times_postponement_model.py`
Expected: FAIL (`LookupError: Unknown feature: 'session_times'`, `AttributeError` on the new fields).

- [ ] **Step 3: Register the switches**

In `backend/etqan/platform/features.py`, after B2a's `disposal_status` entry and before `# ── phase B3 ──`:

```python
    # Slice B2b (Plan 21): in / out times and postponement, off by default.
    Feature(
        "session_times",
        "In / out times",
        "أوقات الدخول والخروج",
        "teaching",
        built=True,
    ),
    Feature(
        "postponement",
        "Session postponement",
        "تأجيل الحصص",
        "teaching",
        built=True,
    ),
```

- [ ] **Step 4: Add the columns and constraints**

In `backend/etqan/scheduling/models.py`, in `Session`, after `disposal_reason`:

```python
    # Slice B2b (spec §3.1): who came in and left when, and the minutes the
    # teacher actually taught — a record only; pay and consumption stay on
    # `minutes` (B-3).
    teacher_in_at = models.DateTimeField(null=True, blank=True)
    teacher_out_at = models.DateTimeField(null=True, blank=True)
    student_in_at = models.DateTimeField(null=True, blank=True)
    student_out_at = models.DateTimeField(null=True, blank=True)
    actual_minutes = models.PositiveSmallIntegerField(
        null=True,
        blank=True,
        validators=[MinValueValidator(1), MaxValueValidator(600)],
    )
    # Slice B2b (B-4): a postponed session leaves its slot and remembers the
    # slot date it came from, so generation never recreates it there.
    original_slot = models.ForeignKey(
        ScheduleSlot,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="postponed_sessions",
    )
    original_on = models.DateField(null=True, blank=True)
    original_starts_at = models.DateTimeField(null=True, blank=True)
    postponed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    postponed_at = models.DateTimeField(null=True, blank=True)
```

and in `Session.Meta.constraints`, append:

```python
            # Slice B2b §3.1.
            models.CheckConstraint(
                condition=Q(teacher_in_at__isnull=True)
                | Q(teacher_out_at__isnull=True)
                | Q(teacher_out_at__gte=F("teacher_in_at")),
                name="scheduling_teacher_out_after_in",
            ),
            models.CheckConstraint(
                condition=Q(student_in_at__isnull=True)
                | Q(student_out_at__isnull=True)
                | Q(student_out_at__gte=F("student_in_at")),
                name="scheduling_student_out_after_in",
            ),
            models.CheckConstraint(
                condition=Q(original_slot__isnull=True, original_on__isnull=True)
                | Q(original_slot__isnull=False, original_on__isnull=False),
                name="scheduling_postponed_origin_pair",
            ),
            models.UniqueConstraint(
                fields=["original_slot", "original_on"],
                condition=Q(original_slot__isnull=False),
                name="scheduling_postponed_origin_unique",
            ),
```

- [ ] **Step 5: Generate the migration**

Run: `docker compose -f docker-compose.local.yml exec -T django python manage.py makemigrations scheduling --name times_postponement`
Expected: `0007_times_postponement.py` with 10 `AddField` and 4 `AddConstraint`, no `RunPython`, every column nullable. Then `… exec -T django python manage.py migrate_schemas` is NOT needed (pytest builds its own DB); run the tests with `--create-db`.

- [ ] **Step 6: Run the tests**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest -q --create-db etqan/scheduling/tests/test_times_postponement_model.py etqan/platform/tests/test_features.py etqan/academy/tests/test_features_api.py`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/platform/features.py etqan/scheduling/models.py etqan/scheduling/migrations/0007_times_postponement.py etqan/scheduling/tests/test_times_postponement_model.py
git -C backend commit -m "feat(scheduling): in/out times and postponement columns behind two switches (B2b)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The postponement limit in the academy's settings (under a claim)

**Files:**
- Modify: `backend/etqan/academy/models.py`, `backend/etqan/academy/services.py`, `backend/etqan/academy/api/serializers.py`
- Create: `backend/etqan/academy/migrations/0007_postpone_limit.py` (generated)
- Test: `backend/etqan/academy/tests/test_api.py` (append)

**Interfaces:**
- Produces: `AcademySettings.postpone_limit_minutes` (int, default 120); `academy_services.update_settings(..., postpone_limit_minutes=...)`; `academy/settings/` reads and writes `postpone_limit_minutes`.

- [ ] **Step 1: Take the claim**

Run (from `$W`): `python3 scripts/orchestration/ledger.py claim B2 academy --reason "B2b: AcademySettings.postpone_limit_minutes"`
Expected: the ledger shows the claim.

- [ ] **Step 2: Write the failing tests** (append to `backend/etqan/academy/tests/test_api.py`, reusing its existing admin client fixture — read the file's fixtures first and use the same names)

```python
def test_the_postponement_limit_defaults_to_120_minutes(admin_client):
    assert admin_client.get(URL).json()["postpone_limit_minutes"] == 120


@pytest.mark.parametrize("value", [0, 120, 10080])
def test_the_office_sets_the_limit(admin_client, value):
    response = admin_client.patch(URL, {"postpone_limit_minutes": value}, format="json")
    assert response.status_code == 200
    assert response.json()["postpone_limit_minutes"] == value


@pytest.mark.parametrize("value", [-1, 10081])
def test_the_limit_is_bounded(admin_client, value):
    response = admin_client.patch(URL, {"postpone_limit_minutes": value}, format="json")
    assert response.status_code == 400
    assert "postpone_limit_minutes" in response.json()
```

(If the file's admin fixture or `URL` constant has another name, use it; the assertions stay.)

- [ ] **Step 3: Run to see them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest -q etqan/academy/tests/test_api.py -k limit`
Expected: FAIL (`KeyError: 'postpone_limit_minutes'`).

- [ ] **Step 4: Implement**

`models.py`, in `AcademySettings` after `invoice_due_days`:

```python
    # Slice B2b (B-11): students, parents and teachers may postpone a session
    # until this many minutes before it starts.
    postpone_limit_minutes = models.PositiveIntegerField(
        default=120,
        db_default=120,
        validators=[MinValueValidator(0), MaxValueValidator(10080)],
    )
```

`services.py`: add `POSTPONE_LIMIT = (0, 10080)` next to the other bounds; add the keyword `postpone_limit_minutes: int | None = None` to `update_settings` and, after `invoice_due_days`:

```python
    if postpone_limit_minutes is not None:
        settings_row.postpone_limit_minutes = _days(
            postpone_limit_minutes, POSTPONE_LIMIT, "postpone_limit_minutes"
        )
```

`api/serializers.py`, after `invoice_due_days`:

```python
    postpone_limit_minutes = serializers.IntegerField(
        min_value=0, max_value=10080, required=False
    )
```

- [ ] **Step 5: Generate the migration and run the tests**

Run: `… exec -T django python manage.py makemigrations academy --name postpone_limit`, then `… pytest -q --create-db etqan/academy`
Expected: one `AddField` with `db_default=120`; PASS.

- [ ] **Step 6: Commit, then release the claim**

```bash
git -C backend add etqan/academy/models.py etqan/academy/services.py etqan/academy/api/serializers.py etqan/academy/migrations/0007_postpone_limit.py etqan/academy/tests/test_api.py
git -C backend commit -m "feat(academy): the postponement limit setting (B2b)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B2 academy
```

---

### Task 3: Recording in / out times (`services/times.py`)

**Files:**
- Create: `backend/etqan/scheduling/services/times.py`
- Modify: `backend/etqan/scheduling/services/__init__.py`
- Test: `backend/etqan/scheduling/tests/test_times_postponement_times.py`

**Interfaces:**
- Consumes: Task 1's columns; `attendance.lock`, `paylock.refuse_if_paid`, `attendance.has_started`.
- Produces: `record_times(session: Session, *, by, fields: dict) -> Session` (exported). `fields` holds any of `teacher_in_at`, `teacher_out_at`, `student_in_at`, `student_out_at` (datetime or None) and `actual_minutes` (int or None). `EARLY_STAMP = timedelta(minutes=15)`, `MAX_SPAN_MINUTES = 600`.

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2b §4.1: in / out times."""

from datetime import timedelta

import pytest

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ForbiddenError
from etqan.platform.exceptions import PermissionDeniedError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db


@pytest.fixture
def session(subscribe, clock):
    sub = subscribe(slots=two_slots())
    return Session.objects.filter(subscription=sub).order_by("starts_at").first()


@pytest.fixture
def started(session, clock):
    clock.set(session.starts_at + timedelta(minutes=5))
    return session


def teacher_of(session):
    return session.teacher.user


def test_the_teacher_stamps_in_and_out_and_minutes_follow(started, clock, set_features):
    set_features(teacher_attendance=True)
    t = teacher_of(started)
    services.record_times(started, by=t, fields={"teacher_in_at": started.starts_at})
    out = started.starts_at + timedelta(minutes=44, seconds=40)
    done = services.record_times(started, by=t, fields={"teacher_out_at": out})
    assert done.actual_minutes == 45


def test_typed_minutes_are_never_overwritten(started):
    office = make_admin()
    services.record_times(started, by=office, fields={"actual_minutes": 30})
    done = services.record_times(
        started,
        by=office,
        fields={
            "teacher_in_at": started.starts_at,
            "teacher_out_at": started.starts_at + timedelta(minutes=50),
        },
    )
    assert done.actual_minutes == 30


def test_the_teacher_may_stamp_in_15_minutes_early_only(session, clock):
    t = teacher_of(session)
    clock.set(session.starts_at - timedelta(minutes=15))
    services.record_times(session, by=t, fields={"teacher_in_at": clock_now(clock)})
    clock.set(session.starts_at - timedelta(minutes=16))
    with pytest.raises(ConflictError) as err:
        services.record_times(session, by=t, fields={"teacher_out_at": None})
    assert err.value.code == "scheduling.not_started"


def clock_now(_clock):
    from etqan.scheduling import dates  # noqa: PLC0415

    return dates.now()


def test_the_office_waits_for_the_start(session):
    with pytest.raises(ConflictError) as err:
        services.record_times(
            session, by=make_admin(), fields={"student_in_at": session.starts_at}
        )
    assert err.value.code == "scheduling.not_started"


def test_a_teacher_sets_only_the_teacher_pair(started):
    with pytest.raises(PermissionDeniedError):
        services.record_times(
            started, by=teacher_of(started), fields={"student_in_at": started.starts_at}
        )
    with pytest.raises(PermissionDeniedError):
        services.record_times(
            started, by=teacher_of(started), fields={"actual_minutes": 10}
        )


def test_a_teacher_needs_teacher_attendance_on(started, set_features):
    set_features(teacher_attendance=False)
    with pytest.raises(ForbiddenError):
        services.record_times(
            started, by=teacher_of(started), fields={"teacher_in_at": started.starts_at}
        )


def test_out_before_in_is_a_400_on_the_out_field(started):
    with pytest.raises(ValidationError) as err:
        services.record_times(
            started,
            by=make_admin(),
            fields={
                "student_in_at": started.starts_at,
                "student_out_at": started.starts_at - timedelta(minutes=1),
            },
        )
    assert err.value.field == "student_out_at"


def test_a_span_over_600_minutes_is_refused(started):
    with pytest.raises(ValidationError) as err:
        services.record_times(
            started,
            by=make_admin(),
            fields={
                "teacher_in_at": started.starts_at,
                "teacher_out_at": started.starts_at + timedelta(minutes=601),
            },
        )
    assert err.value.field == "teacher_out_at"


def test_refused_on_a_cancelled_or_paid_session(started):
    office = make_admin()
    services.cancel_session(started, by=office, reason="Eid")
    with pytest.raises(ConflictError) as err:
        services.record_times(started, by=office, fields={"actual_minutes": 5})
    assert err.value.code == "scheduling.session_cancelled"
    services.restore_session(started)
    Session.objects.filter(pk=started.pk).update(payroll_locked=True)
    with pytest.raises(ConflictError) as err:
        services.record_times(started, by=office, fields={"actual_minutes": 5})
    assert err.value.code == "payroll.payslip_issued"


def test_times_never_change_status_or_attendance(started):
    done = services.record_times(
        started, by=make_admin(), fields={"teacher_in_at": started.starts_at}
    )
    assert (done.status, done.student_attendance) == ("scheduled", "not_set")
```

(`set_features` is the existing scheduling fixture used by `test_features.py`; check its name in `conftest.py`/root `conftest.py` and reuse it.)

- [ ] **Step 2: Run to see them fail**

Run: `… pytest -q etqan/scheduling/tests/test_times_postponement_times.py`
Expected: FAIL (`AttributeError: module ... has no attribute 'record_times'`).

- [ ] **Step 3: Implement `services/times.py`**

```python
"""In / out times and the minutes actually taught (slice B2b §4.1). A record
only: status, attendance, consumption and pay never read them (B-3)."""

from datetime import timedelta

from django.db import transaction

from etqan.platform import features
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ForbiddenError
from etqan.platform.exceptions import PermissionDeniedError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import is_office
from etqan.scheduling import dates
from etqan.scheduling.models import Session
from etqan.scheduling.services.attendance import TEACHER_ATTENDANCE_OFF
from etqan.scheduling.services.attendance import has_started
from etqan.scheduling.services.attendance import lock
from etqan.scheduling.services.paylock import refuse_if_paid

TEACHER_FIELDS = ("teacher_in_at", "teacher_out_at")
ALL_FIELDS = (*TEACHER_FIELDS, "student_in_at", "student_out_at", "actual_minutes")
PAIRS = (("teacher_in_at", "teacher_out_at"), ("student_in_at", "student_out_at"))
EARLY_STAMP = timedelta(minutes=15)
MAX_SPAN_MINUTES = 600
SECONDS_PER_MINUTE = 60


def _office(by) -> bool:
    # Plan 21 D1: `by=None` is the system, which acts as the office.
    return by is None or is_office(by)


def _gate(session: Session, fields: dict, *, office: bool) -> None:
    """B-2: the start gate, except the teacher's own early "I'm in"."""
    if has_started(session):
        return
    early = (
        not office
        and set(fields) == {"teacher_in_at"}
        and fields["teacher_in_at"] is not None
        and dates.now() >= session.starts_at - EARLY_STAMP
    )
    if not early:
        raise ConflictError(
            "Times open when the session starts.", code="scheduling.not_started"
        )


def _check_pairs(session: Session) -> None:
    for start, end in PAIRS:
        came, left = getattr(session, start), getattr(session, end)
        if came is not None and left is not None and left < came:
            raise ValidationError("Leaving can't be before coming in.", field=end)
    came, left = session.teacher_in_at, session.teacher_out_at
    if (
        came is not None
        and left is not None
        and left - came > timedelta(minutes=MAX_SPAN_MINUTES)
    ):
        raise ValidationError(
            f"That is more than {MAX_SPAN_MINUTES} minutes.", field="teacher_out_at"
        )


@transaction.atomic
def record_times(session: Session, *, by, fields: dict) -> Session:
    """Set or clear any of the four instants and the actual minutes. The
    teacher sets only the teacher pair (and needs teacher attendance on);
    the office sets everything. Refused on a paid or cancelled session and
    before the start gate. While `actual_minutes` is empty and not sent, it
    follows the teacher's in and out."""
    office = _office(by)
    unknown = set(fields) - set(ALL_FIELDS)
    if unknown or not fields:
        raise ValidationError("Send a time to record.", field="teacher_in_at")
    if not office:
        if not features.enabled("teacher_attendance"):
            raise ForbiddenError(TEACHER_ATTENDANCE_OFF)
        if set(fields) - set(TEACHER_FIELDS):
            raise PermissionDeniedError("record the student's times")
    locked = lock(session)
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

Export from `services/__init__.py`: `from etqan.scheduling.services.times import record_times` and add `"record_times"` to `__all__` (alphabetical).

- [ ] **Step 4: Run the tests**

Run: `… pytest -q etqan/scheduling/tests/test_times_postponement_times.py` → PASS. Then `… ruff check . && … ruff format --check . && … lint-imports`.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/scheduling/services/times.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_times_postponement_times.py
git -C backend commit -m "feat(scheduling): record in/out times and actual minutes (B2b)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Postponing a session (`services/postpone.py`)

**Files:**
- Create: `backend/etqan/scheduling/services/postpone.py`
- Modify: `backend/etqan/scheduling/services/__init__.py`
- Test: `backend/etqan/scheduling/tests/test_times_postponement_postpone.py`

**Interfaces:**
- Consumes: Tasks 1–3; `rules.term`, `rules.generation_last_day`, `rules.covering_pause`, `rules.LIVE`, `rules.ENDS_AT`, `generation.conflicts`, `attendance.lock`, `attendance.refuse_if_compensated`, `paylock.refuse_if_paid`.
- Produces (exported):
  - `Postponed` — frozen dataclass `(session: Session, conflicts: list[tuple[Session, Session]])`; `session` read from `sessions_queryset()`; `conflicts` empty for a non-office caller.
  - `postpone_session(session: Session, *, by, occurs_on: date, start_time: time) -> Postponed`
  - `can_postpone(session: Session, viewer) -> bool` — the row-local check (D2), no query when `session.subscription` is select-related.
  - `MAX_MOVE = timedelta(days=14)`.

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2b §4.2: postponement."""

from datetime import date
from datetime import time
from datetime import timedelta

import pytest

from etqan.academy import services as academy_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import dates
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import START
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db


@pytest.fixture
def sub(subscribe):
    return subscribe(slots=two_slots())


def upcoming(sub, index=1):
    return Session.objects.filter(subscription=sub).order_by("starts_at")[index]


def move(session, by, day, at=time(20, 0)):
    return services.postpone_session(session, by=by, occurs_on=day, start_time=at)


def test_the_office_moves_a_slot_session_and_its_slot_date_is_remembered(sub):
    session = upcoming(sub)  # Wednesday 3 June, 18:00
    slot, day, first = session.slot, session.occurs_on, session.starts_at
    result = move(session, make_admin(), date(2026, 6, 4))
    moved = result.session
    assert (moved.slot_id, moved.original_slot_id, moved.original_on) == (
        None,
        slot.pk,
        day,
    )
    assert moved.original_starts_at == first
    assert moved.occurs_on == date(2026, 6, 4)
    assert moved.postponed_at is not None


def test_repeated_moves_keep_the_first_origin(sub):
    session = upcoming(sub)
    first, day = session.starts_at, session.occurs_on
    move(session, make_admin(), date(2026, 6, 4))
    again = move(session, make_admin(), date(2026, 6, 5)).session
    assert (again.original_on, again.original_starts_at) == (day, first)


def test_moving_back_re_attaches_it(sub):
    session = upcoming(sub)
    slot, day = session.slot, session.occurs_on
    move(session, make_admin(), date(2026, 6, 4))
    back = move(session, make_admin(), day, slot.start_time).session
    assert back.slot_id == slot.pk
    assert (back.original_slot_id, back.postponed_at, back.original_starts_at) == (
        None,
        None,
        None,
    )


def test_moving_back_onto_a_regenerated_slot_date_stays_postponed(sub):
    session = upcoming(sub)
    slot, day = session.slot, session.occurs_on
    move(session, make_admin(), date(2026, 6, 4))
    # An older release generated the slot date meanwhile.
    Session.objects.create(
        slot=slot,
        subscription=sub,
        student_id=sub.student_id,
        teacher_id=sub.teacher_id,
        course_id=sub.course_id,
        occurs_on=day,
        starts_at=session.original_starts_at or START,
        minutes=45,
        generated=True,
    )
    back = move(session, make_admin(), day, slot.start_time).session
    assert back.slot_id is None
    assert back.postponed_at is not None


@pytest.mark.parametrize("role", ["student", "parent", "teacher"])
def test_the_limit_boundary_for_each_role(sub, clock, role):
    session = upcoming(sub)
    who = {
        "student": session.student.user,
        "teacher": session.teacher.user,
        "parent": _parent_of(session),
    }[role]
    limit = timedelta(minutes=academy_services.get_settings().postpone_limit_minutes)
    clock.set(session.starts_at - limit)
    move(session, who, session.occurs_on + timedelta(days=1))
    later = upcoming(sub, 2)
    clock.set(later.starts_at - limit + timedelta(seconds=1))
    with pytest.raises(ConflictError) as err:
        move(later, who, later.occurs_on + timedelta(days=1))
    assert err.value.code == "scheduling.too_late_to_postpone"


def _parent_of(session):
    parent = identity_services.create_person("parent", full_name="Omar")
    identity_services.link_guardian(student_id=session.student.user_id, parent_id=parent.id)
    return parent


def test_the_office_has_no_limit(sub, clock):
    session = upcoming(sub)
    clock.set(session.starts_at - timedelta(minutes=1))
    assert move(session, make_admin(), date(2026, 6, 4)).session.postponed_at


def test_non_office_lead_time_and_cap(sub, clock):
    session = upcoming(sub)
    student = session.student.user
    clock.set(session.starts_at - timedelta(days=1))
    soon = dates.now() + timedelta(minutes=30)
    with pytest.raises(ValidationError) as err:
        services.postpone_session(
            session, by=student, occurs_on=soon.date(), start_time=soon.time()
        )
    assert err.value.field == "occurs_on"
    with pytest.raises(ValidationError):
        move(session, student, session.occurs_on + timedelta(days=15))


def test_a_busy_teacher_refuses_non_office_and_is_reported_to_the_office(sub, world):
    session = upcoming(sub)
    other = upcoming(sub, 3)
    at = dates.to_utc(other.occurs_on, time(18, 0), "UTC")
    with pytest.raises(ConflictError) as err:
        services.postpone_session(
            session, by=session.student.user, occurs_on=other.occurs_on,
            start_time=at.time(),
        )
    assert err.value.code == "scheduling.teacher_busy"
    office = services.postpone_session(
        session, by=make_admin(), occurs_on=other.occurs_on, start_time=at.time()
    )
    assert [o.pk for _s, o in office.conflicts] == [other.pk]


@pytest.mark.parametrize(
    ("setup", "code"),
    [
        (lambda s: Session.objects.filter(pk=s.pk).update(payroll_locked=True), "payroll.payslip_issued"),
        (lambda s: Session.objects.filter(pk=s.pk).update(compensated=True), "scheduling.has_compensation"),
        (lambda s: Session.objects.filter(pk=s.pk).update(status="cancelled"), "scheduling.not_allowed_in_status"),
        (lambda s: Session.objects.filter(pk=s.pk).update(teacher_in_at=s.starts_at), "scheduling.not_allowed_in_status"),
        (lambda s: Session.objects.filter(pk=s.pk).update(supervisor_attendance="present"), "scheduling.not_allowed_in_status"),
    ],
)
def test_refusals(sub, setup, code):
    session = upcoming(sub)
    setup(session)
    with pytest.raises(ConflictError) as err:
        move(session, make_admin(), date(2026, 6, 4))
    assert err.value.code == code


def test_a_regular_session_stays_inside_its_window_and_out_of_pauses(sub):
    session = upcoming(sub)
    services.add_pause(sub, from_date=date(2026, 6, 10), to_date=date(2026, 6, 11))
    with pytest.raises(ValidationError):
        move(session, make_admin(), date(2026, 6, 10))
    with pytest.raises(ValidationError):
        move(session, make_admin(), date(2026, 5, 31))


def test_a_new_start_in_the_past_is_a_400(sub, clock):
    session = upcoming(sub)
    clock.set(session.starts_at - timedelta(hours=1))
    with pytest.raises(ValidationError):
        move(session, make_admin(), START.date(), time(7, 0))


def test_a_make_up_or_extra_session_has_no_window(sub):
    extra = hand_session(sub, occurs_on=date(2026, 6, 5), kind="extra")
    assert move(extra, make_admin(), date(2026, 8, 30)).session.occurs_on == date(2026, 8, 30)


def test_a_postponement_onto_a_clock_change_uses_plans_4_conversion(sub):
    academy_services.update_settings(timezone="Europe/Berlin")
    extra = hand_session(sub, occurs_on=date(2026, 6, 5), kind="extra")
    # 02:30 does not exist in Berlin on 28 March 2027: it moves forward.
    moved = move(extra, make_admin(), date(2027, 3, 28), time(2, 30)).session
    assert moved.starts_at == dates.to_utc(date(2027, 3, 28), time(2, 30), "Europe/Berlin")


def test_payroll_reads_the_month_it_moved_into(sub):
    extra = hand_session(sub, occurs_on=date(2026, 6, 29), kind="extra")
    move(extra, make_admin(), date(2026, 7, 2))
    june = services.payroll_sessions(date(2026, 6, 1), date(2026, 6, 30))
    july = services.payroll_sessions(date(2026, 7, 1), date(2026, 7, 31))
    assert extra.pk not in {s.pk for s in june}
    assert extra.pk in {s.pk for s in july}


def test_it_locks_the_subscription_before_the_session(sub):
    from django.db import connection  # noqa: PLC0415
    from django.test.utils import CaptureQueriesContext  # noqa: PLC0415

    session = upcoming(sub)
    with CaptureQueriesContext(connection) as queries:
        move(session, make_admin(), date(2026, 6, 4))
    locks = [q["sql"] for q in queries if "FOR UPDATE" in q["sql"]]
    assert '"scheduling_subscription"' in locks[0]
    assert '"scheduling_session"' in locks[1]


def test_can_postpone_reads_only_the_row(sub, django_assert_num_queries):
    row = services.sessions_queryset().get(pk=upcoming(sub).pk)
    with django_assert_num_queries(0):
        assert services.can_postpone(row, row.student.user) is True
        assert services.can_postpone(row, None) is False
```

(`identity_services.link_guardian` is the Plan 3 service that links a parent: check its exact name in `etqan/identity/services` and use it.)

- [ ] **Step 2: Run to see them fail**

Run: `… pytest -q etqan/scheduling/tests/test_times_postponement_postpone.py`
Expected: FAIL (no `postpone_session`).

- [ ] **Step 3: Implement `services/postpone.py`**

```python
"""Postponing a session (slice B2b §4.2). The session moves; a slot session
leaves its slot and remembers the slot date it came from, so generation never
recreates it (B-4). Locks: the subscription first, then the session (Plan 4);
the session's subscription id is read unlocked and re-checked."""

from dataclasses import dataclass
from datetime import date
from datetime import time
from datetime import timedelta

from django.db import transaction

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import is_office
from etqan.platform.permissions import role_of
from etqan.scheduling import dates
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.services import generation
from etqan.scheduling.services import rules
from etqan.scheduling.services.attendance import refuse_if_compensated
from etqan.scheduling.services.paylock import refuse_if_paid

MAX_MOVE = timedelta(days=14)
NOT_SET = Session.Attendance.NOT_SET
TIMES = ("teacher_in_at", "teacher_out_at", "student_in_at", "student_out_at")
OWN_ROLES = ("teacher", "student", "parent")


@dataclass(frozen=True)
class Postponed:
    session: Session
    conflicts: list[tuple[Session, Session]]


def _office(by) -> bool:
    # Plan 21 D1: `by=None` is the system, which acts as the office.
    return by is None or is_office(by)


def _postponable(session: Session) -> bool:
    """B-7's row conditions."""
    return (
        session.status == Session.Status.SCHEDULED
        and session.student_attendance == NOT_SET
        and session.teacher_attendance == NOT_SET
        and session.supervisor_attendance == NOT_SET
        and all(getattr(session, name) is None for name in TIMES)
    )


def can_postpone(session: Session, viewer) -> bool:
    """Plan 21 D2: everything B-6 / B-7 ask that the row itself holds. The
    time limit is the dashboard's to apply (and the server's on submit)."""
    if viewer is None or role_of(viewer) is None:
        return False
    if not (is_office(viewer) or role_of(viewer) in OWN_ROLES):
        return False
    if session.payroll_locked or session.compensated or not _postponable(session):
        return False
    if session.kind == Session.Kind.REGULAR:
        return session.subscription is not None and session.subscription.status in rules.LIVE
    return True


def _lock(session: Session) -> tuple[Session, Subscription | None]:
    sub_id = (
        Session.objects.filter(pk=session.pk)
        .values_list("subscription_id", flat=True)
        .first()
    )
    sub = (
        Subscription.objects.select_for_update().filter(pk=sub_id).first()
        if sub_id is not None
        else None
    )
    locked = Session.objects.select_for_update().filter(pk=session.pk).first()
    if locked is None:
        raise NotFoundError("Session", session.pk)
    if locked.subscription_id != sub_id:  # moved onto a renewal meanwhile
        return _lock(session)
    return locked, sub


def _refuse_state(locked: Session, sub: Subscription | None) -> None:
    refuse_if_paid(locked)
    refuse_if_compensated(locked)
    not_allowed = ConflictError(
        f"Not allowed while the session is {locked.status}.",
        code="scheduling.not_allowed_in_status",
    )
    if not _postponable(locked):
        raise not_allowed
    if locked.kind == Session.Kind.REGULAR and (sub is None or sub.status not in rules.LIVE):
        raise not_allowed


def _refuse_date(locked: Session, sub: Subscription | None, day: date, start) -> None:
    if start <= dates.now():
        raise ValidationError("Choose a time in the future.", field="occurs_on")
    if locked.kind == Session.Kind.REGULAR:
        span = rules.term(sub, rules.settings().renewal_grace_days)
        last = rules.generation_last_day(sub, span.grace_ends_on)
        if not sub.starts_on <= day <= last or rules.covering_pause(sub, day):
            raise ValidationError(
                "Choose a day inside the subscription's term and outside its pauses.",
                field="occurs_on",
            )


def _overlaps(locked: Session, start, minutes: int):
    end = start + timedelta(minutes=minutes)
    return (
        Session.objects.annotate(ends_at=rules.ENDS_AT)
        .filter(teacher_id=locked.teacher_id, starts_at__lt=end, ends_at__gt=start)
        .exclude(pk=locked.pk)
        .exclude(status=Session.Status.CANCELLED)
    )


def _refuse_for_family_or_teacher(locked: Session, start) -> None:
    """B-6 and B-8 for a student, parent or teacher."""
    limit = timedelta(minutes=rules.settings().postpone_limit_minutes)
    now = dates.now()
    if now > locked.starts_at - limit:
        raise ConflictError(
            "It is too late to postpone this session.",
            code="scheduling.too_late_to_postpone",
        )
    if start < now + limit or start > locked.starts_at + MAX_MOVE:
        raise ValidationError(
            "Choose a time further ahead and within two weeks.", field="occurs_on"
        )
    if _overlaps(locked, start, locked.minutes).exists():
        raise ConflictError(
            "The teacher has another session then.", code="scheduling.teacher_busy"
        )


def _reattach(locked: Session, day: date, at: time) -> bool:
    """B-4 / D8: back to exactly its slot date and the slot's current time,
    when that slot is active and still free on that date."""
    slot = locked.original_slot
    return (
        slot is not None
        and slot.is_active
        and day == locked.original_on
        and at == slot.start_time
        and not Session.objects.filter(slot=slot, occurs_on=day).exists()
    )


@transaction.atomic
def postpone_session(
    session: Session, *, by, occurs_on: date, start_time: time
) -> Postponed:
    """Spec §4.2, refusals in its order."""
    locked, sub = _lock(session)
    office = _office(by)
    _refuse_state(locked, sub)
    start = dates.to_utc(occurs_on, start_time, rules.settings().timezone)
    _refuse_date(locked, sub, occurs_on, start)
    if not office:
        _refuse_for_family_or_teacher(locked, start)
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

Export `Postponed`, `can_postpone`, `postpone_session` from `services/__init__.py`. If `rules.ENDS_AT` is not module-public under that name, use the existing `ENDS_AT` expression in `rules.py` (it is defined at module level there).

- [ ] **Step 4: Run the tests, lint, commit**

Run: `… pytest -q etqan/scheduling/tests/test_times_postponement_postpone.py` → PASS; ruff, format, lint-imports clean.

```bash
git -C backend add etqan/scheduling/services/postpone.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_times_postponement_postpone.py
git -C backend commit -m "feat(scheduling): postpone a session, with the limit and its refusals (B2b)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The timetable respects postponements

**Files:**
- Modify: `backend/etqan/scheduling/services/rules.py` (`regenerable`, `slots_of`), `generation.py` (skip set), `subscriptions.py` (callers, `delete_slot`, teacher change, renewal)
- Test: `backend/etqan/scheduling/tests/test_times_postponement_timetable.py`

**Interfaces:**
- Consumes: Task 4's `postpone_session`.
- Produces: `rules.regenerable(**filters) -> QuerySet[Session]` (D7). `slots_of(...).has_sessions` counts postponed sessions. No signature changes.

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2b §4.2: generation, regeneration, slots, teacher change and
renewal around postponed sessions."""

from datetime import date
from datetime import time

import pytest

from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
WED = date(2026, 6, 3)


@pytest.fixture
def sub(subscribe):
    return subscribe(slots=two_slots())


def postponed(sub, to=date(2026, 6, 4)):
    session = Session.objects.get(subscription=sub, occurs_on=WED)
    return services.postpone_session(
        session, by=make_admin(), occurs_on=to, start_time=time(20, 0)
    ).session


def test_generation_never_recreates_a_postponed_slot_date(sub):
    moved = postponed(sub)
    result = services.generate(date(2026, 6, 1), date(2026, 6, 14))
    assert not Session.objects.filter(slot=moved.original_slot, occurs_on=WED).exists()
    assert result.created == 0


def test_regeneration_after_a_slot_edit_keeps_it_and_its_date_skipped(sub):
    moved = postponed(sub)
    services.update_slot(moved.original_slot, minutes=60)
    assert Session.objects.filter(pk=moved.pk).exists()
    assert not Session.objects.filter(slot=moved.original_slot, occurs_on=WED).exists()


def test_a_pause_and_a_start_edit_keep_it(sub):
    moved = postponed(sub)
    services.add_pause(sub, from_date=date(2026, 6, 4), to_date=date(2026, 6, 4))
    assert Session.objects.filter(pk=moved.pk).exists()


def test_a_postponed_hand_added_session_survives_regeneration(sub):
    hand = hand_session(sub, occurs_on=date(2026, 6, 5))
    services.postpone_session(hand, by=make_admin(), occurs_on=date(2026, 6, 6), start_time=time(9, 0))
    services.update_subscription(sub, teacher_id=make_teacher("Hamza").id)
    assert Session.objects.filter(pk=hand.pk).exists()


def test_cancel_and_expiry_remove_it(sub):
    moved = postponed(sub)
    services.cancel_subscription(sub)
    assert not Session.objects.filter(pk=moved.pk).exists()


def test_a_slot_with_a_postponed_session_is_not_deleted(sub):
    moved = postponed(sub)
    Session.objects.filter(slot=moved.original_slot).delete()
    with pytest.raises(ConflictError) as err:
        services.delete_slot(moved.original_slot)
    assert err.value.code == "scheduling.slot_has_sessions"
    slot = services.slots_of(sub).get(pk=moved.original_slot_id)
    assert slot.has_sessions is True


def test_a_teacher_change_moves_postponed_sessions_too(sub):
    moved = postponed(sub)
    hamza = make_teacher("Hamza")
    services.update_subscription(sub, teacher_id=hamza.id)
    assert Session.objects.get(pk=moved.pk).teacher.user_id == hamza.id


def test_a_renewal_takes_postponed_sessions_dated_from_its_start(sub, clock):
    moved = postponed(sub, to=date(2026, 7, 2))
    renewal = services.renew_subscription(sub, starts_on=date(2026, 7, 1))
    assert Session.objects.get(pk=moved.pk).subscription_id == renewal.pk


def test_an_immediate_renewal_moves_them_before_expiring_the_old_one(sub, clock):
    moved = postponed(sub, to=date(2026, 6, 10))
    clock.set(clock_at(date(2026, 6, 5)))
    renewal = services.renew_subscription(sub, starts_on=date(2026, 6, 5))
    assert Session.objects.get(pk=moved.pk).subscription_id == renewal.pk


def clock_at(day):
    from datetime import UTC  # noqa: PLC0415
    from datetime import datetime  # noqa: PLC0415

    return datetime(day.year, day.month, day.day, 6, 0, tzinfo=UTC)
```

(The renewal tests need the subscription's term to include the renewal date; `two_slots` with the monthly package from 1 June covers 1–30 June plus grace.)

- [ ] **Step 2: Run to see them fail**

Run: `… pytest -q etqan/scheduling/tests/test_times_postponement_timetable.py`
Expected: FAIL (generation recreates the Wednesday; slot deletes; teacher not moved; renewal leaves the session).

- [ ] **Step 3: `rules.py`**

After `untouched_sessions`:

```python
def regenerable(**filters) -> QuerySet[Session]:
    """Plan 21 D7: the untouched sessions regeneration may replace — only
    generated ones (B2a A-9) and never a postponed one (B2b B-5: deleting it
    would free its slot date and bring the old time back)."""
    return untouched_sessions(generated=True, postponed_at__isnull=True, **filters)
```

`slots_of`:

```python
def slots_of(subscription: Subscription) -> QuerySet[ScheduleSlot]:
    produced = Session.objects.filter(slot=OuterRef("pk"))
    moved = Session.objects.filter(original_slot=OuterRef("pk"))
    return subscription.slots.annotate(
        has_sessions=Exists(produced) | Exists(moved)
    )
```

- [ ] **Step 4: `generation.py`** — after the `existing` set:

```python
    # Slice B2b (B-4): a postponed session's slot date stays taken.
    existing |= set(
        Session.objects.filter(
            original_slot__in=slots, original_on__range=(first, last)
        ).values_list("original_slot_id", "original_on")
    )
```

- [ ] **Step 5: `subscriptions.py`**

- `_regenerate`: `rules.delete_untouched(rules.regenerable(subscription=subscription))`.
- `_refill`: `rules.regenerable(subscription=subscription, occurs_on__gt=span.grace_ends_on)`.
- `add_pause`: `rules.regenerable(subscription=subscription, occurs_on__range=(from_date, to_date))`.
- `update_slot`: `rules.regenerable(slot=slot)`.
- `delete_slot`:

```python
def delete_slot(slot: ScheduleSlot) -> None:
    if slot.sessions.exists() or slot.postponed_sessions.exists():
        raise ConflictError(
            "This slot has sessions. Deactivate it instead.",
            code="scheduling.slot_has_sessions",
        )
    slot.delete()
```

- A helper and the teacher change:

```python
def _postponed_unmarked(subscription: Subscription, **filters) -> list[int]:
    """B2b B-5 / B-9: the subscription's postponed, unmarked future sessions,
    locked after the subscription (already held by the caller), in pk order."""
    return list(
        rules.untouched_sessions(
            subscription=subscription, postponed_at__isnull=False, **filters
        )
        .order_by("pk")
        .select_for_update()
        .values_list("pk", flat=True)
    )
```

In `update_subscription`, inside `if {"teacher", "starts_on"} & set(changed):` and before `_regenerate(locked)`:

```python
        if "teacher" in changed:
            Session.objects.filter(pk__in=_postponed_unmarked(locked)).update(
                teacher=locked.teacher, updated_at=dates.now()
            )
```

- Renewal (D6): replace the tail of `renew_subscription` from `rules.delete_untouched(...)` with:

```python
    rules.delete_untouched(
        rules.regenerable(subscription=old, occurs_on__gte=starts_on)
    )
    expire_now = old.status in rules.LIVE and starts_on <= rules.today()
    # Plan 12b: the renewal keeps the supervisor, while they may still be one.
    supervisor = access_services.get_supervisor(old.supervisor_id)
    renewal = create_subscription(
        student_id=old.student.user_id,
        course_id=course_id or old.course_id,
        teacher_id=teacher_id or old.teacher.user_id,
        package_id=package.pk,
        starts_on=starts_on,
        price_minor=price_minor,
        slots=slots,
        renewed_from=old,
        supervisor_id=supervisor.pk if supervisor else None,
    )
    # B2b B-5 (Plan 21 D6): postponed lessons now in the renewal's period go
    # with it, before the old subscription's expiry could remove them.
    Session.objects.filter(
        pk__in=_postponed_unmarked(old, occurs_on__gte=starts_on)
    ).update(subscription=renewal, updated_at=dates.now())
    if expire_now:
        rules.expire([old.pk])
    return renewal
```

(`create_subscription` is decorated `@transaction.atomic` and returns the subscription; the renewal row exists, so the update's FK check locks a row this transaction created.)

- [ ] **Step 6: Run the new tests and the scheduling, billing, payroll and notifications suites**

Run: `… pytest -q etqan/scheduling etqan/billing etqan/payroll etqan/notifications` → PASS (renewal and generation suites unchanged). Ruff, format, lint-imports clean.

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/scheduling/services/rules.py etqan/scheduling/services/generation.py etqan/scheduling/services/subscriptions.py etqan/scheduling/tests/test_times_postponement_timetable.py
git -C backend commit -m "feat(scheduling): the timetable keeps postponed sessions and their slot dates (B2b)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The Today board knows postponements

**Files:**
- Modify: `backend/etqan/scheduling/services/board.py`, `backend/etqan/scheduling/api/payloads.py` (`today_row`)
- Test: `backend/etqan/scheduling/tests/test_times_postponement_board.py`

**Interfaces:**
- Produces: `TodayRow` fields `slot: ScheduleSlot | None`, `start_time: time`, `minutes: int` (D5); state `"postponed"`; payload `slot_id` may be `null`, `start_time` / `minutes` read from the row.

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2b §4.2: the Today board."""

from datetime import date
from datetime import time

import pytest
from rest_framework.test import APIClient

from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
MON = date(2026, 6, 1)


@pytest.fixture
def sub(subscribe):
    return subscribe(slots=two_slots())


def test_a_slot_whose_session_moved_away_shows_postponed(sub):
    today = Session.objects.get(subscription=sub, occurs_on=MON)
    services.postpone_session(today, by=make_admin(), occurs_on=date(2026, 6, 2), start_time=time(9, 0))
    (row,) = services.today_board(MON)
    assert row.state == "postponed"
    assert row.session.pk == today.pk


def test_a_session_postponed_into_today_gets_its_own_row(sub, clock):
    wed = Session.objects.get(subscription=sub, occurs_on=date(2026, 6, 3))
    services.postpone_session(wed, by=make_admin(), occurs_on=MON, start_time=time(21, 0))
    rows = services.today_board(MON)
    moved = next(r for r in rows if r.slot is None)
    assert (moved.session.pk, moved.state, moved.start_time, moved.minutes) == (
        wed.pk,
        "generated",
        time(21, 0),
        wed.minutes,
    )


def test_the_payload_takes_start_and_minutes_from_the_row(sub):
    wed = Session.objects.get(subscription=sub, occurs_on=date(2026, 6, 3))
    services.postpone_session(wed, by=make_admin(), occurs_on=MON, start_time=time(21, 0))
    client = APIClient()
    client.force_login(make_admin("Huda"))
    rows = client.get("/api/v1/schedule/today/").json()["rows"]
    slotless = next(r for r in rows if r["slot_id"] is None)
    assert slotless["start_time"] == "21:00"
    assert slotless["session_id"] == wed.pk
```

- [ ] **Step 2: Run to see them fail** → FAIL.

- [ ] **Step 3: Implement** — in `board.py`:

```python
from datetime import time
from zoneinfo import ZoneInfo
```

`TodayRow`:

```python
@dataclass(frozen=True)
class TodayRow:
    day: date
    slot: ScheduleSlot | None  # None: a session postponed into this day (B2b)
    subscription: Subscription
    starts_at: datetime
    start_time: time  # the row's academy wall-clock time
    minutes: int
    session: Session | None
    state: str  # generated · missing · completed · cancelled · at_disposal · postponed
    derived: rules.Derived
```

In `today_board`: extend the slot query with the moved-away slots, collect them, and append slotless rows:

```python
    zone = ZoneInfo(academy.timezone)
    has_session = Exists(Session.objects.filter(slot=OuterRef("pk"), occurs_on=day))
    moved_away = Exists(
        Session.objects.filter(original_slot=OuterRef("pk"), original_on=day)
    )
    slots = list(
        ScheduleSlot.objects.filter(
            Q(is_active=True, subscription__status__in=rules.LIVE)
            | has_session
            | moved_away,
            weekday=day.weekday(),
        )
        ...  # select_related and order_by unchanged
    )
    moved_in = list(
        rules.sessions_queryset()
        .filter(
            occurs_on=day,
            slot__isnull=True,
            postponed_at__isnull=False,
            subscription__isnull=False,
        )
        .select_related("subscription__student__user", "subscription__teacher__user",
                        "subscription__course", "subscription__renewal")
    )
    derived = rules.derive(
        [s.subscription for s in slots] + [s.subscription for s in moved_in]
    )
    sessions = {s.slot_id: s for s in Session.objects.filter(slot__in=slots, occurs_on=day)}
    away = {
        s.original_slot_id: s
        for s in Session.objects.filter(original_slot__in=slots, original_on=day)
    }
```

In the per-slot loop: `session = sessions.get(slot.pk)`; `postponed = away.get(slot.pk)`; skip (out of window) only when both are `None`; when `session is None and postponed is not None`, append the row with `session=postponed`, `state="postponed"`, `starts_at=dates.to_utc(day, slot.start_time, academy.timezone)`; set `start_time=slot.start_time`, `minutes=slot.minutes` on slot rows. After the loop:

```python
    for session in moved_in:
        rows.append(
            TodayRow(
                day=day,
                slot=None,
                subscription=session.subscription,
                starts_at=session.starts_at,
                start_time=session.starts_at.astimezone(zone).time(),
                minutes=session.minutes,
                session=session,
                state=STATES[session.status],
                derived=derived[session.subscription_id],
            )
        )
    rows.sort(key=lambda r: (r.starts_at, r.slot.pk if r.slot else 0))
    return rows
```

`payloads.today_row`: `"slot_id": row.slot.pk if row.slot else None`, `"start_time": _hhmm(row.start_time)`, `"minutes": row.minutes`.

- [ ] **Step 4: Run** `… pytest -q etqan/scheduling` → PASS (existing board tests read `slot_id`, `start_time`, `minutes` unchanged for slot rows). Lint.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/scheduling/services/board.py etqan/scheduling/api/payloads.py etqan/scheduling/tests/test_times_postponement_board.py
git -C backend commit -m "feat(scheduling): postponed rows on the Today board (B2b)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The API — routes, payload, route table

**Files:**
- Modify: `backend/etqan/scheduling/services/rules.py` (`SESSION_RELATED` + `"subscription"`, D4), `api/serializers.py`, `api/payloads.py`, `api/session_views.py`, `api/urls.py`
- Modify: `backend/etqan/access/tests/test_routes.py`
- Test: `backend/etqan/scheduling/tests/test_api_times_postponement.py`

**Interfaces:**
- Produces: `POST sessions/<id>/times/` → session; `POST sessions/<id>/postpone/` → `{session, conflicts:[{session, other}]}` (conflicts empty for non-office); payload keys `teacher_in_at`, `teacher_out_at`, `student_in_at`, `student_out_at`, `actual_minutes` (with `session_times` on), `original_starts_at`, `postponed_at`, `can_postpone` (with `postponement` on), office-only `postponed_by {id, full_name} | null`.

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B2b §5–§6: the times and postpone routes and the payload."""

from datetime import timedelta

import pytest
from rest_framework.test import APIClient

from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


@pytest.fixture
def on(set_features):
    set_features(session_times=True, postponement=True, teacher_attendance=True)


@pytest.fixture
def session(subscribe, on):
    sub = subscribe(slots=two_slots())
    return Session.objects.filter(subscription=sub).order_by("starts_at")[1]


def test_the_teacher_stamps_in_through_the_api(session, clock):
    clock.set(session.starts_at - timedelta(minutes=10))
    response = as_user(session.teacher.user).post(
        f"/api/v1/sessions/{session.pk}/times/",
        {"teacher_in_at": (session.starts_at - timedelta(minutes=10)).isoformat()},
        format="json",
    )
    assert response.status_code == 200
    assert response.json()["teacher_in_at"]


def test_the_student_postpones_and_sees_no_conflicts(session):
    response = as_user(session.student.user).post(
        f"/api/v1/sessions/{session.pk}/postpone/",
        {"occurs_on": "2026-06-04", "start_time": "20:00"},
        format="json",
    )
    assert response.status_code == 200
    body = response.json()
    assert body["conflicts"] == []
    assert body["session"]["postponed_at"]
    assert "postponed_by" not in body["session"]


def test_the_office_payload_names_who_postponed(session):
    admin = make_admin()
    response = as_user(admin).post(
        f"/api/v1/sessions/{session.pk}/postpone/",
        {"occurs_on": "2026-06-04", "start_time": "20:00"},
        format="json",
    )
    assert response.json()["session"]["postponed_by"]["id"] == admin.pk


def test_can_postpone_in_the_list(session):
    rows = as_user(session.student.user).get("/api/v1/sessions/?when=upcoming").json()["results"]
    assert all("can_postpone" in r for r in rows)


def test_switched_off_routes_404_and_fields_disappear(session, set_features):
    set_features(session_times=False, postponement=False)
    admin = as_user(make_admin())
    assert admin.post(f"/api/v1/sessions/{session.pk}/times/", {"actual_minutes": 5}, format="json").status_code == 404
    assert admin.post(f"/api/v1/sessions/{session.pk}/postpone/", {"occurs_on": "2026-06-04", "start_time": "20:00"}, format="json").status_code == 404
    row = admin.get(f"/api/v1/sessions/{session.pk}/").json()
    assert "teacher_in_at" not in row
    assert "can_postpone" not in row


def test_another_students_session_is_404(session, world):
    from etqan.scheduling.tests.conftest import make_student  # noqa: PLC0415

    stranger = make_student("Bilqis")
    response = as_user(stranger.user if hasattr(stranger, "user") else stranger).post(
        f"/api/v1/sessions/{session.pk}/postpone/",
        {"occurs_on": "2026-06-04", "start_time": "20:00"},
        format="json",
    )
    assert response.status_code == 404


def test_staff_without_session_update_cannot_postpone(session):
    from etqan.access.tests.conftest import staff_with  # noqa: PLC0415

    response = as_user(staff_with("session.view")).post(
        f"/api/v1/sessions/{session.pk}/postpone/",
        {"occurs_on": "2026-06-04", "start_time": "20:00"},
        format="json",
    )
    assert response.status_code == 403


def test_bad_bodies_are_400(session):
    admin = as_user(make_admin())
    assert admin.post(f"/api/v1/sessions/{session.pk}/postpone/", {"occurs_on": "x"}, format="json").status_code == 400
    assert admin.post(f"/api/v1/sessions/{session.pk}/times/", {"actual_minutes": 0}, format="json").status_code == 400
```

(`make_student` returns what `identity_services.create_person` returns — a User in this codebase; check `conftest.py` and drop the `hasattr` branch accordingly. The staff helper's name and module come from the access tests: find the existing helper that creates staff holding given codes, e.g. in `etqan/scheduling/tests/test_staff_scope.py` or `etqan/access/tests/conftest.py`, and use it.)

- [ ] **Step 2: Run to see them fail** → FAIL (404 on unknown routes, missing keys).

- [ ] **Step 3: Serializers** (`api/serializers.py`):

```python
class TimesInput(serializers.Serializer):
    teacher_in_at = serializers.DateTimeField(required=False, allow_null=True)
    teacher_out_at = serializers.DateTimeField(required=False, allow_null=True)
    student_in_at = serializers.DateTimeField(required=False, allow_null=True)
    student_out_at = serializers.DateTimeField(required=False, allow_null=True)
    actual_minutes = serializers.IntegerField(
        min_value=1, max_value=600, required=False, allow_null=True
    )

    def validate(self, attrs):
        if not attrs:
            raise serializers.ValidationError({"teacher_in_at": "Send a time to record."})
        return attrs


class PostponeInput(serializers.Serializer):
    occurs_on = serializers.DateField()
    start_time = serializers.TimeField()
```

- [ ] **Step 4: Payload** (`api/payloads.py`): add `"postponed_by"` to `STAFF_ONLY_SESSION_FIELDS`; in `session_row`, before the office filter:

```python
    # Slice B2b (spec §5): each switch shows its own fields.
    if features.enabled("session_times"):
        row.update(
            teacher_in_at=session.teacher_in_at,
            teacher_out_at=session.teacher_out_at,
            student_in_at=session.student_in_at,
            student_out_at=session.student_out_at,
            actual_minutes=session.actual_minutes,
        )
    if features.enabled("postponement"):
        row.update(
            original_starts_at=session.original_starts_at,
            postponed_at=session.postponed_at,
            postponed_by=_user(session.postponed_by),
            can_postpone=services.can_postpone(session, viewer),
        )
```

and make the office filter tolerant of absent keys: `row.pop(field, None)`. Import `from etqan.platform import features`. Add `"postponed_by"` and `"subscription"` to `rules.SESSION_RELATED` (D4).

Add:

```python
def postponed_session(result: services.Postponed, *, viewer) -> dict:
    """Spec §4.2 step 5: the session, and — for the office only — the
    teacher's sessions it now overlaps."""
    shown = shows_supervision(viewer)
    return {
        "session": session_row(result.session, viewer=viewer, supervision=shown),
        "conflicts": [
            {
                "session": session_row(s, viewer=viewer, supervision=shown),
                "other": session_row(o, viewer=viewer, supervision=shown),
            }
            for s, o in result.conflicts
        ],
    }
```

- [ ] **Step 5: Views and URLs** (`api/session_views.py`):

```python
class TimesView(APIView):
    """B2b §4.1: the session's teacher, or the office holding the code."""

    permission_classes = [HasCode | IsTeacher, FeatureOn]
    permission_codes = {"POST": "attendance.update"}
    feature = "session_times"

    def post(self, request, pk):
        session = session_or_404(request, pk)
        body = TimesInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.record_times(session, by=request.user, fields=dict(body.validated_data))
        return Response(session_payload(request, pk))


class PostponeView(APIView):
    """B2b §4.2: the office by code; the session's teacher, student and the
    student's parents in scope (out of scope is 404)."""

    permission_classes = [HasCode | ReadsOwn, FeatureOn]
    permission_codes = {"POST": "session.update"}
    feature = "postponement"

    def post(self, request, pk):
        session = session_or_404(request, pk)
        body = PostponeInput(data=request.data)
        body.is_valid(raise_exception=True)
        result = services.postpone_session(session, by=request.user, **body.validated_data)
        return Response(payloads.postponed_session(result, viewer=request.user))
```

`urls.py`, after the B2a session routes:

```python
    # Slice B2b (spec §6).
    path(
        "sessions/<int:pk>/times/",
        session_views.TimesView.as_view(),
        name="session-times",
    ),
    path(
        "sessions/<int:pk>/postpone/",
        session_views.PostponeView.as_view(),
        name="session-postpone",
    ),
```

- [ ] **Step 6: Route table** (`access/tests/test_routes.py`): in `ROUTES` after B2a's lines:

```python
    # Slice B2b.
    ("POST", f"/api/v1/sessions/{N}/times/", "attendance.update"),
    ("POST", f"/api/v1/sessions/{N}/postpone/", "session.update"),
```

in `FEATURES`: `("POST", f"/api/v1/sessions/{N}/times/"): "session_times",` and `("POST", f"/api/v1/sessions/{N}/postpone/"): "postponement",`; in `FEATURE_WORDS`: `"/times/": "session_times",` and `"/postpone/": "postponement",`.

- [ ] **Step 7: Run** `… pytest -q etqan/scheduling etqan/access` → PASS; full backend verify once (`… pytest -q --cov=etqan`, ruff, format, lint-imports).

- [ ] **Step 8: Commit**

```bash
git -C backend add etqan/scheduling/services/rules.py etqan/scheduling/api etqan/access/tests/test_routes.py etqan/scheduling/tests/test_api_times_postponement.py
git -C backend commit -m "feat(scheduling): times and postpone routes, payload and route table (B2b)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Demo seeds

**Files:**
- Modify: `backend/etqan/tenants/seeds/b2.py`, `backend/etqan/tenants/management/commands/seed_dev.py` (B2 block only)
- Test: `backend/etqan/tenants/tests/test_seed_b2.py` (append)

**Interfaces:**
- Produces: `b2.seed_times_postponement(subdomain: str) -> None`.

- [ ] **Step 1: Failing test** (append):

```python
def test_demo_gets_a_postponed_session_and_teacher_times_once(seeded):
    # `seeded` is the existing fixture that ran seed_dev; reuse its name.
    with schema_context("academy_demo"):
        assert Session.objects.filter(postponed_at__isnull=False).count() == 1
        assert Session.objects.filter(teacher_in_at__isnull=False).count() == 1
    call_command("seed_dev")
    with schema_context("academy_demo"):
        assert Session.objects.filter(postponed_at__isnull=False).count() == 1
    with schema_context("academy_other"):
        assert not Session.objects.filter(postponed_at__isnull=False).exists()
```

(Match the existing test file's fixture and imports — it already runs `seed_dev` and reads `academy_demo`.)

- [ ] **Step 2: Implement** in `seeds/b2.py`:

```python
# Slice B2b (spec §8): in demo, the first upcoming generated session at least
# a day away moves one day later at the same time, and the latest completed
# session gets teacher in / out times.
POSTPONEMENT = {"demo": {"later_by_days": 1}}


def seed_times_postponement(subdomain: str) -> None:
    """Idempotent: an academy with a postponed session or recorded times is
    left alone. A refused step is printed and skipped."""
    spec = POSTPONEMENT.get(subdomain)
    sessions = scheduling_services.sessions_queryset()
    if spec is None or sessions.filter(
        Q(postponed_at__isnull=False) | Q(teacher_in_at__isnull=False)
    ).exists():
        return
    soon = scheduling_services.today() + timedelta(days=1)
    target = (
        sessions.filter(generated=True, status="scheduled", occurs_on__gte=soon)
        .order_by("starts_at", "id")
        .first()
    )
    if target is not None:
        try:
            scheduling_services.postpone_session(
                target,
                by=None,
                occurs_on=target.occurs_on + timedelta(days=spec["later_by_days"]),
                start_time=target.slot.start_time,
            )
        except (ValidationError, ConflictError) as exc:
            print(f"skip: postpone session {target.pk} — {exc}")  # noqa: T201
    done = sessions.filter(status="completed").order_by("-starts_at").first()
    if done is not None:
        try:
            scheduling_services.record_times(
                done,
                by=None,
                fields={
                    "teacher_in_at": done.starts_at,
                    "teacher_out_at": done.starts_at + timedelta(minutes=done.minutes),
                },
            )
        except (ValidationError, ConflictError) as exc:
            print(f"skip: times for session {done.pk} — {exc}")  # noqa: T201
```

(Add `from django.db.models import Q`.) In `seed_dev.py`'s B2 block, after `b2.seed_session_classes(subdomain)`: `b2.seed_times_postponement(subdomain)`.

- [ ] **Step 3: Run** `… pytest -q etqan/tenants/tests/test_seed_b2.py etqan/tenants/tests/test_seed_dev.py` → PASS; then on this stream: `just _stack-manage migrate_schemas` and `just _stack-manage seed_dev` twice (no errors, no duplicates).

- [ ] **Step 4: Commit**

```bash
git -C backend add etqan/tenants/seeds/b2.py etqan/tenants/management/commands/seed_dev.py etqan/tenants/tests/test_seed_b2.py
git -C backend commit -m "feat(seeds): a postponed session and teacher times in demo (B2b)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Dashboard foundations — types, API, strings, the board

**Files:**
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode` + `"session_times" | "postponement"` at its end, D11 of Plan 17)
- Modify: `dashboard/src/features/scheduling/schemas.ts`, `api.ts`, `TodayBoard.tsx` (+ test)
- Create: `dashboard/src/features/scheduling/postponing.ts` (+ `postponing.test.ts`)
- Create: `dashboard/src/locales/en/sessionTimes.json`, `dashboard/src/locales/ar/sessionTimes.json`
- Modify: `dashboard/src/locales/{en,ar}/scheduling.json` (`today.state.postponed`), `errors.json` (`scheduling.too_late_to_postpone`, `scheduling.teacher_busy`)
- Modify: `dashboard/src/test/scheduling-fixtures.ts`

**Interfaces:**
- Produces:
  - `Session` gains optional `teacher_in_at?, teacher_out_at?, student_in_at?, student_out_at?: string | null; actual_minutes?: number | null; original_starts_at?: string | null; postponed_at?: string | null; postponed_by?: PersonRef | null; can_postpone?: boolean`.
  - `TodayState` gains `"postponed"`; `TodayRow.slot_id: number | null`.
  - `TimesBody = Partial<Record<"teacher_in_at"|"teacher_out_at"|"student_in_at"|"student_out_at", string | null>> & { actual_minutes?: number | null }`; `PostponeBody = { occurs_on: string; start_time: string }`; `PostponedSession = { session: Session; conflicts: { session: Session; other: Session }[] }`.
  - `schedulingApi.recordTimes({ id, ...TimesBody }): Promise<Session>`, `schedulingApi.postpone({ id, ...PostponeBody }): Promise<PostponedSession>`.
  - `mayPostpone(session: Session, opts: { office: boolean; limitMinutes: number; now: Date }): boolean` — `session.can_postpone === true` and, for non-office, `now <= starts_at − limit` (D2).
  - i18n `sessionTimes.*` (below).

- [ ] **Step 1: Failing tests**

`postponing.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { sessionRow } from "@/test/scheduling-fixtures";
import { mayPostpone } from "./postponing";

const at = "2026-06-03T18:00:00Z";

describe("mayPostpone", () => {
	it("needs the server's can_postpone", () => {
		expect(
			mayPostpone(sessionRow({ starts_at: at, can_postpone: false }), {
				office: true,
				limitMinutes: 120,
				now: new Date("2026-06-01T00:00:00Z"),
			}),
		).toBe(false);
	});
	it("holds non-office viewers to the limit, to the second", () => {
		const s = sessionRow({ starts_at: at, can_postpone: true });
		const edge = new Date("2026-06-03T16:00:00Z");
		expect(mayPostpone(s, { office: false, limitMinutes: 120, now: edge })).toBe(true);
		expect(
			mayPostpone(s, {
				office: false,
				limitMinutes: 120,
				now: new Date(edge.getTime() + 1000),
			}),
		).toBe(false);
	});
	it("lets the office postpone any time", () => {
		const s = sessionRow({ starts_at: at, can_postpone: true });
		expect(
			mayPostpone(s, { office: true, limitMinutes: 120, now: new Date(at) }),
		).toBe(true);
	});
});
```

`TodayBoard.test.tsx` (append): a `todayRow({ state: "postponed", session_id: 7 })` renders "Postponed"; a `todayRow({ slot_id: null, session_id: 8 })` renders without a key warning next to a slot row (use distinct student names and assert both rows).

- [ ] **Step 2: Run** `… vitest run src/features/scheduling/postponing.test.ts src/features/scheduling/TodayBoard.test.tsx` → FAIL.

- [ ] **Step 3: Implement**

`postponing.ts`:

```ts
import type { Session } from "./schemas";

/** Slice B2b (Plan 21 D2): the server says what the row allows; the time
 * limit comes from the academy's settings and binds everyone but the office. */
export function mayPostpone(
	session: Session,
	{ office, limitMinutes, now }: { office: boolean; limitMinutes: number; now: Date },
): boolean {
	if (session.can_postpone !== true) return false;
	if (office) return true;
	const lastMoment = new Date(session.starts_at).getTime() - limitMinutes * 60_000;
	return now.getTime() <= lastMoment;
}
```

`api.ts` (after `setPaysTeacher`):

```ts
	// Slice B2b (spec §6).
	recordTimes: async ({ id, ...body }: TimesBody & { id: number }) =>
		(await api.post<Session>(`${SE}${id}/times/`, body)).data,
	postpone: async ({ id, ...body }: PostponeBody & { id: number }) =>
		(await api.post<PostponedSession>(`${SE}${id}/postpone/`, body)).data,
```

`TodayBoard.tsx`: `TONE` gains `postponed: "info"` (or the tone name the file uses for informational chips — keep it a semantic tone); the row key becomes ``key={`${row.slot_id ?? "moved"}-${row.session_id ?? row.slot_id}`}``; the "Generate" button stays only for `missing`.

`sessionTimes.json` (en; ar mirrors key for key):

```json
{
	"times": {
		"title": "Times",
		"teacherIn": "Teacher in",
		"teacherOut": "Teacher out",
		"studentIn": "Student in",
		"studentOut": "Student out",
		"actualMinutes": "Minutes taught",
		"now": "Now",
		"save": "Save times",
		"saved": "Times saved.",
		"imIn": "I'm in",
		"imOut": "I'm out",
		"stamped": "Recorded."
	},
	"postpone": {
		"button": "Postpone",
		"title": "Postpone the session",
		"body": "Choose a new day and time for {{name}}'s session on {{date}}.",
		"date": "Day",
		"time": "Time",
		"studentTime": "{{time}} for the student",
		"submit": "Postpone",
		"done": "Session postponed.",
		"from": "Postponed from {{when}}",
		"tooLate": "It's too late to postpone this session.",
		"conflicts": "The teacher has other sessions then:"
	},
	"settings": {
		"limit": "Postponement limit (minutes before the start)",
		"limitHint": "Students, parents and teachers can postpone a session until this many minutes before it starts."
	}
}
```

ar: same keys with Arabic text, e.g. `"title": "الأوقات"`, `"imIn": "دخلت"`, `"imOut": "خرجت"`, `"postpone": {"button": "تأجيل", "title": "تأجيل الحصة", "body": "اختر يومًا ووقتًا جديدين لحصة {{name}} يوم {{date}}.", …}`, `"from": "مؤجلة من {{when}}"`, `"tooLate": "فات وقت تأجيل هذه الحصة."`, `"limit": "الحد الأقصى للتأجيل (بالدقائق قبل البدء)"`.

`scheduling.json`: `today.state.postponed` = "Postponed" / "مؤجلة". `errors.json` `scheduling`: `too_late_to_postpone` = "It's too late to postpone this session." / "فات وقت تأجيل هذه الحصة.", `teacher_busy` = "The teacher has another session at that time." / "لدى المعلم حصة أخرى في هذا الوقت.".

`scheduling-fixtures.ts`: `sessionRow` default `can_postpone: false` is left out (optional), so existing tests are unaffected; `todayRow` keeps `slot_id: 1`.

- [ ] **Step 4: Run** the two test files, `tsc`, `pnpm lint` → PASS. **Step 5: Commit** (`git -C dashboard add …; commit -m "feat(scheduling): times and postponement types, API and board state (B2b)"` with the trailer).

---

### Task 10: The session page — Times panel and Postpone (office)

**Files:**
- Create: `dashboard/src/features/scheduling/TimesPanel.tsx` (+ test), `PostponeDialog.tsx` (+ test)
- Modify: `dashboard/src/features/scheduling/SessionPage.tsx` (+ test)

**Interfaces:**
- Consumes: Task 9.
- Produces: `<TimesPanel session={…} mode="office" | "teacher" />` (office: four `datetime-local` inputs in the academy zone, each with a "Now" button, and actual minutes; teacher: "I'm in" / "I'm out" buttons only); `<PostponeDialog session={…} academyZone={…} office={boolean} />` (date + time inputs, the student's time when it differs, conflicts via B2a's `ConflictList` for the office).

- [ ] **Step 1: Failing tests** — `TimesPanel.test.tsx`:
  - office mode: clicking "Now" next to "Teacher in" then "Save times" calls `schedulingApi.recordTimes` with `{ id, teacher_in_at: <ISO of the mocked now> }` (mock `Date` with `vi.setSystemTime`);
  - teacher mode before `teacher_in_at`: shows "I'm in" (enabled 15 minutes before `starts_at` per `has_started`/time — the server is the authority, the button just sends `teacher_in_at: now`); after a value is set: "I'm out";
  - a 409 shows the translated error toast.
  `PostponeDialog.test.tsx`:
  - submitting `2026-06-04` / `20:00` calls `schedulingApi.postpone({ id, occurs_on: "2026-06-04", start_time: "20:00" })` (no timezone shift: the raw input strings, as B2a's Add session does);
  - an office answer with conflicts shows them and a Done button; a non-office answer closes with the toast.
  `SessionPage.test.tsx` (append): with `adminWith("session_times", "postponement")`, the Times panel and Postpone show; with `original_starts_at` set, "Postponed from …" shows; with both switches off, neither shows. Use `findBy*` (`renderWithRouter` renders asynchronously).

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement** following `DisposalDialog.tsx` / `MakeUpDialog.tsx` (react-hook-form, `useFieldError`, `applyServerErrors`, `useSchedulingMutation`, `toast`, `errorText`). Datetime inputs convert between the academy zone and ISO with the existing helpers in `@/lib/zoned-time` (find the one that turns an academy wall-clock date + time into a UTC ISO string — B2a's conflict list and the slot editor already use this module; if no such helper exists, add `zonedToIso(day: string, time: string, zone: string): string` there with a test). `SessionPage.tsx`: render `<TimesPanel session mode="office" />` when `hasFeature("session_times") && can("attendance.update")`; render `<PostponeDialog … office />` next to Cancel when `hasFeature("postponement") && can("session.update") && session.can_postpone`; under the facts, `session.original_starts_at ? t("sessionTimes.postpone.from", { when: dayIn(...) + " " + wallTime(...) }) : null` in the academy zone.

- [ ] **Step 4: Run** the files, then `tsc`, `pnpm lint`, `pnpm test:coverage` → PASS. **Step 5: Commit** ("feat(scheduling): times panel and postpone dialog on the session page (B2b)").

---

### Task 11: Teachers, students and parents

**Files:**
- Modify: `dashboard/src/features/scheduling/TeacherSessionTable.tsx` (+ test), `FamilySessions.tsx` (+ test)

**Interfaces:**
- Consumes: `TimesPanel` (teacher mode), `PostponeDialog` (office=false), `mayPostpone`, `useAcademySettings` (for `postpone_limit_minutes`), `useMe`.

- [ ] **Step 1: Failing tests**
  - Teacher table (upcoming/today): with `session_times` on, a started row shows "I'm in"; with `postponement` on and `can_postpone` true and `now` before `starts_at − limit`, the row shows "Postpone"; one minute after the limit it doesn't.
  - Family sessions (upcoming): the same for Postpone, and when `can_postpone` is true but the limit has passed, the line "It's too late to postpone this session." shows.

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement**: a column/cell `actions` on upcoming rows that renders `<TimesPanel session mode="teacher" />` (teacher table only, with `session_times`) and `<PostponeDialog session academyZone={zone} office={false} />` when `hasFeature("postponement") && mayPostpone(session, { office: false, limitMinutes: academy.postpone_limit_minutes, now: new Date() })`; the family list shows the too-late line when `session.can_postpone && !mayPostpone(...)`. Add `postpone_limit_minutes: number` to `AcademySettings` in `dashboard/src/features/academy/api.ts` and to the `academySettings()` fixture (default 120).

- [ ] **Step 4: Run**, `tsc`, lint, coverage → PASS. **Step 5: Commit** ("feat(scheduling): I'm in/out and postpone for teachers, students and parents (B2b)").

---

### Task 12: The limit in Settings → Academy

**Files:**
- Modify: `dashboard/src/features/academy/AcademySettingsForm.tsx` (+ test), `dashboard/src/locales/{en,ar}/academySettings.json` (`errors.limitRange`)

- [ ] **Step 1: Failing test**: with `adminWith("postponement")` the form shows "Postponement limit (minutes before the start)" pre-filled with 120 and sends `postpone_limit_minutes: 90` after editing; with the switch off the field is absent and not sent; 10081 shows the range error.

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement**: schema `postpone_limit_minutes: days(0, 10080, "academySettings.errors.limitRange")`; default from `data.postpone_limit_minutes`; the `Field` (id `postpone_limit_minutes`, label `t("sessionTimes.settings.limit")`, hint `t("sessionTimes.settings.limitHint")`, `type="number"`, `valueAsNumber`) only when `hasFeature("postponement")`; the submit body leaves it out when the switch is off. Strings: `errors.limitRange` = "Choose a number from 0 to 10080." / "اختر رقمًا من 0 إلى 10080.".

- [ ] **Step 4: Run**, `tsc`, lint, coverage → PASS. **Step 5: Commit** ("feat(academy): the postponement limit in Settings (B2b)").

---

### Task 13: End-to-end through Caddy

**Files:**
- Create: `dashboard/e2e/b2-postpone.spec.ts`

- [ ] **Step 1: Write the spec** — model it on `dashboard/e2e/b2-session-classes.spec.ts` (read it first: its stamped teacher/course/package/student setup, the student invitation and sign-in helpers it uses, `findBy`/search patterns). Journey:
  1. `manage("set_features", "demo", "--on", "session_times", "postponement", "teacher_attendance")`.
  2. The admin creates a stamped teacher, course, package and student and a subscription with two weekly slots starting today (as the B2a spec does), and invites the student (the existing invite + mailbox helpers in `e2e/mail.ts` / `fixtures.ts`).
  3. The student signs in, opens My sessions, clicks **Postpone** on their second upcoming session (more than the 120-minute limit away), picks the next day at 20:00, and sees "Session postponed.".
  4. The admin opens that session (search the Sessions list by the student's name) and sees "Postponed from …".
  5. Using `manage` is not allowed to fake time; for the teacher stamps, the admin uses the Times panel on the student's *first* session only if it has started — otherwise skip the stamp assertion with a clear comment and assert the Times panel renders (the start gate is pinned by the backend tests).
- [ ] **Step 2: Run** `just e2e e2e/b2-postpone.spec.ts` twice on the same database → PASS both times.
- [ ] **Step 3: Run** the slice gates: `just test`, `just lint`, `just e2e` (locally the families spec can race features spec in parallel; rerun it alone if it is the only failure).
- [ ] **Step 4: Commit** ("test(e2e): a student postpones a session (B2b)").

---

## Self-review (done while writing)

- **Spec coverage:** §4.1 → Task 3; §4.2 refusals, detach / re-attach, origin → Task 4; generation skip, regeneration (B-5), slots, teacher change (B-9), renewal (B-5) → Task 5; Today board → Task 6; §5 access and payload, §6 routes → Task 7; B-11 setting → Task 2 (+ Task 12 UI); B-12 switches → Task 1; §7 dashboard → Tasks 9–12; §8 seeds → Task 8; §9 e2e → Task 13. B-10 (payroll month) → Task 4 test. B-13 (reminders) is an accepted limit with no code.
- **Placeholders:** none; where the plan points at an existing helper whose exact name must be read from the code (the academy test client fixture, `link_guardian`, the staff-with-codes helper, a zoned-time helper), it says which file to read and what the call must do.
- **Type consistency:** `Postponed(session, conflicts)`, `postpone_session(session, *, by, occurs_on, start_time)`, `record_times(session, *, by, fields)`, `can_postpone(session, viewer)`, `regenerable(**filters)` are used with the same names in Tasks 4–8; dashboard `recordTimes`, `postpone`, `mayPostpone`, `TimesPanel`, `PostponeDialog` in Tasks 9–13.
- **Review Focus:** five lines, each with its test in the owning task.
