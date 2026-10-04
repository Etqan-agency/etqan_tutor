# Plan 26 — Slice B3g: Payment links and payment records — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Slice:** B3g
**Requires:** — (no other phase's slice; B3b and B3c merged first)

**Goal:** An admin records payments that have no invoice, lists and exports every payment record, creates a
payment link (or a donation link) for a registered or unregistered student, and sends it. Whoever opens the
link pays without logging in, and the money becomes a payment record or a donation. Office staff can note
each subscription's payment type and system.

**Architecture:**
- **Billing** (`etqan.billing`): `Payment.invoice` becomes nullable and every payment carries its own
  currency and customer; a new `services/records.py` creates, edits, lists and filters standalone records;
  `SubscriptionTerms` (SUB-006) is a plain table keyed by a subscription id; billing registers the
  `payment_link` purpose (public).
- **Gateways** (`etqan.gateways`): `PaymentLink` and `services/links.py` (create, cancel, list, public view,
  `link_for`), public pay routes, and the three small core changes that let a link checkout run without a
  user: `Prepared.use_switch`, a `public` flag on purposes, and the completion step locking the link
  (G-13). Gateways never imports a selling app; finance registers the `donation_link` purpose.
- **Dashboard** (`features/gateways`, `features/billing`): the public pay page, the return and simulator
  pages moved out of `_authed`, Billing → Payment links, Billing → Payment records, a CSV button on Online
  payments, and `SubscriptionTermsCard` on the office invoice page.

**Tech Stack:**
- backend: Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18, `httpx` + `respx` (from Plan 20), pytest;
- dashboard: React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next, Vitest;
- e2e: Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-03-b3g-links-records-design.md` (decisions G-1 to G-23), slice B3g
of `docs/superpowers/specs/2026-10-03-b3-money-depth-design.md`. It builds on:
- B3b, `docs/superpowers/specs/2026-10-03-b3b-online-payments-design.md` (with its §12 amendments), as built by
  **Plan 20** (`docs/superpowers/plans/2026-10-03-plan-20-online-payments.md`; the code is in
  `backend/etqan/gateways`, `backend/etqan/billing`, `dashboard/src/features/gateways`);
- B3c, `docs/superpowers/specs/2026-10-03-b3c-paypal-design.md`, as built by **Plan 22**
  (`docs/superpowers/plans/2026-10-03-plan-22-paypal.md`): `services/completion.py` (`finish`),
  `services/captures.py` (`still_payable`, `capture_checkout`, `cancel_checkout`, `complete_paypal`), the
  capture and cancel routes, `etqan.platform.currency.to_decimal_string`;
- B3a (donations through `finance.services`), Plan 6 billing, Plan 12a roles, Plan 13 feature switches.

Ledger decisions (the ledger's own D13, D16, D17, D18; not this plan's numbered decisions below) this slice implements: D13 (purposes and `start_checkout`), D16 (revenue includes
standalone payments), D17 (anonymous access to link checkouts, public routes), D18 (SUB-006 lives in billing).

**B3c is built before this plan runs.** Plan 22's names are used as written. Task 5 changes three of its
files; before editing each, read the built file and keep its shape. Where the built code differs from Plan 22,
the built code wins and the edit is made in its spirit.

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), and the meta repo (trunk `master`).
  `marketing/` is not touched.
- **Branch `feat/b3g-links-records`.** The orchestrator creates it before Task 1, once B3b and B3c have
  merged: in the meta worktree and in `backend/` and `dashboard/`, `git fetch origin` then
  `git switch -c feat/b3g-links-records` off `origin/master` (meta) or `origin/main` (submodules). Check
  `git -C backend branch --show-current` and `git -C dashboard branch --show-current` before Task 1 and
  before Task 8.
- **Never run any `git submodule` command.** This worktree's submodules are worktrees of the main
  checkout's.
- **Never use bare `git stash`.**
- **Commits:** Conventional Commits, ending with the `Co-Authored-By:` line of the implementer's own
  session attribution. Commit in the repo the change lives in (`git -C backend …`, `git -C dashboard …`),
  never with `cd`, and never the submodule pointers in meta. Meta commits use explicit paths, never `-a`.

**Shared lists:** add lines only **below** the existing `── phase B3 ──` marker line. Never paste a second
marker line. A snippet below that starts with the marker line means "insert after the existing marker". The
marked lists this slice touches:
- the access `RESOURCES` (`backend/etqan/access/registry.py`): `payment_link`;
- `backend/pyproject.toml`'s B3 contracts block (the identity/academy refinement of G-22);
- `seed_academy` (`backend/etqan/tenants/management/commands/seed_dev.py`), data in
  `backend/etqan/tenants/seeds/gateways.py`;
- `NAV_ITEMS` (`dashboard/src/features/shell/nav.ts`);
- `config/api_router.py` needs nothing: billing's and gateways' routers already exist.

**Lists without markers.** These change in this slice: add to them, and change existing rows only where this
plan says. Expect rebase conflicts there and keep both sides.
- Backend:
  - `etqan/platform/features.py`: `payment_links` and `payment_receipts` flip in place (they sit above the
    markers, as `_later` rows), as plain `Feature(...)` rows like `online_payments` (`_built()` has no
    `requires`);
  - `etqan/platform/tests/test_features.py` (`BUILT`, the unbuilt count 27 → 25);
  - `etqan/access/tests/test_routes.py` (`ROUTES`, `FEATURES`, `FEATURE_WORDS`, `SELF_SERVICE`);
  - `etqan/access/tests/test_registry.py` (resource count +1);
  - `config/settings/base.py`: `DEFAULT_THROTTLE_RATES` gains `payment_link`;
  - billing's `Resource("payment", …)` line, whose `in_use` already carries `update` from Plan 20.
- Dashboard:
  - `features/identity/schemas.ts` (`FeatureCode`), `features/finance/landing.ts` (the `/billing` landing
    order), `features/shell/nav.test.ts`, `routes/permissions.test.ts` (`FEATURE_SCREENS`, `FEATURE_WORDS`);
  - the tests whose exact payloads change on purpose: billing's payment payload tests (`invoice_id` becomes
    `invoice`, plus `currency`, `customer`, `editable`, `deletable`), and the dashboard's `Payment` fixtures.

New translations go in `dashboard/src/locales/{en,ar}/gateways.json` and `billing.json` (B3's areas). Only en
and ar (G-23). **Arabic strings are real Arabic**: the locales test fails when an `ar` value equals its `en`
value (brand words such as "Stripe" and "PayPal" are the only exceptions). Say "إلكتروني" for "online".

**Features:** `payment_links` (requires `online_payments`) and `payment_receipts` (requires `invoices`) become
built, `default=False`. Completions keep working with either off (G-20).

**Backend commands.** Run them from the meta worktree, inside this stream's stack, which must be up
(`just dev-backend`). Load the stream's ports first:
```bash
set -a && . ./.env.stream && set +a
DJ="docker compose -f docker-compose.local.yml exec -T django"
```
- Tests: `$DJ pytest etqan/billing -q` (or any path). Add `--create-db` once after each task that adds a
  migration (Tasks 1, 3 and 4).
- Migrations: `$DJ python manage.py makemigrations gateways --name payment_link` (Task 4 and 3 name theirs).
- Format: `$DJ sh -c 'ruff check --fix . && ruff format .'`
- Verify: `$DJ sh -c 'ruff check . && ruff format --check . && lint-imports && pytest -q --cov=etqan'`
  (the same as `just test-backend`, which the gates task runs).
- **Run every test command in the foreground.** Background pytest runs share the stack's test database and
  collide.
- Never run `manage.py`, `migrate` or e2e any other way. `.env.stream` is what points them at this stream's
  database.
- **Lint:**
  - Watch `PLR0913`. Keyword-only signatures that mirror an API body carry
    `# noqa: PLR0913 -- <reason>`, as billing does.
  - No U+2212 minus or other ambiguous Unicode in Python strings or comments. Write "minus" or `-`.
- **Facts the tests rely on (Plans 6, 20 and 22):**
  - `gateways/tests/conftest.py` pins every clock to Monday 1 June 2026, 08:00 UTC through `world`;
    `admin`, `invoice(...)`, `online_on`, `stripe_on`, `parent_of_world`, `as_user(user)` and (B3c)
    `paypal_on`, `paypal_checkout(...)` exist there.
  - The test academy's `default_currency` is **USD**; scheduling's `world` package is EGP.
    `world.student` is a `User`; its `.id` is what billing's `student_id` and this slice's API `student` take.
  - `config.settings.test` has `GATEWAYS_SIMULATE = True`: a test-mode account's checkouts are simulated, and
    nothing real is ever called.
  - `respx_mock` fails any HTTP request no route mocks; the PayPal fakes are
    `gateways/tests/paypal_fakes.py` (`token_ok`, `ORDERS`, `an_order`, `a_capture`, `refused`).

**Dashboard commands.** Dashboard tests run in the compose `dashboard` service:
```bash
set -a; . ./.env.stream; set +a
DASH="docker compose -f docker-compose.local.yml run --rm"
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm test:coverage
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm vitest run src/features/gateways
```
`just test-frontend` is `tsc --noEmit` only; it does not run tests.
- Format and lint: `pnpm exec biome check --write src e2e` and `pnpm lint` (the same `$DASH dashboard`
  prefix). `pnpm lint` includes the colour check: semantic tokens only (`text-destructive`,
  `text-muted-foreground`, `text-success`, …), no hex literals and no Tailwind palette utilities, not even in
  comments.
- **New route files** are picked up by the TanStack Router plugin. Regenerate `src/routeTree.gen.ts` with
  `pnpm exec vite build` before `tsc`; it is generated, so never hand-edit it.
- **Pristine test output:** a test file that switches the language resets it in
  `afterEach(async () => { await act(async () => { await i18n.changeLanguage("en"); }); })`;
  `vitest run <dir> 2>&1 | grep -c "not wrapped in act"` must print 0 for the files this slice adds.
- **Arabic tests:** when a filter `<option>` repeats a table's text, query it
  `within(screen.getByRole("table"))`.
- **Reuse instead of copying:** `src/features/finance/shared.tsx` (`useListParams`, `pageCount`,
  `DateFilter`, `SearchBox`), `src/components/ExportButton.tsx`, `src/components/Confirm.tsx`, billing's
  `Money`, `errorText`, `applyServerErrors` and `useFieldError`.

**Gates before queuing:** `just test`, `just lint` and `just e2e` against this stream's stack; backend coverage
≥ 80 %; dashboard lines and statements ≥ 80, branches and functions ≥ 70.

**Money:** integer minor units plus an ISO 4217 currency, never summed across currencies. Stored instants are
UTC.

## Decisions (gaps the spec left, or departures it needed)

| # | Decision |
|---|---|
| D1 | **The start route.** Spec G-15 says the generic `POST gateways/checkouts/` cannot start a link checkout. The route is `POST gateways/checkouts/start/` (Plan 20 D1). The behaviour is the same: a link purpose's `prepare` answers 404 when `params` carries no matching token, and that route passes no params. |
| D2 | **The payment migration is three files, one per spec step** (`0004_payment_standalone_columns`, `0005_payment_currency_fill`, `0006_payment_currency_required`). Postgres refuses `ALTER TABLE` on a table with pending trigger events in the same transaction as an `UPDATE`, and Django wraps each migration in one transaction. The steps and their order are the spec's. `SubscriptionTerms` is `0007`. |
| D3 | **`customer_email` is an `EmailField` (254), not 30.** Spec §3.1 writes "`customer_email` and `customer_phone` (≤ 30)"; 30 characters would truncate real addresses. The phone is ≤ 30. |
| D4 | **Gateways may read `identity.services` and `academy.services`.** G-22 grants identity only, but §4.2 says the link's currency defaults to the academy's, which only `academy.services.get_settings().default_currency` knows. Both are services, never models. The first contract drops `etqan.identity` and `etqan.academy` from its forbidden list, and a new contract forbids gateways from their models, api and scopes. |
| D5 | **G-12 needs a switch in the fee rule.** B3b's `fee_for` charges only while `fee_enabled` is on. A link's `add_fee` alone must decide (always at the current `fee_basis_points`). `Prepared` gains `use_switch: bool = True` and `fee_for` gains `use_switch: bool = True`; link purposes set `use_switch=False`. Invoices are unchanged. |
| D6 | **Purposes carry `public`.** `register_purpose(name, *, prepare, complete, public=False)` and `is_public_purpose(name)`. G-15 keys anonymous access on the purpose, and B7 registers its own purposes the same way. A registration with a different `public` flag is "a different duplicate" and raises `ImproperlyConfigured`, as B3b's rule says. |
| D7 | **The still-payable re-check passes `RECHECK = {"recheck": True}` as `params`** (G-14). Only gateways' own code can build it: the public view passes `{"token": …}` and the generic route passes none, so a link purpose's `prepare` accepts a call only with a matching token or `recheck`. |
| D8 | **Anonymous starts.** `start_checkout(..., user=None)`: the reuse tuple uses `getattr(user, "pk", None)`, `created_by` stays null. A second anonymous start for the same link at the same price reuses the pending checkout (B-8), so a payer who reloads is sent to the same session. |
| D9 | **A link checkout's routes are open by purpose.** A new permission class `AuthenticatedOrPublicCheckout` answers anyone for a checkout whose purpose is public and everyone else exactly as `IsAuthenticated` did. `checkout_for` (status, capture, cancel) and `simulate` apply the same rule. B3c's `CaptureView` and `CancelView` switch to it. |
| D10 | **Non-atomic views carry both marks.** The public checkout view has `atomic_request = False` and the `transaction.non_atomic_requests` wrapper in `urls.py` (the route-walk test in `platform/tests/test_drf.py` enforces both). Plan 22's `CaptureView` and `CancelView` have the wrapper but no `atomic_request = False`; Task 5 adds it if the built code still lacks it. |
| D11 | **`LinkInfo.student_id` is the `StudentProfile` pk** (what `Payment.student` stores). The API's `student` is the user id, as in billing's invoice API; `links.create_link(student_id=<user id>)` resolves it. |
| D12 | **The payment row's `customer` also carries `email` and `phone`** (additive to spec §4.1) so the edit dialog can prefill them. |
| D13 | **The return page needs no new flag.** It already offers a back link only for an `invoice` checkout, so a link checkout shows its status only (G-15); the checkout status payload is unchanged. |
| D14 | **Seeds** go under `seed_academy`'s B3 marker (the spec is right; `seed_dev` only calls it). A step that cannot run because its provider is not enabled (a PayPal-less academy) is skipped. |
| D15 | **Token compare is on bytes** (`hmac.compare_digest` raises `TypeError` for a non-ASCII `str`), and a token that is not 1 to 32 characters of `[A-Za-z0-9_-]` (`secrets.token_urlsafe`'s alphabet) is a 404 before any query (a NUL in a query string is a 500). |
| D16 | **`gateways.link_closed` (409)** answers a cancel of a non-open link and a public checkout POST for one. The public GET answers 200 with `payable: false` instead, so the page can say why. |
| D17 | **The three `/pay/*` pages render in a plain frame** (`PublicFrame`), outside `_authed`'s shell and sign-in guard. `ReturnPage` keeps `useMe()`: for an anonymous visitor its 401 resolves to no data, which the page treats as "not office" and ignores. |

## Review Focus

Inputs the spec implies but names no test for. Each one has a test in the task named.

1. **Two payers, one link.** Two checkouts for one link both complete: the first becomes the record and the
   link `paid`; the second is `applied=false` with attention `link_closed`, the purpose is not called, and no
   second payment or donation exists. Task 6.
2. **A token that is not a token:** non-ASCII, 33+ characters, a trailing space. The public routes answer 404,
   never 500; a token mismatch through the generic start route is 404. Task 6.
3. **The fee setting changes after the link is made.** Turning `fee_enabled` off later still charges a link
   created with `add_fee=true`, at the current `fee_basis_points`; a link created with `add_fee=false` never
   pays one. Task 5.
4. **A registered student is deactivated after the link exists.** The link still pays and the record keeps the
   student. Task 6.
5. **A transaction number that already exists:** a standalone record whose `(method, transaction_number)`
   equals an invoice payment's is a 400 on `transaction_number`, on create and on edit; two online
   completions of one number apply once. Tasks 2 and 6.

Also covered where they arise: a donation link while `donations` is off (Tasks 4 and 6), a payer name with
markup rendered escaped (Task 8), and `payment_receipts` off with an existing standalone record (Task 2).

## File structure

**Backend (`backend/`)**

| Path | Responsibility |
|---|---|
| `etqan/billing/models.py` (+ migrations `0004`, `0005`, `0006`, `0007`) | nullable `Payment.invoice`, `currency`, customer fields, check constraint, index; `SubscriptionTerms` |
| `etqan/billing/services/payments.py` | G-5: currency on every payment, no-invoice delete and refund, `record_link_payment` |
| `etqan/billing/services/records.py` | standalone records: create, edit, list, filter, G-2, G-6 |
| `etqan/billing/services/terms.py` | SUB-006 terms |
| `etqan/billing/services/link_purpose.py` | the `payment_link` purpose (public) |
| `etqan/billing/services/summary.py`, `api/payloads.py`, `api/serializers.py`, `api/views.py`, `api/urls.py` | revenue by `Payment.currency`; the one payment row; record and terms routes |
| `etqan/gateways/models.py` (+ migration) | `PaymentLink` |
| `etqan/gateways/services/links.py` | links: create, cancel, list, `link_for`, `LinkInfo`, public view, `start_link_checkout`, `LINK_PURPOSES` |
| `etqan/gateways/services/purposes.py`, `fees.py`, `checkouts.py`, `completion.py`, `captures.py`, `simulator.py`, `__init__.py` | `public`, `use_switch`, anonymous starts, the link lock, the re-check, public simulate |
| `etqan/gateways/api/{permissions,serializers,payloads,views,urls}.py` | `AuthenticatedOrPublicCheckout`; link admin and public routes; checkouts CSV |
| `etqan/finance/services/link_purpose.py`, `apps.py` | the `donation_link` purpose (public) |
| `etqan/platform/features.py`, `etqan/access/registry.py`, `config/settings/base.py`, `pyproject.toml` | features, resource, throttle scope, import contracts |
| `etqan/tenants/seeds/gateways.py`, `seed_dev.py` | demo link and record seeds |

**Dashboard (`dashboard/`)**

| Path | Responsibility |
|---|---|
| `src/features/gateways/linkSchemas.ts`, `linksApi.ts`, `linkQueries.ts` | link types, forms, calls, hooks |
| `src/features/gateways/PublicFrame.tsx`, `PublicLinkPage.tsx` | the public pay page and its frame |
| `src/features/gateways/PaymentLinksPage.tsx`, `LinkDialog.tsx` | Billing → Payment links |
| `src/features/gateways/errors.ts`, `ReturnPage.test.tsx`, `CheckoutsList.tsx` | link error codes; the return page's test for a link checkout; the CSV button |
| `src/features/billing/{schemas,api,queries}.ts`, `PaymentRecordsPage.tsx`, `RecordDialog.tsx`, `SubscriptionTermsCard.tsx`, `InvoicePage.tsx` | records, terms, the card |
| `src/routes/pay.return.tsx`, `pay.simulate.$checkoutId.tsx`, `pay.link.$token.tsx` | the public routes (the first two move out of `_authed`) |
| `src/routes/_authed/billing.links.tsx`, `billing.payments.tsx` | the two admin pages |
| `src/features/identity/schemas.ts`, `finance/landing.ts`, `shell/nav.ts`, `routes/permissions.test.ts` | wiring |
| `src/locales/{en,ar}/gateways.json`, `billing.json`, `src/test/{gateways,billing}-fixtures.ts` | strings and fixtures |
| `e2e/b3-payment-links.spec.ts` | the journey through Caddy |

---
### Task 1: Billing — payments without an invoice (model, migrations, G-5, revenue)

**Files:**
- Modify: `backend/etqan/billing/models.py`
- Create: `backend/etqan/billing/migrations/0004_payment_standalone_columns.py`, `0005_payment_currency_fill.py`, `0006_payment_currency_required.py`
- Modify: `backend/etqan/billing/services/payments.py`, `services/summary.py`, `services/__init__.py`
- Modify: `backend/etqan/billing/api/payloads.py`, `api/views.py` (the prefetch only)
- Modify: existing billing tests that read `invoice_id` from a payment payload
- Test: `backend/etqan/billing/tests/test_standalone.py`

**Interfaces:**
- Consumes: Plan 6/20 billing: `rules.lock`, `rules.save`, `payments.ONLINE_METHODS`, `refund_payment`, `delete_payment`, `record_online_payment`.
- Produces:
  - `Payment.invoice` nullable; `Payment.currency` (3 letters, required); `Payment.customer_type` (`student` | `unregistered`, default `student`); `Payment.student` (→ `identity.StudentProfile`, nullable, `PROTECT`); `Payment.customer_name` (≤ 120), `customer_email` (254), `customer_phone` (≤ 30), all blank by default
  - constraint `billing_payment_has_customer`; index on `(currency, paid_on)`
  - `Payment.CustomerType` choices
  - `payloads.payment_row(payment, *, is_admin)` now answers `{id, customer: {type, name, student_id, email, phone}, invoice: {id, number} | null, transaction_number, reference, method, amount_minor, fee_minor, currency, status, paid_on, notes, refunded_at, recorded_by, created_at, editable, deletable}` (`notes` and `recorded_by` for the office only)
  - `revenue_between` groups by `Payment.currency`

- [ ] **Step 1: Write the failing tests**

`backend/etqan/billing/tests/test_standalone.py`:

```python
"""B3g G-1, G-3 to G-5: a payment may have no invoice; every payment has its
own currency; revenue counts both."""

from datetime import date

import pytest
from django.db import IntegrityError
from django.db import connection
from django.db import transaction
from django.db.migrations.executor import MigrationExecutor

from etqan.billing import services
from etqan.billing.api import payloads
from etqan.billing.models import Payment
from etqan.billing.tests.test_invoices import invoice_for
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError

pytestmark = pytest.mark.django_db
JUNE = (date(2026, 6, 1), date(2026, 7, 1))


def standalone(**fields) -> Payment:
    values = {
        "invoice": None,
        "amount_minor": 1000,
        "currency": "EGP",
        "method": "cash",
        "paid_on": date(2026, 6, 1),
        "customer_type": "unregistered",
        "customer_name": "Abu Khalid",
    }
    return Payment.objects.create(**{**values, **fields})


def refused(**fields):
    with pytest.raises(IntegrityError), transaction.atomic():
        standalone(**fields)


def test_a_standalone_record_needs_a_customer(world):
    profile = identity_services.get_student_profile(world.student.id)
    assert standalone().pk
    assert standalone(customer_type="student", student=profile, customer_name="").pk
    refused(customer_type="student", student=None, customer_name="")
    refused(customer_name="")
    refused(student=profile)  # an unregistered customer has no student


def test_an_invoice_payment_needs_no_customer_fields(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000, currency="EGP")
    payment = services.add_payment(
        bill, amount_minor=400, method="cash", paid_on=date(2026, 6, 1), by=admin
    )
    assert (payment.currency, payment.customer_type, payment.student_id) == (
        "EGP",
        "student",
        None,
    )


def test_an_invoice_payment_takes_the_invoices_currency(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000, currency="USD")
    paid = services.add_payment(
        bill, amount_minor=100, method="cash", paid_on=date(2026, 6, 1), by=admin
    )
    online = services.record_online_payment(
        bill, amount_minor=200, fee_minor=10, method="stripe", transaction_number="pi_1"
    )
    assert (paid.currency, online.currency) == ("USD", "USD")


def test_str_shows_the_currency():
    assert str(standalone(amount_minor=1500, currency="USD")) == "Payment<USD, 1500>"


def test_deleting_a_manual_standalone_record_recalculates_nothing(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000)
    record = standalone()
    services.delete_payment(record)
    assert not Payment.objects.filter(pk=record.pk).exists()
    assert services.invoices_queryset().get(pk=bill.pk).status == "unpaid"


def test_an_online_standalone_record_is_never_deleted():
    record = standalone(method="stripe", transaction_number="pi_9")
    with pytest.raises(ConflictError) as refused_:
        services.delete_payment(record)
    assert refused_.value.code == "billing.online_payment"


def test_deleting_a_manual_invoice_payment_still_recalculates(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000)
    payment = services.add_payment(
        bill, amount_minor=1000, method="cash", paid_on=date(2026, 6, 1), by=admin
    )
    assert services.invoices_queryset().get(pk=bill.pk).status == "paid"
    services.delete_payment(payment)
    assert services.invoices_queryset().get(pk=bill.pk).status == "unpaid"


def test_refunding_a_standalone_record_marks_it_and_touches_no_invoice(admin):
    record = standalone(method="stripe", transaction_number="pi_2", fee_minor=50)
    done = services.refund_payment(record, by=admin)
    assert (done.status, done.refunded_by_id) == ("refunded", admin.pk)
    with pytest.raises(ConflictError):
        services.refund_payment(record, by=admin)


def test_the_payment_row_has_one_shape_for_both_kinds(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000)
    on_invoice = services.add_payment(
        bill, amount_minor=300, method="cash", paid_on=date(2026, 6, 1), by=admin
    )
    row = payloads.payment_row(
        Payment.objects.select_related("invoice__student__user", "student__user").get(
            pk=on_invoice.pk
        ),
        is_admin=True,
    )
    assert row["invoice"] == {"id": bill.pk, "number": bill.number}
    assert row["customer"]["type"] == "student"
    assert row["customer"]["student_id"] == world.student.id
    assert (row["editable"], row["deletable"], row["currency"]) == (False, True, "EGP")
    assert "invoice_id" not in row
    free = standalone(customer_email="a@b.test", customer_phone="+201001234567")
    row = payloads.payment_row(free, is_admin=False)
    assert row["invoice"] is None
    assert row["customer"] == {
        "type": "unregistered",
        "name": "Abu Khalid",
        "student_id": None,
        "email": "a@b.test",
        "phone": "+201001234567",
    }
    assert (row["editable"], row["deletable"]) == (True, True)
    assert "notes" not in row
    online = payloads.payment_row(
        standalone(method="paypal", transaction_number="CAP-1"), is_admin=True
    )
    assert (online["editable"], online["deletable"]) == (False, False)


def test_revenue_counts_standalone_payments_per_payment_currency(world, admin):
    bill = invoice_for(world, admin, amount_minor=5000, currency="EGP")
    services.add_payment(
        bill, amount_minor=1000, method="cash", paid_on=date(2026, 6, 1), by=admin
    )
    standalone(amount_minor=700, currency="USD")
    standalone(amount_minor=200, fee_minor=50, method="stripe", transaction_number="a")
    gone = standalone(
        amount_minor=900, method="stripe", transaction_number="b", fee_minor=10
    )
    services.refund_payment(gone, by=admin)
    standalone(amount_minor=400, paid_on=date(2026, 7, 1))  # next month
    assert services.revenue_between(*JUNE) == [
        {"currency": "EGP", "amount_minor": 1250},
        {"currency": "USD", "amount_minor": 700},
    ]


@pytest.mark.django_db(transaction=True)
def test_the_migration_fills_currency_from_the_invoice_then_requires_it(world, admin):
    """G-1 / §3.1: step 2 copies each invoice payment's currency from its
    invoice; step 3 makes the column required."""
    bill = invoice_for(world, admin, amount_minor=1000, currency="USD")
    services.add_payment(
        bill, amount_minor=100, method="cash", paid_on=date(2026, 6, 1), by=admin
    )
    executor = MigrationExecutor(connection)
    latest = executor.loader.graph.leaf_nodes("billing")
    columns = ("billing", "0004_payment_standalone_columns")
    filled = ("billing", "0005_payment_currency_fill")
    try:
        executor.migrate([columns])
        with connection.cursor() as cursor:
            cursor.execute("UPDATE billing_payment SET currency = NULL")
            cursor.execute("SELECT count(*) FROM billing_payment WHERE currency IS NULL")
            assert cursor.fetchone()[0] == 1
        MigrationExecutor(connection).migrate([filled])
        with connection.cursor() as cursor:
            cursor.execute("SELECT currency FROM billing_payment")
            assert cursor.fetchall() == [("USD",)]
    finally:
        MigrationExecutor(connection).migrate(latest)
    with connection.cursor() as cursor, pytest.raises(IntegrityError):
        cursor.execute(
            "INSERT INTO billing_payment (amount_minor, method, paid_on, reference, notes,"
            " fee_minor, transaction_number, status, created_at, currency, customer_type,"
            " customer_name, customer_email, customer_phone)"
            " VALUES (1, 'cash', '2026-06-01', '', '', 0, '', 'completed', now(), 'EGP',"
            " 'student', '', '', '')"
        )
```

(If `MigrationExecutor` cannot run inside the pytest tenant schema in this repo, keep the first two
assertions' intent with a structural check on the migration modules instead: `0005`'s only operation is the
`RunSQL` whose SQL is the spec's `UPDATE`, and `0006`'s operations alter `currency` to non-null before adding
the constraint and index. Do not drop the test.)

Add to `test_summary.py`'s existing revenue test nothing; the new revenue test above covers G-4.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/billing/tests/test_standalone.py -q`
Expected: FAIL (`invoice` is not nullable, `currency` is not a field).

- [ ] **Step 3: The model**

`backend/etqan/billing/models.py`, in `Payment`:

```python
    class CustomerType(models.TextChoices):
        STUDENT = "student", "Student"
        UNREGISTERED = "unregistered", "Unregistered"

    # B3g G-1: null for a standalone record (a payment link, or one the office
    # recorded by hand with no invoice).
    invoice = models.ForeignKey(
        Invoice,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="payments",
    )
    # B3g G-1: every payment carries its own currency; an invoice payment takes
    # the invoice's.
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    customer_type = models.CharField(
        max_length=12, choices=CustomerType.choices, default=CustomerType.STUDENT
    )
    student = models.ForeignKey(
        "identity.StudentProfile",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    customer_name = models.CharField(max_length=120, blank=True, default="")
    customer_email = models.EmailField(blank=True, default="")
    customer_phone = models.CharField(max_length=30, blank=True, default="")
```

Replace the old `invoice = models.ForeignKey(...)` with the first block. In `Payment.Meta.constraints` add:

```python
            # G-1: an invoice payment, or a customer: a student, or an unregistered
            # person with a name.
            models.CheckConstraint(
                condition=Q(invoice__isnull=False)
                | Q(customer_type="student", student__isnull=False)
                | (
                    Q(customer_type="unregistered", student__isnull=True)
                    & ~Q(customer_name="")
                ),
                name="billing_payment_has_customer",
            ),
```

and replace `indexes = [models.Index(fields=["paid_on"])]` with:

```python
        indexes = [
            models.Index(fields=["paid_on"]),
            models.Index(fields=["currency", "paid_on"]),
        ]
```

and `__str__`:

```python
    def __str__(self):
        return f"Payment<{self.currency}, {self.amount_minor}>"
```

- [ ] **Step 4: The three migrations (spec §3.1, D2)**

Generate once to see what Django wants, then replace the output with the three files below:
`$DJ python manage.py makemigrations billing --name payment_standalone --dry-run -v 3` (read only; nothing is
written).

`backend/etqan/billing/migrations/0004_payment_standalone_columns.py`:

```python
"""B3g G-1, step 1: the new columns (currency nullable for now) and a
nullable invoice."""

import django.core.validators
import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("billing", "0003_payment_fee_minor_payment_refunded_at_and_more"),
        ("identity", "0016_alter_user_role"),
    ]

    operations = [
        migrations.AlterField(
            model_name="payment",
            name="invoice",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="payments",
                to="billing.invoice",
            ),
        ),
        migrations.AddField(
            model_name="payment",
            name="currency",
            field=models.CharField(
                max_length=3,
                null=True,
                validators=[django.core.validators.RegexValidator("^[A-Z]{3}$")],
            ),
        ),
        migrations.AddField(
            model_name="payment",
            name="customer_type",
            field=models.CharField(
                choices=[("student", "Student"), ("unregistered", "Unregistered")],
                default="student",
                max_length=12,
            ),
        ),
        migrations.AddField(
            model_name="payment",
            name="student",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="+",
                to="identity.studentprofile",
            ),
        ),
        migrations.AddField(
            model_name="payment",
            name="customer_name",
            field=models.CharField(blank=True, default="", max_length=120),
        ),
        migrations.AddField(
            model_name="payment",
            name="customer_email",
            field=models.EmailField(blank=True, default="", max_length=254),
        ),
        migrations.AddField(
            model_name="payment",
            name="customer_phone",
            field=models.CharField(blank=True, default="", max_length=30),
        ),
    ]
```

`backend/etqan/billing/migrations/0005_payment_currency_fill.py`:

```python
"""B3g G-1, step 2: every existing payment is an invoice payment; it takes
its invoice's currency. Runs in each academy's schema through
`migrate_schemas`."""

from django.db import migrations

FILL = (
    "UPDATE billing_payment p SET currency = i.currency "
    "FROM billing_invoice i WHERE p.invoice_id = i.id"
)


class Migration(migrations.Migration):
    dependencies = [("billing", "0004_payment_standalone_columns")]

    operations = [migrations.RunSQL(FILL, reverse_sql=migrations.RunSQL.noop)]
```

`backend/etqan/billing/migrations/0006_payment_currency_required.py`:

```python
"""B3g G-1, step 3: currency is required; the customer check and the
currency index."""

import django.core.validators
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("billing", "0005_payment_currency_fill")]

    operations = [
        migrations.AlterField(
            model_name="payment",
            name="currency",
            field=models.CharField(
                max_length=3,
                validators=[django.core.validators.RegexValidator("^[A-Z]{3}$")],
            ),
        ),
        migrations.AddConstraint(
            model_name="payment",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    ("invoice__isnull", False),
                    models.Q(("customer_type", "student"), ("student__isnull", False)),
                    models.Q(
                        ("customer_type", "unregistered"),
                        ("student__isnull", True),
                        models.Q(("customer_name", ""), _negated=True),
                    ),
                    _connector="OR",
                ),
                name="billing_payment_has_customer",
            ),
        ),
        migrations.AddIndex(
            model_name="payment",
            index=models.Index(
                fields=["currency", "paid_on"], name="billing_pay_currenc_idx"
            ),
        ),
    ]
```

Check there is no drift (the index name is Django's generated one; if the command prints a different name,
use it in `0006`): `$DJ python manage.py makemigrations --check --dry-run` prints "No changes detected".

- [ ] **Step 5: The services (G-5)**

`backend/etqan/billing/services/payments.py`:

- `add_payment`: in the `Payment(...)` call add `currency=locked.currency,`.
- `record_online_payment`: in the `Payment(...)` call add `currency=locked.currency,`.
- Replace `refund_payment` and `delete_payment`:

```python
@transaction.atomic
def refund_payment(payment: Payment, *, by) -> Payment:
    """Marked, not executed (phase B3-10): the payment stops counting and the
    invoice's status follows. A void invoice has no completed payments, so a
    refund can never reach one. A standalone record (B3g G-3) has no invoice:
    only its own row is locked and nothing is recalculated."""
    locked = rules.lock(payment.invoice) if payment.invoice_id else None
    fresh = Payment.objects.select_for_update().filter(pk=payment.pk).first()
    if fresh is None:
        raise NotFoundError("Payment", payment.pk)
    if fresh.status == Payment.Status.REFUNDED:
        raise ConflictError(
            "This payment is already refunded.", code="billing.already_refunded"
        )
    fresh.status = Payment.Status.REFUNDED
    fresh.refunded_at = clock.now()
    fresh.refunded_by = by
    fresh.save(update_fields=["status", "refunded_at", "refunded_by"])
    if locked is not None:
        _recalculate(locked)
    return fresh


@transaction.atomic
def delete_payment(payment: Payment) -> None:
    """For mistakes (spec §4.2). An invoice payment locks its invoice first, as
    when paying, and recalculates it; a standalone record has neither (B3g G-2)."""
    locked = rules.lock(payment.invoice) if payment.invoice_id else None
    if payment.method in ONLINE_METHODS:
        raise ConflictError(
            "An online payment is refunded, never deleted.",
            code="billing.online_payment",
        )
    deleted, _ = Payment.objects.filter(pk=payment.pk).delete()
    if not deleted:
        raise NotFoundError("Payment", payment.pk)
    if locked is not None:
        _recalculate(locked)
```

`backend/etqan/billing/services/summary.py`, `revenue_between`: replace
`.values(currency=F("invoice__currency"))` with `.values("currency")`.

- [ ] **Step 6: The payload**

`backend/etqan/billing/api/payloads.py`: add `from etqan.billing.services.payments import ONLINE_METHODS`
and replace `payment_row`:

```python
def _customer(payment) -> dict:
    """Whose payment it is: the invoice's student, the record's student, or the
    unregistered person named on it. Read ``payment`` with
    ``select_related("invoice__student__user", "student__user")``."""
    if payment.invoice_id is not None:
        student, kind = payment.invoice.student, "student"
    elif payment.customer_type == "student":
        student, kind = payment.student, "student"
    else:
        student, kind = None, "unregistered"
    return {
        "type": kind,
        "name": student.user.full_name if student else payment.customer_name,
        "student_id": student.user_id if student else None,
        "email": payment.customer_email,
        "phone": payment.customer_phone,
    }


def payment_row(payment, *, is_admin: bool) -> dict:
    invoice = payment.invoice
    online = payment.method in ONLINE_METHODS
    row = {
        "id": payment.pk,
        "customer": _customer(payment),
        "invoice": (
            {"id": invoice.pk, "number": invoice.number} if invoice is not None else None
        ),
        "transaction_number": payment.transaction_number,
        "reference": payment.reference,
        "method": payment.method,
        "amount_minor": payment.amount_minor,
        "fee_minor": payment.fee_minor,
        "currency": payment.currency,
        "status": payment.status,
        "paid_on": payment.paid_on,
        "refunded_at": payment.refunded_at,
        "created_at": payment.created_at,
        "notes": payment.notes,
        "recorded_by": _person(payment.recorded_by),
        # G-2: only a manual standalone record is edited; any manual one deleted.
        "editable": not online and payment.invoice_id is None,
        "deletable": not online,
    }
    if not is_admin:
        for field in STAFF_ONLY_PAYMENT_FIELDS:
            row.pop(field)
    return row
```

`backend/etqan/billing/api/views.py`: replace `PAYMENTS` with

```python
PAYMENTS = Prefetch(
    "payments",
    Payment.objects.select_related(
        "recorded_by", "invoice__student__user", "student__user"
    ),
)
```

`RefundView.post` and `PaymentDetailView.delete` change in Task 2. `invoice_detail`'s payments already come
from `invoice.payments.all()` (prefetched).

- [ ] **Step 7: Fix the tests that built a Payment or read `invoice_id`**

Run: `grep -rn "invoice_id" etqan/billing/tests etqan/gateways/tests etqan/finance/tests etqan/access/tests`
and `grep -rn "Payment(" etqan | grep -v migrations`. A payload assertion that read `invoice_id` now reads
`invoice` (`{"id": …, "number": …}`); a test that builds a `Payment` directly adds `currency=`.

Run: `$DJ pytest etqan/billing etqan/gateways etqan/finance etqan/access -q --create-db`
Expected: all pass.

- [ ] **Step 8: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/billing etqan/gateways etqan/finance etqan/access
git -C backend commit -m "feat(billing): payments without an invoice, with their own currency and customer"
```

---
### Task 2: Billing — payment records: services, API, CSV and refunds (G-2, G-3, G-6, G-20)

**Files:**
- Create: `backend/etqan/billing/services/records.py`
- Modify: `backend/etqan/billing/services/__init__.py`, `api/serializers.py`, `api/views.py`, `api/urls.py`
- Modify: `backend/etqan/platform/features.py` (`payment_receipts` built), `backend/etqan/platform/tests/test_features.py`
- Modify: `backend/etqan/access/tests/test_routes.py`
- Test: `backend/etqan/billing/tests/test_records.py`

**Interfaces:**
- Consumes: Task 1's `Payment` fields and `payloads.payment_row`; `rules.save`; `invoices.active_student(student_id) -> StudentProfile`; `academy_services.get_settings().default_currency`; `payments.MANUAL_PAYMENT_METHODS`, `ONLINE_METHODS`.
- Produces:
  - `services.payments_queryset() -> QuerySet[Payment]` (newest `paid_on` first, related rows selected)
  - `services.filter_payments(payments, *, method="", customer_type="", status="", currency="", paid_from=None, paid_to=None, has_invoice=None, q="") -> QuerySet[Payment]`
  - `services.create_record(*, customer_type, amount_minor, method, by, student_id=None, customer_name="", customer_email="", customer_phone="", currency=None, transaction_number="", reference="", paid_on=None, notes="") -> Payment`
  - `services.update_record(payment, **changes) -> Payment` (keys as `create_record`'s, minus `customer_type`, `by`)
  - `services.has_standalone_records() -> bool`
  - routes `GET/POST billing/payments/`, `GET/PATCH/DELETE billing/payments/<id>/`; `POST billing/payments/<id>/refund/` answers the payment row for a standalone record
  - feature `payment_receipts` built (`default=False`, requires `invoices`)

- [ ] **Step 1: Write the failing tests**

`backend/etqan/billing/tests/test_records.py`:

```python
"""B3g §4.1: payment records. G-2 (delete versus edit), G-3 (refund), G-6
(a unique transaction number), G-20 (the feature)."""

import csv
import io
from datetime import date

import pytest

from etqan.billing import services
from etqan.billing.models import Payment
from etqan.billing.tests.test_invoices import invoice_for
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
URL = "/api/v1/billing/payments/"


@pytest.fixture
def receipts_on(set_features):
    return set_features(invoices=True, payment_receipts=True)


def record(admin, **fields):
    values = {
        "customer_type": "unregistered",
        "customer_name": "Abu Khalid",
        "amount_minor": 1000,
        "method": "cash",
        "by": admin,
        "currency": "EGP",
    }
    return services.create_record(**{**values, **fields})


def test_an_unregistered_record_is_created_with_defaults(admin):
    payment = record(admin, customer_email="a@b.test")
    assert (payment.invoice_id, payment.recorded_by) == (None, admin)
    assert payment.paid_on == date(2026, 6, 1)  # billing's clock is pinned
    assert (payment.customer_name, payment.customer_email) == ("Abu Khalid", "a@b.test")


def test_the_currency_defaults_to_the_academys(admin):
    payment = record(admin, currency=None)
    assert payment.currency == "USD"  # the test academy's default


def test_a_student_record_needs_an_active_student(world, admin):
    payment = record(
        admin, customer_type="student", student_id=world.student.id, customer_name=""
    )
    assert payment.student.user_id == world.student.id
    with pytest.raises(ValidationError) as missing:
        record(admin, customer_type="student", customer_name="")
    assert missing.value.field == "student"
    with pytest.raises(ValidationError) as unknown:
        record(admin, customer_type="student", student_id=999_999, customer_name="")
    assert unknown.value.field == "student"


def test_an_unregistered_record_needs_a_name_and_no_student(world, admin):
    with pytest.raises(ValidationError) as nameless:
        record(admin, customer_name="  ")
    assert nameless.value.field == "customer_name"
    with pytest.raises(ValidationError) as both:
        record(admin, student_id=world.student.id)
    assert both.value.field == "student"


@pytest.mark.parametrize("method", ["stripe", "paypal", "bitcoin"])
def test_only_manual_methods_by_hand(admin, method):
    with pytest.raises(ValidationError) as refused:
        record(admin, method=method)
    assert refused.value.field == "method"


def test_a_future_date_is_refused(admin):
    with pytest.raises(ValidationError) as refused:
        record(admin, paid_on=date(2026, 6, 2))
    assert refused.value.field == "paid_on"


def test_review_focus_5_a_taken_transaction_number_is_a_400_on_create_and_edit(
    world, admin
):
    bill = invoice_for(world, admin, amount_minor=1000)
    services.record_online_payment(
        bill, amount_minor=100, fee_minor=0, method="stripe", transaction_number="t-1"
    )
    record(admin, transaction_number="t-1")  # another method: allowed
    first = record(admin, transaction_number="t-2")
    for call in (
        lambda: record(admin, transaction_number="t-2"),
        lambda: services.update_record(
            record(admin, transaction_number="t-3"), transaction_number="t-2"
        ),
    ):
        with pytest.raises(ValidationError) as taken:
            call()
        assert taken.value.field == "transaction_number"
    # Saving a record again with its own number is not a clash.
    assert services.update_record(first, transaction_number="t-2").pk == first.pk


def test_g2_only_a_manual_standalone_record_is_edited(world, admin):
    payment = record(admin)
    edited = services.update_record(payment, amount_minor=2500, notes="Corrected")
    assert (edited.amount_minor, edited.notes) == (2500, "Corrected")
    bill = invoice_for(world, admin, amount_minor=1000)
    on_invoice = services.add_payment(
        bill, amount_minor=100, method="cash", paid_on=date(2026, 6, 1), by=admin
    )
    online = record_online(admin)
    for target in (on_invoice, online):
        with pytest.raises(ConflictError) as refused:
            services.update_record(target, notes="x")
        assert refused.value.code == "billing.payment_not_editable"


def record_online(admin):
    return Payment.objects.create(
        invoice=None,
        amount_minor=500,
        currency="EGP",
        method="stripe",
        paid_on=date(2026, 6, 1),
        transaction_number="pi_77",
        customer_type="unregistered",
        customer_name="Online Payer",
    )


def test_editing_the_customer_keeps_the_kind_rules(world, admin):
    unregistered = record(admin)
    with pytest.raises(ValidationError) as blank:
        services.update_record(unregistered, customer_name="")
    assert blank.value.field == "customer_name"
    with pytest.raises(ValidationError) as student:
        services.update_record(unregistered, student_id=world.student.id)
    assert student.value.field == "student"
    of_student = record(
        admin, customer_type="student", student_id=world.student.id, customer_name=""
    )
    with pytest.raises(ValidationError) as named:
        services.update_record(of_student, customer_name="Someone")
    assert named.value.field == "customer_name"
    # An edit that touches no customer field never re-checks the student.
    assert services.update_record(of_student, amount_minor=5).amount_minor == 5


def test_the_list_filters_and_orders_newest_first(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000)
    services.add_payment(
        bill, amount_minor=100, method="bank_transfer", paid_on=date(2026, 5, 1), by=admin
    )
    record(admin, paid_on=date(2026, 5, 20), customer_name="Zed", currency="USD")
    newest = record(admin, paid_on=date(2026, 5, 30), method="instapay")
    refunded = record(admin, paid_on=date(2026, 5, 10), customer_name="Gone")
    services.refund_payment(refunded, by=admin)

    def listed(**filters):
        rows = services.filter_payments(services.payments_queryset(), **filters)
        return [p.pk for p in rows]

    everything = listed()
    assert everything[0] == newest.pk and len(everything) == 4
    assert len(listed(has_invoice=True)) == 1
    assert len(listed(has_invoice=False)) == 3
    assert len(listed(customer_type="student")) == 1  # the invoice payment's
    assert len(listed(customer_type="unregistered")) == 3
    assert listed(method="instapay") == [newest.pk]
    assert listed(status="refunded") == [refunded.pk]
    assert len(listed(currency="USD")) == 1
    assert len(listed(paid_from=date(2026, 5, 20), paid_to=date(2026, 5, 30))) == 2
    assert len(listed(q="zed")) == 1
    assert len(listed(q=bill.number)) == 1
    assert len(listed(q=world.student.full_name[:4])) == 1


# ---- the API --------------------------------------------------------------


def post(client, **fields):
    body = {
        "customer_type": "unregistered",
        "customer_name": "Abu Khalid",
        "amount_minor": 1000,
        "method": "cash",
        "currency": "EGP",
        **fields,
    }
    return client.post(URL, body, format="json")


def test_the_feature_gates_the_list_and_create(api_for, set_features):
    set_features(invoices=True, payment_receipts=False)
    admin = api_for("admin")
    assert admin.get(URL).status_code == 404
    assert post(admin).status_code == 404


def test_create_list_edit_refund_and_delete_over_the_api(api_for, receipts_on):
    admin = api_for("admin")
    created = post(admin, customer_email="a@b.test", transaction_number="x-1")
    assert created.status_code == 201, created.json()
    row = created.json()
    assert row["invoice"] is None
    assert (row["editable"], row["deletable"], row["method"]) == (True, True, "cash")
    assert row["customer"]["name"] == "Abu Khalid"
    page = admin.get(URL).json()
    assert [r["id"] for r in page["results"]] == [row["id"]]
    assert admin.get(f"{URL}{row['id']}/").json()["id"] == row["id"]
    edited = admin.patch(f"{URL}{row['id']}/", {"amount_minor": 1500}, format="json")
    assert (edited.status_code, edited.json()["amount_minor"]) == (200, 1500)
    refunded = admin.post(f"{URL}{row['id']}/refund/")
    assert (refunded.status_code, refunded.json()["status"]) == (200, "refunded")
    assert admin.delete(f"{URL}{row['id']}/").status_code == 204


def test_a_taken_transaction_number_is_a_400_on_that_field(api_for, receipts_on):
    admin = api_for("admin")
    assert post(admin, transaction_number="x-1").status_code == 201
    again = post(admin, transaction_number="x-1")
    assert again.status_code == 400
    assert "transaction_number" in str(again.json())


def test_a_non_editable_record_is_a_409(api_for, receipts_on, world, admin):
    bill = invoice_for(world, admin, amount_minor=1000)
    pay = services.add_payment(
        bill, amount_minor=100, method="cash", paid_on=date(2026, 6, 1), by=admin
    )
    resp = api_for("admin").patch(f"{URL}{pay.pk}/", {"notes": "x"}, format="json")
    assert (resp.status_code, resp.json()["code"]) == (409, "billing.payment_not_editable")


def test_deleting_an_online_record_is_a_409_and_a_manual_invoice_payment_is_not(
    api_for, receipts_on, world, admin
):
    online = record_online(admin)
    resp = api_for("admin").delete(f"{URL}{online.pk}/")
    assert (resp.status_code, resp.json()["code"]) == (409, "billing.online_payment")


def test_deleting_works_with_payment_receipts_off_for_invoice_payments(
    api_for, set_features, world, admin
):
    set_features(invoices=True, payment_receipts=False)
    bill = invoice_for(world, admin, amount_minor=1000)
    pay = services.add_payment(
        bill, amount_minor=100, method="cash", paid_on=date(2026, 6, 1), by=admin
    )
    assert api_for("admin").delete(f"{URL}{pay.pk}/").status_code == 204


@pytest.mark.parametrize(
    "query",
    [
        "method=bitcoin",
        "customer_type=robot",
        "status=lost",
        "currency=EGPP",
        "paid_from=yesterday",
        "paid_to=2026-13-01",
        "has_invoice=maybe",
    ],
)
def test_a_bad_filter_is_a_400(api_for, receipts_on, query):
    resp = api_for("admin").get(f"{URL}?{query}")
    assert resp.status_code == 400


def test_the_csv_follows_the_export_switch(api_for, set_features):
    set_features(invoices=True, payment_receipts=True, export=True)
    admin = api_for("admin")
    post(admin, customer_name="=cmd", amount_minor=700, transaction_number="c-1")
    resp = admin.get(f"{URL}?format=csv")
    assert resp.status_code == 200
    rows = list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))
    assert rows[0] == [
        "Date",
        "Customer",
        "Customer type",
        "Invoice",
        "Method",
        "Transaction number",
        "Amount (minor units)",
        "Fee (minor units)",
        "Currency",
        "Status",
    ]
    assert rows[1][1] == "'=cmd"  # defused against formula injection
    assert rows[1][6:9] == ["700", "0", "EGP"]
    set_features(export=False)
    assert api_for("admin").get(f"{URL}?format=csv").status_code == 404


