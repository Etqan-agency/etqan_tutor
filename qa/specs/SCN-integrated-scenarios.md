# SCN: Integrated scenarios B to E (enrolment, teacher operations, parent view, one simulated month)

Author: Agent 1 (LEAN mode, read-only). This spec approves nothing. Written 2026-10-19 against backend adff9c9 / dashboard 5ed775d (branch qa/campaign-2026-10).
Built from the passed specs F05, F06, F08, F09, F10 and `docs/features/{notifications,sessions,subscriptions,payroll,billing,wallet}.md`. The per-feature rules are
already tested there; every case below chains modules and asserts that the numbers agree **across** them (API and DB). Reuse the F05/F06/F08/F09/F10
helpers and endpoints; do not re-research them.

Academy `qa` (Africa/Cairo, EGP). Cross-tenant checks use `qaother` (UTC, USD). Never touch demo/other/khaled/journey-*.
Provider tags: REAL = our code, DB, local Mailpit SMTP. No case needs SIMULATED, FAKE or BLOCKED; wallet top-ups are manual cash (REAL), no gateway.

## 1. Setup (run once, in order)

All SCN data uses fresh people with the prefix `SCN` so it cannot collide with F05/F06/F09/F10 fixtures (their Sept 2026 payslips for `qa-teacher` already exist).
Helpers: copy the F09 `login`/`api`/`q`/`anon` shell functions (spec F09 Setup) into `scratchpad/scn/env.sh`, jar dir `scratchpad/scn/`, `DC=~/.etqan-qa-tools/dc.sh`.

1. **Switches on qa:**
   `$DC exec -T django python manage.py set_features qa --on families parents invoices payment_receipts balances system_codes supervision session_reports teacher_attendance manual_sessions extra_sessions activity_log payroll_rules salary_projections report_deductions salary_expenses payslip_acknowledgement weekly_schedules postponement auto_notifications notification_preferences`
   (if a code is unknown, `set_features` prints it; check the list in `backend/etqan/platform/features.py`; `auto_notifications` must be ON for TC-017). Record `select features from public.tenants_academy where subdomain='qa'`.
2. **Academy and billing settings:** `PATCH /academy/settings/ {"generation_horizon_days":21,"auto_invoice_on_subscription":true,"invoice_due_days":7,"absent_consumes_session":false,"excused_consumes_session":false}` (record before values). `PATCH /payroll/settings/ {"student_absent_pay_bp":5000,"student_excused_pay_bp":2500,"at_disposal_pays":false}` (record before). `PATCH /billing/settings/ {"local_payment_enabled":true}`.
3. **Logins:** admin, supervisor, `qa-teacher` (teacher T1), `qa-parent` (existing parent, NOT used as SCN parent), plus the new users below once their passwords are set
   (`tenant_command shell --schema=academy_qa -c "...set_password('QA-People-2026!')"` as in F09 Setup 3). qaother admin on `http://qaother.etqan.localhost`.
4. **Catalogue (admin):** course `SCN-C1` (`POST /catalogue/courses/ {"name_ar":"سكن","name_en":"SCN Quran","teacher_ids":[T1,T2]}`), package `SCN-PKG`
   (`POST /catalogue/packages/ {"name_ar":"س","name_en":"SCN Pkg 2x4w","sessions_per_week":2,"session_minutes":60,"duration_value":1,"duration_unit":"month","price_minor":150000,"currency":"EGP"}`; `sessions_total` must read 8).
5. **Teachers:** T1 = `qa-teacher`; T2 = `POST /people/teachers/ {"user":{"full_name":"SCN Teacher Two","email":"scn-teacher2@qa.etqan.test"},"profile":{}}` ; T3 = `SCN Payroll Teacher` (`scn-teacher3@`), used only for the month in TC-014..018.
   Rates: `POST /payroll/rates/ {"teacher":T3,"hourly_rate_minor":6000}`; T1 and T2 rate 6000 too.
6. **Pre-run snapshot (record in evidence):** `select count(*) from billing_invoice; ... billing_payment; ... wallet_walletentry; ... scheduling_session; ... payroll_payslip` and `GET /billing/summary/`, so TC-018 can reconcile **deltas**, not absolutes.
7. Do not run pytest while Playwright runs. Clear the cache before TC-011: `$DC exec -T django python manage.py shell -c "from django.core.cache import cache; cache.clear()"`.

Names: `FAM-A` (family under test), `FAM-B` (second family, isolation), `SA1`/`SA2` (students of FAM-A), `PA` (FAM-A parent/payer), `SB1`/`PB` (FAM-B), `SUB1`/`SUB2` (subscriptions of SA1/SA2).
Cleanup policy: the qa schema is disposable; hand-added unmarked sessions can be deleted, marked/invoiced/paid rows stay. State in each case what is left.

## 2. Test cases (18: P1 16, P2 2; Playwright UI smoke: TC-007, TC-012)

### B. Student enrolment

#### SCN-TC-001: Admin enrols a family (parent + two students + family with payer)  [P1, REAL]
- **Role:** admin. **Data:** none yet.
- **Steps:**
  1. `POST /people/students/ {"user":{"full_name":"SCN Student A1","email":"scn-a1@qa.etqan.test"},"profile":{"country":"EG","date_of_birth":"2014-05-10"}}` -> SA1; same for `SCN Student A2` -> SA2.
  2. `POST /people/parents/ {"user":{"full_name":"SCN Parent A","email":"scn-parent-a@qa.etqan.test"}}` -> PA; `POST /people/students/SA1/guardians/ {"parent_id":PA}` and for SA2.
  3. `POST /people/families/ {"name":"SCN Family A","student_ids":[SA1,SA2],"payer_id":PA}`; `GET /people/families/<id>/`; `GET /billing/payers/?student=SA1`.
  4. Repeat for FAM-B: `SCN Student B1`, `SCN Parent B`, `SCN Family B` (payer PB).
  5. Mailpit: `GET http://localhost:8025/api/v1/search?query=to:scn-parent-a@qa.etqan.test` (invites).
