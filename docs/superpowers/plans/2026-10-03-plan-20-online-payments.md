# Plan 20 — Slice B3b: Online payments (gateway core and Stripe) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Slice:** B3b
**Requires:** — (no other phase's slice; B3a merged first)

**Goal:** An academy connects its own Stripe account. A family pays an unpaid invoice's balance online,
plus a service fee. A verified Stripe event records the payment on the invoice. Admins see every online
checkout, resolve the ones that need attention, and mark payments refunded.

**Architecture:**
- **Backend:**
  - A new tenant app, `etqan.gateways` (B-1), owns `GatewayAccount`, `GatewaySettings`, `Checkout` and
    `WebhookEvent`. Its services are split by job:
    - `services/accounts.py`: settings, keys, encryption;
    - `services/fees.py`: the fee and currency rules;
    - `services/purposes.py`: the purpose registry and its dataclasses;
    - `services/checkouts.py`: `start_checkout`, reuse and supersede, reads, resolve and expiry;
    - `services/webhooks.py`: verifying and processing Stripe events;
    - `services/simulator.py`: signed fake events.
  - Providers sit behind one small interface in `gateways/providers/`: `stripe.py` (httpx) and
    `simulator.py`. Gateways imports no business app.
  - Billing registers the `invoice` purpose in `BillingConfig.ready()` through `gateways.services`. It
    also gains the payment status, fee and transaction number; completed-only sums; refunds; and a
    refusal to delete an online payment.
  - Two platform additions, both business-free: `etqan.platform.currency` (minor digits) and
    `etqan.platform.secrets` (Fernet under `ETQAN_SECRETS_KEY`), plus an `UnavailableError` mapped to 503.
- **Dashboard:**
  - a `features/gateways` module with the settings page, Pay online, the return page, the simulator page
    and the checkouts list;
  - billing's invoice page gains Pay online, payment fee, status and transaction number, and Mark
    refunded.
- **Off by default:** `online_payments` ships off and requires `invoices`. The seeded demo academy turns it
  on through `seed_dev.FEATURES = BUILT`, and gets a Stripe test account with placeholder keys, so the
  simulator works out of the box.

**Tech Stack:**
- backend: Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18, Celery beat, `httpx` (new),
  `cryptography` (Fernet, made explicit), `respx` (new, tests);
- dashboard: React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next,
  `Intl` for money;
- e2e: Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-03-b3b-online-payments-design.md`, slice B3b of
`docs/superpowers/specs/2026-10-03-b3-money-depth-design.md`. It builds on:
- Plan 6 billing (`2026-09-25-billing-design.md`);
- Plan 12a roles;
- Plan 13 feature switches;
- B3a (`2026-10-03-b3a-expenses-donations-design.md`, Plan 15).

Where this plan fills a gap in the spec, or departs from it because of the code, the Decisions below say
so.

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), and the meta repo (trunk `master`).
  `marketing/` is not touched.
- **Branch `feat/b3b-online-payments`.** The orchestrator creates it before Task 1, once B3a has merged:
  in the meta worktree and in `backend/` and `dashboard/`, `git fetch origin` then
  `git switch -c feat/b3b-online-payments` off `origin/master` (meta) or `origin/main` (submodules).
  Check `git -C backend branch --show-current` and `git -C dashboard branch --show-current` before Task 1
  and before Task 10.
- **Never run `git submodule update`, `add`, `sync` or any other `git submodule` command that writes.**
  This worktree's submodules are worktrees of the main checkout's.
- **Never use bare `git stash`.**
- **Commits:** Conventional Commits, ending with the `Co-Authored-By:` line of the implementer's own
  session attribution. Commit in the repo the change lives in (`git -C backend …`, `git -C dashboard …`),
  never with `cd`, and never the submodule pointers in meta.

**Shared lists:** add lines only **below** the existing `── phase B3 ──` marker line. Never paste a second
marker line. A snippet below that starts with the marker line means "insert after the existing marker".
The lists are:
- `TENANT_APPS` (`backend/config/settings/base.py`), already holding `"etqan.finance"`;
- `config/api_router.py`;
- the feature registry (`etqan/platform/features.py`);
- the access `RESOURCES` (`etqan/access/registry.py`);
- `seed_academy` (`etqan/tenants/management/commands/seed_dev.py`), with its data in
  `etqan/tenants/seeds/gateways.py`;
- `backend/pyproject.toml`, in both the platform contract's forbidden list and the B3 contracts block,
  after "billing never imports finance";
- the dashboard's `NAV_ITEMS`;
- `platform/tests/test_features.py`'s `BUILT` dict (it has markers now).

**Lists without markers.** These change in this slice: add to them, and change existing counts or rows
only where this plan says. Expect rebase conflicts there and keep both sides.
- Backend:
  - `access/tests/test_routes.py` (`ROUTES`, `FEATURES`, `FEATURE_WORDS`, `SELF_SERVICE`);
  - `access/tests/test_registry.py` (resource count 24 → 26);
  - `platform/tests/test_features.py` (the unbuilt count stays 27);
  - billing's `Resource("payment", …)` line, whose `in_use` gains `"update"` (billing is B3's);
  - `CELERY_BEAT_SCHEDULE` and `DEFAULT_THROTTLE_RATES` (`config/settings/base.py`);
  - `requirements/base.txt` and `requirements/local.txt`.
- Dashboard:
  - `features/shell/nav.test.ts`;
  - `routes/permissions.test.ts` (`FEATURE_SCREENS`, `FEATURE_WORDS`);
  - `features/identity/schemas.ts` (`FeatureCode`);
  - `features/finance/landing.ts` (the `/billing` landing order).

New translations go in the new files `dashboard/src/locales/{en,ar}/gateways.json`. The billing keys this
slice adds go in `billing.json`, which is B3's billing area.

**Features:** `online_payments` is built with `default=False` and `requires=("invoices",)`, as a plain
`Feature(...)` (since `_built()` has no `requires`).

**Backend commands.** Run them from the meta worktree, inside this stream's stack, which must be up
(`just dev-backend`). Load the stream's ports first:
```bash
set -a && . ./.env.stream && set +a
DJ="docker compose -f docker-compose.local.yml exec -T django"
```
- Tests: `$DJ pytest etqan/gateways -q` (or any path). Add `--create-db` once after each task that adds
  migrations.
- Migrations: `$DJ python manage.py makemigrations gateways` (or `billing`).
- Format: `$DJ sh -c 'ruff check --fix . && ruff format .'`
- Verify: `$DJ sh -c 'ruff check . && ruff format --check . && lint-imports && pytest -q --cov=etqan'`
- **New dependencies:** after Task 1 adds `httpx`, `cryptography` and `respx` to the requirements, rebuild
  this stream's images before anything imports them: `just rebuild`, then `just dev-backend`.
- **Run every test command in the foreground.** Background pytest runs share the stack's test database and
  collide.
- Never run `manage.py`, `migrate` or e2e any other way. `.env.stream` is what points them at this
  stream's database.
- **Lint:**
  - Watch `PLR0913`. Keyword-only signatures that mirror an API body carry
    `# noqa: PLR0913 -- <reason>`, as billing does.
  - No U+2212 minus or other ambiguous Unicode in Python strings or comments (RUF001–003 are not
    auto-fixable). Write "minus" or `-`.
- **Facts the tests rely on:**
  - The test academy's `default_currency` is **USD**. Scheduling's `world` package is EGP.
  - `world.student` is a `User`, and its `.id` is what billing's `student_id` takes.
  - The test settings use `config.settings.test`, where `DEBUG` is False and Celery runs eager.

**Dashboard commands.** Run them from `dashboard/` through `npx pnpm@10`.
- Format: `npx pnpm@10 exec biome check --write src e2e`
- **New route files** are picked up by the TanStack Router plugin. Regenerate `src/routeTree.gen.ts` with
  `npx pnpm@10 exec vite build` before `tsc`; it is generated, so never hand-edit it.
- Verify: `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
- **`pnpm lint`** is `biome ci . && node scripts/check-colors.mjs`. Use semantic tokens only
  (`text-destructive`, `text-muted-foreground`, `text-success`, …): no hex literals and no Tailwind
  palette utilities, not even in comments.
- **Pristine test output:**
  - A test file that switches the language resets it in
    `afterEach(async () => { await act(async () => { await i18n.changeLanguage("en"); }); })`.
  - `vitest run <dir> 2>&1 | grep -c "not wrapped in act"` must print 0 for the files this slice adds.
- **Arabic tests:** when a filter `<option>` repeats a table's text, query it
  `within(screen.getByRole("table"))`.
- **Reuse instead of copying:**
  - `src/features/finance/shared.tsx` (`useListParams`, `pageCount`, `DateFilter`, `SearchBox`,
    `saveOrShowErrors`);
  - billing's `Money` and `formatMoney`;
  - `errorText`, `applyServerErrors` and `codeKey` from `@/lib/form-errors`.

**Gates before queuing:**
- `just test`, `just lint` and `just e2e`, all against this stream's stack;
- backend coverage ≥ 80 %;
- dashboard lines and statements ≥ 80, branches and functions ≥ 70.

**Money:** integer minor units plus an ISO 4217 currency, never summed across currencies. Every
user-facing string comes in Arabic and English (ledger D11: no Spanish strings in this phase).

## Decisions (gaps the spec left, or departures it needed)

| # | Decision |
|---|---|
| D1 | **Starting a checkout is `POST gateways/checkouts/start/`, not `POST gateways/checkouts/`.** The route table test (`access/tests/test_routes.py`) keys code-exempt routes by view class. A self-service POST cannot share a class with the coded GET list, so it gets its own view and URL. The spec's §5 is amended (Task 15 records it in the spec). |
| D2 | These views are `SELF_SERVICE` in the route table, each checking its caller itself: `StartCheckoutView` (the purpose scopes it), `CheckoutDetailView` (the creator, or `checkout.view_any`), `StripeWebhookView` (the signature) and `SimulateView` (the creator; development and CI only). The coded routes are the settings, the checkouts list, resolve and refund. |
| D3 | **Secrets** live in `etqan.platform.secrets`: `encrypt(text)`, `decrypt(token)` and `available()`. The key is `settings.ETQAN_SECRETS_KEY`, a Fernet key read from the environment and blank by default. When it is blank and `settings.SECRETS_KEY_FROM_SECRET_KEY` is true (true in `local.py` and `test.py`, false in base and production), the key is derived from `SECRET_KEY` (SHA-256, urlsafe base64). Otherwise `UnavailableError("secrets", code="gateways.no_key")` is raised. `UnavailableError` is a new platform exception mapped to **503** with `{detail, code}`. |
| D4 | **Currencies:** `etqan.platform.currency.MINOR_DIGITS`: 0 for BIF, CLP, DJF, GNF, ISK, JPY, KMF, KRW, PYG, RWF, UGX, VND, VUV, XAF, XOF, XPF; 3 for BHD, IQD, JOD, KWD, LYD, OMR, TND; 2 for everything else. Stripe's list, `gateways.services.fees.STRIPE_CURRENCIES`, is AED, AUD, BHD, CAD, CHF, DKK, EGP, EUR, GBP, IDR, INR, JOD, JPY, KWD, MAD, MYR, NOK, NZD, OMR, PKR, QAR, SAR, SEK, SGD, TND, TRY, USD, ZAR ([assumed], spec B-6). |
| D5 | **Fee:** `fee = (amount * bp + 5000) // 10000` when the purpose's `add_fee` is true and the setting is on, else 0. For a 3-digit Stripe currency, `amount + fee` must be a multiple of 10, so the fee rounds up to it. When no fee is charged and `amount` is not a multiple of 10, Stripe cannot take it: `providers_for` leaves Stripe out, and `start_checkout` answers 400 on `provider`. |
| D6 | **`add_fee` means "eligible for the academy's fee".** The fee is charged when `add_fee` and `fee_enabled` are both true. The invoice purpose always says `add_fee=True`. B3c's links pass their own toggle. |
| D7 | `Checkout` also stores `redirect_url` (≤ 500), so a reused pending checkout sends the family back to the same Stripe page. The spec's §3.1 lists the fields the API shows; this one is internal. |
| D8 | **Attention reasons are short codes**, translated by the dashboard (`gateways.attention.<code>`): `invoice_void`, `balance_below_amount`, `amount_mismatch`, `currency_mismatch`, `mode_mismatch`, `purpose_unknown`, `reference_missing` (the invoice is gone) and `already_recorded` (the transaction number is already on a payment). The code is stored in `Checkout.attention`. |
| D9 | **The views that call Stripe or process events are `transaction.non_atomic_requests`** (the academy DB has `ATOMIC_REQUESTS=True`): start, webhook and simulate. Each opens its own `transaction.atomic()` blocks. A pending checkout is committed before Stripe is called, and an event's row and effects commit together or not at all. |
| D10 | **`gateways.clock.now()`** is the only clock gateways reads: the 300 s signature tolerance, `completed_at` and expiry. Tests pin it. Billing's purpose dates the payment with billing's clock. |
| D11 | **Expiry** is `gateways.expire_checkouts`: daily at 03:20 UTC, through `for_each_academy`. It marks `expired` every `pending` checkout created more than 25 h ago. |
| D12 | **`can_pay_online`** is on the invoice detail payload only (not on list rows), computed by `billing.services.online.pay_options(invoice)`. It is `[]` when `online_payments` is off, the invoice is void or paid, or the balance is 0; otherwise it is `gateways.services.providers_for(currency, balance, add_fee=True)`. The dashboard shows Pay online only to families (`admin` false). |
| D13 | The webhook finds the checkout by `metadata.checkout`, then `client_reference_id`, then `provider_ref`, in this academy's schema. Each id is parsed as a UUID first; a malformed one counts as not found (200 and logged). |
| D14 | **Simulator outcomes** are `pay` (`checkout.session.completed`, `payment_status=paid`), `fail` (`checkout.session.async_payment_failed`) and `expire` (`checkout.session.expired`). A simulated checkout's `provider_ref` is `cs_sim_<hex>`; its PaymentIntent is `pi_sim_<hex>`; its event ids are `evt_sim_<hex>`. |
| D15 | **Stripe API version** pinned to `2024-06-20` in the `Stripe-Version` header. Bodies are form-encoded, as Stripe's REST API expects; auth is Basic with the secret key as the user. |
| D16 | **Dashboard routes:**
- the return page is `/_authed/pay/return` (search `checkout`); the simulator is `/_authed/pay/simulate/$checkoutId`; neither declares a feature (money may arrive after the switch goes off);
- the settings page is `/_authed/settings/gateways` and the list is `/_authed/billing/checkouts`, both feature `online_payments`;
- the `/billing` landing order becomes invoices, expenses, donations, checkouts. |
| D17 | The **e2e** creates its unpaid invoice through the API as the admin, with the `csrftoken` cookie sent back as `X-CSRFToken`, as axios does. The parent and student are made through the UI, as `billing.spec.ts` does, and the parent signs in through the emailed invite (`acceptInvite`). |
| D18 | **Field problems are 400s on their fields, not codes.** The spec's `gateways.incomplete` is a 400 on `enabled`; `gateways.mode_mismatch` is a 400 on `mode`, `public_key` or `secret`; `gateways.amount_too_small` is a 400 on `amount_minor`. A provider failure is the platform's `ExternalServiceError` (502, generic message). Codes stay for 409 (`gateways.nothing_due`, `gateways.nothing_to_resolve`, `billing.already_refunded`, `billing.online_payment`) and 503 (`gateways.no_key`, `gateways.bad_key`). |
| D19 | **The checkouts list's date filters are UTC days.** Gateways imports no business app, so it cannot read the academy's timezone. |

## Review Focus

Inputs the spec implies but names no test for. Each one has a test in the task named.

1. **The Stripe event arrives before the start request has stored the session id.** It is found by
   `metadata.checkout` and completes the checkout. The start request's late write of `provider_ref` must
   then not move the checkout back to `pending`, nor overwrite `completed`. Tested in Task 7.
2. **The same invoice paid twice from two tabs.** Two pending checkouts are both paid. The second
   completes with `applied=false`, `balance_below_amount`, and no second payment is added. Tested in
   Task 7.
3. **A refund on an invoice that has since been edited down or voided.** Refunding never raises, never
   re-opens a void invoice, and recomputes the status from completed payments. Tested in Task 3.
4. **The fee on tiny and odd amounts:** 1 minor unit; KWD 1 fils with the fee off (no Stripe); JPY 101
   (fee 5). Never 0-amount line items, and never a total Stripe would refuse for a 3-digit currency.
   Tested in Task 4.
5. **A secret shown back by mistake.** No API payload, error body or log line ever carries a secret or its
   Fernet token. Settings answers only `has_secret`/`has_webhook_secret`. Tested in Task 4 (payload) and
   Task 5 (provider errors log no key).

## File structure

**Backend (`backend/`)**

| Path | Responsibility |
|---|---|
| `requirements/base.txt`, `requirements/local.txt` | `httpx`, `cryptography`; `respx` |
| `etqan/platform/currency.py` | minor digits per currency |
| `etqan/platform/secrets.py` | Fernet encrypt and decrypt under `ETQAN_SECRETS_KEY` |
| `etqan/platform/exceptions.py`, `etqan/platform/drf.py` | `UnavailableError` → 503 |
| `config/settings/{base,local,test}.py` | keys, simulator, throttle scope, beat entry |
| `etqan/gateways/{__init__,apps,clock,checks}.py` | the app, its clock, its system check |
| `etqan/gateways/models.py` (+ migration) | `GatewayAccount`, `GatewaySettings`, `Checkout`, `WebhookEvent` |
| `etqan/gateways/providers/{__init__,base,stripe,simulator}.py` | the provider interface and two providers |
| `etqan/gateways/services/__init__.py` | the public API |
| `etqan/gateways/services/accounts.py` | settings and keys |
| `etqan/gateways/services/fees.py` | fee, currencies, `providers_for` |
| `etqan/gateways/services/purposes.py` | registry and dataclasses |
| `etqan/gateways/services/checkouts.py` | start, reuse and supersede, reads, resolve, expiry |
| `etqan/gateways/services/webhooks.py` | verify and process Stripe events |
| `etqan/gateways/services/simulator.py` | build and sign fake events |
| `etqan/gateways/{tasks}.py` | the expiry job |
| `etqan/gateways/api/{__init__,serializers,payloads,views,urls}.py` | `/api/v1/gateways/` |
| `etqan/gateways/tests/…` | conftest and tests per area |
| `etqan/billing/models.py` (+ migration) | payment status, fee, transaction number |
| `etqan/billing/services/{rules,payments,summary,online,__init__}.py` | completed-only sums, refunds, the invoice purpose |
| `etqan/billing/{apps.py}`, `etqan/billing/api/{views,payloads,urls,serializers}.py` | registration, refund route, payloads |
| `etqan/tenants/seeds/gateways.py` | the demo Stripe test account |

**Dashboard (`dashboard/`)**

| Path | Responsibility |
|---|---|
| `src/features/gateways/schemas.ts` | types, option lists, form schemas |
| `src/features/gateways/api.ts`, `queries.ts` | routes and React Query hooks |
| `src/features/gateways/redirect.ts` | `go(url)`, the one full-page navigation (mocked in tests) |
| `src/features/gateways/GatewaySettingsPage.tsx` | Settings → Payment gateways |
| `src/features/gateways/PayOnline.tsx` | the invoice's Pay online button and confirm sheet |
| `src/features/gateways/ReturnPage.tsx` | `/pay/return` |
| `src/features/gateways/SimulatorPage.tsx` | `/pay/simulate/$checkoutId` |
| `src/features/gateways/CheckoutsList.tsx` | Billing → Online payments |
| `src/features/gateways/index.ts` | exports |
| `src/features/billing/{schemas,api,InvoicePage}.tsx?` | payment fields, refund, Pay online slot |
| `src/routes/_authed/{settings.gateways,billing.checkouts,pay.return,pay.simulate.$checkoutId}.tsx` | routes |
| `src/locales/{en,ar}/gateways.json` | the new translation area |
| `src/test/gateways-fixtures.ts` | API-shaped rows for tests |
| `e2e/b3-online-payments.spec.ts` | the journey through Caddy |

---
### Task 1: Dependencies, currency digits, secrets and the 503 error (platform)

**Files:**
- Modify: `backend/requirements/base.txt`, `backend/requirements/local.txt`
- Create: `backend/etqan/platform/currency.py`, `backend/etqan/platform/secrets.py`
- Modify: `backend/etqan/platform/exceptions.py`, `backend/etqan/platform/drf.py`
- Modify: `backend/config/settings/base.py`, `backend/config/settings/local.py`, `backend/config/settings/test.py`
- Test: `backend/etqan/platform/tests/test_currency.py`, `backend/etqan/platform/tests/test_secrets.py`, `backend/etqan/platform/tests/test_drf.py`

**Interfaces:**
- Produces:
  - `etqan.platform.currency.minor_digits(code: str) -> int`
  - `etqan.platform.currency.MINOR_DIGITS: dict[str, int]` (only the non-2 currencies)
  - `etqan.platform.secrets.encrypt(text: str) -> str`
  - `etqan.platform.secrets.decrypt(token: str) -> str`
  - `etqan.platform.secrets.available() -> bool`
  - `etqan.platform.exceptions.UnavailableError(message: str, code: str)`, which answers 503 with `{"detail", "code"}`
  - settings `ETQAN_SECRETS_KEY` (str), `SECRETS_KEY_FROM_SECRET_KEY` (bool), `GATEWAYS_SIMULATE` (bool), throttle rate `gateway_simulate`

- [ ] **Step 0: Check the branch.**
  - `git -C backend branch --show-current` and `git -C dashboard branch --show-current` both print `feat/b3b-online-payments`.
  - `backend/etqan/finance/` exists (B3a is merged).

- [ ] **Step 1: Add the dependencies and rebuild**

`backend/requirements/base.txt`, after `django-storages[s3]>=1.14`:

```text
# B3b: Stripe's REST API (no SDK) and Fernet for the academy's gateway keys.
httpx>=0.27
cryptography>=43.0
```

`backend/requirements/local.txt`, after `factory-boy>=3.3`:

```text
respx>=0.21  # B3b: mocks httpx in the gateway tests
```

Run (from the meta worktree): `just rebuild && just dev-backend`.

Then check: `$DJ python -c "import httpx, respx, cryptography; print('ok')"` prints `ok`.

- [ ] **Step 2: Write the failing tests**

`backend/etqan/platform/tests/test_currency.py`:

```python
"""B3b D4: how many minor units a currency has."""

import pytest

from etqan.platform.currency import minor_digits


@pytest.mark.parametrize(
    ("code", "digits"),
    [("USD", 2), ("EGP", 2), ("SAR", 2), ("JPY", 0), ("KRW", 0), ("KWD", 3), ("BHD", 3), ("JOD", 3), ("OMR", 3), ("TND", 3)],
)
def test_minor_digits(code, digits):
    assert minor_digits(code) == digits


def test_an_unknown_or_lower_case_code_reads_as_upper_case_or_two():
    assert minor_digits("jpy") == 0
    assert minor_digits("XYZ") == 2
```

`backend/etqan/platform/tests/test_secrets.py`:

```python
"""B3b D3: the academy's gateway keys are Fernet tokens at rest."""

import pytest
from cryptography.fernet import Fernet
from django.test import override_settings

from etqan.platform import secrets
from etqan.platform.exceptions import UnavailableError


def test_a_secret_round_trips_and_the_token_hides_it():
    token = secrets.encrypt("sk_test_abc")
    assert token != "sk_test_abc"
    assert "sk_test_abc" not in token
    assert secrets.decrypt(token) == "sk_test_abc"


@override_settings(ETQAN_SECRETS_KEY="", SECRETS_KEY_FROM_SECRET_KEY=True)
def test_without_a_key_dev_and_tests_derive_one_from_secret_key():
    assert secrets.available()
    assert secrets.decrypt(secrets.encrypt("x")) == "x"


def test_a_configured_key_is_used():
    key = Fernet.generate_key().decode()
    with override_settings(ETQAN_SECRETS_KEY=key):
        token = secrets.encrypt("whsec_1")
        assert Fernet(key.encode()).decrypt(token.encode()).decode() == "whsec_1"


@override_settings(ETQAN_SECRETS_KEY="", SECRETS_KEY_FROM_SECRET_KEY=False)
def test_production_without_a_key_fails_closed():
    assert not secrets.available()
    with pytest.raises(UnavailableError) as refused:
        secrets.encrypt("sk_live_x")
    assert refused.value.code == "gateways.no_key"
    with pytest.raises(UnavailableError):
        secrets.decrypt("anything")


def test_a_token_from_another_key_is_unavailable_not_a_crash():
    other = Fernet(Fernet.generate_key()).encrypt(b"x").decode()
    with pytest.raises(UnavailableError) as refused:
        secrets.decrypt(other)
    assert refused.value.code == "gateways.bad_key"
```

Append to `backend/etqan/platform/tests/test_drf.py` (and add `UnavailableError` to its imports, in isort order):

```python
def test_unavailable_error_maps_to_503_with_its_code():
    resp = exception_handler(UnavailableError("No key.", code="gateways.no_key"), {})
    assert resp.status_code == 503
    assert resp.data == {"detail": "No key.", "code": "gateways.no_key"}
```

- [ ] **Step 3: Run them to see them fail**

Run: `$DJ pytest etqan/platform/tests/test_currency.py etqan/platform/tests/test_secrets.py etqan/platform/tests/test_drf.py -q`
Expected: collection errors (`ModuleNotFoundError: etqan.platform.currency`, `ImportError: UnavailableError`).

- [ ] **Step 4: Implement**

`backend/etqan/platform/currency.py`:

```python
"""How many minor units each ISO 4217 currency has (B3b D4). Money is
stored in minor units everywhere; a provider that speaks decimals, or that
rounds by the unit, asks here. Two digits unless listed."""

MINOR_DIGITS: dict[str, int] = {
    **dict.fromkeys(
        (
            "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW",
            "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF",
        ),
        0,
    ),
    **dict.fromkeys(("BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"), 3),
}


def minor_digits(code: str) -> int:
    return MINOR_DIGITS.get(code.upper(), 2)
```

`backend/etqan/platform/secrets.py`:

```python
"""Secrets at rest (B3 phase B3-6, B3b D3): an academy's gateway keys are
stored as Fernet tokens under ``ETQAN_SECRETS_KEY``. Development and tests
may derive the key from ``SECRET_KEY`` (``SECRETS_KEY_FROM_SECRET_KEY``);
production has no fallback, so a missing key fails closed (503) rather than
storing or using a key in the clear."""

import base64
import hashlib

from cryptography.fernet import Fernet
from cryptography.fernet import InvalidToken
from django.conf import settings

from etqan.platform.exceptions import UnavailableError

NO_KEY = "gateways.no_key"
BAD_KEY = "gateways.bad_key"


def _key() -> bytes | None:
    configured = getattr(settings, "ETQAN_SECRETS_KEY", "")
    if configured:
        return configured.encode()
    if getattr(settings, "SECRETS_KEY_FROM_SECRET_KEY", False):
        digest = hashlib.sha256(settings.SECRET_KEY.encode()).digest()
        return base64.urlsafe_b64encode(digest)
    return None


def available() -> bool:
    return _key() is not None


def _fernet() -> Fernet:
    key = _key()
    if key is None:
        raise UnavailableError("Secrets cannot be stored or read here.", code=NO_KEY)
    return Fernet(key)


def encrypt(text: str) -> str:
    return _fernet().encrypt(text.encode()).decode()


def decrypt(token: str) -> str:
    try:
        return _fernet().decrypt(token.encode()).decode()
    except InvalidToken:
        # Stored under another key (a rotated or lost ETQAN_SECRETS_KEY):
        # the admin must enter the key again, nothing else can read it.
        raise UnavailableError(
            "A stored secret cannot be read with this key.", code=BAD_KEY
        ) from None
```

`backend/etqan/platform/exceptions.py`, append:

```python
class UnavailableError(EtqanError):
    """This server cannot do it as configured (503): for example no key to
    read or store an academy's gateway secrets. ``code`` names the reason
    for clients, as ConflictError's does."""

    def __init__(self, message: str, code: str):
        super().__init__(message=message, code=code)
```

`backend/etqan/platform/drf.py`:
- import `UnavailableError` (isort order);
- add `(UnavailableError, status.HTTP_503_SERVICE_UNAVAILABLE),` to `_STATUS_BY_TYPE` after the `ExternalServiceError` row;
- change `if isinstance(exc, ConflictError):` to `if isinstance(exc, ConflictError | UnavailableError):`.

`backend/config/settings/base.py`:

1. After the `FRONTEND_URL` block, add:

```python
# B3b (phase B3-6): a Fernet key for secrets at rest (academies' gateway
# keys). Production must set it; dev and tests may derive one from
# SECRET_KEY (local.py / test.py set SECRETS_KEY_FROM_SECRET_KEY).
ETQAN_SECRETS_KEY = env("ETQAN_SECRETS_KEY", default="")
SECRETS_KEY_FROM_SECRET_KEY = False
# B3b B-12: checkouts in a test-mode account never reach Stripe; a dashboard
# page plays the provider. The gateways system check refuses it without DEBUG.
GATEWAYS_SIMULATE = env.bool("GATEWAYS_SIMULATE", default=False)
```

2. In `REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"]`, add `"gateway_simulate": "30/minute",`.

`backend/config/settings/local.py`, after `SECRET_KEY = env(...)`:

```python
SECRETS_KEY_FROM_SECRET_KEY = True
GATEWAYS_SIMULATE = env.bool("GATEWAYS_SIMULATE", default=True)
```

`backend/config/settings/test.py`, after `SECRET_KEY = ...`:

```python
SECRETS_KEY_FROM_SECRET_KEY = True
GATEWAYS_SIMULATE = True
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `$DJ pytest etqan/platform -q`
Expected: all pass.

- [ ] **Step 6: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add requirements/base.txt requirements/local.txt etqan/platform config/settings
git -C backend commit -m "feat(platform): currency digits, Fernet secrets and a 503 error for B3b"
```

---
### Task 2: The gateways app, its models, its feature, its contracts and its system check

**Files:**
- Create: `backend/etqan/gateways/__init__.py` (empty), `apps.py`, `clock.py`, `checks.py`, `models.py`, `migrations/__init__.py`, `migrations/0001_initial.py` (generated), `services/__init__.py`, `tests/__init__.py`, `tests/conftest.py`, `tests/test_models.py`, `tests/test_checks.py`
- Modify: `backend/config/settings/base.py` (`TENANT_APPS`, under the B3 marker after `"etqan.finance"`)
- Modify: `backend/etqan/platform/features.py` (under the B3 marker, after `expenses`)
- Modify: `backend/etqan/platform/tests/test_features.py` (`BUILT` gains `"online_payments": False` after `"expenses": False`)
- Modify: `backend/pyproject.toml`:
  - the platform contract's forbidden list, under its B3 marker after `"etqan.finance"`;
  - the B3 contracts block, after "billing never imports finance"

**Interfaces:**
- Produces:
  - models `GatewayAccount`, `GatewaySettings`, `Checkout`, `WebhookEvent`
  - `GatewayAccount.Provider.STRIPE = "stripe"`; `Mode.TEST = "test"`, `Mode.LIVE = "live"`
  - `Checkout.Status`: `PENDING`, `COMPLETED`, `FAILED`, `CANCELLED`, `EXPIRED`
  - `gateways.clock.now() -> datetime`
  - fixtures:
    - `clock` (a `Clock` chaining billing's and gateways'; `.set(when)`)
    - `world`
    - `admin`
    - `online_on` (`set_features(invoices=True, online_payments=True)`)
    - `invoice` (factory `invoice(amount_minor=…, currency=…, payer=…)`)
    - `parent_of_world`
  - the feature `online_payments`

- [ ] **Step 1: Write the failing tests**

`backend/etqan/gateways/tests/conftest.py`:

```python
"""Gateways fixtures. Every clock is pinned to Monday 1 June 2026, 08:00 UTC:
scheduling's, billing's (invoice and payment dates) and gateways' (signature
tolerance, completion, expiry)."""

from datetime import date

import pytest

from etqan.billing import services as billing_services
from etqan.billing.tests.conftest import Clock as BillingClock
from etqan.billing.tests.conftest import make_parent
from etqan.gateways import clock as gateways_clock
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_admin


class Clock(BillingClock):
    def set(self, when) -> None:
        super().set(when)
        self._monkeypatch.setattr(gateways_clock, "now", lambda: when)


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
def online_on(set_features):
    """B3b ships `online_payments` off; it requires `invoices`."""
    return set_features(invoices=True, online_payments=True)


@pytest.fixture
def parent_of_world(world):
    return make_parent("Zainab", world.student)


@pytest.fixture
def invoice(world, admin):
    """`invoice(amount_minor=50000)`: an unpaid EGP invoice for Yusuf, due
    8 June, the payer his first guardian if he has one, else himself."""

    def make(**overrides):
        fields = {
            "student_id": world.student.id,
            "amount_minor": 50000,
            "currency": "EGP",
            "due_on": date(2026, 6, 8),
            "description": "Tajweed — June",
            "by": admin,
            **overrides,
        }
        return billing_services.create_invoice(**fields)

    return make
```

`backend/etqan/gateways/tests/test_models.py`:

```python
"""B3b §3.1: the gateway tables and their database rules."""

import uuid

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.gateways.models import Checkout
from etqan.gateways.models import GatewayAccount
from etqan.gateways.models import GatewaySettings
from etqan.gateways.models import WebhookEvent

pytestmark = pytest.mark.django_db


def checkout(**overrides):
    fields = {
        "purpose": "invoice",
        "reference_id": 1,
        "provider": "stripe",
        "amount_minor": 1000,
        "fee_minor": 50,
        "currency": "EGP",
        **overrides,
    }
    return Checkout.objects.create(**fields)


def refused(**fields):
    with pytest.raises(IntegrityError), transaction.atomic():
        checkout(**fields)


def test_a_checkout_is_pending_with_a_uuid_and_nothing_applied():
    made = checkout()
    assert isinstance(made.pk, uuid.UUID)
    assert made.status == Checkout.Status.PENDING
    assert made.applied is None
    assert made.attention == ""
    assert made.simulated is False


def test_amounts_are_checked_by_the_database():
    refused(amount_minor=0)
    refused(fee_minor=-1)


def test_a_provider_ref_is_unique_when_set():
    checkout(provider_ref="cs_1")
    checkout(provider_ref="")
    checkout(provider_ref="")
    refused(provider_ref="cs_1")


def test_one_account_per_provider_and_one_settings_row():
    GatewayAccount.objects.create(provider="stripe")
    with pytest.raises(IntegrityError), transaction.atomic():
        GatewayAccount.objects.create(provider="stripe")
    settings = GatewaySettings.load()
    assert (settings.pk, settings.fee_enabled, settings.fee_basis_points) == (1, True, 500)
    assert GatewaySettings.load().pk == 1
    assert GatewaySettings.objects.count() == 1


def test_an_event_id_is_unique_per_provider():
    WebhookEvent.objects.create(provider="stripe", event_id="evt_1", type="x")
    WebhookEvent.objects.create(provider="paypal", event_id="evt_1", type="x")
    with pytest.raises(IntegrityError), transaction.atomic():
        WebhookEvent.objects.create(provider="stripe", event_id="evt_1", type="y")
```

`backend/etqan/gateways/tests/test_checks.py`:

```python
"""B-12: the simulator never runs on a server without DEBUG."""

from django.test import override_settings

from etqan.gateways.checks import simulator_needs_debug


@override_settings(DEBUG=False, GATEWAYS_SIMULATE=True)
def test_the_simulator_without_debug_is_an_error():
    errors = simulator_needs_debug(None)
    assert [e.id for e in errors] == ["gateways.E001"]


@override_settings(DEBUG=True, GATEWAYS_SIMULATE=True)
def test_the_simulator_with_debug_is_fine():
    assert simulator_needs_debug(None) == []


@override_settings(DEBUG=False, GATEWAYS_SIMULATE=False)
def test_no_simulator_is_fine():
    assert simulator_needs_debug(None) == []
```

In `backend/etqan/platform/tests/test_features.py`, add the line below `"expenses": False,` (under the B3 marker of the `BUILT` dict):

```python
    "online_payments": False,
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DJ pytest etqan/gateways etqan/platform/tests/test_features.py -q`
Expected: collection errors (no `etqan.gateways`) and a `test_the_defaults_match_the_spec` failure.

- [ ] **Step 3: Implement the app**

`backend/etqan/gateways/apps.py`:

```python
from django.apps import AppConfig


class GatewaysConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.gateways"
    label = "gateways"

    def ready(self):
        from etqan.gateways import checks  # noqa: F401, PLC0415 -- registers the check
```

`backend/etqan/gateways/clock.py`:

```python
"""The only clock gateways reads (B3b D10), so tests pin it by monkeypatching
`now`: the signature tolerance, completion times and expiry."""

from datetime import datetime

from django.utils import timezone


def now() -> datetime:
    """The current instant, timezone-aware UTC."""
    return timezone.now()
```

`backend/etqan/gateways/checks.py`:

```python
"""B3b B-12: the offline simulator is for development, tests and CI. A
server without DEBUG must never take a "payment" no provider made."""

from django.conf import settings
from django.core.checks import Error
from django.core.checks import register


@register()
def simulator_needs_debug(app_configs, **kwargs):
    if getattr(settings, "GATEWAYS_SIMULATE", False) and not settings.DEBUG:
        return [
            Error(
                "GATEWAYS_SIMULATE is on without DEBUG.",
                hint="Turn GATEWAYS_SIMULATE off outside development and CI.",
                id="gateways.E001",
            )
        ]
    return []
```

`backend/etqan/gateways/models.py`:

```python
"""Online payments (B3b §3.1): each academy's own gateway accounts, the fee
settings, the checkouts families start, and every provider event received.

Gateways imports no business app: what a checkout pays for is a registered
purpose and an id (B-1). Business rules live in `etqan.gateways.services`.
"""

import uuid

from django.conf import settings
from django.core.validators import MaxValueValidator
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
from django.db import models
from django.db.models import Q

CURRENCY = RegexValidator(r"^[A-Z]{3}$")


class GatewayAccount(models.Model):
    class Provider(models.TextChoices):
        STRIPE = "stripe", "Stripe"

    class Mode(models.TextChoices):
        TEST = "test", "Test"
        LIVE = "live", "Live"

    provider = models.CharField(max_length=16, choices=Provider.choices, unique=True)
    enabled = models.BooleanField(default=False)
    mode = models.CharField(max_length=4, choices=Mode.choices, default=Mode.TEST)
    public_key = models.CharField(max_length=200, blank=True, default="")
    # Fernet tokens (etqan.platform.secrets), never the keys themselves.
    secret_enc = models.TextField(blank=True, default="")
    webhook_secret_enc = models.TextField(blank=True, default="")
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"GatewayAccount<{self.provider}, {self.mode}, {self.enabled}>"


class GatewaySettings(models.Model):
    """One row (pk 1) per academy (B-7)."""

    fee_enabled = models.BooleanField(default=True)
    fee_basis_points = models.PositiveIntegerField(
        default=500, validators=[MinValueValidator(0), MaxValueValidator(2000)]
    )

    def __str__(self):
        return f"GatewaySettings<{self.fee_enabled}, {self.fee_basis_points}>"

    @classmethod
    def load(cls) -> "GatewaySettings":
        settings_row, _ = cls.objects.get_or_create(pk=1)
        return settings_row


class Checkout(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        COMPLETED = "completed", "Completed"
        FAILED = "failed", "Failed"
        CANCELLED = "cancelled", "Cancelled"
        EXPIRED = "expired", "Expired"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    purpose = models.CharField(max_length=40)
    reference_id = models.BigIntegerField()
    provider = models.CharField(max_length=16)
    simulated = models.BooleanField(default=False)
    amount_minor = models.BigIntegerField()
    fee_minor = models.BigIntegerField(default=0)
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.PENDING
    )
    # Null until completed; false: the purpose could not take the money (B-11).
    applied = models.BooleanField(null=True, blank=True)
    # A short code (plan D8), blank unless applied is false.
    attention = models.CharField(max_length=40, blank=True, default="")
    resolved_at = models.DateTimeField(null=True, blank=True)
    resolved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    provider_ref = models.CharField(max_length=255, blank=True, default="")
    redirect_url = models.URLField(max_length=500, blank=True, default="")
    transaction_number = models.CharField(max_length=120, blank=True, default="")
    description = models.CharField(max_length=200, blank=True, default="")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=Q(amount_minor__gt=0),
                name="gateways_checkout_amount_positive",
            ),
            models.CheckConstraint(
                condition=Q(fee_minor__gte=0), name="gateways_checkout_fee_not_negative"
            ),
            models.UniqueConstraint(
                fields=["provider_ref"],
                condition=~Q(provider_ref=""),
                name="gateways_checkout_provider_ref_unique",
            ),
        ]
        indexes = [
            models.Index(fields=["purpose", "reference_id", "provider", "status"]),
            models.Index(fields=["status"]),
        ]

    def __str__(self):
        return f"Checkout<{self.pk}, {self.status}>"


class WebhookEvent(models.Model):
    """Every verified provider event, recorded with its effects (§4.4): a
    replay finds its row and does nothing."""

    provider = models.CharField(max_length=16)
    event_id = models.CharField(max_length=255)
    type = models.CharField(max_length=100)
    received_at = models.DateTimeField(auto_now_add=True)
    checkout = models.ForeignKey(
        Checkout,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="events",
    )

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["provider", "event_id"], name="gateways_event_unique"
            )
        ]

    def __str__(self):
        return f"WebhookEvent<{self.provider}, {self.event_id}>"
```

`backend/etqan/gateways/services/__init__.py`:

```python
"""Public API of the gateways module. Other apps import only this package."""

__all__: list[str] = []
```

- [ ] **Step 4: Register the app, the feature and the contracts**

`backend/config/settings/base.py`: in `TENANT_APPS`, after the existing `"etqan.finance",` line (below the B3 marker), add `"etqan.gateways",`.

`backend/etqan/platform/features.py`: below the `expenses` line under the B3 marker, add:

```python
    # B3b: families pay invoices online (Stripe); needs invoices (B-13).
    Feature(
        "online_payments",
        "Online payments",
        "الدفع الإلكتروني",
        "money",
        default=False,
        built=True,
        requires=("invoices",),
    ),
```

`backend/pyproject.toml`:

- In the platform contract's `forbidden_modules`, after `"etqan.finance",` (below its B3 marker), add `"etqan.gateways",`.
- In the B3 contracts block, after the "billing never imports finance" contract, add:

```toml
[[tool.importlinter.contracts]]
name = "gateways imports no business app"
type = "forbidden"
# B3b B-1: what a checkout pays for is a purpose name and an id; the selling
# app registers callbacks. Users are referenced by string.
source_modules = ["etqan.gateways"]
forbidden_modules = [
    "etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.scheduling",
    "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access",
    "etqan.tenants", "etqan.site", "etqan.finance",
]

[[tool.importlinter.contracts]]
name = "other apps reach gateways only through its services"
type = "forbidden"
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.scheduling", "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access", "etqan.finance"]
forbidden_modules = ["etqan.gateways.models", "etqan.gateways.api", "etqan.gateways.providers", "etqan.gateways.clock"]
allow_indirect_imports = true
```

The gateways tests build invoices through billing's services and fixtures, which this contract would
forbid. Add this line to the first contract (import-linter 2's `**` matches any depth):

```toml
ignore_imports = ["etqan.gateways.tests.** -> etqan.**"]
```

- [ ] **Step 5: Generate the migration and run the tests**

Run:
- `$DJ python manage.py makemigrations gateways`
- `$DJ pytest etqan/gateways etqan/platform/tests/test_features.py etqan/academy/tests/test_features_api.py --create-db -q`

Expected: all pass. `test_features_api` reads `len(features.REGISTRY)`, so it needs no edit.

- [ ] **Step 6: Lint, contracts and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/gateways etqan/platform/features.py etqan/platform/tests/test_features.py config/settings/base.py pyproject.toml
git -C backend commit -m "feat(gateways): the app, its models and the online_payments feature (off)"
```

---
### Task 3: Billing — payment status, fee, transaction number, refunds

**Files:**
- Modify: `backend/etqan/billing/models.py`, plus the generated migration `backend/etqan/billing/migrations/0003_…py`
- Modify: `backend/etqan/billing/services/rules.py`, `payments.py`, `summary.py`, `__init__.py`
- Modify: `backend/etqan/billing/api/serializers.py`, `payloads.py`, `views.py`, `urls.py`
- Modify: `backend/etqan/access/registry.py`: the `payment` line's `in_use` gains `"update"`. The line sits above the B3 marker, but billing is B3's, so it is edited in place.
- Modify: `backend/etqan/access/tests/test_routes.py`: a `ROUTES` row and its `FEATURES` row under `"invoices"`
- Test: `backend/etqan/billing/tests/test_refunds.py` (new); `backend/etqan/billing/tests/test_summary.py` (one test added)

**Interfaces:**
- Produces, all exported from `etqan.billing.services`:
  - `ONLINE_METHODS: frozenset[str]` = `{"stripe", "paypal"}`
  - `MANUAL_PAYMENT_METHODS`, the manual `(value, label)` pairs, unchanged in content
  - `record_online_payment(invoice, *, amount_minor: int, fee_minor: int, method: str, transaction_number: str) -> Payment`
  - `refund_payment(payment, *, by) -> Payment`
  - `Payment.Status.COMPLETED` and `Payment.Status.REFUNDED`
- Consumed by: Task 6 (the invoice purpose calls `record_online_payment`).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/billing/tests/test_refunds.py`:

```python
"""B3b B-7, B-9, B-10, §4.7: completed payments count; a refund takes a
payment out of the invoice's paid amount and out of revenue; online payments
are refunded, never deleted."""

from datetime import date

import pytest

from etqan.billing import services
from etqan.billing.models import Invoice
from etqan.billing.models import Payment
from etqan.billing.tests.test_invoices import invoice_for
from etqan.billing.tests.test_invoices import pay
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
JUNE_1 = date(2026, 6, 1)


def online(invoice, amount, *, fee=50, ref="pi_1", method="stripe"):
    return services.record_online_payment(
        invoice,
        amount_minor=amount,
        fee_minor=fee,
        method=method,
        transaction_number=ref,
    )


def fresh(invoice) -> Invoice:
    return services.invoices_queryset().get(pk=invoice.pk)


def test_an_online_payment_is_dated_today_by_nobody_with_its_fee(world, admin):
    invoice = invoice_for(world, admin, amount_minor=1000)
    payment = online(invoice, 1000, fee=50, ref="pi_9")
    assert (payment.paid_on, payment.recorded_by, payment.fee_minor) == (JUNE_1, None, 50)
    assert (payment.method, payment.transaction_number) == ("stripe", "pi_9")
    assert payment.status == Payment.Status.COMPLETED
    assert fresh(invoice).status == "paid"


def test_an_online_payment_obeys_the_balance_and_void(world, admin):
    invoice = invoice_for(world, admin, amount_minor=1000)
    with pytest.raises(ValidationError) as refused:
        online(invoice, 1001)
    assert refused.value.field == "amount_minor"
    other = invoice_for(world, admin, amount_minor=1000)
    services.void_invoice(other, by=admin)
    with pytest.raises(ConflictError) as void:
        online(other, 10)
    assert void.value.code == "billing.invoice_void"


def test_a_transaction_number_is_used_once_per_method(world, admin):
    invoice = invoice_for(world, admin, amount_minor=1000)
    online(invoice, 400, ref="pi_same")
    with pytest.raises(ValidationError):
        online(invoice, 400, ref="pi_same")
    online(invoice, 400, ref="pi_same", method="paypal")


def test_manual_payments_may_not_claim_an_online_method(world, admin):
    invoice = invoice_for(world, admin, amount_minor=1000)
    with pytest.raises(ValidationError) as refused:
        pay(invoice, admin, 100, method="stripe")
    assert refused.value.field == "method"


def test_a_refund_takes_the_payment_out_of_paid_and_the_status_follows(world, admin):
    invoice = invoice_for(world, admin, amount_minor=1000)
    cash = pay(invoice, admin, 600)
    card = online(invoice, 400)
    assert fresh(invoice).status == "paid"
    refunded = services.refund_payment(card, by=admin)
    assert (refunded.status, refunded.refunded_by) == ("refunded", admin)
    assert refunded.refunded_at is not None
    row = fresh(invoice)
    assert (row.status, row.paid_minor, row.balance_minor) == ("partial", 600, 400)
    services.refund_payment(cash, by=admin)
    assert fresh(invoice).status == "unpaid"


def test_a_second_refund_is_refused(world, admin):
    invoice = invoice_for(world, admin, amount_minor=1000)
    card = online(invoice, 1000)
    services.refund_payment(card, by=admin)
    with pytest.raises(ConflictError) as again:
        services.refund_payment(card, by=admin)
    assert again.value.code == "billing.already_refunded"


def test_once_everything_is_refunded_the_invoice_can_be_edited_and_voided(world, admin):
    invoice = invoice_for(world, admin, amount_minor=1000)
    services.refund_payment(online(invoice, 1000), by=admin)
    services.update_invoice(invoice, amount_minor=900)
    voided = services.void_invoice(invoice, by=admin)
    assert voided.status == "void"
    # Review Focus 3: a refunded payment on a void invoice stays refunded,
    # and nothing re-opens the invoice.
    payment = Payment.objects.get(invoice=invoice)
    with pytest.raises(ConflictError):
        services.refund_payment(payment, by=admin)
    assert fresh(invoice).status == "void"


def test_online_payments_cannot_be_deleted_but_refunded_manual_ones_can(world, admin):
    invoice = invoice_for(world, admin, amount_minor=1000)
    card = online(invoice, 500)
    with pytest.raises(ConflictError) as refused:
        services.delete_payment(card)
    assert refused.value.code == "billing.online_payment"
    cash = pay(invoice, admin, 500)
    services.refund_payment(cash, by=admin)
    services.delete_payment(cash)
    assert not Payment.objects.filter(pk=cash.pk).exists()


def test_the_refund_route(api_for, world, admin):
    invoice = invoice_for(world, admin, amount_minor=1000)
    card = online(invoice, 1000)
    client = api_for("admin")
    resp = client.post(f"/api/v1/billing/payments/{card.pk}/refund/")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "unpaid"
    assert body["payments"][0]["status"] == "refunded"
    assert body["payments"][0]["fee_minor"] == 50
    assert body["payments"][0]["transaction_number"] == "pi_1"
    assert body["payments"][0]["refunded_at"] is not None
    again = client.post(f"/api/v1/billing/payments/{card.pk}/refund/")
    assert (again.status_code, again.json()["code"]) == (409, "billing.already_refunded")
    gone = client.delete(f"/api/v1/billing/payments/{card.pk}/")
    assert (gone.status_code, gone.json()["code"]) == (409, "billing.online_payment")


def test_the_manual_payment_route_refuses_an_online_method(api_for, world, admin):
    invoice = invoice_for(world, admin, amount_minor=1000)
    resp = api_for("admin").post(
        f"/api/v1/billing/invoices/{invoice.pk}/payments/",
        {"amount_minor": 100, "method": "stripe", "paid_on": "2026-06-01"},
        format="json",
    )
    assert resp.status_code == 400
    assert "method" in resp.json()
```

Append to `backend/etqan/billing/tests/test_summary.py` (add the imports it needs, in isort order):

```python
def test_revenue_counts_the_fee_and_only_completed_payments(world, admin):
    invoice = invoice_for(world, admin, amount_minor=1000, currency="EGP")
    card = services.record_online_payment(
        invoice, amount_minor=600, fee_minor=30, method="stripe", transaction_number="pi_r"
    )
    services.add_payment(
        invoice, amount_minor=400, method="cash", paid_on=date(2026, 6, 1), by=admin
    )
    first, following = date(2026, 6, 1), date(2026, 7, 1)
    assert services.revenue_between(first, following) == [
        {"currency": "EGP", "amount_minor": 1030}
    ]
    services.refund_payment(card, by=admin)
    assert services.revenue_between(first, following) == [
        {"currency": "EGP", "amount_minor": 400}
    ]
```

At the top of `test_summary.py`, add `from etqan.billing.tests.test_invoices import invoice_for`, and `from datetime import date` if it is missing (isort order). `world` and `admin` are fixtures from `billing/tests/conftest.py`.

In `backend/etqan/access/tests/test_routes.py`:
- in `ROUTES`, after `("DELETE", f"/api/v1/billing/payments/{N}/", "payment.delete"),`, add
  `("POST", f"/api/v1/billing/payments/{N}/refund/", "payment.update"),`;
- in `FEATURES`'s `"invoices"` tuple, after `("DELETE", f"/api/v1/billing/payments/{N}/"),`, add
  `("POST", f"/api/v1/billing/payments/{N}/refund/"),`.

- [ ] **Step 2: Run them to see them fail**

Run: `$DJ pytest etqan/billing/tests/test_refunds.py etqan/billing/tests/test_summary.py etqan/access/tests/test_routes.py -q`
Expected: failures. `record_online_payment`, `refund_payment` and the route are missing, and the route table no longer matches.

- [ ] **Step 3: Implement the model**

In `backend/etqan/billing/models.py`, class `Payment`:

1. Add to `Method`, after `OTHER`:

```python
        # B3b B-9: recorded by their provider's verified event, never by hand.
        STRIPE = "stripe", "Stripe"
        PAYPAL = "paypal", "PayPal"
```

2. Add inside `Payment`, after `Method`:

```python
    class Status(models.TextChoices):
        COMPLETED = "completed", "Completed"
        REFUNDED = "refunded", "Refunded"
```

3. Add the fields after `notes`:

```python
    # B3b B-9: the service fee paid on top (online payments), the provider's
    # own id, and whether it still counts (a refund takes it out).
    fee_minor = models.BigIntegerField(default=0, validators=[MinValueValidator(0)])
    transaction_number = models.CharField(max_length=120, blank=True, default="")
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.COMPLETED
    )
    refunded_at = models.DateTimeField(null=True, blank=True)
    refunded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
```

4. Replace `Meta.constraints` with:

```python
        constraints = [
            models.CheckConstraint(
                condition=Q(amount_minor__gt=0), name="billing_payment_amount_positive"
            ),
            models.CheckConstraint(
                condition=Q(fee_minor__gte=0), name="billing_payment_fee_not_negative"
            ),
            models.UniqueConstraint(
                fields=["method", "transaction_number"],
                condition=~Q(transaction_number=""),
                name="billing_payment_transaction_unique",
            ),
        ]
```

Run `$DJ python manage.py makemigrations billing`. The migration only adds columns with defaults and constraints.

- [ ] **Step 4: Implement the rules, the payments and revenue**

`backend/etqan/billing/services/rules.py`:

1. Add, below `OPEN = (UNPAID, PARTIAL)`:

```python
# B3b B-9: a refunded payment no longer counts toward anything.
COUNTS = Q(status=Payment.Status.COMPLETED)
```

2. Change these three to count completed payments only:
   - `refuse_if_paid_into`: `Payment.objects.filter(COUNTS, invoice=invoice).exists()`
   - `paid_of`: `Payment.objects.filter(COUNTS, invoice=invoice).aggregate(...)`
   - `_paid_subquery`: `Payment.objects.filter(COUNTS, invoice=OuterRef("pk"))`
3. Update their docstrings to say "completed payments".

`backend/etqan/billing/services/payments.py`:

1. Replace the `MANUAL_PAYMENT_METHODS` definition with:

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

2. In `add_payment`, first thing after `locked = rules.lock(invoice)`, add:

```python
    if method in ONLINE_METHODS:
        raise ValidationError(
            "Online payments are recorded by their provider.", field="method"
        )
```

3. Add below `add_payment`:

```python
@transaction.atomic
def record_online_payment(
    invoice: Invoice,
    *,
    amount_minor: int,
    fee_minor: int,
    method: str,
    transaction_number: str,
) -> Payment:
    """A provider's payment (B3b §4.3): dated the academy's today, recorded by
    nobody, with its fee. The same balance and void rules as by hand; the
    transaction number is used once per method."""
    locked = rules.lock(invoice)
    rules.refuse_if_void(locked)
    if amount_minor > locked.amount_minor - rules.paid_of(locked):
        raise ValidationError("That is more than the balance.", field="amount_minor")
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
        invoice=locked,
        amount_minor=amount_minor,
        fee_minor=fee_minor,
        method=method,
        transaction_number=transaction_number,
        paid_on=clock.today(),
        recorded_by=None,
    )
    rules.save(payment)
    _recalculate(locked)
    return payment


@transaction.atomic
def refund_payment(payment: Payment, *, by) -> Payment:
    """Marked, not executed (phase B3-10): the payment stops counting and the
    invoice's status follows. A void invoice is never re-opened."""
    locked = rules.lock(payment.invoice)
    fresh = Payment.objects.select_for_update().get(pk=payment.pk)
    if fresh.status == Payment.Status.REFUNDED:
        raise ConflictError(
            "This payment is already refunded.", code="billing.already_refunded"
        )
    fresh.status = Payment.Status.REFUNDED
    fresh.refunded_at = clock.now()
    fresh.refunded_by = by
    fresh.save(update_fields=["status", "refunded_at", "refunded_by"])
    if locked.status != Invoice.Status.VOID:
        _recalculate(locked)
    return fresh
```

4. In `delete_payment`, after `locked = rules.lock(payment.invoice)`, add:

```python
    if payment.method in ONLINE_METHODS:
        raise ConflictError(
            "An online payment is refunded, never deleted.",
            code="billing.online_payment",
        )
```

5. Imports: `ConflictError` from `etqan.platform.exceptions`.

`backend/etqan/billing/services/summary.py`, `revenue_between`:

```python
    rows = (
        Payment.objects.filter(
            status=Payment.Status.COMPLETED, paid_on__gte=first, paid_on__lt=following
        )
        .values(currency=F("invoice__currency"))
        .annotate(amount_minor=Sum(F("amount_minor") + F("fee_minor")))
        .order_by("currency")
    )
```

Update its docstring: "completed payments, their fee included (B3b B-9: the fee is money received)".

`backend/etqan/billing/services/__init__.py`: import and list in `__all__` (alphabetical)
`ONLINE_METHODS`, `record_online_payment` and `refund_payment` from `etqan.billing.services.payments`.

- [ ] **Step 5: Implement the API**

`backend/etqan/billing/api/serializers.py`, `PaymentInput.method`:

```python
    # B3b B-9: only the manual methods by hand.
    method = serializers.ChoiceField(choices=services.MANUAL_PAYMENT_METHODS)
```

(Drop the now-unused `Payment` import if ruff flags it.)

`backend/etqan/billing/api/payloads.py`, `payment_row`'s dict, after `"reference"`:

```python
        "fee_minor": payment.fee_minor,
        "transaction_number": payment.transaction_number,
        "status": payment.status,
        "refunded_at": payment.refunded_at,
```

`backend/etqan/billing/api/views.py`, after `PaymentDetailView`:

```python
class RefundView(APIView):
    """B3b §4.7: marks a payment refunded; answers with its invoice."""

    permission_classes = [HasCode, FeatureOn]
    feature = "invoices"
    permission_codes = {"POST": "payment.update"}

    def post(self, request, pk):
        payment = get_object_or_404(Payment.objects.select_related("invoice"), pk=pk)
        services.refund_payment(payment, by=request.user)
        return detail(payment.invoice_id, request)
```

`backend/etqan/billing/api/urls.py`, after the `payments/<int:pk>/` path:

```python
    path(
        "payments/<int:pk>/refund/", views.RefundView.as_view(), name="payment-refund"
    ),
```

`backend/etqan/access/registry.py`, the payment line:

```python
    Resource(
        "payment", "Payments", "المدفوعات", ("view_any", "create", "update", "delete")
    ),
```

- [ ] **Step 6: Run the billing, finance and access suites**

Run: `$DJ pytest etqan/billing etqan/finance etqan/access --create-db -q`
Expected: all pass. B3a's donation-methods test is unchanged, because `MANUAL_PAYMENT_METHODS` keeps its nine pairs.

- [ ] **Step 7: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/billing etqan/access
git -C backend commit -m "feat(billing): payment status, fee and transaction number; refunds; completed-only sums"
```

---
### Task 4: Gateway settings, the fee rules and the settings API

**Files:**
- Create: `backend/etqan/gateways/services/accounts.py`, `backend/etqan/gateways/services/fees.py`
- Create: `backend/etqan/gateways/api/__init__.py` (empty), `serializers.py`, `payloads.py`, `views.py`, `urls.py`
- Modify: `backend/etqan/gateways/services/__init__.py`
- Modify: `backend/config/api_router.py`: under the B3 marker, after the finance path
- Modify: `backend/etqan/access/registry.py`: a `gateway` resource under the B3 marker
- Modify: `backend/etqan/access/tests/test_registry.py`: the resource count goes 24 → 25
- Modify: `backend/etqan/access/tests/test_routes.py`: `ROUTES`, `FEATURES`, `FEATURE_WORDS`
- Test: `backend/etqan/gateways/tests/test_fees.py`, `backend/etqan/gateways/tests/test_settings.py`

**Interfaces:**
- Consumes: `etqan.platform.secrets`, `etqan.platform.currency.minor_digits`, `etqan.platform.frontend.frontend_url`, `GatewayAccount`, `GatewaySettings` (Task 2).
- Produces, all exported from `etqan.gateways.services`:
  - `STRIPE_CURRENCIES: frozenset[str]`
  - `fee_for(amount_minor: int, currency: str, *, add_fee: bool, provider: str = "stripe") -> int | None`
    - returns `None` when the provider cannot take the amount (plan D5)
  - `providers_for(currency: str, amount_minor: int, *, add_fee: bool) -> list[str]`
  - `stripe_account() -> GatewayAccount`
  - `fee_settings() -> GatewaySettings`
  - `update_settings(*, stripe: dict | None = None, fee: dict | None = None, by) -> None`
  - `secret_of(account) -> str`
  - `webhook_secret_of(account) -> str`

- [ ] **Step 1: Write the failing tests**

`backend/etqan/gateways/tests/test_fees.py`:

```python
"""B-6, B-7, plan D5: the fee, half up, and what Stripe can take."""

import pytest

from etqan.gateways import services
from etqan.gateways.models import GatewaySettings

pytestmark = pytest.mark.django_db


def test_five_percent_half_up():
    assert services.fee_for(10000, "EGP", add_fee=True) == 500
    assert services.fee_for(10010, "EGP", add_fee=True) == 501  # 500.5 -> 501
    assert services.fee_for(10009, "EGP", add_fee=True) == 500  # 500.45 -> 500


def test_no_fee_when_the_purpose_or_the_academy_says_so():
    assert services.fee_for(10000, "EGP", add_fee=False) == 0
    GatewaySettings.objects.update_or_create(pk=1, defaults={"fee_enabled": False})
    assert services.fee_for(10000, "EGP", add_fee=True) == 0


def test_the_percentage_is_the_academys():
    GatewaySettings.objects.update_or_create(pk=1, defaults={"fee_basis_points": 250})
    assert services.fee_for(10000, "USD", add_fee=True) == 250


def test_review_focus_4_tiny_and_odd_amounts():
    assert services.fee_for(1, "EGP", add_fee=True) == 0
    assert services.fee_for(101, "JPY", add_fee=True) == 5
    # Three-digit currencies: the total must be a multiple of 10.
    assert services.fee_for(1000, "KWD", add_fee=True) == 50
    assert services.fee_for(1001, "KWD", add_fee=True) == 59  # 1001 + 59 = 1060
    assert services.fee_for(1000, "KWD", add_fee=False) == 0
    assert services.fee_for(1001, "KWD", add_fee=False) is None


def test_a_currency_stripe_does_not_take():
    assert "XYZ" not in services.STRIPE_CURRENCIES
    assert services.fee_for(1000, "XYZ", add_fee=True) is None


def test_providers_for_lists_enabled_providers_that_can_take_it(stripe_on):
    assert services.providers_for("EGP", 1000, add_fee=True) == ["stripe"]
    assert services.providers_for("XYZ", 1000, add_fee=True) == []
    assert services.providers_for("KWD", 1001, add_fee=False) == []


def test_providers_for_is_empty_when_stripe_is_off():
    assert services.providers_for("EGP", 1000, add_fee=True) == []
```

Add to `backend/etqan/gateways/tests/conftest.py`, with `from etqan.gateways import services as gateways_services` among the imports:

```python
TEST_KEYS = {
    "enabled": True,
    "mode": "test",
    "public_key": "pk_test_demo",
    "secret": "sk_test_demo",
    "webhook_secret": "whsec_demo",
}


@pytest.fixture
def stripe_on():
    """An enabled Stripe account in test mode with placeholder keys."""
    gateways_services.update_settings(stripe=TEST_KEYS, by=None)
    return gateways_services.stripe_account()
```

`backend/etqan/gateways/tests/test_settings.py`:

```python
"""B-5, §4.1: the academy's Stripe keys and fee; secrets are write-only."""

import pytest
from django.test import override_settings

from etqan.gateways import services
from etqan.gateways.tests.conftest import TEST_KEYS
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
URL = "/api/v1/gateways/settings/"


def test_the_admin_reads_the_settings_without_any_secret(api_for, online_on, stripe_on):
    body = api_for("admin").get(URL).json()
    assert body == {
        "stripe": {
            "enabled": True,
            "mode": "test",
            "public_key": "pk_test_demo",
            "has_secret": True,
            "has_webhook_secret": True,
            "webhook_url": body["stripe"]["webhook_url"],
            "events": [
                "checkout.session.completed",
                "checkout.session.async_payment_succeeded",
                "checkout.session.async_payment_failed",
                "checkout.session.expired",
            ],
            "currencies": sorted(services.STRIPE_CURRENCIES),
        },
        "fee": {"enabled": True, "basis_points": 500},
    }
    assert body["stripe"]["webhook_url"].endswith("/api/v1/gateways/webhooks/stripe/")
    # Review Focus 5: neither the key nor its token is ever sent back.
    text = str(body)
    assert "sk_test_demo" not in text
    assert "whsec_demo" not in text
    assert stripe_on.secret_enc not in text


def test_the_admin_saves_keys_and_the_fee(api_for, online_on):
    client = api_for("admin")
    resp = client.patch(
        URL, {"stripe": TEST_KEYS, "fee": {"enabled": False, "basis_points": 300}},
        format="json",
    )
    assert resp.status_code == 200
    assert resp.json()["stripe"]["enabled"] is True
    assert resp.json()["fee"] == {"enabled": False, "basis_points": 300}
    account = services.stripe_account()
    assert services.secret_of(account) == "sk_test_demo"
    assert services.webhook_secret_of(account) == "whsec_demo"
    assert "sk_test_demo" not in resp.content.decode()


def test_enabling_needs_every_key(api_for, online_on):
    resp = api_for("admin").patch(
        URL, {"stripe": {"enabled": True, "public_key": "pk_test_x"}}, format="json"
    )
    assert resp.status_code == 400
    assert "enabled" in resp.json()


@pytest.mark.parametrize(
    ("change", "field"),
    [
        ({"public_key": "pk_live_x"}, "public_key"),
        ({"secret": "sk_live_x"}, "secret"),
        ({"webhook_secret": "nope"}, "webhook_secret"),
        ({"mode": "live"}, "mode"),
    ],
)
def test_keys_must_match_the_mode(stripe_on, change, field):
    with pytest.raises(ValidationError) as refused:
        services.update_settings(stripe=change, by=None)
    assert refused.value.field == field
    # Review Focus 5: the message never repeats the key.
    assert "sk_live_x" not in refused.value.message


def test_an_empty_secret_clears_it_and_disables_the_account(stripe_on):
    services.update_settings(stripe={"secret": ""}, by=None)
    account = services.stripe_account()
    assert (account.secret_enc, account.enabled) == ("", False)


def test_the_fee_percentage_is_bounded(api_for, online_on):
    resp = api_for("admin").patch(
        URL, {"fee": {"basis_points": 2001}}, format="json"
    )
    assert resp.status_code == 400


@override_settings(ETQAN_SECRETS_KEY="", SECRETS_KEY_FROM_SECRET_KEY=False)
def test_saving_a_secret_without_a_key_is_503(api_for, online_on):
    resp = api_for("admin").patch(
        URL, {"stripe": {"secret": "sk_test_x"}}, format="json"
    )
    assert (resp.status_code, resp.json()["code"]) == (503, "gateways.no_key")


def test_feature_off_is_404_for_the_admin(api_for, set_features):
    set_features(online_payments=False)
    assert api_for("admin").get(URL).status_code == 404


def test_families_and_teachers_get_403(api_for, online_on):
    for role in ("parent", "student", "teacher"):
        assert api_for(role).get(URL).status_code == 403
```

In `backend/etqan/access/tests/test_routes.py`:
- `ROUTES`, after the finance rows:

```python
    # Phase B3, slice B3b.
    ("GET", "/api/v1/gateways/settings/", "gateway.view"),
    ("PATCH", "/api/v1/gateways/settings/", "gateway.update"),
```

- `FEATURES`, after the `"donations"` block:

```python
    # Phase B3, slice B3b.
    **dict.fromkeys(
        (
            ("GET", "/api/v1/gateways/settings/"),
            ("PATCH", "/api/v1/gateways/settings/"),
        ),
        "online_payments",
    ),
```

- `FEATURE_WORDS`, after `"/finance/summary/": "expenses",`: add `"/gateways/": "online_payments",`.

In `backend/etqan/access/tests/test_registry.py`: `== 24` becomes `== 25`.

- [ ] **Step 2: Run them to see them fail**

Run: `$DJ pytest etqan/gateways etqan/access -q`
Expected: failures. There is no `fee_for` and no route, and the registry count is off.

- [ ] **Step 3: Implement the fee rules**

`backend/etqan/gateways/services/fees.py`:

```python
"""What a family pays on top, and what a provider can take (B-6, B-7, plan
D5): the fee is the academy's percentage, half up, and only for purposes
that charge it; three-digit currencies go to Stripe in multiples of 10."""

from etqan.gateways.models import GatewayAccount
from etqan.gateways.models import GatewaySettings
from etqan.platform.currency import minor_digits

# [assumed] (spec B-6): the currencies Stripe Checkout takes for our academies.
STRIPE_CURRENCIES = frozenset(
    {
        "AED", "AUD", "BHD", "CAD", "CHF", "DKK", "EGP", "EUR", "GBP", "IDR",
        "INR", "JOD", "JPY", "KWD", "MAD", "MYR", "NOK", "NZD", "OMR", "PKR",
        "QAR", "SAR", "SEK", "SGD", "TND", "TRY", "USD", "ZAR",
    }
)
CURRENCIES = {GatewayAccount.Provider.STRIPE: STRIPE_CURRENCIES}


def fee_settings() -> GatewaySettings:
    return GatewaySettings.load()


def fee_for(
    amount_minor: int, currency: str, *, add_fee: bool, provider: str = "stripe"
) -> int | None:
    """The fee in minor units, or None when ``provider`` cannot take this
    amount in this currency."""
    if currency not in CURRENCIES.get(provider, frozenset()):
        return None
    settings_row = fee_settings()
    fee = 0
    if add_fee and settings_row.fee_enabled:
        fee = (amount_minor * settings_row.fee_basis_points + 5000) // 10000
    if minor_digits(currency) == 3:  # three-digit currencies
        remainder = (amount_minor + fee) % 10
        if remainder:
            if fee == 0:
                return None
            fee += 10 - remainder
    return fee


def providers_for(currency: str, amount_minor: int, *, add_fee: bool) -> list[str]:
    """The enabled providers that can take ``amount_minor`` in ``currency``."""
    enabled = GatewayAccount.objects.filter(enabled=True).values_list(
        "provider", flat=True
    )
    return [
        provider
        for provider in sorted(enabled)
        if fee_for(amount_minor, currency, add_fee=add_fee, provider=provider)
        is not None
    ]
```


- [ ] **Step 4: Implement the accounts**

`backend/etqan/gateways/services/accounts.py`:

```python
"""The academy's own Stripe account (B-5) and the fee settings (B-7).
Secrets are Fernet tokens (etqan.platform.secrets); nothing here returns
them except to the provider that uses them."""

from django.db import transaction

from etqan.gateways.models import GatewayAccount
from etqan.gateways.models import GatewaySettings
from etqan.platform import secrets
from etqan.platform.exceptions import ValidationError

STRIPE = GatewayAccount.Provider.STRIPE
# B-5: a key's prefix says which mode it belongs to.
PREFIXES = {
    "test": {"public_key": ("pk_test_",), "secret": ("sk_test_", "rk_test_")},
    "live": {"public_key": ("pk_live_",), "secret": ("sk_live_", "rk_live_")},
}
WEBHOOK_PREFIX = "whsec_"
STRIPE_FIELDS = ("enabled", "mode", "public_key", "secret", "webhook_secret")


def stripe_account() -> GatewayAccount:
    account, _ = GatewayAccount.objects.get_or_create(provider=STRIPE)
    return account


def secret_of(account: GatewayAccount) -> str:
    return secrets.decrypt(account.secret_enc) if account.secret_enc else ""


def webhook_secret_of(account: GatewayAccount) -> str:
    return (
        secrets.decrypt(account.webhook_secret_enc)
        if account.webhook_secret_enc
        else ""
    )


def _check_prefix(field: str, value: str, mode: str) -> None:
    if value and not value.startswith(PREFIXES[mode][field]):
        raise ValidationError(
            f"This key does not belong to a {mode}-mode Stripe account.", field=field
        )


def _apply_stripe(account: GatewayAccount, change: dict) -> None:
    mode = change.get("mode", account.mode)
    if "mode" in change and change["mode"] != account.mode:
        # Stored keys must belong to the new mode too.
        try:
            _check_prefix("public_key", account.public_key, mode)
            _check_prefix("secret", secret_of(account), mode)
        except ValidationError:
            raise ValidationError(
                "Enter keys for this mode first.", field="mode"
            ) from None
    account.mode = mode
    if "public_key" in change:
        _check_prefix("public_key", change["public_key"], mode)
        account.public_key = change["public_key"]
    if "secret" in change:
        _check_prefix("secret", change["secret"], mode)
        account.secret_enc = secrets.encrypt(change["secret"]) if change["secret"] else ""
    if "webhook_secret" in change:
        value = change["webhook_secret"]
        if value and not value.startswith(WEBHOOK_PREFIX):
            raise ValidationError(
                "This is not a Stripe signing secret.", field="webhook_secret"
            )
        account.webhook_secret_enc = secrets.encrypt(value) if value else ""
    complete = account.public_key and account.secret_enc and account.webhook_secret_enc
    if change.get("enabled") and not complete:
        raise ValidationError(
            "Enter the keys and the signing secret first.", field="enabled"
        )
    if "enabled" in change:
        account.enabled = bool(change["enabled"])
    if not complete:
        account.enabled = False


@transaction.atomic
def update_settings(*, stripe: dict | None = None, fee: dict | None = None, by) -> None:
    """§4.1: any of the Stripe fields and the fee. A secret is write-only and
    "" clears it (which disables the account)."""
    if stripe is not None:
        account = GatewayAccount.objects.select_for_update().get(pk=stripe_account().pk)
        _apply_stripe(account, {k: v for k, v in stripe.items() if k in STRIPE_FIELDS})
        account.updated_by = by
        account.save()
    if fee is not None:
        settings_row = GatewaySettings.load()
        if "enabled" in fee:
            settings_row.fee_enabled = bool(fee["enabled"])
        if "basis_points" in fee:
            settings_row.fee_basis_points = fee["basis_points"]
        settings_row.full_clean()
        settings_row.save()
```

`backend/etqan/gateways/services/__init__.py`:

```python
"""Public API of the gateways module. Other apps import only this package."""

from etqan.gateways.services.accounts import secret_of
from etqan.gateways.services.accounts import stripe_account
from etqan.gateways.services.accounts import update_settings
from etqan.gateways.services.accounts import webhook_secret_of
from etqan.gateways.services.fees import STRIPE_CURRENCIES
from etqan.gateways.services.fees import fee_for
from etqan.gateways.services.fees import fee_settings
from etqan.gateways.services.fees import providers_for

__all__ = [
    "STRIPE_CURRENCIES",
    "fee_for",
    "fee_settings",
    "providers_for",
    "secret_of",
    "stripe_account",
    "update_settings",
    "webhook_secret_of",
]
```

- [ ] **Step 5: Implement the settings API**

`backend/etqan/gateways/api/serializers.py`:

```python
"""Request bodies (B3b §5). Responses are built in `payloads`."""

from rest_framework import serializers

from etqan.gateways.models import GatewayAccount


class StripeInput(serializers.Serializer):
    enabled = serializers.BooleanField(required=False)
    mode = serializers.ChoiceField(choices=GatewayAccount.Mode.choices, required=False)
    public_key = serializers.CharField(max_length=200, required=False, allow_blank=True)
    secret = serializers.CharField(
        max_length=255, required=False, allow_blank=True, write_only=True
    )
    webhook_secret = serializers.CharField(
        max_length=255, required=False, allow_blank=True, write_only=True
    )


class FeeInput(serializers.Serializer):
    enabled = serializers.BooleanField(required=False)
    basis_points = serializers.IntegerField(min_value=0, max_value=2000, required=False)


class SettingsInput(serializers.Serializer):
    stripe = StripeInput(required=False)
    fee = FeeInput(required=False)
```

`backend/etqan/gateways/api/payloads.py`:

```python
"""JSON shapes for gateways (B3b §4). Secrets never appear: only whether
one is set (B-5, Review Focus 5)."""

from etqan.gateways import services
from etqan.platform.frontend import frontend_url

STRIPE_EVENTS = (
    "checkout.session.completed",
    "checkout.session.async_payment_succeeded",
    "checkout.session.async_payment_failed",
    "checkout.session.expired",
)


def settings_payload() -> dict:
    account = services.stripe_account()
    fee = services.fee_settings()
    return {
        "stripe": {
            "enabled": account.enabled,
            "mode": account.mode,
            "public_key": account.public_key,
            "has_secret": bool(account.secret_enc),
            "has_webhook_secret": bool(account.webhook_secret_enc),
            "webhook_url": f"{frontend_url()}/api/v1/gateways/webhooks/stripe/",
            "events": list(STRIPE_EVENTS),
            "currencies": sorted(services.STRIPE_CURRENCIES),
        },
        "fee": {"enabled": fee.fee_enabled, "basis_points": fee.fee_basis_points},
    }
```

`backend/etqan/gateways/api/views.py`:

```python
"""Gateways endpoints (B3b §5). Thin: parse, call one service, answer."""

from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.gateways import services
from etqan.gateways.api import payloads
from etqan.gateways.api.serializers import SettingsInput
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode


class SettingsView(APIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "online_payments"
    permission_codes = {"GET": "gateway.view", "PATCH": "gateway.update"}

    def get(self, request):
        return Response(payloads.settings_payload())

    def patch(self, request):
        body = SettingsInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.update_settings(**body.validated_data, by=request.user)
        return Response(payloads.settings_payload())
```

`backend/etqan/gateways/api/urls.py`:

```python
from django.urls import path

from etqan.gateways.api import views

app_name = "gateways"
urlpatterns = [
    path("settings/", views.SettingsView.as_view(), name="settings"),
]
```

`backend/config/api_router.py`, after the finance path (under the B3 marker):

```python
    # settings/, checkouts/, webhooks/, simulate/ (B3b spec §5).
    path("gateways/", include("etqan.gateways.api.urls")),
```

`backend/etqan/access/registry.py`, under the B3 marker, after the finance resources:

```python
    # B3b: the academy's Stripe keys and fee.
    Resource("gateway", "Payment gateways", "بوابات الدفع", ("view", "update")),
```

- [ ] **Step 6: Run the tests**

Run: `$DJ pytest etqan/gateways etqan/access etqan/platform -q`
Expected: all pass.

- [ ] **Step 7: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/gateways etqan/access config/api_router.py
git -C backend commit -m "feat(gateways): the academy's Stripe keys, the fee and the settings API"
```

---
### Task 5: The provider interface, Stripe over httpx, and the simulator provider

**Files:**
- Create: `backend/etqan/gateways/providers/__init__.py`, `base.py`, `stripe.py`, `simulator.py`
- Test: `backend/etqan/gateways/tests/test_providers.py`

**Interfaces:**
- Consumes: `GatewayAccount`, `Checkout` (Task 2); `secret_of` (Task 4); `etqan.platform.frontend.app_url`.
- Produces (used only inside gateways):
  - `providers.base.Session(ref: str, url: str)`, a frozen dataclass
  - `providers.base.ProviderError(reason: str)`, where `reason` is `"amount_too_small"` or `"error"`
  - `providers.provider_for(account, *, simulate: bool)`, which returns an object with
    - `create(account, checkout, *, success_url: str, cancel_url: str) -> Session`
    - `expire(account, ref: str) -> None`
  - `providers.stripe.API = "https://api.stripe.com/v1"` and `STRIPE_VERSION = "2024-06-20"`

- [ ] **Step 1: Write the failing tests**

`backend/etqan/gateways/tests/test_providers.py`:

```python
"""B-3, D14, D15: Checkout Sessions over Stripe's REST API, and the
simulator that stands in for it. Stripe is never really called in tests:
respx answers."""

import logging
from urllib.parse import parse_qs

import httpx
import pytest

from etqan.gateways.models import Checkout
from etqan.gateways.providers import provider_for
from etqan.gateways.providers.base import ProviderError
from etqan.gateways.providers.stripe import API
from etqan.gateways.providers.stripe import STRIPE_VERSION

pytestmark = pytest.mark.django_db
SESSIONS = f"{API}/checkout/sessions"


def a_checkout(**overrides):
    fields = {
        "purpose": "invoice",
        "reference_id": 7,
        "provider": "stripe",
        "amount_minor": 50000,
        "fee_minor": 2500,
        "currency": "EGP",
        "description": "INV-000007",
        **overrides,
    }
    return Checkout.objects.create(**fields)


def create(stripe_on, checkout):
    return provider_for(stripe_on, simulate=False).create(
        stripe_on, checkout, success_url="https://a/ok", cancel_url="https://a/no"
    )


def test_a_session_has_two_line_items_and_the_checkout_id_everywhere(
    stripe_on, respx_mock
):
    route = respx_mock.post(SESSIONS).mock(
        return_value=httpx.Response(
            200, json={"id": "cs_test_1", "url": "https://checkout.stripe.com/c/1"}
        )
    )
    checkout = a_checkout()
    session = create(stripe_on, checkout)
    assert (session.ref, session.url) == ("cs_test_1", "https://checkout.stripe.com/c/1")
    request = route.calls.last.request
    assert request.headers["Idempotency-Key"] == str(checkout.pk)
    assert request.headers["Stripe-Version"] == STRIPE_VERSION
    assert request.headers["Authorization"].startswith("Basic ")
    form = {key: values[0] for key, values in parse_qs(request.content.decode()).items()}
    assert form["mode"] == "payment"
    assert form["client_reference_id"] == str(checkout.pk)
    assert form["metadata[checkout]"] == str(checkout.pk)
    assert form["payment_intent_data[metadata][checkout]"] == str(checkout.pk)
    assert form["success_url"] == "https://a/ok"
    assert form["cancel_url"] == "https://a/no"
    assert form["line_items[0][price_data][currency]"] == "egp"
    assert form["line_items[0][price_data][unit_amount]"] == "50000"
    assert form["line_items[0][price_data][product_data][name]"] == "INV-000007"
    assert form["line_items[0][quantity]"] == "1"
    assert form["line_items[1][price_data][unit_amount]"] == "2500"
    assert form["line_items[1][price_data][product_data][name]"] == "Service fee"


def test_no_fee_line_when_the_fee_is_zero(stripe_on, respx_mock):
    route = respx_mock.post(SESSIONS).mock(
        return_value=httpx.Response(200, json={"id": "cs_2", "url": "https://s/2"})
    )
    create(stripe_on, a_checkout(fee_minor=0))
    assert "line_items[1]" not in route.calls.last.request.content.decode()


def test_amount_too_small_is_its_own_reason(stripe_on, respx_mock):
    respx_mock.post(SESSIONS).mock(
        return_value=httpx.Response(
            400, json={"error": {"code": "amount_too_small", "message": "Too small"}}
        )
    )
    with pytest.raises(ProviderError) as refused:
        create(stripe_on, a_checkout())
    assert refused.value.reason == "amount_too_small"


@pytest.mark.parametrize(
    "answer",
    [
        httpx.Response(500, json={"error": {"type": "api_error"}}),
        httpx.Response(401, json={"error": {"type": "invalid_request_error"}}),
        httpx.ConnectError("down"),
    ],
)
def test_any_other_failure_is_an_error_and_no_key_is_logged(
    stripe_on, respx_mock, caplog, answer
):
    respx_mock.post(SESSIONS).mock(side_effect=[answer])
    caplog.set_level(logging.INFO)
    with pytest.raises(ProviderError) as refused:
        create(stripe_on, a_checkout())
    assert refused.value.reason == "error"
    # Review Focus 5
    assert "sk_test_demo" not in caplog.text


def test_expire_posts_to_the_session(stripe_on, respx_mock):
    route = respx_mock.post(f"{SESSIONS}/cs_9/expire").mock(
        return_value=httpx.Response(200, json={"id": "cs_9", "status": "expired"})
    )
    provider_for(stripe_on, simulate=False).expire(stripe_on, "cs_9")
    assert route.called


def test_the_simulator_never_calls_stripe(stripe_on, respx_mock):
    checkout = a_checkout()
    session = provider_for(stripe_on, simulate=True).create(
        stripe_on, checkout, success_url="https://a/ok", cancel_url="https://a/no"
    )
    assert session.ref.startswith("cs_sim_")
    assert session.url.endswith(f"/app/pay/simulate/{checkout.pk}")
    provider_for(stripe_on, simulate=True).expire(stripe_on, session.ref)
    assert not respx_mock.calls
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DJ pytest etqan/gateways/tests/test_providers.py -q`
Expected: collection error (no `etqan.gateways.providers`).

- [ ] **Step 3: Implement**

`backend/etqan/gateways/providers/base.py`:

```python
"""The one provider interface (B-2): create a hosted checkout, expire one."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Session:
    ref: str
    url: str


class ProviderError(Exception):
    """The provider refused or failed. ``reason`` is `amount_too_small` or
    `error`; the provider's own words stay in the server log (never in an
    answer to the family)."""

    def __init__(self, reason: str = "error"):
        self.reason = reason
        super().__init__(reason)
```

`backend/etqan/gateways/providers/stripe.py`:

```python
"""Stripe Checkout over the REST API (B-3, plan D15). Form-encoded bodies,
Basic auth with the academy's secret key, a pinned API version and an
idempotency key per checkout. Errors are logged by Stripe's code only: never
a key, never the request."""

import logging

import httpx

from etqan.gateways.providers.base import ProviderError
from etqan.gateways.providers.base import Session
from etqan.gateways.services.accounts import secret_of

API = "https://api.stripe.com/v1"
STRIPE_VERSION = "2024-06-20"
TIMEOUT = 20.0
FEE_LINE = "Service fee"
logger = logging.getLogger(__name__)


def _line(index: int, *, name: str, amount: int, currency: str) -> list[tuple]:
    prefix = f"line_items[{index}]"
    return [
        (f"{prefix}[price_data][currency]", currency.lower()),
        (f"{prefix}[price_data][unit_amount]", str(amount)),
        (f"{prefix}[price_data][product_data][name]", name),
        (f"{prefix}[quantity]", "1"),
    ]


class StripeProvider:
    def _post(self, account, path: str, data: list[tuple], *, idempotency: str = ""):
        headers = {"Stripe-Version": STRIPE_VERSION}
        if idempotency:
            headers["Idempotency-Key"] = idempotency
        try:
            response = httpx.post(
                f"{API}{path}",
                data=data,
                auth=(secret_of(account), ""),
                headers=headers,
                timeout=TIMEOUT,
            )
        except httpx.HTTPError as exc:
            logger.warning("Stripe unreachable: %s", type(exc).__name__)
            raise ProviderError("error") from None
        if response.is_success:
            return response.json()
        error = (response.json() if response.content else {}).get("error", {})
        logger.warning(
            "Stripe refused %s: %s %s %s",
            path,
            response.status_code,
            error.get("type", ""),
            error.get("code", ""),
        )
        reason = "amount_too_small" if error.get("code") == "amount_too_small" else "error"
        raise ProviderError(reason)

    def create(self, account, checkout, *, success_url: str, cancel_url: str) -> Session:
        ref = str(checkout.pk)
        data = [
            ("mode", "payment"),
            ("success_url", success_url),
            ("cancel_url", cancel_url),
            ("client_reference_id", ref),
            ("metadata[checkout]", ref),
            ("payment_intent_data[metadata][checkout]", ref),
            *_line(
                0,
                name=checkout.description or ref,
                amount=checkout.amount_minor,
                currency=checkout.currency,
            ),
        ]
        if checkout.fee_minor > 0:
            data += _line(
                1, name=FEE_LINE, amount=checkout.fee_minor, currency=checkout.currency
            )
        body = self._post(account, "/checkout/sessions", data, idempotency=ref)
        return Session(ref=body["id"], url=body["url"])

    def expire(self, account, ref: str) -> None:
        self._post(account, f"/checkout/sessions/{ref}/expire", [])
```

`backend/etqan/gateways/providers/simulator.py`:

```python
"""B-12: a test-mode checkout's provider while GATEWAYS_SIMULATE is on.
Nothing leaves the server; a dashboard page plays the hosted checkout and
posts the outcome (services.simulator)."""

import uuid

from etqan.gateways.providers.base import Session
from etqan.platform.frontend import app_url


class SimulatorProvider:
    def create(self, account, checkout, *, success_url: str, cancel_url: str) -> Session:
        return Session(
            ref=f"cs_sim_{uuid.uuid4().hex}",
            url=app_url(f"/pay/simulate/{checkout.pk}"),
        )

    def expire(self, account, ref: str) -> None:
        return None
```

`backend/etqan/gateways/providers/__init__.py`:

```python
"""Providers (B-2). Stripe in B3b; B3c adds PayPal here."""

from etqan.gateways.providers.simulator import SimulatorProvider
from etqan.gateways.providers.stripe import StripeProvider


def provider_for(account, *, simulate: bool):
    return SimulatorProvider() if simulate else StripeProvider()
```

- [ ] **Step 4: Run the tests**

Run: `$DJ pytest etqan/gateways -q`
Expected: all pass. `respx_mock` is respx's pytest fixture; it fails a test that makes an unmocked request.

- [ ] **Step 5: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/gateways
git -C backend commit -m "feat(gateways): Stripe Checkout over httpx and the offline simulator provider"
```

---
### Task 6: Purposes, `start_checkout`, the invoice purpose and Pay-online options

**Files:**
- Create: `backend/etqan/gateways/services/purposes.py`, `backend/etqan/gateways/services/checkouts.py`
- Modify: `backend/etqan/gateways/services/__init__.py`
- Modify: `backend/etqan/gateways/api/serializers.py`, `views.py`, `urls.py`, `payloads.py`
- Create: `backend/etqan/billing/services/online.py`
- Modify: `backend/etqan/billing/apps.py`, `backend/etqan/billing/services/__init__.py`
- Modify: `backend/etqan/billing/api/payloads.py`, `backend/etqan/billing/api/views.py` (`can_pay_online`)
- Modify: `backend/etqan/access/tests/test_routes.py` (a `SELF_SERVICE` entry)
- Test: `backend/etqan/gateways/tests/test_checkouts.py`, `backend/etqan/billing/tests/test_online.py`

**Interfaces:**
- Consumes: `fee_for`, `providers_for`, `stripe_account` (Task 4); `provider_for`, `ProviderError` (Task 5); `record_online_payment`, `rules` (Task 3).
- Produces, all exported from `etqan.gateways.services`:
  - `Prepared(amount_minor: int, currency: str, description: str, add_fee: bool)`, frozen
  - `Applied(ok: bool, reason: str = "")`, frozen
  - `CompletedCheckout(id, purpose, reference_id, provider, amount_minor, fee_minor, currency, transaction_number, completed_at)`, frozen
  - `register_purpose(name: str, *, prepare, complete) -> None`
  - `purpose_named(name: str) -> Purpose | None`
  - `StartedCheckout(id: uuid.UUID, redirect_url: str, amount_minor: int, fee_minor: int, currency: str)`, frozen
  - `start_checkout(purpose: str, reference_id: int, provider: str, *, user, params: dict | None = None) -> StartedCheckout`
- Also produces:
  - `billing.services.online.pay_options(invoice) -> list[str]`, exported as `billing.services.pay_options`;
  - `register()`, called from `BillingConfig.ready()`.
- Route: `POST /api/v1/gateways/checkouts/start/` (plan D1), answering 201 with `{id, redirect_url, amount_minor, fee_minor, currency}`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/gateways/tests/test_checkouts.py`:

```python
"""B3b §4.2, B-8: starting a checkout for an invoice: scope, nothing due,
currency, reuse and supersede, provider errors."""

from urllib.parse import parse_qs

import httpx
import pytest
from django.test import override_settings
from rest_framework.test import APIClient

from etqan.billing import services as billing_services
from etqan.gateways import services
from etqan.gateways.models import Checkout
from etqan.gateways.providers.stripe import API

pytestmark = pytest.mark.django_db
URL = "/api/v1/gateways/checkouts/start/"
SESSIONS = f"{API}/checkout/sessions"


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


def start(client, invoice, provider="stripe"):
    return client.post(
        URL,
        {"purpose": "invoice", "reference_id": invoice.pk, "provider": provider},
        format="json",
    )


@pytest.fixture
def family(online_on, stripe_on, parent_of_world, invoice):
    """Zainab pays Yusuf's 500.00 EGP invoice."""
    return parent_of_world, invoice()


def test_the_payer_starts_a_simulated_checkout_for_the_balance_plus_fee(family):
    parent, bill = family
    resp = start(as_user(parent), bill)
    assert resp.status_code == 201
    body = resp.json()
    assert (body["amount_minor"], body["fee_minor"], body["currency"]) == (50000, 2500, "EGP")
    assert body["redirect_url"].endswith(f"/app/pay/simulate/{body['id']}")
    checkout = Checkout.objects.get(pk=body["id"])
    assert (checkout.purpose, checkout.reference_id, checkout.simulated) == (
        "invoice", bill.pk, True,
    )
    assert checkout.provider_ref.startswith("cs_sim_")
    assert (checkout.created_by, checkout.description) == (parent, bill.number)


def test_the_balance_not_the_amount_is_paid(family, admin):
    parent, bill = family
    billing_services.add_payment(
        bill, amount_minor=20000, method="cash", paid_on=bill.issued_on, by=admin
    )
    body = start(as_user(parent), bill).json()
    assert (body["amount_minor"], body["fee_minor"]) == (30000, 1500)


def test_starting_again_reuses_the_pending_checkout(family):
    parent, bill = family
    first = start(as_user(parent), bill).json()
    second = start(as_user(parent), bill).json()
    assert second["id"] == first["id"]
    assert second["redirect_url"] == first["redirect_url"]
    assert Checkout.objects.count() == 1


def test_a_changed_amount_supersedes_the_pending_checkout(family, admin):
    parent, bill = family
    first = start(as_user(parent), bill).json()
    billing_services.add_payment(
        bill, amount_minor=10000, method="cash", paid_on=bill.issued_on, by=admin
    )
    second = start(as_user(parent), bill).json()
    assert second["id"] != first["id"]
    assert Checkout.objects.get(pk=first["id"]).status == "cancelled"
    assert Checkout.objects.get(pk=second["id"]).status == "pending"


@override_settings(GATEWAYS_SIMULATE=False)
def test_a_real_test_mode_checkout_calls_stripe_and_supersede_expires_it(
    family, admin, respx_mock
):
    parent, bill = family
    created = respx_mock.post(SESSIONS).mock(
        side_effect=[
            httpx.Response(200, json={"id": "cs_test_a", "url": "https://stripe.test/a"}),
            httpx.Response(200, json={"id": "cs_test_b", "url": "https://stripe.test/b"}),
        ]
    )
    expired = respx_mock.post(f"{SESSIONS}/cs_test_a/expire").mock(
        return_value=httpx.Response(200, json={"id": "cs_test_a"})
    )
    first = start(as_user(parent), bill).json()
    assert first["redirect_url"] == "https://stripe.test/a"
    form = parse_qs(created.calls.last.request.content.decode())
    assert form["success_url"][0].endswith(f"/app/pay/return?checkout={first['id']}")
    billing_services.add_payment(
        bill, amount_minor=10000, method="cash", paid_on=bill.issued_on, by=admin
    )
    second = start(as_user(parent), bill).json()
    assert second["redirect_url"] == "https://stripe.test/b"
    assert expired.called


@override_settings(GATEWAYS_SIMULATE=False)
def test_a_provider_failure_is_502_and_the_checkout_failed(family, respx_mock):
    parent, bill = family
    respx_mock.post(SESSIONS).mock(return_value=httpx.Response(500, json={}))
    resp = start(as_user(parent), bill)
    assert resp.status_code == 502
    assert "sk_test" not in resp.content.decode()
    assert Checkout.objects.get().status == "failed"


@override_settings(GATEWAYS_SIMULATE=False)
def test_too_small_for_stripe_is_a_400(family, respx_mock):
    parent, bill = family
    respx_mock.post(SESSIONS).mock(
        return_value=httpx.Response(400, json={"error": {"code": "amount_too_small"}})
    )
    resp = start(as_user(parent), bill)
    assert resp.status_code == 400
    assert "amount_minor" in resp.json()


def test_nothing_due_is_409(family, admin):
    parent, bill = family
    billing_services.add_payment(
        bill, amount_minor=50000, method="cash", paid_on=bill.issued_on, by=admin
    )
    resp = start(as_user(parent), bill)
    assert (resp.status_code, resp.json()["code"]) == (409, "gateways.nothing_due")


def test_a_void_invoice_is_409(online_on, stripe_on, invoice, api_for, admin):
    bill = invoice()
    billing_services.void_invoice(bill, by=admin)
    resp = start(api_for("admin"), bill)
    assert (resp.status_code, resp.json()["code"]) == (409, "gateways.nothing_due")


def test_who_may_start(family, api_for, staff_for):
    _, bill = family
    assert start(api_for("parent"), bill).status_code == 404  # another family
    assert start(api_for("teacher"), bill).status_code == 404
    assert start(staff_for(), bill).status_code == 404
    assert start(staff_for("invoice.view"), bill).status_code == 201
    assert start(api_for("admin"), bill).status_code == 201
    assert start(APIClient(), bill).status_code == 403


def test_a_currency_or_provider_stripe_cannot_take_is_400(online_on, stripe_on, invoice, api_for):
    bill = invoice(currency="XYZ")
    resp = start(api_for("admin"), bill)
    assert (resp.status_code, list(resp.json())) == (400, ["provider"])
    services.update_settings(stripe={"enabled": False}, by=None)
    resp = start(api_for("admin"), invoice())
    assert (resp.status_code, list(resp.json())) == (400, ["provider"])


def test_an_unknown_purpose_is_400(online_on, stripe_on, api_for):
    resp = api_for("admin").post(
        URL, {"purpose": "nope", "reference_id": 1, "provider": "stripe"}, format="json"
    )
    assert (resp.status_code, list(resp.json())) == (400, ["purpose"])


def test_the_feature_off_is_404(family, set_features):
    parent, bill = family
    set_features(online_payments=False)
    assert start(as_user(parent), bill).status_code == 404
```

`backend/etqan/billing/tests/test_online.py`:

```python
"""B3b §4.3, D12: billing's `invoice` purpose and the Pay-online options."""

import uuid
from datetime import datetime
from datetime import UTC

import pytest

from etqan.billing import services
from etqan.billing.models import Payment
from etqan.billing.services import online
from etqan.billing.tests.test_invoices import invoice_for
from etqan.billing.tests.test_invoices import pay
from etqan.gateways import services as gateways_services
from etqan.gateways.tests.conftest import TEST_KEYS

pytestmark = pytest.mark.django_db


def done(invoice, amount, *, fee=0, ref="pi_1", currency="EGP"):
    return gateways_services.CompletedCheckout(
        id=uuid.uuid4(),
        purpose="invoice",
        reference_id=invoice.pk,
        provider="stripe",
        amount_minor=amount,
        fee_minor=fee,
        currency=currency,
        transaction_number=ref,
        completed_at=datetime(2026, 6, 1, 8, tzinfo=UTC),
    )


def test_the_invoice_purpose_is_registered():
    assert gateways_services.purpose_named("invoice") is not None


def test_complete_records_the_payment(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000, currency="EGP")
    applied = online.complete(done(bill, 1000, fee=50))
    assert applied == gateways_services.Applied(ok=True)
    payment = Payment.objects.get(invoice=bill)
    assert (payment.amount_minor, payment.fee_minor, payment.method) == (1000, 50, "stripe")


@pytest.mark.parametrize(
    ("setup", "amount", "currency", "reason"),
    [
        ("void", 1000, "EGP", "invoice_void"),
        ("paid", 1000, "EGP", "balance_below_amount"),
        ("none", 1001, "EGP", "balance_below_amount"),
        ("none", 1000, "USD", "currency_mismatch"),
    ],
)
def test_money_it_cannot_take_is_not_applied(world, admin, setup, amount, currency, reason):
    bill = invoice_for(world, admin, amount_minor=1000, currency="EGP")
    if setup == "void":
        services.void_invoice(bill, by=admin)
    if setup == "paid":
        pay(bill, admin, 1000)
    applied = online.complete(done(bill, amount, currency=currency))
    assert applied == gateways_services.Applied(ok=False, reason=reason)
    assert not Payment.objects.filter(invoice=bill, method="stripe").exists()


def test_a_transaction_already_recorded_is_not_applied_twice(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000, currency="EGP")
    online.complete(done(bill, 400, ref="pi_x"))
    again = online.complete(done(bill, 400, ref="pi_x"))
    assert again == gateways_services.Applied(ok=False, reason="already_recorded")


def test_pay_options(world, admin, set_features):
    bill = invoice_for(world, admin, amount_minor=1000, currency="EGP")
    set_features(invoices=True, online_payments=True)
    assert services.pay_options(services.invoices_queryset().get(pk=bill.pk)) == []
    gateways_services.update_settings(stripe=TEST_KEYS, by=None)
    fresh = services.invoices_queryset().get(pk=bill.pk)
    assert services.pay_options(fresh) == ["stripe"]
    set_features(online_payments=False)
    assert services.pay_options(fresh) == []
    set_features(online_payments=True)
    pay(bill, admin, 1000)
    assert services.pay_options(services.invoices_queryset().get(pk=bill.pk)) == []


def test_the_invoice_detail_carries_can_pay_online(api_for, world, admin, set_features):
    set_features(invoices=True, online_payments=True)
    gateways_services.update_settings(stripe=TEST_KEYS, by=None)
    bill = invoice_for(world, admin, amount_minor=1000, currency="EGP")
    body = api_for("admin").get(f"/api/v1/billing/invoices/{bill.pk}/").json()
    assert body["can_pay_online"] == ["stripe"]
```

In `backend/etqan/access/tests/test_routes.py`, `SELF_SERVICE`, after the site entries:

```python
    # Phase B3, slice B3b (plan D2): each checks its caller itself.
    "etqan.gateways.api.views.StartCheckoutView": (
        "a family starts paying what it can read; the purpose scopes it"
    ),
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DJ pytest etqan/gateways/tests/test_checkouts.py etqan/billing/tests/test_online.py etqan/access/tests/test_routes.py -q`
Expected: failures and collection errors (`start_checkout`, `online`, the route).

- [ ] **Step 3: Implement the purposes**

`backend/etqan/gateways/services/purposes.py`:

```python
"""What a checkout pays for (B-1, ledger D4/D13). The selling app registers
a purpose in its AppConfig.ready(): `prepare` prices it for a caller (or
refuses: NotFoundError, ConflictError), `complete` takes the money once a
verified event says it was paid. Gateways never imports the selling app."""

import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class Prepared:
    amount_minor: int
    currency: str
    description: str
    # Eligible for the academy's service fee (plan D6).
    add_fee: bool


@dataclass(frozen=True)
class Applied:
    ok: bool
    # A short code when not ok (plan D8).
    reason: str = ""


@dataclass(frozen=True)
class CompletedCheckout:
    id: uuid.UUID
    purpose: str
    reference_id: int
    provider: str
    amount_minor: int
    fee_minor: int
    currency: str
    transaction_number: str
    completed_at: datetime


@dataclass(frozen=True)
class Purpose:
    prepare: Callable[[int, object, dict | None], Prepared]
    complete: Callable[[CompletedCheckout], Applied]


_PURPOSES: dict[str, Purpose] = {}


def register_purpose(name: str, *, prepare, complete) -> None:
    _PURPOSES[name] = Purpose(prepare=prepare, complete=complete)


def purpose_named(name: str) -> Purpose | None:
    return _PURPOSES.get(name)
```

- [ ] **Step 4: Implement `start_checkout`**

`backend/etqan/gateways/services/checkouts.py`:

```python
"""Starting a checkout (B3b §4.2, B-8). The pending row is committed before
the provider is called, and the provider is never called under a row lock
(plan D9): the callers' views are non-atomic."""

import logging
import uuid
from dataclasses import dataclass

from django.conf import settings
from django.db import transaction

from etqan.gateways.models import Checkout
from etqan.gateways.models import GatewayAccount
from etqan.gateways.providers import provider_for
from etqan.gateways.providers.base import ProviderError
from etqan.gateways.services import fees
from etqan.gateways.services.purposes import purpose_named
from etqan.platform.exceptions import ExternalServiceError
from etqan.platform.exceptions import ValidationError
from etqan.platform.frontend import app_url

PENDING = Checkout.Status.PENDING
logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class StartedCheckout:
    id: uuid.UUID
    redirect_url: str
    amount_minor: int
    fee_minor: int
    currency: str


def _started(checkout: Checkout) -> StartedCheckout:
    return StartedCheckout(
        id=checkout.pk,
        redirect_url=checkout.redirect_url,
        amount_minor=checkout.amount_minor,
        fee_minor=checkout.fee_minor,
        currency=checkout.currency,
    )


def _account(provider: str) -> GatewayAccount:
    account = GatewayAccount.objects.filter(provider=provider, enabled=True).first()
    if account is None:
        raise ValidationError("This payment method is not available.", field="provider")
    return account


def start_checkout(  # noqa: PLR0913 -- keyword-only after the three ids (ledger D13)
    purpose: str,
    reference_id: int,
    provider: str,
    *,
    user,
    params: dict | None = None,
) -> StartedCheckout:
    handler = purpose_named(purpose)
    if handler is None:
        raise ValidationError("Unknown purpose.", field="purpose")
    account = _account(provider)
    prepared = handler.prepare(reference_id, user, params)
    fee = fees.fee_for(
        prepared.amount_minor, prepared.currency, add_fee=prepared.add_fee, provider=provider
    )
    if fee is None:
        raise ValidationError(
            "This payment method cannot take this amount.", field="provider"
        )
    simulate = settings.GATEWAYS_SIMULATE and account.mode == GatewayAccount.Mode.TEST
    with transaction.atomic():
        pending = list(
            Checkout.objects.select_for_update().filter(
                purpose=purpose, reference_id=reference_id, provider=provider, status=PENDING
            )
        )
        for old in pending:
            same = (old.amount_minor, old.fee_minor, old.simulated) == (
                prepared.amount_minor, fee, simulate,
            )
            if same and old.redirect_url:
                return _started(old)
        for old in pending:
            old.status = Checkout.Status.CANCELLED
            old.save(update_fields=["status"])
        checkout = Checkout.objects.create(
            purpose=purpose,
            reference_id=reference_id,
            provider=provider,
            simulated=simulate,
            amount_minor=prepared.amount_minor,
            fee_minor=fee,
            currency=prepared.currency,
            description=prepared.description[:200],
            created_by=user,
        )
    client = provider_for(account, simulate=simulate)
    for old in pending:
        if old.provider_ref and old.simulated == simulate:
            try:
                client.expire(account, old.provider_ref)
            except ProviderError:
                logger.warning("Could not expire superseded checkout %s", old.pk)
    back = app_url(f"/pay/return?checkout={checkout.pk}")
    try:
        session = client.create(account, checkout, success_url=back, cancel_url=back)
    except ProviderError as exc:
        Checkout.objects.filter(pk=checkout.pk, status=PENDING).update(
            status=Checkout.Status.FAILED
        )
        if exc.reason == "amount_too_small":
            raise ValidationError(
                "This amount is too small to pay online.", field="amount_minor"
            ) from None
        raise ExternalServiceError("payment") from None
    # Review Focus 1: only the provider's fields; a webhook may already have
    # completed this checkout, and its status must stay as it is.
    Checkout.objects.filter(pk=checkout.pk).update(
        provider_ref=session.ref, redirect_url=session.url
    )
    checkout.redirect_url = session.url
    return _started(checkout)
```

`backend/etqan/gateways/services/__init__.py`: add these imports and `__all__` entries (alphabetical):
- from `checkouts`: `StartedCheckout`, `start_checkout`;
- from `purposes`: `Applied`, `CompletedCheckout`, `Prepared`, `purpose_named`, `register_purpose`.

- [ ] **Step 5: Implement the start route**

`backend/etqan/gateways/api/serializers.py`, append:

```python
class StartInput(serializers.Serializer):
    purpose = serializers.CharField(max_length=40)
    reference_id = serializers.IntegerField(min_value=1)
    provider = serializers.ChoiceField(choices=GatewayAccount.Provider.choices)
```

`backend/etqan/gateways/api/payloads.py`, append:

```python
def started(checkout) -> dict:
    return {
        "id": str(checkout.id),
        "redirect_url": checkout.redirect_url,
        "amount_minor": checkout.amount_minor,
        "fee_minor": checkout.fee_minor,
        "currency": checkout.currency,
    }
```

`backend/etqan/gateways/api/views.py`, append. Add the imports `from rest_framework import status`, `from rest_framework.permissions import IsAuthenticated` and `from etqan.gateways.api.serializers import StartInput`:

```python
class StartCheckoutView(APIView):
    """Plan D1/D2: any signed-in caller; the purpose scopes what they may pay
    (404 otherwise). Non-atomic (plan D9): see urls."""

    permission_classes = [IsAuthenticated, FeatureOn]
    feature = "online_payments"

    def post(self, request):
        body = StartInput(data=request.data)
        body.is_valid(raise_exception=True)
        started = services.start_checkout(**body.validated_data, user=request.user)
        return Response(payloads.started(started), status=status.HTTP_201_CREATED)
```

Import `IsAuthenticated` from `rest_framework.permissions`. An anonymous caller gets 403 before the feature check.

`backend/etqan/gateways/api/urls.py`:
- import `from django.db import transaction`;
- add:

```python
    path(
        "checkouts/start/",
        transaction.non_atomic_requests(views.StartCheckoutView.as_view()),
        name="checkout-start",
    ),
```

- [ ] **Step 6: Implement billing's purpose and the options**

`backend/etqan/billing/services/online.py`:

```python
"""Billing's `invoice` purpose (B3b §4.3) and the invoice's Pay-online
options (plan D12). Billing reaches gateways only through its services."""

from etqan.billing.models import Invoice
from etqan.billing.scopes import scope_for
from etqan.billing.services import payments
from etqan.billing.services import rules
from etqan.gateways import services as gateways_services
from etqan.platform import features
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import codes_of
from etqan.platform.permissions import role_of

NAME = "invoice"
CLOSED = (Invoice.Status.VOID, Invoice.Status.PAID)


def _readable(reference_id: int, user) -> Invoice:
    """B-14: what the caller may read, as billing scopes it; staff need the
    invoice code itself, not just an office account."""
    if role_of(user) == "staff" and "invoice.view" not in codes_of(user):
        raise NotFoundError("Invoice", reference_id)
    invoice = scope_for(user, rules.invoices_queryset()).filter(pk=reference_id).first()
    if invoice is None:
        raise NotFoundError("Invoice", reference_id)
    return invoice


def prepare(reference_id: int, user, params: dict | None) -> gateways_services.Prepared:
    invoice = _readable(reference_id, user)
    if invoice.status in CLOSED or invoice.balance_minor <= 0:
        raise ConflictError("Nothing is due on this invoice.", code="gateways.nothing_due")
    return gateways_services.Prepared(
        amount_minor=invoice.balance_minor,
        currency=invoice.currency,
        description=invoice.number,
        add_fee=True,
    )


def complete(done: gateways_services.CompletedCheckout) -> gateways_services.Applied:
    """Takes the money when it still fits (B-11); otherwise says why."""
    invoice = Invoice.objects.filter(pk=done.reference_id).first()
    if invoice is None:
        return gateways_services.Applied(ok=False, reason="reference_missing")
    locked = rules.lock(invoice)
    if locked.status == Invoice.Status.VOID:
        return gateways_services.Applied(ok=False, reason="invoice_void")
    if locked.currency != done.currency:
        return gateways_services.Applied(ok=False, reason="currency_mismatch")
    if locked.amount_minor - rules.paid_of(locked) < done.amount_minor:
        return gateways_services.Applied(ok=False, reason="balance_below_amount")
    try:
        payments.record_online_payment(
            locked,
            amount_minor=done.amount_minor,
            fee_minor=done.fee_minor,
            method=done.provider,
            transaction_number=done.transaction_number,
        )
    except ValidationError:
        return gateways_services.Applied(ok=False, reason="already_recorded")
    return gateways_services.Applied(ok=True)


def pay_options(invoice) -> list[str]:
    """Plan D12: ``invoice`` comes from `invoices_queryset()`."""
    if not features.enabled("online_payments"):
        return []
    if invoice.status in CLOSED or invoice.balance_minor <= 0:
        return []
    return gateways_services.providers_for(
        invoice.currency, invoice.balance_minor, add_fee=True
    )


def register() -> None:
    gateways_services.register_purpose(NAME, prepare=prepare, complete=complete)
```

`record_online_payment` runs inside the webhook's transaction, so its `ValidationError` on a duplicate transaction number leaves no partial write. The surrounding `transaction.atomic` savepoint in `record_online_payment` rolls back.

`backend/etqan/billing/apps.py`:

```python
class BillingConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.billing"
    label = "billing"

    def ready(self):
        # B3b §4.3: the `invoice` purpose, paid online through gateways.
        from etqan.billing.services import online  # noqa: PLC0415

        online.register()
```

`backend/etqan/billing/services/__init__.py`: export `pay_options` from `etqan.billing.services.online`.

`backend/etqan/billing/api/payloads.py`:
- give `invoice_detail` a keyword `can_pay_online: list[str] | None = None`;
- add `"can_pay_online": list(can_pay_online or []),` to its dict.

`backend/etqan/billing/api/views.py`, in `detail()` and `InvoiceDetailView.get`:
- pass `can_pay_online=services.pay_options(invoice)`;
- in `get`, read the invoice through `invoice_or_404`, as now; it comes from `invoices_queryset()`, so it carries `balance_minor`.

- [ ] **Step 7: Run the tests**

Run: `$DJ pytest etqan/gateways etqan/billing etqan/access -q`
Expected: all pass.

- [ ] **Step 8: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/gateways etqan/billing etqan/access
git -C backend commit -m "feat(gateways): start_checkout with purposes; billing pays invoices online"
```

---
### Task 7: Webhooks, completion and the simulator

**Files:**
- Create: `backend/etqan/gateways/services/webhooks.py`, `backend/etqan/gateways/services/simulator.py`
- Modify: `backend/etqan/gateways/services/__init__.py`, `api/serializers.py`, `api/views.py`, `api/urls.py`
- Modify: `backend/etqan/access/tests/test_routes.py` (two `SELF_SERVICE` entries)
- Test: `backend/etqan/gateways/tests/test_webhooks.py`, `backend/etqan/gateways/tests/test_simulate.py`

**Interfaces:**
- Consumes: `stripe_account`, `webhook_secret_of` (Task 4); `purpose_named`, `CompletedCheckout` (Task 6); `gateways.clock.now` (Task 2).
- Produces, all exported from `etqan.gateways.services`:
  - `BadSignature` (an Exception)
  - `sign_stripe(raw: bytes, secret: str, timestamp: int) -> str`
  - `process_stripe(raw: bytes, header: str) -> None`
  - `simulate(checkout_id, outcome: str, *, user) -> None`
- Routes:
  - `POST /api/v1/gateways/webhooks/stripe/`
  - `POST /api/v1/gateways/simulate/<uuid>/` with body `{outcome: "pay" | "fail" | "expire"}`, answering 200 with `{status}`

- [ ] **Step 1: Write the failing tests**

`backend/etqan/gateways/tests/test_webhooks.py`:

```python
"""B3b §4.4, B-4, B-11: verified Stripe events move checkouts; completion
is accepted from any state but completed; money that cannot be applied
waits for an admin; replays and unknown checkouts are harmless."""

import json
import uuid
from datetime import datetime
from datetime import UTC

import pytest
from django.test import override_settings
from rest_framework.test import APIClient

from etqan.billing.models import Payment
from etqan.gateways import services
from etqan.gateways.models import Checkout
from etqan.gateways.models import WebhookEvent
from etqan.gateways.providers.base import Session
from etqan.gateways.services import purposes

pytestmark = pytest.mark.django_db
URL = "/api/v1/gateways/webhooks/stripe/"
NOW = datetime(2026, 6, 1, 8, tzinfo=UTC)


def session_event(checkout, kind="checkout.session.completed", **object_overrides):
    obj = {
        "id": checkout.provider_ref or "cs_x",
        "object": "checkout.session",
        "client_reference_id": str(checkout.pk),
        "metadata": {"checkout": str(checkout.pk)},
        "payment_status": "paid",
        "amount_total": checkout.amount_minor + checkout.fee_minor,
        "currency": checkout.currency.lower(),
        "payment_intent": f"pi_{uuid.uuid4().hex[:8]}",
        **object_overrides,
    }
    return {
        "id": f"evt_{uuid.uuid4().hex}",
        "type": kind,
        "livemode": False,
        "data": {"object": obj},
    }


def post(event, *, secret="whsec_demo", at=NOW):
    raw = json.dumps(event).encode()
    header = services.sign_stripe(raw, secret, int(at.timestamp()))
    return APIClient().post(
        URL, data=raw, content_type="application/json", HTTP_STRIPE_SIGNATURE=header
    )


@pytest.fixture
def pending(online_on, stripe_on, invoice, admin):
    """A pending 500.00 + 25.00 EGP checkout for an unpaid invoice."""

    def make(bill=None, **fields):
        bill = bill or invoice()
        return Checkout.objects.create(
            purpose="invoice",
            reference_id=bill.pk,
            provider="stripe",
            amount_minor=50000,
            fee_minor=2500,
            currency="EGP",
            provider_ref=fields.pop("provider_ref", f"cs_{uuid.uuid4().hex[:8]}"),
            **fields,
        )

    return make


def test_a_completed_session_records_the_payment(pending):
    checkout = pending()
    event = session_event(checkout)
    resp = post(event)
    assert resp.status_code == 200
    checkout.refresh_from_db()
    assert (checkout.status, checkout.applied, checkout.attention) == ("completed", True, "")
    assert checkout.transaction_number == event["data"]["object"]["payment_intent"]
    assert checkout.completed_at == NOW
    payment = Payment.objects.get(invoice_id=checkout.reference_id)
    assert (payment.amount_minor, payment.fee_minor, payment.method) == (50000, 2500, "stripe")


def test_a_bad_or_stale_signature_is_400_and_nothing_is_stored(pending, clock):
    checkout = pending()
    assert post(session_event(checkout), secret="whsec_other").status_code == 400
    stale = datetime(2026, 6, 1, 7, 54, 59, tzinfo=UTC)  # 301 s before NOW
    assert post(session_event(checkout), at=stale).status_code == 400
    assert not WebhookEvent.objects.exists()
    checkout.refresh_from_db()
    assert checkout.status == "pending"


def test_a_replay_does_nothing(pending):
    checkout = pending()
    event = session_event(checkout)
    assert post(event).status_code == 200
    assert post(event).status_code == 200
    assert Payment.objects.filter(invoice_id=checkout.reference_id).count() == 1


@pytest.mark.parametrize("state", ["cancelled", "expired", "failed"])
def test_completion_is_accepted_from_any_state_but_completed(pending, state):
    checkout = pending(status=state)
    post(session_event(checkout))
    checkout.refresh_from_db()
    assert (checkout.status, checkout.applied) == ("completed", True)


def test_a_completed_checkout_ignores_later_events(pending):
    checkout = pending()
    post(session_event(checkout))
    post(session_event(checkout, "checkout.session.expired"))
    post(session_event(checkout, payment_intent="pi_other"))
    checkout.refresh_from_db()
    assert checkout.status == "completed"
    assert Payment.objects.filter(invoice_id=checkout.reference_id).count() == 1


@pytest.mark.parametrize(
    ("overrides", "event_fields", "reason"),
    [
        ({"amount_total": 1}, {}, "amount_mismatch"),
        ({"currency": "usd"}, {}, "currency_mismatch"),
        ({}, {"livemode": True}, "mode_mismatch"),
    ],
)
def test_money_that_does_not_match_needs_attention(pending, overrides, event_fields, reason):
    checkout = pending()
    event = {**session_event(checkout, **overrides), **event_fields}
    assert post(event).status_code == 200
    checkout.refresh_from_db()
    assert (checkout.status, checkout.applied, checkout.attention) == (
        "completed", False, reason,
    )
    assert not Payment.objects.filter(invoice_id=checkout.reference_id).exists()


def test_review_focus_2_two_tabs_both_paid(pending, invoice):
    bill = invoice()
    first, second = pending(bill), pending(bill)
    post(session_event(first))
    post(session_event(second))
    second.refresh_from_db()
    assert (second.applied, second.attention) == (False, "balance_below_amount")
    assert Payment.objects.filter(invoice=bill).count() == 1


def test_failed_and_expired_move_only_a_pending_checkout(pending):
    failed = pending()
    post(session_event(failed, "checkout.session.async_payment_failed"))
    failed.refresh_from_db()
    assert failed.status == "failed"
    expired = pending()
    post(session_event(expired, "checkout.session.expired"))
    expired.refresh_from_db()
    assert expired.status == "expired"


def test_an_unpaid_completed_session_waits_for_its_async_result(pending):
    checkout = pending()
    post(session_event(checkout, payment_status="unpaid"))
    checkout.refresh_from_db()
    assert checkout.status == "pending"
    post(session_event(checkout, "checkout.session.async_payment_succeeded"))
    checkout.refresh_from_db()
    assert checkout.status == "completed"


def test_an_event_for_a_checkout_this_academy_lacks_is_200(pending):
    checkout = pending()
    event = session_event(
        checkout, metadata={"checkout": "not-a-uuid"}, client_reference_id=str(uuid.uuid4()),
        id="cs_elsewhere",
    )
    assert post(event).status_code == 200
    assert WebhookEvent.objects.get().checkout is None
    checkout.refresh_from_db()
    assert checkout.status == "pending"


def test_a_failing_purpose_rolls_everything_back_and_answers_500(
    pending, monkeypatch
):
    def boom(done):
        raise RuntimeError("purpose failed")

    monkeypatch.setitem(
        purposes._PURPOSES,  # noqa: SLF001 -- a test double for one purpose
        "boom",
        purposes.Purpose(prepare=lambda *a: None, complete=boom),
    )
    checkout = pending(purpose="boom")
    resp = post(session_event(checkout))
    assert resp.status_code == 500
    assert not WebhookEvent.objects.exists()
    checkout.refresh_from_db()
    assert checkout.status == "pending"


def test_an_unknown_purpose_needs_attention(pending):
    checkout = pending(purpose="gone")
    post(session_event(checkout))
    checkout.refresh_from_db()
    assert (checkout.applied, checkout.attention) == (False, "purpose_unknown")


@override_settings(ETQAN_SECRETS_KEY="", SECRETS_KEY_FROM_SECRET_KEY=False)
def test_without_a_key_the_webhook_answers_503_so_stripe_retries(pending):
    checkout = pending()
    resp = post(session_event(checkout))
    assert (resp.status_code, resp.json()["code"]) == (503, "gateways.no_key")


def test_review_focus_1_the_event_before_the_session_id_is_stored(
    online_on, stripe_on, parent_of_world, invoice, monkeypatch
):
    """Stripe can answer the webhook before start_checkout has written the
    session id: the checkout is found by its metadata, completes, and the
    late write of the id leaves it completed."""
    bill = invoice()

    class PaysAtOnce:
        def create(self, account, checkout, *, success_url, cancel_url):
            post(session_event(checkout))
            return Session(ref="cs_late", url="https://stripe.test/late")

        def expire(self, account, ref):
            return None

    monkeypatch.setattr(
        "etqan.gateways.services.checkouts.provider_for",
        lambda account, *, simulate: PaysAtOnce(),
    )
    started = services.start_checkout(
        "invoice", bill.pk, "stripe", user=parent_of_world
    )
    checkout = Checkout.objects.get(pk=started.id)
    assert (checkout.status, checkout.applied) == ("completed", True)
    assert checkout.provider_ref == "cs_late"
```

`backend/etqan/gateways/tests/test_simulate.py`:

```python
"""B-12, §4.6: the simulator page's outcomes go through the real webhook
handling, for the checkout's creator, only while GATEWAYS_SIMULATE is on."""

import pytest
from django.test import override_settings
from rest_framework.test import APIClient

from etqan.billing.models import Payment
from etqan.gateways import services
from etqan.gateways.models import Checkout

pytestmark = pytest.mark.django_db


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


@pytest.fixture
def simulated(online_on, stripe_on, parent_of_world, invoice):
    started = services.start_checkout(
        "invoice", invoice().pk, "stripe", user=parent_of_world
    )
    return parent_of_world, Checkout.objects.get(pk=started.id)


def outcome(client, checkout, value):
    return client.post(
        f"/api/v1/gateways/simulate/{checkout.pk}/", {"outcome": value}, format="json"
    )


def test_pay_completes_through_the_webhook_path(simulated):
    parent, checkout = simulated
    resp = outcome(as_user(parent), checkout, "pay")
    assert (resp.status_code, resp.json()) == (200, {"status": "completed"})
    checkout.refresh_from_db()
    assert checkout.transaction_number.startswith("pi_sim_")
    assert Payment.objects.filter(invoice_id=checkout.reference_id).count() == 1


@pytest.mark.parametrize(("value", "status"), [("fail", "failed"), ("expire", "expired")])
def test_fail_and_expire(simulated, value, status):
    parent, checkout = simulated
    assert outcome(as_user(parent), checkout, value).json() == {"status": status}


def test_only_the_creator_of_a_simulated_checkout(simulated, api_for):
    parent, checkout = simulated
    assert outcome(api_for("parent"), checkout, "pay").status_code == 404
    assert outcome(api_for("admin"), checkout, "pay").status_code == 404
    Checkout.objects.filter(pk=checkout.pk).update(simulated=False)
    assert outcome(as_user(parent), checkout, "pay").status_code == 404


@override_settings(GATEWAYS_SIMULATE=False)
def test_no_simulator_without_the_setting(simulated):
    parent, checkout = simulated
    assert outcome(as_user(parent), checkout, "pay").status_code == 404


def test_a_bad_outcome_is_400(simulated):
    parent, checkout = simulated
    assert outcome(as_user(parent), checkout, "maybe").status_code == 400
```

In `backend/etqan/access/tests/test_routes.py`, `SELF_SERVICE`, after the `StartCheckoutView` entry:

```python
    "etqan.gateways.api.views.StripeWebhookView": "Stripe, signature-checked",
    "etqan.gateways.api.views.SimulateView": (
        "the checkout's creator; development and CI only (GATEWAYS_SIMULATE)"
    ),
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DJ pytest etqan/gateways/tests/test_webhooks.py etqan/gateways/tests/test_simulate.py -q`
Expected: collection errors (no `sign_stripe`, no routes).

- [ ] **Step 3: Implement the webhook processing**

`backend/etqan/gateways/services/webhooks.py`:

```python
"""Stripe events (B3b §4.4). Verified over the raw body; recorded with
their effects in one transaction (a failure rolls both back and Stripe
retries); a replay finds its row and does nothing. A verified completion
completes from any state but completed (B-4); money that cannot be applied
completes with applied=false and a reason (B-11, plan D8)."""

import hashlib
import hmac
import json
import logging
import uuid

from django.db import IntegrityError
from django.db import transaction

from etqan.gateways import clock
from etqan.gateways.models import Checkout
from etqan.gateways.models import GatewayAccount
from etqan.gateways.models import WebhookEvent
from etqan.gateways.services.accounts import stripe_account
from etqan.gateways.services.accounts import webhook_secret_of
from etqan.gateways.services.purposes import CompletedCheckout
from etqan.gateways.services.purposes import purpose_named

STRIPE = GatewayAccount.Provider.STRIPE
TOLERANCE_SECONDS = 300
COMPLETED_SESSION = "checkout.session.completed"
ASYNC_SUCCEEDED = "checkout.session.async_payment_succeeded"
ASYNC_FAILED = "checkout.session.async_payment_failed"
SESSION_EXPIRED = "checkout.session.expired"
PENDING = Checkout.Status.PENDING
COMPLETED = Checkout.Status.COMPLETED
logger = logging.getLogger(__name__)


class BadSignature(Exception):  # noqa: N818 -- reads as what was received
    """The event is not Stripe's (or not this academy's endpoint's)."""


def _digest(raw: bytes, secret: str, timestamp: str) -> str:
    signed = timestamp.encode() + b"." + raw
    return hmac.new(secret.encode(), signed, hashlib.sha256).hexdigest()


def sign_stripe(raw: bytes, secret: str, timestamp: int) -> str:
    """A `Stripe-Signature` header for ``raw``, as Stripe builds it."""
    return f"t={timestamp},v1={_digest(raw, secret, str(timestamp))}"


def verify_stripe(raw: bytes, header: str, secret: str) -> dict:
    parts = [item.split("=", 1) for item in header.split(",") if "=" in item]
    stamps = [value for key, value in parts if key == "t"]
    signatures = [value for key, value in parts if key == "v1"]
    if not secret or not stamps or not signatures or not stamps[0].isdigit():
        raise BadSignature
    if abs(clock.now().timestamp() - int(stamps[0])) > TOLERANCE_SECONDS:
        raise BadSignature
    expected = _digest(raw, secret, stamps[0])
    if not any(hmac.compare_digest(expected, given) for given in signatures):
        raise BadSignature
    return json.loads(raw)


def _as_uuid(value) -> uuid.UUID | None:
    try:
        return uuid.UUID(str(value))
    except ValueError:
        return None


def _find(obj: dict) -> Checkout | None:
    """Plan D13: by our metadata, then the reference, then the session id."""
    for value in (obj.get("metadata", {}).get("checkout"), obj.get("client_reference_id")):
        key = _as_uuid(value) if value else None
        if key is not None:
            found = Checkout.objects.filter(pk=key).first()
            if found is not None:
                return found
    ref = obj.get("id") or ""
    return Checkout.objects.filter(provider=STRIPE, provider_ref=ref).first() if ref else None


def _attention(checkout: Checkout, obj: dict, event: dict, account) -> str:
    if bool(event.get("livemode")) != (account.mode == GatewayAccount.Mode.LIVE):
        return "mode_mismatch"
    if (obj.get("currency") or "").upper() != checkout.currency:
        return "currency_mismatch"
    if obj.get("amount_total") != checkout.amount_minor + checkout.fee_minor:
        return "amount_mismatch"
    if purpose_named(checkout.purpose) is None:
        return "purpose_unknown"
    return ""


def _complete(checkout: Checkout, obj: dict, event: dict, account) -> None:
    checkout.status = COMPLETED
    checkout.completed_at = clock.now()
    checkout.transaction_number = obj.get("payment_intent") or ""
    reason = _attention(checkout, obj, event, account)
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
    checkout.applied = applied
    checkout.save()


def _apply(checkout: Checkout, event: dict, account) -> None:
    obj = event["data"]["object"]
    kind = event.get("type")
    if checkout.status == COMPLETED:
        return
    paid = kind == ASYNC_SUCCEEDED or (
        kind == COMPLETED_SESSION and obj.get("payment_status") == "paid"
    )
    if paid:
        _complete(checkout, obj, event, account)
    elif kind == ASYNC_FAILED and checkout.status == PENDING:
        checkout.status = Checkout.Status.FAILED
        checkout.save(update_fields=["status"])
    elif kind == SESSION_EXPIRED and checkout.status == PENDING:
        checkout.status = Checkout.Status.EXPIRED
        checkout.save(update_fields=["status"])


def process_stripe(raw: bytes, header: str) -> None:
    """Raises BadSignature (400), UnavailableError (503, no key) or whatever
    a purpose raises (500, rolled back)."""
    account = stripe_account()
    event = verify_stripe(raw, header, webhook_secret_of(account))
    with transaction.atomic():
        try:
            with transaction.atomic():
                record = WebhookEvent.objects.create(
                    provider=STRIPE, event_id=event["id"], type=event.get("type", "")
                )
        except IntegrityError:
            return  # a replay
        obj = (event.get("data") or {}).get("object") or {}
        found = _find(obj)
        if found is None:
            logger.info("Stripe event %s names no checkout here", event["id"])
            return
        record.checkout = found
        record.save(update_fields=["checkout"])
        checkout = Checkout.objects.select_for_update().get(pk=found.pk)
        _apply(checkout, event, account)
```

`backend/etqan/gateways/services/simulator.py`:

```python
"""B-12, plan D14: the simulator page's outcomes, as signed Stripe events
handled by the real webhook path."""

import json
import uuid

from django.conf import settings

from etqan.gateways import clock
from etqan.gateways.models import Checkout
from etqan.gateways.services import webhooks
from etqan.gateways.services.accounts import stripe_account
from etqan.gateways.services.accounts import webhook_secret_of
from etqan.platform.exceptions import NotFoundError

OUTCOMES = {
    "pay": webhooks.COMPLETED_SESSION,
    "fail": webhooks.ASYNC_FAILED,
    "expire": webhooks.SESSION_EXPIRED,
}


def simulate(checkout_id, outcome: str, *, user) -> str:
    """The checkout's status after ``outcome``."""
    checkout = (
        Checkout.objects.filter(pk=checkout_id, simulated=True, created_by=user).first()
        if settings.GATEWAYS_SIMULATE
        else None
    )
    if checkout is None:
        raise NotFoundError("Checkout", checkout_id)
    obj = {
        "id": checkout.provider_ref,
        "object": "checkout.session",
        "client_reference_id": str(checkout.pk),
        "metadata": {"checkout": str(checkout.pk)},
        "payment_status": "paid" if outcome == "pay" else "unpaid",
        "amount_total": checkout.amount_minor + checkout.fee_minor,
        "currency": checkout.currency.lower(),
        "payment_intent": f"pi_sim_{uuid.uuid4().hex}",
    }
    event = {
        "id": f"evt_sim_{uuid.uuid4().hex}",
        "type": OUTCOMES[outcome],
        "livemode": False,
        "data": {"object": obj},
    }
    raw = json.dumps(event).encode()
    secret = webhook_secret_of(stripe_account())
    webhooks.process_stripe(
        raw, webhooks.sign_stripe(raw, secret, int(clock.now().timestamp()))
    )
    checkout.refresh_from_db()
    return checkout.status
```

`backend/etqan/gateways/services/__init__.py`: export `BadSignature`, `process_stripe`, `sign_stripe` (from `webhooks`) and `simulate` (from `simulator`).

- [ ] **Step 4: Implement the routes**

`backend/etqan/gateways/api/serializers.py`, append:

```python
class SimulateInput(serializers.Serializer):
    outcome = serializers.ChoiceField(choices=("pay", "fail", "expire"))
```

`backend/etqan/gateways/api/views.py`, append. Add the imports `logging`, `from rest_framework.permissions import AllowAny`, `from rest_framework.throttling import ScopedRateThrottle`, `from etqan.platform.exceptions import UnavailableError` and `SimulateInput`:

```python
logger = logging.getLogger(__name__)


class StripeWebhookView(APIView):
    """§4.4: Stripe, unauthenticated (so CSRF-free), verified over the raw
    body; not throttled. Non-atomic (plan D9): see urls."""

    authentication_classes: list = []
    permission_classes = [AllowAny]

    def post(self, request):
        try:
            services.process_stripe(
                request.body, request.headers.get("Stripe-Signature", "")
            )
        except services.BadSignature:
            return Response({"detail": "Bad signature."}, status=400)
        except UnavailableError:
            raise
        except Exception:  # noqa: BLE001 -- rolled back; Stripe retries on 5xx
            logger.exception("Stripe event failed")
            return Response({"detail": "Not processed."}, status=500)
        return Response({"received": True})


class SimulateView(APIView):
    """§4.6: the checkout's creator, while GATEWAYS_SIMULATE is on (404
    otherwise). Non-atomic (plan D9)."""

    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "gateway_simulate"

    def post(self, request, pk):
        body = SimulateInput(data=request.data)
        body.is_valid(raise_exception=True)
        status_now = services.simulate(pk, body.validated_data["outcome"], user=request.user)
        return Response({"status": status_now})
```

`backend/etqan/gateways/api/urls.py`, add:

```python
    path(
        "webhooks/stripe/",
        transaction.non_atomic_requests(views.StripeWebhookView.as_view()),
        name="webhook-stripe",
    ),
    path(
        "simulate/<uuid:pk>/",
        transaction.non_atomic_requests(views.SimulateView.as_view()),
        name="simulate",
    ),
```

- [ ] **Step 5: Run the tests**

Run: `$DJ pytest etqan/gateways etqan/access -q`
Expected: all pass. If `test_a_bad_or_stale_signature…` fails on the stale case, check that the `clock` fixture pins `gateways.clock.now` to `NOW` (conftest `Clock`).

- [ ] **Step 6: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/gateways etqan/access
git -C backend commit -m "feat(gateways): verified Stripe webhooks, completion from any state, the simulator"
```

---
### Task 8: The checkouts list, detail and resolve; the expiry job

**Files:**
- Modify: `backend/etqan/gateways/services/checkouts.py`, `services/__init__.py`
- Create: `backend/etqan/gateways/tasks.py`
- Modify: `backend/etqan/gateways/api/serializers.py`, `payloads.py`, `views.py`, `urls.py`
- Modify: `backend/config/settings/base.py` (a `CELERY_BEAT_SCHEDULE` entry)
- Modify: `backend/etqan/access/registry.py` (a `checkout` resource under the B3 marker, after `gateway`)
- Modify: `backend/etqan/access/tests/test_registry.py` (resource count 25 → 26)
- Modify: `backend/etqan/access/tests/test_routes.py` (a `U` constant, `ROUTES`, `FEATURES`, `SELF_SERVICE`)
- Test: `backend/etqan/gateways/tests/test_list.py`, `backend/etqan/gateways/tests/test_expiry.py`

**Interfaces:**
- Produces, all exported from `etqan.gateways.services`:
  - `checkouts_queryset()`
  - `filter_checkouts(qs, *, status="", purpose="", attention="", created_from=None, created_to=None)`
  - `checkout_for(user, checkout_id) -> Checkout`
  - `resolve_checkout(checkout_id, *, by) -> Checkout`
  - `expire_stale() -> int`
- Routes:
  - `GET gateways/checkouts/`, paginated, with rows from `payloads.checkout_row`
  - `GET gateways/checkouts/<uuid>/`, answering `{id, status, applied, amount_minor, fee_minor, currency, purpose, reference_id}`
  - `POST gateways/checkouts/<uuid>/resolve/`, answering 200 with the row
- Task `gateways.expire_checkouts`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/gateways/tests/test_list.py`:

```python
"""B3b §4.5, §4.7, §4.8: who reads a checkout, the admin's list, and
resolving the ones that need attention."""

from datetime import date

import pytest
from rest_framework.test import APIClient

from etqan.gateways.models import Checkout

pytestmark = pytest.mark.django_db
LIST = "/api/v1/gateways/checkouts/"


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


def a_checkout(**fields):
    return Checkout.objects.create(
        purpose="invoice",
        reference_id=fields.pop("reference_id", 1),
        provider="stripe",
        amount_minor=1000,
        fee_minor=50,
        currency="EGP",
        **fields,
    )


def test_the_creator_and_the_office_read_a_checkout(online_on, parent_of_world, api_for, staff_for):
    mine = a_checkout(created_by=parent_of_world)
    url = f"{LIST}{mine.pk}/"
    assert as_user(parent_of_world).get(url).json() == {
        "id": str(mine.pk),
        "status": "pending",
        "applied": None,
        "amount_minor": 1000,
        "fee_minor": 50,
        "currency": "EGP",
        "purpose": "invoice",
        "reference_id": 1,
    }
    assert api_for("admin").get(url).status_code == 200
    assert staff_for("checkout.view_any").get(url).status_code == 200
    assert staff_for().get(url).status_code == 404
    assert api_for("parent").get(url).status_code == 404
    assert APIClient().get(url).status_code == 403


def test_the_list_filters(online_on, api_for):
    done = a_checkout(status="completed", applied=True)
    stuck = a_checkout(status="completed", applied=False, attention="invoice_void")
    a_checkout(status="pending")
    client = api_for("admin")

    def ids(**params):
        return [row["id"] for row in client.get(LIST, params).json()["results"]]

    assert set(ids(status="completed")) == {str(done.pk), str(stuck.pk)}
    assert ids(attention="open") == [str(stuck.pk)]
    assert ids(purpose="invoice", created_from=date(2026, 1, 1).isoformat())
    assert client.get(LIST, {"status": "nope"}).status_code == 400
    assert client.get(LIST, {"attention": "maybe"}).status_code == 400
    assert client.get(LIST, {"created_from": "x"}).status_code == 400
    row = client.get(LIST, {"attention": "open"}).json()["results"][0]
    assert row["attention"] == "invoice_void"
    assert set(row) >= {
        "id", "purpose", "reference_id", "provider", "simulated", "amount_minor",
        "fee_minor", "currency", "status", "applied", "attention", "resolved_at",
        "resolved_by", "transaction_number", "description", "created_by",
        "created_at", "completed_at",
    }


def test_resolving(online_on, api_for):
    stuck = a_checkout(status="completed", applied=False, attention="invoice_void")
    client = api_for("admin")
    url = f"{LIST}{stuck.pk}/resolve/"
    resp = client.post(url)
    assert resp.status_code == 200
    assert resp.json()["resolved_by"]["id"] == client.user.pk
    assert client.get(LIST, {"attention": "open"}).json()["results"] == []
    again = client.post(url)
    assert (again.status_code, again.json()["code"]) == (409, "gateways.nothing_to_resolve")
    fine = a_checkout(status="completed", applied=True)
    refused = client.post(f"{LIST}{fine.pk}/resolve/")
    assert refused.json()["code"] == "gateways.nothing_to_resolve"
```

`backend/etqan/gateways/tests/test_expiry.py`:

```python
"""Plan D11, spec §4.5: pending checkouts older than 25 h expire daily, in
every academy."""

from datetime import timedelta

import pytest
from django.conf import settings
from django_tenants.utils import tenant_context

from etqan.gateways import clock as gateways_clock
from etqan.gateways import services
from etqan.gateways import tasks
from etqan.gateways.models import Checkout

pytestmark = pytest.mark.django_db


def aged(hours, **fields):
    checkout = Checkout.objects.create(
        purpose="invoice", reference_id=1, provider="stripe",
        amount_minor=1000, currency="EGP", **fields,
    )
    Checkout.objects.filter(pk=checkout.pk).update(
        created_at=gateways_clock.now() - timedelta(hours=hours)
    )
    return checkout


def status(checkout):
    checkout.refresh_from_db()
    return checkout.status


def test_only_old_pending_checkouts_expire(clock):
    old, young = aged(26), aged(24)
    finished = aged(30, status="completed", applied=True)
    assert services.expire_stale() == 1
    assert (status(old), status(young), status(finished)) == ("expired", "pending", "completed")


def test_the_job_runs_daily_in_every_academy(clock, tenants):
    here = aged(30)
    with tenant_context(tenants.other):
        there = aged(30)
    results = tasks.expire_checkouts()
    assert results[tenants.main.schema_name] == "ok"
    assert status(here) == "expired"
    with tenant_context(tenants.other):
        assert status(there) == "expired"
    entry = settings.CELERY_BEAT_SCHEDULE["gateways.expire_checkouts"]
    assert entry["task"] == tasks.expire_checkouts.name == "gateways.expire_checkouts"
    assert (entry["schedule"].hour, entry["schedule"].minute) == ({3}, {20})
```

`backend/etqan/access/tests/test_routes.py`:

1. Below `N = 999999 …`, add:

```python
U = "00000000-0000-0000-0000-000000000000"  # a checkout id no academy has
```

2. In `ROUTES`, after the gateway settings rows, add:

```python
    ("GET", "/api/v1/gateways/checkouts/", "checkout.view_any"),
    ("POST", f"/api/v1/gateways/checkouts/{U}/resolve/", "checkout.update"),
```

3. Add both to the `"online_payments"` tuple in `FEATURES`.

4. In `SELF_SERVICE`, add:

```python
    "etqan.gateways.api.views.CheckoutDetailView": (
        "the checkout's creator, or the office with checkout.view_any (in the view)"
    ),
```

5. In `test_registry.py`, change `== 25` to `== 26`.

- [ ] **Step 2: Run them to see them fail**

Run: `$DJ pytest etqan/gateways/tests/test_list.py etqan/gateways/tests/test_expiry.py etqan/access -q`
Expected: failures (no routes, no task, no resource).

- [ ] **Step 3: Implement the services**

Append to `backend/etqan/gateways/services/checkouts.py`. Add the imports `from datetime import date`, `from datetime import timedelta`, `from django.db.models import QuerySet`, `from etqan.gateways import clock`, `from etqan.platform.exceptions import ConflictError`, `from etqan.platform.exceptions import NotFoundError` and `from etqan.platform.permissions import codes_of`, `is_office`, `role_of`:

```python
STALE_AFTER = timedelta(hours=25)  # Stripe sessions live 24 h (plan D11)


def checkouts_queryset() -> QuerySet[Checkout]:
    return Checkout.objects.select_related("created_by", "resolved_by")


def filter_checkouts(  # noqa: PLR0913 -- keyword-only; mirrors the list's query
    checkouts: QuerySet[Checkout],
    *,
    status: str = "",
    purpose: str = "",
    attention: str = "",
    created_from: date | None = None,
    created_to: date | None = None,
) -> QuerySet[Checkout]:
    """§4.8, newest first. Dates are UTC days (gateways reads no academy
    calendar; plan D19)."""
    if status:
        checkouts = checkouts.filter(status=status)
    if purpose:
        checkouts = checkouts.filter(purpose=purpose)
    if attention == "open":
        checkouts = checkouts.filter(applied=False, resolved_at__isnull=True)
    if created_from is not None:
        checkouts = checkouts.filter(created_at__date__gte=created_from)
    if created_to is not None:
        checkouts = checkouts.filter(created_at__date__lte=created_to)
    return checkouts.order_by("-created_at")


def checkout_for(user, checkout_id) -> Checkout:
    """§4.5: its creator, admins, or staff holding checkout.view_any."""
    checkout = checkouts_queryset().filter(pk=checkout_id).first()
    office = is_office(user) and (
        role_of(user) == "admin" or "checkout.view_any" in codes_of(user)
    )
    if checkout is None or not (office or checkout.created_by_id == user.pk):
        raise NotFoundError("Checkout", checkout_id)
    return checkout


@transaction.atomic
def resolve_checkout(checkout_id, *, by) -> Checkout:
    checkout = Checkout.objects.select_for_update().filter(pk=checkout_id).first()
    if checkout is None:
        raise NotFoundError("Checkout", checkout_id)
    if checkout.applied is not False or checkout.resolved_at is not None:
        raise ConflictError(
            "Nothing here needs resolving.", code="gateways.nothing_to_resolve"
        )
    checkout.resolved_at = clock.now()
    checkout.resolved_by = by
    checkout.save(update_fields=["resolved_at", "resolved_by"])
    return checkout


def expire_stale() -> int:
    """Plan D11: a verified completion still lands later (B-4)."""
    return Checkout.objects.filter(
        status=PENDING, created_at__lt=clock.now() - STALE_AFTER
    ).update(status=Checkout.Status.EXPIRED)
```

Export the five names from `services/__init__.py`.

`backend/etqan/gateways/tasks.py`:

```python
from celery import shared_task

from etqan.gateways import services
from etqan.platform.tenancy import for_each_academy

EXPIRE = "gateways.expire_checkouts"


@shared_task(name=EXPIRE, soft_time_limit=3000, time_limit=3300)
def expire_checkouts() -> dict[str, str]:
    """Daily (plan D11): stale pending checkouts expire in every academy."""
    return for_each_academy(services.expire_stale, name=EXPIRE)
```

`backend/config/settings/base.py`, in `CELERY_BEAT_SCHEDULE`, after `"notifications.scan"`:

```python
    # B3b (plan D11): daily, stale pending checkouts expire.
    "gateways.expire_checkouts": {
        "task": "gateways.expire_checkouts",
        "schedule": crontab(hour=3, minute=20),
    },
```

- [ ] **Step 4: Implement the routes**

`backend/etqan/gateways/api/serializers.py`, append:

```python
class CheckoutQueryInput(serializers.Serializer):
    # A bad value is a 400 on its field, never silently "everything".
    status = serializers.ChoiceField(choices=Checkout.Status.choices, required=False)
    purpose = serializers.CharField(max_length=40, required=False, allow_blank=True)
    attention = serializers.ChoiceField(choices=("open",), required=False)
    created_from = serializers.DateField(required=False)
    created_to = serializers.DateField(required=False)
```

(import `Checkout` from `etqan.gateways.models`.)

`backend/etqan/gateways/api/payloads.py`, append:

```python
def _person(user) -> dict | None:
    return None if user is None else {"id": user.pk, "full_name": user.full_name}


def checkout_status(checkout) -> dict:
    return {
        "id": str(checkout.pk),
        "status": checkout.status,
        "applied": checkout.applied,
        "amount_minor": checkout.amount_minor,
        "fee_minor": checkout.fee_minor,
        "currency": checkout.currency,
        "purpose": checkout.purpose,
        "reference_id": checkout.reference_id,
    }


def checkout_row(checkout) -> dict:
    return {
        **checkout_status(checkout),
        "provider": checkout.provider,
        "simulated": checkout.simulated,
        "attention": checkout.attention,
        "resolved_at": checkout.resolved_at,
        "resolved_by": _person(checkout.resolved_by),
        "transaction_number": checkout.transaction_number,
        "description": checkout.description,
        "created_by": _person(checkout.created_by),
        "created_at": checkout.created_at,
        "completed_at": checkout.completed_at,
    }
```

`backend/etqan/gateways/api/views.py`, append (with `from rest_framework import generics` and `CheckoutQueryInput`):

```python
class CheckoutListView(generics.GenericAPIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "online_payments"
    permission_codes = {"GET": "checkout.view_any"}

    def get(self, request):
        query = CheckoutQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        rows = services.filter_checkouts(
            services.checkouts_queryset(), **query.validated_data
        )
        page = self.paginate_queryset(rows)
        return self.get_paginated_response([payloads.checkout_row(c) for c in page])


class CheckoutDetailView(APIView):
    """§4.5: signed in; its creator or the office (checked in the service)."""

    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        return Response(payloads.checkout_status(services.checkout_for(request.user, pk)))


class ResolveView(APIView):
    permission_classes = [HasCode, FeatureOn]
    feature = "online_payments"
    permission_codes = {"POST": "checkout.update"}

    def post(self, request, pk):
        checkout = services.resolve_checkout(pk, by=request.user)
        fresh = services.checkouts_queryset().get(pk=checkout.pk)
        return Response(payloads.checkout_row(fresh))
```

`backend/etqan/gateways/api/urls.py`, add:

```python
    path("checkouts/", views.CheckoutListView.as_view(), name="checkouts"),
    path("checkouts/<uuid:pk>/", views.CheckoutDetailView.as_view(), name="checkout"),
    path(
        "checkouts/<uuid:pk>/resolve/", views.ResolveView.as_view(), name="checkout-resolve"
    ),
```

`backend/etqan/access/registry.py`, under the B3 marker after `gateway`:

```python
    # B3b: the online checkouts, and resolving the ones needing attention.
    Resource(
        "checkout", "Online payments", "المدفوعات الإلكترونية", ("view_any", "update")
    ),
```

- [ ] **Step 5: Run the tests**

Run: `$DJ pytest etqan/gateways etqan/access -q`
Expected: all pass.

- [ ] **Step 6: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/gateways etqan/access config/settings/base.py
git -C backend commit -m "feat(gateways): checkouts list, detail and resolve; daily expiry"
```

---
### Task 9: Demo seeds

**Files:**
- Create: `backend/etqan/tenants/seeds/gateways.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py`: one import, and one line under the B3 marker after `finance_seeds.seed_finance(subdomain)`
- Test: `backend/etqan/tenants/tests/test_seed_gateways.py`

**Interfaces:**
- Consumes: `gateways.services.update_settings`, `stripe_account`, `fee_settings` (Task 4).
- Produces: `seed_gateways(subdomain: str) -> None`.

- [ ] **Step 1: Write the failing test**

`backend/etqan/tenants/tests/test_seed_gateways.py`, in the same shape as `test_seed_finance.py`. Note
`DEBUG=True`, since `seed_dev` refuses to run without it, and the return to the public schema between
calls:

```python
"""B3b §8: demo gets an enabled Stripe test account with placeholder keys
(the simulator works out of the box) and the default fee; other gets
nothing; seeding twice changes nothing."""

import pytest
from django.core.management import call_command
from django.db import connection
from django.test import override_settings
from django_tenants.utils import tenant_context

from etqan.gateways import services as gateways_services
from etqan.tenants.models import Academy


def state():
    account = gateways_services.stripe_account()
    return (
        account.enabled,
        account.mode,
        account.public_key,
        gateways_services.secret_of(account) if account.secret_enc else "",
        gateways_services.webhook_secret_of(account) if account.webhook_secret_enc else "",
        account.secret_enc,
        gateways_services.fee_settings().fee_basis_points,
    )


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_gives_demo_a_stripe_test_account_once():
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        first = state()
        assert first[:5] == (True, "test", "pk_test_demo", "sk_test_demo", "whsec_demo")
        assert first[6] == 500
    with tenant_context(other):
        assert state()[:2] == (False, "test")
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert state() == first  # the same token: not re-encrypted
```

- [ ] **Step 2: Run it to see it fail**

Run: `$DJ pytest etqan/tenants/tests/test_seed_gateways.py -q`
Expected: FAIL (`demo` is not enabled).

- [ ] **Step 3: Implement**

`backend/etqan/tenants/seeds/gateways.py`:

```python
"""Phase B3, slice B3b (spec §8): the demo academy's Stripe account in test
mode with placeholder keys, so the offline simulator (GATEWAYS_SIMULATE)
works out of the box; nothing real is ever called with them. Idempotent:
an account that already has a secret is left alone (re-encrypting would
change its token)."""

from etqan.gateways import services as gateways_services

STRIPE = {
    "demo": {
        "enabled": True,
        "mode": "test",
        "public_key": "pk_test_demo",
        "secret": "sk_test_demo",
        "webhook_secret": "whsec_demo",
    }
}


def seed_gateways(subdomain: str) -> None:
    keys = STRIPE.get(subdomain)
    if keys is None or gateways_services.stripe_account().secret_enc:
        return
    gateways_services.update_settings(stripe=keys, by=None)
    gateways_services.fee_settings()  # the default fee row (5 %)
```

`backend/etqan/tenants/management/commands/seed_dev.py`:
- import `from etqan.tenants.seeds import gateways as gateways_seeds`, in isort order next to `finance_seeds`;
- under the B3 marker, after `finance_seeds.seed_finance(subdomain)`, add `gateways_seeds.seed_gateways(subdomain)`.

- [ ] **Step 4: Run the tests, then seed the stack twice**

Run: `$DJ pytest etqan/tenants -q`
Expected: all pass.

Then seed this stream's own database twice, through `just seed` (or the `$DJ python manage.py seed_dev` form). Check that the demo Stripe account is enabled after both runs:

```bash
$DJ python manage.py shell -c "from django_tenants.utils import tenant_context; from etqan.tenants.models import Academy; from etqan.gateways import services as s; a=Academy.objects.get(subdomain='demo'); ctx=tenant_context(a); ctx.__enter__(); print(s.stripe_account().enabled, s.stripe_account().mode)"
```

Expected output: `True test`.

- [ ] **Step 5: Lint and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format . && ruff check . && lint-imports'
git -C backend add etqan/tenants
git -C backend commit -m "feat(seeds): the demo academy's Stripe test account"
```

---
### Task 10: Dashboard foundations — types, API, hooks, translations, nav

**Files:**
- Create: `dashboard/src/features/gateways/schemas.ts`, `api.ts`, `queries.ts`, `redirect.ts`, `errors.ts`, `index.ts`, `schemas.test.ts`, `api.test.ts`, `errors.test.ts`
- Create: `dashboard/src/locales/en/gateways.json`, `dashboard/src/locales/ar/gateways.json`
- Create: `dashboard/src/test/gateways-fixtures.ts`
- Modify: `dashboard/src/features/billing/schemas.ts`, `api.ts`, `index.ts`
- Modify: `dashboard/src/test/billing-fixtures.ts` (the new payment fields and `can_pay_online` defaults)
- Modify: `dashboard/src/locales/{en,ar}/billing.json` (methods and refund strings), `dashboard/src/locales/{en,ar}/errors.json` (two lines in `billing`)
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode` gains `"online_payments"`)
- Modify: `dashboard/src/features/shell/nav.ts` (two items under the B3 marker), `nav.test.ts`

**Interfaces:**
- Produces:
  - `gatewaysApi`, with:
    - `settings()`
    - `saveSettings(body)`
    - `start({purpose, reference_id, provider})`
    - `checkout(id)`
    - `checkouts(params)`
    - `resolve(id)`
    - `simulate({id, outcome})`
  - hooks:
    - `useGatewaySettings()`
    - `useCheckouts(params)`
    - `useCheckout(id, {poll})`
    - `useGatewaysMutation(write)`
  - `go(url)`
  - helpers `toBasisPoints(percent: string): number` and `toPercent(bp: number): string`
  - types `GatewaySettings`, `SettingsPatch`, `StartedCheckout`, `CheckoutStatusBody`, `CheckoutRow`, `CheckoutStatus`, `Provider`
  - `billingApi.refund(paymentId) -> InvoiceDetail`
  - `Payment` gains `fee_minor`, `transaction_number`, `status`, `refunded_at`
  - `InvoiceDetail` gains `can_pay_online: Provider[]`
  - `ONLINE_METHODS`

- [ ] **Step 0: Check the branch.** `git -C dashboard branch --show-current` prints `feat/b3b-online-payments`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/gateways/schemas.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { feeFormSchema, toBasisPoints, toPercent } from "./schemas";

describe("fee percent ↔ basis points", () => {
	it("converts both ways", () => {
		expect(toBasisPoints("5")).toBe(500);
		expect(toBasisPoints("2.5")).toBe(250);
		expect(toBasisPoints("0")).toBe(0);
		expect(toPercent(500)).toBe("5");
		expect(toPercent(250)).toBe("2.5");
	});

	it("accepts 0–20 with up to two decimals", () => {
		const ok = (percent: string) =>
			feeFormSchema.safeParse({ enabled: true, percent }).success;
		expect(ok("5")).toBe(true);
		expect(ok("20")).toBe(true);
		expect(ok("12.75")).toBe(true);
		expect(ok("20.01")).toBe(false);
		expect(ok("-1")).toBe(false);
		expect(ok("1.234")).toBe(false);
		expect(ok("")).toBe(false);
	});
});
```

`dashboard/src/features/gateways/api.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { gatewaysApi } from "./api";

describe("gatewaysApi", () => {
	afterEach(() => vi.restoreAllMocks());

	it("starts a checkout at checkouts/start/", async () => {
		const post = vi
			.spyOn(api, "post")
			.mockResolvedValue({ data: { id: "c1" } } as never);
		await gatewaysApi.start({
			purpose: "invoice",
			reference_id: 51,
			provider: "stripe",
		});
		expect(post).toHaveBeenCalledWith("gateways/checkouts/start/", {
			purpose: "invoice",
			reference_id: 51,
			provider: "stripe",
		});
	});

	it("posts a simulated outcome and a resolve", async () => {
		const post = vi
			.spyOn(api, "post")
			.mockResolvedValue({ data: {} } as never);
		await gatewaysApi.simulate({ id: "c1", outcome: "pay" });
		expect(post).toHaveBeenCalledWith("gateways/simulate/c1/", {
			outcome: "pay",
		});
		await gatewaysApi.resolve("c1");
		expect(post).toHaveBeenCalledWith("gateways/checkouts/c1/resolve/");
	});

	it("patches the settings", async () => {
		const patch = vi
			.spyOn(api, "patch")
			.mockResolvedValue({ data: {} } as never);
		await gatewaysApi.saveSettings({ fee: { basis_points: 300 } });
		expect(patch).toHaveBeenCalledWith("gateways/settings/", {
			fee: { basis_points: 300 },
		});
	});
});
```

In `dashboard/src/features/shell/nav.test.ts`:
- "ships the grouped admin areas in order": after `"/billing/donations",` add `"/billing/checkouts",` and `"/settings/gateways",`.
- "names a feature on exactly the items that belong to one": add `"/billing/checkouts": "online_payments",` and `"/settings/gateways": "online_payments",`.
- "hides the items of every feature the academy has switched off": add `"/billing/checkouts"` and `"/settings/gateways"` to the list.

- [ ] **Step 2: Run them to see them fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/gateways src/features/shell src/features/finance src/locales`
Expected: failures (missing modules, nav order).

- [ ] **Step 3: Implement the gateways module**

`dashboard/src/features/gateways/schemas.ts`:

```ts
import { z } from "zod";
import type { Person } from "@/features/billing/schemas";

export type Provider = "stripe";
export const PROVIDERS = ["stripe"] as const satisfies readonly Provider[];

export const CHECKOUT_STATUSES = [
	"pending",
	"completed",
	"failed",
	"cancelled",
	"expired",
] as const;
export type CheckoutStatus = (typeof CHECKOUT_STATUSES)[number];

/** Plan D8: why an online payment could not be applied. */
export const ATTENTION_CODES = [
	"invoice_void",
	"balance_below_amount",
	"amount_mismatch",
	"currency_mismatch",
	"mode_mismatch",
	"purpose_unknown",
	"reference_missing",
	"already_recorded",
] as const;

export interface GatewaySettings {
	stripe: {
		enabled: boolean;
		mode: "test" | "live";
		public_key: string;
		has_secret: boolean;
		has_webhook_secret: boolean;
		webhook_url: string;
		events: string[];
		currencies: string[];
	};
	fee: { enabled: boolean; basis_points: number };
}

export interface StripePatch {
	enabled?: boolean;
	mode?: "test" | "live";
	public_key?: string;
	secret?: string;
	webhook_secret?: string;
}

export interface SettingsPatch {
	stripe?: StripePatch;
	fee?: { enabled?: boolean; basis_points?: number };
}

export interface StartBody {
	purpose: "invoice";
	reference_id: number;
	provider: Provider;
}

export interface StartedCheckout {
	id: string;
	redirect_url: string;
	amount_minor: number;
	fee_minor: number;
	currency: string;
}

export interface CheckoutStatusBody {
	id: string;
	status: CheckoutStatus;
	applied: boolean | null;
	amount_minor: number;
	fee_minor: number;
	currency: string;
	purpose: string;
	reference_id: number;
}

export interface CheckoutRow extends CheckoutStatusBody {
	provider: Provider;
	simulated: boolean;
	attention: string;
	resolved_at: string | null;
	resolved_by: Person | null;
	transaction_number: string;
	description: string;
	created_by: Person | null;
	created_at: string;
	completed_at: string | null;
}

/** The Stripe card's form. A blank secret field keeps the saved one. */
export const stripeFormSchema = z.object({
	enabled: z.boolean(),
	mode: z.enum(["test", "live"]),
	public_key: z.string().max(200),
	secret: z.string().max(255),
	webhook_secret: z.string().max(255),
});
export type StripeForm = z.infer<typeof stripeFormSchema>;

/** The fee card's form: a percentage 0–20 with up to two decimals. */
export const feeFormSchema = z.object({
	enabled: z.boolean(),
	percent: z
		.string()
		.regex(/^\d{1,2}(\.\d{1,2})?$/, "gateways.errors.percent")
		.refine((value) => Number(value) <= 20, "gateways.errors.percent"),
});
export type FeeForm = z.infer<typeof feeFormSchema>;

export function toBasisPoints(percent: string): number {
	return Math.round(Number(percent) * 100);
}

export function toPercent(bp: number): string {
	return String(bp / 100);
}

/** Only what changed; blank secrets are left out (kept on the server). */
export function stripePatch(values: StripeForm): StripePatch {
	const { secret, webhook_secret, ...rest } = values;
	return {
		...rest,
		...(secret ? { secret } : {}),
		...(webhook_secret ? { webhook_secret } : {}),
	};
}
```

`dashboard/src/features/gateways/api.ts`:

```ts
import { api, clean, type Paginated, type QueryParams } from "@/lib/api";
import type {
	CheckoutRow,
	CheckoutStatus,
	CheckoutStatusBody,
	GatewaySettings,
	SettingsPatch,
	StartBody,
	StartedCheckout,
} from "./schemas";

const G = "gateways/";

export const gatewaysApi = {
	settings: async () =>
		(await api.get<GatewaySettings>(`${G}settings/`)).data,
	saveSettings: async (body: SettingsPatch) =>
		(await api.patch<GatewaySettings>(`${G}settings/`, body)).data,
	start: async (body: StartBody) =>
		(await api.post<StartedCheckout>(`${G}checkouts/start/`, body)).data,
	checkout: async (id: string) =>
		(await api.get<CheckoutStatusBody>(`${G}checkouts/${id}/`)).data,
	checkouts: async (params: QueryParams) =>
		(
			await api.get<Paginated<CheckoutRow>>(`${G}checkouts/`, {
				params: clean(params),
			})
		).data,
	resolve: async (id: string) =>
		(await api.post<CheckoutRow>(`${G}checkouts/${id}/resolve/`)).data,
	simulate: async ({
		id,
		outcome,
	}: {
		id: string;
		outcome: "pay" | "fail" | "expire";
	}) =>
		(
			await api.post<{ status: CheckoutStatus }>(`${G}simulate/${id}/`, {
				outcome,
			})
		).data,
};
```

`dashboard/src/features/gateways/queries.ts`:

```ts
import {
	keepPreviousData,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { billingKey } from "@/features/billing/queries";
import type { QueryParams } from "@/lib/api";
import { gatewaysApi } from "./api";

/** Every gateways query lives under this key. */
export const gatewaysKey = ["gateways"] as const;

export function useGatewaySettings() {
	return useQuery({
		queryKey: [...gatewaysKey, "settings"],
		queryFn: gatewaysApi.settings,
	});
}

export function useCheckouts(params: QueryParams) {
	return useQuery({
		queryKey: [...gatewaysKey, "checkouts", params],
		queryFn: () => gatewaysApi.checkouts(params),
		placeholderData: keepPreviousData,
	});
}

/** One checkout; with `poll`, refetched every 2 s while it is pending. */
export function useCheckout(id: string | undefined, { poll }: { poll: boolean }) {
	return useQuery({
		queryKey: [...gatewaysKey, "checkout", id],
		queryFn: () => gatewaysApi.checkout(id as string),
		enabled: id !== undefined,
		refetchInterval: (query) =>
			poll && query.state.data?.status === "pending" ? 2000 : false,
	});
}

/** A gateways write: refreshes gateways and billing (a payment lands). */
export function useGatewaysMutation<A, R>(write: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (args: A) => write(args),
		onSuccess: () =>
			Promise.all([
				qc.invalidateQueries({ queryKey: gatewaysKey }),
				qc.invalidateQueries({ queryKey: billingKey }),
			]),
	});
}
```

`dashboard/src/features/gateways/redirect.ts`:

```ts
/** The one full-page navigation (to Stripe or the simulator): its own
 * module so tests replace it. */
export function go(url: string): void {
	window.location.assign(url);
}
```

`dashboard/src/features/gateways/index.ts`:

```ts
export { gatewaysApi } from "./api";
export * from "./queries";
export * from "./schemas";
```

(Tasks 11–13 add their components' exports here.)

- [ ] **Step 4: Billing types, API and fixtures**

`dashboard/src/features/billing/schemas.ts`:

1. Below `PAYMENT_METHODS`, add:

```ts
/** B3b B-9: recorded by a provider's verified event, never by hand. */
export const ONLINE_METHODS = ["stripe", "paypal"] as const;
export type OnlineMethod = (typeof ONLINE_METHODS)[number];
```

2. In `Payment`:
   - change `method: PaymentMethod;` to `method: PaymentMethod | OnlineMethod;`;
   - add after `reference: string;`:

```ts
	fee_minor: number;
	transaction_number: string;
	status: "completed" | "refunded";
	refunded_at: string | null;
```

3. In `InvoiceDetail`, add `can_pay_online: "stripe"[];` (B3b D12: the providers its reader may pay with).

`dashboard/src/features/billing/api.ts`, add to `billingApi`:

```ts
	refund: async (paymentId: number) =>
		(await api.post<InvoiceDetail>(`billing/payments/${paymentId}/refund/`))
			.data,
```

`dashboard/src/test/billing-fixtures.ts`:
- `paymentRow` defaults gain `fee_minor: 0, transaction_number: "", status: "completed", refunded_at: null,`;
- `invoiceDetail` and `familyInvoice` gain `can_pay_online: []` before `...overrides`.

`dashboard/src/test/gateways-fixtures.ts`:

```ts
import type {
	CheckoutRow,
	GatewaySettings,
	StartedCheckout,
} from "@/features/gateways/schemas";

export function gatewaySettings(
	overrides: Partial<GatewaySettings> = {},
): GatewaySettings {
	return {
		stripe: {
			enabled: true,
			mode: "test",
			public_key: "pk_test_demo",
			has_secret: true,
			has_webhook_secret: true,
			webhook_url: "http://demo.etqan.localhost/api/v1/gateways/webhooks/stripe/",
			events: [
				"checkout.session.completed",
				"checkout.session.async_payment_succeeded",
				"checkout.session.async_payment_failed",
				"checkout.session.expired",
			],
			currencies: ["EGP", "USD"],
		},
		fee: { enabled: true, basis_points: 500 },
		...overrides,
	};
}

export function started(overrides: Partial<StartedCheckout> = {}): StartedCheckout {
	return {
		id: "6f1c2a8e-0000-4000-8000-000000000001",
		redirect_url: "https://checkout.stripe.test/c/1",
		amount_minor: 100000,
		fee_minor: 5000,
		currency: "EGP",
		...overrides,
	};
}

export function checkoutRow(overrides: Partial<CheckoutRow> = {}): CheckoutRow {
	return {
		id: "6f1c2a8e-0000-4000-8000-000000000001",
		status: "completed",
		applied: false,
		amount_minor: 100000,
		fee_minor: 5000,
		currency: "EGP",
		purpose: "invoice",
		reference_id: 51,
		provider: "stripe",
		simulated: false,
		attention: "invoice_void",
		resolved_at: null,
		resolved_by: null,
		transaction_number: "pi_123",
		description: "INV-000051",
		created_by: { id: 31, full_name: "Omar" },
		created_at: "2026-06-01T08:00:00Z",
		completed_at: "2026-06-01T08:05:00Z",
		...overrides,
	};
}
```

- [ ] **Step 5: Translations, feature code, nav and landing**

`dashboard/src/locales/en/gateways.json`:

```json
{
	"gateways": {
		"nav": {
			"settings": "Payment gateways",
			"checkouts": "Online payments"
		},
		"settings": {
			"subtitle": "Connect your own Stripe account so families can pay invoices online.",
			"stripe": "Stripe",
			"enabled": "Accept payments with Stripe",
			"mode": "Mode",
			"modes": { "test": "Test", "live": "Live" },
			"publicKey": "Publishable key",
			"secret": "Secret key",
			"webhookSecret": "Webhook signing secret",
			"saved": "Saved ✓ — enter a new one to replace it",
			"notSet": "Not set",
			"webhookUrl": "Webhook URL",
			"copy": "Copy",
			"copied": "Copied",
			"events": "Send these events to the webhook URL:",
			"fee": "Service fee",
			"feeEnabled": "Add a service fee to online payments",
			"percent": "Percentage",
			"save": "Save",
			"saved_toast": "Payment settings saved"
		},
		"pay": {
			"button": "Pay online with {{provider}}",
			"title": "Pay online",
			"balance": "Amount due",
			"fee": "Service fee",
			"total": "Total",
			"continue": "Continue to {{provider}}",
			"cancel": "Cancel"
		},
		"return": {
			"title": "Your payment",
			"paid": "Paid — thank you.",
			"processing": "Still processing. This can take a minute.",
			"notPaid": "Not paid.",
			"refresh": "Refresh",
			"retry": "Try again",
			"back": "Back to the invoice",
			"missing": "We could not find this payment."
		},
		"simulate": {
			"title": "Simulated payment",
			"note": "Test mode: no money moves. Choose what the provider would answer.",
			"pay": "Pay",
			"fail": "Decline",
			"expire": "Let it expire"
		},
		"checkouts": {
			"all": "All",
			"attention": "Needs attention",
			"empty": "No online payments yet.",
			"loadError": "Online payments could not be loaded.",
			"resolve": "Mark resolved",
			"resolved": "Marked resolved",
			"columns": {
				"date": "Date",
				"what": "For",
				"amount": "Amount",
				"fee": "Fee",
				"status": "Status",
				"payer": "Started by",
				"transaction": "Transaction"
			}
		},
		"status": {
			"pending": "Pending",
			"completed": "Completed",
			"failed": "Failed",
			"cancelled": "Cancelled",
			"expired": "Expired"
		},
		"attention": {
			"invoice_void": "The invoice was void when the money arrived.",
			"balance_below_amount": "The invoice no longer owed this much.",
			"amount_mismatch": "The amount paid did not match.",
			"currency_mismatch": "The currency paid did not match.",
			"mode_mismatch": "The payment came from the wrong mode (test/live).",
			"purpose_unknown": "Nothing here could take this payment.",
			"reference_missing": "The invoice no longer exists.",
			"already_recorded": "This transaction is already recorded."
		},
		"errors": {
			"percent": "Enter a percentage from 0 to 20.",
			"no_key": "This server cannot store payment keys yet. Contact Etqan.",
			"bad_key": "The saved keys can no longer be read. Enter them again.",
			"nothing_due": "Nothing is due on this invoice.",
			"nothing_to_resolve": "Nothing here needs resolving."
		}
	}
}
```

`dashboard/src/locales/ar/gateways.json`: the same keys, key for key, in Arabic. Keep the placeholders `{{provider}}` as they are:

```json
{
	"gateways": {
		"nav": {
			"settings": "بوابات الدفع",
			"checkouts": "المدفوعات الإلكترونية"
		},
		"settings": {
			"subtitle": "اربط حساب Stripe الخاص بك ليتمكن أولياء الأمور من دفع الفواتير إلكترونيًا.",
			"stripe": "Stripe",
			"enabled": "قبول المدفوعات عبر Stripe",
			"mode": "الوضع",
			"modes": { "test": "تجريبي", "live": "مباشر" },
			"publicKey": "المفتاح العام",
			"secret": "المفتاح السري",
			"webhookSecret": "سر توقيع الإشعارات",
			"saved": "محفوظ ✓ — أدخل قيمة جديدة لاستبداله",
			"notSet": "غير مُعيَّن",
			"webhookUrl": "رابط الإشعارات (Webhook)",
			"copy": "نسخ",
			"copied": "تم النسخ",
			"events": "أرسل هذه الأحداث إلى رابط الإشعارات:",
			"fee": "رسوم الخدمة",
			"feeEnabled": "إضافة رسوم خدمة إلى المدفوعات الإلكترونية",
			"percent": "النسبة",
			"save": "حفظ",
			"saved_toast": "تم حفظ إعدادات الدفع"
		},
		"pay": {
			"button": "ادفع إلكترونيًا عبر {{provider}}",
			"title": "الدفع الإلكتروني",
			"balance": "المبلغ المستحق",
			"fee": "رسوم الخدمة",
			"total": "الإجمالي",
			"continue": "المتابعة إلى {{provider}}",
			"cancel": "إلغاء"
		},
		"return": {
			"title": "عملية الدفع",
			"paid": "تم الدفع — شكرًا لك.",
			"processing": "ما زال الدفع قيد المعالجة، قد يستغرق ذلك دقيقة.",
			"notPaid": "لم يتم الدفع.",
			"refresh": "تحديث",
			"retry": "حاول مرة أخرى",
			"back": "العودة إلى الفاتورة",
			"missing": "لم نجد هذه العملية."
		},
		"simulate": {
			"title": "دفع تجريبي",
			"note": "وضع تجريبي: لا تنتقل أي أموال. اختر ما سيجيب به مزود الدفع.",
			"pay": "ادفع",
			"fail": "رفض",
			"expire": "اتركها تنتهي"
		},
		"checkouts": {
			"all": "الكل",
			"attention": "بحاجة إلى مراجعة",
			"empty": "لا توجد مدفوعات إلكترونية بعد.",
			"loadError": "تعذّر تحميل المدفوعات الإلكترونية.",
			"resolve": "تحديد كمُعالَجة",
			"resolved": "تم التحديد كمُعالَجة",
			"columns": {
				"date": "التاريخ",
				"what": "مقابل",
				"amount": "المبلغ",
				"fee": "الرسوم",
				"status": "الحالة",
				"payer": "بدأها",
				"transaction": "رقم العملية"
			}
		},
		"status": {
			"pending": "قيد الانتظار",
			"completed": "مكتملة",
			"failed": "فاشلة",
			"cancelled": "ملغاة",
			"expired": "منتهية"
		},
		"attention": {
			"invoice_void": "كانت الفاتورة ملغاة عند وصول المبلغ.",
			"balance_below_amount": "لم تعد الفاتورة مستحقة بهذا المبلغ.",
			"amount_mismatch": "المبلغ المدفوع غير مطابق.",
			"currency_mismatch": "عملة الدفع غير مطابقة.",
			"mode_mismatch": "جاء الدفع من وضع مختلف (تجريبي/مباشر).",
			"purpose_unknown": "لا يوجد ما يستقبل هذا الدفع.",
			"reference_missing": "الفاتورة لم تعد موجودة.",
			"already_recorded": "هذه العملية مسجلة مسبقًا."
		},
		"errors": {
			"percent": "أدخل نسبة من 0 إلى 20.",
			"no_key": "لا يستطيع الخادم حفظ مفاتيح الدفع بعد. تواصل مع إتقان.",
			"bad_key": "تعذّرت قراءة المفاتيح المحفوظة. أدخلها مرة أخرى.",
			"nothing_due": "لا يوجد مبلغ مستحق على هذه الفاتورة.",
			"nothing_to_resolve": "لا يوجد ما يحتاج إلى معالجة."
		}
	}
}
```

Locale areas are picked up by `import.meta.glob("../locales/*/*.json")` in `src/lib/i18n.ts`, so the new files need no registration.

`dashboard/src/locales/{en,ar}/billing.json`:
- under `billing.methods`, add `"stripe": "Stripe"` and `"paypal": "PayPal"` (Arabic: `"stripe": "Stripe"`, `"paypal": "PayPal"`);
- under `billing.payments`, add:
  - en: `"fee": "fee {{amount}}"`, `"refunded": "Refunded"`, `"refund": "Mark refunded"`, `"refundTitle": "Mark this payment refunded"`, `"refundBody": "It stops counting toward the invoice and revenue. No money is sent back by Etqan."`, `"refundDone": "Payment marked refunded"`;
  - ar: `"fee": "رسوم {{amount}}"`, `"refunded": "مستردة"`, `"refund": "تحديد كمستردة"`, `"refundTitle": "تحديد هذه الدفعة كمستردة"`, `"refundBody": "لن تُحتسب ضمن الفاتورة والإيرادات. لا تُعيد إتقان أي أموال."`, `"refundDone": "تم تحديد الدفعة كمستردة"`.
- **Billing's 409 codes** are read from the shared `errors.json` (`codeKey(code)` → `errors.<code>`). Add two
  lines to its existing `"billing"` object in both languages. The object is billing's, and billing is B3's:
  - en: `"already_refunded": "This payment is already refunded."`, `"online_payment": "An online payment can be refunded, not deleted."`;
  - ar: `"already_refunded": "هذه الدفعة مستردة مسبقًا."`, `"online_payment": "الدفعة الإلكترونية تُسترد ولا تُحذف."`.
- **Gateways' codes** (`gateways.no_key`, `gateways.bad_key`, `gateways.nothing_due`,
  `gateways.nothing_to_resolve`) are translated by a gateways helper from `gateways.json`, as B3a did
  for finance, so `errors.json` gains nothing else. Add to `dashboard/src/features/gateways/errors.ts`:

```ts
import type { TFunction } from "i18next";
import { errorText } from "@/lib/form-errors";
import { parseApiError } from "@/features/identity/api";

const PREFIX = "gateways.";

/** A gateways error code's own wording (gateways.json), else the shared one. */
export function gatewaysErrorText(error: unknown, t: TFunction): string {
	const code = parseApiError(error).code;
	return code?.startsWith(PREFIX)
		? t(`gateways.errors.${code.slice(PREFIX.length)}`)
		: errorText(error, t);
}
```

  `parseApiError` is the helper `features/finance/bits.tsx` uses (`@/features/identity/api`). Export
  `gatewaysErrorText` from `index.ts`. Add `errors.test.ts`:
  - an `AxiosError` with `{data: {detail: "x", code: "gateways.nothing_due"}, status: 409}` reads
    "Nothing is due on this invoice.";
  - a `billing.invoice_void` one falls back to `errorText`.

`dashboard/src/features/identity/schemas.ts`, `FeatureCode`: after `| "expenses"`, add

```ts
	// Phase B3, slice B3b.
	| "online_payments"
```

`dashboard/src/features/shell/nav.ts`:
- import `CreditCard` and `MonitorSmartphone` from `lucide-react` (alphabetical);
- under the B3 marker, after the donations item, add:

```ts
	// B3b: payments families make online, and the academy's Stripe keys.
	office(
		"/billing/checkouts",
		"gateways.nav.checkouts",
		MonitorSmartphone,
		"billing",
		"checkout.view_any",
		"online_payments",
	),
	office(
		"/settings/gateways",
		"gateways.nav.settings",
		CreditCard,
		"settings",
		"gateway.view",
		"online_payments",
	),
```

- [ ] **Step 6: Run the tests**

Run: `npx pnpm@10 exec vitest run src/features/gateways src/features/shell src/features/finance src/features/billing src/locales`
Expected: all pass. The locale parity test checks `gateways.json` en/ar key for key.

Then: `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint`

- [ ] **Step 7: Commit**

```bash
npx pnpm@10 exec biome check --write src e2e
git -C dashboard add src
git -C dashboard commit -m "feat(gateways): dashboard module, translations and nav"
```

---
### Task 11: Settings → Payment gateways

**Files:**
- Create: `dashboard/src/features/gateways/GatewaySettingsPage.tsx`, `GatewaySettingsPage.test.tsx`
- Create: `dashboard/src/routes/_authed/settings.gateways.tsx`
- Modify: `dashboard/src/features/gateways/index.ts`
- Modify: `dashboard/src/routes/permissions.test.ts`:
  - `FEATURE_SCREENS` gains `"/_authed/settings/gateways": "online_payments"`;
  - `FEATURE_WORDS` gains `|gateways|checkouts`
- Generated: `dashboard/src/routeTree.gen.ts` (`vite build`)

**Interfaces:**
- Consumes: `useGatewaySettings`, `gatewaysApi.saveSettings`, `useGatewaysMutation`, `stripeFormSchema`, `feeFormSchema`, `stripePatch`, `toBasisPoints`, `toPercent`, `gatewaysErrorText` (Task 10).
- Produces: `GatewaySettingsPage`.

- [ ] **Step 1: Write the failing test**

`dashboard/src/features/gateways/GatewaySettingsPage.test.tsx`:

```tsx
import { act, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { staffMe } from "@/test/access-fixtures";
import { gatewaySettings } from "@/test/gateways-fixtures";
import { renderWithRouter } from "@/test/render";
import { gatewaysApi } from "./api";
import { GatewaySettingsPage } from "./GatewaySettingsPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		gatewaysApi: {
			...actual.gatewaysApi,
			settings: vi.fn(),
			saveSettings: vi.fn(),
		},
	};
});

describe("GatewaySettingsPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(gatewaysApi.settings).mockResolvedValue(gatewaySettings());
		vi.mocked(gatewaysApi.saveSettings).mockResolvedValue(gatewaySettings());
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("shows the saved state of each secret, never a secret", async () => {
		renderWithRouter(<GatewaySettingsPage />);
		expect(await screen.findByLabelText("Publishable key")).toHaveValue(
			"pk_test_demo",
		);
		expect(screen.getByLabelText("Secret key")).toHaveValue("");
		expect(screen.getAllByText(/Saved ✓/)).toHaveLength(2);
		expect(
			screen.getByText(
				"http://demo.etqan.localhost/api/v1/gateways/webhooks/stripe/",
			),
		).toBeVisible();
		expect(screen.getByText("checkout.session.completed")).toBeVisible();
	});

	it("saves only what was typed: a blank secret is kept", async () => {
		const user = userEvent.setup();
		renderWithRouter(<GatewaySettingsPage />);
		const key = await screen.findByLabelText("Publishable key");
		await user.clear(key);
		await user.type(key, "pk_test_new");
		await user.click(screen.getAllByRole("button", { name: "Save" })[0]);
		await waitFor(() =>
			expect(gatewaysApi.saveSettings).toHaveBeenCalledWith({
				stripe: { enabled: true, mode: "test", public_key: "pk_test_new" },
			}),
		);
	});

	it("saves the fee as basis points and refuses more than 20 %", async () => {
		const user = userEvent.setup();
		renderWithRouter(<GatewaySettingsPage />);
		const percent = await screen.findByLabelText("Percentage");
		expect(percent).toHaveValue("5");
		await user.clear(percent);
		await user.type(percent, "25");
		await user.click(screen.getAllByRole("button", { name: "Save" })[1]);
		expect(
			await screen.findByText("Enter a percentage from 0 to 20."),
		).toBeVisible();
		await user.clear(percent);
		await user.type(percent, "2.5");
		await user.click(screen.getAllByRole("button", { name: "Save" })[1]);
		await waitFor(() =>
			expect(gatewaysApi.saveSettings).toHaveBeenCalledWith({
				fee: { enabled: true, basis_points: 250 },
			}),
		);
	});

	it("puts a refused key on its field and a 503 in words", async () => {
		const user = userEvent.setup();
		vi.mocked(gatewaysApi.saveSettings)
			.mockRejectedValueOnce(
				new AxiosError("Bad", "400", undefined, undefined, {
					status: 400,
					data: { secret: ["This key does not belong to a test-mode Stripe account."] },
				} as never),
			)
			.mockRejectedValueOnce(
				new AxiosError("No", "503", undefined, undefined, {
					status: 503,
					data: { detail: "x", code: "gateways.no_key" },
				} as never),
			);
		renderWithRouter(<GatewaySettingsPage />);
		await user.type(await screen.findByLabelText("Secret key"), "sk_live_x");
		const save = screen.getAllByRole("button", { name: "Save" })[0];
		await user.click(save);
		expect(
			await screen.findByText(
				"This key does not belong to a test-mode Stripe account.",
			),
		).toBeVisible();
		await user.click(save);
		expect(
			await screen.findByText(
				"This server cannot store payment keys yet. Contact Etqan.",
			),
		).toBeVisible();
	});

	it("is read-only for staff without gateway.update", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("gateway.view")}>
				<GatewaySettingsPage />
			</CanProvider>,
		);
		expect(await screen.findByLabelText("Publishable key")).toBeDisabled();
		expect(screen.queryByRole("button", { name: "Save" })).toBeNull();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderWithRouter(<GatewaySettingsPage />);
		expect(await screen.findByLabelText("المفتاح العام")).toBeVisible();
		expect(screen.getByText("رسوم الخدمة")).toBeVisible();
	});
});
```

In `dashboard/src/routes/permissions.test.ts`:
- add `"/_authed/settings/gateways": "online_payments",` to `FEATURE_SCREENS`;
- change `FEATURE_WORDS` to `/families|parents|reports|invoices|supervision|expenses|donations|gateways|checkouts/`.

- [ ] **Step 2: Run it to see it fail**

Run: `npx pnpm@10 exec vitest run src/features/gateways/GatewaySettingsPage.test.tsx`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement**

`dashboard/src/features/gateways/GatewaySettingsPage.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useController, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Checkbox,
	Field,
	Input,
	Select,
	Spinner,
	SubmitButton,
	toast,
} from "@/ui";
import { gatewaysApi } from "./api";
import { gatewaysErrorText } from "./errors";
import { useGatewaySettings, useGatewaysMutation } from "./queries";
import {
	type FeeForm,
	feeFormSchema,
	type GatewaySettings,
	type StripeForm,
	stripeFormSchema,
	stripePatch,
	toBasisPoints,
	toPercent,
} from "./schemas";

function useSave() {
	const { t } = useTranslation();
	const save = useGatewaysMutation(gatewaysApi.saveSettings);
	return {
		save,
		saved: () => toast({ description: t("gateways.settings.saved_toast"), variant: "success" }),
	};
}

function SecretHint({ saved }: { saved: boolean }) {
	const { t } = useTranslation();
	return (
		<p className="text-sm text-muted-foreground">
			{saved ? t("gateways.settings.saved") : t("gateways.settings.notSet")}
		</p>
	);
}

function WebhookUrl({ url }: { url: string }) {
	const { t } = useTranslation();
	const [copied, setCopied] = useState(false);
	return (
		<div className="flex flex-col gap-1.5">
			<span className="text-sm font-medium">{t("gateways.settings.webhookUrl")}</span>
			<div className="flex flex-wrap items-center gap-2">
				<code dir="ltr" className="break-all rounded bg-muted px-2 py-1 text-sm">
					{url}
				</code>
				<Button
					type="button"
					size="sm"
					variant="outline"
					onClick={() => {
						void navigator.clipboard?.writeText(url);
						setCopied(true);
					}}
				>
					{copied ? t("gateways.settings.copied") : t("gateways.settings.copy")}
				</Button>
			</div>
		</div>
	);
}

function StripeCard({ data, editable }: { data: GatewaySettings; editable: boolean }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const { save, saved } = useSave();
	const [failure, setFailure] = useState("");
	const {
		register,
		control,
		handleSubmit,
		setError,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<StripeForm>({
		resolver: zodResolver(stripeFormSchema),
		disabled: !editable,
		defaultValues: {
			enabled: data.stripe.enabled,
			mode: data.stripe.mode,
			public_key: data.stripe.public_key,
			secret: "",
			webhook_secret: "",
		},
	});
	const enabled = useController({ control, name: "enabled" });

	async function onSubmit(values: StripeForm) {
		setFailure("");
		try {
			const fresh = await save.mutateAsync({ stripe: stripePatch(values) });
			reset({
				enabled: fresh.stripe.enabled,
				mode: fresh.stripe.mode,
				public_key: fresh.stripe.public_key,
				secret: "",
				webhook_secret: "",
			});
			saved();
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (Object.keys(parsed.fieldErrors).length === 0) {
				setFailure(gatewaysErrorText(error, t));
			}
		}
	}

	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("gateways.settings.stripe")}</CardTitle>
			</CardHeader>
			<CardContent>
				<form onSubmit={handleSubmit(onSubmit)} className="flex max-w-xl flex-col gap-4" noValidate>
					<label htmlFor="stripe_enabled" className="flex items-center gap-2 text-sm">
						<Checkbox
							id="stripe_enabled"
							checked={enabled.field.value}
							disabled={enabled.field.disabled}
							onCheckedChange={enabled.field.onChange}
						/>
						{t("gateways.settings.enabled")}
					</label>
					{errors.enabled?.message ? (
						<p className="text-sm text-destructive">{fieldError(errors.enabled.message)}</p>
					) : null}
					<Field id="stripe_mode" label={t("gateways.settings.mode")} error={fieldError(errors.mode?.message)}>
						<Select {...register("mode")}>
							<option value="test">{t("gateways.settings.modes.test")}</option>
							<option value="live">{t("gateways.settings.modes.live")}</option>
						</Select>
					</Field>
					<Field id="stripe_public_key" label={t("gateways.settings.publicKey")} error={fieldError(errors.public_key?.message)}>
						<Input dir="ltr" autoComplete="off" {...register("public_key")} />
					</Field>
					<Field id="stripe_secret" label={t("gateways.settings.secret")} error={fieldError(errors.secret?.message)}>
						<Input dir="ltr" type="password" autoComplete="new-password" {...register("secret")} />
					</Field>
					<SecretHint saved={data.stripe.has_secret} />
					<Field id="stripe_webhook_secret" label={t("gateways.settings.webhookSecret")} error={fieldError(errors.webhook_secret?.message)}>
						<Input dir="ltr" type="password" autoComplete="new-password" {...register("webhook_secret")} />
					</Field>
					<SecretHint saved={data.stripe.has_webhook_secret} />
					<WebhookUrl url={data.stripe.webhook_url} />
					<div className="flex flex-col gap-1 text-sm">
						<span>{t("gateways.settings.events")}</span>
						<ul className="list-inside list-disc" dir="ltr">
							{data.stripe.events.map((event) => (
								<li key={event}>
									<code>{event}</code>
								</li>
							))}
						</ul>
					</div>
					{failure ? (
						<Alert variant="destructive">
							<AlertDescription>{failure}</AlertDescription>
						</Alert>
					) : null}
					{editable ? (
						<SubmitButton pending={isSubmitting}>{t("gateways.settings.save")}</SubmitButton>
					) : null}
				</form>
			</CardContent>
		</Card>
	);
}

function FeeCard({ data, editable }: { data: GatewaySettings; editable: boolean }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const { save, saved } = useSave();
	const {
		register,
		control,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<FeeForm>({
		resolver: zodResolver(feeFormSchema),
		disabled: !editable,
		defaultValues: {
			enabled: data.fee.enabled,
			percent: toPercent(data.fee.basis_points),
		},
	});
	const enabled = useController({ control, name: "enabled" });

	async function onSubmit(values: FeeForm) {
		try {
			await save.mutateAsync({
				fee: { enabled: values.enabled, basis_points: toBasisPoints(values.percent) },
			});
			saved();
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("gateways.settings.fee")}</CardTitle>
			</CardHeader>
			<CardContent>
				<form onSubmit={handleSubmit(onSubmit)} className="flex max-w-xs flex-col gap-4" noValidate>
					<label htmlFor="fee_enabled" className="flex items-center gap-2 text-sm">
						<Checkbox
							id="fee_enabled"
							checked={enabled.field.value}
							disabled={enabled.field.disabled}
							onCheckedChange={enabled.field.onChange}
						/>
						{t("gateways.settings.feeEnabled")}
					</label>
					<Field id="fee_percent" label={t("gateways.settings.percent")} error={fieldError(errors.percent?.message)}>
						<Input dir="ltr" inputMode="decimal" {...register("percent")} />
					</Field>
					{editable ? (
						<SubmitButton pending={isSubmitting}>{t("gateways.settings.save")}</SubmitButton>
					) : null}
				</form>
			</CardContent>
		</Card>
	);
}

/** B3b §6: the academy's Stripe keys (write-only secrets) and the fee. */
export function GatewaySettingsPage() {
	const { t } = useTranslation();
	const can = useCan();
	const { data, isError } = useGatewaySettings();
	if (isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("errors.generic")}</AlertDescription>
			</Alert>
		);
	}
	if (!data) return <Spinner />;
	const editable = can("gateway.update");
	return (
		<div className="flex flex-col gap-6">
			<StripeCard data={data} editable={editable} />
			<FeeCard data={data} editable={editable} />
		</div>
	);
}
```

`SubmitButton` takes `pending`; `errors.generic` is the shared "Something went wrong" string.

`dashboard/src/routes/_authed/settings.gateways.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { GatewaySettingsPage } from "@/features/gateways";
import { requireOffice } from "@/features/identity/require-admin";
import { PageContainer, PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/settings/gateways")({
	staticData: { permission: "gateway.view", feature: "online_payments" },
	beforeLoad: ({ context }) => requireOffice(context),
	component: function GatewaySettingsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("gateways.nav.settings"));
		return (
			<PageContainer>
				<PageHeader
					title={t("gateways.nav.settings")}
					description={t("gateways.settings.subtitle")}
				/>
				<GatewaySettingsPage />
			</PageContainer>
		);
	},
});
```

Export `GatewaySettingsPage` from `dashboard/src/features/gateways/index.ts`.

- [ ] **Step 4: Regenerate the routes and run the tests**

Run: `npx pnpm@10 exec vite build`, then
`npx pnpm@10 exec vitest run src/features/gateways src/routes`
Expected: all pass. Check the output has no "not wrapped in act".

- [ ] **Step 5: Verify and commit**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint
git -C dashboard add src
git -C dashboard commit -m "feat(gateways): Settings → Payment gateways"
```

---
### Task 12: Pay online, refunds on the invoice page, the return page and the simulator page

**Files:**
- Create: `dashboard/src/features/gateways/PayOnline.tsx`, `PayOnline.test.tsx`, `ReturnPage.tsx`, `ReturnPage.test.tsx`, `SimulatorPage.tsx`, `SimulatorPage.test.tsx`
- Create: `dashboard/src/routes/_authed/pay.return.tsx`, `dashboard/src/routes/_authed/pay.simulate.$checkoutId.tsx`
- Modify: `dashboard/src/features/billing/InvoicePage.tsx`, `InvoicePage.test.tsx`, `schemas.ts` (`completedPayments`)
- Modify: `dashboard/src/routes/_authed/learning.invoices.$invoiceId.tsx` (passes `PayOnline` into the page)
- Modify: `dashboard/src/features/gateways/index.ts`

**Interfaces:**
- Consumes:
  - `gatewaysApi.start`, `gatewaysApi.checkout`, `gatewaysApi.simulate`;
  - `useCheckout`, `useGatewaysMutation`, `go`, `gatewaysErrorText` (Task 10);
  - `billingApi.refund`, `ONLINE_METHODS` (Task 10);
  - `useMe` (`@/features/identity/queries`).
- Produces:
  - `PayOnline({invoice})`;
  - `ReturnPage({checkoutId})`;
  - `SimulatorPage({checkoutId})`;
  - `InvoicePage` gains an optional `actions?: (invoice: InvoiceDetail) => ReactNode`. It renders it in its actions row, so billing never imports gateways.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/gateways/PayOnline.test.tsx`:

```tsx
import { act, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { familyInvoice } from "@/test/billing-fixtures";
import { started } from "@/test/gateways-fixtures";
import { renderWithRouter } from "@/test/render";
import { gatewaysApi } from "./api";
import { PayOnline } from "./PayOnline";
import { go } from "./redirect";

vi.mock("./redirect", () => ({ go: vi.fn() }));
vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		gatewaysApi: { ...actual.gatewaysApi, start: vi.fn() },
	};
});

const payable = familyInvoice({ can_pay_online: ["stripe"] });

describe("PayOnline", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(gatewaysApi.start).mockResolvedValue(started());
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("shows nothing when the invoice can't be paid online", () => {
		const { container } = renderWithRouter(
			<PayOnline invoice={familyInvoice()} />,
		);
		expect(container).toBeEmptyDOMElement();
	});

	it("starts a checkout, shows balance, fee and total, then leaves for Stripe", async () => {
		const user = userEvent.setup();
		renderWithRouter(<PayOnline invoice={payable} />);
		await user.click(
			await screen.findByRole("button", { name: "Pay online with Stripe" }),
		);
		expect(gatewaysApi.start).toHaveBeenCalledWith({
			purpose: "invoice",
			reference_id: 51,
			provider: "stripe",
		});
		const sheet = await screen.findByRole("dialog");
		expect(within(sheet).getByText("EGP 1,000.00")).toBeVisible();
		expect(within(sheet).getByText("EGP 50.00")).toBeVisible();
		expect(within(sheet).getByText("EGP 1,050.00")).toBeVisible();
		expect(go).not.toHaveBeenCalled();
		await user.click(
			within(sheet).getByRole("button", { name: "Continue to Stripe" }),
		);
		expect(go).toHaveBeenCalledWith("https://checkout.stripe.test/c/1");
	});

	it("says why it can't start", async () => {
		const user = userEvent.setup();
		vi.mocked(gatewaysApi.start).mockRejectedValue(
			new AxiosError("No", "409", undefined, undefined, {
				status: 409,
				data: { detail: "x", code: "gateways.nothing_due" },
			} as never),
		);
		renderWithRouter(<PayOnline invoice={payable} />);
		await user.click(
			await screen.findByRole("button", { name: "Pay online with Stripe" }),
		);
		expect(
			await screen.findByText("Nothing is due on this invoice."),
		).toBeVisible();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderWithRouter(<PayOnline invoice={payable} />);
		expect(
			await screen.findByRole("button", { name: "ادفع إلكترونيًا عبر Stripe" }),
		).toBeVisible();
	});
});
```

`dashboard/src/features/gateways/ReturnPage.test.tsx`:

```tsx
import { act, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { identityApi } from "@/features/identity/api";
import i18n from "@/lib/i18n";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { gatewaysApi } from "./api";
import { ReturnPage } from "./ReturnPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		gatewaysApi: { ...actual.gatewaysApi, checkout: vi.fn() },
	};
});

const ID = "6f1c2a8e-0000-4000-8000-000000000001";
const body = (status: string) => ({
	id: ID,
	status,
	applied: status === "completed" ? true : null,
	amount_minor: 100000,
	fee_minor: 5000,
	currency: "EGP",
	purpose: "invoice",
	reference_id: 51,
});
const PATHS = ["/learning/invoices/$invoiceId", "/billing/invoices/$invoiceId"];

describe("ReturnPage", () => {
	beforeEach(() => vi.clearAllMocks());
	afterEach(async () => {
		vi.useRealTimers();
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("waits while pending, then says paid, with the family's invoice link", async () => {
		vi.useFakeTimers({ shouldAdvanceTime: true });
		vi.mocked(gatewaysApi.checkout)
			.mockResolvedValueOnce(body("pending") as never)
			.mockResolvedValue(body("completed") as never);
		renderWithRouter(<ReturnPage checkoutId={ID} />, { extraPaths: PATHS });
		expect(
			await screen.findByText("Still processing. This can take a minute."),
		).toBeVisible();
		await act(async () => {
			vi.advanceTimersByTime(2100);
		});
		expect(await screen.findByText("Paid — thank you.")).toBeVisible();
		expect(
			screen.getByRole("link", { name: "Back to the invoice" }),
		).toHaveAttribute("href", expect.stringContaining("/learning/invoices/51"));
	});

	it("says not paid for a failed or expired checkout", async () => {
		vi.mocked(gatewaysApi.checkout).mockResolvedValue(body("expired") as never);
		renderWithRouter(<ReturnPage checkoutId={ID} />, { extraPaths: PATHS });
		expect(await screen.findByText("Not paid.")).toBeVisible();
	});

	it("says it can't find a missing checkout", async () => {
		renderWithRouter(<ReturnPage checkoutId={undefined} />, {
			extraPaths: PATHS,
		});
		expect(
			await screen.findByText("We could not find this payment."),
		).toBeVisible();
	});
});
```

`useMe` reads `identityApi.me`. Mock it as `routes/_authed/index.test.tsx` does, and answer per case:

```tsx
vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { ...actual.identityApi, me: vi.fn() } };
});
const parent = { id: 31, email: "p@x.test", full_name: "Omar", role: "parent", profiles: [] };
// beforeEach: vi.mocked(identityApi.me).mockResolvedValue(parent as never);
```

Add one office case:
- `vi.mocked(identityApi.me).mockResolvedValue(staffMe("checkout.view_any"))`;
- `gatewaysApi.checkout` answers `body("completed")`;
- the "Back to the invoice" link's `href` contains `/billing/invoices/51`.

`dashboard/src/features/gateways/SimulatorPage.test.tsx`:

```tsx
import { act, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { gatewaysApi } from "./api";
import { SimulatorPage } from "./SimulatorPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		gatewaysApi: { ...actual.gatewaysApi, checkout: vi.fn(), simulate: vi.fn() },
	};
});

const ID = "6f1c2a8e-0000-4000-8000-000000000001";

describe("SimulatorPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(gatewaysApi.checkout).mockResolvedValue({
			id: ID,
			status: "pending",
			applied: null,
			amount_minor: 100000,
			fee_minor: 5000,
			currency: "EGP",
			purpose: "invoice",
			reference_id: 51,
		} as never);
		vi.mocked(gatewaysApi.simulate).mockResolvedValue({ status: "completed" });
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("posts the chosen outcome and goes to the return page", async () => {
		const user = userEvent.setup();
		const { router } = renderWithRouter(<SimulatorPage checkoutId={ID} />, {
			extraPaths: ["/pay/return"],
		});
		expect(await screen.findByText("Simulated payment")).toBeVisible();
		await user.click(screen.getByRole("button", { name: "Pay" }));
		expect(gatewaysApi.simulate).toHaveBeenCalledWith({ id: ID, outcome: "pay" });
		await vi.waitFor(() =>
			expect(router.state.location.pathname).toBe("/pay/return"),
		);
	});
});
```

`renderWithRouter` returns `{ client, router, ...view }`.

In `dashboard/src/features/billing/InvoicePage.test.tsx`, add:

```tsx
	it("refunds a payment, and never deletes an online one", async () => {
		const user = userEvent.setup();
		const card = paymentRow({
			id: 62,
			method: "stripe",
			fee_minor: 5000,
			transaction_number: "pi_123",
			reference: "",
		});
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({ payments: [paymentRow(), card] }),
		);
		vi.mocked(billingApi.refund).mockResolvedValue(invoiceDetail());
		renderPage();
		const online = (await screen.findByText(/pi_123/)).closest("li") as HTMLElement;
		expect(within(online).getByText(/Stripe/)).toBeVisible();
		expect(within(online).getByText(/fee EGP 50\.00/)).toBeVisible();
		expect(within(online).queryByRole("button", { name: /Delete/ })).toBeNull();
		await user.click(within(online).getByRole("button", { name: "Mark refunded" }));
		await user.click(
			within(await screen.findByRole("alertdialog")).getByRole("button", {
				name: "Mark this payment refunded",
			}),
		);
		expect(billingApi.refund).toHaveBeenCalledWith(62);
	});

	it("shows a refunded payment as refunded, with no actions", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({
				payments: [paymentRow({ status: "refunded", refunded_at: "2026-06-03T00:00:00Z" })],
			}),
		);
		renderPage();
		const row = (await screen.findByText("Refunded")).closest("li") as HTMLElement;
		expect(within(row).queryByRole("button", { name: "Mark refunded" })).toBeNull();
	});

	it("renders the caller's actions (Pay online) in the actions row", async () => {
		renderWithRouter(
			<InvoicePage
				invoiceId="51"
				admin={false}
				actions={(invoice) => <span>pay {invoice.number}</span>}
			/>,
			{ extraPaths: [PRINT, SUBSCRIPTION] },
		);
		expect(await screen.findByText("pay INV-000051")).toBeVisible();
	});
```

Add `refund: vi.fn()` to that file's `billingApi` mock. As with deletes there, the confirm button in the `alertdialog` carries the dialog's title.

- [ ] **Step 2: Run them to see them fail**

Run: `npx pnpm@10 exec vitest run src/features/gateways src/features/billing`
Expected: failures (missing components, refund action).

- [ ] **Step 3: Implement**

`dashboard/src/features/gateways/PayOnline.tsx`:

```tsx
import { useMutation } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import type { InvoiceDetail } from "@/features/billing/schemas";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
} from "@/ui";
import { gatewaysApi } from "./api";
import { gatewaysErrorText } from "./errors";
import { go } from "./redirect";
import type { Provider, StartedCheckout } from "./schemas";

const NAMES: Record<Provider, string> = { stripe: "Stripe" };

/** B3b §6: a family pays an invoice's balance online. The checkout is
 * started first, so the sheet shows the server's own fee and total. */
export function PayOnline({ invoice }: { invoice: InvoiceDetail }) {
	const { t } = useTranslation();
	const start = useMutation({ mutationFn: gatewaysApi.start });
	const [sheet, setSheet] = useState<(StartedCheckout & { provider: Provider }) | null>(null);
	const [failure, setFailure] = useState("");
	if (invoice.can_pay_online.length === 0) return null;

	async function begin(provider: Provider) {
		setFailure("");
		try {
			const result = await start.mutateAsync({
				purpose: "invoice",
				reference_id: invoice.id,
				provider,
			});
			setSheet({ ...result, provider });
		} catch (error) {
			setFailure(gatewaysErrorText(error, t));
		}
	}

	return (
		<>
			{invoice.can_pay_online.map((provider) => (
				<Button
					key={provider}
					size="sm"
					disabled={start.isPending}
					onClick={() => void begin(provider)}
				>
					{t("gateways.pay.button", { provider: NAMES[provider] })}
				</Button>
			))}
			{failure ? (
				<Alert variant="destructive">
					<AlertDescription>{failure}</AlertDescription>
				</Alert>
			) : null}
			<Dialog open={sheet !== null} onOpenChange={(open) => !open && setSheet(null)}>
				{sheet ? (
					<DialogContent>
						<DialogTitle>{t("gateways.pay.title")}</DialogTitle>
						<DialogDescription className="sr-only">
							{t("gateways.pay.title")}
						</DialogDescription>
						<dl className="grid grid-cols-2 gap-2 text-sm">
							<dt>{t("gateways.pay.balance")}</dt>
							<dd><Money minor={sheet.amount_minor} currency={sheet.currency} /></dd>
							<dt>{t("gateways.pay.fee")}</dt>
							<dd><Money minor={sheet.fee_minor} currency={sheet.currency} /></dd>
							<dt className="font-medium">{t("gateways.pay.total")}</dt>
							<dd className="font-medium">
								<Money minor={sheet.amount_minor + sheet.fee_minor} currency={sheet.currency} />
							</dd>
						</dl>
						<DialogFooter>
							<Button variant="outline" onClick={() => setSheet(null)}>
								{t("gateways.pay.cancel")}
							</Button>
							<Button onClick={() => go(sheet.redirect_url)}>
								{t("gateways.pay.continue", { provider: NAMES[sheet.provider] })}
							</Button>
						</DialogFooter>
					</DialogContent>
				) : null}
			</Dialog>
		</>
	);
}
```

`dashboard/src/features/gateways/ReturnPage.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useMe } from "@/features/identity/queries";
import { Alert, AlertDescription, Button, Card, CardContent, Spinner } from "@/ui";
import { useCheckout } from "./queries";

const POLL_FOR_MS = 60_000;

/** B3b §4.5: polls every 2 s for up to a minute, then lets the payer refresh. */
export function ReturnPage({ checkoutId }: { checkoutId: string | undefined }) {
	const { t } = useTranslation();
	const { data: me } = useMe();
	const [polling, setPolling] = useState(true);
	useEffect(() => {
		const timer = setTimeout(() => setPolling(false), POLL_FOR_MS);
		return () => clearTimeout(timer);
	}, []);
	const { data, isError, refetch, isFetching } = useCheckout(checkoutId, { poll: polling });
	if (checkoutId === undefined || isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("gateways.return.missing")}</AlertDescription>
			</Alert>
		);
	}
	if (!data) return <Spinner />;
	const office = me?.role === "admin" || me?.role === "staff";
	const invoiceId = String(data.reference_id);
	const back =
		data.purpose === "invoice" ? (
			<Button asChild variant="outline" size="sm">
				{office ? (
					<Link to="/billing/invoices/$invoiceId" params={{ invoiceId }}>
						{t("gateways.return.back")}
					</Link>
				) : (
					<Link to="/learning/invoices/$invoiceId" params={{ invoiceId }}>
						{t("gateways.return.back")}
					</Link>
				)}
			</Button>
		) : null;
	return (
		<Card>
			<CardContent className="flex flex-col items-start gap-4 pt-6">
				{data.status === "completed" ? (
					<p className="text-success">{t("gateways.return.paid")}</p>
				) : data.status === "pending" ? (
					<>
						<p>{t("gateways.return.processing")}</p>
						<Button size="sm" disabled={isFetching} onClick={() => void refetch()}>
							{t("gateways.return.refresh")}
						</Button>
					</>
				) : (
					<p className="text-destructive">{t("gateways.return.notPaid")}</p>
				)}
				{back}
			</CardContent>
		</Card>
	);
}
```

`text-success` is a semantic token (the toast uses it).

`dashboard/src/features/gateways/SimulatorPage.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import { Alert, AlertDescription, Button, Card, CardContent, CardHeader, CardTitle, Spinner } from "@/ui";
import { gatewaysApi } from "./api";
import { gatewaysErrorText } from "./errors";
import { useCheckout, useGatewaysMutation } from "./queries";

const OUTCOMES = ["pay", "fail", "expire"] as const;

/** B-12: plays Stripe's hosted page in development and CI. */
export function SimulatorPage({ checkoutId }: { checkoutId: string }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { data, isError, error } = useCheckout(checkoutId, { poll: false });
	const simulate = useGatewaysMutation(gatewaysApi.simulate);
	if (isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{gatewaysErrorText(error, t)}</AlertDescription>
			</Alert>
		);
	}
	if (!data) return <Spinner />;
	return (
		<Card className="max-w-md">
			<CardHeader className="border-b border-border">
				<CardTitle>{t("gateways.simulate.title")}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-4 pt-4">
				<p className="text-sm text-muted-foreground">{t("gateways.simulate.note")}</p>
				<p className="text-lg font-medium">
					<Money minor={data.amount_minor + data.fee_minor} currency={data.currency} />
				</p>
				<div className="flex flex-wrap gap-2">
					{OUTCOMES.map((outcome) => (
						<Button
							key={outcome}
							variant={outcome === "pay" ? "default" : "outline"}
							disabled={simulate.isPending}
							onClick={async () => {
								await simulate.mutateAsync({ id: checkoutId, outcome });
								await navigate({ to: "/pay/return", search: { checkout: checkoutId } });
							}}
						>
							{t(`gateways.simulate.${outcome}`)}
						</Button>
					))}
				</div>
			</CardContent>
		</Card>
	);
}
```

`dashboard/src/routes/_authed/pay.return.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { ReturnPage } from "@/features/gateways";
import { PageContainer, PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/pay/return")({
	// No feature (plan D16): money may arrive after the switch goes off.
	validateSearch: (search: Record<string, unknown>) => ({
		checkout: typeof search.checkout === "string" ? search.checkout : undefined,
	}),
	component: function PayReturnRoute() {
		const { t } = useTranslation();
		const { checkout } = Route.useSearch();
		usePageTitle(t("gateways.return.title"));
		return (
			<PageContainer>
				<PageHeader title={t("gateways.return.title")} />
				<ReturnPage checkoutId={checkout} />
			</PageContainer>
		);
	},
});
```

`dashboard/src/routes/_authed/pay.simulate.$checkoutId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SimulatorPage } from "@/features/gateways";
import { PageContainer } from "@/ui";

export const Route = createFileRoute("/_authed/pay/simulate/$checkoutId")({
	component: function PaySimulateRoute() {
		const { t } = useTranslation();
		const { checkoutId } = Route.useParams();
		usePageTitle(t("gateways.simulate.title"));
		return (
			<PageContainer>
				<SimulatorPage checkoutId={checkoutId} />
			</PageContainer>
		);
	},
});
```

Export `PayOnline`, `ReturnPage` and `SimulatorPage` from `dashboard/src/features/gateways/index.ts`.

**Billing changes:**

1. `dashboard/src/features/billing/schemas.ts`, append:

```ts
/** B3b B-9: only completed payments count; a refunded one doesn't. */
export function completedPayments(invoice: InvoiceDetail): Payment[] {
	return invoice.payments.filter((payment) => payment.status !== "refunded");
}
```

2. `dashboard/src/features/billing/InvoicePage.tsx`:
   - `InvoicePage` takes `actions?: (invoice: InvoiceDetail) => ReactNode` (import `ReactNode` from `react`) and passes it to `Actions`. `Actions` renders `{actions?.(invoice)}` first in its `<section>`.
   - The void button's condition `invoice.payments.length === 0` becomes `completedPayments(invoice).length === 0`.
   - In `Payments`, each `<li>` shows:
     - the method label (`t(\`billing.methods.${payment.method}\`)`, which now covers stripe and paypal);
     - when `payment.fee_minor > 0`, `· {t("billing.payments.fee", { amount: formatMoney(payment.fee_minor, invoice.currency, i18n.language) })}` after the amount;
     - `payment.transaction_number` (in `dir="ltr"`) next to the reference;
     - `<StatusChip tone="neutral">{t("billing.payments.refunded")}</StatusChip>` when `payment.status === "refunded"`.
   - Actions per row:
     - **Delete** shows only when `canDelete` and the method is not in `ONLINE_METHODS`. A refunded manual payment can still be deleted.
     - **Mark refunded** shows when `admin && payment.status === "completed" && can("payment.update")`. It is a `Confirm` with `action={t("billing.payments.refund")}`, `title={t("billing.payments.refundTitle")}` and `body={t("billing.payments.refundBody")}`. It calls `useBillingMutation(billingApi.refund)`, with the success toast `t("billing.payments.refundDone")` and `errorText` on error.
   - In `EditInvoiceDialog.tsx`, `const paidInto = invoice.payments.length > 0;` becomes `completedPayments(invoice).length > 0`, matching the server.

3. `dashboard/src/routes/_authed/learning.invoices.$invoiceId.tsx`: import `PayOnline` from `@/features/gateways` and render

```tsx
<InvoicePage
	invoiceId={invoiceId}
	admin={false}
	actions={(invoice) => <PayOnline invoice={invoice} />}
/>
```

- [ ] **Step 4: Regenerate routes and run the tests**

Run: `npx pnpm@10 exec vite build`, then
`npx pnpm@10 exec vitest run src/features/gateways src/features/billing src/routes`
Expected: all pass, with 0 "not wrapped in act" from these files.

- [ ] **Step 5: Verify and commit**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint
git -C dashboard add src
git -C dashboard commit -m "feat(gateways): Pay online, refunds on the invoice, return and simulator pages"
```

---
### Task 13: Billing → Online payments (the checkouts list) and the `/billing` landing

**Files:**
- Create: `dashboard/src/features/gateways/CheckoutsList.tsx`, `CheckoutsList.test.tsx`
- Create: `dashboard/src/routes/_authed/billing.checkouts.tsx`
- Modify: `dashboard/src/features/gateways/index.ts`
- Modify: `dashboard/src/features/finance/landing.ts`, `landing.test.ts` (checkouts last)
- Modify: `dashboard/src/routes/permissions.test.ts` (`FEATURE_SCREENS` gains `"/_authed/billing/checkouts": "online_payments"`)

**Interfaces:**
- Consumes:
  - `useCheckouts`, `gatewaysApi.resolve`, `useGatewaysMutation`, `gatewaysErrorText`, `CHECKOUT_STATUSES`, `CheckoutRow` (Task 10);
  - `useListParams`, `pageCount`, `DateFilter` from `@/features/finance/shared`;
  - billing's `Money`.
- Produces: `CheckoutsList`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/gateways/CheckoutsList.test.tsx`:

```tsx
import { act, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { staffMe } from "@/test/access-fixtures";
import { checkoutRow } from "@/test/gateways-fixtures";
import { renderWithRouter } from "@/test/render";
import { page } from "@/test/scheduling-fixtures";
import { gatewaysApi } from "./api";
import { CheckoutsList } from "./CheckoutsList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		gatewaysApi: { ...actual.gatewaysApi, checkouts: vi.fn(), resolve: vi.fn() },
	};
});

const stuck = checkoutRow();
const fine = checkoutRow({
	id: "6f1c2a8e-0000-4000-8000-000000000002",
	applied: true,
	attention: "",
	transaction_number: "pi_ok",
	description: "INV-000052",
});

function lastParams() {
	return vi.mocked(gatewaysApi.checkouts).mock.calls.at(-1)?.[0];
}

describe("CheckoutsList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(gatewaysApi.checkouts).mockResolvedValue(page([stuck, fine]));
		vi.mocked(gatewaysApi.resolve).mockResolvedValue({
			...stuck,
			resolved_at: "2026-06-02T00:00:00Z",
		});
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("lists checkouts with why one needs attention, and resolves it", async () => {
		const user = userEvent.setup();
		renderWithRouter(<CheckoutsList />);
		const table = await screen.findByRole("table");
		const row = within(table).getByRole("row", { name: /INV-000051/ });
		expect(
			within(row).getByText("The invoice was void when the money arrived."),
		).toBeVisible();
		expect(within(row).getByText("pi_123")).toBeVisible();
		await user.click(within(row).getByRole("button", { name: "Mark resolved" }));
		expect(gatewaysApi.resolve).toHaveBeenCalledWith(stuck.id);
		const okRow = within(table).getByRole("row", { name: /INV-000052/ });
		expect(within(okRow).queryByRole("button", { name: "Mark resolved" })).toBeNull();
	});

	it("filters by the attention tab, status and dates", async () => {
		const user = userEvent.setup();
		renderWithRouter(<CheckoutsList />);
		await screen.findByRole("table");
		await user.click(screen.getByRole("tab", { name: "Needs attention" }));
		expect(lastParams()).toMatchObject({ attention: "open", page: 1 });
		await user.selectOptions(screen.getByLabelText("Status"), "completed");
		expect(lastParams()).toMatchObject({ status: "completed", attention: "open" });
	});

	it("hides Resolve from staff without checkout.update", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("checkout.view_any")}>
				<CheckoutsList />
			</CanProvider>,
		);
		await screen.findByRole("table");
		expect(screen.queryByRole("button", { name: "Mark resolved" })).toBeNull();
	});

	it("shows an empty list and a load error", async () => {
		vi.mocked(gatewaysApi.checkouts).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<CheckoutsList />);
		expect(await screen.findByText("No online payments yet.")).toBeVisible();
		unmount();
		vi.mocked(gatewaysApi.checkouts).mockRejectedValueOnce(new Error("down"));
		renderWithRouter(<CheckoutsList />);
		expect(
			await screen.findByText("Online payments could not be loaded."),
		).toBeVisible();
	});

	it("reads in Arabic", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderWithRouter(<CheckoutsList />);
		const table = await screen.findByRole("table");
		expect(within(table).getAllByText("مكتملة").length).toBeGreaterThan(0);
	});
});
```

`dashboard/src/features/finance/landing.test.ts`, add:

```ts
	it("lands on online payments last", () => {
		expect(
			billingLanding({
				...staffMe("checkout.view_any"),
				features: ["online_payments"],
			}),
		).toBe("/billing/checkouts");
	});
```

`dashboard/src/routes/permissions.test.ts`: add `"/_authed/billing/checkouts": "online_payments",` to `FEATURE_SCREENS`.

- [ ] **Step 2: Run them to see them fail**

Run: `npx pnpm@10 exec vitest run src/features/gateways/CheckoutsList.test.tsx src/features/finance/landing.test.ts`
Expected: FAIL.

- [ ] **Step 3: Implement**

`dashboard/src/features/gateways/CheckoutsList.tsx`:

```tsx
import { MonitorSmartphone } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { Money } from "@/features/billing";
import { DateFilter, pageCount, useListParams } from "@/features/finance/shared";
import { useCan } from "@/features/identity/permissions";
import { formatDay } from "@/lib/zoned-time";
import { Alert, AlertDescription, Button, EmptyState, Select, Spinner, StatusChip, toast } from "@/ui";
import { gatewaysApi } from "./api";
import { gatewaysErrorText } from "./errors";
import { useCheckouts, useGatewaysMutation } from "./queries";
import { CHECKOUT_STATUSES, type CheckoutRow } from "./schemas";

function ResolveButton({ row }: { row: CheckoutRow }) {
	const { t } = useTranslation();
	const resolve = useGatewaysMutation(gatewaysApi.resolve);
	return (
		<Button
			size="sm"
			variant="outline"
			disabled={resolve.isPending}
			onClick={() =>
				resolve.mutate(row.id, {
					onSuccess: () =>
						toast({ description: t("gateways.checkouts.resolved"), variant: "success" }),
					onError: (error) =>
						toast({ description: gatewaysErrorText(error, t), variant: "destructive" }),
				})
			}
		>
			{t("gateways.checkouts.resolve")}
		</Button>
	);
}

/** B3b §4.8: every online checkout; the "Needs attention" tab lists money
 * that arrived but could not be applied, until an admin resolves it. */
export function CheckoutsList() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const { params, page, update, goTo } = useListParams();
	const { data, isPending, isError } = useCheckouts(params);
	const attention = params.attention === "open";
	const columns = ["date", "what", "amount", "fee", "status", "payer", "transaction"] as const;
	return (
		<div className="flex flex-col gap-4">
			<div role="tablist" className="flex gap-2">
				<Button
					role="tab"
					aria-selected={!attention}
					size="sm"
					variant={attention ? "outline" : "default"}
					onClick={() => update({ attention: undefined })}
				>
					{t("gateways.checkouts.all")}
				</Button>
				<Button
					role="tab"
					aria-selected={attention}
					size="sm"
					variant={attention ? "default" : "outline"}
					onClick={() => update({ attention: "open" })}
				>
					{t("gateways.checkouts.attention")}
				</Button>
			</div>
			<div className="flex flex-wrap items-end gap-3">
				<div className="flex flex-col gap-1.5">
					<label htmlFor="checkout-status" className="text-sm font-medium">
						{t("gateways.checkouts.columns.status")}
					</label>
					<Select
						id="checkout-status"
						value={String(params.status ?? "")}
						onChange={(e) => update({ status: e.target.value || undefined })}
					>
						<option value="">{t("gateways.checkouts.all")}</option>
						{CHECKOUT_STATUSES.map((status) => (
							<option key={status} value={status}>
								{t(`gateways.status.${status}`)}
							</option>
						))}
					</Select>
				</div>
				<DateFilter
					id="checkouts-from"
					label={t("finance.list.from")}
					value={String(params.created_from ?? "")}
					onChange={(value) => update({ created_from: value || undefined })}
				/>
				<DateFilter
					id="checkouts-to"
					label={t("finance.list.to")}
					value={String(params.created_to ?? "")}
					onChange={(value) => update({ created_to: value || undefined })}
				/>
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("gateways.checkouts.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<Spinner />
			) : data.results.length === 0 ? (
				<EmptyState icon={MonitorSmartphone} title={t("gateways.checkouts.empty")} />
			) : (
				<div className="overflow-x-auto">
					<table className="w-full text-sm">
						<thead>
							<tr className="border-b border-border">
								{columns.map((column) => (
									<th key={column} className="px-2 py-2 text-start font-medium">
										{t(`gateways.checkouts.columns.${column}`)}
									</th>
								))}
								<th className="px-2 py-2" />
							</tr>
						</thead>
						<tbody>
							{data.results.map((row) => (
								<tr key={row.id} className="border-b border-border align-top">
									<td className="px-2 py-2">{formatDay(row.created_at.slice(0, 10), i18n.language)}</td>
									<td className="px-2 py-2" dir="ltr">{row.description}</td>
									<td className="px-2 py-2"><Money minor={row.amount_minor} currency={row.currency} /></td>
									<td className="px-2 py-2"><Money minor={row.fee_minor} currency={row.currency} /></td>
									<td className="px-2 py-2">
										<div className="flex flex-col gap-1">
											<StatusChip tone={row.status === "completed" ? "live" : "neutral"}>
												{t(`gateways.status.${row.status}`)}
											</StatusChip>
											{row.attention && !row.resolved_at ? (
												<span className="text-destructive">
													{t(`gateways.attention.${row.attention}`)}
												</span>
											) : null}
										</div>
									</td>
									<td className="px-2 py-2">{row.created_by?.full_name ?? ""}</td>
									<td className="px-2 py-2" dir="ltr">{row.transaction_number}</td>
									<td className="px-2 py-2">
										{row.applied === false && !row.resolved_at && can("checkout.update") ? (
											<ResolveButton row={row} />
										) : null}
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

This mirrors `ExpensesList.tsx` (B3a): `Pager` takes `page`, `pages` and `onChange`; `EmptyState` takes `icon` and `title`; the date labels reuse `finance.list.from` and `finance.list.to`.

`dashboard/src/routes/_authed/billing.checkouts.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { CheckoutsList } from "@/features/gateways";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/billing/checkouts")({
	staticData: { permission: "checkout.view_any", feature: "online_payments" },
	component: function CheckoutsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("gateways.nav.checkouts"));
		return (
			<>
				<PageHeader title={t("gateways.nav.checkouts")} />
				<CheckoutsList />
			</>
		);
	},
});
```

`dashboard/src/features/finance/landing.ts`, `BILLING_PAGES`, after the donations entry:

```ts
	{
		to: "/billing/checkouts",
		code: "checkout.view_any",
		feature: "online_payments",
	},
