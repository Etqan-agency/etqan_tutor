# Plan 15 — Slice B3a: Expenses, donations and net profit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Slice:** B3a
**Requires:** — (no other phase's slice)

**Goal:** An academy records what it spends (expenses) and what it is given (donations). Its admin home shows this month's expenses, net profit (revenue − expenses) and donations per currency. Other apps post expenses through one service, which B4 will use for paid payslips.

**Architecture:**
- **Backend:** a new tenant app, `etqan.finance` (A-1), owns `Expense`, `Donation` and a one-row `DonationCounter`. Its services are split by job:
  - `services/rules.py`: field checks and the no-future-date rule;
  - `services/expenses.py`: the admin's writes, the list filters, and `post_expense` / `withdraw_expense` for other apps;
  - `services/numbering.py`: donation numbers;
  - `services/donations.py`: the donation writes and filters;
  - `services/summary.py`: the month's expenses, net profit and donations.

  It reads revenue and the manual payment methods only through two additive `etqan.billing.services` exports (`revenue_between`, `MANUAL_PAYMENT_METHODS`). It has its own `finance.clock`, as billing does.
- **Dashboard:** a `features/finance` module, two pages under the admin Billing group (Expenses, Donations), a `FinanceSummaryCard` on the admin home, and a `/billing` index that opens the first billing page the user may see.
- **Off by default:** both features ship off, and the seeded demo academy turns them on through `seed_dev.FEATURES = BUILT`.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next, `Intl` for money and dates; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-03-b3a-expenses-donations-design.md` (slice B3a of `docs/superpowers/specs/2026-10-03-b3-money-depth-design.md`). It builds on Plan 6 billing (`2026-09-25-billing-design.md`), Plan 12a roles (`2026-09-28-roles-permissions-design.md`) and Plan 13 feature switches (`2026-09-30-feature-toggles-design.md`). Where this plan fills a gap in the spec, the Decisions below say so.

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), and the meta repo (trunk `master`). `marketing/` is not touched.
- The branch `feat/b3a-money` already exists in the meta worktree, `backend/` and `dashboard/`, so do not create it. Check with `git -C backend branch --show-current` and `git -C dashboard branch --show-current` before Task 1 and Task 8.
- **Never run `git submodule update`, `add`, `sync` or any other `git submodule` command that writes.** This worktree's submodules are worktrees of the main checkout's.
- Commits use Conventional Commits and end with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Commit in the submodule the change lives in (`git -C backend …`, `git -C dashboard …`), never the submodule pointers in meta.

**Shared lists:** add lines only under the `── phase B3 ──` markers. That covers:
- `TENANT_APPS` (`backend/config/settings/base.py`);
- `config/api_router.py`;
- the feature registry (`etqan/platform/features.py`). `donations` is changed in place, as the registry's comment says;
- the access `RESOURCES` (`etqan/access/registry.py`);
- `seed_academy` (`etqan/tenants/management/commands/seed_dev.py`), with its data in `etqan/tenants/seeds/finance.py`;
- `backend/pyproject.toml`, in both the platform contract's forbidden list and the contracts section;
- the dashboard's `NAV_ITEMS`.

New translations go in the new files `dashboard/src/locales/{en,ar}/finance.json`. Test tables that have no markers take additive edits only; expect rebase conflicts there and keep both sides:
- `access/tests/test_routes.py` and `test_registry.py`;
- `platform/tests/test_features.py`;
- `features/shell/nav.test.ts`;
- `features/identity/schemas.ts` (`FeatureCode`);
- the imports of `nav.ts`, `seed_dev.py` and `routes/_authed/index.tsx`.

**Features:** `expenses` and `donations` are built with `default=False` (`_built(...)` defaults to `True`, so the `default=False` must be written out).

**Backend commands.** Run them from the meta worktree, inside this stream's own stack, which must be up (`just dev-backend`). Load the stream's ports first:
```bash
set -a && . ./.env.stream && set +a
DJ="docker compose -f docker-compose.local.yml exec -T django"
```
- Tests: `$DJ pytest etqan/finance -q` (or any path). Add `--create-db` once after Task 1, which adds migrations.
- Migrations: `$DJ python manage.py makemigrations finance`.
- Format: `$DJ sh -c 'ruff check --fix . && ruff format .'`
- Verify: `$DJ sh -c 'ruff check . && ruff format --check . && lint-imports && pytest -q --cov=etqan'`
- Never run `manage.py`, `migrate` or e2e any other way. `.env.stream` is what points them at this stream's database.
- Lint: watch `PLR0913`. Keyword-only signatures that mirror an API body carry `# noqa: PLR0913 -- <reason>`, as billing does. An argument named `type` carries `# noqa: A002 -- <reason>` on its own line, and ruff accepts that.

**Dashboard commands.** Run them from `dashboard/` through `npx pnpm@10`.
- Format: `npx pnpm@10 exec biome check --write src e2e`
- New route files are picked up by the TanStack Router plugin. Regenerate `src/routeTree.gen.ts` with `npx pnpm@10 exec vite build` before `tsc`; it is generated, so never hand-edit it.
- Verify: `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`. Use semantic tokens only (`text-destructive`, `text-muted-foreground`, …): no hex literals and no Tailwind palette utilities, not even in comments.
- `tsc` has `noUnusedLocals` and `noUnusedParameters`.

**Gates before queuing:**
- `just test`, `just lint` and `just e2e`, all against this stream's stack;
- backend coverage ≥ 80 %;
- dashboard lines and statements ≥ 80, branches and functions ≥ 70.

**Money:** integer minor units plus an ISO 4217 currency, never summed across currencies. Every user-facing string comes in Arabic and English.

## Decisions (gaps the spec left, filled here)

| # | Decision |
|---|---|
| D1 | `Donation.Method` is a static `TextChoices` in `finance.models`: billing's nine manual methods in billing's order, then `stripe` and `paypal`. It is static rather than computed so the model module never imports billing's services at app-loading time. A test pins it to `billing.services.MANUAL_PAYMENT_METHODS` + `stripe` + `paypal`, so the two cannot drift. |
| D2 | The `posted` list filter is a `ChoiceField(("true", "false"))`, not a `BooleanField`: DRF reads a missing boolean in a query string as `False`, which would hide every posted expense by default. |
| D3 | `FEATURE_WORDS` in `access/tests/test_routes.py` gains `"/expenses/": "expenses"`, `"/donations/": "donations"` and `"/finance/summary/": "expenses"`. A single `"/finance/"` word cannot work, because finance's routes belong to two features. |
| D4 | The import-linter gains three B3 contracts under the B3 marker, and the existing single-line lists are not edited: <br>• "finance reaches other apps only through their services"; <br>• "other apps reach finance only through its services"; <br>• "billing never imports finance". <br>The first forbids finance `etqan.billing.{models,api,scopes,clock}`, which has the same effect as adding finance to the existing "other apps reach billing only through its services" list. |
| D5 | The 409 for a posted expense is translated by a finance helper, `financeErrorText`, from `finance.json`. The shared `errors.json` is not edited. |
| D6 | `PATCH` bodies ignore keys that are not writable (`source`, `source_id`, `number`), as DRF serializers do. A test pins that they change nothing. |
| D7 | The home card is one component, `FinanceSummaryCard expenses donations`. `Home` renders it behind `widget.revenue_stats`, passing each feature from `me`. With both features off it renders nothing. |
| D8 | Seeded amounts are in EGP, the demo packages' currency, so the demo's net profit nets against its EGP revenue. Each expense is dated the first of the academy's current month. |

## Review Focus

These are inputs the spec implies but no requirement names. Each one has a test in the task named.

1. **A list request with no `posted` parameter.** Every expense is listed, posted ones included; a missing boolean must never mean `false` (D2). The test is in Task 6.
2. **A `PATCH` that sends `source`, `source_id` or `number`.** These keys are ignored, so a manual expense never becomes "posted" and a donation never changes its number (D6). The test is in Task 6.
3. **The default date near the academy's midnight.** An expense saved at 23:30 UTC, when the academy is in Asia/Tokyo, is dated the academy's today (the next day), not the UTC day. The test is in Task 3.
4. **A donation edited from completed to pending.** It leaves this month's donation total at once. The test is in Task 5.
5. **An amount with more decimals than its currency has** ("1.234" EGP, "1.5" JPY). The dialog refuses it rather than rounding it into minor units. The test is in Task 9.

## File structure

**Backend (`backend/`)**

| Path | Responsibility |
|---|---|
| `etqan/finance/__init__.py`, `apps.py` | the app |
| `etqan/finance/clock.py` | the only clock finance reads (academy calendar) |
| `etqan/finance/models.py` | `Expense`, `Donation`, `DonationCounter` |
| `etqan/finance/migrations/0001_initial.py` | generated |
| `etqan/finance/services/__init__.py` | the public API other apps import |
| `etqan/finance/services/rules.py` | `check`, `save`, `not_future` |
| `etqan/finance/services/expenses.py` | expense writes and filters, plus `post_expense` / `withdraw_expense` |
| `etqan/finance/services/numbering.py` | `DON-000001` numbers |
| `etqan/finance/services/donations.py` | donation writes and filters |
| `etqan/finance/services/summary.py` | the month's expenses, net profit and donations |
| `etqan/finance/api/{__init__,serializers,payloads,views,urls}.py` | `/api/v1/finance/` |
| `etqan/finance/tests/…` | conftest and tests per area |
| `etqan/billing/services/summary.py`, `payments.py`, `__init__.py` | `revenue_between`, `MANUAL_PAYMENT_METHODS` (additive) |
| `etqan/tenants/seeds/finance.py` | the demo data and `seed_finance` |
| `config/settings/base.py`, `config/api_router.py`, `pyproject.toml`, `etqan/platform/features.py`, `etqan/access/registry.py`, `etqan/tenants/management/commands/seed_dev.py` | one line, or one block, under each B3 marker |

**Dashboard (`dashboard/`)**

| Path | Responsibility |
|---|---|
| `src/features/finance/schemas.ts` | types, option lists, form schemas |
| `src/features/finance/api.ts`, `queries.ts` | the routes and their React Query hooks |
| `src/features/finance/landing.ts` | `billingLanding(me)` for the `/billing` index |
| `src/features/finance/bits.tsx` | `financeErrorText`, `PostedBadge` |
| `src/features/finance/ExpensesList.tsx`, `ExpenseDialog.tsx` | the Expenses page |
| `src/features/finance/DonationsList.tsx`, `DonationDialog.tsx` | the Donations page |
| `src/features/finance/FinanceSummaryCard.tsx` | the home card |
| `src/features/finance/index.ts` | the module's exports |
| `src/routes/_authed/billing.expenses.tsx`, `billing.donations.tsx`, `billing.index.tsx` | routes |
| `src/locales/{en,ar}/finance.json` | the new translation area |
| `src/test/finance-fixtures.ts` | API-shaped rows for tests |
| `e2e/b3-finance.spec.ts` | the journey through Caddy |

---

### Task 1: The finance app, its models, its two features and its import contracts

**Files:**
- Create: `backend/etqan/finance/__init__.py`, `apps.py`, `clock.py`, `models.py`, `migrations/__init__.py`, `migrations/0001_initial.py` (generated), `services/__init__.py` (empty for now), `tests/__init__.py`, `tests/conftest.py`, `tests/test_models.py`
- Modify: `backend/config/settings/base.py` (B3 marker in `TENANT_APPS`), `backend/etqan/platform/features.py` (`donations` in place; `expenses` under the B3 marker), `backend/etqan/platform/tests/test_features.py`, `backend/pyproject.toml` (B3 markers)

**Interfaces:**
- Produces:
  - `etqan.finance.models.Expense` with `Type` choices `salaries · rent · marketing · software · utilities · supplies · fees · other`;
  - `Donation` with `Method` choices (D1) and `Status` choices `pending · completed · failed · refunded · cancelled`;
  - `DonationCounter`;
  - `etqan.finance.clock.now() -> datetime` and `today() -> date`;
  - the test fixtures `clock` (pins scheduling, billing and finance), `world`, `admin` and `finance_on` (switches both features on).

- [ ] **Step 1: Write the failing feature-registry test**

Edit `backend/etqan/platform/tests/test_features.py`: the `BUILT` dict gains the two features in registry order (`donations` sits where its `_later` line was, `expenses` under the B3 marker at the end), and the counts move by one.

```python
BUILT = {
    "families": True,
    "parents": True,
    "supervision": False,
    "session_reports": True,
    "invoices": True,
    "auto_notifications": True,
    "teacher_attendance": True,
    "export": True,
    # Phase B3 (slice B3a): built, off by default (orchestration PO-5).
    "donations": False,
    "expenses": False,
}
```

In `test_the_registry_has_36_unique_codes_in_both_languages`:
- rename the test to `test_the_registry_has_37_unique_codes_in_both_languages`;
- change both `36`s to `37`.

In `test_the_defaults_match_the_spec`:
- change `assert len(unbuilt) == 28` to `assert len(unbuilt) == 27`;
- replace the docstring with `"""§3.1: the built features, on by default but supervision and phase B3's; §3.2: the unbuilt ones are stored now and off by default."""`.

- [ ] **Step 2: Run it to verify it fails**

Run: `$DJ pytest etqan/platform/tests/test_features.py -q`
Expected: FAIL (`BUILT` has 8 entries, registry has 36 codes).

- [ ] **Step 3: Register the features**

In `backend/etqan/platform/features.py`, replace the line `_later("donations", "Donations", "نظام التبرعات", "money"),` in place with:

```python
    # Phase B3 (slice B3a): built, off by default (orchestration PO-5).
    _built("donations", "Donations", "نظام التبرعات", "money", default=False),
```

and under `# ── phase B3 ──` add:

```python
    # ── phase B3 ──
    _built("expenses", "Expenses", "نظام المصروفات", "money", default=False),
```

- [ ] **Step 4: Run it to verify it passes**

Run: `$DJ pytest etqan/platform/tests/test_features.py -q`
Expected: PASS.

- [ ] **Step 5: Write the failing model tests**

`backend/etqan/finance/tests/__init__.py`: empty.

`backend/etqan/finance/tests/conftest.py`:

```python
"""Finance fixtures. Every clock is pinned to Monday 1 June 2026, 08:00 UTC:
scheduling's (sessions), billing's (invoice and payment dates) and
finance's (expense and donation dates, the month)."""

import pytest

from etqan.billing.tests.conftest import Clock as BillingClock
from etqan.finance import clock as finance_clock
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_admin


class Clock(BillingClock):
    def set(self, when) -> None:
        super().set(when)
        self._monkeypatch.setattr(finance_clock, "now", lambda: when)


@pytest.fixture
def clock(monkeypatch):
    return Clock(monkeypatch)


@pytest.fixture
def world(clock):
    """Scheduling's world: student Yusuf, teacher Bilal, course Tajweed and
    the Monthly package at 150000 EGP."""
    return build_world()


@pytest.fixture
def admin():
    return make_admin()


@pytest.fixture
def finance_on(set_features):
    """Both B3a features switched on for the academy under test (they ship
    off, A-2)."""
    return set_features(expenses=True, donations=True)
```

`backend/etqan/finance/tests/test_models.py`:

```python
"""B3a spec §3: the constraints the database itself keeps."""

from datetime import date

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.billing import services as billing_services
from etqan.finance.models import Donation
from etqan.finance.models import Expense


def expense(**overrides):
    fields = {
        "title": "Rent",
        "type": Expense.Type.RENT,
        "amount_minor": 1000,
        "currency": "EGP",
        "spent_on": date(2026, 6, 1),
        **overrides,
    }
    return Expense.objects.create(**fields)


def refused(**overrides):
    with pytest.raises(IntegrityError), transaction.atomic():
        expense(**overrides)


def test_an_amount_must_be_positive():
    refused(amount_minor=0)
    with pytest.raises(IntegrityError), transaction.atomic():
        Donation.objects.create(
            number="DON-000001",
            amount_minor=0,
            currency="EGP",
            method="cash",
            received_on=date(2026, 6, 1),
        )


def test_a_source_and_its_id_come_together():
    refused(source="payroll.payslip")
    refused(source_id=7)
    assert expense(source="payroll.payslip", source_id=7).source_id == 7
    assert expense().source == ""


def test_one_expense_per_source_row_but_any_number_of_manual_ones():
    expense(source="payroll.payslip", source_id=7)
    refused(source="payroll.payslip", source_id=7)
    expense(source="payroll.payslip", source_id=8)
    expense()
    expense()
    assert Expense.objects.count() == 4


def test_donation_methods_extend_billings_manual_methods():
    """D1: billing's manual methods, in billing's order, then the two
    gateways (A-6)."""
    manual = [value for value, _ in billing_services.MANUAL_PAYMENT_METHODS]
    assert Donation.Method.values == [*manual, "stripe", "paypal"]
    assert Donation.Status.values == [
        "pending",
        "completed",
        "failed",
        "refunded",
        "cancelled",
    ]


def test_rows_read_newest_first():
    older = expense(spent_on=date(2026, 5, 31))
    newer = expense(spent_on=date(2026, 6, 2))
    same_day = expense(spent_on=date(2026, 6, 2))
    assert list(Expense.objects.all()) == [same_day, newer, older]
```

(`MANUAL_PAYMENT_METHODS` arrives in Task 2; this one test stays red until then — run the others with `-k "not extend"` in Step 6 and Step 9.)

- [ ] **Step 6: Run them to verify they fail**

Run: `$DJ pytest etqan/finance -q -k "not extend"`
Expected: FAIL (`ModuleNotFoundError: etqan.finance`).

- [ ] **Step 7: Write the app**

`backend/etqan/finance/__init__.py`:

```python
"""Expenses, donations and net profit (phase B3, slice B3a)."""
```

`backend/etqan/finance/apps.py`:

```python
from django.apps import AppConfig


class FinanceConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.finance"
    label = "finance"
```

`backend/etqan/finance/clock.py`:

```python
"""The only clock finance reads, so tests pin it by monkeypatching `now`."""

from datetime import date
from datetime import datetime
from zoneinfo import ZoneInfo

from django.utils import timezone

from etqan.academy import services as academy_services


def now() -> datetime:
    """The current instant, timezone-aware UTC."""
    return timezone.now()


def today() -> date:
    """Today on the academy's calendar (`AcademySettings.timezone`): money is
    dated, and this month counted, by it (B3a §4)."""
    return now().astimezone(ZoneInfo(academy_services.get_settings().timezone)).date()
```

`backend/etqan/finance/models.py`:

```python
"""Expenses, donations and donation numbering (B3a spec §3, A-1).

Other apps' models are referenced by string: finance never imports them.
Business rules live in `etqan.finance.services`.
"""

from django.conf import settings
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
from django.db import models
from django.db.models import Q

CURRENCY = RegexValidator(r"^[A-Z]{3}$")


class Expense(models.Model):
    """Money the academy spent (audit BILL-006). A posted expense names the
    row of another app it stands for (``source``, ``source_id``, A-8)."""

    class Type(models.TextChoices):
        # Audit BILL-006 saw "salaries"; the rest are assumed (A-4).
        SALARIES = "salaries", "Salaries"
        RENT = "rent", "Rent"
        MARKETING = "marketing", "Marketing"
        SOFTWARE = "software", "Software"
        UTILITIES = "utilities", "Utilities"
        SUPPLIES = "supplies", "Supplies"
        FEES = "fees", "Fees"
        OTHER = "other", "Other"

    title = models.CharField(max_length=200)
    type = models.CharField(max_length=12, choices=Type.choices)
    amount_minor = models.BigIntegerField(validators=[MinValueValidator(1)])
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    spent_on = models.DateField()  # the academy's calendar
    notes = models.TextField(blank=True, default="")
    # Blank for an admin's expense; "payroll.payslip" and the payslip's id for
    # one another app posted (A-8).
    source = models.CharField(max_length=40, blank=True, default="")
    source_id = models.BigIntegerField(null=True, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-spent_on", "-id"]
        constraints = [
            models.CheckConstraint(
                condition=Q(amount_minor__gt=0), name="finance_expense_amount_positive"
            ),
            models.CheckConstraint(
                condition=(Q(source="") & Q(source_id__isnull=True))
                | (~Q(source="") & Q(source_id__isnull=False)),
                name="finance_expense_source_pair",
            ),
            models.UniqueConstraint(
                fields=["source", "source_id"],
                condition=~Q(source=""),
                name="finance_expense_one_per_source",
            ),
        ]
        indexes = [models.Index(fields=["spent_on"])]

    def __str__(self):
        return f"Expense<{self.title}, {self.amount_minor} {self.currency}>"


class DonationCounter(models.Model):
    """The last donation number handed out. One row (pk 1) in each academy's
    schema, locked while a number is taken, as invoices are numbered."""

    last_number = models.PositiveIntegerField(default=0)

    def __str__(self):
        return f"DonationCounter<{self.last_number}>"


class Donation(models.Model):
    """Money the academy was given (audit BILL-005). Never revenue (B3-5)."""

    class Method(models.TextChoices):
        # D1: billing's manual methods (`billing.services.MANUAL_PAYMENT_METHODS`,
        # pinned by a test), then the gateways a donation may arrive by.
        CASH = "cash", "Cash"
        BANK_TRANSFER = "bank_transfer", "Bank transfer"
        INSTAPAY = "instapay", "InstaPay"
        VODAFONE_CASH = "vodafone_cash", "Vodafone Cash"
        WESTERN_UNION = "western_union", "Western Union"
        ZELLE = "zelle", "Zelle"
        VENMO = "venmo", "Venmo"
        CASHAPP = "cashapp", "Cash App"
        OTHER = "other", "Other"
        STRIPE = "stripe", "Stripe"
        PAYPAL = "paypal", "PayPal"

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        COMPLETED = "completed", "Completed"
        FAILED = "failed", "Failed"
        REFUNDED = "refunded", "Refunded"
        CANCELLED = "cancelled", "Cancelled"

    number = models.CharField(max_length=20, unique=True)
    amount_minor = models.BigIntegerField(validators=[MinValueValidator(1)])
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    method = models.CharField(max_length=16, choices=Method.choices)
    transaction_number = models.CharField(max_length=120, blank=True, default="")
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.COMPLETED
    )
    donor_name = models.CharField(max_length=120, blank=True, default="")
    donor_email = models.EmailField(blank=True, default="")
    received_on = models.DateField()  # the academy's calendar
    notes = models.TextField(blank=True, default="")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-received_on", "-id"]
        constraints = [
            models.CheckConstraint(
                condition=Q(amount_minor__gt=0), name="finance_donation_amount_positive"
            )
        ]
        indexes = [models.Index(fields=["received_on"])]

    def __str__(self):
        return f"Donation<{self.number}, {self.status}>"
```

`backend/etqan/finance/migrations/__init__.py` and `backend/etqan/finance/services/__init__.py`: empty files for now (services gets its docstring and exports in Task 3).

In `backend/config/settings/base.py`, under `TENANT_APPS`'s marker:

```python
    # ── phase B3 ──
    "etqan.finance",
```

In `backend/pyproject.toml`:

1. In the "platform imports no business modules" contract's `forbidden_modules`, under its `# ── phase B3 ──`:

```toml
    # ── phase B3 ──
    "etqan.finance",
```

2. In the contracts section, under `# ── phase B3 ──` (D4):

```toml
# ── phase B3 ──
[[tool.importlinter.contracts]]
name = "finance reaches other apps only through their services"
type = "forbidden"
# B3a A-1: revenue and the payment methods through billing's services, the
# timezone through academy's; never another app's models.
source_modules = ["etqan.finance"]
forbidden_modules = [
    "etqan.identity.models", "etqan.identity.api",
    "etqan.catalogue",
    "etqan.academy.models", "etqan.academy.api",
    "etqan.scheduling.models", "etqan.scheduling.api",
    "etqan.billing.models", "etqan.billing.api", "etqan.billing.scopes", "etqan.billing.clock",
    "etqan.payroll", "etqan.notifications", "etqan.access",
    "etqan.tenants", "etqan.site",
]
# finance.services -> billing.services -> billing.models is the allowed path.
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "other apps reach finance only through its services"
type = "forbidden"
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.scheduling", "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access"]
forbidden_modules = ["etqan.finance.models", "etqan.finance.api", "etqan.finance.clock"]
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "billing never imports finance"
type = "forbidden"
# A-1: finance reads billing's revenue; billing never reads finance.
source_modules = ["etqan.billing"]
forbidden_modules = ["etqan.finance"]
```

- [ ] **Step 8: Generate the migration**

Run: `$DJ python manage.py makemigrations finance`
Expected: `etqan/finance/migrations/0001_initial.py` with `Expense`, `DonationCounter`, `Donation`, the three constraints and two indexes.

- [ ] **Step 9: Run the tests and the contracts**

Run: `$DJ pytest etqan/finance etqan/platform -q --create-db -k "not extend" && $DJ lint-imports`
Expected: PASS; every contract kept.

- [ ] **Step 10: Commit**

```bash
git -C backend add etqan/finance config/settings/base.py etqan/platform/features.py etqan/platform/tests/test_features.py pyproject.toml
git -C backend commit -m "feat(finance): expenses and donations models, features off by default

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Billing's two additive exports

**Files:**
- Modify: `backend/etqan/billing/services/summary.py`, `backend/etqan/billing/services/payments.py`, `backend/etqan/billing/services/__init__.py`
- Test: `backend/etqan/billing/tests/test_summary.py`

**Interfaces:**
- Produces:
  - `billing.services.revenue_between(first: date, following: date) -> list[dict]`, returning `[{"currency", "amount_minor"}]` in currency order;
  - `billing.services.MANUAL_PAYMENT_METHODS: tuple[tuple[str, str], ...]`.

  `revenue_this_month()` is unchanged in behaviour.

- [ ] **Step 1: Write the failing tests**

Append to `backend/etqan/billing/tests/test_summary.py`:

```python
def test_revenue_between_sums_a_window_per_currency(world, admin, clock):
    """B3a §4.5: payments with first <= paid_on < following, per currency;
    finance counts its own month with it."""
    clock.set(datetime(2026, 6, 20, 9, tzinfo=UTC))
    egp = invoice(world.student, admin, 10000)
    usd = invoice(world.student, admin, 5000, currency="USD")
    pay(egp, admin, 1000, date(2026, 5, 31))
    pay(egp, admin, 2000, date(2026, 6, 1))
    pay(egp, admin, 3000, date(2026, 6, 19))
    pay(usd, admin, 700, date(2026, 6, 20))
    assert services.revenue_between(date(2026, 6, 1), date(2026, 6, 20)) == [
        {"currency": "EGP", "amount_minor": 5000}
    ]
    assert services.revenue_between(date(2026, 6, 1), date(2026, 7, 1)) == [
        {"currency": "EGP", "amount_minor": 5000},
        {"currency": "USD", "amount_minor": 700},
    ]
    assert services.revenue_between(date(2026, 7, 1), date(2026, 8, 1)) == []
    assert services.summary()["revenue_this_month"] == services.revenue_between(
        date(2026, 6, 1), date(2026, 7, 1)
    )


def test_the_manual_payment_methods_are_the_payment_choices():
    """B3a §4.5: what finance's donation methods extend (D1)."""
    assert services.MANUAL_PAYMENT_METHODS == tuple(Payment.Method.choices)
    assert services.MANUAL_PAYMENT_METHODS[0] == ("cash", "Cash")
```

and add `from etqan.billing.models import Payment` to the file's imports.

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/billing/tests/test_summary.py -q`
Expected: FAIL (`AttributeError: … has no attribute 'revenue_between'`).

- [ ] **Step 3: Implement**

In `backend/etqan/billing/services/summary.py`, replace `revenue_this_month` with:

```python
def revenue_between(first: date, following: date) -> list[dict]:
    """The one revenue query (B3a §4.5): payments with
    ``first <= paid_on < following``, summed per currency, in currency
    order. Finance nets this month's expenses against it."""
    rows = (
        Payment.objects.filter(paid_on__gte=first, paid_on__lt=following)
        .values(currency=F("invoice__currency"))
        .annotate(amount_minor=Sum("amount_minor"))
        .order_by("currency")
    )
    return [
        {"currency": row["currency"], "amount_minor": row["amount_minor"]}
        for row in rows
    ]


def revenue_this_month() -> list[dict]:
    """Payments whose `paid_on` falls in the academy's current calendar month
    (its timezone decides the month near midnight)."""
    return revenue_between(*month_of(clock.today()))
```

In `backend/etqan/billing/services/payments.py`, after the imports:

```python
# B3a §4.5: the manual methods, as (value, label) pairs, for the apps that
# take money the same ways (finance's donations extend them).
MANUAL_PAYMENT_METHODS = tuple(Payment.Method.choices)
```

In `backend/etqan/billing/services/__init__.py`, add the imports in alphabetical position and the names to `__all__` (alphabetical; constants first, as `FILTER_STATUSES` is):

```python
from etqan.billing.services.payments import MANUAL_PAYMENT_METHODS
from etqan.billing.services.summary import revenue_between
```

```python
__all__ = [
    "FILTER_STATUSES",
    "MANUAL_PAYMENT_METHODS",
    "PaymentStatus",
    ...
    "resolve_payer",
    "revenue_between",
    "status_for",
    ...
]
```

- [ ] **Step 4: Run them to verify they pass**

Run: `$DJ pytest etqan/billing etqan/finance -q`
Expected: PASS (the Task 1 `extend` test passes now too).

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/billing/services etqan/billing/tests/test_summary.py
git -C backend commit -m "feat(billing): revenue_between and MANUAL_PAYMENT_METHODS for finance

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Expense services and the posting service

**Files:**
- Create: `backend/etqan/finance/services/rules.py`, `backend/etqan/finance/services/expenses.py`
- Modify: `backend/etqan/finance/services/__init__.py`
- Test: `backend/etqan/finance/tests/test_expenses.py`, `backend/etqan/finance/tests/test_posting.py`

**Interfaces:**
- Consumes: `Expense` and `clock.today()` (Task 1).
- Produces, all in `etqan.finance.services`:
  - `create_expense(*, title, type, amount_minor, by, currency=None, spent_on=None, notes="") -> Expense`
  - `update_expense(expense, *, title=None, type=None, amount_minor=None, currency=None, spent_on=None, notes=None) -> Expense`
  - `delete_expense(expense) -> None`
  - `expenses_queryset() -> QuerySet[Expense]`, with `created_by` joined
  - `filter_expenses(qs, *, type="", currency="", spent_from=None, spent_to=None, q="", posted=None) -> QuerySet`
  - `post_expense(*, source, source_id, title, type, amount_minor, currency, spent_on, notes="") -> Expense`
  - `withdraw_expense(*, source, source_id) -> None`
  - `has_records() -> bool`
  - `today() -> date`

  Refusals: `ConflictError(code="finance.expense_posted")`; field problems raise `ValidationError(field=…)`.

- [ ] **Step 1: Write the failing expense tests**

`backend/etqan/finance/tests/test_expenses.py`:

```python
"""B3a §4.1, §4.3: an admin's expenses."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.academy import services as academy_services
from etqan.finance import services
from etqan.finance.models import Expense
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError


def create(admin, **overrides):
    fields = {"title": "Rent", "type": "rent", "amount_minor": 250000, "by": admin}
    return services.create_expense(**{**fields, **overrides})


def refused_on(field, call):
    with pytest.raises(ValidationError) as caught:
        call()
    assert caught.value.field == field


def test_an_expense_defaults_to_the_academys_currency_and_today(admin, clock):
    academy_services.update_settings(default_currency="SAR")
    expense = create(admin, notes="June")
    assert (expense.currency, expense.spent_on, expense.notes) == (
        "SAR",
        date(2026, 6, 1),
        "June",
    )
    assert expense.created_by == admin
    assert (expense.source, expense.source_id) == ("", None)


def test_the_default_date_is_the_academys_today_near_midnight(admin, clock):
    """Review focus 3: 23:30 UTC on 1 June is already 2 June in Tokyo."""
    clock.set(datetime(2026, 6, 1, 23, 30, tzinfo=UTC))
    academy_services.update_settings(timezone="Asia/Tokyo")
    assert create(admin).spent_on == date(2026, 6, 2)


def test_a_given_currency_is_cleaned_and_a_bad_one_refused(admin, clock):
    assert create(admin, currency="usd").currency == "USD"
    refused_on("currency", lambda: create(admin, currency="dollars"))


def test_the_fields_are_checked(admin, clock):
    refused_on("title", lambda: create(admin, title=""))
    refused_on("title", lambda: create(admin, title="x" * 201))
    refused_on("type", lambda: create(admin, type="travel"))
    refused_on("amount_minor", lambda: create(admin, amount_minor=0))
    refused_on("spent_on", lambda: create(admin, spent_on=date(2026, 6, 2)))
    assert not Expense.objects.exists()


def test_an_edit_writes_only_what_it_was_given(admin, clock):
    expense = create(admin, notes="June")
    services.update_expense(expense, amount_minor=260000, currency="egp")
    expense.refresh_from_db()
    assert (expense.title, expense.amount_minor, expense.currency) == (
        "Rent",
        260000,
        "EGP",
    )
    assert expense.notes == "June"
    services.update_expense(expense, notes="")
    expense.refresh_from_db()
    assert expense.notes == ""
    refused_on(
        "spent_on", lambda: services.update_expense(expense, spent_on=date(2026, 7, 1))
    )


def test_a_posted_expense_refuses_edit_and_delete(admin, clock):
    posted = services.post_expense(
        source="payroll.payslip",
        source_id=7,
        title="Salary — Bilal",
        type="salaries",
        amount_minor=120000,
        currency="EGP",
        spent_on=date(2026, 6, 1),
    )
    for attempt in (
        lambda: services.update_expense(posted, title="Mine now"),
        lambda: services.delete_expense(posted),
    ):
        with pytest.raises(ConflictError) as caught:
            attempt()
        assert caught.value.code == "finance.expense_posted"
    assert Expense.objects.get().title == "Salary — Bilal"


def test_a_manual_expense_is_deleted(admin, clock):
    services.delete_expense(create(admin))
    assert not services.has_records()


def test_the_list_filters(admin, clock):
    rent = create(admin, spent_on=date(2026, 5, 30))
    ads = create(admin, title="Facebook ads", type="marketing", currency="USD")
    posted = services.post_expense(
        source="payroll.payslip",
        source_id=9,
        title="Salary — Maryam",
        type="salaries",
        amount_minor=90000,
        currency="EGP",
        spent_on=date(2026, 6, 1),
    )

    def ids(**query):
        rows = services.filter_expenses(services.expenses_queryset(), **query)
        return [row.pk for row in rows]

    assert ids() == [posted.pk, ads.pk, rent.pk]
    assert ids(type="marketing") == [ads.pk]
    assert ids(currency="usd") == [ads.pk]
    assert ids(spent_from=date(2026, 6, 1)) == [posted.pk, ads.pk]
    assert ids(spent_to=date(2026, 5, 31)) == [rent.pk]
    assert ids(q="FACEBOOK") == [ads.pk]
    assert ids(posted=True) == [posted.pk]
    assert ids(posted=False) == [ads.pk, rent.pk]
    assert services.has_records()
```

- [ ] **Step 2: Write the failing posting tests**

`backend/etqan/finance/tests/test_posting.py`:

```python
"""B3a §4.4, A-8: the expenses other apps post (B4 posts paid payslips)."""

from datetime import date

import pytest
from django.db import transaction

from etqan.finance import services
from etqan.finance.models import Expense
from etqan.finance.services import expenses as expense_services
from etqan.platform.exceptions import ValidationError

SOURCE = {"source": "payroll.payslip", "source_id": 7}


def post(**overrides):
    fields = {
        **SOURCE,
        "title": "Salary — Bilal",
        "type": "salaries",
        "amount_minor": 120000,
        "currency": "EGP",
        "spent_on": date(2026, 5, 31),
        **overrides,
    }
    return services.post_expense(**fields)


def test_a_post_creates_one_expense_for_its_source(clock):
    expense = post(notes="May")
    assert (expense.source, expense.source_id, expense.created_by) == (
        "payroll.payslip",
        7,
        None,
    )
    assert (expense.type, expense.amount_minor, expense.notes) == (
        "salaries",
        120000,
        "May",
    )


def test_posting_again_updates_the_same_expense_in_place(clock):
    first = post()
    again = post(amount_minor=125000, currency="usd", title="Salary — Bilal (fixed)")
    assert again.pk == first.pk
    assert Expense.objects.count() == 1
    stored = Expense.objects.get()
    assert (stored.amount_minor, stored.currency, stored.title) == (
        125000,
        "USD",
        "Salary — Bilal (fixed)",
    )


def test_a_post_that_loses_the_insert_race_updates_the_winner(clock, monkeypatch):
    """§4.4: the other post inserted between this one's look-up and insert;
    the unique constraint refuses the second row inside a savepoint, and the
    post updates the winner instead. The caller's transaction stays usable."""
    winner = post()
    real = expense_services.locked_for
    misses = [None]

    def locked(source, source_id):
        return misses.pop() if misses else real(source, source_id)

    monkeypatch.setattr(expense_services, "locked_for", locked)
    updated = post(amount_minor=99000)
    assert updated.pk == winner.pk
    assert list(Expense.objects.values_list("amount_minor", flat=True)) == [99000]


def test_withdrawing_deletes_it_and_withdrawing_nothing_is_fine(clock):
    post()
    services.withdraw_expense(**SOURCE)
    services.withdraw_expense(**SOURCE)
    assert not Expense.objects.exists()


def test_a_post_rolls_back_with_its_callers_transaction(clock):
    def post_then_fail():
        with transaction.atomic():
            post()
            raise RuntimeError("the caller failed")

    with pytest.raises(RuntimeError):
        post_then_fail()
    assert not Expense.objects.exists()


def test_posting_works_with_the_feature_off_and_any_date(clock, set_features):
    """A-8: the record is complete when expenses is switched on; the source
    decides the date, even one after the academy's today."""
    set_features(expenses=False)
    assert post(spent_on=date(2026, 7, 31)).spent_on == date(2026, 7, 31)


@pytest.mark.parametrize(
    ("overrides", "field"),
    [
        ({"source": " "}, "source"),
        ({"amount_minor": 0}, "amount_minor"),
        ({"currency": "EGPX"}, "currency"),
        ({"type": "travel"}, "type"),
        ({"title": ""}, "title"),
    ],
)
def test_a_bad_post_is_refused_on_its_field(clock, overrides, field):
    with pytest.raises(ValidationError) as caught:
        post(**overrides)
    assert caught.value.field == field
    assert not Expense.objects.exists()
```

- [ ] **Step 3: Run them to verify they fail**

Run: `$DJ pytest etqan/finance/tests/test_expenses.py etqan/finance/tests/test_posting.py -q`
Expected: FAIL (`AttributeError: module 'etqan.finance.services' has no attribute 'create_expense'`).

- [ ] **Step 4: Implement**

`backend/etqan/finance/services/rules.py`:

```python
"""The checks every finance row goes through (B3a §4.1). One implementation
each."""

from datetime import date

from django.core.exceptions import ValidationError as DjangoValidationError

from etqan.finance import clock
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import from_django


def check(obj, *, exclude=()) -> None:
    """Field checks with readable messages (a blank title, a zero amount, an
    unknown type), as 400s on their fields. Constraints are left to the
    database: the posting service relies on its unique constraint."""
    try:
        obj.full_clean(exclude=list(exclude), validate_constraints=False)
    except DjangoValidationError as exc:
        raise from_django(exc) from None


def save(obj, update_fields=None) -> None:
    check(obj)
    obj.save(update_fields=update_fields)


def not_future(day: date, field: str) -> date:
    """A date an admin gives may not be after the academy's today (§4.1)."""
    if day > clock.today():
        raise ValidationError("A date can't be in the future.", field=field)
    return day
```

`backend/etqan/finance/services/expenses.py`:

```python
"""Expenses: an admin's (B3a §4.1) and those other apps post (§4.4, A-8)."""

from datetime import date

from django.db import IntegrityError
from django.db import transaction
from django.db.models import Q
from django.db.models import QuerySet

from etqan.academy import services as academy_services
from etqan.finance import clock
from etqan.finance.models import Donation
from etqan.finance.models import Expense
from etqan.finance.services import rules
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency


def _currency(value: str | None) -> str:
    """The given currency, cleaned, else the academy's (A-3)."""
    default = academy_services.get_settings().default_currency
    return clean_currency(value or default, field="currency")


def _lock(expense: Expense) -> Expense:
    return Expense.objects.select_for_update().get(pk=expense.pk)


def refuse_if_posted(expense: Expense) -> None:
    """A-8: the app that posted it owns it."""
    if expense.source:
        raise ConflictError(
            "This expense was posted by another part of the system.",
            code="finance.expense_posted",
        )


def create_expense(  # noqa: PLR0913 -- keyword-only; mirrors the API body (B3a §4.1)
    *,
    title: str,
    type: str,  # noqa: A002 -- the expense's type, as the API names it (A-4)
    amount_minor: int,
    by,
    currency: str | None = None,
    spent_on: date | None = None,
    notes: str = "",
) -> Expense:
    """An admin's expense, in the academy's currency and dated its today
    unless given others."""
    expense = Expense(
        title=title,
        type=type,
        amount_minor=amount_minor,
        currency=_currency(currency),
        spent_on=rules.not_future(spent_on or clock.today(), "spent_on"),
        notes=notes,
        created_by=by,
    )
    rules.save(expense)
    return expense


@transaction.atomic
def update_expense(  # noqa: PLR0913 -- keyword-only; mirrors the API body (B3a §4.1)
    expense: Expense,
    *,
    title: str | None = None,
    type: str | None = None,  # noqa: A002 -- the expense's type (A-4)
    amount_minor: int | None = None,
    currency: str | None = None,
    spent_on: date | None = None,
    notes: str | None = None,
) -> Expense:
    """Only the given fields are written back; a posted expense refuses."""
    locked = _lock(expense)
    refuse_if_posted(locked)
    given = {
        "title": title,
        "type": type,
        "amount_minor": amount_minor,
        "currency": None if currency is None else _currency(currency),
        "spent_on": None if spent_on is None else rules.not_future(spent_on, "spent_on"),
        "notes": notes,
    }
    changed = [field for field, value in given.items() if value is not None]
    for field in changed:
        setattr(locked, field, given[field])
    rules.save(locked, update_fields=[*changed, "updated_at"])
    return locked


@transaction.atomic
def delete_expense(expense: Expense) -> None:
    locked = _lock(expense)
    refuse_if_posted(locked)
    locked.delete()


def expenses_queryset() -> QuerySet[Expense]:
    return Expense.objects.select_related("created_by")


def filter_expenses(  # noqa: PLR0913 -- keyword-only; mirrors the list's query (B3a §4.3)
    expenses: QuerySet[Expense],
    *,
    type: str = "",  # noqa: A002 -- the list's filter, as the API names it
    currency: str = "",
    spent_from: date | None = None,
    spent_to: date | None = None,
    q: str = "",
    posted: bool | None = None,
) -> QuerySet[Expense]:
    """The expense list's filters, newest first; dates are the academy's."""
    if type:
        expenses = expenses.filter(type=type)
    if currency:
        expenses = expenses.filter(currency=currency.strip().upper())
    if spent_from is not None:
        expenses = expenses.filter(spent_on__gte=spent_from)
    if spent_to is not None:
        expenses = expenses.filter(spent_on__lte=spent_to)
    if q := q.strip():
        expenses = expenses.filter(title__icontains=q)
    if posted is not None:
        expenses = expenses.exclude(source="") if posted else expenses.filter(source="")
    return expenses.order_by("-spent_on", "-id")


def locked_for(source: str, source_id: int) -> Expense | None:
    """The expense posted for this source row, locked, or None. Module-level
    (not exported) so a test can stand in for a lost race."""
    return (
        Expense.objects.select_for_update()
        .filter(source=source, source_id=source_id)
        .first()
    )


def post_expense(  # noqa: PLR0913 -- keyword-only; the posted expense's columns (B3a §4.4)
    *,
    source: str,
    source_id: int,
    title: str,
    type: str,  # noqa: A002 -- the expense's type (A-4)
    amount_minor: int,
    currency: str,
    spent_on: date,
    notes: str = "",
) -> Expense:
    """Create, or update in place, the one expense for ``(source,
    source_id)`` (A-8). Idempotent whatever the interleaving: an insert that
    loses a race to a concurrent post is refused by the unique constraint
    inside a savepoint, and this post then updates the winner. The caller
    owns the transaction: inside it, a post rolls back with the caller."""
    if not source.strip():
        raise ValidationError("Name the source of a posted expense.", field="source")
    fields = {
        "title": title,
        "type": type,
        "amount_minor": amount_minor,
        "currency": clean_currency(currency, field="currency"),
        "spent_on": spent_on,
        "notes": notes,
    }
    with transaction.atomic():
        expense = locked_for(source, source_id)
        if expense is None:
            fresh = Expense(source=source, source_id=source_id, **fields)
            rules.check(fresh)
            try:
                with transaction.atomic():
                    fresh.save()
            except IntegrityError:
                expense = locked_for(source, source_id)
            else:
                return fresh
        for field, value in fields.items():
            setattr(expense, field, value)
        rules.save(expense, update_fields=[*fields, "updated_at"])
        return expense


def withdraw_expense(*, source: str, source_id: int) -> None:
    """Delete the expense posted for this source row; nothing if none."""
    Expense.objects.filter(source=source, source_id=source_id).delete()


def has_records() -> bool:
    """Whether the academy has any expense or donation (the seeds' guard)."""
    return Expense.objects.exists() or Donation.objects.exists()
```

`backend/etqan/finance/services/__init__.py`:

```python
"""Public API of the finance module. Other apps import only this package."""

from etqan.finance.clock import today
from etqan.finance.services.expenses import create_expense
from etqan.finance.services.expenses import delete_expense
from etqan.finance.services.expenses import expenses_queryset
from etqan.finance.services.expenses import filter_expenses
from etqan.finance.services.expenses import has_records
from etqan.finance.services.expenses import post_expense
from etqan.finance.services.expenses import refuse_if_posted
from etqan.finance.services.expenses import update_expense
from etqan.finance.services.expenses import withdraw_expense

__all__ = [
    "create_expense",
    "delete_expense",
    "expenses_queryset",
    "filter_expenses",
    "has_records",
    "post_expense",
    "refuse_if_posted",
    "today",
    "update_expense",
    "withdraw_expense",
]
```

- [ ] **Step 5: Run them to verify they pass**

Run: `$DJ pytest etqan/finance -q`
Expected: PASS.

- [ ] **Step 6: Format, lint, contracts, commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/finance
git -C backend commit -m "feat(finance): expense services and the posting service other apps call

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Donation services and numbering

**Files:**
- Create: `backend/etqan/finance/services/numbering.py`, `backend/etqan/finance/services/donations.py`
- Modify: `backend/etqan/finance/services/__init__.py`
- Test: `backend/etqan/finance/tests/test_donations.py`

**Interfaces:**
- Consumes: `Donation`, `DonationCounter` (Task 1); `rules.check`, `rules.save`, `rules.not_future` (Task 3).
- Produces, all in `etqan.finance.services`:
  - `create_donation(*, amount_minor, method, by, currency=None, status="completed", received_on=None, transaction_number="", donor_name="", donor_email="", notes="") -> Donation`
  - `update_donation(donation, *, amount_minor=None, method=None, currency=None, status=None, received_on=None, transaction_number=None, donor_name=None, donor_email=None, notes=None) -> Donation`
  - `delete_donation(donation) -> None`
  - `donations_queryset()`
  - `filter_donations(qs, *, status="", method="", currency="", received_from=None, received_to=None, q="") -> QuerySet`
  - `next_donation_number() -> str`

- [ ] **Step 1: Write the failing tests**

`backend/etqan/finance/tests/test_donations.py`:

```python
"""B3a §3.2, §4.2: donation records and their numbers."""

from datetime import date

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.academy import services as academy_services
from etqan.finance import services
from etqan.finance.models import Donation
from etqan.platform.exceptions import ValidationError


def give(admin, **overrides):
    fields = {"amount_minor": 50000, "method": "bank_transfer", "by": admin}
    return services.create_donation(**{**fields, **overrides})


def refused_on(field, call):
    with pytest.raises(ValidationError) as caught:
        call()
    assert caught.value.field == field


def test_a_donation_is_numbered_and_defaults_to_completed_today(admin, clock):
    academy_services.update_settings(default_currency="USD")
    first = give(admin, donor_name="Abu Khalid", transaction_number="TX-1")
    second = give(admin, method="stripe", status="pending", currency="egp")
    assert (first.number, first.status, first.currency, first.received_on) == (
        "DON-000001",
        "completed",
        "USD",
        date(2026, 6, 1),
    )
    assert (first.donor_name, first.transaction_number, first.created_by) == (
        "Abu Khalid",
        "TX-1",
        admin,
    )
    assert (second.number, second.status, second.currency) == (
        "DON-000002",
        "pending",
        "EGP",
    )


def test_a_refused_donation_takes_no_number(admin, clock):
    refused_on("amount_minor", lambda: give(admin, amount_minor=0))
    refused_on("method", lambda: give(admin, method="crypto"))
    refused_on("status", lambda: give(admin, status="lost"))
    refused_on("donor_email", lambda: give(admin, donor_email="not-an-email"))
    refused_on("received_on", lambda: give(admin, received_on=date(2026, 6, 2)))
    refused_on("currency", lambda: give(admin, currency="EG"))
    assert give(admin).number == "DON-000001"


def test_numbers_are_taken_under_the_counter_lock(admin, clock):
    """The counter row is read FOR UPDATE, so two donations at once never
    share a number (as invoice numbers, Plan 6 D1)."""
    with CaptureQueriesContext(connection) as queries:
        give(admin)
    locked = [
        q["sql"]
        for q in queries.captured_queries
        if "finance_donationcounter" in q["sql"] and "FOR UPDATE" in q["sql"]
    ]
    assert locked


def test_an_edit_writes_only_what_it_was_given_and_keeps_the_number(admin, clock):
    donation = give(admin, notes="Ramadan")
    services.update_donation(donation, status="refunded", donor_email="a@b.test")
    donation.refresh_from_db()
    assert (donation.number, donation.status, donation.donor_email) == (
        "DON-000001",
        "refunded",
        "a@b.test",
    )
    assert donation.notes == "Ramadan"
    refused_on(
        "received_on",
        lambda: services.update_donation(donation, received_on=date(2026, 7, 1)),
    )


def test_a_donation_is_deleted(admin, clock):
    services.delete_donation(give(admin))
    assert not Donation.objects.exists()


def test_the_list_filters(admin, clock):
    old = give(admin, received_on=date(2026, 5, 20), donor_name="Umm Sara")
    usd = give(admin, method="paypal", currency="USD", transaction_number="PAY-77")
    pending = give(admin, status="pending")

    def ids(**query):
        rows = services.filter_donations(services.donations_queryset(), **query)
        return [row.pk for row in rows]

    assert ids() == [pending.pk, usd.pk, old.pk]
    assert ids(status="pending") == [pending.pk]
    assert ids(method="paypal") == [usd.pk]
    assert ids(currency="usd") == [usd.pk]
    assert ids(received_from=date(2026, 6, 1)) == [pending.pk, usd.pk]
    assert ids(received_to=date(2026, 5, 31)) == [old.pk]
    assert ids(q="umm") == [old.pk]
    assert ids(q="pay-77") == [usd.pk]
    assert ids(q="000003") == [pending.pk]
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/finance/tests/test_donations.py -q`
Expected: FAIL (`AttributeError: … has no attribute 'create_donation'`).

- [ ] **Step 3: Implement**

`backend/etqan/finance/services/numbering.py`:

```python
"""Donation numbers (B3a §3.2), taken as invoice numbers are."""

from etqan.finance.models import DonationCounter

NUMBER_FORMAT = "DON-{:06d}"


def next_donation_number() -> str:
    """The academy's next donation number, `DON-000001`. The one counter row
    is taken `FOR UPDATE`, so a second donation at the same moment waits
    here; the counter moves in the donation's transaction, so a rolled-back
    donation gives its number back. Call it inside a transaction."""
    counter, _ = DonationCounter.objects.select_for_update().get_or_create(pk=1)
    counter.last_number += 1
    counter.save(update_fields=["last_number"])
    return NUMBER_FORMAT.format(counter.last_number)
```

`backend/etqan/finance/services/donations.py`:

```python
"""Donation records (B3a §4.2). Not revenue (B3-5)."""

from datetime import date

from django.db import transaction
from django.db.models import Q
from django.db.models import QuerySet

from etqan.academy import services as academy_services
from etqan.finance import clock
from etqan.finance.models import Donation
from etqan.finance.services import rules
from etqan.finance.services.numbering import next_donation_number
from etqan.platform.validators import clean_currency


def _currency(value: str | None) -> str:
    default = academy_services.get_settings().default_currency
    return clean_currency(value or default, field="currency")


@transaction.atomic
def create_donation(  # noqa: PLR0913 -- keyword-only; mirrors the API body (B3a §4.1)
    *,
    amount_minor: int,
    method: str,
    by,
    currency: str | None = None,
    status: str = Donation.Status.COMPLETED,
    received_on: date | None = None,
    transaction_number: str = "",
    donor_name: str = "",
    donor_email: str = "",
    notes: str = "",
) -> Donation:
    """Checked first, numbered last: a refused donation takes no number."""
    donation = Donation(
        amount_minor=amount_minor,
        currency=_currency(currency),
        method=method,
        status=status,
        received_on=rules.not_future(received_on or clock.today(), "received_on"),
        transaction_number=transaction_number,
        donor_name=donor_name,
        donor_email=donor_email,
        notes=notes,
        created_by=by,
    )
    rules.check(donation, exclude=["number"])
    donation.number = next_donation_number()
    donation.save()
    return donation


@transaction.atomic
def update_donation(  # noqa: PLR0913 -- keyword-only; mirrors the API body (B3a §4.1)
    donation: Donation,
    *,
    amount_minor: int | None = None,
    method: str | None = None,
    currency: str | None = None,
    status: str | None = None,
    received_on: date | None = None,
    transaction_number: str | None = None,
    donor_name: str | None = None,
    donor_email: str | None = None,
    notes: str | None = None,
) -> Donation:
    """Only the given fields are written back; the number never changes."""
    locked = Donation.objects.select_for_update().get(pk=donation.pk)
    given = {
        "amount_minor": amount_minor,
        "method": method,
        "currency": None if currency is None else _currency(currency),
        "status": status,
        "received_on": None
        if received_on is None
        else rules.not_future(received_on, "received_on"),
        "transaction_number": transaction_number,
        "donor_name": donor_name,
        "donor_email": donor_email,
        "notes": notes,
    }
    changed = [field for field, value in given.items() if value is not None]
    for field in changed:
        setattr(locked, field, given[field])
    rules.save(locked, update_fields=[*changed, "updated_at"])
    return locked


def delete_donation(donation: Donation) -> None:
    Donation.objects.filter(pk=donation.pk).delete()


def donations_queryset() -> QuerySet[Donation]:
    return Donation.objects.select_related("created_by")


def filter_donations(  # noqa: PLR0913 -- keyword-only; mirrors the list's query (B3a §4.3)
    donations: QuerySet[Donation],
    *,
    status: str = "",
    method: str = "",
    currency: str = "",
    received_from: date | None = None,
    received_to: date | None = None,
    q: str = "",
) -> QuerySet[Donation]:
    """The donation list's filters, newest first; dates are the academy's."""
    exact = {
        "status": status or None,
        "method": method or None,
        "currency": currency.strip().upper() or None,
        "received_on__gte": received_from,
        "received_on__lte": received_to,
    }
    donations = donations.filter(
        **{key: value for key, value in exact.items() if value is not None}
    )
    if q := q.strip():
        donations = donations.filter(
            Q(number__icontains=q)
            | Q(donor_name__icontains=q)
            | Q(transaction_number__icontains=q)
        )
    return donations.order_by("-received_on", "-id")
```

In `backend/etqan/finance/services/__init__.py`, add the imports and names (alphabetical):

```python
from etqan.finance.services.donations import create_donation
from etqan.finance.services.donations import delete_donation
from etqan.finance.services.donations import donations_queryset
from etqan.finance.services.donations import filter_donations
from etqan.finance.services.donations import update_donation
from etqan.finance.services.numbering import next_donation_number
```

and `"create_donation"`, `"delete_donation"`, `"donations_queryset"`, `"filter_donations"`, `"next_donation_number"`, `"update_donation"` in `__all__`.

- [ ] **Step 4: Run them to verify they pass**

Run: `$DJ pytest etqan/finance -q`
Expected: PASS.

- [ ] **Step 5: Format, lint, commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/finance
git -C backend commit -m "feat(finance): donation records with DON- numbers

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: This month's expenses, net profit and donations

**Files:**
- Create: `backend/etqan/finance/services/summary.py`
- Modify: `backend/etqan/finance/services/__init__.py`
- Test: `backend/etqan/finance/tests/test_summary.py`

**Interfaces:**
- Consumes: `billing.services.revenue_between` (Task 2); `clock.today()`; `features.enabled`.
- Produces, in `etqan.finance.services`:
  - `summary() -> {"expenses_this_month": [MoneyLine], "net_profit_this_month": [MoneyLine] | None}`
  - `donations_summary() -> {"donations_this_month": [MoneyLine]}`

  Each `MoneyLine` is `{"currency": str, "amount_minor": int}`, in currency order.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/finance/tests/test_summary.py`:

```python
"""B3a §4.6, A-7: this academy month's expenses, net profit and donations,
per currency, never summed across currencies."""

from datetime import UTC
from datetime import date
from datetime import datetime

from etqan.academy import services as academy_services
from etqan.billing import services as billing_services
from etqan.finance import services


def spend(admin, amount, currency="EGP", spent_on=None):
    return services.create_expense(
        title="Cost",
        type="other",
        amount_minor=amount,
        currency=currency,
        spent_on=spent_on,
        by=admin,
    )


def receive(world, admin, amount, currency="EGP", paid_on=None):
    """A paid invoice: billing's revenue (B3-5). Billing's clock is pinned
    with finance's, so its today is finance's."""
    invoice = billing_services.create_invoice(
        student_id=world.student.id,
        amount_minor=amount,
        currency=currency,
        due_on=date(2026, 7, 31),
        description="Lessons",
        by=admin,
    )
    billing_services.add_payment(
        invoice,
        amount_minor=amount,
        method="cash",
        paid_on=paid_on or services.today(),
        by=admin,
    )


def test_net_profit_is_revenue_less_expenses_per_currency(world, admin, clock):
    receive(world, admin, 100000)
    receive(world, admin, 5000, currency="USD")
    spend(admin, 30000)
    spend(admin, 2000, currency="SAR")
    assert services.summary() == {
        "expenses_this_month": [
            {"currency": "EGP", "amount_minor": 30000},
            {"currency": "SAR", "amount_minor": 2000},
        ],
        "net_profit_this_month": [
            {"currency": "EGP", "amount_minor": 70000},
            {"currency": "SAR", "amount_minor": -2000},
            {"currency": "USD", "amount_minor": 5000},
        ],
    }


def test_the_month_is_the_academys(world, admin, clock):
    # 20:00 UTC on 30 June is already 1 July in Tokyo: July is this month.
    clock.set(datetime(2026, 6, 30, 20, tzinfo=UTC))
    academy_services.update_settings(timezone="Asia/Tokyo")
    spend(admin, 1000, spent_on=date(2026, 6, 30))  # June: excluded.
    spend(admin, 2000, spent_on=date(2026, 7, 1))
    receive(world, admin, 9000, paid_on=date(2026, 6, 30))  # June: excluded.
    assert services.summary() == {
        "expenses_this_month": [{"currency": "EGP", "amount_minor": 2000}],
        "net_profit_this_month": [{"currency": "EGP", "amount_minor": -2000}],
    }
    # In UTC it is still 30 June.
    academy_services.update_settings(timezone="UTC")
    assert services.summary() == {
        "expenses_this_month": [{"currency": "EGP", "amount_minor": 1000}],
        "net_profit_this_month": [{"currency": "EGP", "amount_minor": 8000}],
    }


def test_nothing_this_month_is_empty_lists(clock):
    assert services.summary() == {
        "expenses_this_month": [],
        "net_profit_this_month": [],
    }
    assert services.donations_summary() == {"donations_this_month": []}


def test_with_invoices_off_net_profit_is_null(admin, clock, set_features):
    """A-7: without invoices the academy records no revenue."""
    spend(admin, 1000)
    set_features(invoices=False)
    assert services.summary() == {
        "expenses_this_month": [{"currency": "EGP", "amount_minor": 1000}],
        "net_profit_this_month": None,
    }


def test_donations_count_completed_ones_this_month_only(admin, clock):
    services.create_donation(amount_minor=5000, method="cash", currency="EGP", by=admin)
    services.create_donation(amount_minor=700, method="paypal", currency="USD", by=admin)
    services.create_donation(
        amount_minor=900, method="cash", currency="EGP", status="pending", by=admin
    )
    services.create_donation(
        amount_minor=400,
        method="cash",
        currency="EGP",
        received_on=date(2026, 5, 31),
        by=admin,
    )
    assert services.donations_summary() == {
        "donations_this_month": [
            {"currency": "EGP", "amount_minor": 5000},
            {"currency": "USD", "amount_minor": 700},
        ]
    }


def test_a_donation_set_back_to_pending_leaves_the_total(admin, clock):
    """Review focus 4."""
    gift = services.create_donation(
        amount_minor=5000, method="cash", currency="EGP", by=admin
    )
    services.update_donation(gift, status="pending")
    assert services.donations_summary() == {"donations_this_month": []}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/finance/tests/test_summary.py -q`
Expected: FAIL (`AttributeError: … has no attribute 'summary'`).

- [ ] **Step 3: Implement**

`backend/etqan/finance/services/summary.py`:

```python
"""The admin home's finance figures (B3a §4.6). Never summed across
currencies (B3-4)."""

from datetime import date
from datetime import timedelta

from django.db.models import QuerySet
from django.db.models import Sum

from etqan.billing import services as billing_services
from etqan.finance import clock
from etqan.finance.models import Donation
from etqan.finance.models import Expense
from etqan.platform import features


def month_of(day: date) -> tuple[date, date]:
    """The first day of ``day``'s month and the first day of the next."""
    first = day.replace(day=1)
    return first, (first + timedelta(days=32)).replace(day=1)


def _per_currency(rows: QuerySet) -> list[dict]:
    totals = rows.values("currency").annotate(total=Sum("amount_minor"))
    return [
        {"currency": row["currency"], "amount_minor": row["total"]}
        for row in totals.order_by("currency")
    ]


def expenses_between(first: date, following: date) -> list[dict]:
    return _per_currency(
        Expense.objects.filter(spent_on__gte=first, spent_on__lt=following)
    )


def donations_between(first: date, following: date) -> list[dict]:
    """Completed donations only (A-6)."""
    return _per_currency(
        Donation.objects.filter(
            status=Donation.Status.COMPLETED,
            received_on__gte=first,
            received_on__lt=following,
        )
    )


def net_profit(revenue: list[dict], expenses: list[dict]) -> list[dict]:
    """Revenue − expenses for every currency present in either, in currency
    order (A-7). A currency with only expenses is negative."""
    earned = {row["currency"]: row["amount_minor"] for row in revenue}
    spent = {row["currency"]: row["amount_minor"] for row in expenses}
    return [
        {"currency": code, "amount_minor": earned.get(code, 0) - spent.get(code, 0)}
        for code in sorted(earned.keys() | spent.keys())
    ]


def summary() -> dict:
    """`finance/summary/`: this academy month's expenses, and its net profit
    while `invoices` is on (null otherwise, A-7)."""
    first, following = month_of(clock.today())
    spent = expenses_between(first, following)
    profit = None
    if features.enabled("invoices"):
        profit = net_profit(billing_services.revenue_between(first, following), spent)
    return {"expenses_this_month": spent, "net_profit_this_month": profit}


def donations_summary() -> dict:
    """`finance/donations/summary/`: this academy month's completed
    donations."""
    first, following = month_of(clock.today())
    return {"donations_this_month": donations_between(first, following)}
```

In `backend/etqan/finance/services/__init__.py`, add:

```python
from etqan.finance.services.summary import donations_summary
from etqan.finance.services.summary import summary
```

and `"donations_summary"` and `"summary"` in `__all__`.

- [ ] **Step 4: Run them to verify they pass**

Run: `$DJ pytest etqan/finance -q`
Expected: PASS.

- [ ] **Step 5: Format, lint, commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/finance
git -C backend commit -m "feat(finance): this month's expenses, net profit and donations

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 6: The finance API, its permission resources and its route-table rows

**Files:**
- Create: `backend/etqan/finance/api/__init__.py` (empty), `serializers.py`, `payloads.py`, `views.py`, `urls.py`
- Modify: `backend/config/api_router.py` (B3 marker), `backend/etqan/access/registry.py` (B3 marker), `backend/etqan/access/tests/test_routes.py`, `backend/etqan/access/tests/test_registry.py`
- Test: `backend/etqan/finance/tests/test_api.py`

**Interfaces:**
- Consumes: every service from Tasks 3–5.
- Produces the routes of spec §5 under `/api/v1/finance/`:
  - `expenses/`, `expenses/<id>/`;
  - `donations/`, `donations/<id>/`, `donations/summary/`;
  - `summary/`.

  It also adds the permission codes `expense.{view,view_any,create,update,delete}` and `donation.{view,view_any,create,update,delete}`.

- [ ] **Step 1: Add the route-table rows and the registry count (failing)**

In `backend/etqan/access/tests/test_routes.py`:

1. At the end of `ROUTES`, after the access rows:

```python
    # Finance (phase B3, slice B3a).
    ("GET", "/api/v1/finance/expenses/", "expense.view_any"),
    ("POST", "/api/v1/finance/expenses/", "expense.create"),
    ("GET", f"/api/v1/finance/expenses/{N}/", "expense.view"),
    ("PATCH", f"/api/v1/finance/expenses/{N}/", "expense.update"),
    ("DELETE", f"/api/v1/finance/expenses/{N}/", "expense.delete"),
    ("GET", "/api/v1/finance/donations/", "donation.view_any"),
    ("POST", "/api/v1/finance/donations/", "donation.create"),
    ("GET", f"/api/v1/finance/donations/{N}/", "donation.view"),
    ("PATCH", f"/api/v1/finance/donations/{N}/", "donation.update"),
    ("DELETE", f"/api/v1/finance/donations/{N}/", "donation.delete"),
    ("GET", "/api/v1/finance/donations/summary/", "widget.revenue_stats"),
    ("GET", "/api/v1/finance/summary/", "widget.revenue_stats"),
```

2. At the end of `FEATURES`, after the `"invoices"` block:

```python
    # Phase B3, slice B3a.
    **dict.fromkeys(
        (
            ("GET", "/api/v1/finance/expenses/"),
            ("POST", "/api/v1/finance/expenses/"),
            ("GET", f"/api/v1/finance/expenses/{N}/"),
            ("PATCH", f"/api/v1/finance/expenses/{N}/"),
            ("DELETE", f"/api/v1/finance/expenses/{N}/"),
            ("GET", "/api/v1/finance/summary/"),
        ),
        "expenses",
    ),
    **dict.fromkeys(
        (
            ("GET", "/api/v1/finance/donations/"),
            ("POST", "/api/v1/finance/donations/"),
            ("GET", f"/api/v1/finance/donations/{N}/"),
            ("PATCH", f"/api/v1/finance/donations/{N}/"),
            ("DELETE", f"/api/v1/finance/donations/{N}/"),
            ("GET", "/api/v1/finance/donations/summary/"),
        ),
        "donations",
    ),
```

3. At the end of `FEATURE_WORDS` (D3):

```python
    # Phase B3: finance's routes belong to two features.
    "/expenses/": "expenses",
    "/donations/": "donations",
    "/finance/summary/": "expenses",
```

In `backend/etqan/access/tests/test_registry.py`, change `== 22` to `== 24`, and add after the `role` assertion in `test_resources_carry_the_12_verbs_and_the_role_resource_6`:

```python
    # Phase B3 (slice B3a, A-9).
    assert by_code["expense"].in_use == (
        "view",
        "view_any",
        "create",
        "update",
        "delete",
    )
    assert by_code["donation"].in_use == by_code["expense"].in_use
```

Run: `$DJ pytest etqan/access -q`
Expected: FAIL (unknown codes, unrouted paths).

- [ ] **Step 2: Write the failing API tests**

`backend/etqan/finance/tests/test_api.py`:

```python
"""B3a §5: the finance routes, their payloads, errors and gates."""

import csv
import io

import pytest
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.academy import services as academy_services
from etqan.finance import services
from etqan.finance.models import Expense

EXPENSES = "/api/v1/finance/expenses/"
DONATIONS = "/api/v1/finance/donations/"
SUMMARY = "/api/v1/finance/summary/"
DONATIONS_SUMMARY = "/api/v1/finance/donations/summary/"
EXPENSE_KEYS = {
    "id",
    "title",
    "type",
    "amount_minor",
    "currency",
    "spent_on",
    "notes",
    "source",
    "source_id",
    "posted",
    "created_by",
    "created_at",
    "updated_at",
}
DONATION_KEYS = {
    "id",
    "number",
    "amount_minor",
    "currency",
    "method",
    "transaction_number",
    "status",
    "donor_name",
    "donor_email",
    "received_on",
    "notes",
    "created_by",
    "created_at",
    "updated_at",
}


def posted_salary(source_id=7, **overrides):
    fields = {
        "source": "payroll.payslip",
        "source_id": source_id,
        "title": "Salary — Bilal",
        "type": "salaries",
        "amount_minor": 120000,
        "currency": "EGP",
        "spent_on": services.today(),
        **overrides,
    }
    return services.post_expense(**fields)


def rows(resp):
    assert resp.status_code == 200, resp.content
    return [row["id"] for row in resp.json()["results"]]


@pytest.fixture
def admin_api(api_for, clock, finance_on):
    """An admin, with both features on and the academy's currency USD."""
    academy_services.update_settings(default_currency="USD")
    return api_for("admin")


def test_the_admin_records_reads_edits_and_deletes_an_expense(admin_api):
    resp = admin_api.post(
        EXPENSES,
        {"title": "Rent", "type": "rent", "amount_minor": 250000},
        format="json",
    )
    assert resp.status_code == 201, resp.content
    data = resp.json()
    assert set(data) == EXPENSE_KEYS
    assert {key: data[key] for key in EXPENSE_KEYS - {"id", "created_at", "updated_at"}} == {
        "title": "Rent",
        "type": "rent",
        "amount_minor": 250000,
        "currency": "USD",
        "spent_on": "2026-06-01",
        "notes": "",
        "source": "",
        "source_id": None,
        "posted": False,
        "created_by": {
            "id": admin_api.user.pk,
            "full_name": admin_api.user.full_name,
        },
    }
    url = f"{EXPENSES}{data['id']}/"
    assert admin_api.get(url).json() == data
    resp = admin_api.patch(url, {"amount_minor": 260000, "notes": "June"}, format="json")
    assert resp.status_code == 200, resp.content
    assert (resp.json()["amount_minor"], resp.json()["notes"]) == (260000, "June")
    assert admin_api.delete(url).status_code == 204
    assert admin_api.get(url).status_code == 404


def test_a_patch_ignores_the_keys_it_may_not_write(admin_api):
    """Review focus 2 (D6): a manual expense never becomes posted, and a
    donation never changes its number."""
    expense = admin_api.post(
        EXPENSES, {"title": "Ads", "type": "marketing", "amount_minor": 100}, format="json"
    ).json()
    resp = admin_api.patch(
        f"{EXPENSES}{expense['id']}/",
        {"source": "payroll.payslip", "source_id": 3, "title": "Ads (fixed)"},
        format="json",
    )
    assert (resp.json()["posted"], resp.json()["source"], resp.json()["title"]) == (
        False,
        "",
        "Ads (fixed)",
    )
    donation = admin_api.post(
        DONATIONS, {"amount_minor": 500, "method": "cash"}, format="json"
    ).json()
    resp = admin_api.patch(
        f"{DONATIONS}{donation['id']}/",
        {"number": "DON-999999", "status": "refunded"},
        format="json",
    )
    assert (resp.json()["number"], resp.json()["status"]) == ("DON-000001", "refunded")


def test_bad_fields_are_400s_on_their_fields(admin_api):
    cases = [
        ({"type": "rent", "amount_minor": 1}, "title"),
        ({"title": "x", "type": "travel", "amount_minor": 1}, "type"),
        ({"title": "x", "type": "rent", "amount_minor": 0}, "amount_minor"),
        ({"title": "x", "type": "rent", "amount_minor": 1, "currency": "EG"}, "currency"),
        (
            {"title": "x", "type": "rent", "amount_minor": 1, "spent_on": "2026-06-02"},
            "spent_on",
        ),
    ]
    for body, field in cases:
        resp = admin_api.post(EXPENSES, body, format="json")
        assert resp.status_code == 400, (body, resp.content)
        assert field in resp.json(), (body, resp.json())
    resp = admin_api.post(
        DONATIONS,
        {"amount_minor": 1, "method": "cash", "donor_email": "nope"},
        format="json",
    )
    assert resp.status_code == 400
    assert "donor_email" in resp.json()


def test_a_posted_expense_is_listed_and_refuses_edit_and_delete(admin_api):
    posted = posted_salary()
    url = f"{EXPENSES}{posted.pk}/"
    body = admin_api.get(url).json()
    assert (body["posted"], body["source"], body["source_id"], body["created_by"]) == (
        True,
        "payroll.payslip",
        7,
        None,
    )
    for resp in (
        admin_api.patch(url, {"title": "Mine"}, format="json"),
        admin_api.delete(url),
    ):
        assert resp.status_code == 409
        assert resp.json()["code"] == "finance.expense_posted"
        assert "detail" in resp.json()
    assert Expense.objects.get().title == "Salary — Bilal"


def test_the_expense_list_filters_and_400s(admin_api):
    rent = services.create_expense(
        title="Rent", type="rent", amount_minor=1, by=admin_api.user
    )
    posted = posted_salary()
    # Review focus 1 (D2): no `posted` parameter lists both.
    assert rows(admin_api.get(EXPENSES)) == [posted.pk, rent.pk]
    assert rows(admin_api.get(EXPENSES, {"posted": "true"})) == [posted.pk]
    assert rows(admin_api.get(EXPENSES, {"posted": "false"})) == [rent.pk]
    assert rows(admin_api.get(EXPENSES, {"type": "rent", "q": "ren"})) == [rent.pk]
    assert rows(admin_api.get(EXPENSES, {"spent_from": "2026-06-02"})) == []
    for bad in ({"type": "travel"}, {"spent_from": "junk"}, {"posted": "maybe"}):
        resp = admin_api.get(EXPENSES, bad)
        assert resp.status_code == 400, bad
        assert next(iter(bad)) in resp.json()


def test_the_donation_list_filters_and_400s(admin_api):
    cash = services.create_donation(amount_minor=1, method="cash", by=admin_api.user)
    paypal = services.create_donation(
        amount_minor=2,
        method="paypal",
        status="pending",
        donor_name="Umm Sara",
        by=admin_api.user,
    )
    assert rows(admin_api.get(DONATIONS)) == [paypal.pk, cash.pk]
    assert rows(admin_api.get(DONATIONS, {"status": "pending"})) == [paypal.pk]
    assert rows(admin_api.get(DONATIONS, {"method": "cash"})) == [cash.pk]
    assert rows(admin_api.get(DONATIONS, {"q": "umm"})) == [paypal.pk]
    for bad in ({"status": "lost"}, {"received_to": "junk"}, {"method": "gold"}):
        assert admin_api.get(DONATIONS, bad).status_code == 400, bad


def read_csv(resp):
    assert resp.status_code == 200, resp.content
    assert resp["Content-Type"].startswith("text/csv")
    return list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))


