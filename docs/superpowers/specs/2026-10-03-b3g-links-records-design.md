# Slice B3g — Payment links and payment records — Design

**Date:** 2026-10-03
**Status:** Draft for the B3 orchestrator's review (orchestration spec PO-3). B3g was split from B3c by
B3c's spec review and is built right after B3c, before B3d (phase §3).
**Phase:** B3 (`2026-10-03-b3-money-depth-design.md`), slice B3g. **Requires:** no other phase's slice;
B3c (`2026-10-03-b3c-paypal-design.md`) merges first.
**Builds on:**
- B3b (`2026-10-03-b3b-online-payments-design.md`): gateways, `start_checkout`, purposes, webhooks, the
  simulator, payment status, fee and refunds;
- B3c: PayPal, the capture and cancel routes, `complete_paypal`, the still-payable check (C-8);
- B3a (`2026-10-03-b3a-expenses-donations-design.md`): donations through `finance.services`;
- Plan 6 billing, Plan 12a roles, Plan 13 feature switches.

**Evidence:**
- audit BILL-001 (payment records: customer name, transaction number, customer type, method, amount,
  currency, status, date; filters; one "unregistered student" Stripe row);
- audit BILL-004 (payment links: registered / unregistered student, gateway PayPal / Stripe, currency,
  amount, "enable 5 % service fee", description, status, copy link; filters gateway, status, dates; a
  "Link subscription" tab whose fields were not rendered);
- audit BILL-005 (a Stripe donation, completed); SUB-006 / §1.3 #6 (payment type, subscription system);
  SYS-002 (`payment_links`, `payment_receipts`);
- P1 BILL-001, BILL-004, BR-25 (5 % fee), BR-47 (revenue = completed payment records).

## 1. Goal

