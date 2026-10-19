# F08: Sessions and attendance (lifecycle, marking, reports, postponement, make-up, disposal, archive, activity log, supervision, meeting links)

Author: Agent 1 (LEAN mode). This spec approves nothing. Written 2026-10-18 from backend adff9c9 / dashboard 5ed775d.

Sources read: `backend/etqan/scheduling/{models.py, scopes.py, api/{urls,session_views,supervision_views,serializers}.py,
services/{attendance,manual,postpone,times,reports,supervision,meetings,rules,paylock,revert}.py}`,
`integrations/services/video.py`, `access/presets.py`, `docs/features/{sessions,meetings}.md`.
Existing tests (pytest, `backend/etqan/scheduling/tests/`): `test_attendance.py`, `test_actions.py`, `test_api_session_writes.py`,
`test_api_sessions.py`, `test_session_classes_*.py`, `test_api_session_classes.py`, `test_times_postponement_*.py`,
`test_api_times_postponement.py`, `test_activity_*.py`, `test_api_activity.py`, `test_archive_*.py`, `test_api_archive_*.py`, `test_reports.py`,
`test_supervision.py`, `test_api_supervision.py`, `test_host_link.py`, `test_meetings.py`, `test_paylock.py`, `test_today.py`, `test_compensated_by.py`.
Business rules are well unit-tested; this spec therefore concentrates on live-stack, end-to-end, cross-role and cross-tenant behaviour. Where a pytest
already covers the rule, the case says "covered by" and only the live/API/DB/role path is new.

## 1. What the code does (facts the cases rely on)

- Tables (schema `academy_qa`): `scheduling_session`, `scheduling_sessionreport` (1 per session), `scheduling_sessionactivity` (log).
  Session columns used: `status` (scheduled/completed/cancelled/at_disposal), `student_attendance` / `teacher_attendance` / `supervisor_attendance`
  (`not_set`/`present`/`absent`/`excused`; supervisor has only not_set/present/absent), `kind` (regular/compensation/extra/trial), `compensated`,
  `compensated_by`, `compensates_id`, `pays_teacher`, `payroll_locked`, `marked_by_id/marked_at`, `cancel_reason`, `disposal_reason`, `archived_at`,
  `meeting_url/provider/ref`, `starts_at` (UTC), `occurs_on`, `minutes`, `actual_minutes`, `teacher_in_at/out_at`, `postponed_at`, `original_slot_id/original_on`.
- There is **no "late" status**. Supported attendance values: `present`, `absent`, `excused` (and `not_set` = undo, office only).
- Routes are under `/api/v1/` (login: `POST /api/v1/identity/login/` with `{"identifier","password"}`, session cookie + CSRF; people lists under `/api/v1/people/`).
- Marking: `POST /sessions/<id>/attendance/` body `{"student_attendance"?,"teacher_attendance"?}`. Gate: `starts_at <= now`. Student mark completes a scheduled session;
  teacher mark never changes status. `not_set` only for office. Teacher needs switch `teacher_attendance` (default ON). Refusals (409): `payroll.payslip_issued`,
  `scheduling.has_compensation`, `scheduling.session_cancelled`, `scheduling.not_started`, `scheduling.not_allowed_in_status` (student mark on at_disposal).
- Consumption rule (`rules.consuming`): completed AND student present (or absent/excused when `absent_consumes_session` / `excused_consumes_session`) AND teacher not absent
  AND kind regular/compensation AND not compensated (balance-compensated counts). Shown as `sessions_remaining` on the subscription payload.
- Permissions: `AttendanceView` = `HasCode(attendance.update) | IsTeacher`; cancel/restore/bulk/disposal/pays-teacher = `session.update`; add = `session.create` + switch;
  delete = `session.delete`; activity = `session.view` + `activity_log`, revert = `session.update`; archive = `session.delete`, unarchive = `session.restore`; report = `session_report.view/update`
  or the session's teacher; supervision = `session.supervise` + switch `supervision`; host link = authenticated + not impersonating, then teacher-of-session only (404 otherwise).
  Teacher/student/parent are scoped to own rows (404 outside). The **Supervisor preset holds** `session.update`, `attendance.update`, `session_report.update`, `session.supervise` plus all session/attendance/report reads.
- Meetings: `scheduling.provision_meetings` (Celery beat every 5 min) fills blank `meeting_url` of scheduled, non-archived sessions starting within LEAD; runs only if `zoom_api` on or the
  academy has its own Zoom. Zoom failing with no creds: if the session starts within 30 minutes, falls back to Jitsi `https://meet.jit.si/Etqan<uuid4hex>` (provider `jitsi`), else waits.

## 2. Provider tags

REAL = our code and DB. Jitsi link generation is REAL (just a UUID URL, nothing is called; whether the room opens on meet.jit.si is not tested). Zoom (create meeting, host/start link,
`meeting.ended` webhook): **FAKE** (monkeypatched pytest in `test_host_link.py`, `test_meetings.py`) and live **BLOCKED** (no credentials). Notifications from sessions go to mailpit/in-app (REAL local).

## 3. Setup (academy `qa`, UTC offset +2/+3 Africa/Cairo; EGP)

Run once. Prefer API; ids are discovered from list endpoints. Let `$DC` = the `dc.sh` helper. Log in per role with the cookie jar (admin `qa-admin@qa.etqan.test`, `qa-staff-nocode@`, `qa-staff-codes@`,
`qa-supervisor@`, `qa-teacher@`, `qa-student@`, `qa-parent@`; other academy `qaother-admin@qa.etqan.test` on `qaother.etqan.localhost`).

