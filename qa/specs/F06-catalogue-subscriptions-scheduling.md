# F06: Catalogue, subscriptions & scheduling (F06 + F07 merged, LEAN)

Author: Agent 1 (research and test strategy). Approves nothing. Written 2026-10-18 from backend adff9c9 / dashboard 5ed775d.
Read: `docs/features/{catalogue,subscriptions,scheduling-tools}.md`, `catalogue/{models,services}.py`, `catalogue/api/serializers.py`,
`scheduling/{dates.py,api/views.py,api/serializers.py}`, `scheduling/services/{subscriptions,generation,lifecycle}.py`,
`rules.py` (excerpts), `academy/services.py`, `identity/services.py` (`deactivate`).

## Conventions
- API-first. `Host: qa.etqan.localhost` (other academy: `qaother.etqan.localhost`). Base `http://localhost/api/v1/`.
- `A <who> METHOD path [json]` means: curl with that user's cookie jar and `X-CSRFToken` (see Setup, helper `api`).
- Today in the stack is 2026-10-18 (Sunday). `D1` = next Monday 2026-10-19. academy `qa` is Africa/Cairo, EGP.
- Money is always integer minor units (EGP 1500.00 = `150000`). Tags: REAL unless stated. All data is created by tests with the prefix `QA6 ` and removed in cleanup (or left, if the case says so).
- Existing pytest is cited as **Cov:**. Agent 2 runs `pytest etqan/catalogue etqan/scheduling` once (scoped) as a baseline, then spends time on the API cases.
- Switches on qa (set once, see Setup): `country_pricing trial_sessions teacher_availability study_groups multi_course_subscriptions families family_subscriptions group_subscriptions weekly_schedules subscription_archive invoices supervision`.
- Priorities: P1 critical, P2 real risk. UI smoke cases (Playwright): TC-006, TC-014, TC-023 only.

## Setup (run once, as the qa admin)
```
DC=/private/tmp/claude-501/-Users-khaledsakr-Documents-Etqan-tutor/55afddca-abb7-4698-b08b-38df7f0acb0e/scratchpad/dc.sh
# S0 switches (record features JSON before/after)
$DC exec -T django python manage.py set_features qa --on country_pricing trial_sessions teacher_availability study_groups \
  multi_course_subscriptions families family_subscriptions group_subscriptions weekly_schedules subscription_archive invoices supervision
# S1 helper: api <jar> <METHOD> <path> [json]   (login once per jar)
H='Host: qa.etqan.localhost'; B=http://localhost/api/v1
login(){ jar=/tmp/qa6-$1.jar; rm -f $jar; curl -s -c $jar -H "$H" $B/identity/csrf/ >/dev/null
  T=$(awk '/csrftoken/{print $7}' $jar); curl -s -b $jar -c $jar -H "$H" -H "X-CSRFToken: $T" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$2\",\"password\":\"$3\"}" $B/identity/login/ -o /dev/null -w "%{http_code}\n"; }
api(){ jar=/tmp/qa6-$1.jar; T=$(awk '/csrftoken/{print $7}' $jar); m=$2; p=$3; shift 3
  curl -s -b $jar -c $jar -H "$H" -H "X-CSRFToken: $T" -H 'Content-Type: application/json' -X $m "$B$p" ${1:+-d "$1"} -w "\n%{http_code}\n"; }
login admin qa-admin@qa.etqan.test 'QA-Admin-2026!'; login codes qa-staff-codes@qa.etqan.test 'QA-People-2026!'
login nocode qa-staff-nocode@qa.etqan.test 'QA-People-2026!'; login sup qa-supervisor@qa.etqan.test 'QA-People-2026!'
login teacher qa-teacher@qa.etqan.test 'QA-People-2026!'; login student qa-student@qa.etqan.test 'QA-People-2026!'
login parent qa-parent@qa.etqan.test 'QA-People-2026!'
# S2 extra people (admin): POST /people/teachers/ {"user":{"full_name":"QA6 Teacher B","email":"qa6-teacher-b@qa.etqan.test"},"profile":{}}
#    same for QA6 Teacher C, students QA6 Student 1..4 (profile {"country":"EG"}), QA6 Student SA ({"country":"SA"}),
#    parent (guardian link per people_views) and a family: POST /people/families/ {"name":"QA6 Family","student_ids":[s1,s2],"payer_id":<parent user id>}.
#    Accept invites via mailpit or set a password (as F01 SETUP-5). Confirm the person body shape in identity/api/people_serializers.py:89.
# S3 catalogue (admin):
#   C1 POST /catalogue/courses/ {"name_ar":"قرآن","name_en":"QA6 Quran","language":"ar","teacher_ids":[<qa-teacher>,<teacherB>]}
#   C2 POST /catalogue/courses/ {"name_ar":"عربي","name_en":"QA6 Arabic","language":"ar","teacher_ids":[<qa-teacher>]}
#   P1 POST /catalogue/packages/ {"name_ar":"ب","name_en":"QA6 Pkg 2x1m","sessions_per_week":2,"session_minutes":45,"duration_value":1,"duration_unit":"month","freeze_days_allowed":7,"price_minor":150000,"currency":"EGP"}
#   P2 same with sessions_per_week 3, duration 10 day, price_minor 99999, name "QA6 Pkg 3x10d"
# Teacher conflicts / DB peeks:  $DC exec -T django python manage.py tenant_command dbshell --schema=academy_qa   (or psql -h localhost -p 5433 -U etqan etqan, schema academy_qa)
# Run the hourly job on demand: $DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c \
#   "from etqan.scheduling.services import run_lifecycle; print(run_lifecycle())"
```
Prerequisites: stack up, qa and qaother exist (F01 PASSED), mailpit up, F01 accounts valid. Never write to demo/other.

---

## A. Catalogue and money

