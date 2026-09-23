---
name: billing-hardening
phase: B
modules: [billing, identity]
status: implemented
created: 2026-08-13
closed: 2026-09-04
extends: docs/superpowers/specs/2026-07-09-billing-subscriptions-design.md
---

## Why

B1 shipped subscriptions, entitlement, and webhook mirroring. A logic review of the
merged module (`backend/kaleem/billing/`) found that the design is sound in shape —
provider seam, idempotency ledger, out-of-order guard, partial unique constraint — but
that it treats the Stripe webhook as the **only** channel through which money facts
reach kaleem, and that "one subscription per user" is enforced over too narrow a set of
states. Both produce silent, money-losing failures.

This spec records the full audit and defines the remediation.

Scope note: findings marked **[bug]** are defects in shipped B1 code and are fixed under
this spec. Findings marked **[gap]** are missing capability — same spec, but they are new
behaviour, not regressions. Findings marked **[note]** are recorded and deliberately not
acted on now.

---

## Part 1 — Audit findings

### A. Duplicate / double subscription (the reported bug #1)

**A1 [bug] — the "one live subscription" invariant covers only two of six states.**

`LIVE_STATUSES = (ACTIVE, PAST_DUE)` (`services.py:31`) and the partial unique constraint
`unique_live_subscription_per_user` (`models.py:87`) both key off exactly those two
statuses. But `_writable_status` will happily write `unpaid`, `incomplete`, and
`incomplete_expired` onto a row from a `customer.subscription.updated` event
(`services.py:245`).

A subscription in Stripe status `unpaid` still exists upstream and is still recoverable.
Ours is invisible to `get_current_subscription`, so `create_checkout` waves the user
through (`services.py:82`), and the DB constraint does not fire because neither row is
`active`/`past_due`. Result: **two real Stripe subscriptions for one user, both billable,
only one visible in the UI.** Same path via `incomplete`.

**A2 [bug] — a duplicate is detected and then dropped on the floor.**

When the constraint does fire, `_apply_checkout_completed` catches the `IntegrityError`,
calls `_log_duplicate_live_subscription`, and acks 200 (`services.py:155`). The comment is
right that auto-cancelling is a money decision a webhook must not make silently — but the
only durable trace is a `logger.critical` line. There is no table, no queue, no admin
surface, nothing that survives log rotation or a missing alert rule. In practice a
customer paying twice is discovered when they complain.

**A3 [gap] — no way to change plan, which is what makes A1 user-visible.**

`create_checkout` refuses any user with a live subscription, and there is no
`Subscription.modify(items=…)` path. An Individual subscriber who wants Family, or a
Family subscriber who wants to downgrade, has no supported route. The unsupported route
they will actually take is: cancel, wait, resubscribe — or, if their row happens to be in
one of the A1 states, subscribe again on top. Enforcing "one subscription" without
shipping "change plan" is what turns A1 from a rare race into a path users are pushed
down.

**A4 [gap] — no idempotency keys on any Stripe write.**

`Customer.create`, `checkout.Session.create`, and `Subscription.modify` are all called
without `idempotency_key` (`providers/stripe_provider.py:124,132,147`). Stripe documents
this as required for safe retries. Without it, a client retry or a double-submitted
checkout button creates a second Checkout Session (and `_ensure_customer` admits it
orphans Stripe customers, `services.py:69`).

---

### B. Webhook is the single source of truth (the reported bug #2)

**B1 [gap] — nothing reconciles kaleem against Stripe, ever.**

There is exactly one write path into `Subscription`: `handle_webhook`. There is no
periodic reconciliation, no fetch-on-redirect, no admin "resync" action, and no alert on
webhook silence. `django_celery_beat` is already configured
(`config/settings/base.py:205`), so the machinery exists and is simply unused.

Concretely, every one of these fails silently today:

| Failure | Consequence |
| --- | --- |
| Webhook endpoint misconfigured / secret rotated | User pays, gets nothing, forever |
| Our API down during delivery + Stripe exhausts its 3-day retry | Same |
| Event delivered but handler no-ops (unknown plan/user, A2 duplicate) | Same, and we acked 200 so Stripe will never resend |
| Cancellation processed by Stripe, `deleted` event lost | Row stays `ACTIVE` → **free access forever** |
| Renewal payment fails, `payment_failed` lost | User keeps access unpaid |

Note the symmetry: losing events costs us money in one direction and costs the customer
money in the other. `cancel_subscription` makes this vivid — it calls Stripe, sets
`cancel_at_period_end=True`, and returns success, but **never touches `status`**
(`services.py:314`). The only thing in the entire system that ends access is an inbound
webhook.

**B2 [bug] — the out-of-order guard is missing on `checkout.session.completed`.**

