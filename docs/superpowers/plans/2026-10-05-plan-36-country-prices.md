# Plan 36 — Slice B3d: Country prices and local payment methods — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Slice:** B3d
**Requires:** — (no other phase's slice; B3g and B3h merged first; includes the delegated R2 hook in scheduling)

**Goal:** An academy sets, per package, the price and currency a student of each country pays, and a new or renewed subscription for that student takes it (the B2-owned hook, ledger R2, delegated to B3). For each country the academy also lists local ways to pay (bank transfer, InstaPay, …), each with an optional logo and plain-text instructions, and a family sees them on its unpaid invoice.

**Architecture:**
- **Backend, catalogue (B3 owns pricing):** one model `PackageCountryPrice`, the resolver `package_price(package, *, country) -> Price`, a list-replace route `catalogue/packages/<id>/country-prices/` behind the feature `country_pricing` (flipped to built in place, off by default), and an ungated read `catalogue/packages/<id>/price/[?student=]` the office forms prefill from.
- **Backend, billing:** `BillingSettings` (one row, `local_payment_enabled`), `LocalPaymentCountry`, `LocalPaymentMethod` (logo through `etqan.platform.uploads`), their routes under `invoices`, a new access resource `payment_method`, and `local_methods` on the invoice detail payload.
- **The hook (R2, under a ledger claim):** `scheduling.create_subscription` / `renew_subscription` resolve their default price and currency through `catalogue.services.package_price` and take an optional keyword-only `currency`; the create and renew bodies take an optional `currency`. Dashboard `TermFields` prefills from `usePackagePrice`, and the subscription form and renew dialog send the currency they converted with.
- **Dashboard:** a "Prices by country" card on the package page, a Billing → Local payment methods page (switch, country toggles, add/edit dialog with a logo), a "Local payment" card on the payment-gateways settings page, and a "Pay locally" block on the invoice page.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18, Pillow; React 19 + TanStack Router/Query, react-hook-form + zod 4, i18next, `Intl`; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-05-b3d-countries-currencies-design.md` (decisions D-1..D-21, review-revised). Ledger: D23 (the subscription price hook), D25 (`ValidationError.code`), D2 (no academy HTML on the academy origin), D12 (uploads), D19 (`NotImpersonating` only on money-moving routes: none here), D11/D22 (en and ar only), request R2 (the hook text, delegated by B2 to B3). Format and conventions follow Plan 35 (`2026-10-05-plan-35-exchange-rates.md`).

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), and the meta worktree `/home/abdulkhalek/Projects/etqan_tutor-wt/b3` (trunk `master`). `marketing/` is not touched.
- Work on a `feat/b3d-country-prices` branch in `backend/` and `dashboard/`. B3h is built first: create the branch from each repo's trunk once B3h has merged (`git -C backend switch -c feat/b3d-country-prices origin/main`, same for `dashboard`); if B3h has not merged yet, branch from `feat/b3h-exchange-rates` and rebase onto trunk after it merges. Check with `git -C backend branch --show-current` first.
- **Never run any `git submodule` subcommand.** Commit in the repo the change lives in (`git -C backend …`, `git -C dashboard …`), never the submodule pointers in meta, and never `git commit -a` in meta.
- Commits use Conventional Commits and end with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

**Ownership and claims.** B3 owns `etqan.catalogue` pricing, `etqan.billing`, `features/catalogue`, `features/billing`, `features/finance`. The scheduling files are B2's: Task 9 Step 1 claims them in the ledger before any of them is edited, and Task 10's last step releases them. The scheduling service changes are **additive only**: `currency: str | None = None`, keyword-only; every existing scheduling test passes unchanged with `country_pricing` off.

**Shared lists:** add lines only under the `── phase B3 ──` markers: the feature registry (`etqan/platform/features.py`; `country_pricing` is flipped **in place**, where it already sits), the access `RESOURCES` (`etqan/access/registry.py`), `seed_academy` (`seed_dev.py`), the dashboard `NAV_ITEMS`. Test tables without markers take additive edits only (`access/tests/test_routes.py`, `access/tests/test_registry.py`, `platform/tests/test_features.py`, `tenants/tests/test_seed_dev.py`, `features/shell/nav.test.ts`, `routes/permissions.test.ts`, `features/identity/schemas.ts`, `locales/*/errors.json`); keep both sides on a rebase conflict. Translations go in the existing `catalogue.json` and `billing.json` area files (one file per area).

**Features:** `country_pricing` becomes built in place with `default=False` (TutorHamster's flag; `_built(..., default=False)`). Local methods sit under `invoices` plus the billing setting `local_payment_enabled` (default false), which is a setting, not a feature (D-11).

**Money:** integer minor units plus an ISO currency, converted in the dashboard only with `toMinor` / `toMajor` in the row's own currency. Stored instants are UTC.

**Language:** only en and ar strings (D11), real Arabic: `locales.test.ts` fails when an ar value equals its en value.

**Dashboard forms:** dialogs use `defaultValues` + `useFillOnOpen` (from `@/features/finance/shared`), never `values:`. A form that renders one of two field sets (add vs edit) keys each branch (`key={method?.id ?? "new"}`) so no input state leaks between them.

**Backend commands.** Run from the meta worktree, inside this stream's stack (`just dev-backend`). Load the ports first:
```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/b3
set -a && . ./.env.stream && set +a
DJ="docker compose -f docker-compose.local.yml exec -T django"
```
- Targeted tests: `$DJ pytest etqan/catalogue -q` (add `--create-db` once after a task adds a migration).
- Migrations: `$DJ python manage.py makemigrations catalogue` / `… billing`. Never run `manage.py`, `migrate` or e2e any other way.
- Format and lint: `$DJ sh -c 'ruff check --fix . && ruff format .'`, `$DJ lint-imports`.
- Whole suite: `just test-backend`. Watch `PLR0913` (keyword-only signatures that mirror an API body carry `# noqa: PLR0913 -- <reason>`).

**Dashboard commands.** From the meta worktree (`.env.stream` loaded as above):
```bash
DASH="docker compose -f docker-compose.local.yml run --rm dashboard"
export HOST_UID=$(id -u) HOST_GID=$(id -g)
```
- One test file: `$DASH pnpm vitest run src/features/catalogue/<file>`.
- Full dashboard tests with coverage: `set -a; . ./.env.stream; set +a; HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm test:coverage`.
- Types: `just test-frontend` (this is `tsc --noEmit` only, not the tests). Lint: `just lint-frontend` (`biome ci . && node scripts/check-colors.mjs`): semantic tokens only, no hex, no Tailwind palette utilities.
- New route files regenerate `src/routeTree.gen.ts` with `$DASH pnpm exec vite build` before `tsc`; it is generated, never hand-edited.
- Format: `$DASH pnpm exec biome check --write src e2e`.

**Gates before queuing:** `just test`, `just lint`, `just e2e e2e/b3-country-prices.spec.ts` (plus the full `just e2e`), backend coverage ≥ 80 %, dashboard lines and statements ≥ 80, branches and functions ≥ 70. B3d is not queued until Tasks 9–10 (the hook) are committed (spec D-6).

## Decisions (gaps the spec left, filled here)

| # | Decision |
|---|---|
| P1 | **D-20 / ledger D25 is already on trunk**: B9c gave `ValidationError` its optional `code` (default `validation_error`) and `etqan.platform.drf.exception_handler` adds `code` to the body whenever it is not the default. B3d builds nothing there; Task 9 adds the tests that pin it (handler unit test and the hook's 400 body). |
| P2 | `LOGO_PATH = tenant_upload_path("payment-methods")` keeps the spec's folder, but the helper names the callable `payment-methods_path`, which is not a Python identifier: migrations serialise `module.qualname`. So `billing/models.py` sets `LOGO_PATH.__module__ = __name__` and `LOGO_PATH.__name__ = LOGO_PATH.__qualname__ = "LOGO_PATH"` (as `site/uploads.py` renames its paths). |
| P3 | `logo_url` is `method.logo.url` or `null`: `/media/tenants/<schema>/payment-methods/<uuid>.png` locally (same-origin through Caddy's `/media/*`), the S3 URL in production. No request is needed, so `payloads.invoice_detail` stays request-free. |
| P4 | `GET billing/local-methods/` answers `countries` as the union of the `LocalPaymentCountry` rows and the countries that have methods (unfiltered), sorted, each with its effective `enabled` (a method's country without a row is enabled, D-10). |
| P5 | The nav item hides while the setting is off through a new optional `NavItem.setting?: NavSetting` (`"localPayment"`), filtered by `withSettings(items, settings)` in `nav.ts`. `AppShell` fetches `billing/settings/` only while such an item survives the code and feature filters. Additive shell change, as ledger D27's badge was. |
| P6 | `set_country_prices` locks the package row (`select_for_update`) before it deletes and re-creates, so two saves of one package run one after the other instead of colliding on the unique constraint (a 500). A body that is not a JSON list is a 400 on `rows`; more than 250 rows is a 400 on `rows`. `price_minor` must be a JSON integer ≥ 0 (a bool or a float is refused). |
| P7 | The price route: `?student` that is not a positive integer is a 400 on `student`; a staff account without `student.view_any` asking with `?student` is a 403, checked before the lookup. Without `?student` the answer is the package's own price whatever the switch says. |
| P8 | **Dashboard price prefill, one path:** `TermFields` always reads `usePackagePrice(package, studentId)`; without a student the route answers the package's own price. The price field is reset each time the key (package, student, resolved currency) changes; the renew dialog passes `keep` (the subscription's price and currency), and when the resolved currency equals `keep.currency` the field takes `keep.price_minor` (P4-10). Submit is disabled while the price is pending or failed; a failure shows "The price for this student could not be loaded." A 400 with code `catalogue.price_currency_changed` refetches the price queries, so the field resets to the new resolved price. |
| P9 | `RenewDialog` moves from `values:` to `defaultValues` + `useFillOnOpen` while it is under the claim (house rule), and asks for the price only while open. |
| P10 | **Group bundles (R2 item 4, D-5)**: B2f is still at `spec` in the ledger, so per R2's own text item (4) becomes part of B2f's build and is not in this plan. **B2e's conversion form** is `SubscriptionForm` with a `trial` prop (B2e branch): it passes `watch("student")` like any create, so it is covered without a change of its own. Rebase on whichever of B2e/B2f merges first; their changes to the same signatures are additive. | Keys are dot-form per D34 (`rows.<i>.<field>`).
| P11 | The 400's translated text lives in `errors.json` as `errors.catalogue.price_currency_changed` (the form error helper turns any `code` into `errors.<code>`). |
| P12 | Multipart booleans: DRF reads a missing checkbox in a multipart body as `False`. `LocalMethodInput.is_active` is an `OptionalBoolean` (`default_empty_html = empty`), so a create that leaves it out creates an **active** method. |
| P13 | The logo is read from `request.data` outside the serializer: absent → unchanged; `""` (or null) → cleared; an uploaded file → checked and stored; anything else → 400 on `logo`. A replaced, cleared or deleted logo's file is deleted in `transaction.on_commit`, so a rolled-back request keeps it. |
| P14 | The e2e file is `e2e/b3-country-prices.spec.ts` (the spec §9 says `b3-countries.spec.ts`; the orchestrator's name wins). |
| P15 | Seeds run for the demo academy only (as `seed_b9`), each step only when its table is empty (the student: when absent). |
| P16 | `online._nothing_due` becomes the public `online.nothing_due` (two callers), so `local_methods_for` uses the same "void or nothing due" rule without a private import. |

## Review Focus

1. **A student whose country has a price row while `country_pricing` is off** gets the package's own price and currency, on the price route and on a created subscription (D-3). Tests in Task 1 (resolver), Task 2 (route) and Task 9 (hook).
2. **The resolved currency changes under an open form** (the country row or the student's country is edited after the prefill): the server refuses the stale currency with a 400 `catalogue.price_currency_changed` on `price_minor`, the form shows it, refetches the price and resets the field. Tests in Task 9 (backend) and Task 10 (dashboard).
3. **A repeated country or a bad row deep in a PUT**: a 400 keyed `rows.i.<field>` on the later row and nothing written (the old list stays). Tests in Task 1 and Task 2.
4. **Instructions holding HTML, a link and Windows line breaks**: stored trimmed with `\n`, rendered as text with the breaks kept, no element and no anchor made. Tests in Task 3 (service) and Task 8 (invoice block).
5. **A logo replaced, cleared or deleted, then the request rolled back**: the old file stays; on commit it is removed. A multipart create with no `is_active` makes an active method (P12). Tests in Task 3 and Task 4.

## File structure

**Backend (`backend/`)**

| Path | Responsibility |
|---|---|
| `etqan/catalogue/models.py`, `migrations/0002_*.py` (generated) | `PackageCountryPrice` |
| `etqan/catalogue/services.py` | `Price`, `package_price`, `price_for_student`, `country_prices`, `set_country_prices`, `copy_country_prices`; `duplicate_package` atomic |
| `etqan/catalogue/api/views.py`, `urls.py` | `CountryPricesView`, `PackagePriceView` |
| `etqan/catalogue/tests/test_country_prices.py`, `test_country_prices_api.py` | new tests |
| `etqan/billing/models.py`, `migrations/0008_*.py` (generated) | `BillingSettings`, `LocalPaymentCountry`, `LocalPaymentMethod`, `LOGO_PATH` |
| `etqan/billing/services/local.py`, `services/__init__.py`, `services/online.py` | local methods, settings, `local_methods_for`; `nothing_due` made public |
| `etqan/billing/api/serializers.py`, `payloads.py`, `views.py`, `urls.py` | settings, methods, countries routes; `local_methods` on the invoice detail |
| `etqan/billing/tests/test_local_methods.py`, `test_local_methods_api.py` | new tests |
| `etqan/platform/features.py`, `platform/tests/test_features.py`, `platform/tests/test_drf.py` | the feature; D25 pin |
| `etqan/access/registry.py`, `access/tests/test_registry.py`, `access/tests/test_routes.py` | `payment_method`, the route matrix |
| `etqan/tenants/seeds/countries.py`, `tenants/management/commands/seed_dev.py`, `tenants/tests/test_seed_countries.py`, `tenants/tests/test_seed_dev.py` | `seed_countries` |
| `etqan/scheduling/services/subscriptions.py`, `scheduling/api/serializers.py`, `scheduling/tests/test_country_pricing.py` | the R2 hook (claimed) |

**Dashboard (`dashboard/`)**

| Path | Responsibility |
|---|---|
| `src/features/catalogue/schemas.ts`, `api.ts`, `queries.ts`, `index.ts` | country prices and the resolved price; `usePackagePrice` |
| `src/features/catalogue/CountryPricesCard.tsx` (+ test) | the package page card |
| `src/routes/_authed/catalogue.packages.$packageId.tsx` | renders the card |
| `src/features/billing/schemas.ts`, `api.ts`, `queries.ts`, `index.ts` | settings, local methods, `InvoiceDetail.local_methods` |
| `src/features/billing/LocalMethodsPage.tsx`, `LocalMethodDialog.tsx`, `LocalPayment.tsx` (+ tests) | the page, the dialog, the switch, the settings card, the invoice block |
| `src/features/billing/InvoicePage.tsx` | renders the invoice block |
| `src/routes/_authed/billing.local-methods.tsx`, `settings.gateways.tsx` | the page route; the settings card |
| `src/features/finance/landing.ts` (+ test) | `BILLING_PAGES` entry after `/billing/exchange-rates` |
| `src/features/shell/nav.ts`, `AppShell.tsx`, `nav.test.ts` | the nav item and `withSettings` |
| `src/features/identity/schemas.ts`, `src/routes/permissions.test.ts` | `country_pricing`; `FEATURE_SCREENS` / `FEATURE_WORDS` |
| `src/locales/{en,ar}/catalogue.json`, `billing.json`, `errors.json` | strings |
| `src/test/catalogue-fixtures.ts` (new), `src/test/billing-fixtures.ts` | fixtures |
| `src/features/scheduling/TermFields.tsx`, `SubscriptionForm.tsx`, `RenewDialog.tsx`, `schemas.ts` (+ tests) | the R2 hook (claimed) |
| `e2e/b3-country-prices.spec.ts` | the journey through Caddy |

---

### Task 1: Country prices: the model, the feature and the resolver

**Files:**
- Modify: `backend/etqan/catalogue/models.py`, `backend/etqan/catalogue/services.py`, `backend/etqan/platform/features.py` (in place), `backend/etqan/platform/tests/test_features.py`
- Create: `backend/etqan/catalogue/migrations/0002_*.py` (generated), `backend/etqan/catalogue/tests/test_country_prices.py`

**Interfaces:**
- Produces:
  - `etqan.catalogue.models.PackageCountryPrice(package FK related_name="country_prices", country, price_minor, currency, updated_at)`, unique `(package, country)`, ordered by country.
  - `catalogue.services.Price` — frozen dataclass `(price_minor: int, currency: str, country: str, source: str)`; `source` is `"country"` or `"package"`.
  - `package_price(package, *, country: str) -> Price`; `price_for_student(package, *, student_id: int) -> Price` (400 on `student` when the profile is missing); `country_prices(package) -> list[PackageCountryPrice]`; `set_country_prices(package, rows: object) -> list[PackageCountryPrice]`; `copy_country_prices(source, copy) -> None`; `MAX_COUNTRY_PRICES = 250`.
  - Feature code `country_pricing` built, `default=False`.

- [ ] **Step 1: Write the failing tests**

In `backend/etqan/platform/tests/test_features.py`, in `BUILT`, insert after `"articles": False,` (registry order) and add B3d to the comment above the block ("…, B8's url_redirects and articles, B3d's country_pricing, B3's donations, …"):

```python
    "country_pricing": False,
```

Create `backend/etqan/catalogue/tests/test_country_prices.py`:

```python
"""B3d D-1..D-3, D-9: country prices, the resolver, duplicating and deleting."""

import pytest

from etqan.catalogue import services
from etqan.catalogue.models import Package
from etqan.catalogue.models import PackageCountryPrice
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db

PACKAGE = {
    "name_ar": "شهري",
    "name_en": "Monthly",
    "sessions_per_week": 2,
    "session_minutes": 45,
    "duration_value": 1,
    "duration_unit": "month",
    "price_minor": 150000,
    "currency": "EGP",
}


@pytest.fixture
def package():
    return services.create_package(**PACKAGE)


def sa(price_minor=45000, currency="SAR"):
    return {"country": "SA", "price_minor": price_minor, "currency": currency}


def stored(package):
    return [
        (r.country, r.price_minor, r.currency)
        for r in services.country_prices(package)
    ]


def test_the_resolver_answers_the_row_only_while_the_switch_is_on(package, set_features):
    services.set_country_prices(package, [sa()])
    set_features(country_pricing=False)
    assert services.package_price(package, country="SA") == services.Price(
        150000, "EGP", "SA", "package"
    )
    set_features(country_pricing=True)
    assert services.package_price(package, country="SA") == services.Price(
        45000, "SAR", "SA", "country"
    )
    # no row for the country, and a blank country: the package's own price
    assert services.package_price(package, country="EG") == services.Price(
        150000, "EGP", "EG", "package"
    )
    assert services.package_price(package, country="") == services.Price(
        150000, "EGP", "", "package"
    )


def test_price_for_student_reads_the_profile_country(package, set_features):
    set_features(country_pricing=True)
    services.set_country_prices(package, [sa()])
    karim = identity_services.create_person(
        "student", full_name="Karim", profile={"country": "SA"}
    )
    yusuf = identity_services.create_person("student", full_name="Yusuf")
    assert services.price_for_student(package, student_id=karim.pk).source == "country"
    assert services.price_for_student(package, student_id=yusuf.pk) == services.Price(
        150000, "EGP", "", "package"
    )
    with pytest.raises(ValidationError) as caught:
        services.price_for_student(package, student_id=999999)
    assert caught.value.field == "student"


def test_set_country_prices_replaces_the_whole_list_and_cleans_codes(package):
    services.set_country_prices(package, [sa(), {"country": "eg", "price_minor": 0, "currency": "egp"}])
    assert stored(package) == [("EG", 0, "EGP"), ("SA", 45000, "SAR")]
    services.set_country_prices(package, [sa(50000)])
    assert stored(package) == [("SA", 50000, "SAR")]
    services.set_country_prices(package, [])
    assert stored(package) == []


@pytest.mark.parametrize(
    ("rows", "field"),
    [
        ([{"country": "", "price_minor": 1, "currency": "SAR"}], "rows.0.country"),
        ([{"country": "SAU", "price_minor": 1, "currency": "SAR"}], "rows.0.country"),
        ([{"price_minor": 1, "currency": "SAR"}], "rows.0.country"),
        ([sa(), {"country": "sa", "price_minor": 1, "currency": "SAR"}], "rows.1.country"),
        ([sa(), {"country": "EG", "price_minor": 1, "currency": "EG"}], "rows.1.currency"),
        ([sa(-1)], "rows.0.price_minor"),
        ([sa(1.5)], "rows.0.price_minor"),
        ([sa(True)], "rows.0.price_minor"),
        ([sa("100")], "rows.0.price_minor"),
        ([{"country": 12, "price_minor": 1, "currency": "SAR"}], "rows.0.country"),
        (["SA"], "rows.0.country"),
        ({"country": "SA"}, "rows"),
        ([sa()] * 251, "rows"),
    ],
)
def test_a_bad_list_is_refused_on_its_row_and_nothing_changes(package, rows, field):
    services.set_country_prices(package, [sa(1)])
    with pytest.raises(ValidationError) as caught:
        services.set_country_prices(package, rows)
    assert caught.value.field == field
    assert stored(package) == [("SA", 1, "SAR")]


def test_250_rows_are_allowed():
    package = services.create_package(**PACKAGE)
    codes = [f"{a}{b}" for a in "ABCDEFGHIJ" for b in "ABCDEFGHIJKLMNOPQRSTUVWXY"]
    services.set_country_prices(
        package, [{"country": c, "price_minor": 1, "currency": "USD"} for c in codes]
    )
    assert len(stored(package)) == 250


def test_duplicating_copies_the_rows_and_deleting_cascades(package):
    services.set_country_prices(package, [sa()])
    copy = services.duplicate_package(package)
    assert stored(copy) == [("SA", 45000, "SAR")]
    services.delete_package(copy)
    assert not PackageCountryPrice.objects.filter(package_id=copy.pk).exists()
    assert stored(package) == [("SA", 45000, "SAR")]


def test_duplicating_is_one_transaction(package, monkeypatch):
    services.set_country_prices(package, [sa()])

    def boom(source, copy):
        raise RuntimeError("copy failed")

    monkeypatch.setattr(services, "copy_country_prices", boom)
    before = Package.objects.count()
    with pytest.raises(RuntimeError):
        services.duplicate_package(package)
    assert Package.objects.count() == before
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/catalogue/tests/test_country_prices.py etqan/platform/tests/test_features.py -q`
Expected: FAIL (`ImportError: PackageCountryPrice`; `country_pricing` not in `BUILT`).

- [ ] **Step 3: Implement the model and the feature**

`backend/etqan/catalogue/models.py`, append:

```python
class PackageCountryPrice(models.Model):
    """B3d D-1: what a student of one country pays for a package, in any
    currency. The package's own price stays the default elsewhere."""

    package = models.ForeignKey(
        Package, on_delete=models.CASCADE, related_name="country_prices"
    )
    # Catalogue never imports identity's models (plan D15): its own check.
    country = models.CharField(
        max_length=2, validators=[RegexValidator(r"^[A-Z]{2}$")]
    )
    price_minor = models.BigIntegerField(validators=[MinValueValidator(0)])
    currency = models.CharField(
        max_length=3, validators=[RegexValidator(r"^[A-Z]{3}$")]
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["country", "id"]
        constraints = [
            models.UniqueConstraint(
                fields=["package", "country"], name="catalogue_country_price_unique"
            )
        ]

    def __str__(self):
        return f"PackageCountryPrice<{self.package_id}, {self.country}>"
```

Run: `$DJ python manage.py makemigrations catalogue` (commit what it writes; the name may differ).

`backend/etqan/platform/features.py`: replace the existing

```python
    _later(
        "country_pricing", "Per-country pricing", "نظام التسعير حسب الدولة", "money"
    ),
```

in place with

```python
    # Phase B3, slice B3d (D-18): built, off by default (TutorHamster's flag).
    _built(
        "country_pricing",
        "Per-country pricing",
        "نظام التسعير حسب الدولة",
        "money",
        default=False,
    ),
```

- [ ] **Step 4: Implement the services**

`backend/etqan/catalogue/services.py`: add the imports `from dataclasses import dataclass`, `from etqan.catalogue.models import PackageCountryPrice`, `from etqan.platform import features`, `from etqan.platform.validators import clean_country`; make `duplicate_package` atomic and copy the rows:

```python
@transaction.atomic
def duplicate_package(package: Package) -> Package:
    copy = Package.objects.get(pk=package.pk)
    copy.pk = None
    copy.name_ar = _copy_name(package, "ar")
    copy.name_en = _copy_name(package, "en")
    copy.is_active = False
    copy.save()
    # B3d D-9: the copy sells at the same country prices.
    copy_country_prices(package, copy)
    return copy
```

and append a section:

```python
# ── Country prices (phase B3, slice B3d) ─────────────────────────────────────

MAX_COUNTRY_PRICES = 250


@dataclass(frozen=True)
class Price:
    """D-3: what a package costs for one country. ``country`` is the one asked
    for (blank when none), whichever ``source`` answered."""

    price_minor: int
    currency: str
    country: str
    source: str  # "country" | "package"


def country_prices(package: Package) -> list[PackageCountryPrice]:
    return list(package.country_prices.order_by("country"))


def _row_error(index: int, field: str, message: str) -> ValidationError:
    return ValidationError(message, field=f"rows.{index}.{field}")


def _clean_country_row(index: int, row) -> dict:
    if not isinstance(row, dict):
        raise _row_error(index, "country", "Each row needs a country, a price and a currency.")
    try:
        # str(): a JSON number in a code must be a 400, not a 500.
        country = clean_country(str(row.get("country") or ""), "country")
        currency = clean_currency(str(row.get("currency") or ""), "currency")
    except ValidationError as exc:
        raise _row_error(index, exc.field, exc.message) from None
    if not country:
        raise _row_error(index, "country", "Choose a country.")
    price = row.get("price_minor")
    # A bool is an int in Python; a JSON true is not a price.
    if isinstance(price, bool) or not isinstance(price, int) or price < 0:
        raise _row_error(index, "price_minor", "Enter a price of 0 or more.")
    return {"country": country, "price_minor": price, "currency": currency}


@transaction.atomic
def set_country_prices(package: Package, rows) -> list[PackageCountryPrice]:
    """D-9: the whole list, replaced in one transaction (plan P6)."""
    if not isinstance(rows, list):
        raise ValidationError("Send the list of country prices.", field="rows")
    if len(rows) > MAX_COUNTRY_PRICES:
        raise ValidationError(
            f"Use at most {MAX_COUNTRY_PRICES} countries.", field="rows"
        )
    cleaned, seen = [], set()
    for index, row in enumerate(rows):
        values = _clean_country_row(index, row)
        if values["country"] in seen:
            raise _row_error(index, "country", "This country is already in the list.")
        seen.add(values["country"])
        cleaned.append(values)
    # Locked: two saves of one package run one after the other (plan P6).
    Package.objects.select_for_update().filter(pk=package.pk).first()
    PackageCountryPrice.objects.filter(package=package).delete()
    PackageCountryPrice.objects.bulk_create(
        PackageCountryPrice(package=package, **values) for values in cleaned
    )
    return country_prices(package)


def copy_country_prices(source: Package, copy: Package) -> None:
    PackageCountryPrice.objects.bulk_create(
        PackageCountryPrice(
            package=copy,
            country=row.country,
            price_minor=row.price_minor,
            currency=row.currency,
        )
        for row in source.country_prices.all()
    )


def package_price(package: Package, *, country: str) -> Price:
    """D-3, the one resolver: the country's row while `country_pricing` is on
    and one exists, else the package's own price."""
    country = country or ""
    if country and features.enabled("country_pricing"):
        row = package.country_prices.filter(country=country).first()
        if row is not None:
            return Price(row.price_minor, row.currency, country, "country")
    return Price(package.price_minor, package.currency, country, "package")


def price_for_student(package: Package, *, student_id: int) -> Price:
    """§4.1: the price for a student's country (D-2: their profile's)."""
    profile = identity_services.get_student_profile(student_id)
    if profile is None:
        raise ValidationError("Choose a student.", field="student")
    return package_price(package, country=profile.country)
```

(`_clean_country_row`'s first message line is longer than 88 characters: let `ruff format` wrap it.)

- [ ] **Step 5: Run the tests, format, lint, commit**

Run: `$DJ pytest etqan/catalogue etqan/platform -q --create-db`
Expected: PASS.
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`
Expected: clean (catalogue already imports `etqan.identity.services` and `etqan.platform`).

```bash
git -C backend add etqan/catalogue etqan/platform/features.py etqan/platform/tests/test_features.py
git -C backend commit -m "feat(catalogue): country prices, the price resolver and country_pricing (B3d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Country prices: the API and the route matrix

**Files:**
- Modify: `backend/etqan/catalogue/api/views.py`, `backend/etqan/catalogue/api/urls.py`, `backend/etqan/access/tests/test_routes.py`
- Create: `backend/etqan/catalogue/tests/test_country_prices_api.py`

**Interfaces:**
- Consumes: Task 1 services.
- Produces:
  - `GET/PUT /api/v1/catalogue/packages/<id>/country-prices/` → `[{country, price_minor, currency}]` ordered by country (feature `country_pricing`; `package.view_any` / `package.update`).
  - `GET /api/v1/catalogue/packages/<id>/price/[?student=<user id>]` → `{price_minor, currency, source}` (`package.view_any`, plus `student.view_any` with `?student`; no feature gate).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/access/tests/test_routes.py`:
- `ROUTES`, after the last phase B3 rows (B3g's links, B3h's exchange rates):

```python
    # Phase B3, slice B3d: country prices and the resolved price.
    ("GET", f"/api/v1/catalogue/packages/{N}/country-prices/", "package.view_any"),
    ("PUT", f"/api/v1/catalogue/packages/{N}/country-prices/", "package.update"),
    ("GET", f"/api/v1/catalogue/packages/{N}/price/", "package.view_any"),
```

- `FEATURES`, after the B3h block:

```python
    # Phase B3, slice B3d.
    **dict.fromkeys(
        (
            ("GET", f"/api/v1/catalogue/packages/{N}/country-prices/"),
            ("PUT", f"/api/v1/catalogue/packages/{N}/country-prices/"),
        ),
        "country_pricing",
    ),
```

- `FEATURE_WORDS`: `"/country-prices/": "country_pricing",  # B3d`.

Create `backend/etqan/catalogue/tests/test_country_prices_api.py`:

```python
"""B3d §4.1, §5: the country-prices and price routes."""

import pytest
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.catalogue import services
from etqan.catalogue.models import PackageCountryPrice
from etqan.catalogue.tests.test_country_prices import PACKAGE
from etqan.identity import services as identity_services

pytestmark = pytest.mark.django_db
P = "/api/v1/catalogue/packages/"


@pytest.fixture
def package(set_features):
    set_features(country_pricing=True)
    return services.create_package(**PACKAGE)


def rows_url(package):
    return f"{P}{package.pk}/country-prices/"


def price_url(package, student=None):
    tail = "" if student is None else f"?student={student}"
    return f"{P}{package.pk}/price/{tail}"


def test_the_admin_reads_and_replaces_the_list(api_for, package):
    admin = api_for("admin")
    assert admin.get(rows_url(package)).json() == []
    body = [
        {"country": "sa", "price_minor": 45000, "currency": "sar"},
        {"country": "AE", "price_minor": 40000, "currency": "AED"},
    ]
    resp = admin.put(rows_url(package), body, format="json")
    assert resp.status_code == 200, resp.content
    assert resp.json() == [
        {"country": "AE", "price_minor": 40000, "currency": "AED"},
        {"country": "SA", "price_minor": 45000, "currency": "SAR"},
    ]
    assert admin.put(rows_url(package), [], format="json").json() == []
    assert admin.get(rows_url(package)).json() == []


def test_a_bad_row_is_a_400_keyed_by_its_index(api_for, package):
    admin = api_for("admin")
    good = {"country": "SA", "price_minor": 1, "currency": "SAR"}
    admin.put(rows_url(package), [good], format="json")
    resp = admin.put(
        rows_url(package),
        [good, {"country": "SA", "price_minor": 2, "currency": "SAR"}],
        format="json",
    )
    assert resp.status_code == 400
    assert set(resp.json()) == {"rows.1.country"}
    resp = admin.put(rows_url(package), {"country": "SA"}, format="json")
    assert resp.status_code == 400 and "rows" in resp.json()
    assert admin.get(rows_url(package)).json() == [good]


def test_the_feature_gates_the_list_but_not_the_price(api_for, package, set_features):
    admin = api_for("admin")
    set_features(country_pricing=False)
    assert admin.get(rows_url(package)).status_code == 404
    assert admin.put(rows_url(package), [], format="json").status_code == 404
    assert admin.get(price_url(package)).json() == {
        "price_minor": 150000,
        "currency": "EGP",
        "source": "package",
    }


def test_the_price_route_resolves_for_a_student(api_for, package, set_features):
    services.set_country_prices(
        package, [{"country": "SA", "price_minor": 45000, "currency": "SAR"}]
    )
    karim = identity_services.create_person(
        "student", full_name="Karim", profile={"country": "SA"}
    )
    admin = api_for("admin")
    assert admin.get(price_url(package, karim.pk)).json() == {
        "price_minor": 45000,
        "currency": "SAR",
        "source": "country",
    }
    set_features(country_pricing=False)  # Review Focus 1
    assert admin.get(price_url(package, karim.pk)).json()["source"] == "package"
    for bad in ("999999", "abc", "0", ""):
        resp = admin.get(price_url(package, bad))
        assert resp.status_code == 400, bad
        assert "student" in resp.json()


def test_reading_a_students_price_needs_the_student_list(api_for, staff_for, package):
    karim = identity_services.create_person("student", full_name="Karim")
    reader = staff_for("package.view_any")
    assert reader.get(price_url(package)).status_code == 200
    assert reader.get(price_url(package, karim.pk)).status_code == 403
    both = staff_for("package.view_any", "student.view_any")
    assert both.get(price_url(package, karim.pk)).status_code == 200


def test_teachers_families_and_strangers_are_refused(api_for, staff_for, package):
    routes = [
        ("get", rows_url(package), None),
        ("put", rows_url(package), []),
        ("get", price_url(package), None),
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
    reader = staff_for("package.view_any")
    assert reader.get(rows_url(package)).status_code == 200
    assert reader.put(rows_url(package), [], format="json").status_code == 403


def test_duplicating_through_the_api_copies_the_rows(api_for, package):
    admin = api_for("admin")
    row = {"country": "SA", "price_minor": 45000, "currency": "SAR"}
    admin.put(rows_url(package), [row], format="json")
    copy = admin.post(f"{P}{package.pk}/duplicate/").json()
    assert admin.get(f"{P}{copy['id']}/country-prices/").json() == [row]


def test_another_academy_never_leaks(api_for, package, tenants, set_features):
    set_features(academy=tenants.other, country_pricing=True)
    with tenant_context(tenants.other):
        theirs = services.create_package(**PACKAGE)
        services.set_country_prices(
            theirs, [{"country": "SA", "price_minor": 1, "currency": "SAR"}]
        )
    # Each academy's schema has its own table: none of theirs is here.
    assert not PackageCountryPrice.objects.exists()
    assert api_for("admin").get(rows_url(package)).json() == []
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/catalogue/tests/test_country_prices_api.py etqan/access -q`
Expected: FAIL (the routes 404; the matrix lacks handlers).

- [ ] **Step 3: Implement the views and urls**

`backend/etqan/catalogue/api/views.py`: add imports `from django.shortcuts import get_object_or_404`, `from rest_framework.exceptions import PermissionDenied`, `from rest_framework.views import APIView`, `from etqan.platform.exceptions import ValidationError`, `from etqan.platform.permissions import FeatureOn`, `codes_of`, `role_of`; append:

```python
def _country_row(row) -> dict:
    return {
        "country": row.country,
        "price_minor": row.price_minor,
        "currency": row.currency,
    }


class CountryPricesView(APIView):
    """B3d §4.1: a package's prices by country, edited as one list. Office
    only (`HasCode`): teachers read packages, never these."""

    permission_classes = [HasCode, FeatureOn]
    feature = "country_pricing"
    permission_codes = {"GET": "package.view_any", "PUT": "package.update"}

    def get(self, request, pk):
        package = get_object_or_404(Package, pk=pk)
        return Response([_country_row(r) for r in services.country_prices(package)])

    def put(self, request, pk):
        package = get_object_or_404(Package, pk=pk)
        rows = services.set_country_prices(package, request.data)
        return Response([_country_row(r) for r in rows])


class PackagePriceView(APIView):
    """B3d D-8: the price the office forms prefill; no feature gate (with the
    switch off it is the package's own price)."""

    permission_classes = [HasCode]
    permission_codes = {"GET": "package.view_any"}

    def get(self, request, pk):
        student = request.query_params.get("student")
        if student is not None and (
            role_of(request.user) == "staff"
            and "student.view_any" not in codes_of(request.user)
        ):
            raise PermissionDenied("A student's price needs the students list.")
        package = get_object_or_404(Package, pk=pk)
        if student is None:
            price = services.package_price(package, country="")
        elif not student.isdigit() or int(student) < 1:
            raise ValidationError("Choose a student.", field="student")
        else:
            price = services.price_for_student(package, student_id=int(student))
        return Response(
            {
                "price_minor": price.price_minor,
                "currency": price.currency,
                "source": price.source,
            }
        )
```

`backend/etqan/catalogue/api/urls.py`:

```python
from django.urls import path
from rest_framework.routers import SimpleRouter

from etqan.catalogue.api.views import CountryPricesView
from etqan.catalogue.api.views import CourseViewSet
from etqan.catalogue.api.views import PackagePriceView
from etqan.catalogue.api.views import PackageViewSet

router = SimpleRouter()
router.register("courses", CourseViewSet, basename="courses")
router.register("packages", PackageViewSet, basename="packages")

app_name = "catalogue"
urlpatterns = [
    # Phase B3, slice B3d.
    path(
        "packages/<int:pk>/country-prices/",
        CountryPricesView.as_view(),
        name="package-country-prices",
    ),
    path("packages/<int:pk>/price/", PackagePriceView.as_view(), name="package-price"),
    *router.urls,
]
```

- [ ] **Step 4: Run, format, lint, commit**

Run: `$DJ pytest etqan/catalogue etqan/access -q`
Expected: PASS, including `test_every_route_of_a_built_feature_declares_it`, the switched-off-feature test and the code matrix for the three new rows.
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/catalogue etqan/access/tests/test_routes.py
git -C backend commit -m "feat(catalogue): country-prices and price routes (B3d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 3: Local payment methods: the models, the resource and the services

**Files:**
- Modify: `backend/etqan/billing/models.py`, `backend/etqan/billing/services/__init__.py`, `backend/etqan/billing/services/online.py`, `backend/etqan/access/registry.py` (B3 marker), `backend/etqan/access/tests/test_registry.py`
- Create: `backend/etqan/billing/migrations/0008_*.py` (generated), `backend/etqan/billing/services/local.py`, `backend/etqan/billing/tests/test_local_methods.py`

**Interfaces:**
- Produces:
  - models `BillingSettings` (pk 1, `local_payment_enabled`), `LocalPaymentCountry(country unique, enabled)`, `LocalPaymentMethod(country, name, currency, is_active, logo, instructions, position, created_at, updated_at)`; `LOGO_PATH`.
  - `billing.services`: `billing_settings() -> BillingSettings` (unsaved default when there is no row), `has_billing_settings() -> bool`, `update_billing_settings(*, local_payment_enabled: bool) -> BillingSettings`, `clean_instructions(value) -> str`, `create_local_method(*, country, name, instructions, currency="", is_active=True, position=0, logo=None) -> LocalPaymentMethod`, `update_local_method(method, *, logo=UNCHANGED, **fields) -> LocalPaymentMethod`, `delete_local_method(method) -> None`, `local_methods_queryset()`, `filter_local_methods(queryset, *, country=None, is_active=None)`, `local_countries() -> list[tuple[str, bool]]`, `has_local_countries() -> bool`, `set_country_enabled(country: str, *, enabled: bool) -> LocalPaymentCountry`, `local_methods_for(invoice) -> list[LocalPaymentMethod]`, `UNCHANGED`, `LOGO_MAX`, `LOGO_EXTENSIONS`.
  - `billing.services.online.nothing_due(invoice) -> bool` (was `_nothing_due`, plan P16).
  - Resource `payment_method` with in-use verbs `view_any, create, update, delete`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/access/tests/test_registry.py`, in `test_resources_carry_the_12_verbs_and_the_role_resource_6`, after the B3 assertions:

```python
    # Phase B3 (slice B3d, D-19).
    assert by_code["payment_method"].in_use == ("view_any", "create", "update", "delete")
```

Create `backend/etqan/billing/tests/test_local_methods.py`:

```python
"""B3d D-10..D-16, §4.3: local payment methods, the country toggle, the
switch and what an invoice shows."""

import io

import pytest
from django.core.files.storage import default_storage
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import connection
from PIL import Image

from etqan.billing import services
from etqan.billing.models import LocalPaymentMethod
from etqan.billing.tests.test_invoices import invoice_for
from etqan.billing.tests.test_invoices import pay
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db


@pytest.fixture(autouse=True)
def _media(settings, tmp_path):
    settings.MEDIA_ROOT = str(tmp_path)


def image(name="logo.png", fmt="PNG", size=(20, 20)):
    buf = io.BytesIO()
    Image.new("RGB", size).save(buf, fmt)
    return SimpleUploadedFile(name, buf.getvalue())


def method(**overrides):
    fields = {
        "country": "SA",
        "name": "Bank transfer",
        "instructions": "IBAN SA00 0000",
        **overrides,
    }
    return services.create_local_method(**fields)


def test_a_method_is_cleaned_on_save():
    m = method(
        country=" sa ",
        name="  STC Pay ",
        currency="sar",
        instructions="  Line one\r\nLine two\r\n\r\n",
    )
    assert (m.country, m.name, m.currency) == ("SA", "STC Pay", "SAR")
    assert m.instructions == "Line one\nLine two"
    assert (m.is_active, m.position, m.logo.name or None) == (True, 0, None)
    assert method(currency="").currency == ""


@pytest.mark.parametrize(
    ("overrides", "field"),
    [
        ({"country": ""}, "country"),
        ({"country": "S"}, "country"),
        ({"country": "SAU"}, "country"),
        ({"name": "  "}, "name"),
        ({"name": "x" * 121}, "name"),
        ({"instructions": " \r\n "}, "instructions"),
        ({"instructions": "x" * 4001}, "instructions"),
        ({"currency": "SR"}, "currency"),
    ],
)
def test_a_bad_field_is_a_400_on_it(overrides, field):
    with pytest.raises(ValidationError) as caught:
        method(**overrides)
    assert caught.value.field == field
    assert not LocalPaymentMethod.objects.exists()


def test_4000_characters_after_normalising_are_allowed():
    assert len(method(instructions=" " + "x" * 4000 + "\r\n").instructions) == 4000


def test_html_and_links_are_kept_as_text():
    text = '<b>Pay</b> at <a href="https://evil.test">here</a>\r\nhttps://bank.test'
    m = method(instructions=text)
    assert m.instructions == '<b>Pay</b> at <a href="https://evil.test">here</a>\nhttps://bank.test'


def test_a_logo_is_checked_and_stored_under_the_academy():
    m = method(logo=image())
    assert m.logo.name.startswith(f"tenants/{connection.schema_name}/payment-methods/")
    assert m.logo.name.endswith(".png")
    assert default_storage.exists(m.logo.name)
    assert method(logo=image("logo.webp", "WEBP")).logo.name.endswith(".webp")
    assert method(logo=image("logo.jpg", "JPEG")).logo.name.endswith(".jpg")


@pytest.mark.parametrize(
    "make",
    [
        lambda: image("logo.gif", "GIF"),
        lambda: SimpleUploadedFile("logo.svg", b"<svg xmlns='http://www.w3.org/2000/svg'/>"),
        lambda: SimpleUploadedFile("logo.png", b"not a png at all"),
        lambda: SimpleUploadedFile("big.png", b"\x89PNG" + b"0" * (1024 * 1024)),
        lambda: "https://evil.test/logo.png",
    ],
    ids=["gif", "svg", "bad-content", "over-1-mb", "a-string"],
)
def test_a_bad_logo_is_a_400_on_logo(make):
    with pytest.raises(ValidationError) as caught:
        method(logo=make())
    assert caught.value.field == "logo"
    assert not LocalPaymentMethod.objects.exists()


def test_a_replaced_or_cleared_logo_is_removed_only_on_commit(
    django_capture_on_commit_callbacks,
):
    m = method(logo=image())
    first = m.logo.name
    with django_capture_on_commit_callbacks(execute=False) as rolled_back:
        services.update_local_method(m, logo=image("b.png"))
    # Not committed: the old file is still there (Review Focus 5).
    assert default_storage.exists(first)
    for callback in rolled_back:
        callback()
    assert not default_storage.exists(first)
    second = m.logo.name
    with django_capture_on_commit_callbacks(execute=True):
        services.update_local_method(m, logo="")
    m.refresh_from_db()
    assert not m.logo
    assert not default_storage.exists(second)


def test_an_edit_without_a_logo_keeps_it_and_delete_removes_it(
    django_capture_on_commit_callbacks,
):
    m = method(logo=image())
    name = m.logo.name
    with django_capture_on_commit_callbacks(execute=True):
        services.update_local_method(m, name="Al Rajhi", position=2, is_active=False)
    m.refresh_from_db()
    assert (m.name, m.position, m.is_active, m.logo.name) == ("Al Rajhi", 2, False, name)
    with django_capture_on_commit_callbacks(execute=True):
        services.delete_local_method(m)
    assert not default_storage.exists(name)
    assert not LocalPaymentMethod.objects.exists()


def test_countries_are_the_rows_and_the_method_countries():
    method(country="SA")
    method(country="EG")
    services.set_country_enabled("EG", enabled=False)
    services.set_country_enabled("AE", enabled=True)
    assert services.local_countries() == [("AE", True), ("EG", False), ("SA", True)]
    services.set_country_enabled("EG", enabled=True)
    assert ("EG", True) in services.local_countries()


def test_the_setting_is_off_until_switched_on():
    assert services.billing_settings().local_payment_enabled is False
    assert not services.has_billing_settings()  # reading writes nothing
    services.update_billing_settings(local_payment_enabled=True)
    assert services.billing_settings().local_payment_enabled is True
    assert services.has_billing_settings()


# ── What an invoice shows (D-15) ─────────────────────────────────────────────


@pytest.fixture
def saudi(world):
    identity_services.update_person(world.student, profile={"country": "SA"})
    services.update_billing_settings(local_payment_enabled=True)
    return world


def shown(invoice):
    fresh = services.invoices_queryset().get(pk=invoice.pk)
    return [m.name for m in services.local_methods_for(fresh)]


def test_the_invoice_shows_its_countrys_active_methods_in_order(saudi, admin):
    method(name="Bank transfer", position=2)
    method(name="STC Pay", currency="SAR", position=1)
    method(name="Wise", currency="USD")
    method(name="Old", is_active=False)
    method(name="InstaPay", country="EG")
    bill = invoice_for(saudi, admin, currency="SAR")
    assert shown(bill) == ["STC Pay", "Bank transfer"]
    egp = invoice_for(saudi, admin, currency="EGP")
    assert shown(egp) == ["Bank transfer"]  # the blank currency matches any


def test_each_case_with_nothing_to_show(saudi, admin):
    method()
    bill = invoice_for(saudi, admin, amount_minor=1000)
    assert shown(bill) == ["Bank transfer"]
    services.set_country_enabled("SA", enabled=False)
    assert shown(bill) == []
    services.set_country_enabled("SA", enabled=True)
    services.update_billing_settings(local_payment_enabled=False)
    assert shown(bill) == []
    services.update_billing_settings(local_payment_enabled=True)
    pay(bill, admin, 1000)
    assert shown(bill) == []  # paid
    void = invoice_for(saudi, admin)
    services.void_invoice(void, by=admin)
    assert shown(void) == []
    identity_services.update_person(saudi.student, profile={"country": ""})
    assert shown(invoice_for(saudi, admin)) == []  # no country
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/billing/tests/test_local_methods.py etqan/access/tests/test_registry.py -q`
Expected: FAIL (`ImportError: LocalPaymentMethod`; no `payment_method` resource).

- [ ] **Step 3: Implement the models, migration and resource**

`backend/etqan/billing/models.py`: add `from etqan.platform.uploads import tenant_upload_path` and after `CURRENCY`:

```python
COUNTRY = RegexValidator(r"^[A-Z]{2}$")
# B3d D-14: logos in public media. The helper names the callable after the
# folder ("payment-methods_path", not an identifier): migrations import it by
# module and name, so it is renamed to this variable (plan P2).
LOGO_PATH = tenant_upload_path("payment-methods")
LOGO_PATH.__module__ = __name__
LOGO_PATH.__name__ = LOGO_PATH.__qualname__ = "LOGO_PATH"
```

and append:

```python
class BillingSettings(models.Model):
    """B3d D-11: the academy's billing settings, one row (pk 1). A setting,
    not a feature switch: SYS-003's "local payment"."""

    local_payment_enabled = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return "BillingSettings"


class LocalPaymentCountry(models.Model):
    """B3d D-10: whether a country's methods are offered. A country with
    methods and no row is enabled."""

    country = models.CharField(max_length=2, unique=True, validators=[COUNTRY])
    enabled = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["country"]

    def __str__(self):
        return f"LocalPaymentCountry<{self.country}, {self.enabled}>"


class LocalPaymentMethod(models.Model):
    """B3d D-10, D-12..D-14: one way to pay locally in one country. Paying
    stays out of band: the office records the payment (D-15)."""

    country = models.CharField(max_length=2, db_index=True, validators=[COUNTRY])
    name = models.CharField(max_length=120)
    # Blank: shown for an invoice in any currency (D-12).
    currency = models.CharField(
        max_length=3, blank=True, default="", validators=[CURRENCY]
    )
    is_active = models.BooleanField(default=True)
    logo = models.ImageField(upload_to=LOGO_PATH, null=True, blank=True, max_length=255)
    instructions = models.TextField(max_length=4000)
    position = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["country", "position", "id"]

    def __str__(self):
        return f"LocalPaymentMethod<{self.country}, {self.name}>"
```

Run: `$DJ python manage.py makemigrations billing` and check the generated file says `upload_to=etqan.billing.models.LOGO_PATH`.

`backend/etqan/access/registry.py`, under `# ── phase B3 ──` after the `payment_link` resource:

```python
    # B3d: local payment methods per country (D-19).
    Resource(
        "payment_method",
        "Local payment methods",
        "طرق الدفع المحلية",
        ("view_any", "create", "update", "delete"),
    ),
```

- [ ] **Step 4: Implement the services**

`backend/etqan/billing/services/online.py`: rename `_nothing_due` to `nothing_due` (its definition and the two calls in `prepare` and `pay_options`).

Create `backend/etqan/billing/services/local.py`:

```python
"""B3d §4.3: local payment methods per country, the country toggle, and the
setting that shows them on invoices (D-10..D-16)."""

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.db.models import Q

from etqan.billing.models import BillingSettings
from etqan.billing.models import LocalPaymentCountry
from etqan.billing.models import LocalPaymentMethod
from etqan.billing.services.online import nothing_due
from etqan.platform import uploads
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_country
from etqan.platform.validators import clean_currency
from etqan.platform.validators import from_django

LOGO_EXTENSIONS = frozenset({".png", ".jpg", ".jpeg", ".webp"})  # not GIF (D-14)
LOGO_MAX = 1024 * 1024
NAME_MAX = 120
INSTRUCTIONS_MAX = 4000
UNCHANGED = object()  # `update_local_method(logo=…)` left out (plan P13)


# ── The setting ──────────────────────────────────────────────────────────────


def billing_settings() -> BillingSettings:
    """The row, or its unsaved defaults: reading never writes."""
    return BillingSettings.objects.filter(pk=1).first() or BillingSettings(pk=1)


def has_billing_settings() -> bool:
    return BillingSettings.objects.exists()


def update_billing_settings(*, local_payment_enabled: bool) -> BillingSettings:
    row, _ = BillingSettings.objects.update_or_create(
        pk=1, defaults={"local_payment_enabled": local_payment_enabled}
    )
    return row


# ── Methods ──────────────────────────────────────────────────────────────────


def clean_instructions(value) -> str:
    """D-13: plain text, trimmed, line breaks as \\n, 1–4000 characters."""
    text = str(value or "").replace("\r\n", "\n").replace("\r", "\n").strip()
    if not text:
        raise ValidationError("Enter the instructions.", field="instructions")
    if len(text) > INSTRUCTIONS_MAX:
        raise ValidationError(
            f"Use at most {INSTRUCTIONS_MAX} characters.", field="instructions"
        )
    return text


def _clean_name(value) -> str:
    name = str(value or "").strip()
    if not name:
        raise ValidationError("Enter a name.", field="name")
    if len(name) > NAME_MAX:
        raise ValidationError(f"Use at most {NAME_MAX} characters.", field="name")
    return name


def _clean_method_country(value) -> str:
    country = clean_country(value, "country")
    if not country:  # D-16: a method needs a country
        raise ValidationError("Choose a country.", field="country")
    return country


def _clean_method_currency(value) -> str:
    return clean_currency(value, "currency") if str(value or "").strip() else ""


_CLEANERS = {
    "country": _clean_method_country,
    "name": _clean_name,
    "instructions": clean_instructions,
    "currency": _clean_method_currency,
}


def _cleaned(fields: dict) -> dict:
    return {
        key: _CLEANERS[key](value) if key in _CLEANERS else value
        for key, value in fields.items()
    }


def _store_logo(method: LocalPaymentMethod, upload) -> None:
    if not hasattr(upload, "read") or not getattr(upload, "name", ""):
        raise ValidationError("Choose a PNG, JPEG or WEBP image.", field="logo")
    checked = uploads.check_upload(
        upload, extensions=LOGO_EXTENSIONS, max_bytes=LOGO_MAX, field="logo"
    )
    method.logo.save(checked.original_name, checked.file, save=False)


def _save(method: LocalPaymentMethod) -> None:
    try:
        method.full_clean(exclude=["logo"])
    except DjangoValidationError as exc:
        raise from_django(exc) from None
    method.save()


def _delete_file_on_commit(storage, name: str) -> None:
    """D-14: only once the change has committed; a rollback keeps the file."""
    transaction.on_commit(lambda: storage.delete(name))


@transaction.atomic
def create_local_method(  # noqa: PLR0913 -- keyword-only; mirrors the API body (§4.3)
    *,
    country: str,
    name: str,
    instructions: str,
    currency: str = "",
    is_active: bool = True,
    position: int = 0,
    logo=None,
) -> LocalPaymentMethod:
    method = LocalPaymentMethod(
        **_cleaned(
            {
                "country": country,
                "name": name,
                "instructions": instructions,
                "currency": currency,
            }
        ),
        is_active=is_active,
        position=position,
    )
    if logo:
        _store_logo(method, logo)
    _save(method)
    return method


@transaction.atomic
def update_local_method(
    method: LocalPaymentMethod, *, logo=UNCHANGED, **fields
) -> LocalPaymentMethod:
    """Any subset of the fields. ``logo``: left out keeps it, ``""`` or
    ``None`` clears it, a file replaces it (plan P13)."""
    for key, value in _cleaned(fields).items():
        setattr(method, key, value)
    old = (method.logo.storage, method.logo.name) if method.logo else None
    if logo is not UNCHANGED:
        if logo in ("", None):
            method.logo = None
        else:
            _store_logo(method, logo)
    _save(method)
    if logo is not UNCHANGED and old is not None:
        _delete_file_on_commit(*old)
    return method


@transaction.atomic
def delete_local_method(method: LocalPaymentMethod) -> None:
    old = (method.logo.storage, method.logo.name) if method.logo else None
    method.delete()
    if old is not None:
        _delete_file_on_commit(*old)


def local_methods_queryset():
    return LocalPaymentMethod.objects.all()


def filter_local_methods(
    queryset, *, country: str | None = None, is_active: bool | None = None
):
    if country:
        queryset = queryset.filter(country=country.strip().upper())
    if is_active is not None:
        queryset = queryset.filter(is_active=is_active)
    return queryset


# ── Countries ────────────────────────────────────────────────────────────────


def local_countries() -> list[tuple[str, bool]]:
    """Plan P4: every country with a row or a method, with whether it is
    enabled (a method's country without a row is, D-10)."""
    found = dict(LocalPaymentCountry.objects.values_list("country", "enabled"))
    for country in LocalPaymentMethod.objects.values_list("country", flat=True):
        found.setdefault(country, True)
    return sorted(found.items())


def has_local_countries() -> bool:
    return LocalPaymentCountry.objects.exists()


def set_country_enabled(country: str, *, enabled: bool) -> LocalPaymentCountry:
    row, _ = LocalPaymentCountry.objects.update_or_create(
        country=country, defaults={"enabled": enabled}
    )
    return row


# ── What an invoice shows ────────────────────────────────────────────────────


def local_methods_for(invoice) -> list[LocalPaymentMethod]:
    """D-15: ``invoice`` comes from `invoices_queryset()` (its student is
    joined). Nothing unless the setting is on, something is due, the
    student's country is set and enabled; then its active methods whose
    currency is blank or the invoice's, by position."""
    if not billing_settings().local_payment_enabled or nothing_due(invoice):
        return []
    country = invoice.student.country
    if not country or LocalPaymentCountry.objects.filter(
        country=country, enabled=False
    ).exists():
        return []
    return list(
        LocalPaymentMethod.objects.filter(country=country, is_active=True)
        .filter(Q(currency="") | Q(currency=invoice.currency))
        .order_by("position", "id")
    )
```

`backend/etqan/billing/services/__init__.py`: import from `etqan.billing.services.local` — `LOGO_EXTENSIONS`, `LOGO_MAX`, `UNCHANGED`, `billing_settings`, `clean_instructions`, `create_local_method`, `delete_local_method`, `filter_local_methods`, `has_billing_settings`, `has_local_countries`, `local_countries`, `local_methods_for`, `local_methods_queryset`, `set_country_enabled`, `update_billing_settings`, `update_local_method` — and add each name to `__all__` (alphabetical, as the file keeps it).

- [ ] **Step 5: Run, format, lint, commit**

Run: `$DJ pytest etqan/billing etqan/access -q --create-db`
Expected: PASS (the existing `test_online.py` still passes after the rename).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/billing etqan/access/registry.py etqan/access/tests/test_registry.py
git -C backend commit -m "feat(billing): local payment methods, the country toggle and the local payment setting (B3d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Local payment methods: the API, the invoice payload and the route matrix

**Files:**
- Modify: `backend/etqan/billing/api/serializers.py`, `payloads.py`, `views.py`, `urls.py`, `backend/etqan/access/tests/test_routes.py`
- Create: `backend/etqan/billing/tests/test_local_methods_api.py`

**Interfaces:**
- Consumes: Task 3 services.
- Produces (all `invoices`):
  - `GET/PATCH /api/v1/billing/settings/` → `{local_payment_enabled}` (`payment_method.view_any` / `.update`);
  - `GET/POST /api/v1/billing/local-methods/` → `{countries: [{country, enabled}], methods: [row]}` / 201 `row`; filters `country`, `is_active` (`.view_any` / `.create`);
  - `PATCH/DELETE /api/v1/billing/local-methods/<id>/` (`.update` / `.delete`), multipart or JSON;
  - `PUT /api/v1/billing/local-countries/<CC>/` `{enabled}` → `{country, enabled}` (`.update`); a malformed code is a 404;
  - a row: `{id, country, name, currency, is_active, logo_url, instructions, position, updated_at}`;
  - the invoice detail (every reader, every write route's answer) gains `local_methods: [{id, name, logo_url, instructions}]`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/access/tests/test_routes.py`:
- `ROUTES`, after Task 2's B3d rows:

```python
    ("GET", "/api/v1/billing/settings/", "payment_method.view_any"),
    ("PATCH", "/api/v1/billing/settings/", "payment_method.update"),
    ("GET", "/api/v1/billing/local-methods/", "payment_method.view_any"),
    ("POST", "/api/v1/billing/local-methods/", "payment_method.create"),
    ("PATCH", f"/api/v1/billing/local-methods/{N}/", "payment_method.update"),
    ("DELETE", f"/api/v1/billing/local-methods/{N}/", "payment_method.delete"),
    ("PUT", "/api/v1/billing/local-countries/ZZ/", "payment_method.update"),
```

- `FEATURES`, after Task 2's B3d block:

```python
    **dict.fromkeys(
        (
            ("GET", "/api/v1/billing/settings/"),
            ("PATCH", "/api/v1/billing/settings/"),
            ("GET", "/api/v1/billing/local-methods/"),
            ("POST", "/api/v1/billing/local-methods/"),
            ("PATCH", f"/api/v1/billing/local-methods/{N}/"),
            ("DELETE", f"/api/v1/billing/local-methods/{N}/"),
            ("PUT", "/api/v1/billing/local-countries/ZZ/"),
        ),
        "invoices",
    ),
```

- `FEATURE_WORDS`: `"/billing/settings/": "invoices",`, `"/local-methods/": "invoices",`, `"/local-countries/": "invoices",` (each with `# B3d`).

Create `backend/etqan/billing/tests/test_local_methods_api.py`:

```python
"""B3d §4.3, §5: the local payment routes and the invoice's local_methods."""

import io

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django_tenants.utils import tenant_context
from PIL import Image
from rest_framework.test import APIClient

from etqan.billing import services
from etqan.billing.models import LocalPaymentMethod
from etqan.billing.tests.conftest import make_parent
from etqan.billing.tests.test_invoices import invoice_for
from etqan.billing.tests.test_invoices import pay
from etqan.identity import services as identity_services

pytestmark = pytest.mark.django_db
B = "/api/v1/billing/"
METHODS = f"{B}local-methods/"
ROW_KEYS = {
    "id",
    "country",
    "name",
    "currency",
    "is_active",
    "logo_url",
    "instructions",
    "position",
    "updated_at",
}


@pytest.fixture(autouse=True)
def _media(settings, tmp_path):
    settings.MEDIA_ROOT = str(tmp_path)


def png(name="logo.png"):
    buf = io.BytesIO()
    Image.new("RGB", (20, 20)).save(buf, "PNG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/png")


def create(client, **fields):
    body = {
        "country": "SA",
        "name": "Bank transfer",
        "instructions": "IBAN SA00",
        **fields,
    }
    return client.post(METHODS, body, format="multipart")


def test_the_admin_runs_the_whole_list(api_for):
    admin = api_for("admin")
    resp = create(admin, currency="sar", logo=png())
    assert resp.status_code == 201, resp.content
    row = resp.json()
    assert set(row) == ROW_KEYS
    assert (row["country"], row["currency"], row["is_active"], row["position"]) == (
        "SA",
        "SAR",
        True,  # left out of a multipart body: still active (plan P12)
        0,
    )
    assert row["logo_url"].startswith("/media/tenants/")
    patched = admin.patch(
        f"{METHODS}{row['id']}/",
        {"is_active": "false", "position": "3", "logo": ""},
        format="multipart",
    )
    assert patched.status_code == 200, patched.content
    assert (patched.json()["is_active"], patched.json()["position"]) == (False, 3)
    assert patched.json()["logo_url"] is None
    assert admin.patch(
        f"{METHODS}{row['id']}/", {"name": "Al Rajhi"}, format="json"
    ).json()["name"] == "Al Rajhi"
    listed = admin.get(METHODS).json()
    assert listed["countries"] == [{"country": "SA", "enabled": True}]
    assert [m["name"] for m in listed["methods"]] == ["Al Rajhi"]
    assert admin.get(METHODS, {"is_active": "true"}).json()["methods"] == []
    assert admin.get(METHODS, {"country": "eg"}).json()["methods"] == []
    assert admin.delete(f"{METHODS}{row['id']}/").status_code == 204
    assert not LocalPaymentMethod.objects.exists()


@pytest.mark.parametrize(
    ("fields", "field"),
    [
        ({"country": ""}, "country"),
        ({"name": ""}, "name"),
        ({"instructions": "  "}, "instructions"),
        ({"currency": "SR"}, "currency"),
        ({"position": "-1"}, "position"),
        ({"logo": "https://evil.test/a.png"}, "logo"),
    ],
)
def test_bad_bodies_are_400s_on_their_fields(api_for, fields, field):
    resp = create(api_for("admin"), **fields)
    assert resp.status_code == 400, resp.content
    assert field in resp.json()
    assert not LocalPaymentMethod.objects.exists()


def test_a_gif_or_svg_logo_is_refused(api_for):
    admin = api_for("admin")
    gif = SimpleUploadedFile("a.gif", b"GIF89a" + b"0" * 20, content_type="image/gif")
    svg = SimpleUploadedFile("a.svg", b"<svg/>", content_type="image/svg+xml")
    for upload in (gif, svg):
        resp = create(admin, logo=upload)
        assert resp.status_code == 400 and "logo" in resp.json()


def test_the_setting_and_the_country_toggle(api_for):
    admin = api_for("admin")
    assert admin.get(f"{B}settings/").json() == {"local_payment_enabled": False}
    resp = admin.patch(f"{B}settings/", {"local_payment_enabled": True}, format="json")
    assert resp.json() == {"local_payment_enabled": True}
    assert admin.patch(f"{B}settings/", {}, format="json").status_code == 400
    resp = admin.put(f"{B}local-countries/EG/", {"enabled": False}, format="json")
    assert resp.json() == {"country": "EG", "enabled": False}
    assert admin.get(METHODS).json()["countries"] == [{"country": "EG", "enabled": False}]
    for bad in ("eg", "EGY", "E1"):
        resp = admin.put(f"{B}local-countries/{bad}/", {"enabled": True}, format="json")
        assert resp.status_code == 404, bad
    assert (
        admin.put(f"{B}local-countries/EG/", {}, format="json").status_code == 400
    )


def test_the_feature_gates_every_route(api_for, set_features):
    admin = api_for("admin")
    set_features(invoices=False)
    assert admin.get(METHODS).status_code == 404
    assert admin.get(f"{B}settings/").status_code == 404
    assert admin.put(f"{B}local-countries/SA/", {"enabled": True}, format="json").status_code == 404


def test_only_the_office_with_the_codes_reaches_the_admin_routes(api_for, staff_for):
    existing = services.create_local_method(
        country="SA", name="Bank", instructions="IBAN"
    )
    routes = [
        ("get", f"{B}settings/", None),
        ("patch", f"{B}settings/", {"local_payment_enabled": True}),
        ("get", METHODS, None),
        ("post", METHODS, {"country": "SA", "name": "x", "instructions": "y"}),
        ("patch", f"{METHODS}{existing.pk}/", {"name": "z"}),
        ("delete", f"{METHODS}{existing.pk}/", None),
        ("put", f"{B}local-countries/SA/", {"enabled": False}),
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
    reader = staff_for("payment_method.view_any")
    assert reader.get(METHODS).status_code == 200
    assert reader.delete(f"{METHODS}{existing.pk}/").status_code == 403


def test_the_invoice_detail_carries_the_methods_for_family_and_office(
    api_for, world, admin, set_features
):
    identity_services.update_person(world.student, profile={"country": "SA"})
    services.update_billing_settings(local_payment_enabled=True)
    services.create_local_method(
        country="SA", name="Bank", instructions="<b>IBAN</b>\nSA00"
    )
    bill = invoice_for(world, admin, amount_minor=1000)
    office = api_for("admin")
    body = office.get(f"{B}invoices/{bill.pk}/").json()
    assert [
        {k: m[k] for k in ("name", "logo_url", "instructions")}
        for m in body["local_methods"]
    ] == [{"name": "Bank", "logo_url": None, "instructions": "<b>IBAN</b>\nSA00"}]
    assert set(body["local_methods"][0]) == {"id", "name", "logo_url", "instructions"}
    parent = APIClient()
    parent.force_login(make_parent("Huda", world.student))
    assert len(parent.get(f"{B}invoices/{bill.pk}/").json()["local_methods"]) == 1
    # every write route answers through detail(): a part payment still shows them,
    # the full one does not
    resp = office.post(
        f"{B}invoices/{bill.pk}/payments/",
        {"amount_minor": 400, "method": "cash", "paid_on": "2026-06-01"},
        format="json",
    )
    assert len(resp.json()["local_methods"]) == 1
    pay(bill, admin, 600)
    assert office.get(f"{B}invoices/{bill.pk}/").json()["local_methods"] == []


def test_another_academy_never_leaks(api_for, tenants):
    with tenant_context(tenants.other):
        theirs = services.create_local_method(
            country="SA", name="Theirs", instructions="x"
        )
        services.set_country_enabled("SA", enabled=False)
        services.update_billing_settings(local_payment_enabled=True)
    # Each academy's schema has its own tables.
    assert theirs.pk
    admin = api_for("admin")
    assert admin.get(METHODS).json() == {"countries": [], "methods": []}
    assert admin.get(f"{B}settings/").json() == {"local_payment_enabled": False}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/billing/tests/test_local_methods_api.py etqan/access -q`
Expected: FAIL (404s on the new routes; the matrix lacks handlers).

- [ ] **Step 3: Implement serializers, payloads, views and urls**

`backend/etqan/billing/api/serializers.py`, append (add `from rest_framework.fields import empty`):

```python
class OptionalBoolean(serializers.BooleanField):
    """DRF reads a checkbox missing from a multipart body as False; here it
    stays absent (plan P12)."""

    default_empty_html = empty


class BillingSettingsInput(serializers.Serializer):
    local_payment_enabled = serializers.BooleanField()


class LocalMethodInput(serializers.Serializer):
    """§4.3. Text is checked by the service (trim, CRLF, lengths); the logo
    is read from the request outside this body (plan P13)."""

    country = serializers.CharField(allow_blank=True)
    name = serializers.CharField(allow_blank=True, trim_whitespace=False)
    instructions = serializers.CharField(allow_blank=True, trim_whitespace=False)
    currency = serializers.CharField(allow_blank=True, required=False)
    is_active = OptionalBoolean(required=False)
    position = serializers.IntegerField(min_value=0, max_value=32767, required=False)


class LocalMethodQueryInput(serializers.Serializer):
    # A query string is form input too: a missing `is_active` must not read
    # as False (plan P12).
    country = serializers.CharField(required=False, allow_blank=True)
    is_active = OptionalBoolean(allow_null=True, default=None)


class LocalCountryInput(serializers.Serializer):
    enabled = serializers.BooleanField()
```

`backend/etqan/billing/api/payloads.py`, append and extend `invoice_detail`:

```python
def billing_settings(row) -> dict:
    return {"local_payment_enabled": row.local_payment_enabled}


def _logo_url(method) -> str | None:
    """Plan P3: /media/… locally (same origin), the bucket URL in production."""
    return method.logo.url if method.logo else None


def local_method(method) -> dict:
    return {
        "id": method.pk,
        "country": method.country,
        "name": method.name,
        "currency": method.currency,
        "is_active": method.is_active,
        "logo_url": _logo_url(method),
        "instructions": method.instructions,
        "position": method.position,
        "updated_at": method.updated_at,
    }


def local_methods_payload(countries, methods) -> dict:
    return {
        "countries": [
            {"country": country, "enabled": enabled} for country, enabled in countries
        ],
        "methods": [local_method(m) for m in methods],
    }
```

```python
def invoice_detail(
    invoice,
    *,
    is_admin: bool,
    can_pay_online: list[str] | None = None,
    local_methods: list | None = None,
) -> dict:
    """The row plus its payments (prefetched with ``recorded_by``), the
    providers it can be paid online with (B3b plan D12) and the local ways
    to pay (B3d D-15), for every reader."""
    return {
        **invoice_row(invoice, is_admin=is_admin),
        "can_pay_online": list(can_pay_online or []),
        "local_methods": [
            {
                "id": m.pk,
                "name": m.name,
                "logo_url": _logo_url(m),
                "instructions": m.instructions,
            }
            for m in local_methods or []
        ],
        "payments": [
            payment_row(payment, is_admin=is_admin)
            for payment in invoice.payments.all()
        ],
    }
```

`backend/etqan/billing/api/views.py`: in `detail()` and `InvoiceDetailView.get`, pass `local_methods=services.local_methods_for(invoice)` next to `can_pay_online`. Add imports `from rest_framework.parsers import FormParser, JSONParser, MultiPartParser`, `from etqan.platform.validators import COUNTRY_RE`, the four new inputs; append:

```python
PARSERS = [JSONParser, MultiPartParser, FormParser]


class BillingSettingsView(APIView):
    """B3d D-11: SYS-003's local payment switch."""

    permission_classes = [HasCode, FeatureOn]
    feature = "invoices"
    permission_codes = {
        "GET": "payment_method.view_any",
        "PATCH": "payment_method.update",
    }

    def get(self, request):
        return Response(payloads.billing_settings(services.billing_settings()))

    def patch(self, request):
        body = BillingSettingsInput(data=request.data)
        body.is_valid(raise_exception=True)
        row = services.update_billing_settings(**body.validated_data)
        return Response(payloads.billing_settings(row))


def _method_response(pk, *, code=status.HTTP_200_OK) -> Response:
    method = services.local_methods_queryset().get(pk=pk)
    return Response(payloads.local_method(method), status=code)


class LocalMethodListView(APIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "invoices"
    permission_codes = {
        "GET": "payment_method.view_any",
        "POST": "payment_method.create",
    }
    parser_classes = PARSERS

    def get(self, request):
        query = LocalMethodQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        methods = services.filter_local_methods(
            services.local_methods_queryset(), **query.validated_data
        )
        return Response(
            payloads.local_methods_payload(services.local_countries(), methods)
        )

    def post(self, request):
        body = LocalMethodInput(data=request.data)
        body.is_valid(raise_exception=True)
        method = services.create_local_method(
            **body.validated_data, logo=request.data.get("logo") or None
        )
        return _method_response(method.pk, code=status.HTTP_201_CREATED)


class LocalMethodDetailView(APIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "invoices"
    permission_codes = {
        "PATCH": "payment_method.update",
        "DELETE": "payment_method.delete",
    }
    parser_classes = PARSERS

    def patch(self, request, pk):
        method = get_object_or_404(services.local_methods_queryset(), pk=pk)
        body = LocalMethodInput(data=request.data, partial=True)
        body.is_valid(raise_exception=True)
        services.update_local_method(
            method,
            **body.validated_data,
            logo=request.data.get("logo", services.UNCHANGED),
        )
        return _method_response(pk)

    def delete(self, request, pk):
        services.delete_local_method(
            get_object_or_404(services.local_methods_queryset(), pk=pk)
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class LocalCountryView(APIView):
    """§4.3: a country's toggle, created on first use. A malformed code is
    not a country: 404 (D-16)."""

    permission_classes = [HasCode, FeatureOn]
    feature = "invoices"
    permission_codes = {"PUT": "payment_method.update"}

    def put(self, request, code):
        if not COUNTRY_RE.fullmatch(code):
            raise NotFound("Country not found.")
        body = LocalCountryInput(data=request.data)
        body.is_valid(raise_exception=True)
        row = services.set_country_enabled(code, **body.validated_data)
        return Response({"country": row.country, "enabled": row.enabled})
```

(`create_local_method` takes the cleaned body plus `logo`; the serializer's absent keys fall back to the service defaults, so `is_active` left out is `True`.)

`backend/etqan/billing/api/urls.py`, append to `urlpatterns`:

```python
    # Phase B3, slice B3d.
    path("settings/", views.BillingSettingsView.as_view(), name="settings"),
    path("local-methods/", views.LocalMethodListView.as_view(), name="local-methods"),
    path(
        "local-methods/<int:pk>/",
        views.LocalMethodDetailView.as_view(),
        name="local-method",
    ),
    path(
        "local-countries/<str:code>/",
        views.LocalCountryView.as_view(),
        name="local-country",
    ),
```

- [ ] **Step 4: Run, format, lint, commit**

Run: `$DJ pytest etqan/billing etqan/access -q`
Expected: PASS. If an existing billing test compares the invoice detail's whole key set, add `"local_methods"` to it (additive).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/billing etqan/access/tests/test_routes.py
git -C backend commit -m "feat(billing): local payment routes and local_methods on the invoice (B3d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Seeds

**Files:**
- Create: `backend/etqan/tenants/seeds/countries.py`, `backend/etqan/tenants/tests/test_seed_countries.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (B3 marker), `backend/etqan/tenants/tests/test_seed_dev.py` (the demo student count)

**Interfaces:**
- Consumes: `catalogue.services.find_package`, `country_prices`, `set_country_prices`; `identity.services.create_person`, `get_user_by_email`; Task 3's billing services.
- Produces: `seed_countries(subdomain: str) -> None`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/tenants/tests/test_seed_countries.py`:

```python
"""B3d §8: Karim Saleh (SA), a SAR price on "Monthly, 2 a week", two SA
methods, the SA country row and the local payment setting, seeded once."""

import pytest
from django.core.management import call_command
from django.db import connection
from django.test import override_settings
from django_tenants.utils import tenant_context

from etqan.billing import services as billing
from etqan.catalogue import services as catalogue
from etqan.identity import services as identity
from etqan.tenants.models import Academy


def state():
    package = catalogue.find_package("Monthly, 2 a week")
    return {
        "karim": identity.get_student_profile(
            identity.get_user_by_email("karim@demo.test").pk
        ).country,
        "prices": [
            (r.country, r.price_minor, r.currency)
            for r in catalogue.country_prices(package)
        ],
        "methods": [
            (m.country, m.name, m.currency, bool(m.logo), m.is_active)
            for m in billing.local_methods_queryset()
        ],
        "countries": billing.local_countries(),
        "enabled": billing.billing_settings().local_payment_enabled,
    }


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_gives_demo_its_country_prices_and_local_methods_once():
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        first = state()
        assert first == {
            "karim": "SA",
            "prices": [("SA", 45000, "SAR")],
            "methods": [
                ("SA", "Bank transfer", "", False, True),
                ("SA", "STC Pay", "SAR", False, True),
            ],
            "countries": [("SA", True)],
            "enabled": True,
        }
    with tenant_context(other):
        assert not billing.local_methods_queryset().exists()
        assert not billing.has_billing_settings()
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert state() == first


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_an_office_choice_is_never_overwritten():
    from etqan.tenants.seeds import countries as seeds  # noqa: PLC0415

    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(Academy.objects.get(subdomain="demo")):
        billing.update_billing_settings(local_payment_enabled=False)
        billing.set_country_enabled("SA", enabled=False)
        seeds.seed_countries("demo")
        assert billing.billing_settings().local_payment_enabled is False
        assert billing.local_countries() == [("SA", False)]
```

`backend/etqan/tenants/tests/test_seed_dev.py`, in `test_seed_dev_adds_people_and_catalogue_once`: `assert students.count() == 3` becomes `assert students.count() == 4  # B3d adds Karim Saleh (SA)`.

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/tenants/tests/test_seed_countries.py etqan/tenants/tests/test_seed_dev.py -q`
Expected: FAIL (no Karim; no rows).

- [ ] **Step 3: Implement**

Create `backend/etqan/tenants/seeds/countries.py`:

```python
"""Phase B3, slice B3d (spec §8): a Saudi demo student, a SAR price on the
monthly package, two local methods for Saudi Arabia, the country row and the
local payment setting. Demo only (plan P15). Services only; each step runs
only when its table is empty (the student: when absent), so a second run, or
an office choice made since, is left alone."""

from etqan.billing import services as billing_services
from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError

KARIM = {"full_name": "Karim Saleh", "email": "karim@demo.test"}
PACKAGE = "Monthly, 2 a week"
PRICE = {"country": "SA", "price_minor": 45000, "currency": "SAR"}
METHODS = (
    {
        "country": "SA",
        "name": "Bank transfer",
        "currency": "",
        "position": 0,
        "instructions": (
            "Transfer to Etqan Demo Academy\n"
            "IBAN: SA03 8000 0000 6080 1016 7519\n"
            "Write the invoice number in the transfer note."
        ),
    },
    {
        "country": "SA",
        "name": "STC Pay",
        "currency": "SAR",
        "position": 1,
        "instructions": "Send to 0500000000 (Etqan Demo).\nThen send us the receipt.",
    },
)


def _seed_student() -> None:
    try:
        identity_services.get_user_by_email(KARIM["email"])
    except NotFoundError:
        identity_services.create_person(
            "student",
            **KARIM,
            profile={"status": "active", "country": "SA"},
            invite=False,
        )


def seed_countries(subdomain: str) -> None:
    if subdomain != "demo":
        return
    _seed_student()
    package = catalogue_services.find_package(PACKAGE)
    if package is not None and not catalogue_services.country_prices(package):
        catalogue_services.set_country_prices(package, [PRICE])
    if not billing_services.local_methods_queryset().exists():
        for fields in METHODS:
            billing_services.create_local_method(**fields)
    if not billing_services.has_local_countries():
        billing_services.set_country_enabled("SA", enabled=True)
    if not billing_services.has_billing_settings():
        billing_services.update_billing_settings(local_payment_enabled=True)
```

`seed_dev.py`: import `from etqan.tenants.seeds import countries as countries_seeds` (next to the other seed imports) and, under `# ── phase B3 ──`, after the last B3 call (B3h's `finance_seeds.seed_rates(subdomain)`): `countries_seeds.seed_countries(subdomain)`.

- [ ] **Step 4: Run, format, lint, commit**

Run: `$DJ pytest etqan/tenants -q`
Expected: PASS (if another tenants test counts demo students or lists every demo person exactly, add Karim to it the same way).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/tenants
git -C backend commit -m "feat(seeds): a Saudi demo student, a SAR country price and local methods (B3d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 6: Dashboard — country prices card and `usePackagePrice`

**Files:**
- Modify: `dashboard/src/features/catalogue/schemas.ts`, `api.ts`, `queries.ts`, `index.ts`, `dashboard/src/routes/_authed/catalogue.packages.$packageId.tsx`, `dashboard/src/features/identity/schemas.ts`, `dashboard/src/locales/en/catalogue.json`, `dashboard/src/locales/ar/catalogue.json`
- Create: `dashboard/src/features/catalogue/CountryPricesCard.tsx`, `CountryPricesCard.test.tsx`, `api.test.ts`, `queries.test.tsx`, `dashboard/src/test/catalogue-fixtures.ts`

**Interfaces:**
- Consumes: Task 2's routes.
- Produces:
  - types `CountryPrice {country, price_minor, currency}`, `PackagePrice {price_minor, currency, source: "country" | "package"}`; `countryPricesFormSchema` / `CountryPricesFormValues` (`{rows: {country, currency, price}[]}`);
  - `catalogueApi.countryPrices(packageId)`, `setCountryPrices({packageId, rows})`, `price(packageId, studentId?)`;
  - `packagePriceKey = ["catalogue", "price"]`; `usePackagePrice(packageId?: string | number, studentId?: string | number) -> { data?: PackagePrice; isPending: boolean; isError: boolean }` (a blank or non-numeric id counts as absent; `isPending` only while a chosen package's price is loading); `useCountryPrices(packageId)`, `useSaveCountryPrices(packageId)`;
  - `<CountryPricesCard packageId />`; fixtures `countryPrice(overrides)`, `packagePrice(overrides)`;
  - `FeatureCode` gains `"country_pricing"`.

- [ ] **Step 1: Write the failing tests and fixtures**

`src/features/identity/schemas.ts`: add `| "country_pricing"` to `FeatureCode` under a `// Phase B3, slice B3d.` comment (after B3h's `"exchange_rates"`).

Create `src/test/catalogue-fixtures.ts`:

```ts
import type { CountryPrice, PackagePrice } from "@/features/catalogue";

export function countryPrice(overrides: Partial<CountryPrice> = {}): CountryPrice {
	return { country: "SA", price_minor: 45000, currency: "SAR", ...overrides };
}

export function packagePrice(overrides: Partial<PackagePrice> = {}): PackagePrice {
	return { price_minor: 150000, currency: "EGP", source: "package", ...overrides };
}
```

Create `src/features/catalogue/api.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { catalogueApi } from "./api";

vi.mock("@/lib/api", async (orig) => {
	const actual = await orig<typeof import("@/lib/api")>();
	const ok = () => Promise.resolve({ data: [] });
	return {
		...actual,
		api: { get: vi.fn(ok), put: vi.fn(ok), post: vi.fn(ok), patch: vi.fn(ok), delete: vi.fn(ok) },
	};
});

describe("catalogueApi country prices (B3d §5)", () => {
	beforeEach(() => vi.clearAllMocks());

	it("reads and replaces a package's list", async () => {
		await catalogueApi.countryPrices(5);
		expect(api.get).toHaveBeenLastCalledWith("catalogue/packages/5/country-prices/");
		const rows = [{ country: "SA", price_minor: 45000, currency: "SAR" }];
		await catalogueApi.setCountryPrices({ packageId: 5, rows });
		expect(api.put).toHaveBeenLastCalledWith("catalogue/packages/5/country-prices/", rows);
	});

	it("reads the resolved price, for a student or the package", async () => {
		await catalogueApi.price(5, 11);
		expect(api.get).toHaveBeenLastCalledWith("catalogue/packages/5/price/", {
			params: { student: 11 },
		});
		await catalogueApi.price(5);
		expect(api.get).toHaveBeenLastCalledWith("catalogue/packages/5/price/", { params: {} });
	});
});
```

Create `src/features/catalogue/queries.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { packagePrice } from "@/test/catalogue-fixtures";
import { catalogueApi } from "./api";
import { usePackagePrice } from "./queries";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, catalogueApi: { ...actual.catalogueApi, price: vi.fn() } };
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("usePackagePrice", () => {
	beforeEach(() => vi.clearAllMocks());

	it("asks nothing and is not pending without a package", () => {
		const { result } = renderHook(() => usePackagePrice("", "11"), { wrapper });
		expect(result.current.isPending).toBe(false);
		expect(catalogueApi.price).not.toHaveBeenCalled();
	});

	it("is pending until the student's price resolves", async () => {
		vi.mocked(catalogueApi.price).mockResolvedValue(
			packagePrice({ price_minor: 45000, currency: "SAR", source: "country" }),
		);
		const { result } = renderHook(() => usePackagePrice("5", 11), { wrapper });
		expect(result.current.isPending).toBe(true);
		await waitFor(() => expect(result.current.data?.currency).toBe("SAR"));
		expect(result.current.isPending).toBe(false);
		expect(catalogueApi.price).toHaveBeenCalledWith(5, 11);
	});

	it("reads the package's own price without a student, and reports failure", async () => {
		vi.mocked(catalogueApi.price).mockRejectedValue(new Error("offline"));
		const { result } = renderHook(() => usePackagePrice(5, "abc"), { wrapper });
		await waitFor(() => expect(result.current.isError).toBe(true));
		expect(catalogueApi.price).toHaveBeenCalledWith(5, undefined);
	});
});
```

Create `src/features/catalogue/CountryPricesCard.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { staffMe } from "@/test/access-fixtures";
import { countryPrice } from "@/test/catalogue-fixtures";
import { renderWithRouter } from "@/test/render";
import { catalogueApi } from "./api";
import { CountryPricesCard } from "./CountryPricesCard";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		catalogueApi: { ...actual.catalogueApi, countryPrices: vi.fn(), setCountryPrices: vi.fn() },
	};
});

const ROWS = [
	countryPrice(),
	countryPrice({ country: "KW", price_minor: 1234, currency: "KWD" }),
	countryPrice({ country: "JP", price_minor: 1500, currency: "JPY" }),
];
const fieldset = (n: number) => screen.getByRole("group", { name: `Country price ${n}` });

describe("CountryPricesCard", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(catalogueApi.countryPrices).mockResolvedValue(ROWS);
		vi.mocked(catalogueApi.setCountryPrices).mockImplementation(async ({ rows }) => rows);
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("shows each row's price in its own currency", async () => {
		renderWithRouter(<CountryPricesCard packageId={5} />);
		expect(await screen.findByText("Prices by country")).toBeInTheDocument();
		await waitFor(() => expect(within(fieldset(1)).getByLabelText(/^Price \(SAR\)/)).toHaveValue("450.00"));
		expect(within(fieldset(2)).getByLabelText(/^Price \(KWD\)/)).toHaveValue("1.234");
		expect(within(fieldset(3)).getByLabelText(/^Price \(JPY\)/)).toHaveValue("1500");
		expect(within(fieldset(1)).getByLabelText(/^Country/)).toHaveValue("SA");
	});

	it("saves the whole list, converting each row with its currency", async () => {
		const user = userEvent.setup();
		renderWithRouter(<CountryPricesCard packageId={5} />);
		const kwd = await within(await screen.findByRole("group", { name: "Country price 2" })).findByLabelText(/^Price/);
		await user.clear(kwd);
		await user.type(kwd, "2.5");
		await user.click(screen.getByRole("button", { name: "Remove row 3" }));
		await user.click(screen.getByRole("button", { name: "Add country" }));
		const added = fieldset(3);
		await user.selectOptions(within(added).getByLabelText(/^Country/), "EG");
		await user.selectOptions(within(added).getByLabelText(/^Currency/), "EGP");
		await user.type(within(added).getByLabelText(/^Price/), "100.5");
		await user.click(screen.getByRole("button", { name: "Save prices" }));
		await waitFor(() =>
			expect(catalogueApi.setCountryPrices).toHaveBeenCalledWith({
				packageId: 5,
				rows: [
					{ country: "SA", currency: "SAR", price_minor: 45000 },
					{ country: "KW", currency: "KWD", price_minor: 2500 },
					{ country: "EG", currency: "EGP", price_minor: 10050 },
				],
			}),
		);
		expect(await screen.findByText("Prices saved.")).toBeInTheDocument();
	});

	it("refuses too many decimals for the currency, then a repeated country", async () => {
		const user = userEvent.setup();
		renderWithRouter(<CountryPricesCard packageId={5} />);
		const sar = await within(await screen.findByRole("group", { name: "Country price 1" })).findByLabelText(/^Price/);
		await user.clear(sar);
		await user.type(sar, "1.234");
		await user.click(screen.getByRole("button", { name: "Save prices" }));
		expect(await within(fieldset(1)).findByText("Enter a price with no more decimals than the currency has.")).toBeInTheDocument();
		// zod runs the list-level check only once every row parses: fix the row first.
		await user.clear(sar);
		await user.type(sar, "1.23");
		await user.selectOptions(within(fieldset(2)).getByLabelText(/^Country/), "SA");
		await user.click(screen.getByRole("button", { name: "Save prices" }));
		expect(await within(fieldset(2)).findByText("This country is already in the list.")).toBeInTheDocument();
		expect(catalogueApi.setCountryPrices).not.toHaveBeenCalled();
	});

	it("puts the server's row error under its row", async () => {
		vi.mocked(catalogueApi.setCountryPrices).mockRejectedValue(
			new AxiosError("bad", "400", undefined, undefined, {
				status: 400,
				data: { "rows.1.country": ["This country is already in the list."] },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<CountryPricesCard packageId={5} />);
		await screen.findByRole("group", { name: "Country price 1" });
		await user.click(screen.getByRole("button", { name: "Save prices" }));
		expect(await within(fieldset(2)).findByText("This country is already in the list.")).toBeInTheDocument();
	});

	it("is read-only for staff who may only view packages", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("package.view_any")}>
				<CountryPricesCard packageId={5} />
			</CanProvider>,
		);
		await screen.findByRole("group", { name: "Country price 1" });
		expect(within(fieldset(1)).getByLabelText(/^Country/)).toBeDisabled();
		expect(screen.queryByRole("button", { name: "Save prices" })).toBeNull();
		expect(screen.queryByRole("button", { name: "Add country" })).toBeNull();
	});

	it("says when there are none, and when they can't load", async () => {
		vi.mocked(catalogueApi.countryPrices).mockResolvedValue([]);
		const { unmount } = renderWithRouter(<CountryPricesCard packageId={5} />);
		expect(await screen.findByText("No country prices yet.")).toBeInTheDocument();
		unmount();
		vi.mocked(catalogueApi.countryPrices).mockRejectedValue(new Error("offline"));
		renderWithRouter(<CountryPricesCard packageId={5} />);
		expect(await screen.findByText("The country prices could not be loaded.")).toBeInTheDocument();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderWithRouter(<CountryPricesCard packageId={5} />);
		expect(await screen.findByText("الأسعار حسب الدولة")).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "حفظ الأسعار" })).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/catalogue`
Expected: FAIL (no `CountryPricesCard`, `usePackagePrice`, API methods or fixtures).

- [ ] **Step 3: Implement the data layer**

`schemas.ts` (add `import { minorDigits } from "@/lib/money";`), append:

```ts
/** B3d §4.1: one row of a package's prices by country. */
export interface CountryPrice {
	country: string;
	price_minor: number;
	currency: string;
}

/** B3d D-8: what a subscription form prefills. */
export interface PackagePrice {
	price_minor: number;
	currency: string;
	source: "country" | "package";
}

const MAJOR = /^\d+(\.\d+)?$/;
const CODE3 = /^[A-Z]{3}$/;

/** A price in its own row's currency: no more decimals than it has. */
export const countryPricesFormSchema = z.object({
	rows: z
		.array(
			z
				.object({
					country: z.string().regex(/^[A-Z]{2}$/, "catalogue.countryPrices.errors.country"),
					currency: z.string().regex(CODE3, "catalogue.countryPrices.errors.currency"),
					price: z.string().trim(),
				})
				.superRefine((row, ctx) => {
					const fraction = row.price.split(".")[1] ?? "";
					const digits = CODE3.test(row.currency) ? minorDigits(row.currency) : 2;
					if (!MAJOR.test(row.price) || fraction.length > digits) {
						ctx.addIssue({
							code: "custom",
							path: ["price"],
							message: "catalogue.countryPrices.errors.price",
						});
					}
				}),
		)
		.superRefine((rows, ctx) => {
			const seen = new Set<string>();
			rows.forEach((row, index) => {
				if (row.country && seen.has(row.country)) {
					ctx.addIssue({
						code: "custom",
						path: [index, "country"],
						message: "catalogue.countryPrices.errors.repeated",
					});
				}
				seen.add(row.country);
			});
		}),
});
export type CountryPricesFormValues = z.infer<typeof countryPricesFormSchema>;
```

`api.ts`, inside `catalogueApi` (import the two types from `./schemas`):

```ts
	/** B3d §4.1: a package's prices by country, replaced as one list. */
	countryPrices: async (packageId: number) =>
		(await api.get<CountryPrice[]>(`catalogue/packages/${packageId}/country-prices/`)).data,
	setCountryPrices: async ({ packageId, rows }: { packageId: number; rows: CountryPrice[] }) =>
		(await api.put<CountryPrice[]>(`catalogue/packages/${packageId}/country-prices/`, rows)).data,
	/** B3d D-8: the price for a student's country, or the package's own. */
	price: async (packageId: number, studentId?: number) =>
		(
			await api.get<PackagePrice>(`catalogue/packages/${packageId}/price/`, {
				params: studentId === undefined ? {} : { student: studentId },
			})
		).data,
```

`queries.ts`, append (import `CountryPrice` from `./schemas`):

```ts
/** B3d D-8: every resolved price lives under this key. */
export const packagePriceKey = ["catalogue", "price"] as const;

function asId(value: string | number | undefined): number | undefined {
	const n =
		typeof value === "number" ? value : /^\d+$/.test(value ?? "") ? Number(value) : Number.NaN;
	return Number.isInteger(n) && n > 0 ? n : undefined;
}

/** B3d §7 (R2): the price and currency a subscription form prefills, for
 * the student's country, or the package's own without a student. Pending
 * only while a chosen package's price is on its way. */
export function usePackagePrice(
	packageId?: string | number,
	studentId?: string | number,
) {
	const pkg = asId(packageId);
	const student = asId(studentId);
	const query = useQuery({
		queryKey: [...packagePriceKey, pkg, student ?? null],
		queryFn: () => catalogueApi.price(pkg as number, student),
		enabled: pkg !== undefined,
	});
	return {
		data: query.data,
		isPending: pkg !== undefined && query.isPending,
		isError: query.isError,
	};
}

export function useCountryPrices(packageId: number) {
	return useQuery({
		queryKey: [...catalogueKey("packages"), "country-prices", packageId],
		queryFn: () => catalogueApi.countryPrices(packageId),
	});
}

export function useSaveCountryPrices(packageId: number) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (rows: CountryPrice[]) => catalogueApi.setCountryPrices({ packageId, rows }),
		onSuccess: () =>
			Promise.all([
				qc.invalidateQueries({ queryKey: catalogueKey("packages") }),
				qc.invalidateQueries({ queryKey: packagePriceKey }),
			]),
	});
}
```

`index.ts`: export `CountryPricesCard` from `./CountryPricesCard`, add `packagePriceKey`, `useCountryPrices`, `usePackagePrice`, `useSaveCountryPrices` to the `./queries` export, `CountryPrice`, `CountryPricesFormValues`, `PackagePrice` to the type export and `countryPricesFormSchema` to the schema export.

- [ ] **Step 4: Implement the card and the route**

Create `src/features/catalogue/CountryPricesCard.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { Plus, Trash2 } from "lucide-react";
import { useMemo } from "react";
import { type Path, useFieldArray, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { parseApiError } from "@/features/identity/api";
import { useCan } from "@/features/identity/permissions";
import { countryOptions } from "@/lib/countries";
import { CURRENCIES } from "@/lib/currencies";
import { useFieldError } from "@/lib/field-error";
import { errorText } from "@/lib/form-errors";
import { toMajor, toMinor } from "@/lib/money";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
	Field,
	Input,
	Select,
	Spinner,
	SubmitButton,
	toast,
} from "@/ui";
import { useCountryPrices, useSaveCountryPrices } from "./queries";
import {
	type CountryPrice,
	type CountryPricesFormValues,
	countryPricesFormSchema,
} from "./schemas";