```
# 1. switches on qa (all session features; payroll for money cases)
$DC exec -T django python manage.py set_features qa --on manual_sessions extra_sessions compensation_sessions disposal_status session_times postponement activity_log session_archive subscription_archive supervision session_reports teacher_attendance payroll_rules salary_projections
#    (if payroll_rules / salary_projections codes are named differently, run `set_features qa --on` with the codes listed in backend/etqan/platform/features.py)
# 2. discover people/catalogue ids (as admin)
GET /api/v1/people/students/ ; GET /api/v1/people/teachers/ ; GET /api/v1/catalogue/courses/ ; GET /api/v1/catalogue/packages/
#    If qa has no course/package/teacher rates yet, create via the existing admin APIs (course with the QA teacher linked, a 10-session package, a teacher hourly rate e.g. 12000 minor units = 120.00 EGP/h)
# 3. a subscription with weekly slots for QA student + QA teacher (Subscription A), and a second one (B) with no slots
POST /api/v1/subscriptions/  {"student":S,"course":C,"teacher":T,"package":P,"starts_on":"<today-14d>","price_minor":50000,"slots":[...]}
# 4. PAST sessions are created with the hand-add API (it accepts past dates), so no clock manipulation is needed
POST /api/v1/sessions/extra/ {"student":S,"course":C,"teacher":T,"occurs_on":"<yesterday>","start_time":"10:00","minutes":60}
POST /api/v1/sessions/regular/ {"subscription":A,"occurs_on":"<in term, past>","start_time":"11:00"}
# 5. a FUTURE session: same calls with occurs_on = today+2 days
# 6. assign supervisor: PATCH /api/v1/sessions/<id>/ {"supervisor_id":<qa-supervisor user id>}   (needs supervision on)
# 7. DB check helper
$DC exec -T django python manage.py tenant_command dbshell --schema=academy_qa     # or psql -h localhost -p 5433 -U etqan etqan, SET search_path=academy_qa;
```
Tag a "RESET" for cleanup: QA-created sessions are noted in the case; remove hand-added unmarked ones with `DELETE /api/v1/sessions/<id>/`, marked ones stay (qa schema is disposable).
Names used below: `P1` = past regular session of Sub A, `P2..P5` = past extra sessions, `F1..F3` = future sessions (+2 days), `Q1` = other-academy session (create the same way in `qaother`).

## 4. Test cases (26: P1 22, P2 4)

### Workflow, state transitions and money

#### F08-TC-001: Teacher marks a session present, session completes, package is consumed (E2E, UI smoke 1)  [P1, REAL]
- **Role:** teacher `qa-teacher`. **Switches:** `teacher_attendance` (default on). **Data:** Subscription A with `sessions_remaining = R`, past regular session `P1` (scheduled).
- **Steps:** (UI smoke, Playwright, `--workers=1`) log in at `qa.etqan.localhost/app/`, open Teaching > Sessions, press Present on P1, confirm toast. API: `GET /api/v1/subscriptions/A/` before and after.
- **Expected:** `POST /api/v1/sessions/P1/attendance/ {"student_attendance":"present"}` 200; `status=completed`; subscription `sessions_remaining = R-1`.
- **Assert (DB):** `scheduling_session` P1: `status='completed'`, `student_attendance='present'`, `marked_by_id`=teacher user, `marked_at` not null; one `scheduling_sessionactivity` row `action='attendance'` with `changes` `{"student_attendance":["not_set","present"],"status":["scheduled","completed"]}`.
- Covered by `test_attendance.py`, `test_api_session_writes.py`; the UI + live DB path is new. **Cleanup:** none (P1 stays completed).

#### F08-TC-002: Attendance value matrix and the consumption/money rule  [P1, REAL]
- **Role:** admin. **Switches:** none. **Data:** past sessions P2 (regular of Sub A), P3, P4, P5 (all regular, Sub A, scheduled). Academy settings `absent_consumes_session=false`, `excused_consumes_session=false` first.
- **Steps:** mark P2 `absent`, P3 `excused`, P4 `present` with `teacher_attendance=absent`, P5 `present`. Read `sessions_remaining` after each. Then `PATCH /api/v1/academy/settings/ {"absent_consumes_session":true}` (find exact path in `academy/api/urls.py`) and re-read; then `excused_consumes_session:true`.
- **Expected:** all four become `completed`. Consumption: P2 no, P3 no, P4 no (teacher absent), P5 yes -> remaining drops by exactly 1. After `absent_consumes_session=true` P2 counts (-1 more); after `excused...=true` P3 counts (-1 more). Settings are read live (no cache).
- **Assert (DB):** the three attendance columns per row; `sessions_remaining` equals `package size - count(consuming)` computed in SQL: `status='completed' AND student_attendance IN (...) AND teacher_attendance<>'absent' AND kind IN ('regular','compensation') AND compensated=false`.
- **Edge:** an invalid value `{"student_attendance":"late"}` -> 400 (`late` is not supported; it is a doc/requirement gap if the owner expects it, see gaps). **Cleanup:** restore both settings to false.

#### F08-TC-003: Money, extra session never consumes and teacher pay follows `pays_teacher` (integer minor units)  [P1, REAL]
- **Role:** admin. **Switches:** `extra_sessions`, `payroll_rules`, `salary_projections`. **Data:** teacher rate 12000 minor/hour (120.00 EGP), extra session X1 (60 min, `pays_teacher=true`) and X2 (30 min, `pays_teacher=false`), both in the current month and already started.
- **Steps:** mark X1 and X2 present. `GET /api/v1/payroll/payslips/projection/`. Then `POST /api/v1/sessions/X2/pays-teacher/ {"pays_teacher":true}` and re-read the projection.
- **Expected:** subscription `sessions_remaining` unchanged by X1/X2. Projection adds exactly 12000 for X1 (60 min * 12000/60), nothing for X2; after the toggle adds 6000 for X2 (30 min). Amounts are integers, currency EGP, no float artefacts. Rounding of odd minutes follows `rules.session_amount` (also test `minutes=45`: 9000).
- **Assert (DB):** `scheduling_session.pays_teacher`; payroll projection lines sum equals sum(rate*minutes/60) with the module's rounding; no row in `scheduling_session` with `payroll_locked=true` yet.
- Covered by `test_session_classes_*`, payroll tests; the live money chain is new. **Cleanup:** none.

#### F08-TC-004: Issued payslip locks the session; every write path refuses  [P1, REAL]
- **Role:** admin. **Switches:** payroll features of TC-003. **Data:** completed session P6 in a month with an issued payslip.
- **Steps:** `POST /api/v1/payroll/payslips/generate/` for the teacher/month, `POST /api/v1/payroll/payslips/<id>/issue/`. Then on P6: attendance (`absent`), `cancel {"reason":"x"}`, `restore`, `postpone`, `times`, `disposal`, `pays-teacher`, bulk `present`.
- **Expected:** each is 409 with code `payroll.payslip_issued` (bulk reports it in `skipped` with that code, `done=[]`); the payslip total (integer minor units) is unchanged afterwards. `payroll_locked=true`.
- **Assert (DB):** `scheduling_session.payroll_locked=true` for exactly the payslip's sessions; status and attendance of P6 unchanged; no new `sessionactivity` row.
- Covered by `test_paylock.py`; the all-endpoints sweep on the live stack is new. **Cleanup:** none (leave payslip issued; use dedicated teacher/month).