def test_csv_exports_follow_the_export_feature(admin_api, set_features):
    services.create_expense(title="Rent", type="rent", amount_minor=250000, by=admin_api.user)
    posted_salary()
    services.create_donation(
        amount_minor=500, method="cash", donor_name="Abu Khalid", by=admin_api.user
    )
    expenses = read_csv(admin_api.get(EXPENSES, {"format": "csv"}))
    assert expenses[0] == [
        "Title",
        "Type",
        "Amount (minor units)",
        "Currency",
        "Spent on",
        "Notes",
        "Posted",
    ]
    assert [row[0] for row in expenses[1:]] == ["Salary — Bilal", "Rent"]
    assert [row[6] for row in expenses[1:]] == ["yes", "no"]
    donations = read_csv(admin_api.get(DONATIONS, {"format": "csv"}))
    assert donations[0] == [
        "Number",
        "Donor",
        "Email",
        "Amount (minor units)",
        "Currency",
        "Method",
        "Transaction number",
        "Status",
        "Received on",
    ]
    assert donations[1][:2] == ["DON-000001", "Abu Khalid"]
    set_features(export=False)
    assert admin_api.get(EXPENSES, {"format": "csv"}).status_code == 404
    assert admin_api.get(DONATIONS, {"format": "csv"}).status_code == 404


