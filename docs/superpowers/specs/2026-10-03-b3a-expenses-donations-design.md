# Slice B3a — Expenses, donations and net profit — Design

**Date:** 2026-10-03
**Status:** Approved by the B3 orchestrator on 2026-10-03, after an independent spec review whose findings
are folded in (orchestration spec PO-3).
**Phase:** B3 (`2026-10-03-b3-money-depth-design.md`), slice B3a. **Requires:** no other phase's slice.
**Builds on:** Plan 6 billing (`2026-09-25-billing-design.md`), Plan 12a roles
(`2026-09-28-roles-permissions-design.md`), Plan 13 feature switches (`2026-09-30-feature-toggles-design.md`).
**Evidence:** audit BILL-005, BILL-006 and §3 #9; P1 BILL-005/006, DASH-003, BR-47/48, §4.2 (resource names);
audit PAY-013.

## 1. Goal

An academy records what it spends (expenses) and what it is given (donations), and its admin home shows
this month's expenses, net profit (revenue − expenses) and donations per currency. Other apps post expenses
through one service; B4 uses it to turn paid teacher payslips into expenses (PAY-013).

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| A-1 | A new tenant app `etqan.finance` owns `Expense`, `Donation` and `DonationCounter`. It never imports another app's models. It reads revenue and the payment-method list through `etqan.billing.services` (two additive exports, §4.5), and the academy's timezone through `etqan.academy.services`; it has its own `finance.clock` (as billing has), which tests pin. | phase B3-2; billing `clock.py` pattern |
| A-2 | Two features, both built and off by default (`default=False`): `expenses` (new, under the B3 marker, group money) and `donations` (TutorHamster's flag, made built in place). A switched-off feature's routes answer 404 to callers who hold the route's code (non-holders still get 403, as `FeatureOn` runs after the code check). Its nav items and cards disappear, and its data stays. The seeded demo academy has both on (`seed_dev.FEATURES = BUILT`). | phase B3-3; spec feature-toggles §5.2, §7, FT-4 |
| A-3 | Expense fields follow TutorHamster: title\*, type\*, amount\*, currency, notes. Currency is required in TutorHamster's form; here it defaults to the academy's currency when omitted. We add `spent_on`, the academy-calendar date the money went out, so months are counted by it. | audit BILL-006; [assumed] (`spent_on` and the currency default; TutorHamster lists by created date) |
| A-4 | Expense types: `salaries · rent · marketing · software · utilities · supplies · fees · other`. | audit BILL-006 ("salaries" seen; options not rendered, U11); [assumed] (the rest) |
| A-5 | Donation fields follow TutorHamster: a record number, amount\*, method\*, transaction number, status\*. We add currency, optional donor name and email, `received_on` and notes. The number format is `DON-000001`. | audit BILL-005, P1 BILL-005 (record no., amount, method, transaction no., status); [assumed] (currency, donor, `received_on`, notes, number format) |
| A-6 | Donation methods: billing's manual methods plus `stripe` and `paypal`, for a gateway donation recorded by hand with its transaction number. Donation status: `pending · completed · failed · refunded · cancelled`. Only `completed` donations count in totals. | P1 BILL-005 (a Stripe `pi_…` row, "completed"); P1 BR-47 (completed only); [assumed] (the manual methods; the status list is borrowed from the subscription payment-status list, audit §1.3 #6) |
| A-7 | Revenue is billing's revenue for the month (payments by `paid_on`). Net profit = revenue − expenses, per currency, for the academy's current calendar month. A currency with only expenses shows a negative profit. **Net profit is shown only while `invoices` is on**: without invoices the academy records no revenue, and "−expenses" would mislead. Donations are not revenue and have their own card. | phase B3-5; P1 BR-47/48; [assumed] (hidden with invoices off) |
| A-8 | **Posted expenses.** `post_expense(source, source_id, …)` creates or updates the one expense for that source; `withdraw_expense(source, source_id)` deletes it. A posted expense is read-only through the API (409 `finance.expense_posted`). Posting works whether or not `expenses` is on, so the record is complete when it is switched on. | audit PAY-013; spec feature-toggles FT-4; [assumed] (read-only) |
| A-9 | Access: two new permission resources, `expense` and `donation`, with `view, view_any, create, update, delete` in use. Admins hold every code. Teachers, parents and students never see finance. The home cards need the existing `widget.revenue_stats`. | spec roles-permissions; P1 §4.2 (resources `expense`, `donation::record`) |
| A-10 | Money is integer minor units plus an ISO 4217 currency, never summed across currencies. | phase B3-4 |

## 3. Data (`etqan.finance`)

### 3.1 Expense

| Field | Notes |
|---|---|
| `title` | text, 1–200 characters |
| `type` | A-4 values |
| `amount_minor` | > 0 (check constraint) |
| `currency` | `^[A-Z]{3}$` |
| `spent_on` | date (academy calendar) |
| `notes` | text, may be blank |
| `source` | text ≤ 40, blank for a manual expense; for a posted one a dotted source name such as `payroll.payslip` |
| `source_id` | bigint, null for a manual expense |
| `created_by` | → User, nullable, `SET_NULL` (null for a posted expense) |
| `created_at`, `updated_at` | |

Constraints:
- `source` blank ⇔ `source_id` null (check constraint);
- `(source, source_id)` unique where `source` is not blank (conditional unique constraint).

Ordering is newest `spent_on`, then newest id. There is an index on `spent_on`.

### 3.2 Donation

| Field | Notes |
|---|---|
| `number` | `DON-000001`, unique, taken from `DonationCounter` (one row, pk 1) under a row lock, as invoice numbers are |
| `amount_minor` | > 0 (check constraint) |
| `currency` | `^[A-Z]{3}$` |
| `method` | A-6 values |
| `transaction_number` | text ≤ 120, may be blank |
| `status` | A-6 values |
| `donor_name` | text ≤ 120, may be blank |
| `donor_email` | email, may be blank |
| `received_on` | date (academy calendar) |
| `notes` | text, may be blank |
| `created_by` | → User, nullable, `SET_NULL` |
| `created_at`, `updated_at` | |

Ordering is newest `received_on`, then newest id. There is an index on `received_on`.

## 4. Behaviour

### 4.1 Requests

**Expense** (POST; PATCH takes any subset of the same fields):

| Field | Required | Default | Rule |
|---|---|---|---|
| `title` | ✓ | | 1–200 characters |
| `type` | ✓ | | A-4 |
| `amount_minor` | ✓ | | integer ≥ 1 |
| `currency` | | academy `default_currency` | `^[A-Z]{3}$` |
| `spent_on` | | academy today | not after the academy's today (400 on `spent_on`) |
| `notes` | | `""` | |

`source` and `source_id` are never writable through the API.

**Donation** (POST; PATCH takes any subset, but `number` is never writable):

| Field | Required | Default | Rule |
|---|---|---|---|
| `amount_minor` | ✓ | | integer ≥ 1 |
| `method` | ✓ | | A-6 |
| `currency` | | academy `default_currency` | `^[A-Z]{3}$` |
| `status` | | `completed` | A-6 |
| `received_on` | | academy today | not after the academy's today (400 on `received_on`) |
| `transaction_number`, `donor_name`, `donor_email`, `notes` | | `""` | lengths as §3.2; email format |

### 4.2 Responses

A list row is the same as the detail.

- **Expense:** `{id, title, type, amount_minor, currency, spent_on, notes, source, source_id, posted, created_by, created_at, updated_at}`.
  `posted` is `source != ""`. `created_by` is `{id, full_name}` or null.
- **Donation:** `{id, number, amount_minor, currency, method, transaction_number, status, donor_name, donor_email, received_on, notes, created_by, created_at, updated_at}`.

### 4.3 Lists

- **Expenses:**
  - filters: `type`, `currency`, `spent_from`, `spent_to` (academy dates), `q` (title contains), and `posted` (`true` / `false`);
  - a filter value that fails to parse is a 400 on that filter;
  - paginated with the shared pager;
  - `?format=csv` answers while the `export` feature is on, otherwise 404 (as billing's CSV does), with columns Title, Type, Amount (minor units), Currency, Spent on, Notes, Posted (yes/no).
- **Donations:**
  - filters: `status`, `method`, `currency`, `received_from`, `received_to`, and `q` (number, donor name or transaction number);
  - CSV as for expenses, with columns Number, Donor, Email, Amount (minor units), Currency, Method, Transaction number, Status, Received on.

### 4.4 Posting service (for other apps)

```python
finance.services.post_expense(
    *, source: str, source_id: int, title: str, type: str,
    amount_minor: int, currency: str, spent_on: date, notes: str = "",
) -> Expense
finance.services.withdraw_expense(*, source: str, source_id: int) -> None
```

- **`post_expense`** finds the expense for `(source, source_id)` under `select_for_update` and updates it in place.
  - If there is none, it inserts one inside a savepoint.
  - If that insert hits the unique constraint because a concurrent post won, it re-reads the row under lock and updates it.
  - The result is one row per source, whatever the interleaving.
- **`withdraw_expense`** deletes the row, and does nothing if there is none.
- **Validation:** the same rules as the API (title, amount ≥ 1, currency format, known type). `source` must be non-blank. A bad value raises the platform `ValidationError`. `spent_on` may be any date; the source decides.
- **Transactions:** the caller owns the transaction. A post inside the caller's transaction rolls back with it.

### 4.5 Billing exports (additive)

- `billing.services.revenue_between(first: date, following: date) -> list[{currency, amount_minor}]`: payments with `first ≤ paid_on < following`, summed per currency, in currency order. Billing's own `revenue_this_month()` is rewritten on top of it, with the same result.
- `billing.services.MANUAL_PAYMENT_METHODS`: the `(value, label)` pairs of `Payment.Method`, which finance's donation methods extend.

### 4.6 Summaries

**`finance/summary/`** is gated on `expenses` and needs `widget.revenue_stats`. It covers the academy's current calendar month (`finance.clock`):

```json
{
  "expenses_this_month": [{"currency": "USD", "amount_minor": 12000}],
  "net_profit_this_month": [{"currency": "USD", "amount_minor": 38000}]
}
```

- Expenses are counted by `spent_on`, revenue by `revenue_between` over the same month.
- `net_profit_this_month` lists every currency present in revenue or expenses, as revenue − expenses, in currency order.
- While `invoices` is off the key is `null` (A-7). The card then shows expenses only.

**`finance/donations/summary/`** is gated on `donations` and needs `widget.revenue_stats`. It returns `{"donations_this_month": [{currency, amount_minor}]}`, counting completed donations by `received_on`.

## 5. API (`/api/v1/finance/`)

| Route | Methods | Feature | Codes |
|---|---|---|---|
| `expenses/` | GET, POST | `expenses` | `expense.view_any`, `expense.create` |
| `expenses/<id>/` | GET, PATCH, DELETE | `expenses` | `expense.view`, `expense.update`, `expense.delete` |
| `donations/` | GET, POST | `donations` | `donation.view_any`, `donation.create` |
| `donations/<id>/` | GET, PATCH, DELETE | `donations` | `donation.view`, `donation.update`, `donation.delete` |
| `donations/summary/` | GET | `donations` | `widget.revenue_stats` |
| `summary/` | GET | `expenses` | `widget.revenue_stats` |

- **Responses:**
  - POST answers 201 and PATCH answers 200, each with the row (§4.2);
  - DELETE answers 204.
- **Errors:**
  - a field problem is a 400 on that field;
  - an edit or delete of a posted expense is a 409 with body `{detail, code: "finance.expense_posted"}`;
  - an unknown id is a 404.
- **Access:**
  - teachers, parents, students and anonymous callers get 403 on every route;
  - staff without the code get 403;
  - while the route's feature is off, a code holder gets 404.

**Wiring:**
- `config/api_router.py` adds `finance/` under the B3 marker;
- `TENANT_APPS` adds `etqan.finance` under the B3 marker;
- the import-linter gets a finance contract under the B3 marker. Finance is also added to the sources of
  the "other apps reach billing only through its services" contract, and to the platform contract's
  forbidden list, under its B3 marker;
- `etqan/access/tests/test_routes.py` gets the new route rows, `FEATURES` entries and `"/finance/"` in
  `FEATURE_WORDS`;
- `etqan/platform/tests/test_features.py`'s `BUILT` expectation gets the two features.

## 6. Dashboard (`/app/`)

- **Nav:** two items under the B3 marker, in group `billing`:
  - "Expenses": `/billing/expenses`, code `expense.view_any`, feature `expenses`;
  - "Donations": `/billing/donations`, code `donation.view_any`, feature `donations`.

  Their labels are `finance.nav.expenses` and `finance.nav.donations`, in the new area files
  `locales/{en,ar}/finance.json`, as `website.nav.*` does.
- **`/billing` index:** redirects to the first billing page the user may see, in nav order: invoices, then
  expenses, then donations. It no longer always sends the user to invoices.
- **`FeatureCode`** (`features/identity/schemas.ts`) gains `"expenses" | "donations"`. This file has no phase
  markers, so rebases may conflict there; keep it to that one line.
- **Expenses page:**
  - a list with type, currency and date filters, search, the pager, and CSV when `export` is on;
  - a create / edit dialog: title, type, amount, currency (defaulting to the academy's), date (defaulting
    to today), notes;
  - delete, with a confirmation;
  - a posted row shows a badge named after its source (`finance.source.payroll.payslip` → "Posted from
    payroll", with a generic "Posted" for an unknown source) and offers no edit or delete.
- **Donations page:** the same pattern, with status, method, currency and date filters, search, the pager,
  CSV, the dialog, and delete with a confirmation.
- **Home:** one added line in `routes/_authed/index.tsx`, rendering a `FinanceSummaryCard`. The card shows:
  - "Expenses this month" and, when not null, "Net profit this month" per currency, with negatives in the
    danger tone, while `expenses` is on;
  - "Donations this month" while `donations` is on;
  - all of it behind `widget.revenue_stats`.
- **Throughout:**
  - RTL and phone width;
  - semantic tokens only;
  - error, empty and not-found states;
  - the 409 code translated;
  - both languages key for key.

## 7. Seeds

A B3 step under `seed_academy`'s B3 marker, with its data and functions in `etqan/tenants/seeds/finance.py`.
It gives the demo academy:
- four expenses in the current month: rent, marketing, software, and a manual salaries expense;
- three donations: two completed, one pending.

The step runs only when the academy has no expenses and no donations, so seeding twice changes nothing.
The demo academy has both features on through `BUILT` (A-2); `other` keeps the defaults (off).

## 8. Testing

- **Backend:**
  - model constraints;
  - create, edit and delete, including the posted-expense refusals;
  - filters and their 400s;
  - CSV with `export` on and off;
  - donation numbering: sequential, under a lock;
  - `post_expense`: create, update in place, the duplicate-insert fallback, `withdraw_expense`, and a
    post rolled back with its caller's transaction;
  - summary arithmetic: several currencies, month boundaries in the academy's timezone, pending
    donations excluded, net profit `null` with `invoices` off;
  - `revenue_between`, and `revenue_this_month` unchanged;
  - feature gates (404 for code holders) and the role × route matrix (admin, staff with and without
    codes, teacher, parent, student, anonymous);
  - cross-academy isolation.
- **Dashboard:**
  - both pages, the dialogs, the home card and the `/billing` redirect, in both languages;
  - error, empty and validation states;
  - nav visibility by feature and permission.
- **E2E** (`dashboard/e2e/b3-finance.spec.ts`, through Caddy):
  - before the test, `manage("set_features", "demo", "--on", "expenses", "donations")` through
    `e2e/manage.ts`, so it does not depend on the seed;
  - the admin records an expense and a donation;
  - the home shows the expense, the net profit and the donation.

## 9. Out of scope

- Gateway donations taken online (B3b), exchange-rate conversion of the totals (B3c).
- Posting paid payslips as expenses: the call is B4's (A-8 provides the service).
- Expense receipts or attachments, budgets, recurring expenses, charts.

## 10. Amendments from planning (Plan 15)

- **Donation methods** (A-6, §4.5): finance keeps the list as a static tuple in `finance.models`, and a test
  pins it to `billing.services.MANUAL_PAYMENT_METHODS` plus `stripe` and `paypal`. Computing it from
  billing's services while Django loads apps would make the models import billing's services.
- **`posted` filter** (§4.3) accepts only `true` or `false`; any other value is a 400. A missing filter
  means both kinds.
- **Wiring** (§5):
  - `FEATURE_WORDS` gets `"/expenses/"`, `"/donations/"` and `"/finance/summary/"`, since finance's routes
    belong to two features.
  - Finance's import rules are three new contracts under the B3 marker, not edits to the existing shared
    line. They are: finance reaches billing only through its services; billing never imports finance;
    finance's models are its own.
- **PATCH** ignores `source`, `source_id` and `number` in the body, without an error.
- **The posted-expense 409** is translated from `finance.json` by a finance helper; `errors.json` is left
  alone.
- **The home card** reads the `expenses` and `donations` flags from `me` and renders nothing when both are
  off.
- **Seeds** are in EGP, dated the first of the academy's current month.
