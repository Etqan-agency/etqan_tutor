# F05: People (staff, teachers, students, parents, families, tags, contracts)

Author: Agent 1 (research and test strategy, LEAN mode). Approves nothing. Written 2026-10-18 from the
code state in `environment.md` (backend adff9c9, dashboard 5ed775d).

Sources read: `docs/features/people.md`, `docs/features/employment.md`; `backend/etqan/identity/{models,services,scopes,authentication,signin}.py`,
`identity/api/{people_urls,people_views,people_serializers,people_filters,payloads,views}.py`,
`access/{services,presets,registry}.py` (staff accounts), `employment/{models,services}.py` + `employment/api/*`,
`platform/{permissions,csv,uploads,pagination,validators}.py`.
Existing tests (cited as "Covered by"): `identity/tests/test_people_api.py`, `test_people_actions_api.py`, `test_families_api.py`,
`test_family_bulk.py`, `test_family_people.py`, `test_staff_scope.py`, `test_tags_api.py`, `test_profile_access.py`,
`employment/tests/test_api.py`; e2e `dashboard/e2e/people-catalogue.spec.ts`, `families.spec.ts`.

## Conventions
- `H` = helpers in `$S/qa.sh` (`S=/private/tmp/claude-501/-Users-khaledsakr-Documents-Etqan-tutor/55afddca-abb7-4698-b08b-38df7f0acb0e/scratchpad`):
  `login <sub> <jar> <email> <pw>`, `req <sub> <jar> <METHOD> <path> [json]` (prints body + `HTTP code`), `accept <email> <pw>`
  (follows the Mailpit invite link), `mails <email>`, `Q "<sql>"` (psql, use `academy_qa.` / `academy_qaother.` schema prefix).
  Path is relative to `/api/v1/`. Jars: `adm` (qa-admin), `nocode` (qa-staff-nocode), `codes` (qa-staff-codes), `sup` (qa-supervisor),
  `tch` (qa-teacher), `stu` (qa-student), `par` (qa-parent), `oth` (qaother-admin on sub `qaother`). Anonymous = no jar / `anon`.
- Person body: `{"user":{"full_name","email","phone","preferred_language","timezone"},"profile":{...}}`. List envelope:
  `{count,next,previous,results:[{id,role,two_factor,user:{...,account_state,is_active},profile}]}`; page size 25, `page_size` max 100.
  Errors are nested (`{"user":{"email":["..."]}}`, `{"profile":{...}}`, `non_field_errors`).
- Emails always `@qa.etqan.test`; Mailpit is REAL SMTP to a local sink. Provider tag is REAL unless stated; nothing here needs
  an outside provider except where marked.
- DB tables (schema `academy_qa`): `identity_user`, `identity_studentprofile`, `identity_teacherprofile`, `identity_parentprofile`,
  `identity_guardianship`, `identity_family`, `identity_tag`, `identity_studentprofile_tags`, `identity_teacherprofile_tags`,
  `account_emailaddress`, `django_session`, `employment_contract`, `access_staffrole` (+ its user join table).
- Naming: test data uses prefix `QA5 ` / emails `f05-*@qa.etqan.test` so cleanup is one SQL/API sweep (people are never deleted via API;
  cleanup = deactivate, or leave: qa is a throwaway academy).

## Setup (once, academy `qa`)
```
S=/private/tmp/claude-501/-Users-khaledsakr-Documents-Etqan-tutor/55afddca-abb7-4698-b08b-38df7f0acb0e/scratchpad
$S/dc.sh exec -T django python manage.py set_features qa --on families parents contracts quick_login export
# (spanish and phone_login stay as they are; TC-024 turns spanish on and back off)
source $S/qa.sh
login qa adm qa-admin@qa.etqan.test 'QA-Admin-2026!'; login qa nocode qa-staff-nocode@qa.etqan.test 'QA-People-2026!'
login qa codes qa-staff-codes@qa.etqan.test 'QA-People-2026!'; login qa sup qa-supervisor@qa.etqan.test 'QA-People-2026!'
login qa tch qa-teacher@qa.etqan.test 'QA-People-2026!'; login qa stu qa-student@qa.etqan.test 'QA-People-2026!'
login qa par qa-parent@qa.etqan.test 'QA-People-2026!'; login qaother oth qaother-admin@qa.etqan.test 'QA-Other-2026!'
# 60 students for pagination/bulk (email-less, no invites): names QA5 Bulk 001..060, mixed status/country/DOB
for i in $(seq -w 1 60); do req qa adm POST people/students/ "{\"user\":{\"full_name\":\"QA5 Bulk $i\",\"phone\":\"+2010000${i}00\"},\"profile\":{\"status\":\"$([ $((10#$i % 5)) -eq 0 ] && echo trial || echo active)\",\"country\":\"EG\",\"date_of_birth\":\"$((2005 + 10#$i % 12))-06-15\"}}" | tail -1; done
# Roles for TC-014 (ids returned): staff role "QA5 Student Edit" = student.view,student.view_any,student.create,student.update
req qa adm POST access/roles/ '{"name_ar":"QA5 تحرير","name_en":"QA5 Student Edit","permissions":["student.view","student.view_any","student.create","student.update"]}'
# a second academy fixture exists already: qaother admin. Create one student there: 
req qaother oth POST people/students/ '{"user":{"full_name":"QA5 Other Student","email":"f05-other-stu@qa.etqan.test"},"profile":{}}'
```
Prerequisite state to record before the run: `Q "select role,count(*) from academy_qa.identity_user group by 1"` and the same for `academy_qaother`
(TC-016 compares against it). Mailpit reachable at `localhost:8025`. Check pytest of the F05 apps is not running at the same time.

## What the code does (short)
- `people/<kind>/` (kind = students|parents|teachers|admins): list needs `<role>.view_any`, create `<role>.create`, detail `.view`, edit `.update`;
  `admins` declares no code so only role `admin` passes. `scope_for` returns all rows for admin/staff and `none()` for anyone else.
  Parents routes are behind the `parents` switch; families behind `families`; contracts behind `contracts`.
- `create_person` validates everything first, creates the user, the profile, an unverified primary `EmailAddress`, and queues the invite after commit.
  Duplicate check is `iexact` on both `identity_user.email` and `account_emailaddress.email` (DB: unique `lower(email)`).
- Edit email: never signed in (no usable password) = replace + re-invite; otherwise `pending_email` + confirmation, promoted on confirmation.
- Deactivate: not self, not the last active admin (row lock); ends all sessions in one table scan; bulk deactivate for students.
- Family: needs >= 1 student, none in another family, payer = one of the students or one of their parents (active); `payer_needs_choosing` is derived.
- Money: the only money-like field here is `TeacherProfile.pay_currency` (3 letters, default = academy `default_currency`, here EGP) plus `payout_*`.
  There are no amounts in this feature; money correctness = currency default/validation/immutability across edits and in CSV.

---
## Test cases

### A. Owner workflows

#### F05-TC-001: Owner adds a student with an email; the student accepts the invite and signs in
- **Role:** admin, then the student. **Switches:** defaults. **Priority:** P1. **Provider:** REAL (Mailpit SMTP).
- **Data:** `f05-stu1@qa.etqan.test`, tag id of a student preset (`GET people/tags/?kind=student`).
- **Steps:** (1) `req qa adm POST people/students/ '{"user":{"full_name":"QA5 Sami","email":"f05-stu1@qa.etqan.test","phone":"+201005550101","preferred_language":"ar"},"profile":{"gender":"male","country":"eg","date_of_birth":"2012-03-01","status":"trial","notes":"private note","nationality":"arab","tag_ids":[<tag>]}}'`.
  (2) `GET people/students/<id>/`. (3) `mails f05-stu1@qa.etqan.test`. (4) `accept f05-stu1@qa.etqan.test 'QA-Stu1-2026!'`. (5) `login qa s1 ...`. (6) `GET identity/me/` as the student.
