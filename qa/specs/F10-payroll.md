# F10: Teacher payroll

Author: Agent 1 (research and test strategy, LEAN mode). This spec approves nothing.
Written 2026-10-18 from backend adff9c9 / dashboard 5ed775d.

Sources read: `backend/etqan/payroll/{models,clock,scopes}.py`, `payroll/services/*` (payslips, build, rules,
rates, adjustments, fixed_salaries, settings, balances, withdrawals, salary_expenses, projections),
`payroll/api/{views,serializers,urls}.py`, `scheduling/services/{paylock,attendance}.py`,
`finance/services/expenses.py:post_expense`, `platform/{permissions,csv}.py`, `docs/features/payroll.md`.
Existing tests (backend `etqan/payroll/tests/`, ~30 files) cover the arithmetic, locks, scopes and every error code
at service and API level with a pinned clock. They do NOT cover: the real HTTP stack, real sessions marked through
the scheduling API, cross-academy isolation in a live DB, a real concurrent POST race, the expense landing in
finance totals, or the dashboard. Cases below cite the test and re-run only the P1-critical ones end to end.

Conventions: `$QA` = `http://qa.etqan.localhost/api/v1`, `$QO` = `http://qaother.etqan.localhost/api/v1`.
Session-cookie auth as the stated role (use the F01/e2e login helper; send the CSRF header on writes).
Money is in integer minor units (piastres for EGP). Schema `academy_qa`; table names are
`payroll_teacherrate`, `payroll_studentrate`, `payroll_payadjustment`, `payroll_fixedsalary`,
`payroll_payrollsettings`, `payroll_payslip`, `payroll_payslipline`, `payroll_payslipcounter`,
`payroll_withdrawalrequest`, `payroll_balancelock`, `scheduling_session`, `finance_expense`
(confirm with `\dt academy_qa.*` first). "Closed month" = September 2026 (today is 2026-10-18, academy tz
Africa/Cairo, currency EGP). "Open month" = October 2026.

Common error shape: HTTP 409 with `code` in the body for the `payroll.*` codes named below; 400 names the field.

---

## Setup (run once, in order)

Uses `dc.sh` = the helper in `environment.md`. All data is created in academy `qa` only.

1. Switches (all payroll switches on; base state for most cases):
   ```
   dc.sh exec -T django python manage.py set_features qa --on student_teacher_rate bulk_teacher_rates payroll_rules \
     session_reports report_deductions incentives_deductions fixed_teacher_salary teacher_balance \
     payslip_acknowledgement salary_expenses salary_projections manual_sessions extra_sessions \
     disposal_status teacher_attendance exchange_rates
   ```
   Cases that need a switch off say so and restore it afterwards. Verify with `GET $QA/features/`
   (or `select features from public.tenants_academy where subdomain='qa'`).
2. People in `qa` (prefer the dashboard People pages or the people API; fallback
   `dc.sh exec -T django python manage.py tenant_command shell --schema=academy_qa`):
   - Teachers `T1 = qa-teacher@qa.etqan.test` (exists), `T2 = qa-teacher2@`, `T3 = qa-teacher3@`
     (password `QA-People-2026!`). All with `pay_currency=EGP`.
   - Students `S1 = qa-student@` (exists), `S2 = qa-student2@`, `S3 = qa-student3@`.
   - Staff role "QA Payroll Full" = payslip.{view,view_any,create,update}, payroll_rate.{view_any,create,update,delete},
     payroll_adjustment.{view_any,create,update,delete}, payroll_settings.{view,update},
     teacher_withdrawal.{view_any,create,update}; user `qa-staff-pay@`.
   - Staff role "QA Payroll Read" = payslip.view_any + payslip.view only; user `qa-staff-payread@`.
   - Existing: `qa-staff-nocode@`, `qa-staff-codes@` (student codes only), `qa-supervisor@`, `qa-student@`,
     `qa-parent@`, admin `qa-admin@`.
   - Courses `C1`, `C2` (catalogue API) and a subscription for each (S,T,C) pair used below.
3. Sessions (closed month Sept 2026). Create with `POST $QA/sessions/extra/` (switch `extra_sessions`):
   `{"student": S1, "course": C1, "teacher": T1, "occurs_on": "2026-09-10", "start_time": "10:00", "minutes": 60}`
   then mark: `PATCH`/`POST $QA/sessions/<id>/attendance/` `{"student_attendance":"present"}` (completes it).
   If the API refuses past dates, create with `tenant_command shell` (`Session.objects.create(...)`) and say so in the log.
   Standard fixture "F10-A" (build with a script, record ids in the evidence file):
   - T1: rate default 6000 (60 EGP/h). Sessions 09-03 60 min, 09-10 45 min, 09-17 30 min, all `present/present`. Expected gross 6000+4500+3000 = 13500.
4. Per-case extra data is stated in the case. Reset between cases with the cleanup line; drafts are deleted by
   regenerating, issued/paid payslips cannot be deleted (use fresh teachers/months, see each cleanup).
5. Clock: payroll reads the real clock. "Month over" cases use September 2026 (closed) and October 2026 (open). No
   clock patching is possible; use `occurs_on` dates.

---

## Cases

### Core money workflow

**F10-TC-001 (P1, REAL): owner end-to-end, set rate, generate, issue, pay, expense, acknowledge**
- Role: admin, then teacher T1. Switches: base.
- Data: fixture F10-A.
- Steps:
  1. `POST $QA/payroll/rates/` `{"teacher":T1,"hourly_rate_minor":6000}` -> 201 (skip if exists).
  2. `POST $QA/payroll/payslips/generate/` `{"year":2026,"month":9}` -> 200; `created>=1`, no `missing_rate` for T1.
  3. `GET $QA/payroll/payslips/?year=2026&month=9&teacher=T1` -> status `draft`, gross 13500, net 13500; note `number` `PAY-NNNNNN`.
  4. `GET .../payslips/<id>/` -> 3 `session` lines (6000/4500/3000), `rate_minor` 6000, `minutes` 60/45/30.
  5. `POST .../payslips/<id>/issue/` -> 200 status `issued`, `issued_by` set.
  6. `POST .../payslips/<id>/mark-paid/` `{"paid_on":"2026-10-18","notes":"cash"}` -> 200 status `paid`.
  7. As T1: `GET $QA/payroll/payslips/` lists it; `POST .../payslips/<id>/acknowledge/` -> 200 `acknowledged_at` set.