def test_a_family_is_refused_and_a_standalone_record_never_reaches_one(
    api_for, receipts_on, world
):
    from etqan.billing.tests.conftest import make_parent  # noqa: PLC0415

    admin = api_for("admin")
    assert post(admin).status_code == 201
    parent = make_parent("Omar", world.student)
    from rest_framework.test import APIClient  # noqa: PLC0415

    client = APIClient()
    client.force_login(parent)
    assert client.get(URL).status_code == 403
    assert client.post(URL, {}, format="json").status_code == 403
    # Family scopes work through invoices: the record is in none of them.
    assert client.get("/api/v1/billing/invoices/").json()["results"] == []


def test_a_record_stays_listed_when_receipts_are_switched_off_later(
    api_for, set_features
):
    set_features(invoices=True, payment_receipts=True)
    admin = api_for("admin")
    created = post(admin).json()
    set_features(payment_receipts=False)
    assert api_for("admin").get(URL).status_code == 404
    assert Payment.objects.filter(pk=created["id"]).exists()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/billing/tests/test_records.py -q`
Expected: FAIL (`services.create_record` is not defined).

- [ ] **Step 3: The service**

`backend/etqan/billing/services/records.py`:

```python
"""Standalone payment records: payments with no invoice (B3g G-1 to G-3,
G-6). Created and edited by the office by hand (manual methods only); online
ones arrive through a payment-link checkout and are never edited."""

from datetime import date

from django.db import IntegrityError
from django.db import transaction
from django.db.models import Q
from django.db.models import QuerySet

from etqan.academy import services as academy_services
from etqan.billing import clock
from etqan.billing.models import Payment
from etqan.billing.services import rules
from etqan.billing.services.invoices import active_student
from etqan.billing.services.payments import MANUAL_PAYMENT_METHODS
from etqan.billing.services.payments import ONLINE_METHODS
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency

MANUAL = frozenset(value for value, _ in MANUAL_PAYMENT_METHODS)
STUDENT = Payment.CustomerType.STUDENT
UNREGISTERED = Payment.CustomerType.UNREGISTERED
TRANSACTION_UNIQUE = "billing_payment_transaction_unique"


def payments_queryset() -> QuerySet[Payment]:
    """Newest ``paid_on`` first; everything `payloads.payment_row` reads."""
    return Payment.objects.select_related(
        "invoice__student__user", "student__user", "recorded_by"
    ).order_by("-paid_on", "-id")


def has_standalone_records() -> bool:
    return Payment.objects.filter(invoice__isnull=True).exists()


def filter_payments(  # noqa: PLR0913 -- keyword-only; mirrors the list's query (B3g §4.1)
    payments: QuerySet[Payment],
    *,
    method: str = "",
    customer_type: str = "",
    status: str = "",
    currency: str = "",
    paid_from: date | None = None,
    paid_to: date | None = None,
    has_invoice: bool | None = None,
    q: str = "",
) -> QuerySet[Payment]:
    if method:
        payments = payments.filter(method=method)
    if customer_type == STUDENT:
        # An invoice payment's customer is the invoice's student.
        payments = payments.filter(Q(invoice__isnull=False) | Q(customer_type=STUDENT))
    elif customer_type == UNREGISTERED:
        payments = payments.filter(invoice__isnull=True, customer_type=UNREGISTERED)
    if status:
        payments = payments.filter(status=status)
    if currency:
        payments = payments.filter(currency=currency)
    if paid_from is not None:
        payments = payments.filter(paid_on__gte=paid_from)
    if paid_to is not None:
        payments = payments.filter(paid_on__lte=paid_to)
    if has_invoice is not None:
        payments = payments.filter(invoice__isnull=not has_invoice)
    if q.strip():
        text = q.strip()
        payments = payments.filter(
            Q(invoice__student__user__full_name__icontains=text)
            | Q(student__user__full_name__icontains=text)
            | Q(customer_name__icontains=text)
            | Q(transaction_number__icontains=text)
            | Q(invoice__number__icontains=text)
        )
    return payments


def _check_method(method: str) -> None:
    if method not in MANUAL:
        raise ValidationError("Choose a manual payment method.", field="method")


def _check_date(paid_on: date) -> None:
    if paid_on > clock.today():
        raise ValidationError("A payment can't be dated in the future.", field="paid_on")


def _check_unique(method: str, number: str, exclude_pk: int | None = None) -> None:
    taken = Payment.objects.filter(method=method, transaction_number=number)
    if number and taken.exclude(pk=exclude_pk).exists():
        raise ValidationError(
            "This transaction number is already recorded.", field="transaction_number"
        )


def _save(payment: Payment) -> None:
    """The unique constraint is the last word under a race (G-6)."""
    try:
        with transaction.atomic():
            rules.save(payment)
    except IntegrityError as exc:
        diag = getattr(exc.__cause__, "diag", None)
        if getattr(diag, "constraint_name", None) != TRANSACTION_UNIQUE:
            raise
        raise ValidationError(
            "This transaction number is already recorded.", field="transaction_number"
        ) from None


@transaction.atomic
def create_record(  # noqa: PLR0913 -- keyword-only; mirrors the API body (B3g §4.1)
    *,
    customer_type: str,
    amount_minor: int,
    method: str,
    by,
    student_id: int | None = None,
    customer_name: str = "",
    customer_email: str = "",
    customer_phone: str = "",
    currency: str | None = None,
    transaction_number: str = "",
    reference: str = "",
    paid_on: date | None = None,
    notes: str = "",
) -> Payment:
    _check_method(method)
    paid_on = paid_on or clock.today()
    _check_date(paid_on)
    code = clean_currency(
        currency or academy_services.get_settings().default_currency, field="currency"
    )
    if customer_type == STUDENT:
        if student_id is None:
            raise ValidationError("Choose a student.", field="student")
        student, name = active_student(student_id), ""
    else:
        if student_id is not None:
            raise ValidationError(
                "An unregistered customer has no student.", field="student"
            )
        student, name = None, customer_name.strip()
        if not name:
            raise ValidationError("Enter the customer's name.", field="customer_name")
    _check_unique(method, transaction_number)
    payment = Payment(
        invoice=None,
        customer_type=customer_type,
        student=student,
        customer_name=name,
        customer_email=customer_email,
        customer_phone=customer_phone,
        amount_minor=amount_minor,
        currency=code,
        method=method,
        transaction_number=transaction_number,
        reference=reference,
        paid_on=paid_on,
        notes=notes,
        recorded_by=by,
    )
    _save(payment)
    return payment


def _edit_customer(fresh: Payment, changes: dict) -> None:
    """The customer's kind is fixed at creation (§4.1); its rules still hold."""
    if fresh.customer_type == STUDENT:
        if "customer_name" in changes:
            raise ValidationError(
                "A student's record is named by the student.", field="customer_name"
            )
        if "student_id" in changes:
            fresh.student = active_student(changes["student_id"])
    else:
        if "student_id" in changes:
            raise ValidationError(
                "An unregistered customer has no student.", field="student"
            )
        if "customer_name" in changes:
            fresh.customer_name = changes["customer_name"].strip()
            if not fresh.customer_name:
                raise ValidationError(
                    "Enter the customer's name.", field="customer_name"
                )
    for key in ("customer_email", "customer_phone"):
        if key in changes:
            setattr(fresh, key, changes[key])


@transaction.atomic
def update_record(payment: Payment, **changes) -> Payment:
    """G-2: a manual standalone record only; anything else is a 409
    ``billing.payment_not_editable``."""
    fresh = Payment.objects.select_for_update().filter(pk=payment.pk).first()
    if fresh is None:
        raise NotFoundError("Payment", payment.pk)
    if fresh.invoice_id is not None or fresh.method in ONLINE_METHODS:
        raise ConflictError(
            "Only a manual payment record without an invoice is edited.",
            code="billing.payment_not_editable",
        )
    if "method" in changes:
        _check_method(changes["method"])
    if "paid_on" in changes:
        _check_date(changes["paid_on"])
    if "currency" in changes:
        changes["currency"] = clean_currency(changes["currency"], field="currency")
    _edit_customer(fresh, changes)
    for key in (
        "amount_minor",
        "currency",
        "method",
        "transaction_number",
        "reference",
        "paid_on",
        "notes",
    ):
        if key in changes:
            setattr(fresh, key, changes[key])
    _check_unique(fresh.method, fresh.transaction_number, fresh.pk)
    _save(fresh)
    return fresh
```

`backend/etqan/billing/services/__init__.py`: import and export `create_record`, `filter_payments`,
`has_standalone_records`, `payments_queryset`, `update_record` from `etqan.billing.services.records`, with
the matching `__all__` entries (keep it sorted).

- [ ] **Step 4: The feature**

`backend/etqan/platform/features.py`: replace the `payment_receipts` `_later(...)` row (above the markers)
with a plain `Feature(...)` in place:

```python
    # B3g (G-20): the payment records list and standalone records; needs invoices.
    Feature(
        "payment_receipts",
        "Payment receipt records",
        "سجلات إيصالات الدفع",
        "money",
        default=False,
        built=True,
        requires=("invoices",),
    ),
```

`platform/tests/test_features.py`: `BUILT` gains `payment_receipts`, and the unbuilt count falls by one
(27 → 26 here; Task 4 takes it to 25). Run the file and fix the exact numbers it names.

- [ ] **Step 5: The API**

`backend/etqan/billing/api/serializers.py`, append:

```python
class RecordInput(serializers.Serializer):
    """The create body (§4.1). `student` is the student's user id, as in the
    invoice API."""

    customer_type = serializers.ChoiceField(choices=("student", "unregistered"))
    student = _id(required=False)
    customer_name = serializers.CharField(max_length=120, required=False, allow_blank=True)
    customer_email = serializers.EmailField(required=False, allow_blank=True)
    customer_phone = serializers.CharField(max_length=30, required=False, allow_blank=True)
    amount_minor = serializers.IntegerField(min_value=1)
    currency = serializers.CharField(max_length=3, required=False)
    method = serializers.ChoiceField(choices=services.MANUAL_PAYMENT_METHODS)
    transaction_number = serializers.CharField(
        max_length=120, required=False, allow_blank=True
    )
    reference = serializers.CharField(max_length=120, required=False, allow_blank=True)
    paid_on = serializers.DateField(required=False)
    notes = serializers.CharField(required=False, allow_blank=True)


class RecordPatchInput(RecordInput):
    """Any subset of the create fields except `customer_type` (fixed when the
    record is created)."""

    def get_fields(self):
        fields = super().get_fields()
        fields.pop("customer_type")
        for field in fields.values():
            field.required = False
        return fields


class RecordQueryInput(serializers.Serializer):
    # A bad value is a 400 on its field, never silently "everything".
    method = serializers.ChoiceField(
        choices=[value for value, _ in Payment.Method.choices], required=False
    )
    customer_type = serializers.ChoiceField(
        choices=("student", "unregistered"), required=False
    )
    status = serializers.ChoiceField(choices=Payment.Status.choices, required=False)
    currency = serializers.RegexField(r"^[A-Z]{3}$", required=False)
    paid_from = serializers.DateField(required=False)
    paid_to = serializers.DateField(required=False)
    has_invoice = serializers.BooleanField(required=False)
    q = serializers.CharField(required=False, allow_blank=True)
```

with `from etqan.billing.models import Payment` added to the imports. (`BooleanField(required=False)` on a
query string reads "true"/"false"; for other text DRF raises 400, and an omitted filter stays absent because
`has_invoice` is not defaulted: build the serializer with `data=request.query_params` and read
`validated_data` only.)

`backend/etqan/billing/api/views.py`:

```python
RECORD_COLUMNS = (
    ("paid_on", "Date"),
    ("customer.name", "Customer"),
    ("customer.type", "Customer type"),
    ("invoice.number", "Invoice"),
    ("method", "Method"),
    ("transaction_number", "Transaction number"),
    ("amount_minor", "Amount (minor units)"),
    ("fee_minor", "Fee (minor units)"),
    ("currency", "Currency"),
    ("status", "Status"),
)
```

Add the imports `RecordInput`, `RecordPatchInput`, `RecordQueryInput`, and these views (before `RefundView`):

```python
def record_response(pk, *, code=status.HTTP_200_OK) -> Response:
    """A fresh read of one payment row for the office."""
    payment = get_object_or_404(services.payments_queryset(), pk=pk)
    return Response(payloads.payment_row(payment, is_admin=True), status=code)


class PaymentRecordListView(CSVExportMixin, generics.GenericAPIView):
    """B3g §4.1: every payment record, with or without an invoice."""

    permission_classes = [HasCode, FeatureOn]
    feature = "payment_receipts"
    permission_codes = {"GET": "payment.view_any", "POST": "payment.create"}
    csv_filename = "payments"
    csv_columns = RECORD_COLUMNS

    def get(self, request):
        query = RecordQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        rows = services.filter_payments(
            services.payments_queryset(), **query.validated_data
        )
        if self.wants_csv():
            return self.csv_response(
                [payloads.payment_row(p, is_admin=True) for p in rows]
            )
        page = self.paginate_queryset(rows)
        return self.get_paginated_response(
            [payloads.payment_row(p, is_admin=True) for p in page]
        )

    def post(self, request):
        body = RecordInput(data=request.data)
        body.is_valid(raise_exception=True)
        payment = services.create_record(**_ids(body.validated_data), by=request.user)
        return record_response(payment.pk, code=status.HTTP_201_CREATED)
```

Replace `PaymentDetailView` and `RefundView`:

```python
class PaymentDetailView(APIView):
    """GET and PATCH follow `payment_receipts` (a standalone record's own
    screen); DELETE keeps `invoices`, so an invoice payment is still deleted
    with receipts off (§4.1)."""

    permission_classes = [HasCode, FeatureOn]
    feature = {
        "GET": "payment_receipts",
        "PATCH": "payment_receipts",
        "DELETE": "invoices",
    }
    permission_codes = {
        "GET": "payment.view_any",
        "PATCH": "payment.update",
        "DELETE": "payment.delete",
    }

    def get(self, request, pk):
        return record_response(pk)

    def patch(self, request, pk):
        payment = get_object_or_404(Payment, pk=pk)
        body = RecordPatchInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.update_record(payment, **_ids(body.validated_data))
        return record_response(pk)

    def delete(self, request, pk):
        payment = get_object_or_404(Payment.objects.select_related("invoice"), pk=pk)
        services.delete_payment(payment)
        return Response(status=status.HTTP_204_NO_CONTENT)


class RefundView(APIView):
    """B3b §4.7: marks a payment refunded. It answers its invoice, or, for a
    standalone record (B3g G-3), the payment row."""

    permission_classes = [HasCode, FeatureOn]
    feature = "invoices"
    permission_codes = {"POST": "payment.update"}

    def post(self, request, pk):
        payment = get_object_or_404(Payment.objects.select_related("invoice"), pk=pk)
        services.refund_payment(payment, by=request.user)
        if payment.invoice_id is None:
            return record_response(pk)
        return detail(payment.invoice_id, request)
```

`backend/etqan/billing/api/urls.py`: add before the `payments/<int:pk>/` path:
`path("payments/", views.PaymentRecordListView.as_view(), name="payment-records"),`.

- [ ] **Step 6: The route table**

`backend/etqan/access/tests/test_routes.py`:
- `ROUTES`, after the `invoices/<N>/payments/` rows, add
  `("GET", "/api/v1/billing/payments/", "payment.view_any")`,
  `("POST", "/api/v1/billing/payments/", "payment.create")`,
  `("GET", f"/api/v1/billing/payments/{N}/", "payment.view_any")`,
  `("PATCH", f"/api/v1/billing/payments/{N}/", "payment.update")`.
- `FEATURES`: a new group
  ```python
      # Phase B3, slice B3g (G-20): the records list and a record's own screen.
      **dict.fromkeys(
          (
              ("GET", "/api/v1/billing/payments/"),
              ("POST", "/api/v1/billing/payments/"),
              ("GET", f"/api/v1/billing/payments/{N}/"),
              ("PATCH", f"/api/v1/billing/payments/{N}/"),
          ),
          "payment_receipts",
      ),
  ```
  The existing `DELETE .../payments/<N>/` row stays under `"invoices"`.
- `FEATURE_WORDS`: replace `"/billing/": "invoices"` with the three words that are still one feature each
  (payments and terms are per-method or ungated and are covered by `FEATURES` above):
  `"/billing/invoices/": "invoices"`, `"/billing/summary/": "invoices"`, `"/billing/payers/": "invoices"`.

Run: `$DJ pytest etqan/access etqan/platform etqan/billing -q`
Expected: all pass. If `test_registry.py` or `test_features.py` name a count, update it.

- [ ] **Step 7: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/billing etqan/platform etqan/access
git -C backend commit -m "feat(billing): payment records list, create, edit, refund and CSV"
```

---
### Task 3: Billing — subscription payment terms (SUB-006, G-18, G-19)

**Files:**
- Modify: `backend/etqan/billing/models.py`
- Create: `backend/etqan/billing/migrations/0007_subscriptionterms.py`
- Create: `backend/etqan/billing/services/terms.py`
- Modify: `backend/etqan/billing/services/__init__.py`, `api/serializers.py`, `api/views.py`, `api/urls.py`
- Modify: `backend/etqan/access/tests/test_routes.py`
- Test: `backend/etqan/billing/tests/test_terms.py`

