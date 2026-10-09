# Plan 55 — Salary projections (slice B4d) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B4b (Plan 54), and through it B4a (Plan 46).
**Slice:** B4d · **Phase spec:** `docs/superpowers/specs/2026-10-08-b4-payroll-depth-design.md` (§1–§4, §3 row B4d and its notes) · **Slice spec:** `docs/superpowers/specs/2026-10-08-b4d-salary-projections-design.md`

**Goal:** One read-only screen answers "what will each teacher be paid for this month if every scheduled session takes place?" Per teacher it shows the pay so far beside the projection, then per-currency totals and, while exchange rates are on, one estimated total in the academy currency. The switch `salary_projections` is off by default. There is no new model and no migration, and generate and issue pay exactly what B4b pays.

**Architecture:**
- **Rule** (P-3). `rules.PROJECTED` is one more `Q` term; `rules.pay_rule(pay, *, projected=False)` adds it when asked. `build.paying_sessions`, `build._session_lines`, `build.build` and `payslips._paying_teacher_ids` gain an additive keyword-only `projected: bool = False`, and `build` gains `counters: bool = True` (P-7). Generate, issue and `_unpaid_rows` never pass either.
- **Service** (§4). `services/projections.py` holds `project() -> Projection`, with `ProjectionRow` and `CurrencyTotal`. It reads `effective_settings()` once and the month from `payroll.clock.today()`, discovers teachers with the same `pay` (P-4), runs two builds per teacher with no lock and no transaction of its own, totals per currency, and converts the projected totals through `finance.services.convert_estimate` (D31).
- **API** (§5). `GET /api/v1/payroll/payslips/projection/`, registered before `payslips/<int:pk>/`. `HasCode` only (`payslip.view_any`) plus `FeatureOn`. `?format=csv` through `CSVExportMixin`.
- **Dashboard** (§6). A "Salary projections" page at `/payroll/projections`, a nav item under Payroll, and a header button on the payslips page, both while the switch is on. Table, per-currency totals, the B3h-style estimate line, one explanation line, CSV.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod, i18next; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-08-b4d-salary-projections-design.md`. It builds on:
- Plan 46 (B4a): `PaySettings`, `effective_settings`, `get_settings`, `update_settings`, `rules.pay_rule(pay)`, `rules.PAYS`, `rules.AT_DISPOSAL_PAYS`, `rules.PAYING_TEACHER_ATTENDANCE`, `build.paying_sessions(teacher, first, last, pay)`, `build._session_lines(teacher, first, last, language, pay)`, `build(teacher, year, month, settings=None)`, `regroup`, `MEMBER`, `Line.session_status` / `.group_role`, `payslips._paying_teacher_ids(first, last, pay)`, conftest `rules_on`, `student_rate`, `june_group`; the payroll settings page and nav conventions; the API-driven E2E (Task 14).
- Plan 54 (B4b): the build order (session lines → `regroup` → `_fixed_month` → gross → `_adjustment_lines` → `_missing_report_ids` → `_report_lines` → totals → `missing_rate` → `_counters`), `Built.reports_sent` / `.reports_missing` / `.teacher_absences`, `payslips._pending_teacher_ids(last, pay)`, `payslips._fixed_teacher_ids(first, pay)`, conftest `pay_in`, `fixed_salary`, `percent_bonus`, and the switches `incentives_deductions` and `fixed_teacher_salary`.
- B3h: `finance.services.convert_estimate`, `Estimate(currency, amount_minor, missing, as_of)`, `finance.services.create_rate`, and the dashboard's `finance.estimate.*` strings.

Everything Plans 46 and 54 produce is treated as existing; their names are used as they define them (rulings R2, R10).

It also applies these ledger and orchestration rules:
- **D24 / D31**: the only cross-currency figure goes through `convert_estimate` and is labelled an estimate.
- **PO-5 / FT-2**: the switch is off by default; with it off the route is 404 and nothing else moves.

## Plan rulings (where this plan fills a gap in the spec)

| # | Ruling |
|---|---|
| R1 | **The month is never a parameter.** `project()` takes no argument; the view reads no query parameter except DRF's `format`. The month is `payroll.clock.today()` (the academy's timezone), so a test moves it with the payroll `clock` fixture. |
| R2 | **One discovery query covers paying and projected teachers.** `_paying_teacher_ids(first, last, pay, *, projected=False)` gains the additive keyword and passes it to `rules.pay_rule`. Since `pay_rule(pay, projected=True)` is `pay_rule(pay) | PROJECTED`, the one query is P-4's union of Plan 46's paying teachers and the teachers with a projected row. Discovery is that set, `_pending_teacher_ids(last, pay)` and `_fixed_teacher_ids(first, pay)`, all with the same `pay`. |
| R3 | **`project()` lives in `services/projections.py`** and imports the three discovery helpers from `services/payslips.py` (same package; generate keeps using them unchanged). It is **not** `@transaction.atomic`: an atomic block would put a `SAVEPOINT` in the read-only test's captured SQL, and a projection needs no snapshot (P-7). |
| R4 | **`counters=False` skips only Plan 54's `_counters(...)` call**; the three counter fields keep their `Built` default, `None`. Lines, totals and `missing_rate` are identical either way (pinned in Task 2). |
| R5 | **The estimate is hidden in the service.** When every currency's projected total is 0, including when there are no rows, `project()` returns `estimate=None` without calling `convert_estimate`. Otherwise it converts exactly the projected totals (never the pay so far). The dashboard shows the line whenever `estimate` is not null. Negative totals are passed through unchanged (`convert_estimate` handles signs). |
| R6 | **The estimate's wording is B3h's.** The dashboard reuses the existing keys `finance.estimate.value`, `.valueNoDate`, `.addRates` and `.missing` and the "Add rates" link to `/billing/exchange-rates` (only with `exchange_rate.create`), so the app has one estimate sentence in both languages. The component is a local `EstimateLine` in the payroll feature: finance's is not exported, and it hides an all-base month, which P-6 does not. |
| R7 | **A row's teacher is the User** (`ProjectionRow.teacher`), so the payload's `teacher` is `{id: User id, full_name}` like every payroll row, and rows sort by `(full_name, pk)`. |
| R8 | **The header button** is `ProjectionsButton`, exported by the payroll feature and rendered beside `PageHeader` in `routes/_authed/payroll.payslips.index.tsx`. It renders nothing while `salary_projections` is off. The payslips page needs `payslip.view_any` already, the same code the projection needs. |
| R9 | **Query count** (P-7). The service test builds 1, then 2, then 3 teachers of the same shape, counts SELECTs, and asserts the step is the same twice and at most `PER_TEACHER_MAX = 12` (two builds of at most six SELECTs each; the bound fails on any per-line N+1). This route is the one exception to "the same count for 1 row and for 3 rows" in Global Constraints: P-7 fixes the count **per teacher** instead. |
| R10 | **Names that differ across plans, and the choice made.** `_pending_teacher_ids` is Plan 54's `(last, pay)`, not trunk's `(last)`. `_session_lines` exists in `build.py` (Plan 46 Task 4) and in `rules.py` (Plan 46 Task 7, the counter subquery): only `build._session_lines` changes. `build`'s settings parameter is `settings` (called with `settings=pay`). Before Task 2, run `grep -n "def _paying_teacher_ids\|def _pending_teacher_ids\|def _fixed_teacher_ids" backend/etqan/payroll/services/payslips.py && grep -n "def build\|def paying_sessions\|def _session_lines\|def _counters\|^MEMBER\|^SESSION" backend/etqan/payroll/services/build.py && grep -n "def pay_rule\|^PAYING_TEACHER_ATTENDANCE\|^AT_DISPOSAL_PAYS" backend/etqan/payroll/services/rules.py`; every name must print once. If one is spelled differently in trunk, use trunk's spelling everywhere below and say so in the report. |
| R11 | **Two boolean flags push `build` and `_session_lines` past ruff's five arguments.** Both carry `# noqa: PLR0913 -- keyword-only flags (B4d P-3, P-7)`, not the API-body wording, because no API body is mirrored. |
| R12 | **No seed and no access resource.** The route uses Plan 7's `payslip.view_any`; `seed_b4` is unchanged (the switch stays off in dev). The nav icon is `Telescope` (unused in `nav.ts`; `TrendingUp` is taken by levels). |
| R13 | **The E2E** builds its data through the API (`postAsAdmin`), switches features with `manage("set_features", …)` as Plan 46 Task 14 does, reads the JSON with `page.request.get` and then checks the page. The 1st of the current month is computed in UTC, the demo academy's calendar, as Plan 46 Task 14 does. |

## Global Constraints

**Repos and branches**
- The meta worktree is `/home/abdulkhalek/Projects/etqan_tutor-wt/b4`, written `$W` below.
- The branch is `feat/b4d-salary-projections`. Meta is cut from `origin/master`; `backend/` and `dashboard/` are cut from `origin/main`. `marketing/` is untouched.
- Commit in the submodule that owns each file (`git -C $W/backend …`, `git -C $W/dashboard …`).
- Never run `git submodule update`, or any other `git submodule` subcommand that writes.
- Commit messages are Conventional Commits and end with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Never edit `STATE.md`, CI workflows, Caddyfiles or meta's submodule pointers.
- Shared lists get lines only under `── phase B4 ──` markers. This plan's markers are in:
  - `etqan/platform/features.py`;
  - `dashboard/src/features/shell/nav.ts`.

  `salary_projections` is a new registry line (there is no `_later` line to flip). It goes last in the B4 block, after B4a's (and any B4b or B4c) lines.

**Commands.** The stream stack must be up (`just dev-backend`) and `$W/.env.stream` must exist. The conductor creates it when it gives B4 a slot.
- Load the stream's environment first: `cd $W; set -a; . ./.env.stream; set +a`.
- Run docker compose directly. Below, `…` stands for `docker compose -f docker-compose.local.yml`.
- **Backend tests:** `… exec -T django pytest -q <paths>`.
- **Backend format:** `… exec -T django ruff check --fix .`, then `… exec -T django ruff format .`.
- **Backend verify:** `ruff check .`, `ruff format --check .`, `lint-imports`, `pytest -q --cov=etqan`, each through `… exec -T django`.
- **No migration.** This slice adds no model and no column; `makemigrations --check` must stay clean.
- **Dashboard tests:** `… exec -T dashboard pnpm exec vitest run <paths>`.
- **Dashboard verify:** `pnpm exec tsc --noEmit`, `pnpm lint`, `pnpm test:coverage`, each through `… exec -T dashboard`. Format first with `… exec -T dashboard pnpm exec biome check --write src e2e`.
- **New route files:** regenerate `src/routeTree.gen.ts` with `… exec -T dashboard pnpm exec vite build`. It is generated: never edit it by hand.
- **Seeding:** `just _stack-manage migrate_schemas`, then `just _stack-manage seed_dev`.
- **E2E:** only through `just e2e …`.
- **Slice gates:** `just test`, `just lint`, `just e2e`.
- Never run `manage.py`, `migrate` or pytest any other way.