`_is_out_of_order` is called from `_apply_to_existing` only (`services.py:215`).
`_apply_checkout_completed` writes `status=ACTIVE` via `update_or_create` with no ordering
check at all (`services.py:151`). A late-delivered `checkout.session.completed` landing
after the `customer.subscription.deleted` that superseded it resurrects the row to
`ACTIVE` — precisely the resurrection bug that was fixed for `updated` and missed here.

**B3 [bug] — `checkout.session.completed` grants access without checking `payment_status`.**

The provider hardcodes `status="active"` for this event
(`providers/stripe_provider.py:180`) and services hardcodes `Subscription.Status.ACTIVE`
(`services.py:143`). Neither reads `session.payment_status`. For delayed-notification
payment methods (SEPA debit, ACH, boleto — all plausible for an international student
base) the session completes with `payment_status='unpaid'` and the subscription is
`incomplete`. We grant full entitlement to an unpaid subscription, and if the payment
later fails we never hear about it, because…

**B4 [gap] — `checkout.session.async_payment_succeeded` / `async_payment_failed` /
`checkout.session.expired` are not handled.** They fall through to the "ignored" branch
(`services.py:290`). These are the events that resolve B3.

**B5 [note] — other unhandled events.** `customer.subscription.trial_will_end`,
`customer.subscription.paused`/`resumed`, `invoice.payment_action_required`,
`charge.dispute.created`. None are reachable with today's plan configuration (no trials,
no pause, no disputes handled anywhere in the product). Recorded, not built.

---

### C. Entitlement and lifecycle logic

**C1 [gap] — a failed payment locks the customer out with no self-serve recovery.**

`past_due` is not paid-through (`_is_paid_through`, `services.py:331`) → entitlement is
revoked. `past_due` *is* a live status → `create_checkout` refuses a new subscription.
There is no Stripe Billing Portal session endpoint and no update-payment-method flow
anywhere in backend or dashboard. A customer whose card expires is therefore locked out
of the product **and** locked out of fixing it, with no notification (the `notifications`
module does not exist yet). This is the single worst customer-facing outcome in the
module and it is reachable by an ordinary expired card.

**C2 [gap] — no grace period.** Revoking on the first `invoice.payment_failed` is a policy
choice made implicitly by the status map. Standard practice is to keep access through the
provider's retry schedule (Stripe Smart Retries run ~2 weeks) and revoke at `unpaid`.
Requires a product decision — see Open Questions.

**C3 [bug] — `_is_paid_through`'s CANCELED branch is effectively dead, and the
"access until period end" promise is unbacked.** `cancel_subscription` never writes
`CANCELED`; the row only becomes `CANCELED` when `customer.subscription.deleted` arrives,
at which point `_mirrored_period_fields` overwrites `current_period_end` with a timestamp
that is already in the past. So the branch that is supposed to honour paid-through-period
access almost never returns `True`. The promise currently holds only because the row stays
`ACTIVE` until deletion — i.e. by accident, via the same webhook we cannot rely on (B1).

**C4 [note] — `_has_paid_through` scans every historical subscription row in Python**
(`any(_is_paid_through(s) for s in query)`, `services.py:346`) and family inheritance
loops one query per parent. Correct, but it is the hot path for every gated action in
the product. Fine at current scale; revisit when scheduling starts calling it per booking.

---

### D. Data integrity and operations

**D1 [gap] — nothing verifies that what Stripe charged matches the plan we sold.**
`_apply_checkout_completed` trusts `metadata.plan_id` and never cross-checks the price on
the resulting subscription against `plan.stripe_price_id`, nor the invoice amount against
`display_amount`/`currency`. A mis-mapped price in the dashboard bills the wrong amount
indefinitely, undetected.

**D2 [gap] — no operator surface for billing incidents.** A2, plus every
`billing.webhook.unresolved` / `unknown_subscription` / `unmapped_status` warning, exists
only as a log line. No dead-letter table, no admin view, no replay.

**D3 [note] — `StripeEventLog` grows without bound.** No retention policy. Harmless for
years; note it before it is a surprise.

**D4 [note] — no tax handling.** `automatic_tax` is not enabled and no billing address is
collected. Selling digital services internationally carries VAT/sales-tax obligations.
This is a business decision, not an engineering one — flagged for `docs/decisions/`, not
built here.

**D5 [note] — `get_current_subscription` does not `select_related("plan")`**, so
`MySubscriptionView` issues an extra query for the `current` block. Trivial.

---

## Part 2 — Remediation

Ordered by "what stops money being lost", not by effort.

**Status 2026-08-13:** all of R1–R8 implemented. R2 was pulled to the front after the
owner reproduced B1 directly (webhook delivery disabled → card charged, kaleem never
learned about it), since settle-on-redirect is the direct fix for that path.
Backend `feat/billing-hardening`, dashboard `feat/billing-hardening`.

