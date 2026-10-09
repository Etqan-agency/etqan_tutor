# Plan 54 — Percentage incentives, report deductions, fixed salary (slice B4b) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B4a (Plan 46).
**Slice:** B4b · **Phase spec:** `docs/superpowers/specs/2026-10-08-b4-payroll-depth-design.md` (§1–§4) · **Slice spec:** `docs/superpowers/specs/2026-10-08-b4b-incentives-reports-fixed-design.md`

**Goal:** A bonus can be a percentage of the month's gross; a paid session still without its report loses a share of its pay; a teacher can be paid a fixed monthly salary instead of per session; and every payslip stores three counters (reports sent, reports not sent, teacher absences). Three switches are flipped in place, all off by default, and with them off every payslip pays exactly what B4a pays.

**Architecture:**
- **Data** (spec §3). `PayAdjustment.amount_minor` becomes nullable and gains `percent_bp`, with one check constraint for the two forms. `PayrollSettings` gains `report_deduction_bp`. A new `FixedSalary` model (one per teacher). `Payslip` gains three nullable counters, and `PayslipLine.Kind` gains `report` and `fixed`. One migration, next after trunk's payroll leaf. It rewrites no data.
- **Rules.**
  - `services/settings.py`: `PaySettings` gains `report_deduction_bp`, `percentages`, `fixed_salary` and `session_reports`, all filled once by `effective_settings()` (S-1).
  - `rules.py` gains `UNSET`, `percent_text`, `adjustment_amount`, `counting_fixed_salaries`, `stale_fixed_salaries`, `counting_fixed_salary`, `REPORT_OWED` and `TEACHER_AWAY`. `pending_adjustments` and `other_currency_adjustments` take `percentages=`.
  - `build.py` follows spec §4.1: session lines → `regroup` → the fixed line (zeroing the session lines) → gross → adjustment lines (fixed and percentage) → report lines → totals → `missing_rate` → counters.
  - `payslips.py` discovers fixed-salary teachers (F-3), names stale ones (`stale_fixed_salary`), skips late rows of a fixed-salary month (F-4), and copies the counters.
- **Services.** `services/fixed_salaries.py` holds the fixed-salary CRUD. `services/adjustments.py` gains `percent_bp`, the form rule and the `UNSET` sentinel.
- **API.** New routes `fixed-salaries/` (feature `fixed_teacher_salary`, codes `payroll_rate.*`). Adjustments, settings, payslip rows, the CSV and the generate result gain their fields.
- **Dashboard.** The adjustment dialog's "Fixed amount / Percentage" choice, a settings field, a fixed-salary row on the Rates page, `PayslipBody`'s fixed and report sections and counters, three more counter columns, and the stale-salary notice.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod, i18next; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-08-b4b-incentives-reports-fixed-design.md`. It builds on:
- Plan 46 (B4a): `PaySettings`, `effective_settings`, `build(…, settings=)`, `Line`, `regroup`, `paying_sessions`, `_unpaid_rows`, the settings page, `PayslipBody`'s `LineBadges`, the counts toggle and `seed_b4`. Everything Plan 46 produces is treated as existing; its names are used as Plan 46 defines them.
- Plan 7 (`2026-09-26-payroll-design.md`; code in `backend/etqan/payroll/`).
- Plan 5's session reports (`scheduling.services.missing_reports`, `write_report`; the reverse field `report`).

It also applies these ledger and orchestration rules:
- **D25**: `ValidationError(code=…)`.
- **PO-5 / FT-2 / FT-4**: switches off by default; a switch stored true while unbuilt takes effect with neutral defaults; rows made while a switch was on stay readable and deletable.

## Plan rulings (where this plan fills a gap in the spec)

| # | Ruling |
|---|---|
| R1 | **`PaySettings` gains four fields with dataclass defaults**: `report_deduction_bp=0`, `percentages=False`, `fixed_salary=False`, `session_reports=True`. The defaults are a fresh academy's (`session_reports` is on by default), so `PaySettings.DEFAULTS` and Plan 46's tests are unchanged. `session_reports` is added to the snapshot so R-4's "null while `session_reports` is off" is read once, with the other switches (S-1). |
| R2 | **The two switch refusals are request rules.** I-3 ("a request body that sets `percent_bp` to a value is 400") and R-1 ("a PATCH that carries `report_deduction_bp` is 400") live in the serializers (`validate_percent_bp`, `validate_report_deduction_bp`). The services enforce the form rules only (exactly one of amount and percentage; a percentage is a bonus; ranges). This lets `seed_b4` create the demo's pending 5 % bonus while the switch is off (spec §7), and lets tests write a stored `report_deduction_bp` for the B4-2 regression. A `null` `percent_bp` is never refused: clearing one is allowed while off. |
| R3 | **`UNSET` lives in `rules.py`**, shared by `update_adjustment` and `update_fixed_salary`. The API passes only the keys a PATCH sent (`partial=True`), so a key left out stays `UNSET`. |
| R4 | **`pending_adjustments(last, *, percentages)` and `other_currency_adjustments(last, *, percentages)`** take a required keyword. Every caller passes the snapshot's `percentages`. Issue reads `effective_settings()` before it locks the pending adjustments, because the snapshot decides which rows it locks. The lock order is unchanged; the settings row is never locked. |
| R5 | **Copied text** (academy default language): fixed line "Fixed monthly salary" / "الراتب الشهري الثابت"; percentage bonus "Bonus — 12.5 % — {reason}" / "مكافأة — 12.5 ٪ — {reason}"; report line "Missing report — {description}" / "تقرير غير مرسل — {description}"; per class "Missing reports (2 of 3) — {description}" / "تقارير غير مرسلة (2 من 3) — {description}". `{p}` is computed in integers (`percent_text`). |
| R6 | **`report_deductions_minor` is positive**: the negated sum of the report lines, like `deductions_minor`. It is a correlated subquery on `payslips_queryset()`, so the list's query count is unchanged. |
| R7 | **Counters.** `reports_sent` = `payroll_sessions(first, last)` filtered to the teacher, the payslip's session ids, `REPORT_OWED` and `report__isnull=False`. `teacher_absences` = the teacher's `payroll_sessions` rows of the month with `TEACHER_AWAY`. `reports_missing` = the size of R-2's set. They are computed only from unlocked rows, which at build is every row the payslip pays. |
| R8 | **A second fixed salary is a 409**, never `full_clean`'s 400. `create_fixed_salary` runs `rules.check(row, exclude=("teacher",))`, so the OneToOne's `validate_unique` is skipped, then pre-checks `_taken(teacher)`, and turns a concurrent `IntegrityError` into the same 409. |
| R9 | **Per class and fixed salary together:** `regroup` runs first, then the fixed salary zeroes every session line. Members already carry 0; the carrier's rate is cleared like any line. |
| R10 | **Adjustment dialog bodies.** A percentage bonus sends `{kind: "bonus", amount_minor: null, percent_bp}`. Turning a percentage back into an amount also sends `percent_bp: null`. A fixed adjustment that was always fixed sends no `percent_bp` key, so Plan 7's request bodies are unchanged. A pending percentage edited while the switch is off sends only `{effective_on, reason}`. |
| R11 | **The fixed salary's start month** is an optional `<input type="month">`. An empty value sends no `starts_on`, so the server's default (this month on the academy's calendar) applies; a chosen month sends `YYYY-MM-01`. |
| R12 | **`PayslipBody`.** Fixed lines get their own "Fixed salary" section before "Sessions". The report section is shown only when there are report lines, so payslips from before B4b look exactly as they do today. The rate cell shows "—" for a session line with no rate when the payslip has a fixed line, or when the line is a `member` line. |
| R13 | **CSV order.** B4b appends its four columns at the end of `CSV_COLUMNS` as trunk has it at build time. If B4c merged first, they go after B4c's two ("whichever slice comes second appends after the first"). Tests assert with `endswith`. |
| R14 | **`stale_fixed_salary`** names every teacher (active or not) whose fixed salary has started by the month and is in an old currency, while `fixed_teacher_salary` is on. |
| R15 | **The E2E** creates its data through the API, sets 50 % on the settings page, and asserts copied line text with a regex that accepts both academy languages, because copied text follows the demo academy's default language. |

## Global Constraints

**Repos and branches**
- The meta worktree is `/home/abdulkhalek/Projects/etqan_tutor-wt/b4`, written `$W` below.
- The branch is `feat/b4b-incentives-reports` (already checked out in meta, `backend/` and `dashboard/`). Meta is cut from `origin/master`; `backend/` and `dashboard/` are cut from `origin/main`. `marketing/` is untouched.
- B4c (Plan 53) is not merged when this plan is written, and nothing here depends on it. Where a step below replaces a whole function or file (`generate`, `PayslipBody`, `seeds/b4.py`, `effective_settings`), first compare it with trunk: if trunk has moved past B4a's version (B4c merged first, say), merge this plan's changes into trunk's version instead of replacing it. Shared lists (`CSV_COLUMNS`, payloads, the `BUILT` test) get B4b's lines after whatever trunk already has.
- Commit in the submodule that owns each file (`git -C $W/backend …`, `git -C $W/dashboard …`).
- Never run `git submodule update`, or any other `git submodule` subcommand that writes.
- Commit messages are Conventional Commits and end with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Never edit `STATE.md`, CI workflows, Caddyfiles or meta's submodule pointers.
- Shared lists get lines only under `── phase B4 ──` markers. This plan's markers are in:
  - `etqan/platform/features.py`;
  - `etqan/access/registry.py`;
  - `etqan/tenants/management/commands/seed_dev.py`;
  - `dashboard/src/features/shell/nav.ts`.

  The registry's existing `_later("incentives_deductions", …)`, `_later("report_deductions", …)` and `_later("fixed_teacher_salary", …)` lines are flipped **in place**. This slice adds no line under a marker: `seed_b4` is already called under seed_dev's marker (Plan 46), and there is no new resource or nav item.

**Commands.** The stream stack must be up (`just dev-backend`) and `$W/.env.stream` must exist. The conductor creates it when it gives B4 a slot.
- Load the stream's environment first: `cd $W; set -a; . ./.env.stream; set +a`.
- Run docker compose directly. Below, `…` stands for `docker compose -f docker-compose.local.yml`.
- **Backend tests:** `… exec -T django pytest -q <paths>`. Add `--create-db` once after the migration.
- **Backend format:** `… exec -T django ruff check --fix .`, then `… exec -T django ruff format .`.
- **Backend verify:** `ruff check .`, `ruff format --check .`, `lint-imports`, `pytest -q --cov=etqan`, each through `… exec -T django`.
- **Migration:** `… exec -T django python manage.py makemigrations payroll --name incentives_reports_fixed`. Trunk's payroll leaf at build time is `0002_pay_rules` (B4a), so this makes `0003_incentives_reports_fixed`, or `0004_incentives_reports_fixed` if B4c merged first. Use the generated file's real name below.
- **Dashboard tests:** `… exec -T dashboard pnpm exec vitest run <paths>`.
- **Dashboard verify:** `pnpm exec tsc --noEmit`, `pnpm lint`, `pnpm test:coverage`, each through `… exec -T dashboard`. Format first with `… exec -T dashboard pnpm exec biome check --write src e2e`.
- **New route files:** regenerate `src/routeTree.gen.ts` with `… exec -T dashboard pnpm exec vite build`. It is generated: never edit it by hand. (This slice adds no route file.)
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
  - root fixtures: `staff_for(*codes)`, `api_for("admin")`, `set_features(**switches)`, `tenants`;
  - payroll's conftest: `clock`, `world`, `admin`, `june_sessions`, `mark`, `set_rate`, `adjust`, `JUNE`, and Plan 46's `rules_on`, `student_rate`, `june_group`;
  - scheduling's conftest: `make_teacher`, `make_student`, `hand_session`, `group_bundle`, `bundles_on`, `two_slots`.
- New shared payroll test helpers go once in `etqan/payroll/tests/conftest.py`: `pay_in` and `fixed_salary` (Task 2), `percent_bonus` (Task 3). `pay_in` already exists as a local helper in trunk's `test_rates_adjustments.py` (same body): Task 2 moves it to the conftest and that file imports it, so it exists once.
- Every list or read that renders rows carries a query-count test that counts SELECTs only. It must give the same count for 1 row and for 3 rows.
- `etqan/platform/tests/test_features.py` `BUILT` lists every built switch **in registry order**. All three B4b switches are flipped in place: `incentives_deductions` between `verified_certificates` and `homework` (the registry has `payment_links`, `verified_certificates`, `incentives_deductions`, `free_sessions`, `homework`); `report_deductions` and `fixed_teacher_salary` between `session_archive` and `registration_waitlist`.
- Three trunk tests use `report_deductions` as their example of an unbuilt switch held by `session_reports`. Flipping it to built with `requires=("session_reports", "payroll_rules")` changes what they see; Task 1 updates them.
- The test academy's default language is **Arabic** (`AcademySettings.default_language` defaults to `ar`), so copied text is Arabic unless a test sets `academy_services.update_settings(default_language="en")`, as trunk's `test_group_pay.py` does.
- `etqan/access/tests/test_routes.py`:
  - every new route joins `ROUTES`, and every gated route joins `FEATURES`, under a `# Slice B4b.` comment;
  - `FEATURE_WORDS` gains `"/fixed-salaries/": "fixed_teacher_salary"`.
- `dashboard/src/routes/permissions.test.ts`: unchanged (no new screen).

**Coverage and dev data**
- Gates: backend ≥ 80 %; dashboard lines 80 / statements 80 / branches 70 / functions 70.
- The seeded dev password is `e2e-EtqanTest-2026`. The demo admin is `admin@demo.test`.

## Review Focus

1. **Switches off, nothing moves (B4-2).** With a stored report share of 5000, a stored fixed salary and a pending percentage bonus written straight to the table, a month with a missing report builds the same lines and totals as B4a, and issue leaves the percentage pending. The same holds with the three switches stored true and neutral defaults. Pinned by Task 6.
2. **A percentage of nothing.** A percentage bonus on a month whose gross is 0 makes no line and stays pending; it is never used up for nothing at issue. Pinned in Task 4.
3. **Per class.** One class of three rows with two reports missing loses `round_half_up(750 × 5000 × 2, 10000 × 3) = 250` in one line on the carrier, not three lines and not 750. Pinned in Task 5.
4. **A fixed-salary month.** Session lines are listed at 0 with no rate, are locked at issue, never set `missing_rate`, get no report deduction, and a late row is not reported in `unpaid_sessions`. Pinned in Tasks 4–6.
5. **`update_adjustment`.** A key left out is unchanged, `None` clears, and the row after the change must have exactly one form (400 on `amount_minor`), so `{percent_bp: 1000, amount_minor: null}` turns a fixed bonus into a 10 % one. Pinned in Task 3.

---

### Task 1: The switches, the models and the migration

**Files:**
- Modify: `backend/etqan/platform/features.py`. Flip `incentives_deductions`, `report_deductions` and `fixed_teacher_salary` in place.
- Modify: `backend/etqan/platform/tests/test_features.py` (`BUILT`, the `requires` assertion, the prerequisite test, `test_describe_lists_every_feature_for_the_academy_admin`).
- Modify: `backend/etqan/academy/tests/test_features_api.py`, `backend/etqan/tenants/tests/test_admin_features.py` (their `report_deductions` expectations).
- Modify: `backend/etqan/payroll/models.py`.
- Create: `backend/etqan/payroll/migrations/0003_incentives_reports_fixed.py` (generated; `0004_…` if B4c merged first).
- Test: `backend/etqan/payroll/tests/test_models.py` (append).

**Interfaces:**
- Produces:
  - `PayAdjustment.amount_minor: int | None`, `PayAdjustment.percent_bp: int | None`, constraint `payroll_adjustment_one_form` (replacing `payroll_adjustment_amount_positive`);
  - `PayrollSettings.report_deduction_bp` (0–10000, default 0);
  - `FixedSalary(teacher, monthly_minor, currency, starts_on, created_at, updated_at)`;
  - `Payslip.reports_sent`, `.reports_missing`, `.teacher_absences` (nullable);
  - `PayslipLine.Kind.REPORT` (`"report"`) and `PayslipLine.Kind.FIXED` (`"fixed"`);
  - switches `incentives_deductions`, `report_deductions` (requires `session_reports`, `payroll_rules`) and `fixed_teacher_salary`, built and off.

- [ ] **Step 1: Write the failing tests**

