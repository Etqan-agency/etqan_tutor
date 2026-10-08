# Integrations slice 2 — Metering and Etqan invoices — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Slice:** Integrations 2 (metering and Etqan invoices). Not a phase: built outside the B2–B11 streams (spec §7).
**Requires:** slice 1 merged (`docs/superpowers/plans/2026-10-07-plan-integrations-1-core.md`: `etqan.integrations`, the resolver, `Academy.etqan_defaults_suspended`, the `meter_email` seam). **Unblocks:** B5c, Zoom (B2) and AI (B10) metering through `etqan_billing.services.record_usage(...)`; the B3 Stripe Connect follow-up through `connect_fee()` and `record_collected_fee(...)`.

**Goal:** Use of Etqan's default accounts is metered and invoiced to each academy monthly. Email (the only provider built) records one unit per accepted message on Etqan's default; WhatsApp, Zoom and AI phases record through the same public service. On the 1st of each month the job drafts last month's invoice for every academy that used Etqan's defaults (quantity × price − allowance, per service and unit, in integer minor units); Etqan reviews drafts for 24 hours, then they are issued and emailed with their PDF to the academy's admins. Academy admins see this month's usage and their invoices under Settings → Etqan billing and a banner on every page once an invoice is 15 days unpaid; Etqan staff set prices, per-academy overrides, allowances and Connect fees, review/issue/mark paid/void invoices, add manual and credit lines, read usage per academy, and from 30 days unpaid may switch an academy's "suspend Etqan defaults".

**Architecture:**
- **Backend:** a new app `etqan.etqan_billing` (SHARED_APPS, public schema, label `etqan_billing`): `UsageEvent`, `Price`, `AcademyPricing`, `ConnectFee`, `CollectedFee`, `InvoiceSequence`, `EtqanInvoice`, `EtqanInvoiceLine`, every row keyed by its academy. `services/usage.py` records usage (`record_usage`, `record_collected_fee`), `services/pricing.py` prices it (`usage_lines`, `month_usage`, `current_prices`, `connect_fee`), `services/invoices.py` runs the invoice lifecycle (`build_month`, `create_draft`, `issue`, `issue_due`, `add_line`, `remove_line`, `mark_paid`, `void`, `is_overdue`, `may_suspend`). `pdf.py` renders the PDF (fpdf2, DejaVu Sans with Arabic shaping). `tasks.py` holds the beat jobs and the invoice email (sent from the public schema on Etqan's default, never metered). `etqan.integrations.services.email.meter_email` is filled in; `send_email_now` gains attachments and a fixed Message-ID; the Integrations card gains `default_prices`.
- **API (admins only):** `GET /api/v1/etqan-billing/usage/`, `GET /api/v1/etqan-billing/invoices/`, `GET /api/v1/etqan-billing/invoices/<id>/pdf/`.
- **Platform admin:** Price, AcademyPricing, ConnectFee, usage (read-only), collected fees (read-only), invoices (add a draft, issue, mark paid, void, read lines), invoice lines (add a manual or credit line, remove one), and the "suspend Etqan's defaults" checkbox on the Academy page.
- **Dashboard:** `src/features/etqanbilling/` (schemas, api, queries, format, `EtqanBillingPage`, `OverdueBanner`), the route `/settings/etqan-billing`, a Settings nav item, the banner in `AppShell`, the default's price on the Integrations cards, `src/locales/{en,ar}/etqanBilling.json`.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18, Celery + django-celery-beat, fpdf2 + uharfbuzz (new), React 19 + TanStack Router/Query, i18next.

**Spec:** `docs/superpowers/specs/2026-10-07-integrations-and-etqan-billing-design.md` — slice 2 of §7: §5 (UsageEvent, Price, AcademyPricing, EtqanInvoice/Line, monthly job, overdue, manual suspend), §6 Settings → Etqan billing and the platform admin's prices, overrides, allowances, Connect fee, invoices, usage and suspend switch, §8 invoice tests and the metering tests. Out of this slice: the WhatsApp, Zoom and AI providers and their metering calls (their phases, through `record_usage`); Stripe Connect onboarding and `application_fee` (B3 follow-up, through `connect_fee()` and `record_collected_fee`); tax/VAT and automatic charging (IN-8).

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), the meta repo (trunk `master`). `marketing/` and `infra/` are not touched.
- Work in the fresh worktree `/home/abdulkhalek/Projects/etqan_tutor-wt/integrations-2`, created from meta `master` after slice 1 merged, on branch `feat/integrations-2` in `backend/`, `dashboard/` and meta. Check first: `git -C backend branch --show-current` and `git -C dashboard branch --show-current` print `feat/integrations-2`, and `test -f backend/etqan/integrations/services/resolver.py && echo slice1` prints `slice1`.
- **Never run any `git submodule` subcommand.** Commit in the repo the change lives in (`git -C backend …`, `git -C dashboard …`); in meta commit only explicit paths, never `git commit -a` (it captures submodule pointers). Do not touch `/home/abdulkhalek/Projects/etqan_tutor` or any other worktree.
- Commits use Conventional Commits and end with the trailer `Co-Authored-By: <implementing model> <noreply@anthropic.com>`, where `<implementing model>` is the name of the model that runs the task (for example `Claude Opus 5.5 (1M context)`). Set it once per shell: `TRAILER="Co-Authored-By: <implementing model> <noreply@anthropic.com>"` with the real name filled in; every commit below passes `-m "$TRAILER"`.