An admin records payments that have no invoice, sees every payment record in one list and exports it. They
create a payment link for a registered or unregistered student, or a donation link, and send it. Whoever
opens it pays without logging in, and the money becomes a payment record or a donation. Office staff can
note each subscription's payment type and system.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| G-1 | **Standalone payment records.** <br>• Billing's `Payment.invoice` becomes nullable. <br>• Every payment gains its own `currency`; an invoice payment takes the invoice's. <br>• `customer_type` is `student` or `unregistered`. <br>• Standalone records add `student`, `customer_name`, `customer_email` and `customer_phone`. <br>• Status stays B3b's `completed / refunded`. <br>Pending, failed or cancelled manual records are not built: TutorHamster's form shows them, but B3b fixed the two statuses. | audit BILL-001; spec b3b B-9; [assumed] |
| G-2 | **Delete versus edit.** <br>• DELETE is refused only for online methods (409 `billing.online_payment`, B-10). A manual invoice payment is still deleted as today, and its invoice is recalculated. A manual standalone record is deleted with no recalculation. <br>• PATCH is accepted only on a manual standalone record; anything else is a 409 `billing.payment_not_editable`. | spec b3b B-10; billing spec §4.2; spec review |
| G-3 | **Refunding a standalone record** uses B3b's refund route. It answers the payment row, not an invoice, and recalculates nothing. | spec b3b §4.7; spec review |
| G-4 | **Revenue includes standalone payments.** `revenue_between` sums `amount_minor + fee_minor` of completed payments, with or without an invoice, grouped by `Payment.currency`. Invoice sums are unchanged. | P1 BR-47; ledger D5; phase B3-5 |
| G-5 | **Code that assumed an invoice:** each of these handles `invoice=None`, checked against the code: <br>• `payments.delete_payment` locks and recalculates only when there is an invoice; <br>• B3b's refund service: G-3; <br>• `payloads.payment_row` replaces `invoice_id` with `invoice: {id, number} \| null`; <br>• `Payment.__str__` shows the currency instead of the invoice; <br>• `summary.revenue_between`: G-4. <br>`scopes.scope_for(via="invoice")` leaves standalone records out of the family scopes, which is intended: they are office-only. `rules.paid_of`, the paid subquery, `refuse_if_paid_into`, `add_payment` and the invoice purpose always filter by an invoice and are unchanged. | billing code (`services/payments.py`, `services/summary.py`, `api/payloads.py`, `scopes.py`, `models.py`) |
| G-6 | **A unique transaction number:** a breach of `(method, transaction_number)` when a record is created or edited is a 400 on `transaction_number`. | spec b3b §3.2; spec review |
| G-7 | **Payment links live in `etqan.gateways`** (`PaymentLink`). <br>• A link is single-use with a fixed amount, and its status is `open · paid · cancelled`. <br>• It is not edited (cancel it and create another) and has no expiry date. <br>• Its token is `secrets.token_urlsafe(16)`, compared with `hmac.compare_digest`. <br>• Its URL is `app_url("/pay/link/<token>")`. | phase B3-2; audit BILL-004 (status "paid", copy link); [assumed] |
| G-8 | **The payer** is either a registered student or an unregistered one. <br>• Registered: the API field `student` is the student's user id, as in billing's invoice API, resolved to the profile by `active_student`. <br>• Unregistered: `payer_name` is required; `payer_email` and `payer_phone` are optional. <br>Anyone holding the link can pay it; the payer only decides whom the money is recorded for. | audit BILL-004; billing API (`student`); [assumed] |
| G-9 | **The "Link subscription" tab** of BILL-004 is `[unknown]`: its fields were never rendered. It is not built and has no target slice; it is revisited only if it is observed. | audit BILL-004 (U-fields); ledger D1 |
| G-10 | **Two kinds of link.** <br>• `payment` uses the purpose `payment_link`, registered by billing; the money becomes a standalone record. <br>• `donation` uses the purpose `donation_link`, registered by finance; the money becomes a completed donation through `finance.services.create_donation`, with method = provider. <br>Purposes only record money; the link's own state belongs to gateways (G-13). Billing and finance read a link through `gateways.services.link_for(id) -> LinkInfo`, a frozen record: <br>`id, token, kind, status, title, student_id, payer_display_name, payer_email, payer_phone, amount_minor, currency, add_fee`. | phase B3-2, B3-7; ledger D13; spec b3a A-6 |
| G-11 | **Donation links and the `donations` switch:** while it is off, creating a donation link is refused (400 on `kind`), and the public routes answer 404 for donation links. A checkout already paid still records its donation (FT-4). | spec feature-toggles FT-4; spec review |
| G-12 | **The fee.** <br>• The setting `fee_enabled` only sets the default of a link's `add_fee` when the link is created. <br>• At checkout, the link's `add_fee` alone decides, always at the current `fee_basis_points` (B-7). <br>• The public page and the list's preview use the same rule. <br>• A donation link never has a fee. | phase B3-8; P1 BR-25, BILL-004; spec review |
| G-13 | **Completing a link checkout.** Gateways' completion path (B3b §4.4 and B3c's `complete_paypal`) locks the checkout and then the `PaymentLink` (`select_for_update`). <br>• A link that is not `open`: `applied=false`, attention `link_closed`, and the purpose is not called. <br>• An open link: the purpose's `complete` runs. When the money applied, the link becomes `paid`, with `checkout` and `paid_at`, under the same lock. <br>• B-11's checks still come first; an unapplied payment leaves the link `open`. | spec b3b B-11; spec review |
| G-14 | **Still payable for links:** B3c's C-8 check, for a link purpose, is "the link is still `open`", read under the checkout lock. | spec b3c C-8 |
| G-15 | **Anonymous link checkouts.** <br>• A link checkout is started only by the public route, as `start_checkout(…, user=None, params={"token": …})`. <br>• The purposes' `prepare` answers 404 on a token mismatch, so the generic `POST gateways/checkouts/` cannot start one. <br>• For a checkout whose purpose is `payment_link` or `donation_link`, the status, capture, cancel and simulate routes answer anyone holding the (unguessable, version 4) UUID. This is keyed on the purpose, not on the missing creator. <br>• The return and simulator pages move out of `_authed`. | spec b3b §4.5–4.6; spec b3c §4.3; spec review |
| G-16 | **Public routes** use `authentication_classes=[]` and `AllowAny`, with the per-IP throttle scope `payment_link` (60/minute). The academy's name comes from `connection.tenant.name`, read directly as `etqan.site` does; no accessor exists. The title and description are plain text, rendered escaped. | ledger D2; site code; [assumed] (rate) |
| G-17 | **A link whose provider cannot take it:** when the provider is disabled or does not take the link's currency, the public page reports `payable: false` and its Pay button is disabled with "Online payment is unavailable". A POST is then B3b's 400 on `provider`. | spec b3b §4.2 step 1; spec review |
| G-18 | **SUB-006 lives in billing**, not in scheduling (B2 owns scheduling). <br>• `SubscriptionTerms` is keyed by a plain `subscription_id`, as invoices are. <br>• `payment_type` is `prepaid` or `postpaid` (default `prepaid`); `system` is `normal` or `monthly` (default `normal`). <br>• Terms belong to one subscription id: a renewal starts from the defaults, and there is no B2 hook. <br>• They are recorded and shown only; nothing reads them. | ledger D10, D7; audit SUB-006; [assumed] (defaults, renewal, no effect) |
| G-19 | **SUB-006 is office-only:** its route needs `subscription.view` / `subscription.update` (HasCode). The card shows on the office invoice page, never on the family pages. | spec roles-permissions; [assumed] |
| G-20 | **Features:** `payment_links` and `payment_receipts` become built in place, `default=False`. <br>• `payment_links` requires `online_payments` (phase B3-3). <br>• `payment_receipts` requires `invoices`, and gates the records list, standalone records and the checkouts CSV. The checkouts CSV also needs `online_payments` and `export`. <br>• Completions keep working with either off. | phase B3-3; audit SYS-002; FT-4; [assumed] (`payment_receipts` scope) |
| G-21 | **Access:** a new resource `payment_link` (`view_any`, `create`, `update`). Billing's `payment` codes are used as they are. | spec roles-permissions; spec b3b B-14 |
| G-22 | **Imports.** <br>• Gateways never imports a selling app (billing, finance, wallet, B7's). It reads students through `identity.services` only (a refinement of B-1). <br>• A new contract: other apps reach gateways only through `gateways.services`. | spec b3b B-1; CLAUDE.md |
| G-23 | Only en and ar strings. | ledger D11 |

## 3. Data

### 3.1 `etqan.billing` (owned by B3)

**`Payment`:**
- `invoice` becomes nullable;
- adds `currency` (3 letters), `customer_type` (default `student`), `student` (→ `identity.StudentProfile`,
  nullable, `PROTECT`), `customer_name` (≤ 120), `customer_email` and `customer_phone` (≤ 30). The
  customer text fields are blank by default.
- **Check constraint:** one of
  - `invoice` set;
  - `customer_type=student` and `student` set;
  - `customer_type=unregistered`, `customer_name` not blank and `student` null.
- **Index** on `(currency, paid_on)`.

**The migration** runs in each academy's schema through `migrate_schemas`, in three steps:
1. Add the columns, with `currency` nullable, and make `invoice` nullable.
2. One `UPDATE billing_payment p SET currency = i.currency FROM billing_invoice i WHERE p.invoice_id = i.id`.
3. Make `currency` required, and add the check constraint and the index.

**`SubscriptionTerms`:** `subscription_id` (bigint, unique), `payment_type`, `system`, `updated_by` and
`updated_at`.

### 3.2 `etqan.gateways`

**`PaymentLink`:**

| Field | Notes |
|---|---|
| `token` | ≤ 32, unique |
| `kind` | `payment` or `donation` |
| `title` | 1–200 characters; the checkout's description |
| `description` | text, may be blank |
| `student` | → `identity.StudentProfile`, nullable, `PROTECT` |
| `payer_name`, `payer_email`, `payer_phone` | ≤ 120, email, ≤ 30; blank when `student` is set |
| `provider` | `stripe` or `paypal` |
| `amount_minor`, `currency` | amount > 0; `^[A-Z]{3}$` |
| `add_fee` | bool |
| `status` | `open · paid · cancelled` |
| `checkout` | → Checkout, nullable, `PROTECT` |
| `paid_at`, `cancelled_at`, `cancelled_by` | |
| `created_by`, `created_at` | |

- **Check constraints:**
  - `student` is set ⇔ `payer_name` is blank;
  - a `donation` link has `add_fee = false`;
  - `amount_minor > 0`.
- **Ordering:** newest first.
- **Index:** on `status`.

## 4. Behaviour

### 4.1 Payment records

- **List** `GET billing/payments/` (`payment.view_any`, `payment_receipts`):
  - newest `paid_on` first, paginated;
  - each row is `{id, customer: {type, name, student_id}, invoice: {id, number} | null, transaction_number, reference, method, amount_minor, fee_minor, currency, status, paid_on, notes, refunded_at, recorded_by, editable, deletable}`:
    - the name is the invoice's student, the record's student, or `customer_name`;
    - `editable` = a manual method and no invoice;
    - `deletable` = a manual method;
  - filters: `method`, `customer_type`, `status`, `currency`, `paid_from`, `paid_to`, `has_invoice`
    (`true` / `false`) and `q` (name, transaction number or invoice number). A bad value is a 400 on that
    filter.
  - `?format=csv` answers while `export` is on (404 otherwise), with the columns Date, Customer, Customer
    type, Invoice, Method, Transaction number, Amount (minor units), Fee (minor units), Currency and Status.
- **Create** `POST billing/payments/` (`payment.create`, `payment_receipts`) takes
  `{customer_type, student | customer_name (+ customer_email?, customer_phone?), amount_minor, currency?, method, transaction_number?, reference?, paid_on?, notes?}`:
  - manual methods only;
  - `paid_on` is not in the future;
  - the currency defaults to the academy's;
  - G-6 applies.
- **Detail** `billing/payments/<id>/`:
  - feature by method: `{"GET": "payment_receipts", "PATCH": "payment_receipts", "DELETE": "invoices"}`;
  - GET needs `payment.view_any`;
  - PATCH (`payment.update`) takes any subset of the create fields except `customer_type`, which is fixed
    when the record is created; it is refused as G-2 says;
  - DELETE (`payment.delete`) follows G-2.

### 4.2 Payment links (admin)

- **Create** `POST gateways/links/` (`payment_link.create`) takes
  `{kind, title, description?, student | payer_name (+ payer_email?, payer_phone?), provider, amount_minor, currency?, add_fee?}`:
  - the currency defaults to the academy's;
  - the provider must be enabled and take the currency (400 on `provider`);
  - exactly one of `student` and `payer_name` (400);
  - `student` must be active (400 on `student`);
  - `add_fee` defaults to `fee_enabled` (G-12);
  - G-11 applies to a donation link, which also forces `add_fee=false`;
  - answers 201 with the row.
- **Row:** `{id, kind, title, description, payer: {type, student_id, name, email, phone}, provider, amount_minor, currency, add_fee, fee_minor, status, url, checkout_id, paid_at, created_by, created_at}`.
  `fee_minor` is the paying checkout's fee for a paid link, otherwise the preview (G-12).
- **List** `GET gateways/links/` (`payment_link.view_any`): paginated; filters `status`, `kind`, `provider`,
  `created_from`, `created_to` and `q` (title or payer name). **Detail** `gateways/links/<id>/`, with the
  same code.
- **Cancel** `POST gateways/links/<id>/cancel/` (`payment_link.update`):
  - `open` → `cancelled`; any other status is a 409 `gateways.link_closed`;
  - a pending checkout is left alone; money that still arrives becomes attention (G-13).

### 4.3 Public pay page

- **`GET gateways/pay/<token>/`** (G-16) answers
  `{academy_name, kind, title, description, payer_name, amount_minor, fee_minor, currency, provider, status, payable}`:
  - `payer_name` is the first name only for a registered student;
  - `payable` is false for a closed link, and in the cases of G-17;
  - 404 for an unknown token, while `payment_links` is off, and for G-11.
- **`POST gateways/pay/<token>/checkout/`:**
  - calls `start_checkout("payment_link" | "donation_link", link.id, link.provider, user=None, params={"token": token})`;
  - answers 201 with `StartedCheckout`;
  - a closed link is a 409 `gateways.link_closed`.
- **The purposes' `prepare`:**
  - checks the token with `compare_digest` (404 on a mismatch);
  - requires `open` (409);
  - returns `Prepared(amount_minor, currency, title, add_fee)`.
- **`payment_link`'s `complete`** (billing) adds a payment with:
  - `invoice=None` and the link's customer fields;
  - method = provider; the amount, fee, currency and transaction number;
  - `paid_on` = the academy's today, `recorded_by=None`;
  - notes "Payment link: <title>".

  It returns `Applied(True, "")`.
- **`donation_link`'s `complete`** (finance) calls `create_donation` with:
  - `method` = provider, `status=completed`, the transaction number;
  - donor = `payer_display_name` and `payer_email`;
  - `received_on` = the academy's today, `by=None`;
  - notes "Payment link: <title>".

### 4.4 Checkouts CSV

`GET gateways/checkouts/?format=csv` (`checkout.view_any`) answers only while `online_payments`,
`payment_receipts` and `export` are all on; otherwise 404. It keeps B3b's filters. Its columns are:
Created, Checkout, Purpose, Reference, Provider, Amount (minor units), Fee (minor units), Currency, Status,
Applied, Attention, Transaction number, Completed at.

### 4.5 Subscription payment terms (SUB-006)

- **`GET billing/subscriptions/<id>/terms/`** (`subscription.view`) answers `{payment_type, system}`, with
  the defaults when no row exists.
- **`PATCH`** (`subscription.update`) creates the row or updates it.
- An id that `scheduling.services.subscriptions_queryset()` does not hold is a 404.
- There is no feature gate.
- A deleted subscription's row stays and is never read.

## 5. API summary (`/api/v1/`)

| Route | Methods | Feature | Codes |
|---|---|---|---|
| `billing/payments/` | GET, POST | `payment_receipts` | `payment.view_any`, `payment.create` |
| `billing/payments/<id>/` | GET, PATCH / DELETE | `payment_receipts` / `invoices` | `payment.view_any`, `payment.update`, `payment.delete` |
| `billing/subscriptions/<id>/terms/` | GET, PATCH | — | `subscription.view`, `subscription.update` |
| `gateways/links/` | GET, POST | `payment_links` | `payment_link.view_any`, `payment_link.create` |
| `gateways/links/<id>/` | GET | `payment_links` | `payment_link.view_any` |
| `gateways/links/<id>/cancel/` | POST | `payment_links` | `payment_link.update` |
| `gateways/pay/<token>/` | GET | `payment_links` | public, throttled |
| `gateways/pay/<token>/checkout/` | POST | `payment_links` | public, throttled |
| `gateways/checkouts/?format=csv` | GET | `online_payments` + `payment_receipts` + `export` | `checkout.view_any` |

**Changed on purpose:**
- the status, capture, cancel and simulate routes for link purposes (G-15);
- a billing payment's payload: `invoice`, `currency`, the customer fields, `editable` and `deletable`;
- B3b's refund route answers the payment row for a standalone record;
- billing's summary test: revenue includes standalone records;
- the route table, registry and feature counts.

## 6. Dashboard

- **`routes/pay.return.tsx`** and **`routes/pay.simulate.$checkoutId.tsx`** move out of `_authed` (G-15).
  For a link checkout, the return page shows the status only, with no back link.
- **`routes/pay.link.$token.tsx`** (public) shows the academy name, the title, the description (plain
  text), the amount, the fee, the total, and Pay. When the link is not `payable` the page says why: paid,
  cancelled, or unavailable.
- **Billing → Payment links** (`_authed/billing.links.tsx`, `payment_link.view_any`, `payment_links`):
  - the list, with its filters and copy-link;
  - a create dialog with:
    - the payer: a registered-student picker, or an unregistered name, email and phone;
    - the kind (Donation only while `donations` is on);
    - provider, currency and amount;
    - the fee toggle, defaulting to the setting and hidden for donations;
    - title and description;
  - Cancel.
- **Billing → Payment records** (`_authed/billing.payments.tsx`, `payment.view_any`, `payment_receipts`):
  - the list, with its filters and CSV;
  - an add / edit dialog for standalone records;
  - Mark refunded;
  - delete, when the row is `deletable`.
- **Billing → Online payments:** a CSV button (G-20).
- **Office invoice page:** for a subscription invoice, a "Payment terms" card (`SubscriptionTermsCard`,
  exported from `features/billing`). It shows to holders of `subscription.view` and is editable with
  `subscription.update`.
- **Wiring:**
  - keys in `locales/{en,ar}/gateways.json` and `billing.json`;
  - nav items under the B3 marker;
  - `FeatureCode` gains `payment_links` and `payment_receipts`;
  - `FEATURE_SCREENS` and `FEATURE_WORDS` rows;
  - the `/billing` index order: invoices, payments, links, expenses, donations;
  - semantic tokens, RTL and phone width.

## 7. Dependencies and environment

- **No new package.**
- **Settings:** the throttle scope `payment_link` (60/minute, per IP).
- **Wiring under the B3 markers:**
  - `payment_links` and `payment_receipts` flipped in place in `platform/features.py`, using the
    `requires` argument B3b gives `_built`;
  - the `payment_link` resource in `access/registry.py`;
  - the import contract of G-22;
  - `FinanceConfig.ready()` registers `donation_link`; `BillingConfig.ready()` registers `payment_link`.
- **Request to B2** (non-blocking, orchestration spec §6.2.1): one line in
  `routes/_authed/scheduling.subscriptions.$subscriptionId.tsx` that renders `SubscriptionTermsCard`.
  B3g does not wait for it: the card already shows on subscription invoices, and B2 changes no model.

## 8. Seeds

The demo academy gets these under the B3 marker of `seed_academy`. Each step runs only when its table is
empty.
- An open **Stripe** payment link in the academy's currency, for a registered demo student, with the fee.
- An open **PayPal** donation link in USD, for an unregistered donor.
- One standalone cash record for an unregistered customer.

## 9. Testing

- **Backend:**
  - **Payment records:**
    - the migration's three steps and the currency fill;
    - the constraints;
    - every G-5 function with `invoice=None`;
    - list filters and their 400s; CSV with `export` on and off;
    - create, edit and delete under G-2, including deleting a manual invoice payment (recalculated) and
      refusing to delete an online one;
    - G-6's 400;
    - refunding a standalone record (G-3);
    - revenue with standalone and refunded records.
  - **Links:**
    - validation, G-11 and G-12, cancel;
    - public routes: unknown token, feature off, closed link, `payable` false, token mismatch through the
      generic route, the throttle;
    - both purposes end to end with Stripe and PayPal;
    - G-13: paying a paid or cancelled link gives attention without calling the purpose; an unapplied
      payment leaves the link open;
    - G-14 before a PayPal capture;
    - anonymous access for link purposes only (G-15).
  - **SUB-006:** defaults, create-or-update, an unknown subscription is 404, the codes, and a family
    refused.
  - **Checkouts CSV:** each of its three switches.
  - **Matrix and isolation:** the role × route rows; cross-academy isolation of tokens.
- **Dashboard:**
  - both admin pages and their dialogs;
  - the public link page in each state;
  - the public return and simulator pages;
  - the terms card;
  - the CSV buttons;
  - both languages.
- **E2E** (`dashboard/e2e/b3-payment-links.spec.ts`):
  1. Switch on `invoices`, `online_payments`, `payment_links` and `payment_receipts` for demo.
  2. The admin creates a Stripe link for an unregistered student.
  3. A logged-out browser pays it through the Stripe simulator.
  4. The link shows Paid, and the payment records list shows the record with its fee.

## 10. Out of scope

- Reusable or open-amount links, link expiry dates, and sending links by email or WhatsApp (B5 may add
  sending).
- BILL-004's "Link subscription" tab (G-9).
- Pending, failed or cancelled manual payment records (G-1).
- Any effect of SUB-006 on invoicing or renewals (G-18).
- Wallet top-up through links (B3e), activation codes as a payment method (B3f), local payment methods
  (B3d).
