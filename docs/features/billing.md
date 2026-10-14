# Billing: invoices and payments

`etqan.billing` holds an academy's invoices to families and every payment the academy receives:
by hand at the office, online through a provider, from a student's wallet, or by a system code.
Admins and staff with the right permission codes issue invoices and record payments. Parents and
students see the invoices they pay or are billed for. Teachers see none. This page also covers
standalone payment records, local payment methods and subscription payment terms. Online checkout
is in [online-payments.md](online-payments.md), the wallet in [wallet.md](wallet.md) and codes in
[vouchers.md](vouchers.md).

## Money representation

- Every amount is an integer of **minor units** (`*_minor`, `BigIntegerField`) plus a 3-letter
  ISO 4217 `currency` (`^[A-Z]{3}$`). `12345` with `USD` means 123.45 USD.
- Minor digits per currency are in `etqan/platform/currency.py` (`MINOR_DIGITS`). The default is 2.
  Some currencies use 0 (JPY, KRW, CLP …) and some use 3 (BHD, IQD, JOD, KWD, LYD, OMR, TND).
  `to_decimal_string` and `from_decimal_string` convert for providers that use decimals (PayPal).
- Amounts are **never summed across currencies**. Every total is a list of
  `{currency, amount_minor}`. The only cross-currency figure is finance's labelled estimate
  ([finance.md](finance.md)).
- Dates such as `issued_on`, `due_on` and `paid_on` are on the academy's calendar
  (`billing/clock.py:today`, from `AcademySettings.timezone`). Timestamps are stored in UTC.
- On the dashboard, `src/lib/money.ts` (`toMinor`, `toMajor`, `formatMoney`) converts what a
  user types to and from minor units. The dashboard (`src/lib/money.ts`) and the marketing site
  (`src/lib/money.ts`) each keep a copy of `MINOR_DIGITS`. They never ask the browser's `Intl`,
  which disagrees for 17 codes (IQD, IDR, PKR, LBP, SYP, YER…). **Change all three together.**

## Concepts

| Model | What it is |
| --- | --- |
| `Invoice` | Number `INV-000123`, payer (a user), student (`StudentProfile`), optional plain `subscription_id`, `amount_minor` > 0, currency, `issued_on` ≤ `due_on`, status `unpaid`/`partial`/`paid`/`void`. |
| `InvoiceCounter` | One row (pk 1) per academy. It is locked `FOR UPDATE` while a number is taken, so numbers are gap-free per transaction. |
| `Payment` | `invoice` is nullable: a payment with no invoice is a *standalone record*. Fields: `currency`, `amount_minor`, `fee_minor`, `method`, `paid_on`, `transaction_number`, `status` (`completed`/`refunded`/`credited`), `customer_type` (`student`/`unregistered`) with customer name, email and phone, and `wallet_topup`. |
| `SubscriptionTerms` | SUB-006 metadata per subscription id: `payment_type` (prepaid/postpaid) and `system` (normal/monthly). It is stored and shown only. Nothing reads it. |
| `BillingSettings` | One row. `local_payment_enabled` turns on the local methods shown to families. |
| `LocalPaymentCountry` / `LocalPaymentMethod` | Manual ways to pay, per country: name, optional currency, logo, plain-text instructions and position. A country with no row counts as enabled. |

Payment methods: the manual ones (`cash`, `bank_transfer`, `instapay`, `vodafone_cash`,
`western_union`, `zelle`, `venmo`, `cashapp`, `other`) and the reserved ones, which no one can
enter by hand: `stripe`, `paypal` (only a provider event records them), `wallet` (only
`etqan.wallet`) and `code` (only `etqan.vouchers`). Database constraints enforce these rules:

- `wallet` and `code` payments sit on an invoice and have no fee.
- A top-up is a student's standalone record.
- `(method, transaction_number)` is unique.

## How it works

- **Status.** `services/rules.py:status_for` is the only status function. It counts the
  `completed` payments: nothing paid is `unpaid`, part paid is `partial`, all paid is `paid`.
  Only `void_invoice` sets `void`, and only when the invoice has no payments.
  - `overdue` is derived, never stored: `rules.overdue(today)` means open and due before today.
  - Every write locks the invoice row first (`rules.lock`) and then recalculates its status
    (`payments._recalculate`).
- **Manual invoice.** `services/invoices.py:create_invoice` checks the student is active and
  resolves the payer (`services/payers.py:resolve_payer`). The default payer is the first of:
  - the family payer (when `families` is on);
  - the active guardians (when `parents` is on);
  - the student.

  The currency is the subscription's if one is given, else the one in the request, else the
  academy's `default_currency`. A refused invoice never takes a number.
