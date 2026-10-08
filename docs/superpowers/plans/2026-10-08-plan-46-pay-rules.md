# Plan 46 — Pay rules and rates (slice B4a) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B2a, B2e, B2f (all merged). No unmerged slice of another phase. B2g (substitutes) is not needed: payroll pays `session.teacher` whatever B2g does.
**Slice:** B4a · **Phase spec:** `docs/superpowers/specs/2026-10-08-b4-payroll-depth-design.md` (§1–§4 phase, §5–§11 this slice)

**Goal:** Payroll gains per-student rates, bulk rate assignment and per-academy pay rules: a weight for absent and for excused students, opt-in pay for `at_disposal` sessions, and per-class pay for group classes. Every payslip line copies its session's class, weight and group role, and payslips show TutorHamster's counter columns. Three switches are added, all off by default, and with them off every payslip pays exactly what it pays today.

**Architecture:**
- **Data** (spec §6). Payroll gets two new models, `StudentRate` and `PayrollSettings` (one row, pk 1, created by the migration). `PayslipLine` gains six descriptive columns. One migration, `payroll/0002_pay_rules`, adds tables and columns and creates the settings row; it rewrites no data.
- **Rules.**
  - `services/settings.py` holds `PaySettings`, a frozen snapshot of the effective settings, plus `effective_settings()`, `get_settings()` and `update_settings()`.
  - `rules.py` gains `FULL_BP`, the weighted `session_amount`, `pay_rule(pay)`, `weight(pay, status, attendance)`, `rate_for(..., student_rate=None)`, `current_student_rates(teacher)` and `group_key(...)`.
  - `build.py` gains `paying_sessions(teacher, first, last, pay)` and `regroup(lines, language)`, and its `Line` carries the new columns.
  - `payslips.py` reads the settings once per `generate` and per `issue`, and applies the late-row rule (A-6).
- **Rates.** `services/student_rates.py` holds the student-rate CRUD. `services/rates.py` gains `assign_rates`.
- **API.** New routes `student-rates/` (feature `student_teacher_rate`), `rates/bulk/` (feature `bulk_teacher_rates`) and `settings/` (feature `payroll_rules`, resource `payroll_settings`). Payslip rows gain `counts`, and lines gain the new columns. The CSV gains the counter columns.
- **Dashboard.** A payroll settings page, a per-student rates section and a bulk dialog on the Rates page, class badges on payslip lines, and a "Show session counts" toggle on the payslips list.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod, i18next; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-08-b4-payroll-depth-design.md`. It builds on:
- Plan 7 (`2026-09-26-payroll-design.md`; code in `backend/etqan/payroll/`);
- B2a (session kinds, `at_disposal`, `pays_teacher`);
- B2f (group bundles: `Subscription.bundle`, `SubscriptionBundle.kind = "group"`).

It also applies these ledger decisions:
- **D6** and **D15**: group rows are paid per student until B4 decides.
- **D25**: `ValidationError(code=…)`.
- **D47**: group pay.
- **D48**: P7-2 becomes configurable.

## Plan rulings (where this plan fills a gap in the spec)

| # | Ruling |
|---|---|
| R1 | **`PaySettings` is a frozen dataclass**, so settings can be passed around and compared in tests. It carries `student_absent_pay_bp`, `student_excused_pay_bp`, `at_disposal_pays`, `group_pay` and `student_rates` (bool). `student_rates` is whether `student_teacher_rate` is on: one snapshot answers every switch question `build` asks. `PaySettings.DEFAULTS` is today's rule. |
| R2 | **A student rate is keyed by `StudentProfile` id** inside `build`, because `session.student_id` is a profile id. API bodies and rows use User ids, as everywhere in payroll. |
| R3 | **The bulk route's second code** (A-11) is a payroll permission class, `AlsoUpdatesRates`, listed after `HasCode`. Admins pass, and staff must also hold `payroll_rate.update`. The route table declares `payroll_rate.create`, which `HasCode` checks. |
| R4 | **The group-class annotation** is `Case(When(subscription__bundle__kind="group", then=F("subscription__bundle_id")), default=Value(None))` on the queryset `payroll_sessions` returns (B4-1). The kind is compared as the string `"group"`, because payroll never imports scheduling's models. |
| R5 | **A member line's description** is the session's description plus ` — ` and "group class" / "حصة جماعية" in the academy's default language, the language `describe_session` already uses. |
| R6 | **Counters in the CSV** are flat keys, `count_regular` … `count_group_members`, added only to the CSV rows. JSON keeps the nested `counts`. |
| R7 | **The payslips list's counters** sit behind one checkbox, "Show session counts" (spec §9 as amended). The checkbox is kept in `localStorage` under `etqan.payroll.showCounts`, with every read and write wrapped in try/catch. |
| R8 | **The E2E builds its data through the API** (`postAsAdmin`) and switches features with `manage("set_features", …)`, as `b2-session-classes.spec.ts` does. Every exact request body is read from the trunk serializers before the test is written; none is guessed. |

## Global Constraints

**Repos and branches**
- The meta worktree is `/home/abdulkhalek/Projects/etqan_tutor-wt/b4`, written `$W` below.
- The branch is `feat/b4a-pay-rules`. Meta is cut from `origin/master`; `backend/` and `dashboard/` are cut from `origin/main`. `marketing/` is untouched.
- Commit in the submodule that owns each file (`git -C $W/backend …`, `git -C $W/dashboard …`).
- Never run `git submodule update`, or any other `git submodule` subcommand that writes.
- Commit messages are Conventional Commits and end with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Never edit `STATE.md`, CI workflows, Caddyfiles or meta's submodule pointers.
- Shared lists get lines only under `── phase B4 ──` markers. This plan's markers are in:
  - `etqan/platform/features.py`;
  - `etqan/access/registry.py`;
  - `etqan/tenants/management/commands/seed_dev.py`;
  - `dashboard/src/features/shell/nav.ts`.

  The registry's existing `_later("student_teacher_rate", …)` line is flipped **in place**.

**Commands.** The stream stack must be up (`just dev-backend`) and `$W/.env.stream` must exist. The conductor creates it when it gives B4 a slot.
- Load the stream's environment first: `cd $W; set -a; . ./.env.stream; set +a`.
- Run docker compose directly. Below, `…` stands for `docker compose -f docker-compose.local.yml`.
- **Backend tests:** `… exec -T django pytest -q <paths>`. Add `--create-db` once after the migration.
- **Backend format:** `… exec -T django ruff check --fix .`, then `… exec -T django ruff format .`.
- **Backend verify:** `ruff check .`, `ruff format --check .`, `lint-imports`, `pytest -q --cov=etqan`, each through `… exec -T django`.
- **Migration:** `… exec -T django python manage.py makemigrations payroll --name pay_rules`. Trunk's payroll leaf is `0001_initial`, so this makes `0002_pay_rules`.
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
- Long keyword-only signatures carry `# noqa: PLR0913 -- keyword-only; mirrors the API body (spec §8)`.
- Payroll code and tests never import another app's `models`. Use `identity_services`, `catalogue_services` and `scheduling_services`. Field paths on returned querysets are allowed (B4-1).
- `pnpm lint` allows semantic colour tokens only, never a literal colour, and that includes tests.

**TDD and reports**
- Every task runs its new tests before the implementation and keeps the failing output (RED) for the report, then the passing output (GREEN). A report without RED evidence is sent back.
- Trunk helpers:
  - root fixtures: `staff_for(*codes)`, `api_for("admin")`, `set_features(**switches)`;
  - payroll's conftest: `clock`, `world`, `admin`, `june_sessions`, `mark`, `set_rate`, `adjust`, `JUNE`;
  - scheduling's conftest: `make_teacher`, `make_student`, `hand_session`, `group_bundle`, `bundles_on`, `two_slots`.
- New shared payroll test helpers go once in `etqan/payroll/tests/conftest.py`: `rules_on` (Task 2), `student_rate` (Task 3) and `june_group` (Task 5).
- Every list or read that renders rows carries a query-count test that counts SELECTs only. It must give the same count for 1 row and for 3 rows.
- `etqan/platform/tests/test_features.py` `BUILT` lists every built switch **in registry order**. `student_teacher_rate` is flipped in place; `payroll_rules` and `bulk_teacher_rates` are new lines under `# ── phase B4 ──`.
- `etqan/access/tests/test_routes.py`:
  - every new route joins `ROUTES`, and every gated route joins `FEATURES`, under a `# Slice B4a.` comment;
  - `FEATURE_WORDS` gains `"/student-rates/": "student_teacher_rate"`, `"/rates/bulk/": "bulk_teacher_rates"` and `"/payroll/settings/": "payroll_rules"`.
- `dashboard/src/routes/permissions.test.ts`: `FEATURE_SCREENS` gains `"/_authed/payroll/settings": "payroll_rules"`, and `FEATURE_WORDS` gains `payroll\/settings|`.

**Coverage and dev data**
- Gates: backend ≥ 80 %; dashboard lines 80 / statements 80 / branches 70 / functions 70.
- The seeded dev password is `e2e-EtqanTest-2026`. The demo admin is `admin@demo.test`.

## Review Focus

1. **Switches off, nothing moves.** An academy that never touches B4 must see identical payslip lines and totals after the slice merges, even with a non-default settings row and student rates already saved. Pinned by Task 4's regression test (settings row edited, switches off).
2. **A rate in an old currency.** A student rate saved before the teacher's `pay_currency` changed must not count, exactly like Plan 7's course rates. Pinned in Task 3.
3. **A group class with one absent student and two present.** The class pays once at 100 %, not at the absent weight and not three times. Pinned in Task 5.
4. **Regenerate after issue under per-class.** A late row of an already-paid class must not appear in `unpaid_sessions`, but a late row of a new class must. Pinned in Task 5.
5. **Bulk assignment with a staff user holding only `payroll_rate.create`.** The request is refused with 403 and nothing is written. Pinned in Task 8.

---

### Task 1: The switches, the models and the migration

**Files:**
- Modify: `backend/etqan/platform/features.py`. Flip `student_teacher_rate` in place. Under `# ── phase B4 ──` add `payroll_rules` and `bulk_teacher_rates`.
- Modify: `backend/etqan/platform/tests/test_features.py` (`BUILT`).
- Modify: `backend/etqan/access/registry.py`. Under `# ── phase B4 ──` add the `payroll_settings` resource.
- Modify: `backend/etqan/payroll/models.py`.
- Create: `backend/etqan/payroll/migrations/0002_pay_rules.py` (generated, then edited to add the `RunPython`).
- Test: `backend/etqan/payroll/tests/test_models.py` (append).

**Interfaces:**
- Produces:
  - `StudentRate(teacher, student, hourly_rate_minor, currency, created_at, updated_at)`;
  - `PayrollSettings(student_absent_pay_bp, student_excused_pay_bp, at_disposal_pays, group_pay, updated_at, updated_by)` with `PayrollSettings.GroupPay.PER_STUDENT`/`PER_CLASS`;
  - `PayslipLine.session_kind`, `.session_status`, `.student_attendance`, `.pay_bp`, `.group_key`, `.group_role`, with `PayslipLine.GroupRole.CARRIER`/`MEMBER`;
  - switch codes `student_teacher_rate`, `payroll_rules` and `bulk_teacher_rates`, and the resource `payroll_settings` (`view`, `update`).

- [ ] **Step 1: Write the failing tests**

Append to `backend/etqan/payroll/tests/test_models.py`:

```python
from django.db import IntegrityError

from etqan.payroll.models import PayrollSettings
from etqan.payroll.models import PayslipLine
from etqan.payroll.models import StudentRate
from etqan.platform import features


def test_the_migration_creates_the_settings_row_with_todays_rule(db):
    row = PayrollSettings.objects.get(pk=1)
    assert row.student_absent_pay_bp == 10000
    assert row.student_excused_pay_bp == 10000
    assert row.at_disposal_pays is False
    assert row.group_pay == PayrollSettings.GroupPay.PER_STUDENT


@pytest.mark.parametrize("field", ["student_absent_pay_bp", "student_excused_pay_bp"])
@pytest.mark.parametrize("value", [-1, 10001])
def test_a_weight_outside_0_to_10000_is_refused_by_the_database(db, field, value):
    with pytest.raises(IntegrityError):
        PayrollSettings.objects.filter(pk=1).update(**{field: value})


def test_one_student_rate_per_teacher_and_student(world):
    teacher = world.teacher.teacher_profile
    student = world.student.student_profile
    StudentRate.objects.create(
        teacher=teacher, student=student, hourly_rate_minor=900, currency="USD"
    )
    with pytest.raises(IntegrityError):
        StudentRate.objects.create(
            teacher=teacher, student=student, hourly_rate_minor=800, currency="USD"
        )


def test_a_line_starts_with_empty_descriptive_columns(db):
    field_defaults = {
        name: PayslipLine._meta.get_field(name).default  # noqa: SLF001
        for name in ("session_kind", "session_status", "student_attendance",
                     "group_key", "group_role")
    }
    assert set(field_defaults.values()) == {""}
    assert PayslipLine._meta.get_field("pay_bp").null  # noqa: SLF001


def test_the_b4a_switches_are_built_and_off():
    for code in ("student_teacher_rate", "payroll_rules", "bulk_teacher_rates"):
        feature = features.get(code)
        assert feature.built
        assert feature.default is False
```

In `etqan/platform/tests/test_features.py` `BUILT`:
- add `"student_teacher_rate": False` at its registry position, between `study_groups` and `donations`, and extend the "Flipped in place" comment with "B4a's student_teacher_rate";
- add, under `# ── phase B4 ──` (between B3's and B6's blocks):

```python
    # ── phase B4 ──
    "payroll_rules": False,
    "bulk_teacher_rates": False,
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_models.py etqan/platform/tests/test_features.py`
Expected: FAIL with ImportError (`PayrollSettings`), and the `BUILT` comparison fails.

- [ ] **Step 3: The switches and the resource**

In `features.py`, replace the `_later("student_teacher_rate", …)` block in place with:

```python
    # Phase B4, slice B4a (A-1): flipped to built in place, off by default.
    Feature(
        "student_teacher_rate",
        "Per-student teacher rate",
        "سعر المعلم لكل طالب",
        "money",
        built=True,
    ),
```

Under `# ── phase B4 ──`:

```python
    # ── phase B4 ──
    # Slice B4a (A-3, A-12): pay weights, at-disposal pay and group-class pay.
    Feature("payroll_rules", "Payroll rules", "قواعد الرواتب", "money", built=True),
    # Slice B4a (A-2, A-12): assign one set of rates to several teachers.
    Feature(
        "bulk_teacher_rates",
        "Bulk teacher rates",
        "أسعار المعلمين بالجملة",
        "money",
        built=True,
    ),
```

In `access/registry.py`, under `# ── phase B4 ──`:

```python
    # ── phase B4 ──
    # Slice B4a (A-11): the academy's payroll rules.
    Resource(
        "payroll_settings",
        "Payroll settings",
        "إعدادات الرواتب",
        ("view", "update"),
    ),
```

- [ ] **Step 4: The models**

In `payroll/models.py`, after `TeacherRate`, add:

```python
class StudentRate(models.Model):
    """Slice B4a A-1: a teacher's hourly rate for one student, any course.
    Counts only while `student_teacher_rate` is on and in the teacher's
    current `pay_currency`."""

    teacher = models.ForeignKey(
        "identity.TeacherProfile", on_delete=models.PROTECT, related_name="+"
    )
    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    hourly_rate_minor = models.BigIntegerField(validators=[MinValueValidator(0)])
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["teacher_id", "student_id"]
        constraints = [
            models.UniqueConstraint(
                fields=["teacher", "student"], name="payroll_student_rate_one"
            ),
            models.CheckConstraint(
                condition=Q(hourly_rate_minor__gte=0),
                name="payroll_student_rate_not_negative",
            ),
        ]

    def __str__(self):
        return f"StudentRate<{self.teacher_id}, {self.student_id}>"


BP = [MinValueValidator(0), MaxValueValidator(10000)]


class PayrollSettings(models.Model):
    """Slice B4a A-3: the academy's pay rules, one row (pk 1, made by the
    migration). Read only through `services.effective_settings`, which
    gives today's rule while `payroll_rules` is off."""

    class GroupPay(models.TextChoices):
        PER_STUDENT = "per_student", "Per student"
        PER_CLASS = "per_class", "Per class"

    student_absent_pay_bp = models.PositiveSmallIntegerField(
        default=10000, validators=BP
    )
    student_excused_pay_bp = models.PositiveSmallIntegerField(
        default=10000, validators=BP
    )
    at_disposal_pays = models.BooleanField(default=False)
    group_pay = models.CharField(
        max_length=11, choices=GroupPay.choices, default=GroupPay.PER_STUDENT
    )
    updated_at = models.DateTimeField(auto_now=True)
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=Q(student_absent_pay_bp__lte=10000),
                name="payroll_settings_absent_bp_max",
            ),
            models.CheckConstraint(
                condition=Q(student_excused_pay_bp__lte=10000),
                name="payroll_settings_excused_bp_max",
            ),
        ]

    def __str__(self):
        return "PayrollSettings"
```

