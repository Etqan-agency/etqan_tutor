# Slice B3b — Online payments (gateway core and Stripe) — Design

**Date:** 2026-10-03
**Status:** Approved by the B3 orchestrator on 2026-10-03, after an independent spec review whose findings
are folded in (orchestration spec PO-3).
**Phase:** B3 (`2026-10-03-b3-money-depth-design.md`), slice B3b. **Requires:** no other phase's slice.
B3a (finance, queued) merges first. This slice changes billing's revenue, which feeds B3a's net profit.
**Builds on:**
- Plan 6 billing (`2026-09-25-billing-design.md`);
- Plan 13 feature switches;
- Plan 12a roles;
- B3a (`2026-10-03-b3a-expenses-donations-design.md`).

**Evidence:**
- audit SYS-003 (switches; Stripe: public key, secret, webhook secret; PayPal: mode, client id, secret,
  currency, locale), §1.3 #6 (payment statuses incl. refunded) and #20, BILL-003 (5 % fee);
- P1 INT-001 (Stripe keys + webhook secret; PaymentIntent ids stored), §9 (an inbound webhook route must
  exist), BR-25 (5 % fee), BR-47 (revenue = completed payment records).

## 1. Goal

An academy connects its own Stripe account. A family opens an unpaid invoice and pays its balance
online, plus a service fee. A verified Stripe event records the payment on the invoice. Admins see every
online checkout, clear the ones that need attention, and can mark a payment refunded.