def test_the_summaries(admin_api, set_features):
    services.create_expense(title="Rent", type="rent", amount_minor=1000, by=admin_api.user)
    services.create_donation(amount_minor=300, method="cash", by=admin_api.user)
    assert admin_api.get(SUMMARY).json() == {
        "expenses_this_month": [{"currency": "USD", "amount_minor": 1000}],
        "net_profit_this_month": [{"currency": "USD", "amount_minor": -1000}],
    }
    assert admin_api.get(DONATIONS_SUMMARY).json() == {
        "donations_this_month": [{"currency": "USD", "amount_minor": 300}]
    }
    set_features(invoices=False)
    assert admin_api.get(SUMMARY).json()["net_profit_this_month"] is None


def test_the_features_gate_their_routes(api_for, clock, set_features):
    admin = api_for("admin")
    set_features(expenses=True, donations=False)
    assert admin.get(EXPENSES).status_code == 200
    assert admin.get(SUMMARY).status_code == 200
    assert admin.get(DONATIONS).status_code == 404
    assert admin.get(DONATIONS_SUMMARY).status_code == 404
    set_features(expenses=False, donations=True)
    assert admin.get(EXPENSES).status_code == 404
    assert admin.get(SUMMARY).status_code == 404
    assert admin.get(DONATIONS).status_code == 200


