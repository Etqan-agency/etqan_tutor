# Plan 17 — Session Classes (slice B2a) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** none (B2 depends only on B1, merged).
**Slice:** B2a · **Phase spec:** docs/superpowers/specs/2026-10-03-b2-scheduling-depth-design.md

**Goal:** The office adds sessions by hand — a regular session on a subscription, an extra session outside the package, a compensation (make-up) for a session that did not use up the package — every session carries its kind and whether it pays the teacher, and a session can be placed at the administration's disposal; all four behind per-academy switches that are off by default.

**Architecture:**
- **Data.** `scheduling.Session` gains `kind`, `compensates` (→ Session), `compensated`, `pays_teacher`, `created_by`, `disposal_reason`, and the status `at_disposal` (column 10 → 12 characters). One additive migration, `0006_session_classes`. Two constraints: one live compensation per original; `kind = compensation` ⇔ `compensates` set.
- **Rules** stay where they are: the one consumption rule (`rules.consuming`) adds `kind ∈ {regular, compensation}` and `compensated = false`; `payroll_sessions` adds `pays_teacher = true`; the regenerating callers delete only `generated` untouched sessions, cancel and expiry only `regular` ones. Eligibility (`rules.is_compensable`) is one function.
- **Services.** A new module `scheduling/services/manual.py` adds, deletes and re-prices hand-added sessions; `attendance.py` gains the frozen-original rule, the compensation lifecycle and `place_at_disposal`. All are exported from `scheduling.services`.
- **API.** One create route per kind (`sessions/regular/`, `sessions/extra/`, `sessions/compensation/`) so each declares one feature; `DELETE sessions/<id>/`; `sessions/<id>/disposal/`; `sessions/<id>/pays-teacher/`; a `kind` filter and the new payload fields.
- **Dashboard.** Kind chips and the `at_disposal` label everywhere a session status shows; Sessions list tabs and an Add session dialog; on the session page the compensation links, a pays-teacher toggle, Add make-up, disposal, restore and delete.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next, Radix UI; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-03-b2a-session-classes-design.md` (slice B2a of `docs/superpowers/specs/2026-10-03-b2-scheduling-depth-design.md`). It builds on Plan 4 (generation, "untouched" sessions), Plan 5 (attendance, the consumption rule, cancel/restore, the payload), Plan 7 (`payroll_sessions`, the payroll lock), Plan 12a (codes), Plan 13 (switches). Where this plan fills a gap in the spec, the Decisions below say so.

## Global Constraints

**Repos and branches**
- Meta worktree: `/home/abdulkhalek/Projects/etqan_tutor-wt/b2` (call it `$W`). Meta, `backend/` and `dashboard/` are all on `feat/b2a-scheduling`; backend and dashboard start at their `origin/main` heads. `marketing/` is untouched.
- Commit in the submodule that owns the file (`git -C $W/backend …`, `git -C $W/dashboard …`). Never run `git submodule update` (or any writing `git submodule` subcommand) in this worktree.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Never edit `STATE.md`, CI workflows, Caddyfiles, or meta's submodule pointers.

**Commands (verified in this worktree; the slot-1 stack must be up: `just dev-backend`)**
- Every command runs from `$W` with the stream's environment loaded, inside this stream's own containers:
  ```bash
  cd /home/abdulkhalek/Projects/etqan_tutor-wt/b2
  set -a; . ./.env.stream; set +a
  DC="docker compose -f docker-compose.local.yml"
  ```
  The containers run as uid 1000 (the host user), so files they write are yours. There is no host `.venv` and no host `node_modules`; never run `manage.py`, `migrate` or pytest against any other database.
- Backend tests: `$DC exec -T django pytest -q <paths>`. After Task 1's migration add `--create-db` once.
- Backend format: `$DC exec -T django sh -c 'ruff check --fix . && ruff format .'`
- Backend verify: `$DC exec -T django sh -c 'ruff check . && ruff format --check . && lint-imports && pytest -q --cov=etqan'`
- Migration (Task 1): `$DC exec -T django python manage.py makemigrations scheduling --name session_classes`
- Dashboard tests: `$DC exec -T dashboard pnpm exec vitest run <paths>`
- Dashboard format: `$DC exec -T dashboard pnpm exec biome check --write src e2e`
- Dashboard verify: `$DC exec -T dashboard sh -c 'pnpm exec tsc --noEmit && pnpm lint && pnpm test:coverage && pnpm build'`
- Slice gates (orchestration §7, before queuing): `just test`, `just lint`, `just e2e`.
- Ruff selects `PL`, `FBT`, `DTZ`, `BLE`, `ERA`, `SLF`, `C901` (complexity 10), `E501` (88 columns). Long keyword-only signatures carry `# noqa: PLR0913 -- keyword-only; mirrors the API body (spec §6)` as the codebase does. Migrations are excluded from Ruff.
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`: no hex colours, no Tailwind palette utilities; semantic tokens only.

**Coverage and dev data**
- Gates: backend ≥ 80 % (`pytest --cov=etqan`); dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`; `demo` admin `admin@demo.test`, `other` admin `admin@other.test`.

**Orchestration rules**
- Shared lists: add lines only under `── phase B2 ──` markers (feature registry, access `RESOURCES`, `seed_academy`). Widening the existing `session` resource's `in_use` is B2's own resource (phase spec §4).
- New translation areas are new files `dashboard/src/locales/{en,ar}/<area>.json` whose top-level key is the file name: this plan adds `sessionClasses.json`. Labels of the existing `scheduling` area and the `errors.scheduling` codes are B2's and edited in place.
- New e2e specs are `dashboard/e2e/b2-*.spec.ts`.
- **Migrations are additive** (phase B2-16): every new column is nullable or has a `db_default`; the status column only widens. Never `makemigrations --merge`; on a clash after a rebase, delete `0006_session_classes` and regenerate it.
- Service signature changes are additive only. `etqan.platform` imports no business module.

**API and data rules (spec values verbatim)**
- Kinds: `regular · compensation · extra`. Status gains `at_disposal`.
- 409 bodies are `{detail, code}`. New codes: `scheduling.not_compensable`, `scheduling.already_compensated`, `scheduling.has_compensation`, `scheduling.session_generated`, `scheduling.session_marked`. Reused: `scheduling.not_allowed_in_status`, `payroll.payslip_issued`, `scheduling.has_marked_sessions`.
- A switched-off feature's routes answer `404 {"detail": "This feature is not enabled for this academy."}` after the permission check.
- Routes: `POST sessions/regular/` (`manual_sessions`), `POST sessions/extra/` (`extra_sessions`), `POST sessions/compensation/` (`compensation_sessions`) — `session.create`, `201 {session, conflicts}`; `DELETE sessions/<id>/` (`session.delete`, no feature, `204`); `POST sessions/<id>/disposal/` (`session.update`, `disposal_status`); `POST sessions/<id>/pays-teacher/` (`session.update`, `extra_sessions`).
- Payload: everyone in scope sees `kind`, `compensates_id`, `compensation_id`; the office alone sees `pays_teacher`, `compensated`, `created_by {id, full_name} | null`, `disposal_reason` (and, on the detail read, `compensable` — D1).

### Decisions this plan makes where the spec is silent or leaves a choice

- **D1 — `compensable` on the office's detail read.** The spec has the dashboard compute eligibility from payload fields, but A-3 depends on the academy's consumption switches; restating the rule in TypeScript would be a second copy of it. The detail read (`GET sessions/<id>/` and every write's answer) gives the office `compensable`, computed by `rules.is_compensable` (one query). Lists don't carry it (no N+1). The server stays the authority either way.
- **D2 — The list's Add session dialog offers Regular and Extra.** A make-up needs its original, which is picked by opening that session: **Add make-up session** lives on the session page (spec §7 has both). The list dialog's kind picker therefore lists the switched-on kinds among `regular` and `extra`.
- **D3 — Any restore clears `disposal_reason`.** A-11 keeps it while the session is cancelled "for the record"; once restored to `scheduled` there is nothing to record.
- **D4 — `by` may be `None`.** The services take `by` (→ `created_by`); the API passes `request.user`, the seeds pass `None` ("system", A-12).
- **D5 — The Plan 13 registry tests stop hard-coding the registry's size.** `etqan/platform/tests/test_features.py` asserted exactly 36 codes, 8 built and 28 unbuilt; every phase that registers a feature would break and conflict on those lines. They now pin Plan 13's eight built features and their order at the head of `BUILT`, unique codes, and "every feature outside Plan 13's built eight is off by default". B2's own registry test lives in `etqan/scheduling/tests/test_session_classes_features.py`. If another phase's rebase brings its own edit of the same assertions, keep the generalised form.
- **D6 — Demo's switches come from `features.BUILT`.** `seed_dev.FEATURES = {"demo": features.BUILT}` already switches every built feature on for demo, so marking the four codes built turns them on there; the B2 seed step only adds data.
- **D7 — Public aliases for the shared checks.** `services/subscriptions.py` gains `active_student = _student`, `active_course = _course`, `course_teacher = _teacher` so `manual.py` reuses the same checks without reaching into private names (Ruff `SLF001`).
- **D8 — `generation.conflicts` becomes public.** `_conflicts` is renamed `conflicts` and reused by `manual.py` for a single added session (P4-9).
- **D9 — Lock order.** Restoring or cancelling a compensation locks the compensation, then its original (`select_for_update` / `update`). Nothing locks an original and then its compensation, so no cycle forms; the docstrings say so.
- **D10 — The B2 seed step's import sits under the marker** (`from etqan.tenants.seeds import b2  # noqa: PLC0415`, inside `seed_academy`), so parallel phases never edit the same import lines.
- **D11 — The dashboard's `FeatureCode` union gains the four codes at its end**; a rebase conflict there resolves by keeping every phase's codes.

## Review Focus

- **A consumption switch flipped after a make-up exists.** Expected: an original with a live make-up never counts, whatever `absent_consumes_session` / `excused_consumes_session` say, so the package is charged once. Test: Task 4 `test_flipping_a_switch_never_counts_an_original_and_its_make_up_twice`.
- **Two make-ups for one original at once.** Expected: the original's row lock serialises them; the second gets 409 `scheduling.already_compensated`, and the database's partial unique constraint backs it. Tests: Task 1 `test_one_live_compensation_per_original`; Task 3 `test_a_second_make_up_is_refused`.
- **A hand-added time on a clock change.** Expected: Plan 4's single conversion — a non-existent local time moves forward, an ambiguous one takes the first occurrence. Test: Task 3 `test_an_added_session_on_a_clock_change_uses_plans_4_conversion`.
- **A hand-added session when the subscription's teacher, start date, slots or pauses change.** Expected: it is kept with its own teacher (regeneration touches only generated sessions); cancel and expiry remove a hand-added regular session but never a make-up or an extra session. Tests: Task 2 `test_regeneration_keeps_sessions_added_by_hand`, `test_ending_a_subscription_removes_its_regular_sessions_only`, `test_a_renewal_leaves_hand_added_sessions_until_the_old_term_ends`.
- **A session added in the past.** Expected: allowed (recording what happened); its attendance opens at once because `has_started` is true; a regular one still must fall inside the subscription's window. Tests: Task 3 `test_a_regular_session_in_the_past_is_recorded_and_open_for_attendance`; Task 6 `test_the_admin_adds_a_past_extra_session_and_marks_it`.

---

## File Structure

```
backend/
  etqan/platform/features.py                    four switches under ── phase B2 ── (Task 1)
  etqan/platform/tests/test_features.py         generalised registry assertions (Task 1, D5)
  etqan/scheduling/
    models.py                                    Session: kind, compensates, compensated, pays_teacher,
                                                 created_by, disposal_reason, at_disposal (Task 1)
    migrations/0006_session_classes.py           generated (Task 1)
    services/rules.py                            consuming, expire, is_compensable,
                                                 sessions_queryset, has_hand_added_sessions (Tasks 2, 3, 6, 7)
    services/paylock.py                          payroll_sessions: pays_teacher (Task 2)
    services/subscriptions.py                    generated-only regeneration, regular-only cancel,
                                                 public aliases, at_disposal blocks delete (Tasks 2, 3, 5)
    services/generation.py                       conflicts() public (Task 3)
    services/manual.py                           NEW: create_*, delete_session, set_pays_teacher (Tasks 3–5)
    services/attendance.py                       frozen original, compensation lifecycle,
                                                 place_at_disposal (Tasks 4, 5)
    services/board.py                            at_disposal state (Task 5)
    services/__init__.py                         exports (Tasks 3–5, 7)
    api/serializers.py payloads.py
        session_views.py urls.py                 the routes (Task 6)
    tests/conftest.py                            hand_session helper (Task 1)
    tests/test_session_classes_*.py              NEW (Tasks 1–6)
  etqan/access/registry.py                       session in_use gains delete (Task 6)
  etqan/access/tests/test_routes.py              ROUTES, FEATURES, FEATURE_WORDS (Task 6)
  etqan/tenants/seeds/b2.py                      NEW: seed_session_classes (Task 7)
  etqan/tenants/management/commands/seed_dev.py  one call under ── phase B2 ── (Task 7)
  etqan/tenants/tests/test_seed_b2.py            NEW (Task 7)
dashboard/
  src/features/identity/schemas.ts               FeatureCode (Task 8)
  src/features/scheduling/
    schemas.ts api.ts bits.tsx                    kinds, at_disposal, bodies, api calls (Task 8)
    SessionKindChip.tsx                           NEW (Task 8)
    AttendanceControls.tsx TodayBoard.tsx
      SessionsPanel.tsx TeacherSessionTable.tsx
      FamilySessions.tsx                          kind chip, at_disposal (Task 8)
    SessionsList.tsx AddSessionDialog.tsx (NEW)
      SessionFields.tsx (NEW)                     tabs, filter, Add session (Task 9)
    SessionPage.tsx SessionClasses.tsx (NEW)
      MakeUpDialog.tsx (NEW) DisposalDialog.tsx (NEW)  (Task 10)
  src/test/scheduling-fixtures.ts                sessionRow defaults (Task 8)
  src/locales/{en,ar}/sessionClasses.json        NEW (Task 8)
  src/locales/{en,ar}/scheduling.json errors.json  at_disposal labels, 409 codes (Task 8)
  e2e/b2-session-classes.spec.ts                 NEW (Task 11)
```

---

### Task 1: The switches, the Session columns and the migration

**Files:**
- Modify: `backend/etqan/platform/features.py` (under `# ── phase B2 ──`)
- Modify: `backend/etqan/platform/tests/test_features.py:27-46`
- Modify: `backend/etqan/scheduling/models.py` (class `Session`)
- Create: `backend/etqan/scheduling/migrations/0006_session_classes.py` (generated)
- Modify: `backend/etqan/scheduling/tests/conftest.py` (add `hand_session`)
- Create: `backend/etqan/scheduling/tests/test_session_classes_features.py`
- Create: `backend/etqan/scheduling/tests/test_session_classes_model.py`

**Interfaces:**
- Produces: `Session.Kind` (`REGULAR`, `COMPENSATION`, `EXTRA`), `Session.Status.AT_DISPOSAL`; fields `kind`, `compensates`/`compensates_id`, reverse `compensations`, `compensated`, `pays_teacher`, `created_by`, `disposal_reason`. Feature codes `manual_sessions`, `extra_sessions`, `compensation_sessions`, `disposal_status`. Test helper `hand_session(subscription, *, occurs_on, start=time(10, 0), **fields) -> Session`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/scheduling/tests/test_session_classes_features.py`:

```python
"""Slice B2a §2 A-13: the four session-class switches are built, in the
teaching group, and off by default."""

import pytest

from etqan.platform import features

B2A = ("manual_sessions", "extra_sessions", "compensation_sessions", "disposal_status")


@pytest.mark.parametrize("code", B2A)
def test_each_session_class_is_a_built_switch_off_by_default(code):
    feature = features.get(code)
    assert feature.built is True
    assert feature.default is False
    assert feature.group == "teaching"
    assert feature.requires == ()
    assert features.is_on(code, {}) is False
    assert features.is_on(code, {code: True}) is True


def test_they_sit_after_plan_13s_features():
    codes = [feature.code for feature in features.REGISTRY]
    assert codes.index("public_links") < codes.index("manual_sessions")
    assert [c for c in features.BUILT if c in B2A] == list(B2A)
```

`backend/etqan/scheduling/tests/test_session_classes_model.py`:

```python
"""Slice B2a §3.1: the new Session columns, their database defaults and the
two constraints."""

from datetime import date

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db


def first(sub):
    return Session.objects.filter(subscription=sub).order_by("starts_at").first()


def test_a_generated_session_is_regular_paid_and_not_compensated(subscribe):
    session = first(subscribe(slots=two_slots()))
    assert (session.kind, session.pays_teacher, session.compensated) == (
        "regular",
        True,
        False,
    )
    assert session.compensates is None
    assert session.created_by is None
    assert session.disposal_reason == ""


def test_at_disposal_fits_the_status_column(subscribe):
    session = first(subscribe(slots=two_slots()))
    Session.objects.filter(pk=session.pk).update(status="at_disposal")
    session.refresh_from_db()
    assert session.status == Session.Status.AT_DISPOSAL


def test_a_compensation_needs_its_original_and_only_it_has_one(subscribe):
    sub = subscribe(slots=two_slots())
    session = first(sub)
    with pytest.raises(IntegrityError), transaction.atomic():
        Session.objects.filter(pk=session.pk).update(kind="compensation")
    with pytest.raises(IntegrityError), transaction.atomic():
        hand_session(sub, occurs_on=date(2026, 6, 5), compensates=session)


def test_one_live_compensation_per_original(subscribe):
    sub = subscribe(slots=two_slots())
    original = first(sub)

    def make_up(**fields):
        return hand_session(
            sub,
            occurs_on=date(2026, 6, 5),
            kind="compensation",
            compensates=original,
            **fields,
        )

    live = make_up()
    with pytest.raises(IntegrityError), transaction.atomic():
        make_up()
    Session.objects.filter(pk=live.pk).update(status="cancelled")
    assert make_up().compensates == original
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DC exec -T django pytest -q etqan/scheduling/tests/test_session_classes_features.py etqan/scheduling/tests/test_session_classes_model.py`
Expected: FAIL — `LookupError: Unknown feature: 'manual_sessions'` and `ImportError: cannot import name 'hand_session'`.

- [ ] **Step 3: Register the switches**

In `backend/etqan/platform/features.py`, replace the line `    # ── phase B2 ──` with:

```python
    # ── phase B2 ──
    # Slice B2a (Plan 17): the session classes, built and off by default.
    Feature(
        "manual_sessions",
        "Add sessions by hand",
        "إضافة الحصص يدويًا",
        "teaching",
        built=True,
    ),
    Feature("extra_sessions", "Extra sessions", "الحصص الإضافية", "teaching", built=True),
    Feature(
        "compensation_sessions",
        "Compensation sessions",
        "الحصص التعويضية",
        "teaching",
        built=True,
    ),
    Feature(
        "disposal_status",
        "At the administration's disposal",
        "تحت تصرف الإدارة",
        "teaching",
        built=True,
    ),
```

(Run the backend format command afterwards; Ruff may rewrap the short `Feature(...)` line.)

- [ ] **Step 4: Generalise Plan 13's registry tests (D5)**

In `backend/etqan/platform/tests/test_features.py` replace `test_the_registry_has_36_unique_codes_in_both_languages` and `test_the_defaults_match_the_spec` with:

```python
def test_the_registry_has_unique_codes_in_both_languages():
    """Plan 13 §3 listed 36; the parallel phases add theirs under their
    markers, so the count only grows."""
    codes = [feature.code for feature in features.REGISTRY]
    assert len(codes) >= 36
    assert len(set(codes)) == len(codes)
    assert set(codes) == features.CODES
    for feature in features.REGISTRY:
        assert re.fullmatch(r"[a-z][a-z_]*", feature.code), feature.code
        assert feature.label_en.strip(), feature.code
        assert ARABIC.search(feature.label_ar), feature.code
        assert feature.group in features.GROUPS, feature.code


def test_the_defaults_match_the_spec():
    """§3.1: Plan 13's eight built features lead `BUILT`, on by default but
    supervision; every other feature, built later or not yet, is off by
    default (PO-5)."""
    assert {code: features.get(code).default for code in BUILT} == BUILT
    assert list(features.BUILT)[: len(BUILT)] == list(BUILT)
    assert not any(
        feature.default for feature in features.REGISTRY if feature.code not in BUILT
    )
    assert features.get("report_deductions").requires == ("session_reports",)
```

- [ ] **Step 5: Add the Session columns**

In `backend/etqan/scheduling/models.py`, class `Session`:

Replace the `Status` class with:

```python
    class Status(models.TextChoices):
        SCHEDULED = "scheduled", "Scheduled"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"
        # Slice B2a (A-11): TutorHamster's "at the administration's disposal".
        AT_DISPOSAL = "at_disposal", "At the administration's disposal"

    class Kind(models.TextChoices):
        """Slice B2a (A-1): generated sessions are regular; the office adds
        regular, compensation and extra ones by hand."""

        REGULAR = "regular", "Regular"
        COMPENSATION = "compensation", "Compensation"
        EXTRA = "extra", "Extra"
```

Replace the `status` field with:

```python
    # Slice B2a: widened from 10 to 12 for `at_disposal` (no data changes).
    status = models.CharField(
        max_length=12, choices=Status.choices, default=Status.SCHEDULED
    )
```

After `opened_by_supervisor_at` (before `created_at`), add:

```python
    # Slice B2a (spec §3.1). New columns on an existing table: nullable, or
    # with a database default (phase B2-16).
    kind = models.CharField(
        max_length=12,
        choices=Kind.choices,
        default=Kind.REGULAR,
        db_default=Kind.REGULAR,
    )
    # A compensation's original (A-3); PROTECT: an original with a make-up
    # pointing at it is never deleted.
    compensates = models.ForeignKey(
        "self",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="compensations",
    )
    # Set on the original while it has a live compensation (A-4): it is then
    # frozen, and the consumption rule leaves it out.
    compensated = models.BooleanField(default=False, db_default=False)
    pays_teacher = models.BooleanField(default=True, db_default=True)
    # Who added it by hand (A-12); null for generated sessions ("system").
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    disposal_reason = models.TextField(blank=True, default="", db_default="")
```

In `Meta.constraints`, after `scheduling_session_slot_day_unique`, add:

```python
            # Slice B2a (A-3): at most one live compensation per original.
            models.UniqueConstraint(
                fields=["compensates"],
                condition=Q(compensates__isnull=False) & ~Q(status="cancelled"),
                name="scheduling_one_live_compensation",
            ),
            models.CheckConstraint(
                condition=(Q(kind="compensation") & Q(compensates__isnull=False))
                | (~Q(kind="compensation") & Q(compensates__isnull=True)),
                name="scheduling_compensation_has_original",
            ),
```

- [ ] **Step 6: Generate the migration**

Run: `$DC exec -T django python manage.py makemigrations scheduling --name session_classes`
Expected: `etqan/scheduling/migrations/0006_session_classes.py` with `AddField` × 6, `AlterField` on `status` (max_length 12) and `AddConstraint` × 2. Read it: no `RunPython`, no `RemoveField`, every `AddField` has `db_default` or `null=True`.

- [ ] **Step 7: Add the test helper**

In `backend/etqan/scheduling/tests/conftest.py`, add the import `from etqan.scheduling.models import Session` with the other imports, and after `subscription_for`:

```python
def hand_session(subscription, *, occurs_on, start=time(10, 0), **fields):
    """A session added by hand (slice B2a), written straight to the table:
    for tests whose subject is not the service that adds sessions. The
    academy's timezone is UTC in these tests."""
    values = {
        "subscription": subscription,
        "student_id": subscription.student_id,
        "teacher_id": subscription.teacher_id,
        "course_id": subscription.course_id,
        "occurs_on": occurs_on,
        "starts_at": dates.to_utc(occurs_on, start, "UTC"),
        "minutes": subscription.session_minutes,
        "generated": False,
        **fields,
    }
    return Session.objects.create(**values)
```

- [ ] **Step 8: Run the tests**

Run: `$DC exec -T django pytest -q --create-db etqan/scheduling/tests/test_session_classes_features.py etqan/scheduling/tests/test_session_classes_model.py etqan/platform/tests/test_features.py etqan/tenants/tests/test_seed_dev.py`
Expected: PASS.

- [ ] **Step 9: Format, verify, commit**

```bash
$DC exec -T django sh -c 'ruff check --fix . && ruff format . && lint-imports'
git -C backend add etqan/platform/features.py etqan/platform/tests/test_features.py etqan/scheduling/models.py etqan/scheduling/migrations/0006_session_classes.py etqan/scheduling/tests/conftest.py etqan/scheduling/tests/test_session_classes_features.py etqan/scheduling/tests/test_session_classes_model.py
git -C backend commit -m "feat(scheduling): session kinds, compensation link, pays_teacher and at_disposal (B2a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: What counts, what payroll reads, what the system deletes

**Files:**
- Modify: `backend/etqan/scheduling/services/rules.py` (`consuming`, `expire`)
- Modify: `backend/etqan/scheduling/services/paylock.py` (`payroll_sessions`)
- Modify: `backend/etqan/scheduling/services/subscriptions.py` (`_regenerate`, `_refill`, `cancel_subscription`, `add_pause`, `update_slot`, `renew_subscription`)
- Create: `backend/etqan/scheduling/tests/test_session_classes_rules.py`

**Interfaces:**
- Consumes: Task 1's columns and `hand_session`.
- Produces: `rules.COUNTED_KINDS = (Session.Kind.REGULAR, Session.Kind.COMPENSATION)`; `consuming()` excludes extra and compensated sessions; `payroll_sessions()` returns only `pays_teacher=True`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/scheduling/tests/test_session_classes_rules.py`:

```python
"""Slice B2a §4.3 (consumption), §4.7 (payroll reads paying sessions) and
§4.4 / A-9 (which sessions the system deletes)."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.services import rules
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
DONE = {
    "status": "completed",
    "student_attendance": "present",
    "teacher_attendance": "present",
}


def exists(session):
    return Session.objects.filter(pk=session.pk).exists()


def test_only_regular_and_compensation_sessions_count(subscribe):
    sub = subscribe(slots=two_slots())
    hand_session(sub, occurs_on=date(2026, 6, 2), kind="extra", **DONE)
    assert services.derived(sub).sessions_used == 0
    original = hand_session(sub, occurs_on=date(2026, 6, 3), compensated=True, **DONE)
    assert services.derived(sub).sessions_used == 0
    hand_session(
        sub,
        occurs_on=date(2026, 6, 4),
        kind="compensation",
        compensates=original,
        **DONE,
    )
    assert services.derived(sub).sessions_used == 1


def test_a_regular_session_added_by_hand_counts_like_a_generated_one(subscribe):
    sub = subscribe(slots=two_slots())
    hand_session(sub, occurs_on=date(2026, 6, 2), **DONE)
    assert services.derived(sub).sessions_used == 1


def test_payroll_reads_only_sessions_that_pay_the_teacher(subscribe):
    sub = subscribe(slots=two_slots())
    unpaid = hand_session(sub, occurs_on=date(2026, 6, 2), kind="extra", pays_teacher=False)
    paid = hand_session(sub, occurs_on=date(2026, 6, 3), kind="extra")
    ids = set(
        services.payroll_sessions(date(2026, 6, 1), date(2026, 6, 30)).values_list(
            "pk", flat=True
        )
    )
    assert paid.pk in ids
    assert unpaid.pk not in ids


def test_regeneration_keeps_sessions_added_by_hand(subscribe):
    sub = subscribe(slots=two_slots())
    kept = hand_session(sub, occurs_on=date(2026, 6, 5))
    services.update_subscription(sub, starts_on=date(2026, 6, 2))
    assert exists(kept)
    services.add_pause(sub, from_date=date(2026, 6, 4), to_date=date(2026, 6, 6))
    assert exists(kept)
    slot = sub.slots.first()
    services.update_slot(slot, is_active=False)
    assert exists(kept)


def test_ending_a_subscription_removes_its_regular_sessions_only(subscribe):
    sub = subscribe(slots=two_slots())
    regular = hand_session(sub, occurs_on=date(2026, 6, 5))
    original = (
        Session.objects.filter(subscription=sub, generated=True)
        .order_by("starts_at")
        .first()
    )
    Session.objects.filter(pk=original.pk).update(status="cancelled")
    make_up = hand_session(
        sub, occurs_on=date(2026, 6, 6), kind="compensation", compensates=original
    )
    extra = hand_session(sub, occurs_on=date(2026, 6, 7), kind="extra")
    services.cancel_subscription(sub)
    assert not exists(regular)
    assert exists(make_up)
    assert exists(extra)
    assert exists(original)


def test_expiry_removes_regular_sessions_only(subscribe):
    sub = subscribe(slots=two_slots())
    regular = hand_session(sub, occurs_on=date(2026, 6, 5))
    extra = hand_session(sub, occurs_on=date(2026, 6, 7), kind="extra")
    rules.expire([sub.pk])
    assert not exists(regular)
    assert exists(extra)


def test_a_renewal_leaves_hand_added_sessions_until_the_old_term_ends(
    subscribe, clock
):
    sub = subscribe(slots=two_slots())
    added = hand_session(sub, occurs_on=date(2026, 6, 24))
    services.renew_subscription(sub, starts_on=date(2026, 6, 22))
    assert exists(added)
    clock.set(datetime(2026, 6, 22, 8, 0, tzinfo=UTC))
    services.run_lifecycle()
    assert not exists(added)
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DC exec -T django pytest -q etqan/scheduling/tests/test_session_classes_rules.py`
Expected: FAIL — the extra session counts (`assert 1 == 0`), the unpaid session is in payroll's list, the hand-added session is deleted by regeneration, the make-up and extra are deleted by cancel. (`test_a_regular_session_added_by_hand_counts_like_a_generated_one` and `test_a_renewal_leaves_…`'s last assertion pass already: guards.)

