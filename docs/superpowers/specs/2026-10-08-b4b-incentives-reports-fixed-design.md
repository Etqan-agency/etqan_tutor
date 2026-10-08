# Slice B4b — Percentage incentives, report deductions, fixed salary — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); review findings
applied 2026-10-08.
**Phase spec:** `docs/superpowers/specs/2026-10-08-b4-payroll-depth-design.md` (§3 row B4b, B4-1…B4-10).
**Requires:** B4a (Plan 46). It builds on B4a's:
- `PaySettings`, `effective_settings` and `build(…, settings=)`;
- `Line` with its copied columns;
- `regroup` and `paying_sessions`;
- the payroll settings page.

**Evidence:**
- P1 PAY-002: inputs "reports sent / not sent", "absence sessions", "total deductions", "total incentives".
- P1 PAY-005: an incentive is a fixed amount or a percentage.
- P1 PAY-008, BR-33: missing reports produce a deduction.
- P1 PAY-009: the fixed-salary flag.
- TH §2.6: the "Report deductions" settings tab exists, but its fields were not captured.
- P1 §19: payroll arithmetic is a CRITICAL unknown.

Anything the audits do not show is marked `[assumed]`.

## 1. Goal

Three switches, each off by default:
1. **Percentage incentives** (`incentives_deductions`). A bonus can be a percentage of the month's pay.
2. **Report deductions** (`report_deductions`). A paid session still without a report loses a share of its pay.
3. **Fixed salary** (`fixed_teacher_salary`). A teacher is paid a fixed monthly amount instead of per session.

Payslips also gain counters for *reports sent*, *reports not sent* and *teacher absences*.

