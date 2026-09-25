# Plan 6 — Billing (Invoices & Manual Payments) — Design

**Date:** 2026-09-25
**Status:** Approved in brainstorming (sections 1–3), pending written-spec review.
**Phase:** B0, milestone 6 of the parity roadmap (`2026-09-24-parity-roadmap-design.md`).
**Builds on:**
- v1 spec §4.7 and §5.4 (`2026-09-23-etqan-tutor-v1-design.md`);
- Plan 4 (subscriptions, renew; `2026-09-24-subscriptions-scheduling-design.md`);
- Plan 3 (people, guardianship, role permissions, CSV);
- the academy-sites spec (site branding: logo and names).

**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §2.5 (BILL-001 payment records, BILL-003 invoices) and `docs/PHASE_1_SYSTEM_AUDIT.md` (BILL-003: auto-numbered invoices). Roadmap rule R4 applies.

## 1. Goal

Admins bill families and record what they pay:
- An invoice is created automatically when a subscription is created or renewed. Admins can also issue invoices by hand.
- Payments are recorded against an invoice, and its status follows from them.
- The admin home shows this month's revenue per currency and the overdue invoices.

Parents and students see their own invoices and can print an academy-branded invoice or receipt.

## 2. Decisions

| # | Decision |
|---|---|
| P6-1 | A new tenant app, `etqan.billing`, owns `Invoice`, `Payment` and invoice numbering. It reads subscriptions only through `etqan.scheduling`'s services. Scheduling's services never import billing. The subscription create and renew API views call billing after scheduling, inside the same request transaction. |
| P6-2 | **Manual payments only.** Online gateways, payment links, the 5% service fee, wallets, discount codes and expenses are phase B3. |
| P6-3 | Payment methods follow TutorHamster's manual options: `cash · bank_transfer · instapay · vodafone_cash · western_union · zelle · venmo · cashapp · other`. |
| P6-4 | The payer is a person, either a parent or the student. It defaults to the student's first guardian (the earliest-created guardianship), else the student. Family accounts with a named payer are phase B1. |
| P6-5 | **Printable invoice.** Each invoice has a clean, academy-branded page that anyone who can see the invoice can print or save as PDF from the browser. |
| P6-6 | Money is integer minor units plus an ISO 4217 currency. A payment's currency is its invoice's currency. Totals are never summed across currencies. |

## 3. Data

### 3.1 AcademySettings (existing)

New fields:
- `auto_invoice_on_subscription`, bool, default `true`;
- `invoice_due_days`, 0–90, default 7.

### 3.2 Invoice (new, `etqan.billing`)

