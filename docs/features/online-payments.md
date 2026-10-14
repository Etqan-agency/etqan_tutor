# Online payments (gateways)

`etqan.gateways` lets families and anonymous payers pay online with Stripe Checkout or PayPal
(Orders v2), and lets the office create payment links. It is generic: it does not know what is
being paid for. A *purpose* registered by the selling app (billing, finance, wallet, recorded,
consultations) prices the checkout and takes the money once a verified provider event says it was
paid.

- Admins set the provider accounts and the service fee.
- The office reviews checkouts and resolves the ones that need attention.

## Concepts

| Model | What it is |
| --- | --- |
| `GatewayAccount` | One per provider (`stripe`, `paypal`): `enabled`, `mode` (test/live), `public_key` (PayPal client id), `secret_enc` and `webhook_secret_enc` (Fernet tokens via `etqan.platform.secrets`, never returned by the API), PayPal `webhook_id`/`currency`/`locale`, `notes`. |
| `GatewaySettings` | One row: `fee_enabled` (default true) and `fee_basis_points` (default 500 = 5 %, max 2000). |
| `Checkout` | UUID pk. Fields: `purpose`, `reference_id`, `provider`, `simulated`, `amount_minor` + `fee_minor`, `currency`, status (`pending`/`completed`/`failed`/`cancelled`/`expired`), `applied` (null until completed; false means the purpose refused), an `attention` reason with `resolved_at`/`resolved_by`, `provider_ref`, `redirect_url`, `transaction_number`, and `via_connect` + `platform_fee_minor` for Stripe Connect. |
| `WebhookEvent` | Every verified event, unique on `(provider, event_id)`. A replay finds its row and does nothing. |
| `PaymentLink` | Fixed-amount, single-use link with a 32-character token. Fields: kind `payment`/`donation`, title, a student or a typed payer name/email/phone, provider, amount and currency, `add_fee` (payment links only), status `open`/`paid`/`cancelled`, and the checkout that paid it. |

Registered purposes:

| Purpose | Owner | Notes |
| --- | --- | --- |
| `invoice` | billing | |
| `payment_link` | billing | public |
| `donation_link` | finance | public |
| `wallet_topup` | wallet | |
| `recorded_course` | recorded | |
| `consultation` | consultations | |

A *public* purpose lets anyone who holds the checkout UUID read, capture, cancel and simulate it.

## How it works

- **Which account pays** (`services/connect.py:stripe_route`):
  - Stripe uses the academy's own enabled keys first.
  - Otherwise it uses the academy's Stripe Connect account on Etqan's platform
    (`integrations.services.stripe_connect()`, only when Etqan's default payments service resolves
    for the academy and the account is active). Etqan's cut is then added as Stripe's
    `application_fee_amount`, computed by `application_fee` from `etqan_billing.connect_fee()`.
  - PayPal is only ever the academy's own account.
- **Which providers are offered** (`services/fees.py:providers_for`): enabled providers that can
  take the currency. Stripe takes a fixed list, `STRIPE_CURRENCIES`. PayPal takes only its
  account's currency (USD, EUR, SAR, AED, GBP or CAD).
- **Service fee** (`fees.py:fee_for`): `amount × basis_points / 10000`, rounded half up, added on
  top.
  - Invoices and top-ups use the academy switch.
  - A payment link's own `add_fee` decides for that link (`use_switch=False`).
  - Donations never carry a fee.
  - For three-decimal currencies, the total is rounded up to a multiple of 10.
- **Start** (`services/checkouts.py:start_checkout`, a non-atomic view):
  1. The purpose's `prepare(reference_id, user, params)` prices the checkout or refuses it
     (404/409).
  2. Under a Postgres advisory lock per (schema, purpose, reference), a matching pending checkout
     is reused if it is still valid: same price, same creator, same mode, under 23 h for Stripe
     or 3 h for PayPal. Otherwise the old pending checkouts are cancelled and a new row is
     committed.
  3. Only then is the provider called. It is never called while a row lock is held. A provider
     error marks the checkout `failed`.
  4. The return URL is `app_url("/pay/return?checkout=<id>")`.
- **Completion** (`services/completion.py:finish`): the one completion path, for every provider.
  - B-11 checks, in order: mode, currency, amount (`amount + fee`), known purpose. For links, the
    link must still be open.
  - Any failure completes the checkout with `applied=false` and an `attention` code
    (`mode_mismatch`, `currency_mismatch`, `amount_mismatch`, `link_closed`, `purpose_refused`,
    `already_recorded`, …).
  - Otherwise it calls the purpose's `complete(CompletedCheckout)`. Money already paid is never
    dropped. Something that cannot be applied shows in the checkouts list until someone resolves
    it (`resolve_checkout`).
