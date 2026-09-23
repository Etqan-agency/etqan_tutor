# Stripe billing runbook

Operational steps for the `billing` module (`docs/architecture/billing.md`). Stripe
**test mode** only — no live keys exist yet (go-live is a separate launch task).

## 1. Stripe test-mode Price setup

1. In the Stripe dashboard (test mode), create two recurring Prices, monthly billing
   period:
   - **Individual** — one adult student, 4 sessions/month.
   - **Family** — one parent, 4 sessions/child/month.
2. Copy each Price's id (`price_…`).
3. In Django admin, create the matching `SubscriptionPlan` rows with the **same**
   amount/currency as the Stripe Price:
   - `plan_type`: `individual` or `family`.
   - `sessions_per_cycle`: 4 (or whatever the product spec currently says).
   - `stripe_price_id`: the `price_…` id copied above.
   - `display_amount`: the Price's amount in minor units (e.g. cents).
   - `currency`: the Price's currency, lowercase ISO-4217 (Stripe convention).
   - `is_active`: true.

Plan/Price creation is manual — there is no programmatic sync in B1 (see `ISSUES.md`).
Keep `display_amount`/`currency` in lockstep with the Stripe Price by hand; a mismatch
only affects what the pricing page *shows*, not what Stripe actually charges.

## 2. Environment variables

| Var | Where | Notes |
| --- | --- | --- |
| `DJANGO_STRIPE_SECRET_KEY` | local `.env`, staging `.env.production` | Stripe **test** secret key (`sk_test_…`). Never commit. |
| `DJANGO_STRIPE_WEBHOOK_SECRET` | local `.env`, staging `.env.production` | The signing secret for the registered webhook endpoint (`whsec_…`). Never commit. |
| `DJANGO_STRIPE_API_VERSION` | **required in every environment** | The Stripe API version. **Set it explicitly** — see below. Staging is on `2026-08-26.dahlia`. |

> **Always set `DJANGO_STRIPE_API_VERSION`.** This runbook used to say "leave it unset, the
> default is read off the installed SDK". That was wrong, and it bit us: on 2026-09-03 the
> SDK default moved from `2026-07-29.dahlia` to `2026-08-26.dahlia` **between two deploys on
> the same day**, because `requirements/base.txt` allows `stripe>=15.5,<16.0` and the rebuild
> picked up 15.6.1. Unset, the inbound webhook payload shape is decided by Stripe's release
> calendar and whenever you last rebuilt — and it must match the version the webhook endpoint
> was *created* at, which cannot be changed afterwards (§3). Pin both sides yourself.

Both secrets default to `""` in `config/settings/base.py` (local/dev convenience) but are
**required** (`env(...)`, no default) in `config/settings/production.py` — a missing
value fails startup rather than silently accepting unsigned webhooks.

> **Migrating an older `.env`.** These variables were renamed to carry the `DJANGO_`
> prefix used by every other setting in this project. An `.env.production` still holding
> the un-prefixed `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` will fail startup with
> `ImproperlyConfigured: Set the DJANGO_STRIPE_SECRET_KEY environment variable` — that is
> the rename, not a lost secret. Rename the keys in place (values unchanged) and restart.

On the staging VPS these live in `.env.production`, managed directly on the box — same
as `DJANGO_FRONTEND_URL`. CI does not sync or know about them; update them over SSH and
restart the stack if either value changes.

## 3. Register the webhook endpoint

In the Stripe dashboard (test mode), add a webhook endpoint:

```text
https://api-staging.kaleem.academy/api/v1/billing/webhook/
```