**Interfaces:**
- Consumes: `scheduling_services.subscriptions_queryset()` (billing already imports `etqan.scheduling.services`); the registry's `subscription.view` and `subscription.update` codes.
- Produces:
  - model `SubscriptionTerms(subscription_id unique, payment_type, system, updated_by, updated_at)` with `PaymentType` (`prepaid` default | `postpaid`) and `System` (`normal` default | `monthly`)
  - `services.terms.Terms(payment_type: str, system: str)` (frozen)
  - `services.terms_for(subscription_id: int) -> Terms`; `services.set_terms(subscription_id: int, *, by, payment_type: str | None = None, system: str | None = None) -> Terms` (both: `NotFoundError` for an id scheduling does not hold)
  - route `GET|PATCH billing/subscriptions/<id>/terms/`, codes `subscription.view` / `subscription.update`, no feature gate

- [ ] **Step 1: Write the failing tests**

`backend/etqan/billing/tests/test_terms.py`:

```python
"""B3g §4.5, G-18, G-19: SUB-006's payment type and system. Recorded and
shown only; nothing reads them."""

import pytest
from rest_framework.test import APIClient

from etqan.billing import services
from etqan.billing.models import SubscriptionTerms
from etqan.billing.tests.conftest import make_parent
from etqan.platform.exceptions import NotFoundError

pytestmark = pytest.mark.django_db


def url(subscription_id):
    return f"/api/v1/billing/subscriptions/{subscription_id}/terms/"


def test_no_row_reads_as_the_defaults(subscribe):
    sub = subscribe()
    terms = services.terms_for(sub.pk)
    assert (terms.payment_type, terms.system) == ("prepaid", "normal")
    assert not SubscriptionTerms.objects.exists()


def test_set_creates_then_updates_one_row(subscribe, admin):
    sub = subscribe()
    first = services.set_terms(sub.pk, by=admin, payment_type="postpaid")
    assert (first.payment_type, first.system) == ("postpaid", "normal")
    second = services.set_terms(sub.pk, by=admin, system="monthly")
    assert (second.payment_type, second.system) == ("postpaid", "monthly")
    row = SubscriptionTerms.objects.get()
    assert (row.subscription_id, row.updated_by_id) == (sub.pk, admin.pk)


def test_an_unknown_subscription_is_not_found(admin):
    with pytest.raises(NotFoundError):
        services.terms_for(999_999)
    with pytest.raises(NotFoundError):
        services.set_terms(999_999, by=admin, system="monthly")


def test_a_renewal_starts_from_the_defaults(subscribe, admin):
    old = subscribe()
    services.set_terms(old.pk, by=admin, payment_type="postpaid", system="monthly")
    renewed = subscribe()
    assert services.terms_for(renewed.pk).payment_type == "prepaid"


def test_the_api_reads_and_patches(api_for, subscribe):
    sub = subscribe()
    admin = api_for("admin")
    assert admin.get(url(sub.pk)).json() == {"payment_type": "prepaid", "system": "normal"}
    patched = admin.patch(url(sub.pk), {"payment_type": "postpaid"}, format="json")
    assert (patched.status_code, patched.json()) == (
        200,
        {"payment_type": "postpaid", "system": "normal"},
    )
    assert admin.patch(url(sub.pk), {"system": "yearly"}, format="json").status_code == 400
    assert admin.get(url(999_999)).status_code == 404


def test_it_has_no_feature_gate(api_for, subscribe, set_features):
    sub = subscribe()
    set_features(invoices=False, payment_receipts=False)
    assert api_for("admin").get(url(sub.pk)).status_code == 200


def test_staff_need_the_codes_and_a_family_is_refused(api_for, staff_for, subscribe, world):
    sub = subscribe()
    assert staff_for("subscription.view").get(url(sub.pk)).status_code == 200
    only_view = staff_for("subscription.view")
    assert only_view.patch(url(sub.pk), {"system": "monthly"}, format="json").status_code == 403
    assert staff_for("subscription.update").get(url(sub.pk)).status_code == 403
    assert staff_for("subscription.update").patch(
        url(sub.pk), {"system": "monthly"}, format="json"
    ).status_code == 200
    parent = APIClient()
    parent.force_login(make_parent("Omar", world.student))
    assert parent.get(url(sub.pk)).status_code == 403
    assert parent.patch(url(sub.pk), {"system": "monthly"}, format="json").status_code == 403
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/billing/tests/test_terms.py -q`
Expected: FAIL (`SubscriptionTerms` does not exist).

- [ ] **Step 3: The model and migration**

`backend/etqan/billing/models.py`, append:

```python
class SubscriptionTerms(models.Model):
    """SUB-006 (B3g G-18): how an academy's office notes a subscription is paid.
    Keyed by a plain subscription id, as invoices are; recorded and shown only,
    nothing reads it. A renewal is a new subscription, so it starts from the
    defaults; a deleted subscription's row stays and is never read."""

    class PaymentType(models.TextChoices):
        PREPAID = "prepaid", "Prepaid"
        POSTPAID = "postpaid", "Postpaid"

    class System(models.TextChoices):
        NORMAL = "normal", "Normal"
        MONTHLY = "monthly", "Monthly"

    subscription_id = models.BigIntegerField(unique=True)
    payment_type = models.CharField(
        max_length=10, choices=PaymentType.choices, default=PaymentType.PREPAID
    )
    system = models.CharField(max_length=10, choices=System.choices, default=System.NORMAL)
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"SubscriptionTerms<{self.subscription_id}, {self.payment_type}, {self.system}>"
```

`backend/etqan/billing/migrations/0007_subscriptionterms.py`:

```python
import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("billing", "0006_payment_currency_required"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="SubscriptionTerms",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True, primary_key=True, serialize=False, verbose_name="ID"
                    ),
                ),
                ("subscription_id", models.BigIntegerField(unique=True)),
                (
                    "payment_type",
                    models.CharField(
                        choices=[("prepaid", "Prepaid"), ("postpaid", "Postpaid")],
                        default="prepaid",
                        max_length=10,
                    ),
                ),
                (
                    "system",
                    models.CharField(
                        choices=[("normal", "Normal"), ("monthly", "Monthly")],
                        default="normal",
                        max_length=10,
                    ),
                ),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "updated_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="+",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
        ),
    ]
```

Check no drift: `$DJ python manage.py makemigrations --check --dry-run` prints "No changes detected".

- [ ] **Step 4: The service**

`backend/etqan/billing/services/terms.py`:

```python
"""SUB-006: a subscription's payment type and system (B3g G-18). Office-only
metadata; nothing in billing or scheduling reads it."""

from dataclasses import dataclass

from django.db import transaction

from etqan.billing.models import SubscriptionTerms
from etqan.platform.exceptions import NotFoundError
from etqan.scheduling import services as scheduling_services


@dataclass(frozen=True)
class Terms:
    payment_type: str
    system: str


def _require(subscription_id: int) -> None:
    held = scheduling_services.subscriptions_queryset().filter(pk=subscription_id)
    if not held.exists():
        raise NotFoundError("Subscription", subscription_id)


def terms_for(subscription_id: int) -> Terms:
    """The stored terms, or the defaults when no row exists."""
    _require(subscription_id)
    row = SubscriptionTerms.objects.filter(subscription_id=subscription_id).first()
    if row is None:
        return Terms(
            SubscriptionTerms.PaymentType.PREPAID, SubscriptionTerms.System.NORMAL
        )
    return Terms(row.payment_type, row.system)


@transaction.atomic
def set_terms(
    subscription_id: int, *, by, payment_type: str | None = None, system: str | None = None
) -> Terms:
    """Creates the row or updates it; a field left out keeps its value."""
    _require(subscription_id)
    row, _ = SubscriptionTerms.objects.select_for_update().get_or_create(
        subscription_id=subscription_id
    )
    if payment_type is not None:
        row.payment_type = payment_type
    if system is not None:
        row.system = system
    row.updated_by = by
    row.save()
    return Terms(row.payment_type, row.system)
```

`backend/etqan/billing/services/__init__.py`: export `Terms`, `set_terms`, `terms_for` (and `__all__`).

- [ ] **Step 5: The API**

`api/serializers.py`, append:

```python
class TermsInput(serializers.Serializer):
    payment_type = serializers.ChoiceField(
        choices=SubscriptionTerms.PaymentType.choices, required=False
    )
    system = serializers.ChoiceField(choices=SubscriptionTerms.System.choices, required=False)
```

with `from etqan.billing.models import SubscriptionTerms` among the imports. `api/views.py`, append:

```python
class SubscriptionTermsView(APIView):
    """SUB-006 (G-19): office-only, so it needs the subscription codes
    themselves; there is no feature gate (G-18)."""

    permission_classes = [HasCode]
    permission_codes = {"GET": "subscription.view", "PATCH": "subscription.update"}

    @staticmethod
    def _answer(terms) -> Response:
        return Response({"payment_type": terms.payment_type, "system": terms.system})

    def get(self, request, pk):
        return self._answer(services.terms_for(pk))

    def patch(self, request, pk):
        body = TermsInput(data=request.data)
        body.is_valid(raise_exception=True)
        return self._answer(
            services.set_terms(pk, by=request.user, **body.validated_data)
        )
```

(import `TermsInput`). `api/urls.py`: add
`path("subscriptions/<int:pk>/terms/", views.SubscriptionTermsView.as_view(), name="subscription-terms"),`.

- [ ] **Step 6: The route table**

`access/tests/test_routes.py`, `ROUTES`, after the billing rows:

```python
    # Phase B3, slice B3g (G-19): SUB-006, office-only, no feature gate.
    ("GET", f"/api/v1/billing/subscriptions/{N}/terms/", "subscription.view"),
    ("PATCH", f"/api/v1/billing/subscriptions/{N}/terms/", "subscription.update"),
```

Run: `$DJ pytest etqan/billing etqan/access -q --create-db`
Expected: all pass (`test_every_other_route_is_there_with_every_feature_off` covers "no feature gate").

- [ ] **Step 7: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/billing etqan/access
git -C backend commit -m "feat(billing): SUB-006 subscription payment terms"
```

---
### Task 4: Gateways — `PaymentLink`, its services and the admin API (G-7 to G-12, G-20 to G-22)

**Files:**
- Modify: `backend/etqan/gateways/models.py`; Create: the migration (generated)
- Create: `backend/etqan/gateways/services/links.py`
- Modify: `backend/etqan/gateways/services/purposes.py` (the `RECHECK` constant), `services/fees.py`, `services/__init__.py`
- Modify: `backend/etqan/gateways/api/serializers.py`, `api/payloads.py`, `api/views.py`, `api/urls.py`
- Modify: `backend/etqan/platform/features.py`, `backend/etqan/platform/tests/test_features.py`
- Modify: `backend/etqan/access/registry.py`, `backend/etqan/access/tests/test_registry.py`, `backend/etqan/access/tests/test_routes.py`
- Modify: `backend/config/settings/base.py`, `backend/pyproject.toml`
- Modify: `backend/etqan/gateways/tests/conftest.py`
- Test: `backend/etqan/gateways/tests/test_links.py`, `test_models.py`

**Interfaces:**
- Consumes: Plan 20/22 `fees.fee_for`, `fees.fee_settings`, `GatewayAccount`; `identity_services.get_student_profile`; `academy_services.get_settings`; `etqan.platform.features.enabled`; `app_url`.
- Produces:
  - model `PaymentLink` (§3.2) with `Kind` (`payment` | `donation`) and `Status` (`open` | `paid` | `cancelled`)
  - `fees.fee_for(..., use_switch: bool = True)`: with `use_switch=False` the fee is charged whenever `add_fee` is true, whatever `fee_enabled` says (D5)
  - `purposes.RECHECK = {"recheck": True}`
  - in `services.links` (exported from `etqan.gateways.services`):
    - `LINK_PURPOSES: dict[str, str]` (`{"payment": "payment_link", "donation": "donation_link"}`)
    - `LinkInfo` (frozen: `id, token, kind, status, title, student_id, payer_display_name, payer_email, payer_phone, amount_minor, currency, add_fee`)
    - `create_link(*, kind, title, provider, amount_minor, by, description="", student_id=None, payer_name="", payer_email="", payer_phone="", currency=None, add_fee=None) -> PaymentLink` (`student_id` is a user id)
    - `links_queryset()`, `filter_links(links, *, status="", kind="", provider="", created_from=None, created_to=None, q="")`, `cancel_link(link_id, *, by) -> PaymentLink`
    - `link_for(link_id) -> LinkInfo`, `link_fee(link) -> int`, `link_url(link) -> str`, `has_links() -> bool`
  - routes `GET|POST gateways/links/`, `GET gateways/links/<id>/`, `POST gateways/links/<id>/cancel/`
  - resource `payment_link` (`view_any`, `create`, `update`); feature `payment_links` built (`default=False`, requires `online_payments`); throttle scope `payment_link` (60/minute)

- [ ] **Step 1: Write the failing tests**

Append to `backend/etqan/gateways/tests/conftest.py`:

```python
@pytest.fixture
def links_on(set_features):
    """B3g ships `payment_links` off; it requires `online_payments`, which
    requires `invoices`. Donations are on too, for donation links."""
    return set_features(
        invoices=True,
        online_payments=True,
        payment_links=True,
        payment_receipts=True,
        donations=True,
    )


@pytest.fixture
def link(links_on, stripe_on, admin):
    """`link(**overrides)`: an open 500.00 EGP Stripe payment link for the
    unregistered payer "Abu Khalid", with the fee."""

    def make(**overrides):
        fields = {
            "kind": "payment",
            "title": "June fees",
            "provider": "stripe",
            "amount_minor": 50000,
            "currency": "EGP",
            "payer_name": "Abu Khalid",
            "by": admin,
            **overrides,
        }
        return gateways_services.create_link(**fields)

    return make
```

`backend/etqan/gateways/tests/test_links.py`:

```python
"""B3g §4.2: creating, listing and cancelling payment links; G-8, G-11,
G-12, G-17, G-20, G-21."""

from datetime import timedelta

import pytest
from django.db import IntegrityError
from django.db import transaction
from django.utils import timezone

from etqan.gateways import services
from etqan.gateways.models import PaymentLink
from etqan.gateways.models import GatewaySettings
from etqan.gateways.tests.conftest import as_user
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
URL = "/api/v1/gateways/links/"


def body(**overrides):
    return {
        "kind": "payment",
        "title": "June fees",
        "provider": "stripe",
        "amount_minor": 50000,
        "currency": "EGP",
        "payer_name": "Abu Khalid",
        **overrides,
    }


def test_an_unregistered_link_has_a_token_a_url_and_the_fee(link, admin):
    made = link()
    assert (made.status, made.kind, made.add_fee) == ("open", "payment", True)
    assert len(made.token) >= 22
    assert services.link_url(made).endswith(f"/app/pay/link/{made.token}")
    assert services.link_fee(made) == 2500


def test_a_registered_link_resolves_the_student_by_user_id(link, world):
    made = link(payer_name="", student_id=world.student.id)
    assert made.student.user_id == world.student.id
    info = services.link_for(made.pk)
    assert info.student_id == made.student_id  # the profile's pk (plan D11)
    assert info.payer_display_name == world.student.full_name


def test_exactly_one_of_student_and_payer_name(link, world):
    with pytest.raises(ValidationError) as both:
        link(student_id=world.student.id)
    assert both.value.field == "payer_name"
    with pytest.raises(ValidationError) as neither:
        link(payer_name="  ")
    assert neither.value.field == "student"


def test_the_student_must_be_active(link, world):
    world.student.is_active = False
    world.student.save()
    with pytest.raises(ValidationError) as refused:
        link(payer_name="", student_id=world.student.id)
    assert refused.value.field == "student"


def test_the_provider_must_be_enabled_and_take_the_currency(link, links_on, admin):
    with pytest.raises(ValidationError) as unsupported:
        link(currency="ZZZ")
    assert unsupported.value.field == "provider"
    with pytest.raises(ValidationError) as off:
        link(provider="paypal")  # no PayPal account in this test
    assert off.value.field == "provider"


def test_the_currency_defaults_to_the_academys(link):
    assert link(currency=None).currency == "USD"


def test_g12_the_setting_only_sets_the_default(link):
    GatewaySettings.objects.update_or_create(pk=1, defaults={"fee_enabled": False})
    assert link().add_fee is False
    assert link(add_fee=True).add_fee is True
    GatewaySettings.objects.update_or_create(pk=1, defaults={"fee_enabled": True})
    assert link().add_fee is True
    assert link(add_fee=False).add_fee is False


def test_g12_a_donation_link_never_has_a_fee_and_needs_the_switch(link, set_features):
    assert link(kind="donation", add_fee=True).add_fee is False
    set_features(donations=False)
    with pytest.raises(ValidationError) as off:
        link(kind="donation")
    assert off.value.field == "kind"


def test_cancel_closes_an_open_link_once(link, admin):
    made = link()
    cancelled = services.cancel_link(made.pk, by=admin)
    assert (cancelled.status, cancelled.cancelled_by_id) == ("cancelled", admin.pk)
    assert cancelled.cancelled_at is not None
    with pytest.raises(ConflictError) as again:
        services.cancel_link(made.pk, by=admin)
    assert again.value.code == "gateways.link_closed"


def test_the_constraints(link, admin):
    made = link()
    for change in ({"payer_name": ""}, {"amount_minor": 0}):
        with pytest.raises(IntegrityError), transaction.atomic():
            PaymentLink.objects.filter(pk=made.pk).update(**change)
    with pytest.raises(IntegrityError), transaction.atomic():
        PaymentLink.objects.filter(pk=made.pk).update(kind="donation", add_fee=True)


# ---- the API --------------------------------------------------------------


def test_the_api_creates_lists_and_cancels(api_for, links_on, stripe_on):
    admin = api_for("admin")
    created = admin.post(URL, body(), format="json")
    assert created.status_code == 201, created.json()
    row = created.json()
    assert row["payer"] == {
        "type": "unregistered",
        "student_id": None,
        "name": "Abu Khalid",
        "email": "",
        "phone": "",
    }
    assert (row["status"], row["fee_minor"], row["checkout_id"]) == ("open", 2500, None)
    assert row["url"].endswith(f"/app/pay/link/{services.links_queryset().get().token}")
    assert admin.get(f"{URL}{row['id']}/").json()["id"] == row["id"]
    assert admin.get(URL).json()["count"] == 1
    cancelled = admin.post(f"{URL}{row['id']}/cancel/")
    assert (cancelled.status_code, cancelled.json()["status"]) == (200, "cancelled")
    again = admin.post(f"{URL}{row['id']}/cancel/")
    assert (again.status_code, again.json()["code"]) == (409, "gateways.link_closed")


@pytest.mark.parametrize(
    "override",
    [{"title": ""}, {"title": "x" * 201}, {"amount_minor": 0}, {"kind": "loan"}],
)
def test_a_bad_body_is_a_400(api_for, links_on, stripe_on, override):
    assert api_for("admin").post(URL, body(**override), format="json").status_code == 400


def test_filters_and_their_400s(api_for, link):
    link(title="Alpha")
    link(title="Beta", kind="donation")
    gone = link(title="Gamma")
    admin = api_for("admin")
    services.cancel_link(gone.pk, by=admin.user)

    def count(query):
        resp = admin.get(f"{URL}?{query}")
        assert resp.status_code == 200, resp.json()
        return resp.json()["count"]

    assert count("status=open") == 2
    assert count("status=cancelled") == 1
    assert count("kind=donation") == 1
    assert count("provider=stripe") == 3
    assert count("q=alph") == 1
    assert count("q=Abu") == 3
    today = timezone.now().date()  # created_at is stamped by the database clock
    assert count(f"created_from={today}&created_to={today}") == 3
    assert count(f"created_from={today + timedelta(days=1)}") == 0
    for bad in ("status=lost", "kind=x", "provider=x", "created_from=soon"):
        assert admin.get(f"{URL}?{bad}").status_code == 400


def test_the_feature_and_its_requirement(api_for, link, set_features):
    admin = api_for("admin")
    link()
    set_features(payment_links=False)
    assert admin.get(URL).status_code == 404
    set_features(payment_links=True, online_payments=False)  # requires it (G-20)
    assert admin.get(URL).status_code == 404


def test_a_family_is_refused(link, parent_of_world):
    link()
    assert as_user(parent_of_world).get(URL).status_code == 403
    assert as_user(parent_of_world).post(URL, body(), format="json").status_code == 403
```

Add to `backend/etqan/gateways/tests/test_models.py` nothing: the constraints test above covers them.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/gateways/tests/test_links.py -q`
Expected: FAIL (no `create_link`).

- [ ] **Step 3: The model**

`backend/etqan/gateways/models.py`, append:

```python
class PaymentLink(models.Model):
    """B3g §3.2: a fixed-amount, single-use link someone pays without logging
    in. Not edited (cancel it and make another); no expiry date. Whoever holds
    the token can pay it: the payer fields only decide whom the money is
    recorded for (G-8)."""

    class Kind(models.TextChoices):
        PAYMENT = "payment", "Payment"
        DONATION = "donation", "Donation"

    class Status(models.TextChoices):
        OPEN = "open", "Open"
        PAID = "paid", "Paid"
        CANCELLED = "cancelled", "Cancelled"

    token = models.CharField(max_length=32, unique=True)
    kind = models.CharField(max_length=10, choices=Kind.choices)
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True, default="")
    # A string reference: gateways imports no business app (B-1, G-22).
    student = models.ForeignKey(
        "identity.StudentProfile",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    payer_name = models.CharField(max_length=120, blank=True, default="")
    payer_email = models.EmailField(blank=True, default="")
    payer_phone = models.CharField(max_length=30, blank=True, default="")
    provider = models.CharField(max_length=16)
    amount_minor = models.BigIntegerField()
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    add_fee = models.BooleanField(default=False)
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.OPEN
    )
    checkout = models.ForeignKey(
        Checkout,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    paid_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancelled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "-pk"]
        constraints = [
            # A registered payer has no typed name; an unregistered one has.
            models.CheckConstraint(
                condition=(Q(student__isnull=False, payer_name=""))
                | (Q(student__isnull=True) & ~Q(payer_name="")),
                name="gateways_link_one_payer",
            ),
            models.CheckConstraint(
                condition=Q(kind="payment") | Q(add_fee=False),
                name="gateways_link_donation_no_fee",
            ),
            models.CheckConstraint(
                condition=Q(amount_minor__gt=0), name="gateways_link_amount_positive"
            ),
        ]
        indexes = [models.Index(fields=["status"])]

    def __str__(self):
        return f"PaymentLink<{self.pk}, {self.kind}, {self.status}>"
```

Generate the migration: `$DJ python manage.py makemigrations gateways --name payment_link`. Expected: one
new file in `etqan/gateways/migrations/` with a `CreateModel("PaymentLink")`. Open it and confirm the three
constraints and the index are there.

- [ ] **Step 4: The fee switch, the re-check constant and the features (D5, D7)**

`backend/etqan/gateways/services/fees.py`: change the signature and the fee line (keep B3c's currency table
and any other change in the built file):

```python
def fee_for(
    amount_minor: int,
    currency: str,
    *,
    add_fee: bool,
    provider: str = "stripe",
    use_switch: bool = True,
) -> int | None:
    """The fee in minor units, or None when ``provider`` cannot take this
    amount in this currency. ``use_switch=False`` (a payment link, B3g G-12):
    ``add_fee`` alone decides, at the current percentage."""
```

and replace `if add_fee and settings_row.fee_enabled:` with
`if add_fee and (settings_row.fee_enabled or not use_switch):`.

`backend/etqan/gateways/services/purposes.py`: add under the dataclasses

```python
# G-14: how gateways asks a purpose "is this still payable?" without a token
# (the checkout's creator may be nobody). Only gateways' own code builds it:
# the public view passes {"token": ...} and the generic route passes none.
RECHECK: dict = {"recheck": True}
```