**Code style**
- Ruff selects `PL`, `FBT`, `DTZ`, `BLE`, `ERA`, `SLF`, `C901` (10) and `E501` (88).
- Imports are one per line (`from x import a`, then `from x import b`), as every trunk file has them.
- A boolean keyword argument is keyword-only.
- Long keyword-only signatures carry `# noqa: PLR0913 -- keyword-only; mirrors the API body (spec §8)` (this slice's two flags: R11).
- Payroll code and tests never import another app's `models`. Use `identity_services`, `catalogue_services`, `scheduling_services` and `finance_services`. Field paths on returned querysets are allowed (B4-1).
- `pnpm lint` allows semantic colour tokens only, never a literal colour, and that includes tests.

**TDD and reports**
- Every task runs its new tests before the implementation and keeps the failing output (RED) for the report, then the passing output (GREEN). A report without RED evidence is sent back.
- Trunk helpers:
  - root fixtures: `staff_for(*codes)`, `api_for("admin")`, `set_features(**switches)`, `tenants`;
  - payroll's conftest: `clock`, `world`, `admin`, `june_sessions`, `mark`, `set_rate`, `adjust`, `JUNE`, Plan 46's `rules_on`, `student_rate`, `june_group`, and Plan 54's `pay_in`, `fixed_salary`, `percent_bonus`;
  - scheduling's conftest: `make_teacher`, `make_student`, `hand_session`, `group_bundle`, `bundles_on`, `two_slots`, `subscription_for`.
- This slice adds no shared payroll test helper; its fixtures are local to its test modules.
- Every list or read that renders rows carries a query-count test that counts SELECTs only. It must give the same count for 1 row and for 3 rows (the projection's per-teacher rule is R9).
- `etqan/platform/tests/test_features.py` `BUILT` lists every built switch **in registry order**. `salary_projections` is a new line, last under `# ── phase B4 ──`.
- `etqan/access/tests/test_routes.py`:
  - the new route joins `ROUTES`, and joins `FEATURES`, under a `# Slice B4d.` comment;
  - `FEATURE_WORDS` gains `"/projection/": "salary_projections"`.
- `dashboard/src/routes/permissions.test.ts`: `FEATURE_SCREENS` gains `"/_authed/payroll/projections": "salary_projections"`, and `FEATURE_WORDS` gains `payroll\/projections|`.

**Coverage and dev data**
- Gates: backend ≥ 80 %; dashboard lines 80 / statements 80 / branches 70 / functions 70.
- The seeded dev password is `e2e-EtqanTest-2026`. The demo admin is `admin@demo.test`.

## Review Focus

1. **Generate and issue never project.** No caller but `project()` passes `projected=True` or `counters=False`, and `build(…)` with the defaults equals B4b's build object for object. Pinned by Task 2's regression test.
2. **Read-only.** `project()` takes no lock, writes nothing and opens no savepoint, with the payroll settings row present and `payroll_rules` on (so `get_settings()` runs). Pinned in Task 3 by the captured-SQL test.
3. **The teacher gate (B4-6) on scheduled rows.** A scheduled row whose teacher is already marked absent is not projected. Pinned in Tasks 2 and 3.
4. **Per class, the carrier can move.** With student rates on, a lower-id scheduled row becomes the class's carrier, so projected falls below the pay so far. Pinned in Task 3; the page says so (Task 6).
5. **Access.** `HasCode` only: a teacher, a student and a parent get 403 on the JSON **and** the CSV; staff need `payslip.view_any`; the switch off is 404. Pinned in Task 4.

---

### Task 1: The switch

**Files:**
- Modify: `backend/etqan/platform/features.py` (under `# ── phase B4 ──`, last in the block)
- Modify: `backend/etqan/platform/tests/test_features.py` (`BUILT`)

**Interfaces:**
- Produces: the switch `salary_projections` (built, off, group `money`, `requires=()`).

- [ ] **Step 1: Write the failing test**

In `etqan/platform/tests/test_features.py` `BUILT`, add as the last line of the `# ── phase B4 ──` block (after `"bulk_teacher_rates": False,` and any line B4b or B4c added there):

```python
    "salary_projections": False,
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `… exec -T django pytest -q etqan/platform/tests/test_features.py`
Expected: FAIL. The `BUILT` comparison names `salary_projections` as missing from the registry.

- [ ] **Step 3: Add the switch**

In `features.py`, as the last entry under `# ── phase B4 ──`:

```python
    # Slice B4d (P-1…P-8): the current month's salary projection, read only.
    Feature(
        "salary_projections",
        "Salary projections",
        "توقعات الرواتب",
        "money",
        built=True,
    ),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/platform/tests/test_features.py etqan/access`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/platform/features.py etqan/platform/tests/test_features.py
git -C $W/backend commit -m "feat(payroll): salary_projections switch (B4d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The projected term in the pay rule and in build

**Files:**
- Modify: `backend/etqan/payroll/services/rules.py` (`PROJECTED`, `pay_rule`)
- Modify: `backend/etqan/payroll/services/build.py` (`paying_sessions`, `_session_lines`, `build`)
- Modify: `backend/etqan/payroll/services/payslips.py` (`_paying_teacher_ids`)
- Test: `backend/etqan/payroll/tests/test_projected_build.py` (new)

**Interfaces:**
- Consumes: Plan 46's `pay_rule`, `PAYS`, `AT_DISPOSAL_PAYS`, `PAYING_TEACHER_ATTENDANCE`, `paying_sessions`, `_session_lines`, `build`, `_paying_teacher_ids`; Plan 54's `build` body and `_counters`.
- Produces:
  - `rules.PROJECTED = Q(status="scheduled", teacher_attendance__in=PAYING_TEACHER_ATTENDANCE)`;
  - `rules.pay_rule(pay, *, projected=False) -> Q`;
  - `paying_sessions(teacher, first, last, pay, *, projected=False)`;
  - `build(teacher, year, month, settings=None, *, projected=False, counters=True) -> Built`;
  - `_paying_teacher_ids(first, last, pay, *, projected=False) -> set[int]`.

- [ ] **Step 1: Run the R10 name check**

Run the three `grep` commands of ruling R10 from `$W`. Expected: each listed name prints exactly once.

- [ ] **Step 2: Write the failing tests**

`backend/etqan/payroll/tests/test_projected_build.py`:

```python
"""Slice B4d P-3: the projected term in the pay rule and in build, and the
regression guarantee (B4-2): without ``projected`` nothing moves."""

from dataclasses import replace
from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db.models import Q

from etqan.payroll.services import rules
from etqan.payroll.services.build import build
from etqan.payroll.services.payslips import _paying_teacher_ids
from etqan.payroll.services.settings import PaySettings
from etqan.payroll.services.settings import update_settings
from etqan.payroll.tests.conftest import adjust
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import set_rate
from etqan.scheduling import services as scheduling_services

# 15 June, 12:00: of Bilal's nine June sessions (1, 3, 8, 10, 15, 17, 22,
# 24, 29 June at 18:00) the first four have started.
MID_JUNE = datetime(2026, 6, 15, 12, tzinfo=UTC)


@pytest.fixture
def sessions(world, clock):
    found = june_sessions(world)
    clock.set(MID_JUNE)
    return found


def june(teacher, **kwargs):
    teacher.teacher_profile.refresh_from_db()
    return build(teacher.teacher_profile, 2026, 6, **kwargs)


def test_the_projected_term_is_added_only_when_asked():
    at_disposal = PaySettings(
        **{**PaySettings.DEFAULTS.__dict__, "at_disposal_pays": True}
    )
    assert rules.PROJECTED == Q(
        status="scheduled", teacher_attendance__in=("present", "not_set")
    )
    assert rules.pay_rule(PaySettings.DEFAULTS) == rules.PAYS
    assert rules.pay_rule(PaySettings.DEFAULTS, projected=True) == (
        rules.PAYS | rules.PROJECTED
    )
    assert rules.pay_rule(at_disposal, projected=True) == (
        rules.PAYS | rules.AT_DISPOSAL_PAYS | rules.PROJECTED
    )


def test_a_scheduled_row_is_priced_as_if_it_takes_place(world, sessions):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    assert june(world.teacher).session_ids == [sessions[0].pk]
    ahead = june(world.teacher, projected=True)
    assert ahead.session_ids == [session.pk for session in sessions]
    last = next(line for line in ahead.lines if line.session_id == sessions[8].pk)
    assert (
        last.session_status,
        last.student_attendance,
        last.pay_bp,
        last.amount_minor,
    ) == ("scheduled", "not_set", 10000, 750)
    assert ahead.gross_minor == 9 * 750


def test_weights_apply_to_completed_rows_only(world, sessions, rules_on):
    update_settings(by=None, student_absent_pay_bp=0)
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher, student="absent")
    amounts = {
        line.session_id: line.amount_minor
        for line in june(world.teacher, projected=True).lines
    }
    assert amounts[sessions[0].pk] == 0
    assert amounts[sessions[1].pk] == 750  # unmarked, in the past: projected
    assert amounts[sessions[8].pk] == 750


def test_a_scheduled_row_with_the_teacher_absent_is_not_projected(
    world, sessions, admin
):
    set_rate(world.teacher, 1000)
    scheduling_services.mark_attendance(
        sessions[3], by=admin, teacher_attendance="absent"
    )
    sessions[3].refresh_from_db()
    assert sessions[3].status == "scheduled"
    ahead = june(world.teacher, projected=True)
    assert sessions[3].pk not in ahead.session_ids
    assert len(ahead.session_ids) == 8


def test_without_the_flags_build_is_b4bs(world, sessions):
    """B4-2: ``projected=False`` and ``counters=True`` are the defaults, and
    ``counters=False`` changes only the three counters."""
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    mark(sessions[1], world.teacher, teacher="absent")
    adjust(world.teacher, "bonus", 500, on=date(2026, 6, 10))
    built = june(world.teacher)
    assert built.teacher_absences == 1
    assert june(world.teacher, projected=False, counters=True) == built
    assert june(world.teacher, counters=False) == replace(
        built, reports_sent=None, reports_missing=None, teacher_absences=None
    )


def test_discovery_finds_scheduled_rows_only_when_asked(world, sessions):
    first, last = rules.month_bounds(2026, 6)
    pay = PaySettings.DEFAULTS
    assert _paying_teacher_ids(first, last, pay) == set()
    assert _paying_teacher_ids(first, last, pay, projected=True) == {
        world.teacher.teacher_profile.pk
    }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_projected_build.py`
Expected: FAIL. `rules.PROJECTED` is missing (AttributeError), and `build()` and `_paying_teacher_ids()` refuse the `projected` / `counters` keywords (TypeError).

- [ ] **Step 4: `rules.py`**

After `AT_DISPOSAL_PAYS` (Plan 46), add `PROJECTED`, and replace `pay_rule`:

```python
# Slice B4d P-3: a scheduled session priced as if it takes place, on the same
# teacher gate as P7-2 (B4-6). Only `project()` asks for it.
PROJECTED = Q(status="scheduled", teacher_attendance__in=PAYING_TEACHER_ATTENDANCE)


def pay_rule(pay, *, projected: bool = False) -> Q:
    """Slice B4a A-5: P7-2's paying sessions, and at-disposal ones when the
    effective settings pay them. Discovery and build both use it. Slice B4d
    P-3: ``projected`` adds the month's scheduled sessions whose teacher is
    not marked absent or excused; generate and issue never pass it."""
    rule = PAYS | AT_DISPOSAL_PAYS if pay.at_disposal_pays else PAYS
    return rule | PROJECTED if projected else rule
```

- [ ] **Step 5: `build.py`**

Replace `paying_sessions`, give `_session_lines` the flag, and change three lines of `build` (Plan 54's body otherwise unchanged; edit it as trunk has it at build time):

```python
def paying_sessions(teacher, first, last, pay, *, projected: bool = False):
    """The teacher's paying sessions of the month (A-4, A-5), oldest first,
    each with ``group_bundle_id``: its group bundle's id, or None (plan R4).
    The one discovery query generate and build share. Slice B4d P-3:
    ``projected`` adds the scheduled rows `rules.PROJECTED` names."""
    return (
        scheduling_services.payroll_sessions(first, last)
        .filter(rules.pay_rule(pay, projected=projected), teacher=teacher)
        .annotate(group_bundle_id=GROUP_BUNDLE_ID)
    )


def _session_lines(  # noqa: PLR0913 -- keyword-only flags (B4d P-3, P-7)
    teacher, first, last, language, pay, *, projected: bool = False
) -> list[Line]:
    rates = rules.current_rates(teacher)
    students = rules.current_student_rates(teacher) if pay.student_rates else {}
    lines = []
    for session in paying_sessions(teacher, first, last, pay, projected=projected):
        ...  # the loop body is Plan 46's, unchanged
    return lines
```

`build`'s signature, its docstring addition, its `_session_lines` call and its `Built(...)` call:

```python
def build(  # noqa: PLR0913 -- keyword-only flags (B4d P-3, P-7)
    teacher,
    year: int,
    month: int,
    settings=None,
    *,
    projected: bool = False,
    counters: bool = True,
) -> Built:
    """(Keep Plan 7's, Plan 46's and Plan 54's docstring, and add:) Slice B4d:
    ``projected`` also prices the month's scheduled sessions whose teacher
    is not marked absent (P-3: `rules.pay_rule`); ``counters=False`` skips
    the payslip counters, which stay None (P-7). Only `project()` passes
    either; generate and issue never do."""
    pay = settings if settings is not None else effective_settings()
    first, last = rules.month_bounds(year, month)
    language = academy_services.get_settings().default_language
    sessions = _session_lines(teacher, first, last, language, pay, projected=projected)
    ...  # regroup, the fixed month, gross, adjustments, report lines: unchanged
    counts = _counters(teacher, first, last, sessions, missing, pay) if counters else {}
    return Built(
        currency=teacher.pay_currency,
        lines=(*fixed, *sessions, *adjustments, *reports),
        gross_minor=gross,
        bonuses_minor=bonuses,
        deductions_minor=deductions,
        net_minor=gross + bonuses - deductions,
        missing_rate=not fixed
        and any(
            line.rate_minor is None and line.group_role != MEMBER for line in sessions
        ),
        **counts,
    )
```

`_missing_report_ids` needs no change: `missing_reports` returns completed sessions only, so a scheduled line is never deducted. If `C901` fires on `build`, move the counters line into `_counts(teacher, first, last, sessions, missing, pay, *, counters)`; never weaken the rule.

- [ ] **Step 6: `payslips.py`**

```python
def _paying_teacher_ids(first, last, pay, *, projected: bool = False) -> set[int]:
    """TeacherProfile ids with a paying session no payslip has locked in the
    month: one query however many teachers (plan D3), with the same pay rule
    as `build`. Slice B4d (plan R2): ``projected`` also finds teachers with a
    projected scheduled row; generate never passes it."""
    return set(
        scheduling_services.payroll_sessions(first, last)
        .filter(rules.pay_rule(pay, projected=projected))
        .order_by()
        .values_list("teacher_id", flat=True)
        .distinct()
    )
```

`generate`, `issue` and `_unpaid_rows` are not touched: they call these functions without the new keywords.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`
Expected: PASS. Every Plan 7, Plan 46 and Plan 54 payroll test passes unchanged.

- [ ] **Step 8: Commit**

```bash
git -C $W/backend add etqan/payroll/services/rules.py etqan/payroll/services/build.py etqan/payroll/services/payslips.py etqan/payroll/tests/test_projected_build.py
git -C $W/backend commit -m "feat(payroll): projected term in the pay rule and build (B4d P-3)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The projection service

**Files:**
- Create: `backend/etqan/payroll/services/projections.py`
- Modify: `backend/etqan/payroll/services/__init__.py` (exports)
- Test: `backend/etqan/payroll/tests/test_projections.py` (new)

**Interfaces:**
- Consumes: Task 2's flags; `_paying_teacher_ids`, `_pending_teacher_ids(last, pay)`, `_fixed_teacher_ids(first, pay)`; `effective_settings`; `identity_services.teacher_profiles_by_id`; `payroll.clock.today`; `finance_services.convert_estimate`.
- Produces:
  - `ProjectionRow(teacher: User, currency, paid_so_far_minor, projected_minor, scheduled_sessions, scheduled_minutes, missing_rate)`;
  - `CurrencyTotal(currency, paid_so_far_minor, projected_minor)`;
  - `Projection(year, month, rows: list[ProjectionRow], totals: list[CurrencyTotal], estimate: Estimate | None)`;
  - `project() -> Projection`, exported from `etqan.payroll.services` with the three dataclasses.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_projections.py`:

```python
"""Slice B4d P-1…P-7: the current month's salary projection — pay so far
beside the projection, discovery, totals, the estimate, read-only, cost."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.academy import services as academy_services
from etqan.catalogue import services as catalogue_services
from etqan.finance import services as finance_services
from etqan.payroll import services
from etqan.payroll.models import PayrollSettings
from etqan.payroll.services import CurrencyTotal
from etqan.payroll.services.settings import update_settings
from etqan.payroll.tests.conftest import adjust
from etqan.payroll.tests.conftest import fixed_salary
from etqan.payroll.tests.conftest import june_group
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import pay_in
from etqan.payroll.tests.conftest import percent_bonus
from etqan.payroll.tests.conftest import set_rate
from etqan.payroll.tests.conftest import student_rate
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots

# 15 June, 12:00: of Bilal's nine June sessions (1, 3, 8, 10, 15, 17, 22,
# 24, 29 June at 18:00, 45 minutes) the first four have started.
MID_JUNE = datetime(2026, 6, 15, 12, tzinfo=UTC)
JUNE_1 = date(2026, 6, 1)
JUNE_10 = date(2026, 6, 10)
PER_TEACHER_MAX = 12  # plan R9: two builds of at most six SELECTs each


@pytest.fixture
def sessions(world, clock):
    found = june_sessions(world)
    clock.set(MID_JUNE)
    return found


def row_of(projection, user):
    (row,) = [row for row in projection.rows if row.teacher.pk == user.pk]
    return row


def money(row):
    return (row.paid_so_far_minor, row.projected_minor)


def scheduled(row):
    return (row.scheduled_sessions, row.scheduled_minutes)


def selects(captured):
    return [q for q in captured if q["sql"].lstrip().upper().startswith("SELECT")]


# ── The month (P-1) ──────────────────────────────────────────────────────────


def test_the_month_is_today_on_the_academys_calendar(world, clock):
    clock.set(datetime(2026, 6, 30, 22, tzinfo=UTC))
    june = services.project()
    assert (june.year, june.month) == (2026, 6)
    academy_services.update_settings(timezone="Asia/Riyadh")  # 1 July, 01:00
    july = services.project()
    assert (july.year, july.month) == (2026, 7)


# ── Pay so far and projected (P-2, P-3, P-5) ─────────────────────────────────


def test_completed_and_scheduled_rows(world, sessions, rules_on):
    """Weights apply to completed rows only; the unmarked past rows (8 and
    10 June) are projected like the five future ones."""
    update_settings(by=None, student_absent_pay_bp=5000)
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    mark(sessions[1], world.teacher, student="absent")
    row = row_of(services.project(), world.teacher)
    assert (row.currency, row.missing_rate) == ("USD", False)
    assert money(row) == (750 + 375, 750 + 375 + 7 * 750)
    assert scheduled(row) == (7, 7 * 45)


def test_a_scheduled_row_with_the_teacher_absent_is_not_projected(
    world, sessions, admin
):
    """No fixed salary and no pending adjustment: only scheduled rows, so the
    pay so far is 0."""
    set_rate(world.teacher, 1000)
    scheduling_services.mark_attendance(
        sessions[3], by=admin, teacher_attendance="absent"
    )
    row = row_of(services.project(), world.teacher)
    assert money(row) == (0, 8 * 750)
    assert scheduled(row) == (8, 8 * 45)


def test_a_scheduled_group_class_counts_once_and_members_are_not_counted(
    world, clock, bundles_on, rules_on
):
    classes = june_group(world, make_student("Zaid"))
    clock.set(MID_JUNE)
    update_settings(by=None, group_pay="per_class")
    set_rate(world.teacher, 1000)
    for session in classes[0]:
        mark(session, world.teacher)
    row = row_of(services.project(), world.teacher)
    assert len(classes) == 9
    assert money(row) == (750, 9 * 750)
    assert scheduled(row) == (8, 8 * 45)  # carriers only (A-8)


def test_per_class_a_lower_id_scheduled_row_can_bring_projected_below(
    world, clock, bundles_on, rules_on, set_features
):
    """Each class pays its carrier: so far Zaid's completed row (2000/h);
    projected, Yusuf's lower-id scheduled row (500/h)."""
    set_features(student_teacher_rate=True)
    classes = june_group(world, make_student("Zaid"))
    clock.set(datetime(2026, 6, 30, 20, tzinfo=UTC))  # every class has started
    update_settings(by=None, group_pay="per_class")
    low, high = classes[0][0], classes[0][-1]
    assert {rows[0].student_id for rows in classes} == {low.student_id}
    student_rate(world.teacher, low.student.user, 500)
    student_rate(world.teacher, high.student.user, 2000)
    for rows in classes:
        mark(rows[-1], world.teacher)
    row = row_of(services.project(), world.teacher)
    assert money(row) == (9 * 1500, 9 * 375)
    assert row.projected_minor < row.paid_so_far_minor


def test_a_fixed_salary_teacher_is_paid_the_same_either_way(
    world, sessions, set_features
):
    set_features(fixed_teacher_salary=True)
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    adjust(world.teacher, "bonus", 500, on=JUNE_10)
    row = row_of(services.project(), world.teacher)
    assert money(row) == (50500, 50500)
    assert scheduled(row) == (8, 8 * 45)
    assert row.missing_rate is False


def test_a_percentage_bonus_scales_with_the_projected_gross(
    world, sessions, set_features
):
    set_features(incentives_deductions=True)
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    percent_bonus(world.teacher, 1000, on=JUNE_10)
    row = row_of(services.project(), world.teacher)
    assert money(row) == (750 + 75, 9 * 750 + 675)


def test_a_missing_rate_is_flagged(world, sessions):
    row = row_of(services.project(), world.teacher)
    assert money(row) == (0, 0)
    assert scheduled(row) == (9, 9 * 45)
    assert row.missing_rate is True


# ── Discovery (P-4) ──────────────────────────────────────────────────────────


def test_a_teacher_whose_builds_are_empty_is_dropped(world, sessions, set_features):
    """Hamza is found through a pending percentage, but a share of a gross of
    0 makes no line in either build (B4b I-2)."""
    set_features(incentives_deductions=True)
    set_rate(world.teacher, 1000)
    hamza = make_teacher("Hamza")
    percent_bonus(hamza, 1000, on=JUNE_10)
    assert [row.teacher.pk for row in services.project().rows] == [world.teacher.pk]


def test_a_teacher_with_only_an_adjustment_is_listed(world, sessions):
    hamza = make_teacher("Hamza")
    adjust(hamza, "bonus", 700, on=JUNE_10)
    assert money(row_of(services.project(), hamza)) == (700, 700)


# ── Totals and the estimate (P-6) ────────────────────────────────────────────


def two_currencies(world, sessions):
    """Bilal (USD, 1000/h): one session done, eight to come. Hamza (EGP): a
    2000 bonus only."""
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    hamza = make_teacher("Hamza")
    pay_in(hamza, "EGP")
    adjust(hamza, "bonus", 2000, on=JUNE_10)
    return hamza


def test_rows_by_name_and_totals_per_currency(world, sessions):
    two_currencies(world, sessions)
    projection = services.project()
    assert [row.teacher.full_name for row in projection.rows] == ["Bilal", "Hamza"]
    assert projection.totals == [
        CurrencyTotal("EGP", 2000, 2000),
        CurrencyTotal("USD", 750, 9 * 750),
    ]
    assert projection.estimate is None  # exchange_rates is off


def test_the_estimate_converts_the_projected_totals(world, sessions, set_features):
    two_currencies(world, sessions)
    academy_services.update_settings(default_currency="EGP")
    set_features(exchange_rates=True)
    finance_services.create_rate(currency="USD", rate="50", by=None)
    estimate = services.project().estimate
    assert (estimate.currency, estimate.amount_minor, estimate.missing) == (
        "EGP",
        9 * 750 * 50 + 2000,
        (),
    )
    assert estimate.as_of is not None


def test_a_missing_rate_names_its_currency(world, sessions, set_features):
    two_currencies(world, sessions)
    academy_services.update_settings(default_currency="EGP")
    set_features(exchange_rates=True)
    estimate = services.project().estimate
    assert (estimate.amount_minor, estimate.missing, estimate.as_of) == (
        None,
        ("USD",),
        None,
    )


def test_no_estimate_when_every_total_is_0(world, sessions, set_features):
    set_features(exchange_rates=True)
    projection = services.project()  # Bilal has no rate: every amount is 0
    assert projection.totals == [CurrencyTotal("USD", 0, 0)]
    assert projection.estimate is None


# ── Read-only and cost (P-7) ─────────────────────────────────────────────────


def test_project_only_reads(world, sessions, rules_on, set_features):
    set_features(
        exchange_rates=True, incentives_deductions=True, fixed_teacher_salary=True
    )
    assert PayrollSettings.objects.filter(pk=1).exists()
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    adjust(world.teacher, "bonus", 500, on=JUNE_10)
    with CaptureQueriesContext(connection) as captured:
        services.project()
    written = [
        q["sql"]
        for q in captured
        if "FOR UPDATE" in q["sql"].upper()
        or "SAVEPOINT" in q["sql"].upper()
        or q["sql"].lstrip().upper().startswith(("INSERT", "UPDATE"))
    ]
    assert written == []


def test_the_query_count_is_fixed_per_teacher(world, clock):
    """Each teacher: their own student, a subscription from today, a session
    this morning marked done and the rest of June scheduled."""
    clock.set(MID_JUNE)
    on_course = [world.teacher.id]
    counts = []
    for n in range(3):
        teacher = make_teacher(f"Teacher {n}")
        on_course.append(teacher.id)
        catalogue_services.update_course(world.course, teacher_ids=on_course)
        subscription = subscription_for(
            world,
            student_id=make_student(f"Student {n}").id,
            teacher_id=teacher.id,
            starts_on=MID_JUNE.date(),
            slots=two_slots(),
        )
        done = hand_session(subscription, occurs_on=MID_JUNE.date(), start=time(9))
        mark(done, teacher)
        set_rate(teacher, 1000)
        with CaptureQueriesContext(connection) as captured:
            projection = services.project()
        assert len(projection.rows) == n + 1
        counts.append(len(selects(captured)))
    step = counts[1] - counts[0]
    assert counts[2] - counts[1] == step
    assert 0 < step <= PER_TEACHER_MAX
```

Before writing `test_the_month_is_today_on_the_academys_calendar`, read how trunk's `test_build.py::test_copied_text_is_in_the_academys_language` calls `academy_services.update_settings`, and pass `timezone=` the same way. Before writing the query-count test, check that trunk's `create_subscription` accepts `starts_on` equal to today (it generates its horizon from today); if it refuses, use `starts_on=JUNE_1` with the clock still at 1 June for the subscription, then `clock.set(MID_JUNE)` before marking.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_projections.py`
Expected: FAIL with `ImportError: cannot import name 'CurrencyTotal' from 'etqan.payroll.services'`.

- [ ] **Step 3: `services/projections.py`**

```python
"""Slice B4d: the current month's salary projection (spec P-1…P-7). Read
only: no lock, no write and no transaction of its own (plan R3). Two builds
per teacher are not one snapshot under READ COMMITTED; a projection is an
estimate."""

from dataclasses import dataclass

from etqan.finance import services as finance_services
from etqan.identity import services as identity_services
from etqan.payroll import clock
from etqan.payroll.services import rules
from etqan.payroll.services.build import MEMBER
from etqan.payroll.services.build import SESSION
from etqan.payroll.services.build import build
from etqan.payroll.services.payslips import _fixed_teacher_ids
from etqan.payroll.services.payslips import _paying_teacher_ids
from etqan.payroll.services.payslips import _pending_teacher_ids
from etqan.payroll.services.settings import effective_settings

SCHEDULED = "scheduled"


@dataclass(frozen=True)
class ProjectionRow:
    """P-5: one teacher's month, in the teacher's ``currency``. ``teacher``
    is the User (plan R7)."""

    teacher: object
    currency: str
    paid_so_far_minor: int
    projected_minor: int
    scheduled_sessions: int
    scheduled_minutes: int
    missing_rate: bool


@dataclass(frozen=True)
class CurrencyTotal:
    currency: str
    paid_so_far_minor: int
    projected_minor: int


@dataclass(frozen=True)
class Projection:
    year: int
    month: int
    rows: list[ProjectionRow]
    totals: list[CurrencyTotal]
    estimate: finance_services.Estimate | None


def _discover(first, last, pay) -> set[int]:
    """P-4 (plan R2): TeacherProfile ids with a paying or projected row, a
    pending adjustment or a counting fixed salary, all with ``pay``."""
    return (
        _paying_teacher_ids(first, last, pay, projected=True)
        | _pending_teacher_ids(last, pay)
        | _fixed_teacher_ids(first, pay)
    )


def _row(teacher, year: int, month: int, pay) -> ProjectionRow | None:
    """P-2, P-5: what generate would build now beside the projected build;
    None when both builds have no line (P-4)."""
    so_far = build(teacher, year, month, settings=pay, counters=False)
    ahead = build(
        teacher, year, month, settings=pay, projected=True, counters=False
    )
    if not so_far.lines and not ahead.lines:
        return None
    scheduled = [
        line
        for line in ahead.lines
        if line.kind == SESSION
        and line.session_status == SCHEDULED
        and line.group_role != MEMBER
    ]
    return ProjectionRow(
        teacher=teacher.user,
        currency=ahead.currency,
        paid_so_far_minor=so_far.net_minor,
        projected_minor=ahead.net_minor,
        scheduled_sessions=len(scheduled),
        scheduled_minutes=sum(line.minutes for line in scheduled),
        missing_rate=ahead.missing_rate,
    )


def _totals(rows: list[ProjectionRow]) -> list[CurrencyTotal]:
    """P-6, B4-3: one total per currency, never summed across, by code."""
    sums: dict[str, tuple[int, int]] = {}
    for row in rows:
        paid, ahead = sums.get(row.currency, (0, 0))
        sums[row.currency] = (
            paid + row.paid_so_far_minor,
            ahead + row.projected_minor,
        )
    return [CurrencyTotal(code, *sums[code]) for code in sorted(sums)]


def _estimate(totals: list[CurrencyTotal]):
    """P-6 (plan R5): the projected totals in the academy currency, or None
    when every one is 0 (the line is hidden) or `exchange_rates` is off."""
    if all(total.projected_minor == 0 for total in totals):
        return None
    return finance_services.convert_estimate(
        [
            {"currency": total.currency, "amount_minor": total.projected_minor}
            for total in totals
        ]
    )


def project() -> Projection:
    """Slice B4d §4: the current month on the academy's calendar (P-1), each
    discovered teacher's pay so far and projection (P-2…P-5), ordered by
    name, the per-currency totals and their estimate (P-6). Teacher profiles
    load in one query (P-7)."""
    pay = effective_settings()
    today = clock.today()
    first, last = rules.month_bounds(today.year, today.month)
    teachers = identity_services.teacher_profiles_by_id(_discover(first, last, pay))
    rows = [
        row
        for teacher in teachers.values()
        if (row := _row(teacher, today.year, today.month, pay)) is not None
    ]
    rows.sort(key=lambda row: (row.teacher.full_name, row.teacher.pk))
    totals = _totals(rows)
    return Projection(today.year, today.month, rows, totals, _estimate(totals))
```

Export from `services/__init__.py` (and `__all__`, alphabetically): `CurrencyTotal`, `Projection`, `ProjectionRow`, `project`.

`finance.services` is already the public path other apps use (B3's import contract forbids only finance's models, api and clock), and finance imports nothing from payroll, so there is no cycle. Confirm with `… exec -T django lint-imports` in Step 4.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`, then `… exec -T django lint-imports`
Expected: PASS, and every contract kept. If the read-only test lists a statement, the fix is in the code path that wrote it (a `get_or_create` that missed, an `atomic` block), never in the test.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/payroll/services/projections.py etqan/payroll/services/__init__.py etqan/payroll/tests/test_projections.py
git -C $W/backend commit -m "feat(payroll): salary projection service (B4d P-1..P-7)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The route, its payload and its CSV

**Files:**
- Modify: `backend/etqan/payroll/api/payloads.py` (`projection_row`, `projection`)
- Modify: `backend/etqan/payroll/api/views.py` (`PROJECTION_CSV_COLUMNS`, `ProjectionView`)
- Modify: `backend/etqan/payroll/api/urls.py`
- Modify: `backend/etqan/access/tests/test_routes.py`
- Test: `backend/etqan/payroll/tests/test_api_projections.py` (new)

**Interfaces:**
- Consumes: `services.project` (Task 3); `CSVExportMixin`, `HasCode`, `FeatureOn`.
- Produces: `GET /api/v1/payroll/payslips/projection/` → `{year, month, rows: [{teacher: {id, full_name}, currency, paid_so_far_minor, projected_minor, scheduled_sessions, scheduled_minutes, missing_rate}], totals: [{currency, paid_so_far_minor, projected_minor}], estimate: {currency, amount_minor, missing, as_of} | null}`; `?format=csv` with columns teacher, currency, scheduled_sessions, scheduled_minutes, paid_so_far_minor, projected_minor, missing_rate.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_api_projections.py`:

```python
"""Slice B4d §5: the projection route — its switch, office-only access for
the JSON and the CSV, the shape, the CSV columns and isolation."""

import csv
import io
from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django_tenants.utils import tenant_context

from etqan.academy import services as academy_services
from etqan.finance import services as finance_services
from etqan.payroll.tests.conftest import adjust
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import set_rate
from etqan.scheduling.tests.conftest import make_teacher

URL = "/api/v1/payroll/payslips/projection/"
MID_JUNE = datetime(2026, 6, 15, 12, tzinfo=UTC)


@pytest.fixture
def projections_on(set_features):
    set_features(salary_projections=True)


@pytest.fixture
def bilal(world, clock):
    """Bilal at 1000/h on 15 June: 1 June done, eight June sessions to come
    (8 and 10 June are unmarked, so projected too)."""
    sessions = june_sessions(world)
    clock.set(MID_JUNE)
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    return world.teacher


@pytest.mark.parametrize("query", [{}, {"format": "csv"}])
def test_404_while_the_switch_is_off(bilal, api_for, query):
    assert api_for("admin").get(URL, query).status_code == 404


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
@pytest.mark.parametrize("query", [{}, {"format": "csv"}])
def test_only_the_office_reads_it(bilal, api_for, projections_on, role, query):
    assert api_for(role).get(URL, query).status_code == 403


def test_a_teacher_cannot_read_even_their_own(bilal, projections_on):
    from rest_framework.test import APIClient  # noqa: PLC0415

    client = APIClient()
    client.force_login(bilal)
    assert client.get(URL).status_code == 403
    assert client.get(URL, {"format": "csv"}).status_code == 403


def test_staff_need_payslip_view_any(bilal, staff_for, projections_on):
    assert staff_for("payroll_rate.view_any").get(URL).status_code == 403
    assert staff_for("payslip.view_any").get(URL).status_code == 200


def test_the_shape(bilal, api_for, projections_on):
    assert api_for("admin").get(URL).json() == {
        "year": 2026,
        "month": 6,
        "rows": [
            {
                "teacher": {"id": bilal.id, "full_name": "Bilal"},
                "currency": "USD",
                "paid_so_far_minor": 750,
                "projected_minor": 9 * 750,
                "scheduled_sessions": 8,
                "scheduled_minutes": 360,
                "missing_rate": False,
            }
        ],
        "totals": [
            {"currency": "USD", "paid_so_far_minor": 750, "projected_minor": 6750}
        ],
        "estimate": None,
    }


def test_the_estimate_in_the_payload(bilal, api_for, projections_on, set_features):
    academy_services.update_settings(default_currency="EGP")
    set_features(exchange_rates=True)
    finance_services.create_rate(currency="USD", rate="50", by=None)
    estimate = api_for("admin").get(URL).json()["estimate"]
    assert (estimate["currency"], estimate["amount_minor"], estimate["missing"]) == (
        "EGP",
        6750 * 50,
        [],
    )
    assert estimate["as_of"] is not None


def test_the_csv(bilal, api_for, projections_on):
    resp = api_for("admin").get(URL, {"format": "csv"})
    assert resp.status_code == 200
    assert 'filename="salary-projections.csv"' in resp["Content-Disposition"]
    rows = list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))
    assert rows == [
        [
            "Teacher",
            "Currency",
            "Scheduled sessions",
            "Scheduled minutes",
            "Paid so far (minor units)",
            "Projected (minor units)",
            "Missing rate",
        ],
        ["Bilal", "USD", "8", "360", "750", "6750", "no"],
    ]


def test_another_academys_teachers_are_not_projected(
    bilal, api_for, projections_on, tenants
):
    with tenant_context(tenants.other):
        kareem = make_teacher("Kareem")
        adjust(kareem, "bonus", 700, on=date(2026, 6, 10))
    rows = api_for("admin").get(URL).json()["rows"]
    assert [row["teacher"]["full_name"] for row in rows] == ["Bilal"]
```

In `etqan/access/tests/test_routes.py`:
- `ROUTES`, under a `# Slice B4d.` comment after the payroll block (or after B4a's/B4b's lines):

```python
    # Slice B4d.
    ("GET", "/api/v1/payroll/payslips/projection/", "payslip.view_any"),
```

- `FEATURES`, under `# Phase B4, slice B4d.`:

```python
    # Phase B4, slice B4d.
    ("GET", "/api/v1/payroll/payslips/projection/"): "salary_projections",
```

- `FEATURE_WORDS`: `"/projection/": "salary_projections",  # B4d`.

If trunk's `test_routes.py` has a role-matrix test that expects every `payslip.view_any` route to admit teachers (Plan 7's `READERS`), check it lists routes explicitly; this route is `HasCode` only (P-8) and must not join any teacher-readable list.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_api_projections.py etqan/access/tests/test_routes.py`
Expected: FAIL. `payslips/projection/` resolves to nothing (404 on every call, so the 403 and 200 tests fail), and the route-table test names the missing handler.

- [ ] **Step 3: Payloads**

In `payloads.py`:

```python
def projection_row(row) -> dict:
    """Slice B4d P-5: one teacher's month, in the row's currency."""
    return {
        "teacher": person(row.teacher),
        "currency": row.currency,
        "paid_so_far_minor": row.paid_so_far_minor,
        "projected_minor": row.projected_minor,
        "scheduled_sessions": row.scheduled_sessions,
        "scheduled_minutes": row.scheduled_minutes,
        "missing_rate": row.missing_rate,
    }


def projection(result) -> dict:
    """Slice B4d §5: the month, the rows, the per-currency totals and the
    estimate of the projected totals (null while it is hidden or rates are
    off, P-6)."""
    estimate = result.estimate
    return {
        "year": result.year,
        "month": result.month,
        "rows": [projection_row(row) for row in result.rows],
        "totals": [
            {
                "currency": total.currency,
                "paid_so_far_minor": total.paid_so_far_minor,
                "projected_minor": total.projected_minor,
            }
            for total in result.totals
        ],
        "estimate": None
        if estimate is None
        else {
            "currency": estimate.currency,
            "amount_minor": estimate.amount_minor,
            "missing": list(estimate.missing),
            "as_of": estimate.as_of,
        },
    }
```

- [ ] **Step 4: The view and the route**

In `views.py` (import `FeatureOn` from `etqan.platform.permissions` if Plan 46 has not already):

```python
# Slice B4d §5: the projection's CSV, one row per teacher.
PROJECTION_CSV_COLUMNS = (
    ("teacher", "Teacher"),
    ("currency", "Currency"),
    ("scheduled_sessions", "Scheduled sessions"),
    ("scheduled_minutes", "Scheduled minutes"),
    ("paid_so_far_minor", "Paid so far (minor units)"),
    ("projected_minor", "Projected (minor units)"),
    ("missing_rate", "Missing rate"),
)


class ProjectionView(CSVExportMixin, APIView):
    """Slice B4d: the current month's salary projection. The office only
    (P-8: `HasCode`, never `READERS`), so a teacher, student or parent gets
    403 for the JSON and the CSV alike. The JSON and the CSV each run
    `project()` once (P-7)."""

    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"GET": "payslip.view_any"}
    feature = "salary_projections"
    csv_filename = "salary-projections"
    csv_columns = PROJECTION_CSV_COLUMNS

    def get(self, request):
        result = services.project()
        if self.wants_csv():
            return self.csv_response(
                [payloads.projection_row(row) for row in result.rows]
            )
        return Response(payloads.projection(result))
```

In `urls.py`, right after `payslips/generate/` and **before** `payslips/<int:pk>/`:

```python
    path(
        "payslips/projection/",
        views.ProjectionView.as_view(),
        name="payslips-projection",
    ),
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll etqan/access`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C $W/backend add etqan/payroll/api etqan/access/tests/test_routes.py etqan/payroll/tests/test_api_projections.py
git -C $W/backend commit -m "feat(payroll): salary projection route and CSV (B4d §5)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Then run the backend verify list (Global Constraints) once for the backend half of the slice, and keep the output.

---

### Task 5: Dashboard foundations — the switch, types, API, hook, fixtures, strings

**Files:**
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode`: `salary_projections` under a `// Phase B4, slice B4d.` comment)
- Modify: `dashboard/src/features/payroll/schemas.ts`
- Modify: `dashboard/src/features/payroll/api.ts`, `api.test.ts`
- Modify: `dashboard/src/features/payroll/queries.ts`
- Modify: `dashboard/src/test/payroll-fixtures.ts`
- Modify: `dashboard/src/locales/{en,ar}/payroll.json`, `nav.json`