Nothing changes while the switches are off (B4-2). This holds even when an academy stored one of these
switches as true while it was unbuilt (FT-2). The switch then takes effect, but its defaults are neutral: the
bp is 0 and no rows exist.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| I-1 | **A percentage incentive is a `PayAdjustment`** of kind `bonus`, with `percent_bp` from 1 to 10000 and `amount_minor` null. A fixed adjustment keeps `amount_minor > 0` and `percent_bp` null. A deduction is always fixed. A check constraint enforces exactly one form. The migration makes `amount_minor` nullable (`blank=True`), adds `percent_bp` (`blank=True`, null) and replaces the amount constraint. Existing rows already satisfy the new constraint, so no data is rewritten. `currency` stays the teacher's `pay_currency`, so Plan 7's currency rules apply. | P1 PAY-005 ("type: fixed amount / percentage"); P1 PAY-004 (deductions: amount) |
| I-2 | **The base of a percentage is the payslip's gross**: the session lines after B4a's weights, plus the fixed-salary line when one counts. Report deductions and other adjustments are not part of it. Amount = `round_half_up(gross × percent_bp, 10000)`. The description is "Bonus — {p} % — {reason}", where `{p}` is `percent_bp / 100` without trailing zeros (1250 → "12.5"). The line stores its amount, so an issued payslip is frozen (P7-4). **A percentage line of 0 is not written, and its adjustment stays pending**, so it is never used up for nothing. A percentage left pending applies to the gross of the month that finally uses it. | [assumed] base (amends the phase §3 wording "gross session pay"); B4-4 rounding |
| I-3 | **While `incentives_deductions` is off:** a request body that sets `percent_bp` to a value is 400 on `percent_bp`. An existing percentage row can still have its reason and date edited, and can be deleted. Generate's discovery, its `other_currency` warning and `build` all leave percentage rows out, so they stay pending and are not marked used at issue. Fixed bonuses and deductions are Plan 7's and stay always on. | PO-5; FT-4 |
| R-1 | **Report deduction setting.** `PayrollSettings` gains `report_deduction_bp`, from 0 to 10000, default 0, shown on B4a's settings page. `PaySettings` gains it; it is 0 unless `report_deductions` is on. The registry line `report_deductions` is flipped in place to built, off, with `requires=("session_reports", "payroll_rules")`, because the setting lives on `payroll_rules`'s page. While the switch is off the settings form does not send the field, and a PATCH that carries it is 400 on the field. | TH §2.6 · [assumed] percentage form (phase §3) |
| R-2 | **Which sessions owe a report** is scheduling's rule, `scheduling.services.missing_reports(now=…)`: completed, student present, teacher not absent, no report, ended more than 24 hours ago. `build` intersects it with its own session lines in one query: `missing_reports(now=clock.now()).filter(pk__in=line_session_ids)`. Payroll never restates the rule. See the R-2 detail after this table for what the 24-hour window and later report writes do. | P1 FLOW-005; `scheduling/services/reports.py`; spec Plan 7 §4.3, P7-4 |
| R-3 | **Deduction lines.** See the R-3 detail after this table. | [assumed]; spec Plan 7 §4.1 totals |
| R-4 | **Counters stored on the payslip at build**, as nullable small ints. All are null on payslips built before B4b. See the R-4 detail after this table for each definition. | P1 PAY-002 inputs; TH §2.6 optional columns |
| F-1 | **Fixed salary** (`FixedSalary`): one row per teacher, with `monthly_minor > 0`, `currency` (the teacher's `pay_currency` when saved) and `starts_on` (the first day of a month; default the current month on the academy's calendar), plus `created_at` and `updated_at`. It **counts for a month** when `fixed_teacher_salary` is on, its currency is the teacher's current `pay_currency`, and the month is on or after `starts_on`. A row with a stale currency does not count, and generate names such teachers in a new `GenerateResult.stale_fixed_salary`. | P1 PAY-009 · [assumed] model and start month |
| F-2 | **A month with a counting fixed salary.** `build` writes a `fixed` line first ("Fixed monthly salary", in the academy language) for the full amount, with no pro-rating (phase §3). Every paying session is still listed after it and locked at issue, with amount 0, `rate_minor` null and `pay_bp` kept. Such lines never set `missing_rate`. The line order is fixed → sessions → adjustments → reports. | [assumed] (phase §3) |
| F-3 | **Generate includes active fixed-salary teachers.** Each teacher returned by `identity_services.active_teachers()` whose fixed salary counts for the month gets a payslip, even with no other activity. "Active" means active at generate time [assumed]. An inactive teacher gets a payslip only through other activity, and `build` then still adds their fixed line if it counts. | [assumed] |
| F-4 | **Late rows of a fixed-salary month** (B4a A-6 late-row rule) are not reported in `unpaid_sessions` while the teacher's fixed salary counts for that month: the fixed salary already covers them. | B4a A-6 reasoning; D47 |
| F-5 | **Access.** Fixed salaries use the `payroll_rate.*` codes. The route is 404 while `fixed_teacher_salary` is off. Active and inactive teachers are allowed. Teachers, students and parents get 403. | spec Plan 7 §4.7 |
| S-1 | **Switches are read once.** `PaySettings` gains `percentages: bool` (`incentives_deductions` on) and `fixed_salary: bool` (`fixed_teacher_salary` on), filled by `effective_settings()` like B4a's `student_rates`. Generate and issue pass the same snapshot to discovery and to `build`. | B4a A-3 |

**R-2 detail — the 24-hour window and later report writes:**
- A session that ends on the month's last evening is not deducted at a generate on the 1st, but a later
  issue deducts it.
- If issue runs within 24 hours of that session's end, the session is never deducted.
- A report written before issue removes the deduction, because issue rebuilds from fresh data.
- A report written after issue is not refunded (P7-4).

**R-3 detail — deduction lines.** Each session line in R-2's set that carries an amount gets a `report` line.
- **Placement:** after the adjustment lines.
- **Amount:** `-round_half_up(line.amount_minor × report_deduction_bp, 10000)`.
- **Line fields:** it carries the session's `session_id`, and its description is "Missing report — {session
  description}".
- **Per class** (B4a A-6), there is one line per class. Its amount is
  `-round_half_up(carrier_amount × bp × missing_rows, 10000 × class_rows)`, where `missing_rows` counts the
  class's rows in the set. It carries the carrier's `session_id`, and its description is "Missing reports
  ({missing} of {rows}) — {carrier description}".
- **Zero amounts:** a deduction of 0 makes no line.
- **Totals:** report lines count in `deductions_minor`, and net = gross + bonuses − deductions.
- **Fixed salary:** session lines of a fixed-salary month carry 0, so they get no report deduction.

**R-4 detail — the counters:**
- `reports_sent` is the payslip's session lines (member lines included) whose session is completed with the
  student present, the teacher `present` or `not_set`, and a report. It is read through the field path
  `report__isnull=False` on `payroll_sessions` (B4-1).