#### F06-TC-001: Owner builds the catalogue (course, teachers, package) and sessions_total is derived
- **Pri:** P1. **Role:** admin. **Switches:** none. **Tag:** REAL.
- **Steps:** A admin POST `/catalogue/courses/` (C1 body). POST `/catalogue/packages/` P1 and P2 bodies (S3). GET `/catalogue/packages/<P1>/`, `/catalogue/courses/?q=QA6`. PATCH P1 `{"price_minor":160000}`.
- **Expected:** 201s. P1 `sessions_total` = 8 (2/wk × 4 weeks, a month is 4 weeks), P2 = 6 (3/wk × ceil(10/7)=2 weeks). `price_minor` is an integer in JSON, never "1500.00". `sessions_total` is not writable (PATCH `{"sessions_total":99}` is ignored/400).
- **Assertions DB (`academy_qa.catalogue_package`):** `price_minor` bigint 150000 then 160000, `currency='EGP'`; no `sessions_total` column; `catalogue_course_teachers` has 2 rows for C1.
- **Cov:** `catalogue/tests/test_sessions_total.py`, `test_api.py::test_package_sessions_total_is_derived_and_read_only`, `test_course_crud_with_teachers`. Kept as the end-to-end owner workflow.
- **Cleanup:** none (data reused). Revert P1 price to 150000.

#### F06-TC-002: Money input validation (integer minor units, currency)
- **Pri:** P1. **Role:** admin. **Tag:** REAL.
- **Steps:** POST `/catalogue/packages/` with the P1 body, varying one field each time: `price_minor` = `15.5`, `"1500"`, `-1`, `true`, `null`, `9223372036854775808`, `0`; `currency` = `"egp"`, `"EG"`, `"EGPP"`, `""`, `"XXX"`, `"ZZZ"`; `sessions_per_week` 0/15; `session_minutes` 14/241; `duration_value` 0/366; `freeze_days_allowed` 366.
- **Expected:** non-integer, negative, bool, null and overflow values give 400 with a `price_minor` field error and no row (never 500). `0` is accepted (free package). `"egp"` is stored as `EGP`. Bad currency 400 `currency`. Range violations 400 on the right field.
- **Assertions DB:** `count(*)` of packages unchanged after every 400; no 500 in `docker logs`.
- **Cov:** `test_api.py::test_package_bounds` (ranges only). Money/currency cases are new.
- **Cleanup:** delete the free/lowercase packages created.

#### F06-TC-003: Catalogue permission matrix
- **Pri:** P1. **Role:** all. **Tag:** REAL.
- **Steps:** for each of admin, staff-with-codes (give `qa-staff-codes` the codes `course.*`,`package.*` view_any/create/update/delete/replicate via its role; `qa-staff-nocode` has none), supervisor, teacher, student, parent, anonymous: GET `/catalogue/courses/`, GET `/catalogue/packages/`, POST `/catalogue/packages/` (P1 body), PATCH `<P1>` `{"is_active":true}`, DELETE `<new>`, POST `<P1>/duplicate/`, PUT `<P1>/country-prices/` `{"rows":[]}`, GET `<P1>/price/?student=<s>`.
- **Expected:** admin 2xx all. Staff with codes: per code. Staff without codes: 403 on all. Teacher: GET lists 200 with only `is_active=true` rows, all writes 403. Student/parent: 403 or 404, never data. Anonymous: 401/403.
- **Assertions:** teacher list excludes an inactive package (create one inactive first). No DB change for any refused write. Staff with only `package.view_any` cannot pass `?student=` unless it also has `student.view_any`.
- **Cov:** `test_api.py::test_roles` (partial).

#### F06-TC-004: Catalogue cross-academy isolation (qa vs qaother)
- **Pri:** P1. **Role:** admin of each. **Tag:** REAL.
- **Steps:** in qaother (login `qaother-admin@qa.etqan.test`), create a package and a course. From qa admin: GET/PATCH/DELETE/duplicate/country-prices on those ids; from qaother admin the same against qa's P1 id. Also use a qaother-session cookie against `Host: qa...`.
- **Expected:** 404 for every cross id (same integer ids may exist in both: verify each side gets its own row). Lists never contain the other academy's rows. Cross-host cookie is 401/403.
- **Assertions DB:** `academy_qa.catalogue_package` and `academy_qaother.catalogue_package` counts unchanged by the cross attempts; no package named with the other academy's marker appears.
- **Cleanup:** delete the qaother rows.

#### F06-TC-005: Delete vs deactivate, duplicate, inactive items cannot be sold
- **Pri:** P1. **Role:** admin. **Tag:** REAL.
- **Steps:** (after TC-008 made a subscription on P1/C1) DELETE `/catalogue/packages/<P1>/`, DELETE `/catalogue/courses/<C1>/`. POST `<P1>/duplicate/`, `<C1>/duplicate/`. PATCH P1 `{"is_active":false}` then POST `/subscriptions/` with it. Delete an unused package.
- **Expected:** 409 `catalogue.in_use` for both used rows. Duplicates are inactive, named "... (copy)", keep teachers and country prices. Subscription on an inactive package/course: 400 field `package` / `course` ("Choose an active ..."). Unused delete 204. Existing subscription still shows its copied values.
- **Assertions DB:** original rows still present; copy `is_active=false`; `catalogue_packagecountryprice` rows duplicated.
- **Cov:** `test_services.py` (delete/duplicate). The sell-inactive and in_use API path are repeated here because money depends on them.

## B. Country pricing and currencies