**Interfaces:**
- Produces:
  - TS types `ProjectionRow`, `ProjectionTotal`, `ProjectionEstimate`, `Projection`;
  - `payrollApi.projection()`, `projectionCsvUrl()`;
  - hook `useSalaryProjection()`;
  - fixtures `projectionRow(o)`, `projection(o)`;
  - strings `payroll.projections.*`, `nav.payrollProjections`.

- [ ] **Step 1: Write the failing test**

Append to `src/features/payroll/api.test.ts` (and add `projectionCsvUrl` to its import from `./api`):

```ts
	it("reads the salary projection (B4d)", async () => {
		await payrollApi.projection();
		expect(api.get).toHaveBeenLastCalledWith("payroll/payslips/projection/");
		expect(projectionCsvUrl()).toBe(
			"/api/v1/payroll/payslips/projection/?format=csv",
		);
	});
```

It goes inside the existing `describe("payrollApi", …)` block, whose `vi.mock("@/lib/api", …)` already sets `defaults.baseURL` to `/api/v1/`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll/api.test.ts`
Expected: FAIL with `payrollApi.projection is not a function`.

- [ ] **Step 3: Implement**

`schemas.ts`:

```ts
/** Slice B4d P-5: one teacher's month so far and as projected, in the
 * teacher's currency. */