def test_only_the_office_reaches_finance(api_for, staff_for, clock, finance_on):
    expense = services.create_expense(title="Rent", type="rent", amount_minor=1, by=None)
    donation = services.create_donation(amount_minor=1, method="cash", by=None)
    routes = [
        ("get", EXPENSES, None),
        ("post", EXPENSES, {"title": "x", "type": "rent", "amount_minor": 1}),
        ("get", f"{EXPENSES}{expense.pk}/", None),
        ("patch", f"{EXPENSES}{expense.pk}/", {"notes": "x"}),
        ("delete", f"{EXPENSES}{expense.pk}/", None),
        ("get", DONATIONS, None),
        ("post", DONATIONS, {"amount_minor": 1, "method": "cash"}),
        ("get", f"{DONATIONS}{donation.pk}/", None),
        ("patch", f"{DONATIONS}{donation.pk}/", {"notes": "x"}),
        ("delete", f"{DONATIONS}{donation.pk}/", None),
        ("get", DONATIONS_SUMMARY, None),
        ("get", SUMMARY, None),
        ("get", f"{EXPENSES}?format=csv", None),
    ]
    clients = {
        "teacher": api_for("teacher"),
        "parent": api_for("parent"),
        "student": api_for("student"),
        "anonymous": APIClient(),
        "staff without codes": staff_for(),
    }
    for who, client in clients.items():
        for method, path, data in routes:
            resp = getattr(client, method)(path, data, format="json")
            assert resp.status_code == 403, (who, method, path)
            assert "csv" not in resp.headers.get("Content-Type", "")
    reader = staff_for("expense.view_any", "expense.view", "widget.revenue_stats")
    assert reader.get(EXPENSES).status_code == 200
    assert reader.get(SUMMARY).status_code == 200
    assert reader.delete(f"{EXPENSES}{expense.pk}/").status_code == 403


def test_another_academy_never_leaks(admin_api, tenants, set_features):
    set_features(academy=tenants.other, expenses=True, donations=True)
    with tenant_context(tenants.other):
        theirs = services.create_expense(
            title="Their rent", type="rent", amount_minor=1, by=None
        )
        services.create_donation(amount_minor=1, method="cash", by=None)
    assert rows(admin_api.get(EXPENSES)) == []
    assert rows(admin_api.get(DONATIONS)) == []
    assert admin_api.get(f"{EXPENSES}{theirs.pk}/").status_code == 404
    assert admin_api.get(SUMMARY).json()["expenses_this_month"] == []
```

The `admin_api` fixture sets the academy's currency to USD, which the default-currency assertions rely on.

- [ ] **Step 3: Run them to verify they fail**

Run: `$DJ pytest etqan/finance/tests/test_api.py -q`
Expected: FAIL (404 on every route: nothing is routed yet).

- [ ] **Step 4: Implement**

`backend/etqan/access/registry.py`, under `# ── phase B3 ──` in `RESOURCES`:

```python
    # ── phase B3 ──
    # Slice B3a (A-9): TutorHamster's `expense` and `donation::record`.
    Resource("expense", "Expenses", "المصروفات", (*EDIT, "delete")),
    Resource("donation", "Donations", "التبرعات", (*EDIT, "delete")),
```

`backend/etqan/finance/api/serializers.py`:

```python
"""Request bodies and list queries (B3a §4.1, §4.3). Responses are built in
`payloads`. PATCH reuses each body with ``partial=True``; keys a body does
not name (``source``, ``source_id``, ``number``) are ignored (D6)."""

from rest_framework import serializers

from etqan.finance.models import Donation
from etqan.finance.models import Expense

# D2: a query-string boolean that is missing would read as false.
YES_NO = ("true", "false")


class ExpenseInput(serializers.Serializer):
    title = serializers.CharField(max_length=200)
    type = serializers.ChoiceField(choices=Expense.Type.choices)
    amount_minor = serializers.IntegerField(min_value=1)
    currency = serializers.CharField(max_length=3, required=False)
    spent_on = serializers.DateField(required=False)
    notes = serializers.CharField(required=False, allow_blank=True)


class DonationInput(serializers.Serializer):
    amount_minor = serializers.IntegerField(min_value=1)
    method = serializers.ChoiceField(choices=Donation.Method.choices)
    currency = serializers.CharField(max_length=3, required=False)
    status = serializers.ChoiceField(choices=Donation.Status.choices, required=False)
    received_on = serializers.DateField(required=False)
    transaction_number = serializers.CharField(
        max_length=120, required=False, allow_blank=True
    )
    donor_name = serializers.CharField(max_length=120, required=False, allow_blank=True)
    donor_email = serializers.EmailField(required=False, allow_blank=True)
    notes = serializers.CharField(required=False, allow_blank=True)


class ExpenseQueryInput(serializers.Serializer):
    # A bad value is a 400 on its field, never silently "everything".
    type = serializers.ChoiceField(choices=Expense.Type.choices, required=False)
    currency = serializers.CharField(max_length=3, required=False, allow_blank=True)
    spent_from = serializers.DateField(required=False)
    spent_to = serializers.DateField(required=False)
    q = serializers.CharField(required=False, allow_blank=True)
    posted = serializers.ChoiceField(choices=YES_NO, required=False)

    def validate_posted(self, value: str) -> bool:
        return value == "true"


class DonationQueryInput(serializers.Serializer):
    status = serializers.ChoiceField(choices=Donation.Status.choices, required=False)
    method = serializers.ChoiceField(choices=Donation.Method.choices, required=False)
    currency = serializers.CharField(max_length=3, required=False, allow_blank=True)
    received_from = serializers.DateField(required=False)
    received_to = serializers.DateField(required=False)
    q = serializers.CharField(required=False, allow_blank=True)
```

`backend/etqan/finance/api/payloads.py`:

```python
"""JSON shapes for finance (B3a §4.2). A list row is the detail."""


def _person(user) -> dict | None:
    if user is None:
        return None
    return {"id": user.pk, "full_name": user.full_name}


def expense(row) -> dict:
    return {
        "id": row.pk,
        "title": row.title,
        "type": row.type,
        "amount_minor": row.amount_minor,
        "currency": row.currency,
        "spent_on": row.spent_on,
        "notes": row.notes,
        "source": row.source,
        "source_id": row.source_id,
        "posted": bool(row.source),
        "created_by": _person(row.created_by),
        "created_at": row.created_at,
        "updated_at": row.updated_at,
    }


def donation(row) -> dict:
    return {
        "id": row.pk,
        "number": row.number,
        "amount_minor": row.amount_minor,
        "currency": row.currency,
        "method": row.method,
        "transaction_number": row.transaction_number,
        "status": row.status,
        "donor_name": row.donor_name,
        "donor_email": row.donor_email,
        "received_on": row.received_on,
        "notes": row.notes,
        "created_by": _person(row.created_by),
        "created_at": row.created_at,
        "updated_at": row.updated_at,
    }
```

`backend/etqan/finance/api/views.py`:

```python
"""Finance endpoints (B3a §5). Thin: parse, call one service, re-read and
arrange a payload. Office only (A-9): ``HasCode`` lets admins through and
staff with the route's code; nobody else. ``FeatureOn`` runs after it, so a
code holder gets 404 while the route's feature is off."""

from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.finance import services
from etqan.finance.api import payloads
from etqan.finance.api.serializers import DonationInput
from etqan.finance.api.serializers import DonationQueryInput
from etqan.finance.api.serializers import ExpenseInput
from etqan.finance.api.serializers import ExpenseQueryInput
from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode

EXPENSE_CSV = (
    ("title", "Title"),
    ("type", "Type"),
    ("amount_minor", "Amount (minor units)"),
    ("currency", "Currency"),
    ("spent_on", "Spent on"),
    ("notes", "Notes"),
    ("posted", "Posted"),
)
DONATION_CSV = (
    ("number", "Number"),
    ("donor_name", "Donor"),
    ("donor_email", "Email"),
    ("amount_minor", "Amount (minor units)"),
    ("currency", "Currency"),
    ("method", "Method"),
    ("transaction_number", "Transaction number"),
    ("status", "Status"),
    ("received_on", "Received on"),
)


def _expense(pk) -> dict:
    """A fresh read of what a write changed."""
    return payloads.expense(services.expenses_queryset().get(pk=pk))


def _donation(pk) -> dict:
    return payloads.donation(services.donations_queryset().get(pk=pk))


class ExpenseListView(CSVExportMixin, generics.GenericAPIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "expenses"
    permission_codes = {"GET": "expense.view_any", "POST": "expense.create"}
    csv_filename = "expenses"
    csv_columns = EXPENSE_CSV

    def get(self, request):
        query = ExpenseQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        expenses = services.filter_expenses(
            services.expenses_queryset(), **query.validated_data
        )
        if self.wants_csv():
            return self.csv_response([payloads.expense(e) for e in expenses])
        page = self.paginate_queryset(expenses)
        return self.get_paginated_response([payloads.expense(e) for e in page])

    def post(self, request):
        body = ExpenseInput(data=request.data)
        body.is_valid(raise_exception=True)
        expense = services.create_expense(**body.validated_data, by=request.user)
        return Response(_expense(expense.pk), status=status.HTTP_201_CREATED)


class ExpenseDetailView(APIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "expenses"
    permission_codes = {
        "GET": "expense.view",
        "PATCH": "expense.update",
        "DELETE": "expense.delete",
    }

    def get(self, request, pk):
        return Response(
            payloads.expense(get_object_or_404(services.expenses_queryset(), pk=pk))
        )

    def patch(self, request, pk):
        expense = get_object_or_404(services.expenses_queryset(), pk=pk)
        body = ExpenseInput(data=request.data, partial=True)
        body.is_valid(raise_exception=True)
        services.update_expense(expense, **body.validated_data)
        return Response(_expense(pk))

    def delete(self, request, pk):
        services.delete_expense(get_object_or_404(services.expenses_queryset(), pk=pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class DonationListView(CSVExportMixin, generics.GenericAPIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "donations"
    permission_codes = {"GET": "donation.view_any", "POST": "donation.create"}
    csv_filename = "donations"
    csv_columns = DONATION_CSV

    def get(self, request):
        query = DonationQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        donations = services.filter_donations(
            services.donations_queryset(), **query.validated_data
        )
        if self.wants_csv():
            return self.csv_response([payloads.donation(d) for d in donations])
        page = self.paginate_queryset(donations)
        return self.get_paginated_response([payloads.donation(d) for d in page])

    def post(self, request):
        body = DonationInput(data=request.data)
        body.is_valid(raise_exception=True)
        donation = services.create_donation(**body.validated_data, by=request.user)
        return Response(_donation(donation.pk), status=status.HTTP_201_CREATED)


class DonationDetailView(APIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "donations"
    permission_codes = {
        "GET": "donation.view",
        "PATCH": "donation.update",
        "DELETE": "donation.delete",
    }

    def get(self, request, pk):
        return Response(
            payloads.donation(get_object_or_404(services.donations_queryset(), pk=pk))
        )

    def patch(self, request, pk):
        donation = get_object_or_404(services.donations_queryset(), pk=pk)
        body = DonationInput(data=request.data, partial=True)
        body.is_valid(raise_exception=True)
        services.update_donation(donation, **body.validated_data)
        return Response(_donation(pk))

    def delete(self, request, pk):
        services.delete_donation(
            get_object_or_404(services.donations_queryset(), pk=pk)
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class SummaryView(APIView):
    """The home's expenses and net profit: the revenue widget (A-9)."""

    permission_classes = [HasCode, FeatureOn]
    feature = "expenses"
    permission_codes = {"GET": "widget.revenue_stats"}

    def get(self, request):
        return Response(services.summary())


class DonationSummaryView(APIView):
    """The home's donations: the revenue widget too (A-9)."""

    permission_classes = [HasCode, FeatureOn]
    feature = "donations"
    permission_codes = {"GET": "widget.revenue_stats"}

    def get(self, request):
        return Response(services.donations_summary())
```

`backend/etqan/finance/api/urls.py`:

```python
from django.urls import path

from etqan.finance.api import views

app_name = "finance"
urlpatterns = [
    path("expenses/", views.ExpenseListView.as_view(), name="expenses"),
    path("expenses/<int:pk>/", views.ExpenseDetailView.as_view(), name="expense"),
    path("donations/", views.DonationListView.as_view(), name="donations"),
    path(
        "donations/summary/",
        views.DonationSummaryView.as_view(),
        name="donations-summary",
    ),
    path("donations/<int:pk>/", views.DonationDetailView.as_view(), name="donation"),
    path("summary/", views.SummaryView.as_view(), name="summary"),
]
```

`backend/config/api_router.py`, under `# ── phase B3 ──`:

```python
    # ── phase B3 ──
    # expenses/, donations/, donations/summary/, summary/ (B3a spec §5).
    path("finance/", include("etqan.finance.api.urls")),
```

- [ ] **Step 5: Run them to verify they pass**

Run: `$DJ pytest etqan/finance etqan/access -q`
Expected: PASS. In `test_routes.py`, staff with the code get 404 (not 403) from the finance routes while the features are off. That is expected, and the tests assert only `!= 403`.

- [ ] **Step 6: Format, lint, contracts, commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/finance etqan/access config/api_router.py
git -C backend commit -m "feat(finance): /api/v1/finance/ routes, expense and donation permissions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Demo seeds