The gateway core (accounts, encryption, checkouts, purposes, webhooks, simulator) is built so that
PayPal (B3c) and the later purposes (payment links B3g, wallet top-up B3e, add-on sales B7) only plug in.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| B-1 | A new tenant app `etqan.gateways` owns gateway accounts, the fee settings, checkouts and received webhook events. It never imports billing or any other business app. Selling apps call `gateways.services.start_checkout` and register a **purpose** with two callbacks (§4.3). This slice registers `invoice` (billing). | phase B3-2, B3-7; ledger D4 |
| B-2 | **Stripe only in this slice**, through one provider interface. PayPal (Orders v2, capture on return, its own webhook verification) moves to B3c with its account fields, which are observed in the audit: mode, client id, secret, currency, locale. The re-slicing is recorded in the phase spec. | audit SYS-003; spec review (scope) |
| B-3 | **Stripe Checkout** (hosted page) through Stripe's REST API with `httpx`, pinning a `Stripe-Version` header. There is no SDK. Every create call sends `Idempotency-Key` = checkout id. Signatures are verified locally: HMAC-SHA256 of `t.payload` over the raw body, with a 300 s tolerance. | P1 INT-001; [assumed] (client choice) |
| B-4 | **A completion event completes from any state but `completed`.** A verified Stripe completion (`checkout.session.completed` with `payment_status=paid`, or `checkout.session.async_payment_succeeded`) completes the checkout even if it was locally `cancelled`, `expired` or `failed`. Only `completed` is terminal. Money that arrives is never dropped. | spec review (critical) |
| B-5 | **Keys belong to the academy.** The Stripe account holds `enabled`, `mode` (`test`/`live`), the publishable key, the secret key and the webhook signing secret. Secrets are Fernet-encrypted under `ETQAN_SECRETS_KEY` and never returned; the API only says whether each one is set. The mode must match the key prefixes (`pk_test_`/`sk_test_` versus `pk_live_`/`sk_live_`), otherwise 400 `gateways.mode_mismatch`. | audit SYS-003 (keys + webhook secret); phase B3-6; [assumed] (mode field) |
| B-6 | **Currencies** come from a backend exponent table, `etqan.platform.currency` (ISO 4217 minor digits; [assumed] list). Stripe takes a fixed, explicit currency list ([assumed], kept in `gateways`). For the 3-decimal currencies (KWD, BHD, JOD, OMR, TND), the amount sent must be divisible by 10, so the fee rounds up to it. An invoice whose currency Stripe does not take shows no "Pay online". Stripe's "amount too small" error is a 400 `gateways.amount_too_small`. | spec review; [assumed] |
| B-7 | **Service fee:** a gateways setting with `fee_enabled` (default on) and `fee_basis_points` (default 500, 0–2000). The fee is `(amount × bp + 5000) // 10000` minor units (half up), then adjusted per B-6. It is shown before leaving for Stripe as its own line item, stored on the checkout and copied to the payment. A purpose decides whether the fee applies (`Prepared.add_fee`); the invoice purpose follows the setting. | P1 BR-25, BILL-003; phase B3-8; [assumed] (configurable percentage, formula) |
| B-8 | **What is paid:** the invoice's balance at checkout time, in full. One pending checkout per (purpose, reference, provider): starting another one reuses the pending one if its amount and fee are unchanged; otherwise it expires the old session at Stripe and marks it `cancelled`. | spec review; [assumed] |
| B-9 | **Billing's payments gain:** methods `stripe` (and `paypal` for B3c), `fee_minor` (default 0), `transaction_number` (the provider's id, unique per method when set), and `status` (`completed`/`refunded`) with `refunded_at`/`refunded_by`. `MANUAL_PAYMENT_METHODS` becomes the manual subset only, and the manual-payment API accepts only those. Every sum counts `completed` payments only: `paid_of`, the paid subquery and through it the invoice list, overdue and balance, `refuse_if_paid_into`, and `revenue_between`. **Revenue** = `amount_minor + fee_minor` of completed payments. A refund therefore also changes the figures of the month the money was received. | audit §1.3 #6, BILL-001; phase B3-5, B3-10; ledger D5; [assumed] (fee counts as revenue) |
| B-10 | **Online payments cannot be deleted** (409 `billing.online_payment`); they can only be refunded. A refunded manual payment may still be deleted as before. An invoice whose payments are all refunded may be voided and edited again. | spec review; billing spec §4.2 |
| B-11 | **Late, surplus or mismatched money is never lost.** The checkout completes with `applied = false` and an attention reason when any of these holds: the invoice is void; its balance is below the amount; the paid total or currency differs from amount + fee; or the event's `livemode` differs from the account's mode. Admins resolve it (`resolved_at`/`resolved_by`) after handling it by hand. Unapplied money is not revenue (ledger D5). | spec review; [assumed] |
| B-12 | **Offline simulator for development, tests and CI.** It works when the setting `GATEWAYS_SIMULATE` is on (true in `local.py` and `test.py`, false by default) and the account is in `test` mode. Checkouts are then created with `simulated = true` and Stripe is never called. The dashboard simulator page posts the outcome, which produces a correctly signed Stripe-shaped event, handled by the real webhook path. A system check refuses `GATEWAYS_SIMULATE` when `DEBUG` is off; the simulate route also refuses non-simulated checkouts. The meta CI already runs e2e on `config.settings.local`. | [assumed]; orchestration spec §8.1 (no external account in a slice) |
| B-13 | **Features:** `online_payments` (new, under the B3 marker, `default=False`) requires `invoices`. It gates the settings page, the checkouts list and "Pay online". Webhooks keep working while it is off. | phase B3-3, B3-9; spec feature-toggles §3.3 |
| B-14 | **Access:** new resources `gateway` (`view`, `update`) and `checkout` (`view_any`, `update` for resolve). Billing's `payment` resource gains `update` in use, for refunds. That line belongs to billing, which B3 owns, so it is edited in place; a custom role already holding the greyed `payment.update` gains refunds. A checkout for an invoice may be started by its reader as billing scopes it: the payer, the student, a guardian per Plan 6, or office staff with `invoice.view`. Teachers get 404. | spec roles-permissions; billing spec §4.6 |
| B-15 | Live keys are never entered by us; using them is the academy's act. A smoke test with real Stripe test keys is an owner escalation (§8.1) and is not part of this slice. | orchestration spec §8.1 |

## 3. Data

### 3.1 `etqan.gateways`

**GatewayAccount** (one row per provider; this slice uses only `stripe`):

| Field | Notes |
|---|---|
| `provider` | `stripe` (B3c adds `paypal`), unique |
| `enabled` | bool, default false |
| `mode` | `test` or `live`, default `test` |
| `public_key` | ≤ 200 characters |
| `secret_enc`, `webhook_secret_enc` | Fernet tokens, may be blank |
| `updated_by`, `updated_at` | |

An account can be enabled only when its keys and signing secret are set (400 `gateways.incomplete`).

**GatewaySettings** (pk 1): `fee_enabled` (default true) and `fee_basis_points` (default 500).

**Checkout:**

| Field | Notes |
|---|---|
| `id` | UUID, primary key |
| `purpose`, `reference_id` | the registered purpose and its object's id |
| `provider`, `simulated` | |
| `amount_minor`, `fee_minor`, `currency` | amount > 0, fee ≥ 0 |
| `status` | `pending · completed · failed · cancelled · expired` |
| `applied` | bool, null until completed |
| `attention`, `resolved_at`, `resolved_by` | for checkouts that need attention |
| `provider_ref` | the Stripe session id, unique when set |
| `transaction_number` | the PaymentIntent id |
| `description` | |
| `created_by` | → User, nullable |
| `created_at`, `completed_at` | |