- **Expected:** 201s; family lists both students, `payer_needs_choosing=false`; `billing/payers` for SA1 returns PA. A student already in FAM-A cannot join FAM-B (400). Invites for the parent and both students reach Mailpit (REAL).
- **Assert (DB):** `identity_user` roles (student x2, parent x1), `identity_studentprofile`, guardian link rows (2), one family row with 2 members and `payer` = PA; unique lower(email) holds; one unverified `account_emailaddress` per user.
- **Cleanup:** none. Passwords are set per Setup 3 for PA, PB, SA1, SB1.

#### SCN-TC-002: Package + subscription + weekly slots generate sessions with correct local and UTC times across the Cairo DST change  [P1, REAL]
- **Role:** admin. **Switches:** `weekly_schedules`, `generation_horizon_days=21`. **Data:** SA1, SA2, T1, SCN-C1, SCN-PKG.
- **Steps:** (today is Mon 2026-10-19; Egypt leaves DST on Fri 2026-10-30 00:00, so UTC+3 becomes UTC+2)
  1. `POST /subscriptions/ {"student":SA1,"course":C1,"teacher":T1,"package":PKG,"starts_on":"2026-10-19","slots":[{"weekdays":[0,3],"start_time":"18:00"}]}` -> SUB1. SA2 / T2 with `"slots":[{"weekdays":[1,4],"start_time":"17:00"}]` -> SUB2.
  2. `GET /subscriptions/SUB1/` then `GET /subscriptions/SUB1/sessions/`; `GET /subscriptions/SUB1/` again for `sessions_remaining`.
  3. If the 21-day horizon has not produced everything: `POST /schedule/generate/ {"from":"2026-10-19","to":"2026-11-30","subscription":SUB1}`.
- **Expected:** SUB1 sessions on Mon/Thu 18:00 Cairo: Mon 10-19, Thu 10-22, Mon 10-26, Thu 10-29 at `starts_at` 15:00Z; Mon 11-02, Thu 11-05 at 16:00Z (wall clock stays 18:00, the UTC instant moves one hour). 8 sessions total (package size), `kind=regular`, `status=scheduled`, `minutes=60`, `occurs_on` = Cairo local date, none before `starts_on`. `sessions_remaining=8`. SUB2 Tue/Fri 17:00 local: Fri 10-30 17:00 is 15:00Z (UTC+2 after midnight change), Tue 10-20 is 14:00Z. Teacher T1 `GET /schedule/today/` shows only SUB1's session of the day.
- **Assert (DB):** `select occurs_on, starts_at at time zone 'UTC', starts_at at time zone 'Africa/Cairo' from scheduling_session where subscription_id=SUB1 order by starts_at` matches the table above; `count(*)=8`; all `starts_at` timestamptz; no session has `occurs_on` that differs from its Cairo date.
- **Edge:** a slot at Fri 00:30 on 2026-10-30 (ambiguous hour) generates exactly one session (covered by F06-TC-011; here only confirm it does not shift SUB1).
- **Cleanup:** none (SUB1/SUB2 are used by every later case).

#### SCN-TC-003: Subscription creates the right invoice for the right payer; regenerate and renew never duplicate  [P1, REAL]
- **Role:** admin. **Switches:** `invoices`, `auto_invoice_on_subscription`.
- **Steps:** after TC-002: `GET /billing/invoices/?student=SA1`; `GET /billing/invoices/<id>/`; `POST /schedule/generate/` twice more for SUB1; `GET /billing/invoices/?student=SA1`; `GET /subscriptions/SUB1/sessions/`.
- **Expected:** exactly one invoice per subscription: `amount_minor=150000` (integer), `currency=EGP`, `due_on=today+7`, `payer`=PA (via family), `status=unpaid`, number `INV-NNNNNN`. A second `generate` returns 0 new sessions and creates no invoice; the session count stays 8.
- **Assert (DB):** `select id, student_id, payer_id, amount_minor, currency, status from billing_invoice where subscription_id in (SUB1,SUB2)` (2 rows, 150000 each); `count(*) from scheduling_session where subscription_id=SUB1` = 8 after three generate calls; invoice counter advanced by exactly 2 since the snapshot.
- **Cleanup:** none.

#### SCN-TC-004: Scheduling conflicts and inactive people are refused or reported  [P2, REAL]
- **Role:** admin.
- **Steps:** `POST /subscriptions/` for a third student (SCN Student A3, add to FAM-A) with T1 at the SAME slot as SUB1 (Mon 18:00) ; read the `conflicts` of `POST /schedule/generate/`; `POST /people/teachers/<T2>/deactivate/` is NOT done (T2 is needed); instead deactivate a throwaway teacher `SCN Teacher Gone` and try `POST /subscriptions/` with it.
- **Expected:** conflict is reported (not silently double-booked) with the colliding session ids, or the sessions are created with a flagged conflict per F06 rule; the subscription with the deactivated teacher is refused 400. SUB1 sessions unchanged.
- **Assert (DB):** no two non-cancelled sessions of T1 overlap unless flagged: `select a.id,b.id from scheduling_session a join scheduling_session b on a.teacher_id=b.teacher_id and a.id<b.id and a.status<>'cancelled' and b.status<>'cancelled' and tstzrange(a.starts_at,a.starts_at+a.minutes*interval '1 minute') && tstzrange(b.starts_at,b.starts_at+b.minutes*interval '1 minute')` returns only the intentionally conflicting pair(s).
- **Cleanup:** cancel the SA3 subscription (`POST /subscriptions/<id>/cancel/`); it also voids/keeps its invoice per F09, record which.