#### F08-TC-005: Cancel, restore and the state machine (including invalid transitions)  [P1, REAL]
- **Role:** admin. **Data:** P7 (past regular, scheduled), F1 (future).
- **Steps:** `cancel {"reason":""}` -> 400; `cancel {"reason":"teacher ill"}` on P7; `cancel` again; `attendance present` on cancelled P7; `restore` P7; `restore` again; mark P7 present then `cancel` then `restore`; mark F1 present (not started).
- **Expected:** empty reason 400 `reason`; first cancel 200 `cancelled` with `cancel_reason`, `cancelled_by`, `cancelled_at`; second cancel 409 `scheduling.not_allowed_in_status`; attendance on cancelled 409 `scheduling.session_cancelled`; restore returns `scheduled`; second restore 409; after present+cancel+restore the status is `completed` (attendance kept); F1 attendance 409 `scheduling.not_started`.
- **Assert (DB):** cancel fields cleared on restore (`cancel_reason=''`, `cancelled_by_id` null); student_attendance preserved; one activity row per change with action cancel/restore.
- Covered by `test_actions.py`, `test_attendance.py`; **Cleanup:** none.

#### F08-TC-006: Duplicate / repeated marking and double-click race  [P1, REAL]
- **Role:** teacher then admin. **Data:** P8 past scheduled.
- **Steps:** send the same `present` request twice, then fire 5 concurrent `POST attendance` (present vs absent mix, `xargs -P5 curl`). Then admin `{"student_attendance":"not_set"}`.
- **Expected:** repeat of the same value is accepted idempotently (200) or logged as no-op; final state is one of the sent values (last writer), never an inconsistent mix (status completed, attendance set); no 500. Concurrent requests are serialised by row lock. `not_set` by admin returns status `scheduled`; by teacher 403.
- **Assert (DB):** a single session row; count of `sessionactivity` rows equals number of effective changes; `marked_by_id` is the last writer. A duplicate identical mark must not create duplicate consumption (remaining changes by at most 1 in total).
- **Note:** whether an identical repeat writes an activity row is not specified; record observed behaviour. **Cleanup:** none.

#### F08-TC-007: At-disposal flow, never consumes, never auto-deleted  [P1, REAL]
- **Role:** admin. **Switches:** `disposal_status` (off first). **Data:** F2 future scheduled with Sub A, P9 past scheduled.
- **Steps:** switch off -> `POST /sessions/P9/disposal/ {"reason":"no teacher"}` expect 404/403 by switch; switch on -> 200 `at_disposal`. Then student mark `present` on P9; teacher mark `teacher_attendance=present` on P9; `restore`; place disposal on a marked (completed) session; cancel an at_disposal session.
- **Expected:** student mark on at_disposal 409 `scheduling.not_allowed_in_status`; teacher mark OK (status stays); restore -> `scheduled` and `disposal_reason=''`; disposal on completed 409; cancel of at_disposal OK keeps `disposal_reason`. `sessions_remaining` never changes for at_disposal. Run `scheduling.run_daily` (`$DC exec -T django python manage.py tenant_command shell`/celery task) and confirm P9 is not deleted.
- **Assert (DB):** `status`, `disposal_reason`; session still present after the daily job. Covered by `test_session_classes_disposal.py`; **Cleanup:** none.

#### F08-TC-008: Make-up (compensation) and balance compensation, original frozen  [P1, REAL]
- **Role:** admin. **Switches:** `compensation_sessions`. **Data:** cancelled session C1 (Sub A), completed-without-consuming session C2 (absent), extra session X3, scheduled session F3.
- **Steps:** `POST /sessions/compensation/ {"compensates":C1,"occurs_on":"<+3d>","start_time":"10:00"}`; again for C1; for C2; for X3 (extra); for F3 (scheduled). Then try attendance/restore/cancel/disposal on C1 (now compensated). Cancel the compensation and re-check C1. Restore the cancelled compensation.
- **Expected:** C1/C2 201 `kind=compensation`, original `compensated=true`; second make-up for C1 409 `scheduling.has_compensation`/already compensated; X3 and F3 refused (not compensable); actions on frozen C1 409 `scheduling.has_compensation`; cancelling the make-up sets C1 `compensated=false`; restoring the cancelled make-up re-marks C1 or 409 `scheduling.already_compensated` if another live one exists. Package never gets +1 session for the make-up (it replaces the original).
- **Assert (DB):** `compensates_id` only on compensation rows (check constraint), at most one live compensation per original (partial unique); `compensated_by='makeup'`. Covered by `test_session_classes_manual.py`, `test_compensated_by.py`; the API chain on live data is new. **Cleanup:** none.

#### F08-TC-009: Postponement by family within the window, by office without  [P1, REAL]
- **Role:** student/parent/teacher, then admin. **Switches:** `postponement`. **Data:** academy setting `postpone_limit_minutes=120`; F4 starts in 3 days (Sub A, from a slot); F5 starts in 90 minutes (extra session); teacher has another session at T_busy.
- **Steps:** student `POST /sessions/F4/postpone/ {"occurs_on":D,"start_time":"15:00"}` to a free time 5 days later; to a time 20 days later; to a time overlapping teacher's other session; student on F5 (too late); admin on F5; parent of the student on F4's sibling; parent of another family; then move F4 back to its exact original slot date/time.
- **Expected:** valid move 200 (`postponed_at` set, `slot_id` null, `original_slot_id`/`original_on` set); >14 days 400 `occurs_on`; busy 409 `scheduling.teacher_busy`; F5 student 409 `scheduling.too_late_to_postpone`; admin on F5 200 with `conflicts` warnings only; other family 404; return to original slot reattaches (`slot_id` restored, `original_*` null) and the daily generation does not duplicate the date (unique (slot,date)).
- **Assert (DB):** one row per (slot_id, occurs_on); `original_starts_at` stores the old UTC instant; the new `starts_at` honours Africa/Cairo (check around DST boundary, Cairo observes DST: pick a date after the clocks change). Covered by `test_times_postponement_postpone.py`; **Cleanup:** none.

#### F08-TC-010: Postponement refused states and the archived-session hole  [P1, REAL]
- **Role:** admin. **Data:** completed session, cancelled, at_disposal, compensated original, session with `teacher_in_at`, session of a cancelled/expired subscription, archived future session.
- **Steps:** postpone each to a valid future time.
- **Expected:** every one 409 `scheduling.not_allowed_in_status` (or `scheduling.archived` for the archived one while `session_archive` is on); target date inside pauses or outside term for a regular session -> 400 `occurs_on`.
- **Assert (DB):** no change to any row, no activity row. Covered by `test_times_postponement_postpone.py`, `test_archive_refusals.py`. **Cleanup:** none.

### Permissions and tenant isolation