`PositiveSmallIntegerField` already makes PostgreSQL refuse a negative value (a check constraint), so `-1` raises `IntegrityError` too.

In `PayslipLine`, add after `amount_minor`:

```python
    class GroupRole(models.TextChoices):
        CARRIER = "carrier", "Carrier"
        MEMBER = "member", "Member"

    # Slice B4a A-7: copied from the session at build, whatever the switches;
    # empty on lines written before B4a.
    session_kind = models.CharField(max_length=12, blank=True, default="")
    session_status = models.CharField(max_length=12, blank=True, default="")
    student_attendance = models.CharField(max_length=8, blank=True, default="")
    pay_bp = models.PositiveSmallIntegerField(null=True, blank=True)
    group_key = models.CharField(max_length=64, blank=True, default="")
    group_role = models.CharField(
        max_length=7, choices=GroupRole.choices, blank=True, default=""
    )
```

`GroupRole` is a nested class. Place it at the top of the class body, next to `Kind`.

- [ ] **Step 5: The migration**

Run `… exec -T django python manage.py makemigrations payroll --name pay_rules`. Then append this `RunPython` to its `operations` and the function above `class Migration`:

```python
def create_settings_row(apps, schema_editor):
    apps.get_model("payroll", "PayrollSettings").objects.get_or_create(pk=1)


# in operations, last:
        migrations.RunPython(create_settings_row, migrations.RunPython.noop),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `… exec -T django pytest -q --create-db etqan/payroll etqan/platform/tests/test_features.py etqan/access`
Expected: PASS. The access registry test shows `payroll_settings` codes as "not used yet" until Task 8, which is allowed for an unused code.

- [ ] **Step 7: Commit**

```bash
git -C $W/backend add etqan/platform/features.py etqan/platform/tests/test_features.py etqan/access/registry.py etqan/payroll/models.py etqan/payroll/migrations/0002_pay_rules.py etqan/payroll/tests/test_models.py
git -C $W/backend commit -m "feat(payroll): B4a switches, student rates, payroll settings, line columns

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Effective settings, the weighted amount and the pay rule

**Files:**
- Create: `backend/etqan/payroll/services/settings.py`
- Modify: `backend/etqan/payroll/services/rules.py`
- Modify: `backend/etqan/payroll/services/__init__.py` (exports)
- Modify: `backend/etqan/payroll/tests/conftest.py` (`rules_on`)
- Test: `backend/etqan/payroll/tests/test_pay_rules.py` (new)

**Interfaces:**
- Consumes: `PayrollSettings` (Task 1).
- Produces:
  - `PaySettings` (frozen dataclass: `student_absent_pay_bp: int`, `student_excused_pay_bp: int`, `at_disposal_pays: bool`, `group_pay: str`, `student_rates: bool`), with `PaySettings.DEFAULTS`;
  - `get_settings() -> PayrollSettings`;
  - `effective_settings() -> PaySettings`;
  - `update_settings(*, by, **fields) -> PayrollSettings`;
  - `rules.FULL_BP = 10000`;
  - `rules.session_amount(rate_minor, minutes, pay_bp=FULL_BP)`;
  - `rules.pay_rule(pay) -> Q`;
  - `rules.weight(pay, status, student_attendance) -> int`;
  - conftest `rules_on(set_features)`, a fixture that turns `payroll_rules` on.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_pay_rules.py`:

```python
"""Slice B4a: the effective settings (A-3, B4-2), the weighted amount (B4-4)
and the paying rule (A-4, A-5)."""

import pytest

from etqan.payroll.models import PayrollSettings
from etqan.payroll.services import rules
from etqan.payroll.services.settings import PaySettings
from etqan.payroll.services.settings import effective_settings
from etqan.payroll.services.settings import get_settings
from etqan.payroll.services.settings import update_settings
from etqan.platform.exceptions import ValidationError


@pytest.mark.parametrize(
    ("rate", "minutes"), [(1000, 45), (1, 1), (999, 59), (12345, 60), (7, 30)]
)
def test_full_weight_equals_plan_7s_formula(rate, minutes):
    assert rules.session_amount(rate, minutes) == rules.round_half_up(
        rate * minutes, 60
    )
    assert rules.session_amount(rate, minutes, 10000) == rules.round_half_up(
        rate * minutes, 60
    )


def test_a_weight_scales_and_rounds_once():
    # 1000/h x 45 min = 750; half of it is 375; 1/3 of 750 is 250.
    assert rules.session_amount(1000, 45, 5000) == 375
    assert rules.session_amount(1000, 45, 3333) == 250  # 249.975 → 250
    assert rules.session_amount(1000, 45, 0) == 0


def test_settings_are_todays_rule_while_payroll_rules_is_off(db):
    update_settings(
        by=None, student_absent_pay_bp=0, at_disposal_pays=True, group_pay="per_class"
    )
    assert effective_settings() == PaySettings.DEFAULTS


def test_settings_apply_while_payroll_rules_is_on(db, rules_on):
    update_settings(by=None, student_absent_pay_bp=5000, group_pay="per_class")
    pay = effective_settings()
    assert pay.student_absent_pay_bp == 5000
    assert pay.group_pay == "per_class"
    assert pay.student_rates is False


def test_student_rates_follow_their_own_switch(db, set_features):
    set_features(student_teacher_rate=True)
    assert effective_settings().student_rates is True
    assert effective_settings().student_absent_pay_bp == 10000


def test_get_settings_recreates_a_missing_row(db):
    PayrollSettings.objects.all().delete()
    assert get_settings().pk == 1


@pytest.mark.parametrize(
    ("field", "value"),
    [("student_absent_pay_bp", 10001), ("student_excused_pay_bp", -5),
     ("group_pay", "per_family")],
)
def test_update_settings_refuses_bad_values_on_their_field(db, field, value):
    with pytest.raises(ValidationError) as caught:
        update_settings(by=None, **{field: value})
    assert caught.value.field == field


@pytest.mark.parametrize(
    ("status", "attendance", "expected"),
    [
        ("completed", "present", 10000),
        ("completed", "not_set", 10000),
        ("completed", "absent", 2500),
        ("completed", "excused", 7500),
        ("at_disposal", "not_set", 10000),
    ],
)
def test_weight_by_student_attendance(status, attendance, expected):
    pay = PaySettings(
        student_absent_pay_bp=2500,
        student_excused_pay_bp=7500,
        at_disposal_pays=True,
        group_pay="per_student",
        student_rates=False,
    )
    assert rules.weight(pay, status, attendance) == expected


def test_pay_rule_adds_at_disposal_only_when_asked():
    assert rules.pay_rule(PaySettings.DEFAULTS) == rules.PAYS
    on = PaySettings(**{**PaySettings.DEFAULTS.__dict__, "at_disposal_pays": True})
    assert rules.pay_rule(on) == rules.PAYS | rules.AT_DISPOSAL_PAYS
```

Add to `backend/etqan/payroll/tests/conftest.py`:

```python
@pytest.fixture
def rules_on(set_features):
    """Slice B4a: `payroll_rules` on (it is off by default)."""
    set_features(payroll_rules=True)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_pay_rules.py`
Expected: FAIL with `ModuleNotFoundError: etqan.payroll.services.settings`.

- [ ] **Step 3: Implement `services/settings.py`**

```python
"""Slice B4a A-3: the academy's pay rules. `build` and `generate` read
`effective_settings()` once and pass it down, so one run sees one set of
values (B4-2: today's rule while `payroll_rules` is off)."""

from dataclasses import dataclass

from django.db import transaction

from etqan.payroll.models import PayrollSettings
from etqan.payroll.services import rules
from etqan.platform import features

PER_STUDENT = PayrollSettings.GroupPay.PER_STUDENT
PER_CLASS = PayrollSettings.GroupPay.PER_CLASS
FIELDS = (
    "student_absent_pay_bp",
    "student_excused_pay_bp",
    "at_disposal_pays",
    "group_pay",
)


@dataclass(frozen=True)
class PaySettings:
    student_absent_pay_bp: int
    student_excused_pay_bp: int
    at_disposal_pays: bool
    group_pay: str
    # Whether `student_teacher_rate` is on (plan R1).
    student_rates: bool


PaySettings.DEFAULTS = PaySettings(
    student_absent_pay_bp=rules.FULL_BP,
    student_excused_pay_bp=rules.FULL_BP,
    at_disposal_pays=False,
    group_pay=PER_STUDENT,
    student_rates=False,
)


def get_settings() -> PayrollSettings:
    """The academy's row (the migration makes it; recreated if missing).
    `get_or_create` absorbs a concurrent insert itself."""
    return PayrollSettings.objects.get_or_create(pk=1)[0]


def effective_settings() -> PaySettings:
    """The rules `build` applies now: the row while `payroll_rules` is on,
    today's rule while it is off; student rates by their own switch."""
    student_rates = features.enabled("student_teacher_rate")
    if not features.enabled("payroll_rules"):
        return PaySettings(
            **{**PaySettings.DEFAULTS.__dict__, "student_rates": student_rates}
        )
    row = get_settings()
    return PaySettings(
        **{field: getattr(row, field) for field in FIELDS},
        student_rates=student_rates,
    )


@transaction.atomic
def update_settings(*, by, **fields) -> PayrollSettings:
    """Change any of ``FIELDS``; a bad value is a 400 on its field."""
    row = PayrollSettings.objects.select_for_update().get(pk=get_settings().pk)
    for field, value in fields.items():
        setattr(row, field, value)
    row.updated_by = by
    rules.save(row)
    return row
```

`rules.save` calls `full_clean`, so the validators raise a 400 on the field. That includes the `group_pay` choices and the bp range. A negative integer fails `full_clean` too, because the field is a `PositiveSmallIntegerField`.

- [ ] **Step 4: Extend `rules.py`**

Replace `session_amount` and add the rest after `PAYS`:

```python
FULL_BP = 10000  # B4-4: a weight in basis points; 10000 is 100 %
# Slice B4a A-5: an at-disposal session paid when the academy says so, on
# the same teacher gate as P7-2.
AT_DISPOSAL_PAYS = Q(
    status="at_disposal", teacher_attendance__in=PAYING_TEACHER_ATTENDANCE
)


def session_amount(rate_minor: int, minutes: int, pay_bp: int = FULL_BP) -> int:
    """The one amount formula (spec §4.1, B4-4): an hourly rate for
    ``minutes`` at weight ``pay_bp``, rounded half up once in integers. At
    full weight it is Plan 7's ``round_half_up(rate * minutes / 60)``."""
    return round_half_up(
        rate_minor * minutes * pay_bp, MINUTES_PER_HOUR * FULL_BP
    )


def pay_rule(pay) -> Q:
    """Slice B4a A-5: P7-2's paying sessions, and at-disposal ones when the
    effective settings pay them. Discovery and build both use it."""
    return PAYS | AT_DISPOSAL_PAYS if pay.at_disposal_pays else PAYS


def weight(pay, status: str, student_attendance: str) -> int:
    """Slice B4a A-4/A-5: the share of the rate a paying session earns."""
    if status == "at_disposal":
        return FULL_BP
    if student_attendance == "absent":
        return pay.student_absent_pay_bp
    if student_attendance == "excused":
        return pay.student_excused_pay_bp
    return FULL_BP
```

`settings.py` imports `rules`, so `rules` must not import `settings`. `pay_rule` and `weight` take any object with those attributes (duck-typed `PaySettings`).

Export from `services/__init__.py` (and `__all__`): `PaySettings`, `effective_settings`, `get_settings`, `update_settings`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`
Expected: PASS. Every Plan 7 test is unchanged.

- [ ] **Step 6: Commit**

```bash
git -C $W/backend add etqan/payroll/services/settings.py etqan/payroll/services/rules.py etqan/payroll/services/__init__.py etqan/payroll/tests/conftest.py etqan/payroll/tests/test_pay_rules.py
git -C $W/backend commit -m "feat(payroll): effective pay settings, weighted amount, pay rule (B4a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Per-student rates — the service and the rate precedence

**Files:**
- Create: `backend/etqan/payroll/services/student_rates.py`
- Modify: `backend/etqan/payroll/services/rules.py` (`current_student_rates`, `rate_for`)
- Modify: `backend/etqan/payroll/services/__init__.py`
- Modify: `backend/etqan/payroll/tests/conftest.py` (`student_rate`)
- Test: `backend/etqan/payroll/tests/test_student_rates.py` (new)

**Interfaces:**
- Consumes: `StudentRate` (Task 1); `rules.teacher_of` and `rules.check` (trunk).
- Produces:
  - `create_student_rate(*, teacher_id, student_id, hourly_rate_minor) -> StudentRate` (User ids);
  - `update_student_rate(rate, *, hourly_rate_minor) -> StudentRate`;
  - `delete_student_rate(rate) -> None`;
  - `student_rates_queryset() -> QuerySet[StudentRate]` (teacher and student users joined, by teacher name then student name);
  - `rules.current_student_rates(teacher) -> dict[int, int]` (StudentProfile id → rate; R2);
  - `rules.rate_for(rates, course_id, student_rate=None) -> int | None`;
  - conftest `student_rate(teacher_user, student_user, hourly)`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_student_rates.py`:

```python
"""Slice B4a A-1: per-student rates, their refusals and their currency."""

import pytest

from etqan.identity import services as identity_services
from etqan.payroll import services
from etqan.payroll.services import rules
from etqan.payroll.tests.conftest import student_rate
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import make_student


def test_a_student_rate_is_saved_in_the_teachers_currency(world):
    rate = student_rate(world.teacher, world.student, 900)
    assert rate.currency == "USD"
    assert rate.teacher.user_id == world.teacher.id
    assert rate.student.user_id == world.student.id


def test_a_second_rate_for_the_same_pair_is_409(world):
    student_rate(world.teacher, world.student, 900)
    with pytest.raises(ConflictError) as caught:
        student_rate(world.teacher, world.student, 800)
    assert caught.value.code == "payroll.rate_exists"


def test_the_people_must_be_a_teacher_and_a_student(world):
    with pytest.raises(ValidationError) as caught:
        student_rate(world.student, world.student, 900)
    assert caught.value.field == "teacher"
    with pytest.raises(ValidationError) as caught:
        student_rate(world.teacher, world.teacher, 900)
    assert caught.value.field == "student"


def test_update_saves_in_the_current_currency_and_delete_removes(world):
    rate = student_rate(world.teacher, world.student, 900)
    identity_services.update_person(world.teacher, profile={"pay_currency": "EGP"})
    updated = services.update_student_rate(rate, hourly_rate_minor=1100)
    assert (updated.hourly_rate_minor, updated.currency) == (1100, "EGP")
    services.delete_student_rate(updated)
    assert not services.student_rates_queryset().exists()


def test_current_student_rates_leave_out_an_old_currency(world):
    other = make_student("Zaid")
    student_rate(world.teacher, world.student, 900)
    student_rate(world.teacher, other, 950)
    profile = world.teacher.teacher_profile
    assert rules.current_student_rates(profile) == {
        world.student.student_profile.pk: 900,
        other.student_profile.pk: 950,
    }
    identity_services.update_person(profile.user, profile={"pay_currency": "EGP"})
    profile.refresh_from_db()
    assert rules.current_student_rates(profile) == {}


@pytest.mark.parametrize(
    ("rates", "student", "expected"),
    [
        ({None: 1000, 7: 1200}, 1500, 1500),  # the student's rate wins
        ({None: 1000, 7: 1200}, None, 1200),  # else the course's
        ({None: 1000}, None, 1000),  # else the default
        ({}, None, None),  # else none (missing rate)
    ],
)
def test_rate_precedence(rates, student, expected):
    assert rules.rate_for(rates, 7, student) == expected
```