const ROW_ERROR = /^rows\[(\d+)\]\.(country|currency|price_minor)$/;
const toRow = (row: CountryPrice) => ({
	country: row.country,
	currency: row.currency,
	price: toMajor(row.price_minor, row.currency),
});
/** The curated codes, plus a row's own code when the API holds another. */
const currencyChoices = (current: string): string[] =>
	!current || (CURRENCIES as readonly string[]).includes(current)
		? [...CURRENCIES]
		: [current, ...CURRENCIES];

/** B3d §6: a package's prices by country (CATALOG-003's repeater), saved
 * as one list (D-9). Shown only for an existing package while
 * `country_pricing` is on (the route decides). */
export function CountryPricesCard({ packageId }: { packageId: number }) {
	const { t } = useTranslation();
	const { data, isError } = useCountryPrices(packageId);
	return (
		<Card>
			<CardHeader>
				<CardTitle>{t("catalogue.countryPrices.title")}</CardTitle>
				<CardDescription>{t("catalogue.countryPrices.body")}</CardDescription>
			</CardHeader>
			<CardContent>
				{isError ? (
					<Alert variant="destructive">
						<AlertDescription>{t("catalogue.countryPrices.loadError")}</AlertDescription>
					</Alert>
				) : data ? (
					<CountryPricesForm key={packageId} packageId={packageId} initial={data} />
				) : (
					<Spinner />
				)}
			</CardContent>
		</Card>
	);
}