Subscribe it to exactly these eight event types (this is the full set
`_EVENT_HANDLERS` in `billing/services.py` understands — anything else is logged and
acked with no effect):

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `checkout.session.async_payment_failed`
- `checkout.session.expired`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.paid`
- `invoice.payment_failed`

The three `checkout.session.*` events beyond `completed` matter for
delayed-notification payment methods (SEPA debit, ACH, boleto). Those complete the
session with `payment_status="unpaid"` and the subscription `incomplete`; kaleem
grants nothing until `async_payment_succeeded` arrives. Without them subscribed, a
customer paying by bank debit is charged and never gets access.

**Pin the endpoint's API version — at creation, because it cannot be changed later.**
`WebhookEndpoint` accepts `api_version` only on *create*; the update call ignores it. Getting
this wrong is therefore not a config edit but a full rotation: create a replacement endpoint,
move `DJANGO_STRIPE_WEBHOOK_SECRET` on the VPS to its new signing secret, restart, then delete
the old endpoint. Order matters — keep the old endpoint alive until the new secret is live, or
you drop deliveries. (Both endpoints running briefly is safe: same event id, and
`StripeEventLog` dedupes.)

Set it to the same value as `DJANGO_STRIPE_API_VERSION` (§2) — **not** to whatever the SDK
happens to default to today, which moves with the dependency. Staging: `2026-08-26.dahlia`.

An endpoint registered with *no* version inherits the account default, and Stripe changes
that default over time. Payload shapes are versioned: `2025-03-31.basil`, for example,
moved a subscription's `current_period_end` onto `items.data[].current_period_end` and an
invoice's `subscription` to `parent.subscription_details.subscription`. The parser
tolerates both shapes, but pinning is what makes the payload predictable rather than a
function of Stripe's release calendar. When you upgrade the `stripe` dependency, re-check
this endpoint's version against the new SDK pin.

Copy the endpoint's signing secret into `DJANGO_STRIPE_WEBHOOK_SECRET` on staging.

## 3b. Configure the billing portal

`POST /api/v1/billing/portal/` opens a Stripe-hosted portal session. This is the only
self-serve way out of a failed payment — `past_due` and `unpaid` subscriptions count as
*live*, so they block starting a new subscription, and without a working portal the
customer is locked out of the product and out of the fix at the same time.

Stripe dashboard → Settings → Billing → Customer portal:

- **Payment methods:** allow customers to update.
- **Invoice history:** on.
- **Cancellation:** allow, *at end of billing period* (matches
  `cancel_subscription`, which is cancel-at-period-end).
- **Subscription update:** on, with both plan Prices listed as switchable products.
  Set proration to **create prorations** for upgrades and **at period end** for
  downgrades (the decision recorded in the B2 spec, OQ-B2-2).

⚠ This configuration is *not* in code and CI cannot check it. A portal with
subscription-update switched off silently removes the plan-change path; a portal with
cancellation set to "immediately" would cut access the customer has already paid for.
Re-check it after any Stripe account change.

The set of Prices a given user may switch to is still enforced server-side —
`_allowed_plans_for` mirrors `_require_eligible_buyer`, so a linked child is offered
nothing and a non-parent is never offered Family.

## 3c. Scheduled jobs

Two Celery beat tasks, declared in `config/settings/base.py` so they are reviewable in
code rather than only in the beat database:

| Task | Schedule | What it does |
| --- | --- | --- |
| `billing.tasks.reconcile_subscriptions` | nightly 03:17 | Asks Stripe for every customer's subscriptions and makes kaleem agree. Records a `reconciled_drift` incident per correction. |
| `billing.tasks.detect_webhook_silence` | every 6h | Raises a CRITICAL `webhook_silence` incident when no Stripe event has arrived within `BILLING_WEBHOOK_SILENCE_HOURS` (default 24). |

Both are safe to run by hand during an incident:

```bash
python manage.py shell -c "from kaleem.billing import services; services.reconcile_subscriptions()"
```

The reconciler is what makes **Stripe** the source of truth rather than webhook
delivery. If it stops running, kaleem silently goes back to being only as correct as
the last webhook that happened to arrive.

## 3d. The incident queue

Django admin → Billing → Billing incidents. Everything that needs a human lands here
instead of only in a log line: duplicate live subscriptions, unresolvable events,
unknown subscriptions or prices, amount mismatches, reconciliation drift, webhook
silence.

- Filter by **severity = critical** and **resolved = no** first. `critical` means money
  is wrong right now.
- Rows are read-only except for the **Mark selected incidents resolved** action.
  Resolving is only a flag — the actual fix happens in the Stripe dashboard.
- A repeating problem shows as one row with a rising `occurrences` count. Once
  resolved, the next occurrence opens a fresh row.

## Required settings for the dunning harness

Two account-level settings the nightly `stripe-clock` workflow depends on and
cannot create for itself. An environment missing either produces a harness that
hangs or passes while testing nothing.

1. **Settings → Subscriptions → "manage failed payments" must be set to
   *mark the subscription as unpaid*** after retries are exhausted. The
   alternatives (cancel, or leave it `past_due`) make `unpaid` unreachable — and
   `unpaid` is the only status that revokes entitlement. The harness names this
   setting in its timeout message, so the failure diagnoses itself.
2. **The `STRIPE_SECRET_KEY` repo secret**, holding the `sk_test_…` test-mode key. The
   workflow maps it to `DJANGO_STRIPE_SECRET_KEY`. The harness refuses to run against a
   non-test key (it checks the `sk_test_` prefix), so a live key here fails fast rather
   than touching real customers. The recurring monthly **Price** the harness bills is not
   a secret — it is the committed default in `backend/tests/stripe_clock/conftest.py`.
   Do **not** wire `STRIPE_CLOCK_PRICE_ID` in the workflow: an unset GitHub secret
   resolves to the empty string, which overrides that default and breaks every run.
3. **`DJANGO_STRIPE_API_VERSION` must be set to the Stripe account's current default**
   for the harness run (`2025-06-30.basil` as of 2026-09-04), not to the production pin.
   `stripe listen` renders forwarded events at the account default and offers no way to
   forward at a specific version, so the harness has to meet Stripe where it renders.
   The harness asserts this equality, so if Stripe moves the account default the nightly
   goes red with the observed and expected versions named — which is the intended signal,
   not a flake. When that happens, update this value and check the parsers still handle
   the new shape.

The harness shares the staging Stripe test account. Its objects are bound to a
test clock and deleted on teardown, so they cannot be confused with staging data.

## 4. Local development

Use the Stripe CLI to forward events to your local backend:

```bash
stripe listen --forward-to http://api.kaleem.localhost/api/v1/billing/webhook/
```

`stripe listen` prints a `whsec_…` signing secret for this session — put it in your
local `.env` as `DJANGO_STRIPE_WEBHOOK_SECRET`, and restart the backend so it picks up
the new value. Trigger test events (e.g. `stripe trigger checkout.session.completed`) or
drive the flow through the real `/billing` UI with a test card.

## 5. Manual staging test (D9)

The hosted-Stripe redirect can't run in Playwright (`ISSUES.md`), so this is the
required manual verification before calling B1 done:

1. Log in as a parent (or an adult student not linked as a child) on staging.
2. Go to `/billing`. Click **Subscribe** on a plan.
3. On Stripe's hosted checkout, pay with test card `4242 4242 4242 4242`, any future
   expiry date, any CVC, any postal code.
4. Confirm — Stripe redirects back to `/billing?checkout=success`. The page shows a
   "finishing up…" state while it polls `GET me/subscription/`.
5. Once the webhook lands, the page flips to the active subscription card (status,
   renewal date).
6. Click **Cancel** → confirm in the dialog. The card should now read
   "cancels on `{period_end}`".
7. In the Stripe dashboard, open the subscription and verify `cancel_at_period_end` is
   set to `true`.

If step 4 times out, refresh — the fallback message tells the user webhook delivery may
take a moment; check `stripe listen` (local) or the endpoint's delivery log (staging) for
a failed delivery before assuming a bug.

## 6. Incident: duplicate live subscription

**Symptom.** A `duplicate_live_subscription` row in the incident queue (severity
`critical`), and a `CRITICAL` log line:

```text
billing.webhook.duplicate_live_subscription reason=… user_id=… existing_subscription=sub_… incoming_subscription=sub_… event_id=…
```

**What it means.** Stripe reported a second live subscription for a user who already has
one — most often the user opened checkout in two tabs and completed both. `reason` says
which defence caught it: `pre_write_check` (the service read the existing row first) or
`db_constraint` (the read lost a race and the
`unique_live_subscription_per_user` constraint caught the insert).

**What kaleem did.** Nothing beyond refusing to record the second subscription. It did
**not** cancel or refund anything in Stripe, and it acked the webhook 200 on purpose (a
non-2xx would make Stripe retry a request that can never succeed, for three days). The
customer's account still shows exactly one subscription.

**What you must do.** The customer is very likely being billed twice by Stripe right now,
and only Stripe knows it. This needs a human — which subscription to void and whether to
refund is a money decision the webhook handler must not make silently.

1. Open the Stripe dashboard → Customers → the user (`user_id` in the log line maps to
   `BillingCustomer.user`; the customer id is on that row, read-only in Django admin).
2. Confirm both `existing_subscription` and `incoming_subscription` are live in Stripe.
3. Decide which to keep — normally the one kaleem has recorded (`existing_subscription`),
   so the app and Stripe agree without any local edit.
4. Cancel the other **immediately** (not at period end) in Stripe, and refund the charge
   it has already taken if the customer paid for it.
5. If you instead keep `incoming_subscription`, you must also fix the local row: cancel
   `existing_subscription` in Stripe, then update the `Subscription` row in Django admin
   to the surviving `stripe_subscription_id`. Do this only if there is a reason to; the
   simple path is step 3.
6. Mark the incident resolved in Django admin, and note it in the journal. A rising
   `occurrences` count on one row means the same duplicate keeps being re-reported;
   repeated *distinct* incidents mean something is letting users open two checkouts,
   which is a bug to fix rather than an incident to keep clearing.

Related: the `unique_live_subscription_per_user` constraint is added by migration
`billing/0003` and widened by `billing/0004` to cover `unpaid` and `incomplete` as well
as `active` and `past_due`. If either migration fails to apply, it is because a user
already has two live rows — reconcile them in Stripe (above) and fix the rows before
deploying.

## 7. Incident: webhook silence

**Symptom.** A `webhook_silence` incident, severity `critical`.

**What it means.** No Stripe event has reached us for longer than
`BILLING_WEBHOOK_SILENCE_HOURS`. Usually the endpoint secret was rotated, the endpoint
was deleted or disabled in Stripe, or the API host has been unreachable long enough for
Stripe to give up retrying.

**What to check, in order.**

1. Stripe dashboard → Developers → Webhooks → the endpoint. Is it enabled? Are recent
   deliveries failing, and with what status?
2. If deliveries show `400 Invalid webhook signature`, the signing secret no longer
   matches `DJANGO_STRIPE_WEBHOOK_SECRET`. Copy it again and redeploy.
3. If deliveries show 5xx, read the application logs for that window.
4. Once fixed, **run the reconciler by hand** (§3c). Stripe will not resend events it
   has given up on, so anything lost during the silence is only recoverable by
   reconciling.

**What kaleem did meanwhile.** Checkouts completed in the browser still settled, because
`POST /billing/checkout/settle/` asks Stripe directly rather than waiting to be told.
Everything *after* checkout — renewals, failed cards, cancellations — was not applied
until the reconciler next ran.

## 8. Incident: amount mismatch

**Symptom.** An `amount_mismatch` incident, severity `critical`, with `expected_*` and
`charged_*` in its detail.

**What it means.** Stripe charged something other than what the plan says it sells —
almost always a `SubscriptionPlan.stripe_price_id` pointing at the wrong Price, or a
Price edited in the Stripe dashboard without the plan being updated.

**What kaleem did.** Recorded the subscription anyway. The customer *was* charged;
refusing to record it would leave them paying for nothing.

**What you must do.** Decide which side is wrong. If the Price is right and the plan row
is stale, fix `display_amount`/`currency`/`stripe_price_id` in Django admin. If the plan
is right and the customer was overcharged, refund the difference in Stripe. Then resolve
the incident.
