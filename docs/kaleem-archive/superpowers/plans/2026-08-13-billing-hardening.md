---
name: billing-hardening
spec: docs/superpowers/specs/2026-08-13-billing-hardening-design.md
created: 2026-08-13
status: done
---

## Plan — billing hardening (B2)

Implements the R1–R8 remediation from the spec. TDD throughout (D3): failing test first,
then code, 100% line + branch on `kaleem.billing`.

**Branching.** Backend `feat/billing-hardening` → main. Dashboard `feat/billing-hardening`
→ main. Meta `feat/billing-hardening` (this spec + plan + STATE + ISSUES) → develop.
Submodule pointers bumped in a follow-up meta commit only after both submodule PRs merge —
same discipline as B1.

**Slice order is deliberate.** Slice 1 is the money-losing defects and ships alone if
everything after it slips. Slice 2 must not ship without slice 3 — widening `LIVE_STATUSES`
to include `unpaid` while `unpaid` has no recovery path would create a worse dead end than
the one it fixes (spec R8).

---

### Slice 1 — webhook handler defects (R3, R7)

Pure bug fixes to shipped code. No new models, no new endpoints, no migration.

1. **Out-of-order guard on checkout completion (B2).**
   Test: a `checkout.session.completed` whose `created` predates a row's `last_event_at`
   leaves a `CANCELED` row canceled. Then: call `_is_out_of_order` in
   `_apply_checkout_completed` before the `update_or_create`, on the row found by
   `stripe_subscription_id` (not the live-for-user lookup — a resurrected row is not live).
2. **`payment_status` gates ACTIVE (B3).**
   Test: a completed session with `payment_status="unpaid"` produces an `INCOMPLETE` row
   and no entitlement; `"paid"` and `"no_payment_required"` produce `ACTIVE`. Then: add
   `payment_status` to `WebhookEvent`, parse it in the provider, branch in
   `_apply_checkout_completed`.
3. **Async payment events (B4).**
   Test each of `async_payment_succeeded` → `ACTIVE`, `async_payment_failed` →
   `INCOMPLETE_EXPIRED`, `checkout.session.expired` → no-op + info log. Then: route them in
   `_handle_event`. Note `async_payment_*` carry a session object, so they resolve by
   `obj["subscription"]` like `completed` does, not by `obj["id"]`.
4. **Cancellation records the period end (C3/R7).**
   Test: `cancel_subscription` on a row with a future period end leaves the user entitled,
   and a row whose period end has passed is not entitled, *without any webhook*. Then: have
   `cancel_at_period_end` return the provider's `current_period_end` and persist it.
   `_is_paid_through`'s CANCELED branch finally has a real value.

Gate: `pytest kaleem/billing`, `lint-imports`, coverage 100% on the module.

---

### Slice 2 — the duplicate-subscription invariant (R1)

5. **Widen `LIVE_STATUSES`** to `(ACTIVE, PAST_DUE, UNPAID, INCOMPLETE)`.
   Test first, and test *both* halves of the split invariant: an `unpaid` row blocks a
   second `create_checkout`, **and** an `unpaid` row is not entitled. The regression this
   guards is someone "simplifying" by reusing one status set for both questions.
6. **Migration 0004** widening `unique_live_subscription_per_user`'s condition to the same
   four statuses, spelled literally per the existing convention. Test: two live rows in each
   of the four statuses raise `IntegrityError`; `canceled` and `incomplete_expired` do not.
7. **`past_due` becomes entitled (R8).**
   Test: `past_due` is entitled, `unpaid` is not. Then: one branch in `_is_paid_through`.
   Ordering matters — this lands with slice 2 because slice 2 is what makes `unpaid` the
   revocation point.

---

### Slice 3 — self-serve recovery and plan change (R4, C1, A3)

