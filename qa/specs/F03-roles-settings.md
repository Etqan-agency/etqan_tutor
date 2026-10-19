# F03: Roles, permissions and academy settings (F03 + F04 merged)

Author: Agent 1 (research and test strategy, LEAN mode). This spec approves nothing.
Written 2026-10-18 from backend adff9c9 / dashboard 5ed775d. Log: `qa/logs/F03/agent1.md` (not written, lean).

Sources read: `platform/{permissions,features,validators}.py`, `access/{services,presets,models,registry}.py`,
`access/api/*`, `academy/{services,models}.py` + `academy/api/*`, `translations/{services}.py` + `api/views.py`,
`systemstatus/{services}.py` + `api/views.py`, `identity/impersonation.py`, `identity/api/people_views.py`
(QuickLoginView), `billing/api/views.py`, `payroll/api/views.py`, `scheduling/api/{session,supervision}_views.py`,
`docs/features/{roles-permissions,academy-settings,feature-toggles}.md`.

## 1. Facts the cases rely on (read from code)

- `HasCode`: admin always passes; staff pass if an ACTIVE role holds the code in `permission_codes[method]`
  (tuple = any); everyone else fails. No code declared for the method = admin only.
- `FeatureOn` (listed after `HasCode`) raises **404** "This feature is not enabled for this academy." when the
  switch is off. **The task brief says 403; code and `docs/features/feature-toggles.md` say 404. Expected value
  in this spec is 404 for a caller who passes the role check and 403 for a caller refused by it.**
- Role endpoints (`/api/v1/access/`): `registry/`, `roles/` (GET list, POST), `roles/<id>/` (GET, PATCH), `staff/`
  (GET, POST), `staff/<id>/` (GET, PATCH). No PUT/DELETE (expect 405).
- Role: `name_ar`, `name_en` (max 60, unique `Lower()` each, DB constraints `access_staffrole_name_{en,ar}_ci_unique`),
  `permissions` JSON (sorted, deduped, registry codes only), `is_active`. Table `academy_qa.access_staffrole`,
  members in `access_staffrole_members`.
- Settings: `GET/PATCH /api/v1/academy/settings/` = `[HasCode | ReadOnly]`: every signed-in user reads; PATCH needs admin or
  staff `academy_settings.update`. Bounds: horizon 1..60, grace 0..60, due days 0..90, postpone 0..10080 (only while
  `postponement` is on). `default_currency` is only `^[A-Z]{3}$` after upper-casing. Table `academy_qa.academy_academysettings`.
- `GET /api/v1/academy/features/`: `HasCode` with no codes = admin only. Read-only (no write method exists).
- Quick translate: `PUT|DELETE /api/v1/translations/<lang>/<key>/` needs `page.quick_translate` + feature `quick_translate`;
  `GET /api/v1/translations/` anonymous, `{}` while off. Table `academy_qa.translations_translationoverride`.
- System status: `GET /api/v1/system-status/`, `POST /api/v1/system-status/runs/` need `page.system_status` + feature
  `system_status`. Table `academy_qa.systemstatus_jobrun`.
- Impersonation: `POST /api/v1/people/{students|parents|teachers}/<id>/quick-login/` (feature `quick_login`, code
  `quick_login.create`, staff also need `<kind>.view`); stop at `POST /api/v1/identity/impersonation/stop/`.
  `NotImpersonating` -> 403 `{"code":"identity.impersonating"}`.

## 2. Setup (run once, academy `qa`)

Conventions: host `qa.etqan.localhost`, API base `http://qa.etqan.localhost/api/v1`. Passwords in `environment.md`.
`DC=/private/tmp/claude-501/-Users-khaledsakr-Documents-Etqan-tutor/55afddca-abb7-4698-b08b-38df7f0acb0e/scratchpad/dc.sh`

```bash
# S1. Switch everything this spec needs on, in qa only (set_features accepts many codes after --on)
$DC exec -T django python manage.py set_features qa --on invoices payment_receipts payroll_rules quick_login \
   supervision postponement quick_translate system_status themes spanish parents families session_reports \
   student_teacher_rate teacher_balance
# S2. Login helper (cookie jar per actor; CSRF token from the csrf cookie). Usage: login <jar> <host> <email> <password>
login(){ curl -s -c $1 http://$2/api/v1/identity/csrf/ >/dev/null; T=$(awk '/csrftoken/{print $7}' $1);
  curl -s -b $1 -c $1 -H "X-CSRFToken: $T" -H 'Content-Type: application/json' -H "Origin: http://$2" \
   -d "{\"email\":\"$3\",\"password\":\"$4\"}" http://$2/api/v1/identity/login/ -o /dev/null -w '%{http_code}\n'; }
# call <jar> <host> <METHOD> <path> [json]   (adds CSRF header for writes)
call(){ T=$(awk '/csrftoken/{print $7}' $1); curl -s -b $1 -c $1 -X $3 -H "X-CSRFToken: $T" -H "Origin: http://$2" \
   -H 'Content-Type: application/json' ${5:+-d "$5"} http://$2/api/v1$4 -w '\n%{http_code}\n'; }
login /tmp/adm  qa.etqan.localhost qa-admin@qa.etqan.test 'QA-Admin-2026!'
login /tmp/nocode qa.etqan.localhost qa-staff-nocode@qa.etqan.test 'QA-People-2026!'
login /tmp/codes  qa.etqan.localhost qa-staff-codes@qa.etqan.test 'QA-People-2026!'
login /tmp/sup    qa.etqan.localhost qa-supervisor@qa.etqan.test 'QA-People-2026!'
login /tmp/tch qa.etqan.localhost qa-teacher@qa.etqan.test 'QA-People-2026!'
login /tmp/stu qa.etqan.localhost qa-student@qa.etqan.test 'QA-People-2026!'
login /tmp/par qa.etqan.localhost qa-parent@qa.etqan.test 'QA-People-2026!'
login /tmp/oadm qaother.etqan.localhost qaother-admin@qa.etqan.test 'QA-Other-2026!'
# S3. Money fixtures (via API as admin): a subscription + invoice in EGP so currency-change cases have rows.
#     Create a course/teacher/subscription through the existing QA people (see feature-inventory.md), then
call /tmp/adm qa.etqan.localhost POST /billing/invoices/ '{"student":<QA_STUDENT_ID>,"currency":"EGP","lines":[{"description":"QA F03","amount_minor":150000}]}'
#     (exact invoice body: read backend/etqan/billing/api/serializers.py InvoiceCreateInput before running)
# S4. Playwright smoke: use the scratchpad pw/ setup from environment.md; E2E_MANAGE=<scratchpad>/manage-wrap.sh
# S5. DB checks: PGPASSWORD=etqan psql -h localhost -p 5433 -U etqan etqan -c "set search_path=academy_qa; <sql>"
# S6. Record baseline before the run: select * from academy_academysettings; select id,name_en,permissions,is_active from access_staffrole;
```