- [ ] **Step 3: The consumption rule and expiry**

In `backend/etqan/scheduling/services/rules.py`, below `EXCUSED = …`, add:

```python
# Slice B2a (A-2): only these kinds can use up the package.
COUNTED_KINDS = (Session.Kind.REGULAR, Session.Kind.COMPENSATION)
```

In `consuming`, extend the docstring's first paragraph with "Slice B2a: only regular and compensation sessions count, and never an original whose make-up is live (A-2, A-4)." and replace the returned `Q(...)` with:

```python
    return Q(
        **{
            f"{prefix}status": Session.Status.COMPLETED,
            f"{prefix}student_attendance__in": students,
            f"{prefix}teacher_attendance__in": teachers,
            f"{prefix}kind__in": COUNTED_KINDS,
            f"{prefix}compensated": False,
        }
    )
```

In `expire`, replace the deletion line with:

```python
    # Slice B2a (A-9): ending a subscription removes its untouched regular
    # sessions, hand-added ones too; make-ups and extras stay the office's.
    delete_untouched(
        untouched_sessions(
            subscription_id__in=subscription_ids, kind=Session.Kind.REGULAR
        )
    )
```

- [ ] **Step 4: Payroll reads paying sessions only**

In `backend/etqan/scheduling/services/paylock.py`, `payroll_sessions`: append to the docstring "Slice B2a (A-8): a session whose `pays_teacher` is off is left out." and change the filter to:

```python
        Session.objects.filter(
            occurs_on__range=(first, last), payroll_locked=False, pays_teacher=True
        )
```

- [ ] **Step 5: Regeneration deletes generated sessions; cancel deletes regular ones**

In `backend/etqan/scheduling/services/subscriptions.py`:

`_regenerate`:

```python
def _regenerate(subscription: Subscription) -> None:
    """Replace the untouched generated sessions (P4-7; slice B2a A-9: a
    session added by hand is the office's) and fill the horizon again."""
    rules.delete_untouched(
        rules.untouched_sessions(subscription=subscription, generated=True)
    )
    generation.generate_horizon(subscription)
```

`_refill`: in its `untouched_sessions(...)` call add `generated=True,`.

`cancel_subscription`: replace the last line with:

```python
    # Slice B2a (A-9): its untouched regular sessions go, hand-added included.
    rules.delete_untouched(
        rules.untouched_sessions(subscription=locked, kind=Session.Kind.REGULAR)
    )
```

`add_pause`: in its `untouched_sessions(...)` call add `generated=True,`.

`update_slot`: `rules.delete_untouched(rules.untouched_sessions(slot=slot, generated=True))`.

`renew_subscription`: `rules.untouched_sessions(subscription=old, occurs_on__gte=starts_on, generated=True)`.

- [ ] **Step 6: Run the tests and the scheduling, payroll and billing suites**

Run: `$DC exec -T django pytest -q etqan/scheduling etqan/payroll etqan/billing etqan/notifications`
Expected: PASS (existing behaviour for generated sessions is unchanged).

- [ ] **Step 7: Format and commit**

```bash
$DC exec -T django sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/scheduling/services/rules.py etqan/scheduling/services/paylock.py etqan/scheduling/services/subscriptions.py etqan/scheduling/tests/test_session_classes_rules.py
git -C backend commit -m "feat(scheduling): kinds in the consumption rule, pays_teacher in payroll, generated-only regeneration (B2a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Adding sessions by hand (`services/manual.py`)

**Files:**
- Modify: `backend/etqan/scheduling/services/generation.py` (rename `_conflicts` → `conflicts`)
- Modify: `backend/etqan/scheduling/services/subscriptions.py` (public aliases, D7)
- Modify: `backend/etqan/scheduling/services/rules.py` (`is_compensable`)
- Create: `backend/etqan/scheduling/services/manual.py`
- Modify: `backend/etqan/scheduling/services/__init__.py`
- Create: `backend/etqan/scheduling/tests/test_session_classes_manual.py`

**Interfaces:**
- Consumes: Task 1–2.
- Produces (exported from `etqan.scheduling.services`):
  - `Added` — frozen dataclass `(session: Session, conflicts: list[tuple[Session, Session]])`; `session` is read from `sessions_queryset()`.
  - `create_regular_session(*, by, subscription_id: int, occurs_on: date, start_time: time, teacher_id: int | None = None, minutes: int | None = None, meeting_url: str = "", pays_teacher: bool = True, notes: str = "") -> Added`
  - `create_extra_session(*, by, student_id: int, course_id: int, teacher_id: int, occurs_on: date, start_time: time, minutes: int, subscription_id: int | None = None, meeting_url: str = "", pays_teacher: bool = True, notes: str = "") -> Added`
  - `create_compensation(*, by, compensates_id: int, occurs_on: date, start_time: time, teacher_id: int | None = None, minutes: int | None = None, meeting_url: str = "", pays_teacher: bool = True, notes: str = "") -> Added`
  - `is_compensable(session: Session) -> bool` (from `rules`)
  - `generation.conflicts(created: list[Session]) -> list[tuple[Session, Session]]`
  - `subscriptions.active_student`, `active_course`, `course_teacher` (aliases)
  People are User ids; `by` is a User or `None` (D4).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/scheduling/tests/test_session_classes_manual.py`:

```python
"""Slice B2a §4.1: the three ways the office adds a session, and A-3's
eligibility for a make-up."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

import pytest

from etqan.academy import services as academy_services
from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
TEN = time(10, 0)


@pytest.fixture
def admin():
    return make_admin()


def first(sub):
    return Session.objects.filter(subscription=sub).order_by("starts_at").first()


def code(excinfo):
    return excinfo.value.code


# ── Regular ──────────────────────────────────────────────────────────────────


def test_a_regular_session_takes_the_subscriptions_people(subscribe, world, admin):
    sub = subscribe(slots=two_slots())
    added = services.create_regular_session(
        by=admin, subscription_id=sub.pk, occurs_on=date(2026, 6, 5), start_time=TEN
    )
    session = added.session
    assert (session.kind, session.generated, session.created_by) == (
        "regular",
        False,
        admin,
    )
    assert session.student == sub.student
    assert session.course == sub.course
    assert session.teacher == sub.teacher
    assert session.minutes == 45
    assert session.meeting_url == "https://meet.test/bilal"
    assert session.starts_at == datetime(2026, 6, 5, 10, 0, tzinfo=UTC)
    assert session.pays_teacher is True
    assert added.conflicts == []


def test_a_regular_session_in_the_past_is_recorded_and_open_for_attendance(
    subscribe, admin
):
    sub = subscribe(slots=two_slots(), starts_on=date(2026, 5, 25))
    session = services.create_regular_session(
        by=admin, subscription_id=sub.pk, occurs_on=date(2026, 5, 27), start_time=TEN
    ).session
    assert services.has_started(session) is True


@pytest.mark.parametrize(
    "day", [date(2026, 5, 31), date(2026, 7, 9)], ids=["before", "after-grace"]
)
def test_a_regular_session_stays_inside_the_window(subscribe, admin, day):
    sub = subscribe(slots=two_slots())
    with pytest.raises(ValidationError) as excinfo:
        services.create_regular_session(
            by=admin, subscription_id=sub.pk, occurs_on=day, start_time=TEN
        )
    assert excinfo.value.field == "occurs_on"


def test_a_regular_session_stays_outside_the_pauses(subscribe, admin):
    sub = subscribe(slots=two_slots())
    services.add_pause(sub, from_date=date(2026, 6, 4), to_date=date(2026, 6, 6))
    with pytest.raises(ValidationError) as excinfo:
        services.create_regular_session(
            by=admin, subscription_id=sub.pk, occurs_on=date(2026, 6, 5), start_time=TEN
        )
    assert excinfo.value.field == "occurs_on"


def test_a_regular_session_needs_a_live_subscription(subscribe, admin):
    sub = subscribe(slots=two_slots())
    services.cancel_subscription(sub)
    with pytest.raises(ConflictError) as excinfo:
        services.create_regular_session(
            by=admin, subscription_id=sub.pk, occurs_on=date(2026, 6, 5), start_time=TEN
        )
    assert code(excinfo) == "scheduling.not_allowed_in_status"


def test_a_regular_session_needs_an_active_student(subscribe, world, admin):
    sub = subscribe(slots=two_slots())
    identity_services.deactivate(world.student, by=None)
    with pytest.raises(ValidationError) as excinfo:
        services.create_regular_session(
            by=admin, subscription_id=sub.pk, occurs_on=date(2026, 6, 5), start_time=TEN
        )
    assert excinfo.value.field == "subscription"


def test_a_regular_session_teacher_must_teach_the_course(subscribe, admin):
    sub = subscribe(slots=two_slots())
    stranger = make_teacher("Hamza")
    with pytest.raises(ValidationError) as excinfo:
        services.create_regular_session(
            by=admin,
            subscription_id=sub.pk,
            occurs_on=date(2026, 6, 5),
            start_time=TEN,
            teacher_id=stranger.id,
        )
    assert excinfo.value.field == "teacher"


def test_an_overlap_with_the_teachers_other_session_is_reported(subscribe, admin):
    sub = subscribe(slots=two_slots())
    added = services.create_regular_session(
        by=admin,
        subscription_id=sub.pk,
        occurs_on=date(2026, 6, 1),
        start_time=time(18, 15),
    )
    [(session, other)] = added.conflicts
    assert session.pk == added.session.pk
    assert other.occurs_on == date(2026, 6, 1)


# ── Extra ────────────────────────────────────────────────────────────────────


def test_an_extra_session_never_uses_up_the_package(subscribe, world, admin, clock):
    sub = subscribe(slots=two_slots())
    session = services.create_extra_session(
        by=admin,
        student_id=world.student.id,
        course_id=world.course.id,
        teacher_id=world.teacher.id,
        occurs_on=date(2026, 6, 2),
        start_time=TEN,
        minutes=30,
        subscription_id=sub.pk,
        pays_teacher=False,
    ).session
    assert (session.kind, session.pays_teacher, session.minutes) == ("extra", False, 30)
    clock.set(datetime(2026, 6, 2, 11, 0, tzinfo=UTC))
    services.mark_attendance(session, by=admin, student_attendance="present")
    assert services.derived(sub).sessions_used == 0


def test_an_extra_session_needs_no_subscription_but_only_the_students(
    subscribe, world, admin
):
    sub = subscribe(slots=two_slots())
    alone = services.create_extra_session(
        by=admin,
        student_id=world.student.id,
        course_id=world.course.id,
        teacher_id=world.teacher.id,
        occurs_on=date(2026, 6, 2),
        start_time=TEN,
        minutes=30,
    ).session
    assert alone.subscription is None
    other = make_student("Omar")
    with pytest.raises(ValidationError) as excinfo:
        services.create_extra_session(
            by=admin,
            student_id=other.id,
            course_id=world.course.id,
            teacher_id=world.teacher.id,
            occurs_on=date(2026, 6, 2),
            start_time=TEN,
            minutes=30,
            subscription_id=sub.pk,
        )
    assert excinfo.value.field == "subscription"


def test_an_added_session_on_a_clock_change_uses_plans_4_conversion(world, admin):
    academy_services.update_settings(timezone="Europe/Berlin")
    session = services.create_extra_session(
        by=admin,
        student_id=world.student.id,
        course_id=world.course.id,
        teacher_id=world.teacher.id,
        # 25 Oct 2026: 02:30 happens twice in Berlin; the first is CEST.
        occurs_on=date(2026, 10, 25),
        start_time=time(2, 30),
        minutes=30,
    ).session
    assert session.starts_at == datetime(2026, 10, 25, 0, 30, tzinfo=UTC)


# ── Compensation ─────────────────────────────────────────────────────────────


def started(clock):
    clock.set(datetime(2026, 6, 1, 18, 5, tzinfo=UTC))


@pytest.mark.parametrize(
    ("status", "student", "teacher", "switches", "expected"),
    [
        ("cancelled", "not_set", "not_set", {}, True),
        ("at_disposal", "not_set", "not_set", {}, True),
        ("completed", "excused", "present", {}, True),
        ("completed", "excused", "present", {"excused_consumes_session": True}, False),
        ("completed", "absent", "present", {}, False),
        ("completed", "absent", "present", {"absent_consumes_session": False}, True),
        ("completed", "present", "absent", {}, True),
        ("completed", "present", "present", {}, False),
        ("scheduled", "not_set", "not_set", {}, False),
    ],
)
def test_who_can_be_made_up(subscribe, status, student, teacher, switches, expected):  # noqa: PLR0913 -- pytest parameters
    session = first(subscribe(slots=two_slots()))
    Session.objects.filter(pk=session.pk).update(
        status=status, student_attendance=student, teacher_attendance=teacher
    )
    if switches:
        academy_services.update_settings(**switches)
    session.refresh_from_db()
    assert services.is_compensable(session) is expected


def test_an_extra_session_is_never_made_up(world, admin):
    extra = services.create_extra_session(
        by=admin,
        student_id=world.student.id,
        course_id=world.course.id,
        teacher_id=world.teacher.id,
        occurs_on=date(2026, 6, 2),
        start_time=TEN,
        minutes=30,
    ).session
    Session.objects.filter(pk=extra.pk).update(status="cancelled")
    extra.refresh_from_db()
    assert services.is_compensable(extra) is False


def test_a_make_up_copies_the_original_and_marks_it(subscribe, admin, clock):
    sub = subscribe(slots=two_slots())
    original = first(sub)
    services.cancel_session(original, by=admin, reason="Eid")
    session = services.create_compensation(
        by=admin, compensates_id=original.pk, occurs_on=date(2026, 6, 9), start_time=TEN
    ).session
    assert (session.kind, session.compensates_id) == ("compensation", original.pk)
    assert session.subscription == sub
    assert session.student == original.student
    assert session.teacher == original.teacher
    assert session.minutes == original.minutes
    original.refresh_from_db()
    assert original.compensated is True


def test_a_second_make_up_is_refused(subscribe, admin):
    original = first(subscribe(slots=two_slots()))
    services.cancel_session(original, by=admin, reason="Eid")
    services.create_compensation(
        by=admin, compensates_id=original.pk, occurs_on=date(2026, 6, 9), start_time=TEN
    )
    with pytest.raises(ConflictError) as excinfo:
        services.create_compensation(
            by=admin,
            compensates_id=original.pk,
            occurs_on=date(2026, 6, 10),
            start_time=TEN,
        )
    assert code(excinfo) == "scheduling.already_compensated"


def test_a_scheduled_session_is_not_compensable(subscribe, admin):
    original = first(subscribe(slots=two_slots()))
    with pytest.raises(ConflictError) as excinfo:
        services.create_compensation(
            by=admin,
            compensates_id=original.pk,
            occurs_on=date(2026, 6, 9),
            start_time=TEN,
        )
    assert code(excinfo) == "scheduling.not_compensable"


def test_an_unknown_original_is_a_field_error(admin):
    with pytest.raises(ValidationError) as excinfo:
        services.create_compensation(
            by=admin, compensates_id=999999, occurs_on=date(2026, 6, 9), start_time=TEN
        )
    assert excinfo.value.field == "compensates"


def test_a_make_up_may_have_another_teacher_of_the_course(subscribe, world, admin):
    hamza = make_teacher("Hamza")
    catalogue_services.update_course(
        world.course, teacher_ids=[world.teacher.id, hamza.id]
    )
    original = first(subscribe(slots=two_slots()))
    services.cancel_session(original, by=admin, reason="Eid")
    session = services.create_compensation(
        by=admin,
        compensates_id=original.pk,
        occurs_on=date(2026, 6, 9),
        start_time=TEN,
        teacher_id=hamza.id,
    ).session
    assert session.teacher.user == hamza
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DC exec -T django pytest -q etqan/scheduling/tests/test_session_classes_manual.py`
Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'create_regular_session'`.

- [ ] **Step 3: `generation.conflicts` (D8)**

In `backend/etqan/scheduling/services/generation.py` rename `def _conflicts(` to `def conflicts(` and its one call in `generate` to `result.conflicts = conflicts(created)`. Extend its docstring: "Slice B2a: also used for one session added by hand."

- [ ] **Step 4: Public aliases (D7)**

In `backend/etqan/scheduling/services/subscriptions.py`, after `_teacher`:

```python
# Slice B2a (D7): the same checks for the sessions the office adds by hand
# (services/manual.py).
active_student = _student
active_course = _course
course_teacher = _teacher
```

- [ ] **Step 5: `rules.is_compensable`**

In `backend/etqan/scheduling/services/rules.py`, after `has_marked_sessions`:

```python
def is_compensable(session: Session) -> bool:
    """Slice B2a A-3: a session of a subscription that did not use up the
    package — cancelled, at the administration's disposal, or completed
    without consuming (the academy's switches are read live) — that is not
    an extra session and has no live make-up. Compensations qualify too, so
    a make-up can itself be made up."""
    if (
        session.kind == Session.Kind.EXTRA
        or session.compensated
        or session.subscription_id is None
    ):
        return False
    if session.status in (Session.Status.CANCELLED, Session.Status.AT_DISPOSAL):
        return True
    if session.status != Session.Status.COMPLETED:
        return False
    return not Session.objects.filter(consuming(settings()), pk=session.pk).exists()
```

- [ ] **Step 6: `services/manual.py`**

Create `backend/etqan/scheduling/services/manual.py`:

```python
"""Sessions the office adds by hand (slice B2a spec §4.1): a regular session
on a subscription, an extra session outside the package, and a compensation
(make-up) for a session that did not use up the package. Each answers with
the session and the teacher's other sessions it overlaps (P4-9: reported,
never blocked). ``by`` is the User who added it, or None for the seeds
("system", A-12)."""

from dataclasses import dataclass
from datetime import date
from datetime import time

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import from_django
from etqan.scheduling import dates
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.services import generation
from etqan.scheduling.services import rules
from etqan.scheduling.services import subscriptions as subs


@dataclass(frozen=True)
class Added:
    session: Session
    conflicts: list[tuple[Session, Session]]


def _session(  # noqa: PLR0913 -- keyword-only; the columns a hand-added session sets
    *,
    by,
    kind: str,
    subscription: Subscription | None,
    student,
    course,
    teacher,
    occurs_on: date,
    start_time: time,
    minutes: int,
    meeting_url: str,
    pays_teacher: bool,
    notes: str,
    compensates: Session | None = None,
) -> Session:
    return Session(
        kind=kind,
        subscription=subscription,
        student=student,
        course=course,
        teacher=teacher,
        compensates=compensates,
        occurs_on=occurs_on,
        # Plan 4's single conversion: a missing local time moves forward, an
        # ambiguous one takes the first occurrence.
        starts_at=dates.to_utc(occurs_on, start_time, rules.settings().timezone),
        minutes=minutes,
        meeting_url=meeting_url or teacher.default_meeting_url,
        pays_teacher=pays_teacher,
        notes=notes,
        created_by=by,
        # Plan 12b: the subscription's supervisor, as generation does.
        supervisor_id=subscription.supervisor_id if subscription else None,
        generated=False,
    )


def _add(session: Session) -> Added:
    try:
        # Constraints are checked by the callers, with readable errors.
        session.full_clean(validate_constraints=False)
    except DjangoValidationError as exc:
        raise from_django(exc) from None
    session.save()
    fresh = rules.sessions_queryset().get(pk=session.pk)
    return Added(fresh, generation.conflicts([fresh]))


@transaction.atomic
def create_regular_session(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §6)
    *,
    by,
    subscription_id: int,
    occurs_on: date,
    start_time: time,
    teacher_id: int | None = None,
    minutes: int | None = None,
    meeting_url: str = "",
    pays_teacher: bool = True,
    notes: str = "",
) -> Added:
    """A-6: on an active or paused subscription with an active student,
    inside its generating window and outside its pauses. The teacher
    defaults to the subscription's and must teach the course. The
    subscription is locked first (Plan 4's lock order), so a cancel or an
    expiry racing with this waits."""
    sub = Subscription.objects.select_for_update().filter(pk=subscription_id).first()
    if sub is None:
        raise ValidationError("Choose a subscription.", field="subscription")
    rules.require_status(sub)
    if not sub.student.user.is_active:
        raise ValidationError(
            "This subscription's student is not active.", field="subscription"
        )
    span = rules.term(sub, rules.settings().renewal_grace_days)
    last = rules.generation_last_day(sub, span.grace_ends_on)
    if not sub.starts_on <= occurs_on <= last or rules.covering_pause(sub, occurs_on):
        raise ValidationError(
            "Choose a day inside the subscription's term and outside its pauses.",
            field="occurs_on",
        )
    teacher = subs.course_teacher(teacher_id or sub.teacher.user_id, sub.course)
    return _add(
        _session(
            by=by,
            kind=Session.Kind.REGULAR,
            subscription=sub,
            student=sub.student,
            course=sub.course,
            teacher=teacher,
            occurs_on=occurs_on,
            start_time=start_time,
            minutes=minutes or sub.session_minutes,
            meeting_url=meeting_url,
            pays_teacher=pays_teacher,
            notes=notes,
        )
    )


@transaction.atomic
def create_extra_session(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §6)
    *,
    by,
    student_id: int,
    course_id: int,
    teacher_id: int,
    occurs_on: date,
    start_time: time,
    minutes: int,
    subscription_id: int | None = None,
    meeting_url: str = "",
    pays_teacher: bool = True,
    notes: str = "",
) -> Added:
    """A-7: an active student, an active course and an active teacher who
    teaches it; a subscription is optional and must be the student's. It
    never uses up the package (A-2)."""
    student = subs.active_student(student_id)
    course = subs.active_course(course_id)
    teacher = subs.course_teacher(teacher_id, course)
    subscription = None
    if subscription_id is not None:
        subscription = Subscription.objects.filter(
            pk=subscription_id, student=student
        ).first()
        if subscription is None:
            raise ValidationError(
                "Choose one of the student's subscriptions.", field="subscription"
            )
    return _add(
        _session(
            by=by,
            kind=Session.Kind.EXTRA,
            subscription=subscription,
            student=student,
            course=course,
            teacher=teacher,
            occurs_on=occurs_on,
            start_time=start_time,
            minutes=minutes,
            meeting_url=meeting_url,
            pays_teacher=pays_teacher,
            notes=notes,
        )
    )


@transaction.atomic
def create_compensation(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §6)
    *,
    by,
    compensates_id: int,
    occurs_on: date,
    start_time: time,
    teacher_id: int | None = None,
    minutes: int | None = None,
    meeting_url: str = "",
    pays_teacher: bool = True,
    notes: str = "",
) -> Added:
    """A-3 / A-5: a make-up for a session that did not use up the package.
    The original's row is locked while it is checked, so two make-ups for it
    are serialised and the second is refused; it is then marked
    ``compensated`` (A-4). The make-up copies the original's student, course
    and subscription; its date is free."""
    original = Session.objects.select_for_update().filter(pk=compensates_id).first()
    if original is None:
        raise ValidationError("Choose a session to make up.", field="compensates")
    if original.compensated:
        raise ConflictError(
            "This session already has a make-up session.",
            code="scheduling.already_compensated",
        )
    if not rules.is_compensable(original):
        raise ConflictError(
            "Only a session that did not use up the package can be made up.",
            code="scheduling.not_compensable",
        )
    teacher = subs.course_teacher(
        teacher_id or original.teacher.user_id, original.course
    )
    added = _add(
        _session(
            by=by,
            kind=Session.Kind.COMPENSATION,
            subscription=original.subscription,
            student=original.student,
            course=original.course,
            teacher=teacher,
            occurs_on=occurs_on,
            start_time=start_time,
            minutes=minutes or original.minutes,
            meeting_url=meeting_url,
            pays_teacher=pays_teacher,
            notes=notes,
            compensates=original,
        )
    )
    original.compensated = True
    original.save(update_fields=["compensated", "updated_at"])
    return added
```

- [ ] **Step 7: Export them**

In `backend/etqan/scheduling/services/__init__.py` add, in alphabetical position among the imports:

```python
from etqan.scheduling.services.manual import Added
from etqan.scheduling.services.manual import create_compensation
from etqan.scheduling.services.manual import create_extra_session
from etqan.scheduling.services.manual import create_regular_session
from etqan.scheduling.services.rules import is_compensable
```

and `"Added"`, `"create_compensation"`, `"create_extra_session"`, `"create_regular_session"`, `"is_compensable"` to `__all__` (sorted as Ruff's `RUF022` expects).

- [ ] **Step 8: Run the tests**

Run: `$DC exec -T django pytest -q etqan/scheduling`
Expected: PASS.

- [ ] **Step 9: Format, lint-imports, commit**

```bash
$DC exec -T django sh -c 'ruff check --fix . && ruff format . && lint-imports'
git -C backend add etqan/scheduling/services etqan/scheduling/tests/test_session_classes_manual.py
git -C backend commit -m "feat(scheduling): add regular, extra and compensation sessions by hand (B2a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The frozen original, the compensation lifecycle, deleting a hand-added session

**Files:**
- Modify: `backend/etqan/scheduling/services/attendance.py`
- Modify: `backend/etqan/scheduling/services/manual.py` (`delete_session`)
- Modify: `backend/etqan/scheduling/services/__init__.py`
- Create: `backend/etqan/scheduling/tests/test_session_classes_lifecycle.py`