function CountryPricesForm({
	packageId,
	initial,
}: {
	packageId: number;
	initial: CountryPrice[];
}) {
	const { t, i18n } = useTranslation();
	const fieldError = useFieldError();
	const editable = useCan()("package.update");
	const save = useSaveCountryPrices(packageId);
	const countries = useMemo(() => countryOptions(i18n.language), [i18n.language]);
	const {
		control,
		register,
		handleSubmit,
		reset,
		setError,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<CountryPricesFormValues>({
		resolver: zodResolver(countryPricesFormSchema),
		defaultValues: { rows: initial.map(toRow) },
	});
	const rows = useFieldArray({ control, name: "rows" });

	async function onSubmit(values: CountryPricesFormValues) {
		try {
			const saved = await save.mutateAsync(
				values.rows.map((row) => ({
					country: row.country,
					currency: row.currency,
					price_minor: toMinor(row.price, row.currency),
				})),
			);
			reset({ rows: saved.map(toRow) });
			toast({ description: t("catalogue.countryPrices.saved"), variant: "success" });
		} catch (error) {
			let placed = false;
			for (const [key, message] of Object.entries(parseApiError(error).fieldErrors)) {
				const match = ROW_ERROR.exec(key);
				if (!match) continue;
				const field = match[2] === "price_minor" ? "price" : match[2];
				setError(`rows.${Number(match[1])}.${field}` as Path<CountryPricesFormValues>, {
					message,
				});
				placed = true;
			}
			if (!placed) setError("root.server", { message: errorText(error, t) });
		}
	}

	return (
		<form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4" noValidate>
			{rows.fields.length === 0 ? (
				<p className="text-sm text-muted-foreground">{t("catalogue.countryPrices.empty")}</p>
			) : null}
			{rows.fields.map((row, index) => {
				const currency = watch(`rows.${index}.currency`);
				const rowErrors = errors.rows?.[index];
				const id = (name: string) => `country-price-${index}-${name}`;
				return (
					<fieldset
						key={row.id}
						disabled={!editable}
						className="grid gap-3 rounded-lg border border-border p-3 sm:grid-cols-[2fr_1fr_1fr_auto] sm:items-end"
					>
						<legend className="sr-only">
							{t("catalogue.countryPrices.row", { number: index + 1 })}
						</legend>
						<Field
							id={id("country")}
							label={t("catalogue.countryPrices.country")}
							error={fieldError(rowErrors?.country?.message)}
							required
						>
							<Select {...register(`rows.${index}.country`)}>
								<option value="">—</option>
								{countries.map((c) => (
									<option key={c.code} value={c.code}>
										{c.name}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id={id("currency")}
							label={t("catalogue.packages.currency")}
							error={fieldError(rowErrors?.currency?.message)}
							required
						>
							<Select dir="ltr" {...register(`rows.${index}.currency`)}>
								<option value="">—</option>
								{currencyChoices(currency).map((code) => (
									<option key={code} value={code}>
										{code}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id={id("price")}
							label={t("catalogue.countryPrices.price", { currency })}
							error={fieldError(rowErrors?.price?.message)}
							required
						>
							<Input inputMode="decimal" dir="ltr" {...register(`rows.${index}.price`)} />
						</Field>
						{editable ? (
							<Button
								type="button"
								variant="outline"
								size="sm"
								aria-label={t("catalogue.countryPrices.remove", { number: index + 1 })}
								onClick={() => rows.remove(index)}
							>
								<Trash2 className="size-4" />
							</Button>
						) : null}
					</fieldset>
				);
			})}
			{errors.root?.server ? (
				<Alert variant="destructive">
					<AlertDescription>{fieldError(errors.root.server.message)}</AlertDescription>
				</Alert>
			) : null}
			{editable ? (
				<div className="flex flex-wrap gap-2">
					<Button
						type="button"
						variant="outline"
						size="sm"
						onClick={() => rows.append({ country: "", currency: "", price: "" })}
					>
						<Plus className="size-4" />
						{t("catalogue.countryPrices.add")}
					</Button>
					<SubmitButton pending={isSubmitting} size="sm">
						{t("catalogue.countryPrices.save")}
					</SubmitButton>
				</div>
			) : null}
		</form>
	);
}
```

(The legend gives each `fieldset` its accessible name, so `getByRole("group", { name: "Country price 1" })` finds it.)

`src/routes/_authed/catalogue.packages.$packageId.tsx`: import `CountryPricesCard` from `@/features/catalogue` and `useHasFeature` from `@/features/identity/permissions`; in the component:

```tsx
		const hasFeature = useHasFeature();
		const id = Number(packageId);
		// B3d §6: only once the package exists, while country pricing is on.
		const countryPrices =
			packageId !== "new" && Number.isInteger(id) && id > 0 && hasFeature("country_pricing");
		...
				<PackageForm packageId={packageId} />
				{countryPrices ? (
					<div className="mt-6">
						<CountryPricesCard packageId={id} />
					</div>
				) : null}
```

Locales. `src/locales/en/catalogue.json`, add top-level:

```json
"countryPrices": {
  "title": "Prices by country",
  "body": "Students from these countries pay this price, in this currency, on new subscriptions. Everyone else pays the package price.",
  "empty": "No country prices yet.",
  "row": "Country price {{number}}",
  "country": "Country",
  "price": "Price ({{currency}})",
  "add": "Add country",
  "remove": "Remove row {{number}}",
  "save": "Save prices",
  "saved": "Prices saved.",
  "loadError": "The country prices could not be loaded.",
  "errors": {
    "country": "Choose a country.",
    "currency": "Choose a currency.",
    "price": "Enter a price with no more decimals than the currency has.",
    "repeated": "This country is already in the list."
  }
},
"price": {
  "loadError": "The price for this student could not be loaded."
}
```

`src/locales/ar/catalogue.json`:

```json
"countryPrices": {
  "title": "الأسعار حسب الدولة",
  "body": "يدفع الطلاب من هذه الدول هذا السعر وبهذه العملة في الاشتراكات الجديدة، ويدفع غيرهم سعر الباقة.",
  "empty": "لا توجد أسعار للدول بعد.",
  "row": "سعر الدولة {{number}}",
  "country": "الدولة",
  "price": "السعر ({{currency}})",
  "add": "إضافة دولة",
  "remove": "حذف الصف {{number}}",
  "save": "حفظ الأسعار",
  "saved": "تم حفظ الأسعار.",
  "loadError": "تعذّر تحميل أسعار الدول.",
  "errors": {
    "country": "اختر دولة.",
    "currency": "اختر عملة.",
    "price": "أدخل سعرًا لا تزيد خاناته العشرية على ما تسمح به العملة.",
    "repeated": "هذه الدولة موجودة في القائمة بالفعل."
  }
},
"price": {
  "loadError": "تعذّر تحميل السعر لهذا الطالب."
}
```

(`catalogue.price.loadError` is used by Task 10; both files get it now so the en/ar key-equality test stays green.)

- [ ] **Step 5: Run the tests and the checks, commit**

Run: `$DASH pnpm exec biome check --write src e2e`
Run: `$DASH pnpm vitest run src/features/catalogue src/locales src/routes`
Run: `just test-frontend && just lint-frontend`
Expected: PASS.

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(catalogue): prices by country card and usePackagePrice (B3d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Dashboard — the local payment methods page, the switch and the nav item

**Files:**
- Modify: `dashboard/src/features/billing/schemas.ts`, `api.ts`, `queries.ts`, `index.ts`, `api.test.ts`, `schemas.test.ts`, `dashboard/src/features/finance/landing.ts`, `landing.test.ts`, `dashboard/src/features/shell/nav.ts`, `nav.test.ts`, `AppShell.tsx`, `AppShell.test.tsx`, `dashboard/src/routes/permissions.test.ts`, `dashboard/src/locales/{en,ar}/billing.json`, `dashboard/src/test/billing-fixtures.ts`
- Create: `dashboard/src/features/billing/LocalPayment.tsx`, `LocalMethodsPage.tsx`, `LocalMethodDialog.tsx`, `LocalMethodsPage.test.tsx`, `dashboard/src/routes/_authed/billing.local-methods.tsx`

**Interfaces:**
- Consumes: Task 4's routes; `useFillOnOpen` (`@/features/finance/shared`); `countryOptions`, `CURRENCIES`; `Confirm`.
- Produces:
  - types `BillingSettings`, `LocalCountry`, `LocalMethod`, `LocalMethods`, `InvoiceLocalMethod`; `InvoiceDetail.local_methods: InvoiceLocalMethod[]`; `localMethodFormSchema` / `LocalMethodFormValues`; `localMethodBody(values, logo: File | null, editing: boolean): FormData`; `LOGO_TYPES`, `LOGO_MAX_BYTES`;
  - `billingApi.settings()`, `updateSettings(body)`, `localMethods()`, `createLocalMethod(body: FormData)`, `updateLocalMethod({id, body})`, `deleteLocalMethod(id)`, `setLocalCountry({country, enabled})`;
  - `useBillingSettings(enabled = true)` (key `[...billingKey, "settings"]`), `useLocalMethods()` (key `[...billingKey, "local-methods"]`);
  - `<LocalPaymentSwitch />`, `<LocalMethodsPage />`, `<LocalMethodDialog method? />`;
  - `NavItem.setting?: NavSetting`, `type NavSetting = "localPayment"`, `withSettings(items, settings)`;
  - fixtures `localMethodRow(overrides)`, `localMethods(overrides)`; `invoiceDetail` / `familyInvoice` gain `local_methods: []`.

- [ ] **Step 1: Write the failing tests and fixtures**

`src/test/billing-fixtures.ts`: add `local_methods: [],` to `invoiceDetail`'s and `familyInvoice`'s objects (next to `can_pay_online: []`), import `LocalMethod`, `LocalMethods` and add:

```ts
export function localMethodRow(overrides: Partial<LocalMethod> = {}): LocalMethod {
	return {
		id: 61,
		country: "SA",
		name: "Bank transfer",
		currency: "",
		is_active: true,
		logo_url: null,
		instructions: "IBAN SA03 8000\nWrite the invoice number.",
		position: 0,
		updated_at: "2026-06-01T08:00:00Z",
		...overrides,
	};
}

export function localMethods(overrides: Partial<LocalMethods> = {}): LocalMethods {
	return {
		countries: [{ country: "SA", enabled: true }],
		methods: [
			localMethodRow(),
			localMethodRow({ id: 62, name: "STC Pay", currency: "SAR", position: 1, logo_url: "/media/stc.png" }),
		],
		...overrides,
	};
}
```

`src/features/billing/api.test.ts`: add `put: vi.fn(ok),` to the mocked `api`, and:

```ts
	it("reads and writes the local payment routes (B3d §5)", async () => {
		await billingApi.settings();
		expect(api.get).toHaveBeenLastCalledWith("billing/settings/");
		await billingApi.updateSettings({ local_payment_enabled: true });
		expect(api.patch).toHaveBeenLastCalledWith("billing/settings/", { local_payment_enabled: true });
		await billingApi.localMethods();
		expect(api.get).toHaveBeenLastCalledWith("billing/local-methods/");
		const body = new FormData();
		await billingApi.createLocalMethod(body);
		expect(api.post).toHaveBeenLastCalledWith("billing/local-methods/", body);
		await billingApi.updateLocalMethod({ id: 4, body: { is_active: false } });
		expect(api.patch).toHaveBeenLastCalledWith("billing/local-methods/4/", { is_active: false });
		await billingApi.deleteLocalMethod(4);
		expect(api.delete).toHaveBeenLastCalledWith("billing/local-methods/4/");
		await billingApi.setLocalCountry({ country: "SA", enabled: false });
		expect(api.put).toHaveBeenLastCalledWith("billing/local-countries/SA/", { enabled: false });
	});
```

`src/features/billing/schemas.test.ts`, add (import `localMethodBody`, `localMethodFormSchema`):

```ts
describe("local method form (B3d §4.3)", () => {
	const values = {
		country: "SA",
		name: "STC Pay",
		currency: "SAR",
		instructions: "Send to 0500000000",
		position: "1",
		is_active: false,
		remove_logo: true,
	};

	it("needs a country, a name, instructions and a whole position", () => {
		expect(localMethodFormSchema.safeParse(values).success).toBe(true);
		for (const bad of [
			{ country: "" },
			{ name: "  " },
			{ instructions: " " },
			{ instructions: "x".repeat(4001) },
			{ position: "-1" },
			{ currency: "SR" },
		]) {
			expect(localMethodFormSchema.safeParse({ ...values, ...bad }).success).toBe(false);
		}
		expect(localMethodFormSchema.safeParse({ ...values, currency: "" }).success).toBe(true);
	});

	it("builds the multipart body: a new logo, or an empty one to clear it", () => {
		const logo = new File(["x"], "logo.png", { type: "image/png" });
		const added = localMethodBody(values, logo, false);
		expect(Object.fromEntries(added.entries())).toMatchObject({
			country: "SA",
			name: "STC Pay",
			currency: "SAR",
			position: "1",
			is_active: "false",
		});
		expect(added.get("logo")).toBe(logo);
		expect(localMethodBody(values, null, true).get("logo")).toBe("");
		expect(localMethodBody(values, null, false).has("logo")).toBe(false);
		expect(localMethodBody({ ...values, remove_logo: false }, null, true).has("logo")).toBe(false);
	});
});
```

`src/features/finance/landing.test.ts`, add:

```ts
	it("lands on local payment methods last, for staff who may see only them", () => {
		expect(
			billingLanding({ ...staffMe("payment_method.view_any"), features: ["invoices"] }),
		).toBe("/billing/local-methods");
		expect(
			billingLanding({ ...staffMe("invoice.view_any", "payment_method.view_any"), features: ["invoices"] }),
		).toBe("/billing/invoices");
	});
```

`src/features/shell/nav.test.ts`:
- in "ships the grouped admin areas in order", add `"/billing/local-methods",` after `"/billing/exchange-rates",`;
- in "hides the items of every feature the academy has switched off", add `"/billing/local-methods",` to the list;
- in "names a feature on exactly the items that belong to one", add `"/billing/local-methods": "invoices",` after the exchange-rates row;
- in "groups consecutive items", add `"billing.local.nav",` after `"finance.nav.exchangeRates",`;
- a new block (import `withSettings`):

```ts
describe("withSettings (B3d plan P5)", () => {
	it("keeps a setting's item only while that setting is on", () => {
		const local = NAV_ITEMS.filter((i) => i.setting === "localPayment");
		expect(local.map((i) => i.to)).toEqual(["/billing/local-methods"]);
		expect(withSettings(local, { localPayment: true })).toEqual(local);
		expect(withSettings(local, { localPayment: false })).toEqual([]);
		expect(withSettings(local, {})).toEqual([]); // still loading
		const plain = NAV_ITEMS.filter((i) => !i.setting);
		expect(withSettings(plain, {})).toEqual(plain);
	});
});
```

`src/features/shell/AppShell.test.tsx` (import `billingApi` from `@/features/billing/api` and `adminWith` from `@/test/access-fixtures`), add:

```tsx
describe("AppShell local payment item (B3d)", () => {
	afterEach(() => vi.restoreAllMocks());

	it("shows Local payment methods only while the setting is on", async () => {
		const settings = vi
			.spyOn(billingApi, "settings")
			.mockResolvedValue({ local_payment_enabled: false });
		me = adminWith("invoices");
		const { unmount } = renderShell();
		await waitFor(() => expect(settings).toHaveBeenCalled());
		expect(screen.queryByRole("link", { name: "Local payment methods" })).toBeNull();
		unmount();
		settings.mockResolvedValue({ local_payment_enabled: true });
		renderShell();
		expect((await screen.findAllByRole("link", { name: "Local payment methods" }))[0]).toHaveAttribute(
			"href",
			"/billing/local-methods",
		);
	});
});
```

(If the file's other tests render an admin without mocking `billingApi.settings`, add a `vi.spyOn(billingApi, "settings").mockResolvedValue({ local_payment_enabled: false })` to their `beforeEach` so no real request is attempted.)

`src/routes/permissions.test.ts`: `"/_authed/billing/local-methods": "invoices",` in `FEATURE_SCREENS` (after B3h's exchange-rates row), and add `|local-methods` to the `FEATURE_WORDS` regex.

Create `src/features/billing/LocalMethodsPage.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { staffMe } from "@/test/access-fixtures";
import { localMethodRow, localMethods } from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { billingApi } from "./api";
import { LocalMethodsPage } from "./LocalMethodsPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		billingApi: {
			...actual.billingApi,
			settings: vi.fn(),
			updateSettings: vi.fn(),
			localMethods: vi.fn(),
			createLocalMethod: vi.fn(),
			updateLocalMethod: vi.fn(),
			deleteLocalMethod: vi.fn(),
			setLocalCountry: vi.fn(),
		},
	};
});

const item = (name: string) => screen.getByRole("listitem", { name });
const png = () => new File([new Uint8Array(10)], "logo.png", { type: "image/png" });

describe("LocalMethodsPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(billingApi.settings).mockResolvedValue({ local_payment_enabled: true });
		vi.mocked(billingApi.updateSettings).mockResolvedValue({ local_payment_enabled: false });
		vi.mocked(billingApi.localMethods).mockResolvedValue(localMethods());
		vi.mocked(billingApi.createLocalMethod).mockResolvedValue(localMethodRow());
		vi.mocked(billingApi.updateLocalMethod).mockResolvedValue(localMethodRow());
		vi.mocked(billingApi.deleteLocalMethod).mockResolvedValue(undefined);
		vi.mocked(billingApi.setLocalCountry).mockResolvedValue({ country: "SA", enabled: false });
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("groups the methods by country with their currency, logo and order", async () => {
		renderWithRouter(<LocalMethodsPage />);
		expect(await screen.findByRole("heading", { name: /Saudi Arabia/ })).toBeInTheDocument();
		expect(within(item("Bank transfer")).getByText("Any currency")).toBeInTheDocument();
		expect(within(item("STC Pay")).getByText("SAR")).toBeInTheDocument();
		expect(within(item("STC Pay")).getByRole("presentation")).toHaveAttribute("src", "/media/stc.png");
		expect(within(item("STC Pay")).getByText("Position 1")).toBeInTheDocument();
	});

	it("switches local payment, a country and a method", async () => {
		const user = userEvent.setup();
		renderWithRouter(<LocalMethodsPage />);
		const local = await screen.findByRole("checkbox", { name: "Show local payment methods on invoices" });
		await waitFor(() => expect(local).toBeChecked());
		await user.click(local);
		await waitFor(() =>
			expect(billingApi.updateSettings).toHaveBeenCalledWith({ local_payment_enabled: false }),
		);
		await user.click(screen.getByRole("checkbox", { name: "Offer in Saudi Arabia" }));
		await waitFor(() =>
			expect(billingApi.setLocalCountry).toHaveBeenCalledWith({ country: "SA", enabled: false }),
		);
		await user.click(within(item("STC Pay")).getByRole("checkbox", { name: "Active" }));
		await waitFor(() =>
			expect(billingApi.updateLocalMethod).toHaveBeenCalledWith({ id: 62, body: { is_active: false } }),
		);
	});

	it("adds a method with a logo, as multipart", async () => {
		const user = userEvent.setup();
		renderWithRouter(<LocalMethodsPage />);
		await user.click(await screen.findByRole("button", { name: "Add method" }));
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(within(dialog).getByLabelText(/^Country/), "SA");
		await user.type(within(dialog).getByLabelText(/^Name/), "Al Rajhi");
		await user.selectOptions(within(dialog).getByLabelText(/^Currency/), "SAR");
		await user.type(within(dialog).getByLabelText(/^Instructions/), "Line one{Enter}Line two");
		await user.upload(within(dialog).getByLabelText(/^Logo/), png());
		await user.click(within(dialog).getByRole("button", { name: "Save method" }));
		await waitFor(() => expect(billingApi.createLocalMethod).toHaveBeenCalled());
		const body = vi.mocked(billingApi.createLocalMethod).mock.calls[0][0] as FormData;
		expect(body.get("name")).toBe("Al Rajhi");
		expect(body.get("instructions")).toBe("Line one\nLine two");
		expect(body.get("is_active")).toBe("true");
		expect((body.get("logo") as File).name).toBe("logo.png");
		expect(await screen.findByText("Method saved.")).toBeInTheDocument();
	});

	it("refuses a GIF or an over-1-MB logo before sending", async () => {
		const user = userEvent.setup({ applyAccept: false });
		renderWithRouter(<LocalMethodsPage />);
		await user.click(await screen.findByRole("button", { name: "Add method" }));
		const dialog = screen.getByRole("dialog");
		await user.upload(
			within(dialog).getByLabelText(/^Logo/),
			new File(["GIF89a"], "a.gif", { type: "image/gif" }),
		);
		expect(within(dialog).getByText("Choose a PNG, JPEG or WEBP image.")).toBeInTheDocument();
		await user.upload(
			within(dialog).getByLabelText(/^Logo/),
			new File([new Uint8Array(1024 * 1024 + 1)], "big.png", { type: "image/png" }),
		);
		expect(within(dialog).getByText("The logo must be at most 1 MB.")).toBeInTheDocument();
	});

	it("edits a method, filling the dialog once, and clears its logo", async () => {
		const user = userEvent.setup();
		renderWithRouter(<LocalMethodsPage />);
		await user.click(await within(await screen.findByRole("listitem", { name: "STC Pay" })).findByRole("button", { name: "Edit STC Pay" }));
		const dialog = screen.getByRole("dialog");
		await waitFor(() => expect(within(dialog).getByLabelText(/^Name/)).toHaveValue("STC Pay"));
		expect(within(dialog).getByLabelText(/^Position/)).toHaveValue("1");
		await user.click(within(dialog).getByRole("checkbox", { name: "Remove the logo" }));
		await user.click(within(dialog).getByRole("button", { name: "Save method" }));
		await waitFor(() => expect(billingApi.updateLocalMethod).toHaveBeenCalled());
		const { id, body } = vi.mocked(billingApi.updateLocalMethod).mock.calls[0][0] as {
			id: number;
			body: FormData;
		};
		expect(id).toBe(62);
		expect(body.get("logo")).toBe("");
	});

	it("shows the server's refusal on its field", async () => {
		vi.mocked(billingApi.createLocalMethod).mockRejectedValue(
			Object.assign(new Error("bad"), {
				isAxiosError: true,
				response: { status: 400, data: { logo: ["This file is not a valid image."] } },
			}),
		);
		const user = userEvent.setup();
		renderWithRouter(<LocalMethodsPage />);
		await user.click(await screen.findByRole("button", { name: "Add method" }));
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(within(dialog).getByLabelText(/^Country/), "SA");
		await user.type(within(dialog).getByLabelText(/^Name/), "X");
		await user.type(within(dialog).getByLabelText(/^Instructions/), "Y");
		await user.upload(within(dialog).getByLabelText(/^Logo/), png());
		await user.click(within(dialog).getByRole("button", { name: "Save method" }));
		expect(await within(dialog).findByText("This file is not a valid image.")).toBeInTheDocument();
	});

	it("deletes behind a confirmation", async () => {
		const user = userEvent.setup();
		renderWithRouter(<LocalMethodsPage />);
		await user.click(await within(await screen.findByRole("listitem", { name: "Bank transfer" })).findByRole("button", { name: "Delete" }));
		await user.click(await screen.findByRole("button", { name: "Delete this method" }));
		await waitFor(() => expect(billingApi.deleteLocalMethod).toHaveBeenCalledWith(61));
		expect(await screen.findByText("Method deleted.")).toBeInTheDocument();
	});

	it("is read-only for staff who may only view", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("payment_method.view_any")}>
				<LocalMethodsPage />
			</CanProvider>,
		);
		await screen.findByRole("heading", { name: /Saudi Arabia/ });
		expect(screen.queryByRole("button", { name: "Add method" })).toBeNull();
		expect(screen.queryByRole("button", { name: /^Edit/ })).toBeNull();
		expect(screen.queryByRole("button", { name: "Delete" })).toBeNull();
		expect(screen.getByRole("checkbox", { name: "Show local payment methods on invoices" })).toBeDisabled();
		expect(screen.getByRole("checkbox", { name: "Offer in Saudi Arabia" })).toBeDisabled();
	});

	it("says when there are none, and when they can't load", async () => {
		vi.mocked(billingApi.localMethods).mockResolvedValue({ countries: [], methods: [] });
		const { unmount } = renderWithRouter(<LocalMethodsPage />);
		expect(await screen.findByText("No local payment methods yet.")).toBeInTheDocument();
		unmount();
		vi.mocked(billingApi.localMethods).mockRejectedValue(new Error("offline"));
		renderWithRouter(<LocalMethodsPage />);
		expect(await screen.findByText("The local payment methods could not be loaded.")).toBeInTheDocument();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderWithRouter(<LocalMethodsPage />);
		expect(await screen.findByRole("button", { name: "إضافة طريقة" })).toBeInTheDocument();
		expect(screen.getByText("أي عملة")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/billing src/features/finance src/features/shell src/routes`
Expected: FAIL (no local payment API, schema, page, nav item).

- [ ] **Step 3: Implement the data layer**

`schemas.ts` (billing), append and extend `InvoiceDetail`:

```ts
/** B3d D-11: the academy's billing settings. */
export interface BillingSettings {
	local_payment_enabled: boolean;
}
export interface LocalCountry {
	country: string;
	enabled: boolean;
}
/** B3d §4.3: one local way to pay; a blank currency is shown for any. */
export interface LocalMethod {
	id: number;
	country: string;
	name: string;
	currency: string;
	is_active: boolean;
	logo_url: string | null;
	instructions: string;
	position: number;
	updated_at: string;
}
export interface LocalMethods {
	countries: LocalCountry[];
	methods: LocalMethod[];
}
/** B3d D-15: what an invoice's reader sees. */
export interface InvoiceLocalMethod {
	id: number;
	name: string;
	logo_url: string | null;
	instructions: string;
}
// in InvoiceDetail: /** B3d D-15: the local ways to pay it. */ local_methods: InvoiceLocalMethod[];

export const LOGO_TYPES = ["image/png", "image/jpeg", "image/webp"] as const;
export const LOGO_MAX_BYTES = 1024 * 1024;

export const localMethodFormSchema = z.object({
	country: z.string().regex(/^[A-Z]{2}$/, "billing.local.errors.country"),
	name: z
		.string()
		.trim()
		.min(1, "billing.local.errors.name")
		.max(120, "billing.local.errors.nameLong"),
	currency: z.string().regex(/^([A-Z]{3})?$/, "billing.local.errors.currency"),
	instructions: z
		.string()
		.trim()
		.min(1, "billing.local.errors.instructions")
		.max(4000, "billing.local.errors.instructionsLong"),
	position: z.string().regex(/^\d{1,4}$/, "billing.local.errors.position"),
	is_active: z.boolean(),
	remove_logo: z.boolean(),
});
export type LocalMethodFormValues = z.infer<typeof localMethodFormSchema>;

/** The multipart body: a chosen logo goes as a file; editing with "remove"
 * ticked sends `logo=""` (plan P13). */
export function localMethodBody(
	values: LocalMethodFormValues,
	logo: File | null,
	editing: boolean,
): FormData {
	const body = new FormData();
	body.append("country", values.country);
	body.append("name", values.name);
	body.append("currency", values.currency);
	body.append("instructions", values.instructions);
	body.append("position", values.position);
	body.append("is_active", values.is_active ? "true" : "false");
	if (logo) body.append("logo", logo);
	else if (editing && values.remove_logo) body.append("logo", "");
	return body;
}
```

`api.ts` (billing), inside `billingApi`, with the types imported:

```ts
	/** B3d §4.3: the local payment switch, methods and country toggles. */
	settings: async () => (await api.get<BillingSettings>("billing/settings/")).data,
	updateSettings: async (body: BillingSettings) =>
		(await api.patch<BillingSettings>("billing/settings/", body)).data,
	localMethods: async () => (await api.get<LocalMethods>(LOCAL)).data,
	createLocalMethod: async (body: FormData) =>
		(await api.post<LocalMethod>(LOCAL, body)).data,
	updateLocalMethod: async ({ id, body }: { id: number; body: FormData | { is_active: boolean } }) =>
		(await api.patch<LocalMethod>(`${LOCAL}${id}/`, body)).data,
	deleteLocalMethod: async (id: number) => {
		await api.delete(`${LOCAL}${id}/`);
	},
	setLocalCountry: async ({ country, enabled }: LocalCountry) =>
		(await api.put<LocalCountry>(`billing/local-countries/${country}/`, { enabled })).data,
```

with `const LOCAL = "billing/local-methods/";` beside `I`.

`queries.ts` (billing), append:

```ts
/** B3d D-11: the local payment switch. `enabled` lets the shell ask only
 * when its nav item could show (plan P5). */
export function useBillingSettings(enabled = true) {
	return useQuery({
		queryKey: [...billingKey, "settings"],
		queryFn: billingApi.settings,
		enabled,
	});
}

export function useLocalMethods() {
	return useQuery({
		queryKey: [...billingKey, "local-methods"],
		queryFn: billingApi.localMethods,
	});
}
```

`index.ts` (billing): export `LocalMethodsPage`, `LocalMethodDialog`, and from `./LocalPayment` `LocalPaymentSwitch` (Task 8 adds `LocalPaymentCard`, `LocalPaymentMethods` there).

- [ ] **Step 4: Implement the switch, the dialog and the page**

Create `src/features/billing/LocalPayment.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";
import { errorText } from "@/lib/form-errors";
import { Checkbox, Spinner, toast } from "@/ui";
import { billingApi } from "./api";
import { useBillingMutation, useBillingSettings } from "./queries";

/** B3d D-11: SYS-003's switch, on the methods page and the settings card. */
export function LocalPaymentSwitch() {
	const { t } = useTranslation();
	const can = useCan();
	const { data } = useBillingSettings();
	const save = useBillingMutation(billingApi.updateSettings);
	if (!data) return <Spinner />;
	return (
		<div className="flex items-start gap-3">
			<Checkbox
				id="local-payment-enabled"
				checked={data.local_payment_enabled}
				disabled={!can("payment_method.update") || save.isPending}
				onCheckedChange={(value) =>
					save.mutate(
						{ local_payment_enabled: value },
						{
							onSuccess: () =>
								toast({ description: t("billing.local.switchSaved"), variant: "success" }),
							onError: (error) =>
								toast({ description: errorText(error, t), variant: "destructive" }),
						},
					)
				}
			/>
			<div className="flex flex-col gap-0.5">
				<label htmlFor="local-payment-enabled" className="font-medium">
					{t("billing.local.switch")}
				</label>
				<p className="text-sm text-muted-foreground">{t("billing.local.switchHint")}</p>
			</div>
		</div>
	);
}
```

Create `src/features/billing/LocalMethodDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useMemo, useState } from "react";
import { useController, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFillOnOpen } from "@/features/finance/shared";
import { countryOptions } from "@/lib/countries";
import { CURRENCIES } from "@/lib/currencies";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
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
	Input,
	Select,
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { billingApi } from "./api";
import { useBillingMutation } from "./queries";
import {
	LOGO_MAX_BYTES,
	LOGO_TYPES,
	type LocalMethod,
	type LocalMethodFormValues,
	localMethodBody,
	localMethodFormSchema,
} from "./schemas";

/** B3d §6: add a local method, or (with `method`) edit one. Plain-text
 * instructions (D-13); an optional PNG, JPEG or WEBP logo up to 1 MB (D-14). */
export function LocalMethodDialog({ method }: { method?: LocalMethod }) {
	const { t } = useTranslation();
	const [open, setOpen] = useState(false);
	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				{method ? (
					<Button size="sm" variant="outline" aria-label={t("billing.local.editFor", { name: method.name })}>
						{t("billing.local.edit")}
					</Button>
				) : (
					<Button size="sm">{t("billing.local.add")}</Button>
				)}
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{method ? t("billing.local.editTitle") : t("billing.local.add")}</DialogTitle>
				<DialogDescription>{t("billing.local.dialogBody")}</DialogDescription>
				{/* Keyed: the add and edit branches never share input state. */}
				<LocalMethodForm key={method?.id ?? "new"} method={method} open={open} onDone={() => setOpen(false)} />
			</DialogContent>
		</Dialog>
	);
}

function LocalMethodForm({
	method,
	open,
	onDone,
}: {
	method?: LocalMethod;
	open: boolean;
	onDone: () => void;
}) {
	const { t, i18n } = useTranslation();
	const fieldError = useFieldError();
	const [logo, setLogo] = useState<File | null>(null);
	const [logoError, setLogoError] = useState<string | undefined>();
	const create = useBillingMutation(billingApi.createLocalMethod);
	const update = useBillingMutation(billingApi.updateLocalMethod);
	const countries = useMemo(() => countryOptions(i18n.language), [i18n.language]);
	const initial = useCallback(
		(): LocalMethodFormValues => ({
			country: method?.country ?? "",
			name: method?.name ?? "",
			currency: method?.currency ?? "",
			instructions: method?.instructions ?? "",
			position: String(method?.position ?? 0),
			is_active: method?.is_active ?? true,
			remove_logo: false,
		}),
		[method],
	);
	const {
		register,
		control,
		handleSubmit,
		reset,
		setError,
		setFocus,
		formState: { errors, isSubmitting },
	} = useForm<LocalMethodFormValues>({
		resolver: zodResolver(localMethodFormSchema),
		defaultValues: initial(),
	});
	useFillOnOpen({ open, ready: true, reset, setFocus, initial, first: method ? "name" : "country" });
	const active = useController({ control, name: "is_active" });
	const removeLogo = useController({ control, name: "remove_logo" });

	function chooseLogo(file: File | undefined) {
		setLogoError(undefined);
		setLogo(null);
		if (!file) return;
		if (!(LOGO_TYPES as readonly string[]).includes(file.type)) {
			setLogoError(t("billing.local.errors.logoType"));
		} else if (file.size > LOGO_MAX_BYTES) {
			setLogoError(t("billing.local.errors.logoSize"));
		} else {
			setLogo(file);
		}
	}

	async function onSubmit(values: LocalMethodFormValues) {
		if (logoError) return;
		const body = localMethodBody(values, logo, Boolean(method));
		try {
			if (method) await update.mutateAsync({ id: method.id, body });
			else await create.mutateAsync(body);
			onDone();
			toast({ description: t("billing.local.saved"), variant: "success" });
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.logo) setLogoError(parsed.fieldErrors.logo);
		}
	}

	return (
		<form onSubmit={handleSubmit(onSubmit)} className="mt-4 flex flex-col gap-4" noValidate>
			<div className="grid gap-4 sm:grid-cols-2">
				<Field id="local-method-country" label={t("billing.local.fields.country")} error={fieldError(errors.country?.message)} required>
					<Select {...register("country")}>
						<option value="">—</option>
						{countries.map((c) => (
							<option key={c.code} value={c.code}>
								{c.name}
							</option>
						))}
					</Select>
				</Field>
				<Field id="local-method-name" label={t("billing.local.fields.name")} error={fieldError(errors.name?.message)} required>
					<Input {...register("name")} />
				</Field>
				<Field id="local-method-currency" label={t("billing.local.fields.currency")} error={fieldError(errors.currency?.message)}>
					<Select dir="ltr" {...register("currency")}>
						<option value="">{t("billing.local.anyCurrency")}</option>
						{CURRENCIES.map((code) => (
							<option key={code} value={code}>
								{code}
							</option>
						))}
					</Select>
				</Field>
				<Field id="local-method-position" label={t("billing.local.fields.position")} error={fieldError(errors.position?.message)}>
					<Input inputMode="numeric" dir="ltr" {...register("position")} />
				</Field>
			</div>
			<Field id="local-method-instructions" label={t("billing.local.fields.instructions")} error={fieldError(errors.instructions?.message)} required>
				<Textarea rows={6} dir="auto" {...register("instructions")} />
			</Field>
			<Field id="local-method-logo" label={t("billing.local.fields.logo")} error={logoError}>
				<Input type="file" accept={LOGO_TYPES.join(",")} onChange={(e) => chooseLogo(e.target.files?.[0])} />
			</Field>
			{method?.logo_url && !logo ? (
				<div className="flex items-center gap-3">
					<img src={method.logo_url} alt="" width={48} height={48} className="size-12 rounded-md border border-border object-contain" />
					<Checkbox id="local-method-remove-logo" checked={removeLogo.field.value} onCheckedChange={removeLogo.field.onChange} />
					<label htmlFor="local-method-remove-logo">{t("billing.local.removeLogo")}</label>
				</div>
			) : null}
			<div className="flex items-center gap-2">
				<Checkbox id="local-method-active" checked={active.field.value} onCheckedChange={active.field.onChange} />
				<label htmlFor="local-method-active">{t("billing.local.fields.active")}</label>
			</div>
			{errors.root?.server ? (
				<Alert variant="destructive">
					<AlertDescription>{fieldError(errors.root.server.message)}</AlertDescription>
				</Alert>
			) : null}
			<DialogFooter className="mt-0">
				<DialogClose asChild>
					<Button type="button" variant="outline">
						{t("people.cancel")}
					</Button>
				</DialogClose>
				<SubmitButton pending={isSubmitting}>{t("billing.local.save")}</SubmitButton>
			</DialogFooter>
		</form>
	);
}
```

Create `src/features/billing/LocalMethodsPage.tsx`:

```tsx
import { Landmark } from "lucide-react";
import { useMemo } from "react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { useCan } from "@/features/identity/permissions";
import { errorText } from "@/lib/form-errors";
import { Alert, AlertDescription, Checkbox, EmptyState, Spinner, StatusChip, toast } from "@/ui";
import { billingApi } from "./api";
import { LocalMethodDialog } from "./LocalMethodDialog";
import { LocalPaymentSwitch } from "./LocalPayment";
import { useBillingMutation, useLocalMethods } from "./queries";

/** B3d §6: Billing → Local payment methods: the switch, then the methods
 * grouped by country, each country with its toggle. */
export function LocalMethodsPage() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const { data, isPending, isError } = useLocalMethods();
	const country = useBillingMutation(billingApi.setLocalCountry);
	const update = useBillingMutation(billingApi.updateLocalMethod);
	const remove = useBillingMutation(billingApi.deleteLocalMethod);
	const regions = useMemo(
		() => new Intl.DisplayNames([i18n.language], { type: "region" }),
		[i18n.language],
	);
	const fail = (error: unknown) =>
		toast({ description: errorText(error, t), variant: "destructive" });
	const editable = can("payment_method.update");

	const body = isError ? (
		<Alert variant="destructive">
			<AlertDescription>{t("billing.local.loadError")}</AlertDescription>
		</Alert>
	) : isPending ? (
		<Spinner />
	) : data.countries.length === 0 ? (
		<EmptyState icon={Landmark} title={t("billing.local.empty")} />
	) : (
		data.countries.map(({ country: code, enabled }) => {
			const name = regions.of(code) ?? code;
			return (
				<section key={code} aria-labelledby={`local-${code}`} className="flex flex-col gap-3 rounded-lg border border-border p-4">
					<div className="flex flex-wrap items-center justify-between gap-2">
						<h2 id={`local-${code}`} className="font-semibold">
							{name} <span dir="ltr">({code})</span>
						</h2>
						<div className="flex items-center gap-2">
							<Checkbox
								id={`local-country-${code}`}
								checked={enabled}
								disabled={!editable || country.isPending}
								onCheckedChange={(value) => country.mutate({ country: code, enabled: value }, { onError: fail })}
							/>
							<label htmlFor={`local-country-${code}`}>{t("billing.local.offerIn", { country: name })}</label>
						</div>
					</div>
					<ul className="flex flex-col gap-2">
						{data.methods
							.filter((m) => m.country === code)
							.map((m) => (
								<li key={m.id} aria-label={m.name} className="flex flex-wrap items-center gap-3 rounded-md border border-border p-3">
									{m.logo_url ? (
										<img src={m.logo_url} alt="" width={48} height={48} className="size-12 rounded-md border border-border object-contain" />
									) : null}
									<div className="flex min-w-0 flex-1 flex-col">
										<span className="font-medium">{m.name}</span>
										<span className="text-sm text-muted-foreground">
											{t("billing.local.position", { position: m.position })}
										</span>
									</div>
									<StatusChip>{m.currency || t("billing.local.anyCurrency")}</StatusChip>
									<div className="flex items-center gap-2">
										<Checkbox
											id={`local-method-${m.id}-active`}
											checked={m.is_active}
											disabled={!editable || update.isPending}
											onCheckedChange={(value) => update.mutate({ id: m.id, body: { is_active: value } }, { onError: fail })}
										/>
										<label htmlFor={`local-method-${m.id}-active`}>{t("billing.local.fields.active")}</label>
									</div>
									{editable ? <LocalMethodDialog method={m} /> : null}
									{can("payment_method.delete") ? (
										<Confirm
											action={t("billing.local.delete")}
											title={t("billing.local.deleteTitle")}
											body={t("billing.local.deleteBody")}
											onConfirm={() =>
												remove.mutate(m.id, {
													onSuccess: () => toast({ description: t("billing.local.deleted"), variant: "success" }),
													onError: fail,
												})
											}
										/>
									) : null}
								</li>
							))}
					</ul>
				</section>
			);
		})
	);

	return (
		<div className="flex flex-col gap-6">
			<LocalPaymentSwitch />
			{can("payment_method.create") ? (
				<div>
					<LocalMethodDialog />
				</div>
			) : null}
			{body}
		</div>
	);
}
```

(`EmptyState` takes `icon` and a translated `title`; `StatusChip` without a tone is neutral.)

Create `src/routes/_authed/billing.local-methods.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { LocalMethodsPage } from "@/features/billing";
import { usePageTitle } from "@/features/branding";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/billing/local-methods")({
	staticData: { permission: "payment_method.view_any", feature: "invoices" },
	component: function LocalMethodsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("billing.local.nav"));
		return (
			<>
				<PageHeader title={t("billing.local.nav")} description={t("billing.local.subtitle")} />
				<LocalMethodsPage />
			</>
		);
	},
});
```

- [ ] **Step 5: Wire the landing, the nav and the shell**

`src/features/finance/landing.ts`: append to `BILLING_PAGES`, after B3h's `/billing/exchange-rates` entry:
`{ to: "/billing/local-methods", code: "payment_method.view_any", feature: "invoices" },`.

`src/features/shell/nav.ts`: add `Landmark` to the `lucide-react` import (alphabetical); to `NavItem` add

```ts
	/** B3d (plan P5): shown only while this academy setting is on (the
	 * shell fetches it). */
	setting?: NavSetting;