Role/ID discovery: `call /tmp/adm qa.etqan.localhost GET /access/roles/` (ids of "Supervisor", "QA No Codes", "QA Student View").
Cleanup rule for every case: roles are never deleted, so created roles are named `F03-*` and retired at the end; settings
are restored to the S6 baseline; translation overrides are deleted; throwaway staff are deactivated.

Existing coverage (backend pytest, do not duplicate except where marked P1-critical): `access/tests/{test_roles,test_staff,
test_registry,test_routes,test_me,test_supervisors,test_access_api}.py`, `academy/tests/{test_api,test_services,
test_features_api}.py`, `translations/tests`, `systemstatus/tests`, `identity/tests/test_impersonation*.py`,
`platform/tests/test_feature_on.py`, dashboard e2e `features.spec.ts`, `b9-platform.spec.ts` (reconcile + theme),
`b9-languages.spec.ts`. None of these hit the live stack, a real session cookie, or two academies together.

## 3. Test cases (27)

Legend: P1 = critical. Provider REAL unless stated. "A" = qa admin jar, "O" = qaother admin jar.

### Roles and staff workflows

**F03-TC-001 (P1) Owner builds a "Front desk" role and hires staff, end to end.**
Role: A. Switches: S1. Data: none.
1. `GET /access/registry/` -> 200, contains resources, `page.*`, `widget.*`, `in_use` flags.
2. `POST /access/roles/` `{"name_ar":"F03 الاستقبال","name_en":"F03 Front desk","permissions":["student.view_any","student.view","invoice.view_any","invoice.view"]}` -> 201, `permissions` sorted, `is_active=true`, `members=0`.
3. `POST /access/staff/` `{"full_name":"F03 Hana","email":"f03-hana@qa.etqan.test","role_ids":[<id>]}` -> 201, `invited=true`.
4. Mailpit `GET http://localhost:8025/api/v1/search?query=to:f03-hana@qa.etqan.test` -> one set-password mail; complete it, then `login` as Hana.
5. Hana `GET /identity/me/` -> `role=staff`, `permissions` equals the 4 codes, `is_super_admin=false`.
6. Hana `GET /people/students/` 200; `GET /billing/invoices/` 200; `POST /billing/invoices/` 403; `GET /payroll/rates/` 403; `GET /access/roles/` 403.
Assertions: DB `access_staffrole` row (permissions JSON identical, `is_active`), `access_staffrole_members` 1 row, `identity_user.role='staff'`. Roles list `member_count` 1 after Hana is active.
Cleanup: retire role, deactivate Hana. Cites: `test_access_api.py` covers pieces; this is the whole live chain. Provider: REAL (mailpit sink).

**F03-TC-002 (P1) Role validation and naming rules.**
Role: A. Steps (all `POST /access/roles/` unless noted), expected status in brackets:
- duplicate `name_en` in different case `"f03 FRONT DESK"` [400, field `name_en`]; duplicate `name_ar` [400];
- blank/whitespace names [400]; 61-char name [400]; name with surrounding spaces is stored trimmed;
- `permissions:["nope.view"]` [400 "Unknown permission"]; `permissions:"student.view"` [400]; `permissions:[1]` [400]; `permissions:null` [400];
- duplicates `["student.view","student.view"]` -> stored once; greyed (not `in_use`) code e.g. `student.delete` accepted and stored;
- `PATCH /access/roles/<id>/` with `{"members":[1]}` or `{"id":9}` [400 "Unknown field"]; `PUT` and `DELETE` [405]; `GET /access/roles/999999/` [404].
- Supervisor preset: try renaming a role to `"supervisor"` [400].
Assertions: DB rows unchanged on every 4xx (count of `access_staffrole` constant). Cleanup: retire created. Cites: `test_roles.py` unit-level; re-run live only the unique-name and unknown-code items (P1: DB constraint on the real schema).

**F03-TC-003 (P1) Retiring and restoring a role takes effect on a live session at once.**
Role: A, staff Hana (TC-001). Switches: S1.
1. Hana is logged in; `GET /billing/invoices/` 200.
2. A: `PATCH /access/roles/<id>/` `{"is_active":false}` -> 200.
3. Hana (same jar, no re-login): `GET /billing/invoices/` -> 403; `GET /identity/me/` -> `permissions=[]`.
4. `GET /access/staff/<hana>/` still lists the retired role (members kept); `GET /access/roles/?active=false` lists it.
5. `POST /access/staff/` with `role_ids:[<retired>]` -> 400 "A retired role can't be added".
6. A: `PATCH ... {"is_active":true}` -> Hana's invoice GET is 200 again without any change on her account.
7. A: edit permissions `{"permissions":["student.view_any"]}` -> Hana loses invoice access immediately (live permission change).
Assertions: `access_staffrole_members` row for Hana never removed. Cleanup: retire role. Cites `test_roles.py` (service); live-session timing is new.

**F03-TC-004 (P1) Anti-escalation: staff editors cannot hand out or strip codes they do not hold.**
Setup: role `F03 Role editor` = `{role.view_any, role.view, role.create, role.update, staff.view_any, staff.view, staff.create, staff.update, student.view_any}`; staff Ed holds it. A second role `F03 Money` = `{invoice.view_any, payment.view_any, payslip.view_any}` held by staff Mo.
Steps (as Ed):
1. `POST /access/roles/` with `permissions:["invoice.view_any"]` -> 403 (Ed lacks it). With `["student.view_any"]` -> 201.
2. `PATCH /access/roles/<Money>/` `{"permissions":[]}` -> 403 ("only remove permissions you hold"). `{"permissions":["invoice.view_any","payment.view_any","payslip.view_any","student.view_any"]}` -> 403 is NOT expected: adding a held code while keeping the unheld ones is allowed -> 200 (verify; this is the "keeping is always allowed" rule).
3. `POST /access/staff/` `{"role_ids":[<Money>]}` -> 403; `PATCH /access/staff/<Mo>/` `{"email":"x@qa.etqan.test"}` -> 403; `{"is_active":false}` -> 403.
4. `PATCH /access/staff/<Ed>/` `{"role_ids":[]}` -> 403 "can't change your own roles"; `{"is_active":false}` -> 403.
5. `PATCH /access/roles/<Money>/` `{"is_active":true}` after A retired it -> 403.
Assertions: DB `permissions` of Money unchanged after each 403. Cleanup: retire F03 roles, deactivate Ed/Mo. Cites `test_roles.py`, `test_staff.py` (service); P1-critical, live re-run of steps 1, 2, 5 only.