**Interfaces:**
- Consumes: Task 3.
- Produces: `attendance.refuse_if_compensated(session)`, `attendance.release_original(session)`; `delete_session(session: Session) -> None` (exported). `mark_attendance`, `cancel_session`, `restore_session`, `bulk_sessions` keep their signatures.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/scheduling/tests/test_session_classes_lifecycle.py`:

```python
"""Slice B2a A-4 / §4.6 (an original with a live make-up is frozen; a
make-up's cancel and restore move the mark) and §4.2 (deleting a session
added by hand)."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

import pytest

from etqan.academy import services as academy_services
from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
TEN = time(10, 0)


@pytest.fixture
def admin():
    return make_admin()


@pytest.fixture
def excused(subscribe, admin, clock):
    """Monday 1 June's session, after it started: the student excused (which
    does not count by default), so it can be made up."""
    sub = subscribe(slots=two_slots())
    session = Session.objects.filter(subscription=sub).order_by("starts_at").first()
    clock.set(datetime(2026, 6, 1, 18, 5, tzinfo=UTC))
    services.mark_attendance(
        session, by=admin, student_attendance="excused", teacher_attendance="present"
    )
    return session


def make_up(original, admin, day=date(2026, 6, 9)):
    return services.create_compensation(
        by=admin, compensates_id=original.pk, occurs_on=day, start_time=TEN
    ).session


def refused(excinfo, expected):
    assert excinfo.value.code == expected


def test_the_original_is_frozen_while_its_make_up_is_live(excused, admin):
    make_up(excused, admin)
    with pytest.raises(ConflictError) as excinfo:
        services.mark_attendance(excused, by=admin, student_attendance="present")
    refused(excinfo, "scheduling.has_compensation")
    with pytest.raises(ConflictError) as excinfo:
        services.cancel_session(excused, by=admin, reason="Eid")
    refused(excinfo, "scheduling.has_compensation")
    result = services.bulk_sessions([excused.pk], action="absent", by=admin)
    assert result.skipped == [(excused.pk, "scheduling.has_compensation")]


def test_a_cancelled_original_with_a_make_up_is_not_restored(subscribe, admin):
    sub = subscribe(slots=two_slots())
    original = Session.objects.filter(subscription=sub).order_by("starts_at").first()
    services.cancel_session(original, by=admin, reason="Eid")
    make_up(original, admin)
    with pytest.raises(ConflictError) as excinfo:
        services.restore_session(original)
    refused(excinfo, "scheduling.has_compensation")


def test_flipping_a_switch_never_counts_an_original_and_its_make_up_twice(
    excused, admin, clock
):
    session = make_up(excused, admin)
    clock.set(datetime(2026, 6, 9, 11, 0, tzinfo=UTC))
    services.mark_attendance(session, by=admin, student_attendance="present")
    sub = excused.subscription
    assert services.derived(sub).sessions_used == 1
    academy_services.update_settings(excused_consumes_session=True)
    assert services.derived(sub).sessions_used == 1


def test_cancelling_the_make_up_frees_the_original(excused, admin):
    session = make_up(excused, admin)
    services.cancel_session(session, by=admin, reason="Teacher ill")
    excused.refresh_from_db()
    assert excused.compensated is False
    assert services.is_compensable(excused) is True


def test_restoring_the_make_up_marks_the_original_again(excused, admin):
    session = make_up(excused, admin)
    services.cancel_session(session, by=admin, reason="Teacher ill")
    services.restore_session(session)
    excused.refresh_from_db()
    assert excused.compensated is True


def test_a_make_up_is_not_restored_over_another_live_one(excused, admin):
    first = make_up(excused, admin)
    services.cancel_session(first, by=admin, reason="Teacher ill")
    make_up(excused, admin, day=date(2026, 6, 10))
    with pytest.raises(ConflictError) as excinfo:
        services.restore_session(first)
    refused(excinfo, "scheduling.already_compensated")


def test_a_make_up_is_not_restored_once_the_original_counts(excused, admin):
    first = make_up(excused, admin)
    services.cancel_session(first, by=admin, reason="Teacher ill")
    services.mark_attendance(excused, by=admin, student_attendance="present")
    with pytest.raises(ConflictError) as excinfo:
        services.restore_session(first)
    refused(excinfo, "scheduling.not_compensable")


# ── Deleting a session added by hand (§4.2) ──────────────────────────────────


def test_a_hand_added_session_is_deleted_and_a_make_up_frees_its_original(
    excused, admin
):
    session = make_up(excused, admin)
    services.delete_session(session)
    assert not Session.objects.filter(pk=session.pk).exists()
    excused.refresh_from_db()
    assert excused.compensated is False


def test_a_generated_session_is_never_deleted(excused, admin):
    with pytest.raises(ConflictError) as excinfo:
        services.delete_session(
            Session.objects.filter(generated=True).exclude(pk=excused.pk).first()
        )
    refused(excinfo, "scheduling.session_generated")


def test_a_compensated_hand_added_session_is_not_deleted(subscribe, admin):
    sub = subscribe(slots=two_slots())
    added = services.create_regular_session(
        by=admin, subscription_id=sub.pk, occurs_on=date(2026, 6, 5), start_time=TEN
    ).session
    services.cancel_session(added, by=admin, reason="Eid")
    make_up(added, admin)
    with pytest.raises(ConflictError) as excinfo:
        services.delete_session(added)
    refused(excinfo, "scheduling.has_compensation")


def test_a_marked_or_cancelled_hand_added_session_is_not_deleted(
    subscribe, admin, clock
):
    sub = subscribe(slots=two_slots())
    added = services.create_regular_session(
        by=admin, subscription_id=sub.pk, occurs_on=date(2026, 6, 1), start_time=TEN
    ).session
    clock.set(datetime(2026, 6, 1, 10, 5, tzinfo=UTC))
    services.mark_attendance(added, by=admin, teacher_attendance="present")
    with pytest.raises(ConflictError) as excinfo:
        services.delete_session(added)
    refused(excinfo, "scheduling.session_marked")
    other = services.create_regular_session(
        by=admin, subscription_id=sub.pk, occurs_on=date(2026, 6, 5), start_time=TEN
    ).session
    services.cancel_session(other, by=admin, reason="Eid")
    with pytest.raises(ConflictError) as excinfo:
        services.delete_session(other)
    refused(excinfo, "scheduling.not_allowed_in_status")


def test_a_paid_session_is_refused_first(subscribe, admin):
    sub = subscribe(slots=two_slots())
    added = services.create_regular_session(
        by=admin, subscription_id=sub.pk, occurs_on=date(2026, 6, 5), start_time=TEN
    ).session
    services.lock_sessions([added.pk])
    with pytest.raises(ConflictError) as excinfo:
        services.delete_session(added)
    refused(excinfo, "payroll.payslip_issued")
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DC exec -T django pytest -q etqan/scheduling/tests/test_session_classes_lifecycle.py`
Expected: FAIL — attendance on the compensated original succeeds; `services.delete_session` is missing.

- [ ] **Step 3: Attendance — the frozen original and the compensation lifecycle**

In `backend/etqan/scheduling/services/attendance.py`:

Add the imports `from etqan.scheduling.services import rules`, and the constants below `NOT_SET`:

```python
AT_DISPOSAL = Session.Status.AT_DISPOSAL
COMPENSATION = Session.Kind.COMPENSATION
```

After `_not_allowed`, add:

```python
def refuse_if_compensated(session: Session) -> None:
    """Slice B2a A-4: an original with a live make-up takes no attendance
    change, restore, cancel or disposal. Call it on the locked row."""
    if session.compensated:
        raise ConflictError(
            "This session has a make-up session, so it can't change.",
            code="scheduling.has_compensation",
        )


def release_original(session: Session) -> None:
    """A compensation that stops being live (cancelled or deleted) frees its
    original (A-4). The compensation's row is locked by the caller and the
    original's is taken by this update; nothing locks them the other way
    round, so no cycle forms (plan D9)."""
    if session.kind == COMPENSATION and session.compensates_id is not None:
        Session.objects.filter(pk=session.compensates_id).update(
            compensated=False, updated_at=dates.now()
        )


def _reclaim_original(session: Session) -> None:
    """Restoring a compensation (§4.6): its original must still qualify and
    have no other live make-up; it is then marked again."""
    original = Session.objects.select_for_update().get(pk=session.compensates_id)
    if original.compensated:
        raise ConflictError(
            "This session already has a make-up session.",
            code="scheduling.already_compensated",
        )
    if not rules.is_compensable(original):
        raise ConflictError(
            "Only a session that did not use up the package can be made up.",
            code="scheduling.not_compensable",
        )
    original.compensated = True
    original.save(update_fields=["compensated", "updated_at"])
```

In `mark_attendance`, directly after `refuse_if_paid(locked)` add `refuse_if_compensated(locked)`.

In `cancel_session`, after `refuse_if_paid(locked)` add `refuse_if_compensated(locked)`, and after `locked.save(...)` add `release_original(locked)`.

Replace `restore_session` with:

```python
@transaction.atomic
def restore_session(session: Session) -> Session:
    """Spec §4.3: back to scheduled, or to completed when the student's
    attendance is set; the cancel fields are cleared. A session an issued
    payslip pays is refused before its status is looked at (Plan 7 spec
    §4.5). Slice B2a: a compensated original is frozen (A-4); restoring a
    cancelled compensation re-checks and marks its original (§4.6)."""
    locked = lock(session)
    refuse_if_paid(locked)
    refuse_if_compensated(locked)
    if locked.status != CANCELLED:
        raise _not_allowed(locked)
    if locked.kind == COMPENSATION:
        _reclaim_original(locked)
    locked.status = SCHEDULED if locked.student_attendance == NOT_SET else COMPLETED
    locked.cancel_reason = ""
    locked.cancelled_by = None
    locked.cancelled_at = None
    locked.save(
        update_fields=[
            "status",
            "cancel_reason",
            "cancelled_by",
            "cancelled_at",
            "updated_at",
        ]
    )
    return locked
```

`bulk_sessions` needs no change: the refusals are `ConflictError`s and are skipped with their code.

- [ ] **Step 4: `delete_session`**

Append to `backend/etqan/scheduling/services/manual.py` (add `from etqan.scheduling.services import attendance` and `from etqan.scheduling.services.paylock import refuse_if_paid` to its imports):

```python
NOT_SET = Session.Attendance.NOT_SET


@transaction.atomic
def delete_session(session: Session) -> None:
    """Spec §4.2 (A-10): only a session added by hand, unmarked, scheduled or
    at the administration's disposal, unpaid and with no live make-up.
    Refusals in this order: paid, generated, compensated, marked, status.
    Deleting a compensation frees its original."""
    locked = attendance.lock(session)
    refuse_if_paid(locked)
    if locked.generated:
        raise ConflictError(
            "A generated session can't be deleted. Cancel it instead.",
            code="scheduling.session_generated",
        )
    attendance.refuse_if_compensated(locked)
    if locked.student_attendance != NOT_SET or locked.teacher_attendance != NOT_SET:
        raise ConflictError(
            "Attendance is marked on this session.", code="scheduling.session_marked"
        )
    if locked.status not in (Session.Status.SCHEDULED, Session.Status.AT_DISPOSAL):
        raise ConflictError(
            f"Not allowed while the session is {locked.status}.",
            code="scheduling.not_allowed_in_status",
        )
    attendance.release_original(locked)
    locked.delete()
```

Export `delete_session` from `services/__init__.py` (import and `__all__`).

- [ ] **Step 5: Run the tests**

Run: `$DC exec -T django pytest -q etqan/scheduling etqan/payroll etqan/notifications`
Expected: PASS.

- [ ] **Step 6: Format and commit**

```bash
$DC exec -T django sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/scheduling/services etqan/scheduling/tests/test_session_classes_lifecycle.py
git -C backend commit -m "feat(scheduling): freeze a made-up original; make-up cancel and restore; delete hand-added sessions (B2a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: At the administration's disposal; `pays_teacher`

**Files:**
- Modify: `backend/etqan/scheduling/services/attendance.py` (`place_at_disposal`, `mark_attendance`, `cancel_session`, `restore_session`)
- Modify: `backend/etqan/scheduling/services/manual.py` (`set_pays_teacher`)
- Modify: `backend/etqan/scheduling/services/subscriptions.py` (`delete_subscription`)
- Modify: `backend/etqan/scheduling/services/board.py` (`STATES`)
- Modify: `backend/etqan/scheduling/services/__init__.py`
- Create: `backend/etqan/scheduling/tests/test_session_classes_disposal.py`

**Interfaces:**
- Produces (exported): `place_at_disposal(session: Session, *, reason: str = "") -> Session`; `set_pays_teacher(session: Session, *, pays_teacher: bool) -> Session`. Today board row state `"at_disposal"`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/scheduling/tests/test_session_classes_disposal.py`:

```python
"""Slice B2a A-11 / §4.5 (at the administration's disposal) and §4.7
(`pays_teacher`)."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db


@pytest.fixture
def admin():
    return make_admin()


@pytest.fixture
def monday(subscribe):
    """Monday 1 June's 18:00 session; the clock is 08:00 that day."""
    sub = subscribe(slots=two_slots())
    return Session.objects.filter(subscription=sub).order_by("starts_at").first()


def test_a_scheduled_session_is_placed_and_restored(monday):
    placed = services.place_at_disposal(monday, reason="  Student travelling  ")
    assert (placed.status, placed.disposal_reason) == (
        "at_disposal",
        "Student travelling",
    )
    restored = services.restore_session(monday)
    assert (restored.status, restored.disposal_reason) == ("scheduled", "")


def test_only_a_scheduled_session_is_placed(monday, admin):
    services.cancel_session(monday, by=admin, reason="Eid")
    with pytest.raises(ConflictError) as excinfo:
        services.place_at_disposal(monday)
    assert excinfo.value.code == "scheduling.not_allowed_in_status"


def test_a_paid_session_is_not_placed(monday):
    services.lock_sessions([monday.pk])
    with pytest.raises(ConflictError) as excinfo:
        services.place_at_disposal(monday)
    assert excinfo.value.code == "payroll.payslip_issued"


def test_its_student_attendance_is_refused_and_its_teachers_taken(
    monday, admin, clock
):
    services.place_at_disposal(monday)
    clock.set(datetime(2026, 6, 1, 18, 5, tzinfo=UTC))
    with pytest.raises(ConflictError) as excinfo:
        services.mark_attendance(monday, by=admin, student_attendance="present")
    assert excinfo.value.code == "scheduling.not_allowed_in_status"
    marked = services.mark_attendance(monday, by=admin, teacher_attendance="present")
    assert (marked.status, marked.teacher_attendance) == ("at_disposal", "present")
    result = services.bulk_sessions([monday.pk], action="present", by=admin)
    assert result.skipped == [(monday.pk, "scheduling.not_allowed_in_status")]


def test_it_is_cancelled_keeping_the_reason_and_restored_to_scheduled(
    monday, admin
):
    services.place_at_disposal(monday, reason="Travelling")
    cancelled = services.cancel_session(monday, by=admin, reason="Eid")
    assert (cancelled.status, cancelled.disposal_reason) == ("cancelled", "Travelling")
    restored = services.restore_session(monday)
    assert (restored.status, restored.disposal_reason) == ("scheduled", "")


def test_it_never_counts_and_the_system_keeps_it(monday, subscribe):
    services.place_at_disposal(monday)
    sub = monday.subscription
    services.update_slot(monday.slot, minutes=50)
    services.generate(date(2026, 6, 1), date(2026, 6, 1), subscription=sub)
    monday.refresh_from_db()
    assert monday.status == "at_disposal"
    assert Session.objects.filter(slot=monday.slot, occurs_on=monday.occurs_on).count() == 1
    assert services.derived(sub).sessions_used == 0


def test_a_subscription_with_one_is_not_deleted(monday):
    services.place_at_disposal(monday)
    with pytest.raises(ConflictError) as excinfo:
        services.delete_subscription(monday.subscription, before_delete=lambda _: None)
    assert excinfo.value.code == "scheduling.has_marked_sessions"


def test_the_today_board_shows_it(monday):
    services.place_at_disposal(monday)
    [row] = [r for r in services.today_board() if r.session and r.session.pk == monday.pk]
    assert row.state == "at_disposal"


def test_pays_teacher_is_switched_until_a_payslip_pays_it(monday):
    assert services.set_pays_teacher(monday, pays_teacher=False).pays_teacher is False
    services.lock_sessions([monday.pk])
    with pytest.raises(ConflictError) as excinfo:
        services.set_pays_teacher(monday, pays_teacher=True)
    assert excinfo.value.code == "payroll.payslip_issued"
```

(The slot edit regenerates the slot's untouched sessions; the `at_disposal` row is not untouched, so it stays and generation skips its (slot, date).)

- [ ] **Step 2: Run them to see them fail**

Run: `$DC exec -T django pytest -q etqan/scheduling/tests/test_session_classes_disposal.py`
Expected: FAIL — `place_at_disposal` missing.

- [ ] **Step 3: Attendance**

In `backend/etqan/scheduling/services/attendance.py`:

In `mark_attendance`, after the cancelled check add:

```python
    if student_attendance is not None and locked.status == AT_DISPOSAL:
        # Slice B2a A-11: its teacher's attendance is taken; its student's not.
        raise _not_allowed(locked)
```

In `cancel_session`, change the allowed statuses to `(SCHEDULED, COMPLETED, AT_DISPOSAL)` and extend the docstring: "Slice B2a: also from at_disposal, keeping `disposal_reason` for the record."

In `restore_session`, replace `if locked.status != CANCELLED: raise _not_allowed(locked)` … `locked.status = …` with:

```python
    if locked.status == AT_DISPOSAL:
        locked.status = SCHEDULED
    elif locked.status == CANCELLED:
        if locked.kind == COMPENSATION:
            _reclaim_original(locked)
        locked.status = (
            SCHEDULED if locked.student_attendance == NOT_SET else COMPLETED
        )
    else:
        raise _not_allowed(locked)
```

and, before saving, `locked.disposal_reason = ""` (plan D3) with `"disposal_reason"` added to `update_fields`. Extend the docstring: "Slice B2a: also from at_disposal, back to scheduled; any restore clears `disposal_reason` (plan D3)."

Add:

```python
@transaction.atomic
def place_at_disposal(session: Session, *, reason: str = "") -> Session:
    """Slice B2a A-11: a scheduled session whose student attendance is not
    set goes to the administration's disposal. It never consumes, today's
    payroll rule does not pay it, and the system never deletes it (it is not
    untouched)."""
    locked = lock(session)
    refuse_if_paid(locked)
    refuse_if_compensated(locked)
    if locked.status != SCHEDULED or locked.student_attendance != NOT_SET:
        raise _not_allowed(locked)
    locked.status = AT_DISPOSAL
    locked.disposal_reason = (reason or "").strip()
    locked.save(update_fields=["status", "disposal_reason", "updated_at"])
    return locked
```

- [ ] **Step 4: `set_pays_teacher`**

Append to `manual.py`:

```python
@transaction.atomic
def set_pays_teacher(session: Session, *, pays_teacher: bool) -> Session:
    """§4.7: the office switches whether the session pays its teacher, until
    an issued payslip pays it."""
    locked = attendance.lock(session)
    refuse_if_paid(locked)
    locked.pays_teacher = pays_teacher
    locked.save(update_fields=["pays_teacher", "updated_at"])
    return locked
```

- [ ] **Step 5: `delete_subscription` and the Today board**

In `subscriptions.delete_subscription`, change the refusal filter to:

```python
    if sessions.filter(
        rules.MARKED
        | Q(status__in=(Session.Status.CANCELLED, Session.Status.AT_DISPOSAL))
    ).exists():
```

(Every compensation's original is cancelled, at_disposal or completed, so a subscription with a make-up is refused here too and the `compensates` PROTECT is never reached.)

In `services/board.py` add `Session.Status.AT_DISPOSAL: "at_disposal",` to `STATES`, and update `TodayRow.state`'s comment to `# generated · missing · completed · cancelled · at_disposal`.

Export `place_at_disposal` and `set_pays_teacher` from `services/__init__.py`.

- [ ] **Step 6: Run the tests**

Run: `$DC exec -T django pytest -q etqan/scheduling etqan/billing etqan/payroll etqan/notifications`
Expected: PASS.

- [ ] **Step 7: Format and commit**

```bash
$DC exec -T django sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/scheduling/services etqan/scheduling/tests/test_session_classes_disposal.py
git -C backend commit -m "feat(scheduling): at the administration's disposal, and switching pays_teacher (B2a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The API — routes, payload, filter, CSV, route table

**Files:**
- Modify: `backend/etqan/scheduling/services/rules.py` (`SESSION_RELATED`, `sessions_queryset`, `filter_sessions`)
- Modify: `backend/etqan/scheduling/api/serializers.py`
- Modify: `backend/etqan/scheduling/api/payloads.py`
- Modify: `backend/etqan/scheduling/api/session_views.py`
- Modify: `backend/etqan/scheduling/api/urls.py`
- Modify: `backend/etqan/access/registry.py` (`session` resource)
- Modify: `backend/etqan/access/tests/test_routes.py`
- Create: `backend/etqan/scheduling/tests/test_api_session_classes.py`

**Interfaces:**
- Consumes: Tasks 3–5.
- Produces: the routes in Global Constraints; payload keys `kind`, `compensates_id`, `compensation_id`, office-only `pays_teacher`, `compensated`, `created_by`, `disposal_reason`, detail-only `compensable` (D1); `?kind=` filter; CSV column `Kind`; create answer `{session, conflicts: [{session, other}]}`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/scheduling/tests/test_api_session_classes.py`:

```python
"""Slice B2a §5–§6: the routes, who may call them, the switches, the payload
and the list's kind filter."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db.models import Max
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots
from etqan.scheduling.tests.conftest import until_pk_exceeds

pytestmark = pytest.mark.django_db
URL = "/api/v1/sessions/"
ON = {
    "manual_sessions": True,
    "extra_sessions": True,
    "compensation_sessions": True,
    "disposal_status": True,
}


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


@pytest.fixture
def admin():
    return as_user(make_admin())


@pytest.fixture
def switched_on(set_features):
    set_features(**ON)


@pytest.fixture
def sub(subscribe):
    return subscribe(slots=two_slots())


def monday(sub):
    return Session.objects.filter(subscription=sub).order_by("starts_at").first()


def regular_body(sub, **extra):
    return {
        "subscription": sub.pk,
        "occurs_on": "2026-06-05",
        "start_time": "10:00",
        **extra,
    }


def test_the_admin_adds_a_regular_session(admin, sub, switched_on):
    resp = admin.post(f"{URL}regular/", regular_body(sub), format="json")
    body = resp.json()
    assert resp.status_code == 201, body
    session = body["session"]
    assert (session["kind"], session["generated"], session["minutes"]) == (
        "regular",
        False,
        45,
    )
    assert session["created_by"]["full_name"] == "Amina"
    assert session["pays_teacher"] is True
    assert body["conflicts"] == []


def test_each_create_route_answers_404_while_its_switch_is_off(admin, sub, world):
    for path, payload in (
        ("regular/", regular_body(sub)),
        (
            "extra/",
            {
                "student": world.student.id,
                "course": world.course.id,
                "teacher": world.teacher.id,
                "occurs_on": "2026-06-05",
                "start_time": "10:00",
                "minutes": 30,
            },
        ),
        (
            "compensation/",
            {"compensates": 1, "occurs_on": "2026-06-05", "start_time": "10:00"},
        ),
    ):
        assert admin.post(f"{URL}{path}", payload, format="json").status_code == 404


def test_staff_need_session_create_and_the_others_are_refused(
    staff_for, sub, world, switched_on, set_features
):
    assert staff_for().post(f"{URL}regular/", regular_body(sub), format="json").status_code == 403
    holder = staff_for("session.create")
    assert holder.post(f"{URL}regular/", regular_body(sub), format="json").status_code == 201
    for user in (world.teacher, world.student):
        assert as_user(user).post(f"{URL}regular/", regular_body(sub), format="json").status_code == 403
    assert APIClient().post(f"{URL}regular/", regular_body(sub), format="json").status_code in (401, 403)
    # The permission is checked before the switch (Plan 13 §5.2).
    set_features(manual_sessions=False)
    assert staff_for().post(f"{URL}regular/", regular_body(sub), format="json").status_code == 403


def test_the_admin_adds_a_past_extra_session_and_marks_it(admin, world, switched_on, clock):
    resp = admin.post(
        f"{URL}extra/",
        {
            "student": world.student.id,
            "course": world.course.id,
            "teacher": world.teacher.id,
            "occurs_on": "2026-05-30",
            "start_time": "10:00",
            "minutes": 30,
            "pays_teacher": False,
        },
        format="json",
    )
    session = resp.json()["session"]
    assert resp.status_code == 201, session
    assert (session["kind"], session["pays_teacher"], session["has_started"]) == (
        "extra",
        False,
        True,
    )
    mark = admin.post(
        f"{URL}{session['id']}/attendance/",
        {"student_attendance": "present"},
        format="json",
    )
    assert mark.json()["status"] == "completed"


def test_a_make_up_links_both_ways_and_the_detail_says_whats_compensable(
    admin, sub, switched_on
):
    original = monday(sub)
    admin.post(f"{URL}{original.pk}/cancel/", {"reason": "Eid"}, format="json")
    assert admin.get(f"{URL}{original.pk}/").json()["compensable"] is True
    resp = admin.post(
        f"{URL}compensation/",
        {"compensates": original.pk, "occurs_on": "2026-06-09", "start_time": "10:00"},
        format="json",
    )
    assert resp.status_code == 201, resp.json()
    make_up = resp.json()["session"]
    assert (make_up["kind"], make_up["compensates_id"]) == ("compensation", original.pk)
    detail = admin.get(f"{URL}{original.pk}/").json()
    assert (detail["compensation_id"], detail["compensated"], detail["compensable"]) == (
        make_up["id"],
        True,
        False,
    )
    again = admin.post(
        f"{URL}compensation/",
        {"compensates": original.pk, "occurs_on": "2026-06-10", "start_time": "10:00"},
        format="json",
    )
    assert (again.status_code, again.json()["code"]) == (
        409,
        "scheduling.already_compensated",
    )


def test_the_teacher_sees_the_kind_but_not_the_office_fields(
    admin, sub, world, switched_on
):
    added = admin.post(f"{URL}regular/", regular_body(sub), format="json").json()
    row = as_user(world.teacher).get(f"{URL}{added['session']['id']}/").json()
    assert (row["kind"], row["compensates_id"], row["compensation_id"]) == (
        "regular",
        None,
        None,
    )
    for field in ("pays_teacher", "compensated", "created_by", "disposal_reason", "compensable"):
        assert field not in row


def test_delete_needs_session_delete_and_a_hand_added_unmarked_session(
    admin, sub, staff_for, switched_on
):
    added = admin.post(f"{URL}regular/", regular_body(sub), format="json").json()
    pk = added["session"]["id"]
    assert staff_for("session.update").delete(f"{URL}{pk}/").status_code == 403
    generated = admin.delete(f"{URL}{monday(sub).pk}/")
    assert (generated.status_code, generated.json()["code"]) == (
        409,
        "scheduling.session_generated",
    )
    assert staff_for("session.delete").delete(f"{URL}{pk}/").status_code == 204
    assert not Session.objects.filter(pk=pk).exists()


def test_disposal_and_restore(admin, sub, set_features, switched_on):
    pk = monday(sub).pk
    placed = admin.post(f"{URL}{pk}/disposal/", {"reason": "Travelling"}, format="json")
    assert placed.status_code == 200
    assert (placed.json()["status"], placed.json()["disposal_reason"]) == (
        "at_disposal",
        "Travelling",
    )
    assert admin.post(f"{URL}{pk}/restore/").json()["status"] == "scheduled"
    set_features(disposal_status=False)
    assert admin.post(f"{URL}{pk}/disposal/", {}, format="json").status_code == 404


def test_restore_and_cancel_still_work_while_the_switch_is_off(
    admin, sub, set_features, switched_on
):
    pk = monday(sub).pk
    admin.post(f"{URL}{pk}/disposal/", {}, format="json")
    set_features(disposal_status=False)
    assert admin.get(f"{URL}{pk}/").json()["status"] == "at_disposal"
    assert admin.post(f"{URL}{pk}/restore/").json()["status"] == "scheduled"


def test_pays_teacher_is_switched_with_extra_sessions_on(admin, sub, set_features):
    pk = monday(sub).pk
    url = f"{URL}{pk}/pays-teacher/"
    assert admin.post(url, {"pays_teacher": False}, format="json").status_code == 404
    set_features(extra_sessions=True)
    resp = admin.post(url, {"pays_teacher": False}, format="json")
    assert (resp.status_code, resp.json()["pays_teacher"]) == (200, False)
    assert admin.post(url, {}, format="json").status_code == 400


def test_the_list_filters_by_kind_and_at_disposal(admin, sub, world, switched_on):
    admin.post(
        f"{URL}extra/",
        {
            "student": world.student.id,
            "course": world.course.id,
            "teacher": world.teacher.id,
            "occurs_on": "2026-06-02",
            "start_time": "10:00",
            "minutes": 30,
        },
        format="json",
    )
    admin.post(f"{URL}{monday(sub).pk}/disposal/", {}, format="json")
    extras = admin.get(f"{URL}?kind=extra").json()["results"]
    assert [row["kind"] for row in extras] == ["extra"]
    disposed = admin.get(f"{URL}?status=at_disposal").json()["results"]
    assert [row["id"] for row in disposed] == [monday(sub).pk]
    assert admin.get(f"{URL}?kind=trial").status_code == 400


def test_the_csv_has_a_kind_column(admin, sub):
    header = admin.get(f"{URL}?format=csv").content.decode("utf-8-sig").splitlines()[0]
    assert "Kind" in header.split(",")


def test_another_academys_session_is_never_reached(admin, sub, tenants, switched_on):
    ceiling = Session.objects.aggregate(m=Max("pk"))["m"]
    with tenant_context(tenants.other):
        other = build_world()
        theirs_sub = until_pk_exceeds(
            Session, ceiling, lambda: subscription_for(other, slots=two_slots())
        )
        theirs = Session.objects.filter(subscription=theirs_sub).order_by("pk").first()
    assert theirs.pk > ceiling
    made_up = admin.post(
        f"{URL}compensation/",
        {"compensates": theirs.pk, "occurs_on": "2026-06-09", "start_time": "10:00"},
        format="json",
    )
    assert made_up.status_code == 400
    assert "compensates" in made_up.json()
    for method, path in (
        ("delete", f"{URL}{theirs.pk}/"),
        ("post", f"{URL}{theirs.pk}/disposal/"),
        ("post", f"{URL}{theirs.pk}/pays-teacher/"),
    ):
        assert getattr(admin, method)(path, {"pays_teacher": True}, format="json").status_code == 404
```

(Check the field-error body shape with `grep -n "def from_django\|field" backend/etqan/platform/exceptions.py backend/etqan/platform/drf.py`: Plan 3's 400 body is `{"<field>": ["…"]}`; adjust the `"compensates" in made_up.json()` assertion if the shape nests fields.)

- [ ] **Step 2: Run them to see them fail**

Run: `$DC exec -T django pytest -q etqan/scheduling/tests/test_api_session_classes.py`
Expected: FAIL — 404/405 on the new routes, missing payload keys.

- [ ] **Step 3: The queryset and the filter**

In `rules.py`:

```python
SESSION_RELATED = (
    "student__user",
    "teacher__user",
    "course",
    "supervisor",
    "created_by",
)
```

`sessions_queryset`:

```python
def sessions_queryset() -> QuerySet[Session]:
    """Sessions with everything a row shows, in one query: the people and
    course joined, ``has_report`` as an EXISTS and (slice B2a) the live
    compensation's id."""
    report = SessionReport.objects.filter(session=OuterRef("pk"))
    live_compensation = Session.objects.filter(compensates=OuterRef("pk")).exclude(
        status=Session.Status.CANCELLED
    )
    return Session.objects.select_related(*SESSION_RELATED).annotate(
        has_report=Exists(report),
        compensation_id=Subquery(live_compensation.values("pk")[:1]),
    )
```

`filter_sessions`: add a keyword `kind: str = "",` after `status`, and `"kind": kind,` in `exact`. Add to the docstring: "Slice B2a: ``kind``."

- [ ] **Step 4: Serializers**

In `api/serializers.py` add `kind = serializers.ChoiceField(choices=Session.Kind.values, required=False)` to `SessionFilterInput` (after `status`; `status` already takes `Session.Status.values`, which now include `at_disposal`), and:

```python
class _AddedSessionInput(serializers.Serializer):
    """Slice B2a §6: the fields every session added by hand takes."""

    occurs_on = serializers.DateField()
    start_time = serializers.TimeField()
    minutes = serializers.IntegerField(min_value=15, max_value=240, required=False)
    meeting_url = serializers.URLField(required=False, allow_blank=True, max_length=200)
    pays_teacher = serializers.BooleanField(required=False)
    notes = serializers.CharField(required=False, allow_blank=True)


class RegularSessionInput(_AddedSessionInput):
    subscription = _id()
    teacher = _id(required=False)


class ExtraSessionInput(_AddedSessionInput):
    student = _id()
    course = _id()
    teacher = _id()
    minutes = serializers.IntegerField(min_value=15, max_value=240)
    subscription = _id(required=False)


class CompensationInput(_AddedSessionInput):
    compensates = _id()
    teacher = _id(required=False)


class DisposalInput(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True)


class PaysTeacherInput(serializers.Serializer):
    pays_teacher = serializers.BooleanField()
```

- [ ] **Step 5: Payloads**

In `api/payloads.py`, add to `session_row`'s `row` dict (after `"payroll_locked"`):

```python
        # Slice B2a (spec §5): everyone in scope sees the kind and the links.
        "kind": session.kind,
        "compensates_id": session.compensates_id,
        "compensation_id": session.compensation_id,
        "pays_teacher": session.pays_teacher,
        "compensated": session.compensated,
        "created_by": _user(session.created_by),
        "disposal_reason": session.disposal_reason,
```

Change `STAFF_ONLY_SESSION_FIELDS` to:

```python
STAFF_ONLY_SESSION_FIELDS = (
    "notes",
    "cancel_reason",
    # Slice B2a (spec §5): the office alone.
    "pays_teacher",
    "compensated",
    "created_by",
    "disposal_reason",
)
```

Add:

```python
def added_session(added: services.Added, *, viewer) -> dict:
    """Slice B2a §4.1: the new session and the teacher's sessions it
    overlaps (P4-9: reported, never blocked)."""
    shown = shows_supervision(viewer)
    return {
        "session": session_row(added.session, viewer=viewer, supervision=shown),
        "conflicts": [
            {
                "session": session_row(session, viewer=viewer, supervision=shown),
                "other": session_row(other, viewer=viewer, supervision=shown),
            }
            for session, other in added.conflicts
        ],
    }
```

- [ ] **Step 6: Views**

In `api/session_views.py`:

Add `("kind", "Kind")` to `CSV_COLUMNS` right after `("course", "Course")`.

Import the new serializers and `from rest_framework import status`.

Replace `session_payload` with:

```python
def session_payload(request, pk) -> dict:
    """The session as it is now: every write answers with a fresh read. The
    office also learns whether it can be made up (plan D1: the one rule,
    asked once, never restated in the dashboard)."""
    session = services.sessions_queryset().get(pk=pk)
    row = payloads.session_row(
        session,
        viewer=request.user,
        supervision=payloads.shows_supervision(request.user),
    )
    if is_office(request.user):
        row["compensable"] = services.is_compensable(session)
    return row
```

In `SessionDetailView`: `permission_codes` gains `"DELETE": "session.delete"`, and add:

```python
    def delete(self, request, pk):
        # Slice B2a §4.2: no switch — a session added while one was on can
        # still be deleted after it goes off (A-13).
        services.delete_session(session_or_404(request, pk))
        return Response(status=status.HTTP_204_NO_CONTENT)
```

Add the create views:

```python
class RegularSessionView(APIView):
    """Slice B2a §6: one route per kind, so each declares its own switch."""

    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"POST": "session.create"}
    feature = "manual_sessions"

    def post(self, request):
        body = RegularSessionInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = dict(body.validated_data)
        added = services.create_regular_session(
            by=request.user,
            subscription_id=data.pop("subscription"),
            teacher_id=data.pop("teacher", None),
            **data,
        )
        return Response(
            payloads.added_session(added, viewer=request.user),
            status=status.HTTP_201_CREATED,
        )


class ExtraSessionView(APIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"POST": "session.create"}
    feature = "extra_sessions"

    def post(self, request):
        body = ExtraSessionInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = dict(body.validated_data)
        added = services.create_extra_session(
            by=request.user,
            student_id=data.pop("student"),
            course_id=data.pop("course"),
            teacher_id=data.pop("teacher"),
            subscription_id=data.pop("subscription", None),
            **data,
        )
        return Response(
            payloads.added_session(added, viewer=request.user),
            status=status.HTTP_201_CREATED,
        )


class CompensationView(APIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"POST": "session.create"}
    feature = "compensation_sessions"

    def post(self, request):
        body = CompensationInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = dict(body.validated_data)
        added = services.create_compensation(
            by=request.user,
            compensates_id=data.pop("compensates"),
            teacher_id=data.pop("teacher", None),
            **data,
        )
        return Response(
            payloads.added_session(added, viewer=request.user),
            status=status.HTTP_201_CREATED,
        )


class DisposalView(APIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"POST": "session.update"}
    feature = "disposal_status"

    def post(self, request, pk):
        session = session_or_404(request, pk)
        body = DisposalInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.place_at_disposal(session, **body.validated_data)
        return Response(session_payload(request, pk))


class PaysTeacherView(APIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"POST": "session.update"}
    feature = "extra_sessions"

    def post(self, request, pk):
        session = session_or_404(request, pk)
        body = PaysTeacherInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.set_pays_teacher(session, **body.validated_data)
        return Response(session_payload(request, pk))
```

(The `ValidationError` a service raises for an unknown `compensates` id becomes the field 400; another academy's id is "unknown" here because tenancy keeps it out of the query.)

- [ ] **Step 7: URLs**

In `api/urls.py`, after the `sessions/bulk/` entry:

```python
    # Slice B2a (spec §6).
    path(
        "sessions/regular/",
        session_views.RegularSessionView.as_view(),
        name="session-add-regular",
    ),
    path(
        "sessions/extra/",
        session_views.ExtraSessionView.as_view(),
        name="session-add-extra",
    ),
    path(
        "sessions/compensation/",
        session_views.CompensationView.as_view(),
        name="session-add-compensation",
    ),
    path(
        "sessions/<int:pk>/disposal/",
        session_views.DisposalView.as_view(),
        name="session-disposal",
    ),
    path(
        "sessions/<int:pk>/pays-teacher/",
        session_views.PaysTeacherView.as_view(),
        name="session-pays-teacher",
    ),
```

- [ ] **Step 8: The registry and the route table**

In `backend/etqan/access/registry.py`, the `session` resource becomes:

```python
    Resource(
        "session",
        "Sessions",
        "الحصص",
        # Slice B2a: `delete` is in use (hand-added sessions).
        (*EDIT, "delete", SUPERVISE[0]),
        verbs=(*ALL_VERBS, SUPERVISE[0]),
    ),
```

In `backend/etqan/access/tests/test_routes.py`:

- `ROUTES`, after `("PUT", f"/api/v1/sessions/{N}/report/", "session_report.update"),`:

```python
    # Slice B2a: session classes, in etqan.scheduling.
    ("POST", "/api/v1/sessions/regular/", "session.create"),
    ("POST", "/api/v1/sessions/extra/", "session.create"),
    ("POST", "/api/v1/sessions/compensation/", "session.create"),
    ("DELETE", f"/api/v1/sessions/{N}/", "session.delete"),
    ("POST", f"/api/v1/sessions/{N}/disposal/", "session.update"),
    ("POST", f"/api/v1/sessions/{N}/pays-teacher/", "session.update"),
```

- `FEATURES`, at its end:

```python
    # Slice B2a.
    ("POST", "/api/v1/sessions/regular/"): "manual_sessions",
    ("POST", "/api/v1/sessions/extra/"): "extra_sessions",
    ("POST", f"/api/v1/sessions/{N}/pays-teacher/"): "extra_sessions",
    ("POST", "/api/v1/sessions/compensation/"): "compensation_sessions",
    ("POST", f"/api/v1/sessions/{N}/disposal/"): "disposal_status",
```

- `FEATURE_WORDS`, at its end:

```python
    "/sessions/regular/": "manual_sessions",
    "/sessions/extra/": "extra_sessions",
    "/pays-teacher/": "extra_sessions",
    "/sessions/compensation/": "compensation_sessions",
    "/disposal/": "disposal_status",
```

(Read how `FEATURE_WORDS` is matched — `grep -n "FEATURE_WORDS" -A15 backend/etqan/access/tests/test_routes.py` — and keep the words specific enough not to catch other routes.)

- [ ] **Step 9: Run the tests**

Run: `$DC exec -T django pytest -q etqan/scheduling etqan/access etqan/platform`
Expected: PASS. If an existing test pins a session row's exact keys or the CSV header, add the new keys / the Kind column there.

- [ ] **Step 10: Format, verify, commit**

```bash
$DC exec -T django sh -c 'ruff check --fix . && ruff format . && lint-imports'
git -C backend add etqan/scheduling etqan/access
git -C backend commit -m "feat(scheduling): session-class routes, payload, kind filter and route table (B2a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Demo seeds

**Files:**
- Create: `backend/etqan/tenants/seeds/b2.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (one block under `# ── phase B2 ──`)
- Modify: `backend/etqan/scheduling/services/rules.py` (`has_hand_added_sessions`) and `services/__init__.py`
- Create: `backend/etqan/tenants/tests/test_seed_b2.py`

**Interfaces:**
- Consumes: `create_compensation`, `create_extra_session`, `is_compensable`, `sessions_queryset`, `today`.
- Produces: `scheduling.services.has_hand_added_sessions() -> bool`; `tenants.seeds.b2.seed_session_classes(subdomain: str) -> None`.

- [ ] **Step 1: Write the failing test**

`backend/etqan/tenants/tests/test_seed_b2.py`:

```python
"""Slice B2a §8: demo gets one make-up for a seeded excused session and one
extra session that doesn't pay the teacher, once; other gets nothing. The
four switches are on in demo (plan D6: `features.BUILT`)."""

import pytest
from django.core.management import call_command
from django.db import connection
from django.test import override_settings
from django_tenants.utils import tenant_context

from etqan.platform import features
from etqan.scheduling import services as scheduling_services
from etqan.tenants.models import Academy

B2A = ("manual_sessions", "extra_sessions", "compensation_sessions", "disposal_status")


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_demo_gets_a_make_up_and_an_unpaid_extra_session_once():
    call_command("seed_dev")
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        assert all(features.enabled(code) for code in B2A)
        hand = scheduling_services.sessions_queryset().filter(generated=False)
        assert sorted(hand.values_list("kind", flat=True)) == ["compensation", "extra"]
        extra = hand.get(kind="extra")
        assert extra.pays_teacher is False
        make_up = hand.get(kind="compensation")
        assert make_up.compensates.student_attendance == "excused"
        assert make_up.compensates.compensated is True
    with tenant_context(other):
        assert not features.enabled("manual_sessions")
        assert not scheduling_services.has_hand_added_sessions()
```

- [ ] **Step 2: Run it to see it fail**

Run: `$DC exec -T django pytest -q etqan/tenants/tests/test_seed_b2.py`
Expected: FAIL — no hand-added sessions (`[] == ["compensation", "extra"]`).

- [ ] **Step 3: The service and the seed step**

In `rules.py`, in the Seeds section:

```python
def has_hand_added_sessions() -> bool:
    """Slice B2a seeds: whether the office added any session by hand."""
    return Session.objects.filter(generated=False).exists()
```

Export it from `services/__init__.py`.

Create `backend/etqan/tenants/seeds/b2.py`:

```python
"""Phase B2's demo seed steps (spec 2026-10-02 §6.1)."""

from datetime import time
from datetime import timedelta

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services

# Slice B2a (spec §8): in demo, a make-up tomorrow for the first seeded
# excused session, and an extra session in two days that doesn't pay the
# teacher. Other academies get nothing.
SESSION_CLASSES = {
    "demo": {
        "make_up": {"in_days": 1, "start": time(10, 0)},
        "extra": {
            "student": "Zaid Huda",
            "course": "Quran Memorisation",
            "teacher": "Ustadha Maryam",
            "in_days": 2,
            "start": time(11, 0),
            "minutes": 30,
        },
    }
}


def _person(role: str, full_name: str):
    return identity_services.people_queryset(role).filter(full_name=full_name).first()


def _first_excused():
    excused = (
        scheduling_services.sessions_queryset()
        .filter(student_attendance="excused", kind="regular")
        .order_by("starts_at", "id")
    )
    return next((s for s in excused if scheduling_services.is_compensable(s)), None)


def seed_session_classes(subdomain: str) -> None:
    """Idempotent: an academy with any session added by hand is left alone.
    A refused step is printed and skipped, as the other seeds do."""
    spec = SESSION_CLASSES.get(subdomain)
    if spec is None or scheduling_services.has_hand_added_sessions():
        return
    today = scheduling_services.today()
    original = _first_excused()
    if original is not None:
        try:
            scheduling_services.create_compensation(
                by=None,
                compensates_id=original.pk,
                occurs_on=today + timedelta(days=spec["make_up"]["in_days"]),
                start_time=spec["make_up"]["start"],
            )
        except (ValidationError, ConflictError) as exc:
            print(f"skip: make-up for session {original.pk} — {exc}")  # noqa: T201
    extra = spec["extra"]
    student = _person("student", extra["student"])
    teacher = _person("teacher", extra["teacher"])
    course = catalogue_services.find_course(extra["course"])
    if None in (student, teacher, course):
        print("skip: extra session — seeded record not found")  # noqa: T201
        return
    try:
        scheduling_services.create_extra_session(
            by=None,
            student_id=student.id,
            course_id=course.id,
            teacher_id=teacher.id,
            occurs_on=today + timedelta(days=extra["in_days"]),
            start_time=extra["start"],
            minutes=extra["minutes"],
            pays_teacher=False,
        )
    except (ValidationError, ConflictError) as exc:
        print(f"skip: extra session — {exc}")  # noqa: T201
```

In `seed_dev.py`, replace `        # ── phase B2 ──` with (D10):

```python
        # ── phase B2 ──
        from etqan.tenants.seeds import b2  # noqa: PLC0415 -- under the B2 marker (plan D10)

        b2.seed_session_classes(subdomain)
```

- [ ] **Step 4: Run the seed tests**

Run: `$DC exec -T django pytest -q etqan/tenants/tests/test_seed_b2.py etqan/tenants/tests/test_seed_dev.py etqan/platform/tests/test_phase_sections.py`
Expected: PASS (the marker test still sees every marker once, in order).

- [ ] **Step 5: Seed this stream's dev database and look**

Run from `$W`: `just _stack-manage seed_dev` (this stream's django container; `just` loads `.env.stream`), then `just _stack-manage shell -c "from django_tenants.utils import schema_context; from etqan.scheduling.models import Session; ctx=schema_context('demo'); ctx.__enter__(); print(list(Session.objects.filter(generated=False).values_list('kind','pays_teacher')))"`.
Expected: `[('compensation', True), ('extra', False)]` (order may vary).

- [ ] **Step 6: Format, lint-imports, commit**

```bash
$DC exec -T django sh -c 'ruff check --fix . && ruff format . && lint-imports'
git -C backend add etqan/tenants/seeds/b2.py etqan/tenants/management/commands/seed_dev.py etqan/tenants/tests/test_seed_b2.py etqan/scheduling/services/rules.py etqan/scheduling/services/__init__.py
git -C backend commit -m "feat(seeds): a make-up and an unpaid extra session in demo (B2a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Dashboard foundations — types, API, strings, kind chips, `at_disposal` everywhere

**Files:**
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode`, D11)
- Modify: `dashboard/src/features/scheduling/schemas.ts`
- Modify: `dashboard/src/features/scheduling/api.ts`
- Modify: `dashboard/src/features/scheduling/bits.tsx` (`SESSION_TONE`)
- Create: `dashboard/src/features/scheduling/SessionKindChip.tsx` (+ `.test.tsx`)
- Modify: `dashboard/src/features/scheduling/TodayBoard.tsx` (`TONE`)
- Modify: `dashboard/src/features/scheduling/AttendanceControls.tsx` (+ test)
- Modify: `dashboard/src/features/scheduling/SessionsList.tsx`, `SessionPage.tsx`, `SessionsPanel.tsx`, `TeacherSessionTable.tsx`, `FamilySessions.tsx` (kind chip next to the status)
- Modify: `dashboard/src/test/scheduling-fixtures.ts` (`sessionRow`)
- Create: `dashboard/src/locales/en/sessionClasses.json`, `dashboard/src/locales/ar/sessionClasses.json`
- Modify: `dashboard/src/locales/{en,ar}/scheduling.json`, `dashboard/src/locales/{en,ar}/errors.json`

**Interfaces:**
- Produces:
  - `SESSION_KINDS = ["regular", "compensation", "extra"] as const`, `type SessionKind`; `SESSION_STATUSES` gains `"at_disposal"`; `TodayState` gains `"at_disposal"`.
  - `Session` gains `kind: SessionKind; compensates_id: number | null; compensation_id: number | null; pays_teacher?: boolean; compensated?: boolean; created_by?: PersonRef | null; disposal_reason?: string; compensable?: boolean`.
  - `AddedSession { session: Session; conflicts: { session: Session; other: Session }[] }`; `AddSessionBody` (discriminated by `kind`: `"regular" | "extra" | "compensation"`).
  - `schedulingApi.addSession(body: AddSessionBody): Promise<AddedSession>`, `deleteSession(id: number): Promise<void>`, `placeAtDisposal({ id, reason }): Promise<Session>`, `setPaysTeacher({ id, pays_teacher }): Promise<Session>`.
  - `<SessionKindChip kind={…} />` — renders nothing for `regular`.
  - i18n keys under `sessionClasses.*` (below).

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/scheduling/SessionKindChip.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import { SessionStatusChip } from "./bits";
import { SessionKindChip } from "./SessionKindChip";

describe("SessionKindChip", () => {
	it("names make-up and extra sessions, and nothing for a regular one", () => {
		const { container, rerender } = render(<SessionKindChip kind="regular" />);
		expect(container).toBeEmptyDOMElement();
		rerender(<SessionKindChip kind="compensation" />);
		expect(screen.getByText("Make-up")).toBeInTheDocument();
		rerender(<SessionKindChip kind="extra" />);
		expect(screen.getByText("Extra")).toBeInTheDocument();
	});

	it("labels the at-disposal status", () => {
		render(<SessionStatusChip status="at_disposal" />);
		expect(
			screen.getByText("At the administration's disposal"),
		).toBeInTheDocument();
	});
});
```

In `dashboard/src/features/scheduling/AttendanceControls.test.tsx`, add:

```tsx
	it("keeps the student's attendance closed at the administration's disposal", () => {
		renderWithRouter(
			<AttendanceControls
				session={sessionRow({ status: "at_disposal" })}
				canClear
			/>,
		);
		expect(
			screen.getByRole("combobox", { name: "Student attendance for Yusuf" }),
		).toBeDisabled();
		expect(
			screen.getByRole("combobox", { name: "Teacher attendance for Yusuf" }),
		).toBeEnabled();
	});
```

(Match the accessible names to `scheduling.attendance.studentFor` / `teacherFor` in `locales/en/scheduling.json`, and the imports to the file's existing ones.)

- [ ] **Step 2: Run them to see them fail**

Run: `$DC exec -T dashboard pnpm exec vitest run src/features/scheduling/SessionKindChip.test.tsx src/features/scheduling/AttendanceControls.test.tsx`
Expected: FAIL — module `./SessionKindChip` not found; type errors on `"at_disposal"`.

- [ ] **Step 3: Types and API**

`dashboard/src/features/identity/schemas.ts` — extend `FeatureCode` at its end:

```ts
	| "export"
	// Slice B2a (Plan 17).
	| "manual_sessions"
	| "extra_sessions"
	| "compensation_sessions"
	| "disposal_status";
```

`dashboard/src/features/scheduling/schemas.ts`:

```ts
export const SESSION_STATUSES = [
	"scheduled",
	"completed",
	"cancelled",
	// Slice B2a (A-11).
	"at_disposal",
] as const;

/** Slice B2a (A-1): what a session is. */
export const SESSION_KINDS = ["regular", "compensation", "extra"] as const;
export type SessionKind = (typeof SESSION_KINDS)[number];
```

In `interface Session`, after `generated: boolean;`:

```ts
	// Slice B2a: everyone in scope.
	kind: SessionKind;
	compensates_id: number | null;
	compensation_id: number | null;
	// Slice B2a: the office alone; `compensable` on the detail read only.
	pays_teacher?: boolean;
	compensated?: boolean;
	created_by?: PersonRef | null;
	disposal_reason?: string;
	compensable?: boolean;
```

`export type TodayState = "generated" | "missing" | "completed" | "cancelled" | "at_disposal";`

After `GenerationResult`:

```ts
/** Slice B2a §6: a session added by hand, and the teacher's sessions it
 * overlaps (P4-9: reported, never blocked). */
export interface AddedSession {
	session: Session;
	conflicts: { session: Session; other: Session }[];
}
interface AddedSessionFields {
	occurs_on: string;
	start_time: string;
	minutes?: number;
	meeting_url?: string;
	pays_teacher?: boolean;
	notes?: string;
}
export type AddSessionBody =
	| ({ kind: "regular"; subscription: number; teacher?: number } & AddedSessionFields)
	| ({
			kind: "extra";
			student: number;
			course: number;
			teacher: number;
			minutes: number;
			subscription?: number;
	  } & AddedSessionFields)
	| ({ kind: "compensation"; compensates: number; teacher?: number } & AddedSessionFields);
```

`dashboard/src/features/scheduling/api.ts` — import `AddedSession`, `AddSessionBody` and add to `schedulingApi`:

```ts
	// Slice B2a (spec §6): one route per kind.
	addSession: async ({ kind, ...body }: AddSessionBody) =>
		(await api.post<AddedSession>(`${SE}${kind}/`, body)).data,
	deleteSession: async (id: number) => {
		await api.delete(`${SE}${id}/`);
	},
	placeAtDisposal: async ({ id, reason }: { id: number; reason: string }) =>
		(await api.post<Session>(`${SE}${id}/disposal/`, { reason })).data,
	setPaysTeacher: async ({
		id,
		pays_teacher,
	}: {
		id: number;
		pays_teacher: boolean;
	}) => (await api.post<Session>(`${SE}${id}/pays-teacher/`, { pays_teacher })).data,
```

`dashboard/src/test/scheduling-fixtures.ts` — `sessionRow` defaults gain `kind: "regular", compensates_id: null, compensation_id: null,` (before `notes`).

- [ ] **Step 4: Strings**

`dashboard/src/locales/en/sessionClasses.json`:

```json
{
	"kind": {
		"regular": "Regular",
		"compensation": "Make-up",
		"extra": "Extra"
	},
	"tabs": {
		"label": "Session kind",
		"all": "All",
		"regular": "Core",
		"compensation": "Make-up",
		"extra": "Extra"
	},
	"add": {
		"button": "Add session",
		"title": "Add a session",
		"body": "A regular session counts against its subscription; an extra session is outside the package.",
		"kind": "Kind",
		"subscription": "Subscription",
		"subscriptionOption": "{{student}} — {{course}}",
		"student": "Student",
		"course": "Course",
		"teacher": "Teacher",
		"sameTeacher": "The usual teacher",
		"date": "Date",
		"time": "Start time (academy time)",
		"minutes": "Minutes",
		"minutesDefault": "Leave empty for the usual length",
		"meetingUrl": "Meeting link",
		"notes": "Notes",
		"paysTeacher": "Pays the teacher",
		"submit": "Add session",
		"added": "Session added.",
		"conflicts": "The teacher has other sessions at that time:",
		"done": "Done"
	},
	"makeUp": {
		"button": "Add make-up session",
		"title": "Add a make-up session",
		"body": "For {{name}}'s session on {{date}}. The make-up counts against the package; this session no longer does.",
		"submit": "Add make-up session",
		"added": "Make-up session added."
	},
	"links": {
		"original": "Makes up for",
		"compensation": "Made up by",
		"session": "The session on {{date}}"
	},
	"createdBy": "Added by",
	"system": "System",
	"frozen": "This session has a make-up session, so it can't change.",
	"paysTeacher": {
		"label": "Pays the teacher",
		"saved": "Saved."
	},
	"disposal": {
		"button": "Place at the administration's disposal",
		"title": "Place at the administration's disposal",
		"body": "The session doesn't count against the package and isn't paid by the usual payroll rule. Restore it to schedule it again.",
		"reason": "Reason (optional)",
		"submit": "Place at disposal",
		"because": "At the administration's disposal: {{reason}}"
	},
	"delete": {
		"button": "Delete session",
		"title": "Delete this session",
		"body": "It was added by hand and nothing is recorded on it yet.",
		"done": "Session deleted."
	},
	"errors": {
		"required": "Choose one.",
		"minutesRange": "Between 15 and 240 minutes."
	}
}
```

`dashboard/src/locales/ar/sessionClasses.json`:

```json
{
	"kind": {
		"regular": "عادية",
		"compensation": "تعويضية",
		"extra": "إضافية"
	},
	"tabs": {
		"label": "نوع الحصة",
		"all": "الكل",
		"regular": "أساسية",
		"compensation": "تعويضية",
		"extra": "إضافية"
	},
	"add": {
		"button": "إضافة حصة",
		"title": "إضافة حصة",
		"body": "الحصة العادية تُحتسب من اشتراكها، والحصة الإضافية خارج الباقة.",
		"kind": "النوع",
		"subscription": "الاشتراك",
		"subscriptionOption": "{{student}} — {{course}}",
		"student": "الطالب",
		"course": "الدورة",
		"teacher": "المعلم",
		"sameTeacher": "المعلم المعتاد",
		"date": "التاريخ",
		"time": "وقت البدء (بتوقيت الأكاديمية)",
		"minutes": "الدقائق",
		"minutesDefault": "اتركها فارغة للمدة المعتادة",
		"meetingUrl": "رابط الحصة",
		"notes": "ملاحظات",
		"paysTeacher": "تُحتسب للمعلم",
		"submit": "إضافة الحصة",
		"added": "تمت إضافة الحصة.",
		"conflicts": "لدى المعلم حصص أخرى في هذا الوقت:",
		"done": "تم"
	},
	"makeUp": {
		"button": "إضافة حصة تعويضية",
		"title": "إضافة حصة تعويضية",
		"body": "عن حصة {{name}} بتاريخ {{date}}. الحصة التعويضية تُحتسب من الباقة، وهذه الحصة لم تعد تُحتسب.",
		"submit": "إضافة الحصة التعويضية",
		"added": "تمت إضافة الحصة التعويضية."
	},
	"links": {
		"original": "تعويض عن",
		"compensation": "عُوِّضت بـ",
		"session": "حصة {{date}}"
	},
	"createdBy": "أضافها",
	"system": "النظام",
	"frozen": "لهذه الحصة حصة تعويضية، فلا يمكن تغييرها.",
	"paysTeacher": {
		"label": "تُحتسب للمعلم",
		"saved": "تم الحفظ."
	},
	"disposal": {
		"button": "وضعها تحت تصرف الإدارة",
		"title": "وضع الحصة تحت تصرف الإدارة",
		"body": "لا تُحتسب الحصة من الباقة ولا يدفعها نظام الرواتب المعتاد. استرجعها لجدولتها من جديد.",
		"reason": "السبب (اختياري)",
		"submit": "وضعها تحت التصرف",
		"because": "تحت تصرف الإدارة: {{reason}}"
	},
	"delete": {
		"button": "حذف الحصة",
		"title": "حذف هذه الحصة",
		"body": "أُضيفت يدويًا ولم يُسجَّل عليها شيء بعد.",
		"done": "تم حذف الحصة."
	},
	"errors": {
		"required": "اختر واحدًا.",
		"minutesRange": "بين 15 و240 دقيقة."
	}
}
```

`scheduling.json` (en / ar): add `"at_disposal": "At the administration's disposal"` / `"at_disposal": "تحت تصرف الإدارة"` to `sessions.status`, to `today.state`, and to every other session-status map in the file that lists `scheduled`/`completed`/`cancelled` (`grep -n '"scheduled"' src/locales/en/scheduling.json`).

`errors.json` (en / ar), under `"scheduling"`:

```json
		"not_compensable": "Only a session that did not use up the package can be made up.",
		"already_compensated": "This session already has a make-up session.",
		"has_compensation": "This session has a make-up session, so it can't change.",
		"session_generated": "A generated session can't be deleted. Cancel it instead.",
		"session_marked": "Attendance is marked on this session."
```

```json
		"not_compensable": "لا يمكن تعويض إلا حصة لم تُحتسب من الباقة.",
		"already_compensated": "لهذه الحصة حصة تعويضية بالفعل.",
		"has_compensation": "لهذه الحصة حصة تعويضية، فلا يمكن تغييرها.",
		"session_generated": "لا يمكن حذف حصة مُولَّدة. ألغِها بدلًا من ذلك.",
		"session_marked": "سُجِّل الحضور على هذه الحصة."
```

- [ ] **Step 5: Chips and controls**

`dashboard/src/features/scheduling/SessionKindChip.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { StatusChip } from "@/ui";
import type { SessionKind } from "./schemas";

/** Slice B2a (A-1): a make-up or an extra session says so; a regular one
 * shows nothing, as every session did before. */
export function SessionKindChip({ kind }: { kind: SessionKind }) {
	const { t } = useTranslation();
	if (kind === "regular") return null;
	return (
		<StatusChip tone="neutral">{t(`sessionClasses.kind.${kind}`)}</StatusChip>
	);
}
```

(Check `StatusChip`'s tones in `src/ui/status-chip.tsx`; use `neutral` or the closest non-alarming tone it offers.)

`bits.tsx` — `SESSION_TONE` gains `at_disposal: "warning",`.
`TodayBoard.tsx` — `TONE` gains `at_disposal: "neutral",`.
`AttendanceControls.tsx` — the student picker gets its own `disabled={closed || session.status === "at_disposal"}` (the teacher picker keeps `closed`); add to the doc comment: "Slice B2a: at the administration's disposal, the student's attendance stays closed (A-11)."

Put `<SessionKindChip kind={session.kind} />` right after each `<SessionStatusChip status={session.status} />` in `SessionsList.tsx`, `SessionPage.tsx`, `TeacherSessionTable.tsx` and `FamilySessions.tsx` (wrap the pair in `<span className="flex flex-wrap items-center gap-1">` where they share a cell), and after the status text in `SessionsPanel.tsx`.

- [ ] **Step 6: Run the tests and the type check**

Run: `$DC exec -T dashboard sh -c 'pnpm exec tsc --noEmit && pnpm exec vitest run src/features/scheduling src/lib'`
Expected: PASS (the locale test keeps `ar` and `en` key-for-key equal).

- [ ] **Step 7: Format and commit**

```bash
$DC exec -T dashboard pnpm exec biome check --write src e2e
git -C dashboard add src
git -C dashboard commit -m "feat(scheduling): session kinds and at_disposal in the dashboard (B2a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Sessions list — tabs, the status filter, Add session

**Files:**
- Create: `dashboard/src/features/scheduling/SessionFields.tsx`
- Create: `dashboard/src/features/scheduling/AddSessionDialog.tsx` (+ `.test.tsx`)
- Modify: `dashboard/src/features/scheduling/schemas.ts` (`addSessionFormSchema`, `makeUpFormSchema`)
- Modify: `dashboard/src/features/scheduling/SessionsList.tsx` (+ `SessionsList.test.tsx`)

**Interfaces:**
- Consumes: Task 8.
- Produces: `SessionFields` (shared date/time/minutes/link/notes fields for `react-hook-form` inside a `FormProvider`; props `{ minutesHint?: string }`); `AddSessionDialog` (props `{ kinds: ("regular" | "extra")[]; academyZone: string }`); `ConflictList` (props `{ conflicts: AddedSession["conflicts"]; academyZone: string }`, exported from `AddSessionDialog.tsx`); `addSessionFormSchema`, `AddSessionFormValues`, `makeUpFormSchema`, `MakeUpFormValues`, `toAddedFields(values)`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/scheduling/AddSessionDialog.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { page, sessionRow, subscriptionRow } from "@/test/scheduling-fixtures";
import { AddSessionDialog } from "./AddSessionDialog";
import { schedulingApi } from "./api";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, addSession: vi.fn(), list: vi.fn() },
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return { ...actual, catalogueApi: { ...actual.catalogueApi, list: vi.fn() } };
});