export interface ProjectionRow {
	teacher: Person;
	currency: string;
	paid_so_far_minor: number;
	projected_minor: number;
	scheduled_sessions: number;
	scheduled_minutes: number;
	missing_rate: boolean;
}

/** Slice B4d P-6: one currency's totals; never summed across currencies. */
export interface ProjectionTotal {
	currency: string;
	paid_so_far_minor: number;
	projected_minor: number;
}

/** Slice B4d P-6: the projected totals in the academy currency (B3h's
 * convert_estimate). `amount_minor` is null with `missing`. */
export interface ProjectionEstimate {
	currency: string;
	amount_minor: number | null;
	missing: string[];
	as_of: string | null;
}

/** Slice B4d §5: the current month on the academy's calendar. */
export interface Projection {
	year: number;
	month: number;
	rows: ProjectionRow[];
	totals: ProjectionTotal[];
	estimate: ProjectionEstimate | null;
}
```

`api.ts` (add `Projection` to the type import):

```ts
	projection: async () =>
		(await api.get<Projection>(`${PAYSLIPS}projection/`)).data,
```

and below `payslipsCsvUrl`:

```ts
/** Slice B4d: the salary projection's CSV (the office only). */
export function projectionCsvUrl(): string {
	return csvUrl(`${PAYSLIPS}projection/`, {});
}
```

`index.ts` exports `projectionCsvUrl` beside `payslipsCsvUrl`.

`queries.ts`:

```ts
/** Slice B4d: the current month's salary projection. */
export function useSalaryProjection() {
	return useQuery({
		queryKey: [...payrollKey, "projection"],
		queryFn: () => payrollApi.projection(),
	});
}
```

`payroll-fixtures.ts` (add `Projection` and `ProjectionRow` to the type import):

```ts
export function projectionRow(
	overrides: Partial<ProjectionRow> = {},
): ProjectionRow {
	return {
		teacher: { id: 21, full_name: "Bilal" },
		currency: "USD",
		paid_so_far_minor: 750,
		projected_minor: 6750,
		scheduled_sessions: 8,
		scheduled_minutes: 360,
		missing_rate: false,
		...overrides,
	};
}