**F03-TC-005 (P1) Suspected S1: a role editor retires a stronger role.** Same Ed/Mo as TC-004.
1. Ed: `PATCH /access/roles/<Money>/` `{"is_active":false}`.
Expected by intent (anti-escalation, `roles-permissions.md` rule set): refused with 403, because Ed does not hold Money's codes and the retire strips Mo's access (and a retired role can only be restored by someone who holds all its codes, so Ed cannot undo it). Code: `update_role` guards only the **restore** branch, not retire.
2. If it returns 200: confirm Mo now gets 403 on `GET /billing/invoices/`, and Ed cannot restore it (403). Also Ed `PATCH {"name_en":"x","name_ar":"y"}` on Money (rename) -> note result.
Assertions: `access_staffrole.is_active` for Money, Mo `me.permissions`. Priority P1 if it succeeds (privilege boundary; lockout of a stronger account). Cleanup: A restores Money.

**F03-TC-006 (P2) Staff account lifecycle and listing.**
Role: A. Steps: `POST /access/staff/` missing email [400]; duplicate email of an existing person (e.g. `qa-teacher@qa.etqan.test`) [400]; `role_ids:[999999]` [400]; role id from academy qaother (get it via O) [400, not leaked]; `role_ids:"1"` [400]. `GET /access/staff/?search=hana&role=<id>&active=true` returns Hana only; admin `qa-admin@` never appears. Deactivate: `PATCH /access/staff/<id>/ {"is_active":false}`: her old session now 401/403 on `/identity/me/`, login fails, `role_ids` kept. Reactivate works.
Assertions: `identity_user.is_active`, sessions invalidated (`django_session` count for user). Cites `test_staff.py`. Cleanup: deactivate.

**F03-TC-007 (P1) Supervisor preset and supervision rules.**
Role: A. Switches: `supervision`.
1. DB: `select permissions from access_staffrole where name_en='Supervisor'` equals exactly the 20 codes (view+view_any of student, teacher, parent, family, subscription, session, attendance, session_report = 16, plus session.update, attendance.update, session_report.update, session.supervise); `qa-supervisor@` is a member. Verify nothing on money or settings: `me.permissions` of supervisor has no `invoice.*`, `payslip.*`, `academy_settings.*`.
2. `GET /supervision/supervisors/` as A -> includes the supervisor, never an admin, never `qa-staff-nocode`.
3. Retire Supervisor role -> list no longer has them; restore -> back. Deactivate the supervisor user -> gone.
4. Role without `session.supervise` (QA Student View) never listed. With `supervision` off: `GET /supervision/supervisors/` -> 404 (A), 403 (nocode staff).
5. Probe: assign the supervisor to a session (`PATCH /sessions/<id>/ {"supervisor":<id>}` per `session_views.py`), then retire the role: does the session keep a dangling supervisor, and does the supervisor lose `/supervision/` access (403)? Record the behaviour (feeds S4).
Assertions: DB above. Cites `test_supervisors.py`. Cleanup: restore role/users.

### Permission enforcement

**F03-TC-008 (P1) Matrix 1: settings, features and roles endpoints for all actors.**
Actors: A, `nocode` staff, `codes` staff, supervisor, teacher, student, parent, anonymous (no jar). Table of expected statuses:

| Request | admin | staff nocode | staff w/ code | supervisor | teacher | student | parent | anon |
|---|---|---|---|---|---|---|---|---|
| GET `/academy/settings/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401/403 |
| PATCH `/academy/settings/` `{"renewal_grace_days":7}` | 200 | 403 | 403 (200 only with `academy_settings.update`) | 403 | 403 | 403 | 403 | 401/403 |
| GET `/academy/features/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 401/403 |
| GET `/access/roles/` | 200 | 403 | 403 (200 with `role.view_any`) | 403 | 403 | 403 | 403 | 401/403 |
| POST `/access/roles/` | 201 | 403 | 403 | 403 | 403 | 403 | 403 | 401/403 |
| GET `/access/staff/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 401/403 |
| GET `/people/admins/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 401/403 |

Then grant `codes` staff (via a role) `academy_settings.update` only -> PATCH 200, features still 403. Assertions: status codes, plus no row change in `academy_academysettings.updated_at` for the 403s. Note exact anonymous code (401 vs 403) in evidence. Cleanup: revert role.

**F03-TC-009 (P1) Matrix 2: business endpoints (people, scheduling, billing, payroll).**
Same actors plus a "partial staff" holding only `student.view_any,invoice.view_any,session.view_any,payslip.view_any`. Requests and expected:
- people: GET `/people/students/` admin 200, nocode 403, partial 200, supervisor 200, teacher/student/parent 403, anon 401/403; POST `/people/students/` partial 403; GET `/people/teachers/` partial 403; GET `/people/admins/` all non-admin 403.
- scheduling: GET `/sessions/` admin 200, partial 200, nocode 403, teacher/student/parent 200 but **own rows only** (ReadsOwn); POST/PATCH `/sessions/<id>/` by student 403; `GET /subscriptions/` per `HasCode`.
- billing: GET `/billing/invoices/` admin 200, partial 200, student/parent 200 own rows, **teacher 403**; POST `/billing/invoices/` partial 403, student 403; `POST /billing/invoices/<id>/void/`, `POST /billing/payments/<id>/refund/` partial 403.
- payroll: GET `/payroll/payslips/` admin 200, partial 200, teacher 200 own issued/paid only, student/parent 403; `GET /payroll/rates/` partial 403, teacher 403; `POST /payroll/payslips/generate/` partial 403; `POST /payroll/payslips/<id>/mark-paid/` partial 403.
Assertions: statuses; result sets for teacher/student/parent contain only rows where the DB `student_id`/`teacher_id` is theirs. Cites per-app pytest route tests; this is the live cross-app sweep. Cleanup: none.