```

and after `NAV_BADGE_LABELS`:

```ts
/** The academy settings a nav item can depend on (B3d plan P5). */
export type NavSetting = "localPayment";

/** Keeps an item that names a setting only while that setting is on; a
 * setting still loading counts as off. */
export function withSettings(
	items: NavItem[],
	settings: Partial<Record<NavSetting, boolean>>,
): NavItem[] {
	return items.filter((i) => i.setting === undefined || settings[i.setting] === true);
}
```

Under `// ── phase B3 ──`, after B3h's `/billing/exchange-rates` item and before `/settings/gateways`:

```ts
	// B3d: local payment methods, while the academy's setting is on.
	{
		...office(
			"/billing/local-methods",
			"billing.local.nav",
			Landmark,
			"billing",
			"payment_method.view_any",
			"invoices",
		),
		setting: "localPayment",
	},
```

`src/features/shell/AppShell.tsx`: import `useBillingSettings` from `@/features/billing/queries` and `withSettings` from `./nav`; rename the current `items` to `visible` and add:

```tsx
	// B3d (plan P5): the local-methods item follows the billing setting,
	// asked only while that item could show.
	const { data: billingSettings } = useBillingSettings(
		visible.some((i) => i.setting === "localPayment"),
	);
	const items = withSettings(visible, {
		localPayment: billingSettings?.local_payment_enabled,
	});
```