The teacher's currency is changed with trunk's `identity_services.update_person(user, profile={...})`.

Add to the payroll conftest:

```python
def student_rate(teacher, student, hourly):
    """``teacher``'s (a User) rate for ``student`` (a User)."""
    return services.create_student_rate(
        teacher_id=teacher.id, student_id=student.id, hourly_rate_minor=hourly
    )
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_student_rates.py`
Expected: FAIL with ImportError / AttributeError (`create_student_rate`).

- [ ] **Step 3: Implement**

`services/student_rates.py`:

```python
"""Slice B4a A-1: a teacher's hourly rate for one student, saved in the
teacher's current `pay_currency` (as course rates, spec Plan 7 §4.6)."""

from django.db import IntegrityError
from django.db import transaction
from django.db.models import QuerySet

from etqan.identity import services as identity_services
from etqan.payroll.models import StudentRate
from etqan.payroll.services import rules
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

RATE_EXISTS = "payroll.rate_exists"


def _student_of(user_id: int):
    profile = identity_services.get_student_profile(user_id)
    if profile is None or profile.user.role != "student":
        raise ValidationError("Choose a student.", field="student")
    return profile


@transaction.atomic
def create_student_rate(
    *, teacher_id: int, student_id: int, hourly_rate_minor: int
) -> StudentRate:
    teacher = rules.teacher_of(teacher_id)
    rate = StudentRate(
        teacher=teacher,
        student=_student_of(student_id),
        hourly_rate_minor=hourly_rate_minor,
        currency=teacher.pay_currency,
    )
    rules.check(rate)
    try:
        with transaction.atomic():
            rate.save()
    except IntegrityError:
        raise ConflictError(
            "This teacher already has a rate for this student. Edit it instead.",
            code=RATE_EXISTS,
        ) from None
    return rate


def _lock(rate: StudentRate) -> StudentRate:
    try:
        return (
            StudentRate.objects.select_for_update(of=("self",))
            .select_related("teacher")
            .get(pk=rate.pk)
        )
    except StudentRate.DoesNotExist:
        raise NotFoundError("Rate", rate.pk) from None


@transaction.atomic
def update_student_rate(rate: StudentRate, *, hourly_rate_minor: int) -> StudentRate:
    locked = _lock(rate)
    locked.hourly_rate_minor = hourly_rate_minor
    locked.currency = locked.teacher.pay_currency
    rules.save(locked, update_fields=["hourly_rate_minor", "currency", "updated_at"])
    return locked


@transaction.atomic
def delete_student_rate(rate: StudentRate) -> None:
    _lock(rate).delete()


def student_rates_queryset() -> QuerySet[StudentRate]:
    return StudentRate.objects.select_related(
        "teacher__user", "student__user"
    ).order_by("teacher__user__full_name", "teacher_id", "student__user__full_name")
```

`rules.check` uses `full_clean(validate_constraints=False)`, so the unique pair is decided by the database (IntegrityError → 409), as `rates._insert` does for course rates.

In `rules.py`:

```python
def current_student_rates(teacher) -> dict[int, int]:
    """Slice B4a A-1: the teacher's student rates in their current
    ``pay_currency``, StudentProfile id → hourly rate (plan R2)."""
    return dict(
        StudentRate.objects.filter(
            teacher=teacher, currency=teacher.pay_currency
        ).values_list("student_id", "hourly_rate_minor")
    )


def rate_for(
    rates: dict[int | None, int], course_id: int, student_rate: int | None = None
) -> int | None:
    """Slice B4a A-1: the student's rate, else the course's, else the
    default, else None (spec Plan 7 §4.1)."""
    if student_rate is not None:
        return student_rate
    return rates.get(course_id, rates.get(None))
```

Import `StudentRate` in `rules.py`. Export the four service functions from `services/__init__.py`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/payroll/services/student_rates.py etqan/payroll/services/rules.py etqan/payroll/services/__init__.py etqan/payroll/tests/conftest.py etqan/payroll/tests/test_student_rates.py
git -C $W/backend commit -m "feat(payroll): per-student teacher rates and rate precedence (B4a A-1)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Build with weights, at-disposal pay, student rates and the copied columns

**Files:**
- Modify: `backend/etqan/payroll/services/build.py`
- Modify: `backend/etqan/payroll/services/payslips.py` (`write`, `generate`, `issue`, `_paying_teacher_ids`)
- Test: `backend/etqan/payroll/tests/test_build_rules.py` (new)

**Interfaces:**
- Consumes:
  - `PaySettings`, `effective_settings` (Task 2);
  - `rules.pay_rule`, `rules.weight`, `rules.session_amount(…, pay_bp)` (Task 2);
  - `rules.current_student_rates`, `rules.rate_for(…, student_rate)` (Task 3).
- Produces:
  - `build(teacher, year, month, settings=None) -> Built`, where `None` means "read `effective_settings()`";
  - `Line` gains `session_kind`, `session_status`, `student_attendance`, `pay_bp`, `group_key` and `group_role`, all defaulting to `""` or `None`;
  - `paying_sessions(teacher, first, last, pay) -> QuerySet` (annotated with `group_bundle_id`);
  - `rules.group_key(bundle_id, starts_at, minutes) -> str`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_build_rules.py`. It uses `sessions` (Bilal's nine June sessions, July 1st) the way `test_build.py` defines it. Copy that fixture's three lines into the new file; a fixture local to a test module is not a shared helper.

```python
"""Slice B4a: build with the pay rules (A-1, A-4, A-5, A-7) and the
regression guarantee (B4-2)."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.payroll.services import rules
from etqan.payroll.services.build import build
from etqan.payroll.services.settings import update_settings
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import set_rate
from etqan.payroll.tests.conftest import student_rate
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import hand_session

JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)


@pytest.fixture
def sessions(world, clock):
    found = june_sessions(world)
    clock.set(JULY_FIRST)
    return found


def june(teacher, **kwargs):
    teacher.teacher_profile.refresh_from_db()
    return build(teacher.teacher_profile, 2026, 6, **kwargs)


def every_class(world, sessions, admin):
    """Session 0 present, 1 absent, 2 excused student; 3 at disposal with
    the teacher present; 4 teacher absent (never paid); 5 a hand-added extra
    session, student present; the rest untouched (scheduled)."""
    mark(sessions[0], world.teacher)
    mark(sessions[1], world.teacher, student="absent")
    mark(sessions[2], world.teacher, student="excused")
    scheduling_services.place_at_disposal(sessions[3], by=admin)
    scheduling_services.mark_attendance(
        sessions[3], by=admin, teacher_attendance="present"
    )
    mark(sessions[4], world.teacher, teacher="absent")
    extra = hand_session(
        sessions[0].subscription, occurs_on=date(2026, 6, 6), kind="extra"
    )
    mark(extra, world.teacher)
    return extra


def test_with_every_switch_off_lines_and_totals_are_plan_7s(
    world, sessions, admin
):
    """B4-2: a non-default settings row and a student rate change nothing
    while their switches are off."""
    set_rate(world.teacher, 1000)
    student_rate(world.teacher, world.student, 5000)
    update_settings(
        by=None, student_absent_pay_bp=0, student_excused_pay_bp=0,
        at_disposal_pays=True, group_pay="per_class",
    )
    extra = every_class(world, sessions, admin)
    built = june(world.teacher)
    paid = [sessions[0].pk, sessions[1].pk, sessions[2].pk, extra.pk]
    assert sorted(built.session_ids) == sorted(paid)
    for line in built.lines:
        assert line.rate_minor == 1000
        assert line.amount_minor == rules.round_half_up(1000 * line.minutes, 60)
    assert built.gross_minor == 4 * 750
    assert built.missing_rate is False


def test_lines_copy_the_session_class_whatever_the_switches(
    world, sessions, admin
):
    set_rate(world.teacher, 1000)
    extra = every_class(world, sessions, admin)
    by_id = {line.session_id: line for line in june(world.teacher).lines}
    assert by_id[sessions[1].pk].student_attendance == "absent"
    assert by_id[sessions[1].pk].session_kind == "regular"
    assert by_id[sessions[1].pk].session_status == "completed"
    assert by_id[sessions[1].pk].pay_bp == 10000
    assert by_id[extra.pk].session_kind == "extra"
    assert {line.group_key for line in by_id.values()} == {""}
    assert {line.group_role for line in by_id.values()} == {""}


def test_weights_and_at_disposal_apply_while_payroll_rules_is_on(
    world, sessions, admin, rules_on
):
    set_rate(world.teacher, 1000)
    update_settings(
        by=None, student_absent_pay_bp=5000, student_excused_pay_bp=2500,
        at_disposal_pays=True,
    )
    every_class(world, sessions, admin)
    by_id = {line.session_id: line for line in june(world.teacher).lines}
    assert by_id[sessions[0].pk].amount_minor == 750
    assert (by_id[sessions[1].pk].pay_bp, by_id[sessions[1].pk].amount_minor) == (
        5000, 375,
    )
    assert by_id[sessions[2].pk].amount_minor == 188  # 187.5 → 188
    assert by_id[sessions[3].pk].session_status == "at_disposal"
    assert by_id[sessions[3].pk].amount_minor == 750
    assert sessions[4].pk not in by_id


def test_at_disposal_with_the_teacher_absent_never_pays(
    world, sessions, admin, rules_on
):
    set_rate(world.teacher, 1000)
    update_settings(by=None, at_disposal_pays=True)
    scheduling_services.place_at_disposal(sessions[3], by=admin)
    scheduling_services.mark_attendance(
        sessions[3], by=admin, teacher_attendance="absent"
    )
    assert june(world.teacher).session_ids == []


def test_a_student_rate_wins_while_its_switch_is_on(
    world, sessions, set_features
):
    set_features(student_teacher_rate=True)
    set_rate(world.teacher, 1000)
    student_rate(world.teacher, world.student, 2000)
    mark(sessions[0], world.teacher)
    (line,) = june(world.teacher).lines
    assert (line.rate_minor, line.amount_minor) == (2000, 1500)


def test_settings_passed_in_are_used_as_given(world, sessions, rules_on):
    """generate and issue read the settings once and pass them (A-3)."""
    from etqan.payroll.services.settings import PaySettings  # noqa: PLC0415

    set_rate(world.teacher, 1000)
    mark(sessions[1], world.teacher, student="absent")
    half = PaySettings(**{**PaySettings.DEFAULTS.__dict__, "student_absent_pay_bp": 5000})
    (line,) = june(world.teacher, settings=half).lines
    assert line.amount_minor == 375
```

Before writing `every_class`, check B2a's attendance rule for an at-disposal session: its teacher attendance may be marked by the office (A-11). Use the trunk service; if `mark_attendance` refuses teacher marks there, use the trunk route's service instead. Also check that `hand_session(..., kind="extra")` is valid without the `extra_sessions` switch, since it writes straight to the table. Replace `PLC0415` local imports with a module-level import if ruff flags them.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_build_rules.py`
Expected: FAIL. `build()` takes no `settings`, `Line` has no `session_kind`, and the weights are not applied.

- [ ] **Step 3: Implement in `build.py`**

Extend `Line`:

```python
@dataclass(frozen=True)
class Line:
    kind: str
    description: str
    amount_minor: int  # signed: a deduction is negative
    session_id: int | None = None
    adjustment_id: int | None = None
    minutes: int | None = None
    rate_minor: int | None = None
    # Slice B4a A-7: what the session was, copied whatever the switches.
    session_kind: str = ""
    session_status: str = ""
    student_attendance: str = ""
    pay_bp: int | None = None
    group_key: str = ""
    group_role: str = ""
```

Add, and rewrite `_session_lines`:

```python
GROUP_BUNDLE_ID = Case(
    When(subscription__bundle__kind="group", then=F("subscription__bundle_id")),
    default=Value(None),
    output_field=IntegerField(),
)


def paying_sessions(teacher, first, last, pay):
    """The teacher's paying sessions of the month (A-4, A-5), oldest first,
    each with ``group_bundle_id``: its group bundle's id, or None (plan R4).
    The one discovery query generate and build share."""
    return (
        scheduling_services.payroll_sessions(first, last)
        .filter(rules.pay_rule(pay), teacher=teacher)
        .annotate(group_bundle_id=GROUP_BUNDLE_ID)
    )


def _session_lines(teacher, first, last, language, pay) -> list[Line]:
    rates = rules.current_rates(teacher)
    students = rules.current_student_rates(teacher) if pay.student_rates else {}
    lines = []
    for session in paying_sessions(teacher, first, last, pay):
        rate = rules.rate_for(rates, session.course_id, students.get(session.student_id))
        pay_bp = rules.weight(pay, session.status, session.student_attendance)
        lines.append(
            Line(
                kind=SESSION,
                session_id=session.pk,
                description=describe_session(session, language),
                minutes=session.minutes,
                rate_minor=rate,
                amount_minor=0
                if rate is None
                else rules.session_amount(rate, session.minutes, pay_bp),
                session_kind=session.kind,
                session_status=session.status,
                student_attendance=session.student_attendance,
                pay_bp=pay_bp,
                group_key=rules.group_key(
                    session.group_bundle_id, session.starts_at, session.minutes
                ),
            )
        )
    return lines
```

`build` gains `settings=None`:

```python
def build(teacher, year: int, month: int, settings=None) -> Built:
    """... (keep the docstring; add:) ``settings`` are the effective pay
    rules (slice B4a); None reads them now."""
    pay = settings if settings is not None else effective_settings()
    first, last = rules.month_bounds(year, month)
    language = academy_services.get_settings().default_language
    sessions = _session_lines(teacher, first, last, language, pay)
    ...  # unchanged
```

`settings.py` imports only `rules` and models, so `build.py` may import `from etqan.payroll.services.settings import effective_settings` with no cycle.

In `rules.py`:

```python
def group_key(bundle_id: int | None, starts_at, minutes: int) -> str:
    """Slice B4a A-7: one group class's key, stable across builds; empty
    without a group bundle."""
    if bundle_id is None:
        return ""
    stamp = starts_at.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    return f"{bundle_id}:{stamp}:{minutes}"
```

- [ ] **Step 4: Thread the settings through `payslips.py`**

- `write()` copies the six new fields onto each `PayslipLine` (`session_kind=line.session_kind`, …).
- `_paying_teacher_ids(first, last, pay)` filters `rules.pay_rule(pay)` instead of `rules.PAYS`.
- `generate()` reads `pay = effective_settings()` right after the counter lock, then calls `_paying_teacher_ids(first, last, pay)` and `build(teacher, year, month, settings=pay)`.
- `issue()` reads `pay = effective_settings()` after the locks and calls `build(..., settings=pay)`.

The spec's lock order is unchanged.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll etqan/scheduling/tests -k "payroll or paylock"`, then `… exec -T django pytest -q etqan/payroll`
Expected: PASS. Every trunk payroll test passes unchanged.

- [ ] **Step 6: Commit**

```bash
git -C $W/backend add etqan/payroll/services/build.py etqan/payroll/services/payslips.py etqan/payroll/services/rules.py etqan/payroll/tests/test_build_rules.py
git -C $W/backend commit -m "feat(payroll): weights, at-disposal pay and student rates in build (B4a)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Per-class group pay and the late-row rule

**Files:**
- Modify: `backend/etqan/payroll/services/build.py` (`regroup`, `missing_rate`)
- Modify: `backend/etqan/payroll/services/payslips.py` (the `unpaid_sessions` rule)
- Modify: `backend/etqan/payroll/tests/conftest.py` (`june_group`)
- Test: `backend/etqan/payroll/tests/test_group_pay.py` (new)

**Interfaces:**
- Consumes: `paying_sessions`, `Line.group_key`/`group_role` (Task 4); `PayslipLine.GroupRole` (Task 1).
- Produces:
  - `regroup(lines: list[Line], language: str) -> list[Line]`;
  - `PER_CLASS` behaviour in `build`;
  - `payslips._unpaid_rows(teacher, first, last, pay) -> bool`;
  - conftest `june_group(world, *others) -> list[list[Session]]` (each June class's rows).

- [ ] **Step 1: Write the failing tests**

Add to the payroll conftest:

```python
def june_group(world, *others):
    """A group bundle (B2f) for ``world``'s student and ``others`` from
    1 June, Mondays and Wednesdays 18:00, generated for June; returns each
    class's rows, oldest class first, each class's rows by id."""
    from itertools import groupby  # noqa: PLC0415

    created = group_bundle(world, *others)
    for member in created.members:
        scheduling_services.generate(*JUNE, subscription=member)
    rows = sorted(
        (
            session
            for member in created.members
            for session in scheduling_services.sessions_of(member).filter(
                occurs_on__range=JUNE
            )
        ),
        key=lambda s: (s.starts_at, s.pk),
    )
    return [list(group) for _, group in groupby(rows, key=lambda s: s.starts_at)]
```

Import `group_bundle` from scheduling's conftest. Read B2f's `CreatedBundle.members` in trunk: if members are not `Subscription` objects, map them to their subscriptions the way scheduling's tests do. The `bundles_on` fixture is needed wherever `group_bundle` is called.

`backend/etqan/payroll/tests/test_group_pay.py`:

```python
"""Slice B4a A-6: per-class pay for group classes, and late rows of a class
already paid (P7-4)."""

from datetime import UTC
from datetime import datetime

import pytest

from etqan.payroll import services
from etqan.payroll.models import Payslip
from etqan.payroll.services.build import build
from etqan.payroll.services.settings import update_settings
from etqan.payroll.tests.conftest import june_group
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import set_rate
from etqan.scheduling.tests.conftest import make_student

JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)
AUGUST_FIRST = datetime(2026, 8, 1, 9, tzinfo=UTC)


@pytest.fixture
def classes(world, clock, bundles_on):
    found = june_group(world, make_student("Zaid"), make_student("Omar"))
    clock.set(JULY_FIRST)
    return found


@pytest.fixture
def per_class(rules_on):
    update_settings(by=None, group_pay="per_class")


def june(world):
    world.teacher.teacher_profile.refresh_from_db()
    return build(world.teacher.teacher_profile, 2026, 6)


def test_per_student_pays_each_row_as_today(world, classes):
    set_rate(world.teacher, 1000)
    for row in classes[0]:
        mark(row, world.teacher)
    built = june(world)
    assert [line.amount_minor for line in built.lines] == [750, 750, 750]
    assert {line.group_role for line in built.lines} == {""}
    assert len({line.group_key for line in built.lines}) == 1


def test_per_class_pays_the_class_once(world, classes, per_class):
    set_rate(world.teacher, 1000)
    first, *rest = classes[0]
    for row in classes[0]:
        mark(row, world.teacher)
    lines = {line.session_id: line for line in june(world).lines}
    assert lines[first.pk].group_role == "carrier"
    assert lines[first.pk].amount_minor == 750
    for row in rest:
        member = lines[row.pk]
        assert (member.group_role, member.amount_minor, member.rate_minor) == (
            "member", 0, None,
        )
        assert member.minutes == row.minutes
        assert member.description.endswith("— group class")
    assert june(world).gross_minor == 750
    assert june(world).missing_rate is False


def test_one_present_student_makes_the_class_full_pay(world, classes, per_class):
    update_settings(by=None, student_absent_pay_bp=0)
    set_rate(world.teacher, 1000)
    a, b, c = classes[0]
    mark(a, world.teacher, student="absent")
    mark(b, world.teacher, student="absent")
    mark(c, world.teacher, student="present")
    built = june(world)
    assert built.gross_minor == 750
    carrier = next(line for line in built.lines if line.group_role == "carrier")
    assert (carrier.session_id, carrier.pay_bp) == (a.pk, 10000)


def test_all_absent_class_pays_at_the_absent_weight(world, classes, per_class):
    update_settings(by=None, student_absent_pay_bp=5000)
    set_rate(world.teacher, 1000)
    for row in classes[0]:
        mark(row, world.teacher, student="absent")
    assert june(world).gross_minor == 375


def test_a_row_the_teacher_missed_is_not_in_the_class(world, classes, per_class):
    set_rate(world.teacher, 1000)
    a, b, c = classes[0]
    mark(a, world.teacher, teacher="absent")
    mark(b, world.teacher)
    mark(c, world.teacher)
    lines = {line.session_id: line for line in june(world).lines}
    assert a.pk not in lines
    assert lines[b.pk].group_role == "carrier"


def test_without_a_rate_only_the_carrier_is_missing(world, classes, per_class):
    for row in classes[0]:
        mark(row, world.teacher)
    built = june(world)
    assert built.missing_rate is True
    assert sum(1 for line in built.lines if line.rate_minor is None) == 3


def test_issue_locks_every_row_of_a_class(world, classes, per_class, admin):
    set_rate(world.teacher, 1000)
    for row in classes[0]:
        mark(row, world.teacher)
    services.generate(2026, 6)
    payslip = Payslip.objects.get(teacher__user=world.teacher)
    services.issue(payslip, by=admin)
    for row in classes[0]:
        row.refresh_from_db()
        assert row.payroll_locked


def test_a_late_row_of_a_paid_class_is_not_reported_unpaid(
    world, classes, per_class, admin, clock
):
    """A-6 late rows: the class is paid; paying the row again would pay the
    hour twice. A late row of a new class is still reported."""
    set_rate(world.teacher, 1000)
    a, b, c = classes[0]
    mark(a, world.teacher)
    mark(b, world.teacher)
    services.generate(2026, 6)
    services.issue(Payslip.objects.get(teacher__user=world.teacher), by=admin)
    clock.set(AUGUST_FIRST)
    mark(c, world.teacher)  # completed after June was issued
    assert services.generate(2026, 6).unpaid_sessions == []
    mark(classes[1][0], world.teacher)  # a class no payslip paid
    assert services.generate(2026, 6).unpaid_sessions == [world.teacher]
```

`test_without_a_rate_only_the_carrier_is_missing` checks two things. `missing_rate` is driven by the carrier. Members also have `rate_minor` None by definition, so all three lines have no rate; the test asserts both facts.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_group_pay.py`
Expected: the per-class tests and the late-row test FAIL. `test_per_student_pays_each_row_as_today` already passes from Task 4, and that is expected.

- [ ] **Step 3: Implement `regroup` and the missing-rate rule**

In `build.py`:

```python
CARRIER = PayslipLine.GroupRole.CARRIER
MEMBER = PayslipLine.GroupRole.MEMBER
GROUP_CLASS = {"en": "group class", "ar": "حصة جماعية"}


def regroup(lines: list[Line], language: str) -> list[Line]:
    """Slice B4a A-6, per class: in each group class (same ``group_key``)
    the lowest session id carries the pay at the class's highest weight; the
    other rows are member lines of 0 with no rate. Order is kept."""
    classes: dict[str, list[Line]] = {}
    for line in lines:
        if line.group_key:
            classes.setdefault(line.group_key, []).append(line)
    replaced: dict[int, Line] = {}
    note = GROUP_CLASS[_suffix(language)]
    for rows in classes.values():
        carrier = min(rows, key=lambda line: line.session_id)
        pay_bp = max(line.pay_bp for line in rows)
        replaced[carrier.session_id] = replace(
            carrier,
            group_role=CARRIER,
            pay_bp=pay_bp,
            amount_minor=0
            if carrier.rate_minor is None
            else rules.session_amount(carrier.rate_minor, carrier.minutes, pay_bp),
        )
        for line in rows:
            if line is not carrier:
                replaced[line.session_id] = replace(
                    line,
                    group_role=MEMBER,
                    rate_minor=None,
                    amount_minor=0,
                    description=f"{line.description} — {note}",
                )
    return [replaced.get(line.session_id, line) for line in lines]
```

In `build()`, after `_session_lines`:

```python
    if pay.group_pay == PER_CLASS:
        sessions = regroup(sessions, language)
    ...
        missing_rate=any(
            line.rate_minor is None and line.group_role != MEMBER for line in sessions
        ),
```

Import `replace` from `dataclasses` and `PER_CLASS` from `services.settings`.

- [ ] **Step 4: The late-row rule in `generate`**

In `payslips.py`:

```python
def _unpaid_rows(teacher, first, last, pay) -> bool:
    """Whether a paying row of an issued or paid month still waits for a
    later adjustment (P7-4). Per class (A-6), a row whose class is already on
    the teacher's issued or paid lines does not: that hour is paid."""
    rows = build_module.paying_sessions(teacher, first, last, pay)
    if pay.group_pay != PER_CLASS:
        return rows.exists()
    paid = set(
        PayslipLine.objects.filter(
            payslip__teacher=teacher, payslip__status__in=(ISSUED, PAID)
        )
        .exclude(group_key="")
        .values_list("group_key", flat=True)
    )
    return any(
        not (key := rules.group_key(row.group_bundle_id, row.starts_at, row.minutes))
        or key not in paid
        for row in rows
    )