and add `use_switch: bool = True` as the last field of `Prepared` (comment: "G-12: false for a payment
link, whose own `add_fee` decides").

`backend/etqan/platform/features.py`: replace the `payment_links` `_later(...)` row with

```python
    # B3g (G-20): payment links; needs online payments.
    Feature(
        "payment_links",
        "Payment links",
        "نظام روابط الدفع",
        "money",
        default=False,
        built=True,
        requires=("online_payments",),
    ),
```

`platform/tests/test_features.py`: `BUILT` gains `payment_links`; the unbuilt count is now 25. Run the file
and fix the exact numbers it names.

`backend/etqan/access/registry.py`, under `── phase B3 ──`, after the `checkout` resource:

```python
    # B3g: payment links (G-21); payment records use billing's `payment` codes.
    Resource(
        "payment_link",
        "Payment links",
        "روابط الدفع",
        ("view_any", "create", "update"),
    ),
```

`access/tests/test_registry.py`: the resource count rises by one; fix the number it names.

`backend/config/settings/base.py`: `DEFAULT_THROTTLE_RATES` gains `"payment_link": "60/minute",`.

`backend/pyproject.toml`, B3 contracts block: in the contract named "gateways imports no business app",
delete `"etqan.identity"` and `"etqan.academy"` from `forbidden_modules` and add
`allow_indirect_imports = true` (gateways now reaches `identity.services` and `academy.services`, whose own
imports are not its business; D4). After that contract add:

```toml
[[tool.importlinter.contracts]]
name = "gateways reaches identity and academy only through their services"
type = "forbidden"
# B3g G-22 (and plan D4): a link's student, and the academy's default currency.
source_modules = ["etqan.gateways"]
forbidden_modules = [
    "etqan.identity.models", "etqan.identity.api", "etqan.identity.scopes",
    "etqan.academy.models", "etqan.academy.api",
]
allow_indirect_imports = true
ignore_imports = ["etqan.gateways.tests.** -> etqan.**"]
```

- [ ] **Step 5: The service**

`backend/etqan/gateways/services/links.py`:

```python
"""Payment links (B3g G-7 to G-17). A link is the gateways app's own state;
the purposes `payment_link` (billing) and `donation_link` (finance) only
record money. Billing and finance read a link through `link_for`."""

import hmac
import secrets
from dataclasses import dataclass
from datetime import date

from django.db import transaction
from django.db.models import Q
from django.db.models import QuerySet

from etqan.academy import services as academy_services
from etqan.gateways import clock
from etqan.gateways.models import GatewayAccount
from etqan.gateways.models import PaymentLink
from etqan.gateways.services import fees
from etqan.identity import services as identity_services
from etqan.platform import features
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.frontend import app_url
from etqan.platform.validators import clean_currency

OPEN = PaymentLink.Status.OPEN
PAID = PaymentLink.Status.PAID
CANCELLED = PaymentLink.Status.CANCELLED
PAYMENT = PaymentLink.Kind.PAYMENT
DONATION = PaymentLink.Kind.DONATION
# The purpose each kind of link pays through (G-10).
LINK_PURPOSES = {PAYMENT.value: "payment_link", DONATION.value: "donation_link"}
MAX_TOKEN = 32


@dataclass(frozen=True)
class LinkInfo:
    """What billing and finance may read of a link (G-10). ``student_id`` is
    the StudentProfile's pk."""

    id: int
    token: str
    kind: str
    status: str
    title: str
    student_id: int | None
    payer_display_name: str
    payer_email: str
    payer_phone: str
    amount_minor: int
    currency: str
    add_fee: bool


def links_queryset() -> QuerySet[PaymentLink]:
    return PaymentLink.objects.select_related(
        "student__user", "created_by", "checkout"
    )


def has_links() -> bool:
    return PaymentLink.objects.exists()


def link_url(link: PaymentLink) -> str:
    return app_url(f"/pay/link/{link.token}")


def _payer_name(link: PaymentLink) -> str:
    return link.student.user.full_name if link.student_id else link.payer_name


def link_for(link_id: int) -> LinkInfo:
    link = links_queryset().filter(pk=link_id).first()
    if link is None:
        raise NotFoundError("Payment link", link_id)
    return LinkInfo(
        id=link.pk,
        token=link.token,
        kind=link.kind,
        status=link.status,
        title=link.title,
        student_id=link.student_id,
        payer_display_name=_payer_name(link),
        payer_email=link.payer_email,
        payer_phone=link.payer_phone,
        amount_minor=link.amount_minor,
        currency=link.currency,
        add_fee=link.add_fee,
    )


def allows(link: LinkInfo, params: dict | None) -> bool:
    """Whether a purpose's `prepare` may price ``link`` for these params: the
    token (compared in constant time, on bytes: D15) or gateways' own
    re-check (D7). Anything else, including none, is "not found" (G-15)."""
    if not params:
        return False
    if params.get("recheck") is True:
        return True
    given = params.get("token")
    return (
        isinstance(given, str)
        and len(given) <= MAX_TOKEN
        and hmac.compare_digest(given.encode(), link.token.encode())
    )


def _fee_quote(link: PaymentLink) -> int | None:
    """G-12: the link's own flag decides, at the current percentage."""
    return fees.fee_for(
        link.amount_minor,
        link.currency,
        add_fee=link.add_fee,
        provider=link.provider,
        use_switch=False,
    )


def link_fee(link: PaymentLink) -> int:
    """The paying checkout's fee for a paid link, otherwise the preview."""
    if link.status == PAID and link.checkout_id is not None:
        return link.checkout.fee_minor
    return _fee_quote(link) or 0


def _provider_takes(link: PaymentLink) -> bool:
    """G-17: enabled, and able to take this amount in this currency."""
    enabled = GatewayAccount.objects.filter(provider=link.provider, enabled=True)
    return enabled.exists() and _fee_quote(link) is not None


def _active_student(user_id: int):
    profile = identity_services.get_student_profile(user_id)
    if profile is None or profile.user.role != "student" or not profile.user.is_active:
        raise ValidationError("Choose an active student.", field="student")
    return profile


def create_link(  # noqa: PLR0913 -- keyword-only; mirrors the API body (B3g §4.2)
    *,
    kind: str,
    title: str,
    provider: str,
    amount_minor: int,
    by,
    description: str = "",
    student_id: int | None = None,
    payer_name: str = "",
    payer_email: str = "",
    payer_phone: str = "",
    currency: str | None = None,
    add_fee: bool | None = None,
) -> PaymentLink:
    if kind == DONATION and not features.enabled("donations"):
        raise ValidationError("Donations are switched off.", field="kind")
    name = payer_name.strip()
    if student_id is not None:
        if name or payer_email or payer_phone:
            raise ValidationError(
                "Choose a student or name the payer, not both.", field="payer_name"
            )
        student = _active_student(student_id)
    else:
        if not name:
            raise ValidationError("Choose a student or name the payer.", field="student")
        student = None
    code = clean_currency(
        currency or academy_services.get_settings().default_currency, field="currency"
    )
    if kind == DONATION:
        fee_flag = False
    elif add_fee is None:
        fee_flag = fees.fee_settings().fee_enabled
    else:
        fee_flag = add_fee
    link = PaymentLink(
        token=secrets.token_urlsafe(16),
        kind=kind,
        title=title.strip(),
        description=description,
        student=student,
        payer_name=name,
        payer_email=payer_email,
        payer_phone=payer_phone,
        provider=provider,
        amount_minor=amount_minor,
        currency=code,
        add_fee=fee_flag,
        created_by=by,
    )
    if not _provider_takes(link):
        raise ValidationError(
            "This payment method cannot take this amount.", field="provider"
        )
    link.save()
    return link


def filter_links(  # noqa: PLR0913 -- keyword-only; mirrors the list's query (B3g §4.2)
    links: QuerySet[PaymentLink],
    *,
    status: str = "",
    kind: str = "",
    provider: str = "",
    created_from: date | None = None,
    created_to: date | None = None,
    q: str = "",
) -> QuerySet[PaymentLink]:
    """Newest first. Dates are UTC days (gateways reads no academy calendar)."""
    if status:
        links = links.filter(status=status)
    if kind:
        links = links.filter(kind=kind)
    if provider:
        links = links.filter(provider=provider)
    if created_from is not None:
        links = links.filter(created_at__date__gte=created_from)
    if created_to is not None:
        links = links.filter(created_at__date__lte=created_to)
    if q.strip():
        text = q.strip()
        links = links.filter(
            Q(title__icontains=text)
            | Q(payer_name__icontains=text)
            | Q(student__user__full_name__icontains=text)
        )
    return links.order_by("-created_at", "-pk")


@transaction.atomic
def cancel_link(link_id: int, *, by) -> PaymentLink:
    """`open` to `cancelled`. A pending checkout is left alone; money that
    still arrives becomes attention (G-13)."""
    link = PaymentLink.objects.select_for_update().filter(pk=link_id).first()
    if link is None:
        raise NotFoundError("Payment link", link_id)
    if link.status != OPEN:
        raise ConflictError("This link is closed.", code="gateways.link_closed")
    link.status = CANCELLED
    link.cancelled_at = clock.now()
    link.cancelled_by = by
    link.save(update_fields=["status", "cancelled_at", "cancelled_by"])
    return link
```

`backend/etqan/gateways/services/__init__.py`: export `LINK_PURPOSES`, `LinkInfo`, `allows` (as
`link_allowed`: `from etqan.gateways.services.links import allows as link_allowed`), `cancel_link`,
`create_link`, `filter_links`, `has_links`, `link_fee`, `link_for`, `link_url`, `links_queryset`, plus
`RECHECK` from purposes, with the matching `__all__` entries.

- [ ] **Step 6: The API**

`api/serializers.py`, append:

```python
class LinkInput(serializers.Serializer):
    kind = serializers.ChoiceField(choices=PaymentLink.Kind.choices)
    title = serializers.CharField(min_length=1, max_length=200)
    description = serializers.CharField(required=False, allow_blank=True)
    # The student's user id, as in billing's invoice API (G-8).
    student = serializers.IntegerField(min_value=1, required=False)
    payer_name = serializers.CharField(max_length=120, required=False, allow_blank=True)
    payer_email = serializers.EmailField(required=False, allow_blank=True)
    payer_phone = serializers.CharField(max_length=30, required=False, allow_blank=True)
    provider = serializers.ChoiceField(choices=("stripe", "paypal"))
    amount_minor = serializers.IntegerField(min_value=1)
    currency = serializers.CharField(max_length=3, required=False)
    add_fee = serializers.BooleanField(required=False)


class LinkQueryInput(serializers.Serializer):
    status = serializers.ChoiceField(choices=PaymentLink.Status.choices, required=False)
    kind = serializers.ChoiceField(choices=PaymentLink.Kind.choices, required=False)
    provider = serializers.ChoiceField(choices=("stripe", "paypal"), required=False)
    created_from = serializers.DateField(required=False)
    created_to = serializers.DateField(required=False)
    q = serializers.CharField(required=False, allow_blank=True)
```

(import `PaymentLink` from `etqan.gateways.models`).

`api/payloads.py`, append:

```python
def link_row(link) -> dict:
    registered = link.student_id is not None
    return {
        "id": link.pk,
        "kind": link.kind,
        "title": link.title,
        "description": link.description,
        "payer": {
            "type": "student" if registered else "unregistered",
            "student_id": link.student.user_id if registered else None,
            "name": link.student.user.full_name if registered else link.payer_name,
            "email": link.payer_email,
            "phone": link.payer_phone,
        },
        "provider": link.provider,
        "amount_minor": link.amount_minor,
        "currency": link.currency,
        "add_fee": link.add_fee,
        "fee_minor": services.link_fee(link),
        "status": link.status,
        "url": services.link_url(link),
        "checkout_id": str(link.checkout_id) if link.checkout_id else None,
        "paid_at": link.paid_at,
        "created_by": _person(link.created_by),
        "created_at": link.created_at,
    }
```

`api/views.py`, append (and import `LinkInput`, `LinkQueryInput`):

```python
def _link_response(pk, *, code=status.HTTP_200_OK) -> Response:
    link = services.links_queryset().get(pk=pk)
    return Response(payloads.link_row(link), status=code)


class LinkListView(generics.GenericAPIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "payment_links"
    permission_codes = {"GET": "payment_link.view_any", "POST": "payment_link.create"}

    def get(self, request):
        query = LinkQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        rows = services.filter_links(services.links_queryset(), **query.validated_data)
        page = self.paginate_queryset(rows)
        return self.get_paginated_response([payloads.link_row(link) for link in page])

    def post(self, request):
        body = LinkInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = dict(body.validated_data)
        if "student" in data:
            data["student_id"] = data.pop("student")
        link = services.create_link(**data, by=request.user)
        return _link_response(link.pk, code=status.HTTP_201_CREATED)


class LinkDetailView(APIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "payment_links"
    permission_codes = {"GET": "payment_link.view_any"}

    def get(self, request, pk):
        link = services.links_queryset().filter(pk=pk).first()
        if link is None:
            raise NotFoundError("Payment link", pk)
        return Response(payloads.link_row(link))


class LinkCancelView(APIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "payment_links"
    permission_codes = {"POST": "payment_link.update"}

    def post(self, request, pk):
        services.cancel_link(pk, by=request.user)
        return _link_response(pk)
```

(import `NotFoundError` from `etqan.platform.exceptions`). `api/urls.py`, add:

```python
    path("links/", views.LinkListView.as_view(), name="links"),
    path("links/<int:pk>/", views.LinkDetailView.as_view(), name="link"),
    path("links/<int:pk>/cancel/", views.LinkCancelView.as_view(), name="link-cancel"),
```

- [ ] **Step 7: The route table**

`access/tests/test_routes.py`:
- `ROUTES`: add
  ```python
      # Phase B3, slice B3g.
      ("GET", "/api/v1/gateways/links/", "payment_link.view_any"),
      ("POST", "/api/v1/gateways/links/", "payment_link.create"),
      ("GET", f"/api/v1/gateways/links/{N}/", "payment_link.view_any"),
      ("POST", f"/api/v1/gateways/links/{N}/cancel/", "payment_link.update"),
  ```
- `FEATURES`: a group of those four under `"payment_links"`.
- `FEATURE_WORDS`: replace `"/gateways/": "online_payments"` with
  `"/gateways/settings/": "online_payments"`, `"/gateways/checkouts/": "online_payments"` and
  `"/gateways/links/": "payment_links"` (Task 6 adds the public routes to `SELF_SERVICE`).

Run: `$DJ pytest etqan/gateways etqan/access etqan/platform -q --create-db`
Then: `$DJ sh -c 'lint-imports'` Expected: contracts kept.
Expected: all pass.

- [ ] **Step 8: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/gateways etqan/platform etqan/access config/settings/base.py pyproject.toml
git -C backend commit -m "feat(gateways): payment links, their services and admin API"
```

---
### Task 5: Gateways core — public purposes, anonymous checkouts, the fee switch and the re-check (G-12, G-14, G-15)

**Files:**
- Modify: `backend/etqan/gateways/services/purposes.py`, `services/checkouts.py`, `services/captures.py` (B3c), `services/simulator.py`, `services/__init__.py`
- Create: `backend/etqan/gateways/api/permissions.py`
- Modify: `backend/etqan/gateways/api/views.py`
- Test: `backend/etqan/gateways/tests/test_public_checkouts.py`

**Interfaces:**
- Consumes: Plan 20 `register_purpose`, `Prepared`, `start_checkout`, `checkout_for`, `simulate`; B3c `still_payable`, `capture_checkout`, `cancel_checkout`, `CaptureView`, `CancelView`; Task 4's `fee_for(use_switch=)`, `Prepared.use_switch`, `RECHECK`.
- Produces:
  - `register_purpose(name, *, prepare, complete, public: bool = False)`; `purposes.is_public_purpose(name: str) -> bool` (exported from `etqan.gateways.services`)
  - `start_checkout(..., user=None)` works: `created_by` stays null, the reuse tuple keys on `getattr(user, "pk", None)`, and `fee_for` receives `use_switch=prepared.use_switch`
  - `checkout_for(user, checkout_id)` and `simulate(checkout_id, outcome, *, user)` answer anyone (an `AnonymousUser` included) for a checkout whose purpose is public
  - `still_payable` passes `RECHECK` as `params` and honours `prepared.use_switch` (G-14)
  - `api.permissions.AuthenticatedOrPublicCheckout`; the status, capture, cancel and simulate views use it (D9)

- [ ] **Step 1: Write the failing tests**

`backend/etqan/gateways/tests/test_public_checkouts.py`:

```python
"""B3g G-12, G-14, G-15: a purpose may be public; a checkout of a public
purpose is started with no user and read, captured, cancelled and simulated
by anyone holding its UUID."""

import pytest
from django.contrib.auth.models import AnonymousUser
from rest_framework.test import APIClient

from etqan.gateways import services
from etqan.gateways.models import Checkout
from etqan.gateways.models import GatewaySettings
from etqan.gateways.services import purposes
from etqan.gateways.services.captures import still_payable
from etqan.gateways.tests.conftest import as_user
from etqan.platform.exceptions import NotFoundError

pytestmark = pytest.mark.django_db


@pytest.fixture
def fake_purpose():
    """`fake_purpose(name, public=False, use_switch=True, seen=None)`: a purpose
    pricing 1000 EGP with the fee; ``seen`` collects each `prepare`'s params."""
    names = []

    def make(name, *, public=False, use_switch=True, seen=None):
        def prepare(reference_id, user, params):
            if seen is not None:
                seen.append(params)
            return services.Prepared(
                amount_minor=1000,
                currency="EGP",
                description="Demo",
                add_fee=True,
                use_switch=use_switch,
            )

        def complete(done):
            return services.Applied(ok=True)

        services.register_purpose(name, prepare=prepare, complete=complete, public=public)
        names.append(name)

    yield make
    for name in names:
        purposes._PURPOSES.pop(name, None)  # noqa: SLF001 -- test cleanup


def started(name, *, provider="stripe", user=None):
    return services.start_checkout(name, 1, provider, user=user, params={"token": "t"})


def test_public_is_a_flag_of_the_registration(fake_purpose):
    fake_purpose("demo_public", public=True)
    fake_purpose("demo_private")
    assert services.is_public_purpose("demo_public") is True
    assert services.is_public_purpose("demo_private") is False
    assert services.is_public_purpose("never_registered") is False


def test_registering_the_same_name_with_another_flag_is_refused(fake_purpose):
    from django.core.exceptions import ImproperlyConfigured  # noqa: PLC0415

    fake_purpose("demo_flag", public=True)
    with pytest.raises(ImproperlyConfigured):
        services.register_purpose(
            "demo_flag", prepare=lambda *a: None, complete=lambda d: None, public=False
        )


def test_a_checkout_starts_with_no_user_and_a_second_start_reuses_it(
    online_on, stripe_on, fake_purpose
):
    fake_purpose("demo_public", public=True)
    first = started("demo_public")
    again = started("demo_public")
    assert first.id == again.id
    checkout = Checkout.objects.get(pk=first.id)
    assert checkout.created_by is None
    assert (checkout.amount_minor, checkout.fee_minor) == (1000, 50)


def test_review_focus_3_the_fee_setting_does_not_gate_a_link_style_purpose(
    online_on, stripe_on, fake_purpose
):
    fake_purpose("demo_link", public=True, use_switch=False)
    fake_purpose("demo_invoice", use_switch=True)
    GatewaySettings.objects.update_or_create(
        pk=1, defaults={"fee_enabled": False, "fee_basis_points": 300}
    )
    link_style = started("demo_link")
    assert Checkout.objects.get(pk=link_style.id).fee_minor == 30  # 3 % of 1000
    invoice_style = services.start_checkout(
        "demo_invoice", 1, "stripe", user=None, params=None
    )
    assert Checkout.objects.get(pk=invoice_style.id).fee_minor == 0


def test_the_still_payable_check_passes_the_recheck_marker(
    online_on, stripe_on, fake_purpose
):
    seen = []
    fake_purpose("demo_public", public=True, use_switch=False, seen=seen)
    checkout = Checkout.objects.get(pk=started("demo_public").id)
    seen.clear()
    assert still_payable(checkout) is True
    assert seen == [purposes.RECHECK]
    GatewaySettings.objects.update_or_create(pk=1, defaults={"fee_basis_points": 300})
    assert still_payable(checkout) is False  # the fee decision changed (C-8)


def test_checkout_for_answers_anyone_for_a_public_purpose_only(
    online_on, stripe_on, fake_purpose, parent_of_world
):
    fake_purpose("demo_public", public=True)
    fake_purpose("demo_private")
    public = Checkout.objects.get(pk=started("demo_public").id)
    private = Checkout.objects.get(
        pk=services.start_checkout(
            "demo_private", 1, "stripe", user=parent_of_world, params=None
        ).id
    )
    assert services.checkout_for(AnonymousUser(), public.pk).pk == public.pk
    assert services.checkout_for(parent_of_world, public.pk).pk == public.pk
    with pytest.raises(NotFoundError):
        services.checkout_for(AnonymousUser(), private.pk)


def test_the_status_route_is_open_for_a_public_checkout_only(
    online_on, stripe_on, fake_purpose, parent_of_world
):
    fake_purpose("demo_public", public=True)
    fake_purpose("demo_private")
    public = started("demo_public")
    private = services.start_checkout(
        "demo_private", 1, "stripe", user=parent_of_world, params=None
    )
    anon = APIClient()
    got = anon.get(f"/api/v1/gateways/checkouts/{public.id}/")
    assert got.status_code == 200
    assert got.json()["purpose"] == "demo_public"
    assert anon.get(f"/api/v1/gateways/checkouts/{private.id}/").status_code in (401, 403)
    own = as_user(parent_of_world).get(f"/api/v1/gateways/checkouts/{private.id}/")
    assert own.status_code == 200
    assert anon.get(f"/api/v1/gateways/checkouts/{public.id}x/").status_code == 404


def test_anyone_simulates_a_public_checkout_and_only_the_creator_a_private_one(
    online_on, stripe_on, fake_purpose, parent_of_world, world
):
    fake_purpose("demo_public", public=True)
    fake_purpose("demo_private")
    public = started("demo_public")
    private = services.start_checkout(
        "demo_private", 1, "stripe", user=parent_of_world, params=None
    )
    anon = APIClient()
    done = anon.post(f"/api/v1/gateways/simulate/{public.id}/", {"outcome": "pay"}, format="json")
    assert (done.status_code, done.json()) == (200, {"status": "completed"})
    assert anon.post(
        f"/api/v1/gateways/simulate/{private.id}/", {"outcome": "pay"}, format="json"
    ).status_code in (401, 403)
    stranger = as_user(world.student)
    assert stranger.post(
        f"/api/v1/gateways/simulate/{private.id}/", {"outcome": "pay"}, format="json"
    ).status_code == 404


def test_a_public_paypal_checkout_is_captured_and_cancelled_by_anyone(
    online_on, paypal_on, fake_purpose
):
    fake_purpose("demo_public", public=True)
    checkout = Checkout.objects.create(
        purpose="demo_public",
        reference_id=1,
        provider="paypal",
        simulated=True,
        amount_minor=1000,
        fee_minor=50,
        currency="USD",
        provider_ref="ord_sim_1",
    )
    anon = APIClient()
    captured = anon.post(f"/api/v1/gateways/checkouts/{checkout.pk}/capture/")
    assert (captured.status_code, captured.json()["status"]) == (200, "pending")
    cancelled = anon.post(f"/api/v1/gateways/checkouts/{checkout.pk}/cancel/")
    assert (cancelled.status_code, cancelled.json()["status"]) == (200, "cancelled")


def test_the_generic_start_route_still_needs_a_user_and_a_registered_purpose(
    online_on, stripe_on, fake_purpose
):
    fake_purpose("demo_public", public=True)
    resp = APIClient().post(
        "/api/v1/gateways/checkouts/start/",
        {"purpose": "demo_public", "reference_id": 1, "provider": "stripe"},
        format="json",
    )
    assert resp.status_code in (401, 403)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/gateways/tests/test_public_checkouts.py -q`
Expected: FAIL (`register_purpose()` takes no `public`).

- [ ] **Step 3: Purposes**

`backend/etqan/gateways/services/purposes.py`:

```python
@dataclass(frozen=True)
class Purpose:
    prepare: Callable[[int, object, dict | None], Prepared]
    complete: Callable[[CompletedCheckout], Applied]
    # G-15, D6: a checkout of a public purpose is read, captured, cancelled
    # and simulated by anyone holding its UUID. The purpose's `prepare` must
    # then check its own token (a link) or be started by trusted code only.
    public: bool = False


def register_purpose(name: str, *, prepare, complete, public: bool = False) -> None:
    """One app owns a name; registering the same handlers again is a no-op."""
    purpose = Purpose(prepare=prepare, complete=complete, public=public)
    if _PURPOSES.get(name, purpose) != purpose:
        raise ImproperlyConfigured(f"The purpose {name!r} is registered already.")
    _PURPOSES[name] = purpose


def is_public_purpose(name: str) -> bool:
    purpose = _PURPOSES.get(name)
    return purpose is not None and purpose.public
```

(`purpose_named` stays.) `services/__init__.py`: export `is_public_purpose` (and keep `RECHECK` from
Task 4).

- [ ] **Step 4: `start_checkout`, `checkout_for`, `simulate`, `still_payable`**

`backend/etqan/gateways/services/checkouts.py`:
- in `start_checkout`, the fee call gains `use_switch=prepared.use_switch`:

```python
    fee = fees.fee_for(
        prepared.amount_minor,
        prepared.currency,
        add_fee=prepared.add_fee,
        provider=provider,
        use_switch=prepared.use_switch,
    )
```

- `wanted = (prepared.amount_minor, fee, simulate, getattr(user, "pk", None))` (replace `user.pk`; run
  `grep -n "user\.pk\|user\.id" etqan/gateways/services/*.py` and make every other use of `user` in this
  module tolerate `None`: `created_by=user` is already fine);
- replace `checkout_for`:

```python
def checkout_for(user, checkout_id) -> Checkout:
    """§4.5: its creator, admins, or staff holding checkout.view_any; and, for
    a public purpose (G-15), anyone holding the UUID, signed in or not."""
    checkout = checkouts_queryset().filter(pk=checkout_id).first()
    if checkout is not None and is_public_purpose(checkout.purpose):
        return checkout
    if checkout is None or not getattr(user, "is_authenticated", False):
        raise NotFoundError("Checkout", checkout_id)
    office = is_office(user) and (
        role_of(user) == "admin" or "checkout.view_any" in codes_of(user)
    )
    if not (office or checkout.created_by_id == user.pk):
        raise NotFoundError("Checkout", checkout_id)
    return checkout
```

with `from etqan.gateways.services.purposes import is_public_purpose` beside `purpose_named`.

`backend/etqan/gateways/services/simulator.py`: in `simulate`, replace the lookup:

```python
    checkout = (
        Checkout.objects.filter(pk=checkout_id, simulated=True).first()
        if settings.GATEWAYS_SIMULATE
        else None
    )
    if checkout is not None and not _may_simulate(checkout, user):
        checkout = None
    if checkout is None:
        raise NotFoundError("Checkout", checkout_id)
```

and add above it:

```python
def _may_simulate(checkout: Checkout, user) -> bool:
    """B-12: its creator, or anyone for a public purpose (G-15)."""
    if is_public_purpose(checkout.purpose):
        return True
    return bool(getattr(user, "is_authenticated", False)) and (
        checkout.created_by_id == user.pk
    )
```

with `from etqan.gateways.services.purposes import is_public_purpose`.

`backend/etqan/gateways/services/captures.py` (B3c), in `still_payable`:

```python
    try:
        prepared = handler.prepare(checkout.reference_id, checkout.created_by, RECHECK)
    except EtqanError:
        return False
    fee = fees.fee_for(
        prepared.amount_minor,
        prepared.currency,
        add_fee=prepared.add_fee,
        provider=checkout.provider,
        use_switch=prepared.use_switch,
    )
```

(`from etqan.gateways.services.purposes import RECHECK, purpose_named`.) The invoice purpose ignores
`params`, so it is unaffected; if a B3c test asserted `prepare` was called with `None`, change it to
`RECHECK`.

- [ ] **Step 5: The permission class, the views and the payload**

`backend/etqan/gateways/api/permissions.py`:

```python
"""Who may reach a checkout's own routes (B3g G-15, D9)."""

from rest_framework.permissions import BasePermission

from etqan.gateways import services
from etqan.gateways.models import Checkout


class AuthenticatedOrPublicCheckout(BasePermission):
    """A signed-in user, as `IsAuthenticated`; or anyone, when the checkout in
    the URL belongs to a public purpose (a payment link). An anonymous caller
    on any other checkout is refused exactly as before."""

    def has_permission(self, request, view):
        if request.user and request.user.is_authenticated:
            return True
        purpose = (
            Checkout.objects.filter(pk=view.kwargs.get("pk"))
            .values_list("purpose", flat=True)
            .first()
        )
        return purpose is not None and services.is_public_purpose(purpose)
```

`api/views.py`: `from etqan.gateways.api.permissions import AuthenticatedOrPublicCheckout`;
- `SimulateView`: add `permission_classes = [AuthenticatedOrPublicCheckout]` (it had none: the default
  applied) and keep the throttle and `atomic_request = False`;
- `CheckoutDetailView`: `permission_classes = [AuthenticatedOrPublicCheckout]` (was `[IsAuthenticated]`);
- B3c's `CaptureView` and `CancelView`: `permission_classes = [AuthenticatedOrPublicCheckout]` and add
  `atomic_request = False` if it is missing (D10: the route-walk test in `platform/tests/test_drf.py`
  requires the attribute and the `non_atomic_requests` wrapper together).

Run: `$DJ pytest etqan/gateways etqan/platform/tests/test_drf.py etqan/access -q`
Expected: all pass, including the route-walk test (`test_non_atomic_views_and_routes_agree`).

- [ ] **Step 6: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/gateways
git -C backend commit -m "feat(gateways): public purposes, anonymous checkouts and the link fee rule"
```

---
### Task 6: The public pay routes, the link lock and both purposes (G-10, G-11, G-13 to G-17)

**Files:**
- Modify: `backend/etqan/gateways/services/links.py`, `services/completion.py` (B3c), `services/__init__.py`
- Modify: `backend/etqan/gateways/api/payloads.py`, `api/views.py`, `api/urls.py`
- Modify: `backend/etqan/billing/services/payments.py`, `services/__init__.py`, `apps.py`; Create: `backend/etqan/billing/services/link_purpose.py`
- Modify: `backend/etqan/finance/apps.py`; Create: `backend/etqan/finance/services/link_purpose.py`
- Modify: `backend/etqan/access/tests/test_routes.py` (`SELF_SERVICE`)
- Test: `backend/etqan/gateways/tests/test_pay_links.py`

**Interfaces:**
- Consumes: Task 4's `links` module and `LinkInfo`, `link_allowed`; Task 5's `public` purposes and anonymous `start_checkout`; B3c's `completion.finish`, `complete_paypal`; `billing.services.rules.save`, `clock.today`; `finance.services.create_donation`.
- Produces:
  - in `services.links`: `PublicLink` (frozen: `academy_name, kind, title, description, payer_name, amount_minor, fee_minor, currency, provider, status, payable`), `link_by_token(token) -> PaymentLink` (404 for a malformed or unknown token, and for a donation link while `donations` is off), `public_link(token) -> PublicLink`, `start_link_checkout(token) -> StartedCheckout`
  - `completion.finish` locks the link after the checkout (G-13)
  - `billing.services.record_link_payment(*, student_id, customer_name, customer_email, customer_phone, amount_minor, fee_minor, currency, method, transaction_number, notes) -> Payment`
  - purposes `payment_link` (billing, public) and `donation_link` (finance, public)
  - routes `GET gateways/pay/<token>/` and `POST gateways/pay/<token>/checkout/` (public, throttled `payment_link`, feature `payment_links`); `POST` is non-atomic

- [ ] **Step 1: Write the failing tests**

`backend/etqan/gateways/tests/test_pay_links.py`:

```python
"""B3g §4.3 and G-10 to G-17: the public pay page, both purposes end to end
with Stripe and PayPal, and the link lock."""

from datetime import date
from urllib.parse import quote

import httpx
import pytest
from django.contrib.auth.models import AnonymousUser
from django.db import connection
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.billing.models import Payment
from etqan.finance.models import Donation
from etqan.gateways import services
from etqan.gateways.models import Checkout
from etqan.gateways.models import GatewayAccount
from etqan.gateways.models import PaymentLink
from etqan.gateways.tests.conftest import as_user
from etqan.gateways.tests.paypal_fakes import ORDERS
from etqan.gateways.tests.paypal_fakes import a_capture
from etqan.gateways.tests.paypal_fakes import an_order
from etqan.gateways.tests.paypal_fakes import token_ok
from etqan.platform.exceptions import NotFoundError

pytestmark = [pytest.mark.django_db, pytest.mark.respx(assert_all_called=False)]
API = "/api/v1/gateways"


def page(token):
    return f"{API}/pay/{token}/"


def start(client, token):
    return client.post(f"{API}/pay/{token}/checkout/")


def simulate(checkout_id, outcome="pay"):
    return services.simulate(checkout_id, outcome, user=AnonymousUser())


def pay_through_stripe(made):
    started = services.start_link_checkout(made.token)
    assert simulate(started.id) == "completed"
    made.refresh_from_db()
    return Checkout.objects.get(pk=started.id)


# ---- the public page ------------------------------------------------------


def test_the_page_shows_the_link_with_its_fee_and_the_academy(link, world):
    made = link(payer_name="", student_id=world.student.id)
    got = APIClient().get(page(made.token))
    assert got.status_code == 200
    assert got.json() == {
        "academy_name": connection.tenant.name,
        "kind": "payment",
        "title": "June fees",
        "description": "",
        "payer_name": world.student.full_name.split()[0],  # first name only
        "amount_minor": 50000,
        "fee_minor": 2500,
        "currency": "EGP",
        "provider": "stripe",
        "status": "open",
        "payable": True,
    }


def test_an_unregistered_payers_name_is_shown_as_typed(link):
    made = link(payer_name="Abu Khalid Al-Omari")
    assert APIClient().get(page(made.token)).json()["payer_name"] == "Abu Khalid Al-Omari"


@pytest.mark.parametrize(
    "token", ["nope", "é" * 5, "a" * 33, "bad token", "%00", "A" * 22 + "%20"]
)
def test_review_focus_2_a_token_that_is_not_a_token_is_a_404(link, token):
    link()
    client = APIClient()
    assert client.get(f"{API}/pay/{quote(token, safe='%')}/").status_code == 404
    assert client.post(f"{API}/pay/{quote(token, safe='%')}/checkout/").status_code == 404


def test_the_feature_gates_both_routes(link, set_features):
    made = link()
    set_features(payment_links=False)
    assert APIClient().get(page(made.token)).status_code == 404
    assert start(APIClient(), made.token).status_code == 404


def test_g11_a_donation_link_is_a_404_while_donations_are_off(link, set_features):
    made = link(kind="donation")
    assert APIClient().get(page(made.token)).status_code == 200
    set_features(donations=False)
    assert APIClient().get(page(made.token)).status_code == 404
    assert start(APIClient(), made.token).status_code == 404


def test_a_closed_link_says_so_and_cannot_be_started(link, admin):
    made = link()
    services.cancel_link(made.pk, by=admin)
    got = APIClient().get(page(made.token)).json()
    assert (got["status"], got["payable"]) == ("cancelled", False)
    refused = start(APIClient(), made.token)
    assert (refused.status_code, refused.json()["code"]) == (409, "gateways.link_closed")


def test_g17_a_provider_that_cannot_take_it_makes_the_link_unpayable(link):
    made = link()
    GatewayAccount.objects.filter(provider="stripe").update(enabled=False)
    assert APIClient().get(page(made.token)).json()["payable"] is False
    refused = start(APIClient(), made.token)
    assert refused.status_code == 400
    assert "provider" in str(refused.json())


def test_the_throttle_is_per_ip_and_60_a_minute(link):
    made = link()
    client = APIClient()
    assert [client.get(page(made.token)).status_code for _ in range(60)] == [200] * 60
    assert client.get(page(made.token)).status_code == 429


def test_a_token_from_another_academy_is_a_404_here(link, tenants):
    made = link()
    with tenant_context(tenants.other):
        with pytest.raises(NotFoundError):
            services.link_by_token(made.token)


def test_the_generic_start_route_cannot_start_a_link_checkout(link, parent_of_world):
    made = link()
    resp = as_user(parent_of_world).post(
        f"{API}/checkouts/start/",
        {"purpose": "payment_link", "reference_id": made.pk, "provider": "stripe"},
        format="json",
    )
    assert resp.status_code == 404
    assert not Checkout.objects.exists()


# ---- a payment link, end to end ------------------------------------------


def test_stripe_a_paid_payment_link_becomes_a_standalone_record(link):
    made = link()
    anon = APIClient()
    began = start(anon, made.token)
    assert began.status_code == 201, began.json()
    checkout_id = began.json()["id"]
    assert (began.json()["amount_minor"], began.json()["fee_minor"]) == (50000, 2500)
    done = anon.post(
        f"{API}/simulate/{checkout_id}/", {"outcome": "pay"}, format="json"
    )
    assert (done.status_code, done.json()) == (200, {"status": "completed"})
    made.refresh_from_db()
    assert (made.status, str(made.checkout_id)) == ("paid", checkout_id)
    assert made.paid_at is not None
    payment = Payment.objects.get()
    assert (payment.invoice_id, payment.customer_type, payment.customer_name) == (
        None,
        "unregistered",
        "Abu Khalid",
    )
    assert (payment.method, payment.amount_minor, payment.fee_minor, payment.currency) == (
        "stripe",
        50000,
        2500,
        "EGP",
    )
    assert (payment.paid_on, payment.recorded_by, payment.notes) == (
        date(2026, 6, 1),
        None,
        "Payment link: June fees",
    )
    assert payment.transaction_number.startswith("pi_sim_")
    after = anon.get(page(made.token)).json()
    assert (after["status"], after["payable"], after["fee_minor"]) == ("paid", False, 2500)
    checkout = Checkout.objects.get(pk=checkout_id)
    assert (checkout.applied, checkout.attention) == (True, "")


def test_review_focus_4_a_registered_student_deactivated_later_still_pays(link, world):
    made = link(payer_name="", student_id=world.student.id)
    world.student.is_active = False
    world.student.save()
    pay_through_stripe(made)
    payment = Payment.objects.get()
    assert (payment.customer_type, payment.student_id) == ("student", made.student_id)
    assert payment.customer_name == ""


def test_g20_completions_keep_working_with_the_switches_off(link, set_features):
    made = link()
    started = services.start_link_checkout(made.token)
    set_features(payment_links=False, payment_receipts=False)
    assert simulate(started.id) == "completed"
    assert Payment.objects.count() == 1
    made.refresh_from_db()
    assert made.status == "paid"


def test_paypal_a_paid_donation_link_becomes_a_completed_donation(link, paypal_on, world):
    made = link(
        kind="donation",
        provider="paypal",
        currency="USD",
        payer_name="",
        student_id=world.student.id,
        amount_minor=2500,
    )
    started = services.start_link_checkout(made.token)
    assert started.fee_minor == 0  # a donation never has a fee
    assert simulate(started.id) == "completed"
    donation = Donation.objects.get()
    assert (donation.method, donation.status, donation.amount_minor) == (
        "paypal",
        "completed",
        2500,
    )
    assert (donation.currency, donation.donor_name) == ("USD", world.student.full_name)
    assert (donation.created_by, donation.notes) == (None, "Payment link: June fees")
    assert donation.transaction_number.startswith("CAP-SIM-")
    made.refresh_from_db()
    assert made.status == "paid"


def test_g20_a_donation_still_lands_with_donations_switched_off(link, set_features, paypal_on):
    made = link(kind="donation", provider="paypal", currency="USD", amount_minor=2500)
    started = services.start_link_checkout(made.token)
    set_features(donations=False)
    assert simulate(started.id) == "completed"
    assert Donation.objects.count() == 1


# ---- G-13: the link lock --------------------------------------------------


def stripe_checkout(made, ref):
    return Checkout.objects.create(
        purpose="payment_link",
        reference_id=made.pk,
        provider="stripe",
        simulated=True,
        amount_minor=made.amount_minor,
        fee_minor=2500,
        currency=made.currency,
        provider_ref=f"cs_sim_{ref}",
    )


def test_review_focus_1_two_payers_one_link_the_second_is_attention(link):
    made = link()
    first, second = stripe_checkout(made, "a"), stripe_checkout(made, "b")
    assert simulate(first.pk) == "completed"
    assert simulate(second.pk) == "completed"
    first.refresh_from_db()
    second.refresh_from_db()
    assert (first.applied, first.attention) == (True, "")
    assert (second.applied, second.attention) == (False, "link_closed")
    assert Payment.objects.count() == 1  # the purpose was not called again
    made.refresh_from_db()
    assert made.checkout_id == first.pk


def test_money_for_a_cancelled_link_is_attention_and_never_a_record(link, admin):
    made = link()
    checkout = stripe_checkout(made, "c")
    services.cancel_link(made.pk, by=admin)
    simulate(checkout.pk)
    checkout.refresh_from_db()
    assert (checkout.status, checkout.applied, checkout.attention) == (
        "completed",
        False,
        "link_closed",
    )
    assert not Payment.objects.exists()
    made.refresh_from_db()
    assert made.status == "cancelled"


def test_an_unapplied_payment_leaves_the_link_open(link, paypal_on):
    first = link(provider="paypal", currency="USD")
    second = link(provider="paypal", currency="USD", title="Second")
    one = Checkout.objects.get(pk=services.start_link_checkout(first.token).id)
    two = Checkout.objects.get(pk=services.start_link_checkout(second.token).id)
    capture = {
        "id": "CAP-DUP",
        "status": "COMPLETED",
        "amount": {"currency_code": "USD", "value": "525.00"},
    }
    services.complete_paypal(one.pk, capture)
    services.complete_paypal(two.pk, capture)
    two.refresh_from_db()
    assert (two.applied, two.attention) == (False, "already_recorded")
    second.refresh_from_db()
    assert second.status == "open"  # B-11: the money stays attention, the link open
    assert Payment.objects.count() == 1


# ---- G-14 and anonymous capture ------------------------------------------


def real_paypal_checkout(made, order="ORDER-L1"):
    return Checkout.objects.create(
        purpose="payment_link",
        reference_id=made.pk,
        provider="paypal",
        amount_minor=made.amount_minor,
        fee_minor=2500,
        currency="USD",
        provider_ref=order,
    )


def test_g14_a_cancelled_link_is_never_captured(link, paypal_on, admin, respx_mock):
    made = link(provider="paypal", currency="USD")
    checkout = real_paypal_checkout(made)
    services.cancel_link(made.pk, by=admin)
    resp = APIClient().post(f"{API}/checkouts/{checkout.pk}/capture/")
    assert (resp.status_code, resp.json()) == (200, {"status": "cancelled", "applied": None})
    assert not respx_mock.calls  # PayPal was never asked to capture


def test_an_anonymous_capture_of_an_open_link_records_the_payment(
    link, paypal_on, respx_mock
):
    made = link(provider="paypal", currency="USD")
    checkout = real_paypal_checkout(made)
    token_ok(respx_mock)
    respx_mock.post(f"{ORDERS}/{checkout.provider_ref}/capture").mock(
        return_value=httpx.Response(
            201, json=an_order(checkout, capture=a_capture(checkout, capture_id="CAP-9"))
        )
    )
    resp = APIClient().post(f"{API}/checkouts/{checkout.pk}/capture/")
    assert (resp.status_code, resp.json()) == (200, {"status": "completed", "applied": True})
    made.refresh_from_db()
    assert made.status == "paid"
    assert Payment.objects.get().transaction_number == "CAP-9"


def test_the_donation_purpose_refuses_a_payment_links_id(link):
    made = link()
    with pytest.raises(NotFoundError):
        services.start_checkout(
            "donation_link", made.pk, "stripe", user=None, params={"token": made.token}
        )
    assert PaymentLink.objects.get(pk=made.pk).status == "open"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/gateways/tests/test_pay_links.py -q`
Expected: FAIL (`services.start_link_checkout` is not defined).

- [ ] **Step 3: The public side of `links`**

`backend/etqan/gateways/services/links.py`: add `import re`, `from django.db import connection`,
`from etqan.gateways.services.checkouts import StartedCheckout, start_checkout` (merge with the imports),
and, near `MAX_TOKEN`:

```python
# secrets.token_urlsafe's alphabet: anything else is no token, so it never
# reaches the database (a NUL in a query is a 500; D15).
TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{1,32}$")
```

Replace `allows`' length test with `TOKEN_RE.fullmatch(given)`. Append:

```python
@dataclass(frozen=True)
class PublicLink:
    """What the public page shows (§4.3). The academy's name comes from the
    tenant on the connection, as `etqan.site` reads it."""

    academy_name: str
    kind: str
    title: str
    description: str
    payer_name: str
    amount_minor: int
    fee_minor: int
    currency: str
    provider: str
    status: str
    payable: bool


def link_by_token(token: str) -> PaymentLink:
    """404 for a malformed or unknown token (compared in constant time), and for
    a donation link while `donations` is off (G-11)."""
    link = None
    if TOKEN_RE.fullmatch(token or ""):
        link = links_queryset().filter(token=token).first()
    if link is None or not hmac.compare_digest(link.token.encode(), token.encode()):
        raise NotFoundError("Payment link")
    if link.kind == DONATION and not features.enabled("donations"):
        raise NotFoundError("Payment link")
    return link


def public_link(token: str) -> PublicLink:
    link = link_by_token(token)
    if link.student_id:
        parts = link.student.user.full_name.split()
        payer = parts[0] if parts else ""  # a registered student: first name only
    else:
        payer = link.payer_name
    return PublicLink(
        academy_name=connection.tenant.name,
        kind=link.kind,
        title=link.title,
        description=link.description,
        payer_name=payer,
        amount_minor=link.amount_minor,
        fee_minor=link_fee(link),
        currency=link.currency,
        provider=link.provider,
        status=link.status,
        payable=link.status == OPEN and _provider_takes(link),
    )


def start_link_checkout(token: str) -> StartedCheckout:
    """§4.3: the only way a link checkout starts. No user; the token goes to
    the purpose's `prepare`, which checks it again (G-15). A closed link is a
    409; a provider that cannot take it is B3b's 400 on `provider`."""
    link = link_by_token(token)
    if link.status != OPEN:
        raise ConflictError("This link is closed.", code="gateways.link_closed")
    return start_checkout(
        LINK_PURPOSES[link.kind],
        link.pk,
        link.provider,
        user=None,
        params={"token": token},
    )
```

Export `PublicLink`, `link_by_token`, `public_link`, `start_link_checkout` from
`services/__init__.py`.

- [ ] **Step 4: The link lock in the completion (G-13)**

`backend/etqan/gateways/services/completion.py` (B3c): read the built `finish`, keep its signature and the
order of its checks, and change its body so that, after `attention_for` finds nothing, a link purpose locks
its link:

```python
from etqan.gateways.models import PaymentLink
from etqan.gateways.services.links import LINK_PURPOSES

LINK_PURPOSE_NAMES = frozenset(LINK_PURPOSES.values())


def finish(
    checkout: Checkout,
    *,
    transaction_number: str,
    paid_minor: int | None,
    paid_currency: str,
    mode_matches: bool = True,
) -> None:
    checkout.status = Checkout.Status.COMPLETED
    checkout.completed_at = clock.now()
    checkout.transaction_number = transaction_number
    reason = attention_for(
        checkout, paid_minor=paid_minor, paid_currency=paid_currency, mode_matches=mode_matches
    )
    link = None
    if not reason and checkout.purpose in LINK_PURPOSE_NAMES:
        # G-13: the checkout is locked (the caller holds it); now the link, in
        # that order everywhere, so two payers of one link serialize here.
        link = PaymentLink.objects.select_for_update().filter(pk=checkout.reference_id).first()
        if link is not None and link.status != PaymentLink.Status.OPEN:
            reason = "link_closed"
    if reason:
        applied, checkout.attention = False, reason
    else:
        result = purpose_named(checkout.purpose).complete(
            CompletedCheckout(
                id=checkout.pk,
                purpose=checkout.purpose,
                reference_id=checkout.reference_id,
                provider=checkout.provider,
                amount_minor=checkout.amount_minor,
                fee_minor=checkout.fee_minor,
                currency=checkout.currency,
                transaction_number=checkout.transaction_number,
                completed_at=checkout.completed_at,
            )
        )
        applied, checkout.attention = result.ok, result.reason
        if result.ok and link is not None:
            # Under the same lock: the money applied, so the link is paid.
            link.status = PaymentLink.Status.PAID
            link.checkout = checkout
            link.paid_at = checkout.completed_at
            link.save(update_fields=["status", "checkout", "paid_at"])
    checkout.applied = applied
    checkout.save()
```

(An unapplied payment leaves the link `open`; a link that does not exist is the purpose's
`reference_missing`.)

- [ ] **Step 5: Billing's purpose**

`backend/etqan/billing/services/payments.py`, append:

```python
@transaction.atomic
def record_link_payment(  # noqa: PLR0913 -- keyword-only; one standalone payment's columns
    *,
    student_id: int | None,
    customer_name: str,
    customer_email: str,
    customer_phone: str,
    amount_minor: int,
    fee_minor: int,
    currency: str,
    method: str,
    transaction_number: str,
    notes: str,
) -> Payment:
    """A payment-link checkout's money (B3g §4.3): a standalone record dated
    the academy's today, recorded by nobody, with its fee. Errors are mapped
    by field (``transaction_number``) like `record_online_payment`'s."""
    if method not in ONLINE_METHODS:
        raise ValidationError("That is not an online method.", field="method")
    if (
        transaction_number
        and Payment.objects.filter(
            method=method, transaction_number=transaction_number
        ).exists()
    ):
        raise ValidationError(
            "This transaction is already recorded.", field="transaction_number"
        )
    payment = Payment(
        invoice=None,
        customer_type=(
            Payment.CustomerType.STUDENT
            if student_id is not None
            else Payment.CustomerType.UNREGISTERED
        ),
        student_id=student_id,
        customer_name="" if student_id is not None else customer_name,
        customer_email=customer_email,
        customer_phone=customer_phone,
        amount_minor=amount_minor,
        fee_minor=fee_minor,
        currency=currency,
        method=method,
        transaction_number=transaction_number,
        paid_on=clock.today(),
        recorded_by=None,
        notes=notes,
    )
    rules.save(payment)
    return payment
```

Export it from `billing/services/__init__.py`. `backend/etqan/billing/services/link_purpose.py`:

```python
"""Billing's `payment_link` purpose (B3g G-10, §4.3): the money of a payment
link becomes a standalone payment record. The link's own state is gateways'
(G-13); this only prices the link and records the money."""

from django.db import IntegrityError

from etqan.billing.services import payments
from etqan.gateways import services as gateways_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

NAME = "payment_link"
TRANSACTION_UNIQUE = "billing_payment_transaction_unique"


def prepare(reference_id: int, user, params: dict | None):
    """404 unless the caller holds the token (or is gateways' own re-check); a
    closed link is a 409 (G-14, §4.3). The link's own `add_fee` decides the fee."""
    link = gateways_services.link_for(reference_id)
    if link.kind != "payment" or not gateways_services.link_allowed(link, params):
        raise NotFoundError("Payment link", reference_id)
    if link.status != "open":
        raise ConflictError("This link is closed.", code="gateways.link_closed")
    return gateways_services.Prepared(
        amount_minor=link.amount_minor,
        currency=link.currency,
        description=link.title,
        add_fee=link.add_fee,
        use_switch=False,
    )


def complete(done: gateways_services.CompletedCheckout) -> gateways_services.Applied:
    try:
        link = gateways_services.link_for(done.reference_id)
    except NotFoundError:
        return gateways_services.Applied(ok=False, reason="reference_missing")
    try:
        payments.record_link_payment(
            student_id=link.student_id,
            customer_name=link.payer_display_name if link.student_id is None else "",
            customer_email=link.payer_email,
            customer_phone=link.payer_phone,
            amount_minor=done.amount_minor,
            fee_minor=done.fee_minor,
            currency=done.currency,
            method=done.provider,
            transaction_number=done.transaction_number,
            notes=f"Payment link: {link.title}"[:500],
        )
    except ValidationError as exc:
        if exc.field != "transaction_number":
            raise
        return gateways_services.Applied(ok=False, reason="already_recorded")
    except IntegrityError as exc:
        diag = getattr(exc.__cause__, "diag", None)
        if getattr(diag, "constraint_name", None) != TRANSACTION_UNIQUE:
            raise
        return gateways_services.Applied(ok=False, reason="already_recorded")
    return gateways_services.Applied(ok=True)


def register() -> None:
    gateways_services.register_purpose(
        NAME, prepare=prepare, complete=complete, public=True
    )
```

`backend/etqan/billing/apps.py`, `ready()`: after `online.register()` add
`from etqan.billing.services import link_purpose  # noqa: PLC0415` and `link_purpose.register()`.

- [ ] **Step 6: Finance's purpose**

`backend/etqan/finance/services/link_purpose.py`:

```python
"""Finance's `donation_link` purpose (B3g G-10, §4.3): the money of a donation
link becomes a completed donation. Never a fee (G-12)."""

from etqan.finance.services import donations
from etqan.gateways import services as gateways_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError

NAME = "donation_link"


def prepare(reference_id: int, user, params: dict | None):
    link = gateways_services.link_for(reference_id)
    if link.kind != "donation" or not gateways_services.link_allowed(link, params):
        raise NotFoundError("Payment link", reference_id)
    if link.status != "open":
        raise ConflictError("This link is closed.", code="gateways.link_closed")
    return gateways_services.Prepared(
        amount_minor=link.amount_minor,
        currency=link.currency,
        description=link.title,
        add_fee=False,
        use_switch=False,
    )


def complete(done: gateways_services.CompletedCheckout) -> gateways_services.Applied:
    """Records the donation whatever the `donations` switch says (FT-4): the
    money was paid."""
    try:
        link = gateways_services.link_for(done.reference_id)
    except NotFoundError:
        return gateways_services.Applied(ok=False, reason="reference_missing")
    donations.create_donation(
        amount_minor=done.amount_minor,
        method=done.provider,
        by=None,
        currency=done.currency,
        transaction_number=done.transaction_number,
        donor_name=link.payer_display_name,
        donor_email=link.payer_email,
        notes=f"Payment link: {link.title}",
    )
    return gateways_services.Applied(ok=True)


def register() -> None:
    gateways_services.register_purpose(
        NAME, prepare=prepare, complete=complete, public=True
    )
```

`backend/etqan/finance/apps.py`:

```python
    def ready(self):
        # B3g G-10: donation links are paid through gateways.
        from etqan.finance.services import link_purpose  # noqa: PLC0415

        link_purpose.register()
```

- [ ] **Step 7: The public routes**

`api/payloads.py`, append:

```python
def public_link(link) -> dict:
    return {
        "academy_name": link.academy_name,
        "kind": link.kind,
        "title": link.title,
        "description": link.description,
        "payer_name": link.payer_name,
        "amount_minor": link.amount_minor,
        "fee_minor": link.fee_minor,
        "currency": link.currency,
        "provider": link.provider,
        "status": link.status,
        "payable": link.payable,
    }
```

`api/views.py`, append:

```python
class PublicLinkView(APIView):
    """§4.3, G-16: anyone holding the token. No authentication (so no CSRF),
    per-IP throttle, switched by `payment_links`; the title and description go
    out as plain text and the page renders them escaped."""

    authentication_classes: list = []
    permission_classes = [AllowAny, FeatureOn]
    feature = "payment_links"
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "payment_link"

    def get(self, request, token):
        return Response(payloads.public_link(services.public_link(token)))


class PublicLinkCheckoutView(PublicLinkView):
    """Starts the link's checkout, with no user (G-15). Non-atomic (D10): the
    pending checkout commits before the provider is called; see urls."""

    atomic_request = False

    def post(self, request, token):
        started = services.start_link_checkout(token)
        return Response(payloads.started(started), status=status.HTTP_201_CREATED)
```

(`PublicLinkCheckoutView` inherits `get` from `PublicLinkView`; add `http_method_names = ["post", "options"]`
to it so a GET on the checkout URL is a 405.) `api/urls.py`:

```python
    path("pay/<str:token>/", views.PublicLinkView.as_view(), name="pay-link"),
    path(
        "pay/<str:token>/checkout/",
        transaction.non_atomic_requests(views.PublicLinkCheckoutView.as_view()),
        name="pay-link-checkout",
    ),
```

`access/tests/test_routes.py`, `SELF_SERVICE`:

```python
    # Phase B3, slice B3g (G-16): anyone holding the token; throttled and
    # switched by `payment_links` (not in the code table: no code).
    "etqan.gateways.api.views.PublicLinkView": "the public pay page (the link's token)",
    "etqan.gateways.api.views.PublicLinkCheckoutView": (
        "starts a link's checkout (the link's token)"
    ),
```

and `FEATURE_WORDS` gains `"/gateways/pay/": "payment_links"` only if those routes are in `ROUTES`/`ADMIN_ONLY`
(they are not; skip it).

Run: `$DJ pytest etqan/gateways etqan/billing etqan/finance etqan/access etqan/platform -q`
Expected: all pass, including `test_non_atomic_views_and_routes_agree` (the checkout view has the attribute
and the wrapper) and the import contracts.

- [ ] **Step 8: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/gateways etqan/billing etqan/finance etqan/access
git -C backend commit -m "feat(gateways): public pay routes, the link lock and the link purposes"
```

---
### Task 7: The checkouts CSV, the demo seeds and isolation (G-20, §4.4, §8)

**Files:**
- Modify: `backend/etqan/gateways/api/views.py` (`CheckoutListView`)
- Modify: `backend/etqan/tenants/seeds/gateways.py`, `backend/etqan/tenants/management/commands/seed_dev.py`
- Test: `backend/etqan/gateways/tests/test_checkouts_csv.py`, `backend/etqan/tenants/tests/test_seed_links.py`

**Interfaces:**
- Consumes: Plan 20's `checkout_row`, `filter_checkouts`; `etqan.platform.csv.CSVExportMixin`, `CSVRenderer`; Task 2's `billing_services.create_record`, `has_standalone_records`; Task 4's `gateways_services.create_link`, `has_links`.
- Produces:
  - `GET gateways/checkouts/?format=csv` (`checkout.view_any`): answers only while `online_payments`, `payment_receipts` and `export` are all on, otherwise 404; keeps B3b's filters
  - `seed_links(subdomain, student)` in `etqan/tenants/seeds/gateways.py`

- [ ] **Step 1: Write the failing tests**

`backend/etqan/gateways/tests/test_checkouts_csv.py`:

```python
"""B3g §4.4, G-20: the checkouts CSV needs online_payments, payment_receipts
and export, all three; the JSON list needs only the first."""

import csv
import io

import pytest

from etqan.gateways.models import Checkout

pytestmark = pytest.mark.django_db
URL = "/api/v1/gateways/checkouts/"
HEADER = [
    "Created",
    "Checkout",
    "Purpose",
    "Reference",
    "Provider",
    "Amount (minor units)",
    "Fee (minor units)",
    "Currency",
    "Status",
    "Applied",
    "Attention",
    "Transaction number",
    "Completed at",
]


@pytest.fixture
def three_on(set_features):
    return set_features(
        invoices=True, online_payments=True, payment_receipts=True, export=True
    )


def checkout(**fields):
    values = {
        "purpose": "invoice",
        "reference_id": 7,
        "provider": "stripe",
        "amount_minor": 50000,
        "fee_minor": 2500,
        "currency": "EGP",
        **fields,
    }
    return Checkout.objects.create(**values)


def test_the_csv_has_the_spec_columns_and_keeps_the_filters(api_for, three_on):
    checkout(status="completed", applied=True, transaction_number="pi_1")
    checkout(status="failed")
    resp = api_for("admin").get(f"{URL}?format=csv&status=completed")
    assert resp.status_code == 200
    rows = list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))
    assert rows[0] == HEADER
    assert len(rows) == 2
    row = dict(zip(HEADER, rows[1], strict=True))
    assert (row["Purpose"], row["Reference"], row["Provider"]) == ("invoice", "7", "stripe")
    assert (row["Amount (minor units)"], row["Fee (minor units)"]) == ("50000", "2500")
    assert (row["Status"], row["Applied"], row["Transaction number"]) == (
        "completed",
        "yes",
        "pi_1",
    )


@pytest.mark.parametrize("off", ["online_payments", "payment_receipts", "export"])
def test_each_of_the_three_switches_closes_the_csv(api_for, three_on, set_features, off):
    checkout()
    set_features(**{off: False})
    admin = api_for("admin")
    assert admin.get(f"{URL}?format=csv").status_code == 404
    expected = 404 if off == "online_payments" else 200
    assert admin.get(URL).status_code == expected  # the JSON list is unaffected


def test_the_csv_needs_the_view_code(api_for, staff_for, three_on):
    checkout(status="completed", applied=True)
    assert staff_for("invoice.view_any").get(f"{URL}?format=csv").status_code == 403
    assert staff_for("checkout.view_any").get(f"{URL}?format=csv").status_code == 200
```

`backend/etqan/tenants/tests/test_seed_links.py`:

```python
"""B3g §8: the demo academy's payment links and one standalone record, each
step only when its table is empty; other gets nothing."""

import pytest
from django.core.management import call_command
from django.db import connection
from django.test import override_settings
from django_tenants.utils import tenant_context

from etqan.billing import services as billing_services
from etqan.gateways import services as gateways_services
from etqan.platform.exceptions import NotFoundError
from etqan.tenants.models import Academy


def state():
    links = [
        (
            link.kind,
            link.provider,
            link.currency,
            link.add_fee,
            link.status,
            link.payer_name,
            bool(link.student_id),
        )
        for link in gateways_services.links_queryset().order_by("pk")
    ]
    records = [
        (p.customer_type, p.customer_name, p.method, p.amount_minor, p.invoice_id)
        for p in billing_services.payments_queryset().filter(invoice__isnull=True)
    ]
    return links, records


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_gives_demo_its_links_and_record_once():
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        first = state()
        assert first[0] == [
            ("payment", "stripe", "EGP", True, "open", "", True),
            ("donation", "paypal", "USD", False, "open", "Umm Sara", False),
        ]
        assert first[1] == [("unregistered", "Abu Khalid", "cash", 40000, None)]
    with tenant_context(other):
        assert state() == ([], [])
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert state() == first
```

Append to `test_seed_links.py` (cross-academy isolation of tokens, §9):

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_one_academys_links_are_invisible_to_another():
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        token = gateways_services.links_queryset().first().token
    with tenant_context(other):
        assert not gateways_services.has_links()
        with pytest.raises(NotFoundError):
            gateways_services.link_by_token(token)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$DJ pytest etqan/gateways/tests/test_checkouts_csv.py etqan/tenants/tests/test_seed_links.py -q`
Expected: FAIL.

- [ ] **Step 3: The CSV**

`backend/etqan/gateways/api/views.py`: imports `from etqan.platform import features`,
`from etqan.platform.csv import CSVExportMixin, CSVRenderer`; add

```python
CHECKOUT_COLUMNS = (
    ("created_at", "Created"),
    ("id", "Checkout"),
    ("purpose", "Purpose"),
    ("reference_id", "Reference"),
    ("provider", "Provider"),
    ("amount_minor", "Amount (minor units)"),
    ("fee_minor", "Fee (minor units)"),
    ("currency", "Currency"),
    ("status", "Status"),
    ("applied", "Applied"),
    ("attention", "Attention"),
    ("transaction_number", "Transaction number"),
    ("completed_at", "Completed at"),
)
```

and replace `CheckoutListView`:

```python
class CheckoutListView(CSVExportMixin, generics.GenericAPIView):
    """§4.8, B3g §4.4: the list; its CSV also needs `payment_receipts` (and
    `export`, which the mixin checks): without a renderer DRF answers 404."""

    permission_classes = [HasCode, FeatureOn]
    feature = "online_payments"
    permission_codes = {"GET": "checkout.view_any"}
    csv_filename = "online-payments"
    csv_columns = CHECKOUT_COLUMNS

    def get_renderers(self):
        renderers = super().get_renderers()
        if features.enabled("payment_receipts"):
            return renderers
        return [r for r in renderers if not isinstance(r, CSVRenderer)]

    def get(self, request):
        query = CheckoutQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        rows = services.filter_checkouts(
            services.checkouts_queryset(), **query.validated_data
        )
        if self.wants_csv():
            return self.csv_response([payloads.checkout_row(c) for c in rows])
        page = self.paginate_queryset(rows)
        return self.get_paginated_response([payloads.checkout_row(c) for c in page])
```

- [ ] **Step 4: The seeds**

`backend/etqan/tenants/seeds/gateways.py`: add imports
`from etqan.billing import services as billing_services` and
`from etqan.platform.exceptions import ValidationError`, and append:

```python
# Phase B3, slice B3g (spec §8). Each step runs only when its table is empty.
LINKS = {
    "demo": (
        # A registered student, in the academy's currency, with the fee.
        {
            "kind": "payment",
            "title": "Tajweed - monthly fees",
            "provider": "stripe",
            "amount_minor": 150000,
            "add_fee": True,
            "registered": True,
        },
        # An unregistered donor, in USD (PayPal's demo account is USD).
        {
            "kind": "donation",
            "title": "Support the academy",
            "provider": "paypal",
            "amount_minor": 5000,
            "currency": "USD",
            "payer_name": "Umm Sara",
        },
    )
}
RECORDS = {
    "demo": (
        {
            "customer_name": "Abu Khalid",
            "amount_minor": 40000,
            "method": "cash",
            "notes": "Walk-in payment",
        },
    )
}


def seed_links(subdomain: str, student) -> None:
    """``student`` is a demo student's user (or None: the registered link is
    then skipped). A provider that is not enabled here (a staging academy
    without the simulator) skips its link rather than failing the seed."""
    if not gateways_services.has_links():
        for spec in LINKS.get(subdomain, ()):
            fields = {key: value for key, value in spec.items() if key != "registered"}
            if spec.get("registered"):
                if student is None:
                    continue
                fields["student_id"] = student.pk
            try:
                gateways_services.create_link(**fields, by=None)
            except ValidationError:
                continue
    if not billing_services.has_standalone_records():
        for spec in RECORDS.get(subdomain, ()):
            billing_services.create_record(
                customer_type="unregistered", by=None, **spec
            )
```

`seed_dev.py`, under `── phase B3 ──` after `gateways_seeds.seed_gateways(subdomain)`:

```python
        gateways_seeds.seed_links(subdomain, _person("student", "Yusuf Omar"))
```

(`_person` returns a user or `None`.) Check `etqan.tenants`' import contract allows `billing.services` (the
module already imports billing's services elsewhere); if `lint-imports` complains, follow the message.

Run: `$DJ pytest etqan/gateways etqan/tenants etqan/billing etqan/finance -q`
Expected: all pass. A demo-seed test elsewhere that counts payments or revenue may need the standalone
record added; the failing assertion names it.

- [ ] **Step 5: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/gateways etqan/tenants
git -C backend commit -m "feat(gateways): checkouts CSV and demo links and records seeds"
```

---
### Task 8: Dashboard — link types, the public pay page and the public return and simulator routes (G-15, G-16, G-17)

**Files:**
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode`)
- Modify: `dashboard/src/features/gateways/schemas.ts` (`ATTENTION_CODES`), `index.ts`
- Create: `dashboard/src/features/gateways/linkSchemas.ts`, `linksApi.ts`, `linkQueries.ts`, `PublicFrame.tsx`, `PublicLinkPage.tsx`
- Move (`git -C dashboard mv`): `src/routes/_authed/pay.return.tsx` to `src/routes/pay.return.tsx`; `src/routes/_authed/pay.simulate.$checkoutId.tsx` to `src/routes/pay.simulate.$checkoutId.tsx`
- Create: `dashboard/src/routes/pay.link.$token.tsx`
- Modify: `dashboard/src/locales/en/gateways.json`, `dashboard/src/locales/ar/gateways.json`, `dashboard/src/test/gateways-fixtures.ts`
- Test: `dashboard/src/features/gateways/PublicLinkPage.test.tsx`, `ReturnPage.test.tsx` (one case added)

**Interfaces:**
- Consumes: Task 4 and 6 routes: `GET gateways/pay/<token>/` and `POST gateways/pay/<token>/checkout/`, `GET|POST gateways/links/`, `POST gateways/links/<id>/cancel/`; Plan 20/22 `gatewaysErrorText`, `go` (`./redirect`), `Provider`, `StartedCheckout`, `useCheckout`; billing's `Money`.
- Produces:
  - `FeatureCode` gains `"payment_links"` and `"payment_receipts"`
  - in `linkSchemas.ts`: `LINK_KINDS`, `LINK_STATUSES`, `LinkKind`, `LinkStatus`, `PaymentLinkRow`, `PublicLink`, `LinkBody`
  - `linksApi`: `list(params)`, `create(body)`, `cancel(id)`, `publicLink(token)`, `startPublic(token)`
  - hooks `useLinks(params)`, `usePublicLink(token)`
  - `<PublicFrame>{children}</PublicFrame>`, `<PublicLinkPage token={string} />`
  - public routes `/pay/link/$token`, `/pay/return`, `/pay/simulate/$checkoutId` (outside `_authed`)
  - fixtures `paymentLinkRow(overrides)`, `publicLink(overrides)`

- [ ] **Step 1: Write the failing tests**

Append to `dashboard/src/test/gateways-fixtures.ts` (adding the two type imports from
`@/features/gateways/linkSchemas`):

```ts
export function paymentLinkRow(
	overrides: Partial<PaymentLinkRow> = {},
): PaymentLinkRow {
	return {
		id: 5,
		kind: "payment",
		title: "June fees",
		description: "",
		payer: {
			type: "unregistered",
			student_id: null,
			name: "Abu Khalid",
			email: "",
			phone: "",
		},
		provider: "stripe",
		amount_minor: 50000,
		currency: "EGP",
		add_fee: true,
		fee_minor: 2500,
		status: "open",
		url: "http://demo.etqan.localhost/app/pay/link/tok-5",
		checkout_id: null,
		paid_at: null,
		created_by: { id: 1, full_name: "Amina" },
		created_at: "2026-06-01T08:00:00Z",
		...overrides,
	};
}

export function publicLink(overrides: Partial<PublicLink> = {}): PublicLink {
	return {
		academy_name: "Demo Academy",
		kind: "payment",
		title: "June fees",
		description: "",
		payer_name: "Abu Khalid",
		amount_minor: 50000,
		fee_minor: 2500,
		currency: "EGP",
		provider: "stripe",
		status: "open",
		payable: true,
		...overrides,
	};
}
```

`dashboard/src/features/gateways/PublicLinkPage.test.tsx`:

```tsx
import { act, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { publicLink, started } from "@/test/gateways-fixtures";
import { renderWithRouter } from "@/test/render";
import { linksApi } from "./linksApi";
import { PublicLinkPage } from "./PublicLinkPage";
import { go } from "./redirect";

vi.mock("./redirect", () => ({ go: vi.fn() }));
vi.mock("./linksApi", async (orig) => {
	const actual = await orig<typeof import("./linksApi")>();
	return {
		...actual,
		linksApi: { ...actual.linksApi, publicLink: vi.fn(), startPublic: vi.fn() },
	};
});

function conflict(code: string) {
	return new AxiosError("No", "409", undefined, undefined, {
		status: 409,
		data: { detail: "x", code },
	} as never);
}

describe("PublicLinkPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(linksApi.publicLink).mockResolvedValue(publicLink());
		vi.mocked(linksApi.startPublic).mockResolvedValue(
			started({ redirect_url: "https://pay.test/s/1" }),
		);
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("shows the academy, title, amount, fee and total, and pays with the provider", async () => {
		const user = userEvent.setup();
		renderWithRouter(<PublicLinkPage token="tok-5" />);
		expect(await screen.findByText("Demo Academy")).toBeVisible();
		expect(screen.getByText("June fees")).toBeVisible();
		expect(screen.getByText("EGP 500.00")).toBeVisible();
		expect(screen.getByText("EGP 25.00")).toBeVisible();
		expect(screen.getByText("EGP 525.00")).toBeVisible();
		expect(screen.getByText("For Abu Khalid")).toBeVisible();
		await user.click(screen.getByRole("button", { name: "Pay with Stripe" }));
		expect(linksApi.startPublic).toHaveBeenCalledWith("tok-5");
		await waitFor(() => expect(go).toHaveBeenCalledWith("https://pay.test/s/1"));
	});

	it("renders the title and description as plain text, escaped", async () => {
		vi.mocked(linksApi.publicLink).mockResolvedValue(
			publicLink({
				title: "<img src=x onerror=alert(1)>",
				description: "<script>alert(1)</script>\nSecond line",
			}),
		);
		const { container } = renderWithRouter(<PublicLinkPage token="tok-5" />);
		expect(
			await screen.findByText("<img src=x onerror=alert(1)>"),
		).toBeVisible();
		expect(container.querySelector("script, img")).toBeNull();
		expect(screen.getByText(/<script>alert\(1\)<\/script>/)).toBeVisible();
	});

	it("labels a donation and hides a zero fee", async () => {
		vi.mocked(linksApi.publicLink).mockResolvedValue(
			publicLink({ kind: "donation", fee_minor: 0, provider: "paypal" }),
		);
		renderWithRouter(<PublicLinkPage token="tok-5" />);
		expect(
			await screen.findByRole("button", { name: "Donate with PayPal" }),
		).toBeEnabled();
		expect(screen.queryByText("Service fee")).toBeNull();
	});

	it.each([
		["paid", "This link has been paid. Thank you."],
		["cancelled", "This link was cancelled."],
	])("says why a %s link cannot be paid", async (status, words) => {
		vi.mocked(linksApi.publicLink).mockResolvedValue(
			publicLink({ status: status as "paid", payable: false }),
		);
		renderWithRouter(<PublicLinkPage token="tok-5" />);
		expect(await screen.findByText(words)).toBeVisible();
		expect(screen.getByRole("button", { name: /Pay with/ })).toBeDisabled();
	});

	it("disables Pay with the unavailable note when the provider cannot take it", async () => {
		vi.mocked(linksApi.publicLink).mockResolvedValue(
			publicLink({ payable: false }),
		);
		renderWithRouter(<PublicLinkPage token="tok-5" />);
		expect(
			await screen.findByText("Online payment is unavailable."),
		).toBeVisible();
		expect(screen.getByRole("button", { name: /Pay with/ })).toBeDisabled();
	});

	it("shows the server's reason when the checkout cannot start", async () => {
		const user = userEvent.setup();
		vi.mocked(linksApi.startPublic).mockRejectedValue(
			conflict("gateways.link_closed"),
		);
		renderWithRouter(<PublicLinkPage token="tok-5" />);
		await user.click(
			await screen.findByRole("button", { name: "Pay with Stripe" }),
		);
		expect(
			await screen.findByText("This link is no longer open."),
		).toBeVisible();
		expect(go).not.toHaveBeenCalled();
	});

	it("says so when the link does not exist", async () => {
		vi.mocked(linksApi.publicLink).mockRejectedValue(
			new AxiosError("No", "404", undefined, undefined, { status: 404 } as never),
		);
		renderWithRouter(<PublicLinkPage token="nope" />);
		expect(
			await screen.findByText("This payment link doesn't exist."),
		).toBeVisible();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderWithRouter(<PublicLinkPage token="tok-5" />);
		expect(await screen.findByText("Demo Academy")).toBeVisible();
		expect(screen.getByRole("button", { name: "الدفع عبر Stripe" })).toBeEnabled();
	});
});
```

In `ReturnPage.test.tsx`, add inside the existing `describe` (it already mocks `gatewaysApi.checkout` and
`identityApi.me`; reuse its `renderWithRouter` and `body` helpers):

```tsx
	it("shows only the status, with no link, for a payment-link checkout", async () => {
		vi.mocked(gatewaysApi.checkout).mockResolvedValue({
			...body("completed"),
			purpose: "payment_link",
			reference_id: 5,
		});
		vi.mocked(identityApi.me).mockRejectedValue(new Error("401")); // not signed in
		renderWithRouter(<ReturnPage checkoutId={ID} />, { extraPaths: PATHS });
		expect(await screen.findByText("Paid — thank you.")).toBeVisible();
		expect(screen.queryByRole("link")).toBeNull();
	});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm vitest run src/features/gateways/PublicLinkPage.test.tsx`
Expected: FAIL (the modules do not exist).

- [ ] **Step 3: Types, API and hooks**

`dashboard/src/features/identity/schemas.ts`, `FeatureCode`: replace the final `| "online_payments";` with

```ts
	| "online_payments"
	// Phase B3, slice B3g.
	| "payment_links"
	| "payment_receipts";
```

`dashboard/src/features/gateways/schemas.ts`: add `"link_closed",` as the last entry of `ATTENTION_CODES`.

`dashboard/src/features/gateways/linkSchemas.ts`:

```ts
import type { Person } from "@/features/billing/schemas";
import type { Provider } from "./schemas";

export const LINK_KINDS = ["payment", "donation"] as const;
export type LinkKind = (typeof LINK_KINDS)[number];
export const LINK_STATUSES = ["open", "paid", "cancelled"] as const;
export type LinkStatus = (typeof LINK_STATUSES)[number];

/** B3g §4.2: one payment link, as the office reads it. */
export interface PaymentLinkRow {
	id: number;
	kind: LinkKind;
	title: string;
	description: string;
	payer: {
		type: "student" | "unregistered";
		/** The student's user id. */
		student_id: number | null;
		name: string;
		email: string;
		phone: string;
	};
	provider: Provider;
	amount_minor: number;
	currency: string;
	add_fee: boolean;
	fee_minor: number;
	status: LinkStatus;
	url: string;
	checkout_id: string | null;
	paid_at: string | null;
	created_by: Person | null;
	created_at: string;
}

/** B3g §4.3: what anyone holding the token sees. */
export interface PublicLink {
	academy_name: string;
	kind: LinkKind;
	title: string;
	description: string;
	payer_name: string;
	amount_minor: number;
	fee_minor: number;
	currency: string;
	provider: Provider;
	status: LinkStatus;
	payable: boolean;
}

/** The create body (§4.2). `student` is the student's user id. */
export interface LinkBody {
	kind: LinkKind;
	title: string;
	description?: string;
	student?: number;
	payer_name?: string;
	payer_email?: string;
	payer_phone?: string;
	provider: Provider;
	amount_minor: number;
	currency?: string;
	add_fee?: boolean;
}
```

(Task 9 adds the create form's schema to this file.)

`dashboard/src/features/gateways/linksApi.ts`:

```ts
import { api, clean, type Paginated, type QueryParams } from "@/lib/api";
import type { LinkBody, PaymentLinkRow, PublicLink } from "./linkSchemas";
import type { StartedCheckout } from "./schemas";

const G = "gateways/";

export const linksApi = {
	list: async (params: QueryParams) =>
		(
			await api.get<Paginated<PaymentLinkRow>>(`${G}links/`, {
				params: clean(params),
			})
		).data,
	create: async (body: LinkBody) =>
		(await api.post<PaymentLinkRow>(`${G}links/`, body)).data,
	cancel: async (id: number) =>
		(await api.post<PaymentLinkRow>(`${G}links/${id}/cancel/`)).data,
	publicLink: async (token: string) =>
		(await api.get<PublicLink>(`${G}pay/${encodeURIComponent(token)}/`)).data,
	startPublic: async (token: string) =>
		(
			await api.post<StartedCheckout>(
				`${G}pay/${encodeURIComponent(token)}/checkout/`,
			)
		).data,
};
```

`dashboard/src/features/gateways/linkQueries.ts`:

```ts
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import type { QueryParams } from "@/lib/api";
import { gatewaysKey } from "./queries";
import { linksApi } from "./linksApi";

export function useLinks(params: QueryParams) {
	return useQuery({
		queryKey: [...gatewaysKey, "links", params],
		queryFn: () => linksApi.list(params),
		placeholderData: keepPreviousData,
	});
}

/** The public page's link: no retry (a 404 is final), no refetch on focus
 * (the payer is about to leave for the provider and come back). */
export function usePublicLink(token: string) {
	return useQuery({
		queryKey: [...gatewaysKey, "public-link", token],
		queryFn: () => linksApi.publicLink(token),
		retry: false,
		refetchOnWindowFocus: false,
	});
}
```

`dashboard/src/features/gateways/index.ts`: add

```ts
export * from "./linkQueries";
export * from "./linkSchemas";
export { linksApi } from "./linksApi";
export { PublicFrame } from "./PublicFrame";
export { PublicLinkPage } from "./PublicLinkPage";
```

(keep the exports sorted the way biome wants; `pnpm exec biome check --write src` fixes the order).

- [ ] **Step 4: The frame and the page**

`dashboard/src/features/gateways/PublicFrame.tsx`:

```tsx
import type { ReactNode } from "react";

/** The plain frame of the three public `/pay/*` pages (G-15): no app shell, no
 * sign-in. Phone width first, with the 16px gutter. */
export function PublicFrame({ children }: { children: ReactNode }) {
	return (
		<main className="mx-auto flex min-h-dvh w-full max-w-lg flex-col justify-center gap-4 px-4 py-8">
			{children}
		</main>
	);
}
```

`dashboard/src/features/gateways/PublicLinkPage.tsx`:

```tsx
import { useMutation } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
} from "@/ui";
import { gatewaysErrorText } from "./errors";
import { usePublicLink } from "./linkQueries";
import { linksApi } from "./linksApi";
import { go } from "./redirect";
import type { Provider } from "./schemas";