#### F06-TC-006: Country price list end to end (UI smoke)
- **Pri:** P1. **Role:** admin. **Switches:** `country_pricing`. **Tag:** REAL. **UI smoke #1 (Playwright, workers=1).**
- **Steps:** UI `/app/catalogue/packages/<P1>`: open "Country prices", add SA = 5000 SAR (50.00) and AE = 4000 AED... Save. Reload. API: GET `<P1>/country-prices/`; PUT `{"rows":[{"country":"SA","price_minor":5000,"currency":"SAR"},{"country":"US","price_minor":3000,"currency":"USD"}]}` (replaces whole list).
- **Expected:** UI shows the major-unit amounts (50.00) and API holds minor units. PUT replaces: the earlier AE row is gone. Case: `sa` lower-case is accepted and stored `SA`.
- **Assertions DB (`catalogue_packagecountryprice`):** exactly the PUT rows, `price_minor` integers, unique (package, country).
- **Cov:** `test_country_prices*.py`, `dashboard/e2e/b3-country-prices.spec.ts`. UI part is the only new item.

#### F06-TC-007: Country price validation and the 250-row cap
- **Pri:** P2. **Role:** admin. **Tag:** REAL.
- **Steps:** PUT `<P1>/country-prices/` with: duplicate country; `price_minor` -1 / 1.5 / true / 9223372036854775808; country `"XX1"`, `"S"`, `""`; currency `"sar"`, `"S"`; 251 rows; `"rows":"x"`; a failing second row after a valid first.
- **Expected:** 400 with errors keyed `rows.<i>.<field>`; list unchanged after any 400 (atomic). 250 rows accepted.
- **Assertions DB:** row count unchanged after each 400.
- **Cov:** `test_country_prices.py`, `test_country_prices_api.py` (most). Agent 2 may run pytest instead of re-driving all variants.

#### F06-TC-008: Subscription price follows the student's country; stale currency is refused
- **Pri:** P1. **Role:** admin. **Switches:** `country_pricing`, `invoices`. **Tag:** REAL.
- **Data:** P1 country rows SA=5000 SAR; students EG (no row) and SA.
- **Steps:**
  1. GET `/catalogue/packages/<P1>/price/?student=<SA>` and `<EG>`.
  2. POST `/subscriptions/` `{"student":<SA>,"course":C1,"teacher":<qa-teacher>,"package":P1,"starts_on":"2026-10-19","slots":[{"weekdays":[0,3],"start_time":"18:00"}]}` and the same for EG.
  3. POST again for the EG student with `"currency":"SAR"` (stale), then with an explicit `"price_minor":120000,"currency":"EGP"`.
  4. Turn `country_pricing` off, create for SA.
- **Expected:** SA price 5000 SAR, EG price 150000 EGP. Subscriptions store the resolved amount and currency. Stale currency: 400 `catalogue.price_currency_changed` on `price_minor`, no row. Explicit price wins (120000 EGP). With the switch off the SA student pays the package's 150000 EGP and the `price/` endpoint behaves the same (no feature gate, per docs).
- **Assertions DB (`scheduling_subscription`):** `price_minor`, `currency` per row; `sessions_total`=8; `session_minutes`=45; `term_ends_on` = start + 1 month - 1 day = 2026-11-18. With `invoices`+`auto_invoice_on_subscription` on: one `billing_invoice` per subscription whose total equals `price_minor` in the same currency (no float rounding).
- **Cov:** `scheduling/tests/test_country_pricing.py`, `test_bundles_country_pricing.py`. New: the stale-currency and switch-off paths via API.
- **Cleanup:** cancel + delete these subscriptions (delete is refused when invoiced, then void the invoice via billing API or cancel only).

#### F06-TC-009: Package edits never reach existing subscriptions; renewal re-prices
- **Pri:** P1. **Role:** admin. **Tag:** REAL.
- **Steps:** with a subscription on P1 (price 150000): PATCH P1 `{"price_minor":200000,"session_minutes":60,"duration_value":2}`. GET the subscription. POST `/subscriptions/<id>/renew/` `{}`. Then change the SA student's country row currency, renew his subscription without `price_minor`.
- **Expected:** old subscription keeps 150000 / 45 min / 1 month. Renewal copies the NEW package numbers (60 min, 2 months, `sessions_total` 16) and the price **carries over** (150000, per P4-10) while the currency is unchanged; when the resolved currency changed, the renewal takes the new package/country price in the new currency.
- **Assertions DB:** `scheduling_subscription` old vs new row (`renewed_from_id`), `duration_value`, `price_minor`, `currency`.
- **Cov:** `test_renewal.py` (carried price), `test_country_pricing.py`. Combined here as one money workflow.

## C. Subscription lifecycle

#### F06-TC-010: Create subscription end to end (slots, sessions, UTC storage, Cairo DST in the horizon)
- **Pri:** P1. **Role:** admin. **Tag:** REAL.
- **Steps:** set academy horizon 14 days (`PATCH /academy/settings/ {"generation_horizon_days":14}`, record before). POST `/subscriptions/` with slots `[{"weekdays":[0],"start_time":"18:00"}]` starting 2026-10-19 (Mon) for QA6 Student 1; GET `/subscriptions/<id>/sessions/`; then `POST /schedule/generate/ {"from":"2026-10-19","to":"2026-11-30","subscription":<id>}`.
- **Expected:** Monday sessions at 18:00 Cairo. Egypt ends DST on the last Thursday of October (2026-10-29 24:00): the Oct 19 and 26 sessions are 15:00Z (UTC+3), the Nov 2 session is 16:00Z (UTC+2). The wall-clock time stays 18:00 in the academy zone. Compute the expectation with `python -c "from zoneinfo import ZoneInfo;..."`, not by hand.
- **Assertions DB (`scheduling_session`):** `starts_at` (timestamptz, UTC), `occurs_on` is the local date, `minutes`=45, `generated=true`, `slot_id` set, `teacher_id`, `student_id`; unique (slot, occurs_on) (re-running generate adds 0: `skipped_existing` > 0). Sessions only within `starts_on`..`term_ends_on`+grace.
- **Cov:** `test_generation.py`, `test_dates.py` (zone maths on America/New_York). Cairo and the API are new.