- **Expected:** (1) 201, `user.account_state=invited`, `country="EG"` (upper-cased), `age_group` teen/child per academy date, tag chip present. (3) exactly 1 invite mail whose link host is `qa.etqan.localhost` and path `/app/reset-password`. (4) 200. (5) 200. (6) `profile` has no `notes`/`nationality`; `timezone`/`preferred_language` defaulted from the academy where not sent (here `ar` as sent, tz `Africa/Cairo`).
- **Assert (DB):** `identity_user` role=student, `is_active`, `password` usable only after step 4; `account_emailaddress` primary, `verified` false then true; `identity_studentprofile` row 1:1, tags join row; `django_session` gains a row after login.
- **Covered by:** `test_people_api::test_create_student_with_email_sends_invite`, e2e `people-catalogue.spec.ts` (UI). Kept P1 for the end-to-end chain incl. DB verification flag.
- **Cleanup:** none (leave; deactivated in TC-011).

#### F05-TC-002: Email-less student, then adding an email later
- **Role:** admin. **Priority:** P1. **Provider:** REAL.
- **Steps:** (1) create `QA5 NoMail` with no `email` (twice, two different names). (2) `POST people/students/<id>/invite/`; `POST .../password-reset/`. (3) `PATCH people/students/<id>/ {"user":{"email":"f05-nomail@qa.etqan.test"}}`. (4) `PATCH` again with `{"user":{"email":""}}` and with `{"user":{"email":"other@qa.etqan.test"}}`.
- **Expected:** (1) both 201, `account_state=no_login`, no mail. (2) both 400 (invite: "only someone who has not set a password"; reset: "Add an email address first"). (3) 200, state `invited`, 1 invite mail. (4) `""` -> 400 "cannot be removed" is expected only when an email already exists; second PATCH of a different address while still never-signed-in replaces and re-invites (old link dead: use old token on `identity/password/reset/confirm/` -> 400).
- **Assert (DB):** two rows with `email IS NULL` (not `''`) in `identity_user`; after step 3 exactly one `account_emailaddress` row; after the replace the old address is gone from both tables.
- **Covered by:** `test_people_api::test_create_student_without_email`, `test_people_services` (partly). P1 for the NULL-not-empty-string uniqueness and dead-link assertion.

#### F05-TC-003: Teacher onboarding: profile, courses, payout, currency default
- **Role:** admin. **Priority:** P1. **Provider:** REAL.
- **Steps:** (1) `POST people/teachers/` without `gender` -> 400 on `profile.gender`. (2) with `gender:"female"`, `pay_currency` omitted, `payout_method:"vodafone_cash"`, no `payout_details` -> 400 (`profile.payout_details`). (3) full: `payout_details:"+201005550202"`, `pay_currency:"usd"`, `tag_ids:[teacher tag]`, `course_ids:[]`. (4) `PATCH` clearing `payout_method:""` then `pay_currency` omitted. (5) create another teacher with `pay_currency` omitted.
- **Expected:** (1)(2) 400 and nothing created (count unchanged). (3) 201, `pay_currency="USD"` (upper-cased), invite mailed. (5) `pay_currency="EGP"` (academy default). (4) currency unchanged by an unrelated PATCH.
- **Assert (DB):** `identity_teacherprofile.pay_currency` is `USD`/`EGP`, 3 chars; failed attempts leave no `identity_user` row (atomic); invite count = 1 per successful create.
- **Covered by:** `test_people_api::test_teacher_needs_gender_and_links_courses`, `test_profile_depth`. P1 for currency (money) default and atomic rollback.

#### F05-TC-004: Parent with two children (siblings), guardian links, `parents` switch
- **Role:** admin. **Switches:** `parents` on, then off, then on. **Priority:** P1. **Provider:** REAL.
- **Steps:** (1) create parent `f05-par1@` (`profile:{"has_whatsapp":true}`), two students (no email). (2) `POST people/students/<s1>/guardians/ {"parent_id":<p>}` and for `<s2>`; second parent `f05-par2@` linked to `<s1>` only. (3) `GET people/parents/<p>/children/`; `GET people/students/<s1>/guardians/`. (4) `DELETE people/students/<s1>/guardians/<p>/`; repeat the DELETE. (5) link a teacher id as parent (`parent_id=<teacher>`). (6) `set_features qa --off parents`; as admin `GET people/parents/` and `GET people/students/<s1>/guardians/`; parent `par1` accepts invite and logs in / has a live session. (7) switch on again.
- **Expected:** (2) 201 with guardians list in name order. (3) p has 2 children, s1 has 2 guardians. (4) 204 then 204 (idempotent). (5) 404 (not in the parent scope). (6) both 404; the parent's existing session is signed out on its next request (anonymous, 401/403) and a new login is refused with the "Parent access is not enabled" message; data intact. (7) parent can log in again and sees both children.
- **Assert (DB):** `identity_guardianship` unique (parent, student) pair, no duplicates after repeated POST; `identity_parentprofile` auto-created for a parent without one.
- **Covered by:** `test_people_actions_api::test_guardians_link_unlink_and_children`, `test_whatsapp_parents`, `test_features`. P1 for the switch-off live-session behaviour.