Append to `backend/etqan/payroll/tests/test_models.py` (merge the imports into the file's import block; `date`, `pytest`, `IntegrityError`, `transaction`, `PayAdjustment`, `PayrollSettings`, `PayslipLine`, `features`, `make_teacher` and the `teacher`/`payslip` helpers are already there, so only `FixedSalary` is a new import):

```python
from etqan.payroll.models import FixedSalary
from etqan.payroll.models import PayrollSettings
from etqan.payroll.models import PayslipLine
from etqan.platform import features

JUNE_15 = date(2026, 6, 15)


def adjustment(teacher, **fields):
    return PayAdjustment.objects.create(
        teacher=teacher,
        currency="USD",
        effective_on=JUNE_15,
        reason="Extra",
        **fields,
    )


def test_a_bonus_may_be_a_percentage_instead_of_an_amount(teacher):
    share = adjustment(teacher, kind="bonus", amount_minor=None, percent_bp=1000)
    fixed = adjustment(teacher, kind="deduction", amount_minor=500)
    assert (share.amount_minor, share.percent_bp) == (None, 1000)
    assert fixed.percent_bp is None


@pytest.mark.parametrize(
    "fields",
    [
        {"kind": "bonus", "amount_minor": 500, "percent_bp": 1000},  # both
        {"kind": "bonus", "amount_minor": None},  # neither
        {"kind": "deduction", "amount_minor": None, "percent_bp": 1000},
        {"kind": "bonus", "amount_minor": None, "percent_bp": 0},
        {"kind": "bonus", "amount_minor": None, "percent_bp": 10001},
    ],
)
def test_the_database_refuses_any_other_form(teacher, fields):
    with pytest.raises(IntegrityError), transaction.atomic():
        adjustment(teacher, **fields)


def test_one_fixed_salary_per_teacher_and_never_zero(teacher):
    june = date(2026, 6, 1)
    FixedSalary.objects.create(
        teacher=teacher, monthly_minor=50000, currency="USD", starts_on=june
    )
    with pytest.raises(IntegrityError), transaction.atomic():
        FixedSalary.objects.create(
            teacher=teacher, monthly_minor=1, currency="USD", starts_on=june
        )
    other = make_teacher("Hamza").teacher_profile
    with pytest.raises(IntegrityError), transaction.atomic():
        FixedSalary.objects.create(
            teacher=other, monthly_minor=0, currency="USD", starts_on=june
        )


def test_the_report_share_defaults_to_nothing(db):
    assert PayrollSettings.objects.get(pk=1).report_deduction_bp == 0
    with pytest.raises(IntegrityError), transaction.atomic():
        PayrollSettings.objects.filter(pk=1).update(report_deduction_bp=10001)


def test_counters_start_unknown_and_lines_have_two_new_kinds(teacher):
    slip = payslip(teacher)
    assert (slip.reports_sent, slip.reports_missing, slip.teacher_absences) == (
        None,
        None,
        None,
    )
    assert {"report", "fixed"} <= set(PayslipLine.Kind.values)


def test_the_b4b_switches_are_built_and_off():
    for code in ("incentives_deductions", "report_deductions", "fixed_teacher_salary"):
        feature = features.get(code)
        assert feature.built
        assert feature.default is False
    assert features.get("report_deductions").requires == (
        "session_reports",
        "payroll_rules",
    )
```

In `etqan/platform/tests/test_features.py`:
- In `BUILT`, add `"incentives_deductions": False` between `"verified_certificates"` and `"homework"`, and `"report_deductions": False, "fixed_teacher_salary": False` between `"session_archive"` and `"registration_waitlist"`. Extend the "Flipped in place" comment with "B4b's incentives_deductions, report_deductions and fixed_teacher_salary".
- Replace `assert features.get("report_deductions").requires == ("session_reports",)` with:

```python
    assert features.get("report_deductions").requires == (
        "session_reports",
        "payroll_rules",
    )
```

- In `test_a_prerequisite_switched_off_holds_a_feature_off`, `report_deductions` now also needs `payroll_rules`. Replace its body with:

```python
def test_a_prerequisite_switched_off_holds_a_feature_off():
    both = {"report_deductions": True, "payroll_rules": True}
    assert features.is_on("report_deductions", both) is True
    assert features.held_by("report_deductions", both) == []
    held = {**both, "session_reports": False}
    assert features.is_on("report_deductions", held) is False
    assert features.held_by("report_deductions", held) == ["session_reports"]
    # Slice B4b R-1: its setting lives on payroll_rules' page.
    alone = {"report_deductions": True}
    assert features.held_by("report_deductions", alone) == ["payroll_rules"]
    # Nothing holds a feature whose own switch is off.
    assert features.held_by("report_deductions", {"session_reports": False}) == []
```

- In `test_describe_lists_every_feature_for_the_academy_admin` (it sets `report_deductions=True, session_reports=False`), the expected `rows["report_deductions"]` becomes `"built": True` and `"held_by": ["session_reports", "payroll_rules"]` (`payroll_rules` is off by default).

Trunk's other two `report_deductions` examples (an expected change):
- `etqan/academy/tests/test_features_api.py::test_the_admin_reads_every_feature_in_registry_order`: `by_code["report_deductions"]["held_by"]` becomes `["session_reports", "payroll_rules"]`.
- `etqan/tenants/tests/test_admin_features.py::test_the_change_page_shows_the_features_by_group`: the switch is now built, so its help text loses "Takes effect when built." and becomes `"Held off: needs Session reports, Payroll rules."` (read `tenants/admin.py`'s `held_by` note to confirm the exact join). `test_the_command_prints_the_switch_not_the_effective_state` needs no change.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_models.py etqan/platform/tests/test_features.py`
Expected: FAIL with ImportError (`FixedSalary`), and the `BUILT` comparison fails.

- [ ] **Step 3: The switches**

In `features.py`, replace the three `_later(…)` blocks **in place**:

```python
    # Phase B4, slice B4b (I-1…I-3): flipped to built in place, off by
    # default. It gates percentage bonuses only; fixed bonuses and
    # deductions stay always on (Plan 7).
    Feature(
        "incentives_deductions",
        "Incentives and deductions",
        "نظام الحوافز والخصومات",
        "money",
        built=True,
    ),
```

```python
    # Phase B4, slice B4b (R-1): flipped in place. Its setting lives on the
    # payroll rules page, so it needs payroll_rules too.
    Feature(
        "report_deductions",
        "Report deductions",
        "خصومات التقارير",
        "money",
        built=True,
        requires=("session_reports", "payroll_rules"),
    ),
    # Phase B4, slice B4b (F-1…F-5): flipped in place.
    Feature(
        "fixed_teacher_salary",
        "Fixed teacher salary",
        "الراتب الثابت للمعلم",
        "money",
        built=True,
    ),
```

- [ ] **Step 4: The models**

In `payroll/models.py`, replace `PayAdjustment`'s `amount_minor` and its `Meta.constraints`:

```python
    # Slice B4b I-1: a fixed amount, or (a bonus only) a percentage of the
    # month's gross in basis points; exactly one is set.
    amount_minor = models.BigIntegerField(
        null=True, blank=True, validators=[MinValueValidator(1)]
    )
    percent_bp = models.PositiveSmallIntegerField(
        null=True,
        blank=True,
        validators=[MinValueValidator(1), MaxValueValidator(10000)],
    )
```

```python
    class Meta:
        ordering = ["-effective_on", "-id"]
        constraints = [
            models.CheckConstraint(
                condition=Q(amount_minor__gt=0, percent_bp__isnull=True)
                | Q(
                    amount_minor__isnull=True,
                    percent_bp__gte=1,
                    percent_bp__lte=10000,
                    kind="bonus",
                ),
                name="payroll_adjustment_one_form",
            )
        ]
```

`percent_bp` goes right after `amount_minor`. `__str__` stays.

In `PayrollSettings` (Plan 46), add after `group_pay`:

```python
    # Slice B4b R-1: the share of a session's pay a missing report costs.
    # Counts only while `report_deductions` is on (`effective_settings`).
    report_deduction_bp = models.PositiveSmallIntegerField(default=0, validators=BP)
```

and to its `Meta.constraints`:

```python
            models.CheckConstraint(
                condition=Q(report_deduction_bp__lte=10000),
                name="payroll_settings_report_bp_max",
            ),
```

After `PayrollSettings`, add:

```python
class FixedSalary(models.Model):
    """Slice B4b F-1: a teacher's fixed monthly salary, paid in full for every
    month from ``starts_on`` (the first of a month) while
    `fixed_teacher_salary` is on and ``currency`` is the teacher's current
    `pay_currency`."""

    teacher = models.OneToOneField(
        "identity.TeacherProfile", on_delete=models.PROTECT, related_name="+"
    )
    monthly_minor = models.BigIntegerField(validators=[MinValueValidator(1)])
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    starts_on = models.DateField()  # the academy's calendar
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["teacher_id"]
        constraints = [
            models.CheckConstraint(
                condition=Q(monthly_minor__gt=0),
                name="payroll_fixed_salary_positive",
            )
        ]

    def __str__(self):
        return f"FixedSalary<{self.teacher_id}, {self.monthly_minor}>"
```

In `Payslip`, add after `missing_rate`:

```python
    # Slice B4b R-4: stored at build; null on payslips built before B4b, and
    # the two report counters also while `session_reports` is off.
    reports_sent = models.PositiveSmallIntegerField(null=True, blank=True)
    reports_missing = models.PositiveSmallIntegerField(null=True, blank=True)
    teacher_absences = models.PositiveSmallIntegerField(null=True, blank=True)
```

In `PayslipLine.Kind`:

```python
    class Kind(models.TextChoices):
        SESSION = "session", "Session"
        ADJUSTMENT = "adjustment", "Adjustment"
        # Slice B4b R-3 and F-2.
        REPORT = "report", "Missing report"
        FIXED = "fixed", "Fixed salary"
```

`kind`'s `max_length=10` already fits both.

- [ ] **Step 5: The migration**

Run `… exec -T django python manage.py makemigrations payroll --name incentives_reports_fixed`. Read the generated file: it must hold `RemoveConstraint(payroll_adjustment_amount_positive)`, `AlterField(amount_minor)`, the `AddField`s, `CreateModel(FixedSalary)`, an `AlterField(PayslipLine.kind)` and `AddConstraint`s, with the `AddConstraint(payroll_adjustment_one_form)` **after** `AddField(percent_bp)`. If Django ordered them otherwise, move that `AddConstraint` to the end. No `RunPython`: existing rows already satisfy the new constraint.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `… exec -T django pytest -q --create-db etqan/payroll etqan/platform/tests/test_features.py etqan/access etqan/academy/tests/test_features_api.py etqan/tenants/tests/test_admin_features.py`
Expected: PASS. `test_the_database_refuses_an_adjustment_of_nothing` (Plan 7) still passes under the new constraint.

- [ ] **Step 7: Commit**

```bash
git -C $W/backend add etqan/platform/features.py etqan/platform/tests/test_features.py etqan/academy/tests/test_features_api.py etqan/tenants/tests/test_admin_features.py etqan/payroll/models.py etqan/payroll/migrations etqan/payroll/tests/test_models.py
git -C $W/backend commit -m "feat(payroll): B4b switches, percentage adjustments, fixed salary, counters

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The settings snapshot and the fixed-salary service

**Files:**
- Modify: `backend/etqan/payroll/services/settings.py`
- Modify: `backend/etqan/payroll/services/rules.py` (`UNSET`, fixed-salary queries)
- Create: `backend/etqan/payroll/services/fixed_salaries.py`
- Modify: `backend/etqan/payroll/services/__init__.py`
- Modify: `backend/etqan/payroll/tests/conftest.py` (`pay_in`, `fixed_salary`)
- Modify: `backend/etqan/payroll/tests/test_rates_adjustments.py` (drop its local `pay_in`, import the conftest's)
- Test: `backend/etqan/payroll/tests/test_pay_rules.py` (append), `backend/etqan/payroll/tests/test_fixed_salaries.py` (new)

**Interfaces:**
- Consumes: `PayrollSettings.report_deduction_bp`, `FixedSalary` (Task 1); Plan 46's `PaySettings`, `FIELDS`, `get_settings`, `update_settings`.
- Produces:
  - `PaySettings.report_deduction_bp: int`, `.percentages: bool`, `.fixed_salary: bool`, `.session_reports: bool` (plan R1);
  - `rules.UNSET`;
  - `rules.counting_fixed_salaries(first) -> QuerySet[FixedSalary]`, `rules.stale_fixed_salaries(first)`, `rules.counting_fixed_salary(teacher, first, pay) -> FixedSalary | None`;
  - `create_fixed_salary(*, teacher_id, monthly_minor, starts_on=None)`, `update_fixed_salary(row, *, monthly_minor=UNSET, starts_on=UNSET)`, `delete_fixed_salary(row)`, `fixed_salaries_queryset()`;
  - conftest `pay_in(teacher, currency)` and `fixed_salary(teacher, monthly, *, starts_on=None)`.

- [ ] **Step 1: Write the failing tests**

Add to `backend/etqan/payroll/tests/conftest.py` (import `from etqan.identity import services as identity_services`). `pay_in` is moved here from `test_rates_adjustments.py`, which then imports it from the conftest instead of defining it:

```python
def pay_in(teacher, currency):
    """Slice B4b: ``teacher`` (a User) is paid in ``currency`` from now on."""
    identity_services.update_person(teacher, profile={"pay_currency": currency})


def fixed_salary(teacher, monthly, *, starts_on=None):
    """Slice B4b: ``teacher``'s (a User) fixed monthly salary."""
    return services.create_fixed_salary(
        teacher_id=teacher.id, monthly_minor=monthly, starts_on=starts_on
    )
```

Append to `backend/etqan/payroll/tests/test_pay_rules.py`:

```python
def test_the_b4b_switch_answers_are_in_the_snapshot(db, set_features):
    pay = effective_settings()
    assert (
        pay.percentages,
        pay.fixed_salary,
        pay.session_reports,
        pay.report_deduction_bp,
    ) == (False, False, True, 0)
    set_features(
        incentives_deductions=True, fixed_teacher_salary=True, session_reports=False
    )
    pay = effective_settings()
    assert (pay.percentages, pay.fixed_salary, pay.session_reports) == (
        True,
        True,
        False,
    )


def test_the_report_share_counts_only_while_report_deductions_is_on(
    db, set_features
):
    update_settings(by=None, report_deduction_bp=5000)
    assert effective_settings().report_deduction_bp == 0
    set_features(payroll_rules=True)
    assert effective_settings().report_deduction_bp == 0
    set_features(report_deductions=True)
    assert effective_settings().report_deduction_bp == 5000
    set_features(session_reports=False)  # its prerequisite holds it off
    assert effective_settings().report_deduction_bp == 0


@pytest.mark.parametrize("value", [-1, 10001])
def test_a_report_share_outside_0_to_10000_is_refused(db, value):
    with pytest.raises(ValidationError) as caught:
        update_settings(by=None, report_deduction_bp=value)
    assert caught.value.field == "report_deduction_bp"
```

`backend/etqan/payroll/tests/test_fixed_salaries.py`:

```python
"""Slice B4b F-1, §4.3: a teacher's fixed monthly salary."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.payroll import services
from etqan.payroll.models import FixedSalary
from etqan.payroll.services import fixed_salaries
from etqan.payroll.services import rules
from etqan.payroll.tests.conftest import fixed_salary
from etqan.payroll.tests.conftest import pay_in
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import make_teacher

JUNE_1 = date(2026, 6, 1)


def test_it_is_in_the_teachers_currency_from_the_first_of_its_month(world):
    pay_in(world.teacher, "EGP")
    row = fixed_salary(world.teacher, 50000, starts_on=date(2026, 6, 17))
    assert (row.monthly_minor, row.currency, row.starts_on) == (50000, "EGP", JUNE_1)
    assert row.teacher.user_id == world.teacher.id


def test_it_starts_this_month_on_the_academys_calendar_by_default(world, clock):
    # The academy's timezone is UTC in these tests.
    clock.set(datetime(2026, 7, 31, 23, tzinfo=UTC))
    assert fixed_salary(world.teacher, 50000).starts_on == date(2026, 7, 1)


def test_a_second_one_is_409(world):
    fixed_salary(world.teacher, 50000)
    with pytest.raises(ConflictError) as caught:
        fixed_salary(world.teacher, 60000)
    assert caught.value.code == "payroll.fixed_salary_exists"


def test_a_concurrent_insert_is_409_too(world, monkeypatch):
    """The database decides a race (plan R8): simulated by a pre-check that
    misses the row another request just inserted."""
    fixed_salary(world.teacher, 50000)
    monkeypatch.setattr(fixed_salaries, "_taken", lambda teacher: False)
    with pytest.raises(ConflictError) as caught:
        fixed_salary(world.teacher, 60000)
    assert caught.value.code == "payroll.fixed_salary_exists"
    assert FixedSalary.objects.count() == 1


@pytest.mark.parametrize(
    ("who", "monthly", "field"),
    [("student", 1, "teacher"), ("teacher", 0, "monthly_minor")],
)
def test_bad_input_is_400_on_its_field(world, who, monthly, field):
    person = world.teacher if who == "teacher" else world.student
    with pytest.raises(ValidationError) as caught:
        fixed_salary(person, monthly)
    assert caught.value.field == field
    assert not FixedSalary.objects.exists()


def test_an_edit_keeps_what_is_left_out_and_moves_to_the_current_currency(world):
    row = fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    pay_in(world.teacher, "EGP")
    edited = services.update_fixed_salary(row, monthly_minor=70000)
    assert (edited.monthly_minor, edited.currency, edited.starts_on) == (
        70000,
        "EGP",
        JUNE_1,
    )
    moved = services.update_fixed_salary(edited, starts_on=date(2026, 8, 20))
    assert (moved.monthly_minor, moved.starts_on) == (70000, date(2026, 8, 1))


def test_delete_and_a_row_deleted_meanwhile(world):
    row = fixed_salary(world.teacher, 50000)
    services.delete_fixed_salary(row)
    assert not services.fixed_salaries_queryset().exists()
    with pytest.raises(NotFoundError):
        services.update_fixed_salary(row, monthly_minor=1)


def test_which_salaries_count_for_a_month(world):
    other = make_teacher("Hamza")
    mine = fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    later = fixed_salary(other, 40000, starts_on=date(2026, 7, 1))
    assert list(rules.counting_fixed_salaries(JUNE_1)) == [mine]
    assert set(rules.counting_fixed_salaries(date(2026, 7, 1))) == {mine, later}
    pay_in(world.teacher, "EGP")
    assert list(rules.counting_fixed_salaries(JUNE_1)) == []
    assert list(rules.stale_fixed_salaries(JUNE_1)) == [mine]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_pay_rules.py etqan/payroll/tests/test_fixed_salaries.py`
Expected: FAIL with ImportError (`fixed_salaries`) and AttributeError (`PaySettings` has no `percentages`).

- [ ] **Step 3: The settings snapshot**

In `services/settings.py`, extend the dataclass (the new fields have defaults, so Plan 46's `PaySettings(...)` constructions and `DEFAULTS` stay valid):

```python
@dataclass(frozen=True)
class PaySettings:
    student_absent_pay_bp: int
    student_excused_pay_bp: int
    at_disposal_pays: bool
    group_pay: str
    # Whether `student_teacher_rate` is on (plan 46 R1).
    student_rates: bool
    # Slice B4b (S-1, plan 54 R1): a missing report's share (0 unless
    # `report_deductions` is on), and whether `incentives_deductions`,
    # `fixed_teacher_salary` and `session_reports` are on. The defaults are
    # a fresh academy's.
    report_deduction_bp: int = 0
    percentages: bool = False
    fixed_salary: bool = False
    session_reports: bool = True
```

Replace `effective_settings`:

```python
def _switches() -> dict:
    """The switch answers `build` asks, read once (B4a A-3, B4b S-1)."""
    return {
        "student_rates": features.enabled("student_teacher_rate"),
        "percentages": features.enabled("incentives_deductions"),
        "fixed_salary": features.enabled("fixed_teacher_salary"),
        "session_reports": features.enabled("session_reports"),
    }


def effective_settings() -> PaySettings:
    """The rules `build` applies now: the row while `payroll_rules` is on,
    today's rule while it is off; the switches by their own codes. The
    report share counts only while `report_deductions` is on (R-1), which
    itself needs `payroll_rules` and `session_reports`."""
    switches = _switches()
    if not features.enabled("payroll_rules"):
        return PaySettings(**{**PaySettings.DEFAULTS.__dict__, **switches})
    row = get_settings()
    return PaySettings(
        **{field: getattr(row, field) for field in FIELDS},
        **switches,
        report_deduction_bp=row.report_deduction_bp
        if features.enabled("report_deductions")
        else 0,
    )
```

`FIELDS` stays Plan 46's four names: `report_deduction_bp` is read separately because its effective value depends on another switch. `update_settings` needs no change; `rules.save` runs `full_clean`, so a bad share is a 400 on `report_deduction_bp`.

- [ ] **Step 4: `rules.py` additions**

Import `FixedSalary` from the models. Add:

```python
class _Unset:
    """Slice B4b §4.2: a keyword the caller left out, so ``None`` can mean
    "clear"."""

    def __repr__(self) -> str:
        return "UNSET"


UNSET = _Unset()


def counting_fixed_salaries(first: date) -> QuerySet[FixedSalary]:
    """Slice B4b F-1: fixed salaries that count for the month starting
    ``first``: started by then and in their teacher's current
    ``pay_currency``. Callers check `fixed_teacher_salary` themselves."""
    return FixedSalary.objects.filter(
        starts_on__lte=first, currency=F("teacher__pay_currency")
    )


def stale_fixed_salaries(first: date) -> QuerySet[FixedSalary]:
    """Fixed salaries that would count for the month but for a currency the
    teacher is no longer paid in (F-1): left out, and named by generate."""
    return FixedSalary.objects.filter(starts_on__lte=first).exclude(
        currency=F("teacher__pay_currency")
    )


def counting_fixed_salary(teacher, first: date, pay) -> FixedSalary | None:
    """The teacher's fixed salary for the month, or None while
    `fixed_teacher_salary` is off (``pay``, the effective settings) or it
    does not count. Compared with the in-memory ``pay_currency`` too, as
    adjustments are (spec Plan 7 §4.1)."""
    if not pay.fixed_salary:
        return None
    return (
        counting_fixed_salaries(first)
        .filter(teacher=teacher, currency=teacher.pay_currency)
        .first()
    )
```

- [ ] **Step 5: `services/fixed_salaries.py`**

```python
"""Slice B4b F-1, spec §4.3: a teacher's fixed monthly salary. One per
teacher, saved in their current `pay_currency`, starting on the first of a
month. Each write locks its row, as rates do."""

from datetime import date

from django.db import IntegrityError
from django.db import transaction
from django.db.models import QuerySet

from etqan.payroll import clock
from etqan.payroll.models import FixedSalary
from etqan.payroll.services import rules
from etqan.payroll.services.rules import UNSET
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError

FIXED_SALARY_EXISTS = "payroll.fixed_salary_exists"


def _exists() -> ConflictError:
    return ConflictError(
        "This teacher already has a fixed salary. Edit it instead.",
        code=FIXED_SALARY_EXISTS,
    )


def _taken(teacher) -> bool:
    return FixedSalary.objects.filter(teacher=teacher).exists()


def _month_of(day: date) -> date:
    return day.replace(day=1)


@transaction.atomic
def create_fixed_salary(
    *, teacher_id: int, monthly_minor: int, starts_on: date | None = None
) -> FixedSalary:
    """For a teacher by User id, active or not, in their current
    `pay_currency`; from the first of ``starts_on``'s month, by default this
    month on the academy's calendar. A second one is 409, a race included."""
    teacher = rules.teacher_of(teacher_id)
    row = FixedSalary(
        teacher=teacher,
        monthly_minor=monthly_minor,
        currency=teacher.pay_currency,
        starts_on=_month_of(starts_on or clock.today()),
    )
    # One per teacher is a 409, never full_clean's unique 400 (plan R8).
    rules.check(row, exclude=("teacher",))
    if _taken(teacher):
        raise _exists()
    try:
        with transaction.atomic():
            row.save()
    except IntegrityError:
        raise _exists() from None
    return row


def _lock(row: FixedSalary) -> FixedSalary:
    try:
        return (
            FixedSalary.objects.select_for_update(of=("self",))
            .select_related("teacher")
            .get(pk=row.pk)
        )
    except FixedSalary.DoesNotExist:
        raise NotFoundError("Fixed salary", row.pk) from None


@transaction.atomic
def update_fixed_salary(
    row: FixedSalary, *, monthly_minor=UNSET, starts_on=UNSET
) -> FixedSalary:
    """Saved in the teacher's current `pay_currency`; a keyword left out is
    unchanged. Issued payslips keep their copied lines (P7-4)."""
    locked = _lock(row)
    edits = {
        name: value
        for name, value in (("monthly_minor", monthly_minor), ("starts_on", starts_on))
        if value is not UNSET
    }
    if "starts_on" in edits:
        edits["starts_on"] = _month_of(edits["starts_on"])
    for name, value in edits.items():
        setattr(locked, name, value)
    locked.currency = locked.teacher.pay_currency
    rules.save(locked, update_fields=[*edits, "currency", "updated_at"])
    return locked


@transaction.atomic
def delete_fixed_salary(row: FixedSalary) -> None:
    _lock(row).delete()


def fixed_salaries_queryset() -> QuerySet[FixedSalary]:
    """With the teacher's user, by teacher name: one query."""
    return FixedSalary.objects.select_related("teacher__user").order_by(
        "teacher__user__full_name", "teacher_id"
    )
```

Export `create_fixed_salary`, `update_fixed_salary`, `delete_fixed_salary` and `fixed_salaries_queryset` from `services/__init__.py` (imports and `__all__`).

- [ ] **Step 6: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`
Expected: PASS. Plan 46's `test_settings_are_todays_rule_while_payroll_rules_is_off` still passes: with every switch at its default, `session_reports` is True, as in `DEFAULTS`.

- [ ] **Step 7: Commit**

```bash
git -C $W/backend add etqan/payroll/services/settings.py etqan/payroll/services/rules.py etqan/payroll/services/fixed_salaries.py etqan/payroll/services/__init__.py etqan/payroll/tests/conftest.py etqan/payroll/tests/test_rates_adjustments.py etqan/payroll/tests/test_pay_rules.py etqan/payroll/tests/test_fixed_salaries.py
git -C $W/backend commit -m "feat(payroll): B4b settings snapshot and fixed-salary service

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Percentage adjustments, the pending filter and the demo seed

**Files:**
- Modify: `backend/etqan/payroll/services/adjustments.py`
- Modify: `backend/etqan/payroll/services/rules.py` (`pending_adjustments`, `other_currency_adjustments`)
- Modify: `backend/etqan/payroll/services/build.py` (`_adjustment_lines` call site)
- Modify: `backend/etqan/payroll/services/payslips.py` (`_pending_teacher_ids`, `_other_currency_teachers`, `issue`)
- Modify: `backend/etqan/payroll/tests/conftest.py` (`percent_bonus`)
- Modify: `backend/etqan/tenants/seeds/b4.py`
- Modify: `backend/etqan/payroll/tests/test_build.py` and `backend/etqan/payroll/tests/test_generate.py` (trunk callers of the changed signatures, below)
- Test: `backend/etqan/payroll/tests/test_percentages.py` (new), `backend/etqan/tenants/tests/test_seed_b4.py` (append)

**Interfaces:**
- Consumes: `PayAdjustment.percent_bp` (Task 1), `rules.UNSET` and `pay_in` (Task 2).
- Produces:
  - `create_adjustment(*, teacher_id, kind, effective_on, reason, by, amount_minor=None, percent_bp=None)`;
  - `update_adjustment(adjustment, *, kind=UNSET, amount_minor=UNSET, percent_bp=UNSET, effective_on=UNSET, reason=UNSET)`;
  - `adjustments.check_form(adjustment)`;
  - `rules.pending_adjustments(last, *, percentages)`, `rules.other_currency_adjustments(last, *, percentages)`;
  - conftest `percent_bonus(teacher, percent_bp, *, on, **fields)`;
  - `seed_b4` adds the demo's pending 5 % bonus.

- [ ] **Step 1: Write the failing tests**

Add to the payroll conftest:

```python
def percent_bonus(teacher, percent_bp, *, on, **fields):
    """Slice B4b: a percentage bonus for ``teacher`` (a User), effective
    ``on``. The service does not ask the switch (plan R2)."""
    return services.create_adjustment(
        teacher_id=teacher.id,
        kind="bonus",
        amount_minor=None,
        percent_bp=percent_bp,
        effective_on=on,
        **{"reason": "Target", "by": None, **fields},
    )
```

`backend/etqan/payroll/tests/test_percentages.py`:

```python
"""Slice B4b I-1…I-3, §4.2: percentage bonuses, the form rule, UNSET edits,
and percentages left pending while their switch is off."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.payroll import services
from etqan.payroll.models import PayAdjustment
from etqan.payroll.models import Payslip
from etqan.payroll.services import rules
from etqan.payroll.tests.conftest import adjust
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import pay_in
from etqan.payroll.tests.conftest import percent_bonus
from etqan.payroll.tests.conftest import set_rate
from etqan.platform.exceptions import ValidationError

JUNE_15 = date(2026, 6, 15)
JUNE_30 = date(2026, 6, 30)
JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)


def test_a_percentage_bonus_is_in_the_teachers_current_currency(world):
    pay_in(world.teacher, "EGP")
    share = percent_bonus(world.teacher, 1250, on=JUNE_15)
    assert (share.kind, share.amount_minor, share.percent_bp, share.currency) == (
        "bonus",
        None,
        1250,
        "EGP",
    )


@pytest.mark.parametrize(
    ("fields", "field"),
    [
        ({"kind": "deduction", "amount_minor": None, "percent_bp": 1000}, "kind"),
        ({"amount_minor": None, "percent_bp": None}, "amount_minor"),
        ({"amount_minor": 500, "percent_bp": 1000}, "amount_minor"),
        ({"amount_minor": None, "percent_bp": 10001}, "percent_bp"),
        ({"amount_minor": None, "percent_bp": 0}, "percent_bp"),
    ],
)
def test_a_bad_form_is_a_field_error(world, fields, field):
    body = {
        "teacher_id": world.teacher.id,
        "kind": "bonus",
        "effective_on": JUNE_15,
        "reason": "Target",
        "by": None,
        **fields,
    }
    with pytest.raises(ValidationError) as exc:
        services.create_adjustment(**body)
    assert exc.value.field == field
    assert not PayAdjustment.objects.exists()


def test_a_key_left_out_is_unchanged_and_none_clears_it(world):
    bonus = adjust(world.teacher, "bonus", 500, on=JUNE_15)
    services.update_adjustment(bonus, reason=" Eid ")
    bonus.refresh_from_db()
    assert (bonus.amount_minor, bonus.percent_bp, bonus.reason) == (500, None, "Eid")
    services.update_adjustment(bonus, amount_minor=None, percent_bp=1000)
    bonus.refresh_from_db()
    assert (bonus.amount_minor, bonus.percent_bp) == (None, 1000)
    services.update_adjustment(bonus, percent_bp=None, amount_minor=700)
    bonus.refresh_from_db()
    assert (bonus.amount_minor, bonus.percent_bp) == (700, None)


def test_the_row_after_the_change_has_exactly_one_form(world):
    bonus = adjust(world.teacher, "bonus", 500, on=JUNE_15)
    for edit in ({"amount_minor": None}, {"percent_bp": 1000}):
        with pytest.raises(ValidationError) as exc:
            services.update_adjustment(bonus, **edit)
        assert exc.value.field == "amount_minor"
    share = percent_bonus(world.teacher, 1000, on=JUNE_15)
    with pytest.raises(ValidationError) as exc:
        services.update_adjustment(share, kind="deduction")
    assert exc.value.field == "kind"
    bonus.refresh_from_db()
    share.refresh_from_db()
    assert (bonus.amount_minor, bonus.percent_bp) == (500, None)
    assert share.kind == "bonus"


def test_pending_percentages_only_while_they_count(world):
    fixed = adjust(world.teacher, "bonus", 500, on=JUNE_15)
    share = percent_bonus(world.teacher, 1000, on=JUNE_15)
    assert list(rules.pending_adjustments(JUNE_30, percentages=False)) == [fixed]
    assert set(rules.pending_adjustments(JUNE_30, percentages=True)) == {fixed, share}
    pay_in(world.teacher, "EGP")
    assert list(rules.other_currency_adjustments(JUNE_30, percentages=False)) == [
        fixed
    ]
    assert set(rules.other_currency_adjustments(JUNE_30, percentages=True)) == {
        fixed,
        share,
    }


def test_while_off_a_percentage_brings_no_payslip_and_no_warning(world, clock):
    """I-3: generate's discovery and its other_currency warning leave it out."""
    clock.set(JULY_FIRST)
    percent_bonus(world.teacher, 1000, on=JUNE_15)
    assert services.generate(2026, 6).created == 0
    pay_in(world.teacher, "EGP")
    assert services.generate(2026, 6).other_currency == []


def test_while_off_issue_leaves_a_percentage_pending(world, clock, admin):
    sessions = june_sessions(world)
    clock.set(JULY_FIRST)
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    share = percent_bonus(world.teacher, 1000, on=JUNE_15)
    services.generate(2026, 6)
    payslip = services.issue(Payslip.objects.get(), by=admin)
    assert payslip.bonuses_minor == 0
    share.refresh_from_db()
    assert share.payslip is None
```

Append to `backend/etqan/tenants/tests/test_seed_b4.py` (Plan 46's file; import `timedelta` from `datetime` and `timezone` from `django.utils`):

```python
def test_seed_b4_adds_one_pending_percentage_bonus_once(db, monkeypatch):
    teacher = make_teacher("Ustadh Bilal")
    make_student("Yusuf Omar")
    monkeypatch.setattr(
        "etqan.tenants.seeds.b4.PEOPLE", {"demo": ("Ustadh Bilal", "Yusuf Omar")}
    )
    seed_b4("demo")
    seed_b4("demo")
    (bonus,) = payroll_services.adjustments_queryset().filter(
        percent_bp__isnull=False
    )
    assert (
        bonus.teacher.user_id,
        bonus.kind,
        bonus.percent_bp,
        bonus.amount_minor,
        bonus.payslip_id,
    ) == (teacher.id, "bonus", 500, None, None)
    first = timezone.localdate().replace(day=1)
    assert bonus.effective_on == (first - timedelta(days=1)).replace(day=15)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_percentages.py etqan/tenants/tests/test_seed_b4.py`
Expected: FAIL with `TypeError: create_adjustment() got an unexpected keyword argument 'percent_bp'`.

- [ ] **Step 3: `adjustments.py`**

Import `ValidationError` from `etqan.platform.exceptions` and `UNSET` from `etqan.payroll.services.rules`. Add `check_form`, and replace `create_adjustment` and `update_adjustment`:

```python
def check_form(adjustment: PayAdjustment) -> None:
    """Slice B4b I-1, §4.2: exactly one of an amount and a percentage (400 on
    `amount_minor`), and only a bonus may be a percentage (400 on `kind`).
    Whether percentages are switched on is the request's rule (plan R2)."""
    if (adjustment.amount_minor is None) == (adjustment.percent_bp is None):
        raise ValidationError(
            "Give either an amount or a percentage.", field="amount_minor"
        )
    if (
        adjustment.percent_bp is not None
        and adjustment.kind != PayAdjustment.Kind.BONUS
    ):
        raise ValidationError("Only a bonus can be a percentage.", field="kind")


@transaction.atomic
def create_adjustment(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)
    *,
    teacher_id: int,
    kind: str,
    effective_on: date,
    reason: str,
    by,
    amount_minor: int | None = None,
    percent_bp: int | None = None,
) -> PayAdjustment:
    """A bonus or a deduction for a teacher by User id, in their current
    `pay_currency`: a fixed amount, or (slice B4b I-1) a bonus of
    ``percent_bp`` of the month's gross."""
    teacher = rules.teacher_of(teacher_id)
    adjustment = PayAdjustment(
        teacher=teacher,
        kind=kind,
        amount_minor=amount_minor,
        percent_bp=percent_bp,
        currency=teacher.pay_currency,
        effective_on=effective_on,
        reason=reason.strip(),
        created_by=by,
    )
    check_form(adjustment)
    rules.save(adjustment)
    return adjustment


@transaction.atomic
def update_adjustment(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)
    adjustment: PayAdjustment,
    *,
    kind=UNSET,
    amount_minor=UNSET,
    percent_bp=UNSET,
    effective_on=UNSET,
    reason=UNSET,
) -> PayAdjustment:
    """Only while unused (409 `payroll.adjustment_used`); saved in the
    teacher's current `pay_currency`. A keyword left out is unchanged and
    None clears its field (slice B4b §4.2); the row after the change must
    pass `check_form`. Only the edited columns are written."""
    locked = lock(adjustment)
    refuse_if_used(locked)
    given = {
        "kind": kind,
        "amount_minor": amount_minor,
        "percent_bp": percent_bp,
        "effective_on": effective_on,
        "reason": reason,
    }
    edits = {name: value for name, value in given.items() if value is not UNSET}
    if isinstance(edits.get("reason"), str):
        edits["reason"] = edits["reason"].strip()
    for name, value in edits.items():
        setattr(locked, name, value)
    check_form(locked)
    locked.currency = locked.teacher.pay_currency
    rules.save(locked, update_fields=[*edits, "currency"])
    return locked