const NAMES: Record<Provider, string> = { stripe: "Stripe", paypal: "PayPal" };

/** B3g §6: whoever holds the link pays without logging in. Everything shown
 * comes from the server; the title and description are plain text, rendered
 * escaped (G-16). The Pay button is disabled, with the reason, when the link
 * cannot be paid (G-17). */
export function PublicLinkPage({ token }: { token: string }) {
	const { t } = useTranslation();
	const { data, isError } = usePublicLink(token);
	const start = useMutation({ mutationFn: () => linksApi.startPublic(token) });
	const [failure, setFailure] = useState("");
	if (isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("gateways.link.notFound")}</AlertDescription>
			</Alert>
		);
	}
	if (!data) return <Spinner />;

	async function pay() {
		setFailure("");
		try {
			const started = await start.mutateAsync();
			go(started.redirect_url);
		} catch (error) {
			setFailure(gatewaysErrorText(error, t));
		}
	}

	const provider = NAMES[data.provider];
	const note =
		data.status === "paid"
			? t("gateways.link.paid")
			: data.status === "cancelled"
				? t("gateways.link.cancelled")
				: data.payable
					? ""
					: t("gateways.link.unavailable");
	return (
		<Card>
			<CardHeader>
				<p className="text-sm text-muted-foreground">{data.academy_name}</p>
				<CardTitle>{data.title}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				{data.description ? (
					<p className="whitespace-pre-line">{data.description}</p>
				) : null}
				{data.payer_name ? (
					<p className="text-sm text-muted-foreground">
						{t("gateways.link.for", { name: data.payer_name })}
					</p>
				) : null}
				<dl className="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
					<dt>{t("gateways.pay.balance")}</dt>
					<dd>
						<Money minor={data.amount_minor} currency={data.currency} />
					</dd>
					{data.fee_minor > 0 ? (
						<>
							<dt>{t("gateways.pay.fee")}</dt>
							<dd>
								<Money minor={data.fee_minor} currency={data.currency} />
							</dd>
						</>
					) : null}
					<dt className="font-medium">{t("gateways.pay.total")}</dt>
					<dd className="font-medium">
						<Money
							minor={data.amount_minor + data.fee_minor}
							currency={data.currency}
						/>
					</dd>
				</dl>
				{note ? (
					<p
						className={
							data.status === "paid" ? "text-success" : "text-muted-foreground"
						}
					>
						{note}
					</p>
				) : null}
				{failure ? (
					<Alert variant="destructive">
						<AlertDescription>{failure}</AlertDescription>
					</Alert>
				) : null}
				<Button
					disabled={!data.payable || start.isPending}
					onClick={() => void pay()}
				>
					{t(
						data.kind === "donation"
							? "gateways.link.donate"
							: "gateways.link.pay",
						{ provider },
					)}
				</Button>
			</CardContent>
		</Card>
	);
}
```

(`gateways.pay.balance` is B3b's "Amount due"; `fee` and `total` are B3b's too.)

- [ ] **Step 5: The routes**

Move the two routes out of `_authed`:

```bash
git -C dashboard mv 'src/routes/_authed/pay.return.tsx' 'src/routes/pay.return.tsx'
git -C dashboard mv 'src/routes/_authed/pay.simulate.$checkoutId.tsx' 'src/routes/pay.simulate.$checkoutId.tsx'
```

`dashboard/src/routes/pay.return.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PublicFrame, ReturnPage } from "@/features/gateways";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/pay/return")({
	// No feature (plan D16): money may arrive after the switch goes off. Public
	// (G-15): a payment-link payer is not signed in.
	validateSearch: (
		search: Record<string, unknown>,
	): { checkout: string | undefined; cancelled?: true } => ({
		checkout: typeof search.checkout === "string" ? search.checkout : undefined,
		// The provider's cancel URL adds cancelled=1 (parsed as 1 or "1").
		...(String(search.cancelled) === "1" ? { cancelled: true } : {}),
	}),
	component: function PayReturnRoute() {
		const { t } = useTranslation();
		const { checkout, cancelled } = Route.useSearch();
		usePageTitle(t("gateways.return.title"));
		return (
			<PublicFrame>
				<PageHeader title={t("gateways.return.title")} />
				<ReturnPage checkoutId={checkout} cancelled={cancelled} />
			</PublicFrame>
		);
	},
});
```

Keep any change B3c made to this file's `validateSearch` (it accepts `1`, `"1"` and `true`): copy B3c's
version of the search parser, change only the route id and the frame.

`dashboard/src/routes/pay.simulate.$checkoutId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PublicFrame, SimulatorPage } from "@/features/gateways";