- Assertions: DB `payroll_payslip` one row (teacher,2026,9) status paid, paid_on, paid_by, net 13500; 3 `payroll_payslipline` kind session
  summing to gross; the 3 `scheduling_session.payroll_locked = true`; one `finance_expense` row (source `payroll.payslip`,
  source_id = payslip id, type `salaries`, amount 13500, currency EGP, spent_on 2026-10-18); `payroll_payslipcounter.last_number` advanced by 1 per created draft.
- Existing: test_api.py, test_issue.py, test_acknowledge.py cover each step at API level. Re-run end to end for the real stack.
- Cleanup: none (payslip stays; later cases use T2/T3 or other months).

**F10-TC-002 (P1, REAL): rounding, half-up, once per line, integer only**
- Role: admin. Switches: base. Data: T2 default rate 12345; Sept sessions for T2: 45 min present; 30 min present; 20 min present;
  45 min `student_attendance=absent`; 45 min `excused` (weights set in TC-013: absent 5000 bp, excused 2500 bp, set them first via `PATCH $QA/payroll/settings/`).
- Steps: generate 2026-09; `GET` T2 payslip.
- Expected line amounts: 45 min = 9258.75 -> 9259; 30 min = 6172.5 -> 6173; 20 min = 4115; absent 45 min at 5000 bp = 4629.375 -> 4629;
  excused 45 min at 2500 bp = 2314.6875 -> 2315. Gross = sum of the rounded lines (26491), never a rounded sum of unrounded values.
- Assertions: every `amount_minor` is an int, no decimals in JSON; `gross_minor` = sum(lines); `net = gross + bonuses - deductions`; DB `payroll_payslipline.amount_minor` equal.
- Existing: test_build.py, test_percentages.py check the formula. Re-run for the API JSON types.
- Cleanup: regenerate draft; leave T2 draft or delete the sessions.

**F10-TC-003 (P1, REAL): the pay rule, which sessions pay and which month they fall in**
- Role: admin. Switches: base, `at_disposal_pays` false (default). Data: T3 rate 6000; sessions of 60 min:
  (a) completed/present 2026-09-30 23:30 Cairo-time start (occurs_on 09-30); (b) completed/present 2026-10-01 00:30 (occurs_on 10-01);
  (c) completed, teacher_attendance `absent`; (d) completed, teacher `excused`; (e) completed, teacher `not_set`;
  (f) still `scheduled` in September; (g) `cancelled`; (h) `at_disposal` (disposal endpoint); (i) completed with `pays_teacher=false` (`POST $QA/sessions/<id>/pays-teacher/`).
- Steps: generate Sept; read T3 payslip session ids; then `PATCH $QA/payroll/settings/` `{"at_disposal_pays":true}`, regenerate, read again; set back to false.
- Expected: Sept payslip pays exactly (a) and (e); (b) belongs to October; (c),(d),(f),(g),(i) excluded; (h) excluded, then included at 100 % when `at_disposal_pays` is on.
- Assertions: line `session_id` set; `teacher_absences` counts (c)+(d) (and (h) if absent); DB session rows unchanged until issue.
- Existing: test_pay_rules.py, test_counts.py. Re-run only the timezone boundary (a)/(b) live, which unit tests pin with a fake clock.
- Cleanup: settings back to defaults; sessions stay.

**F10-TC-004 (P1, REAL): rate precedence student > course > default, and the switch**
- Role: admin. Switches: `student_teacher_rate` on, then off. Data: new teacher T4 (or T2 with a clean month, e.g. August 2026):
  default 6000, course C2 rate 9000, student rate (T,S2) 12000; August sessions 60 min each: (S1,C1), (S1,C2), (S2,C1), (S2,C2).
- Steps: `POST $QA/payroll/rates/` default and `{"course":C2,...}`; `POST $QA/payroll/student-rates/` `{"teacher":T,"student":S2,"hourly_rate_minor":12000}`; generate Aug; read lines.
  Then `set_features qa --off student_teacher_rate`; `POST .../student-rates/` -> 404/403 (route gated); regenerate; read lines; switch back on.
- Expected on: S1/C1 6000, S1/C2 9000, S2/C1 12000, S2/C2 12000. Off: S2 rows fall back to 6000 and 9000.
  Duplicate default rate for the same teacher -> 400 on `course`; duplicate (teacher, course) -> 400.
- Assertions: `payroll_teacherrate` unique constraint, one default per teacher; `payroll_studentrate` row survives the switch off but is not applied.
- Existing: test_student_rates.py, test_rates_adjustments.py. P1 because it decides every line.
- Cleanup: delete the rates created for this case.

**F10-TC-005 (P1, REAL): missing rate blocks issue and nothing changes**
- Role: admin. Data: T3 with no rate, one completed Sept session (use a month T3 has no issued payslip, e.g. July 2026).
- Steps: generate July -> `missing_rate` lists T3; payslip `missing_rate:true`, net 0. `POST .../issue/` -> 409 `payroll.missing_rate`.
  Then create rate; `issue/` without regenerating -> 200 (issue rebuilds from fresh data).
- Assertions after 409: payslip still `draft`, no `payroll_locked` session, adjustments unused, `issued_at` null. After 200: lines priced.
- Existing: test_issue.py `missing_rate`. Re-run end to end.
- Cleanup: none.

**F10-TC-006 (P1, REAL): issue only after the month is over (academy calendar)**
- Role: admin. Data: any teacher with an October 2026 completed session and a rate.
- Steps: generate 2026-10 -> a draft is created; `POST .../issue/` -> 409 `payroll.month_not_over`; `POST .../mark-paid/` on the draft -> 409 `payroll.not_allowed_in_status`.
  `generate` with `{"year":1999,"month":9}` and `{"year":2026,"month":13}` -> 400 on the field.
- Assertions: draft unchanged; no lock; October draft is rebuilt on each generate (number kept).
- Existing: test_issue.py. Cleanup: regenerate after removing the October session, or leave the draft.