#### F08-TC-011: Permission matrix, reads (list, detail, CSV, report fields)  [P1, REAL]
- **Role:** admin, staff-nocode, staff-codes (`student.view` only), supervisor, teacher, student, parent, anonymous. **Data:** sessions of QA student/teacher, plus one session of another student/teacher in qa.
- **Steps:** each role: `GET /sessions/`, `GET /sessions/<own>/`, `GET /sessions/<foreign>/`, `GET /sessions/?format=csv` (or `Accept: text/csv`), `GET /sessions/<id>/activity/`, `GET /reports/missing/`.
- **Expected:** admin all 200; staff-nocode/staff-codes 403 on list/detail (no `session.view_any`/`session.view`); supervisor 200 (preset reads); teacher/student/parent 200 on own rows only, 404 on foreign; CSV only for office (others 403, even with a bad filter); activity only office with code (others 403/404); anonymous 401/403 everywhere. Student/parent payload hides `cancel_reason`, `notes`, `has_report`, `payroll_locked`; teacher sees `has_report` for own.
- **Assert:** field-level diff of the JSON per role; no cross-user leak in list totals (`count`). **Cleanup:** none.

#### F08-TC-012: Permission matrix, writes  [P1, REAL]
- **Role:** same eight roles. **Data:** a past scheduled session S of the QA teacher+student; a second past session S2 of another teacher.
- **Steps:** for each role try: `attendance present` on S and S2, `cancel`, `restore`, `bulk {"ids":[S],"action":"present"}`, `disposal`, `pays-teacher`, `extra` create, `DELETE`, `archive`, `PUT report`, `times`.
- **Expected:** admin all allowed (subject to state). staff-nocode and staff-codes: 403 on all. Supervisor (preset holds `session.update`, `attendance.update`, `session_report.update`): allowed on attendance/cancel/bulk/disposal (confirm and report; see S3), 403 on `session.create`/`session.delete`/archive. Teacher: attendance and times and report only on own session (S ok, S2 404), 403 on cancel/restore/bulk/disposal/pays-teacher/delete/create. Student/parent: 403 on all except postpone (own, TC-009). Anonymous 401/403.
- **Assert (DB):** after the run only S changed as expected; S2 untouched; `marked_by_id` records the actual actor. **Cleanup:** none.

#### F08-TC-013: Cross-academy isolation  [P1, REAL]
- **Role:** `qaother-admin` on `qaother.etqan.localhost`, qa admin on qa. **Data:** session Q1 in qaother (create via extra API there), session P1 in qa.
- **Steps:** with the qaother cookie call every route against qa's session ids (attendance, cancel, restore, bulk with mixed ids, postpone, report, activity, revert, host-link, archive, supervision open). Reverse direction too. Also reuse the qa cookie against the qaother host.
- **Expected:** 404 for foreign ids (never 403/200); bulk returns `skipped=[(id,"not_found")]` and `done=[]` for foreign ids while handling own ids in the same call; a qa session cookie is not valid on the other host (401); `GET /sessions/` totals only own academy; CSV contains no foreign rows.
- **Assert (DB):** `academy_qa.scheduling_session` and `academy_qaother.scheduling_session` unchanged by cross calls (count + max(updated_at)); `sessionactivity` unchanged. **Cleanup:** remove Q1 if unmarked.

### Reports, times, supervision

#### F08-TC-014: Session report workflow and missing-reports list  [P1, REAL]
- **Role:** teacher (own), admin, other teacher, student. **Switches:** `session_reports` (on). **Data:** completed present session R1 that ended >24h ago, completed present R2 ended <24h ago, scheduled session R3, absent-marked R4.
- **Steps:** `GET /reports/missing/` as teacher and admin; `PUT /sessions/R1/report/ {"behaviour":5,"participation":4,"notes":"ok"}`; PUT again with 3/2; PUT with 0, 6, "a"; PUT on R3; GET as student/parent/other teacher; switch off `session_reports` and GET.
- **Expected:** missing list holds R1 only (R2 too recent, R4 absent, R3 not completed); first PUT 200 creates, second replaces (still one row, `written_by` kept = first author, `updated_at` moves); out-of-range 400 `behaviour`; R3 409 `scheduling.not_completed`; student/parent/other teacher 404; switch off -> 404; after the PUT R1 leaves the missing list.
- **Assert (DB):** `scheduling_sessionreport` has exactly one row for R1 (unique session_id). Covered by `test_reports.py`; **Cleanup:** none.

#### F08-TC-015: Teacher in/out times and actual minutes (record only)  [P2, REAL]
- **Role:** teacher, admin. **Switches:** `session_times`, `teacher_attendance`. **Data:** session T1 starting in 10 minutes, session T2 started 1 hour ago (60 min).
- **Steps:** teacher `POST /sessions/T1/times/ {"teacher_in_at":"<now>"}` (within 15 min allowed); teacher stamps `student_in_at` (403); teacher on T2 `teacher_in_at`/`teacher_out_at` 55 minutes apart; out before in; span >600 min; admin sets `actual_minutes:45`; teacher with `teacher_attendance` off.
- **Expected:** T1 early "in" 200, other early fields 409 `scheduling.not_started`; student fields by teacher 403; `actual_minutes` auto = 55; out<in 400; >600 400; admin override respected; switch off -> teacher 403. Consumption and pay still use `minutes` (60), not `actual_minutes` (assert projection unchanged).
- **Assert (DB):** `teacher_in_at/out_at`, `actual_minutes`. Covered by `test_times_postponement_times.py`; **Cleanup:** none.

#### F08-TC-016: Supervision, opening window and supervisor attendance  [P1, REAL]
- **Role:** supervisor `qa-supervisor`, admin, staff-codes. **Switches:** `supervision`. **Data:** session V1 (starts in 5 min), V2 (starts in 2 h), V3 (started 30 min ago, 60 min), V4 (ended 1 h ago), V5 cancelled; all with supervisor = qa-supervisor; V6 supervised by someone else.
- **Steps:** `GET /supervision/` (V6 absent, V5 absent); `POST /supervision/<id>/open/` for each; `POST /supervision/<id>/attendance/ {"status":"present"}` for V3, V2, V4; `{"status":"excused"}`; open V6; admin `PATCH /sessions/V2/ {"supervisor_attendance":"present"}`; admin PATCH `{"supervisor_id":null}` then `{"supervisor_attendance":"present"}`; switch `supervision` off and GET.
- **Expected:** V1/V3 open 200 returns `meeting_url` and sets `opened_by_supervisor_at` once; V2 409 `scheduling.supervision_not_open`; V4 open 409 `scheduling.session_ended`; V5 409 `scheduling.session_cancelled`; V6 404; attendance present on V3 ok; V2 attendance 409 not open; `excused` 400; reassigning resets `supervisor_attendance=not_set` and `opened_by_supervisor_at=null`; PATCH attendance with no supervisor 400 "Assign a supervisor first"; switch off -> 404 for all supervision routes.
- **Assert (DB):** `supervisor_id`, `supervisor_attendance`, `opened_by_supervisor_at`; activity rows `supervision` / `supervisor_attendance`. Covered by `test_supervision.py`, `test_api_supervision.py`; **Cleanup:** none.