**Files:**
- Create: `backend/etqan/tenants/seeds/finance.py`, `backend/etqan/tenants/tests/test_seed_finance.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (one import, one line under the B3 marker)

**Interfaces:**
- Consumes: `finance.services.create_expense`, `create_donation`, `has_records`, `today`.
- Produces: `etqan.tenants.seeds.finance.seed_finance(subdomain: str) -> None`.

- [ ] **Step 1: Write the failing test**

`backend/etqan/tenants/tests/test_seed_finance.py`:

```python
"""B3a spec §7: the demo academy's expenses and donations, seeded once."""

import pytest
from django.core.management import call_command
from django.db import connection
from django.test import override_settings
from django_tenants.utils import tenant_context

from etqan.finance import services as finance
from etqan.tenants.models import Academy


def state():
    expenses = [
        (e.title, e.type, e.amount_minor, e.currency, e.spent_on.day)
        for e in finance.expenses_queryset().order_by("pk")
    ]
    donations = [
        (d.number, d.status, d.amount_minor, d.currency, d.donor_name)
        for d in finance.donations_queryset().order_by("pk")
    ]
    return expenses, donations


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_gives_demo_its_expenses_and_donations_once():
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        first = state()
        assert first == (
            [
                ("Office rent", "rent", 250000, "EGP", 1),
                ("Facebook ads", "marketing", 60000, "EGP", 1),
                ("Zoom subscription", "software", 15000, "EGP", 1),
                ("Teachers' Eid bonus", "salaries", 40000, "EGP", 1),
            ],
            [
                ("DON-000001", "completed", 50000, "EGP", "Abu Khalid"),
                ("DON-000002", "completed", 25000, "EGP", ""),
                ("DON-000003", "pending", 100000, "EGP", "Umm Sara"),
            ],
        )
        assert all(e.source == "" for e in finance.expenses_queryset())
    with tenant_context(other):
        assert state() == ([], [])
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert state() == first
```

Run: `$DJ pytest etqan/tenants/tests/test_seed_finance.py -q`
Expected: FAIL (the first `state()` is `([], [])`).

- [ ] **Step 2: Implement**

`backend/etqan/tenants/seeds/finance.py`:

```python
"""Phase B3, slice B3a (spec §7): the demo academy's expenses and donations.

In EGP, as the demo packages are, so the demo's net profit nets against its
revenue (plan D8); dated the first of the academy's month, so they count as
this month's. Idempotent: an academy that already has an expense or a
donation is left alone."""

from etqan.finance import services as finance_services

EXPENSES = {
    "demo": (
        ("Office rent", "rent", 250000),
        ("Facebook ads", "marketing", 60000),
        ("Zoom subscription", "software", 15000),
        ("Teachers' Eid bonus", "salaries", 40000),
    )
}
DONATIONS = {
    "demo": (
        (50000, "bank_transfer", "completed", "Abu Khalid"),
        (25000, "cash", "completed", ""),
        (100000, "instapay", "pending", "Umm Sara"),
    )
}


def seed_finance(subdomain: str) -> None:
    if finance_services.has_records():
        return
    first = finance_services.today().replace(day=1)
    for title, kind, amount in EXPENSES.get(subdomain, ()):
        finance_services.create_expense(
            title=title,
            type=kind,
            amount_minor=amount,
            currency="EGP",
            spent_on=first,
            by=None,
        )
    for amount, method, status, donor in DONATIONS.get(subdomain, ()):
        finance_services.create_donation(
            amount_minor=amount,
            method=method,
            status=status,
            donor_name=donor,
            currency="EGP",
            received_on=first,
            by=None,
        )
```

In `backend/etqan/tenants/management/commands/seed_dev.py`:
- add the import `from etqan.tenants.seeds import finance as finance_seeds` after `from etqan.tenants.models import Academy` (isort order);
- under `seed_academy`'s marker, add:

```python
        # ── phase B3 ──
        finance_seeds.seed_finance(subdomain)
```

- [ ] **Step 3: Run the seed tests**

Run: `$DJ pytest etqan/tenants -q`
Expected: PASS. That includes `test_seed_dev_switches_every_built_feature_on_in_demo_only`, which now covers `expenses` and `donations` through `BUILT`.

- [ ] **Step 4: Format, lint, contracts, commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/tenants
git -C backend commit -m "feat(seeds): demo expenses and donations

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Backend gate**

Run: `$DJ sh -c 'ruff check . && ruff format --check . && lint-imports && pytest -q --cov=etqan'`
Expected: all pass; coverage ≥ 80 % (the floor in `pyproject.toml`).

---
### Task 8: Dashboard foundations: types, API, hooks, translations and nav

**Files:**
- Create in `dashboard/src/features/finance/`: `schemas.ts`, `api.ts`, `queries.ts`, `landing.ts`, `bits.tsx`, `index.ts`, `schemas.test.ts`, `api.test.ts`, `landing.test.ts`
- Create: `dashboard/src/locales/en/finance.json`, `dashboard/src/locales/ar/finance.json`, `dashboard/src/test/finance-fixtures.ts`
- Modify:
  - `dashboard/src/features/identity/schemas.ts` (`FeatureCode`);
  - `dashboard/src/features/shell/nav.ts` (icon imports, plus two items under the B3 marker);
  - `dashboard/src/features/shell/nav.test.ts`.

  The `/billing` index switches to `billingLanding` in Task 10, once both new routes exist, because the router types `redirect({ to })` against the route tree.

**Interfaces:**
- Consumes: the API of Task 6.
- Produces:
  - types `Expense`, `Donation`, `MoneyLine`, `FinanceSummary`, `DonationsSummary`, `ExpenseBody`, `DonationBody`;
  - the constants `EXPENSE_TYPES`, `DONATION_METHODS`, `DONATION_STATUSES`;
  - the form schemas `expenseFormSchema`, `donationFormSchema` (types `ExpenseFormValues`, `DonationFormValues`);
  - `financeApi.{expenses, createExpense, updateExpense, deleteExpense, donations, createDonation, updateDonation, deleteDonation, summary, donationsSummary}`, `expensesCsvUrl`, `donationsCsvUrl`;
  - the hooks `useExpenses`, `useDonations`, `useFinanceSummary`, `useDonationsSummary`, `useFinanceMutation`, under the key `financeKey`;
  - `billingLanding(me)`, `financeErrorText(error, t)`, `useFinanceFieldError()`, `<PostedBadge source />`;
  - the fixtures `expenseRow`, `donationRow`, `financeSummary`, `donationsSummary`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/finance/api.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { donationsCsvUrl, expensesCsvUrl, financeApi } from "./api";

vi.mock("@/lib/api", async (orig) => {
	const actual = await orig<typeof import("@/lib/api")>();
	const ok = () => Promise.resolve({ data: { id: 1 } });
	return {
		...actual,
		api: {
			defaults: { baseURL: "/api/v1/" },
			get: vi.fn(ok),
			post: vi.fn(ok),
			patch: vi.fn(ok),
			delete: vi.fn(ok),
		},
	};
});

describe("financeApi", () => {
	beforeEach(() => vi.clearAllMocks());

	it("reads the lists and summaries from the spec §5 routes", async () => {
		await financeApi.expenses({ type: "rent", q: "", page: 2 });
		expect(api.get).toHaveBeenCalledWith("finance/expenses/", {
			params: { type: "rent", page: "2" },
		});
		await financeApi.donations({ status: "pending" });
		expect(api.get).toHaveBeenLastCalledWith("finance/donations/", {
			params: { status: "pending" },
		});
		await financeApi.summary();
		expect(api.get).toHaveBeenLastCalledWith("finance/summary/");
		await financeApi.donationsSummary();
		expect(api.get).toHaveBeenLastCalledWith("finance/donations/summary/");
	});

	it("writes expenses and donations", async () => {
		const expense = { title: "Rent", type: "rent" as const, amount_minor: 100 };
		await financeApi.createExpense(expense);
		expect(api.post).toHaveBeenCalledWith("finance/expenses/", expense);
		await financeApi.updateExpense({ id: 3, notes: "June" });
		expect(api.patch).toHaveBeenCalledWith("finance/expenses/3/", {
			notes: "June",
		});
		await financeApi.deleteExpense(3);
		expect(api.delete).toHaveBeenCalledWith("finance/expenses/3/");
		const donation = { amount_minor: 100, method: "cash" as const };
		await financeApi.createDonation(donation);
		expect(api.post).toHaveBeenLastCalledWith("finance/donations/", donation);
		await financeApi.updateDonation({ id: 4, status: "refunded" });
		expect(api.patch).toHaveBeenLastCalledWith("finance/donations/4/", {
			status: "refunded",
		});
		await financeApi.deleteDonation(4);
		expect(api.delete).toHaveBeenLastCalledWith("finance/donations/4/");
	});

	it("builds the CSV links with the list's filters, without paging", () => {
		expect(expensesCsvUrl({ type: "rent", page: 3 })).toBe(
			"/api/v1/finance/expenses/?type=rent&format=csv",
		);
		expect(donationsCsvUrl({ status: "completed" })).toBe(
			"/api/v1/finance/donations/?status=completed&format=csv",
		);
	});
});
```

`dashboard/src/features/finance/schemas.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { donationFormSchema, expenseFormSchema } from "./schemas";

const expense = {
	title: "Rent",
	type: "rent",
	amount: "150.50",
	currency: "EGP",
	spent_on: "2026-06-01",
	notes: "",
};
const donation = {
	amount: "50",
	currency: "USD",
	method: "cash",
	status: "completed",
	received_on: "2026-06-01",
	transaction_number: "",
	donor_name: "",
	donor_email: "",
	notes: "",
};

const messages = (result: { success: boolean; error?: { issues: { path: PropertyKey[]; message: string }[] } }) =>
	Object.fromEntries(
		(result.error?.issues ?? []).map((issue) => [
			String(issue.path[0]),
			issue.message,
		]),
	);

describe("expenseFormSchema", () => {
	it("takes a filled-in expense", () => {
		expect(expenseFormSchema.safeParse(expense).success).toBe(true);
	});

	it("refuses a blank title and a missing date", () => {
		const result = expenseFormSchema.safeParse({
			...expense,
			title: " ",
			spent_on: "",
		});
		expect(messages(result)).toEqual({
			title: "finance.errors.required",
			spent_on: "finance.errors.dateRequired",
		});
	});

	it("refuses more decimals than the currency has, never rounding (review focus 5)", () => {
		for (const [currency, value] of [
			["EGP", "1.234"],
			["JPY", "1.5"],
		]) {
			expect(
				messages(expenseFormSchema.safeParse({ ...expense, currency, amount: value })),
			).toEqual({ amount: "billing.errors.amountInvalid" });
		}
		expect(
			expenseFormSchema.safeParse({ ...expense, currency: "JPY", amount: "15" })
				.success,
		).toBe(true);
	});

	it("refuses a title over 200 characters", () => {
		expect(
			messages(expenseFormSchema.safeParse({ ...expense, title: "x".repeat(201) })),
		).toEqual({ title: "finance.errors.tooLong" });
	});
});

describe("donationFormSchema", () => {
	it("takes a donation with or without a donor email", () => {
		expect(donationFormSchema.safeParse(donation).success).toBe(true);
		expect(
			donationFormSchema.safeParse({ ...donation, donor_email: "a@b.test" })
				.success,
		).toBe(true);
	});

	it("refuses a bad email, a zero amount and an unknown method", () => {
		const result = donationFormSchema.safeParse({
			...donation,
			donor_email: "nope",
			amount: "0",
			method: "gold",
		});
		expect(Object.keys(messages(result)).sort()).toEqual([
			"amount",
			"donor_email",
			"method",
		]);
		expect(messages(result).donor_email).toBe("finance.errors.email");
	});
});
```

`dashboard/src/features/finance/landing.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import type { Me } from "@/features/identity/schemas";
import { staffMe } from "@/test/access-fixtures";
import { billingLanding } from "./landing";

const admin: Me = {
	id: 1,
	email: "a@b.test",
	full_name: "Amina",
	role: "admin",
	profiles: [],
};

describe("billingLanding", () => {
	it("opens the first billing page the user may see, in nav order", () => {
		expect(billingLanding(admin)).toBe("/billing/invoices");
		expect(billingLanding({ ...admin, features: ["expenses", "donations"] })).toBe(
			"/billing/expenses",
		);
		expect(billingLanding({ ...admin, features: ["donations"] })).toBe(
			"/billing/donations",
		);
		expect(billingLanding(staffMe("donation.view_any"))).toBe(
			"/billing/donations",
		);
	});

	it("sends someone who may see none of them home", () => {
		expect(billingLanding({ ...admin, features: [] })).toBe("/");
		expect(billingLanding(staffMe())).toBe("/");
	});
});
```

(`features` undefined means everything is on, as `hasFeature` reads it.)

In `dashboard/src/features/shell/nav.test.ts`:

1. In `"ships the grouped admin areas in order"`, insert `"/billing/expenses"` and `"/billing/donations"` after `"/settings/roles"` (they sit under the B3 marker, before `/account`).
2. In `"hides the items of every feature the academy has switched off"`, add `"/billing/expenses"` and `"/billing/donations"` to the loop's list.
3. In `"names a feature on exactly the items that belong to one"`, add `"/billing/expenses": "expenses"` and `"/billing/donations": "donations"` to the expected object.
4. In `"groups consecutive items"`, change the billing group expectation to:

```ts
		expect(groups[2]?.items.map((i) => i.labelKey)).toEqual([
			"nav.invoices",
			"finance.nav.expenses",
			"finance.nav.donations",
		]);
```

5. Add a test:

```ts
	it("shows Expenses and Donations to staff with their codes while each is on", () => {
		const codes = (c: string) =>
			c === "expense.view_any" || c === "donation.view_any";
		const only = (on: FeatureCode) => (code: FeatureCode) => code === on;
		expect(
			visibleNavItems(NAV_ITEMS, [], "staff", codes, only("expenses")).map(
				(i) => i.to,
			),
		).toEqual(["/", "/billing/expenses", "/account"]);
		expect(
			visibleNavItems(NAV_ITEMS, [], "staff", codes, only("donations")).map(
				(i) => i.to,
			),
		).toEqual(["/", "/billing/donations", "/account"]);
	});
```

Run: `npx pnpm@10 vitest run src/features/finance src/features/shell/nav.test.ts`
Expected: FAIL (`./api` not found; nav lists differ).

- [ ] **Step 2: Write the module**

`dashboard/src/features/finance/schemas.ts`:

```ts
import { z } from "zod";
import { amount } from "@/features/billing";

// B3a spec A-4, A-6.
export const EXPENSE_TYPES = [
	"salaries",
	"rent",
	"marketing",
	"software",
	"utilities",
	"supplies",
	"fees",
	"other",
] as const;
export type ExpenseType = (typeof EXPENSE_TYPES)[number];
export const DONATION_METHODS = [
	"cash",
	"bank_transfer",
	"instapay",
	"vodafone_cash",
	"western_union",
	"zelle",
	"venmo",
	"cashapp",
	"other",
	"stripe",
	"paypal",
] as const;
export type DonationMethod = (typeof DONATION_METHODS)[number];
export const DONATION_STATUSES = [
	"pending",
	"completed",
	"failed",
	"refunded",
	"cancelled",
] as const;
export type DonationStatus = (typeof DONATION_STATUSES)[number];

export interface Person {
	id: number;
	full_name: string;
}

/** Spec §4.2. A posted expense (`source` set) is read-only (A-8). */
export interface Expense {
	id: number;
	title: string;
	type: ExpenseType;
	amount_minor: number;
	currency: string;
	spent_on: string;
	notes: string;
	source: string;
	source_id: number | null;
	posted: boolean;
	created_by: Person | null;
	created_at: string;
	updated_at: string;
}

export interface Donation {
	id: number;
	number: string;
	amount_minor: number;
	currency: string;
	method: DonationMethod;
	transaction_number: string;
	status: DonationStatus;
	donor_name: string;
	donor_email: string;
	received_on: string;
	notes: string;
	created_by: Person | null;
	created_at: string;
	updated_at: string;
}

export interface MoneyLine {
	currency: string;
	amount_minor: number;
}
/** Spec §4.6: `net_profit_this_month` is null while invoices are off. */
export interface FinanceSummary {
	expenses_this_month: MoneyLine[];
	net_profit_this_month: MoneyLine[] | null;
}
export interface DonationsSummary {
	donations_this_month: MoneyLine[];
}

// Request bodies (spec §4.1).
export interface ExpenseBody {
	title: string;
	type: ExpenseType;
	amount_minor: number;
	currency?: string;
	spent_on?: string;
	notes?: string;
}
export interface DonationBody {
	amount_minor: number;
	method: DonationMethod;
	currency?: string;
	status?: DonationStatus;
	received_on?: string;
	transaction_number?: string;
	donor_name?: string;
	donor_email?: string;
	notes?: string;
}

// Form schemas. Messages are i18n keys, translated by `useFieldError`.
const day = z
	.string()
	.regex(/^\d{4}-\d{2}-\d{2}$/, "finance.errors.dateRequired");
const currency = z.string().regex(/^[A-Z]{3}$/, "finance.errors.required");
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** An amount shaped like a number above zero, before its currency is
 * known (as billing's invoice form does). */
const looseAmount = z
	.string()
	.min(1, "finance.errors.required")
	.refine(
		(value) => /^\d+(\.\d+)?$/.test(value.trim()) && Number(value) > 0,
		"billing.errors.amountInvalid",
	);

/** Then checked against the chosen currency's minor units with billing's
 * one money field, so "1.234" EGP or "1.5" JPY is refused, never rounded.
 * Zod runs an object's refinement only once every field has parsed. */
function amountFor(
	data: { amount: string; currency: string },
	ctx: z.RefinementCtx,
) {
	if (!amount(data.currency).safeParse(data.amount).success) {
		ctx.addIssue({
			code: "custom",
			path: ["amount"],
			message: "billing.errors.amountInvalid",
		});
	}
}

export const expenseFormSchema = z
	.object({
		title: z
			.string()
			.trim()
			.min(1, "finance.errors.required")
			.max(200, "finance.errors.tooLong"),
		type: z.enum(EXPENSE_TYPES),
		amount: looseAmount,
		currency,
		spent_on: day,
		notes: z.string(),
	})
	.superRefine(amountFor);
export type ExpenseFormValues = z.infer<typeof expenseFormSchema>;

export const donationFormSchema = z
	.object({
		amount: looseAmount,
		currency,
		method: z.enum(DONATION_METHODS, "finance.errors.required"),
		status: z.enum(DONATION_STATUSES),
		received_on: day,
		transaction_number: z.string().max(120, "finance.errors.tooLong"),
		donor_name: z.string().max(120, "finance.errors.tooLong"),
		donor_email: z
			.string()
			.trim()
			.refine((value) => value === "" || EMAIL.test(value), "finance.errors.email"),
		notes: z.string(),
	})
	.superRefine(amountFor);
export type DonationFormValues = z.infer<typeof donationFormSchema>;
```

`dashboard/src/features/finance/api.ts`:

```ts
import {
	api,
	clean,
	csvUrl,
	type Paginated,
	type QueryParams,
} from "@/lib/api";
import type {
	Donation,
	DonationBody,
	DonationsSummary,
	Expense,
	ExpenseBody,
	FinanceSummary,
} from "./schemas";

const F = "finance/";
const EXPENSES = `${F}expenses/`;
const DONATIONS = `${F}donations/`;

export const financeApi = {
	expenses: async (params: QueryParams) =>
		(await api.get<Paginated<Expense>>(EXPENSES, { params: clean(params) }))
			.data,
	createExpense: async (body: ExpenseBody) =>
		(await api.post<Expense>(EXPENSES, body)).data,
	updateExpense: async ({
		id,
		...body
	}: Partial<ExpenseBody> & { id: number }) =>
		(await api.patch<Expense>(`${EXPENSES}${id}/`, body)).data,
	deleteExpense: async (id: number) => {
		await api.delete(`${EXPENSES}${id}/`);
	},
	donations: async (params: QueryParams) =>
		(await api.get<Paginated<Donation>>(DONATIONS, { params: clean(params) }))
			.data,
	createDonation: async (body: DonationBody) =>
		(await api.post<Donation>(DONATIONS, body)).data,
	updateDonation: async ({
		id,
		...body
	}: Partial<DonationBody> & { id: number }) =>
		(await api.patch<Donation>(`${DONATIONS}${id}/`, body)).data,
	deleteDonation: async (id: number) => {
		await api.delete(`${DONATIONS}${id}/`);
	},
	summary: async () => (await api.get<FinanceSummary>(`${F}summary/`)).data,
	donationsSummary: async () =>
		(await api.get<DonationsSummary>(`${DONATIONS}summary/`)).data,
};

/** The expense list's CSV export, with the list's filters. */
export function expensesCsvUrl(params: QueryParams): string {
	return csvUrl(EXPENSES, params);
}

/** The donation list's CSV export, with the list's filters. */
export function donationsCsvUrl(params: QueryParams): string {
	return csvUrl(DONATIONS, params);
}
```

`dashboard/src/features/finance/queries.ts`:

```ts
import {
	keepPreviousData,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import type { QueryParams } from "@/lib/api";
import { financeApi } from "./api";

/** Every finance query lives under this key. */
export const financeKey = ["finance"] as const;

export function useExpenses(params: QueryParams) {
	return useQuery({
		queryKey: [...financeKey, "expenses", params],
		queryFn: () => financeApi.expenses(params),
		placeholderData: keepPreviousData,
	});
}

export function useDonations(params: QueryParams) {
	return useQuery({
		queryKey: [...financeKey, "donations", params],
		queryFn: () => financeApi.donations(params),
		placeholderData: keepPreviousData,
	});
}

export function useFinanceSummary({ enabled }: { enabled: boolean }) {
	return useQuery({
		queryKey: [...financeKey, "summary"],
		queryFn: financeApi.summary,
		enabled,
	});
}

export function useDonationsSummary({ enabled }: { enabled: boolean }) {
	return useQuery({
		queryKey: [...financeKey, "donations-summary"],
		queryFn: financeApi.donationsSummary,
		enabled,
	});
}

/** A finance write: on success the lists and the home card refresh. */
export function useFinanceMutation<A, R>(write: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (args: A) => write(args),
		onSuccess: () => qc.invalidateQueries({ queryKey: financeKey }),
	});
}
```

`dashboard/src/features/finance/landing.ts`:

```ts
import { can, hasFeature } from "@/features/identity/permissions";
import type { FeatureCode, Me } from "@/features/identity/schemas";

/** The billing pages in nav order, each with its code and feature. */
const BILLING_PAGES = [
	{ to: "/billing/invoices", code: "invoice.view_any", feature: "invoices" },
	{ to: "/billing/expenses", code: "expense.view_any", feature: "expenses" },
	{ to: "/billing/donations", code: "donation.view_any", feature: "donations" },
] as const satisfies readonly {
	to: string;
	code: string;
	feature: FeatureCode;
}[];

export type BillingPage = (typeof BILLING_PAGES)[number]["to"] | "/";

/** B3a spec §6: `/billing` opens the first billing page `me` may see; home
 * when there is none. */
export function billingLanding(me: Me): BillingPage {
	return (
		BILLING_PAGES.find(
			(page) => can(me, page.code) && hasFeature(me, page.feature),
		)?.to ?? "/"
	);
}
```