Indexes: on `(purpose, reference_id, provider, status)` and on `status`.

**WebhookEvent:** `provider`, `event_id` (unique with `provider`), `type`, `received_at` and a nullable
`checkout`.

### 3.2 `etqan.billing` (owned by B3)

`Payment`:
- `method` gains `stripe` and `paypal`;
- adds `fee_minor` (≥ 0, default 0), `transaction_number` (≤ 120, blank allowed), `status`
  (`completed`/`refunded`, default `completed`), `refunded_at` and `refunded_by`;
- gains a unique constraint on `(method, transaction_number)` where `transaction_number` is not blank.

The migration adds columns with defaults only, so no data is rewritten.

### 3.3 `etqan.platform.currency`

- `MINOR_DIGITS`: a table of ISO 4217 minor-unit digits, defaulting to 2. It includes 0 (JPY, KRW, …)
  and 3 (KWD, BHD, JOD, OMR, TND).
- `minor_digits(code)` and `to_decimal_string(minor, code)`.

## 4. Behaviour

### 4.1 Settings

- `GET gateways/settings/` returns
  `{stripe: {enabled, mode, public_key, has_secret, has_webhook_secret, webhook_url, events, currencies}, fee: {enabled, basis_points}}`.
  - `webhook_url` is `frontend_url() + "/api/v1/gateways/webhooks/stripe/"`.
  - `events` lists what to subscribe to: `checkout.session.completed`,
    `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed` and
    `checkout.session.expired`.
- `PATCH gateways/settings/` takes `{stripe: {enabled?, mode?, public_key?, secret?, webhook_secret?}, fee: {enabled?, basis_points?}}`.
  - Secrets are write-only.
  - `""` clears a secret, which also disables the account.
- **Without `ETQAN_SECRETS_KEY` in production** (B3-6):
  - saving a secret is a 503 `gateways.no_key`;
  - starting a checkout is a 503 `gateways.no_key`;
  - a webhook answers 503, so Stripe retries.

### 4.2 Starting a checkout

```python
gateways.services.start_checkout(
    purpose: str, reference_id: int, provider: str, *, user: User | None, params: dict | None = None,
) -> StartedCheckout  # {id, redirect_url, amount_minor, fee_minor, currency}
```

The REST route is `POST gateways/checkouts/ {purpose, reference_id, provider}`, which answers 201 with the
same fields. The steps:

1. **The provider** must be enabled and take the currency (400 on `provider`).
2. **The purpose's `prepare(reference_id, user, params)`** returns
   `Prepared(amount_minor, currency, description, add_fee)`, or refuses:
   - 404 when the user cannot see the object;
   - 409 `gateways.nothing_due`.
3. **B-8:** reuse or supersede a pending checkout for the same purpose, reference and provider.
4. **Create and call Stripe:**
   - Create the `pending` checkout and commit.
   - Call Stripe outside any row lock: a Checkout Session with
     - two line items (the amount, then the fee when > 0);
     - `client_reference_id` = checkout id;
     - `metadata.checkout` and `payment_intent_data.metadata.checkout` = checkout id;
     - success and cancel URLs from `app_url("/pay/return?checkout=<id>")`.
   - Store the session id and URL.
5. **A Stripe error** is a 502 `gateways.provider_error`, or a 400 `gateways.amount_too_small` when that is
   the cause. The checkout becomes `failed`, and the detail is logged server-side only.

### 4.3 Purposes

```python
gateways.services.register_purpose(name: str, *, prepare: Prepare, complete: Complete) -> None
# prepare(reference_id: int, user: User | None, params: dict | None) -> Prepared
# complete(c: CompletedCheckout) -> Applied(ok: bool, reason: str)
# CompletedCheckout: frozen {id, purpose, reference_id, provider, amount_minor, fee_minor, currency,
#                            transaction_number, completed_at}
```

- Billing registers `invoice` in `BillingConfig.ready()`.
- **Its `complete`** locks the invoice and applies the money only when both hold:
  - the invoice is not void;
  - its completed-payments balance is at least `amount_minor`.

  It then adds a payment with:
  - method = provider;
  - `amount_minor`, `fee_minor` and `transaction_number`;
  - `paid_on` = the academy's today, `recorded_by` = null.

  Otherwise it returns `ok=False` with a reason (B-11).