- `reports_missing` is the payslip's session lines in R-2's set (member lines included).
- Sent + missing can be less than the reports owed, because of the 24-hour window. This is intended.
- Both report counters are null while `session_reports` is off, because the academy does not use reports.
- `teacher_absences` is always filled. It counts the teacher's month rows from `payroll_sessions` with status
  `completed` or `at_disposal` and teacher attendance `absent` or `excused`. "Excused" means the teacher's
  (phase §3). Rows with `pays_teacher` off are not in `payroll_sessions`, so they are not counted.

## 3. Data

| Model | Change |
|---|---|
| `PayAdjustment` | `amount_minor` nullable, `blank=True`. `percent_bp` small int, null, `blank=True`. Check constraint: `(amount_minor > 0 AND percent_bp IS NULL) OR (amount_minor IS NULL AND percent_bp BETWEEN 1 AND 10000 AND kind = 'bonus')`. |
| `PayrollSettings` | `report_deduction_bp` (0–10000, default 0, check constraint). |
| `FixedSalary` (new) | `teacher` (OneToOne `TeacherProfile`, PROTECT), `monthly_minor` (> 0), `currency`, `starts_on`, `created_at`, `updated_at`. |
| `Payslip` | `reports_sent`, `reports_missing` and `teacher_absences`: positive small int, null. |
| `PayslipLine.Kind` | gains `report` and `fixed`. |

There is one migration, numbered next after trunk's payroll leaf at build time (`0003` after B4a, or `0004` if
B4c merged first). It adds columns and tables and alters one nullability and one constraint. It rewrites no
data.

## 4. Behaviour

### 4.1 Build order

1. Session lines (B4a), then `regroup`.
2. If the fixed salary counts (F-1), put the `fixed` line first and zero the session lines (F-2).
3. Gross = session lines + fixed line.
4. Adjustment lines:
   - a fixed bonus or deduction, as today;
   - a percentage bonus, per I-2. A percentage line of 0 is skipped, and its adjustment stays pending.
5. Report lines (R-3).
6. Totals:
   - bonuses = the positive adjustment lines;
   - deductions = the negative adjustment lines + the report lines;
   - net = gross + bonuses − deductions.
7. `missing_rate` = any **session** line with no rate, except `member` lines and every session line of a month
   whose fixed salary counts. Adjustment, fixed and report lines never count.
8. The counters (R-4).

### 4.2 Adjustment rules

- `create_adjustment` and `update_adjustment` gain `percent_bp` (additive).
- `update_adjustment` uses an `UNSET` sentinel for a field that was not sent, so `None` means "clear". This
  replaces today's "None means unchanged" in its body, and its signature stays additive.
- The serializers allow null for `amount_minor` and `percent_bp`.
- **The row after the change** must have exactly one of the two fields set, otherwise 400 on `amount_minor`.
  For example, `{percent_bp: 1000, amount_minor: null}` turns a fixed bonus into a 10 % one.
- A percentage needs kind `bonus` (400 on `kind`), and needs `incentives_deductions` on (I-3).
- The pending and used rules are unchanged (`payroll.adjustment_used`).

### 4.3 Fixed salary

- `create_fixed_salary(teacher_id, monthly_minor, starts_on=None)`:
  - It is created in the teacher's currency.
  - A teacher who already has one gets 409 `payroll.fixed_salary_exists`, including after a concurrent
    insert.
  - `starts_on` is normalised to the first of its month.
- `update_fixed_salary(row, *, monthly_minor=UNSET, starts_on=UNSET)` saves in the current currency.
- `delete_fixed_salary(row)` deletes the row. Issued payslips keep their copied lines.
- Each locks its row, as rates do.

### 4.4 Generate and issue

- Discovery adds F-3's teachers.
- `GenerateResult` gains `stale_fixed_salary`.
- Late rows follow F-4.
- Issue rebuilds and refuses as today. The negative-net refusal now also covers report deductions.

## 5. API (`/api/v1/payroll/`)