#### F05-TC-005: Family with a paying parent, edit, retire, filters
- **Role:** admin. **Switches:** `families`, `parents`. **Priority:** P1. **Provider:** REAL.
- **Steps:** (1) `GET people/families/payers/?students=<s1>,<s2>` -> choices (students first, then their parents). (2) `POST people/families/ {"name":"QA5 Family A","student_ids":[<s1>,<s2>],"payer_id":<par1>,"notes":"x"}`. (3) failures: payer = unrelated parent; payer = teacher; `student_ids:[]`; a student already in family A; name of 121 chars; name `"   "`. (4) `PATCH people/families/<f>/ {"payer_id":<s1>}`, then `{"student_ids":[<s1>]}`, then `{"is_active":false}`. (5) `GET people/students/?account_type=family`, `?account_type=individual`, `?family=<f>`; `GET people/families/?search=qa5&active=false`.
- **Expected:** (2) 201, `payer_needs_choosing=false`, students sorted by name. (3) each 400 on the named field (`payer_id`/`student_ids`/`name`), nothing written. (4) payer student ok; removing `s2` returns it to `account_type=individual`; retire keeps students attached. (5) filters return exactly those students; no duplicates.
- **Assert (DB):** `identity_studentprofile.family_id` set/cleared accordingly; `identity_family.payer_id` FK PROTECT (no delete route: `DELETE` -> 405).
- **Covered by:** `test_families_api`, `test_family_people`, e2e `families.spec.ts`. P1 (billing's payer comes from here).

#### F05-TC-006: Payer lifecycle: the payer is deactivated or loses the link
- **Role:** admin. **Priority:** P1. **Provider:** REAL (billing consumption itself is F-billing; here the identity side).
- **Steps:** family A (TC-005) with payer parent `par1` linked to s1. (1) `POST people/parents/<par1>/deactivate/`. (2) `GET people/families/<f>/`. (3) shell: `tenant_command shell --schema=academy_qa -c "from etqan.identity import services as s; print(s.family_payer(<s1>), [u.id for u in s.guardians_by_link(<s1>)])"`. (4) `POST .../activate/`. (5) `DELETE people/students/<s1>/guardians/<par1>/` then GET family. (6) `PATCH` family `payer_id=<s1>` to repair.
- **Expected:** (2) `payer_needs_choosing=true`, still lists the old payer. (3) `family_payer` None; `guardians_by_link` skips the inactive parent (falls to the next guardian par2 / none). (4) flag false again. (5) flag true (link gone). (6) false.
- **Assert (DB):** no row of `identity_family` changes in steps 1-5 (`updated_at` constant); flag is derived only.
- **Covered by:** `test_family_people` (units). P1 for the API-visible flag after deactivate; cross-check with F09 invoices later.

#### F05-TC-007: Bulk actions on 60 students
- **Role:** admin. **Priority:** P1. **Provider:** REAL.
- **Steps:** with the 60 Setup students: (1) `POST people/students/bulk/ {"ids":[...20],"action":"set_status","status":"paused"}`. (2) `add_tag` with a student tag; `remove_tag`; `add_tag` with a retired tag (retire one first via `PATCH people/tags/<t>/ {"is_active":false}`); `remove_tag` with the retired tag. (3) `deactivate` 10 students, one of which holds a live session; `activate` them. (4) `ids` of 501 -> ; `ids:[]`; ids mixing a teacher id, a qaother student id, a nonexistent id. (5) `create_family` with 3 ids where one is already in a family, then `add_to_family`/`remove_from_family`.
- **Expected:** (1) `{"updated":20}`. (2) add ok, remove ok, retired add 400 `tag_id`, retired remove ok. (3) updated 10, session of the deactivated student dead, rest alive. (4) 400 / 400 / `{"updated":<only real students of qa>}` with no error and no effect on the foreign ids. (5) `{"updated":2,"skipped":[{id,reason:"in_another_family"}]}`; remove returns count.
- **Assert (DB):** counts via SQL per status/tag/active exactly match `updated`; qaother students unchanged; `identity_studentprofile_tags` has no duplicates.
- **Covered by:** `test_people_actions_api::test_bulk*`, `test_family_bulk`. P1 for the 60-row volume and session kill.

#### F05-TC-008: Search, filter, pagination and CSV on 60+ students
- **Role:** admin. **Priority:** P1. **Provider:** REAL.
- **Steps:** (1) `GET people/students/` pages 1..3 and `?page=4`; record ids. (2) `?page_size=100`, `?page_size=101`, `?page_size=0`, `?page_size=abc`, `?page=0`, `?page=-1`, `?page=999`. (3) `?q=Bulk 05`, `?q=2010000`, `?q=QA5`, `?q=%` and `?q=_`; `?is_active=false`; `?status=trial`; `?country=eg` (lower); `?age_group=teen`; `?tag=<t1>&tag=<t2>` (ANY); `?tag=abc`; `?nationality=`; `?gender=`. (4) `?format=csv` with and without filters; a student named `=HYPERLINK("http://x")` and `+cmd` and `-5 days`.
- **Expected:** (1) page sizes 25/25/10+, `count` = true total, union of pages has no duplicate and no gap, stable name/id order. (2) `page_size` clamps to <=100; junk falls back to 25; out-of-range page 404, never 500. (3) counts match SQL; tag filter does not duplicate people having both tags; `%`/`_` are literal-safe (no match-all unless contained). (4) CSV UTF-8 BOM, header row, row count = filtered count (not 25), cells starting `=`/`+cmd`/`-5 days` prefixed `'`, a pure `+201...` phone left intact.
- **Assert (DB):** each filter count equals the same predicate in SQL on `identity_user` join `identity_studentprofile`.
- **Covered by:** `test_people_api::test_search_filters_and_pagination`, `test_csv_*`, `test_people_depth_lists`. P1 for the real 60-row set and the CSV injection check.

#### F05-TC-009: Duplicate email handling (create and edit)
- **Role:** admin. **Priority:** P1. **Provider:** REAL.
- **Steps:** with `f05-dup@qa.etqan.test` held by student A: (1) create a parent with the identical email; (2) with `F05-DUP@QA.ETQAN.TEST`; (3) with ` f05-dup@qa.etqan.test ` (spaces); (4) PATCH another person to it; (5) PATCH A to its own email in different case; (6) person B whose `pending_email` is `f05-pend@...` (after a signed-in email change), then create C with `f05-pend@...`; (7) same email in `qaother` (`req qaother oth POST people/teachers/ ...f05-dup...`); (8) teacher with `email` of the academy admin.
- **Expected:** (1)-(4) 400 `user.email: "This email is already in use."`, nothing created, no mail. (5) 200, no invite, no change. (6) 400 (pending address counts). (7) 201 (schemas are separate; this is allowed). (8) 400.
- **Assert (DB):** `identity_user_email_ci_unique` index present (`\d academy_qa.identity_user`); count of `lower(email)=...` = 1 in `academy_qa`, 1 in `academy_qaother`; Mailpit count unchanged for refused cases.
- **Covered by:** `test_people_api::test_duplicate_email_error_is_nested_under_user`, `test_people_services`. P1 for casing/whitespace/pending/cross-academy.

#### F05-TC-010: Admin changes a signed-in person's email: pending, confirmation, promotion
- **Role:** admin, then the person. **Priority:** P1. **Provider:** REAL.
- **Steps:** student `f05-stu1@` (TC-001, has signed in). (1) `PATCH people/students/<id>/ {"user":{"email":"f05-stu1b@qa.etqan.test"}}`. (2) GET it. (3) login with old email works; login with new email fails. (4) open the confirmation link from Mailpit (`mails f05-stu1b@...`; allauth `identity/verify-email/` with the key). (5) GET again; login old/new; `mails f05-stu1@...` for the security alert.
- **Expected:** (1) 200, `email` unchanged, `pending_email` = new. (3) old ok, new 400. (5) `email` = new, `pending_email=""`, old address gone from `account_emailaddress` (free to reuse), old login fails, new works, old address received the security alert.
- **Assert (DB):** after (1) two `account_emailaddress` rows (old primary verified, new non-primary unverified); after (5) one row, primary+verified; `identity_user.email` = new.
- **Covered by:** `test_email_management`, `test_people_services`. P1 (account takeover surface).

### B. State transitions and edge cases

#### F05-TC-011: Deactivate and reactivate: sessions die, last admin and self are protected
- **Role:** admin. **Priority:** P1. **Provider:** REAL.
- **Steps:** (1) with `stu` and `s1` logged in (live jars), `POST people/students/<id>/deactivate/`; immediately `GET identity/me/` with that jar; try `login`. (2) `POST people/teachers/<id>/deactivate/` for a teacher with a quick-login session open (`POST people/teachers/<id>/quick-login/` as admin first). (3) admin deactivates self; create 2nd admin and have admin2 deactivate admin1 and then try the last one. (4) `POST .../activate/`; log in with the old password. (5) `POST people/admins/<id>/deactivate/` as staff `codes`. (6) `POST people/students/<id>/deactivate/` twice.
- **Expected:** (1) 200 `is_active=false`, `account_state=inactive`; `me` -> 401/403, login refused with the inactive message. (2) the impersonation session also ends. (3) self -> 400 "cannot deactivate your own account"; last admin -> 400 "at least one active admin"; the `deactivation_blocked` field shows `self`/`last_admin`. (4) works with the unchanged password. (5) 403. (6) second call 200 (idempotent).
- **Assert (DB):** `identity_user.is_active`; `django_session` rows for that user id gone (decode `session_data` or count before/after); other users' sessions untouched.
- **Covered by:** `test_people_actions_api::test_self_guard_*`, `test_last_admin_*`. P1 for the live-session and reactivate-with-same-password parts.

#### F05-TC-012: Deactivated person: invite/reset links, lists and downstream pickers
- **Role:** admin. **Priority:** P1. **Provider:** REAL.
- **Steps:** (1) invite a student, deactivate before acceptance, then `POST .../invite/` and use the earlier invite link on `identity/password/reset/confirm/`. (2) forgot-password for a deactivated active-password person: `POST identity/password/reset/ {"email":...}`; `mails`. (3) `GET people/teachers/?is_active=true` vs `false`; a deactivated teacher in the catalogue/scheduling teacher pickers (`GET people/teachers/?is_active=true` is the source; spot check `GET catalogue/...` teacher options if present). (4) deactivated parent: sign-in attempt; `GET people/students/<s>/guardians/` still lists them.
- **Expected:** (1) invite action 400 (`inactive`); old link: sets a password but the account stays inactive and cannot sign in (record exactly what the API says; a reset must not reactivate). (2) generic 200, no usable reset mail for an inactive account (or mail but no sign-in): record behaviour. (3) filters exact. (4) refused; guardians list unchanged (people screens do not filter by `is_active`).
- **Assert (DB):** `is_active` stays false through every step; `account_emailaddress.verified` after step 1 (see S6).
- **Covered by:** `test_active_teachers`, `test_api_auth` (partly). P1 (access-control leak if a reset reactivates).

#### F05-TC-013: Permission matrix on people routes (compressed)
- **Roles:** admin, staff no-code, staff `codes` (student.view+view_any), supervisor, teacher, student, parent, anonymous. **Priority:** P1. **Provider:** REAL.
- **Steps:** for each jar run: `GET people/students/`, `GET people/students/<id>/`, `POST people/students/`, `PATCH people/students/<id>/`, `POST .../deactivate/`, `POST people/students/bulk/`, `GET people/teachers/`, `GET people/parents/`, `GET people/admins/`, `GET people/tags/`, `POST people/tags/`, `GET people/families/`, `GET people/students/?format=csv`, `GET identity/me/`.
- **Expected (status):**
  | jar | students GET list/detail | students POST/PATCH/action/bulk | teachers/parents GET | admins GET | tags GET | families GET | csv |
  |---|---|---|---|---|---|---|---|
  | admin | 200 | 201/200 | 200 | 200 | 200 | 200 | 200 |
  | nocode | 403 | 403 | 403 | 403 | 403 | 403 | 403 |
  | codes | 200 | 403 | 403 | 403 | 403 | 403 | 200 |
  | supervisor | 200 | 403 | 200 | 403 | 403 (no `tag.*`) | 200 | 200 |
  | teacher/student/parent | 403 | 403 | 403 | 403 | 403 | 403 | 403 |
  | anonymous | 401/403 | same | same | same | same | same | same |
  `identity/me/` 200 for everyone signed in, 401/403 anonymous. No 5xx anywhere; a 404/403 never reveals whether an id exists to non-office users.
- **Assert:** the response body of every 403 contains no person data; DB unchanged (row counts before/after).
- **Covered by:** `test_people_api::test_non_admins_are_refused`, `test_people_actions_api::test_non_admins_*`, `test_staff_scope`. P1: the matrix executed against the live stack with the real supervisor/staff accounts.

#### F05-TC-014: Staff with partial codes: granularity of create/update/bulk/guardians/tags
- **Role:** staff with role "QA5 Student Edit" (student.view/view_any/create/update), created via `access/staff/`. **Priority:** P1. **Provider:** REAL.
- **Steps:** create staff `f05-st-edit@` with `role_ids:[<role>]`, accept invite, login `ed`. (1) `POST people/students/` -> 201 with an email. (2) `PATCH` the student. (3) `POST people/students/bulk/ {"action":"create_family",...}` and `add_to_family`. (4) `POST people/students/<s>/guardians/ {"parent_id":<p>}` (no `parent.view`). (5) `GET people/families/payers/?students=<s>`. (6) `POST people/tags/`. (7) `POST people/teachers/`. (8) `POST people/students/<s>/quick-login/`. (9) `POST people/admins/<a>/deactivate/`.
- **Expected:** (1)(2) ok. (3) `create_family` 403 ("also need permission to create families"); `add_to_family` allowed on `student.update` alone. (4) see S3: record whether it is allowed and what parent data comes back. (5) 200 (any of family.create/update or student.update). (6)(7)(9) 403. (8) 403 (no `quick_login.create`).
- **Assert (DB):** no rows created for the 403 calls; `identity_family` count unchanged by (3) create_family.
- **Covered by:** `test_family_bulk::*staff_for*`, `test_staff_scope`. P1.

#### F05-TC-015: Staff account lifecycle through `access/staff/`
- **Role:** admin, staff. **Switches:** defaults. **Priority:** P1. **Provider:** REAL.
- **Steps:** (1) `POST access/staff/ {"full_name":"QA5 Staffer","email":"f05-staff@qa.etqan.test","role_ids":[<supervisor role>]}`; `accept`; login. (2) `POST access/staff/` with duplicate email and with `email` missing. (3) `PATCH access/staff/<id>/ {"role_ids":[<other>]}`, `{"is_active":false}`, `{"is_active":true}`. (4) the staff member `PATCH`es own `role_ids` and `is_active:false`. (5) `GET people/admins/` and `GET people/staff/` (no such) as admin; list shows staff in `access/staff/` only. (6) a staff with a weaker role edits the email/activity of a stronger staff.
- **Expected:** (1) 201, state `invited`, becomes `active`; `/me` `permissions` equals the role's codes. (2) 400 on `email`. (3) role change takes effect on the next request; deactivate kills the session. (4) 403 for both. (5) staff never appear under `people/admins/`. (6) 403 (stronger-account guard).
- **Assert (DB):** `identity_user.role='staff'`, no profile row, `access` join rows match.
- **Covered by:** `access/tests/*`, `test_staff_accounts`. P1 here only for the end-to-end invite->login->permissions chain; the guard rules belong to F03.

#### F05-TC-016: Cross-academy isolation of people (qa vs qaother)
- **Role:** admin of each. **Priority:** P1 (P0 if it fails). **Provider:** REAL.
- **Steps:** let `Xo` = ids of a student, parent, teacher, family, tag, contract in `qaother`; `Xq` = the same in `qa`. As qa admin (and as the qaother admin against qa ids): (1) `GET/PATCH` `people/<kind>/<Xo>/`; `POST .../deactivate/`; `GET people/students/<Xo>/guardians/`; (2) `POST people/students/<Xq>/guardians/ {"parent_id":<qaother parent>}`; (3) `POST people/families/ {"student_ids":[<qaother student>],"payer_id":<qaother parent>}`; (4) `bulk` with qaother ids; (5) tag ids of qaother in `tag_ids`; (6) `GET contracts/<qaother id>/` (+`/file/`); (7) replay the `qaother` `sessionid` cookie against `qa.etqan.localhost/api/v1/identity/me/` and the reverse; (8) log into `qa` with qaother admin credentials; (9) `GET people/students/?q=<qaother name>`; CSV export; (10) use a reset token from one academy on the other's confirm endpoint.
- **Expected:** every foreign id: 404 (detail/actions), 400 (invalid choice) for writes referencing them, `updated:0`/ignored in bulk; (7) anonymous; (8) 400; (9) 0 results, CSV has none; (10) 400 invalid link. No foreign row changed.
- **Assert (DB):** full-table checksums before/after for `academy_qaother` (`select md5(string_agg(t::text,'' order by id)) from academy_qaother.identity_user t` for user, profile, family, tag, contract tables) and the same for `academy_qa` (apart from intended changes).
- **Covered by:** `test_other_academy_people_never_leak`, `test_actions_on_another_kind_or_academy_are_404`, `test_guardian_from_other_academy_is_404`, `test_another_academys_families_*`, `test_family_bulk::test_non_students_and_other_academies_*`. P1 for the live two-subdomain run and cookie replay, which pytest cannot do.

#### F05-TC-017: A parent sees only their own children
- **Role:** parent `par` (qa-parent, linked to qa-student only), second parent. **Switches:** `parents`. **Priority:** P1. **Provider:** REAL.
- **Steps:** (1) `GET identity/me/` as `par`: `children`. (2) link a second child (admin), re-read; unlink the first, re-read. (3) as `par`: `GET people/students/<other child>/`, `.../guardians/`, `GET people/parents/<id>/children/`, `GET people/families/`, `GET contracts/`, `GET people/tags/`. (4) other parent's `me` does not contain `par`'s children. (5) `parents` off -> `children` absent from `me`.
- **Expected:** (1)(2) exactly the linked, current children, each with `profile` lacking `notes`/`nationality`. (3) all 403. (4) disjoint. (5) key absent (and the session is signed out, TC-004).
- **Assert (DB):** `children` ids equal `select student.user_id from identity_guardianship g join identity_parentprofile p ... where p.user_id=<par>`.
- **Covered by:** `test_parent_me_reads_children_profiles`, `test_parent_me_hides_staff_notes_*`. P1 for the live link/unlink edits and 403 sweep. (Other APIs' scoping, e.g. sessions/invoices for parents, belongs to F06/F08/F09.)

#### F05-TC-018: Profile self-edit for every role; no privilege escalation
- **Role:** teacher, student, parent, admin, staff each on their own account. **Priority:** P1. **Provider:** REAL.
- **Steps:** `PATCH identity/me/` with: (1) `{"full_name":"QA5 New Name","phone":"+201005550303","preferred_language":"en","timezone":"Africa/Cairo"}`. (2) mass-assignment attempt: `{"role":"admin","is_active":false,"email":"x@qa.etqan.test","is_staff":true,"is_superuser":true,"profile":{"notes":"hacked","xp":999999,"status":"active"},"pay_currency":"USD","family":1}`. (3) `{"phone":"12345"}`, `{"timezone":"Mars/Phobos"}`, `{"full_name":"   "}`, `{"preferred_language":"es"}` (spanish off), `{"full_name":"<256 chars>"}`. (4) as admin quick-logged-in as the student (impersonating): `PATCH identity/me/ {"phone":"+201005550404"}` and `{"full_name":"x"}`. (5) email change: `POST identity/me/emails/` without and with a wrong `current_password`.
- **Expected:** (1) 200 and persisted. (2) 200 or 400 but **no** field of (2) changes: role, active, email, profile fields, currency, family unchanged. (3) each 400 on its field with nothing changed. (4) phone 403 `identity.impersonating`; name ok. (5) 400 without/with wrong password.
- **Assert (DB):** `identity_user` row diff after (2) is empty except possibly `updated` columns; `identity_studentprofile.notes/xp/status` and `identity_teacherprofile.pay_currency` unchanged.
- **Covered by:** `test_me_shows_own_profile_and_updates_contact_fields`, `test_phone_login`, `test_impersonation`, `test_spanish`. P1 for the explicit mass-assignment probes.

#### F05-TC-019: Staff-only fields and payout details: who can read them
- **Role:** all. **Priority:** P1. **Provider:** REAL.
- **Steps:** student with `notes:"internal"`, `nationality:"foreign"`; teacher with `payout_method:"bank_account"`, `payout_details:"IBAN QA5-SECRET"`; parent with `notes`. Read as: student (`identity/me/`), parent (`me` + children), teacher (`me`), other teacher, supervisor (`GET people/teachers/<id>/`), staff `codes` (`people/students/<id>/`), CSV export, family `notes`.
- **Expected:** `notes`/`nationality` absent from `me` of the person and of parents' children; `payout_details` only in admin/staff-with-`teacher.view*` payloads and in the teacher's own `me`; never in any student/parent/other-teacher response; CSV `teachers` has "Payout method" column (confirm whether details are exported: record).
- **Assert (DB):** values stored verbatim; grep every non-office JSON response above for the marker strings (`IBAN QA5-SECRET`, `internal`) = 0 hits.
- **Covered by:** `test_student_me_hides_staff_notes`, `test_profile_access`. P1 (PII/financial data).

#### F05-TC-020: Tags: create, rename, order, retire; assignment rules
- **Role:** admin; staff with `tag.*`. **Priority:** P1. **Provider:** REAL.
- **Steps:** (1) `GET people/tags/` (preset count per kind; record, F01 baseline 21 student + 22 teacher). (2) `POST people/tags/ {"kind":"student","name_en":"QA5 Gifted","name_ar":"موهوب","emoji":"🌟"}`; the same again; same with `name_en:"qa5 GIFTED"`; same `name_ar` different kind. (3) `PATCH people/tags/<t>/ {"position":1}` then `{"position":999}`, `{"position":0}`, `{"kind":"teacher"}`. (4) attach to a student; retire the tag; `PATCH` the student keeping `tag_ids`; assign it to a second student; `POST bulk add_tag`; filter `?tag=<t>`. (5) use a teacher tag in `tag_ids` of a student. (6) `DELETE people/tags/<t>/`.
- **Expected:** (2) first 201, the other two 400 (`name_en`), cross-kind same name ok. (3) positions renumbered 1..n with no gaps, 0 -> 400, `kind` ignored/unknown; (4) retired tag stays on person, second student -> 400 "retired tag", bulk add 400, filter still finds the first student; `people` count counts only active people. (5) 400. (6) 405.
- **Assert (DB):** `identity_tag.position` contiguous per kind; unique `(kind, lower(name_en))`; no row deleted.
- **Covered by:** `test_tags`, `test_tags_api`. P1 for the run on the real preset data and concurrency of positions.

### C. Contracts (teacher contracts, `contracts` switch)

#### F05-TC-021: Contract workflow with a private file
- **Role:** admin, teacher. **Switches:** `contracts` on. **Priority:** P1. **Provider:** REAL (local private storage).
- **Steps:** (1) `curl -F teacher=<t> -F reference=EMP-1 -F details= -F file=@sample.pdf` to `contracts/` (multipart, CSRF header). (2) `GET contracts/`, `?teacher=<t>`, `?q=EMP`. (3) `GET contracts/<id>/file/` as admin and as the owning teacher; capture headers. (4) `PATCH` new file (docx), then `PATCH remove_file=true` with empty details, then with details set. (5) bad inputs: `.exe`; 11 MiB pdf; text renamed `.pdf`; non-teacher `teacher` id (student); neither details nor file; reference 61 chars; file name 300 chars. (6) `DELETE contracts/<id>/`.
- **Expected:** (1) 201, `has_file=true`, no URL anywhere in JSON. (3) 200 attachment, `Cache-Control: private, no-store`, `X-Content-Type-Options: nosniff`, correct bytes (sha256 equal). (4) old object removed after commit, `remove_file` with empty details -> 400 `non_field_errors`. (5) every case 400 with no row/file created; the long name is cut to 255 keeping the extension. (6) 204 and file gone.
- **Assert (DB/FS):** `employment_contract` row, `file` path `tenants/academy_qa/employment/<uuid>.<ext>` in the private media dir (inside django container: `ls $DJANGO_PRIVATE_MEDIA_ROOT/tenants/academy_qa/employment`); CHECK `employment_contract_details_or_file` present; files list before/after for orphans after failed uploads (expected: orphans only on rolled-back requests, document the count).
- **Covered by:** `employment/tests/test_api.py` (whole flow). P1 for the live-stack run and storage-on-disk assertions.

#### F05-TC-022: Contract access matrix and isolation
- **Role:** admin, staff without/with `contract.*`, teacher A (owner), teacher B, student, parent, anonymous, qaother admin. **Priority:** P1. **Provider:** REAL.
- **Steps:** with one contract of teacher A (with file): each role does `GET contracts/`, `GET contracts/<id>/`, `GET contracts/<id>/file/`, `POST`, `PATCH`, `DELETE`. Then `set_features qa --off contracts` and repeat for admin and teacher A. Then try the stored path over HTTP (`http://qa.etqan.localhost/media/tenants/academy_qa/employment/<name>`, `/private/...`). Deactivate teacher A and retry download with their old session. Staff with `contract.view_any` only (no `contract.view`) on detail/file.
- **Expected:** admin all 2xx; staff no-code 403, staff with codes only the verbs held; teacher A: list shows only own, detail/file 200, write verbs 403; teacher B: 404 on A's detail/file, empty list; student/parent 403; anonymous 401/403; qaother admin 404; switch off: 404 for admin and teacher; direct media URL 404/403 (no public access to the private file); deactivated teacher denied.
- **Assert (DB):** `employment_contract` untouched by refused calls; no `file` URL leaks in any JSON.
- **Covered by:** `test_teacher_sees_only_own_and_cannot_write`, `test_teacher_cannot_download_another_teachers_file`, `test_students_and_parents_are_refused`, `test_off_is_404_*`. P1 for the direct-URL probe and cross-academy file access.

### D. Concurrency, validation and switches

#### F05-TC-023: Concurrency: duplicate email race, family claim race, last-admin race
- **Role:** admin(s). **Priority:** P2 (P1 if a 500 or an invariant breaks). **Provider:** REAL.
- **Steps:** (1) fire 2-5 parallel `POST people/students/` with the same new email (`xargs -P5`). (2) two parallel `POST people/families/` claiming the same student. (3) two admins deactivate each other at the same time (3 admins: A deactivates B while B deactivates A, repeat 10x). (4) two parallel `PATCH` to the same email on different people.
- **Expected:** exactly one 201 and the others 400 (never 500; see S1). One family wins and the loser gets 400 on `student_ids`. At least one admin stays active; no 500.
- **Assert (DB):** one row per email; one `family_id` per student; `select count(*) from academy_qa.identity_user where role='admin' and is_active` >= 1.
- **Covered by:** `test_family_bulk::test_a_student_claimed_meanwhile_*` (simulated), `test_people_services` (lock). Live race is new.

#### F05-TC-024: Field validation edges for students and teachers
- **Role:** admin. **Priority:** P2. **Provider:** REAL.
- **Steps:** create/PATCH with: `xp` 1000001 and -1; `date_of_birth` in the future, `0001-01-01`, `"2012-02-30"`; `country` `"egy"`, `"e"`, `" eg "`; `status` `"nope"`; `gender` `"x"`; `preferred_language` `"es"` with `spanish` off then on; `timezone` `"UTC+2"`; `phone` `"+201 005 550 505"` (spaces) and 17 digits; `full_name` 255/256 chars and with Arabic/emoji/leading spaces; `default_meeting_url` `"javascript:alert(1)"` and 2000 chars; `payout_method` `"nope"`; `pay_currency` `"XXX"`, `"eg"`, `"EGPP"`, `""`; `null` for text fields; unknown keys in `profile`/`user`; `profile` for an admin.
- **Expected:** each invalid value 400 on the correct nested field with nothing written; spaces in phone stripped; names trimmed; unknown keys rejected; no 500 on any input. Record accepted oddities (future DOB, `XXX`) as findings.
- **Assert (DB):** column lengths respected (`phone` varchar(16), `full_name` 255, `country` 2).
- **Covered by:** `test_profile_depth`, `test_spanish`, `test_people_api::test_bad_phone_is_nested_under_user`. P2.

#### F05-TC-025: Student age groups and academy-day boundary
- **Role:** admin. **Priority:** P2. **Provider:** REAL.
- **Steps:** with the academy tz Africa/Cairo, create students with DOB exactly 13 years ago today, 13 years ago tomorrow, 18 years ago today/tomorrow; `GET people/students/?age_group=child|teen|adult|minor`; read `profile.age_group`. Repeat around midnight Cairo vs UTC if practical (otherwise static DOBs and compare with `Q "select current_date at time zone 'Africa/Cairo'"`).
- **Expected:** `child <13`, `teen 13-17`, `adult >=18` by the academy's today; filters agree with payload; `minor` = child + teen.
- **Assert (DB):** DOB stored as date; filter counts equal SQL date comparisons.
- **Covered by:** `test_ages`. P2.

#### F05-TC-026: `families` switch off and back on
- **Role:** admin, staff. **Switches:** `families` off then on. **Priority:** P1. **Provider:** REAL.
- **Steps:** with data from TC-005: `set_features qa --off families`; call `GET people/families/`, `POST people/families/`, `GET people/families/payers/?students=1`, `POST people/students/bulk/` with `create_family` / `add_to_family` (as admin, as staff without family codes), `GET people/students/` (fields), `?account_type=family`, `?format=csv`; then switch on.
- **Expected:** family routes 404; bulk family actions 404 for admin and 403 for staff without the code (permission first); student rows have no `account_type`/`family`; the filters are ignored (not an error); CSV has no Family columns; after switch-on everything reappears intact (family rows and student links unchanged; `invoices` payer fallback unaffected).
- **Assert (DB):** `identity_family` and `identity_studentprofile.family_id` identical before/after the off/on cycle (checksum).
- **Covered by:** `test_family_bulk::test_the_family_actions_go_with_the_families_feature`, `test_features`. P1.

#### F05-TC-027: Invite/reset token abuse
- **Role:** anonymous. **Priority:** P1. **Provider:** REAL.
- **Steps:** (1) accept an invite, then reuse the same link. (2) change the person's email (never signed in) and use the old link. (3) deactivate the person, use the link. (4) tamper `uid` (another user's id) with a valid token; truncated token; weak `new_password` ("12345678", "password"). (5) take a valid qa link and post it to `qaother.etqan.localhost`'s confirm endpoint with the same uid number.
- **Expected:** (1) 400 (token includes the password hash). (2) 400. (3) record (see S6). (4) 400 each; weak password 400 with the validator message and the password not set. (5) 400.
- **Assert (DB):** `identity_user.password` unchanged by every failing call.
- **Covered by:** `test_password_management`, `test_code_reset` (partly). P1.

### E. UI smoke (Playwright, `--workers=1`)

#### F05-TC-028: UI smoke 1: add a student, see it in the 60-row list, deactivate
- **Role:** admin (browser). **Priority:** P1. **Provider:** REAL.
- **Steps:** `/app/people/students/new` fill name+email+tag; save; open list, search `QA5 Bulk 05`, go to page 2 and 3 of the unfiltered list, run the bulk bar (select 3, deactivate); open one row and Activate. Axe scan of the list.
- **Expected/Assert:** toast, row appears with state chip "invited"; counts and pagination in the UI equal the API; the bulk result equals `GET ...?is_active=false`; no console errors; DB row matches.
- **Covered by:** e2e `people-catalogue.spec.ts` (create path only). P1 for pagination/bulk UI.

#### F05-TC-029: UI smoke 2: family with a paying parent
- **Role:** admin. **Priority:** P1. **Provider:** REAL.
- **Steps:** `/app/people/families` -> new family: pick two students, payer select shows students first then their parents; choose the parent; save; open the family page; retire.
- **Expected/Assert:** payer options match `GET people/families/payers/`; flag "payer needs choosing" visible after deactivating the payer; DB `identity_family.payer_id`.
- **Covered by:** e2e `families.spec.ts`. Run the existing spec plus a short extension rather than a new one.

#### F05-TC-030: UI smoke 3: contracts upload by admin, download by the teacher
- **Role:** admin then teacher. **Switches:** `contracts`. **Priority:** P2. **Provider:** REAL.
- **Steps:** `/app/people/contracts?teacher=<id>` -> create with PDF; sign in as the teacher, `/app/account` -> "My contracts" -> download.
- **Expected/Assert:** the downloaded bytes' sha256 equals the upload; student cannot open `/app/people/contracts` (guard); API/DB per TC-021.
- **Covered by:** no e2e today.

---
## Suspected defects from code reading (for Agent 2 to confirm or clear)
- **S1 (P2):** Duplicate-email race: `_build_person`/`update_person` pre-check `_email_taken` then `user.save()`; there is no `IntegrityError` handler, so two simultaneous creates of one email can return a 500 (the ci-unique index saves the data). Try in TC-023. (Tags have such a handler; people do not.)
- **S2 (P2):** `bulk_family(add_to_family)` loads the family with `Family.objects.filter(pk=...)` and does not check `is_active` or payer validity: students can be added to a retired family, and the family may show `payer_needs_choosing` afterwards. Check against the doc ("retired families supply no payer"). Try in TC-007/005.
- **S3 (P2):** `POST people/students/<id>/guardians/` needs only `student.update` and resolves the parent via `person_or_404` (all parents), so a staff account without `parent.view` can link any parent and read that parent's name/email/phone from the response. Same for `FamilyPayersView` (names only). TC-014 step 4.
- **S4 (P2, product question):** every `*.view_any` holder (the Supervisor preset has teacher/student/parent/family view) sees `payout_details` (bank/IBAN), student `notes` and `nationality`, and `last_login_ip` through `person_rows`. Docs say "staff see all rows"; confirm that is wanted for payout details. TC-019.
- **S5 (P2):** `pay_currency` accepts any three letters (`XXX`, `ZZZ`; already in F01 coverage gaps) and there is no check against currencies the academy/payroll can pay; a typo (`EGPP` is refused, `EGB` is not) would only fail later in payroll. TC-003/024.
- **S6 (P3):** `confirm_password_reset` works for a deactivated user (sets the password and marks the primary email verified); and `deactivate` does not revoke outstanding invite/reset/pending-email links. It cannot sign in, but verify the account stays inactive and no activation side effect occurs. TC-012/027.
- **S7 (P3):** `date_of_birth` has no range check (future or year 0001 accepted; a future DOB yields `age_group=child`); `xp` is bounded but `default_meeting_url` scheme is not restricted beyond `URLField`. TC-024.
- **S8 (P3):** Upload checks for contracts are signature-only for `.docx`/`.pdf` (first 16 bytes); a non-DOCX zip renamed `.docx` is accepted. The file is private and served as an attachment with `nosniff`, so impact is low. TC-021.
- **S9 (P3):** Family/payer eligibility checks `is_active` for the payer but `_family_students` does not exclude deactivated students, so a family can be created for inactive students. Confirm the intended rule. TC-005.
- **S10 (P3):** `resend_invite` on a deactivated invited person answers with "Only someone who has not set a password yet can be re-invited" (misleading; the real reason is inactivity). Cosmetic. TC-012.

## Not tested here (see coverage-gaps.md)
Live WhatsApp/SMS delivery, 2FA admin-disable and quick-login link emails (F02), staff role definitions (F03), invoices consuming the family payer (F09), registration/self-signup (F10), the 300-student seed and performance.

---
## Added by Agent 2 (execution, 2026-10-19)

#### F05-TC-031: Impersonation (quick-login) cannot reach office routes and ends with the target
- **Role:** admin quick-logged-in as a student. **Priority:** P1. **Provider:** REAL.
- **Steps:** admin fresh session → `POST people/students/<s>/quick-login/`; then `GET people/students/`, `people/teachers/`,
  `access/staff/`, `contracts/`, `people/families/`; `POST people/admins/`; nested `quick-login`; admin (other session) deactivates the
  student; impersonating session `GET identity/me/`.
- **Expected:** every office call 403, nothing created; the impersonating session ends when the target is deactivated.

### Spec corrections (expected behaviour re-checked against docs/code)
- **TC-006 step 5:** unlinking the payer from *one* student leaves `payer_needs_choosing=false` while the payer is still a parent of
  another family student (correct: payer = "one of the students or their parents"). The flag turns true only after the payer is
  unlinked from every family student (executed as a follow-up: true, then false after repair).
- **TC-011 step 3:** the `last_admin` refusal is unreachable sequentially (only an active admin can deactivate, and self is refused
  first); it is covered by the TC-023 mutual-deactivation race (10 rounds, always exactly one active admin) and pytest.
- **TC-018 step 3 / TC-024:** `preferred_language:"es"` with `spanish` off is refused on `people/*` and on `me` unless it is the
  person's *stored* value (`_clean_person_language(stored=...)`, by design). Unknown keys in `user`/`profile` are ignored by DRF
  (200, nothing stored), not rejected: standard behaviour, not a defect.
- **TC-007 step 4:** qaother ids collide numerically with qa ids (qaother student id 5 = qa-student id 5), so foreign-id probes are
  done from the qaother side against qa-only ids (TC-016) plus schema checksums.

## Results (Agent 2, 2026-10-19, lean mode)
Evidence root: `qa/evidence/F05/` (scripts in `scripts/`, Playwright in `pw/`). Stack: backend adff9c9 / dashboard 5ed775d on
branch qa/campaign-2026-10. Setup: `set_features qa --on families parents contracts quick_login export` (+ qaother families parents
contracts for TC-016); 60 `QA5 Bulk` students, role 29 "QA5 Student Edit". Scoped pytest `etqan/identity etqan/employment`: 888 passed
(`pytest-identity-employment.txt`).

| Case | Result | Tag | Evidence | Notes |
|---|---|---|---|---|
| TC-001 | PASS | REAL | `tc001-003.txt` | invited→active, EG upper-cased, teen, 1 invite (host qa, `/app/reset-password`), `me` hides notes/nationality, verified f→t |
| TC-002 | PASS | REAL | `tc001-003.txt` | NULL email, invite/reset 400, add email → 1 invite, replace re-invites, old link 400 |
| TC-003 | PASS | REAL | `tc001-003.txt` | gender/payout_details 400 atomic (count 116→116, 0 mail); USD upper-cased; default EGP; currency kept on unrelated PATCH. Note: clearing `payout_method` keeps the old `payout_details` text (not filed) |
| TC-004 | PASS | REAL | `tc004-006.txt` | idempotent link/unlink, teacher as parent 404, parents off: routes 404, live parent session 403, login "Parent access is not enabled", back on: children intact |
| TC-005 | PASS | REAL | `tc004-006.txt` | payers students-then-parents, 6 invalid creates 400 with no row, filters exact, DELETE 405 |
| TC-006 | PASS | REAL | `tc004-006.txt`, `tc006b-007.txt` | deactivate payer → flag true; `family_payer` None, `guardians_by_link` skips inactive; family row `updated_at` constant (see spec correction) |
| TC-007 | FAIL | REAL | `tc006b-007.txt`, `tc007b-008.txt` | bulk counts = SQL, retired tag add 400, 501/empty ids 400, session of bulk-deactivated student killed (others alive), qaother checksum unchanged; **S2 → ETQAN-QA-033 (P3)** |
| TC-008 | FAIL | REAL | `tc007b-008.txt`, `tc008-csv.txt`, `students.csv` | 76 rows over 4 pages, no dup/gap, page_size clamp, bad page 404, filters = SQL, `%`/`_` literal, CSV BOM + full count + `'`-prefixed `=`/`+`/`-`/`@` cells; **lower-case `country=eg` → 0: ETQAN-QA-037 (P4)** |
| TC-009 | PASS | REAL | `tc009-010a.txt`, `tc009b-010.txt` | case/space/pending/admin duplicates 400, no user/mail; own email other case = no-op; qaother same email 201; `identity_user_email_ci_unique` present |
| TC-010 | PASS | REAL | `tc009-010a.txt`, `tc009b-010.txt` | pending_email, old login works/new "not verified", verify-email → promoted, old login fails, security alert to old address, key single-use, old address reusable |
| TC-011 | PASS | REAL | `tc011-012-027.txt`, `tc011-redo.txt` | sessions die on deactivate (incl. quick-login impersonation session), self 400 + `deactivation_blocked:"self"`, staff 403, idempotent, reactivate keeps password |
| TC-012 | FAIL | REAL | `tc011-012-027.txt` | filters exact, deactivated parent refused, guardians still listed; **S6 → ETQAN-QA-034 (P3)** (old invite link sets password + verifies on a deactivated account; forgot-password mails an inactive account), **S10 → ETQAN-QA-037 (P4)** |
| TC-013 | PASS | REAL | `tc013-matrix.txt` | 8 roles × 14 calls exactly as the spec table; no person data in 403 bodies; 403 identical for existing/nonexistent ids; counts only changed by admin |
| TC-014 | PASS | REAL | `tc014-015.txt` | create/patch ok, create_family 403 (family count 4→4), add_to_family ok, tags/teachers/quick-login/admin 403; S3 recorded below |
| TC-015 | PASS | REAL | `tc014-015.txt` | staff invite→active, perms = role, dup/missing email 400, role change live, self-edit 403, deactivate kills session, no profile row, staff not under admins |
| TC-016 | PASS | REAL | `tc016.txt` | qaother admin → qa-only ids 404/400/`updated:0`; cookie replay 403 both ways; cross credentials 400; cross reset link 400; checksums of 8 tables unchanged in both schemas |
| TC-017 | PASS | REAL | `tc017-019.txt` | `children` = SQL through link/unlink, profiles without notes/nationality, 7 office routes 403, disjoint parents, parents off → 403 |
| TC-018 | PASS | REAL | `tc017-019.txt` | contact edit ok for 4 roles; mass-assignment (role/active/email/staff/superuser/notes/xp/status/currency/family) changes nothing; invalid values 400; impersonated phone 403 `identity.impersonating`; email change needs correct password |
| TC-019 | PASS | REAL | `tc017-019.txt`, `teachers.csv` | markers absent from every student/parent/other-teacher response; teacher's own `me` has payout; CSV has Payout method, not details; S4 recorded below |
| TC-020 | PASS | REAL | `tc020-023.txt` | ci-unique names per kind, positions contiguous (also after 6 parallel moves), 0 → 400, kind immutable, retired tag kept on edit, refused for new people/bulk, DELETE 405 |
| TC-021 | FAIL | REAL | `tc021.txt` | 201 no URL leak, private/no-store/nosniff attachment, sha256 equal, old file removed on replace, 6 bad inputs 400 with no row/file orphan, long name cut to 255 keeping `.pdf`, delete 204 + 404; **S8 → ETQAN-QA-036 (P3)** |
| TC-022 | PASS | REAL | `tc022.txt` | full matrix incl. view_any-only (list only), teacher B 404, media/private URLs 404, qaother 404, switch off 404, deactivated teacher 403 |
| TC-023 | PASS (retest 1) | REAL | `tc023-race.txt`, `tc020-023.txt`, `retest-1/qa032-api-repro.txt` | Execution: **S1 → ETQAN-QA-032 (P2)**, 4/5 parallel creates and 1/2 parallel edits → 500. Retest 1 (2026-10-19): 3×5 creates, mixed-case 5, 3×2 edits → exactly one winner, all others 400 field error, 0 500s; QA-032 VERIFIED. Family claim race ok (201 + 400); last-admin race 10/10 ok |
| TC-024 | FAIL | REAL | `tc024-025.txt` | all other edges 400 on the right field, phone spaces stripped, names trimmed, 255/256, `javascript:` URL 400; **S7 → ETQAN-QA-035 (P3)**; **S5 → ETQAN-QA-022 (P3, F05 note added)**: `XXX`/`EGB` pay currency accepted |
| TC-025 | PASS | REAL | `tc024-025.txt` | 13/18 today/tomorrow boundaries by the academy's day; child/teen/adult/minor counts = SQL |
| TC-026 | PASS | REAL | `tc026.txt` | routes and bulk family actions 404 (staff 403 first), fields/CSV columns gone, filters ignored, checksums identical after off/on |
| TC-027 | PASS | REAL | `tc011-012-027.txt` | reused/tampered/truncated/cross-academy tokens 400, weak passwords 400, passwords unchanged; step 3 is ETQAN-QA-034 |
| TC-028 | PASS | REAL | `pw-run2.txt`, `pw/tc028*.json` | UI create (invited), pager = API (4 pages), search, bulk Set status on 3 = API, deactivate/activate; axe: 0 violations; no 5xx |
| TC-029 | PASS | REAL | `pw-run2.txt`, `pw/tc029*` | payer options = API order, family saved with the parent payer, payer deactivated → API flag + "Choose a new payer" on the row |
| TC-030 | PASS | REAL | `pw-run2.txt`, `pw/tc030*` | admin upload in UI, teacher downloads under My contracts, sha256 equal; student redirected, API 403 |
| TC-031 | PASS | REAL | `tc031.txt` | added P1: impersonation session 403 on 5 office routes + admin create + quick-login; ends when the target is deactivated |

**Totals:** 31 executed (30 spec + 1 added), 25 PASS, 6 FAIL (P2 ×1, P3 ×4, P4 ×1 by worst bug), 0 BLOCKED. All REAL; no SIM/FAKE.
UI smoke 3/3 (run 1 had two test-side selector issues, fixed; run 2 green).

### Suspected defects
| S | Verdict | Evidence |
|---|---|---|
| S1 | CONFIRMED → ETQAN-QA-032 (P2) | `tc023-race.txt` |
| S2 | CONFIRMED → ETQAN-QA-033 (P3) | `tc006b-007.txt` |
| S3 | BY DESIGN: `docs/features/people.md` table sets `student.view`/`student.update` for guardian list/link. Live: a student-only staff member links parent 121 and gets its name/email/phone while `GET people/parents/121/` is 403; product question (parent contact enumeration by id) for the owner, not filed | `tc014-015.txt` |
| S4 | BY DESIGN (docs: office staff with the view codes see the full rows). Live: Supervisor preset sees `payout_details` IBAN, notes, nationality, `last_login_ip`; no leak to students/parents/other teachers. Product question for the owner | `tc017-019.txt` |
| S5 | CONFIRMED, same root cause as ETQAN-QA-022 (note added there) | `tc024-025.txt` |
| S6 | CONFIRMED → ETQAN-QA-034 (P3); account stays inactive, no activation side effect | `tc011-012-027.txt` |
| S7 | PARTLY CONFIRMED → ETQAN-QA-035 (P3) for DOB; meeting URL part refuted | `tc024-025.txt` |
| S8 | CONFIRMED → ETQAN-QA-036 (P3) | `tc021.txt` |
| S9 | BY DESIGN / refuted as a defect: a family may include an inactive student (payer must be active, enforced); no doc rule against it, and deactivating a student later keeps the family link anyway | `s9.txt` |
| S10 | CONFIRMED → ETQAN-QA-037 (P4) | `tc011-012-027.txt` |