### R1 — Widen the live-subscription invariant (fixes A1)

- `LIVE_STATUSES` becomes `(ACTIVE, PAST_DUE, UNPAID, INCOMPLETE)`.
- New migration widening `unique_live_subscription_per_user`'s condition to the same four
  statuses, spelled literally (keeping the existing convention).
- `incomplete_expired` and `canceled` remain terminal.
- Entitlement is unchanged: `LIVE_STATUSES` answers "does this row still have a claim on
  the user", `_is_paid_through` answers "is the user covered". Widening one must not widen
  the other — a regression test asserts an `unpaid` row is live-but-not-entitled.

### R2 — Reconciliation, so Stripe is authoritative (fixes B1)

Three independent channels, so no single one is load-bearing:

1. **On redirect.** A new `POST /api/v1/billing/checkout/{session_id}/settle` that
   retrieves the Checkout Session from Stripe and applies the same state transition the
   webhook would. The dashboard's existing "finishing up…" poller calls this instead of
   blind-polling our own API. Turns the common case (webhook is merely slow) into a
   synchronous confirm.
2. **Nightly reconciliation task.** A Celery beat task walking
   `stripe.Subscription.list(status="all")` for every `BillingCustomer`, diffing status /
   `current_period_end` / `cancel_at_period_end` / price against our rows, correcting
   drift, and recording every correction as a billing incident (R5). Also flags our-side
   rows with no Stripe counterpart and vice versa.
3. **Webhook silence alarm.** A task that raises an incident when `StripeEventLog` has
   received nothing in N hours during a period where we expect traffic.

The reconciler is the only writer allowed to bypass the out-of-order guard, and only
because Stripe's live object is by definition the newest state.

### R3 — Fix the webhook handler defects (fixes B2, B3, B4)

- Apply `_is_out_of_order` in `_apply_checkout_completed` before writing (B2).
- Parse `payment_status` into `WebhookEvent`; on `checkout.session.completed`, write
  `ACTIVE` only when `payment_status in ("paid", "no_payment_required")`, otherwise write
  `INCOMPLETE` (B3).
- Handle `checkout.session.async_payment_succeeded` → `ACTIVE`,
  `async_payment_failed` → `INCOMPLETE_EXPIRED`, `checkout.session.expired` → no-op with
  an info log (B4).

### R4 — Self-serve recovery and plan change (fixes C1, A3)

- `POST /api/v1/billing/portal` → `stripe.billing_portal.Session.create`, returning a
  redirect URL. This is the standard, PCI-clean way to update a card, view invoices, and
  cancel. It also gives `past_due` users a way out, which is the C1 fix.
- Plan change: configure the portal's subscription-update flow against the active plan
  set rather than building our own proration UI. Per OQ-B2-2, **upgrades prorate
  immediately (`proration_behavior=create_prorations`) and downgrades take effect at
  period end (`schedule_at_period_end`)** — both are portal configuration, not code.
  `customer.subscription.updated` already mirrors the result; extend `_apply_to_existing`
  to also re-point `plan` when the subscription's price no longer matches the stored plan.
- Eligibility is not enforceable inside the portal, so the portal's allowed-plan set is
  configured per customer at session-create time: a user with no parent profile is not
  offered Family, mirroring `_require_eligible_buyer`. This is the one place where the
  eligibility rule has to exist twice; a test asserts the two stay in step.
- The portal makes cancel-from-portal reachable, which is fine — it lands as
  `customer.subscription.updated`/`deleted` like any other cancel.

### R5 — Billing incidents table (fixes A2, D2)

A `BillingIncident` model (`kind`, `severity`, `user`, `stripe_object_id`, `event_id`,
`detail` JSON, `resolved_at`, `resolved_by`) written by every place that currently only
calls `logger.critical` / `logger.warning` about unresolvable state, plus by the
reconciler. Read-only in Django admin except for resolve. This is what turns "a customer
may be paying twice" from a log line into a work queue.

### R6 — Idempotency and amount verification (fixes A4, D1)

- `idempotency_key` on every Stripe write. Key derivation: `ensure_customer` →
  `f"customer:{user.id}"`; `create_checkout_session` → `f"checkout:{user.id}:{plan.id}:{nonce}"`
  where the nonce is stable per in-flight attempt; `cancel_at_period_end` →
  `f"cancel:{subscription_id}"`.
- On `checkout.session.completed` and `invoice.paid`, verify the price id on the
  subscription matches `plan.stripe_price_id` and the amount matches
  `display_amount`/`currency`; on mismatch, still mirror the subscription (the customer
  *was* charged) but raise a `BillingIncident`.

### R7 — Cancellation writes local state (fixes C3)

