# Slice B4c — Teacher balance, withdrawals, acknowledgement, salary expenses — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); review findings applied
2026-10-08.
**Phase spec:** `docs/superpowers/specs/2026-10-08-b4-payroll-depth-design.md` (§3 row B4c, B4-1…B4-10).
**Requires:** B4a (Plan 46: the payroll strings area, conftest helpers, migration 0002) and B3a
(`finance.services.post_expense`, merged). Nothing from B4b; B4c may be built before B4b.

**Evidence:**
- P1 PAY-006: the salary invoice status pending / paid / cancelled, and the "teacher receipt-confirmation
  status".
- P1 PAY-007: withdrawal requests (teacher, amount in USD, request status, notes; filters status and teacher).
- P1 PAY-010: the teacher record's "current balance", which withdrawals draw against. TH lists it as a number
  field on the teacher form's financial tab. Whether it can be edited is unknown.
- BR-23 ("choose a teacher with sufficient balance") and BR-24 (USD).
- TH §1.3 #17: an expense "teacher salary – {teacher} – receipt INV-…" of type "salaries" (PAY-013, PROBABLE).
- P1 §3: the teacher actor requests withdrawals and receives salary receipts.
- Ledger D19: money-moving actions refuse an impersonated session.

Anything the audits do not show is marked `[assumed]`.

## 1. Goal

Three switches, each off by default:

1. **Teacher balance** (`teacher_balance`). The office may pay an issued payslip into the teacher's balance.
   The teacher (or the office for them) asks to withdraw from it, and the office approves, pays or rejects.
2. **Receipt acknowledgement** (`payslip_acknowledgement`). A teacher confirms receipt of a paid payslip.
3. **Salary expenses** (`salary_expenses`, `requires=()`). A payslip posts itself to the academy's expenses
   when it becomes paid. This happens whether or not finance's `expenses` switch is on, so the record is
   complete when expenses are shown (B3a A-8).

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| C-1 | **Pay to balance** is a second way to pay an issued payslip. `pay_to_balance(payslip, *, paid_on, by, notes=None)` does everything `mark_paid` does, and also sets `paid_to_balance = true`. It needs `teacher_balance` on: the route answers 404 while it is off. The payslip's status is `paid` either way, and the board shows "Paid to balance". | P1 PAY-010 · [assumed] that payslips feed the balance |
| C-2 | **The balance is derived, per currency.** Credits are the net of the teacher's paid-to-balance payslips. Withdrawn is the amount of their `paid` requests. Reserved is their requests that are `under_review` or `approved`. `balance = credits − withdrawn` and `available = balance − reserved`, computed in **one SQL statement** (conditional sums in subqueries of one SELECT). `payroll.services.balances_of(teacher_user_id) -> list[Balance(currency, balance_minor, available_minor)]` lists every currency with any credit or request, ordered by currency code. A user with no teacher profile gets `[]`. It is the only read other apps use (ledger decision, affects B11). There is no ledger table, so nothing can drift. | B4-3 · [assumed] derived |
| C-3 | **A withdrawal request** (`WithdrawalRequest`) has these fields: `teacher` (→ `TeacherProfile`, PROTECT), `amount_minor > 0`, `currency`, `status`, `notes` (the requester's), `office_notes`, `requested_by` / `decided_by` / `paid_by` (→ User, SET_NULL), `decided_at`, `paid_on`, `created_at` and `updated_at`. The statuses are `under_review` (the default, TH's "under review"), `approved`, `paid`, `rejected` and `cancelled`. The currency is one of the teacher's balance currencies, not always USD (phase §3 deviation from BR-24). A currency missing from `balances_of` is 400 on `currency`. | P1 PAY-007 · [assumed] statuses beyond "under review" |
| C-4 | **Transitions.** See the C-4 detail after this table. | [assumed]; extends phase §3 (office cancel) deliberately |
| C-5 | **Locks** (keeps the phase §3 rule). Create, approve, reject, pay and cancel each first take the payroll-owned row `BalanceLock(teacher, currency)` (unique; `get_or_create`, then `select_for_update`). They then lock the request row and decide on fresh rows. The order is always BalanceLock → request row. No payslip lock is ever taken inside it, and pay to balance takes no BalanceLock (it only raises the balance). On create, `amount > available` is 409 `payroll.insufficient_balance`. **Sufficient balance is enforced** (phase §3), which also covers two concurrent requests. | BR-23 · [assumed] enforced |
| C-6 | **Who acts.** A teacher creates requests only for themselves; the service refuses an inactive teacher's own request (400 on `teacher`). The office (resource `teacher_withdrawal`: `view_any`, `create`, `update`) creates and acts for any teacher, active or not, so someone who left can be paid out. Teachers read only their own requests and balance (others 404). Students and parents get 403. API bodies and filters name people by User id. | P1 PAY-007 form (the office picks the teacher); P1 §3; B4-9 |
| C-7 | **Payout details.** The office row shows the teacher's payout method and details (PEOPLE-005), read for the whole page from the `TeacherProfile` row that `withdrawals_queryset()` already joins through payroll's own `teacher` foreign key (a B4-1 field path; zero extra queries per page; plan 53 R3). This is intended: whoever pays a withdrawal needs them. Teachers see `office_notes` on their own requests, which is how they read a rejection reason. | P1 PEOPLE-005 |
| C-8 | **Acknowledgement.** While `payslip_acknowledgement` is on, the payslip's teacher may acknowledge a `paid` payslip once, which sets `acknowledged_at`. A second acknowledgement is 409 `payroll.already_acknowledged`; a payslip that is not paid is 409 `payroll.not_allowed_in_status`. Nobody else acknowledges: admins and staff get 403. The office sees the date. It changes no amount. | P1 PAY-006 "teacher receipt-confirmation status" |
| C-9 | **Salary expenses.** See the C-9 detail after this table. | TH §1.3 #17 (PAY-013); ledger D3; B3a A-8 |
| C-10 | **No impersonation** (D19). Every B4c write route adds `NotImpersonating`: pay-to-balance, acknowledge, and withdrawal create, approve, reject, pay and cancel. Plan 7's `mark-paid` is left unchanged (not B4c's route; an admin does not pay as someone else). | ledger D19 |
| C-11 | **Office balance view.** The withdrawals page shows the selected teacher's balances (read-only) above the list. That is where the office sees the teacher's "current balance". | P1 PAY-010 · [assumed] placement |

