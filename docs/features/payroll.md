# Teacher payroll

Monthly teacher pay. The office sets hourly rates, adds bonuses and deductions, and can set a fixed
monthly salary. It generates a draft payslip per teacher and month from the sessions the teacher taught,
issues it once the month is over (which freezes it and locks its sessions), and marks it paid, either
directly or into the teacher's in-app balance. Teachers read their own issued and paid payslips. They
can confirm receipt, and they can request withdrawals from their balance. Admins can do everything.
Staff can do what their access codes allow. Students and parents get no access.

## Concepts

| Model (`etqan.payroll.models`) | What it is |
|---|---|
| `TeacherRate` | Hourly rate (minor units) for a teacher. `course_id` null is the teacher's default rate. One per (teacher, course). |
| `StudentRate` | Hourly rate for one (teacher, student) pair, any course. Counts only while `student_teacher_rate` is on. |
| `PayAdjustment` | A bonus or deduction with a reason and `effective_on` date. It has either `amount_minor`, or (bonus only) `percent_bp` of the month's gross. `payslip` is set once an issued payslip uses it; after that it can't change. |
| `FixedSalary` | One per teacher: `monthly_minor` from `starts_on` (always the first of a month). |
| `PayrollSettings` | One row (pk 1) per academy: absent/excused student pay weights (bp), `at_disposal_pays`, `group_pay` (`per_student` / `per_class`), `report_deduction_bp`. |
| `Payslip` | Unique per (teacher, year, month). Number `PAY-000123`. Status `draft → issued → paid`. Holds totals (gross, bonuses, deductions, net), `missing_rate`, report/absence counters, `paid_to_balance` and `acknowledged_at`. |
| `PayslipLine` | One line on a payslip, with kind `session`, `fixed`, `adjustment` or `report`. Amounts are signed (deductions are negative). Session lines copy the session's kind, status, attendance, weight (`pay_bp`) and group key/role. |
| `PayslipCounter` | Single row that hands out payslip numbers. |
| `WithdrawalRequest` | Teacher request against their balance: `under_review → approved → paid`, or `rejected` / `cancelled`. |
| `BalanceLock` | One row per (teacher, currency). Every withdrawal write locks it first. |

Other rules:
- Money is in the teacher's `TeacherProfile.pay_currency`, which lives in `identity`. Every rate,
  adjustment and fixed salary is saved in that currency. A row left in an old currency does not count.
- Sessions and courses are plain ids. Payroll reads sessions only through `etqan.scheduling.services`.
- All dates (month bounds, "month over", `paid_on`) use the academy's calendar
  (`etqan/payroll/clock.py`, from `AcademySettings.timezone`).

## How it works

**Pay rule** (`services/rules.py:pay_rule`). A session pays when all of these hold:
- `status=completed`;
- teacher attendance is `present` or `not_set`;
- `scheduling.services.payroll_sessions` returns it, which requires `pays_teacher` on and not yet
  `payroll_locked`.

With `at_disposal_pays` on, `at_disposal` sessions pay too. The month is decided by the session's
`occurs_on`.

**Building a month** (`services/build.py:build`). This one function is used by generate, issue and the
projection. Steps:
1. **Rate:** the student rate if there is one, else the course rate, else the teacher's default rate
   (`rules.rate_for`). A session with no rate gets a line of 0 and sets `missing_rate`.
2. **Amount:** `round_half_up(rate × minutes × pay_bp, 60 × 10000)`, in integers only
   (`rules.session_amount`). The weight `pay_bp` is 100 % for an at-disposal session. Otherwise it is the
   absent or excused weight when the student was absent or excused (`rules.weight`).
3. **Per-class group pay** (`build.regroup`): within one group class (bundle + start + minutes), the
   lowest session id carries the pay at the class's highest weight. The other rows become `member` lines
   of 0.
4. **Fixed salary** (`build._fixed_month`): a counting fixed salary adds one `fixed` line and zeroes
   every session line.
5. **Gross** is the session lines plus the fixed line.
6. **Adjustments:** pending adjustments with `effective_on ≤ month end`, in the current currency. A
   percentage bonus is its share of gross. A share of 0 makes no line, and the adjustment stays pending.
7. **Report deductions:** each session line that owes a missing report (`scheduling.services.missing_reports`)
   loses `report_deduction_bp` of its amount. For a group class this is computed once on the carrier line.