Locales. `src/locales/en/billing.json`, add top-level `"local"`:

```json
"local": {
  "nav": "Local payment methods",
  "subtitle": "Ways to pay in each country, shown on unpaid invoices.",
  "switch": "Show local payment methods on invoices",
  "switchHint": "Families see the methods of their country on an unpaid invoice. You record their payments by hand.",
  "switchSaved": "Local payment updated.",
  "add": "Add method",
  "edit": "Edit",
  "editFor": "Edit {{name}}",
  "editTitle": "Edit method",
  "dialogBody": "Families see the name, the logo and these instructions on their invoice.",
  "save": "Save method",
  "saved": "Method saved.",
  "delete": "Delete",
  "deleteTitle": "Delete this method",
  "deleteBody": "Families will no longer see it on their invoices.",
  "deleted": "Method deleted.",
  "empty": "No local payment methods yet.",
  "loadError": "The local payment methods could not be loaded.",
  "anyCurrency": "Any currency",
  "position": "Position {{position}}",
  "offerIn": "Offer in {{country}}",
  "removeLogo": "Remove the logo",
  "payLocally": "Pay locally",
  "payLocallyBody": "Pay with one of these, then tell the academy so it can record your payment.",
  "card": "Local payment",
  "manage": "Manage local payment methods",
  "fields": {
    "country": "Country",
    "name": "Name",
    "currency": "Currency",
    "position": "Position",
    "instructions": "Instructions",
    "logo": "Logo (PNG, JPEG or WEBP, up to 1 MB)",
    "active": "Active"
  },
  "errors": {
    "country": "Choose a country.",
    "name": "Enter a name.",
    "nameLong": "Use at most 120 characters.",
    "currency": "Choose a currency.",
    "instructions": "Enter the instructions.",
    "instructionsLong": "Use at most 4000 characters.",
    "position": "Enter a whole number from 0.",
    "logoType": "Choose a PNG, JPEG or WEBP image.",
    "logoSize": "The logo must be at most 1 MB."
  }
}
```