```

The `kind`, `amount_minor`, … parameters carry no annotation because their default is the sentinel; ruff accepts that.

- [ ] **Step 4: The pending filter and its call sites**

In `rules.py`, replace both functions:

```python
def pending_adjustments(last: date, *, percentages: bool) -> QuerySet[PayAdjustment]:
    """Adjustments no issued payslip has used, effective on or before
    ``last``, in their teacher's current ``pay_currency`` (spec §4.1).
    Slice B4b I-3: percentage bonuses only while ``percentages``
    (`incentives_deductions` on); otherwise they wait, unused."""
    pending = PayAdjustment.objects.filter(
        payslip__isnull=True,
        effective_on__lte=last,
        currency=F("teacher__pay_currency"),
    )
    return pending if percentages else pending.filter(percent_bp__isnull=True)


def other_currency_adjustments(
    last: date, *, percentages: bool
) -> QuerySet[PayAdjustment]:
    """The same pending adjustments, but in a currency their teacher is no
    longer paid in: left out of every payslip and reported (spec §4.1).
    Percentages are left out of the warning too while they are off (I-3)."""
    other = PayAdjustment.objects.filter(
        payslip__isnull=True, effective_on__lte=last
    ).exclude(currency=F("teacher__pay_currency"))
    return other if percentages else other.filter(percent_bp__isnull=True)
```

In `build.py`, `_adjustment_lines` gains `pay` and filters with it (Task 4 computes the percentage amounts; until then no test builds with `percentages` on):

```python
def _adjustment_lines(teacher, last, language, pay) -> list[Line]:
    pending = (
        rules.pending_adjustments(last, percentages=pay.percentages)
        .filter(teacher=teacher, currency=teacher.pay_currency)
        .order_by("effective_on", "id")
    )
    ...  # the comprehension is unchanged
```

and `build()` calls `_adjustment_lines(teacher, last, language, pay)`.

In `payslips.py`:

```python
def _pending_teacher_ids(last, pay) -> set[int]:
    """TeacherProfile ids with a pending adjustment in the month: one query,
    with the same filter as `build` (plan D3; B4b I-3)."""
    return set(
        rules.pending_adjustments(last, percentages=pay.percentages)
        .order_by()
        .values_list("teacher_id", flat=True)
        .distinct()
    )


def _other_currency_teachers(last, pay) -> list:
    adjustments = rules.other_currency_adjustments(
        last, percentages=pay.percentages
    ).select_related("teacher__user")
    users = {a.teacher.user_id: a.teacher.user for a in adjustments}
    return _by_name(users.values())
```

- `generate()` calls `_pending_teacher_ids(last, pay)` and `_other_currency_teachers(last, pay)` with the `pay` Plan 46 already reads there.
- Trunk tests that call the old signatures (an expected change):
  - `test_build.py::test_a_pay_currency_change_drops_old_rates_and_adjustments` calls `rules.other_currency_adjustments(date(2026, 6, 30))`; it becomes `rules.other_currency_adjustments(date(2026, 6, 30), percentages=False)`.
  - `test_generate.py`'s `phantom` fixture patches `_pending_teacher_ids` with `lambda last: found(last) | {…}`; it becomes `lambda last, pay: found(last, pay) | {…}`.
- In `issue()`, move `pay = effective_settings()` to just after the `payroll.month_not_over` check, before the adjustment lock (plan R4), and lock with `rules.pending_adjustments(last, percentages=pay.percentages)`. The `build(..., settings=pay)` call is unchanged.

- [ ] **Step 5: The seed**

Rewrite `backend/etqan/tenants/seeds/b4.py`, keeping Plan 46's student-rate body and its `_user(role, name)` lookup exactly as Plan 46 wrote them. Trunk's `_user` is defined above `seed_b4` and uses `identity_services` (kept in the import block below); keep `_user` where it is:

```python
"""Phase B4 demo data. Slice B4a: one per-student rate. Slice B4b: one
pending 5 % bonus for Ustadh Bilal, effective last month; it stays pending,
shown as "5 %", while `incentives_deductions` is off. Demo academy only;
idempotent; switches stay off; no fixed salary is seeded."""

from datetime import timedelta

from django.utils import timezone

from etqan.identity import services as identity_services
from etqan.payroll import services as payroll_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

PEOPLE = {"demo": ("Ustadh Bilal", "Yusuf Omar")}
RATE = 1500  # minor units of the teacher's pay currency
BONUS_BP = 500  # 5 %


def seed_b4(subdomain: str) -> None:
    people = PEOPLE.get(subdomain)
    if people is None:
        return
    _student_rate(people)
    _percentage_bonus(people[0])


def _student_rate(people) -> None:
    """Slice B4a (Plan 46), unchanged."""
    if payroll_services.student_rates_queryset().exists():
        return
    teacher, student = (
        _user(role, name)
        for role, name in zip(("teacher", "student"), people, strict=True)
    )
    if teacher is None or student is None:
        print("skip: B4 student rate — seeded people not found")  # noqa: T201
        return
    try:
        payroll_services.create_student_rate(
            teacher_id=teacher.id, student_id=student.id, hourly_rate_minor=RATE
        )
    except (ValidationError, ConflictError) as exc:
        print(f"skip: B4 student rate — {exc}")  # noqa: T201


def _percentage_bonus(name: str) -> None:
    """Slice B4b §7: made through the service, which leaves the switch to the
    request (plan 54 R2), so it is pending while the switch is off."""
    if (
        payroll_services.adjustments_queryset()
        .filter(percent_bp__isnull=False)
        .exists()
    ):
        return
    teacher = _user("teacher", name)
    if teacher is None:
        print("skip: B4 percentage bonus — seeded teacher not found")  # noqa: T201
        return
    first = timezone.localdate().replace(day=1)
    try:
        payroll_services.create_adjustment(
            teacher_id=teacher.id,
            kind="bonus",
            amount_minor=None,
            percent_bp=BONUS_BP,
            effective_on=(first - timedelta(days=1)).replace(day=15),
            reason="Monthly incentive",
            by=None,
        )
    except ValidationError as exc:
        print(f"skip: B4 percentage bonus — {exc}")  # noqa: T201
```

`_user` stays as Plan 46 defined it (above `seed_b4` in trunk).

- [ ] **Step 6: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll etqan/tenants/tests/test_seed_b4.py`, then `just _stack-manage seed_dev` twice.
Expected: PASS. Every Plan 7 adjustment test passes unchanged (`test_an_unused_adjustment_is_edited_in_the_current_currency` still sees one `FOR UPDATE`). The second seed run adds nothing for B4.

- [ ] **Step 7: Commit**

```bash
git -C $W/backend add etqan/payroll/services/adjustments.py etqan/payroll/services/rules.py etqan/payroll/services/build.py etqan/payroll/services/payslips.py etqan/payroll/tests/conftest.py etqan/payroll/tests/test_build.py etqan/payroll/tests/test_generate.py etqan/payroll/tests/test_percentages.py etqan/tenants/seeds/b4.py etqan/tenants/tests/test_seed_b4.py
git -C $W/backend commit -m "feat(payroll): percentage bonuses, UNSET edits, pending filter, demo seed (B4b I-1..I-3)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Build — the fixed salary and percentage bonuses

**Files:**
- Modify: `backend/etqan/payroll/services/build.py`
- Modify: `backend/etqan/payroll/services/rules.py` (`percent_text`, `adjustment_amount`)
- Test: `backend/etqan/payroll/tests/test_build_b4b.py` (new)

**Interfaces:**
- Consumes: `rules.counting_fixed_salary` (Task 2); `pending_adjustments(…, percentages=)` (Task 3); Plan 46's `regroup`, `MEMBER`, `PER_CLASS`, `effective_settings`.
- Produces:
  - `rules.percent_text(percent_bp) -> str`, `rules.adjustment_amount(adjustment, gross_minor) -> int`;
  - `build` per spec §4.1 steps 1–4, 6 and 7: the `fixed` line first, session lines zeroed in a fixed-salary month, percentage lines of the gross, and the new `missing_rate` rule.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_build_b4b.py`:

```python
"""Slice B4b §4.1: a fixed salary (F-1, F-2) and percentage bonuses (I-2) in
build, with the line order fixed → sessions → adjustments."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.academy import services as academy_services
from etqan.payroll import services
from etqan.payroll.models import Payslip
from etqan.payroll.services import rules
from etqan.payroll.services.build import build
from etqan.payroll.services.settings import update_settings
from etqan.payroll.tests.conftest import adjust
from etqan.payroll.tests.conftest import fixed_salary
from etqan.payroll.tests.conftest import june_group
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import pay_in
from etqan.payroll.tests.conftest import percent_bonus
from etqan.payroll.tests.conftest import set_rate
from etqan.scheduling.tests.conftest import make_student

JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)
JUNE_1 = date(2026, 6, 1)
JUNE_15 = date(2026, 6, 15)


@pytest.fixture(autouse=True)
def english(db):
    """Copied text in English: the test academy's default language is Arabic."""
    academy_services.update_settings(default_language="en")


@pytest.fixture
def sessions(world, clock):
    found = june_sessions(world)
    clock.set(JULY_FIRST)
    return found


@pytest.fixture
def percentages_on(set_features):
    set_features(incentives_deductions=True)


@pytest.fixture
def fixed_on(set_features):
    set_features(fixed_teacher_salary=True)


def june(teacher):
    teacher.teacher_profile.refresh_from_db()
    return build(teacher.teacher_profile, 2026, 6)


@pytest.mark.parametrize(
    ("bp", "text"),
    [(1250, "12.5"), (1000, "10"), (1205, "12.05"), (5, "0.05"), (10000, "100")],
)
def test_a_percentage_reads_without_trailing_zeros(bp, text):
    assert rules.percent_text(bp) == text


def test_a_percentage_is_a_share_of_the_weighted_gross(
    world, sessions, rules_on, percentages_on
):
    update_settings(by=None, student_absent_pay_bp=5000)
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    mark(sessions[1], world.teacher, student="absent")
    percent_bonus(world.teacher, 1000, on=JUNE_15, reason="Target")
    adjust(world.teacher, "deduction", 100, on=JUNE_15)
    built = june(world.teacher)
    assert built.gross_minor == 750 + 375
    share = next(
        line
        for line in built.lines
        if line.kind == "adjustment" and line.amount_minor > 0
    )
    assert share.amount_minor == 113  # 10 % of 1125 = 112.5 → 113
    assert share.description == "Bonus — 10 % — Target"
    assert (built.bonuses_minor, built.deductions_minor, built.net_minor) == (
        113,
        100,
        1138,
    )


def test_a_percentage_is_copied_in_the_academys_language(
    world, sessions, percentages_on
):
    academy_services.update_settings(default_language="ar")
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    percent_bonus(world.teacher, 1250, on=JUNE_15, reason="هدف")
    (share,) = [line for line in june(world.teacher).lines if line.kind == "adjustment"]
    assert share.description == "مكافأة — 12.5 ٪ — هدف"


def test_a_percentage_of_nothing_is_no_line_and_stays_pending(
    world, sessions, percentages_on, admin
):
    set_rate(world.teacher, 1000)
    share = percent_bonus(world.teacher, 1000, on=JUNE_15)
    adjust(world.teacher, "bonus", 500, on=JUNE_15)
    built = june(world.teacher)
    assert built.gross_minor == 0
    assert share.pk not in built.adjustment_ids
    services.generate(2026, 6)
    services.issue(Payslip.objects.get(), by=admin)
    share.refresh_from_db()
    assert share.payslip is None


def test_a_percentage_is_used_at_issue(world, sessions, percentages_on, admin):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    share = percent_bonus(world.teacher, 2000, on=JUNE_15)
    services.generate(2026, 6)
    payslip = services.issue(Payslip.objects.get(), by=admin)
    share.refresh_from_db()
    assert share.payslip_id == payslip.pk
    assert payslip.bonuses_minor == 150


def test_a_fixed_salary_month_pays_the_fixed_line_and_lists_sessions_at_0(
    world, sessions, fixed_on, percentages_on
):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    mark(sessions[1], world.teacher)
    fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    percent_bonus(world.teacher, 1250, on=JUNE_15)
    built = june(world.teacher)
    assert [line.kind for line in built.lines] == [
        "fixed",
        "session",
        "session",
        "adjustment",
    ]
    fixed = built.lines[0]
    assert (fixed.amount_minor, fixed.description, fixed.session_id) == (
        50000,
        "Fixed monthly salary",
        None,
    )
    paid = built.lines[1:3]
    assert [line.session_id for line in paid] == [sessions[0].pk, sessions[1].pk]
    assert {(line.amount_minor, line.rate_minor, line.pay_bp) for line in paid} == {
        (0, None, 10000)
    }
    assert built.gross_minor == 50000
    assert built.bonuses_minor == 6250  # 12.5 % of the fixed salary


def test_no_rate_is_no_missing_rate_in_a_fixed_salary_month(
    world, sessions, fixed_on
):
    mark(sessions[0], world.teacher)
    fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    assert june(world.teacher).missing_rate is False


def test_a_fixed_salary_counts_from_its_month_in_the_current_currency(
    world, sessions, fixed_on
):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    row = fixed_salary(world.teacher, 50000, starts_on=date(2026, 7, 1))
    assert [line.kind for line in june(world.teacher).lines] == ["session"]
    services.update_fixed_salary(row, starts_on=JUNE_1)
    assert june(world.teacher).lines[0].kind == "fixed"
    pay_in(world.teacher, "EGP")
    built = june(world.teacher)
    assert "fixed" not in {line.kind for line in built.lines}
    assert built.missing_rate is True  # the USD rate no longer counts either


def test_a_stored_fixed_salary_is_ignored_while_its_switch_is_off(world, sessions):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    built = june(world.teacher)
    assert [line.kind for line in built.lines] == ["session"]
    assert built.gross_minor == 750


def test_per_class_then_the_fixed_salary(
    world, clock, bundles_on, rules_on, fixed_on
):
    classes = june_group(world, make_student("Zaid"))
    clock.set(JULY_FIRST)
    update_settings(by=None, group_pay="per_class")
    for row in classes[0]:
        mark(row, world.teacher)
    fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    built = june(world.teacher)
    roles = [line.group_role for line in built.lines if line.kind == "session"]
    assert roles == ["carrier", "member"]
    assert (built.gross_minor, built.missing_rate) == (50000, False)
```

The academy's language is switched with `academy_services.update_settings(default_language=…)`, as in trunk's `test_build.py::test_copied_text_is_in_the_academys_language`. The autouse `english` fixture makes this file's copied text English (the test academy defaults to Arabic); the Arabic test switches back to `ar` itself.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_build_b4b.py`
Expected: FAIL. `rules.percent_text` is missing, there is no `fixed` line, and a percentage bonus raises `TypeError` (`amount_minor` is None).

- [ ] **Step 3: `rules.py`**

```python
def percent_text(percent_bp: int) -> str:
    """Slice B4b I-2: basis points as a percentage without trailing zeros,
    in integers (1250 → "12.5", 1000 → "10", 5 → "0.05")."""
    whole, rest = divmod(percent_bp, 100)
    return str(whole) if rest == 0 else f"{whole}.{rest:02d}".rstrip("0")


def adjustment_amount(adjustment, gross_minor: int) -> int:
    """Slice B4b I-2: a fixed adjustment's amount, or a percentage bonus's
    share of ``gross_minor``, rounded half up once (B4-4)."""
    if adjustment.percent_bp is None:
        return adjustment.amount_minor
    return round_half_up(gross_minor * adjustment.percent_bp, FULL_BP)
```

- [ ] **Step 4: `build.py`**

Add the constants and helpers, replace `describe_adjustment` and `_adjustment_lines`, and replace `build`:

```python
FIXED = PayslipLine.Kind.FIXED
# Slice B4b: copied text of the new lines, in the academy's language (plan R5).
FIXED_SALARY = {"en": "Fixed monthly salary", "ar": "الراتب الشهري الثابت"}
PERCENT_SIGN = {"en": "%", "ar": "٪"}


def describe_adjustment(adjustment: PayAdjustment, language: str) -> str:
    """ "{Bonus|Deduction} — {reason}", the kind in ``language``; a
    percentage bonus (slice B4b I-2) reads "Bonus — {p} % — {reason}"."""
    suffix = _suffix(language)
    kind = KIND_NAMES[suffix][adjustment.kind]
    if adjustment.percent_bp is None:
        return f"{kind} — {adjustment.reason}"
    percent = f"{rules.percent_text(adjustment.percent_bp)} {PERCENT_SIGN[suffix]}"
    return f"{kind} — {percent} — {adjustment.reason}"


def _adjustment_lines(teacher, last, language, pay, gross: int) -> list[Line]:
    """Pending adjustments, oldest first. A percentage bonus is its share of
    ``gross`` (I-2); a share of 0 makes no line, so the adjustment stays
    pending for the month that finally uses it."""
    pending = (
        rules.pending_adjustments(last, percentages=pay.percentages)
        .filter(teacher=teacher, currency=teacher.pay_currency)
        .order_by("effective_on", "id")
    )
    lines = []
    for adjustment in pending:
        amount = rules.adjustment_amount(adjustment, gross)
        if amount == 0:
            continue
        lines.append(
            Line(
                kind=ADJUSTMENT,
                adjustment_id=adjustment.pk,
                description=describe_adjustment(adjustment, language),
                amount_minor=amount
                if adjustment.kind == PayAdjustment.Kind.BONUS
                else -amount,
            )
        )
    return lines


def _fixed_month(teacher, first, language, pay, sessions):
    """Slice B4b F-2: ``(fixed lines, session lines)``. A counting fixed
    salary is one line for the full amount, and every session line is then
    listed at 0 with no rate (``pay_bp`` kept). Otherwise nothing changes."""
    salary = rules.counting_fixed_salary(teacher, first, pay)
    if salary is None:
        return [], sessions
    fixed = Line(
        kind=FIXED,
        description=FIXED_SALARY[_suffix(language)],
        amount_minor=salary.monthly_minor,
    )
    return [fixed], [
        replace(line, amount_minor=0, rate_minor=None) for line in sessions
    ]


def build(teacher, year: int, month: int, settings=None) -> Built:
    """(Keep Plan 7's and Plan 46's docstring, and add:) Slice B4b §4.1: a
    counting fixed salary (F-1) is a `fixed` line first and zeroes the session
    lines (F-2); gross is the session lines plus that line; a percentage bonus
    is a share of gross (I-2); `missing_rate` ignores member lines and every
    session line of a fixed-salary month."""
    pay = settings if settings is not None else effective_settings()
    first, last = rules.month_bounds(year, month)
    language = academy_services.get_settings().default_language
    sessions = _session_lines(teacher, first, last, language, pay)
    if pay.group_pay == PER_CLASS:
        sessions = regroup(sessions, language)
    fixed, sessions = _fixed_month(teacher, first, language, pay, sessions)
    gross = sum(line.amount_minor for line in (*fixed, *sessions))
    adjustments = _adjustment_lines(teacher, last, language, pay, gross)
    bonuses = sum(line.amount_minor for line in adjustments if line.amount_minor > 0)
    deductions = -sum(
        line.amount_minor for line in adjustments if line.amount_minor < 0
    )
    return Built(
        currency=teacher.pay_currency,
        lines=(*fixed, *sessions, *adjustments),
        gross_minor=gross,
        bonuses_minor=bonuses,
        deductions_minor=deductions,
        net_minor=gross + bonuses - deductions,
        missing_rate=not fixed
        and any(
            line.rate_minor is None and line.group_role != MEMBER for line in sessions
        ),
    )
```

`replace` is already imported (Plan 46). `Built.session_ids` keeps reading `kind == SESSION`, so a fixed-salary month's zero lines are still locked at issue (F-2). The `fixed` line has no session or adjustment id.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`
Expected: PASS. Plan 7's and Plan 46's build tests are unchanged.

- [ ] **Step 6: Commit**

```bash
git -C $W/backend add etqan/payroll/services/build.py etqan/payroll/services/rules.py etqan/payroll/tests/test_build_b4b.py
git -C $W/backend commit -m "feat(payroll): fixed-salary line and percentage bonuses in build (B4b F-2, I-2)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Build — report deductions and the counters

**Files:**
- Modify: `backend/etqan/payroll/services/build.py`
- Modify: `backend/etqan/payroll/services/rules.py` (`REPORT_OWED`, `TEACHER_AWAY`)
- Modify: `backend/etqan/payroll/services/payslips.py` (`write`)
- Test: `backend/etqan/payroll/tests/test_report_deductions.py` (new)

**Interfaces:**
- Consumes: `scheduling_services.missing_reports(now=)`, `payroll_sessions`, `write_report`; `payroll.clock.now`; `PaySettings.report_deduction_bp`, `.session_reports` (Task 2).
- Produces:
  - `Built.reports_sent`, `.reports_missing`, `.teacher_absences`;
  - `report` lines after the adjustment lines (R-3), counted in `deductions_minor`;
  - `write()` copies the three counters onto the payslip.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_report_deductions.py`:

```python
"""Slice B4b R-2…R-4: missing-report deductions (one per session, one per
class), the 24-hour window, and the payslip counters."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

import pytest

from etqan.academy import services as academy_services
from etqan.payroll import services
from etqan.payroll.models import Payslip
from etqan.payroll.services.build import build
from etqan.payroll.services.settings import update_settings
from etqan.payroll.tests.conftest import adjust
from etqan.payroll.tests.conftest import fixed_salary
from etqan.payroll.tests.conftest import june_group
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import set_rate
from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_student

JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)
JUNE_15 = date(2026, 6, 15)


@pytest.fixture(autouse=True)
def english(db):
    """Copied text in English: the test academy's default language is Arabic."""
    academy_services.update_settings(default_language="en")


@pytest.fixture
def sessions(world, clock):
    found = june_sessions(world)
    clock.set(JULY_FIRST)
    return found


@pytest.fixture
def reports_on(set_features):
    """Half a session's pay for a missing report (`session_reports` is on by
    default)."""
    set_features(payroll_rules=True, report_deductions=True)
    update_settings(by=None, report_deduction_bp=5000)


def june(teacher):
    teacher.teacher_profile.refresh_from_db()
    return build(teacher.teacher_profile, 2026, 6)


def report(session, by):
    return scheduling_services.write_report(
        session, by=by, behaviour=4, participation=4
    )


def kinds(built):
    return [line.kind for line in built.lines]


def test_a_missing_report_takes_its_share_of_the_session(
    world, sessions, reports_on
):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    mark(sessions[1], world.teacher)
    report(sessions[1], world.teacher)
    adjust(world.teacher, "bonus", 500, on=JUNE_15)
    built = june(world.teacher)
    assert kinds(built) == ["session", "session", "adjustment", "report"]
    owed = built.lines[-1]
    assert (owed.session_id, owed.amount_minor) == (sessions[0].pk, -375)
    assert owed.description == f"Missing report — {built.lines[0].description}"
    assert (
        built.gross_minor,
        built.bonuses_minor,
        built.deductions_minor,
        built.net_minor,
    ) == (1500, 500, 375, 1625)


def test_a_report_written_before_issue_removes_the_deduction(
    world, sessions, reports_on, admin
):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    services.generate(2026, 6)
    assert Payslip.objects.get().deductions_minor == 375
    report(sessions[0], world.teacher)
    payslip = services.issue(Payslip.objects.get(), by=admin)
    assert payslip.deductions_minor == 0
    assert not payslip.lines.filter(kind="report").exists()


def test_the_months_last_evening_waits_24_hours(
    world, sessions, reports_on, admin, clock
):
    set_rate(world.teacher, 1000)
    late = hand_session(
        sessions[0].subscription, occurs_on=date(2026, 6, 30), start=time(20, 0)
    )
    mark(late, world.teacher)  # ended 20:45 on 30 June; it is 1 July, 09:00
    services.generate(2026, 6)
    assert not Payslip.objects.get().lines.filter(kind="report").exists()
    clock.set(datetime(2026, 7, 1, 21, tzinfo=UTC))  # over 24 hours since
    payslip = services.issue(Payslip.objects.get(), by=admin)
    assert list(
        payslip.lines.filter(kind="report").values_list("session_id", flat=True)
    ) == [late.pk]


def test_per_class_one_line_in_proportion(world, clock, bundles_on, reports_on):
    classes = june_group(world, make_student("Zaid"), make_student("Omar"))
    clock.set(JULY_FIRST)
    update_settings(by=None, group_pay="per_class")
    set_rate(world.teacher, 1000)
    for row in classes[0]:
        mark(row, world.teacher)
    report(classes[0][0], world.teacher)
    built = june(world.teacher)
    carrier = next(line for line in built.lines if line.group_role == "carrier")
    (owed,) = [line for line in built.lines if line.kind == "report"]
    # round_half_up(750 x 5000 x 2, 10000 x 3) = 250
    assert (owed.session_id, owed.amount_minor) == (carrier.session_id, -250)
    assert owed.description == f"Missing reports (2 of 3) — {carrier.description}"


def test_no_deduction_on_a_fixed_salary_months_sessions(
    world, sessions, reports_on, set_features
):
    set_features(fixed_teacher_salary=True)
    mark(sessions[0], world.teacher)
    fixed_salary(world.teacher, 50000, starts_on=date(2026, 6, 1))
    built = june(world.teacher)
    assert "report" not in kinds(built)
    assert built.reports_missing == 1


def test_a_share_of_0_makes_no_line(world, sessions, set_features):
    set_features(payroll_rules=True, report_deductions=True)
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    assert kinds(june(world.teacher)) == ["session"]


def test_report_deductions_count_in_the_negative_net_refusal(
    world, sessions, reports_on, admin
):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    adjust(world.teacher, "deduction", 500, on=JUNE_15)
    services.generate(2026, 6)
    payslip = Payslip.objects.get()
    assert payslip.net_minor == 750 - 500 - 375
    with pytest.raises(ConflictError) as caught:
        services.issue(payslip, by=admin)
    assert caught.value.code == "payroll.negative_net"


def test_the_counters(world, sessions, admin):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    report(sessions[0], world.teacher)  # sent
    mark(sessions[1], world.teacher)  # not sent
    mark(sessions[2], world.teacher, student="absent")  # owes none
    mark(sessions[3], world.teacher, teacher="absent")  # an absence
    mark(sessions[4], world.teacher, teacher="excused")  # an absence
    scheduling_services.place_at_disposal(sessions[5], by=admin)
    scheduling_services.mark_attendance(
        sessions[5], by=admin, teacher_attendance="absent"
    )  # an absence
    built = june(world.teacher)
    assert (built.reports_sent, built.reports_missing, built.teacher_absences) == (
        1,
        1,
        3,
    )
    services.generate(2026, 6)
    payslip = Payslip.objects.get()
    assert (
        payslip.reports_sent,
        payslip.reports_missing,
        payslip.teacher_absences,
    ) == (1, 1, 3)


def test_report_counters_are_null_while_session_reports_is_off(
    world, sessions, set_features
):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    mark(sessions[3], world.teacher, teacher="absent")
    set_features(session_reports=False)
    built = june(world.teacher)
    assert (built.reports_sent, built.reports_missing, built.teacher_absences) == (
        None,
        None,
        1,
    )
```

Trunk's `place_at_disposal(session, *, reason="", by=None)` takes a scheduled session whose student attendance is not set (B2a A-11) and asks no switch, and `mark_attendance` then accepts its teacher attendance (only its student attendance is refused), so `test_the_counters` needs no `disposal_status`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_report_deductions.py`
Expected: FAIL. There are no `report` lines and `Built` has no `reports_sent`.

- [ ] **Step 3: `rules.py`**

```python
# Slice B4b R-4: a session that owes a report (P1 FLOW-005), and a month row
# the teacher missed (absent, or excused by the teacher).
REPORT_OWED = Q(
    status="completed",
    student_attendance="present",
    teacher_attendance__in=PAYING_TEACHER_ATTENDANCE,
)
TEACHER_AWAY = Q(
    status__in=("completed", "at_disposal"),
    teacher_attendance__in=("absent", "excused"),
)
```

- [ ] **Step 4: `build.py`**

Import `from etqan.payroll import clock`. Add to `Built`, after `missing_rate`:

```python
    # Slice B4b R-4: stored on the payslip at build.
    reports_sent: int | None = None
    reports_missing: int | None = None
    teacher_absences: int | None = None
```

Add:

```python
REPORT = PayslipLine.Kind.REPORT
MISSING_REPORT = {
    "en": "Missing report — {description}",
    "ar": "تقرير غير مرسل — {description}",
}
MISSING_REPORTS = {
    "en": "Missing reports ({missing} of {rows}) — {description}",
    "ar": "تقارير غير مرسلة ({missing} من {rows}) — {description}",
}


def _missing_report_ids(sessions, pay) -> set[int]:
    """Slice B4b R-2: the session lines (members included) whose session owes
    a report it does not have yet. This is scheduling's rule, intersected with
    this month's lines in one query. Empty while `session_reports` is off."""
    if not pay.session_reports or not sessions:
        return set()
    return set(
        scheduling_services.missing_reports(now=clock.now())
        .filter(pk__in=[line.session_id for line in sessions])
        .values_list("pk", flat=True)
    )


def _report_lines(sessions, missing, bp, language) -> list[Line]:
    """Slice B4b R-3: each missing report takes ``bp`` of its line's amount.
    Per class (B4a A-6), the carrier's line takes the class's share once:
    ``round_half_up(amount × bp × missing rows, 10000 × class rows)``. A
    deduction of 0 makes no line; a fixed-salary month's lines carry 0."""
    if bp == 0 or not missing:
        return []
    suffix = _suffix(language)
    rows_of: dict[str, list[Line]] = {}
    for line in sessions:
        if line.group_role:
            rows_of.setdefault(line.group_key, []).append(line)
    lines = []
    for line in sessions:
        if line.group_role == CARRIER:
            rows = rows_of[line.group_key]
            owed = sum(1 for row in rows if row.session_id in missing)
            amount = rules.round_half_up(
                line.amount_minor * bp * owed, rules.FULL_BP * len(rows)
            )
            description = MISSING_REPORTS[suffix].format(
                missing=owed, rows=len(rows), description=line.description
            )
        elif not line.group_role and line.session_id in missing:
            amount = rules.round_half_up(line.amount_minor * bp, rules.FULL_BP)
            description = MISSING_REPORT[suffix].format(description=line.description)
        else:
            continue
        if amount:
            lines.append(
                Line(
                    kind=REPORT,
                    session_id=line.session_id,
                    description=description,
                    amount_minor=-amount,
                )
            )
    return lines


def _counters(teacher, first, last, sessions, missing, pay) -> dict:
    """Slice B4b R-4 (plan R7). Absences are always counted; the report
    counters are None while `session_reports` is off."""
    month = scheduling_services.payroll_sessions(first, last).filter(teacher=teacher)
    absences = month.filter(rules.TEACHER_AWAY).count()
    if not pay.session_reports:
        return {
            "reports_sent": None,
            "reports_missing": None,
            "teacher_absences": absences,
        }
    ids = [line.session_id for line in sessions]
    sent = (
        month.filter(rules.REPORT_OWED, pk__in=ids, report__isnull=False).count()
        if ids
        else 0
    )
    return {
        "reports_sent": sent,
        "reports_missing": len(missing),
        "teacher_absences": absences,
    }
```

Replace `build`'s body from `adjustments = …` to the end:

```python
    adjustments = _adjustment_lines(teacher, last, language, pay, gross)
    missing = _missing_report_ids(sessions, pay)
    reports = _report_lines(sessions, missing, pay.report_deduction_bp, language)
    bonuses = sum(line.amount_minor for line in adjustments if line.amount_minor > 0)
    deductions = -sum(
        line.amount_minor for line in (*adjustments, *reports) if line.amount_minor < 0
    )
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
        **_counters(teacher, first, last, sessions, missing, pay),
    )
```

Add "Report lines (R-3) come last and count as deductions" to `build`'s docstring. `CARRIER` is Plan 46's constant in this module. A `report` line has kind `report`, so `session_ids` and Plan 46's counters (which read `kind=session`) never count it.

- [ ] **Step 5: `write()` copies the counters**

In `payslips.write`, after `payslip.missing_rate = built.missing_rate`:

```python
    payslip.reports_sent = built.reports_sent
    payslip.reports_missing = built.reports_missing
    payslip.teacher_absences = built.teacher_absences
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git -C $W/backend add etqan/payroll/services/build.py etqan/payroll/services/rules.py etqan/payroll/services/payslips.py etqan/payroll/tests/test_report_deductions.py
git -C $W/backend commit -m "feat(payroll): missing-report deductions and payslip counters (B4b R-2..R-4)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Generate and issue — fixed-salary discovery, stale salaries, late rows, and the B4-2 regression

**Files:**
- Modify: `backend/etqan/payroll/services/payslips.py` (`GenerateResult`, `_fixed_teacher_ids`, `_stale_fixed_salary_teachers`, `_unpaid_rows`, `generate`)
- Test: `backend/etqan/payroll/tests/test_generate_b4b.py` (new)

**Interfaces:**
- Consumes: `identity_services.active_teachers()`; `rules.counting_fixed_salaries`, `stale_fixed_salaries`, `counting_fixed_salary` (Task 2); Plan 46's `_unpaid_rows(teacher, first, last, pay)`.
- Produces: `GenerateResult.stale_fixed_salary: list[User]`; F-3 discovery; F-4 late rows.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_generate_b4b.py`:

```python
"""Slice B4b §4.4, F-3, F-4 and the regression guarantee (B4-2, FT-2)."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.identity import services as identity_services
from etqan.payroll import services
from etqan.payroll.models import PayAdjustment
from etqan.payroll.models import Payslip
from etqan.payroll.services.build import build
from etqan.payroll.services.settings import update_settings
from etqan.payroll.tests.conftest import adjust
from etqan.payroll.tests.conftest import fixed_salary
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import pay_in
from etqan.payroll.tests.conftest import set_rate
from etqan.scheduling import services as scheduling_services

JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)
AUGUST_FIRST = datetime(2026, 8, 1, 9, tzinfo=UTC)
JUNE_1 = date(2026, 6, 1)
JUNE_15 = date(2026, 6, 15)


@pytest.fixture
def sessions(world, clock):
    found = june_sessions(world)
    clock.set(JULY_FIRST)
    return found


@pytest.fixture
def fixed_on(set_features):
    set_features(fixed_teacher_salary=True)


def june(teacher):
    teacher.teacher_profile.refresh_from_db()
    return build(teacher.teacher_profile, 2026, 6)


# ── Fixed salaries (F-3, F-4) ────────────────────────────────────────────────


def test_an_active_teacher_with_a_fixed_salary_gets_a_payslip_alone(
    world, sessions, fixed_on
):
    fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    assert services.generate(2026, 6).created == 1
    payslip = Payslip.objects.get()
    assert (payslip.gross_minor, payslip.net_minor) == (50000, 50000)
    assert [line.kind for line in payslip.lines.all()] == ["fixed"]


def test_not_before_its_start_month(world, sessions, fixed_on):
    fixed_salary(world.teacher, 50000, starts_on=date(2026, 7, 1))
    assert services.generate(2026, 6).created == 0


def test_an_inactive_teacher_needs_other_activity(world, sessions, fixed_on):
    fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    identity_services.deactivate(world.teacher, by=None)
    assert services.generate(2026, 6).created == 0
    adjust(world.teacher, "bonus", 100, on=JUNE_15)
    services.generate(2026, 6)
    lines = Payslip.objects.get().lines.all()
    assert [line.kind for line in lines] == ["fixed", "adjustment"]


def test_a_stale_currency_is_named_and_not_counted(world, sessions, fixed_on):
    fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    pay_in(world.teacher, "EGP")
    result = services.generate(2026, 6)
    assert (result.created, result.stale_fixed_salary) == (0, [world.teacher])


def test_no_stale_names_while_the_switch_is_off(world, sessions):
    fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    pay_in(world.teacher, "EGP")
    assert services.generate(2026, 6).stale_fixed_salary == []


def test_issue_locks_a_fixed_salary_months_sessions(
    world, sessions, fixed_on, admin
):
    mark(sessions[0], world.teacher)
    fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    services.generate(2026, 6)
    payslip = services.issue(Payslip.objects.get(), by=admin)
    sessions[0].refresh_from_db()
    assert sessions[0].payroll_locked
    assert payslip.net_minor == 50000


def test_late_rows_of_a_fixed_salary_month_are_not_reported(
    world, sessions, fixed_on, admin, clock
):
    mark(sessions[0], world.teacher)
    fixed_salary(world.teacher, 50000, starts_on=JUNE_1)
    services.generate(2026, 6)
    services.issue(Payslip.objects.get(), by=admin)
    clock.set(AUGUST_FIRST)
    mark(sessions[1], world.teacher)  # completed after June was issued
    assert services.generate(2026, 6).unpaid_sessions == []


# ── The regression guarantee (B4-2, FT-2) ────────────────────────────────────


def same(built, other) -> bool:
    keys = ("gross_minor", "bonuses_minor", "deductions_minor", "net_minor")
    return built.lines == other.lines and all(
        getattr(built, key) == getattr(other, key) for key in (*keys, "missing_rate")
    )


def b4a_month(world, sessions):
    """A month as B4a builds it: one session with its report missing, one
    with it written, a bonus and a deduction."""
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    mark(sessions[1], world.teacher)
    scheduling_services.write_report(
        sessions[1], by=world.teacher, behaviour=4, participation=4
    )
    adjust(world.teacher, "bonus", 500, on=JUNE_15)
    adjust(world.teacher, "deduction", 200, on=JUNE_15)
    built = june(world.teacher)
    assert [line.kind for line in built.lines] == [
        "session",
        "session",
        "adjustment",
        "adjustment",
    ]
    return built


def test_with_the_b4b_switches_off_nothing_moves(world, sessions, admin):
    """A stored report share, a stored fixed salary and a pending percentage
    written straight to the table change nothing while their switches are
    off, and issue leaves the percentage pending."""
    before = b4a_month(world, sessions)
    update_settings(by=None, report_deduction_bp=5000)
    fixed_salary(world.teacher, 99000, starts_on=JUNE_1)
    share = PayAdjustment.objects.create(
        teacher=world.teacher.teacher_profile,
        kind="bonus",
        amount_minor=None,
        percent_bp=1000,
        currency="USD",
        effective_on=JUNE_15,
        reason="Straight to the table",
    )
    assert same(june(world.teacher), before)
    services.generate(2026, 6)
    payslip = services.issue(Payslip.objects.get(), by=admin)
    assert (payslip.gross_minor, payslip.net_minor) == (1500, 1800)
    share.refresh_from_db()
    assert share.payslip is None


def test_switches_stored_true_before_the_slice_are_neutral(
    world, sessions, set_features
):
    """FT-2: switches stored true while unbuilt take effect with neutral
    defaults: a report share of 0, no fixed salary, no percentage."""
    before = b4a_month(world, sessions)
    set_features(
        payroll_rules=True,
        incentives_deductions=True,
        report_deductions=True,
        fixed_teacher_salary=True,
    )
    assert same(june(world.teacher), before)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_generate_b4b.py`
Expected: FAIL. A fixed salary alone brings no payslip, `GenerateResult` has no `stale_fixed_salary`, and the late row is reported. The two regression tests already pass: they pin Tasks 2–5, and that is expected.

- [ ] **Step 3: `payslips.py`**

`GenerateResult` gains, last:

```python
    # Slice B4b F-1: teachers whose fixed salary is in a currency they are no
    # longer paid in (left out of their payslip).
    stale_fixed_salary: list = field(default_factory=list)
```

Add:

```python
def _fixed_teacher_ids(first, pay) -> set[int]:
    """Slice B4b F-3: active teachers (at generate time) whose fixed salary
    counts for the month; each gets a payslip even with no other activity."""
    if not pay.fixed_salary:
        return set()
    active = [profile.pk for profile in identity_services.active_teachers()]
    return set(
        rules.counting_fixed_salaries(first)
        .filter(teacher_id__in=active)
        .values_list("teacher_id", flat=True)
    )


def _stale_fixed_salary_teachers(first, pay) -> list:
    """Slice B4b F-1 (plan R14): every teacher, active or not, whose fixed
    salary has started but is in an old currency."""
    if not pay.fixed_salary:
        return []
    rows = rules.stale_fixed_salaries(first).select_related("teacher__user")
    return _by_name(row.teacher.user for row in rows)
```