#### F06-TC-011: DST spring-forward gap and autumn fold on a slot
- **Pri:** P1. **Role:** admin. **Tag:** REAL.
- **Steps:** subscription starting 2027-04-01 with slots Friday 00:30 and Thursday 23:30 (Egypt: DST starts the last Friday of April 2027-04-30 at 00:00, clocks 00:00→01:00). `POST /schedule/generate/ {"from":"2027-04-20","to":"2027-05-10","subscription":<id>}`. Repeat with Friday 00:30 on 2026-10-30 (the autumn change: 24:00 Thursday back to 23:00).
- **Expected:** a time inside the gap is read with the pre-change offset and lands one hour later (00:30 → 01:30 local, `starts_at`=2027-04-29T22:30Z), per `dates.to_utc` docstring (fold=0); an ambiguous autumn time takes the first occurrence. No exception, no missing or duplicated date, no 500.
- **Assertions DB:** one session per slot per date, `starts_at` equals `zoneinfo` result, `occurs_on` is the local calendar day.
- **Cov:** `test_dates.py` covers New_York gap/fold only. Provider: REAL.
- **Cleanup:** cancel/delete the test subscription.

#### F06-TC-012: Timezone change does not move sessions (verify STATE issue)
- **Pri:** P1. **Role:** admin. **Tag:** REAL. **Suspected defect S1.**
- **Steps:** with TC-010's subscription (Cairo, Monday 18:00, sessions already generated for the next 14 days) PATCH `/academy/settings/ {"timezone":"America/New_York"}` (record before). Without any other action GET sessions; then run `run_lifecycle` (Setup) and `POST /schedule/generate/` for the range; GET sessions. Restore `Africa/Cairo`.
- **Expected (documented intent):** the slot is "wall clock of the academy", so after the change future untouched sessions should be at 18:00 New_York. **Code reading:** nothing recalculates `starts_at`, and `generate` skips existing (slot, date), so existing sessions stay at the old UTC instant (now 11:00/12:00 New_York) while newly generated ones use the new zone: one schedule with two different local times. Record the exact observed behaviour. Pass criterion for the product is that the owner is warned or sessions are re-anchored; otherwise file a defect (severity by Agent 2, likely P2).
- **Assertions DB:** `starts_at` values before/after for the same slot; `academy_academysettings.timezone`.
- **Cov:** `test_generation.py:117,186` change the zone before creating sessions only.

#### F06-TC-013: Pause: freeze days, overlap, status sync and the term growing
- **Pri:** P1. **Role:** admin. **Tag:** REAL.
- **Steps:** on a P1 subscription (freeze 7): POST `/subscriptions/<id>/pauses/` `{"from_date":"2026-10-20","to_date":"2026-10-26"}` (7 days); again overlapping `{"from_date":"2026-10-25","to_date":"2026-10-27"}`; a further 1-day pause (freeze exhausted); `from_date` before `starts_on`; `from_date` > `to_date`. Then a pause that covers today, `POST /pauses/<id>/end/`, `DELETE /pauses/<id>/` on a future pause and on a started one.
- **Expected:** first 201; overlap 409 `scheduling.pause_overlaps`; extra day 409 `scheduling.freeze_days_exceeded`; bad dates 400. Untouched sessions inside the pause are deleted; the derived `ends_on` grows by the paused days; `status=paused` only while a pause covers today; after `end` the end moves to yesterday; delete of a started pause is refused.
- **Assertions DB:** `scheduling_subscriptionpause` rows; `scheduling_session` rows inside the range gone; `status`.
- **Cov:** `test_subscriptions.py`, `test_rules.py`. Boundary cases (7 vs 8 days, term end) added.

#### F06-TC-014: Renew, cancel, archive (owner workflow, UI smoke)
- **Pri:** P1. **Role:** admin. **Switches:** `subscription_archive`. **Tag:** REAL. **UI smoke #2.**
- **Steps:** UI `/app/scheduling/subscriptions/<id>`: Renew (dialog, defaults), then Cancel the renewal, then Renew again, then archive the old expired one. API for the DB checks: POST `/subscriptions/<id>/renew/` twice; POST `/subscriptions/<id>/cancel/`; POST `/subscriptions/<id>/archive/` on a live and on an ended one; DELETE `/subscriptions/<id>/archive/`.
- **Expected:** renewal starts the day after `ends_on` (or today if later), slots copy, old status stays active until the renewal starts; second renew 409 `scheduling.already_renewed` unless the renewal was cancelled (then OK and `renewed_from` released). Cancel: status `cancelled`, untouched regular future sessions deleted, marked ones kept. Archive of a live subscription refused; archived one refuses renew (409 `scheduling.archived`) until restored.
- **Assertions DB:** `renewed_from_id` chain (one-to-one), `status`, `expired_at`, `archived_at/by`, `scheduling_session` counts.
- **Cov:** `test_renewal.py`, `test_archive_*.py`, `dashboard/e2e/b2-archive.spec.ts`.

