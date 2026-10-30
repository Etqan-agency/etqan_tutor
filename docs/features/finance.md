---
title: "Finance: expenses, donations, net profit and exchange rates"
---

`etqan.finance` records what an academy spends (expenses) and what it is given (donations). It
works out the month's net profit (revenue minus expenses, per currency) and stores exchange rates
typed in by hand. Those rates are used only to show labelled "converted estimates". Admins and
staff holding the finance codes use it. Families never see it. Payroll posts paid payslips into
expenses through a service.

Payment records and per-country local payment methods are billing's job; see
[billing.md](billing.md). Online donations come in through donation links; see
[online-payments.md](online-payments.md).

## Concepts

| Model | What it is |
| --- | --- |
| `Expense` | Fields: `title`, `type`, `amount_minor` > 0, `currency`, `spent_on` (academy date), `notes`. `type` is one of salaries, rent, marketing, software, utilities, supplies, fees, other. A *posted* expense has `source` + `source_id` (for example `payroll.payslip`, id), unique per source row. A manual expense has both blank. |
| `Donation` | Fields: number `DON-000001` (from `DonationCounter`, locked like invoice numbers), amount, currency, `method`, `transaction_number`, `status`, donor name and email, `received_on`. `method` is billing's manual methods plus `stripe` and `paypal`. `status` is one of pending, completed, failed, refunded, cancelled. Donations are **never revenue**. |
| `ExchangeRate` | One current row per `currency` (no history): `rate` (Decimal 20,10) = the value of one unit in `base_currency`. `base_currency` is the academy's `default_currency` at the moment the row was written. Rate > 0, and the currency cannot be the base itself. |

Money is integer minor units plus an ISO currency, as in billing. A rate is a decimal, not money.

## How it works

- **Expenses** (`services/expenses.py`):
  - `create_expense` defaults to the academy currency and today. A future `spent_on` is a 400.
  - `update_expense` and `delete_expense` refuse a posted expense (409
    `finance.expense_posted`); the app that posted it owns it.
- **Posting from other apps:** `post_expense(source, source_id, …)` creates or updates the one
  expense for that source row.
  - It is idempotent, and safe under races through a savepoint retry.
  - It runs in the caller's transaction.
  - `withdraw_expense` deletes the posted expense.
  - Today the only caller is `payroll/services/salary_expenses.py:post_salary`. It posts a
    `salaries` expense when a payslip is paid and `salary_expenses` is on, even if `expenses` is
    off.
- **Donations** (`services/donations.py`): manual create, update and delete. A donation is
  checked before it takes a number, so a refused one never consumes one. `received_on` may not be
  in the future.
  - The `donation_link` gateway purpose (`services/link_purpose.py`) records a completed online
    donation, with no fee, whatever the `donations` switch says.
  - Online donations that finance's rules refuse become checkout attention, never an error.
- **Summary** (`services/summary.py:summary`), for the academy's current calendar month:
  - `expenses_this_month`: expenses per currency.
  - `net_profit_this_month` = `billing.revenue_between(...)` − expenses, per currency, for every
    currency in either list. A currency with only expenses comes out negative. The value is
    `null` while `invoices` is off.
  - `net_profit_estimate`: see below.
  - `donations_summary` returns completed donations this month, per currency. They are reported
    separately and never added to profit.
- **Exchange rates** (`services/rates.py`):
  - `create_rate` refuses the academy currency itself and a currency that already has a row
    (edit that one instead).
  - `update_rate` rewrites the rate and re-stamps `base_currency` with the current default.
  - A row is *stale* when its currency has since become the academy currency (`own_currency`) or
    the academy currency changed (`base_changed`). It is *old* after 30 days; old rows still
    convert.
- **Converted estimate** (`services/convert.py:convert_estimate`): the only path that crosses
  currencies.
  - It returns `None` while `exchange_rates` is off.
  - It uses only rates stamped with the current base, so stale rows are skipped.
  - If any non-zero line lacks a rate, it returns `amount_minor=None` and lists the `missing`
    codes. It never returns a partial sum.
  - Otherwise it does exact Decimal maths, adjusting for each currency's minor digits, and rounds
    once, half up. `as_of` is the oldest rate used.
  - Callers: finance's summary, `payroll/services/projections.py`,
    `consultations/services/earnings.py`.