In Plan 46's `_unpaid_rows`, add first:

```python
    if rules.counting_fixed_salary(teacher, first, pay) is not None:
        # Slice B4b F-4: the fixed salary already pays the month.
        return False
```

`generate` becomes (keep Plan 7's docstring and add the slice's sentence):

```python
@transaction.atomic
def generate(year: int, month: int) -> GenerateResult:
    """(Plan 7's docstring.) Slice B4b: active teachers whose fixed salary
    counts are discovered too (F-3); late rows of a fixed-salary month are
    not reported (F-4); stale fixed salaries are named."""
    counter = numbering.hold()
    pay = effective_settings()
    first, last = rules.month_bounds(year, month)
    existing = {
        payslip.teacher_id: payslip
        for payslip in Payslip.objects.select_for_update()
        .filter(year=year, month=month)
        .order_by("pk")
    }
    paying = _paying_teacher_ids(first, last, pay)
    active = (
        paying | _pending_teacher_ids(last, pay) | _fixed_teacher_ids(first, pay)
    )
    teachers = identity_services.teacher_profiles_by_id(active)
    result = GenerateResult()
    missing = []
    unpaid = []
    for teacher_id in sorted(active):
        payslip = existing.get(teacher_id)
        teacher = teachers[teacher_id]
        if payslip is not None and payslip.status != DRAFT:
            # Issue locked every session it paid, so these were completed
            # after it: a correction for a later month (spec P7-4).
            if teacher_id in paying and _unpaid_rows(teacher, first, last, pay):
                unpaid.append(teacher.user)
            continue
        built = build(teacher, year, month, settings=pay)
        if not built.lines:
            # Its activity went between discovery and build (READ COMMITTED):
            # no line, so the teacher is inactive after all.
            if payslip is not None:
                payslip.delete()
                result.removed += 1
            continue
        if payslip is None:
            payslip = Payslip(
                number=numbering.take(counter), teacher=teacher, year=year, month=month
            )
            result.created += 1
        else:
            result.replaced += 1
        write(payslip, built)
        if built.missing_rate:
            missing.append(teacher.user)
    for teacher_id, payslip in existing.items():
        if teacher_id not in active and payslip.status == DRAFT:
            payslip.delete()
            result.removed += 1
    result.missing_rate = _by_name(missing)
    result.unpaid_sessions = _by_name(unpaid)
    result.other_currency = _other_currency_teachers(last, pay)
    result.stale_fixed_salary = _stale_fixed_salary_teachers(first, pay)
    return result
```

If ruff's `C901` fires on `generate`, move the loop body for one teacher into `_generate_one(teacher, payslip, …)`; never weaken a rule to satisfy it. The issue's negative-net refusal needs no change: report lines are in `deductions_minor`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`
Expected: PASS, including every Plan 7 generate test (`test_a_session_completed_after_issue_is_named_for_an_adjustment` still names the teacher, because no fixed salary counts there).

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/payroll/services/payslips.py etqan/payroll/tests/test_generate_b4b.py
git -C $W/backend commit -m "feat(payroll): fixed-salary discovery, stale salaries, late rows; B4-2 regression (B4b F-3, F-4)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The API — adjustments, settings, fixed salaries, payslip rows and the CSV

**Files:**
- Modify: `backend/etqan/payroll/api/serializers.py`
- Modify: `backend/etqan/payroll/api/payloads.py`
- Modify: `backend/etqan/payroll/api/views.py`
- Modify: `backend/etqan/payroll/api/urls.py`
- Modify: `backend/etqan/payroll/services/rules.py` (`payslips_queryset`: `report_lines`)
- Modify: `backend/etqan/access/tests/test_routes.py`
- Modify: `backend/etqan/payroll/tests/test_api.py`, `backend/etqan/payroll/tests/test_counts.py` (expected rows)
- Test: `backend/etqan/payroll/tests/test_api_b4b.py` (new)

**Interfaces:**
- Consumes: Tasks 2–6.
- Produces:
  - `GET/POST /api/v1/payroll/fixed-salaries/`, `PATCH/DELETE /api/v1/payroll/fixed-salaries/<id>/`. Row: `{id, teacher: {id, full_name}, monthly_minor, currency, starts_on, current, created_at, updated_at}`;
  - adjustment rows and bodies with `percent_bp`, and `amount_minor` nullable;
  - the settings row with `report_deduction_bp`;
  - payslip rows with `reports_sent`, `reports_missing`, `teacher_absences` and `report_deductions_minor`;
  - the generate result with `stale_fixed_salary`;
  - four CSV columns, last (plan R13).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_api_b4b.py`:

```python
"""Slice B4b §5: switches answer 404 or 400, the role matrix, shapes, the
CSV, query counts and isolation."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context

from etqan.payroll import services
from etqan.payroll.models import Payslip
from etqan.payroll.services.settings import update_settings
from etqan.payroll.tests.conftest import fixed_salary
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import pay_in
from etqan.payroll.tests.conftest import percent_bonus
from etqan.payroll.tests.conftest import set_rate
from etqan.scheduling.tests.conftest import make_teacher

P = "/api/v1/payroll/"
FIXED = f"{P}fixed-salaries/"
JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)


@pytest.fixture
def b4b_on(set_features):
    set_features(
        incentives_deductions=True,
        fixed_teacher_salary=True,
        payroll_rules=True,
        report_deductions=True,
    )


def body(world, **fields):
    return {
        "teacher": world.teacher.id,
        "kind": "bonus",
        "effective_on": "2026-06-15",
        "reason": "Target",
        **fields,
    }


def selects(captured):
    return [q for q in captured if q["sql"].lstrip().upper().startswith("SELECT")]


# ── Adjustments ──────────────────────────────────────────────────────────────


def test_a_percentage_needs_its_switch(world, api_for):
    response = api_for("admin").post(
        f"{P}adjustments/", body(world, percent_bp=1000), format="json"
    )
    assert response.status_code == 400
    assert "percent_bp" in response.json()


def test_a_percentage_bonus_round_trip(world, api_for, b4b_on):
    admin = api_for("admin")
    created = admin.post(f"{P}adjustments/", body(world, percent_bp=1000), format="json")
    assert created.status_code == 201, created.json()
    row = created.json()
    assert (row["percent_bp"], row["amount_minor"]) == (1000, None)
    url = f"{P}adjustments/{row['id']}/"
    fixed = admin.patch(url, {"percent_bp": None, "amount_minor": 500}, format="json")
    assert (fixed.json()["percent_bp"], fixed.json()["amount_minor"]) == (None, 500)
    back = admin.patch(url, {"percent_bp": 1250, "amount_minor": None}, format="json")
    assert (back.json()["percent_bp"], back.json()["amount_minor"]) == (1250, None)


@pytest.mark.parametrize(
    ("fields", "field"),
    [
        ({"amount_minor": None}, "amount_minor"),
        ({"amount_minor": 500, "percent_bp": 1000}, "amount_minor"),
        ({"kind": "deduction", "percent_bp": 1000}, "kind"),
        ({"percent_bp": 10001}, "percent_bp"),
        ({"percent_bp": 0}, "percent_bp"),
    ],
)
def test_bad_forms_are_400_on_their_field(world, api_for, b4b_on, fields, field):
    response = api_for("admin").post(
        f"{P}adjustments/", body(world, **fields), format="json"
    )
    assert response.status_code == 400
    assert field in response.json()


def test_a_pending_percentage_stays_editable_while_off(world, api_for):
    """I-3 / FT-4: its reason and date can change and it can be deleted;
    setting a percentage cannot."""
    share = percent_bonus(world.teacher, 1000, on=date(2026, 6, 15))
    admin = api_for("admin")
    url = f"{P}adjustments/{share.pk}/"
    edited = admin.patch(url, {"reason": "Ramadan"}, format="json")
    assert edited.status_code == 200
    assert (edited.json()["reason"], edited.json()["percent_bp"]) == ("Ramadan", 1000)
    refused = admin.patch(url, {"percent_bp": 1500}, format="json")
    assert refused.status_code == 400
    assert "percent_bp" in refused.json()
    assert admin.delete(url).status_code == 204


# ── Settings ─────────────────────────────────────────────────────────────────


def test_the_report_share_needs_its_switch(world, api_for, set_features):
    set_features(payroll_rules=True)
    admin = api_for("admin")
    assert admin.get(f"{P}settings/").json()["report_deduction_bp"] == 0
    refused = admin.patch(
        f"{P}settings/", {"report_deduction_bp": 5000}, format="json"
    )
    assert refused.status_code == 400
    assert "report_deduction_bp" in refused.json()
    set_features(report_deductions=True)
    saved = admin.patch(f"{P}settings/", {"report_deduction_bp": 5000}, format="json")
    assert saved.json()["report_deduction_bp"] == 5000


# ── Fixed salaries ───────────────────────────────────────────────────────────


def test_fixed_salaries_are_404_while_off(world, api_for):
    assert api_for("admin").get(FIXED).status_code == 404


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_people_outside_the_office_get_403(world, api_for, b4b_on, role):
    client = api_for(role)
    assert client.get(FIXED).status_code == 403
    response = client.post(
        FIXED, {"teacher": world.teacher.id, "monthly_minor": 1}, format="json"
    )
    assert response.status_code == 403


def test_a_fixed_salary_round_trip(world, api_for, b4b_on):
    admin = api_for("admin")
    created = admin.post(
        FIXED,
        {"teacher": world.teacher.id, "monthly_minor": 50000, "starts_on": "2026-06-17"},
        format="json",
    )
    assert created.status_code == 201, created.json()
    row = created.json()
    assert row["teacher"] == {"id": world.teacher.id, "full_name": world.teacher.full_name}
    assert (row["monthly_minor"], row["currency"], row["starts_on"], row["current"]) == (
        50000,
        "USD",
        "2026-06-01",
        True,
    )
    listed = admin.get(FIXED, {"teacher": world.teacher.id}).json()
    assert [r["id"] for r in listed] == [row["id"]]
    duplicate = admin.post(
        FIXED, {"teacher": world.teacher.id, "monthly_minor": 1}, format="json"
    )
    assert (duplicate.status_code, duplicate.json()["code"]) == (
        409,
        "payroll.fixed_salary_exists",
    )
    patched = admin.patch(f"{FIXED}{row['id']}/", {"monthly_minor": 60000}, format="json")
    assert (patched.json()["monthly_minor"], patched.json()["starts_on"]) == (
        60000,
        "2026-06-01",
    )
    pay_in(world.teacher, "EGP")
    assert admin.get(FIXED).json()[0]["current"] is False
    assert admin.delete(f"{FIXED}{row['id']}/").status_code == 204
    assert admin.get(FIXED).json() == []


def test_staff_need_the_rate_codes(world, staff_for, b4b_on):
    data = {"teacher": world.teacher.id, "monthly_minor": 50000}
    reader = staff_for("payroll_rate.view_any")
    assert reader.get(FIXED).status_code == 200
    assert reader.post(FIXED, data, format="json").status_code == 403
    writer = staff_for("payroll_rate.view_any", "payroll_rate.create")
    assert writer.post(FIXED, data, format="json").status_code == 201


def test_the_fixed_salary_list_costs_the_same_for_more_rows(world, api_for, b4b_on):
    admin = api_for("admin")
    fixed_salary(world.teacher, 1000)

    def queries():
        with CaptureQueriesContext(connection) as ctx:
            assert admin.get(FIXED).status_code == 200
        return len(selects(ctx.captured_queries))

    one = queries()
    for n in range(2):
        fixed_salary(make_teacher(f"T{n}"), 1000)
    assert queries() == one


def test_another_academys_fixed_salary_never_shows(world, api_for, b4b_on, tenants):
    with tenant_context(tenants.other):
        theirs = fixed_salary(make_teacher("Kareem"), 900)
    admin = api_for("admin")
    assert admin.get(FIXED).json() == []
    response = admin.patch(f"{FIXED}{theirs.pk}/", {"monthly_minor": 1}, format="json")
    assert response.status_code == 404


# ── Payslips and generate ────────────────────────────────────────────────────


def test_payslip_rows_carry_the_counters_and_report_deductions(
    world, clock, api_for, set_features
):
    sessions = june_sessions(world)
    clock.set(JULY_FIRST)
    set_features(payroll_rules=True, report_deductions=True)
    update_settings(by=None, report_deduction_bp=5000)
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    mark(sessions[1], world.teacher, teacher="absent")
    services.generate(2026, 6)
    admin = api_for("admin")
    (row,) = admin.get(f"{P}payslips/").json()["results"]
    keys = (
        "reports_sent",
        "reports_missing",
        "teacher_absences",
        "report_deductions_minor",
        "deductions_minor",
    )
    assert {key: row[key] for key in keys} == {
        "reports_sent": 0,
        "reports_missing": 1,
        "teacher_absences": 1,
        "report_deductions_minor": 375,
        "deductions_minor": 375,
    }
    response = admin.get(f"{P}payslips/", {"format": "csv"})
    header, line = response.content.decode("utf-8-sig").splitlines()[:2]
    assert header.endswith(
        "Reports sent,Reports not sent,Teacher absences,"
        "Report deductions (minor units)"
    )
    assert line.endswith(",0,1,1,375")


def test_a_payslip_from_before_b4b_has_null_counters(world, api_for):
    Payslip.objects.create(
        number="PAY-000009",
        teacher=world.teacher.teacher_profile,
        year=2026,
        month=5,
        currency="USD",
    )
    (row,) = api_for("admin").get(f"{P}payslips/").json()["results"]
    assert (
        row["reports_sent"],
        row["reports_missing"],
        row["teacher_absences"],
        row["report_deductions_minor"],
    ) == (None, None, None, 0)


def test_generate_names_stale_fixed_salaries(world, clock, api_for, b4b_on):
    clock.set(JULY_FIRST)
    fixed_salary(world.teacher, 50000, starts_on=date(2026, 6, 1))
    pay_in(world.teacher, "EGP")
    result = api_for("admin").post(
        f"{P}payslips/generate/", {"year": 2026, "month": 6}, format="json"
    ).json()
    assert result["stale_fixed_salary"] == [
        {"id": world.teacher.id, "full_name": world.teacher.full_name}
    ]
```

In `test_routes.py`, under `# Slice B4b.` in `ROUTES`:

```python
    # Slice B4b.
    ("GET", "/api/v1/payroll/fixed-salaries/", "payroll_rate.view_any"),
    ("POST", "/api/v1/payroll/fixed-salaries/", "payroll_rate.create"),
    ("PATCH", f"/api/v1/payroll/fixed-salaries/{N}/", "payroll_rate.update"),
    ("DELETE", f"/api/v1/payroll/fixed-salaries/{N}/", "payroll_rate.delete"),
```

In `FEATURES`, under `# Slice B4b.`:

```python
    # Slice B4b.
    **dict.fromkeys(
        (
            ("GET", "/api/v1/payroll/fixed-salaries/"),
            ("POST", "/api/v1/payroll/fixed-salaries/"),
            ("PATCH", f"/api/v1/payroll/fixed-salaries/{N}/"),
            ("DELETE", f"/api/v1/payroll/fixed-salaries/{N}/"),
        ),
        "fixed_teacher_salary",
    ),
```

In `FEATURE_WORDS`: `"/fixed-salaries/": "fixed_teacher_salary",  # B4b`.

Update the expected rows that now describe the B4b payload (an expected change):
- `test_api.py::test_the_csv_is_for_admins`: the header gains, at its end, `"Reports sent", "Reports not sent", "Teacher absences", "Report deductions (minor units)"`. Bilal's issued June row gains `"0", "2", "0", "0"`: both of his sessions owe a report and have none (it is 1 July, so both ended over 24 hours before), the share is 0 while `report_deductions` is off, and he missed none. "At its end" means after whatever trunk has at build time (B4c's two columns, if it merged first).
- `test_api.py::test_generate_answers_the_counts_and_names` is the one exact generate-result dict; trunk has no exact payslip-row or adjustment-row dict.
- `test_api.py`: every exact payslip-row dict gains `reports_sent`, `reports_missing`, `teacher_absences` and `report_deductions_minor`; every exact generate-result dict gains `"stale_fixed_salary": []`; every exact adjustment-row dict gains `"percent_bp": None`.
- Plan 46's `test_counts.py::test_the_csv_has_the_counter_columns` asserts `row.endswith(",1,0,0,0,0,1,0,0")`, which no longer holds once columns follow B4a's. Keep its meaning without depending on what comes after B4a's columns (B4c's two, if it merged first): parse the two lines with `csv.reader`, zip header with row, and assert the eight B4a counter columns by name (`Regular sessions` "1" … `Group members` "0") plus B4b's four (`Reports sent` "0", `Reports not sent` "0", `Teacher absences` "0", `Report deductions (minor units)` "0"): its one line's student was absent, so it owes no report.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_api_b4b.py etqan/access/tests/test_routes.py`
Expected: FAIL. `fixed-salaries/` is 404 for everyone, `percent_bp` is not accepted, and the route table names the missing handlers.

- [ ] **Step 3: Serializers**

Import `from etqan.platform import features`. Replace the two adjustment inputs, and add:

```python
def _percentage_switch(value):
    """Slice B4b I-3 (plan R2): setting a percentage needs
    `incentives_deductions`; clearing one (null) never does."""
    if value is not None and not features.enabled("incentives_deductions"):
        raise serializers.ValidationError("Percentage bonuses are switched off.")
    return value


class AdjustmentCreateInput(serializers.Serializer):
    teacher = _id()
    kind = serializers.ChoiceField(choices=PayAdjustment.Kind.choices)
    # Slice B4b I-1: exactly one of the two; the service checks the form.
    amount_minor = serializers.IntegerField(min_value=1, allow_null=True, default=None)
    percent_bp = serializers.IntegerField(
        min_value=1, max_value=10000, allow_null=True, default=None
    )
    effective_on = serializers.DateField()
    reason = serializers.CharField()

    def validate_percent_bp(self, value):
        return _percentage_switch(value)


class AdjustmentUpdateInput(serializers.Serializer):
    kind = serializers.ChoiceField(choices=PayAdjustment.Kind.choices, required=False)
    amount_minor = serializers.IntegerField(
        min_value=1, allow_null=True, required=False
    )
    percent_bp = serializers.IntegerField(
        min_value=1, max_value=10000, allow_null=True, required=False
    )
    effective_on = serializers.DateField(required=False)
    reason = serializers.CharField(required=False)

    def validate_percent_bp(self, value):
        return _percentage_switch(value)


class FixedSalaryQueryInput(serializers.Serializer):
    teacher = _id(required=False)


class FixedSalaryCreateInput(serializers.Serializer):
    teacher = _id()
    monthly_minor = serializers.IntegerField(min_value=1)
    starts_on = serializers.DateField(required=False)


class FixedSalaryUpdateInput(serializers.Serializer):
    monthly_minor = serializers.IntegerField(min_value=1, required=False)
    starts_on = serializers.DateField(required=False)
```

Plan 46's `SettingsInput` gains:

```python
    # Slice B4b R-1: sent only while `report_deductions` is on.
    report_deduction_bp = serializers.IntegerField(
        min_value=0, max_value=10000, required=False
    )

    def validate_report_deduction_bp(self, value):
        if not features.enabled("report_deductions"):
            raise serializers.ValidationError("Report deductions are switched off.")
        return value
```

- [ ] **Step 4: Payloads and the queryset**

In `rules.py`, import `BigIntegerField` and add the report total to `payslips_queryset()`'s `.annotate(...)`:

```python
def _report_lines_total():
    """Slice B4b §5: the signed sum of the payslip's report lines, in SQL."""
    lines = (
        PayslipLine.objects.filter(
            payslip=OuterRef("pk"), kind=PayslipLine.Kind.REPORT
        )
        .order_by()
        .values("payslip")
        .annotate(value=Sum("amount_minor"))
        .values("value")
    )
    return Coalesce(
        Subquery(lines, output_field=BigIntegerField()),
        Value(0),
        output_field=BigIntegerField(),
    )
```

```python
        report_lines=_report_lines_total(),
```

In `payloads.py`:
- `adjustment_row` gains `"percent_bp": adjustment.percent_bp` after `amount_minor`.
- `payslip_row` gains, after `missing_rate`:

```python
        # Slice B4b R-4, §5 (plan R6: report deductions as a positive total).
        "reports_sent": payslip.reports_sent,
        "reports_missing": payslip.reports_missing,
        "teacher_absences": payslip.teacher_absences,
        "report_deductions_minor": -payslip.report_lines,
```

- `generate_result` gains `"stale_fixed_salary": [person(user) for user in result.stale_fixed_salary]`.
- Plan 46's `settings_row` gains `"report_deduction_bp": row.report_deduction_bp`.
- Add:

```python
def fixed_salary_row(row) -> dict:
    """Slice B4b §5. ``current`` is false for a salary left in a currency the
    teacher is no longer paid in: it does not count (F-1)."""
    return {
        "id": row.pk,
        "teacher": person(row.teacher.user),
        "monthly_minor": row.monthly_minor,
        "currency": row.currency,
        "starts_on": row.starts_on,
        "current": row.currency == row.teacher.pay_currency,
        "created_at": row.created_at,
        "updated_at": row.updated_at,
    }
```

- [ ] **Step 5: Views and urls**

`CSV_COLUMNS` gains, last (plan R13):

```python
    # Slice B4b R-4, §5.
    ("reports_sent", "Reports sent"),
    ("reports_missing", "Reports not sent"),
    ("teacher_absences", "Teacher absences"),
    ("report_deductions_minor", "Report deductions (minor units)"),
```

Import the three fixed-salary serializers, and add:

```python
# ── Fixed salaries (slice B4b) ───────────────────────────────────────────────


def fixed_salary_or_404(pk):
    return get_object_or_404(services.fixed_salaries_queryset(), pk=pk)


class FixedSalaryListView(APIView):
    """Slice B4b F-5: every fixed salary at once (not paged), like `rates/`."""

    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"GET": "payroll_rate.view_any", "POST": "payroll_rate.create"}
    feature = "fixed_teacher_salary"

    def get(self, request):
        query = FixedSalaryQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        rows = services.fixed_salaries_queryset()
        if "teacher" in query.validated_data:
            rows = rows.filter(teacher__user_id=query.validated_data["teacher"])
        return Response([payloads.fixed_salary_row(row) for row in rows])

    def post(self, request):
        body = FixedSalaryCreateInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        row = services.create_fixed_salary(
            teacher_id=data["teacher"],
            monthly_minor=data["monthly_minor"],
            starts_on=data.get("starts_on"),
        )
        return Response(
            payloads.fixed_salary_row(fixed_salary_or_404(row.pk)),
            status=status.HTTP_201_CREATED,
        )


