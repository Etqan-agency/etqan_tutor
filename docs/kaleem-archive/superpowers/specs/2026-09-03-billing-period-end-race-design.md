---
name: billing-period-end-race
phase: B
modules: [billing]
status: approved
created: 2026-09-03
closed: null
---

## Goal

A newly-created subscription has no `current_period_end`, so the dashboard shows
"Active" with no renewal date until the nightly reconciler fills it in — up to ~24 hours
later. Fix the row so it is correct the moment it is created.

Found in the 2026-09-03 staging click-through, with timestamps:

```
04:18:43.553  invoice.paid                <- the ONLY event carrying the period end
04:18:43.561  unknown_subscription        <- no row yet, event DROPPED
04:18:43.633  checkout.session.completed  <- creates the row, carries no period end
04:18:46.281  settle:cs_test_...          <- idempotent, no duplicate
```

Stripe delivers `invoice.paid` and `checkout.session.completed` concurrently and in no
guaranteed order. When the invoice wins, `_apply_to_existing` finds no `Subscription`
row, records an `unknown_subscription` incident, and returns — discarding the authoritative
period end. A Checkout Session payload has neither `current_period_end` nor `items`, so the
row that `_apply_checkout_completed` then creates has `current_period_end = None`.

Reproducible, not a fluke: the `reconciled_drift` incidents for staging users 5 and 7 are
both this exact correction (`current_period_end: [None, ...]`).

**Why the existing tests missed it.** The backend suite is at 97% and `billing` is at 100%
line+branch. The race only exists between two *real, concurrently delivered* webhooks;
every test drives handlers one at a time in a chosen order.

## Decision

**When a checkout completion creates or updates a subscription row without a period end,
ask the provider for it.** By the time `checkout.session.completed` fires, the provider's
subscription already exists and already carries the period (verified against the live
staging subscription).

This is chosen over the alternatives because it is the only one that also fixes the case
where `invoice.paid` is never delivered at all — the failure mode B2's settle path exists
for.

## Alternatives considered

- **Let the invoice arm create the row.** The invoice payload does carry
  `parent.subscription_details.metadata` (`user_id`, `plan_id`), so it *could*. Rejected:
  it duplicates the eligibility, duplicate-live and charge-verification guards that
  `_apply_checkout_completed` owns, and puts subscription creation behind two different
  doors that must be kept in agreement forever.
- **Persist and replay dropped events once the row appears.** The general fix, and the
  right one if this class of drop recurs. Rejected as disproportionate today: it needs a
  queue table, replay ordering, and a retention policy to solve one known field.
- **Do nothing; the reconciler already corrects it.** Rejected: correct within 24 hours is
  not correct. The first thing a new subscriber sees is a plan with no renewal date, which
  reads as broken at exactly the moment they have just paid.

## Data model delta

None. `Subscription.current_period_end` already exists and is already nullable.

## API delta

None external. One new method on the `PaymentProvider` Protocol:

```python
def get_subscription(self, subscription_id: str) -> ProviderSubscription | None: ...
```

Returns `None` when the provider does not know the id. `StripeProvider` implements it with
the existing `_sdk_period_end` / `_sdk_price_id` readers, so the basil-vs-dahlia shape
fallback is shared rather than duplicated. `tests/fakes.py` gains the same method.

## Behaviour

In `_apply_checkout_completed`, after the row is written and only when
`current_period_end` is not already set:

1. Ask the provider for the subscription.
2. If it reports a period end, save it.
3. If the lookup fails or returns nothing, **leave the row as it is and carry on.** The
   webhook must still be acked: a provider outage here must not turn a successful
   subscription into a 5xx that Stripe retries for three days. The reconciler remains the
   backstop, exactly as today.

The extra call happens once per checkout, not per webhook, and is skipped entirely when a
concurrent `invoice.paid` already won the race and set the field.

## Frontend

None. `SubscriptionCard` already renders the renewal date when `current_period_end` is
present — it had nothing to render. Verified by the same staging click-through: the date
appeared as soon as the cancel path set the field.

## Module boundaries

Wholly inside `kaleem.billing`. No new cross-module calls, no new events. All provider
access stays behind the `PaymentProvider` seam — `stripe` is still imported only by
`StripeProvider` (D4).

## Out of scope

- The general dropped-event replay mechanism (see Alternatives).
- `invoice.paid` missing `keep_canceled=True` (`ISSUES.md`) — a separate defect in the
  same file, deliberately not bundled (D10).
- The webhook endpoint's API-version pin (`ISSUES.md`).

## Definition of done

- Failing test first (D3), covering: invoice-first ordering, checkout-first ordering, the
  provider returning nothing, and the provider raising.
- `billing` stays at 100% line+branch; repo floor 97 stays green (ADR-0026).
- Re-run the staging click-through and confirm the renewal date renders immediately.