describe("AddSessionDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(schedulingApi.list).mockResolvedValue(page([subscriptionRow()]));
		vi.mocked(peopleApi.list).mockImplementation(async (kind) =>
			page(
				kind === "students"
					? [{ id: 11, user: { full_name: "Yusuf", timezone: "UTC" } }]
					: [{ id: 21, user: { full_name: "Bilal", timezone: "UTC" } }],
			) as never,
		);
		vi.mocked(catalogueApi.list).mockImplementation(async (kind) =>
			page(
				kind === "courses"
					? [{ id: 3, name_ar: "تجويد", name_en: "Tajweed", teacher_ids: [21], is_active: true }]
					: [],
			) as never,
		);
	});

	it("adds a regular session on a subscription", async () => {
		vi.mocked(schedulingApi.addSession).mockResolvedValue({
			session: sessionRow({ id: 90, generated: false }),
			conflicts: [],
		});
		const user = userEvent.setup();
		renderWithRouter(<AddSessionDialog kinds={["regular", "extra"]} academyZone="UTC" />);
		await user.click(screen.getByRole("button", { name: "Add session" }));
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(within(dialog).getByLabelText(/^Subscription/), "7");
		await user.type(within(dialog).getByLabelText(/^Date/), "2026-06-05");
		await user.type(within(dialog).getByLabelText(/^Start time/), "10:00");
		await user.click(within(dialog).getByRole("button", { name: "Add session" }));
		expect(schedulingApi.addSession).toHaveBeenCalledWith({
			kind: "regular",
			subscription: 7,
			occurs_on: "2026-06-05",
			start_time: "10:00",
			meeting_url: "",
			notes: "",
		});
		expect(await screen.findByText("Session added.")).toBeInTheDocument();
	});

	it("asks for the student, course, teacher and minutes of an extra session", async () => {
		const user = userEvent.setup();
		renderWithRouter(<AddSessionDialog kinds={["regular", "extra"]} academyZone="UTC" />);
		await user.click(screen.getByRole("button", { name: "Add session" }));
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(within(dialog).getByLabelText(/^Kind/), "extra");
		await user.click(within(dialog).getByRole("button", { name: "Add session" }));
		expect(within(dialog).getAllByText("Choose one.")).toHaveLength(3);
		expect(within(dialog).getByText("Between 15 and 240 minutes.")).toBeInTheDocument();
		expect(schedulingApi.addSession).not.toHaveBeenCalled();
	});

	it("shows the teacher's other sessions at that time", async () => {
		vi.mocked(schedulingApi.addSession).mockResolvedValue({
			session: sessionRow({ id: 90 }),
			conflicts: [
				{
					session: sessionRow({ id: 90 }),
					other: sessionRow({ id: 41, student: { id: 12, full_name: "Aisha", timezone: "UTC" } }),
				},
			],
		});
		const user = userEvent.setup();
		renderWithRouter(<AddSessionDialog kinds={["regular"]} academyZone="UTC" />);
		await user.click(screen.getByRole("button", { name: "Add session" }));
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(within(dialog).getByLabelText(/^Subscription/), "7");
		await user.type(within(dialog).getByLabelText(/^Date/), "2026-06-01");
		await user.type(within(dialog).getByLabelText(/^Start time/), "18:00");
		await user.click(within(dialog).getByRole("button", { name: "Add session" }));
		expect(await within(dialog).findByText("The teacher has other sessions at that time:")).toBeInTheDocument();
		expect(within(dialog).getByText(/overlaps Aisha/)).toBeInTheDocument();
	});
});
```

The mocks follow `SubscriptionForm.test.tsx`: `peopleApi.list` and `catalogueApi.list` answer one student, one teacher and one course (whose `teacher_ids` lists the teacher); `page()` and `subscriptionRow()` come from `src/test/scheduling-fixtures.ts`. Check `peopleApi.list` / `catalogueApi.list`'s first argument names (`kind`) against those modules.

In `SessionsList.test.tsx` add:

```tsx
	it("filters by kind on the tabs the academy's switches allow", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<CanProvider me={adminWith("extra_sessions")}>
				<SessionsList />
			</CanProvider>,
		);
		const tabs = await screen.findByRole("group", { name: "Session kind" });
		expect(within(tabs).getByRole("button", { name: "All" })).toHaveAttribute("aria-pressed", "true");
		expect(within(tabs).queryByRole("button", { name: "Make-up" })).toBeNull();
		await user.click(within(tabs).getByRole("button", { name: "Extra" }));
		expect(schedulingApi.sessions).toHaveBeenLastCalledWith(
			expect.objectContaining({ kind: "extra", page: 1 }),
		);
	});

	it("offers at-disposal in the status filter only while its switch is on", async () => {
		renderWithRouter(
			<CanProvider me={adminWith()}>
				<SessionsList />
			</CanProvider>,
		);
		const status = await screen.findByRole("combobox", { name: "Status" });
		expect(within(status).queryByRole("option", { name: "At the administration's disposal" })).toBeNull();
	});

	it("shows Add session to an admin with a switch on", async () => {
		renderWithRouter(
			<CanProvider me={adminWith("manual_sessions")}>
				<SessionsList />
			</CanProvider>,
		);
		expect(await screen.findByRole("button", { name: "Add session" })).toBeInTheDocument();
	});