```

In `generate`, replace `if teacher_id in paying: unpaid.append(teacher.user)` with `if teacher_id in paying and _unpaid_rows(teacher, first, last, pay): unpaid.append(teacher.user)`.

Import `paying_sessions` directly (`from etqan.payroll.services.build import paying_sessions`) rather than as a module alias, matching the file's style.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C $W/backend add etqan/payroll/services/build.py etqan/payroll/services/payslips.py etqan/payroll/tests/conftest.py etqan/payroll/tests/test_group_pay.py
git -C $W/backend commit -m "feat(payroll): per-class group pay and the late-row rule (B4a A-6)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Bulk rate assignment

**Files:**
- Modify: `backend/etqan/payroll/services/rates.py` (`assign_rates`, `AssignResult`)
- Modify: `backend/etqan/payroll/services/__init__.py`
- Test: `backend/etqan/payroll/tests/test_bulk_rates.py` (new)

**Interfaces:**
- Consumes: `rules.teacher_of` (trunk) and `catalogue_services.get_course` (trunk).
- Produces: `assign_rates(*, teacher_ids: list[int], rates: list[dict]) -> AssignResult(created: int, updated: int)`. Each entry in `rates` is `{"course_id": int | None, "hourly_rate_minor": int}`.

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B4a A-2: one set of rates saved to several teachers at once."""

import pytest

from etqan.identity import services as identity_services
from etqan.payroll import services
from etqan.payroll.models import TeacherRate
from etqan.payroll.tests.conftest import set_rate
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import make_teacher


def rates_of(user):
    return dict(
        TeacherRate.objects.filter(teacher__user=user).values_list(
            "course_id", "hourly_rate_minor"
        )
    )


def test_creates_and_updates_and_leaves_other_rates_alone(world):
    other = make_teacher("Hamza")
    set_rate(world.teacher, 500)
    fiqh = set_rate(world.teacher, 700, course=world.course)  # updated below
    result = services.assign_rates(
        teacher_ids=[world.teacher.id, other.id],
        rates=[
            {"course_id": None, "hourly_rate_minor": 1000},
            {"course_id": world.course.pk, "hourly_rate_minor": 1200},
        ],
    )
    assert (result.created, result.updated) == (2, 2)
    assert rates_of(world.teacher) == {None: 1000, world.course.pk: 1200}
    assert rates_of(other) == {None: 1000, world.course.pk: 1200}
    fiqh.refresh_from_db()
    assert fiqh.currency == "USD"


def test_a_rate_for_another_course_is_untouched(world):
    from etqan.scheduling.tests.conftest import other_course  # noqa: PLC0415

    fiqh = other_course(world)
    set_rate(world.teacher, 900, course=fiqh)
    services.assign_rates(
        teacher_ids=[world.teacher.id],
        rates=[{"course_id": None, "hourly_rate_minor": 1000}],
    )
    assert rates_of(world.teacher) == {None: 1000, fiqh.pk: 900}


def test_mixed_currencies_are_refused_and_nothing_is_written(world):
    other = make_teacher("Hamza")
    identity_services.update_person(other, profile={"pay_currency": "EGP"})
    with pytest.raises(ValidationError) as caught:
        services.assign_rates(
            teacher_ids=[world.teacher.id, other.id],
            rates=[{"course_id": None, "hourly_rate_minor": 1000}],
        )
    assert (caught.value.field, caught.value.code) == (
        "teachers", "payroll.mixed_currencies",
    )
    assert not TeacherRate.objects.exists()


@pytest.mark.parametrize(
    ("teachers", "rates", "field"),
    [
        ("student", [{"course_id": None, "hourly_rate_minor": 1}], "teachers"),
        ("teacher", [], "rates"),
        ("teacher", [{"course_id": 999999, "hourly_rate_minor": 1}], "rates"),
        (
            "teacher",
            [{"course_id": None, "hourly_rate_minor": 1}] * 2,
            "rates",
        ),
    ],
)
def test_bad_input_is_400_on_its_field(world, teachers, rates, field):
    who = world.teacher if teachers == "teacher" else world.student
    with pytest.raises(ValidationError) as caught:
        services.assign_rates(teacher_ids=[who.id], rates=rates)
    assert caught.value.field == field
    assert not TeacherRate.objects.exists()


def test_a_concurrent_insert_is_409_and_rolls_back(world, monkeypatch):
    """The unique constraint decides a race (A-2): simulated by inserting
    the row between the lock and the insert."""
    from etqan.payroll.services import rates as rates_module  # noqa: PLC0415

    original = rates_module._existing  # noqa: SLF001

    def racing(teachers):
        found = original(teachers)
        TeacherRate.objects.create(
            teacher=teachers[0], course_id=None, hourly_rate_minor=1, currency="USD"
        )
        return found

    monkeypatch.setattr(rates_module, "_existing", racing)
    with pytest.raises(ConflictError) as caught:
        services.assign_rates(
            teacher_ids=[world.teacher.id],
            rates=[{"course_id": None, "hourly_rate_minor": 1000}],
        )
    assert caught.value.code == "payroll.rate_exists"
```

In the race test, the inserted row is rolled back with the batch, because the test DB transaction contains the savepoint. The test asserts only the code. If `ValidationError` has no `code` attribute on trunk, read D25's implementation in `etqan/platform/exceptions.py` for the attribute name.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_bulk_rates.py`
Expected: FAIL with AttributeError (`assign_rates`).

- [ ] **Step 3: Implement in `rates.py`**

```python
@dataclass(frozen=True)
class AssignResult:
    created: int
    updated: int


def _teachers(teacher_ids: list[int]) -> list:
    if not teacher_ids:
        raise ValidationError("Choose at least one teacher.", field="teachers")
    teachers = [rules.teacher_of(pk, field="teachers") for pk in teacher_ids]
    if len({teacher.pay_currency for teacher in teachers}) > 1:
        raise ValidationError(
            "These teachers are paid in different currencies.",
            field="teachers",
            code="payroll.mixed_currencies",
        )
    return teachers


def _checked(rates: list[dict]) -> list[dict]:
    courses = [rate["course_id"] for rate in rates]
    if not rates or len(set(courses)) != len(courses):
        raise ValidationError("Give each course one rate.", field="rates")
    for course_id in courses:
        if course_id is not None and catalogue_services.get_course(course_id) is None:
            raise ValidationError("Choose a course.", field="rates")
    return rates


def _existing(teachers) -> dict[tuple[int, int | None], TeacherRate]:
    """The teachers' rates, `FOR UPDATE` in id order."""
    rows = TeacherRate.objects.select_for_update().filter(
        teacher__in=teachers
    ).order_by("pk")
    return {(row.teacher_id, row.course_id): row for row in rows}


@transaction.atomic
def assign_rates(*, teacher_ids: list[int], rates: list[dict]) -> AssignResult:
    """Slice B4a A-2: save each rate to every teacher, updating the (teacher,
    course) rate that exists and creating the rest; other rates untouched.
    One currency for the batch; all or nothing; a concurrent insert of the
    same rate is 409 `payroll.rate_exists`."""
    teachers = _teachers(list(dict.fromkeys(teacher_ids)))
    rates = _checked(rates)
    existing = _existing(teachers)
    created = updated = 0
    try:
        with transaction.atomic():
            for teacher in teachers:
                for rate in rates:
                    row = existing.get((teacher.pk, rate["course_id"]))
                    if row is None:
                        row = TeacherRate(teacher=teacher, course_id=rate["course_id"])
                        created += 1
                    else:
                        updated += 1
                    row.hourly_rate_minor = rate["hourly_rate_minor"]
                    row.currency = teacher.pay_currency
                    rules.save(row)
    except IntegrityError:
        raise ConflictError(
            "A rate was added meanwhile. Try again.", code="payroll.rate_exists"
        ) from None
    return AssignResult(created=created, updated=updated)
```