**F03-TC-010 (P1) Row scope: own-data roles never see others' rows; office sees all.**
Role: student `qa-student`, a second student, parent of student 1, teacher.
1. Create a second invoice for another student (A). Student 1 `GET /billing/invoices/` -> only own; `GET /billing/invoices/<other>/` -> 404 (not 403). Same for `/sessions/<other>/`, `/payroll/payslips/<other>/` as teacher B.
2. Parent sees only linked child's invoices; unlink guardian (`DELETE /people/students/<id>/guardians/<pid>/`) -> parent loses them at once.
3. Staff with `invoice.view_any` sees both rows.
Assertions: row counts vs `select count(*) from billing_invoice where student_id=...`. Cleanup: relink guardian. Provider REAL.

**F03-TC-011 (P1) Cross-academy isolation of roles, staff and settings.**
1. A creates role `F03 Iso`; O `GET /access/roles/` does not list it; O `GET /access/roles/<A-id>/` -> 404 (or its own different row, compare ids); O `PATCH` it -> 404.
2. Use A's session cookie against `qaother.etqan.localhost/api/v1/identity/me/` -> 401/403 (cookie is per host; also try replaying with `Host: qaother.etqan.localhost`).
3. Login on qaother host as `qa-staff-codes@qa.etqan.test` -> 400/401 (account does not exist there).
4. O `PATCH /academy/settings/ {"default_currency":"GBP"}`; A `GET` still EGP. DB: `academy_qa.academy_academysettings` vs `academy_qaother.academy_academysettings` differ.
5. `POST /access/staff/` on qa with the email of a qaother person -> succeeds independently (same email may exist in both academies); verify no cross-link in DB.
6. Translation override set in qa never appears in `GET qaother.../translations/` and vice versa.
Cleanup: revert qaother currency to USD, retire F03-Iso. Provider REAL.

**F03-TC-012 (P1) Feature off: 404 for allowed callers, 403 first for unauthorised, dashboard `me.features`.**
Switches: toggle with `set_features qa --off invoices` then `--on invoices` at the end.
1. `GET /identity/me/` as A -> `features` has no `invoices`, `online_payments`, `payment_links` (prerequisite chain: `requires`). `GET /academy/features/` row `invoices` `on=false`; `online_payments` shows `held_by:["invoices"]`.
2. A `GET /billing/invoices/` -> **404** "This feature is not enabled for this academy." (docs/code), not 403. Student (READERS passes) -> 404. `nocode` staff -> **403** (role check first). Teacher -> 403.
3. Mixed gate: `GET /billing/payments/` (`payment_receipts`) with `invoices` on but `payment_receipts` off -> 404; `GET /billing/settings/` follows `invoices`.
4. Data survives: `select count(*) from billing_invoice` unchanged after switching off and on.
5. Switch a default-on feature off (`families`): `/people/families/` 404 for A.
6. Note the brief's "403" expectation: record the observed code per case and report mismatch against the brief, not against the code.
Cites `platform/tests/test_feature_on.py`; live DB/state restoration is new. Cleanup: restore switches from S1.

**F03-TC-013 (P1) Admin can only read feature switches.**
Role: A (and staff with every code). `GET /academy/features/` -> 200, 88 entries (`select jsonb_object_keys` not needed, count the response vs `platform/features.py` REGISTRY), each with `code,label_ar,label_en,group,on,built,held_by`. `POST|PUT|PATCH|DELETE /academy/features/` -> 405; `PATCH /academy/features/invoices/` -> 404. Try writing via settings: `PATCH /academy/settings/ {"features":{"invoices":false},"supervision_enabled":true}` -> 200 but `supervision_enabled` unchanged and `public.tenants_academy.features` unchanged (`select features from public.tenants_academy where subdomain='qa'`). Staff holding every non-admin code (build a role from the whole registry) -> 403. Change a switch with `set_features` and confirm the next GET reflects it (no stale cache). Cleanup: restore.

**F03-TC-014 (P1) Impersonation (quick login) and `NotImpersonating`.**
Switches: `quick_login`. Roles: A, staff Qlee with `quick_login.create` + `teacher.view` only.
1. A `POST /people/teachers/<qa-teacher>/quick-login/` -> 200, `me.impersonator` set; the session is now the teacher.
2. As impersonated teacher: `GET /payroll/payslips/` 200 (reading allowed); `POST /identity/me/password/ {"old_password":"...","new_password":"Zz-12345678!"}` -> 403 `identity.impersonating`; any wallet/chat POST -> 403 `identity.impersonating`; `POST /people/teachers/<id>/quick-login/` again -> 403 (teacher has no code).
3. `POST /identity/impersonation/stop/` -> back to admin; `me.role=admin`. `security-log` shows IMPERSONATE and RETURN events (`select kind,actor_id,target_id from identity_securityevent order by id desc limit 2`).
4. A `POST /people/admins/<id>/quick-login/` -> 404/400 (never admins); staff `nocode` -> 403; Qlee on a teacher -> 200, on a student (no `student.view`) -> 403; parent target while `parents` off -> 404; deactivated target -> 400 `identity.quick_login_refused`.
5. Impersonating then calling quick-login again (as the teacher or after switching actor) -> `ALREADY` path; impersonator deactivated mid-session (`PATCH /access/staff/<Qlee> {"is_active":false}` from A while Qlee impersonates) -> next request is signed out (S-9a re-check). Session older than 3600s: set `since` back in `django_session` via shell and expect sign-out.
Cites `identity/tests/test_impersonation*.py`. Provider REAL. Cleanup: stop impersonation, deactivate Qlee.

### Academy settings