- **Import contracts:** "gateways never imports billing" and "billing reaches gateways only through its
  services", both under the B3 marker.
- **The ledger's D4** is updated with this signature.

### 4.4 Webhooks

`POST gateways/webhooks/stripe/` has `authentication_classes=[]`, `permission_classes=[AllowAny]`, is
CSRF-exempt and is not throttled (it is verified locally).

1. **Verify the signature** over the raw `request.body`. A failure is a 400, and nothing is stored.
2. **Record the event.** In one transaction, insert the `WebhookEvent` inside a savepoint. An
   `IntegrityError` there means a replay: answer 200 and do nothing.
3. **Find the checkout** by `metadata.checkout`, else by `client_reference_id`, else by session id. If none
   exists in this academy, answer 200 and log it; it may belong to another academy on the same Stripe
   account.
4. **Lock the checkout** (`select_for_update`) and apply the event:
   - **a completion** (B-4), when the checkout is not yet `completed`:
     - set `completed`, `completed_at` and `transaction_number` (from `payment_intent`);
     - check the event's `livemode`, `amount_total` and `currency` against the checkout (B-11);
     - call the purpose's `complete`;
     - store `applied` and `attention`;
   - `checkout.session.async_payment_failed` → `failed`, only from `pending`;
   - `checkout.session.expired` → `expired`, only from `pending`;
   - anything else: record it and ignore it.
5. **If processing raises,** the transaction (event row included) rolls back and the response is a 500,
   so Stripe retries.

The `(method, transaction_number)` constraint backs this up against a double payment.

### 4.5 Status and return

- `GET gateways/checkouts/<uuid>/` requires login and is visible to `created_by` and to office staff with
  `checkout.view_any`; anyone else gets 404. It returns
  `{id, status, applied, amount_minor, fee_minor, currency, purpose, reference_id}`.
- **The return page** `/app/pay/return?checkout=<id>`:
  - polls every 2 s for up to 60 s;
  - shows Paid, Still processing (with a refresh button) or Not paid (with a retry);
  - links back to the invoice at `/learning/invoices/$id` for families or `/billing/invoices/$id` for
    the office.
- **Expiry:** a daily Celery job loops over academies (`tenant_context`) and marks `expired` every
  `pending` checkout older than 25 h, since Stripe sessions live 24 h. B-4 still accepts money that
  arrives later.

### 4.6 Simulator (B-12)

- `POST gateways/simulate/<uuid>/ {outcome: "pay" | "fail" | "expire"}`:
  - exists only while `GATEWAYS_SIMULATE` is on (404 otherwise);
  - requires login as the checkout's creator;
  - refuses non-simulated checkouts (404);
  - builds the Stripe event JSON, signs it with the stored signing secret and passes it to the webhook
    handling, signature check included;
  - is throttled with the new scope `gateway_simulate`.
- The simulator page `/app/pay/simulate/$id` sits inside `_authed`. It reads the checkout through §4.5's
  route and shows the amount, the fee and the three buttons. A simulated `redirect_url` points to it.

### 4.7 Refunds and resolving

- **`POST billing/payments/<id>/refund/`** (`payment.update`):
  - sets `refunded`, `refunded_at` and `refunded_by`;
  - recalculates the invoice's status from its completed payments;
  - calls no provider;
  - answers 200 with the invoice detail;
  - a second refund is a 409 `billing.already_refunded`.
- **`POST gateways/checkouts/<uuid>/resolve/`** (`checkout.update`):
  - sets `resolved_at` and `resolved_by` on a checkout with `applied=false`;
  - otherwise answers 409 `gateways.nothing_to_resolve`.

### 4.8 Checkouts list (admin)

`GET gateways/checkouts/` (`checkout.view_any`) is paginated and newest first. Its filters are `status`,
`purpose`, `attention` (`open`) and `created_from` / `created_to`. CSV export moves to B3g, with the
payment records list.

## 5. API summary (`/api/v1/`)

| Route | Methods | Feature | Codes |
|---|---|---|---|
| `gateways/settings/` | GET, PATCH | `online_payments` | `gateway.view`, `gateway.update` |
| `gateways/checkouts/` | GET | `online_payments` | `checkout.view_any` |
| `gateways/checkouts/start/` | POST | `online_payments` | self-service, scoped by the purpose (plan D1) |
| `gateways/checkouts/<uuid>/` | GET | — | creator or `checkout.view_any` |
| `gateways/checkouts/<uuid>/resolve/` | POST | `online_payments` | `checkout.update` |
| `gateways/webhooks/stripe/` | POST | — | public, signature-checked |
| `gateways/simulate/<uuid>/` | POST | — | creator; only with `GATEWAYS_SIMULATE` |
| `billing/payments/<id>/refund/` | POST | `invoices` | `payment.update` |