- Check that trunk's `ValidationError` takes `code=` (D25) and keep the keyword name it has.
- Import `dataclass` and `ConflictError`.
- `assign_rates` exceeds no complexity limit as written. If ruff's `C901` fires, move the inner loop into `_save_all(teachers, rates, existing) -> tuple[int, int]`.
- Export `assign_rates` and `AssignResult` from the services package.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/payroll/services/rates.py etqan/payroll/services/__init__.py etqan/payroll/tests/test_bulk_rates.py
git -C $W/backend commit -m "feat(payroll): bulk rate assignment for several teachers (B4a A-2)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Counters on payslips, the new line fields and the CSV

**Files:**
- Modify: `backend/etqan/payroll/services/rules.py` (`payslips_queryset`, `_session_lines`)
- Modify: `backend/etqan/payroll/api/payloads.py` (`payslip_row`, `line_row`, `csv_row`)
- Modify: `backend/etqan/payroll/api/views.py` (`CSV_COLUMNS`, the CSV branch)
- Test: `backend/etqan/payroll/tests/test_counts.py` (new)

**Interfaces:**
- Consumes: the line columns (Task 1) and build (Tasks 4–5).
- Produces:
  - the payslip row's `counts: {regular, compensation, extra, trial, at_disposal, student_absent, student_excused, group_members} | null`;
  - line rows with `session_kind`, `session_status`, `student_attendance`, `pay_bp`, `group_key` and `group_role`;
  - CSV columns `count_*` (R6).

- [ ] **Step 1: Write the failing tests**

```python
"""Slice B4a A-8: counters from the session lines, members left out of the
sessions and minutes, legacy payslips, the line fields and the CSV."""

from datetime import UTC
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.payroll import services
from etqan.payroll.models import Payslip
from etqan.payroll.models import PayslipLine
from etqan.payroll.services.settings import update_settings
from etqan.payroll.tests.conftest import june_group
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import set_rate
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher

JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)
URL = "/api/v1/payroll/payslips/"


def selects(captured):
    return [q for q in captured if q["sql"].lstrip().upper().startswith("SELECT")]


def test_counts_by_class_and_attendance(world, clock, api_for):
    sessions = june_sessions(world)
    clock.set(JULY_FIRST)
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    mark(sessions[1], world.teacher, student="absent")
    mark(sessions[2], world.teacher, student="excused")
    services.generate(2026, 6)
    (row,) = api_for("admin").get(URL).json()["results"]
    assert row["counts"] == {
        "regular": 3, "compensation": 0, "extra": 0, "trial": 0,
        "at_disposal": 0, "student_absent": 1, "student_excused": 1,
        "group_members": 0,
    }
    assert (row["sessions"], row["minutes"]) == (3, 135)


def test_member_lines_are_counted_apart_not_in_hours(
    world, clock, bundles_on, rules_on, api_for
):
    classes = june_group(world, make_student("Zaid"))
    clock.set(JULY_FIRST)
    update_settings(by=None, group_pay="per_class")
    set_rate(world.teacher, 1000)
    for row in classes[0]:
        mark(row, world.teacher)
    services.generate(2026, 6)
    (row,) = api_for("admin").get(URL).json()["results"]
    assert row["counts"]["group_members"] == 1
    assert (row["sessions"], row["minutes"]) == (1, 45)


def test_a_payslip_written_before_b4a_has_null_counts(world, clock, api_for):
    sessions = june_sessions(world)
    clock.set(JULY_FIRST)
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    services.generate(2026, 6)
    PayslipLine.objects.update(session_kind="", session_status="")
    (row,) = api_for("admin").get(URL).json()["results"]
    assert row["counts"] is None


def test_lines_carry_their_class(world, clock, api_for):
    sessions = june_sessions(world)
    clock.set(JULY_FIRST)
    set_rate(world.teacher, 1000)
    mark(sessions[1], world.teacher, student="absent")
    services.generate(2026, 6)
    payslip = Payslip.objects.get()
    (line,) = api_for("admin").get(f"{URL}{payslip.pk}/").json()["lines"]
    assert {key: line[key] for key in (
        "session_kind", "session_status", "student_attendance", "pay_bp",
        "group_key", "group_role",
    )} == {
        "session_kind": "regular", "session_status": "completed",
        "student_attendance": "absent", "pay_bp": 10000, "group_key": "",
        "group_role": "",
    }


```

**Query count.** The counters are annotations on `payslips_queryset()`, so trunk's
`test_api.py::test_the_payslip_list_costs_the_same_queries_for_more_rows` already pins their cost. It runs
the list with 3 payslips, then with 6, and asserts the same count. It must keep passing unchanged; do not
add a second query-count test. Trunk's CSV test (`test_api.py`, the exact-row assertion near line 250) gains
the eight counter values at the end of its expected row (`"2", "0", "0", "0", "0", "0", "0", "0"` for its
two regular sessions: read its fixture for the real numbers).

**CSV test.** Add to `test_counts.py`:

```python
def test_the_csv_has_the_counter_columns(world, clock, api_for):
    sessions = june_sessions(world)
    clock.set(JULY_FIRST)
    set_rate(world.teacher, 1000)
    mark(sessions[1], world.teacher, student="absent")
    services.generate(2026, 6)
    response = api_for("admin").get(URL, {"format": "csv"})
    header, row = response.content.decode().splitlines()[:2]
    assert "Regular sessions" in header
    assert "Student absent" in header
    assert "Group members" in header
    assert row.endswith(",1,0,0,0,0,1,0,0") or ",1,0,0,0,0,1,0,0," in row
```

The CSV row assertion depends on the column order. Put the eight `count_*` columns **last** in `CSV_COLUMNS` and assert `row.endswith(",1,0,0,0,0,1,0,0")` only.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_counts.py`
Expected: FAIL with `KeyError: 'counts'`.

- [ ] **Step 3: Implement**

In `rules.py`, give `_session_lines` filters and exclude member lines from `sessions` and `minutes`:

```python
COUNTS = {
    "regular": Q(session_kind="regular"),
    "compensation": Q(session_kind="compensation"),
    "extra": Q(session_kind="extra"),
    "trial": Q(session_kind="trial"),
    "at_disposal": Q(session_status="at_disposal"),
    "student_absent": Q(student_attendance="absent"),
    "student_excused": Q(student_attendance="excused"),
    "group_members": Q(group_role="member"),
}
NOT_MEMBER = ~Q(group_role="member")


def _session_lines(aggregate, condition=NOT_MEMBER):
    lines = (
        PayslipLine.objects.filter(
            condition, payslip=OuterRef("pk"), kind=PayslipLine.Kind.SESSION
        )
        .order_by()
        .values("payslip")
        .annotate(value=aggregate)
        .values("value")
    )
    return Coalesce(Subquery(lines, output_field=IntegerField()), Value(0))


def payslips_queryset() -> QuerySet[Payslip]:
    """... (keep the docstring; add:) Slice B4a A-8: ``count_<name>`` per
    class from the copied line columns, and ``legacy`` when a session line
    predates them (its counts are then unknown)."""
    return Payslip.objects.select_related(
        "teacher__user", "issued_by", "paid_by"
    ).annotate(
        sessions=_session_lines(Count("pk")),
        minutes=_session_lines(Sum("minutes")),
        legacy=Exists(
            PayslipLine.objects.filter(
                payslip=OuterRef("pk"), kind=PayslipLine.Kind.SESSION, session_kind=""
            )
        ),
        **{
            f"count_{name}": _session_lines(Count("pk"), condition)
            for name, condition in COUNTS.items()
        },
    )
```

`GROUP_MEMBERS` passes `Q(group_role="member")` as its condition, so it counts members.

In `payloads.py`:

```python
def counts_of(payslip) -> dict | None:
    """Slice B4a A-8: None when the payslip predates the copied columns."""
    if payslip.legacy:
        return None
    return {name: getattr(payslip, f"count_{name}") for name in COUNT_NAMES}
```

Define `COUNT_NAMES` in the payloads module as the eight names in order. It must not import `rules` from services (`payloads` already imports nothing from services), so repeat the names there. A test pins the two lists equal:

```python
def test_payload_and_rules_name_the_same_counters():
    from etqan.payroll.api.payloads import COUNT_NAMES  # noqa: PLC0415
    from etqan.payroll.services.rules import COUNTS  # noqa: PLC0415

    assert list(COUNTS) == list(COUNT_NAMES)
```

- `payslip_row` adds `"counts": counts_of(payslip)`.
- `line_row` adds the six fields.
- Add `csv_row(row)`, which returns `{**row, **{f"count_{n}": (row["counts"] or {}).get(n, "") for n in COUNT_NAMES}}`.

In `views.py`:
- `CSV_COLUMNS` gains, last:
  - `("count_regular", "Regular sessions")`
  - `("count_compensation", "Compensation sessions")`
  - `("count_extra", "Extra sessions")`
  - `("count_trial", "Trial sessions")`
  - `("count_at_disposal", "At disposal")`
  - `("count_student_absent", "Student absent")`
  - `("count_student_excused", "Student excused")`
  - `("count_group_members", "Group members")`
- The CSV branch maps rows through `payloads.csv_row`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`
Expected: PASS. Trunk `test_api.py` assertions on exact payslip rows may need `counts` and the line fields added. Update those dict literals: they now describe the B4a payload, and that is an expected change.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/payroll/services/rules.py etqan/payroll/api/payloads.py etqan/payroll/api/views.py etqan/payroll/tests/test_counts.py etqan/payroll/tests/test_api.py
git -C $W/backend commit -m "feat(payroll): payslip counters, line class fields, CSV counter columns (B4a A-8)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The routes — student rates, bulk rates and settings

**Files:**
- Modify: `backend/etqan/payroll/api/serializers.py`
- Modify: `backend/etqan/payroll/api/payloads.py` (`student_rate_row`, `settings_row`)
- Modify: `backend/etqan/payroll/api/views.py`
- Modify: `backend/etqan/payroll/api/urls.py`
- Modify: `backend/etqan/access/tests/test_routes.py`
- Test: `backend/etqan/payroll/tests/test_api_pay_rules.py` (new)

**Interfaces:**
- Consumes: Task 2 settings services, Task 3 student-rate services, Task 6 `assign_rates`.
- Produces:
  - `GET/POST /api/v1/payroll/student-rates/`, `PATCH/DELETE /api/v1/payroll/student-rates/<id>/`;
  - `POST /api/v1/payroll/rates/bulk/`;
  - `GET/PATCH /api/v1/payroll/settings/`.

  Shapes are as in spec §8. The settings row is `{student_absent_pay_bp, student_excused_pay_bp, at_disposal_pays, group_pay, updated_at, updated_by: {id, full_name} | null}`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_api_pay_rules.py`:

```python
"""Slice B4a §8: the new routes, their switches, codes and shapes."""

import pytest

from etqan.payroll.models import StudentRate
from etqan.payroll.models import TeacherRate
from etqan.payroll.tests.conftest import student_rate

P = "/api/v1/payroll/"


@pytest.fixture
def all_on(set_features):
    set_features(student_teacher_rate=True, payroll_rules=True, bulk_teacher_rates=True)


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("get", "student-rates/"),
        ("post", "rates/bulk/"),
        ("get", "settings/"),
        ("patch", "settings/"),
    ],
)
def test_each_route_is_404_while_its_switch_is_off(world, api_for, method, path):
    response = getattr(api_for("admin"), method)(f"{P}{path}", {}, format="json")
    assert response.status_code == 404


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
@pytest.mark.parametrize(
    ("method", "path"),
    [("get", "student-rates/"), ("post", "rates/bulk/"), ("get", "settings/")],
)
def test_people_outside_the_office_get_403(world, api_for, all_on, role, method, path):
    response = getattr(api_for(role), method)(f"{P}{path}", {}, format="json")
    assert response.status_code == 403


def test_student_rates_round_trip(world, api_for, all_on):
    client = api_for("admin")
    created = client.post(
        f"{P}student-rates/",
        {"teacher": world.teacher.id, "student": world.student.id,
         "hourly_rate_minor": 900},
        format="json",
    )
    assert created.status_code == 201
    row = created.json()
    assert row["teacher"] == {"id": world.teacher.id, "full_name": world.teacher.full_name}
    assert row["student"] == {"id": world.student.id, "full_name": world.student.full_name}
    assert (row["hourly_rate_minor"], row["currency"], row["current"]) == (900, "USD", True)
    listed = client.get(f"{P}student-rates/", {"teacher": world.teacher.id}).json()
    assert [r["id"] for r in listed] == [row["id"]]
    patched = client.patch(
        f"{P}student-rates/{row['id']}/", {"hourly_rate_minor": 950}, format="json"
    )
    assert patched.json()["hourly_rate_minor"] == 950
    assert client.delete(f"{P}student-rates/{row['id']}/").status_code == 204
    assert not StudentRate.objects.exists()


def test_a_duplicate_student_rate_is_409(world, api_for, all_on):
    student_rate(world.teacher, world.student, 900)
    response = api_for("admin").post(
        f"{P}student-rates/",
        {"teacher": world.teacher.id, "student": world.student.id,
         "hourly_rate_minor": 1},
        format="json",
    )
    assert (response.status_code, response.json()["code"]) == (409, "payroll.rate_exists")


def test_bulk_needs_both_rate_codes(world, staff_for, all_on):
    body = {"teachers": [world.teacher.id],
            "rates": [{"course": None, "hourly_rate_minor": 1000}]}
    only_create = staff_for("payroll_rate.create")
    assert only_create.post(f"{P}rates/bulk/", body, format="json").status_code == 403
    assert not TeacherRate.objects.exists()
    both = staff_for("payroll_rate.create", "payroll_rate.update")
    response = both.post(f"{P}rates/bulk/", body, format="json")
    assert response.status_code == 200
    assert response.json() == {"created": 1, "updated": 0}


def test_bulk_mixed_currencies_is_400_with_its_code(world, api_for, all_on):
    from etqan.identity import services as identity_services  # noqa: PLC0415
    from etqan.scheduling.tests.conftest import make_teacher  # noqa: PLC0415

    other = make_teacher("Hamza")
    identity_services.update_person(other, profile={"pay_currency": "EGP"})
    response = api_for("admin").post(
        f"{P}rates/bulk/",
        {"teachers": [world.teacher.id, other.id],
         "rates": [{"course": None, "hourly_rate_minor": 1000}]},
        format="json",
    )
    assert response.status_code == 400
    assert response.json()["code"] == "payroll.mixed_currencies"


def test_settings_read_and_update(world, staff_for, all_on):
    reader = staff_for("payroll_settings.view")
    row = reader.get(f"{P}settings/").json()
    assert row["group_pay"] == "per_student"
    assert reader.patch(f"{P}settings/", {"group_pay": "per_class"},
                        format="json").status_code == 403
    writer = staff_for("payroll_settings.view", "payroll_settings.update")
    updated = writer.patch(
        f"{P}settings/", {"student_absent_pay_bp": 5000, "group_pay": "per_class"},
        format="json",
    ).json()
    assert (updated["student_absent_pay_bp"], updated["group_pay"]) == (5000, "per_class")
    assert updated["updated_by"]["id"] == writer.user.id
    bad = writer.patch(f"{P}settings/", {"student_excused_pay_bp": 10001}, format="json")
    assert bad.status_code == 400