**F10-TC-007 (P1, REAL): duplicate payslip generation for one period**
- Role: admin. Data: T1 Sept payslip from TC-001 (issued/paid) plus T3 Sept draft.
- Steps:
  1. `generate` Sept twice in a row -> same payslip ids and numbers, `replaced` counts, no new rows.
  2. Two parallel `POST generate {"year":2026,"month":9}` (`xargs -P2` or `curl &`): both 200, still ONE payslip per teacher.
  3. Direct duplicate in DB: `insert into academy_qa.payroll_payslip (...)` same (teacher,year,month) -> unique violation.
  4. Generate when a teacher's session is removed (cancel it) -> draft rebuilt; if no activity remains the draft is deleted (`removed`).
- Assertions: `select teacher_id,year,month,count(*) from academy_qa.payroll_payslip group by 1,2,3 having count(*)>1` returns 0 rows; issued/paid T1 payslip bytes unchanged (compare `net_minor`, `updated_at`); numbers strictly increasing; a deleted-then-recreated draft gets a NEW number (record the gap; see S7).
- Existing: test_generate.py (lock order, replace, never touch issued). Real concurrency is the extra value.
- Cleanup: none.

**F10-TC-008 (P1, REAL): the known gap, a session completed after the payslip is issued is never paid**
- Role: admin. Data: T1 Sept payslip is `issued`/`paid` (TC-001). Add a NEW Sept session for T1 (60 min) and mark it completed AFTER issue.
- Steps:
  1. Attendance on a locked session (one of the 3 paid ones) `POST $QA/sessions/<id>/attendance/` -> 409 `payroll.payslip_issued`.
  2. Create the late session (past `occurs_on` 2026-09-24), mark present.
  3. `POST generate {"year":2026,"month":9}` -> 200; `unpaid_sessions` lists T1; payslip unchanged.
  4. Generate October -> T1 October payslip does NOT contain the Sept late session.
  5. Workaround check: `POST $QA/payroll/adjustments/` bonus 6000 `effective_on` 2026-10-05 reason "late Sept session" -> appears on October payslip as an `adjustment` line.
- Expected: the session stays `payroll_locked=false` forever and has no line on any payslip; only the manual bonus pays it.
- Assertions: `scheduling_session` row (late) `payroll_locked=false`; `select count(*) from payroll_payslipline where session_id=<late>` = 0 after both months; the warning is returned only by `generate` for that month (is it surfaced on the dashboard? note in the evidence).
- Existing: test_generate.py:164 asserts the warning. The owner-visible consequence is the new evidence. Record as KNOWN-GAP, not a new bug, unless the warning is missing in the UI.
- Cleanup: none.

### Adjustments, incentives, deductions

**F10-TC-009 (P1, REAL): bonuses and deductions, effective date, single use, immutability once used**
- Role: admin. Data: fresh teacher T5 (rate 6000, Aug sessions 120 min = 12000, month Aug 2026).
- Steps: `POST $QA/payroll/adjustments/`
  A `{"teacher":T5,"kind":"bonus","amount_minor":2500,"effective_on":"2026-08-15","reason":"attendance"}`;
  B `{"kind":"deduction","amount_minor":1000,"effective_on":"2026-08-20",...}`;
  C bonus 700 `effective_on` 2026-09-02 (after Aug end); D `amount_minor` 0 / -5 / both amount and percent / neither -> 400.
  `PATCH` A to 3000 and `DELETE` B then recreate -> OK while unused. Generate Aug, issue, then `PATCH` A and `DELETE` A -> 409 `payroll.adjustment_used`.
  Generate Sept -> C is applied once; A is not applied again.
- Expected Aug: gross 12000, bonuses 3000, deductions 1000, net 14000; C is NOT on August.
- Assertions: `payroll_payadjustment.payslip_id` set for A and B only after issue; `GET adjustments/?teacher=T5&used=false` returns C; each line sign: deduction negative.
- Existing: test_rates_adjustments.py. Cleanup: none (issued).

**F10-TC-010 (P1, REAL): percentage bonus (incentives_deductions)**
- Role: admin. Switches: `incentives_deductions` on, then off. Data: T6, rate 6000, Aug-style month (use June 2026), gross 13500 via 3 sessions.
- Steps: `POST adjustments/` `{"kind":"bonus","percent_bp":1250,...}` -> 201; generate; expected bonus = round_half_up(13500*1250/10000) = 1688 (1687.5 -> 1688), line text "Bonus — 12.5 % — reason".
  `{"kind":"deduction","percent_bp":500}` -> 400 on `kind`; both amount and percent -> 400 on `amount_minor`; `percent_bp` 0 / 10001 -> 400.
  Switch off -> `POST` with percent -> 400 "switched off"; existing percent adjustment is skipped on generate and stays unused; switch on again -> it is applied.
  Percentage of a month with gross 0 (no sessions, only the adjustment) -> no line, adjustment stays pending.
- Assertions: `payroll_payadjustment.percent_bp`, `amount_minor` null; bonuses_minor 1688; net 15188.
- Existing: test_percentages.py. Cleanup: switch back on.

**F10-TC-011 (P1, REAL): deductions larger than pay refuse issue (negative net)**
- Role: admin. Data: T7, rate 6000, one 60-min session (gross 6000) in a closed month, deduction 9000.
- Steps: generate -> draft net -3000 (check how it is shown); `issue/` -> 409 `payroll.negative_net`, nothing changed. `PATCH` deduction to 2000 -> issue 200, net 4000.
- Assertions: after 409 the adjustment is unused and the session unlocked; no partial state.
- Existing: test_issue.py:131. Cleanup: none.

### Rules, fixed salary, group, reports

**F10-TC-012 (P1, REAL): fixed monthly salary**
- Role: admin. Switches: `fixed_teacher_salary` on. Data: T8 (active) and T9 (deactivated after creation), both with a rate and Sept sessions.
- Steps: `POST $QA/payroll/fixed-salaries/` `{"teacher":T8,"monthly_minor":500000,"starts_on":"2026-09-17"}` -> 201, `starts_on` snapped to 2026-09-01; second POST -> 409 `payroll.fixed_salary_exists`; `monthly_minor` 0 -> 400.
  Generate Sept: T8 payslip has one `fixed` line 500000 and all session lines amount 0, gross 500000. Complete a session after issue -> NOT in `unpaid_sessions`.
  Generate for a month with no sessions at all (e.g. 2026-11): active fixed-salary teachers get a draft (see S8); deactivated T9 does not.
  Switch off: the fixed line disappears on regenerate; the row stays.
