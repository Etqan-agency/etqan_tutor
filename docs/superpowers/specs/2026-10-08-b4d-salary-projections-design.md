# Slice B4d — Salary projections — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); review findings applied
2026-10-08. The review's simpler design is adopted: current month only, and projection is one term in the pay
rule.
**Phase spec:** `docs/superpowers/specs/2026-10-08-b4-payroll-depth-design.md` (§3 row B4d, B4-1…B4-10).
**Requires:** B4b (Plan 54), and through it B4a (Plan 46). It reads their `build`, `pay_rule`, `PaySettings`,
discovery helpers, fixed salaries and percentage adjustments. It does not need B4c.

**Evidence:**
- P1 PAY-001: the salary board header action "توقعات الرواتب" (salary projections).
- P1 EXP-005: a forward-looking payroll estimate. The action is confirmed, but the screen was never reached,
  and the routes the audit guessed returned 404.
- TH §2.6.
- Ledger D24/D31: cross-currency figures go only through `finance.services.convert_estimate`.

Everything about the screen is `[assumed]`.

## 1. Goal

One read-only screen answers: "what will each teacher be paid for this month if every scheduled session takes
place?" It shows each teacher's pay so far beside the projection, per-currency totals, and an estimated total
in the academy currency while exchange rates are on. The switch `salary_projections` is off by default.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| P-1 | **The current month only**, on the academy's calendar (`payroll.clock.today()`). The route takes no month. A month that has not ended has no issued payslip (P7-5), so every one of its rows is unlocked. Future months are not projected. Sessions exist only up to the generation horizon, and pending adjustments would be counted in several months. | [assumed]; review |
| P-2 | **Pay so far** is the net of `build(teacher, year, month, settings=pay)`: what generate would build now. A counting fixed salary and every pending adjustment are fully part of it from day 1. | B4-5 |
| P-3 | **Projection mode is one extra term in the paying rule.** `rules.pay_rule(pay, *, projected=False)` adds `Q(status="scheduled", teacher_attendance__in=("present", "not_set"))` when `projected` is true. `paying_sessions` and `build` pass the flag through as an additive keyword-only `projected: bool = False`. Generate, issue and `_unpaid_rows` never pass it. See the P-3 detail after this table for what follows from it. | B4-6 (teacher gate) · [assumed] |
| P-4 | **Who is listed.** Every teacher found by Plan 46's `_paying_teacher_ids` and Plan 54's pending and fixed-salary discovery, plus every teacher with a row matching the projected term. All use the same `pay` snapshot. A teacher whose two builds both have no line is dropped (for example, one found only through an adjustment in another currency). The list is ordered by teacher name. | [assumed] |
| P-5 | **A row** holds the teacher `{id, full_name}`, `currency`, `paid_so_far_minor`, `projected_minor`, `scheduled_sessions`, `scheduled_minutes` and `missing_rate`. `missing_rate` comes from the projected build. `scheduled_*` are counted from the projected build's session lines that are `scheduled` and are not `member` lines (A-8's rule). | PAY-001 columns · [assumed] |
| P-6 | **Totals are per currency** (B4-3). Each currency's total is the sum of `paid_so_far_minor` and the sum of `projected_minor`. **The estimate covers the projected totals only**, through `finance.services.convert_estimate` (D31). See the P-6 detail after this table for each estimate state. | ledger D24, D31; B4-3 |
| P-7 | **Cost.** There are two builds per listed teacher, read-only and with no locks. The builds skip B4b's counters (`build(…, counters=False)`, additive). Teacher profiles load in one call. A query-count test pins a fixed number of queries per teacher. The JSON and the CSV each run `project()` once. The two builds are not one snapshot under READ COMMITTED; a projection is an estimate. | Plan 7 generate precedent; review |
| P-8 | **Access.** The view uses `HasCode` only (`{"GET": "payslip.view_any"}`), not `READERS`, plus the feature gate `salary_projections` (404 while off). Teachers, students and parents get 403, for the JSON and the CSV. | spec Plan 7 §4.7; B4-9 |

**P-3 detail — what follows from the projected term:**
- A scheduled row's student attendance is always `not_set`, because a student mark completes the session. So
  `rules.weight` gives 10000.