### Meetings

#### F08-TC-017: Jitsi fallback link generation (REAL) and provisioning job  [P1, REAL]
- **Role:** system (celery beat), admin. **Switches:** `zoom_api` ON (no Zoom credentials exist so Zoom creation fails), then OFF with no academy Zoom. **Data:** J1 starts in 20 min with blank link, J2 starts in 6 h blank (outside the 30 min fallback), J3 with a typed link `https://example.test/room`, J4 cancelled blank, J5 archived blank, J6 blank started 5 min ago. The teacher's `default_meeting_url` empty for this case.
- **Steps:** run `scheduling.provision_meetings` once (`$DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.scheduling.services import meetings; print(meetings.provision_meetings())"`), run it again, then repeat with `zoom_api` off.
- **Expected:** with `zoom_api` on and Zoom unreachable: J1 and J6 get `https://meet.jit.si/Etqan<32 hex>`, `meeting_provider='jitsi'`, `meeting_ref=''`; J2 stays blank (retries later); J3 keeps the typed link, `provider=''`; J4, J5 unchanged; 2nd run changes nothing (idempotent, URLs do not change); two sessions of one class (same teacher + start + minutes) share one URL; links of different classes differ; with the switch off and no academy Zoom the job returns 0 and nothing is generated.
- **Assert (DB):** `meeting_url`, `meeting_provider`, `meeting_ref` per row; regex `^https://meet\.jit\.si/Etqan[0-9a-f]{32}$`; `JITSI_BASE_URL` env respected.
- **Tag:** Jitsi generation REAL; "room actually opens" not tested. Covered by `test_meetings.py` (FAKE). **Cleanup:** none.

#### F08-TC-018: Zoom is FAKE/BLOCKED, and the host-link rules (teacher only)  [P1, FAKE for Zoom / REAL for access rules]
- **Role:** the session's teacher, another teacher, admin, student, parent, supervisor, anonymous, impersonating admin. **Data:** session H1 with a Jitsi link, H2 with a typed link, H3 without link, H4 cancelled with link, H5 of another teacher, H6 with `meeting_provider='zoom'`, `meeting_ref='123'` set through `shell` (FAKE: no Zoom call is made).
- **Steps:** `GET /sessions/<id>/host-link/` with each role/session combination; as admin "impersonate" the teacher and call it.
- **Expected:** own teacher on H1/H2 200 `{"url":<link>,"host":false}` with header `Cache-Control: no-store`; H3, H4, H5 (by the other teacher), unknown id: 404; admin, student, parent, supervisor on H1: 404 (never the link); anonymous 401/403; impersonation 403; H6 with no Zoom credentials returns the join link with `host:false` (never 500, never a start URL); session payloads for others never include any `start_url`.
- **Assert:** responses; no host link in `scheduling_session` columns or logs (grep container logs for `start_url`). Live Zoom start link / meeting creation / `meeting.ended` webhook metering: **BLOCKED** (note in coverage-gaps). Covered by `test_host_link.py`; **Cleanup:** clear H6 ref.

### Archive, log, revert, bulk

#### F08-TC-019: Bulk mark and cancel, per-row results, 200 limit, lock order  [P1, REAL]
- **Role:** admin, then teacher. **Data:** 6 sessions: 2 past scheduled, 1 future, 1 cancelled, 1 payslip-locked, 1 foreign-academy id plus id 999999.
- **Steps:** `POST /sessions/bulk/ {"ids":[...],"action":"present"}`; `action:"cancel"` with and without `reason`; `action:"late"`; 0 ids; 201 ids; duplicate ids; as teacher.
- **Expected:** `done` holds the 2 past; `skipped` lists future `scheduling.not_started`, cancelled `scheduling.session_cancelled`, locked `payroll.payslip_issued`, foreign/unknown `not_found`; each row's result independent (a refusal never rolls back others); cancel without reason 400; bad action 400; 0 or 201 ids 400; duplicates collapse; teacher 403. Concurrent bulk calls with overlapping ids in opposite order do not deadlock (run two in parallel, both complete).
- **Assert (DB):** only `done` ids changed; one activity row per changed session. Covered by `test_actions.py`; **Cleanup:** none.

#### F08-TC-020: Activity log and revert  [P1, REAL]
- **Role:** admin. **Switches:** `activity_log`. **Data:** session L1 with history: mark present, cancel, restore, postpone/times.
- **Steps:** `GET /sessions/L1/activity/`; revert the latest entry `POST /sessions/L1/activity/<entry>/revert/`; revert an older entry whose field has since changed; revert a revert; revert for a payslip-locked session; switch the feature off; teacher/staff-nocode call GET.
- **Expected:** entries newest first with actor, action, `changes {field:[before,after]}`; revert of the newest restores previous values and writes a new entry with `reverts`=old id; stale entry 409 `scheduling.changed_since`; non-revertible 409 `scheduling.not_revertible`; locked session 409 `payroll.payslip_issued`; feature off 404; non-office 403/404. Revert runs as the reverting user (their permissions apply, so a supervisor without `session.update` cannot).
- **Assert (DB):** `scheduling_sessionactivity` columns `actor_id`, `action`, `changes`, `reverts_id`; session columns equal to the "before" values. Covered by `test_activity_revert.py`; **Cleanup:** none.

#### F08-TC-021: Archive and unarchive sessions  [P1, REAL]
- **Role:** admin, staff-codes. **Switches:** `session_archive`. **Data:** old completed A1, old cancelled A2, future scheduled A3, completed-on-payslip A4.
- **Steps:** `POST /sessions/archive/ {"ids":[A1,A2,A3,A4]}`; list default, `?archived=only`, `?archived=include`; subscription remaining/invoice/payroll projection before/after; `POST /sessions/unarchive/`; attempt `restore` on archived future A3; switch off and list.
- **Expected:** only sessions "no longer due" archive (A3 future scheduled skipped/refused; others per rule); default list hides archived; counts (`sessions_remaining`, payroll, invoices) unchanged by archive; `unarchive` needs `session.restore` (staff without it 403); restore of an archived future session 409 `scheduling.archived`; switch off shows all rows again.
- **Assert (DB):** `archived_at` set/cleared; activity `archive`/`unarchive`. Covered by `test_archive_sessions.py`, `test_api_archive_routes.py`; **Cleanup:** unarchive.

