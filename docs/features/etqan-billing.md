---
title: "Etqan billing"
---

This page covers how Etqan bills academies for using its default accounts (email, WhatsApp, video meetings,
AI). It is separate from an academy billing its own students, which lives in `etqan.billing`.

`etqan.etqan_billing` records each confirmed use of an Etqan default and prices it per academy. Each month it
builds an invoice per academy and emails a PDF to the academy's admins. Academies pay by hand (bank transfer or
any other method). Etqan staff then mark the invoice paid in the platform admin. Academy admins see this
month's usage and past invoices in Settings → Etqan billing. When an invoice is overdue, every page shows them
a banner.

## Concepts

Everything lives in the **public schema** (SHARED_APPS). There is one ledger, and every row is keyed by
`academy`.

| Model | Purpose |
|---|---|
| `UsageEvent` | One provider-confirmed use: `academy`, `service`, `unit`, `quantity`, `occurred_at` (UTC), `source_ref`. Unique on `(academy, service, unit, source_ref)`. |
| `Price` | Etqan's price for a `(service, unit)`, in minor units per `PER[unit]` units, from `effective_from` (a UTC date) until the next price |
| `AcademyPricing` | Per-academy override `amount` and/or monthly `free_allowance` for a `(service, unit)` |
| `ConnectFee` | Per-academy Stripe Connect platform fee: `percent_bp` (basis points), `fixed_amount`, `currency` |
| `CollectedFee` | A Connect fee Stripe already collected (`application_fee.created`). Unique on `(academy, source_ref)`. |
| `EtqanInvoice` | One invoice per academy per UTC month: `number` `ETQ-YYYY-MM-NNNN`, `status` `draft → issued → paid` or `void`, `total` (minor units), `draft_until`, `issued_at`, `due_at`, `emailed_at`, paid fields, void fields. At most one non-void invoice per `(academy, period)`. |
| `EtqanInvoiceLine` | `kind` `usage` / `connect_fees` / `manual` / `credit`; signed `amount` (a credit is negative) |
| `InvoiceSequence` | Per-month counter for invoice numbers |

Metered units (`services/usage.py:UNITS`) and the batch size each price is quoted per (`pricing.PER`):

| Service | Unit | Price per | Recorded by |
|---|---|---|---|
| email | `email` | 1,000 | `integrations.services.email.meter_email`, keyed by Message-ID |
| whatsapp | `conversation` | 1 | `integrations.services.whatsapp.meter_whatsapp`, keyed by wamid |
| video | `minute` | 1 | `integrations.services.video._meeting_ended`, keyed by `<meeting instance uuid>:minute` |
| ai | `input_token`, `output_token` | 1,000,000 | `etqan.ai.services.meter`, keyed by `ai-draft-<uuid>:<unit>` |

Payments are not metered. Connect fees go into `CollectedFee` instead.

## How it works

### Metering: `services/usage.py:record_usage`

`record_usage(source=, service=, unit=, quantity=, source_ref=, occurred_at=None)` works as follows:

- It raises `ValueError` when the unit does not belong to the service, the quantity is not a positive integer,
  `source_ref` is empty or longer than 255 characters, or `occurred_at` is naive.
- It records nothing and returns `None` when `source != "etqan"` or the connection is in the public schema.
  Use of an academy's own account is never charged.
- It uses `get_or_create` on `(academy, service, unit, source_ref)`. A repeated webhook or retry returns the
  first event unchanged, so each `source_ref` is counted once per unit.
- One provider event that yields several units records each unit under its own row. AI uses one ref per unit
  as well.
- Callers do not send the provider event to `record_usage` until the provider has confirmed it. A metering
  failure after a successful send is logged and never raised, because a delivered message cannot be undone.

`record_collected_fee(amount=, currency=, source_ref=, occurred_at=)` is idempotent on the Stripe fee id. It is
called from `gateways/services/connect_webhooks.py`, and only for events in the platform key's mode.

### Pricing: `services/pricing.py`

- `usage_lines(academy_id, period)` groups the month's daily usage by `(service, unit)`. The price for each day
  is the academy's override, or else the latest `Price` effective that day (0 if there is none).
- The free allowance is used up once per month, in date order.
- The month produces one line for each distinct unit price in effect during it.
- `charge(billable, unit_amount, per)` rounds half up to a whole minor unit.
- `current_prices(service)` gives today's price and allowance for the current academy. It feeds the
  Integrations cards (`default_prices`).
- `connect_fee()` gives the current academy's `ConnectFeeTerms`, or `None`. `etqan.gateways` uses it to
  compute `application_fee`.
- Everything is billed in one currency, `ETQAN_BILLING_CURRENCY`.

### Invoices: `services/invoices.py`

- `build_month(period=None)` runs on the 1st for the previous UTC month. It loops over every academy,
  suspended ones included, with one transaction per academy. An academy that fails is logged and the loop
  continues. Results are `built`, `none`, `exists` or `failed`.
- `create_draft(academy, period)` adds usage lines and `connect_fees` lines (one per currency). It runs only if
  the month had activity (`has_activity`). It also raises `already_invoiced` if a non-void invoice exists.
- `connect_fees` lines are shown but excluded from `total`, because those fees were already paid through
  Stripe.