```

(Use the list's existing mock name for `schedulingApi.sessionList`/`sessions` — `grep -n "vi.fn()" src/features/scheduling/SessionsList.test.tsx` — and its existing imports.)

- [ ] **Step 2: Run them to see them fail**

Run: `$DC exec -T dashboard pnpm exec vitest run src/features/scheduling/AddSessionDialog.test.tsx src/features/scheduling/SessionsList.test.tsx`
Expected: FAIL — module not found; no "Session kind" group.

- [ ] **Step 3: Form schemas**

In `schemas.ts`, after `cancelSessionSchema`:

```ts
// Slice B2a: sessions added by hand. Minutes are typed as text so "" means
// "the usual length" (regular, make-up); an extra session needs them.
const clock = z.string().regex(/^\d{2}:\d{2}$/, "scheduling.errors.timeRequired");
const optionalMinutes = z
	.string()
	.refine(
		(v) => v === "" || (/^\d+$/.test(v) && Number(v) >= 15 && Number(v) <= 240),
		"sessionClasses.errors.minutesRange",
	);
const addedFields = {
	occurs_on: isoDate,
	start_time: clock,
	minutes: optionalMinutes,
	meeting_url: z.union([z.url("scheduling.errors.urlInvalid"), z.literal("")]),
	notes: z.string(),
};

