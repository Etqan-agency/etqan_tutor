# billing — architecture

Stripe-backed monthly subscriptions and the single entitlement gate the rest of the
system checks before letting a user book a session. `billing` mirrors Stripe's state via
webhooks; it never decides pricing or payment logic itself — Stripe does, and `billing`
records what Stripe reports.

Spec: `docs/superpowers/specs/2026-07-09-billing-subscriptions-design.md` · Status:
shipped (Phase B, B1).

## Data model

```mermaid
erDiagram
    User ||--o| BillingCustomer : has
    User ||--o{ Subscription : "pays for (over time)"
    SubscriptionPlan ||--o{ Subscription : "sold as"
```

- **SubscriptionPlan** — admin-CRUD via Django admin. `plan_type` (`individual` |
  `family`), `sessions_per_cycle` (per-student for Individual, per-child for Family),
  `stripe_price_id` (the recurring Stripe Price — charge source of truth),
  `display_amount` (minor units) + `currency`, `is_active`. Display copy (name,
  description) is **not** stored here — the frontend supplies bilingual copy keyed on
  `plan_type`.
- **BillingCustomer** — `OneToOneField` `user` → `stripe_customer_id`. Created lazily on
  a user's first checkout (`_ensure_customer`), never eagerly.
- **Subscription** — many-over-time per user (`ForeignKey`, not `OneToOne` — a user can
  resubscribe after lapsing). `stripe_subscription_id` (unique), `status` (mirrors
  Stripe: `active` / `past_due` / `canceled` / `incomplete` / `incomplete_expired` /
  `unpaid`), `current_period_end` (nullable — see below), `cancel_at_period_end`,
  `last_event_at` (nullable — the provider timestamp of the newest event applied to the
  row). Indexed on `(user, status)`. At most one row is *live* per user, enforced by a
  partial `UniqueConstraint` (`unique_live_subscription_per_user`, on `user` where
  `status IN ('active', 'past_due')`) **and** by a pre-write check in `services`. The
  service check alone is not enough: `create_checkout`'s guard is a TOCTOU read, so two
  browser tabs both completing checkout would otherwise produce two live rows — and the
  second would bill monthly while being invisible in the UI, which only ever shows and
  cancels the newest live row.
- **StripeEventLog** — `stripe_event_id` (unique), `event_type`, `received_at`,
  `processed_at` (nullable). The idempotency ledger: a webhook whose event id is already
  present and processed is a no-op (`billing/services.py:160-173`).

`current_period_end` is nullable because `checkout.session.completed` activates a
subscription with `status=active` before Stripe has reported a period end; the follow-up
`customer.subscription.updated` / `invoice.paid` events fill it in. Entitlement treats a
bare `active` status as paid-through regardless, so there is no coverage gap during that
window.

## Public service API (`billing/services.py`)

All inter-module and API-layer access goes through here.

| Function | Signature | Purpose |
| --- | --- | --- |
| `list_active_plans` | `() -> QuerySet[SubscriptionPlan]` | Active plans, `id` order. |
| `create_checkout` | `(user, plan_id: int) -> str` | Validates buyer role fits the plan and that they have no current subscription, ensures a `BillingCustomer`, returns a Stripe-hosted checkout URL. |
| `get_current_subscription` | `(user) -> Subscription \| None` | The user's live subscription (see `LIVE_STATUSES` below). |
| `cancel_subscription` | `(user) -> Subscription` | Sets `cancel_at_period_end` via the provider and locally; raises `NotFoundError` if the user has no current subscription. |
| `handle_webhook` | `(payload: bytes, signature: str) -> None` | Verifies the signature, de-duplicates via `StripeEventLog`, applies the event. Raises `ValidationError` on a bad signature. |
| `Capability` | `StrEnum` (`BOOK_SESSION`) | What a subscription entitles a user to. Only one member exists; the enum exists so call sites don't change when more are added. |
| `is_entitled_to` | `(user, capability: Capability) -> bool` | The entitlement gate other modules call. `capability` is currently unused (every capability resolves to the same subscription check) — kept for a stable signature. |

Errors are typed (`platform.exceptions.NotFoundError` / `ValidationError` /
`PermissionDeniedError`), never bare `Exception`.

### `LIVE_STATUSES` vs. entitlement — read this before touching either

Two different questions, two different answers, both deliberate:

- **`get_current_subscription`** uses `LIVE_STATUSES = (ACTIVE, PAST_DUE)` — "which row
  is this user's *current* subscription", i.e. still has some claim on them (paying, or
  failing to pay). This is what the `/billing` UI shows and what `cancel_subscription`
  operates on. `past_due` counts as current because the user still has a subscription to
  see, manage, or have retried — it just isn't paid.
- **`is_entitled_to`** (via `_is_paid_through`) answers "can this user book a session
  right now" — `active` ⇒ yes; `canceled` ⇒ yes only while `current_period_end` is still
  in the future (access continues through the paid month); every other status,
  **including `past_due`**, ⇒ no.

So a `past_due` subscription is simultaneously "current" (shows up in `/billing`, can be
cancelled) and "not entitled" (can't book). Don't unify these into one status set —
that's the whole point of having two separate checks.

### Entitlement matrix

| Subscription status | `current_period_end` | Entitled? |
| --- | --- | --- |
| `active` | any (may be null right after checkout) | Yes |
| `canceled` | in the future | Yes (paid through) |
| `canceled` | in the past / null | No |
| `past_due` | any | No |
| `incomplete` / `incomplete_expired` / `unpaid` | any | No |
| *(none — no subscription row)* | — | No |

**Family chaining:** a student with no qualifying subscription of their own is entitled
if **any** parent (`identity_services.get_parent_user_ids(user.id)`) holds a paid-through
subscription on a **Family** plan (`_has_paid_through(parent_id,
plan_type=SubscriptionPlan.PlanType.FAMILY)`). An Individual plan held by someone else
never chains.

## Provider abstraction (`billing/providers/`)

`PaymentProvider` (`providers/__init__.py`) is a `Protocol`:

```python
class PaymentProvider(Protocol):
    def ensure_customer(self, user) -> str: ...
    def create_checkout_session(self, request: CheckoutRequest) -> str: ...
    def cancel_at_period_end(self, subscription_id: str) -> None: ...
    def verify_and_parse_webhook(self, payload: bytes, signature: str) -> WebhookEvent: ...
```

`get_provider()` instantiates `settings.BILLING_PAYMENT_PROVIDER` (a dotted path,
`django.utils.module_loading.import_string`) — currently
`kaleem.billing.providers.stripe_provider.StripeProvider`, the only implementation.
`WebhookEvent` and `CheckoutRequest` are provider-neutral dataclasses; `services.py` only
ever sees these, never a raw Stripe object. **`stripe_provider.py` is the only file in
`billing` that imports the `stripe` SDK** — everything else, including `services.py`, is
provider-agnostic.

To add a second provider (OQ-06, local payment methods): implement the `PaymentProvider`
Protocol in a new `providers/<name>_provider.py`, point
`DJANGO_BILLING_PAYMENT_PROVIDER` at it, and translate that provider's webhook payload
into `WebhookEvent` — no change needed in `services.py`.

## HTTP endpoints (`billing/api/`)

Session auth + CSRF like the rest of the API, **except the webhook**. Mounted at
`/api/v1/billing/` (`config/api_router.py`).

| Endpoint | Method | Auth | Response |
| --- | --- | --- | --- |
| `plans/` | GET | session | `[{ id, plan_type, sessions_per_cycle, display_amount, currency }]` |
| `checkout/` | POST `{ plan_id }` | session | `{ checkout_url }`; 400 if already subscribed; 403 on role/plan mismatch |
| `me/subscription/` | GET | session | `{ current: {...} \| null, history: [...] }`, each item `{ id, plan_type, sessions_per_cycle, status, current_period_end, cancel_at_period_end }` |
| `me/subscription/cancel/` | POST | session | the updated subscription (same shape as above); 404 if no current subscription |
| `webhook/` | POST | **Stripe signature only** | `{ received: true }` |

`GET me/subscription/` history is `request.user.subscriptions.select_related("plan")`
ordered newest-first; `current` reuses `get_current_subscription` (see the
`select_related` note in `ISSUES.md` — it costs one extra query there).

## Webhook: signature auth and CSRF exemption (ADR-0025)

`POST /api/v1/billing/webhook/` is server-to-server: no browser, no session, no CSRF
token. `StripeWebhookView` carries `@method_decorator(csrf_exempt, name="dispatch")`,
`authentication_classes = []`, `permission_classes = [AllowAny]` — the **only**
CSRF-exempt endpoint in the codebase. In its place, `handle_webhook` verifies the
`Stripe-Signature` header as an HMAC against `STRIPE_WEBHOOK_SECRET` **before** touching
any row; a bad signature raises `ValidationError` → HTTP 400 with no state change.
`StripeEventLog` makes every handler idempotent against Stripe's at-least-once retries.
Full reasoning, threat model, and the "never copy this pattern" warning:
`docs/adr/0025-stripe-webhook-csrf-exemption.md`.

Handled event types (unknown types are logged and acked 200, no effect):

- `checkout.session.completed` → create/activate the `Subscription` (`status=active`).
  Ignored (logged, acked) when the plan id or user id in the session metadata does not
  resolve, or when the session carries no subscription at all (a `mode=payment` session,
  or another integration sharing the Stripe account). If the user already has a *live*
  row with a different `stripe_subscription_id`, nothing is written and nothing is
  cancelled upstream: the handler logs at **CRITICAL** and acks 200. Deciding which
  subscription to void and whether to refund is a money decision for an operator — see
  `docs/runbook/stripe-billing.md`, "Duplicate live subscription".
- `customer.subscription.updated` → sync `status` (only if it maps onto
  `Subscription.Status`; an unrecognised value is logged and dropped rather than
  written), `current_period_end`, `cancel_at_period_end`. Never moves a row *out of*
  `canceled`.
- `customer.subscription.deleted` → `status=canceled`, **hardcoded** from the event type
  rather than read from the payload (symmetrically with `checkout.session.completed`
  hardcoding `active`). Trusting the payload's `status` here meant a missing or unmapped
  value wrote no status at all, leaving a deleted subscription `active` — i.e. still
  entitled, for free. `current_period_end` / `cancel_at_period_end` are still mirrored.
- `invoice.paid` → `status=active`, refresh `current_period_end`.
- `invoice.payment_failed` → `status=past_due`.

**Ordering.** Stripe does not guarantee delivery order, so every event carries its
provider timestamp (`WebhookEvent.created`) and each applied event stamps
`Subscription.last_event_at`. An event older than the stored value is discarded: without
this, a late-delivered `customer.subscription.updated` (`status=active`) landing after
the `deleted` that superseded it would resurrect a dead subscription — an `active` row
with no upstream subscription behind it, i.e. free access forever. The "never leave
`canceled` on an `updated`" rule above is the floor beneath that guard, for when
timestamps cannot help (missing or equal `created`).

**Payload versioning.** Webhook payload shapes are versioned, and an endpoint registered
without an explicit version inherits the Stripe *account* default — so a Stripe-side
upgrade can reshape our inbound payloads with no deploy on our side. `2025-03-31.basil`
did exactly that: it moved a subscription's `current_period_end` onto
`items.data[].current_period_end` and an invoice's `subscription` to
`parent.subscription_details.subscription`. Two defences: `StripeProvider.__init__` pins
`stripe.api_version` from `settings.STRIPE_API_VERSION` (default read off the installed
SDK's own outbound pin, override with `DJANGO_STRIPE_API_VERSION`), and the parser reads
the new locations first with the legacy fields as fallback. Both shapes are covered by
tests. The Stripe dashboard endpoint must be pinned to the same version — see the
runbook.

**Failures never become retry loops.** Everything reachable from a webhook that could
raise is handled and acked: unresolvable metadata, non-numeric metadata, a session with
no subscription, and `IntegrityError` from the live-subscription constraint (on both the
`checkout.session.completed` insert and the `_apply_to_existing` save, each inside a
savepoint so the surrounding transaction and the `StripeEventLog` write survive). An
unhandled 500 here would make Stripe retry the same doomed event for three days.

## Module boundaries

`billing` may import `kaleem.platform` and call `kaleem.identity.services`
(`get_parent_profile`, `get_student_profile`, `get_parent_user_ids`) — nothing else.
Enforced by two import-linter `forbidden` contracts in `pyproject.toml`: "billing
imports no business modules except identity" lists every other business module as
forbidden, and "billing does not import identity models directly" names
`kaleem.identity.models` specifically — D4's headline rule is only actually enforced if
the models package is listed. The second contract needs `allow_indirect_imports` (and so
its own contract) because `billing` legitimately imports `kaleem.identity.services`,
which of course imports its own models; `kaleem.billing.tests.*` is exempted, since test
fixtures build identity rows directly. `scheduling` (and later modules) call `billing.services.
is_entitled_to` directly for gating — `billing` never imports `scheduling`.

`identity.services.get_parent_user_ids(student_user_id: int) -> list[int]` was added for
this module: resolves every parent linked to a student, empty list if none, used only
for Family entitlement chaining.