`dashboard/src/features/finance/bits.tsx`:

```tsx
import type { TFunction } from "i18next";
import { useTranslation } from "react-i18next";
import { parseApiError } from "@/features/identity/api";
import { useFieldError } from "@/lib/field-error";
import { codeKey, errorText } from "@/lib/form-errors";

const POSTED = "finance.expense_posted";

/** A failed finance action as one sentence (plan D5): the posted-expense
 * refusal from finance's own file, anything else as everywhere else. */
export function financeErrorText(error: unknown, t: TFunction): string {
	return parseApiError(error).code === POSTED
		? t("finance.errors.expense_posted")
		: errorText(error, t);
}

/** `useFieldError` that also reads the posted-expense refusal a form puts on
 * `root.server` (plan D5). */
export function useFinanceFieldError() {
	const fieldError = useFieldError();
	return (message: string | undefined) =>
		fieldError(
			message === codeKey(POSTED) ? "finance.errors.expense_posted" : message,
		);
}

/** Where a posted expense came from (spec §6): "Posted from payroll", or a
 * generic "Posted" for a source this dashboard doesn't know yet. */
export function PostedBadge({ source }: { source: string }) {
	const { t } = useTranslation();
	return (
		<span className="inline-flex rounded-md bg-secondary px-2 py-1 text-xs font-medium text-muted-foreground">
			{t(`finance.source.${source}`, {
				defaultValue: t("finance.source.generic"),
			})}
		</span>
	);
}
```

`dashboard/src/features/finance/index.ts` (the components arrive in Tasks 9–11 and are added here then):

```ts
export { donationsCsvUrl, expensesCsvUrl, financeApi } from "./api";
export { financeErrorText, PostedBadge, useFinanceFieldError } from "./bits";
export { billingLanding } from "./landing";
export * from "./queries";
export * from "./schemas";
```

`dashboard/src/test/finance-fixtures.ts`:

```ts
import type {
	Donation,
	DonationsSummary,
	Expense,
	FinanceSummary,
} from "@/features/finance/schemas";

/** API-shaped finance rows for feature tests. */
export function expenseRow(overrides: Partial<Expense> = {}): Expense {
	return {
		id: 81,
		title: "Office rent",
		type: "rent",
		amount_minor: 250000,
		currency: "EGP",
		spent_on: "2026-06-01",
		notes: "June",
		source: "",
		source_id: null,
		posted: false,
		created_by: { id: 1, full_name: "Amina" },
		created_at: "2026-06-01T08:00:00Z",
		updated_at: "2026-06-01T08:00:00Z",
		...overrides,
	};
}

export function donationRow(overrides: Partial<Donation> = {}): Donation {
	return {
		id: 91,
		number: "DON-000001",
		amount_minor: 50000,
		currency: "EGP",
		method: "bank_transfer",
		transaction_number: "TX-1",
		status: "completed",
		donor_name: "Abu Khalid",
		donor_email: "",
		received_on: "2026-06-01",
		notes: "",
		created_by: { id: 1, full_name: "Amina" },
		created_at: "2026-06-01T08:00:00Z",
		updated_at: "2026-06-01T08:00:00Z",
		...overrides,
	};
}

export function financeSummary(
	overrides: Partial<FinanceSummary> = {},
): FinanceSummary {
	return {
		expenses_this_month: [{ currency: "EGP", amount_minor: 365000 }],
		net_profit_this_month: [
			{ currency: "EGP", amount_minor: -165000 },
			{ currency: "USD", amount_minor: 4000 },
		],
		...overrides,
	};
}

export function donationsSummary(
	overrides: Partial<DonationsSummary> = {},
): DonationsSummary {
	return {
		donations_this_month: [{ currency: "EGP", amount_minor: 75000 }],
		...overrides,
	};
}
```

`dashboard/src/locales/en/finance.json`:

```json
{
	"nav": {
		"expenses": "Expenses",
		"donations": "Donations"
	},
	"types": {
		"salaries": "Salaries",
		"rent": "Rent",
		"marketing": "Marketing",
		"software": "Software",
		"utilities": "Utilities",
		"supplies": "Supplies",
		"fees": "Fees",
		"other": "Other"
	},
	"methods": {
		"cash": "Cash",
		"bank_transfer": "Bank transfer",
		"instapay": "InstaPay",
		"vodafone_cash": "Vodafone Cash",
		"western_union": "Western Union",
		"zelle": "Zelle",
		"venmo": "Venmo",
		"cashapp": "Cash App",
		"other": "Other",
		"stripe": "Stripe",
		"paypal": "PayPal"
	},
	"statuses": {
		"pending": "Pending",
		"completed": "Completed",
		"failed": "Failed",
		"refunded": "Refunded",
		"cancelled": "Cancelled"
	},
	"source": {
		"generic": "Posted",
		"payroll": {
			"payslip": "Posted from payroll"
		}
	},
	"fields": {
		"title": "Title",
		"type": "Type",
		"amount": "Amount",
		"amountIn": "Amount ({{currency}})",
		"currency": "Currency",
		"spentOn": "Date",
		"receivedOn": "Received on",
		"notes": "Notes",
		"method": "Method",
		"status": "Status",
		"transactionNumber": "Transaction number",
		"donorName": "Donor name",
		"donorEmail": "Donor email",
		"number": "Number",
		"donor": "Donor",
		"actions": "Actions"
	},
	"list": {
		"from": "From",
		"to": "To",
		"anyType": "Any type",
		"anyCurrency": "Any currency",
		"anyStatus": "Any status",
		"anyMethod": "Any method"
	},
	"expenses": {
		"add": "Add expense",
		"edit": "Edit",
		"editFor": "Edit {{title}}",
		"editTitle": "Edit expense",
		"body": "Money the academy spent, in one currency.",
		"save": "Save expense",
		"saved": "Expense saved.",
		"delete": "Delete",
		"deleteTitle": "Delete this expense",
		"deleteBody": "It leaves this month's figures. This can't be undone.",
		"deleted": "Expense deleted.",
		"empty": "No expenses yet.",
		"loadError": "The expenses could not be loaded.",
		"search": "Search by title",
		"entry": "Entry",
		"filter": {
			"all": "All entries",
			"manual": "Entered here",
			"posted": "Posted by the system"
		}
	},
	"donations": {
		"add": "Add donation",
		"edit": "Edit",
		"editFor": "Edit {{number}}",
		"editTitle": "Edit donation",
		"body": "A gift to the academy. Donations are not revenue.",
		"save": "Save donation",
		"saved": "Donation saved.",
		"delete": "Delete",
		"deleteTitle": "Delete this donation",
		"deleteBody": "This can't be undone.",
		"deleted": "Donation deleted.",
		"empty": "No donations yet.",
		"loadError": "The donations could not be loaded.",
		"search": "Search by number, donor or transaction"
	},
	"home": {
		"title": "Spending and giving",
		"expenses": "Expenses this month",
		"noExpenses": "No expenses yet this month.",
		"netProfit": "Net profit this month",
		"noProfit": "No revenue or expenses yet this month.",
		"donations": "Donations this month",
		"noDonations": "No donations yet this month.",
		"loadError": "Couldn't load this month's figures."
	},
	"errors": {
		"required": "Fill this in.",
		"dateRequired": "Choose a date.",
		"tooLong": "That is too long.",
		"email": "Enter a valid email address, or leave it empty.",
		"expense_posted": "This expense was posted from another part of the system, so it can't be changed here."
	}
}
```

`dashboard/src/locales/ar/finance.json`:

```json
{
	"nav": {
		"expenses": "المصروفات",
		"donations": "التبرعات"
	},
	"types": {
		"salaries": "رواتب",
		"rent": "إيجار",
		"marketing": "تسويق",
		"software": "برمجيات",
		"utilities": "مرافق",
		"supplies": "مستلزمات",
		"fees": "رسوم",
		"other": "أخرى"
	},
	"methods": {
		"cash": "نقدًا",
		"bank_transfer": "تحويل بنكي",
		"instapay": "إنستاباي",
		"vodafone_cash": "فودافون كاش",
		"western_union": "ويسترن يونيون",
		"zelle": "زيل",
		"venmo": "فينمو",
		"cashapp": "كاش آب",
		"other": "أخرى",
		"stripe": "سترايب",
		"paypal": "باي بال"
	},
	"statuses": {
		"pending": "قيد الانتظار",
		"completed": "مكتمل",
		"failed": "فشل",
		"refunded": "مسترد",
		"cancelled": "ملغي"
	},
	"source": {
		"generic": "مُسجَّل تلقائيًا",
		"payroll": {
			"payslip": "مُسجَّل من الرواتب"
		}
	},
	"fields": {
		"title": "العنوان",
		"type": "النوع",
		"amount": "المبلغ",
		"amountIn": "المبلغ ({{currency}})",
		"currency": "العملة",
		"spentOn": "التاريخ",
		"receivedOn": "تاريخ الاستلام",
		"notes": "ملاحظات",
		"method": "طريقة الدفع",
		"status": "الحالة",
		"transactionNumber": "رقم المعاملة",
		"donorName": "اسم المتبرع",
		"donorEmail": "بريد المتبرع",
		"number": "الرقم",
		"donor": "المتبرع",
		"actions": "إجراءات"
	},
	"list": {
		"from": "من",
		"to": "إلى",
		"anyType": "كل الأنواع",
		"anyCurrency": "كل العملات",
		"anyStatus": "كل الحالات",
		"anyMethod": "كل الطرق"
	},
	"expenses": {
		"add": "إضافة مصروف",
		"edit": "تعديل",
		"editFor": "تعديل {{title}}",
		"editTitle": "تعديل المصروف",
		"body": "ما أنفقته الأكاديمية، بعملة واحدة.",
		"save": "حفظ المصروف",
		"saved": "تم حفظ المصروف.",
		"delete": "حذف",
		"deleteTitle": "حذف هذا المصروف",
		"deleteBody": "سيُحذف من أرقام هذا الشهر. لا يمكن التراجع عن ذلك.",
		"deleted": "تم حذف المصروف.",
		"empty": "لا توجد مصروفات بعد.",
		"loadError": "تعذّر تحميل المصروفات.",
		"search": "ابحث بالعنوان",
		"entry": "المصدر",
		"filter": {
			"all": "كل القيود",
			"manual": "مُدخلة هنا",
			"posted": "مُسجّلة من النظام"
		}
	},
	"donations": {
		"add": "إضافة تبرع",
		"edit": "تعديل",
		"editFor": "تعديل {{number}}",
		"editTitle": "تعديل التبرع",
		"body": "هبة للأكاديمية. التبرعات ليست إيرادات.",
		"save": "حفظ التبرع",
		"saved": "تم حفظ التبرع.",
		"delete": "حذف",
		"deleteTitle": "حذف هذا التبرع",
		"deleteBody": "لا يمكن التراجع عن ذلك.",
		"deleted": "تم حذف التبرع.",
		"empty": "لا توجد تبرعات بعد.",
		"loadError": "تعذّر تحميل التبرعات.",
		"search": "ابحث بالرقم أو المتبرع أو رقم المعاملة"
	},
	"home": {
		"title": "المصروفات والتبرعات",
		"expenses": "مصروفات هذا الشهر",
		"noExpenses": "لا مصروفات بعد هذا الشهر.",
		"netProfit": "صافي ربح هذا الشهر",
		"noProfit": "لا إيرادات ولا مصروفات بعد هذا الشهر.",
		"donations": "تبرعات هذا الشهر",
		"noDonations": "لا تبرعات بعد هذا الشهر.",
		"loadError": "تعذّر تحميل أرقام هذا الشهر."
	},
	"errors": {
		"required": "املأ هذا الحقل.",
		"dateRequired": "اختر تاريخًا.",
		"tooLong": "النص طويل جدًا.",
		"email": "أدخل بريدًا إلكترونيًا صحيحًا، أو اتركه فارغًا.",
		"expense_posted": "سُجّل هذا المصروف من جزء آخر من النظام، فلا يمكن تعديله هنا."
	}
}
```

In `dashboard/src/features/identity/schemas.ts`, extend `FeatureCode`:

```ts
	| "export"
	// Phase B3, slice B3a.
	| "donations"
	| "expenses";
```

In `dashboard/src/features/shell/nav.ts`:
- add `HandHeart` and `TrendingDown` to the `lucide-react` import, in alphabetical order;
- under `// ── phase B3 ──`, add:

```ts
	// ── phase B3 ──
	// B3a: what the academy spends and is given.
	office(
		"/billing/expenses",
		"finance.nav.expenses",
		TrendingDown,
		"billing",
		"expense.view_any",
		"expenses",
	),
	office(
		"/billing/donations",
		"finance.nav.donations",
		HandHeart,
		"billing",
		"donation.view_any",
		"donations",
	),
```

- [ ] **Step 3: Run the tests**

Run: `npx pnpm@10 vitest run src/features/finance src/features/shell src/lib`
Expected: PASS, including the locale parity test, which keeps `ar` and `en` key-for-key equal.

- [ ] **Step 4: Format, type-check, commit**

```bash
cd dashboard
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint
git add src/features/finance src/locales/en/finance.json src/locales/ar/finance.json src/test/finance-fixtures.ts src/features/identity/schemas.ts src/features/shell/nav.ts src/features/shell/nav.test.ts
git commit -m "feat(finance): dashboard module, translations and nav

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 9: The Expenses page

**Files:**
- Create: `dashboard/src/features/finance/ExpenseDialog.tsx`, `ExpensesList.tsx`, `ExpensesList.test.tsx`, `dashboard/src/routes/_authed/billing.expenses.tsx`
- Modify: `dashboard/src/features/finance/index.ts`

**Interfaces:**
- Consumes (Task 8):
  - `financeApi`, `useExpenses`, `useFinanceMutation`, `expensesCsvUrl`;
  - `expenseFormSchema`, `EXPENSE_TYPES`;
  - `financeErrorText`, `useFinanceFieldError`, `PostedBadge`.

  It also uses billing's `Money`, `useAcademySettings`, `CURRENCIES`, `toMinor`/`toMajor` and `todayIn`/`formatDay`.
- Produces: `<ExpensesList />` and `<ExpenseDialog expense? />`, plus the route `/billing/expenses`, whose `staticData` is `{ permission: "expense.view_any", feature: "expenses" }`.

- [ ] **Step 1: Write the failing test**

`dashboard/src/features/finance/ExpensesList.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { staffMe } from "@/test/access-fixtures";
import { expenseRow } from "@/test/finance-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { financeApi } from "./api";
import { ExpensesList } from "./ExpensesList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		financeApi: {
			...actual.financeApi,
			expenses: vi.fn(),
			createExpense: vi.fn(),
			updateExpense: vi.fn(),
			deleteExpense: vi.fn(),
		},
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const posted = expenseRow({
	id: 82,
	title: "Salary — Bilal",
	type: "salaries",
	amount_minor: 120000,
	source: "payroll.payslip",
	source_id: 7,
	posted: true,
	created_by: null,
});

function lastParams() {
	return vi.mocked(financeApi.expenses).mock.calls.at(-1)?.[0];
}

function row(text: string) {
	return screen.getByRole("row", { name: new RegExp(text) });
}

describe("ExpensesList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ timezone: "Asia/Tokyo", default_currency: "EGP" }),
		);
		vi.mocked(financeApi.expenses).mockResolvedValue(
			page([expenseRow(), posted]),
		);
	});
	afterEach(async () => {
		vi.useRealTimers();
		await i18n.changeLanguage("en");
	});

	it("lists expenses; a posted one shows its source and can't be changed", async () => {
		renderWithRouter(<ExpensesList />);
		await screen.findByRole("table");
		const rent = row("Office rent");
		expect(within(rent).getByText("Rent")).toBeInTheDocument();
		expect(within(rent).getByText(/2,500\.00/)).toBeInTheDocument();
		expect(
			within(rent).getByRole("button", { name: "Edit Office rent" }),
		).toBeInTheDocument();
		expect(
			within(rent).getByRole("button", { name: "Delete" }),
		).toBeInTheDocument();
		const salary = row("Salary");
		expect(within(salary).getByText("Posted from payroll")).toBeInTheDocument();
		expect(within(salary).queryAllByRole("button")).toHaveLength(0);
	});

	it("names an unknown source generically", async () => {
		vi.mocked(financeApi.expenses).mockResolvedValue(
			page([expenseRow({ ...posted, source: "shop.order" })]),
		);
		renderWithRouter(<ExpensesList />);
		expect(await screen.findByText("Posted")).toBeInTheDocument();
	});

	it("filters by search, type, currency, entry and dates, from page 1", async () => {
		const user = userEvent.setup();
		renderWithRouter(<ExpensesList />);
		await screen.findByRole("table");
		await user.type(screen.getByRole("searchbox"), "rent");
		await waitFor(() => expect(lastParams()).toMatchObject({ q: "rent", page: 1 }));
		await user.selectOptions(screen.getByLabelText("Type"), "rent");
		await user.selectOptions(screen.getByLabelText("Currency"), "USD");
		await user.selectOptions(screen.getByLabelText("Entry"), "posted");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({
				type: "rent",
				currency: "USD",
				posted: "true",
			}),
		);
		await user.selectOptions(screen.getByLabelText("Entry"), "all");
		await waitFor(() => expect(lastParams()?.posted).toBeUndefined());
		await user.type(screen.getByLabelText("From"), "2026-06-01");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({ spent_from: "2026-06-01" }),
		);
	});

	it("adds one in the academy's currency, dated the academy's today", async () => {
		// 20:00 UTC on 1 July is already 2 July in the academy's Tokyo.
		vi.useFakeTimers({
			now: new Date("2026-07-01T20:00:00Z"),
			toFake: ["Date"],
		});
		vi.mocked(financeApi.createExpense).mockResolvedValue(expenseRow());
		const user = userEvent.setup();
		renderWithRouter(<ExpensesList />);
		await user.click(await screen.findByRole("button", { name: "Add expense" }));
		const dialog = screen.getByRole("dialog");
		await waitFor(() =>
			expect(within(dialog).getByLabelText(/^Date/)).toHaveValue("2026-07-02"),
		);
		expect(within(dialog).getByLabelText(/^Currency/)).toHaveValue("EGP");
		await user.click(within(dialog).getByRole("button", { name: "Save expense" }));
		// The title and the amount.
		expect(await within(dialog).findAllByText("Fill this in.")).toHaveLength(2);
		await user.type(within(dialog).getByLabelText(/^Title/), "Printer ink");
		await user.selectOptions(within(dialog).getByLabelText(/^Type/), "supplies");
		// Review focus 5: three decimals for EGP is refused, not rounded.
		await user.type(within(dialog).getByLabelText(/^Amount/), "12.345");
		await user.click(within(dialog).getByRole("button", { name: "Save expense" }));
		expect(
			await within(dialog).findByText(
				"Enter an amount above zero, like 150 or 150.50.",
			),
		).toBeInTheDocument();
		expect(financeApi.createExpense).not.toHaveBeenCalled();
		await user.clear(within(dialog).getByLabelText(/^Amount/));
		await user.type(within(dialog).getByLabelText(/^Amount/), "12.34");
		await user.click(within(dialog).getByRole("button", { name: "Save expense" }));
		await waitFor(() =>
			expect(financeApi.createExpense).toHaveBeenCalledWith({
				title: "Printer ink",
				type: "supplies",
				amount_minor: 1234,
				currency: "EGP",
				spent_on: "2026-07-02",
				notes: "",
			}),
		);
		expect(await screen.findByText("Expense saved.")).toBeInTheDocument();
	});

	it("edits one and puts the server's field error on its field", async () => {
		vi.mocked(financeApi.updateExpense).mockRejectedValue(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { spent_on: ["A date can't be in the future."] },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<ExpensesList />);
		await user.click(
			await screen.findByRole("button", { name: "Edit Office rent" }),
		);
		const dialog = screen.getByRole("dialog");
		const amount = within(dialog).getByLabelText(/^Amount/);
		expect(amount).toHaveValue("2500.00");
		await user.clear(amount);
		await user.type(amount, "2600");
		await user.click(within(dialog).getByRole("button", { name: "Save expense" }));
		expect(financeApi.updateExpense).toHaveBeenCalledWith({
			id: 81,
			title: "Office rent",
			type: "rent",
			amount_minor: 260000,
			currency: "EGP",
			spent_on: "2026-06-01",
			notes: "June",
		});
		expect(
			await within(dialog).findByText("A date can't be in the future."),
		).toBeInTheDocument();
	});

	it("deletes after confirming, and shows the posted refusal translated", async () => {
		vi.mocked(financeApi.deleteExpense).mockRejectedValueOnce(
			new AxiosError("Conflict", "409", undefined, undefined, {
				status: 409,
				data: { detail: "Posted.", code: "finance.expense_posted" },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<ExpensesList />);
		await user.click(
			within(await screen.findByRole("row", { name: /Office rent/ })).getByRole(
				"button",
				{ name: "Delete" },
			),
		);
		// `Confirm` labels its confirming button with the dialog's title.
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Delete this expense",
			}),
		);
		expect(financeApi.deleteExpense).toHaveBeenCalledWith(81);
		expect(
			await screen.findByText(
				"This expense was posted from another part of the system, so it can't be changed here.",
			),
		).toBeInTheDocument();
	});

	it("hides what a staff account may not do, and says when it's empty or failed", async () => {
		vi.mocked(financeApi.expenses).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(
			<CanProvider me={staffMe("expense.view_any")}>
				<ExpensesList />
			</CanProvider>,
		);
		expect(await screen.findByText("No expenses yet.")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Add expense" })).toBeNull();
		unmount();
		vi.mocked(financeApi.expenses).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<ExpensesList />);
		expect(
			await screen.findByText("The expenses could not be loaded."),
		).toBeInTheDocument();
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(<ExpensesList />);
		await screen.findByRole("table");
		expect(within(row("Office rent")).getByText("إيجار")).toBeInTheDocument();
		expect(screen.getByText("مُسجَّل من الرواتب")).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "إضافة مصروف" })).toBeInTheDocument();
	});
});
```

Run: `npx pnpm@10 vitest run src/features/finance/ExpensesList.test.tsx`
Expected: FAIL (`./ExpensesList` not found).

- [ ] **Step 2: Implement the dialog**

`dashboard/src/features/finance/ExpenseDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { CURRENCIES } from "@/lib/currencies";
import { applyServerErrors } from "@/lib/form-errors";
import { toMajor, toMinor } from "@/lib/money";
import { todayIn } from "@/lib/zoned-time";
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
	Select,
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { financeApi } from "./api";
import { useFinanceFieldError } from "./bits";
import { useFinanceMutation } from "./queries";
import {
	EXPENSE_TYPES,
	type Expense,
	type ExpenseFormValues,
	expenseFormSchema,
} from "./schemas";