`src/locales/ar/billing.json`:

```json
"local": {
  "nav": "طرق الدفع المحلية",
  "subtitle": "طرق الدفع في كل دولة، تظهر على الفواتير غير المدفوعة.",
  "switch": "إظهار طرق الدفع المحلية على الفواتير",
  "switchHint": "ترى الأسر طرق الدفع الخاصة بدولتها على الفاتورة غير المدفوعة، وتسجّل أنت مدفوعاتها يدويًا.",
  "switchSaved": "تم تحديث الدفع المحلي.",
  "add": "إضافة طريقة",
  "edit": "تعديل",
  "editFor": "تعديل {{name}}",
  "editTitle": "تعديل الطريقة",
  "dialogBody": "ترى الأسر الاسم والشعار وهذه التعليمات على فاتورتها.",
  "save": "حفظ الطريقة",
  "saved": "تم حفظ الطريقة.",
  "delete": "حذف",
  "deleteTitle": "حذف هذه الطريقة",
  "deleteBody": "لن تراها الأسر على فواتيرها بعد الآن.",
  "deleted": "تم حذف الطريقة.",
  "empty": "لا توجد طرق دفع محلية بعد.",
  "loadError": "تعذّر تحميل طرق الدفع المحلية.",
  "anyCurrency": "أي عملة",
  "position": "الترتيب {{position}}",
  "offerIn": "متاحة في {{country}}",
  "removeLogo": "إزالة الشعار",
  "payLocally": "الدفع المحلي",
  "payLocallyBody": "ادفع بإحدى هذه الطرق، ثم أخبر الأكاديمية لتسجّل دفعتك.",
  "card": "الدفع المحلي",
  "manage": "إدارة طرق الدفع المحلية",
  "fields": {
    "country": "الدولة",
    "name": "الاسم",
    "currency": "العملة",
    "position": "الترتيب",
    "instructions": "التعليمات",
    "logo": "الشعار (PNG أو JPEG أو WEBP، حتى 1 ميغابايت)",
    "active": "مفعّلة"
  },
  "errors": {
    "country": "اختر دولة.",
    "name": "أدخل اسمًا.",
    "nameLong": "استخدم 120 حرفًا على الأكثر.",
    "currency": "اختر عملة.",
    "instructions": "أدخل التعليمات.",
    "instructionsLong": "استخدم 4000 حرف على الأكثر.",
    "position": "أدخل عددًا صحيحًا من 0.",
    "logoType": "اختر صورة PNG أو JPEG أو WEBP.",
    "logoSize": "يجب ألا يزيد حجم الشعار على 1 ميغابايت."
  }
}
```

(`payLocally*`, `card` and `manage` are used by Task 8; both files get them now.)

- [ ] **Step 6: Regenerate routes, run the tests and the checks, commit**