- **Edit and void.** `update_invoice` refuses any change on a void invoice. The amount can only
  change while nothing is paid. `void_invoice` is permanent.
- **Subscriptions produce charges.** Scheduling's create, renew and bundle views call
  `services/subscriptions.py:invoice_subscription` in the same transaction as the subscription.
  - If the invoice fails, the subscription rolls back too.
  - An invoice is issued only when the `invoices` feature is on,
    `AcademySettings.auto_invoice_on_subscription` is true and the price is not 0.
  - The invoice uses the subscription's `price_minor` and currency and is due after
    `AcademySettings.invoice_due_days`. Its description is "course — package" in the academy's
    language.
  - The price itself comes from scheduling and catalogue (`catalogue.services.package_price`,
    which applies per-country prices when `country_pricing` is on).
  - A subscription with a non-void invoice cannot be deleted
    (`refuse_if_invoiced`, 409 `billing.subscription_invoiced`).
  - `payment_statuses(ids)` gives scheduling each subscription's paid/partial/unpaid/overdue state
    in one query.
- **Manual payment.** `services/payments.py:add_payment` takes a payment in the invoice's
  currency. It refuses reserved methods, a payment dated in the future, and any amount above the
  remaining balance (`rules.refuse_if_over_balance`).
- **Refund.** `refund_payment` marks the payment `refunded`. It is recorded only: no provider
  API is called. A refunded payment stops counting. Wallet, top-up, code and credited payments
  are refused (`refuse_reserved_money`). `delete_payment` exists for mistakes.
- **Online payments.** Billing registers the gateway purpose `invoice` (`services/online.py`):
  - `prepare` prices the balance with the service fee.
  - `complete` calls `record_online_payment`, which writes a `stripe`/`paypal` payment with
    `fee_minor` and the provider's transaction number.
  - A void invoice, a balance that is now too low, or a duplicate transaction comes back as an
    "attention" reason, never as an error.
  - `pay_options(invoice)` lists the providers that can take the balance.
- **Standalone records** (`services/records.py`):
  - The office creates and edits payments with no invoice (`create_record`, `update_record`),
    for a student or an unregistered customer, by manual methods only.
  - Payment-link money arrives through the `payment_link` purpose
    (`services/link_purpose.py` → `record_link_payment`).
- **Revenue.** `services/summary.py:revenue_between` sums `amount_minor + fee_minor` per currency
  for payments with status `completed` or `credited`. It leaves out `wallet` and `code` methods:
  that money counted when the wallet was topped up or the code was sold.
  `summary()` returns this month's revenue and overdue counts and balances, per currency.
- **Local methods** (`services/local.py:local_methods_for`): an invoice shows the active methods
  of its student's `country` only when all of these hold:
  - `local_payment_enabled` is on;
  - the country is enabled;
  - something is due on the invoice;
  - the method's currency is blank or the invoice's.

  The family still pays outside the system, and the office records the payment by hand.
- **Visibility** (`scopes.py:scope_for`): office users see everything. A student sees invoices
  where they are the student or the payer. A parent sees what they pay plus their children's
  invoices. Anything else is out of scope and answers 404.

## API

All paths are under `/api/v1/billing/`. "Office" means admins, plus staff who hold the listed
code. Every route also needs the feature named.

| Method | Path | Who | Purpose |
| --- | --- | --- | --- |
| GET, POST | `/api/v1/billing/invoices/` | office `invoice.view_any`/`invoice.create`; family read-only (scoped) | List (filters, `?format=csv`) and create (`invoices`) |
| GET, PATCH | `/api/v1/billing/invoices/<id>/` | office `invoice.view`/`invoice.update`; family read | Detail (`can_pay_online`, `local_methods`), edit |
| POST | `/api/v1/billing/invoices/<id>/void/` | `invoice.update` | Void |
| GET, POST | `/api/v1/billing/invoices/<id>/payments/` | `payment.view_any`/`payment.create`; family read | Invoice payments; add a manual payment |
| GET, POST | `/api/v1/billing/payments/` | `payment.view_any`/`payment.create` | Every payment record, CSV; create a standalone record (`payment_receipts`) |
| GET, PATCH, DELETE | `/api/v1/billing/payments/<id>/` | `payment.view_any`/`.update`/`.delete` | Record detail and edit (`payment_receipts`); delete (`invoices`) |
| POST | `/api/v1/billing/payments/<id>/refund/` | `payment.update` | Mark refunded |
| GET | `/api/v1/billing/summary/` | `widget.revenue_stats` | Revenue this month, overdue |
| GET | `/api/v1/billing/payers/` | `invoice.create` | Payer options for a student |
| GET, PATCH | `/api/v1/billing/subscriptions/<id>/terms/` | `subscription.view`/`.update` | SUB-006 terms (no feature gate) |
| GET, PATCH | `/api/v1/billing/settings/` | `payment_method.view_any`/`.update` | `local_payment_enabled` |
| GET, POST | `/api/v1/billing/local-methods/` | `payment_method.view_any`/`.create` | List and create local methods (multipart, logo) |
| PATCH, DELETE | `/api/v1/billing/local-methods/<id>/` | `payment_method.update`/`.delete` | Edit and delete |
| PUT | `/api/v1/billing/local-countries/<CC>/` | `payment_method.update` | Enable or disable a country |