export const Route = createFileRoute("/pay/simulate/$checkoutId")({
	component: function PaySimulateRoute() {
		const { t } = useTranslation();
		const { checkoutId } = Route.useParams();
		usePageTitle(t("gateways.simulate.title"));
		return (
			<PublicFrame>
				<SimulatorPage checkoutId={checkoutId} />
			</PublicFrame>
		);
	},
});
```

`dashboard/src/routes/pay.link.$token.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PublicFrame, PublicLinkPage } from "@/features/gateways";

// Public (G-15, G-16): no sign-in; the server answers 404 while `payment_links`
// is off, which the page shows as "doesn't exist".
export const Route = createFileRoute("/pay/link/$token")({
	component: function PayLinkRoute() {
		const { t } = useTranslation();
		const { token } = Route.useParams();
		usePageTitle(t("gateways.link.title"));
		return (
			<PublicFrame>
				<PublicLinkPage token={token} />
			</PublicFrame>
		);
	},
});
```

Regenerate the route tree and look for stale references:
`HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm exec vite build`, then
`grep -rn "_authed/pay" src` must print nothing (fix any test or link that named the old ids; in-app
navigation uses the path `/pay/return`, which is unchanged).

- [ ] **Step 6: Strings**

`dashboard/src/locales/en/gateways.json`: add `"link_closed": "The link was already paid or cancelled when the money arrived."`
to `attention`, `"link_closed": "This link is no longer open."` to `errors`, and a new `link` object:

```json
	"link": {
		"title": "Payment link",
		"notFound": "This payment link doesn't exist.",
		"for": "For {{name}}",
		"pay": "Pay with {{provider}}",
		"donate": "Donate with {{provider}}",
		"paid": "This link has been paid. Thank you.",
		"cancelled": "This link was cancelled.",
		"unavailable": "Online payment is unavailable."
	}
```

`dashboard/src/locales/ar/gateways.json`: the same keys:

```json
	"link": {
		"title": "رابط دفع",
		"notFound": "رابط الدفع هذا غير موجود.",
		"for": "الدفع لصالح {{name}}",
		"pay": "الدفع عبر {{provider}}",
		"donate": "التبرع عبر {{provider}}",
		"paid": "تم دفع هذا الرابط. شكرًا لك.",
		"cancelled": "تم إلغاء هذا الرابط.",
		"unavailable": "الدفع الإلكتروني غير متاح."
	}
```

with `attention.link_closed`: `"كان الرابط مدفوعًا أو ملغيًا عند وصول المبلغ."` and `errors.link_closed`:
`"هذا الرابط لم يعد مفتوحًا."`.

- [ ] **Step 7: Run the tests, format and commit**

```bash
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm exec biome check --write src e2e
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm vitest run src/features/gateways src/routes src/features/identity src/lib
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm tsc --noEmit
```

Expected: all pass; `pnpm vitest run src/features/gateways 2>&1 | grep -c "not wrapped in act"` prints 0.

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(gateways): public pay page, and the return and simulator pages outside the app shell"
```

---
### Task 9: Dashboard — Billing → Payment links (list, create dialog, copy, cancel)

**Files:**
- Modify: `dashboard/src/features/gateways/linkSchemas.ts` (the form schema), `index.ts`
- Create: `dashboard/src/features/gateways/LinkDialog.tsx`, `PaymentLinksPage.tsx`
- Create: `dashboard/src/routes/_authed/billing.links.tsx`
- Modify: `dashboard/src/features/shell/nav.ts`, `nav.test.ts`, `dashboard/src/features/finance/landing.ts`, `landing.test.ts`, `dashboard/src/routes/permissions.test.ts`
- Modify: `dashboard/src/locales/en/gateways.json`, `dashboard/src/locales/ar/gateways.json`
- Test: `dashboard/src/features/gateways/linkSchemas.test.ts`, `LinkDialog.test.tsx`, `PaymentLinksPage.test.tsx`

**Interfaces:**
- Consumes: Task 8's `linksApi`, `useLinks`, `PaymentLinkRow`, `LinkBody`, `LINK_KINDS`, `LINK_STATUSES`; Plan 20/22's `useGatewaysMutation`, `useGatewaySettings`, `PROVIDERS`, `Provider`; `useListParams`, `pageCount`, `DateFilter`, `SearchBox` (`@/features/finance/shared`); `usePeople("students", …)`; `useAcademySettings`; `useCan`, `useHasFeature`; `CURRENCIES`; `toMinor`; billing's `Money`; `Confirm`, `Pager`.
- Produces:
  - `linkSchemas.ts`: `linkFormSchema`, `LinkFormValues`, `toLinkBody(values: LinkFormValues): LinkBody`
  - `<LinkDialog />` (trigger "Create link"), `<PaymentLinksPage />`
  - route `/_authed/billing/links` (`payment_link.view_any`, feature `payment_links`)
  - nav item `/billing/links` (label key `gateways.nav.links`), landing entry after invoices

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/gateways/linkSchemas.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { type LinkFormValues, linkFormSchema, toLinkBody } from "./linkSchemas";

const base: LinkFormValues = {
	payer: "unregistered",
	student: "",
	payer_name: "Abu Khalid",
	payer_email: "",
	payer_phone: "",
	kind: "payment",
	provider: "stripe",
	currency: "EGP",
	amount: "500.00",
	add_fee: true,
	title: "June fees",
	description: "",
};

function problems(values: Partial<LinkFormValues>) {
	const result = linkFormSchema.safeParse({ ...base, ...values });
	return result.success
		? {}
		: Object.fromEntries(
				result.error.issues.map((i) => [String(i.path[0]), i.message]),
			);
}

describe("linkFormSchema", () => {
	it("accepts a complete unregistered link", () => {
		expect(problems({})).toEqual({});
	});

	it("needs a student for a registered payer and a name for the other", () => {
		expect(problems({ payer: "student" })).toEqual({
			student: "billing.errors.required",
		});
		expect(problems({ payer_name: "  " })).toEqual({
			payer_name: "gateways.links.errors.name",
		});
		expect(problems({ payer: "student", student: "11" })).toEqual({});
	});

	it("checks the email, the title and the amount for the currency", () => {
		expect(problems({ payer_email: "nope" })).toEqual({
			payer_email: "gateways.links.errors.email",
		});
		expect(problems({ title: " " }).title).toBe("billing.errors.required");
		expect(problems({ amount: "0" }).amount).toBe("billing.errors.amountInvalid");
		expect(problems({ amount: "5.001" }).amount).toBe("billing.errors.amountInvalid");
		expect(problems({ currency: "JPY", amount: "5.5" }).amount).toBe(
			"billing.errors.amountInvalid",
		);
		expect(problems({ currency: "KWD", amount: "5.125" })).toEqual({});
	});
});

describe("toLinkBody", () => {
	it("builds an unregistered payment link with its fee choice", () => {
		expect(toLinkBody({ ...base, payer_email: "a@b.test" })).toEqual({
			kind: "payment",
			title: "June fees",
			provider: "stripe",
			amount_minor: 50000,
			currency: "EGP",
			add_fee: true,
			payer_name: "Abu Khalid",
			payer_email: "a@b.test",
		});
	});

	it("sends the student's user id and no payer text for a registered payer", () => {
		const body = toLinkBody({ ...base, payer: "student", student: "11", payer_name: "x" });
		expect(body.student).toBe(11);
		expect(body).not.toHaveProperty("payer_name");
	});

	it("never sends a fee flag for a donation, and keeps a description", () => {
		const body = toLinkBody({
			...base,
			kind: "donation",
			provider: "paypal",
			currency: "USD",
			description: " Eid ",
		});
		expect(body).not.toHaveProperty("add_fee");
		expect(body.description).toBe("Eid");
		expect(body.amount_minor).toBe(50000);
	});
});
```

`dashboard/src/features/gateways/LinkDialog.test.tsx`:

```tsx
import { act, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import { peopleApi } from "@/features/people/api";
import i18n from "@/lib/i18n";
import { adminWith } from "@/test/access-fixtures";
import { gatewaySettings, paymentLinkRow } from "@/test/gateways-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { gatewaysApi } from "./api";
import { LinkDialog } from "./LinkDialog";
import { linksApi } from "./linksApi";

vi.mock("./linksApi", async (orig) => {
	const actual = await orig<typeof import("./linksApi")>();
	return { ...actual, linksApi: { ...actual.linksApi, create: vi.fn() } };
});
vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, gatewaysApi: { ...actual.gatewaysApi, settings: vi.fn() } };
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});

async function open(me = adminWith("donations")) {
	const user = userEvent.setup();
	renderWithRouter(
		<CanProvider me={me}>
			<LinkDialog />
		</CanProvider>,
	);
	await user.click(await screen.findByRole("button", { name: "Create link" }));
	const dialog = await screen.findByRole("dialog");
	// The academy's currency and the fee setting arrive after the dialog opens
	// and re-seed the form: wait for them before typing anything.
	await waitFor(() =>
		expect(screen.getByLabelText(/^Currency/)).toHaveValue("EGP"),
	);
	await waitFor(() => expect(gatewaysApi.settings).toHaveBeenCalled());
	await act(async () => {});
	return { user, dialog };
}

describe("LinkDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ default_currency: "EGP" }),
		);
		vi.mocked(gatewaysApi.settings).mockResolvedValue(gatewaySettings());
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 11, user: { full_name: "Yusuf" } }]) as never,
		);
		vi.mocked(linksApi.create).mockResolvedValue(paymentLinkRow());
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("creates a link for an unregistered payer with the fee on by default", async () => {
		const { user } = await open();
		await user.type(screen.getByLabelText(/^Payer's name/), "Abu Khalid");
		await user.type(screen.getByLabelText(/^Title/), "June fees");
		await user.type(screen.getByLabelText(/^Amount/), "500");
		await user.click(screen.getByRole("button", { name: "Create link" }));
		await waitFor(() =>
			expect(linksApi.create).toHaveBeenCalledWith({
				kind: "payment",
				title: "June fees",
				provider: "stripe",
				amount_minor: 50000,
				currency: "EGP",
				add_fee: true,
				payer_name: "Abu Khalid",
			}),
		);
	});

	it("starts the fee off when the academy's setting is off", async () => {
		vi.mocked(gatewaysApi.settings).mockResolvedValue(
			gatewaySettings({ fee: { enabled: false, basis_points: 500 } }),
		);
		await open();
		await waitFor(() =>
			expect(screen.getByLabelText("Add the service fee")).not.toBeChecked(),
		);
	});

	it("names a registered student by id", async () => {
		const { user } = await open();
		await user.selectOptions(screen.getByLabelText(/^Payer$/), "student");
		await user.selectOptions(await screen.findByLabelText(/^Student/), "11");
		await user.type(screen.getByLabelText(/^Title/), "June fees");
		await user.type(screen.getByLabelText(/^Amount/), "10");
		await user.click(screen.getByRole("button", { name: "Create link" }));
		await waitFor(() => expect(linksApi.create).toHaveBeenCalled());
		const body = vi.mocked(linksApi.create).mock.calls[0][0];
		expect(body.student).toBe(11);
		expect(body).not.toHaveProperty("payer_name");
	});

	it("offers Donation only while donations are on, and then hides the fee", async () => {
		const { user } = await open();
		await user.selectOptions(screen.getByLabelText(/^Type/), "donation");
		expect(screen.queryByLabelText("Add the service fee")).toBeNull();
	});

	it("hides Donation while donations are off", async () => {
		await open(adminWith());
		expect(screen.queryByRole("option", { name: "Donation" })).toBeNull();
	});

	it("shows a server refusal on its field and keeps the dialog open", async () => {
		const { user, dialog } = await open();
		vi.mocked(linksApi.create).mockRejectedValue(
			new AxiosError("No", "400", undefined, undefined, {
				status: 400,
				data: { errors: { provider: ["This payment method cannot take this amount."] } },
			} as never),
		);
		await user.type(screen.getByLabelText(/^Payer's name/), "Abu Khalid");
		await user.type(screen.getByLabelText(/^Title/), "June fees");
		await user.type(screen.getByLabelText(/^Amount/), "500");
		await user.click(screen.getByRole("button", { name: "Create link" }));
		expect(
			await screen.findByText("This payment method cannot take this amount."),
		).toBeVisible();
		expect(dialog).toBeVisible();
	});
});
```

(The 400 body shape above follows `parseApiError`; if the codebase's error body differs, copy the shape
`InvoiceForm.test.tsx` uses for its server error case.)

`dashboard/src/features/gateways/PaymentLinksPage.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import { peopleApi } from "@/features/people/api";
import i18n from "@/lib/i18n";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { gatewaySettings, paymentLinkRow } from "@/test/gateways-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { gatewaysApi } from "./api";
import { linksApi } from "./linksApi";
import { PaymentLinksPage } from "./PaymentLinksPage";

vi.mock("./linksApi", async (orig) => {
	const actual = await orig<typeof import("./linksApi")>();
	return {
		...actual,
		linksApi: { ...actual.linksApi, list: vi.fn(), cancel: vi.fn(), create: vi.fn() },
	};
});
vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, gatewaysApi: { ...actual.gatewaysApi, settings: vi.fn() } };
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});

const lastParams = () => vi.mocked(linksApi.list).mock.calls.at(-1)?.[0];