export function projection(overrides: Partial<Projection> = {}): Projection {
	return {
		year: 2026,
		month: 6,
		rows: [projectionRow()],
		totals: [{ currency: "USD", paid_so_far_minor: 750, projected_minor: 6750 }],
		estimate: null,
		...overrides,
	};
}
```

`identity/schemas.ts` `FeatureCode`, after B4a's lines:

```ts
	// Phase B4, slice B4d.
	| "salary_projections"
```

Strings. `en/payroll.json` gains (same keys in `ar/payroll.json`):

```json
"projections": {
	"title": "Salary projections",
	"heading": "Projection for {{month}} {{year}}",
	"explanation": "Scheduled sessions are counted as if they take place with the student present. Report deductions are not projected. With per-class pay, the projection can be below the pay so far.",
	"teachers": "Teachers",
	"columns": {
		"teacher": "Teacher",
		"sessions": "Scheduled sessions",
		"hours": "Scheduled hours",
		"paidSoFar": "Paid so far",
		"projected": "Projected",
		"currency": "Currency"
	},
	"totals": "Totals by currency",
	"empty": "No teacher has pay or scheduled sessions this month.",
	"loadError": "The salary projection couldn't be loaded."
}
```

`ar/payroll.json`:

```json
"projections": {
	"title": "توقعات الرواتب",
	"heading": "التوقعات لشهر {{month}} {{year}}",
	"explanation": "تُحتسب الحصص المجدولة كأنها ستُعقد بحضور الطالب. لا تدخل خصومات التقارير في التوقعات. مع الدفع لكل حصة جماعية، قد يكون المتوقع أقل من المستحق حتى الآن.",
	"teachers": "المعلمون",
	"columns": {
		"teacher": "المعلم",
		"sessions": "الحصص المجدولة",
		"hours": "الساعات المجدولة",
		"paidSoFar": "المستحق حتى الآن",
		"projected": "المتوقع",
		"currency": "العملة"
	},
	"totals": "الإجماليات حسب العملة",
	"empty": "لا يوجد معلم له أجر أو حصص مجدولة هذا الشهر.",
	"loadError": "تعذر تحميل توقعات الرواتب."
}
```

`nav.json`: `"payrollProjections": "Salary projections"` / `"payrollProjections": "توقعات الرواتب"`.

The estimate line needs no new string (R6). The "Missing rate" badge reuses `payroll.missingRate`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll src/locales`, then `… exec -T dashboard pnpm exec tsc --noEmit`
Expected: PASS. The ar/en key-equality test passes.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/identity/schemas.ts src/features/payroll src/test/payroll-fixtures.ts src/locales
git -C $W/dashboard commit -m "feat(payroll): B4d projection types, API, hook, fixtures and strings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The projections page, the nav item and the header button