#### F08-TC-022: Today view and list filters  [P2, REAL]
- **Role:** admin, teacher, student. **Data:** sessions yesterday 23:30 local (still running after UTC/local midnight), today 00:10, today 23:50, tomorrow 00:10, in Africa/Cairo; one of qaother.
- **Steps:** `GET /sessions/?when=today`, `?when=week`, `?when=upcoming`, `?when=past`, `?status=completed&kind=extra&student_attendance=present`, `?q=<student name>`; `GET /schedule/today/` (today board); `?when=bogus`.
- **Expected:** "today" uses the academy's timezone (`Africa/Cairo`), not UTC: the 00:10 local session is today even though its UTC date is yesterday; the 23:50 local is today; bogus -> 400; filters combine with AND; teacher/student see only theirs; no foreign rows. Today board states (`schedule/today/`) match statuses.
- **Assert (DB):** `occurs_on` (local date) vs `starts_at` (UTC) for the rows. Covered by `test_today.py`, `test_api_sessions.py`; **Cleanup:** none.

#### F08-TC-023: Hand-added sessions: validation, conflicts and delete rules  [P2, REAL]
- **Role:** admin, staff-codes. **Switches:** `manual_sessions`, `extra_sessions` (toggle each). **Data:** Sub A (active), Sub B-cancelled, a student with an inactive account, teacher with an existing session at 10:00.
- **Steps:** create regular session in/out of term and in a pause; for a cancelled subscription; extra with `minutes` 14 / 241 / missing; teacher who does not teach the course; overlapping teacher time; DELETE a hand-added unmarked, a marked, a generated, one with make-up; switch off then DELETE a previously added one.
- **Expected:** valid 201 with `conflicts` warnings for the overlap (not blocked); out-of-term/pause 400 `occurs_on`; cancelled sub 409; minutes outside 15-240 400; wrong teacher 400; delete: only unmarked, unpaid, hand-added, no make-up (else 409 `scheduling.session_generated` / `scheduling.has_compensation` / marked); delete works with the switch off; non-`session.create` staff 403.
- **Assert (DB):** `generated=false`, `created_by_id`, `subscription_id`; a deleted session's report/activity rows are gone (cascade, see S4). Covered by `test_session_classes_manual.py`; **Cleanup:** none.