- Assertions: `payroll_fixedsalary` one row/teacher; `payroll_payslipline.kind='fixed'`; `missing_rate` false even with no rate.
- Existing: test_fixed_salaries.py, test_build_b4b.py. Cleanup: delete fixed salaries; leave issued.

**F10-TC-013 (P1, REAL): payroll rules, weights, at-disposal, group pay**
- Role: admin; staff with `payroll_settings.update`. Switches: `payroll_rules` on, then off.
- Steps: `PATCH $QA/payroll/settings/` `{"student_absent_pay_bp":5000,"student_excused_pay_bp":2500,"at_disposal_pays":true,"group_pay":"per_class"}` -> 200.
  Bounds: `student_absent_pay_bp` -1 and 10001 -> 400; `group_pay` "x" -> 400.
  Group class: bundle kind group, class of 3 students, same teacher, same start, 60 min, rate 6000. per_student -> 3 lines of 6000 (gross 18000); per_class -> carrier (lowest session id) 6000 at the highest weight, 2 `member` lines of 0 with " — group class" suffix; mixed attendance (1 present, 2 absent) -> carrier at 100 %.
  `payroll_rules` off: `GET/PATCH settings` -> 404/403 feature-off; build uses defaults (100 %, per_student) whatever the row says.
- Assertions: `payroll_payrollsettings` single row pk 1; `payroll_payslipline.group_role`, `pay_bp`, `group_key`; `sessions` count in list excludes members.
- Existing: test_pay_rules.py, test_group_pay.py, test_api_pay_rules.py. Re-run the group case live.
- Cleanup: reset settings to 10000/10000/false/per_student.

**F10-TC-014 (P1, REAL): report deductions**
- Role: admin. Switches: `session_reports`, `payroll_rules`, `report_deductions` on. Data: T10 rate 6000; Sept: 3 sessions 60 min completed/present; 1 with a report, 2 without.
- Steps: `PATCH settings` `{"report_deduction_bp":1000}`; generate; read lines. Expected: two `report` lines of -600 each, `deductions_minor` 1200, `reports_sent` 1, `reports_missing` 2, net 18000-1200.
  Group per_class class of 4 with 2 reports missing at 6000: one report line = round(6000*1000*2/(10000*4)) = 300.
  `report_deductions` off: `PATCH` with `report_deduction_bp` -> 400; builds ignore the stored bp. 10001 -> 400.
- Assertions: line kind `report`, signed negative, session_id of the carrier; totals consistent; issue rebuilds the same.
- Existing: test_report_deductions.py. Cleanup: bp back to 0.

**F10-TC-015 (P1, REAL): currency consistency, pay_currency change**
- Role: admin. Data: T11 EGP: rate 6000, fixed salary, an adjustment, Sept sessions, plus an issued August payslip (EGP).
- Steps: change T11 `pay_currency` to USD (people profile PATCH). Generate Sept: rate in EGP does not count -> payslip `missing_rate`, T11 listed in `missing_rate`; adjustment listed in `other_currency`; fixed salary in `stale_fixed_salary`.
  `PATCH rates/<id>/` re-saves in USD (amount 6000 now means USD 60.00; check the UI warns); issue; check `payslip.currency` USD; August payslip still EGP unchanged.
  Bulk assign to T11 (USD) + T1 (EGP) -> 400 `payroll.mixed_currencies`, nothing written.
  `POST adjustments/` for T11 -> stored with currency USD.
- Assertions: every `payroll_*.currency` column equals the teacher's `pay_currency` at write time; `payroll_payslip.currency` per payslip; no cross-currency sums anywhere (projection totals per currency, TC-025).
- Existing: test_issue.py:136, test_generate_b4b.py. Cleanup: restore T11 to EGP only after the case.

**F10-TC-016 (P2, REAL): bulk rates**
- Role: admin; staff "QA Payroll Full"; a staff role with `payroll_rate.create` but not `.update` (create ad hoc). Switches: `bulk_teacher_rates` on/off.
- Steps: `POST $QA/payroll/rates/bulk/` `{"teachers":[T1,T2,T3],"rates":[{"course":null,"hourly_rate_minor":7000},{"course":C1,"hourly_rate_minor":8000}]}` -> `{created,updated}` right counts.
  One unknown course or an inactive/non-teacher id (a student id) -> 400 and NOTHING written (count rows before/after). Duplicate course in `rates` -> 400. 201 teachers -> 400. Switch off -> 403/404. create-only staff -> 403.
- Assertions: `payroll_teacherrate` counts; currency of each row = teacher currency.
- Existing: test_bulk_rates.py. Cleanup: restore T1 default to 6000.

### Payment, expense, balance

**F10-TC-017 (P1, REAL): payment state machine and guards**
- Role: admin. Data: a draft, an issued and a paid payslip (use TC-001..012 leftovers or make three teachers).
- Steps: mark-paid on draft -> 409 `payroll.not_allowed_in_status`; issue on issued/paid -> 409 same code; mark-paid on paid -> 409; `paid_on` tomorrow (2026-10-19) -> 400 on `paid_on`; `paid_on` malformed -> 400.
  `pay-to-balance/` with `teacher_balance` off -> 403/404; on -> 200 `paid_to_balance` true. Pay-to-balance on already-paid -> 409.
  Quick-login (impersonated) admin session: `pay-to-balance/` -> 403 `identity.impersonating`; `mark-paid/` and `issue/` in the same session: record the result (see S3).
- Assertions: state never goes backwards; `paid_on`, `paid_by` set once; nothing mutated on each refusal.
- Existing: test_issue.py, test_pay_to_balance.py, test_api_payslip_balance.py. Re-run live; the impersonation comparison is new.
- Cleanup: none.

**F10-TC-018 (P1, REAL): salary expense posting and finance consistency**
- Role: admin. Switches: `salary_expenses` on; also run with it off and with finance `expenses` off.
- Steps: pay one issued payslip (net 13500, EGP teacher) with `salary_expenses` on -> exactly 1 `finance_expense`. Call `mark-paid` again -> 409 and still 1 expense.
  Pay a payslip while the switch is off -> 0 expenses; switch on later -> NOT back-posted (documented).
  Net-0 payslip (fixed-salary-less, only deduction cancelling pay) -> no expense. Teacher in USD in the EGP academy (T11 after TC-015): expense currency USD; check the finance summary (`GET $QA/finance/summary/` or the finance UI) does not add USD minor units into an EGP total.
  Backdated `paid_on` 2026-01-01 on an issued September payslip -> accepted? (see S1) record the expense `spent_on`.
  Title: "Teacher salary – <name> – receipt PAY-NNNNNN".