- **Stripe events** (`services/webhooks.py:process_stripe`):
  - The HMAC is verified over the raw body with a 300 s tolerance.
  - The event is recorded and applied in one transaction. `checkout.session.completed` (paid) and
    `async_payment_succeeded` complete the checkout. `async_payment_failed` and `expired` fail or
    expire it.
  - The checkout is found by metadata, then `client_reference_id`, then the session id, and only
    in the current academy's schema.
- **Connect events** (`services/connect_webhooks.py:process_connect`) arrive on the base domain:
  - The body is checked against each of Etqan's Connect signing secrets.
  - The event's account id is routed to its academy schema.
  - Each event type is handled differently:

    | Event | Effect |
    |---|---|
    | `account.updated` | Updates the academy's Connect account (integrations). |
    | Session events | Go through the same `apply_event`. |
    | `application_fee.created` | Recorded with `etqan_billing.record_collected_fee`, only in the platform key's mode. |
- **PayPal** (`gateways/paypal.py`, `services/captures.py`, `services/paypal_webhooks.py`):
  - REST over httpx with no SDK. OAuth tokens are cached per academy, mode and client id.
  - When the family comes back, the dashboard calls `capture/`. `capture_checkout` checks the
    checkout is still payable and captures. `complete_paypal` is the shared finish.
  - The webhook checks headers, the cert host, JSON and the event type before asking PayPal to
    verify the signature.
  - `PAYMENT.CAPTURE.REFUNDED` and `REVERSED` only flag attention (`provider_refunded`,
    `provider_reversed`). Billing is not changed.
- **Payment links** (`services/links.py`):
  - `create_link` takes a student or a typed payer.
  - The public page `pay/<token>` compares the token in constant time. A donation link answers
    404 while `donations` is off.
  - `cancel_link` closes a link. Money that still arrives on a closed link becomes attention.
  - The first applied payment marks the link `paid`.
- **Refunds** are never executed at a provider. See billing's "mark refunded".
- **Simulator** (`services/simulator.py`): with `GATEWAYS_SIMULATE` on and a test-mode own
  account, checkouts never reach the provider. A dashboard page plays the provider by sending
  signed Stripe events, or PayPal-shaped captures, through the real paths. The system check
  `gateways.E001` refuses it without `DEBUG`.

## API

Academy host, under `/api/v1/gateways/` unless noted.

| Method | Path | Who | Purpose |
| --- | --- | --- | --- |
| GET, PATCH | `/api/v1/gateways/settings/` | `gateway.view`/`gateway.update` (`online_payments`) | Accounts (secrets write-only) and fee |
| POST | `/api/v1/gateways/checkouts/start/` | any signed-in user, not quick-login | `{purpose, reference_id, provider}` → redirect URL |
| GET | `/api/v1/gateways/checkouts/` | `checkout.view_any` | List with filters. CSV only while `payment_receipts` is on |
| GET | `/api/v1/gateways/checkouts/<uuid>/` | creator, office; anyone for public purposes | Status (return page) |
| POST | `/api/v1/gateways/checkouts/<uuid>/resolve/` | `checkout.update` | Clear an attention |
| POST | `/api/v1/gateways/checkouts/<uuid>/capture/` | as detail, not quick-login | PayPal capture on return |
| POST | `/api/v1/gateways/checkouts/<uuid>/cancel/` | as detail, not quick-login | PayPal cancel |
| POST | `/api/v1/gateways/webhooks/stripe/` | Stripe (signature) | Academy's own Stripe events |
| POST | `/api/v1/gateways/webhooks/paypal/` | PayPal (verified) | PayPal events |
| GET, POST | `/api/v1/gateways/links/` | `payment_link.view_any`/`.create` (`payment_links`) | List and create links |
| GET | `/api/v1/gateways/links/<id>/` | `payment_link.view_any` | Link detail |
| POST | `/api/v1/gateways/links/<id>/cancel/` | `payment_link.update` | Cancel |
| GET | `/api/v1/gateways/pay/<token>/` | anyone (throttled) | Public link page data |
| POST | `/api/v1/gateways/pay/<token>/checkout/` | anyone (throttled) | Start the link's checkout |
| POST | `/api/v1/gateways/simulate/<uuid>/` | creator (anyone for public) | Simulator outcome `pay`/`fail`/`expire` |
| POST | `/api/v1/webhooks/stripe-connect/` (**base domain**, `config/urls_public.py`) | Stripe (signature) | Etqan's Connect events |

Throttles (`config/settings/base.py`):