**Payload changes:**
- A billing payment gains `fee_minor`, `status`, `transaction_number` and `refunded_at`.
- An invoice gains `can_pay_online: ["stripe"] | []` for its reader. It is `[]` when nothing is due, the
  feature is off, or Stripe does not take the currency.
- `paid_minor` and `balance_minor` count completed payments only.

**Tests that change on purpose:**
- billing `test_summary` (revenue = amount + fee, completed only);
- the invoice payload tests (new fields);
- the route table, registry and feature counts (marker-less tables).

finance's donation-methods test is unchanged, since `MANUAL_PAYMENT_METHODS` stays the manual set.

## 6. Dashboard

- **Settings → Payment gateways** (`_authed/settings.gateways.tsx`, `gateway.view`, feature
  `online_payments`):
  - the Stripe card: enabled, mode, publishable key, the secrets shown as "saved ✓ / replace", and the
    webhook URL with a copy button and the events list;
  - the fee card.
- **Invoice page:**
  - families get "Pay online" when `can_pay_online` is not empty. A confirm sheet shows the balance, the
    fee and the total, then follows `redirect_url`;
  - admins see the method, fee, transaction number and status in the payments list, a "Mark refunded"
    action, and no delete on online payments.
- **`_authed/pay.return.tsx`** and **`_authed/pay.simulate.$checkoutId.tsx`**.
- **Billing → Online payments** (`_authed/billing.checkouts.tsx`, `checkout.view_any`): the list with a
  "Needs attention" tab and Resolve.
- **Wiring:**
  - the new area `locales/{en,ar}/gateways.json`;
  - nav items under the B3 marker;
  - `FeatureCode` gains `online_payments`;
  - `FEATURE_SCREENS` and `FEATURE_WORDS` rows;
  - semantic tokens, RTL and phone width.

## 7. Dependencies and environment

- **`requirements/base.txt`:** `httpx` and an explicit `cryptography`.
- **`requirements/local.txt`:** `respx` (HTTP mocking).
- The stream's Docker images must be rebuilt (`just rebuild`).
- **Settings:**
  - `ETQAN_SECRETS_KEY`, read from the environment, with the DEBUG/test derivation of B3-6;
  - `GATEWAYS_SIMULATE`;
  - the throttle scope `gateway_simulate`;
  - the Celery beat entry for the expiry job.
- **For the conductor (meta files):** add `ETQAN_SECRETS_KEY` to `infra/` (production and staging env) and
  to CI's env if CI ever runs production settings. This is requested in the ledger when B3b is queued.

## 8. Seeds

The demo academy gets a Stripe account in `test` mode with placeholder keys (`pk_test_demo…`,
`sk_test_demo…`, `whsec_demo…`), enabled, so the simulator works out of the box. It also gets the default
fee. Seeding twice changes nothing.

## 9. Testing

