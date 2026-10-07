# Plan 40 — Slice B3e: Student wallet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Slice:** B3e
**Requires:** — for Part A (B3h and B3d are its base). Part B (compensation) only if request R3 to B2 has landed (spec §7); otherwise Part B moves to B3f and B3e merges with no B2 change.

**Goal:** Each student holds money with the academy, one balance per currency, kept as an append-only ledger. The office tops it up in cash, adjusts it, moves an invoice payment into it and reverses a top-up; a family tops it up online; either spends it on the student's invoices. A balance is never negative and revenue counts each received amount once (ledger D36).

**Architecture:**
- **Backend, new app `etqan.wallet` (TENANT_APPS, B3 marker):** `Wallet` (one per student and currency, a cached balance), `WalletEntry` (signed amount, running balance, kind, plain ids of the payment, invoice and session) and `TopUp` (what an online top-up charges). Services in `etqan/wallet/services/` lock the wallet row (`select_for_update`) and append one entry per write; reads go through `balances_of` (ledger D37). A private gateways purpose `wallet_topup` is registered in `WalletConfig.ready()`.
- **Backend, billing (B3 owns it):** `Payment.Method.WALLET`, `Payment.Status.CREDITED`, `Payment.wallet_topup` and two checks (migration `billing.0009`); new services `record_wallet_payment`, `credit_payment`, `record_topup_payment`, `refund_topup_payment`, `invoice_for` (the old `online._readable`); delete, refund and edit refuse wallet money, deciding on the payment row re-read under its lock (E-9); payment rows carry `editable`, `deletable`, `refundable` and `wallet_topup` (E-10); `revenue_between` follows E-7.
- **API:** `/api/v1/wallet/…` (spec §5): the office's student reads and writes behind the new resource `wallet` and the feature `balances` (flipped to built in place, off by default); the family's `mine/`, top-up options and start, scoped by E-17 in the views.
- **Dashboard:** a new `src/features/wallet/` (the student card with its statement, Top up, Adjust and Reverse; Pay from balance and Move to balance passed into billing's invoice page by the routes; the family's Balance page with the online top-up), billing's pages reading the server's row flags, and the return page's `wallet_topup` branch.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query, react-hook-form + zod 4, i18next, `Intl`; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-06-b3e-student-wallet-design.md` (decisions E-1..E-25, review-revised). Ledger: D16 and D36 (revenue), D37 (`balances_of`), D19 (`NotImpersonating` on money routes), D25 (`ValidationError.code`), D28 (`RECHECK`, `use_switch`), D34 (dot-form row keys; no row lists here), request R3 (Part B). Format and conventions follow Plan 36 (`2026-10-05-plan-36-country-prices.md`).

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), and the meta worktree `/home/abdulkhalek/Projects/etqan_tutor-wt/b3` (trunk `master`). `marketing/` is not touched.
- **The orchestrator, not the implementer, creates `feat/b3e-wallet`** in `backend/`, `dashboard/` and meta from the current B3d tips (`backend` and `dashboard` are on `feat/b3d-country-prices`: trunk + B2e + B3h + B3d). Before Task 1, check `git -C backend branch --show-current` and `git -C dashboard branch --show-current` both print `feat/b3e-wallet`; stop and report if not.
- **Never run any `git submodule` subcommand.** Commit in the repo the change lives in (`git -C backend …`, `git -C dashboard …`), never the submodule pointers in meta, and never `git commit -a` in meta.
- Commits use Conventional Commits and end with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

**Ownership.** B3 owns `etqan.billing`, `etqan.gateways`, the new `etqan.wallet`, `features/billing`, `features/gateways` and the new `features/wallet`. The student page route (`people.students.$personId.tsx`) is a trunk page no phase owns (spec §7): B3e adds one card line to it and notes it in the PR. The scheduling files are B2's: Part B (Task 17) touches them only under a ledger claim and only if R3 has landed.

**Shared lists:** add lines only under the `── phase B3 ──` markers: `TENANT_APPS` (`config/settings/base.py`), `config/api_router.py`, the access `RESOURCES` (`etqan/access/registry.py`), `pyproject.toml`'s import contracts (and the platform contract's forbidden list), `seed_academy` (`seed_dev.py`), the dashboard `NAV_ITEMS`. `balances` is flipped **in place** in `etqan/platform/features.py`, where its `_later` line already sits (as B3d did with `country_pricing`). Test tables without markers take additive edits only (`access/tests/test_routes.py`, `access/tests/test_registry.py`, `platform/tests/test_features.py`, `platform/tests/test_drf.py`, `tenants/tests/test_seed_dev.py`, `tenants/tests/test_seed_links.py`, `features/shell/nav.test.ts`, `routes/permissions.test.ts`, `features/identity/schemas.ts`, `locales/*/errors.json`); keep both sides on a rebase conflict. Translations: a new area file `locales/{en,ar}/wallet.json`, plus keys in the existing `billing.json`, `gateways.json` and `errors.json`.

**Features:** `balances` becomes built in place, `default=False`, `requires=()` (E-21). Online top-ups also need `online_payments`; paying an invoice and moving a payment also need `invoices` (404 otherwise; the buttons hide). While `balances` is off every wallet route is a 404, but a started top-up still completes (E-16).

**Money:** integer minor units plus an ISO currency, converted in the dashboard only with `toMinor` / `toMajor` / `formatMoney` in the row's own currency. Never across currencies (E-2). Stored instants are UTC; the statement shows dates in the academy's timezone.

**Bad input is a 400, never a 500:** every body field goes through a serializer or a service check (`ValidationError(field=…)`); a JSON string, bool or float where an integer belongs is a 400 on that field.

**Locks:** two disjoint chains (E-6): money `Checkout → TopUp → Wallet → Invoice → Payment`; compensation (Part B) `Subscription → Session → Wallet`. Lock order is proven from the captured `FOR UPDATE` statements (`CaptureQueriesContext`), never with threads.

**Language:** only en and ar strings (E-25, D11), real Arabic: `locales.test.ts` fails when keys differ, and its gateways check fails when an ar value equals its en value.

**Dashboard forms:** dialogs use `defaultValues` + `useFillOnOpen` (from `@/features/finance/shared`), never `values:`; saves go through `saveOrShowErrors` (it maps the server's `amount_minor` onto the form's `amount`). Billing and gateways never import `@/features/wallet`: the routes pass wallet components into billing's `InvoicePage` (`actions`, the new `paymentActions`).

**Backend commands.** Run from the meta worktree, inside this stream's stack (`just dev-backend`). Load the ports first:
```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/b3
set -a && . ./.env.stream && set +a
export HOST_UID=$(id -u) HOST_GID=$(id -g)
DJ="docker compose -f docker-compose.local.yml run --rm -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan -e DJANGO_EMAIL_SUBJECT_PREFIX= django"
```
- Targeted tests: `$DJ pytest etqan/wallet -q` (add `--create-db` once after a task adds a migration).
- Migrations: `$DJ python manage.py makemigrations wallet` / `… billing`. Never run `manage.py`, `migrate` or e2e any other way.
- Format and lint: `$DJ sh -c 'ruff check --fix . && ruff format .'`, `$DJ lint-imports`.
- Whole suite: `just test-backend`. Watch `PLR0913` (keyword-only signatures that mirror an API body carry `# noqa: PLR0913 -- <reason>`).

**Dashboard commands.** From the meta worktree (`.env.stream` and `HOST_UID`/`HOST_GID` loaded as above):
```bash
DASH="docker compose -f docker-compose.local.yml run --rm dashboard"
```
- One test file: `$DASH pnpm vitest run src/features/wallet/<file>`.
- Full dashboard tests with coverage: `$DASH pnpm test:coverage`.
- Types: `just test-frontend` (`tsc --noEmit` only). Lint: `just lint-frontend` (`biome ci . && node scripts/check-colors.mjs`): semantic tokens only, no hex, no Tailwind palette utilities.
- A new route file regenerates `src/routeTree.gen.ts` with `$DASH pnpm exec vite build` before `tsc`; it is generated, never hand-edited.
- Format: `$DASH pnpm exec biome check --write src e2e`.

**Gates before queuing:** `just test`, `just lint`, the gitleaks directory scan, `just e2e e2e/b3-wallet.spec.ts` (twice: it must pass on a rerun) plus the full `just e2e`, backend coverage ≥ 80 %, dashboard lines and statements ≥ 80, branches and functions ≥ 70.

## Decisions (gaps the spec left, filled here)

| # | Decision |
|---|---|
| W1 | **Branches:** the orchestrator creates `feat/b3e-wallet` in backend, dashboard and meta from the current B3d tips; the implementer only checks it (Global Constraints). |
| W2 | **`balances` is flipped in place** where its `_later` line sits (spec §7), not added under the marker (the code already exists in the registry). `platform/tests/test_features.py`'s `BUILT` gains `"balances": False` right after `"country_pricing": False` (registry order). |
| W3 | **The resource `wallet` lands with its routes (Task 8)**, not with the app (Task 1): `test_every_code_in_the_table_is_in_the_registry_and_in_use` requires every in-use code to be declared by a route. |
| W4 | **Migrations:** `wallet.0001_initial` (Task 1, holding the `compensation` kind and its constraint, so Part B adds none) and `billing.0009_*` (Task 2, after B3d's `0008`). |
| W5 | **`Payment.wallet_topup` has `default=False` and `db_default=False`:** with `db_default` alone a fresh instance reads a `DatabaseDefault` (truthy) until refreshed, and the payload reads it right after a create. |
| W6 | **Billing placement:** `record_wallet_payment`, `credit_payment`, `refund_topup_payment` and the guard `refuse_wallet_money` live in `billing/services/payments.py` (beside `_recalculate`); `record_topup_payment` in `records.py` (beside `_check_unique` / `_save`); `online._readable(reference_id, user)` becomes the public `invoice_for(user, invoice_id)` (the spec's argument order). Billing also exports `METHOD_LABELS = dict(Payment.Method.choices)` for the statement's notes. |
| W7 | **Refusals inside billing that the wallet pre-empts:** `credit_payment` on a standalone record is a 400 on `payment` (the wallet answers 409 `wallet.not_invoice_payment` first); `refund_topup_payment` on a non-top-up is 409 `billing.not_topup` (the wallet answers `wallet.not_topup` first) and on a non-completed top-up 409 `billing.already_refunded` (the existing code). `record_topup_payment` takes `by=None` for a manual method (the seeds), and refuses a fee on a manual method (400 `fee_minor`). |
| W8 | **A debit never creates a wallet:** `lock_wallet(..., create=False)` answers `None` when the (student, currency) row is missing, which is 409 `wallet.insufficient_balance`. A credit `get_or_create`s the row first (the unique constraint settles a race), then locks it. |
| W9 | **Paying an invoice, the order of checks:** a non-integer or < 1 `amount_minor` → 400; void → 409 `billing.invoice_void`; nothing due → 409 `wallet.nothing_due`; amount (given, or the default `min(wallet, due)`) < 1 or over the wallet → 409 `wallet.insufficient_balance`; over the invoice balance → billing's 400 `amount_minor`. A payer-only family member (E-17) and a stranger get 404. |
| W10 | **Lock order per write, as asserted:** pay = `wallet_wallet → billing_invoice` (the payment is inserted, so no payment row lock: the spec's "then payment" holds for move only); move = `wallet_wallet → billing_invoice → billing_payment`; reverse = `wallet_wallet → billing_payment`; online completion = `gateways_checkout → wallet_topup → wallet_wallet`; billing's own delete and credit = `billing_invoice → billing_payment`. |
| W11 | **Adjustments:** a non-zero integer with `abs(amount_minor) ≤ 100,000,000` (the top-up cap, E-19), and a reason trimmed to 1–500 characters. A staff account's sign is checked in the view: positive needs `wallet.create`, negative `wallet.update` (403 otherwise). |
| W12 | **Entry notes** (written by the service, E-22): manual top-up `"<method label>[ · <reference>]"`; online top-up the provider's label (`Stripe`, `PayPal`); `spend` and `refund` the invoice number; `reversal` empty; `adjustment` the reason (blanked for a family reader); compensation `"<YYYY-MM-DD> · <course name_en>[ · <reason>]"`. |
| W13 | **Entry payload gains `reversed`** (true on a `topup` entry whose payment has a `reversal` entry), so the dashboard hides Reverse on a top-up already given back. Additive to spec §5's shape. |
| W14 | **Route matrix:** the student reads and the office writes (seven routes) are tabled in `ROUTES` and `FEATURES` (`balances`) with `FEATURE_WORDS["/wallet/"] = "balances"`. The adjustments row's code is the tuple `("wallet.create", "wallet.update")` (either passes `HasCode`; the sign is checked in the view, W11). Move's `payment.update` is checked in the view *after* the payment lookup (as B9b's quick login checks the kind's code past the lookup), so an unknown id is 404 first and the matrix's "with the code: not 403" holds. `mine/`, `top-ups/options/` and `top-ups/` are `SELF_SERVICE` (families only, E-17 in the views, like `StartCheckoutView`). |
| W15 | **An unknown student id is 404** for every student route (`student_of` raises `NotFoundError`), for the office and the family alike. |
| W16 | **`REUSE_FOR = timedelta(hours=23)`** is the wallet's own constant, mirroring gateways' (`gateways/services/checkouts.py:39`), which `gateways.services` does not re-export. |
| W17 | **Top-up currencies (E-18)** are ordered: the academy's `default_currency` first, then the rest sorted. A start in a currency not in that list is a 400 on `currency`. |
| W18 | **Billing's existing lock test changes for delete:** `test_every_write_locks_the_invoice_row_first` asserted a single `FOR UPDATE`; E-9's re-read makes delete lock the invoice, then the payment (Task 3 updates the assertion for `delete` only). |
| W19 | **Seed side effects:** `test_seed_links` reads standalone records; its `state()` now leaves out `wallet_topup` records. `test_seed_dev`'s demo EGP revenue rises from 200000 to 230000 (Aisha's cash top-up is revenue, E-7). |
| W20 | **Invoice page rows:** `InvoicePage` gains `paymentActions?: (payment: Payment) => ReactNode`. A `refunded` or `credited` payment shows a chip (`Refunded` / `Moved to balance`) and "Refunded on …" / "Moved on …" from `refunded_at`, in the academy's timezone. The records page's method filter gains `wallet` ("Balance"). |
| W21 | **Who sees Pay from balance:** on the office page, `wallet.update` and `wallet.view_any` (it reads the balance) and `balances`; on the family page, every student or parent (the server checks E-17; a payer-only reader's balance read is a 404, so the button stays hidden). Both need an open invoice with a balance and a wallet above 0 in its currency. The office's dialog has an editable amount; the family's is a confirmation that sends no amount (the server's default). |
| W22 | **A staff account holding only one adjustment code** gets a client-side refusal on the wrong sign ("You may only add to the balance." / "…only take away…") before the server's 403. |
| W23 | **Part B's `compensable` flag** also requires `subscription.archived_at is None` (spec E-23 wording), which is stricter than R3's server refusal (only while `subscription_archive` is on); the claim stays scheduling's decision. A compensation's optional reason is appended to its note (W12), so the family sees it like the other notes. |
| W24 | **The return page's `wallet_topup` branch** asks `me` (a private purpose, D30) and shows "Back to the balance" / "Try again" links to `/learning/wallet` once `me` has settled. |

## Review Focus

1. **A debit raced by another write** (two tabs: one spends 200.00 while the other reverses the 300.00 top-up or adjusts −300.00, each from a page that loaded 300.00): the second is 409 `wallet.insufficient_balance` because the service reads the balance after the lock, and nothing is written. Tests in Task 6 (`test_a_debit_reads_the_balance_after_the_lock`) and the DB CHECKs in Task 1.
2. **A payment moved to the balance while the office still has the invoice page open (C1):** Delete or Mark refunded on that stale row is 409 `billing.payment_credited` (and `billing.wallet_payment` for a balance payment), the wallet and its entries unchanged. Tests in Task 3 (billing alone) and Task 6 (`test_c1_…`, with the wallet).
3. **Odd input on every money field:** `"100"`, `true`, `1.5`, `0`, `-5`, `100000001`, `"usd"` (accepted, upper-cased), `"US"`, a future `paid_on`, a whitespace-only reason, an unknown provider: each a 400 on its field (or accepted where noted), never a 500 and never a partial write. Tests in Tasks 5 and 8.
4. **Online money that does not fit:** a second paid checkout for one top-up (credited again), the same provider transaction twice (`already_recorded`), a currency or amount that differs from the row (attention), and completion while `balances` is off (still credited). Tests in Task 7.
5. **What a family must not see or do:** no `created_by`, no adjustment reason, no sibling's wallet as a payer-only reader (404), no write while impersonated (403). Tests in Task 8 (API) and Task 14 (the Balance page).

## File structure

**Backend (`backend/`)**

| Path | Responsibility |
|---|---|
| `etqan/wallet/__init__.py`, `apps.py` | the app; `ready()` registers the `wallet_topup` purpose (Task 7) |
| `etqan/wallet/models.py`, `migrations/0001_initial.py` (generated) | `Wallet`, `WalletEntry`, `TopUp`, `MAX_TOPUP_MINOR` |
| `etqan/wallet/services/__init__.py` | the public API |
| `etqan/wallet/services/reads.py` | `Balance`, `balances_of` (D37), `entries_of`, `student_of`, `may_use`, `family_wallets`, `topup_currencies`, `has_entries` |
| `etqan/wallet/services/ledger.py` | `lock_wallet`, `write`, `top_up`, `adjust`, `pay_invoice`, `move_to_wallet`, `reverse_topup`, `find_payment` |
| `etqan/wallet/services/online.py`, `topup_purpose.py` | `start_top_up`; the purpose's `prepare` / `complete` |
| `etqan/wallet/services/compensation.py` (Part B only) | `compensation_for`, `compensate` |
| `etqan/wallet/api/{urls,views,serializers,payloads}.py` | the routes of spec §5 |
| `etqan/wallet/tests/` | `conftest.py`, `test_models.py`, `test_ledger.py`, `test_spending.py`, `test_online_topup.py`, `test_api.py`, (Part B) `test_compensation.py` |
| `etqan/billing/models.py`, `migrations/0009_*.py` (generated) | `WALLET`, `CREDITED`, `wallet_topup`, two checks |
| `etqan/billing/services/payments.py`, `records.py`, `online.py`, `summary.py`, `__init__.py` | wallet services, guards on the locked row, `invoice_for`, revenue (E-7) |
| `etqan/billing/api/payloads.py` | the row flags (E-10) |
| `etqan/billing/tests/test_wallet_columns.py`, `test_wallet_payments.py`, `test_invoices.py` | new tests; the delete lock assertion (W18) |
| `etqan/platform/features.py`, `platform/tests/test_features.py`, `platform/tests/test_drf.py` | `balances`; `StartTopUpView` is non-atomic |
| `etqan/access/registry.py`, `access/tests/test_registry.py`, `access/tests/test_routes.py` | the `wallet` resource, the route matrix |
| `config/settings/base.py`, `config/api_router.py`, `pyproject.toml` | the app, its routes, its import contracts |
| `etqan/tenants/seeds/wallet.py`, `management/commands/seed_dev.py`, `tests/test_seed_wallet.py`, `tests/test_seed_dev.py`, `tests/test_seed_links.py` | `seed_wallet` |

**Dashboard (`dashboard/`)**

| Path | Responsibility |
|---|---|
| `src/features/billing/schemas.ts`, `InvoicePage.tsx`, `PaymentRecordsPage.tsx`, `InvoicePrint.tsx` (+ tests) | `credited`, `wallet`, the row flags, `paymentActions` |
| `src/features/wallet/schemas.ts`, `api.ts`, `queries.ts`, `index.ts` (+ tests) | types, form schemas, `walletApi`, `useWalletMutation` |
| `src/features/wallet/Statement.tsx` (+ test) | one currency's statement with Reverse |
| `src/features/wallet/StudentWalletCard.tsx`, `TopUpDialog.tsx`, `AdjustDialog.tsx` (+ test) | the student page's card |
| `src/features/wallet/PayFromWallet.tsx`, `MoveToWallet.tsx` (+ tests) | the invoice page's actions |
| `src/features/wallet/FamilyWalletPage.tsx`, `OnlineTopUpDialog.tsx` (+ tests) | the family's Balance page |
| `src/features/wallet/SessionWalletCard.tsx` (+ test, Part B only) | the session page's card |
| `src/features/gateways/ReturnPage.tsx` (+ test) | the `wallet_topup` branch |
| `src/routes/_authed/people.students.$personId.tsx` (+ new test), `billing.invoices.$invoiceId.tsx`, `learning.invoices.$invoiceId.tsx`, `learning.wallet.tsx` (new) | wiring |
| `src/features/shell/nav.ts`, `nav.test.ts`, `src/routes/permissions.test.ts`, `src/features/identity/schemas.ts` | nav item, `FEATURE_SCREENS` / `FEATURE_WORDS`, `FeatureCode` |
| `src/locales/{en,ar}/wallet.json` (new), `billing.json`, `gateways.json`, `errors.json` | strings |
| `src/test/billing-fixtures.ts`, `src/test/wallet-fixtures.ts` (new) | fixtures |
| `e2e/b3-wallet.spec.ts` | the journey through Caddy |

---

### Task 1: The wallet app, its models and the `balances` feature

**Files:**
- Create: `backend/etqan/wallet/__init__.py`, `backend/etqan/wallet/apps.py`, `backend/etqan/wallet/models.py`, `backend/etqan/wallet/migrations/__init__.py`, `backend/etqan/wallet/migrations/0001_initial.py` (generated), `backend/etqan/wallet/services/__init__.py`, `backend/etqan/wallet/tests/__init__.py`, `backend/etqan/wallet/tests/conftest.py`, `backend/etqan/wallet/tests/test_models.py`
- Modify: `backend/config/settings/base.py` (B3 marker), `backend/etqan/platform/features.py` (in place), `backend/etqan/platform/tests/test_features.py`, `backend/pyproject.toml` (B3 marker)

**Interfaces:**
- Produces:
  - `etqan.wallet.models.MAX_TOPUP_MINOR = 100_000_000`;
  - `Wallet(student → identity.StudentProfile PROTECT, currency, balance_minor ≥ 0, created_at, updated_at)`, unique `(student, currency)`;
  - `WalletEntry(wallet → Wallet PROTECT related_name="entries", kind, amount_minor, balance_after_minor ≥ 0, payment_id, invoice_id, session_id, top_up → TopUp PROTECT, note ≤ 500, created_by, created_at)` with `WalletEntry.Kind` (`TOPUP`, `REFUND`, `ADJUSTMENT`, `SPEND`, `REVERSAL`, `COMPENSATION`), `CREDITS`, `DEBITS`, `WITH_PAYMENT`;
  - `TopUp(student, currency, amount_minor 1..MAX, status pending|paid, created_by, created_at, paid_at)` with `TopUp.Status`;
  - feature `balances` built, `default=False`, `requires=()`;
  - test helpers in `etqan/wallet/tests/conftest.py`: fixtures `clock`, `world`, `admin`, `wallet_on`, `online_on`, `stripe_on`, `paypal_on`, `parent`, `invoice`; functions `profile_id(user)`, `as_user(user)`, `ledger_holds(student_user_id)`.

- [ ] **Step 1: Write the failing tests**

In `backend/etqan/platform/tests/test_features.py`, in `BUILT`, insert after `"country_pricing": False,` (registry order) and add B3e to the comment above the block ("…, B3d's country_pricing, B3e's balances, B3's donations, …"):

```python
    "balances": False,
```

Create `backend/etqan/wallet/__init__.py`:

```python
"""Student wallets (phase B3, slice B3e)."""
```

Create `backend/etqan/wallet/tests/__init__.py` (empty) and `backend/etqan/wallet/tests/conftest.py`:

```python
"""Wallet fixtures. Every clock is pinned to Monday 1 June 2026, 08:00 UTC:
scheduling's, billing's (payment dates) and gateways' (completion), as in
gateways' tests. The test academy's default currency is USD."""

from datetime import date

import pytest
from rest_framework.test import APIClient

from etqan.billing import services as billing_services
from etqan.billing.tests.conftest import make_parent
from etqan.gateways import services as gateways_services
from etqan.gateways.tests.conftest import PAYPAL_KEYS
from etqan.gateways.tests.conftest import TEST_KEYS
from etqan.gateways.tests.conftest import Clock
from etqan.identity import services as identity_services
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_admin


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
def wallet_on(set_features):
    """B3e ships `balances` off (E-21); paying and moving also need invoices."""
    return set_features(invoices=True, balances=True)


@pytest.fixture
def online_on(set_features):
    return set_features(invoices=True, balances=True, online_payments=True)


@pytest.fixture
def stripe_on():
    """An enabled Stripe account in test mode (the simulator, a 5 % fee)."""
    gateways_services.update_settings(stripe=TEST_KEYS, by=None)
    return gateways_services.stripe_account()


@pytest.fixture
def paypal_on():
    """An enabled PayPal Sandbox account in USD."""
    gateways_services.update_settings(paypal=PAYPAL_KEYS, by=None)
    return gateways_services.paypal_account()


@pytest.fixture
def parent(world):
    return make_parent("Zainab", world.student)


@pytest.fixture
def invoice(world, admin):
    """`invoice(amount_minor=20000)`: an unpaid EGP invoice for Yusuf, due
    8 June."""

    def make(**overrides):
        fields = {
            "student_id": world.student.id,
            "amount_minor": 20000,
            "currency": "EGP",
            "due_on": date(2026, 6, 8),
            "description": "Tajweed — June",
            "by": admin,
            **overrides,
        }
        return billing_services.create_invoice(**fields)

    return make


def profile_id(user) -> int:
    """The StudentProfile's pk of a student ``user``."""
    return identity_services.get_student_profile(user.pk).pk


def as_user(user) -> APIClient:
    client = APIClient()
    client.force_login(user)
    return client


def ledger_holds(student_user_id: int) -> None:
    """E-3: each wallet's cache is the sum of its entries and the last
    running balance."""
    from etqan.wallet.models import Wallet  # noqa: PLC0415

    for wallet in Wallet.objects.filter(student__user_id=student_user_id):
        entries = list(wallet.entries.order_by("id"))
        assert wallet.balance_minor == sum(e.amount_minor for e in entries)
        last = entries[-1].balance_after_minor if entries else 0
        assert wallet.balance_minor == last
```

Create `backend/etqan/wallet/tests/test_models.py`:

```python
"""B3e §3.1, E-3, E-21: the ledger's tables refuse what the services never
write; `balances` is built, off by default and needs nothing."""

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.platform import features
from etqan.wallet.models import MAX_TOPUP_MINOR
from etqan.wallet.models import TopUp
from etqan.wallet.models import Wallet
from etqan.wallet.models import WalletEntry
from etqan.wallet.tests.conftest import profile_id

pytestmark = pytest.mark.django_db


@pytest.fixture
def wallet(world):
    return Wallet.objects.create(student_id=profile_id(world.student), currency="EGP")


def refused(make):
    with pytest.raises(IntegrityError), transaction.atomic():
        make()


def entry(wallet, **fields):
    values = {
        "wallet": wallet,
        "kind": "topup",
        "amount_minor": 100,
        "balance_after_minor": 100,
        "payment_id": 1,
        **fields,
    }
    return WalletEntry.objects.create(**values)


def test_balances_is_built_off_by_default_and_needs_nothing():
    feature = features.get("balances")
    assert (feature.built, feature.default, feature.requires) == (True, False, ())


def test_one_wallet_per_student_and_currency(wallet):
    refused(lambda: Wallet.objects.create(student_id=wallet.student_id, currency="EGP"))
    Wallet.objects.create(student_id=wallet.student_id, currency="USD")


def test_a_balance_is_never_negative(wallet):
    refused(lambda: Wallet.objects.filter(pk=wallet.pk).update(balance_minor=-1))
    first = entry(wallet)
    refused(
        lambda: WalletEntry.objects.filter(pk=first.pk).update(balance_after_minor=-1)
    )


@pytest.mark.parametrize(
    ("kind", "amount"),
    [
        ("topup", -1),
        ("topup", 0),
        ("refund", -1),
        ("compensation", -1),
        ("spend", 1),
        ("reversal", 1),
        ("adjustment", 0),
    ],
)
def test_the_sign_follows_the_kind(wallet, kind, amount):
    refused(lambda: entry(wallet, kind=kind, amount_minor=amount, session_id=7))


def test_money_kinds_name_their_payment_and_compensation_its_session(wallet):
    for kind, sign in (("topup", 1), ("refund", 1), ("spend", -1), ("reversal", -1)):
        refused(
            lambda kind=kind, sign=sign: entry(
                wallet, kind=kind, amount_minor=sign, payment_id=None
            )
        )
    refused(lambda: entry(wallet, kind="compensation", payment_id=None))
    entry(wallet, kind="adjustment", amount_minor=-5, payment_id=None)
    entry(wallet, kind="compensation", payment_id=None, session_id=9)


def test_one_entry_per_kind_and_payment_and_one_compensation_per_session(wallet):
    entry(wallet, payment_id=5)
    refused(lambda: entry(wallet, payment_id=5))
    entry(wallet, kind="spend", amount_minor=-1, payment_id=5)
    entry(wallet, kind="compensation", payment_id=None, session_id=9)
    refused(lambda: entry(wallet, kind="compensation", payment_id=None, session_id=9))
    entry(wallet, kind="adjustment", payment_id=None, session_id=9)


def test_a_top_up_row_holds_1_to_the_cap(world):
    student = profile_id(world.student)

    def row(amount):
        return TopUp.objects.create(student_id=student, currency="EGP", amount_minor=amount)

    refused(lambda: row(0))
    refused(lambda: row(MAX_TOPUP_MINOR + 1))
    assert row(MAX_TOPUP_MINOR).status == "pending"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/wallet etqan/platform/tests/test_features.py -q`
Expected: FAIL (`ModuleNotFoundError: etqan.wallet.models`; `balances` not in `BUILT`).

- [ ] **Step 3: Implement the app and the models**

Create `backend/etqan/wallet/apps.py` (Task 7 adds `ready()`):

```python
from django.apps import AppConfig


class WalletConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.wallet"
    label = "wallet"
```

Create `backend/etqan/wallet/migrations/__init__.py` (empty) and `backend/etqan/wallet/services/__init__.py`:

```python
"""Public API of the wallet module (B3e). Other apps import only this
package; later phases read balances only through `balances_of` (D37)."""

__all__: list[str] = []
```

Create `backend/etqan/wallet/models.py`:

```python
"""Student wallets (phase B3, slice B3e): one balance per student and
currency, kept as an append-only ledger (E-2, E-3). Other apps' rows are
referenced by string or by plain id: wallet imports no other app's models."""

from django.conf import settings
from django.core.validators import MaxValueValidator
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
from django.db import models
from django.db.models import Q

CURRENCY = RegexValidator(r"^[A-Z]{3}$")
# E-19: the most one top-up adds, online or by hand.
MAX_TOPUP_MINOR = 100_000_000


class Wallet(models.Model):
    """Created on its first credit (E-2, plan W8). PROTECT: students are
    deactivated, never deleted."""

    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    # E-3: a cache of the entries' sum, written only by the services, in the
    # entry's transaction.
    balance_minor = models.BigIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["currency", "id"]
        constraints = [
            models.UniqueConstraint(
                fields=["student", "currency"], name="wallet_one_per_currency"
            ),
            models.CheckConstraint(
                condition=Q(balance_minor__gte=0), name="wallet_balance_not_negative"
            ),
        ]

    def __str__(self):
        return f"Wallet<{self.student_id}, {self.currency}, {self.balance_minor}>"


class TopUp(models.Model):
    """E-15: what an online top-up charges, created before its checkout (the
    checkout's `reference_id`), so a re-check prices it without request data."""

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        PAID = "paid", "Paid"

    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    amount_minor = models.BigIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(MAX_TOPUP_MINOR)]
    )
    status = models.CharField(
        max_length=8, choices=Status.choices, default=Status.PENDING
    )
    # `prepare` fails closed without one (E-15).
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    paid_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=Q(amount_minor__gte=1, amount_minor__lte=MAX_TOPUP_MINOR),
                name="wallet_topup_amount_range",
            )
        ]

    def __str__(self):
        return f"TopUp<{self.pk}, {self.currency}, {self.amount_minor}, {self.status}>"


class WalletEntry(models.Model):
    """E-3, E-4: one movement, never updated or deleted; a correction is
    itself an entry (P2 rule P2)."""

    class Kind(models.TextChoices):
        TOPUP = "topup", "Top-up"
        REFUND = "refund", "Moved from an invoice"
        ADJUSTMENT = "adjustment", "Adjustment"
        SPEND = "spend", "Paid an invoice"
        REVERSAL = "reversal", "Top-up given back"
        COMPENSATION = "compensation", "Compensation"

    wallet = models.ForeignKey(
        Wallet, on_delete=models.PROTECT, related_name="entries"
    )
    kind = models.CharField(max_length=12, choices=Kind.choices)
    amount_minor = models.BigIntegerField()  # credit > 0, debit < 0
    balance_after_minor = models.BigIntegerField()
    # Plain ids (E-1): billing's payment and invoice, scheduling's session.
    payment_id = models.BigIntegerField(null=True, blank=True, db_index=True)
    invoice_id = models.BigIntegerField(null=True, blank=True)
    session_id = models.BigIntegerField(null=True, blank=True)
    top_up = models.ForeignKey(
        TopUp, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    note = models.CharField(max_length=500, blank=True, default="")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-id"]
        indexes = [models.Index(fields=["wallet", "-id"], name="wallet_entry_newest")]
        constraints = [
            models.CheckConstraint(
                condition=Q(balance_after_minor__gte=0),
                name="wallet_entry_balance_not_negative",
            ),
            # E-4: the sign follows the kind; an adjustment is either, not 0.
            models.CheckConstraint(
                condition=Q(
                    kind__in=["topup", "refund", "compensation"], amount_minor__gt=0
                )
                | Q(kind__in=["spend", "reversal"], amount_minor__lt=0)
                | (Q(kind="adjustment") & ~Q(amount_minor=0)),
                name="wallet_entry_sign_follows_kind",
            ),
            models.CheckConstraint(
                condition=~Q(kind="compensation") | Q(session_id__isnull=False),
                name="wallet_entry_compensation_has_session",
            ),
            models.CheckConstraint(
                condition=~Q(kind__in=["topup", "refund", "spend", "reversal"])
                | Q(payment_id__isnull=False),
                name="wallet_entry_money_has_payment",
            ),
            models.UniqueConstraint(
                fields=["kind", "payment_id"],
                condition=Q(payment_id__isnull=False),
                name="wallet_entry_one_per_payment",
            ),
            # Part B (E-23): the constraint ships now, so Part B adds no migration.
            models.UniqueConstraint(
                fields=["session_id"],
                condition=Q(kind="compensation"),
                name="wallet_entry_one_compensation_per_session",
            ),
        ]

    def __str__(self):
        return f"WalletEntry<{self.kind}, {self.amount_minor}>"


CREDITS = (WalletEntry.Kind.TOPUP, WalletEntry.Kind.REFUND, WalletEntry.Kind.COMPENSATION)
DEBITS = (WalletEntry.Kind.SPEND, WalletEntry.Kind.REVERSAL)
WITH_PAYMENT = (
    WalletEntry.Kind.TOPUP,
    WalletEntry.Kind.REFUND,
    WalletEntry.Kind.SPEND,
    WalletEntry.Kind.REVERSAL,
)
```

`backend/config/settings/base.py`, `TENANT_APPS`, under `# ── phase B3 ──`, after `"etqan.gateways",`:

```python
    "etqan.wallet",
```

`backend/etqan/platform/features.py`: replace the existing

```python
    _later("balances", "Balances", "نظام الأرصدة", "money"),
```

in place with

```python
    # Phase B3, slice B3e (E-21): built, off by default, needs nothing
    # (online top-ups and paying invoices check their own features).
    _built("balances", "Balances", "نظام الأرصدة", "money", default=False),
```

`backend/pyproject.toml`:
- In "platform imports no business modules", under `# ── phase B3 ──`, after `"etqan.gateways",`: `"etqan.wallet",`.
- In "gateways imports no business app", append `"etqan.wallet"` to `forbidden_modules` (after `"etqan.finance"`).
- In "other apps reach gateways only through its services", append `"etqan.wallet"` to `source_modules` (after `"etqan.finance"`).
- Under `# ── phase B3 ──`, after the last B3 contract ("other apps reach gateways only through its services"), add:

```toml
[[tool.importlinter.contracts]]
name = "wallet reaches other apps only through their services"
type = "forbidden"
# B3e E-1: billing, gateways, identity, scheduling and academy through their
# services only; never another app's models, api, scopes or clock.
source_modules = ["etqan.wallet"]
forbidden_modules = [
    "etqan.identity.models", "etqan.identity.api",
    "etqan.catalogue",
    "etqan.academy.models", "etqan.academy.api",
    "etqan.scheduling.models", "etqan.scheduling.api", "etqan.scheduling.dates",
    "etqan.scheduling.scopes", "etqan.scheduling.tasks",
    "etqan.billing.models", "etqan.billing.api", "etqan.billing.scopes", "etqan.billing.clock",
    "etqan.gateways.models", "etqan.gateways.api", "etqan.gateways.providers",
    "etqan.gateways.clock", "etqan.gateways.paypal",
    "etqan.finance", "etqan.payroll", "etqan.notifications", "etqan.access",
    "etqan.tenants", "etqan.site",
]
# wallet.services -> billing.services -> billing.models is the allowed path.
allow_indirect_imports = true
ignore_imports = ["etqan.wallet.tests.** -> etqan.**"]

[[tool.importlinter.contracts]]
name = "other apps reach wallet only through its services"
type = "forbidden"
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.scheduling", "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access", "etqan.finance", "etqan.gateways"]
forbidden_modules = ["etqan.wallet.models", "etqan.wallet.api"]
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "billing never imports wallet"
type = "forbidden"
# E-1: the wallet calls billing; billing never reads the wallet.
source_modules = ["etqan.billing"]
forbidden_modules = ["etqan.wallet"]

[[tool.importlinter.contracts]]
name = "scheduling never imports wallet"
type = "forbidden"
# E-1, E-23: the wallet calls scheduling's claim; never the reverse.
source_modules = ["etqan.scheduling"]
forbidden_modules = ["etqan.wallet"]
```

Generate the migration: `$DJ python manage.py makemigrations wallet` (it writes `wallet/migrations/0001_initial.py`; commit it as generated).

- [ ] **Step 4: Run the tests, format, lint, commit**

Run: `$DJ pytest etqan/wallet etqan/platform -q --create-db`
Expected: PASS.
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`
Expected: clean (the wallet imports nothing yet but its own models).

```bash
git -C backend add etqan/wallet config/settings/base.py etqan/platform/features.py etqan/platform/tests/test_features.py pyproject.toml
git -C backend commit -m "feat(wallet): the wallet app, its ledger tables and the balances feature (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 2: Billing: the wallet method, the credited status, the top-up flag and revenue

**Files:**
- Modify: `backend/etqan/billing/models.py`, `backend/etqan/billing/services/payments.py`, `backend/etqan/billing/services/summary.py`, `backend/etqan/billing/services/__init__.py`
- Create: `backend/etqan/billing/migrations/0009_*.py` (generated), `backend/etqan/billing/tests/test_wallet_columns.py`

**Interfaces:**
- Produces:
  - `Payment.Method.WALLET = "wallet"` (label "Balance"), `Payment.Status.CREDITED = "credited"` (label "Moved to balance"), `Payment.wallet_topup: bool` (default False);
  - checks `billing_payment_wallet_on_invoice` and `billing_payment_topup_standalone` (E-8);
  - in `billing.services.payments`: `WALLET`, `CREDITED`, `NOT_MANUAL = ONLINE_METHODS | {WALLET}`, `MANUAL_PAYMENT_METHODS` (unchanged value), `METHOD_LABELS: dict[str, str]`; exported from `billing.services`: `METHOD_LABELS`;
  - `revenue_between` per E-7.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/billing/tests/test_wallet_columns.py`:

```python
"""B3e E-7, E-8: billing's wallet method, the credited status, the top-up
flag, their two checks, the unchanged manual methods and revenue."""

from datetime import date

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.billing import services
from etqan.billing.models import Payment
from etqan.billing.tests.test_invoices import invoice_for
from etqan.identity import services as identity_services

JUNE = (date(2026, 6, 1), date(2026, 7, 1))


def record(world, **fields):
    """A raw payment row (the checks, not the services, are under test)."""
    values = {
        "currency": "EGP",
        "amount_minor": 1000,
        "method": "cash",
        "paid_on": date(2026, 6, 1),
        "customer_type": "student",
        "student": identity_services.get_student_profile(world.student.pk),
        **fields,
    }
    return Payment.objects.create(**values)


def refused(make):
    with pytest.raises(IntegrityError), transaction.atomic():
        make()


def test_the_wallet_is_a_method_but_never_a_manual_one():
    assert (Payment.Method.WALLET, Payment.Status.CREDITED) == ("wallet", "credited")
    assert "wallet" not in [value for value, _ in services.MANUAL_PAYMENT_METHODS]
    assert services.METHOD_LABELS["wallet"] == "Balance"
    assert services.METHOD_LABELS["cash"] == "Cash"


def test_a_wallet_payment_pays_an_invoice_with_no_fee(world, admin):
    bill = invoice_for(world, admin, currency="EGP")
    refused(lambda: record(world, method="wallet"))
    refused(lambda: record(world, invoice=bill, method="wallet", fee_minor=10))
    assert record(world, invoice=bill, method="wallet").fee_minor == 0


def test_a_top_up_is_a_students_standalone_record(world, admin):
    bill = invoice_for(world, admin, currency="EGP")
    assert record(world).wallet_topup is False
    refused(lambda: record(world, invoice=bill, wallet_topup=True))
    refused(
        lambda: record(
            world,
            wallet_topup=True,
            customer_type="unregistered",
            student=None,
            customer_name="Abu Khalid",
        )
    )
    refused(lambda: record(world, wallet_topup=True, method="wallet"))
    assert record(world, wallet_topup=True, method="stripe").wallet_topup is True


def test_revenue_counts_top_ups_and_credited_payments_but_never_wallet_spends(
    world, admin
):
    """E-7 (ledger D36): received once, counted once."""
    bill = invoice_for(world, admin, currency="EGP", amount_minor=50000)
    record(world, wallet_topup=True, amount_minor=10000)
    record(world, wallet_topup=True, method="stripe", amount_minor=5000, fee_minor=250)
    record(world, invoice=bill, method="wallet", amount_minor=3000)
    record(world, invoice=bill, amount_minor=2000, status="credited")
    record(world, invoice=bill, method="wallet", amount_minor=900, status="credited")
    record(world, wallet_topup=True, amount_minor=700, status="refunded")
    assert services.revenue_between(*JUNE) == [
        {"currency": "EGP", "amount_minor": 10000 + 5250 + 2000}
    ]
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/billing/tests/test_wallet_columns.py -q`
Expected: FAIL (`AttributeError: WALLET`; the field `wallet_topup` is unknown).

- [ ] **Step 3: Implement the columns, the constants and revenue**

`backend/etqan/billing/models.py`, in `Payment.Method`, after `PAYPAL = "paypal", "PayPal"`:

```python
        # B3e E-8: paid from the student's balance; never by hand, never
        # revenue (the money counted when it was topped up).
        WALLET = "wallet", "Balance"
```

in `Payment.Status`, after `REFUNDED = "refunded", "Refunded"`:

```python
        # B3e E-12: moved into the student's balance; stays revenue.
        CREDITED = "credited", "Moved to balance"
```

after the `refunded_by` field (its stamps also stamp a move, E-8), before `recorded_by`:

```python
    # B3e E-8: money the family put into the student's balance (a standalone
    # record). Both defaults (plan W5): a fresh instance reads False.
    wallet_topup = models.BooleanField(default=False, db_default=False)
```

and in `Meta.constraints`, after `billing_payment_has_customer`:

```python
            # B3e E-8: a wallet payment pays an invoice, with no fee; a top-up
            # is a student's standalone record, never paid from the wallet.
            models.CheckConstraint(
                condition=~Q(method="wallet")
                | (Q(invoice__isnull=False) & Q(fee_minor=0)),
                name="billing_payment_wallet_on_invoice",
            ),
            models.CheckConstraint(
                condition=Q(wallet_topup=False)
                | (
                    Q(invoice__isnull=True)
                    & Q(customer_type="student")
                    & ~Q(method="wallet")
                ),
                name="billing_payment_topup_standalone",
            ),
```

Run: `$DJ python manage.py makemigrations billing --name payment_wallet` (it writes `0009_payment_wallet.py`: the field, the two `AlterField`s for the choices and the two constraints; existing rows satisfy both checks).

`backend/etqan/billing/services/payments.py`: replace the two constants at the top

```python
# B3b B-9: methods only a provider's verified event records (and refunds).
ONLINE_METHODS = frozenset({Payment.Method.STRIPE, Payment.Method.PAYPAL})
# B3a §4.5: the manual methods, as (value, label) pairs, for the apps that
# take money the same ways (finance's donations extend them).
MANUAL_PAYMENT_METHODS = tuple(
    (value, label)
    for value, label in Payment.Method.choices
    if value not in ONLINE_METHODS
)
```

with

```python
# B3b B-9: methods only a provider's verified event records (and refunds).
ONLINE_METHODS = frozenset({Payment.Method.STRIPE, Payment.Method.PAYPAL})
# B3e E-8: paid from the student's balance, only by etqan.wallet.
WALLET = Payment.Method.WALLET
CREDITED = Payment.Status.CREDITED
NOT_MANUAL = ONLINE_METHODS | {WALLET}
# B3a §4.5: the manual methods, as (value, label) pairs, for the apps that
# take money the same ways (finance's donations extend them).
MANUAL_PAYMENT_METHODS = tuple(
    (value, label)
    for value, label in Payment.Method.choices
    if value not in NOT_MANUAL
)
# B3e plan W12: every method's English label (the wallet's statement notes).
METHOD_LABELS = dict(Payment.Method.choices)
```

`backend/etqan/billing/services/summary.py`, replace `revenue_between`:

```python
def revenue_between(first: date, following: date) -> list[dict]:
    """The one revenue query (B3a §4.5): payments with ``first <= paid_on <
    following``, their fee included (B3b B-9: the fee is money received),
    summed per currency, in currency order. B3g G-4: with or without an
    invoice, each in the payment's own currency. B3e E-7 (ledger D36): a
    payment moved into a wallet (`credited`) stays revenue; a payment from
    the wallet (method `wallet`) never is, since its money counted when it
    was topped up. Finance nets this month's expenses against it."""
    rows = (
        Payment.objects.filter(
            status__in=(Payment.Status.COMPLETED, Payment.Status.CREDITED),
            paid_on__gte=first,
            paid_on__lt=following,
        )
        .exclude(method=Payment.Method.WALLET)
        .values("currency")
        .annotate(amount_minor=Sum(F("amount_minor") + F("fee_minor")))
        .order_by("currency")
    )
    return [
        {"currency": row["currency"], "amount_minor": row["amount_minor"]}
        for row in rows
    ]
```

`backend/etqan/billing/services/__init__.py`: add `from etqan.billing.services.payments import METHOD_LABELS` (after the `MANUAL_PAYMENT_METHODS` import) and `"METHOD_LABELS",` to `__all__` (after `"MANUAL_PAYMENT_METHODS",`).

- [ ] **Step 4: Run, format, lint, commit**

Run: `$DJ pytest etqan/billing etqan/finance --create-db -q`
Expected: PASS, including `test_the_manual_payment_methods_are_the_payment_choices` (the pinned list is unchanged) and finance's `test_donation_methods_extend_billings_manual_methods`.
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/billing
git -C backend commit -m "feat(billing): the wallet method, credited payments, the top-up flag and revenue (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Billing: the wallet's services and the guards decided on the locked row

**Files:**
- Modify: `backend/etqan/billing/services/payments.py`, `backend/etqan/billing/services/records.py`, `backend/etqan/billing/services/online.py`, `backend/etqan/billing/services/__init__.py`, `backend/etqan/billing/tests/test_invoices.py` (the delete lock assertion, plan W18)
- Create: `backend/etqan/billing/tests/test_wallet_payments.py`

**Interfaces:**
- Consumes: Task 2's `WALLET`, `CREDITED`, `NOT_MANUAL`.
- Produces (all exported from `etqan.billing.services`):
  - `record_wallet_payment(invoice, *, amount_minor: int, by) -> Payment` — locks the invoice; 409 `billing.invoice_void`; 400 `amount_minor` over the balance; method `wallet`, fee 0, dated the academy's today;
  - `credit_payment(payment, *, by) -> Payment` — 400 `payment` without an invoice; locks the invoice, re-reads the payment `FOR UPDATE` (404 if gone); 409 `billing.payment_not_completed`; sets `credited` and the refund stamps; recalculates;
  - `record_topup_payment(*, student_profile_id, amount_minor, currency, method, by, fee_minor=0, paid_on=None, transaction_number="", reference="", notes="") -> Payment` — a `wallet_topup` standalone record (W7);
  - `refund_topup_payment(payment, *, by) -> Payment` — re-reads `FOR UPDATE`; 409 `billing.not_topup` / `billing.already_refunded`; sets `refunded`;
  - `invoice_for(user, invoice_id) -> Invoice` — from `invoices_queryset()`, scoped as the invoice route; 404 otherwise; staff need `invoice.view`;
  - `refuse_wallet_money(payment)` — 409 `billing.wallet_payment` / `billing.wallet_topup` / `billing.payment_credited`;
  - `delete_payment` and `refund_payment` decide on the re-read row; `update_record` refuses top-ups and credited payments (409 `billing.payment_not_editable`); `add_payment` and `create_record` refuse `wallet` (400 `method`).

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/billing/tests/test_wallet_payments.py`:

```python
"""B3e §4.1, E-9: billing's services for the wallet, and the guards that
keep wallet money out of billing's own refund, delete and edit, each
decided on the payment row re-read under its lock."""

import re
from datetime import date

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.billing import services
from etqan.billing.models import Payment
from etqan.billing.tests.conftest import make_parent
from etqan.billing.tests.test_invoices import invoice_for
from etqan.billing.tests.test_invoices import pay
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

JUNE_1 = date(2026, 6, 1)


def topup(world, admin, amount=5000, **fields):
    values = {
        "student_profile_id": identity_services.get_student_profile(world.student.pk).pk,
        "amount_minor": amount,
        "currency": "EGP",
        "method": "cash",
        "by": admin,
        **fields,
    }
    return services.record_topup_payment(**values)


def locked_tables(action) -> list[str]:
    """The tables ``action`` locks, in order (plan W10)."""
    with CaptureQueriesContext(connection) as ctx:
        action()
    return [
        re.search(r'FROM "(\w+)"', q["sql"]).group(1)
        for q in ctx.captured_queries
        if "FOR UPDATE" in q["sql"]
    ]


def status(invoice) -> str:
    return services.invoices_queryset().get(pk=invoice.pk).status


def test_a_wallet_payment_pays_dated_today_with_no_fee(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000)
    payment = services.record_wallet_payment(bill, amount_minor=400, by=admin)
    assert (
        payment.method,
        payment.fee_minor,
        payment.paid_on,
        payment.recorded_by,
        payment.currency,
    ) == ("wallet", 0, JUNE_1, admin, bill.currency)
    assert status(bill) == "partial"
    with pytest.raises(ValidationError) as over:
        services.record_wallet_payment(bill, amount_minor=601, by=admin)
    assert over.value.field == "amount_minor"
    void = invoice_for(world, admin)
    services.void_invoice(void, by=admin)
    with pytest.raises(ConflictError) as refused:
        services.record_wallet_payment(void, amount_minor=1, by=admin)
    assert refused.value.code == "billing.invoice_void"


def test_a_moved_payment_is_credited_and_its_invoice_reopens(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000)
    cash = pay(bill, admin, 1000)
    assert status(bill) == "paid"
    moved = services.credit_payment(cash, by=admin)
    assert (moved.status, moved.refunded_by) == ("credited", admin)
    assert moved.refunded_at is not None
    assert status(bill) == "unpaid"
    with pytest.raises(ConflictError) as again:
        services.credit_payment(cash, by=admin)
    assert again.value.code == "billing.payment_not_completed"
    record = services.create_record(
        customer_type="unregistered",
        customer_name="Abu Khalid",
        amount_minor=100,
        method="cash",
        by=admin,
    )
    with pytest.raises(ValidationError) as standalone:
        services.credit_payment(record, by=admin)
    assert standalone.value.field == "payment"


def test_crediting_and_deleting_lock_the_invoice_then_the_payment(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000)
    first, second = pay(bill, admin, 300), pay(bill, admin, 300)
    assert locked_tables(lambda: services.credit_payment(first, by=admin)) == [
        "billing_invoice",
        "billing_payment",
    ]
    assert locked_tables(lambda: services.delete_payment(second)) == [
        "billing_invoice",
        "billing_payment",
    ]
    with pytest.raises(NotFoundError):
        services.delete_payment(second)


def test_a_manual_top_up_is_a_students_standalone_record(world, admin):
    payment = topup(world, admin, reference="R-1", paid_on=date(2026, 5, 30))
    assert (
        payment.invoice_id,
        payment.customer_type,
        payment.student.user_id,
        payment.wallet_topup,
        payment.method,
        payment.paid_on,
        payment.recorded_by,
        payment.fee_minor,
        payment.reference,
    ) == (None, "student", world.student.pk, True, "cash", date(2026, 5, 30), admin, 0, "R-1")
    assert topup(world, admin).paid_on == JUNE_1  # no date: the academy's today
    assert topup(world, admin, by=None).recorded_by is None  # the seeds (W7)
    # E-14: no active_student; a deactivated student keeps receiving.
    identity_services.deactivate(world.student, by=admin)
    assert topup(world, admin).wallet_topup is True


@pytest.mark.parametrize(
    ("fields", "field"),
    [
        ({"method": "wallet"}, "method"),
        ({"method": "bitcoin"}, "method"),
        ({"paid_on": date(2026, 6, 2)}, "paid_on"),
        ({"currency": "EG"}, "currency"),
        ({"fee_minor": 10}, "fee_minor"),
        ({"amount_minor": 0}, "amount_minor"),
    ],
)
def test_a_bad_top_up_is_a_400(world, admin, fields, field):
    with pytest.raises(ValidationError) as caught:
        topup(world, admin, **fields)
    assert caught.value.field == field
    assert not Payment.objects.filter(wallet_topup=True).exists()


def test_an_online_top_up_is_dated_today_by_nobody_with_its_fee(world, admin):
    online = topup(
        world,
        admin,
        method="stripe",
        fee_minor=250,
        transaction_number="pi_1",
        paid_on=date(2026, 5, 1),
    )
    assert (online.paid_on, online.recorded_by, online.fee_minor) == (JUNE_1, None, 250)
    with pytest.raises(ValidationError) as twice:
        topup(world, admin, method="stripe", transaction_number="pi_1")
    assert twice.value.field == "transaction_number"


def test_a_top_up_is_refunded_once_and_only_a_top_up(world, admin):
    top = topup(world, admin)
    refunded = services.refund_topup_payment(top, by=admin)
    assert (refunded.status, refunded.refunded_by) == ("refunded", admin)
    with pytest.raises(ConflictError) as again:
        services.refund_topup_payment(top, by=admin)
    assert again.value.code == "billing.already_refunded"
    bill = invoice_for(world, admin, amount_minor=1000)
    with pytest.raises(ConflictError) as other:
        services.refund_topup_payment(pay(bill, admin, 100), by=admin)
    assert other.value.code == "billing.not_topup"


def test_billing_never_undoes_wallet_money_deciding_on_the_locked_row(world, admin):
    """E-9 (review C1): each guard reads the fresh row, never the caller's."""
    bill = invoice_for(world, admin, amount_minor=5000)
    spent = services.record_wallet_payment(bill, amount_minor=500, by=admin)
    top = topup(world, admin)
    cash = pay(bill, admin, 1000)
    stale = Payment.objects.select_related("invoice").get(pk=cash.pk)
    services.credit_payment(cash, by=admin)  # moved after `stale` was read
    cases = [(spent, "billing.wallet_payment"), (top, "billing.wallet_topup")]
    cases.append((stale, "billing.payment_credited"))
    for payment, code in cases:
        for action in (
            lambda p=payment: services.delete_payment(p),
            lambda p=payment: services.refund_payment(p, by=admin),
        ):
            with pytest.raises(ConflictError) as refused:
                action()
            assert refused.value.code == code
    with pytest.raises(ConflictError) as edit:
        services.update_record(top, reference="X")
    assert edit.value.code == "billing.payment_not_editable"
    statuses = Payment.objects.filter(pk__in=[spent.pk, top.pk, cash.pk])
    assert sorted(statuses.values_list("status", flat=True)) == [
        "completed",
        "completed",
        "credited",
    ]


def test_add_payment_and_create_record_refuse_the_wallet_method(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000)
    with pytest.raises(ValidationError) as on_invoice:
        pay(bill, admin, 100, method="wallet")
    assert on_invoice.value.field == "method"
    with pytest.raises(ValidationError) as standalone:
        services.create_record(
            customer_type="unregistered",
            customer_name="Abu Khalid",
            amount_minor=100,
            method="wallet",
            by=admin,
        )
    assert standalone.value.field == "method"


def test_invoice_for_reads_as_the_invoice_route_scopes(world, admin, staff_for):
    bill = invoice_for(world, admin)
    parent = make_parent("Zainab", world.student)
    assert services.invoice_for(parent, bill.pk).pk == bill.pk
    assert services.invoice_for(admin, bill.pk).balance_minor == bill.amount_minor
    assert services.invoice_for(staff_for("invoice.view").user, bill.pk).pk == bill.pk
    for reader in (make_parent("Huda"), staff_for("invoice.view_any").user):
        with pytest.raises(NotFoundError):
            services.invoice_for(reader, bill.pk)
    with pytest.raises(NotFoundError):
        services.invoice_for(admin, 999999)
```

`backend/etqan/billing/tests/test_invoices.py`, in `test_every_write_locks_the_invoice_row_first`, replace

```python
    assert [s for s in sql if "FOR UPDATE" in s] == [sql[0]]
```

with

```python
    locks = [s for s in sql if "FOR UPDATE" in s]
    if write == "delete":
        # B3e E-9 (plan W18): then the payment row itself, re-read under
        # its own lock before anything is decided.
        assert locks[0] == sql[0]
        assert len(locks) == 2 and 'FROM "billing_payment"' in locks[1]
    else:
        assert locks == [sql[0]]
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/billing/tests/test_wallet_payments.py etqan/billing/tests/test_invoices.py -q`
Expected: FAIL (`AttributeError: record_wallet_payment`, …; the delete case asserts two locks).

- [ ] **Step 3: Implement the services and the guards**

`backend/etqan/billing/services/payments.py`:

In `add_payment`, after the `ONLINE_METHODS` refusal:

```python
    if method == WALLET:
        raise ValidationError(
            "A payment from the balance is made from the balance.", field="method"
        )
```

Add, before `record_online_payment`:

```python
def refuse_wallet_money(payment: Payment) -> None:
    """B3e E-9: only etqan.wallet undoes wallet money. ``payment`` is the
    fresh row read under its lock, never the caller's copy (review C1). The
    refusals stand while `balances` is off: those payments freeze."""
    if payment.method == WALLET:
        raise ConflictError(
            "A payment from the balance is moved back to the balance, "
            "not refunded or deleted.",
            code="billing.wallet_payment",
        )
    if payment.wallet_topup:
        raise ConflictError(
            "A balance top-up is reversed from the balance, not refunded or deleted.",
            code="billing.wallet_topup",
        )
    if payment.status == CREDITED:
        raise ConflictError(
            "This payment was moved to the balance.", code="billing.payment_credited"
        )


def _locked_payment(payment: Payment) -> Payment:
    fresh = Payment.objects.select_for_update().filter(pk=payment.pk).first()
    if fresh is None:
        raise NotFoundError("Payment", payment.pk)
    return fresh


def _stamp(fresh: Payment, status: str, by) -> None:
    """A refund's or a move's status and stamps (E-8)."""
    fresh.status = status
    fresh.refunded_at = clock.now()
    fresh.refunded_by = by
    fresh.save(update_fields=["status", "refunded_at", "refunded_by"])


@transaction.atomic
def record_wallet_payment(invoice: Invoice, *, amount_minor: int, by) -> Payment:
    """B3e §4.1, E-11: a payment from the student's balance, dated the
    academy's today, with no fee. The void and balance rules are checked
    again here, under the invoice lock."""
    locked = rules.lock(invoice)
    rules.refuse_if_void(locked)
    rules.refuse_if_over_balance(locked, amount_minor)
    payment = Payment(
        invoice=locked,
        currency=locked.currency,
        amount_minor=amount_minor,
        method=WALLET,
        paid_on=clock.today(),
        recorded_by=by,
    )
    rules.save(payment)
    _recalculate(locked)
    return payment


@transaction.atomic
def credit_payment(payment: Payment, *, by) -> Payment:
    """B3e E-12: a completed invoice payment moved into the student's
    balance. It stops counting toward the invoice but stays revenue (E-7).
    Billing's lock order: the invoice, then the payment re-read."""
    if payment.invoice_id is None:
        raise ValidationError(
            "Only an invoice's payment is moved to the balance.", field="payment"
        )
    locked = rules.lock(payment.invoice)
    fresh = _locked_payment(payment)
    if fresh.status != Payment.Status.COMPLETED:
        raise ConflictError(
            "Only a completed payment is moved to the balance.",
            code="billing.payment_not_completed",
        )
    _stamp(fresh, CREDITED, by)
    _recalculate(locked)
    return fresh


@transaction.atomic
def refund_topup_payment(payment: Payment, *, by) -> Payment:
    """B3e E-13: a reversed top-up leaves revenue with its fee (E-7)."""
    fresh = _locked_payment(payment)
    if not fresh.wallet_topup:
        raise ConflictError("This is not a balance top-up.", code="billing.not_topup")
    if fresh.status != Payment.Status.COMPLETED:
        raise ConflictError(
            "This payment is already refunded.", code="billing.already_refunded"
        )
    _stamp(fresh, Payment.Status.REFUNDED, by)
    return fresh
```

Replace `refund_payment` and `delete_payment`:

```python
@transaction.atomic
def refund_payment(payment: Payment, *, by) -> Payment:
    """Marked, not executed (phase B3-10): the payment stops counting and the
    invoice's status follows. A void invoice has no completed payments, so a
    refund can never reach one. A standalone record (B3g G-3) has no invoice:
    only its own row is locked and nothing is recalculated. B3e E-9: wallet
    money is refused, on the fresh row."""
    locked = rules.lock(payment.invoice) if payment.invoice_id else None
    fresh = _locked_payment(payment)
    refuse_wallet_money(fresh)
    if fresh.status == Payment.Status.REFUNDED:
        raise ConflictError(
            "This payment is already refunded.", code="billing.already_refunded"
        )
    _stamp(fresh, Payment.Status.REFUNDED, by)
    if locked is not None:
        _recalculate(locked)
    return fresh


@transaction.atomic
def delete_payment(payment: Payment) -> None:
    """For mistakes (spec §4.2). An invoice payment locks its invoice first, as
    when paying, then (B3e E-9) re-reads the payment under its own lock and
    decides on that row; a standalone record has no invoice (B3g G-2)."""
    locked = rules.lock(payment.invoice) if payment.invoice_id else None
    fresh = _locked_payment(payment)
    refuse_wallet_money(fresh)
    if fresh.method in ONLINE_METHODS:
        raise ConflictError(
            "An online payment is refunded, never deleted.",
            code="billing.online_payment",
        )
    fresh.delete()
    if locked is not None:
        _recalculate(locked)
```

`backend/etqan/billing/services/records.py`:

In `update_record`, replace the refusal condition and its docstring:

```python
@transaction.atomic
def update_record(payment: Payment, **changes) -> Payment:
    """G-2: a manual standalone record that is not refunded only; anything
    else is a 409 ``billing.payment_not_editable``. B3e E-9: nor a top-up
    or a payment moved to the balance (decided on the locked row)."""
    fresh = Payment.objects.select_for_update().filter(pk=payment.pk).first()
    if fresh is None:
        raise NotFoundError("Payment", payment.pk)
    if (
        fresh.invoice_id is not None
        or fresh.method in ONLINE_METHODS
        or fresh.status != Payment.Status.COMPLETED
        or fresh.wallet_topup
    ):
        raise ConflictError(
            "Only a manual, unrefunded payment record without an invoice is edited.",
            code="billing.payment_not_editable",
        )
```

(the rest of `update_record` is unchanged; `status != COMPLETED` covers refunded and credited.)

Append:

```python
@transaction.atomic
def record_topup_payment(  # noqa: PLR0913 -- keyword-only; one top-up's columns (B3e §4.1)
    *,
    student_profile_id: int,
    amount_minor: int,
    currency: str,
    method: str,
    by,
    fee_minor: int = 0,
    paid_on: date | None = None,
    transaction_number: str = "",
    reference: str = "",
    notes: str = "",
) -> Payment:
    """B3e E-14, E-16: money put into a student's balance, a standalone
    record flagged ``wallet_topup``. A manual method is recorded by ``by``
    (None for the seeds, plan W7) on ``paid_on`` (not in the future), with
    no fee; an online one is dated the academy's today, recorded by nobody,
    with its fee. No `active_student`: a deactivated student keeps a wallet."""
    online = method in ONLINE_METHODS
    if not online:
        _check_method(method)
        if fee_minor:
            raise ValidationError(
                "Only an online payment carries a fee.", field="fee_minor"
            )
    _check_amount(amount_minor)
    paid_on = clock.today() if online or paid_on is None else paid_on
    _check_date(paid_on)
    code = clean_currency(currency, field="currency")
    _check_unique(method, transaction_number)
    payment = Payment(
        invoice=None,
        customer_type=STUDENT,
        student_id=student_profile_id,
        amount_minor=amount_minor,
        fee_minor=fee_minor,
        currency=code,
        method=method,
        transaction_number=transaction_number,
        reference=reference,
        paid_on=paid_on,
        notes=notes,
        recorded_by=None if online else by,
        wallet_topup=True,
    )
    _save(payment)
    return payment
```

(`_check_method` reads `MANUAL`, which leaves out `wallet` since Task 2, so `create_record` already refuses it.)

`backend/etqan/billing/services/online.py`: replace `_readable` with the public `invoice_for` (argument order per spec §4.1) and call it from `prepare`:

```python
def invoice_for(user, invoice_id: int) -> Invoice:
    """B-14; public since B3e (the wallet's pay route): the invoice ``user``
    may read, as billing scopes it, from `invoices_queryset()`; staff need
    the invoice code itself, not just an office account. 404 otherwise."""
    if role_of(user) == "staff" and "invoice.view" not in codes_of(user):
        raise NotFoundError("Invoice", invoice_id)
    invoice = scope_for(user, rules.invoices_queryset()).filter(pk=invoice_id).first()
    if invoice is None:
        raise NotFoundError("Invoice", invoice_id)
    return invoice


def prepare(reference_id: int, user, params: dict | None) -> gateways_services.Prepared:
    invoice = invoice_for(user, reference_id)
```

(the rest of `prepare` is unchanged.)

`backend/etqan/billing/services/__init__.py`: add the imports, each in its alphabetical place,

```python
from etqan.billing.services.online import invoice_for
from etqan.billing.services.payments import credit_payment
from etqan.billing.services.payments import record_wallet_payment
from etqan.billing.services.payments import refund_topup_payment
from etqan.billing.services.payments import refuse_wallet_money
from etqan.billing.services.records import record_topup_payment
```

and `"credit_payment"`, `"invoice_for"`, `"record_topup_payment"`, `"record_wallet_payment"`, `"refund_topup_payment"`, `"refuse_wallet_money"` to `__all__` (sorted; ruff's `RUF022` keeps it sorted).

- [ ] **Step 4: Run, format, lint, commit**

Run: `$DJ pytest etqan/billing etqan/gateways etqan/finance -q`
Expected: PASS (the gateways invoice purpose still reads through `invoice_for`; `test_records`, `test_refunds` and `test_standalone` unchanged).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/billing
git -C backend commit -m "feat(billing): wallet payments, moves and top-ups; guards decided on the locked row (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Billing: the payment-row flags and the credited filter

**Files:**
- Modify: `backend/etqan/billing/api/payloads.py`
- Test: `backend/etqan/billing/tests/test_wallet_payments.py` (append)

**Interfaces:**
- Consumes: Task 3's services.
- Produces: every payment row (invoice detail, payments list, records list, a record) carries `editable`, `deletable`, `refundable`, `wallet_topup`, computed on the server (E-10); the records list's `?status=credited` filters moved payments (the serializer reads `Payment.Status.choices`, so no serializer change).

- [ ] **Step 1: Write the failing tests**

In `backend/etqan/billing/tests/test_wallet_payments.py`, add `from etqan.billing.api import payloads` to the import block (after `from etqan.billing import services`), then append:

```python
def flags(payment) -> tuple:
    row = payloads.payment_row(
        services.payments_queryset().get(pk=payment.pk), is_admin=True
    )
    return (row["editable"], row["deletable"], row["refundable"], row["wallet_topup"])


def test_the_row_flags_follow_e10(world, admin):
    bill = invoice_for(world, admin, amount_minor=5000)
    cash = pay(bill, admin, 1000)
    assert flags(cash) == (False, True, True, False)
    spent = services.record_wallet_payment(bill, amount_minor=500, by=admin)
    assert flags(spent) == (False, False, False, False)
    services.credit_payment(cash, by=admin)
    assert flags(cash) == (False, False, False, False)
    top = topup(world, admin)
    assert flags(top) == (False, False, False, True)
    services.refund_topup_payment(top, by=admin)
    assert flags(top) == (False, False, False, True)
    record = services.create_record(
        customer_type="unregistered",
        customer_name="Abu Khalid",
        amount_minor=1000,
        method="cash",
        by=admin,
    )
    assert flags(record) == (True, True, True, False)
    card = services.record_online_payment(
        bill, amount_minor=500, fee_minor=25, method="stripe", transaction_number="pi_f"
    )
    assert flags(card) == (False, False, True, False)
    services.refund_payment(card, by=admin)
    assert flags(card) == (False, False, False, False)


def test_the_records_list_filters_moved_payments(api_for, set_features, world, admin):
    set_features(invoices=True, payment_receipts=True)
    bill = invoice_for(world, admin, amount_minor=1000)
    cash, other = pay(bill, admin, 300), pay(bill, admin, 300)
    services.credit_payment(cash, by=admin)
    resp = api_for("admin").get("/api/v1/billing/payments/", {"status": "credited"})
    assert resp.status_code == 200
    assert [row["id"] for row in resp.json()["results"]] == [cash.pk]
    assert resp.json()["results"][0]["status"] == "credited"
    assert other.pk not in [row["id"] for row in resp.json()["results"]]
    bad = api_for("admin").get("/api/v1/billing/payments/", {"status": "moved"})
    assert bad.status_code == 400
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/billing/tests/test_wallet_payments.py -q -k "flags or moved"`
Expected: FAIL (`KeyError: 'refundable'`).

- [ ] **Step 3: Implement the flags**

`backend/etqan/billing/api/payloads.py`: replace the import line with

```python
from etqan.billing.services.payments import CREDITED
from etqan.billing.services.payments import ONLINE_METHODS
from etqan.billing.services.payments import WALLET
```

and replace `payment_row`:

```python
def payment_row(payment, *, is_admin: bool) -> dict:
    invoice = payment.invoice
    online = payment.method in ONLINE_METHODS
    from_wallet = payment.method == WALLET
    top_up = payment.wallet_topup
    credited = payment.status == CREDITED
    row = {
        "id": payment.pk,
        "customer": _customer(payment),
        "invoice": (
            None if invoice is None else {"id": invoice.pk, "number": invoice.number}
        ),
        "transaction_number": payment.transaction_number,
        "reference": payment.reference,
        "method": payment.method,
        "amount_minor": payment.amount_minor,
        "fee_minor": payment.fee_minor,
        "currency": payment.currency,
        "status": payment.status,
        "paid_on": payment.paid_on,
        # B3e E-8: a move stamps it too; the dashboard labels it by status.
        "refunded_at": payment.refunded_at,
        "created_at": payment.created_at,
        "notes": payment.notes,
        "recorded_by": _person(payment.recorded_by),
        "wallet_topup": top_up,
        # G-2, B3e E-10: computed here; no page re-derives them from `method`.
        "editable": not online
        and payment.invoice_id is None
        and payment.status == "completed"
        and not top_up,
        "deletable": not (online or from_wallet or top_up or credited),
        "refundable": payment.status == "completed" and not from_wallet and not top_up,
    }
    if not is_admin:
        for field in STAFF_ONLY_PAYMENT_FIELDS:
            row.pop(field)
    return row
```

- [ ] **Step 4: Run, format, lint, commit**

Run: `$DJ pytest etqan/billing -q`
Expected: PASS (`test_standalone` and `test_records` keep their `editable`/`deletable` expectations).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/billing
git -C backend commit -m "feat(billing): payment rows carry editable, deletable, refundable and wallet_topup (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 5: Wallet services: the ledger, office top-ups, adjustments and reads

**Files:**
- Create: `backend/etqan/wallet/services/reads.py`, `backend/etqan/wallet/services/ledger.py`, `backend/etqan/wallet/tests/test_ledger.py`
- Modify: `backend/etqan/wallet/services/__init__.py`

**Interfaces:**
- Consumes: Task 1's models; Task 3's `billing.services.record_topup_payment`, `MANUAL_PAYMENT_METHODS`, `METHOD_LABELS`; `identity.services.get_student_profile`; `platform.validators.clean_currency`.
- Produces (exported from `etqan.wallet.services`):
  - `Balance(currency: str, balance_minor: int)` (frozen dataclass); `balances_of(student_user_id: int) -> list[Balance]` (by currency; D37);
  - `entries_of(student_user_id: int, currency: str | None = None) -> QuerySet[WalletEntry]` (newest first, `wallet` and `created_by` joined, annotated `reversed`);
  - `student_of(student_user_id: int) -> dict` (`{"id", "name"}`; `NotFoundError` when no student profile);
  - `top_up(student_user_id, *, amount_minor, currency, method, by, paid_on=None, reference="") -> WalletEntry`;
  - `adjust(student_user_id, *, amount_minor, currency, reason, by) -> WalletEntry`;
  - in `ledger`: `INSUFFICIENT = "wallet.insufficient_balance"`, `insufficient() -> ConflictError`, `profile_of(student_user_id)`, `check_amount(value) -> int`, `lock_wallet(student_profile_id, currency, *, create: bool) -> Wallet | None`, `write(wallet, *, kind, amount_minor, by, note="", **links) -> WalletEntry`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/wallet/tests/test_ledger.py`:

```python
"""B3e §4.2, E-3, E-4, E-14, E-19: office top-ups, adjustments, the ledger's
invariants and the reads by student."""

from datetime import date

import pytest

from etqan.billing.models import Payment
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.wallet import services
from etqan.wallet.models import MAX_TOPUP_MINOR
from etqan.wallet.models import Wallet
from etqan.wallet.models import WalletEntry
from etqan.wallet.tests.conftest import ledger_holds

pytestmark = pytest.mark.django_db


def cash(world, admin, amount=30000, currency="EGP", **fields):
    values = {
        "amount_minor": amount,
        "currency": currency,
        "method": "cash",
        "by": admin,
        **fields,
    }
    return services.top_up(world.student.id, **values)


def adjust(world, admin, amount, currency="EGP", reason="Typo"):
    return services.adjust(
        world.student.id,
        amount_minor=amount,
        currency=currency,
        reason=reason,
        by=admin,
    )


def test_a_cash_top_up_records_its_payment_and_its_entry(world, admin):
    entry = cash(world, admin, reference="R-7", paid_on=date(2026, 5, 31))
    payment = Payment.objects.get(pk=entry.payment_id)
    assert (
        entry.kind,
        entry.amount_minor,
        entry.balance_after_minor,
        entry.note,
        entry.created_by,
    ) == ("topup", 30000, 30000, "Cash · R-7", admin)
    assert (
        payment.wallet_topup,
        payment.invoice_id,
        payment.method,
        payment.paid_on,
        payment.recorded_by,
        payment.amount_minor,
        payment.currency,
    ) == (True, None, "cash", date(2026, 5, 31), admin, 30000, "EGP")
    assert cash(world, admin, 500).note == "Cash"
    assert services.balances_of(world.student.id) == [services.Balance("EGP", 30500)]
    ledger_holds(world.student.id)


def test_a_deactivated_student_keeps_a_wallet(world, admin):
    identity_services.deactivate(world.student, by=admin)
    cash(world, admin, 1000)
    assert services.balances_of(world.student.id) == [services.Balance("EGP", 1000)]


def test_the_cap_and_a_lowercase_currency_are_taken(world, admin):
    entry = cash(world, admin, MAX_TOPUP_MINOR, currency="usd")
    assert (entry.wallet.currency, entry.amount_minor) == ("USD", MAX_TOPUP_MINOR)


@pytest.mark.parametrize(
    ("fields", "field"),
    [
        ({"amount": 0}, "amount_minor"),
        ({"amount": -5}, "amount_minor"),
        ({"amount": MAX_TOPUP_MINOR + 1}, "amount_minor"),
        ({"amount": "100"}, "amount_minor"),
        ({"amount": True}, "amount_minor"),
        ({"amount": 1.5}, "amount_minor"),
        ({"currency": "EG"}, "currency"),
        ({"currency": None}, "currency"),
        ({"method": "stripe"}, "method"),
        ({"method": "wallet"}, "method"),
        ({"paid_on": date(2026, 6, 2)}, "paid_on"),
    ],
)
def test_a_bad_top_up_is_a_400_and_writes_nothing(world, admin, fields, field):
    with pytest.raises(ValidationError) as caught:
        cash(world, admin, **fields)
    assert caught.value.field == field
    assert not WalletEntry.objects.exists()
    assert not Wallet.objects.exists()
    assert not Payment.objects.filter(wallet_topup=True).exists()


def test_an_unknown_student_is_404(admin):
    with pytest.raises(NotFoundError):
        services.top_up(
            999999, amount_minor=100, currency="EGP", method="cash", by=admin
        )
    with pytest.raises(NotFoundError):
        services.student_of(999999)


def test_an_adjustment_needs_a_reason_and_a_debit_needs_the_balance(world, admin):
    cash(world, admin, 1000)
    plus = adjust(world, admin, 500, reason="  Welcome credit ")
    assert (plus.kind, plus.amount_minor, plus.balance_after_minor, plus.note) == (
        "adjustment",
        500,
        1500,
        "Welcome credit",
    )
    assert adjust(world, admin, -1500).balance_after_minor == 0
    with pytest.raises(ConflictError) as short:
        adjust(world, admin, -1)
    assert short.value.code == "wallet.insufficient_balance"
    # Plan W8: a debit never creates an empty wallet.
    with pytest.raises(ConflictError):
        adjust(world, admin, -1, currency="SAR")
    assert not Wallet.objects.filter(currency="SAR").exists()
    assert adjust(world, admin, 700, currency="SAR").wallet.currency == "SAR"
    ledger_holds(world.student.id)


@pytest.mark.parametrize(
    ("amount", "reason", "field"),
    [
        (0, "x", "amount_minor"),
        (MAX_TOPUP_MINOR + 1, "x", "amount_minor"),
        (-(MAX_TOPUP_MINOR + 1), "x", "amount_minor"),
        ("5", "x", "amount_minor"),
        (False, "x", "amount_minor"),
        (5, "", "reason"),
        (5, "   ", "reason"),
        (5, "x" * 501, "reason"),
        (5, None, "reason"),
    ],
)
def test_a_bad_adjustment_is_a_400(world, admin, amount, reason, field):
    with pytest.raises(ValidationError) as caught:
        adjust(world, admin, amount, reason=reason)
    assert caught.value.field == field
    assert not WalletEntry.objects.exists()


def test_entries_read_newest_first_and_by_currency(world, admin):
    cash(world, admin, 100)
    cash(world, admin, 200, currency="USD")
    adjust(world, admin, 5, reason="Rounding")
    entries = services.entries_of(world.student.id)
    assert [(e.kind, e.wallet.currency, e.reversed) for e in entries] == [
        ("adjustment", "EGP", False),
        ("topup", "USD", False),
        ("topup", "EGP", False),
    ]
    assert [e.amount_minor for e in services.entries_of(world.student.id, "USD")] == [200]
    assert services.balances_of(world.student.id) == [
        services.Balance("EGP", 105),
        services.Balance("USD", 200),
    ]
    assert services.student_of(world.student.id) == {
        "id": world.student.id,
        "name": "Yusuf",
    }


def test_a_student_with_no_wallet_reads_empty(world):
    assert services.balances_of(world.student.id) == []
    assert not services.entries_of(world.student.id).exists()
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/wallet/tests/test_ledger.py -q`
Expected: FAIL (`AttributeError: module 'etqan.wallet.services' has no attribute 'top_up'`).

- [ ] **Step 3: Implement the reads and the ledger**

Create `backend/etqan/wallet/services/reads.py`:

```python
"""What the wallet reads (B3e §4.2). Later phases read balances only
through `balances_of` (ledger D37)."""

from dataclasses import dataclass

from django.db.models import Exists
from django.db.models import OuterRef
from django.db.models import QuerySet

from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError
from etqan.wallet.models import Wallet
from etqan.wallet.models import WalletEntry


@dataclass(frozen=True)
class Balance:
    currency: str
    balance_minor: int


def balances_of(student_user_id: int) -> list[Balance]:
    """One balance per currency the student holds, by currency (D37)."""
    wallets = Wallet.objects.filter(student__user_id=student_user_id).order_by(
        "currency"
    )
    return [Balance(w.currency, w.balance_minor) for w in wallets]


def entries_of(
    student_user_id: int, currency: str | None = None
) -> QuerySet[WalletEntry]:
    """The statement, newest first; ``reversed`` marks a top-up already given
    back (plan W13)."""
    reversal = WalletEntry.objects.filter(
        kind=WalletEntry.Kind.REVERSAL, payment_id=OuterRef("payment_id")
    )
    entries = (
        WalletEntry.objects.filter(wallet__student__user_id=student_user_id)
        .select_related("wallet", "created_by")
        .annotate(reversed=Exists(reversal))
        .order_by("-id")
    )
    if currency:
        entries = entries.filter(wallet__currency=currency)
    return entries


def student_of(student_user_id: int) -> dict:
    """The student as wallet payloads name them; 404 for anyone else (W15)."""
    profile = identity_services.get_student_profile(student_user_id)
    if profile is None:
        raise NotFoundError("Student", student_user_id)
    return {"id": profile.user_id, "name": profile.user.full_name}
```

Create `backend/etqan/wallet/services/ledger.py`:

```python
"""The wallet's writes (B3e §4.2). Each is one transaction that locks its
wallet row (E-6), reads the balance fresh after the lock and appends one
entry; the cache moves in the same transaction (E-3). There is no write
that edits or deletes an entry."""

from datetime import date

from django.db import transaction

from etqan.billing import services as billing_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency
from etqan.wallet.models import MAX_TOPUP_MINOR
from etqan.wallet.models import Wallet
from etqan.wallet.models import WalletEntry

Kind = WalletEntry.Kind
INSUFFICIENT = "wallet.insufficient_balance"
REASON_LENGTH = 500
MANUAL = frozenset(value for value, _ in billing_services.MANUAL_PAYMENT_METHODS)


def insufficient() -> ConflictError:
    return ConflictError("The balance does not cover this.", code=INSUFFICIENT)


def profile_of(student_user_id: int):
    profile = identity_services.get_student_profile(student_user_id)
    if profile is None:
        raise NotFoundError("Student", student_user_id)
    return profile


def _is_int(value) -> bool:
    # A bool is an int in Python; a JSON true is not an amount.
    return isinstance(value, int) and not isinstance(value, bool)


def check_amount(value) -> int:
    """E-19: 1 to 100,000,000 minor units."""
    if not _is_int(value) or not 1 <= value <= MAX_TOPUP_MINOR:
        raise ValidationError(
            f"Enter an amount from 1 to {MAX_TOPUP_MINOR} minor units.",
            field="amount_minor",
        )
    return value


def lock_wallet(student_profile_id: int, currency: str, *, create: bool) -> Wallet | None:
    """E-6: the (student, currency) row, `SELECT … FOR UPDATE`, read fresh.
    A credit creates it first (the unique constraint settles a race); a
    debit never creates an empty one (plan W8): None means nothing to spend."""
    if create:
        Wallet.objects.get_or_create(student_id=student_profile_id, currency=currency)
    return (
        Wallet.objects.select_for_update()
        .filter(student_id=student_profile_id, currency=currency)
        .first()
    )


def write(  # noqa: PLR0913 -- keyword-only; one entry's columns
    wallet: Wallet, *, kind: str, amount_minor: int, by, note: str = "", **links
) -> WalletEntry:
    """Appends one entry to the locked ``wallet`` and moves its cache. A debit
    beyond the fresh balance is 409; the CHECKs are the last guard (E-6)."""
    balance = wallet.balance_minor + amount_minor
    if balance < 0:
        raise insufficient()
    entry = WalletEntry.objects.create(
        wallet=wallet,
        kind=kind,
        amount_minor=amount_minor,
        balance_after_minor=balance,
        note=note[:REASON_LENGTH],
        created_by=by,
        **links,
    )
    wallet.balance_minor = balance
    wallet.save(update_fields=["balance_minor", "updated_at"])
    return entry


@transaction.atomic
def top_up(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)
    student_user_id: int,
    *,
    amount_minor: int,
    currency: str,
    method: str,
    by,
    paid_on: date | None = None,
    reference: str = "",
) -> WalletEntry:
    """E-14: the office's manual top-up: a `wallet_topup` payment and a
    `topup` entry, in one transaction. A deactivated student is fine."""
    profile = profile_of(student_user_id)
    check_amount(amount_minor)
    code = clean_currency(currency or "", field="currency")
    if method not in MANUAL:
        raise ValidationError("Choose a manual payment method.", field="method")
    wallet = lock_wallet(profile.pk, code, create=True)
    payment = billing_services.record_topup_payment(
        student_profile_id=profile.pk,
        amount_minor=amount_minor,
        currency=code,
        method=method,
        by=by,
        paid_on=paid_on,
        reference=reference,
    )
    label = billing_services.METHOD_LABELS.get(method, method)
    note = f"{label} · {reference}" if reference else label
    return write(
        wallet,
        kind=Kind.TOPUP,
        amount_minor=amount_minor,
        by=by,
        note=note,
        payment_id=payment.pk,
    )


@transaction.atomic
def adjust(
    student_user_id: int, *, amount_minor: int, currency: str, reason: str, by
) -> WalletEntry:
    """E-4, E-5: a correction, never money in or out (no payment, never
    revenue). A negative amount must be covered by the balance (W11)."""
    profile = profile_of(student_user_id)
    if (
        not _is_int(amount_minor)
        or amount_minor == 0
        or abs(amount_minor) > MAX_TOPUP_MINOR
    ):
        raise ValidationError(
            f"Enter an amount other than 0, up to {MAX_TOPUP_MINOR} minor units.",
            field="amount_minor",
        )
    text = (reason or "").strip()
    if not text or len(text) > REASON_LENGTH:
        raise ValidationError(
            "Give a reason of 1 to 500 characters.", field="reason"
        )
    code = clean_currency(currency or "", field="currency")
    wallet = lock_wallet(profile.pk, code, create=amount_minor > 0)
    if wallet is None:
        raise insufficient()
    return write(
        wallet, kind=Kind.ADJUSTMENT, amount_minor=amount_minor, by=by, note=text
    )
```

Replace `backend/etqan/wallet/services/__init__.py`:

```python
"""Public API of the wallet module (B3e). Other apps import only this
package; later phases read balances only through `balances_of` (D37)."""

from etqan.wallet.services.ledger import adjust
from etqan.wallet.services.ledger import top_up
from etqan.wallet.services.reads import Balance
from etqan.wallet.services.reads import balances_of
from etqan.wallet.services.reads import entries_of
from etqan.wallet.services.reads import student_of

__all__ = [
    "Balance",
    "adjust",
    "balances_of",
    "entries_of",
    "student_of",
    "top_up",
]
```

- [ ] **Step 4: Run, format, lint, commit**

Run: `$DJ pytest etqan/wallet -q`
Expected: PASS.
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`
Expected: clean (wallet reaches billing and identity through their services only).

```bash
git -C backend add etqan/wallet
git -C backend commit -m "feat(wallet): the ledger, office top-ups, adjustments and balances_of (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 6: Wallet services: paying invoices, moving payments, reversing top-ups

**Files:**
- Modify: `backend/etqan/wallet/services/ledger.py`, `backend/etqan/wallet/services/reads.py`, `backend/etqan/wallet/services/__init__.py`
- Create: `backend/etqan/wallet/tests/test_spending.py`

**Interfaces:**
- Consumes: Task 3's `invoice_for`, `invoices_queryset`, `record_wallet_payment`, `credit_payment`, `refund_topup_payment`, `payments_queryset`; Task 5's `lock_wallet`, `write`, `insufficient`.
- Produces (exported):
  - `may_use(user, student_user_id: int) -> bool` (E-17: the student themself, or a parent of the student; nobody else);
  - `find_payment(payment_id: int)` (billing's payment row, `NotFoundError` otherwise);
  - `pay_invoice(invoice_id, *, by, amount_minor=None) -> WalletEntry` (W9);
  - `move_to_wallet(payment_id, *, by) -> WalletEntry` (409 `wallet.not_invoice_payment` for a standalone record);
  - `reverse_topup(payment_id, *, by) -> WalletEntry` (409 `wallet.not_topup`, `wallet.insufficient_balance`).

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/wallet/tests/test_spending.py`:

```python
"""B3e E-6, E-11..E-13, E-17, §9: paying invoices from the balance, moving a
payment into it, reversing a top-up; the locks from captured SQL, the C1
race, a stale balance, and revenue counted once."""

import re
from datetime import date

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.billing import services as billing_services
from etqan.billing.models import Invoice
from etqan.billing.models import Payment
from etqan.billing.tests.conftest import make_parent
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.wallet import services
from etqan.wallet.models import WalletEntry
from etqan.wallet.tests.conftest import ledger_holds

pytestmark = pytest.mark.django_db
JUNE = (date(2026, 6, 1), date(2026, 7, 1))
INSUFFICIENT = "wallet.insufficient_balance"


def fund(world, admin, amount=30000, currency="EGP"):
    return services.top_up(
        world.student.id, amount_minor=amount, currency=currency, method="cash", by=admin
    )


def status(invoice) -> str:
    return billing_services.invoices_queryset().get(pk=invoice.pk).status


def balance(world, currency="EGP") -> int:
    held = {b.currency: b.balance_minor for b in services.balances_of(world.student.id)}
    return held.get(currency, 0)


def cash_payment(bill, admin, amount):
    return billing_services.add_payment(
        bill, amount_minor=amount, method="cash", paid_on=date(2026, 6, 1), by=admin
    )


def locked_tables(action) -> list[str]:
    """The tables ``action`` locks, in order (plan W10)."""
    with CaptureQueriesContext(connection) as ctx:
        action()
    return [
        re.search(r'FROM "(\w+)"', q["sql"]).group(1)
        for q in ctx.captured_queries
        if "FOR UPDATE" in q["sql"]
    ]


def code(caught) -> str:
    return caught.value.code


def test_paying_takes_the_smaller_of_the_balance_and_the_amount_due(
    world, admin, invoice
):
    fund(world, admin, 30000)
    bill = invoice(amount_minor=20000)
    entry = services.pay_invoice(bill.pk, by=admin)
    payment = Payment.objects.get(pk=entry.payment_id)
    assert (
        entry.kind,
        entry.amount_minor,
        entry.balance_after_minor,
        entry.invoice_id,
        entry.note,
    ) == ("spend", -20000, 10000, bill.pk, bill.number)
    assert (payment.method, payment.amount_minor, payment.fee_minor) == ("wallet", 20000, 0)
    assert payment.invoice_id == bill.pk
    assert status(bill) == "paid"
    bigger = invoice(amount_minor=50000)
    assert services.pay_invoice(bigger.pk, by=admin).amount_minor == -10000
    assert (status(bigger), balance(world)) == ("partial", 0)
    ledger_holds(world.student.id)


def test_the_office_may_pay_less_and_both_balances_bound_it(world, admin, invoice):
    fund(world, admin, 30000)
    bill = invoice(amount_minor=20000)
    services.pay_invoice(bill.pk, by=admin, amount_minor=5000)
    assert (status(bill), balance(world)) == ("partial", 25000)
    with pytest.raises(ConflictError) as over_wallet:
        services.pay_invoice(bill.pk, by=admin, amount_minor=25001)
    assert code(over_wallet) == INSUFFICIENT
    with pytest.raises(ValidationError) as over_due:
        services.pay_invoice(bill.pk, by=admin, amount_minor=15001)
    assert over_due.value.field == "amount_minor"
    for bad in (0, -1, "5", True, 1.5):
        with pytest.raises(ValidationError) as refused:
            services.pay_invoice(bill.pk, by=admin, amount_minor=bad)
        assert refused.value.field == "amount_minor"
    assert balance(world) == 25000


def test_void_nothing_due_empty_and_other_currency(world, admin, invoice):
    void = invoice()
    billing_services.void_invoice(void, by=admin)
    fund(world, admin, 1000)
    with pytest.raises(ConflictError) as voided:
        services.pay_invoice(void.pk, by=admin)
    assert code(voided) == "billing.invoice_void"
    small = invoice(amount_minor=1000)
    services.pay_invoice(small.pk, by=admin)
    with pytest.raises(ConflictError) as paid:
        services.pay_invoice(small.pk, by=admin)
    assert code(paid) == "wallet.nothing_due"
    with pytest.raises(ConflictError) as empty:
        services.pay_invoice(invoice(amount_minor=500).pk, by=admin)
    assert code(empty) == INSUFFICIENT
    with pytest.raises(ConflictError) as dollars:
        services.pay_invoice(invoice(currency="USD", amount_minor=500).pk, by=admin)
    assert code(dollars) == INSUFFICIENT
    assert not services.balances_of(world.student.id)[0].balance_minor


def test_the_family_pays_by_e17_and_a_payer_only_reader_does_not(
    world, admin, invoice, parent
):
    fund(world, admin, 30000)
    assert services.pay_invoice(invoice(amount_minor=1000).pk, by=parent).kind == "spend"
    # The student themself, parent or no parent.
    mine = invoice(amount_minor=1000)
    assert services.pay_invoice(mine.pk, by=world.student).amount_minor == -1000
    # A payer who is not the student's parent reads the invoice it pays, but
    # not the student's wallet (E-17): 404.
    payer_only = make_parent("Huda")
    billed = invoice(amount_minor=1000)
    Invoice.objects.filter(pk=billed.pk).update(payer=payer_only)
    assert billing_services.invoice_for(payer_only, billed.pk).pk == billed.pk
    with pytest.raises(NotFoundError):
        services.pay_invoice(billed.pk, by=payer_only)
    with pytest.raises(NotFoundError):
        services.pay_invoice(billed.pk, by=make_parent("Nobody"))
    assert balance(world) == 28000


def test_the_office_needs_the_invoice_code(world, admin, invoice, staff_for):
    fund(world, admin, 30000)
    bill = invoice(amount_minor=1000)
    with pytest.raises(NotFoundError):
        services.pay_invoice(bill.pk, by=staff_for("wallet.update").user)
    clerk = staff_for("wallet.update", "invoice.view").user
    assert services.pay_invoice(bill.pk, by=clerk).created_by == clerk


def test_moving_a_payment_credits_its_amount_without_the_fee(world, admin, invoice):
    bill = invoice(amount_minor=20000)
    cash = cash_payment(bill, admin, 20000)
    entry = services.move_to_wallet(cash.pk, by=admin)
    assert (entry.kind, entry.amount_minor, entry.invoice_id, entry.payment_id) == (
        "refund",
        20000,
        bill.pk,
        cash.pk,
    )
    assert entry.note == bill.number
    assert Payment.objects.get(pk=cash.pk).status == "credited"
    assert status(bill) == "unpaid"
    card = billing_services.record_online_payment(
        invoice(amount_minor=10000),
        amount_minor=10000,
        fee_minor=500,
        method="stripe",
        transaction_number="pi_move",
    )
    assert services.move_to_wallet(card.pk, by=admin).amount_minor == 10000
    assert balance(world) == 30000
    ledger_holds(world.student.id)


def test_moving_a_wallet_payment_undoes_the_spend(world, admin, invoice):
    fund(world, admin, 30000)
    bill = invoice(amount_minor=20000)
    spend = services.pay_invoice(bill.pk, by=admin)
    back = services.move_to_wallet(spend.payment_id, by=admin)
    assert (back.kind, back.amount_minor, back.balance_after_minor) == ("refund", 20000, 30000)
    assert status(bill) == "unpaid"


def test_what_cannot_be_moved(world, admin, invoice):
    record = billing_services.create_record(
        customer_type="unregistered",
        customer_name="Abu Khalid",
        amount_minor=100,
        method="cash",
        by=admin,
    )
    with pytest.raises(ConflictError) as standalone:
        services.move_to_wallet(record.pk, by=admin)
    assert code(standalone) == "wallet.not_invoice_payment"
    bill = invoice(amount_minor=1000)
    refunded = cash_payment(bill, admin, 300)
    billing_services.refund_payment(refunded, by=admin)
    moved = cash_payment(bill, admin, 300)
    services.move_to_wallet(moved.pk, by=admin)
    for payment in (refunded, moved):
        with pytest.raises(ConflictError) as again:
            services.move_to_wallet(payment.pk, by=admin)
        assert code(again) == "billing.payment_not_completed"
    with pytest.raises(NotFoundError):
        services.move_to_wallet(999999, by=admin)
    assert WalletEntry.objects.count() == 1


def test_reversing_a_top_up_needs_its_amount_in_the_balance(world, admin, invoice):
    top = fund(world, admin, 30000)
    services.pay_invoice(invoice(amount_minor=20000).pk, by=admin)
    with pytest.raises(ConflictError) as short:
        services.reverse_topup(top.payment_id, by=admin)
    assert code(short) == INSUFFICIENT
    spend = WalletEntry.objects.get(kind="spend")
    services.move_to_wallet(spend.payment_id, by=admin)
    entry = services.reverse_topup(top.payment_id, by=admin)
    assert (entry.kind, entry.amount_minor, entry.balance_after_minor) == (
        "reversal",
        -30000,
        0,
    )
    assert Payment.objects.get(pk=top.payment_id).status == "refunded"
    assert services.entries_of(world.student.id).get(pk=top.pk).reversed is True
    with pytest.raises(ConflictError) as again:
        services.reverse_topup(top.payment_id, by=admin)
    assert code(again) in ("billing.already_refunded", INSUFFICIENT)
    with pytest.raises(ConflictError) as not_top:
        services.reverse_topup(spend.payment_id, by=admin)
    assert code(not_top) == "wallet.not_topup"
    ledger_holds(world.student.id)


def test_a_debit_reads_the_balance_after_the_lock(world, admin, invoice):
    """Review Focus 1: a page loaded 300.00; another tab spent 200.00 since."""
    top = fund(world, admin, 30000)
    seen = services.balances_of(world.student.id)
    services.pay_invoice(invoice(amount_minor=20000).pk, by=admin)
    assert seen == [services.Balance("EGP", 30000)]
    with pytest.raises(ConflictError) as adjusted:
        services.adjust(
            world.student.id, amount_minor=-30000, currency="EGP", reason="Typo", by=admin
        )
    assert code(adjusted) == INSUFFICIENT
    with pytest.raises(ConflictError) as reversed_:
        services.reverse_topup(top.payment_id, by=admin)
    assert code(reversed_) == INSUFFICIENT
    assert Payment.objects.get(pk=top.payment_id).status == "completed"
    assert balance(world) == 10000


def test_each_write_locks_wallet_then_invoice_then_payment(world, admin, invoice):
    """E-6, plan W10: the money chain, from the captured FOR UPDATE SQL."""
    top = fund(world, admin, 30000)
    bill = invoice(amount_minor=1000)
    assert locked_tables(lambda: services.pay_invoice(bill.pk, by=admin)) == [
        "wallet_wallet",
        "billing_invoice",
    ]
    spend = WalletEntry.objects.get(kind="spend")
    assert locked_tables(
        lambda: services.move_to_wallet(spend.payment_id, by=admin)
    ) == ["wallet_wallet", "billing_invoice", "billing_payment"]
    assert locked_tables(
        lambda: services.reverse_topup(top.payment_id, by=admin)
    ) == ["wallet_wallet", "billing_payment"]


def test_c1_a_payment_moved_meanwhile_is_neither_deleted_nor_refunded(
    world, admin, invoice
):
    """E-9, review C1: loaded completed, moved, then deleted or refunded."""
    bill = invoice(amount_minor=20000)
    cash = cash_payment(bill, admin, 20000)
    stale = Payment.objects.select_related("invoice").get(pk=cash.pk)
    services.move_to_wallet(cash.pk, by=admin)
    spent = services.pay_invoice(bill.pk, by=admin)
    stale_spend = Payment.objects.select_related("invoice").get(pk=spent.payment_id)
    before = list(WalletEntry.objects.values_list("id", "balance_after_minor"))
    for payment, expected in (
        (stale, "billing.payment_credited"),
        (stale_spend, "billing.wallet_payment"),
    ):
        for action in (
            lambda p=payment: billing_services.delete_payment(p),
            lambda p=payment: billing_services.refund_payment(p, by=admin),
        ):
            with pytest.raises(ConflictError) as refused:
                action()
            assert code(refused) == expected
    assert list(WalletEntry.objects.values_list("id", "balance_after_minor")) == before
    assert balance(world) == 0
    assert Payment.objects.get(pk=cash.pk).status == "credited"


def test_revenue_counts_the_money_once(world, admin, invoice):
    """E-7, ledger D36, spec §9: top up 100 and spend 100, revenue is 100."""
    top = fund(world, admin, 10000)
    bill = invoice(amount_minor=10000)
    spend = services.pay_invoice(bill.pk, by=admin)
    revenue = [{"currency": "EGP", "amount_minor": 10000}]
    assert billing_services.revenue_between(*JUNE) == revenue
    services.adjust(world.student.id, amount_minor=500, currency="EGP", reason="Gift", by=admin)
    services.move_to_wallet(spend.payment_id, by=admin)  # a wallet payment, credited
    assert billing_services.revenue_between(*JUNE) == revenue
    cash = cash_payment(bill, admin, 10000)
    services.move_to_wallet(cash.pk, by=admin)  # credited stays revenue
    assert billing_services.revenue_between(*JUNE) == [
        {"currency": "EGP", "amount_minor": 20000}
    ]
    services.reverse_topup(top.payment_id, by=admin)  # leaves with its fee (0)
    assert billing_services.revenue_between(*JUNE) == revenue
    assert balance(world) == 10500
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/wallet/tests/test_spending.py -q`
Expected: FAIL (`AttributeError: … 'pay_invoice'`).

- [ ] **Step 3: Implement**

`backend/etqan/wallet/services/reads.py`, add the import `from etqan.platform.permissions import role_of` and append:

```python
def may_use(user, student_user_id: int) -> bool:
    """E-17: the student themself, or a parent of the student. A payer who
    is neither (a paying sibling) reads the invoices it pays, never the
    wallet. The office is decided by codes, in the views."""
    role = role_of(user)
    if role == "student":
        return user.pk == student_user_id
    if role == "parent":
        return identity_services.is_parent_of(user.pk, student_user_id)
    return False
```

`backend/etqan/wallet/services/ledger.py`, add the imports

```python
from etqan.platform.permissions import is_office
from etqan.wallet.services.reads import may_use
```

and append:

```python
def find_payment(payment_id: int):
    """Billing's row for ``payment_id``, read unlocked to learn its student
    and currency; 404 otherwise. The lock comes after the wallet's (E-6)."""
    payment = billing_services.payments_queryset().filter(pk=payment_id).first()
    if payment is None:
        raise NotFoundError("Payment", payment_id)
    return payment


@transaction.atomic
def pay_invoice(invoice_id: int, *, by, amount_minor: int | None = None) -> WalletEntry:
    """E-11, plan W9: a `wallet` payment and its `spend` entry. The invoice is
    read as billing scopes it (`invoice_for`: 404, staff need invoice.view);
    a family member must also be E-17's. The wallet is locked, then the
    amount is decided on fresh values; billing checks again under the
    invoice lock (wallet → invoice, E-6)."""
    invoice = billing_services.invoice_for(by, invoice_id)
    if not is_office(by) and not may_use(by, invoice.student.user_id):
        raise NotFoundError("Invoice", invoice_id)
    if amount_minor is not None and (not _is_int(amount_minor) or amount_minor < 1):
        raise ValidationError("Enter an amount above zero.", field="amount_minor")
    wallet = lock_wallet(invoice.student_id, invoice.currency, create=False)
    fresh = billing_services.invoices_queryset().get(pk=invoice.pk)
    if fresh.status == "void":
        raise ConflictError("This invoice is void.", code="billing.invoice_void")
    if fresh.balance_minor <= 0:
        raise ConflictError(
            "Nothing is due on this invoice.", code="wallet.nothing_due"
        )
    available = wallet.balance_minor if wallet is not None else 0
    amount = (
        min(available, fresh.balance_minor) if amount_minor is None else amount_minor
    )
    if amount < 1 or amount > available:
        raise insufficient()
    payment = billing_services.record_wallet_payment(fresh, amount_minor=amount, by=by)
    return write(
        wallet,
        kind=Kind.SPEND,
        amount_minor=-amount,
        by=by,
        note=fresh.number,
        payment_id=payment.pk,
        invoice_id=fresh.pk,
    )


@transaction.atomic
def move_to_wallet(payment_id: int, *, by) -> WalletEntry:
    """E-12: a completed invoice payment, any method, into the wallet of
    (the invoice's student, the payment's currency); the fee stays revenue
    and is not credited. For a `wallet` payment it undoes a spend."""
    payment = find_payment(payment_id)
    if payment.invoice_id is None:
        raise ConflictError(
            "Only a payment on an invoice is moved to the balance.",
            code="wallet.not_invoice_payment",
        )
    wallet = lock_wallet(payment.invoice.student_id, payment.currency, create=True)
    moved = billing_services.credit_payment(payment, by=by)
    return write(
        wallet,
        kind=Kind.REFUND,
        amount_minor=moved.amount_minor,
        by=by,
        note=payment.invoice.number,
        payment_id=moved.pk,
        invoice_id=moved.invoice_id,
    )


@transaction.atomic
def reverse_topup(payment_id: int, *, by) -> WalletEntry:
    """E-13: gives a top-up back. The balance must cover it (read after the
    lock); billing marks the payment refunded, re-checking its status on the
    locked row, so its revenue and fee leave together (E-7)."""
    payment = find_payment(payment_id)
    if not payment.wallet_topup:
        raise ConflictError(
            "Only a balance top-up is reversed.", code="wallet.not_topup"
        )
    wallet = lock_wallet(payment.student_id, payment.currency, create=False)
    if wallet is None or wallet.balance_minor < payment.amount_minor:
        raise insufficient()
    refunded = billing_services.refund_topup_payment(payment, by=by)
    return write(
        wallet,
        kind=Kind.REVERSAL,
        amount_minor=-refunded.amount_minor,
        by=by,
        payment_id=refunded.pk,
    )
```

Replace `backend/etqan/wallet/services/__init__.py`'s imports and `__all__` with:

```python
from etqan.wallet.services.ledger import adjust
from etqan.wallet.services.ledger import find_payment
from etqan.wallet.services.ledger import move_to_wallet
from etqan.wallet.services.ledger import pay_invoice
from etqan.wallet.services.ledger import reverse_topup
from etqan.wallet.services.ledger import top_up
from etqan.wallet.services.reads import Balance
from etqan.wallet.services.reads import balances_of
from etqan.wallet.services.reads import entries_of
from etqan.wallet.services.reads import may_use
from etqan.wallet.services.reads import student_of

__all__ = [
    "Balance",
    "adjust",
    "balances_of",
    "entries_of",
    "find_payment",
    "may_use",
    "move_to_wallet",
    "pay_invoice",
    "reverse_topup",
    "student_of",
    "top_up",
]
```

- [ ] **Step 4: Run, format, lint, commit**

Run: `$DJ pytest etqan/wallet etqan/billing -q`
Expected: PASS.
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/wallet
git -C backend commit -m "feat(wallet): pay invoices, move payments and reverse top-ups, wallet before invoice (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 7: The online top-up: the `wallet_topup` purpose, its start and the family's reads

**Files:**
- Create: `backend/etqan/wallet/services/online.py`, `backend/etqan/wallet/services/topup_purpose.py`, `backend/etqan/wallet/tests/test_online_topup.py`
- Modify: `backend/etqan/wallet/apps.py`, `backend/etqan/wallet/services/reads.py`, `backend/etqan/wallet/services/__init__.py`

**Interfaces:**
- Consumes: `gateways.services.register_purpose`, `start_checkout`, `Prepared`, `Applied`, `CompletedCheckout`, `StartedCheckout`; `academy.services.get_settings`; `billing.services.invoices_queryset`, `record_topup_payment`, `METHOD_LABELS`; Task 5/6's `lock_wallet`, `write`, `check_amount`, `profile_of`, `may_use`.
- Produces:
  - `topup_currencies(student_user_id) -> list[str]` (W17), `family_wallets(user) -> list[dict]` (`{"student": {"id","name"}, "balances": list[Balance], "topup_currencies": list[str]}`, one per student the caller may use), both exported;
  - `start_top_up(student_user_id, *, amount_minor, currency, provider, user) -> StartedCheckout`, exported;
  - `etqan.wallet.services.topup_purpose`: `NAME = "wallet_topup"`, `prepare(reference_id, user, params) -> Prepared`, `complete(done) -> Applied`, `register()`; registered in `WalletConfig.ready()`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/wallet/tests/test_online_topup.py`:

```python
"""B3e E-15, E-16, E-18: the private `wallet_topup` purpose, started by a
family, priced from its TopUp row (so a re-check prices it the same),
completed by a verified payment, even with `balances` off."""

import re
import uuid
from datetime import date

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone

from etqan.billing import services as billing_services
from etqan.billing.models import Payment
from etqan.billing.tests.conftest import make_parent
from etqan.gateways import services as gateways_services
from etqan.gateways.models import Checkout
from etqan.gateways.services import captures
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import make_student
from etqan.wallet import services
from etqan.wallet.models import TopUp
from etqan.wallet.models import WalletEntry
from etqan.wallet.services import topup_purpose
from etqan.wallet.tests.conftest import ledger_holds

pytestmark = pytest.mark.django_db
JUNE = (date(2026, 6, 1), date(2026, 7, 1))


def start(world, user, amount=5000, currency="EGP", provider="stripe"):
    return services.start_top_up(
        world.student.id,
        amount_minor=amount,
        currency=currency,
        provider=provider,
        user=user,
    )


def done(row, **fields):
    values = {
        "id": uuid.uuid4(),
        "purpose": "wallet_topup",
        "reference_id": row.pk,
        "provider": "stripe",
        "amount_minor": row.amount_minor,
        "fee_minor": 250,
        "currency": row.currency,
        "transaction_number": f"pi_{uuid.uuid4().hex[:8]}",
        "completed_at": timezone.now(),
        **fields,
    }
    return gateways_services.CompletedCheckout(**values)


@pytest.fixture
def egp(world, admin):
    """EGP is a top-up currency for Yusuf once he holds it (E-18)."""
    services.top_up(
        world.student.id, amount_minor=100, currency="EGP", method="cash", by=admin
    )


def test_the_purpose_is_registered_private():
    assert gateways_services.purpose_named("wallet_topup") is not None
    assert gateways_services.is_public_purpose("wallet_topup") is False


def test_starting_creates_a_row_and_reuses_it(world, parent, online_on, stripe_on, egp):
    started = start(world, parent)
    row = TopUp.objects.get()
    assert (row.amount_minor, row.currency, row.created_by, row.status) == (
        5000,
        "EGP",
        parent,
        "pending",
    )
    checkout = Checkout.objects.get(pk=started.id)
    assert (
        checkout.purpose,
        checkout.reference_id,
        checkout.amount_minor,
        checkout.fee_minor,
        checkout.description,
    ) == ("wallet_topup", row.pk, 5000, 250, "Wallet top-up · Yusuf")
    assert start(world, parent).id == started.id
    assert TopUp.objects.count() == 1
    start(world, parent, amount=6000)
    assert TopUp.objects.count() == 2


def test_a_start_refuses_bad_input_and_strangers(world, parent, online_on, stripe_on, egp):
    for fields, field in (
        ({"amount": 0}, "amount_minor"),
        ({"amount": 100_000_001}, "amount_minor"),
        ({"currency": "JPY"}, "currency"),
        ({"currency": "EG"}, "currency"),
        ({"provider": "visa"}, "provider"),
    ):
        with pytest.raises(ValidationError) as caught:
            start(world, parent, **fields)
        assert caught.value.field == field, fields
    with pytest.raises(NotFoundError):
        start(world, make_parent("Huda"))
    assert not Checkout.objects.exists()


def test_prepare_refuses_who_and_what_it_must(
    world, parent, online_on, stripe_on, egp, set_features
):
    start(world, parent)
    row = TopUp.objects.get()
    for user in (make_parent("Huda"), None):
        with pytest.raises(NotFoundError):
            topup_purpose.prepare(row.pk, user, None)
    with pytest.raises(NotFoundError):
        topup_purpose.prepare(999999, parent, None)
    identity_services.unlink_guardian(parent, world.student)
    with pytest.raises(NotFoundError):
        topup_purpose.prepare(row.pk, parent, None)  # a lost guardian link
    identity_services.link_guardian(parent, world.student)
    for off in ("balances", "online_payments"):
        set_features(**{off: False})
        with pytest.raises(NotFoundError):
            topup_purpose.prepare(row.pk, parent, None)
        set_features(**{off: True})
    TopUp.objects.filter(pk=row.pk).update(status="paid")
    with pytest.raises(ConflictError) as paid:
        topup_purpose.prepare(row.pk, parent, None)
    assert paid.value.code == "wallet.topup_paid"
    with pytest.raises(ConflictError):
        gateways_services.start_checkout("wallet_topup", row.pk, "stripe", user=parent)


def test_a_recheck_prices_it_as_the_start_did(world, parent, online_on, stripe_on, egp):
    started = start(world, parent)
    row = TopUp.objects.get()
    prepared = topup_purpose.prepare(row.pk, parent, gateways_services.RECHECK)
    assert (
        prepared.amount_minor,
        prepared.currency,
        prepared.add_fee,
        prepared.use_switch,
    ) == (5000, "EGP", True, True)
    assert captures.still_payable(Checkout.objects.get(pk=started.id)) is True


def test_a_stripe_payment_credits_the_wallet_and_its_fee_is_revenue(
    world, parent, online_on, stripe_on, egp
):
    started = start(world, parent)
    assert gateways_services.simulate(started.id, "pay", user=parent) == "completed"
    checkout = Checkout.objects.get(pk=started.id)
    assert (checkout.applied, checkout.attention) == (True, "")
    entry = WalletEntry.objects.get(kind="topup", top_up__isnull=False)
    payment = Payment.objects.get(pk=entry.payment_id)
    assert (entry.amount_minor, entry.note, entry.created_by) == (5000, "Stripe", None)
    assert (
        payment.method,
        payment.fee_minor,
        payment.wallet_topup,
        payment.recorded_by,
        payment.transaction_number,
    ) == ("stripe", 250, True, None, checkout.transaction_number)
    row = TopUp.objects.get()
    assert row.status == "paid" and row.paid_at is not None
    assert billing_services.revenue_between(*JUNE) == [
        {"currency": "EGP", "amount_minor": 100 + 5250}
    ]
    ledger_holds(world.student.id)


def test_a_paypal_capture_credits_too(world, parent, online_on, paypal_on):
    started = start(world, parent, currency="USD", provider="paypal")
    assert gateways_services.simulate(started.id, "pay", user=parent) == "completed"
    entry = WalletEntry.objects.get(kind="topup")
    assert (entry.wallet.currency, entry.amount_minor, entry.note) == ("USD", 5000, "PayPal")
    assert Payment.objects.get(pk=entry.payment_id).fee_minor == 250


def test_a_second_paid_checkout_for_one_row_credits_again(
    world, parent, online_on, stripe_on, egp
):
    """E-16: Stripe, then another checkout of the same row: the family's money."""
    started = start(world, parent)
    gateways_services.simulate(started.id, "pay", user=parent)
    row = TopUp.objects.get()
    second = Checkout.objects.create(
        purpose="wallet_topup",
        reference_id=row.pk,
        provider="stripe",
        simulated=True,
        amount_minor=5000,
        fee_minor=250,
        currency="EGP",
        provider_ref=f"cs_sim_{uuid.uuid4().hex[:8]}",
        created_by=parent,
    )
    assert gateways_services.simulate(second.pk, "pay", user=parent) == "completed"
    second.refresh_from_db()
    assert second.applied is True
    assert WalletEntry.objects.filter(top_up=row).count() == 2
    assert services.balances_of(world.student.id) == [services.Balance("EGP", 10100)]


def test_the_same_transaction_twice_is_already_recorded(world, parent, online_on, stripe_on, egp):
    start(world, parent)
    row = TopUp.objects.get()
    once = done(row, transaction_number="pi_dup")
    assert topup_purpose.complete(once) == gateways_services.Applied(ok=True)
    assert topup_purpose.complete(once) == gateways_services.Applied(
        ok=False, reason="already_recorded"
    )
    assert WalletEntry.objects.filter(top_up=row).count() == 1


def test_money_that_does_not_match_its_row_needs_attention(
    world, parent, online_on, stripe_on, egp
):
    start(world, parent)
    row = TopUp.objects.get()
    for fields, reason in (
        ({"currency": "USD"}, "currency_mismatch"),
        ({"amount_minor": 4999}, "amount_mismatch"),
        ({"reference_id": 999999}, "reference_missing"),
    ):
        assert topup_purpose.complete(done(row, **fields)) == gateways_services.Applied(
            ok=False, reason=reason
        )
    assert not WalletEntry.objects.filter(top_up=row).exists()
    assert TopUp.objects.get().status == "pending"


def test_a_started_top_up_completes_with_balances_off(
    world, parent, online_on, stripe_on, egp, set_features
):
    started = start(world, parent)
    set_features(balances=False)
    assert gateways_services.simulate(started.id, "pay", user=parent) == "completed"
    assert Checkout.objects.get(pk=started.id).applied is True
    assert WalletEntry.objects.filter(top_up__isnull=False).count() == 1


def test_completion_locks_checkout_then_top_up_then_wallet(
    world, parent, online_on, stripe_on, egp
):
    """E-6, plan W10: the money chain's head, from the captured SQL."""
    started = start(world, parent)
    with CaptureQueriesContext(connection) as ctx:
        gateways_services.simulate(started.id, "pay", user=parent)
    tables = [
        re.search(r'FROM "(\w+)"', q["sql"]).group(1)
        for q in ctx.captured_queries
        if "FOR UPDATE" in q["sql"]
    ]
    assert tables == ["gateways_checkout", "wallet_topup", "wallet_wallet"]


def test_the_top_up_currencies_follow_e18(world, admin, invoice):
    assert services.topup_currencies(world.student.id) == ["USD"]  # the academy's
    invoice(currency="SAR", amount_minor=1000)
    void = invoice(currency="JPY", amount_minor=1000)
    billing_services.void_invoice(void, by=admin)
    services.top_up(
        world.student.id, amount_minor=100, currency="EGP", method="cash", by=admin
    )
    assert services.topup_currencies(world.student.id) == ["USD", "EGP", "SAR"]


def test_family_wallets_lists_each_student_the_caller_may_use(world, parent, admin):
    sister = make_student("Maryam")
    identity_services.link_guardian(parent, sister)
    services.top_up(
        world.student.id, amount_minor=100, currency="EGP", method="cash", by=admin
    )
    rows = services.family_wallets(parent)
    assert [row["student"] for row in rows] == [
        {"id": world.student.id, "name": "Yusuf"},
        {"id": sister.id, "name": "Maryam"},
    ]
    assert rows[0]["balances"] == [services.Balance("EGP", 100)]
    assert (rows[1]["balances"], rows[1]["topup_currencies"]) == ([], ["USD"])
    assert [row["student"]["id"] for row in services.family_wallets(world.student)] == [
        world.student.id
    ]
    assert services.family_wallets(admin) == []
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/wallet/tests/test_online_topup.py -q`
Expected: FAIL (`ImportError: topup_purpose`).

- [ ] **Step 3: Implement**

`backend/etqan/wallet/services/reads.py`, add the imports

```python
from etqan.academy import services as academy_services
from etqan.billing import services as billing_services
```

and append:

```python
def topup_currencies(student_user_id: int) -> list[str]:
    """E-18, plan W17: the academy's currency first, then the student's
    wallets' and non-void invoices' currencies, sorted."""
    default = academy_services.get_settings().default_currency
    held = set(
        Wallet.objects.filter(student__user_id=student_user_id).values_list(
            "currency", flat=True
        )
    )
    invoiced = set(
        billing_services.invoices_queryset()
        .filter(student__user_id=student_user_id)
        .exclude(status="void")
        .order_by()
        .values_list("currency", flat=True)
    )
    return [default, *sorted((held | invoiced) - {default})]


def _family_students(user) -> list:
    role = role_of(user)
    if role == "student":
        profile = identity_services.get_student_profile(user.pk)
        return [profile] if profile is not None else []
    if role == "parent":
        return list(identity_services.get_children(user.pk).select_related("user"))
    return []


def family_wallets(user) -> list[dict]:
    """`wallet/mine/` (spec §5): each student the caller may use (E-17), a
    student with no parent alone."""
    return [
        {
            "student": {"id": profile.user_id, "name": profile.user.full_name},
            "balances": balances_of(profile.user_id),
            "topup_currencies": topup_currencies(profile.user_id),
        }
        for profile in _family_students(user)
    ]
```

Create `backend/etqan/wallet/services/online.py`:

```python
"""A family's online top-up (B3e E-15, §4.2): a `TopUp` row first, then
gateways' checkout for it. Called from a non-atomic view: the row commits
in its own block before the provider is called (gateways' plan D9)."""

from datetime import timedelta

from django.db import transaction
from django.utils import timezone

from etqan.gateways import services as gateways_services
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency
from etqan.wallet.models import TopUp
from etqan.wallet.services.ledger import check_amount
from etqan.wallet.services.ledger import profile_of
from etqan.wallet.services.reads import may_use
from etqan.wallet.services.reads import topup_currencies
from etqan.wallet.services.topup_purpose import NAME

# Plan W16: gateways' REUSE_FOR (services/checkouts.py), which its public
# API does not re-export.
REUSE_FOR = timedelta(hours=23)


def start_top_up(
    student_user_id: int, *, amount_minor: int, currency: str, provider: str, user
) -> gateways_services.StartedCheckout:
    """Reuses the newest pending row of the same student, currency, amount
    and creator younger than 23 hours, else creates one. The lookup is
    unlocked: two clicks may make two rows, each paid only through its own
    checkout (§4.2)."""
    if not may_use(user, student_user_id):
        raise NotFoundError("Student", student_user_id)
    profile = profile_of(student_user_id)
    check_amount(amount_minor)
    code = clean_currency(currency or "", field="currency")
    if code not in topup_currencies(student_user_id):
        raise ValidationError(
            "Choose one of the offered currencies.", field="currency"
        )
    with transaction.atomic():
        row = (
            TopUp.objects.filter(
                student=profile,
                currency=code,
                amount_minor=amount_minor,
                created_by=user,
                status=TopUp.Status.PENDING,
                created_at__gt=timezone.now() - REUSE_FOR,
            )
            .order_by("-id")
            .first()
        )
        if row is None:
            row = TopUp.objects.create(
                student=profile, currency=code, amount_minor=amount_minor, created_by=user
            )
    return gateways_services.start_checkout(NAME, row.pk, provider, user=user)
```

Create `backend/etqan/wallet/services/topup_purpose.py`:

```python
"""The wallet's private `wallet_topup` purpose (B3e E-15, E-16, §4.3). The
amount comes from the TopUp row, never from params, so gateways' re-check
(RECHECK, ledger D28) prices it as the start did."""

import logging

from django.db import IntegrityError
from django.db import transaction
from django.utils import timezone

from etqan.billing import services as billing_services
from etqan.gateways import services as gateways_services
from etqan.platform import features
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.wallet.models import TopUp
from etqan.wallet.models import WalletEntry
from etqan.wallet.services.ledger import lock_wallet
from etqan.wallet.services.ledger import write
from etqan.wallet.services.reads import may_use

NAME = "wallet_topup"
TRANSACTION_UNIQUE = "billing_payment_transaction_unique"
logger = logging.getLogger(__name__)


def prepare(reference_id: int, user, params: dict | None) -> gateways_services.Prepared:
    """404 unless ``user`` created the row and may still use the wallet
    (E-17), with `balances` and `online_payments` on; a paid row is 409 (no
    new checkout starts for it). `use_switch` stays True: the academy's fee
    switch decides, as for invoices."""
    row = TopUp.objects.select_related("student__user").filter(pk=reference_id).first()
    user_id = getattr(user, "pk", None)
    if (
        row is None
        or user_id is None
        or row.created_by_id != user_id
        or not features.enabled("balances")
        or not features.enabled("online_payments")
        or not may_use(user, row.student.user_id)
    ):
        raise NotFoundError("Top-up", reference_id)
    if row.status == TopUp.Status.PAID:
        raise ConflictError("This top-up is already paid.", code="wallet.topup_paid")
    return gateways_services.Prepared(
        amount_minor=row.amount_minor,
        currency=row.currency,
        description=f"Wallet top-up · {row.student.user.full_name}",
        add_fee=True,
    )


def complete(done: gateways_services.CompletedCheckout) -> gateways_services.Applied:
    """E-16: every paid checkout of the row is credited (the only duplicate
    guard is the unique transaction number per method), even while
    `balances` is off: money received is never dropped. The caller holds the
    checkout's lock; then the row, then the wallet (E-6)."""
    row = TopUp.objects.select_for_update().filter(pk=done.reference_id).first()
    if row is None:
        return gateways_services.Applied(ok=False, reason="reference_missing")
    if done.currency != row.currency:
        return gateways_services.Applied(ok=False, reason="currency_mismatch")
    if done.amount_minor != row.amount_minor:
        return gateways_services.Applied(ok=False, reason="amount_mismatch")
    wallet = lock_wallet(row.student_id, row.currency, create=True)
    try:
        with transaction.atomic():
            payment = billing_services.record_topup_payment(
                student_profile_id=row.student_id,
                amount_minor=done.amount_minor,
                currency=done.currency,
                method=done.provider,
                by=None,
                fee_minor=done.fee_minor,
                transaction_number=done.transaction_number,
            )
            write(
                wallet,
                kind=WalletEntry.Kind.TOPUP,
                amount_minor=done.amount_minor,
                by=None,
                note=billing_services.METHOD_LABELS.get(done.provider, done.provider),
                payment_id=payment.pk,
                top_up=row,
            )
    except ValidationError as exc:
        if exc.field == "transaction_number":
            return gateways_services.Applied(ok=False, reason="already_recorded")
        # As billing's link purpose: refused money is attention, never a
        # webhook 500 the provider retries forever. Logged by field only.
        logger.warning("wallet_topup %s not recorded: refused on %s", done.id, exc.field)
        return gateways_services.Applied(ok=False, reason="")
    except IntegrityError as exc:
        diag = getattr(exc.__cause__, "diag", None)
        if getattr(diag, "constraint_name", None) != TRANSACTION_UNIQUE:
            raise
        return gateways_services.Applied(ok=False, reason="already_recorded")
    if row.status != TopUp.Status.PAID:
        row.status = TopUp.Status.PAID
        row.paid_at = timezone.now()
        row.save(update_fields=["status", "paid_at"])
    return gateways_services.Applied(ok=True)


def register() -> None:
    gateways_services.register_purpose(NAME, prepare=prepare, complete=complete)
```

`backend/etqan/wallet/apps.py`, add to `WalletConfig`:

```python
    def ready(self):
        # B3e E-15: the private `wallet_topup` purpose, paid through gateways.
        from etqan.wallet.services import topup_purpose  # noqa: PLC0415

        topup_purpose.register()
```

`backend/etqan/wallet/services/__init__.py`: add

```python
from etqan.wallet.services.online import start_top_up
from etqan.wallet.services.reads import family_wallets
from etqan.wallet.services.reads import topup_currencies
```

and `"family_wallets"`, `"start_top_up"`, `"topup_currencies"` to `__all__` (sorted).

- [ ] **Step 4: Run, format, lint, commit**

Run: `$DJ pytest etqan/wallet etqan/gateways -q`
Expected: PASS (gateways' own tests register their doubles beside the new purpose).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`
Expected: clean ("gateways imports no business app" now forbids `etqan.wallet`; the wallet reaches gateways through `gateways.services` only).

```bash
git -C backend add etqan/wallet
git -C backend commit -m "feat(wallet): the private wallet_topup purpose and the family's online top-up (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 8: The wallet API, the `wallet` resource and the route matrix

**Files:**
- Create: `backend/etqan/wallet/api/__init__.py`, `backend/etqan/wallet/api/serializers.py`, `backend/etqan/wallet/api/payloads.py`, `backend/etqan/wallet/api/views.py`, `backend/etqan/wallet/api/urls.py`, `backend/etqan/wallet/tests/test_api.py`
- Modify: `backend/config/api_router.py` (B3 marker), `backend/etqan/access/registry.py` (B3 marker), `backend/etqan/access/tests/test_registry.py`, `backend/etqan/access/tests/test_routes.py`, `backend/etqan/platform/tests/test_drf.py`

**Interfaces:**
- Consumes: Tasks 5–7's services.
- Produces (spec §5, under `/api/v1/wallet/`):
  - `GET mine/` → `[{student: {id, name}, balances: [{currency, balance_minor}], topup_currencies}]` (students and parents);
  - `GET students/<id>/` → `{student, balances}`; `GET students/<id>/entries/?currency=&page=` → paginated `{id, kind, currency, amount_minor, balance_after_minor, note, invoice_id, payment_id, session_id, created_at, reversed}` plus `created_by` for the office (`wallet.view_any`, or the family by E-17);
  - `POST students/<id>/top-ups/` `{amount_minor, currency, method, paid_on?, reference?}` (`wallet.create`); `POST students/<id>/adjustments/` `{amount_minor, currency, reason}` (`wallet.create` / `wallet.update` by sign);
  - `POST invoices/<id>/pay/` `{amount_minor?}` (`wallet.update` + `invoice.view`, or the family); `POST payments/<id>/move/` (`wallet.update` + `payment.update`); `POST payments/<id>/reverse/` (`wallet.update`) — each write answers 201 with the new entry (office shape);
  - `GET top-ups/options/?student=&currency=&amount_minor=` → `{currencies, providers}`; `POST top-ups/` `{student, amount_minor, currency, provider}` → 201 `{id, redirect_url, amount_minor, fee_minor, currency}` (non-atomic, throttle `gateway_start`);
  - access resource `wallet` ("Student balances" / "أرصدة الطلاب"), verbs in use `view_any`, `create`, `update`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/access/tests/test_registry.py`, in `test_resources_carry_the_12_verbs_and_the_role_resource_6`, after the `payment_method` assertion:

```python
    # Phase B3 (slice B3e, E-20).
    assert by_code["wallet"].in_use == ("view_any", "create", "update")
    assert (by_code["wallet"].label_en, by_code["wallet"].label_ar) == (
        "Student balances",
        "أرصدة الطلاب",
    )
```

`backend/etqan/access/tests/test_routes.py`:
- `ROUTES`, after the B3d rows (`("PUT", "/api/v1/billing/local-countries/ZZ/", "payment_method.update"),`):

```python
    # Phase B3, slice B3e: student balances (plan W14). mine/ and the online
    # top-up are SELF_SERVICE: families only, E-17 in the views.
    ("GET", f"/api/v1/wallet/students/{N}/", "wallet.view_any"),
    ("GET", f"/api/v1/wallet/students/{N}/entries/", "wallet.view_any"),
    ("POST", f"/api/v1/wallet/students/{N}/top-ups/", "wallet.create"),
    (
        "POST",
        f"/api/v1/wallet/students/{N}/adjustments/",
        ("wallet.create", "wallet.update"),
    ),
    ("POST", f"/api/v1/wallet/invoices/{N}/pay/", "wallet.update"),
    ("POST", f"/api/v1/wallet/payments/{N}/move/", "wallet.update"),
    ("POST", f"/api/v1/wallet/payments/{N}/reverse/", "wallet.update"),
```

- `FEATURES`, after the B3d `invoices` block:

```python
    # Phase B3, slice B3e.
    **dict.fromkeys(
        (
            ("GET", f"/api/v1/wallet/students/{N}/"),
            ("GET", f"/api/v1/wallet/students/{N}/entries/"),
            ("POST", f"/api/v1/wallet/students/{N}/top-ups/"),
            ("POST", f"/api/v1/wallet/students/{N}/adjustments/"),
            ("POST", f"/api/v1/wallet/invoices/{N}/pay/"),
            ("POST", f"/api/v1/wallet/payments/{N}/move/"),
            ("POST", f"/api/v1/wallet/payments/{N}/reverse/"),
        ),
        "balances",
    ),
```

- `FEATURE_WORDS`, after the B3d lines: `"/wallet/": "balances",  # B3e`.
- `SELF_SERVICE`, after the B3g gateways entries:

```python
    # Phase B3, slice B3e (plan W14): families only; E-17 in the views.
    "etqan.wallet.api.views.MyWalletsView": "a student's or parent's own wallets",
    "etqan.wallet.api.views.TopUpOptionsView": (
        "a family's top-up choices for a student it may use (E-17)"
    ),
    "etqan.wallet.api.views.StartTopUpView": (
        "a family tops up a student it may use (E-17); throttled"
    ),
```

`backend/etqan/platform/tests/test_drf.py`, in `test_non_atomic_views_and_routes_agree`, add `"StartTopUpView",` to the expected set (after `"PayPalWebhookView",`).

Create `backend/etqan/wallet/tests/test_api.py`:

```python
"""B3e §5, E-17, E-20..E-22, D19: the wallet routes, who reads and writes
them, what a family sees, impersonation, the features and isolation."""

import time
from datetime import date

import pytest
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.billing import services as billing_services
from etqan.billing.models import Payment
from etqan.billing.tests.conftest import make_parent
from etqan.platform.permissions import IMPERSONATOR_KEY
from etqan.platform.permissions import FEATURE_OFF
from etqan.scheduling.tests.conftest import make_student
from etqan.wallet import services
from etqan.wallet.models import TopUp
from etqan.wallet.models import Wallet
from etqan.wallet.models import WalletEntry
from etqan.wallet.tests.conftest import as_user
from etqan.wallet.tests.conftest import profile_id

pytestmark = pytest.mark.django_db
W = "/api/v1/wallet/"


def student_url(world, tail=""):
    return f"{W}students/{world.student.id}/{tail}"


def fund(world, admin, amount=30000, currency="EGP"):
    return services.top_up(
        world.student.id, amount_minor=amount, currency=currency, method="cash", by=admin
    )


def impersonated(client, admin):
    """``client``'s session marked as opened by ``admin`` (quick login)."""
    session = client.session
    session[IMPERSONATOR_KEY] = {
        "id": admin.pk,
        "hash": admin.get_session_auth_hash(),
        "since": time.time(),
    }
    session.save()
    return client


def test_the_office_reads_balances_and_the_statement(api_for, wallet_on, world, admin):
    fund(world, admin)
    services.adjust(world.student.id, amount_minor=-500, currency="EGP", reason="Typo", by=admin)
    office = api_for("admin")
    assert office.get(student_url(world)).json() == {
        "student": {"id": world.student.id, "name": "Yusuf"},
        "balances": [{"currency": "EGP", "balance_minor": 29500}],
    }
    body = office.get(student_url(world, "entries/")).json()
    assert body["count"] == 2
    first = body["results"][0]
    assert {k: first[k] for k in ("kind", "currency", "amount_minor", "balance_after_minor", "note")} == {
        "kind": "adjustment",
        "currency": "EGP",
        "amount_minor": -500,
        "balance_after_minor": 29500,
        "note": "Typo",
    }
    assert first["created_by"] == {"id": admin.pk, "full_name": admin.full_name}
    assert set(first) >= {"invoice_id", "payment_id", "session_id", "created_at", "reversed"}
    assert office.get(student_url(world, "entries/"), {"currency": "USD"}).json()["count"] == 0
    assert office.get(student_url(world, "entries/"), {"currency": "usd!"}).status_code == 400


def test_a_family_sees_no_names_and_no_adjustment_reason(api_for, wallet_on, world, admin, parent):
    fund(world, admin)
    services.adjust(world.student.id, amount_minor=500, currency="EGP", reason="Sorry", by=admin)
    for reader in (parent, world.student):
        rows = as_user(reader).get(student_url(world, "entries/")).json()["results"]
        assert [(r["kind"], r["note"]) for r in rows] == [("adjustment", ""), ("topup", "Cash")]
        assert all("created_by" not in r for r in rows)


def test_who_reads_a_students_wallet(api_for, staff_for, wallet_on, world, admin, parent):
    fund(world, admin)
    assert as_user(parent).get(student_url(world)).status_code == 200
    assert as_user(world.student).get(student_url(world)).status_code == 200
    assert staff_for("wallet.view_any").get(student_url(world)).status_code == 200
    sibling_payer = make_parent("Huda", make_student("Maryam"))
    assert as_user(sibling_payer).get(student_url(world)).status_code == 404
    assert as_user(make_student("Omar")).get(student_url(world)).status_code == 404
    assert api_for("teacher").get(student_url(world)).status_code == 403
    assert staff_for("wallet.create").get(student_url(world)).status_code == 403
    assert APIClient().get(student_url(world)).status_code == 403
    assert api_for("admin").get(f"{W}students/999999/").status_code == 404


def test_the_office_tops_up_and_bad_bodies_are_400s(staff_for, wallet_on, world):
    clerk = staff_for("wallet.create")
    good = {"amount_minor": 30000, "currency": "egp", "method": "cash", "reference": "R-1"}
    resp = clerk.post(student_url(world, "top-ups/"), good, format="json")
    assert resp.status_code == 201, resp.content
    assert (resp.json()["kind"], resp.json()["note"], resp.json()["currency"]) == (
        "topup",
        "Cash · R-1",
        "EGP",
    )
    assert Payment.objects.get(pk=resp.json()["payment_id"]).recorded_by == clerk.user
    for bad, field in (
        ({"amount_minor": "abc"}, "amount_minor"),
        ({"amount_minor": 0}, "amount_minor"),
        ({"amount_minor": 100_000_001}, "amount_minor"),
        ({"amount_minor": True}, "amount_minor"),
        ({"amount_minor": 1.5}, "amount_minor"),
        ({"method": "stripe"}, "method"),
        ({"method": "wallet"}, "method"),
        ({"currency": "US"}, "currency"),
        ({"paid_on": "2026-06-02"}, "paid_on"),
        ({"paid_on": "June"}, "paid_on"),
    ):
        resp = clerk.post(student_url(world, "top-ups/"), {**good, **bad}, format="json")
        assert resp.status_code == 400, (bad, resp.content)
        assert field in resp.json(), bad
    assert WalletEntry.objects.count() == 1
    assert staff_for("wallet.update").post(
        student_url(world, "top-ups/"), good, format="json"
    ).status_code == 403
    assert clerk.post(f"{W}students/999999/top-ups/", good, format="json").status_code == 404


def test_adjusting_needs_the_code_of_its_sign(staff_for, wallet_on, world, admin):
    fund(world, admin, 1000)
    url = student_url(world, "adjustments/")
    adder, taker = staff_for("wallet.create"), staff_for("wallet.update")
    plus = {"amount_minor": 500, "currency": "EGP", "reason": "Welcome credit"}
    minus = {**plus, "amount_minor": -500, "reason": "Typo"}
    assert adder.post(url, plus, format="json").status_code == 201
    assert adder.post(url, minus, format="json").status_code == 403
    assert taker.post(url, plus, format="json").status_code == 403
    assert taker.post(url, minus, format="json").status_code == 201
    over = taker.post(url, {**minus, "amount_minor": -5000}, format="json")
    assert (over.status_code, over.json()["code"]) == (409, "wallet.insufficient_balance")
    for bad, field in (
        ({"amount_minor": 0}, "amount_minor"),
        ({"reason": "   "}, "reason"),
        ({"reason": "x" * 501}, "reason"),
        ({"currency": "E"}, "currency"),
    ):
        resp = adder.post(url, {**plus, **bad}, format="json")
        assert resp.status_code == 400 and field in resp.json(), bad


def test_paying_an_invoice_by_route(api_for, staff_for, wallet_on, world, admin, invoice, parent):
    fund(world, admin)
    bill = invoice(amount_minor=10000)
    resp = as_user(parent).post(f"{W}invoices/{bill.pk}/pay/", {}, format="json")
    assert resp.status_code == 201, resp.content
    assert (resp.json()["kind"], resp.json()["amount_minor"]) == ("spend", -10000)
    lower = invoice(amount_minor=10000)
    url = f"{W}invoices/{lower.pk}/pay/"
    assert staff_for("wallet.update").post(url, {}, format="json").status_code == 404
    clerk = staff_for("wallet.update", "invoice.view")
    assert clerk.post(url, {"amount_minor": "x"}, format="json").status_code == 400
    resp = clerk.post(url, {"amount_minor": 2500}, format="json")
    assert (resp.status_code, resp.json()["amount_minor"]) == (201, -2500)
    over = clerk.post(url, {"amount_minor": 7501}, format="json")
    assert over.status_code == 400 and "amount_minor" in over.json()
    assert as_user(make_parent("Huda")).post(url, {}, format="json").status_code == 404
    assert api_for("teacher").post(url, {}, format="json").status_code == 403


def test_a_student_without_a_parent_pays_alone(wallet_on, world, admin, invoice):
    fund(world, admin)
    bill = invoice(amount_minor=1000)
    resp = as_user(world.student).post(f"{W}invoices/{bill.pk}/pay/", {}, format="json")
    assert resp.status_code == 201
    assert billing_services.invoices_queryset().get(pk=bill.pk).status == "paid"


def test_moving_needs_payment_update_after_the_lookup(staff_for, wallet_on, world, admin, invoice):
    bill = invoice(amount_minor=1000)
    cash = billing_services.add_payment(
        bill, amount_minor=1000, method="cash", paid_on=date(2026, 6, 1), by=admin
    )
    only = staff_for("wallet.update")
    assert only.post(f"{W}payments/999999/move/").status_code == 404
    assert only.post(f"{W}payments/{cash.pk}/move/").status_code == 403
    both = staff_for("wallet.update", "payment.update")
    resp = both.post(f"{W}payments/{cash.pk}/move/")
    assert (resp.status_code, resp.json()["kind"], resp.json()["amount_minor"]) == (201, "refund", 1000)
    again = both.post(f"{W}payments/{cash.pk}/move/")
    assert (again.status_code, again.json()["code"]) == (409, "billing.payment_not_completed")


def test_reversing_by_route(api_for, wallet_on, world, admin):
    top = fund(world, admin)
    office = api_for("admin")
    resp = office.post(f"{W}payments/{top.payment_id}/reverse/")
    assert (resp.status_code, resp.json()["kind"]) == (201, "reversal")
    rows = office.get(student_url(world, "entries/")).json()["results"]
    assert [(r["kind"], r["reversed"]) for r in rows] == [("reversal", False), ("topup", True)]
    record = billing_services.create_record(
        customer_type="unregistered", customer_name="Abu Khalid", amount_minor=1, method="cash", by=admin
    )
    other = office.post(f"{W}payments/{record.pk}/reverse/")
    assert (other.status_code, other.json()["code"]) == (409, "wallet.not_topup")


def test_paying_and_moving_need_invoices(api_for, set_features, wallet_on, world, admin, invoice):
    fund(world, admin)
    bill = invoice(amount_minor=1000)
    set_features(invoices=False)
    office = api_for("admin")
    for url in (f"{W}invoices/{bill.pk}/pay/", f"{W}payments/1/move/"):
        resp = office.post(url, {}, format="json")
        assert (resp.status_code, resp.json()) == (404, {"detail": FEATURE_OFF})


def test_every_family_route_is_404_with_balances_off(set_features, online_on, world, parent):
    set_features(balances=False)
    client = as_user(parent)
    for resp in (
        client.get(f"{W}mine/"),
        client.get(f"{W}top-ups/options/", {"student": world.student.id}),
        client.post(f"{W}top-ups/", {}, format="json"),
    ):
        assert (resp.status_code, resp.json()) == (404, {"detail": FEATURE_OFF})


def test_mine_is_for_students_and_parents(api_for, wallet_on, world, admin, parent):
    fund(world, admin)
    expected = [
        {
            "student": {"id": world.student.id, "name": "Yusuf"},
            "balances": [{"currency": "EGP", "balance_minor": 30000}],
            "topup_currencies": ["USD", "EGP"],
        }
    ]
    assert as_user(parent).get(f"{W}mine/").json() == expected
    assert as_user(world.student).get(f"{W}mine/").json() == expected
    for role in ("admin", "teacher"):
        assert api_for(role).get(f"{W}mine/").status_code == 403


def test_the_options_follow_the_providers(online_on, stripe_on, world, parent):
    client = as_user(parent)
    url = f"{W}top-ups/options/"
    query = {"student": world.student.id, "currency": "USD", "amount_minor": 5000}
    assert client.get(url, query).json() == {"currencies": ["USD"], "providers": ["stripe"]}
    assert client.get(url, {**query, "currency": "SAR"}).json()["providers"] == []
    assert client.get(url, {"student": world.student.id}).json() == {
        "currencies": ["USD"],
        "providers": [],
    }
    for bad in ({**query, "amount_minor": "x"}, {**query, "student": "y"}, {}):
        assert client.get(url, bad).status_code == 400, bad
    assert as_user(make_parent("Huda")).get(url, query).status_code == 404


def test_starting_a_top_up_by_route(set_features, online_on, stripe_on, world, parent, admin):
    body = {"student": world.student.id, "amount_minor": 5000, "currency": "USD", "provider": "stripe"}
    resp = as_user(parent).post(f"{W}top-ups/", body, format="json")
    assert resp.status_code == 201, resp.content
    assert {k: resp.json()[k] for k in ("amount_minor", "fee_minor", "currency")} == {
        "amount_minor": 5000,
        "fee_minor": 250,
        "currency": "USD",
    }
    assert resp.json()["redirect_url"]
    bad = as_user(parent).post(f"{W}top-ups/", {**body, "provider": "visa"}, format="json")
    assert bad.status_code == 400 and "provider" in bad.json()
    set_features(online_payments=False)
    off = as_user(parent).post(f"{W}top-ups/", body, format="json")
    assert (off.status_code, off.json()) == (404, {"detail": FEATURE_OFF})


def test_impersonated_sessions_move_no_money(api_for, set_features, online_on, stripe_on, world, admin, invoice, parent):
    set_features(quick_login=True)
    fund(world, admin)
    bill = invoice(amount_minor=1000)
    office = impersonated(api_for("admin"), admin)
    family = impersonated(as_user(parent), admin)
    for resp in (
        office.post(student_url(world, "top-ups/"), {"amount_minor": 1, "currency": "EGP", "method": "cash"}, format="json"),
        office.post(student_url(world, "adjustments/"), {"amount_minor": 1, "currency": "EGP", "reason": "x"}, format="json"),
        office.post(f"{W}payments/1/move/"),
        office.post(f"{W}payments/1/reverse/"),
        family.post(f"{W}invoices/{bill.pk}/pay/", {}, format="json"),
        family.post(f"{W}top-ups/", {"student": world.student.id, "amount_minor": 1, "currency": "USD", "provider": "stripe"}, format="json"),
    ):
        assert (resp.status_code, resp.json()["code"]) == (403, "identity.impersonating")
    assert office.get(student_url(world)).status_code == 200  # reading stays open
    assert services.balances_of(world.student.id) == [services.Balance("EGP", 30000)]


def test_no_route_edits_or_deletes_an_entry(api_for, wallet_on, world, admin):
    entry = fund(world, admin)
    office = api_for("admin")
    for method in ("put", "patch", "delete"):
        resp = getattr(office, method)(student_url(world, "entries/"), {}, format="json")
        assert resp.status_code == 405
    assert office.get(f"{W}entries/{entry.pk}/").status_code == 404


def test_another_academys_wallets_never_leak(api_for, wallet_on, world, admin, tenants, set_features):
    fund(world, admin)
    set_features(academy=tenants.other, balances=True)
    with tenant_context(tenants.other):
        assert not Wallet.objects.exists()
        assert not WalletEntry.objects.exists()
        assert not TopUp.objects.exists()
    assert Wallet.objects.get().student_id == profile_id(world.student)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/wallet/tests/test_api.py etqan/access etqan/platform/tests/test_drf.py -q`
Expected: FAIL (the routes 404; the registry lacks `wallet`).

- [ ] **Step 3: Implement the API**

Create `backend/etqan/wallet/api/__init__.py` (empty) and `backend/etqan/wallet/api/serializers.py`:

```python
"""Request bodies and list queries (B3e §5). Responses are built in
`payloads`. Bad input is a 400 on its field, never a 500."""

from rest_framework import serializers

from etqan.billing import services as billing_services
from etqan.wallet.models import MAX_TOPUP_MINOR

PROVIDERS = ("stripe", "paypal")


def _amount(**kwargs):
    return serializers.IntegerField(max_value=MAX_TOPUP_MINOR, **kwargs)


class EntriesQueryInput(serializers.Serializer):
    currency = serializers.RegexField(r"^[A-Z]{3}$", required=False)


class TopUpInput(serializers.Serializer):
    amount_minor = _amount(min_value=1)
    currency = serializers.CharField(max_length=3)
    method = serializers.ChoiceField(choices=billing_services.MANUAL_PAYMENT_METHODS)
    paid_on = serializers.DateField(required=False)
    reference = serializers.CharField(max_length=120, required=False, allow_blank=True)


class AdjustmentInput(serializers.Serializer):
    amount_minor = _amount(min_value=-MAX_TOPUP_MINOR)
    currency = serializers.CharField(max_length=3)
    reason = serializers.CharField(max_length=500)

    def validate_amount_minor(self, value):
        if value == 0:
            raise serializers.ValidationError("Enter an amount other than zero.")
        return value


class PayInput(serializers.Serializer):
    amount_minor = serializers.IntegerField(min_value=1, required=False)


class OptionsQueryInput(serializers.Serializer):
    student = serializers.IntegerField(min_value=1)
    currency = serializers.RegexField(r"^[A-Z]{3}$", required=False)
    amount_minor = _amount(min_value=1, required=False)


class StartInput(serializers.Serializer):
    student = serializers.IntegerField(min_value=1)
    amount_minor = _amount(min_value=1)
    currency = serializers.CharField(max_length=3)
    provider = serializers.ChoiceField(choices=PROVIDERS)
```

Create `backend/etqan/wallet/api/payloads.py`:

```python
"""JSON shapes for the wallet (B3e §5). The office sees who recorded each
entry; a family never does, nor an adjustment's reason (E-22)."""


def _person(user) -> dict | None:
    return None if user is None else {"id": user.pk, "full_name": user.full_name}


def balance_row(balance) -> dict:
    return {"currency": balance.currency, "balance_minor": balance.balance_minor}


def entry_row(entry, *, office: bool) -> dict:
    row = {
        "id": entry.pk,
        "kind": entry.kind,
        "currency": entry.wallet.currency,
        "amount_minor": entry.amount_minor,
        "balance_after_minor": entry.balance_after_minor,
        "note": entry.note,
        "invoice_id": entry.invoice_id,
        "payment_id": entry.payment_id,
        "session_id": entry.session_id,
        "created_at": entry.created_at,
        # Plan W13: a top-up already given back.
        "reversed": entry.kind == "topup" and bool(getattr(entry, "reversed", False)),
    }
    if office:
        row["created_by"] = _person(entry.created_by)
    elif entry.kind == "adjustment":
        row["note"] = ""
    return row


def student_wallet(student: dict, balances) -> dict:
    return {"student": student, "balances": [balance_row(b) for b in balances]}


def family_row(item: dict) -> dict:
    return {
        **student_wallet(item["student"], item["balances"]),
        "topup_currencies": item["topup_currencies"],
    }


def started(checkout) -> dict:
    return {
        "id": str(checkout.id),
        "redirect_url": checkout.redirect_url,
        "amount_minor": checkout.amount_minor,
        "fee_minor": checkout.fee_minor,
        "currency": checkout.currency,
    }
```

Create `backend/etqan/wallet/api/views.py`:

```python
"""Wallet endpoints (B3e §5). Thin: parse, call one service, answer. Every
write answers 201 with the new entry; the dashboard refetches the payment
and the invoice (no billing payload: `etqan.billing.api` is forbidden)."""

from rest_framework import generics
from rest_framework import status
from rest_framework.exceptions import NotFound
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from etqan.gateways import services as gateways_services
from etqan.platform import features
from etqan.platform.exceptions import NotFoundError
from etqan.platform.permissions import FEATURE_OFF
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.platform.permissions import IsParent
from etqan.platform.permissions import IsStudent
from etqan.platform.permissions import NotImpersonating
from etqan.platform.permissions import ReadOnly
from etqan.platform.permissions import codes_of
from etqan.platform.permissions import is_office
from etqan.platform.permissions import role_of
from etqan.wallet import services
from etqan.wallet.api import payloads
from etqan.wallet.api.serializers import AdjustmentInput
from etqan.wallet.api.serializers import EntriesQueryInput
from etqan.wallet.api.serializers import OptionsQueryInput
from etqan.wallet.api.serializers import PayInput
from etqan.wallet.api.serializers import StartInput
from etqan.wallet.api.serializers import TopUpInput

FEATURE = "balances"
FAMILY = IsParent | IsStudent
# E-20: the office by code; students and parents read, scoped by E-17.
READERS = HasCode | (ReadOnly & (IsParent | IsStudent))


def _need(feature: str) -> None:
    """A second feature a route also needs (E-21): 404 as a missing route."""
    if not features.enabled(feature):
        raise NotFound(FEATURE_OFF)


def _holds(user, code: str) -> bool:
    """Admins hold every code (E-20)."""
    return role_of(user) == "admin" or code in codes_of(user)


def _student(request, pk: int) -> dict:
    """The office passed `HasCode`; a family member must be E-17's (404
    otherwise, as for any student it may not see, plan W15)."""
    if not is_office(request.user) and not services.may_use(request.user, pk):
        raise NotFoundError("Student", pk)
    return services.student_of(pk)


def _created(entry) -> Response:
    return Response(
        payloads.entry_row(entry, office=True), status=status.HTTP_201_CREATED
    )


class MyWalletsView(APIView):
    """`wallet/mine/`: a student's own wallets, or a parent's children's."""

    permission_classes = [FAMILY, FeatureOn]
    feature = FEATURE

    def get(self, request):
        return Response(
            [payloads.family_row(row) for row in services.family_wallets(request.user)]
        )


class StudentWalletView(APIView):
    permission_classes = [READERS, FeatureOn]
    feature = FEATURE
    permission_codes = {"GET": "wallet.view_any"}

    def get(self, request, pk):
        student = _student(request, pk)
        return Response(payloads.student_wallet(student, services.balances_of(pk)))


class EntriesView(generics.GenericAPIView):
    permission_classes = [READERS, FeatureOn]
    feature = FEATURE
    permission_codes = {"GET": "wallet.view_any"}

    def get(self, request, pk):
        _student(request, pk)
        query = EntriesQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        entries = services.entries_of(pk, query.validated_data.get("currency"))
        office = is_office(request.user)
        page = self.paginate_queryset(entries)
        return self.get_paginated_response(
            [payloads.entry_row(e, office=office) for e in page]
        )


class TopUpsView(APIView):
    permission_classes = [HasCode, FeatureOn, NotImpersonating]
    feature = FEATURE
    permission_codes = {"POST": "wallet.create"}

    def post(self, request, pk):
        services.student_of(pk)
        body = TopUpInput(data=request.data)
        body.is_valid(raise_exception=True)
        return _created(services.top_up(pk, **body.validated_data, by=request.user))


class AdjustmentsView(APIView):
    """E-20, plan W11: either code passes the route; the sign is checked here."""

    permission_classes = [HasCode, FeatureOn, NotImpersonating]
    feature = FEATURE
    permission_codes = {"POST": ("wallet.create", "wallet.update")}

    def post(self, request, pk):
        services.student_of(pk)
        body = AdjustmentInput(data=request.data)
        body.is_valid(raise_exception=True)
        amount = body.validated_data["amount_minor"]
        needed = "wallet.create" if amount > 0 else "wallet.update"
        if not _holds(request.user, needed):
            raise PermissionDenied(f"This adjustment needs {needed}.")
        return _created(services.adjust(pk, **body.validated_data, by=request.user))


class PayView(APIView):
    """E-11, E-20: the office with wallet.update (and invoice.view, through
    `invoice_for`), or the family by E-17 (in the service)."""

    permission_classes = [HasCode | IsParent | IsStudent, FeatureOn, NotImpersonating]
    feature = FEATURE
    permission_codes = {"POST": "wallet.update"}

    def post(self, request, pk):
        _need("invoices")
        body = PayInput(data=request.data)
        body.is_valid(raise_exception=True)
        return _created(
            services.pay_invoice(
                pk, by=request.user, amount_minor=body.validated_data.get("amount_minor")
            )
        )


class MoveView(APIView):
    """E-12, E-20: also payment.update (as billing's refund), checked after
    the lookup so an unknown id is 404 first (plan W14)."""

    permission_classes = [HasCode, FeatureOn, NotImpersonating]
    feature = FEATURE
    permission_codes = {"POST": "wallet.update"}

    def post(self, request, pk):
        _need("invoices")
        services.find_payment(pk)
        if not _holds(request.user, "payment.update"):
            raise PermissionDenied("Moving a payment also needs payment.update.")
        return _created(services.move_to_wallet(pk, by=request.user))


class ReverseView(APIView):
    permission_classes = [HasCode, FeatureOn, NotImpersonating]
    feature = FEATURE
    permission_codes = {"POST": "wallet.update"}

    def post(self, request, pk):
        return _created(services.reverse_topup(pk, by=request.user))


class TopUpOptionsView(APIView):
    """`{currencies, providers}` for a student the family may use (E-18)."""

    permission_classes = [FAMILY, FeatureOn]
    feature = FEATURE

    def get(self, request):
        _need("online_payments")
        query = OptionsQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        data = query.validated_data
        if not services.may_use(request.user, data["student"]):
            raise NotFoundError("Student", data["student"])
        currencies = services.topup_currencies(data["student"])
        currency, amount = data.get("currency"), data.get("amount_minor")
        providers = (
            gateways_services.providers_for(currency, amount, add_fee=True)
            if currency in currencies and amount is not None
            else []
        )
        return Response({"currencies": currencies, "providers": providers})


class StartTopUpView(APIView):
    """E-15: non-atomic (see urls): the TopUp row and the pending checkout
    commit before the provider is called. Never a quick-login session (D19)."""

    permission_classes = [FAMILY, NotImpersonating, FeatureOn]
    feature = FEATURE
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "gateway_start"
    atomic_request = False

    def post(self, request):
        _need("online_payments")
        body = StartInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        started = services.start_top_up(
            data["student"],
            amount_minor=data["amount_minor"],
            currency=data["currency"],
            provider=data["provider"],
            user=request.user,
        )
        return Response(payloads.started(started), status=status.HTTP_201_CREATED)
```

Create `backend/etqan/wallet/api/urls.py`:

```python
from django.db import transaction
from django.urls import path

from etqan.wallet.api import views

app_name = "wallet"
urlpatterns = [
    path("mine/", views.MyWalletsView.as_view(), name="mine"),
    path("students/<int:pk>/", views.StudentWalletView.as_view(), name="student"),
    path("students/<int:pk>/entries/", views.EntriesView.as_view(), name="entries"),
    path("students/<int:pk>/top-ups/", views.TopUpsView.as_view(), name="top-ups"),
    path(
        "students/<int:pk>/adjustments/",
        views.AdjustmentsView.as_view(),
        name="adjustments",
    ),
    path("invoices/<int:pk>/pay/", views.PayView.as_view(), name="pay"),
    path("payments/<int:pk>/move/", views.MoveView.as_view(), name="move"),
    path("payments/<int:pk>/reverse/", views.ReverseView.as_view(), name="reverse"),
    path("top-ups/options/", views.TopUpOptionsView.as_view(), name="top-up-options"),
    path(
        "top-ups/",
        transaction.non_atomic_requests(views.StartTopUpView.as_view()),
        name="top-up-start",
    ),
]
```

`backend/config/api_router.py`, under `# ── phase B3 ──`, after the gateways line:

```python
    # mine/, students/, invoices/<id>/pay/, payments/<id>/move|reverse/,
    # top-ups/ (B3e spec §5).
    path("wallet/", include("etqan.wallet.api.urls")),
```

`backend/etqan/access/registry.py`, under `# ── phase B3 ──`, after the `payment_method` resource:

```python
    # B3e (E-20): student balances; admins hold it, teachers never.
    Resource(
        "wallet",
        "Student balances",
        "أرصدة الطلاب",
        ("view_any", "create", "update"),
    ),
```

- [ ] **Step 4: Run, format, lint, commit**

Run: `$DJ pytest etqan/wallet etqan/access etqan/platform -q`
Expected: PASS, including `test_every_route_declares_its_code_or_is_named_exempt`, the code matrix for the seven rows (with each code: not 403, since an unknown id is 404 and an empty body 400), `test_a_switched_off_feature_is_404_after_the_permission_check`, `test_every_route_of_a_built_feature_declares_it` (`/wallet/` → `balances`) and `test_non_atomic_views_and_routes_agree`.
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/wallet config/api_router.py etqan/access etqan/platform/tests/test_drf.py
git -C backend commit -m "feat(wallet): the wallet routes, the wallet resource and the route matrix (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 9: Seeds

**Files:**
- Create: `backend/etqan/tenants/seeds/wallet.py`, `backend/etqan/tenants/tests/test_seed_wallet.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (B3 marker), `backend/etqan/wallet/services/reads.py`, `backend/etqan/wallet/services/__init__.py`, `backend/etqan/tenants/tests/test_seed_dev.py`, `backend/etqan/tenants/tests/test_seed_links.py` (plan W19)

**Interfaces:**
- Consumes: `wallet.services.top_up`, `adjust`, `balances_of`, `entries_of`; `identity.services.people_queryset`.
- Produces: `wallet.services.has_entries() -> bool` (exported); `seed_wallet(subdomain: str) -> None`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/tenants/tests/test_seed_wallet.py`:

```python
"""B3e §8: Aisha Omar's demo balance (a cash top-up of EGP 300.00 today
and a "Welcome credit" of EGP 50.00), seeded once, after the payment-link
seeds; the other academy gets nothing."""

import pytest
from django.core.management import call_command
from django.db import connection
from django.test import override_settings
from django_tenants.utils import tenant_context

from etqan.identity import services as identity
from etqan.tenants.models import Academy
from etqan.wallet import services as wallet


def state():
    aisha = identity.people_queryset("student").get(full_name="Aisha Omar")
    return {
        "balances": wallet.balances_of(aisha.pk),
        "entries": [
            (e.kind, e.amount_minor, e.note) for e in wallet.entries_of(aisha.pk)
        ],
    }


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_gives_aisha_her_balance_once():
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        first = state()
        assert first == {
            "balances": [wallet.Balance("EGP", 35000)],
            "entries": [
                ("adjustment", 5000, "Welcome credit"),
                ("topup", 30000, "Cash"),
            ],
        }
    with tenant_context(other):
        assert not wallet.has_entries()
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert state() == first
```

`backend/etqan/tenants/tests/test_seed_links.py`, in `state()`, the records read becomes (plan W19):

```python
    records = [
        (p.customer_type, p.customer_name, p.method, p.amount_minor, p.invoice_id)
        for p in billing_services.payments_queryset().filter(
            invoice__isnull=True, wallet_topup=False
        )
    ]
```

`backend/etqan/tenants/tests/test_seed_dev.py`, in `test_seed_dev_invoices_the_seeded_subscriptions_once`, the revenue expectation becomes:

```python
        # B3g: plus the demo's standalone cash record (the academy currency);
        # B3e: plus Aisha's EGP 300.00 cash top-up (E-7: revenue on arrival).
        assert sorted(
            first[1]["revenue_this_month"], key=lambda row: row["currency"]
        ) == [
            {"currency": "EGP", "amount_minor": 230000},
            {"currency": "USD", "amount_minor": 40000},
        ]
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/tenants/tests/test_seed_wallet.py etqan/tenants/tests/test_seed_dev.py etqan/tenants/tests/test_seed_links.py -q`
Expected: FAIL (`has_entries` missing; no balance; EGP revenue 200000).

- [ ] **Step 3: Implement**

`backend/etqan/wallet/services/reads.py`, append:

```python
def has_entries() -> bool:
    """Whether this academy has any wallet entry (the seeds' guard)."""
    return WalletEntry.objects.exists()
```

and export it from `backend/etqan/wallet/services/__init__.py` (`from etqan.wallet.services.reads import has_entries`, `"has_entries"` in `__all__`).

Create `backend/etqan/tenants/seeds/wallet.py`:

```python
"""Phase B3, slice B3e (spec §8): Aisha Omar's balance on the demo academy:
a cash top-up of EGP 300.00 today and an adjustment of +EGP 50.00 ("Welcome
credit"). Wallet services only; skipped once the academy has any wallet
entry. Called after `seed_links`, which skips itself once any standalone
record exists (a top-up is one). No e2e journey reads Aisha."""

from etqan.identity import services as identity_services
from etqan.wallet import services as wallet_services

STUDENT = "Aisha Omar"
CURRENCY = "EGP"


def seed_wallet(subdomain: str) -> None:
    if subdomain != "demo" or wallet_services.has_entries():
        return
    aisha = (
        identity_services.people_queryset("student").filter(full_name=STUDENT).first()
    )
    if aisha is None:
        return
    wallet_services.top_up(
        aisha.pk, amount_minor=30000, currency=CURRENCY, method="cash", by=None
    )
    wallet_services.adjust(
        aisha.pk,
        amount_minor=5000,
        currency=CURRENCY,
        reason="Welcome credit",
        by=None,
    )
```

`backend/etqan/tenants/management/commands/seed_dev.py`: import `from etqan.tenants.seeds import wallet as wallet_seeds` (beside the other seed imports, sorted) and, under `# ── phase B3 ──`, after `countries_seeds.seed_countries(subdomain)` (so after `gateways_seeds.seed_links`):

```python
        wallet_seeds.seed_wallet(subdomain)
```

- [ ] **Step 4: Run, format, lint, commit**

Run: `$DJ pytest etqan/tenants -q`
Expected: PASS (`seed_links` still writes its Abu Khalid record: it runs first).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`
Expected: clean (tenants reaches the wallet through `etqan.wallet.services` only).

```bash
git -C backend add etqan/tenants etqan/wallet/services
git -C backend commit -m "feat(seeds): Aisha Omar's demo balance, after the payment-link seeds (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 10: Dashboard — billing reads the row flags; `credited` and `wallet`

**Files:**
- Modify: `dashboard/src/features/billing/schemas.ts`, `InvoicePage.tsx`, `PaymentRecordsPage.tsx`, `InvoicePrint.tsx`, `InvoicePage.test.tsx`, `PaymentRecordsPage.test.tsx`, `InvoicePrint.test.tsx`, `schemas.test.ts`, `dashboard/src/test/billing-fixtures.ts`, `dashboard/src/locales/en/billing.json`, `dashboard/src/locales/ar/billing.json`, `dashboard/src/locales/en/errors.json`, `dashboard/src/locales/ar/errors.json`

**Interfaces:**
- Consumes: Task 4's payment rows.
- Produces:
  - `WALLET_METHOD = "wallet"`; `Payment.method: PaymentMethod | OnlineMethod | "wallet"`; `Payment.status: "completed" | "refunded" | "credited"`; `Payment.refundable: boolean`, `Payment.wallet_topup: boolean`;
  - `completedPayments(invoice)` keeps `status === "completed"` only (Void and the amount edit follow);
  - `InvoicePage` prop `paymentActions?: (payment: Payment) => ReactNode` (plan W20); rows read `deletable` / `refundable`; a refunded or credited row shows its chip and "Refunded on …" / "Moved on …";
  - `PaymentRecordsPage`: rows read the flags; "Balance top-up" chip; status filter gains `credited`; method filter gains `wallet`;
  - `InvoicePrint`: `credited` is "Moved to balance";
  - fixtures `paymentRow` default `refundable: true`, `wallet_topup: false`.

- [ ] **Step 1: Write the failing tests and the fixture fields**

`dashboard/src/test/billing-fixtures.ts`, in `paymentRow`'s object, after `deletable: true,`:

```ts
		refundable: true,
		wallet_topup: false,
```

`dashboard/src/features/billing/schemas.test.ts`: add `completedPayments` to the import from `"./schemas"`, add the import `import { invoiceDetail, paymentRow } from "@/test/billing-fixtures";`, and append:

```ts
describe("completedPayments (B3e E-10)", () => {
	it("keeps only completed payments, so a moved one frees Void and the amount", () => {
		const invoice = invoiceDetail({
			payments: [
				paymentRow({ id: 1 }),
				paymentRow({ id: 2, status: "refunded" }),
				paymentRow({ id: 3, status: "credited" }),
			],
		});
		expect(completedPayments(invoice).map((p) => p.id)).toEqual([1]);
	});
});
```

`dashboard/src/features/billing/InvoicePage.test.tsx` — the server now decides the row actions, so three existing tests send the flags it would send:
- in "refunds a payment, and never deletes an online one", the `card` row gains `deletable: false,` (after `reference: "",`);
- in "shows a refunded payment as refunded, with no actions", the row gains `refundable: false,`;
- in "reads the refund rows in Arabic", the second (refunded) row gains `refundable: false,`.

Append inside `describe("InvoicePage", …)`:

```tsx
	it("reads the row flags: a balance payment and a moved one offer nothing", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({
				payments: [
					paymentRow({
						id: 63,
						method: "wallet",
						reference: "",
						deletable: false,
						refundable: false,
					}),
					paymentRow({
						id: 64,
						status: "credited",
						refunded_at: "2026-06-03T21:30:00Z",
						reference: "MV-1",
						deletable: false,
						refundable: false,
					}),
				],
			}),
		);
		renderPage();
		const fromBalance = (await screen.findByText(/· Balance/)).closest(
			"li",
		) as HTMLElement;
		expect(within(fromBalance).queryByRole("button")).toBeNull();
		const moved = screen.getByText("Moved to balance").closest(
			"li",
		) as HTMLElement;
		// The academy is in Asia/Tokyo: 21:30 UTC on 3 June is 4 June there.
		expect(
			await within(moved).findByText("Moved on Jun 4, 2026"),
		).toBeVisible();
		expect(within(moved).queryByRole("button")).toBeNull();
	});

	it("dates a refunded payment in the academy's timezone", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({
				payments: [
					paymentRow({
						status: "refunded",
						refunded_at: "2026-06-03T21:30:00Z",
						refundable: false,
					}),
				],
			}),
		);
		renderPage();
		expect(await screen.findByText("Refunded on Jun 4, 2026")).toBeVisible();
	});

	it("renders the route's payment actions on each payment (B3e)", async () => {
		renderWithRouter(
			<InvoicePage
				invoiceId="51"
				admin
				paymentActions={(payment) => <span>{`move ${payment.id}`}</span>}
			/>,
			{ extraPaths: [PRINT, SUBSCRIPTION] },
		);
		expect(await screen.findByText("move 61")).toBeVisible();
	});

	it("reads a moved payment in Arabic", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({
				payments: [
					paymentRow({
						method: "wallet",
						status: "credited",
						refunded_at: "2026-06-03T00:00:00Z",
						deletable: false,
						refundable: false,
					}),
				],
			}),
		);
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		try {
			renderPage();
			expect(await screen.findByText("نُقلت إلى الرصيد")).toBeInTheDocument();
			expect(screen.getByText(/· الرصيد/)).toBeInTheDocument();
		} finally {
			await act(async () => {
				await i18n.changeLanguage("en");
			});
		}
	});
```

`dashboard/src/features/billing/PaymentRecordsPage.test.tsx`, append inside the `describe`:

```tsx
	it("reads the row flags, marks top-ups and filters moved payments", async () => {
		vi.mocked(billingApi.records).mockResolvedValue(
			page([
				paymentRow({
					id: 70,
					status: "credited",
					deletable: false,
					refundable: false,
				}),
				recordRow({
					id: 71,
					customer: {
						type: "student",
						name: "Yusuf",
						student_id: 11,
						email: "",
						phone: "",
					},
					wallet_topup: true,
					editable: false,
					deletable: false,
					refundable: true,
				}),
			]),
		);
		const user = userEvent.setup();
		renderWithRouter(<PaymentRecordsPage />, { extraPaths: [DETAIL] });
		const table = await screen.findByRole("table");
		expect(within(table).getByText("Balance top-up")).toBeVisible();
		expect(within(table).getByText("Moved to balance")).toBeVisible();
		expect(within(table).queryByRole("button", { name: "Edit" })).toBeNull();
		expect(within(table).queryByRole("button", { name: "Delete" })).toBeNull();
		// The server says the top-up row is refundable here; the page obeys.
		expect(
			within(table).getAllByRole("button", { name: "Mark refunded" }),
		).toHaveLength(1);
		await user.selectOptions(screen.getByLabelText("Status"), "credited");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({ status: "credited", page: 1 }),
		);
		await user.selectOptions(screen.getByLabelText("Method"), "wallet");
		await waitFor(() => expect(lastParams()).toMatchObject({ method: "wallet" }));
	});
```

`dashboard/src/features/billing/InvoicePrint.test.tsx`, append inside the `describe`:

```tsx
	it("marks a payment moved to the balance on the receipt", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({
				payments: [
					paymentRow({
						status: "credited",
						refunded_at: "2026-06-03T00:00:00Z",
					}),
				],
			}),
		);
		renderWithRouter(<InvoicePrint invoiceId="51" />);
		const sheet = await screen.findByRole("article", { name: "Invoice" });
		const row = within(sheet)
			.getByText(/InstaPay/)
			.closest("li") as HTMLElement;
		expect(within(row).getByText("Moved to balance")).toBeInTheDocument();
	});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/billing`
Expected: FAIL (type errors on `refundable`, `"credited"`, `paymentActions`; "Moved to balance" not found).

- [ ] **Step 3: Implement**

`dashboard/src/features/billing/schemas.ts`:
- after `export type OnlineMethod = …`:

```ts
/** B3e E-8: paid from the student's balance; never by hand. */
export const WALLET_METHOD = "wallet" as const;
```

- in `Payment`: `method: PaymentMethod | OnlineMethod | typeof WALLET_METHOD;`, `status: "completed" | "refunded" | "credited";`, and replace the six lines from `refunded_at: string | null;` through `deletable: boolean;` (with their two comments) with:

```ts
	/** B3e E-8: a move stamps it too (the date reads "Moved on"). */
	refunded_at: string | null;
	created_at: string;
	/** B3e E-10: the server's flags; no page re-derives them from `method`. */
	editable: boolean;
	deletable: boolean;
	refundable: boolean;
	/** B3e: money put into a student's balance. */
	wallet_topup: boolean;
```

- replace `completedPayments`:

```ts
/** B3b B-9, B3e E-10: only completed payments count; a refunded one, or one
 * moved to the balance, doesn't. */
export function completedPayments(invoice: InvoiceDetail): Payment[] {
	return invoice.payments.filter((payment) => payment.status === "completed");
}
```

`dashboard/src/features/billing/InvoicePage.tsx`:
- imports: drop `ONLINE_METHODS` from the `./schemas` import; add `import { useAcademySettings } from "@/features/academy/queries";` and `dayIn` to the `@/lib/zoned-time` import (`import { dayIn, formatDay } from "@/lib/zoned-time";`).
- below `type InvoiceActions = …`:

```tsx
/** B3e (plan W20): a route's per-payment actions (Move to balance), so
 * billing never imports the wallet. */
type PaymentActions = (payment: Payment) => ReactNode;
```

- replace `Payments`:

```tsx
function Payments({
	invoice,
	admin,
	paymentActions,
}: {
	invoice: InvoiceDetail;
	admin: boolean;
	paymentActions?: PaymentActions;
}) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const { data: academy } = useAcademySettings();
	const remove = useBillingMutation(billingApi.deletePayment);
	const refund = useBillingMutation(billingApi.refund);
	const canDelete = admin && invoice.status !== "void" && can("payment.delete");
	const canRefund = admin && can("payment.update");
	// B3e (W20): when a refund or a move happened, in the academy's calendar.
	const stamped = (payment: Payment) =>
		payment.status !== "completed" && payment.refunded_at && academy
			? t(
					payment.status === "credited"
						? "billing.payments.movedOn"
						: "billing.payments.refundedOn",
					{
						date: dayIn(
							new Date(payment.refunded_at),
							academy.timezone,
							i18n.language,
						),
					},
				)
			: "";
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("billing.payments.title")}</CardTitle>
			</CardHeader>
			<CardContent>
				{invoice.payments.length === 0 ? (
					<p className="text-sm text-muted-foreground">
						{t("billing.payments.none")}
					</p>
				) : (
					<ul className="flex flex-col divide-y divide-border">
						{invoice.payments.map((payment) => {
							const amount = formatMoney(
								payment.amount_minor,
								invoice.currency,
								i18n.language,
							);
							const when = stamped(payment);
							return (
								<li
									key={payment.id}
									className="flex flex-wrap items-center justify-between gap-2 py-3"
								>
									<div className="flex flex-col gap-0.5 text-sm">
										<span className="flex flex-wrap items-center gap-2 font-medium">
											<span>
												<span dir="ltr">{amount}</span> ·{" "}
												{t(`billing.methods.${payment.method}`)}
												{payment.fee_minor > 0
													? ` · ${t("billing.payments.fee", {
															amount: formatMoney(
																payment.fee_minor,
																invoice.currency,
																i18n.language,
															),
														})}`
													: ""}
											</span>
											{payment.status !== "completed" ? (
												<StatusChip tone="neutral">
													{t(`billing.payments.${payment.status}`)}
												</StatusChip>
											) : null}
										</span>
										<span className="text-muted-foreground">
											{formatDay(payment.paid_on, i18n.language)}
											{payment.reference ? ` · ${payment.reference}` : ""}
											{payment.transaction_number ? (
												<>
													{" · "}
													<span dir="ltr">{payment.transaction_number}</span>
												</>
											) : null}
										</span>
										{when ? (
											<span className="text-muted-foreground">{when}</span>
										) : null}
										{payment.notes ? (
											<span className="text-muted-foreground">
												{payment.notes}
											</span>
										) : null}
									</div>
									<div className="flex flex-wrap gap-2">
										{paymentActions?.(payment)}
										{canRefund && payment.refundable ? (
											<Confirm
												action={t("billing.payments.refund")}
												title={t("billing.payments.refundTitle")}
												body={t("billing.payments.refundBody")}
												onConfirm={() =>
													refund.mutate(payment.id, {
														onSuccess: () =>
															toast({
																description: t("billing.payments.refundDone"),
																variant: "success",
															}),
														onError: (error) =>
															toast({
																description: errorText(error, t),
																variant: "destructive",
															}),
													})
												}
											/>
										) : null}
										{canDelete && payment.deletable ? (
											<Confirm
												action={t("billing.payments.delete", { amount })}
												title={t("billing.payments.deleteTitle")}
												body={t("billing.payments.deleteBody")}
												onConfirm={() =>
													remove.mutate(payment.id, {
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
								</li>
							);
						})}
					</ul>
				)}
			</CardContent>
		</Card>
	);
}
```

- `InvoicePage`'s props gain `paymentActions` (after `actions`):

```tsx
	/** B3e: per-payment actions from the route (Move to balance). */
	paymentActions?: PaymentActions;
```

  (destructure it beside `actions`) and the last child becomes `<Payments invoice={invoice} admin={admin} paymentActions={paymentActions} />`.

`dashboard/src/features/billing/PaymentRecordsPage.tsx`:
- the schemas import becomes `import { ONLINE_METHODS, PAYMENT_METHODS, type Payment, WALLET_METHOD } from "./schemas";`
- in `RowActions`, the refund condition `row.status === "completed" && can("payment.update")` becomes `row.refundable && can("payment.update")`;
- the method filter's options become `[...PAYMENT_METHODS, ...ONLINE_METHODS, WALLET_METHOD].map(…)`; the status filter's `(["completed", "refunded"] as const)` becomes `(["completed", "refunded", "credited"] as const)`;
- the method cell becomes:

```tsx
									<td className="px-2 py-2">
										<span className="flex flex-wrap items-center gap-1">
											{t(`billing.methods.${row.method}`)}
											{row.wallet_topup ? (
												<StatusChip tone="neutral">
													{t("billing.records.topUp")}
												</StatusChip>
											) : null}
										</span>
									</td>
```

`dashboard/src/features/billing/InvoicePrint.tsx`, in the payments list replace

```tsx
										{payment.status === "refunded" ? (
											<>
												{" · "}
												<strong>{t("billing.payments.refunded")}</strong>
											</>
										) : null}
```

with

```tsx
										{payment.status !== "completed" ? (
											<>
												{" · "}
												<strong>{t(`billing.payments.${payment.status}`)}</strong>
											</>
										) : null}
```

Locales — `dashboard/src/locales/en/billing.json`:
- `methods`: after `"other": "Other"` add `"wallet": "Balance"`;
- `payments`: after `"refunded": "Refunded",` add `"credited": "Moved to balance", "refundedOn": "Refunded on {{date}}", "movedOn": "Moved on {{date}}",`;
- `records.status`: add `"credited": "Moved to balance"`; `records`: add `"topUp": "Balance top-up"`.

`dashboard/src/locales/ar/billing.json`, the same keys:
- `methods.wallet`: `"الرصيد"`;
- `payments.credited`: `"نُقلت إلى الرصيد"`, `payments.refundedOn`: `"استُردت في {{date}}"`, `payments.movedOn`: `"نُقلت في {{date}}"`;
- `records.status.credited`: `"نُقلت إلى الرصيد"`; `records.topUp`: `"شحن الرصيد"`.

`dashboard/src/locales/en/errors.json`, in `billing`, add:

```json
		"wallet_payment": "A payment from the balance is moved back to the balance, not refunded or deleted.",
		"wallet_topup": "A balance top-up is reversed from the student's balance, not refunded or deleted here.",
		"payment_credited": "This payment was moved to the balance.",
		"payment_not_completed": "Only a completed payment can be moved to the balance.",
		"not_topup": "This payment is not a balance top-up."
```

`dashboard/src/locales/ar/errors.json`, in `billing`, add:

```json
		"wallet_payment": "الدفعة من الرصيد تُعاد إلى الرصيد، ولا تُسترد ولا تُحذف.",
		"wallet_topup": "شحن الرصيد يُعكس من رصيد الطالب، ولا يُسترد ولا يُحذف هنا.",
		"payment_credited": "نُقلت هذه الدفعة إلى الرصيد.",
		"payment_not_completed": "لا تُنقل إلى الرصيد إلا دفعة مكتملة.",
		"not_topup": "هذه الدفعة ليست شحنًا للرصيد."
```

- [ ] **Step 4: Run, type-check, lint, commit**

Run: `$DASH pnpm vitest run src/features/billing src/locales`
Expected: PASS.
Run: `just test-frontend && just lint-frontend`

```bash
git -C dashboard add src/features/billing src/test/billing-fixtures.ts src/locales
git -C dashboard commit -m "feat(billing): pages read the server's payment flags; credited and wallet payments (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 11: Dashboard — the wallet feature's base and the statement

**Files:**
- Create: `dashboard/src/features/wallet/schemas.ts`, `api.ts`, `queries.ts`, `Statement.tsx`, `index.ts`, `schemas.test.ts`, `api.test.ts`, `Statement.test.tsx`, `dashboard/src/test/wallet-fixtures.ts`, `dashboard/src/locales/en/wallet.json`, `dashboard/src/locales/ar/wallet.json`
- Modify: `dashboard/src/features/identity/schemas.ts`, `dashboard/src/locales/en/errors.json`, `dashboard/src/locales/ar/errors.json`

**Interfaces:**
- Consumes: Task 8's routes.
- Produces:
  - `FeatureCode` gains `"balances"`;
  - types `EntryKind`, `Balance`, `StudentRef`, `StudentWallet`, `FamilyWallet`, `WalletEntry` (with `reversed`, office-only `created_by`), `TopUpBody`, `AdjustmentBody`, `TopUpOptions`, `StartTopUpBody`; `MAX_TOPUP_MINOR`;
  - `amountIssue(text, currency, { signed? }) -> string | null` (an i18n key or null); form schemas `topUpFormSchema` / `TopUpFormValues`, `adjustFormSchema` / `AdjustFormValues`, `payFormSchema(available, due, currency)` / `PayFormValues`, `onlineTopUpSchema` / `OnlineTopUpValues`;
  - `walletApi.{mine, student, entries, topUp, adjust, payInvoice, move, reverse, topUpOptions, startTopUp}`;
  - `walletKey = ["wallet"]`; `useMyWallets()`, `useStudentWallet(id, enabled?)`, `useEntries(id, currency, page)`, `useTopUpOptions(params, enabled)`, `useWalletMutation(write)` (refreshes wallet, billing and scheduling);
  - `<Statement studentId currency office />`;
  - fixtures `walletEntry()`, `studentWallet()`, `familyWallet()`.

- [ ] **Step 1: Write the failing tests and fixtures**

`dashboard/src/features/identity/schemas.ts`, in `FeatureCode`, after the B3d lines (`| "country_pricing"`):

```ts
	// Phase B3, slice B3e.
	| "balances"
```

Create `dashboard/src/test/wallet-fixtures.ts`:

```ts
import type {
	FamilyWallet,
	StudentWallet,
	WalletEntry,
} from "@/features/wallet/schemas";

/** API-shaped wallet rows (the office's view: with `created_by`). */
export function walletEntry(overrides: Partial<WalletEntry> = {}): WalletEntry {
	return {
		id: 81,
		kind: "topup",
		currency: "EGP",
		amount_minor: 30000,
		balance_after_minor: 30000,
		note: "Cash",
		invoice_id: null,
		payment_id: 91,
		session_id: null,
		created_at: "2026-06-01T21:30:00Z",
		reversed: false,
		created_by: { id: 1, full_name: "Amina" },
		...overrides,
	};
}

export function studentWallet(
	overrides: Partial<StudentWallet> = {},
): StudentWallet {
	return {
		student: { id: 11, name: "Yusuf" },
		balances: [
			{ currency: "EGP", balance_minor: 30000 },
			{ currency: "USD", balance_minor: 5000 },
		],
		...overrides,
	};
}

export function familyWallet(
	overrides: Partial<FamilyWallet> = {},
): FamilyWallet {
	return { ...studentWallet(), topup_currencies: ["EGP", "USD"], ...overrides };
}
```

Create `dashboard/src/features/wallet/schemas.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
	adjustFormSchema,
	amountIssue,
	onlineTopUpSchema,
	payFormSchema,
	topUpFormSchema,
} from "./schemas";

const topUp = (amount: string, currency = "EGP") =>
	topUpFormSchema.safeParse({
		amount,
		currency,
		method: "cash",
		paid_on: "2026-06-01",
		reference: "",
	});

describe("amountIssue (E-19)", () => {
	it("takes a positive amount in the currency's minor units, up to the cap", () => {
		expect(amountIssue("300", "EGP")).toBeNull();
		expect(amountIssue("300.5", "EGP")).toBeNull();
		expect(amountIssue("1000000.00", "EGP")).toBeNull();
		expect(amountIssue("100000000", "JPY")).toBeNull();
		expect(amountIssue("1.234", "KWD")).toBeNull();
	});

	it("names what is wrong", () => {
		expect(amountIssue("", "EGP")).toBe("billing.errors.required");
		expect(amountIssue("0", "EGP")).toBe("billing.errors.amountInvalid");
		expect(amountIssue("-5", "EGP")).toBe("billing.errors.amountInvalid");
		expect(amountIssue("1.005", "EGP")).toBe("billing.errors.amountInvalid");
		expect(amountIssue("5.5", "JPY")).toBe("billing.errors.amountInvalid");
		expect(amountIssue("abc", "EGP")).toBe("billing.errors.amountInvalid");
		expect(amountIssue("1000000.01", "EGP")).toBe("wallet.errors.tooMuch");
	});

	it("takes a signed amount for an adjustment, never 0", () => {
		expect(amountIssue("-5", "EGP", { signed: true })).toBeNull();
		expect(amountIssue("-0", "EGP", { signed: true })).toBe(
			"billing.errors.amountInvalid",
		);
		expect(amountIssue("-1000000.01", "EGP", { signed: true })).toBe(
			"wallet.errors.tooMuch",
		);
	});
});

describe("the wallet's form schemas", () => {
	it("checks a top-up's amount against its own currency", () => {
		expect(topUp("300.00").success).toBe(true);
		expect(topUp("300.5", "JPY").success).toBe(false);
		expect(topUp("300", "").success).toBe(false);
	});

	it("needs a reason of up to 500 characters for an adjustment", () => {
		const base = { amount: "-5", currency: "EGP" };
		expect(adjustFormSchema.safeParse({ ...base, reason: "Typo" }).success).toBe(
			true,
		);
		expect(adjustFormSchema.safeParse({ ...base, reason: "  " }).success).toBe(
			false,
		);
		expect(
			adjustFormSchema.safeParse({ ...base, reason: "x".repeat(501) }).success,
		).toBe(false);
	});

	it("bounds a payment by the balance first, then the amount due", () => {
		const schema = payFormSchema(30000, 20000, "EGP");
		expect(schema.safeParse({ amount: "200.00" }).success).toBe(true);
		const overDue = schema.safeParse({ amount: "250.00" });
		expect(overDue.error?.issues[0].message).toBe("billing.errors.overBalance");
		const overWallet = schema.safeParse({ amount: "300.01" });
		expect(overWallet.error?.issues[0].message).toBe("wallet.errors.overBalance");
	});

	it("checks an online top-up's amount", () => {
		expect(
			onlineTopUpSchema.safeParse({ amount: "50", currency: "USD" }).success,
		).toBe(true);
		expect(
			onlineTopUpSchema.safeParse({ amount: "0", currency: "USD" }).success,
		).toBe(false);
	});
});
```

Create `dashboard/src/features/wallet/api.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { walletApi } from "./api";

vi.mock("@/lib/api", async (orig) => {
	const actual = await orig<typeof import("@/lib/api")>();
	return {
		...actual,
		api: { get: vi.fn(), post: vi.fn() },
	};
});

describe("walletApi (spec §5)", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(api.get).mockResolvedValue({ data: "read" });
		vi.mocked(api.post).mockResolvedValue({ data: "written" });
	});

	it("reads the family's wallets, a student's and their statement", async () => {
		await walletApi.mine();
		await walletApi.student(11);
		await walletApi.entries(11, { currency: "EGP", page: 2 });
		await walletApi.topUpOptions({ student: 11, currency: "USD" });
		expect(vi.mocked(api.get).mock.calls).toEqual([
			["wallet/mine/"],
			["wallet/students/11/"],
			["wallet/students/11/entries/", { params: { currency: "EGP", page: "2" } }],
			["wallet/top-ups/options/", { params: { student: "11", currency: "USD" } }],
		]);
	});

	it("posts each write to its route", async () => {
		const body = { amount_minor: 100, currency: "EGP" };
		await walletApi.topUp({
			studentId: 11,
			...body,
			method: "cash",
			paid_on: "2026-06-01",
			reference: "",
		});
		await walletApi.adjust({ studentId: 11, ...body, reason: "Typo" });
		await walletApi.payInvoice({ invoiceId: 51 });
		await walletApi.payInvoice({ invoiceId: 51, amount_minor: 500 });
		await walletApi.move(61);
		await walletApi.reverse(62);
		await walletApi.startTopUp({ student: 11, ...body, provider: "stripe" });
		expect(vi.mocked(api.post).mock.calls).toEqual([
			[
				"wallet/students/11/top-ups/",
				{ ...body, method: "cash", paid_on: "2026-06-01", reference: "" },
			],
			["wallet/students/11/adjustments/", { ...body, reason: "Typo" }],
			["wallet/invoices/51/pay/", {}],
			["wallet/invoices/51/pay/", { amount_minor: 500 }],
			["wallet/payments/61/move/"],
			["wallet/payments/62/reverse/"],
			["wallet/top-ups/", { student: 11, ...body, provider: "stripe" }],
		]);
	});
});
```

(`clean` from `src/lib/api.ts` drops blanks and turns every value into a string, hence `page: "2"` and `student: "11"`.)

Create `dashboard/src/features/wallet/Statement.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { walletEntry } from "@/test/wallet-fixtures";
import { walletApi } from "./api";
import { Statement } from "./Statement";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		walletApi: { ...actual.walletApi, entries: vi.fn(), reverse: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const OFFICE_INVOICE = "/billing/invoices/$invoiceId";
const FAMILY_INVOICE = "/learning/invoices/$invoiceId";
const ROWS = [
	walletEntry({
		id: 83,
		kind: "spend",
		amount_minor: -20000,
		balance_after_minor: 15000,
		note: "INV-000051",
		invoice_id: 51,
		payment_id: 93,
	}),
	walletEntry({
		id: 82,
		kind: "adjustment",
		amount_minor: 5000,
		balance_after_minor: 35000,
		note: "Welcome credit",
		payment_id: null,
	}),
	walletEntry(),
];

function renderStatement(office = true) {
	return renderWithRouter(
		<Statement studentId={11} currency="EGP" office={office} />,
		{ extraPaths: [OFFICE_INVOICE, FAMILY_INVOICE] },
	);
}

describe("Statement", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ timezone: "Asia/Tokyo" }),
		);
		vi.mocked(walletApi.entries).mockResolvedValue(page(ROWS));
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("lists the office's statement newest first, in the academy's timezone", async () => {
		renderStatement();
		const table = await screen.findByRole("table");
		expect(walletApi.entries).toHaveBeenCalledWith(11, {
			currency: "EGP",
			page: 1,
		});
		const rows = within(table).getAllByRole("row");
		expect(rows).toHaveLength(4);
		expect(within(rows[1]).getByText("Paid an invoice")).toBeVisible();
		expect(
			within(rows[1]).getByRole("link", { name: "INV-000051" }),
		).toHaveAttribute("href", "/billing/invoices/51");
		expect(within(rows[1]).getByText("-EGP 200.00")).toBeVisible();
		expect(within(rows[2]).getByText("Welcome credit")).toBeVisible();
		// 21:30 UTC on 1 June is 2 June in Tokyo.
		expect(await within(rows[3]).findByText("Jun 2, 2026")).toBeVisible();
		expect(within(rows[3]).getByText("+EGP 300.00")).toBeVisible();
		expect(within(rows[3]).getByText("Amina")).toBeVisible();
		expect(
			within(rows[3]).getByRole("button", { name: "Reverse" }),
		).toBeVisible();
		expect(within(rows[1]).queryByRole("button")).toBeNull();
	});

	it("reverses a top-up after confirming, and says why the server refused", async () => {
		const user = userEvent.setup();
		vi.mocked(walletApi.reverse)
			.mockRejectedValueOnce(
				new AxiosError("Refused", "409", undefined, undefined, {
					status: 409,
					data: { detail: "x", code: "wallet.insufficient_balance" },
				} as never),
			)
			.mockResolvedValueOnce(walletEntry({ kind: "reversal" }));
		renderStatement();
		const reverse = async () => {
			await user.click(await screen.findByRole("button", { name: "Reverse" }));
			await user.click(
				within(await screen.findByRole("alertdialog")).getByRole("button", {
					name: "Give this top-up back",
				}),
			);
		};
		await reverse();
		expect(
			await screen.findByText("The balance does not cover this."),
		).toBeVisible();
		await reverse();
		await waitFor(() => expect(walletApi.reverse).toHaveBeenLastCalledWith(91));
		expect(await screen.findByText("Top-up reversed.")).toBeVisible();
	});

	it("hides Reverse without wallet.update and on a top-up already given back", async () => {
		vi.mocked(walletApi.entries).mockResolvedValue(
			page([walletEntry({ reversed: true }), walletEntry({ id: 84 })]),
		);
		const { unmount } = renderStatement();
		await screen.findByRole("table");
		expect(screen.getAllByRole("button", { name: "Reverse" })).toHaveLength(1);
		unmount();
		renderWithRouter(
			<CanProvider me={staffMe("wallet.view_any")}>
				<Statement studentId={11} currency="EGP" office />
			</CanProvider>,
		);
		await screen.findByRole("table");
		expect(screen.queryByRole("button", { name: "Reverse" })).toBeNull();
	});

	it("shows a family neither names nor Reverse, and links its own invoice page", async () => {
		vi.mocked(walletApi.entries).mockResolvedValue(
			page(ROWS.map(({ created_by: _by, ...row }) => row)),
		);
		renderStatement(false);
		const table = await screen.findByRole("table");
		expect(within(table).queryByText("By")).toBeNull();
		expect(within(table).queryByText("Amina")).toBeNull();
		expect(screen.queryByRole("button", { name: "Reverse" })).toBeNull();
		expect(
			within(table).getByRole("link", { name: "INV-000051" }),
		).toHaveAttribute("href", "/learning/invoices/51");
	});

	it("says when there are no entries, or the statement failed", async () => {
		vi.mocked(walletApi.entries).mockResolvedValueOnce(page([]));
		const { unmount } = renderStatement();
		expect(await screen.findByText("No entries yet.")).toBeVisible();
		unmount();
		vi.mocked(walletApi.entries).mockRejectedValueOnce(new Error("offline"));
		renderStatement();
		expect(
			await screen.findByText("The statement could not be loaded."),
		).toBeVisible();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderStatement();
		const table = await screen.findByRole("table");
		expect(within(table).getByText("دفع فاتورة")).toBeVisible();
		expect(within(table).getByRole("button", { name: "عكس" })).toBeVisible();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/wallet`
Expected: FAIL (the modules do not exist).

- [ ] **Step 3: Implement**

Create `dashboard/src/features/wallet/schemas.ts`:

```ts
import { z } from "zod";
import { PAYMENT_METHODS, type PaymentMethod } from "@/features/billing/schemas";
import type { Provider } from "@/features/gateways/schemas";
import { minorDigits, toMinor } from "@/lib/money";

export const ENTRY_KINDS = [
	"topup",
	"refund",
	"adjustment",
	"spend",
	"reversal",
	"compensation",
] as const;
export type EntryKind = (typeof ENTRY_KINDS)[number];

/** E-19: the most one top-up (or one adjustment, plan W11) moves. */
export const MAX_TOPUP_MINOR = 100_000_000;

export interface Balance {
	currency: string;
	balance_minor: number;
}
export interface StudentRef {
	id: number;
	name: string;
}
export interface StudentWallet {
	student: StudentRef;
	balances: Balance[];
}
/** `wallet/mine/`: one per student the family may use (E-17). */
export interface FamilyWallet extends StudentWallet {
	topup_currencies: string[];
}
export interface WalletEntry {
	id: number;
	kind: EntryKind;
	currency: string;
	amount_minor: number;
	balance_after_minor: number;
	/** Blank on a family's adjustment (E-22). */
	note: string;
	invoice_id: number | null;
	payment_id: number | null;
	session_id: number | null;
	created_at: string;
	/** Plan W13: a top-up already given back. */
	reversed: boolean;
	/** The office only (E-22). */
	created_by?: { id: number; full_name: string } | null;
}
export interface TopUpBody {
	amount_minor: number;
	currency: string;
	method: PaymentMethod;
	paid_on: string;
	reference: string;
}
export interface AdjustmentBody {
	amount_minor: number;
	currency: string;
	reason: string;
}
export interface TopUpOptions {
	currencies: string[];
	providers: Provider[];
}
export interface StartTopUpBody {
	student: number;
	amount_minor: number;
	currency: string;
	provider: Provider;
}

const CURRENCY = /^[A-Z]{3}$/;

/** Why `text` is not an amount in `currency` (an i18n key), or null: a
 * positive amount (`signed`: any but 0) with no more decimals than the
 * currency has, at most the cap (E-19). */
export function amountIssue(
	text: string,
	currency: string,
	{ signed = false }: { signed?: boolean } = {},
): string | null {
	const value = text.trim();
	if (!value) return "billing.errors.required";
	const digits = minorDigits(currency);
	const sign = signed ? "-?" : "";
	const pattern =
		digits > 0
			? new RegExp(`^${sign}\\d+(\\.\\d{1,${digits}})?$`)
			: new RegExp(`^${sign}\\d+$`);
	if (!pattern.test(value)) return "billing.errors.amountInvalid";
	const minor = toMinor(value, currency);
	if (minor === 0 || (!signed && minor < 0)) {
		return "billing.errors.amountInvalid";
	}
	if (Math.abs(minor) > MAX_TOPUP_MINOR) return "wallet.errors.tooMuch";
	return null;
}

/** The amount's issue once the currency is a code (the currency is itself
 * a field, so the check runs in the object's `superRefine`). */
function refineAmount(
	amount: string,
	currency: string,
	signed: boolean,
	add: (message: string) => void,
) {
	if (!CURRENCY.test(currency)) return;
	const issue = amountIssue(amount, currency, { signed });
	if (issue) add(issue);
}

/** The office's top-up (E-14). */
export const topUpFormSchema = z
	.object({
		amount: z.string(),
		currency: z.string().regex(CURRENCY, "billing.errors.required"),
		method: z.enum(PAYMENT_METHODS),
		paid_on: z
			.string()
			.regex(/^\d{4}-\d{2}-\d{2}$/, "billing.errors.dateRequired"),
		reference: z.string().max(120, "billing.errors.tooLong"),
	})
	.superRefine((data, ctx) =>
		refineAmount(data.amount, data.currency, false, (message) =>
			ctx.addIssue({ code: "custom", path: ["amount"], message }),
		),
	);
export type TopUpFormValues = z.infer<typeof topUpFormSchema>;

/** A correction, either sign (E-4, E-5). */
export const adjustFormSchema = z
	.object({
		amount: z.string(),
		currency: z.string().regex(CURRENCY, "billing.errors.required"),
		reason: z
			.string()
			.trim()
			.min(1, "wallet.errors.reason")
			.max(500, "wallet.errors.reasonLong"),
	})
	.superRefine((data, ctx) =>
		refineAmount(data.amount, data.currency, true, (message) =>
			ctx.addIssue({ code: "custom", path: ["amount"], message }),
		),
	);
export type AdjustFormValues = z.infer<typeof adjustFormSchema>;

/** Paying an invoice from the balance (E-11): over the balance first, then
 * over what is due, as the server decides. */
export const payFormSchema = (available: number, due: number, currency: string) =>
	z.object({ amount: z.string() }).superRefine((data, ctx) => {
		const add = (message: string) =>
			ctx.addIssue({ code: "custom", path: ["amount"], message });
		const issue = amountIssue(data.amount, currency);
		if (issue) return add(issue);
		const minor = toMinor(data.amount.trim(), currency);
		if (minor > available) add("wallet.errors.overBalance");
		else if (minor > due) add("billing.errors.overBalance");
	});
export type PayFormValues = z.infer<ReturnType<typeof payFormSchema>>;

/** A family's online top-up (E-15). */
export const onlineTopUpSchema = z
	.object({
		amount: z.string(),
		currency: z.string().regex(CURRENCY, "billing.errors.required"),
	})
	.superRefine((data, ctx) =>
		refineAmount(data.amount, data.currency, false, (message) =>
			ctx.addIssue({ code: "custom", path: ["amount"], message }),
		),
	);
export type OnlineTopUpValues = z.infer<typeof onlineTopUpSchema>;
```

Create `dashboard/src/features/wallet/api.ts`:

```ts
import type { StartedCheckout } from "@/features/gateways/schemas";
import { api, clean, type Paginated, type QueryParams } from "@/lib/api";
import type {
	AdjustmentBody,
	FamilyWallet,
	StartTopUpBody,
	StudentWallet,
	TopUpBody,
	TopUpOptions,
	WalletEntry,
} from "./schemas";

const W = "wallet/";

/** B3e spec §5. Every write answers the new entry; the caller refetches. */
export const walletApi = {
	mine: async () => (await api.get<FamilyWallet[]>(`${W}mine/`)).data,
	student: async (id: number) =>
		(await api.get<StudentWallet>(`${W}students/${id}/`)).data,
	entries: async (id: number, params: QueryParams) =>
		(
			await api.get<Paginated<WalletEntry>>(`${W}students/${id}/entries/`, {
				params: clean(params),
			})
		).data,
	topUp: async ({ studentId, ...body }: TopUpBody & { studentId: number }) =>
		(await api.post<WalletEntry>(`${W}students/${studentId}/top-ups/`, body))
			.data,
	adjust: async ({
		studentId,
		...body
	}: AdjustmentBody & { studentId: number }) =>
		(
			await api.post<WalletEntry>(
				`${W}students/${studentId}/adjustments/`,
				body,
			)
		).data,
	payInvoice: async ({
		invoiceId,
		amount_minor,
	}: {
		invoiceId: number;
		amount_minor?: number;
	}) =>
		(
			await api.post<WalletEntry>(
				`${W}invoices/${invoiceId}/pay/`,
				amount_minor === undefined ? {} : { amount_minor },
			)
		).data,
	move: async (paymentId: number) =>
		(await api.post<WalletEntry>(`${W}payments/${paymentId}/move/`)).data,
	reverse: async (paymentId: number) =>
		(await api.post<WalletEntry>(`${W}payments/${paymentId}/reverse/`)).data,
	topUpOptions: async (params: QueryParams) =>
		(
			await api.get<TopUpOptions>(`${W}top-ups/options/`, {
				params: clean(params),
			})
		).data,
	startTopUp: async (body: StartTopUpBody) =>
		(await api.post<StartedCheckout>(`${W}top-ups/`, body)).data,
};
```

Create `dashboard/src/features/wallet/queries.ts`:

```ts
import {
	keepPreviousData,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { billingKey } from "@/features/billing/queries";
import { schedulingKey } from "@/features/scheduling/queries";
import type { QueryParams } from "@/lib/api";
import { walletApi } from "./api";

/** Every wallet query lives under this key. */
export const walletKey = ["wallet"] as const;

export function useMyWallets() {
	return useQuery({ queryKey: [...walletKey, "mine"], queryFn: walletApi.mine });
}

/** A student's balances; a reader outside E-17 gets a 404 (no retry). */
export function useStudentWallet(id: number | undefined, enabled = true) {
	return useQuery({
		queryKey: [...walletKey, "student", id],
		queryFn: () => walletApi.student(id as number),
		enabled: enabled && id !== undefined,
		retry: false,
	});
}

export function useEntries(id: number, currency: string, page: number) {
	return useQuery({
		queryKey: [...walletKey, "entries", id, currency, page],
		queryFn: () => walletApi.entries(id, { currency, page }),
		placeholderData: keepPreviousData,
	});
}

export function useTopUpOptions(params: QueryParams, enabled: boolean) {
	return useQuery({
		queryKey: [...walletKey, "options", params],
		queryFn: () => walletApi.topUpOptions(params),
		enabled,
	});
}

/** A wallet write (spec §6): refreshes the wallet, billing (the invoice and
 * the payment records) and scheduling (a subscription's payment status). */
export function useWalletMutation<A, R>(write: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (args: A) => write(args),
		onSuccess: () =>
			Promise.all([
				qc.invalidateQueries({ queryKey: walletKey }),
				qc.invalidateQueries({ queryKey: billingKey }),
				qc.invalidateQueries({ queryKey: schedulingKey }),
			]),
	});
}
```

Create `dashboard/src/features/wallet/Statement.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { Pager } from "@/components/Pager";
import { useAcademySettings } from "@/features/academy/queries";
import { Money } from "@/features/billing";
import { pageCount } from "@/features/finance/shared";
import { useCan } from "@/features/identity/permissions";
import { errorText } from "@/lib/form-errors";
import { formatMoney } from "@/lib/money";
import { dayIn } from "@/lib/zoned-time";
import { Alert, AlertDescription, Spinner, toast } from "@/ui";
import { walletApi } from "./api";
import { useEntries, useWalletMutation } from "./queries";
import type { WalletEntry } from "./schemas";

/** "+EGP 300.00" / "-EGP 200.00", left to right in RTL text. */
function Signed({ minor, currency }: { minor: number; currency: string }) {
	const { i18n } = useTranslation();
	return (
		<span dir="ltr">
			{minor > 0 ? "+" : "-"}
			{formatMoney(Math.abs(minor), currency, i18n.language)}
		</span>
	);
}

/** An invoice's number links to the reader's own invoice page. */
function Note({ entry, office }: { entry: WalletEntry; office: boolean }) {
	if (entry.invoice_id === null) return <>{entry.note}</>;
	const params = { invoiceId: String(entry.invoice_id) };
	const className = "text-primary-text underline-offset-4 hover:underline";
	return office ? (
		<Link to="/billing/invoices/$invoiceId" params={params} className={className}>
			<span dir="ltr">{entry.note}</span>
		</Link>
	) : (
		<Link to="/learning/invoices/$invoiceId" params={params} className={className}>
			<span dir="ltr">{entry.note}</span>
		</Link>
	);
}

function Reverse({ entry }: { entry: WalletEntry }) {
	const { t } = useTranslation();
	const reverse = useWalletMutation(walletApi.reverse);
	return (
		<Confirm
			action={t("wallet.reverse.action")}
			title={t("wallet.reverse.title")}
			body={t("wallet.reverse.body")}
			onConfirm={() =>
				reverse.mutate(entry.payment_id as number, {
					onSuccess: () =>
						toast({ description: t("wallet.reverse.done"), variant: "success" }),
					onError: (error) =>
						toast({ description: errorText(error, t), variant: "destructive" }),
				})
			}
		/>
	);
}

const COLUMNS = ["date", "kind", "note", "amount", "balance"] as const;

/** One currency's statement (spec §6), newest first, 25 a page, dated in
 * the academy's timezone. `office`: who recorded each entry, and Reverse on
 * a top-up not yet given back (wallet.update). A family's rows come without
 * names or adjustment reasons (E-22). */
export function Statement({
	studentId,
	currency,
	office,
}: {
	studentId: number;
	currency: string;
	office: boolean;
}) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const [page, setPage] = useState(1);
	const { data: academy } = useAcademySettings();
	const { data, isPending, isError } = useEntries(studentId, currency, page);
	if (isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("wallet.statement.loadError")}</AlertDescription>
			</Alert>
		);
	}
	if (isPending) return <Spinner />;
	if (data.results.length === 0) {
		return (
			<p className="text-sm text-muted-foreground">
				{t("wallet.statement.empty")}
			</p>
		);
	}
	const when = (instant: string) =>
		academy ? dayIn(new Date(instant), academy.timezone, i18n.language) : "";
	const reversible = (entry: WalletEntry) =>
		office &&
		entry.kind === "topup" &&
		!entry.reversed &&
		entry.payment_id !== null &&
		can("wallet.update");
	return (
		<div className="flex flex-col gap-3">
			<div className="overflow-x-auto">
				<table className="w-full text-sm">
					<caption className="sr-only">
						{t("wallet.statement.title", { currency })}
					</caption>
					<thead>
						<tr className="border-b border-border">
							{COLUMNS.map((column) => (
								<th key={column} className="px-2 py-2 text-start font-medium">
									{t(`wallet.statement.columns.${column}`)}
								</th>
							))}
							{office ? (
								<th className="px-2 py-2 text-start font-medium">
									{t("wallet.statement.columns.by")}
								</th>
							) : null}
							<th className="px-2 py-2" />
						</tr>
					</thead>
					<tbody>
						{data.results.map((entry) => (
							<tr key={entry.id} className="border-b border-border align-top">
								<td className="px-2 py-2">{when(entry.created_at)}</td>
								<td className="px-2 py-2">{t(`wallet.kinds.${entry.kind}`)}</td>
								<td className="px-2 py-2">
									<Note entry={entry} office={office} />
								</td>
								<td className="px-2 py-2">
									<Signed minor={entry.amount_minor} currency={entry.currency} />
								</td>
								<td className="px-2 py-2">
									<Money
										minor={entry.balance_after_minor}
										currency={entry.currency}
									/>
								</td>
								{office ? (
									<td className="px-2 py-2">
										{entry.created_by?.full_name ?? ""}
									</td>
								) : null}
								<td className="px-2 py-2">
									{reversible(entry) ? <Reverse entry={entry} /> : null}
								</td>
							</tr>
						))}
					</tbody>
				</table>
			</div>
			<Pager page={page} pages={pageCount(data.count)} onChange={setPage} />
		</div>
	);
}
```

Create `dashboard/src/features/wallet/index.ts` (later tasks add their components):

```ts
export { walletApi } from "./api";
export * from "./queries";
export * from "./schemas";
export { Statement } from "./Statement";
```

Create `dashboard/src/locales/en/wallet.json`:

```json
{
	"nav": "Balance",
	"card": {
		"title": "Balance",
		"body": "Money the student holds with the academy, one balance per currency.",
		"loadError": "The balance could not be loaded.",
		"none": "No balance yet.",
		"tabs": "Currencies"
	},
	"kinds": {
		"topup": "Top-up",
		"refund": "Moved from an invoice",
		"adjustment": "Adjustment",
		"spend": "Paid an invoice",
		"reversal": "Top-up given back",
		"compensation": "Compensation"
	},
	"statement": {
		"title": "Statement in {{currency}}",
		"empty": "No entries yet.",
		"loadError": "The statement could not be loaded.",
		"columns": {
			"date": "Date",
			"kind": "Entry",
			"note": "Details",
			"amount": "Amount",
			"balance": "Balance after",
			"by": "By"
		}
	},
	"reverse": {
		"action": "Reverse",
		"title": "Give this top-up back",
		"body": "Its amount leaves the balance and the top-up is marked refunded. Hand the money back to the family yourself.",
		"done": "Top-up reversed."
	},
	"topUp": {
		"action": "Top up",
		"title": "Top up the balance",
		"amount": "Amount",
		"currency": "Currency",
		"method": "Method",
		"paidOn": "Received on",
		"reference": "Reference",
		"save": "Add to balance",
		"done": "Balance topped up."
	},
	"adjust": {
		"action": "Adjust",
		"title": "Adjust the balance",
		"amount": "Amount (+ adds, - takes away)",
		"currency": "Currency",
		"reason": "Reason",
		"note": "Correction only: not a cash refund.",
		"available": "Available: {{amount}}",
		"save": "Save adjustment",
		"done": "Balance adjusted."
	},
	"pay": {
		"action": "Pay from balance",
		"title": "Pay from the balance",
		"body": "Pay {{amount}} from the balance ({{balance}} available).",
		"amount": "Amount ({{currency}})",
		"confirm": "Pay",
		"done": "Paid from the balance."
	},
	"move": {
		"action": "Move to balance",
		"title": "Move this payment to the balance",
		"body": "It stops counting toward the invoice and its amount is added to the student's balance. It cannot be given back as cash afterwards.",
		"done": "Payment moved to the balance."
	},
	"family": {
		"title": "Balance",
		"loadError": "The balances could not be loaded.",
		"none": "No students to show.",
		"topUp": "Top up",
		"topUpTitle": "Top up {{name}}'s balance",
		"providers": "Ways to pay",
		"providersLoading": "Finding ways to pay…",
		"noProviders": "No online payment takes this amount in this currency.",
		"pay": "Pay with {{provider}}",
		"sheetTitle": "Top up online",
		"amount": "Amount"
	},
	"errors": {
		"tooMuch": "That amount is too large for one entry.",
		"reason": "Give a reason.",
		"reasonLong": "Keep the reason under 500 characters.",
		"overBalance": "That is more than the balance holds.",
		"onlyAdd": "You may only add to the balance.",
		"onlyTake": "You may only take away from the balance."
	}
}
```

Create `dashboard/src/locales/ar/wallet.json`:

```json
{
	"nav": "الرصيد",
	"card": {
		"title": "الرصيد",
		"body": "المال الذي يحتفظ به الطالب لدى الأكاديمية، رصيد لكل عملة.",
		"loadError": "تعذّر تحميل الرصيد.",
		"none": "لا رصيد بعد.",
		"tabs": "العملات"
	},
	"kinds": {
		"topup": "شحن",
		"refund": "منقول من فاتورة",
		"adjustment": "تسوية",
		"spend": "دفع فاتورة",
		"reversal": "إعادة شحن",
		"compensation": "تعويض"
	},
	"statement": {
		"title": "كشف الحساب بـ {{currency}}",
		"empty": "لا قيود بعد.",
		"loadError": "تعذّر تحميل كشف الحساب.",
		"columns": {
			"date": "التاريخ",
			"kind": "القيد",
			"note": "التفاصيل",
			"amount": "المبلغ",
			"balance": "الرصيد بعده",
			"by": "بواسطة"
		}
	},
	"reverse": {
		"action": "عكس",
		"title": "إعادة هذا الشحن",
		"body": "يُخصم مبلغه من الرصيد ويُحدَّد الشحن كمسترد. سلّم المال للأسرة بنفسك.",
		"done": "تم عكس الشحن."
	},
	"topUp": {
		"action": "شحن",
		"title": "شحن الرصيد",
		"amount": "المبلغ",
		"currency": "العملة",
		"method": "طريقة الدفع",
		"paidOn": "تاريخ الاستلام",
		"reference": "المرجع",
		"save": "إضافة إلى الرصيد",
		"done": "تم شحن الرصيد."
	},
	"adjust": {
		"action": "تسوية",
		"title": "تسوية الرصيد",
		"amount": "المبلغ (+ يضيف، - يخصم)",
		"currency": "العملة",
		"reason": "السبب",
		"note": "تصحيح فقط: ليس استردادًا نقديًا.",
		"available": "المتاح: {{amount}}",
		"save": "حفظ التسوية",
		"done": "تمت تسوية الرصيد."
	},
	"pay": {
		"action": "ادفع من الرصيد",
		"title": "الدفع من الرصيد",
		"body": "دفع {{amount}} من الرصيد (المتاح {{balance}}).",
		"amount": "المبلغ ({{currency}})",
		"confirm": "ادفع",
		"done": "تم الدفع من الرصيد."
	},
	"move": {
		"action": "نقل إلى الرصيد",
		"title": "نقل هذه الدفعة إلى الرصيد",
		"body": "لن تُحتسب ضمن الفاتورة ويُضاف مبلغها إلى رصيد الطالب. لا يمكن ردّها نقدًا بعد ذلك.",
		"done": "نُقلت الدفعة إلى الرصيد."
	},
	"family": {
		"title": "الرصيد",
		"loadError": "تعذّر تحميل الأرصدة.",
		"none": "لا طلاب لعرضهم.",
		"topUp": "شحن",
		"topUpTitle": "شحن رصيد {{name}}",
		"providers": "طرق الدفع",
		"providersLoading": "جارٍ البحث عن طرق الدفع…",
		"noProviders": "لا توجد وسيلة دفع إلكتروني تقبل هذا المبلغ بهذه العملة.",
		"pay": "ادفع عبر {{provider}}",
		"sheetTitle": "الشحن الإلكتروني",
		"amount": "المبلغ"
	},
	"errors": {
		"tooMuch": "هذا المبلغ أكبر من المسموح لقيد واحد.",
		"reason": "اذكر السبب.",
		"reasonLong": "اجعل السبب أقل من 500 حرف.",
		"overBalance": "هذا أكثر مما في الرصيد.",
		"onlyAdd": "يمكنك الإضافة إلى الرصيد فقط.",
		"onlyTake": "يمكنك الخصم من الرصيد فقط."
	}
}
```

`dashboard/src/locales/en/errors.json`, add a `wallet` block (after `billing`):

```json
	"wallet": {
		"insufficient_balance": "The balance does not cover this.",
		"nothing_due": "Nothing is due on this invoice.",
		"not_invoice_payment": "Only a payment on an invoice can be moved to the balance.",
		"not_topup": "Only a balance top-up can be reversed.",
		"topup_paid": "This top-up is already paid."
	}
```

`dashboard/src/locales/ar/errors.json`, the same block:

```json
	"wallet": {
		"insufficient_balance": "الرصيد لا يغطي هذا.",
		"nothing_due": "لا شيء مستحق على هذه الفاتورة.",
		"not_invoice_payment": "لا تُنقل إلى الرصيد إلا دفعة على فاتورة.",
		"not_topup": "لا يُعكس إلا شحن للرصيد.",
		"topup_paid": "هذا الشحن مدفوع مسبقًا."
	}
```

- [ ] **Step 4: Run, type-check, lint, commit**

Run: `$DASH pnpm vitest run src/features/wallet src/locales`
Expected: PASS (the locales test keeps en and ar key-for-key equal).
Run: `just test-frontend && just lint-frontend`

```bash
git -C dashboard add src/features/wallet src/features/identity/schemas.ts src/test/wallet-fixtures.ts src/locales
git -C dashboard commit -m "feat(wallet): the wallet feature's api, queries, schemas and statement (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 12: Dashboard — the student page's balance card: Top up and Adjust

**Files:**
- Create: `dashboard/src/features/wallet/TopUpDialog.tsx`, `AdjustDialog.tsx`, `StudentWalletCard.tsx`, `StudentWalletCard.test.tsx`, `dashboard/src/routes/_authed/people.students.$personId.test.tsx`
- Modify: `dashboard/src/features/wallet/index.ts`, `dashboard/src/routes/_authed/people.students.$personId.tsx` (one import, one card: the trunk page no phase owns, spec §7)

**Interfaces:**
- Consumes: Task 11's `walletApi.student`, `topUp`, `adjust`, `useStudentWallet`, `useWalletMutation`, `Statement`, the form schemas; `useFillOnOpen`, `saveOrShowErrors`, `SettingsWait` from `@/features/finance/shared`.
- Produces: `<StudentWalletCard studentId />` (hides itself without `wallet.view_any` or `balances`), `<TopUpDialog studentId currency? />`, `<AdjustDialog studentId balances currency? />`, exported from `@/features/wallet`.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/wallet/StudentWalletCard.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { todayIn } from "@/lib/zoned-time";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { studentWallet, walletEntry } from "@/test/wallet-fixtures";
import { walletApi } from "./api";
import { StudentWalletCard } from "./StudentWalletCard";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		walletApi: {
			...actual.walletApi,
			student: vi.fn(),
			entries: vi.fn(),
			topUp: vi.fn(),
			adjust: vi.fn(),
		},
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

function renderCard(me = adminWith("balances")) {
	return renderWithRouter(
		<CanProvider me={me}>
			<StudentWalletCard studentId={11} />
		</CanProvider>,
	);
}

async function openDialog(user: ReturnType<typeof userEvent.setup>, name: string) {
	await user.click(await screen.findByRole("button", { name }));
	const dialog = await screen.findByRole("dialog");
	await waitFor(() => expect(within(dialog).getByLabelText(/^Amount/)).toHaveFocus());
	return dialog;
}

describe("StudentWalletCard", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ timezone: "Asia/Tokyo" }),
		);
		vi.mocked(walletApi.student).mockResolvedValue(studentWallet());
		vi.mocked(walletApi.entries).mockResolvedValue(page([walletEntry()]));
		vi.mocked(walletApi.topUp).mockResolvedValue(walletEntry());
		vi.mocked(walletApi.adjust).mockResolvedValue(
			walletEntry({ kind: "adjustment" }),
		);
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("shows one tab per currency, each with its balance and statement", async () => {
		const user = userEvent.setup();
		renderCard();
		expect(await screen.findByRole("tab", { name: "EGP" })).toHaveAttribute(
			"aria-selected",
			"true",
		);
		const panel = screen.getByRole("tabpanel");
		expect(within(panel).getAllByText("EGP 300.00")[0]).toBeVisible();
		expect(walletApi.entries).toHaveBeenCalledWith(11, { currency: "EGP", page: 1 });
		await user.click(screen.getByRole("tab", { name: "USD" }));
		expect(within(screen.getByRole("tabpanel")).getByText("$50.00")).toBeVisible();
		await waitFor(() =>
			expect(walletApi.entries).toHaveBeenCalledWith(11, {
				currency: "USD",
				page: 1,
			}),
		);
	});

	it("says when the student holds nothing yet, or the balance failed", async () => {
		vi.mocked(walletApi.student).mockResolvedValueOnce(
			studentWallet({ balances: [] }),
		);
		const { unmount } = renderCard();
		expect(await screen.findByText("No balance yet.")).toBeVisible();
		expect(screen.getByRole("button", { name: "Top up" })).toBeVisible();
		unmount();
		vi.mocked(walletApi.student).mockRejectedValueOnce(new Error("offline"));
		renderCard();
		expect(
			await screen.findByText("The balance could not be loaded."),
		).toBeVisible();
	});

	it("hides itself without wallet.view_any or the balances feature", async () => {
		const { unmount } = renderCard(adminWith());
		await act(async () => {});
		expect(screen.queryByText("Balance")).toBeNull();
		unmount();
		renderCard({ ...staffMe("wallet.create"), features: ["balances"] });
		await act(async () => {});
		expect(screen.queryByText("Balance")).toBeNull();
		expect(walletApi.student).not.toHaveBeenCalled();
	});

	it("tops up by hand in the chosen tab's currency, dated the academy's today", async () => {
		const user = userEvent.setup();
		renderCard();
		const dialog = await openDialog(user, "Top up");
		expect(within(dialog).getByLabelText(/^Currency/)).toHaveValue("EGP");
		expect(within(dialog).getByLabelText(/^Received on/)).toHaveValue(
			todayIn("Asia/Tokyo"),
		);
		await user.type(within(dialog).getByLabelText(/^Amount/), "300.50");
		await user.selectOptions(within(dialog).getByLabelText(/^Method/), "instapay");
		await user.type(within(dialog).getByLabelText(/^Reference/), " IP-1 ");
		await user.click(within(dialog).getByRole("button", { name: "Add to balance" }));
		await waitFor(() =>
			expect(walletApi.topUp).toHaveBeenCalledWith({
				studentId: 11,
				amount_minor: 30050,
				currency: "EGP",
				method: "instapay",
				paid_on: todayIn("Asia/Tokyo"),
				reference: "IP-1",
			}),
		);
		expect(await screen.findByText("Balance topped up.")).toBeVisible();
	});

	it("refuses a bad amount here, and shows the server's refusal", async () => {
		const user = userEvent.setup();
		vi.mocked(walletApi.topUp).mockRejectedValueOnce(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { paid_on: ["A payment can't be dated in the future."] },
			} as never),
		);
		renderCard();
		const dialog = await openDialog(user, "Top up");
		const amount = within(dialog).getByLabelText(/^Amount/);
		const save = within(dialog).getByRole("button", { name: "Add to balance" });
		await user.type(amount, "0");
		await user.click(save);
		expect(
			await within(dialog).findByText(
				"Enter an amount above zero, like 150 or 150.50.",
			),
		).toBeVisible();
		await user.clear(amount);
		await user.type(amount, "1000000.01");
		await user.click(save);
		expect(
			await within(dialog).findByText("That amount is too large for one entry."),
		).toBeVisible();
		await user.clear(amount);
		await user.type(amount, "10");
		await user.click(save);
		expect(
			await within(dialog).findByText("A payment can't be dated in the future."),
		).toBeVisible();
	});

	it("adjusts with a signed amount, a reason and the correction note", async () => {
		const user = userEvent.setup();
		renderCard();
		const dialog = await openDialog(user, "Adjust");
		expect(
			within(dialog).getByText("Correction only: not a cash refund."),
		).toBeVisible();
		expect(within(dialog).getByText("Available: EGP 300.00")).toBeVisible();
		await user.type(within(dialog).getByLabelText(/^Amount/), "-50");
		await user.click(within(dialog).getByRole("button", { name: "Save adjustment" }));
		expect(await within(dialog).findByText("Give a reason.")).toBeVisible();
		await user.type(within(dialog).getByLabelText(/^Reason/), "Typo");
		await user.click(within(dialog).getByRole("button", { name: "Save adjustment" }));
		await waitFor(() =>
			expect(walletApi.adjust).toHaveBeenCalledWith({
				studentId: 11,
				amount_minor: -5000,
				currency: "EGP",
				reason: "Typo",
			}),
		);
		expect(await screen.findByText("Balance adjusted.")).toBeVisible();
	});

	it("lets a staff account adjust only in the direction its codes allow", async () => {
		const user = userEvent.setup();
		renderCard({
			...staffMe("wallet.view_any", "wallet.create"),
			features: ["balances"],
		});
		const dialog = await openDialog(user, "Adjust");
		await user.type(within(dialog).getByLabelText(/^Amount/), "-5");
		await user.type(within(dialog).getByLabelText(/^Reason/), "Typo");
		await user.click(within(dialog).getByRole("button", { name: "Save adjustment" }));
		expect(
			await within(dialog).findByText("You may only add to the balance."),
		).toBeVisible();
		expect(walletApi.adjust).not.toHaveBeenCalled();
	});

	it("shows no Top up or Adjust to a reader without the write codes", async () => {
		renderCard({ ...staffMe("wallet.view_any"), features: ["balances"] });
		expect(await screen.findByRole("tab", { name: "EGP" })).toBeVisible();
		expect(screen.queryByRole("button", { name: "Top up" })).toBeNull();
		expect(screen.queryByRole("button", { name: "Adjust" })).toBeNull();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderCard();
		expect(await screen.findByRole("tab", { name: "EGP" })).toBeVisible();
		expect(screen.getByRole("button", { name: "شحن" })).toBeVisible();
		expect(screen.getByRole("button", { name: "تسوية" })).toBeVisible();
	});
});
```

Create `dashboard/src/routes/_authed/people.students.$personId.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
	createMemoryHistory,
	createRootRoute,
	createRoute,
	createRouter,
	RouterProvider,
} from "@tanstack/react-router";
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { Route } from "./people.students.$personId";

vi.mock("@/features/people", () => ({
	StudentForm: ({ personId }: { personId: string }) => (
		<p>{`student form ${personId}`}</p>
	),
}));
vi.mock("@/features/wallet", () => ({
	StudentWalletCard: ({ studentId }: { studentId: number }) => (
		<p>{`balance card for ${studentId}`}</p>
	),
}));

/** Mounts the real route under the same id it has in the app's tree. */
function renderRoute(initial: string) {
	const rootRoute = createRootRoute();
	const authed = createRoute({ getParentRoute: () => rootRoute, id: "_authed" });
	const page = createRoute({
		getParentRoute: () => authed,
		path: "people/students/$personId",
		component: Route.options.component,
	});
	const router = createRouter({
		routeTree: rootRoute.addChildren([authed.addChildren([page])]),
		history: createMemoryHistory({ initialEntries: [initial] }),
	});
	render(
		<QueryClientProvider client={new QueryClient()}>
			<RouterProvider router={router} />
		</QueryClientProvider>,
	);
}

describe("student route: the balance card (B3e §6)", () => {
	it("shows the card for an existing student", async () => {
		renderRoute("/people/students/11");
		expect(await screen.findByText("student form 11")).toBeInTheDocument();
		expect(screen.getByText("balance card for 11")).toBeInTheDocument();
	});

	it("shows no card on the new-student page", async () => {
		renderRoute("/people/students/new");
		expect(await screen.findByText("student form new")).toBeInTheDocument();
		expect(screen.queryByText(/balance card for/)).toBeNull();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/wallet/StudentWalletCard.test.tsx 'src/routes/_authed/people.students.$personId.test.tsx'`
Expected: FAIL (`StudentWalletCard` does not exist; the route renders no card).

- [ ] **Step 3: Implement**

Create `dashboard/src/features/wallet/TopUpDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { PAYMENT_METHODS } from "@/features/billing/schemas";
import {
	SettingsWait,
	saveOrShowErrors,
	useFillOnOpen,
} from "@/features/finance/shared";
import { CURRENCIES } from "@/lib/currencies";
import { useFieldError } from "@/lib/field-error";
import { toMinor } from "@/lib/money";
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
	toast,
} from "@/ui";
import { walletApi } from "./api";
import { useWalletMutation } from "./queries";
import { type TopUpFormValues, topUpFormSchema } from "./schemas";

/** The codes to offer, the chosen one first when it is not in the list. */
export function currencyChoices(current?: string): string[] {
	const all = [...CURRENCIES] as string[];
	return current && !all.includes(current) ? [current, ...all] : all;
}

/** E-14: the office's manual top-up: money received by hand, in the shown
 * tab's currency (else the academy's), dated the academy's today. */
export function TopUpDialog({
	studentId,
	currency,
}: {
	studentId: number;
	currency?: string;
}) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const settings = useAcademySettings();
	const academy = settings.data;
	const save = useWalletMutation(walletApi.topUp);
	const initial = useCallback(
		(): TopUpFormValues => ({
			amount: "",
			currency: currency ?? academy?.default_currency ?? "",
			method: "cash",
			paid_on: academy ? todayIn(academy.timezone) : "",
			reference: "",
		}),
		[currency, academy],
	);
	const {
		register,
		handleSubmit,
		setError,
		setFocus,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<TopUpFormValues>({
		resolver: zodResolver(topUpFormSchema),
		defaultValues: initial(),
	});
	const filled = useFillOnOpen({
		open,
		ready: academy !== undefined,
		reset,
		setFocus,
		initial,
		first: "amount",
	});

	async function onSubmit(values: TopUpFormValues) {
		const saved = await saveOrShowErrors(
			() =>
				save.mutateAsync({
					studentId,
					amount_minor: toMinor(values.amount.trim(), values.currency),
					currency: values.currency,
					method: values.method,
					paid_on: values.paid_on,
					reference: values.reference.trim(),
				}),
			setError,
		);
		if (saved) {
			setOpen(false);
			toast({ description: t("wallet.topUp.done"), variant: "success" });
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm">{t("wallet.topUp.action")}</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("wallet.topUp.title")}</DialogTitle>
				<DialogDescription className="sr-only">
					{t("wallet.topUp.title")}
				</DialogDescription>
				{filled ? (
					<form
						onSubmit={handleSubmit(onSubmit)}
						className="mt-4 flex flex-col gap-4"
						noValidate
					>
						<div className="grid gap-4 sm:grid-cols-2">
							<Field
								id="wallet-topup-amount"
								label={t("wallet.topUp.amount")}
								error={fieldError(errors.amount?.message)}
								required
							>
								<Input inputMode="decimal" dir="ltr" {...register("amount")} />
							</Field>
							<Field
								id="wallet-topup-currency"
								label={t("wallet.topUp.currency")}
								error={fieldError(errors.currency?.message)}
								required
							>
								<Select dir="ltr" {...register("currency")}>
									{currencyChoices(currency).map((code) => (
										<option key={code} value={code}>
											{code}
										</option>
									))}
								</Select>
							</Field>
							<Field
								id="wallet-topup-method"
								label={t("wallet.topUp.method")}
								error={fieldError(errors.method?.message)}
								required
							>
								<Select {...register("method")}>
									{PAYMENT_METHODS.map((method) => (
										<option key={method} value={method}>
											{t(`billing.methods.${method}`)}
										</option>
									))}
								</Select>
							</Field>
							<Field
								id="wallet-topup-paid_on"
								label={t("wallet.topUp.paidOn")}
								error={fieldError(errors.paid_on?.message)}
								required
							>
								<Input type="date" dir="ltr" {...register("paid_on")} />
							</Field>
							<Field
								id="wallet-topup-reference"
								label={t("wallet.topUp.reference")}
								error={fieldError(errors.reference?.message)}
							>
								<Input dir="ltr" {...register("reference")} />
							</Field>
						</div>
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
								{t("wallet.topUp.save")}
							</SubmitButton>
						</DialogFooter>
					</form>
				) : (
					<SettingsWait
						failed={settings.isError}
						retrying={settings.isFetching}
						onRetry={() => void settings.refetch()}
					/>
				)}
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/wallet/AdjustDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { saveOrShowErrors, useFillOnOpen } from "@/features/finance/shared";
import { useCan } from "@/features/identity/permissions";
import { useFieldError } from "@/lib/field-error";
import { formatMoney, toMinor } from "@/lib/money";
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
import { walletApi } from "./api";
import { useWalletMutation } from "./queries";
import { type AdjustFormValues, adjustFormSchema, type Balance } from "./schemas";
import { currencyChoices } from "./TopUpDialog";

/** E-4, E-5: a correction, either sign, never money in or out. A staff
 * account adds with wallet.create and takes away with wallet.update (W11,
 * W22); the server decides again. */
export function AdjustDialog({
	studentId,
	balances,
	currency,
}: {
	studentId: number;
	balances: Balance[];
	currency?: string;
}) {
	const { t, i18n } = useTranslation();
	const fieldError = useFieldError();
	const can = useCan();
	const [open, setOpen] = useState(false);
	const save = useWalletMutation(walletApi.adjust);
	const initial = useCallback(
		(): AdjustFormValues => ({
			amount: "",
			currency: currency ?? balances[0]?.currency ?? "",
			reason: "",
		}),
		[currency, balances],
	);
	const {
		register,
		handleSubmit,
		setError,
		setFocus,
		reset,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<AdjustFormValues>({
		resolver: zodResolver(adjustFormSchema),
		defaultValues: initial(),
	});
	useFillOnOpen({ open, ready: true, reset, setFocus, initial, first: "amount" });
	const chosen = watch("currency");
	const available =
		balances.find((b) => b.currency === chosen)?.balance_minor ?? 0;

	async function onSubmit(values: AdjustFormValues) {
		const minor = toMinor(values.amount.trim(), values.currency);
		if (minor > 0 && !can("wallet.create")) {
			return setError("amount", { message: "wallet.errors.onlyTake" });
		}
		if (minor < 0 && !can("wallet.update")) {
			return setError("amount", { message: "wallet.errors.onlyAdd" });
		}
		const saved = await saveOrShowErrors(
			() =>
				save.mutateAsync({
					studentId,
					amount_minor: minor,
					currency: values.currency,
					reason: values.reason.trim(),
				}),
			setError,
		);
		if (saved) {
			setOpen(false);
			toast({ description: t("wallet.adjust.done"), variant: "success" });
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("wallet.adjust.action")}
				</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("wallet.adjust.title")}</DialogTitle>
				<DialogDescription>{t("wallet.adjust.note")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<div className="grid gap-4 sm:grid-cols-2">
						<Field
							id="wallet-adjust-amount"
							label={t("wallet.adjust.amount")}
							error={fieldError(errors.amount?.message)}
							required
						>
							<Input inputMode="decimal" dir="ltr" {...register("amount")} />
						</Field>
						<Field
							id="wallet-adjust-currency"
							label={t("wallet.adjust.currency")}
							error={fieldError(errors.currency?.message)}
							required
						>
							<Select dir="ltr" {...register("currency")}>
								{currencyChoices(currency).map((code) => (
									<option key={code} value={code}>
										{code}
									</option>
								))}
							</Select>
						</Field>
					</div>
					{/^[A-Z]{3}$/.test(chosen) ? (
						<p className="text-sm text-muted-foreground">
							{t("wallet.adjust.available", {
								amount: formatMoney(available, chosen, i18n.language),
							})}
						</p>
					) : null}
					<Field
						id="wallet-adjust-reason"
						label={t("wallet.adjust.reason")}
						error={fieldError(errors.reason?.message)}
						required
					>
						<Textarea rows={2} {...register("reason")} />
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
							{t("wallet.adjust.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/wallet/StudentWalletCard.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
	Spinner,
} from "@/ui";
import { AdjustDialog } from "./AdjustDialog";
import { useStudentWallet } from "./queries";
import { Statement } from "./Statement";
import { TopUpDialog } from "./TopUpDialog";

function WalletCard({ studentId }: { studentId: number }) {
	const { t } = useTranslation();
	const can = useCan();
	const { data, isError } = useStudentWallet(studentId);
	const [chosen, setChosen] = useState<string | undefined>();
	const balances = data?.balances ?? [];
	const current =
		balances.find((b) => b.currency === chosen) ?? balances[0] ?? undefined;
	return (
		<Card>
			<CardHeader className="flex flex-row flex-wrap items-start justify-between gap-2 border-b border-border">
				<div className="flex flex-col gap-1">
					<CardTitle>{t("wallet.card.title")}</CardTitle>
					<CardDescription>{t("wallet.card.body")}</CardDescription>
				</div>
				{data ? (
					<div className="flex flex-wrap gap-2">
						{can("wallet.create") ? (
							<TopUpDialog studentId={studentId} currency={current?.currency} />
						) : null}
						{can("wallet.create") || can("wallet.update") ? (
							<AdjustDialog
								studentId={studentId}
								balances={balances}
								currency={current?.currency}
							/>
						) : null}
					</div>
				) : null}
			</CardHeader>
			<CardContent className="flex flex-col gap-4 pt-4">
				{isError ? (
					<Alert variant="destructive">
						<AlertDescription>{t("wallet.card.loadError")}</AlertDescription>
					</Alert>
				) : !data ? (
					<Spinner />
				) : current === undefined ? (
					<p className="text-sm text-muted-foreground">{t("wallet.card.none")}</p>
				) : (
					<>
						<div
							role="tablist"
							aria-label={t("wallet.card.tabs")}
							className="flex flex-wrap gap-2 border-b border-border pb-2"
						>
							{balances.map((balance) => (
								<button
									key={balance.currency}
									type="button"
									role="tab"
									id={`wallet-tab-${balance.currency}`}
									aria-selected={balance.currency === current.currency}
									aria-controls={`wallet-panel-${balance.currency}`}
									onClick={() => setChosen(balance.currency)}
									className="rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-secondary aria-selected:bg-secondary aria-selected:text-foreground"
									dir="ltr"
								>
									{balance.currency}
								</button>
							))}
						</div>
						<div
							role="tabpanel"
							id={`wallet-panel-${current.currency}`}
							aria-labelledby={`wallet-tab-${current.currency}`}
							className="flex flex-col gap-3"
						>
							<p className="text-2xl font-semibold">
								<Money minor={current.balance_minor} currency={current.currency} />
							</p>
							<Statement
								key={current.currency}
								studentId={studentId}
								currency={current.currency}
								office
							/>
						</div>
					</>
				)}
			</CardContent>
		</Card>
	);
}

/** B3e §6: the student page's balance card (edit mode only), for the
 * office with wallet.view_any while `balances` is on; it hides itself
 * otherwise. One tab per currency with its balance and statement; Top up
 * (wallet.create), Adjust (wallet.create or wallet.update). */
export function StudentWalletCard({ studentId }: { studentId: number }) {
	const can = useCan();
	const hasFeature = useHasFeature();
	if (!hasFeature("balances") || !can("wallet.view_any")) return null;
	return <WalletCard studentId={studentId} />;
}
```

`dashboard/src/features/wallet/index.ts`, add:

```ts
export { AdjustDialog } from "./AdjustDialog";
export { StudentWalletCard } from "./StudentWalletCard";
export { TopUpDialog } from "./TopUpDialog";
```

Replace `dashboard/src/routes/_authed/people.students.$personId.tsx` (the same route plus one import and one card, B3e §6, spec §7):

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { newOrView } from "@/features/identity/permissions";
import { StudentForm } from "@/features/people";
import { StudentWalletCard } from "@/features/wallet";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/people/students/$personId")({
	staticData: { permission: newOrView("personId", "student") },
	component: function StudentRoute() {
		const { t } = useTranslation();
		const { personId } = Route.useParams();
		const id = Number(personId);
		const existing = personId !== "new" && Number.isInteger(id) && id > 0;
		const title =
			personId === "new" ? t("people.students.new") : t("people.students.edit");
		usePageTitle(title);
		return (
			<>
				<PageHeader title={title} />
				<StudentForm personId={personId} />
				{/* B3e §6: the card hides itself without wallet.view_any or balances. */}
				{existing ? (
					<div className="mt-6">
						<StudentWalletCard studentId={id} />
					</div>
				) : null}
			</>
		);
	},
});
```

- [ ] **Step 4: Run, type-check, lint, commit**

Run: `$DASH pnpm vitest run src/features/wallet 'src/routes/_authed/people.students.$personId.test.tsx'`
Expected: PASS.
Run: `just test-frontend && just lint-frontend`

```bash
git -C dashboard add src/features/wallet 'src/routes/_authed/people.students.$personId.tsx' 'src/routes/_authed/people.students.$personId.test.tsx'
git -C dashboard commit -m "feat(wallet): the student page's balance card with top up and adjust (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 13: Dashboard — Pay from balance and Move to balance on the invoice pages

**Files:**
- Create: `dashboard/src/features/wallet/PayFromWallet.tsx`, `MoveToWallet.tsx`, `PayFromWallet.test.tsx`, `MoveToWallet.test.tsx`
- Modify: `dashboard/src/features/wallet/index.ts`, `dashboard/src/routes/_authed/billing.invoices.$invoiceId.tsx`, `dashboard/src/routes/_authed/learning.invoices.$invoiceId.tsx`

**Interfaces:**
- Consumes: Task 10's `InvoicePage` `actions` / `paymentActions`; Task 11's `walletApi.payInvoice`, `move`, `useStudentWallet`, `payFormSchema`.
- Produces: `<PayFromWallet invoice office />` (plan W21) and `<MoveToWallet payment />` (`wallet.update`, `payment.update`, `balances`; a completed payment on an invoice), exported from `@/features/wallet` and wired by the two invoice routes.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/wallet/PayFromWallet.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CanProvider } from "@/features/identity/permissions";
import type { Me } from "@/features/identity/schemas";
import i18n from "@/lib/i18n";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { familyInvoice, invoiceDetail } from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { studentWallet, walletEntry } from "@/test/wallet-fixtures";
import { walletApi } from "./api";
import { PayFromWallet } from "./PayFromWallet";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		walletApi: { ...actual.walletApi, student: vi.fn(), payInvoice: vi.fn() },
	};
});

const PARENT: Me = {
	id: 31,
	email: "p@x.test",
	full_name: "Omar",
	role: "parent",
	profiles: [],
	features: ["invoices", "balances"],
};

function renderPay(
	invoice = invoiceDetail(),
	office = true,
	me: Me = adminWith("invoices", "balances"),
) {
	return renderWithRouter(
		<CanProvider me={me}>
			<PayFromWallet invoice={invoice} office={office} />
		</CanProvider>,
	);
}

describe("PayFromWallet", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		// Invoice 51: EGP 1,000.00 due; the wallet holds EGP 300.00.
		vi.mocked(walletApi.student).mockResolvedValue(studentWallet());
		vi.mocked(walletApi.payInvoice).mockResolvedValue(
			walletEntry({ kind: "spend", amount_minor: -30000 }),
		);
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("lets the family pay the default, the smaller of balance and amount due", async () => {
		const user = userEvent.setup();
		renderPay(familyInvoice(), false, PARENT);
		await user.click(await screen.findByRole("button", { name: "Pay from balance" }));
		const dialog = await screen.findByRole("dialog");
		expect(dialog).toHaveTextContent(
			"Pay EGP 300.00 from the balance (EGP 300.00 available).",
		);
		expect(within(dialog).queryByLabelText(/^Amount/)).toBeNull();
		await user.click(within(dialog).getByRole("button", { name: "Pay" }));
		await waitFor(() =>
			expect(walletApi.payInvoice).toHaveBeenCalledWith({ invoiceId: 51 }),
		);
		expect(await screen.findByText("Paid from the balance.")).toBeVisible();
		expect(walletApi.student).toHaveBeenCalledWith(11);
	});

	it("lets the office lower the amount, and refuses more than either balance", async () => {
		const user = userEvent.setup();
		vi.mocked(walletApi.student).mockResolvedValue(
			studentWallet({ balances: [{ currency: "EGP", balance_minor: 300000 }] }),
		);
		renderPay();
		await user.click(await screen.findByRole("button", { name: "Pay from balance" }));
		const dialog = await screen.findByRole("dialog");
		const amount = within(dialog).getByLabelText(/^Amount/);
		await waitFor(() => expect(amount).toHaveValue("1000.00"));
		const pay = within(dialog).getByRole("button", { name: "Pay" });
		await user.clear(amount);
		await user.type(amount, "1000.01");
		await user.click(pay);
		expect(
			await within(dialog).findByText("That is more than the balance."),
		).toBeVisible();
		await user.clear(amount);
		await user.type(amount, "250");
		await user.click(pay);
		await waitFor(() =>
			expect(walletApi.payInvoice).toHaveBeenCalledWith({
				invoiceId: 51,
				amount_minor: 25000,
			}),
		);
	});

	it("refuses more than the wallet holds, here and from the server", async () => {
		const user = userEvent.setup();
		vi.mocked(walletApi.payInvoice).mockRejectedValueOnce(
			new AxiosError("Conflict", "409", undefined, undefined, {
				status: 409,
				data: { detail: "x", code: "wallet.insufficient_balance" },
			} as never),
		);
		renderPay();
		await user.click(await screen.findByRole("button", { name: "Pay from balance" }));
		const dialog = await screen.findByRole("dialog");
		const amount = within(dialog).getByLabelText(/^Amount/);
		await waitFor(() => expect(amount).toHaveValue("300.00"));
		await user.clear(amount);
		await user.type(amount, "300.01");
		await user.click(within(dialog).getByRole("button", { name: "Pay" }));
		expect(
			await within(dialog).findByText("That is more than the balance holds."),
		).toBeVisible();
		await user.clear(amount);
		await user.type(amount, "300");
		await user.click(within(dialog).getByRole("button", { name: "Pay" }));
		expect(
			await within(dialog).findByText("The balance does not cover this."),
		).toBeVisible();
	});

	it.each([
		["a void invoice", invoiceDetail({ status: "void", balance_minor: 0 })],
		["nothing due", invoiceDetail({ status: "paid", balance_minor: 0 })],
	])("hides itself on %s", async (_, invoice) => {
		renderPay(invoice);
		await act(async () => {});
		expect(screen.queryByRole("button", { name: "Pay from balance" })).toBeNull();
		expect(walletApi.student).not.toHaveBeenCalled();
	});

	it("hides itself on an empty wallet or one in another currency", async () => {
		vi.mocked(walletApi.student).mockResolvedValue(
			studentWallet({ balances: [{ currency: "USD", balance_minor: 5000 }] }),
		);
		renderPay();
		await waitFor(() => expect(walletApi.student).toHaveBeenCalled());
		expect(screen.queryByRole("button", { name: "Pay from balance" })).toBeNull();
	});

	it("hides itself without the codes, the feature, or a readable wallet", async () => {
		const { unmount } = renderPay(invoiceDetail(), true, {
			...staffMe("invoice.view", "wallet.update"),
			features: ["invoices", "balances"],
		});
		await act(async () => {});
		expect(screen.queryByRole("button", { name: "Pay from balance" })).toBeNull();
		unmount();
		renderPay(invoiceDetail(), true, adminWith("invoices"));
		await act(async () => {});
		expect(screen.queryByRole("button", { name: "Pay from balance" })).toBeNull();
		expect(walletApi.student).not.toHaveBeenCalled();
		vi.mocked(walletApi.student).mockRejectedValue(
			new AxiosError("Not Found", "404", undefined, undefined, {
				status: 404,
			} as never),
		);
		renderPay(familyInvoice(), false, PARENT);
		await waitFor(() => expect(walletApi.student).toHaveBeenCalled());
		expect(screen.queryByRole("button", { name: "Pay from balance" })).toBeNull();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderPay(familyInvoice(), false, PARENT);
		expect(
			await screen.findByRole("button", { name: "ادفع من الرصيد" }),
		).toBeVisible();
	});
});
```

Create `dashboard/src/features/wallet/MoveToWallet.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { CanProvider } from "@/features/identity/permissions";
import type { Me } from "@/features/identity/schemas";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { paymentRow, recordRow } from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { walletEntry } from "@/test/wallet-fixtures";
import { walletApi } from "./api";
import { MoveToWallet } from "./MoveToWallet";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, walletApi: { ...actual.walletApi, move: vi.fn() } };
});

function renderMove(payment = paymentRow(), me: Me = adminWith("balances")) {
	return renderWithRouter(
		<CanProvider me={me}>
			<MoveToWallet payment={payment} />
		</CanProvider>,
	);
}

describe("MoveToWallet", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(walletApi.move).mockResolvedValue(walletEntry({ kind: "refund" }));
	});

	it("moves a completed invoice payment after confirming", async () => {
		const user = userEvent.setup();
		renderMove();
		await user.click(await screen.findByRole("button", { name: "Move to balance" }));
		await user.click(
			within(await screen.findByRole("alertdialog")).getByRole("button", {
				name: "Move this payment to the balance",
			}),
		);
		await waitFor(() => expect(walletApi.move).toHaveBeenCalledWith(61));
		expect(await screen.findByText("Payment moved to the balance.")).toBeVisible();
	});

	it("says why the server refused", async () => {
		const user = userEvent.setup();
		vi.mocked(walletApi.move).mockRejectedValueOnce(
			new AxiosError("Conflict", "409", undefined, undefined, {
				status: 409,
				data: { detail: "x", code: "billing.payment_not_completed" },
			} as never),
		);
		renderMove();
		await user.click(await screen.findByRole("button", { name: "Move to balance" }));
		await user.click(
			within(await screen.findByRole("alertdialog")).getByRole("button", {
				name: "Move this payment to the balance",
			}),
		);
		expect(
			await screen.findByText(
				"Only a completed payment can be moved to the balance.",
			),
		).toBeVisible();
	});

	it.each([
		["a refunded payment", paymentRow({ status: "refunded" }), adminWith("balances")],
		["a moved payment", paymentRow({ status: "credited" }), adminWith("balances")],
		["a standalone record", recordRow(), adminWith("balances")],
		["balances off", paymentRow(), adminWith()],
		[
			"no payment.update",
			paymentRow(),
			{ ...staffMe("wallet.update"), features: ["balances"] },
		],
		[
			"no wallet.update",
			paymentRow(),
			{ ...staffMe("payment.update"), features: ["balances"] },
		],
	])("is not offered for %s", async (_, payment, me) => {
		renderMove(payment, me as Me);
		await act(async () => {});
		expect(screen.queryByRole("button", { name: "Move to balance" })).toBeNull();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/wallet/PayFromWallet.test.tsx src/features/wallet/MoveToWallet.test.tsx`
Expected: FAIL (the components do not exist).

- [ ] **Step 3: Implement**

Create `dashboard/src/features/wallet/PayFromWallet.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import type { InvoiceDetail } from "@/features/billing/schemas";
import { saveOrShowErrors, useFillOnOpen } from "@/features/finance/shared";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { useFieldError } from "@/lib/field-error";
import { formatMoney, toMajor, toMinor } from "@/lib/money";
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
	SubmitButton,
	toast,
} from "@/ui";
import { walletApi } from "./api";
import { useStudentWallet, useWalletMutation } from "./queries";
import { type PayFormValues, payFormSchema } from "./schemas";

function PayDialog({
	invoice,
	office,
	available,
}: {
	invoice: InvoiceDetail;
	office: boolean;
	available: number;
}) {
	const { t, i18n } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const pay = useWalletMutation(walletApi.payInvoice);
	const due = invoice.balance_minor;
	const suggested = Math.min(available, due);
	const money = (minor: number) =>
		formatMoney(minor, invoice.currency, i18n.language);
	const initial = useCallback(
		(): PayFormValues => ({ amount: toMajor(suggested, invoice.currency) }),
		[suggested, invoice.currency],
	);
	const {
		register,
		handleSubmit,
		setError,
		setFocus,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<PayFormValues>({
		resolver: zodResolver(payFormSchema(available, due, invoice.currency)),
		defaultValues: initial(),
	});
	useFillOnOpen({ open, ready: true, reset, setFocus, initial, first: "amount" });

	async function onSubmit(values: PayFormValues) {
		// W21: the family sends no amount (the server's default, E-11).
		const body = office
			? {
					invoiceId: invoice.id,
					amount_minor: toMinor(values.amount.trim(), invoice.currency),
				}
			: { invoiceId: invoice.id };
		const saved = await saveOrShowErrors(() => pay.mutateAsync(body), setError);
		if (saved) {
			setOpen(false);
			toast({ description: t("wallet.pay.done"), variant: "success" });
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("wallet.pay.action")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("wallet.pay.title")}</DialogTitle>
				<DialogDescription>
					{t("wallet.pay.body", {
						amount: money(suggested),
						balance: money(available),
					})}
				</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					{office ? (
						<Field
							id="wallet-pay-amount"
							label={t("wallet.pay.amount", { currency: invoice.currency })}
							error={fieldError(errors.amount?.message)}
							required
						>
							<Input inputMode="decimal" dir="ltr" {...register("amount")} />
						</Field>
					) : null}
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.root.server.message)}
							</AlertDescription>
						</Alert>
					) : null}
					{!office && errors.amount?.message ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.amount.message)}
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
							{t("wallet.pay.confirm")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

/** B3e §6, E-11, plan W21: "Pay from balance" on an invoice page. Shown
 * while the invoice is not void and has a balance, and the student's wallet
 * in its currency is above 0, to a viewer who may spend it: the family by
 * role (the server checks E-17; a payer-only reader cannot read the wallet,
 * so the button stays hidden), the office with wallet.update and
 * wallet.view_any. The office may lower the amount. */
export function PayFromWallet({
	invoice,
	office,
}: {
	invoice: InvoiceDetail;
	office: boolean;
}) {
	const can = useCan();
	const hasFeature = useHasFeature();
	const allowed =
		hasFeature("balances") &&
		(!office || (can("wallet.update") && can("wallet.view_any")));
	const open = invoice.status !== "void" && invoice.balance_minor > 0;
	const { data } = useStudentWallet(invoice.student.id, allowed && open);
	const available =
		data?.balances.find((b) => b.currency === invoice.currency)
			?.balance_minor ?? 0;
	if (!allowed || !open || available <= 0) return null;
	return <PayDialog invoice={invoice} office={office} available={available} />;
}
```

Create `dashboard/src/features/wallet/MoveToWallet.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import type { Payment } from "@/features/billing/schemas";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { errorText } from "@/lib/form-errors";
import { toast } from "@/ui";
import { walletApi } from "./api";
import { useWalletMutation } from "./queries";

/** B3e §6, E-12: "Move to balance" on a completed invoice payment, for the
 * office with wallet.update and payment.update while `balances` is on. */
export function MoveToWallet({ payment }: { payment: Payment }) {
	const { t } = useTranslation();
	const can = useCan();
	const hasFeature = useHasFeature();
	const move = useWalletMutation(walletApi.move);
	if (
		!hasFeature("balances") ||
		!can("wallet.update") ||
		!can("payment.update") ||
		payment.status !== "completed" ||
		payment.invoice === null
	) {
		return null;
	}
	return (
		<Confirm
			action={t("wallet.move.action")}
			title={t("wallet.move.title")}
			body={t("wallet.move.body")}
			onConfirm={() =>
				move.mutate(payment.id, {
					onSuccess: () =>
						toast({ description: t("wallet.move.done"), variant: "success" }),
					onError: (error) =>
						toast({ description: errorText(error, t), variant: "destructive" }),
				})
			}
		/>
	);
}
```

`dashboard/src/features/wallet/index.ts`, add:

```ts
export { MoveToWallet } from "./MoveToWallet";
export { PayFromWallet } from "./PayFromWallet";
```

Replace `dashboard/src/routes/_authed/billing.invoices.$invoiceId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { InvoicePage } from "@/features/billing";
import { usePageTitle } from "@/features/branding";
import { MoveToWallet, PayFromWallet } from "@/features/wallet";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/billing/invoices/$invoiceId")({
	staticData: { permission: "invoice.view", feature: "invoices" },
	component: function InvoiceRoute() {
		const { t } = useTranslation();
		const { invoiceId } = Route.useParams();
		usePageTitle(t("billing.invoice.title"));
		return (
			<>
				<PageHeader title={t("billing.invoice.title")} />
				{/* B3e §6: wallet actions come from the route; billing never imports them. */}
				<InvoicePage
					invoiceId={invoiceId}
					admin
					actions={(invoice) => <PayFromWallet invoice={invoice} office />}
					paymentActions={(payment) => <MoveToWallet payment={payment} />}
				/>
			</>
		);
	},
});
```

Replace `dashboard/src/routes/_authed/learning.invoices.$invoiceId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { InvoicePage } from "@/features/billing";
import { usePageTitle } from "@/features/branding";
import { PayOnline } from "@/features/gateways";
import { PayFromWallet } from "@/features/wallet";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/learning/invoices/$invoiceId")({
	staticData: { feature: "invoices" },
	component: function FamilyInvoiceRoute() {
		const { t } = useTranslation();
		const { invoiceId } = Route.useParams();
		usePageTitle(t("billing.invoice.title"));
		return (
			<>
				<PageHeader title={t("billing.invoice.title")} />
				<InvoicePage
					invoiceId={invoiceId}
					admin={false}
					actions={(invoice) => (
						<>
							<PayOnline invoice={invoice} />
							<PayFromWallet invoice={invoice} office={false} />
						</>
					)}
				/>
			</>
		);
	},
});
```

- [ ] **Step 4: Run, type-check, lint, commit**

Run: `$DASH pnpm vitest run src/features/wallet src/features/billing src/routes`
Expected: PASS.
Run: `just test-frontend && just lint-frontend`

```bash
git -C dashboard add src/features/wallet 'src/routes/_authed/billing.invoices.$invoiceId.tsx' 'src/routes/_authed/learning.invoices.$invoiceId.tsx'
git -C dashboard commit -m "feat(wallet): pay an invoice from the balance; move a payment to it (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 14: Dashboard — the family's Balance page, the online top-up and the return page

**Files:**
- Create: `dashboard/src/features/wallet/OnlineTopUpDialog.tsx`, `FamilyWalletPage.tsx`, `OnlineTopUpDialog.test.tsx`, `FamilyWalletPage.test.tsx`, `dashboard/src/routes/_authed/learning.wallet.tsx`
- Modify: `dashboard/src/features/wallet/index.ts`, `dashboard/src/features/gateways/ReturnPage.tsx`, `ReturnPage.test.tsx`, `dashboard/src/features/shell/nav.ts` (B3 marker), `nav.test.ts`, `dashboard/src/routes/permissions.test.ts`, `dashboard/src/locales/en/gateways.json`, `dashboard/src/locales/ar/gateways.json`, `dashboard/src/routeTree.gen.ts` (generated)

**Interfaces:**
- Consumes: Task 11's `walletApi.mine`, `topUpOptions`, `startTopUp`, `useMyWallets`, `useTopUpOptions`, `onlineTopUpSchema`, `amountIssue`, `Statement`; gateways' `go` (`@/features/gateways/redirect`), `gatewaysErrorText`, `PROVIDER_NAMES`.
- Produces:
  - route `/_authed/learning/wallet` (`staticData: { feature: "balances" }`, under the `learning` layout: students and parents);
  - `<FamilyWalletPage />`, `<OnlineTopUpDialog wallet />`, exported;
  - nav item `/learning/wallet` (`wallet.nav`, group `learning`, `requiresRole: ["student", "parent"]`, feature `balances`) under the B3 marker;
  - `ReturnPage` asks `me` for a `wallet_topup` checkout too and links back to `/learning/wallet` (W24); `gateways.return.backToBalance`.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/wallet/OnlineTopUpDialog.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { go } from "@/features/gateways/redirect";
import i18n from "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { familyWallet } from "@/test/wallet-fixtures";
import { walletApi } from "./api";
import { OnlineTopUpDialog } from "./OnlineTopUpDialog";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		walletApi: { ...actual.walletApi, topUpOptions: vi.fn(), startTopUp: vi.fn() },
	};
});
vi.mock("@/features/gateways/redirect", () => ({ go: vi.fn() }));

const STARTED = {
	id: "6f1c2a8e-0000-4000-8000-000000000001",
	redirect_url: "https://checkout.test/cs_1",
	amount_minor: 5000,
	fee_minor: 250,
	currency: "USD",
};

async function open(user: ReturnType<typeof userEvent.setup>) {
	await user.click(screen.getByRole("button", { name: "Top up" }));
	return screen.findByRole("dialog");
}

describe("OnlineTopUpDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(walletApi.topUpOptions).mockResolvedValue({
			currencies: ["EGP", "USD"],
			providers: ["stripe", "paypal"],
		});
		vi.mocked(walletApi.startTopUp).mockResolvedValue(STARTED);
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("asks for the providers of the typed amount, starts, shows the fee and redirects", async () => {
		const user = userEvent.setup();
		renderWithRouter(<OnlineTopUpDialog wallet={familyWallet()} />);
		const dialog = await open(user);
		await user.selectOptions(within(dialog).getByLabelText(/^Currency/), "USD");
		await user.type(within(dialog).getByLabelText(/^Amount/), "50");
		await waitFor(() =>
			expect(walletApi.topUpOptions).toHaveBeenLastCalledWith({
				student: 11,
				currency: "USD",
				amount_minor: 5000,
			}),
		);
		await user.click(
			await within(dialog).findByRole("button", { name: "Pay with Stripe" }),
		);
		await waitFor(() =>
			expect(walletApi.startTopUp).toHaveBeenCalledWith({
				student: 11,
				amount_minor: 5000,
				currency: "USD",
				provider: "stripe",
			}),
		);
		const sheet = await screen.findByRole("dialog", { name: "Top up online" });
		expect(within(sheet).getByText("$2.50")).toBeVisible();
		expect(within(sheet).getByText("$52.50")).toBeVisible();
		await user.click(
			within(sheet).getByRole("button", { name: "Continue to Stripe" }),
		);
		expect(go).toHaveBeenCalledWith("https://checkout.test/cs_1");
	});

	it("asks nothing for a bad amount and says when no provider takes it", async () => {
		const user = userEvent.setup();
		vi.mocked(walletApi.topUpOptions).mockResolvedValue({
			currencies: ["EGP", "USD"],
			providers: [],
		});
		renderWithRouter(<OnlineTopUpDialog wallet={familyWallet()} />);
		const dialog = await open(user);
		await user.type(within(dialog).getByLabelText(/^Amount/), "0");
		expect(
			await within(dialog).findByText(
				"Enter an amount above zero, like 150 or 150.50.",
			),
		).toBeVisible();
		expect(walletApi.topUpOptions).not.toHaveBeenCalled();
		await user.clear(within(dialog).getByLabelText(/^Amount/));
		await user.type(within(dialog).getByLabelText(/^Amount/), "5");
		expect(
			await within(dialog).findByText(
				"No online payment takes this amount in this currency.",
			),
		).toBeVisible();
	});

	it("says why a start was refused", async () => {
		const user = userEvent.setup();
		vi.mocked(walletApi.startTopUp).mockRejectedValueOnce(
			new AxiosError("Forbidden", "403", undefined, undefined, {
				status: 403,
				data: { detail: "x", code: "identity.impersonating" },
			} as never),
		);
		renderWithRouter(<OnlineTopUpDialog wallet={familyWallet()} />);
		const dialog = await open(user);
		await user.type(within(dialog).getByLabelText(/^Amount/), "50");
		await user.click(
			await within(dialog).findByRole("button", { name: "Pay with PayPal" }),
		);
		expect(await within(dialog).findByRole("alert")).toBeVisible();
		expect(go).not.toHaveBeenCalled();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		const user = userEvent.setup();
		renderWithRouter(<OnlineTopUpDialog wallet={familyWallet()} />);
		await user.click(screen.getByRole("button", { name: "شحن" }));
		expect(
			await screen.findByRole("dialog", { name: "شحن رصيد Yusuf" }),
		).toBeVisible();
	});
});
```

Create `dashboard/src/features/wallet/FamilyWalletPage.test.tsx`:

```tsx
import { act, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import type { Me } from "@/features/identity/schemas";
import i18n from "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { familyWallet, walletEntry } from "@/test/wallet-fixtures";
import { walletApi } from "./api";
import { FamilyWalletPage } from "./FamilyWalletPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		walletApi: { ...actual.walletApi, mine: vi.fn(), entries: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const PARENT: Me = {
	id: 31,
	email: "p@x.test",
	full_name: "Omar",
	role: "parent",
	profiles: [],
	features: ["invoices", "balances", "online_payments"],
};
// What a family receives (E-22): no `created_by`, no adjustment reason.
const { created_by: _by, ...FAMILY_ROW } = walletEntry({
	kind: "adjustment",
	amount_minor: 5000,
	note: "",
	payment_id: null,
});

function renderPage(me: Me = PARENT) {
	return renderWithRouter(
		<CanProvider me={me}>
			<FamilyWalletPage />
		</CanProvider>,
		{ extraPaths: ["/learning/invoices/$invoiceId"] },
	);
}

describe("FamilyWalletPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(walletApi.mine).mockResolvedValue([
			familyWallet({ balances: [{ currency: "EGP", balance_minor: 35000 }] }),
			familyWallet({
				student: { id: 12, name: "Maryam" },
				balances: [],
				topup_currencies: ["EGP"],
			}),
		]);
		vi.mocked(walletApi.entries).mockResolvedValue(page([FAMILY_ROW]));
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("shows a parent each child's balances and statements, without staff names", async () => {
		renderPage();
		const yusuf = await screen.findByRole("region", { name: "Yusuf" });
		expect(within(yusuf).getAllByText("EGP 350.00")[0]).toBeVisible();
		const statement = within(yusuf).getByRole("region", {
			name: "Statement in EGP",
		});
		expect(await within(statement).findByText("Adjustment")).toBeVisible();
		expect(within(statement).queryByText("By")).toBeNull();
		expect(within(statement).queryByText("Amina")).toBeNull();
		const maryam = screen.getByRole("region", { name: "Maryam" });
		expect(within(maryam).getByText("No balance yet.")).toBeVisible();
		expect(within(maryam).getByRole("button", { name: "Top up" })).toBeVisible();
		expect(walletApi.entries).toHaveBeenCalledWith(11, { currency: "EGP", page: 1 });
	});

	it("offers no online top-up while online payments are off", async () => {
		renderPage({ ...PARENT, features: ["invoices", "balances"] });
		await screen.findByRole("region", { name: "Yusuf" });
		expect(screen.queryByRole("button", { name: "Top up" })).toBeNull();
	});

	it("says when there is no student, or the balances failed", async () => {
		vi.mocked(walletApi.mine).mockResolvedValueOnce([]);
		const { unmount } = renderPage();
		expect(await screen.findByText("No students to show.")).toBeVisible();
		unmount();
		vi.mocked(walletApi.mine).mockRejectedValueOnce(new Error("offline"));
		renderPage();
		expect(
			await screen.findByText("The balances could not be loaded."),
		).toBeVisible();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderPage();
		const yusuf = await screen.findByRole("region", { name: "Yusuf" });
		expect(
			within(yusuf).getByRole("region", { name: "كشف الحساب بـ EGP" }),
		).toBeVisible();
	});
});
```

`dashboard/src/features/gateways/ReturnPage.test.tsx`: `PATHS` gains `"/learning/wallet"`; append inside the `describe`:

```tsx
	it("asks who the payer is for a top-up and links back to the balance", async () => {
		vi.mocked(gatewaysApi.checkout).mockResolvedValue({
			...body("completed"),
			purpose: "wallet_topup",
			reference_id: 7,
		} as never);
		renderWithRouter(<ReturnPage checkoutId={ID} />, { extraPaths: PATHS });
		expect(await screen.findByText("Paid — thank you.")).toBeVisible();
		expect(
			await screen.findByRole("link", { name: "Back to the balance" }),
		).toHaveAttribute("href", expect.stringContaining("/learning/wallet"));
		expect(identityApi.me).toHaveBeenCalled();
	});

	it("offers to try a failed top-up again from the balance", async () => {
		vi.mocked(gatewaysApi.checkout).mockResolvedValue({
			...body("failed"),
			purpose: "wallet_topup",
			reference_id: 7,
		} as never);
		renderWithRouter(<ReturnPage checkoutId={ID} />, { extraPaths: PATHS });
		expect(
			await screen.findByRole("link", { name: "Try again" }),
		).toHaveAttribute("href", expect.stringContaining("/learning/wallet"));
	});
```

`dashboard/src/features/shell/nav.test.ts`:
- in "ships the grouped admin areas in order", add `"/learning/wallet",` right after `"/settings/gateways",`;
- in "names a feature on exactly the items that belong to one", add `"/learning/wallet": "balances",` after `"/settings/gateways": "online_payments",`;
- in "shows students and parents their sessions, subscriptions and invoices", the list becomes `["/", "/learning/sessions", "/learning/subscriptions", "/learning/invoices", "/learning/wallet", "/learning/progress", "/account"]` (comment `// B3e` on the wallet line).

`dashboard/src/routes/permissions.test.ts`:
- `FEATURE_SCREENS`, after `"/_authed/settings/gateways": "online_payments",`: `"/_authed/learning/wallet": "balances",  // B3e`;
- `FEATURE_WORDS`: add `|wallet` after `|checkouts`.

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/wallet src/features/gateways/ReturnPage.test.tsx src/features/shell/nav.test.ts src/routes/permissions.test.ts`
Expected: FAIL (the components and route do not exist; the return page links to the invoice).

- [ ] **Step 3: Implement**

Create `dashboard/src/features/wallet/OnlineTopUpDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useMutation } from "@tanstack/react-query";
import { useCallback, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import { useFillOnOpen } from "@/features/finance/shared";
import { gatewaysErrorText } from "@/features/gateways/errors";
import { go } from "@/features/gateways/redirect";
import {
	PROVIDER_NAMES,
	type Provider,
	type StartedCheckout,
} from "@/features/gateways/schemas";
import { useFieldError } from "@/lib/field-error";
import { toMinor } from "@/lib/money";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Input,
	Select,
} from "@/ui";
import { walletApi } from "./api";
import { useTopUpOptions } from "./queries";
import {
	amountIssue,
	type FamilyWallet,
	type OnlineTopUpValues,
	onlineTopUpSchema,
} from "./schemas";

/** The server's fee and total before leaving for the provider, as Pay
 * online shows them (spec §6). */
function TopUpSheet({
	sheet,
	onClose,
}: {
	sheet: (StartedCheckout & { provider: Provider }) | null;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	return (
		<Dialog open={sheet !== null} onOpenChange={(open) => !open && onClose()}>
			{sheet ? (
				<DialogContent>
					<DialogTitle>{t("wallet.family.sheetTitle")}</DialogTitle>
					<DialogDescription className="sr-only">
						{t("wallet.family.sheetTitle")}
					</DialogDescription>
					<dl className="grid grid-cols-2 gap-2 text-sm">
						<dt>{t("wallet.family.amount")}</dt>
						<dd>
							<Money minor={sheet.amount_minor} currency={sheet.currency} />
						</dd>
						<dt>{t("gateways.pay.fee")}</dt>
						<dd>
							<Money minor={sheet.fee_minor} currency={sheet.currency} />
						</dd>
						<dt className="font-medium">{t("gateways.pay.total")}</dt>
						<dd className="font-medium">
							<Money
								minor={sheet.amount_minor + sheet.fee_minor}
								currency={sheet.currency}
							/>
						</dd>
					</dl>
					<DialogFooter>
						<Button variant="outline" onClick={onClose}>
							{t("gateways.pay.cancel")}
						</Button>
						<Button onClick={() => go(sheet.redirect_url)}>
							{t("gateways.pay.continue", {
								provider: PROVIDER_NAMES[sheet.provider],
							})}
						</Button>
					</DialogFooter>
				</DialogContent>
			) : null}
		</Dialog>
	);
}

/** B3e E-15, §6: a family tops a student up online: the amount and a
 * currency from `topup_currencies`, then the providers that take it, then
 * the server's fee and total, then the provider. */
export function OnlineTopUpDialog({ wallet }: { wallet: FamilyWallet }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const [sheet, setSheet] = useState<
		(StartedCheckout & { provider: Provider }) | null
	>(null);
	const [failure, setFailure] = useState("");
	const start = useMutation({ mutationFn: walletApi.startTopUp });
	const initial = useCallback(
		(): OnlineTopUpValues => ({
			amount: "",
			currency: wallet.topup_currencies[0] ?? "",
		}),
		[wallet.topup_currencies],
	);
	const {
		register,
		watch,
		setFocus,
		reset,
		formState: { errors },
	} = useForm<OnlineTopUpValues>({
		resolver: zodResolver(onlineTopUpSchema),
		defaultValues: initial(),
		mode: "onChange",
	});
	useFillOnOpen({ open, ready: true, reset, setFocus, initial, first: "amount" });
	const amount = watch("amount");
	const currency = watch("currency");
	const valid =
		/^[A-Z]{3}$/.test(currency) && amountIssue(amount, currency) === null;
	const minor = valid ? toMinor(amount.trim(), currency) : undefined;
	const options = useTopUpOptions(
		{ student: wallet.student.id, currency, amount_minor: minor },
		open && valid,
	);
	const providers = options.data?.providers ?? [];

	async function begin(provider: Provider) {
		setFailure("");
		try {
			const result = await start.mutateAsync({
				student: wallet.student.id,
				amount_minor: minor as number,
				currency,
				provider,
			});
			setOpen(false);
			setSheet({ ...result, provider });
		} catch (error) {
			setFailure(gatewaysErrorText(error, t));
		}
	}

	return (
		<>
			<Dialog open={open} onOpenChange={setOpen}>
				<DialogTrigger asChild>
					<Button size="sm">{t("wallet.family.topUp")}</Button>
				</DialogTrigger>
				<DialogContent>
					<DialogTitle>
						{t("wallet.family.topUpTitle", { name: wallet.student.name })}
					</DialogTitle>
					<DialogDescription className="sr-only">
						{t("wallet.family.topUpTitle", { name: wallet.student.name })}
					</DialogDescription>
					<form
						onSubmit={(event) => event.preventDefault()}
						className="mt-4 flex flex-col gap-4"
						noValidate
					>
						<div className="grid gap-4 sm:grid-cols-2">
							<Field
								id="family-topup-amount"
								label={t("wallet.topUp.amount")}
								error={fieldError(errors.amount?.message)}
								required
							>
								<Input inputMode="decimal" dir="ltr" {...register("amount")} />
							</Field>
							<Field
								id="family-topup-currency"
								label={t("wallet.topUp.currency")}
								error={fieldError(errors.currency?.message)}
								required
							>
								<Select dir="ltr" {...register("currency")}>
									{wallet.topup_currencies.map((code) => (
										<option key={code} value={code}>
											{code}
										</option>
									))}
								</Select>
							</Field>
						</div>
						{!valid ? null : options.isPending ? (
							<p className="text-sm text-muted-foreground">
								{t("wallet.family.providersLoading")}
							</p>
						) : providers.length === 0 ? (
							<p className="text-sm text-muted-foreground">
								{t("wallet.family.noProviders")}
							</p>
						) : (
							<div
								role="group"
								aria-label={t("wallet.family.providers")}
								className="flex flex-wrap gap-2"
							>
								{providers.map((provider) => (
									<Button
										key={provider}
										type="button"
										size="sm"
										disabled={start.isPending}
										onClick={() => void begin(provider)}
									>
										{t("wallet.family.pay", {
											provider: PROVIDER_NAMES[provider],
										})}
									</Button>
								))}
							</div>
						)}
						{failure ? (
							<Alert variant="destructive">
								<AlertDescription>{failure}</AlertDescription>
							</Alert>
						) : null}
					</form>
				</DialogContent>
			</Dialog>
			<TopUpSheet sheet={sheet} onClose={() => setSheet(null)} />
		</>
	);
}
```

(A destructive `Alert` renders `role="alert"` (`src/ui/alert.tsx`); the refused start's text is `gateways.errors.impersonating`, through `gatewaysErrorText`.)

Create `dashboard/src/features/wallet/FamilyWalletPage.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import { useHasFeature } from "@/features/identity/permissions";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
} from "@/ui";
import { OnlineTopUpDialog } from "./OnlineTopUpDialog";
import { useMyWallets } from "./queries";
import type { FamilyWallet } from "./schemas";
import { Statement } from "./Statement";

function StudentSection({
	wallet,
	online,
}: {
	wallet: FamilyWallet;
	online: boolean;
}) {
	const { t } = useTranslation();
	const headingId = `wallet-student-${wallet.student.id}`;
	return (
		<section aria-labelledby={headingId}>
			<Card>
				<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
					<CardTitle id={headingId}>{wallet.student.name}</CardTitle>
					{online ? <OnlineTopUpDialog wallet={wallet} /> : null}
				</CardHeader>
				<CardContent className="flex flex-col gap-6 pt-4">
					{wallet.balances.length === 0 ? (
						<p className="text-sm text-muted-foreground">
							{t("wallet.card.none")}
						</p>
					) : (
						wallet.balances.map((balance) => (
							<section
								key={balance.currency}
								aria-label={t("wallet.statement.title", {
									currency: balance.currency,
								})}
								className="flex flex-col gap-2"
							>
								<p className="text-2xl font-semibold">
									<Money
										minor={balance.balance_minor}
										currency={balance.currency}
									/>
								</p>
								<Statement
									studentId={wallet.student.id}
									currency={balance.currency}
									office={false}
								/>
							</section>
						))
					)}
				</CardContent>
			</Card>
		</section>
	);
}

/** B3e §6, Family → Balance: one section per student the reader may use
 * (a student alone sees their own), each currency's balance and statement
 * (E-22), and Top up while `online_payments` is on. */
export function FamilyWalletPage() {
	const { t } = useTranslation();
	const hasFeature = useHasFeature();
	const { data, isPending, isError } = useMyWallets();
	if (isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("wallet.family.loadError")}</AlertDescription>
			</Alert>
		);
	}
	if (isPending) return <Spinner />;
	if (data.length === 0) {
		return (
			<p className="text-sm text-muted-foreground">{t("wallet.family.none")}</p>
		);
	}
	const online = hasFeature("online_payments");
	return (
		<div className="flex flex-col gap-6">
			{data.map((wallet) => (
				<StudentSection key={wallet.student.id} wallet={wallet} online={online} />
			))}
		</div>
	);
}
```

`dashboard/src/features/wallet/index.ts`, add:

```ts
export { FamilyWalletPage } from "./FamilyWalletPage";
export { OnlineTopUpDialog } from "./OnlineTopUpDialog";
```

Create `dashboard/src/routes/_authed/learning.wallet.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { FamilyWalletPage } from "@/features/wallet";
import { PageHeader } from "@/ui";

/** B3e §6: Family → Balance (students and parents, the `learning` layout). */
export const Route = createFileRoute("/_authed/learning/wallet")({
	staticData: { feature: "balances" },
	component: function LearningWalletRoute() {
		const { t } = useTranslation();
		usePageTitle(t("wallet.family.title"));
		return (
			<>
				<PageHeader title={t("wallet.family.title")} />
				<FamilyWalletPage />
			</>
		);
	},
});
```

Regenerate the route tree: `$DASH pnpm exec vite build`.

`dashboard/src/features/shell/nav.ts`: add `PiggyBank` to the lucide import (between `Package` and `Presentation`) and, under `// ── phase B3 ──`, after the `/settings/gateways` item:

```ts
	// B3e: a student's or parent's balances (E-17).
	{
		to: "/learning/wallet",
		labelKey: "wallet.nav",
		icon: PiggyBank,
		group: "learning",
		requiresRole: ["student", "parent"],
		feature: "balances",
	},
```

`dashboard/src/features/gateways/ReturnPage.tsx`:
- the `me` query (W24):

```tsx
	// The page is public (D17): only a private purpose's checkout links back
	// into the app (an invoice, B3e's wallet top-up), so only then is the
	// payer asked who they are. An anonymous payment-link payer never calls
	// me/ (which would refuse them).
	const purpose = data?.purpose;
	const meQuery = useMe({
		enabled: purpose === "invoice" || purpose === "wallet_topup",
	});
```

- after `const office = …`, replace the `invoice` constant and `link` with:

```tsx
	// Until `me` settles the page cannot tell the office's invoice page from
	// the family's, so it shows no link rather than the wrong one.
	const settled = !meQuery.isPending;
	const invoice = data.purpose === "invoice" && settled;
	const topUp = data.purpose === "wallet_topup" && settled;
```

```tsx
	const link = (label: string) =>
		invoice ? (
			<InvoiceLink
				invoiceId={String(data.reference_id)}
				office={office}
				label={label}
			/>
		) : topUp ? (
			<Button asChild variant="outline" size="sm">
				<Link to="/learning/wallet">{label}</Link>
			</Button>
		) : null;
```

- the back link's label: `link(topUp ? t("gateways.return.backToBalance") : t("gateways.return.back"))`.

`dashboard/src/locales/en/gateways.json`, in `return`: `"backToBalance": "Back to the balance"`; `dashboard/src/locales/ar/gateways.json`: `"backToBalance": "العودة إلى الرصيد"`.

- [ ] **Step 4: Run, type-check, lint, commit**

Run: `$DASH pnpm vitest run src/features/wallet src/features/gateways src/features/shell src/routes src/locales`
Expected: PASS.
Run: `just test-frontend && just lint-frontend`

```bash
git -C dashboard add src/features/wallet src/features/gateways src/features/shell src/routes src/routeTree.gen.ts src/locales
git -C dashboard commit -m "feat(wallet): the family's Balance page and online top-up; the return page links back (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 15: The e2e journey

**Files:**
- Create: `dashboard/e2e/b3-wallet.spec.ts`

**Interfaces:**
- Consumes: the whole of Part A through Caddy; `manage("set_features", …)`; `login`, `DEMO_URL`, `DEMO_ADMIN`, `expectLoggedIn`, `acceptInvite`, `invoiceHeader` from `e2e/fixtures.ts`. Rerun-safe (spec §9): USD only (never touching `b3-finance.spec.ts`'s EGP deltas), and a fresh parent and child each run.

- [ ] **Step 1: Write the spec**

```ts
import { expect, test } from "@playwright/test";
import {
	acceptInvite,
	DEMO_ADMIN,
	DEMO_URL,
	expectLoggedIn,
	invoiceHeader,
	login,
} from "./fixtures";
import { manage } from "./manage";

// B3e spec §9: a fresh parent and child each run, in USD. The admin tops the
// child up 300.00 in cash; the parent pays a 200.00 invoice from the balance
// (100.00 left); the admin moves that payment back to the balance (300.00,
// the invoice unpaid again); the parent tops up 50.00 online through the
// Stripe simulator (350.00).
test("a family's balance is topped up, spent, refilled by a moved payment and topped up online", async ({
	page,
	browser,
}) => {
	// 1. A database seeded before B3e would not have the switches on.
	manage("set_features", "demo", "--on", "invoices", "online_payments", "balances");
	const stamp = Date.now();
	const parent = `E2E Wallet Payer ${stamp}`;
	const parentEmail = `e2e-wallet-${stamp}@e2e.test`;
	const child = `E2E Wallet Child ${stamp}`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// 2. The parent (invited by email) and the child, as b3-online-payments does …
	await page.goto(`${DEMO_URL}/app/people/parents/new`);
	await page.getByLabel(/^full name/i).fill(parent);
	await page.getByLabel(/^email/i).fill(parentEmail);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/parents\/\d+$/);

	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(child);
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);
	const childUrl = page.url();
	await page.getByLabel("Find a parent").fill(parent);
	await page.getByRole("button", { name: `Link ${parent}`, exact: true }).click();
	await expect(
		page.getByRole("button", { name: `Unlink ${parent}`, exact: true }),
	).toBeVisible();

	// … and a 200.00 USD invoice through the invoice form (billed to the parent).
	const dueOn = new Date(Date.now() + 30 * 86_400_000).toISOString().slice(0, 10);
	await page.goto(`${DEMO_URL}/app/billing/invoices/new`);
	await page.getByLabel("Find a student").fill(child);
	await page.getByLabel(/^Student/).selectOption({ label: child });
	await page.getByLabel(/^Currency/).selectOption("USD");
	await page.getByLabel(/^Amount/).fill("200.00");
	await page.getByLabel(/^Due/).fill(dueOn);
	await page.getByLabel(/^Description/).fill(`E2E wallet ${stamp}`);
	await page.getByRole("button", { name: "Create invoice" }).click();
	await expect(page).toHaveURL(/\/app\/billing\/invoices\/\d+$/);
	const invoiceUrl = page.url();
	const invoiceId = invoiceUrl.match(/invoices\/(\d+)$/)?.[1] ?? "";
	const number =
		(await page.getByRole("heading", { name: /^INV-\d{6}$/ }).textContent()) ?? "";

	// 3. On the child's page the admin adds a cash top-up of 300.00 USD.
	await page.goto(childUrl);
	await page.getByRole("button", { name: "Top up" }).click();
	const topUp = page.getByRole("dialog");
	await topUp.getByLabel(/^Amount/).fill("300.00");
	await topUp.getByLabel(/^Currency/).selectOption("USD");
	await topUp.getByLabel(/^Method/).selectOption("cash");
	await topUp.getByRole("button", { name: "Add to balance" }).click();
	await expect(page.getByText("Balance topped up.")).toBeVisible();
	await expect(page.getByRole("tab", { name: "USD" })).toBeVisible();
	await expect(page.getByRole("tabpanel").getByText("$300.00").first()).toBeVisible();

	// 4. The parent sees 300.00 and pays the invoice from the balance.
	const guardian = await acceptInvite(browser, parentEmail, "e2e-Payer-2026", parent);
	await guardian.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	await guardian.goto(`${DEMO_URL}/app/learning/wallet`);
	const balance = guardian.getByRole("region", { name: child });
	await expect(balance.getByText("$300.00").first()).toBeVisible();
	await guardian.goto(`${DEMO_URL}/app/learning/invoices/${invoiceId}`);
	await guardian.getByRole("button", { name: "Pay from balance" }).click();
	const confirm = guardian.getByRole("dialog");
	await expect(confirm).toContainText(
		"Pay $200.00 from the balance ($300.00 available).",
	);
	await confirm.getByRole("button", { name: "Pay", exact: true }).click();
	await expect(
		invoiceHeader(guardian, number).getByText("Paid", { exact: true }),
	).toBeVisible();
	await guardian.goto(`${DEMO_URL}/app/learning/wallet`);
	await expect(balance.getByText("$100.00").first()).toBeVisible();

	// 5. The admin moves that payment back to the balance: the invoice is
	// unpaid again and the balance is 300.00.
	await page.goto(invoiceUrl);
	const spent = page.locator("li").filter({ hasText: "· Balance" });
	await spent.getByRole("button", { name: "Move to balance" }).click();
	await page
		.getByRole("alertdialog")
		.getByRole("button", { name: "Move this payment to the balance" })
		.click();
	await expect(spent).toContainText("Moved to balance");
	await expect(
		invoiceHeader(page, number).getByText("Unpaid", { exact: true }),
	).toBeVisible();
	await page.goto(childUrl);
	await expect(
		page.getByRole("tabpanel").getByText("$300.00").first(),
	).toBeVisible();

	// 6. The parent tops up 50.00 USD online through the Stripe simulator.
	await guardian.goto(`${DEMO_URL}/app/learning/wallet`);
	await balance.getByRole("button", { name: "Top up" }).click();
	const online = guardian.getByRole("dialog");
	await online.getByLabel(/^Currency/).selectOption("USD");
	await online.getByLabel(/^Amount/).fill("50.00");
	await online.getByRole("button", { name: "Pay with Stripe" }).click();
	const sheet = guardian.getByRole("dialog", { name: "Top up online" });
	await expect(sheet.getByText("$2.50")).toBeVisible(); // the 5 % fee
	await expect(sheet.getByText("$52.50")).toBeVisible();
	await sheet.getByRole("button", { name: "Continue to Stripe" }).click();
	await expect(guardian).toHaveURL(/\/app\/pay\/simulate\//);
	await guardian.getByRole("button", { name: "Pay", exact: true }).click();
	await expect(guardian).toHaveURL(/\/app\/pay\/return\?checkout=/);
	await expect(guardian.getByText("Paid — thank you.")).toBeVisible();
	await guardian.getByRole("link", { name: "Back to the balance" }).click();
	await expect(guardian).toHaveURL(/\/app\/learning\/wallet$/);
	await expect(balance.getByText("$350.00").first()).toBeVisible();
	await guardian.context().close();
});
```

(Part B's step 7 is appended by Task 17, only if it runs.)

- [ ] **Step 2: Run it against this stream's fresh stack, twice**

Run: `just e2e e2e/b3-wallet.spec.ts` (stack up via `just dev-backend`; rebuild images first if dependencies changed, and use a fresh stack before trusting the result: `wallet.0001` and `billing.0009` must have run through `migrate_schemas`).
Expected: PASS. Run it a second time: it must pass again (a fresh parent and child each run; nothing seeded is read).

- [ ] **Step 3: Commit**

```bash
git -C dashboard add e2e/b3-wallet.spec.ts
git -C dashboard commit -m "test(e2e): top up, pay from, move into and top up online a student's balance (B3e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 16: Gates

**Files:** none new; fix what the gates find in the task that owns it.

- [ ] **Step 1: Backend**

Run: `just test-backend`
Expected: PASS, total coverage ≥ 80 %. Check `etqan/wallet/services/*.py`, `etqan/wallet/api/views.py` and the new billing functions are fully covered (`--cov-report=term-missing`).

- [ ] **Step 2: Lint and boundaries**

Run: `just lint` (ruff, biome, the colour check) and `just check-boundaries` (`lint-imports`).
Expected: PASS, including the four new wallet contracts and the two extended gateways contracts. If a contract fails, do not weaken it: move the import behind a service.

- [ ] **Step 3: Dashboard**

Run: `$DASH pnpm test:coverage`
Run: `just test-frontend`
Expected: PASS; lines and statements ≥ 80, branches and functions ≥ 70.

- [ ] **Step 4: Secrets**

Run, from the meta worktree (CI's directory scan, which covers the submodule working trees):

```bash
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:v8.30.1 dir /repo --redact --no-banner --exit-code 1
```

Expected: no leaks (the tests use placeholder keys from gateways' conftest only).

- [ ] **Step 5: End to end**

Run: `just e2e` (the whole suite, on a fresh stack).
Expected: PASS, including `b3-wallet.spec.ts`, `b3-online-payments.spec.ts`, `b3-payment-links.spec.ts` (its standalone record is still seeded first), `b3-finance.spec.ts` (EGP deltas only) and `billing.spec.ts` (Delete and Mark refunded now read the server's flags).

- [ ] **Step 6: Ledger, PRs and report**

- The orchestrator records E-9's refinement (spec §7): `python3 scripts/orchestration/ledger.py decide --source "B3e spec E-9" --affects B4,B7,B11 B3 "Billing refuses to refund, delete or edit wallet, top-up and credited payments, deciding on the locked row; only etqan.wallet undoes them."`; D36/D37 are already recorded.
- In the PR descriptions note: migrations `wallet.0001_initial` and `billing.0009_payment_wallet`; the feature `balances` built in place (off by default); the resource `wallet`; payment rows' new `refundable` and `wallet_topup`, the status `credited` and the method `wallet`; `billing.services.invoice_for` (was `online._readable`); the one card line on the trunk student page (`people.students.$personId.tsx`, spec §7); whether Part B (Task 17) ran or moved to B3f.
- Open PRs as Plan 15 did (`gh pr create --repo Etqan-agency/etqan_tutor_backend`, `…_dashboard`, then meta with `--repo Etqan-agency/etqan_tutor`); bump submodule pointers in meta only after both merge, with explicit paths (never `git commit -a`, never `git submodule`).

---
### Task 17 (Part B, conditional on R3): Compensation for a session as balance

**This task runs only if request R3 has landed.** It is the slice's last task (spec §7). If R3 is not merged when Tasks 1–16 have passed review, skip this task entirely: B3e merges with no B2 change, the migration already holds the `compensation` kind and its constraint, and compensation moves to B3f (note it in the PRs and the report). Compensation is never built without R3: an unmarked credit would let a make-up and a credit both pay for one session.

**Files (only if Step 1 says go):**
- Create: `backend/etqan/wallet/services/compensation.py`, `backend/etqan/wallet/tests/test_compensation.py`, `dashboard/src/features/wallet/SessionWalletCard.tsx`, `dashboard/src/features/wallet/SessionWalletCard.test.tsx`
- Modify: `backend/etqan/wallet/services/__init__.py`, `backend/etqan/wallet/api/{serializers,payloads,views,urls}.py`, `backend/etqan/access/tests/test_routes.py`, `dashboard/src/features/wallet/{schemas,api,queries,index}.ts`, `dashboard/src/locales/{en,ar}/wallet.json`, `dashboard/e2e/b3-wallet.spec.ts`; and, only if R3's dashboard line is not yet there, `dashboard/src/routes/_authed/scheduling.sessions.$sessionId.tsx` under a ledger claim (B2's file).

**Interfaces:**
- Consumes: R3's `scheduling.services.claim_session_for_balance(session_id: int) -> Session` (locks subscription, then session; marks `compensated`; refuses with `ValidationError(field="session")`, `scheduling.archived`, `scheduling.already_compensated`, `scheduling.not_compensable`); `scheduling.services.sessions_queryset()`, `is_compensable(session)`.
- Produces:
  - `compensation_for(session_id) -> dict` (`{session_id, compensable, currency, default_amount_minor, entry}`; `NotFoundError` for an unknown session), `compensate(session_id, *, amount_minor, by, reason="") -> WalletEntry`, exported;
  - `GET /api/v1/wallet/compensations/?session=` → `{session_id, compensable, currency, default_amount_minor, entry: <office entry> | null}`; `POST /api/v1/wallet/compensations/` `{session, amount_minor, reason?}` → 201 entry; both `wallet.create` and `balances`; POST refuses impersonation (403);
  - `<SessionWalletCard sessionId />` (`wallet.create`, `balances`; regardless of `compensation_sessions`), exported from `@/features/wallet`.

- [ ] **Step 1: Check that R3 has landed (go / no-go)**

```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/b3
python3 scripts/orchestration/ledger.py show | grep -E '^\| R3 \|'
git -C backend grep -n "def claim_session_for_balance" -- etqan/scheduling/services
git -C backend grep -n "claim_session_for_balance" -- etqan/scheduling/services/__init__.py
```

Go only if the ledger row's status is `done` **and** both greps find the function (defined and exported) on `feat/b3e-wallet`. Otherwise stop here, skip the rest of this task, and report "Part B (compensation) moves to B3f: R3 has not landed".

- [ ] **Step 2: Write the failing backend tests**

`backend/etqan/access/tests/test_routes.py`: after the B3e `ROUTES` rows add

```python
    # B3e Part B (E-23, on R3).
    ("GET", "/api/v1/wallet/compensations/", "wallet.create"),
    ("POST", "/api/v1/wallet/compensations/", "wallet.create"),
```

and add both `("GET", "/api/v1/wallet/compensations/")` and `("POST", "/api/v1/wallet/compensations/")` to the B3e `FEATURES` block (`balances`).

Create `backend/etqan/wallet/tests/test_compensation.py`:

```python
"""B3e E-23 (Part B, on R3): a session the student did not get, credited
to their balance instead of a make-up; one or the other, never both."""

import re
import time
from datetime import time as clock_time

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import IMPERSONATOR_KEY
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.tests.conftest import subscription_for
from etqan.wallet import services
from etqan.wallet.tests.conftest import as_user

pytestmark = pytest.mark.django_db
URL = "/api/v1/wallet/compensations/"


@pytest.fixture
def subscription(world):
    """Monthly: 150000 EGP for 8 sessions, from Monday 1 June 2026."""
    return subscription_for(world)


def scheduled(subscription, index=0):
    return Session.objects.filter(subscription=subscription, status="scheduled").order_by(
        "occurs_on", "id"
    )[index]


def cancel(subscription, admin, index=0):
    return scheduling_services.cancel_session(
        scheduled(subscription, index), by=admin, reason="Teacher ill"
    )


def code(caught) -> str:
    return caught.value.code


def test_the_prefill_the_claim_and_the_credit(wallet_on, world, admin, subscription):
    session = cancel(subscription, admin)
    info = services.compensation_for(session.pk)
    assert (
        info["compensable"],
        info["currency"],
        info["default_amount_minor"],
        info["entry"],
    ) == (True, "EGP", 150000 // 8, None)
    entry = services.compensate(session.pk, amount_minor=18750, by=admin, reason="Sorry")
    assert (entry.kind, entry.amount_minor, entry.session_id) == (
        "compensation",
        18750,
        session.pk,
    )
    assert entry.note == f"{session.occurs_on.isoformat()} · Tajweed · Sorry"
    assert Session.objects.get(pk=session.pk).compensated is True
    after = services.compensation_for(session.pk)
    assert (after["compensable"], after["entry"].pk) == (False, entry.pk)
    assert services.balances_of(world.student.id) == [services.Balance("EGP", 18750)]


def test_a_balance_and_a_make_up_exclude_each_other(wallet_on, admin, subscription):
    credited = cancel(subscription, admin)
    services.compensate(credited.pk, amount_minor=100, by=admin)
    with pytest.raises(ConflictError) as again:
        services.compensate(credited.pk, amount_minor=100, by=admin)
    assert code(again) == "scheduling.already_compensated"
    with pytest.raises(ConflictError) as make_up:
        scheduling_services.create_compensation(
            by=admin,
            compensates_id=credited.pk,
            occurs_on=credited.occurs_on,
            start_time=clock_time(6, 0),
        )
    assert code(make_up) == "scheduling.already_compensated"
    made_up = cancel(subscription, admin)
    scheduling_services.create_compensation(
        by=admin,
        compensates_id=made_up.pk,
        occurs_on=made_up.occurs_on,
        start_time=clock_time(6, 0),
    )
    with pytest.raises(ConflictError) as after_make_up:
        services.compensate(made_up.pk, amount_minor=100, by=admin)
    assert code(after_make_up) == "scheduling.already_compensated"
    assert services.compensation_for(made_up.pk)["compensable"] is False


def test_what_cannot_be_compensated(wallet_on, set_features, admin, subscription):
    with pytest.raises(ConflictError) as still_scheduled:
        services.compensate(scheduled(subscription).pk, amount_minor=100, by=admin)
    assert code(still_scheduled) == "scheduling.not_compensable"
    original = cancel(subscription, admin)
    make_up = scheduling_services.create_compensation(
        by=admin,
        compensates_id=original.pk,
        occurs_on=original.occurs_on,
        start_time=clock_time(6, 0),
    ).session
    scheduling_services.cancel_session(make_up, by=admin, reason="Again")
    with pytest.raises(ConflictError) as compensation_kind:
        services.compensate(make_up.pk, amount_minor=100, by=admin)
    assert code(compensation_kind) == "scheduling.not_compensable"
    assert services.compensation_for(make_up.pk)["compensable"] is False
    archived = cancel(subscription, admin)
    set_features(subscription_archive=True)
    Subscription.objects.filter(pk=subscription.pk).update(archived_at=timezone.now())
    assert services.compensation_for(archived.pk)["compensable"] is False
    with pytest.raises(ConflictError) as on_archive:
        services.compensate(archived.pk, amount_minor=100, by=admin)
    assert code(on_archive) == "scheduling.archived"
    with pytest.raises(NotFoundError):
        services.compensation_for(999999)
    with pytest.raises(ValidationError) as missing:
        services.compensate(999999, amount_minor=100, by=admin)
    assert missing.value.field == "session"
    for bad in (0, -1, 100_000_001, "5"):
        with pytest.raises(ValidationError) as amount:
            services.compensate(archived.pk, amount_minor=bad, by=admin)
        assert amount.value.field == "amount_minor"


def test_the_claim_locks_subscription_then_session_then_wallet(
    wallet_on, admin, subscription
):
    session = cancel(subscription, admin)
    with CaptureQueriesContext(connection) as ctx:
        services.compensate(session.pk, amount_minor=100, by=admin)
    tables = [
        re.search(r'FROM "(\w+)"', q["sql"]).group(1)
        for q in ctx.captured_queries
        if "FOR UPDATE" in q["sql"]
    ]
    assert tables == ["scheduling_subscription", "scheduling_session", "wallet_wallet"]


def test_the_route(api_for, staff_for, set_features, wallet_on, admin, subscription):
    session = cancel(subscription, admin)
    office = api_for("admin")
    read = office.get(URL, {"session": session.pk}).json()
    assert read == {
        "session_id": session.pk,
        "compensable": True,
        "currency": "EGP",
        "default_amount_minor": 18750,
        "entry": None,
    }
    assert office.get(URL).status_code == 400
    assert office.get(URL, {"session": 999999}).status_code == 404
    assert staff_for("wallet.update").get(URL, {"session": session.pk}).status_code == 403
    body = {"session": session.pk, "amount_minor": 18750}
    set_features(quick_login=True)
    impersonated = api_for("admin")
    marked = impersonated.session
    marked[IMPERSONATOR_KEY] = {
        "id": admin.pk,
        "hash": admin.get_session_auth_hash(),
        "since": time.time(),
    }
    marked.save()
    assert impersonated.get(URL, {"session": session.pk}).status_code == 200
    refused = impersonated.post(URL, body, format="json")
    assert (refused.status_code, refused.json()["code"]) == (403, "identity.impersonating")
    resp = staff_for("wallet.create").post(URL, body, format="json")
    assert (resp.status_code, resp.json()["kind"]) == (201, "compensation")
    assert office.get(URL, {"session": session.pk}).json()["entry"]["id"] == resp.json()["id"]
    assert as_user(admin).post(URL, {**body, "amount_minor": "x"}, format="json").status_code == 400
```

Run: `$DJ pytest etqan/wallet/tests/test_compensation.py etqan/access -q`
Expected: FAIL (the services and the route do not exist).

- [ ] **Step 3: Implement the backend**

Create `backend/etqan/wallet/services/compensation.py`:

```python
"""Part B (B3e E-23, on R3): a session the student did not get, credited to
their balance. Scheduling decides and marks the session under its own locks
(`claim_session_for_balance`: subscription, then session); the wallet is
locked after them (the compensation chain, E-6). It cannot be undone; the
money is corrected by an adjustment."""

from django.db import transaction

from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services
from etqan.wallet.models import WalletEntry
from etqan.wallet.services.ledger import check_amount
from etqan.wallet.services.ledger import lock_wallet
from etqan.wallet.services.ledger import write

REASON_LENGTH = 300  # the note keeps its date and course (500 in all)


def compensation_for(session_id: int) -> dict:
    """The session card's facts. `compensable` also needs a live (not
    archived) subscription and a non-`compensation` session (plan W23)."""
    session = scheduling_services.sessions_queryset().filter(pk=session_id).first()
    if session is None:
        raise NotFoundError("Session", session_id)
    subscription = session.subscription
    entry = (
        WalletEntry.objects.select_related("wallet", "created_by")
        .filter(kind=WalletEntry.Kind.COMPENSATION, session_id=session_id)
        .first()
    )
    compensable = (
        subscription is not None
        and session.kind != "compensation"
        and subscription.archived_at is None
        and entry is None
        and scheduling_services.is_compensable(session)
    )
    default = (
        subscription.price_minor // subscription.sessions_total
        if subscription is not None and subscription.sessions_total
        else 0
    )
    return {
        "session_id": session.pk,
        "compensable": compensable,
        "currency": subscription.currency if subscription is not None else None,
        "default_amount_minor": default,
        "entry": entry,
    }


@transaction.atomic
def compensate(
    session_id: int, *, amount_minor: int, by, reason: str = ""
) -> WalletEntry:
    check_amount(amount_minor)
    text = (reason or "").strip()
    if len(text) > REASON_LENGTH:
        raise ValidationError(
            f"Keep the reason under {REASON_LENGTH} characters.", field="reason"
        )
    session = scheduling_services.claim_session_for_balance(session_id)
    subscription = session.subscription
    wallet = lock_wallet(session.student_id, subscription.currency, create=True)
    note = f"{session.occurs_on.isoformat()} · {session.course.name_en}"
    return write(
        wallet,
        kind=WalletEntry.Kind.COMPENSATION,
        amount_minor=amount_minor,
        by=by,
        note=f"{note} · {text}" if text else note,
        session_id=session.pk,
    )
```

`backend/etqan/wallet/services/__init__.py`: add `from etqan.wallet.services.compensation import compensate` and `… import compensation_for`, and both names to `__all__`.

`backend/etqan/wallet/api/serializers.py`, append:

```python
class CompensationQueryInput(serializers.Serializer):
    session = serializers.IntegerField(min_value=1)


class CompensationInput(serializers.Serializer):
    session = serializers.IntegerField(min_value=1)
    amount_minor = _amount(min_value=1)
    reason = serializers.CharField(max_length=300, required=False, allow_blank=True)
```

`backend/etqan/wallet/api/payloads.py`, append:

```python
def compensation(info: dict) -> dict:
    entry = info["entry"]
    return {
        **{k: info[k] for k in ("session_id", "compensable", "currency")},
        "default_amount_minor": info["default_amount_minor"],
        "entry": None if entry is None else entry_row(entry, office=True),
    }
```

`backend/etqan/wallet/api/views.py`: add the imports `from etqan.platform.permissions import IMPERSONATING`, `from etqan.platform.permissions import impersonator_id`, `CompensationInput`, `CompensationQueryInput`, and append:

```python
class CompensationsView(APIView):
    """Part B (E-23): `wallet.create`; regardless of `compensation_sessions`.
    Reading stays open while impersonating; crediting does not (D19)."""

    permission_classes = [HasCode, FeatureOn]
    feature = FEATURE
    permission_codes = {"GET": "wallet.create", "POST": "wallet.create"}

    def get(self, request):
        query = CompensationQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        info = services.compensation_for(query.validated_data["session"])
        return Response(payloads.compensation(info))

    def post(self, request):
        if impersonator_id(request) is not None:
            raise PermissionDenied(IMPERSONATING)
        body = CompensationInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        return _created(
            services.compensate(
                data["session"],
                amount_minor=data["amount_minor"],
                by=request.user,
                reason=data.get("reason", ""),
            )
        )
```

`backend/etqan/wallet/api/urls.py`, add `path("compensations/", views.CompensationsView.as_view(), name="compensations"),`.

Run: `$DJ pytest etqan/wallet etqan/access etqan/scheduling -q`
Expected: PASS (every existing scheduling test unchanged).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`
Expected: clean ("scheduling never imports wallet" holds: the wallet calls scheduling).

```bash
git -C backend add etqan/wallet etqan/access/tests/test_routes.py
git -C backend commit -m "feat(wallet): compensate a session as balance through R3's claim (B3e Part B)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: Write the failing dashboard test**

Create `dashboard/src/features/wallet/SessionWalletCard.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import type { Me } from "@/features/identity/schemas";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings } from "@/test/scheduling-fixtures";
import { walletEntry } from "@/test/wallet-fixtures";
import { walletApi } from "./api";
import { SessionWalletCard } from "./SessionWalletCard";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		walletApi: {
			...actual.walletApi,
			compensation: vi.fn(),
			compensate: vi.fn(),
		},
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const OPEN = {
	session_id: 7,
	compensable: true,
	currency: "EGP",
	default_amount_minor: 18750,
	entry: null,
};

function renderCard(me: Me = adminWith("balances")) {
	return renderWithRouter(
		<CanProvider me={me}>
			<SessionWalletCard sessionId="7" />
		</CanProvider>,
	);
}

describe("SessionWalletCard (Part B)", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(walletApi.compensation).mockResolvedValue(OPEN);
		vi.mocked(walletApi.compensate).mockResolvedValue(
			walletEntry({ kind: "compensation", amount_minor: 18750 }),
		);
	});

	it("offers the prefilled compensation and credits it", async () => {
		const user = userEvent.setup();
		renderCard();
		await user.click(
			await screen.findByRole("button", { name: "Compensate as balance" }),
		);
		const dialog = await screen.findByRole("dialog");
		const amount = within(dialog).getByLabelText(/^Amount/);
		await waitFor(() => expect(amount).toHaveValue("187.50"));
		await user.type(within(dialog).getByLabelText(/^Reason/), "Teacher ill");
		await user.click(within(dialog).getByRole("button", { name: "Add to balance" }));
		await waitFor(() =>
			expect(walletApi.compensate).toHaveBeenCalledWith({
				session: 7,
				amount_minor: 18750,
				reason: "Teacher ill",
			}),
		);
	});

	it("says when the session was compensated", async () => {
		vi.mocked(walletApi.compensation).mockResolvedValue({
			...OPEN,
			compensable: false,
			entry: walletEntry({ kind: "compensation", amount_minor: 18750 }),
		});
		renderCard();
		expect(
			await screen.findByText("Compensated with EGP 187.50 on Jun 1, 2026."),
		).toBeVisible();
	});

	it("shows nothing when not compensable, without the code or the feature", async () => {
		vi.mocked(walletApi.compensation).mockResolvedValue({
			...OPEN,
			compensable: false,
		});
		const { unmount } = renderCard();
		await waitFor(() => expect(walletApi.compensation).toHaveBeenCalled());
		expect(screen.queryByRole("button")).toBeNull();
		unmount();
		vi.mocked(walletApi.compensation).mockClear();
		renderCard({ ...staffMe("wallet.update"), features: ["balances"] });
		renderCard(adminWith());
		await act(async () => {});
		expect(walletApi.compensation).not.toHaveBeenCalled();
	});
});
```

Run: `$DASH pnpm vitest run src/features/wallet/SessionWalletCard.test.tsx`
Expected: FAIL.

- [ ] **Step 5: Implement the dashboard card and wire it**

`dashboard/src/features/wallet/schemas.ts`, append:

```ts
/** Part B (E-23): a session's compensation facts. */
export interface Compensation {
	session_id: number;
	compensable: boolean;
	currency: string | null;
	default_amount_minor: number;
	entry: WalletEntry | null;
}
export interface CompensateBody {
	session: number;
	amount_minor: number;
	reason: string;
}
export const compensateFormSchema = (currency: string) =>
	z
		.object({
			amount: z.string(),
			reason: z.string().max(300, "wallet.errors.reasonShort"),
		})
		.superRefine((data, ctx) =>
			refineAmount(data.amount, currency, false, (message) =>
				ctx.addIssue({ code: "custom", path: ["amount"], message }),
			),
		);
export type CompensateFormValues = z.infer<ReturnType<typeof compensateFormSchema>>;
```

`dashboard/src/features/wallet/api.ts`, add (types `Compensation`, `CompensateBody` imported):

```ts
	compensation: async (sessionId: number) =>
		(
			await api.get<Compensation>(`${W}compensations/`, {
				params: { session: String(sessionId) },
			})
		).data,
	compensate: async (body: CompensateBody) =>
		(await api.post<WalletEntry>(`${W}compensations/`, body)).data,
```

`dashboard/src/features/wallet/queries.ts`, append:

```ts
export function useCompensation(sessionId: number, enabled: boolean) {
	return useQuery({
		queryKey: [...walletKey, "compensation", sessionId],
		queryFn: () => walletApi.compensation(sessionId),
		enabled,
		retry: false,
	});
}
```

Create `dashboard/src/features/wallet/SessionWalletCard.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { saveOrShowErrors, useFillOnOpen } from "@/features/finance/shared";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { useFieldError } from "@/lib/field-error";
import { formatMoney, toMajor, toMinor } from "@/lib/money";
import { dayIn } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Input,
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { walletApi } from "./api";
import { useCompensation, useWalletMutation } from "./queries";
import {
	type CompensateFormValues,
	type Compensation,
	compensateFormSchema,
} from "./schemas";

function CompensateDialog({ info }: { info: Compensation & { currency: string } }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const save = useWalletMutation(walletApi.compensate);
	const initial = useCallback(
		(): CompensateFormValues => ({
			amount: toMajor(info.default_amount_minor, info.currency),
			reason: "",
		}),
		[info.default_amount_minor, info.currency],
	);
	const {
		register,
		handleSubmit,
		setError,
		setFocus,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<CompensateFormValues>({
		resolver: zodResolver(compensateFormSchema(info.currency)),
		defaultValues: initial(),
	});
	useFillOnOpen({ open, ready: true, reset, setFocus, initial, first: "amount" });

	async function onSubmit(values: CompensateFormValues) {
		const saved = await saveOrShowErrors(
			() =>
				save.mutateAsync({
					session: info.session_id,
					amount_minor: toMinor(values.amount.trim(), info.currency),
					reason: values.reason.trim(),
				}),
			setError,
		);
		if (saved) {
			setOpen(false);
			toast({ description: t("wallet.compensation.saved"), variant: "success" });
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm">{t("wallet.compensation.action")}</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("wallet.compensation.title")}</DialogTitle>
				<DialogDescription>{t("wallet.compensation.body")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id="wallet-compensation-amount"
						label={t("wallet.compensation.amount", { currency: info.currency })}
						error={fieldError(errors.amount?.message)}
						required
					>
						<Input inputMode="decimal" dir="ltr" {...register("amount")} />
					</Field>
					<Field
						id="wallet-compensation-reason"
						label={t("wallet.compensation.reason")}
						error={fieldError(errors.reason?.message)}
					>
						<Textarea rows={2} {...register("reason")} />
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
							{t("wallet.compensation.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

/** Part B (E-23, R3's line on the session page): "Compensate as balance"
 * with the prefilled amount when the session is compensable; "Compensated
 * with … on …" once it was; nothing otherwise. `wallet.create` and
 * `balances`, regardless of `compensation_sessions`. */
export function SessionWalletCard({ sessionId }: { sessionId: string }) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const hasFeature = useHasFeature();
	const { data: academy } = useAcademySettings();
	const id = Number(sessionId);
	const allowed =
		hasFeature("balances") &&
		can("wallet.create") &&
		Number.isInteger(id) &&
		id > 0;
	const { data: info } = useCompensation(id, allowed);
	if (!allowed || !info) return null;
	const entry = info.entry;
	if (entry === null && (!info.compensable || info.currency === null)) return null;
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("wallet.compensation.title")}</CardTitle>
			</CardHeader>
			<CardContent className="pt-4">
				{entry ? (
					<p className="text-sm">
						{t("wallet.compensation.done", {
							amount: formatMoney(entry.amount_minor, entry.currency, i18n.language),
							date: academy
								? dayIn(new Date(entry.created_at), academy.timezone, i18n.language)
								: "",
						})}
					</p>
				) : (
					<CompensateDialog info={{ ...info, currency: info.currency as string }} />
				)}
			</CardContent>
		</Card>
	);
}
```

`dashboard/src/features/wallet/index.ts`: `export { SessionWalletCard } from "./SessionWalletCard";`.

`dashboard/src/locales/en/wallet.json`: add

```json
	"compensation": {
		"title": "Compensate as balance",
		"body": "Credit the student's balance for this session instead of a make-up. It cannot be undone.",
		"action": "Compensate as balance",
		"amount": "Amount ({{currency}})",
		"reason": "Reason (optional)",
		"save": "Add to balance",
		"saved": "Session compensated as balance.",
		"done": "Compensated with {{amount}} on {{date}}."
	},
```

and `"reasonShort": "Keep the reason under 300 characters."` in `errors`; `dashboard/src/locales/ar/wallet.json` the same keys:

```json
	"compensation": {
		"title": "التعويض بالرصيد",
		"body": "أضف قيمة هذه الحصة إلى رصيد الطالب بدلًا من حصة تعويضية. لا يمكن التراجع عن ذلك.",
		"action": "التعويض بالرصيد",
		"amount": "المبلغ ({{currency}})",
		"reason": "السبب (اختياري)",
		"save": "إضافة إلى الرصيد",
		"saved": "عُوّضت الحصة بالرصيد.",
		"done": "عُوّضت بمبلغ {{amount}} في {{date}}."
	},
```

and `"reasonShort": "اجعل السبب أقل من 300 حرف."` in `errors`.

The session page line (R3's DASHBOARD part): if `git -C dashboard grep -n SessionWalletCard -- 'src/routes/_authed/scheduling.sessions.$sessionId.tsx'` finds nothing, claim the file first (`python3 scripts/orchestration/ledger.py claim --reason "B3e Part B: R3's SessionWalletCard line (spec §7)" B3 'dashboard/src/routes/_authed/scheduling.sessions.$sessionId.tsx'`), add `import { SessionWalletCard } from "@/features/wallet";` and, after `<SessionPage sessionId={sessionId} />`:

```tsx
					<div className="mt-6">
						<SessionWalletCard sessionId={sessionId} />
					</div>
```

then release it after the commit (`python3 scripts/orchestration/ledger.py release B3 'dashboard/src/routes/_authed/scheduling.sessions.$sessionId.tsx'`).

Run: `$DASH pnpm vitest run src/features/wallet src/locales src/routes`
Expected: PASS.
Run: `just test-frontend && just lint-frontend`

```bash
git -C dashboard add src/features/wallet src/locales 'src/routes/_authed/scheduling.sessions.$sessionId.tsx'
git -C dashboard commit -m "feat(wallet): the session page's compensate-as-balance card (B3e Part B)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: The e2e's step 7**

In `dashboard/e2e/b3-wallet.spec.ts`, append at the end of the test body (after `await guardian.context().close();`):

```ts
	// 7 (Part B, R3): the admin subscribes the child, cancels a session and
	// compensates it as balance; the child's statement lists it.
	const inDays = (days: number) =>
		new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
	const weekday = (day: string) =>
		new Intl.DateTimeFormat("en", { weekday: "short", timeZone: "UTC" }).format(
			new Date(`${day}T00:00:00Z`),
		);
	await page.goto(`${DEMO_URL}/app/scheduling/subscriptions/new`);
	await page.getByLabel("Find a student").fill(child);
	await page.getByLabel(/^Student/).selectOption({ label: child });
	await page.getByLabel(/^Course/).selectOption({ label: "Tajweed" });
	await page.getByLabel(/^Teacher/).selectOption({ label: "Ustadh Bilal" });
	await page.getByLabel(/^Package/).selectOption({ label: "Monthly, 2 a week" });
	await page.getByLabel(weekday(inDays(1)), { exact: true }).click();
	await page.getByLabel(weekday(inDays(3)), { exact: true }).click();
	await page.getByLabel(/^Start time/).fill("10:00");
	await page.getByRole("button", { name: "Create subscription" }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/subscriptions\/\d+$/);
	await page.goto(`${DEMO_URL}/app/scheduling/sessions`);
	await page.getByLabel("Period").selectOption("upcoming");
	await page.getByRole("combobox", { name: "Status" }).selectOption("scheduled");
	await page.getByRole("searchbox").fill(child);
	await page
		.getByRole("row", { name: new RegExp(child) })
		.first()
		.getByRole("link", { name: child, exact: true })
		.click();
	await expect(page).toHaveURL(/\/app\/scheduling\/sessions\/\d+$/);
	await page.getByRole("button", { name: "Cancel session" }).click();
	const cancel = page.getByRole("dialog");
	await cancel.getByLabel(/^Reason/).fill("E2E: teacher ill");
	await cancel.getByRole("button", { name: "Cancel session" }).click();
	await page.getByRole("button", { name: "Compensate as balance" }).click();
	const compensate = page.getByRole("dialog");
	await expect(compensate.getByLabel(/^Amount/)).toHaveValue("187.50");
	await compensate.getByRole("button", { name: "Add to balance" }).click();
	await expect(page.getByText(/^Compensated with EGP\s187\.50 on /)).toBeVisible();
	await page.goto(childUrl);
	await page.getByRole("tab", { name: "EGP" }).click();
	await expect(page.getByRole("tabpanel").getByText("Compensation")).toBeVisible();
```

(The seeded "Monthly, 2 a week" costs EGP 1500.00 for 8 sessions: the prefill is 187.50. A compensation is never revenue, so `b3-finance.spec.ts`'s EGP deltas are untouched.)

Run: `just e2e e2e/b3-wallet.spec.ts` twice.
Expected: PASS both times.

```bash
git -C dashboard add e2e/b3-wallet.spec.ts
git -C dashboard commit -m "test(e2e): compensate a cancelled session as balance (B3e Part B)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
## Self-review against the spec

- **E-1** (new app, own contracts, services only, no app imports wallet): Task 1 (app, `TENANT_APPS`, the four contracts, gateways' two lists), Tasks 5–8 (services only), Task 16 (`lint-imports`). **E-2** (one wallet per student and currency, created on its first entry; no conversion): Task 1 constraint, Task 5 (`lock_wallet`, plan W8), Task 6 (another-currency invoice refused). **E-3** (append-only, signed amounts, running balance, cache, CHECKs, no edit route): Task 1 tests, `ledger_holds` in Tasks 5–7, Task 8 (`test_no_route_edits_or_deletes_an_entry`). **E-4** (kinds, reason 1–500): Tasks 1 and 5. **E-5** (an adjustment is a correction, never revenue; the dialog's note): Task 6 revenue test, Task 12 dialog. **E-6** (locks, fresh balance, two chains): Task 6 (captured SQL, stale balance), Task 7 (checkout → top-up → wallet), Task 17 (subscription → session → wallet), billing's own in Task 3. **E-7** (revenue): Task 2 (query) and Task 6 (end to end), Task 7 (a top-up's fee). **E-8** (billing's method, status, field, checks; stamps; MANUAL unchanged): Tasks 2 and 4. **E-9** (guards on the fresh locked row; `add_payment`/`create_record` refuse `wallet`): Task 3, Task 6 (C1 with the wallet). **E-10** (flags, `completedPayments`, the pages and print): Tasks 4 and 10. **E-11** (default amount, two over-balance answers, void, nothing due, today, partial): Task 6, Task 13. **E-12** (move any completed invoice payment; fee stays; standalone refused): Task 6. **E-13** (reverse needs the balance; refunded; from the statement): Task 6, Task 11 (Reverse on `topup` entries). **E-14** (manual top-up: method, date, reference; no `active_student`): Tasks 3 and 5. **E-15** (private purpose, TopUp row, `prepare`'s refusals, `use_switch`, paid row 409): Task 7. **E-16** (complete: lock, mismatch attention, every paid checkout credited, `already_recorded`, balances off): Task 7. **E-17** (student, parent; payer-only excluded; 404): Tasks 6–8, 13. **E-18** (currencies; no provider message): Task 7, Task 8 (options), Task 14 (dialog). **E-19** (1..100,000,000): Tasks 1, 5, 8, 11. **E-20** (resource and verbs; `invoice.view` through `invoice_for`; `payment.update` in the view; `NotImpersonating`): Task 8 (plan W14). **E-21** (`balances` in place, default off, requires nothing; 404s; completion while off): Tasks 1, 7, 8. **E-22** (family view): Task 8 (API), Tasks 11 and 14 (pages). **E-23** (compensation, Part B, R3): Task 17, conditional. **E-24** (nothing sent; `balances_of`): no notification code anywhere; `balances_of` in Task 5. **E-25** (en and ar): every locale block, real Arabic.
- **§3 data:** Task 1 (wallet), Task 2 (billing). **§4.1 billing services:** Tasks 2–4. **§4.2 wallet services:** Tasks 5–7, 17. **§4.3 the purpose:** Task 7. **§5 API:** Task 8 (and 17). **§6 dashboard:** Tasks 10–14 (and 17). **§7 wiring:** Tasks 1, 8, 9, 14; R3 in Task 17. **§8 seeds:** Task 9. **§9 tests:** each backend and dashboard bullet maps to a test above; the e2e is Task 15 (step 7 in Task 17). **§10 out of scope:** nothing built for cash-back of a moved payment, an office balances list, transfers, automatic payment, undoing a compensation, notifications, XP or gateway refund APIs.

**Spec gaps and contradictions found (spec not edited):**
1. E-6 / §9 say `pay_invoice` locks "wallet, then invoice, then payment"; paying inserts the payment and locks no payment row. The plan asserts `wallet → invoice` for pay and `wallet → invoice → payment` for move (plan W10).
2. E-9's re-read in `delete_payment` adds a second `FOR UPDATE`; billing's existing `test_every_write_locks_the_invoice_row_first` asserts exactly one for delete, so its assertion changes for delete only (plan W18).
3. Spec §8 seeds EGP 300.00 as Aisha's top-up: it is revenue (E-7), so `test_seed_dev`'s demo EGP revenue rises to 230000, and `test_seed_links` (which reads every standalone record) now sees the top-up unless it leaves `wallet_topup` records out (plan W19).
4. The user's ordering put "resource `wallet`" with the app; the route matrix test requires each in-use code to be declared by a route, so the resource lands with the routes (Task 8, plan W3).
5. §5 lists `mine/`, `top-ups/options/` and `top-ups/` with no office code; the route table has no row shape for family-only routes, so they are `SELF_SERVICE` like `StartCheckoutView` (plan W14), and their feature 404s are tested in `test_api.py`.
6. E-20 says moving "needs `payment.update` … checked in the view"; checked before the lookup it would turn the matrix's "with the code: not 403" into a 403 for `wallet.update` alone. It is checked after the payment lookup (plan W14).
7. §5's entry shape has no way to tell a reversed top-up; the plan adds `reversed` (plan W13) so Reverse hides.
8. E-8 asks `wallet_topup` with `db_default=False`; with `db_default` alone a new instance reads a truthy `DatabaseDefault` until refreshed, so the field also has `default=False` (plan W5).
9. §4.1's `credit_payment` and `refund_topup_payment` name no code for a standalone payment or a non-top-up; the wallet refuses those first, and billing's own refusals are W7's.
10. E-23 marks `compensable` false for an archived subscription without saying "only while the archive feature is on" (R3's refusal is); the card follows the spec (stricter, plan W23).
11. The spec's `seed_wallet` runs "only when the academy has no wallet entry", which needs a read the spec does not list: `has_entries()` (Task 9).