**C-4 detail — transitions.**
- From `under_review`:
  - → `approved` (office);
  - → `rejected` (office);
  - → `cancelled`, by the request's teacher (`teacher.user == request.user`, whoever created it) or by the
    office.
- From `approved`:
  - → `paid` (office; takes `paid_on`, which may not be after the academy's today nor before the request's
    creation date on the academy's calendar; 400 on `paid_on`);
  - → `rejected` (office);
  - → `cancelled` (office only).
- **Every rejection requires `office_notes`** (400 on `office_notes`).
- `paid`, `rejected` and `cancelled` are final. Any other move is 409 `payroll.not_allowed_in_status`,
  including a teacher cancelling an approved request.

**C-9 detail — salary expenses.**
- **When it posts.** While `salary_expenses` is on, the transaction that makes a payslip `paid` (by
  `mark_paid` or `pay_to_balance`) also calls `finance.services.post_expense(source="payroll.payslip",
  source_id=payslip.pk, title=…, type="salaries", amount_minor=net, currency=payslip.currency,
  spent_on=paid_on)`.
- **The title.** "Teacher salary – {name} – receipt {number}" (ar "راتب المعلم – {name} – إيصال {number}"), in
  the academy's default language. Any other language falls back to English (D11/D22). The name is truncated so
  the title fits finance's 200 characters.
- **When it does not post.**
  - A net of 0 posts nothing.
  - Withdrawals never post: the cost is recognised when the payslip is paid, including when it is paid to the
    balance [assumed].
  - Payslips paid while the switch was off are not back-posted.
- **Failures.** Any error from `post_expense` propagates and rolls the payment back (one transaction).
- **Lock order.** Payslip row, then the expense row inside `post_expense`'s savepoint; no path takes them the
  other way.

## 3. Data

| Model | Change |
|---|---|
| `Payslip` | `paid_to_balance` (bool, default false), `acknowledged_at` (datetime, null) |
| `WithdrawalRequest` (new) | as C-3; indexes (teacher, status) and (status, created_at); check `amount_minor > 0` |
| `BalanceLock` (new) | `teacher` (FK `TeacherProfile`, PROTECT), `currency`; unique (teacher, currency) |

There is one migration, `payroll/0004_balance_payouts` (0003 if B4c merges before B4b; §6.2 rule 2 decides at
rebase). It only adds tables and columns.

Payroll already reaches finance only through `finance.services`: B3's contract forbids every other app from
importing finance's models, api and clock. No `pyproject.toml` change is needed (supersedes the phase §4 note).

## 4. API (`/api/v1/payroll/`)

| Route | Methods | Code (route table) | Notes |
|---|---|---|---|
| `payslips/<id>/pay-to-balance/` | POST | `payslip.update` | Feature `teacher_balance`. Body `{paid_on, notes?}`. |
| `payslips/<id>/acknowledge/` | POST | — (`SELF_SERVICE`: "the payslip's teacher states receipt") | Feature `payslip_acknowledgement`. Checked in the view: 404 while the feature is off, 403 for anyone but a teacher, and 404 for a payslip that is not the teacher's own. |
| `balances/` | GET | `teacher_withdrawal.view_any` (or a teacher, own) | Feature `teacher_balance`. Office: `?teacher=<user id>` is required (400 on `teacher`), and a user who is not a teacher is 404. A teacher: the parameter is ignored and the balance is their own. |
| `withdrawals/` | GET / POST | `teacher_withdrawal.view_any` / `teacher_withdrawal.create` (or a teacher, own) | Feature `teacher_balance`. GET is paged; filters `status`, `currency` and `teacher` (office only). POST `{teacher?, amount_minor, currency, notes?}`; a teacher's `teacher` is forced to themselves. |
| `withdrawals/<id>/` | GET | `teacher_withdrawal.view_any` (or a teacher, own) | |
| `withdrawals/<id>/approve/`, `reject/`, `pay/` | POST | `teacher_withdrawal.update` | `reject` takes `{office_notes}`; `pay` takes `{paid_on}`. |
| `withdrawals/<id>/cancel/` | POST | `teacher_withdrawal.update` (or the request's teacher) | |

- **Teacher access.** Routes a teacher may use combine `HasCode | IsTeacher`, scoped like Plan 7's payslips.
- **Route-table tests.** Every route above except acknowledge joins `ROUTES` and the `FEATURES` map under
  `teacher_balance`, or `payslip_acknowledgement`. Acknowledge goes in `SELF_SERVICE` with its reason.
- **Payslip rows** gain `paid_to_balance` and `acknowledged_at`, both visible to teachers on their own payslips.
  The payslip CSV gains them as its last two columns. B4d appends after them.
- **The withdrawal row:** `{id, teacher, amount_minor, currency, status, notes, office_notes, requested_by,
  decided_by, decided_at, paid_on, paid_by, created_at, payout: {method, details}}`. `payout` is office-only.

## 5. Dashboard

- **Payslip page (office).**
  - "Pay to balance" sits beside "Mark paid" while `teacher_balance` is on, with the same date dialog.
  - The page shows "Paid to balance" and "Acknowledged on {date}".
- **Withdrawals page (office).**
  - Route `/payroll/withdrawals`, a nav item under Payroll, gated by `teacher_balance`.
  - Filters: status and teacher. With a teacher picked, that teacher's balances show above the list (C-11).
  - Rows: teacher, amount, status, requested date and payout method.
  - Actions: approve; reject (with a required reason); pay (with a date); cancel.
  - "New request": teacher → their balances → amount ≤ available. It is shown only with `teacher_withdrawal.create`
    and `teacher.view_any`, because the teacher picker needs the teacher list.
- **Teacher.**
  - "My balance" (`/teaching/balance`, `teacher_balance`): balances per currency and the teacher's requests,
    with "Request a withdrawal" (amount ≤ available). The teacher can cancel while a request is under review, and
    sees the rejection reason.
  - "My payslips" gains "Confirm receipt" on a paid payslip (`payslip_acknowledgement`).
- **Refusals.** Codes are translated: `payroll.insufficient_balance`, `payroll.already_acknowledged`, the status
  refusals, and `identity.impersonating`.

## 6. Seeds

B4c adds no seed data. A paid-to-balance payslip would need a newly issued month, and Plan 7's seeded payslips
(Bilal's paid, Maryam's issued) stay as they are. The E2E builds its own data.

## 7. Testing

- **Pay to balance:** the same as mark paid, plus the flag; 404 while off; the balance rises by the net.
- **Balance arithmetic:**
  - per currency;
  - reserved requests;
  - paid withdrawals;
  - two currencies;
  - `available` read in one SELECT (a query-count test);
  - `[]` for a non-teacher.
- **Withdrawals:**
  - every transition and every refusal;
  - insufficient balance;
  - a currency outside the balances → 400;
  - reject without notes → 400;
  - `paid_on` before the request date → 400;
  - concurrency: a lock-shape test capturing `BalanceLock … FOR UPDATE` before the request row on create,
    approve and pay;
  - teacher-own scope;
  - a service-level refusal of an inactive teacher's own request;
  - the office creating for an inactive teacher.
- **Acknowledgement:** the teacher only; paid only; once; 403 for admin, staff, student and parent; 404 while
  off.
- **Impersonation:** each B4c write route answers 403 `identity.impersonating` under quick login.
- **Expenses:**
  - posted on mark paid and on pay to balance while `salary_expenses` is on, **including with `expenses` off**;
  - one transaction (a failing post rolls back the payment);
  - not posted while off, or for a net of 0;
  - the title in each language and truncated for a long name;
  - idempotent by `source_id`.
- **API:** the role matrix and route table (ROUTES, FEATURES, `SELF_SERVICE`), and cross-academy isolation.
- **Dashboard:** each page and dialog in both languages.
- **E2E** (`e2e/b4-balance.spec.ts`). The test owns its data:
  1. Switches on.
  2. Through the API, a fresh teacher with a pending bonus adjustment dated last month (the simplest activity),
     then generate last month and issue that teacher's payslip.
  3. The admin pays it to the balance.
  4. The teacher signs in, sees the balance and requests part of it.
  5. The admin approves and pays the request.
  6. The teacher sees the lower balance and confirms receipt of the payslip.

  Generating last month also rebuilds the seeded teachers' drafts. It never touches issued or paid payslips, so
  other specs that assert those are unaffected.