describe("PaymentLinksPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(gatewaysApi.settings).mockResolvedValue(gatewaySettings());
		vi.mocked(peopleApi.list).mockResolvedValue(page([]) as never);
		vi.mocked(linksApi.list).mockResolvedValue(
			page([
				paymentLinkRow(),
				paymentLinkRow({
					id: 6,
					title: "Eid gift",
					kind: "donation",
					provider: "paypal",
					currency: "USD",
					fee_minor: 0,
					add_fee: false,
					status: "paid",
					payer: { type: "unregistered", student_id: null, name: "Umm Sara", email: "u@x.test", phone: "" },
				}),
			]),
		);
		vi.mocked(linksApi.cancel).mockResolvedValue(paymentLinkRow({ status: "cancelled" }));
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("lists each link with its payer, amount, fee and status", async () => {
		renderWithRouter(<PaymentLinksPage />);
		const table = await screen.findByRole("table");
		expect(within(table).getByText("June fees")).toBeVisible();
		expect(within(table).getByText("Abu Khalid")).toBeVisible();
		expect(within(table).getByText("EGP 500.00")).toBeVisible();
		expect(within(table).getByText("EGP 25.00")).toBeVisible();
		expect(within(table).getByText("Eid gift")).toBeVisible();
		expect(within(table).getByText("Paid")).toBeVisible();
	});

	it("passes its filters to the server and resets to page 1", async () => {
		const user = userEvent.setup();
		renderWithRouter(<PaymentLinksPage />);
		await screen.findByRole("table");
		await user.selectOptions(screen.getByLabelText("Status"), "open");
		await waitFor(() => expect(lastParams()).toMatchObject({ status: "open", page: 1 }));
		await user.selectOptions(screen.getByLabelText("Type"), "donation");
		await user.selectOptions(screen.getByLabelText("Provider"), "paypal");
		await user.type(screen.getByRole("searchbox"), "Eid");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({
				status: "open",
				kind: "donation",
				provider: "paypal",
				q: "Eid",
			}),
		);
	});

	it("copies a link's address", async () => {
		const user = userEvent.setup();
		renderWithRouter(<PaymentLinksPage />);
		await screen.findByRole("table");
		await user.click(screen.getAllByRole("button", { name: "Copy link" })[0]);
		expect(await navigator.clipboard.readText()).toBe(
			"http://demo.etqan.localhost/app/pay/link/tok-5",
		);
	});

	it("cancels an open link after confirming, and offers nothing on a paid one", async () => {
		const user = userEvent.setup();
		renderWithRouter(<PaymentLinksPage />);
		await screen.findByRole("table");
		expect(screen.getAllByRole("button", { name: "Cancel link" })).toHaveLength(1);
		await user.click(screen.getByRole("button", { name: "Cancel link" }));
		await user.click(
			within(await screen.findByRole("alertdialog")).getByRole("button", {
				name: "Cancel this link",
			}),
		);
		await waitFor(() => expect(linksApi.cancel).toHaveBeenCalledWith(5));
	});

	it("hides what a staff account may not do", async () => {
		renderWithRouter(
			<CanProvider me={{ ...staffMe("payment_link.view_any"), features: ["payment_links"] }}>
				<PaymentLinksPage />
			</CanProvider>,
		);
		await screen.findByRole("table");
		expect(screen.queryByRole("button", { name: "Create link" })).toBeNull();
		expect(screen.queryByRole("button", { name: "Cancel link" })).toBeNull();
		expect(screen.getAllByRole("button", { name: "Copy link" })).toHaveLength(2);
	});

	it("says when there are none or the list failed", async () => {
		vi.mocked(linksApi.list).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(
			<CanProvider me={adminWith()}>
				<PaymentLinksPage />
			</CanProvider>,
		);
		expect(await screen.findByText("No payment links yet.")).toBeVisible();
		unmount();
		vi.mocked(linksApi.list).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<PaymentLinksPage />);
		expect(
			await screen.findByText("The payment links could not be loaded."),
		).toBeVisible();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderWithRouter(<PaymentLinksPage />);
		expect(await screen.findByText("June fees")).toBeVisible();
		expect(screen.getAllByRole("button", { name: "نسخ الرابط" })).toHaveLength(2);
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm vitest run src/features/gateways/linkSchemas.test.ts`
Expected: FAIL (`linkFormSchema` is not exported).

- [ ] **Step 3: The form schema**

`dashboard/src/features/gateways/linkSchemas.ts`: add `import { z } from "zod";`, `import { minorDigits, toMinor } from "@/lib/money";`
and change the `./schemas` import to `import { PROVIDERS, type Provider } from "./schemas";`, then append:

```ts
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/** The create dialog's form. Messages are i18n keys, translated by
 * `useFieldError`. The amount is checked against the chosen currency's minor
 * digits, as the invoice form does. */
export const linkFormSchema = z
	.object({
		payer: z.enum(["student", "unregistered"]),
		student: z.string(),
		payer_name: z.string().max(120),
		payer_email: z.string().max(254),
		payer_phone: z.string().max(30),
		kind: z.enum(LINK_KINDS),
		provider: z.enum(PROVIDERS),
		currency: z.string().regex(/^[A-Z]{3}$/, "billing.errors.required"),
		amount: z.string().min(1, "billing.errors.required"),
		add_fee: z.boolean(),
		title: z.string().trim().min(1, "billing.errors.required").max(200),
		description: z.string(),
	})
	.superRefine((data, ctx) => {
		const refuse = (path: string, message: string) =>
			ctx.addIssue({ code: "custom", path: [path], message });
		if (data.payer === "student" && !data.student) {
			refuse("student", "billing.errors.required");
		}
		if (data.payer === "unregistered") {
			if (!data.payer_name.trim()) refuse("payer_name", "gateways.links.errors.name");
			const email = data.payer_email.trim();
			if (email && !EMAIL.test(email)) refuse("payer_email", "gateways.links.errors.email");
		}
		const digits = minorDigits(data.currency);
		const pattern =
			digits > 0 ? new RegExp(`^\\d+(\\.\\d{1,${digits}})?$`) : /^\d+$/;
		const amount = data.amount.trim();
		if (amount && !(pattern.test(amount) && Number(amount) > 0)) {
			refuse("amount", "billing.errors.amountInvalid");
		}
	});
export type LinkFormValues = z.infer<typeof linkFormSchema>;

/** The request body (§4.2): a registered payer by user id, otherwise the typed
 * payer; the fee flag only for a payment (a donation never has one). */
export function toLinkBody(values: LinkFormValues): LinkBody {
	const body: LinkBody = {
		kind: values.kind,
		title: values.title.trim(),
		provider: values.provider,
		amount_minor: toMinor(values.amount.trim(), values.currency),
		currency: values.currency,
	};
	const description = values.description.trim();
	if (description) body.description = description;
	if (values.kind === "payment") body.add_fee = values.add_fee;
	if (values.payer === "student") {
		body.student = Number(values.student);
	} else {
		body.payer_name = values.payer_name.trim();
		if (values.payer_email.trim()) body.payer_email = values.payer_email.trim();
		if (values.payer_phone.trim()) body.payer_phone = values.payer_phone.trim();
	}
	return body;
}
```

- [ ] **Step 4: The create dialog**

`dashboard/src/features/gateways/LinkDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { useHasFeature } from "@/features/identity/permissions";
import { usePeople } from "@/features/people";
import { CURRENCIES } from "@/lib/currencies";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
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
import { useGatewaySettings, useGatewaysMutation } from "./queries";
import {
	LINK_KINDS,
	type LinkFormValues,
	linkFormSchema,
	toLinkBody,
} from "./linkSchemas";
import { linksApi } from "./linksApi";
import { PROVIDERS, type Provider } from "./schemas";

const NAMES: Record<Provider, string> = { stripe: "Stripe", paypal: "PayPal" };

/** B3g §6: a new payment link. The payer is a registered student or someone
 * typed in; Donation is offered only while `donations` is on; the fee toggle
 * starts from the academy's setting (on when this account may not read it:
 * the server then decides only if the box is left out, so it is always sent)
 * and is hidden for a donation. */
export function LinkDialog() {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const hasFeature = useHasFeature();
	const [open, setOpen] = useState(false);
	const [query, setQuery] = useState("");
	const { data: academy } = useAcademySettings();
	const { data: settings } = useGatewaySettings();
	const { data: students } = usePeople("students", {
		is_active: "true",
		page_size: 100,
		q: query.trim(),
	});
	const create = useGatewaysMutation(linksApi.create);
	const currency = academy?.default_currency ?? "";
	const {
		register,
		handleSubmit,
		setError,
		reset,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<LinkFormValues>({
		resolver: zodResolver(linkFormSchema),
		values: {
			payer: "unregistered",
			student: "",
			payer_name: "",
			payer_email: "",
			payer_phone: "",
			kind: "payment",
			provider: "stripe",
			currency,
			amount: "",
			add_fee: settings?.fee.enabled ?? true,
			title: "",
			description: "",
		},
	});
	const payer = watch("payer");
	const kind = watch("kind");
	const chosen = watch("currency") || currency;
	const currencies = Array.from(new Set([currency, ...CURRENCIES])).filter(Boolean);

	async function onSubmit(values: LinkFormValues) {
		try {
			await create.mutateAsync(toLinkBody(values));
			reset();
			setOpen(false);
			toast({ description: t("gateways.links.created"), variant: "success" });
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
				<Button size="sm">{t("gateways.links.create")}</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("gateways.links.dialogTitle")}</DialogTitle>
				<DialogDescription>{t("gateways.links.dialogHelp")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<div className="grid gap-4 sm:grid-cols-2">
						<Field id="link-payer" label={t("gateways.links.form.payerType")}>
							<Select {...register("payer")}>
								<option value="unregistered">
									{t("gateways.links.form.payerOther")}
								</option>
								<option value="student">
									{t("gateways.links.form.payerStudent")}
								</option>
							</Select>
						</Field>
						<Field id="link-kind" label={t("gateways.links.form.kind")}>
							<Select {...register("kind")}>
								{LINK_KINDS.filter(
									(k) => k === "payment" || hasFeature("donations"),
								).map((k) => (
									<option key={k} value={k}>
										{t(`gateways.links.kinds.${k}`)}
									</option>
								))}
							</Select>
						</Field>
						{payer === "student" ? (
							<>
								<Field
									id="link-student-search"
									label={t("gateways.links.form.findStudent")}
								>
									<Input
										type="search"
										value={query}
										onChange={(e) => setQuery(e.target.value)}
									/>
								</Field>
								<Field
									id="link-student"
									label={t("gateways.links.form.student")}
									error={fieldError(errors.student?.message)}
									required
								>
									<Select {...register("student")}>
										<option value="">—</option>
										{students?.results.map((p) => (
											<option key={p.id} value={p.id}>
												{p.user.full_name}
											</option>
										))}
									</Select>
								</Field>
							</>
						) : (
							<>
								<Field
									id="link-payer_name"
									label={t("gateways.links.form.payerName")}
									error={fieldError(errors.payer_name?.message)}
									required
								>
									<Input {...register("payer_name")} />
								</Field>
								<Field
									id="link-payer_email"
									label={t("gateways.links.form.payerEmail")}
									error={fieldError(errors.payer_email?.message)}
								>
									<Input type="email" dir="ltr" {...register("payer_email")} />
								</Field>
								<Field
									id="link-payer_phone"
									label={t("gateways.links.form.payerPhone")}
									error={fieldError(errors.payer_phone?.message)}
								>
									<Input dir="ltr" {...register("payer_phone")} />
								</Field>
							</>
						)}
						<Field
							id="link-provider"
							label={t("gateways.links.form.provider")}
							error={fieldError(errors.provider?.message)}
						>
							<Select {...register("provider")}>
								{PROVIDERS.map((p) => (
									<option key={p} value={p}>
										{NAMES[p]}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="link-currency"
							label={t("gateways.links.form.currency")}
							error={fieldError(errors.currency?.message)}
							required
						>
							<Select {...register("currency")}>
								{currencies.map((code) => (
									<option key={code} value={code}>
										{code}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="link-amount"
							label={t("gateways.links.form.amount", { currency: chosen })}
							error={fieldError(errors.amount?.message)}
							required
						>
							<Input inputMode="decimal" dir="ltr" {...register("amount")} />
						</Field>
						<Field
							id="link-title"
							label={t("gateways.links.form.title")}
							error={fieldError(errors.title?.message)}
							required
						>
							<Input {...register("title")} />
						</Field>
					</div>
					<Field
						id="link-description"
						label={t("gateways.links.form.description")}
						error={fieldError(errors.description?.message)}
					>
						<Textarea rows={3} {...register("description")} />
					</Field>
					{kind === "payment" ? (
						<label className="flex items-center gap-2 text-sm">
							<input type="checkbox" {...register("add_fee")} />
							{t("gateways.links.form.fee")}
						</label>
					) : null}
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
							{t("gateways.links.create")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

(The dialog trigger and its submit button share the name "Create link"; the tests click the trigger first,
then the submit inside the open dialog, where the trigger is hidden from the accessibility tree.)

- [ ] **Step 5: The page**

`dashboard/src/features/gateways/PaymentLinksPage.tsx`:

```tsx
import { Link2 } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { Pager } from "@/components/Pager";
import { Money } from "@/features/billing";
import {
	DateFilter,
	pageCount,
	SearchBox,
	useListParams,
} from "@/features/finance/shared";
import { useCan } from "@/features/identity/permissions";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	EmptyState,
	Select,
	Spinner,
	StatusChip,
	toast,
} from "@/ui";
import { gatewaysErrorText } from "./errors";
import { LinkDialog } from "./LinkDialog";
import { useLinks } from "./linkQueries";
import { LINK_KINDS, LINK_STATUSES, type PaymentLinkRow } from "./linkSchemas";
import { linksApi } from "./linksApi";
import { useGatewaysMutation } from "./queries";
import { PROVIDERS, type Provider } from "./schemas";

const NAMES: Record<Provider, string> = { stripe: "Stripe", paypal: "PayPal" };
const COLUMNS = [
	"date",
	"title",
	"payer",
	"kind",
	"provider",
	"amount",
	"fee",
	"status",
] as const;

function CancelButton({ row }: { row: PaymentLinkRow }) {
	const { t } = useTranslation();
	const cancel = useGatewaysMutation(linksApi.cancel);
	return (
		<Confirm
			action={t("gateways.links.cancel")}
			title={t("gateways.links.cancelTitle")}
			body={t("gateways.links.cancelBody")}
			onConfirm={() =>
				cancel.mutate(row.id, {
					onSuccess: () =>
						toast({
							description: t("gateways.links.cancelled"),
							variant: "success",
						}),
					onError: (error) =>
						toast({
							description: gatewaysErrorText(error, t),
							variant: "destructive",
						}),
				})
			}
		/>
	);
}

/** B3g §6, Billing → Payment links: the list with its filters and copy-link,
 * a create dialog, and Cancel for an open link. */
export function PaymentLinksPage() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const { params, page, update, goTo } = useListParams();
	const { data, isPending, isError } = useLinks(params);

	async function copy(url: string) {
		try {
			await navigator.clipboard.writeText(url);
			toast({ description: t("gateways.links.copied"), variant: "success" });
		} catch {
			toast({ description: url });
		}
	}

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				<SearchBox
					id="links-search"
					label={t("gateways.links.filters.search")}
					value={String(params.q ?? "")}
					onChange={(value) => update({ q: value || undefined })}
				/>
				<div className="flex flex-col gap-1.5">
					<label htmlFor="links-status" className="text-sm font-medium">
						{t("gateways.links.filters.status")}
					</label>
					<Select
						id="links-status"
						value={String(params.status ?? "")}
						onChange={(e) => update({ status: e.target.value || undefined })}
					>
						<option value="">{t("gateways.links.all")}</option>
						{LINK_STATUSES.map((s) => (
							<option key={s} value={s}>
								{t(`gateways.links.status.${s}`)}
							</option>
						))}
					</Select>
				</div>
				<div className="flex flex-col gap-1.5">
					<label htmlFor="links-kind" className="text-sm font-medium">
						{t("gateways.links.filters.kind")}
					</label>
					<Select
						id="links-kind"
						value={String(params.kind ?? "")}
						onChange={(e) => update({ kind: e.target.value || undefined })}
					>
						<option value="">{t("gateways.links.all")}</option>
						{LINK_KINDS.map((k) => (
							<option key={k} value={k}>
								{t(`gateways.links.kinds.${k}`)}
							</option>
						))}
					</Select>
				</div>
				<div className="flex flex-col gap-1.5">
					<label htmlFor="links-provider" className="text-sm font-medium">
						{t("gateways.links.filters.provider")}
					</label>
					<Select
						id="links-provider"
						value={String(params.provider ?? "")}
						onChange={(e) => update({ provider: e.target.value || undefined })}
					>
						<option value="">{t("gateways.links.all")}</option>
						{PROVIDERS.map((p) => (
							<option key={p} value={p}>
								{NAMES[p]}
							</option>
						))}
					</Select>
				</div>
				<DateFilter
					id="links-from"
					label={t("finance.list.from")}
					value={String(params.created_from ?? "")}
					onChange={(value) => update({ created_from: value || undefined })}
				/>
				<DateFilter
					id="links-to"
					label={t("finance.list.to")}
					value={String(params.created_to ?? "")}
					onChange={(value) => update({ created_to: value || undefined })}
				/>
				{can("payment_link.create") ? <LinkDialog /> : null}
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("gateways.links.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<Spinner />
			) : data.results.length === 0 ? (
				<EmptyState icon={Link2} title={t("gateways.links.empty")} />
			) : (
				<div className="overflow-x-auto">
					<table className="w-full text-sm">
						<thead>
							<tr className="border-b border-border">
								{COLUMNS.map((column) => (
									<th key={column} className="px-2 py-2 text-start font-medium">
										{t(`gateways.links.columns.${column}`)}
									</th>
								))}
								<th className="px-2 py-2" />
							</tr>
						</thead>
						<tbody>
							{data.results.map((row) => (
								<tr key={row.id} className="border-b border-border align-top">
									<td className="px-2 py-2">
										{formatDay(row.created_at.slice(0, 10), i18n.language)}
									</td>
									<td className="px-2 py-2">{row.title}</td>
									<td className="px-2 py-2">
										<div className="flex flex-col">
											<span>{row.payer.name}</span>
											{row.payer.email ? (
												<span className="text-muted-foreground" dir="ltr">
													{row.payer.email}
												</span>
											) : null}
										</div>
									</td>
									<td className="px-2 py-2">
										{t(`gateways.links.kinds.${row.kind}`)}
									</td>
									<td className="px-2 py-2">{NAMES[row.provider]}</td>
									<td className="px-2 py-2">
										<Money minor={row.amount_minor} currency={row.currency} />
									</td>
									<td className="px-2 py-2">
										<Money minor={row.fee_minor} currency={row.currency} />
									</td>
									<td className="px-2 py-2">
										<StatusChip tone={row.status === "paid" ? "live" : "neutral"}>
											{t(`gateways.links.status.${row.status}`)}
										</StatusChip>
									</td>
									<td className="px-2 py-2">
										<div className="flex flex-wrap gap-2">
											<Button
												size="sm"
												variant="outline"
												onClick={() => void copy(row.url)}
											>
												{t("gateways.links.copy")}
											</Button>
											{row.status === "open" && can("payment_link.update") ? (
												<CancelButton row={row} />
											) : null}
										</div>
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			<Pager page={page} pages={pageCount(data?.count)} onChange={goTo} />
		</div>
	);
}
```

`features/gateways/index.ts`: also export `LinkDialog` and `PaymentLinksPage`.

- [ ] **Step 6: The route, the nav, the landing and the strings**

`dashboard/src/routes/_authed/billing.links.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PaymentLinksPage } from "@/features/gateways";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/billing/links")({
	staticData: { permission: "payment_link.view_any", feature: "payment_links" },
	component: function LinksRoute() {
		const { t } = useTranslation();
		usePageTitle(t("gateways.nav.links"));
		return (
			<>
				<PageHeader title={t("gateways.nav.links")} />
				<PaymentLinksPage />
			</>
		);
	},
});
```

`dashboard/src/features/shell/nav.ts`: add `Link2` to the lucide import (keep the list sorted) and, directly
under `// ── phase B3 ──`, before B3a's lines:

```ts
	// B3g: payment links (payment records join in the next task).
	office(
		"/billing/links",
		"gateways.nav.links",
		Link2,
		"billing",
		"payment_link.view_any",
		"payment_links",
	),
```

`nav.test.ts`: in the expected order list add `"/billing/links",` right before `"/billing/expenses"`; in the
"hides the items of every feature the academy has switched off" list add `"/billing/links"`; in the
"names a feature on exactly the items" map add `"/billing/links": "payment_links",`.

`features/finance/landing.ts`: insert after the invoices row
`{ to: "/billing/links", code: "payment_link.view_any", feature: "payment_links" },`. `landing.test.ts`: add

```ts
	it("opens payment links for staff who may see only them", () => {
		expect(
			billingLanding({
				...staffMe("payment_link.view_any"),
				features: ["payment_links"],
			}),
		).toBe("/billing/links");
	});
```

`routes/permissions.test.ts`: `FEATURE_SCREENS` gains `"/_authed/billing/links": "payment_links",` and the
`FEATURE_WORDS` regex gains `|links`.

Strings. `dashboard/src/locales/en/gateways.json`: `nav.links` = `"Payment links"`, and a `links` object:

```json
	"links": {
		"empty": "No payment links yet.",
		"loadError": "The payment links could not be loaded.",
		"create": "Create link",
		"dialogTitle": "New payment link",
		"dialogHelp": "Anyone who opens the link can pay it once, without signing in.",
		"created": "Payment link created.",
		"copy": "Copy link",
		"copied": "Link copied.",
		"cancel": "Cancel link",
		"cancelTitle": "Cancel this link",
		"cancelBody": "Nobody will be able to pay it any more. A payment already on its way is kept for you to review.",
		"cancelled": "Link cancelled.",
		"all": "All",
		"filters": {
			"search": "Search by title or payer",
			"status": "Status",
			"kind": "Type",
			"provider": "Provider"
		},
		"columns": {
			"date": "Created",
			"title": "Title",
			"payer": "Payer",
			"kind": "Type",
			"provider": "Provider",
			"amount": "Amount",
			"fee": "Fee",
			"status": "Status"
		},
		"status": { "open": "Open", "paid": "Paid", "cancelled": "Cancelled" },
		"kinds": { "payment": "Payment", "donation": "Donation" },
		"form": {
			"payerType": "Payer",
			"payerStudent": "A registered student",
			"payerOther": "Someone else",
			"findStudent": "Find a student",
			"student": "Student",
			"payerName": "Payer's name",
			"payerEmail": "Payer's email",
			"payerPhone": "Payer's phone",
			"kind": "Type",
			"provider": "Provider",
			"currency": "Currency",
			"amount": "Amount ({{currency}})",
			"fee": "Add the service fee",
			"title": "Title",
			"description": "Description"
		},
		"errors": {
			"name": "Enter the payer's name.",
			"email": "Enter a valid email address."
		}
	}
```

`dashboard/src/locales/ar/gateways.json`: `nav.links` = `"روابط الدفع"`, and:

```json
	"links": {
		"empty": "لا توجد روابط دفع بعد.",
		"loadError": "تعذّر تحميل روابط الدفع.",
		"create": "إنشاء رابط",
		"dialogTitle": "رابط دفع جديد",
		"dialogHelp": "يمكن لأي شخص يفتح الرابط أن يدفعه مرة واحدة دون تسجيل الدخول.",
		"created": "تم إنشاء رابط الدفع.",
		"copy": "نسخ الرابط",
		"copied": "تم نسخ الرابط.",
		"cancel": "إلغاء الرابط",
		"cancelTitle": "إلغاء هذا الرابط",
		"cancelBody": "لن يتمكن أحد من دفعه بعد الآن. المبلغ الذي في الطريق يُحفظ لتراجعه.",
		"cancelled": "تم إلغاء الرابط.",
		"all": "الكل",
		"filters": {
			"search": "ابحث بالعنوان أو الدافع",
			"status": "الحالة",
			"kind": "النوع",
			"provider": "بوابة الدفع"
		},
		"columns": {
			"date": "تاريخ الإنشاء",
			"title": "العنوان",
			"payer": "الدافع",
			"kind": "النوع",
			"provider": "البوابة",
			"amount": "المبلغ",
			"fee": "الرسوم",
			"status": "الحالة"
		},
		"status": { "open": "مفتوح", "paid": "مدفوع", "cancelled": "ملغى" },
		"kinds": { "payment": "دفعة", "donation": "تبرع" },
		"form": {
			"payerType": "الدافع",
			"payerStudent": "طالب مسجّل",
			"payerOther": "شخص آخر",
			"findStudent": "ابحث عن طالب",
			"student": "الطالب",
			"payerName": "اسم الدافع",
			"payerEmail": "البريد الإلكتروني للدافع",
			"payerPhone": "هاتف الدافع",
			"kind": "النوع",
			"provider": "بوابة الدفع",
			"currency": "العملة",
			"amount": "المبلغ ({{currency}})",
			"fee": "إضافة رسوم الخدمة",
			"title": "العنوان",
			"description": "الوصف"
		},
		"errors": {
			"name": "أدخل اسم الدافع.",
			"email": "أدخل بريدًا إلكترونيًا صحيحًا."
		}
	}
```

- [ ] **Step 7: Run the tests, format and commit**

```bash
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm exec vite build
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm exec biome check --write src e2e
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm vitest run src/features/gateways src/features/shell src/features/finance src/routes src/locales
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm tsc --noEmit
```

Expected: all pass (a locales test compares en and ar keys and that no ar value equals its en value except
brand words); `grep -c "not wrapped in act"` over the new files prints 0.

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(gateways): Billing payment links page with create, copy and cancel"
```

---
### Task 10: Dashboard — Billing → Payment records, the checkouts CSV button and the Payment terms card

**Files:**
- Modify: `dashboard/src/features/billing/schemas.ts` (the `Payment` shape, record bodies, the form schema), `api.ts`, `queries.ts`, `index.ts`, `InvoicePage.tsx`
- Create: `dashboard/src/features/billing/RecordDialog.tsx`, `PaymentRecordsPage.tsx`, `SubscriptionTermsCard.tsx`
- Modify: `dashboard/src/features/gateways/api.ts`, `CheckoutsList.tsx`
- Create: `dashboard/src/routes/_authed/billing.payments.tsx`
- Modify: `dashboard/src/features/shell/nav.ts`, `nav.test.ts`, `finance/landing.ts`, `landing.test.ts`, `routes/permissions.test.ts`
- Modify: `dashboard/src/locales/{en,ar}/billing.json`, `dashboard/src/test/billing-fixtures.ts`
- Test: `dashboard/src/features/billing/recordSchemas.test.ts`, `RecordDialog.test.tsx`, `PaymentRecordsPage.test.tsx`, `SubscriptionTermsCard.test.tsx`; additions to `InvoicePage.test.tsx` and `features/gateways/CheckoutsList.test.tsx`

**Interfaces:**
- Consumes: Task 2's `billing/payments/` routes and the payment row; Task 3's `billing/subscriptions/<id>/terms/`; Task 7's checkouts CSV; `ExportButton`, `csvUrl`, `Confirm`, `Pager`, `useListParams`, `pageCount`, `DateFilter`, `SearchBox`, `usePeople`, `useAcademySettings`, `todayIn`, `useCan`, `useHasFeature`.
- Produces:
  - `Payment` becomes `{id, customer: {type, name, student_id, email, phone}, invoice: {id, number} | null, transaction_number, reference, method, amount_minor, fee_minor, currency, status, paid_on, refunded_at, created_at, editable, deletable, notes?, recorded_by?}` (no `invoice_id`)
  - `RecordBody`, `RecordPatch`, `recordFormSchema`, `RecordFormValues`, `toRecordBody(values, { edit })`
  - `billingApi.records(params)`, `createRecord(body)`, `updateRecord({ id, ...patch })`, `refundRecord(id)`, `terms(id)`, `setTerms({ id, ...patch })`; `recordsCsvUrl(params)`; `useRecords(params)`, `useSubscriptionTerms(id, enabled)`
  - `<PaymentRecordsPage />`, `<RecordDialog record? />`, `<SubscriptionTermsCard subscriptionId={number} />` (exported from `features/billing`)
  - `checkoutsCsvUrl(params)` in `features/gateways/api.ts`
  - route `/_authed/billing/payments` (`payment.view_any`, feature `payment_receipts`); nav item and landing entry before payment links

- [ ] **Step 1: Write the failing tests**

Update `dashboard/src/test/billing-fixtures.ts`: replace `paymentRow` and add `recordRow`:

```ts
export function paymentRow(overrides: Partial<Payment> = {}): Payment {
	return {
		id: 61,
		customer: {
			type: "student",
			name: "Yusuf",
			student_id: 11,
			email: "",
			phone: "",
		},
		invoice: { id: 51, number: "INV-000051" },
		transaction_number: "",
		reference: "IP-9",
		method: "instapay",
		amount_minor: 50000,
		fee_minor: 0,
		currency: "EGP",
		status: "completed",
		paid_on: "2026-06-02",
		refunded_at: null,
		created_at: "2026-06-02T09:00:00Z",
		editable: false,
		deletable: true,
		notes: "First half",
		recorded_by: { id: 1, full_name: "Amina" },
		...overrides,
	};
}

/** A standalone record: no invoice, an unregistered customer, by hand. */
export function recordRow(overrides: Partial<Payment> = {}): Payment {
	return paymentRow({
		id: 62,
		customer: {
			type: "unregistered",
			name: "Abu Khalid",
			student_id: null,
			email: "a@b.test",
			phone: "+201001234567",
		},
		invoice: null,
		method: "cash",
		reference: "",
		transaction_number: "T-1",
		amount_minor: 40000,
		editable: true,
		notes: "Walk-in",
		...overrides,
	});
}
```

(`familyInvoice` destructures `notes` and `recorded_by` from `paymentRow()`; it keeps working.)

`dashboard/src/features/billing/recordSchemas.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
	type RecordFormValues,
	recordFormSchema,
	toRecordBody,
} from "./schemas";

const base: RecordFormValues = {
	customer_type: "unregistered",
	student: "",
	customer_name: "Abu Khalid",
	customer_email: "",
	customer_phone: "",
	amount: "400.00",
	currency: "EGP",
	method: "cash",
	transaction_number: "",
	reference: "",
	paid_on: "2026-06-01",
	notes: "",
};

function problems(values: Partial<RecordFormValues>) {
	const result = recordFormSchema.safeParse({ ...base, ...values });
	return result.success
		? {}
		: Object.fromEntries(result.error.issues.map((i) => [String(i.path[0]), i.message]));
}

describe("recordFormSchema", () => {
	it("accepts a complete record", () => {
		expect(problems({})).toEqual({});
	});

	it("needs a student for a student record and a name for an unregistered one", () => {
		expect(problems({ customer_type: "student" })).toEqual({
			student: "billing.errors.required",
		});
		expect(problems({ customer_name: " " })).toEqual({
			customer_name: "billing.records.errors.name",
		});
	});

	it("checks the amount for the currency, the date and the email", () => {
		expect(problems({ amount: "0" }).amount).toBe("billing.errors.amountInvalid");
		expect(problems({ amount: "4.005" }).amount).toBe("billing.errors.amountInvalid");
		expect(problems({ paid_on: "" }).paid_on).toBe("billing.errors.dateRequired");
		expect(problems({ customer_email: "x" })).toEqual({
			customer_email: "billing.records.errors.email",
		});
	});
});

describe("toRecordBody", () => {
	it("leaves blanks out when creating", () => {
		expect(toRecordBody(base, { edit: false })).toEqual({
			customer_type: "unregistered",
			customer_name: "Abu Khalid",
			amount_minor: 40000,
			currency: "EGP",
			method: "cash",
			paid_on: "2026-06-01",
		});
	});

	it("sends blanks when editing, so a field can be cleared", () => {
		const body = toRecordBody(base, { edit: true });
		expect(body).toMatchObject({
			customer_email: "",
			customer_phone: "",
			transaction_number: "",
			reference: "",
			notes: "",
		});
	});

	it("names a student by user id and sends no typed name", () => {
		const body = toRecordBody(
			{ ...base, customer_type: "student", student: "11", customer_name: "x" },
			{ edit: false },
		);
		expect(body.student).toBe(11);
		expect(body).not.toHaveProperty("customer_name");
	});
});
```

`dashboard/src/features/billing/RecordDialog.test.tsx`:

```tsx
import { act, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { peopleApi } from "@/features/people/api";
import i18n from "@/lib/i18n";
import { recordRow } from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { billingApi } from "./api";
import { RecordDialog } from "./RecordDialog";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		billingApi: { ...actual.billingApi, createRecord: vi.fn(), updateRecord: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});

async function open(trigger: string, record?: ReturnType<typeof recordRow>) {
	const user = userEvent.setup();
	renderWithRouter(<RecordDialog record={record} />);
	await user.click(await screen.findByRole("button", { name: trigger }));
	await screen.findByRole("dialog");
	// The academy's today and currency re-seed the form once loaded.
	await waitFor(() => expect(screen.getByLabelText(/^Paid on/)).toHaveValue("2026-06-01"));
	await act(async () => {});
	return user;
}

describe("RecordDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.useFakeTimers({ now: new Date("2026-06-01T08:00:00Z"), toFake: ["Date"] });
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ timezone: "UTC", default_currency: "EGP" }),
		);
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 11, user: { full_name: "Yusuf" } }]) as never,
		);
		vi.mocked(billingApi.createRecord).mockResolvedValue(recordRow());
		vi.mocked(billingApi.updateRecord).mockResolvedValue(recordRow());
	});
	afterEach(async () => {
		vi.useRealTimers();
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("adds a record for an unregistered customer, dated today in the academy's currency", async () => {
		const user = await open("Add payment record");
		await user.type(screen.getByLabelText(/^Customer's name/), "Abu Khalid");
		await user.type(screen.getByLabelText(/^Amount/), "400");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(billingApi.createRecord).toHaveBeenCalledWith({
				customer_type: "unregistered",
				customer_name: "Abu Khalid",
				amount_minor: 40000,
				currency: "EGP",
				method: "cash",
				paid_on: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/),
			}),
		);
	});

	it("edits a record without a customer type to change, and sends blanks", async () => {
		const user = userEvent.setup();
		renderWithRouter(<RecordDialog record={recordRow()} />);
		await user.click(await screen.findByRole("button", { name: "Edit" }));
		expect(await screen.findByLabelText(/^Customer's name/)).toHaveValue("Abu Khalid");
		expect(screen.queryByLabelText(/^Customer$/)).toBeNull();
		await user.clear(screen.getByLabelText(/^Notes/));
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() => expect(billingApi.updateRecord).toHaveBeenCalled());
		const sent = vi.mocked(billingApi.updateRecord).mock.calls[0][0];
		expect(sent).toMatchObject({ id: 62, notes: "", customer_name: "Abu Khalid" });
		expect(sent).not.toHaveProperty("customer_type");
	});
});
```

(`toFake: ["Date"]` pins only the clock, as `InvoiceForm.test.tsx` does, so `userEvent` and the query
timers stay real.)

`dashboard/src/features/billing/PaymentRecordsPage.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import { peopleApi } from "@/features/people/api";
import i18n from "@/lib/i18n";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { paymentRow, recordRow } from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { billingApi } from "./api";
import { PaymentRecordsPage } from "./PaymentRecordsPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		billingApi: {
			...actual.billingApi,
			records: vi.fn(),
			createRecord: vi.fn(),
			updateRecord: vi.fn(),
			refundRecord: vi.fn(),
			deletePayment: vi.fn(),
		},
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});

const lastParams = () => vi.mocked(billingApi.records).mock.calls.at(-1)?.[0];
const DETAIL = "/billing/invoices/$invoiceId";

describe("PaymentRecordsPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(peopleApi.list).mockResolvedValue(page([]) as never);
		vi.mocked(billingApi.records).mockResolvedValue(
			page([paymentRow(), recordRow()]),
		);
		vi.mocked(billingApi.refundRecord).mockResolvedValue(
			recordRow({ status: "refunded" }),
		);
		vi.mocked(billingApi.deletePayment).mockResolvedValue(undefined);
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("lists every payment with its customer, invoice, method and amount", async () => {
		renderWithRouter(<PaymentRecordsPage />, { extraPaths: [DETAIL] });
		const table = await screen.findByRole("table");
		expect(within(table).getByText("Yusuf")).toBeVisible();
		expect(within(table).getByText("Abu Khalid")).toBeVisible();
		expect(within(table).getByRole("link", { name: "INV-000051" })).toBeVisible();
		expect(within(table).getByText("Cash")).toBeVisible();
		expect(within(table).getByText("EGP 400.00")).toBeVisible();
	});

	it("passes its filters to the server and resets to page 1", async () => {
		const user = userEvent.setup();
		renderWithRouter(<PaymentRecordsPage />, { extraPaths: [DETAIL] });
		await screen.findByRole("table");
		await user.selectOptions(screen.getByLabelText("Method"), "cash");
		await user.selectOptions(screen.getByLabelText("Customer"), "unregistered");
		await user.selectOptions(screen.getByLabelText("Invoice"), "false");
		await user.type(screen.getByRole("searchbox"), "Abu");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({
				method: "cash",
				customer_type: "unregistered",
				has_invoice: "false",
				q: "Abu",
				page: 1,
			}),
		);
	});

	it("offers the CSV export with the same filters while export is on", async () => {
		renderWithRouter(
			<CanProvider me={adminWith("payment_receipts", "export")}>
				<PaymentRecordsPage />
			</CanProvider>,
			{ extraPaths: [DETAIL] },
		);
		const link = await screen.findByRole("link", { name: "Export CSV" });
		expect(link.getAttribute("href")).toContain("billing/payments/?format=csv");
	});

	it("shows Edit only on an editable record, and refund and delete as the row allows", async () => {
		renderWithRouter(<PaymentRecordsPage />, { extraPaths: [DETAIL] });
		await screen.findByRole("table");
		expect(screen.getAllByRole("button", { name: "Edit" })).toHaveLength(1);
		expect(screen.getAllByRole("button", { name: "Mark refunded" })).toHaveLength(2);
	});

	it("marks a record refunded and deletes one after confirming", async () => {
		const user = userEvent.setup();
		renderWithRouter(<PaymentRecordsPage />, { extraPaths: [DETAIL] });
		await screen.findByRole("table");
		await user.click(screen.getAllByRole("button", { name: "Mark refunded" })[1]);
		await user.click(
			within(await screen.findByRole("alertdialog")).getByRole("button", {
				name: "Mark this payment refunded",
			}),
		);
		await waitFor(() => expect(billingApi.refundRecord).toHaveBeenCalledWith(62));
		await user.click(screen.getAllByRole("button", { name: "Delete" })[1]);
		await user.click(
			within(await screen.findByRole("alertdialog")).getByRole("button", {
				name: "Delete payment record",
			}),
		);
		await waitFor(() => expect(billingApi.deletePayment).toHaveBeenCalledWith(62));
	});

	it("hides what a staff account may not do", async () => {
		renderWithRouter(
			<CanProvider
				me={{ ...staffMe("payment.view_any"), features: ["payment_receipts"] }}
			>
				<PaymentRecordsPage />
			</CanProvider>,
			{ extraPaths: [DETAIL] },
		);
		await screen.findByRole("table");
		for (const name of ["Add payment record", "Edit", "Mark refunded", "Delete"]) {
			expect(screen.queryByRole("button", { name })).toBeNull();
		}
	});

	it("says when there are none or the list failed", async () => {
		vi.mocked(billingApi.records).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<PaymentRecordsPage />);
		expect(await screen.findByText("No payment records yet.")).toBeVisible();
		unmount();
		vi.mocked(billingApi.records).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<PaymentRecordsPage />);
		expect(
			await screen.findByText("The payment records could not be loaded."),
		).toBeVisible();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderWithRouter(<PaymentRecordsPage />, { extraPaths: [DETAIL] });
		expect(await screen.findByText("Abu Khalid")).toBeVisible();
		expect(screen.getAllByRole("button", { name: "تعديل" })).toHaveLength(1);
	});
});
```

`dashboard/src/features/billing/SubscriptionTermsCard.test.tsx`:

```tsx
import { act, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { billingApi } from "./api";
import { SubscriptionTermsCard } from "./SubscriptionTermsCard";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		billingApi: { ...actual.billingApi, terms: vi.fn(), setTerms: vi.fn() },
	};
});

describe("SubscriptionTermsCard", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(billingApi.terms).mockResolvedValue({
			payment_type: "prepaid",
			system: "normal",
		});
		vi.mocked(billingApi.setTerms).mockResolvedValue({
			payment_type: "postpaid",
			system: "normal",
		});
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("shows the terms and saves a change", async () => {
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionTermsCard subscriptionId={7} />);
		const type = await screen.findByLabelText("Payment type");
		expect(type).toHaveValue("prepaid");
		expect(screen.getByRole("button", { name: "Save" })).toBeDisabled();
		await user.selectOptions(type, "postpaid");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(billingApi.setTerms).toHaveBeenCalledWith({
				id: 7,
				payment_type: "postpaid",
				system: "normal",
			}),
		);
	});

	it("is read-only for staff who may only view, and absent without the view code", async () => {
		const { unmount } = renderWithRouter(
			<CanProvider me={staffMe("subscription.view")}>
				<SubscriptionTermsCard subscriptionId={7} />
			</CanProvider>,
		);
		expect(await screen.findByLabelText("Payment type")).toBeDisabled();
		expect(screen.queryByRole("button", { name: "Save" })).toBeNull();
		unmount();
		vi.clearAllMocks();
		renderWithRouter(
			<CanProvider me={staffMe("invoice.view_any")}>
				<SubscriptionTermsCard subscriptionId={7} />
			</CanProvider>,
		);
		expect(screen.queryByText("Payment terms")).toBeNull();
		expect(billingApi.terms).not.toHaveBeenCalled();
	});

	it("shows nothing when the subscription is gone", async () => {
		vi.mocked(billingApi.terms).mockRejectedValue(new Error("404"));
		renderWithRouter(
			<CanProvider me={adminWith()}>
				<SubscriptionTermsCard subscriptionId={9} />
			</CanProvider>,
		);
		await waitFor(() => expect(billingApi.terms).toHaveBeenCalledWith(9));
		expect(screen.queryByText("Payment terms")).toBeNull();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderWithRouter(<SubscriptionTermsCard subscriptionId={7} />);
		expect(await screen.findByLabelText("نوع الدفع")).toHaveValue("prepaid");
	});
});
```

Additions to existing tests:
- `InvoicePage.test.tsx`: add `terms: vi.fn()` to the mocked `billingApi` and
  `vi.mocked(billingApi.terms).mockResolvedValue({ payment_type: "prepaid", system: "normal" });` to
  `beforeEach`; and two cases:

```tsx
	it("shows an office reader the Payment terms card of a subscription invoice", async () => {
		renderPage();
		expect(await screen.findByText("Payment terms")).toBeVisible();
		expect(billingApi.terms).toHaveBeenCalledWith(7);
	});

	it("never shows the card on a family's page", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(familyInvoice());
		renderPage(false);
		await screen.findByText("INV-000051");
		expect(screen.queryByText("Payment terms")).toBeNull();
		expect(billingApi.terms).not.toHaveBeenCalled();
	});
```

- `features/gateways/CheckoutsList.test.tsx`: add

```tsx
	it("offers the CSV only while payment receipts and export are both on", async () => {
		const { unmount } = renderWithRouter(
			<CanProvider me={adminWith("online_payments", "payment_receipts", "export")}>
				<CheckoutsList />
			</CanProvider>,
		);
		const link = await screen.findByRole("link", { name: "Export CSV" });
		expect(link.getAttribute("href")).toContain("gateways/checkouts/?format=csv");
		unmount();
		renderWithRouter(
			<CanProvider me={adminWith("online_payments", "export")}>
				<CheckoutsList />
			</CanProvider>,
		);
		await screen.findByRole("table");
		expect(screen.queryByRole("link", { name: "Export CSV" })).toBeNull();
	});
```

(import `CanProvider` and `adminWith` there if the file does not already.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm vitest run src/features/billing/recordSchemas.test.ts`
Expected: FAIL (`recordFormSchema` is not exported).

- [ ] **Step 3: Types, form schema, API and hooks**

`dashboard/src/features/billing/schemas.ts`: replace the `Payment` interface and add the record types:

```ts
export interface PaymentCustomer {
	type: "student" | "unregistered";
	name: string;
	/** The student's user id; null for an unregistered customer. */
	student_id: number | null;
	email: string;
	phone: string;
}

/** B3g §4.1: one payment row, whether or not it belongs to an invoice. */
export interface Payment {
	id: number;
	customer: PaymentCustomer;
	invoice: { id: number; number: string } | null;
	transaction_number: string;
	reference: string;
	method: PaymentMethod | OnlineMethod;
	amount_minor: number;
	fee_minor: number;
	currency: string;
	status: "completed" | "refunded";
	paid_on: string;
	refunded_at: string | null;
	created_at: string;
	/** A manual method and no invoice (G-2). */
	editable: boolean;
	/** A manual method (G-2). */
	deletable: boolean;
	// Admins and staff only (spec §4.6).
	notes?: string;
	recorded_by?: Person | null;
}

/** The create body for a standalone record (§4.1). `student` is a user id. */
export interface RecordBody {
	customer_type: "student" | "unregistered";
	student?: number;
	customer_name?: string;
	customer_email?: string;
	customer_phone?: string;
	amount_minor: number;
	currency?: string;
	method: PaymentMethod;
	transaction_number?: string;
	reference?: string;
	paid_on?: string;
	notes?: string;
}
export type RecordPatch = Partial<Omit<RecordBody, "customer_type">>;

export interface Terms {
	payment_type: "prepaid" | "postpaid";
	system: "normal" | "monthly";
}
```

and, after `paymentFormSchema`'s block (it uses `pick`, `day`, `looseAmount` defined above it), append:

```ts
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/** B3g's add and edit dialog for a standalone record. */
export const recordFormSchema = z
	.object({
		customer_type: z.enum(["student", "unregistered"]),
		student: z.string(),
		customer_name: z.string().max(120),
		customer_email: z.string().max(254),
		customer_phone: z.string().max(30),
		amount: looseAmount,
		currency: z.string().regex(/^[A-Z]{3}$/, "billing.errors.required"),
		method: z.enum(PAYMENT_METHODS),
		transaction_number: z.string().max(120),
		reference: z.string().max(120),
		paid_on: day,
		notes: z.string(),
	})
	.superRefine((data, ctx) => {
		const refuse = (path: string, message: string) =>
			ctx.addIssue({ code: "custom", path: [path], message });
		if (data.customer_type === "student" && !data.student) {
			refuse("student", "billing.errors.required");
		}
		if (data.customer_type === "unregistered" && !data.customer_name.trim()) {
			refuse("customer_name", "billing.records.errors.name");
		}
		const email = data.customer_email.trim();
		if (email && !EMAIL.test(email)) {
			refuse("customer_email", "billing.records.errors.email");
		}
		if (/^[A-Z]{3}$/.test(data.currency)) {
			const digits = minorDigits(data.currency);
			const [, fraction = ""] = data.amount.trim().split(".");
			if (fraction.length > digits) refuse("amount", "billing.errors.amountInvalid");
		}
	});
export type RecordFormValues = z.infer<typeof recordFormSchema>;

/** The request body. Creating leaves blanks out; editing sends them, so a
 * field can be cleared (PATCH takes any subset). */
export function toRecordBody(
	values: RecordFormValues,
	{ edit }: { edit: boolean },
): RecordBody {
	const body: RecordBody = {
		customer_type: values.customer_type,
		amount_minor: toMinor(values.amount.trim(), values.currency),
		currency: values.currency,
		method: values.method,
		paid_on: values.paid_on,
	};
	if (values.customer_type === "student") {
		body.student = Number(values.student);
	} else {
		body.customer_name = values.customer_name.trim();
	}
	const optional = {
		customer_email: values.customer_email.trim(),
		customer_phone: values.customer_phone.trim(),
		transaction_number: values.transaction_number.trim(),
		reference: values.reference.trim(),
		notes: values.notes.trim(),
	};
	for (const [key, value] of Object.entries(optional)) {
		if (edit || value) (body as unknown as Record<string, string>)[key] = value;
	}
	return body;
}
```

(import `toMinor` next to `minorDigits` from `@/lib/money`.) Run `grep -rn "invoice_id" src` and fix any
remaining read of the old field (the old `Payment.invoice_id` had no consumer besides the fixture).

`dashboard/src/features/billing/api.ts`: import `Payment`, `RecordBody`, `RecordPatch`, `Terms`; add to
`billingApi`:

```ts
	records: async (params: QueryParams) =>
		(
			await api.get<Paginated<Payment>>("billing/payments/", {
				params: clean(params),
			})
		).data,
	createRecord: async (body: RecordBody) =>
		(await api.post<Payment>("billing/payments/", body)).data,
	updateRecord: async ({ id, ...body }: RecordPatch & { id: number }) =>
		(await api.patch<Payment>(`billing/payments/${id}/`, body)).data,
	/** A standalone record's refund answers the payment row (G-3). */
	refundRecord: async (paymentId: number) =>
		(await api.post<Payment>(`billing/payments/${paymentId}/refund/`)).data,
	terms: async (subscriptionId: number) =>
		(await api.get<Terms>(`billing/subscriptions/${subscriptionId}/terms/`)).data,
	setTerms: async ({ id, ...body }: Partial<Terms> & { id: number }) =>
		(await api.patch<Terms>(`billing/subscriptions/${id}/terms/`, body)).data,
```