#### F06-TC-015: Renewal must not duplicate a session (verify STATE issue)
- **Pri:** P1. **Role:** admin. **Tag:** REAL. **Suspected defect S3.**
- **Steps:** subscription A (slot Mon 18:00, started 2026-10-12 so Oct 19 exists). Mark attendance on the Oct 19 session (completed) via `POST /sessions/<id>/attendance/` (see sessions API, one marked session). Then `POST /subscriptions/<A>/renew/ {"starts_on":"2026-10-19"}` (an early renewal starting on a date that already has a marked session). Also test `starts_on` = today, and a renewal with a different weekday slot set.
- **Expected:** exactly one session per (student, date, time). Code reading: renew deletes only *untouched* old sessions from `starts_on`; a marked old session on/after that date stays and the renewal generates its own session for the same date (different slot row, so the unique (slot, date) does not stop it): a duplicate lesson for the same student/teacher/time. Verify and record; also verify the old sub's generation stops the day before (`generation_last_day`).
- **Assertions DB:** `select occurs_on, starts_at, student_id, teacher_id, count(*) from academy_qa.scheduling_session where status<>'cancelled' group by 1,2,3,4 having count(*)>1;`.
- **Cov:** `test_renewal.py` does not mark a session in the overlap.
- **Correction (Agent 3, fix cycle 1, 2026-10-19):** the duplicate is the documented design, not a defect. B2b spec §10 (`2026-10-03-b2b-times-postponement-design.md`): a marked old lesson on/after the renewal's start "is kept, and the renewal also generates that date (as B2a does for marked generated sessions)"; `test_renewal.py::test_old_untouched_sessions_from_the_new_start_are_removed` marks 8 June and asserts both the old and the renewal session, and `test_today.py::test_a_session_always_shows_even_after_its_renewal_took_over` asserts both board rows (the Cov line above is wrong). **Expected now:** both sessions exist, and the renew answer lists the overlap in `conflicts` (P4-9, via the ETQAN-QA-042 fix). Changing the design (skip the date) is an owner decision: see coverage-gaps Proposals.

#### F06-TC-016: Concurrent renewals produce one renewal
- **Pri:** P1. **Role:** admin x2. **Tag:** REAL.
- **Steps:** fire two `POST /subscriptions/<id>/renew/` `{}` in parallel (`& wait`), twice with different ids, from two sessions (admin and staff-with-codes).
- **Expected:** one 201 and one 409 `scheduling.already_renewed`; never two rows with the same `renewed_from_id`, no 500.
- **Assertions DB:** `select renewed_from_id,count(*) from scheduling_subscription group by 1 having count(*)>1;` empty.
- **Cov:** no concurrency test (test_renewal.py single-threaded).

#### F06-TC-017: Deactivated teacher/student keep getting sessions (verify STATE issue)
- **Pri:** P1. **Role:** admin. **Tag:** REAL. **Suspected defect S2.**
- **Steps:** subscription with QA6 Teacher B and QA6 Student 2 (slot daily-ish). `POST /people/teachers/<B>/deactivate/` and `POST /people/students/<s2>/deactivate/`. GET their sessions. `run_lifecycle` + `POST /schedule/generate/` for the next 14 days (after deleting a future session so there is something to regenerate). Try creating a new subscription with the deactivated teacher/student. Reactivate afterwards.
- **Expected (code reading):** `identity.deactivate` only ends login sessions; `generation._lock_live` filters on subscription status only, so new sessions are still generated for the inactive teacher/student and appear on the Today board. New subscriptions with them are refused 400 ("Choose an active teacher/student"). Record what the owner sees; product intent per docs: an inactive person should not get new sessions (or the owner must be told).
- **Assertions DB:** `scheduling_session` rows with `teacher_id`=B created after the deactivation timestamp; `identity_user.is_active=false`.
- **Cov:** none.

## D. Conflicts, teacher availability, trials

#### F06-TC-018: Teacher and student conflicts (warned, never blocked)
- **Pri:** P1. **Role:** admin. **Tag:** REAL.
- **Steps:** two subscriptions with the same teacher, same Monday 18:00 slot (different students), then a subscription for the *same student* with another teacher at the same time. `POST /schedule/generate/` for the range and read `conflicts` in the response. Add a manual session overlapping by 10 minutes. Group case: see TC-024.
- **Expected:** creates succeed; the generate/create response lists teacher conflicts (pairs). Back-to-back sessions (end = next start) are not a conflict. **Open question for Agent 2:** the code only checks the teacher; a student double-booked with two teachers is not reported (record, S5).
- **Assertions DB:** both sessions exist; no unique violation; `conflicts` pairs match overlapping `starts_at`/`minutes`.
- **Cov:** `test_generation.py` (teacher conflicts), `test_bundles_clashes.py`.

#### F06-TC-019: Teacher availability and course-teacher rules
- **Pri:** P2. **Role:** teacher, admin. **Switches:** `teacher_availability`. **Tag:** REAL.
- **Steps:** A teacher PUT `/schedule/availability/ {"windows":[{"weekday":0,"start_time":"09:00","end_time":"12:00"}]}`; end <= start; 51 windows; teacher B tries PUT `/schedule/availability/<teacherA>/`; admin PUT it. Create a subscription at Monday 18:00 (outside the window) and with a teacher who does not teach the course.
- **Expected:** window saved; invalid 400; teacher cannot edit another teacher (403/404); admin can. Outside-window subscription is created with a warning in the payload (never blocked); teacher not on the course 400 field `teacher`. Switch off: warning absent.
- **Assertions DB:** `scheduling_teacheravailability` rows replaced atomically (old rows gone).
- **Cov:** `test_api_availability.py`, `test_availability_services.py`.

#### F06-TC-020: Trial request to subscription conversion
- **Pri:** P1. **Role:** admin. **Switches:** `trial_sessions`. **Tag:** REAL.
- **Steps:** POST `/trials/` `{"student":<s3>,"course":C1,"source":"api","minutes":30,"heard_from":<value from TrialRequest.HeardFrom>}`; `GET /trials/suggest/?course=C1&occurs_on=2026-10-26&start_time=16:00&minutes=30`; `POST /trials/<id>/schedule/ {"teacher_id":<qa-teacher>,"occurs_on":"2026-10-26","start_time":"16:00"}` twice (second is refused); complete the trial session (attendance API); `POST /subscriptions/ {... ,"trial_id":<id>}` as admin, as staff without `trial_session.update`, and again with the same trial. DELETE the converted trial.
- **Expected:** trial `accepted` after scheduling; second schedule 4xx; conversion only with a completed session and the same student (else 4xx); staff without the code 403; second conversion refused; delete of converted trial refused; teacher not on the course refused. Trial session has no subscription/slot and `kind='trial'`.
- **Assertions DB:** `scheduling_trialrequest.converted_to_id`; `scheduling_session` rows `kind='trial'` (at most 1 live).
- **Cov:** `test_trials_*.py`, `test_api_trials*.py`, `b2-trials.spec.ts`. Kept because conversion moves money (invoice).