- Assertions: `select source_id,type,amount_minor,currency,spent_on,title from academy_qa.finance_expense where source='payroll.payslip'`; unique per payslip; amount equals `net_minor`; pay-to-balance also posts the expense at payment (not at withdrawal); a withdrawal pay posts none.
- Existing: finance/tests/test_posting.py, payroll tests for `salary_expenses`. The finance totals and the currency are the new value.
- Cleanup: none.

**F10-TC-019 (P1, REAL): balance and withdrawal lifecycle**
- Role: admin and teacher T1. Switches: `teacher_balance` on. Data: T1 has a payslip paid to balance, net 20000 EGP.
- Steps:
  1. `GET $QA/payroll/balances/?teacher=T1` (admin) and `GET $QA/payroll/balances/` (T1) -> `[{"currency":"EGP","balance_minor":20000,"available_minor":20000}]`.
  2. T1 `POST $QA/payroll/withdrawals/` `{"amount_minor":8000,"currency":"EGP","notes":"rent"}` -> 201 `under_review`; balance 20000, available 12000.
  3. T1 requests 13000 -> 409 `payroll.insufficient_balance`; 12000 -> 201 (available 0); 1 more -> 409.
  4. Admin `approve` (first request) -> `approved`; `pay` with `paid_on` today -> `paid`; balance 12000, available 0. `paid_on` before the request day or tomorrow -> 400.
  5. Admin `reject` second request with `{"office_notes":""}` -> 400 on `office_notes`; with a reason -> `rejected`, available back to 12000; T1 sees the reason.
  6. T1 cancels a new `under_review` request -> `cancelled`; T1 cancels an `approved` one -> 409; admin cancels approved -> ok.
  7. Invalid: `amount_minor` 0/-1 -> 400; currency "USD" (no balance) -> 400 on `currency`; currency "egp" lower case.
  8. Admin creates for T1 with `{"teacher":T1,...}`; teacher passing another `teacher` id is ignored.
- Assertions: `payroll_withdrawalrequest` status transitions with `decided_by`, `paid_by`; derived balance equals `sum(net of paid_to_balance payslips) - sum(paid withdrawals)`; `payroll_balancelock` one row per (teacher,currency); no `finance_expense` for withdrawals.
- Existing: test_withdrawals.py, test_balances.py, test_api_withdrawals.py. Re-run live.
- Cleanup: none.

**F10-TC-020 (P1, REAL): concurrent withdrawal requests cannot overdraw**
- Role: teacher T1 (and admin on the same teacher). Data: available 20000.
- Steps: 5 simultaneous `POST withdrawals/` of 12000 (separate curl processes with the same session). Also approve+cancel and reject+approve of the same request concurrently.
- Expected: exactly ONE 201, the others 409 `payroll.insufficient_balance`; contested decisions yield one winner, the loser 409 `payroll.not_allowed_in_status`.
- Assertions: `select sum(amount_minor) from academy_qa.payroll_withdrawalrequest where status in ('under_review','approved','paid')` <= 20000; available never negative.
- Existing: none at HTTP level (unit tests use the lock only). Cleanup: cancel leftovers.

**F10-TC-021 (P1, REAL): payslip acknowledgement**
- Role: teacher T1, T2, admin. Switches: `payslip_acknowledgement` on/off.
- Steps: acknowledge a `draft` (T1 sees none -> 404), an `issued` payslip -> 409 `payroll.not_allowed_in_status`; own `paid` -> 200; again -> 409 `payroll.already_acknowledged`;
  T2 acknowledging T1's payslip -> 404; admin and staff -> 403; student/parent/anonymous -> 403/401; switch off -> 403/404; impersonated T1 -> 403.
- Assertions: `payroll_payslip.acknowledged_at` set once, amounts unchanged, `acknowledged_at` in CSV.
- Existing: test_acknowledge.py. Cleanup: none.

### Permissions and isolation

**F10-TC-022 (P1, REAL): teacher sees only their own payslips and withdrawals, and no office fields**
- Role: T1, T2. Data: T1 and T2 each have draft/issued/paid payslips in different months and withdrawals.
- Steps: T1 `GET payslips/` -> only T1's issued and paid (no draft); `?teacher=T2` still only T1's; `GET payslips/<T2 id>/` -> 404; T1 detail JSON has no `notes`, `issued_by`, `paid_by`, and no other teacher data;
  `GET payslips/?format=csv` / `Accept: text/csv` -> 403; `GET withdrawals/` own only; `GET withdrawals/<T2 id>/` -> 404; payout method/details of the withdrawal not present in the teacher view; `GET balances/?teacher=T2` returns T1's own balance.
  Projection and settings/rates/adjustments endpoints -> 403.
- Assertions: compare against `select id,teacher_id,status from academy_qa.payroll_payslip`; response ids are a subset of T1's issued/paid.
- Existing: test_api.py, test_staff_scope.py. Cleanup: none.

**F10-TC-023 (P1, REAL): permission matrix (compressed)**
- Roles: anonymous, student, parent, `qa-staff-nocode@`, `qa-staff-codes@` (student codes), `qa-staff-payread@`, `qa-staff-pay@`, `qa-supervisor@`, T1, admin.
- Endpoints (one request each, record status): `GET rates/`, `POST rates/`, `PATCH/DELETE rates/<id>/`, `POST rates/bulk/`, `GET/PATCH settings/`, `GET/POST adjustments/`, `PATCH adjustments/<id>/`,
  `GET payslips/`, `GET payslips/<id>/`, `POST payslips/generate/`, `POST .../issue/`, `.../mark-paid/`, `.../pay-to-balance/`, `GET payslips/projection/`, `GET payslips/?format=csv`, `GET balances/?teacher=`, `GET/POST withdrawals/`, `POST withdrawals/<id>/{approve,reject,pay,cancel}/`, `GET/POST fixed-salaries/`, `GET/POST student-rates/`.