class FixedSalaryDetailView(APIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"PATCH": "payroll_rate.update", "DELETE": "payroll_rate.delete"}
    feature = "fixed_teacher_salary"

    def patch(self, request, pk):
        row = fixed_salary_or_404(pk)
        body = FixedSalaryUpdateInput(data=request.data, partial=True)
        body.is_valid(raise_exception=True)
        services.update_fixed_salary(row, **body.validated_data)
        return Response(payloads.fixed_salary_row(fixed_salary_or_404(pk)))

    def delete(self, request, pk):
        services.delete_fixed_salary(fixed_salary_or_404(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)
```

`AdjustmentListView.post` and `AdjustmentDetailView.patch` need no change: they already pass `validated_data` through, and a PATCH's `partial=True` leaves out what was not sent (plan R3).

`urls.py` gains:

```python
    path("fixed-salaries/", views.FixedSalaryListView.as_view(), name="fixed-salaries"),
    path(
        "fixed-salaries/<int:pk>/",
        views.FixedSalaryDetailView.as_view(),
        name="fixed-salary",
    ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll etqan/access`
Expected: PASS, including trunk's `test_the_payslip_list_costs_the_same_queries_for_more_rows` unchanged (the report total is a subquery).

- [ ] **Step 7: Commit**

```bash
git -C $W/backend add etqan/payroll/api etqan/payroll/services/rules.py etqan/access/tests/test_routes.py etqan/payroll/tests/test_api.py etqan/payroll/tests/test_counts.py etqan/payroll/tests/test_api_b4b.py
git -C $W/backend commit -m "feat(payroll): fixed-salary routes, percentage and report-share fields, counters in rows and CSV (B4b §5)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Dashboard foundations — types, API, hooks, fixtures, strings

**Files:**
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode`)
- Modify: `dashboard/src/features/payroll/schemas.ts`, `schemas.test.ts`
- Modify: `dashboard/src/features/payroll/api.ts`, `api.test.ts`
- Modify: `dashboard/src/features/payroll/queries.ts`
- Modify: `dashboard/src/test/payroll-fixtures.ts`
- Modify: `dashboard/src/locales/{en,ar}/payroll.json`, `dashboard/src/locales/{en,ar}/errors.json`

**Interfaces:**
- Produces:
  - `FeatureCode` gains `incentives_deductions`, `report_deductions` and `fixed_teacher_salary`;
  - `Adjustment.amount_minor: number | null`, `Adjustment.percent_bp: number | null`;
  - `FixedSalary`, `FixedSalaryBody`, `FixedSalaryPatch`;
  - `Payslip` counters and `report_deductions_minor`; `PayslipLine.kind` with `"report" | "fixed"`; `GenerateResult.stale_fixed_salary`; `PayrollSettings.report_deduction_bp`;
  - `ADJUSTMENT_FORMS`, `REPORT_COUNT_KEYS`, `PERCENT`, `percentToBp`, `bpToPercent`, the `adjustmentFormSchema` `form`/`percent` fields, `fixedSalaryFormSchema`;
  - `payrollApi.fixedSalaries`, `createFixedSalary`, `updateFixedSalary`, `deleteFixedSalary`; hook `useFixedSalaries({enabled})`;
  - fixture `fixedSalaryRow(o)`.

- [ ] **Step 1: Write the failing tests**

Append to `api.test.ts`:

```ts
it("calls the B4b routes", async () => {
	await payrollApi.fixedSalaries({ teacher: 21 });
	expect(api.get).toHaveBeenLastCalledWith("payroll/fixed-salaries/", {
		params: { teacher: "21" },
	});
	await payrollApi.createFixedSalary({
		teacher: 21,
		monthly_minor: 50000,
		starts_on: "2026-07-01",
	});
	expect(api.post).toHaveBeenLastCalledWith("payroll/fixed-salaries/", {
		teacher: 21,
		monthly_minor: 50000,
		starts_on: "2026-07-01",
	});
	await payrollApi.updateFixedSalary({ id: 5, monthly_minor: 60000 });
	expect(api.patch).toHaveBeenLastCalledWith("payroll/fixed-salaries/5/", {
		monthly_minor: 60000,
	});
	await payrollApi.deleteFixedSalary(5);
	expect(api.delete).toHaveBeenLastCalledWith("payroll/fixed-salaries/5/");
	await payrollApi.updateAdjustment({
		id: 91,
		amount_minor: null,
		percent_bp: 1000,
	});
	expect(api.patch).toHaveBeenLastCalledWith("payroll/adjustments/91/", {
		amount_minor: null,
		percent_bp: 1000,
	});
});
```

In `schemas.test.ts`, extend `base` with `form: "amount" as const, percent: ""`, import `bpToPercent` and `percentToBp`, and add inside `describe("adjustmentFormSchema", …)`:

```ts
	it("checks a percentage bonus instead of an amount", () => {
		const schema = adjustmentFormSchema(currencyOf);
		const percent = (value: string) =>
			schema.safeParse({ ...base, form: "percent", amount: "", percent: value });
		expect(percent("12.5").success).toBe(true);
		for (const bad of ["0", "100.01", "12.345", "", "abc"]) {
			expect(percent(bad).error?.issues[0]).toMatchObject({
				path: ["percent"],
				message: "payroll.errors.percent",
			});
		}
		// A deduction is always an amount, whatever the form says.
		expect(
			schema.safeParse({ ...base, kind: "deduction", form: "percent" }).success,
		).toBe(true);
	});
```

and a new `describe`:

```ts
describe("percentages", () => {
	it("turns a percentage into basis points and back in integers", () => {
		expect(percentToBp("12.5")).toBe(1250);
		expect(percentToBp("0.01")).toBe(1);
		expect(percentToBp("100")).toBe(10000);
		expect(bpToPercent(1250)).toBe("12.5");
		expect(bpToPercent(1205)).toBe("12.05");
		expect(bpToPercent(1000)).toBe("10");
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll/api.test.ts src/features/payroll/schemas.test.ts`
Expected: FAIL with `payrollApi.fixedSalaries is not a function` and missing exports.

- [ ] **Step 3: Implement**

`identity/schemas.ts`, in `FeatureCode`:

```ts
	// Phase B4, slice B4b.
	| "incentives_deductions"
	| "report_deductions"
	| "fixed_teacher_salary"
```

`payroll/schemas.ts`. In `Adjustment`, replace `amount_minor: number;` with:

```ts
	// Slice B4b I-1: a fixed amount, or a bonus's share of the month's gross
	// in basis points (10000 = 100 %); exactly one is set.
	amount_minor: number | null;
	percent_bp: number | null;
```

In `AdjustmentBody`, replace `amount_minor: number;` with `amount_minor: number | null;` and add `percent_bp?: number | null;`.

`Payslip` gains:

```ts
	// Slice B4b R-4: null on payslips built before B4b; the report counters
	// are also null while session reports are off.
	reports_sent: number | null;
	reports_missing: number | null;
	teacher_absences: number | null;
	// The report lines' total, positive like deductions_minor.
	report_deductions_minor: number;
```

`PayslipLine.kind` becomes `"session" | "adjustment" | "report" | "fixed";`. `GenerateResult` gains `stale_fixed_salary: Person[];` with the comment "Slice B4b F-1: a fixed salary in an old currency, left out." Plan 46's `PayrollSettings` gains `report_deduction_bp: number;`.

Add:

```ts
export const ADJUSTMENT_FORMS = ["amount", "percent"] as const;
export type AdjustmentForm = (typeof ADJUSTMENT_FORMS)[number];
export const REPORT_COUNT_KEYS = [
	"reports_sent",
	"reports_missing",
	"teacher_absences",
] as const;

/** Slice B4b F-1: a teacher's fixed monthly salary. `current` is false for
 * one left in a currency the teacher is no longer paid in. */
export interface FixedSalary {
	id: number;
	teacher: Person;
	monthly_minor: number;
	currency: string;
	// The first of a month.
	starts_on: string;
	current: boolean;
	created_at: string;
	updated_at: string;
}
export interface FixedSalaryBody {
	teacher: number;
	monthly_minor: number;
	starts_on?: string;
}
export type FixedSalaryPatch = Partial<Omit<FixedSalaryBody, "teacher">>;

/** Slice B4b: a percentage typed with at most two decimals, as basis points
 * (10000 = 100 %), in integers only. */
export const PERCENT = /^\d{1,3}(\.\d{1,2})?$/;

export function percentToBp(text: string): number {
	const [whole = "0", fraction = ""] = text.trim().split(".");
	return Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
}

export function bpToPercent(bp: number): string {
	const whole = Math.floor(bp / 100);
	const rest = bp % 100;
	return rest === 0
		? String(whole)
		: `${whole}.${String(rest).padStart(2, "0")}`.replace(/0$/, "");
}
```

Replace `adjustmentFormSchema`:

```ts
/** A bonus or deduction: the amount is checked against the chosen
 * teacher's currency, with billing's one money field. Before a teacher is
 * chosen (no currency yet) it only has to be filled in. Slice B4b: a bonus
 * may instead be a percentage, from 0.01 to 100. */
export const adjustmentFormSchema = (
	currencyOf: (teacher: string) => string | null,
) =>
	z
		.object({
			teacher: z.string().min(1, "payroll.errors.required"),
			kind: z.enum(ADJUSTMENT_KINDS),
			form: z.enum(ADJUSTMENT_FORMS),
			amount: z.string(),
			percent: z.string(),
			effective_on: day,
			reason: z.string().trim().min(1, "payroll.errors.required"),
		})
		.superRefine((data, ctx) => {
			if (data.kind === "bonus" && data.form === "percent") {
				const text = data.percent.trim();
				const bp = PERCENT.test(text) ? percentToBp(text) : 0;
				if (bp < 1 || bp > 10000) {
					ctx.addIssue({
						code: "custom",
						path: ["percent"],
						message: "payroll.errors.percent",
					});
				}
				return;
			}
			const currency = currencyOf(data.teacher);
			const checked = (
				currency
					? amount(currency)
					: z.string().min(1, "billing.errors.required")
			).safeParse(data.amount);
			if (!checked.success) {
				ctx.addIssue({
					code: "custom",
					path: ["amount"],
					message: checked.error.issues[0]?.message,
				});
			}
		});

/** Slice B4b: a fixed monthly salary in the teacher's currency, from a month
 * ("YYYY-MM") or, empty, from this month (plan R11). */
export const fixedSalaryFormSchema = (currency: string) =>
	z.object({
		amount: amount(currency),
		month: z.string().regex(/^(\d{4}-\d{2})?$/, "payroll.errors.month"),
	});
export type FixedSalaryFormValues = z.infer<
	ReturnType<typeof fixedSalaryFormSchema>
>;
```

`api.ts` gains (import `FixedSalary`, `FixedSalaryBody`, `FixedSalaryPatch`):

```ts
	fixedSalaries: async (params: QueryParams = {}) =>
		(
			await api.get<FixedSalary[]>(`${P}fixed-salaries/`, {
				params: clean(params),
			})
		).data,
	createFixedSalary: async (body: FixedSalaryBody) =>
		(await api.post<FixedSalary>(`${P}fixed-salaries/`, body)).data,
	updateFixedSalary: async ({ id, ...body }: FixedSalaryPatch & { id: number }) =>
		(await api.patch<FixedSalary>(`${P}fixed-salaries/${id}/`, body)).data,
	deleteFixedSalary: async (id: number) => {
		await api.delete(`${P}fixed-salaries/${id}/`);
	},
```

`queries.ts`:

```ts
export function useFixedSalaries({ enabled = true }: { enabled?: boolean } = {}) {
	return useQuery({
		queryKey: [...payrollKey, "fixed-salaries"],
		queryFn: () => payrollApi.fixedSalaries(),
		enabled,
	});
}
```

`payroll-fixtures.ts`:
- `payslipRow` gains `reports_sent: null, reports_missing: null, teacher_absences: null, report_deductions_minor: 0`.
- `adjustmentRow` gains `percent_bp: null`.
- `generateResult` gains `stale_fixed_salary: []`.
- Plan 46's `settingsRow` gains `report_deduction_bp: 0`.
- Add:

```ts
export function fixedSalaryRow(overrides: Partial<FixedSalary> = {}): FixedSalary {
	return {
		id: 51,
		teacher: { id: 21, full_name: "Bilal" },
		monthly_minor: 250000,
		currency: "USD",
		starts_on: "2026-07-01",
		current: true,
		created_at: "2026-07-01T08:00:00Z",
		updated_at: "2026-07-01T08:00:00Z",
		...overrides,
	};
}
```

`en/payroll.json` gains these keys. Merge them into the existing objects; `errors`, `adjustments`, `payslip`, `list`, Plan 46's `settings` and `counts` already exist:

```json
"adjustments": {
	"formLegend": "Bonus type",
	"forms": { "amount": "Fixed amount", "percent": "Percentage" },
	"percent": "Percentage of the month's gross (%)",
	"percentHint": "Worked out on the payslip that uses it: its session pay plus any fixed salary.",
	"percentOff": "Percentage bonuses are switched off. This one waits, unused, until they are on again; you can still change its date and reason, or delete it.",
	"percentValue": "{{percent}} %"
},
"settings": {
	"reportDeduction": "Missing report deduction (%)",
	"reportDeductionHint": "Share of a session's pay taken off when its report is still missing a day after the session ended."
},
"fixed": {
	"title": "Fixed monthly salary",
	"none": "No fixed salary.",
	"perMonth": "per month",
	"from": "from {{month}}",
	"note": "Sessions are still listed on the payslip, but they are not paid per hour.",
	"oldCurrency": "Old currency: not counted",
	"set": "Set a fixed salary",
	"setFor": "Set a fixed salary for {{name}}",
	"edit": "Edit",
	"editFor": "Edit the fixed salary of {{name}}",
	"body": "Paid in full every month from its first month, in the teacher's pay currency.",
	"amount": "Per month ({{currency}})",
	"startsOn": "From month",
	"startsOnHint": "Leave it empty to start this month.",
	"save": "Save fixed salary",
	"saved": "Fixed salary saved.",
	"remove": "Remove the fixed salary of {{name}}",
	"removeTitle": "Remove this fixed salary",
	"removeBody": "Issued payslips keep their lines. Later months are paid per session again."
},
"payslip": {
	"fixed": "Fixed salary",
	"fixedNote": "This month is paid by the fixed salary; the sessions are listed for the record.",
	"reports": "Report deductions"
},
"counts": {
	"reports_sent": "Reports sent",
	"reports_missing": "Reports not sent",
	"teacher_absences": "Teacher absences"
},
"list": {
	"staleFixedSalary": "The fixed salary of {{names}} is in a currency they are no longer paid in, so it was left out. Edit it to count."
},
"errors": {
	"percent": "Enter a percentage above 0 and up to 100, with at most two decimals.",
	"month": "Choose a month."
}
```

`ar/payroll.json`, the same keys:
- `adjustments`:
  - `formLegend`: "نوع المكافأة"
  - `forms`: `amount` "مبلغ ثابت", `percent` "نسبة مئوية"
  - `percent`: "نسبة من إجمالي الشهر (٪)"
  - `percentHint`: "تُحسب في كشف الراتب الذي يستخدمها: أجر حصصه مع أي راتب ثابت."
  - `percentOff`: "مكافآت النسبة المئوية معطّلة. تبقى هذه المكافأة معلّقة دون استخدام حتى تُفعَّل؛ ويمكنك تعديل تاريخها وسببها، أو حذفها."
  - `percentValue`: "{{percent}} ٪"
- `settings`:
  - `reportDeduction`: "خصم التقرير غير المرسل (٪)"
  - `reportDeductionHint`: "نسبة من أجر الحصة تُخصم إذا بقي تقريرها غير مرسل بعد يوم من انتهائها."
- `fixed`:
  - `title`: "الراتب الشهري الثابت"
  - `none`: "لا يوجد راتب ثابت."
  - `perMonth`: "شهريًا"
  - `from`: "ابتداءً من {{month}}"
  - `note`: "تبقى الحصص مدرجة في كشف الراتب، لكنها لا تُدفع بالساعة."
  - `oldCurrency`: "عملة قديمة: لا يُحتسب"
  - `set`: "تعيين راتب ثابت"
  - `setFor`: "تعيين راتب ثابت لـ{{name}}"
  - `edit`: "تعديل"
  - `editFor`: "تعديل الراتب الثابت لـ{{name}}"
  - `body`: "يُدفع كاملًا كل شهر ابتداءً من شهره الأول، بعملة راتب المعلم."
  - `amount`: "شهريًا ({{currency}})"
  - `startsOn`: "من شهر"
  - `startsOnHint`: "اتركه فارغًا ليبدأ هذا الشهر."
  - `save`: "حفظ الراتب الثابت"
  - `saved`: "تم حفظ الراتب الثابت."
  - `remove`: "إزالة الراتب الثابت لـ{{name}}"
  - `removeTitle`: "إزالة هذا الراتب الثابت"
  - `removeBody`: "تحتفظ الكشوف الصادرة بسطورها. وتُدفع الأشهر التالية بالحصة من جديد."
- `payslip`:
  - `fixed`: "الراتب الثابت"
  - `fixedNote`: "يُدفع هذا الشهر بالراتب الثابت؛ والحصص مدرجة للتوثيق."
  - `reports`: "خصومات التقارير"
- `counts`: `reports_sent` "التقارير المرسلة", `reports_missing` "التقارير غير المرسلة", `teacher_absences` "غياب المعلم"
- `list`:
  - `staleFixedSalary`: "الراتب الثابت لـ{{names}} بعملة لم يعودوا يتقاضون بها، فلم يُحتسب. عدّله ليُحتسب."
- `errors`:
  - `percent`: "أدخل نسبة أكبر من 0 وحتى 100، بخانتين عشريتين على الأكثر."
  - `month`: "اختر شهرًا."

In `errors.json`, the `payroll` section gains:
- en: `"fixed_salary_exists": "This teacher already has a fixed salary. Edit it instead."`
- ar: `"fixed_salary_exists": "لدى هذا المعلم راتب ثابت بالفعل. عدّله بدلًا من ذلك."`

No `es` key is added (D22).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll/api.test.ts src/features/payroll/schemas.test.ts src/locales`
Expected: PASS, and the ar/en key-equality test passes. `tsc --noEmit` is run at the end of Task 9: until then `AdjustmentDialog.tsx` and `AdjustmentsList.tsx` still read `amount_minor` as a number.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/identity/schemas.ts src/features/payroll/schemas.ts src/features/payroll/schemas.test.ts src/features/payroll/api.ts src/features/payroll/api.test.ts src/features/payroll/queries.ts src/test/payroll-fixtures.ts src/locales
git -C $W/dashboard commit -m "feat(payroll): B4b types, fixed-salary API, percent helpers, fixtures and strings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: The adjustment dialog, the adjustments list and the settings field

**Files:**
- Modify: `dashboard/src/features/payroll/AdjustmentDialog.tsx`
- Modify: `dashboard/src/features/payroll/AdjustmentsList.tsx`, `AdjustmentsList.test.tsx`
- Modify: `dashboard/src/features/payroll/SettingsPage.tsx`, `SettingsPage.test.tsx` (Plan 46's files)

**Interfaces:**
- Consumes: `useHasFeature` (`@/features/identity/permissions`); Task 8's schemas and strings.
- Produces: the "Fixed amount / Percentage" choice (I-3: only while `incentives_deductions` is on and kind is Bonus); "10 %" in the list; the "Missing report deduction (%)" field while `report_deductions` is on.

- [ ] **Step 1: Write the failing tests**

Append to `AdjustmentsList.test.tsx` (import `adminWith` from `@/test/access-fixtures`):

```tsx
	it("adds a percentage bonus while percentages are on", async () => {
		vi.mocked(payrollApi.createAdjustment).mockResolvedValue(
			adjustmentRow({ amount_minor: null, percent_bp: 1250 }),
		);
		const user = userEvent.setup();
		renderWithRouter(<AdjustmentsList />, { extraPaths: [PAYSLIP] });
		await user.click(
			await screen.findByRole("button", { name: "Add adjustment" }),
		);
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(within(dialog).getByLabelText(/^Teacher/), "21");
		await user.click(within(dialog).getByLabelText("Percentage"));
		expect(within(dialog).queryByLabelText(/^Amount/)).toBeNull();
		const percent = within(dialog).getByLabelText(/^Percentage of the month/);
		await user.type(percent, "12.345");
		await user.type(within(dialog).getByLabelText(/^Reason/), "Target");
		await user.click(
			within(dialog).getByRole("button", { name: "Save adjustment" }),
		);
		expect(
			await within(dialog).findByText(
				"Enter a percentage above 0 and up to 100, with at most two decimals.",
			),
		).toBeInTheDocument();
		await user.clear(percent);
		await user.type(percent, "12.5");
		await user.click(
			within(dialog).getByRole("button", { name: "Save adjustment" }),
		);
		await waitFor(() =>
			expect(payrollApi.createAdjustment).toHaveBeenCalledWith(
				expect.objectContaining({
					teacher: 21,
					kind: "bonus",
					amount_minor: null,
					percent_bp: 1250,
					reason: "Target",
				}),
			),
		);
	});

	it("never offers a percentage for a deduction", async () => {
		const user = userEvent.setup();
		renderWithRouter(<AdjustmentsList />, { extraPaths: [PAYSLIP] });
		await user.click(
			await screen.findByRole("button", { name: "Add adjustment" }),
		);
		const dialog = screen.getByRole("dialog");
		expect(within(dialog).getByLabelText("Percentage")).toBeInTheDocument();
		await user.selectOptions(within(dialog).getByLabelText(/^Kind/), "deduction");
		expect(within(dialog).queryByLabelText("Percentage")).toBeNull();
	});

	it("shows a percentage bonus as a percentage", async () => {
		vi.mocked(payrollApi.adjustments).mockResolvedValue(
			page([
				adjustmentRow({
					id: 93,
					reason: "Target",
					amount_minor: null,
					percent_bp: 1000,
				}),
			]),
		);
		renderWithRouter(<AdjustmentsList />, { extraPaths: [PAYSLIP] });
		await screen.findByRole("table");
		expect(within(row("Target")).getByText("10 %")).toBeInTheDocument();
	});

	it("keeps a pending percentage while percentages are off", async () => {
		vi.mocked(payrollApi.adjustments).mockResolvedValue(
			page([
				adjustmentRow({ reason: "Target", amount_minor: null, percent_bp: 1000 }),
			]),
		);
		vi.mocked(payrollApi.updateAdjustment).mockResolvedValue(adjustmentRow());
		const user = userEvent.setup();
		renderWithRouter(
			<CanProvider me={adminWith()}>
				<AdjustmentsList />
			</CanProvider>,
			{ extraPaths: [PAYSLIP] },
		);
		await user.click(
			await screen.findByRole("button", { name: "Edit Target for Bilal" }),
		);
		const dialog = screen.getByRole("dialog");
		expect(within(dialog).queryByLabelText("Percentage")).toBeNull();
		expect(within(dialog).getByLabelText(/^Percentage of the month/)).toHaveValue(
			"10",
		);
		expect(within(dialog).getByText(/switched off/)).toBeInTheDocument();
		const reason = within(dialog).getByLabelText(/^Reason/);
		await user.clear(reason);
		await user.type(reason, "Ramadan");
		await user.click(
			within(dialog).getByRole("button", { name: "Save adjustment" }),
		);
		await waitFor(() =>
			expect(payrollApi.updateAdjustment).toHaveBeenCalledWith({
				id: 91,
				effective_on: "2026-06-15",
				reason: "Ramadan",
			}),
		);
	});

	it("shows the server's percentage refusal on its field", async () => {
		vi.mocked(payrollApi.createAdjustment).mockRejectedValue(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { percent_bp: ["Percentage bonuses are switched off."] },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<AdjustmentsList />, { extraPaths: [PAYSLIP] });
		await user.click(
			await screen.findByRole("button", { name: "Add adjustment" }),
		);
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(within(dialog).getByLabelText(/^Teacher/), "21");
		await user.click(within(dialog).getByLabelText("Percentage"));
		await user.type(within(dialog).getByLabelText(/^Percentage of the month/), "10");
		await user.type(within(dialog).getByLabelText(/^Reason/), "Target");
		await user.click(
			within(dialog).getByRole("button", { name: "Save adjustment" }),
		);
		expect(
			await within(dialog).findByText("Percentage bonuses are switched off."),
		).toBeInTheDocument();
	});

	it("reads a percentage in Arabic", async () => {
		await i18n.changeLanguage("ar");
		vi.mocked(payrollApi.adjustments).mockResolvedValue(
			page([
				adjustmentRow({ reason: "Target", amount_minor: null, percent_bp: 1250 }),
			]),
		);
		renderWithRouter(<AdjustmentsList />, { extraPaths: [PAYSLIP] });
		await screen.findByRole("table");
		expect(within(row("Target")).getByText("12.5 ٪")).toBeInTheDocument();
	});
```

In Plan 46's `SettingsPage.test.tsx` (import `adminWith`):
- The first test's expected `updateSettings` body gains `report_deduction_bp: 0`: outside the app shell every feature reads as on (`useHasFeature`'s `allowAll`), so the field is shown and sent.
- Add:

```tsx
	it("saves the missing report share as basis points", async () => {
		renderWithRouter(<SettingsPage />);
		const share = await screen.findByLabelText(/missing report deduction/i);
		expect(share).toHaveValue(0);
		await userEvent.clear(share);
		await userEvent.type(share, "50");
		await userEvent.click(screen.getByRole("button", { name: /save rules/i }));
		await waitFor(() =>
			expect(payrollApi.updateSettings).toHaveBeenCalledWith(
				expect.objectContaining({ report_deduction_bp: 5000 }),
			),
		);
	});

	it("neither shows nor sends the share while report deductions are off", async () => {
		renderWithRouter(
			<CanProvider me={adminWith("payroll_rules")}>
				<SettingsPage />
			</CanProvider>,
		);
		await screen.findByLabelText(/student missed/i);
		expect(screen.queryByLabelText(/missing report deduction/i)).toBeNull();
		await userEvent.click(screen.getByRole("button", { name: /save rules/i }));
		await waitFor(() => expect(payrollApi.updateSettings).toHaveBeenCalled());
		expect(
			vi.mocked(payrollApi.updateSettings).mock.calls[0][0],
		).not.toHaveProperty("report_deduction_bp");
	});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll/AdjustmentsList.test.tsx src/features/payroll/SettingsPage.test.tsx`
Expected: FAIL (no "Percentage" choice, "$0.00" instead of "10 %", no share field).

- [ ] **Step 3: `AdjustmentDialog.tsx`**

Add the imports `useHasFeature` (`@/features/identity/permissions`), `ADJUSTMENT_FORMS`, `type AdjustmentBody`, `type AdjustmentPatch`, `bpToPercent` and `percentToBp` (`./schemas`). Then, in the component:

```tsx
	const has = useHasFeature();
	// Slice B4b I-3: a percentage is offered only while percentages are on.
	// A pending one made while they were on keeps its percentage while they
	// are off: only its date and reason change (plan R10).
	const percentOn = has("incentives_deductions");
	const wasPercent = adjustment ? adjustment.percent_bp !== null : false;
	const percentLocked = wasPercent && !percentOn;
```

The form's `values` become:

```tsx
		values: {
			teacher: adjustment ? String(adjustment.teacher.id) : "",
			kind: adjustment?.kind ?? "bonus",
			form: wasPercent ? "percent" : "amount",
			amount:
				adjustment && adjustment.amount_minor !== null
					? toMajor(
							adjustment.amount_minor,
							currencyOf(String(adjustment.teacher.id)) ?? adjustment.currency,
						)
					: "",
			percent:
				adjustment && adjustment.percent_bp !== null
					? bpToPercent(adjustment.percent_bp)
					: "",
			effective_on:
				adjustment?.effective_on ?? (academy ? todayIn(academy.timezone) : ""),
			reason: adjustment?.reason ?? "",
		},
```

After `const currency = …`:

```tsx
	const kind = watch("kind");
	const asPercent = kind === "bonus" && watch("form") === "percent";

	/** Plan R10: what the request carries for each case. */
	function fieldsOf(values: AdjustmentFormValues): AdjustmentPatch {
		const when = { effective_on: values.effective_on, reason: values.reason };
		if (percentLocked) return when;
		if (values.kind === "bonus" && values.form === "percent") {
			return {
				kind: "bonus",
				amount_minor: null,
				percent_bp: percentToBp(values.percent),
				...when,
			};
		}
		return {
			kind: values.kind,
			amount_minor: toMinor(values.amount, currencyOf(values.teacher) ?? ""),
			// Turning a percentage back into an amount clears it (§4.2).
			...(wasPercent ? { percent_bp: null } : {}),
			...when,
		};
	}
```

`onSubmit` becomes:

```tsx
	async function onSubmit(values: AdjustmentFormValues) {
		const fields = fieldsOf(values);
		try {
			if (adjustment) {
				await update.mutateAsync({ id: adjustment.id, ...fields });
			} else {
				// A new adjustment is never locked, so its fields are complete.
				await create.mutateAsync({
					teacher: Number(values.teacher),
					...(fields as Omit<AdjustmentBody, "teacher">),
				});
			}
			reset();
			setOpen(false);
			toast({
				description: t("payroll.adjustments.saved"),
				variant: "success",
			});
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.amount_minor) {
				setError("amount", { message: parsed.fieldErrors.amount_minor });
			}
			if (parsed.fieldErrors.percent_bp) {
				setError("percent", { message: parsed.fieldErrors.percent_bp });
			}
		}
	}
```

In the JSX grid:
- Render the Kind `Field` only when `!percentLocked`.
- After the Kind field, render the choice:

```tsx
						{percentOn && kind === "bonus" && !percentLocked ? (
							<fieldset className="flex flex-col gap-2 sm:col-span-2">
								<legend className="text-sm font-medium">
									{t("payroll.adjustments.formLegend")}
								</legend>
								<div className="flex flex-wrap gap-4">
									{ADJUSTMENT_FORMS.map((form) => (
										<label key={form} className="flex items-center gap-2 text-sm">
											<input type="radio" value={form} {...register("form")} />
											{t(`payroll.adjustments.forms.${form}`)}
										</label>
									))}
								</div>
							</fieldset>
						) : null}
```

- Replace the amount `Field` with:

```tsx
						{asPercent ? (
							<Field
								id="adjustment-percent"
								label={t("payroll.adjustments.percent")}
								error={fieldError(errors.percent?.message)}
								required
							>
								<Input
									inputMode="decimal"
									dir="ltr"
									readOnly={percentLocked}
									{...register("percent")}
								/>
							</Field>
						) : (
							<Field
								id="adjustment-amount"
								label={
									currency
										? t("payroll.adjustments.amount", { currency })
										: t("payroll.columns.amount")
								}
								error={fieldError(errors.amount?.message)}
								required
							>
								<Input inputMode="decimal" dir="ltr" {...register("amount")} />
							</Field>
						)}
```

- Below the grid:

```tsx
					{asPercent ? (
						<p className="text-sm text-muted-foreground">
							{percentLocked
								? t("payroll.adjustments.percentOff")
								: t("payroll.adjustments.percentHint")}
						</p>
					) : null}
```

The percentage input is `readOnly`, not `disabled`, when locked: react-hook-form drops a disabled field's value, and the schema needs it.

- [ ] **Step 4: `AdjustmentsList.tsx`**

Import `bpToPercent` from `./schemas`. The amount cell becomes:

```tsx
									<td className="p-3">
										{adjustment.percent_bp !== null ? (
											t("payroll.adjustments.percentValue", {
												percent: bpToPercent(adjustment.percent_bp),
											})
										) : (
											<Money
												minor={adjustment.amount_minor ?? 0}
												currency={adjustment.currency}
											/>
										)}
									</td>
```

- [ ] **Step 5: `SettingsPage.tsx`**

In Plan 46's settings page (`SettingsPage` loads; `SettingsForm({ initial, readOnly })` holds the form, whose field names are the API's, in %, so `applyServerErrors` maps a 400 onto them unchanged):
- Import `useHasFeature` next to `useCan` (`@/features/identity/permissions`). In `SettingsForm`, add `const has = useHasFeature();` and `const reportsOn = has("report_deductions");`.
- `settingsFormSchema` gains `report_deduction_bp: percent`, the same `percent` preprocessor as the two weights (0 to 100, at most two decimals, an empty input refused rather than saved as 0).
- Its form `values` gain `report_deduction_bp: initial.report_deduction_bp / 100`.
- Its submit body gains `...(reportsOn ? { report_deduction_bp: toBp(values.report_deduction_bp) } : {})`.
- No server-error mapping is needed: the form field has the API's name.
- After the student-excused weight (inside the same `Card` as the weights, after the `.map(...)`), add:

```tsx
					{reportsOn ? (
						<div className="flex flex-col gap-1.5">
							<Field
								id="settings-report_deduction"
								label={t("payroll.settings.reportDeduction")}
								error={fieldError(errors.report_deduction_bp?.message)}
							>
								<Input
									type="number"
									inputMode="decimal"
									min={0}
									max={100}
									step={0.01}
									dir="ltr"
									disabled={readOnly}
									aria-describedby="settings-report_deduction-hint"
									{...register("report_deduction_bp")}
								/>
							</Field>
							<p
								id="settings-report_deduction-hint"
								className="text-sm text-muted-foreground"
							>
								{t("payroll.settings.reportDeductionHint")}
							</p>
						</div>
					) : null}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll`, then `… exec -T dashboard pnpm exec tsc --noEmit`, then `pnpm lint`
Expected: PASS. The trunk `AdjustmentsList` tests still expect bodies without `percent_bp`, because a fixed adjustment that was always fixed sends none (plan R10).

- [ ] **Step 7: Commit**

```bash
git -C $W/dashboard add src/features/payroll
git -C $W/dashboard commit -m "feat(payroll): percentage bonuses in the adjustment dialog; missing-report share setting (B4b §6)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: The fixed salary on the Rates page

**Files:**
- Create: `dashboard/src/features/payroll/FixedSalary.tsx`, `FixedSalary.test.tsx`
- Modify: `dashboard/src/features/payroll/RatesPage.tsx`, `RatesPage.test.tsx`

**Interfaces:**
- Consumes: `useFixedSalaries`, `payrollApi.createFixedSalary`/`updateFixedSalary`/`deleteFixedSalary`, `fixedSalaryFormSchema` (Task 8); `RateTeacher` (`./RateDialog`); `useHasFeature`, `useCan`.
- Produces: `<FixedSalaryRow teacher salary />` and `<FixedSalaryDialog teacher salary />`. Each teacher card on the Rates page shows a fixed-salary row while `fixed_teacher_salary` is on.

- [ ] **Step 1: Write the failing tests**

`FixedSalary.test.tsx`:

```tsx
import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { fixedSalaryRow } from "@/test/payroll-fixtures";
import { renderWithRouter } from "@/test/render";
import { payrollApi } from "./api";
import { FixedSalaryRow } from "./FixedSalary";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		payrollApi: {
			...actual.payrollApi,
			createFixedSalary: vi.fn(),
			updateFixedSalary: vi.fn(),
			deleteFixedSalary: vi.fn(),
		},
	};
});

const BILAL = {
	id: 21,
	user: { full_name: "Bilal" },
	profile: { pay_currency: "USD" },
};

describe("FixedSalaryRow", () => {
	beforeEach(() => vi.clearAllMocks());
	afterEach(async () => {
		await i18n.changeLanguage("en");
	});

	it("sets one from a chosen month", async () => {
		vi.mocked(payrollApi.createFixedSalary).mockResolvedValue(fixedSalaryRow());
		const user = userEvent.setup();
		renderWithRouter(<FixedSalaryRow teacher={BILAL} />);
		expect(await screen.findByText("No fixed salary.")).toBeInTheDocument();
		await user.click(
			screen.getByRole("button", { name: "Set a fixed salary for Bilal" }),
		);
		const dialog = screen.getByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^Per month \(USD\)/), "2500");
		fireEvent.change(within(dialog).getByLabelText(/^From month/), {
			target: { value: "2026-07" },
		});
		await user.click(
			within(dialog).getByRole("button", { name: "Save fixed salary" }),
		);
		await waitFor(() =>
			expect(payrollApi.createFixedSalary).toHaveBeenCalledWith({
				teacher: 21,
				monthly_minor: 250000,
				starts_on: "2026-07-01",
			}),
		);
	});

	it("starts this month when no month is chosen", async () => {
		vi.mocked(payrollApi.createFixedSalary).mockResolvedValue(fixedSalaryRow());
		const user = userEvent.setup();
		renderWithRouter(<FixedSalaryRow teacher={BILAL} />);
		await user.click(
			await screen.findByRole("button", { name: "Set a fixed salary for Bilal" }),
		);
		const dialog = screen.getByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^Per month \(USD\)/), "2500");
		await user.click(
			within(dialog).getByRole("button", { name: "Save fixed salary" }),
		);
		await waitFor(() =>
			expect(payrollApi.createFixedSalary).toHaveBeenCalledWith({
				teacher: 21,
				monthly_minor: 250000,
			}),
		);
	});

	it("shows the salary, its month and an old currency, and edits it", async () => {
		vi.mocked(payrollApi.updateFixedSalary).mockResolvedValue(fixedSalaryRow());
		const user = userEvent.setup();
		renderWithRouter(
			<FixedSalaryRow
				teacher={BILAL}
				salary={fixedSalaryRow({ currency: "EGP", current: false })}
			/>,
		);
		expect(await screen.findByText("from July 2026")).toBeInTheDocument();
		expect(screen.getByText("Old currency: not counted")).toBeInTheDocument();
		expect(screen.getByText(/not paid per hour/)).toBeInTheDocument();
		await user.click(
			screen.getByRole("button", { name: "Edit the fixed salary of Bilal" }),
		);
		const dialog = screen.getByRole("dialog");
		const amount = within(dialog).getByLabelText(/^Per month \(USD\)/);
		await user.clear(amount);
		await user.type(amount, "3000");
		await user.click(
			within(dialog).getByRole("button", { name: "Save fixed salary" }),
		);
		await waitFor(() =>
			expect(payrollApi.updateFixedSalary).toHaveBeenCalledWith({
				id: 51,
				monthly_minor: 300000,
				starts_on: "2026-07-01",
			}),
		);
	});

	it("translates a duplicate", async () => {
		vi.mocked(payrollApi.createFixedSalary).mockRejectedValue(
			new AxiosError("Conflict", "409", undefined, undefined, {
				status: 409,
				data: { code: "payroll.fixed_salary_exists", detail: "exists" },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<FixedSalaryRow teacher={BILAL} />);
		await user.click(
			await screen.findByRole("button", { name: "Set a fixed salary for Bilal" }),
		);
		const dialog = screen.getByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^Per month \(USD\)/), "2500");
		await user.click(
			within(dialog).getByRole("button", { name: "Save fixed salary" }),
		);
		expect(
			await within(dialog).findByText(
				"This teacher already has a fixed salary. Edit it instead.",
			),
		).toBeInTheDocument();
	});

	it("removes one after confirming", async () => {
		vi.mocked(payrollApi.deleteFixedSalary).mockResolvedValue(undefined);
		const user = userEvent.setup();
		renderWithRouter(<FixedSalaryRow teacher={BILAL} salary={fixedSalaryRow()} />);
		await user.click(
			await screen.findByRole("button", {
				name: "Remove the fixed salary of Bilal",
			}),
		);
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Remove this fixed salary",
			}),
		);
		await waitFor(() =>
			expect(payrollApi.deleteFixedSalary).toHaveBeenCalledWith(51),
		);
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(<FixedSalaryRow teacher={BILAL} salary={fixedSalaryRow()} />);
		expect(await screen.findByText("الراتب الشهري الثابت")).toBeInTheDocument();
	});
});
```

In `RatesPage.test.tsx`:
- Add `fixedSalaries: vi.fn()` to the `payrollApi` mock, and `vi.mocked(payrollApi.fixedSalaries).mockResolvedValue([])` in `beforeEach`.
- Import `fixedSalaryRow` (`adminWith` and `CanProvider` are already imported).
- Add:

```tsx
	it("shows each teacher's fixed salary while the switch is on", async () => {
		vi.mocked(payrollApi.fixedSalaries).mockResolvedValue([fixedSalaryRow()]);
		renderWithRouter(<RatesPage />);
		expect(await screen.findByText("from July 2026")).toBeInTheDocument();
		expect(within(card("Bilal")).getByText("Fixed monthly salary")).toBeInTheDocument();
	});

	it("asks for no fixed salary while the switch is off", async () => {
		renderWithRouter(
			<CanProvider me={adminWith()}>
				<RatesPage />
			</CanProvider>,
		);
		await screen.findByText("Bilal");
		expect(payrollApi.fixedSalaries).not.toHaveBeenCalled();
		expect(screen.queryByText("Fixed monthly salary")).toBeNull();
	});