**F03-TC-015 (P1) Owner configures the academy end to end, and it persists.**
Role: A. Baseline S6 (qa = Africa/Cairo, EGP, `ar`).
1. `PATCH /academy/settings/` `{"timezone":"Asia/Riyadh","default_currency":"sar","default_language":"en","generation_horizon_days":21,"renewal_grace_days":3,"invoice_due_days":10,"absent_consumes_session":true,"excused_consumes_session":false,"auto_invoice_on_subscription":true,"postpone_limit_minutes":90}` -> 200, `default_currency="SAR"` (upper-cased), `postpone_limit_minutes=90` (postponement on).
2. `GET` returns the same; second jar (teacher) `GET` shows same currency/timezone; DB row identical, `updated_at` advanced.
3. `GET /system-status/` `timezone="Asia/Riyadh"` and `academy_now` offset `+03:00`.
4. New user created after change (`POST /access/staff/`) gets `preferred_language` = ? (record: `default_language` is documented as the language new accounts get; assert it).
5. Restart check: `$DC restart django` is not needed; just `GET` after 60s (no cache). Revert to baseline.
Assertions: `academy_qa.academy_academysettings` single row (count=1), `public.tenants_academy.timezone/currency` (record whether they changed: they should not per docs, but admin pages read them: see S3). Cleanup: restore baseline.

**F03-TC-016 (P1) Currency change and money correctness (integer minor units).**
Role: A. Fixture: invoice from S3, `amount_minor=150000` EGP.
1. `PATCH /academy/settings/ {"default_currency":"USD"}` -> 200.
2. `GET /billing/invoices/<id>/` still `currency="EGP"`, `total_minor=150000` (no re-denomination); DB `billing_invoice.currency='EGP'`.
3. New invoice without explicit currency (if the API allows) or a new payment link / wallet / rate default now uses `USD`; mixed-currency academy: `GET /billing/summary/` does not add EGP and USD minor units into one number (check how totals are grouped; record the exact output).
4. `POST /billing/invoices/` with `"amount_minor":1500.5` or `"150000.00"` -> 400 (integers only); negative -> 400.
5. Invalid currency changes: `"US"`, `"USDD"`, `"U$D"`, `"123"`, `""`, `null`, `" usd "` (trimmed + upper-cased -> ok?) -> 400 except the last; **`"ZZZ"` and `"XXX"` are accepted today (regex only)**; record as S2.
Assertions: DB `billing_invoice.total_minor`, `currency` unchanged; `academy_academysettings.default_currency`. Cleanup: restore EGP.

**F03-TC-017 (P1) Settings validation boundaries and types.**
Role: A. Each case one PATCH, expect status and unchanged DB on 400:
- horizon 0, 61, -1, `"abc"`, `14.5`, `"14"` [0/61/-1/abc/14.5 -> 400; `"14"` -> accepted as int: record]; grace -1, 61 -> 400, 0 and 60 -> 200; due days 91 -> 400, 0 and 90 -> 200; postpone 10081 -> 400, 10080 and 0 -> 200.
- bool fields: `"yes"`, `1`, `"false"`, `null`, `[]` (record DRF coercion; `{"absent_consumes_session":"maybe"}` -> 400).
- timezone: `"Mars/Phobos"`, `""`, `"cairo"`, 65-char string -> 400; `"UTC"`, `"Africa/Cairo"`, `"Etc/GMT+14"` -> 200.
- language: `"es"`, `"fr"`, `"AR"` -> 400; `"ar"`,`"en"` -> 200.
- unknown field `{"foo":1}` and read-only `updated_at`, `supervision_enabled` -> 200 ignored.
- empty body `{}` -> 200 no change; non-JSON body -> 400/415.
- postponement off: `{"postpone_limit_minutes":60}` -> 400 and the key absent from GET.
Cites `academy/tests/test_api.py` (bounds, tz, booleans); live P1 re-run only for the money/time keys (timezone, currency) and the postponement gate. Cleanup: restore.

**F03-TC-018 (P2) Settings robustness: self-heal and concurrent edits.**
1. Disjoint concurrent PATCHes: `(horizon=30)` and `(grace=5)` fired in parallel (two jars, `&`) -> both persisted (partial updates; verify no lost update since the service saves the whole row: a read-modify-write on the same row may overwrite one field. Record the outcome over 20 attempts: S5).
2. Delete the singleton row in a throwaway state? Not on `qa`: run in `qa-tmp-1` only: `delete from academy_qa_tmp_1.academy_academysettings` then `GET /academy/settings/` -> 200 and row recreated from `public.tenants_academy` timezone/currency.
3. A second `AcademySettings` row inserted by SQL (duplicate singleton) -> record which row `.first()` serves (no uniqueness guard).
Assertions: DB counts. Cleanup: remove duplicate row. Priority P2 (race is real but rare).

### Language, themes, quick translate, system status

**F03-TC-019 (P1) Quick translate: owner rewords a label, and it reaches the sign-in page.**
Role: A. Switches: `quick_translate`.
1. `PUT /translations/en/nav.students/` `{"value":"Learners"}` (pick a key present in `dashboard/src/locales/en/*.json`) -> 201; again with `{"value":"Pupils"}` -> 200; DB `translations_translationoverride` one row (language,key unique), `updated_by` = admin.
2. Anonymous (no jar) `GET /translations/` -> 200 `{"en":{"nav.students":"Pupils"}}` with `Cache-Control: max-age=60`.
3. `DELETE /translations/en/nav.students/` -> 204; delete again -> 204; GET no longer has it.
4. Switch `quick_translate` off: GET -> `{}` (anonymous), PUT -> 404 for A, 403 for nocode; rows remain in DB; switch on: values return.
5. Spanish override `PUT /translations/es/...` accepted even while `spanish` off (L-10); record.
6. Isolation: set in qa, read from qaother host -> absent. Hit anonymous GET 130 times in a minute -> 429 after 120 (throttle scope `translations`).
Cleanup: delete all F03 overrides. Cites `translations/tests`; live isolation and throttling new.

**F03-TC-020 (P1) Quick translate input safety.**
Role: A. `PUT /translations/en/<key>/` with values: `"<b>x</b>"`, `"a>b"`, `"$t(nav.students)"`, `"{{- name}}"`, `"{{a b}}"`, `"{{name}}"` (ok), `"Hello {{ name }}"` (ok), `"{{name"` (record), `"   "` (400), 501 chars (400), 500 chars (200), emoji/Arabic text (200 and round-trips). Keys: `"__proto__.x"`, `"a.constructor"`, `"a.prototype.b"`, `"nokey"`, `"a..b"`, 201-char key, `"a.b-c"`, `"1a.b"` -> 400 except valid ones. Language `fr` -> 400.
Permissions: staff without `page.quick_translate` 403; teacher 403; anonymous 401/403; NotImpersonating not applied (record whether admin-as-teacher is blocked: n/a).
Cap: 2000 rows: insert 2000 via `manage.py tenant_command shell --schema=academy_qa` loop, then PUT new key -> 400 `translations.limit`, update existing key -> 200. Cleanup: delete rows. Cites `translations/tests`.