**Files:**
- Create: `dashboard/src/features/payroll/ProjectionsPage.tsx`, `ProjectionsPage.test.tsx`
- Create: `dashboard/src/routes/_authed/payroll.projections.tsx`
- Modify: `dashboard/src/routes/_authed/payroll.payslips.index.tsx` (the header button)
- Modify: `dashboard/src/features/payroll/index.ts`
- Modify: `dashboard/src/features/shell/nav.ts` (under `// ── phase B4 ──`)
- Modify: `dashboard/src/routes/permissions.test.ts`
- Generated: `dashboard/src/routeTree.gen.ts`

**Interfaces:**
- Consumes: `useSalaryProjection`, `projectionCsvUrl` (Task 5); `ExportButton`, `Money`, `useCan`, `useHasFeature`, `useAcademySettings`, `formatMoney`, `dayIn`, `hours`, `monthName` (trunk).
- Produces: `ProjectionsPage`, `ProjectionsButton`, and the route `/payroll/projections` (`staticData: { permission: "payslip.view_any", feature: "salary_projections" }`).

- [ ] **Step 1: Write the failing test**

`src/features/payroll/ProjectionsPage.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { adminWith } from "@/test/access-fixtures";
import { projection, projectionRow } from "@/test/payroll-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings } from "@/test/scheduling-fixtures";
import { payrollApi } from "./api";
import { ProjectionsButton, ProjectionsPage } from "./ProjectionsPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		payrollApi: { ...actual.payrollApi, projection: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const EXPLANATION =
	"Scheduled sessions are counted as if they take place with the student present. Report deductions are not projected. With per-class pay, the projection can be below the pay so far.";
const cells = (row: HTMLElement) =>
	within(row)
		.getAllByRole("cell")
		.map((cell) => cell.textContent);

describe("ProjectionsPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(payrollApi.projection).mockResolvedValue(projection());
	});
	afterEach(async () => {
		await i18n.changeLanguage("en");
	});

	it("names the server's month, explains itself and has no month picker", async () => {
		renderWithRouter(<ProjectionsPage />);
		expect(
			await screen.findByRole("heading", { name: "Projection for June 2026" }),
		).toBeInTheDocument();
		expect(screen.getByText(EXPLANATION)).toBeInTheDocument();
		expect(screen.queryByRole("combobox")).toBeNull();
	});

	it("shows each teacher's row in its currency, with a missing-rate badge", async () => {
		vi.mocked(payrollApi.projection).mockResolvedValue(
			projection({
				rows: [
					projectionRow(),
					projectionRow({
						teacher: { id: 22, full_name: "Maryam" },
						paid_so_far_minor: 0,
						projected_minor: 0,
						scheduled_sessions: 2,
						scheduled_minutes: 90,
						missing_rate: true,
					}),
				],
			}),
		);
		renderWithRouter(<ProjectionsPage />);
		const table = await screen.findByRole("table", { name: "Teachers" });
		const bilal = within(table).getByRole("row", { name: /Bilal/ });
		expect(cells(bilal)).toEqual(["Bilal", "8", "6", "$7.50", "$67.50"]);
		expect(within(bilal).queryByText("Missing rate")).toBeNull();
		const maryam = within(table).getByRole("row", { name: /Maryam/ });
		expect(within(maryam).getByText("Missing rate")).toBeInTheDocument();
	});

	it("totals each currency apart and shows a negative as negative", async () => {
		vi.mocked(payrollApi.projection).mockResolvedValue(
			projection({
				totals: [
					{ currency: "EGP", paid_so_far_minor: -5000, projected_minor: 20000 },
					{ currency: "USD", paid_so_far_minor: 750, projected_minor: 6750 },
				],
			}),
		);
		renderWithRouter(<ProjectionsPage />);
		const totals = await screen.findByRole("table", {
			name: "Totals by currency",
		});
		const usd = within(totals).getByRole("row", { name: /USD/ });
		expect(cells(usd)).toEqual(["USD", "$7.50", "$67.50"]);
		const egp = within(totals).getByRole("row", { name: /EGP/ });
		const paid = within(egp).getAllByRole("cell")[1];
		expect(paid).toHaveTextContent(/[-−]/);
		expect(paid).toHaveClass("text-destructive");
	});

	it("shows the estimate at today's rates", async () => {
		vi.mocked(payrollApi.projection).mockResolvedValue(
			projection({
				estimate: {
					currency: "EGP",
					amount_minor: 339500,
					missing: [],
					as_of: null,
				},
			}),
		);
		renderWithRouter(<ProjectionsPage />);
		expect(
			await screen.findByText(/^≈ .*3,395\.00, estimated at your current rates$/),
		).toBeInTheDocument();
	});

	it("dates the estimate by its oldest rate", async () => {
		vi.mocked(payrollApi.projection).mockResolvedValue(
			projection({
				estimate: {
					currency: "EGP",
					amount_minor: 339500,
					missing: [],
					as_of: "2026-06-10T09:00:00Z",
				},
			}),
		);
		renderWithRouter(<ProjectionsPage />);
		expect(
			await screen.findByText(/estimated at your current rates \(as of .+\)/),
		).toBeInTheDocument();
	});

	it("names the currencies that have no rate", async () => {
		vi.mocked(payrollApi.projection).mockResolvedValue(
			projection({
				estimate: {
					currency: "EGP",
					amount_minor: null,
					missing: ["GBP", "USD"],
					as_of: null,
				},
			}),
		);
		renderWithRouter(<ProjectionsPage />, {
			extraPaths: ["/billing/exchange-rates"],
		});
		expect(
			await screen.findByRole("link", { name: "Add rates" }),
		).toHaveAttribute("href", "/billing/exchange-rates");
		expect(
			screen.getByText(/for GBP, USD to see an estimate/),
		).toBeInTheDocument();
	});

	it("shows no estimate line when there is none", async () => {
		renderWithRouter(<ProjectionsPage />);
		await screen.findByRole("table", { name: "Teachers" });
		expect(screen.queryByText(/≈/)).toBeNull();
	});

	it("offers the CSV", async () => {
		renderWithRouter(<ProjectionsPage />);
		expect(
			await screen.findByRole("link", { name: "Export CSV" }),
		).toHaveAttribute("href", "/api/v1/payroll/payslips/projection/?format=csv");
	});

	it("says when no teacher has pay this month", async () => {
		vi.mocked(payrollApi.projection).mockResolvedValue(
			projection({ rows: [], totals: [] }),
		);
		renderWithRouter(<ProjectionsPage />);
		expect(
			await screen.findByText(
				"No teacher has pay or scheduled sessions this month.",
			),
		).toBeInTheDocument();
	});

	it("says when the projection can't be loaded", async () => {
		vi.mocked(payrollApi.projection).mockRejectedValue(new Error("boom"));
		renderWithRouter(<ProjectionsPage />);
		expect(
			await screen.findByText("The salary projection couldn't be loaded."),
		).toBeInTheDocument();
	});

	it("renders in Arabic", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(<ProjectionsPage />);
		expect(
			await screen.findByRole("table", { name: "المعلمون" }),
		).toBeInTheDocument();
		expect(
			screen.getByText(/تُحتسب الحصص المجدولة كأنها ستُعقد بحضور الطالب/),
		).toBeInTheDocument();
		expect(screen.getByRole("columnheader", { name: "المتوقع" })).toBeInTheDocument();
	});
});

describe("ProjectionsButton", () => {
	it("opens the projections while the switch is on", async () => {
		renderWithRouter(
			<CanProvider me={adminWith("salary_projections")}>
				<ProjectionsButton />
			</CanProvider>,
			{ extraPaths: ["/payroll/projections"] },
		);
		await userEvent.click(
			await screen.findByRole("link", { name: "Salary projections" }),
		);
		expect(await screen.findByText("at /payroll/projections")).toBeInTheDocument();
	});

	it("is not there while the switch is off", async () => {
		renderWithRouter(
			<CanProvider me={adminWith()}>
				<p>payslips</p>
				<ProjectionsButton />
			</CanProvider>,
		);
		await screen.findByText("payslips");
		expect(screen.queryByRole("link", { name: "Salary projections" })).toBeNull();
	});
});
```