| Field | Notes |
|---|---|
| `number` | `INV-000123`: unique per academy, handed out in sequence from a locked counter row, so concurrent invoices never share or skip a number |
| `payer` | → User (a parent or the student) |
| `student` | → `StudentProfile` |
| `subscription_id` | nullable reference to a `scheduling.Subscription` (a plain id, validated through scheduling's services) |
| `description` | text |
| `amount_minor` | > 0 |
| `currency` | ISO 4217 |
| `issued_on`, `due_on` | dates in the academy's calendar; `due_on` ≥ `issued_on` |
| `status` | `unpaid · partial · paid · void` |
| `notes` | text, admin-only |
| `created_by`, `voided_by`, `voided_at` | audit |
| `created_at`, `updated_at` | |

### 3.3 Payment (new)

| Field | Notes |
|---|---|
| `invoice` | → Invoice |
| `amount_minor` | > 0 |
| `method` | P6-3 values |
| `paid_on` | date |
| `reference` | text, optional (transfer or receipt number) |
| `notes` | text, optional |
| `recorded_by` | → User |
| `created_at` | |

## 4. Behaviour

### 4.1 Status and balance

- **Paid and balance:** `paid_minor` is the sum of the invoice's payments, and `balance_minor` = `amount_minor` − `paid_minor`.
- **Status:** it is recalculated after every payment is added or deleted, inside the same transaction, with the invoice row locked:
  - nothing paid → `unpaid`;
  - part paid → `partial`;
  - the full amount paid → `paid`.
- **Overpayment is refused.** A payment greater than the balance returns 400 on `amount_minor`.
- **Overdue** is derived and never stored: status `unpaid` or `partial`, and `due_on` < the academy's today.

### 4.2 Void and edit

- **Void:**
  - allowed only when the invoice has no payments (409 `billing.has_payments`);
  - a void invoice accepts no payments (409 `billing.invoice_void`);
  - voiding cannot be undone.
- **Editing:**
  - description, `due_on` and notes are always editable, except on a void invoice;
  - `amount_minor` is editable only while there are no payments;
  - editing a void invoice returns 409 `billing.invoice_void`.
- **Deleting a payment:** admin-only, for mistakes. The status is recalculated.

### 4.3 Automatic invoices

When `auto_invoice_on_subscription` is on, creating or renewing a subscription creates one invoice:
- the amount is the subscription's `price_minor` and `currency`;
- the student is the subscription's, and the payer follows P6-4;
- it is issued today (academy calendar) and due today plus `invoice_due_days`;
- the description is "{course name} — {package name}" in the academy's default language.

It is not created when the price is 0 or the switch is off. It is created in the same transaction as the subscription, so a failure rolls both back.

Cancelling or deleting a subscription never touches its invoices. The admin voids them if needed. Deleting a subscription is refused while it has a non-void invoice (409 `billing.subscription_invoiced`), so no invoice is left pointing at nothing. Admins void the invoice first.

### 4.4 Subscription payment status

This is derived from the subscription's non-void invoices, for admins only:
- `none`: no invoice;
- `paid`: all invoices are paid;
- `partial`: some payment exists but not everything is paid;
- `unpaid`: no payment at all.

An `overdue` flag is set when any of its invoices is overdue.

### 4.5 Revenue and overdue summary

- **Revenue this month:** the payments whose `paid_on` falls in the academy's current calendar month, summed per currency.
- **Overdue:** the count and the balance per currency of overdue invoices.

### 4.6 Access

| | Admin | Parent | Student | Teacher |
|---|---|---|---|---|
| Invoices and payments: read | all | invoices they pay or whose student is their child | their own (as student or payer) | none |
| Create, edit, void; record or delete payments; summary; CSV | ✓ | | | |
| Print page | any | the invoices they can read | the invoices they can read | |

- One permission class per role plus `scope_for`, as before. Out-of-scope objects return 404.
- `notes` and `created_by` are admin-only in payloads, and so are a payment's `notes` and `recorded_by`.

## 5. API (`/api/v1/billing/`, existing conventions)

| Route | Methods | Notes |
|---|---|---|
| `invoices/` | GET, POST | Filters: `status` (`unpaid·partial·paid·void·overdue`), `student`, `payer`, `subscription`, `issued_from`, `issued_to`, `q` (number or name). Paginated, newest first. `?format=csv` is admin-only. POST takes `{student, payer?, subscription?, amount_minor, currency?, due_on, description, notes?}`; `issued_on` is today. |
| `invoices/<id>/` | GET, PATCH | PATCH: `description`, `due_on`, `notes`, `amount_minor` (rules in §4.2). The response includes the payments. |
| `invoices/<id>/void/` | POST | |
| `invoices/<id>/payments/` | GET, POST | POST `{amount_minor, method, paid_on, reference?, notes?}`. |
| `payments/<id>/` | DELETE | |
| `summary/` | GET | `{revenue_this_month: [{currency, amount_minor}], overdue: [{currency, count, balance_minor}]}`. |

- **Subscriptions:** Plan 4's subscription list and detail payloads gain `payment_status` and `payment_overdue` for admins.
- **Settings:** `academy/settings/` gains the two settings.
- **Errors:**
  - 409 bodies are `{detail, code}`, with codes `billing.has_payments`, `billing.invoice_void` and `billing.subscription_invoiced`;
  - field problems return 400;
  - the payer must be the student or one of the student's guardians (400 on `payer`);
  - a subscription must belong to the student (400 on `subscription`).

## 6. Dashboard (`/app/`)

**Admin** (a new "Billing" nav group):
- **Invoices:**
  - status tabs (all, unpaid, partial, paid, overdue, void);
  - filters for student and date range, search, the shared Pager and CSV export;
  - columns: number, student, payer, amount, paid, balance, due date, and status with an overdue badge.
- **New invoice:**
  - student, then payer (defaults per P6-4, with the student's guardians and the student as choices);
  - an optional subscription of that student, which pre-fills the amount, currency and description;
  - then the due date (default today + `invoice_due_days`) and notes.
- **Invoice page:**
  - details and an edit dialog;
  - "Record payment" (amount defaulting to the balance, method, date defaulting to today, reference);
  - the payments list with delete, "Void invoice", and "Print".
- **Subscriptions:** the list gains a payment-status column, and the detail page gains an "Invoices" panel.
- **Home:** a "Revenue this month" card per currency, and an overdue count.
- **Settings → Academy:** the auto-invoice switch and the due days.

**Parent and student:** the "Learning" group gains "Invoices". It lists their invoices, and each one opens read-only with Print.

**Print page** (`/app/invoices/<id>/print`):
- rendered without the app shell;
- shows the academy logo and name (site branding), invoice number, dates, payer and student, description, amount, the payments made and the balance due;
- in the viewer's language, RTL for Arabic;
- styled for A4 printing (`@media print`), with a Print button hidden on paper.

**Throughout:**
- every string is in Arabic and English;
- right-to-left and phone width;
- semantic colour tokens only;
- not-found and error states;
- 409 codes shown translated;
- the shared helpers reused.

## 7. Seeds

Demo subscriptions get their invoices (by auto-invoicing or a backfill):
- one paid in full;
- one partly paid;
- one unpaid and overdue;
- one void.

Running seeding twice changes nothing.

## 8. Testing

- **Backend:**
  - status arithmetic across add and delete payment;
  - overpayment refused;
  - void and edit rules;
  - numbering: sequential, with no duplicates under concurrent creation (a lock-shape test);
  - auto-invoice on create and renew, with the switch off, at a zero price, and rolled back with the subscription on failure;
  - the payer rule and payer validation;
  - subscription payment status;
  - revenue and overdue per currency, using the academy month boundaries;
  - the role × route matrix, including anonymous;
  - cross-academy isolation with data in both academies.
- **Dashboard:** every page, dialog and the print page, in both languages, with error, not-found and validation states.
- **E2E through Caddy:**
  1. The admin creates a subscription and its invoice appears.
  2. The admin records a partial payment, then the rest; the status goes partial, then paid.
  3. The parent (invited, sets a password) signs in, sees the paid invoice and opens the print page.
- **Coverage gates as today.**

## 9. Risks

- **Money mistakes.** Mitigation:
  - one status function;
  - integer minor units only;
  - overpayment refused;
  - currencies never mixed;
  - a test matrix over add, delete and void.
- **Duplicate invoice numbers.** Mitigation: a locked counter row per academy, with a concurrency test.
- **Invoice and subscription drift.** A subscription can be edited after its invoice. The invoice keeps its own amount, and the admin edits or voids it by hand.

## 10. Out of scope (roadmap phase)

- Gateways, payment links, service fees, wallets, codes, expenses, net profit, exchange rates: B3.
- Unpaid-invoice reminders and notifications: Plan 8 and B5.
- Family accounts with a single payer: B1.
- Refunds: B3.