**F03-TC-021 (P1) System status page and manual run.**
Role: A and staff with `page.system_status`. Switches: `system_status`.
1. `GET /system-status/` -> `version`, `subdomain="qa"`, `timezone`, `academy_now`, `server_now`, `features_on` equals `len(me.features)`, `jobs` list of 2, `runs` list.
2. `POST /system-status/runs/ {"job":"reconcile_subscriptions"}` -> 202 status `queued`; second POST immediately -> 409 `systemstatus.run_open`; poll GET until `ok` (celery worker up), `result` JSON set, `finished_at` set. `{"job":"notifications"}` and `{}` and `{"job":"rm -rf"}` -> 400.
3. DB: `select job,status,requested_by_id from systemstatus_jobrun order by id desc limit 3`; with no open run the partial unique index allows a new run.
4. Stale run: `update systemstatus_jobrun set status='running', requested_at=now()-interval '2 hours'` then POST -> old one `failed "Timed out."`, new one 202.
5. Permissions: nocode staff 403, teacher/student 403, anonymous 401/403. `system_status` off: A 404, nocode 403.
6. Suspended-academy run fails: use `qa-tmp-1` (suspended): optional, `run_job` fails with error (FAKE direct task call).
Cites `systemstatus/tests`, `b9-platform.spec.ts` (UI run). Cleanup: set stuck runs to failed.

**F03-TC-022 (P2) Themes and Spanish gating.**
Switches: `themes`, `spanish`. API-first parts: set `preferred_language` of the QA student to `es` (`PATCH /identity/me/ {"preferred_language":"es"}` as student) with `spanish` on -> 200; `spanish` off -> `me.effective_language="en"`, `preferred_language` still `es` (DB `identity_user.preferred_language='es'`); with `spanish` off, setting `es` -> 400; sending back the stored `es` unchanged while off -> kept. Academy `default_language:"es"` -> 400. Theme: no backend; UI check in TC-027. Cites `identity` tests for `effective_language`. Cleanup: restore language.

### Dashboard smoke (Playwright, `--workers=1`)

**F03-TC-023 (P1, UI smoke 1/3) Owner creates a role and hires staff in the dashboard; staff sees a narrowed app.**
Role: A, then staff. Tool: Playwright on `http://qa.etqan.localhost/app/`.
1. Admin: Settings -> Roles -> New: tick student view + invoice view; save; People -> Staff -> New: name/email/role; save.
2. Accept invite from mailpit, sign in as the staff. Sidebar shows only People/Billing entries permitted; `/app/settings/roles` shows `NoAccess`; `/app/billing/invoices` lists rows, no "New invoice" button.
3. Admin retires the role in the UI; staff reload -> `NoAccess` on invoices.
4. axe-core check on the roles editor (record only).
Assertions: UI + the API/DB checks of TC-001/003. Evidence: trace, screenshot. Cleanup: retire role, deactivate staff.

**F03-TC-024 (P1, UI smoke 2/3) Settings form saves and survives reload; features page is read-only; FeatureOff screen.**
Role: A. 1. `/app/settings/academy`: change currency to `EUR` and grace days to 5, save, reload: values persist; DB row matches; invalid timezone input is blocked client side or shows the server field error. 2. `/app/settings/features`: lists switches, no toggle controls (count `input[type=checkbox]` / switches = 0). 3. With `quick_translate` off (`set_features qa --off quick_translate`), open `/app/settings/quick-translate` -> `FeatureOff` screen (not 404 page, not blank); nav item hidden. Turn back on -> page loads. Assertions: DB, `me.features`. Cleanup: restore currency EGP and switches.

**F03-TC-025 (P2, UI smoke 3/3) Language and theme per browser.**
Role: A. Switch `themes` on: pick `nord` on `/app/account`, reload -> persists in `localStorage["etqan-palette"]`; academy brand colour unchanged; switch `themes` off -> default palette is used and the stored value is kept; set `ar` -> `dir=rtl`; with `spanish` on the picker offers Spanish, off -> hidden. Quick translate override of one label appears after save without reload. Cites `b9-platform.spec.ts` theme test, `b9-languages.spec.ts`; run only if time allows.

### Gap and abuse cases

**F03-TC-026 (P1) Impersonation or staff cannot reach admin-only and settings endpoints; feature switches cannot be forged.**
Staff with the biggest possible role (every registry code, built by A via `GET /access/registry/`): `GET /people/admins/`, `GET /identity/security-log/`, `GET /identity/google/settings/`, `GET /academy/features/` -> all 403 (admin-only by absence of codes). `PATCH /academy/settings/` -> 200 (holds `academy_settings.update`). Impersonated sessions (TC-014) cannot PATCH settings either: A impersonating a teacher gets 403 as the teacher. Header/param forgery: send `X-Forwarded-Host: qaother.etqan.localhost`, `?academy=qaother`, `?schema=academy_qaother` on `GET /academy/settings/` and `GET /access/roles/` -> still qa data. Mass assignment on staff create: `{"role":"admin","is_superuser":true,"is_staff":true}` ignored or 400; DB `identity_user.role='staff'`, `is_superuser=false`. Cleanup: retire role, deactivate user.

**F03-TC-027 (P1) Staff-created role chain cannot reach admin powers.**
Staff Ed (TC-004) with `staff.create` creates staff `Eve` with a role Ed holds; Eve's codes <= Ed's codes; Ed cannot make a staff `role`=admin through any field; Ed cannot reset the password or email of the **admin** (`PATCH /access/staff/<admin_id>/` -> 404 since admins are not staff rows; `POST /people/admins/<id>/password-reset/` -> 403); Ed `GET /identity/me/` after Eve is created shows unchanged `permissions`. Also: Ed with `staff.update` changes **Eve's** email (Eve outranked: codes subset) -> 200 then Eve's password reset invite goes to the new address (mailpit) -> account takeover of a weaker account is allowed by design; record as expected. Cleanup: deactivate Ed, Eve.

## 4. Suspected defects from code reading (for Agent 2)

