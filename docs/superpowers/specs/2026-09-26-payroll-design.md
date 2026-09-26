# Plan 7 — Teacher Payroll — Design

**Date:** 2026-09-26
**Status:** Approved in brainstorming (sections 1–3), pending written-spec review.
**Phase:** B0, milestone 7 of the parity roadmap (`2026-09-24-parity-roadmap-design.md`).
**Builds on:**
- v1 spec §4.8 and §5.5 (`2026-09-23-etqan-tutor-v1-design.md`);
- Plan 5 (sessions and attendance; `2026-09-25-sessions-attendance-design.md`), which defers the payroll lock to here;
- Plan 6 (billing; `2026-09-25-billing-design.md`), whose counter numbering, print layout and conventions this reuses;
- Plan 3 (`TeacherProfile.pay_currency`, role permissions).

**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §2.6 (PAY-001) and `docs/PHASE_1_SYSTEM_AUDIT.md` (PAY-002 inputs, PAY-003 per-course rates, PAY-004 deductions, PAY-005 incentives, PAY-006 salary receipts, BR-34 pay in the teacher's own currency). Roadmap rule R4 applies.

## 1. Goal

Admins pay teachers monthly for the sessions they taught:
- Rates are set per teacher (a default, plus per course), in the teacher's own currency.
- Bonuses and deductions are recorded with a reason.
- For any month, draft payslips are generated from completed sessions and pending adjustments.
- Once the month has ended, a payslip is issued. That freezes it and locks its sessions against changes. It is then marked paid.

Teachers see and print their own issued and paid payslips.

## 2. Decisions

| # | Decision |
|---|---|
| P7-1 | A new tenant app, `etqan.payroll`, owns `TeacherRate`, `PayAdjustment`, `Payslip` and `PayslipLine`. It reads sessions only through `etqan.scheduling`'s services. **Scheduling owns the lock:** `Session.payroll_locked` is set through a scheduling service, and scheduling's own rules enforce it. Scheduling never imports payroll. |
| P7-2 | **Pay rule (owner decision):** a session pays when it is `completed` and its `teacher_attendance` is `present` or `not_set`, **whatever the student's attendance**. A teacher who is `absent` or `excused` is not paid for it. There are no academy switches. |
| P7-3 | Every payslip, rate and adjustment is in the teacher's `pay_currency`. Totals are never summed across currencies. |
| P7-4 | One payslip per teacher per month. Payslip lines copy their values, so an issued payslip never changes. Corrections are adjustments on a later month (v1 §4.8). |
| P7-5 | A month's payslip can be issued only after the month has ended (academy calendar), so no session of that month is left out. |
| P7-6 | Out of scope, all phase B4: percentage incentives, per-student rates, fixed-salary mode, teacher balance and withdrawals, report-based deductions, receipt acknowledgement, and posting salaries to expenses. |

## 3. Data

### 3.1 Session (existing, `etqan.scheduling`)

New field: `payroll_locked`, bool, default `false`. Only scheduling's `lock_sessions(ids)` service sets it.

### 3.2 TeacherRate (new, `etqan.payroll`)

| Field | Notes |
|---|---|
| `teacher` | → `TeacherProfile` |
| `course_id` | nullable reference to a `catalogue.Course` (a plain id, validated through catalogue's services); null means the teacher's default rate |
| `hourly_rate_minor` | ≥ 0 |
| `currency` | set to the teacher's `pay_currency` when saved |
| `created_at`, `updated_at` | |

It is unique on (teacher, course), with at most one default per teacher.

### 3.3 PayAdjustment (new)

| Field | Notes |
|---|---|
| `teacher` | → `TeacherProfile` |
| `kind` | `bonus · deduction` |
| `amount_minor` | > 0 |
| `currency` | set to the teacher's `pay_currency` when saved |
| `effective_on` | date |
| `reason` | required text |
| `payslip` | nullable → Payslip; set when an issued payslip uses it |
| `created_by`, `created_at` | |

### 3.4 Payslip (new)

| Field | Notes |
|---|---|
| `number` | `PAY-000123`: unique per academy, from a locked counter row (as for invoices) |
| `teacher` | → `TeacherProfile` |
| `year`, `month` | unique together with `teacher` |
| `status` | `draft · issued · paid` |
| `currency` | the teacher's `pay_currency` when generated |
| `gross_minor`, `bonuses_minor`, `deductions_minor`, `net_minor` | net = gross + bonuses − deductions |
| `missing_rate` | bool |
| `issued_at`, `issued_by`, `paid_on`, `paid_by` | |
| `notes` | admin-only |
| `created_at`, `updated_at` | |

### 3.5 PayslipLine (new)

| Field | Notes |
|---|---|
| `payslip` | → Payslip |
| `kind` | `session · adjustment` |
| `session_id` | plain id, for session lines |
| `adjustment` | → PayAdjustment, for adjustment lines |
| `description` | copied text: date, course, student for a session; kind and reason for an adjustment |
| `minutes`, `rate_minor` | session lines |
| `amount_minor` | signed: a deduction is negative |

## 4. Behaviour

### 4.1 Building a teacher's month

For teacher T and month M (the academy's calendar):

**Session lines.** T's sessions with `occurs_on` in M that pass P7-2 and are not already `payroll_locked` by another payslip, ordered by `starts_at`.
- **Rate:** T's rate for the session's course, else T's default rate. Only rates in T's current `pay_currency` count.
- **Amount:** `round_half_up(rate × minutes / 60)` in integer minor units.
- **No rate:** the line's amount is 0 and the payslip's `missing_rate` is true.

**Adjustment lines.** T's adjustments with no `payslip`, `effective_on` ≤ the last day of M, and currency equal to T's `pay_currency`. Bonuses add; deductions subtract. Adjustments in another currency are left out and reported as a warning.

**Totals:**
- gross = the sum of the session lines;
- bonuses and deductions are summed separately;
- net = gross + bonuses − deductions.

### 4.2 Generate (admin)

`generate(year, month)` runs for every active or inactive teacher with at least one paying session or pending adjustment for M:
- it creates a `draft` payslip, or replaces the lines and totals of the existing draft;
- `issued` and `paid` payslips for M are never touched;
- drafts for M whose teacher now has no activity are deleted.

It returns `{created, replaced, removed, missing_rate: [teacher ids]}`. A new payslip takes its number when first created, and replacing a draft keeps its number.

### 4.3 Issue (admin)

Inside one transaction, with the payslip row locked:
1. The payslip must be `draft`; otherwise 409 `payroll.not_allowed_in_status`.
2. M must have ended in the academy's calendar; otherwise 409 `payroll.month_not_over`.
3. The draft is rebuilt from fresh data (§4.1), so late attendance changes are included.
4. A missing rate gives 409 `payroll.missing_rate`, and a negative net gives 409 `payroll.negative_net`.
5. The status becomes `issued`, with `issued_at` and `issued_by` recorded. Its adjustments' `payslip` is set. Its sessions are locked through scheduling's `lock_sessions`.

### 4.4 Mark paid (admin)

- From `issued` only; otherwise 409 `payroll.not_allowed_in_status`.
- It takes `paid_on`, which may not be after the academy's today (400 on `paid_on`), and records `paid_by`.

### 4.5 The session lock (scheduling)

A session with `payroll_locked` refuses attendance changes, cancel, restore, and bulk actions with 409 `payroll.payslip_issued`. In bulk it is skipped with that code. It is completed, so it is never "untouched", and generation and lifecycle never touch it.

### 4.6 Rates and adjustments

- **Rates:**
  - each is saved in the teacher's current `pay_currency`;
  - a rate can be edited or deleted at any time, and issued payslips keep their copied rates;
  - changing a teacher's `pay_currency` leaves old rates in the old currency, so they no longer count (§4.1) until new rates are set.
- **Adjustments:**
  - editable and deletable only while unused; otherwise 409 `payroll.adjustment_used`;
  - saved in the teacher's current `pay_currency`.

### 4.7 Access

| | Admin | Teacher | Student / Parent |
|---|---|---|---|
| Rates, adjustments, generate, issue, mark paid, CSV | ✓ | | |
| Payslips: read | all | their own `issued` and `paid` payslips only | none |
| Print page | any | their own issued and paid payslips | none |

- Students, parents and anonymous callers get 403 on every payroll route.
- A teacher gets 404 on other teachers' payslips and on drafts.
- `notes`, `issued_by` and `paid_by` are admin-only.
- The session payload gains `payroll_locked` for admins and the session's teacher.

## 5. API (`/api/v1/payroll/`, existing conventions)

| Route | Methods | Notes |
|---|---|---|
| `rates/` | GET, POST | Filter: `teacher`. POST `{teacher, course?, hourly_rate_minor}`. |
| `rates/<id>/` | PATCH, DELETE | PATCH `hourly_rate_minor`. |
| `adjustments/` | GET, POST | Filters: `teacher`, `used` (true/false). POST `{teacher, kind, amount_minor, effective_on, reason}`. |
| `adjustments/<id>/` | PATCH, DELETE | Unused only. |
| `payslips/` | GET | Filters: `year`, `month`, `teacher`, `status`. Paginated. `?format=csv` is admin-only. |
| `payslips/generate/` | POST | `{year, month}` → the result from §4.2. |
| `payslips/<id>/` | GET | Includes the lines. |
| `payslips/<id>/issue/` | POST | Returns the payslip. |
| `payslips/<id>/mark-paid/` | POST | `{paid_on}`. Returns the payslip. |

- People are referenced by User id, as in Plan 3.
- 409 bodies are `{detail, code}`, and field problems return 400.

## 6. Dashboard (`/app/`)

**Admin** (a new "Payroll" nav group):
- **Payslips:**
  - a month picker (default: last month) and "Generate", whose result names teachers missing a rate;
  - a table of teacher, sessions, hours, gross, bonuses, deductions and net (in its currency), status, and a missing-rate badge;
  - filters for status and teacher, and CSV export.
- **Payslip page:**
  - lines grouped as sessions, then adjustments, then the totals;
  - "Issue", with translated refusals;
  - "Mark paid", with a date;
  - "Print".
- **Rates:** per teacher, the default rate plus per-course rates, with add, edit and delete, and a warning for teachers without a default rate.
- **Adjustments:** a list with filters, and add, edit and delete for unused ones.

**Teacher:** "Teaching" gains "My payslips". It lists their issued and paid payslips, each opening read-only with Print.

**Print page:** the same academy-branded, no-shell A4 layout as invoices (Plan 6), in the viewer's language and right-to-left for Arabic.

**Sessions:** a `payroll_locked` session shows a "Paid in payslip" note. Its attendance controls are disabled, and cancel and restore are hidden.

**Throughout:**
- every string is in Arabic and English;
- right-to-left and phone width;
- semantic colour tokens only;
- not-found and error states;
- 409 codes shown translated;
- the shared helpers reused.

## 7. Seeds

The demo teachers get:
- a default rate, and one course rate;
- one teacher with no rate, to show the warning;
- one bonus.

For last month:
- payslips are generated;
- one is issued;
- one is issued and marked paid.

Running seeding twice changes nothing.

## 8. Testing

- **Backend:**
  - the pay rule for every student × teacher attendance combination;
  - rate choice and rounding;
  - adjustments by date and currency;
  - generate: create, replace, remove, and leave issued alone;
  - issue:
    - its refusals: month not over, missing rate, negative net, wrong status;
    - its fresh rebuild;
    - locking the sessions;
  - the lock on attendance, cancel, restore and bulk;
  - numbering under concurrency (a lock-shape test with exact SQL);
  - a `pay_currency` change;
  - the role × route matrix, including a teacher seeing only their own non-drafts;
  - cross-academy isolation with data in both academies.
- **Dashboard:** every page, dialog and the print page, in both languages.
- **E2E through Caddy:**
  1. The admin sets a rate for a teacher with completed sessions last month, and generates.
  2. The admin issues the payslip and marks it paid.
  3. The teacher (invited) signs in, sees the payslip and prints it.
  4. The locked session's attendance controls are disabled.
- **Coverage gates as today.**

## 9. Risks

- **Pay mistakes.** Mitigation:
  - one pay rule and one amount formula;
  - integer minor units;
  - copied lines;
  - issue only after the month ends;
  - a fresh rebuild at issue.
- **Changing paid history.** Mitigation: the session lock, enforced in scheduling on every write path.
- **Currency drift.** Mitigation: the teacher's current currency governs; stale rates count as missing.

## 10. Out of scope (roadmap phase)

- Percentage incentives, per-student rates, fixed salary, teacher balance and withdrawals, report deductions, receipt acknowledgement, and salaries as expenses: B4.
- Payslip notifications: Plan 8.