8. **Totals:** `net = gross + bonuses − deductions`. Line descriptions are written in the academy's
   default language.

Settings and switches are read once per run through `services/settings.py:effective_settings`. While
`payroll_rules` is off, the defaults apply: 100 % weights, no at-disposal pay, per-student group pay, no
report share.

**Lifecycle** (`services/payslips.py`):
- `generate(year, month)`:
  - Holds the counter lock, then locks the month's payslips in id order.
  - Finds teachers with paying sessions, pending adjustments, or (active teachers) a counting fixed salary.
  - Creates or rebuilds their drafts and deletes drafts with nothing left.
  - Never touches issued or paid payslips.
  - Reports four lists: `missing_rate`, `other_currency` (adjustments), `unpaid_sessions` (sessions
    completed after the month was issued, payable only by a later adjustment) and `stale_fixed_salary`.
- `issue(payslip, by)`:
  - Allowed only for a draft whose month is over.
  - Locks the payslip, the teacher's pending adjustments and the month's unlocked sessions
    (`scheduling.hold_sessions`), then rebuilds from fresh data.
  - Refuses with 409 `payroll.not_allowed_in_status`, `month_not_over`, `missing_rate` or `negative_net`.
  - On success it marks the adjustments as used and calls `scheduling.lock_sessions` on the paid sessions.
- `mark_paid` / `pay_to_balance`: allowed only from `issued`. `paid_on` can't be in the future. Both go
  through `_pay`, the only code that makes a payslip paid. In the same transaction it posts a `salaries`
  expense through `finance.services.post_expense` (`services/salary_expenses.py:post_salary`). This happens
  only while `salary_expenses` is on and net ≠ 0. The post is idempotent by payslip id, and if it fails
  the payment rolls back.
- `acknowledge(payslip, by)`: the payslip's own teacher, once, only on a paid payslip
  (409 `payroll.already_acknowledged`).

**Rates and adjustments:**
- Rates can be edited at any time. Issued payslips keep the rates they copied.
- `rates.assign_rates` (bulk) writes one set of rates to several teachers who share one currency. It is
  all or nothing.
- An adjustment can be edited or deleted only while unused (409 `payroll.adjustment_used`).
- A percentage needs `incentives_deductions` on, and it must be a bonus.
- While `incentives_deductions` is off, percentage bonuses wait and stay unused.

**Balance** (`services/balances.py:balances_of`). The balance is derived: there is no ledger table.
Per currency:
- credits = net of the teacher's payslips paid to balance;
- `balance = credits − paid withdrawals`;
- `available = balance − (under_review + approved)`.

**Withdrawals** (`services/withdrawals.py`):
- Every write locks the `BalanceLock` first.
- Create is allowed only in a currency the teacher has a balance in, and only for an amount up to
  `available` (409 `payroll.insufficient_balance`). A teacher must be active to request for themselves.
- The office approves, rejects (a reason is required, and the teacher can read it), pays (`paid_on` falls
  between the request day and today), or cancels.
- The teacher can cancel their own request while it is under review.
- Paying a withdrawal never posts an expense.

**Projection** (`services/projections.py:project`). Read-only and current month only. For each teacher it
builds the month twice:
- "so far": the same as generate would build now;
- "projected": also prices `scheduled` sessions on the same teacher gate.

It gives one total per currency. It also gives an estimate in the academy's currency through
`finance.services.convert_estimate`, which needs `exchange_rates` on.

**Who sees what** (`etqan/payroll/scopes.py`):
- The office sees every payslip and withdrawal.
- A teacher sees their own issued and paid payslips (never drafts) and their own withdrawals.
- Anything out of scope returns 404.
- Teachers don't see `notes`, `issued_by` or `paid_by`.
- Money-moving writes refuse quick-login (impersonated) sessions (`NotImpersonating`).

## API