## API

All routes are under `/api/v1/finance/`, office only (`HasCode`). Each is gated by the feature
named in the Purpose column.

| Method | Path | Who | Purpose |
| --- | --- | --- | --- |
| GET, POST | `/api/v1/finance/expenses/` | `expense.view_any`/`expense.create` | List (filters, `posted`, `?format=csv`), create (`expenses`) |
| GET, PATCH, DELETE | `/api/v1/finance/expenses/<id>/` | `expense.view`/`.update`/`.delete` | Detail, edit and delete (manual only) |
| GET, POST | `/api/v1/finance/donations/` | `donation.view_any`/`donation.create` | List (CSV), create (`donations`) |
| GET, PATCH, DELETE | `/api/v1/finance/donations/<id>/` | `donation.view`/`.update`/`.delete` | Detail, edit, delete |
| GET | `/api/v1/finance/donations/summary/` | `widget.revenue_stats` | Donations this month (`donations`) |
| GET | `/api/v1/finance/summary/` | `widget.revenue_stats` | Expenses, net profit, estimate (`expenses`) |
| GET, POST | `/api/v1/finance/exchange-rates/` | `exchange_rate.view_any`/`.create` | Base currency plus rows with stale/old flags; add (`exchange_rates`) |
| PATCH, DELETE | `/api/v1/finance/exchange-rates/<id>/` | `exchange_rate.update`/`.delete` | Edit or delete a rate |

## Dashboard

These pages sit under the office `billing` layout:

| Route | Shows |
| --- | --- |
| `routes/_authed/billing.expenses.tsx` | `ExpensesList`, `ExpenseDialog` |
| `routes/_authed/billing.donations.tsx` | `DonationsList`, `DonationDialog` |
| `routes/_authed/billing.exchange-rates.tsx` | `ExchangeRatesList`, `ExchangeRateDialog` |

- `FinanceSummaryCard` sits on the admin home (`routes/_authed/index.tsx`). It is also reused by
  `features/consultations/MarginsReport.tsx`.
- `features/finance/landing.ts:billingLanding` picks the first billing page the user may open, for
  `/billing`.
- Feature folder: `dashboard/src/features/finance/`.

## Background jobs

None. Every figure is computed when it is read.

## Configuration

- **Features:** `expenses`, `donations`, `exchange_rates` (all built, off by default; they need
  nothing else) and `salary_expenses` (payroll posting).
  - Net profit also needs `invoices`.
  - CSV needs `export`.
- **Academy settings:** `default_currency` (the base for rates, and the default currency for new
  rows), `timezone` (the month boundaries).

## Code map

- `backend/etqan/finance/models.py`, `clock.py`
- `backend/etqan/finance/services/`: `expenses.py`, `donations.py`, `summary.py`, `rates.py`,
  `convert.py`, `link_purpose.py`, `rules.py`, `numbering.py`
- `backend/etqan/finance/api/`
- `backend/etqan/payroll/services/salary_expenses.py` (the posting caller)
- `dashboard/src/features/finance/`

## Design history

- [B3 phase design](../superpowers/specs/2026-10-03-b3-money-depth-design.md): B3-4 (no
  cross-currency sums) and B3-5 (revenue, donations, net profit).
- [B3a expenses and donations](../superpowers/specs/2026-10-03-b3a-expenses-donations-design.md):
  expenses, the posting service, donations, home cards.
- [B3g links and records](../superpowers/specs/2026-10-03-b3g-links-records-design.md): online
  donations through donation links.
- [B3h exchange rates](../superpowers/specs/2026-10-05-b3h-exchange-rates-design.md): split out of
  B3d. Covers rates and `convert_estimate`.
- [B3d countries and currencies](../superpowers/specs/2026-10-05-b3d-countries-currencies-design.md):
  despite the file name, it holds country prices and local methods (see billing). Its exchange
  rates part moved to B3h.
- Plans: [Plan 15 expenses and donations](../superpowers/plans/2026-10-03-plan-15-expenses-donations.md),
  [Plan 35 exchange rates](../superpowers/plans/2026-10-05-plan-35-exchange-rates.md).