## E. Groups, bundles, schedules

#### F06-TC-021: Multi-course bundle: all-or-nothing, money per member
- **Pri:** P1. **Role:** admin. **Switches:** `multi_course_subscriptions`. **Tag:** REAL.
- **Steps:** POST `/bundles/multi-course/ {"student_id":<s1>,"starts_on":"2026-10-19","rows":[{"course":C1,"teacher":<A>,"package":P1,"slots":[{"weekdays":[0],"start_time":"17:00"}]},{"course":C2,"teacher":<A>,"package":P2,"price_minor":0}]}`; then one with a bad second row (inactive package); one row only; the same course twice. Renew / pause / cancel the bundle; one member marked so cancel refuses.
- **Expected:** 201 with two members and per-member price (150000, 0); bad row: 400 keyed `rows.1.package`, **no** subscription and no invoice created for row 0 (rollback). One row / duplicate course 400. Bundle actions all-or-nothing, error names the refusing member.
- **Assertions DB:** `scheduling_subscriptionbundle` kind/owner check; member `bundle_id`; counts of subscriptions unchanged after the failures; invoices only for committed members.
- **Cov:** `test_bundles_create.py`, `test_bundles_actions.py`, `b2-bundles.spec.ts`.

#### F06-TC-022: Family bundle (payer, distinct students) and feature dependencies
- **Pri:** P1. **Role:** admin, parent. **Switches:** `family_subscriptions` + `families`. **Tag:** REAL.
- **Steps:** POST `/bundles/family/ {"family_id":<F>,"starts_on":"2026-10-19","rows":[{"student":<s1>,"course":C1,"teacher":<A>,"package":P1},{"student":<s2>,"course":C1,"teacher":<A>,"package":P1}]}`; same student twice; a student outside the family; inactive family. Parent GET `/subscriptions/` and `/bundles/<id>/`. Switch `family_subscriptions` off.
- **Expected:** 201, each member priced for its own student's country; invalid rows 400 `rows.N...`; parent sees only own children's subscriptions via `/subscriptions/` and gets 404 on `/bundles/*` (office only); off-switch 404/403 on create.
- **Assertions DB:** members belong to the family's students; `owner` check constraint (family set, student/study_group null).
- **Cov:** `test_bundles_*`. Parent visibility and money-per-student are added.

#### F06-TC-023: Study group + group bundle, add/remove member (UI smoke)
- **Pri:** P1. **Role:** admin. **Switches:** `study_groups`, `group_subscriptions`. **Tag:** REAL. **UI smoke #3.**
- **Steps:** UI `/app/people/groups`: create group "QA6 Group" with students s1,s2. API: POST `/groups/` the same; second group with s1 (already in one); POST `/bundles/group/ {"group_id":<g>,"starts_on":"2026-10-19","rows":[{"course":C1,"teacher":<A>,"package":P1,"slots":[{"weekdays":[2],"start_time":"19:00"}]}]}`; POST `/bundles/<b>/members/ {"student_id":<s3>,"starts_on":"2026-10-19"}`; DELETE `/bundles/<b>/members/<s3>/`; DELETE `/groups/<g>`.
- **Expected:** student in at most one group (second 400); one subscription per active member, all one currency (a member whose country price differs in currency is refused or the whole create fails, per D-5: record); new member copies the newest member; remove cancels his live subscriptions only; deleting a group with bundles refused. Group siblings (same teacher/time) are not reported as a clash.
- **Assertions DB:** `scheduling_studygroupmember` one-to-one on student; member subscriptions share bundle id and currency.
- **Cov:** `test_api_groups.py`, `test_groups_*.py`, `test_bundles_members.py`, `b2-bundles.spec.ts`.

#### F06-TC-024: Weekly schedules: stop, delete, restore, bulk teacher change, substitution
- **Pri:** P1. **Role:** admin. **Switches:** `weekly_schedules`. **Tag:** REAL.
- **Steps:** POST `/schedules/stop/ {"subscription_ids":[a]}`; run lifecycle; POST `/schedules/delete/`, `/schedules/restore/`, `/schedules/activate/`; `/schedules/teacher/ {"subscription_ids":[a,b],"teacher_id":<B>}` with b having a marked session; `/schedules/substitutions/ {"subscription_ids":[a],"teacher_id":<C>,"from_date":"2026-10-26","to_date":"2026-11-02"}` plus an overlapping one and a 400-day range; `DELETE /schedules/substitutions/<id>/`.
- **Expected:** stopped: untouched future sessions deleted, nothing new generated even after the job; restore returns it active; activate refills the horizon; bulk change is all-or-nothing (b refused so a unchanged); substitution moves untouched sessions in range to C with `substitute_for_id` set, overlaps refused, range > 366 days 400, removal returns them to the regular teacher; marked sessions untouched.
- **Assertions DB:** `schedule_status`, `scheduling_teachersubstitution`, `scheduling_session.teacher_id/substitute_for_id`.
- **Cov:** `test_schedules_*.py`, `test_api_schedules.py`, `b2-schedules.spec.ts`.

## F. Lifecycle job, permissions and isolation