All paths are under `/api/v1/payroll/` (`etqan/payroll/api/urls.py`, mounted in `config/api_router.py`).
"Office" means admins, or staff holding the listed code.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET, POST | `/api/v1/payroll/rates/` | `payroll_rate.view_any` / `.create` | List rates (filters available); add a default or course rate |
| PATCH, DELETE | `/api/v1/payroll/rates/<id>/` | `payroll_rate.update` / `.delete` | Edit or remove a rate |
| POST | `/api/v1/payroll/rates/bulk/` | `payroll_rate.create` + `.update`; feature `bulk_teacher_rates` | Assign rates to several teachers |
| GET, POST | `/api/v1/payroll/student-rates/` | `payroll_rate.*`; feature `student_teacher_rate` | Per-student rates |
| PATCH, DELETE | `/api/v1/payroll/student-rates/<id>/` | same | Edit or remove |
| GET, PATCH | `/api/v1/payroll/settings/` | `payroll_settings.view` / `.update`; feature `payroll_rules` | Pay rules (`report_deduction_bp` only while `report_deductions` is on) |
| GET, POST | `/api/v1/payroll/adjustments/` | `payroll_adjustment.view_any` / `.create` | Bonuses and deductions (filters `teacher`, `used`) |
| PATCH, DELETE | `/api/v1/payroll/adjustments/<id>/` | `payroll_adjustment.update` / `.delete` | Only while unused |
| GET, POST | `/api/v1/payroll/fixed-salaries/` | `payroll_rate.*`; feature `fixed_teacher_salary` | Fixed monthly salaries |
| PATCH, DELETE | `/api/v1/payroll/fixed-salaries/<id>/` | same | Edit or remove |
| GET | `/api/v1/payroll/payslips/` | `payslip.view_any`, or a teacher (own issued and paid) | List (`year`, `month`, `teacher`, `status`). CSV export is office only. |
| POST | `/api/v1/payroll/payslips/generate/` | `payslip.create` | Generate drafts for `{year, month}` |
| GET | `/api/v1/payroll/payslips/projection/` | `payslip.view_any`; feature `salary_projections` | Current month projection (JSON or CSV) |
| GET | `/api/v1/payroll/payslips/<id>/` | `payslip.view`, or the teacher | Payslip with lines |
| POST | `/api/v1/payroll/payslips/<id>/issue/` | `payslip.update` | Issue |
| POST | `/api/v1/payroll/payslips/<id>/mark-paid/` | `payslip.update` | Mark paid (`paid_on`, `notes`) |
| POST | `/api/v1/payroll/payslips/<id>/pay-to-balance/` | `payslip.update`; feature `teacher_balance`; not impersonating | Pay into the balance |
| POST | `/api/v1/payroll/payslips/<id>/acknowledge/` | Teacher; feature `payslip_acknowledgement`; not impersonating | Confirm receipt |
| GET | `/api/v1/payroll/balances/` | `teacher_withdrawal.view_any` (`?teacher=`), or the teacher (own) | Balances per currency |
| GET, POST | `/api/v1/payroll/withdrawals/` | `teacher_withdrawal.view_any` / `.create`, or the teacher; feature `teacher_balance` | List or create requests |
| GET | `/api/v1/payroll/withdrawals/<id>/` | same | One request (the office also sees payout method and details) |
| POST | `/api/v1/payroll/withdrawals/<id>/approve/`, `reject/`, `pay/` | `teacher_withdrawal.update`; not impersonating | Office decisions |
| POST | `/api/v1/payroll/withdrawals/<id>/cancel/` | Office (`.update`) or the requesting teacher | Cancel |

## Dashboard

Feature folder: `dashboard/src/features/payroll/`. Strings are in `locales/<lng>/payroll.json`.

| Route | Who | Component |
|---|---|---|
| `/payroll` → redirects to `/payroll/payslips` | office (`requireOffice`) | `payroll.tsx`, `payroll.index.tsx` |
| `/payroll/payslips`, `/payroll/payslips/$payslipId` | `payslip.view_any` / `.view` | `PayslipsList`, `PayslipPage` (generate, issue, pay, pay to balance) |
| `/payroll/rates` | `payroll_rate.view_any` | `RatesPage`, which also shows `FixedSalaryRow`, `BulkRatesDialog` and `StudentRates` when their features are on |
| `/payroll/adjustments` | `payroll_adjustment.view_any` | `AdjustmentsList`, `AdjustmentDialog` |
| `/payroll/settings` | `payroll_settings.view`; `payroll_rules` | `SettingsPage` |
| `/payroll/withdrawals` | `teacher_withdrawal.view_any`; `teacher_balance` | `WithdrawalsPage`, `WithdrawalActions` |
| `/payroll/projections` | `payslip.view_any`; `salary_projections` | `ProjectionsPage` (opened from a button on the payslip list) |
| `/teaching/payslips`, `/teaching/payslips/$payslipId` | teacher | `TeacherPayslips`, `PayslipPage admin={false}`, `ConfirmReceipt` |
| `/teaching/balance` | teacher; `teacher_balance` | `MyBalance`, `WithdrawalDialog`, `CancelWithdrawal` |
| `/payslips/$payslipId/print` (`_print` layout) | readers | `PayslipPrint` |

