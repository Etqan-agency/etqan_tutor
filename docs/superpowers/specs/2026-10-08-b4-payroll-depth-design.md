# Phase B4 — Payroll depth — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); review findings applied
2026-10-08.
**Phase:** B4 of `2026-09-24-parity-roadmap-design.md` §2: per-student rates; percentage incentives; report
deductions; fixed salary; teacher balance and withdrawal requests; receipt acknowledgement; salary
projections; bulk rate assignment; receipts → expenses (PAY-002…013, EXP-005). Depends on B2 (session
classes) and B3 (expenses). B4a needs only B2a, B2e and B2f, and B4c needs B3a; all four are merged (§3).
**Works under:** `2026-10-02-parallel-orchestration-design.md` (ledger, slices, merge queue, ownership:
B4 owns `etqan.payroll`).
**Builds on:**
- Plan 7 (`2026-09-26-payroll-design.md`): rates, adjustments, payslips, the lock, and P7-1 to P7-6.
- B2a (`2026-10-03-b2a-session-classes-design.md`): session kinds, `pays_teacher` and `at_disposal`.
- B2e: trial sessions.
- B2f (`2026-10-03-b2f-bundles-groups-design.md`): bundles and group classes.
- B3a: `finance.services.post_expense`.

**Evidence:**
- `docs/PHASE_1_SYSTEM_AUDIT.md`, cited as `P1 …`.
- `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md`, cited as `TH …`.

R7 is dropped (ledger D1). Payroll arithmetic is the audits' CRITICAL unknown (P1 §19 "Exact payroll
arithmetic", TH U6). Every rule below that the audits do not show is therefore marked `[assumed]`, and it is
chosen so that **with every new switch off, every payslip pays exactly what it pays today** (B4-2).

This document holds two specs:
- §1–§4: the phase spec.
- §5–§11: the first slice's spec, **B4a — pay rules and rates**.

Later slices get their own spec files, designed against this one.

## 1. Goal

Turn Plan 7's single pay rule into TutorHamster's payroll. That means adding:
- rates per student;
- a weight for each student attendance;
- pay for group classes;
- percentage incentives;
- report deductions;
- a fixed-salary mode;
- a teacher balance with withdrawal requests;
- receipt acknowledgement;
- posting paid salaries to expenses;
- a forward salary projection.

Every piece is a per-academy switch, off by default (PO-5). Each slice therefore merges without changing any
amount an academy already sees.

## 2. Phase decisions