```

`card(name)` is the file's existing helper (used by its delete test).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll/FixedSalary.test.tsx src/features/payroll/RatesPage.test.tsx`
Expected: FAIL (module not found).

- [ ] **Step 3: `FixedSalary.tsx`**

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { Money } from "@/features/billing";
import { useCan } from "@/features/identity/permissions";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors, errorText } from "@/lib/form-errors";
import { toMajor, toMinor } from "@/lib/money";
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
	Field,
	Input,
	StatusChip,
	SubmitButton,
	toast,
} from "@/ui";
import { payrollApi } from "./api";
import { usePayrollMutation } from "./queries";
import type { RateTeacher } from "./RateDialog";
import {
	type FixedSalary,
	type FixedSalaryFormValues,
	fixedSalaryFormSchema,
} from "./schemas";

/** "July 2026" for a month's first day, in the reader's language. */
function monthName(day: string, language: string): string {
	return new Intl.DateTimeFormat(language, {
		month: "long",
		year: "numeric",
		timeZone: "UTC",
	}).format(new Date(`${day}T00:00:00Z`));
}

/** Slice B4b F-1, §6: a teacher's fixed monthly salary on their rates card.
 * `teacher` is null when their pay currency is unknown (Plan 12a fix round
 * 2): the salary is shown, but nothing is offered for editing. */
export function FixedSalaryRow({
	teacher,
	salary,
}: {
	teacher: RateTeacher | null;
	salary?: FixedSalary;
}) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const remove = usePayrollMutation(payrollApi.deleteFixedSalary);
	const name = teacher?.user.full_name ?? salary?.teacher.full_name ?? "";
	const mayWrite = can(salary ? "payroll_rate.update" : "payroll_rate.create");
	return (
		<div className="flex flex-col gap-2 border-t border-border pt-3">
			<div className="flex flex-wrap items-center justify-between gap-2">
				<div className="flex flex-col gap-1 text-sm">
					<span className="font-medium">{t("payroll.fixed.title")}</span>
					{salary ? (
						<span className="flex flex-wrap items-center gap-2">
							<Money minor={salary.monthly_minor} currency={salary.currency} />
							{t("payroll.fixed.perMonth")}
							<span>
								{t("payroll.fixed.from", {
									month: monthName(salary.starts_on, i18n.language),
								})}
							</span>
							{salary.current ? null : (
								<StatusChip tone="warning">
									{t("payroll.fixed.oldCurrency")}
								</StatusChip>
							)}
						</span>
					) : (
						<span className="text-muted-foreground">
							{t("payroll.fixed.none")}
						</span>
					)}
				</div>
				<div className="flex flex-wrap gap-2">
					{teacher && mayWrite ? (
						<FixedSalaryDialog teacher={teacher} salary={salary} />
					) : null}
					{salary && can("payroll_rate.delete") ? (
						<Confirm
							action={t("payroll.fixed.remove", { name })}
							title={t("payroll.fixed.removeTitle")}
							body={t("payroll.fixed.removeBody")}
							onConfirm={() =>
								remove.mutate(salary.id, {
									onError: (error) =>
										toast({
											description: errorText(error, t),
											variant: "destructive",
										}),
								})
							}
						/>
					) : null}
				</div>
			</div>
			{salary ? (
				<p className="text-sm text-muted-foreground">{t("payroll.fixed.note")}</p>
			) : null}
		</div>
	);
}

/** Set or edit a fixed monthly salary in the teacher's current pay
 * currency; the month is optional (plan R11). */