| Route | Methods | Notes |
|---|---|---|
| `adjustments/`, `adjustments/<id>/` | as today | The body and the row gain `percent_bp`. `amount_minor` may be null in both. |
| `fixed-salaries/` | GET, POST | Feature `fixed_teacher_salary`. Codes `payroll_rate.view_any` and `payroll_rate.create`. Not paged. Filter `teacher`. POST `{teacher, monthly_minor, starts_on?}` creates only (409 if one exists). Row: `{id, teacher, monthly_minor, currency, starts_on, current, created_at, updated_at}`. |
| `fixed-salaries/<id>/` | PATCH, DELETE | Codes `payroll_rate.update` and `payroll_rate.delete`. |
| `settings/` | GET, PATCH | Gains `report_deduction_bp` (R-1). |
| `payslips/generate/` | POST | The result gains `stale_fixed_salary` (people). |
| `payslips/`, `payslips/<id>/` | GET | Rows gain `reports_sent`, `reports_missing`, `teacher_absences` and `report_deductions_minor` (the sum of the report lines, a subquery). The CSV gains these four as its last columns (before B4c's two if B4c merged first; whichever slice comes second appends after the first). |

## 6. Dashboard

- **Adjustment dialog.** With `incentives_deductions` on and kind Bonus, a "Fixed amount / Percentage" choice
  appears. A percentage is entered as a % with up to two decimals and sent as bp. The list shows "10 %" for a
  percentage bonus, including a pending one while the switch is off.
- **Settings page.** A "Missing report deduction (%)" field appears while `report_deductions` is on.
- **Rates page.** While `fixed_teacher_salary` is on, a "Fixed monthly salary" row on each teacher card (amount
  and start month; set, edit, remove), with a note that sessions are still listed but not paid per hour.
- **`PayslipBody`** is shared by the office page, the teacher's payslip page and print.
  - It renders `fixed` lines first.
  - It shows a "Report deductions" section for `report` lines.
  - It shows "—" in the rate cell of a fixed-salary month's session lines, as for member lines.
  - It shows the three counters under the totals, each hidden when null.
- **Payslips list.** The counts toggle (B4a) adds the three counters.
- **Generate result.** It names teachers with a stale fixed salary.
- **Strings.** All strings go in `payroll.json` and `errors.json` (`payroll.fixed_salary_exists`), in en and ar.

## 7. Seeds

`seed_b4` gains a demo percentage bonus: 5 % for Ustadh Bilal, effective last month. It is created only when no
`PayAdjustment` with `percent_bp` exists. While the switch is off it stays pending, and the dashboard shows it
as "5 %". No fixed salary is seeded.

## 8. Testing

- **Regression (B4-2).** With the three switches off, a fixture month must build the same lines and totals as
  B4a. The month contains:
  - a missing report;
  - a stored `report_deduction_bp` of 5000;
  - a stored fixed salary;
  - a pending percentage bonus written straight to the table.

  The same holds with the switches stored true before the slice (neutral defaults).
- **Percentages.**
  - The base and the rounding, including weighted session lines and a fixed salary.
  - A zero gross leaves the adjustment pending.
  - Use at issue.
  - Edit (`UNSET` versus a null that clears; switching form).
  - The row-after-patch rule.
  - Refusals while the switch is off and for a deduction; reason edits still allowed while off.
  - The database constraint.
- **Report deductions.**
  - One line per missing report.
  - None once the report is written before issue.
  - The 24-hour window at month end.
  - Per class: proportional, one line.
  - A negative net is refused at issue.
- **Counters.**
  - `reports_sent` and `reports_missing`, null while `session_reports` is off.
  - `teacher_absences`.
  - Null on old payslips.
- **Fixed salary.**
  - A payslip for an active teacher with no sessions.
  - `starts_on` respected.
  - Sessions listed at 0 and locked.
  - No missing rate.
  - A stale currency is reported and not counted.
  - An inactive teacher gets no payslip without activity.
  - Late rows are not reported.
  - Duplicate create is 409.
- **API.** Switches answer 404 or 400; the role matrix; isolation.
- **Dashboard.** Each new control, and `PayslipBody` with fixed and report lines, in both languages.
- **E2E** (`e2e/b4-report-deductions.spec.ts`). The admin turns on `payroll_rules`, `session_reports`,
  `report_deductions` and `incentives_deductions`, and sets 50 %. Through the API, a fresh teacher gets:
  - a rate;
  - a session last month with the student present and no report;
  - a 10 % bonus.

  Generating shows a "Missing report" line at half the session's pay, and a bonus line of 10 % of the gross.