export const addSessionFormSchema = z
	.object({
		kind: z.enum(["regular", "extra"]),
		subscription: z.string(),
		student: z.string(),
		course: z.string(),
		teacher: z.string(),
		pays_teacher: z.boolean(),
		...addedFields,
	})
	.superRefine((v, ctx) => {
		const need = (path: string) =>
			ctx.addIssue({ code: "custom", path: [path], message: "sessionClasses.errors.required" });
		if (v.kind === "regular" && !v.subscription) need("subscription");
		if (v.kind === "extra") {
			for (const key of ["student", "course", "teacher"] as const) if (!v[key]) need(key);
			if (!v.minutes)
				ctx.addIssue({ code: "custom", path: ["minutes"], message: "sessionClasses.errors.minutesRange" });
		}
	});
export type AddSessionFormValues = z.infer<typeof addSessionFormSchema>;

export const makeUpFormSchema = z.object({ teacher: z.string(), ...addedFields });
export type MakeUpFormValues = z.infer<typeof makeUpFormSchema>;

/** The shared fields as the API takes them: empty minutes are left out. */
export function toAddedFields(v: {
	occurs_on: string;
	start_time: string;
	minutes: string;
	meeting_url: string;
	notes: string;
}) {
	return {
		occurs_on: v.occurs_on,
		start_time: v.start_time,
		...(v.minutes ? { minutes: Number(v.minutes) } : {}),
		meeting_url: v.meeting_url,
		notes: v.notes,
	};
}
```

- [ ] **Step 4: `SessionFields` and `AddSessionDialog`**

`dashboard/src/features/scheduling/SessionFields.tsx` — the date, start time, minutes, meeting link and notes inputs, read through `useFormContext()`, each in a `Field` (`id`s `session-date`, `session-time`, `session-minutes`, `session-link`, `session-notes`; labels `sessionClasses.add.date|time|minutes|meetingUrl|notes`; `date` and `time` `required`; minutes with `hint={minutesHint}`; `dir="ltr"` on date, time and link inputs, as `SlotFields.tsx` and `SessionsList.tsx` do). Errors through `useFieldError()`.

`dashboard/src/features/scheduling/AddSessionDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { FormProvider, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { usePeople } from "@/features/people";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { formatDay, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Checkbox,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Select,
	SubmitButton,
	toast,
} from "@/ui";
import { schedulingApi } from "./api";
import { useLocalName } from "./bits";
import { useChoices } from "./choices";
import { useSchedulingMutation, useSubscriptions } from "./queries";
import { SessionFields } from "./SessionFields";
import {
	type AddedSession,
	type AddSessionFormValues,
	addSessionFormSchema,
	toAddedFields,
} from "./schemas";

const EMPTY: AddSessionFormValues = {
	kind: "regular",
	subscription: "",
	student: "",
	course: "",
	teacher: "",
	pays_teacher: true,
	occurs_on: "",
	start_time: "",
	minutes: "",
	meeting_url: "",
	notes: "",
};

/** The teacher's other sessions the new one overlaps (P4-9), in the words
 * GenerateDialog uses. */
export function ConflictList({
	conflicts,
	academyZone,
}: {
	conflicts: AddedSession["conflicts"];
	academyZone: string;
}) {
	const { t, i18n } = useTranslation();
	const time = (iso: string) => wallTime(new Date(iso), academyZone, i18n.language);
	return (
		<section className="flex flex-col gap-1 text-sm">
			<p>{t("sessionClasses.add.conflicts")}</p>
			<ul className="list-disc ps-5">
				{conflicts.map(({ session, other }) => (
					<li key={`${session.id}-${other.id}`}>
						{t("scheduling.generate.conflict", {
							teacher: session.teacher.full_name,
							date: formatDay(session.occurs_on, i18n.language),
							student: session.student.full_name,
							time: time(session.starts_at),
							other: other.student.full_name,
							otherTime: time(other.starts_at),
						})}
					</li>
				))}
			</ul>
		</section>
	);
}

/** Slice B2a §7 / plan D2: add a regular session on a subscription or an
 * extra session; make-ups start from the original's page. */
export function AddSessionDialog({
	kinds,
	academyZone,
}: {
	kinds: ("regular" | "extra")[];
	academyZone: string;
}) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const localName = useLocalName();
	const [open, setOpen] = useState(false);
	const [conflicts, setConflicts] = useState<AddedSession["conflicts"] | null>(null);
	const add = useSchedulingMutation(schedulingApi.addSession);
	const methods = useForm<AddSessionFormValues>({
		resolver: zodResolver(addSessionFormSchema),
		defaultValues: { ...EMPTY, kind: kinds[0] },
	});
	const { register, handleSubmit, setError, reset, watch, formState } = methods;
	const kind = watch("kind");
	const courseId = watch("course");
	const subs = useSubscriptions({ status: "active", page_size: 100 }, { enabled: open && kind === "regular" });
	const students = usePeople("students", { is_active: "true", page_size: 100 }, { enabled: open && kind === "extra" });
	const { courses, teachersFor } = useChoices();

	function close(next: boolean) {
		setOpen(next);
		if (!next) {
			reset({ ...EMPTY, kind: kinds[0] });
			setConflicts(null);
		}
	}

	async function onSubmit(v: AddSessionFormValues) {
		const fields = toAddedFields(v);
		try {
			const added = await add.mutateAsync(
				v.kind === "regular"
					? {
							kind: "regular",
							subscription: Number(v.subscription),
							...(v.teacher ? { teacher: Number(v.teacher) } : {}),
							...fields,
						}
					: {
							kind: "extra",
							student: Number(v.student),
							course: Number(v.course),
							teacher: Number(v.teacher),
							minutes: Number(v.minutes),
							pays_teacher: v.pays_teacher,
							...fields,
						},
			);
			toast({ description: t("sessionClasses.add.added") });
			if (added.conflicts.length > 0) setConflicts(added.conflicts);
			else close(false);
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<Dialog open={open} onOpenChange={close}>
			<DialogTrigger asChild>
				<Button size="sm">{t("sessionClasses.add.button")}</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("sessionClasses.add.title")}</DialogTitle>
				<DialogDescription>{t("sessionClasses.add.body")}</DialogDescription>
				{conflicts ? (
					<div className="mt-4 flex flex-col gap-4">
						<ConflictList conflicts={conflicts} academyZone={academyZone} />
						<DialogFooter>
							<DialogClose asChild>
								<Button type="button">{t("sessionClasses.add.done")}</Button>
							</DialogClose>
						</DialogFooter>
					</div>
				) : (
					<FormProvider {...methods}>
						<form onSubmit={handleSubmit(onSubmit)} className="mt-4 flex flex-col gap-4" noValidate>
							{kinds.length > 1 ? (
								<Field id="session-kind" label={t("sessionClasses.add.kind")}>
									<Select {...register("kind")}>
										{kinds.map((k) => (
											<option key={k} value={k}>
												{t(`sessionClasses.kind.${k}`)}
											</option>
										))}
									</Select>
								</Field>
							) : null}
							{kind === "regular" ? (
								<Field
									id="session-subscription"
									label={t("sessionClasses.add.subscription")}
									error={fieldError(formState.errors.subscription?.message)}
									required
								>
									<Select {...register("subscription")}>
										<option value="" />
										{(subs.data?.results ?? []).map((s) => (
											<option key={s.id} value={s.id}>
												{t("sessionClasses.add.subscriptionOption", {
													student: s.student.full_name,
													course: localName(s.course),
												})}
											</option>
										))}
									</Select>
								</Field>
							) : (
								<>
									<Field id="session-student" label={t("sessionClasses.add.student")} error={fieldError(formState.errors.student?.message)} required>
										<Select {...register("student")}>
											<option value="" />
											{(students.data?.results ?? []).map((p) => (
												<option key={p.id} value={p.id}>
													{p.user.full_name}
												</option>
											))}
										</Select>
									</Field>
									<Field id="session-course" label={t("sessionClasses.add.course")} error={fieldError(formState.errors.course?.message)} required>
										<Select {...register("course")}>
											<option value="" />
											{courses.map((c) => (
												<option key={c.id} value={c.id}>
													{localName(c)}
												</option>
											))}
										</Select>
									</Field>
								</>
							)}
							<Field
								id="session-teacher"
								label={t("sessionClasses.add.teacher")}
								error={fieldError(formState.errors.teacher?.message)}
								required={kind === "extra"}
							>
								<Select {...register("teacher")}>
									<option value="">{kind === "regular" ? t("sessionClasses.add.sameTeacher") : ""}</option>
									{teachersFor(courseId).map((p) => (
										<option key={p.id} value={p.id}>
											{p.user.full_name}
										</option>
									))}
								</Select>
							</Field>
							<SessionFields minutesHint={kind === "regular" ? t("sessionClasses.add.minutesDefault") : undefined} />
							{kind === "extra" ? (
								<label className="flex items-center gap-2 text-sm">
									<Checkbox
										checked={watch("pays_teacher")}
										onCheckedChange={(on) => methods.setValue("pays_teacher", on === true)}
									/>
									{t("sessionClasses.add.paysTeacher")}
								</label>
							) : null}
							{formState.errors.root?.server ? (
								<Alert variant="destructive">
									<AlertDescription>{fieldError(formState.errors.root.server.message)}</AlertDescription>
								</Alert>
							) : null}
							<DialogFooter>
								<SubmitButton pending={formState.isSubmitting}>{t("sessionClasses.add.submit")}</SubmitButton>
							</DialogFooter>
						</form>
					</FormProvider>
				)}
			</DialogContent>
		</Dialog>
	);
}
```

Adapt the component names and props to the `@/ui` exports actually used by `GenerateDialog.tsx` and `SubscriptionForm.tsx` (`SubmitButton`'s prop name, `Field`'s `id`/`hint`); for a regular session the teacher picker lists the teachers of the chosen subscription's course (`teachersFor(String(selectedSub?.course.id ?? ""))`) — compute `selectedSub` from `subs.data` and `watch("subscription")`.

- [ ] **Step 5: The list**

In `SessionsList.tsx`:
- `const hasFeature = useHasFeature();`
- above the filters, a tab group:

```tsx
const KIND_TABS = [
	["all", undefined, undefined],
	["regular", "regular", undefined],
	["compensation", "compensation", "compensation_sessions"],
	["extra", "extra", "extra_sessions"],
] as const;
```

```tsx
<div role="group" aria-label={t("sessionClasses.tabs.label")} className="flex flex-wrap gap-2">
	{KIND_TABS.filter(([, , feature]) => !feature || hasFeature(feature)).map(([key, kind]) => (
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
</div>
```

(Use the `Button` variant names the codebase uses for a selected toggle — `MySupervision.tsx` uses `"primary"` / `"outline"` with `aria-pressed`.)
- the status `choice(...)` options: `SESSION_STATUSES.filter((s) => s !== "at_disposal" || hasFeature("disposal_status"))`.
- before `<ExportButton …/>`:

```tsx
{can("session.create") && academy ? (
	(() => {
		const kinds = (
			[
				["regular", "manual_sessions"],
				["extra", "extra_sessions"],
			] as const
		)
			.filter(([, feature]) => hasFeature(feature))
			.map(([kind]) => kind);
		return kinds.length ? <AddSessionDialog kinds={[...kinds]} academyZone={academy.timezone} /> : null;
	})()
) : null}
```

(Lift that into a small `const addKinds = …` above the `return` rather than an IIFE if Biome prefers.)

- [ ] **Step 6: Run the tests**

Run: `$DC exec -T dashboard sh -c 'pnpm exec tsc --noEmit && pnpm exec vitest run src/features/scheduling'`
Expected: PASS.

- [ ] **Step 7: Format and commit**

```bash
$DC exec -T dashboard pnpm exec biome check --write src e2e
git -C dashboard add src
git -C dashboard commit -m "feat(scheduling): session-kind tabs and Add session on the sessions list (B2a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Session page — links, pays-teacher, make-up, disposal, restore, delete

**Files:**
- Create: `dashboard/src/features/scheduling/SessionClasses.tsx` (+ `.test.tsx`)
- Create: `dashboard/src/features/scheduling/MakeUpDialog.tsx`
- Create: `dashboard/src/features/scheduling/DisposalDialog.tsx`
- Modify: `dashboard/src/features/scheduling/SessionPage.tsx` (+ `SessionPage.test.tsx`)

**Interfaces:**
- Consumes: Tasks 8–9 (`SessionFields`, `ConflictList`, `makeUpFormSchema`, `toAddedFields`, `schedulingApi.*`).
- Produces: `<SessionClasses session={…} academyZone={…} />` (office card); `<MakeUpDialog session={…} academyZone={…} />`; `<DisposalDialog onPlace={(reason) => Promise<unknown>} />`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/scheduling/SessionClasses.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { sessionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SessionClasses } from "./SessionClasses";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			addSession: vi.fn(),
			setPaysTeacher: vi.fn(),
			deleteSession: vi.fn(),
		},
	};
});

const ALL = ["manual_sessions", "extra_sessions", "compensation_sessions", "disposal_status"] as const;