- Expected: anonymous 401/403; student, parent, no-code staff 403 everywhere; payread staff: GET payslips (drafts included), CSV and projection OK, every write 403; full staff: all OK; supervisor: record (preset codes, likely none of payroll); T1: only own payslips, own balance/withdrawals, acknowledge, create/cancel own withdrawal; admin all.
  A staff user holding `payslip.update` but not `payslip.view_any` -> record.
- Assertions: no DB change from any 403 (row counts before/after); status codes tabulated in the evidence. 
- Existing: access/tests/test_routes.py (registry), test_staff_scope.py. Cleanup: none.

**F10-TC-024 (P1, REAL): cross-academy isolation, qa vs qaother**
- Role: admin of each academy. Data: in `qaother` (UTC/USD): a teacher `qo-teacher@qa.etqan.test`, rate, session, payslip generated and paid to balance, adjustment, withdrawal. Record ids in both academies.
- Steps: with the qa admin session on `qa.etqan.localhost` request `payslips/<qaother id>/`, `adjustments/<id>/`, `rates/<id>/`, `withdrawals/<id>/`, `fixed-salaries/<id>/` -> 404 (ids that exist only in qaother; also ids that exist in both with different content). Repeat reversed.
  Use the qa admin cookie against `qaother.etqan.localhost` -> 401/403 (session is per academy). `GET payslips/` in each returns only own rows. Payslip numbers/counters independent (`PAY-000001` can exist in both). `generate` in qa does not create rows in `academy_qaother`. Teacher id of qaother as `teacher` in a qa `POST rates/` -> 400 "Choose a teacher".
  `salary_expenses` posting lands only in the academy's schema.
- Assertions: row counts per schema before/after each call; `select count(*) from academy_qaother.payroll_*` unchanged by qa writes.
- Existing: none for payroll. Cleanup: leave qaother data (tag with notes "F10").

### UI smoke (Playwright, --workers=1, at most 3)

**F10-TC-025 (P1, REAL, Playwright UI smoke 1): office pays a month in the dashboard**
- Role: admin, `http://qa.etqan.localhost/app/payroll/payslips`. Data: a teacher with a rate and completed sessions in a closed month not yet generated.
- Steps: open Payroll -> Payslips, choose the month, Generate; open the draft (`/payroll/payslips/$id`), check lines/net match API; Issue; Mark paid with today's date and a note; open the print page `/payslips/$id/print`; open Rates page (rate table, bulk dialog), Adjustments page (add a bonus), Settings page.
- Expected: toasts/states match API; net shown equals `net_minor`/100 with currency EGP; status chips change; no console errors; axe: no serious violation on payslip page.
- Assertions: API `GET payslips/<id>/` and DB row agree with the screen; evidence trace.
- Existing: dashboard e2e has no payroll spec (confirm with `ls dashboard/e2e`).

**F10-TC-026 (P1, REAL, Playwright UI smoke 2): teacher reads payslip, confirms, withdraws**
- Role: T1 on `/teaching/payslips`, `/teaching/balance`. Data: paid payslip not acknowledged; payslip paid to balance (TC-019 leftover).
- Steps: open the payslip -> Confirm receipt; open My balance -> shows 20000 -> request withdrawal via dialog; cancel the request via the cancel dialog.
- Expected: messages in the academy language, amounts correct, cancel allowed only while under review; no drafts visible; no admin navigation entries.
- Assertions: API + DB `acknowledged_at`, `payroll_withdrawalrequest` rows.
- Existing: none.

### Projection, CSV, limits

**F10-TC-027 (P2, REAL): salary projection**
- Role: admin, staff payread, T1 (403). Switches: `salary_projections` on, `exchange_rates` on/off.
- Data: T1 with completed + scheduled sessions in October 2026 (future-dated and one stale past-dated still `scheduled`), USD teacher T11 with a scheduled session.
- Steps: `GET $QA/payroll/payslips/projection/` and with CSV; compare `paid_so_far_minor` with a regenerated October draft; projected = paid so far + scheduled rows priced; totals per currency EGP and USD never summed; `estimate` appears only with `exchange_rates` on; switch off -> 403/404; teacher 403; no DB writes (compare `payroll_payslip` counts).
- Expected: scheduled past-dated sessions are included (see S6).
- Existing: test_projections.py, test_api_projections.py. Cleanup: none.

**F10-TC-028 (P2, REAL): payslip list filters, CSV export and formula injection**
- Role: admin, teacher. Data: a teacher whose full name starts with `=` (e.g. `=HYPERLINK("http://evil","x")`) created via the people API.
- Steps: `GET payslips/?year=2026&month=9&status=paid&teacher=T1`; bad values (`year=1`, `month=13`, `status=x`, `teacher=0`) -> 400 on the field; `?format=csv` as admin -> file; check the name cell is prefixed with `'` (formula guard), money columns are plain integers and equal the JSON; as T1 -> 403.
- Assertions: CSV column order from `CSV_COLUMNS`, `net_minor` sums equal DB sum.
- Existing: platform csv tests, test_staff_scope.py (export). Cleanup: rename the teacher back.

**F10-TC-029 (P2, REAL): numeric limits and malformed money input**
- Role: admin. Steps: `POST rates/` `hourly_rate_minor` 9223372036854775807 (T-new) with two 60-min sessions, then `generate`; `POST adjustments/` `amount_minor` 9223372036854775807; fixed salary 9223372036854775807; withdrawal amount over int64; floats `"6000.5"`, strings, `null`, exponent `1e3`, negative zero for each money field.
- Expected: each is rejected with a 400 or accepted and handled; a 500 (DB overflow) is a defect (see S2). Float/str money -> 400, never rounded.
- Assertions: no partial rows left; HTTP status recorded for each; error body names a field.
- Existing: none. Cleanup: delete created rows.

---

## Suspected defects from code reading (highest-value items for Agent 2)