**Tenancy**
- django-tenants: one schema per academy. Every `etqan_billing` model is SHARED_APPS (public schema only); each row names its academy with a foreign key to `settings.TENANT_MODEL`. Migrate with `migrate_schemas` (the stack's `migrate` already is); never assume one schema.
- Code never imports `etqan.tenants`: the current academy is `django.db.connection.tenant` (none in the public schema); the job loops `django_tenants.utils.get_tenant_model()` itself. A task that needs an academy's own data (its admins) enters it with `etqan.platform.tenancy.academy_context(schema_name)`.
- Any user-facing URL is built with `etqan.platform.frontend.app_url()` / `frontend_url()` (the invoice email's link).

**Shared lists.** This work is not a phase: never add lines under a `── phase Bn ──` marker. Every shared list gets its lines in the existing block whose comment reads `Integrations (spec 2026-10-07; not a phase)` (slice 1 created it directly above the list's `Parallel phases` lead-in), or at the end of a list that has no markers (`SHARED_APPS`, `CELERY_BEAT_SCHEDULE`, the route test table `ADMIN_ONLY`, `nav.test.ts`'s list next to slice 1's line). That covers `config/settings/base.py`, `config/api_router.py`, `pyproject.toml`, `src/features/shell/nav.ts`. `etqan/platform/tests/test_phase_sections.py` keeps passing because no marker moves. Test tables take additive edits only.

**Money and time.** Money is integer minor units plus a currency, always (`amount`, `total`, `unit_amount` are integers; a percent is integer basis points). Etqan bills in one currency, `settings.ETQAN_BILLING_CURRENCY`. Stored instants are UTC; a "month" is the UTC calendar month; `etqan_billing` reads time only from `etqan.etqan_billing.clock.now()` (timezone-aware UTC), so tests pin it.

**Secrets.** No secret is added in this slice. The invoice email never goes through an academy's own account (plan D14).

**API.** All routes under `/api/v1/`. Domain errors are `etqan.platform.exceptions` (400 `ValidationError` with `field` or `code`, 404 `NotFoundError`). A programming error in a call between apps (`record_usage` with an unknown unit) is a `ValueError`.

**Language.** en and ar only (ledger D11), real Arabic (brand names such as WhatsApp, Stripe, Zoom stay Latin). No Spanish file (ledger D22). The PDF and the invoice email are English (plan D15).

**Backend commands.** Run from the meta worktree, inside this worktree's own stack, which reuses slice 1's slot-5 ports (`stream-env.sh` only writes slots 1–4). If `.env.stream` or `backend/.env` is missing: stop slice 1's stack (`docker compose -p etqan-integrations down`, run anywhere), then
```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/integrations-2
cp ../integrations/.env.stream .env.stream
sed -i 's/^COMPOSE_PROJECT_NAME=.*/COMPOSE_PROJECT_NAME=etqan-integrations-2/' .env.stream
cp ../integrations/backend/.env backend/.env
just rebuild && just dev-backend
```
Check the ports are free first: `docker ps --format '{{.Names}} {{.Ports}}' | grep -E ':(8580|8500|5932|6879)->'` prints nothing. Load the stack in every shell:
```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/integrations-2
set -a && . ./.env.stream && set +a
DJ="docker compose -f docker-compose.local.yml exec -T django"
```
- Targeted tests: `$DJ pytest etqan/etqan_billing -q` (add `--create-db` once after a task adds a migration).
- Migrations: `$DJ python manage.py makemigrations <app_label>`. Never run `manage.py`, `migrate` or e2e any other way.
- Format and lint: `$DJ sh -c 'ruff check --fix . && ruff format .'`, `$DJ lint-imports`.
- After a requirements change (Task 5): `just rebuild && just dev-backend`.
- Whole suite: `just test-backend`.

**Dashboard commands.** From the meta worktree (with `.env.stream` loaded as above):
```bash
DASH="docker compose -f docker-compose.local.yml run --rm dashboard"
export HOST_UID=$(id -u) HOST_GID=$(id -g)
```
- One test file: `$DASH pnpm vitest run src/features/etqanbilling/<file>`.
- Full tests with coverage: `$DASH pnpm test:coverage`.
- Types: `just test-frontend` (`tsc --noEmit`). Lint: `just lint-frontend` (biome + `check-colors.mjs`: semantic tokens only, no hex, no Tailwind palette utilities).
- A new route file regenerates `src/routeTree.gen.ts` with `$DASH pnpm exec vite build` before `tsc`; never hand-edit it.
- Format: `$DASH pnpm exec biome check --write src`.

**Coverage and gates.** Backend coverage ≥ 80 % (`just test-backend`). Dashboard lines and statements ≥ 80, branches and functions ≥ 70 (`pnpm test:coverage`). Before the PRs: `just test`, `just lint`, and the full `just e2e` (every email now writes a usage row).

## Decisions (gaps the spec left, filled here)

**Owner review (2026-10-08):** confirmed D5 (price batches), D6 (USD), D9 (collected Connect fees shown, not added to the total); `ETQAN_BILLING_PAYMENT_INSTRUCTIONS` ships as a placeholder the owner fills before the first invoices go out.

Slice 1's D1–D17 stand; in particular D2 (the suspend flag is `Academy.etqan_defaults_suspended`, read by the resolver from `connection.tenant`) and D13 (`meter_email` is the one email metering seam). Slice 2 adds:

| # | Decision |
|---|---|
| D1 | **One shared app, `etqan.etqan_billing`** (label `etqan_billing`, SHARED_APPS). Usage, prices and invoices are Etqan's ledger across academies, so they live once in `public`, each row keyed by `academy` (FK to `settings.TENANT_MODEL`, `PROTECT`; academies are never deleted). A query in an academy reaches them through the `search_path`; every academy-facing read filters by `connection.tenant`. |
| D2 | **Import direction.** `etqan.integrations.services` (metering, card prices) → `etqan.etqan_billing.services`; `etqan_billing.services`, `.models` and `.clock` import only the platform. The invoice email lives in `etqan_billing.tasks`, which imports `integrations.services` and `identity.services`; services never queue it (the admin action and the hourly job do). No import cycle at the services layer; `lint-imports` enforces it (Task 1). |
| D3 | **`record_usage(*, source, service, unit, quantity, source_ref, occurred_at=None) -> UsageEvent | None`** takes the caller's `Resolved.source` and records only `"etqan"` (IN-5 in one place), and nothing in the public schema. A repeated `(academy, service, source_ref)` returns the first event and changes nothing (a replayed webhook never double-counts). A wrong call (unknown service/unit, quantity not a positive int, empty or > 255-char ref, naive time) is a `ValueError`. `occurred_at` defaults to now; providers pass their own confirmation time. |
| D4 | **Email metering.** One unit = one message the provider accepted (Django's `send()` count), whatever the number of recipients. `send_email_now` sets the Message-ID itself and passes it to `meter_email(resolved, *, accepted, message_id)` as `source_ref`. Etqan's own mail in the public schema (staff mail, the invoice email) has no academy and is never metered. |
| D5 | **Units and price batches are fixed in code** (`PER`): WhatsApp `conversation` per 1, email `email` per 1,000, video `minute` per 1, AI `input_token` and `output_token` per 1,000,000. `Price.amount` is minor units per batch; a line's charge is `(billable × amount + per // 2) // per` (half up, per line). |
| D6 | **One Etqan currency**: `settings.ETQAN_BILLING_CURRENCY` (env, default `USD`), stamped on each `Price`, invoice and charged line. Collected Connect fees keep their own currency. |
| D7 | **Academy terms.** `AcademyPricing` per academy + service + unit: an optional override `amount` (replaces Etqan's price for the whole month, whatever its `effective_from`) and a monthly `free_allowance` in units. The **Connect fee** is its own one-to-one model `ConnectFee` (`percent_bp` in basis points ≤ 10,000, `fixed_amount` minor units, `currency`); no row means Etqan set no fee. `connect_fee()` returns it for the current academy (the B3 follow-up's `application_fee`). |
| D8 | **Price changes mid-month.** A `Price` applies to usage on UTC dates on or after its `effective_from`. A month that crosses a change gets one usage line per price in effect; the allowance is used up once, in date order. Usage with no price at all is listed at 0 (Etqan sees it on the draft). |
| D9 | **Collected Connect fees** are recorded by the B3 follow-up through `record_collected_fee(*, amount, currency, source_ref, occurred_at=None)` (idempotent like D3). The invoice shows one read-only line per currency, "Stripe Connect platform fees collected (already paid)", **not counted in the total** (Stripe already took them). A month with only collected fees still gets an invoice (it is the academy's statement). |
| D10 | **Numbering.** `ETQ-YYYY-MM-NNNN`: `YYYY-MM` is the invoice's usage month, `NNNN` a per-month counter across academies (`InvoiceSequence` row locked `FOR UPDATE`), assigned when the draft is created. A voided invoice keeps its number; gaps are allowed (no tax numbering rules, IN-8). |
| D11 | **Lifecycle.** `draft` (editable until `draft_until` = created + 24 h) → `issued` (by the hourly job past `draft_until`, or earlier by Etqan) → `paid` (date, method ∈ bank transfer / cash / card / other, reference) or `void` (from draft or issued; never from paid). `due_at` = `issued_at` + 15 days; an invoice is **overdue** when issued, total > 0 and now ≥ `due_at`. The academy never sees drafts. |
| D12 | **Corrections.** Lines change only on drafts. Etqan adds `manual` lines (positive) and `credit` lines (entered positive, stored negative); a draft's total never goes below zero. Etqan may create a draft by hand for any month (admin "Add"), so a credit has an invoice to sit on even when the next month has no usage. |
| D13 | **The monthly job** (1st, 03:00 UTC) loops every academy except public, **including status-suspended ones** (last month's use is still owed), one transaction each; a failing academy is logged and skipped; an academy that already has a non-void invoice for the month is skipped (re-running is safe). It needs no schema switch: the ledger is public. |
| D14 | **The invoice email** is Etqan's mail: sent in the public schema through `integrations.services.send_email_now` (so on Etqan's default, never the academy's own SMTP, never metered), from `DEFAULT_FROM_EMAIL`, to the academy's active admins (`identity.services.active_admins()` inside the academy), with the PDF attached and a link to Settings → Etqan billing. SMTP errors retry (3, backoff). `emailed_at` records it. |
| D15 | **PDF**: fpdf2 with text shaping (uharfbuzz) and DejaVu Sans / Sans Bold committed in `etqan_billing/fonts/` (with their licence), so an Arabic academy name or line renders joined and right-to-left with no system font or apt package. Labels are English. Payment instructions come from `settings.ETQAN_BILLING_PAYMENT_INSTRUCTIONS` (env) and appear on the PDF and in the email. |
| D16 | **The suspend switch** is a checkbox on the platform admin's Academy change page. Turning it on is refused unless the academy has an issued invoice with total > 0 unpaid for ≥ 30 days since issue; turning it off is always allowed. The field's help text shows the oldest unpaid invoice's age. |
| D17 | **Academy API: admins only** (no staff code, like `academy/features/`): `usage/` (this UTC month, per service+unit: quantity, free, charge so far, days), `invoices/` (every invoice ever issued: issued, paid, void), `invoices/<id>/pdf/`. The overdue banner reads the same invoices list (no extra endpoint) and is shown to admins only. |
| D18 | **The Integrations card's default price** (slice 1 D16): `default_prices: [{unit, per, amount, currency, free}]`, today's price after the academy's override and with its allowance; empty for payments (the B3 follow-up shows the Connect fee) and for a unit with no price. |

## Review Focus

1. **One academy's ledger reaching another.** Usage, invoices and PDFs are public-schema rows; an academy-facing read that forgets the academy filter leaks every academy's bill. Tests: `test_another_academys_invoice_is_a_404` (Task 7), `test_the_academy_sees_only_its_issued_invoices` (Task 4), `test_this_months_usage_by_day` (other academy's use excluded, Task 3), `test_another_academys_terms_do_not_apply` (Task 3).
2. **Counting use that must not be charged, or counting it twice.** A replayed webhook, mail on the academy's own SMTP, Etqan's staff mail and Etqan's invoice email itself. Tests: `test_a_repeated_webhook_counts_once`, `test_use_on_the_academys_own_account_is_never_recorded` (Task 2), `test_email_on_the_academys_own_account_is_never_metered`, `test_etqan_staff_mail_in_the_public_schema_is_never_metered` (Task 2), `test_the_invoice_email_goes_out_on_etqans_default_and_is_never_metered` (Task 6).
3. **Month edges and price changes.** An event at 23:59 UTC on the 30th vs 00:00 on the 1st; a price that changes on the 16th; an allowance that must be used once across both prices; rounding to whole minor units. Tests: `test_the_month_is_the_utc_calendar_month`, `test_a_price_applies_from_its_effective_date_and_the_allowance_is_used_once`, `test_the_charge_rounds_half_up_to_a_whole_minor_unit` (Task 3).
4. **An issued invoice changing.** Adding or removing a line, re-issuing, the job rebuilding the month, an admin form posting a line to it. Tests: `test_an_issued_invoice_never_changes`, `test_running_the_job_twice_builds_nothing_new` (Task 4), `test_a_line_on_an_issued_invoice_is_refused` (Task 8).
5. **Overdue and suspension firing wrongly.** A zero-total, paid or void invoice shown as overdue; the suspend switch flipped before 30 days. Tests: `test_an_invoice_is_overdue_15_days_after_issue`, `test_a_zero_invoice_is_never_overdue` (Task 4), `test_suspending_before_30_days_is_refused`, `test_a_zero_invoice_never_allows_suspending` (Task 9), `"shows nothing without an overdue invoice or to anyone but an admin"` (Task 12).

## File structure

**Backend (`backend/`)**

| Path | Responsibility |
|---|---|
| `etqan/etqan_billing/__init__.py`, `apps.py`, `clock.py` | the shared app, its clock |
| `etqan/etqan_billing/models.py`, `migrations/0001_initial.py` (generated) | the ledger |
| `etqan/etqan_billing/services/__init__.py` | public API (other apps import only this) |
| `etqan/etqan_billing/services/usage.py` | `record_usage`, `record_collected_fee`, `UNITS`, `current_academy_id` |
| `etqan/etqan_billing/services/pricing.py` | `PER`, month helpers, `charge`, `usage_lines`, `month_usage`, `current_prices`, `connect_fee`, `money`, `price_text` |
| `etqan/etqan_billing/services/invoices.py` | drafts, the monthly build, issue, lines, paid, void, overdue, suspension |
| `etqan/etqan_billing/pdf.py`, `fonts/DejaVuSans.ttf`, `fonts/DejaVuSans-Bold.ttf`, `fonts/LICENSE` | the PDF |
| `etqan/etqan_billing/tasks.py` | beat jobs, the invoice email |
| `etqan/etqan_billing/api/{__init__,payloads,views,urls}.py` | the academy API |
| `etqan/etqan_billing/admin.py` | the platform admin |
| `etqan/etqan_billing/tests/{__init__,conftest}.py`, `test_models.py`, `test_usage.py`, `test_pricing.py`, `test_invoices.py`, `test_pdf.py`, `test_tasks.py`, `test_api.py`, `test_admin.py` | tests |
| `etqan/integrations/services/email.py`, `etqan/integrations/api/payloads.py`, `etqan/integrations/tests/test_email.py`, `etqan/integrations/tests/test_api.py` | metering filled in, attachments, card prices |
| `etqan/tenants/admin.py`, `etqan/tenants/tests/test_admin_suspend.py` | the suspend switch |
| `etqan/access/tests/test_routes.py` | admins-only routes |
| `config/settings/base.py`, `config/api_router.py`, `pyproject.toml`, `requirements/base.txt` | wiring, contracts, dependencies |

**Dashboard (`dashboard/`)**

| Path | Responsibility |
|---|---|
| `src/features/etqanbilling/schemas.ts`, `api.ts`, `queries.ts`, `format.ts`, `index.ts` | data layer, formatting |
| `src/features/etqanbilling/EtqanBillingPage.tsx`, `OverdueBanner.tsx` | the page, the banner |
| `src/routes/_authed/settings.etqan-billing.tsx` | the route |
| `src/features/shell/AppShell.tsx`, `AppShell.test.tsx`, `nav.ts`, `nav.test.ts`, `src/routes/permissions.test.ts` | wiring |
| `src/features/integrations/schemas.ts`, `IntegrationsPage.tsx`, `IntegrationsPage.test.tsx`, `src/test/integrations-fixtures.ts` | the card's price |
| `src/locales/{en,ar}/etqanBilling.json` | strings |
| `src/test/etqanbilling-fixtures.ts` | fixtures |

**Meta:** `CLAUDE.md`, `STATE.md`.

---

### Task 1: The `etqan_billing` app, its ledger, settings and import contracts

**Files:**
- Create: `backend/etqan/etqan_billing/__init__.py`, `apps.py`, `clock.py`, `models.py`, `migrations/__init__.py`, `migrations/0001_initial.py` (generated), `tests/__init__.py`, `tests/conftest.py`, `tests/test_models.py`
- Modify: `backend/config/settings/base.py`, `backend/pyproject.toml`

**Interfaces:**
- Consumes: django-tenants app routing; `settings.TENANT_MODEL` (`"tenants.Academy"`).
- Produces: `etqan.etqan_billing.clock.now() -> datetime`; models `Metered` (TextChoices `whatsapp, email, video, ai`), `Unit` (`conversation, email, minute, input_token, output_token`), `etqan_currency() -> str`, `UsageEvent(academy, service, unit, quantity, occurred_at, source_ref, recorded_at)`, `Price(service, unit, amount, currency, effective_from)`, `AcademyPricing(academy, service, unit, amount: int | None, free_allowance)`, `ConnectFee(academy 1-1, percent_bp, fixed_amount, currency)`, `CollectedFee(academy, amount, currency, occurred_at, source_ref, recorded_at)`, `InvoiceSequence(period unique, last_number)`, `EtqanInvoice(academy, number, period, status, currency, total, created_at, draft_until, issued_at, due_at, emailed_at, paid_on, paid_method, paid_reference, voided_at, void_reason)` with `EtqanInvoice.Status` (`draft, issued, paid, void`) and `EtqanInvoice.PaidMethod` (`bank_transfer, cash, card, other`), `EtqanInvoiceLine(invoice → related_name "lines", kind, service, unit, quantity, free_quantity, unit_amount, per, amount, currency, description, created_at)` with `EtqanInvoiceLine.Kind` (`usage, connect_fees, manual, credit`); settings `ETQAN_BILLING_CURRENCY`, `ETQAN_BILLING_PAYMENT_INSTRUCTIONS`; test helpers `moment(text)`, `at` fixture, `usage(academy, when, *, quantity, service, unit, ref)`.

- [ ] **Step 1: Write the failing test**

Create `backend/etqan/etqan_billing/__init__.py`:

```python
"""Etqan's metering of its default accounts and its monthly invoices to
academies (spec 2026-10-07 §5)."""
```

Create `backend/etqan/etqan_billing/tests/__init__.py` empty, and `backend/etqan/etqan_billing/tests/conftest.py`:

```python
"""Etqan billing fixtures: a pinned clock and ledger rows made directly."""

import itertools
from datetime import UTC
from datetime import datetime

import pytest

from etqan.etqan_billing import clock
from etqan.etqan_billing.models import UsageEvent

_refs = itertools.count(1)


def moment(text: str) -> datetime:
    """``"2026-09-10 12:00"`` as an aware UTC instant."""
    return datetime.fromisoformat(text).replace(tzinfo=UTC)


@pytest.fixture
def at(monkeypatch):
    """``at("2026-10-01 03:00")`` pins etqan_billing's clock and returns it."""

    def pin(text: str) -> datetime:
        pinned = moment(text)
        monkeypatch.setattr(clock, "now", lambda: pinned)
        return pinned

    return pin


def usage(  # noqa: PLR0913 -- one ledger row's parts
    academy,
    when: str = "2026-09-10 12:00",
    *,
    quantity: int = 1,
    service: str = "email",
    unit: str = "email",
    ref: str | None = None,
) -> UsageEvent:
    return UsageEvent.objects.create(
        academy=academy,
        service=service,
        unit=unit,
        quantity=quantity,
        occurred_at=moment(when),
        source_ref=ref or f"ref-{next(_refs)}",
    )
```

Create `backend/etqan/etqan_billing/tests/test_models.py`:

```python
"""Spec §5: Etqan's ledger lives once, in the public schema, every row
keyed by its academy (plan D1)."""

from datetime import date

import pytest
from django.db import IntegrityError
from django.db import connection
from django.db import transaction

from etqan.etqan_billing.models import EtqanInvoice
from etqan.etqan_billing.models import Metered
from etqan.etqan_billing.models import Price
from etqan.etqan_billing.models import Unit
from etqan.etqan_billing.tests.conftest import moment
from etqan.etqan_billing.tests.conftest import usage

pytestmark = pytest.mark.django_db
SEPT = date(2026, 9, 1)
TABLES = [
    "etqan_billing_usageevent",
    "etqan_billing_price",
    "etqan_billing_academypricing",
    "etqan_billing_connectfee",
    "etqan_billing_collectedfee",
    "etqan_billing_invoicesequence",
    "etqan_billing_etqaninvoice",
    "etqan_billing_etqaninvoiceline",
]


def _schemas_of(table: str) -> set[str]:
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT table_schema FROM information_schema.tables WHERE table_name = %s",
            [table],
        )
        return {row[0] for row in cursor.fetchall()}


@pytest.mark.parametrize("table", TABLES)
def test_the_ledger_is_in_the_public_schema_only(table):
    assert _schemas_of(table) == {"public"}


def test_the_metered_services_and_units_of_the_spec():
    assert Metered.values == ["whatsapp", "email", "video", "ai"]
    assert Unit.values == [
        "conversation",
        "email",
        "minute",
        "input_token",
        "output_token",
    ]


def test_a_source_ref_counts_once_per_academy_and_service(tenants):
    usage(tenants.main, ref="<m1@etqan>")
    usage(tenants.other, ref="<m1@etqan>")
    usage(tenants.main, service="whatsapp", unit="conversation", ref="<m1@etqan>")
    with pytest.raises(IntegrityError), transaction.atomic():
        usage(tenants.main, ref="<m1@etqan>")


def _invoice(academy, number: str, status: str = "draft") -> EtqanInvoice:
    return EtqanInvoice.objects.create(
        academy=academy,
        period=SEPT,
        number=number,
        status=status,
        draft_until=moment("2026-10-02 03:00"),
    )


def test_one_invoice_a_month_unless_voided(tenants):
    _invoice(tenants.main, "ETQ-2026-09-0001", status="void")
    _invoice(tenants.main, "ETQ-2026-09-0002")
    _invoice(tenants.other, "ETQ-2026-09-0003")
    with pytest.raises(IntegrityError), transaction.atomic():
        _invoice(tenants.main, "ETQ-2026-09-0004")


def test_prices_and_invoices_carry_etqans_one_currency(settings, tenants):
    settings.ETQAN_BILLING_CURRENCY = "EUR"
    price = Price.objects.create(
        service="email", unit="email", amount=100, effective_from=SEPT
    )
    invoice = _invoice(tenants.main, "ETQ-2026-09-0001")
    assert (price.currency, invoice.currency) == ("EUR", "EUR")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$DJ pytest etqan/etqan_billing/tests/test_models.py -q`
Expected: FAIL at collection with `ModuleNotFoundError: No module named 'etqan.etqan_billing.models'`.

- [ ] **Step 3: Write the app, the clock and the models**

`backend/etqan/etqan_billing/apps.py`:

```python
from django.apps import AppConfig


class EtqanBillingConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.etqan_billing"
    label = "etqan_billing"
    verbose_name = "Etqan billing"
```

`backend/etqan/etqan_billing/clock.py`:

```python
"""The only clock etqan_billing reads, so tests pin it by monkeypatching
`now`: when usage happened, when a draft may be issued, when an invoice is
due."""

from datetime import datetime

from django.utils import timezone


def now() -> datetime:
    """The current instant, timezone-aware UTC."""
    return timezone.now()
```

`backend/etqan/etqan_billing/models.py`:

```python
"""Etqan's metering and invoices (spec 2026-10-07 §5), in the public schema
(SHARED_APPS): one ledger for every academy, each row keyed by its academy
(plan D1). Money is integer minor units plus a currency; instants are UTC.
Business rules live in `etqan.etqan_billing.services`."""

from django.conf import settings
from django.core.validators import MaxValueValidator
from django.db import models
from django.db.models import Q


class Metered(models.TextChoices):
    """The services Etqan bills by use (spec §4; payments is not metered)."""

    WHATSAPP = "whatsapp", "WhatsApp"
    EMAIL = "email", "Email"
    VIDEO = "video", "Video meetings"
    AI = "ai", "AI"


class Unit(models.TextChoices):
    CONVERSATION = "conversation", "Conversation"
    EMAIL = "email", "Email"
    MINUTE = "minute", "Meeting minute"
    INPUT_TOKEN = "input_token", "AI input token"
    OUTPUT_TOKEN = "output_token", "AI output token"


def etqan_currency() -> str:
    """Plan D6: Etqan bills in one currency."""
    return settings.ETQAN_BILLING_CURRENCY


class UsageEvent(models.Model):
    """One provider-confirmed use of an Etqan default (plan D3)."""

    academy = models.ForeignKey(
        settings.TENANT_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    service = models.CharField(max_length=16, choices=Metered.choices)
    unit = models.CharField(max_length=16, choices=Unit.choices)
    quantity = models.PositiveBigIntegerField()
    occurred_at = models.DateTimeField()
    # The provider's own id for the event (a Message-ID, a WhatsApp
    # conversation id): a repeated webhook carries the same one.
    source_ref = models.CharField(max_length=255)
    recorded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-occurred_at", "-id"]
        constraints = [
            models.UniqueConstraint(
                fields=["academy", "service", "source_ref"],
                name="etqan_billing_usage_counted_once",
            )
        ]
        indexes = [
            models.Index(
                fields=["academy", "occurred_at"], name="etqan_billing_usage_month"
            )
        ]

    def __str__(self):
        return f"UsageEvent<{self.service}/{self.unit} x{self.quantity}>"


class Price(models.Model):
    """Etqan's price for one unit, per `services.PER` units (plan D5), from
    `effective_from` (a UTC date) until the next price (plan D8)."""

    service = models.CharField(max_length=16, choices=Metered.choices)
    unit = models.CharField(max_length=16, choices=Unit.choices)
    amount = models.PositiveIntegerField(help_text="Minor units per batch of units.")
    currency = models.CharField(max_length=3, default=etqan_currency, editable=False)
    effective_from = models.DateField()

    class Meta:
        ordering = ["service", "unit", "-effective_from"]
        constraints = [
            models.UniqueConstraint(
                fields=["service", "unit", "effective_from"],
                name="etqan_billing_one_price_a_day",
            )
        ]

    def __str__(self):
        return f"Price<{self.service}/{self.unit} from {self.effective_from}>"


class AcademyPricing(models.Model):
    """One academy's terms for one unit (plan D7): an override of Etqan's
    price and a monthly free allowance."""

    academy = models.ForeignKey(
        settings.TENANT_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    service = models.CharField(max_length=16, choices=Metered.choices)
    unit = models.CharField(max_length=16, choices=Unit.choices)
    amount = models.PositiveIntegerField(
        null=True,
        blank=True,
        help_text="Minor units per batch; blank uses Etqan's price.",
    )
    free_allowance = models.PositiveBigIntegerField(
        default=0, help_text="Units free each calendar month."
    )

    class Meta:
        verbose_name_plural = "academy pricing"
        constraints = [
            models.UniqueConstraint(
                fields=["academy", "service", "unit"],
                name="etqan_billing_one_term_a_unit",
            )
        ]

    def __str__(self):
        return f"AcademyPricing<{self.academy_id} {self.service}/{self.unit}>"


class ConnectFee(models.Model):
    """The academy's Stripe Connect platform fee (spec §5, plan D7), taken
    through `application_fee` by the B3 follow-up."""

    academy = models.OneToOneField(
        settings.TENANT_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    percent_bp = models.PositiveIntegerField(
        validators=[MaxValueValidator(10_000)],
        help_text="Basis points: 250 = 2.5 %.",
    )
    fixed_amount = models.PositiveIntegerField(
        default=0, help_text="Minor units per payment."
    )
    currency = models.CharField(max_length=3)

    def __str__(self):
        return f"ConnectFee<{self.academy_id} {self.percent_bp}bp>"


class CollectedFee(models.Model):
    """A Connect platform fee Stripe already collected (plan D9)."""

    academy = models.ForeignKey(
        settings.TENANT_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    amount = models.PositiveBigIntegerField()
    currency = models.CharField(max_length=3)
    occurred_at = models.DateTimeField()
    source_ref = models.CharField(max_length=255)
    recorded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-occurred_at", "-id"]
        constraints = [
            models.UniqueConstraint(
                fields=["academy", "source_ref"],
                name="etqan_billing_fee_counted_once",
            )
        ]

    def __str__(self):
        return f"CollectedFee<{self.academy_id} {self.amount} {self.currency}>"


class InvoiceSequence(models.Model):
    """The last number given in one invoice month (plan D10)."""

    period = models.DateField(unique=True)
    last_number = models.PositiveIntegerField(default=0)


class EtqanInvoice(models.Model):
    """One academy's invoice for one UTC calendar month (spec §5)."""

    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        ISSUED = "issued", "Issued"
        PAID = "paid", "Paid"
        VOID = "void", "Void"

    class PaidMethod(models.TextChoices):
        BANK_TRANSFER = "bank_transfer", "Bank transfer"
        CASH = "cash", "Cash"
        CARD = "card", "Card"
        OTHER = "other", "Other"

    academy = models.ForeignKey(
        settings.TENANT_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    number = models.CharField(max_length=20, unique=True)
    # The first day of the invoiced month.
    period = models.DateField()
    status = models.CharField(
        max_length=8, choices=Status.choices, default=Status.DRAFT
    )
    currency = models.CharField(max_length=3, default=etqan_currency)
    # Minor units: every line but the collected Connect fees (plan D9).
    total = models.BigIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    draft_until = models.DateTimeField()
    issued_at = models.DateTimeField(null=True, blank=True)
    due_at = models.DateTimeField(null=True, blank=True)
    emailed_at = models.DateTimeField(null=True, blank=True)
    paid_on = models.DateField(null=True, blank=True)
    paid_method = models.CharField(
        max_length=16, choices=PaidMethod.choices, blank=True, default=""
    )
    paid_reference = models.CharField(max_length=100, blank=True, default="")
    voided_at = models.DateTimeField(null=True, blank=True)
    void_reason = models.CharField(max_length=200, blank=True, default="")

    class Meta:
        ordering = ["-period", "number"]
        constraints = [
            models.UniqueConstraint(
                fields=["academy", "period"],
                condition=~Q(status="void"),
                name="etqan_billing_one_invoice_a_month",
            )
        ]

    def __str__(self):
        return self.number


class EtqanInvoiceLine(models.Model):
    class Kind(models.TextChoices):
        USAGE = "usage", "Usage"
        CONNECT_FEES = "connect_fees", "Connect fees collected"
        MANUAL = "manual", "Manual"
        CREDIT = "credit", "Credit"

    invoice = models.ForeignKey(
        EtqanInvoice, on_delete=models.CASCADE, related_name="lines"
    )
    kind = models.CharField(max_length=16, choices=Kind.choices)
    # Usage lines only (connect_fees says "payments").
    service = models.CharField(max_length=16, blank=True, default="")
    unit = models.CharField(max_length=16, blank=True, default="")
    quantity = models.PositiveBigIntegerField(default=0)
    free_quantity = models.PositiveBigIntegerField(default=0)
    unit_amount = models.PositiveIntegerField(default=0)
    per = models.PositiveIntegerField(default=1)
    # Signed minor units: a credit is negative.
    amount = models.BigIntegerField()
    currency = models.CharField(max_length=3)
    description = models.CharField(max_length=200)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["id"]

    def __str__(self):
        return f"{self.description} ({self.amount} {self.currency})"
```

Create `backend/etqan/etqan_billing/migrations/__init__.py` empty.

- [ ] **Step 4: Wire the settings**

In `backend/config/settings/base.py`, in `SHARED_APPS`, replace

```python
    # Integrations (spec 2026-10-07; not a phase): Etqan's default accounts.
    "etqan.integrations",
]
```

with

```python
    # Integrations (spec 2026-10-07; not a phase): Etqan's default accounts.
    "etqan.integrations",
    # Integrations slice 2: Etqan's metering and invoices to academies.
    "etqan.etqan_billing",
]
```

Directly after the `ETQAN_SECRETS_KEY = env("ETQAN_SECRETS_KEY", default="")` line add:

```python
# Integrations slice 2 (spec 2026-10-07 §5): Etqan bills its default
# accounts' use in one currency (plan D6); the payment instructions go on
# every invoice PDF and email (plan D15).
ETQAN_BILLING_CURRENCY = env("ETQAN_BILLING_CURRENCY", default="USD")
ETQAN_BILLING_PAYMENT_INSTRUCTIONS = env(
    "ETQAN_BILLING_PAYMENT_INSTRUCTIONS",
    default=(
        "Pay by bank transfer to the account Etqan gave you, quoting the "
        "invoice number, or by any method Etqan accepts. Etqan marks the "
        "invoice paid when the payment arrives."
    ),
)
```

- [ ] **Step 5: Write the import contracts**

In `backend/pyproject.toml`, in the `"platform imports no business modules"` contract, replace

```toml
    # Integrations (spec 2026-10-07; not a phase).
    "etqan.integrations",
```

with

```toml
    # Integrations (spec 2026-10-07; not a phase).
    "etqan.integrations",
    "etqan.etqan_billing",
```

Replace the head of slice 1's first integrations contract

```toml
[[tool.importlinter.contracts]]
name = "integrations imports only the platform"
type = "forbidden"
# IN-7: every service asks integrations; integrations asks nobody but the
# platform. The academy is read from the connection, never from tenants.
```

with

```toml
[[tool.importlinter.contracts]]
name = "integrations imports only the platform and etqan_billing's services"
type = "forbidden"
# IN-7: every service asks integrations; integrations asks nobody but the
# platform, and etqan_billing's services to meter (slice 2 plan D2). The
# academy is read from the connection, never from tenants.
```

Directly after slice 1's `"other apps reach integrations only through its services"` contract (its `allow_indirect_imports = true` line), add:

```toml
# Integrations slice 2 (spec 2026-10-07 §5; not a phase), plan D2.
[[tool.importlinter.contracts]]
name = "etqan_billing's core imports only the platform"
type = "forbidden"
source_modules = [
    "etqan.etqan_billing.services", "etqan.etqan_billing.models", "etqan.etqan_billing.clock",
]
forbidden_modules = [
    "etqan.identity", "etqan.integrations", "etqan.tenants",
    "etqan.etqan_billing.tasks", "etqan.etqan_billing.admin", "etqan.etqan_billing.api",
    "etqan.etqan_billing.pdf",
]

[[tool.importlinter.contracts]]
name = "etqan_billing reaches identity and integrations only through their services"
type = "forbidden"
source_modules = ["etqan.etqan_billing"]
forbidden_modules = [
    "etqan.tenants", "etqan.site", "etqan.academy", "etqan.catalogue", "etqan.scheduling",
    "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access", "etqan.finance",
    "etqan.gateways", "etqan.learning", "etqan.employment", "etqan.library",
    "etqan.registration", "etqan.systemstatus", "etqan.translations",
    "etqan.identity.models", "etqan.identity.api", "etqan.identity.adapter",
    "etqan.integrations.models", "etqan.integrations.accounts", "etqan.integrations.api",
    "etqan.integrations.providers", "etqan.integrations.tasks", "etqan.integrations.clock",
    "etqan.integrations.admin",
]
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "other apps reach etqan_billing only through its services"
type = "forbidden"
source_modules = [
    "etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants",
    "etqan.scheduling", "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access",
    "etqan.finance", "etqan.gateways", "etqan.learning", "etqan.employment", "etqan.library",
    "etqan.registration", "etqan.systemstatus", "etqan.translations", "etqan.integrations",
]
forbidden_modules = [
    "etqan.etqan_billing.models", "etqan.etqan_billing.api", "etqan.etqan_billing.tasks",
    "etqan.etqan_billing.admin", "etqan.etqan_billing.pdf", "etqan.etqan_billing.clock",
]
allow_indirect_imports = true
```

(Tasks 2 and 9 add an `ignore_imports` line to the last contract when a test first imports the ledger's models; `lint-imports` refuses an ignore that matches nothing.)

- [ ] **Step 6: Generate the migration and run the tests**

Run: `$DJ python manage.py makemigrations etqan_billing`
Expected: `Migrations for 'etqan_billing': etqan/etqan_billing/migrations/0001_initial.py` listing the eight models, the constraints and the index.

Run: `$DJ pytest etqan/etqan_billing/tests/test_models.py -q --create-db`
Expected: PASS (12 passed).

Run: `$DJ lint-imports`
Expected: every contract `KEPT`.

- [ ] **Step 7: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/etqan_billing config/settings/base.py pyproject.toml
git -C backend commit -m "feat(etqan_billing): the ledger app — usage, prices, terms, invoices" -m "$TRAILER"
```

---

### Task 2: Recording usage, collected fees and email metering

**Files:**
- Create: `backend/etqan/etqan_billing/services/__init__.py`, `backend/etqan/etqan_billing/services/usage.py`, `backend/etqan/etqan_billing/tests/test_usage.py`
- Modify: `backend/etqan/integrations/services/email.py`, `backend/etqan/integrations/tests/test_email.py`, `backend/pyproject.toml`

**Interfaces:**
- Consumes: Task 1's models and clock; slice 1's `Resolved` (`source` is `"academy"` or `"etqan"`), `send_email_now`.
- Produces: `etqan_billing.services.record_usage(*, source: str, service: str, unit: str, quantity: int, source_ref: str, occurred_at: datetime | None = None) -> UsageEvent | None`; `record_collected_fee(*, amount: int, currency: str, source_ref: str, occurred_at: datetime | None = None) -> CollectedFee | None`; `UNITS: dict[str, tuple[str, ...]]`; `ETQAN = "etqan"`; `current_academy_id() -> int | None`. `integrations.services.send_email_now(..., attachments: list[tuple[str, bytes, str]] | None = None)`; `meter_email(resolved, *, accepted: int, message_id: str) -> None`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/etqan_billing/tests/test_usage.py`:

```python
"""Spec §5: use of Etqan's defaults is recorded once per provider
confirmation, and only for source == "etqan" (IN-5, plan D3)."""

from datetime import datetime

import pytest
from django.db import connection

from etqan.etqan_billing import services
from etqan.etqan_billing.models import CollectedFee
from etqan.etqan_billing.models import UsageEvent
from etqan.etqan_billing.tests.conftest import moment

pytestmark = pytest.mark.django_db


def record(**overrides):
    return services.record_usage(
        **{
            "source": "etqan",
            "service": "whatsapp",
            "unit": "conversation",
            "quantity": 1,
            "source_ref": "wamid.1",
            **overrides,
        }
    )


def test_use_on_etqans_default_is_recorded_for_the_academy_on_the_connection(
    tenants, at
):
    pinned = at("2026-10-05 09:30")
    event = record()
    assert (
        event.academy_id,
        event.service,
        event.unit,
        event.quantity,
        event.occurred_at,
    ) == (tenants.main.pk, "whatsapp", "conversation", 1, pinned)


def test_a_repeated_webhook_counts_once():
    first = record()
    again = record(quantity=5)
    assert again.pk == first.pk
    assert list(UsageEvent.objects.values_list("quantity", flat=True)) == [1]


def test_the_same_ref_in_another_service_or_academy_is_its_own_use(tenants):
    record()
    record(service="ai", unit="input_token", quantity=1200)
    connection.set_tenant(tenants.other)
    record()
    assert UsageEvent.objects.count() == 3


def test_use_on_the_academys_own_account_is_never_recorded():
    assert record(source="academy") is None
    assert UsageEvent.objects.count() == 0


def test_the_public_schema_records_nothing():
    connection.set_schema_to_public()
    assert record() is None
    assert UsageEvent.objects.count() == 0


def test_the_providers_time_is_kept():
    event = record(occurred_at=moment("2026-09-30 23:59"))
    assert event.occurred_at == moment("2026-09-30 23:59")


@pytest.mark.parametrize(
    "overrides",
    [
        {"service": "payments", "unit": "conversation"},
        {"service": "email", "unit": "minute"},
        {"quantity": 0},
        {"quantity": -3},
        {"quantity": 1.5},
        {"quantity": True},
        {"source_ref": ""},
        {"source_ref": "x" * 256},
        {"occurred_at": datetime(2026, 9, 1, 12)},  # noqa: DTZ001 -- naive on purpose
    ],
)
def test_a_wrong_call_is_a_programming_error(overrides):
    with pytest.raises(ValueError):  # noqa: PT011 -- each case has its own message
        record(**overrides)


def test_a_collected_connect_fee_is_recorded_once(tenants):
    fee = services.record_collected_fee(amount=290, currency="usd", source_ref="fee_1")
    again = services.record_collected_fee(
        amount=290, currency="USD", source_ref="fee_1"
    )
    assert again.pk == fee.pk
    assert (fee.academy_id, fee.amount, fee.currency) == (tenants.main.pk, 290, "USD")


@pytest.mark.parametrize(
    "overrides",
    [{"amount": 0}, {"amount": 2.5}, {"currency": "US"}, {"source_ref": ""}],
)
def test_a_wrong_fee_is_a_programming_error(overrides):
    with pytest.raises(ValueError):  # noqa: PT011
        services.record_collected_fee(
            **{"amount": 290, "currency": "USD", "source_ref": "fee_1", **overrides}
        )


def test_the_public_schema_records_no_fee():
    connection.set_schema_to_public()
    assert (
        services.record_collected_fee(amount=290, currency="USD", source_ref="fee_1")
        is None
    )
    assert CollectedFee.objects.count() == 0
```

In `backend/etqan/integrations/tests/test_email.py`, add the import

```python
from etqan.etqan_billing.models import UsageEvent
```

replace `test_the_meter_is_called_once_with_how_the_email_resolved` with

```python
def test_the_meter_is_called_once_with_how_the_email_resolved(monkeypatch):
    seen = []
    monkeypatch.setattr(
        email_service,
        "meter_email",
        lambda resolved, *, accepted, message_id: seen.append(
            (resolved.source, accepted, message_id)
        ),
    )
    services.send_email_now(**BRANDED, to=["yusuf@family.test"])
    (message,) = mail.outbox
    assert seen == [("etqan", 1, message.extra_headers["Message-ID"])]
```

and add at the end:

```python
def test_each_email_on_etqans_default_is_one_email_of_usage(tenants):
    services.send_email_now(**BRANDED, to=["yusuf@family.test", "maryam@family.test"])
    (message,) = mail.outbox
    (event,) = UsageEvent.objects.all()
    assert (event.academy_id, event.service, event.unit, event.quantity) == (
        tenants.main.pk,
        "email",
        "email",
        1,
    )
    assert event.source_ref == message.extra_headers["Message-ID"]


def test_email_on_the_academys_own_account_is_never_metered(own_email, monkeypatch):
    monkeypatch.setattr(email_provider, "SMTP_BACKEND", LOCMEM)
    services.send_email_now(**BRANDED, to=["yusuf@family.test"])
    assert len(mail.outbox) == 1
    assert UsageEvent.objects.count() == 0


def test_etqan_staff_mail_in_the_public_schema_is_never_metered():
    connection.set_schema_to_public()
    services.send_email_now(**{**BRANDED, "reply_to": []}, to=["ops@etqan.test"])
    assert len(mail.outbox) == 1
    assert UsageEvent.objects.count() == 0


def test_an_attachment_goes_with_the_message():
    pdf = ("ETQ-2026-09-0001.pdf", b"%PDF-1.4", "application/pdf")
    services.send_email_now(**BRANDED, to=["yusuf@family.test"], attachments=[pdf])
    assert [tuple(a) for a in mail.outbox[0].attachments] == [pdf]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/etqan_billing/tests/test_usage.py etqan/integrations/tests/test_email.py -q`
Expected: FAIL — `ImportError: cannot import name 'services' from 'etqan.etqan_billing'` and, in `test_email.py`, `TypeError: send_email_now() got an unexpected keyword argument 'attachments'` / `<lambda>() missing 1 required keyword-only argument: 'message_id'`.

- [ ] **Step 3: Write the usage services**

`backend/etqan/etqan_billing/services/usage.py`:

```python
"""Spec §5: use of Etqan's default accounts, recorded once per provider
confirmation (plan D3), and the Connect fees Stripe collected (plan D9).
Only use on Etqan's defaults is ever recorded (IN-5): the caller passes
how its account resolved, and an academy's own account is never charged."""

from datetime import datetime

from django.db import connection
from django.utils import timezone
from django_tenants.utils import get_public_schema_name

from etqan.etqan_billing import clock
from etqan.etqan_billing.models import CollectedFee
from etqan.etqan_billing.models import UsageEvent

ETQAN = "etqan"
REF_LENGTH = 255
# Spec §4's metered unit per service (payments is not metered).
UNITS: dict[str, tuple[str, ...]] = {
    "whatsapp": ("conversation",),
    "email": ("email",),
    "video": ("minute",),
    "ai": ("input_token", "output_token"),
}


def current_academy_id() -> int | None:
    """The academy on the connection; None in the public schema."""
    if connection.schema_name == get_public_schema_name():
        return None
    return connection.tenant.pk


def _whole(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def _when(occurred_at: datetime | None) -> datetime:
    when = occurred_at or clock.now()
    if timezone.is_naive(when):
        raise ValueError("occurred_at must be timezone-aware.")
    return when


def _ref(source_ref: str) -> str:
    if not source_ref or len(source_ref) > REF_LENGTH:
        raise ValueError(f"source_ref must be 1 to {REF_LENGTH} characters.")
    return source_ref


def record_usage(  # noqa: PLR0913 -- one confirmed use's parts
    *,
    source: str,
    service: str,
    unit: str,
    quantity: int,
    source_ref: str,
    occurred_at: datetime | None = None,
) -> UsageEvent | None:
    """Record one provider-confirmed use in the current academy (plan D3).

    ``source`` is the caller's ``Resolved.source``: only ``"etqan"`` is
    recorded. ``source_ref`` is the provider's id for the event; a repeat
    returns the first event unchanged. Returns None when nothing is recorded
    (the academy's own account, or the public schema)."""
    if unit not in UNITS.get(service, ()):
        raise ValueError(f"Not a metered unit: {service}/{unit}.")
    if not _whole(quantity):
        raise ValueError("quantity must be a positive whole number.")
    ref = _ref(source_ref)
    when = _when(occurred_at)
    academy_id = current_academy_id()
    if source != ETQAN or academy_id is None:
        return None
    event, _ = UsageEvent.objects.get_or_create(
        academy_id=academy_id,
        service=service,
        source_ref=ref,
        defaults={"unit": unit, "quantity": quantity, "occurred_at": when},
    )
    return event


def record_collected_fee(
    *,
    amount: int,
    currency: str,
    source_ref: str,
    occurred_at: datetime | None = None,
) -> CollectedFee | None:
    """The B3 follow-up's seam (plan D9): a Connect platform fee Stripe
    collected for Etqan from the current academy's payment, in minor units
    of ``currency``. Idempotent on ``source_ref`` (the Stripe fee id)."""
    if not _whole(amount):
        raise ValueError("amount must be a positive whole number of minor units.")
    code = (currency or "").upper()
    if len(code) != 3 or not code.isalpha():  # ISO 4217
        raise ValueError("currency must be an ISO 4217 code.")
    ref = _ref(source_ref)
    when = _when(occurred_at)
    academy_id = current_academy_id()
    if academy_id is None:
        return None
    fee, _ = CollectedFee.objects.get_or_create(
        academy_id=academy_id,
        source_ref=ref,
        defaults={"amount": amount, "currency": code, "occurred_at": when},
    )
    return fee
```

`backend/etqan/etqan_billing/services/__init__.py`:

```python
"""Public API of etqan_billing. Other apps import only this package."""

from etqan.etqan_billing.services.usage import ETQAN
from etqan.etqan_billing.services.usage import UNITS
from etqan.etqan_billing.services.usage import current_academy_id
from etqan.etqan_billing.services.usage import record_collected_fee
from etqan.etqan_billing.services.usage import record_usage

__all__ = [
    "ETQAN",
    "UNITS",
    "current_academy_id",
    "record_collected_fee",
    "record_usage",
]
```

- [ ] **Step 4: Fill the email metering seam**

In `backend/etqan/integrations/services/email.py`, replace the imports block

```python
from email.utils import parseaddr
from email.utils import quote as email_quote

from django.core.mail import EmailMultiAlternatives
from django.db import connection
```

with

```python
from email.utils import make_msgid
from email.utils import parseaddr
from email.utils import quote as email_quote

from django.core.mail import EmailMultiAlternatives
from django.core.mail.utils import DNS_NAME
from django.db import connection

from etqan.etqan_billing import services as billing
```

Replace the whole `meter_email` function with

```python
def meter_email(resolved: Resolved, *, accepted: int, message_id: str) -> None:
    """The one place email is metered (spec §5; slice 1 D13, slice 2 D4):
    each accepted message on Etqan's default is one ``email`` unit, counted
    once by its Message-ID. Email on the academy's own account is never
    charged (IN-5), and Etqan's own mail in the public schema has no
    academy: `record_usage` records neither."""
    if accepted:
        billing.record_usage(
            source=resolved.source,
            service=EMAIL,
            unit=EMAIL,
            quantity=accepted,
            source_ref=message_id,
        )
```

Replace the whole `send_email_now` function with

```python
def send_email_now(  # noqa: PLR0913 -- the branded message's parts
    *,
    subject: str,
    body: str,
    from_email: str,
    to: list[str],
    alternatives: list | None = None,
    reply_to: list[str] | None = None,
    attachments: list[tuple[str, bytes, str]] | None = None,
) -> Resolved:
    """Send one already-branded email now through the account the current
    academy resolves to. ``attachments`` are ``(filename, content,
    mimetype)``. Raises NotSetUpError when no account resolves; SMTP errors
    (``OSError``) propagate for the caller to retry."""
    resolved = resolve(EMAIL)
    if resolved is None:
        raise NotSetUpError("Email is not set up for this academy.")
    # Set here, not by Django, so the meter counts this message by it.
    message_id = make_msgid(domain=DNS_NAME)
    message = EmailMultiAlternatives(
        subject=subject,
        body=body,
        from_email=_sender(resolved, from_email),
        to=to,
        # Spec §4: the default's replies go to the academy; an own account's
        # From already is the academy's.
        reply_to=[] if resolved.source == ACADEMY else list(reply_to or []),
        attachments=list(attachments or []),
        headers={"Message-ID": message_id},
        connection=mail_connection(resolved.config, resolved.secrets()),
    )
    for content, mimetype in alternatives or []:
        message.attach_alternative(content, mimetype)
    accepted = message.send()
    meter_email(resolved, accepted=accepted, message_id=message_id)
    return resolved
```

In `backend/pyproject.toml`, in the `"other apps reach etqan_billing only through its services"` contract (Task 1), add after its `allow_indirect_imports = true` line:

```toml
ignore_imports = ["etqan.integrations.tests.** -> etqan.etqan_billing.**"]
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `$DJ pytest etqan/etqan_billing etqan/integrations etqan/identity etqan/notifications -q`
Expected: PASS (every email the suites send now also writes a usage row; nothing else changes).

Run: `$DJ lint-imports`
Expected: every contract `KEPT`.

- [ ] **Step 6: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/etqan_billing etqan/integrations pyproject.toml
git -C backend commit -m "feat(etqan_billing): record usage once per confirmation; meter email on Etqan's default" -m "$TRAILER"
```

---

### Task 3: Prices, academy terms and the month's usage lines

**Files:**
- Create: `backend/etqan/etqan_billing/services/pricing.py`, `backend/etqan/etqan_billing/tests/test_pricing.py`
- Modify: `backend/etqan/etqan_billing/services/__init__.py`

**Interfaces:**
- Consumes: Task 1's `Price`, `AcademyPricing`, `ConnectFee`, `CollectedFee`, `UsageEvent`, `etqan_currency`, `clock`; Task 2's `UNITS`, `current_academy_id`.
- Produces: `PER: dict[str, int]`; `LINE_TITLES: dict[str, str]`; `month_bounds(period: date) -> tuple[datetime, datetime]`; `next_month(period) -> date`; `previous_month(period) -> date`; `this_month() -> date`; `charge(billable: int, unit_amount: int, per: int) -> int`; `Terms(override: int | None, free: int)`; `terms_for(academy_id, service, unit) -> Terms`; `UsageLine(service, unit, quantity, free_quantity, unit_amount, per, amount)` (frozen dataclass); `daily_usage(academy_id, start, end) -> list[dict]` (keys `service, unit, day, total`); `usage_lines(academy_id: int, period: date) -> list[UsageLine]`; `collected_fees(academy_id, period) -> list[tuple[str, int]]`; `has_activity(academy_id, period) -> bool`; `month_usage() -> dict` (`{"month": date, "currency", "usage": [{"service", "unit", "quantity", "free", "amount", "days": [{"date": date, "quantity"}]}]}`); `current_prices(service: str) -> list[dict]` (`{"unit", "per", "amount", "currency", "free"}`); `ConnectFeeTerms(percent_bp, fixed_amount, currency)`; `connect_fee() -> ConnectFeeTerms | None`; `money(amount: int, currency: str) -> str`; `price_text(amount, currency, unit) -> str`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/etqan_billing/tests/test_pricing.py`:

```python
"""Spec §5 and §8: quantity × price − allowance per service and unit, in
whole minor units; an academy's override; a price's effective date (plan
D5, D7, D8)."""

from datetime import date

import pytest
from django.db import connection

from etqan.etqan_billing import services
from etqan.etqan_billing.models import AcademyPricing
from etqan.etqan_billing.models import ConnectFee
from etqan.etqan_billing.models import Price
from etqan.etqan_billing.services import UsageLine
from etqan.etqan_billing.tests.conftest import usage

pytestmark = pytest.mark.django_db
SEPT = date(2026, 9, 1)


def price(amount: int, since: str = "2026-01-01", *, service="email", unit="email"):
    return Price.objects.create(
        service=service,
        unit=unit,
        amount=amount,
        effective_from=date.fromisoformat(since),
    )


def terms(academy, *, amount=None, free=0, service="email", unit="email"):
    return AcademyPricing.objects.create(
        academy=academy, service=service, unit=unit, amount=amount, free_allowance=free
    )


def lines(academy, period=SEPT):
    return services.usage_lines(academy.pk, period)


def test_quantity_less_the_allowance_times_the_price(tenants):
    price(100)  # 1.00 per 1,000 emails
    terms(tenants.main, free=1000)
    usage(tenants.main, quantity=2500)
    assert lines(tenants.main) == [
        UsageLine("email", "email", 2500, 1000, 100, 1000, 150)
    ]


def test_an_academy_override_replaces_etqans_price(tenants):
    price(100)
    terms(tenants.main, amount=80, free=1000)
    usage(tenants.main, quantity=2500)
    (line,) = lines(tenants.main)
    assert (line.unit_amount, line.amount) == (80, 120)


def test_another_academys_terms_do_not_apply(tenants):
    price(100)
    terms(tenants.other, amount=1, free=10_000)
    usage(tenants.main, quantity=2000)
    (line,) = lines(tenants.main)
    assert (line.free_quantity, line.unit_amount, line.amount) == (0, 100, 200)


def test_a_price_applies_from_its_effective_date_and_the_allowance_is_used_once(
    tenants,
):
    price(100, "2026-01-01")
    price(200, "2026-09-16")
    terms(tenants.main, free=500)
    usage(tenants.main, "2026-09-10 08:00", quantity=1000)
    usage(tenants.main, "2026-09-20 08:00", quantity=1000)
    assert lines(tenants.main) == [
        UsageLine("email", "email", 1000, 500, 100, 1000, 50),
        UsageLine("email", "email", 1000, 0, 200, 1000, 200),
    ]


def test_a_price_from_after_the_month_does_not_apply(tenants):
    price(100, "2026-01-01")
    price(999, "2026-10-01")
    usage(tenants.main, "2026-09-30 23:59", quantity=1000)
    (line,) = lines(tenants.main)
    assert (line.unit_amount, line.amount) == (100, 100)


def test_the_charge_rounds_half_up_to_a_whole_minor_unit():
    assert [services.charge(n, 100, 1000) for n in (1, 4, 5, 15, 2500)] == [
        0,
        0,
        1,
        2,
        250,
    ]
    assert services.charge(3, 7, 1) == 21


def test_the_month_is_the_utc_calendar_month(tenants):
    price(1, service="whatsapp", unit="conversation")
    for when in (
        "2026-08-31 23:59",
        "2026-09-01 00:00",
        "2026-09-30 23:59",
        "2026-10-01 00:00",
    ):
        usage(tenants.main, when, service="whatsapp", unit="conversation")
    (line,) = lines(tenants.main)
    assert (line.quantity, line.amount) == (2, 2)


def test_use_with_no_price_is_listed_at_zero(tenants):
    usage(tenants.main, quantity=40, service="video", unit="minute")
    assert lines(tenants.main) == [UsageLine("video", "minute", 40, 0, 0, 1, 0)]


def test_each_unit_is_its_own_line(tenants):
    price(300, service="ai", unit="input_token")
    price(1500, service="ai", unit="output_token")
    usage(tenants.main, quantity=2_000_000, service="ai", unit="input_token")
    usage(tenants.main, quantity=500_000, service="ai", unit="output_token")
    assert [(line.unit, line.amount) for line in lines(tenants.main)] == [
        ("input_token", 600),
        ("output_token", 750),
    ]


def test_an_allowance_larger_than_the_use_charges_nothing(tenants):
    price(100)
    terms(tenants.main, free=5000)
    usage(tenants.main, quantity=2000)
    (line,) = lines(tenants.main)
    assert (line.free_quantity, line.amount) == (2000, 0)


def test_this_months_usage_by_day(tenants, at):
    price(100)
    at("2026-10-15 10:00")
    usage(tenants.main, "2026-10-01 08:00", quantity=1200)
    usage(tenants.main, "2026-10-03 09:00", quantity=1300)
    usage(tenants.main, "2026-09-30 23:00", quantity=999)
    usage(tenants.other, "2026-10-02 10:00", quantity=7)
    assert services.month_usage() == {
        "month": date(2026, 10, 1),
        "currency": "USD",
        "usage": [
            {
                "service": "email",
                "unit": "email",
                "quantity": 2500,
                "free": 0,
                "amount": 250,
                "days": [
                    {"date": date(2026, 10, 1), "quantity": 1200},
                    {"date": date(2026, 10, 3), "quantity": 1300},
                ],
            }
        ],
    }


def test_the_card_shows_todays_price_after_the_academys_terms(tenants, at):
    at("2026-09-20 10:00")
    price(100, "2026-01-01")
    price(200, "2026-10-01")
    terms(tenants.main, free=1000)
    assert services.current_prices("email") == [
        {"unit": "email", "per": 1000, "amount": 100, "currency": "USD", "free": 1000}
    ]
    assert services.current_prices("payments") == []
    assert services.current_prices("video") == []


def test_an_override_shows_even_without_etqans_price(tenants):
    terms(tenants.main, amount=5, service="video", unit="minute")
    assert services.current_prices("video") == [
        {"unit": "minute", "per": 1, "amount": 5, "currency": "USD", "free": 0}
    ]


def test_the_connect_fee_is_the_academys_own(tenants):
    assert services.connect_fee() is None
    ConnectFee.objects.create(
        academy=tenants.main, percent_bp=250, fixed_amount=30, currency="USD"
    )
    assert services.connect_fee() == services.ConnectFeeTerms(250, 30, "USD")
    connection.set_tenant(tenants.other)
    assert services.connect_fee() is None


def test_money_and_price_text():
    assert services.money(150, "USD") == "1.50 USD"
    assert services.money(5, "KWD") == "0.005 KWD"
    assert services.price_text(100, "USD", "email") == "1.00 USD per 1,000 emails"
    assert services.price_text(5, "USD", "conversation") == "0.05 USD per conversation"
    assert (
        services.price_text(300, "USD", "input_token")
        == "3.00 USD per 1,000,000 input tokens"
    )
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/etqan_billing/tests/test_pricing.py -q`
Expected: FAIL at collection with `ImportError: cannot import name 'UsageLine' from 'etqan.etqan_billing.services'`.

- [ ] **Step 3: Write the pricing services**

`backend/etqan/etqan_billing/services/pricing.py`:

```python
"""Spec §5: what Etqan charges for the use of its defaults, in integer
minor units of Etqan's one currency (plan D5–D8)."""

from dataclasses import dataclass
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta
from itertools import groupby

from django.db.models import Sum
from django.db.models.functions import TruncDate

from etqan.etqan_billing import clock
from etqan.etqan_billing.models import AcademyPricing
from etqan.etqan_billing.models import CollectedFee
from etqan.etqan_billing.models import ConnectFee
from etqan.etqan_billing.models import Price
from etqan.etqan_billing.models import UsageEvent
from etqan.etqan_billing.models import etqan_currency
from etqan.etqan_billing.services.usage import UNITS
from etqan.etqan_billing.services.usage import current_academy_id
from etqan.platform.currency import to_decimal_string

# Plan D5: a price is per this many units.
PER: dict[str, int] = {
    "conversation": 1,
    "email": 1000,
    "minute": 1,
    "input_token": 1_000_000,
    "output_token": 1_000_000,
}
# A usage line's description, by unit (each unit belongs to one service).
LINE_TITLES: dict[str, str] = {
    "conversation": "WhatsApp conversations",
    "email": "Emails",
    "minute": "Video meeting minutes",
    "input_token": "AI input tokens",
    "output_token": "AI output tokens",
}
# The unit's noun, one and many, for a price's wording.
NOUNS: dict[str, tuple[str, str]] = {
    "conversation": ("conversation", "conversations"),
    "email": ("email", "emails"),
    "minute": ("meeting minute", "meeting minutes"),
    "input_token": ("input token", "input tokens"),
    "output_token": ("output token", "output tokens"),
}


def next_month(period: date) -> date:
    return (period.replace(day=28) + timedelta(days=4)).replace(day=1)


def previous_month(period: date) -> date:
    return (period.replace(day=1) - timedelta(days=1)).replace(day=1)


def month_bounds(period: date) -> tuple[datetime, datetime]:
    """The UTC calendar month that ``period`` falls in, as [start, end)."""
    first = period.replace(day=1)
    return (
        datetime.combine(first, time.min, tzinfo=UTC),
        datetime.combine(next_month(first), time.min, tzinfo=UTC),
    )


def this_month() -> date:
    return clock.now().astimezone(UTC).date().replace(day=1)


def charge(billable: int, unit_amount: int, per: int) -> int:
    """``billable`` units at ``unit_amount`` per ``per`` units, rounded half
    up to a whole minor unit (plan D5)."""
    return (billable * unit_amount + per // 2) // per


def money(amount: int, currency: str) -> str:
    """``150, "USD"`` → ``"1.50 USD"``."""
    return f"{to_decimal_string(amount, currency)} {currency}"


def price_text(amount: int, currency: str, unit: str) -> str:
    """``100, "USD", "email"`` → ``"1.00 USD per 1,000 emails"``."""
    per = PER[unit]
    one, many = NOUNS[unit]
    batch = one if per == 1 else f"{per:,} {many}"
    return f"{money(amount, currency)} per {batch}"


@dataclass(frozen=True)
class Terms:
    """An academy's terms for one unit (plan D7)."""

    override: int | None = None
    free: int = 0


def terms_for(academy_id: int | None, service: str, unit: str) -> Terms:
    if academy_id is None:
        return Terms()
    row = AcademyPricing.objects.filter(
        academy_id=academy_id, service=service, unit=unit
    ).first()
    return Terms() if row is None else Terms(row.amount, row.free_allowance)


def _amount_on(prices: list[Price], day: date) -> int:
    """Plan D8: the latest price in effect on ``day``; 0 when none is."""
    return next((p.amount for p in prices if p.effective_from <= day), 0)


@dataclass(frozen=True)
class UsageLine:
    service: str
    unit: str
    quantity: int
    free_quantity: int
    unit_amount: int
    per: int
    amount: int


def daily_usage(academy_id: int, start: datetime, end: datetime) -> list[dict]:
    """The academy's use in [start, end) per service, unit and UTC day, in
    that order: ``[{"service", "unit", "day", "total"}]``."""
    return list(
        UsageEvent.objects.filter(
            academy_id=academy_id, occurred_at__gte=start, occurred_at__lt=end
        )
        .annotate(day=TruncDate("occurred_at", tzinfo=UTC))
        .values("service", "unit", "day")
        .annotate(total=Sum("quantity"))
        .order_by("service", "unit", "day")
    )


def _by_unit(rows: list[dict]):
    return groupby(rows, key=lambda row: (row["service"], row["unit"]))


def usage_lines(academy_id: int, period: date) -> list[UsageLine]:
    """Plan D7–D8: one line per service, unit and price in effect over the
    month; the monthly allowance is used up once, in date order."""
    start, end = month_bounds(period)
    lines: list[UsageLine] = []
    for (service, unit), days in _by_unit(daily_usage(academy_id, start, end)):
        terms = terms_for(academy_id, service, unit)
        prices = list(
            Price.objects.filter(service=service, unit=unit).order_by(
                "-effective_from"
            )
        )
        remaining = terms.free
        # unit amount -> [quantity, free], in the order the prices came.
        buckets: dict[int, list[int]] = {}
        for row in days:
            amount = (
                terms.override
                if terms.override is not None
                else _amount_on(prices, row["day"])
            )
            free = min(remaining, row["total"])
            remaining -= free
            bucket = buckets.setdefault(amount, [0, 0])
            bucket[0] += row["total"]
            bucket[1] += free
        per = PER[unit]
        lines.extend(
            UsageLine(
                service,
                unit,
                quantity,
                free,
                amount,
                per,
                charge(quantity - free, amount, per),
            )
            for amount, (quantity, free) in buckets.items()
        )
    return lines


def collected_fees(academy_id: int, period: date) -> list[tuple[str, int]]:
    """Plan D9: the Connect fees collected in the month, per currency."""
    start, end = month_bounds(period)
    rows = (
        CollectedFee.objects.filter(
            academy_id=academy_id, occurred_at__gte=start, occurred_at__lt=end
        )
        .values("currency")
        .annotate(total=Sum("amount"))
        .order_by("currency")
    )
    return [(row["currency"], row["total"]) for row in rows]


def has_activity(academy_id: int, period: date) -> bool:
    """Whether the month has anything to invoice: use of Etqan's defaults,
    or Connect fees collected (plan D9)."""
    start, end = month_bounds(period)
    window = {"occurred_at__gte": start, "occurred_at__lt": end}
    return (
        UsageEvent.objects.filter(academy_id=academy_id, **window).exists()
        or CollectedFee.objects.filter(academy_id=academy_id, **window).exists()
    )


def month_usage() -> dict:
    """Spec §6: the current academy's use of Etqan's defaults this UTC
    month, per service and unit, by day, with the charge so far."""
    academy_id = current_academy_id()
    period = this_month()
    usage = []
    if academy_id is not None:
        start, end = month_bounds(period)
        lines = usage_lines(academy_id, period)
        for (service, unit), days in _by_unit(daily_usage(academy_id, start, end)):
            mine = [line for line in lines if line.unit == unit]
            usage.append(
                {
                    "service": service,
                    "unit": unit,
                    "quantity": sum(line.quantity for line in mine),
                    "free": sum(line.free_quantity for line in mine),
                    "amount": sum(line.amount for line in mine),
                    "days": [
                        {"date": row["day"], "quantity": row["total"]} for row in days
                    ],
                }
            )
    return {"month": period, "currency": etqan_currency(), "usage": usage}


def current_prices(service: str) -> list[dict]:
    """Plan D18: Etqan's price today for each unit of ``service`` after the
    current academy's override, with its monthly allowance; a unit with no
    price is left out."""
    academy_id = current_academy_id()
    today = clock.now().astimezone(UTC).date()
    prices = []
    for unit in UNITS.get(service, ()):
        terms = terms_for(academy_id, service, unit)
        amount = terms.override
        if amount is None:
            price = (
                Price.objects.filter(
                    service=service, unit=unit, effective_from__lte=today
                )
                .order_by("-effective_from")
                .first()
            )
            if price is None:
                continue
            amount = price.amount
        prices.append(
            {
                "unit": unit,
                "per": PER[unit],
                "amount": amount,
                "currency": etqan_currency(),
                "free": terms.free,
            }
        )
    return prices


@dataclass(frozen=True)
class ConnectFeeTerms:
    percent_bp: int
    fixed_amount: int
    currency: str


def connect_fee() -> ConnectFeeTerms | None:
    """The current academy's Stripe Connect platform fee (spec §5, plan D7)
    for the B3 follow-up's ``application_fee``; None when Etqan set none."""
    academy_id = current_academy_id()
    row = (
        ConnectFee.objects.filter(academy_id=academy_id).first()
        if academy_id is not None
        else None
    )
    if row is None:
        return None
    return ConnectFeeTerms(row.percent_bp, row.fixed_amount, row.currency)
```

Replace `backend/etqan/etqan_billing/services/__init__.py` with:

```python
"""Public API of etqan_billing. Other apps import only this package."""

from etqan.etqan_billing.services.pricing import LINE_TITLES
from etqan.etqan_billing.services.pricing import PER
from etqan.etqan_billing.services.pricing import ConnectFeeTerms
from etqan.etqan_billing.services.pricing import Terms
from etqan.etqan_billing.services.pricing import UsageLine
from etqan.etqan_billing.services.pricing import charge
from etqan.etqan_billing.services.pricing import collected_fees
from etqan.etqan_billing.services.pricing import connect_fee
from etqan.etqan_billing.services.pricing import current_prices
from etqan.etqan_billing.services.pricing import daily_usage
from etqan.etqan_billing.services.pricing import has_activity
from etqan.etqan_billing.services.pricing import month_bounds
from etqan.etqan_billing.services.pricing import month_usage
from etqan.etqan_billing.services.pricing import money
from etqan.etqan_billing.services.pricing import next_month
from etqan.etqan_billing.services.pricing import previous_month
from etqan.etqan_billing.services.pricing import price_text
from etqan.etqan_billing.services.pricing import terms_for
from etqan.etqan_billing.services.pricing import this_month
from etqan.etqan_billing.services.pricing import usage_lines
from etqan.etqan_billing.services.usage import ETQAN
from etqan.etqan_billing.services.usage import UNITS
from etqan.etqan_billing.services.usage import current_academy_id
from etqan.etqan_billing.services.usage import record_collected_fee
from etqan.etqan_billing.services.usage import record_usage

__all__ = [
    "ETQAN",
    "LINE_TITLES",
    "PER",
    "UNITS",
    "ConnectFeeTerms",
    "Terms",
    "UsageLine",
    "charge",
    "collected_fees",
    "connect_fee",
    "current_academy_id",
    "current_prices",
    "daily_usage",
    "has_activity",
    "money",
    "month_bounds",
    "month_usage",
    "next_month",
    "previous_month",
    "price_text",
    "record_collected_fee",
    "record_usage",
    "terms_for",
    "this_month",
    "usage_lines",
]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `$DJ pytest etqan/etqan_billing -q`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/etqan_billing
git -C backend commit -m "feat(etqan_billing): prices, academy terms, allowances and the month's usage lines" -m "$TRAILER"
```

---

### Task 4: Invoices — drafts, the monthly build, issue, lines, paid, void, overdue

**Files:**
- Create: `backend/etqan/etqan_billing/services/invoices.py`, `backend/etqan/etqan_billing/tests/test_invoices.py`
- Modify: `backend/etqan/etqan_billing/services/__init__.py`, `backend/etqan/etqan_billing/tests/conftest.py`

**Interfaces:**
- Consumes: Task 3's `usage_lines`, `collected_fees`, `has_activity`, `previous_month`, `this_month`, `LINE_TITLES`; Task 2's `current_academy_id`; Task 1's models; `etqan.platform.exceptions.ValidationError`, `NotFoundError`.
- Produces: constants `DRAFT_HOURS = 24`, `DUE_DAYS = 15`, `SUSPEND_DAYS = 30`, `ADDABLE = ("manual", "credit")`, `CONNECT_FEES_TITLE`; error codes `NOT_DRAFT = "etqan_billing.not_draft"`, `NOT_ISSUED = "etqan_billing.not_issued"`, `PAID = "etqan_billing.paid"`, `ALREADY_INVOICED = "etqan_billing.already_invoiced"`, `NEGATIVE_TOTAL = "etqan_billing.negative_total"`, `USAGE_LINE = "etqan_billing.usage_line"`; `has_invoice(academy, period) -> bool`; `create_draft(academy, period: date) -> EtqanInvoice`; `build_month(period: date | None = None) -> dict[str, str]` (values `built | none | exists | failed`); `check_line(invoice, *, kind, description, amount) -> tuple[str, int]`; `add_line(invoice, *, kind, description, amount) -> EtqanInvoiceLine`; `remove_line(line) -> None`; `issue(invoice) -> EtqanInvoice`; `issue_due() -> list[int]`; `mark_paid(invoice, *, paid_on: date, method: str, reference: str = "") -> EtqanInvoice`; `void(invoice, *, reason: str = "") -> EtqanInvoice`; `is_overdue(invoice, now: datetime | None = None) -> bool`; `oldest_unpaid_days(academy) -> int | None`; `may_suspend(academy) -> bool`; `academy_invoices() -> list[EtqanInvoice]`; `academy_invoice(invoice_id: int) -> EtqanInvoice`. Test fixtures `priced` (email at 100 per 1,000 from 2026-01-01) and `draft` (main academy, 2,500 emails in September, drafted at 2026-10-01 03:00: `ETQ-2026-09-0001`, total 250).

- [ ] **Step 1: Write the failing tests**

Replace `backend/etqan/etqan_billing/tests/conftest.py` with:

```python
"""Etqan billing fixtures: a pinned clock, ledger rows made directly, and a
September draft for the main academy."""

import itertools
from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.etqan_billing import clock
from etqan.etqan_billing.models import Price
from etqan.etqan_billing.models import UsageEvent

SEPT = date(2026, 9, 1)
_refs = itertools.count(1)


def moment(text: str) -> datetime:
    """``"2026-09-10 12:00"`` as an aware UTC instant."""
    return datetime.fromisoformat(text).replace(tzinfo=UTC)


@pytest.fixture
def at(monkeypatch):
    """``at("2026-10-01 03:00")`` pins etqan_billing's clock and returns it."""

    def pin(text: str) -> datetime:
        pinned = moment(text)
        monkeypatch.setattr(clock, "now", lambda: pinned)
        return pinned

    return pin


def usage(  # noqa: PLR0913 -- one ledger row's parts
    academy,
    when: str = "2026-09-10 12:00",
    *,
    quantity: int = 1,
    service: str = "email",
    unit: str = "email",
    ref: str | None = None,
) -> UsageEvent:
    return UsageEvent.objects.create(
        academy=academy,
        service=service,
        unit=unit,
        quantity=quantity,
        occurred_at=moment(when),
        source_ref=ref or f"ref-{next(_refs)}",
    )


@pytest.fixture
def priced():
    """Etqan's email price: 1.00 per 1,000 emails since January."""
    return Price.objects.create(
        service="email", unit="email", amount=100, effective_from=date(2026, 1, 1)
    )


@pytest.fixture
def draft(tenants, priced, at):
    """The main academy's September draft: 2,500 emails, 2.50 USD, drafted
    on 1 October at 03:00 UTC (the clock stays pinned there)."""
    from etqan.etqan_billing import services  # noqa: PLC0415

    usage(tenants.main, quantity=2500)
    at("2026-10-01 03:00")
    return services.create_draft(tenants.main, SEPT)
```

`backend/etqan/etqan_billing/tests/test_invoices.py`:

```python
"""Spec §5 and §8: one invoice per academy per UTC month with usage, built
by the monthly job; drafts for 24 hours, then issued; issued invoices never
change; corrections are credit lines; overdue after 15 days; suspension
allowed from 30 (plan D9–D13, D16)."""

from datetime import date
from datetime import timedelta

import pytest

from etqan.etqan_billing import services
from etqan.etqan_billing.models import CollectedFee
from etqan.etqan_billing.models import EtqanInvoice
from etqan.etqan_billing.services import invoices as invoices_module
from etqan.etqan_billing.tests.conftest import SEPT
from etqan.etqan_billing.tests.conftest import moment
from etqan.etqan_billing.tests.conftest import usage
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
OCT = date(2026, 10, 1)


def test_the_job_drafts_last_months_invoice_for_each_academy_that_used_etqans_defaults(
    tenants, priced, at
):
    usage(tenants.main, quantity=2500)
    now = at("2026-10-01 03:00")
    results = services.build_month()
    assert (results[tenants.main.schema_name], results[tenants.other.schema_name]) == (
        "built",
        "none",
    )
    invoice = EtqanInvoice.objects.get()
    assert (
        invoice.academy_id,
        invoice.period,
        invoice.number,
        invoice.status,
        invoice.total,
        invoice.currency,
        invoice.draft_until,
    ) == (
        tenants.main.pk,
        SEPT,
        "ETQ-2026-09-0001",
        "draft",
        250,
        "USD",
        now + timedelta(hours=24),
    )
    (line,) = invoice.lines.all()
    assert (
        line.kind,
        line.description,
        line.quantity,
        line.free_quantity,
        line.unit_amount,
        line.per,
        line.amount,
    ) == ("usage", "Emails", 2500, 0, 100, 1000, 250)


def test_a_month_without_usage_makes_no_invoice(tenants, priced, at):
    usage(tenants.main, "2026-08-20 10:00")
    at("2026-10-01 03:00")
    services.build_month()
    assert not EtqanInvoice.objects.exists()


def test_running_the_job_twice_builds_nothing_new(tenants, priced, at):
    usage(tenants.main)
    at("2026-10-01 03:00")
    services.build_month()
    assert services.build_month()[tenants.main.schema_name] == "exists"
    assert EtqanInvoice.objects.count() == 1


def test_the_job_loops_every_academy_and_one_failure_does_not_stop_it(
    tenants, priced, at, monkeypatch
):
    usage(tenants.main)
    usage(tenants.other)
    real = invoices_module.create_draft

    def flaky(academy, period):
        if academy.pk == tenants.main.pk:
            raise RuntimeError("boom")
        return real(academy, period)

    monkeypatch.setattr(invoices_module, "create_draft", flaky)
    at("2026-10-01 03:00")
    results = services.build_month()
    assert (results[tenants.main.schema_name], results[tenants.other.schema_name]) == (
        "failed",
        "built",
    )
    assert list(EtqanInvoice.objects.values_list("academy_id", "number")) == [
        (tenants.other.pk, "ETQ-2026-09-0001")
    ]


def test_a_suspended_academy_still_gets_its_last_months_invoice(tenants, priced, at):
    type(tenants.other).objects.filter(pk=tenants.other.pk).update(status="suspended")
    usage(tenants.other)
    at("2026-10-01 03:00")
    assert services.build_month()[tenants.other.schema_name] == "built"


def test_numbers_count_up_within_the_month_across_academies(tenants, priced, at):
    usage(tenants.main)
    usage(tenants.other)
    at("2026-10-01 03:00")
    services.build_month()
    assert dict(
        EtqanInvoice.objects.values_list("academy__schema_name", "number")
    ) == {
        tenants.main.schema_name: "ETQ-2026-09-0001",
        tenants.other.schema_name: "ETQ-2026-09-0002",
    }
    assert services.create_draft(tenants.main, OCT).number == "ETQ-2026-10-0001"


def test_collected_connect_fees_show_but_do_not_count(tenants, priced, at):
    usage(tenants.main, quantity=2500)
    CollectedFee.objects.create(
        academy=tenants.main,
        amount=870,
        currency="EUR",
        occurred_at=moment("2026-09-12 10:00"),
        source_ref="fee_1",
    )
    at("2026-10-01 03:00")
    services.build_month()
    invoice = EtqanInvoice.objects.get()
    fee = invoice.lines.get(kind="connect_fees")
    assert (invoice.total, fee.amount, fee.currency, fee.description) == (
        250,
        870,
        "EUR",
        "Stripe Connect platform fees collected (already paid)",
    )


def test_a_month_with_only_collected_fees_is_still_invoiced(tenants, at):
    CollectedFee.objects.create(
        academy=tenants.main,
        amount=870,
        currency="USD",
        occurred_at=moment("2026-09-12 10:00"),
        source_ref="fee_1",
    )
    at("2026-10-01 03:00")
    assert services.build_month()[tenants.main.schema_name] == "built"
    assert EtqanInvoice.objects.get().total == 0


def test_a_second_invoice_for_the_month_is_refused(draft, tenants):
    with pytest.raises(ValidationError) as caught:
        services.create_draft(tenants.main, date(2026, 9, 15))
    assert caught.value.code == "etqan_billing.already_invoiced"


def test_issuing_freezes_the_invoice_and_sets_its_due_date(draft, at):
    now = at("2026-10-01 12:00")
    issued = services.issue(draft)
    assert (issued.status, issued.issued_at, issued.due_at) == (
        "issued",
        now,
        now + timedelta(days=15),
    )


def test_drafts_are_issued_after_their_24_hours(draft, at):
    at("2026-10-02 02:59")
    assert services.issue_due() == []
    at("2026-10-02 03:00")
    assert services.issue_due() == [draft.pk]
    draft.refresh_from_db()
    assert draft.status == "issued"


def test_an_issued_invoice_never_changes(draft, tenants, at):
    services.issue(draft)
    usage_line = draft.lines.get()
    for change in (
        lambda: services.add_line(
            draft, kind="manual", description="Setup", amount=1000
        ),
        lambda: services.remove_line(usage_line),
        lambda: services.issue(draft),
    ):
        with pytest.raises(ValidationError) as caught:
            change()
        assert caught.value.code == "etqan_billing.not_draft"
    usage(tenants.main, "2026-09-29 10:00", quantity=9000)
    assert services.build_month(SEPT)[tenants.main.schema_name] == "exists"
    draft.refresh_from_db()
    assert (draft.total, draft.lines.count()) == (250, 1)


def test_etqan_adds_manual_and_credit_lines_to_a_draft(draft):
    services.add_line(draft, kind="manual", description="Onboarding call", amount=5000)
    services.add_line(
        draft, kind="credit", description="Correction to ETQ-2026-08-0004", amount=1250
    )
    draft.refresh_from_db()
    assert draft.total == 250 + 5000 - 1250
    assert list(draft.lines.values_list("kind", "amount")) == [
        ("usage", 250),
        ("manual", 5000),
        ("credit", -1250),
    ]


def test_a_correction_is_a_credit_line_on_the_next_invoice(tenants, priced, at):
    usage(tenants.main, quantity=2500)
    at("2026-10-01 03:00")
    september = services.issue(services.create_draft(tenants.main, SEPT))
    usage(tenants.main, "2026-10-10 12:00", quantity=5000)
    at("2026-11-01 03:00")
    services.build_month()
    october = EtqanInvoice.objects.get(period=OCT)
    services.add_line(
        october,
        kind="credit",
        description=f"Correction to {september.number}",
        amount=100,
    )
    october.refresh_from_db()
    september.refresh_from_db()
    assert (october.total, september.total, september.lines.count()) == (400, 250, 1)


def test_a_credit_cannot_take_the_invoice_below_zero(draft):
    with pytest.raises(ValidationError) as caught:
        services.add_line(draft, kind="credit", description="Too much", amount=251)
    assert caught.value.code == "etqan_billing.negative_total"


@pytest.mark.parametrize(
    ("kind", "description", "amount", "field"),
    [
        ("usage", "Emails", 10, "kind"),
        ("connect_fees", "Fees", 10, "kind"),
        ("manual", "  ", 10, "description"),
        ("manual", "x" * 201, 10, "description"),
        ("manual", "Setup", 0, "amount"),
        ("manual", "Setup", -5, "amount"),
        ("manual", "Setup", True, "amount"),
        ("manual", "Setup", 2.5, "amount"),
    ],
)
def test_a_wrong_line_is_refused(draft, kind, description, amount, field):
    with pytest.raises(ValidationError) as caught:
        services.add_line(draft, kind=kind, description=description, amount=amount)
    assert caught.value.field == field


def test_usage_lines_cannot_be_removed_but_manual_ones_can(draft):
    manual = services.add_line(draft, kind="manual", description="Setup", amount=10)
    with pytest.raises(ValidationError) as caught:
        services.remove_line(draft.lines.get(kind="usage"))
    assert caught.value.code == "etqan_billing.usage_line"
    services.remove_line(manual)
    draft.refresh_from_db()
    assert draft.total == 250


def test_removing_a_charge_cannot_leave_a_credit_below_zero(draft):
    manual = services.add_line(draft, kind="manual", description="Setup", amount=1000)
    services.add_line(draft, kind="credit", description="Goodwill", amount=1200)
    with pytest.raises(ValidationError) as caught:
        services.remove_line(manual)
    assert caught.value.code == "etqan_billing.negative_total"


def test_etqan_marks_an_issued_invoice_paid(draft, at):
    services.issue(draft)
    at("2026-10-10 09:00")
    paid = services.mark_paid(
        draft, paid_on=date(2026, 10, 9), method="bank_transfer", reference=" TRX-77 "
    )
    assert (paid.status, paid.paid_on, paid.paid_method, paid.paid_reference) == (
        "paid",
        date(2026, 10, 9),
        "bank_transfer",
        "TRX-77",
    )


def test_only_an_issued_invoice_can_be_paid(draft):
    with pytest.raises(ValidationError) as caught:
        services.mark_paid(draft, paid_on=date(2026, 10, 1), method="cash")
    assert caught.value.code == "etqan_billing.not_issued"


@pytest.mark.parametrize(
    ("paid_on", "method", "field"),
    [
        (date(2026, 10, 1), "crypto", "method"),
        (date(2026, 10, 2), "cash", "paid_on"),
        (None, "cash", "paid_on"),
    ],
)
def test_a_payment_needs_a_known_method_and_a_day_not_in_the_future(
    draft, paid_on, method, field
):
    services.issue(draft)
    with pytest.raises(ValidationError) as caught:
        services.mark_paid(draft, paid_on=paid_on, method=method)
    assert caught.value.field == field


def test_a_draft_or_issued_invoice_can_be_voided_never_a_paid_one(draft, tenants, at):
    services.void(draft, reason=" Duplicate ")
    draft.refresh_from_db()
    assert (draft.status, draft.void_reason, draft.voided_at) == (
        "void",
        "Duplicate",
        moment("2026-10-01 03:00"),
    )
    again = services.issue(services.create_draft(tenants.main, SEPT))
    assert again.number == "ETQ-2026-09-0002"
    services.mark_paid(again, paid_on=date(2026, 10, 1), method="cash")
    with pytest.raises(ValidationError) as caught:
        services.void(again)
    assert caught.value.code == "etqan_billing.paid"


def test_an_invoice_is_overdue_15_days_after_issue(draft):
    services.issue(draft)
    draft.refresh_from_db()
    assert not services.is_overdue(draft, moment("2026-10-16 02:59"))
    assert services.is_overdue(draft, moment("2026-10-16 03:00"))
    services.mark_paid(draft, paid_on=date(2026, 10, 1), method="cash")
    draft.refresh_from_db()
    assert not services.is_overdue(draft, moment("2026-11-30 00:00"))


def test_a_zero_invoice_is_never_overdue(tenants, at):
    at("2026-10-01 03:00")
    invoice = services.issue(services.create_draft(tenants.main, SEPT))
    assert invoice.total == 0
    assert not services.is_overdue(invoice, moment("2027-01-01 00:00"))


def test_suspending_is_allowed_from_30_days_unpaid(draft, tenants, at):
    assert services.oldest_unpaid_days(tenants.main) is None
    services.issue(draft)
    at("2026-10-31 02:59")
    assert (
        services.oldest_unpaid_days(tenants.main),
        services.may_suspend(tenants.main),
    ) == (29, False)
    at("2026-10-31 03:00")
    assert (
        services.oldest_unpaid_days(tenants.main),
        services.may_suspend(tenants.main),
    ) == (30, True)


def test_the_academy_sees_only_its_issued_invoices(draft, tenants):
    theirs = services.issue(services.create_draft(tenants.other, SEPT))
    assert services.academy_invoices() == []
    services.issue(draft)
    assert [invoice.pk for invoice in services.academy_invoices()] == [draft.pk]
    assert services.academy_invoice(draft.pk).number == "ETQ-2026-09-0001"
    with pytest.raises(NotFoundError):
        services.academy_invoice(theirs.pk)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/etqan_billing/tests/test_invoices.py -q`
Expected: FAIL at collection with `ImportError: cannot import name 'invoices' from 'etqan.etqan_billing.services'`.

- [ ] **Step 3: Write the invoice services**

`backend/etqan/etqan_billing/services/invoices.py`:

```python
"""Spec §5: Etqan's monthly invoices to academies. Drafts are built from
the metered usage, stay editable for 24 hours and are then issued; an
issued invoice never changes again (corrections are credit lines on the
next one). Emailing the PDF is `etqan_billing.tasks`' job (plan D2)."""

import logging
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import timedelta

from django.db import transaction
from django.db.models import Sum
from django_tenants.utils import get_public_schema_name
from django_tenants.utils import get_tenant_model

from etqan.etqan_billing import clock
from etqan.etqan_billing.models import EtqanInvoice
from etqan.etqan_billing.models import EtqanInvoiceLine
from etqan.etqan_billing.models import InvoiceSequence
from etqan.etqan_billing.models import etqan_currency
from etqan.etqan_billing.services.pricing import LINE_TITLES
from etqan.etqan_billing.services.pricing import collected_fees
from etqan.etqan_billing.services.pricing import has_activity
from etqan.etqan_billing.services.pricing import previous_month
from etqan.etqan_billing.services.pricing import this_month
from etqan.etqan_billing.services.pricing import usage_lines
from etqan.etqan_billing.services.usage import current_academy_id
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

logger = logging.getLogger(__name__)
Status = EtqanInvoice.Status
Kind = EtqanInvoiceLine.Kind

DRAFT_HOURS = 24
DUE_DAYS = 15
SUSPEND_DAYS = 30
DESCRIPTION_LENGTH = 200
NUMBER = "ETQ-{:%Y-%m}-{:04d}"
ADDABLE = (Kind.MANUAL, Kind.CREDIT)
CONNECT_FEES_TITLE = "Stripe Connect platform fees collected (already paid)"

NOT_DRAFT = "etqan_billing.not_draft"
NOT_ISSUED = "etqan_billing.not_issued"
PAID = "etqan_billing.paid"
ALREADY_INVOICED = "etqan_billing.already_invoiced"
NEGATIVE_TOTAL = "etqan_billing.negative_total"
USAGE_LINE = "etqan_billing.usage_line"


def _next_number(period: date) -> str:
    """Plan D10. The month's counter row is taken FOR UPDATE, in the
    draft's transaction: a rolled-back draft gives its number back."""
    sequence, _ = InvoiceSequence.objects.select_for_update().get_or_create(
        period=period
    )
    sequence.last_number += 1
    sequence.save(update_fields=["last_number"])
    return NUMBER.format(period, sequence.last_number)


def has_invoice(academy, period: date) -> bool:
    return (
        EtqanInvoice.objects.filter(academy=academy, period=period.replace(day=1))
        .exclude(status=Status.VOID)
        .exists()
    )


def _retotal(invoice: EtqanInvoice) -> None:
    """Plan D9: the collected Connect fees are shown, never charged."""
    invoice.total = (
        invoice.lines.exclude(kind=Kind.CONNECT_FEES).aggregate(total=Sum("amount"))[
            "total"
        ]
        or 0
    )
    invoice.save(update_fields=["total"])


@transaction.atomic
def create_draft(academy, period: date) -> EtqanInvoice:
    """A draft for the month ``period`` falls in, with its usage lines and
    its collected Connect fees (none when the month had neither: Etqan's
    hand-made draft, plan D12)."""
    period = period.replace(day=1)
    if has_invoice(academy, period):
        raise ValidationError(
            "This academy already has an invoice for that month.",
            code=ALREADY_INVOICED,
        )
    currency = etqan_currency()
    invoice = EtqanInvoice.objects.create(
        academy=academy,
        period=period,
        number=_next_number(period),
        currency=currency,
        draft_until=clock.now() + timedelta(hours=DRAFT_HOURS),
    )
    EtqanInvoiceLine.objects.bulk_create(
        [
            EtqanInvoiceLine(
                invoice=invoice,
                kind=Kind.USAGE,
                service=line.service,
                unit=line.unit,
                quantity=line.quantity,
                free_quantity=line.free_quantity,
                unit_amount=line.unit_amount,
                per=line.per,
                amount=line.amount,
                currency=currency,
                description=LINE_TITLES[line.unit],
            )
            for line in usage_lines(academy.pk, period)
        ]
        + [
            EtqanInvoiceLine(
                invoice=invoice,
                kind=Kind.CONNECT_FEES,
                service="payments",
                amount=total,
                currency=fee_currency,
                description=CONNECT_FEES_TITLE,
            )
            for fee_currency, total in collected_fees(academy.pk, period)
        ]
    )
    _retotal(invoice)
    return invoice


def _build_one(academy, period: date) -> str:
    if has_invoice(academy, period):
        return "exists"
    if not has_activity(academy.pk, period):
        return "none"
    create_draft(academy, period)
    return "built"


def build_month(period: date | None = None) -> dict[str, str]:
    """Spec §5's monthly job (plan D13): drafts for the previous UTC month
    (or ``period``'s) for every academy that used Etqan's defaults. Loops
    every academy itself, suspended ones too, one transaction each; a
    failing academy is logged and the loop moves on. Returns
    ``{schema_name: "built" | "none" | "exists" | "failed"}``."""
    month = (period or previous_month(this_month())).replace(day=1)
    academies = (
        get_tenant_model()
        .objects.exclude(schema_name=get_public_schema_name())
        .order_by("schema_name")
    )
    results: dict[str, str] = {}
    for academy in academies:
        try:
            with transaction.atomic():
                results[academy.schema_name] = _build_one(academy, month)
        except Exception:
            logger.exception(
                "Etqan invoice for %s failed for academy %s",
                f"{month:%Y-%m}",
                academy.schema_name,
            )
            results[academy.schema_name] = "failed"
    return results


def _locked(invoice: EtqanInvoice) -> EtqanInvoice:
    return EtqanInvoice.objects.select_for_update().get(pk=invoice.pk)


def _draft(invoice: EtqanInvoice) -> EtqanInvoice:
    locked = _locked(invoice)
    if locked.status != Status.DRAFT:
        raise ValidationError(
            "Only a draft invoice can change. Correct an issued one with a "
            "credit line on the next invoice.",
            code=NOT_DRAFT,
        )
    return locked


def check_line(
    invoice: EtqanInvoice, *, kind: str, description: object, amount: object
) -> tuple[str, int]:
    """Plan D12: a manual or credit line's description and signed amount
    (a credit is entered positive and stored negative), or a
    ValidationError naming the field. ``invoice`` must stay at or above
    zero."""
    if kind not in ADDABLE:
        raise ValidationError("Only a manual or a credit line can be added.", field="kind")
    text = description.strip() if isinstance(description, str) else ""
    if not text:
        raise ValidationError("Describe the line.", field="description")
    if len(text) > DESCRIPTION_LENGTH:
        raise ValidationError(
            f"Keep the description to {DESCRIPTION_LENGTH} characters.",
            field="description",
        )
    if isinstance(amount, bool) or not isinstance(amount, int) or amount <= 0:
        raise ValidationError(
            "Enter a positive whole amount in minor units.", field="amount"
        )
    signed = -amount if kind == Kind.CREDIT else amount
    if invoice.total + signed < 0:
        raise ValidationError(
            "A credit cannot take the invoice below zero.", code=NEGATIVE_TOTAL
        )
    return text, signed


@transaction.atomic
def add_line(
    invoice: EtqanInvoice, *, kind: str, description: object, amount: object
) -> EtqanInvoiceLine:
    locked = _draft(invoice)
    text, signed = check_line(
        locked, kind=kind, description=description, amount=amount
    )
    line = EtqanInvoiceLine.objects.create(
        invoice=locked,
        kind=kind,
        amount=signed,
        currency=locked.currency,
        description=text,
    )
    _retotal(locked)
    return line


@transaction.atomic
def remove_line(line: EtqanInvoiceLine) -> None:
    locked = _draft(line.invoice)
    if line.kind not in ADDABLE:
        raise ValidationError(
            "A usage line comes from the metered use and cannot be removed.",
            code=USAGE_LINE,
        )
    if locked.total - line.amount < 0:
        raise ValidationError(
            "Removing this line would take the invoice below zero.",
            code=NEGATIVE_TOTAL,
        )
    line.delete()
    _retotal(locked)


@transaction.atomic
def issue(invoice: EtqanInvoice) -> EtqanInvoice:
    """Freeze the draft and start its 15 days (plan D11)."""
    locked = _draft(invoice)
    now = clock.now()
    locked.status = Status.ISSUED
    locked.issued_at = now
    locked.due_at = now + timedelta(days=DUE_DAYS)
    locked.save(update_fields=["status", "issued_at", "due_at"])
    return locked


def issue_due() -> list[int]:
    """Drafts past their 24 hours, issued (spec §5); their ids."""
    due = EtqanInvoice.objects.filter(
        status=Status.DRAFT, draft_until__lte=clock.now()
    ).order_by("number")
    return [issue(invoice).pk for invoice in list(due)]


@transaction.atomic
def mark_paid(
    invoice: EtqanInvoice, *, paid_on: object, method: str, reference: str = ""
) -> EtqanInvoice:
    """IN-6: Etqan records a payment it received, by any method."""
    locked = _locked(invoice)
    if locked.status != Status.ISSUED:
        raise ValidationError(
            "Only an issued invoice can be marked paid.", code=NOT_ISSUED
        )
    if method not in EtqanInvoice.PaidMethod.values:
        raise ValidationError("Choose how it was paid.", field="method")
    today = clock.now().astimezone(UTC).date()
    if not isinstance(paid_on, date) or paid_on > today:
        raise ValidationError(
            "Enter the day it was paid, not a future one.", field="paid_on"
        )
    locked.status = Status.PAID
    locked.paid_on = paid_on
    locked.paid_method = method
    locked.paid_reference = (reference or "").strip()[:100]
    locked.save(
        update_fields=["status", "paid_on", "paid_method", "paid_reference"]
    )
    return locked


@transaction.atomic
def void(invoice: EtqanInvoice, *, reason: str = "") -> EtqanInvoice:
    """A draft or an issued invoice withdrawn; its month is free for a new
    draft. A paid one is corrected with a credit instead."""
    locked = _locked(invoice)
    if locked.status == Status.PAID:
        raise ValidationError(
            "A paid invoice cannot be voided; credit the next invoice instead.",
            code=PAID,
        )
    if locked.status != Status.VOID:
        locked.status = Status.VOID
        locked.voided_at = clock.now()
        locked.void_reason = (reason or "").strip()[:200]
        locked.save(update_fields=["status", "voided_at", "void_reason"])
    return locked


def is_overdue(invoice: EtqanInvoice, now: datetime | None = None) -> bool:
    """Plan D11: issued, something to pay, and 15 days gone."""
    moment = now or clock.now()
    return (
        invoice.status == Status.ISSUED
        and invoice.total > 0
        and invoice.due_at is not None
        and moment >= invoice.due_at
    )


def oldest_unpaid_days(academy) -> int | None:
    """Whole days since the academy's oldest unpaid invoice was issued."""
    oldest = (
        EtqanInvoice.objects.filter(
            academy=academy, status=Status.ISSUED, total__gt=0
        )
        .order_by("issued_at")
        .first()
    )
    return None if oldest is None else (clock.now() - oldest.issued_at).days


def may_suspend(academy) -> bool:
    """Spec §5, plan D16: from 30 days after issue, Etqan may suspend."""
    days = oldest_unpaid_days(academy)
    return days is not None and days >= SUSPEND_DAYS


def academy_invoices() -> list[EtqanInvoice]:
    """Plan D17: the current academy's invoices once issued (drafts are
    Etqan's), newest month first."""
    return list(
        EtqanInvoice.objects.filter(
            academy_id=current_academy_id(), issued_at__isnull=False
        ).order_by("-period", "-number")
    )


def academy_invoice(invoice_id: int) -> EtqanInvoice:
    invoice = (
        EtqanInvoice.objects.filter(
            academy_id=current_academy_id(), issued_at__isnull=False, pk=invoice_id
        )
        .select_related("academy")
        .first()
    )
    if invoice is None:
        raise NotFoundError("Invoice", invoice_id)
    return invoice
```

Replace `backend/etqan/etqan_billing/services/__init__.py` with:

```python
"""Public API of etqan_billing. Other apps import only this package."""

from etqan.etqan_billing.services.invoices import ADDABLE
from etqan.etqan_billing.services.invoices import ALREADY_INVOICED
from etqan.etqan_billing.services.invoices import CONNECT_FEES_TITLE
from etqan.etqan_billing.services.invoices import DRAFT_HOURS
from etqan.etqan_billing.services.invoices import DUE_DAYS
from etqan.etqan_billing.services.invoices import NEGATIVE_TOTAL
from etqan.etqan_billing.services.invoices import NOT_DRAFT
from etqan.etqan_billing.services.invoices import NOT_ISSUED
from etqan.etqan_billing.services.invoices import PAID
from etqan.etqan_billing.services.invoices import SUSPEND_DAYS
from etqan.etqan_billing.services.invoices import USAGE_LINE
from etqan.etqan_billing.services.invoices import academy_invoice
from etqan.etqan_billing.services.invoices import academy_invoices
from etqan.etqan_billing.services.invoices import add_line
from etqan.etqan_billing.services.invoices import build_month
from etqan.etqan_billing.services.invoices import check_line
from etqan.etqan_billing.services.invoices import create_draft
from etqan.etqan_billing.services.invoices import has_invoice
from etqan.etqan_billing.services.invoices import is_overdue
from etqan.etqan_billing.services.invoices import issue
from etqan.etqan_billing.services.invoices import issue_due
from etqan.etqan_billing.services.invoices import mark_paid
from etqan.etqan_billing.services.invoices import may_suspend
from etqan.etqan_billing.services.invoices import oldest_unpaid_days
from etqan.etqan_billing.services.invoices import remove_line
from etqan.etqan_billing.services.invoices import void
from etqan.etqan_billing.services.pricing import LINE_TITLES
from etqan.etqan_billing.services.pricing import PER
from etqan.etqan_billing.services.pricing import ConnectFeeTerms
from etqan.etqan_billing.services.pricing import Terms
from etqan.etqan_billing.services.pricing import UsageLine
from etqan.etqan_billing.services.pricing import charge
from etqan.etqan_billing.services.pricing import collected_fees
from etqan.etqan_billing.services.pricing import connect_fee
from etqan.etqan_billing.services.pricing import current_prices
from etqan.etqan_billing.services.pricing import daily_usage
from etqan.etqan_billing.services.pricing import has_activity
from etqan.etqan_billing.services.pricing import month_bounds
from etqan.etqan_billing.services.pricing import month_usage
from etqan.etqan_billing.services.pricing import money
from etqan.etqan_billing.services.pricing import next_month
from etqan.etqan_billing.services.pricing import previous_month
from etqan.etqan_billing.services.pricing import price_text
from etqan.etqan_billing.services.pricing import terms_for
from etqan.etqan_billing.services.pricing import this_month
from etqan.etqan_billing.services.pricing import usage_lines
from etqan.etqan_billing.services.usage import ETQAN
from etqan.etqan_billing.services.usage import UNITS
from etqan.etqan_billing.services.usage import current_academy_id
from etqan.etqan_billing.services.usage import record_collected_fee
from etqan.etqan_billing.services.usage import record_usage

__all__ = [
    "ADDABLE",
    "ALREADY_INVOICED",
    "CONNECT_FEES_TITLE",
    "DRAFT_HOURS",
    "DUE_DAYS",
    "ETQAN",
    "LINE_TITLES",
    "NEGATIVE_TOTAL",
    "NOT_DRAFT",
    "NOT_ISSUED",
    "PAID",
    "PER",
    "SUSPEND_DAYS",
    "UNITS",
    "USAGE_LINE",
    "ConnectFeeTerms",
    "Terms",
    "UsageLine",
    "academy_invoice",
    "academy_invoices",
    "add_line",
    "build_month",
    "charge",
    "check_line",
    "collected_fees",
    "connect_fee",
    "create_draft",
    "current_academy_id",
    "current_prices",
    "daily_usage",
    "has_activity",
    "has_invoice",
    "is_overdue",
    "issue",
    "issue_due",
    "mark_paid",
    "may_suspend",
    "money",
    "month_bounds",
    "month_usage",
    "next_month",
    "oldest_unpaid_days",
    "previous_month",
    "price_text",
    "record_collected_fee",
    "record_usage",
    "remove_line",
    "terms_for",
    "this_month",
    "usage_lines",
    "void",
]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `$DJ pytest etqan/etqan_billing -q`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/etqan_billing
git -C backend commit -m "feat(etqan_billing): monthly drafts, issue, manual and credit lines, paid, void, overdue" -m "$TRAILER"
```

---

### Task 5: The invoice PDF

**Files:**
- Create: `backend/etqan/etqan_billing/pdf.py`, `backend/etqan/etqan_billing/fonts/DejaVuSans.ttf`, `backend/etqan/etqan_billing/fonts/DejaVuSans-Bold.ttf`, `backend/etqan/etqan_billing/fonts/LICENSE`, `backend/etqan/etqan_billing/tests/test_pdf.py`
- Modify: `backend/requirements/base.txt`

**Interfaces:**
- Consumes: Task 1's `EtqanInvoice`, `EtqanInvoiceLine.Kind`; Task 3's `money`; `settings.ETQAN_BILLING_PAYMENT_INSTRUCTIONS`.
- Produces: `etqan.etqan_billing.pdf.render(invoice: EtqanInvoice) -> bytes` (a PDF whose document title is the invoice number); `filename(invoice) -> str` (`"ETQ-2026-09-0001.pdf"`); `PDF_TYPE = "application/pdf"`.

- [ ] **Step 1: Add the dependencies and the fonts**

Append to `backend/requirements/base.txt`:

```
# Integrations slice 2: Etqan's invoice PDF, with Arabic shaping (plan D15).
fpdf2>=2.8
uharfbuzz>=0.39
```

Fetch DejaVu Sans (free licence, redistributable; committed so neither CI nor the image needs a system font):

```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/integrations-2/backend/etqan/etqan_billing
mkdir -p fonts
TARBALL="$(mktemp)"
curl -fsSL -o "$TARBALL" https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.tar.bz2
tar -xjf "$TARBALL" -C fonts --strip-components=2 dejavu-fonts-ttf-2.37/ttf/DejaVuSans.ttf dejavu-fonts-ttf-2.37/ttf/DejaVuSans-Bold.ttf
tar -xjf "$TARBALL" -C fonts --strip-components=1 dejavu-fonts-ttf-2.37/LICENSE
rm "$TARBALL"
ls fonts
cd /home/abdulkhalek/Projects/etqan_tutor-wt/integrations-2
```

Expected: `DejaVuSans-Bold.ttf  DejaVuSans.ttf  LICENSE`.

Rebuild the images for the new packages: `just rebuild && just dev-backend`.
Expected: the build installs `fpdf2` and `uharfbuzz`; `$DJ python -c "import fpdf, uharfbuzz; print(fpdf.__version__)"` prints a version ≥ 2.8.

- [ ] **Step 2: Write the failing test**

`backend/etqan/etqan_billing/tests/test_pdf.py`:

```python
"""Spec §5: the invoice PDF that goes to the academy's admins and that
they download; an Arabic academy name or line renders (plan D15)."""

from datetime import date

import pytest

from etqan.etqan_billing import pdf
from etqan.etqan_billing import services
from etqan.etqan_billing.models import EtqanInvoice
from etqan.etqan_billing.models import EtqanInvoiceLine

pytestmark = pytest.mark.django_db


def test_the_pdf_names_the_invoice(draft):
    data = pdf.render(draft)
    assert data.startswith(b"%PDF-")
    assert b"ETQ-2026-09-0001" in data  # the document's title
    assert pdf.filename(draft) == "ETQ-2026-09-0001.pdf"


def test_an_arabic_academy_name_and_every_kind_of_line_render(draft):
    services.add_line(draft, kind="manual", description="جلسة إعداد", amount=500)
    services.add_line(draft, kind="credit", description="Correction", amount=100)
    EtqanInvoiceLine.objects.create(
        invoice=draft,
        kind="connect_fees",
        service="payments",
        amount=870,
        currency="EUR",
        description=services.CONNECT_FEES_TITLE,
    )
    services.issue(draft)
    services.mark_paid(draft, paid_on=date(2026, 10, 1), method="bank_transfer")
    # A fresh academy object: the session-shared one must keep its name.
    invoice = EtqanInvoice.objects.select_related("academy").get(pk=draft.pk)
    invoice.academy.name = "أكاديمية نور"
    assert pdf.render(invoice).startswith(b"%PDF-")
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `$DJ pytest etqan/etqan_billing/tests/test_pdf.py -q`
Expected: FAIL at collection with `ImportError: cannot import name 'pdf' from 'etqan.etqan_billing'`.

- [ ] **Step 4: Write the renderer**

`backend/etqan/etqan_billing/pdf.py`:

```python
"""The PDF of an Etqan invoice (spec §5): attached to the email to the
academy's admins and downloaded from Settings → Etqan billing. English
labels; DejaVu Sans with text shaping, so an Arabic academy name or line
reads joined and right to left (plan D15)."""

from pathlib import Path

from django.conf import settings
from fpdf import FPDF
from fpdf.enums import XPos
from fpdf.enums import YPos

from etqan.etqan_billing.models import EtqanInvoice
from etqan.etqan_billing.models import EtqanInvoiceLine
from etqan.etqan_billing.services import money

PDF_TYPE = "application/pdf"
FONTS = Path(__file__).resolve().parent / "fonts"
FAMILY = "DejaVu"
NEXT_LINE = {"new_x": XPos.LMARGIN, "new_y": YPos.NEXT}
HEADINGS = ("Description", "Quantity", "Free", "Unit price", "Amount")
WIDTHS = (70, 25, 25, 35, 35)
ALIGN = ("LEFT", "RIGHT", "RIGHT", "RIGHT", "RIGHT")
Kind = EtqanInvoiceLine.Kind


def filename(invoice: EtqanInvoice) -> str:
    return f"{invoice.number}.pdf"


def _day(value) -> str:
    return f"{value:%d %B %Y}" if value else "—"


def _facts(invoice: EtqanInvoice) -> list[tuple[str, str]]:
    facts = [
        ("Billed to", invoice.academy.name),
        ("Period", f"{invoice.period:%B %Y} (UTC)"),
        ("Status", invoice.get_status_display()),
    ]
    if invoice.issued_at:
        facts += [("Issued", _day(invoice.issued_at)), ("Due", _day(invoice.due_at))]
    if invoice.paid_on:
        facts.append(
            ("Paid", f"{_day(invoice.paid_on)} · {invoice.get_paid_method_display()}")
        )
    return facts


def _row(line: EtqanInvoiceLine) -> tuple[str, ...]:
    if line.kind == Kind.USAGE:
        return (
            line.description,
            f"{line.quantity:,}",
            f"{line.free_quantity:,}",
            f"{money(line.unit_amount, line.currency)} / {line.per:,}",
            money(line.amount, line.currency),
        )
    return (line.description, "", "", "", money(line.amount, line.currency))


def render(invoice: EtqanInvoice) -> bytes:
    pdf = FPDF(format="A4")
    pdf.set_title(invoice.number)
    pdf.set_author("Etqan")
    pdf.add_font(FAMILY, "", str(FONTS / "DejaVuSans.ttf"))
    pdf.add_font(FAMILY, "B", str(FONTS / "DejaVuSans-Bold.ttf"))
    pdf.set_text_shaping(use_shaping_engine=True)
    pdf.add_page()
    pdf.set_font(FAMILY, "B", 16)
    pdf.cell(0, 10, f"Etqan invoice {invoice.number}", **NEXT_LINE)
    pdf.set_font(FAMILY, "", 10)
    for label, value in _facts(invoice):
        pdf.cell(0, 6, f"{label}: {value}", **NEXT_LINE)
    pdf.ln(4)
    lines = list(invoice.lines.all())
    with pdf.table(col_widths=WIDTHS, text_align=ALIGN) as table:
        table.row(HEADINGS)
        for line in lines:
            if line.kind != Kind.CONNECT_FEES:
                table.row(_row(line))
    pdf.ln(2)
    pdf.set_font(FAMILY, "B", 12)
    pdf.cell(
        0, 8, f"Total: {money(invoice.total, invoice.currency)}", align="R", **NEXT_LINE
    )
    pdf.set_font(FAMILY, "", 9)
    for line in lines:
        if line.kind == Kind.CONNECT_FEES:
            pdf.cell(
                0, 6, f"{line.description}: {money(line.amount, line.currency)}", **NEXT_LINE
            )
    pdf.ln(4)
    pdf.multi_cell(0, 5, settings.ETQAN_BILLING_PAYMENT_INSTRUCTIONS)
    return bytes(pdf.output())
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `$DJ pytest etqan/etqan_billing/tests/test_pdf.py -q`
Expected: PASS (2 passed). If the Arabic test fails with an `uharfbuzz` import error, the image was not rebuilt (Step 1).

- [ ] **Step 6: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/etqan_billing requirements/base.txt
git -C backend commit -m "feat(etqan_billing): invoice PDF with DejaVu Sans and Arabic shaping" -m "$TRAILER"
```

---

### Task 6: Background jobs — monthly drafts, issuing, the invoice email

**Files:**
- Create: `backend/etqan/etqan_billing/tasks.py`, `backend/etqan/etqan_billing/tests/test_tasks.py`
- Modify: `backend/config/settings/base.py`, `backend/pyproject.toml`

**Interfaces:**
- Consumes: Task 4's `build_month`, `issue_due`, `issue`; Task 5's `pdf.render`, `pdf.filename`, `pdf.PDF_TYPE`; Task 3's `money`; `etqan.identity.services.active_admins()`; `etqan.integrations.services.send_email_now(..., attachments=)`, `NotSetUpError`; `etqan.platform.tenancy.academy_context`; `etqan.platform.frontend.app_url`.
- Produces: Celery tasks `etqan_billing.build_month` (`build_month() -> dict[str, str]`), `etqan_billing.issue_due` (`issue_due() -> list[int]`, emails each), `etqan_billing.send_invoice` (`send_invoice(invoice_id: int) -> str`: `sent | not_issued | no_admins | not_set_up`); beat entries for the first two; `BILLING_PATH = "/settings/etqan-billing"`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/etqan_billing/tests/test_tasks.py`:

```python
"""Spec §5: the 1st-of-month drafts, issuing after 24 hours, and the PDF
emailed to the academy's admins from Etqan (plan D13, D14)."""

import pytest
from celery.schedules import crontab
from django.conf import settings
from django.core import mail
from django.db import connection

from etqan.etqan_billing import services
from etqan.etqan_billing import tasks
from etqan.etqan_billing.models import EtqanInvoice
from etqan.etqan_billing.models import UsageEvent
from etqan.etqan_billing.tests.conftest import usage
from etqan.integrations import services as integrations

pytestmark = pytest.mark.django_db
SMTP = {
    "host": "smtp.noor.test",
    "port": 587,
    "username": "mailer@noor.test",
    "password": "app-password-1234",
    "security": "starttls",
    "from_address": "office@noor.test",
}


@pytest.fixture
def head(api_for):
    """The academy's admin, who gets Etqan's invoices; a teacher does not."""
    api_for("teacher", email="teacher@noor.test")
    return api_for("admin", email="head@noor.test").user


def test_the_beat_runs_the_month_on_the_first_and_issues_hourly():
    schedule = settings.CELERY_BEAT_SCHEDULE
    assert schedule["etqan_billing.build_month"] == {
        "task": "etqan_billing.build_month",
        "schedule": crontab(day_of_month=1, hour=3, minute=0),
    }
    assert schedule["etqan_billing.issue_due"] == {
        "task": "etqan_billing.issue_due",
        "schedule": crontab(minute=10),
    }


def test_the_monthly_task_builds_last_months_drafts(tenants, priced, at):
    usage(tenants.main, quantity=2500)
    at("2026-10-01 03:00")
    results = tasks.build_month.delay().get()
    assert results[tenants.main.schema_name] == "built"


def test_the_issued_invoice_is_emailed_to_the_academys_admins_with_its_pdf(
    draft, head
):
    issued = services.issue(draft)
    assert tasks.send_invoice.delay(issued.pk).get() == "sent"
    (message,) = mail.outbox
    assert message.to == ["head@noor.test"]
    assert message.subject == "[Etqan] Invoice ETQ-2026-09-0001 for September 2026"
    assert message.from_email == settings.DEFAULT_FROM_EMAIL
    assert "2.50 USD, due by 16 October 2026" in message.body
    assert "http://testserver/app/settings/etqan-billing" in message.body
    assert settings.ETQAN_BILLING_PAYMENT_INSTRUCTIONS in message.body
    ((name, content, mimetype),) = message.attachments
    assert (name, mimetype) == ("ETQ-2026-09-0001.pdf", "application/pdf")
    assert content.startswith(b"%PDF-")
    issued.refresh_from_db()
    assert issued.emailed_at is not None
    # The task gives the connection back as it found it.
    assert connection.schema_name == issued.academy.schema_name


def test_the_invoice_email_goes_out_on_etqans_default_and_is_never_metered(
    draft, head
):
    # The academy's own SMTP server sends the academy's mail; Etqan's
    # invoice is Etqan's mail and must not go through it, nor count as use.
    integrations.connect("email", fields=dict(SMTP), by=head)
    before = UsageEvent.objects.count()
    issued = services.issue(draft)
    assert tasks.send_invoice.delay(issued.pk).get() == "sent"
    (message,) = mail.outbox
    assert message.from_email == settings.DEFAULT_FROM_EMAIL
    assert UsageEvent.objects.count() == before


def test_a_draft_is_not_emailed(draft, head):
    assert tasks.send_invoice.delay(draft.pk).get() == "not_issued"
    assert mail.outbox == []


def test_an_academy_without_an_admin_gets_no_email(draft):
    issued = services.issue(draft)
    assert tasks.send_invoice.delay(issued.pk).get() == "no_admins"
    assert mail.outbox == []


def test_nothing_is_sent_when_etqans_email_is_off(draft, head):
    from etqan.integrations.models import PlatformAccount  # noqa: PLC0415

    PlatformAccount.objects.filter(service="email").update(enabled=False)
    issued = services.issue(draft)
    assert tasks.send_invoice.delay(issued.pk).get() == "not_set_up"
    assert EtqanInvoice.objects.get(pk=issued.pk).emailed_at is None


def test_the_hourly_task_issues_due_drafts_and_emails_them(draft, head, at):
    at("2026-10-02 03:00")
    assert tasks.issue_due.delay().get() == [draft.pk]
    draft.refresh_from_db()
    assert draft.status == "issued"
    assert [message.to for message in mail.outbox] == [["head@noor.test"]]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/etqan_billing/tests/test_tasks.py -q`
Expected: FAIL at collection with `ImportError: cannot import name 'tasks' from 'etqan.etqan_billing'`.

- [ ] **Step 3: Write the tasks**

`backend/etqan/etqan_billing/tasks.py`:

```python
"""Etqan billing's background work (spec §5): the 1st-of-month drafts,
issuing drafts past their 24 hours, and emailing each issued invoice's PDF
to the academy's admins from Etqan (plan D13, D14)."""

import logging

from celery import shared_task
from django.conf import settings
from django_tenants.utils import get_public_schema_name
from django_tenants.utils import schema_context

from etqan.etqan_billing import clock
from etqan.etqan_billing import pdf
from etqan.etqan_billing import services
from etqan.etqan_billing.models import EtqanInvoice
from etqan.identity import services as identity
from etqan.integrations import services as integrations
from etqan.platform.frontend import app_url
from etqan.platform.tenancy import academy_context

logger = logging.getLogger(__name__)
BUILD = "etqan_billing.build_month"
ISSUE = "etqan_billing.issue_due"
SEND = "etqan_billing.send_invoice"
BILLING_PATH = "/settings/etqan-billing"


@shared_task(name=BUILD)
def build_month() -> dict[str, str]:
    """On the 1st at 03:00 UTC: drafts for the month before."""
    return services.build_month()


@shared_task(name=ISSUE)
def issue_due() -> list[int]:
    """Hourly: drafts past their 24 hours are issued, then emailed."""
    issued = services.issue_due()
    for invoice_id in issued:
        send_invoice.delay(invoice_id)
    return issued


def _message(invoice: EtqanInvoice, link: str) -> tuple[str, str]:
    month = f"{invoice.period:%B %Y}"
    subject = f"[Etqan] Invoice {invoice.number} for {month}"
    body = (
        "Hello,\n\n"
        f"Etqan's invoice {invoice.number} for {month} is attached: "
        f"{services.money(invoice.total, invoice.currency)}, "
        f"due by {invoice.due_at:%d %B %Y}.\n\n"
        "It covers your academy's use of Etqan's default accounts (email, "
        "WhatsApp, video meetings, AI). Your use this month and your past "
        f"invoices are in Settings → Etqan billing:\n{link}\n\n"
        f"{settings.ETQAN_BILLING_PAYMENT_INSTRUCTIONS}\n\n"
        "— Etqan"
    )
    return subject, body


@shared_task(
    name=SEND,
    autoretry_for=(OSError,),
    retry_backoff=True,
    retry_kwargs={"max_retries": 3},
)
def send_invoice(invoice_id: int) -> str:
    """Email an issued invoice's PDF to its academy's active admins (plan
    D14). It is Etqan's mail: sent from the public schema, so it goes out on
    Etqan's default account, never the academy's own, and is never metered.
    Returns ``sent``, ``not_issued``, ``no_admins`` or ``not_set_up``; an
    SMTP error (``OSError``) retries with backoff."""
    invoice = EtqanInvoice.objects.select_related("academy").get(pk=invoice_id)
    if invoice.issued_at is None:
        return "not_issued"
    with academy_context(invoice.academy.schema_name):
        to = [admin.email for admin in identity.active_admins() if admin.email]
        link = app_url(BILLING_PATH)
    if not to:
        logger.warning(
            "Etqan invoice %s not emailed: %s has no active admin",
            invoice.number,
            invoice.academy.schema_name,
        )
        return "no_admins"
    subject, body = _message(invoice, link)
    with schema_context(get_public_schema_name()):
        try:
            integrations.send_email_now(
                subject=subject,
                body=body,
                from_email=settings.DEFAULT_FROM_EMAIL,
                to=to,
                attachments=[(pdf.filename(invoice), pdf.render(invoice), pdf.PDF_TYPE)],
            )
        except integrations.NotSetUpError:
            logger.warning(
                "Etqan invoice %s not emailed: Etqan's email is off", invoice.number
            )
            return "not_set_up"
    EtqanInvoice.objects.filter(pk=invoice.pk).update(emailed_at=clock.now())
    return "sent"
```

In `backend/config/settings/base.py`, add at the end of the `CELERY_BEAT_SCHEDULE` dict (after its last entry, before the closing `}`):

```python
    # Integrations slice 2 (spec 2026-10-07 §5; not a phase): on the 1st at
    # 03:00 UTC, drafts of Etqan's invoices for the month before; hourly,
    # drafts past their 24 hours are issued and emailed.
    "etqan_billing.build_month": {
        "task": "etqan_billing.build_month",
        "schedule": crontab(day_of_month=1, hour=3, minute=0),
    },
    "etqan_billing.issue_due": {
        "task": "etqan_billing.issue_due",
        "schedule": crontab(minute=10),
    },
```

In `backend/pyproject.toml`, in the `"etqan_billing reaches identity and integrations only through their services"` contract (Task 1), add after its `allow_indirect_imports = true` line (the tests read other apps' rows to set up and check):

```toml
ignore_imports = ["etqan.etqan_billing.tests.** -> etqan.**"]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `$DJ pytest etqan/etqan_billing -q`
Expected: PASS.

Run: `$DJ lint-imports`
Expected: every contract `KEPT` (`tasks` reaches identity and integrations only through their services).

- [ ] **Step 5: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/etqan_billing config/settings/base.py pyproject.toml
git -C backend commit -m "feat(etqan_billing): monthly and hourly jobs; email the invoice PDF from Etqan" -m "$TRAILER"
```

---

### Task 7: The academy API, the route table and the Integrations card's price

**Files:**
- Create: `backend/etqan/etqan_billing/api/__init__.py`, `backend/etqan/etqan_billing/api/payloads.py`, `backend/etqan/etqan_billing/api/views.py`, `backend/etqan/etqan_billing/api/urls.py`, `backend/etqan/etqan_billing/tests/test_api.py`
- Modify: `backend/config/api_router.py`, `backend/etqan/access/tests/test_routes.py`, `backend/etqan/integrations/api/payloads.py`, `backend/etqan/integrations/tests/test_api.py`

**Interfaces:**
- Consumes: Task 3's `month_usage`, `current_prices`; Task 4's `academy_invoices`, `academy_invoice`, `is_overdue`; Task 5's `pdf.render`, `pdf.filename`, `pdf.PDF_TYPE`; `etqan.platform.permissions.HasCode` (empty `permission_codes` = admins only).
- Produces: `GET /api/v1/etqan-billing/usage/` → `{"month": "2026-10", "currency": "USD", "usage": [{"service", "unit", "quantity", "free", "amount", "days": [{"date": "2026-10-01", "quantity"}]}]}`; `GET /api/v1/etqan-billing/invoices/` → `{"invoices": [{"id", "number", "period": "2026-09", "status": "issued|paid|void", "total", "currency", "issued_at", "due_at", "paid_on", "overdue"}]}`; `GET /api/v1/etqan-billing/invoices/<id>/pdf/` → `application/pdf` attachment. The Integrations card gains `"default_prices": [{"unit", "per", "amount", "currency", "free"}]`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/etqan_billing/tests/test_api.py`:

```python
"""Spec §6: Settings → Etqan billing, admins only (plan D17): this month's
use, the academy's issued invoices and their PDFs, never another
academy's (Review Focus 1)."""

import pytest

from etqan.etqan_billing import services
from etqan.etqan_billing.tests.conftest import SEPT
from etqan.etqan_billing.tests.conftest import usage

pytestmark = pytest.mark.django_db
URL = "/api/v1/etqan-billing/"


def test_the_admin_reads_this_months_usage(api_for, tenants, priced, at):
    at("2026-10-15 10:00")
    usage(tenants.main, "2026-10-01 08:00", quantity=1200)
    assert api_for("admin").get(f"{URL}usage/").json() == {
        "month": "2026-10",
        "currency": "USD",
        "usage": [
            {
                "service": "email",
                "unit": "email",
                "quantity": 1200,
                "free": 0,
                "amount": 120,
                "days": [{"date": "2026-10-01", "quantity": 1200}],
            }
        ],
    }


def test_the_admin_lists_issued_invoices_never_drafts(api_for, draft, at):
    client = api_for("admin")
    assert client.get(f"{URL}invoices/").json() == {"invoices": []}
    services.issue(draft)
    (item,) = client.get(f"{URL}invoices/").json()["invoices"]
    assert item == {
        "id": draft.pk,
        "number": "ETQ-2026-09-0001",
        "period": "2026-09",
        "status": "issued",
        "total": 250,
        "currency": "USD",
        "issued_at": "2026-10-01T03:00:00Z",
        "due_at": "2026-10-16T03:00:00Z",
        "paid_on": None,
        "overdue": False,
    }
    at("2026-10-16 03:00")
    assert client.get(f"{URL}invoices/").json()["invoices"][0]["overdue"] is True


def test_the_pdf_downloads(api_for, draft):
    issued = services.issue(draft)
    resp = api_for("admin").get(f"{URL}invoices/{issued.pk}/pdf/")
    assert resp.status_code == 200
    assert resp["Content-Type"] == "application/pdf"
    assert resp["Content-Disposition"] == 'attachment; filename="ETQ-2026-09-0001.pdf"'
    assert resp.content.startswith(b"%PDF-")


def test_a_drafts_pdf_is_a_404(api_for, draft):
    assert api_for("admin").get(f"{URL}invoices/{draft.pk}/pdf/").status_code == 404


def test_another_academys_invoice_is_a_404(api_for, tenants, priced, at):
    usage(tenants.other, quantity=10)
    at("2026-10-01 03:00")
    theirs = services.issue(services.create_draft(tenants.other, SEPT))
    client = api_for("admin")
    assert client.get(f"{URL}invoices/").json() == {"invoices": []}
    assert client.get(f"{URL}invoices/{theirs.pk}/pdf/").status_code == 404


def test_teachers_and_parents_never_see_etqan_billing(api_for):
    for role in ("teacher", "parent"):
        client = api_for(role)
        assert client.get(f"{URL}invoices/").status_code == 403
        assert client.get(f"{URL}usage/").status_code == 403
```

In `backend/etqan/integrations/tests/test_api.py`, add the imports

```python
from datetime import date

from etqan.etqan_billing.models import AcademyPricing
from etqan.etqan_billing.models import Price
```

add `"default_prices": [],` as the last key of both expected cards in `test_the_admin_reads_one_card_per_service_in_order` (after `"own": None,`), and add at the end:

```python
def test_the_card_shows_etqans_price_for_the_academy(api_for, tenants):
    Price.objects.create(
        service="email", unit="email", amount=100, effective_from=date(2026, 1, 1)
    )
    AcademyPricing.objects.create(
        academy=tenants.main, service="email", unit="email", free_allowance=1000
    )
    card = api_for("admin").get(URL).json()["services"][1]
    assert card["default_prices"] == [
        {"unit": "email", "per": 1000, "amount": 100, "currency": "USD", "free": 1000}
    ]
```

In `backend/etqan/access/tests/test_routes.py`, add at the end of the `ADMIN_ONLY` list (before its closing `]`):

```python
    # Integrations slice 2 (spec 2026-10-07 §6; not a phase): Settings →
    # Etqan billing, admins only (plan D17).
    ("GET", "/api/v1/etqan-billing/usage/"),
    ("GET", "/api/v1/etqan-billing/invoices/"),
    ("GET", f"/api/v1/etqan-billing/invoices/{N}/pdf/"),
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/etqan_billing/tests/test_api.py etqan/integrations/tests/test_api.py etqan/access/tests/test_routes.py -q`
Expected: FAIL — the billing routes are 404, the cards have no `default_prices`, and `test_every_route_declares_its_code_or_is_named_exempt` fails on the three tabled paths no view serves.

- [ ] **Step 3: Write the API**

Create `backend/etqan/etqan_billing/api/__init__.py` empty.

`backend/etqan/etqan_billing/api/payloads.py`:

```python
"""JSON shapes for Settings → Etqan billing (spec §6, plan D17)."""

from etqan.etqan_billing import services
from etqan.etqan_billing.models import EtqanInvoice


def usage(month: dict) -> dict:
    return {
        "month": f"{month['month']:%Y-%m}",
        "currency": month["currency"],
        "usage": month["usage"],
    }


def invoice(item: EtqanInvoice) -> dict:
    return {
        "id": item.pk,
        "number": item.number,
        "period": f"{item.period:%Y-%m}",
        "status": item.status,
        "total": item.total,
        "currency": item.currency,
        "issued_at": item.issued_at,
        "due_at": item.due_at,
        "paid_on": item.paid_on,
        "overdue": services.is_overdue(item),
    }


def invoices(items: list[EtqanInvoice]) -> dict:
    return {"invoices": [invoice(item) for item in items]}
```

`backend/etqan/etqan_billing/api/views.py`:

```python
"""Settings → Etqan billing (spec §6). Admins only: the views declare no
staff code (plan D17), as `academy/features/` does."""

from django.http import HttpResponse
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.etqan_billing import pdf
from etqan.etqan_billing import services
from etqan.etqan_billing.api import payloads
from etqan.platform.permissions import HasCode


class UsageView(APIView):
    """This UTC month's use of Etqan's defaults, per service and day."""

    permission_classes = [HasCode]
    permission_codes: dict = {}

    def get(self, request):
        return Response(payloads.usage(services.month_usage()))


class InvoiceListView(APIView):
    """Every invoice Etqan has issued to the academy, newest month first."""

    permission_classes = [HasCode]
    permission_codes: dict = {}

    def get(self, request):
        return Response(payloads.invoices(services.academy_invoices()))


class InvoicePdfView(APIView):
    permission_classes = [HasCode]
    permission_codes: dict = {}

    def get(self, request, invoice_id: int):
        invoice = services.academy_invoice(invoice_id)
        response = HttpResponse(pdf.render(invoice), content_type=pdf.PDF_TYPE)
        response["Content-Disposition"] = (
            f'attachment; filename="{pdf.filename(invoice)}"'
        )
        return response
```

`backend/etqan/etqan_billing/api/urls.py`:

```python
from django.urls import path

from etqan.etqan_billing.api import views

app_name = "etqan_billing"
urlpatterns = [
    path("usage/", views.UsageView.as_view(), name="usage"),
    path("invoices/", views.InvoiceListView.as_view(), name="invoices"),
    path(
        "invoices/<int:invoice_id>/pdf/",
        views.InvoicePdfView.as_view(),
        name="invoice-pdf",
    ),
]
```

In `backend/config/api_router.py`, replace

```python
    # Integrations (spec 2026-10-07; not a phase): the academy's accounts
    # with outside services.
    path("integrations/", include("etqan.integrations.api.urls")),
```

with

```python
    # Integrations (spec 2026-10-07; not a phase): the academy's accounts
    # with outside services, and Etqan's invoices for using its defaults.
    path("integrations/", include("etqan.integrations.api.urls")),
    path("etqan-billing/", include("etqan.etqan_billing.api.urls")),
```

- [ ] **Step 4: Show the default's price on the Integrations card**

In `backend/etqan/integrations/api/payloads.py`, replace

```python
from etqan.integrations import services
```

with

```python
from etqan.etqan_billing import services as billing
from etqan.integrations import services
```

and in `card`, replace

```python
        "own": _own(services.own_account(service)),
    }
```

with

```python
        "own": _own(services.own_account(service)),
        # Slice 2 plan D18: Etqan's price for this academy, per unit.
        "default_prices": billing.current_prices(service),
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `$DJ pytest etqan/etqan_billing etqan/integrations etqan/access -q`
Expected: PASS.

Run: `$DJ lint-imports`
Expected: every contract `KEPT`.

- [ ] **Step 6: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/etqan_billing etqan/integrations etqan/access/tests/test_routes.py config/api_router.py
git -C backend commit -m "feat(etqan_billing): Settings → Etqan billing API; default prices on the Integrations card" -m "$TRAILER"
```

---

### Task 8: The platform admin — prices, academy terms, Connect fee, usage, invoices

**Files:**
- Create: `backend/etqan/etqan_billing/admin.py`, `backend/etqan/etqan_billing/tests/test_admin.py`

**Interfaces:**
- Consumes: Task 4's `create_draft`, `has_invoice`, `check_line`, `add_line`, `remove_line`, `issue`, `mark_paid`, `void`, `ADDABLE`; Task 3's `UNITS`, `money`, `price_text`; Task 6's `tasks.send_invoice`; `etqan.platform.exceptions.EtqanError`.
- Produces: admin pages under `/admin/etqan_billing/` on the bare base domain: `price/`, `academypricing/`, `connectfee/`, `usageevent/` (read-only), `collectedfee/` (read-only), `etqaninvoice/` (add a draft by hand; actions `issue_invoices`, `mark_paid`, `void_invoices`; lines shown read-only), `etqaninvoiceline/` (add a manual or credit line to a draft; delete a manual or credit line of a draft).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/etqan_billing/tests/test_admin.py`:

```python
"""Spec §6: Etqan's prices, each academy's terms and Connect fee, usage and
invoices in the platform admin (the bare base domain only)."""

from datetime import date

import pytest
from django.core import mail
from django.db import connection
from django_tenants.utils import tenant_context

from etqan.etqan_billing import services
from etqan.etqan_billing.models import AcademyPricing
from etqan.etqan_billing.models import ConnectFee
from etqan.etqan_billing.models import EtqanInvoice
from etqan.etqan_billing.models import Price
from etqan.etqan_billing.tests.conftest import usage
from etqan.identity.models import User

pytestmark = pytest.mark.django_db
PUBLIC_HOST = "etqan.localhost"
A = "/admin/etqan_billing/"


@pytest.fixture
def staff_client(client):
    connection.set_schema_to_public()
    staff = User.objects.create_superuser(
        email="ops@etqan.test", password="pw-12345678"
    )
    client.force_login(staff)
    return client


def get(client, url):
    return client.get(url, HTTP_HOST=PUBLIC_HOST)


def post(client, url, data, *, follow=False):
    return client.post(url, data, HTTP_HOST=PUBLIC_HOST, follow=follow)


def test_the_admin_is_not_served_on_an_academy_host(client):
    assert client.get(f"{A}price/", HTTP_HOST="testserver").status_code == 404


def test_etqan_sets_a_price(staff_client):
    resp = post(
        staff_client,
        f"{A}price/add/",
        {
            "service": "email",
            "unit": "email",
            "amount": "100",
            "effective_from": "2026-11-01",
            "_save": "Save",
        },
    )
    assert resp.status_code == 302, resp.content[:2000]
    price = Price.objects.get()
    assert (price.amount, price.currency) == (100, "USD")
    assert "1.00 USD per 1,000 emails" in get(staff_client, f"{A}price/").content.decode()


def test_a_unit_of_another_service_is_refused(staff_client):
    resp = post(
        staff_client,
        f"{A}price/add/",
        {"service": "email", "unit": "minute", "amount": "1", "effective_from": "2026-11-01"},
    )
    assert resp.status_code == 200
    assert "Email is metered in email." in resp.content.decode()
    assert not Price.objects.exists()


def test_etqan_sets_an_academys_override_and_allowance(staff_client, tenants):
    resp = post(
        staff_client,
        f"{A}academypricing/add/",
        {
            "academy": tenants.main.pk,
            "service": "email",
            "unit": "email",
            "amount": "80",
            "free_allowance": "1000",
            "_save": "Save",
        },
    )
    assert resp.status_code == 302, resp.content[:2000]
    terms = AcademyPricing.objects.get()
    assert (terms.academy_id, terms.amount, terms.free_allowance) == (
        tenants.main.pk,
        80,
        1000,
    )


def test_the_public_schema_is_no_academy_to_price(staff_client, tenants):
    resp = post(
        staff_client,
        f"{A}academypricing/add/",
        {"academy": tenants.public.pk, "service": "email", "unit": "email", "free_allowance": "0"},
    )
    assert resp.status_code == 200
    assert "Select a valid choice" in resp.content.decode()


def test_etqan_sets_an_academys_connect_fee(staff_client, tenants):
    data = {
        "academy": tenants.main.pk,
        "percent_bp": "10001",
        "fixed_amount": "30",
        "currency": "USD",
        "_save": "Save",
    }
    assert post(staff_client, f"{A}connectfee/add/", data).status_code == 200
    data["percent_bp"] = "250"
    assert post(staff_client, f"{A}connectfee/add/", data).status_code == 302
    fee = ConnectFee.objects.get()
    assert (fee.percent_bp, fee.fixed_amount, fee.currency) == (250, 30, "USD")


def test_usage_is_read_only_and_listed_per_academy(staff_client, tenants):
    usage(tenants.main, quantity=7)
    page = get(staff_client, f"{A}usageevent/?academy__id__exact={tenants.main.pk}")
    assert page.status_code == 200
    assert tenants.main.name in page.content.decode()
    assert get(staff_client, f"{A}usageevent/add/").status_code == 403


def test_etqan_issues_a_draft_and_the_pdf_goes_to_the_admins(
    draft, staff_client, tenants, django_capture_on_commit_callbacks
):
    with tenant_context(tenants.main):
        User.objects.create_user(
            email="head@noor.test", password="pw-12345678", full_name="Head", role="admin"
        )
    with django_capture_on_commit_callbacks(execute=True):
        resp = post(
            staff_client,
            f"{A}etqaninvoice/",
            {"action": "issue_invoices", "_selected_action": [draft.pk]},
        )
    assert resp.status_code == 302
    draft.refresh_from_db()
    assert draft.status == "issued"
    assert [message.to for message in mail.outbox] == [["head@noor.test"]]


def test_etqan_marks_an_invoice_paid_with_its_date_method_and_reference(
    draft, staff_client, at
):
    services.issue(draft)
    at("2026-10-10 09:00")
    post(
        staff_client,
        f"{A}etqaninvoice/",
        {
            "action": "mark_paid",
            "_selected_action": [draft.pk],
            "paid_on": "2026-10-09",
            "method": "bank_transfer",
            "reference": "TRX-77",
        },
    )
    draft.refresh_from_db()
    assert (draft.status, draft.paid_on, draft.paid_method, draft.paid_reference) == (
        "paid",
        date(2026, 10, 9),
        "bank_transfer",
        "TRX-77",
    )


def test_a_payment_without_a_date_is_refused(draft, staff_client):
    services.issue(draft)
    resp = post(
        staff_client,
        f"{A}etqaninvoice/",
        {"action": "mark_paid", "_selected_action": [draft.pk], "method": "cash"},
        follow=True,
    )
    assert "Enter the day it was paid, not a future one." in resp.content.decode()
    draft.refresh_from_db()
    assert draft.status == "issued"


def test_etqan_voids_an_invoice(draft, staff_client):
    post(
        staff_client,
        f"{A}etqaninvoice/",
        {"action": "void_invoices", "_selected_action": [draft.pk], "reason": "Duplicate"},
    )
    draft.refresh_from_db()
    assert (draft.status, draft.void_reason) == ("void", "Duplicate")


def test_etqan_adds_a_credit_line_to_a_draft(draft, staff_client):
    resp = post(
        staff_client,
        f"{A}etqaninvoiceline/add/",
        {
            "invoice": draft.pk,
            "kind": "credit",
            "description": "Correction to ETQ-2026-08-0004",
            "amount": "100",
            "_save": "Save",
        },
    )
    assert resp.status_code == 302, resp.content[:2000]
    draft.refresh_from_db()
    assert draft.total == 150


def test_a_line_on_an_issued_invoice_is_refused(draft, staff_client):
    services.issue(draft)
    resp = post(
        staff_client,
        f"{A}etqaninvoiceline/add/",
        {"invoice": draft.pk, "kind": "manual", "description": "Setup", "amount": "100"},
    )
    assert resp.status_code == 200
    assert "Select a valid choice" in resp.content.decode()
    assert draft.lines.count() == 1


def test_a_credit_below_zero_is_refused_on_the_form(draft, staff_client):
    resp = post(
        staff_client,
        f"{A}etqaninvoiceline/add/",
        {"invoice": draft.pk, "kind": "credit", "description": "Too much", "amount": "300"},
    )
    assert resp.status_code == 200
    assert "A credit cannot take the invoice below zero." in resp.content.decode()


def test_etqan_removes_a_manual_line_but_never_a_usage_line(draft, staff_client):
    manual = services.add_line(draft, kind="manual", description="Setup", amount=10)
    usage_line = draft.lines.get(kind="usage")
    assert (
        get(staff_client, f"{A}etqaninvoiceline/{usage_line.pk}/delete/").status_code
        == 403
    )
    resp = post(staff_client, f"{A}etqaninvoiceline/{manual.pk}/delete/", {"post": "yes"})
    assert resp.status_code == 302
    draft.refresh_from_db()
    assert (draft.total, draft.lines.count()) == (250, 1)


def test_etqan_drafts_an_invoice_by_hand_for_a_month(staff_client, tenants, at):
    at("2026-11-02 10:00")
    resp = post(
        staff_client,
        f"{A}etqaninvoice/add/",
        {"academy": tenants.main.pk, "period": "2026-10-15", "_save": "Save"},
    )
    assert resp.status_code == 302, resp.content[:2000]
    invoice = EtqanInvoice.objects.get()
    assert (invoice.period, invoice.number, invoice.status, invoice.total) == (
        date(2026, 10, 1),
        "ETQ-2026-10-0001",
        "draft",
        0,
    )


def test_a_second_invoice_for_a_month_is_refused_on_the_form(draft, staff_client, tenants):
    resp = post(
        staff_client,
        f"{A}etqaninvoice/add/",
        {"academy": tenants.main.pk, "period": "2026-09-03"},
    )
    assert resp.status_code == 200
    assert "This academy already has an invoice for that month." in resp.content.decode()
    assert EtqanInvoice.objects.count() == 1


def test_the_invoice_page_shows_its_lines_and_edits_nothing(draft, staff_client):
    services.issue(draft)
    page = get(staff_client, f"{A}etqaninvoice/{draft.pk}/change/").content.decode()
    assert "ETQ-2026-09-0001" in page
    assert "Emails" in page
    assert "2.50 USD" in page
    assert 'name="number"' not in page
    assert "Issued invoices never change" in page
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/etqan_billing/tests/test_admin.py -q`
Expected: FAIL — the admin pages are not registered (`404` where `302` or `200` is expected).

- [ ] **Step 3: Write the admin**

`backend/etqan/etqan_billing/admin.py`:

```python
"""Spec §6: Etqan's prices, each academy's terms and Connect fee, usage and
invoices, in the platform admin (the bare base domain only:
`config/urls_public.py`). Every change to an invoice goes through
`etqan_billing.services`; an issued invoice is read-only (plan D11, D12)."""

from functools import partial

from django import forms
from django.contrib import admin
from django.contrib import messages
from django.contrib.admin.helpers import ActionForm
from django.db import transaction
from django.urls import reverse
from django.utils.html import format_html
from django_tenants.utils import get_public_schema_name
from django_tenants.utils import get_tenant_model

from etqan.etqan_billing import services
from etqan.etqan_billing import tasks
from etqan.etqan_billing.models import AcademyPricing
from etqan.etqan_billing.models import CollectedFee
from etqan.etqan_billing.models import ConnectFee
from etqan.etqan_billing.models import EtqanInvoice
from etqan.etqan_billing.models import EtqanInvoiceLine
from etqan.etqan_billing.models import Metered
from etqan.etqan_billing.models import Price
from etqan.etqan_billing.models import UsageEvent
from etqan.platform.exceptions import EtqanError

Status = EtqanInvoice.Status


def _academies():
    return get_tenant_model().objects.exclude(schema_name=get_public_schema_name())


def _check_unit(form: forms.ModelForm) -> None:
    """A price or a term names one of the service's own units."""
    service = form.cleaned_data.get("service")
    unit = form.cleaned_data.get("unit")
    units = services.UNITS.get(service, ())
    if service and unit and unit not in units:
        form.add_error(
            "unit", f"{Metered(service).label} is metered in {', '.join(units)}."
        )


class PriceForm(forms.ModelForm):
    class Meta:
        model = Price
        fields = ["service", "unit", "amount", "effective_from"]

    def clean(self):
        cleaned = super().clean()
        _check_unit(self)
        return cleaned


@admin.register(Price)
class PriceAdmin(admin.ModelAdmin):
    form = PriceForm
    list_display = ["service", "unit", "price", "effective_from"]
    list_filter = ["service", "unit"]

    @admin.display(description="Price")
    def price(self, obj) -> str:
        return services.price_text(obj.amount, obj.currency, obj.unit)


class AcademyPricingForm(forms.ModelForm):
    class Meta:
        model = AcademyPricing
        fields = ["academy", "service", "unit", "amount", "free_allowance"]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["academy"].queryset = _academies()

    def clean(self):
        cleaned = super().clean()
        _check_unit(self)
        return cleaned


@admin.register(AcademyPricing)
class AcademyPricingAdmin(admin.ModelAdmin):
    form = AcademyPricingForm
    list_display = ["academy", "service", "unit", "amount", "free_allowance"]
    list_filter = ["service", "academy"]


class ConnectFeeForm(forms.ModelForm):
    class Meta:
        model = ConnectFee
        fields = ["academy", "percent_bp", "fixed_amount", "currency"]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["academy"].queryset = _academies()

    def clean_currency(self) -> str:
        return self.cleaned_data["currency"].upper()


@admin.register(ConnectFee)
class ConnectFeeAdmin(admin.ModelAdmin):
    form = ConnectFeeForm
    list_display = ["academy", "percent_bp", "fixed_amount", "currency"]


class ReadOnlyAdmin(admin.ModelAdmin):
    """Rows the providers write; Etqan only reads them."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(UsageEvent)
class UsageEventAdmin(ReadOnlyAdmin):
    list_display = ["academy", "service", "unit", "quantity", "occurred_at", "source_ref"]
    list_filter = ["service", "unit", "academy"]
    date_hierarchy = "occurred_at"


@admin.register(CollectedFee)
class CollectedFeeAdmin(ReadOnlyAdmin):
    list_display = ["academy", "amount", "currency", "occurred_at", "source_ref"]
    list_filter = ["academy", "currency"]
    date_hierarchy = "occurred_at"


class InvoiceActionForm(ActionForm):
    """The changelist's action bar: a payment's details, a void's reason."""

    paid_on = forms.DateField(required=False, label="Paid on")
    method = forms.ChoiceField(
        required=False,
        choices=[("", "—"), *EtqanInvoice.PaidMethod.choices],
        label="Method",
    )
    reference = forms.CharField(required=False, max_length=100, label="Reference")
    reason = forms.CharField(required=False, max_length=200, label="Void reason")


class NewInvoiceForm(forms.ModelForm):
    """Plan D12: a draft for any month, by hand."""

    class Meta:
        model = EtqanInvoice
        fields = ["academy", "period"]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["academy"].queryset = _academies()
        self.fields["period"].help_text = (
            "Any day of the month: the invoice covers that calendar month (UTC)."
        )

    def clean(self):
        cleaned = super().clean()
        academy, period = cleaned.get("academy"), cleaned.get("period")
        if academy and period:
            cleaned["period"] = period.replace(day=1)
            if services.has_invoice(academy, period):
                self.add_error(
                    "period", "This academy already has an invoice for that month."
                )
        return cleaned


class LineInline(admin.TabularInline):
    model = EtqanInvoiceLine
    fields = [
        "kind",
        "description",
        "quantity",
        "free_quantity",
        "unit_amount",
        "per",
        "amount_shown",
    ]
    readonly_fields = fields
    extra = 0
    can_delete = False

    def has_add_permission(self, request, obj=None):
        return False

    @admin.display(description="Amount")
    def amount_shown(self, obj) -> str:
        return services.money(obj.amount, obj.currency)


INVOICE_FIELDS = [
    "number",
    "academy",
    "period",
    "status",
    "total_shown",
    "lines_note",
    "draft_until",
    "issued_at",
    "due_at",
    "emailed_at",
    "paid_on",
    "paid_method",
    "paid_reference",
    "voided_at",
    "void_reason",
]


@admin.register(EtqanInvoice)
class EtqanInvoiceAdmin(admin.ModelAdmin):
    list_display = [
        "number",
        "academy",
        "period",
        "status",
        "total_shown",
        "draft_until",
        "due_at",
        "paid_on",
    ]
    list_filter = ["status", "period", "academy"]
    search_fields = ["number"]
    actions = ["issue_invoices", "mark_paid", "void_invoices"]
    action_form = InvoiceActionForm
    inlines = [LineInline]

    def has_delete_permission(self, request, obj=None):
        return False

    def get_form(self, request, obj=None, change=False, **kwargs):
        if obj is None:
            kwargs["form"] = NewInvoiceForm
        return super().get_form(request, obj, change=change, **kwargs)

    def get_fields(self, request, obj=None):
        return ["academy", "period"] if obj is None else INVOICE_FIELDS

    def get_readonly_fields(self, request, obj=None):
        return [] if obj is None else INVOICE_FIELDS

    def get_inline_instances(self, request, obj=None):
        return [] if obj is None else super().get_inline_instances(request, obj)

    def save_model(self, request, obj, form, change):
        if change:
            return
        created = services.create_draft(
            form.cleaned_data["academy"], form.cleaned_data["period"]
        )
        obj.pk = created.pk
        obj.number = created.number

    @admin.display(description="Total")
    def total_shown(self, obj) -> str:
        return services.money(obj.total, obj.currency)

    @admin.display(description="Lines")
    def lines_note(self, obj) -> str:
        if obj.status != Status.DRAFT:
            return (
                "Issued invoices never change; correct one with a credit line "
                "on the next invoice."
            )
        url = reverse("admin:etqan_billing_etqaninvoiceline_add")
        return format_html(
            '<a href="{}?invoice={}">Add a manual or credit line</a>', url, obj.pk
        )

    def _each(self, request, queryset, change, done: str) -> None:
        for invoice in queryset.order_by("number"):
            try:
                change(invoice)
            except EtqanError as exc:
                # A leading "· " absorbs the admin's capfirst (slice 1's
                # convention), so an invoice number keeps its case.
                self.message_user(
                    request, f"· {invoice.number}: {exc.message}", messages.ERROR
                )
            else:
                self.message_user(
                    request, f"· {invoice.number}: {done}", messages.SUCCESS
                )

    @admin.action(description="Issue the selected drafts now (and email them)")
    def issue_invoices(self, request, queryset):
        def issue_and_send(invoice):
            issued = services.issue(invoice)
            transaction.on_commit(partial(tasks.send_invoice.delay, issued.pk))

        self._each(
            request, queryset, issue_and_send, "issued; the PDF goes to its admins."
        )

    @admin.action(description="Mark the selected invoices paid (date, method above)")
    def mark_paid(self, request, queryset):
        form = InvoiceActionForm(request.POST)
        form.is_valid()
        data = form.cleaned_data
        self._each(
            request,
            queryset,
            lambda invoice: services.mark_paid(
                invoice,
                paid_on=data.get("paid_on"),
                method=data.get("method") or "",
                reference=data.get("reference") or "",
            ),
            "marked paid.",
        )

    @admin.action(description="Void the selected invoices (reason above)")
    def void_invoices(self, request, queryset):
        form = InvoiceActionForm(request.POST)
        form.is_valid()
        reason = form.cleaned_data.get("reason") or ""
        self._each(
            request,
            queryset,
            lambda invoice: services.void(invoice, reason=reason),
            "voided.",
        )


class NewLineForm(forms.ModelForm):
    """Plan D12: a manual charge or a credit on a draft."""

    kind = forms.ChoiceField(
        choices=[
            (kind.value, kind.label)
            for kind in EtqanInvoiceLine.Kind
            if kind in services.ADDABLE
        ]
    )
    amount = forms.IntegerField(
        min_value=1,
        help_text=(
            "Minor units of Etqan's currency: 1250 = 12.50. A credit is "
            "entered positive and subtracts."
        ),
    )

    class Meta:
        model = EtqanInvoiceLine
        fields = ["invoice", "kind", "description", "amount"]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["invoice"].queryset = EtqanInvoice.objects.filter(
            status=Status.DRAFT
        )

    def clean(self):
        cleaned = super().clean()
        if self.errors:
            return cleaned
        try:
            services.check_line(
                cleaned["invoice"],
                kind=cleaned["kind"],
                description=cleaned["description"],
                amount=cleaned["amount"],
            )
        except EtqanError as exc:
            self.add_error(getattr(exc, "field", None), exc.message)
        return cleaned


@admin.register(EtqanInvoiceLine)
class EtqanInvoiceLineAdmin(admin.ModelAdmin):
    form = NewLineForm
    list_display = ["invoice", "kind", "description", "amount", "currency"]
    list_filter = ["kind"]

    def get_actions(self, request):
        actions = super().get_actions(request)
        actions.pop("delete_selected", None)
        return actions

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        if obj is None:
            return True
        return obj.kind in services.ADDABLE and obj.invoice.status == Status.DRAFT

    def save_model(self, request, obj, form, change):
        created = services.add_line(
            form.cleaned_data["invoice"],
            kind=form.cleaned_data["kind"],
            description=form.cleaned_data["description"],
            amount=form.cleaned_data["amount"],
        )
        obj.pk = created.pk

    def delete_model(self, request, obj):
        try:
            services.remove_line(obj)
        except EtqanError as exc:
            self.message_user(request, f"· {exc.message}", messages.ERROR)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `$DJ pytest etqan/etqan_billing -q`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/etqan_billing
git -C backend commit -m "feat(etqan_billing): platform admin for prices, terms, Connect fee, usage and invoices" -m "$TRAILER"
```

---

### Task 9: The "suspend Etqan's defaults" switch on the Academy page

**Files:**
- Create: `backend/etqan/tenants/tests/test_admin_suspend.py`
- Modify: `backend/etqan/tenants/admin.py`, `backend/pyproject.toml`

**Interfaces:**
- Consumes: slice 1's `Academy.etqan_defaults_suspended` (read by the resolver, slice 1 D2); Task 4's `may_suspend(academy)`, `oldest_unpaid_days(academy)`, `SUSPEND_DAYS`.
- Produces: the checkbox "Suspend Etqan's defaults" on `/admin/tenants/academy/<id>/change/`, refused before 30 days unpaid (plan D16).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/tenants/tests/test_admin_suspend.py`:

```python
"""Spec §5, plan D16: from 30 days after an unpaid invoice's issue, Etqan
may suspend an academy's use of Etqan's default accounts; never sooner,
never automatically; lifting it is always allowed."""

from datetime import date
from datetime import timedelta

import pytest
from django import forms
from django.db import connection
from django.utils import timezone

from etqan.etqan_billing.models import EtqanInvoice
from etqan.identity.models import User
from etqan.tenants.models import Academy

pytestmark = pytest.mark.django_db
PUBLIC_HOST = "etqan.localhost"


@pytest.fixture
def staff_client(client):
    connection.set_schema_to_public()
    staff = User.objects.create_superuser(
        email="ops5@etqan.test", password="pw-12345678"
    )
    client.force_login(staff)
    return client


def change_url(academy) -> str:
    return f"/admin/tenants/academy/{academy.pk}/change/"


def submitted(resp) -> dict:
    """The change form's data as the page would post it (an unchecked box
    is left out), with the domains' inline as it came."""
    form = resp.context["adminform"].form
    data = {}
    for name, field in form.fields.items():
        value = form[name].value()
        if isinstance(field, forms.BooleanField):
            if value:
                data[name] = "on"
        elif value is not None:
            data[name] = value
    for inline in resp.context["inline_admin_formsets"]:
        formset = inline.formset
        for name in formset.management_form.fields:
            data[f"{formset.prefix}-{name}"] = formset.management_form[name].value()
        for row in formset.forms:
            for name in row.fields:
                if (value := row[name].value()) is not None:
                    data[row.add_prefix(name)] = value
    return data


def unpaid(academy, days_ago: int, *, total: int = 250) -> EtqanInvoice:
    issued_at = timezone.now() - timedelta(days=days_ago, minutes=1)
    return EtqanInvoice.objects.create(
        academy=academy,
        period=date(2026, 9, 1),
        number=f"ETQ-TEST-{days_ago:04d}",
        status="issued",
        total=total,
        draft_until=issued_at,
        issued_at=issued_at,
        due_at=issued_at + timedelta(days=15),
    )


def switch(client, academy, *, on: bool):
    page = client.get(change_url(academy), HTTP_HOST=PUBLIC_HOST)
    data = submitted(page)
    data.pop("etqan_defaults_suspended", None)
    if on:
        data["etqan_defaults_suspended"] = "on"
    data["_save"] = "Save"
    return client.post(change_url(academy), data, HTTP_HOST=PUBLIC_HOST)


def suspended(academy) -> bool:
    return Academy.objects.get(pk=academy.pk).etqan_defaults_suspended


def test_etqan_suspends_an_academys_defaults_from_30_days_unpaid(staff_client, tenants):
    unpaid(tenants.main, 31)
    page = staff_client.get(change_url(tenants.main), HTTP_HOST=PUBLIC_HOST)
    assert "Oldest unpaid Etqan invoice: issued 31 days ago." in page.content.decode()
    assert switch(staff_client, tenants.main, on=True).status_code == 302
    assert suspended(tenants.main)


def test_suspending_before_30_days_is_refused(staff_client, tenants):
    unpaid(tenants.main, 20)
    resp = switch(staff_client, tenants.main, on=True)
    assert resp.status_code == 200
    assert (
        "Etqan&#x27;s defaults may be suspended only once an Etqan invoice is "
        "unpaid 30 days after issue." in resp.content.decode()
    )
    assert not suspended(tenants.main)


def test_a_zero_invoice_never_allows_suspending(staff_client, tenants):
    unpaid(tenants.main, 40, total=0)
    page = staff_client.get(change_url(tenants.main), HTTP_HOST=PUBLIC_HOST)
    assert "No unpaid Etqan invoice." in page.content.decode()
    assert switch(staff_client, tenants.main, on=True).status_code == 200
    assert not suspended(tenants.main)


def test_lifting_a_suspension_is_always_allowed(staff_client, tenants):
    Academy.objects.filter(pk=tenants.main.pk).update(etqan_defaults_suspended=True)
    assert switch(staff_client, tenants.main, on=False).status_code == 302
    assert not suspended(tenants.main)
```

In `backend/pyproject.toml`, in the `"other apps reach etqan_billing only through its services"` contract, replace

```toml
ignore_imports = ["etqan.integrations.tests.** -> etqan.etqan_billing.**"]
```

with

```toml
ignore_imports = [
    "etqan.integrations.tests.** -> etqan.etqan_billing.**",
    "etqan.tenants.tests.** -> etqan.etqan_billing.**",
]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/tenants/tests/test_admin_suspend.py -q`
Expected: FAIL — the page has no "Oldest unpaid Etqan invoice" text, and posting the box is ignored (the form does not have the field), so the academy is never suspended.

- [ ] **Step 3: Add the switch to the Academy change form**

In `backend/etqan/tenants/admin.py`, add the import (with the other `etqan` imports):

```python
from etqan.etqan_billing import services as etqan_billing
```

Add `"etqan_defaults_suspended"` to `ACADEMY_FIELDS` directly after `"plan_notes"`:

```python
ACADEMY_FIELDS = [
    "name",
    "subdomain",
    "schema_name",
    "status",
    "timezone",
    "currency",
    "plan_label",
    "plan_notes",
    "etqan_defaults_suspended",
    "created_at",
]
```

Directly after `FEATURES_NOTE = (…)` add:

```python
# Integrations slice 2 (spec 2026-10-07 §5, plan D16).
SUSPEND_LABEL = "Suspend Etqan's defaults"
SUSPEND_HELP = (
    "Stops this academy's use of Etqan's default accounts (email, WhatsApp, "
    "video, AI); its own accounts keep working. Allowed once an Etqan "
    "invoice is unpaid 30 days after issue; never automatic."
)
```

In `_AcademyChangeForm`, replace

```python
    class Meta:
        model = Academy
        fields = ["name", "status", "timezone", "currency", "plan_label", "plan_notes"]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        stored = self.instance.features
```

with

```python
    class Meta:
        model = Academy
        fields = [
            "name",
            "status",
            "timezone",
            "currency",
            "plan_label",
            "plan_notes",
            "etqan_defaults_suspended",
        ]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        days = etqan_billing.oldest_unpaid_days(self.instance)
        unpaid = (
            "No unpaid Etqan invoice."
            if days is None
            else f"Oldest unpaid Etqan invoice: issued {days} days ago."
        )
        suspend = self.fields["etqan_defaults_suspended"]
        suspend.label = SUSPEND_LABEL
        suspend.help_text = f"{SUSPEND_HELP} {unpaid}"
        stored = self.instance.features
```

and add this method to `_AcademyChangeForm` directly before its `save` method:

```python
    def clean_etqan_defaults_suspended(self) -> bool:
        """Plan D16: switching on needs an invoice 30 days unpaid; lifting a
        suspension is always allowed."""
        value = self.cleaned_data["etqan_defaults_suspended"]
        if (
            value
            and not self.instance.etqan_defaults_suspended
            and not etqan_billing.may_suspend(self.instance)
        ):
            raise forms.ValidationError(
                "Etqan's defaults may be suspended only once an Etqan invoice "
                f"is unpaid {etqan_billing.SUSPEND_DAYS} days after issue."
            )
        return value
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `$DJ pytest etqan/tenants etqan/integrations -q`
Expected: PASS (the existing Academy admin tests post the box unchecked, which keeps the academy as it was).

Run: `$DJ lint-imports`
Expected: every contract `KEPT`.

- [ ] **Step 5: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/tenants pyproject.toml
git -C backend commit -m "feat(tenants): suspend an academy's Etqan defaults from 30 days unpaid" -m "$TRAILER"
```

---

### Task 10: Dashboard data layer, formatting and strings

**Files:**
- Create: `dashboard/src/features/etqanbilling/schemas.ts`, `api.ts`, `queries.ts`, `format.ts`, `index.ts`, `api.test.ts`, `queries.test.tsx`, `format.test.ts`, `dashboard/src/test/etqanbilling-fixtures.ts`, `dashboard/src/locales/en/etqanBilling.json`, `dashboard/src/locales/ar/etqanBilling.json`
- Modify: `dashboard/src/features/integrations/schemas.ts`, `dashboard/src/test/integrations-fixtures.ts`

**Interfaces:**
- Consumes: `api` from `@/lib/api` (base `/api/v1/`), `formatMoney` from `@/lib/money`; Task 7's API shapes.
- Produces: types `Metered`, `Unit`, `InvoiceStatus`, `UsageDay`, `UsageRow`, `MonthUsage`, `EtqanInvoice`, `EtqanInvoices`, `DefaultPrice`; `etqanBillingApi.usage(): Promise<MonthUsage>`, `.invoices(): Promise<EtqanInvoices>`; `invoicePdfUrl(id: number): string`; `etqanBillingKey`, `useMonthUsage()`, `useEtqanInvoices(enabled = true)`; `monthName(period, language)`, `dayName(iso, language)`, `count(n, language)`, `priceText(price, t, language)`; fixtures `monthUsage(overrides)`, `etqanInvoice(overrides)`; `IntegrationCard.default_prices: DefaultPrice[]`; locale area `etqanBilling`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/test/etqanbilling-fixtures.ts`:

```ts
import type {
	EtqanInvoice,
	MonthUsage,
} from "@/features/etqanbilling/schemas";

export function etqanInvoice(
	overrides: Partial<EtqanInvoice> = {},
): EtqanInvoice {
	return {
		id: 7,
		number: "ETQ-2026-09-0001",
		period: "2026-09",
		status: "issued",
		total: 250,
		currency: "USD",
		issued_at: "2026-10-02T03:00:00Z",
		due_at: "2026-10-17T03:00:00Z",
		paid_on: null,
		overdue: false,
		...overrides,
	};
}

export function monthUsage(overrides: Partial<MonthUsage> = {}): MonthUsage {
	return {
		month: "2026-10",
		currency: "USD",
		usage: [
			{
				service: "email",
				unit: "email",
				quantity: 2500,
				free: 1000,
				amount: 150,
				days: [
					{ date: "2026-10-01", quantity: 1200 },
					{ date: "2026-10-03", quantity: 1300 },
				],
			},
		],
		...overrides,
	};
}
```

`dashboard/src/features/etqanbilling/api.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { etqanInvoice, monthUsage } from "@/test/etqanbilling-fixtures";
import { etqanBillingApi, invoicePdfUrl } from "./api";

describe("etqanBillingApi", () => {
	afterEach(() => vi.restoreAllMocks());

	it("reads this month's use", async () => {
		const get = vi
			.spyOn(api, "get")
			.mockResolvedValue({ data: monthUsage() } as never);
		expect(await etqanBillingApi.usage()).toEqual(monthUsage());
		expect(get).toHaveBeenCalledWith("etqan-billing/usage/");
	});

	it("lists the invoices", async () => {
		const body = { invoices: [etqanInvoice()] };
		const get = vi.spyOn(api, "get").mockResolvedValue({ data: body } as never);
		expect(await etqanBillingApi.invoices()).toEqual(body);
		expect(get).toHaveBeenCalledWith("etqan-billing/invoices/");
	});

	it("links each invoice's PDF", () => {
		expect(invoicePdfUrl(7)).toBe("/api/v1/etqan-billing/invoices/7/pdf/");
	});
});
```

`dashboard/src/features/etqanbilling/queries.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { etqanInvoice, monthUsage } from "@/test/etqanbilling-fixtures";
import { etqanBillingApi } from "./api";
import { useEtqanInvoices, useMonthUsage } from "./queries";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		etqanBillingApi: { usage: vi.fn(), invoices: vi.fn() },
	};
});

function wrap({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("etqan billing queries", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(etqanBillingApi.usage).mockResolvedValue(monthUsage());
		vi.mocked(etqanBillingApi.invoices).mockResolvedValue({
			invoices: [etqanInvoice()],
		});
	});

	it("reads this month's use", async () => {
		const { result } = renderHook(() => useMonthUsage(), { wrapper: wrap });
		await waitFor(() => expect(result.current.data?.month).toBe("2026-10"));
	});

	it("reads the invoices only when asked", async () => {
		const off = renderHook(() => useEtqanInvoices(false), { wrapper: wrap });
		expect(off.result.current.fetchStatus).toBe("idle");
		expect(etqanBillingApi.invoices).not.toHaveBeenCalled();
		const on = renderHook(() => useEtqanInvoices(), { wrapper: wrap });
		await waitFor(() =>
			expect(on.result.current.data?.invoices).toHaveLength(1),
		);
	});
});
```

`dashboard/src/features/etqanbilling/format.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import i18n from "@/lib/i18n";
import { count, dayName, monthName, priceText } from "./format";

describe("etqan billing formatting", () => {
	it("names a UTC month and day in the reader's language", () => {
		expect(monthName("2026-09", "en")).toBe("September 2026");
		expect(dayName("2026-10-01", "en")).toBe("Oct 1, 2026");
		expect(count(2500, "en")).toBe("2,500");
	});

	it("says a price with its batch and the monthly allowance", () => {
		expect(
			priceText(
				{ unit: "email", per: 1000, amount: 100, currency: "USD", free: 1000 },
				i18n.t,
				"en",
			),
		).toBe(
			"Etqan's price: $1.00 per 1,000 emails. The first 1,000 each month are free.",
		);
		expect(
			priceText(
				{ unit: "conversation", per: 1, amount: 5, currency: "USD", free: 0 },
				i18n.t,
				"en",
			),
		).toBe("Etqan's price: $0.05 per conversation.");
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DASH pnpm vitest run src/features/etqanbilling`
Expected: FAIL — `Failed to resolve import "./api"` (and `./queries`, `./format`, `@/features/etqanbilling/schemas`).

- [ ] **Step 3: Write the data layer**

`dashboard/src/features/etqanbilling/schemas.ts`:

```ts
// Spec 2026-10-07 §5–6: Etqan's invoices to the academy and its use of
// Etqan's default accounts. Money is integer minor units + currency.
export type Metered = "whatsapp" | "email" | "video" | "ai";
export type Unit =
	| "conversation"
	| "email"
	| "minute"
	| "input_token"
	| "output_token";
/** Drafts are Etqan's: the academy sees an invoice once issued. */
export type InvoiceStatus = "issued" | "paid" | "void";

export interface UsageDay {
	date: string;
	quantity: number;
}

export interface UsageRow {
	service: Metered;
	unit: Unit;
	quantity: number;
	free: number;
	/** The charge so far, in minor units of the month's currency. */
	amount: number;
	days: UsageDay[];
}

export interface MonthUsage {
	/** "2026-10" */
	month: string;
	currency: string;
	usage: UsageRow[];
}

export interface EtqanInvoice {
	id: number;
	number: string;
	/** "2026-09": the invoiced UTC month. */
	period: string;
	status: InvoiceStatus;
	total: number;
	currency: string;
	issued_at: string;
	due_at: string;
	paid_on: string | null;
	overdue: boolean;
}

export interface EtqanInvoices {
	invoices: EtqanInvoice[];
}

/** Etqan's price for one unit on the Integrations card (plan D18). */
export interface DefaultPrice {
	unit: Unit;
	per: number;
	amount: number;
	currency: string;
	free: number;
}
```

`dashboard/src/features/etqanbilling/api.ts`:

```ts
import { api } from "@/lib/api";
import type { EtqanInvoices, MonthUsage } from "./schemas";

const B = "etqan-billing/";

export const etqanBillingApi = {
	usage: async () => (await api.get<MonthUsage>(`${B}usage/`)).data,
	invoices: async () => (await api.get<EtqanInvoices>(`${B}invoices/`)).data,
};

/** The invoice's PDF; same origin, so the session cookie goes with it. */
export function invoicePdfUrl(id: number): string {
	return `${api.defaults.baseURL ?? "/api/v1/"}${B}invoices/${id}/pdf/`;
}
```

`dashboard/src/features/etqanbilling/queries.ts`:

```ts
import { useQuery } from "@tanstack/react-query";
import { etqanBillingApi } from "./api";

/** Every Etqan billing query lives under this key. */
export const etqanBillingKey = ["etqan-billing"] as const;

export function useMonthUsage() {
	return useQuery({
		queryKey: [...etqanBillingKey, "usage"],
		queryFn: etqanBillingApi.usage,
	});
}

/** Shared by the billing page and the overdue banner; off for anyone but
 * an admin (plan D17). */
export function useEtqanInvoices(enabled = true) {
	return useQuery({
		queryKey: [...etqanBillingKey, "invoices"],
		queryFn: etqanBillingApi.invoices,
		enabled,
		staleTime: 5 * 60 * 1000,
	});
}
```

`dashboard/src/features/etqanbilling/format.ts`:

```ts
import type { TFunction } from "i18next";
import { formatMoney } from "@/lib/money";
import type { DefaultPrice } from "./schemas";

/** "2026-09" as "September 2026": the invoice's UTC month. */
export function monthName(period: string, language: string): string {
	const [year, month] = period.split("-").map(Number);
	return new Intl.DateTimeFormat(language, {
		month: "long",
		year: "numeric",
		timeZone: "UTC",
	}).format(new Date(Date.UTC(year, month - 1, 1)));
}

/** A UTC day ("2026-10-01" or an instant) in the reader's language. */
export function dayName(iso: string, language: string): string {
	return new Intl.DateTimeFormat(language, {
		dateStyle: "medium",
		timeZone: "UTC",
	}).format(new Date(iso));
}

export function count(n: number, language: string): string {
	return new Intl.NumberFormat(language).format(n);
}

/** "Etqan's price: $1.00 per 1,000 emails. The first 1,000 each month are free." */
export function priceText(
	price: DefaultPrice,
	t: TFunction,
	language: string,
): string {
	const line = t("etqanBilling.price.line", {
		amount: formatMoney(price.amount, price.currency, language),
		per: t(`etqanBilling.price.per.${price.unit}`, {
			n: count(price.per, language),
		}),
	});
	if (price.free <= 0) return line;
	return `${line} ${t("etqanBilling.price.free", { n: count(price.free, language) })}`;
}
```

`dashboard/src/features/etqanbilling/index.ts`:

```ts
export { etqanBillingApi, invoicePdfUrl } from "./api";
export * from "./format";
export * from "./queries";
export * from "./schemas";
```

In `dashboard/src/features/integrations/schemas.ts`, add at the top

```ts
import type { DefaultPrice } from "@/features/etqanbilling/schemas";
```

and in `IntegrationCard` add after `own: OwnAccount | null;`:

```ts
	/** Etqan's price for the default, per unit (slice 2 plan D18). */
	default_prices: DefaultPrice[];
```

In `dashboard/src/test/integrations-fixtures.ts`, in `card`, add `default_prices: [],` after `own: null,`.

- [ ] **Step 4: Write the strings**

`dashboard/src/locales/en/etqanBilling.json`:

```json
{
	"nav": {
		"title": "Etqan billing"
	},
	"page": {
		"subtitle": "What your academy owes Etqan for using its default accounts: this month's use and your invoices."
	},
	"units": {
		"conversation": "WhatsApp conversations",
		"email": "Emails",
		"minute": "Video meeting minutes",
		"input_token": "AI input tokens",
		"output_token": "AI output tokens"
	},
	"usage": {
		"title": "Use this month ({{month}})",
		"none": "No use of Etqan's default accounts yet this month.",
		"summary": "{{quantity}} used · {{free}} free · {{amount}} so far",
		"daily": "{{unit}} by day",
		"day": "Day",
		"quantity": "Quantity"
	},
	"invoices": {
		"title": "Invoices",
		"none": "No invoices yet. Etqan invoices on the 1st of each month for the month before.",
		"number": "Number",
		"month": "Month",
		"total": "Total",
		"due": "Due",
		"status": "Status",
		"pdf": "PDF",
		"pdfLabel": "Download {{number}} as PDF",
		"paidOn": "Paid on {{date}}"
	},
	"status": {
		"issued": "Unpaid",
		"paid": "Paid",
		"void": "Void",
		"overdue": "Overdue"
	},
	"payNote": "Pay by bank transfer or any way Etqan accepts; Etqan marks the invoice paid when the payment arrives.",
	"banner": {
		"overdue": "An Etqan invoice is overdue. Pay it to keep using Etqan's default accounts.",
		"open": "See Etqan billing"
	},
	"price": {
		"line": "Etqan's price: {{amount}} {{per}}.",
		"free": "The first {{n}} each month are free.",
		"per": {
			"conversation": "per conversation",
			"email": "per {{n}} emails",
			"minute": "per meeting minute",
			"input_token": "per {{n}} input tokens",
			"output_token": "per {{n}} output tokens"
		}
	}
}
```

`dashboard/src/locales/ar/etqanBilling.json`:

```json
{
	"nav": {
		"title": "فواتير إتقان"
	},
	"page": {
		"subtitle": "ما تستحقه إتقان على أكاديميتك مقابل استخدام حساباتها الافتراضية: استخدام هذا الشهر وفواتيرك."
	},
	"units": {
		"conversation": "محادثات WhatsApp",
		"email": "رسائل البريد الإلكتروني",
		"minute": "دقائق الاجتماعات المرئية",
		"input_token": "رموز إدخال الذكاء الاصطناعي",
		"output_token": "رموز إخراج الذكاء الاصطناعي"
	},
	"usage": {
		"title": "استخدام هذا الشهر ({{month}})",
		"none": "لا استخدام لحسابات إتقان الافتراضية هذا الشهر بعد.",
		"summary": "{{quantity}} مستخدمة · {{free}} مجانية · {{amount}} حتى الآن",
		"daily": "{{unit}} حسب اليوم",
		"day": "اليوم",
		"quantity": "الكمية"
	},
	"invoices": {
		"title": "الفواتير",
		"none": "لا فواتير بعد. تصدر إتقان فاتورة الشهر السابق في اليوم الأول من كل شهر.",
		"number": "الرقم",
		"month": "الشهر",
		"total": "الإجمالي",
		"due": "تاريخ الاستحقاق",
		"status": "الحالة",
		"pdf": "PDF",
		"pdfLabel": "تنزيل {{number}} بصيغة PDF",
		"paidOn": "دُفعت في {{date}}"
	},
	"status": {
		"issued": "غير مدفوعة",
		"paid": "مدفوعة",
		"void": "ملغاة",
		"overdue": "متأخرة"
	},
	"payNote": "ادفع بتحويل بنكي أو بأي وسيلة تقبلها إتقان، وتسجّل إتقان الفاتورة مدفوعة عند وصول المبلغ.",
	"banner": {
		"overdue": "لديك فاتورة من إتقان متأخرة السداد. ادفعها لتواصل استخدام حسابات إتقان الافتراضية.",
		"open": "عرض فواتير إتقان"
	},
	"price": {
		"line": "سعر إتقان: {{amount}} {{per}}.",
		"free": "أول {{n}} في كل شهر مجانًا.",
		"per": {
			"conversation": "لكل محادثة",
			"email": "لكل {{n}} رسالة بريد",
			"minute": "لكل دقيقة اجتماع",
			"input_token": "لكل {{n}} رمز إدخال",
			"output_token": "لكل {{n}} رمز إخراج"
		}
	}
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `$DASH pnpm vitest run src/features/etqanbilling src/features/integrations`
Expected: PASS.

Run: `just test-frontend`
Expected: `tsc --noEmit` passes (every `IntegrationCard` now carries `default_prices`).

- [ ] **Step 6: Format and commit**

```bash
$DASH pnpm exec biome check --write src
git -C dashboard add src/features/etqanbilling src/features/integrations/schemas.ts src/test/etqanbilling-fixtures.ts src/test/integrations-fixtures.ts src/locales/en/etqanBilling.json src/locales/ar/etqanBilling.json
git -C dashboard commit -m "feat(etqanbilling): data layer, formatting and strings" -m "$TRAILER"
```

---

### Task 11: Settings → Etqan billing, its route and nav item; the default's price on the Integrations cards

**Files:**
- Create: `dashboard/src/features/etqanbilling/EtqanBillingPage.tsx`, `dashboard/src/features/etqanbilling/EtqanBillingPage.test.tsx`, `dashboard/src/routes/_authed/settings.etqan-billing.tsx`
- Modify: `dashboard/src/features/etqanbilling/index.ts`, `dashboard/src/features/shell/nav.ts`, `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/routes/permissions.test.ts`, `dashboard/src/features/integrations/IntegrationsPage.tsx`, `dashboard/src/features/integrations/IntegrationsPage.test.tsx`, `dashboard/src/routeTree.gen.ts` (generated)

**Interfaces:**
- Consumes: Task 10's `useMonthUsage`, `useEtqanInvoices`, `invoicePdfUrl`, `monthName`, `dayName`, `count`, `priceText`, types; `ADMINS_ONLY`, `requireOffice`, `usePageTitle`, `@/ui` (`Alert`, `AlertDescription`, `Card`, `CardContent`, `CardDescription`, `CardHeader`, `CardTitle`, `PageContainer`, `PageHeader`, `Spinner`, `StatusChip`).
- Produces: `EtqanBillingPage` (exported from `@/features/etqanbilling`); the route `/_authed/settings/etqan-billing` (`staticData: { permission: ADMINS_ONLY }`); the nav item `/settings/etqan-billing`; `DefaultPrices` on each Integrations card.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/etqanbilling/EtqanBillingPage.test.tsx`:

```tsx
import { act, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { etqanInvoice, monthUsage } from "@/test/etqanbilling-fixtures";
import { renderWithRouter } from "@/test/render";
import { etqanBillingApi } from "./api";
import { EtqanBillingPage } from "./EtqanBillingPage";
import { dayName } from "./format";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		etqanBillingApi: { usage: vi.fn(), invoices: vi.fn() },
	};
});

describe("EtqanBillingPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(etqanBillingApi.usage).mockResolvedValue(monthUsage());
		vi.mocked(etqanBillingApi.invoices).mockResolvedValue({
			invoices: [etqanInvoice()],
		});
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("shows this month's use per unit and by day", async () => {
		renderWithRouter(<EtqanBillingPage />);
		expect(
			await screen.findByText("Use this month (October 2026)"),
		).toBeVisible();
		expect(screen.getByText("Emails")).toBeVisible();
		expect(
			screen.getByText("2,500 used · 1,000 free · $1.50 so far"),
		).toBeVisible();
		const daily = screen.getByRole("table", { name: "Emails by day" });
		expect(within(daily).getByText("1,200")).toBeVisible();
		expect(
			within(daily).getByText(dayName("2026-10-03", "en")),
		).toBeVisible();
	});

	it("lists the invoices with their PDF", async () => {
		renderWithRouter(<EtqanBillingPage />);
		const row = (await screen.findByText("ETQ-2026-09-0001")).closest(
			"tr",
		) as HTMLElement;
		expect(within(row).getByText("September 2026")).toBeVisible();
		expect(within(row).getByText("$2.50")).toBeVisible();
		expect(within(row).getByText("Unpaid")).toBeVisible();
		expect(
			within(row).getByRole("link", {
				name: "Download ETQ-2026-09-0001 as PDF",
			}),
		).toHaveAttribute("href", "/api/v1/etqan-billing/invoices/7/pdf/");
	});

	it("marks an overdue invoice and a paid one", async () => {
		vi.mocked(etqanBillingApi.invoices).mockResolvedValue({
			invoices: [
				etqanInvoice({ overdue: true }),
				etqanInvoice({
					id: 6,
					number: "ETQ-2026-08-0003",
					period: "2026-08",
					status: "paid",
					paid_on: "2026-09-20",
				}),
			],
		});
		renderWithRouter(<EtqanBillingPage />);
		expect(await screen.findByText("Overdue")).toBeVisible();
		expect(screen.getByText("Paid")).toBeVisible();
		expect(
			screen.getByText(`Paid on ${dayName("2026-09-20", "en")}`),
		).toBeVisible();
	});

	it("says when there is nothing yet", async () => {
		vi.mocked(etqanBillingApi.usage).mockResolvedValue(
			monthUsage({ usage: [] }),
		);
		vi.mocked(etqanBillingApi.invoices).mockResolvedValue({ invoices: [] });
		renderWithRouter(<EtqanBillingPage />);
		expect(
			await screen.findByText(
				"No use of Etqan's default accounts yet this month.",
			),
		).toBeVisible();
		expect(
			await screen.findByText(
				"No invoices yet. Etqan invoices on the 1st of each month for the month before.",
			),
		).toBeVisible();
	});

	it("says when the server fails", async () => {
		vi.mocked(etqanBillingApi.usage).mockRejectedValue(new Error("down"));
		vi.mocked(etqanBillingApi.invoices).mockRejectedValue(new Error("down"));
		renderWithRouter(<EtqanBillingPage />);
		expect(
			await screen.findAllByText("Something went wrong. Please try again."),
		).toHaveLength(2);
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderWithRouter(<EtqanBillingPage />);
		expect(await screen.findByText("الفواتير")).toBeVisible();
		expect(await screen.findByText("غير مدفوعة")).toBeVisible();
	});
});
```

In `dashboard/src/features/integrations/IntegrationsPage.test.tsx`, add inside `describe("IntegrationsPage", …)`:

```tsx
	it("shows Etqan's price for its default", async () => {
		vi.mocked(integrationsApi.list).mockResolvedValue(
			integrations({
				default_prices: [
					{ unit: "email", per: 1000, amount: 100, currency: "USD", free: 1000 },
				],
			}),
		);
		renderWithRouter(<IntegrationsPage />);
		expect(
			await screen.findByText(
				"Etqan's price: $1.00 per 1,000 emails. The first 1,000 each month are free.",
			),
		).toBeVisible();
	});
```

In `dashboard/src/features/shell/nav.test.ts`, in the `"ships the grouped admin areas in order"` list, replace

```ts
			// Integrations (spec 2026-10-07; not a phase)
			"/settings/integrations",
```

with

```ts
			// Integrations (spec 2026-10-07; not a phase)
			"/settings/integrations",
			"/settings/etqan-billing",
```

In `dashboard/src/routes/permissions.test.ts`, add after the `describe("Settings → Integrations", …)` block:

```ts
describe("Settings → Etqan billing", () => {
	it("is for admins only and belongs to no feature", () => {
		const route = (router.routesById as unknown as Record<string, AnyRoute>)[
			"/_authed/settings/etqan-billing"
		];
		expect(route?.options.staticData).toEqual({ permission: ADMINS_ONLY });
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DASH pnpm vitest run src/features/etqanbilling src/features/integrations src/features/shell/nav.test.ts src/routes/permissions.test.ts`
Expected: FAIL — `Failed to resolve import "./EtqanBillingPage"`, the price text is missing, the nav list lacks `/settings/etqan-billing`, the route is undefined.

- [ ] **Step 3: Write the page**

`dashboard/src/features/etqanbilling/EtqanBillingPage.tsx`:

```tsx
import { FileDown } from "lucide-react";
import { useTranslation } from "react-i18next";
import { formatMoney } from "@/lib/money";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
	Spinner,
	StatusChip,
} from "@/ui";
import { invoicePdfUrl } from "./api";
import { count, dayName, monthName } from "./format";
import { useEtqanInvoices, useMonthUsage } from "./queries";
import type { EtqanInvoice, UsageRow } from "./schemas";

function Failed() {
	const { t } = useTranslation();
	return (
		<Alert variant="destructive">
			<AlertDescription>{t("errors.generic")}</AlertDescription>
		</Alert>
	);
}

function UsageCard({ row, currency }: { row: UsageRow; currency: string }) {
	const { t, i18n } = useTranslation();
	const lang = i18n.language;
	const unit = t(`etqanBilling.units.${row.unit}`);
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{unit}</CardTitle>
				<CardDescription>
					{t("etqanBilling.usage.summary", {
						quantity: count(row.quantity, lang),
						free: count(row.free, lang),
						amount: formatMoney(row.amount, currency, lang),
					})}
				</CardDescription>
			</CardHeader>
			<CardContent className="pt-4">
				<table className="w-full text-sm">
					<caption className="sr-only">
						{t("etqanBilling.usage.daily", { unit })}
					</caption>
					<thead className="text-muted-foreground">
						<tr>
							<th scope="col" className="p-2 text-start font-medium">
								{t("etqanBilling.usage.day")}
							</th>
							<th scope="col" className="p-2 text-end font-medium">
								{t("etqanBilling.usage.quantity")}
							</th>
						</tr>
					</thead>
					<tbody>
						{row.days.map((day) => (
							<tr key={day.date} className="border-t border-border">
								<td className="p-2">{dayName(day.date, lang)}</td>
								<td className="p-2 text-end tabular-nums">
									{count(day.quantity, lang)}
								</td>
							</tr>
						))}
					</tbody>
				</table>
			</CardContent>
		</Card>
	);
}

function UsageSection() {
	const { t, i18n } = useTranslation();
	const { data, isError } = useMonthUsage();
	if (isError) return <Failed />;
	if (!data) return <Spinner />;
	return (
		<section aria-labelledby="etqan-usage" className="flex flex-col gap-4">
			<h2 id="etqan-usage" className="text-lg font-semibold">
				{t("etqanBilling.usage.title", {
					month: monthName(data.month, i18n.language),
				})}
			</h2>
			{data.usage.length === 0 ? (
				<p className="text-sm text-muted-foreground">
					{t("etqanBilling.usage.none")}
				</p>
			) : (
				<div className="grid gap-6 lg:grid-cols-2">
					{data.usage.map((row) => (
						<UsageCard key={row.unit} row={row} currency={data.currency} />
					))}
				</div>
			)}
		</section>
	);
}

function InvoiceStatus({ invoice }: { invoice: EtqanInvoice }) {
	const { t, i18n } = useTranslation();
	const status = invoice.overdue ? "overdue" : invoice.status;
	const tone =
		status === "overdue" ? "warning" : status === "paid" ? "live" : "neutral";
	return (
		<div className="flex flex-col items-start gap-1">
			<StatusChip tone={tone}>{t(`etqanBilling.status.${status}`)}</StatusChip>
			{invoice.paid_on ? (
				<span className="text-xs text-muted-foreground">
					{t("etqanBilling.invoices.paidOn", {
						date: dayName(invoice.paid_on, i18n.language),
					})}
				</span>
			) : null}
		</div>
	);
}

function InvoicesSection() {
	const { t, i18n } = useTranslation();
	const lang = i18n.language;
	const { data, isError } = useEtqanInvoices();
	if (isError) return <Failed />;
	if (!data) return <Spinner />;
	return (
		<section aria-labelledby="etqan-invoices" className="flex flex-col gap-4">
			<h2 id="etqan-invoices" className="text-lg font-semibold">
				{t("etqanBilling.invoices.title")}
			</h2>
			{data.invoices.length === 0 ? (
				<p className="text-sm text-muted-foreground">
					{t("etqanBilling.invoices.none")}
				</p>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{(["number", "month", "total", "due", "status"] as const).map(
									(key) => (
										<th
											key={key}
											scope="col"
											className="p-3 text-start font-medium"
										>
											{t(`etqanBilling.invoices.${key}`)}
										</th>
									),
								)}
								<th scope="col" className="p-3 text-start font-medium">
									{t("etqanBilling.invoices.pdf")}
								</th>
							</tr>
						</thead>
						<tbody>
							{data.invoices.map((invoice) => (
								<tr key={invoice.id} className="border-t border-border">
									<td className="p-3 font-medium" dir="ltr">
										{invoice.number}
									</td>
									<td className="p-3">{monthName(invoice.period, lang)}</td>
									<td className="p-3 tabular-nums">
										{formatMoney(invoice.total, invoice.currency, lang)}
									</td>
									<td className="p-3">{dayName(invoice.due_at, lang)}</td>
									<td className="p-3">
										<InvoiceStatus invoice={invoice} />
									</td>
									<td className="p-3">
										<a
											href={invoicePdfUrl(invoice.id)}
											aria-label={t("etqanBilling.invoices.pdfLabel", {
												number: invoice.number,
											})}
											className="inline-flex items-center gap-1 font-medium text-primary-text underline-offset-4 hover:underline"
										>
											<FileDown aria-hidden="true" className="size-4" />
											{t("etqanBilling.invoices.pdf")}
										</a>
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
		</section>
	);
}

/** Spec §6: Settings → Etqan billing (admins). */
export function EtqanBillingPage() {
	const { t } = useTranslation();
	return (
		<div className="flex flex-col gap-8">
			<UsageSection />
			<InvoicesSection />
			<p className="text-sm text-muted-foreground">
				{t("etqanBilling.payNote")}
			</p>
		</div>
	);
}
```

In `dashboard/src/features/etqanbilling/index.ts`, add:

```ts
export { EtqanBillingPage } from "./EtqanBillingPage";
```

`dashboard/src/routes/_authed/settings.etqan-billing.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { EtqanBillingPage } from "@/features/etqanbilling";
import { ADMINS_ONLY } from "@/features/identity/permissions";
import { requireOffice } from "@/features/identity/require-admin";
import { PageContainer, PageHeader } from "@/ui";

/** Spec 2026-10-07 §6, slice 2 plan D17: admins only, as the API behind it. */
export const Route = createFileRoute("/_authed/settings/etqan-billing")({
	staticData: { permission: ADMINS_ONLY },
	beforeLoad: ({ context }) => requireOffice(context),
	component: function EtqanBillingRoute() {
		const { t } = useTranslation();
		usePageTitle(t("etqanBilling.nav.title"));
		return (
			<PageContainer>
				<PageHeader
					title={t("etqanBilling.nav.title")}
					description={t("etqanBilling.page.subtitle")}
				/>
				<EtqanBillingPage />
			</PageContainer>
		);
	},
});
```

In `dashboard/src/features/shell/nav.ts`, replace

```ts
	// Integrations (spec 2026-10-07; not a phase): the academy's outside-service accounts.
	office(
		"/settings/integrations",
		"integrations.nav.title",
		Plug,
		"settings",
		"integration.view",
	),
```

with

```ts
	// Integrations (spec 2026-10-07; not a phase): the academy's outside-service accounts.
	office(
		"/settings/integrations",
		"integrations.nav.title",
		Plug,
		"settings",
		"integration.view",
	),
	// Integrations slice 2: Etqan's invoices to the academy, admins only.
	office(
		"/settings/etqan-billing",
		"etqanBilling.nav.title",
		ReceiptText,
		"settings",
		ADMINS_ONLY,
	),
```

(`ReceiptText` and `ADMINS_ONLY` are already imported in `nav.ts`.)

- [ ] **Step 4: Show the default's price on each Integrations card**

In `dashboard/src/features/integrations/IntegrationsPage.tsx`, add the import

```tsx
import { priceText } from "@/features/etqanbilling/format";
```

change the schema import to

```tsx
import type {
	IntegrationCard,
	OwnAccount,
	Using,
} from "./schemas";
import type { DefaultPrice } from "@/features/etqanbilling/schemas";
```

add above `function ServiceCard`:

```tsx
/** Slice 2 plan D18: what Etqan charges for its default, per unit. */
function DefaultPrices({ prices }: { prices: DefaultPrice[] }) {
	const { t, i18n } = useTranslation();
	if (prices.length === 0) return null;
	return (
		<ul className="flex flex-col gap-1 text-sm text-muted-foreground">
			{prices.map((price) => (
				<li key={price.unit}>{priceText(price, t, i18n.language)}</li>
			))}
		</ul>
	);
}
```

and in `ServiceCard`, replace

```tsx
				<p className="text-sm text-muted-foreground">
					{t(`integrations.default.${card.default_status}`)}
				</p>
```

with

```tsx
				<p className="text-sm text-muted-foreground">
					{t(`integrations.default.${card.default_status}`)}
				</p>
				<DefaultPrices prices={card.default_prices} />
```

- [ ] **Step 5: Regenerate the route tree and run the tests**

Run: `$DASH pnpm exec vite build`
Expected: the build passes and `src/routeTree.gen.ts` gains `/_authed/settings/etqan-billing`.

Run: `$DASH pnpm vitest run src/features/etqanbilling src/features/integrations src/features/shell src/routes`
Expected: PASS.

Run: `just test-frontend && just lint-frontend`
Expected: both pass.

- [ ] **Step 6: Format and commit**

```bash
$DASH pnpm exec biome check --write src
git -C dashboard add src/features/etqanbilling src/features/integrations src/features/shell/nav.ts src/features/shell/nav.test.ts src/routes/_authed/settings.etqan-billing.tsx src/routes/permissions.test.ts src/routeTree.gen.ts
git -C dashboard commit -m "feat(etqanbilling): Settings → Etqan billing; Etqan's price on the Integrations cards" -m "$TRAILER"
```

---

### Task 12: The overdue banner on every page

**Files:**
- Create: `dashboard/src/features/etqanbilling/OverdueBanner.tsx`, `dashboard/src/features/etqanbilling/OverdueBanner.test.tsx`
- Modify: `dashboard/src/features/etqanbilling/index.ts`, `dashboard/src/features/shell/AppShell.tsx`, `dashboard/src/features/shell/AppShell.test.tsx`

**Interfaces:**
- Consumes: Task 10's `useEtqanInvoices(enabled)`; `useMe` from `@/features/identity/queries`; Task 11's route `/settings/etqan-billing`.
- Produces: `OverdueBanner` (exported from `@/features/etqanbilling`), rendered by `AppShell` under the impersonation banner.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/etqanbilling/OverdueBanner.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { useMe } from "@/features/identity/queries";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { etqanInvoice } from "@/test/etqanbilling-fixtures";
import { renderWithRouter } from "@/test/render";
import { etqanBillingApi } from "./api";
import { OverdueBanner } from "./OverdueBanner";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		etqanBillingApi: { usage: vi.fn(), invoices: vi.fn() },
	};
});
vi.mock("@/features/identity/queries", async (orig) => ({
	...(await orig<typeof import("@/features/identity/queries")>()),
	useMe: vi.fn(),
}));

function signedIn(me: ReturnType<typeof adminWith>) {
	vi.mocked(useMe).mockReturnValue({ data: me } as never);
}

describe("OverdueBanner", () => {
	beforeEach(() => vi.clearAllMocks());

	it("tells an admin an invoice is overdue and links to Etqan billing", async () => {
		signedIn(adminWith());
		vi.mocked(etqanBillingApi.invoices).mockResolvedValue({
			invoices: [etqanInvoice({ overdue: true })],
		});
		renderWithRouter(<OverdueBanner />);
		expect(
			await screen.findByText(
				"An Etqan invoice is overdue. Pay it to keep using Etqan's default accounts.",
			),
		).toBeVisible();
		expect(
			screen.getByRole("link", { name: "See Etqan billing" }),
		).toHaveAttribute("href", "/settings/etqan-billing");
	});

	it("shows nothing without an overdue invoice or to anyone but an admin", async () => {
		signedIn(adminWith());
		vi.mocked(etqanBillingApi.invoices).mockResolvedValue({
			invoices: [etqanInvoice(), etqanInvoice({ id: 8, status: "paid" })],
		});
		const admin = renderWithRouter(<OverdueBanner />);
		await vi.waitFor(() =>
			expect(etqanBillingApi.invoices).toHaveBeenCalledTimes(1),
		);
		expect(admin.queryByRole("status")).toBeNull();
		admin.unmount();

		vi.mocked(etqanBillingApi.invoices).mockClear();
		signedIn(staffMe("integration.view"));
		const staff = renderWithRouter(<OverdueBanner />);
		expect(staff.queryByRole("status")).toBeNull();
		expect(etqanBillingApi.invoices).not.toHaveBeenCalled();
	});
});
```

In `dashboard/src/features/shell/AppShell.test.tsx`, add the imports

```tsx
import { etqanBillingApi } from "@/features/etqanbilling";
import { adminWith } from "@/test/access-fixtures";
import { etqanInvoice } from "@/test/etqanbilling-fixtures";
```

(merge `adminWith` into the existing `@/test/access-fixtures` import), add to the top-level `beforeEach`:

```tsx
	// Integrations slice 2: the overdue banner reads an admin's invoices.
	vi.spyOn(etqanBillingApi, "invoices").mockResolvedValue({ invoices: [] });
```

and add inside `describe("AppShell", …)`:

```tsx
	it("shows an admin the overdue Etqan invoice banner on every page", async () => {
		me = adminWith();
		vi.mocked(etqanBillingApi.invoices).mockResolvedValue({
			invoices: [etqanInvoice({ overdue: true })],
		});
		renderShell();
		expect(
			await screen.findByText(
				"An Etqan invoice is overdue. Pay it to keep using Etqan's default accounts.",
			),
		).toBeVisible();
	});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DASH pnpm vitest run src/features/etqanbilling/OverdueBanner.test.tsx src/features/shell/AppShell.test.tsx`
Expected: FAIL — `Failed to resolve import "./OverdueBanner"`; the shell shows no banner.

- [ ] **Step 3: Write the banner and put it in the shell**

`dashboard/src/features/etqanbilling/OverdueBanner.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { useMe } from "@/features/identity/queries";
import { useEtqanInvoices } from "./queries";

/** Spec §5–6: once an Etqan invoice is 15 days unpaid, every page tells
 * the academy's admins (plan D17). Nobody else is asked. */
export function OverdueBanner() {
	const { t } = useTranslation();
	const { data: me } = useMe({ enabled: false });
	const admin = me?.role === "admin";
	const { data } = useEtqanInvoices(admin);
	if (!admin || !data?.invoices.some((invoice) => invoice.overdue)) return null;
	return (
		<div
			role="status"
			className="flex flex-wrap items-center gap-3 border-b border-border bg-warning px-4 py-2 text-sm font-medium text-warning-foreground"
		>
			<span className="me-auto">{t("etqanBilling.banner.overdue")}</span>
			<Link
				to="/settings/etqan-billing"
				className="underline underline-offset-4"
			>
				{t("etqanBilling.banner.open")}
			</Link>
		</div>
	);
}
```

In `dashboard/src/features/etqanbilling/index.ts`, add:

```ts
export { OverdueBanner } from "./OverdueBanner";
```

In `dashboard/src/features/shell/AppShell.tsx`, add the import

```tsx
import { OverdueBanner } from "@/features/etqanbilling";
```

and replace

```tsx
				<ImpersonationBanner />
```

with

```tsx
				<ImpersonationBanner />
				<OverdueBanner />
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `$DASH pnpm vitest run src/features/etqanbilling src/features/shell`
Expected: PASS.

Run: `just test-frontend && just lint-frontend`
Expected: both pass.

- [ ] **Step 5: Format and commit**

```bash
$DASH pnpm exec biome check --write src
git -C dashboard add src/features/etqanbilling src/features/shell/AppShell.tsx src/features/shell/AppShell.test.tsx
git -C dashboard commit -m "feat(etqanbilling): overdue Etqan invoice banner for admins on every page" -m "$TRAILER"
```

---

### Task 13: Docs, state and the gates

**Files:**
- Modify: `CLAUDE.md` (meta), `STATE.md` (meta)

**Interfaces:**
- Consumes: everything above.
- Produces: the metering rule every later phase follows (spec §7), the current position.

- [ ] **Step 1: Write the failing check**

Run: `grep -c "record_usage" CLAUDE.md STATE.md`
Expected: `CLAUDE.md:0` and `STATE.md:0` (exit status 1).

- [ ] **Step 2: Run the whole suite before the docs**

Run: `just test && just lint`
Expected: backend and dashboard suites, `lint-imports`, ruff, biome and the secret scan pass; backend coverage ≥ 80 %. Then `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm test:coverage` — lines and statements ≥ 80, branches and functions ≥ 70. Then `just e2e` (the full suite; every email a journey sends now also writes a usage row): all pass.

- [ ] **Step 3: Implement**

In `CLAUDE.md`, replace

```markdown
  `etqan.integrations.services.resolve(service)`; no app stores keys of its own. Email goes out
  only through `integrations.services.queue_email` / `send_email_now`. Secrets go through
  `etqan.platform.secrets`.
```

with

```markdown
  `etqan.integrations.services.resolve(service)`; no app stores keys of its own. Email goes out
  only through `integrations.services.queue_email` / `send_email_now`. Secrets go through
  `etqan.platform.secrets`.
- Use of an Etqan default is metered on the provider's confirmation with
  `etqan.etqan_billing.services.record_usage(source=resolved.source, service, unit, quantity,
  source_ref)`; it records only `source == "etqan"`, once per `source_ref`.
```

In `STATE.md`, in the `## Integrations (outside the phases)` section, replace the sentence that begins `Next: slice 2` (through the end of that paragraph) with:

```markdown
Slice 2 is built: `etqan.etqan_billing` (public schema) meters use of Etqan's defaults
(`record_usage`, email on Etqan's default counted per message), prices it (`Price`, per-academy
`AcademyPricing` overrides and allowances, `ConnectFee`), drafts invoices on the 1st at 03:00 UTC,
issues them after 24 hours and emails the PDF to the academy's admins; Settings → Etqan billing
(admins), the overdue banner, the platform admin (prices, terms, Connect fee, usage, invoices) and
the "suspend Etqan's defaults" switch (from 30 days unpaid). Next: B5c meters WhatsApp
conversations, B2/B10 Zoom minutes and AI tokens through `record_usage`; the B3 follow-up reads
`connect_fee()` and records `record_collected_fee`.
```

- [ ] **Step 4: Run the check to see it pass**

Run: `grep -c "record_usage" CLAUDE.md STATE.md`
Expected: `CLAUDE.md:1` and `STATE.md:2`.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md STATE.md
git commit -m "docs: integrations slice 2 metering rule and state" -m "$TRAILER"
```

Then open the PRs (backend and dashboard `feat/integrations-2` → `main`; meta `feat/integrations-2` → `master` with `--repo Etqan-agency/etqan_tutor`), merge after review, and bump the submodule pointers in meta with explicit paths (`git add backend dashboard`), never `git commit -a`. Production needs `ETQAN_BILLING_CURRENCY` and `ETQAN_BILLING_PAYMENT_INSTRUCTIONS` set (both have defaults) and a rebuilt image (new Python packages).

---

## Self-review

**Spec coverage (slice 2):**
- §5 `UsageEvent` (academy, service, unit, quantity, UTC `occurred_at`, `source_ref` unique per academy+service, recorded only on confirmation and only for `source == "etqan"`) — Tasks 1 and 2 (D3); email metered through slice 1's seam — Task 2 (D4); the public `record_usage` interface for WhatsApp, Zoom and AI — Task 2, tested on WhatsApp and AI units.
- §5 `Price` (minor units, one Etqan currency, `effective_from`) and `AcademyPricing` (override, monthly allowance; Connect fee percent + fixed as `ConnectFee`) — Tasks 1 and 3 (D5–D8); the Connect fee seam (`connect_fee()`, `record_collected_fee`) with no Stripe code — Tasks 2–4 (D9).
- §5 `EtqanInvoice` + lines, `ETQ-YYYY-MM-NNNN`, one per academy per UTC month with usage, quantity × price − allowance lines, the read-only Connect fees line, manual lines, `draft → issued → paid | void` — Task 4 (D10–D12).
- §5 monthly job (1st, 03:00 UTC, loops academies, previous month), drafts editable 24 h then issued automatically or earlier by Etqan, issuing emails the admins with the PDF — Tasks 4, 5, 6, 8 (D13–D15).
- §5 overdue (15 days → banner), suspension from 30 days, manual, the resolver then skips step 2 (slice 1) — Tasks 4, 9, 12 (D11, D16).
- §5 issued invoices never change; corrections are credit lines on the next invoice — Task 4 (`test_an_issued_invoice_never_changes`, `test_a_correction_is_a_credit_line_on_the_next_invoice`), Task 8 (admin refuses lines on issued invoices).
- §6 Settings → Etqan billing (admins: usage this month per service, daily; past invoices with PDF, status, due date; the overdue banner on every page) — Tasks 7, 10, 11, 12 (D17). The Integrations card's default price — Tasks 7 and 11 (D18).
- §6 platform admin: prices, per-academy overrides, allowances, Connect fee, invoices (review drafts, add manual line, issue, mark paid with date/method/reference, void), usage per academy, the suspend switch — Tasks 8 and 9.
- §8 invoice tests (allowance and override arithmetic in minor units, `effective_from`, zero-usage month, immutability, credit line, the job loops every academy), webhook idempotency and no usage for `source == "academy"`, role gates and the overdue banner — Tasks 2, 3, 4, 6, 7, 11, 12.
- IN-8 respected: no tax/VAT, no automatic charging (Etqan marks paid; suspension is manual).

**Placeholder scan:** every step carries the full test code, the exact command and expected result, the full implementation and an exact commit command. The only angle-bracketed token is the trailer's `<implementing model>`, defined in Global Constraints. Generated files (`0001_initial.py`, `routeTree.gen.ts`) and the downloaded fonts are produced by the named commands.

**Name consistency:** `record_usage(source=, service=, unit=, quantity=, source_ref=, occurred_at=)` matches Task 2's definition, `meter_email`, the CLAUDE.md rule and the tests. `UNITS`, `PER`, `LINE_TITLES`, `UsageLine`, `usage_lines`, `daily_usage` (key `total`), `month_usage` (keys `month`, `currency`, `usage[].{service, unit, quantity, free, amount, days[].{date, quantity}}`), `current_prices` (`unit, per, amount, currency, free`), `ConnectFeeTerms`, `connect_fee`, `money`, `price_text` agree across Tasks 3, 5, 7, 8. Invoice functions `create_draft`, `build_month`, `has_invoice`, `check_line(invoice, *, kind, description, amount)`, `add_line`, `remove_line`, `issue`, `issue_due`, `mark_paid(invoice, *, paid_on, method, reference)`, `void(invoice, *, reason)`, `is_overdue`, `oldest_unpaid_days`, `may_suspend`, `academy_invoices`, `academy_invoice`, constants `ADDABLE`, `SUSPEND_DAYS`, `CONNECT_FEES_TITLE` and error codes `etqan_billing.{not_draft, not_issued, paid, already_invoiced, negative_total, usage_line}` match between Task 4, the admin (Task 8), the tenants form (Task 9), the tasks (Task 6) and the tests. Celery names `etqan_billing.build_month`, `etqan_billing.issue_due`, `etqan_billing.send_invoice` match the beat schedule and tests. The API shapes in Task 7 match `schemas.ts`, the fixtures and the page tests (Tasks 10–12); the route `/settings/etqan-billing` matches `BILLING_PATH`, the nav item, the banner's link and the permissions test.

**Fixed inline during review:** the invoice email is sent inside `schema_context(public)` because the test (and a request-time caller) runs inside an academy, where the academy's own SMTP would have resolved and metered it; `check_line` takes the locked invoice so the zero-floor uses the current total; services never queue the email (`tasks` imports identity, which `etqan_billing.services` must not reach, D2); `ignore_imports` lines are added only in the task whose test first needs them, since `lint-imports` refuses an ignore that matches nothing; `__str__` lines kept under 88 characters.