describe("SessionClasses", () => {
	beforeEach(() => vi.clearAllMocks());

	it("links a make-up and its original both ways", () => {
		renderWithRouter(
			<SessionClasses
				session={sessionRow({ kind: "compensation", compensates_id: 40, generated: false, created_by: null })}
				academyZone="UTC"
			/>,
			{ extraPaths: ["/scheduling/sessions/$sessionId"] },
		);
		expect(screen.getByText("Makes up for")).toBeInTheDocument();
		expect(screen.getByRole("link", { name: /session/i })).toHaveAttribute("href", "/scheduling/sessions/40");
		expect(screen.getByText("System")).toBeInTheDocument();
	});

	it("offers a make-up only on a session the server calls compensable", async () => {
		const { rerender } = renderWithRouter(
			<CanProvider me={adminWith(...ALL)}>
				<SessionClasses session={sessionRow({ status: "cancelled", compensable: true })} academyZone="UTC" />
			</CanProvider>,
		);
		expect(screen.getByRole("button", { name: "Add make-up session" })).toBeInTheDocument();
		rerender(
			<CanProvider me={adminWith(...ALL)}>
				<SessionClasses session={sessionRow({ status: "cancelled", compensable: false })} academyZone="UTC" />
			</CanProvider>,
		);
		expect(screen.queryByRole("button", { name: "Add make-up session" })).toBeNull();
	});

	it("adds the make-up with the original's id", async () => {
		vi.mocked(schedulingApi.addSession).mockResolvedValue({ session: sessionRow({ id: 90 }), conflicts: [] });
		const user = userEvent.setup();
		renderWithRouter(
			<SessionClasses session={sessionRow({ status: "cancelled", compensable: true })} academyZone="UTC" />,
		);
		await user.click(screen.getByRole("button", { name: "Add make-up session" }));
		const dialog = screen.getByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^Date/), "2026-06-09");
		await user.type(within(dialog).getByLabelText(/^Start time/), "10:00");
		await user.click(within(dialog).getByRole("button", { name: "Add make-up session" }));
		expect(schedulingApi.addSession).toHaveBeenCalledWith(
			expect.objectContaining({ kind: "compensation", compensates: 41, occurs_on: "2026-06-09", start_time: "10:00" }),
		);
	});

	it("switches pays-teacher, and hides it without the switch or the code", async () => {
		vi.mocked(schedulingApi.setPaysTeacher).mockResolvedValue(sessionRow({ pays_teacher: false }));
		const user = userEvent.setup();
		const { rerender } = renderWithRouter(
			<SessionClasses session={sessionRow({ pays_teacher: true })} academyZone="UTC" />,
		);
		await user.click(screen.getByRole("checkbox", { name: "Pays the teacher" }));
		expect(schedulingApi.setPaysTeacher).toHaveBeenCalledWith({ id: 41, pays_teacher: false });
		rerender(
			<CanProvider me={staffMe("session.view")}>
				<SessionClasses session={sessionRow({ pays_teacher: true })} academyZone="UTC" />
			</CanProvider>,
		);
		expect(screen.getByRole("checkbox", { name: "Pays the teacher" })).toBeDisabled();
	});

	it("deletes a session added by hand that nothing is recorded on", async () => {
		vi.mocked(schedulingApi.deleteSession).mockResolvedValue(undefined);
		const user = userEvent.setup();
		renderWithRouter(
			<SessionClasses session={sessionRow({ generated: false })} academyZone="UTC" />,
			{ extraPaths: ["/scheduling/sessions"] },
		);
		await user.click(screen.getByRole("button", { name: "Delete session" }));
		await user.click(within(screen.getByRole("alertdialog")).getByRole("button", { name: "Delete this session" }));
		expect(schedulingApi.deleteSession).toHaveBeenCalledWith(41);
		expect(await screen.findByText("at /scheduling/sessions")).toBeInTheDocument();
	});

	it("never offers delete on a generated or marked session", () => {
		renderWithRouter(<SessionClasses session={sessionRow({ generated: true })} academyZone="UTC" />);
		expect(screen.queryByRole("button", { name: "Delete session" })).toBeNull();
	});
});
```

In `SessionPage.test.tsx` add (mocking `placeAtDisposal` in the file's `vi.mock` block):

```tsx
	it("places a session at the administration's disposal and restores it", async () => {
		vi.mocked(schedulingApi.placeAtDisposal).mockResolvedValue(
			sessionRow({ status: "at_disposal", disposal_reason: "Travelling" }),
		);
		const user = userEvent.setup();
		renderWithRouter(<SessionPage sessionId="41" />);
		await user.click(await screen.findByRole("button", { name: "Place at the administration's disposal" }));
		const dialog = screen.getByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^Reason/), "Travelling");
		await user.click(within(dialog).getByRole("button", { name: "Place at disposal" }));
		expect(schedulingApi.placeAtDisposal).toHaveBeenCalledWith({ id: 41, reason: "Travelling" });
	});

	it("shows Restore and Cancel on a session at the administration's disposal", async () => {
		vi.mocked(schedulingApi.session).mockResolvedValue(
			sessionRow({ status: "at_disposal", disposal_reason: "Travelling" }),
		);
		renderWithRouter(<SessionPage sessionId="41" />);
		expect(await screen.findByText("At the administration's disposal: Travelling")).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Restore session" })).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Cancel session" })).toBeInTheDocument();
	});

	it("freezes a session that has a make-up", async () => {
		vi.mocked(schedulingApi.session).mockResolvedValue(
			sessionRow({ status: "cancelled", compensated: true, compensation_id: 90 }),
		);
		renderWithRouter(<SessionPage sessionId="41" />);
		expect(await screen.findByText("This session has a make-up session, so it can't change.")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Restore session" })).toBeNull();
	});
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DC exec -T dashboard pnpm exec vitest run src/features/scheduling/SessionClasses.test.tsx src/features/scheduling/SessionPage.test.tsx`
Expected: FAIL.

- [ ] **Step 3: `DisposalDialog` and `MakeUpDialog`**

`DisposalDialog.tsx` — `CancelSessionDialog`'s shape with an optional reason: trigger `Button size="sm" variant="outline"` reading `sessionClasses.disposal.button`; title `sessionClasses.disposal.title`, body `sessionClasses.disposal.body`; a `Textarea` in a `Field id="disposal-reason" label={t("sessionClasses.disposal.reason")}`; submit `sessionClasses.disposal.submit`; `onPlace(reason)` is awaited, then the dialog closes; a server error goes through `applyServerErrors` and shows `root.server` in an `Alert`.

`MakeUpDialog.tsx`:

```tsx
/** Slice B2a §7: a make-up for this session; its student, course and
 * subscription are the original's, the date and time are chosen (A-5). */
export function MakeUpDialog({ session, academyZone }: { session: Session; academyZone: string }) {
	const { t, i18n } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const [conflicts, setConflicts] = useState<AddedSession["conflicts"] | null>(null);
	const add = useSchedulingMutation(schedulingApi.addSession);
	const { teachersFor } = useChoices();
	const methods = useForm<MakeUpFormValues>({
		resolver: zodResolver(makeUpFormSchema),
		defaultValues: { teacher: "", occurs_on: "", start_time: "", minutes: "", meeting_url: "", notes: "" },
	});
	async function onSubmit(v: MakeUpFormValues) {
		try {
			const added = await add.mutateAsync({
				kind: "compensation",
				compensates: session.id,
				...(v.teacher ? { teacher: Number(v.teacher) } : {}),
				...toAddedFields(v),
			});
			toast({ description: t("sessionClasses.makeUp.added") });
			if (added.conflicts.length) setConflicts(added.conflicts);
			else setOpen(false);
		} catch (error) {
			applyServerErrors(error, methods.setError);
		}
	}
	// Dialog: trigger "sessionClasses.makeUp.button"; title "…makeUp.title";
	// body t("sessionClasses.makeUp.body", { name: session.student.full_name, date: formatDay(session.occurs_on, i18n.language) });
	// a teacher Select ("" = sessionClasses.add.sameTeacher, then teachersFor(String(session.course.id)));
	// <SessionFields minutesHint={t("sessionClasses.add.minutesDefault")} />; root error Alert;
	// submit "sessionClasses.makeUp.submit"; after conflicts, <ConflictList …/> and a Done button —
	// the same structure as AddSessionDialog (Task 9), reusing ConflictList and SessionFields.
}
```

Write it out in full following `AddSessionDialog` (same imports, `FormProvider`, `Field`, `Select`, `SubmitButton`, `Alert`).

- [ ] **Step 4: `SessionClasses`**

```tsx
import { Link, useNavigate } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { Fact } from "@/components/Fact";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { errorText } from "@/lib/form-errors";
import { Card, CardContent, CardHeader, CardTitle, Checkbox, toast } from "@/ui";
import { schedulingApi } from "./api";
import { MakeUpDialog } from "./MakeUpDialog";
import { useSchedulingMutation } from "./queries";
import type { Session } from "./schemas";

/** Slice B2a §7 (office): the session's class — its make-up links, who added
 * it, whether it pays the teacher — with Add make-up and Delete. Fields the
 * server left out (a non-office viewer) hide their rows. */
export function SessionClasses({ session, academyZone }: { session: Session; academyZone: string }) {
	const { t } = useTranslation();
	const can = useCan();
	const hasFeature = useHasFeature();
	const navigate = useNavigate();
	const pays = useSchedulingMutation(schedulingApi.setPaysTeacher);
	const remove = useSchedulingMutation(schedulingApi.deleteSession);
	const paid = session.payroll_locked === true;
	const unmarked = session.student_attendance === "not_set" && session.teacher_attendance === "not_set";
	const deletable =
		!session.generated &&
		unmarked &&
		(session.status === "scheduled" || session.status === "at_disposal") &&
		!session.compensated &&
		!paid &&
		can("session.delete");
	const link = (id: number) => (
		<Link to="/scheduling/sessions/$sessionId" params={{ sessionId: String(id) }} className="font-medium text-primary-text underline-offset-4 hover:underline">
			{t("sessionClasses.links.session", { date: `#${id}` })}
		</Link>
	);
	const fail = (e: unknown) => toast({ description: errorText(e, t), variant: "destructive" });
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t(`sessionClasses.kind.${session.kind}`)}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				<dl className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
					{session.compensates_id ? <Fact label={t("sessionClasses.links.original")}>{link(session.compensates_id)}</Fact> : null}
					{session.compensation_id ? <Fact label={t("sessionClasses.links.compensation")}>{link(session.compensation_id)}</Fact> : null}
					{!session.generated && session.created_by !== undefined ? (
						<Fact label={t("sessionClasses.createdBy")}>{session.created_by?.full_name ?? t("sessionClasses.system")}</Fact>
					) : null}
				</dl>
				{session.pays_teacher !== undefined && hasFeature("extra_sessions") ? (
					<label className="flex items-center gap-2 text-sm">
						<Checkbox
							checked={session.pays_teacher}
							disabled={paid || pays.isPending || !can("session.update")}
							onCheckedChange={(on) =>
								pays.mutate({ id: session.id, pays_teacher: on === true }, { onError: fail })
							}
						/>
						{t("sessionClasses.paysTeacher.label")}
					</label>
				) : null}
				<div className="flex flex-wrap gap-2">
					{session.compensable && can("session.create") && hasFeature("compensation_sessions") ? (
						<MakeUpDialog session={session} academyZone={academyZone} />
					) : null}
					{deletable ? (
						<Confirm
							action={t("sessionClasses.delete.button")}
							title={t("sessionClasses.delete.title")}
							body={t("sessionClasses.delete.body")}
							onConfirm={() =>
								remove.mutate(session.id, {
									onSuccess: () => {
										toast({ description: t("sessionClasses.delete.done") });
										navigate({ to: "/scheduling/sessions" });
									},
									onError: fail,
								})
							}
						/>
					) : null}
				</div>
			</CardContent>
		</Card>
	);
}
```

(The `links.session` label shows the session's number; if you prefer its date, fetch nothing — the id is all the payload has. Keep the accessible name containing "session" for the test.)

- [ ] **Step 5: `SessionPage`**

- Render `<SessionClasses session={session} academyZone={academy.timezone} />` after the details card when `can("session.view")` (every office viewer; a teacher never reaches this page).
- Under the cancelled reason, add: `session.status === "at_disposal" && session.disposal_reason ? <p className="text-sm">{t("sessionClasses.disposal.because", { reason: session.disposal_reason })}</p> : null`.
- Replace the cancel/restore block with:

```tsx
<div className="flex flex-wrap gap-2" hidden={!can("session.update")}>
	{session.compensated ? (
		<p className="text-sm text-muted-foreground">{t("sessionClasses.frozen")}</p>
	) : session.payroll_locked ? null : (
		<>
			{session.status === "cancelled" || session.status === "at_disposal" ? (
				<Button size="sm" variant="outline" disabled={restore.isPending} onClick={() => restore.mutate(session.id, { onError: (e) => toast({ description: errorText(e, t), variant: "destructive" }) })}>
					{t("scheduling.session.restore")}
				</Button>
			) : null}
			{session.status === "scheduled" && hasFeature("disposal_status") ? (
				<DisposalDialog onPlace={(reason) => disposal.mutateAsync({ id: session.id, reason })} />
			) : null}
			{session.status !== "cancelled" ? (
				<CancelSessionDialog
					action={t("scheduling.session.cancel")}
					body={t("scheduling.session.cancelBody")}
					onCancel={(reason) => cancel.mutateAsync({ id: session.id, reason })}
				/>
			) : null}
		</>
	)}
</div>
```

with `const disposal = useSchedulingMutation(schedulingApi.placeAtDisposal);`. Restore and Cancel show whatever the switch says (A-13); only placing needs `disposal_status`.

- [ ] **Step 6: Run the tests and coverage**

Run: `$DC exec -T dashboard sh -c 'pnpm exec tsc --noEmit && pnpm exec vitest run src/features/scheduling && pnpm test:coverage'`
Expected: PASS and the coverage gates hold.

- [ ] **Step 7: Format, verify, commit**

```bash
$DC exec -T dashboard sh -c 'pnpm exec biome check --write src e2e && pnpm lint && pnpm build'
git -C dashboard add src
git -C dashboard commit -m "feat(scheduling): make-up, disposal, pays-teacher and delete on the session page (B2a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: End-to-end through Caddy

**Files:**
- Create: `dashboard/e2e/b2-session-classes.spec.ts`

**Interfaces:**
- Consumes: everything; the demo seeds (Task 7); `manage("set_features", …)` from `e2e/manage.ts`.

- [ ] **Step 1: Write the journey**

`dashboard/e2e/b2-session-classes.spec.ts`:

```ts
import { expect, type Page, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { manage } from "./manage";

const SWITCHES = ["manual_sessions", "extra_sessions", "compensation_sessions", "disposal_status"];

/** Tomorrow's date in UTC (demo's academy clock), as the date input takes it. */
function tomorrow(): string {
	return new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
}

/** The first upcoming scheduled session on the list, opened. */
async function openUpcomingScheduled(page: Page) {
	await page.goto(`${DEMO_URL}/app/scheduling/sessions`);
	await page.getByLabel("Period").selectOption("upcoming");
	await page.getByRole("combobox", { name: "Status" }).selectOption("scheduled");
	const row = page.getByRole("row").filter({ hasText: "Scheduled" }).first();
	await row.getByRole("link").first().click();
	await expect(page).toHaveURL(/\/app\/scheduling\/sessions\/\d+$/);
	return page.url();
}

// Slice B2a spec §9: with the switches on, the admin makes up a cancelled
// session (the original then links its make-up and offers no second one),
// adds an extra session, and places a session at the administration's
// disposal and restores it. Each run uses fresh upcoming sessions, so a
// second run on the same database passes too.
test("the admin adds a make-up and an extra session, and uses the disposal status", async ({ page }) => {
	for (const code of SWITCHES) manage("set_features", "demo", "--on", code);
	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// A make-up for a cancelled session
	const original = await openUpcomingScheduled(page);
	await page.getByRole("button", { name: "Cancel session" }).click();
	const cancel = page.getByRole("dialog");
	await cancel.getByLabel(/^Reason/).fill("E2E: teacher travelling");
	await cancel.getByRole("button", { name: "Cancel session" }).click();
	await expect(page.getByText("Cancelled: E2E: teacher travelling")).toBeVisible();
	await page.getByRole("button", { name: "Add make-up session" }).click();
	const makeUp = page.getByRole("dialog");
	await makeUp.getByLabel(/^Date/).fill(tomorrow());
	await makeUp.getByLabel(/^Start time/).fill("06:00");
	await makeUp.getByRole("button", { name: "Add make-up session" }).click();
	await expect(page.getByText("Make-up session added.")).toBeVisible();
	await page.getByRole("button", { name: "Done" }).click().catch(() => {});
	await page.goto(original);
	await expect(page.getByText("Made up by")).toBeVisible();
	await expect(page.getByRole("button", { name: "Add make-up session" })).toHaveCount(0);
	await expect(page.getByText("This session has a make-up session, so it can't change.")).toBeVisible();

	// An extra session from the list
	await page.goto(`${DEMO_URL}/app/scheduling/sessions`);
	await page.getByRole("button", { name: "Add session" }).click();
	const add = page.getByRole("dialog");
	await add.getByLabel(/^Kind/).selectOption("extra");
	await add.getByLabel(/^Student/).selectOption({ label: "Zaid Huda" });
	await add.getByLabel(/^Course/).selectOption({ label: "Quran Memorisation" });
	await add.getByLabel(/^Teacher/).selectOption({ label: "Ustadha Maryam" });
	await add.getByLabel(/^Date/).fill(tomorrow());
	await add.getByLabel(/^Start time/).fill("05:00");
	await add.getByLabel(/^Minutes/).fill("30");
	await add.getByRole("button", { name: "Add session" }).click();
	await expect(page.getByText("Session added.")).toBeVisible();
	await page.getByRole("button", { name: "Done" }).click().catch(() => {});
	await page.getByRole("group", { name: "Session kind" }).getByRole("button", { name: "Extra" }).click();
	await page.getByLabel("Period").selectOption("upcoming");
	await expect(page.getByRole("row").filter({ hasText: "Zaid Huda" }).first()).toContainText("Extra");

	// At the administration's disposal, then restored
	await openUpcomingScheduled(page);
	await page.getByRole("button", { name: "Place at the administration's disposal" }).click();
	const disposal = page.getByRole("dialog");
	await disposal.getByLabel(/^Reason/).fill("E2E: student travelling");
	await disposal.getByRole("button", { name: "Place at disposal" }).click();
	await expect(page.getByText("At the administration's disposal: E2E: student travelling")).toBeVisible();
	await page.getByRole("button", { name: "Restore session" }).click();
	await expect(page.getByText("Scheduled").first()).toBeVisible();
});
```

(The Done buttons only appear when the new session overlaps another of the teacher's; `.catch(() => {})` keeps the journey independent of that. If the dialog stays open with conflicts, Playwright's auto-wait on `click()` handles it within the default timeout — or replace with `if (await page.getByRole("button", { name: "Done" }).isVisible()) …`.)

- [ ] **Step 2: Run the whole e2e suite against this stream**

Run (from `$W`, stack up, demo seeded by `just _stack-manage seed_dev`): `just e2e`
Expected: every spec passes, `b2-session-classes.spec.ts` included. Then run `just e2e e2e/b2-session-classes.spec.ts` a second time on the same database: PASS again. If an older journey (`journey.spec.ts`, `payroll.spec.ts`, `sessions.spec.ts`) now finds the seeded make-up or extra session where it expected one row, narrow that journey's locator by date or student (as Plan 13's final review did) rather than changing the seeds.

- [ ] **Step 3: Format and commit**

```bash
$DC exec -T dashboard pnpm exec biome check --write src e2e
git -C dashboard add e2e/b2-session-classes.spec.ts
git -C dashboard commit -m "test(e2e): session classes journey (B2a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: The slice gates**

Run from `$W`: `just test`, `just lint`, `just e2e`. All green before the slice is queued (`python3 scripts/orchestration/ledger.py queue B2a`). STATE.md is the conductor's: not edited here.