```

**Cross-academy isolation.** Add one test with `tenants.other`, following trunk payroll `test_api.py`'s isolation test. A student rate made in the other academy is not listed in this one.

**Error body field.** The error body carries `code` for a 400 only through D25's handler. If trunk's body puts the field error under another key, assert against trunk's actual shape (read `etqan/platform/exceptions.py` and its handler).

`test_routes.py`, under `# Slice B4a.` in `ROUTES`:

```python
    ("GET", "/api/v1/payroll/student-rates/", "payroll_rate.view_any"),
    ("POST", "/api/v1/payroll/student-rates/", "payroll_rate.create"),
    ("PATCH", f"/api/v1/payroll/student-rates/{N}/", "payroll_rate.update"),
    ("DELETE", f"/api/v1/payroll/student-rates/{N}/", "payroll_rate.delete"),
    ("POST", "/api/v1/payroll/rates/bulk/", "payroll_rate.create"),
    ("GET", "/api/v1/payroll/settings/", "payroll_settings.view"),
    ("PATCH", "/api/v1/payroll/settings/", "payroll_settings.update"),
```

Add `FEATURES` entries mapping the four student-rate keys to `student_teacher_rate`, the bulk key to `bulk_teacher_rates`, and the two settings keys to `payroll_rules`. Add the three `FEATURE_WORDS` entries from Global Constraints.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_api_pay_rules.py etqan/access/tests/test_routes.py`
Expected: FAIL with 404 on every route, and the route-table coverage test names the missing handlers.

- [ ] **Step 3: Serializers**

```python
class StudentRateQueryInput(serializers.Serializer):
    teacher = _id(required=False)
    student = _id(required=False)


class StudentRateCreateInput(serializers.Serializer):
    teacher = _id()
    student = _id()
    hourly_rate_minor = serializers.IntegerField(min_value=0)


class BulkRateInput(serializers.Serializer):
    course = _id(required=False, allow_null=True, default=None)
    hourly_rate_minor = serializers.IntegerField(min_value=0)


class BulkRatesInput(serializers.Serializer):
    teachers = serializers.ListField(child=_id(), min_length=1, max_length=200)
    rates = BulkRateInput(many=True)


class SettingsInput(serializers.Serializer):
    student_absent_pay_bp = serializers.IntegerField(
        min_value=0, max_value=10000, required=False
    )
    student_excused_pay_bp = serializers.IntegerField(
        min_value=0, max_value=10000, required=False
    )
    at_disposal_pays = serializers.BooleanField(required=False)
    group_pay = serializers.ChoiceField(
        choices=PayrollSettings.GroupPay.choices, required=False
    )
```

Use `RateUpdateInput` (trunk) for the student-rate PATCH.

- [ ] **Step 4: Payloads**

```python
def student_rate_row(rate) -> dict:
    return {
        "id": rate.pk,
        "teacher": person(rate.teacher.user),
        "student": person(rate.student.user),
        "hourly_rate_minor": rate.hourly_rate_minor,
        "currency": rate.currency,
        "current": rate.currency == rate.teacher.pay_currency,
        "created_at": rate.created_at,
        "updated_at": rate.updated_at,
    }


def settings_row(row) -> dict:
    return {
        "student_absent_pay_bp": row.student_absent_pay_bp,
        "student_excused_pay_bp": row.student_excused_pay_bp,
        "at_disposal_pays": row.at_disposal_pays,
        "group_pay": row.group_pay,
        "updated_at": row.updated_at,
        "updated_by": person(row.updated_by),
    }
```

- [ ] **Step 5: Views and urls**

```python
class AlsoUpdatesRates(BasePermission):
    """Slice B4a A-11 (plan R3): bulk assignment both creates and replaces
    rates, so staff also need `payroll_rate.update`; admins always pass."""

    def has_permission(self, request, view):
        role = role_of(request.user)
        return role == "admin" or (
            role == "staff" and "payroll_rate.update" in codes_of(request.user)
        )


class StudentRateListView(APIView):
    """Every student rate at once (not paged), like `rates/`."""

    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"GET": "payroll_rate.view_any", "POST": "payroll_rate.create"}
    feature = "student_teacher_rate"

    def get(self, request):
        query = StudentRateQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        rates = services.student_rates_queryset()
        if "teacher" in query.validated_data:
            rates = rates.filter(teacher__user_id=query.validated_data["teacher"])
        if "student" in query.validated_data:
            rates = rates.filter(student__user_id=query.validated_data["student"])
        return Response([payloads.student_rate_row(rate) for rate in rates])

    def post(self, request):
        body = StudentRateCreateInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        rate = services.create_student_rate(
            teacher_id=data["teacher"],
            student_id=data["student"],
            hourly_rate_minor=data["hourly_rate_minor"],
        )
        return Response(
            payloads.student_rate_row(student_rate_or_404(rate.pk)),
            status=status.HTTP_201_CREATED,
        )


def student_rate_or_404(pk):
    return get_object_or_404(services.student_rates_queryset(), pk=pk)