/** The currencies a picker offers: the curated list, plus the academy's and
 * the row's own when they are not on it. */
export function currencyChoices(...extra: (string | undefined)[]): string[] {
	return [
		...new Set([
			...extra.filter((code): code is string => Boolean(code)),
			...CURRENCIES,
		]),
	];
}

/** Add an expense, or edit a manual one (B3a spec §6). The currency defaults
 * to the academy's and the date to its today. */
export function ExpenseDialog({ expense }: { expense?: Expense }) {
	const { t } = useTranslation();
	const fieldError = useFinanceFieldError();
	const [open, setOpen] = useState(false);
	const { data: academy } = useAcademySettings();
	const create = useFinanceMutation(financeApi.createExpense);
	const update = useFinanceMutation(financeApi.updateExpense);
	const {
		register,
		handleSubmit,
		setError,
		reset,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<ExpenseFormValues>({
		resolver: zodResolver(expenseFormSchema),
		values: {
			title: expense?.title ?? "",
			type: expense?.type ?? "other",
			amount: expense ? toMajor(expense.amount_minor, expense.currency) : "",
			currency: expense?.currency ?? academy?.default_currency ?? "",
			spent_on:
				expense?.spent_on ?? (academy ? todayIn(academy.timezone) : ""),
			notes: expense?.notes ?? "",
		},
	});
	const currency = watch("currency");

	async function onSubmit(values: ExpenseFormValues) {
		const body = {
			title: values.title.trim(),
			type: values.type,
			amount_minor: toMinor(values.amount, values.currency),
			currency: values.currency,
			spent_on: values.spent_on,
			notes: values.notes,
		};
		try {
			if (expense) {
				await update.mutateAsync({ id: expense.id, ...body });
			} else {
				await create.mutateAsync(body);
			}
			reset();
			setOpen(false);
			toast({ description: t("finance.expenses.saved"), variant: "success" });
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.amount_minor) {
				setError("amount", { message: parsed.fieldErrors.amount_minor });
			}
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button
					size="sm"
					variant={expense ? "outline" : "primary"}
					aria-label={
						expense
							? t("finance.expenses.editFor", { title: expense.title })
							: undefined
					}
				>
					{expense ? t("finance.expenses.edit") : t("finance.expenses.add")}
				</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>
					{expense ? t("finance.expenses.editTitle") : t("finance.expenses.add")}
				</DialogTitle>
				<DialogDescription>{t("finance.expenses.body")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id="expense-title"
						label={t("finance.fields.title")}
						error={fieldError(errors.title?.message)}
						required
					>
						<Input {...register("title")} />
					</Field>
					<div className="grid gap-4 sm:grid-cols-2">
						<Field
							id="expense-type"
							label={t("finance.fields.type")}
							error={fieldError(errors.type?.message)}
							required
						>
							<Select {...register("type")}>
								{EXPENSE_TYPES.map((type) => (
									<option key={type} value={type}>
										{t(`finance.types.${type}`)}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="expense-currency"
							label={t("finance.fields.currency")}
							error={fieldError(errors.currency?.message)}
							required
						>
							<Select dir="ltr" {...register("currency")}>
								{currencyChoices(
									academy?.default_currency,
									expense?.currency,
								).map((code) => (
									<option key={code} value={code}>
										{code}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="expense-amount"
							label={
								currency
									? t("finance.fields.amountIn", { currency })
									: t("finance.fields.amount")
							}
							error={fieldError(errors.amount?.message)}
							required
						>
							<Input inputMode="decimal" dir="ltr" {...register("amount")} />
						</Field>
						<Field
							id="expense-spent_on"
							label={t("finance.fields.spentOn")}
							error={fieldError(errors.spent_on?.message)}
							required
						>
							<Input type="date" dir="ltr" {...register("spent_on")} />
						</Field>
					</div>
					<Field
						id="expense-notes"
						label={t("finance.fields.notes")}
						error={fieldError(errors.notes?.message)}
					>
						<Textarea rows={2} {...register("notes")} />
					</Field>
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
							{t("finance.expenses.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

- [ ] **Step 3: Implement the list and the route**

`dashboard/src/features/finance/ExpensesList.tsx`:

```tsx
import { TrendingDown } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { ExportButton } from "@/components/ExportButton";
import { Pager } from "@/components/Pager";
import { Money } from "@/features/billing";
import { useCan } from "@/features/identity/permissions";
import type { QueryParams } from "@/lib/api";
import { CURRENCIES } from "@/lib/currencies";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	EmptyState,
	Input,
	Select,
	Spinner,
	toast,
} from "@/ui";
import { expensesCsvUrl, financeApi } from "./api";
import { financeErrorText, PostedBadge } from "./bits";
import { ExpenseDialog } from "./ExpenseDialog";
import { useExpenses, useFinanceMutation } from "./queries";
import { EXPENSE_TYPES } from "./schemas";

// The backend paginates at 25 rows a page (StandardPagination).
const PAGE_SIZE = 25;
// D2: the entry filter sends `posted` only when one kind is chosen.
const ENTRY = { all: undefined, manual: "false", posted: "true" } as const;
const COLUMNS = ["date", "title", "type", "amount", "notes", "actions"] as const;
const COLUMN_KEY = {
	date: "finance.fields.spentOn",
	title: "finance.fields.title",
	type: "finance.fields.type",
	amount: "finance.fields.amount",
	notes: "finance.fields.notes",
	actions: "finance.fields.actions",
} as const;

/** B3a spec §6 Expenses: search, type, currency, entry and date filters,
 * paging and CSV; add, and edit or delete the manual ones. A posted row
 * names its source and offers nothing (A-8). */
export function ExpensesList() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const [params, setParams] = useState<QueryParams>({ page: 1 });
	const { data, isPending, isError } = useExpenses(params);
	const remove = useFinanceMutation(financeApi.deleteExpense);
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const update = (patch: QueryParams) =>
		setParams({ ...params, page: 1, ...patch });
	const entry =
		(Object.keys(ENTRY) as (keyof typeof ENTRY)[]).find(
			(key) => ENTRY[key] === params.posted,
		) ?? "all";

	const date = (key: "spent_from" | "spent_to", label: string) => (
		<div className="flex flex-col gap-1">
			<label htmlFor={`expenses-${key}`} className="text-xs">
				{label}
			</label>
			<Input
				id={`expenses-${key}`}
				type="date"
				dir="ltr"
				className="w-auto"
				value={String(params[key] ?? "")}
				onChange={(e) => update({ [key]: e.target.value })}
			/>
		</div>
	);

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				<div className="min-w-48 flex-1">
					<label htmlFor="expenses-search" className="sr-only">
						{t("finance.expenses.search")}
					</label>
					<Input
						id="expenses-search"
						type="search"
						placeholder={t("finance.expenses.search")}
						value={String(params.q ?? "")}
						onChange={(e) => update({ q: e.target.value })}
					/>
				</div>
				<Select
					aria-label={t("finance.fields.type")}
					className="w-auto"
					value={String(params.type ?? "")}
					onChange={(e) => update({ type: e.target.value })}
				>
					<option value="">{t("finance.list.anyType")}</option>
					{EXPENSE_TYPES.map((type) => (
						<option key={type} value={type}>
							{t(`finance.types.${type}`)}
						</option>
					))}
				</Select>
				<Select
					aria-label={t("finance.fields.currency")}
					className="w-auto"
					dir="ltr"
					value={String(params.currency ?? "")}
					onChange={(e) => update({ currency: e.target.value })}
				>
					<option value="">{t("finance.list.anyCurrency")}</option>
					{CURRENCIES.map((code) => (
						<option key={code} value={code}>
							{code}
						</option>
					))}
				</Select>
				<Select
					aria-label={t("finance.expenses.entry")}
					className="w-auto"
					value={entry}
					onChange={(e) =>
						update({ posted: ENTRY[e.target.value as keyof typeof ENTRY] })
					}
				>
					{(Object.keys(ENTRY) as (keyof typeof ENTRY)[]).map((key) => (
						<option key={key} value={key}>
							{t(`finance.expenses.filter.${key}`)}
						</option>
					))}
				</Select>
				{date("spent_from", t("finance.list.from"))}
				{date("spent_to", t("finance.list.to"))}
				<ExportButton href={expensesCsvUrl(params)} />
				{can("expense.create") ? <ExpenseDialog /> : null}
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("finance.expenses.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState
							icon={TrendingDown}
							title={t("finance.expenses.empty")}
						/>
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{COLUMNS.map((key) => (
									<th
										key={key}
										scope="col"
										className="p-3 text-start font-medium"
									>
										{t(COLUMN_KEY[key])}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{rows.map((expense) => (
								<tr key={expense.id} className="border-t border-border">
									<td className="p-3">
										{formatDay(expense.spent_on, i18n.language)}
									</td>
									<td className="p-3">{expense.title}</td>
									<td className="p-3">{t(`finance.types.${expense.type}`)}</td>
									<td className="p-3">
										<Money
											minor={expense.amount_minor}
											currency={expense.currency}
										/>
									</td>
									<td className="p-3">{expense.notes}</td>
									<td className="p-3">
										{expense.posted ? (
											<PostedBadge source={expense.source} />
										) : (
											<div className="flex flex-wrap gap-2">
												{can("expense.update") ? (
													<ExpenseDialog expense={expense} />
												) : null}
												{can("expense.delete") ? (
													<Confirm
														action={t("finance.expenses.delete")}
														title={t("finance.expenses.deleteTitle")}
														body={t("finance.expenses.deleteBody")}
														onConfirm={() =>
															remove.mutate(expense.id, {
																onSuccess: () =>
																	toast({
																		description: t("finance.expenses.deleted"),
																		variant: "success",
																	}),
																onError: (error) =>
																	toast({
																		description: financeErrorText(error, t),
																		variant: "destructive",
																	}),
															})
														}
													/>
												) : null}
											</div>
										)}
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			<Pager
				page={page}
				pages={pages}
				onChange={(next) => setParams({ ...params, page: next })}
			/>
		</div>
	);
}
```

`dashboard/src/routes/_authed/billing.expenses.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { ExpensesList } from "@/features/finance";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/billing/expenses")({
	staticData: { permission: "expense.view_any", feature: "expenses" },
	component: function ExpensesRoute() {
		const { t } = useTranslation();
		usePageTitle(t("finance.nav.expenses"));
		return (
			<>
				<PageHeader title={t("finance.nav.expenses")} />
				<ExpensesList />
			</>
		);
	},
});
```

In `dashboard/src/features/finance/index.ts`, add:

```ts
export { ExpenseDialog } from "./ExpenseDialog";
export { ExpensesList } from "./ExpensesList";
```

- [ ] **Step 4: Run the tests**

Run: `npx pnpm@10 vitest run src/features/finance`
Expected: PASS.

- [ ] **Step 5: Format, type-check, commit**

```bash
cd dashboard
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint
git add src/features/finance src/routes/_authed/billing.expenses.tsx src/routeTree.gen.ts
git commit -m "feat(finance): the Expenses page

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: The Donations page

**Files:**
- Create: `dashboard/src/features/finance/DonationDialog.tsx`, `DonationsList.tsx`, `DonationsList.test.tsx`, `dashboard/src/routes/_authed/billing.donations.tsx`
- Modify: `dashboard/src/features/finance/index.ts`, `dashboard/src/routes/_authed/billing.index.tsx`

**Interfaces:**
- Consumes: Task 8's module and `currencyChoices` (exported by `ExpenseDialog.tsx`, Task 9).
- Produces: `<DonationsList />` and `<DonationDialog donation? />`, plus the route `/billing/donations`, whose `staticData` is `{ permission: "donation.view_any", feature: "donations" }`.

- [ ] **Step 1: Write the failing test**

`dashboard/src/features/finance/DonationsList.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { staffMe } from "@/test/access-fixtures";
import { donationRow } from "@/test/finance-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { financeApi } from "./api";
import { DonationsList } from "./DonationsList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		financeApi: {
			...actual.financeApi,
			donations: vi.fn(),
			createDonation: vi.fn(),
			updateDonation: vi.fn(),
			deleteDonation: vi.fn(),
		},
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

function lastParams() {
	return vi.mocked(financeApi.donations).mock.calls.at(-1)?.[0];
}

describe("DonationsList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ default_currency: "USD" }),
		);
		vi.mocked(financeApi.donations).mockResolvedValue(
			page([
				donationRow(),
				donationRow({
					id: 92,
					number: "DON-000002",
					status: "pending",
					method: "paypal",
					donor_name: "",
					amount_minor: 700,
					currency: "USD",
				}),
			]),
		);
	});
	afterEach(async () => {
		vi.useRealTimers();
		await i18n.changeLanguage("en");
	});

	it("lists donations with their number, donor, method and status", async () => {
		renderWithRouter(<DonationsList />);
		await screen.findByRole("table");
		const first = screen.getByRole("row", { name: /DON-000001/ });
		expect(within(first).getByText("Abu Khalid")).toBeInTheDocument();
		expect(within(first).getByText("Bank transfer")).toBeInTheDocument();
		expect(within(first).getByText("Completed")).toBeInTheDocument();
		expect(within(first).getByText(/500\.00/)).toBeInTheDocument();
		const second = screen.getByRole("row", { name: /DON-000002/ });
		expect(within(second).getByText("PayPal")).toBeInTheDocument();
		expect(within(second).getByText("Pending")).toBeInTheDocument();
		expect(within(second).getByText("$7.00")).toBeInTheDocument();
	});

	it("filters by search, status, method, currency and dates", async () => {
		const user = userEvent.setup();
		renderWithRouter(<DonationsList />);
		await screen.findByRole("table");
		await user.type(screen.getByRole("searchbox"), "khalid");
		await user.selectOptions(screen.getByLabelText("Status"), "pending");
		await user.selectOptions(screen.getByLabelText("Method"), "paypal");
		await user.selectOptions(screen.getByLabelText("Currency"), "USD");
		await user.type(screen.getByLabelText("To"), "2026-06-30");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({
				q: "khalid",
				status: "pending",
				method: "paypal",
				currency: "USD",
				received_to: "2026-06-30",
				page: 1,
			}),
		);
	});

	it("records one with its donor, dated today and completed by default", async () => {
		vi.useFakeTimers({
			now: new Date("2026-06-03T10:00:00Z"),
			toFake: ["Date"],
		});
		vi.mocked(financeApi.createDonation).mockResolvedValue(donationRow());
		const user = userEvent.setup();
		renderWithRouter(<DonationsList />);
		await user.click(await screen.findByRole("button", { name: "Add donation" }));
		const dialog = screen.getByRole("dialog");
		await waitFor(() =>
			expect(within(dialog).getByLabelText(/^Received on/)).toHaveValue(
				"2026-06-03",
			),
		);
		expect(within(dialog).getByLabelText(/^Status/)).toHaveValue("completed");
		await user.type(within(dialog).getByLabelText(/^Amount/), "25");
		await user.selectOptions(within(dialog).getByLabelText(/^Method/), "stripe");
		await user.type(within(dialog).getByLabelText(/^Donor email/), "nope");
		await user.click(within(dialog).getByRole("button", { name: "Save donation" }));
		expect(
			await within(dialog).findByText(
				"Enter a valid email address, or leave it empty.",
			),
		).toBeInTheDocument();
		await user.clear(within(dialog).getByLabelText(/^Donor email/));
		await user.type(within(dialog).getByLabelText(/^Donor name/), "Umm Sara");
		await user.type(within(dialog).getByLabelText(/^Transaction number/), "pi_1");
		await user.click(within(dialog).getByRole("button", { name: "Save donation" }));
		await waitFor(() =>
			expect(financeApi.createDonation).toHaveBeenCalledWith({
				amount_minor: 2500,
				currency: "USD",
				method: "stripe",
				status: "completed",
				received_on: "2026-06-03",
				transaction_number: "pi_1",
				donor_name: "Umm Sara",
				donor_email: "",
				notes: "",
			}),
		);
	});

	it("edits one's status", async () => {
		vi.mocked(financeApi.updateDonation).mockResolvedValue(donationRow());
		const user = userEvent.setup();
		renderWithRouter(<DonationsList />);
		await user.click(
			await screen.findByRole("button", { name: "Edit DON-000001" }),
		);
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(within(dialog).getByLabelText(/^Status/), "refunded");
		await user.click(within(dialog).getByRole("button", { name: "Save donation" }));
		await waitFor(() =>
			expect(financeApi.updateDonation).toHaveBeenCalledWith(
				expect.objectContaining({ id: 91, status: "refunded", amount_minor: 50000 }),
			),
		);
	});

	it("deletes one after confirming", async () => {
		vi.mocked(financeApi.deleteDonation).mockResolvedValue(undefined);
		const user = userEvent.setup();
		renderWithRouter(<DonationsList />);
		const first = await screen.findByRole("row", { name: /DON-000001/ });
		await user.click(within(first).getByRole("button", { name: "Delete" }));
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Delete this donation",
			}),
		);
		await waitFor(() => expect(financeApi.deleteDonation).toHaveBeenCalledWith(91));
		expect(await screen.findByText("Donation deleted.")).toBeInTheDocument();
	});

	it("hides what a staff account may not do, and says when it's empty or failed", async () => {
		vi.mocked(financeApi.donations).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(
			<CanProvider me={staffMe("donation.view_any")}>
				<DonationsList />
			</CanProvider>,
		);
		expect(await screen.findByText("No donations yet.")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Add donation" })).toBeNull();
		unmount();
		vi.mocked(financeApi.donations).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<DonationsList />);
		expect(
			await screen.findByText("The donations could not be loaded."),
		).toBeInTheDocument();
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(<DonationsList />);
		await screen.findByRole("table");
		expect(screen.getByText("تحويل بنكي")).toBeInTheDocument();
		expect(screen.getByText("قيد الانتظار")).toBeInTheDocument();
	});
});
```

Run: `npx pnpm@10 vitest run src/features/finance/DonationsList.test.tsx`
Expected: FAIL (`./DonationsList` not found).

- [ ] **Step 2: Implement the dialog**

`dashboard/src/features/finance/DonationDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { applyServerErrors } from "@/lib/form-errors";
import { toMajor, toMinor } from "@/lib/money";
import { todayIn } from "@/lib/zoned-time";
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
	Select,
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { financeApi } from "./api";
import { useFinanceFieldError } from "./bits";
import { currencyChoices } from "./ExpenseDialog";
import { useFinanceMutation } from "./queries";
import {
	DONATION_METHODS,
	DONATION_STATUSES,
	type Donation,
	type DonationFormValues,
	donationFormSchema,
} from "./schemas";

/** Record a donation, or edit one (B3a spec §6). The number is the
 * server's; the status defaults to completed, the date to today. */
export function DonationDialog({ donation }: { donation?: Donation }) {
	const { t } = useTranslation();
	const fieldError = useFinanceFieldError();
	const [open, setOpen] = useState(false);
	const { data: academy } = useAcademySettings();
	const create = useFinanceMutation(financeApi.createDonation);
	const update = useFinanceMutation(financeApi.updateDonation);
	const {
		register,
		handleSubmit,
		setError,
		reset,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<DonationFormValues>({
		resolver: zodResolver(donationFormSchema),
		values: {
			amount: donation ? toMajor(donation.amount_minor, donation.currency) : "",
			currency: donation?.currency ?? academy?.default_currency ?? "",
			method: donation?.method ?? "cash",
			status: donation?.status ?? "completed",
			received_on:
				donation?.received_on ?? (academy ? todayIn(academy.timezone) : ""),
			transaction_number: donation?.transaction_number ?? "",
			donor_name: donation?.donor_name ?? "",
			donor_email: donation?.donor_email ?? "",
			notes: donation?.notes ?? "",
		},
	});
	const currency = watch("currency");

	async function onSubmit(values: DonationFormValues) {
		const body = {
			amount_minor: toMinor(values.amount, values.currency),
			currency: values.currency,
			method: values.method,
			status: values.status,
			received_on: values.received_on,
			transaction_number: values.transaction_number.trim(),
			donor_name: values.donor_name.trim(),
			donor_email: values.donor_email.trim(),
			notes: values.notes,
		};
		try {
			if (donation) {
				await update.mutateAsync({ id: donation.id, ...body });
			} else {
				await create.mutateAsync(body);
			}
			reset();
			setOpen(false);
			toast({ description: t("finance.donations.saved"), variant: "success" });
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.amount_minor) {
				setError("amount", { message: parsed.fieldErrors.amount_minor });
			}
		}
	}

	const text = (
		name: "transaction_number" | "donor_name" | "donor_email",
		label: string,
	) => (
		<Field
			id={`donation-${name}`}
			label={label}
			error={fieldError(errors[name]?.message)}
		>
			<Input
				dir={name === "donor_name" ? undefined : "ltr"}
				{...register(name)}
			/>
		</Field>
	);

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button
					size="sm"
					variant={donation ? "outline" : "primary"}
					aria-label={
						donation
							? t("finance.donations.editFor", { number: donation.number })
							: undefined
					}
				>
					{donation ? t("finance.donations.edit") : t("finance.donations.add")}
				</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>
					{donation
						? t("finance.donations.editTitle")
						: t("finance.donations.add")}
				</DialogTitle>
				<DialogDescription>{t("finance.donations.body")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<div className="grid gap-4 sm:grid-cols-2">
						<Field
							id="donation-currency"
							label={t("finance.fields.currency")}
							error={fieldError(errors.currency?.message)}
							required
						>
							<Select dir="ltr" {...register("currency")}>
								{currencyChoices(
									academy?.default_currency,
									donation?.currency,
								).map((code) => (
									<option key={code} value={code}>
										{code}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="donation-amount"
							label={
								currency
									? t("finance.fields.amountIn", { currency })
									: t("finance.fields.amount")
							}
							error={fieldError(errors.amount?.message)}
							required
						>
							<Input inputMode="decimal" dir="ltr" {...register("amount")} />
						</Field>
						<Field
							id="donation-method"
							label={t("finance.fields.method")}
							error={fieldError(errors.method?.message)}
							required
						>
							<Select {...register("method")}>
								{DONATION_METHODS.map((method) => (
									<option key={method} value={method}>
										{t(`finance.methods.${method}`)}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="donation-status"
							label={t("finance.fields.status")}
							error={fieldError(errors.status?.message)}
							required
						>
							<Select {...register("status")}>
								{DONATION_STATUSES.map((status) => (
									<option key={status} value={status}>
										{t(`finance.statuses.${status}`)}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="donation-received_on"
							label={t("finance.fields.receivedOn")}
							error={fieldError(errors.received_on?.message)}
							required
						>
							<Input type="date" dir="ltr" {...register("received_on")} />
						</Field>
						{text("transaction_number", t("finance.fields.transactionNumber"))}
						{text("donor_name", t("finance.fields.donorName"))}
						{text("donor_email", t("finance.fields.donorEmail"))}
					</div>
					<Field
						id="donation-notes"
						label={t("finance.fields.notes")}
						error={fieldError(errors.notes?.message)}
					>
						<Textarea rows={2} {...register("notes")} />
					</Field>
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
							{t("finance.donations.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

- [ ] **Step 3: Implement the list and the route**

`dashboard/src/features/finance/DonationsList.tsx`:

```tsx
import { HandHeart } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { ExportButton } from "@/components/ExportButton";
import { Pager } from "@/components/Pager";
import { Money } from "@/features/billing";
import { useCan } from "@/features/identity/permissions";
import type { QueryParams } from "@/lib/api";
import { CURRENCIES } from "@/lib/currencies";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	EmptyState,
	Input,
	Select,
	Spinner,
	toast,
} from "@/ui";
import { donationsCsvUrl, financeApi } from "./api";
import { financeErrorText } from "./bits";
import { DonationDialog } from "./DonationDialog";
import { useDonations, useFinanceMutation } from "./queries";
import { DONATION_METHODS, DONATION_STATUSES } from "./schemas";

// The backend paginates at 25 rows a page (StandardPagination).
const PAGE_SIZE = 25;
const COLUMN_KEYS = [
	"finance.fields.number",
	"finance.fields.receivedOn",
	"finance.fields.donor",
	"finance.fields.amount",
	"finance.fields.method",
	"finance.fields.status",
	"finance.fields.actions",
] as const;

/** B3a spec §6 Donations: search, status, method, currency and date
 * filters, paging and CSV; record, edit and delete. */
export function DonationsList() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const [params, setParams] = useState<QueryParams>({ page: 1 });
	const { data, isPending, isError } = useDonations(params);
	const remove = useFinanceMutation(financeApi.deleteDonation);
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const update = (patch: QueryParams) =>
		setParams({ ...params, page: 1, ...patch });

	const choose = (
		key: "status" | "method" | "currency",
		label: string,
		any: string,
		options: readonly { value: string; text: string }[],
	) => (
		<Select
			aria-label={label}
			className="w-auto"
			value={String(params[key] ?? "")}
			onChange={(e) => update({ [key]: e.target.value })}
		>
			<option value="">{any}</option>
			{options.map((option) => (
				<option key={option.value} value={option.value}>
					{option.text}
				</option>
			))}
		</Select>
	);
	const date = (key: "received_from" | "received_to", label: string) => (
		<div className="flex flex-col gap-1">
			<label htmlFor={`donations-${key}`} className="text-xs">
				{label}
			</label>
			<Input
				id={`donations-${key}`}
				type="date"
				dir="ltr"
				className="w-auto"
				value={String(params[key] ?? "")}
				onChange={(e) => update({ [key]: e.target.value })}
			/>
		</div>
	);

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				<div className="min-w-48 flex-1">
					<label htmlFor="donations-search" className="sr-only">
						{t("finance.donations.search")}
					</label>
					<Input
						id="donations-search"
						type="search"
						placeholder={t("finance.donations.search")}
						value={String(params.q ?? "")}
						onChange={(e) => update({ q: e.target.value })}
					/>
				</div>
				{choose(
					"status",
					t("finance.fields.status"),
					t("finance.list.anyStatus"),
					DONATION_STATUSES.map((value) => ({
						value,
						text: t(`finance.statuses.${value}`),
					})),
				)}
				{choose(
					"method",
					t("finance.fields.method"),
					t("finance.list.anyMethod"),
					DONATION_METHODS.map((value) => ({
						value,
						text: t(`finance.methods.${value}`),
					})),
				)}
				{choose(
					"currency",
					t("finance.fields.currency"),
					t("finance.list.anyCurrency"),
					CURRENCIES.map((value) => ({ value, text: value })),
				)}
				{date("received_from", t("finance.list.from"))}
				{date("received_to", t("finance.list.to"))}
				<ExportButton href={donationsCsvUrl(params)} />
				{can("donation.create") ? <DonationDialog /> : null}
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("finance.donations.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={HandHeart} title={t("finance.donations.empty")} />
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{COLUMN_KEYS.map((key) => (
									<th
										key={key}
										scope="col"
										className="p-3 text-start font-medium"
									>
										{t(key)}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{rows.map((donation) => (
								<tr key={donation.id} className="border-t border-border">
									<td className="p-3" dir="ltr">
										{donation.number}
									</td>
									<td className="p-3">
										{formatDay(donation.received_on, i18n.language)}
									</td>
									<td className="p-3">{donation.donor_name}</td>
									<td className="p-3">
										<Money
											minor={donation.amount_minor}
											currency={donation.currency}
										/>
									</td>
									<td className="p-3">
										{t(`finance.methods.${donation.method}`)}
									</td>
									<td className="p-3">
										{t(`finance.statuses.${donation.status}`)}
									</td>
									<td className="p-3">
										<div className="flex flex-wrap gap-2">
											{can("donation.update") ? (
												<DonationDialog donation={donation} />
											) : null}
											{can("donation.delete") ? (
												<Confirm
													action={t("finance.donations.delete")}
													title={t("finance.donations.deleteTitle")}
													body={t("finance.donations.deleteBody")}
													onConfirm={() =>
														remove.mutate(donation.id, {
															onSuccess: () =>
																toast({
																	description: t("finance.donations.deleted"),
																	variant: "success",
																}),
															onError: (error) =>
																toast({
																	description: financeErrorText(error, t),
																	variant: "destructive",
																}),
														})
													}
												/>
											) : null}
										</div>
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			<Pager
				page={page}
				pages={pages}
				onChange={(next) => setParams({ ...params, page: next })}
			/>
		</div>
	);
}
```

`dashboard/src/routes/_authed/billing.donations.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { DonationsList } from "@/features/finance";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/billing/donations")({
	staticData: { permission: "donation.view_any", feature: "donations" },
	component: function DonationsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("finance.nav.donations"));
		return (
			<>
				<PageHeader title={t("finance.nav.donations")} />
				<DonationsList />
			</>
		);
	},
});
```

Now that `/billing/expenses` and `/billing/donations` exist, point the `/billing` index at the first page the user may see (spec §6):

`dashboard/src/routes/_authed/billing.index.tsx`:

```tsx
import { createFileRoute, redirect } from "@tanstack/react-router";
import { billingLanding } from "@/features/finance";
import { meQueryOptions } from "@/features/identity/queries";

// B3a spec §6: the first billing page the user may see (invoices,
// expenses, donations); home when there is none.
export const Route = createFileRoute("/_authed/billing/")({
	beforeLoad: async ({ context }) => {
		const me = await context.queryClient.ensureQueryData(meQueryOptions);
		throw redirect({ to: billingLanding(me) });
	},
});
```

In `dashboard/src/features/finance/index.ts`, add:

```ts
export { DonationDialog } from "./DonationDialog";
export { DonationsList } from "./DonationsList";
```

- [ ] **Step 4: Run the tests**

Run: `npx pnpm@10 vitest run src/features/finance`
Expected: PASS.

- [ ] **Step 5: Format, type-check, commit**

```bash
cd dashboard
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint
git add src/features/finance src/routes/_authed/billing.donations.tsx src/routes/_authed/billing.index.tsx src/routeTree.gen.ts
git commit -m "feat(finance): the Donations page

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 11: The home card

**Files:**
- Create: `dashboard/src/features/finance/FinanceSummaryCard.tsx`, `FinanceSummaryCard.test.tsx`
- Modify:
  - `dashboard/src/features/finance/index.ts`;
  - `dashboard/src/routes/_authed/index.tsx` (one import and one rendered element);
  - `dashboard/src/routes/_authed/index.test.tsx`.

**Interfaces:**
- Consumes: `useFinanceSummary`, `useDonationsSummary` (Task 8), and billing's `Money`.
- Produces: `<FinanceSummaryCard expenses={boolean} donations={boolean} />`, which renders nothing when both are false (D7).

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/finance/FinanceSummaryCard.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { donationsSummary, financeSummary } from "@/test/finance-fixtures";
import { renderWithRouter } from "@/test/render";
import { financeApi } from "./api";
import { FinanceSummaryCard } from "./FinanceSummaryCard";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		financeApi: {
			...actual.financeApi,
			summary: vi.fn(),
			donationsSummary: vi.fn(),
		},
	};
});

describe("FinanceSummaryCard", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(financeApi.summary).mockResolvedValue(financeSummary());
		vi.mocked(financeApi.donationsSummary).mockResolvedValue(donationsSummary());
	});

	it("shows expenses, net profit (a loss in the danger tone) and donations per currency", async () => {
		renderWithRouter(<FinanceSummaryCard expenses donations />);
		expect(
			await screen.findByRole("heading", { name: "Expenses this month" }),
		).toBeInTheDocument();
		expect(await screen.findByText(/3,650\.00/)).toBeInTheDocument();
		const loss = screen.getByText(/-?1,650\.00/);
		expect(loss.closest("li")).toHaveClass("text-destructive");
		expect(screen.getByText("$40.00").closest("li")).not.toHaveClass(
			"text-destructive",
		);
		expect(await screen.findByText(/750\.00/)).toBeInTheDocument();
	});

	it("asks only for what is switched on, and renders nothing with both off", async () => {
		const { unmount } = renderWithRouter(
			<FinanceSummaryCard expenses={false} donations />,
		);
		expect(
			await screen.findByRole("heading", { name: "Donations this month" }),
		).toBeInTheDocument();
		expect(screen.queryByText("Expenses this month")).toBeNull();
		expect(financeApi.summary).not.toHaveBeenCalled();
		unmount();
		vi.clearAllMocks();
		const { container } = renderWithRouter(
			<FinanceSummaryCard expenses={false} donations={false} />,
		);
		expect(container.querySelector('[data-slot="card"]')).toBeNull();
		expect(financeApi.summary).not.toHaveBeenCalled();
		expect(financeApi.donationsSummary).not.toHaveBeenCalled();
	});

	it("hides net profit while invoices are off, and says when there is nothing yet", async () => {
		vi.mocked(financeApi.summary).mockResolvedValue(
			financeSummary({ expenses_this_month: [], net_profit_this_month: null }),
		);
		vi.mocked(financeApi.donationsSummary).mockResolvedValue(
			donationsSummary({ donations_this_month: [] }),
		);
		renderWithRouter(<FinanceSummaryCard expenses donations />);
		expect(
			await screen.findByText("No expenses yet this month."),
		).toBeInTheDocument();
		expect(screen.queryByText("Net profit this month")).toBeNull();
		expect(
			await screen.findByText("No donations yet this month."),
		).toBeInTheDocument();
	});

	it("says when the figures can't load", async () => {
		vi.mocked(financeApi.summary).mockRejectedValue(new Error("offline"));
		renderWithRouter(<FinanceSummaryCard expenses donations={false} />);
		expect(
			await screen.findByText("Couldn't load this month's figures."),
		).toBeInTheDocument();
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		try {
			renderWithRouter(<FinanceSummaryCard expenses donations />);
			expect(
				await screen.findByRole("heading", { name: "صافي ربح هذا الشهر" }),
			).toBeInTheDocument();
		} finally {
			await i18n.changeLanguage("en");
		}
	});
});
```

In `dashboard/src/routes/_authed/index.test.tsx`:
- add the mock below, next to the billing one;
- in the existing `beforeEach`, add the mocked resolves shown after it;
- add the import `import { donationsSummary, financeSummary } from "@/test/finance-fixtures";`.

```tsx
vi.mock("@/features/finance/api", async (orig) => {
	const actual = await orig<typeof import("@/features/finance/api")>();
	return {
		...actual,
		financeApi: {
			...actual.financeApi,
			summary: vi.fn(),
			donationsSummary: vi.fn(),
		},
	};
});
```

```tsx
		vi.mocked(financeApi.summary).mockResolvedValue(financeSummary());
		vi.mocked(financeApi.donationsSummary).mockResolvedValue(donationsSummary());
```

Then add these tests:

```tsx
	it("shows an admin the finance card for the finance features that are on", async () => {
		renderHome({
			...student,
			role: "admin",
			profiles: [],
			features: ["invoices", "expenses"],
		});
		expect(
			await screen.findByRole("heading", { name: "Expenses this month" }),
		).toBeInTheDocument();
		expect(screen.queryByText("Donations this month")).toBeNull();
		expect(financeApi.donationsSummary).not.toHaveBeenCalled();
	});

	it("shows no finance card without the widget's code or with both features off", async () => {
		renderHome(staffMe("expense.view_any"));
		await screen.findByRole("heading", { level: 1 });
		expect(financeApi.summary).not.toHaveBeenCalled();
		renderHome({
			...student,
			role: "admin",
			profiles: [],
			features: ["invoices"],
		});
		await screen.findAllByRole("heading", { level: 1 });
		expect(screen.queryByText("Expenses this month")).toBeNull();
		expect(financeApi.summary).not.toHaveBeenCalled();
	});
```

and import `financeApi` from `@/features/finance/api` there (`PageHeader` renders the greeting as the page's `h1`; `Card` carries `data-slot="card"`).

Run: `npx pnpm@10 vitest run src/features/finance/FinanceSummaryCard.test.tsx src/routes/_authed/index.test.tsx`
Expected: FAIL (`./FinanceSummaryCard` not found).

- [ ] **Step 2: Implement**

`dashboard/src/features/finance/FinanceSummaryCard.tsx`:

```tsx
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import { cn } from "@/lib/cn";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
} from "@/ui";
import { useDonationsSummary, useFinanceSummary } from "./queries";
import type { MoneyLine } from "./schemas";

function Lines({
	title,
	lines,
	empty,
}: {
	title: string;
	lines: MoneyLine[];
	empty: string;
}) {
	return (
		<section className="flex flex-col gap-2">
			<h3 className="text-sm text-muted-foreground">{title}</h3>
			{lines.length === 0 ? (
				<p className="text-sm">{empty}</p>
			) : (
				<ul className="flex flex-col gap-1 text-lg font-semibold">
					{lines.map((line) => (
						<li
							key={line.currency}
							className={cn(line.amount_minor < 0 && "text-destructive")}
						>
							<Money minor={line.amount_minor} currency={line.currency} />
						</li>
					))}
				</ul>
			)}
		</section>
	);
}

/** B3a spec §6 admin home: this academy month's expenses and net profit per
 * currency while `expenses` is on (net profit only while invoices are,
 * A-7), and its completed donations while `donations` is on. Never summed
 * across currencies. Nothing at all with both off (plan D7). */
export function FinanceSummaryCard({
	expenses,
	donations,
}: {
	expenses: boolean;
	donations: boolean;
}) {
	const { t } = useTranslation();
	const money = useFinanceSummary({ enabled: expenses });
	const gifts = useDonationsSummary({ enabled: donations });
	if (!expenses && !donations) return null;
	let body: ReactNode;
	if ((expenses && money.isError) || (donations && gifts.isError)) {
		body = (
			<Alert variant="destructive">
				<AlertDescription>{t("finance.home.loadError")}</AlertDescription>
			</Alert>
		);
	} else if ((expenses && !money.data) || (donations && !gifts.data)) {
		body = <Spinner />;
	} else {
		body = (
			<div className="grid gap-6 sm:grid-cols-3">
				{expenses && money.data ? (
					<>
						<Lines
							title={t("finance.home.expenses")}
							lines={money.data.expenses_this_month}
							empty={t("finance.home.noExpenses")}
						/>
						{money.data.net_profit_this_month ? (
							<Lines
								title={t("finance.home.netProfit")}
								lines={money.data.net_profit_this_month}
								empty={t("finance.home.noProfit")}
							/>
						) : null}
					</>
				) : null}
				{donations && gifts.data ? (
					<Lines
						title={t("finance.home.donations")}
						lines={gifts.data.donations_this_month}
						empty={t("finance.home.noDonations")}
					/>
				) : null}
			</div>
		);
	}
	return (
		<Card className="mb-6">
			<CardHeader className="border-b border-border">
				<CardTitle>{t("finance.home.title")}</CardTitle>
			</CardHeader>
			<CardContent>{body}</CardContent>
		</Card>
	);
}
```

In `dashboard/src/features/finance/index.ts`, add `export { FinanceSummaryCard } from "./FinanceSummaryCard";`.

In `dashboard/src/routes/_authed/index.tsx`:
- add `import { FinanceSummaryCard } from "@/features/finance";`;
- right after the `BillingSummaryCard` expression, add:

```tsx
			{/* Phase B3 (B3a, plan D7): expenses, net profit and donations. */}
			{can(me, "widget.revenue_stats") ? (
				<FinanceSummaryCard
					expenses={hasFeature(me, "expenses")}
					donations={hasFeature(me, "donations")}
				/>
			) : null}
```

- [ ] **Step 3: Run the tests**

Run: `npx pnpm@10 vitest run src/features/finance src/routes`
Expected: PASS.

- [ ] **Step 4: The dashboard gate**

Run: `npx pnpm@10 exec biome check --write src e2e && npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass. Lines and statements must be ≥ 80; branches and functions ≥ 70.

- [ ] **Step 5: Commit**

```bash
cd dashboard
git add src/features/finance src/routes/_authed/index.tsx src/routes/_authed/index.test.tsx
git commit -m "feat(finance): expenses, net profit and donations on the admin home

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: The journey through Caddy

**Files:**
- Create: `dashboard/e2e/b3-finance.spec.ts`

**Interfaces:**
- Consumes: the stack (`just dev-backend`), `set_features` through `e2e/manage.ts`, and the routes and pages of Tasks 6–11.

- [ ] **Step 1: Write the journey**

`dashboard/e2e/b3-finance.spec.ts`:

```ts
import { expect, type Page, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { manage } from "./manage";

type Line = { currency: string; amount_minor: number };

/** This month's EGP figure from a summary line list (0 when absent). */
const egp = (lines: Line[] | null) =>
	lines?.find((line) => line.currency === "EGP")?.amount_minor ?? 0;

const money = (minor: number) =>
	new Intl.NumberFormat("en", { style: "currency", currency: "EGP" }).format(
		minor / 100,
	);

async function summaries(page: Page) {
	const base = `${DEMO_URL}/api/v1/finance`;
	const finance = await (await page.request.get(`${base}/summary/`)).json();
	const gifts = await (
		await page.request.get(`${base}/donations/summary/`)
	).json();
	return {
		expenses: egp(finance.expenses_this_month),
		profit: egp(finance.net_profit_this_month),
		donations: egp(gifts.donations_this_month),
	};
}

// B3a spec §8: Etqan switches expenses and donations on for demo (so the
// journey does not depend on the seed); the admin records an expense and a
// donation; the home shows the new expense, net profit and donation totals.
// Totals are read before and after, so earlier runs' rows don't matter.
test("the admin records an expense and a donation, and the home adds them up", async ({
	page,
}) => {
	manage("set_features", "demo", "--on", "expenses", "donations");
	const stamp = Date.now();
	const title = `E2E rent ${stamp}`;
	const donor = `E2E donor ${stamp}`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	const before = await summaries(page);

	// 1. An expense of 123.45 EGP, today
	await page.goto(`${DEMO_URL}/app/billing/expenses`);
	await page.getByRole("button", { name: "Add expense" }).click();
	const expense = page.getByRole("dialog");
	await expense.getByLabel(/^Title/).fill(title);
	await expense.getByLabel(/^Type/).selectOption("rent");
	await expense.getByLabel(/^Currency/).selectOption("EGP");
	await expense.getByLabel(/^Amount/).fill("123.45");
	await expense.getByRole("button", { name: "Save expense" }).click();
	await expect(page.getByRole("row", { name: new RegExp(title) })).toContainText(
		"123.45",
	);

	// 2. A completed donation of 50 EGP, today
	await page.goto(`${DEMO_URL}/app/billing/donations`);
	await page.getByRole("button", { name: "Add donation" }).click();
	const donation = page.getByRole("dialog");
	await donation.getByLabel(/^Currency/).selectOption("EGP");
	await donation.getByLabel(/^Amount/).fill("50");
	await donation.getByLabel(/^Method/).selectOption("cash");
	await donation.getByLabel(/^Donor name/).fill(donor);
	await donation.getByRole("button", { name: "Save donation" }).click();
	await expect(page.getByRole("row", { name: new RegExp(donor) })).toContainText(
		"Completed",
	);

	// 3. The home adds them up
	const after = await summaries(page);
	expect(after.expenses - before.expenses).toBe(12345);
	expect(after.profit - before.profit).toBe(-12345);
	expect(after.donations - before.donations).toBe(5000);
	await page.goto(`${DEMO_URL}/app/`);
	await expect(
		page.getByRole("heading", { name: "Expenses this month" }),
	).toBeVisible();
	await expect(page.getByText(money(after.expenses))).toBeVisible();
	await expect(page.getByText(money(after.profit))).toBeVisible();
	await expect(page.getByText(money(after.donations))).toBeVisible();
});
```

- [ ] **Step 2: Run the whole suite against this stream's stack**

Run (from the meta worktree; the stack must be up and migrated, and `just e2e` runs `manage` in this stack's django container):

```bash
just migrate
just seed
just e2e
```

Expected: every spec passes, `b3-finance.spec.ts` included. The card formats through billing's `formatMoney`, which is `Intl.NumberFormat(language, { style: "currency", currency })`, so in English it renders exactly what `money()` builds, negatives included.

- [ ] **Step 3: Commit**

```bash
cd dashboard
npx pnpm@10 exec biome check --write e2e
git add e2e/b3-finance.spec.ts
git commit -m "test(e2e): B3a expenses and donations journey

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Slice gates

- [ ] **Step 1: Run every gate against this stream's stack**

From the meta worktree:

```bash
just test
just lint
just e2e
```

Expected:
- backend tests pass, with coverage ≥ 80 %;
- the dashboard type check passes;
- the import boundaries hold;
- ruff and biome are clean;
- the colour check passes;
- every Playwright spec passes.

- [ ] **Step 2: Record and hand over**

Per the orchestration loop:
- update the phase row (`python3 scripts/orchestration/ledger.py phase B3 --status review --task "final review"`);
- dispatch the fresh whole-slice reviewer;
- fix any critical or important finding, and log minor ones in `../_ledger/orchestration/phases/B3.md`;
- `queue B3a`.

## Spec coverage

| Spec section | Task |
|---|---|
| §2 A-1 (app, boundaries, clock) | 1, 2 |
| §2 A-2 (features off by default; 404 for code holders; demo on) | 1, 6, 7 |
| §2 A-3, A-4 (expense fields and types) | 1, 3 |
| §2 A-5, A-6 (donation fields, methods, statuses, numbers) | 1, 4 |
| §2 A-7 (net profit, null with invoices off) | 5, 11 |
| §2 A-8 (posted expenses, read-only, feature-independent) | 3, 6, 9 |
| §2 A-9 (resources, office only, widget code) | 6, 8, 11 |
| §2 A-10 (money) | 3, 4, 5 |
| §3.1, §3.2 (data) | 1 |
| §4.1, §4.2 (requests, responses) | 3, 4, 6 |
| §4.3 (lists, filters, CSV) | 3, 4, 6 |
| §4.4 (posting service) | 3 |
| §4.5 (billing exports) | 2 |
| §4.6 (summaries) | 5, 6 |
| §5 (API, errors, access, wiring) | 1, 6 |
| §6 (dashboard) | 8, 9, 10, 11 |
| §7 (seeds) | 7 |
| §8 (testing) | every task; e2e in 12 |