Before writing the money assertions, read `PayslipsList.test.tsx`'s "$15.00" cells: USD renders as `$7.50` in English. If trunk's `academySettings()` fixture needs an argument, pass it as `PayslipsList.test.tsx` does.

- [ ] **Step 2: Run the test to verify it fails**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll/ProjectionsPage.test.tsx`
Expected: FAIL (module `./ProjectionsPage` not found).

- [ ] **Step 3: Implement `ProjectionsPage.tsx`**

```tsx
import { Link } from "@tanstack/react-router";
import { Telescope } from "lucide-react";
import { useTranslation } from "react-i18next";
import { ExportButton } from "@/components/ExportButton";
import { useAcademySettings } from "@/features/academy/queries";
import { Money } from "@/features/billing";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { cn } from "@/lib/cn";
import { formatMoney } from "@/lib/money";
import { dayIn } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	EmptyState,
	Spinner,
	StatusChip,
} from "@/ui";
import { projectionCsvUrl } from "./api";
import { hours, monthName } from "./bits";
import { useSalaryProjection } from "./queries";
import type {
	ProjectionEstimate,
	ProjectionRow,
	ProjectionTotal,
} from "./schemas";

const ROW_COLUMNS = [
	"teacher",
	"sessions",
	"hours",
	"paidSoFar",
	"projected",
] as const;
const TOTAL_COLUMNS = ["currency", "paidSoFar", "projected"] as const;

/** A money cell; a negative amount reads as negative (P-6). */
function AmountCell({ minor, currency }: { minor: number; currency: string }) {
	return (
		<td className={cn("p-3", minor < 0 && "text-destructive")}>
			<Money minor={minor} currency={currency} />
		</td>
	);
}

function Head({ keys }: { keys: readonly string[] }) {
	const { t } = useTranslation();
	return (
		<thead className="bg-secondary text-muted-foreground">
			<tr>
				{keys.map((key) => (
					<th key={key} scope="col" className="p-3 text-start font-medium">
						{t(`payroll.projections.columns.${key}`)}
					</th>
				))}
			</tr>
		</thead>
	);
}

function Rows({ rows }: { rows: ProjectionRow[] }) {
	const { t, i18n } = useTranslation();
	return (
		<div className="overflow-x-auto rounded-lg border border-border">
			<table
				className="w-full text-sm"
				aria-label={t("payroll.projections.teachers")}
			>
				<Head keys={ROW_COLUMNS} />
				<tbody>
					{rows.map((row) => (
						<tr key={row.teacher.id} className="border-t border-border">
							<td className="p-3">
								<span className="inline-flex flex-wrap items-center gap-1">
									{row.teacher.full_name}
									{row.missing_rate ? (
										<StatusChip tone="warning">
											{t("payroll.missingRate")}
										</StatusChip>
									) : null}
								</span>
							</td>
							<td className="p-3">{row.scheduled_sessions}</td>
							<td className="p-3">
								{hours(row.scheduled_minutes, i18n.language)}
							</td>
							<AmountCell minor={row.paid_so_far_minor} currency={row.currency} />
							<AmountCell minor={row.projected_minor} currency={row.currency} />
						</tr>
					))}
				</tbody>
			</table>
		</div>
	);
}

function Totals({ totals }: { totals: ProjectionTotal[] }) {
	const { t } = useTranslation();
	const title = t("payroll.projections.totals");
	return (
		<section className="flex flex-col gap-2">
			<h3 className="text-sm text-muted-foreground">{title}</h3>
			<div className="overflow-x-auto rounded-lg border border-border">
				<table className="w-full text-sm" aria-label={title}>
					<Head keys={TOTAL_COLUMNS} />
					<tbody>
						{totals.map((total) => (
							<tr key={total.currency} className="border-t border-border">
								<td className="p-3" dir="ltr">
									{total.currency}
								</td>
								<AmountCell
									minor={total.paid_so_far_minor}
									currency={total.currency}
								/>
								<AmountCell
									minor={total.projected_minor}
									currency={total.currency}
								/>
							</tr>
						))}
					</tbody>
				</table>
			</div>
		</section>
	);
}

/** B4d P-6 in B3h's words (plan R6): the projected totals as one estimate
 * in the academy currency, dated by its oldest rate in the academy's
 * timezone, or the currencies that still need a rate. */
function EstimateLine({ estimate }: { estimate: ProjectionEstimate }) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const settings = useAcademySettings({ enabled: Boolean(estimate.as_of) });
	if (estimate.amount_minor === null) {
		const rest = t("finance.estimate.missing", {
			codes: estimate.missing.join(", "),
		});
		return (
			<p className="text-sm text-muted-foreground" dir="auto">
				{can("exchange_rate.create") ? (
					<Link to="/billing/exchange-rates" className="underline">
						{t("finance.estimate.addRates")}
					</Link>
				) : (
					t("finance.estimate.addRates")
				)}{" "}
				{rest}
			</p>
		);
	}
	if (estimate.as_of && settings.isPending) return null; // the date waits for the zone
	const amount = formatMoney(
		estimate.amount_minor,
		estimate.currency,
		i18n.language,
	);
	const date =
		estimate.as_of && settings.data
			? dayIn(new Date(estimate.as_of), settings.data.timezone, i18n.language)
			: null;
	return (
		<p className="text-sm text-muted-foreground" dir="auto">
			{date
				? t("finance.estimate.value", { amount, date })
				: t("finance.estimate.valueNoDate", { amount })}
		</p>
	);
}