#### F08-TC-024: Teacher attendance switch and teacher self-attendance  [P1, REAL]
- **Role:** teacher, admin. **Switches:** `teacher_attendance` ON then OFF. **Data:** past session TA1.
- **Steps:** teacher `{"teacher_attendance":"present"}`; teacher marks student present; teacher `{"teacher_attendance":"absent"}` then check consumption; switch OFF: teacher marks student, teacher marks self, teacher stamps times; admin does the same.
- **Expected:** ON: both marks work, teacher mark never changes `status`; `absent` by teacher makes the session non-consuming; OFF: teacher gets 403 on every one (including the student's mark), admin still 200.
- **Assert (DB):** `teacher_attendance`, `status` unchanged by teacher mark on a scheduled session (status stays `scheduled` until the student mark). Covered by `test_attendance.py`; **Cleanup:** switch back ON.

### Boundary and sweep cases

#### F08-TC-025: Start-time gate and timezone boundary  [P1, REAL]
- **Role:** admin, teacher. **Data:** academy tz Africa/Cairo; session starting in 1 minute, session that started 1 second ago (create with `start_time` rounded), session at a DST transition day.
- **Steps:** mark attendance, cancel, times, postpone on each; wait for the minute and re-mark.
- **Expected:** before `starts_at` attendance 409 `scheduling.not_started` for admin as well; after start 200; the gate compares UTC instants: `starts_at` equals local `start_time` converted with the academy zone (Cairo DST: UTC+2 winter / +3 summer; nonexistent/ambiguous local times follow Plan 4's rule); `has_started` in the payload flips accordingly.
- **Assert (DB):** `starts_at` UTC value vs expected from `occurs_on`+`start_time`+tz. **Cleanup:** none.

#### F08-TC-026: Archived session edit hole, and student-mark undo effects (defect probes)  [P2, REAL]
- **Role:** admin. **Switches:** `session_archive`. **Data:** archived completed session AR1; completed session with report RP1.
- **Steps:** on AR1: attendance `absent`, cancel, times, disposal, pays-teacher while archived; on RP1: admin `not_set` then GET report and `/reports/missing/`.
- **Expected (per docs):** an archived session "refuses edits until unarchived" -> each call should be refused. Observed behaviour per code: only postpone and restore check `archived_at`; attendance/cancel/times/disposal likely succeed (S1). After undoing a completed session with a report, status returns to `scheduled` but the report stays (S5); it should not appear in missing reports.
- **Assert:** record exact status codes; DB `archived_at`, `status`, report row. Bug evidence for S1/S5. **Cleanup:** unarchive, re-mark.

## 5. Suspected defects from code reading (S1..)

- **S1 (P2):** `attendance.mark_attendance`, `cancel_session`, `place_at_disposal`, `times.record_times` and `set_pays_teacher` never call `rules.refuse_if_session_archived` (only `postpone_session` and `restore_session` do), although `docs/features/sessions.md` says an archived session "refuses edits until it is unarchived". An archived session can still be marked, cancelled, re-timed, so counts and payroll move while the row is hidden from default lists. Probe: TC-026.
- **S2 (P2):** `AttendanceView` has no upper bound on how old a session can be; a teacher can (re)mark or flip `present`/`absent` on any started session until a payslip is issued, changing consumption and pay retroactively. Probe: TC-002/TC-006 (mark an old session as teacher), then check the projection.
- **S3 (P1/P2, confirm intent):** the seeded Supervisor preset holds `session.update` and `attendance.update`, so a supervisor can cancel, bulk-cancel, place at disposal and mark attendance for every session of the academy, not only those assigned to them (scope is office-wide for staff). Probe: TC-012.
- **S4 (P3):** `delete_session` deletes the row with `SessionActivity` and `SessionReport` cascading, so the audit trail of a hand-added session disappears when it is deleted. Probe: TC-023.
- **S5 (P3):** admin undo (`student_attendance=not_set`) of a completed session returns it to `scheduled` but keeps its `SessionReport`; the "report requires completed" rule is then violated and payloads show `has_report` on a scheduled session. Probe: TC-026.
- **S6 (P2):** `update_session_supervision._set_attendance` (PATCH `supervisor_attendance`) has no start-gate or cancelled/archived check and no payroll-lock check, unlike the supervisor's own `mark_supervisor_attendance`; staff with `attendance.update` can mark a future or cancelled session's supervisor present. Probe: TC-016.
- **S7 (P2):** `host_link_for` has no time window, no archived/completed check and no active-teacher check: the session's teacher (even a deactivated one with a live session cookie, or after the session ended) can still obtain the join link; for Zoom it fetches a new start link at any time. Probe: TC-018.
- **S8 (P3):** `AttendanceInput` accepts the same value repeatedly and writes a new activity entry / overwrites `marked_by` on each identical re-mark (no idempotency), so a double-click by another person silently changes the recorded marker. Probe: TC-006.
- **S9 (P3):** requirement gap: the task lists "late" as an attendance status, but the model supports only present/absent/excused. If the owner expects "late" it is missing (see coverage-gaps).
- **S10 (P2):** `create_regular_session`/`create_extra_session` accept `occurs_on` in the past with no limit, so a hand-added past session can be marked and paid immediately (pay manufactured by a single admin call). Probe: Setup step 4, TC-003.

## 6. Case summary

| Priority | Cases |
|---|---|
| P1 | 22 (001-014, 016-021, 024, 025) |
| P2 | 4 (015, 022, 023, 026) |
Total 26. UI smoke: TC-001 only (plus optional: TC-009 student postpone dialog, TC-014 report dialog if time).

#### F08-TC-027 (added by Agent 2): Retroactive teacher re-mark moves consumption and pay until a payslip locks it  [P1, REAL]
- **Role:** teacher `qa-teacher`. **Data:** P8 (11 days old, Sub B, scheduled after the TC-006 undo), P6 (on issued payslip PAY-000039).
- **Steps:** teacher marks P8 present, then `teacher_attendance=absent`, then `present`; read Sub B `sessions_remaining` and the salary projection after each; teacher marks P6.
- **Expected:** each change applies (no age limit by design: the payroll lock is the documented bound, `docs/features/sessions.md` §Attendance, `paylock.py`), is logged with the teacher as actor, and moves consumption and pay consistently; P6 409 `payroll.payslip_issued`.

## 7. Results (Agent 2, 2026-10-19 16:36–16:55Z, lean mode, backend/dashboard working tree `qa/campaign-2026-10`)

Setup: `evidence/F08/s0-setup.txt`, `s1-setup.txt` (switches on, Sub A 82 + Sub B 83 for qa-student/qa-teacher from 2026-10-01, 14 hand-added sessions 235–250; ids in `scripts/ids.env`).
Spec corrections found while executing: QA teacher's rate is 6000 minor/h (not 12000), so TC-003 amounts are 6000/3000/4500; the academy defaults were `absent_consumes_session=true`, `excused_consumes_session=false` (restored after TC-002).

| Case | Pri | Result | Tag | Evidence | Notes |
|---|---|---|---|---|---|
| TC-001 | P1 | PASS | REAL | `pw-run1.txt`, `pw/tc001-*.png`, `tc001-db.txt` | UI: teacher Today tab → Present on U1 (Sub C 84, "QA Student Two"); API 200, DB completed/present, `marked_by_id=7`, activity `{status, student_attendance}`; Sub C used 0→1, remaining 8→7. "Not set" option disabled for the teacher |
| TC-002 | P1 | PASS | REAL | `tc002-003.txt` | absent/excused/teacher-absent do not consume; present −1; `absent_consumes` → −1, `excused_consumes` → −1; SQL count = API every step; `late` 400 |
| TC-003 | P1 | PASS | REAL | `tc002-003.txt` | X1 60 min +6000, X2 (pays off) +0 then +3000, X4 45 min +4500; Sub A remaining unchanged by extras; integers only |
| TC-004 | P1 | PASS | REAL | `tc004-005.txt` | payslip 42 (July, teacher 7) issued: attendance×2, cancel, restore, postpone, times, disposal, pays-teacher, DELETE → 409 `payroll.payslip_issued`; bulk present/cancel → skipped with that code; net 6000 unchanged; no new activity. Observation: `PUT report` on the locked session is 200 (reports are outside the lock per paylock docstring) |
| TC-005 | P1 | PASS | REAL | `tc004-005.txt` | empty reason 400; cancel/second cancel 409; attendance on cancelled 409; restore clears cancel fields; present+cancel+restore → completed; future 409 `not_started`; 5 activity rows |
| TC-006 | P1 | PASS | REAL | `tc006-007.txt` | identical re-mark: 200 and **no** new activity row (S8 refuted); 5 concurrent mixed marks all 200, serialised (4 activity rows, final consistent); teacher `not_set` 403; admin undo → scheduled; no 500 |
| TC-007 | P1 | PASS | REAL | `tc006-007.txt`, `tc007b-008.txt` | switch off 404; at_disposal; student mark 409, teacher mark OK (status kept); restore clears reason; disposal on completed 409; cancel from at_disposal keeps reason; remaining unchanged; `run_daily` keeps P9 |
| TC-008 | P1 | PASS | REAL | `tc007b-008.txt` | make-ups for cancelled C1 and excused C2 (201, original `compensated=t`, `compensated_by=makeup`); second 409 `already_compensated`; extra/future/consuming 409 `not_compensable`; frozen original 409 `has_compensation` ×5; cancel make-up unfreezes; new make-up M3 then restore of M1 409; check constraint + partial unique index present; package never +1 |
| TC-009 | P1 | PASS | REAL | `tc009.txt`, `tc010.txt` | student: >14 d 400, busy 409, valid 200 (slot left, original_* set); F5 in 90 min 409 `too_late_to_postpone`; admin 200 with `conflicts` [{session, other}]; other family 404; parent OK; DST: 10-31 15:00 → 13:00Z (UTC+2); teacher back to the original slot → `slot_id` reattached, original_* null; `run_daily` no duplicate (slot,date) |
| TC-010 | P1 | PASS | REAL | `tc010.txt` | completed/cancelled/at_disposal/teacher_in/expired-sub 409 `not_allowed_in_status`; compensated originals 409 `has_compensation`. Not runnable: archived future session (D-5 refuses archiving a future session; covered by pytest `test_archive_refusals`), pause date (package has 0 freeze days). 11-03 for Sub B (term 10-31) accepted: inside grace = the generation window (doc line 59, `rules.generation_last_day`), by design |
| TC-011 | P1 | PASS | REAL | `tc011.txt` | admin/supervisor all 214; staff-nocode/codes 403; teacher 103 / student 82 / parent 82 = DB own counts, foreign 404, CSV 403, activity 404; anon 403; student/parent payload hides cancel_reason/notes/has_report/payroll_locked; teacher sees has_report |
| TC-012 | P1 | PASS | REAL | `tc012.txt` | full matrix on fresh pairs per role. Supervisor may disposal/restore/pays/times/attendance/report/bulk/cancel on an unassigned session, 403 archive/delete/create: **S3 by design** (`roles-permissions` spec §3.4 preset holds academy-wide `update`); teacher own only (S2 404, cancel/bulk/etc. 403); student/parent/staff 403/404; `marked_by` = actor |
| TC-013 | P1 | PASS | REAL | `tc013.txt` | qaother admin on its host: 16 session routes on a qa id → 404; bulk `[Q1, qa id]` → done [Q1], skipped not_found; cookies across hosts 403; qaother list/CSV only own rows; qa schema count/max(updated_at)/activity/report unchanged |
| TC-014 | P1 | FAIL (P4) | REAL | `tc014.txt` | missing list = R1 only; teacher PUT creates, admin PUT replaces (one row, `written_by` kept, `updated_at` moves); 0/6/"a" 400; scheduled 409 `not_completed`; student/parent/other teacher 404; switch off 404 and R1 leaves the list. P4 **ETQAN-QA-047**: `has_report` still shown while `session_reports` is off. Report on an absent-marked session is accepted (not specified) |
| TC-015 | P2 | PASS | REAL | `tc015-024.txt` | early teacher_in 200, early out 409; teacher student_in 403; 55-min span → actual 55; out<in 400; >600 400; admin override 45; pay still 6000 (minutes 60) |
| TC-016 | P1 | FAIL (P3) | REAL | `tc016.txt` | list shows V1–V4 (not cancelled V5, not V6); open V1/V3 200 (stamp once), V2 409 not_open, V4 409 ended, V5 409 cancelled, V6 404; attendance V3/V4 OK, V2 409, excused 400; staff-codes 403; reassign resets attendance/stamp; no supervisor 400; switch off 404. **S6 confirmed → ETQAN-QA-044 (P3)**: office PATCH sets supervisor present on a future (V2) and a cancelled (V5) session |
| TC-017 | P1 | PASS | REAL (Jitsi) | `tc017.txt` | zoom_api off → 0; on (no Zoom account): J1/J7 (one class) share one `meet.jit.si/Etqan<32hex>`, J8/J2/J6 own rooms, J3 typed link kept, J4 cancelled untouched; run 2 → 0 (idempotent); off again → 0. Spec expectation for J2 corrected: with no Zoom account `create_meeting` returns Jitsi at once; the 30-min rule applies only to a Zoom *failure* (FAKE, pytest `test_meetings.py`) |
| TC-018 | P1 | PASS | REAL rules / FAKE Zoom | `tc018.txt` | own teacher H1/H2/H6 200 `host:false` + `Cache-Control: no-store`; no link/cancelled/other teacher/unknown 404; admin/student/parent/supervisor 404; anon 403; impersonation 403 `identity.impersonating`; H6 (zoom ref, no creds) join link, no 500; no `start_url` in payloads, list, logs, DB. S7: link still given after the session ended (same join link every in-scope payload already carries) — no extra exposure for Jitsi/typed links; Zoom start-link timing live **BLOCKED** |
| TC-019 | P1 | PASS | REAL | `tc019.txt` | per-row done/skipped codes (not_started, payslip_issued, session_cancelled, not_found), duplicates collapse, 2 activity rows; reason/late/0/201 → 400; teacher 403; two opposite-order concurrent bulks both 200, no deadlock |
| TC-020 | P1 | PASS | REAL | `tc020.txt` | entries newest first with actor/changes/can_revert; revert newest, revert restore, stale 409 `changed_since`, revert-of-revert, locked 409, compensated 409; teacher/student 404, staff 403, supervisor 200; switch off 404 |
| TC-021 | P1 | PASS | REAL | `tc021-026.txt` | archive done for completed/cancelled/locked, future skipped; default list hides, only/include show; remaining/projection unchanged; staff-codes and supervisor unarchive 403; switch off shows all + routes 404. Restore of an archived *past* cancelled session 200 = Plan 31 R7 (only a future start is refused); student lists include archived rows by design (`archived_mode`) |
| TC-022 | P2 | PASS | REAL | `tc022.txt` | today = Cairo date (00:10 local whose UTC date is yesterday is today; 23:50 today; tomorrow 00:10 not); week/upcoming/past consistent for admin/teacher/student; bogus 400; AND filters = DB 62; q works, no foreign rows; Today board office only (teacher/student 403) |
| TC-023 | P2 | PASS | REAL | `tc023-025.txt` | out of term 400; archived/cancelled sub 409; minutes 14/241/missing 400; wrong teacher 400; overlap 201 with 2 conflicts; delete marked 409 `session_marked`, generated 409 `session_generated`, make-up original 409; delete with switches off 204; create with switch off 404. S4: activity rows go with the session = **by design** (B2c spec C-9 CASCADE) |
| TC-024 | P1 | PASS | REAL | `tc015-024.txt` | ON: teacher self-present keeps `scheduled`, student mark completes, teacher absent un-consumes; OFF: teacher attendance/self/times 403, admin 200; report write still allowed |
| TC-025 | P1 | PASS | REAL | `tc023-025.txt` | session 1 min ahead: admin/teacher attendance, times, bulk → not_started; after start (has_started flips) 200; ambiguous 10-29 23:30 → first occurrence 20:30Z, 10-30 00:30 → 22:30Z |
| TC-026 | P2 | FAIL (P3) | REAL | `tc021-026.txt` | S1: archived rows accept attendance (consumption 6→7), pays-teacher (−6000), times, cancel, restore, report, bulk = **by design** (B2d spec D-7 "Archived sessions still take writes"); the feature doc says the opposite → **ETQAN-QA-046 (P4 doc)**. **S5 confirmed → ETQAN-QA-045 (P3)**: undo leaves `scheduled` + `has_report=true`, report readable but not editable (409), not in missing list |
| TC-027 | P1 | PASS | REAL | `tc027.txt` | added by Agent 2: teacher flips an 11-day-old session; remaining and projection move consistently (+3000 / −3000), all logged; locked P6 409. S2 = by design (payroll lock is the bound) |

UI smoke (Playwright `e2e/qa/f08-sessions-attendance.spec.ts`, workers=1): 3/3 PASS first run (TC-001 teacher mark, admin session page Activity, student read-only). pytest `etqan/scheduling`: **1380 passed** (110 s), `pytest-scheduling.txt`.

Suspected defects: S1 by design (D-7) + doc mismatch QA-046 · S2 by design · S3 by design (§3.4) · S4 by design (C-9) · S5 **confirmed** QA-045 · S6 **confirmed** QA-044 · S7 no extra exposure (Zoom live BLOCKED) · S8 refuted · S9 requirement gap stays in coverage-gaps (no `late`, 400) · S10 by design (B2a line 68 "A start in the past is allowed").

Totals: 27 executed · 24 PASS · 3 FAIL (P3 ×2, P4 ×1 + P4 doc) · 0 BLOCKED (live Zoom sub-parts of TC-017/018 BLOCKED, tagged). No P0–P2 found.
Left in place (qa disposable): Sub A 82, B 83, C 84; sessions 235–309; payslip 42 (PAY-000039, July, teacher 7) issued; Jitsi links on 14 qa sessions due today; settings restored (absent=true, excused=false), zoom_api off, all session switches on.
