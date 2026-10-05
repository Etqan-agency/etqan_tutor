# Slice B3c — PayPal — Design

**Date:** 2026-10-03
**Status:** Draft for the B3 orchestrator's review (orchestration spec PO-3). This is the re-sliced B3c, after
a spec review: payment links and payment records moved to B3g (`2026-10-03-b3g-links-records-design.md`).
**Phase:** B3 (`2026-10-03-b3-money-depth-design.md`), slice B3c. **Requires:** no other phase's slice.
B3b merges first; this slice plugs PayPal into B3b's gateway core.
**Builds on:**
- B3b (`2026-10-03-b3b-online-payments-design.md`): `etqan.gateways`, accounts, encryption, checkouts,
  `start_checkout`, purposes, webhooks, the simulator, the expiry job, the service fee;
- Plan 6 billing; Plan 13 feature switches; Plan 12a roles.

**Evidence:**
- audit SYS-003 and §1.3 #20 (PayPal: sandbox / production, client id, secret, currency USD · EUR · SAR ·
  AED · GBP · CAD, locale);
- P1 INT-001 (Stripe: keys, webhook secret, notes), INT-002 (PayPal: status, client id, client secret,
  currency, language, notes), §9 (a PayPal webhook must exist), §1.3 #6 (statuses incl. refunded).

## 1. Goal