```

Export `CheckoutsList` from `dashboard/src/features/gateways/index.ts`.

- [ ] **Step 4: Regenerate routes and run the tests**

Run: `npx pnpm@10 exec vite build`, then
`npx pnpm@10 exec vitest run src/features/gateways src/features/finance src/routes src/features/shell`
Expected: all pass, with 0 "not wrapped in act" from the new files.

- [ ] **Step 5: Verify and commit**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
git -C dashboard add src
git -C dashboard commit -m "feat(gateways): Billing → Online payments, with Needs attention and Resolve"
```

---
### Task 14: The journey through Caddy

**Files:**
- Create: `dashboard/e2e/b3-online-payments.spec.ts`

**Interfaces:**
- Consumes:
  - the stack (`just dev-backend`), seeded after Task 9: the demo Stripe test account exists and `GATEWAYS_SIMULATE` is on in `local.py`;
  - `manage("set_features", …)` through `e2e/manage.ts`;
  - `acceptInvite` and `login` from `e2e/fixtures.ts`.

- [ ] **Step 1: Write the journey**

`dashboard/e2e/b3-online-payments.spec.ts`:

```ts
import { expect, type Page, test } from "@playwright/test";
import {
	acceptInvite,
	DEMO_ADMIN,
	DEMO_URL,
	expectLoggedIn,
	login,
} from "./fixtures";
import { manage } from "./manage";

/** The invoice page's card header: its number and the status chip only. */
const invoiceHeader = (page: Page, number: string) =>
	page.locator('[data-slot="card-header"]').filter({
		has: page.getByRole("heading", { name: number, exact: true }),
	});

/** A write to the API as the signed-in admin: the CSRF cookie goes back as
 * the header, as the dashboard's axios does (plan D17). */
async function postAsAdmin(page: Page, path: string, data: object) {
	const csrf =
		(await page.context().cookies()).find((c) => c.name === "csrftoken")
			?.value ?? "";
	return page.request.post(`${DEMO_URL}/api/v1/${path}`, {
		headers: { "X-CSRFToken": csrf, Referer: `${DEMO_URL}/app/` },
		data,
	});
}

// B3b spec §9: a parent pays an unpaid invoice online through the offline
// simulator; the return page says paid; the admin sees the Stripe payment
// with its fee, marks it refunded, and the invoice is unpaid again.
test("a parent pays online through the simulator, and the admin refunds it", async ({
	page,
	browser,
}) => {
	manage("set_features", "demo", "--on", "invoices", "online_payments");
	const stamp = Date.now();
	const parent = `E2E Payer ${stamp}`;
	const parentEmail = `e2e-payer-${stamp}@e2e.test`;
	const student = `E2E Payee ${stamp}`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// A parent (invited by email) and their child, as billing.spec.ts does
	await page.goto(`${DEMO_URL}/app/people/parents/new`);
	await page.getByLabel(/^full name/i).fill(parent);
	await page.getByLabel(/^email/i).fill(parentEmail);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/parents\/\d+$/);

	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(student);
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);
	const studentId = Number(page.url().match(/students\/(\d+)$/)?.[1]);
	await page.getByLabel("Find a parent").fill(parent);
	await page
		.getByRole("button", { name: `Link ${parent}`, exact: true })
		.click();
	await expect(
		page.getByRole("button", { name: `Unlink ${parent}`, exact: true }),
	).toBeVisible();

	// 1. An unpaid 500 EGP invoice, billed to the parent (the default payer)
	const dueOn = new Date(Date.now() + 30 * 86_400_000).toISOString().slice(0, 10);
	const created = await postAsAdmin(page, "billing/invoices/", {
		student: studentId,
		amount_minor: 50000,
		currency: "EGP",
		due_on: dueOn,
		description: `E2E online ${stamp}`,
	});
	expect(created.status()).toBe(201);
	const invoice = (await created.json()) as { id: number; number: string };

	// 2. The parent pays it online: confirm sheet, simulator, return page
	const guardian = await acceptInvite(browser, parentEmail, "e2e-Payer-2026", parent);
	await guardian.goto(`${DEMO_URL}/app/learning/invoices/${invoice.id}`);
	await guardian.getByRole("button", { name: "Pay online with Stripe" }).click();
	const sheet = guardian.getByRole("dialog");
	await expect(sheet.getByText("EGP 25.00")).toBeVisible(); // the 5 % fee
	await expect(sheet.getByText("EGP 525.00")).toBeVisible();
	await sheet.getByRole("button", { name: "Continue to Stripe" }).click();
	await expect(guardian).toHaveURL(/\/app\/pay\/simulate\//);
	await guardian.getByRole("button", { name: "Pay", exact: true }).click();
	await expect(guardian).toHaveURL(/\/app\/pay\/return\?checkout=/);
	await expect(guardian.getByText("Paid — thank you.")).toBeVisible();
	await guardian.getByRole("link", { name: "Back to the invoice" }).click();
	await expect(
		invoiceHeader(guardian, invoice.number).getByText("Paid", { exact: true }),
	).toBeVisible();
	await guardian.context().close();

	// 3. The admin sees the Stripe payment and its fee, and refunds it
	await page.goto(`${DEMO_URL}/app/billing/invoices/${invoice.id}`);
	const payment = page.locator("li").filter({ hasText: "Stripe" });
	await expect(payment).toContainText("fee EGP 25.00");
	await payment.getByRole("button", { name: "Mark refunded" }).click();
	await page
		.getByRole("alertdialog")
		.getByRole("button", { name: "Mark this payment refunded" })
		.click();
	await expect(payment).toContainText("Refunded");
	await expect(
		invoiceHeader(page, invoice.number).getByText("Unpaid", { exact: true }),
	).toBeVisible();
});
```