#### SCN-TC-005: The whole enrolment chain is invisible and un-usable across academies  [P1, REAL]
- **Role:** qa admin, qaother admin.
- **Steps:** in qaother create a student `SCN Other Student`, course, package, subscription and invoice (USD). As qa admin: `GET/PATCH` every qaother id on `/people/students/`, `/subscriptions/`, `/sessions/`, `/billing/invoices/`; `POST /subscriptions/` in qa using qaother's student/course/package/teacher ids; `POST /schedule/generate/ {"subscription":<qaother id>}`. As qaother admin: same against SUB1, SA1, the SA1 invoice, the family. `GET /billing/summary/` on both.
- **Expected:** every foreign id 404 (or 400 "does not exist" on create), no 500, no data in either list. Summaries do not include each other's rows (qa EGP only, qaother USD only).
- **Assert (DB):** `select count(*)` of qa rows unchanged for SCN data; `scheduling_session` in `academy_qaother` has no SUB1 rows; both summaries equal their own-schema SQL sums.
- **Cleanup:** none.

### C. Teacher operations

#### SCN-TC-006: A teacher sees only their own sessions, students and reports  [P1, REAL]
- **Role:** T1 (`qa-teacher`), T2 (`scn-teacher2`), admin. **Data:** SUB1 (T1), SUB2 (T2).
- **Steps:** as T1: `GET /sessions/`, `GET /sessions/<SUB1 session>/`, `GET /sessions/<SUB2 session>/`, `GET /schedule/today/`, `GET /people/students/`, `GET /subscriptions/`, `GET /billing/invoices/`, `GET /payroll/payslips/`. Repeat as T2.
- **Expected:** T1 lists only sessions with `teacher=T1` (SUB1's 8 + earlier QA fixtures), foreign session 404 (not 403, no existence leak). Students/subscriptions lists contain only T1's students (SA1, not SA2). Invoices 403. Payslips list only T1's own. T2 mirrors it.
- **Assert (DB):** `count` of the API list equals `select count(*) from scheduling_session where teacher_id=T1 and archived_at is null`; no SA2 row id in T1 responses; no 5xx in `docker logs`.
- **Cleanup:** none.

#### SCN-TC-007: Teacher marks present / absent / excused and the package, status and activity log follow (UI smoke 1)  [P1, REAL]
- **Role:** T1. **Switches:** `teacher_attendance`, `activity_log`. **Data:** SUB1 has 8 future sessions, so create three PAST sessions for SUB1 with `POST /sessions/regular/ {"subscription":SUB1,"occurs_on":"<yesterday>","start_time":"10:00"}` at 10:00, 11:00, 12:00 (call them U1..U3), plus an extra session U4 `POST /sessions/extra/` yesterday 13:00 (`pays_teacher=true`). `sessions_remaining` before = R.
- **Steps:** (UI) Playwright `--workers=1`: log in `qa.etqan.localhost/app/` as T1, Teaching > Sessions, press Present on U1, confirm the toast. (API) `POST /sessions/U2/attendance/ {"student_attendance":"absent"}`; U3 `{"student_attendance":"excused"}`; U4 `{"student_attendance":"present","teacher_attendance":"present"}`; a future session `{"student_attendance":"present"}`; `{"student_attendance":"late"}`; T1 on SUB2's session; `GET /subscriptions/SUB1/`.
- **Expected:** U1 present -> 200 `completed`, `sessions_remaining=R-1`. U2 absent and U3 excused complete the session but do NOT consume (settings false); U4 (extra) does not consume. Future session 409 `scheduling.not_started`; `late` 400 (there is no late status; late = `session.late` notice only, see gaps); SUB2 session 404. UI toast and row status match the API.
- **Assert (DB):** `student_attendance`/`status`/`marked_by_id`(=T1 user)/`marked_at` for U1..U4; four `scheduling_sessionactivity` rows `action='attendance'`; consumption SQL `status='completed' and student_attendance='present' and teacher_attendance<>'absent' and kind in ('regular','compensation') and compensated=false` equals `package size - sessions_remaining`.
- **Cleanup:** none (these are the evidence for TC-016/TC-018 deltas: note U1..U4 ids).

#### SCN-TC-008: Teacher writes a session report; missing-report list, privacy and the payroll switch interplay  [P1, REAL]
- **Role:** T1, T2, admin, SA1, PA. **Switches:** `session_reports`.
- **Steps:** as T1 `GET /reports/missing/` (U1 listed); `PUT /sessions/U1/report/ {"behaviour":5,"participation":4,"notes":"SCN good"}`; PUT 0, 6, "a" ; `GET /reports/missing/` again; T2 `PUT /sessions/U1/report/`; SA1 and PA `GET /sessions/U1/report/`; admin GET.
- **Expected:** report saved (200), U1 leaves the missing list; 0/6/"a" -> 400; T2 404; the student/parent read follows the F08 rule (record what they see; no other student's report). Notes are stored verbatim and not interpreted as HTML in the API.
- **Assert (DB):** one `scheduling_sessionreport` row for U1 with 5/4 and the notes; `report.missing` input for the scan (`reports_missing`) excludes U1 afterwards.
- **Cleanup:** none.

#### SCN-TC-009: Supervisor view and marking  [P2, REAL]
- **Role:** `qa-supervisor`, T1, admin. **Switches:** `supervision`.
- **Steps:** admin `PATCH /sessions/<SUB1 Mon session>/ {"supervisor_id":<supervisor user id>}`; supervisor `GET /supervision/`; `POST /supervision/<id>/open/`; `POST /supervision/<id>/attendance/ {"supervisor_attendance":"present"}`; T1 `GET /supervision/`; supervisor `GET /sessions/` and tries `POST /subscriptions/`, `DELETE /sessions/<id>/`.
- **Expected:** the supervisor sees only sessions assigned to them; open/attendance 200 and stored; the teacher gets 403/empty on supervision; the supervisor cannot create subscriptions or delete sessions (403), per the Supervisor preset.
- **Assert (DB):** `supervisor_attendance='present'` and an activity row for that session; no change to `student_attendance` or `status`.
- **Cleanup:** unassign the supervisor (`PATCH ... {"supervisor_id":null}`).

### D. Parent experience

#### SCN-TC-010: A parent sees only their own children's sessions and attendance  [P1, REAL]
- **Role:** PA, PB, `qa-parent` (an unrelated third family), SA1 (student), admin.
- **Steps:** as PA: `GET /sessions/`, `GET /sessions/<U1>/` (SA1), `GET /sessions/<U2>/`, `GET /sessions/<SA2 session>/`, `GET /sessions/<SB1 session>/`, `GET /subscriptions/`, `GET /people/students/`, `GET /people/families/`. As PB and `qa-parent` the same. As SA1 `GET /sessions/` and SA2's session.
- **Expected:** PA sees the sessions and attendance of SA1 and SA2 (U1 completed/present, U2 absent) and nothing of FAM-B or `qa-parent`'s child (404); students list = SA1, SA2 only; PB sees only SB1; SA1 sees only own sessions, not SA2's (siblings are separate students). Teacher notes/internal fields (`cancel_reason`, activity log, host link) are not in the parent payload.
- **Assert (DB):** the API session id set for PA equals `select id from scheduling_session where student_id in (SA1,SA2) and archived_at is null`; zero FAM-B ids in any PA response; payload keys exclude `meeting_url` host fields and `marked_by` internals (record what is exposed).
- **Cleanup:** none.

#### SCN-TC-011: A parent sees only their own invoices and pays from the wallet; other families are invisible  [P1, REAL]
- **Role:** PA, PB, admin. **Switches:** `invoices`, `balances`.
- **Steps:** as PA: `GET /billing/invoices/`, `GET /billing/invoices/<SA1 invoice>/`, `GET /billing/invoices/<FAM-B invoice>/`, `GET /billing/payments/`, `GET /billing/summary/`, `GET /wallet/mine/`, `GET /wallet/students/SB1/`, `POST /billing/invoices/<SA1 invoice>/payments/ {"amount_minor":1000,"method":"cash","paid_on":"<today>"}`. Admin tops up SA1: `POST /wallet/students/SA1/top-ups/ {"amount_minor":30000,"currency":"EGP","method":"cash","paid_on":"<today>"}`. PA: `POST /wallet/invoices/<SA1 invoice>/pay/ {"amount_minor":30000}`; again with `{"amount_minor":999999999}`.
- **Expected:** PA lists exactly the invoices of SA1 and SA2 (2 rows; each shows `balance_minor`); FAM-B invoice 404; payments/summary 403; recording a cash payment is office-only (403); the wallet pay moves 30000 from the wallet to the invoice (invoice `balance_minor` 120000, status `partial`); the oversize amount 400/409 with the wallet unchanged.
- **Assert (DB):** `wallet_wallet.balance_minor = sum(wallet_walletentry.amount_minor)`; one wallet debit entry linked to a `billing_payment` with `method='wallet'`; invoice `paid` sum = 30000; PA's top-up cash payment counted as revenue once, the wallet payment not (F09 rule).
- **Cleanup:** none (this wallet money is part of TC-015).

#### SCN-TC-012: Parent portal shows the children's schedule, attendance and invoice in the UI (UI smoke 2)  [P1, REAL]
- **Role:** PA. **Data:** after TC-007/TC-011.
- **Steps:** Playwright `--workers=1`: log in `qa.etqan.localhost/app/` as PA; open the schedule/sessions page, then the invoices page; check an axe pass is not required. Then try the URL of a FAM-B session and invoice directly.
- **Expected:** the SA1/SA2 upcoming sessions display local Cairo times (18:00, 17:00), U1 shows present and U2 absent, the invoice shows 150000 as the academy formats it (1,500.00 EGP) with the 30000 wallet payment; FAM-B URLs show a not-found page with no data. The numbers match the API of TC-010/011.
- **Assert (DB/API):** the displayed totals equal `billing_invoice.amount_minor` and `balance_minor`; session count equals the API list; Playwright trace and screenshot saved in evidence.
- **Cleanup:** none.

#### SCN-TC-013: Parent and student write-denial matrix across modules  [P1, REAL]
- **Role:** PA, SA1, PB, anonymous.
- **Steps:** PA/SA1: `POST /sessions/U2/attendance/`, `POST /sessions/extra/`, `POST /subscriptions/`, `PATCH /subscriptions/SUB1/`, `POST /subscriptions/SUB1/cancel/`, `POST /billing/invoices/`, `POST /billing/invoices/<id>/void/`, `POST /wallet/students/SA1/top-ups/`, `POST /wallet/students/SA1/adjustments/`, `GET /payroll/payslips/`, `GET /payroll/rates/`, `GET /finance/summary/`, `GET /notifications/log/`, `POST /people/students/`. PB the same against FAM-A ids. Anonymous: a sample.
- **Expected:** 403 for the whole write set (404 for foreign ids), 401 for anonymous, no body leaks internal ids; allowed exceptions only: parent/student postpone of their own future session if `postponement` is on (record it) and wallet pay of their own invoice.
- **Assert (DB):** row counts of `scheduling_session`, `billing_invoice`, `billing_payment`, `wallet_walletentry`, `payroll_payslip` unchanged by the whole matrix; `U2.student_attendance` still `absent`.
- **Cleanup:** none.

### E. One simulated month (September 2026, closed) plus today

Fixture "SCN-MONTH" (build with a script; hand-add APIs accept past dates, record ids in evidence). Student SA1, course C1, teacher **T3** (rate 6000/h = 100/min), all `kind=regular` hand-added to a subscription `SUB3` (SA1, T3, SCN-PKG, `starts_on` 2026-09-01, no slots) unless noted. 13 sessions in Sept 2026, marked via `POST /sessions/<id>/attendance/`:

| Id | Date | Min | Student | Teacher | Notes |
|---|---|---|---|---|---|
| M1-M6 | 09-02,04,09,11,16,18 | 60 | present | present | 6 x 6000 = 36000 |
| M7 | 09-23 | 45 | present | present | 4500 |
| M8 | 09-25 | 60 | absent | present | absent weight 5000 bp -> 3000 |
| M9 | 09-28 | 60 | excused | present | excused weight 2500 bp -> 1500 |
| M10 | 09-29 | 60 | present | **absent** | pays 0, not consumed |
| M11 | 09-30 | 60 | (cancelled `POST /sessions/<id>/cancel/` with a reason) | - | pays 0, not consumed |

Expected from rules: completed sessions = 10 (M1-M10), cancelled 1; consuming = M1-M7 = 7 (absent/excused flags false, M10 teacher absent); payroll gross for T3 = 36000+4500+3000+1500 = **45000** (9 paying lines, M10/M11 contribute 0).

#### SCN-TC-014: Month of attendance: session states, consumption and per-status counts agree between API and DB  [P1, REAL]
- **Role:** admin (marking), T3 (own list).
- **Steps:** build the fixture; `GET /sessions/?teacher=T3&from=2026-09-01&to=2026-09-30`; `GET /subscriptions/SUB3/`; as T3 `GET /sessions/`; `GET /reports/missing/` as T3.
- **Expected:** 11 sessions (10 completed, 1 cancelled), `sessions_remaining` = 8 - 7 = 1 on SUB3; T3 sees the same 11 and nothing else; M1..M10 are in the missing-report list until reports are written (`session.report.missing` window is 7 days, so older ones may not appear; record).
- **Assert (DB):** `select status, student_attendance, teacher_attendance, count(*) from scheduling_session where subscription_id=SUB3 group by 1,2,3` matches the table; consumption SQL (TC-007) = 7; `payroll_locked=false` for all.
- **Cleanup:** none.

#### SCN-TC-015: Invoices paid partially, then by wallet, then in full; every balance reconciles  [P1, REAL]
- **Role:** admin, PA. **Data:** the SUB1 invoice INV1 (150000, from TC-003; 30000 already paid from the wallet in TC-011, so the balance is 120000) and the SUB2 invoice INV2 (150000).
- **Steps:**
  1. INV1: `POST /billing/invoices/INV1/payments/ {"amount_minor":50000,"method":"cash","paid_on":"<today>"}` -> 200, status `partial`, balance 70000.
  2. Overpay refusal: same with 70001 -> 400 "more than the balance"; float `1.5` and `"100"` -> 400.
  3. Top-up SA1 wallet `POST /wallet/students/SA1/top-ups/ {"amount_minor":40000,"currency":"EGP","method":"cash","paid_on":"<today>"}`; `POST /wallet/invoices/INV1/pay/ {"amount_minor":40000}` as PA -> balance 30000.
  4. Final cash `POST /billing/invoices/INV1/payments/ {"amount_minor":30000,"method":"cash","paid_on":"<today>"}` -> status `paid`, balance 0; a further payment -> 400.
  5. INV2: pay in full 150000 by cash in one call; `POST /billing/invoices/INV2/void/` on it -> refused (paid).
  6. One more invoice INV3 (`POST /billing/invoices/ {"student":SA2,"amount_minor":20000,"due_on":"<today>","description":"SCN extra"}`) left unpaid, and INV4 (10000) voided.
- **Expected:** amounts all integers; statuses move unpaid -> partial -> paid; INV1 paid total = 30000(wallet, TC-011) + 50000 + 40000(wallet) + 30000 = 150000 exactly. The wallet balance after step 3 is 30000 (TC-011) + 40000 - 30000 - 40000 = 0 (record the real number from the ledger).
- **Assert (DB):** `select sum(amount_minor) from billing_payment where invoice_id=INV1 and status in ('completed','credited')` = 150000 and equals `billing_invoice.amount_minor`; wallet balance equals entry sum; payment methods set for INV1 = {wallet, cash}; counter and `last_number` advance monotonically; INV4 `status='void'`.
- **Cleanup:** none.

#### SCN-TC-016: Payroll from the completed sessions: counts and minor-unit totals, issue, pay, acknowledge, locked sessions  [P1, REAL]
- **Role:** admin, T3. **Switches:** payroll set (Setup 1/2).
- **Steps:**
  1. `POST /payroll/payslips/generate/ {"year":2026,"month":9}` (other teachers' Sept payslips already exist from F10; they must not be changed) -> note T3's draft.
  2. `GET /payroll/payslips/?year=2026&month=9&teacher=T3`, `GET /payroll/payslips/<id>/`.
  3. `POST /payroll/payslips/<id>/issue/`; then attendance change on M1: `POST /sessions/M1/attendance/ {"student_attendance":"absent"}` -> 409 `payroll.payslip_issued`.
  4. `POST /payroll/payslips/<id>/mark-paid/ {"paid_on":"<today>","notes":"scn"}`; as T3 `GET /payroll/payslips/`, `POST .../acknowledge/`; as T1 `GET /payroll/payslips/<T3 id>/`.
- **Expected:** draft gross = net = 45000, 9 session lines (6000 x 6, 4500, 3000, 1500) with `minutes` 60/45/60/60 and `rate_minor` 6000; M10 and M11 produce no money; issue -> `issued`; mark-paid -> `paid`; T3 can read and acknowledge only their own; T1 gets 404/403 on T3's slip. A second `generate` is idempotent (created 0, same number).
- **Assert (DB):** `payroll_payslip` one row (T3, 2026, 9) `gross_minor=net_minor=45000`; `payroll_payslipline` rows kind `session` sum = 45000 and count = 9; the same sessions have `payroll_locked=true` and M10/M11 are not locked; one `finance_expense` (`source='payroll.payslip'`, `source_id`=slip id, type `salaries`, amount 45000, currency EGP, `spent_on`=today); counter advanced by 1.
- **Cleanup:** none.

#### SCN-TC-017: Absence notification reaches the family in the app and in Mailpit  [P1, REAL local SMTP]
- **Role:** admin (mark), PA (inbox), Mailpit. **Switches:** `auto_notifications`; notification setting `session.student_absent` enabled (`GET /notifications/settings/`, `PATCH` if off, record).
- **Steps:** create an extra session for SA2 starting 1 hour ago `POST /sessions/extra/ {"student":SA2,"course":C1,"teacher":T1,"occurs_on":"<today>","start_time":"<now-1h in Cairo>","minutes":30}`; mark `POST /sessions/<id>/attendance/ {"student_attendance":"absent"}`; run `$DC exec -T django python manage.py scan_notifications` (twice); wait for the celery email task (poll up to 60 s) `GET http://localhost:8025/api/v1/search?query=to:scn-parent-a@qa.etqan.test`; as PA `GET /notifications/` and `/notifications/unread-count/`; as PB `GET /notifications/`.
- **Expected:** one `session.student_absent` notification per intended recipient (the guardian PA; the student SA2 only if SA2 has an email, which it does; office per the audience table), exactly once even though the scan ran twice (dedupe key); one email to `scn-parent-a@qa.etqan.test` in Mailpit with the academy language, a link under the academy host, no raw placeholders `{{`; PB and the unrelated `qa-parent` receive nothing.
- **Assert (DB):** `select type, user_id, email_status, dedupe_key from notifications_notification where type='session.student_absent'` has no duplicate dedupe_key and `email_status='sent'` for PA; Mailpit message count for that recipient = 1 (REAL SMTP, local sink).
- **Edge:** a muted category (`notification_preferences` on, PA mutes sessions) -> no new notification on a second absence. Restore the preference.
- **Cleanup:** none; record the Mailpit message id in evidence.

#### SCN-TC-018: Reports and totals reconcile across attendance, billing, payroll and finance  [P1, REAL]
- **Role:** admin. **Data:** everything above; compare against the pre-run snapshot (Setup 6).
- **Steps:** `GET /billing/summary/`; `GET /billing/invoices/?format=csv`; `GET /billing/payments/?format=csv`; `GET /finance/summary/`; `GET /payroll/payslips/?year=2026&month=9`; `GET /payroll/payslips/projection/`; `GET /sessions/?format=csv`; then run the reconciliation SQL below in `academy_qa`.
- **Expected (each must hold; any mismatch is a P1 finding):**
  1. Revenue this month (EGP) delta = sum of cash payments recorded today on INV1/INV2 plus the cash top-up = 50000 + 30000 + 150000 + 30000(TC-011 top-up) + 40000 = **300000**. Wallet payments (30000 + 40000) are NOT in revenue; wallet top-ups are.
  2. Open receivables = INV3 20000 only (INV1/INV2 paid, INV4 void excluded). Summary `overdue`/unpaid agree.
  3. Payroll: T3 slip net 45000 EGP; `finance_expense` total for source `payroll.payslip` rose by exactly 45000; `/finance/summary/` per-currency expense in EGP rose by 45000; payroll lines = 9; sum of `session` lines = gross.
  4. Attendance: completed sessions = billing-independent (no invoice depends on attendance in this product, state so); consuming sessions of SUB3 = 7, SUB1 U1 consuming = 1; absences (U2, M8, new SA2 absence) are not billed or paid more than the weights allow.
  5. CSVs: row counts equal the API list totals; money columns are decimal strings with the currency's exponent (EGP 2 digits), and sums equal the integer minor-unit totals / 100.
  6. Projection for October (open month) includes the U1 and U4 pay for T1 and none of Sept.
- **Assert (DB):** `select currency, sum(amount_minor+fee_minor) from billing_payment where status in ('completed','credited') and method not in ('wallet','code') and paid_on >= date_trunc('month', now() at time zone 'Africa/Cairo') group by 1`; `select sum(amount_minor) from finance_expense where source='payroll.payslip'`; `select sum(gross_minor) from payroll_payslip where year=2026 and month=9`; `select sum(balance_minor) from wallet_wallet` equals `sum(wallet_walletentry.amount_minor)`; `select count(*) from billing_invoice where status<>'void' and amount_minor > coalesce((select sum(amount_minor) from billing_payment p where p.invoice_id=billing_invoice.id and p.status in ('completed','credited')),0)` = open invoices.
- **Cleanup:** record final snapshot in evidence. If wallet/revenue disagree, file with the exact SQL result.

## 3. Case summary

| ID | Group | Title | Pri | Tag | UI |
|---|---|---|---|---|---|
| 001 | B | Family, parent, two students | P1 | REAL | |
| 002 | B | Package + subscription + slots, UTC/local across DST | P1 | REAL | |
| 003 | B | Invoice/payer per subscription, no duplicates | P1 | REAL | |
| 004 | B | Conflicts and inactive people | P2 | REAL | |
| 005 | B | Chain isolation across academies | P1 | REAL | |
| 006 | C | Teacher sees only own sessions | P1 | REAL | |
| 007 | C | Attendance present/absent/excused and consumption | P1 | REAL | Playwright 1 |
| 008 | C | Session report and missing list | P1 | REAL | |
| 009 | C | Supervisor view and marking | P2 | REAL | |
| 010 | D | Parent sees only own children's sessions | P1 | REAL | |
| 011 | D | Parent invoices and wallet, other family hidden | P1 | REAL | |
| 012 | D | Parent portal UI | P1 | REAL | Playwright 2 |
| 013 | D | Write-denial matrix | P1 | REAL | |
| 014 | E | Month of attendance, consumption | P1 | REAL | |
| 015 | E | Invoices partial, wallet, full | P1 | REAL | |
| 016 | E | Payroll counts and totals, issue, pay | P1 | REAL | |
| 017 | E | Absence notice to Mailpit | P1 | REAL (local SMTP) | |
| 018 | E | Cross-module reconciliation | P1 | REAL | |

Total 18: P1 16, P2 2. Tags: REAL 18, SIMULATED 0, FAKE 0, BLOCKED 0. UI smoke 2.

## 4. Open points the executor must confirm (do not guess; read the 400/404 and the code)
- **Q1** Whether a teacher-absent session (M10) is a zero-amount payslip line or no line (TC-016 accepts either as long as it adds 0).
- **Q2** Exact field names `student_absent_pay_bp` / `student_excused_pay_bp` and `auto_notifications` feature code (F10 spec uses the first two; confirm the third in `features.py`).
- **Q3** Whether parents/students may postpone (TC-013) and what a parent can read of a session report (TC-008/010); record observed behaviour, then compare with `docs/features/sessions.md`.
- **Q4** Whether `late` attendance is expected by the owner: already a documented gap (F08, QA-046 doc); do not re-file.
- **Q5** Whether cancelling SUB3's M11 or cancelling a subscription voids or keeps its auto invoice (TC-004 cleanup): record the observed rule.

## 5. Results (Agent 2, 2026-10-19 17:02–17:18Z, lean mode, live stack, academy `qa` + `qaother`)

Evidence: `qa/evidence/SCN/` (`s0-setup.txt` snapshot, `s1-setup.txt`, `tcNNN*.txt`, `restore.txt`, CSV exports, `pw/` screenshots and page text, `pw-tc0*-run*.txt`, `scripts/` incl. `ids.env`).
Ids: T1 7, T2 219, T3 220, TG 221 (deactivated); SA1 222, SA2 223, PA 224, SB1 225, PB 226, SA3 227; FAM-A 11, FAM-B 12; course 6, package 17 (8 sessions); SUB1 85, SUB2 86, SUB-A3 87 (cancelled), SUB3 88; U1 383, U2 384, U3 385, U4 382; M1..M11 388..398; INV1 146, INV2 147, INV3 151, INV4 152 (void), INVB 149 (FAM-B), SUB-A3 inv 148 (void), SUB3 inv 150 (void); payslip 43 (PAY-000040).
Setup: features on (all codes known, `auto_notifications` exists). New users needed `account_emailaddress.verified=true` (SQL QA data edit, same as F09/F10): the invite link stops working once the password is set by shell (token bound to the password hash; correct), and a reset request for an invited account sends no mail. Settings were restored to the s0 values at the end (`restore.txt`).

| TC | Result | Tag | Evidence | Notes |
|---|---|---|---|---|
| 001 | PASS | REAL | tc001.txt | 201s; families list both students, `payer_needs_choosing=false`; `billing/payers` default = PA; SA1 into FAM-B → 400 "already in another family". 5 invites in Mailpit. DB: roles, 3 studentprofiles with family ids, 3 guardianship rows (profile ids), payer set, unique emails, one unverified `account_emailaddress` each. Profile payload needs `gender` (spec corrected). |
| 002 | PASS | REAL | tc002-003.txt | Mon/Thu 18:00 Cairo = 15:00Z until 10-29, 16:00Z from 11-02; SUB2 Tue/Fri 17:00 = 14:00Z, Fri 10-30 = 15:00Z (DST change). `occurs_on` = Cairo date for every row. Horizon 21 d gave 7 sessions; generate to 11-30 → 11 sessions (term + 7-day grace, 2 skipped out of term). **Spec corrected:** generation fills the term + grace (F06 spec, `subscriptions.md`), not "package size"; the package (8) is the consumption budget (`sessions_remaining=8`). `schedule/today/` is office-only (`session.view_any`), teacher 403 by design. |
| 003 | PASS | REAL | tc002-003.txt | One invoice per subscription: 146/147, 150000 EGP, due +7 (10-26), payer PA (family), `unpaid`, `INV-000146/147`. Two more generates: created 0, no invoice; counter +2. |
| 004 | PASS | REAL | tc004.txt | SA3 at T1's Mon 18:00 → 201 with `conflicts` (each pair listed, incl. 354↔371); overlap SQL shows only flagged pairs (T1 already double-booked by F06/F08 fixtures, all reported). Deactivated teacher → 400 "Choose an active teacher". SUB1 md5 unchanged. Cleanup: cancel kept invoice 148 unpaid (Q5: cancel does not void) → voided by hand; 1 started session (371) kept. |
| 005 | PASS | REAL | tc005.txt | qaother → qa ids: all 404 / 400 on create, no 500. qa → qaother: cross-host cookie 403 on every route; same numeric ids resolve to qa's own rows (payload names differ: "F02 Student new2" vs "SCN Other Student"). Lists contain no foreign rows; summaries per schema (qa EGP/KWD/USD = SQL, qaother USD 4000 = SQL). Test-side slip: the first qa→qaother probe hit qa's own sub 2 (notes restored to '') and generated 5 extra future sessions 377–381 on it (generated sessions can't be deleted; left in place). |
| 006 | PASS | REAL | tc006.txt | T1 paged session ids == DB (174, incl. U1..U4); T2 6 == DB. Foreign session 404. Subscriptions list only own; invoices 403; payslips only own; no SA2 id in T1 output. People list 403 for teachers (design). |
| 007 | PASS | REAL | tc007.txt, pw-tc007-run3.txt, pw/tc007-teacher-present.png | UI: teacher marks U1 present (200, completed, remaining 8→7). API: U2 absent/U3 excused complete without consuming (switches false), U4 extra not consumed; future 409 `scheduling.not_started`; `late` 400; SUB2 session 404. `marked_by=7`, 4 activity rows; consumption SQL 1 = 8−7. |
| 008 | PASS | REAL | tc008.txt | Report 200 (notes stored verbatim incl. `<b>`), 0/6/"a" 400, T2 404, student/parent 404 (staff-only by design, `can_read_report`), admin 200. U1 is not "missing" yet: missing = ended > 24 h ago (`REPORT_DUE_AFTER`); U4 (> 24 h) listed, gone after its report. |
| 009 | PASS | REAL | tc009.txt | Supervisor sees only assigned (9 live of 10, 1 cancelled); open of an ended session 409; on a running session open 200 + attendance (`{"status":"present"}`, spec field name corrected) 200, activity row, student attendance/status unchanged; teacher 403 on supervision; supervisor POST subscription / DELETE session 403. Unassigned after. |
| 010 | PASS | REAL | tc010.txt | PA session set == sessions of PA's guardianship children (22); FAM-B / qa-parent child 404; PB sees only SB1 (1); SA1 sees only own (16). Parent payload has no cancel_reason/notes/marked_by/supervisor/has_report/payroll fields. SA3 (family member, PA not guardian) is not visible to PA: visibility follows guardianship (record). People/families lists 403 for parents (design). |
| 011 | PASS | REAL | tc011.txt | PA lists FAM-A invoices only (incl. void 148 as payer); FAM-B invoice 149 404 (PB sees only 149); payments/summary 403; cash payment by parent 403; wallet top-up 30000 then pay 30000 → INV1 partial 120000; oversize 409 `wallet.insufficient_balance`. Wallet balance = entry sum; wallet spend linked to payment 76 `method=wallet`. |
| 012 | PASS | REAL | pw-tc012-run4.txt, pw/tc012-* | Parent UI: 10:00 Present, 11:00 Absent, 12:00 Excused; Nov 2 18:00 (after DST) and Oct 20/30 17:00 local; no FAM-B; 22 list items = API count 22. Invoice: EGP 1,500.00 / paid 300.00 / balance 1,200.00 = API. FAM-B invoice URL → "This invoice couldn't be found." (after the query retries, ~6 s). |
| 013 | PASS | REAL | tc013.txt | PA, SA1, PB: 15 writes/reads each → 403 (permission before lookup, so no existence leak); anonymous 403 "Authentication credentials were not provided" (DRF session auth answers 403, not 401). Row counts session/invoice/payment/wallet/payslip/subscription unchanged; U2 still absent. Postpone exception not exercised (`can_postpone` exposed). |
| 014 | PASS | REAL | tc014.txt | 11 sessions (10 completed, 1 cancelled), group-by matches the table, consumption 7, `sessions_remaining` 1, T3 sees exactly M1..M11, missing reports M1..M7 (teacher-absent M10 excluded by design), none locked. |
| 015 | PASS | REAL | tc015.txt | partial 70000 → overpay 70001 400 → float 400 → `"100"` accepted as 100 (known DRF coercion, F09 TC-002) → wallet 40000 → closed with the real balance 29899 → `paid`, further 1 → 400. INV1 payments = cash 80000 + wallet 70000 = 150000 = amount. INV2 paid in one call, void refused 409 `billing.has_payments`; INV3 unpaid 20000; INV4 void. Wallet 0 = entries. SUB3's auto invoice 150 (issued today for the back-dated Sept subscription) voided to keep the month payroll-only. |
| 016 | PASS | REAL | tc016.txt | T3 draft gross = net = 45000, 9 session lines (6×6000, 4500, 3000, 1500), M10/M11 no line (Q1). Issue → M1 attendance 409 `payroll.payslip_issued`; mark-paid; T3 lists/acknowledges own; T1 404. Second generate created 0. DB: 9 lines sum 45000, M1..M9 locked, M10/M11 not; `finance_expense` 18 (payroll.payslip, 43, 45000 EGP, today); counter +1. Other teachers' issued/paid Sept slips unchanged; their 3 drafts were rebuilt (by design, `payroll.md`). |
| 017 | PASS | REAL (local SMTP) | tc017.txt | Absent on SA2 extra → one `session.student_absent` to PA (guardians-only audience, `finders.py`), dedupe key `...:session:399:224`, scan ran twice, `email_status=sent`; one Mailpit message in Arabic, links under `qa.etqan.localhost`, no `{{`. PB / qa-parent nothing. Mute "sessions" → second absence creates nothing; restored. |
| 018 | PASS | REAL | tc018.txt, *.csv | Revenue EGP 747856 → 1047856 (+300000 = INV1 cash 80000 + INV2 150000 + top-ups 70000; wallet 70000 not counted) = SQL. Open receivables 2 / 25000 (INV3 20000 + FAM-B 5000 from TC-011); no paid/unpaid status mismatches. Payroll expense +45000, finance EGP expense 939065 → 984065; slip lines = gross. Consumption SUB3 7, SUB1 1. Wallet sum 72000 = entries. CSV rows = API counts (152/76/334); money columns are integer minor units by design (headers say "minor units"; spec corrected). Projection Oct: U1 and U4 each move T1's paid-so-far by 6000 (toggle probe, restored); T3 (Sept only) absent. |

**Totals:** 18 executed, 18 PASS, 0 FAIL, 0 BLOCKED (REAL 18). UI smoke 2/2 (TC-007, TC-012). No 5xx in the django log during the run. **No new defect.** Spec corrections (expectation, not product): TC-002 session count and teacher Today board, TC-008 missing-report window and family read, TC-009 field name, TC-013 anonymous 403, TC-015 numeric string, TC-018 CSV minor units and receivables.