## Dashboard

- **Office** (`routes/_authed/billing*.tsx`, guarded by `requireOffice`):
  - `billing/` redirects to the first billing page the user may open
    (`features/finance/landing.ts:billingLanding`).
  - `billing/invoices/` and `billing/invoices/new` list and create invoices.
  - `billing/invoices/$invoiceId` shows an invoice. It also mounts the wallet and voucher actions,
    passed in by the route because billing never imports them.
  - `billing/payments` lists payment records and `billing/local-methods` holds the local methods.
- **Family:** `learning/invoices/` and `learning/invoices/$invoiceId` (with PayOnline,
  PayFromWallet and ApplyCode).
- **Print:** `_print/invoices.$invoiceId.print.tsx`.
- **Elsewhere:**
  - `BillingSummaryCard` on the home page (`routes/_authed/index.tsx`);
  - `SubscriptionInvoices` and `SubscriptionTermsCard` on the subscription page;
  - `LocalPayment` (settings card) on `settings/gateways`.
- **Feature folder:** `dashboard/src/features/billing/`.

## Background jobs

Billing has no Celery task of its own. `notifications.scan` (every minute) reads
`services/notices.py:invoices_issued` and `invoices_overdue` to send new-invoice and overdue
notices. An invoice paid in full by a code at issue is left out. "Overdue" is computed when it is
read.

## Configuration

- **Features:**
  - `invoices` (core);
  - `payment_receipts` (records list, standalone records; requires `invoices`, off by default);
  - `country_pricing` (catalogue);
  - `export` (CSV).
- **Academy settings:** `default_currency`, `auto_invoice_on_subscription` (default true),
  `invoice_due_days`, `default_language`, `timezone`.
- **Billing settings:** `local_payment_enabled`.

## Code map

- `backend/etqan/billing/models.py`, `scopes.py`, `clock.py`
- `backend/etqan/billing/services/`: `invoices.py`, `payments.py`, `rules.py`,
  `subscriptions.py`, `records.py`, `online.py`, `link_purpose.py`, `local.py`, `payers.py`,
  `terms.py`, `summary.py`, `notices.py`, `numbering.py`
- `backend/etqan/billing/api/` (`views.py`, `payloads.py`, `serializers.py`, `urls.py`)
- `backend/etqan/platform/currency.py` (minor digits), `backend/etqan/platform/validators.py` (`clean_currency`)
- Callers: `backend/etqan/scheduling/api/views.py`, `scheduling/api/bundle_views.py`
- `dashboard/src/features/billing/`, `dashboard/src/lib/money.ts`, `dashboard/src/lib/currencies.ts`

## Design history

- [Plan 6 billing spec](../superpowers/specs/2026-09-25-billing-design.md): invoices and manual
  payments. Its "online payments and refunds later" non-goals were overtaken by B3.
- [B3 phase design](../superpowers/specs/2026-10-03-b3-money-depth-design.md): money rules
  B3-1…B3-11 and the slice map.
- [B3b online payments](../superpowers/specs/2026-10-03-b3b-online-payments-design.md): payment
  status, fee, transaction number, refunds marked.
- [B3g links and records](../superpowers/specs/2026-10-03-b3g-links-records-design.md):
  standalone records, currency on every payment, SUB-006 terms.
- [B3d countries and local methods](../superpowers/specs/2026-10-05-b3d-countries-currencies-design.md):
  country prices and local methods.
- [B3e wallet](../superpowers/specs/2026-10-06-b3e-student-wallet-design.md) and
  [B3f system codes](../superpowers/specs/2026-10-07-b3f-system-codes-design.md): the
  `wallet`/`code` methods and `credited` status.
- Plans: [Plan 6](../superpowers/plans/2026-09-25-plan-6-billing.md),
  [Plan 26 links and records](../superpowers/plans/2026-10-03-plan-26-links-records.md),
  [Plan 36 country prices](../superpowers/plans/2026-10-05-plan-36-country-prices.md).