`cancel_subscription` stays cancel-at-period-end, but records `current_period_end` from
the provider response so `_is_paid_through`'s CANCELED branch has a real value to work
with, and so access ends on schedule even if the `deleted` event never arrives. The
nightly reconciler is the backstop.

### R8 — Grace period (fixes C2)

**Decided 2026-08-13:** a `past_due` customer keeps **full** access for as long as Stripe's
Smart Retries are still running, and loses it the moment the subscription reaches `unpaid`.
Access does not degrade in between — a customer mid-dunning is a paying customer having a
bad week, not a lapsed one.

Implementation: `_is_paid_through` returns `True` for `PAST_DUE`. No timer of our own, no
`past_due_since` column — Stripe already owns the retry schedule and moving to `unpaid` is
its signal that the schedule is exhausted. Building a parallel clock would only drift from
it.

This makes R1 load-bearing: `unpaid` becomes the status that both revokes entitlement and
(via the widened `LIVE_STATUSES`) still blocks a second checkout, which is exactly why R4's
portal is required in the same slice — otherwise `unpaid` is the new C1 dead end.

---

## Non-goals

- Session quota enforcement (`sessions_per_cycle`) — still B3 territory, unchanged.
- Local/regional payment methods (OQ-06) — the provider seam already anticipates this.
- Tax (D4), dunning email (needs `notifications`), invoice PDFs, proration UI of our own.

## Decisions and open questions

- **OQ-B2-1 — RESOLVED 2026-08-13.** A `past_due` customer keeps full access through
  Stripe's retry schedule; entitlement stops at `unpaid`. See R8.
- **OQ-B2-2 — RESOLVED 2026-08-13.** Plan changes go through the Stripe Billing Portal's
  subscription-update flow: **upgrades prorate immediately, downgrades take effect at
  period end**. We build no proration UI and no switch endpoint of our own; the result
  arrives as an ordinary `customer.subscription.updated`. See R4.
- **OQ-B2-3 — OPEN, does not block.** When the reconciler finds a genuine double
  subscription (A2), is auto-cancelling the *newer* one with a proportional refund
  acceptable policy, or does every case stay manual? Proposal: manual until we have seen a
  few real ones — R5's incident queue is built to make manual handling tolerable, so
  nothing is blocked on this.

## Definition of Done

Standard D9, plus: reconciliation task covered by tests that assert it corrects each drift
direction; a test proving an `unpaid` row blocks a second checkout; a test proving a late
`checkout.session.completed` cannot resurrect a canceled row; runbook
`docs/runbook/stripe-billing.md` extended with the incident queue and the reconciler.

---

## Closure (2026-09-04)

All thirteen audit findings are remediated, merged, and live on staging since 2026-08-17.
Verified over HTTP against `api-staging` rather than inferred from a green build: the two
new B2 endpoints return 403 rather than 404 (so new code is serving, not a stale image),
and the webhook returns 400 on an unsigned body (so signature verification is live). The
full click-through ran twice on 2026-09-03 and reconciled exactly with Stripe both times.

### The one thing that is still not proven, stated precisely

The `past_due` **renewal** path has never run against real Stripe. It is worth being exact
about how big that hole is, because "past_due is untested" overstates it:

- **Covered by tests, at the provider seam:** `invoice.payment_failed → past_due`;
  `past_due` is entitled; `unpaid` is not; a child inherits a `past_due` Family plan and
  does not inherit an `unpaid` one; an `unpaid` row still blocks a second checkout.
- **Covered by the manual click-through:** a *declined card at checkout*
  (`4000 0000 0000 0341` → zero subscriptions, not entitled, no incidents).
- **Not covered by anything:** that Stripe's *real* renewal failure emits those events, in
  the shape we parse, on a subscription that was already `active`. That transition cannot
  be clicked — it needs **Stripe test clocks** to advance the billing cycle.

So the untested part is the wiring between real Stripe and handlers that are themselves
well covered. That is a narrower risk than an untested state machine — but it is not a
small one, because R8 makes `unpaid` the status that actually revokes access, and `unpaid`
is only ever reached by walking through `past_due` on a real renewal schedule. **The one
transition nobody has ever observed is the one that takes entitlement away.**

### Why that does not block closing the specs

Closing a spec asserts *what it designed was built and verified*. It does not assert the
phase is done. The test-clock gap stays a `blocks a phase close` entry in `ISSUES.md`,
where it already is, and it should be worked before real money — not held open as an
indefinitely-`draft` spec, which is how B1 sat unclosed for eight weeks while its contents
shipped, drifted, and were amended by another spec.

**OQ-B2-3 remains open and still does not block:** whether the reconciler should
auto-cancel a genuine double subscription with a proportional refund, or leave every case
manual. Manual until we have seen a few real ones; R5's incident queue exists to make that
tolerable.