- [ ] **Step 2: Run it against this stream's stack**

The stack must be up and current:
- `just dev-backend`;
- restart the `django`, `dashboard` and `celery_*` services if they were started before Tasks 1–13 (`just rebuild` already rebuilt the images in Task 1; a running container may still hold old code or routes);
- `just migrate`;
- `just seed`.

Run: `just e2e b3-online-payments`
Expected: 1 passed.

Then the whole suite once: `just e2e`.
Expected: all pass. Locally, `families.spec` can race `features.spec` (CI runs serially). If only that one fails, rerun it alone with `just e2e families` and report both results.

- [ ] **Step 3: Commit**

```bash
npx pnpm@10 exec biome check --write src e2e
git -C dashboard add e2e/b3-online-payments.spec.ts
git -C dashboard commit -m "test(e2e): B3b pay an invoice online through the simulator, then refund"
```

---

### Task 15: Slice gates and the spec amendment

**Files:**
- Modify (meta repo): `docs/superpowers/specs/2026-10-03-b3b-online-payments-design.md`, recording plan D1 in §5 and a `## 12. Amendments from planning (Plan 20)` section listing D1, D3, D5–D8, D12 and D19.

- [ ] **Step 1: Amend the spec**

1. In §5's table, change the row `| \`gateways/checkouts/\` | POST | …` to `| \`gateways/checkouts/start/\` | POST | \`online_payments\` | self-service, scoped by the purpose (plan D1) |`.
2. Add the section:

```markdown
## 12. Amendments from planning (Plan 20)

- **Start route** (§4.2, §5): `POST gateways/checkouts/start/`. The route-table test keys code-exempt
  routes by view class, so the self-service start cannot share the coded list's view.
- **Secrets** (B-5): `etqan.platform.secrets`. A missing key raises the platform's new `UnavailableError`
  (503 with a code); dev and tests may derive the key from `SECRET_KEY`.
- **Fee** (B-6, B-7): `(amount × bp + 5000) // 10000`. For a three-digit currency the total is rounded up
  to a multiple of 10 through the fee. With no fee, an amount Stripe cannot take leaves Stripe out of the
  options.
- **Attention codes** (B-11): `invoice_void`, `balance_below_amount`, `amount_mismatch`,
  `currency_mismatch`, `mode_mismatch`, `purpose_unknown`, `reference_missing`, `already_recorded`.
- **Validation errors** are 400s on their fields: `gateways.incomplete` is a 400 on `enabled`,
  `gateways.mode_mismatch` a 400 on `mode`/`public_key`/`secret`, and `gateways.amount_too_small` a 400 on
  `amount_minor`. Codes stay for 409 and 503.
- **`can_pay_online`** is on the invoice detail only, not on list rows.
- **The checkouts list's dates** are UTC days, since gateways reads no academy calendar.
```

3. Commit in the meta worktree:

```bash
git add docs/superpowers/specs/2026-10-03-b3b-online-payments-design.md
git commit -m "docs: B3b spec amendments from Plan 20"
```

- [ ] **Step 2: Run the gates against this stream's stack**

- `just test`. The backend part reports coverage ≥ 80 % (`--cov=etqan`); `test-frontend` is `tsc`.
- `just lint` (ruff, biome, colour check, import contracts).
- `just e2e`.
- From `dashboard/`, `npx pnpm@10 test:coverage`: lines and statements ≥ 80, branches and functions ≥ 70.

All must pass, with the known local `families.spec` race handled as in Task 14.

- [ ] **Step 3: Hand over**

Report to the orchestrator:
- the commits per repo;
- the gate outputs;
- the request the conductor must act on: add `ETQAN_SECRETS_KEY` (a Fernet key, `cryptography.fernet.Fernet.generate_key()`) to the production and staging environment in `infra/`, and leave `GATEWAYS_SIMULATE` unset there. These are meta files the conductor owns (spec §7).