- **S1** `payslips._pay` only rejects a FUTURE `paid_on`; there is no lower bound (before the issue date or before the payslip's month), and `salary_expenses.post_salary` uses `paid_on` as the expense `spent_on`, so a backdated pay silently books a salary into a closed finance period. (TC-018)
- **S2** No upper bound on `hourly_rate_minor`, `amount_minor`, `monthly_minor` and withdrawal `amount_minor` (BigInteger columns, serializers only set `min_value`); a huge rate or two huge lines overflow `gross_minor`/`amount_minor` at generate or issue and likely return an unhandled 500. (TC-029)
- **S3** `GenerateView`, `IssueView` and `MarkPaidView` do not carry `NotImpersonating`, while pay-to-balance, acknowledgement and every withdrawal action do; `mark-paid` posts a salary expense, so a quick-login session can move money that docs/B4c C-10 says is refused. Confirm whether intended. (TC-017)
- **S4** Known gap, P7-4: a session completed after its month is issued is never paid by a session line; only `generate` returns `unpaid_sessions`, nothing persists it. Check the dashboard actually shows the warning after Generate and whether it survives a page reload. (TC-008)
- **S5** Pending adjustments are consumed by whichever month is issued first with `effective_on <= month end`. Issuing October before September moves September's adjustments onto October and the September draft loses them. Order of issue changes who gets what. (TC-009 variant)
- **S6** Projection prices every `scheduled` session in the current month including past-dated ones nobody marked, overstating "projected"; also each projection runs two builds per teacher with no snapshot. (TC-027)
- **S7** Draft numbers are taken from the counter when a draft is created; deleting a draft with no activity and recreating it consumes a new `PAY-` number, so receipt numbers (also used in the expense title) can have gaps. (TC-007)
- **S8** `_fixed_teacher_ids` gives every active fixed-salary teacher a draft for ANY month from 2000 to 2100 allowed by `MonthInput` (including future months); no end date on a fixed salary, and an active teacher who has left keeps getting a full-salary draft until deactivated. (TC-012)
- **S9** `salary_expenses` posts in the teacher's `pay_currency`, not the academy currency; check whether finance totals/summary treat a USD salary in an EGP academy correctly. (TC-018)
- **S10** Changing a teacher's `pay_currency` makes rates, adjustments and fixed salaries silently not count; `PATCH rates/` re-saves the same number in the new currency (6000 EGP minor becomes USD 60.00) without any conversion or warning. Product question. (TC-015)
- **S11** Negative-net trap: a payslip whose deductions exceed pay cannot be issued and there is no carry-forward; the only way out is editing or deleting the deduction. Product question. (TC-011)

## Untestable here

See `coverage-gaps.md` section F10: live payout rails (none exist; payout is manual), exchange rate providers beyond the simulator, and clock-dependent `month_over` for a month that is genuinely in the future/past boundary (no clock control in a live stack).

---

## Added by Agent 2 (validation, 2026-10-19)

**F10-TC-030 (P1, REAL): double-submit races on issue, mark-paid and pay-to-balance**
- Role: two admin sessions. Data: T9 (user 43) September 2026 draft (fixed salary 300000 EGP).
- Steps: two parallel `POST .../issue/`; then `mark-paid/` and `pay-to-balance/` in parallel on the issued payslip.
- Expected: each race has one 200 and one 409 `payroll.not_allowed_in_status`; exactly one `finance_expense` row equal to `net_minor`.
- Why added: TC-017/018 cover the guards only sequentially; a double click or two office users paying the same payslip is a real
  money risk (double expense / paid twice).

Spec corrections found while executing (test-side, product right): the session report endpoint is `PUT /sessions/<id>/report/`
(not POST); `unpaid_sessions`, `missing_rate`, `other_currency`, `stale_fixed_salary` list teachers (`{id, full_name}`), not
sessions; the attendance endpoint is `POST /sessions/<id>/attendance/`; scheduling routes are mounted at `/api/v1/sessions/...`;
people created through `create_person(invite=False)` need a verified `account_emailaddress` before they can sign in.

## Results (Agent 2, 2026-10-19)

Backend adff9c9, dashboard 5ed775d (branch qa/campaign-2026-10). Every money value checked as an integer in minor units with its
currency (EGP in `qa`, USD for T11 after the switch and for qaother). Evidence paths are relative to `qa/evidence/F10/`;
scripts in `scripts/` (sec*.py, setup*.py), log `qa/logs/F10/agent2.md`.

| Case | Result | Tag | Evidence | Note |
|---|---|---|---|---|
| TC-001 | PASS | REAL | tc001.txt | 6000/4500/3000 → 13500 EGP; issue, paid, ack; 3 sessions locked; 1 expense 13500 EGP |
| TC-002 | PASS | REAL | tc002.txt | lines 9259/6173/4115/4629/2315, gross 26491 = sum, all ints |
| TC-003 | PASS | REAL | tc003.txt | Sept pays (a),(e) only; 23:30/00:30 Cairo boundary correct; at-disposal 100 % when on |
| TC-004 | PASS | REAL | tc004.txt | 6000/9000/12000/12000; switch off → 6000/9000, student-rates 404, row kept |
| TC-005 | PASS | REAL | tc005.txt | 409 `payroll.missing_rate`, nothing changed; issue after rate 6000 |
| TC-006 | PASS | REAL | tc006.txt | October 409 `month_not_over`; mark-paid draft 409; bad months 400 by field |
| TC-007 | PASS | REAL | tc007.txt | 2 + 4 parallel generates, no duplicates; DB unique `payroll_one_payslip_per_teacher_month`; S7 gap recorded |
| TC-008 | PASS | REAL | tc008.txt, pw/s4-ui.json | KNOWN-GAP: late session never paid, `unpaid_sessions` lists T1; adjustment workaround works |
| TC-009 | PASS | REAL | tc009.txt | gross 12000 + 3000 − 1000 = 14000; used adjustment 409; C applied in Sept only |
| TC-010 | PASS | REAL | tc010.txt | 12.5 % of 13500 = 1688 (half up), net 15188; switch off waits; gross-0 stays pending |
| TC-011 | PASS | REAL | tc011.txt | net −3000 → 409 `negative_net`, no partial state; after edit net 4000 |
| TC-012 | PASS | REAL | tc012.txt | fixed 500000 snapped to 09-01; 409 exists; deactivated excluded; S8 confirmed |
| TC-013 | PASS | REAL | tc013.txt, tc013-014-016-rerun.txt | per_student 9000 / per_class 3000 + 2 members of 0; rules off → 100 % (38065) |
| TC-014 | PASS | REAL | tc014.txt, tc013-014-016-rerun.txt | 2 × −600, sent 1 / missing 2, net 16800; group carrier −300 once; off → 400 |
| TC-015 | PASS | REAL | tc015.txt | USD switch: missing_rate / other_currency / stale_fixed_salary; issued USD; Aug stays EGP; mixed bulk 400 |
| TC-016 | PASS | REAL | tc016.txt, tc013-014-016-rerun.txt | created 3 / updated 3; every bad body 400 with no rows; create-only staff 403 |
| TC-017 | PASS | REAL | tc017.txt | state machine guards; paid_on tomorrow 400; pay-to-balance off 404; quick-login refusals (S3) |
| TC-018 | PASS (retest 1) | REAL | tc018.txt, retest-1/api-db.txt | was FAIL → QA-029 VERIFIED 2026-10-19; expense posting, idempotence, switch-off, net-0 and USD currency all correct; backdated paid_on accepted → ETQAN-QA-029 (P2) |
| TC-019 | PASS | REAL | tc019.txt | balance 20000 → 12000/0 → 11900; reject needs reason; cancel rules; derived balance = API |
| TC-020 | PASS | REAL | tc020.txt | 5 parallel requests → exactly one 201, 4 × 409; approve/reject and pay/cancel races: one winner |
| TC-021 | PASS | REAL | tc021.txt | draft 404, issued 409, own paid 200 once, others 403/404, switch off 404; CSV "Receipt confirmed at" |
| TC-022 | PASS | REAL | tc022.txt | teacher sees own issued/paid only, no office fields, CSV 403, other ids 404 |
| TC-023 | PASS | REAL | tc023.txt | 29 endpoints × 11 roles tabulated; no DB change on any refused call |
| TC-024 | PASS | REAL | tc024.txt | qa ↔ qaother: own-schema rows only, foreign ids 404, cross-host cookie 403, counters independent |
| TC-025 | PASS | REAL (Playwright) | pw-run5.txt, pw/tc025-ui.json, pw/tc025-paid.png, pw/tc025-print.png | generate → issue → mark paid in UI; API 6000 EGP paid; axe: 0 serious |
| TC-026 | FAIL | REAL (Playwright) | pw-run5.txt, pw/tc026-ui.json, pw/tc026-cancel-toast.json | receipt confirmed, withdrawal 1000 created and cancelled; no cancel toast → ETQAN-QA-031 (P4) |
| TC-027 | PASS | REAL | tc027.txt | per-currency rows, so-far = October draft net 12000, CSV, estimate null with exchange_rates off, no writes; S6 confirmed |
| TC-028 | PASS | REAL | tc028.txt | filters + 400s by field; formula cell `'=HYPERLINK`; CSV net sum 898465 = DB |
| TC-029 | FAIL | REAL | tc029.txt | no 500; malformed money 400; int64-max inputs accepted and one teacher blocks the month's generate → ETQAN-QA-030 (P3) |
| TC-030 | PASS | REAL | tc030.txt | parallel issue / mark-paid vs pay-to-balance: one winner each, one expense 300000 |

Totals: 30 executed, 27 PASS, 3 FAIL (P2 ×1, P3 ×1, P4 ×1), 0 BLOCKED. REAL 30, SIMULATED 0, FAKE 0.

### Suspected defects, verdicts

| Item | Verdict | Evidence |
|---|---|---|
| S1 backdated `paid_on` | **CONFIRMED** → ETQAN-QA-029 (P2): Sept payslip paid on 2026-01-01, expense `spent_on` 2026-01-01 | tc018.txt |
| S2 money upper bounds / overflow | **CONFIRMED in part** → ETQAN-QA-030 (P3): no 500 (overflow surfaces as 400), but int64-max inputs accepted and Generate fails for every teacher of the month | tc029.txt |
| S3 generate/issue/mark-paid without NotImpersonating | **REFUTED (by design, unreachable)**: B4c spec C-10 leaves mark-paid as is; quick login targets only teacher/student/parent, so impersonated issue/mark-paid/generate are 403 by codes; pay-to-balance 403, acknowledge 403 `identity.impersonating` | tc017.txt |
| S4 unpaid-sessions warning | **CONFIRMED as KNOWN-GAP**: the dashboard shows "Sessions of QA teacher were completed after their payslip was issued…" after Generate, gone after a reload (not persisted). Documented behaviour, no bug | pw/s4-ui.json, pw/s4-after-generate.png |
| S5 pending adjustment consumed by first issued month | **CONFIRMED, documented** ("pending adjustments with effective_on ≤ month end"): adjustment C (700) shows on both the Sept and Oct drafts; whichever is issued first takes it. No double pay (used once, TC-009). Product question, not filed | tc009.txt |
| S6 projection prices stale past-dated scheduled sessions | **CONFIRMED, as coded/documented**: T1 projected 33000 includes session 51 (2026-10-10, still scheduled): 210 scheduled minutes. Product question, not filed | tc027.txt |
| S7 receipt number gaps | **CONFIRMED, no documented gapless rule**: TX draft PAY-000009 removed then recreated as PAY-000014. Observation, not filed | tc007.txt |
| S8 fixed-salary drafts for any month | **CONFIRMED, documented** ("active teachers with a counting fixed salary"): generate 2099-12 creates T8's 500000 draft (PAY-000028); deactivated T9 excluded; drafts cannot be issued before the month ends. Observation, not filed | tc012.txt |
| S9 USD salary in an EGP academy | **REFUTED**: expense stored in USD and `/finance/summary/` keeps per-currency totals (EGP 33500, USD 6000), never summed | tc018.txt |
| S10 pay_currency change re-saves numbers | **CONFIRMED, documented** ("every rate … is saved in that currency; a row left in an old currency does not count"): `PATCH rates/8/` 6000 became USD 6000 with no conversion. Product question, not filed | tc015.txt |
| S11 negative-net trap | **CONFIRMED, documented** (409 `payroll.negative_net`, no carry-forward). Product question, not filed | tc011.txt |

Other observations (no bug): lower-case `"egp"` on a withdrawal is accepted and stored as EGP; integral floats (`1000.0`, `-0.0`)
are coerced to integers by DRF while `"6000.5"`, `"1e3"`, `true` are refused; a staff role with `payslip.update` but not
`payslip.view_any` reaches issue/mark-paid by id (409/400 from the service); copied texts (line descriptions, expense title) are in
the academy's default language (Arabic) by design. Test data left in place: QA teachers T2–T14 + TX (users 36–49), staff 50–53,
roles 25–28, group bundle 1, payslips up to PAY-000037 incl. drafts for 2026-11 and 2099-12, qaother teacher 4 with PAY-000001.