- Rates, `regroup`, fixed-salary zeroing, the percentage base and `missing_rate` all apply unchanged.
- A scheduled row whose teacher is already marked absent or excused is not projected, because the B4-6 gate
  still holds.
- Report deductions are never projected: `missing_reports` returns only completed sessions.
- Past scheduled rows of the month that are still unmarked are projected like future ones.
- Under per-class pay with student rates on, a scheduled row with a lower id can become a class's carrier, so
  projected may be below pay so far. The page says so.

**P-6 detail — the estimate:**
- `exchange_rates` off: `convert_estimate` returns None, and no estimate is shown.
- A rate is missing: the amount is null and the missing currencies are named.
- Every total is 0: the line is hidden.
- Negative amounts are rendered as negative.

## 3. Data

There is no new model and no migration. The registry gains `salary_projections`: built, off, group `money`,
`requires=()`, under the B4 marker.

## 4. Behaviour

`payroll.services.project() -> Projection(year, month, rows: list[ProjectionRow], totals:
list[CurrencyTotal(currency, paid_so_far_minor, projected_minor)], estimate: Estimate | None)`.

It reads `effective_settings()` once and the month from `clock.today()`. It then runs discovery (P-4), then the
two builds per teacher.

## 5. API (`/api/v1/payroll/`)

`payslips/projection/` is registered before `payslips/<int:pk>/`.

| Route | Methods | Notes |
|---|---|---|
| `payslips/projection/` | GET | Feature `salary_projections`. Code `payslip.view_any` (`HasCode` only). Returns `{year, month, rows, totals, estimate: {currency, amount_minor, missing, as_of} \| null}`. `?format=csv` gives the rows through `CSVExportMixin`, with columns teacher, currency, scheduled_sessions, scheduled_minutes, paid_so_far_minor, projected_minor, missing_rate. |

## 6. Dashboard

- **Page.** "Salary projections" at `/payroll/projections`. There is a nav item under Payroll and a header
  button on the payslips page, both while `salary_projections` is on. The heading names the server's
  `{year, month}`, and there is no month picker.
- **Table.** Teacher, scheduled sessions, scheduled hours, paid so far and projected, each in its row's
  currency, with a "missing rate" badge.
- **Totals.** Per-currency totals follow, then the estimate line ("≈ {amount} {currency}, estimate at today's
  rates" or the missing currencies) when shown.
- **Explanation.** One line: "Scheduled sessions are counted as if they take place with the student present.
  Report deductions are not projected. With per-class pay, the projection can be below the pay so far."
- **Export.** CSV.
- **Throughout:** both languages, RTL, phone width, semantic tokens, empty and error states.

## 7. Testing

- **Pay so far vs projected.**
  - Completed and scheduled rows.
  - Weights apply to completed rows only.
  - A scheduled row with the teacher marked absent is not projected.
  - An unmarked past scheduled row is projected.
  - A scheduled group class under per-class pay is counted once.
  - Per class with a lower-id scheduled row can give projected < paid so far.
  - A fixed-salary teacher has pay so far = projected = fixed + adjustments.
  - A percentage bonus scales with the projected gross.
  - A missing rate is flagged.
  - With no fixed salary and no pending adjustment, a teacher with only scheduled rows has pay so far 0.
- **Counts.** `scheduled_*` exclude member lines.
- **Discovery.** A teacher with empty builds is dropped.
- **Read-only.** With the settings row present, the captured SQL has no `FOR UPDATE`, `INSERT`, `UPDATE` or
  `SAVEPOINT`.
- **Query count.** A fixed number of queries per teacher.
- **Totals and estimate.**
  - Totals per currency.
  - The estimate is null while `exchange_rates` is off, converted while it is on, and null with the currency
    named when a rate is missing.
  - The line is hidden when every total is 0.
- **API.**
  - 404 while the switch is off.
  - Office only: 403 for a teacher on the JSON and the CSV.
  - The CSV columns.
  - Isolation.
- **Regression (B4-2).** `build(…, projected=False)` equals B4b's build.
- **Dashboard.** The page in both languages and the estimate states.
- **E2E** (`e2e/b4-projections.spec.ts`). With `salary_projections` on, the test creates through the API a
  fresh teacher with a rate and an unmarked extra session on the 1st of the current month (academy calendar).
  That teacher appears with projected > pay so far = 0.