8. **`POST /api/v1/billing/portal`** → `stripe.billing_portal.Session.create`, returns
   `{portal_url}`. Provider method `create_portal_session(customer_id, return_url,
   allowed_plans)`. Tests: no `BillingCustomer` → 404; provider error → mapped, not leaked;
   the allowed-plan set excludes Family for a user with no parent profile (spec R4).
9. **Plan re-pointing on `subscription.updated`.** Test: an `updated` event whose price no
   longer matches the stored plan re-points `Subscription.plan`; an unknown price raises an
   incident (slice 4) and leaves the plan alone. Then: resolve `SubscriptionPlan` by
   `stripe_price_id` in `_apply_to_existing`.
10. **Dashboard:** "Update payment method" / "Change plan" entry points on the billing page,
    a `past_due` state that leads with the recovery action rather than an error, en + ar.

---

### Slice 4 — billing incidents (R5, A2, D2)

11. **`BillingIncident` model** + migration (`kind`, `severity`, `user`, `stripe_object_id`,
    `event_id`, `detail` JSON, `resolved_at`, `resolved_by`).
12. **Raise incidents** everywhere that currently only logs about unresolvable state:
    `_log_duplicate_live_subscription`, `unknown_plan`, `unknown_user`,
    `unknown_subscription`, `unmapped_status`. Keep the log lines — the incident is the
    durable record, the log is still what pages someone.
13. **Admin:** read-only list + filters, one `resolve` action. No editing of mirrored fields
    (the existing `admin.py` convention).

---

### Slice 5 — reconciliation (R2, B1)

14. **`settle_checkout_session(session_id)` service** + `POST /api/v1/billing/checkout/
    {session_id}/settle`. Retrieves the session from Stripe and applies the same transition
    the webhook would, via the shared code path — the point is one state machine with two
    entry points, not two implementations. Test: settle before the webhook lands, then the
    webhook lands, and assert the second is a no-op.
15. **Dashboard poller** calls `settle` instead of blind-polling `/subscription`.
16. **Nightly `reconcile_subscriptions` Celery task.** Walks `stripe.Subscription.list` per
    `BillingCustomer`; diffs status / `current_period_end` / `cancel_at_period_end` / price;
    corrects drift; raises an incident per correction. Tests cover each drift direction
    including the two that cost money: Stripe canceled + ours `ACTIVE`, and Stripe active +
    ours missing entirely. This writer intentionally bypasses `_is_out_of_order` (spec R2).
17. **`detect_webhook_silence` task** → incident when `StripeEventLog` has been quiet past
    the threshold.
18. **Beat schedule entries** for 16 and 17.

---

### Slice 6 — idempotency and amount verification (R6, A4, D1)

19. **`idempotency_key` on every Stripe write**, keys per spec R6. Test via the fake
    provider that the key is stable across a retry of the same logical operation and differs
    across distinct ones.
20. **Verify charge matches plan** on `checkout.session.completed` and `invoice.paid`:
    price id vs `plan.stripe_price_id`, amount vs `display_amount`/`currency`. On mismatch,
    still mirror the subscription — the customer *was* charged — and raise an incident.

---

### Close-out

- `docs/runbook/stripe-billing.md`: incident queue, reconciler, what to do when the
  reconciler reports a double subscription (OQ-B2-3 is still manual).
- Stripe dashboard config that is *not* code and must be done by hand: portal
  subscription-update flow + allowed products, proration behaviour per OQ-B2-2, webhook
  endpoint subscribed to the three new `checkout.session.*` events. Record in the runbook.
- `/ship` (D9), `STATE.md`, journal entry, close the B1 spec if staging click-through is
  finally done.

### Risks

- **Slice 2 without slice 3 is a regression.** Called out above; enforced by shipping them
  in one PR if they are ready together, and by not merging slice 2 alone.
- **The reconciler is a writer with no ordering guard.** If it is wrong, it is wrong at
  scale and silently. Its tests are the most important ones in this plan.
- **Portal configuration is out-of-band state.** A misconfigured portal is invisible to CI.
  Hence the runbook entry, and a startup check is worth considering.