class StudentRateDetailView(APIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"PATCH": "payroll_rate.update", "DELETE": "payroll_rate.delete"}
    feature = "student_teacher_rate"

    def patch(self, request, pk):
        rate = student_rate_or_404(pk)
        body = RateUpdateInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.update_student_rate(rate, **body.validated_data)
        return Response(payloads.student_rate_row(student_rate_or_404(pk)))

    def delete(self, request, pk):
        services.delete_student_rate(student_rate_or_404(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class BulkRatesView(APIView):
    permission_classes = [HasCode, AlsoUpdatesRates, FeatureOn]
    permission_codes = {"POST": "payroll_rate.create"}
    feature = "bulk_teacher_rates"

    def post(self, request):
        body = BulkRatesInput(data=request.data)
        body.is_valid(raise_exception=True)
        result = services.assign_rates(
            teacher_ids=body.validated_data["teachers"],
            rates=[
                {"course_id": r["course"], "hourly_rate_minor": r["hourly_rate_minor"]}
                for r in body.validated_data["rates"]
            ],
        )
        return Response({"created": result.created, "updated": result.updated})


class SettingsView(APIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"GET": "payroll_settings.view", "PATCH": "payroll_settings.update"}
    feature = "payroll_rules"

    def get(self, request):
        return Response(payloads.settings_row(services.get_settings()))

    def patch(self, request):
        body = SettingsInput(data=request.data)
        body.is_valid(raise_exception=True)
        row = services.update_settings(by=request.user, **body.validated_data)
        return Response(payloads.settings_row(row))
```

`urls.py` gains the routes below. `rates/bulk/` goes **before** `rates/<int:pk>/`, which cannot match it anyway since `bulk` is not an int; keep it next to the rates routes.

```python
    path("rates/bulk/", views.BulkRatesView.as_view(), name="rates-bulk"),
    path("student-rates/", views.StudentRateListView.as_view(), name="student-rates"),
    path(
        "student-rates/<int:pk>/",
        views.StudentRateDetailView.as_view(),
        name="student-rate",
    ),
    path("settings/", views.SettingsView.as_view(), name="settings"),
```

Import `BasePermission` from DRF, and `FeatureOn`, `codes_of` and `role_of` from `etqan.platform.permissions`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll etqan/access`
Expected: PASS. The registry test now sees `payroll_settings.view`/`.update` in use.

- [ ] **Step 7: Commit**

```bash
git -C $W/backend add etqan/payroll/api etqan/access/tests/test_routes.py etqan/payroll/tests/test_api_pay_rules.py
git -C $W/backend commit -m "feat(payroll): student-rate, bulk-rate and settings routes (B4a §8)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Demo seed

**Files:**
- Create: `backend/etqan/tenants/seeds/b4.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (under `# ── phase B4 ──`)
- Test: `backend/etqan/tenants/tests/test_seed_b4.py` (new). If trunk keeps seed tests elsewhere (`grep -rln "seed_b6" etqan/*/tests`), follow that place.

**Interfaces:**
- Consumes: `services.create_student_rate`, `services.student_rates_queryset` (Task 3).
- Produces: `seed_b4(subdomain: str) -> None`.

- [ ] **Step 1: Write the failing test**

```python
"""Slice B4a §10: the demo's student rate, made once."""

from etqan.payroll import services as payroll_services
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.tenants.seeds.b4 import seed_b4


def test_seed_b4_adds_one_student_rate_once(db, monkeypatch):
    teacher = make_teacher("Ustadh Bilal")
    student = make_student("Yusuf Omar")
    monkeypatch.setattr(
        "etqan.tenants.seeds.b4.PEOPLE", {"demo": ("Ustadh Bilal", "Yusuf Omar")}
    )
    seed_b4("demo")
    seed_b4("demo")
    (rate,) = payroll_services.student_rates_queryset()
    assert (rate.teacher.user_id, rate.student.user_id) == (teacher.id, student.id)


def test_seed_b4_skips_other_academies(db):
    seed_b4("other")
    assert not payroll_services.student_rates_queryset().exists()
```

Read how `seed_b6` finds people by name (`identity_services.find_person` or `seed_dev._person`) and use the same lookup. `seed_dev._person` is private to the command, so the seed module must use the identity service that `_person` wraps.

- [ ] **Step 2: Run the test to verify it fails**

Run: `… exec -T django pytest -q etqan/tenants/tests/test_seed_b4.py`
Expected: FAIL with ModuleNotFoundError.

- [ ] **Step 3: Implement**

```python
"""Phase B4 demo data (slice B4a): one per-student rate, so the Rates page's
per-student section has a row once `student_teacher_rate` is switched on.
Demo academy only; idempotent; switches stay off."""

from etqan.payroll import services as payroll_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

PEOPLE = {"demo": ("Ustadh Bilal", "Yusuf Omar")}
RATE = 1500  # minor units of the teacher's pay currency


def seed_b4(subdomain: str) -> None:
    people = PEOPLE.get(subdomain)
    if people is None or payroll_services.student_rates_queryset().exists():
        return
    teacher, student = (_user(role, name) for role, name in zip(
        ("teacher", "student"), people, strict=True))
    if teacher is None or student is None:
        print("skip: B4 student rate — seeded people not found")  # noqa: T201
        return
    try:
        payroll_services.create_student_rate(
            teacher_id=teacher.id, student_id=student.id, hourly_rate_minor=RATE
        )
    except (ValidationError, ConflictError) as exc:
        print(f"skip: B4 student rate — {exc}")  # noqa: T201
```

`_user(role, name)` is the identity lookup from Step 1's note, written as a two-line local helper. In `seed_dev.py`, under `# ── phase B4 ──`, add `seed_b4(subdomain)`. Import it beside `seed_b6`'s import, in alphabetical order.

- [ ] **Step 4: Run the test, then seed the stack twice**

Run: `… exec -T django pytest -q etqan/tenants/tests/test_seed_b4.py`, then `just _stack-manage seed_dev` twice.
Expected: PASS, and the second seed run reports nothing new for B4.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/tenants/seeds/b4.py etqan/tenants/management/commands/seed_dev.py etqan/tenants/tests/test_seed_b4.py
git -C $W/backend commit -m "feat(seeds): B4a demo student rate

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Dashboard foundations — types, API, hooks, fixtures, strings, switches

**Files:**
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode`: `student_teacher_rate`, `payroll_rules`, `bulk_teacher_rates` under a `// Phase B4, slice B4a.` comment)
- Modify: `dashboard/src/features/payroll/schemas.ts`
- Modify: `dashboard/src/features/payroll/api.ts`, `api.test.ts`
- Modify: `dashboard/src/features/payroll/queries.ts`
- Modify: `dashboard/src/test/payroll-fixtures.ts`
- Modify: `dashboard/src/locales/{en,ar}/payroll.json`, `errors.json` (the `payroll` section), `nav.json`

**Interfaces:**
- Produces:
  - TS types `StudentRate`, `PayrollSettings`, `GroupPay = "per_student" | "per_class"`, `PayslipCounts`;
  - `Payslip.counts: PayslipCounts | null`;
  - `PayslipLine` fields `session_kind`, `session_status`, `student_attendance`, `pay_bp`, `group_key`, `group_role`;
  - `payrollApi.studentRates(params)`, `createStudentRate(body)`, `updateStudentRate({id, hourly_rate_minor})`, `deleteStudentRate(id)`, `bulkRates(body)`, `settings()`, `updateSettings(patch)`;
  - hooks `useStudentRates({enabled})`, `usePayrollSettings({enabled})`;
  - fixtures `studentRateRow(o)` and `settingsRow(o)`.

- [ ] **Step 1: Write the failing tests**

Append to `api.test.ts`, following the file's existing pattern of mocking `api` and asserting the URL and body:

```ts
it("calls the B4a routes", async () => {
	vi.mocked(api.get).mockResolvedValue({ data: [] });
	vi.mocked(api.post).mockResolvedValue({ data: { created: 1, updated: 0 } });
	vi.mocked(api.patch).mockResolvedValue({ data: {} });
	await payrollApi.studentRates({ teacher: 21 });
	expect(api.get).toHaveBeenCalledWith("payroll/student-rates/", {
		params: { teacher: 21 },
	});
	await payrollApi.bulkRates({
		teachers: [21, 22],
		rates: [{ course: null, hourly_rate_minor: 1000 }],
	});
	expect(api.post).toHaveBeenCalledWith("payroll/rates/bulk/", {
		teachers: [21, 22],
		rates: [{ course: null, hourly_rate_minor: 1000 }],
	});
	await payrollApi.updateSettings({ group_pay: "per_class" });
	expect(api.patch).toHaveBeenCalledWith("payroll/settings/", {
		group_pay: "per_class",
	});
	await payrollApi.updateStudentRate({ id: 5, hourly_rate_minor: 900 });
	expect(api.patch).toHaveBeenCalledWith("payroll/student-rates/5/", {
		hourly_rate_minor: 900,
	});
});
```

Read the top of `api.test.ts` for how it mocks `@/lib/api`, and match it exactly.

- [ ] **Step 2: Run the test to verify it fails**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll/api.test.ts`
Expected: FAIL with `payrollApi.studentRates is not a function`.

- [ ] **Step 3: Implement**

In `schemas.ts`:

```ts
export const GROUP_PAY = ["per_student", "per_class"] as const;
export type GroupPay = (typeof GROUP_PAY)[number];

/** Slice B4a A-1: a teacher's hourly rate for one student. `current` is
 * false for a rate left in a currency the teacher is no longer paid in. */
export interface StudentRate {
	id: number;
	teacher: Person;
	student: Person;
	hourly_rate_minor: number;
	currency: string;
	current: boolean;
	created_at: string;
	updated_at: string;
}

/** Slice B4a A-3: weights are basis points (10000 = 100 %). */
export interface PayrollSettings {
	student_absent_pay_bp: number;
	student_excused_pay_bp: number;
	at_disposal_pays: boolean;
	group_pay: GroupPay;
	updated_at: string;
	updated_by: Person | null;
}

export const COUNT_KEYS = [
	"regular",
	"compensation",
	"extra",
	"trial",
	"at_disposal",
	"student_absent",
	"student_excused",
	"group_members",
] as const;
export type PayslipCounts = Record<(typeof COUNT_KEYS)[number], number>;

export interface BulkRatesBody {
	teachers: number[];
	rates: { course: number | null; hourly_rate_minor: number }[];
}
```

`Payslip` gains `counts: PayslipCounts | null;`. `PayslipLine` gains:

```ts
	// Slice B4a A-7: empty on lines written before B4a.
	session_kind: "" | "regular" | "compensation" | "extra" | "trial";
	session_status: "" | "completed" | "at_disposal";
	student_attendance: "" | "present" | "absent" | "excused" | "not_set";
	pay_bp: number | null;
	group_key: string;
	group_role: "" | "carrier" | "member";
```

`api.ts` gains:

```ts
	studentRates: async (params: QueryParams = {}) =>
		(
			await api.get<StudentRate[]>(`${P}student-rates/`, {
				params: clean(params),
			})
		).data,
	createStudentRate: async (body: {
		teacher: number;
		student: number;
		hourly_rate_minor: number;
	}) => (await api.post<StudentRate>(`${P}student-rates/`, body)).data,
	updateStudentRate: async ({
		id,
		...body
	}: {
		id: number;
		hourly_rate_minor: number;
	}) => (await api.patch<StudentRate>(`${P}student-rates/${id}/`, body)).data,
	deleteStudentRate: async (id: number) => {
		await api.delete(`${P}student-rates/${id}/`);
	},
	bulkRates: async (body: BulkRatesBody) =>
		(
			await api.post<{ created: number; updated: number }>(
				`${P}rates/bulk/`,
				body,
			)
		).data,
	settings: async () =>
		(await api.get<PayrollSettings>(`${P}settings/`)).data,
	updateSettings: async (patch: Partial<PayrollSettings>) =>
		(await api.patch<PayrollSettings>(`${P}settings/`, patch)).data,
```

`queries.ts`:

```ts
export function useStudentRates({ enabled = true }: { enabled?: boolean } = {}) {
	return useQuery({
		queryKey: [...payrollKey, "student-rates"],
		queryFn: () => payrollApi.studentRates(),
		enabled,
	});
}

export function usePayrollSettings({
	enabled = true,
}: { enabled?: boolean } = {}) {
	return useQuery({
		queryKey: [...payrollKey, "settings"],
		queryFn: () => payrollApi.settings(),
		enabled,
	});
}
```

In `payroll-fixtures.ts`:
- `payslipRow` gains `counts: null`.
- `lineRow` gains `session_kind: "regular"`, `session_status: "completed"`, `student_attendance: "present"`, `pay_bp: 10000`, `group_key: ""`, `group_role: ""`.
- Add `studentRateRow(o)` (id 91, teacher Bilal 21, student `{id: 31, full_name: "Yusuf"}`, 1500 USD, current true).
- Add `settingsRow(o)` (the defaults).

Add strings to `en/payroll.json` and `ar/payroll.json` with equal keys:

```json
"settings": {
	"title": "Payroll rules",
	"intro": "These rules apply to payslips generated or issued from now on. Issued payslips never change.",
	"absentWeight": "Pay for a session the student missed (%)",
	"absentHint": "Share of the rate paid when the student was absent and the teacher attended.",
	"excusedWeight": "Pay for a session the student was excused from (%)",
	"excusedHint": "Share of the rate paid when the student was excused and the teacher attended.",
	"atDisposal": "Pay sessions at the administration's disposal",
	"atDisposalHint": "Paid in full when the teacher attended or wasn't marked.",
	"groupPay": "Group classes",
	"perStudent": "Pay for each student in the class",
	"perClass": "Pay once per class",
	"perClassWarning": "Per class uses the course or default rate of the class's first row; a student taught by another teacher (a substitute) forms that teacher's own class.",
	"save": "Save rules",
	"saved": "Payroll rules saved.",
	"loadError": "The payroll rules couldn't be loaded."
},
"studentRates": {
	"title": "Per-student rates",
	"hint": "A per-student rate replaces the teacher's course and default rate for that student.",
	"add": "Add a student rate",
	"edit": "Edit the rate for {{student}}",
	"student": "Student",
	"none": "No per-student rates.",
	"delete": "Delete the rate for {{student}}",
	"deleteTitle": "Delete this student rate?",
	"deleteBody": "Issued payslips keep their rates.",
	"oldCurrency": "Old currency: not counted"
},
"bulk": {
	"open": "Assign to several teachers",
	"title": "Assign rates to several teachers",
	"currency": "Pay currency",
	"teachers": "Teachers",
	"addRow": "Add a course rate",
	"course": "Course",
	"defaultRate": "Default rate",
	"rate": "Rate per hour",
	"submit": "Assign",
	"done": "{{created}} rates created, {{updated}} updated."
},
"lines": {
	"absent": "Student absent",
	"excused": "Student excused",
	"atDisposal": "At disposal",
	"weight": "{{percent}} %",
	"member": "Group class — paid on the first line"
},
"kindsOfSession": {
	"regular": "Regular",
	"compensation": "Make-up",
	"extra": "Extra",
	"trial": "Trial"
},
"counts": {
	"show": "Show session counts",
	"regular": "Regular",
	"compensation": "Make-up",
	"extra": "Extra",
	"trial": "Trial",
	"at_disposal": "At disposal",
	"student_absent": "Student absent",
	"student_excused": "Student excused",
	"group_members": "Group members"
}
```

Arabic values, in the same keys:
- `settings`:
  - "قواعد الرواتب"
  - "تُطبَّق هذه القواعد على كشوف الرواتب التي تُنشأ أو تُصدر من الآن. لا تتغير الكشوف الصادرة."
  - "أجر حصة غاب عنها الطالب (٪)"
  - "نسبة الأجر عند غياب الطالب وحضور المعلم."
  - "أجر حصة اعتذر عنها الطالب (٪)"
  - "نسبة الأجر عند اعتذار الطالب وحضور المعلم."
  - "دفع الحصص تحت تصرف الإدارة"
  - "تُدفع كاملة إذا حضر المعلم أو لم يُسجَّل حضوره."
  - "الحصص الجماعية"
  - "الدفع عن كل طالب في الحصة"
  - "الدفع مرة واحدة لكل حصة"
  - "يستخدم الدفع لكل حصة أجر المادة أو الأجر الافتراضي لأول صف في الحصة؛ والطالب الذي يدرّسه معلم آخر (بديل) يكوّن حصة لذلك المعلم."
  - "حفظ القواعد"
  - "تم حفظ قواعد الرواتب."
  - "تعذر تحميل قواعد الرواتب."
- `studentRates`:
  - "أجور حسب الطالب"
  - "أجر الطالب يحل محل أجر المادة والأجر الافتراضي للمعلم مع هذا الطالب."
  - "إضافة أجر لطالب"
  - "تعديل أجر {{student}}"
  - "الطالب"
  - "لا توجد أجور حسب الطالب."
  - "حذف أجر {{student}}"
  - "حذف أجر هذا الطالب؟"
  - "تحتفظ الكشوف الصادرة بأجورها."
  - "عملة قديمة: لا تُحتسب"
- `bulk`:
  - "تعيين لعدة معلمين"
  - "تعيين الأجور لعدة معلمين"
  - "عملة الراتب"
  - "المعلمون"
  - "إضافة أجر مادة"
  - "المادة"
  - "الأجر الافتراضي"
  - "الأجر بالساعة"
  - "تعيين"
  - "تم إنشاء {{created}} وتحديث {{updated}} من الأجور."
- `lines`:
  - "الطالب غائب"
  - "الطالب معتذر"
  - "تحت تصرف الإدارة"
  - "{{percent}} ٪"
  - "حصة جماعية — مدفوعة في السطر الأول"
- `kindsOfSession`: "عادية", "تعويضية", "إضافية", "تجريبية".
- `counts`:
  - "إظهار أعداد الحصص"
  - "عادية"
  - "تعويضية"
  - "إضافية"
  - "تجريبية"
  - "تحت تصرف الإدارة"
  - "غياب الطالب"
  - "اعتذار الطالب"
  - "أعضاء المجموعة"

In `errors.json`, the `payroll` section gains:
- en:
  - `"mixed_currencies": "These teachers are paid in different currencies. Choose teachers of one currency."`
  - `"rate_exists": "This rate already exists. Edit it instead."`
- ar:
  - `"mixed_currencies": "هؤلاء المعلمون يتقاضون بعملات مختلفة. اختر معلمين بعملة واحدة."`
  - `"rate_exists": "هذا الأجر موجود بالفعل. عدّله بدلًا من ذلك."`

`nav.json` gains `"payrollSettings": "Payroll rules"` / `"قواعد الرواتب"`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll src/locales`, then `… exec -T dashboard pnpm exec tsc --noEmit`
Expected: PASS. The ar/en key-equality test passes.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/identity/schemas.ts src/features/payroll src/test/payroll-fixtures.ts src/locales
git -C $W/dashboard commit -m "feat(payroll): B4a types, API, hooks, fixtures and strings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: The payroll settings page

**Files:**
- Create: `dashboard/src/features/payroll/SettingsPage.tsx`, `SettingsPage.test.tsx`
- Create: `dashboard/src/routes/_authed/payroll.settings.tsx`
- Modify: `dashboard/src/features/payroll/index.ts`
- Modify: `dashboard/src/features/shell/nav.ts` (under `// ── phase B4 ──`)
- Modify: `dashboard/src/routes/permissions.test.ts`
- Generated: `dashboard/src/routeTree.gen.ts`

**Interfaces:**
- Consumes: `usePayrollSettings` and `payrollApi.updateSettings` (Task 10); `useCan` and `usePayrollMutation` (trunk).
- Produces: `SettingsPage` and the route `/payroll/settings` (`staticData: { permission: "payroll_settings.view", feature: "payroll_rules" }`).

- [ ] **Step 1: Write the failing test**

`SettingsPage.test.tsx`, with the same mocking pattern as `RatesPage.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { settingsRow } from "@/test/payroll-fixtures";
import { renderWithRouter } from "@/test/render";
import { payrollApi } from "./api";
import { SettingsPage } from "./SettingsPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		payrollApi: {
			...actual.payrollApi,
			settings: vi.fn(),
			updateSettings: vi.fn(),
		},
	};
});

describe("SettingsPage", () => {
	afterEach(async () => {
		await i18n.changeLanguage("en");
	});
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(payrollApi.settings).mockResolvedValue(settingsRow());
		vi.mocked(payrollApi.updateSettings).mockResolvedValue(
			settingsRow({ student_absent_pay_bp: 5000, group_pay: "per_class" }),
		);
	});

	it("shows the weights as percentages and saves basis points", async () => {
		renderWithRouter(<SettingsPage />);
		const absent = await screen.findByLabelText(/student missed/i);
		expect(absent).toHaveValue(100);
		await userEvent.clear(absent);
		await userEvent.type(absent, "50");
		await userEvent.click(screen.getByLabelText(/pay once per class/i));
		expect(screen.getByText(/substitute/i)).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: /save rules/i }));
		await waitFor(() =>
			expect(payrollApi.updateSettings).toHaveBeenCalledWith({
				student_absent_pay_bp: 5000,
				student_excused_pay_bp: 10000,
				at_disposal_pays: false,
				group_pay: "per_class",
			}),
		);
	});

	it("refuses a percentage over 100", async () => {
		renderWithRouter(<SettingsPage />);
		const excused = await screen.findByLabelText(/student was excused/i);
		await userEvent.clear(excused);
		await userEvent.type(excused, "101");
		await userEvent.click(screen.getByRole("button", { name: /save rules/i }));
		expect(await screen.findByRole("alert")).toBeInTheDocument();
		expect(payrollApi.updateSettings).not.toHaveBeenCalled();
	});

	it("is read-only without payroll_settings.update", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("payroll_settings.view")}>
				<SettingsPage />
			</CanProvider>,
		);
		expect(await screen.findByLabelText(/student missed/i)).toBeDisabled();
		expect(screen.getByLabelText(/pay once per class/i)).toBeDisabled();
		expect(screen.queryByRole("button", { name: /save rules/i })).toBeNull();
	});

	it("renders in Arabic", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(<SettingsPage />);
		expect(await screen.findByText("قواعد الرواتب")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll/SettingsPage.test.tsx`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `SettingsPage.tsx`**

Write a react-hook-form + zod form like `AdjustmentDialog.tsx`'s form (read it for the project's `Form`, `FormField` and `Input` components and how server errors map, `applyServerErrors` or equivalent).
- **Schema:** two `z.coerce.number().int().min(0).max(100)` percentages, a boolean, and `z.enum(GROUP_PAY)`.
- **Defaults:** from `usePayrollSettings()`, with `bp / 100`.
- **Submit:** `percent * 100` per weight, through `usePayrollMutation(payrollApi.updateSettings)`. Show the `payroll.settings.saved` toast on success, and translated errors with `errorText` on failure.
- **Group pay:** a radio group (`<fieldset>` + `<legend>`). `perClassWarning` is shown while `per_class` is selected.
- **Read-only:** without `can("payroll_settings.update")`, every input is disabled and there is no Save button.
- **States:** a loading `Spinner`, and an error `Alert` with `payroll.settings.loadError`.
- **Layout:** semantic tokens only, a `Card` per group of fields, phone width (`flex-col` stacks).

Route `payroll.settings.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SettingsPage } from "@/features/payroll";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/payroll/settings")({
	staticData: { permission: "payroll_settings.view", feature: "payroll_rules" },
	component: function PayrollSettingsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.payrollSettings"));
		return (
			<>
				<PageHeader title={t("nav.payrollSettings")} />
				<SettingsPage />
			</>
		);
	},
});
```

`nav.ts`, under `// ── phase B4 ──`:

```ts
	// ── phase B4 ──
	// Slice B4a: the academy's pay rules.
	office(
		"/payroll/settings",
		"nav.payrollSettings",
		SlidersHorizontal,
		"payroll",
		"payroll_settings.view",
		"payroll_rules",
	),
```

Import `SlidersHorizontal` from `lucide-react`. If the nav test pins icon uniqueness or order, follow its rule.

In `permissions.test.ts`, add `"/_authed/payroll/settings": "payroll_rules"` under a `// Slice B4a` comment, and insert `payroll\/settings|` into `FEATURE_WORDS`.

- [ ] **Step 4: Regenerate the route tree, run the tests**

Run: `… exec -T dashboard pnpm exec vite build`, then `… exec -T dashboard pnpm exec vitest run src/features/payroll src/routes src/features/shell`, then `tsc --noEmit`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/payroll src/routes src/features/shell/nav.ts src/routeTree.gen.ts
git -C $W/dashboard commit -m "feat(payroll): payroll rules settings page (B4a §9)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Per-student rates and the bulk dialog on the Rates page

**Files:**
- Create: `dashboard/src/features/payroll/StudentRates.tsx`, `StudentRates.test.tsx`
- Create: `dashboard/src/features/payroll/StudentRateDialog.tsx`
- Create: `dashboard/src/features/payroll/BulkRatesDialog.tsx`, `BulkRatesDialog.test.tsx`
- Modify: `dashboard/src/features/payroll/RatesPage.tsx`, `RatesPage.test.tsx`

**Interfaces:**
- Consumes:
  - `useStudentRates`, `payrollApi.createStudentRate`/`updateStudentRate`/`deleteStudentRate`/`bulkRates` (Task 10);
  - `useHasFeature` (`@/features/identity/permissions`), `useCan`, `usePeople` (trunk).
- Produces:
  - `<StudentRates />`, shown on the Rates page while `student_teacher_rate` is on;
  - `<BulkRatesDialog teachers courses />`, a header action shown while `bulk_teacher_rates` is on and the viewer can both create and update rates.

- [ ] **Step 1: Write the failing tests**

`StudentRates.test.tsx` (mock `payrollApi.studentRates`, `createStudentRate`, `deleteStudentRate` and `peopleApi.list` as `RatesPage.test.tsx` does):

```tsx
it("lists rates grouped by teacher and marks an old currency", async () => {
	vi.mocked(payrollApi.studentRates).mockResolvedValue([
		studentRateRow(),
		studentRateRow({
			id: 92,
			student: { id: 32, full_name: "Zaid" },
			currency: "EGP",
			current: false,
		}),
	]);
	renderWithRouter(<StudentRates />);
	expect(await screen.findByText("Yusuf")).toBeInTheDocument();
	expect(screen.getByText(/old currency/i)).toBeInTheDocument();
});

async function addRate() {
	renderWithRouter(<StudentRates teachers={[teacher(21, "Bilal")]} />);
	await userEvent.click(
		await screen.findByRole("button", { name: /add a student rate/i }),
	);
	const dialog = await screen.findByRole("dialog");
	await userEvent.selectOptions(within(dialog).getByLabelText(/^teacher/i), "21");
	await userEvent.selectOptions(within(dialog).getByLabelText(/^student/i), "31");
	await userEvent.type(within(dialog).getByLabelText(/rate per hour/i), "15");
	await userEvent.click(within(dialog).getByRole("button", { name: /save/i }));
}

it("adds a rate for an active student", async () => {
	vi.mocked(payrollApi.studentRates).mockResolvedValue([]);
	vi.mocked(peopleApi.list).mockResolvedValue(
		page([{ id: 31, user: { full_name: "Yusuf" }, profile: {} }]) as never,
	);
	vi.mocked(payrollApi.createStudentRate).mockResolvedValue(studentRateRow());
	await addRate();
	await waitFor(() =>
		expect(payrollApi.createStudentRate).toHaveBeenCalledWith({
			teacher: 21,
			student: 31,
			hourly_rate_minor: 1500,
		}),
	);
});

it("shows a 409 rate_exists translated", async () => {
	vi.mocked(payrollApi.studentRates).mockResolvedValue([]);
	vi.mocked(peopleApi.list).mockResolvedValue(
		page([{ id: 31, user: { full_name: "Yusuf" }, profile: {} }]) as never,
	);
	vi.mocked(payrollApi.createStudentRate).mockRejectedValue(
		new AxiosError("Conflict", "409", undefined, undefined, {
			status: 409,
			data: { code: "payroll.rate_exists", detail: "exists" },
		} as never),
	);
	await addRate();
	expect(
		await screen.findByText("This rate already exists. Edit it instead."),
	).toBeInTheDocument();
});
```

Both new test files import `screen`, `waitFor` and `within` from `@testing-library/react`, `userEvent`, `AxiosError` from `axios`, and `studentRateRow` from `@/test/payroll-fixtures`. The `teacher(id, name, currency)` helper, `TAJWEED`, the `page()` fixture and the people mock are copied from `RatesPage.test.tsx`. The money input converts with the currency's minor units the way `RateDialog` does, so `15` USD becomes `1500`. Check the people row shape `usePeople("students")` returns in trunk and match it in the mock.

`BulkRatesDialog.test.tsx`:

```tsx
it("offers only teachers of the chosen currency and sends one batch", async () => {
	renderWithRouter(
		<BulkRatesDialog
			teachers={[teacher(21, "Bilal"), teacher(22, "Maryam", "EGP"), teacher(23, "Hamza")]}
			courses={[TAJWEED]}
		/>,
	);
	await userEvent.click(await screen.findByRole("button", { name: /assign to several/i }));
	await userEvent.selectOptions(screen.getByLabelText(/pay currency/i), "USD");
	expect(screen.queryByLabelText("Maryam")).toBeNull();
	await userEvent.click(screen.getByLabelText("Bilal"));
	await userEvent.click(screen.getByLabelText("Hamza"));
	await userEvent.type(screen.getByLabelText(/default rate/i), "10");
	await userEvent.click(screen.getByRole("button", { name: /^assign$/i }));
	await waitFor(() =>
		expect(payrollApi.bulkRates).toHaveBeenCalledWith({
			teachers: [21, 23],
			rates: [{ course: null, hourly_rate_minor: 1000 }],
		}),
	);
	expect(await screen.findByText(/1 rates created, 0 updated/i)).toBeInTheDocument();
});

it("shows mixed_currencies translated", async () => {
	vi.mocked(payrollApi.bulkRates).mockRejectedValue(
		new AxiosError("Bad", "400", undefined, undefined, {
			status: 400,
			data: { code: "payroll.mixed_currencies", teachers: ["mixed"] },
		} as never),
	);
	renderWithRouter(
		<BulkRatesDialog teachers={[teacher(21, "Bilal")]} courses={[TAJWEED]} />,
	);
	await userEvent.click(
		await screen.findByRole("button", { name: /assign to several/i }),
	);
	await userEvent.selectOptions(screen.getByLabelText(/pay currency/i), "USD");
	await userEvent.click(screen.getByLabelText("Bilal"));
	await userEvent.type(screen.getByLabelText(/default rate/i), "10");
	await userEvent.click(screen.getByRole("button", { name: /^assign$/i }));
	expect(
		await screen.findByText(/paid in different currencies/i),
	).toBeInTheDocument();
});
```

Read D25's error body shape in `etqan/platform/exceptions.py` (how a 400 with a `code` serialises) and match it in the mock if it differs from `{code, <field>: [...]}`.

In `RatesPage.test.tsx`, add:
- with `student_teacher_rate` off (the `CanProvider` fixture's features), neither the student-rates section nor its query is shown;
- with `bulk_teacher_rates` on and a staff user holding only `payroll_rate.create`, the bulk button is hidden.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll`
Expected: FAIL (modules not found).

- [ ] **Step 3: Implement**

- `StudentRateDialog.tsx`:
  - Copy `RateDialog.tsx`'s structure: a money input in the teacher's currency, and add vs edit.
  - The teacher select lists the roster passed in.
  - The student select uses `usePeople("students", { status: "active", page_size: 100 })`. Read the students list filters in `@/features/people` for the trunk status param.
  - On edit, only the rate is editable.
- `StudentRates.tsx`:
  - A `Card` titled `payroll.studentRates.title` with the hint.
  - The rates are grouped by teacher, as a list of student, money, an old-currency chip, and edit / delete (`Confirm`) gated by `can(...)`.
  - It has empty and error states.
- `BulkRatesDialog.tsx`:
  - The steps: currency select (from the teachers' currencies), teacher checkboxes of that currency (`<fieldset>` + `<legend>`), a default-rate money input (optional), and "Add a course rate" rows (course select + money).
  - Submit is disabled until at least one teacher and one rate are set.
  - On success, show the `bulk.done` toast and close.
  - A 400/409 is shown through `errorText`, with a field error on teachers or rates (D25 code).
- `RatesPage.tsx`:
  - `const has = useHasFeature();`
  - The header shows `{has("bulk_teacher_rates") && can("payroll_rate.create") && can("payroll_rate.update") ? <BulkRatesDialog …/> : null}` above the roster, using the `listTeachers` roster.
  - `{has("student_teacher_rate") ? <StudentRates teachers={roster} /> : null}` goes below.
  - `useStudentRates({ enabled: has("student_teacher_rate") })` lives inside `StudentRates`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll`, then `tsc --noEmit`, then `pnpm lint`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/payroll
git -C $W/dashboard commit -m "feat(payroll): per-student rates and bulk assignment on the Rates page (B4a §9)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Payslip line badges and the counters toggle

**Files:**
- Modify: `dashboard/src/features/payroll/PayslipBody.tsx`, `PayslipPage.test.tsx`, `PayslipPrint.test.tsx`
- Modify: `dashboard/src/features/payroll/PayslipsList.tsx`, `PayslipsList.test.tsx`

**Interfaces:**
- Consumes: the `PayslipLine` and `Payslip.counts` types (Task 10).
- Produces: badges on session lines; the "Show session counts" toggle (plan R7).

- [ ] **Step 1: Write the failing tests**

In `PayslipPage.test.tsx`:

```tsx
it("marks each session line's class, weight and group role", async () => {
	vi.mocked(payrollApi.payslip).mockResolvedValue(
		payslipDetail({
			lines: [
				lineRow({ student_attendance: "absent", pay_bp: 5000, amount_minor: 375 }),
				lineRow({ id: 83, session_status: "at_disposal", student_attendance: "not_set" }),
				lineRow({ id: 84, session_kind: "extra" }),
				lineRow({ id: 85, group_role: "member", rate_minor: null, amount_minor: 0 }),
			],
		}),
	);
	renderPage(); // the file's existing helper
	expect(await screen.findByText("Student absent")).toBeInTheDocument();
	expect(screen.getByText("50 %")).toBeInTheDocument();
	expect(screen.getByText("At disposal")).toBeInTheDocument();
	expect(screen.getByText("Extra")).toBeInTheDocument();
	expect(screen.getByText(/paid on the first line/i)).toBeInTheDocument();
	expect(screen.queryByText("100 %")).toBeNull();
	expect(screen.queryByText("Regular")).toBeNull();
});
```

A `regular` kind and full weight show nothing, so legacy lines (empty fields) show nothing either. Add one more case: a legacy line, `lineRow({ session_kind: "", pay_bp: null, student_attendance: "" })`, shows no badge.

`PayslipPrint.test.tsx`: assert that the absent badge prints too, because the print sheet uses `PayslipBody`.

`PayslipsList.test.tsx`:

```tsx
it("adds the counter columns behind one toggle and remembers it", async () => {
	vi.mocked(payrollApi.payslips).mockResolvedValue(
		page([
			payslipRow({
				counts: {
					regular: 3, compensation: 1, extra: 0, trial: 0, at_disposal: 0,
					student_absent: 1, student_excused: 0, group_members: 2,
				},
			}),
			payslipRow({ id: 72, counts: null }),
		]) as never,
	);
	renderList(); // the file's existing helper
	await screen.findByText("PAY-000071");
	expect(screen.queryByRole("columnheader", { name: "Group members" })).toBeNull();
	await userEvent.click(screen.getByLabelText(/show session counts/i));
	expect(screen.getByRole("columnheader", { name: "Group members" })).toBeInTheDocument();
	expect(screen.getAllByText("—").length).toBeGreaterThan(0); // null counts
	expect(localStorage.getItem("etqan.payroll.showCounts")).toBe("1");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `PayslipBody.tsx`, under the description cell, add a `LineBadges` component (local to the file):

```tsx
function LineBadges({ line }: { line: PayslipLine }) {
	const { t } = useTranslation();
	const badges: string[] = [];
	if (line.session_status === "at_disposal") badges.push(t("payroll.lines.atDisposal"));
	if (line.session_kind && line.session_kind !== "regular")
		badges.push(t(`payroll.kindsOfSession.${line.session_kind}`));
	if (line.student_attendance === "absent") badges.push(t("payroll.lines.absent"));
	if (line.student_attendance === "excused") badges.push(t("payroll.lines.excused"));
	if (line.pay_bp !== null && line.pay_bp < 10000)
		badges.push(t("payroll.lines.weight", { percent: line.pay_bp / 100 }));
	if (line.group_role === "member") badges.push(t("payroll.lines.member"));
	if (badges.length === 0) return null;
	return (
		<span className="mt-1 flex flex-wrap gap-1">
			{badges.map((badge) => (
				<StatusChip key={badge} tone="neutral">
					{badge}
				</StatusChip>
			))}
		</span>
	);
}
```

Check `StatusChip`'s `tone` values in `@/ui` and use the neutral one trunk has. A member line's rate cell shows "—", not `payroll.payslip.noRate`, because a member is not a missing rate: `line.group_role === "member" ? "—" : …`.

In `PayslipsList.tsx`:
- Add a checkbox (`<label><input type="checkbox"/>…</label>` with trunk's `Checkbox` if `@/ui` has one).
- Its state is initialised from `localStorage` inside try/catch, and every write is wrapped in try/catch too.
- When on, append one `<th>` per `COUNT_KEYS` with `t(\`payroll.counts.${key}\`)`, and per row `payslip.counts?.[key] ?? "—"`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll`, `tsc --noEmit`, `pnpm lint`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/payroll
git -C $W/dashboard commit -m "feat(payroll): session class badges on payslips and the counts toggle (B4a §9)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: End-to-end through Caddy, and the slice gates

**Files:**
- Create: `dashboard/e2e/b4-pay-rules.spec.ts`

**Interfaces:**
- Consumes: `login`, `DEMO_URL`, `DEMO_ADMIN`, `expectLoggedIn`, `postAsAdmin` (`e2e/fixtures.ts`); `manage` (`e2e/manage.ts`).

- [ ] **Step 1: Write the E2E**

The bodies below are taken from the trunk serializers (plan R8).

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login, postAsAdmin } from "./fixtures";
import { manage } from "./manage";

/** The 15th of last month (UTC, the demo academy's clock): always over, never a
 * month's edge. Also its year and month for the generate picker. */
function lastMonthMid() {
	const now = new Date();
	const first = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 15));
	return {
		day: first.toISOString().slice(0, 10),
		year: first.getUTCFullYear(),
		month: first.getUTCMonth() + 1,
	};
}

test.afterAll(() => {
	manage("set_features", "demo", "--off", "payroll_rules");
});

// Spec §11: with payroll_rules on and the student-absent weight at 50 %, a
// teacher's absent-student session last month is paid at half rate. The test
// owns its teacher, course and student (stamped), so the seeds' payslips and
// re-runs never meet it.
test("payroll rules pay an absent-student session at the chosen weight", async ({ page }) => {
	test.setTimeout(90_000);
	const stamp = Date.now();
	const { day, year, month } = lastMonthMid();
	for (const code of ["payroll_rules", "extra_sessions"])
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
		user: { full_name: `E2E Weighted ${stamp}`, email: `e2e-weighted-${stamp}@e2e.test` },
		profile: { gender: "male" },
	});
	const course = await created("catalogue/courses/", {
		name_ar: `وزن ${stamp}`,
		name_en: `E2E Weights ${stamp}`,
		teacher_ids: [teacher.id],
	});
	const student = await created("people/students/", {
		user: { full_name: `E2E Absentee ${stamp}`, email: `e2e-absentee-${stamp}@e2e.test` },
	});
	const extra = await created("sessions/extra/", {
		student: student.id,
		course: course.id,
		teacher: teacher.id,
		occurs_on: day,
		start_time: "12:00",
		minutes: 60,
	});
	await created(`sessions/${extra.session.id}/attendance/`, {
		student_attendance: "absent",
		teacher_attendance: "present",
	});
	await created("payroll/rates/", { teacher: teacher.id, hourly_rate_minor: 2000 });

	// The rule: half pay for a session the student missed
	await page.goto(`${DEMO_URL}/app/payroll/settings`);
	const absent = page.getByLabel(/student missed/i);
	await absent.fill("50");
	await page.getByRole("button", { name: /save rules/i }).click();
	await expect(page.getByText(/payroll rules saved/i)).toBeVisible();

	// Generate last month and open the teacher's payslip
	await created("payroll/payslips/generate/", { year, month });
	await page.goto(`${DEMO_URL}/app/payroll/payslips?year=${year}&month=${month}`);
	await page
		.getByRole("row", { name: new RegExp(`E2E Weighted ${stamp}`) })
		.getByRole("link")
		.click();
	await expect(page).toHaveURL(/\/app\/payroll\/payslips\/\d+$/);
	await expect(page.getByText("Student absent")).toBeVisible();
	await expect(page.getByText("50 %")).toBeVisible();
	// 20.00/h x 60 min x 50 % = 10.00
	await expect(page.getByRole("cell", { name: /10\.00/ }).first()).toBeVisible();
});
```

- The payslips list reads its month from the URL search params if trunk supports them. If it does not, pick the
  month with the page's month picker, as `e2e/payroll.spec.ts` does.
- The teacher create body is `{user, profile}` (`PersonWriteSerializer`), and its row's `id` is the User id.
- The extra session's 201 body is `{session, conflicts}` (B2a §8).

- [ ] **Step 2: Run the E2E**

Run: `just e2e e2e/b4-pay-rules.spec.ts`
Expected: PASS. If it fails, debug with `superpowers:systematic-debugging` and never weaken an assertion.

- [ ] **Step 3: The slice gates**

Run: `just test`, `just lint`, `just e2e`
Expected: all green, coverage gates met. Keep the outputs for the final review.

- [ ] **Step 4: Commit**

```bash
git -C $W/dashboard add e2e/b4-pay-rules.spec.ts
git -C $W/dashboard commit -m "test(e2e): B4a payroll rules weight an absent-student session

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Spec coverage

| Spec item | Task |
|---|---|
| A-1 per-student rate, precedence, old currency | 1, 3, 4 |
| A-2 bulk assignment, mixed currencies, race, other rates untouched | 6, 8, 12 |
| A-3 settings row, migration, `effective_settings` read once | 1, 2, 4 |
| A-4 weights by student attendance | 2, 4 |
| A-5 at-disposal pay | 2, 4 |
| A-6 group class, carrier and members, late-row rule, substitutes | 5 (and the substitute warning in 10/11) |
| A-7 descriptive columns, `group_key` format | 1, 4, 7 |
| A-8 counters, legacy `null`, member lines out of sessions/minutes, CSV | 7, 13 |
| A-9 trial/extra same rules | 4 (extra in `every_class`); trial follows the same code path |
| A-10 missing rate ignores members | 5 |
| A-11 access, two codes for bulk, `payroll_settings` | 1, 8, 12 |
| A-12 switches and their gates | 1, 8, 11, 12 |
| B4-2 regression with switches off | 4 |
| §9 screens | 11, 12, 13 |
| §10 seed | 9 |
| §11 E2E | 14 |
