---
title: "System codes (vouchers)"
---

`etqan.vouchers` covers what TutorHamster calls "system codes". The office generates batches of
single-use codes. A student or parent (or the office on their behalf) redeems one to do one of
these:

- **activate** a new subscription;
- **renew** a subscription;
- take a **discount** off an invoice;
- for the registered `playlist` kind, get enrolled in a recorded course.

A code is never revenue in itself. Its sale counts as revenue only if the office records it as a
payment record. The app is named `vouchers` so it is not confused with permission codes.

## Concepts

| Model | What it is |
| --- | --- |
| `VoucherBatch` | The shared terms: `kind`, the target, `valid_days` (1–3650), `expires_on` (academy today + `valid_days` − 1, inclusive), `quantity` (1–500), `note`. Discount batches also hold `discount_kind` + `discount_value` + `currency`. The course, package and teacher links are PROTECT, so a deleted course can never widen a scoped code. |
| `Voucher` | One code: `code` (bare, unique), a copy of `kind`, `status` (`unused`/`used`/`void`), redemption stamps (`redeemed_at`/`redeemed_by`/`student`), plain ids `subscription_id`/`invoice_id`/`payment_id`/`target_ref_id`, void stamps and reason. **`expired` is derived** from the batch's `expires_on` and never stored. |

What each kind's batch names:

| Kind | Course | Package | Teacher | Target |
| --- | --- | --- | --- | --- |
| `activation` | required | required | required | none |
| `renewal` | required | required | none | none |
| `discount` | optional | optional | none | none |
| `playlist` | none | none | none | required (`target_id`) |

Discount values: `percent` takes 1–100 and no currency. `fixed` takes 1–100 000 000 minor units and
a currency.

Code text (`services/codes.py`):

- 10 characters of Crockford base 32 (no I, L, O or U), drawn with `secrets`. That is 50 bits.
- Displayed as `SYS-XXXXX-XXXXX`.
- Typed text is normalised: spaces and dashes dropped, upper-cased, a leading `SYS` stripped.

## How it works

- **Generate** (`services/batches.py:generate`): checks the kind's targets. An activation teacher
  must be active and one of the course's teachers. The batch's codes are inserted in bulk, and a
  collision is retried once.
- **Void** (`batches.py:void`): withdraws an unused code (expired ones too) for good. A used or
  void code is a 409.
- **Redeem** (`services/redeem.py:redeem`), one transaction:
  1. The code row is locked first. Nothing locks a code after a subscription, invoice or payment
     (F-15).
  2. A used or expired code is refused. Unknown and void codes give the same "invalid" answer.
  3. The kind's work runs:
     - **activation:** `scheduling.create_subscription` with the batch's course, package and
       teacher, starting today, with no lesson slots. Then `billing.settle_with_code`.
     - **renewal:** the chosen subscription must be the batch's course. It is renewed with the
       batch's package at scheduling's price, then `settle_with_code`.
     - `settle_with_code` issues the subscription's invoice, whatever `auto_invoice_on_subscription`
       says, and pays it in full with one `code` payment. With `invoices` off, or a price of 0,
       the code row is the only record.
     - **discount** (needs `invoices`):
       - The amount is a percent of the invoice amount, rounded half up with a minimum of 1, or
         the fixed value. A fixed discount must be in the invoice's currency.
       - The amount is capped at the balance (`billing.record_code_payment(up_to_balance=True)`).
       - A scoped code must match the invoice subscription's package and course.
       - An invoice can carry only one discount.
     - **registered kinds** (`services/registry.py`): the owning app's hooks do the work. Today
       `recorded` registers `playlist` (feature `recorded_courses`, office code
       `rc_enrolment.create`).
  4. The code is marked `used` with its ids.
- If a scheduling refusal means the code's own course, package or teacher is retired, the answer
  is "unavailable".
- **Family scope:** the student themself, or a parent of the student (`in_family`). A paying
  sibling may not redeem for the student.
- **Remove a discount** (`remove_discount`): the office removes a discount applied by mistake. It
  locks the code, then billing deletes the `code` payment (`delete_code_payment`). The code
  becomes `void` and keeps its history. Activation and renewal payments cannot be undone this way;
  billing refuses to refund or delete any `code` payment (`refuse_reserved_money`).