#### F06-TC-025: Hourly job: expiry, grace, pause sync, idempotent horizon
- **Pri:** P1. **Role:** system. **Tag:** REAL (Celery beat is not asserted; the function is called).
- **Steps:** create a subscription with `starts_on` 40 days ago, 1 month, `renewal_grace_days`=7 (default) so it is past grace; one inside grace; one with a live renewal that started. Run `run_lifecycle` twice.
- **Expected:** the past-grace subscription becomes `expired` with `expired_at` set and its untouched future sessions deleted; the in-grace one stays active; the old subscription expires once the renewal starts. The second run changes nothing (created=0, expired=0). Marked sessions never deleted.
- **Assertions DB:** `status`, `expired_at`, session counts before/after each run.
- **Cov:** `test_lifecycle.py`, `test_rules.py`.

#### F06-TC-026: Subscription permission matrix and own-row scope
- **Pri:** P1. **Role:** all. **Tag:** REAL.
- **Steps:** per role (admin, staff-with-codes, staff-no-codes, supervisor, teacher, student, parent, anonymous): GET `/subscriptions/`, GET `/subscriptions/<id>/` (own and not own), `?format=csv`, POST `/subscriptions/`, PATCH, DELETE, renew, cancel, `POST /pauses`, `POST /schedule/generate/`, `GET /schedule/today/`, `GET /bundles/`, `/trials/`, `/schedules/`.
- **Expected:** office per code; staff-no-codes 403; teacher sees only subscriptions they teach (404 for others); student only own; parent only their child's; CSV is office only (403 for others); writes 403 for non-office; bundles/trials/schedules are 404 for student and parent. Anonymous 401/403. Supervisor per its codes (no extra access).
- **Assertions:** list ids equal the DB set for that person; no field leaks (`price_minor` of others); no DB change from any refused write.
- **Cov:** `test_staff_scope.py`, `test_api_subscriptions.py`.

#### F06-TC-027: Subscription and scheduling cross-academy isolation
- **Pri:** P1. **Role:** admin of each. **Tag:** REAL.
- **Steps:** create an equivalent subscription/bundle/group/trial in qaother. From qa admin and from qaother admin: GET/PATCH/DELETE/renew/cancel/pauses/slots/archive on the other academy's ids; POST a subscription in qa using a qaother student/course/teacher/package id; `POST /schedule/generate/ {"subscription":<other id>}`; `GET /schedule/today/` in each.
- **Expected:** 404 for foreign ids, 400 "Choose an active ..." for foreign student/course/teacher/package ids (no leakage of names); lists and the Today board show only the own academy; generate with a foreign id 404.
- **Assertions DB:** both schemas' counts of `scheduling_subscription`/`scheduling_session` unchanged by the cross attempts; the job run in one tenant never writes into the other schema.
- **Cleanup:** remove qaother test rows.

#### F06-TC-028: Delete subscription guards and slot rules
- **Pri:** P2. **Role:** admin. **Tag:** REAL.
- **Steps:** DELETE a fresh subscription with no marked sessions (and one invoiced, one renewed, one with a marked session). `POST /subscriptions/<id>/slots/` duplicate weekday+time, `weekdays` empty/7, `minutes` 14/241, bad URL; `PATCH /slots/<id>/ {"start_time":...}`; `DELETE /slots/<id>/` on a slot with sessions; `PATCH /subscriptions/<id>/ {"starts_on":...}` after marking; `{"price_minor":-1}`.
- **Expected:** guarded deletes 409 (`billing.subscription_invoiced`, already renewed, `scheduling.has_marked_sessions`); clean one 204 and its sessions/bundle go; duplicate slot 400; slot with sessions 409 `scheduling.slot_has_sessions` (deactivate works); slot edits replace only untouched sessions; negative price 400.
- **Assertions DB:** no orphan `scheduling_session`/`scheduling_scheduleslot` rows after delete.
- **Cov:** `test_subscriptions.py`, `test_actions.py`.

---

## Suspected defects from code reading (for Agent 2)
- **S1** (TC-012): changing `academy.timezone` re-anchors nothing: `AcademySettings` update has no hook, existing sessions keep their old UTC instant while newly generated ones use the new zone, so one weekly slot shows two local times. No warning in the API.
- **S2** (TC-017): `identity.deactivate` only ends login sessions ("the caller ends them"); `generation._lock_live` filters on subscription status/archive/schedule only, so a deactivated teacher or student keeps getting sessions (and the Today board rows). `_teacher`/`_student` guards apply only to new subscriptions.
- **S3** (TC-015): `renew_subscription` deletes only *untouched* old sessions from the renewal start; a marked old session on/after `starts_on` stays and the renewal generates a second session for the same date (different `slot_id`, so the unique constraint does not catch it). Duplicate lesson, possibly a duplicate paid session.
- **S4** (TC-016): `previous` is read after the lock, but two renewals race on `select_for_update` of the *old* row only: verify no second renewal slips through when the first was cancelled in between (`renewed_from` is cleared on the cancelled one).
- **S5** (TC-018): conflicts are computed per teacher only. The same student booked at the same time with two teachers is never reported.
- **S6** (TC-008/012): `price/?student=` ignores the `country_pricing` switch by design (documented), but a subscription created while the switch is off stores the package currency; turning it on later and renewing re-prices only if the currency differs: confirm the carried-over price is intended when the country row is cheaper/dearer in the same currency.
- **S7** (TC-011): a gap time (00:30 on the spring-forward night) lands at 01:30, i.e. possibly inside the *next* slot of the same teacher the same night; conflicts are computed from UTC so this should show up as a conflict: verify.
- **S8** (TC-009): package `currency` can be PATCHed while country rows remain in other currencies and while subscriptions exist; renewal of a carried price keeps the old amount in the old currency only if `price.currency == subscription.currency`, which can silently swap an EGP 1500 subscription to a USD price: check the renewal response and invoice.

## Coverage summary
- Total 28 cases: **P1 = 25** (001-006, 008-018, 020-027), **P2 = 3** (007, 019, 028). UI smoke: 006, 014, 023.
- Provider tags: all REAL (local stack, mailpit). No SIMULATED/FAKE needed. Online payment of invoices is out of scope (F-billing).

