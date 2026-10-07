# Plan 35 — Slice B3h: Exchange rates and the converted net-profit estimate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Slice:** B3h
**Requires:** — (no other phase's slice; B3g merged first; built before B3d)

**Goal:** The admin records, by hand, what one unit of each currency the academy deals in is worth in the academy's own currency. The home's net-profit card then adds one converted figure for the month, labelled an estimate, under the per-currency lines, which stay the truth. Later phases (B4, B7, B11) convert money only through `finance.services.convert_estimate`.

**Architecture:**
- **Backend:** `etqan.finance` (already the owner of net profit) gains one model, `ExchangeRate` (one current rate per currency, `Decimal(20, 10)`), a `services/rates.py` (validation, CRUD, stale and old rules), a `services/convert.py` (`convert_estimate`, the only cross-currency path, exact `Decimal` arithmetic rounded once), a `net_profit_estimate` key on `finance/summary/`, and a new `finance/exchange-rates/` API behind a new feature `exchange_rates` (`requires=()`, default off) and a new access resource `exchange_rate`.
- **Dashboard:** a Billing → Exchange rates page (list, add/edit dialog, delete), and one estimate line in `FinanceSummaryCard`. Rates travel as decimal strings and are never parsed into floats for display.
- **Seeds:** `seed_rates(subdomain)` in `etqan/tenants/seeds/finance.py`, called under the B3 marker.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18, Python `decimal`; React 19 + TanStack Router/Query, react-hook-form + zod 4, i18next, `Intl`; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-05-b3h-exchange-rates-design.md` (decisions H-1..H-11, review-revised). Ledger: D24 and D31 (the `convert_estimate` contract), D5/D16 (revenue, per `Payment.currency`), D11 (en and ar only), D19 (`NotImpersonating` is only for money-moving routes: none here). Format and conventions follow Plan 15 (`2026-10-03-plan-15-expenses-donations.md`) and Plan 26.

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), and the meta repo (trunk `master`). `marketing/` is not touched.
- Work on a `feat/b3h-exchange-rates` branch in `backend/` and `dashboard/` (and in the meta worktree for e2e-free docs only). Create it from each repo's trunk if it does not exist: `git -C backend switch -c feat/b3h-exchange-rates`, `git -C dashboard switch -c feat/b3h-exchange-rates`. Check with `git -C backend branch --show-current` first.
- **Never run any `git submodule` subcommand.** Commit in the repo the change lives in (`git -C backend …`, `git -C dashboard …`), never the submodule pointers in meta, and never `git commit -a` in meta.
- Commits use Conventional Commits and end with exactly `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

**Shared lists:** add lines only under the `── phase B3 ──` markers: the feature registry (`etqan/platform/features.py`), the access `RESOURCES` (`etqan/access/registry.py`), `seed_academy` (`seed_dev.py`), `etqan/tenants/seeds/finance.py`, the dashboard `NAV_ITEMS`. Test tables without markers take additive edits only (`access/tests/test_routes.py`, `platform/tests/test_features.py`, `features/shell/nav.test.ts`, `routes/permissions.test.ts`, `features/identity/schemas.ts`); keep both sides on a rebase conflict. Translations go in the existing `finance.json` area files.

**Features:** `exchange_rates` is built with `requires=()` and `default=False`, written out (`_built` defaults to `True`, so use `Feature(...)` or `default=False`).

**Money and rates:** money is integer minor units plus a currency. A rate is a decimal, not money: stored `Decimal(20, 10)`, accepted only as a JSON string matching `^\d{1,10}(\.\d{1,10})?$` after stripping spaces and greater than 0, emitted as `format(d.normalize(), "f")`. Never summed across currencies except through `convert_estimate`. Stored instants are UTC.

**Language:** only en and ar strings (D11), real Arabic: `locales.test.ts` fails when an ar value equals its en value.

**Backend commands.** Run from the meta worktree, inside this stream's stack (`just dev-backend`). Load the ports first:
```bash
set -a && . ./.env.stream && set +a
DJ="docker compose -f docker-compose.local.yml exec -T django"
```
- Targeted tests: `$DJ pytest etqan/finance -q` (add `--create-db` once after Task 1 adds a migration).
- Migrations: `$DJ python manage.py makemigrations finance`. Never run `manage.py`, `migrate` or e2e any other way.
- Format and lint: `$DJ sh -c 'ruff check --fix . && ruff format .'`, `$DJ lint-imports`.
- Whole suite: `just test-backend`. Watch `PLR0913` (keyword-only signatures that mirror an API body carry `# noqa: PLR0913 -- <reason>`).

**Dashboard commands.** From the meta worktree (the stream's `.env.stream` is loaded as above):
```bash
DASH="docker compose -f docker-compose.local.yml run --rm dashboard"
export HOST_UID=$(id -u) HOST_GID=$(id -g)
```
- One test file: `$DASH pnpm vitest run src/features/finance/<file>`.
- Full dashboard tests with coverage: `set -a; . ./.env.stream; set +a; HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm test:coverage`.
- Types: `just test-frontend` (this is `tsc --noEmit` only, not the tests). Lint: `just lint-frontend` (`biome ci . && node scripts/check-colors.mjs`): semantic tokens only, no hex, no Tailwind palette utilities.
- New route files regenerate `src/routeTree.gen.ts` with `$DASH pnpm exec vite build` before `tsc`; it is generated, never hand-edit.
- Format: `$DASH pnpm exec biome check --write src e2e`.

**Gates before queuing:** `just test`, `just lint`, `just e2e e2e/b3-exchange-rates.spec.ts` (plus the full `just e2e`), backend coverage ≥ 80 %, dashboard lines and statements ≥ 80, branches and functions ≥ 70.

## Decisions (gaps the spec left, filled here)

| # | Decision |
|---|---|
| D1 | The rate check lives in `finance.services.rules.clean_rate(value: object) -> Decimal`, not in a DRF field: the serializer's `rate` is a `JSONField`, so a JSON number reaches the service as a `float` and is refused there with a 400 on `rate` (a DRF `CharField` would silently turn `4.12` into `"4.12"`). |
| D2 | `Estimate` is a frozen dataclass `(currency: str, amount_minor: int \| None, missing: tuple[str, ...], as_of: datetime \| None)`. `missing` is sorted. **When `amount_minor` is `None`, `as_of` is `None` too** (the spec does not say; no figure means nothing to date). The API emits `missing` as a list and `as_of` as ISO-8601 UTC. |
| D3 | `convert_estimate` reads rates with `ExchangeRate.objects.filter(base_currency=base).exclude(currency=base)`: that single query is both stale rules at once (a `base_changed` row has the wrong stamp; an `own_currency` row has `currency == base`). The academy currency converts at rate 1 and never counts for `as_of`. |
| D4 | The final rounding is done after the `Inexact` trap is switched off inside the same `localcontext`: `Decimal.quantize` signals `Inexact` whenever it rounds, so quantizing under the trap would always raise. Multiply and add run under the trap; the single `quantize(Decimal(1), rounding=ROUND_HALF_UP)` does not. The scaling by `10^(base_digits - digits)` uses `scaleb`, which is exact. |
| D5 | The summary computes `net_profit_estimate` only when `net_profit_this_month` is not null; `convert_estimate` itself already returns `None` while `exchange_rates` is off, so the summary never reads the switch twice. Existing exact-dict assertions in `test_summary.py` and `test_api.py` gain `"net_profit_estimate": None`. |
| D6 | `ExchangeRate.updated_at` is `auto_now` (real `timezone.now()`); `old` is computed against `finance.clock.now()` so tests pin it by rewriting `updated_at` with a queryset `.update(...)`. |
| D7 | The estimate line renders the amount with the shared `formatMoney` (symbol or code included), so the spec's "≈ {amount} {currency}" is one formatted money string. The "Add rates" sentence is two keys (`estimate.addRates`, `estimate.missing`) so the first can be a link without `<Trans>`. |
| D8 | The as-of date uses `dayIn(new Date(as_of), academyTimezone, language)`. While the academy settings are still loading the estimate line waits; if they fail it shows the line without "(as of …)". |
| D9 | A stale `own_currency` row shows no edit button (its PATCH is a 400); a `base_changed` row keeps edit. The add dialog offers the curated currencies minus the academy's own and minus those that already have a row. |

## Review Focus

1. **A rate sent as a JSON number** (`{"rate": 4.12}`): 400 on `rate`, never silently accepted as text. Test in Task 2 (service) and Task 4 (API).
2. **The academy currency changed to a currency that already has a rate row** (USD → EGP with an EGP row): GET marks it `stale`/`own_currency`, PATCH is a 400 on `currency` with no `IntegrityError` and the row unchanged, `convert_estimate` converts EGP at 1 and ignores it, DELETE works. Tests in Tasks 2, 3 and 4.
3. **A zero-amount line in a currency with no rate** (a currency whose net profit netted to exactly 0): skipped, not in `missing`, not in `as_of`, so a settled month still gets an estimate. Test in Task 3.
4. **A half at the rounding boundary and a sum per-line rounding would change**: −0.5 rounds to −1, +0.5 to 1, and two 0.4 lines give 1 not 0; a 20-digit rate × 12-digit amount raises no `Inexact`; the global decimal context is untouched afterwards. Tests in Task 3.
5. **The as-of date near the academy's midnight**: `as_of` 22:30 UTC on 30 June is 1 July in Asia/Tokyo; the home shows the academy's date. Test in Task 7.

## File structure

**Backend (`backend/`)**

| Path | Responsibility |
|---|---|
| `etqan/finance/models.py` | `ExchangeRate` |
| `etqan/finance/migrations/0002_exchangerate.py` | generated (name may differ; commit what `makemigrations` writes) |
| `etqan/finance/services/rules.py` | `clean_rate` |
| `etqan/finance/services/rates.py` | `rate_text`, `stale_reason`, `is_old`, `base_currency`, `rates_queryset`, `list_rates`, `create_rate`, `update_rate`, `delete_rate`, `has_rates` |
| `etqan/finance/services/convert.py` | `Estimate`, `convert_estimate` |
| `etqan/finance/services/summary.py` | `net_profit_estimate` key |
| `etqan/finance/services/__init__.py` | exports |
| `etqan/finance/api/{serializers,payloads,views,urls}.py` | `finance/exchange-rates/` |
| `etqan/finance/tests/test_rates.py`, `test_convert.py`, `test_rates_api.py` | new tests; `conftest.py`, `test_summary.py`, `test_api.py` edited |
| `etqan/platform/features.py`, `platform/tests/test_features.py` | the feature |
| `etqan/access/registry.py`, `access/tests/test_registry.py`, `access/tests/test_routes.py` | the resource and the route matrix |
| `etqan/tenants/seeds/finance.py`, `tenants/management/commands/seed_dev.py`, `tenants/tests/test_seed_finance.py` | `seed_rates` |

**Dashboard (`dashboard/`)**

| Path | Responsibility |
|---|---|
| `src/features/finance/schemas.ts` | rate types, `rateFormSchema`, `NetProfitEstimate` |
| `src/features/finance/api.ts`, `queries.ts` | `/finance/exchange-rates/` routes and hooks |
| `src/features/finance/ExchangeRatesList.tsx`, `ExchangeRateDialog.tsx` | the page |
| `src/features/finance/FinanceSummaryCard.tsx` | the estimate line |
| `src/features/finance/landing.ts`, `index.ts` | `BILLING_PAGES` entry, exports |
| `src/routes/_authed/billing.exchange-rates.tsx` | the route |
| `src/features/identity/schemas.ts`, `src/features/shell/nav.ts`, `nav.test.ts`, `src/routes/permissions.test.ts` | wiring |
| `src/locales/{en,ar}/finance.json` | strings |
| `src/test/finance-fixtures.ts` | `exchangeRateRow`, `ratesList`, estimate fixtures |
| `e2e/b3-exchange-rates.spec.ts` | the journey through Caddy |

---

### Task 1: The model, the feature and the access resource

**Files:**
- Modify: `backend/etqan/finance/models.py`, `backend/etqan/platform/features.py` (B3 marker), `backend/etqan/platform/tests/test_features.py`, `backend/etqan/access/registry.py` (B3 marker), `backend/etqan/access/tests/test_registry.py`
- Create: `backend/etqan/finance/migrations/0002_*.py` (generated), `backend/etqan/finance/tests/test_rates.py` (model tests only for now)

**Interfaces:**
- Produces: `etqan.finance.models.ExchangeRate(currency, base_currency, rate: Decimal, updated_by, updated_at)`; feature code `exchange_rates`; resource `exchange_rate` with in-use verbs `view_any, create, update, delete`.

- [ ] **Step 1: Write the failing tests**

In `backend/etqan/platform/tests/test_features.py` add under `# ── phase B3 ──` in `BUILT`, after `"online_payments": False,`:

```python
    "exchange_rates": False,
```

In `backend/etqan/access/tests/test_registry.py`, in `test_resources_carry_the_12_verbs_and_the_role_resource_6`, after the donation assertion:

```python
    # Phase B3 (slice B3h, H-10).
    assert by_code["exchange_rate"].in_use == ("view_any", "create", "update", "delete")
```

Create `backend/etqan/finance/tests/test_rates.py`:

```python
"""B3h: exchange-rate rows, their rules and their services."""

from decimal import Decimal

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.finance.models import ExchangeRate
from etqan.platform import features


def test_exchange_rates_is_built_off_by_default_and_requires_nothing():
    feature = features.get("exchange_rates")
    assert feature.built is True
    assert feature.default is False
    assert feature.requires == ()


def test_a_rate_is_a_positive_decimal_and_never_the_base_itself(db):
    row = ExchangeRate.objects.create(
        currency="SAR", base_currency="EGP", rate=Decimal("13.0000000000")
    )
    assert ExchangeRate.objects.get(pk=row.pk).rate == Decimal("13.0000000000")
    with pytest.raises(IntegrityError), transaction.atomic():
        ExchangeRate.objects.create(currency="USD", base_currency="EGP", rate=0)
    with pytest.raises(IntegrityError), transaction.atomic():
        ExchangeRate.objects.create(currency="EGP", base_currency="EGP", rate=1)
    with pytest.raises(IntegrityError), transaction.atomic():
        ExchangeRate.objects.create(currency="SAR", base_currency="EGP", rate=2)


def test_rates_are_ordered_by_currency(db):
    for code in ("USD", "AED", "SAR"):
        ExchangeRate.objects.create(currency=code, base_currency="EGP", rate=2)
    assert [r.currency for r in ExchangeRate.objects.all()] == ["AED", "SAR", "USD"]
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/platform/tests/test_features.py etqan/access/tests/test_registry.py etqan/finance/tests/test_rates.py -q`
Expected: FAIL (no `exchange_rates` feature, no `exchange_rate` resource, no `ExchangeRate`).

- [ ] **Step 3: Implement**

In `backend/etqan/finance/models.py` change the Django imports to include `F` (`from django.db.models import F` beside `Q`) and append:

```python
class ExchangeRate(models.Model):
    """What one unit of ``currency`` is worth in ``base_currency``, entered by
    hand (B3h H-1). One current row per currency, no history. ``base_currency``
    is the academy's default currency when the row was written; a row whose
    stamp no longer matches is stale (H-3). A rate is a decimal, not money
    (H-2)."""

    currency = models.CharField(max_length=3, unique=True, validators=[CURRENCY])
    base_currency = models.CharField(max_length=3, validators=[CURRENCY])
    rate = models.DecimalField(max_digits=20, decimal_places=10)
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["currency"]
        constraints = [
            models.CheckConstraint(
                condition=Q(rate__gt=0), name="finance_rate_positive"
            ),
            models.CheckConstraint(
                condition=~Q(currency=F("base_currency")),
                name="finance_rate_not_base",
            ),
        ]

    def __str__(self):
        return f"ExchangeRate<{self.currency}->{self.base_currency} {self.rate}>"
```

In `backend/etqan/platform/features.py`, under `# ── phase B3 ──`, after the `online_payments` `Feature(...)` block and before `# ── phase B4 ──`:

```python
    # B3h (H-9): hand-entered exchange rates and the converted net-profit
    # estimate. Useful on its own, so it requires nothing.
    Feature(
        "exchange_rates",
        "Exchange rates",
        "أسعار الصرف",
        "money",
        default=False,
        built=True,
        requires=(),
    ),
```

In `backend/etqan/access/registry.py`, under `# ── phase B3 ──`, after the `payment_link` resource and before `# ── phase B4 ──`:

```python
    # B3h (H-10): hand-entered exchange rates.
    Resource(
        "exchange_rate",
        "Exchange rates",
        "أسعار الصرف",
        ("view_any", "create", "update", "delete"),
    ),
```

- [ ] **Step 4: Generate the migration and run the tests**

Run: `$DJ python manage.py makemigrations finance` (creates `0002_exchangerate.py`; it must only create the table and its two constraints).
Run: `$DJ pytest etqan/platform etqan/finance/tests/test_rates.py etqan/finance/tests/test_models.py -q --create-db`
Then: `$DJ pytest etqan/access/tests/test_registry.py -q`
Expected: PASS. (`test_routes.py` stays red until Task 4 adds the routes: `every_code_in_the_table...` needs the codes in use. Do not run it yet.)

- [ ] **Step 5: Format, lint, contracts, commit**

Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/finance/models.py etqan/finance/migrations etqan/finance/tests/test_rates.py etqan/platform/features.py etqan/platform/tests/test_features.py etqan/access/registry.py etqan/access/tests/test_registry.py
git -C backend commit -m "feat(finance): ExchangeRate model, exchange_rates feature and resource (B3h)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Rate validation, stale and old rules, and the rate services

**Files:**
- Modify: `backend/etqan/finance/services/rules.py`, `backend/etqan/finance/services/__init__.py`, `backend/etqan/finance/tests/conftest.py`, `backend/etqan/finance/tests/test_rates.py`
- Create: `backend/etqan/finance/services/rates.py`

**Interfaces:**
- Consumes: `ExchangeRate` (Task 1); `academy_services.get_settings()`; `clean_currency`; `finance.clock.now()`.
- Produces (all re-exported from `etqan.finance.services`):
  - `rules.clean_rate(value: object) -> Decimal` (raises `ValidationError(field="rate")`);
  - `rate_text(value: Decimal) -> str`;
  - `base_currency() -> str`;
  - `stale_reason(row: ExchangeRate, base: str) -> str | None` (`"own_currency"`, `"base_changed"`, `None`);
  - `is_old(row: ExchangeRate) -> bool`;
  - `rates_queryset() -> QuerySet[ExchangeRate]` (select_related `updated_by`);
  - `list_rates() -> tuple[str, list[ExchangeRate]]` (base, rows by currency);
  - `create_rate(*, currency: str, rate: object, by) -> ExchangeRate`;
  - `update_rate(row: ExchangeRate, *, rate: object, by) -> ExchangeRate`;
  - `delete_rate(row: ExchangeRate) -> None`;
  - `has_rates() -> bool`.
  - Test fixture `base(code="EGP")` in `finance/tests/conftest.py`: switches the academy currency.

- [ ] **Step 1: Write the failing tests**

Append to `backend/etqan/finance/tests/conftest.py`:

```python
@pytest.fixture
def base(db):
    """`base("USD")` makes USD the academy's currency; EGP to start."""
    from etqan.academy import services as academy_services  # noqa: PLC0415

    def switch(code="EGP"):
        academy_services.update_settings(default_currency=code)

    switch("EGP")
    return switch


@pytest.fixture
def rates_on(set_features):
    """The switch these services' callers read (it ships off, H-9)."""
    return set_features(exchange_rates=True)
```

Append to `backend/etqan/finance/tests/test_rates.py`:

```python
from datetime import timedelta

from etqan.finance import clock as finance_clock
from etqan.finance import services
from etqan.platform.exceptions import ValidationError


def make(code="SAR", rate="13", by=None):
    return services.create_rate(currency=code, rate=rate, by=by)


@pytest.mark.parametrize(
    ("text", "shown"),
    [
        ("10", "10"),  # never "1E+1"
        ("0.0000000001", "0.0000000001"),  # never an exponent
        ("4.1200000000", "4.12"),
        ("4.0", "4"),
        ("9999999999.9999999999", "9999999999.9999999999"),
        ("  4.12  ", "4.12"),  # surrounding spaces are stripped
    ],
)
def test_a_rate_reads_as_a_fixed_point_string(base, text, shown):
    row = make(rate=text)
    fresh = ExchangeRate.objects.get(pk=row.pk)
    assert services.rate_text(fresh.rate) == shown


@pytest.mark.parametrize(
    "bad",
    [
        4.12,  # a JSON number (review focus 1)
        4,
        True,
        None,
        "",
        "  ",
        "0",
        "0.0000000000",
        "-1",
        "+1",
        "1e3",
        "1,5",
        ".5",
        "5.",
        "12345678901",  # 11 integer digits
        "1.12345678901",  # 11 decimals
        "abc",
        "١٢",  # non-ASCII digits
    ],
)
def test_a_bad_rate_is_a_400_on_rate(base, bad):
    with pytest.raises(ValidationError) as caught:
        make(rate=bad)
    assert caught.value.field == "rate"
    assert ExchangeRate.objects.count() == 0


def test_the_academy_currency_takes_no_row(base):
    with pytest.raises(ValidationError) as caught:
        make("EGP")
    assert caught.value.field == "currency"


def test_a_malformed_currency_is_a_400_on_currency(base):
    with pytest.raises(ValidationError) as caught:
        make("EG")
    assert caught.value.field == "currency"


def test_a_row_is_stamped_with_the_base_and_the_user(base, admin):
    row = make("sar", "13.5", by=admin)
    row.refresh_from_db()
    assert (row.currency, row.base_currency, row.updated_by_id) == (
        "SAR",
        "EGP",
        admin.pk,
    )


def test_a_duplicate_is_a_400_on_currency(base):
    make()
    with pytest.raises(ValidationError) as caught:
        make(rate="14")
    assert caught.value.field == "currency"
    assert "edit it" in caught.value.message
    assert ExchangeRate.objects.get(currency="SAR").rate == Decimal("13")


def test_a_duplicate_against_a_stale_row_says_edit_it(base):
    make()
    base("USD")
    with pytest.raises(ValidationError) as caught:
        make(rate="14")
    assert caught.value.field == "currency"
    assert "edit it" in caught.value.message


def test_a_lost_unique_race_is_the_same_400_not_a_500(base, monkeypatch):
    """Two POSTs both pass the exists() check; the second insert loses."""
    make()
    monkeypatch.setattr(
        services.rates, "_exists", lambda code: False
    )  # the check was stale when the insert ran
    with pytest.raises(ValidationError) as caught:
        make(rate="14")
    assert caught.value.field == "currency"
    assert "edit it" in caught.value.message


def test_a_row_is_stale_when_the_academy_currency_changes_and_current_after_an_edit(
    base, admin
):
    row = make()
    assert services.stale_reason(row, "EGP") is None
    base("USD")
    assert services.stale_reason(row, services.base_currency()) == "base_changed"
    services.update_rate(row, rate="3.5", by=admin)
    row.refresh_from_db()
    assert (row.base_currency, row.rate) == ("USD", Decimal("3.5"))
    assert services.stale_reason(row, "USD") is None


def test_switching_the_academy_currency_back_makes_the_row_current_again(base):
    row = make()
    base("USD")
    assert services.stale_reason(row, "USD") == "base_changed"
    base("EGP")
    assert services.stale_reason(row, "EGP") is None


def test_own_currency_wins_over_base_changed(base):
    row = make("USD", "48.5")  # base EGP
    base("USD")  # row.currency == academy currency, stamped base EGP differs
    assert services.stale_reason(row, "USD") == "own_currency"


def test_a_patch_on_an_own_currency_row_is_a_400_on_currency_and_writes_nothing(
    base, admin
):
    row = make("USD", "48.5")
    base("USD")
    with pytest.raises(ValidationError) as caught:
        services.update_rate(row, rate="49", by=admin)
    assert caught.value.field == "currency"
    assert "Delete this rate" in caught.value.message
    row.refresh_from_db()
    assert (row.rate, row.base_currency, row.updated_by_id) == (
        Decimal("48.5"),
        "EGP",
        None,
    )
    services.delete_rate(row)  # only DELETE remains
    assert not ExchangeRate.objects.exists()


def test_a_bad_rate_on_update_changes_nothing(base):
    row = make()
    with pytest.raises(ValidationError):
        services.update_rate(row, rate=12.5, by=None)
    row.refresh_from_db()
    assert row.rate == Decimal("13")


def test_a_rate_updated_over_30_days_ago_is_old_but_exactly_30_is_not(base, clock):
    row = make()
    now = finance_clock.now()
    ExchangeRate.objects.filter(pk=row.pk).update(updated_at=now - timedelta(days=30))
    row.refresh_from_db()
    assert services.is_old(row) is False
    ExchangeRate.objects.filter(pk=row.pk).update(
        updated_at=now - timedelta(days=30, seconds=1)
    )
    row.refresh_from_db()
    assert services.is_old(row) is True


def test_list_rates_gives_the_base_and_the_rows_by_currency(base):
    make("USD", "48.5")
    make("SAR", "13")
    shown_base, rows = services.list_rates()
    assert shown_base == "EGP"
    assert [r.currency for r in rows] == ["SAR", "USD"]
    assert services.has_rates() is True
```

(`admin` and `clock` come from the finance conftest; `clock` pins `finance.clock.now`.)

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/finance/tests/test_rates.py -q`
Expected: FAIL (`services.create_rate` and friends do not exist).

- [ ] **Step 3: Implement**

Add to `backend/etqan/finance/services/rules.py` (imports `re`, `Decimal` at the top with the others):

```python
import re
from decimal import Decimal

RATE_RE = re.compile(r"[0-9]{1,10}(\.[0-9]{1,10})?")


def clean_rate(value: object) -> Decimal:
    """A rate as the API accepts it (B3h H-2): a string only (a JSON number
    is refused, D1), spaces stripped, at most 10 integer digits and 10
    decimals, above zero."""
    if not isinstance(value, str):
        raise ValidationError('Send the rate as text, like "4.12".', field="rate")
    text = value.strip()
    if not RATE_RE.fullmatch(text):
        raise ValidationError(
            "Use a number with up to 10 digits before and after the point, "
            "like 4.12.",
            field="rate",
        )
    number = Decimal(text)
    if number <= 0:
        raise ValidationError("The rate must be above zero.", field="rate")
    return number
```

Create `backend/etqan/finance/services/rates.py`:

```python
"""Hand-entered exchange rates (B3h H-1..H-4): one current rate per currency
against the academy's own currency."""

from datetime import timedelta
from decimal import Decimal

from django.db import IntegrityError
from django.db import transaction
from django.db.models import QuerySet

from etqan.academy import services as academy_services
from etqan.finance import clock
from etqan.finance.models import ExchangeRate
from etqan.finance.services import rules
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency

OLD_AFTER = timedelta(days=30)  # H-4: older rates still convert, but are flagged


def rate_text(value: Decimal) -> str:
    """H-2: fixed-point, no trailing zeros or ".", never an exponent."""
    return format(value.normalize(), "f")


def base_currency() -> str:
    return academy_services.get_settings().default_currency


def stale_reason(row: ExchangeRate, base: str) -> str | None:
    """H-3. ``own_currency`` wins over ``base_changed``."""
    if row.currency == base:
        return "own_currency"
    if row.base_currency != base:
        return "base_changed"
    return None


def is_old(row: ExchangeRate) -> bool:
    return clock.now() - row.updated_at > OLD_AFTER


def rates_queryset() -> QuerySet[ExchangeRate]:
    return ExchangeRate.objects.select_related("updated_by")


def list_rates() -> tuple[str, list[ExchangeRate]]:
    return base_currency(), list(rates_queryset())


def has_rates() -> bool:
    return ExchangeRate.objects.exists()


def _exists(code: str) -> bool:
    """Module-level so a test can stand in for a lost race."""
    return ExchangeRate.objects.filter(currency=code).exists()


def _already(code: str) -> ValidationError:
    return ValidationError(
        f"{code} already has a rate row, edit it.", field="currency"
    )


def create_rate(*, currency: str, rate: object, by) -> ExchangeRate:
    """A new rate for ``currency``. The academy's own currency takes none, and
    a currency with a row (stale ones too) is edited, not added."""
    base = base_currency()
    code = clean_currency(currency, field="currency")
    if code == base:
        raise ValidationError(
            f"{base} is the academy's own currency and needs no rate.",
            field="currency",
        )
    if _exists(code):
        raise _already(code)
    value = rules.clean_rate(rate)
    try:
        with transaction.atomic():
            return ExchangeRate.objects.create(
                currency=code, base_currency=base, rate=value, updated_by=by
            )
    except IntegrityError:  # a concurrent POST won the unique race
        raise _already(code) from None


@transaction.atomic
def update_rate(row: ExchangeRate, *, rate: object, by) -> ExchangeRate:
    """Rewrite the rate and re-stamp the base and the user, which makes a
    stale ``base_changed`` row current. A row whose currency has become the
    academy's is refused before any write (H-3)."""
    locked = ExchangeRate.objects.select_for_update().get(pk=row.pk)
    base = base_currency()
    if locked.currency == base:
        raise ValidationError("Delete this rate.", field="currency")
    locked.rate = rules.clean_rate(rate)
    locked.base_currency = base
    locked.updated_by = by
    locked.save(update_fields=["rate", "base_currency", "updated_by", "updated_at"])
    return locked


def delete_rate(row: ExchangeRate) -> None:
    row.delete()
```

In `backend/etqan/finance/services/__init__.py` add (alphabetical, matching the file's style) and extend `__all__`:

```python
from etqan.finance.services import rates
from etqan.finance.services.rates import base_currency
from etqan.finance.services.rates import create_rate
from etqan.finance.services.rates import delete_rate
from etqan.finance.services.rates import has_rates
from etqan.finance.services.rates import is_old
from etqan.finance.services.rates import list_rates
from etqan.finance.services.rates import rate_text
from etqan.finance.services.rates import rates_queryset
from etqan.finance.services.rates import stale_reason
from etqan.finance.services.rates import update_rate
```

(`__all__` gains `"base_currency"`, `"create_rate"`, `"delete_rate"`, `"has_rates"`, `"is_old"`, `"list_rates"`, `"rate_text"`, `"rates"`, `"rates_queryset"`, `"stale_reason"`, `"update_rate"`. The test patches `services.rates._exists`, hence the module export.)

- [ ] **Step 4: Run them to verify they pass**

Run: `$DJ pytest etqan/finance -q`
Expected: PASS.

- [ ] **Step 5: Format, lint, contracts, commit**

Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/finance/services etqan/finance/tests
git -C backend commit -m "feat(finance): exchange-rate rules and services (B3h)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `convert_estimate` and the summary's `net_profit_estimate`

**Files:**
- Create: `backend/etqan/finance/services/convert.py`, `backend/etqan/finance/tests/test_convert.py`
- Modify: `backend/etqan/finance/services/summary.py`, `backend/etqan/finance/services/__init__.py`, `backend/etqan/finance/tests/test_summary.py`, `backend/etqan/finance/tests/test_api.py` (the two exact-dict summary assertions)

**Interfaces:**
- Consumes: `ExchangeRate`, `base_currency()` (Task 2); `etqan.platform.currency.minor_digits`; `features.enabled`.
- Produces:
  - `Estimate(currency: str, amount_minor: int | None, missing: tuple[str, ...], as_of: datetime | None)` frozen dataclass;
  - `convert_estimate(lines: list[dict]) -> Estimate | None` where each line is `{"currency": str, "amount_minor": int}`; `None` while `exchange_rates` is off;
  - `summary()` gains `net_profit_estimate: {"currency", "amount_minor", "missing": [..], "as_of"} | None`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/finance/tests/test_convert.py`:

```python
"""B3h H-5..H-8: the one cross-currency path."""

import decimal
from datetime import timedelta
from decimal import ROUND_HALF_UP
from decimal import Decimal

import pytest

from etqan.finance import clock as finance_clock
from etqan.finance import services
from etqan.finance.models import ExchangeRate


def line(code, minor):
    return {"currency": code, "amount_minor": minor}


def rate(code, value, *, age_days=0):
    row = services.create_rate(currency=code, rate=value, by=None)
    if age_days:
        ExchangeRate.objects.filter(pk=row.pk).update(
            updated_at=finance_clock.now() - timedelta(days=age_days)
        )
    return row


@pytest.fixture(autouse=True)
def on(base, rates_on, clock):
    """EGP academy, switch on, finance's clock pinned."""


def test_it_is_none_while_the_feature_is_off(set_features):
    set_features(exchange_rates=False)
    assert services.convert_estimate([line("EGP", 100)]) is None


def test_empty_lines_and_only_zero_lines_give_zero_with_no_date():
    expected = services.Estimate("EGP", 0, (), None)
    assert services.convert_estimate([]) == expected
    assert services.convert_estimate([line("GBP", 0), line("EGP", 0)]) == expected


def test_the_base_line_counts_at_one_and_never_dates_the_estimate():
    estimate = services.convert_estimate([line("EGP", 500)])
    assert estimate == services.Estimate("EGP", 500, (), None)


def test_two_digit_currencies():
    rate("USD", "48.5")
    assert services.convert_estimate([line("EGP", 500), line("USD", 1000)]).amount_minor == (
        500 + 48500
    )


def test_zero_digit_source_currency():
    services.base_currency()  # EGP base; JPY has no minor units
    rate("JPY", "0.3")  # 1 JPY = 0.3 EGP
    # 1000 JPY * 0.3 = 300.0 EGP = 30000 minor
    assert services.convert_estimate([line("JPY", 1000)]).amount_minor == 30000


def test_three_digit_source_currency():
    rate("KWD", "160.5")  # 1 KWD = 160.5 EGP
    # 1000 minor KWD = 1.000 KWD -> 160.5 EGP -> 16050 minor
    assert services.convert_estimate([line("KWD", 1000)]).amount_minor == 16050


def test_three_digit_base(base):
    base("KWD")
    rate("USD", "0.3075")  # 1 USD = 0.3075 KWD
    # 1000 minor USD = 10.00 USD -> 3.075 KWD -> 3075 minor (3 digits)
    estimate = services.convert_estimate([line("USD", 1000)])
    assert (estimate.currency, estimate.amount_minor) == ("KWD", 3075)


def test_zero_digit_base(base):
    base("JPY")
    rate("USD", "150")  # 1 USD = 150 JPY
    # 1000 minor USD = 10.00 USD -> 1500 JPY
    assert services.convert_estimate([line("USD", 1000)]).amount_minor == 1500


def test_a_negative_line_subtracts():
    rate("USD", "2")
    assert services.convert_estimate([line("EGP", 100), line("USD", -30)]).amount_minor == 40


def test_the_half_rounds_away_from_zero_in_both_directions():
    rate("USD", "0.5")
    assert services.convert_estimate([line("USD", 1)]).amount_minor == 1  # +0.5
    assert services.convert_estimate([line("USD", -1)]).amount_minor == -1  # -0.5
    assert services.convert_estimate([line("USD", 3)]).amount_minor == 2  # 1.5
    assert services.convert_estimate([line("USD", -3)]).amount_minor == -2  # -1.5


def test_it_rounds_the_sum_once_not_each_line():
    rate("USD", "0.4")
    rate("SAR", "0.4")
    # each line is 0.4 (0 when rounded alone); the sum 0.8 rounds to 1
    assert services.convert_estimate([line("USD", 1), line("SAR", 1)]).amount_minor == 1


def test_a_twenty_digit_rate_times_a_twelve_digit_amount_is_exact():
    top = "9999999999.9999999999"  # 20 digits
    rate("USD", top)
    amount = 999999999999  # 12 digits
    with decimal.localcontext() as ctx:
        ctx.prec = 60
        expected = int(
            (Decimal(amount) * Decimal(top)).quantize(
                Decimal(1), rounding=ROUND_HALF_UP
            )
        )
    got = services.convert_estimate([line("USD", amount)]).amount_minor
    assert got == expected
    # the call leaves the caller's decimal context alone
    assert decimal.getcontext().prec == 28
    assert decimal.getcontext().traps[decimal.Inexact] is False


def test_a_missing_rate_is_null_never_partial_and_names_the_codes():
    rate("USD", "2")
    estimate = services.convert_estimate(
        [line("USD", 100), line("GBP", 100), line("CHF", 5)]
    )
    assert estimate.amount_minor is None
    assert estimate.missing == ("CHF", "GBP")  # sorted
    assert estimate.as_of is None  # D2


def test_a_stale_base_changed_rate_is_never_used(base):
    rate("USD", "2")
    base("SAR")
    estimate = services.convert_estimate([line("USD", 100)])
    assert (estimate.currency, estimate.amount_minor, estimate.missing) == (
        "SAR",
        None,
        ("USD",),
    )


def test_a_zero_line_without_a_rate_is_skipped_and_neither_missing_nor_dated():
    # review focus 3
    rate("USD", "2", age_days=3)
    estimate = services.convert_estimate([line("USD", 100), line("GBP", 0)])
    assert estimate.amount_minor == 200
    assert estimate.missing == ()
    assert estimate.as_of == ExchangeRate.objects.get(currency="USD").updated_at


def test_as_of_is_the_oldest_update_among_the_rates_used():
    rate("USD", "2", age_days=10)
    rate("SAR", "3", age_days=40)
    rate("AED", "4", age_days=90)  # not in the lines: never counts
    estimate = services.convert_estimate([line("USD", 1), line("SAR", 1)])
    assert estimate.as_of == ExchangeRate.objects.get(currency="SAR").updated_at


def test_an_old_rate_is_still_used():
    rate("USD", "2", age_days=400)
    assert services.convert_estimate([line("USD", 100)]).amount_minor == 200

def test_an_own_currency_row_is_ignored_and_the_academy_currency_converts_at_one():
    # review focus 2: a row written while the academy was USD, whose currency
    # is now the academy's own (the fixture's EGP)
    ExchangeRate.objects.create(
        currency="EGP", base_currency="USD", rate=Decimal("0.02")
    )
    estimate = services.convert_estimate([line("EGP", 500)])
    assert estimate == services.Estimate("EGP", 500, (), None)
```
Append to `backend/etqan/finance/tests/test_summary.py`:

```python
def test_the_estimate_is_null_with_the_feature_off(world, admin, clock, set_features):
    set_features(exchange_rates=False)
    spend(admin, 1000, currency="USD")
    assert services.summary()["net_profit_estimate"] is None


def test_the_estimate_is_null_while_net_profit_is_null(admin, clock, set_features):
    set_features(exchange_rates=True, invoices=False)
    spend(admin, 1000)
    summary = services.summary()
    assert summary["net_profit_this_month"] is None
    assert summary["net_profit_estimate"] is None


def test_the_estimate_converts_net_profit_over_the_current_rates(
    world, admin, clock, set_features
):
    set_features(exchange_rates=True)
    services.create_rate(currency="USD", rate="48.5", by=admin)
    receive(world, admin, 100000)  # EGP revenue
    spend(admin, 30000)  # EGP expense
    spend(admin, 400, currency="USD")  # net -400 USD
    estimate = services.summary()["net_profit_estimate"]
    # EGP 700.00 less USD 4.00 at 48.5 = 70000 - 19400
    assert estimate["currency"] == "EGP"
    assert estimate["amount_minor"] == 70000 - 19400
    assert estimate["missing"] == []
    assert estimate["as_of"] is not None


def test_the_estimate_lists_the_currencies_it_has_no_rate_for(
    admin, clock, set_features
):
    set_features(exchange_rates=True)
    spend(admin, 400, currency="GBP")
    assert services.summary()["net_profit_estimate"] == {
        "currency": "EGP",
        "amount_minor": None,
        "missing": ["GBP"],
        "as_of": None,
    }
```

Edit the existing exact-dict assertions to carry the new key (D5): in `test_net_profit_is_revenue_less_expenses_per_currency`, `test_the_month_is_the_academys` (both), `test_nothing_this_month_is_empty_lists` (the `summary()` one), and `test_with_invoices_off_net_profit_is_null`, add `"net_profit_estimate": None,` as the last key of each expected dict. In `backend/etqan/finance/tests/test_api.py::test_the_summaries` add `"net_profit_estimate": None,` to the expected JSON.

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/finance -q`
Expected: FAIL (`convert_estimate` and `Estimate` missing; summary lacks the key).

- [ ] **Step 3: Implement**

Create `backend/etqan/finance/services/convert.py`:

```python
"""The only cross-currency path (B3h H-5..H-8, ledger D24/D31): current
hand-entered rates to the academy currency, an exact sum rounded once, null
(never partial) when a rate is missing."""

from dataclasses import dataclass
from datetime import datetime
from decimal import ROUND_HALF_UP
from decimal import Decimal
from decimal import Inexact
from decimal import localcontext

from etqan.finance.models import ExchangeRate
from etqan.finance.services.rates import base_currency
from etqan.platform import features
from etqan.platform.currency import minor_digits


@dataclass(frozen=True)
class Estimate:
    """``amount_minor`` is in the academy currency's minor units, or None when
    a needed rate is missing (then ``missing`` lists the codes, sorted, and
    ``as_of`` is None, D2). ``as_of`` is the oldest ``updated_at`` among the
    rates used, None when none was needed."""

    currency: str
    amount_minor: int | None
    missing: tuple[str, ...]
    as_of: datetime | None


def convert_estimate(lines: list[dict]) -> Estimate | None:
    """``lines`` is ``[{currency, amount_minor}]``. Returns None while
    ``exchange_rates`` is off (H-8), so no caller can skip the gate."""
    if not features.enabled("exchange_rates"):
        return None
    base = base_currency()
    needed = [line for line in lines if line["amount_minor"] != 0]  # H-6
    # D3: a stale row is either stamped with another base or is the academy
    # currency itself; this one query leaves both out.
    rates = {
        row.currency: row
        for row in ExchangeRate.objects.filter(base_currency=base).exclude(
            currency=base
        )
    }
    missing = sorted(
        {
            line["currency"]
            for line in needed
            if line["currency"] != base and line["currency"] not in rates
        }
    )
    if missing:
        return Estimate(base, None, tuple(missing), None)
    used = [rates[line["currency"]] for line in needed if line["currency"] != base]
    as_of = min((row.updated_at for row in used), default=None)
    base_digits = minor_digits(base)
    with localcontext() as ctx:
        ctx.prec = 60
        ctx.traps[Inexact] = True  # a silent rounding is an error (H-5)
        total = Decimal(0)
        for line in needed:
            rate = (
                Decimal(1)
                if line["currency"] == base
                else rates[line["currency"]].rate
            )
            exponent = base_digits - minor_digits(line["currency"])
            total += (Decimal(line["amount_minor"]) * rate).scaleb(exponent)
        # D4: quantize signals Inexact whenever it rounds; this one rounding
        # is intended, so the trap comes off for it alone.
        ctx.traps[Inexact] = False
        amount = int(total.quantize(Decimal(1), rounding=ROUND_HALF_UP))
    return Estimate(base, amount, (), as_of)
```

In `backend/etqan/finance/services/summary.py` import `from etqan.finance.services.convert import convert_estimate` and replace `summary()`:

```python
def _estimate(profit: list[dict] | None) -> dict | None:
    """B3h H-8, D5: net profit in the academy currency at the current rates,
    while it exists. ``convert_estimate`` is None while `exchange_rates` is
    off."""
    if profit is None:
        return None
    estimate = convert_estimate(profit)
    if estimate is None:
        return None
    return {
        "currency": estimate.currency,
        "amount_minor": estimate.amount_minor,
        "missing": list(estimate.missing),
        "as_of": estimate.as_of,
    }


def summary() -> dict:
    """`finance/summary/`: this academy month's expenses, its net profit while
    `invoices` is on (null otherwise, A-7), and that profit as one estimate
    (B3h)."""
    first, following = month_of(clock.today())
    spent = expenses_between(first, following)
    profit = None
    if features.enabled("invoices"):
        profit = net_profit(billing_services.revenue_between(first, following), spent)
    return {
        "expenses_this_month": spent,
        "net_profit_this_month": profit,
        "net_profit_estimate": _estimate(profit),
    }
```

In `services/__init__.py` add `from etqan.finance.services.convert import Estimate` and `convert_estimate` (and both in `__all__`).

- [ ] **Step 4: Run them to verify they pass**

Run: `$DJ pytest etqan/finance -q`
Expected: PASS. If `test_a_twenty_digit_rate…` raises `decimal.Inexact`, the multiply or add exceeded 60 digits: check that `scaleb` and the sum stay inside the `localcontext` and that the `Inexact` trap is off only after the loop.

- [ ] **Step 5: Format, lint, contracts, commit**

Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/finance
git -C backend commit -m "feat(finance): convert_estimate and the net-profit estimate (B3h)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The API, the route matrix and the seeds

**Files:**
- Modify: `backend/etqan/finance/api/serializers.py`, `payloads.py`, `views.py`, `urls.py`, `backend/etqan/access/tests/test_routes.py`, `backend/etqan/tenants/seeds/finance.py`, `backend/etqan/tenants/management/commands/seed_dev.py` (B3 marker), `backend/etqan/tenants/tests/test_seed_finance.py`
- Create: `backend/etqan/finance/tests/test_rates_api.py`

**Interfaces:**
- Consumes: Tasks 2 and 3 services.
- Produces: `GET/POST /api/v1/finance/exchange-rates/`, `PATCH/DELETE /api/v1/finance/exchange-rates/<id>/`; `seed_rates(subdomain: str) -> None`.

GET body: `{base_currency, rates: [{id, currency, base_currency, rate, stale, stale_reason, old, updated_by: {id, full_name} | null, updated_at}]}`. Writes answer one row in that same shape (the row's own base is the academy's after a write).

- [ ] **Step 1: Write the failing tests**

Add to `backend/etqan/access/tests/test_routes.py`:
- `ROUTES` (after B3g's entries; find the last B3 rows and add):

```python
    # B3h: exchange rates.
    ("GET", "/api/v1/finance/exchange-rates/", "exchange_rate.view_any"),
    ("POST", "/api/v1/finance/exchange-rates/", "exchange_rate.create"),
    ("PATCH", f"/api/v1/finance/exchange-rates/{N}/", "exchange_rate.update"),
    ("DELETE", f"/api/v1/finance/exchange-rates/{N}/", "exchange_rate.delete"),
```

- `FEATURES` (next to the B3a block):

```python
    # Phase B3, slice B3h.
    **dict.fromkeys(
        (
            ("GET", "/api/v1/finance/exchange-rates/"),
            ("POST", "/api/v1/finance/exchange-rates/"),
            ("PATCH", f"/api/v1/finance/exchange-rates/{N}/"),
            ("DELETE", f"/api/v1/finance/exchange-rates/{N}/"),
        ),
        "exchange_rates",
    ),
```

- `FEATURE_WORDS` (beside `"/finance/summary/"`): `"/exchange-rates/": "exchange_rates",`.

Create `backend/etqan/finance/tests/test_rates_api.py`:

```python
"""B3h §4-§5: the exchange-rate routes, their payloads, errors and gates."""

from datetime import timedelta
from decimal import Decimal

import pytest
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.academy import services as academy_services
from etqan.finance import clock as finance_clock
from etqan.finance import services
from etqan.finance.models import ExchangeRate

RATES = "/api/v1/finance/exchange-rates/"
SUMMARY = "/api/v1/finance/summary/"
ROW_KEYS = {
    "id",
    "currency",
    "base_currency",
    "rate",
    "stale",
    "stale_reason",
    "old",
    "updated_by",
    "updated_at",
}


@pytest.fixture
def admin_api(api_for, clock, set_features):
    """An admin; rates on; the academy's currency EGP."""
    set_features(exchange_rates=True)
    academy_services.update_settings(default_currency="EGP")
    return api_for("admin")


def post(client, currency, rate):
    return client.post(RATES, {"currency": currency, "rate": rate}, format="json")


def test_the_admin_adds_lists_edits_and_deletes_a_rate(admin_api):
    resp = post(admin_api, "sar", " 13.50 ")
    assert resp.status_code == 201, resp.content
    row = resp.json()
    assert set(row) == ROW_KEYS
    assert {k: row[k] for k in ("currency", "base_currency", "rate")} == {
        "currency": "SAR",
        "base_currency": "EGP",
        "rate": "13.5",
    }
    assert (row["stale"], row["stale_reason"], row["old"]) == (False, None, False)
    assert row["updated_by"] == {
        "id": admin_api.user.pk,
        "full_name": admin_api.user.full_name,
    }
    listed = admin_api.get(RATES).json()
    assert listed["base_currency"] == "EGP"
    assert [r["currency"] for r in listed["rates"]] == ["SAR"]
    patched = admin_api.patch(f"{RATES}{row['id']}/", {"rate": "14"}, format="json")
    assert patched.status_code == 200, patched.content
    assert patched.json()["rate"] == "14"
    assert admin_api.delete(f"{RATES}{row['id']}/").status_code == 204
    assert admin_api.get(RATES).json()["rates"] == []


@pytest.mark.parametrize(
    ("body", "field"),
    [
        ({"currency": "SAR", "rate": 4.12}, "rate"),  # a JSON number, focus 1
        ({"currency": "SAR", "rate": "0"}, "rate"),
        ({"currency": "SAR", "rate": "12345678901"}, "rate"),
        ({"currency": "SAR", "rate": "1.12345678901"}, "rate"),
        ({"currency": "SAR"}, "rate"),
        ({"currency": "EGP", "rate": "2"}, "currency"),  # the academy's own
        ({"currency": "EG", "rate": "2"}, "currency"),
        ({"rate": "2"}, "currency"),
    ],
)
def test_bad_bodies_are_400s_on_their_fields(admin_api, body, field):
    resp = admin_api.post(RATES, body, format="json")
    assert resp.status_code == 400, resp.content
    assert field in resp.json()
    assert not ExchangeRate.objects.exists()


def test_a_duplicate_is_a_400_on_currency_saying_edit_it(admin_api):
    assert post(admin_api, "SAR", "13").status_code == 201
    resp = post(admin_api, "SAR", "14")
    assert resp.status_code == 400
    assert "edit it" in str(resp.json()["currency"])
    academy_services.update_settings(default_currency="USD")  # now stale
    resp = post(admin_api, "SAR", "14")
    assert resp.status_code == 400
    assert "edit it" in str(resp.json()["currency"])


def test_a_lost_post_race_is_a_400_not_a_500(admin_api, monkeypatch):
    post(admin_api, "SAR", "13")
    monkeypatch.setattr(services.rates, "_exists", lambda code: False)
    resp = post(admin_api, "SAR", "14")
    assert resp.status_code == 400
    assert "currency" in resp.json()


def test_stale_and_old_rows_are_flagged(admin_api):
    fresh = post(admin_api, "SAR", "13").json()
    old = post(admin_api, "USD", "48.5").json()
    ExchangeRate.objects.filter(pk=old["id"]).update(
        updated_at=finance_clock.now() - timedelta(days=31)
    )
    rows = {r["currency"]: r for r in admin_api.get(RATES).json()["rates"]}
    assert rows["USD"]["old"] is True and rows["SAR"]["old"] is False
    academy_services.update_settings(default_currency="USD")
    listed = admin_api.get(RATES).json()
    assert listed["base_currency"] == "USD"
    by_code = {r["currency"]: r for r in listed["rates"]}
    # SAR: stamped EGP, now stale; USD: its own currency now
    assert (by_code["SAR"]["stale"], by_code["SAR"]["stale_reason"]) == (
        True,
        "base_changed",
    )
    assert (by_code["USD"]["stale"], by_code["USD"]["stale_reason"]) == (
        True,
        "own_currency",
    )
    # an edit makes the base_changed row current again
    resp = admin_api.patch(f"{RATES}{fresh['id']}/", {"rate": "3.75"}, format="json")
    assert resp.json()["stale"] is False and resp.json()["base_currency"] == "USD"
    # switching back makes an untouched stamp current again, with no edit
    academy_services.update_settings(default_currency="EGP")
    by_code = {r["currency"]: r for r in admin_api.get(RATES).json()["rates"]}
    assert by_code["USD"]["stale"] is False


def test_a_patch_on_an_own_currency_row_is_a_400_and_delete_works(admin_api):
    row = post(admin_api, "USD", "48.5").json()
    academy_services.update_settings(default_currency="USD")
    resp = admin_api.patch(f"{RATES}{row['id']}/", {"rate": "49"}, format="json")
    assert resp.status_code == 400, resp.content
    assert "currency" in resp.json()
    stored = ExchangeRate.objects.get(pk=row["id"])
    assert (stored.rate, stored.base_currency) == (Decimal("48.5"), "EGP")
    assert admin_api.delete(f"{RATES}{row['id']}/").status_code == 204


def test_a_json_number_on_patch_is_a_400_on_rate(admin_api):
    row = post(admin_api, "SAR", "13").json()
    resp = admin_api.patch(f"{RATES}{row['id']}/", {"rate": 14}, format="json")
    assert resp.status_code == 400 and "rate" in resp.json()
    assert ExchangeRate.objects.get(pk=row["id"]).rate == Decimal("13")


def test_the_summary_carries_the_estimate(admin_api):
    services.create_expense(
        title="Ads", type="marketing", amount_minor=400, currency="USD", by=None
    )
    first = admin_api.get(SUMMARY).json()["net_profit_estimate"]
    assert first == {
        "currency": "EGP",
        "amount_minor": None,
        "missing": ["USD"],
        "as_of": None,
    }
    post(admin_api, "USD", "48.5")
    second = admin_api.get(SUMMARY).json()["net_profit_estimate"]
    assert (second["amount_minor"], second["missing"]) == (-19400, [])
    assert second["as_of"].endswith("Z")


def test_the_feature_gates_the_routes(api_for, clock, set_features):
    admin = api_for("admin")
    set_features(exchange_rates=False)
    assert admin.get(RATES).status_code == 404
    assert post(admin, "SAR", "13").status_code == 404


def test_only_the_office_with_the_codes_reaches_rates(
    api_for, staff_for, clock, set_features
):
    set_features(exchange_rates=True)
    academy_services.update_settings(default_currency="EGP")
    row = services.create_rate(currency="SAR", rate="13", by=None)
    routes = [
        ("get", RATES, None),
        ("post", RATES, {"currency": "USD", "rate": "48"}),
        ("patch", f"{RATES}{row.pk}/", {"rate": "14"}),
        ("delete", f"{RATES}{row.pk}/", None),
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
    reader = staff_for("exchange_rate.view_any")
    assert reader.get(RATES).status_code == 200
    assert post(reader, "USD", "48").status_code == 403
    assert reader.delete(f"{RATES}{row.pk}/").status_code == 403
    editor = staff_for("exchange_rate.update")
    assert editor.patch(f"{RATES}{row.pk}/", {"rate": "15"}, format="json").status_code == 200
    assert staff_for("exchange_rate.delete").delete(f"{RATES}{row.pk}/").status_code == 204


def test_another_academy_never_leaks(admin_api, tenants, set_features):
    set_features(academy=tenants.other, exchange_rates=True)
    with tenant_context(tenants.other):
        academy_services.update_settings(default_currency="EGP")
        theirs = services.create_rate(currency="GBP", rate="60", by=None)
    assert admin_api.get(RATES).json()["rates"] == []
    assert (
        admin_api.patch(f"{RATES}{theirs.pk}/", {"rate": "1"}, format="json").status_code
        == 404
    )
    assert admin_api.delete(f"{RATES}{theirs.pk}/").status_code == 404
```

Seeds: add to `backend/etqan/tenants/tests/test_seed_finance.py`:

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_gives_demo_its_sample_rates_once():
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    with tenant_context(demo):
        shown = {r.currency: finance.rate_text(r.rate) for r in finance.rates_queryset()}
        assert shown == {"SAR": "13", "USD": "48.5"}  # the demo is EGP
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert finance.rates_queryset().count() == 2


@pytest.mark.django_db
def test_seed_rates_follows_the_academy_currency():
    from etqan.academy import services as academy_services  # noqa: PLC0415
    from etqan.tenants.seeds import finance as seeds  # noqa: PLC0415

    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    with tenant_context(demo):
        finance.rates_queryset().delete()
        academy_services.update_settings(default_currency="USD")
        seeds.seed_rates("demo")
        assert {r.currency: finance.rate_text(r.rate) for r in finance.rates_queryset()} == {
            "SAR": "0.2667"
        }
        finance.rates_queryset().delete()
        academy_services.update_settings(default_currency="GBP")
        seeds.seed_rates("demo")  # any other base: nothing
        assert not finance.has_rates()
```

(If `test_seed_dev_gives_demo…` needs the demo to exist before the second test, add `call_command("seed_dev")` with `DEBUG=True` at the start of the second test too.)

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/finance/tests/test_rates_api.py etqan/tenants/tests/test_seed_finance.py etqan/access -q`
Expected: FAIL (404 for the routes; `seed_rates` missing; the matrix tests fail on missing handlers).

- [ ] **Step 3: Implement the API**

`backend/etqan/finance/api/serializers.py` append:

```python
class ExchangeRateInput(serializers.Serializer):
    """A JSONField, not a CharField: DRF would turn the number 4.12 into the
    string "4.12", and H-2 refuses it (the service checks, D1)."""

    currency = serializers.CharField()
    rate = serializers.JSONField()


class ExchangeRateUpdateInput(serializers.Serializer):
    rate = serializers.JSONField()
```

`backend/etqan/finance/api/payloads.py`: add `from etqan.finance import services` at the top and:

```python
def exchange_rate(row, base: str) -> dict:
    reason = services.stale_reason(row, base)
    return {
        "id": row.pk,
        "currency": row.currency,
        "base_currency": row.base_currency,
        "rate": services.rate_text(row.rate),
        "stale": reason is not None,
        "stale_reason": reason,
        "old": services.is_old(row),
        "updated_by": _person(row.updated_by),
        "updated_at": row.updated_at,
    }


def exchange_rates(base: str, rows) -> dict:
    return {
        "base_currency": base,
        "rates": [exchange_rate(row, base) for row in rows],
    }
```

`backend/etqan/finance/api/views.py`: import `ExchangeRateInput`, `ExchangeRateUpdateInput`, and append:

```python
def _rate(pk) -> dict:
    """A fresh read of what a write changed."""
    return payloads.exchange_rate(
        services.rates_queryset().get(pk=pk), services.base_currency()
    )


class ExchangeRateListView(APIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "exchange_rates"
    permission_codes = {
        "GET": "exchange_rate.view_any",
        "POST": "exchange_rate.create",
    }

    def get(self, request):
        base, rows = services.list_rates()
        return Response(payloads.exchange_rates(base, rows))

    def post(self, request):
        body = ExchangeRateInput(data=request.data)
        body.is_valid(raise_exception=True)
        row = services.create_rate(**body.validated_data, by=request.user)
        return Response(_rate(row.pk), status=status.HTTP_201_CREATED)


class ExchangeRateDetailView(APIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "exchange_rates"
    permission_codes = {
        "PATCH": "exchange_rate.update",
        "DELETE": "exchange_rate.delete",
    }

    def patch(self, request, pk):
        row = get_object_or_404(services.rates_queryset(), pk=pk)
        body = ExchangeRateUpdateInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.update_rate(row, **body.validated_data, by=request.user)
        return Response(_rate(pk))

    def delete(self, request, pk):
        services.delete_rate(get_object_or_404(services.rates_queryset(), pk=pk))
        return Response(status=status.HTTP_204_NO_CONTENT)
```

(Nothing moves money, so no `NotImpersonating`, D19.) `urls.py` gains:

```python
    path(
        "exchange-rates/",
        views.ExchangeRateListView.as_view(),
        name="exchange-rates",
    ),
    path(
        "exchange-rates/<int:pk>/",
        views.ExchangeRateDetailView.as_view(),
        name="exchange-rate",
    ),
```

- [ ] **Step 4: Implement the seeds**

`backend/etqan/tenants/seeds/finance.py` append:

```python
# Phase B3, slice B3h (spec §8): sample rates against the academy currency,
# from a fixed table keyed on it; any other base gets none.
RATES = {
    "EGP": (("SAR", "13.0"), ("USD", "48.5")),
    "USD": (("SAR", "0.2667"),),
}


def seed_rates(subdomain: str) -> None:  # noqa: ARG001 -- keyed on the currency, like seed_finance's call shape
    """Once: only while the academy has no rate. Finance services only."""
    if finance_services.has_rates():
        return
    for code, rate in RATES.get(finance_services.base_currency(), ()):
        finance_services.create_rate(currency=code, rate=rate, by=None)
```

In `seed_dev.py`, under `# ── phase B3 ──`, after `finance_seeds.seed_finance(subdomain)`: `finance_seeds.seed_rates(subdomain)`.

- [ ] **Step 5: Run everything, format, lint, commit**

Run: `$DJ pytest etqan/finance etqan/access etqan/tenants etqan/platform -q`
Expected: PASS (the whole matrix, including `test_every_route_of_a_built_feature_declares_it` and the "every other route" test with the new routes).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/finance etqan/access/tests/test_routes.py etqan/tenants
git -C backend commit -m "feat(finance): exchange-rates API, route matrix rows and seeds (B3h)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Dashboard — rates data layer, page, dialog and wiring

**Files:**
- Modify: `dashboard/src/features/finance/schemas.ts`, `api.ts`, `queries.ts`, `landing.ts`, `index.ts`, `src/features/identity/schemas.ts`, `src/features/shell/nav.ts`, `src/features/shell/nav.test.ts`, `src/routes/permissions.test.ts`, `src/locales/en/finance.json`, `src/locales/ar/finance.json`, `src/test/finance-fixtures.ts`, `src/features/finance/api.test.ts`, `schemas.test.ts`, `landing.test.ts`
- Create: `dashboard/src/features/finance/ExchangeRatesList.tsx`, `ExchangeRateDialog.tsx`, `ExchangeRatesList.test.tsx`, `dashboard/src/routes/_authed/billing.exchange-rates.tsx`

**Interfaces:**
- Consumes: the Task 4 API; `useFillOnOpen`, `saveOrShowErrors`, `DeleteRow`, `useFinanceFieldError` from `features/finance`; `currencyChoices` from `ExpenseDialog`; `useAcademySettings`; `dayIn`.
- Produces:
  - types `ExchangeRate`, `ExchangeRates`, `RateBody`, `NetProfitEstimate`; `FinanceSummary.net_profit_estimate: NetProfitEstimate | null`; `rateFormSchema`/`RateFormValues`;
  - `financeApi.rates()`, `createRate({currency, rate})`, `updateRate({id, rate})`, `deleteRate(id)`;
  - `useExchangeRates()` (query key `[...financeKey, "rates"]`);
  - `<ExchangeRatesList />`, `<ExchangeRateDialog base taken rate? />`;
  - fixtures `exchangeRateRow(overrides)`, `ratesList(overrides)`.

- [ ] **Step 1: Write the failing tests and fixtures**

`src/features/identity/schemas.ts`: add `| "exchange_rates"` to `FeatureCode` under B3 (after `"payment_receipts"`).

`src/test/finance-fixtures.ts`: import `ExchangeRate`, `ExchangeRates` types; extend `financeSummary`'s default object with `net_profit_estimate: null,`; add:

```ts
export function exchangeRateRow(
	overrides: Partial<ExchangeRate> = {},
): ExchangeRate {
	return {
		id: 71,
		currency: "SAR",
		base_currency: "EGP",
		rate: "13",
		stale: false,
		stale_reason: null,
		old: false,
		updated_by: { id: 1, full_name: "Amina" },
		updated_at: "2026-06-01T08:00:00Z",
		...overrides,
	};
}

export function ratesList(overrides: Partial<ExchangeRates> = {}): ExchangeRates {
	return {
		base_currency: "EGP",
		rates: [exchangeRateRow(), exchangeRateRow({ id: 72, currency: "USD", rate: "48.5" })],
		...overrides,
	};
}
```

`api.test.ts`, add a test:

```ts
	it("reads and writes the exchange rates (B3h §5)", async () => {
		await financeApi.rates();
		expect(api.get).toHaveBeenLastCalledWith("finance/exchange-rates/");
		await financeApi.createRate({ currency: "SAR", rate: "13.5" });
		expect(api.post).toHaveBeenLastCalledWith("finance/exchange-rates/", {
			currency: "SAR",
			rate: "13.5",
		});
		await financeApi.updateRate({ id: 4, rate: "14" });
		expect(api.patch).toHaveBeenLastCalledWith("finance/exchange-rates/4/", {
			rate: "14",
		});
		await financeApi.deleteRate(4);
		expect(api.delete).toHaveBeenLastCalledWith("finance/exchange-rates/4/");
	});
```

`schemas.test.ts`, add (import `rateFormSchema`):

```ts
describe("rateFormSchema", () => {
	const ok = (rate: string) =>
		rateFormSchema.safeParse({ currency: "SAR", rate }).success;
	it("takes a decimal string of up to 10 + 10 digits above zero, spaces stripped", () => {
		expect(ok("4.12")).toBe(true);
		expect(ok("  4.12 ")).toBe(true);
		expect(ok("0.0000000001")).toBe(true);
		expect(ok("9999999999.9999999999")).toBe(true);
		expect(ok("0")).toBe(false);
		expect(ok("0.0")).toBe(false);
		expect(ok("")).toBe(false);
		expect(ok("-1")).toBe(false);
		expect(ok("1e3")).toBe(false);
		expect(ok("4,12")).toBe(false);
		expect(ok("12345678901")).toBe(false);
		expect(ok("1.12345678901")).toBe(false);
	});
	it("returns the trimmed string, never a number", () => {
		const parsed = rateFormSchema.parse({ currency: "SAR", rate: " 4.10 " });
		expect(parsed.rate).toBe("4.10");
	});
});
```

`landing.test.ts`, add:

```ts
	it("lands on exchange rates after online payments, for staff who may see only them", () => {
		expect(
			billingLanding({
				...staffMe("exchange_rate.view_any"),
				features: ["exchange_rates"],
			}),
		).toBe("/billing/exchange-rates");
		const staff = staffMe("checkout.view_any", "exchange_rate.view_any");
		expect(
			billingLanding({ ...staff, features: ["online_payments", "exchange_rates"] }),
		).toBe("/billing/checkouts");
	});
```

`nav.test.ts`: add `"/billing/exchange-rates",` after `"/billing/checkouts",` in the two lists (the all-items list near line 83 and the switched-off list near line 181, before `"/settings/gateways"`), `"/billing/exchange-rates": "exchange_rates",` after the checkouts row of the feature map, and `"finance.nav.exchangeRates",` after `"gateways.nav.checkouts",` in the billing group's label list. `permissions.test.ts`: `"/_authed/billing/exchange-rates": "exchange_rates",` after the links row of `FEATURE_SCREENS`, and add `|exchange-rates` to the `FEATURE_WORDS` regex.

Create `src/features/finance/ExchangeRatesList.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { staffMe } from "@/test/access-fixtures";
import { exchangeRateRow, ratesList } from "@/test/finance-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings } from "@/test/scheduling-fixtures";
import { financeApi } from "./api";
import { ExchangeRatesList } from "./ExchangeRatesList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		financeApi: {
			...actual.financeApi,
			rates: vi.fn(),
			createRate: vi.fn(),
			updateRate: vi.fn(),
			deleteRate: vi.fn(),
		},
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const row = (text: string) => screen.getByRole("row", { name: new RegExp(text) });

describe("ExchangeRatesList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ timezone: "Asia/Tokyo", default_currency: "EGP" }),
		);
		vi.mocked(financeApi.rates).mockResolvedValue(ratesList());
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("shows the base and each rate as '1 SAR = 13 EGP' with the update date in the academy's zone", async () => {
		vi.mocked(financeApi.rates).mockResolvedValue(
			ratesList({
				rates: [
					exchangeRateRow({ rate: "4.12", updated_at: "2026-06-30T22:30:00Z" }),
				],
			}),
		);
		renderWithRouter(<ExchangeRatesList />);
		expect(await screen.findByText(/EGP/, { selector: "p" })).toBeInTheDocument();
		const sar = await screen.findByRole("row", { name: /SAR/ });
		expect(within(sar).getByText("1 SAR = 4.12 EGP")).toBeInTheDocument();
		// 22:30 UTC on 30 June is 1 July in Tokyo
		expect(within(sar).getByText(/Jul 1, 2026/)).toBeInTheDocument();
	});

	it("never turns a rate into a float for display", async () => {
		vi.mocked(financeApi.rates).mockResolvedValue(
			ratesList({
				rates: [exchangeRateRow({ rate: "0.0000000001" }), exchangeRateRow({ id: 2, currency: "USD", rate: "9999999999.9999999999" })],
			}),
		);
		renderWithRouter(<ExchangeRatesList />);
		expect(await screen.findByText("1 SAR = 0.0000000001 EGP")).toBeInTheDocument();
		expect(screen.getByText("1 USD = 9999999999.9999999999 EGP")).toBeInTheDocument();
	});

	it("flags stale and old rows; an own-currency row can only be deleted", async () => {
		vi.mocked(financeApi.rates).mockResolvedValue(
			ratesList({
				base_currency: "USD",
				rates: [
					exchangeRateRow({ id: 1, currency: "SAR", stale: true, stale_reason: "base_changed" }),
					exchangeRateRow({ id: 2, currency: "USD", stale: true, stale_reason: "own_currency" }),
					exchangeRateRow({ id: 3, currency: "GBP", old: true }),
				],
			}),
		);
		renderWithRouter(<ExchangeRatesList />);
		await screen.findByRole("table");
		expect(within(row("SAR")).getByText("Stale")).toBeInTheDocument();
		expect(within(row("SAR")).getByRole("button", { name: "Edit the SAR rate" })).toBeInTheDocument();
		expect(within(row("USD")).getByText("Stale")).toBeInTheDocument();
		expect(within(row("USD")).queryByRole("button", { name: /Edit/ })).toBeNull();
		expect(within(row("USD")).getByRole("button", { name: "Delete" })).toBeInTheDocument();
		expect(within(row("GBP")).getByText("Old")).toBeInTheDocument();
		expect(within(row("GBP")).queryByText("Stale")).toBeNull();
	});

	it("adds a rate: the academy's own currency and ones with a row are not offered; the rate goes as a string", async () => {
		vi.mocked(financeApi.createRate).mockResolvedValue(exchangeRateRow());
		const user = userEvent.setup();
		renderWithRouter(<ExchangeRatesList />);
		await user.click(await screen.findByRole("button", { name: "Add rate" }));
		const dialog = screen.getByRole("dialog");
		const currency = within(dialog).getByLabelText(/^Currency/);
		const offered = within(currency).getAllByRole("option").map((o) => o.textContent);
		expect(offered).not.toContain("EGP"); // the academy's own
		expect(offered).not.toContain("SAR"); // has a row
		expect(offered).not.toContain("USD");
		await user.click(within(dialog).getByRole("button", { name: "Save rate" }));
		expect(await within(dialog).findByText(/Enter a number above zero/)).toBeInTheDocument();
		expect(financeApi.createRate).not.toHaveBeenCalled();
		await user.selectOptions(currency, "GBP");
		await user.type(within(dialog).getByLabelText(/^Rate/), " 60.50 ");
		await user.click(within(dialog).getByRole("button", { name: "Save rate" }));
		await waitFor(() =>
			expect(financeApi.createRate).toHaveBeenCalledWith({ currency: "GBP", rate: "60.50" }),
		);
		expect(await screen.findByText("Rate saved.")).toBeInTheDocument();
	});

	it("edits only the rate, filling the dialog once per opening", async () => {
		vi.mocked(financeApi.updateRate).mockResolvedValue(exchangeRateRow());
		const user = userEvent.setup();
		renderWithRouter(<ExchangeRatesList />);
		await user.click(await screen.findByRole("button", { name: "Edit the SAR rate" }));
		const dialog = screen.getByRole("dialog");
		const rate = within(dialog).getByLabelText(/^Rate/);
		await waitFor(() => expect(rate).toHaveValue("13"));
		expect(within(dialog).queryByLabelText(/^Currency/)).toBeNull();
		await user.clear(rate);
		await user.type(rate, "13.75");
		await user.click(within(dialog).getByRole("button", { name: "Save rate" }));
		await waitFor(() =>
			expect(financeApi.updateRate).toHaveBeenCalledWith({ id: 71, rate: "13.75" }),
		);
	});

	it("shows the server's refusal on the rate field", async () => {
		const error = Object.assign(new Error("bad"), {
			isAxiosError: true,
			response: { status: 400, data: { rate: ["The rate must be above zero."] } },
		});
		vi.mocked(financeApi.createRate).mockRejectedValue(error);
		const user = userEvent.setup();
		renderWithRouter(<ExchangeRatesList />);
		await user.click(await screen.findByRole("button", { name: "Add rate" }));
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(within(dialog).getByLabelText(/^Currency/), "GBP");
		await user.type(within(dialog).getByLabelText(/^Rate/), "1");
		await user.click(within(dialog).getByRole("button", { name: "Save rate" }));
		expect(await within(dialog).findByText("The rate must be above zero.")).toBeInTheDocument();
	});

	it("deletes behind a confirmation", async () => {
		vi.mocked(financeApi.deleteRate).mockResolvedValue(undefined);
		const user = userEvent.setup();
		renderWithRouter(<ExchangeRatesList />);
		await screen.findByRole("table");
		await user.click(within(row("SAR")).getByRole("button", { name: "Delete" }));
		await user.click(await screen.findByRole("button", { name: "Delete this rate" }));
		await waitFor(() => expect(financeApi.deleteRate).toHaveBeenCalledWith(71));
		expect(await screen.findByText("Rate deleted.")).toBeInTheDocument();
	});

	it("hides add, edit and delete from staff who may only view", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("exchange_rate.view_any")}>
				<ExchangeRatesList />
			</CanProvider>,
		);
		await screen.findByRole("table");
		expect(screen.queryByRole("button", { name: "Add rate" })).toBeNull();
		expect(screen.queryByRole("button", { name: /Edit/ })).toBeNull();
		expect(screen.queryByRole("button", { name: "Delete" })).toBeNull();
	});

	it("says when there are no rates, and when they can't load", async () => {
		vi.mocked(financeApi.rates).mockResolvedValue(ratesList({ rates: [] }));
		const { unmount } = renderWithRouter(<ExchangeRatesList />);
		expect(await screen.findByText("No exchange rates yet.")).toBeInTheDocument();
		unmount();
		vi.mocked(financeApi.rates).mockRejectedValue(new Error("offline"));
		renderWithRouter(<ExchangeRatesList />);
		expect(await screen.findByText("The exchange rates could not be loaded.")).toBeInTheDocument();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderWithRouter(<ExchangeRatesList />);
		expect(await screen.findByRole("button", { name: "إضافة سعر" })).toBeInTheDocument();
		expect(screen.getByText("1 SAR تساوي 13 EGP")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/finance src/features/shell src/routes`
Expected: FAIL (no rates API, schema, components or nav item). `FeatureCode` lacks `exchange_rates` until Step 3 as well.

- [ ] **Step 3: Implement**

`schemas.ts` (append; add `net_profit_estimate` to `FinanceSummary`):

```ts
/** B3h §4: `finance/summary/`'s converted net profit; null while exchange
 * rates are off or net profit is. `amount_minor` is null with `missing`. */
export interface NetProfitEstimate {
	currency: string;
	amount_minor: number | null;
	missing: string[];
	as_of: string | null;
}
// in FinanceSummary: net_profit_estimate: NetProfitEstimate | null;

export type StaleReason = "base_changed" | "own_currency";

/** B3h §4. `rate` is a fixed-point decimal string: displayed as it is. */
export interface ExchangeRate {
	id: number;
	currency: string;
	base_currency: string;
	rate: string;
	stale: boolean;
	stale_reason: StaleReason | null;
	old: boolean;
	updated_by: Person | null;
	updated_at: string;
}
export interface ExchangeRates {
	base_currency: string;
	rates: ExchangeRate[];
}
export interface RateBody {
	currency: string;
	rate: string;
}

/** H-2: up to 10 digits each side of the point, above zero, spaces
 * stripped; kept a string. */
export const rateFormSchema = z.object({
	currency,
	rate: z
		.string()
		.trim()
		.regex(/^\d{1,10}(\.\d{1,10})?$/, "finance.rates.errors.rateInvalid")
		.refine((value) => /[1-9]/.test(value), "finance.rates.errors.rateInvalid"),
});
export type RateFormValues = z.infer<typeof rateFormSchema>;
```

`api.ts`: add `const RATES = \`${F}exchange-rates/\`;` and in `financeApi`:

```ts
	rates: async () => (await api.get<ExchangeRates>(RATES)).data,
	createRate: async (body: RateBody) =>
		(await api.post<ExchangeRate>(RATES, body)).data,
	updateRate: async ({ id, rate }: { id: number; rate: string }) =>
		(await api.patch<ExchangeRate>(`${RATES}${id}/`, { rate })).data,
	deleteRate: async (id: number) => {
		await api.delete(`${RATES}${id}/`);
	},
```

`queries.ts`:

```ts
export function useExchangeRates() {
	return useQuery({
		queryKey: [...financeKey, "rates"],
		queryFn: financeApi.rates,
	});
}
```

`landing.ts`: append after the checkouts entry
`{ to: "/billing/exchange-rates", code: "exchange_rate.view_any", feature: "exchange_rates" },`.

`index.ts`: add `export { ExchangeRateDialog } from "./ExchangeRateDialog";` and `export { ExchangeRatesList } from "./ExchangeRatesList";`.

`ExchangeRateDialog.tsx` (new). It follows `ExpenseDialog`: `useForm({ resolver: zodResolver(rateFormSchema), defaultValues })`, `useFillOnOpen({ open, ready: true, reset, setFocus, initial, first: rate ? "rate" : "currency" })` (never `values:`), and `saveOrShowErrors`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { CURRENCIES } from "@/lib/currencies";
import {
	Alert, AlertDescription, Button, Dialog, DialogClose, DialogContent,
	DialogDescription, DialogFooter, DialogTitle, DialogTrigger, Field, Input,
	Select, SubmitButton, toast,
} from "@/ui";
import { financeApi } from "./api";
import { useFinanceFieldError } from "./bits";
import { useFinanceMutation } from "./queries";
import { type ExchangeRate, type RateFormValues, rateFormSchema } from "./schemas";
import { saveOrShowErrors, useFillOnOpen } from "./shared";

/** Add a rate, or (with `rate`) edit one: only the number changes (H-1).
 * `base` is the academy's currency and `taken` the currencies that already
 * have a row, neither of which a new rate may name (D9). */
export function ExchangeRateDialog({
	base,
	taken = [],
	rate,
}: {
	base: string;
	taken?: string[];
	rate?: ExchangeRate;
}) {
	const { t } = useTranslation();
	const fieldError = useFinanceFieldError();
	const [open, setOpen] = useState(false);
	const create = useFinanceMutation(financeApi.createRate);
	const update = useFinanceMutation(financeApi.updateRate);
	const initial = useCallback(
		(): RateFormValues => ({
			currency: rate?.currency ?? "",
			rate: rate?.rate ?? "",
		}),
		[rate],
	);
	const { register, handleSubmit, setError, setFocus, reset, formState: { errors, isSubmitting } } =
		useForm<RateFormValues>({ resolver: zodResolver(rateFormSchema), defaultValues: initial() });
	useFillOnOpen({ open, ready: true, reset, setFocus, initial, first: rate ? "rate" : "currency" });
	const choices = CURRENCIES.filter((code) => code !== base && !taken.includes(code));

	async function onSubmit(values: RateFormValues) {
		const saved = await saveOrShowErrors(async () => {
			if (rate) await update.mutateAsync({ id: rate.id, rate: values.rate });
			else await create.mutateAsync({ currency: values.currency, rate: values.rate });
		}, setError);
		if (saved) {
			setOpen(false);
			toast({ description: t("finance.rates.saved"), variant: "success" });
		}
	}
	// … trigger Button, DialogContent, form: for a new rate a <Select dir="ltr"> field
	// labelled t("finance.fields.currency") with an empty first option and
	// `choices`; the rate <Input inputMode="decimal" dir="ltr"> field labelled
	// t("finance.rates.fields.rate"); root server error Alert; Cancel and
	// <SubmitButton>{t("finance.rates.save")}</SubmitButton>, exactly as ExpenseDialog's JSX.
}
```

Write the JSX in full like `ExpenseDialog` (trigger text `t("finance.rates.edit")` with `aria-label={t("finance.rates.editFor", { currency: rate.currency })}` when editing, else `t("finance.rates.add")`; title `editTitle` or `add`; description `t("finance.rates.dialogBody", { base })`; the currency Field is rendered only when `!rate`, with an empty `<option value="">` first so the zod `currency` regex fires `finance.errors.required` until one is chosen). The rate Field's error is `fieldError(errors.rate?.message)`, the currency's `fieldError(errors.currency?.message)`.

`ExchangeRatesList.tsx` (new): `const { data, isPending, isError } = useExchangeRates()`; `const settings = useAcademySettings()`; `can = useCan()`; `remove = useFinanceMutation(financeApi.deleteRate)`.
- Header paragraph (`<p>`): `t("finance.rates.base", { currency: data.base_currency })` and `t("finance.rates.body", { currency })`; the add button `{can("exchange_rate.create") ? <ExchangeRateDialog base={data.base_currency} taken={data.rates.map(r => r.currency)} /> : null}`.
- Error `Alert` with `finance.rates.loadError`; `Spinner` while pending; `EmptyState` (icon `ArrowRightLeft`) with `finance.rates.empty` when no rows; otherwise a table with columns `rate`, `updated`, `status`, `actions`.
- Row: `<span dir="ltr">{t("finance.rates.line", { from: r.currency, rate: r.rate, base: r.base_currency })}</span>` (`rate` is the API's string, interpolated as-is); updated cell `t("finance.rates.updated", { date })` with `date = settings.data ? dayIn(new Date(r.updated_at), settings.data.timezone, i18n.language) : ""` (no date text while settings load); status cell: `r.stale` → `<StatusChip tone="warning">{t("finance.rates.stale")}</StatusChip>` plus a muted line `t(\`finance.rates.staleReason.${r.stale_reason}\`, { base: r.base_currency })`; `r.old` → `<StatusChip>{t("finance.rates.old")}</StatusChip>` with `title={t("finance.rates.oldHint")}`.
- Actions: `can("exchange_rate.update") && r.stale_reason !== "own_currency"` → `<ExchangeRateDialog base={data.base_currency} rate={r} />`; `can("exchange_rate.delete")` → `<DeleteRow i18nPrefix="finance.rates" remove={(callbacks) => remove.mutate(r.id, callbacks)} />`.

`src/routes/_authed/billing.exchange-rates.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { ExchangeRatesList } from "@/features/finance";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/billing/exchange-rates")({
	staticData: { permission: "exchange_rate.view_any", feature: "exchange_rates" },
	component: function ExchangeRatesRoute() {
		const { t } = useTranslation();
		usePageTitle(t("finance.nav.exchangeRates"));
		return (
			<>
				<PageHeader title={t("finance.nav.exchangeRates")} />
				<ExchangeRatesList />
			</>
		);
	},
});
```

`nav.ts`: import `ArrowRightLeft` from `lucide-react` (alphabetical in the import list) and, under the B3 marker after the `/billing/checkouts` item and before `/settings/gateways`:

```ts
	// B3h: the rates the net-profit estimate converts at.
	office(
		"/billing/exchange-rates",
		"finance.nav.exchangeRates",
		ArrowRightLeft,
		"billing",
		"exchange_rate.view_any",
		"exchange_rates",
	),
```

Locales. `src/locales/en/finance.json`: in `nav` add `"exchangeRates": "Exchange rates"`; add these top-level blocks:

```json
"rates": {
  "base": "Your academy's currency is {{currency}}.",
  "body": "Enter what one unit of each currency is worth in {{currency}}. Rates are used only for estimates; the figures in each currency stay as they are.",
  "line": "1 {{from}} = {{rate}} {{base}}",
  "add": "Add rate",
  "edit": "Edit",
  "editFor": "Edit the {{currency}} rate",
  "editTitle": "Edit rate",
  "dialogBody": "How many {{base}} one unit of this currency is worth.",
  "save": "Save rate",
  "saved": "Rate saved.",
  "delete": "Delete",
  "deleteTitle": "Delete this rate",
  "deleteBody": "Estimates will list this currency as missing until you add a rate again.",
  "deleted": "Rate deleted.",
  "empty": "No exchange rates yet.",
  "loadError": "The exchange rates could not be loaded.",
  "updated": "Updated {{date}}",
  "stale": "Stale",
  "old": "Old",
  "oldHint": "Updated more than 30 days ago",
  "staleReason": {
    "base_changed": "Entered against {{base}}. Edit it to use it again.",
    "own_currency": "This is now your academy's currency. Delete this rate."
  },
  "fields": { "rate": "Rate", "updated": "Last update", "status": "Status" },
  "errors": { "rateInvalid": "Enter a number above zero, with up to 10 digits before and after the point, like 4.12." }
},
"estimate": {
  "value": "≈ {{amount}}, estimated at your current rates (as of {{date}})",
  "valueNoDate": "≈ {{amount}}, estimated at your current rates",
  "addRates": "Add rates",
  "missing": "for {{codes}} to see an estimate"
}
```

`src/locales/ar/finance.json`: `nav.exchangeRates` = `"أسعار الصرف"`; and:

```json
"rates": {
  "base": "عملة الأكاديمية هي {{currency}}.",
  "body": "أدخل قيمة وحدة واحدة من كل عملة بـ {{currency}}. تُستخدم الأسعار للتقديرات فقط، وتبقى الأرقام بكل عملة كما هي.",
  "line": "1 {{from}} تساوي {{rate}} {{base}}",
  "add": "إضافة سعر",
  "edit": "تعديل",
  "editFor": "تعديل سعر {{currency}}",
  "editTitle": "تعديل السعر",
  "dialogBody": "كم {{base}} تساوي وحدة واحدة من هذه العملة.",
  "save": "حفظ السعر",
  "saved": "تم حفظ السعر.",
  "delete": "حذف",
  "deleteTitle": "حذف هذا السعر",
  "deleteBody": "ستظهر هذه العملة ناقصة في التقديرات حتى تضيف سعرًا من جديد.",
  "deleted": "تم حذف السعر.",
  "empty": "لا توجد أسعار صرف بعد.",
  "loadError": "تعذّر تحميل أسعار الصرف.",
  "updated": "آخر تحديث {{date}}",
  "stale": "غير صالح",
  "old": "قديم",
  "oldHint": "حُدّث قبل أكثر من 30 يومًا",
  "staleReason": {
    "base_changed": "أُدخل مقابل {{base}}. عدّله لاستخدامه من جديد.",
    "own_currency": "هذه الآن عملة الأكاديمية. احذف هذا السعر."
  },
  "fields": { "rate": "السعر", "updated": "آخر تحديث", "status": "الحالة" },
  "errors": { "rateInvalid": "أدخل رقمًا أكبر من صفر، بحد أقصى 10 أرقام قبل الفاصلة و10 بعدها، مثل 4.12." }
},
"estimate": {
  "value": "≈ {{amount}} تقديريًا بأسعارك الحالية (بتاريخ {{date}})",
  "valueNoDate": "≈ {{amount}} تقديريًا بأسعارك الحالية",
  "addRates": "أضف أسعار الصرف",
  "missing": "لـ {{codes}} لعرض التقدير"
}
```

(`estimate.*` is used in Task 6; adding both files' keys together keeps the en/ar key-equality test green.) Table column headers use `finance.rates.fields.*`.

- [ ] **Step 4: Regenerate routes, run the tests and the checks**

Run: `$DASH pnpm exec vite build` (regenerates `routeTree.gen.ts`), then `$DASH pnpm exec biome check --write src e2e`.
Run: `$DASH pnpm vitest run src/features/finance src/features/shell src/routes src/locales`
Run: `just test-frontend && just lint-frontend`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(finance): exchange rates page, dialog and wiring (B3h)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

(`routeTree.gen.ts` is tracked: `git -C dashboard status` must show it only if the repo tracks it; add it when it does.)

---

### Task 6: Dashboard — the estimate line on the home card

**Files:**
- Modify: `dashboard/src/features/finance/FinanceSummaryCard.tsx`, `FinanceSummaryCard.test.tsx`

**Interfaces:**
- Consumes: `FinanceSummary.net_profit_estimate`, `NetProfitEstimate` (Task 5); `useCan`; `useAcademySettings`; `formatMoney`, `dayIn`; locale keys `finance.estimate.*`.
- Produces: under the per-currency net profit, one of three lines, only when `net_profit_estimate` is non-null and net profit has at least one line in a currency other than `estimate.currency`.

- [ ] **Step 1: Write the failing tests**

In `FinanceSummaryCard.test.tsx` add imports (`waitFor` from RTL, `CanProvider`, `staffMe`, `academyApi`, `academySettings`) and:

```tsx
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
```

with `vi.mocked(academyApi.get).mockResolvedValue(academySettings({ timezone: "Asia/Tokyo" }))` added to `beforeEach`. Then:

```tsx
const estimate = (over = {}) => ({
	currency: "EGP",
	amount_minor: 123450,
	missing: [],
	as_of: "2026-06-30T22:30:00Z",
	...over,
});
const withEstimate = (e: ReturnType<typeof estimate> | null) =>
	vi.mocked(financeApi.summary).mockResolvedValue(
		financeSummary({ net_profit_estimate: e }),
	);

describe("the converted estimate", () => {
	it("shows the amount, 'at your current rates' and the as-of date in the academy's zone", async () => {
		withEstimate(estimate()); // 22:30 UTC on 30 June is 1 July in Tokyo (review focus 5)
		renderWithRouter(<FinanceSummaryCard expenses donations={false} />);
		expect(
			await screen.findByText(
				/≈ .*1,234\.50.*, estimated at your current rates \(as of Jul 1, 2026\)/,
			),
		).toBeInTheDocument();
	});

	it("drops '(as of …)' when nothing needed a rate", async () => {
		withEstimate(estimate({ as_of: null }));
		renderWithRouter(<FinanceSummaryCard expenses donations={false} />);
		const line = await screen.findByText(/estimated at your current rates/);
		expect(line).toHaveTextContent(/1,234\.50/);
		expect(line).not.toHaveTextContent(/as of/);
	});

	it("shows no estimate line when every figure is in the estimate's own currency", async () => {
		vi.mocked(financeApi.summary).mockResolvedValue(
			financeSummary({
				net_profit_this_month: [{ currency: "EGP", amount_minor: 5000 }],
				net_profit_estimate: estimate({ amount_minor: 5000, as_of: null }),
			}),
		);
		renderWithRouter(<FinanceSummaryCard expenses donations={false} />);
		await screen.findByText("Net profit this month");
		expect(screen.queryByText(/estimated at your current rates/)).toBeNull();
	});

	it("shows no estimate line while the estimate is null", async () => {
		withEstimate(null);
		renderWithRouter(<FinanceSummaryCard expenses donations={false} />);
		await screen.findByText("Net profit this month");
		expect(screen.queryByText(/estimated at your current rates/)).toBeNull();
	});

	it("lists the currencies missing a rate, with a link only for those who may add rates", async () => {
		withEstimate(estimate({ amount_minor: null, missing: ["GBP", "KWD"], as_of: null }));
		const { unmount } = renderWithRouter(
			<CanProvider me={staffMe("widget.revenue_stats", "exchange_rate.create")}>
				<FinanceSummaryCard expenses donations={false} />
			</CanProvider>,
			{ extraPaths: ["/billing/exchange-rates"] },
		);
		const link = await screen.findByRole("link", { name: "Add rates" });
		expect(link).toHaveAttribute("href", "/billing/exchange-rates");
		expect(link.parentElement).toHaveTextContent("Add rates for GBP, KWD to see an estimate");
		unmount();
		renderWithRouter(
			<CanProvider me={staffMe("widget.revenue_stats")}>
				<FinanceSummaryCard expenses donations={false} />
			</CanProvider>,
		);
		expect(
			await screen.findByText("Add rates for GBP, KWD to see an estimate"),
		).toBeInTheDocument();
		expect(screen.queryByRole("link", { name: "Add rates" })).toBeNull();
	});

	it("says the line in Arabic", async () => {
		withEstimate(estimate());
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		try {
			renderWithRouter(<FinanceSummaryCard expenses donations={false} />);
			expect(await screen.findByText(/تقديريًا بأسعارك الحالية/)).toBeInTheDocument();
		} finally {
			await act(async () => {
				await i18n.changeLanguage("en");
			});
		}
	});
});
```

(Adjust the "shows … from the earlier tests" fixtures: `financeSummary()` now defaults `net_profit_estimate: null`, so the three earlier tests are unaffected.)

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/finance/FinanceSummaryCard.test.tsx`
Expected: FAIL (no estimate line yet).

- [ ] **Step 3: Implement**

In `FinanceSummaryCard.tsx` add imports (`Link` from `@tanstack/react-router`, `useCan`, `useAcademySettings`, `formatMoney`, `dayIn`, `NetProfitEstimate`) and an `EstimateLine` component:

```tsx
/** B3h §6: the one converted figure, labelled an estimate. Only when the
 * month has a line in a currency other than the estimate's own (an all-base
 * month needs no conversion); `as_of` is shown as a date in the academy's
 * timezone (D8). */
function EstimateLine({
	estimate,
	profit,
}: {
	estimate: NetProfitEstimate;
	profit: MoneyLine[];
}) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const settings = useAcademySettings({ enabled: Boolean(estimate.as_of) });
	if (!profit.some((line) => line.currency !== estimate.currency)) return null;
	if (estimate.amount_minor === null) {
		const rest = t("finance.estimate.missing", { codes: estimate.missing.join(", ") });
		return (
			<p className="text-sm text-muted-foreground">
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
	const amount = formatMoney(estimate.amount_minor, estimate.currency, i18n.language);
	if (estimate.as_of && settings.isPending) return null; // the date waits for the zone
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
```

In the card body, the net-profit `Lines` section becomes a wrapper so the line sits under the per-currency lines:

```tsx
{money.data.net_profit_this_month ? (
	<div className="flex flex-col gap-2">
		<Lines
			title={t("finance.home.netProfit")}
			lines={money.data.net_profit_this_month}
			empty={t("finance.home.noProfit")}
		/>
		{money.data.net_profit_estimate ? (
			<EstimateLine
				estimate={money.data.net_profit_estimate}
				profit={money.data.net_profit_this_month}
			/>
		) : null}
	</div>
) : null}
```

(`formatMoney` output goes through i18next interpolation; make sure `interpolation.escapeValue` is `false` in `lib/i18n.ts` — it is for React — so "$" and "&" print as written; the test above asserts the digits only.)

- [ ] **Step 4: Run, check and commit**

Run: `$DASH pnpm exec biome check --write src e2e`
Run: `$DASH pnpm vitest run src/features/finance`
Run: `just test-frontend && just lint-frontend`
Expected: PASS.

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(finance): estimated net profit on the home card (B3h)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The e2e journey

**Files:**
- Create: `dashboard/e2e/b3-exchange-rates.spec.ts`

**Interfaces:**
- Consumes: the whole slice through Caddy; `manage("set_features", …)` from `e2e/manage.ts`; `login`, `DEMO_URL`, `DEMO_ADMIN`, `expectLoggedIn` from `e2e/fixtures.ts`.

- [ ] **Step 1: Write the spec**

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { manage } from "./manage";

const money = (minor: number) =>
	new Intl.NumberFormat("en", { style: "currency", currency: "EGP" }).format(
		minor / 100,
	);

// B3h spec §9: the admin records a GBP expense (no seeded rate), so the home
// lists GBP as missing; adds a GBP rate, and the home shows the estimate
// with its date. The demo is EGP and the seed has SAR and USD only.
test("the admin adds a rate and the home turns a missing currency into an estimate", async ({
	page,
}) => {
	// seed_dev.FEATURES already enables every BUILT feature, but a database
	// seeded before B3h would not have it: switch what the journey needs.
	manage(
		"set_features",
		"demo",
		"--on",
		"invoices",
		"expenses",
		"exchange_rates",
	);
	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// 0. A clean slate: no GBP rate left by an earlier run.
	await page.goto(`${DEMO_URL}/app/billing/exchange-rates`);
	await expect(page.getByRole("table")).toBeVisible();
	const leftover = page.getByRole("row", { name: /GBP/ });
	if ((await leftover.count()) > 0) {
		await leftover.getByRole("button", { name: "Delete" }).click();
		await page.getByRole("button", { name: "Delete this rate" }).click();
		await expect(page.getByText("Rate deleted.")).toBeVisible();
		await expect(leftover).toHaveCount(0);
	}

	// 1. The seeded rates read as "1 SAR = 13 EGP" (EGP demo).
	await expect(page.getByText("1 SAR = 13 EGP")).toBeVisible();
	await expect(page.getByText("1 USD = 48.5 EGP")).toBeVisible();

	// 2. A GBP expense: GBP has no rate, so the home lists it as missing.
	await page.goto(`${DEMO_URL}/app/billing/expenses`);
	await page.getByRole("button", { name: "Add expense" }).click();
	const expense = page.getByRole("dialog");
	await expect(expense.getByLabel(/^Currency/)).toBeEnabled();
	await expect(expense.getByLabel(/^Currency/)).not.toHaveValue("");
	await expense.getByLabel(/^Title/).fill(`E2E GBP spend ${Date.now()}`);
	await expense.getByLabel(/^Type/).selectOption("software");
	await expense.getByLabel(/^Currency/).selectOption("GBP");
	await expense.getByLabel(/^Amount/).fill("10");
	await expense.getByRole("button", { name: "Save expense" }).click();
	await expect(page.getByText("Expense saved.")).toBeVisible();
	await page.goto(`${DEMO_URL}/app/`);
	await expect(
		page.getByText("Add rates for GBP to see an estimate"),
	).toBeVisible();

	// 3. Add the GBP rate; the home shows the estimate with its date.
	await page.getByRole("link", { name: "Add rates" }).click();
	await expect(page).toHaveURL(/\/app\/billing\/exchange-rates$/);
	await page.getByRole("button", { name: "Add rate" }).click();
	const dialog = page.getByRole("dialog");
	await dialog.getByLabel(/^Currency/).selectOption("GBP");
	await dialog.getByLabel(/^Rate/).fill("60.5");
	await dialog.getByRole("button", { name: "Save rate" }).click();
	await expect(page.getByText("1 GBP = 60.5 EGP")).toBeVisible();

	const summary = await (
		await page.request.get(`${DEMO_URL}/api/v1/finance/summary/`)
	).json();
	const estimate = summary.net_profit_estimate;
	expect(estimate.missing).toEqual([]);
	await page.goto(`${DEMO_URL}/app/`);
	const line = page.getByText(/estimated at your current rates \(as of .+\)/);
	await expect(line).toBeVisible();
	await expect(line).toContainText(money(estimate.amount_minor));
	await expect(page.getByText(/Add rates for/)).toHaveCount(0);
});
```

- [ ] **Step 2: Run it against this stream's fresh stack**

Run: `just e2e e2e/b3-exchange-rates.spec.ts` (stack up via `just dev-backend`; rebuild images first if dependencies changed, and use a fresh stack before trusting the result).
Expected: PASS. Run it twice: the second run must pass too (step 0 clears the GBP row).

- [ ] **Step 3: Commit**

```bash
git -C dashboard add e2e/b3-exchange-rates.spec.ts
git -C dashboard commit -m "test(e2e): exchange rates and the estimate on the home (B3h)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Gates

**Files:** none new; fix what the gates find in the task that owns it.

- [ ] **Step 1: Backend**

Run: `just test-backend`
Expected: PASS, total coverage ≥ 80 %. Check `etqan/finance/services/convert.py`, `rates.py` and the new views are fully covered (`--cov-report=term-missing` lists any missed line).

- [ ] **Step 2: Lint and boundaries**

Run: `just lint` (ruff, biome, the colour check) and `just check-boundaries` (`lint-imports`).
Expected: PASS. The existing finance contracts already allow `etqan.academy` services and `etqan.platform`; no `pyproject.toml` edit is needed. If a contract fails, do not weaken it: move the import behind a service.

- [ ] **Step 3: Dashboard**

Run: `set -a; . ./.env.stream; set +a; HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm test:coverage`
Run: `just test-frontend`
Expected: PASS; lines and statements ≥ 80, branches and functions ≥ 70.

- [ ] **Step 4: End to end**

Run: `just e2e` (the whole suite, on a fresh stack).
Expected: PASS, including `b3-finance.spec.ts` (the summary gained a key; its assertions read named keys, so nothing there changes).

- [ ] **Step 5: Record the decision and report**

The slice's `decide` entry (ledger D31 already records H-2..H-9) needs nothing more. In the PR descriptions note: the new migration `finance.0002`, the new feature `exchange_rates` (off by default), the new resource `exchange_rate`, and that `finance/summary/` gained `net_profit_estimate`. Open PRs as Plan 15 did (`gh pr create --repo Etqan-agency/etqan_tutor_backend`, `…_dashboard`, then meta with `--repo Etqan-agency/etqan_tutor`); bump submodule pointers in meta only after both merge, with explicit paths (never `git commit -a`).

---

## Self-review against the spec

- **H-1** (rates in finance, one per currency, base stamped, no history, no fetching): Task 1 model; Task 2 `create_rate`. **H-2** (decimal, JSON string only, regex, > 0, output string, base takes no row): Task 2 `clean_rate`, `rate_text`, tests for `10`, `0.0000000001`, `4.1200000000`, number, 11/11 digits, spaces; Task 4 API 400s. **H-3** (stale, `own_currency` wins, PATCH 400 before write, switch-back): Task 2 and Task 4 tests; `convert_estimate` ignores both (Task 3). **H-4** (old after 30 days, `as_of`, "rates as of"): Task 2 `is_old`, Task 3 `as_of`, Tasks 5-6 UI. **H-5** (exact `localcontext` prec 60, Inexact trapped, quantize once ROUND_HALF_UP, no per-line rounding): Task 3, D4. **H-6** (no partial, `missing`, zero lines skipped): Task 3. **H-7** ("at your current rates"): the estimate string, Task 6. **H-8** (`convert_estimate(lines) -> Estimate`, `None` while off): Task 3. **H-9** (`exchange_rates`, `requires=()`, `default=False`; summary rule): Tasks 1 and 3. **H-10** (resource `exchange_rate`, four codes, estimate rides on `widget.revenue_stats`, no `NotImpersonating`): Tasks 1 and 4. **H-11** (en and ar): Task 5 locales, real Arabic.
- **§4 behaviour:** GET/POST/PATCH/DELETE and the concurrent-POST `IntegrityError`: Tasks 2 and 4. **§5:** routes in Task 4. **§6:** page, badges, add/edit/delete, estimate three states, all-base hidden, link only with `exchange_rate.create`, as-of in academy timezone, `BILLING_PAGES`, nav, `FeatureCode`, `FEATURE_SCREENS`/`FEATURE_WORDS`: Tasks 5 and 6. **§7** (no new package or env var; B3 markers): respected. **§8 seeds:** Task 4. **§9 tests:** each backend and dashboard bullet maps to a test above; e2e is Task 7.

**Spec gaps and contradictions found (spec not edited):**
1. §7 says `exchange_rates` is registered "with `requires`", while H-9 says `requires=()`. The plan follows H-9.
2. `as_of` when the amount is `null` (a rate is missing) is unspecified. The plan returns `None` (D2).
3. The order of `missing` is unspecified. The plan sorts it.
4. §6's "≈ {amount} {currency}" is one formatted money string in the plan (D7), since `formatMoney` already carries the currency.
5. §9's e2e step 1 says the demo already has every BUILT feature on; an older seeded database does not, so the spec's journey would silently 404 there. The plan keeps a `set_features` call.
6. The e2e needs a clean slate for GBP (rates are unique per currency, so a second run would have no "missing" state); the spec does not say how to reset it. The plan deletes a leftover GBP row through the UI.
7. H-3 says a PATCH on an `own_currency` row is a 400 on `currency`, but does not say what the dashboard offers; the plan hides Edit for that row (D9).