| Scope | Rate |
| --- | --- |
| `gateway_start` | 20/min |
| `gateway_capture` | 30/min |
| `gateway_simulate` | 30/min |
| `payment_link` | 60/min |
| `paypal_webhook` | 120/min |

Webhooks keep working while `online_payments` is off, so a payment started before the switch went
off is still recorded.

## Dashboard

- `routes/_authed/settings.gateways.tsx`: the `GatewaySettingsPage` (Stripe, PayPal, fee) and the
  local-payment card.
- `routes/_authed/billing.checkouts.tsx`: `CheckoutsList`, with a "needs attention" filter.
- `routes/_authed/billing.links.tsx`: `PaymentLinksPage` and `LinkDialog`.
- Public, top-level routes:
  - `routes/pay.link.$token.tsx` (`PublicLinkPage`);
  - `routes/pay.return.tsx` (`ReturnPage`: polls the checkout, captures PayPal);
  - `routes/pay.simulate.$checkoutId.tsx` (`SimulatorPage`).
- `PayOnline` sits on the family invoice page. The wallet's `OnlineTopUpDialog` also starts
  checkouts.
- Feature folder: `dashboard/src/features/gateways/`.

## Background jobs

`gateways.expire_checkouts` (`gateways/tasks.py`) runs daily at 03:20 and loops over every academy
with `for_each_academy`:

- `expire_local` expires pending Stripe and simulated checkouts older than 25 h, with no provider
  call.
- `settle_paypal` (non-atomic) reads real PayPal checkouts older than 72 h:
  - completed at PayPal: completed here;
  - approved and still payable: captured;
  - otherwise: expired;
  - capture unreadable: stays pending with `capture_unreadable` attention;
  - transient errors: retried on the next run.

## Configuration

- **Features:** `online_payments` (requires `invoices`) and `payment_links` (requires
  `online_payments`). Both are off by default.
- **Env:**
  - `ETQAN_SECRETS_KEY` (Fernet key; required in production, derived from `SECRET_KEY` in
    dev and test);
  - `GATEWAYS_SIMULATE` (default false, true in `local.py` and `test.py`).
- **Academy:** keys and modes are entered on the settings page. Stripe key prefixes must match
  the mode (`pk_test_`/`sk_test_`/`rk_test_`, `whsec_`). Saving an enabled PayPal account checks
  the credentials and webhook id at PayPal.
- **Stripe Connect:** the onboarding and the platform key live in `etqan.integrations`. See
  [integrations.md](integrations.md) and [etqan-billing.md](etqan-billing.md).

## Code map

- `backend/etqan/gateways/models.py`, `paypal.py`, `tasks.py`, `checks.py`
- `backend/etqan/gateways/providers/` (`stripe.py`, `paypal.py`, `simulator.py`, `base.py`)
- `backend/etqan/gateways/services/`: `checkouts.py`, `completion.py`, `purposes.py`, `fees.py`,
  `connect.py`, `connect_webhooks.py`, `webhooks.py`, `captures.py`, `paypal_webhooks.py`,
  `expiry.py`, `links.py`, `accounts.py`, `simulator.py`
- `backend/etqan/gateways/api/` and `backend/config/urls_public.py`
- Purpose owners: `billing/services/online.py`, `billing/services/link_purpose.py`,
  `finance/services/link_purpose.py`, `wallet/services/topup_purpose.py`,
  `recorded/services/purpose.py`, `consultations/services/purpose.py`
- `dashboard/src/features/gateways/`

## Design history

- [B3 phase design](../superpowers/specs/2026-10-03-b3-money-depth-design.md): B3-6…B3-10
  (own keys, one interface, fee, webhooks). B3-6's "own merchant account" is extended by Connect.
- [B3b online payments (Stripe)](../superpowers/specs/2026-10-03-b3b-online-payments-design.md):
  core, Stripe and the simulator. Its "expiry is local only" is superseded by B3c C-16.
- [B3c PayPal](../superpowers/specs/2026-10-03-b3c-paypal-design.md): PayPal, server-side
  capture, provider refunds as attention.
- [B3g links and records](../superpowers/specs/2026-10-03-b3g-links-records-design.md): payment
  and donation links, public purposes.
- [Integrations and Etqan billing](../superpowers/specs/2026-10-07-integrations-and-etqan-billing-design.md):
  the Stripe Connect fallback and the application fee.
- Plans: [Plan 20](../superpowers/plans/2026-10-03-plan-20-online-payments.md),
  [Plan 22](../superpowers/plans/2026-10-03-plan-22-paypal.md),
  [Plan 26](../superpowers/plans/2026-10-03-plan-26-links-records.md),
  [Integrations 3](../superpowers/plans/2026-10-09-plan-integrations-3-zoom-connect.md).