---

## Agent 2 additions and spec corrections (2026-10-19)
- **Date shift:** the stack date was 2026-10-19 (Monday), not 2026-10-18; D1 = today. Expectations were unaffected.
- **TC-002:** `"XXX"`/`"ZZZ"` are accepted as currencies by design: the B3d spec (`2026-10-05-b3d-countries-currencies-design.md`
  line 69) and the model define currency as `^[A-Z]{3}$`, not an ISO list. `"1500"` (a numeric string) is coerced by DRF and stored as
  the integer 1500, so no float is stored. Expectation corrected; not a defect.
- **TC-003/006/007:** `PUT <P>/country-prices/` takes a bare JSON list `[{country,price_minor,currency}]`; `{"rows":[...]}` is a 400
  "Send the list of country prices.". Error keys are `rows.<i>.<field>` as specified.
- **TC-004:** ids collide between schemas (package 1 exists in both), so a cross-id request hits the caller's own row. Isolation
  is proven by content (`qa GET /packages/1/` returns qa's "F03 Pack") and by the other schema's unchanged `max(updated_at)`.
- **TC-013:** `POST /subscriptions/<id>/pauses/` returns the subscription, not the pause. A pause that started today and is ended
  today is removed, so the end does not move to "yesterday".
- **TC-022:** "same student twice" is allowed by design when the courses differ (B2f spec F-2: "a student may have several rows,
  student + course distinct"); student + same course is refused 400 `rows.1.course`. Family payer must be a family student or their
  parent (the qa parent isn't a guardian of the QA6 students, so the payer was QA6 Student 1).
- **S4** refuted (TC-016): cancelling the renewal clears `renewed_from`, and the next parallel pair again yields one 201 + one 409.
- **S5** not a defect by the docs (conflicts are per teacher); a related real gap is filed as ETQAN-QA-042.
- **S6/S8** match the documented intent (B3d D-4 / P4-10: the price carries over unless the resolved currency changed; a changed
  currency takes the new resolved price, and the renewal invoice follows it). Not filed.
- **S7** refuted: the spring-forward gap session (00:30 → 22:30Z = 01:30 local) that now overlaps the 01:15 slot is listed in `conflicts`.
- **Added TC-029 (P1):** a pause that pushes `ends_on` past an existing renewal's start must not generate overlapping old-term sessions.
- Cancelled renewals keep their unpaid invoice: documented (`billing.md`: only `void_invoice` voids). Not filed.

## Results (Agent 2, 2026-10-19)
| Case | Result | Tag | Evidence (`qa/evidence/F06/`) |
|---|---|---|---|
| TC-001 | PASS | REAL | tc001-002.txt |
| TC-002 | PASS (spec corrected: XXX/ZZZ by design) | REAL | tc001-002.txt |
| TC-003 | PASS | REAL | tc003.txt |
| TC-004 | PASS | REAL | tc004.txt |
| TC-005 | PASS | REAL | tc005-006-007.txt |
| TC-006 | PASS (API + UI smoke) | REAL | tc005-006-007.txt, pw/tc006-*.{png,json}, pw-run3.txt |
| TC-007 | PASS | REAL | tc005-006-007.txt |
| TC-008 | PASS (invoices 5000 SAR / 150000 / 120000 / 150000 EGP, bigint) | REAL | tc008.txt |
| TC-009 | PASS (S8 as documented) | REAL | tc009.txt |
| TC-010 | PASS (15:00Z → 16:00Z across 2026-10-29) | REAL | tc010.txt |
| TC-011 | PASS (gap 22:30Z, fold first occurrence; S7 refuted) | REAL | tc011.txt |
| TC-012 | **FAIL** → ETQAN-QA-041 (S1 confirmed) | REAL | tc012.txt |
| TC-013 | PASS | REAL | tc013.txt |
| TC-014 | PASS (API + UI smoke) | REAL | pw/tc014-*.{png,json}, pw-run3.txt, tc016.txt |
| TC-015 | **FAIL** → ETQAN-QA-039 (S3 confirmed) | REAL | tc015.txt |
| TC-016 | PASS (S4 refuted) | REAL | tc016.txt |
| TC-017 | **FAIL** → ETQAN-QA-040 (S2 confirmed) | REAL | tc017.txt |
| TC-018 | **FAIL** → ETQAN-QA-042 (create/renew report no conflicts; S5 by design) | REAL | tc018.txt |
| TC-019 | PASS | REAL | tc019.txt |
| TC-020 | PASS | REAL | tc020.txt |
| TC-021 | PASS (rollback, all-or-nothing pause with `member_id`) | REAL | tc021-022.txt, tc021b-023.txt |
| TC-022 | PASS (spec corrected) | REAL | tc021-022.txt, tc021b-023.txt |
| TC-023 | PASS (API + UI smoke; mixed currency D-5) | REAL | tc021b-023.txt, pw/tc023-*.{png,json} |
| TC-024 | PASS | REAL | tc024.txt |
| TC-025 | PASS | REAL | tc025.txt |
| TC-026 | PASS | REAL | tc026.txt |
| TC-027 | PASS | REAL | tc027.txt |
| TC-028 | PASS | REAL | tc028.txt |
| TC-029 | PASS (old term stops 11-16, renewal from 11-19, no duplicate) | REAL | tc013.txt (t13b section) |

Totals: 29 executed, 25 PASS, 4 FAIL (all P2), 0 BLOCKED. Baseline `pytest etqan/catalogue etqan/scheduling`: 1451 passed
(`pytest-catalogue-scheduling.txt`). Playwright `e2e/qa/f06-catalogue-scheduling.spec.ts`: 3/3 (run 3; runs 1–2 failed on test
locators only, fixed). Cleanup: `cleanup.txt`.