and below it:

```ts
/** The payment records' CSV export, with the list's filters (§4.1). */
export function recordsCsvUrl(params: QueryParams): string {
	return csvUrl("billing/payments/", params);
}
```

`queries.ts`, append:

```ts
export function useRecords(params: QueryParams) {
	return useQuery({
		queryKey: [...billingKey, "records", params],
		queryFn: () => billingApi.records(params),
		placeholderData: keepPreviousData,
	});
}

/** SUB-006: a subscription's payment terms; no request without the view code. */
export function useSubscriptionTerms(id: number, enabled: boolean) {
	return useQuery({
		queryKey: [...billingKey, "terms", id],
		queryFn: () => billingApi.terms(id),
		enabled,
		retry: false,
	});
}
```

`index.ts`: add exports `PaymentRecordsPage`, `RecordDialog`, `SubscriptionTermsCard` and `recordsCsvUrl`
(extend the first line: `export { billingApi, invoicesCsvUrl, recordsCsvUrl } from "./api";`).

`dashboard/src/features/gateways/api.ts`: add `csvUrl` to the `@/lib/api` import and

```ts
/** The checkouts list's CSV export (B3g §4.4), with the list's filters. */
export function checkoutsCsvUrl(params: QueryParams): string {
	return csvUrl(`${G}checkouts/`, params);
}
```

- [ ] **Step 4: The dialog and the page**

`dashboard/src/features/billing/RecordDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { usePeople } from "@/features/people";
import { CURRENCIES } from "@/lib/currencies";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { toMajor } from "@/lib/money";
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
import { billingApi } from "./api";
import { useBillingMutation } from "./queries";
import {
	PAYMENT_METHODS,
	type Payment,
	type RecordFormValues,
	recordFormSchema,
	toRecordBody,
} from "./schemas";

/** B3g §6: adds a standalone payment record, or (with ``record``) edits one.
 * The customer's kind is fixed when it is created, so editing shows no kind. */
export function RecordDialog({ record }: { record?: Payment }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const [query, setQuery] = useState("");
	const { data: academy } = useAcademySettings();
	const { data: students } = usePeople("students", {
		is_active: "true",
		page_size: 100,
		q: query.trim(),
	});
	const create = useBillingMutation(billingApi.createRecord);
	const update = useBillingMutation(billingApi.updateRecord);
	const edit = record !== undefined;
	const currency = record?.currency ?? academy?.default_currency ?? "";
	const {
		register,
		handleSubmit,
		setError,
		reset,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<RecordFormValues>({
		resolver: zodResolver(recordFormSchema),
		values: {
			customer_type: record?.customer.type ?? "unregistered",
			student: record?.customer.student_id ? String(record.customer.student_id) : "",
			customer_name: record?.customer.type === "unregistered" ? record.customer.name : "",
			customer_email: record?.customer.email ?? "",
			customer_phone: record?.customer.phone ?? "",
			amount: record ? toMajor(record.amount_minor, record.currency) : "",
			currency,
			method: (record?.method ?? "cash") as RecordFormValues["method"],
			transaction_number: record?.transaction_number ?? "",
			reference: record?.reference ?? "",
			paid_on: record?.paid_on ?? (academy ? todayIn(academy.timezone) : ""),
			notes: record?.notes ?? "",
		},
	});
	const type = watch("customer_type");
	const chosen = watch("currency") || currency;
	const currencies = Array.from(new Set([currency, ...CURRENCIES])).filter(Boolean);
	const known = students?.results.some((p) => p.id === record?.customer.student_id);

	async function onSubmit(values: RecordFormValues) {
		try {
			const body = toRecordBody(values, { edit });
			if (record) {
				const { customer_type: _kind, ...patch } = body;
				await update.mutateAsync({ id: record.id, ...patch });
			} else {
				await create.mutateAsync(body);
			}
			if (!edit) reset();
			setOpen(false);
			toast({ description: t("billing.records.saved"), variant: "success" });
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.amount_minor) {
				setError("amount", { message: parsed.fieldErrors.amount_minor });
			}
			if (parsed.fieldErrors.student && !parsed.fieldErrors.customer_name) {
				setError("student", { message: parsed.fieldErrors.student });
			}
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant={edit ? "outline" : "primary"}>
					{edit ? t("billing.records.edit") : t("billing.records.add")}
				</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>
					{edit ? t("billing.records.editTitle") : t("billing.records.addTitle")}
				</DialogTitle>
				<DialogDescription>{t("billing.records.help")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<div className="grid gap-4 sm:grid-cols-2">
						{edit ? null : (
							<Field id="record-type" label={t("billing.records.form.customerType")}>
								<Select {...register("customer_type")}>
									<option value="unregistered">
										{t("billing.records.customerTypes.unregistered")}
									</option>
									<option value="student">
										{t("billing.records.customerTypes.student")}
									</option>
								</Select>
							</Field>
						)}
						{type === "student" ? (
							<>
								<Field
									id="record-student-search"
									label={t("billing.records.form.findStudent")}
								>
									<Input
										type="search"
										value={query}
										onChange={(e) => setQuery(e.target.value)}
									/>
								</Field>
								<Field
									id="record-student"
									label={t("billing.records.form.student")}
									error={fieldError(errors.student?.message)}
									required
								>
									<Select {...register("student")}>
										<option value="">—</option>
										{record?.customer.student_id && !known ? (
											<option value={record.customer.student_id}>
												{record.customer.name}
											</option>
										) : null}
										{students?.results.map((p) => (
											<option key={p.id} value={p.id}>
												{p.user.full_name}
											</option>
										))}
									</Select>
								</Field>
							</>
						) : (
							<Field
								id="record-name"
								label={t("billing.records.form.name")}
								error={fieldError(errors.customer_name?.message)}
								required
							>
								<Input {...register("customer_name")} />
							</Field>
						)}
						<Field
							id="record-email"
							label={t("billing.records.form.email")}
							error={fieldError(errors.customer_email?.message)}
						>
							<Input type="email" dir="ltr" {...register("customer_email")} />
						</Field>
						<Field
							id="record-phone"
							label={t("billing.records.form.phone")}
							error={fieldError(errors.customer_phone?.message)}
						>
							<Input dir="ltr" {...register("customer_phone")} />
						</Field>
						<Field
							id="record-currency"
							label={t("billing.records.form.currency")}
							error={fieldError(errors.currency?.message)}
							required
						>
							<Select {...register("currency")}>
								{currencies.map((code) => (
									<option key={code} value={code}>
										{code}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="record-amount"
							label={t("billing.records.form.amount", { currency: chosen })}
							error={fieldError(errors.amount?.message)}
							required
						>
							<Input inputMode="decimal" dir="ltr" {...register("amount")} />
						</Field>
						<Field
							id="record-method"
							label={t("billing.records.form.method")}
							error={fieldError(errors.method?.message)}
							required
						>
							<Select {...register("method")}>
								{PAYMENT_METHODS.map((m) => (
									<option key={m} value={m}>
										{t(`billing.methods.${m}`)}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="record-paid_on"
							label={t("billing.records.form.paidOn")}
							error={fieldError(errors.paid_on?.message)}
							required
						>
							<Input type="date" dir="ltr" {...register("paid_on")} />
						</Field>
						<Field
							id="record-transaction"
							label={t("billing.records.form.transaction")}
							error={fieldError(errors.transaction_number?.message)}
						>
							<Input dir="ltr" {...register("transaction_number")} />
						</Field>
						<Field
							id="record-reference"
							label={t("billing.records.form.reference")}
							error={fieldError(errors.reference?.message)}
						>
							<Input dir="ltr" {...register("reference")} />
						</Field>
					</div>
					<Field
						id="record-notes"
						label={t("billing.records.form.notes")}
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
							{t("billing.records.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

(The `fieldError`, `errors` and `register` names match `PaymentDialog.tsx`, which this follows.)

`dashboard/src/features/billing/PaymentRecordsPage.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { ReceiptText } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { ExportButton } from "@/components/ExportButton";
import { Pager } from "@/components/Pager";
import {
	DateFilter,
	pageCount,
	SearchBox,
	useListParams,
} from "@/features/finance/shared";
import { useCan } from "@/features/identity/permissions";
import { CURRENCIES } from "@/lib/currencies";
import { errorText } from "@/lib/form-errors";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	EmptyState,
	Select,
	Spinner,
	StatusChip,
	toast,
} from "@/ui";
import { billingApi, recordsCsvUrl } from "./api";
import { Money } from "./bits";
import { RecordDialog } from "./RecordDialog";
import { useBillingMutation, useRecords } from "./queries";
import { PAYMENT_METHODS, type Payment } from "./schemas";

const COLUMNS = [
	"date",
	"customer",
	"invoice",
	"method",
	"transaction",
	"amount",
	"fee",
	"status",
] as const;

function RowActions({ row }: { row: Payment }) {
	const { t } = useTranslation();
	const can = useCan();
	const refund = useBillingMutation(billingApi.refundRecord);
	const remove = useBillingMutation(billingApi.deletePayment);
	const failed = (error: unknown) =>
		toast({ description: errorText(error, t), variant: "destructive" });
	return (
		<div className="flex flex-wrap gap-2">
			{row.editable && can("payment.update") ? <RecordDialog record={row} /> : null}
			{row.status === "completed" && can("payment.update") ? (
				<Confirm
					action={t("billing.payments.refund")}
					title={t("billing.payments.refundTitle")}
					body={t("billing.payments.refundBody")}
					onConfirm={() =>
						refund.mutate(row.id, {
							onSuccess: () =>
								toast({
									description: t("billing.payments.refundDone"),
									variant: "success",
								}),
							onError: failed,
						})
					}
				/>
			) : null}
			{row.deletable && can("payment.delete") ? (
				<Confirm
					action={t("billing.records.delete")}
					title={t("billing.records.deleteTitle")}
					body={t("billing.records.deleteBody")}
					onConfirm={() =>
						remove.mutate(row.id, {
							onSuccess: () =>
								toast({
									description: t("billing.records.deleted"),
									variant: "success",
								}),
							onError: failed,
						})
					}
				/>
			) : null}
		</div>
	);
}

/** B3g §6, Billing → Payment records: every payment with or without an
 * invoice, with its filters, CSV, add and edit, refund and delete. */
export function PaymentRecordsPage() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const { params, page, update, goTo } = useListParams();
	const { data, isPending, isError } = useRecords(params);
	const select = (
		id: string,
		label: string,
		key: string,
		options: readonly (readonly [string, string])[],
	) => (
		<div className="flex flex-col gap-1.5">
			<label htmlFor={id} className="text-sm font-medium">
				{label}
			</label>
			<Select
				id={id}
				value={String(params[key] ?? "")}
				onChange={(e) => update({ [key]: e.target.value || undefined })}
			>
				<option value="">{t("billing.records.all")}</option>
				{options.map(([value, text]) => (
					<option key={value} value={value}>
						{text}
					</option>
				))}
			</Select>
		</div>
	);
	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				<SearchBox
					id="records-search"
					label={t("billing.records.filters.search")}
					value={String(params.q ?? "")}
					onChange={(value) => update({ q: value || undefined })}
				/>
				{select(
					"records-method",
					t("billing.records.filters.method"),
					"method",
					[
						...PAYMENT_METHODS,
						"stripe",
						"paypal",
					].map((m) => [m, t(`billing.methods.${m}`)] as const),
				)}
				{select(
					"records-customer",
					t("billing.records.filters.customerType"),
					"customer_type",
					(["student", "unregistered"] as const).map(
						(c) => [c, t(`billing.records.customerTypes.${c}`)] as const,
					),
				)}
				{select(
					"records-status",
					t("billing.records.filters.status"),
					"status",
					(["completed", "refunded"] as const).map(
						(s) => [s, t(`billing.records.status.${s}`)] as const,
					),
				)}
				{select(
					"records-currency",
					t("billing.records.filters.currency"),
					"currency",
					CURRENCIES.map((c) => [c, c] as const),
				)}
				{select("records-invoice", t("billing.records.filters.invoice"), "has_invoice", [
					["true", t("billing.records.invoiceFilter.with")],
					["false", t("billing.records.invoiceFilter.without")],
				])}
				<DateFilter
					id="records-from"
					label={t("finance.list.from")}
					value={String(params.paid_from ?? "")}
					onChange={(value) => update({ paid_from: value || undefined })}
				/>
				<DateFilter
					id="records-to"
					label={t("finance.list.to")}
					value={String(params.paid_to ?? "")}
					onChange={(value) => update({ paid_to: value || undefined })}
				/>
				<ExportButton href={recordsCsvUrl(params)} />
				{can("payment.create") ? <RecordDialog /> : null}
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("billing.records.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<Spinner />
			) : data.results.length === 0 ? (
				<EmptyState icon={ReceiptText} title={t("billing.records.empty")} />
			) : (
				<div className="overflow-x-auto">
					<table className="w-full text-sm">
						<thead>
							<tr className="border-b border-border">
								{COLUMNS.map((column) => (
									<th key={column} className="px-2 py-2 text-start font-medium">
										{t(`billing.records.columns.${column}`)}
									</th>
								))}
								<th className="px-2 py-2" />
							</tr>
						</thead>
						<tbody>
							{data.results.map((row) => (
								<tr key={row.id} className="border-b border-border align-top">
									<td className="px-2 py-2">
										{formatDay(row.paid_on, i18n.language)}
									</td>
									<td className="px-2 py-2">
										<div className="flex flex-col">
											<span>{row.customer.name}</span>
											<span className="text-muted-foreground">
												{t(`billing.records.customerTypes.${row.customer.type}`)}
											</span>
										</div>
									</td>
									<td className="px-2 py-2" dir="ltr">
										{row.invoice ? (
											<Link
												to="/billing/invoices/$invoiceId"
												params={{ invoiceId: String(row.invoice.id) }}
												className="text-primary-text underline-offset-4 hover:underline"
											>
												{row.invoice.number}
											</Link>
										) : null}
									</td>
									<td className="px-2 py-2">{t(`billing.methods.${row.method}`)}</td>
									<td className="px-2 py-2" dir="ltr">
										{row.transaction_number}
									</td>
									<td className="px-2 py-2">
										<Money minor={row.amount_minor} currency={row.currency} />
									</td>
									<td className="px-2 py-2">
										<Money minor={row.fee_minor} currency={row.currency} />
									</td>
									<td className="px-2 py-2">
										<StatusChip
											tone={row.status === "completed" ? "live" : "neutral"}
										>
											{t(`billing.records.status.${row.status}`)}
										</StatusChip>
									</td>
									<td className="px-2 py-2">
										<RowActions row={row} />
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			<Pager page={page} pages={pageCount(data?.count)} onChange={goTo} />
		</div>
	);
}
```

(`PaymentRecordsPage` imports `RecordDialog`, which imports `usePeople` from `@/features/people`; billing
already imports it in `InvoiceForm`, so no new cross-feature edge.)

`dashboard/src/features/billing/SubscriptionTermsCard.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";
import { errorText } from "@/lib/form-errors";
import {
	Button,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Field,
	Select,
	Spinner,
	toast,
} from "@/ui";
import { billingApi } from "./api";
import { useBillingMutation, useSubscriptionTerms } from "./queries";
import type { Terms } from "./schemas";

/** SUB-006 (B3g G-18, G-19): how the office notes a subscription is paid.
 * Recorded and shown only; nothing reads it. Office-only: it needs
 * `subscription.view`, and `subscription.update` to change it. */
export function SubscriptionTermsCard({
	subscriptionId,
}: {
	subscriptionId: number;
}) {
	const { t } = useTranslation();
	const can = useCan();
	const canView = can("subscription.view");
	const canUpdate = can("subscription.update");
	const { data, isPending, isError } = useSubscriptionTerms(subscriptionId, canView);
	const save = useBillingMutation(billingApi.setTerms);
	const [draft, setDraft] = useState<Partial<Terms>>({});
	if (!canView || isError) return null;
	if (isPending) return <Spinner />;
	const terms: Terms = { ...data, ...draft };
	const dirty = terms.payment_type !== data.payment_type || terms.system !== data.system;
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("billing.terms.title")}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				<div className="grid gap-4 sm:grid-cols-2">
					<Field id="terms-type" label={t("billing.terms.paymentType")}>
						<Select
							disabled={!canUpdate}
							value={terms.payment_type}
							onChange={(e) =>
								setDraft({ ...draft, payment_type: e.target.value as Terms["payment_type"] })
							}
						>
							<option value="prepaid">{t("billing.terms.prepaid")}</option>
							<option value="postpaid">{t("billing.terms.postpaid")}</option>
						</Select>
					</Field>
					<Field id="terms-system" label={t("billing.terms.system")}>
						<Select
							disabled={!canUpdate}
							value={terms.system}
							onChange={(e) =>
								setDraft({ ...draft, system: e.target.value as Terms["system"] })
							}
						>
							<option value="normal">{t("billing.terms.normal")}</option>
							<option value="monthly">{t("billing.terms.monthly")}</option>
						</Select>
					</Field>
				</div>
				<p className="text-sm text-muted-foreground">{t("billing.terms.note")}</p>
				{canUpdate ? (
					<div>
						<Button
							size="sm"
							disabled={!dirty || save.isPending}
							onClick={() =>
								save.mutate(
									{ id: subscriptionId, ...terms },
									{
										onSuccess: () => {
											setDraft({});
											toast({
												description: t("billing.terms.saved"),
												variant: "success",
											});
										},
										onError: (error) =>
											toast({
												description: errorText(error, t),
												variant: "destructive",
											}),
									},
								)
							}
						>
							{t("billing.terms.save")}
						</Button>
					</div>
				) : null}
			</CardContent>
		</Card>
	);
}
```

`dashboard/src/features/billing/InvoicePage.tsx`: import `SubscriptionTermsCard`; in the component's returned
`<div className="flex flex-col gap-6">`, immediately after the invoice `</Card>` that closes the main card
(before the `Payments` card), add:

```tsx
			{admin && invoice.subscription_id !== null ? (
				<SubscriptionTermsCard subscriptionId={invoice.subscription_id} />
			) : null}
```

`dashboard/src/features/gateways/CheckoutsList.tsx`: import `ExportButton` from `@/components/ExportButton`
and `checkoutsCsvUrl` from `./api`, and in the filter row (the `<div className="flex flex-wrap items-end gap-3">`
after the two `DateFilter`s) add:

```tsx
				{hasFeature("payment_receipts") ? (
					<ExportButton href={checkoutsCsvUrl(params)} />
				) : null}
```

- [ ] **Step 5: The route, the nav, the landing and the strings**

`dashboard/src/routes/_authed/billing.payments.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { PaymentRecordsPage } from "@/features/billing";
import { usePageTitle } from "@/features/branding";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/billing/payments")({
	staticData: { permission: "payment.view_any", feature: "payment_receipts" },
	component: function PaymentRecordsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("billing.records.nav"));
		return (
			<>
				<PageHeader title={t("billing.records.nav")} />
				<PaymentRecordsPage />
			</>
		);
	},
});
```

`features/shell/nav.ts`: add `ReceiptText` to the lucide import and, directly under `// ── phase B3 ──` before
the B3g payment-links item:

```ts
	// B3g: every payment with or without an invoice (billing's payment codes).
	office(
		"/billing/payments",
		"billing.records.nav",
		ReceiptText,
		"billing",
		"payment.view_any",
		"payment_receipts",
	),
```

`nav.test.ts`: in the order list put `"/billing/payments",` before `"/billing/links",`; add it to the
switched-off list; add `"/billing/payments": "payment_receipts",` to the feature map.

`features/finance/landing.ts`: insert, after the invoices row and before the links row,
`{ to: "/billing/payments", code: "payment.view_any", feature: "payment_receipts" },`; `landing.test.ts`:

```ts
	it("orders the billing pages: invoices, payments, links, expenses, donations", () => {
		const staff = staffMe(
			"invoice.view_any",
			"payment.view_any",
			"payment_link.view_any",
			"expense.view_any",
			"donation.view_any",
		);
		const on = (...features: FeatureCode[]) => ({ ...staff, features });
		expect(
			billingLanding(
				on("invoices", "payment_receipts", "payment_links", "expenses", "donations"),
			),
		).toBe("/billing/invoices");
		expect(
			billingLanding(on("payment_receipts", "payment_links", "expenses")),
		).toBe("/billing/payments");
		expect(billingLanding(on("payment_links", "expenses"))).toBe("/billing/links");
	});
```

(import `type { FeatureCode }` from `@/features/identity/schemas` in `landing.test.ts` if it is not there.)

`routes/permissions.test.ts`: `FEATURE_SCREENS` gains `"/_authed/billing/payments": "payment_receipts",` and the
`FEATURE_WORDS` regex gains `|payments`.

Strings: add to `dashboard/src/locales/en/billing.json` (new top-level objects `records` and `terms`):

```json
	"records": {
		"nav": "Payment records",
		"help": "For money received without an invoice.",
		"empty": "No payment records yet.",
		"loadError": "The payment records could not be loaded.",
		"add": "Add payment record",
		"addTitle": "New payment record",
		"edit": "Edit",
		"editTitle": "Edit payment record",
		"save": "Save",
		"saved": "Payment record saved.",
		"delete": "Delete",
		"deleteTitle": "Delete payment record",
		"deleteBody": "Only for a record made by mistake. It cannot be undone.",
		"deleted": "Payment record deleted.",
		"all": "All",
		"filters": {
			"search": "Search by customer, transaction or invoice",
			"method": "Method",
			"customerType": "Customer",
			"status": "Status",
			"currency": "Currency",
			"invoice": "Invoice"
		},
		"invoiceFilter": { "with": "With an invoice", "without": "Without an invoice" },
		"columns": {
			"date": "Date",
			"customer": "Customer",
			"invoice": "Invoice",
			"method": "Method",
			"transaction": "Transaction",
			"amount": "Amount",
			"fee": "Fee",
			"status": "Status"
		},
		"customerTypes": { "student": "Student", "unregistered": "Unregistered" },
		"status": { "completed": "Completed", "refunded": "Refunded" },
		"form": {
			"customerType": "Customer",
			"student": "Student",
			"findStudent": "Find a student",
			"name": "Customer's name",
			"email": "Customer's email",
			"phone": "Customer's phone",
			"currency": "Currency",
			"amount": "Amount ({{currency}})",
			"method": "Method",
			"paidOn": "Paid on",
			"transaction": "Transaction number",
			"reference": "Reference",
			"notes": "Notes"
		},
		"errors": {
			"name": "Enter the customer's name.",
			"email": "Enter a valid email address."
		}
	},
	"terms": {
		"title": "Payment terms",
		"paymentType": "Payment type",
		"system": "System",
		"prepaid": "Prepaid",
		"postpaid": "Postpaid",
		"normal": "Normal",
		"monthly": "Monthly",
		"note": "For the office only. Nothing here changes how the subscription is billed.",
		"save": "Save",
		"saved": "Payment terms saved."
	}
```

and to `dashboard/src/locales/ar/billing.json`:

```json
	"records": {
		"nav": "سجلات المدفوعات",
		"help": "للمبالغ المستلمة دون فاتورة.",
		"empty": "لا توجد سجلات مدفوعات بعد.",
		"loadError": "تعذّر تحميل سجلات المدفوعات.",
		"add": "إضافة سجل دفع",
		"addTitle": "سجل دفع جديد",
		"edit": "تعديل",
		"editTitle": "تعديل سجل الدفع",
		"save": "حفظ",
		"saved": "تم حفظ سجل الدفع.",
		"delete": "حذف",
		"deleteTitle": "حذف سجل الدفع",
		"deleteBody": "فقط للسجل الذي أُنشئ بالخطأ. لا يمكن التراجع عن ذلك.",
		"deleted": "تم حذف سجل الدفع.",
		"all": "الكل",
		"filters": {
			"search": "ابحث بالعميل أو رقم العملية أو الفاتورة",
			"method": "طريقة الدفع",
			"customerType": "العميل",
			"status": "الحالة",
			"currency": "العملة",
			"invoice": "الفاتورة"
		},
		"invoiceFilter": { "with": "مع فاتورة", "without": "بدون فاتورة" },
		"columns": {
			"date": "التاريخ",
			"customer": "العميل",
			"invoice": "الفاتورة",
			"method": "طريقة الدفع",
			"transaction": "رقم العملية",
			"amount": "المبلغ",
			"fee": "الرسوم",
			"status": "الحالة"
		},
		"customerTypes": { "student": "طالب", "unregistered": "غير مسجّل" },
		"status": { "completed": "مكتمل", "refunded": "مسترد" },
		"form": {
			"customerType": "العميل",
			"student": "الطالب",
			"findStudent": "ابحث عن طالب",
			"name": "اسم العميل",
			"email": "البريد الإلكتروني للعميل",
			"phone": "هاتف العميل",
			"currency": "العملة",
			"amount": "المبلغ ({{currency}})",
			"method": "طريقة الدفع",
			"paidOn": "تاريخ الدفع",
			"transaction": "رقم العملية",
			"reference": "المرجع",
			"notes": "ملاحظات"
		},
		"errors": {
			"name": "أدخل اسم العميل.",
			"email": "أدخل بريدًا إلكترونيًا صحيحًا."
		}
	},
	"terms": {
		"title": "شروط الدفع",
		"paymentType": "نوع الدفع",
		"system": "النظام",
		"prepaid": "مدفوع مسبقًا",
		"postpaid": "مدفوع لاحقًا",
		"normal": "عادي",
		"monthly": "شهري",
		"note": "للمكتب فقط. لا يغيّر شيء هنا طريقة فوترة الاشتراك.",
		"save": "حفظ",
		"saved": "تم حفظ شروط الدفع."
	}
```

- [ ] **Step 6: Run the tests, format and commit**

```bash
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm exec vite build
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm exec biome check --write src e2e
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm vitest run src/features src/routes src/locales
HOST_UID=$(id -u) HOST_GID=$(id -g) $DASH dashboard pnpm tsc --noEmit
```

Expected: all pass. Existing tests that read the old payment shape (`invoice_id`, an `InvoicePage` test
asserting every call) are the ones the failures name; fix them to the new shape.

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(billing): payment records page, checkouts CSV button and the payment terms card"
```

---
### Task 11: The journey through Caddy, the gates and the amendments

**Files:**
- Create: `dashboard/e2e/b3-payment-links.spec.ts`
- Modify (only if a gate shows it): any file a failing gate names

**Interfaces:**
- Consumes: everything above; `e2e/fixtures.ts` (`DEMO_ADMIN`, `DEMO_URL`, `login`, `expectLoggedIn`), `e2e/manage.ts` (`manage`), the demo seed (Stripe test account with the simulator, the 5 % fee, EGP).
- Produces: the spec's e2e (§9) and a green slice.

- [ ] **Step 1: Write the e2e**

`dashboard/e2e/b3-payment-links.spec.ts`:

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { manage } from "./manage";

// B3g spec §9: the admin creates a Stripe link for an unregistered payer; a
// logged-out browser pays it through the Stripe simulator; the link then
// shows Paid, and the payment records list shows the record with its fee.
test("a logged-out payer pays a payment link, and the admin sees the record", async ({
	page,
	browser,
}) => {
	manage(
		"set_features",
		"demo",
		"--on",
		"invoices",
		"online_payments",
		"payment_links",
		"payment_receipts",
	);
	const stamp = Date.now();
	const payer = `E2E Payer ${stamp}`;
	const title = `E2E link ${stamp}`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// 1. The admin creates a 500.00 Stripe link for an unregistered payer
	await page.goto(`${DEMO_URL}/app/billing/links`);
	await page.getByRole("button", { name: "Create link" }).click();
	const dialog = page.getByRole("dialog");
	await dialog.getByLabel(/^Payer's name/).fill(payer);
	await dialog.getByLabel(/^Title/).fill(title);
	await dialog.getByLabel(/^Amount/).fill("500");
	await dialog.getByRole("button", { name: "Create link" }).click();
	const row = page.getByRole("row").filter({ hasText: title });
	await expect(row).toContainText(payer);
	await expect(row).toContainText("Open");
	await expect(row).toContainText("EGP 25.00"); // the 5 % fee

	// The link's address, as the list's "Copy link" would give it
	const listed = await page.request.get(
		`${DEMO_URL}/api/v1/gateways/links/?q=${encodeURIComponent(title)}`,
	);
	expect(listed.status()).toBe(200);
	const { results } = (await listed.json()) as { results: { url: string }[] };
	const path = new URL(results[0].url).pathname;
	expect(path).toMatch(/^\/app\/pay\/link\/[\w-]+$/);

	// 2. A logged-out browser pays it through the simulator
	const visitor = await browser.newContext();
	const anon = await visitor.newPage();
	await anon.goto(`${DEMO_URL}${path}`);
	await expect(anon.getByText(title)).toBeVisible();
	await expect(anon.getByText("EGP 525.00")).toBeVisible();
	await anon.getByRole("button", { name: "Pay with Stripe" }).click();
	await expect(anon).toHaveURL(/\/app\/pay\/simulate\//);
	await anon.getByRole("button", { name: "Pay", exact: true }).click();
	await expect(anon).toHaveURL(/\/app\/pay\/return\?checkout=/);
	await expect(anon.getByText("Paid — thank you.")).toBeVisible();
	await expect(anon.getByRole("link")).toHaveCount(0); // status only, no back link

	// 3. The link now shows Paid, and a second visit cannot pay it again
	await anon.goto(`${DEMO_URL}${path}`);
	await expect(anon.getByText("This link has been paid. Thank you.")).toBeVisible();
	await expect(anon.getByRole("button", { name: /Pay with/ })).toBeDisabled();
	await visitor.close();

	// 4. The admin sees it Paid, and the record with its fee
	await page.goto(`${DEMO_URL}/app/billing/links`);
	await expect(
		page.getByRole("row").filter({ hasText: title }),
	).toContainText("Paid");
	await page.goto(`${DEMO_URL}/app/billing/payments`);
	const record = page.getByRole("row").filter({ hasText: payer });
	await expect(record).toContainText("Unregistered");
	await expect(record).toContainText("Stripe");
	await expect(record).toContainText("EGP 500.00");
	await expect(record).toContainText("EGP 25.00");
});
```

- [ ] **Step 2: Run the journey alone**

Run: `just e2e e2e/b3-payment-links.spec.ts`
Expected: PASS. If the demo academy's default currency is not EGP, the first `Amount (…)` label and the
amounts differ: set the currency in the dialog to EGP (`dialog.getByLabel(/^Currency/).selectOption("EGP")`)
before filling the amount.

- [ ] **Step 3: Run the gates**

All against this stream's stack:

```bash
just test
just lint
just e2e
set -a; . ./.env.stream; set +a
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm test:coverage
DJ="docker compose -f docker-compose.local.yml exec -T django"
$DJ python manage.py makemigrations --check --dry-run
```

Expected:
- `just test`: backend passes with coverage at or above 80 % (`--cov=etqan`), `tsc` clean, boundaries clean;
- `just lint`: ruff, biome, the colour check and `lint-imports` (both new contract edits) pass;
- `just e2e`: every spec passes (the known local `families.spec` race is retried once, as in Plans 20 and 22);
- dashboard coverage: lines and statements at or above 80 %, branches and functions at or above 70 %;
- `makemigrations --check` prints "No changes detected".

Also run, as the executor's own checklist for this slice:

```bash
$DJ pytest etqan/platform/tests/test_drf.py etqan/access -q   # route-walk and route table
$DJ pytest etqan/gateways etqan/billing etqan/finance etqan/tenants -q
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm vitest run 2>&1 | grep -c "not wrapped in act"
```

The last line must print 0.

- [ ] **Step 4: Commit the e2e and hand over**

```bash
git -C dashboard add e2e/b3-payment-links.spec.ts
git -C dashboard commit -m "test(e2e): a logged-out payer pays a payment link"
```

Report to the orchestrator:
- the commits per repo and the gate outputs;
- that no infra change is needed: no new package and no new environment variable (the throttle rate is a
  setting default);
- the non-blocking request to B2 (orchestration spec §6.2.1): one line in
  `routes/_authed/scheduling.subscriptions.$subscriptionId.tsx` rendering
  `<SubscriptionTermsCard subscriptionId={…} />` from `@/features/billing`; B3g does not wait for it (the card
  already shows on a subscription's invoice page);
- the spec amendments below, for the orchestrator to apply to the spec if it wants them there (this plan
  does not edit the spec).

---

## 12. Amendments from planning (Plan 26)

For B3g's spec. None of these changes what the slice does for a user; each fixes a name, a gap or a number.

- **G-15, the start route.** It reads "the generic `POST gateways/checkouts/` cannot start one". The route
  is `POST gateways/checkouts/start/` (Plan 20 D1). The rule is unchanged: a link purpose's `prepare` answers
  404 without a matching token, and that route passes no params.
- **G-22, imports.** Gateways may also read `academy.services` (the link's currency defaults to the
  academy's, §4.2), not only `identity.services`. The "gateways imports no business app" contract drops
  `etqan.identity` and `etqan.academy` and allows indirect imports; a new contract forbids gateways from
  their models, api and scopes.
- **§3.1, `customer_email`.** "`customer_email` and `customer_phone` (≤ 30)" is read as an email field
  (254) and a phone of at most 30 characters.
- **§3.1, the migration** is three files, one per step (`0004`, `0005`, `0006`), because Postgres refuses
  `ALTER TABLE` after an `UPDATE` with pending trigger events in one transaction. `SubscriptionTerms` is
  `0007`.
- **G-12, the fee rule.** `Prepared` and `fee_for` gain `use_switch` (default true). A payment link passes
  false so its own `add_fee` decides whatever `fee_enabled` says.
- **G-15, public purposes.** `register_purpose` gains `public` (default false), read through
  `is_public_purpose`; anonymous access is decided by it, so B7's purposes opt in the same way. A new
  permission class, `AuthenticatedOrPublicCheckout`, serves the status, capture, cancel and simulate routes.
- **G-14, the re-check.** Gateways asks a purpose "still payable?" with `params={"recheck": True}`
  (`RECHECK`); a link purpose accepts that, or a matching token, and nothing else.
- **§4.1, the payment row's `customer`** also carries `email` and `phone`, so the edit dialog can prefill
  them.
- **G-16, tokens.** A token that is not 1 to 32 characters of `[A-Za-z0-9_-]` is a 404 before any query.
- **B3c's capture and cancel views** need `atomic_request = False` next to their `non_atomic_requests`
  wrapper (the route-walk test in `platform/tests/test_drf.py` enforces both); Plan 22 had the wrapper only.
- **§8, seeds** go under `seed_academy`'s B3 marker through `seed_links(subdomain, student)`; a provider
  that is not enabled in the academy skips its link.