Run: `$DASH pnpm exec vite build` (regenerates `routeTree.gen.ts`), then `$DASH pnpm exec biome check --write src e2e`.
Run: `$DASH pnpm vitest run src/features/billing src/features/finance src/features/shell src/routes src/locales`
Run: `just test-frontend && just lint-frontend`
Expected: PASS.

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(billing): local payment methods page, switch and nav item (B3d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Dashboard — the settings card and "Pay locally" on the invoice

**Files:**
- Modify: `dashboard/src/features/billing/LocalPayment.tsx`, `index.ts`, `InvoicePage.tsx`, `InvoicePage.test.tsx`, `dashboard/src/routes/_authed/settings.gateways.tsx`
- Create: `dashboard/src/features/billing/LocalPayment.test.tsx`

**Interfaces:**
- Consumes: Task 7's switch, types and fixtures; `InvoiceDetail.local_methods`.
- Produces: `<LocalPaymentCard />` (switch + link; nothing without `payment_method.view_any` or the `invoices` feature), `<LocalPaymentMethods methods: InvoiceLocalMethod[] />` (nothing when empty).

- [ ] **Step 1: Write the failing tests**

Create `src/features/billing/LocalPayment.test.tsx`:

```tsx
import { act, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { billingApi } from "./api";
import { LocalPaymentCard, LocalPaymentMethods } from "./LocalPayment";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, billingApi: { ...actual.billingApi, settings: vi.fn() } };
});

describe("LocalPaymentMethods (D-15)", () => {
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("renders each method's instructions as text, line breaks kept, no link made", () => {
		const instructions = '<b>IBAN</b> SA03\nSee https://bank.test <a href="https://evil.test">x</a>';
		const { container } = renderWithRouter(
			<LocalPaymentMethods methods={[{ id: 1, name: "Bank transfer", logo_url: "/media/b.png", instructions }]} />,
		);
		expect(screen.getByRole("heading", { name: "Pay locally" })).toBeInTheDocument();
		const text = screen.getByText(/IBAN/);
		expect(text.textContent).toBe(instructions);
		expect(text).toHaveClass("whitespace-pre-line");
		expect(container.querySelector("b")).toBeNull();
		expect(screen.queryByRole("link")).toBeNull();
		expect(screen.getByRole("presentation")).toHaveAttribute("src", "/media/b.png");
	});

	it("renders nothing without methods", () => {
		const { container } = renderWithRouter(<LocalPaymentMethods methods={[]} />);
		expect(container).toBeEmptyDOMElement();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderWithRouter(<LocalPaymentMethods methods={[{ id: 1, name: "STC Pay", logo_url: null, instructions: "x" }]} />);
		expect(screen.getByRole("heading", { name: "الدفع المحلي" })).toBeInTheDocument();
	});
});

describe("LocalPaymentCard", () => {
	beforeEach(() => {
		vi.mocked(billingApi.settings).mockResolvedValue({ local_payment_enabled: true });
	});

	it("shows the switch and links to the methods page", async () => {
		renderWithRouter(<LocalPaymentCard />, { extraPaths: ["/billing/local-methods"] });
		expect(await screen.findByRole("checkbox", { name: "Show local payment methods on invoices" })).toBeChecked();
		expect(screen.getByRole("link", { name: "Manage local payment methods" })).toHaveAttribute(
			"href",
			"/billing/local-methods",
		);
	});

	it("is hidden without the code or with invoices off", () => {
		const { unmount } = renderWithRouter(
			<CanProvider me={staffMe("gateway.view")}>
				<LocalPaymentCard />
			</CanProvider>,
		);
		expect(screen.queryByText("Local payment")).toBeNull();
		unmount();
		renderWithRouter(
			<CanProvider me={adminWith("online_payments")}>
				<LocalPaymentCard />
			</CanProvider>,
		);
		expect(screen.queryByText("Local payment")).toBeNull();
	});
});
```

`src/features/billing/InvoicePage.test.tsx`, add:

```tsx
	it("shows Pay locally when the invoice has local methods, and not otherwise", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({
				local_methods: [{ id: 1, name: "STC Pay", logo_url: null, instructions: "Send to 0500000000" }],
			}),
		);
		const { unmount } = renderWithRouter(<InvoicePage invoiceId="51" admin />);
		expect(await screen.findByRole("heading", { name: "Pay locally" })).toBeInTheDocument();
		expect(screen.getByText("Send to 0500000000")).toBeInTheDocument();
		unmount();
		vi.mocked(billingApi.get).mockResolvedValue(familyInvoice());
		renderWithRouter(<InvoicePage invoiceId="51" admin={false} />);
		await screen.findByText(/INV-/);
		expect(screen.queryByRole("heading", { name: "Pay locally" })).toBeNull();
	});
```

(Match the file's invoice id, fixture imports and first-render wait to its existing tests.)

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/billing/LocalPayment.test.tsx src/features/billing/InvoicePage.test.tsx`
Expected: FAIL (`LocalPaymentCard`, `LocalPaymentMethods` missing).

- [ ] **Step 3: Implement**

`src/features/billing/LocalPayment.tsx`, add (import `Link` from `@tanstack/react-router`, `useHasFeature` from `@/features/identity/permissions`, `Card`, `CardContent`, `CardDescription`, `CardHeader`, `CardTitle` from `@/ui`, `InvoiceLocalMethod` from `./schemas`):

```tsx
/** B3d §6: the "Local payment" card on Settings → Payment gateways. */
export function LocalPaymentCard() {
	const { t } = useTranslation();
	const can = useCan();
	const hasFeature = useHasFeature();
	if (!can("payment_method.view_any") || !hasFeature("invoices")) return null;
	return (
		<Card>
			<CardHeader>
				<CardTitle>{t("billing.local.card")}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				<LocalPaymentSwitch />
				<Link to="/billing/local-methods" className="text-primary-text underline-offset-4 hover:underline">
					{t("billing.local.manage")}
				</Link>
			</CardContent>
		</Card>
	);
}

/** B3d D-15: the invoice's "Pay locally" block, for the family and the
 * office alike. Instructions are text: React escapes them and nothing is
 * linked (D-13, ledger D2); `whitespace-pre-line` keeps their line breaks. */
export function LocalPaymentMethods({ methods }: { methods: InvoiceLocalMethod[] }) {
	const { t } = useTranslation();
	if (methods.length === 0) return null;
	return (
		<Card>
			<CardHeader>
				{/* CardTitle is an h2 already. */}
				<CardTitle>{t("billing.local.payLocally")}</CardTitle>
				<CardDescription>{t("billing.local.payLocallyBody")}</CardDescription>
			</CardHeader>
			<CardContent>
				<ul className="flex flex-col gap-4">
					{methods.map((m) => (
						<li key={m.id} className="flex gap-3">
							{m.logo_url ? (
								// D-14: a 200×200 logo, shown smaller on a phone.
								<img src={m.logo_url} alt="" width={200} height={200} className="size-16 shrink-0 rounded-md border border-border object-contain sm:size-24" />
							) : null}
							<div className="flex min-w-0 flex-col gap-1">
								<h3 className="font-semibold">{m.name}</h3>
								<p className="whitespace-pre-line break-words text-sm">{m.instructions}</p>
							</div>
						</li>
					))}
				</ul>
			</CardContent>
		</Card>
	);
}
```

`index.ts` (billing): also export `LocalPaymentCard`, `LocalPaymentMethods`.

`InvoicePage.tsx`: import `LocalPaymentMethods` from `./LocalPayment` and render, right after the invoice `Card` and before `SubscriptionTermsCard`:

```tsx
			{/* B3d D-15: local ways to pay, next to the route's Pay online. */}
			<LocalPaymentMethods methods={invoice.local_methods ?? []} />
```

`src/routes/_authed/settings.gateways.tsx`: import `LocalPaymentCard` from `@/features/billing` and render it after `<GatewaySettingsPage />` inside a `<div className="mt-6">`.

- [ ] **Step 4: Run, check, commit**

Run: `$DASH pnpm exec biome check --write src e2e`
Run: `$DASH pnpm vitest run src/features/billing src/features/gateways src/routes`
Run: `just test-frontend && just lint-frontend`
Expected: PASS.

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(billing): Pay locally on the invoice and the local payment settings card (B3d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 9: The R2 hook — backend (claimed scheduling files)

**Files:**
- Modify (claimed, B2's): `backend/etqan/scheduling/services/subscriptions.py`, `backend/etqan/scheduling/api/serializers.py`
- Create (claimed): `backend/etqan/scheduling/tests/test_country_pricing.py`
- Modify: `backend/etqan/platform/tests/test_drf.py` (the D25 pin)

**Interfaces:**
- Consumes: `catalogue_services.package_price` (Task 1); `ValidationError(..., code=...)` (already on trunk, plan P1).
- Produces:
  - `create_subscription(..., currency: str | None = None)` and `renew_subscription(..., currency: str | None = None)`, keyword-only, additive;
  - a given `currency` other than the resolved one → `ValidationError(field="price_minor", code="catalogue.price_currency_changed")` → 400 `{"price_minor": [...], "code": "catalogue.price_currency_changed"}`;
  - `SubscriptionCreateInput.currency` and `RenewInput.currency`: optional, 3 letters, upper-cased.

- [ ] **Step 1: Claim the B2 files in the ledger (before any edit)**

B2 delegated R2 to B3 (ledger R2; D-6). Check the claim syntax and that nobody holds these files, then claim each target (the backend and the dashboard ones Task 10 edits):

```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/b3
python3 scripts/orchestration/ledger.py claim --help   # usage: claim --reason REASON phase target
python3 scripts/orchestration/ledger.py show | sed -n '/## Claims and requests/,/## Trunk heads/p'
REASON="B3d: R2 country-pricing hook, delegated by B2 (spec 2026-10-05-b3d §4.2, §7; ledger D23)"
for target in \
  backend/etqan/scheduling/services/subscriptions.py \
  backend/etqan/scheduling/api/serializers.py \
  backend/etqan/scheduling/tests/test_country_pricing.py \
  dashboard/src/features/scheduling/TermFields.tsx \
  dashboard/src/features/scheduling/SubscriptionForm.tsx \
  dashboard/src/features/scheduling/RenewDialog.tsx \
  dashboard/src/features/scheduling/schemas.ts \
  dashboard/src/features/scheduling/TermFields.test.tsx \
  dashboard/src/features/scheduling/SubscriptionForm.test.tsx \
  dashboard/src/features/scheduling/SubscriptionActions.test.tsx
do
  python3 scripts/orchestration/ledger.py claim --reason "$REASON" B3 "$target" || break
done
```

Expected: one `claim <target> for B3` per file. If any claim fails ("… is claimed by B2"), stop: release the ones taken (`python3 scripts/orchestration/ledger.py release B3 <target>`), escalate to the conductor, and do not edit the files.

- [ ] **Step 2: Write the failing tests**

`backend/etqan/platform/tests/test_drf.py`, add:

```python
def test_a_validation_error_names_its_rule_only_when_it_has_one():
    """Ledger D25 (B3d D-20): the optional code reaches the body."""
    resp = exception_handler(
        ValidationError(
            "Now SAR.", field="price_minor", code="catalogue.price_currency_changed"
        ),
        {},
    )
    assert resp.status_code == 400
    assert resp.data == {
        "price_minor": ["Now SAR."],
        "code": "catalogue.price_currency_changed",
    }
    assert exception_handler(ValidationError("bad", field="x"), {}).data == {
        "x": ["bad"]
    }
```

Create `backend/etqan/scheduling/tests/test_country_pricing.py`:

```python
"""B3d hook (ledger R2, D23; spec §4.2): a new or renewed subscription takes
its default price and currency from catalogue's resolver for the student's
country. Every existing scheduling test runs with country_pricing off."""

import pytest

from etqan.billing import services as billing_services
from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Subscription
from etqan.scheduling.tests.conftest import subscription_for

URL = "/api/v1/subscriptions/"
SAR_ROW = {"country": "SA", "price_minor": 45000, "currency": "SAR"}
CHANGED = "catalogue.price_currency_changed"


@pytest.fixture
def saudi(world, set_features):
    """``world``'s student in Saudi Arabia, the Monthly package at 450.00 SAR there."""
    set_features(country_pricing=True)
    catalogue_services.set_country_prices(world.package, [SAR_ROW])
    identity_services.update_person(world.student, profile={"country": "SA"})
    return world


def body(world, **overrides):
    return {
        "student": world.student.id,
        "course": world.course.id,
        "teacher": world.teacher.id,
        "package": world.package.id,
        "starts_on": "2026-06-01",
        **overrides,
    }


def test_a_priced_country_student_gets_the_country_price_and_currency(saudi):
    sub = subscription_for(saudi)
    assert (sub.price_minor, sub.currency) == (45000, "SAR")


def test_with_the_switch_off_the_price_is_todays(saudi, set_features):
    set_features(country_pricing=False)  # Review Focus 1
    sub = subscription_for(saudi)
    assert (sub.price_minor, sub.currency) == (150000, "EGP")


def test_an_explicit_price_is_read_in_the_resolved_currency(saudi):
    sub = subscription_for(saudi, price_minor=40000, currency="sar")
    assert (sub.price_minor, sub.currency) == (40000, "SAR")
    # without a currency, the resolved one
    other = subscription_for(saudi, price_minor=40000)
    assert (other.price_minor, other.currency) == (40000, "SAR")


def test_a_different_currency_is_refused_and_nothing_is_created(saudi):
    with pytest.raises(ValidationError) as caught:
        subscription_for(saudi, price_minor=150000, currency="EGP")
    assert (caught.value.field, caught.value.code) == ("price_minor", CHANGED)
    assert not Subscription.objects.exists()


def test_renewal_keeps_the_amount_paid_while_the_resolved_currency_is_the_same(saudi):
    old = subscription_for(saudi, price_minor=40000)
    new = services.renew_subscription(old)
    assert (new.price_minor, new.currency) == (40000, "SAR")


def test_renewal_takes_the_resolved_price_when_the_currency_changed(world, set_features):
    old = subscription_for(world)  # EGP, before Saudi pricing
    set_features(country_pricing=True)
    catalogue_services.set_country_prices(world.package, [SAR_ROW])
    identity_services.update_person(world.student, profile={"country": "SA"})
    new = services.renew_subscription(old)
    assert (new.price_minor, new.currency) == (45000, "SAR")
    old.refresh_from_db()  # D-7: the snapshot stays
    assert (old.price_minor, old.currency) == (150000, "EGP")


def test_a_renewal_with_a_stale_currency_is_refused(saudi):
    old = subscription_for(saudi)
    with pytest.raises(ValidationError) as caught:
        services.renew_subscription(old, currency="EGP", price_minor=1)
    assert caught.value.code == CHANGED
    assert not Subscription.objects.filter(renewed_from=old).exists()


def test_a_later_change_never_reaches_an_existing_subscription(saudi):
    sub = subscription_for(saudi)
    catalogue_services.set_country_prices(saudi.package, [])
    identity_services.update_person(saudi.student, profile={"country": "EG"})
    sub.refresh_from_db()
    assert (sub.price_minor, sub.currency) == (45000, "SAR")


def test_the_api_takes_currency_and_answers_the_code(api_for, saudi):
    admin = api_for("admin")
    resp = admin.post(URL, body(saudi, price_minor=150000, currency="EGP"), format="json")
    assert resp.status_code == 400, resp.content
    assert set(resp.json()) == {"price_minor", "code"}
    assert resp.json()["code"] == CHANGED  # Review Focus 2
    bad = admin.post(URL, body(saudi, currency="SA"), format="json")
    assert bad.status_code == 400 and "currency" in bad.json()
    resp = admin.post(URL, body(saudi, price_minor=45000, currency="sar"), format="json")
    assert resp.status_code == 201, resp.content
    data = resp.json()
    assert (data["price_minor"], data["currency"]) == (45000, "SAR")
    # the invoice follows the subscription, with no billing change (§4.2)
    invoice = billing_services.invoices_queryset().get(subscription_id=data["id"])
    assert (invoice.amount_minor, invoice.currency) == (45000, "SAR")
    renew = admin.post(f"{URL}{data['id']}/renew/", {"currency": "EGP"}, format="json")
    assert renew.status_code == 400 and renew.json()["code"] == CHANGED
    renew = admin.post(f"{URL}{data['id']}/renew/", {"currency": "SAR"}, format="json")
    assert renew.status_code == 201, renew.content
    assert (renew.json()["price_minor"], renew.json()["currency"]) == (45000, "SAR")
```

- [ ] **Step 3: Run them to verify they fail, and the scheduling suite as it is**

Run: `$DJ pytest etqan/scheduling/tests/test_country_pricing.py etqan/platform/tests/test_drf.py -q`
Expected: the D25 test PASSES already (plan P1); the hook tests FAIL (`TypeError: create_subscription() got an unexpected keyword argument 'currency'`, and the Saudi student gets EGP).
Run: `$DJ pytest etqan/scheduling -q`
Expected: PASS (the baseline every existing test must keep).

- [ ] **Step 4: Implement the service change (additive)**

`backend/etqan/scheduling/services/subscriptions.py`: import `from etqan.platform.validators import clean_currency`; add after `_copy_package`:

```python
def _refuse_other_currency(currency: str | None, price) -> None:
    """B3d D-4 (ledger D23): a form converts its price in the currency it was
    shown; a different resolved one means the prefill went stale (the
    country row or the student's country changed). Code per ledger D25."""
    if currency is not None and clean_currency(currency, "currency") != price.currency:
        raise ValidationError(
            f"The price for this student is now in {price.currency}. "
            "Check the price and try again.",
            field="price_minor",
            code="catalogue.price_currency_changed",
        )
```

In `create_subscription`, add the keyword `currency: str | None = None,` at the end of the keyword-only parameters, and replace

```python
    _copy_package(subscription, package)
    subscription.price_minor = (
        package.price_minor if price_minor is None else price_minor
    )
```

with

```python
    _copy_package(subscription, package)
    # B3d (ledger D23, R2): the default price and currency are those of the
    # student's country, through catalogue's resolver; an explicit price is
    # read in that currency. With country_pricing off this is the package's.
    price = catalogue_services.package_price(
        package, country=subscription.student.country
    )
    _refuse_other_currency(currency, price)
    subscription.currency = price.currency
    subscription.price_minor = price.price_minor if price_minor is None else price_minor
```

In `renew_subscription`, add `currency: str | None = None,` before `by=None,` and replace

```python
    package = _package(package_id or old.package_id)
    if price_minor is None:
        # P4-10: renew at the amount paid, unless the currency changed.
        same_currency = package.currency == old.currency
        price_minor = old.price_minor if same_currency else package.price_minor
```

with

```python
    package = _package(package_id or old.package_id)
    # B3d (D-4): resolved for the old subscription's student and the new
    # package; P4-10 compares with the resolved currency.
    price = catalogue_services.package_price(package, country=old.student.country)
    _refuse_other_currency(currency, price)
    if price_minor is None:
        # P4-10: renew at the amount paid, unless the currency changed.
        same_currency = price.currency == old.currency
        price_minor = old.price_minor if same_currency else price.price_minor
```

and pass `currency=price.currency,` to the inner `create_subscription(...)` call (it resolves the same price in the same transaction, so the check passes).

`backend/etqan/scheduling/api/serializers.py`, add after `_id`:

```python
class CurrencyField(serializers.RegexField):
    """B3d D-4: the currency a form converted its price with, upper-cased;
    the service refuses one the price no longer resolves to."""

    def __init__(self, **kwargs):
        super().__init__(r"^[A-Za-z]{3}$", **kwargs)

    def to_internal_value(self, data):
        return super().to_internal_value(data).upper()
```

and `currency = CurrencyField(required=False)` in `SubscriptionCreateInput` (after `price_minor`) and in `RenewInput` (after `price_minor`). The views already pass the validated body through `_ids(...)` unchanged, so `currency` reaches both services with no view edit.

- [ ] **Step 5: Run, format, lint, commit**

Run: `$DJ pytest etqan/scheduling etqan/billing etqan/catalogue etqan/platform -q`
Expected: PASS — every existing scheduling and billing test unchanged (`country_pricing` is off by default), plus the new file.
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`
Expected: clean (scheduling already imports `etqan.catalogue.services` and `etqan.platform`).

```bash
git -C backend add etqan/scheduling/services/subscriptions.py etqan/scheduling/api/serializers.py etqan/scheduling/tests/test_country_pricing.py etqan/platform/tests/test_drf.py
git -C backend commit -m "feat(scheduling): subscriptions take the country price and currency (B3d, R2 hook)

Delegated by B2 under a ledger claim (ledger R2, D23). Additive:
create_subscription and renew_subscription gain a keyword-only currency;
the create and renew bodies gain an optional currency.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: The R2 hook — dashboard (claimed scheduling files), then release

**Files:**
- Modify (claimed): `dashboard/src/features/scheduling/TermFields.tsx`, `SubscriptionForm.tsx`, `RenewDialog.tsx`, `schemas.ts`, `SubscriptionForm.test.tsx`, `SubscriptionActions.test.tsx`
- Create (claimed): `dashboard/src/features/scheduling/TermFields.test.tsx`
- Modify: `dashboard/src/locales/en/errors.json`, `dashboard/src/locales/ar/errors.json`

**Interfaces:**
- Consumes: `usePackagePrice`, `packagePriceKey` (Task 6); `useFillOnOpen`; Task 9's API.
- Produces: `TermFields` props `studentId?: string | number` and `keep?: KeptPrice` (`{price_minor, currency}`); `SubscriptionBody.currency?: string`, `RenewBody.currency?: string`; both forms send `currency`.

- [ ] **Step 1: Write the failing tests**

`src/locales/en/errors.json`, inside `"catalogue"`: `"price_currency_changed": "The price for this student has changed. Check it and try again."`; `src/locales/ar/errors.json`: `"price_currency_changed": "تغيّر سعر هذا الطالب. راجعه وحاول مرة أخرى."`.

Create `src/features/scheduling/TermFields.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { FormProvider, useForm } from "react-hook-form";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { packagePrice } from "@/test/catalogue-fixtures";
import { renderWithRouter } from "@/test/render";
import { page } from "@/test/scheduling-fixtures";
import { type KeptPrice, TermFields } from "./TermFields";

vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return { ...actual, catalogueApi: { ...actual.catalogueApi, list: vi.fn(), price: vi.fn() } };
});

const monthly = {
	id: 5, name_ar: "شهري", name_en: "Monthly", sessions_total: 8, session_minutes: 45,
	duration_value: 1, duration_unit: "month", price_minor: 150000, currency: "EGP",
};
const SAR = packagePrice({ price_minor: 45000, currency: "SAR", source: "country" });

/** TermFields in a form, with a button that switches to student 12 (EGP). */
function Harness({ keep }: { keep?: KeptPrice }) {
	const [studentId, setStudentId] = useState("11");
	const methods = useForm({
		defaultValues: { course: "3", teacher: "21", package: "5", starts_on: "2026-06-01", price: "" },
	});
	return (
		<FormProvider {...methods}>
			<TermFields studentId={studentId} keep={keep} />
			<button type="button" onClick={() => setStudentId("12")}>
				Other student
			</button>
		</FormProvider>
	);
}