/** Slice B4d §6: the current month's salary projection — the server names
 * the month (no picker); each teacher's pay so far and projection in their
 * currency, per-currency totals, the estimate while there is one, one line
 * on what the projection assumes, and the CSV. */
export function ProjectionsPage() {
	const { t, i18n } = useTranslation();
	const { data, isPending, isError } = useSalaryProjection();
	if (isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("payroll.projections.loadError")}</AlertDescription>
			</Alert>
		);
	}
	if (isPending) {
		return (
			<div className="flex justify-center py-6">
				<Spinner />
			</div>
		);
	}
	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-center justify-between gap-3">
				<h2 className="text-lg font-semibold">
					{t("payroll.projections.heading", {
						month: monthName(data.month, i18n.language),
						year: data.year,
					})}
				</h2>
				<ExportButton href={projectionCsvUrl()} />
			</div>
			<p className="text-sm text-muted-foreground">
				{t("payroll.projections.explanation")}
			</p>
			{data.rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState
							icon={Telescope}
							title={t("payroll.projections.empty")}
						/>
					</CardContent>
				</Card>
			) : (
				<Rows rows={data.rows} />
			)}
			{data.totals.length > 0 ? <Totals totals={data.totals} /> : null}
			{data.estimate ? <EstimateLine estimate={data.estimate} /> : null}
		</div>
	);
}

/** Slice B4d §6 (plan R8): the payslips page's header button, only while
 * the academy has salary projections on. */
export function ProjectionsButton() {
	const { t } = useTranslation();
	const hasFeature = useHasFeature();
	if (!hasFeature("salary_projections")) return null;
	return (
		<Button asChild variant="outline" size="sm">
			<Link to="/payroll/projections">
				<Telescope className="size-4" />
				{t("payroll.projections.title")}
			</Link>
		</Button>
	);
}
```

`index.ts`: `export { ProjectionsButton, ProjectionsPage } from "./ProjectionsPage";`

Route `src/routes/_authed/payroll.projections.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { ProjectionsPage } from "@/features/payroll";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/payroll/projections")({
	staticData: {
		permission: "payslip.view_any",
		feature: "salary_projections",
	},
	component: function PayrollProjectionsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.payrollProjections"));
		return (
			<>
				<PageHeader title={t("nav.payrollProjections")} />
				<ProjectionsPage />
			</>
		);
	},
});
```

`src/routes/_authed/payroll.payslips.index.tsx`, the component's return (import `ProjectionsButton` from `@/features/payroll` beside `PayslipsList`):

```tsx
		return (
			<>
				<div className="flex flex-wrap items-start justify-between gap-3">
					<PageHeader title={t("nav.payslips")} />
					<ProjectionsButton />
				</div>
				<PayslipsList />
			</>
		);
```

`nav.ts`, under `// ── phase B4 ──`, after B4a's payroll-settings item (import `Telescope` from `lucide-react`):

```ts
	// Slice B4d: the current month's salary projection.
	office(
		"/payroll/projections",
		"nav.payrollProjections",
		Telescope,
		"payroll",
		"payslip.view_any",
		"salary_projections",
	),
```

If the nav test pins icon uniqueness or order, follow its rule.

`permissions.test.ts`: add `"/_authed/payroll/projections": "salary_projections",` to `FEATURE_SCREENS` under a `// Slice B4d` comment, and insert `payroll\/projections|` at the start of `FEATURE_WORDS`'s alternation.

- [ ] **Step 4: Regenerate the route tree, run the tests**

Run: `… exec -T dashboard pnpm exec vite build`, then `… exec -T dashboard pnpm exec vitest run src/features/payroll src/routes src/features/shell`, then `… exec -T dashboard pnpm exec tsc --noEmit`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/payroll src/routes src/features/shell/nav.ts src/routeTree.gen.ts
git -C $W/dashboard commit -m "feat(payroll): salary projections page, nav item and payslips button (B4d §6)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: End-to-end through Caddy, and the slice gates

**Files:**
- Create: `dashboard/e2e/b4-projections.spec.ts`

**Interfaces:**
- Consumes: `login`, `DEMO_URL`, `DEMO_ADMIN`, `expectLoggedIn`, `postAsAdmin` (`e2e/fixtures.ts`); `manage` (`e2e/manage.ts`); the request bodies Plan 46 Task 14 read from the trunk serializers (plan R13).

- [ ] **Step 1: Write the E2E**

```ts
import { expect, test } from "@playwright/test";
import {
	DEMO_ADMIN,
	DEMO_URL,
	expectLoggedIn,
	login,
	postAsAdmin,
} from "./fixtures";
import { manage } from "./manage";

/** The 1st of the current month, UTC (the demo academy's calendar). */
function firstOfThisMonth(): string {
	const now = new Date();
	return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))
		.toISOString()
		.slice(0, 10);
}

test.afterAll(() => {
	manage("set_features", "demo", "--off", "salary_projections");
});

// Slice B4d spec §7: with salary_projections on, a fresh teacher with a rate
// and one unmarked extra session on the 1st of this month is projected at a
// full hour and has been paid nothing so far. The test owns its teacher,
// course and student (stamped), so the seeds and re-runs never meet it.
test("an unmarked session this month is projected, not yet paid", async ({ page }) => {
	test.setTimeout(90_000);
	const stamp = Date.now();
	const name = `E2E Projected ${stamp}`;
	for (const code of ["salary_projections", "extra_sessions"])
		manage("set_features", "demo", "--on", code);
	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	const created = async (path: string, data: object) => {
		const response = await postAsAdmin(page, path, data);
		expect(response.ok(), `${path}: ${await response.text()}`).toBeTruthy();
		return response.json();
	};
	const teacher = await created("people/teachers/", {
		user: { full_name: name, email: `e2e-projected-${stamp}@e2e.test` },
		profile: { gender: "male" },
	});
	const course = await created("catalogue/courses/", {
		name_ar: `توقع ${stamp}`,
		name_en: `E2E Projection ${stamp}`,
		teacher_ids: [teacher.id],
	});
	const student = await created("people/students/", {
		user: {
			full_name: `E2E Planned ${stamp}`,
			email: `e2e-planned-${stamp}@e2e.test`,
		},
	});
	await created("sessions/extra/", {
		student: student.id,
		course: course.id,
		teacher: teacher.id,
		occurs_on: firstOfThisMonth(),
		start_time: "12:00",
		minutes: 60,
	});
	await created("payroll/rates/", { teacher: teacher.id, hourly_rate_minor: 2000 });

	// The JSON: one full hour projected, nothing paid so far
	const response = await page.request.get(
		`${DEMO_URL}/api/v1/payroll/payslips/projection/`,
	);
	expect(response.ok()).toBeTruthy();
	const body = await response.json();
	const row = body.rows.find(
		(r: { teacher: { id: number } }) => r.teacher.id === teacher.id,
	);
	expect(row).toMatchObject({
		paid_so_far_minor: 0,
		projected_minor: 2000,
		scheduled_sessions: 1,
		scheduled_minutes: 60,
		missing_rate: false,
	});

	// The page, opened from the payslips page's header button
	await page.goto(`${DEMO_URL}/app/payroll/payslips`);
	await page
		.getByRole("main")
		.getByRole("link", { name: "Salary projections" })
		.click();
	await expect(page).toHaveURL(/\/app\/payroll\/projections$/);
	const line = page
		.getByRole("table", { name: "Teachers" })
		.getByRole("row", { name: new RegExp(name) });
	const money = line.getByRole("cell");
	await expect(money.nth(1)).toHaveText("1");
	await expect(money.nth(3)).toHaveText(/(^|[^\d])0\.00$/); // paid so far
	await expect(money.nth(4)).toHaveText(/20\.00/); // projected
});
```

- The teacher create body is `{user, profile}` (`PersonWriteSerializer`), and its row's `id` is the User id, which is also the projection row's `teacher.id`.
- The extra session's 201 body is `{session, conflicts}` (B2a §8); this test does not need it.
- The button is scoped to `main` because the nav item has the same name.

- [ ] **Step 2: Run the E2E**

Run: `just e2e e2e/b4-projections.spec.ts`
Expected: PASS. If it fails, debug with `superpowers:systematic-debugging` and never weaken an assertion.

- [ ] **Step 3: The slice gates**

Run: `just test`, `just lint`, `just e2e`
Expected: all green, coverage gates met. Keep the outputs for the final review.

- [ ] **Step 4: Commit**

```bash
git -C $W/dashboard add e2e/b4-projections.spec.ts
git -C $W/dashboard commit -m "test(e2e): B4d an unmarked session this month is projected

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Spec coverage

| Spec item | Task |
|---|---|
| P-1 current month only, academy calendar, no month parameter | 3 (`test_the_month_is_today_on_the_academys_calendar`), 4 (shape), 6 (heading, no picker) |
| P-2 pay so far = net of `build(…, settings=pay)`; fixed salary and pending adjustments from day 1 | 3 (fixed salary, adjustment-only teacher) |
| P-3 `pay_rule(pay, *, projected=False)`; `paying_sessions` / `build` flag; never from generate, issue, `_unpaid_rows` | 2 |
| P-3 detail: weight 10000 on scheduled rows; teacher absent not projected; reports never projected; unmarked past rows projected; per-class carrier can move | 2, 3 |
| P-4 discovery union with one `pay`; empty teachers dropped; ordered by name | 2 (`_paying_teacher_ids(…, projected=True)`), 3 |
| P-5 row fields; `missing_rate` from the projected build; `scheduled_*` exclude member lines | 3, 4 |
| P-6 per-currency totals; estimate of projected totals only; off → null; missing rate → null amount with currencies; all zero → hidden; negatives as negative | 3, 4, 6 |
| P-7 two read-only builds, `counters=False`, profiles in one call, fixed queries per teacher, one `project()` per JSON/CSV | 2, 3, 4 |
| P-8 `HasCode` only (`payslip.view_any`), feature gate 404, teacher/student/parent 403 for JSON and CSV | 4 |
| §3 switch `salary_projections`, no model, no migration | 1 |
| §5 route before `payslips/<int:pk>/`, payload, CSV columns | 4 |
| §6 page, nav item, header button, explanation line, CSV, both languages, RTL, phone width, empty and error states | 5, 6 |
| §7 regression `build(…, projected=False)` equals B4b's | 2 |
| §7 read-only SQL with the settings row present; query count | 3 |
| §7 API: 404, 403 JSON and CSV, CSV columns, isolation | 4 |
| §7 E2E `e2e/b4-projections.spec.ts` | 7 |