- **Backend:**
  - encryption: round trip, and fail-closed on save, checkout and webhook without a key in production
    settings;
  - settings validation (`incomplete`, `mode_mismatch`);
  - the currency table and fee arithmetic for 0-, 2- and 3-digit currencies, including the 3-decimal
    rounding;
  - `start_checkout`:
    - scope (another family's invoice is 404; a teacher is 404);
    - an unsupported currency; nothing due;
    - reuse versus supersede;
    - Stripe mocked with `respx`: the request body, the `Idempotency-Key`, errors, amount too small;
  - signature verification: valid, a bad signature, an expired timestamp;
  - a replayed event;
  - completion from `cancelled`, `expired` and `failed` (B-4);
  - every B-11 attention case;
  - an event for an unknown checkout (200);
  - the transaction rollback on a raising handler;
  - payments and revenue:
    - the refund arithmetic: invoice status, balance, overdue, revenue, `already_refunded`;
    - voiding after a full refund;
    - an online payment cannot be deleted;
    - revenue counts the fee;
  - the simulator: route only with the setting, creator only, a non-simulated checkout refused, and the
    system check;
  - the expiry job across academies;
  - the role × route matrix rows;
  - cross-academy isolation of a checkout UUID.
- **Dashboard:**
  - the settings page (secrets never echoed);
  - Pay online and its confirm sheet;
  - the return page states and its link per role;
  - the simulator page;
  - the checkouts list and Resolve;
  - Mark refunded;
  - all of it in both languages.
- **E2E** (`dashboard/e2e/b3-online-payments.spec.ts`):
  1. Switch on `invoices` and `online_payments` for demo.
  2. A parent pays an unpaid invoice through the simulator.
  3. The return page shows Paid.
  4. The admin sees the Stripe payment with its fee and marks it refunded; the invoice is unpaid again.

## 10. Out of scope

- PayPal, payment links, standalone payments, online donations, the checkouts CSV, and SUB-006's payment
  metadata (ledger D10). All of these are B3c/B3g per phase §3.
- Wallet credit for surplus money (B3e).
- Refund API calls, disputes, payouts and saved cards (phase B3-10).
- Any live key or production configuration (B-15).

## 11. Carried to B3c (from this spec's review)

PayPal:
- capture on return through `POST gateways/checkouts/<id>/capture/`, with `CHECKOUT.ORDER.APPROVED` as
  the fallback;
- `PayPal-Request-Id` = checkout id, with `ORDER_ALREADY_CAPTURED` treated as success;
- the capture call runs outside the row-lock transaction;
- `PAYMENT.CAPTURE.PENDING` keeps the checkout pending;
- captures are found by `supplementary_data.related_ids.order_id` first, then `custom_id`;
- the OAuth token is cached per account;
- a named throttle scope for its webhook, since every verification costs two PayPal calls;
- the observed currency (one of USD, EUR, SAR, AED, GBP, CAD) and locale fields;
- a pending PayPal checkout expires after N hours.

## 12. Amendments from planning and build (Plan 20)

- **Start route** (§4.2, §5): `POST gateways/checkouts/start/`. The route-table test keys code-exempt
  routes by view class, so the self-service start cannot share the coded list's view.
- **Secrets** (B-5): `etqan.platform.secrets`. A missing key raises the platform's new `UnavailableError`
  (503 with a code); dev and tests may derive the key from `SECRET_KEY`. A malformed key is reported as
  `gateways.bad_key`, and `available()` is false for it.
- **Fee** (B-6, B-7): `(amount × bp + 5000) // 10000`. For a three-digit currency the total is rounded up
  to a multiple of 10 through the fee. With no fee, an amount Stripe cannot take leaves Stripe out of the
  options. Whether Stripe also needs each line item to be a multiple of 10 is unverified (owner's live
  smoke test).
- **Attention codes** (B-11): `invoice_void`, `balance_below_amount`, `amount_mismatch`,
  `currency_mismatch`, `mode_mismatch`, `purpose_unknown`, `reference_missing`, `already_recorded`.
- **Validation errors** are 400s on their fields: `gateways.incomplete` is a 400 on `enabled`,
  `gateways.mode_mismatch` a 400 on `mode`/`public_key`/`secret`, and `gateways.amount_too_small` a 400 on
  `amount_minor`. Codes stay for 409 and 503. A provider failure is the platform's 502
  (`ExternalServiceError`), not `gateways.provider_error`.
- **Mode switch** (§4.1): a settings change that switches `mode` must carry a new `webhook_secret`, since
  Stripe signs each mode with its own secret. Other changes never decrypt the stored secret.
- **Starting** (B-8): starts for one (academy, purpose, reference) are serialised by a transaction-scoped
  advisory lock that is never held across the provider call. A start meeting another one still at the
  provider (under 2 minutes old) answers 409 `gateways.checkout_starting`. A pending checkout is reused
  only by the same user, at the same price, in the account's current mode, and when under 23 hours old.
- **Purposes** (§4.3): registering a second owner for a purpose name raises `ImproperlyConfigured`.
- **Void invoices** stay void: deleting or refunding a payment never recalculates a void invoice.
- **Simulator** (§4.6): it answers 409 `gateways.no_webhook_secret` when the signing secret is cleared,
  and its event carries the account's mode.
- **Expiry** (B-9) is local only: pending checkouts older than 25 hours are marked expired in the
  database; no provider call is made.
- **`can_pay_online`** is on the invoice detail only, not on list rows.
- **The checkouts list's dates** are UTC days, since gateways reads no academy calendar.
- **Seeds**: the demo academy gets a Stripe test account only when `GATEWAYS_SIMULATE` is on, so staging
  (production settings) seeds none.