describe("TermFields price (B3d R2)", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(page([{ id: 21, user: { full_name: "Bilal" } }]) as never);
		vi.mocked(catalogueApi.list).mockImplementation(
			async (kind) =>
				(kind === "courses"
					? page([{ id: 3, name_ar: "تجويد", name_en: "Tajweed", teacher_ids: [21] }])
					: page([monthly])) as never,
		);
		vi.mocked(catalogueApi.price).mockImplementation(async (_pkg, student) =>
			student === 11 ? SAR : packagePrice(),
		);
	});

	it("prefills the student's country price and labels its currency", async () => {
		renderWithRouter(<Harness />);
		await waitFor(() => expect(screen.getByLabelText(/^Price \(SAR\)/)).toHaveValue("450.00"));
		expect(catalogueApi.price).toHaveBeenCalledWith(5, 11);
	});

	it("resets the price when the resolved currency changes, and keeps typing otherwise", async () => {
		const user = userEvent.setup();
		renderWithRouter(<Harness />);
		const field = await screen.findByLabelText(/^Price \(SAR\)/);
		await waitFor(() => expect(field).toHaveValue("450.00"));
		await user.clear(field);
		await user.type(field, "400");
		expect(field).toHaveValue("400");
		await user.click(screen.getByRole("button", { name: "Other student" }));
		await waitFor(() => expect(screen.getByLabelText(/^Price \(EGP\)/)).toHaveValue("1500.00"));
	});

	it("keeps the amount paid while the resolved currency is the subscription's (P4-10)", async () => {
		const { unmount } = renderWithRouter(
			<Harness keep={{ price_minor: 40000, currency: "SAR" }} />,
		);
		await waitFor(() => expect(screen.getByLabelText(/^Price \(SAR\)/)).toHaveValue("400.00"));
		unmount();
		renderWithRouter(<Harness keep={{ price_minor: 120000, currency: "EGP" }} />);
		await waitFor(() => expect(screen.getByLabelText(/^Price \(SAR\)/)).toHaveValue("450.00"));
	});

	it("says when the price can't be loaded", async () => {
		vi.mocked(catalogueApi.price).mockRejectedValue(new Error("offline"));
		renderWithRouter(<Harness />);
		expect(await screen.findByText("The price for this student could not be loaded.")).toBeInTheDocument();
	});
});
```

`src/features/scheduling/SubscriptionForm.test.tsx`:
- add `price: vi.fn()` to the mocked `catalogueApi`, import `packagePrice` from `@/test/catalogue-fixtures`, and in `beforeEach`: `vi.mocked(catalogueApi.price).mockResolvedValue(packagePrice());`;
- in "creates a subscription with its slots and opens it", the expected body gains `currency: "EGP",` after `price_minor: 150000,`;
- add:

```tsx
	it("prices a student of a priced country in that country's currency", async () => {
		vi.mocked(catalogueApi.price).mockImplementation(async (_pkg, student) =>
			student === 11
				? packagePrice({ price_minor: 45000, currency: "SAR", source: "country" })
				: packagePrice(),
		);
		vi.mocked(schedulingApi.create).mockResolvedValue(subscriptionDetail({ id: 9 }));
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionForm />, {
			extraPaths: ["/scheduling/subscriptions/$subscriptionId"],
		});
		await fillIn(user);
		await waitFor(() => expect(screen.getByLabelText(/^Price \(SAR\)/)).toHaveValue("450.00"));
		await user.click(screen.getByLabelText("Mon"));
		await user.type(screen.getByLabelText(/^Start time/), "18:00");
		await user.click(screen.getByRole("button", { name: "Create subscription" }));
		await waitFor(() =>
			expect(schedulingApi.create).toHaveBeenCalledWith(
				expect.objectContaining({ price_minor: 45000, currency: "SAR" }),
			),
		);
	});

	it("keeps Create disabled while the price is on its way, and after it fails", async () => {
		vi.mocked(catalogueApi.price).mockReturnValue(new Promise(() => {}));
		const user = userEvent.setup();
		const { unmount } = renderWithRouter(<SubscriptionForm />);
		await fillIn(user);
		expect(screen.getByRole("button", { name: "Create subscription" })).toBeDisabled();
		unmount();
		vi.mocked(catalogueApi.price).mockRejectedValue(new Error("offline"));
		renderWithRouter(<SubscriptionForm />);
		await fillIn(user);
		expect(await screen.findByText("The price for this student could not be loaded.")).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Create subscription" })).toBeDisabled();
	});

	it("shows a changed price in words and reads the price again", async () => {
		vi.mocked(schedulingApi.create).mockRejectedValue(
			new AxiosError("bad", "400", undefined, undefined, {
				status: 400,
				data: {
					price_minor: ["The price for this student is now in SAR."],
					code: "catalogue.price_currency_changed",
				},
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionForm />);
		await fillIn(user);
		await waitFor(() => expect(screen.getByLabelText(/^Price/)).toHaveValue("1500.00"));
		const asked = vi.mocked(catalogueApi.price).mock.calls.length;
		await user.click(screen.getByLabelText("Mon"));
		await user.type(screen.getByLabelText(/^Start time/), "18:00");
		await user.click(screen.getByRole("button", { name: "Create subscription" }));
		expect(
			await screen.findByText("The price for this student has changed. Check it and try again."),
		).toBeInTheDocument();
		await waitFor(() =>
			expect(vi.mocked(catalogueApi.price).mock.calls.length).toBeGreaterThan(asked),
		);
	});
```

(Match the existing file's `AxiosError` construction for a 400 if it differs.)

`src/features/scheduling/SubscriptionActions.test.tsx`:
- Renew is disabled until the price resolves (R2): where an existing renew test clicks Renew straight after opening the dialog, first `await waitFor(() => expect(within(dialog).getByLabelText(/^Price/)).toHaveValue(…))` with the value it already expects — the only change to those tests besides the body's `currency`;
- add `price: vi.fn()` to the mocked `catalogueApi`; in `mockChoices()` (or `beforeEach`) `vi.mocked(catalogueApi.price).mockResolvedValue(packagePrice());` (import `packagePrice`);
- in "renews with pre-filled values and opens the renewal", the expected body gains `currency: "EGP",`;
- add:

```tsx
	it("renews at the resolved price when the student's currency is now another", async () => {
		vi.mocked(catalogueApi.price).mockResolvedValue(
			packagePrice({ price_minor: 45000, currency: "SAR", source: "country" }),
		);
		vi.mocked(schedulingApi.renew).mockResolvedValue(subscriptionDetail({ id: 12 }));
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionActions sub={subscriptionDetail({ price_minor: 120000 })} />, {
			extraPaths: [DETAIL],
		});
		await user.click(await screen.findByRole("button", { name: "Renew" }));
		const dialog = await screen.findByRole("dialog");
		await waitFor(() => expect(within(dialog).getByLabelText(/^Price \(SAR\)/)).toHaveValue("450.00"));
		expect(catalogueApi.price).toHaveBeenCalledWith(5, 11);
		await user.click(within(dialog).getByRole("button", { name: "Renew" }));
		await waitFor(() =>
			expect(schedulingApi.renew).toHaveBeenCalledWith(
				7,
				expect.objectContaining({ price_minor: 45000, currency: "SAR" }),
			),
		);
	});

	it("asks no price until the renew dialog opens", async () => {
		renderWithRouter(<SubscriptionActions sub={subscriptionDetail()} />, { extraPaths: [DETAIL] });
		await screen.findByRole("button", { name: "Renew" });
		expect(catalogueApi.price).not.toHaveBeenCalled();
	});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/scheduling/TermFields.test.tsx src/features/scheduling/SubscriptionForm.test.tsx src/features/scheduling/SubscriptionActions.test.tsx`
Expected: FAIL (no `studentId`/`keep`; bodies without `currency`; the price comes from the package list).

- [ ] **Step 3: Implement**

`schemas.ts` (scheduling): add `currency?: string;` after `price_minor?: number;` in `SubscriptionBody` and in `RenewBody`, each with the comment `// B3d (R2): the currency the price was converted with.`

`TermFields.tsx`: add `import { useEffect, useRef } from "react";`, import `usePackagePrice` with `Package` from `@/features/catalogue`, and `Alert`, `AlertDescription` from `@/ui`; then:

```tsx
/** Renew dialog only (P4-10): the amount paid and its currency. */
export interface KeptPrice {
	price_minor: number;
	currency: string;
}
```

Add `studentId` and `keep` to the props:

```tsx
	/** B3d (R2): the student the price is resolved for (their country's
	 * price while country pricing is on). */
	studentId?: string | number;
	/** B3d plan P8: keep this price while the resolved currency is its. */
	keep?: KeptPrice;
```

In the body, after `const pkg = packageById(watch("package"));`:

```tsx
	const packageId = watch("package");
	const price = usePackagePrice(packageId, studentId);
	const currency = price.data?.currency ?? pkg?.currency ?? "";
	// B3d plan P8: the price follows the resolved answer each time the
	// package, the student or the resolved currency changes; typing in
	// between is kept.
	const filledFor = useRef<string | null>(null);
	useEffect(() => {
		const data = price.data;
		if (!data) return;
		const key = `${packageId}|${studentId ?? ""}|${data.currency}`;
		if (filledFor.current === key) return;
		filledFor.current = key;
		const minor =
			keep && keep.currency === data.currency ? keep.price_minor : data.price_minor;
		setValue("price", toMajor(minor, data.currency));
	}, [price.data, packageId, studentId, keep, setValue]);
```

In the package `Select`'s `onChange`, delete the line `setValue("price", toMajor(chosen.price_minor, chosen.currency));` (the effect sets it now) and keep `onPackage?.(chosen);`. The price `Field`'s label becomes `t("scheduling.form.price", { currency })`. After the grid `</div>`, before the package facts:

```tsx
			{price.isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("catalogue.price.loadError")}</AlertDescription>
				</Alert>
			) : null}
```

Update the component's doc comment: "Choosing a package tells `onPackage`; the price is the one resolved for the package and `studentId` (B3d)."

`SubscriptionForm.tsx`: import `useQueryClient` from `@tanstack/react-query` and `packagePriceKey`, `usePackagePrice` from `@/features/catalogue`; then

```tsx
	const qc = useQueryClient();
	// B3d (R2): the price shown and sent is the student's country's.
	const price = usePackagePrice(watch("package"), watch("student"));
```

In `onSubmit`'s body: `price_minor: toMinor(values.price, price.data?.currency ?? pkg?.currency ?? "USD"),` followed by `currency: price.data?.currency,`. In the `catch`, after `applyServerErrors`:

```tsx
			if (parsed.code === "catalogue.price_currency_changed") {
				// Plan P8: the price moved under the form; read it again.
				await qc.invalidateQueries({ queryKey: packagePriceKey });
			}
```

Pass `studentId={watch("student")}` to `<TermFields …>`, and give the submit button `disabled={price.isPending || price.isError}`. (B2e's `trial` prop, when present after a rebase, keeps working: its `student` default flows through `watch("student")`.)

`RenewDialog.tsx` (moves to `defaultValues` + `useFillOnOpen`, plan P9): import `useCallback`, `useMemo` from `react`, `useQueryClient` from `@tanstack/react-query`, `packagePriceKey`, `usePackagePrice` from `@/features/catalogue`, `useFillOnOpen` from `@/features/finance/shared`, `KeptPrice` from `./TermFields`. In `defaults`, replace the price comment with `// The amount paid last time; TermFields resets it to the resolved price when the resolved currency differs (P4-10, B3d).` Then:

```tsx
	const qc = useQueryClient();
	const methods = useForm<RenewFormValues>({
		resolver: zodResolver(renewFormSchema),
		defaultValues: defaults(sub),
	});
	const {
		handleSubmit,
		reset,
		setError,
		setFocus,
		watch,
		formState: { errors, isSubmitting },
	} = methods;
	const initial = useCallback(() => defaults(sub), [sub]);
	useFillOnOpen({ open, ready: true, reset, setFocus, initial, first: "course" });
	// B3d (R2): the price for the student's country, asked only while open.
	const price = usePackagePrice(open ? watch("package") : undefined, sub.student.id);
	const keep = useMemo<KeptPrice | undefined>(
		() =>
			sub.price_minor === undefined || !sub.currency
				? undefined
				: { price_minor: sub.price_minor, currency: sub.currency },
		[sub.price_minor, sub.currency],
	);
	const renew = useSchedulingMutation((values: RenewFormValues) =>
		schedulingApi.renew(sub.id, {
			course: Number(values.course),
			teacher: Number(values.teacher),
			package: Number(values.package),
			starts_on: values.starts_on,
			price_minor: toMinor(
				values.price,
				price.data?.currency ?? packageById(values.package)?.currency ?? sub.currency ?? "USD",
			),
			currency: price.data?.currency,
		}),
	);
```

(The `renew` mutation is declared after `price`, which it reads.) In `onSubmit`'s `catch`, add the same `catalogue.price_currency_changed` refetch as the form. Pass `studentId={sub.student.id}` and `keep={keep}` to `<TermFields …>`, and `disabled={price.isPending || price.isError}` to the `SubmitButton`.

- [ ] **Step 4: Run, check, commit**

Run: `$DASH pnpm exec biome check --write src e2e`
Run: `$DASH pnpm vitest run src/features/scheduling src/features/catalogue src/locales`
Run: `just test-frontend && just lint-frontend`
Expected: PASS (every other scheduling test file unchanged).

```bash
git -C dashboard add src/features/scheduling src/locales
git -C dashboard commit -m "feat(scheduling): subscription forms prefill and send the country price (B3d, R2 hook)

Delegated by B2 under a ledger claim (ledger R2, D23). TermFields reads
usePackagePrice for the student; the form and the renew dialog send the
currency they converted with; the renew dialog fills on open.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Release the claims**

```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/b3
for target in \
  backend/etqan/scheduling/services/subscriptions.py \
  backend/etqan/scheduling/api/serializers.py \
  backend/etqan/scheduling/tests/test_country_pricing.py \
  dashboard/src/features/scheduling/TermFields.tsx \
  dashboard/src/features/scheduling/SubscriptionForm.tsx \
  dashboard/src/features/scheduling/RenewDialog.tsx \
  dashboard/src/features/scheduling/schemas.ts \
  dashboard/src/features/scheduling/TermFields.test.tsx \
  dashboard/src/features/scheduling/SubscriptionForm.test.tsx \
  dashboard/src/features/scheduling/SubscriptionActions.test.tsx
do
  python3 scripts/orchestration/ledger.py release B3 "$target"
done
python3 scripts/orchestration/ledger.py show | sed -n '/## Claims and requests/,/## Trunk heads/p'
```

Expected: one `release <target>` per file; no B3 claim left in the table. (A review fix to these files later in the slice re-claims the file first and releases it after.)

---

### Task 11: The e2e journey

**Files:**
- Create: `dashboard/e2e/b3-country-prices.spec.ts`

**Interfaces:**
- Consumes: the whole slice through Caddy, including the hook (spec D-6: written only once Tasks 9–10 are in); the demo seed (Task 5); `manage("set_features", …)`; `login`, `DEMO_URL`, `DEMO_ADMIN`, `expectLoggedIn`, `invoiceHeader` from `e2e/fixtures.ts`.

- [ ] **Step 1: Write the spec**

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, invoiceHeader, login } from "./fixtures";
import { manage } from "./manage";

const weekday = (day: string) =>
	new Intl.DateTimeFormat("en", { weekday: "short", timeZone: "UTC" }).format(
		new Date(`${day}T00:00:00Z`),
	);

// B3d spec §9: the admin subscribes Karim Saleh (seeded, SA) to "Monthly,
// 2 a week" (EGP 1500.00; SA → SAR 450.00): the form shows 450.00 SAR and
// the invoice is in SAR. A new SAR-only method for SA shows on the invoice
// with the seeded "Bank transfer"; with local payment off, nothing does.
test("a Saudi student is priced in SAR and their invoice lists the local methods", async ({
	page,
}) => {
	// A database seeded before B3d would not have the switch on.
	manage("set_features", "demo", "--on", "invoices", "country_pricing");
	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	const local = page.getByRole("checkbox", {
		name: "Show local payment methods on invoices",
	});

	// 0. Local payment on: an earlier run that failed midway may have left it off.
	await page.goto(`${DEMO_URL}/app/billing/local-methods`);
	await expect(local).toBeVisible();
	if (!(await local.isChecked())) {
		await local.click();
		await expect(local).toBeChecked();
	}

	// 1. The subscription: 450.00 SAR in the form, SAR on the invoice.
	await page.goto(`${DEMO_URL}/app/scheduling/subscriptions/new`);
	const startsOn = page.getByLabel(/^Starts/);
	await expect(startsOn).toHaveValue(/^\d{4}-\d{2}-\d{2}$/);
	const today = await startsOn.inputValue();
	await page.getByLabel("Find a student").fill("Karim");
	await page.getByLabel(/^Student/).selectOption({ label: "Karim Saleh" });
	await page.getByLabel(/^Course/).selectOption({ label: "Tajweed" });
	await page.getByLabel(/^Teacher/).selectOption({ label: "Ustadh Bilal" });
	await page.getByLabel(/^Package/).selectOption({ label: "Monthly, 2 a week" });
	await expect(page.getByLabel(/^Price \(SAR\)/)).toHaveValue("450.00");
	await page.getByLabel(weekday(today), { exact: true }).click();
	await page.getByLabel(/^Start time/).fill("12:00");
	await page.getByRole("button", { name: "Create subscription" }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/subscriptions\/\d+$/);

	const invoiceLink = page.getByRole("link", { name: /^INV-\d{6}$/ });
	await expect(invoiceLink).toHaveCount(1);
	const number = (await invoiceLink.textContent()) ?? "";
	await invoiceLink.click();
	await expect(page).toHaveURL(/\/app\/billing\/invoices\/\d+$/);
	const invoiceUrl = page.url();
	await expect(invoiceHeader(page, number)).toBeVisible();
	await expect(page.getByText("SAR 450.00").first()).toBeVisible();

	// 2. A SAR-only method for SA, next to the seeded Bank transfer.
	const wallet = `E2E Wallet ${Date.now()}`;
	await page.goto(`${DEMO_URL}/app/billing/local-methods`);
	await page.getByRole("button", { name: "Add method" }).click();
	const dialog = page.getByRole("dialog");
	await dialog.getByLabel(/^Country/).selectOption("SA");
	await dialog.getByLabel(/^Name/).fill(wallet);
	await dialog.getByLabel(/^Currency/).selectOption("SAR");
	await dialog
		.getByLabel(/^Instructions/)
		.fill("Send to 0500000000\nThen send us the receipt.");
	await dialog.getByRole("button", { name: "Save method" }).click();
	await expect(page.getByText("Method saved.")).toBeVisible();

	await page.goto(invoiceUrl);
	await expect(page.getByRole("heading", { name: "Pay locally" })).toBeVisible();
	await expect(page.getByRole("heading", { name: wallet })).toBeVisible();
	await expect(page.getByRole("heading", { name: "Bank transfer" })).toBeVisible();

	// 3. Local payment off: no "Pay locally" on the invoice.
	await page.goto(`${DEMO_URL}/app/billing/local-methods`);
	await local.click();
	await expect(local).not.toBeChecked();
	await page.goto(invoiceUrl);
	await expect(invoiceHeader(page, number)).toBeVisible();
	await expect(page.getByRole("heading", { name: "Pay locally" })).toHaveCount(0);

	// Back on, for the next run and the seeded state the other journeys see.
	await page.goto(`${DEMO_URL}/app/billing/local-methods`);
	await local.click();
	await expect(local).toBeChecked();
});
```

- [ ] **Step 2: Run it against this stream's fresh stack**

Run: `just e2e e2e/b3-country-prices.spec.ts` (stack up via `just dev-backend`; rebuild images first if dependencies changed, and use a fresh stack before trusting the result — both new migrations must have run through `migrate_schemas`).
Expected: PASS. Run it twice: the second run must pass too (step 0 and the closing step keep the switch on; each run adds its own method and subscription).

- [ ] **Step 3: Commit**

```bash
git -C dashboard add e2e/b3-country-prices.spec.ts
git -C dashboard commit -m "test(e2e): a Saudi student's SAR price and local payment methods (B3d)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Gates

**Files:** none new; fix what the gates find in the task that owns it (a fix to a claimed scheduling file re-claims it first and releases it after).

- [ ] **Step 1: Backend**

Run: `just test-backend`
Expected: PASS, total coverage ≥ 80 %. Check `etqan/catalogue/services.py`'s country-price section, `etqan/billing/services/local.py`, the new views and the hook lines are fully covered (`--cov-report=term-missing`).

- [ ] **Step 2: Lint and boundaries**

Run: `just lint` (ruff, biome, the colour check) and `just check-boundaries` (`lint-imports`).
Expected: PASS. No contract changes: catalogue already reaches `identity.services`, scheduling `catalogue.services`, billing `etqan.platform`. If a contract fails, do not weaken it: move the import behind a service.

- [ ] **Step 3: Dashboard**

Run: `set -a; . ./.env.stream; set +a; HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm test:coverage`
Run: `just test-frontend`
Expected: PASS; lines and statements ≥ 80, branches and functions ≥ 70.

- [ ] **Step 4: End to end**

Run: `just e2e` (the whole suite, on a fresh stack).
Expected: PASS, including `subscriptions.spec.ts`, `billing.spec.ts` and `journey.spec.ts` (their students have no country, so their prices are unchanged; the subscription form now waits for the resolved price before Create is enabled).

- [ ] **Step 5: Ledger, PRs and report**

- Confirm `python3 scripts/orchestration/ledger.py show` lists no B3 claim (Task 10 Step 5 released them) and record the R2 hook as built on B3d's branches if the conductor asks for a note (ledger D23/D25 already hold the decisions).
- In the PR descriptions note: migrations `catalogue.0002` and `billing.0008`; the feature `country_pricing` built (off by default); the resource `payment_method`; the invoice detail's new `local_methods`; the subscription create and renew bodies' optional `currency` and the 400 `catalogue.price_currency_changed` (the R2 hook, delegated by B2, built under ledger claims now released); B2f's group-bundle part of R2 left to B2f (plan P10).
- Open PRs as Plan 15 did (`gh pr create --repo Etqan-agency/etqan_tutor_backend`, `…_dashboard`, then meta with `--repo Etqan-agency/etqan_tutor`); bump submodule pointers in meta only after both merge, with explicit paths (never `git commit -a`, never `git submodule`).

---

## Self-review against the spec

- **D-1** (country prices in catalogue, any currency, unique per package and country): Task 1 model and services. **D-2** (`StudentProfile.country`, blank → package price): Task 1 resolver tests. **D-3** (one resolver, `source`, `country` echoed, switch off = today): Task 1, Task 2 route. **D-4** (hook: default price and currency, optional `currency`, 400 code, P4-10 vs resolved currency, every create path): Task 9 (API, renewals; B2e conversion goes through the same form and service, plan P10). **D-5** (group bundles): plan P10 — B2f is unmerged, so per R2 it is B2f's build; noted in the PRs. **D-6** (hook commits on B3d's branches, both halves in the merge pair, B3d not queued before): Tasks 9–10 under claims, Task 11 after them, gates. **D-7** (snapshot): Task 9 test. **D-8** (price route; forms prefill and send currency): Tasks 2, 6, 10. **D-9** (PUT replaces the list; duplicate copies in one transaction; delete cascades; office-only `HasCode`): Tasks 1–2. **D-10/D-11** (billing models; the setting; nav hidden while off; page reachable from `/billing` and the settings card): Tasks 3, 4, 7, 8. **D-12** (method currency): Task 3 `local_methods_for`. **D-13** (plain text, trimmed, CRLF, 1–4000, escaped, no links): Tasks 3 and 8. **D-14** (logo: PNG/JPEG/WEBP, no GIF, 1 MB, `LOGO_PATH`, on-commit removal): Tasks 3–4, plan P2. **D-15** (what the family sees; office too): Tasks 3, 4, 8. **D-16** (format-only codes; malformed country 404; method needs a country): Tasks 3–4. **D-17** (online payment unchanged): no change needed; `pay_options` untouched. **D-18** (`country_pricing` built in place, default off): Task 1. **D-19** (resource `payment_method`; package codes; `student.view_any` with `?student`; no `NotImpersonating`): Tasks 2–4. **D-20** (`ValidationError.code`): already on trunk, pinned in Task 9 (plan P1). **D-21** (en and ar): every locale block above, real Arabic.
- **§3 data, §4 behaviour, §5 API:** Tasks 1–4. **§6 dashboard:** Tasks 6–8 and 10 (card, `usePackagePrice`, page, settings card, invoice block, wiring: `FeatureCode`, `FEATURE_SCREENS`/`FEATURE_WORDS`, nav under the B3 marker, `BILLING_PAGES` after `/billing/exchange-rates`). **§7:** no new package, setting or env var; B3 markers; import contracts unchanged; the R2 text built in Tasks 9–10 (minus item 4). **§8 seeds:** Task 5. **§9 tests:** each backend and dashboard bullet maps to a test above; the e2e is Task 11.

**Spec gaps and contradictions found (spec not edited):**
1. D-20 / §7 say B3d builds `ValidationError`'s optional `code`; it is already on trunk (added by B9c, and the handler already emits it). The plan only pins it with tests (P1).
2. §9 names the e2e `dashboard/e2e/b3-countries.spec.ts`; this plan uses `e2e/b3-country-prices.spec.ts` as instructed (P14).
3. D-14's "module-level `LOGO_PATH = tenant_upload_path("payment-methods")`" cannot be serialised by migrations as is: the helper names the callable `payment-methods_path`, not an identifier. The plan renames it (P2).
4. D-5 and R2 item (4) (group bundles) depend on B2f, which is still at `spec`; R2's own text moves (4) into B2f's build, so it is not in this plan (P10).
5. D-6 says B3d builds the hook "only if B2 explicitly delegates"; the ledger shows R2 as `done` with no delegation note, while the orchestrator states B2 delegated it. The plan takes the delegation as given and claims the files (Task 9 Step 1).
6. §6 asks that the nav item hide while a *setting* (not a feature) is off; the nav filtered only by codes and features. The plan adds an optional `NavItem.setting` and an `AppShell` fetch (P5) — an additive shell change outside the phase markers, like ledger D27.
7. §4.1's PUT body is a bare list, but errors are keyed `rows.i.<field>`; the spec does not say where a list-level error goes (not a list, more than 250 rows). The plan uses `rows` (P6).
8. The spec does not mention DRF's multipart rule that a missing boolean reads as `false`; without P12 a method created from a multipart form without `is_active` would be inactive.
9. "Every existing scheduling test passes unchanged" holds for the backend; two dashboard scheduling tests must add a `catalogueApi.price` mock and `currency: "EGP"` to their expected bodies, since the forms now resolve the price and always send the currency (Task 10).
10. §8 adds a fourth demo student, so `test_seed_dev`'s demo student count changes from 3 to 4 (Task 5).