An academy connects its own PayPal account next to Stripe. A family opens an unpaid invoice, chooses
PayPal, approves the payment at PayPal and comes back; the server captures the order and the payment lands
on the invoice. PayPal's webhook covers a payer who never comes back, and refunds or reversals made at
PayPal are flagged for an admin. Everything works offline through B3b's simulator.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| C-1 | **PayPal Orders v2 through `httpx`**, no SDK, behind B3b's provider interface. Base URL by mode: `https://api-m.sandbox.paypal.com` (`test`, shown as "Sandbox") or `https://api-m.paypal.com` (`live`, "Production"). Every call has a 10 s timeout. | audit SYS-003; spec b3b B-3, §11; [assumed] (client, timeout) |
| C-2 | **OAuth token cache:** a client-credentials token per account in Django's cache, keyed by schema, mode and a hash of the client id, with TTL `expires_in` − 300 s. A 401 drops it and retries once. Saving a new secret, client id or mode drops it. | spec b3b §11; [assumed] |
| C-3 | **PayPal account fields:** `enabled`; `mode`; client id (kept in B3b's `public_key` column, named `client_id` in the API); the secret (Fernet, write-only); `webhook_id` (PayPal's id for the subscribed webhook, which its verification API needs; not a secret); `currency` (USD, EUR, SAR, AED, GBP or CAD; default USD); and `locale` (`^[a-z]{2}-[A-Z]{2}$`, default `en-US`, the language of PayPal's page). | audit SYS-003, §1.3 #20; P1 INT-002 ("language"); [assumed] (webhook id, locale format) |
| C-4 | **A `notes` text field on every gateway account**, Stripe's included. It is added as a blank-default column. | P1 INT-001, INT-002 ("notes") |
| C-5 | **Enabling PayPal checks the account:** client id, secret, webhook id and currency must be set (400 `gateways.incomplete`). A token is then fetched from the mode's base URL (a refusal is 400 `gateways.paypal_auth_failed`, PayPal's counterpart of B-5's `mode_mismatch`). Then `GET /v1/notifications/webhooks/<webhook_id>` must answer 200 (otherwise 400 `gateways.paypal_webhook_unknown`). The checks are skipped while `GATEWAYS_SIMULATE` is on. | spec b3b B-5; [assumed] |
| C-6 | **One currency per academy:** PayPal takes only its account's `currency`. SAR and AED are offered because TutorHamster offers them. The settings card warns that PayPal may refuse them, and enabling still succeeds. PayPal refusing the currency at order time is a 400 `gateways.currency_not_supported`, and the checkout becomes `failed`. | audit SYS-003; [assumed] |
| C-7 | **Completion by server-side capture.** The order is created with `intent=CAPTURE`. On return, the page calls `POST gateways/checkouts/<uuid>/capture/`: <br>• a short lock requires `pending` and checks the money is still payable (C-8); <br>• the capture call to PayPal runs outside any lock; <br>• the checkout is completed under the lock through the shared completion function. <br>`CHECKOUT.ORDER.APPROVED` is the fallback when the payer never returns. A verified capture response or a verified `PAYMENT.CAPTURE.COMPLETED` completes the checkout from any state but `completed` (B-4). | ledger D13; spec b3b B-4, §11; spec review |
| C-8 | **Still payable before capture.** Under the short lock, gateways calls the purpose's `prepare(reference_id, checkout.created_by, None)`. If it refuses, or returns a different amount, currency or fee decision, nothing is captured: the checkout becomes `cancelled` and the route answers its status. The payer's approval then lapses at PayPal and no money moves. B3g adds the link purposes' check (C-8 there). | spec review; [assumed] |
| C-9 | **Idempotency:** creating the order sends `PayPal-Request-Id` = checkout id. Capturing sends `<checkout id>-capture`, because PayPal caches one response per request id and the two calls must not share one. <br>• `ORDER_ALREADY_CAPTURED` counts as success: the order is read (`GET /v2/checkout/orders/<id>`) and its capture is used. <br>• A capture with status `PENDING`, or `PAYMENT.CAPTURE.PENDING`, keeps the checkout `pending`. <br>• `DECLINED`, or `PAYMENT.CAPTURE.DENIED`, makes a pending checkout `failed`. | spec b3b §11; [assumed] (capture request id) |
| C-10 | **The redirect is checked:** the `payer-action` link must be `https` on `www.paypal.com` or `www.sandbox.paypal.com`, matching the account's mode. Any other link is a 502 `gateways.provider_error`, and the checkout becomes `failed`. | spec review; [assumed] |
| C-11 | **Cancel:** the cancel URL is `app_url("/pay/return?checkout=<id>&cancelled=1")`. With that flag, the return page shows "Not paid" and calls `POST gateways/checkouts/<uuid>/cancel/`, which moves a `pending` checkout to `cancelled` and does nothing otherwise. B-4 still accepts money that arrives later. | spec review; spec b3b B-4 |
| C-12 | **Webhook** `POST gateways/webhooks/paypal/`, checked in this order before any remote call: <br>• the account must have a webhook id and a secret (otherwise 503, so PayPal retries); <br>• the five `PAYPAL-*` headers must be present (`AUTH-ALGO`, `CERT-URL`, `TRANSMISSION-ID`, `TRANSMISSION-SIG`, `TRANSMISSION-TIME`; otherwise 400); <br>• the `CERT-URL` must be `https` on `api.paypal.com` or `api.sandbox.paypal.com` (otherwise 400); <br>• the JSON must parse (otherwise 400); <br>• an event type the academy did not subscribe to is answered 200, unverified, and nothing is stored; <br>• an event whose checkout is not found (by `supplementary_data.related_ids.order_id` = `provider_ref`, then `custom_id` = checkout id) is answered 200, unverified, and nothing is stored. <br>Only then does `POST /v1/notifications/verify-webhook-signature` run: a result other than `SUCCESS` is a 400 and nothing is stored; a timeout or a PayPal 5xx is a 503. The route has a per-IP throttle scope `paypal_webhook` (120/minute; a 429 makes PayPal retry). | spec b3b B-9, §4.4, §11; P1 §9; spec review |
| C-13 | **Refunds and reversals made at PayPal are recorded as attention, not executed.** `PAYMENT.CAPTURE.REFUNDED` and `PAYMENT.CAPTURE.REVERSED` on a completed checkout set `attention` to `provider_refunded` or `provider_reversed` and clear `resolved_at` / `resolved_by`. `applied` is unchanged and nothing is refunded in billing; the admin marks the payment refunded (B3b §4.7) and resolves the checkout. B3b's resolve route therefore accepts any checkout with an open attention, not only `applied=false`. | phase B3-10; spec b3b §4.7; [assumed] |
| C-14 | **No livemode check for PayPal** (B-11's `livemode` row): an event verified with the account's own credentials belongs to its mode. B-11's amount and currency checks apply, comparing PayPal's decimal `amount.value` and `currency_code` with amount + fee. | spec b3b B-11 |
| C-15 | **Simulator parity:** a simulated PayPal checkout never calls PayPal, and its `redirect_url` is the simulator page. <br>• "pay" builds a PayPal-shaped `COMPLETED` capture and hands it to the shared completion function; <br>• "fail" applies a `DECLINED` capture; <br>• "expire" applies the expiry. <br>The capture route answers a simulated checkout's status without calling PayPal. Only PayPal's remote signature check is not exercised offline; `respx` tests cover it. | spec b3b B-12; [assumed] |
| C-16 | **Expiry:** B3b's daily job also handles pending, non-simulated PayPal checkouts older than 72 h (an approved PayPal order stays capturable for about three days). <br>• It first reads the order: `COMPLETED` → completed through the shared function; `APPROVED` and still payable (C-8) → captured as in §4.3; anything else → `expired`. <br>• A PayPal error leaves the checkout for the next run. <br>• Simulated checkouts expire without a read. | spec b3b §4.5, §11; spec review; [assumed] (72 h) |
| C-17 | **No new feature switch:** PayPal sits under `online_payments` (B-13). Webhooks, captures and the expiry job keep working while it is off. | phase B3-3; spec b3b B-13 |
| C-18 | Only en and ar strings. | ledger D11 |

## 3. Data (`etqan.gateways`)

**GatewayAccount**:
- gains `notes` (text, blank) for both providers, and, blank for Stripe, `webhook_id` (≤ 64), `currency`
  (3 letters) and `locale` (≤ 10);
- `provider` gains `paypal`.

The migration only adds columns with defaults. For a PayPal checkout, the existing Checkout fields hold the
order id (`provider_ref`) and the capture id (`transaction_number`).

## 4. Behaviour

### 4.1 Settings

- **`GET gateways/settings/`:**
  - gains `paypal: {enabled, mode, client_id, has_secret, webhook_id, currency, locale, notes, webhook_url, events, currencies}`;
  - `stripe` gains `notes`.
- **`webhook_url`** is `frontend_url() + "/api/v1/gateways/webhooks/paypal/"`.
- **`events`** lists `CHECKOUT.ORDER.APPROVED`, `PAYMENT.CAPTURE.COMPLETED`, `PAYMENT.CAPTURE.PENDING`,
  `PAYMENT.CAPTURE.DENIED`, `PAYMENT.CAPTURE.REFUNDED` and `PAYMENT.CAPTURE.REVERSED`. These are also the
  subscribed types of C-12.
- **`PATCH`** takes `paypal: {enabled?, mode?, client_id?, secret?, webhook_id?, currency?, locale?, notes?}`
  and `stripe.notes`, with B3b's rules: the secret is write-only, `""` clears it and disables the account,
  and a missing secrets key is a 503 `gateways.no_key`. C-5 runs whenever the result is enabled.

### 4.2 Starting a PayPal checkout

`start_checkout(…, provider="paypal")` runs B3b §4.2 steps 1–3 (the currency must equal the account's
`currency`). It then:
1. creates the `pending` checkout and commits;
2. outside any lock, calls `POST /v2/checkout/orders` with:
   - `PayPal-Request-Id` = checkout id;
   - `intent=CAPTURE`;
   - one purchase unit: `custom_id` = checkout id; `amount` with `breakdown.item_total`; two `items` (the
     amount, then the fee when > 0); values from `currency.to_decimal_string`;
   - `payment_source.paypal.experience_context`: `locale`, `user_action=PAY_NOW`,
     `shipping_preference=NO_SHIPPING`, the return URL `app_url("/pay/return?checkout=<id>")` and the cancel
     URL of C-11;
3. stores the order id in `provider_ref` and the checked (C-10) `payer-action` link as `redirect_url`.

Errors map as B3b §4.2 step 5, plus C-6. An invoice's `can_pay_online` becomes the enabled providers that
take its currency, in the order `stripe`, `paypal`.

### 4.3 Capture

`POST gateways/checkouts/<uuid>/capture/` is visible to the checkout's creator and to holders of
`checkout.view_any`; anyone else gets 404. It has the throttle scope `gateway_capture` (30/minute).

1. A non-PayPal checkout is a 404.
2. A completed or simulated checkout answers its status at once.
3. **Short lock** (`select_for_update`):
   - a checkout that is not `pending` answers its status;
   - C-8 runs; a failure sets `cancelled` and answers the status.
4. **Outside the lock**, capture (C-9):
   - `ORDER_ALREADY_CAPTURED` → read the order;
   - `ORDER_NOT_APPROVED` → answer the status unchanged;
   - any other error → 502 `gateways.provider_error`, with the checkout unchanged.
5. **`complete_paypal(checkout_id, capture)`** locks the checkout and handles the capture's status:
   - `COMPLETED`, unless the checkout is already `completed`:
     - set `completed`, `completed_at` and `transaction_number` (the capture id);
     - apply C-14's checks;
     - call the purpose's `complete`;
     - store `applied` and `attention`;
   - `PENDING`: no change;
   - `DECLINED`: `failed`, only from `pending`.
6. Answer `{status, applied}`.

`complete_paypal` is the one completion path for the capture route, the webhook, the expiry job and the
simulator.

### 4.4 Webhook

After C-12's checks, the webhook follows B3b §4.4:
- **Recording:** the event row is inserted in a savepoint; a replay answers 200; a raising handler rolls
  back and answers 500.
- **`PAYMENT.CAPTURE.COMPLETED`** → `complete_paypal` with the event's capture.
- **`PAYMENT.CAPTURE.PENDING`** → no change. **`PAYMENT.CAPTURE.DENIED`** → `failed`, only from `pending`.
- **`PAYMENT.CAPTURE.REFUNDED`** / **`REVERSED`** → C-13.
- **`CHECKOUT.ORDER.APPROVED`**, when the checkout is still `pending`:
  - the event row commits first;
  - §4.3 steps 3–5 then run, with the capture call outside the lock;
  - a capture error is logged and answered 200. An approved order that was not captured has taken no
    money, and the return page or the expiry job settles it.

### 4.5 Return page, cancel, simulator

- **`_authed/pay.return.tsx`:**
  - for a PayPal checkout that is still `pending`, it calls capture once, then polls as in B3b;
  - with `cancelled=1`, it calls cancel (C-11) and shows "Not paid" with a retry.
- **Status payload:** B3b §4.5's status payload gains `provider`.
- **`POST gateways/checkouts/<uuid>/cancel/`** has the capture route's visibility and throttle.
- **The simulator** (B3b §4.6) builds PayPal-shaped captures for PayPal checkouts (C-15).

## 5. API summary (`/api/v1/`)

| Route | Methods | Feature | Codes |
|---|---|---|---|
| `gateways/settings/` (paypal block, notes) | GET, PATCH | `online_payments` | `gateway.view`, `gateway.update` |
| `gateways/checkouts/<uuid>/capture/` | POST | — | creator or `checkout.view_any` |
| `gateways/checkouts/<uuid>/cancel/` | POST | — | creator or `checkout.view_any` |
| `gateways/webhooks/paypal/` | POST | — | public, PayPal-verified, per-IP throttle |

**Payload changes:**
- the status payload gains `provider`;
- `can_pay_online` may hold `paypal`;
- the settings payload gains the `paypal` block and both accounts' `notes`.

**Changed on purpose:** B3b's resolve route accepts any open attention (C-13).

## 6. Dashboard

- **Settings → Payment gateways:**
  - a PayPal card with: enabled; Sandbox / Production; client id; the secret, shown as "saved ✓ / replace";
    webhook id; currency, with a warning for SAR and AED (C-6); locale; notes; and the webhook URL with a
    copy button and the events list;
  - a notes field on the Stripe card.
- **Invoice page:** "Pay online" offers a choice of provider when `can_pay_online` has two. The confirm
  sheet is unchanged.
- **Return page and simulator:** §4.5; the simulator page labels the provider.
- **Billing → Online payments:** the attention reasons `provider_refunded` and `provider_reversed` are
  translated, and Resolve shows for them.
- **Throughout:** keys in `locales/{en,ar}/gateways.json`; semantic tokens, RTL and phone width.

## 7. Dependencies and environment

- No new package: B3b brought `httpx`, `cryptography` and `respx`.
- **Settings:** throttle scopes `paypal_webhook` (120/minute, per IP) and `gateway_capture` (30/minute).
- The expiry job keeps its Celery beat entry, which now also covers PayPal.

## 8. Seeds

The demo academy gets a PayPal account under the B3 marker of `seed_academy`. It is written directly,
without C-5's remote checks, and the step runs only when no PayPal row exists. The account is:
- in Sandbox mode, with a placeholder client id, secret and webhook id;
- in USD, with the locale `en-US`;
- enabled, so the simulator works.

## 9. Testing

- **Backend** (PayPal mocked with `respx`):
  - **Settings:** `incomplete`, `paypal_auth_failed`, `paypal_webhook_unknown`; the checks skipped under
    simulate; notes on both accounts; the token cache, the 401 retry and the cache drop on a secret, mode or
    client id change.
  - **Orders:** the request body, request id and decimals; the redirect host check; currency refusal; other
    errors.
  - **Capture:**
    - success, `ORDER_ALREADY_CAPTURED`, `ORDER_NOT_APPROVED`, pending, declined, a provider error;
    - the still-payable refusal: an invoice paid or voided meanwhile → `cancelled`, no capture call;
    - visibility (creator, office, other family 404, teacher 404); a non-PayPal checkout is 404;
    - cancel.
  - **Webhook:**
    - each rejection of C-12 in order, with no remote call before verification and nothing stored;
    - the remote verify: success, failure, timeout, 5xx;
    - a replay; each event type;
    - APPROVED capturing; refund and reversal attention, and resolving them;
    - a rollback on a raising handler; the throttle.
  - **Completion:** from `cancelled`, `expired` and `failed` (B-4); B-11's amount and currency cases.
  - **Simulator:** pay, fail and expire for PayPal.
  - **Expiry:** order read outcomes, PayPal error retried, across academies.
  - **Isolation:** cross-academy isolation of checkouts.
- **Dashboard:** the PayPal card (the secret never echoed, the SAR/AED warning), the provider choice, the
  return page's capture and cancelled states, the attention reasons, both languages.
- **E2E** (`dashboard/e2e/b3-paypal.spec.ts`):
  1. Switch on `invoices` and `online_payments` for demo.
  2. The admin issues a USD invoice to a demo student.
  3. The parent pays it with PayPal through the simulator.
  4. The return page shows Paid.
  5. The admin sees the PayPal payment with its fee.

## 10. Out of scope

- Payment links, standalone payment records, online donations, the checkouts CSV and SUB-006: B3g.
- Refunding through PayPal's API, disputes, vaulting, PayPal subscriptions (phase B3-10).
- Reading refunds made in Stripe's dashboard; Stripe stays as B3b left it.
- Live credentials and any production configuration (B-15).

## 11. Carried from B3b §11

| Item | Where |
|---|---|
| Capture on return through `POST gateways/checkouts/<id>/capture/`, `CHECKOUT.ORDER.APPROVED` fallback | C-7, §4.3, §4.4 |
| `PayPal-Request-Id` = checkout id; `ORDER_ALREADY_CAPTURED` is success | C-9 (capture uses `<id>-capture`, reason given) |
| Capture call outside the row-lock transaction | C-7, §4.3 step 4 |
| `PAYMENT.CAPTURE.PENDING` keeps the checkout pending | C-9, §4.4 |
| Captures found by `supplementary_data.related_ids.order_id`, then `custom_id` | C-12 |
| OAuth token cached per account | C-2 |
| Named throttle scope for the PayPal webhook | C-12, §7 |
| Observed currency (USD, EUR, SAR, AED, GBP, CAD) and locale fields | C-3, C-6 |
| A pending PayPal checkout expires after N hours | C-16 (N = 72, after reading the order) |

## 12. Amendments from planning and build (Plan 22)

- **Field errors** (C-5, C-6), as B3b's Plan 20 D18 decided: `gateways.incomplete` is a 400 on
  `enabled`, `gateways.paypal_auth_failed` on `client_id`, `gateways.paypal_webhook_unknown` on
  `webhook_id`, `gateways.currency_not_supported` on `provider`. `gateways.provider_error` is the
  platform's 502. PayPal unreachable while enabling is a 502, not a 400.
- **503 codes:** `gateways.not_configured` (a webhook while the account lacks a webhook id or secret) and
  `gateways.provider_unavailable` (verification timed out, 5xx, or 401/403/429), per B3b §12 precedent
  (field 400s, platform 502, named 503s). Attention codes: `provider_refunded`, `provider_reversed`,
  `purpose_refused`, `capture_unreadable`. Resolve and "needs attention" key on an open attention.
- **Finding a checkout** (C-12): `CHECKOUT.ORDER.APPROVED` carries an order (its id, and `custom_id` in
  `purchase_units[0]`). Refunds and reversals are found by the capture id in their `up` link, against
  `transaction_number`.
- **Still payable** (C-8): the fee is compared, so a changed fee percentage cancels an approved checkout.
- **Expiry** (C-16): every PayPal checkout uses 72 h; simulated or orderless ones expire without a read;
  an approved order no longer payable becomes `expired`. C-16 supersedes B3b §12 "expiry is local only"
  for PayPal. The PayPal pass runs outside the per-academy transaction (`for_each_academy`,
  `atomic=False`).
- **Expiry retries (M6):** transient PayPal errors (unreachable, 5xx, 401/403/429) and a 2xx answer that
  cannot be read (not a JSON object, or a capture call answered without a capture) leave the checkout
  pending for a retry; a 4xx refusal other than 401/403/429 expires it. An order PayPal reports
  `COMPLETED` whose capture cannot be read is never expired: money moved, so the checkout stays pending
  with attention `capture_unreadable` (`applied=false`) until a later read or webhook completes it or the
  office resolves it (a resolved flag is not raised again). This supersedes C-16's literal text. Stale
  real PayPal checkouts with bad credentials (401) stay pending, with a daily warning.
- **Seeds (H4):** the demo PayPal and Stripe accounts are seeded only when `GATEWAYS_SIMULATE` is on.
- **Mode switch (L6):** a PayPal mode switch keeps the other environment's webhook id. Enabling checks
  call PayPal on every enabled save, so a notes-only save answers 502 while PayPal is down.
- **Reuse window:** a pending PayPal checkout is reused for at most 3 hours (Stripe: 23 h).
- **Capture failures:** `INSTRUMENT_DECLINED` is treated as any other capture error (502, the checkout
  stays pending). A retry may get PayPal's cached response, so the payer may have to wait for expiry and
  restart. Follow-up: a per-attempt capture request id.
- **Settings changed mid-flight:** switching PayPal mode or client id while an order is approved makes its
  capture answer 502 until expiry settles it.
- **Webhook verification** sends the delivered raw bytes verbatim inside `webhook_event`.
- **Cancel** answers 404 for a non-PayPal checkout, as capture does.
- **Return page:** it re-captures a still-pending PayPal checkout on each mount (harmless, the server is
  idempotent) and shows capture errors with a Refresh that asks again.
- **Decimals:** `etqan.platform.currency` gains `to_decimal_string` and `from_decimal_string`; an amount
  that does not parse is `amount_mismatch`.
- **Notes** are at most 2000 characters in the API.
- **Locale** is only format-checked at save (`^[a-z]{2}-[A-Z]{2}$`): a locale PayPal rejects makes every
  start fail with 502 until it is corrected.
- **Impersonation (ledger D19):** start, capture, cancel and simulate refuse a quick-login session (403
  `identity.impersonating`); reading a checkout stays open.
- **Wording:** `gateways.errors.provider_failed` is neutral ("did not answer"), since it shows for any
  provider 502: start, capture on the return page and settings saves. The capture call sends
  `Prefer: return=representation`.