- **S1 (P1) A staff role editor can retire a role they do not hold.** `access/services.py:update_role` guards only restore (`fields.get("is_active") and not role.is_active`), not retire. Staff with `role.update` can set `is_active=false` on a stronger role (e.g. Money or any admin-built role), instantly stripping its members, and cannot be undone by them. Also renaming stronger roles is unguarded. TC-005.
- **S2 (P2) Currency accepts non-ISO codes.** `platform/validators.py:clean_currency` is `^[A-Z]{3}$`, so `ZZZ`, `XXX`, `AAA` become the academy currency. Downstream formatting/minor-unit exponent for such codes is unknown. TC-016.
- **S3 (P2) Public `Academy.timezone/currency` go stale after a settings PATCH.** `update_settings` writes only `AcademySettings`; `tenants_academy` keeps the creation values, which the Etqan admin console and any code reading `connection.tenant.timezone` see. TC-015 (record, may be by design).
- **S4 (P2) Retiring/deactivating a supervisor leaves sessions pointing at them.** `get_supervisor` only checks at assignment/renew time; existing `supervisor_id` rows stay and the supervision list/permission for the former supervisor behaviour is unspecified. TC-007 step 5.
- **S5 (P2) Settings is a whole-row read-modify-write on a "singleton by convention" table.** `update_settings` loads the row, sets fields and `save()`s everything; two concurrent partial PATCHes can overwrite each other's field. No uniqueness constraint on the singleton. TC-018.
- **S6 (P1) Currency switch with existing money rows.** No guard or warning when `default_currency` changes while invoices, rates, wallets and playlists exist in the old currency; defaults in `payroll/finance/wallet/gateways/consultations/recorded` start using the new one, so a mixed-currency academy can show summed minor units of different currencies (e.g. `billing/summary/`). TC-016.
- **S7 (P2) Feature-off status mismatch with the brief.** Brief says 403; code and docs say 404 (`FeatureOn` raises `NotFound`). If the product owner intended 403 this is a spec-versus-code conflict, otherwise only the brief is wrong. TC-012.
- **S8 (P3) Quick translate `{{name` (unclosed placeholder) passes `_check_value`.** `PLACEHOLDER_RE` only validates complete `{{...}}` groups; i18next behaviour for a lone `{{` is untested. Spanish overrides are accepted while `spanish` is off. TC-019/020.
- **S9 (P2) Impersonation actions without `NotImpersonating`.** `payroll` `IssueView`/`MarkPaidView` (HasCode only) and `billing` Void/Refund rely on the impersonated user never holding a code (teachers/students/parents have none), so they are safe today, but a future staff-targeted quick login would bypass it. Check `identity/api/views.py:576` too. TC-014 (verify current behaviour is safe).
- **S10 (P3) Boolean settings coerce strings.** DRF `BooleanField` accepts `"yes"`, `"on"`, `1`, so `{"absent_consumes_session":"yes"}` flips a money-affecting switch; `null` handling differs between serializer and `update_settings` (`None` = ignore). TC-017.

## 5. Out of scope here (see coverage-gaps.md)
Etqan staff editing switches in the Django admin (F01/F02), per-feature `FeatureOn` coverage of all 88 switches (each feature spec), Google/2FA/login flows (F02), email/WhatsApp delivery of quick-login links (BLOCKED live), dashboard `PermissionGate` for every route.

## 6. Results (Agent 2, execution run 1, 2026-10-19)

Executed API + DB first (curl jars with CSRF, psql `academy_qa` / `academy_qaother`, Mailpit API), UI smoke in
`dashboard/e2e/qa/f03-roles-settings.spec.ts` (pw-run3: 2/2 passed). Evidence paths are relative to `qa/evidence/F03/`.
Fixtures: `fixtures.txt` (course 1, package 1, subscriptions 1 (student 5 / teacher 7 / supervisor 4) and 2 (student 8 / teacher 16), sessions 1-8, auto invoices 1-2 at 150000 EGP).