## Background jobs

None. Generating, issuing and paying are all manual actions. Payroll defines no Celery task.

## Configuration

Feature switches (`etqan/platform/features.py`, group "money", all off by default). The core flow (rates,
fixed-amount adjustments, payslips) has no switch.

| Switch | Effect |
|---|---|
| `student_teacher_rate` | Per-student rates count and can be edited |
| `bulk_teacher_rates` | Bulk rate assignment |
| `payroll_rules` | `PayrollSettings` is applied (otherwise the defaults) |
| `report_deductions` | Applies `report_deduction_bp`. Requires `session_reports` and `payroll_rules`. |
| `incentives_deductions` | Percentage bonuses only |
| `fixed_teacher_salary` | Fixed salaries |
| `teacher_balance` | Pay to balance, balances, withdrawals |
| `payslip_acknowledgement` | Teacher confirms receipt |
| `salary_expenses` | A paid payslip posts a finance expense (even while `expenses` is off) |
| `salary_projections` | The projection screen |

Access resources (`etqan/access/registry.py`): `payroll_rate`, `payroll_adjustment`, `payslip`,
`payroll_settings`, `teacher_withdrawal`. Teacher fields used: `pay_currency`, `payout_method`,
`payout_details` (`etqan/identity/models.py`). Demo data: `etqan/tenants/seeds/b4.py`.

## Code map

- `backend/etqan/payroll/models.py`: all models.
- `backend/etqan/payroll/services/__init__.py`: the public API. Other apps import only this.
- `backend/etqan/payroll/services/build.py`, `rules.py`: the arithmetic and the pay rule.
- `backend/etqan/payroll/services/payslips.py`: generate, issue, pay, acknowledge.
- `backend/etqan/payroll/services/numbering.py`, `settings.py`, `rates.py`, `student_rates.py`,
  `adjustments.py`, `fixed_salaries.py`: the remaining services.
- `backend/etqan/payroll/services/balances.py`, `withdrawals.py`, `salary_expenses.py`, `projections.py`:
  balance, withdrawals, expense posting, projection.
- `backend/etqan/payroll/clock.py`, `scopes.py`: the academy calendar and row scoping.
- `backend/etqan/payroll/api/`: views, serializers, payloads (including CSV columns).
- `backend/etqan/scheduling/services/paylock.py`: `payroll_sessions`, `hold_sessions`, `lock_sessions`.
- `dashboard/src/features/payroll/`, plus the `dashboard/src/routes/_authed/payroll.*.tsx` and
  `teaching.{payslips,balance}*.tsx` routes.

## Design history

- [Plan 7 — Teacher payroll](../superpowers/specs/2026-09-26-payroll-design.md): rates, adjustments,
  payslips, the session lock. Says "admins". Plan 12 later opened it to staff by code.
- [Phase B4 — Payroll depth](../superpowers/specs/2026-10-08-b4-payroll-depth-design.md): phase rules
  B4-1…B4-10. It also holds the B4a slice spec (per-student and bulk rates, pay settings, group pay,
  copied line columns).
- [B4b — Incentives, report deductions, fixed salary](../superpowers/specs/2026-10-08-b4b-incentives-reports-fixed-design.md).
- [B4c — Balance, withdrawals, acknowledgement, salary expenses](../superpowers/specs/2026-10-08-b4c-balance-payouts-design.md).
- [B4d — Salary projections](../superpowers/specs/2026-10-08-b4d-salary-projections-design.md): current
  month only.
- Plans: [plan 7](../superpowers/plans/2026-09-26-plan-7-payroll.md),
  [plan 46](../superpowers/plans/2026-10-08-plan-46-pay-rules.md),
  [plan 53](../superpowers/plans/2026-10-08-plan-53-balance-payouts.md),
  [plan 54](../superpowers/plans/2026-10-08-plan-54-incentives-reports-fixed.md),
  [plan 55](../superpowers/plans/2026-10-08-plan-55-salary-projections.md).