- A draft can be edited for `DRAFT_HOURS = 24`. During that time:
  - `add_line` / `check_line` add `manual` or `credit` lines only, and the total must stay at or above 0;
  - `remove_line` cannot remove usage lines.

  After 24 hours, `issue_due` issues the draft. Etqan staff can also issue earlier.
- `issue` freezes the invoice and sets `due_at = issued_at + 15 days`. An issued invoice never changes again.
  Corrections become credit lines on the next invoice.
- `mark_paid(paid_on, method, reference)` applies to issued invoices only. `paid_on` cannot be in the future.
  Methods are `bank_transfer`, `cash`, `card`, `other`.
- `void(reason)` applies to a draft or an issued invoice, and frees the month for a new draft. A paid invoice
  cannot be voided.
- `is_overdue`: the invoice is issued, its total is above 0, and `now >= due_at` (15 days).
- `may_suspend`: the oldest unpaid issued invoice is at least 30 days old. Suspension is never automatic. Etqan
  staff tick `Academy.etqan_defaults_suspended` in the tenants admin, which refuses it before 30 days. After
  that, `integrations.resolve` skips Etqan's defaults for the academy. Its own accounts keep working.
- The academy sees only issued invoices (`academy_invoices`, `academy_invoice`). Drafts belong to Etqan.

## API

Academy hosts, admins only (`HasCode` with no codes).

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/etqan-billing/usage/` | admin | This UTC month: `{month, currency, usage: [{service, unit, quantity, free, amount, days[]}]}` |
| GET | `/api/v1/etqan-billing/invoices/` | admin | Issued invoices, newest first, each with `overdue` |
| GET | `/api/v1/etqan-billing/invoices/<id>/pdf/` | admin | The invoice PDF (`ETQ-….pdf`) |

There are no webhooks of its own. Usage reaches this app through the integrations endpoints on the base domain
(`/api/v1/webhooks/zoom/`, `/api/v1/webhooks/stripe-connect/`), described in
[integrations.md](integrations.md).

## Dashboard

- Route `dashboard/src/routes/_authed/settings.etqan-billing.tsx` (`/app/settings/etqan-billing`), permission
  `ADMINS_ONLY`.
- Feature `dashboard/src/features/etqanbilling/`: `EtqanBillingPage` (usage and invoices), and `OverdueBanner`,
  which `features/shell/AppShell.tsx` mounts on every page for admins whenever any invoice is `overdue`.

## Background jobs

Beat schedule in `backend/config/settings/base.py`:

| Task | Schedule | Does |
|---|---|---|
| `etqan_billing.build_month` | 1st of the month, 03:00 UTC | `services.build_month()`: drafts for the previous month, looping over academies itself |
| `etqan_billing.issue_due` | hourly at :10 | Issues drafts past `draft_until`, then queues `send_invoice` for each. It also re-queues issued invoices that have no `emailed_at` and were issued over an hour ago. |
| `etqan_billing.send_invoice` | on demand | Emails the PDF to the academy's active admins. It reads the admins in `academy_context` and sends from the public schema on Etqan's own email, which is never metered. It retries on SMTP errors after 1, 2 and 4 minutes, then sets `emailed_at`. |

## Configuration

- `ETQAN_BILLING_CURRENCY` (default `USD`).
- `ETQAN_BILLING_PAYMENT_INSTRUCTIONS`: printed on every invoice PDF and email that has something to pay.
- Platform admin (`etqan_billing/admin.py`):
  - prices, academy pricing and Connect fees are editable;
  - `UsageEvent` and `CollectedFee` are read-only;
  - invoices have actions to issue, email again, mark paid and void, and inline manual or credit lines on
    drafts. Each action needs the invoice change permission: a staff member who may only view sees none,
    and a forged action POST is refused (ETQAN-QA-013).
- The suspend switch is in the tenants admin (`Academy.etqan_defaults_suspended`).
- The PDF is rendered by `etqan_billing/pdf.py` (fpdf2 with bundled DejaVu fonts, for Arabic shaping).

## Code map

- `backend/etqan/etqan_billing/models.py`
- `backend/etqan/etqan_billing/services/`: `usage.py`, `pricing.py`, `invoices.py`, and `__init__.py` (the
  public API)
- `backend/etqan/etqan_billing/tasks.py`, `pdf.py`, `admin.py`, `api/`
- `backend/etqan/tenants/admin.py` (suspend switch)
- `dashboard/src/features/etqanbilling/`

## Design history

- [Integrations & Etqan billing design](../superpowers/specs/2026-10-07-integrations-and-etqan-billing-design.md)
  §5–§6: the base spec. The spec differs from the code in three places:
  - it puts the Connect fee on `AcademyPricing`, but the code has a separate `ConnectFee` model;
  - it says `UsageEvent` is unique per (academy, service, `source_ref`), but the code includes `unit`
    (migration `0002_usage_counted_once_per_unit`);
  - it says WhatsApp is metered on the delivery webhook, but the code meters on acceptance.
- [Plan: integrations 2, billing](../superpowers/plans/2026-10-08-plan-integrations-2-billing.md): metering,
  prices, the monthly job, screens, admin.
- [Plan: integrations 3, Zoom and Connect](../superpowers/plans/2026-10-09-plan-integrations-3-zoom-connect.md):
  video minutes and collected Connect fees.
- [B10 AI design](../superpowers/specs/2026-10-08-b10-ai-design.md) AI-9: AI token metering. Its note that
  `record_usage` ignores the unit is out of date.