| Case | Result | Tag | Evidence | Notes |
|---|---|---|---|---|
| TC-001 | PASS | REAL | tc001a.txt, tc001b-002.txt | Role 6 sorted codes, invite mail, Hana `me` = 4 codes; students/invoices 200, POST invoice/payroll rates/roles 403; member row 1, `members` 1 |
| TC-002 | PASS | REAL | tc001b-002.txt | All 4xx leave the row count at 6; trim + dedupe + greyed `student.delete` stored. **Spec correction:** PATCH with `members`/`id` is 200 with the field ignored (serializer drops unknown keys; standard DRF), not 400 |
| TC-003 | PASS | REAL | tc003-005.txt | Retire, restore and code change bite on the live session without re-login; retired role refused on staff create (400); member row kept |
| TC-004 | PASS | REAL | tc003-005.txt | Every guard 403 with its field message; Money codes unchanged after each 403; keep+add held code 200 |
| TC-005 | **FAIL** | REAL | tc003-005.txt | S1 CONFIRMED: Ed retires Money (200), Mo loses access, Ed can't restore; rename also unguarded. **ETQAN-QA-021 (P2)** |
| TC-006 | PASS | REAL | tc006-007.txt | Missing/duplicate (case-insensitive) email, bad ids, string ids 400; search; admin never listed; deactivated session 403, login 400, roles kept, reactivate OK. Cross-academy role id not testable (ids are per schema, qaother has only id 1) |
| TC-007 | PASS | REAL | tc006-007.txt | Supervisor preset = 20 codes, no money/settings codes; list follows retire/restore/deactivate; supervision off: admin 404, nocode 403. S4 observed: session/subscription keep `supervisor_id` after retire, the retired supervisor gets 403 on `/supervision/`, new assignment 400. Matches "a retired role keeps its assignments but grants nothing"; not filed |
| TC-008 | PASS | REAL | tc008-010.txt | Matrix exactly as specified; anonymous is **403** (not 401). Staff with `academy_settings.update` only: PATCH 200, features 403 |
| TC-009 | PASS | REAL | tc008-010.txt | Cross-app matrix as specified (teacher 403 on invoices, partial 403 on writes, payments need `payment.view_any`) |
| TC-010 | PASS | REAL | tc008-010.txt | Student/teacher/parent see own rows only, others' detail is 404; guardian unlink removes parent access at once. Payslip row scope not exercised (no payslips exist yet; F10) |
| TC-011 | PASS | REAL | tc011.txt | qaother can't list/GET/PATCH qa role (404); qa cookie on qaother host 403 (also Host header replay); qa staff can't sign in on qaother; currency isolated; same email allowed in both academies independently |
| TC-012 | PASS | REAL | tc012-013.txt | Off: A/student/partial 404 "This feature is not enabled...", nocode/teacher 403; prerequisite chain in `me.features` and `held_by`; rows survive. S7: 404 is per code and docs; only the brief said 403 (spec already records it) |
| TC-013 | PASS | REAL | tc012-013.txt | 88 entries = registry; all writes 405; settings `features`/`supervision_enabled` ignored, public features unchanged; next GET reflects `set_features` |
| TC-014 | PASS | REAL | tc014.txt | Impersonate, sensitive actions 403 `identity.impersonating`, stop, IMPERSONATE/RETURN events 47/48, admin target 404, staff without `student.view` 403, parents off 404, inactive target 400, impersonator deactivated → signed out, session aged >3600s → signed out (row deleted). `PATCH /me/ full_name` allowed while impersonating: not on the S-9a sensitive list, by design. S9 REFUTED for today (targets never hold codes; void as impersonated teacher 403) |
| TC-015 | PASS | REAL | tc015-016.txt | All fields persist, SAR upper-cased, single row, teacher reads same, system status `+03:00`, new account gets `preferred_language=en` and English invite. S3: `tenants_academy` keeps Africa/Cairo/EGP; by design (`academy-settings.md`: public values only seed the row); not filed |
| TC-016 | **FAIL** | REAL | tc015-016.txt | Currency switch never re-denominates (invoice 1 stays 150000 EGP); new invoice uses USD; floats/negatives/0 400 (`"150000.00"` → exact 150000, DRF integer parsing). S6 REFUTED: summary groups per currency (revenue EGP 50000 / USD 2500; overdue EGP 150000 / USD 150000 / ZZZ 100). S2 CONFIRMED: `ZZZ`, `XXX` accepted. **ETQAN-QA-022 (P3)** |
| TC-017 | PASS | REAL | tc017.txt | Every bound and type as specified, DB unchanged on 400; postponement gate works. **Spec correction:** `Etc/GMT+14` doesn't exist (400 is right; `Etc/GMT-14` is the valid one). S10: `"yes"`/`"on"`/`1`/`"false"` coerce (standard DRF BooleanField), `null` 400; not filed |
| TC-018 | **FAIL** | REAL | tc018.txt | S5 CONFIRMED: 20/20 lost updates. **ETQAN-QA-023 (P3)**. Self-heal on `qa-tmp-1` recreates the row from public values. Step 3 (duplicate singleton) not run (lean) |
| TC-019 | PASS | REAL | tc019-020.txt | 201 then 200, one row with `updated_by`, anonymous `max-age=60`, delete idempotent 204, switch off `{}`/404/403 with rows kept, `es` accepted (L-10), qaother `{}`, throttle 429 after 120/min |
| TC-020 | PASS | REAL | tc019-020.txt | All unsafe values/keys/language refused; 500 vs 501 boundary; Arabic/emoji round-trip; cap 2000 → `translations.limit`, update at cap 200. S8: `{{name` / `name}}` accepted; rendered as literal text, not a placeholder; not filed |
| TC-021 | PASS | REAL | tc021-022.txt | Status fields, `features_on` = `len(me.features)`; with the worker stopped: second run 409 `systemstatus.run_open`, stale run → `failed "Timed out."` and new run 202; worker restarted, run `ok`. (With the worker up, a run finishes in <80 ms, so an immediate second POST is 202: not a defect) |
| TC-022 | PASS | REAL | tc021-022.txt | `es` with spanish on, effective `en` when off with stored `es` kept, new `es` 400 while off, academy `default_language:"es"` 400 (ar/en only) |
| TC-023 | PASS | REAL | pw-run3.txt, pw/tc023.json, pw/*.png | UI: role built in the editor, staff invited, invite accepted, narrowed nav, NoAccess on roles, retire → NoAccess + API 403 |
| TC-024 | PASS | REAL | pw-run3.txt, pw/tc024.json, pw/*.png | UI: grace 5 + EUR survive reload (API matches), features page has no toggles, quick translate off → FeatureOff and nav item hidden; baseline restored |
| TC-025 | NOT RUN | — | — | P2, "only if time allows"; deferred (lean). Recorded as a coverage gap |
| TC-026 | PASS | REAL | tc026-027.txt, tc011.txt | Staff with all 881 codes: admins/security-log/google settings/features 403, settings PATCH 200, admin quick-login 404, admin edit 403/404; header/param forgery still serves qa; mass-assignment ignored (`role=staff`, not superuser) |
| TC-027 | PASS | REAL | tc026-027.txt | Ed creates Eve with a held role only; `role:"admin"` ignored; admin edit 404/403; Ed changes weaker Eve's email (by design), not stronger Max's (403) |
| TC-028 (A2, P1) | PASS | REAL | tc015-016.txt | Added by Agent 2: money totals stay per currency in a mixed-currency academy after a currency switch (exact minor units checked against `billing_payment` / `billing_invoice`) |

Totals: 27 executed (26 spec + TC-028), 24 PASS, 3 FAIL, 0 BLOCKED, 1 NOT RUN (TC-025).
Open: ETQAN-QA-021 (P2), ETQAN-QA-022 (P3), ETQAN-QA-023 (P3).
Cleanup (`cleanup.txt`): F03 staff deactivated, F03 roles retired, role 3 codes restored, settings back to the S6 baseline (qa and qaother),
test invoices 4-6 voided, guardian link removed (baseline had none), translations empty, no open job runs, qaother staff "F03 Hana Other" deactivated.
Switches left in the S1 state.

## 7. Retest 1 + gate (Agent 2, 2026-10-19)
| Item | Result | Tag | Evidence |
|---|---|---|---|
| TC-005 (QA-021 repro) | PASS: Ed retire Money 403 `is_active`, DB unchanged, Mo keeps access; rename 200 (PROPOSAL-accepted) | REAL | retest-1/qa021-retest.txt |
| Related guard checks (14) | PASS, except step 13: Ed retires his own only role 200 → ETQAN-QA-024 (P3) | REAL | retest-1/qa021-retest.txt |
| Regression + access pytest | 38 passed; access 2054 passed / 1 owner-WIP failure | FAKE (test DB) | retest-1/pytest-*.txt |
| TC-023/024 UI smoke | 2/2 | REAL | retest-1/playwright.txt |
Gate: PASSED (see execution-progress.md § F03 gate decision).