- **Revenue:** `code` payments are excluded from `billing.revenue_between`. Invoices paid in full
  by a code at issue are left out of the new-invoice notice.

## API

All routes are under `/api/v1/vouchers/` and need the `system_codes` feature.

| Method | Path | Who | Purpose |
| --- | --- | --- | --- |
| GET, POST | `/api/v1/vouchers/batches/` | `voucher.view_any`/`voucher.create` | List batches; generate a batch |
| GET | `/api/v1/vouchers/codes/` | `voucher.view_any` | Codes with filters (state includes derived `expired`), `?format=csv` |
| POST | `/api/v1/vouchers/codes/<id>/void/` | `voucher.update` | Void an unused code |
| POST | `/api/v1/vouchers/codes/<id>/redeem/` | `voucher.update` + the kind's codes, not quick-login | Office redeems a listed code for a student, subscription or invoice |
| POST | `/api/v1/vouchers/codes/redeem/` | as above | Office redeems by typed code |
| POST | `/api/v1/vouchers/codes/<id>/remove-discount/` | `voucher.update`, not quick-login | Remove a used discount (reason required) |
| POST | `/api/v1/vouchers/check/` | student, parent (throttled) | Preview a code: kind, terms, eligible students or subscriptions |
| POST | `/api/v1/vouchers/redeem/` | student, parent, not quick-login (throttled) | Redeem |

The kind's extra office codes (`api/views.py:KIND_CODES`):

| Kind | Also needs |
| --- | --- |
| activation | `subscription.create` |
| renewal | `subscription.update` |
| discount | `payment.create` + `invoice.view` |
| registered kind | its `office_code` |

The family routes are throttled per user (`voucher_redeem`, 20/hour) and per IP
(`voucher_redeem_ip`, 60/hour). Both keys include the academy's schema.

## Dashboard

- **Office:** `routes/_authed/billing.codes.tsx` shows `CodesPage`, which includes
  `GenerateCodesDialog`, `CodeActions`, `VoidCodeDialog` and `OfficeRedeemDialog`.
- **Family:** `routes/_authed/learning.codes.tsx` shows `RedeemCodePage`.
- **Invoice pages:**
  - `ApplyCode` on the office and family invoice pages;
  - `RemoveDiscount` on each payment row of the office invoice page.

  Billing never imports these; the routes pass them in.
- Feature folder: `dashboard/src/features/vouchers/`.
- `settings.registration-codes` is a different feature (registration), not system codes.

## Background jobs

None. Expiry is derived from `expires_on` whenever a code is read.

## Configuration

- **Feature:** `system_codes` (built, off by default, requires nothing).
  - Discount codes also check `invoices`.
  - `playlist` codes check `recorded_courses`.
- **Settings:** throttle rates `voucher_redeem` and `voucher_redeem_ip` in `config/settings/base.py`.

## Code map

- `backend/etqan/vouchers/models.py`, `throttling.py`
- `backend/etqan/vouchers/services/`: `batches.py`, `codes.py`, `redeem.py`, `reads.py`,
  `registry.py`, `errors.py`
- `backend/etqan/vouchers/api/`
- Billing side: `billing/services/subscriptions.py:settle_with_code`,
  `billing/services/payments.py:record_code_payment`, `delete_code_payment`
- `backend/etqan/recorded/services/codes.py` (the `playlist` redeemer)
- `dashboard/src/features/vouchers/`

## Design history

- [B3 phase design](../superpowers/specs/2026-10-03-b3-money-depth-design.md): the B3f slice
  outline.
- [B3f system codes](../superpowers/specs/2026-10-07-b3f-system-codes-design.md): kinds, code
  format, redemption, discount valuation (an `[assumed]` decision), removal.
- [B7g recorded certificates and codes](../superpowers/specs/2026-10-08-b7g-recorded-certificates-codes-design.md):
  adds the registered `playlist` kind (ledger D56).
- Plans: [Plan 45 system codes](../superpowers/plans/2026-10-07-plan-45-system-codes.md),
  [Plan 59 recorded certificates and codes](../superpowers/plans/2026-10-08-plan-59-recorded-certificates-codes.md).