export function FixedSalaryDialog({
	teacher,
	salary,
}: {
	teacher: RateTeacher;
	salary?: FixedSalary;
}) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const currency = teacher.profile.pay_currency;
	const name = teacher.user.full_name;
	const create = usePayrollMutation(payrollApi.createFixedSalary);
	const update = usePayrollMutation(payrollApi.updateFixedSalary);
	const {
		register,
		handleSubmit,
		setError,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<FixedSalaryFormValues>({
		resolver: zodResolver(fixedSalaryFormSchema(currency)),
		values: {
			amount: salary ? toMajor(salary.monthly_minor, currency) : "",
			month: salary ? salary.starts_on.slice(0, 7) : "",
		},
	});

	async function onSubmit(values: FixedSalaryFormValues) {
		const fields = {
			monthly_minor: toMinor(values.amount, currency),
			...(values.month ? { starts_on: `${values.month}-01` } : {}),
		};
		try {
			if (salary) {
				await update.mutateAsync({ id: salary.id, ...fields });
			} else {
				await create.mutateAsync({ teacher: teacher.id, ...fields });
			}
			reset();
			setOpen(false);
			toast({ description: t("payroll.fixed.saved"), variant: "success" });
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.monthly_minor) {
				setError("amount", { message: parsed.fieldErrors.monthly_minor });
			}
			if (parsed.fieldErrors.starts_on) {
				setError("month", { message: parsed.fieldErrors.starts_on });
			}
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button
					size="sm"
					variant={salary ? "outline" : "primary"}
					aria-label={
						salary
							? t("payroll.fixed.editFor", { name })
							: t("payroll.fixed.setFor", { name })
					}
				>
					{salary ? t("payroll.fixed.edit") : t("payroll.fixed.set")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>
					{salary
						? t("payroll.fixed.editFor", { name })
						: t("payroll.fixed.setFor", { name })}
				</DialogTitle>
				<DialogDescription>{t("payroll.fixed.body")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id="fixed-amount"
						label={t("payroll.fixed.amount", { currency })}
						error={fieldError(errors.amount?.message)}
						required
					>
						<Input inputMode="decimal" dir="ltr" {...register("amount")} />
					</Field>
					<Field
						id="fixed-month"
						label={t("payroll.fixed.startsOn")}
						error={fieldError(errors.month?.message)}
					>
						<Input type="month" dir="ltr" {...register("month")} />
					</Field>
					<p className="text-sm text-muted-foreground">
						{t("payroll.fixed.startsOnHint")}
					</p>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.root.server.message)}
							</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>
							{t("payroll.fixed.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Read how `RateDialog.tsx` shows a 409's translated text (`applyServerErrors` putting the code's string in `errors.root.server`) and match it if it differs.

- [ ] **Step 4: `RatesPage.tsx`**

- Import `useHasFeature`, `useFixedSalaries`, `FixedSalaryRow` and `type FixedSalary`.
- `TeacherRates` gains a prop `fixedSalary?: FixedSalary | null`: `undefined` means the switch is off (nothing shown), `null` means no salary yet. At the end of its `CardContent`:

```tsx
				{fixedSalary === undefined ? null : (
					<FixedSalaryRow
						teacher={withCurrency}
						salary={fixedSalary ?? undefined}
					/>
				)}
```

- In `RatesPage`:

```tsx
	const has = useHasFeature();
	// Slice B4b F-5: asked for only while fixed salaries are on.
	const fixedOn = has("fixed_teacher_salary");
	const fixed = useFixedSalaries({ enabled: fixedOn });
```

  - Add `|| (fixedOn && fixed.isError)` to the load-error condition and `|| (fixedOn && !fixed.data)` to the spinner condition.
  - Build `const fixedByTeacher = new Map((fixed.data ?? []).map((row) => [row.teacher.id, row]));`.
  - Pass `fixedSalary={fixedOn ? (fixedByTeacher.get(teacher.id) ?? null) : undefined}` to each `TeacherRates`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll`, then `tsc --noEmit`, then `pnpm lint`
Expected: PASS. If a trunk `RatesPage` test now finds two buttons where it expected one, scope its query to the rates list with `within(...)`; never delete its assertion.

- [ ] **Step 6: Commit**

```bash
git -C $W/dashboard add src/features/payroll
git -C $W/dashboard commit -m "feat(payroll): fixed monthly salary on the Rates page (B4b §6)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: `PayslipBody`, the counters and the generate result

**Files:**
- Modify: `dashboard/src/features/payroll/PayslipBody.tsx`
- Create: `dashboard/src/features/payroll/PayslipBody.test.tsx`
- Modify: `dashboard/src/features/payroll/PayslipPrint.test.tsx`
- Modify: `dashboard/src/features/payroll/PayslipsList.tsx`, `PayslipsList.test.tsx`

**Interfaces:**
- Consumes: `REPORT_COUNT_KEYS`, `PayslipLine.kind`, the payslip counters, `GenerateResult.stale_fixed_salary` (Task 8); Plan 46's `LineBadges`, `COUNT_KEYS` and the counts toggle.
- Produces: `PayslipBody` (shared by the office page, the teacher's page and print) with fixed lines first, the report section, "—" rates in a fixed-salary month, and the counters; the list's three counter columns; the stale-salary notice.

- [ ] **Step 1: Write the failing tests**

`PayslipBody.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import i18n from "@/lib/i18n";
import { lineRow, payslipDetail } from "@/test/payroll-fixtures";
import { renderWithRouter } from "@/test/render";
import { PayslipBody } from "./PayslipBody";

const UNDESCRIBED = {
	session_id: null,
	minutes: null,
	rate_minor: null,
	session_kind: "",
	session_status: "",
	student_attendance: "",
	pay_bp: null,
} as const;

describe("PayslipBody", () => {
	afterEach(async () => {
		await i18n.changeLanguage("en");
	});

	it("puts a fixed salary first and lists the sessions with no rate", async () => {
		renderWithRouter(
			<PayslipBody
				payslip={payslipDetail({
					gross_minor: 250000,
					net_minor: 250000,
					bonuses_minor: 0,
					deductions_minor: 0,
					lines: [
						lineRow({
							id: 80,
							kind: "fixed",
							description: "Fixed monthly salary",
							amount_minor: 250000,
							...UNDESCRIBED,
						}),
						lineRow({ rate_minor: null, amount_minor: 0 }),
					],
				})}
			/>,
		);
		const fixed = await screen.findByRole("heading", { name: "Fixed salary" });
		const sessions = screen.getByRole("heading", { name: "Sessions" });
		expect(
			fixed.compareDocumentPosition(sessions) & Node.DOCUMENT_POSITION_FOLLOWING,
		).toBeTruthy();
		expect(screen.getByText("Fixed monthly salary")).toBeInTheDocument();
		expect(screen.getByText(/paid by the fixed salary/)).toBeInTheDocument();
		expect(screen.queryByText("No rate")).toBeNull();
		expect(screen.getByRole("cell", { name: "—" })).toBeInTheDocument();
	});

	it("shows missing-report deductions in their own section", async () => {
		renderWithRouter(
			<PayslipBody
				payslip={payslipDetail({
					lines: [
						lineRow(),
						lineRow({
							id: 85,
							kind: "report",
							description: "Missing report — 2026-06-01 — Tajweed — Yusuf",
							amount_minor: -375,
							...UNDESCRIBED,
							session_id: 41,
						}),
					],
				})}
			/>,
		);
		expect(
			await screen.findByRole("heading", { name: "Report deductions" }),
		).toBeInTheDocument();
		expect(
			screen.getByText("Missing report — 2026-06-01 — Tajweed — Yusuf"),
		).toBeInTheDocument();
	});

	it("shows the counters it has and hides the unknown ones", async () => {
		renderWithRouter(
			<PayslipBody
				payslip={payslipDetail({
					reports_sent: 1,
					reports_missing: 2,
					teacher_absences: 0,
				})}
			/>,
		);
		const missing = await screen.findByText("Reports not sent");
		expect(missing.nextElementSibling).toHaveTextContent("2");
		expect(screen.getByText("Teacher absences").nextElementSibling).toHaveTextContent(
			"0",
		);
	});

	it("shows no counter or report section on an older payslip", async () => {
		renderWithRouter(<PayslipBody payslip={payslipDetail()} />);
		await screen.findByRole("heading", { name: "Sessions" });
		expect(screen.queryByText("Reports sent")).toBeNull();
		expect(screen.queryByRole("heading", { name: "Report deductions" })).toBeNull();
		expect(screen.queryByRole("heading", { name: "Fixed salary" })).toBeNull();
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(
			<PayslipBody
				payslip={payslipDetail({
					lines: [
						lineRow({
							id: 80,
							kind: "fixed",
							description: "الراتب الشهري الثابت",
							amount_minor: 250000,
							...UNDESCRIBED,
						}),
						lineRow({
							id: 85,
							kind: "report",
							description: "تقرير غير مرسل — 2026-06-01",
							amount_minor: -375,
							...UNDESCRIBED,
						}),
					],
				})}
			/>,
		);
		expect(
			await screen.findByRole("heading", { name: "الراتب الثابت" }),
		).toBeInTheDocument();
		expect(
			screen.getByRole("heading", { name: "خصومات التقارير" }),
		).toBeInTheDocument();
	});
});
```

Append to `PayslipPrint.test.tsx` (`lineRow` is already imported):

```tsx
	it("prints the report deductions too", async () => {
		vi.spyOn(window, "print").mockImplementation(() => {});
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			teacherPayslip({
				lines: [
					lineRow(),
					lineRow({
						id: 85,
						kind: "report",
						description: "Missing report — 2026-06-01 — Tajweed — Yusuf",
						minutes: null,
						rate_minor: null,
						amount_minor: -375,
					}),
				],
			}),
		);
		renderWithRouter(<PayslipPrint payslipId="71" />);
		expect(
			await screen.findByRole("heading", { name: "Report deductions" }),
		).toBeInTheDocument();
	});
```

Append to `PayslipsList.test.tsx`:

```tsx
	it("adds the report and absence counters to the counts columns", async () => {
		localStorage.removeItem("etqan.payroll.showCounts");
		vi.mocked(payrollApi.payslips).mockResolvedValue(
			page([
				payslipRow({
					month: 7,
					reports_sent: 4,
					reports_missing: 1,
					teacher_absences: 2,
				}),
				payslipRow({ id: 72, number: "PAY-000072", month: 7 }),
			]) as never,
		);
		const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
		renderWithRouter(<PayslipsList />, { extraPaths: PATHS });
		await screen.findByRole("table");
		expect(
			screen.queryByRole("columnheader", { name: "Reports sent" }),
		).toBeNull();
		await user.click(screen.getByLabelText(/show session counts/i));
		for (const name of ["Reports sent", "Reports not sent", "Teacher absences"]) {
			expect(screen.getByRole("columnheader", { name })).toBeInTheDocument();
		}
		const cells = (number: string) =>
			within(screen.getByRole("row", { name: new RegExp(number) }))
				.getAllByRole("cell")
				.slice(-3)
				.map((cell) => cell.textContent);
		expect(cells("PAY-000071")).toEqual(["4", "1", "2"]);
		expect(cells("PAY-000072")).toEqual(["—", "—", "—"]);
	});

	it("names teachers whose fixed salary is in an old currency", async () => {
		vi.mocked(payrollApi.generate).mockResolvedValue(
			generateResult({ stale_fixed_salary: [{ id: 21, full_name: "Bilal" }] }),
		);
		const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
		renderWithRouter(<PayslipsList />, { extraPaths: PATHS });
		await screen.findByRole("table");
		await user.click(screen.getByRole("button", { name: "Generate" }));
		expect(
			await screen.findByText(
				/The fixed salary of Bilal is in a currency they are no longer paid in/,
			),
		).toBeInTheDocument();
	});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll`
Expected: FAIL.

- [ ] **Step 3: `PayslipBody.tsx`**

Keep Plan 46's `LineBadges` component as it is. Replace the rest of the file:

```tsx
import { Fragment, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import { StatusChip } from "@/ui"; // LineBadges (kept) uses it
import { type PayslipDetail, type PayslipLine, REPORT_COUNT_KEYS } from "./schemas";

function LineList({
	lines,
	money,
}: {
	lines: PayslipLine[];
	money: (minor: number) => ReactNode;
}) {
	return (
		<ul className="flex flex-col gap-1 text-sm">
			{lines.map((line) => (
				<li key={line.id} className="flex flex-wrap justify-between gap-2">
					<span>{line.description}</span>
					{money(line.amount_minor)}
				</li>
			))}
		</ul>
	);
}

/** A payslip's lines and totals (spec §6): the fixed salary (slice B4b),
 * then sessions, bonuses and deductions, and missing-report deductions; then
 * the totals and the counters it has. The payslip page, the teacher's page
 * and the print sheet show exactly this. */
export function PayslipBody({ payslip }: { payslip: PayslipDetail }) {
	const { t } = useTranslation();
	const of = (kind: PayslipLine["kind"]) =>
		payslip.lines.filter((line) => line.kind === kind);
	const fixed = of("fixed");
	const sessions = of("session");
	const adjustments = of("adjustment");
	const reports = of("report");
	const counters = REPORT_COUNT_KEYS.filter((key) => payslip[key] !== null);
	const money = (minor: number) => (
		<Money minor={minor} currency={payslip.currency} />
	);
	// Slice B4b F-2 (plan R12): a fixed-salary month lists its sessions with
	// no rate, as a member line has none: neither is a missing rate.
	const rateOf = (line: PayslipLine) =>
		line.rate_minor !== null
			? money(line.rate_minor)
			: fixed.length > 0 || line.group_role === "member"
				? "—"
				: t("payroll.payslip.noRate");
	const heading = "py-2 font-medium";
	return (
		<>
			{fixed.length > 0 ? (
				<section className="flex flex-col gap-2">
					<h2 className="font-semibold">{t("payroll.payslip.fixed")}</h2>
					<LineList lines={fixed} money={money} />
					<p className="text-sm text-muted-foreground">
						{t("payroll.payslip.fixedNote")}
					</p>
				</section>
			) : null}
			<section className="flex flex-col gap-2">
				<h2 className="font-semibold">{t("payroll.payslip.sessions")}</h2>
				{sessions.length === 0 ? (
					<p className="text-sm text-muted-foreground">
						{t("payroll.payslip.noSessions")}
					</p>
				) : (
					<div className="overflow-x-auto">
						<table className="w-full text-sm">
							<thead className="border-b border-border text-muted-foreground">
								<tr>
									<th scope="col" className={`${heading} text-start`}>
										{t("payroll.columns.description")}
									</th>
									<th scope="col" className={`${heading} text-end`}>
										{t("payroll.columns.minutes")}
									</th>
									<th scope="col" className={`${heading} text-end`}>
										{t("payroll.columns.rate")}
									</th>
									<th scope="col" className={`${heading} text-end`}>
										{t("payroll.columns.amount")}
									</th>
								</tr>
							</thead>
							<tbody>
								{sessions.map((line) => (
									<tr key={line.id} className="border-b border-border">
										<td className="py-2">
											{line.description}
											<LineBadges line={line} />
										</td>
										<td className="py-2 text-end">{line.minutes}</td>
										<td className="py-2 text-end">{rateOf(line)}</td>
										<td className="py-2 text-end">
											{money(line.amount_minor)}
										</td>
									</tr>
								))}
							</tbody>
						</table>
					</div>
				)}
			</section>
			<section className="flex flex-col gap-2">
				<h2 className="font-semibold">{t("payroll.payslip.adjustments")}</h2>
				{adjustments.length === 0 ? (
					<p className="text-sm text-muted-foreground">
						{t("payroll.payslip.noAdjustments")}
					</p>
				) : (
					<LineList lines={adjustments} money={money} />
				)}
			</section>
			{reports.length > 0 ? (
				<section className="flex flex-col gap-2">
					<h2 className="font-semibold">{t("payroll.payslip.reports")}</h2>
					<LineList lines={reports} money={money} />
				</section>
			) : null}
			<dl className="ms-auto grid w-full max-w-xs grid-cols-2 gap-2 border-t border-border pt-4 text-sm">
				<dt>{t("payroll.columns.gross")}</dt>
				<dd className="text-end">{money(payslip.gross_minor)}</dd>
				<dt>{t("payroll.columns.bonuses")}</dt>
				<dd className="text-end">{money(payslip.bonuses_minor)}</dd>
				<dt>{t("payroll.columns.deductions")}</dt>
				<dd className="text-end">{money(payslip.deductions_minor)}</dd>
				<dt className="font-semibold">{t("payroll.columns.net")}</dt>
				<dd className="text-end font-semibold">{money(payslip.net_minor)}</dd>
			</dl>
			{counters.length > 0 ? (
				<dl className="ms-auto grid w-full max-w-xs grid-cols-2 gap-2 text-sm text-muted-foreground">
					{counters.map((key) => (
						<Fragment key={key}>
							<dt>{t(`payroll.counts.${key}`)}</dt>
							<dd className="text-end">{payslip[key]}</dd>
						</Fragment>
					))}
				</dl>
			) : null}
		</>
	);
}
```

Trunk places `LineBadges` inside the description cell, after the text, as above; keep it so. Trunk's member-line rate cell (`"—"` before `noRate`) is the rule `rateOf` extends. The `payslip[key] !== null` filter also hides a counter that the teacher's payload left out: every counter is a staff and teacher field, never staff-only.

- [ ] **Step 4: `PayslipsList.tsx`**

- Import `REPORT_COUNT_KEYS`.
- Where Plan 46 appends one `<th>` per `COUNT_KEYS` while the toggle is on, append right after them:

```tsx
					{REPORT_COUNT_KEYS.map((key) => (
						<th key={key} scope="col" className="p-3 text-start font-medium">
							{t(`payroll.counts.${key}`)}
						</th>
					))}
```

- Per row, right after Plan 46's count cells:

```tsx
					{REPORT_COUNT_KEYS.map((key) => (
						<td key={key} className="p-3">
							{payslip[key] ?? "—"}
						</td>
					))}
```

  Both sit inside the same "counts shown" condition, so they are the last cells of the row. Trunk writes that condition as `{showCounts ? COUNT_KEYS.map(…) : null}` in both `<thead>` and `<tbody>`; wrap each branch in a fragment (`<>{COUNT_KEYS.map(…)}{REPORT_COUNT_KEYS.map(…)}</>`).
- In `GenerateSummary`, after the `other_currency` paragraph:

```tsx
				{result.stale_fixed_salary.length > 0 ? (
					<p>
						{t("payroll.list.staleFixedSalary", {
							names: names(result.stale_fixed_salary),
						})}{" "}
						<Link
							to="/payroll/rates"
							className="font-medium text-primary-text underline-offset-4 hover:underline"
						>
							{t("payroll.list.setRates")}
						</Link>
					</p>
				) : null}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll`, then `tsc --noEmit`, then `pnpm lint`
Expected: PASS. Trunk's `PayslipPage`, `PayslipPrint` and `TeacherPayslips` tests pass unchanged, because their payslips have no fixed or report line and null counters.

- [ ] **Step 6: Commit**

```bash
git -C $W/dashboard add src/features/payroll
git -C $W/dashboard commit -m "feat(payroll): fixed and report sections, counters on payslips and the list (B4b §6)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: End-to-end through Caddy, and the slice gates

**Files:**
- Create: `dashboard/e2e/b4-report-deductions.spec.ts`

**Interfaces:**
- Consumes: `login`, `DEMO_URL`, `DEMO_ADMIN`, `expectLoggedIn`, `gotoApp`, `postAsAdmin` (`e2e/fixtures.ts`); `manage` (`e2e/manage.ts`); the request bodies of Plan 46's `b4-pay-rules.spec.ts` (people, course, extra session, attendance, rate), which the bodies below already match.

- [ ] **Step 1: Write the E2E**

```ts
import { expect, test } from "@playwright/test";
import {
	DEMO_ADMIN,
	DEMO_URL,
	expectLoggedIn,
	gotoApp,
	login,
	postAsAdmin,
} from "./fixtures";
import { manage } from "./manage";

const SWITCHES = [
	"payroll_rules",
	"session_reports",
	"report_deductions",
	"incentives_deductions",
	"extra_sessions",
];

/** The 15th of last month (UTC, the demo academy's clock): always over, and
 * its session ended far more than 24 hours ago. Also its year and month. */
function lastMonthMid() {
	const now = new Date();
	const mid = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 15));
	return {
		day: mid.toISOString().slice(0, 10),
		year: mid.getUTCFullYear(),
		month: mid.getUTCMonth() + 1,
	};
}

test.afterAll(() => {
	manage(
		"set_features",
		"demo",
		"--off",
		"report_deductions",
		"incentives_deductions",
		"payroll_rules",
	);
});

// Slice B4b §8: at 50 %, a session with the student present and no report
// loses half its pay in a "Missing report" line, and a 10 % bonus pays 10 %
// of the gross. The test owns its teacher, course and student (stamped), so
// the seeds' payslips and re-runs never meet it.
test("a missing report costs its share and a percentage bonus its share of the gross", async ({
	page,
}) => {
	test.setTimeout(90_000);
	const stamp = Date.now();
	const { day, year, month } = lastMonthMid();
	manage("set_features", "demo", "--on", ...SWITCHES);
	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	const created = async (path: string, data: object) => {
		const response = await postAsAdmin(page, path, data);
		expect(response.ok(), `${path}: ${await response.text()}`).toBeTruthy();
		return response.json();
	};
	const teacher = await created("people/teachers/", {
		user: {
			full_name: `E2E Reports ${stamp}`,
			email: `e2e-reports-${stamp}@e2e.test`,
		},
		profile: { gender: "male" },
	});
	const course = await created("catalogue/courses/", {
		name_ar: `تقارير ${stamp}`,
		name_en: `E2E Reports ${stamp}`,
		teacher_ids: [teacher.id],
	});
	const student = await created("people/students/", {
		user: {
			full_name: `E2E Reported ${stamp}`,
			email: `e2e-reported-${stamp}@e2e.test`,
		},
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
		student_attendance: "present",
		teacher_attendance: "present",
	});
	await created("payroll/rates/", { teacher: teacher.id, hourly_rate_minor: 2000 });
	await created("payroll/adjustments/", {
		teacher: teacher.id,
		kind: "bonus",
		amount_minor: null,
		percent_bp: 1000,
		effective_on: day,
		reason: `E2E incentive ${stamp}`,
	});

	// The rule: half a session's pay for a missing report
	const share = page.getByLabel(/missing report deduction/i);
	await gotoApp(page, `${DEMO_URL}/app/payroll/settings`, share);
	await share.fill("50");
	await page.getByRole("button", { name: /save rules/i }).click();
	// Exact: the toast's live region briefly repeats it (as in b4-pay-rules).
	await expect(
		page.getByText("Payroll rules saved.", { exact: true }),
	).toBeVisible();

	// Generate last month and open the teacher's payslip. The payslips list
	// keeps its month in the page's picker, not the URL, so pick it there.
	await created("payroll/payslips/generate/", { year, month });
	await page.goto(`${DEMO_URL}/app/payroll/payslips`);
	await page.getByLabel("Year").selectOption(String(year));
	await page.getByLabel("Month").selectOption(String(month));
	await page
		.getByRole("row", { name: new RegExp(`E2E Reports ${stamp}`) })
		.getByRole("link")
		.click();
	await expect(page).toHaveURL(/\/app\/payroll\/payslips\/\d+$/);

	// Copied text is in the academy's default language (plan R15).
	const missing = page
		.getByRole("listitem")
		.filter({ hasText: /^(Missing report|تقرير غير مرسل) — / });
	await expect(missing).toHaveCount(1);
	await expect(missing).toContainText(/10\.00/); // 20.00/h x 60 min x 50 %
	const bonus = page
		.getByRole("listitem")
		.filter({ hasText: new RegExp(`10 (%|٪) — E2E incentive ${stamp}`) });
	await expect(bonus).toContainText(/2\.00/); // 10 % of 20.00
	await expect(page.getByText("Reports not sent")).toBeVisible();
});
```

- The bodies for people, courses, the extra session and attendance match Plan 46's merged `b4-pay-rules.spec.ts`. Never guess a body.
- The payslips list keeps its month in the page's Year/Month pickers, not the URL (as `b4-pay-rules.spec.ts` picks it).

- [ ] **Step 2: Run the E2E**

Run: `just e2e e2e/b4-report-deductions.spec.ts`
Expected: PASS. If it fails, debug with `superpowers:systematic-debugging` and never weaken an assertion.

- [ ] **Step 3: The slice gates**

Run: `just test`, `just lint`, `just e2e`
Expected: all green, coverage gates met. Keep the outputs for the final review.

- [ ] **Step 4: Commit**

```bash
git -C $W/dashboard add e2e/b4-report-deductions.spec.ts
git -C $W/dashboard commit -m "test(e2e): B4b missing-report deduction and percentage bonus

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Spec coverage

| Spec item | Task |
|---|---|
| I-1 percentage on `PayAdjustment`, one form, constraint, currency | 1, 3, 7 |
| I-2 base = gross (weighted sessions + fixed), rounding, description, zero stays pending, frozen at issue | 4 |
| I-3 refusals while off, edits/deletes still allowed, discovery/warning/build leave percentages out, not used at issue | 3, 6, 7, 9 |
| R-1 `report_deduction_bp`, effective only while `report_deductions` on, requires `payroll_rules`, PATCH 400 while off, form hides the field | 1, 2, 7, 9 |
| R-2 `missing_reports` ∩ lines, 24-hour window, report before issue, no refund after | 5 |
| R-3 report lines: per session, per class formula, zero → no line, totals, fixed month none | 5 |
| R-4 counters: sent, missing, absences, null rules, null on old payslips | 5, 7, 11 |
| F-1 `FixedSalary`, counts rule, stale currency named | 1, 2, 4, 6 |
| F-2 fixed line first, sessions at 0 and locked, no missing rate | 4, 6, 11 |
| F-3 active teachers discovered, inactive only via activity | 6 |
| F-4 late rows not reported | 6 |
| F-5 access: `payroll_rate.*`, 404 off, roles 403 | 7 |
| S-1 switches read once into `PaySettings` | 2 |
| §3 data, one migration, constraint replacement, `blank=True` | 1 |
| §4.1 build order, step 7 `missing_rate` | 4, 5 |
| §4.2 `UNSET`, row-after-patch rule, kind bonus | 3, 7 |
| §4.3 fixed-salary services, 409, `starts_on` normalised, locks | 2 |
| §4.4 discovery, `stale_fixed_salary`, issue refusals incl. report deductions | 5, 6 |
| §5 API (adjustments, fixed salaries, settings, generate, rows, CSV) | 7 |
| §6 dashboard (dialog, list, settings, Rates page, `PayslipBody`, counts toggle, generate result, strings) | 8–11 |
| §7 seed | 3 |
| §8 regression (switches off; switches stored true) | 6 |
| §8 E2E `e2e/b4-report-deductions.spec.ts` | 12 |