| # | Decision | Source |
|---|---|---|
| B4-1 | All of B4 lives in the existing app **`etqan.payroll`**, which B4 owns. New tables and new columns go only on payroll's own tables. Payroll reads sessions only through `scheduling.services` (`payroll_sessions`, `hold_sessions`, `lock_sessions`, `missing_reports`). It may filter and annotate the querysets those services return using scheduling's field paths, as `rules.PAYS` does today (for example `subscription__bundle_id` or `subscription__bundle__kind`). It never imports scheduling's models. It changes no scheduling model. | orchestration §4.3; spec Plan 7 P7-1; `payroll/services/rules.py` precedent |
| B4-2 | **Nothing changes while a switch is off.** Every new rule reads its settings only while its switch is on. With every B4 switch off, `build()` returns the same lines as today: the same set, order, descriptions, rates, minutes and amounts, the same totals and the same `missing_rate`. The new descriptive line columns are filled whatever the switches (A-7). Each slice has a regression test that pins this. Settings rows survive a switch being turned off. | PO-5; orchestration §2 |
| B4-3 | **Money stays per currency** (P7-3, D5). A payslip, a rate, an adjustment, a fixed salary, a balance and a withdrawal are each in one currency, and nothing sums across currencies. The only cross-currency figure B4 shows is the projection's estimated total. It goes through `finance.services.convert_estimate` (D24/D31) and is labelled an estimate. | spec Plan 7 P7-3; ledger D5, D24, D31 |
| B4-4 | **Percentages are basis points:** integers from 0 to 10000, meaning 0 to 100 %. Every derived amount uses Plan 7's one rounding, `round_half_up` on integers. A session's amount becomes `round_half_up(rate × minutes × pay_bp, 60 × 10000)`. With `pay_bp = 10000` this equals today's `round_half_up(rate × minutes, 60)` exactly: `(2rm·10⁴ + 60·10⁴) // (120·10⁴) = (2rm + 60) // 120`. | spec Plan 7 §4.1; P1 PAY-005 "fixed or %" · [assumed] bp |
| B4-5 | **Issued payslips never change** (P7-4). Every *pay rule* acts only through `build()`, which runs at generate and again at issue. A setting changed after a month is issued affects later months only. (B4c's balance and withdrawals act on payslips that are already paid, never on their lines.) | spec Plan 7 P7-4 |
| B4-6 | **Who pays whom stays Plan 7's.** A line pays `session.teacher`. Only sessions that `payroll_sessions` returns are paid: `pays_teacher` on and not locked (D9). The month is `occurs_on` (B2b B-10). Once B2g merges, a substitute is paid by their own rates, because they are the session's teacher. P7-2 stays the base rule: a session pays when it is `completed` and its teacher attendance is `present` or `not_set`. B4a adds weights on top (§5) and one more paying status, `at_disposal`, which an academy must opt into. | spec Plan 7 P7-2; ledger D8, D9; B2g G-5 (queued) |
| B4-7 | **Group classes** (D6, D15). An academy chooses between two modes. **Per student** is today's behaviour and the default. **Per class** pays one line per class. The other rows of the class are listed with an amount of 0 and are locked like any paid row (B4a A-6). | ledger D6, D15 · [assumed] |
| B4-8 | B4 sends no notifications (D39: notifications are pull-based). If B5 asks for payroll notices (payslip issued or paid, withdrawal decided), B4 adds a windowed read service then, shaped like D29. None is built speculatively. | ledger D39 |
| B4-9 | **Teacher panel rights.** A teacher reads their own issued and paid payslips (Plan 7 §4.7). From B4c they also read their own balance and withdrawal requests, and acknowledge their own paid payslips. Teachers never see other teachers' rates, the settings or projections. Students and parents get 403 on every payroll route, as today. | spec Plan 7 §4.7; P1 §3 teacher actor (withdrawal requests, salary receipts) · [assumed] rights |
| B4-10 | Dashboard code stays in `src/features/payroll/`. Office pages go under `/payroll/…` and teacher pages under `/teaching/…`. Strings go in the existing `payroll` area (`dashboard/src/locales/{en,ar}/payroll.json`), which B4 owns. Error-code strings go in the `payroll` section of `errors.json`, and nav labels in `nav.json`. No `es` file is added (D22). | dashboard layout; ledger D11, D22 |

## 3. Slices

| Slice | Topic | Contents | Audit IDs | Switches (off by default) | Requires | Size |
|---|---|---|---|---|---|---|
| **B4a** | pay rules & rates | Per-student rates; bulk rate assignment; payroll settings (a weight for absent and for excused students, `at_disposal` pay, group-class pay); the session class, weight and group role copied onto every payslip line; per-class counters on payslips (TH's board columns) | PAY-001, PAY-002, PAY-003, PAY-011; D6/D15; B2-6 | `student_teacher_rate` (flipped), `payroll_rules` (new), `bulk_teacher_rates` (new) | B2a, B2e, B2f (merged) | M |
| **B4b** | incentives, report deductions, fixed salary | See the notes after this table | PAY-005, PAY-008, PAY-009, PAY-002; BR-33 | `incentives_deductions` (flipped; it gates percentages only, and fixed bonuses and deductions stay always on as in Plan 7), `report_deductions` (flipped; requires `session_reports`), `fixed_teacher_salary` (flipped) | B4a | M |
| **B4c** | balance & payouts | See the notes after this table | PAY-006, PAY-007, PAY-010, PAY-013; BR-23, BR-24 | `teacher_balance` (new), `payslip_acknowledgement` (new), `salary_expenses` (new; requires nothing, so it posts even while `expenses` is off, B3a A-8) | B4a, B3a (merged) | M |
| **B4d** | projections & board export | See the notes after this table | EXP-005, EXP-002 (salaries), PAY-001 | `salary_projections` (new) | B4b | S |

**B4b contents.**
- **Percentage incentives.** A bonus of `percent_bp` of the month's gross session pay, on `PayAdjustment`.
  The migration adds a nullable column and relaxes the amount constraint.
- **Report deductions.** A setting, `report_deduction_bp`. Each paying line whose session appears in
  `scheduling.services.missing_reports()` at build time becomes a `report` line, which takes that share off
  the session's pay.
- **Payslip counters.**
  - *Reports sent* is the paying lines whose session owed a report and has one (the reverse field `report`
    on the `payroll_sessions` queryset, B4-1).
  - *Reports not sent* is the lines found by `missing_reports`.
  - *Teacher absences* is the teacher's non-paying `payroll_sessions` rows with teacher attendance
    `absent` or `excused`.
  - These three counters are stored on the payslip at build, because they are not lines.
- **Fixed monthly salary per teacher.**
  - Gross is the fixed amount, as one `fixed` line.
  - Sessions are listed at 0 and locked.
  - A teacher with a fixed salary gets a payslip every month while active.

**B4c contents.**
- **Teacher balance.**
  - An issued payslip may be paid **to the balance** instead of directly.
  - The balance, per currency, is the paid-to-balance payslips minus the paid withdrawals. It is derived,
    with no ledger table.
- **Withdrawal requests.**
  - The teacher or the office creates one.
  - It runs under review → approved → paid, or ends rejected. The teacher may cancel it while it is under
    review, and the office may cancel it while it is under review or approved (B4c C-4).
  - The amount must be no more than the available balance, and this is hard-enforced. Available means the
    balance minus requests under review or approved.
  - Every create, approve, reject, pay and cancel first takes a payroll-owned lock row, `BalanceLock(teacher, currency)`,
    `FOR UPDATE` (created if missing). Nothing in identity is locked.
- **Receipt acknowledgement.** The teacher acknowledges a paid payslip.
- **Expenses.**
  - A paid payslip, paid directly or to the balance, is posted **once, when it becomes paid**:
    `finance.services.post_expense(source="payroll.payslip", source_id=payslip.id, type="salaries", amount_minor=net, currency, spent_on=paid_on)`.
  - The title is "Teacher salary – {teacher} – receipt {number}", in the academy's default language.
  - A payslip with a net of 0 is not posted.
  - Withdrawals never post an expense.
- **Read service.** `payroll.services.balances_of(teacher_user_id)`.
- **Import contract.** None is needed: B3's contract already keeps every app out of finance's models, api
  and clock.
- **Impersonation.** Every B4c write route refuses a quick-login session (D19).

**B4d contents.**
- **Salary projection** for the current or a future month. Per teacher it shows:
  - the pay so far (`build`);
  - the month's remaining `scheduled` sessions from `payroll_sessions`, priced as if completed with the
    student present, under the current rules;
  - the fixed salary;
  - pending fixed adjustments.
- Per-currency totals, plus a converted estimate (D31).
- The CSV already carries every counter (B4a, B4b and B4c add their own). B4d adds the projection export
  only.

Order: B4a → B4b → B4c → B4d. B4c needs only B4a, so it may be built before B4b if B4b is blocked.

**Recorded deviations and choices that later slices must keep:**

- **P7-2 is made configurable.** P7-2 was an owner decision with "no academy switches". B4a adds academy
  settings that weight it (A-3 to A-6). Their defaults reproduce P7-2 exactly. The teacher-attendance gate
  is never configurable. [assumed; recorded with `decide`]
- **Withdrawals are in the balance's currency, not always USD** (BR-24 says USD). Converting would need a
  rate at request time and would sum currencies (D5). A teacher with balances in two currencies requests
  each one separately. [assumed]
- **"Sufficient balance" is enforced** (BR-23 says it is UNKNOWN whether it is), under the lock above.
  [assumed]
- **A report deduction is a share of the session's pay**, not a fixed amount, so it needs no currency.
  TutorHamster's settings-tab fields were never captured (TH §2.6). [assumed]
- **A percentage incentive is a share of the month's gross pay** (session lines plus a fixed salary) on the
  payslip that uses it.
  [assumed]
- **A fixed salary is paid in full for every month the teacher is active**, with no pro-rating. [assumed]
- **"Excused sessions"** (P1 PAY-002, الحصص المعتذر عنها) is read as *student*-excused (B4a A-4). Teacher-excused
  sessions are counted by B4b among teacher absences. [assumed]
- **BR-06 ("creation date used for salaries")** stays unbuilt. Payroll keeps `occurs_on` (B2 phase §3).

**Not taken by any B4 slice, with the reason:**

- **Teacher profit margins** (the EXP-002 export): they belong to consultations (B7).
- **Excel files:** exports stay CSV (v1 §6.3; EXP-002 is PARTIAL by design).
- **Manual balance top-ups or corrections:** TutorHamster shows "current balance" as a field on the teacher
  form, but whether it can be edited is unknown. Not built; corrections stay adjustments (P7-4).
- **PAY-006's "cancelled" receipt status:** a payslip that should not be paid is never issued, and its draft
  is removed by the next generate once it has no activity. Plan 7's draft → issued → paid stays.
- **Teacher payout method and details** (PEOPLE-005): already on `TeacherProfile` (Plan 3). B4c shows them on
  withdrawal requests read-only.
- **Payslip notifications:** B5, on request (B4-8).
- **Monthly teacher evaluation:** its behaviour is UNKNOWN (as in B6 and B9a A-15).

## 4. Shared lists, ownership and requests

- **Shared lists.** B4 adds lines only under its `── phase B4 ──` markers:
  - the feature registry, where it also flips its own four `_later` lines in place
    (`student_teacher_rate`, `incentives_deductions`, `report_deductions`, `fixed_teacher_salary`);
  - the access `RESOURCES` (`payroll_settings` in B4a, `teacher_withdrawal` in B4c);
  - `seed_dev` (`seed_b4(subdomain)` from `etqan/tenants/seeds/b4.py`);
  - the dashboard's `NAV_ITEMS`.
  - `TENANT_APPS` and `config/api_router.py` are unchanged, because `etqan.payroll` and `payroll/` already
    exist.
- **`pyproject.toml`.** No change: B3's finance contract already covers payroll (B4c §3).
- **Requests to other phases:** none. Every read B4 needs exists in `scheduling.services` or is a field path
  on the querysets those services return (B4-1).
- **Shared decisions to record** (`decide`):
  - B4a: B4-7 together with A-6's group-class definition (affects B2 and B11).
  - B4a: the P7-2 deviation (affects B11).
  - B4c: `payroll.services.balances_of(teacher_user_id) -> list[Balance(currency, balance_minor, available_minor)]`
    (affects B11).

---

# Slice B4a — Pay rules and rates

## 5. Decisions

| # | Decision | Source |
|---|---|---|
| A-1 | **Per-student rate** (`StudentRate`). It holds a teacher, a student, an hourly rate and a currency (the teacher's `pay_currency` when saved). There is one per (teacher, student), and it applies to any course. While `student_teacher_rate` is on, a session's rate is the (teacher, student) rate, else the course rate, else the default rate (Plan 7 §4.1). While it is off, student rates are kept but ignored. A student rate in a currency the teacher is no longer paid in does not count (P7 §4.6). | TH §1.3 #1 (PAY-011 hint "set the teacher's hourly rate per student; the normal hourly-rate calculation stops") · [assumed] fallback to the course rate when no student rate is set (a literal "stops" would leave every other student unpaid) |
| A-2 | **Bulk rate assignment.** The office picks several teachers and one set of rates (a default, per-course rates, or both). Each rate is saved to every chosen teacher at once: an existing (teacher, course) rate is updated, otherwise it is created. The teachers' other rates are untouched. Active and inactive teachers are allowed (as `create_rate`). All chosen teachers must share one `pay_currency`; otherwise the answer is 400 on `teachers` with code `payroll.mixed_currencies` (D25). The form filters teachers by currency first. The assignment is all or nothing, in one transaction. | P1 PAY-003 ("add rates for a group of teachers") · [assumed] one currency per batch (P7-3) |
| A-3 | **Payroll settings.** There is one `PayrollSettings` row per academy, created by this slice's migration (pk 1). Its fields: `student_absent_pay_bp` (default 10000), `student_excused_pay_bp` (default 10000), `at_disposal_pays` (default false), and `group_pay` (`per_student`, the default, or `per_class`). They take effect only while `payroll_rules` is on; while it is off, the defaults apply, which is today's rule. `generate` and `issue` read the effective settings once and pass them down, so discovery and build see the same values. | P1 PAY-001/002 (separate payroll columns for student-absence and excused sessions); TH U6 · [assumed] weights |
| A-4 | **Weight by student attendance.** A paying session whose student attendance is `absent` pays at `student_absent_pay_bp`, and one whose student attendance is `excused` pays at `student_excused_pay_bp`. `present` and `not_set` pay at 10000. The weight is copied onto the line as `pay_bp`. Teacher attendance stays P7-2's gate: a teacher who is absent or excused gets no line. | P1 FLOW-006 (student-absence and excused sessions counted apart); spec Plan 7 P7-2 · [assumed] |
| A-5 | **`at_disposal` pay.** With `at_disposal_pays` on, an `at_disposal` session whose teacher attendance is `present` or `not_set` pays at 10000. Its student attendance is always `not_set` (B2a A-11). With the setting off, it is not paid, as today. | ledger D8; B2 B2-6 ("B4 decides its pay"); B2a A-11 · [assumed] |
| A-6 | **Group class.** See the A-6 detail after this table. | ledger D6, D15; B2f F-4, F-6 · [assumed] |
| A-7 | **Descriptive line columns** are filled on every session line, whatever the switches: `session_kind` (`regular`, `compensation`, `extra` or `trial`), `session_status` (`completed` or `at_disposal`), `student_attendance`, `pay_bp`, `group_key` (empty without a group) and `group_role` (empty, `carrier` or `member`; filled only in `per_class` mode). `group_key` is `"<bundle_id>:<starts_at as UTC YYYY-MM-DDTHH:MM:SSZ>:<minutes>"`. Lines written before this slice keep these columns empty. | P1 PAY-001/002 columns; spec Plan 7 P7-4 (copied lines) |
| A-8 | **Counters.** The payslip payload gains `counts = {regular, compensation, extra, trial, at_disposal, student_absent, student_excused, group_members}`. They are computed in SQL from the session lines, as correlated subqueries the way `sessions` and `minutes` are today. `counts` is `null` for a payslip that has session lines with an empty `session_kind` (written before this slice). The existing `sessions` and `minutes` now count only lines that are not `member` lines, so "total hours" is not inflated by per-class rows. Before this slice there are no member lines, so nothing changes. The office list shows the counters as optional columns behind one toggle, as TutorHamster shows optional columns. They describe stored lines, so they need no switch. | TH §2.6 PAY-001 columns; P1 PAY-002 |
| A-9 | **Trial and extra sessions** pay by the same rules as any other session. `pays_teacher` decides whether they are paid at all (B2e E-4, B2a A-7). There is no separate trial or extra rate. | ledger D9; B2e E-4 ("B4 decides trial pay") · [assumed] no separate rate (TH shows only counts) |
| A-10 | **Missing rate.** `missing_rate` is true when any line other than a `member` line has no rate. Today's rule is otherwise unchanged. | spec Plan 7 §4.1 |
| A-11 | **Access.** See the A-11 detail after this table. | spec Plan 7 §4.7; Plan 12a codes |
| A-12 | **Switches.** See the A-12 detail after this table. | PO-5; FT-2 |

**A-6 detail — group class.**
- **What a class is.** A group class is the paying rows that share:
  - one teacher;
  - one `subscription__bundle_id`, where `subscription__bundle__kind = "group"`;
  - one `starts_at`;
  - one `minutes`.

  These match B2f F-4, which requires the same start and length. Payroll reaches them as field paths on
  `payroll_sessions` (B4-1). A session with no subscription (extra or trial) is never grouped.
- **Per student** (the default). Each row is its own line, as today (D15).
- **Per class.**
  - The row with the lowest id is the class's `carrier`.
  - It is paid at its own rate under A-1's precedence. With student rates on, that is its student's rate if
    one is set, else the course rate, else the default.
  - Its weight is the highest weight among the class's rows. One present student makes it 10000.
  - Every other row is a `member` line, with amount 0, `rate_minor` null, its own minutes kept, and its
    description suffixed "group class".
  - At issue, every row is locked, as today.
- **Late rows** (P7-4). Under `per_class`, `generate`'s `unpaid_sessions` leaves out a row whose
  `group_key` already appears on a line of an issued or paid payslip of the same teacher. That class was
  already paid, and reporting the row would invite the office to pay it a second time through an
  adjustment.
- **Substitutes and a teacher change on one member** (B2g G-5, B2f F-6). A class is per teacher, so a
  member taught by another teacher forms that teacher's own class. Both teachers are then paid for the
  hour. This is accepted [assumed], and the settings page warns about it next to `per_class`.

**A-11 detail — access.**
- Student rates use the existing `payroll_rate.*` codes.
- Bulk assignment needs both `payroll_rate.create` and `payroll_rate.update`. The view uses a small custom
  permission for this, because `permission_codes` maps one code per method.
- The settings need the new resource `payroll_settings`, with `view` and `update`.
- Teachers, students and parents get 403, as in Plan 7.

**A-12 detail — switches.**
- `student_teacher_rate` is flipped to built, and stays off. It gates the student-rate routes (404 while
  off) and their use in `build`. The settings page warns that `per_class` does not use student rates for
  the class's other rows.
- `payroll_rules` is new, off, in group `money`. It gates the settings route (404 while off) and the
  settings' use in `build`.
- `bulk_teacher_rates` is new, off, in group `money`. It gates the bulk route. It is a rates convenience,
  independent of the pay rules.

## 6. Data (`etqan.payroll`)

### 6.1 StudentRate (new)

| Field | Notes |
|---|---|
| `teacher` | → `identity.TeacherProfile`, PROTECT |
| `student` | → `identity.StudentProfile`, PROTECT |
| `hourly_rate_minor` | ≥ 0 |
| `currency` | the teacher's `pay_currency` when saved |
| `created_at`, `updated_at` | |

It is unique on (teacher, student), with a check that `hourly_rate_minor >= 0`.

### 6.2 PayrollSettings (new, one row, pk 1)

| Field | Notes |
|---|---|
| `student_absent_pay_bp` | 0 to 10000, default 10000 |
| `student_excused_pay_bp` | 0 to 10000, default 10000 |
| `at_disposal_pays` | bool, default false |
| `group_pay` | `per_student` or `per_class`, default `per_student` |
| `updated_at` | |
| `updated_by` | → User, SET_NULL |

- Both bp fields have check constraints.
- A data migration creates the row in every academy schema.
- `get_settings()` also creates it if it is missing, using `get_or_create(pk=1)` and retrying once on
  `IntegrityError`.

### 6.3 PayslipLine (existing; new columns, all with defaults)

| Column | Type |
|---|---|
| `session_kind` | char 12, blank |
| `session_status` | char 12, blank |
| `student_attendance` | char 8, blank |
| `pay_bp` | small int, null |
| `group_key` | char 64, blank |
| `group_role` | char 7, blank |

The migration only adds columns.

## 7. Behaviour

### 7.1 Building a line

- **The paying rule.** `rules.pay_rule(settings)` returns the Q for paying sessions:
  - P7-2's `PAYS`;
  - OR, when the effective settings have `at_disposal_pays`, `status=at_disposal` with teacher attendance
    `present` or `not_set`.

  Generate's discovery and `build` both use it, so there is one implementation, as today. `build(teacher,
  year, month, settings=None)` gains the optional `settings` (additive); `None` means "read the effective
  settings".
- **Each paying session**, oldest first:
  1. its rate, per A-1;
  2. its weight, per A-4 and A-5;
  3. its amount, per B4-4.
- **Regrouping.** When `group_pay = per_class`, A-6 then regroups the lines. Line order stays oldest
  first, so each member line stays at its own position.
- **The amount formula.** `session_amount(rate, minutes, pay_bp=10000)` gains the weight as an optional
  argument (additive).

### 7.2 Settings, student rates, bulk

- **Settings.**
  - `get_settings()` returns the row.
  - `effective_settings()` returns the defaults while `payroll_rules` is off (B4-2).
  - `update_settings(by, **fields)` checks the ranges, with a 400 on the field.
- **Student rates.**
  - `create_student_rate(teacher_id, student_id, hourly_rate_minor)`. Both ids are User ids, and teachers
    may be active or not. The refusals:
    - 400 on `teacher` when the user is not a teacher;
    - 400 on `student` when the user is not a student;
    - 409 `payroll.rate_exists` when the (teacher, student) rate exists, including after a concurrent
      insert (IntegrityError).
  - `update_student_rate` and `delete_student_rate` lock the row, as `update_rate` does.
- **Bulk assignment.** `assign_rates(teacher_ids, rates)`.
  - `rates` is `[{course_id | None, hourly_rate_minor}]`, with at least one entry. Courses must be unique
    and are validated through catalogue.
  - Every teacher must be valid (400 on `teachers`), and all must share one currency (A-2).
  - It locks the chosen teachers' existing rates `FOR UPDATE`, in id order. It then updates the ones that
    exist and inserts the rest.
  - A concurrent insert that breaks the unique constraint rolls the whole batch back with 409
    `payroll.rate_exists`.
  - It returns `{created, updated}`.

### 7.3 Unchanged

Generate, issue, mark paid, the lock and numbering are unchanged, except that:
- they call the new rule and build with the same settings;
- generate applies A-6's late-row rule.

## 8. API (`/api/v1/payroll/`)

| Route | Methods | Notes |
|---|---|---|
| `student-rates/` | GET, POST | Feature `student_teacher_rate`. GET is not paged, like `rates/`. Filters `teacher` and `student` (User ids). POST `{teacher, student, hourly_rate_minor}`. Row: `id`, `teacher {id, full_name}`, `student {id, full_name}`, `hourly_rate_minor`, `currency`, `current` (whether its currency is the teacher's `pay_currency`), `created_at`, `updated_at`. |
| `student-rates/<id>/` | PATCH, DELETE | PATCH takes `hourly_rate_minor`. |
| `rates/bulk/` | POST | Feature `bulk_teacher_rates`. Body `{teachers: [user ids], rates: [{course?, hourly_rate_minor}]}`; returns `{created, updated}`. |
| `settings/` | GET, PATCH | Feature `payroll_rules`. Codes `payroll_settings.view` and `payroll_settings.update`. |
| `payslips/`, `payslips/<id>/` | GET | Payslip rows gain `counts` (A-8). Lines gain `session_kind`, `session_status`, `student_attendance`, `pay_bp`, `group_key` and `group_role`. The CSV gains the A-8 counter columns. |

409 bodies are `{detail, code}`, and field problems return 400 (Plan 7 §5).

## 9. Dashboard

- **Rates page.**
  - A "Per-student rates" section, shown while `student_teacher_rate` is on. It lists rates by teacher and
    allows add, edit and delete. The student picker offers active students only.
  - An "Assign to several teachers" dialog, shown while `bulk_teacher_rates` is on. The office picks a
    currency, then teachers of that currency, then rows of course and rate.
- **Payroll settings page** (`/payroll/settings`, a nav item under Payroll, shown while `payroll_rules` is
  on). It shows the two weights as percentages, the `at_disposal` switch and the group-pay radio. Each
  setting has a one-line explanation, and `per_class` shows the A-6 and A-12 warnings.
- **Payslip page.** Session lines show:
  - the class (kind or "at disposal");
  - the student-attendance badge;
  - the weight, when it is below 100 %;
  - "group class — paid on the first line" for `member` lines.
- **Payslips list.** A "Show session counts" toggle adds the counter columns. The list has no column picker
  today, and one toggle is the cheapest form of TutorHamster's optional columns.
- **Throughout:** both languages, right-to-left, phone width, semantic tokens, and translated error codes
  (`payroll.mixed_currencies`, `payroll.rate_exists`).

## 10. Seeds (`seed_b4`)

`seed_b4` is idempotent: it skips itself when any `StudentRate` exists. It creates one student rate for a
demo teacher and one of their students. The switches stay off. The settings row comes from the migration.

## 11. Testing

- **Regression (B4-2).** With every switch off, Plan 7's build tests pass unchanged. A fixture month with
  every class builds the same lines (set, order, descriptions, rates, minutes, amounts), totals and
  `missing_rate` as before. The classes are: an absent student, an excused student, at disposal, trial,
  extra, compensation, and a group of three.
- **Rules.**
  - Rate precedence student → course → default, with the switch on and off, and a stale currency.
  - The weight for each student attendance, with the switch on and off.
  - `at_disposal`, on and off, and with the teacher absent.
- **Per-class groups.**
  - The amount is paid once.
  - The weight rule.
  - Members get amount 0 and a null rate, and are locked at issue.
  - Mixed weights.
  - Rows with different minutes are different classes.
  - A row whose teacher is absent is not part of the class.
  - A member taught by a substitute is its own class.
  - `missing_rate` ignores member lines.
  - The late-row rule in `unpaid_sessions`.
- **Bulk.** Create and update; other rates untouched; mixed currencies refused; an invalid teacher or course
  refused; atomic.
- **Counters.** One query per page (a query-count test). `counts` is null on legacy payslips. `sessions` and
  `minutes` exclude member lines. The CSV columns.
- **API.**
  - Routes answer 404 while their switch is off.
  - The role × route matrix: office codes (bulk needs both codes); teachers, students and parents get 403.
  - Cross-academy isolation.
- **Dashboard.** The settings page, the student-rate section, the bulk dialog, the payslip line badges and
  the list columns, in both languages. Coverage gates as today.
- **E2E** (`e2e/b4-pay-rules.spec.ts`). The test builds its own data through the API as the admin, so it
  never depends on the seeds' payslip states. That data is a fresh teacher with a default rate, and an extra
  session on the 15th of last month marked student absent and teacher present. The admin turns on
  `payroll_rules` and sets the student-absent weight to 50 % on the settings page. They then generate last
  month and open the teacher's payslip, where the line is paid at half rate and marked absent at 50 %.
