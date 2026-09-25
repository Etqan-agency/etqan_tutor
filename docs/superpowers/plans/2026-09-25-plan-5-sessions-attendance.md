# Plan 5 — Sessions, Attendance & Reports — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teachers mark student and teacher attendance on their own sessions once they start and write a staff-only report for each completed one; admins see, filter, export, bulk-mark, cancel and restore every session and see which completed sessions still lack a report; students and parents see their sessions (with the join link), their attendance and each subscription's progress. Marking attendance makes Plan 4's `sessions_used`, extras and carry-over real, under one counting rule with two academy switches.

**Architecture:** Everything stays in `etqan.scheduling` (P5-1). Two new service modules sit beside Plan 4's: `services/attendance.py` (the start-time gate, mark, cancel, restore, bulk; every write locks the session row) and `services/reports.py` (the report-access rule, write/read, the missing-reports query). The counting rule replaces Plan 4's `CONSUMING` placeholder inside `services/rules.py`, where `derive` already lives, so every number follows one implementation. New endpoints live in `api/session_views.py` under `/api/v1/sessions/…` and `/api/v1/reports/missing/`; payloads take the signed-in `viewer` and ask the services what that viewer may see. The dashboard adds admin Sessions, Session and Missing-reports pages to the Scheduling group, a Teaching group for teachers and a My-learning group for students and parents, and role-specific panels on Home.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next, `Intl` for time zones; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-09-25-sessions-attendance-design.md` (Phase B0 milestone 5 of `2026-09-24-parity-roadmap-design.md`; builds on `2026-09-24-subscriptions-scheduling-design.md` as amended — `etqan.scheduling`, untouched sessions, derived values, carry-over — and on Plan 3, `2026-09-24-people-catalogue-design.md` — roles, `scope_for`, CSV). Where this plan fills a gap in the spec, the Decisions below say so.

**Verified:** the code in Tasks 1–13 was applied in order to copies of `backend@201ee1a` and `dashboard@a56a4a3` (the current `main` of each); after every task its format, lint, import-contract, type, test and coverage commands passed (backend 780 → 872 tests, coverage 97.5%; dashboard 440 → 491 tests, lines 90.1%, branches 82.8%, functions 78.7%). The Task 14 spec passed through Caddy against Django (`config.settings.local`, file email backend) and the Vite preview on a freshly migrated and seeded database, as the CI `e2e` job runs them, together with every other spec except `academy-sites.spec.ts` (it needs the marketing server, which that run did not start). Migrations are generated in Task 1 with `makemigrations`, so only their timestamps will differ.

## Global Constraints

- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), meta repo (trunk `master`). Feature branch `feat/sessions-attendance` in every touched repo. The meta branch already exists; create it in `backend/` (Task 1) and `dashboard/` (Task 9) before their first task: `git -C backend switch -c feat/sessions-attendance`, same for `dashboard`. Nothing is merged without the user's approval. After merge, bump the submodule pointers in meta.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Backend commands run from `backend/` with the virtualenv `backend/.venv` and this environment exported once per shell:
  `export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan CELERY_BROKER_URL=redis://localhost:56379/0 DJANGO_SECRET_KEY=test-secret DJANGO_READ_DOT_ENV_FILE=False DJANGO_TENANT_BASE_DOMAIN=etqan.localhost`
  Tests: `.venv/bin/pytest …` (add `--create-db` once after Task 1, which adds migrations). Format: `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`. Verify: `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`. Watch `PLR0913`: keyword-only signatures that mirror an API body or query carry `# noqa: PLR0913 -- <reason>`, as Plan 4's services do.
- Dashboard commands run from `dashboard/` through `npx pnpm@10`. Format: `npx pnpm@10 exec biome check --write src`. Verify: `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`. `pnpm lint` = `biome ci . && node scripts/check-colors.mjs`: no hex colour literals and no Tailwind palette utilities anywhere in `src/`, comments included; semantic tokens only. `tsc` has `noUnusedLocals`/`noUnusedParameters`. New route files are picked up by the TanStack Router plugin; regenerate `src/routeTree.gen.ts` with `npx pnpm@10 exec vite build` before `tsc`.
- Coverage gates: backend ≥ 80% (`pytest --cov=etqan`); dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`; academies `demo` (`admin@demo.test`, timezone UTC) and `other` (`admin@other.test`).
- Tenancy: no new app; everything is in `etqan.scheduling` (TENANT_APPS). Migrate with `migrate_schemas`. No background job and no user-facing URL is added.
- Business logic lives in `etqan/scheduling/services/`; views parse, call one service, re-read and arrange a payload; payloads call services and never restate a rule. Other apps import only `etqan.scheduling.services`; scheduling reaches identity, catalogue and academy only through their `services` (`lint-imports` enforces both). Visibility flags are keyword-only with no default: `session_row(session, *, viewer)`, as Plan 4's `is_admin`.
- All API routes are under `/api/v1/`. Stored instants (`Session.starts_at`, `marked_at`, `cancelled_at`) are UTC; `occurs_on` and the `from`/`to` filters are the academy's calendar (`AcademySettings.timezone`).
- Spec values: session status `scheduled · completed · cancelled`; attendance `not_set · present · absent · excused`; report scales 1–5 (5 excellent, 4 good, 3 average, 2 below average, 1 poor) plus optional notes; `absent_consumes_session` default `true`, `excused_consumes_session` default `false`; bulk `action` `present · absent · cancel`, at most 200 ids, `reason` required for cancel; a report is missing once a completed session ended more than 24 hours ago.
- The counting rule (spec §4.2), verbatim: a session uses up one of its subscription's sessions when `status = completed`, `teacher_attendance ≠ absent`, and `student_attendance` is `present`, or `absent` with `absent_consumes_session` on, or `excused` with `excused_consumes_session` on. It lives only in `rules.consuming`, and the switches are read live.
- Errors: rule refusals are `409 {"detail", "code"}` with `scheduling.not_started`, `scheduling.session_cancelled`, `scheduling.not_completed` or `scheduling.not_allowed_in_status`; field problems are `400 {"<field>": [...]}`; out-of-scope objects are `404`; a role that may not use a route gets `403`.
- Access (spec §4.6): admin everything; a teacher reads the sessions they teach (`Session.teacher`), marks attendance and reads/writes reports on those only, and sees their own missing reports; a student reads their own sessions, a parent their children's; cancel, restore, bulk and CSV are admin-only. `scope_for(user, queryset)` is the one scoping function.
- Every write answers with a fresh read of what it changed. Views define only the methods the spec lists: PUT exists only on `sessions/<id>/report/`.
- Lists `select_related` what a row shows and annotate `has_report`; the session list and the missing-reports list have query-count tests.
- Every dashboard string exists in `src/locales/en/common.json` and `src/locales/ar/common.json` with no English literal in components; zod messages are i18n keys rendered through `useFieldError`; 409 codes render as `errors.<code>` through `applyServerErrors`/`errorText`. Required fields render `*` inside the `<label>`, so tests query `getByLabelText(/^Reason/)`; where one accessible name is a substring of another, match exactly. Screens work RTL and at phone width. Reuse `Pager`, `clean`/`csvUrl`/`Paginated`, `applyServerErrors`/`errorText`/`codeKey`, `useFieldError`, `wallTime`/`formatDay`; no copies of generic helpers inside a feature. Detail pages handle a non-numeric id, a 404 and a load error with translated messages.
- Times (P5-8, Plan 4 M1): every time shown comes from the server's `starts_at`, formatted with `Intl`; nothing recomputes a saved time on the client. Admin screens show the academy's time plus the student's when it reads differently; non-admin screens show the viewer's own `me.timezone`.
- Tests are non-vacuous: each assertion fails without the code under test; duplicate matches are scoped (`within(row)`, `within(dialog)`); cross-academy tests hold data in BOTH academies with the other academy's pk forced above this one's (`until_pk_exceeds`), assert the explicit 404 or `not_found`, and assert this academy's own data is still there.

### Decisions this plan makes where the spec is silent or conflicts with the code

- **D1 — One session list, and `when`.** `GET /sessions/` is new and top-level: one list for every role, narrowed by `scope_for` (admin all, teacher the sessions they teach, student own, parent children's). Plan 4's `subscriptions/<id>/sessions/` stays and now applies the same `scope_for`, so after a teacher change the new teacher does not see the previous teacher's sessions there either, while the previous teacher keeps theirs in `/sessions/`; which subscriptions a teacher sees is unchanged (Plan 4 left this to Plan 5). Besides the spec's filters, `when` = `upcoming` (not yet ended, soonest first — a session in progress keeps its Join link), `past` (ended, latest first, for History), `today` or `week` (today and the next six days on the academy's calendar), so no screen computes "today" on the client. Without `when` the list is ordered by `starts_at`, as the spec says. A bad filter value is a 400 on that field (as Plan 4's `when`), not silently dropped. `upcoming`/`past` use the same SQL end instant as the missing-reports query (`rules.ENDS_AT`).
- **D2 — Pages and navigation per role.** Admin (Scheduling group): Today, Sessions (`/scheduling/sessions`), Missing reports (`/scheduling/reports`), Subscriptions; the session page is `/scheduling/sessions/$sessionId`, under Plan 4's admin guard. Teacher: a `teaching` group with My sessions (`/teaching/sessions`, tabs Today / This week / History) and Reports to write (`/teaching/reports`); Home adds "Today's sessions". Student and parent: a `learning` group with My sessions (`/learning/sessions`) and My subscriptions (`/learning/subscriptions`); Home adds the next session with Join and each live subscription's progress. `/teaching` and `/learning` are guarded by a new `requireRole(context, roles)` (`requireAdmin` becomes `requireRole(["admin"])`), and `NavItem.requiresRole` accepts one role or a list. A teacher writes reports in a dialog on their rows; there is no teacher session page.
- **D3 — The parent's child filter.** `me/` already lists a parent's children with their user ids. With two or more children, My sessions and My subscriptions show a "Child" select that sends `student=<user id>`; the server's scope already limits a parent to their children, so a forged id returns nothing. Home shows every child, with the student's name on each line.
- **D4 — Bulk response.** `{done: [id], skipped: [{id, code}]}`, both in ascending id order, duplicates collapsed. A rule refusal carries its 409 code; an id this academy does not have — including another academy's — is `not_found` (the dashboard reads it as `errors.not_found`). A bad body (`ids` empty or over 200, unknown `action`, cancel without `reason`) is a 400 before anything runs.
- **D5 — Lock order.** Plan 4 locks subscriptions first (in id order) and then deletes or inserts sessions. Plan 5 never locks a subscription: a single-session write locks only that session's row (`select_for_update`) and re-checks its status on the fresh row; bulk locks every requested row up front in one `SELECT … FOR UPDATE ORDER BY id`, then runs each session in its own savepoint, so two bulks never deadlock and one refusal never undoes the rest. A subscription action that deletes an untouched session a bulk cancel holds simply waits, then finds it cancelled and leaves it. (Committing each bulk item outside the request transaction was tried and rejected: it needs `non_atomic_requests`, and DRF's error handler then marks whatever transaction is open — in tests, the test's own — for rollback on any 400 or 403, while the ordered up-front lock already rules out the deadlock it was meant to avoid.)
- **D6 — The rule inside `derive`.** `rules.consuming(academy, *, via="")` builds the `Q` from the settings row `derive` already loads, so the switches cost no query and changing one changes every number at once. It uses positive lookups only (`teacher_attendance__in` everything but `absent`): a negated lookup across `sessions` inside `Count(filter=…)` would become a subquery about the subscription's other sessions.
- **D7 — Undo is admin-only for both attendances.** The spec makes clearing the student's attendance admin-only; clearing the teacher's attendance is an undo too, so it follows the same rule. A teacher sending `not_set` for either gets `403` (`PermissionDeniedError`); the dashboard never offers it to them.
- **D8 — Reports over HTTP.** `GET` returns `{session, behaviour, participation, notes, written_by: {id, full_name}, created_at, updated_at}` or 404 when none is written yet (the dashboard only asks when the row says `has_report`). `PUT` creates or replaces and answers 200 with the report; `written_by` stays the first writer. Every signed-in role reaches the report route's check, so a student or parent gets the same 404 as for a session they cannot see (spec §4.5), not a 403; `reports/missing/` is a role-level 403 for them.
- **D9 — "Missing report" in SQL.** `rules.ENDS_AT = starts_at + minutes × interval '1 minute'`; `missing_reports()` filters `status = completed` (a cancelled session is never completed), `has_report = false` (the `EXISTS` annotation of `sessions_queryset`) and `ENDS_AT < now() − 24 h`, oldest first — one query, scoped per viewer by the view.
- **D10 — Session payload.** Every row: `id, subscription_id, slot_id, occurs_on, starts_at, minutes, status, student_attendance, teacher_attendance, has_started, meeting_url, generated, student {id, full_name, timezone}, teacher {id, full_name}, course {id, name_ar, name_en}`; admins also get `notes` and `cancel_reason`; `has_report` goes to whoever `can_read_report(viewer, session)` — admins and that session's own teacher (the same rule the report routes use). `marked_by`/`cancelled_by` are stored, not shown (the spec's payload list leaves them out).
- **D11 — The start-time gate.** `services.has_started(session)` (`starts_at ≤ now`) is the only implementation: `mark_attendance` enforces it and the payload carries it as `has_started`. The dashboard disables the attendance controls while it is false and the teacher's list re-reads every minute, so the controls open shortly after the start without the browser comparing clocks.
- **D12 — Time on screen.** `otherZoneTime(instant, theirZone, ourZone, language)` joins `@/lib/zoned-time` (Plan 4's Today board helper, moved there so the Sessions list and session page reuse it); `dayIn(instant, zone, language)` gives the date on a viewer's clock. Non-admin screens read the zone through `useViewerZone()` (`me.timezone`).
- **D13 — A switch flip refreshes the screen.** Saving academy settings invalidates every query except the settings themselves: the switches move every subscription's numbers and the time zone moves every "today".
- **D14 — Seeds.** Plan 4's seeds generate from today only, so the demo has no past sessions to mark. `seed_attendance()` first generates each demo subscription's past days (an admin's backfill, Plan 4 D13), then marks every unmarked session before today as its teacher, cycling present, present, absent, present, excused; the second one is a teacher no-show; every completed session except the oldest gets a report, so exactly one old session shows under Missing reports. It runs only when no session in the academy is marked (`has_attendance`), prints `skip:` for a refused item and carries on, and sends nothing. Plan 4's deactivated-teacher seed test deletes the seeded subscriptions to reseed, which marked sessions forbid, so it switches `seed_attendance` off.
- **D15 — Report scales on screen.** Two native selects (Plan 3/4's `Select`) with the five labelled choices from Excellent to Poor, plus Notes; nothing chosen is the field error "Choose one of the five.".
- **D16 — Attendance controls.** Two native selects per session named "Student attendance for {name}" and "Teacher attendance for {name}", so rows in a table stay distinguishable; "Not set" is shown but disabled for teachers; both are disabled on a cancelled session and until `has_started`, with "Attendance opens at the start time." under them.
- **D17 — The admin list opens on Today.** Period (Today, This week, Upcoming, Past, Any time), From/To dates, status, student attendance, teacher, course and search, with the CSV link carrying the same filters. Row checkboxes and "select this page" feed the bulk bar (Mark present, Mark absent, Cancel sessions with a reason); after a run it shows "Done: N. Skipped: M." and one translated line per skipped session, and clears the selection.
- **D18 — Routes and methods.** `sessions/`, `sessions/<id>/` (GET); `sessions/<id>/attendance/`, `…/cancel/`, `…/restore/`, `sessions/bulk/` (POST); `sessions/<id>/report/` (GET, PUT); `reports/missing/` (GET). Each write answers with the session re-read through `sessions_queryset()`.

## Review Focus

- **Wrong counts from a combination nobody tried.** Every status × student attendance × teacher attendance under all four switch settings must count exactly as spec §4.2 says, and a teacher no-show must never count. Tests: Task 2 (`test_the_rule_for_every_attendance_combination`, `test_a_teacher_no_show_never_counts`).
- **Marking before the start, across time zones.** An academy away from UTC must open attendance at the session's real instant, "today" must be the academy's date near midnight UTC, and a teacher or student in another zone must see their own clock. Tests: Task 3 (`test_attendance_opens_at_the_start_time`, `test_the_gate_compares_instants_not_wall_clocks`), Task 6 (`test_today_and_week_are_the_academys_calendar`), Task 12 (`TeacherSessions` "shows today's sessions on the teacher's own clock"), Task 13 (`FamilySessions` "lists upcoming sessions…", Home "shows a student their next session…").
- **A teacher touching a session that isn't theirs.** Another teacher's session must answer 404 to attendance and report calls and never change, a teacher change must leave each teacher with exactly the sessions they teach, and students and parents must never learn a report exists. Tests: Task 7 (`test_a_teacher_cannot_mark_someone_elses_session`, `test_students_and_parents_never_see_a_report`, `test_every_role_on_every_route`), Task 6 (`test_a_teacher_keeps_the_sessions_they_taught_after_a_teacher_change`, `test_non_admins_never_see_staff_fields`).
- **Cancel and restore moving extras and carry-over.** Cancelling a completed session must stop it counting on its subscription and on the renewal's carried-over sessions, and restoring must bring both back. Tests: Task 3 (`test_cancelling_a_completed_session_stops_it_counting_until_restored`, `test_cancel_and_restore_move_extras_through_the_renewal`).
- **Numbers after a switch flip.** Turning a switch must change every subscription's used, remaining and carried-over sessions at once, and the dashboard must not keep showing the old numbers. Tests: Task 2 (`test_flipping_a_switch_changes_every_count_at_once`), Task 3 (the excused step of `test_cancel_and_restore_move_extras_through_the_renewal`), Task 9 (`AcademySettingsForm` "saves the counts-as-used switches and refreshes what they change").

---

## File Structure

```
backend/
  etqan/academy/                   absent/excused_consumes_session (+ migration 0004, API, tests)
  etqan/scheduling/
    models.py                      Session.marked_by/at, cancelled_by/at; NEW SessionReport
    migrations/0002_attendance_and_reports.py
    services/rules.py              consuming (replaces CONSUMING), ENDS_AT, sessions_queryset, filter_sessions,
                                   sessions_of → filter_sessions, has_attendance, unmarked_sessions_before
    services/attendance.py         NEW has_started, lock, mark_attendance, cancel_session, restore_session,
                                   bulk_sessions, BulkResult, MAX_BULK
    services/reports.py            NEW can_read_report, get_report, write_report, missing_reports
    services/generation.py         reads created/conflicting sessions through sessions_queryset
    services/__init__.py           re-exports
    api/payloads.py                session_row(session, *, viewer), generation_result(…, *, viewer),
                                   bulk_result, report_payload
    api/serializers.py             SessionFilterInput, AttendanceInput, CancelSessionInput, BulkInput, ReportInput
    api/session_views.py           NEW list/detail/attendance/cancel/restore/bulk/report/missing views
    api/views.py                   nested sessions list scoped by scope_for; generate passes viewer
    api/urls.py                    sessions/…, reports/missing/
    tests/conftest.py              make_admin
    tests/test_rules.py test_attendance.py test_reports.py test_api_sessions.py test_api_session_writes.py
  etqan/tenants/management/commands/seed_dev.py   seed_attendance (+ tests/test_seed_dev.py)
dashboard/
  src/lib/zoned-time.ts            otherZoneTime, dayIn
  src/features/identity/require-admin.ts          requireRole
  src/features/academy/…           the two switches; saving refreshes other queries
  src/features/scheduling/
    schemas api queries bits       session types, calls and hooks; SessionStatusChip, JoinLink, useViewerZone
    AttendanceControls CancelSessionDialog ReportForm ReportDialog
    SessionPage SessionsList SessionBulkBar MissingReports
    TeacherSessionTable TeacherSessions (TeacherHome)
    ChildFilter FamilySessions FamilySubscriptions (SubscriptionCard) FamilyHome
    TodayBoard                     uses otherZoneTime
  src/features/shell/nav.ts        Sessions, Missing reports; teaching and learning groups; role lists
  src/routes/_authed/              scheduling.sessions.{index,$sessionId}, scheduling.reports,
                                   teaching{,.index,.sessions,.reports}, learning{,.index,.sessions,.subscriptions},
                                   index (role panels)
  src/test/scheduling-fixtures.ts  sessionRow fields, reportRow, academySettings
  src/locales/{en,ar}/common.json
  e2e/sessions.spec.ts
meta: STATE.md, submodule pointers
```

---

### Task 1: Data: the two counting switches, session audit fields and `SessionReport`

**Files:**
- Create (generated): `backend/etqan/academy/migrations/0004_consumption_switches.py`, `backend/etqan/scheduling/migrations/0002_attendance_and_reports.py`
- Modify: `backend/etqan/academy/api/serializers.py`, `backend/etqan/academy/models.py`, `backend/etqan/academy/services.py`, `backend/etqan/scheduling/models.py`
- Test: `backend/etqan/academy/tests/test_api.py`, `backend/etqan/academy/tests/test_services.py`, `backend/etqan/scheduling/tests/test_reports.py` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: `AcademySettings.absent_consumes_session` (default `True`) and `.excused_consumes_session` (default `False`); `academy_services.update_settings(..., absent_consumes_session: bool | None = None, excused_consumes_session: bool | None = None)`; `GET/PATCH /api/v1/academy/settings/` carries both.
- Produces: `Session.marked_by`/`marked_at` and `Session.cancelled_by`/`cancelled_at` (nullable; `SET_NULL`); `SessionReport(session: OneToOne → Session, related_name="report"; behaviour, participation: 1–5 with `SessionReport.Scale`; notes; written_by → User `PROTECT`; created_at; updated_at)` with database checks that both scales are 1–5.

- [ ] **Step 1: Branch**

The meta repo is already on `feat/sessions-attendance`. Create the branch in `backend/` now and in `dashboard/` before Task 9:

```bash
git -C backend switch -c feat/sessions-attendance
```

- [ ] **Step 2: Write the failing tests**

Append to the end of `backend/etqan/academy/tests/test_api.py`:

```python
def test_admin_flips_the_consumption_switches(api_for):
    admin = api_for("admin")
    body = admin.get(URL).json()
    assert (body["absent_consumes_session"], body["excused_consumes_session"]) == (
        True,
        False,
    )
    resp = admin.patch(
        URL,
        {"absent_consumes_session": False, "excused_consumes_session": True},
        format="json",
    )
    body = resp.json()
    assert resp.status_code == 200, body
    assert (body["absent_consumes_session"], body["excused_consumes_session"]) == (
        False,
        True,
    )
    assert admin.get(URL).json()["absent_consumes_session"] is False


def test_a_switch_must_be_a_boolean(api_for):
    resp = api_for("admin").patch(
        URL, {"absent_consumes_session": "sometimes"}, format="json"
    )
    assert resp.status_code == 400
    assert "absent_consumes_session" in resp.json()


def test_only_admin_flips_a_switch(api_for):
    resp = api_for("teacher").patch(
        URL, {"excused_consumes_session": True}, format="json"
    )
    assert resp.status_code == 403
```

Append to the end of `backend/etqan/academy/tests/test_services.py`:

```python
def test_consumption_switches_default_and_update():
    s = services.get_settings()
    assert (s.absent_consumes_session, s.excused_consumes_session) == (True, False)
    s = services.update_settings(
        absent_consumes_session=False, excused_consumes_session=True
    )
    s.refresh_from_db()
    assert (s.absent_consumes_session, s.excused_consumes_session) == (False, True)
    # Leaving a switch out leaves it alone.
    s = services.update_settings(absent_consumes_session=True)
    s.refresh_from_db()
    assert (s.absent_consumes_session, s.excused_consumes_session) == (True, True)
```

Create `backend/etqan/scheduling/tests/test_reports.py`:

```python
import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionReport
from etqan.scheduling.tests.conftest import two_slots


@pytest.mark.parametrize("field", ["behaviour", "participation"])
def test_the_database_keeps_scales_between_1_and_5(subscribe, world, field):
    sub = subscribe(slots=two_slots())
    session = Session.objects.filter(subscription=sub).first()
    values = {"behaviour": 3, "participation": 3, field: 6}
    with pytest.raises(IntegrityError), transaction.atomic():
        SessionReport.objects.create(
            session=session, written_by=world.teacher, **values
        )
```

- [ ] **Step 3: Run them to verify they fail**

Every backend command runs from `backend/` with the environment from Global Constraints exported once per shell.

Run (from `backend/`): `.venv/bin/pytest -q etqan/academy etqan/scheduling/tests/test_reports.py`
Expected: FAIL — `update_settings() got an unexpected keyword argument 'absent_consumes_session'`, and `ImportError: cannot import name 'SessionReport'`.

- [ ] **Step 4: Implement**

In `backend/etqan/academy/api/serializers.py`, replace:

```python
    renewal_grace_days = serializers.IntegerField(
        min_value=0, max_value=60, required=False
    )
    updated_at = serializers.DateTimeField(read_only=True)
```

with:

```python
    renewal_grace_days = serializers.IntegerField(
        min_value=0, max_value=60, required=False
    )
    absent_consumes_session = serializers.BooleanField(required=False)
    excused_consumes_session = serializers.BooleanField(required=False)
    updated_at = serializers.DateTimeField(read_only=True)
```

In `backend/etqan/academy/models.py`, replace:

```python
    renewal_grace_days = models.PositiveSmallIntegerField(
        default=7, validators=[MinValueValidator(0), MaxValueValidator(60)]
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

```

with:

```python
    renewal_grace_days = models.PositiveSmallIntegerField(
        default=7, validators=[MinValueValidator(0), MaxValueValidator(60)]
    )
    # Plan 5 (spec §3.1, §4.2): whether a completed session the student missed
    # uses up one of the package's sessions. Read live by the one counting rule.
    absent_consumes_session = models.BooleanField(default=True)
    excused_consumes_session = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

```

In `backend/etqan/academy/services.py`, replace:

```python
    return value


def update_settings(
    *,
    timezone: str | None = None,
    default_currency: str | None = None,
    default_language: str | None = None,
    generation_horizon_days: int | None = None,
    renewal_grace_days: int | None = None,
) -> AcademySettings:
    settings_row = get_settings()
    if timezone is not None:
```

with:

```python
    return value


def update_settings(  # noqa: PLR0913 -- keyword-only; mirrors the settings body
    *,
    timezone: str | None = None,
    default_currency: str | None = None,
    default_language: str | None = None,
    generation_horizon_days: int | None = None,
    renewal_grace_days: int | None = None,
    absent_consumes_session: bool | None = None,
    excused_consumes_session: bool | None = None,
) -> AcademySettings:
    settings_row = get_settings()
    if timezone is not None:
```

In `backend/etqan/academy/services.py`, replace:

```python
        settings_row.renewal_grace_days = _days(
            renewal_grace_days, GRACE_DAYS, "renewal_grace_days"
        )
    settings_row.save()
    return settings_row
```

with:

```python
        settings_row.renewal_grace_days = _days(
            renewal_grace_days, GRACE_DAYS, "renewal_grace_days"
        )
    if absent_consumes_session is not None:
        settings_row.absent_consumes_session = absent_consumes_session
    if excused_consumes_session is not None:
        settings_row.excused_consumes_session = excused_consumes_session
    settings_row.save()
    return settings_row
```

In `backend/etqan/scheduling/models.py`, replace:

```python
(CLAUDE.md, plan D2). Business rules live in `etqan.scheduling.services`.
"""

from django.core.validators import MaxValueValidator
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
```

with:

```python
(CLAUDE.md, plan D2). Business rules live in `etqan.scheduling.services`.
"""

from django.conf import settings
from django.core.validators import MaxValueValidator
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
```

In `backend/etqan/scheduling/models.py`, replace:

```python
    cancel_reason = models.TextField(blank=True, default="")
    notes = models.TextField(blank=True, default="")
    generated = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

```

with:

```python
    cancel_reason = models.TextField(blank=True, default="")
    notes = models.TextField(blank=True, default="")
    generated = models.BooleanField(default=False)
    # Plan 5 (spec §3.2): who last changed an attendance or cancelled, and when.
    marked_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    marked_at = models.DateTimeField(null=True, blank=True)
    cancelled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    cancelled_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

```

Append to the end of `backend/etqan/scheduling/models.py`:

```python
class SessionReport(models.Model):
    """A teacher's staff-only note on one completed session (P5-2, spec §3.3)."""

    class Scale(models.IntegerChoices):
        POOR = 1, "Poor"
        BELOW_AVERAGE = 2, "Below average"
        AVERAGE = 3, "Average"
        GOOD = 4, "Good"
        EXCELLENT = 5, "Excellent"

    session = models.OneToOneField(
        Session, on_delete=models.CASCADE, related_name="report"
    )
    behaviour = models.PositiveSmallIntegerField(choices=Scale.choices)
    participation = models.PositiveSmallIntegerField(choices=Scale.choices)
    notes = models.TextField(blank=True, default="")
    # The first writer; an edit by someone else keeps them (spec §4.5).
    written_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=Q(behaviour__gte=1, behaviour__lte=5),
                name="scheduling_report_behaviour_1_to_5",
            ),
            models.CheckConstraint(
                condition=Q(participation__gte=1, participation__lte=5),
                name="scheduling_report_participation_1_to_5",
            ),
        ]

    def __str__(self):
        return f"SessionReport<{self.session_id}>"
```

- [ ] **Step 5: Generate the migrations**

Run (from `backend/`): `.venv/bin/python manage.py makemigrations academy --name consumption_switches --settings=config.settings.test`
Expected: `etqan/academy/migrations/0004_consumption_switches.py` adding the two fields.

Run (from `backend/`): `.venv/bin/python manage.py makemigrations scheduling --name attendance_and_reports --settings=config.settings.test`
Expected: `etqan/scheduling/migrations/0002_attendance_and_reports.py` with `+ Add field cancelled_at/cancelled_by/marked_at/marked_by to session` and `+ Create model SessionReport`.

- [ ] **Step 6: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q --create-db etqan/academy etqan/scheduling/tests/test_reports.py`
Expected: PASS. `--create-db` because of the new migrations.

- [ ] **Step 7: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 8: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): counting switches, session audit fields and session reports

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The one consumption rule, with the switches, inside `derive`

**Files:**
- Modify: `backend/etqan/scheduling/services/rules.py`
- Test: `backend/etqan/scheduling/tests/test_rules.py`

**Interfaces:**
- Consumes: Task 1's switches on the settings row.
- Produces: `etqan.scheduling.services.rules.consuming(academy, *, via: str = "") -> Q` — the only implementation of spec §4.2 (plan D6). `rules.CONSUMING` is removed. `derive()`/`derived()` keep their signatures and query count; `sessions_used`, `carried_over_sessions`, `sessions_remaining`, `extra_sessions` and `progress` now follow the rule and read the switches live.

- [ ] **Step 1: Write the failing tests**

In `backend/etqan/scheduling/tests/test_rules.py`, replace:

```python
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import timedelta

from django.db import connection
from django.test.utils import CaptureQueriesContext

```

with:

```python
import itertools
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import timedelta

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

```

In `backend/etqan/scheduling/tests/test_rules.py`, replace:

```python
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionPause
from etqan.scheduling.scopes import scope_for
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher


def add_session(sub, day, *, status="scheduled", attendance="not_set", hour=18):
    return Session.objects.create(
        subscription=sub,
        student=sub.student,
```

with:

```python
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionPause
from etqan.scheduling.scopes import scope_for
from etqan.scheduling.services import rules
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher


def add_session(  # noqa: PLR0913 -- a test factory; every field is optional
    sub, day, *, status="scheduled", attendance="not_set", teacher="not_set", hour=18
):
    return Session.objects.create(
        subscription=sub,
        student=sub.student,
```

In `backend/etqan/scheduling/tests/test_rules.py`, replace:

```python
        minutes=45,
        status=status,
        student_attendance=attendance,
    )


```

with:

```python
        minutes=45,
        status=status,
        student_attendance=attendance,
        teacher_attendance=teacher,
    )


```

In `backend/etqan/scheduling/tests/test_rules.py`, replace:

```python
    assert (d.ends_on, d.grace_ends_on) == (date(2026, 7, 4), date(2026, 7, 4))


def test_only_completed_present_or_absent_sessions_are_used(subscribe):
    sub = subscribe()
    add_session(sub, date(2026, 6, 1), status="completed", attendance="present")
    add_session(sub, date(2026, 6, 2), status="completed", attendance="absent")
    add_session(sub, date(2026, 6, 3), status="completed", attendance="excused")
    add_session(sub, date(2026, 6, 4), status="cancelled", attendance="absent")
    add_session(sub, date(2026, 6, 5))
    d = services.derived(sub)
    assert (d.sessions_used, d.sessions_remaining, d.progress) == (2, 6, 0.25)


def test_extras_carry_into_the_renewal_live(subscribe):
```

with:

```python
    assert (d.ends_on, d.grace_ends_on) == (date(2026, 7, 4), date(2026, 7, 4))


def spec_says_used(session, *, absent_on, excused_on) -> bool:
    """Plan 5 spec §4.2, written out on its own to check the query against."""
    if session.status != "completed" or session.teacher_attendance == "absent":
        return False
    student = session.student_attendance
    return (
        student == "present"
        or (student == "absent" and absent_on)
        or (student == "excused" and excused_on)
    )


@pytest.mark.parametrize(
    ("absent_on", "excused_on"),
    [(True, False), (False, False), (True, True), (False, True)],
)
def test_the_rule_for_every_attendance_combination(subscribe, absent_on, excused_on):
    """Every status x student attendance x teacher attendance, under each
    setting of the two switches."""
    sub = subscribe()
    values = ("not_set", "present", "absent", "excused")
    combos = itertools.product(("scheduled", "completed", "cancelled"), values, values)
    sessions = [
        add_session(
            sub,
            date(2026, 6, 1) + timedelta(days=n),
            status=status,
            attendance=student,
            teacher=teacher,
        )
        for n, (status, student, teacher) in enumerate(combos)
    ]
    academy = academy_services.update_settings(
        absent_consumes_session=absent_on, excused_consumes_session=excused_on
    )
    counted = set(
        Session.objects.filter(rules.consuming(academy)).values_list("pk", flat=True)
    )
    expected = {
        s.pk
        for s in sessions
        if spec_says_used(s, absent_on=absent_on, excused_on=excused_on)
    }
    assert counted == expected
    assert services.derived(sub).sessions_used == len(expected)


def test_a_teacher_no_show_never_counts(subscribe):
    sub = subscribe()
    for n, student in enumerate(("present", "absent", "excused")):
        add_session(
            sub,
            date(2026, 6, 1 + n),
            status="completed",
            attendance=student,
            teacher="absent",
        )
    academy_services.update_settings(excused_consumes_session=True)
    assert services.derived(sub).sessions_used == 0


def test_flipping_a_switch_changes_every_count_at_once(subscribe):
    first = subscribe()
    second = subscribe(student_id=make_student("Aisha").id)
    for sub in (first, second):
        for n, student in enumerate(("present", "excused", "excused", "absent")):
            add_session(
                sub, date(2026, 6, 1 + n), status="completed", attendance=student
            )

    def used():
        found = services.derive([first, second])
        return [found[s.pk].sessions_used for s in (first, second)]

    assert used() == [2, 2]  # present and absent (the defaults)
    academy_services.update_settings(
        excused_consumes_session=True, absent_consumes_session=False
    )
    assert used() == [3, 3]  # present and both excused
    academy_services.update_settings(absent_consumes_session=True)
    assert used() == [4, 4]
    assert services.derived(first).sessions_remaining == 4


def test_extras_carry_into_the_renewal_live(subscribe):
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_rules.py`
Expected: FAIL — `AttributeError: module 'etqan.scheduling.services.rules' has no attribute 'consuming'`, and `test_a_teacher_no_show_never_counts` counts 2 used (the old rule ignores the teacher and the switches).

- [ ] **Step 3: Implement**

In `backend/etqan/scheduling/services/rules.py`, replace:

```python

LIVE = (Subscription.Status.ACTIVE, Subscription.Status.PAUSED)
NOT_SET = Session.Attendance.NOT_SET
# Plan 4's consumption rule (spec §3.2); Plan 5 may add academy switches.
CONSUMING = {
    "status": Session.Status.COMPLETED,
    "student_attendance__in": (Session.Attendance.PRESENT, Session.Attendance.ABSENT),
}
# A session someone has acted on: attendance marked or completed.
MARKED = (
    Q(status=Session.Status.COMPLETED)
```

with:

```python

LIVE = (Subscription.Status.ACTIVE, Subscription.Status.PAUSED)
NOT_SET = Session.Attendance.NOT_SET
PRESENT = Session.Attendance.PRESENT
ABSENT = Session.Attendance.ABSENT
EXCUSED = Session.Attendance.EXCUSED
# A session someone has acted on: attendance marked or completed.
MARKED = (
    Q(status=Session.Status.COMPLETED)
```

In `backend/etqan/scheduling/services/rules.py`, replace:

```python
    return academy_services.get_settings()


def today() -> date:
    """The academy's local date."""
    return dates.local_today(settings().timezone)
```

with:

```python
    return academy_services.get_settings()


def consuming(academy, *, via: str = "") -> Q:
    """The one rule for "this session used up one of the package's sessions"
    (Plan 5 spec §4.2): completed, the teacher was not absent (P5-4), and the
    student was present, or absent or excused while the academy's switch for
    it is on. ``academy`` is the settings row, so the switches are read live;
    ``via`` reaches the session through a relation (``"sessions"``).

    Written with positive lookups only: a negated lookup across a reverse
    relation inside an aggregate's filter would become a subquery about the
    subscription's other sessions."""
    prefix = f"{via}__" if via else ""
    students = [PRESENT]
    if academy.absent_consumes_session:
        students.append(ABSENT)
    if academy.excused_consumes_session:
        students.append(EXCUSED)
    teachers = [value for value in Session.Attendance.values if value != ABSENT]
    return Q(
        **{
            f"{prefix}status": Session.Status.COMPLETED,
            f"{prefix}student_attendance__in": students,
            f"{prefix}teacher_attendance__in": teachers,
        }
    )


def today() -> date:
    """The academy's local date."""
    return dates.local_today(settings().timezone)
```

In `backend/etqan/scheduling/services/rules.py`, replace:

```python
    progress: float


def _usage(student_ids) -> dict[int, tuple[int, int | None, int]]:
    """``{id: (sessions_total, renewed_from_id, sessions_used)}`` for every
    subscription of these students, in one query. A renewal chain never
    changes student, so this holds every link of every chain."""
    consuming = Q(**{f"sessions__{key}": value for key, value in CONSUMING.items()})
    rows = (
        Subscription.objects.filter(student_id__in=student_ids)
        .annotate(used=Count("sessions", filter=consuming))
        .values_list("id", "sessions_total", "renewed_from_id", "used")
    )
    return {row[0]: row[1:] for row in rows}
```

with:

```python
    progress: float


def _usage(student_ids, academy) -> dict[int, tuple[int, int | None, int]]:
    """``{id: (sessions_total, renewed_from_id, sessions_used)}`` for every
    subscription of these students, in one query. A renewal chain never
    changes student, so this holds every link of every chain."""
    rows = (
        Subscription.objects.filter(student_id__in=student_ids)
        .annotate(used=Count("sessions", filter=consuming(academy, via="sessions")))
        .values_list("id", "sessions_total", "renewed_from_id", "used")
    )
    return {row[0]: row[1:] for row in rows}
```

In `backend/etqan/scheduling/services/rules.py`, replace:

```python
    prefetch_related_objects(subscriptions, "pauses")
    academy = settings()
    local_today = dates.local_today(academy.timezone)
    usage = _usage({s.student_id for s in subscriptions})
    carried = _carried_over(usage)
    result = {}
    for sub in subscriptions:
```

with:

```python
    prefetch_related_objects(subscriptions, "pauses")
    academy = settings()
    local_today = dates.local_today(academy.timezone)
    # The settings row read above carries the consumption switches too, so the
    # rule costs no extra query.
    usage = _usage({s.student_id for s in subscriptions}, academy)
    carried = _carried_over(usage)
    result = {}
    for sub in subscriptions:
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling`
Expected: PASS, including Plan 4's `test_derive_costs_the_same_queries_for_one_or_many` (the switches come from the settings row `derive` already reads).

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): count sessions by attendance, the teacher and the academy switches

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Attendance, cancel and restore services, with the start-time gate

**Files:**
- Create: `backend/etqan/scheduling/services/attendance.py`
- Modify: `backend/etqan/scheduling/services/__init__.py`
- Test: `backend/etqan/scheduling/tests/conftest.py`, `backend/etqan/scheduling/tests/test_attendance.py` (new)

**Interfaces:**
- Consumes: Task 1's fields; Task 2's rule (through `derived`).
- Produces (all re-exported from `etqan.scheduling.services`):
  - `has_started(session) -> bool` — `starts_at <= dates.now()`; the one start-time gate (D11).
  - `mark_attendance(session, *, by, student_attendance: str | None = None, teacher_attendance: str | None = None) -> Session` — `ValidationError(field="student_attendance")` when both are missing; 409 `scheduling.session_cancelled`, then 409 `scheduling.not_started`; `PermissionDeniedError` when a non-admin sends `not_set` for either attendance (D7).
  - `cancel_session(session, *, by, reason: str) -> Session` — `ValidationError(field="reason")` for a blank reason; 409 `scheduling.not_allowed_in_status` unless scheduled or completed.
  - `restore_session(session) -> Session` — 409 `scheduling.not_allowed_in_status` unless cancelled.
  - `etqan.scheduling.services.attendance.lock(session) -> Session` — the session's row, `select_for_update`, read fresh; `NotFoundError` if it is gone.
- Produces (tests): `etqan.scheduling.tests.conftest.make_admin(name="Amina") -> User`.

- [ ] **Step 1: Write the failing tests**

In `backend/etqan/scheduling/tests/conftest.py`, replace:

```python
    return identity_services.create_person("student", full_name=name, **user)


def build_world():
    """A student, a teacher listed on the course, and a monthly package of
    2 x 45 minutes a week (8 sessions) with 10 freeze days, in the current
```

with:

```python
    return identity_services.create_person("student", full_name=name, **user)


def make_admin(name="Amina"):
    return identity_services.create_academy_admin(
        f"{name.lower()}@admins.test", full_name=name, password="pw-12345678"
    )


def build_world():
    """A student, a teacher listed on the course, and a monthly package of
    2 x 45 minutes a week (8 sessions) with 10 freeze days, in the current
```

Create `backend/etqan/scheduling/tests/test_attendance.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.academy import services as academy_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import PermissionDeniedError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import two_slots

# The first session: Monday 1 June 2026, 18:00 in the academy's timezone.
FIRST_START = datetime(2026, 6, 1, 18, tzinfo=UTC)


def on(sub, day):
    return Session.objects.get(subscription=sub, occurs_on=day)


def code(exc_info):
    return exc_info.value.code


@pytest.fixture
def first(subscribe, clock):
    """The subscription's first session, just after it started."""
    sub = subscribe(slots=two_slots())
    clock.set(FIRST_START)
    return on(sub, date(2026, 6, 1))


# ── The start-time gate ──────────────────────────────────────────────────────


def test_attendance_opens_at_the_start_time(subscribe, world, clock):
    session = on(subscribe(slots=two_slots()), date(2026, 6, 1))
    clock.set(datetime(2026, 6, 1, 17, 59, tzinfo=UTC))
    assert services.has_started(session) is False
    with pytest.raises(ConflictError) as exc:
        services.mark_attendance(
            session, by=world.teacher, student_attendance="present"
        )
    assert code(exc) == "scheduling.not_started"
    clock.set(FIRST_START)
    assert services.has_started(session) is True
    services.mark_attendance(session, by=world.teacher, student_attendance="present")


def test_the_gate_compares_instants_not_wall_clocks(subscribe, world, clock):
    # 18:00 in Riyadh is 15:00 UTC: marking opens at 15:00 UTC, three hours
    # before a wall-clock comparison with UTC would open it.
    academy_services.update_settings(timezone="Asia/Riyadh")
    session = on(subscribe(slots=two_slots()), date(2026, 6, 1))
    assert session.starts_at == datetime(2026, 6, 1, 15, tzinfo=UTC)
    clock.set(datetime(2026, 6, 1, 14, 59, tzinfo=UTC))
    with pytest.raises(ConflictError) as exc:
        services.mark_attendance(session, by=world.teacher, student_attendance="absent")
    assert code(exc) == "scheduling.not_started"
    clock.set(datetime(2026, 6, 1, 15, 1, tzinfo=UTC))
    marked = services.mark_attendance(
        session, by=world.teacher, student_attendance="absent"
    )
    assert marked.status == "completed"


# ── Marking ──────────────────────────────────────────────────────────────────


def test_a_student_mark_completes_the_session_and_is_recorded(first, world):
    marked = services.mark_attendance(
        first, by=world.teacher, student_attendance="present"
    )
    first.refresh_from_db()
    assert (first.status, first.student_attendance) == ("completed", "present")
    assert (first.marked_by, first.marked_at) == (world.teacher, FIRST_START)
    assert marked.status == "completed"


@pytest.mark.parametrize("value", ["absent", "excused", "present"])
def test_changing_a_mark_keeps_the_session_completed(first, world, value):
    services.mark_attendance(first, by=world.teacher, student_attendance="present")
    services.mark_attendance(first, by=world.teacher, student_attendance=value)
    first.refresh_from_db()
    assert (first.status, first.student_attendance) == ("completed", value)


def test_teacher_attendance_never_changes_the_status(first, world):
    services.mark_attendance(first, by=world.teacher, teacher_attendance="absent")
    first.refresh_from_db()
    assert (first.status, first.teacher_attendance) == ("scheduled", "absent")
    assert first.student_attendance == "not_set"
    assert first.marked_by == world.teacher


def test_one_of_the_two_attendances_is_needed(first, world):
    with pytest.raises(ValidationError) as exc:
        services.mark_attendance(first, by=world.teacher)
    assert exc.value.field == "student_attendance"


@pytest.mark.parametrize(
    "clear", [{"student_attendance": "not_set"}, {"teacher_attendance": "not_set"}]
)
def test_only_an_admin_clears_attendance(first, world, clear):
    services.mark_attendance(
        first,
        by=world.teacher,
        student_attendance="present",
        teacher_attendance="present",
    )
    with pytest.raises(PermissionDeniedError):
        services.mark_attendance(first, by=world.teacher, **clear)
    first.refresh_from_db()
    assert (first.status, first.student_attendance) == ("completed", "present")
    admin = make_admin()
    services.mark_attendance(first, by=admin, **clear)
    first.refresh_from_db()
    assert first.marked_by == admin


def test_clearing_the_student_returns_the_session_to_scheduled(first, world):
    services.mark_attendance(first, by=world.teacher, student_attendance="absent")
    services.mark_attendance(first, by=make_admin(), student_attendance="not_set")
    first.refresh_from_db()
    assert (first.status, first.student_attendance) == ("scheduled", "not_set")


def test_a_cancelled_session_is_not_marked(first, world):
    services.cancel_session(first, by=make_admin(), reason="Teacher ill")
    with pytest.raises(ConflictError) as exc:
        services.mark_attendance(first, by=world.teacher, student_attendance="present")
    assert code(exc) == "scheduling.session_cancelled"


def test_writes_recheck_the_locked_row_not_the_callers_copy(first, world):
    stale = Session.objects.get(pk=first.pk)
    Session.objects.filter(pk=first.pk).update(status="cancelled")
    with pytest.raises(ConflictError) as exc:
        services.mark_attendance(stale, by=world.teacher, student_attendance="present")
    assert code(exc) == "scheduling.session_cancelled"
    Session.objects.filter(pk=first.pk).update(status="scheduled")
    with pytest.raises(ConflictError) as exc:
        services.restore_session(stale)  # the copy says cancelled; the row does not
    assert code(exc) == "scheduling.not_allowed_in_status"


def test_a_deleted_session_is_not_found(first, world):
    Session.objects.filter(pk=first.pk).delete()
    with pytest.raises(NotFoundError):
        services.mark_attendance(first, by=world.teacher, student_attendance="present")


# ── Cancel and restore ───────────────────────────────────────────────────────


def test_cancel_needs_a_reason(first):
    with pytest.raises(ValidationError) as exc:
        services.cancel_session(first, by=make_admin(), reason="  ")
    assert exc.value.field == "reason"


def test_cancel_a_scheduled_session_and_restore_it(first):
    admin = make_admin()
    services.cancel_session(first, by=admin, reason="Holiday")
    first.refresh_from_db()
    assert (first.status, first.cancel_reason) == ("cancelled", "Holiday")
    assert (first.cancelled_by, first.cancelled_at) == (admin, FIRST_START)
    with pytest.raises(ConflictError) as exc:
        services.cancel_session(first, by=admin, reason="Again")
    assert code(exc) == "scheduling.not_allowed_in_status"
    services.restore_session(first)
    first.refresh_from_db()
    assert (first.status, first.cancel_reason) == ("scheduled", "")
    assert (first.cancelled_by, first.cancelled_at) == (None, None)
    with pytest.raises(ConflictError) as exc:
        services.restore_session(first)
    assert code(exc) == "scheduling.not_allowed_in_status"


def test_cancelling_a_completed_session_stops_it_counting_until_restored(first, world):
    sub = first.subscription
    services.mark_attendance(first, by=world.teacher, student_attendance="present")
    assert services.derived(sub).sessions_used == 1
    services.cancel_session(first, by=make_admin(), reason="Recorded twice")
    first.refresh_from_db()
    # The attendance stays, for the record, but no longer counts.
    assert (first.status, first.student_attendance) == ("cancelled", "present")
    assert services.derived(sub).sessions_used == 0
    services.restore_session(first)
    first.refresh_from_db()
    assert first.status == "completed"
    assert services.derived(sub).sessions_used == 1


def test_a_future_session_cancelled_in_advance_survives_regeneration(subscribe, world):
    sub = subscribe(slots=two_slots())
    wednesday = on(sub, date(2026, 6, 3))
    services.cancel_session(wednesday, by=make_admin(), reason="Student travels")
    # A teacher change replaces the untouched sessions only (P4-7).
    maryam = make_teacher("Maryam")
    world.course.teachers.add(maryam.teacher_profile)
    services.update_subscription(sub, teacher_id=maryam.id)
    kept = Session.objects.filter(subscription=sub, occurs_on=date(2026, 6, 3))
    assert [(s.pk, s.status) for s in kept] == [(wednesday.pk, "cancelled")]


# ── Plan 4's extras and carry-over, driven by real marks ────────────────────


def test_cancel_and_restore_move_extras_through_the_renewal(subscribe, world, clock):
    old = subscribe(slots=two_slots())
    services.generate(date(2026, 6, 1), date(2026, 7, 6), subscription=old)
    clock.set(datetime(2026, 7, 6, 20, tzinfo=UTC))
    taught = list(Session.objects.filter(subscription=old).order_by("starts_at")[:9])
    for session in taught:  # 9 taught on an 8-session package
        services.mark_attendance(
            session, by=world.teacher, student_attendance="present"
        )
    new = services.renew_subscription(old, starts_on=date(2026, 7, 8))
    assert services.derived(old).extra_sessions == 1
    assert services.derived(new).carried_over_sessions == 1
    admin = make_admin()
    services.cancel_session(taught[0], by=admin, reason="Duplicate")
    assert services.derived(old).extra_sessions == 0
    assert services.derived(new).carried_over_sessions == 0
    services.restore_session(taught[0])
    assert services.derived(new).carried_over_sessions == 1
    # An excused absence carries over only while its switch is on.
    services.mark_attendance(taught[1], by=admin, student_attendance="excused")
    assert services.derived(new).carried_over_sessions == 0
    academy_services.update_settings(excused_consumes_session=True)
    assert services.derived(new).carried_over_sessions == 1
    assert Subscription.objects.get(pk=new.pk).renewed_from_id == old.pk
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_attendance.py`
Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'has_started'` (and `mark_attendance`, `cancel_session`, `restore_session`).

- [ ] **Step 3: Implement**

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
"""Public API of the scheduling module. Other apps import only this package."""

from etqan.scheduling.services.board import TodayRow
from etqan.scheduling.services.board import today_board
from etqan.scheduling.services.generation import GenerationResult
```

with:

```python
"""Public API of the scheduling module. Other apps import only this package."""

from etqan.scheduling.services.attendance import cancel_session
from etqan.scheduling.services.attendance import has_started
from etqan.scheduling.services.attendance import mark_attendance
from etqan.scheduling.services.attendance import restore_session
from etqan.scheduling.services.board import TodayRow
from etqan.scheduling.services.board import today_board
from etqan.scheduling.services.generation import GenerationResult
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
    "TodayRow",
    "add_pause",
    "add_slots",
    "cancel_subscription",
    "create_subscription",
    "delete_pause",
```

with:

```python
    "TodayRow",
    "add_pause",
    "add_slots",
    "cancel_session",
    "cancel_subscription",
    "create_subscription",
    "delete_pause",
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
    "generate",
    "generate_horizon",
    "has_marked_sessions",
    "has_subscriptions",
    "pause_state",
    "renew_subscription",
    "renewal_starts_on",
    "run_lifecycle",
    "sessions_of",
    "slots_of",
```

with:

```python
    "generate",
    "generate_horizon",
    "has_marked_sessions",
    "has_started",
    "has_subscriptions",
    "mark_attendance",
    "pause_state",
    "renew_subscription",
    "renewal_starts_on",
    "restore_session",
    "run_lifecycle",
    "sessions_of",
    "slots_of",
```

Create `backend/etqan/scheduling/services/attendance.py`:

```python
"""Marking, cancelling and restoring one session, and doing it in bulk
(Plan 5 spec §4.1, §4.3, §4.4).

Every write locks the one session row (``select_for_update``) and checks its
state on that fresh row, so two people marking at once are serialised and the
second sees the first's change. A session write never locks a subscription:
Plan 4 locks subscriptions first (in id order) and then touches sessions, so
taking only a session lock can never close a cycle with it (plan D5).
"""

from django.db import transaction

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import PermissionDeniedError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import role_of
from etqan.scheduling import dates
from etqan.scheduling.models import Session

SCHEDULED = Session.Status.SCHEDULED
COMPLETED = Session.Status.COMPLETED
CANCELLED = Session.Status.CANCELLED
NOT_SET = Session.Attendance.NOT_SET


def has_started(session: Session) -> bool:
    """The start-time gate (P5-5): attendance opens once ``starts_at`` has
    passed. The one implementation; payloads send it as ``has_started``."""
    return session.starts_at <= dates.now()


def lock(session: Session) -> Session:
    """The session's row, locked for this transaction and read fresh."""
    try:
        return Session.objects.select_for_update().get(pk=session.pk)
    except Session.DoesNotExist:
        raise NotFoundError("Session", session.pk) from None


def _not_allowed(session: Session) -> ConflictError:
    return ConflictError(
        f"Not allowed while the session is {session.status}.",
        code="scheduling.not_allowed_in_status",
    )


@transaction.atomic
def mark_attendance(
    session: Session,
    *,
    by,
    student_attendance: str | None = None,
    teacher_attendance: str | None = None,
) -> Session:
    """Spec §4.1. A student mark completes a scheduled session; clearing an
    attendance back to ``not_set`` is an undo, and only an admin undoes
    (plan D7). The teacher's attendance never changes the status."""
    if student_attendance is None and teacher_attendance is None:
        raise ValidationError(
            "Set the student's or the teacher's attendance.",
            field="student_attendance",
        )
    locked = lock(session)
    if locked.status == CANCELLED:
        raise ConflictError(
            "This session was cancelled.", code="scheduling.session_cancelled"
        )
    if not has_started(locked):
        raise ConflictError(
            "Attendance opens when the session starts.",
            code="scheduling.not_started",
        )
    if NOT_SET in (student_attendance, teacher_attendance) and (role_of(by) != "admin"):
        raise PermissionDeniedError("clear attendance")
    fields = ["marked_by", "marked_at", "updated_at"]
    if student_attendance is not None:
        locked.student_attendance = student_attendance
        locked.status = SCHEDULED if student_attendance == NOT_SET else COMPLETED
        fields += ["student_attendance", "status"]
    if teacher_attendance is not None:
        locked.teacher_attendance = teacher_attendance
        fields.append("teacher_attendance")
    locked.marked_by = by
    locked.marked_at = dates.now()
    locked.save(update_fields=fields)
    return locked


@transaction.atomic
def cancel_session(session: Session, *, by, reason: str) -> Session:
    """Spec §4.3: from scheduled, or from completed (it stops counting).
    Attendance and any report are kept, for the record."""
    reason = (reason or "").strip()
    if not reason:
        raise ValidationError("Give a reason.", field="reason")
    locked = lock(session)
    if locked.status not in (SCHEDULED, COMPLETED):
        raise _not_allowed(locked)
    locked.status = CANCELLED
    locked.cancel_reason = reason
    locked.cancelled_by = by
    locked.cancelled_at = dates.now()
    locked.save(
        update_fields=[
            "status",
            "cancel_reason",
            "cancelled_by",
            "cancelled_at",
            "updated_at",
        ]
    )
    return locked


@transaction.atomic
def restore_session(session: Session) -> Session:
    """Spec §4.3: back to scheduled, or to completed when the student's
    attendance is set; the cancel fields are cleared."""
    locked = lock(session)
    if locked.status != CANCELLED:
        raise _not_allowed(locked)
    locked.status = SCHEDULED if locked.student_attendance == NOT_SET else COMPLETED
    locked.cancel_reason = ""
    locked.cancelled_by = None
    locked.cancelled_at = None
    locked.save(
        update_fields=[
            "status",
            "cancel_reason",
            "cancelled_by",
            "cancelled_at",
            "updated_at",
        ]
    )
    return locked
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling`
Expected: PASS.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): mark attendance, cancel and restore a session

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Bulk present, absent and cancel

**Files:**
- Modify: `backend/etqan/scheduling/services/__init__.py`, `backend/etqan/scheduling/services/attendance.py`
- Test: `backend/etqan/scheduling/tests/test_attendance.py`

**Interfaces:**
- Consumes: Task 3's `mark_attendance`, `cancel_session`.
- Produces: `bulk_sessions(ids: Iterable[int], *, action: str, by, reason: str = "") -> BulkResult`; `BulkResult(done: list[int], skipped: list[tuple[int, str]])` in id order; `MAX_BULK = 200`; `ValidationError` on `action` (not present/absent/cancel), `reason` (blank for cancel) and `ids` (0 or more than 200 distinct ids). Locking as in D5.

- [ ] **Step 1: Write the failing tests**

In `backend/etqan/scheduling/tests/test_attendance.py`, replace:

```python
from datetime import datetime

import pytest

from etqan.academy import services as academy_services
from etqan.platform.exceptions import ConflictError
```

with:

```python
from datetime import datetime

import pytest
from django.db.models import Max
from django_tenants.utils import tenant_context

from etqan.academy import services as academy_services
from etqan.platform.exceptions import ConflictError
```

In `backend/etqan/scheduling/tests/test_attendance.py`, replace:

```python
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import two_slots

# The first session: Monday 1 June 2026, 18:00 in the academy's timezone.
FIRST_START = datetime(2026, 6, 1, 18, tzinfo=UTC)
```

with:

```python
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots
from etqan.scheduling.tests.conftest import until_pk_exceeds

# The first session: Monday 1 June 2026, 18:00 in the academy's timezone.
FIRST_START = datetime(2026, 6, 1, 18, tzinfo=UTC)
```

Append to the end of `backend/etqan/scheduling/tests/test_attendance.py`:

```python
# ── Bulk ─────────────────────────────────────────────────────────────────────


def test_bulk_marks_what_it_may_and_skips_the_rest_with_codes(subscribe, clock):
    sub = subscribe(slots=two_slots())
    monday, wednesday = on(sub, date(2026, 6, 1)), on(sub, date(2026, 6, 3))
    next_monday = on(sub, date(2026, 6, 8))
    clock.set(datetime(2026, 6, 4, 9, tzinfo=UTC))  # both June sessions started
    admin = make_admin()
    services.cancel_session(wednesday, by=admin, reason="Holiday")
    missing = next_monday.pk + 1000
    result = services.bulk_sessions(
        [next_monday.pk, wednesday.pk, monday.pk, missing, monday.pk],
        action="present",
        by=admin,
    )
    assert result.done == [monday.pk]
    # In id order, like `done`.
    assert result.skipped == sorted(
        [
            (wednesday.pk, "scheduling.session_cancelled"),
            (next_monday.pk, "scheduling.not_started"),
            (missing, "not_found"),
        ]
    )
    # A refusal never undoes the sessions that were done.
    monday.refresh_from_db()
    assert (monday.status, monday.marked_by) == ("completed", admin)
    next_monday.refresh_from_db()
    assert next_monday.status == "scheduled"


def test_bulk_cancel_needs_a_reason_and_skips_cancelled(subscribe, clock):
    sub = subscribe(slots=two_slots())
    monday, wednesday = on(sub, date(2026, 6, 1)), on(sub, date(2026, 6, 3))
    admin = make_admin()
    with pytest.raises(ValidationError) as exc:
        services.bulk_sessions([monday.pk], action="cancel", by=admin)
    assert exc.value.field == "reason"
    services.cancel_session(wednesday, by=admin, reason="Holiday")
    result = services.bulk_sessions(
        [monday.pk, wednesday.pk], action="cancel", by=admin, reason="Eid"
    )
    assert result.done == [monday.pk]
    assert result.skipped == [(wednesday.pk, "scheduling.not_allowed_in_status")]
    monday.refresh_from_db()
    assert (monday.status, monday.cancel_reason) == ("cancelled", "Eid")


@pytest.mark.parametrize(
    ("ids", "action", "field"),
    [
        ([], "present", "ids"),
        (list(range(1, 202)), "absent", "ids"),
        ([1], "x", "action"),
    ],
)
def test_bulk_bounds(ids, action, field):
    with pytest.raises(ValidationError) as exc:
        services.bulk_sessions(ids, action=action, by=make_admin())
    assert exc.value.field == field


def test_bulk_never_reaches_another_academy(subscribe, clock, tenants):
    mine = on(subscribe(slots=two_slots()), date(2026, 6, 1))
    ceiling = Session.objects.aggregate(m=Max("pk"))["m"]
    with tenant_context(tenants.other):
        world = build_world()
        sub = until_pk_exceeds(
            Session, ceiling, lambda: subscription_for(world, slots=two_slots())
        )
        theirs = Session.objects.filter(subscription=sub).order_by("pk").first()
    assert theirs.pk > ceiling
    clock.set(datetime(2026, 6, 2, 9, tzinfo=UTC))
    result = services.bulk_sessions(
        [mine.pk, theirs.pk], action="absent", by=make_admin()
    )
    assert result.done == [mine.pk]
    assert result.skipped == [(theirs.pk, "not_found")]
    with tenant_context(tenants.other):
        theirs.refresh_from_db()
        assert (theirs.status, theirs.student_attendance) == ("scheduled", "not_set")
    mine.refresh_from_db()
    assert mine.student_attendance == "absent"
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_attendance.py -k bulk`
Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'bulk_sessions'`.

- [ ] **Step 3: Implement**

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
"""Public API of the scheduling module. Other apps import only this package."""

from etqan.scheduling.services.attendance import cancel_session
from etqan.scheduling.services.attendance import has_started
from etqan.scheduling.services.attendance import mark_attendance
```

with:

```python
"""Public API of the scheduling module. Other apps import only this package."""

from etqan.scheduling.services.attendance import MAX_BULK
from etqan.scheduling.services.attendance import BulkResult
from etqan.scheduling.services.attendance import bulk_sessions
from etqan.scheduling.services.attendance import cancel_session
from etqan.scheduling.services.attendance import has_started
from etqan.scheduling.services.attendance import mark_attendance
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
from etqan.scheduling.services.subscriptions import update_subscription

__all__ = [
    "Derived",
    "GenerationResult",
    "TodayRow",
    "add_pause",
    "add_slots",
    "cancel_session",
    "cancel_subscription",
    "create_subscription",
```

with:

```python
from etqan.scheduling.services.subscriptions import update_subscription

__all__ = [
    "MAX_BULK",
    "BulkResult",
    "Derived",
    "GenerationResult",
    "TodayRow",
    "add_pause",
    "add_slots",
    "bulk_sessions",
    "cancel_session",
    "cancel_subscription",
    "create_subscription",
```

In `backend/etqan/scheduling/services/attendance.py`, replace:

```python
"""Marking, cancelling and restoring one session, and doing it in bulk
(Plan 5 spec §4.1, §4.3, §4.4).

Every write locks the one session row (``select_for_update``) and checks its
state on that fresh row, so two people marking at once are serialised and the
second sees the first's change. A session write never locks a subscription:
Plan 4 locks subscriptions first (in id order) and then touches sessions, so
taking only a session lock can never close a cycle with it (plan D5).
"""

from django.db import transaction

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import PermissionDeniedError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import role_of
from etqan.scheduling import dates
from etqan.scheduling.models import Session

SCHEDULED = Session.Status.SCHEDULED
COMPLETED = Session.Status.COMPLETED
```

with:

```python
"""Marking, cancelling and restoring one session, and doing it in bulk
(Plan 5 spec §4.1, §4.3, §4.4).

Every write locks the one session row (``select_for_update``) and checks its
state on that fresh row, so two people marking at once are serialised and the
second sees the first's change. A session write never locks a subscription:
Plan 4 locks subscriptions first (in id order) and then touches sessions, so
taking only a session lock can never close a cycle with it (plan D5).
"""

from collections.abc import Iterable
from dataclasses import dataclass
from dataclasses import field

from django.db import transaction

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import PermissionDeniedError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import role_of
from etqan.scheduling import dates
from etqan.scheduling.models import Session

SCHEDULED = Session.Status.SCHEDULED
COMPLETED = Session.Status.COMPLETED
```

Append to the end of `backend/etqan/scheduling/services/attendance.py`:

```python
# ── Bulk (spec §4.4) ─────────────────────────────────────────────────────────

BULK_ACTIONS = ("present", "absent", "cancel")
MAX_BULK = 200


@dataclass
class BulkResult:
    done: list[int] = field(default_factory=list)
    skipped: list[tuple[int, str]] = field(default_factory=list)  # (id, code)


def bulk_sessions(
    ids: Iterable[int], *, action: str, by, reason: str = ""
) -> BulkResult:
    """Apply ``action`` to each session on its own, with the single-session
    rules above. A session that fails a rule is skipped with its code; an id
    this academy does not have is skipped as ``not_found``.

    Each session runs in its own transaction (the API calls this outside the
    request's transaction, plan D5), so no more than one session is locked at
    a time and one refusal never undoes the others."""
    if action not in BULK_ACTIONS:
        raise ValidationError("Choose present, absent or cancel.", field="action")
    if action == "cancel" and not (reason or "").strip():
        raise ValidationError("Give a reason.", field="reason")
    ids = sorted(set(ids))
    if not 1 <= len(ids) <= MAX_BULK:
        raise ValidationError(f"Choose from 1 to {MAX_BULK} sessions.", field="ids")
    result = BulkResult()
    for pk in ids:
        try:
            with transaction.atomic():
                session = lock(Session(pk=pk))
                if action == "cancel":
                    cancel_session(session, by=by, reason=reason)
                else:
                    mark_attendance(session, by=by, student_attendance=action)
        except NotFoundError:
            result.skipped.append((pk, "not_found"))
        except ConflictError as exc:
            result.skipped.append((pk, exc.code))
        else:
            result.done.append(pk)
    return result
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_attendance.py`
Expected: PASS.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): bulk attendance and cancel with skipped codes

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Reports: write, read and the missing-reports query

**Files:**
- Create: `backend/etqan/scheduling/services/reports.py`
- Modify: `backend/etqan/scheduling/services/__init__.py`, `backend/etqan/scheduling/services/rules.py`
- Test: `backend/etqan/scheduling/tests/test_reports.py`

**Interfaces:**
- Consumes: Task 1's `SessionReport`; Task 3's `lock`.
- Produces (re-exported from `etqan.scheduling.services`):
  - `can_read_report(user, session) -> bool` — admin, or the teacher of this session (P5-2); the one rule for the report routes and for `has_report` (D10).
  - `get_report(session) -> SessionReport | None` (with `written_by`).
  - `write_report(session, *, by, behaviour: int, participation: int, notes: str = "") -> SessionReport` — `ValidationError(field=…)` outside 1–5; 409 `scheduling.not_completed`; keeps the first `written_by`.
  - `missing_reports() -> QuerySet[Session]` — one query, oldest first (D9).
  - `sessions_queryset() -> QuerySet[Session]` — people and course joined, `has_report` annotated.
- Produces: `rules.ENDS_AT` (the SQL end instant) and `reports.REPORT_DUE_AFTER = timedelta(hours=24)`.

- [ ] **Step 1: Write the failing tests**

In `backend/etqan/scheduling/tests/test_reports.py`, replace:

```python
import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionReport
from etqan.scheduling.tests.conftest import two_slots


@pytest.mark.parametrize("field", ["behaviour", "participation"])
def test_the_database_keeps_scales_between_1_and_5(subscribe, world, field):
```

with:

```python
from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import IntegrityError
from django.db import connection
from django.db import transaction
from django.test.utils import CaptureQueriesContext

from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionReport
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import two_slots

MONDAY = date(2026, 6, 1)  # 18:00-18:45 UTC
ENDED = datetime(2026, 6, 1, 18, 45, tzinfo=UTC)


def on(sub, day):
    return Session.objects.get(subscription=sub, occurs_on=day)


@pytest.fixture
def taught(subscribe, world, clock):
    """Monday's session, marked present by its teacher once it started."""
    session = on(subscribe(slots=two_slots()), MONDAY)
    clock.set(ENDED)
    services.mark_attendance(session, by=world.teacher, student_attendance="present")
    return session


@pytest.mark.parametrize("field", ["behaviour", "participation"])
def test_the_database_keeps_scales_between_1_and_5(subscribe, world, field):
```

Append to the end of `backend/etqan/scheduling/tests/test_reports.py`:

```python
# ── Writing ──────────────────────────────────────────────────────────────────


def test_the_teacher_writes_and_an_admin_edits_keeping_the_first_writer(taught, world):
    report = services.write_report(
        taught, by=world.teacher, behaviour=5, participation=4, notes="Fluent"
    )
    assert (report.behaviour, report.participation, report.notes) == (5, 4, "Fluent")
    services.write_report(taught, by=make_admin(), behaviour=2, participation=3)
    report = services.get_report(taught)
    assert (report.behaviour, report.participation, report.notes) == (2, 3, "")
    assert report.written_by == world.teacher
    assert SessionReport.objects.filter(session=taught).count() == 1


def test_a_report_needs_a_completed_session(subscribe, world, clock):
    sub = subscribe(slots=two_slots())
    scheduled = on(sub, MONDAY)
    with pytest.raises(ConflictError) as exc:
        services.write_report(scheduled, by=world.teacher, behaviour=3, participation=3)
    assert exc.value.code == "scheduling.not_completed"
    clock.set(ENDED)
    services.mark_attendance(scheduled, by=world.teacher, student_attendance="present")
    services.cancel_session(scheduled, by=make_admin(), reason="Mistake")
    with pytest.raises(ConflictError) as exc:
        services.write_report(scheduled, by=world.teacher, behaviour=3, participation=3)
    assert exc.value.code == "scheduling.not_completed"
    assert services.get_report(scheduled) is None


@pytest.mark.parametrize(
    ("values", "field"),
    [
        ({"behaviour": 0, "participation": 3}, "behaviour"),
        ({"behaviour": 3, "participation": 6}, "participation"),
    ],
)
def test_scales_run_from_1_to_5(taught, world, values, field):
    with pytest.raises(ValidationError) as exc:
        services.write_report(taught, by=world.teacher, **values)
    assert exc.value.field == field


def test_a_cancelled_session_keeps_its_report(taught, world):
    services.write_report(taught, by=world.teacher, behaviour=4, participation=4)
    services.cancel_session(taught, by=make_admin(), reason="Recorded twice")
    assert services.get_report(taught).behaviour == 4


# ── Who reads ────────────────────────────────────────────────────────────────


def test_only_admins_and_the_sessions_teacher_read_reports(taught, world):
    taught = services.sessions_queryset().get(pk=taught.pk)
    parent = identity_services.create_person("parent", full_name="Omar")
    identity_services.link_guardian(parent, world.student)
    readers = {
        "admin": (make_admin(), True),
        "teacher": (world.teacher, True),
        "another teacher": (make_teacher("Maryam"), False),
        "student": (world.student, False),
        "parent": (parent, False),
    }
    for name, (user, expected) in readers.items():
        assert services.can_read_report(user, taught) is expected, name


# ── Missing reports ──────────────────────────────────────────────────────────


def test_a_report_is_missing_24_hours_after_the_session_ends(taught, world, clock):
    clock.set(datetime(2026, 6, 2, 18, 45, tzinfo=UTC))  # exactly 24 hours
    assert list(services.missing_reports()) == []
    clock.set(datetime(2026, 6, 2, 18, 46, tzinfo=UTC))
    assert [s.pk for s in services.missing_reports()] == [taught.pk]
    services.write_report(taught, by=world.teacher, behaviour=4, participation=5)
    assert list(services.missing_reports()) == []


def test_only_completed_sessions_miss_a_report(subscribe, world, clock):
    sub = subscribe(slots=two_slots())
    monday, wednesday = on(sub, MONDAY), on(sub, date(2026, 6, 3))
    clock.set(datetime(2026, 6, 3, 19, tzinfo=UTC))
    services.mark_attendance(wednesday, by=world.teacher, student_attendance="absent")
    services.cancel_session(wednesday, by=make_admin(), reason="Mistake")
    clock.set(datetime(2026, 6, 10, 9, tzinfo=UTC))
    # Monday was never marked; Wednesday was completed, then cancelled.
    assert list(services.missing_reports()) == []
    services.restore_session(wednesday)
    assert [s.pk for s in services.missing_reports()] == [wednesday.pk]
    assert monday.pk not in {s.pk for s in services.missing_reports()}


def test_missing_reports_costs_the_same_queries_for_one_or_many(
    subscribe, world, clock
):
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 10, 9, tzinfo=UTC))
    before = Session.objects.filter(subscription=sub, occurs_on__lt=date(2026, 6, 9))

    def queries():
        with CaptureQueriesContext(connection) as ctx:
            rows = [
                (s.student.user.full_name, s.teacher.user.full_name, s.course.name_en)
                for s in services.missing_reports()
            ]
        return len(rows), len(ctx.captured_queries)

    first, *rest = before  # 1, 3 and 8 June
    services.mark_attendance(first, by=world.teacher, student_attendance="present")
    one = queries()
    for session in rest:
        services.mark_attendance(
            session, by=world.teacher, student_attendance="present"
        )
    many = queries()
    assert (one[0], many[0]) == (1, 3)
    assert one[1] == many[1]
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_reports.py`
Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'write_report'` (and `get_report`, `can_read_report`, `missing_reports`, `sessions_queryset`).

- [ ] **Step 3: Implement**

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
from etqan.scheduling.services.generation import generate
from etqan.scheduling.services.generation import generate_horizon
from etqan.scheduling.services.lifecycle import run_lifecycle
from etqan.scheduling.services.rules import Derived
from etqan.scheduling.services.rules import derive
from etqan.scheduling.services.rules import derived
```

with:

```python
from etqan.scheduling.services.generation import generate
from etqan.scheduling.services.generation import generate_horizon
from etqan.scheduling.services.lifecycle import run_lifecycle
from etqan.scheduling.services.reports import can_read_report
from etqan.scheduling.services.reports import get_report
from etqan.scheduling.services.reports import missing_reports
from etqan.scheduling.services.reports import write_report
from etqan.scheduling.services.rules import Derived
from etqan.scheduling.services.rules import derive
from etqan.scheduling.services.rules import derived
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
from etqan.scheduling.services.rules import pause_state
from etqan.scheduling.services.rules import renewal_starts_on
from etqan.scheduling.services.rules import sessions_of
from etqan.scheduling.services.rules import slots_of
from etqan.scheduling.services.rules import subscriptions_queryset
from etqan.scheduling.services.rules import today
```

with:

```python
from etqan.scheduling.services.rules import pause_state
from etqan.scheduling.services.rules import renewal_starts_on
from etqan.scheduling.services.rules import sessions_of
from etqan.scheduling.services.rules import sessions_queryset
from etqan.scheduling.services.rules import slots_of
from etqan.scheduling.services.rules import subscriptions_queryset
from etqan.scheduling.services.rules import today
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
    "add_pause",
    "add_slots",
    "bulk_sessions",
    "cancel_session",
    "cancel_subscription",
    "create_subscription",
```

with:

```python
    "add_pause",
    "add_slots",
    "bulk_sessions",
    "can_read_report",
    "cancel_session",
    "cancel_subscription",
    "create_subscription",
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
    "end_pause",
    "generate",
    "generate_horizon",
    "has_marked_sessions",
    "has_started",
    "has_subscriptions",
    "mark_attendance",
    "pause_state",
    "renew_subscription",
    "renewal_starts_on",
    "restore_session",
    "run_lifecycle",
    "sessions_of",
    "slots_of",
    "subscriptions_queryset",
    "today",
```

with:

```python
    "end_pause",
    "generate",
    "generate_horizon",
    "get_report",
    "has_marked_sessions",
    "has_started",
    "has_subscriptions",
    "mark_attendance",
    "missing_reports",
    "pause_state",
    "renew_subscription",
    "renewal_starts_on",
    "restore_session",
    "run_lifecycle",
    "sessions_of",
    "sessions_queryset",
    "slots_of",
    "subscriptions_queryset",
    "today",
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
    "untouched_sessions",
    "update_slot",
    "update_subscription",
]
```

with:

```python
    "untouched_sessions",
    "update_slot",
    "update_subscription",
    "write_report",
]
```

Create `backend/etqan/scheduling/services/reports.py`:

```python
"""Session reports: staff-only notes on completed sessions (Plan 5 spec §4.5,
P5-2). Only the session's teacher and admins read or write them."""

from datetime import timedelta

from django.db import transaction
from django.db.models import QuerySet

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import role_of
from etqan.scheduling import dates
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionReport
from etqan.scheduling.services import rules
from etqan.scheduling.services.attendance import lock

SCALE = range(1, 6)  # 1 = poor … 5 = excellent (P5-7)
# A completed session needs its report within a day of ending (spec §4.5).
REPORT_DUE_AFTER = timedelta(hours=24)


def can_read_report(user, session: Session) -> bool:
    """Admins, and the teacher of this very session (P5-2). The one rule for
    reading and writing a report and for seeing ``has_report``."""
    role = role_of(user)
    if role == "admin":
        return True
    return role == "teacher" and session.teacher.user_id == user.pk


def get_report(session: Session) -> SessionReport | None:
    return (
        SessionReport.objects.select_related("written_by")
        .filter(session=session)
        .first()
    )


def _scale(value: int, field: str) -> int:
    if value not in SCALE:
        raise ValidationError("Choose from 1 (poor) to 5 (excellent).", field=field)
    return value


@transaction.atomic
def write_report(
    session: Session, *, by, behaviour: int, participation: int, notes: str = ""
) -> SessionReport:
    """Create or replace the report (PUT). The first writer is kept in
    ``written_by``; an edit only moves ``updated_at``. The session row is
    locked, so two first writes at once make one report."""
    behaviour = _scale(behaviour, "behaviour")
    participation = _scale(participation, "participation")
    locked = lock(session)
    if locked.status != Session.Status.COMPLETED:
        raise ConflictError(
            "A report is written once the session is completed.",
            code="scheduling.not_completed",
        )
    report = SessionReport.objects.filter(session=locked).first()
    if report is None:
        return SessionReport.objects.create(
            session=locked,
            behaviour=behaviour,
            participation=participation,
            notes=notes,
            written_by=by,
        )
    report.behaviour = behaviour
    report.participation = participation
    report.notes = notes
    report.save(update_fields=["behaviour", "participation", "notes", "updated_at"])
    return report


def missing_reports() -> QuerySet[Session]:
    """Completed sessions that ended more than 24 hours ago with no report,
    oldest first (spec §4.5). A cancelled session is never completed, so it
    is never missing one. One query, filtered in SQL."""
    return (
        rules.sessions_queryset()
        .filter(status=Session.Status.COMPLETED, has_report=False)
        .alias(ends_at=rules.ENDS_AT)
        .filter(ends_at__lt=dates.now() - REPORT_DUE_AFTER)
        .order_by("starts_at", "id")
    )
```

In `backend/etqan/scheduling/services/rules.py`, replace:

```python
from datetime import timedelta

from django.db.models import Count
from django.db.models import Exists
from django.db.models import OuterRef
from django.db.models import Q
from django.db.models import QuerySet
from django.db.models import Subquery
from django.db.models import prefetch_related_objects

from etqan.academy import services as academy_services
```

with:

```python
from datetime import timedelta

from django.db.models import Count
from django.db.models import DateTimeField
from django.db.models import Exists
from django.db.models import ExpressionWrapper
from django.db.models import F
from django.db.models import OuterRef
from django.db.models import Q
from django.db.models import QuerySet
from django.db.models import Subquery
from django.db.models import Value
from django.db.models import prefetch_related_objects

from etqan.academy import services as academy_services
```

In `backend/etqan/scheduling/services/rules.py`, replace:

```python
from etqan.scheduling import dates
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionPause

```

with:

```python
from etqan.scheduling import dates
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionReport
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionPause

```

In `backend/etqan/scheduling/services/rules.py`, replace:

```python
# ── Session rows ─────────────────────────────────────────────────────────────

SESSION_RELATED = ("student__user", "teacher__user", "course")


# ── Status ───────────────────────────────────────────────────────────────────
```

with:

```python
# ── Session rows ─────────────────────────────────────────────────────────────

SESSION_RELATED = ("student__user", "teacher__user", "course")
# When a session ends: its UTC start plus its minutes, in SQL.
ENDS_AT = ExpressionWrapper(
    F("starts_at") + F("minutes") * Value(timedelta(minutes=1)),
    output_field=DateTimeField(),
)


def sessions_queryset() -> QuerySet[Session]:
    """Sessions with everything a row shows, in one query: the people and
    course joined, and ``has_report`` as an EXISTS."""
    report = SessionReport.objects.filter(session=OuterRef("pk"))
    return Session.objects.select_related(*SESSION_RELATED).annotate(
        has_report=Exists(report)
    )


# ── Status ───────────────────────────────────────────────────────────────────
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling`
Expected: PASS.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): session reports and missing reports

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: API: the session list, filters, CSV and detail

**Files:**
- Create: `backend/etqan/scheduling/api/session_views.py`
- Modify: `backend/etqan/scheduling/api/payloads.py`, `backend/etqan/scheduling/api/serializers.py`, `backend/etqan/scheduling/api/urls.py`, `backend/etqan/scheduling/api/views.py`, `backend/etqan/scheduling/services/__init__.py`, `backend/etqan/scheduling/services/generation.py`, `backend/etqan/scheduling/services/rules.py`
- Test: `backend/etqan/scheduling/tests/test_api_sessions.py` (new)

**Interfaces:**
- Consumes: Task 3's `has_started`; Task 5's `sessions_queryset`, `can_read_report`, `ENDS_AT`.
- Produces: `rules.filter_sessions(sessions, *, when="", from_date=None, to_date=None, status="", student_attendance="", teacher=None, student=None, course=None, subscription=None, q="") -> QuerySet` (re-exported); `rules.WHEN = ("upcoming", "past", "today", "week")`; `sessions_of(sub, when)` now delegates to it (D1).
- Produces: `payloads.session_row(session, *, viewer) -> dict` (D10) — `viewer` is the signed-in user, keyword-only, no default; `payloads.generation_result(result, *, viewer)`.
- Produces: `etqan.scheduling.api.session_views` with `sessions_in_scope(request)`, `session_or_404(request, pk)`, `SessionListView`, `SessionDetailView`; `serializers.SessionFilterInput` (validated keys: `when`, `from_date`, `to_date`, `status`, `student_attendance`, `teacher`, `student`, `course`, `subscription`, `q`).
- Routes: `GET /api/v1/sessions/` (paginated; `?format=csv` admin-only) and `GET /api/v1/sessions/<id>/`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/scheduling/tests/test_api_sessions.py`:

```python
import csv
import io
from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.db.models import Max
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.academy import services as academy_services
from etqan.identity import services as identity_services
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots
from etqan.scheduling.tests.conftest import until_pk_exceeds

URL = "/api/v1/sessions/"
JUNE = {day: date(2026, 6, day) for day in range(1, 31)}


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


def on(sub, day):
    return Session.objects.get(subscription=sub, occurs_on=day)


def days(resp):
    assert resp.status_code == 200, resp.json()
    return [row["occurs_on"] for row in resp.json()["results"]]


@pytest.fixture
def admin():
    return as_user(make_admin())


# ── The list and its filters ─────────────────────────────────────────────────


def test_admin_lists_every_session_in_time_order(admin, subscribe):
    subscribe(slots=two_slots())
    assert days(admin.get(URL)) == [
        "2026-06-01",
        "2026-06-03",
        "2026-06-08",
        "2026-06-10",
        "2026-06-15",
    ]


def test_filters(admin, subscribe, world, clock):
    mine = subscribe(slots=two_slots())
    maryam = make_teacher("Maryam")
    world.course.teachers.add(maryam.teacher_profile)
    aisha = subscribe(
        student_id=make_student("Aisha").id,
        teacher_id=maryam.id,
        slots=[{"weekdays": [1], "start_time": "10:00"}],
    )
    clock.set(datetime(2026, 6, 3, 19, tzinfo=UTC))
    services.mark_attendance(
        on(mine, JUNE[1]), by=world.teacher, student_attendance="absent"
    )
    services.cancel_session(on(mine, JUNE[3]), by=make_admin("Huda"), reason="Eid")
    cases = {
        "from=2026-06-08&to=2026-06-10": [
            "2026-06-08",
            "2026-06-09",
            "2026-06-10",
        ],
        "status=cancelled": ["2026-06-03"],
        "student_attendance=absent": ["2026-06-01"],
        f"teacher={maryam.id}": ["2026-06-02", "2026-06-09"],
        f"student={world.student.id}&from=2026-06-09": ["2026-06-10", "2026-06-15"],
        f"subscription={aisha.pk}": ["2026-06-02", "2026-06-09"],
        f"course={world.course.pk}&to=2026-06-02": ["2026-06-01", "2026-06-02"],
        "q=aish": ["2026-06-02", "2026-06-09"],
    }
    for query, expected in cases.items():
        assert days(admin.get(f"{URL}?{query}")) == expected, query


@pytest.mark.parametrize(
    ("query", "field"),
    [
        ("when=tomorrow", "when"),
        ("from=yesterday", "from"),
        ("status=done", "status"),
        ("student_attendance=late", "student_attendance"),
        ("teacher=x", "teacher"),
    ],
)
def test_a_bad_filter_is_a_field_error(admin, query, field):
    resp = admin.get(f"{URL}?{query}")
    assert resp.status_code == 400
    assert field in resp.json()


def test_when_upcoming_keeps_a_session_in_progress(admin, subscribe, clock):
    subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 3, 18, 30, tzinfo=UTC))  # Wednesday's is running
    assert days(admin.get(f"{URL}?when=upcoming"))[0] == "2026-06-03"
    # Past: ended ones, latest first.
    assert days(admin.get(f"{URL}?when=past")) == ["2026-06-01"]
    clock.set(datetime(2026, 6, 3, 18, 45, tzinfo=UTC))
    assert days(admin.get(f"{URL}?when=past")) == ["2026-06-03", "2026-06-01"]


def test_today_and_week_are_the_academys_calendar(admin, subscribe, clock):
    academy_services.update_settings(timezone="Asia/Riyadh")
    subscribe(slots=two_slots())
    # 22:00 UTC on Tuesday 2 June is already Wednesday 3 June in Riyadh.
    clock.set(datetime(2026, 6, 2, 22, tzinfo=UTC))
    assert days(admin.get(f"{URL}?when=today")) == ["2026-06-03"]
    assert days(admin.get(f"{URL}?when=week")) == ["2026-06-03", "2026-06-08"]


# ── What each viewer sees ────────────────────────────────────────────────────


def test_admin_rows_carry_staff_fields_and_the_students_clock(admin, subscribe):
    sub = subscribe(slots=two_slots())
    Session.objects.filter(pk=on(sub, JUNE[1]).pk).update(notes="Bring the book")
    row = admin.get(URL).json()["results"][0]
    assert row["notes"] == "Bring the book"
    assert (row["cancel_reason"], row["has_report"], row["has_started"]) == (
        "",
        False,
        False,
    )
    assert row["student"] == {
        "id": sub.student.user_id,
        "full_name": "Yusuf",
        "timezone": "Asia/Riyadh",
    }
    assert row["starts_at"] == "2026-06-01T18:00:00Z"
    assert (row["meeting_url"], row["minutes"]) == ("https://meet.test/bilal", 45)


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_non_admins_never_see_staff_fields(subscribe, world, role):
    subscribe(slots=two_slots())
    user = {"teacher": world.teacher, "student": world.student}.get(role)
    if user is None:
        user = identity_services.create_person("parent", full_name="Omar")
        identity_services.link_guardian(user, world.student)
    rows = as_user(user).get(URL).json()["results"]
    assert len(rows) == 5
    for row in rows:
        assert "notes" not in row
        assert "cancel_reason" not in row
        # Only the session's own teacher (and admins) learn whether a report exists.
        assert ("has_report" in row) is (role == "teacher")


def test_each_role_reads_only_its_sessions(subscribe, world):
    mine = subscribe(slots=two_slots())
    maryam = make_teacher("Maryam")
    world.course.teachers.add(maryam.teacher_profile)
    theirs = subscribe(
        student_id=make_student("Aisha").id,
        teacher_id=maryam.id,
        slots=[{"weekdays": [1], "start_time": "10:00"}],
    )
    parent = identity_services.create_person("parent", full_name="Omar")
    identity_services.link_guardian(parent, world.student)
    my_ids = set(Session.objects.filter(subscription=mine).values_list("pk", flat=True))
    their_ids = set(
        Session.objects.filter(subscription=theirs).values_list("pk", flat=True)
    )
    cases = [
        (world.student, my_ids),
        (parent, my_ids),
        (world.teacher, my_ids),
        (maryam, their_ids),
        (make_teacher("Kareem"), set()),
    ]
    for user, visible in cases:
        client = as_user(user)
        rows = client.get(f"{URL}?page_size=100").json()["results"]
        assert {row["id"] for row in rows} == visible, user.full_name
        for pk in (min(my_ids), min(their_ids)):
            expected = 200 if pk in visible else 404
            assert client.get(f"{URL}{pk}/").status_code == expected, user.full_name


def test_a_teacher_keeps_the_sessions_they_taught_after_a_teacher_change(
    subscribe, world, clock
):
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 2, 9, tzinfo=UTC))
    services.mark_attendance(
        on(sub, JUNE[1]), by=world.teacher, student_attendance="present"
    )
    maryam = make_teacher("Maryam")
    world.course.teachers.add(maryam.teacher_profile)
    services.update_subscription(sub, teacher_id=maryam.id)
    bilal, new = as_user(world.teacher), as_user(maryam)
    assert days(bilal.get(URL)) == ["2026-06-01"]
    assert "2026-06-01" not in days(new.get(URL))
    # The subscription's own session list follows the same rule.
    nested = f"/api/v1/subscriptions/{sub.pk}/sessions/"
    assert "2026-06-01" not in days(new.get(nested))
    assert days(new.get(nested))[0] == "2026-06-03"


def test_anonymous_is_refused():
    client = APIClient()
    assert client.get(URL).status_code == 403
    assert client.get(f"{URL}1/").status_code == 403


def test_the_list_is_read_only(admin, subscribe):
    session = on(subscribe(slots=two_slots()), JUNE[1])
    assert admin.post(URL, {}, format="json").status_code == 405
    assert admin.put(f"{URL}{session.pk}/", {}, format="json").status_code == 405
    assert admin.delete(f"{URL}{session.pk}/").status_code == 405


# ── CSV ──────────────────────────────────────────────────────────────────────


def test_csv_has_the_filtered_rows_for_admins_only(admin, subscribe, world):
    sub = subscribe(slots=two_slots())
    resp = admin.get(f"{URL}?format=csv&to=2026-06-03")
    assert resp.status_code == 200
    assert resp["Content-Disposition"] == 'attachment; filename="sessions.csv"'
    rows = list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))
    assert rows[0][:3] == ["ID", "Date", "Starts at (UTC)"]
    assert [row[0] for row in rows[1:]] == [
        str(on(sub, JUNE[1]).pk),
        str(on(sub, JUNE[3]).pk),
    ]
    assert rows[1][4:7] == ["Yusuf", "Bilal", "Tajweed"]
    teacher = as_user(world.teacher).get(f"{URL}?format=csv")
    assert teacher.status_code == 403
    assert teacher["Content-Type"].startswith("application/json")


# ── Cost and isolation ───────────────────────────────────────────────────────


def test_the_list_costs_the_same_queries_for_two_or_six_rows(admin, subscribe):
    subscribe(slots=two_slots())
    for n in range(2):
        subscribe(student_id=make_student(f"S{n}").id, slots=two_slots())

    def queries(query):
        with CaptureQueriesContext(connection) as ctx:
            rows = admin.get(f"{URL}?{query}").json()["results"]
        return len(rows), len(ctx.captured_queries)

    two, six = queries("to=2026-06-01&page_size=2"), queries("to=2026-06-03")
    assert (two[0], six[0]) == (2, 6)
    assert two[1] == six[1]


def test_another_academy_never_leaks(admin, subscribe, tenants):
    mine = subscribe(slots=two_slots())
    ceiling = Session.objects.aggregate(m=Max("pk"))["m"]
    with tenant_context(tenants.other):
        world = build_world()
        identity_services.update_person(
            world.student, fields={"full_name": "Layla Other"}
        )
        sub = until_pk_exceeds(
            Session, ceiling, lambda: subscription_for(world, slots=two_slots())
        )
        theirs = Session.objects.filter(subscription=sub).order_by("pk").first()
    assert theirs.pk > ceiling
    listed = admin.get(f"{URL}?page_size=100").json()["results"]
    mine_ids = set(
        Session.objects.filter(subscription=mine).values_list("pk", flat=True)
    )
    assert {row["id"] for row in listed} == mine_ids
    for path in (URL, f"{URL}?format=csv", f"{URL}?q=layla"):
        assert b"Layla Other" not in admin.get(path).content, path
    assert admin.get(f"{URL}{theirs.pk}/").status_code == 404
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_api_sessions.py`
Expected: FAIL — `/api/v1/sessions/` answers 404 (no route), and the nested list still shows the previous teacher's session to the new teacher.

- [ ] **Step 3: Implement**

In `backend/etqan/scheduling/api/payloads.py`, replace:

```python
hiding staff notes from non-admins (see `etqan.identity.api.payloads`).
"""

from etqan.scheduling import dates
from etqan.scheduling import services

```

with:

```python
hiding staff notes from non-admins (see `etqan.identity.api.payloads`).
"""

from etqan.platform.permissions import role_of
from etqan.scheduling import dates
from etqan.scheduling import services

```

In `backend/etqan/scheduling/api/payloads.py`, replace:

```python
    return detail


def session_row(session) -> dict:
    return {
        "id": session.pk,
        "subscription_id": session.subscription_id,
        "slot_id": session.slot_id,
```

with:

```python
    return detail


STAFF_ONLY_SESSION_FIELDS = ("notes", "cancel_reason")


def session_row(session, *, viewer) -> dict:
    """Plan 5 spec §4.6: everyone in scope sees the times, link, status and
    both attendances; ``notes`` and ``cancel_reason`` are admin-only, and
    ``has_report`` is for admins and the session's own teacher. ``viewer`` is
    the signed-in user and has no default, so a caller can't forget it. Read
    ``session`` from `services.sessions_queryset()` (it carries
    ``has_report``)."""
    row = {
        "id": session.pk,
        "subscription_id": session.subscription_id,
        "slot_id": session.slot_id,
```

In `backend/etqan/scheduling/api/payloads.py`, replace:

```python
        "status": session.status,
        "student_attendance": session.student_attendance,
        "teacher_attendance": session.teacher_attendance,
        "meeting_url": session.meeting_url,
        "generated": session.generated,
        "student": _person(session.student),
        "teacher": _person(session.teacher),
        "course": _named(session.course),
    }


def generation_result(result: services.GenerationResult) -> dict:
    return {
        "created": result.created,
        "skipped_existing": result.skipped_existing,
        "skipped_paused": result.skipped_paused,
        "skipped_out_of_term": result.skipped_out_of_term,
        "conflicts": [
            {"session": session_row(session), "other": session_row(other)}
            for session, other in result.conflicts
        ],
    }
```

with:

```python
        "status": session.status,
        "student_attendance": session.student_attendance,
        "teacher_attendance": session.teacher_attendance,
        "has_started": services.has_started(session),
        "meeting_url": session.meeting_url,
        "generated": session.generated,
        "student": _student(session.student),
        "teacher": _person(session.teacher),
        "course": _named(session.course),
        "notes": session.notes,
        "cancel_reason": session.cancel_reason,
        "has_report": session.has_report,
    }
    if role_of(viewer) != "admin":
        for field in STAFF_ONLY_SESSION_FIELDS:
            row.pop(field)
    if not services.can_read_report(viewer, session):
        row.pop("has_report")
    return row


def generation_result(result: services.GenerationResult, *, viewer) -> dict:
    return {
        "created": result.created,
        "skipped_existing": result.skipped_existing,
        "skipped_paused": result.skipped_paused,
        "skipped_out_of_term": result.skipped_out_of_term,
        "conflicts": [
            {
                "session": session_row(session, viewer=viewer),
                "other": session_row(other, viewer=viewer),
            }
            for session, other in result.conflicts
        ],
    }
```

In `backend/etqan/scheduling/api/serializers.py`, replace:

```python

from rest_framework import serializers


def _id(**kwargs):
    return serializers.IntegerField(min_value=1, **kwargs)
```

with:

```python

from rest_framework import serializers

from etqan.scheduling.models import Session


def _id(**kwargs):
    return serializers.IntegerField(min_value=1, **kwargs)
```

Append to the end of `backend/etqan/scheduling/api/serializers.py`:

```python
class SessionFilterInput(serializers.Serializer):
    """The session list's query (spec §5). A bad value is a field error rather
    than a filter silently dropped."""

    when = serializers.ChoiceField(
        choices=("upcoming", "past", "today", "week"), required=False
    )
    to = serializers.DateField(required=False)
    status = serializers.ChoiceField(choices=Session.Status.values, required=False)
    student_attendance = serializers.ChoiceField(
        choices=Session.Attendance.values, required=False
    )
    teacher = _id(required=False)
    student = _id(required=False)
    course = _id(required=False)
    subscription = _id(required=False)
    q = serializers.CharField(required=False, allow_blank=True)

    def get_fields(self):
        fields = super().get_fields()
        fields["from"] = serializers.DateField(required=False)
        return fields

    def validate(self, attrs):
        attrs["from_date"] = attrs.pop("from", None)
        attrs["to_date"] = attrs.pop("to", None)
        return attrs
```

Create `backend/etqan/scheduling/api/session_views.py`:

```python
"""Session and report endpoints (Plan 5 spec §5). Thin: parse, call one
service, re-read the session and arrange its payload."""

from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import IsAdmin
from etqan.platform.permissions import ReadOnly
from etqan.platform.permissions import role_of
from etqan.scheduling import services
from etqan.scheduling.api import payloads
from etqan.scheduling.api.serializers import SessionFilterInput
from etqan.scheduling.models import Session
from etqan.scheduling.scopes import scope_for

CSV_COLUMNS = (
    ("id", "ID"),
    ("occurs_on", "Date"),
    ("starts_at", "Starts at (UTC)"),
    ("minutes", "Minutes"),
    ("student", "Student"),
    ("teacher", "Teacher"),
    ("course", "Course"),
    ("status", "Status"),
    ("student_attendance", "Student attendance"),
    ("teacher_attendance", "Teacher attendance"),
    ("has_report", "Report"),
    ("cancel_reason", "Cancel reason"),
)


def sessions_in_scope(request):
    return scope_for(request.user, services.sessions_queryset())


def session_or_404(request, pk) -> Session:
    return get_object_or_404(sessions_in_scope(request), pk=pk)


class SessionListView(CSVExportMixin, generics.GenericAPIView):
    permission_classes = [IsAdmin | ReadOnly]
    csv_filename = "sessions"
    csv_columns = CSV_COLUMNS

    def get(self, request):
        query = SessionFilterInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        sessions = services.filter_sessions(
            sessions_in_scope(request), **query.validated_data
        )
        if self.wants_csv():
            # Raised, not returned: the mixin answers the error as JSON.
            if role_of(request.user) != "admin":
                raise PermissionDenied("CSV export is for admins only.")
            return self.csv_response(
                [payloads.session_row(s, viewer=request.user) for s in sessions]
            )
        page = self.paginate_queryset(sessions)
        return self.get_paginated_response(
            [payloads.session_row(s, viewer=request.user) for s in page]
        )


class SessionDetailView(APIView):
    permission_classes = [IsAdmin | ReadOnly]

    def get(self, request, pk):
        session = session_or_404(request, pk)
        return Response(payloads.session_row(session, viewer=request.user))
```

In `backend/etqan/scheduling/api/urls.py`, replace:

```python
from django.urls import path

from etqan.scheduling.api import views

app_name = "scheduling"
```

with:

```python
from django.urls import path

from etqan.scheduling.api import session_views
from etqan.scheduling.api import views

app_name = "scheduling"
```

In `backend/etqan/scheduling/api/urls.py`, replace:

```python
    path("slots/<int:pk>/", views.SlotDetailView.as_view(), name="slot"),
    path("schedule/generate/", views.GenerateView.as_view(), name="generate"),
    path("schedule/today/", views.TodayView.as_view(), name="today"),
]
```

with:

```python
    path("slots/<int:pk>/", views.SlotDetailView.as_view(), name="slot"),
    path("schedule/generate/", views.GenerateView.as_view(), name="generate"),
    path("schedule/today/", views.TodayView.as_view(), name="today"),
    # Plan 5 (spec §5)
    path("sessions/", session_views.SessionListView.as_view(), name="session-list"),
    path(
        "sessions/<int:pk>/",
        session_views.SessionDetailView.as_view(),
        name="session-detail",
    ),
]
```

In `backend/etqan/scheduling/api/views.py`, replace:

```python
        query = SessionQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        when = query.validated_data.get("when", "")
        page = self.paginate_queryset(services.sessions_of(sub, when))
        return self.get_paginated_response([payloads.session_row(s) for s in page])


class GenerateView(APIView):
```

with:

```python
        query = SessionQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        when = query.validated_data.get("when", "")
        # Plan 5: a teacher sees only the sessions they teach, also here (a
        # subscription's earlier sessions may belong to its previous teacher).
        sessions = scope_for(request.user, services.sessions_of(sub, when))
        page = self.paginate_queryset(sessions)
        return self.get_paginated_response(
            [payloads.session_row(s, viewer=request.user) for s in page]
        )


class GenerateView(APIView):
```

In `backend/etqan/scheduling/api/views.py`, replace:

```python
        if "subscription" in data:
            sub = subscription_or_404(request, data["subscription"])
        result = services.generate(data["from"], data["to"], subscription=sub)
        return Response(payloads.generation_result(result))


class TodayView(APIView):
```

with:

```python
        if "subscription" in data:
            sub = subscription_or_404(request, data["subscription"])
        result = services.generate(data["from"], data["to"], subscription=sub)
        return Response(payloads.generation_result(result, viewer=request.user))


class TodayView(APIView):
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
from etqan.scheduling.services.rules import Derived
from etqan.scheduling.services.rules import derive
from etqan.scheduling.services.rules import derived
from etqan.scheduling.services.rules import has_marked_sessions
from etqan.scheduling.services.rules import has_subscriptions
from etqan.scheduling.services.rules import pause_state
```

with:

```python
from etqan.scheduling.services.rules import Derived
from etqan.scheduling.services.rules import derive
from etqan.scheduling.services.rules import derived
from etqan.scheduling.services.rules import filter_sessions
from etqan.scheduling.services.rules import has_marked_sessions
from etqan.scheduling.services.rules import has_subscriptions
from etqan.scheduling.services.rules import pause_state
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
    "derive",
    "derived",
    "end_pause",
    "generate",
    "generate_horizon",
    "get_report",
```

with:

```python
    "derive",
    "derived",
    "end_pause",
    "filter_sessions",
    "generate",
    "generate_horizon",
    "get_report",
```

In `backend/etqan/scheduling/services/generation.py`, replace:

```python
    if not created:
        return []
    others = (
        Session.objects.exclude(status=Session.Status.CANCELLED)
        .filter(
            teacher_id__in={s.teacher_id for s in created},
            starts_at__gte=min(s.starts_at for s in created) - MAX_SESSION,
            starts_at__lt=max(ends_at(s) for s in created),
        )
        .select_related(*rules.SESSION_RELATED)
    )
    by_teacher = defaultdict(list)
    for other in others:
```

with:

```python
    if not created:
        return []
    others = (
        rules.sessions_queryset()
        .exclude(status=Session.Status.CANCELLED)
        .filter(
            teacher_id__in={s.teacher_id for s in created},
            starts_at__gte=min(s.starts_at for s in created) - MAX_SESSION,
            starts_at__lt=max(ends_at(s) for s in created),
        )
    )
    by_teacher = defaultdict(list)
    for other in others:
```

In `backend/etqan/scheduling/services/generation.py`, replace:

```python
    attempted = {(s.slot_id, s.occurs_on) for s in new}
    created = [
        s
        for s in Session.objects.filter(
            slot__in=slots, occurs_on__range=(first, last)
        ).select_related(*rules.SESSION_RELATED)
        if (s.slot_id, s.occurs_on) in attempted
    ]
    result.created = len(created)
```

with:

```python
    attempted = {(s.slot_id, s.occurs_on) for s in new}
    created = [
        s
        for s in rules.sessions_queryset().filter(
            slot__in=slots, occurs_on__range=(first, last)
        )
        if (s.slot_id, s.occurs_on) in attempted
    ]
    result.created = len(created)
```

In `backend/etqan/scheduling/services/rules.py`, replace:

```python
    return subscription.slots.annotate(has_sessions=Exists(produced))


def sessions_of(subscription: Subscription, when: str = "") -> QuerySet[Session]:
    """``when``: ``upcoming`` (soonest first), ``past`` (latest first) or all."""
    sessions = Session.objects.filter(subscription=subscription).select_related(
        *SESSION_RELATED
    )
    if when == "upcoming":
        return sessions.filter(starts_at__gte=dates.now()).order_by("starts_at", "id")
    if when == "past":
        return sessions.filter(starts_at__lt=dates.now()).order_by("-starts_at", "-id")
    return sessions.order_by("starts_at", "id")


def pause_state(pause: SubscriptionPause, day: date) -> str:
    if day < pause.from_date:
        return "upcoming"
```

with:

```python
    return subscription.slots.annotate(has_sessions=Exists(produced))


WHEN = ("upcoming", "past", "today", "week")


def _when(sessions: QuerySet[Session], when: str) -> QuerySet[Session]:
    """``upcoming``: not yet ended, soonest first (a session in progress still
    shows its link); ``past``: ended, latest first; ``today`` and ``week``
    (today and the next six days) on the academy's calendar. Anything else:
    every session, soonest first."""
    now = dates.now()
    if when == "upcoming":
        return (
            sessions.alias(ends_at=ENDS_AT)
            .filter(ends_at__gt=now)
            .order_by("starts_at", "id")
        )
    if when == "past":
        return (
            sessions.alias(ends_at=ENDS_AT)
            .filter(ends_at__lte=now)
            .order_by("-starts_at", "-id")
        )
    if when in ("today", "week"):
        first = today()
        last = first + timedelta(days=6 if when == "week" else 0)
        sessions = sessions.filter(occurs_on__range=(first, last))
    return sessions.order_by("starts_at", "id")


def filter_sessions(  # noqa: PLR0913 -- keyword-only; mirrors the list's query (spec §5)
    sessions: QuerySet[Session],
    *,
    when: str = "",
    from_date: date | None = None,
    to_date: date | None = None,
    status: str = "",
    student_attendance: str = "",
    teacher: int | None = None,
    student: int | None = None,
    course: int | None = None,
    subscription: int | None = None,
    q: str = "",
) -> QuerySet[Session]:
    """The session list's filters (spec §5). ``from_date``/``to_date`` are
    academy-local dates; people are User ids, as everywhere in the API."""
    exact = {
        "occurs_on__gte": from_date,
        "occurs_on__lte": to_date,
        "status": status,
        "student_attendance": student_attendance,
        "teacher__user_id": teacher,
        "student__user_id": student,
        "course_id": course,
        "subscription_id": subscription,
    }
    sessions = sessions.filter(
        **{key: value for key, value in exact.items() if value not in (None, "")}
    )
    if q := q.strip():
        sessions = sessions.filter(student__user__full_name__icontains=q)
    return _when(sessions, when)


def sessions_of(subscription: Subscription, when: str = "") -> QuerySet[Session]:
    """A subscription's sessions; ``when`` as in `filter_sessions`."""
    return filter_sessions(
        sessions_queryset().filter(subscription=subscription), when=when
    )


def pause_state(pause: SubscriptionPause, day: date) -> str:
    if day < pause.from_date:
        return "upcoming"
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling`
Expected: PASS, Plan 4's schedule and subscription API tests included.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): session list with filters, CSV and detail

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: API: attendance, cancel, restore, bulk, report and missing reports

**Files:**
- Modify: `backend/etqan/scheduling/api/payloads.py`, `backend/etqan/scheduling/api/serializers.py`, `backend/etqan/scheduling/api/session_views.py`, `backend/etqan/scheduling/api/urls.py`, `backend/etqan/scheduling/services/attendance.py`
- Test: `backend/etqan/scheduling/tests/test_api_session_writes.py` (new)

**Interfaces:**
- Consumes: Tasks 3–6.
- Produces routes (plan D8, D18):
  - `POST sessions/<id>/attendance/` `{student_attendance?, teacher_attendance?}` → session row (admin or the session's teacher).
  - `POST sessions/<id>/cancel/` `{reason}` and `POST sessions/<id>/restore/` → session row (admin).
  - `POST sessions/bulk/` `{ids, action, reason?}` → `{done: [id], skipped: [{id, code}]}` (admin).
  - `GET, PUT sessions/<id>/report/` → `{session, behaviour, participation, notes, written_by: {id, full_name}, created_at, updated_at}`; GET is 404 when none is written.
  - `GET reports/missing/` → paginated session rows (admin: all; teacher: own).
- Produces: `session_views.session_payload(request, pk) -> dict` (the fresh re-read every write answers with); `payloads.bulk_result`, `payloads.report_payload`; serializers `AttendanceInput`, `CancelSessionInput`, `BulkInput`, `ReportInput`.
- Changes: `bulk_sessions` becomes `@transaction.atomic` and locks every requested row up front (D5).

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/scheduling/tests/test_api_session_writes.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.db.models import Max
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.identity import services as identity_services
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots
from etqan.scheduling.tests.conftest import until_pk_exceeds

URL = "/api/v1/sessions/"
MISSING = "/api/v1/reports/missing/"
JUNE = {day: date(2026, 6, day) for day in range(1, 31)}


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


def on(sub, day):
    return Session.objects.get(subscription=sub, occurs_on=day)


@pytest.fixture
def started(subscribe, clock):
    """Monday 1 June's session, just after it started."""
    session = on(subscribe(slots=two_slots()), JUNE[1])
    clock.set(datetime(2026, 6, 1, 18, 5, tzinfo=UTC))
    return session


@pytest.fixture
def admin():
    return as_user(make_admin())


# ── Attendance ───────────────────────────────────────────────────────────────


def test_the_teacher_marks_their_session(started, world):
    resp = as_user(world.teacher).post(
        f"{URL}{started.pk}/attendance/",
        {"student_attendance": "present", "teacher_attendance": "present"},
        format="json",
    )
    body = resp.json()
    assert resp.status_code == 200, body
    assert (body["status"], body["student_attendance"]) == ("completed", "present")
    assert (body["teacher_attendance"], body["has_report"]) == ("present", False)
    started.refresh_from_db()
    assert started.marked_by == world.teacher


def test_attendance_before_the_start_is_a_coded_conflict(subscribe, world):
    session = on(subscribe(slots=two_slots()), JUNE[1])
    resp = as_user(world.teacher).post(
        f"{URL}{session.pk}/attendance/",
        {"student_attendance": "present"},
        format="json",
    )
    assert resp.status_code == 409
    assert resp.json() == {
        "detail": "Attendance opens when the session starts.",
        "code": "scheduling.not_started",
    }


def test_a_teacher_cannot_mark_someone_elses_session(started, world):
    maryam = make_teacher("Maryam")
    resp = as_user(maryam).post(
        f"{URL}{started.pk}/attendance/",
        {"student_attendance": "absent"},
        format="json",
    )
    assert resp.status_code == 404
    started.refresh_from_db()
    assert started.student_attendance == "not_set"


@pytest.mark.parametrize(
    ("body", "field"),
    [
        ({}, "student_attendance"),
        ({"student_attendance": "late"}, "student_attendance"),
        ({"teacher_attendance": ""}, "teacher_attendance"),
    ],
)
def test_attendance_bodies_are_checked(started, admin, body, field):
    resp = admin.post(f"{URL}{started.pk}/attendance/", body, format="json")
    assert resp.status_code == 400
    assert field in resp.json()


def test_only_an_admin_clears_the_students_attendance(started, world, admin):
    teacher = as_user(world.teacher)
    path = f"{URL}{started.pk}/attendance/"
    teacher.post(path, {"student_attendance": "absent"}, format="json")
    refused = teacher.post(path, {"student_attendance": "not_set"}, format="json")
    assert refused.status_code == 403
    cleared = admin.post(path, {"student_attendance": "not_set"}, format="json")
    assert cleared.status_code == 200
    assert (cleared.json()["status"], cleared.json()["student_attendance"]) == (
        "scheduled",
        "not_set",
    )


# ── Cancel and restore ───────────────────────────────────────────────────────


def test_admin_cancels_with_a_reason_and_restores(started, admin, world):
    path = f"{URL}{started.pk}/"
    no_reason = admin.post(f"{path}cancel/", {"reason": " "}, format="json")
    assert (no_reason.status_code, list(no_reason.json())) == (400, ["reason"])
    cancelled = admin.post(f"{path}cancel/", {"reason": "Eid"}, format="json").json()
    assert (cancelled["status"], cancelled["cancel_reason"]) == ("cancelled", "Eid")
    marking = as_user(world.teacher).post(
        f"{path}attendance/", {"student_attendance": "present"}, format="json"
    )
    assert marking.status_code == 409
    assert marking.json()["code"] == "scheduling.session_cancelled"
    restored = admin.post(f"{path}restore/").json()
    assert (restored["status"], restored["cancel_reason"]) == ("scheduled", "")
    again = admin.post(f"{path}restore/")
    assert again.status_code == 409
    assert again.json()["code"] == "scheduling.not_allowed_in_status"


# ── Bulk ─────────────────────────────────────────────────────────────────────


def test_bulk_answers_done_and_skipped_with_codes(subscribe, admin, clock):
    sub = subscribe(slots=two_slots())
    monday, later = on(sub, JUNE[1]), on(sub, JUNE[8])
    clock.set(datetime(2026, 6, 2, 9, tzinfo=UTC))
    ghost = later.pk + 1000
    resp = admin.post(
        f"{URL}bulk/",
        {"ids": [monday.pk, later.pk, ghost], "action": "absent"},
        format="json",
    )
    assert resp.status_code == 200, resp.json()
    assert resp.json() == {
        "done": [monday.pk],
        "skipped": [
            {"id": later.pk, "code": "scheduling.not_started"},
            {"id": ghost, "code": "not_found"},
        ],
    }


@pytest.mark.parametrize(
    ("body", "field"),
    [
        ({"ids": [], "action": "present"}, "ids"),
        ({"ids": list(range(1, 202)), "action": "present"}, "ids"),
        ({"ids": [1], "action": "excused"}, "action"),
        ({"ids": [1], "action": "cancel"}, "reason"),
    ],
)
def test_bulk_bodies_are_checked(admin, body, field):
    resp = admin.post(f"{URL}bulk/", body, format="json")
    assert resp.status_code == 400
    assert field in resp.json()


# ── Reports ──────────────────────────────────────────────────────────────────


def test_the_teacher_writes_the_report_and_an_admin_edits_it(started, world, admin):
    teacher = as_user(world.teacher)
    path = f"{URL}{started.pk}/report/"
    body = {"behaviour": 5, "participation": 4, "notes": "Fluent"}
    early = teacher.put(path, body, format="json")
    assert early.status_code == 409
    assert early.json()["code"] == "scheduling.not_completed"
    assert teacher.get(path).status_code == 404  # none yet
    teacher.post(f"{URL}{started.pk}/attendance/", {"student_attendance": "present"})
    written = teacher.put(path, body, format="json")
    assert written.status_code == 200, written.json()
    assert written.json()["written_by"] == {
        "id": world.teacher.id,
        "full_name": "Bilal",
    }
    edited = admin.put(path, {"behaviour": 3, "participation": 3}, format="json")
    report = edited.json()
    assert (report["behaviour"], report["participation"], report["notes"]) == (
        3,
        3,
        "",
    )
    assert report["written_by"]["id"] == world.teacher.id
    assert teacher.get(path).json()["behaviour"] == 3
    assert admin.get(f"{URL}{started.pk}/").json()["has_report"] is True
    assert teacher.patch(path, body, format="json").status_code == 405


@pytest.mark.parametrize(
    "body",
    [
        {"behaviour": 0, "participation": 3},
        {"behaviour": 3, "participation": 6},
        {"behaviour": 3},
    ],
)
def test_report_scales_are_checked(started, admin, body):
    resp = admin.put(f"{URL}{started.pk}/report/", body, format="json")
    assert resp.status_code == 400


def test_students_and_parents_never_see_a_report(started, world):
    services.mark_attendance(started, by=world.teacher, student_attendance="present")
    services.write_report(started, by=world.teacher, behaviour=4, participation=4)
    parent = identity_services.create_person("parent", full_name="Omar")
    identity_services.link_guardian(parent, world.student)
    for user in (world.student, parent):
        client = as_user(user)
        # They can read the session itself, but its report does not exist
        # for them.
        assert client.get(f"{URL}{started.pk}/").status_code == 200
        assert client.get(f"{URL}{started.pk}/report/").status_code == 404
        put = client.put(
            f"{URL}{started.pk}/report/",
            {"behaviour": 1, "participation": 1},
            format="json",
        )
        assert put.status_code == 404
    assert services.get_report(started).behaviour == 4


# ── Missing reports ──────────────────────────────────────────────────────────


def test_missing_reports_for_admins_and_the_teachers_own(subscribe, world, clock):
    mine = subscribe(slots=two_slots())
    maryam = make_teacher("Maryam")
    world.course.teachers.add(maryam.teacher_profile)
    theirs = subscribe(
        student_id=make_student("Aisha").id,
        teacher_id=maryam.id,
        slots=[{"weekdays": [1], "start_time": "10:00"}],
    )
    clock.set(datetime(2026, 6, 3, 9, tzinfo=UTC))
    services.mark_attendance(
        on(mine, JUNE[1]), by=world.teacher, student_attendance="present"
    )
    services.mark_attendance(
        on(theirs, JUNE[2]), by=maryam, student_attendance="absent"
    )
    clock.set(datetime(2026, 6, 4, 9, tzinfo=UTC))

    def listed(user):
        resp = as_user(user).get(MISSING)
        assert resp.status_code == 200, resp.json()
        return [row["occurs_on"] for row in resp.json()["results"]]

    assert listed(make_admin()) == ["2026-06-01", "2026-06-02"]
    assert listed(world.teacher) == ["2026-06-01"]
    assert listed(maryam) == ["2026-06-02"]
    assert as_user(world.student).get(MISSING).status_code == 403


def test_missing_reports_cost_the_same_queries_for_one_or_three(
    subscribe, world, admin, clock
):
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 10, 9, tzinfo=UTC))
    first, *rest = Session.objects.filter(subscription=sub, occurs_on__lt=JUNE[9])

    def queries():
        with CaptureQueriesContext(connection) as ctx:
            rows = admin.get(MISSING).json()["results"]
        return len(rows), len(ctx.captured_queries)

    services.mark_attendance(first, by=world.teacher, student_attendance="present")
    one = queries()
    for session in rest:
        services.mark_attendance(
            session, by=world.teacher, student_attendance="present"
        )
    many = queries()
    assert (one[0], many[0]) == (1, 3)
    assert one[1] == many[1]


# ── Every role on every route ────────────────────────────────────────────────

ROUTES = [
    ("get", "{url}"),
    ("get", "{url}{id}/"),
    ("post", "{url}{id}/attendance/", {"student_attendance": "present"}),
    ("post", "{url}{id}/cancel/", {"reason": "Eid"}),
    ("post", "{url}{id}/restore/"),
    ("post", "{url}bulk/", {"ids": ["{id}"], "action": "present"}),
    ("get", "{url}{id}/report/"),
    ("put", "{url}{id}/report/", {"behaviour": 4, "participation": 4}),
    ("get", MISSING),
    ("get", "{url}?format=csv"),
]
EXPECTED = {
    "teacher": [200, 200, 200, 403, 403, 403, 200, 200, 200, 403],
    "other teacher": [200, 404, 404, 403, 403, 403, 404, 404, 200, 403],
    "student": [200, 200, 403, 403, 403, 403, 404, 404, 403, 403],
    "parent": [200, 200, 403, 403, 403, 403, 404, 404, 403, 403],
    "anonymous": [403] * len(ROUTES),
}


@pytest.mark.parametrize("role", list(EXPECTED))
def test_every_role_on_every_route(started, world, role):
    services.mark_attendance(started, by=world.teacher, student_attendance="present")
    services.write_report(started, by=world.teacher, behaviour=4, participation=4)
    if role == "parent":
        user = identity_services.create_person("parent", full_name="Omar")
        identity_services.link_guardian(user, world.student)
    else:
        user = {
            "teacher": world.teacher,
            "other teacher": make_teacher("Maryam"),
            "student": world.student,
            "anonymous": None,
        }[role]
    client = as_user(user) if user else APIClient()
    got = []
    for method, template, *body in ROUTES:
        path = template.format(url=URL, id=started.pk)
        data = body[0] if body else {}
        if "ids" in data:
            data = {**data, "ids": [started.pk]}
        got.append(
            getattr(client, method)(path, data or None, format="json").status_code
        )
    assert got == EXPECTED[role]
    started.refresh_from_db()
    assert started.status == "completed"


# ── Another academy ──────────────────────────────────────────────────────────


def test_another_academys_session_is_never_written(started, admin, tenants):
    ceiling = Session.objects.aggregate(m=Max("pk"))["m"]
    with tenant_context(tenants.other):
        other = build_world()
        sub = until_pk_exceeds(
            Session, ceiling, lambda: subscription_for(other, slots=two_slots())
        )
        theirs = Session.objects.filter(subscription=sub).order_by("pk").first()
    assert theirs.pk > ceiling
    for path, body in (
        ("attendance/", {"student_attendance": "present"}),
        ("cancel/", {"reason": "Eid"}),
        ("restore/", {}),
    ):
        assert (
            admin.post(f"{URL}{theirs.pk}/{path}", body, format="json").status_code
            == 404
        )
    assert (
        admin.put(
            f"{URL}{theirs.pk}/report/",
            {"behaviour": 3, "participation": 3},
            format="json",
        ).status_code
        == 404
    )
    with tenant_context(tenants.other):
        theirs.refresh_from_db()
        assert (theirs.status, theirs.student_attendance) == ("scheduled", "not_set")
    # This academy's own session still answers.
    mine = admin.post(
        f"{URL}{started.pk}/attendance/",
        {"student_attendance": "present"},
        format="json",
    )
    assert mine.status_code == 200
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_api_session_writes.py`
Expected: FAIL — every new route answers 404, so `test_every_role_on_every_route` and the write tests fail.

- [ ] **Step 3: Implement**

Append to the end of `backend/etqan/scheduling/api/payloads.py`:

```python
def bulk_result(result: services.BulkResult) -> dict:
    return {
        "done": result.done,
        "skipped": [{"id": pk, "code": code} for pk, code in result.skipped],
    }


def report_payload(report) -> dict:
    return {
        "session": report.session_id,
        "behaviour": report.behaviour,
        "participation": report.participation,
        "notes": report.notes,
        "written_by": {
            "id": report.written_by_id,
            "full_name": report.written_by.full_name,
        },
        "created_at": report.created_at,
        "updated_at": report.updated_at,
    }
```

Append to the end of `backend/etqan/scheduling/api/serializers.py`:

```python
class AttendanceInput(serializers.Serializer):
    student_attendance = serializers.ChoiceField(
        choices=Session.Attendance.values, required=False
    )
    teacher_attendance = serializers.ChoiceField(
        choices=Session.Attendance.values, required=False
    )

    def validate(self, attrs):
        if not attrs:
            raise serializers.ValidationError(
                {"student_attendance": ["Set the student's or the teacher's."]}
            )
        return attrs


class CancelSessionInput(serializers.Serializer):
    reason = serializers.CharField()


class BulkInput(serializers.Serializer):
    ids = serializers.ListField(child=_id(), allow_empty=False, max_length=200)
    action = serializers.ChoiceField(choices=("present", "absent", "cancel"))
    reason = serializers.CharField(required=False, allow_blank=True)

    def validate(self, attrs):
        if attrs["action"] == "cancel" and not attrs.get("reason", "").strip():
            raise serializers.ValidationError({"reason": ["Give a reason."]})
        return attrs


class ReportInput(serializers.Serializer):
    behaviour = serializers.IntegerField(min_value=1, max_value=5)
    participation = serializers.IntegerField(min_value=1, max_value=5)
    notes = serializers.CharField(required=False, allow_blank=True)
```

In `backend/etqan/scheduling/api/session_views.py`, replace:

```python
"""Session and report endpoints (Plan 5 spec §5). Thin: parse, call one
service, re-read the session and arrange its payload."""

from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.exceptions import PermissionDenied
```

with:

```python
"""Session and report endpoints (Plan 5 spec §5). Thin: parse, call one
service, re-read the session and arrange its payload."""

from django.http import Http404
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.exceptions import PermissionDenied
```

In `backend/etqan/scheduling/api/session_views.py`, replace:

```python

from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import IsAdmin
from etqan.platform.permissions import ReadOnly
from etqan.platform.permissions import role_of
from etqan.scheduling import services
from etqan.scheduling.api import payloads
from etqan.scheduling.api.serializers import SessionFilterInput
from etqan.scheduling.models import Session
from etqan.scheduling.scopes import scope_for
```

with:

```python

from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import IsAdmin
from etqan.platform.permissions import IsParent
from etqan.platform.permissions import IsStudent
from etqan.platform.permissions import IsTeacher
from etqan.platform.permissions import ReadOnly
from etqan.platform.permissions import role_of
from etqan.scheduling import services
from etqan.scheduling.api import payloads
from etqan.scheduling.api.serializers import AttendanceInput
from etqan.scheduling.api.serializers import BulkInput
from etqan.scheduling.api.serializers import CancelSessionInput
from etqan.scheduling.api.serializers import ReportInput
from etqan.scheduling.api.serializers import SessionFilterInput
from etqan.scheduling.models import Session
from etqan.scheduling.scopes import scope_for
```

In `backend/etqan/scheduling/api/session_views.py`, replace:

```python
    return get_object_or_404(sessions_in_scope(request), pk=pk)


class SessionListView(CSVExportMixin, generics.GenericAPIView):
    permission_classes = [IsAdmin | ReadOnly]
    csv_filename = "sessions"
```

with:

```python
    return get_object_or_404(sessions_in_scope(request), pk=pk)


def session_payload(request, pk) -> dict:
    """The session as it is now: every write answers with a fresh read."""
    session = services.sessions_queryset().get(pk=pk)
    return payloads.session_row(session, viewer=request.user)


class SessionListView(CSVExportMixin, generics.GenericAPIView):
    permission_classes = [IsAdmin | ReadOnly]
    csv_filename = "sessions"
```

Append to the end of `backend/etqan/scheduling/api/session_views.py`:

```python
class AttendanceView(APIView):
    """The session's teacher or an admin; anyone else in scope is refused by
    role, and a teacher's scope holds only their own sessions (404)."""

    permission_classes = [IsAdmin | IsTeacher]

    def post(self, request, pk):
        session = session_or_404(request, pk)
        body = AttendanceInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.mark_attendance(session, by=request.user, **body.validated_data)
        return Response(session_payload(request, pk))


class SessionCancelView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        session = session_or_404(request, pk)
        body = CancelSessionInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.cancel_session(session, by=request.user, **body.validated_data)
        return Response(session_payload(request, pk))


class SessionRestoreView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        services.restore_session(session_or_404(request, pk))
        return Response(session_payload(request, pk))


class SessionBulkView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request):
        body = BulkInput(data=request.data)
        body.is_valid(raise_exception=True)
        result = services.bulk_sessions(by=request.user, **body.validated_data)
        return Response(payloads.bulk_result(result))


# Every signed-in role reaches the check, so a student or parent asking for a
# report gets the same 404 as for a session they can't see (spec §4.5).
ANY_ROLE = [IsAdmin | IsTeacher | IsStudent | IsParent]


def report_session_or_404(request, pk) -> Session:
    session = session_or_404(request, pk)
    if not services.can_read_report(request.user, session):
        raise Http404
    return session


class SessionReportView(APIView):
    permission_classes = ANY_ROLE

    def get(self, request, pk):
        report = services.get_report(report_session_or_404(request, pk))
        if report is None:
            raise Http404
        return Response(payloads.report_payload(report))

    def put(self, request, pk):
        session = report_session_or_404(request, pk)
        body = ReportInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.write_report(session, by=request.user, **body.validated_data)
        return Response(payloads.report_payload(services.get_report(session)))


class MissingReportsView(generics.GenericAPIView):
    permission_classes = [IsAdmin | IsTeacher]

    def get(self, request):
        sessions = scope_for(request.user, services.missing_reports())
        page = self.paginate_queryset(sessions)
        return self.get_paginated_response(
            [payloads.session_row(s, viewer=request.user) for s in page]
        )
```

In `backend/etqan/scheduling/api/urls.py`, replace:

```python
    path("schedule/today/", views.TodayView.as_view(), name="today"),
    # Plan 5 (spec §5)
    path("sessions/", session_views.SessionListView.as_view(), name="session-list"),
    path(
        "sessions/<int:pk>/",
        session_views.SessionDetailView.as_view(),
        name="session-detail",
    ),
]
```

with:

```python
    path("schedule/today/", views.TodayView.as_view(), name="today"),
    # Plan 5 (spec §5)
    path("sessions/", session_views.SessionListView.as_view(), name="session-list"),
    path(
        "sessions/bulk/",
        session_views.SessionBulkView.as_view(),
        name="session-bulk",
    ),
    path(
        "sessions/<int:pk>/",
        session_views.SessionDetailView.as_view(),
        name="session-detail",
    ),
    path(
        "sessions/<int:pk>/attendance/",
        session_views.AttendanceView.as_view(),
        name="session-attendance",
    ),
    path(
        "sessions/<int:pk>/cancel/",
        session_views.SessionCancelView.as_view(),
        name="session-cancel",
    ),
    path(
        "sessions/<int:pk>/restore/",
        session_views.SessionRestoreView.as_view(),
        name="session-restore",
    ),
    path(
        "sessions/<int:pk>/report/",
        session_views.SessionReportView.as_view(),
        name="session-report",
    ),
    path(
        "reports/missing/",
        session_views.MissingReportsView.as_view(),
        name="missing-reports",
    ),
]
```

In `backend/etqan/scheduling/services/attendance.py`, replace:

```python
"""Marking, cancelling and restoring one session, and doing it in bulk
(Plan 5 spec §4.1, §4.3, §4.4).

Every write locks the one session row (``select_for_update``) and checks its
state on that fresh row, so two people marking at once are serialised and the
second sees the first's change. A session write never locks a subscription:
Plan 4 locks subscriptions first (in id order) and then touches sessions, so
taking only a session lock can never close a cycle with it (plan D5).
"""

from collections.abc import Iterable
```

with:

```python
"""Marking, cancelling and restoring one session, and doing it in bulk
(Plan 5 spec §4.1, §4.3, §4.4).

Every write locks the session row (``select_for_update``) and checks its
state on that fresh row, so two people marking at once are serialised and the
second sees the first's change. A session write never locks a subscription:
Plan 4 locks subscriptions first (in id order) and then touches sessions, so
taking only session locks never closes a cycle with it (plan D5).
"""

from collections.abc import Iterable
```

In `backend/etqan/scheduling/services/attendance.py`, replace:

```python
    skipped: list[tuple[int, str]] = field(default_factory=list)  # (id, code)


def bulk_sessions(
    ids: Iterable[int], *, action: str, by, reason: str = ""
) -> BulkResult:
```

with:

```python
    skipped: list[tuple[int, str]] = field(default_factory=list)  # (id, code)


@transaction.atomic
def bulk_sessions(
    ids: Iterable[int], *, action: str, by, reason: str = ""
) -> BulkResult:
```

In `backend/etqan/scheduling/services/attendance.py`, replace:

```python
    rules above. A session that fails a rule is skipped with its code; an id
    this academy does not have is skipped as ``not_found``.

    Each session runs in its own transaction (the API calls this outside the
    request's transaction, plan D5), so no more than one session is locked at
    a time and one refusal never undoes the others."""
    if action not in BULK_ACTIONS:
        raise ValidationError("Choose present, absent or cancel.", field="action")
    if action == "cancel" and not (reason or "").strip():
```

with:

```python
    rules above. A session that fails a rule is skipped with its code; an id
    this academy does not have is skipped as ``not_found``.

    Every requested row is locked first, in one query and in id order (as
    Plan 4 locks subscriptions), so two bulk requests never wait on each other
    in a cycle; each session then runs in its own savepoint, so one refusal
    never undoes the others (plan D5)."""
    if action not in BULK_ACTIONS:
        raise ValidationError("Choose present, absent or cancel.", field="action")
    if action == "cancel" and not (reason or "").strip():
```

In `backend/etqan/scheduling/services/attendance.py`, replace:

```python
    ids = sorted(set(ids))
    if not 1 <= len(ids) <= MAX_BULK:
        raise ValidationError(f"Choose from 1 to {MAX_BULK} sessions.", field="ids")
    result = BulkResult()
    for pk in ids:
        try:
            with transaction.atomic():
                session = lock(Session(pk=pk))
                if action == "cancel":
                    cancel_session(session, by=by, reason=reason)
                else:
                    mark_attendance(session, by=by, student_attendance=action)
        except NotFoundError:
            result.skipped.append((pk, "not_found"))
        except ConflictError as exc:
            result.skipped.append((pk, exc.code))
        else:
```

with:

```python
    ids = sorted(set(ids))
    if not 1 <= len(ids) <= MAX_BULK:
        raise ValidationError(f"Choose from 1 to {MAX_BULK} sessions.", field="ids")
    rows = {
        session.pk: session
        for session in Session.objects.select_for_update()
        .filter(pk__in=ids)
        .order_by("pk")
    }
    result = BulkResult()
    for pk in ids:
        if pk not in rows:
            result.skipped.append((pk, "not_found"))
            continue
        try:
            with transaction.atomic():
                if action == "cancel":
                    cancel_session(rows[pk], by=by, reason=reason)
                else:
                    mark_attendance(rows[pk], by=by, student_attendance=action)
        except ConflictError as exc:
            result.skipped.append((pk, exc.code))
        else:
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling`
Expected: PASS.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): attendance, cancel, restore, bulk and report endpoints

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Dev seeds: marked past sessions, a teacher no-show and reports

**Files:**
- Modify: `backend/etqan/scheduling/services/__init__.py`, `backend/etqan/scheduling/services/rules.py`, `backend/etqan/tenants/management/commands/seed_dev.py`
- Test: `backend/etqan/tenants/tests/test_seed_dev.py`

**Interfaces:**
- Consumes: Plan 4's `generate`; Tasks 3 and 5's `mark_attendance`, `write_report`, `missing_reports`.
- Produces: `services.has_attendance() -> bool`, `services.unmarked_sessions_before(day) -> QuerySet[Session]`; `seed_dev.seed_attendance()` (called after `seed_subscriptions`), `seed_dev.MARKS`, `NO_SHOW`, `REPORTS` (D14).

- [ ] **Step 1: Write the failing tests**

In `backend/etqan/tenants/tests/test_seed_dev.py`, replace:

```python

from etqan.identity.models import User
from etqan.site import models as site
from etqan.tenants.management.commands.seed_dev import DEV_PASSWORD
from etqan.tenants.models import Academy

```

with:

```python

from etqan.identity.models import User
from etqan.site import models as site
from etqan.tenants.management.commands import seed_dev
from etqan.tenants.management.commands.seed_dev import DEV_PASSWORD
from etqan.tenants.models import Academy

```

In `backend/etqan/tenants/tests/test_seed_dev.py`, replace:

```python

@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_skips_a_subscription_whose_teacher_was_deactivated(capsys):
    """Ruling 1: a seeded teacher/student/course/package deactivated in a dev
    database makes one create_subscription call raise; seed_dev must not
    crash, must skip only that spec, and must still create the others."""
    from etqan.scheduling import services as scheduling  # noqa: PLC0415

    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
```

with:

```python

@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_skips_a_subscription_whose_teacher_was_deactivated(
    capsys, monkeypatch
):
    """Ruling 1: a seeded teacher/student/course/package deactivated in a dev
    database makes one create_subscription call raise; seed_dev must not
    crash, must skip only that spec, and must still create the others."""
    from etqan.scheduling import services as scheduling  # noqa: PLC0415

    # Marked sessions can't be deleted, and this test deletes the seeded
    # subscriptions to seed them again: leave attendance out of it.
    monkeypatch.setattr(seed_dev, "seed_attendance", lambda: None)
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
```

Append to the end of `backend/etqan/tenants/tests/test_seed_dev.py`:

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_marks_past_sessions_and_writes_reports_once():
    from etqan.scheduling import services as scheduling  # noqa: PLC0415

    def state():
        sessions = list(
            scheduling.sessions_queryset().filter(occurs_on__lt=scheduling.today())
        )
        return {
            "marks": sorted({s.student_attendance for s in sessions}),
            "no_shows": sum(s.teacher_attendance == "absent" for s in sessions),
            "completed": sum(s.status == "completed" for s in sessions),
            "reports": sum(s.has_report for s in sessions),
            "missing": scheduling.missing_reports().count(),
            "total": scheduling.sessions_queryset().count(),
        }

    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    with tenant_context(demo):
        first = state()
        assert first["marks"] == ["absent", "excused", "present"]
        assert first["no_shows"] == 1
        assert first["completed"] >= len(seed_dev.MARKS)
        # Every completed session but one has its report; that one is older
        # than a day, so it is the one missing report.
        assert first["reports"] == first["completed"] - 1
        assert first["missing"] == 1
        # Nothing from today on was marked.
        assert (
            not scheduling.sessions_queryset()
            .filter(occurs_on__gte=scheduling.today(), status="completed")
            .exists()
        )
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert state() == first
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/tenants/tests/test_seed_dev.py`
Expected: FAIL — the new test finds no marks (`[] != ['absent', 'excused', 'present']`), and the deactivated-teacher test errors on `monkeypatch.setattr(seed_dev, "seed_attendance", …)` (no such attribute).

- [ ] **Step 3: Implement**

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
from etqan.scheduling.services.rules import derive
from etqan.scheduling.services.rules import derived
from etqan.scheduling.services.rules import filter_sessions
from etqan.scheduling.services.rules import has_marked_sessions
from etqan.scheduling.services.rules import has_subscriptions
from etqan.scheduling.services.rules import pause_state
```

with:

```python
from etqan.scheduling.services.rules import derive
from etqan.scheduling.services.rules import derived
from etqan.scheduling.services.rules import filter_sessions
from etqan.scheduling.services.rules import has_attendance
from etqan.scheduling.services.rules import has_marked_sessions
from etqan.scheduling.services.rules import has_subscriptions
from etqan.scheduling.services.rules import pause_state
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
from etqan.scheduling.services.rules import slots_of
from etqan.scheduling.services.rules import subscriptions_queryset
from etqan.scheduling.services.rules import today
from etqan.scheduling.services.rules import untouched_sessions
from etqan.scheduling.services.subscriptions import add_pause
from etqan.scheduling.services.subscriptions import add_slots
```

with:

```python
from etqan.scheduling.services.rules import slots_of
from etqan.scheduling.services.rules import subscriptions_queryset
from etqan.scheduling.services.rules import today
from etqan.scheduling.services.rules import unmarked_sessions_before
from etqan.scheduling.services.rules import untouched_sessions
from etqan.scheduling.services.subscriptions import add_pause
from etqan.scheduling.services.subscriptions import add_slots
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
    "generate",
    "generate_horizon",
    "get_report",
    "has_marked_sessions",
    "has_started",
    "has_subscriptions",
```

with:

```python
    "generate",
    "generate_horizon",
    "get_report",
    "has_attendance",
    "has_marked_sessions",
    "has_started",
    "has_subscriptions",
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
    "subscriptions_queryset",
    "today",
    "today_board",
    "untouched_sessions",
    "update_slot",
    "update_subscription",
```

with:

```python
    "subscriptions_queryset",
    "today",
    "today_board",
    "unmarked_sessions_before",
    "untouched_sessions",
    "update_slot",
    "update_subscription",
```

Append to the end of `backend/etqan/scheduling/services/rules.py`:

```python
def has_attendance() -> bool:
    """Whether anyone has marked or completed a session in this academy."""
    return Session.objects.filter(MARKED).exists()


def unmarked_sessions_before(day: date) -> QuerySet[Session]:
    """Scheduled sessions dated before ``day`` that nobody has marked, oldest
    first, with their teacher (the seeds mark them as that teacher)."""
    return (
        Session.objects.filter(
            status=Session.Status.SCHEDULED,
            student_attendance=NOT_SET,
            teacher_attendance=NOT_SET,
            occurs_on__lt=day,
        )
        .select_related("teacher__user")
        .order_by("starts_at", "id")
    )
```

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services
from etqan.site import services as site_services
```

with:

```python
from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services
from etqan.site import services as site_services
```

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
                print(f"skip: {spec['student']} pause — {exc}")  # noqa: T201


class Command(BaseCommand):
    help = "Create the public tenant and two dev academies with known admin logins."

```

with:

```python
                print(f"skip: {spec['student']} pause — {exc}")  # noqa: T201


# Plan 5 (spec §7): past sessions are marked in this order, repeating, and
# the second one is a teacher no-show. Every completed session but the oldest
# gets a report, so exactly one old one shows under Missing reports.
MARKS = ("present", "present", "absent", "present", "excused")
NO_SHOW = 1
REPORTS = ((5, 4, "Recited clearly."), (4, 5, ""), (3, 3, "Needs revision."))


def seed_attendance() -> None:
    """Idempotent: an academy where any session is already marked is left
    alone. The demo subscriptions started in the past, so their past sessions
    are generated first (an admin's backfill), then marked by their teacher.
    A session that a rule refuses is skipped and seeding continues."""
    if scheduling_services.has_attendance():
        return
    today = scheduling_services.today()
    for sub in scheduling_services.subscriptions_queryset().order_by("pk"):
        if sub.starts_on < today:
            scheduling_services.generate(
                sub.starts_on, today - timedelta(days=1), subscription=sub
            )
    marked = []
    for n, session in enumerate(scheduling_services.unmarked_sessions_before(today)):
        teacher = session.teacher.user
        try:
            scheduling_services.mark_attendance(
                session,
                by=teacher,
                student_attendance=MARKS[n % len(MARKS)],
                teacher_attendance="absent" if n == NO_SHOW else "present",
            )
        except (ValidationError, ConflictError, NotFoundError) as exc:
            print(f"skip: session {session.pk} attendance — {exc}")  # noqa: T201
            continue
        marked.append((session, teacher))
    for n, (session, teacher) in enumerate(marked[1:]):
        behaviour, participation, notes = REPORTS[n % len(REPORTS)]
        try:
            scheduling_services.write_report(
                session,
                by=teacher,
                behaviour=behaviour,
                participation=participation,
                notes=notes,
            )
        except (ValidationError, ConflictError, NotFoundError) as exc:
            print(f"skip: session {session.pk} report — {exc}")  # noqa: T201


class Command(BaseCommand):
    help = "Create the public tenant and two dev academies with known admin logins."

```

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
                site_services.seed_site(**SITES[subdomain])
                seed_people(PEOPLE[subdomain])
                seed_subscriptions(SUBSCRIPTIONS[subdomain])
```

with:

```python
                site_services.seed_site(**SITES[subdomain])
                seed_people(PEOPLE[subdomain])
                seed_subscriptions(SUBSCRIPTIONS[subdomain])
                seed_attendance()
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/tenants/tests/test_seed_dev.py`
Expected: PASS; seeding twice leaves the counts unchanged.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(seed): mark past demo sessions and write their reports

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Dashboard groundwork: session data layer, time helpers, role guard, the two switches

**Files:**
- Modify: `dashboard/src/features/academy/AcademySettingsForm.tsx`, `dashboard/src/features/academy/api.ts`, `dashboard/src/features/academy/queries.ts`, `dashboard/src/features/identity/require-admin.ts`, `dashboard/src/features/scheduling/TodayBoard.tsx`, `dashboard/src/features/scheduling/api.ts`, `dashboard/src/features/scheduling/index.ts`, `dashboard/src/features/scheduling/queries.ts`, `dashboard/src/features/scheduling/schemas.ts`, `dashboard/src/lib/zoned-time.ts`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/academy/AcademySettingsForm.test.tsx`, `dashboard/src/features/catalogue/PackageForm.test.tsx`, `dashboard/src/features/identity/require-role.test.tsx` (new), `dashboard/src/features/people/AdminsList.test.tsx`, `dashboard/src/features/people/ParentForm.test.tsx`, `dashboard/src/features/people/StudentForm.test.tsx`, `dashboard/src/features/people/TeacherForm.test.tsx`, `dashboard/src/features/scheduling/GenerateDialog.test.tsx`, `dashboard/src/features/scheduling/SubscriptionDetail.test.tsx`, `dashboard/src/features/scheduling/SubscriptionForm.test.tsx`, `dashboard/src/features/scheduling/TodayBoard.test.tsx`, `dashboard/src/features/scheduling/api.test.ts`, `dashboard/src/lib/zoned-time.test.ts`, `dashboard/src/test/scheduling-fixtures.ts`

**Interfaces:**
- Consumes: the Task 6–7 routes and payloads.
- Produces (`@/features/scheduling`): types `Session` (adds `has_started`, `student: StudentRef`, optional `notes`, `cancel_reason`, `has_report`), `SessionReport`, `BulkBody`, `BulkResult`, `AttendanceBody`, `ReportBody`, `BulkAction`; constants `ATTENDANCE`, `SESSION_STATUSES`, `SCALE` (`[5, 4, 3, 2, 1]`); zod `cancelSessionSchema`/`CancelSessionValues`, `reportFormSchema`/`ReportFormValues`.
- Produces: `schedulingApi.sessionList(params)`, `.session(id)`, `.markAttendance({id, ...body})`, `.cancelSession({id, reason})`, `.restoreSession(id)`, `.bulk(body)`, `.report(id)`, `.saveReport({id, ...body})`, `.missingReports(params)`; `sessionsCsvUrl(params)`; hooks `useSessionList(params, { refetchInterval? })`, `useSession(id | undefined)`, `useReport(id, enabled)`, `useMissingReports(params)` — all under `schedulingKey`, so `useSchedulingMutation` refreshes them.
- Produces: `@/lib/zoned-time` `otherZoneTime(instant, theirZone, ourZone, language) -> string | null` (TodayBoard now uses it) and `dayIn(instant, timeZone, language) -> string`.
- Produces: `requireRole(context, roles: readonly Role[])` in `@/features/identity/require-admin` (`requireAdmin` calls it).
- Produces: `AcademySettings.absent_consumes_session`/`excused_consumes_session`; saving settings invalidates every non-settings query (D13).
- Produces (tests): `sessionRow` gains the new fields; `reportRow(overrides)` in `@/test/scheduling-fixtures`.

- [ ] **Step 1: Branch**

```bash
git -C dashboard switch -c feat/sessions-attendance
```

- [ ] **Step 2: Write the failing tests**

In `dashboard/src/features/academy/AcademySettingsForm.test.tsx`, replace:

```tsx
			<Toaster />
		</QueryClientProvider>,
	);
}

describe("AcademySettingsForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
```

with:

```tsx
			<Toaster />
		</QueryClientProvider>,
	);
	return client;
}

const SWITCHES = {
	absent_consumes_session: true,
	excused_consumes_session: false,
};

describe("AcademySettingsForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
```

In `dashboard/src/features/academy/AcademySettingsForm.test.tsx`, replace:

```tsx
			default_language: "ar",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
		});
	});

```

with:

```tsx
			default_language: "ar",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
			...SWITCHES,
		});
	});

```

In `dashboard/src/features/academy/AcademySettingsForm.test.tsx`, replace:

```tsx
			default_language: "en",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
		});
		const user = userEvent.setup();
		renderForm();
```

with:

```tsx
			default_language: "en",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
			...SWITCHES,
		});
		const user = userEvent.setup();
		renderForm();
```

In `dashboard/src/features/academy/AcademySettingsForm.test.tsx`, replace:

```tsx
				default_language: "en",
				generation_horizon_days: 14,
				renewal_grace_days: 7,
			}),
		);
		expect(await screen.findByText("Saved.")).toBeInTheDocument();
```

with:

```tsx
				default_language: "en",
				generation_horizon_days: 14,
				renewal_grace_days: 7,
				...SWITCHES,
			}),
		);
		expect(await screen.findByText("Saved.")).toBeInTheDocument();
```

In `dashboard/src/features/academy/AcademySettingsForm.test.tsx`, replace:

```tsx
			default_language: "ar",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
			...body,
		}));
		const user = userEvent.setup();
```

with:

```tsx
			default_language: "ar",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
			...SWITCHES,
			...body,
		}));
		const user = userEvent.setup();
```

In `dashboard/src/features/academy/AcademySettingsForm.test.tsx`, replace:

```tsx
			),
		);
	});
});
```

with:

```tsx
			),
		);
	});

	it("saves the counts-as-used switches and refreshes what they change", async () => {
		vi.mocked(academyApi.update).mockImplementation(async (body) => ({
			timezone: "Africa/Cairo",
			default_currency: "EGP",
			default_language: "ar",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
			...SWITCHES,
			...body,
		}));
		const user = userEvent.setup();
		const client = renderForm();
		// Something showing sessions used, cached before the save.
		client.setQueryData(["scheduling", "subscriptions", {}], { count: 0 });
		const absent = await screen.findByRole("checkbox", {
			name: "When the student is absent",
		});
		const excused = screen.getByRole("checkbox", {
			name: "When the student is excused",
		});
		expect(absent).toBeChecked();
		expect(excused).not.toBeChecked();
		await user.click(absent);
		await user.click(excused);
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(academyApi.update).toHaveBeenCalledWith(
				expect.objectContaining({
					absent_consumes_session: false,
					excused_consumes_session: true,
				}),
			),
		);
		await waitFor(() =>
			expect(
				client.getQueryState(["scheduling", "subscriptions", {}])
					?.isInvalidated,
			).toBe(true),
		);
	});
});
```

Create `dashboard/src/features/identity/require-role.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
	createMemoryHistory,
	createRootRouteWithContext,
	createRoute,
	createRouter,
	RouterProvider,
} from "@tanstack/react-router";
import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "./api";
import { requireRole } from "./require-admin";
import type { Role } from "./schemas";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, identityApi: { me: vi.fn() } };
});

function renderGuarded(role: Role) {
	vi.mocked(identityApi.me).mockResolvedValue({
		id: 1,
		email: "x@b.com",
		full_name: "X",
		role,
		profiles: role === "admin" ? [] : [role],
	});
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	const rootRoute = createRootRouteWithContext<{
		queryClient: QueryClient;
	}>()();
	const home = createRoute({
		getParentRoute: () => rootRoute,
		path: "/",
		component: () => <p>home</p>,
	});
	const learning = createRoute({
		getParentRoute: () => rootRoute,
		path: "/learning",
		beforeLoad: ({ context }) => requireRole(context, ["student", "parent"]),
		component: () => <p>learning</p>,
	});
	const router = createRouter({
		routeTree: rootRoute.addChildren([home, learning]),
		history: createMemoryHistory({ initialEntries: ["/learning"] }),
		context: { queryClient: client },
	});
	return render(
		<QueryClientProvider client={client}>
			<RouterProvider router={router} />
		</QueryClientProvider>,
	);
}

describe("requireRole", () => {
	beforeEach(() => vi.clearAllMocks());

	it.each(["student", "parent"] as const)("lets a %s through", async (role) => {
		renderGuarded(role);
		expect(await screen.findByText("learning")).toBeInTheDocument();
	});

	it.each(["teacher", "admin"] as const)("sends a %s home", async (role) => {
		renderGuarded(role);
		expect(await screen.findByText("home")).toBeInTheDocument();
		expect(screen.queryByText("learning")).toBeNull();
	});
});
```

In `dashboard/src/features/scheduling/api.test.ts`, replace:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { schedulingApi, subscriptionsCsvUrl } from "./api";

vi.mock("@/lib/api", async (orig) => {
	const actual = await orig<typeof import("@/lib/api")>();
```

with:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { schedulingApi, sessionsCsvUrl, subscriptionsCsvUrl } from "./api";

vi.mock("@/lib/api", async (orig) => {
	const actual = await orig<typeof import("@/lib/api")>();
```

In `dashboard/src/features/scheduling/api.test.ts`, replace:

```ts
			get: vi.fn(ok),
			post: vi.fn(ok),
			patch: vi.fn(ok),
			delete: vi.fn(ok),
		},
	};
```

with:

```ts
			get: vi.fn(ok),
			post: vi.fn(ok),
			patch: vi.fn(ok),
			put: vi.fn(ok),
			delete: vi.fn(ok),
		},
	};
```

In `dashboard/src/features/scheduling/api.test.ts`, replace:

```ts
	});
});

describe("subscriptionsCsvUrl", () => {
	it("keeps the filters and drops the page", () => {
		expect(subscriptionsCsvUrl({ status: "active", page: 3 })).toBe(
```

with:

```ts
	});
});

describe("sessions and reports (Plan 5 spec §5)", () => {
	beforeEach(() => vi.clearAllMocks());

	it("reads sessions, one session, a report and the missing reports", async () => {
		await schedulingApi.sessionList({ when: "today", q: "", page: 1 });
		expect(api.get).toHaveBeenLastCalledWith("sessions/", {
			params: { when: "today", page: "1" },
		});
		await schedulingApi.session(41);
		expect(api.get).toHaveBeenLastCalledWith("sessions/41/");
		await schedulingApi.report(41);
		expect(api.get).toHaveBeenLastCalledWith("sessions/41/report/");
		await schedulingApi.missingReports({ page: 2 });
		expect(api.get).toHaveBeenLastCalledWith("reports/missing/", {
			params: { page: "2" },
		});
	});

	it("writes attendance, cancel, restore, bulk and the report", async () => {
		await schedulingApi.markAttendance({
			id: 41,
			student_attendance: "present",
		});
		expect(api.post).toHaveBeenLastCalledWith("sessions/41/attendance/", {
			student_attendance: "present",
		});
		await schedulingApi.cancelSession({ id: 41, reason: "Eid" });
		expect(api.post).toHaveBeenLastCalledWith("sessions/41/cancel/", {
			reason: "Eid",
		});
		await schedulingApi.restoreSession(41);
		expect(api.post).toHaveBeenLastCalledWith("sessions/41/restore/");
		await schedulingApi.bulk({ ids: [41, 42], action: "absent" });
		expect(api.post).toHaveBeenLastCalledWith("sessions/bulk/", {
			ids: [41, 42],
			action: "absent",
		});
		await schedulingApi.saveReport({ id: 41, behaviour: 5, participation: 4 });
		expect(api.put).toHaveBeenLastCalledWith("sessions/41/report/", {
			behaviour: 5,
			participation: 4,
		});
	});

	it("exports the filtered sessions as CSV", () => {
		expect(sessionsCsvUrl({ when: "week", page: 2, page_size: 25 })).toBe(
			"/api/v1/sessions/?when=week&format=csv",
		);
	});
});

describe("subscriptionsCsvUrl", () => {
	it("keeps the filters and drops the page", () => {
		expect(subscriptionsCsvUrl({ status: "active", page: 3 })).toBe(
```

In `dashboard/src/lib/zoned-time.test.ts`, replace:

```ts
import { describe, expect, it } from "vitest";
import {
	formatDay,
	studentTime,
	todayIn,
	wallTime,
```

with:

```ts
import { describe, expect, it } from "vitest";
import {
	dayIn,
	formatDay,
	otherZoneTime,
	studentTime,
	todayIn,
	wallTime,
```

Append to the end of `dashboard/src/lib/zoned-time.test.ts`:

```ts
describe("otherZoneTime", () => {
	const instant = new Date("2026-06-01T18:00:00Z");

	it("reads the same instant on another clock", () => {
		expect(otherZoneTime(instant, "Asia/Riyadh", "UTC", "en")).toBe("21:00");
		expect(otherZoneTime(instant, "Asia/Kolkata", "UTC", "en")).toBe("23:30");
	});

	it("is null when both clocks read the same", () => {
		expect(otherZoneTime(instant, "UTC", "UTC", "en")).toBeNull();
		expect(
			otherZoneTime(instant, "Europe/London", "Europe/Dublin", "en"),
		).toBeNull();
	});
});

describe("dayIn", () => {
	it("is the date on that zone's calendar", () => {
		const late = new Date("2026-06-01T22:30:00Z");
		expect(dayIn(late, "UTC", "en")).toBe("Jun 1, 2026");
		expect(dayIn(late, "Asia/Riyadh", "en")).toBe("Jun 2, 2026");
	});
});
```

In `dashboard/src/test/scheduling-fixtures.ts`, replace:

```ts
import type {
	Session,
	Subscription,
	SubscriptionDetail,
	TodayRow,
```

with:

```ts
import type {
	Session,
	SessionReport,
	Subscription,
	SubscriptionDetail,
	TodayRow,
```

In `dashboard/src/test/scheduling-fixtures.ts`, replace:

```ts
		status: "scheduled",
		student_attendance: "not_set",
		teacher_attendance: "not_set",
		meeting_url: "https://meet.test/bilal",
		generated: true,
		student: { id: 11, full_name: "Yusuf" },
		teacher: { id: 21, full_name: "Bilal" },
		course: { id: 3, name_ar: "تجويد", name_en: "Tajweed" },
		...overrides,
	};
}
```

with:

```ts
		status: "scheduled",
		student_attendance: "not_set",
		teacher_attendance: "not_set",
		has_started: true,
		meeting_url: "https://meet.test/bilal",
		generated: true,
		student: { id: 11, full_name: "Yusuf", timezone: "Asia/Riyadh" },
		teacher: { id: 21, full_name: "Bilal" },
		course: { id: 3, name_ar: "تجويد", name_en: "Tajweed" },
		notes: "",
		cancel_reason: "",
		has_report: false,
		...overrides,
	};
}

export function reportRow(
	overrides: Partial<SessionReport> = {},
): SessionReport {
	return {
		session: 41,
		behaviour: 5,
		participation: 4,
		notes: "Recited clearly.",
		written_by: { id: 21, full_name: "Bilal" },
		created_at: "2026-06-01T19:00:00Z",
		updated_at: "2026-06-01T19:00:00Z",
		...overrides,
	};
}
```

The API now always sends the two switches, so every test that mocks `academyApi.get` with a settings object needs them. In these eight files add two lines after `renewal_grace_days: 7,` (the only academy-settings fixture in each):

- `dashboard/src/features/catalogue/PackageForm.test.tsx`
- `dashboard/src/features/people/AdminsList.test.tsx`
- `dashboard/src/features/people/ParentForm.test.tsx`
- `dashboard/src/features/people/StudentForm.test.tsx`
- `dashboard/src/features/people/TeacherForm.test.tsx`
- `dashboard/src/features/scheduling/SubscriptionDetail.test.tsx`
- `dashboard/src/features/scheduling/SubscriptionForm.test.tsx`
- `dashboard/src/features/scheduling/TodayBoard.test.tsx`

```bash
sed -i 's/^\(\t*\)renewal_grace_days: 7,$/&\n\1absent_consumes_session: true,\n\1excused_consumes_session: false,/' \
  src/features/catalogue/PackageForm.test.tsx \
  src/features/people/AdminsList.test.tsx \
  src/features/people/ParentForm.test.tsx \
  src/features/people/StudentForm.test.tsx \
  src/features/people/TeacherForm.test.tsx \
  src/features/scheduling/SubscriptionDetail.test.tsx \
  src/features/scheduling/SubscriptionForm.test.tsx \
  src/features/scheduling/TodayBoard.test.tsx
```

(run from `dashboard/`; GNU sed). A Session's `student` now carries `timezone`, so in `dashboard/src/features/scheduling/GenerateDialog.test.tsx` replace `student: { id: 12, full_name: "Aisha" },` with `student: { id: 12, full_name: "Aisha", timezone: "Asia/Riyadh" },`.

- [ ] **Step 3: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling/api.test.ts src/lib/zoned-time.test.ts src/features/identity/require-role.test.tsx src/features/academy`
Expected: FAIL — `schedulingApi.sessionList is not a function`, `otherZoneTime`/`dayIn` and `requireRole` are not exported, and the switch checkboxes are not found.

- [ ] **Step 4: Implement**

In `dashboard/src/features/academy/AcademySettingsForm.tsx`, replace:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { z } from "zod";
import { CURRENCIES } from "@/lib/currencies";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { timezoneOptions } from "@/lib/timezones";
import { Field, Input, Select, Spinner, SubmitButton, toast } from "@/ui";
import { useAcademySettings, useUpdateAcademySettings } from "./queries";

const days = (min: number, max: number, message: string) =>
```

with:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useController, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { z } from "zod";
import { CURRENCIES } from "@/lib/currencies";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { timezoneOptions } from "@/lib/timezones";
import {
	Checkbox,
	Field,
	Input,
	Select,
	Spinner,
	SubmitButton,
	toast,
} from "@/ui";
import { useAcademySettings, useUpdateAcademySettings } from "./queries";

const days = (min: number, max: number, message: string) =>
```

In `dashboard/src/features/academy/AcademySettingsForm.tsx`, replace:

```tsx
	default_language: z.enum(["ar", "en"]),
	generation_horizon_days: days(1, 60, "academySettings.errors.horizonRange"),
	renewal_grace_days: days(0, 60, "academySettings.errors.graceRange"),
});
type Values = z.infer<typeof schema>;

```

with:

```tsx
	default_language: z.enum(["ar", "en"]),
	generation_horizon_days: days(1, 60, "academySettings.errors.horizonRange"),
	renewal_grace_days: days(0, 60, "academySettings.errors.graceRange"),
	absent_consumes_session: z.boolean(),
	excused_consumes_session: z.boolean(),
});
type Values = z.infer<typeof schema>;

```

In `dashboard/src/features/academy/AcademySettingsForm.tsx`, replace:

```tsx
	const update = useUpdateAcademySettings();
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
```

with:

```tsx
	const update = useUpdateAcademySettings();
	const {
		register,
		control,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
```

In `dashboard/src/features/academy/AcademySettingsForm.tsx`, replace:

```tsx
					default_language: data.default_language,
					generation_horizon_days: data.generation_horizon_days,
					renewal_grace_days: data.renewal_grace_days,
				}
			: undefined,
	});
	const fieldError = useFieldError();

	async function onSubmit(values: Values) {
		try {
```

with:

```tsx
					default_language: data.default_language,
					generation_horizon_days: data.generation_horizon_days,
					renewal_grace_days: data.renewal_grace_days,
					absent_consumes_session: data.absent_consumes_session,
					excused_consumes_session: data.excused_consumes_session,
				}
			: undefined,
	});
	const fieldError = useFieldError();
	const absent = useController({
		control,
		name: "absent_consumes_session",
		defaultValue: true,
	});
	const excused = useController({
		control,
		name: "excused_consumes_session",
		defaultValue: false,
	});

	async function onSubmit(values: Values) {
		try {
```

In `dashboard/src/features/academy/AcademySettingsForm.tsx`, replace:

```tsx
			<p className="text-sm text-muted-foreground">
				{t("academySettings.schedulingHint")}
			</p>
			<SubmitButton pending={isSubmitting} className="self-start">
				{t("people.save")}
			</SubmitButton>
```

with:

```tsx
			<p className="text-sm text-muted-foreground">
				{t("academySettings.schedulingHint")}
			</p>
			<fieldset className="flex flex-col gap-3">
				<legend className="mb-2 text-sm font-medium">
					{t("academySettings.countsAsUsed")}
				</legend>
				<label
					htmlFor="absent_consumes_session"
					className="flex items-center gap-2 text-sm"
				>
					<Checkbox
						id="absent_consumes_session"
						checked={absent.field.value}
						onCheckedChange={absent.field.onChange}
					/>
					{t("academySettings.absentCounts")}
				</label>
				<label
					htmlFor="excused_consumes_session"
					className="flex items-center gap-2 text-sm"
				>
					<Checkbox
						id="excused_consumes_session"
						checked={excused.field.value}
						onCheckedChange={excused.field.onChange}
					/>
					{t("academySettings.excusedCounts")}
				</label>
				<p className="text-sm text-muted-foreground">
					{t("academySettings.countsHint")}
				</p>
			</fieldset>
			<SubmitButton pending={isSubmitting} className="self-start">
				{t("people.save")}
			</SubmitButton>
```

In `dashboard/src/features/academy/api.ts`, replace:

```ts
	default_language: Language;
	generation_horizon_days: number;
	renewal_grace_days: number;
	updated_at?: string;
}

```

with:

```ts
	default_language: Language;
	generation_horizon_days: number;
	renewal_grace_days: number;
	// Plan 5 spec §4.2: whether a missed session counts as used.
	absent_consumes_session: boolean;
	excused_consumes_session: boolean;
	updated_at?: string;
}

```

In `dashboard/src/features/academy/queries.ts`, replace:

```ts
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (body: Partial<AcademySettings>) => academyApi.update(body),
		onSuccess: (data) => qc.setQueryData(academySettingsKey, data),
	});
}
```

with:

```ts
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (body: Partial<AcademySettings>) => academyApi.update(body),
		onSuccess: (data) => {
			qc.setQueryData(academySettingsKey, data);
			// The switches change every subscription's used and remaining
			// sessions (and the time zone every "today"): refresh whatever
			// else is on screen rather than show stale numbers.
			return qc.invalidateQueries({
				predicate: (query) => query.queryKey[0] !== academySettingsKey[0],
			});
		},
	});
}
```

In `dashboard/src/features/identity/require-admin.ts`, replace:

```ts
import type { QueryClient } from "@tanstack/react-query";
import { redirect } from "@tanstack/react-router";
import { meQueryOptions } from "@/features/identity/queries";

/**
 * Guards `/website/*`: an academy admin sees it, everyone else bounces to the
 * app home. `_authed`'s own `beforeLoad` already guarantees `me` resolves (a
 * logged-out visitor never reaches here), so this only has to check the role.
 */
export async function requireAdmin(context: {
	queryClient: QueryClient;
}): Promise<void> {
	const me = await context.queryClient.ensureQueryData(meQueryOptions);
	if (me.role !== "admin") throw redirect({ to: "/" });
}
```

with:

```ts
import type { QueryClient } from "@tanstack/react-query";
import { redirect } from "@tanstack/react-router";
import { meQueryOptions } from "@/features/identity/queries";
import type { Role } from "@/features/identity/schemas";

/**
 * Guards a route to some roles: everyone else bounces to the app home.
 * `_authed`'s own `beforeLoad` already guarantees `me` resolves (a logged-out
 * visitor never reaches here), so this only has to check the role.
 */
export async function requireRole(
	context: { queryClient: QueryClient },
	roles: readonly Role[],
): Promise<void> {
	const me = await context.queryClient.ensureQueryData(meQueryOptions);
	if (!roles.includes(me.role)) throw redirect({ to: "/" });
}

/** Guards the admin areas (`/website/*`, `/scheduling/*`, …). */
export function requireAdmin(context: {
	queryClient: QueryClient;
}): Promise<void> {
	return requireRole(context, ["admin"]);
}
```

In `dashboard/src/features/scheduling/TodayBoard.tsx`, replace:

```tsx
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { errorText } from "@/lib/form-errors";
import { formatDay, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
```

with:

```tsx
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { errorText } from "@/lib/form-errors";
import { formatDay, otherZoneTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
```

In `dashboard/src/features/scheduling/TodayBoard.tsx`, replace:

```tsx
	missing: "warning",
};

/** The student's local time for a board row, or null when their clock reads
 * the same as the academy's. Controller ruling: a row's server `starts_at`
 * is the source of truth (`new Date(starts_at)`), never a wall-clock
 * recomputation -- the backend always sends `starts_at`, generated or not. */
function rowStudentTime(
	row: TodayRow,
	academyZone: string,
	language: string,
): string | null {
	if (row.student.timezone === academyZone) return null;
	const instant = new Date(row.starts_at);
	const theirs = wallTime(instant, row.student.timezone, language);
	const ours = wallTime(instant, academyZone, language);
	return theirs === ours ? null : theirs;
}

/** Spec §4.3 / §6: today's slots in the academy's clock, with "Generate" on
 * the missing ones. */
export function TodayBoard() {
```

with:

```tsx
	missing: "warning",
};

/** Spec §4.3 / §6: today's slots in the academy's clock, with "Generate" on
 * the missing ones. */
export function TodayBoard() {
```

In `dashboard/src/features/scheduling/TodayBoard.tsx`, replace:

```tsx
						</thead>
						<tbody>
							{board.rows.map((row) => {
								const theirs = rowStudentTime(
									row,
									academy.timezone,
									i18n.language,
								);
```

with:

```tsx
						</thead>
						<tbody>
							{board.rows.map((row) => {
								// The row's server `starts_at`, never a wall-clock
								// recomputation (controller ruling, Plan 4).
								const theirs = otherZoneTime(
									new Date(row.starts_at),
									row.student.timezone,
									academy.timezone,
									i18n.language,
								);
```

In `dashboard/src/features/scheduling/api.ts`, replace:

```ts
	type QueryParams,
} from "@/lib/api";
import type {
	GenerateBody,
	GenerationResult,
	PauseBody,
	RenewBody,
	Session,
	SlotBody,
	SlotPatch,
	Subscription,
```

with:

```ts
	type QueryParams,
} from "@/lib/api";
import type {
	AttendanceBody,
	BulkBody,
	BulkResult,
	GenerateBody,
	GenerationResult,
	PauseBody,
	RenewBody,
	ReportBody,
	Session,
	SessionReport,
	SlotBody,
	SlotPatch,
	Subscription,
```

In `dashboard/src/features/scheduling/api.ts`, replace:

```ts
} from "./schemas";

const S = "subscriptions/";
const detail = async (request: Promise<{ data: SubscriptionDetail }>) =>
	(await request).data;

```

with:

```ts
} from "./schemas";

const S = "subscriptions/";
const SE = "sessions/";
const detail = async (request: Promise<{ data: SubscriptionDetail }>) =>
	(await request).data;

```

In `dashboard/src/features/scheduling/api.ts`, replace:

```ts
	generate: async (body: GenerateBody) =>
		(await api.post<GenerationResult>("schedule/generate/", body)).data,
	today: async () => (await api.get<TodayBoard>("schedule/today/")).data,
};

/** The subscriptions list's CSV export, with the list's filters. */
export function subscriptionsCsvUrl(params: QueryParams): string {
	return csvUrl(S, params);
```

with:

```ts
	generate: async (body: GenerateBody) =>
		(await api.post<GenerationResult>("schedule/generate/", body)).data,
	today: async () => (await api.get<TodayBoard>("schedule/today/")).data,
	// Plan 5: sessions, attendance and reports (spec §5).
	sessionList: async (params: QueryParams) =>
		(await api.get<Paginated<Session>>(SE, { params: clean(params) })).data,
	session: async (id: number) => (await api.get<Session>(`${SE}${id}/`)).data,
	markAttendance: async ({ id, ...body }: AttendanceBody & { id: number }) =>
		(await api.post<Session>(`${SE}${id}/attendance/`, body)).data,
	cancelSession: async ({ id, reason }: { id: number; reason: string }) =>
		(await api.post<Session>(`${SE}${id}/cancel/`, { reason })).data,
	restoreSession: async (id: number) =>
		(await api.post<Session>(`${SE}${id}/restore/`)).data,
	bulk: async (body: BulkBody) =>
		(await api.post<BulkResult>(`${SE}bulk/`, body)).data,
	report: async (id: number) =>
		(await api.get<SessionReport>(`${SE}${id}/report/`)).data,
	saveReport: async ({ id, ...body }: ReportBody & { id: number }) =>
		(await api.put<SessionReport>(`${SE}${id}/report/`, body)).data,
	missingReports: async (params: QueryParams) =>
		(
			await api.get<Paginated<Session>>("reports/missing/", {
				params: clean(params),
			})
		).data,
};

/** The sessions list's CSV export, with the list's filters (admins only). */
export function sessionsCsvUrl(params: QueryParams): string {
	return csvUrl(SE, params);
}

/** The subscriptions list's CSV export, with the list's filters. */
export function subscriptionsCsvUrl(params: QueryParams): string {
	return csvUrl(S, params);
```

In `dashboard/src/features/scheduling/index.ts`, replace:

```ts
export { schedulingApi, subscriptionsCsvUrl } from "./api";
export * from "./queries";
export { SubscriptionDetail } from "./SubscriptionDetail";
export { SubscriptionForm } from "./SubscriptionForm";
```

with:

```ts
export { schedulingApi, sessionsCsvUrl, subscriptionsCsvUrl } from "./api";
export * from "./queries";
export { SubscriptionDetail } from "./SubscriptionDetail";
export { SubscriptionForm } from "./SubscriptionForm";
```

In `dashboard/src/features/scheduling/queries.ts`, replace:

```ts
	});
}

export function useToday() {
	return useQuery({
		queryKey: [...schedulingKey, "today"],
```

with:

```ts
	});
}

export function useSessionList(
	params: QueryParams,
	{ refetchInterval }: { refetchInterval?: number } = {},
) {
	return useQuery({
		queryKey: [...schedulingKey, "session-list", params],
		queryFn: () => schedulingApi.sessionList(params),
		placeholderData: keepPreviousData,
		// A teacher's list re-reads each minute, so a session's attendance
		// controls open soon after its start time (the server's `has_started`).
		refetchInterval,
	});
}

export function useSession(id: number | undefined) {
	return useQuery({
		queryKey: [...schedulingKey, "session", id],
		queryFn: () => schedulingApi.session(id as number),
		enabled: id !== undefined,
	});
}

/** A session's report; only fetched when the session says it has one. */
export function useReport(id: number, enabled: boolean) {
	return useQuery({
		queryKey: [...schedulingKey, "report", id],
		queryFn: () => schedulingApi.report(id),
		enabled,
	});
}

export function useMissingReports(params: QueryParams) {
	return useQuery({
		queryKey: [...schedulingKey, "missing-reports", params],
		queryFn: () => schedulingApi.missingReports(params),
		placeholderData: keepPreviousData,
	});
}

export function useToday() {
	return useQuery({
		queryKey: [...schedulingKey, "today"],
```

In `dashboard/src/features/scheduling/schemas.ts`, replace:

```ts
	pauses: Pause[];
}

export type Attendance = "not_set" | "present" | "absent" | "excused";
export interface Session {
	id: number;
	subscription_id: number | null;
```

with:

```ts
	pauses: Pause[];
}

export const ATTENDANCE = ["not_set", "present", "absent", "excused"] as const;
export type Attendance = (typeof ATTENDANCE)[number];
export const SESSION_STATUSES = [
	"scheduled",
	"completed",
	"cancelled",
] as const;
export type SessionStatus = (typeof SESSION_STATUSES)[number];

export interface Session {
	id: number;
	subscription_id: number | null;
```

In `dashboard/src/features/scheduling/schemas.ts`, replace:

```ts
	occurs_on: string;
	starts_at: string;
	minutes: number;
	status: "scheduled" | "completed" | "cancelled";
	student_attendance: Attendance;
	teacher_attendance: Attendance;
	meeting_url: string;
	generated: boolean;
	student: PersonRef;
	teacher: PersonRef;
	course: NamedRef;
}

export interface GenerationResult {
```

with:

```ts
	occurs_on: string;
	starts_at: string;
	minutes: number;
	status: SessionStatus;
	student_attendance: Attendance;
	teacher_attendance: Attendance;
	// The server's start-time gate (Plan 5 P5-5): attendance opens once true.
	has_started: boolean;
	meeting_url: string;
	generated: boolean;
	student: StudentRef;
	teacher: PersonRef;
	course: NamedRef;
	// Admins only (Plan 5 spec §4.6).
	notes?: string;
	cancel_reason?: string;
	// Admins and the session's own teacher only.
	has_report?: boolean;
}

/** Plan 5 P5-7: 5 = excellent … 1 = poor. */
export const SCALE = [5, 4, 3, 2, 1] as const;
export interface SessionReport {
	session: number;
	behaviour: number;
	participation: number;
	notes: string;
	written_by: PersonRef;
	created_at: string;
	updated_at: string;
}

export type BulkAction = "present" | "absent" | "cancel";
export interface BulkBody {
	ids: number[];
	action: BulkAction;
	reason?: string;
}
export interface BulkResult {
	done: number[];
	skipped: { id: number; code: string }[];
}
export interface AttendanceBody {
	student_attendance?: Attendance;
	teacher_attendance?: Attendance;
}
export interface ReportBody {
	behaviour: number;
	participation: number;
	notes?: string;
}

export interface GenerationResult {
```

Append to the end of `dashboard/src/features/scheduling/schemas.ts`:

```ts
export const cancelSessionSchema = z.object({
	reason: z.string().trim().min(1, "scheduling.errors.reasonRequired"),
});
export type CancelSessionValues = z.infer<typeof cancelSessionSchema>;

const scale = z
	.number({ error: "scheduling.errors.scaleRequired" })
	.int("scheduling.errors.scaleRequired")
	.min(1, "scheduling.errors.scaleRequired")
	.max(5, "scheduling.errors.scaleRequired");
export const reportFormSchema = z.object({
	behaviour: scale,
	participation: scale,
	notes: z.string(),
});
export type ReportFormValues = z.infer<typeof reportFormSchema>;
```

In `dashboard/src/lib/zoned-time.ts`, replace:

```ts
	}).format(instant);
}

/** The student's time for a slot, or null when their clock reads the same. */
export function studentTime({
	date,
```

with:

```ts
	}).format(instant);
}

/** `instant` on `theirZone`'s clock, or null when it reads the same as on
 * `ourZone`'s (Plan 4 SCHED-017). For a saved session or slot row, pass the
 * server's `starts_at` — never an instant recomputed from a wall time. */
export function otherZoneTime(
	instant: Date,
	theirZone: string,
	ourZone: string,
	language: string,
): string | null {
	if (theirZone === ourZone) return null;
	const theirs = wallTime(instant, theirZone, language);
	return theirs === wallTime(instant, ourZone, language) ? null : theirs;
}

/** `instant`'s calendar date on `timeZone`'s clock, e.g. "Jun 1, 2026". */
export function dayIn(
	instant: Date,
	timeZone: string,
	language: string,
): string {
	return new Intl.DateTimeFormat(language, {
		dateStyle: "medium",
		timeZone,
	}).format(instant);
}

/** The student's time for a slot, or null when their clock reads the same. */
export function studentTime({
	date,
```

Merge these keys into `dashboard/src/locales/en/common.json` and `dashboard/src/locales/ar/common.json` (a nested object merges into the existing one of the same name; a key that already exists takes the new value). Keep the files' tab indentation.

English:

```json
{
  "errors": {
    "not_found": "That session no longer exists.",
    "scheduling": {
      "not_started": "Attendance opens when the session starts.",
      "session_cancelled": "This session was cancelled.",
      "not_completed": "Mark the student's attendance before writing a report."
    }
  },
  "academySettings": {
    "countsAsUsed": "A session counts as used",
    "absentCounts": "When the student is absent",
    "excusedCounts": "When the student is excused",
    "countsHint": "A session always counts when the student is present and never when the teacher is absent. Changing these updates every subscription's numbers."
  },
  "scheduling": {
    "errors": {
      "reasonRequired": "Give a reason.",
      "scaleRequired": "Choose one of the five."
    }
  }
}
```

Arabic:

```json
{
  "errors": {
    "not_found": "هذه الحصة لم تعد موجودة.",
    "scheduling": {
      "not_started": "يُفتح تسجيل الحضور عند بدء الحصة.",
      "session_cancelled": "أُلغيت هذه الحصة.",
      "not_completed": "سجّل حضور الطالب قبل كتابة التقرير."
    }
  },
  "academySettings": {
    "countsAsUsed": "تُحتسب الحصة مستهلكة",
    "absentCounts": "عند غياب الطالب",
    "excusedCounts": "عند غياب الطالب بعذر",
    "countsHint": "تُحتسب الحصة دائمًا عند حضور الطالب، ولا تُحتسب أبدًا عند غياب المعلم. تغيير هذه الخيارات يحدّث أرقام كل الاشتراكات."
  },
  "scheduling": {
    "errors": {
      "reasonRequired": "اذكر السبب.",
      "scaleRequired": "اختر واحدًا من الخمسة."
    }
  }
}
```

- [ ] **Step 5: Format and regenerate routes**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src && npx pnpm@10 exec vite build`
(the build regenerates `src/routeTree.gen.ts`).

- [ ] **Step 6: Run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features src/lib`
Expected: PASS, TodayBoard's student-time tests included (now through `otherZoneTime`).

- [ ] **Step 7: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass; coverage lines/statements ≥ 80, branches/functions ≥ 70; `check-colors` prints no findings.

- [ ] **Step 8: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): session data layer, zone helpers, role guard and counting switches

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Dashboard: the admin session page (attendance, cancel/restore, report)

**Files:**
- Create: `dashboard/src/features/scheduling/AttendanceControls.tsx`, `dashboard/src/features/scheduling/CancelSessionDialog.tsx`, `dashboard/src/features/scheduling/ReportForm.tsx`, `dashboard/src/features/scheduling/SessionPage.tsx`, `dashboard/src/routes/_authed/scheduling.sessions.$sessionId.tsx`
- Modify: `dashboard/src/features/scheduling/bits.tsx`, `dashboard/src/features/scheduling/index.ts`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`, `dashboard/src/routeTree.gen.ts` (generated)
- Test: `dashboard/src/features/scheduling/AttendanceControls.test.tsx` (new), `dashboard/src/features/scheduling/ReportForm.test.tsx` (new), `dashboard/src/features/scheduling/SessionPage.test.tsx` (new), `dashboard/src/test/scheduling-fixtures.ts`

**Interfaces:**
- Consumes: Task 9's API, hooks, schemas and `otherZoneTime`.
- Produces (`@/features/scheduling`): `SessionPage({ sessionId: string })`; internal `AttendanceControls({ session, canClear })` (native selects named `Student attendance for {name}` / `Teacher attendance for {name}`, D16), `CancelSessionDialog({ action, body, onCancel(reason) })`, `ReportForm({ sessionId, report?, onSaved? })` (D15); `bits.SessionStatusChip({ status })`, `bits.JoinLink({ session })` (link named `Join the session with {name}`).
- Produces: route `/scheduling/sessions/$sessionId` (admin, under Plan 4's `/scheduling` guard).
- Produces (tests): `academySettings(overrides)` in `@/test/scheduling-fixtures`.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/scheduling/AttendanceControls.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { sessionRow } from "@/test/scheduling-fixtures";
import { AttendanceControls } from "./AttendanceControls";
import { schedulingApi } from "./api";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, markAttendance: vi.fn() },
	};
});

// The router renders asynchronously, so each test finds its controls first.
const student = () =>
	screen.findByRole("combobox", { name: "Student attendance for Yusuf" });
const teacher = () =>
	screen.findByRole("combobox", { name: "Teacher attendance for Yusuf" });

describe("AttendanceControls", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(schedulingApi.markAttendance).mockResolvedValue(sessionRow());
	});

	it("marks the student and the teacher separately", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<AttendanceControls session={sessionRow()} canClear={false} />,
		);
		await user.selectOptions(await student(), "present");
		await waitFor(() =>
			expect(schedulingApi.markAttendance).toHaveBeenCalledWith({
				id: 41,
				student_attendance: "present",
			}),
		);
		await user.selectOptions(await teacher(), "absent");
		await waitFor(() =>
			expect(schedulingApi.markAttendance).toHaveBeenLastCalledWith({
				id: 41,
				teacher_attendance: "absent",
			}),
		);
	});

	it("stays closed until the session has started", async () => {
		renderWithRouter(
			<AttendanceControls
				session={sessionRow({ has_started: false })}
				canClear
			/>,
		);
		expect(await student()).toBeDisabled();
		expect(await teacher()).toBeDisabled();
		expect(
			screen.getByText("Attendance opens at the start time."),
		).toBeInTheDocument();
	});

	it("stays closed on a cancelled session", async () => {
		renderWithRouter(
			<AttendanceControls
				session={sessionRow({ status: "cancelled" })}
				canClear
			/>,
		);
		expect(await student()).toBeDisabled();
		expect(
			screen.queryByText("Attendance opens at the start time."),
		).toBeNull();
	});

	it("lets only an admin set an attendance back to Not set", async () => {
		const marked = sessionRow({
			status: "completed",
			student_attendance: "absent",
		});
		const { unmount } = renderWithRouter(
			<AttendanceControls session={marked} canClear={false} />,
		);
		expect(await student()).toHaveValue("absent");
		expect(
			screen.getAllByRole("option", { name: "Not set" })[0],
		).toBeDisabled();
		unmount();
		renderWithRouter(<AttendanceControls session={marked} canClear />);
		await student();
		expect(screen.getAllByRole("option", { name: "Not set" })[0]).toBeEnabled();
	});

	it("says why the server refused", async () => {
		vi.mocked(schedulingApi.markAttendance).mockRejectedValue(
			new AxiosError("Conflict", "409", undefined, undefined, {
				status: 409,
				data: { detail: "Too early.", code: "scheduling.not_started" },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(
			<AttendanceControls session={sessionRow()} canClear={false} />,
		);
		await user.selectOptions(await student(), "excused");
		expect(
			await screen.findByText("Attendance opens when the session starts."),
		).toBeInTheDocument();
	});
});
```

Create `dashboard/src/features/scheduling/ReportForm.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { reportRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { ReportForm } from "./ReportForm";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, saveReport: vi.fn() },
	};
});

describe("ReportForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(schedulingApi.saveReport).mockResolvedValue(reportRow());
	});

	it("needs both scales, then saves them with the notes", async () => {
		const onSaved = vi.fn();
		const user = userEvent.setup();
		renderWithRouter(<ReportForm sessionId={41} onSaved={onSaved} />);
		await user.click(
			await screen.findByRole("button", { name: "Save report" }),
		);
		expect(await screen.findAllByText("Choose one of the five.")).toHaveLength(
			2,
		);
		expect(schedulingApi.saveReport).not.toHaveBeenCalled();
		await user.selectOptions(screen.getByLabelText(/^Behaviour/), "5");
		await user.selectOptions(screen.getByLabelText(/^Participation/), "Good");
		await user.type(screen.getByLabelText("Notes"), "Fluent");
		await user.click(screen.getByRole("button", { name: "Save report" }));
		await waitFor(() =>
			expect(schedulingApi.saveReport).toHaveBeenCalledWith({
				id: 41,
				behaviour: 5,
				participation: 4,
				notes: "Fluent",
			}),
		);
		expect(await screen.findByText("Report saved.")).toBeInTheDocument();
		expect(onSaved).toHaveBeenCalled();
	});

	it("starts from the saved report", async () => {
		renderWithRouter(<ReportForm sessionId={41} report={reportRow()} />);
		expect(await screen.findByLabelText(/^Behaviour/)).toHaveValue("5");
		expect(screen.getByLabelText(/^Participation/)).toHaveValue("4");
		expect(screen.getByLabelText("Notes")).toHaveValue("Recited clearly.");
	});

	it("shows a refusal in the reader's language", async () => {
		vi.mocked(schedulingApi.saveReport).mockRejectedValue(
			new AxiosError("Conflict", "409", undefined, undefined, {
				status: 409,
				data: { detail: "Not completed.", code: "scheduling.not_completed" },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<ReportForm sessionId={41} report={reportRow()} />);
		await user.click(
			await screen.findByRole("button", { name: "Save report" }),
		);
		expect(
			await screen.findByText(
				"Mark the student's attendance before writing a report.",
			),
		).toBeInTheDocument();
	});
});
```

Create `dashboard/src/features/scheduling/SessionPage.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { renderWithRouter } from "@/test/render";
import {
	academySettings,
	reportRow,
	sessionRow,
} from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SessionPage } from "./SessionPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			session: vi.fn(),
			report: vi.fn(),
			cancelSession: vi.fn(),
			restoreSession: vi.fn(),
			markAttendance: vi.fn(),
			saveReport: vi.fn(),
		},
	};
});
vi.mock("@/features/academy/api", () => ({
	academyApi: { get: vi.fn(), update: vi.fn() },
}));

describe("SessionPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(schedulingApi.session).mockResolvedValue(
			sessionRow({ notes: "Bring the book" }),
		);
	});

	it("shows the details in the academy's time and the student's", async () => {
		renderWithRouter(<SessionPage sessionId="41" />);
		expect(await screen.findByText("Jun 1, 2026")).toBeInTheDocument();
		expect(screen.getByText("18:00")).toBeInTheDocument();
		expect(screen.getByText("Student's time: 21:00")).toBeInTheDocument();
		expect(screen.getByText("Bring the book")).toBeInTheDocument();
		expect(
			screen.getByRole("link", { name: "Join the session with Yusuf" }),
		).toHaveAttribute("href", "https://meet.test/bilal");
		expect(
			screen.getByText(
				"A report can be written once the student's attendance is marked.",
			),
		).toBeInTheDocument();
		expect(schedulingApi.session).toHaveBeenCalledWith(41);
	});

	it("cancels with a reason", async () => {
		vi.mocked(schedulingApi.cancelSession).mockResolvedValue(
			sessionRow({ status: "cancelled" }),
		);
		const user = userEvent.setup();
		renderWithRouter(<SessionPage sessionId="41" />);
		await user.click(
			await screen.findByRole("button", { name: "Cancel session" }),
		);
		const dialog = screen.getByRole("dialog");
		await user.click(
			within(dialog).getByRole("button", { name: "Cancel session" }),
		);
		expect(
			await within(dialog).findByText("Give a reason."),
		).toBeInTheDocument();
		await user.type(within(dialog).getByLabelText(/^Reason/), "Eid");
		await user.click(
			within(dialog).getByRole("button", { name: "Cancel session" }),
		);
		await waitFor(() =>
			expect(schedulingApi.cancelSession).toHaveBeenCalledWith({
				id: 41,
				reason: "Eid",
			}),
		);
	});

	it("restores a cancelled session", async () => {
		vi.mocked(schedulingApi.session).mockResolvedValue(
			sessionRow({ status: "cancelled", cancel_reason: "Eid" }),
		);
		vi.mocked(schedulingApi.restoreSession).mockResolvedValue(sessionRow());
		const user = userEvent.setup();
		renderWithRouter(<SessionPage sessionId="41" />);
		expect(await screen.findByText("Cancelled: Eid")).toBeInTheDocument();
		expect(
			screen.getByRole("combobox", { name: "Student attendance for Yusuf" }),
		).toBeDisabled();
		await user.click(screen.getByRole("button", { name: "Restore session" }));
		await waitFor(() =>
			expect(schedulingApi.restoreSession).toHaveBeenCalledWith(41),
		);
	});

	it("loads the report of a completed session into the form", async () => {
		vi.mocked(schedulingApi.session).mockResolvedValue(
			sessionRow({
				status: "completed",
				student_attendance: "present",
				has_report: true,
			}),
		);
		vi.mocked(schedulingApi.report).mockResolvedValue(reportRow());
		renderWithRouter(<SessionPage sessionId="41" />);
		expect(await screen.findByText("Written by Bilal")).toBeInTheDocument();
		expect(screen.getByLabelText(/^Behaviour/)).toHaveValue("5");
		expect(schedulingApi.report).toHaveBeenCalledWith(41);
	});

	it("offers an empty report form when none is written yet", async () => {
		vi.mocked(schedulingApi.session).mockResolvedValue(
			sessionRow({ status: "completed", student_attendance: "present" }),
		);
		renderWithRouter(<SessionPage sessionId="41" />);
		expect(await screen.findByLabelText(/^Behaviour/)).toHaveValue("");
		expect(schedulingApi.report).not.toHaveBeenCalled();
	});

	it("handles a bad id, a missing session and a failed load", async () => {
		const { unmount } = renderWithRouter(<SessionPage sessionId="abc" />);
		expect(
			await screen.findByText("This session doesn't exist."),
		).toBeInTheDocument();
		expect(schedulingApi.session).not.toHaveBeenCalled();
		unmount();
		vi.mocked(schedulingApi.session).mockRejectedValueOnce(
			new AxiosError("Not found", "404", undefined, undefined, {
				status: 404,
				data: {},
			} as never),
		);
		const second = renderWithRouter(<SessionPage sessionId="9" />);
		expect(
			await screen.findByText("This session doesn't exist."),
		).toBeInTheDocument();
		second.unmount();
		vi.mocked(schedulingApi.session).mockRejectedValueOnce(new Error("x"));
		renderWithRouter(<SessionPage sessionId="9" />);
		expect(
			await screen.findByText("Couldn't load the session."),
		).toBeInTheDocument();
	});
});
```

In `dashboard/src/test/scheduling-fixtures.ts`, replace:

```ts
import type {
	Session,
	SessionReport,
```

with:

```ts
import type { AcademySettings } from "@/features/academy/api";
import type {
	Session,
	SessionReport,
```

Append to the end of `dashboard/src/test/scheduling-fixtures.ts`:

```ts
/** The academy's settings as `academy/settings/` sends them (UTC, English). */
export function academySettings(
	overrides: Partial<AcademySettings> = {},
): AcademySettings {
	return {
		timezone: "UTC",
		default_currency: "EGP",
		default_language: "en",
		generation_horizon_days: 14,
		renewal_grace_days: 7,
		absent_consumes_session: true,
		excused_consumes_session: false,
		...overrides,
	};
}
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling/AttendanceControls.test.tsx src/features/scheduling/ReportForm.test.tsx src/features/scheduling/SessionPage.test.tsx`
Expected: FAIL — `Failed to resolve import "./AttendanceControls"` (and `./ReportForm`, `./SessionPage`).

- [ ] **Step 3: Implement**

Create `dashboard/src/features/scheduling/AttendanceControls.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { errorText } from "@/lib/form-errors";
import { Select, toast } from "@/ui";
import { schedulingApi } from "./api";
import { useSchedulingMutation } from "./queries";
import { ATTENDANCE, type Attendance, type Session } from "./schemas";

/** The student's and the teacher's attendance for one session (spec §4.1).
 * Closed until the server says the session has started, and on a cancelled
 * session. Only an admin (`canClear`) may set one back to "Not set". */
export function AttendanceControls({
	session,
	canClear,
}: {
	session: Session;
	canClear: boolean;
}) {
	const { t } = useTranslation();
	const mark = useSchedulingMutation(schedulingApi.markAttendance);
	const closed =
		!session.has_started || session.status === "cancelled" || mark.isPending;
	const name = session.student.full_name;

	function save(field: "student_attendance" | "teacher_attendance") {
		return (value: string) =>
			mark.mutate(
				{ id: session.id, [field]: value as Attendance },
				{
					onError: (error) =>
						toast({ description: errorText(error, t), variant: "destructive" }),
				},
			);
	}

	const picker = (
		field: "student_attendance" | "teacher_attendance",
		label: string,
	) => (
		<Select
			aria-label={label}
			className="w-auto px-2"
			value={session[field]}
			disabled={closed}
			onChange={(e) => save(field)(e.target.value)}
		>
			{ATTENDANCE.map((value) => (
				<option
					key={value}
					value={value}
					disabled={value === "not_set" && !canClear}
				>
					{t(`scheduling.attendance.${value}`)}
				</option>
			))}
		</Select>
	);

	return (
		<div className="flex flex-col gap-1">
			<div className="flex flex-wrap items-center gap-2">
				{picker(
					"student_attendance",
					t("scheduling.attendance.studentFor", { name }),
				)}
				{picker(
					"teacher_attendance",
					t("scheduling.attendance.teacherFor", { name }),
				)}
			</div>
			{!session.has_started && session.status !== "cancelled" ? (
				<p className="text-xs text-muted-foreground">
					{t("scheduling.attendance.opensAtStart")}
				</p>
			) : null}
		</div>
	);
}
```

Create `dashboard/src/features/scheduling/CancelSessionDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	SubmitButton,
	Textarea,
} from "@/ui";
import { type CancelSessionValues, cancelSessionSchema } from "./schemas";

/** A reason dialog for cancelling (spec §4.3, §4.4). `onCancel` does the
 * write: one session on its page, or the selected rows in bulk. */
export function CancelSessionDialog({
	action,
	body,
	onCancel,
}: {
	action: string;
	body: string;
	onCancel: (reason: string) => Promise<unknown>;
}) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const {
		register,
		handleSubmit,
		setError,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<CancelSessionValues>({
		resolver: zodResolver(cancelSessionSchema),
		defaultValues: { reason: "" },
	});

	async function onSubmit(values: CancelSessionValues) {
		try {
			await onCancel(values.reason);
			reset();
			setOpen(false);
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="destructive">
					{action}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{action}</DialogTitle>
				<DialogDescription>{body}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id="cancel-reason"
						label={t("scheduling.session.reason")}
						error={fieldError(errors.reason?.message)}
						required
					>
						<Textarea {...register("reason")} />
					</Field>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.root.server.message)}
							</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("scheduling.session.keep")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting} variant="destructive">
							{action}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/scheduling/ReportForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import {
	Alert,
	AlertDescription,
	Field,
	Select,
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { schedulingApi } from "./api";
import { useSchedulingMutation } from "./queries";
import {
	type ReportFormValues,
	reportFormSchema,
	SCALE,
	type SessionReport,
} from "./schemas";

/** The session report (spec §4.5, P5-7): two five-point scales and notes.
 * Staff-only: the session's teacher and admins. */
export function ReportForm({
	sessionId,
	report,
	onSaved,
}: {
	sessionId: number;
	report?: SessionReport;
	onSaved?: () => void;
}) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const save = useSchedulingMutation(schedulingApi.saveReport);
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<ReportFormValues>({
		resolver: zodResolver(reportFormSchema),
		defaultValues: {
			behaviour: report?.behaviour,
			participation: report?.participation,
			notes: report?.notes ?? "",
		},
	});

	async function onSubmit(values: ReportFormValues) {
		try {
			await save.mutateAsync({ id: sessionId, ...values });
			toast({ description: t("scheduling.report.saved"), variant: "success" });
			onSaved?.();
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	const scale = (name: "behaviour" | "participation") => (
		<Field
			id={`report-${sessionId}-${name}`}
			label={t(`scheduling.report.${name}`)}
			error={fieldError(errors[name]?.message)}
			required
		>
			<Select {...register(name, { valueAsNumber: true })}>
				<option value="">{t("scheduling.report.choose")}</option>
				{SCALE.map((value) => (
					<option key={value} value={value}>
						{t(`scheduling.report.scale.${value}`)}
					</option>
				))}
			</Select>
		</Field>
	);

	return (
		<form
			onSubmit={handleSubmit(onSubmit)}
			className="flex flex-col gap-4"
			noValidate
		>
			{scale("behaviour")}
			{scale("participation")}
			<Field
				id={`report-${sessionId}-notes`}
				label={t("scheduling.report.notes")}
				error={fieldError(errors.notes?.message)}
			>
				<Textarea {...register("notes")} />
			</Field>
			{errors.root?.server ? (
				<Alert variant="destructive">
					<AlertDescription>
						{fieldError(errors.root.server.message)}
					</AlertDescription>
				</Alert>
			) : null}
			<SubmitButton pending={isSubmitting} className="self-start">
				{t("scheduling.report.save")}
			</SubmitButton>
		</form>
	);
}
```

Create `dashboard/src/features/scheduling/SessionPage.tsx`:

```tsx
import { isAxiosError } from "axios";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { errorText } from "@/lib/form-errors";
import { formatDay, otherZoneTime, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
	toast,
} from "@/ui";
import { AttendanceControls } from "./AttendanceControls";
import { schedulingApi } from "./api";
import { JoinLink, SessionStatusChip, useLocalName } from "./bits";
import { CancelSessionDialog } from "./CancelSessionDialog";
import { useReport, useSchedulingMutation, useSession } from "./queries";
import { ReportForm } from "./ReportForm";
import type { Session } from "./schemas";

function Fact({ label, children }: { label: string; children: ReactNode }) {
	return (
		<div className="flex flex-col gap-0.5">
			<dt className="text-xs text-muted-foreground">{label}</dt>
			<dd className="font-medium">{children}</dd>
		</div>
	);
}

function ReportCard({ session }: { session: Session }) {
	const { t } = useTranslation();
	const { data: report, isError } = useReport(
		session.id,
		Boolean(session.has_report),
	);
	let body: ReactNode;
	if (session.status !== "completed") {
		body = (
			<p className="text-sm text-muted-foreground">
				{t("scheduling.report.afterCompleted")}
			</p>
		);
	} else if (isError) {
		body = (
			<Alert variant="destructive">
				<AlertDescription>{t("scheduling.report.loadError")}</AlertDescription>
			</Alert>
		);
	} else if (session.has_report && !report) {
		body = <Spinner />;
	} else {
		body = <ReportForm sessionId={session.id} report={report} />;
	}
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("scheduling.report.title")}</CardTitle>
				{report ? (
					<p className="text-sm text-muted-foreground">
						{t("scheduling.report.writtenBy", {
							name: report.written_by.full_name,
						})}
					</p>
				) : null}
			</CardHeader>
			<CardContent>{body}</CardContent>
		</Card>
	);
}

/** Spec §6 Session page (admin): details and the join link, both
 * attendances, cancel and restore, and the report. Times are the academy's,
 * plus the student's when their clock differs (P5-8). */
export function SessionPage({ sessionId }: { sessionId: string }) {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	const { data: academy } = useAcademySettings();
	const parsed = Number(sessionId);
	// `/scheduling/sessions/abc` is never a session: no request.
	const invalidId = !Number.isInteger(parsed) || parsed < 1;
	const {
		data: session,
		isError,
		error,
	} = useSession(invalidId ? undefined : parsed);
	const cancel = useSchedulingMutation(schedulingApi.cancelSession);
	const restore = useSchedulingMutation(schedulingApi.restoreSession);
	const status = isAxiosError(error) ? error.response?.status : undefined;
	if (invalidId || status === 404 || isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>
					{invalidId || status === 404
						? t("scheduling.session.notFound")
						: t("scheduling.session.loadError")}
				</AlertDescription>
			</Alert>
		);
	}
	if (!session || !academy) return <Spinner />;
	const instant = new Date(session.starts_at);
	const theirs = otherZoneTime(
		instant,
		session.student.timezone,
		academy.timezone,
		i18n.language,
	);

	return (
		<div className="flex flex-col gap-6">
			<Card>
				<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
					<CardTitle>{session.student.full_name}</CardTitle>
					<SessionStatusChip status={session.status} />
				</CardHeader>
				<CardContent className="flex flex-col gap-4">
					<dl className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
						<Fact label={t("scheduling.sessions.columns.date")}>
							{formatDay(session.occurs_on, i18n.language)}
						</Fact>
						<Fact label={t("scheduling.sessions.columns.time")}>
							<span dir="ltr">
								{wallTime(instant, academy.timezone, i18n.language)}
							</span>
							{theirs ? (
								<span className="block text-xs font-normal text-muted-foreground">
									{t("scheduling.slots.studentTime", { time: theirs })}
								</span>
							) : null}
						</Fact>
						<Fact label={t("scheduling.sessions.columns.minutes")}>
							{session.minutes}
						</Fact>
						<Fact label={t("scheduling.columns.course")}>
							{localName(session.course)}
						</Fact>
						<Fact label={t("scheduling.columns.teacher")}>
							{session.teacher.full_name}
						</Fact>
						<Fact label={t("scheduling.sessions.columns.link")}>
							<JoinLink session={session} />
						</Fact>
					</dl>
					{session.notes ? (
						<p className="text-sm text-muted-foreground">{session.notes}</p>
					) : null}
					{session.status === "cancelled" ? (
						<p className="text-sm">
							{t("scheduling.session.cancelledBecause", {
								reason: session.cancel_reason,
							})}
						</p>
					) : null}
				</CardContent>
			</Card>
			<Card>
				<CardHeader className="border-b border-border">
					<CardTitle>{t("scheduling.attendance.title")}</CardTitle>
				</CardHeader>
				<CardContent className="flex flex-col gap-4">
					<AttendanceControls session={session} canClear />
					<div className="flex flex-wrap gap-2">
						{session.status === "cancelled" ? (
							<Button
								size="sm"
								variant="outline"
								disabled={restore.isPending}
								onClick={() =>
									restore.mutate(session.id, {
										onError: (e) =>
											toast({
												description: errorText(e, t),
												variant: "destructive",
											}),
									})
								}
							>
								{t("scheduling.session.restore")}
							</Button>
						) : (
							<CancelSessionDialog
								action={t("scheduling.session.cancel")}
								body={t("scheduling.session.cancelBody")}
								onCancel={(reason) =>
									cancel.mutateAsync({ id: session.id, reason })
								}
							/>
						)}
					</div>
				</CardContent>
			</Card>
			<ReportCard session={session} />
		</div>
	);
}
```

In `dashboard/src/features/scheduling/bits.tsx`, replace:

```tsx
import { useTranslation } from "react-i18next";
import { Meter, StatusChip } from "@/ui";
import type { NamedRef, SubscriptionStatus } from "./schemas";

const TONE: Record<SubscriptionStatus, "live" | "neutral" | "warning"> = {
	active: "live",
```

with:

```tsx
import { useTranslation } from "react-i18next";
import { Meter, StatusChip } from "@/ui";
import type {
	NamedRef,
	Session,
	SessionStatus,
	SubscriptionStatus,
} from "./schemas";

const TONE: Record<SubscriptionStatus, "live" | "neutral" | "warning"> = {
	active: "live",
```

Append to the end of `dashboard/src/features/scheduling/bits.tsx`:

```tsx
const SESSION_TONE: Record<SessionStatus, "live" | "neutral" | "warning"> = {
	scheduled: "live",
	completed: "neutral",
	cancelled: "warning",
};

export function SessionStatusChip({ status }: { status: SessionStatus }) {
	const { t } = useTranslation();
	return (
		<StatusChip tone={SESSION_TONE[status]}>
			{t(`scheduling.sessions.status.${status}`)}
		</StatusChip>
	);
}

/** The session's meeting link, named for its student so a list of them reads
 * well; nothing for a cancelled session or one without a link. */
export function JoinLink({ session }: { session: Session }) {
	const { t } = useTranslation();
	if (!session.meeting_url || session.status === "cancelled") return null;
	return (
		<a
			href={session.meeting_url}
			target="_blank"
			rel="noreferrer"
			aria-label={t("scheduling.session.joinName", {
				name: session.student.full_name,
			})}
			className="font-medium text-primary-text underline-offset-4 hover:underline"
		>
			{t("scheduling.session.join")}
		</a>
	);
}
```

In `dashboard/src/features/scheduling/index.ts`, replace:

```ts
export { schedulingApi, sessionsCsvUrl, subscriptionsCsvUrl } from "./api";
export * from "./queries";
export { SubscriptionDetail } from "./SubscriptionDetail";
export { SubscriptionForm } from "./SubscriptionForm";
export { SubscriptionsList } from "./SubscriptionsList";
```

with:

```ts
export { schedulingApi, sessionsCsvUrl, subscriptionsCsvUrl } from "./api";
export * from "./queries";
export { SessionPage } from "./SessionPage";
export { SubscriptionDetail } from "./SubscriptionDetail";
export { SubscriptionForm } from "./SubscriptionForm";
export { SubscriptionsList } from "./SubscriptionsList";
```

Create `dashboard/src/routes/_authed/scheduling.sessions.$sessionId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SessionPage } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/scheduling/sessions/$sessionId")(
	{
		component: function SessionRoute() {
			const { t } = useTranslation();
			const { sessionId } = Route.useParams();
			usePageTitle(t("scheduling.session.title"));
			return (
				<>
					<PageHeader title={t("scheduling.session.title")} />
					<SessionPage sessionId={sessionId} />
				</>
			);
		},
	},
);
```

Merge these keys into `dashboard/src/locales/en/common.json` and `dashboard/src/locales/ar/common.json` (a nested object merges into the existing one of the same name; a key that already exists takes the new value). Keep the files' tab indentation.

English:

```json
{
  "scheduling": {
    "attendance": {
      "title": "Attendance",
      "studentFor": "Student attendance for {{name}}",
      "teacherFor": "Teacher attendance for {{name}}",
      "opensAtStart": "Attendance opens at the start time.",
      "not_set": "Not set",
      "present": "Present",
      "absent": "Absent",
      "excused": "Excused"
    },
    "session": {
      "title": "Session",
      "join": "Join",
      "joinName": "Join the session with {{name}}",
      "notFound": "This session doesn't exist.",
      "loadError": "Couldn't load the session.",
      "cancel": "Cancel session",
      "cancelBody": "The session stops counting against the package. Its attendance and report are kept.",
      "reason": "Reason",
      "keep": "Keep it",
      "restore": "Restore session",
      "cancelledBecause": "Cancelled: {{reason}}"
    },
    "report": {
      "title": "Report",
      "behaviour": "Behaviour",
      "participation": "Participation",
      "notes": "Notes",
      "choose": "Choose…",
      "save": "Save report",
      "saved": "Report saved.",
      "loadError": "Couldn't load the report.",
      "afterCompleted": "A report can be written once the student's attendance is marked.",
      "writtenBy": "Written by {{name}}",
      "scale": {
        "5": "Excellent",
        "4": "Good",
        "3": "Average",
        "2": "Below average",
        "1": "Poor"
      }
    }
  }
}
```

Arabic:

```json
{
  "scheduling": {
    "attendance": {
      "title": "الحضور",
      "studentFor": "حضور الطالب {{name}}",
      "teacherFor": "حضور المعلم مع {{name}}",
      "opensAtStart": "يُفتح تسجيل الحضور عند موعد البدء.",
      "not_set": "لم يُحدَّد",
      "present": "حاضر",
      "absent": "غائب",
      "excused": "غائب بعذر"
    },
    "session": {
      "title": "الحصة",
      "join": "انضمام",
      "joinName": "الانضمام إلى الحصة مع {{name}}",
      "notFound": "هذه الحصة غير موجودة.",
      "loadError": "تعذّر تحميل الحصة.",
      "cancel": "إلغاء الحصة",
      "cancelBody": "لن تُحتسب الحصة من الباقة. يبقى حضورها وتقريرها محفوظين.",
      "reason": "السبب",
      "keep": "إبقاؤها",
      "restore": "استعادة الحصة",
      "cancelledBecause": "أُلغيت: {{reason}}"
    },
    "report": {
      "title": "التقرير",
      "behaviour": "السلوك",
      "participation": "المشاركة",
      "notes": "ملاحظات",
      "choose": "اختر…",
      "save": "حفظ التقرير",
      "saved": "حُفظ التقرير.",
      "loadError": "تعذّر تحميل التقرير.",
      "afterCompleted": "يمكن كتابة التقرير بعد تسجيل حضور الطالب.",
      "writtenBy": "كتبه {{name}}",
      "scale": {
        "5": "ممتاز",
        "4": "جيد",
        "3": "متوسط",
        "2": "دون المتوسط",
        "1": "ضعيف"
      }
    }
  }
}
```

- [ ] **Step 4: Format and regenerate routes**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src && npx pnpm@10 exec vite build`
(the build regenerates `src/routeTree.gen.ts`).

- [ ] **Step 5: Run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling`
Expected: PASS.

- [ ] **Step 6: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass; coverage lines/statements ≥ 80, branches/functions ≥ 70; `check-colors` prints no findings.

- [ ] **Step 7: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): admin session page with attendance, cancel, restore and report

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Dashboard: admin Sessions list with filters, CSV and bulk actions

**Files:**
- Create: `dashboard/src/features/scheduling/SessionBulkBar.tsx`, `dashboard/src/features/scheduling/SessionsList.tsx`, `dashboard/src/routes/_authed/scheduling.sessions.index.tsx`
- Modify: `dashboard/src/features/scheduling/index.ts`, `dashboard/src/features/shell/nav.ts`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`, `dashboard/src/routeTree.gen.ts` (generated)
- Test: `dashboard/src/features/scheduling/SessionsList.test.tsx` (new), `dashboard/src/features/shell/nav.test.ts`

**Interfaces:**
- Consumes: Task 9's `useSessionList`, `sessionsCsvUrl`, `schedulingApi.bulk`; Task 10's `SessionStatusChip`, `CancelSessionDialog` and the session page route.
- Produces: `SessionsList()` (exported), internal `SessionBulkBar({ selected, onDone })`; route `/scheduling/sessions`; nav item `nav.sessions` in the Scheduling group after Today (D2, D17).

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/scheduling/SessionsList.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { academySettings, page, sessionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SessionsList } from "./SessionsList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			sessionList: vi.fn(),
			bulk: vi.fn(),
		},
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return {
		...actual,
		catalogueApi: { ...actual.catalogueApi, list: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({
	academyApi: { get: vi.fn(), update: vi.fn() },
}));

function lastParams() {
	return vi.mocked(schedulingApi.sessionList).mock.calls.at(-1)?.[0];
}

const AISHA = sessionRow({
	id: 42,
	student: { id: 12, full_name: "Aisha", timezone: "UTC" },
	status: "completed",
	student_attendance: "absent",
	teacher_attendance: "present",
});

describe("SessionsList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 21, user: { full_name: "Bilal" } }]) as never,
		);
		vi.mocked(catalogueApi.list).mockResolvedValue(
			page([{ id: 3, name_ar: "تجويد", name_en: "Tajweed" }]) as never,
		);
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(
			page([sessionRow(), AISHA]),
		);
	});

	it("shows today's sessions in the academy's time and the student's", async () => {
		renderWithRouter(<SessionsList />);
		const table = await screen.findByRole("table");
		const [, yusuf, aisha] = within(table).getAllByRole("row");
		expect(within(yusuf).getByText("18:00")).toBeInTheDocument();
		expect(
			within(yusuf).getByText("Student's time: 21:00"),
		).toBeInTheDocument();
		expect(within(yusuf).getByRole("link", { name: "Yusuf" })).toHaveAttribute(
			"href",
			"/scheduling/sessions/41",
		);
		// Aisha's clock is the academy's: no second time.
		expect(within(aisha).queryByText(/Student's time/)).toBeNull();
		expect(
			within(aisha).getByText("Student: Absent · Teacher: Present"),
		).toBeInTheDocument();
		expect(within(aisha).getByText("Completed")).toBeInTheDocument();
		expect(lastParams()).toEqual({ when: "today", page: 1 });
	});

	it("filters, searches and exports what it shows", async () => {
		const user = userEvent.setup();
		renderWithRouter(<SessionsList />);
		await screen.findByRole("table");
		await user.selectOptions(screen.getByLabelText("Period"), "week");
		await waitFor(() => expect(lastParams()).toMatchObject({ when: "week" }));
		await user.selectOptions(screen.getByLabelText("Status"), "cancelled");
		await user.selectOptions(
			screen.getByLabelText("Student attendance"),
			"excused",
		);
		await user.selectOptions(screen.getByLabelText("Teacher"), "21");
		await user.selectOptions(screen.getByLabelText("Course"), "3");
		await user.type(screen.getByLabelText("From"), "2026-06-01");
		await user.type(screen.getByRole("searchbox"), "ai");
		await waitFor(() =>
			expect(lastParams()).toEqual({
				when: "week",
				status: "cancelled",
				student_attendance: "excused",
				teacher: "21",
				course: "3",
				from: "2026-06-01",
				q: "ai",
				page: 1,
			}),
		);
		expect(screen.getByRole("link", { name: "Export CSV" })).toHaveAttribute(
			"href",
			"/api/v1/sessions/?when=week&status=cancelled&student_attendance=excused&teacher=21&course=3&from=2026-06-01&q=ai&format=csv",
		);
		await user.selectOptions(screen.getByLabelText("Period"), "all");
		await waitFor(() => expect(lastParams()?.when).toBeUndefined());
	});

	it("marks the chosen sessions present and says what was skipped", async () => {
		vi.mocked(schedulingApi.bulk).mockResolvedValue({
			done: [41],
			skipped: [{ id: 42, code: "scheduling.session_cancelled" }],
		});
		const user = userEvent.setup();
		renderWithRouter(<SessionsList />);
		await user.click(
			await screen.findByLabelText("Select Yusuf's session on Jun 1, 2026"),
		);
		await user.click(
			screen.getByLabelText("Select Aisha's session on Jun 1, 2026"),
		);
		const bar = screen.getByRole("region", { name: "Bulk actions" });
		expect(within(bar).getByText("2 selected")).toBeInTheDocument();
		await user.click(within(bar).getByRole("button", { name: "Mark present" }));
		await waitFor(() =>
			expect(schedulingApi.bulk).toHaveBeenCalledWith({
				ids: [41, 42],
				action: "present",
			}),
		);
		expect(await screen.findByText("Done: 1. Skipped: 1.")).toBeInTheDocument();
		expect(
			screen.getByText("Session 42: This session was cancelled."),
		).toBeInTheDocument();
		expect(screen.queryByRole("region", { name: "Bulk actions" })).toBeNull();
	});

	it("cancels every session on the page with a reason", async () => {
		vi.mocked(schedulingApi.bulk).mockResolvedValue({
			done: [41, 42],
			skipped: [],
		});
		const user = userEvent.setup();
		renderWithRouter(<SessionsList />);
		await user.click(
			await screen.findByLabelText("Select every session on this page"),
		);
		await user.click(screen.getByRole("button", { name: "Cancel sessions" }));
		const dialog = screen.getByRole("dialog");
		await user.click(
			within(dialog).getByRole("button", { name: "Cancel sessions" }),
		);
		expect(
			await within(dialog).findByText("Give a reason."),
		).toBeInTheDocument();
		expect(schedulingApi.bulk).not.toHaveBeenCalled();
		await user.type(within(dialog).getByLabelText(/^Reason/), "Eid");
		await user.click(
			within(dialog).getByRole("button", { name: "Cancel sessions" }),
		);
		await waitFor(() =>
			expect(schedulingApi.bulk).toHaveBeenCalledWith({
				ids: [41, 42],
				action: "cancel",
				reason: "Eid",
			}),
		);
		expect(await screen.findByText("Done: 2. Skipped: 0.")).toBeInTheDocument();
	});

	it("says when nothing matches, and when loading failed", async () => {
		vi.mocked(schedulingApi.sessionList).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<SessionsList />);
		expect(await screen.findByText("No sessions match.")).toBeInTheDocument();
		unmount();
		vi.mocked(schedulingApi.sessionList).mockRejectedValueOnce(new Error("x"));
		renderWithRouter(<SessionsList />);
		expect(
			await screen.findByText("Couldn't load the sessions."),
		).toBeInTheDocument();
	});
});
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
		expect(NAV_ITEMS.map((i) => i.to)).toEqual([
			"/",
			"/scheduling/today",
			"/scheduling/subscriptions",
			"/people/students",
			"/people/parents",
```

with:

```ts
		expect(NAV_ITEMS.map((i) => i.to)).toEqual([
			"/",
			"/scheduling/today",
			"/scheduling/sessions",
			"/scheduling/subscriptions",
			"/people/students",
			"/people/parents",
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
			"settings",
			undefined,
		]);
		expect(groups[1]?.items).toHaveLength(2);
		expect(groups[2]?.items).toHaveLength(4);
	});
});
```

with:

```ts
			"settings",
			undefined,
		]);
		expect(groups[1]?.items).toHaveLength(3);
		expect(groups[2]?.items).toHaveLength(4);
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling/SessionsList.test.tsx src/features/shell/nav.test.ts`
Expected: FAIL — `Failed to resolve import "./SessionsList"`, and the nav order lacks `/scheduling/sessions`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/scheduling/SessionBulkBar.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { codeKey, errorText } from "@/lib/form-errors";
import { Alert, AlertDescription, Button, toast } from "@/ui";
import { schedulingApi } from "./api";
import { CancelSessionDialog } from "./CancelSessionDialog";
import { useSchedulingMutation } from "./queries";
import type { BulkBody, BulkResult } from "./schemas";

/** Spec §4.4 / §6: present, absent or cancel (with a reason) for the chosen
 * sessions, then a summary of what was done and what was skipped, and why. */
export function SessionBulkBar({
	selected,
	onDone,
}: {
	selected: number[];
	onDone: () => void;
}) {
	const { t } = useTranslation();
	const [result, setResult] = useState<BulkResult | null>(null);
	const bulk = useSchedulingMutation(schedulingApi.bulk);

	async function run(body: BulkBody) {
		const outcome = await bulk.mutateAsync(body);
		setResult(outcome);
		onDone();
	}

	const mark = (action: "present" | "absent") =>
		run({ ids: selected, action }).catch((error) =>
			toast({ description: errorText(error, t), variant: "destructive" }),
		);

	return (
		<>
			{selected.length > 0 ? (
				<section
					aria-label={t("scheduling.bulk.label")}
					className="flex flex-wrap items-center gap-2 rounded-lg border border-border bg-secondary p-3"
				>
					<span className="text-sm font-medium">
						{t("scheduling.bulk.selected", { count: selected.length })}
					</span>
					<Button
						size="sm"
						variant="outline"
						disabled={bulk.isPending}
						onClick={() => mark("present")}
					>
						{t("scheduling.bulk.present")}
					</Button>
					<Button
						size="sm"
						variant="outline"
						disabled={bulk.isPending}
						onClick={() => mark("absent")}
					>
						{t("scheduling.bulk.absent")}
					</Button>
					<CancelSessionDialog
						action={t("scheduling.bulk.cancel")}
						body={t("scheduling.bulk.cancelBody", { count: selected.length })}
						onCancel={(reason) =>
							run({ ids: selected, action: "cancel", reason })
						}
					/>
				</section>
			) : null}
			{result ? (
				<Alert>
					<AlertDescription>
						<p>
							{t("scheduling.bulk.result", {
								done: result.done.length,
								skipped: result.skipped.length,
							})}
						</p>
						{result.skipped.length > 0 ? (
							<ul className="mt-2 list-disc ps-5">
								{result.skipped.map((s) => (
									<li key={s.id}>
										{t("scheduling.bulk.skippedRow", {
											id: s.id,
											reason: t(codeKey(s.code)),
										})}
									</li>
								))}
							</ul>
						) : null}
					</AlertDescription>
				</Alert>
			) : null}
		</>
	);
}
```

Create `dashboard/src/features/scheduling/SessionsList.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { CalendarClock } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { useAcademySettings } from "@/features/academy/queries";
import { type Course, useCatalogue } from "@/features/catalogue";
import { usePeople } from "@/features/people";
import type { QueryParams } from "@/lib/api";
import { formatDay, otherZoneTime, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	Checkbox,
	EmptyState,
	Input,
	Select,
	Spinner,
} from "@/ui";
import { sessionsCsvUrl } from "./api";
import { SessionStatusChip, useLocalName } from "./bits";
import { useSessionList } from "./queries";
import { SessionBulkBar } from "./SessionBulkBar";
import { ATTENDANCE, SESSION_STATUSES } from "./schemas";

// The backend paginates at 25 rows a page (StandardPagination).
const PAGE_SIZE = 25;
const PERIODS = ["today", "week", "upcoming", "past", "all"] as const;

/** Spec §6 Sessions (admin): filters, search, paging, CSV and bulk actions.
 * Times are the academy's, with the student's when their clock differs. */
export function SessionsList() {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	const [params, setParams] = useState<QueryParams>({
		when: "today",
		page: 1,
	});
	const [selected, setSelected] = useState<number[]>([]);
	const { data: academy } = useAcademySettings();
	const { data, isPending, isError } = useSessionList(params);
	const { data: teachers } = usePeople("teachers", { page_size: 100 });
	const { data: courses } = useCatalogue<Course>("courses", {
		page_size: 100,
	});
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const update = (patch: QueryParams) => {
		setParams({ ...params, page: 1, ...patch });
		setSelected([]);
	};
	const pageIds = rows.map((row) => row.id);
	const allChosen =
		pageIds.length > 0 && pageIds.every((id) => selected.includes(id));

	function toggle(id: number) {
		setSelected(
			selected.includes(id)
				? selected.filter((x) => x !== id)
				: [...selected, id],
		);
	}

	const choice = (
		key: string,
		label: string,
		any: string,
		options: { value: string | number; label: string }[],
	) => (
		<Select
			aria-label={label}
			className="w-auto"
			value={String(params[key] ?? "")}
			onChange={(e) => update({ [key]: e.target.value })}
		>
			<option value="">{any}</option>
			{options.map((o) => (
				<option key={o.value} value={o.value}>
					{o.label}
				</option>
			))}
		</Select>
	);

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				<Select
					aria-label={t("scheduling.list.period")}
					className="w-auto"
					value={String(params.when ?? "all")}
					onChange={(e) =>
						update({
							when: e.target.value === "all" ? undefined : e.target.value,
						})
					}
				>
					{PERIODS.map((period) => (
						<option key={period} value={period}>
							{t(`scheduling.list.periods.${period}`)}
						</option>
					))}
				</Select>
				<div className="flex flex-col gap-1">
					<label htmlFor="sessions-from" className="text-xs">
						{t("scheduling.list.from")}
					</label>
					<Input
						id="sessions-from"
						type="date"
						dir="ltr"
						className="w-auto"
						value={String(params.from ?? "")}
						onChange={(e) => update({ from: e.target.value })}
					/>
				</div>
				<div className="flex flex-col gap-1">
					<label htmlFor="sessions-to" className="text-xs">
						{t("scheduling.list.to")}
					</label>
					<Input
						id="sessions-to"
						type="date"
						dir="ltr"
						className="w-auto"
						value={String(params.to ?? "")}
						onChange={(e) => update({ to: e.target.value })}
					/>
				</div>
				{choice(
					"status",
					t("scheduling.columns.status"),
					t("scheduling.list.anyStatus"),
					SESSION_STATUSES.map((s) => ({
						value: s,
						label: t(`scheduling.sessions.status.${s}`),
					})),
				)}
				{choice(
					"student_attendance",
					t("scheduling.list.studentAttendance"),
					t("scheduling.list.anyAttendance"),
					ATTENDANCE.map((a) => ({
						value: a,
						label: t(`scheduling.attendance.${a}`),
					})),
				)}
				{choice(
					"teacher",
					t("scheduling.columns.teacher"),
					t("scheduling.anyTeacher"),
					(teachers?.results ?? []).map((p) => ({
						value: p.id,
						label: p.user.full_name,
					})),
				)}
				{choice(
					"course",
					t("scheduling.columns.course"),
					t("scheduling.anyCourse"),
					(courses?.results ?? []).map((c) => ({
						value: c.id,
						label: localName(c),
					})),
				)}
				<div className="min-w-48 flex-1">
					<label htmlFor="sessions-search" className="sr-only">
						{t("scheduling.search")}
					</label>
					<Input
						id="sessions-search"
						type="search"
						placeholder={t("scheduling.search")}
						value={String(params.q ?? "")}
						onChange={(e) => update({ q: e.target.value })}
					/>
				</div>
				<Button asChild variant="outline" size="sm">
					<a href={sessionsCsvUrl(params)} download>
						{t("people.exportCsv")}
					</a>
				</Button>
			</div>
			<SessionBulkBar selected={selected} onDone={() => setSelected([])} />
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>
						{t("scheduling.sessions.loadError")}
					</AlertDescription>
				</Alert>
			) : isPending || !academy ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState
							icon={CalendarClock}
							title={t("scheduling.list.empty")}
						/>
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								<th scope="col" className="w-10 p-3">
									<Checkbox
										id="select-page"
										checked={allChosen}
										onCheckedChange={(on) =>
											setSelected(
												on
													? [...new Set([...selected, ...pageIds])]
													: selected.filter((id) => !pageIds.includes(id)),
											)
										}
									/>
									<label htmlFor="select-page" className="sr-only">
										{t("scheduling.list.selectPage")}
									</label>
								</th>
								{(
									[
										"date",
										"time",
										"student",
										"teacher",
										"course",
										"status",
										"attendance",
									] as const
								).map((key) => (
									<th
										key={key}
										scope="col"
										className="p-3 text-start font-medium"
									>
										{t(`scheduling.list.columns.${key}`)}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{rows.map((session) => {
								const instant = new Date(session.starts_at);
								const theirs = otherZoneTime(
									instant,
									session.student.timezone,
									academy.timezone,
									i18n.language,
								);
								return (
									<tr key={session.id} className="border-t border-border">
										<td className="p-3">
											<Checkbox
												id={`select-${session.id}`}
												checked={selected.includes(session.id)}
												onCheckedChange={() => toggle(session.id)}
											/>
											<label
												htmlFor={`select-${session.id}`}
												className="sr-only"
											>
												{t("scheduling.list.select", {
													name: session.student.full_name,
													date: formatDay(session.occurs_on, i18n.language),
												})}
											</label>
										</td>
										<td className="p-3">
											{formatDay(session.occurs_on, i18n.language)}
										</td>
										<td className="p-3">
											<span dir="ltr">
												{wallTime(instant, academy.timezone, i18n.language)}
											</span>
											{theirs ? (
												<span className="block text-xs text-muted-foreground">
													{t("scheduling.slots.studentTime", { time: theirs })}
												</span>
											) : null}
										</td>
										<td className="p-3">
											<Link
												to="/scheduling/sessions/$sessionId"
												params={{ sessionId: String(session.id) }}
												className="font-medium text-primary-text underline-offset-4 hover:underline"
											>
												{session.student.full_name}
											</Link>
										</td>
										<td className="p-3">{session.teacher.full_name}</td>
										<td className="p-3">{localName(session.course)}</td>
										<td className="p-3">
											<SessionStatusChip status={session.status} />
										</td>
										<td className="p-3 text-xs">
											{t("scheduling.list.attendanceCell", {
												student: t(
													`scheduling.attendance.${session.student_attendance}`,
												),
												teacher: t(
													`scheduling.attendance.${session.teacher_attendance}`,
												),
											})}
										</td>
									</tr>
								);
							})}
						</tbody>
					</table>
				</div>
			)}
			<Pager
				page={page}
				pages={pages}
				onChange={(next) => {
					setParams({ ...params, page: next });
					setSelected([]);
				}}
			/>
		</div>
	);
}
```

In `dashboard/src/features/scheduling/index.ts`, replace:

```ts
export { schedulingApi, sessionsCsvUrl, subscriptionsCsvUrl } from "./api";
export * from "./queries";
export { SessionPage } from "./SessionPage";
export { SubscriptionDetail } from "./SubscriptionDetail";
export { SubscriptionForm } from "./SubscriptionForm";
export { SubscriptionsList } from "./SubscriptionsList";
```

with:

```ts
export { schedulingApi, sessionsCsvUrl, subscriptionsCsvUrl } from "./api";
export * from "./queries";
export { SessionPage } from "./SessionPage";
export { SessionsList } from "./SessionsList";
export { SubscriptionDetail } from "./SubscriptionDetail";
export { SubscriptionForm } from "./SubscriptionForm";
export { SubscriptionsList } from "./SubscriptionsList";
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	Globe,
	GraduationCap,
	Home,
	Package,
	Presentation,
	Repeat,
```

with:

```ts
	Globe,
	GraduationCap,
	Home,
	ListChecks,
	Package,
	Presentation,
	Repeat,
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
export const NAV_ITEMS: NavItem[] = [
	{ to: "/", labelKey: "auth.home", icon: Home },
	admin("/scheduling/today", "nav.today", CalendarClock, "scheduling"),
	admin("/scheduling/subscriptions", "nav.subscriptions", Repeat, "scheduling"),
	admin("/people/students", "nav.students", GraduationCap, "people"),
	admin("/people/parents", "nav.parents", Users, "people"),
```

with:

```ts
export const NAV_ITEMS: NavItem[] = [
	{ to: "/", labelKey: "auth.home", icon: Home },
	admin("/scheduling/today", "nav.today", CalendarClock, "scheduling"),
	admin("/scheduling/sessions", "nav.sessions", ListChecks, "scheduling"),
	admin("/scheduling/subscriptions", "nav.subscriptions", Repeat, "scheduling"),
	admin("/people/students", "nav.students", GraduationCap, "people"),
	admin("/people/parents", "nav.parents", Users, "people"),
```

Create `dashboard/src/routes/_authed/scheduling.sessions.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SessionsList } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/scheduling/sessions/")({
	component: function SessionsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.sessions"));
		return (
			<>
				<PageHeader title={t("nav.sessions")} />
				<SessionsList />
			</>
		);
	},
});
```

Merge these keys into `dashboard/src/locales/en/common.json` and `dashboard/src/locales/ar/common.json` (a nested object merges into the existing one of the same name; a key that already exists takes the new value). Keep the files' tab indentation.

English:

```json
{
  "nav": {
    "sessions": "Sessions"
  },
  "errors": {
    "scheduling": {
      "not_allowed_in_status": "That isn't possible in the current status."
    }
  },
  "scheduling": {
    "list": {
      "period": "Period",
      "periods": {
        "today": "Today",
        "week": "This week",
        "upcoming": "Upcoming",
        "past": "Past",
        "all": "Any time"
      },
      "from": "From",
      "to": "To",
      "anyStatus": "Any status",
      "studentAttendance": "Student attendance",
      "anyAttendance": "Any attendance",
      "empty": "No sessions match.",
      "selectPage": "Select every session on this page",
      "select": "Select {{name}}'s session on {{date}}",
      "attendanceCell": "Student: {{student}} · Teacher: {{teacher}}",
      "columns": {
        "date": "Date",
        "time": "Time",
        "student": "Student",
        "teacher": "Teacher",
        "course": "Course",
        "status": "Status",
        "attendance": "Attendance"
      }
    },
    "bulk": {
      "label": "Bulk actions",
      "present": "Mark present",
      "absent": "Mark absent",
      "cancel": "Cancel sessions",
      "result": "Done: {{done}}. Skipped: {{skipped}}.",
      "skippedRow": "Session {{id}}: {{reason}}",
      "selected": "{{count}} selected",
      "cancelBody": "Cancel the selected sessions ({{count}}). Sessions that can't be cancelled are skipped."
    }
  }
}
```

Arabic:

```json
{
  "nav": {
    "sessions": "الحصص"
  },
  "errors": {
    "scheduling": {
      "not_allowed_in_status": "هذا غير ممكن في الحالة الحالية."
    }
  },
  "scheduling": {
    "list": {
      "period": "الفترة",
      "periods": {
        "today": "اليوم",
        "week": "هذا الأسبوع",
        "upcoming": "القادمة",
        "past": "السابقة",
        "all": "أي وقت"
      },
      "from": "من",
      "to": "إلى",
      "anyStatus": "أي حالة",
      "studentAttendance": "حضور الطالب",
      "anyAttendance": "أي حضور",
      "empty": "لا توجد حصص مطابقة.",
      "selectPage": "تحديد كل حصص هذه الصفحة",
      "select": "تحديد حصة {{name}} في {{date}}",
      "attendanceCell": "الطالب: {{student}} · المعلم: {{teacher}}",
      "columns": {
        "date": "التاريخ",
        "time": "الوقت",
        "student": "الطالب",
        "teacher": "المعلم",
        "course": "المقرر",
        "status": "الحالة",
        "attendance": "الحضور"
      }
    },
    "bulk": {
      "label": "إجراءات جماعية",
      "present": "تسجيل حضور",
      "absent": "تسجيل غياب",
      "cancel": "إلغاء الحصص",
      "result": "تم: {{done}}. تُخطّي: {{skipped}}.",
      "skippedRow": "الحصة {{id}}: {{reason}}",
      "selected": "{{count}} محددة",
      "cancelBody": "إلغاء الحصص المحددة ({{count}}). تُتخطّى الحصص التي لا يمكن إلغاؤها."
    }
  }
}
```

- [ ] **Step 4: Format and regenerate routes**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src && npx pnpm@10 exec vite build`
(the build regenerates `src/routeTree.gen.ts`).

- [ ] **Step 5: Run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features`
Expected: PASS.

- [ ] **Step 6: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass; coverage lines/statements ≥ 80, branches/functions ≥ 70; `check-colors` prints no findings.

- [ ] **Step 7: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): sessions list with filters, CSV and bulk actions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Dashboard: teacher pages, report dialog and Missing reports

**Files:**
- Create: `dashboard/src/features/scheduling/MissingReports.tsx`, `dashboard/src/features/scheduling/ReportDialog.tsx`, `dashboard/src/features/scheduling/TeacherSessionTable.tsx`, `dashboard/src/features/scheduling/TeacherSessions.tsx`, `dashboard/src/routes/_authed/scheduling.reports.tsx`, `dashboard/src/routes/_authed/teaching.index.tsx`, `dashboard/src/routes/_authed/teaching.reports.tsx`, `dashboard/src/routes/_authed/teaching.sessions.tsx`, `dashboard/src/routes/_authed/teaching.tsx`
- Modify: `dashboard/src/features/scheduling/bits.tsx`, `dashboard/src/features/scheduling/index.ts`, `dashboard/src/features/shell/nav.ts`, `dashboard/src/routes/_authed/index.tsx`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`, `dashboard/src/routeTree.gen.ts` (generated)
- Test: `dashboard/src/features/scheduling/MissingReports.test.tsx` (new), `dashboard/src/features/scheduling/ReportDialog.test.tsx` (new), `dashboard/src/features/scheduling/TeacherSessions.test.tsx` (new), `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/routes/_authed/index.test.tsx`

**Interfaces:**
- Consumes: Task 9's `requireRole`, `useSessionList(params, { refetchInterval })`, `useMissingReports`, `dayIn`; Task 10's `AttendanceControls`, `ReportForm`, `JoinLink`, `SessionStatusChip`.
- Produces: `bits.useViewerZone() -> string | undefined` (the viewer's `me.timezone`, D12); `ReportDialog({ session })` (button named `Write the report for {name}` / `Edit the report for {name}`); `TeacherSessionTable({ when })`; exported `TeacherSessions()`, `TeacherHome()`, `MissingReports({ asAdmin: boolean })`.
- Produces: routes `/scheduling/reports` (admin), `/teaching` (teacher guard) with `/teaching/sessions`, `/teaching/reports` and `/teaching/` → sessions; nav `nav.missingReports` (Scheduling) and the `teaching` group; Home shows `TeacherHome` to teachers.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/scheduling/MissingReports.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { identityApi } from "@/features/identity/api";
import { renderWithRouter } from "@/test/render";
import { academySettings, page, sessionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { MissingReports } from "./MissingReports";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, missingReports: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({
	academyApi: { get: vi.fn(), update: vi.fn() },
}));
vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { ...actual.identityApi, me: vi.fn() } };
});

const ROW = sessionRow({ status: "completed", student_attendance: "present" });

describe("MissingReports", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(identityApi.me).mockResolvedValue({
			id: 21,
			email: "bilal@demo.test",
			full_name: "Bilal",
			role: "teacher",
			profiles: ["teacher"],
			timezone: "Asia/Riyadh",
		});
		vi.mocked(schedulingApi.missingReports).mockResolvedValue(page([ROW]));
	});

	it("links an admin to each session, in the academy's time", async () => {
		renderWithRouter(<MissingReports asAdmin />);
		const item = await screen.findByRole("listitem");
		expect(within(item).getByRole("link", { name: "Yusuf" })).toHaveAttribute(
			"href",
			"/scheduling/sessions/41",
		);
		expect(
			within(item).getByText("Jun 1, 2026 18:00 · Tajweed · Bilal"),
		).toBeInTheDocument();
		expect(within(item).queryByRole("button")).toBeNull();
		expect(schedulingApi.missingReports).toHaveBeenCalledWith({ page: 1 });
	});

	it("gives a teacher Write report, on their own clock", async () => {
		renderWithRouter(<MissingReports asAdmin={false} />);
		const item = await screen.findByRole("listitem");
		expect(
			within(item).getByText("Jun 1, 2026 21:00 · Tajweed · Bilal"),
		).toBeInTheDocument();
		expect(
			within(item).getByRole("button", { name: "Write the report for Yusuf" }),
		).toBeInTheDocument();
		expect(within(item).queryByRole("link")).toBeNull();
	});

	it("says when none are missing, and when loading failed", async () => {
		vi.mocked(schedulingApi.missingReports).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<MissingReports asAdmin />);
		expect(
			await screen.findByText("Every completed session has its report."),
		).toBeInTheDocument();
		unmount();
		vi.mocked(schedulingApi.missingReports).mockRejectedValueOnce(
			new Error("x"),
		);
		renderWithRouter(<MissingReports asAdmin />);
		expect(
			await screen.findByText("Couldn't load the missing reports."),
		).toBeInTheDocument();
	});
});
```

Create `dashboard/src/features/scheduling/ReportDialog.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { reportRow, sessionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { ReportDialog } from "./ReportDialog";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			report: vi.fn(),
			saveReport: vi.fn(),
		},
	};
});

const completed = sessionRow({
	status: "completed",
	student_attendance: "present",
});

describe("ReportDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(schedulingApi.saveReport).mockResolvedValue(reportRow());
		vi.mocked(schedulingApi.report).mockResolvedValue(reportRow());
	});

	it("writes a new report and closes", async () => {
		const user = userEvent.setup();
		renderWithRouter(<ReportDialog session={completed} />);
		await user.click(
			await screen.findByRole("button", {
				name: "Write the report for Yusuf",
			}),
		);
		const dialog = screen.getByRole("dialog");
		expect(within(dialog).getByLabelText(/^Behaviour/)).toHaveValue("");
		await user.selectOptions(within(dialog).getByLabelText(/^Behaviour/), "4");
		await user.selectOptions(
			within(dialog).getByLabelText(/^Participation/),
			"3",
		);
		await user.click(
			within(dialog).getByRole("button", { name: "Save report" }),
		);
		await waitFor(() =>
			expect(schedulingApi.saveReport).toHaveBeenCalledWith({
				id: 41,
				behaviour: 4,
				participation: 3,
				notes: "",
			}),
		);
		await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
		expect(schedulingApi.report).not.toHaveBeenCalled();
	});

	it("opens a written report to edit it", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<ReportDialog session={{ ...completed, has_report: true }} />,
		);
		await user.click(
			await screen.findByRole("button", { name: "Edit the report for Yusuf" }),
		);
		const dialog = screen.getByRole("dialog");
		expect(await within(dialog).findByLabelText(/^Behaviour/)).toHaveValue("5");
		expect(within(dialog).getByLabelText("Notes")).toHaveValue(
			"Recited clearly.",
		);
		expect(schedulingApi.report).toHaveBeenCalledWith(41);
	});

	it("says when the report couldn't be loaded", async () => {
		vi.mocked(schedulingApi.report).mockRejectedValue(new Error("x"));
		const user = userEvent.setup();
		renderWithRouter(
			<ReportDialog session={{ ...completed, has_report: true }} />,
		);
		await user.click(
			await screen.findByRole("button", { name: "Edit the report for Yusuf" }),
		);
		expect(
			await screen.findByText("Couldn't load the report."),
		).toBeInTheDocument();
	});
});
```

Create `dashboard/src/features/scheduling/TeacherSessions.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "@/features/identity/api";
import { renderWithRouter } from "@/test/render";
import { page, sessionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { TeacherHome, TeacherSessions } from "./TeacherSessions";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, sessionList: vi.fn() },
	};
});
vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { ...actual.identityApi, me: vi.fn() } };
});

function lastParams() {
	return vi.mocked(schedulingApi.sessionList).mock.calls.at(-1)?.[0];
}

describe("TeacherSessions", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(identityApi.me).mockResolvedValue({
			id: 21,
			email: "bilal@demo.test",
			full_name: "Bilal",
			role: "teacher",
			profiles: ["teacher"],
			timezone: "Asia/Riyadh",
		});
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(
			page([
				sessionRow({ has_started: false }),
				sessionRow({
					id: 42,
					status: "completed",
					student_attendance: "present",
					student: { id: 12, full_name: "Aisha", timezone: "UTC" },
				}),
			]),
		);
	});

	it("shows today's sessions on the teacher's own clock", async () => {
		renderWithRouter(<TeacherSessions />);
		const table = await screen.findByRole("table");
		const [, yusuf, aisha] = within(table).getAllByRole("row");
		// 18:00 UTC is 21:00 in Riyadh, the teacher's zone.
		expect(within(yusuf).getByText("21:00")).toBeInTheDocument();
		expect(within(yusuf).getByText("Jun 1, 2026")).toBeInTheDocument();
		expect(
			within(yusuf).getByRole("link", { name: "Join the session with Yusuf" }),
		).toBeInTheDocument();
		expect(
			within(yusuf).getByRole("combobox", {
				name: "Student attendance for Yusuf",
			}),
		).toBeDisabled();
		// Only a completed session offers its report.
		expect(within(yusuf).queryByRole("button", { name: /report/ })).toBeNull();
		expect(
			within(aisha).getByRole("button", { name: "Write the report for Aisha" }),
		).toBeInTheDocument();
		expect(lastParams()).toEqual({ when: "today", page: 1 });
	});

	it("moves between Today, This week and History", async () => {
		const user = userEvent.setup();
		renderWithRouter(<TeacherSessions />);
		await screen.findByRole("table");
		await user.click(screen.getByRole("tab", { name: "This week" }));
		await waitFor(() =>
			expect(lastParams()).toEqual({ when: "week", page: 1 }),
		);
		await user.click(screen.getByRole("tab", { name: "History" }));
		await waitFor(() =>
			expect(lastParams()).toEqual({ when: "past", page: 1 }),
		);
	});

	it("says when there are none, and when loading failed", async () => {
		vi.mocked(schedulingApi.sessionList).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<TeacherSessions />);
		expect(await screen.findByText("No sessions here.")).toBeInTheDocument();
		unmount();
		vi.mocked(schedulingApi.sessionList).mockRejectedValueOnce(new Error("x"));
		renderWithRouter(<TeacherSessions />);
		expect(
			await screen.findByText("Couldn't load the sessions."),
		).toBeInTheDocument();
	});

	it("puts today's sessions on the teacher's home", async () => {
		renderWithRouter(<TeacherHome />);
		expect(
			await screen.findByRole("heading", { name: "Today's sessions" }),
		).toBeInTheDocument();
		expect(await screen.findByRole("table")).toBeInTheDocument();
		expect(lastParams()).toEqual({ when: "today", page: 1 });
	});
});
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
			"/",
			"/scheduling/today",
			"/scheduling/sessions",
			"/scheduling/subscriptions",
			"/people/students",
			"/people/parents",
			"/people/teachers",
```

with:

```ts
			"/",
			"/scheduling/today",
			"/scheduling/sessions",
			"/scheduling/reports",
			"/scheduling/subscriptions",
			"/teaching/sessions",
			"/teaching/reports",
			"/people/students",
			"/people/parents",
			"/people/teachers",
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
		]);
	});

	it("gates every grouped item to admins", () => {
		for (const item of NAV_ITEMS.filter((i) => i.group)) {
			expect(item.requiresRole).toBe("admin");
		}
	});

	it("shows only home and account to non-admins", () => {
		for (const role of ["teacher", "student", "parent"] as const) {
			expect(visibleNavItems(NAV_ITEMS, [], role).map((i) => i.to)).toEqual([
				"/",
				"/account",
```

with:

```ts
		]);
	});

	it("gates every grouped item to one role", () => {
		for (const item of NAV_ITEMS.filter((i) => i.group)) {
			expect(item.requiresRole).toBe(
				item.group === "teaching" ? "teacher" : "admin",
			);
		}
	});

	it("shows a teacher their sessions and the reports they owe", () => {
		expect(visibleNavItems(NAV_ITEMS, [], "teacher").map((i) => i.to)).toEqual([
			"/",
			"/teaching/sessions",
			"/teaching/reports",
			"/account",
		]);
	});

	it("shows only home and account to students and parents", () => {
		for (const role of ["student", "parent"] as const) {
			expect(visibleNavItems(NAV_ITEMS, [], role).map((i) => i.to)).toEqual([
				"/",
				"/account",
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
			"settings",
			undefined,
		]);
		expect(groups[1]?.items).toHaveLength(3);
		expect(groups[2]?.items).toHaveLength(4);
	});
});
```

with:

```ts
			"settings",
			undefined,
		]);
		expect(groups[1]?.items).toHaveLength(4);
		expect(groups[2]?.items).toHaveLength(4);
	});
});
```

In `dashboard/src/routes/_authed/index.test.tsx`, replace:

```tsx
	RouterProvider,
} from "@tanstack/react-router";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import type { Me } from "@/features/identity/schemas";
import { ThemeProvider } from "@/lib/theme";
import { Home } from "./index";

function renderHome(me: Me) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
```

with:

```tsx
	RouterProvider,
} from "@tanstack/react-router";
import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "@/features/identity/api";
import type { Me } from "@/features/identity/schemas";
import { schedulingApi } from "@/features/scheduling/api";
import { ThemeProvider } from "@/lib/theme";
import { page, sessionRow } from "@/test/scheduling-fixtures";
import { Home } from "./index";

vi.mock("@/features/scheduling/api", async (orig) => {
	const actual = await orig<typeof import("@/features/scheduling/api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, sessionList: vi.fn() },
	};
});
vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { ...actual.identityApi, me: vi.fn() } };
});

function renderHome(me: Me) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
```

In `dashboard/src/routes/_authed/index.test.tsx`, replace:

```tsx
	profiles: ["student"],
};

describe("Home", () => {
	it("greets the user", async () => {
		renderHome(student);
		expect(await screen.findByText(/sara/i)).toBeInTheDocument();
```

with:

```tsx
	profiles: ["student"],
};

const teacher: Me = {
	id: 21,
	email: "t@b.com",
	full_name: "Bilal",
	role: "teacher",
	profiles: ["teacher"],
	timezone: "UTC",
};

describe("Home", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(
			page([sessionRow()]),
		);
	});

	it("shows a teacher today's sessions and their menu", async () => {
		vi.mocked(identityApi.me).mockResolvedValue(teacher);
		renderHome(teacher);
		expect(
			await screen.findByRole("heading", { name: "Today's sessions" }),
		).toBeInTheDocument();
		expect(await screen.findByRole("table")).toBeInTheDocument();
		expect(schedulingApi.sessionList).toHaveBeenCalledWith({
			when: "today",
			page: 1,
		});
		expect(screen.getByText("Reports to write")).toBeInTheDocument();
	});

	it("shows an admin no session panel", async () => {
		renderHome({ ...student, role: "admin", profiles: [] });
		expect(await screen.findByText("Students")).toBeInTheDocument();
		expect(schedulingApi.sessionList).not.toHaveBeenCalled();
	});

	it("greets the user", async () => {
		renderHome(student);
		expect(await screen.findByText(/sara/i)).toBeInTheDocument();
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling/ReportDialog.test.tsx src/features/scheduling/TeacherSessions.test.tsx src/features/scheduling/MissingReports.test.tsx src/features/shell/nav.test.ts src/routes/_authed/index.test.tsx`
Expected: FAIL — `Failed to resolve import "./ReportDialog"` (and the other new modules), the nav lacks the teacher items, and Home shows no "Today's sessions".

- [ ] **Step 3: Implement**

Create `dashboard/src/features/scheduling/MissingReports.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { FileCheck } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { useAcademySettings } from "@/features/academy/queries";
import { dayIn, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	EmptyState,
	Spinner,
} from "@/ui";
import { useLocalName, useViewerZone } from "./bits";
import { useMissingReports } from "./queries";
import { ReportDialog } from "./ReportDialog";

const PAGE_SIZE = 25;

/** Completed sessions still without a report a day after they ended
 * (spec §4.5). An admin sees every one, in the academy's time, each linking
 * to its session page; a teacher sees their own, on their clock, with
 * "Write report". */
export function MissingReports({ asAdmin }: { asAdmin: boolean }) {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	const { data: academy } = useAcademySettings();
	const viewerZone = useViewerZone();
	const zone = asAdmin ? academy?.timezone : viewerZone;
	const [page, setPage] = useState(1);
	const { data, isPending, isError } = useMissingReports({ page });
	const rows = data?.results ?? [];
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));

	if (isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("scheduling.missing.loadError")}</AlertDescription>
			</Alert>
		);
	}
	if (isPending || !zone) return <Spinner />;
	if (rows.length === 0) {
		return (
			<Card>
				<CardContent>
					<EmptyState icon={FileCheck} title={t("scheduling.missing.empty")} />
				</CardContent>
			</Card>
		);
	}
	return (
		<div className="flex flex-col gap-4">
			<ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
				{rows.map((session) => {
					const instant = new Date(session.starts_at);
					const when = `${dayIn(instant, zone, i18n.language)} ${wallTime(
						instant,
						zone,
						i18n.language,
					)}`;
					return (
						<li
							key={session.id}
							className="flex flex-wrap items-center justify-between gap-2 p-3"
						>
							<div className="flex flex-col">
								{asAdmin ? (
									<Link
										to="/scheduling/sessions/$sessionId"
										params={{ sessionId: String(session.id) }}
										className="font-medium text-primary-text underline-offset-4 hover:underline"
									>
										{session.student.full_name}
									</Link>
								) : (
									<span className="font-medium">
										{session.student.full_name}
									</span>
								)}
								<span className="text-sm text-muted-foreground">
									{t("scheduling.missing.row", {
										when,
										course: localName(session.course),
										teacher: session.teacher.full_name,
									})}
								</span>
							</div>
							{asAdmin ? null : <ReportDialog session={session} />}
						</li>
					);
				})}
			</ul>
			<Pager page={page} pages={pages} onChange={setPage} />
		</div>
	);
}
```

Create `dashboard/src/features/scheduling/ReportDialog.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogContent,
	DialogDescription,
	DialogTitle,
	DialogTrigger,
	Spinner,
} from "@/ui";
import { useReport } from "./queries";
import { ReportForm } from "./ReportForm";
import type { Session } from "./schemas";

/** "Write report" / "Edit report" on a teacher's completed session. */
export function ReportDialog({ session }: { session: Session }) {
	const { t } = useTranslation();
	const [open, setOpen] = useState(false);
	const written = Boolean(session.has_report);
	const { data: report, isError } = useReport(session.id, open && written);
	const name = session.student.full_name;
	let body = (
		<ReportForm sessionId={session.id} onSaved={() => setOpen(false)} />
	);
	if (written && isError) {
		body = (
			<Alert variant="destructive">
				<AlertDescription>{t("scheduling.report.loadError")}</AlertDescription>
			</Alert>
		);
	} else if (written && !report) {
		body = <Spinner />;
	} else if (report) {
		body = (
			<ReportForm
				sessionId={session.id}
				report={report}
				onSaved={() => setOpen(false)}
			/>
		);
	}
	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button
					size="sm"
					variant={written ? "outline" : "primary"}
					aria-label={t(
						written
							? "scheduling.report.editFor"
							: "scheduling.report.writeFor",
						{ name },
					)}
				>
					{t(written ? "scheduling.report.edit" : "scheduling.report.write")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("scheduling.report.title")}</DialogTitle>
				<DialogDescription>
					{t("scheduling.report.dialogBody", { name })}
				</DialogDescription>
				<div className="mt-4">{body}</div>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/scheduling/TeacherSessionTable.tsx`:

```tsx
import { CalendarClock } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import type { QueryParams } from "@/lib/api";
import { dayIn, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	EmptyState,
	Spinner,
} from "@/ui";
import { AttendanceControls } from "./AttendanceControls";
import {
	JoinLink,
	SessionStatusChip,
	useLocalName,
	useViewerZone,
} from "./bits";
import { useSessionList } from "./queries";
import { ReportDialog } from "./ReportDialog";

const PAGE_SIZE = 25;
const MINUTE = 60_000;

/** A teacher's sessions (spec §6): time on their own clock, Join, both
 * attendances (open from the start time) and the report. The list re-reads
 * every minute so the controls open soon after a session starts. */
export function TeacherSessionTable({ when }: { when: string }) {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	const zone = useViewerZone();
	const [page, setPage] = useState(1);
	const params: QueryParams = { when, page };
	const { data, isPending, isError } = useSessionList(params, {
		refetchInterval: MINUTE,
	});
	const rows = data?.results ?? [];
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));

	if (isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>
					{t("scheduling.sessions.loadError")}
				</AlertDescription>
			</Alert>
		);
	}
	if (isPending || !zone) return <Spinner />;
	if (rows.length === 0) {
		return (
			<Card>
				<CardContent>
					<EmptyState icon={CalendarClock} title={t("scheduling.mine.empty")} />
				</CardContent>
			</Card>
		);
	}
	return (
		<div className="flex flex-col gap-4">
			<div className="overflow-x-auto rounded-lg border border-border">
				<table className="w-full text-sm">
					<thead className="bg-secondary text-muted-foreground">
						<tr>
							{(
								[
									"when",
									"student",
									"course",
									"status",
									"join",
									"attendance",
									"report",
								] as const
							).map((key) => (
								<th
									key={key}
									scope="col"
									className="p-3 text-start font-medium"
								>
									{t(`scheduling.mine.columns.${key}`)}
								</th>
							))}
						</tr>
					</thead>
					<tbody>
						{rows.map((session) => {
							const instant = new Date(session.starts_at);
							return (
								<tr key={session.id} className="border-t border-border">
									<td className="p-3">
										<span className="block">
											{dayIn(instant, zone, i18n.language)}
										</span>
										<span dir="ltr" className="font-medium">
											{wallTime(instant, zone, i18n.language)}
										</span>
									</td>
									<td className="p-3">{session.student.full_name}</td>
									<td className="p-3">{localName(session.course)}</td>
									<td className="p-3">
										<SessionStatusChip status={session.status} />
									</td>
									<td className="p-3">
										<JoinLink session={session} />
									</td>
									<td className="p-3">
										<AttendanceControls session={session} canClear={false} />
									</td>
									<td className="p-3">
										{session.status === "completed" ? (
											<ReportDialog session={session} />
										) : null}
									</td>
								</tr>
							);
						})}
					</tbody>
				</table>
			</div>
			<Pager page={page} pages={pages} onChange={setPage} />
		</div>
	);
}
```

Create `dashboard/src/features/scheduling/TeacherSessions.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { TeacherSessionTable } from "./TeacherSessionTable";

const TABS = ["today", "week", "past"] as const;

/** Spec §6 My sessions (teacher): Today, This week and History. */
export function TeacherSessions() {
	const { t } = useTranslation();
	const [tab, setTab] = useState<(typeof TABS)[number]>("today");
	return (
		<div className="flex flex-col gap-4">
			<div
				role="tablist"
				aria-label={t("scheduling.mine.tabs.label")}
				className="flex flex-wrap gap-2 border-b border-border pb-2"
			>
				{TABS.map((key) => (
					<button
						key={key}
						type="button"
						role="tab"
						aria-selected={tab === key}
						onClick={() => setTab(key)}
						className="rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-secondary aria-selected:bg-secondary aria-selected:text-foreground"
					>
						{t(`scheduling.mine.tabs.${key}`)}
					</button>
				))}
			</div>
			{/* Keyed, so a new tab starts again on page 1. */}
			<TeacherSessionTable key={tab} when={tab} />
		</div>
	);
}

/** The teacher's home: today's sessions (spec §6). */
export function TeacherHome() {
	const { t } = useTranslation();
	return (
		<section aria-labelledby="teacher-today" className="flex flex-col gap-3">
			<h2 id="teacher-today" className="text-lg font-semibold">
				{t("scheduling.mine.today")}
			</h2>
			<TeacherSessionTable when="today" />
		</section>
	);
}
```

In `dashboard/src/features/scheduling/bits.tsx`, replace:

```tsx
import { useTranslation } from "react-i18next";
import { Meter, StatusChip } from "@/ui";
import type {
	NamedRef,
```

with:

```tsx
import { useTranslation } from "react-i18next";
import { useMe } from "@/features/identity/queries";
import { Meter, StatusChip } from "@/ui";
import type {
	NamedRef,
```

Append to the end of `dashboard/src/features/scheduling/bits.tsx`:

```tsx
/** The signed-in person's own time zone (`me/`): non-admin screens show every
 * time on their clock (P5-8). Undefined until `me/` has loaded. */
export function useViewerZone(): string | undefined {
	const { data: me } = useMe();
	return me ? (me.timezone ?? "UTC") : undefined;
}
```

In `dashboard/src/features/scheduling/index.ts`, replace:

```ts
export { schedulingApi, sessionsCsvUrl, subscriptionsCsvUrl } from "./api";
export * from "./queries";
export { SessionPage } from "./SessionPage";
export { SessionsList } from "./SessionsList";
```

with:

```ts
export { schedulingApi, sessionsCsvUrl, subscriptionsCsvUrl } from "./api";
export { MissingReports } from "./MissingReports";
export * from "./queries";
export { SessionPage } from "./SessionPage";
export { SessionsList } from "./SessionsList";
```

In `dashboard/src/features/scheduling/index.ts`, replace:

```ts
export { SubscriptionForm } from "./SubscriptionForm";
export { SubscriptionsList } from "./SubscriptionsList";
export * from "./schemas";
export { TodayBoard } from "./TodayBoard";
```

with:

```ts
export { SubscriptionForm } from "./SubscriptionForm";
export { SubscriptionsList } from "./SubscriptionsList";
export * from "./schemas";
export { TeacherHome, TeacherSessions } from "./TeacherSessions";
export { TodayBoard } from "./TodayBoard";
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
import {
	BookOpen,
	CalendarClock,
	Globe,
	GraduationCap,
	Home,
	ListChecks,
	Package,
	Presentation,
	Repeat,
```

with:

```ts
import {
	BookOpen,
	CalendarClock,
	FileClock,
	Globe,
	GraduationCap,
	Home,
	ListChecks,
	NotebookPen,
	Package,
	Presentation,
	Repeat,
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
} from "lucide-react";
import type { ProfileType, Role } from "@/features/identity/schemas";

export type NavGroup = "scheduling" | "people" | "catalogue" | "settings";

export type NavItem = {
	to: string;
```

with:

```ts
} from "lucide-react";
import type { ProfileType, Role } from "@/features/identity/schemas";

export type NavGroup =
	| "scheduling"
	| "teaching"
	| "people"
	| "catalogue"
	| "settings";

export type NavItem = {
	to: string;
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	{ to: "/", labelKey: "auth.home", icon: Home },
	admin("/scheduling/today", "nav.today", CalendarClock, "scheduling"),
	admin("/scheduling/sessions", "nav.sessions", ListChecks, "scheduling"),
	admin("/scheduling/subscriptions", "nav.subscriptions", Repeat, "scheduling"),
	admin("/people/students", "nav.students", GraduationCap, "people"),
	admin("/people/parents", "nav.parents", Users, "people"),
	admin("/people/teachers", "nav.teachers", Presentation, "people"),
```

with:

```ts
	{ to: "/", labelKey: "auth.home", icon: Home },
	admin("/scheduling/today", "nav.today", CalendarClock, "scheduling"),
	admin("/scheduling/sessions", "nav.sessions", ListChecks, "scheduling"),
	admin("/scheduling/reports", "nav.missingReports", FileClock, "scheduling"),
	admin("/scheduling/subscriptions", "nav.subscriptions", Repeat, "scheduling"),
	// Plan 5: a teacher's own sessions and the reports they still owe.
	{
		to: "/teaching/sessions",
		labelKey: "nav.mySessions",
		icon: CalendarClock,
		group: "teaching",
		requiresRole: "teacher",
	},
	{
		to: "/teaching/reports",
		labelKey: "nav.reportsToWrite",
		icon: NotebookPen,
		group: "teaching",
		requiresRole: "teacher",
	},
	admin("/people/students", "nav.students", GraduationCap, "people"),
	admin("/people/parents", "nav.parents", Users, "people"),
	admin("/people/teachers", "nav.teachers", Presentation, "people"),
```

In `dashboard/src/routes/_authed/index.tsx`, replace:

```tsx
import { usePageTitle } from "@/features/branding";
import { useMe } from "@/features/identity/queries";
import type { Me } from "@/features/identity/schemas";
import { NAV_ITEMS, visibleNavItems } from "@/features/shell/nav";
import { BentoTile, PageContainer, PageHeader } from "@/ui";

```

with:

```tsx
import { usePageTitle } from "@/features/branding";
import { useMe } from "@/features/identity/queries";
import type { Me } from "@/features/identity/schemas";
import { TeacherHome } from "@/features/scheduling";
import { NAV_ITEMS, visibleNavItems } from "@/features/shell/nav";
import { BentoTile, PageContainer, PageHeader } from "@/ui";

```

In `dashboard/src/routes/_authed/index.tsx`, replace:

```tsx
	return (
		<PageContainer>
			<PageHeader title={t("auth.greeting", { name: me.full_name })} />
			<div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
				{tiles.map((item) => (
					<BentoTile
```

with:

```tsx
	return (
		<PageContainer>
			<PageHeader title={t("auth.greeting", { name: me.full_name })} />
			{me.role === "teacher" ? <TeacherHome /> : null}
			<div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
				{tiles.map((item) => (
					<BentoTile
```

Create `dashboard/src/routes/_authed/scheduling.reports.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { MissingReports } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/scheduling/reports")({
	component: function MissingReportsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.missingReports"));
		return (
			<>
				<PageHeader
					title={t("nav.missingReports")}
					description={t("scheduling.missing.subtitle")}
				/>
				<MissingReports asAdmin />
			</>
		);
	},
});
```

Create `dashboard/src/routes/_authed/teaching.index.tsx`:

```tsx
import { createFileRoute, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/_authed/teaching/")({
	beforeLoad: () => {
		throw redirect({ to: "/teaching/sessions" });
	},
});
```

Create `dashboard/src/routes/_authed/teaching.reports.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { MissingReports } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/teaching/reports")({
	component: function ReportsToWriteRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.reportsToWrite"));
		return (
			<>
				<PageHeader
					title={t("nav.reportsToWrite")}
					description={t("scheduling.missing.subtitle")}
				/>
				<MissingReports asAdmin={false} />
			</>
		);
	},
});
```

Create `dashboard/src/routes/_authed/teaching.sessions.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { TeacherSessions } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/teaching/sessions")({
	component: function TeachingSessionsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.mySessions"));
		return (
			<>
				<PageHeader title={t("nav.mySessions")} />
				<TeacherSessions />
			</>
		);
	},
});
```

Create `dashboard/src/routes/_authed/teaching.tsx`:

```tsx
import { createFileRoute, Outlet } from "@tanstack/react-router";
import { requireRole } from "@/features/identity/require-admin";
import { PageContainer } from "@/ui";

export const Route = createFileRoute("/_authed/teaching")({
	beforeLoad: ({ context }) => requireRole(context, ["teacher"]),
	component: () => (
		<PageContainer>
			<Outlet />
		</PageContainer>
	),
});
```

Merge these keys into `dashboard/src/locales/en/common.json` and `dashboard/src/locales/ar/common.json` (a nested object merges into the existing one of the same name; a key that already exists takes the new value). Keep the files' tab indentation.

English:

```json
{
  "nav": {
    "missingReports": "Missing reports",
    "mySessions": "My sessions",
    "reportsToWrite": "Reports to write",
    "group": {
      "teaching": "Teaching"
    }
  },
  "scheduling": {
    "report": {
      "write": "Write report",
      "edit": "Edit report",
      "writeFor": "Write the report for {{name}}",
      "editFor": "Edit the report for {{name}}",
      "dialogBody": "How the session with {{name}} went. Only staff see reports."
    },
    "mine": {
      "today": "Today's sessions",
      "empty": "No sessions here.",
      "tabs": {
        "label": "Which sessions",
        "today": "Today",
        "week": "This week",
        "past": "History"
      },
      "columns": {
        "when": "When",
        "student": "Student",
        "course": "Course",
        "status": "Status",
        "join": "Link",
        "attendance": "Attendance",
        "report": "Report"
      }
    },
    "missing": {
      "subtitle": "Completed sessions that ended more than a day ago without a report.",
      "empty": "Every completed session has its report.",
      "loadError": "Couldn't load the missing reports.",
      "row": "{{when}} · {{course}} · {{teacher}}"
    }
  }
}
```

Arabic:

```json
{
  "nav": {
    "missingReports": "تقارير ناقصة",
    "mySessions": "حصصي",
    "reportsToWrite": "تقارير مطلوبة",
    "group": {
      "teaching": "التدريس"
    }
  },
  "scheduling": {
    "report": {
      "write": "كتابة التقرير",
      "edit": "تعديل التقرير",
      "writeFor": "كتابة تقرير حصة {{name}}",
      "editFor": "تعديل تقرير حصة {{name}}",
      "dialogBody": "كيف كانت الحصة مع {{name}}. التقارير للطاقم فقط."
    },
    "mine": {
      "today": "حصص اليوم",
      "empty": "لا توجد حصص هنا.",
      "tabs": {
        "label": "أي الحصص",
        "today": "اليوم",
        "week": "هذا الأسبوع",
        "past": "السجل"
      },
      "columns": {
        "when": "الموعد",
        "student": "الطالب",
        "course": "المقرر",
        "status": "الحالة",
        "join": "الرابط",
        "attendance": "الحضور",
        "report": "التقرير"
      }
    },
    "missing": {
      "subtitle": "حصص مكتملة انتهت منذ أكثر من يوم بلا تقرير.",
      "empty": "كل الحصص المكتملة لها تقارير.",
      "loadError": "تعذّر تحميل التقارير الناقصة.",
      "row": "{{when}} · {{course}} · {{teacher}}"
    }
  }
}
```

- [ ] **Step 4: Format and regenerate routes**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src && npx pnpm@10 exec vite build`
(the build regenerates `src/routeTree.gen.ts`).

- [ ] **Step 5: Run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features src/routes`
Expected: PASS.

- [ ] **Step 6: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass; coverage lines/statements ≥ 80, branches/functions ≥ 70; `check-colors` prints no findings.

- [ ] **Step 7: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): teacher sessions, reports to write and missing reports

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Dashboard: student and parent sessions, subscriptions and home

**Files:**
- Create: `dashboard/src/features/scheduling/ChildFilter.tsx`, `dashboard/src/features/scheduling/FamilyHome.tsx`, `dashboard/src/features/scheduling/FamilySessions.tsx`, `dashboard/src/features/scheduling/FamilySubscriptions.tsx`, `dashboard/src/routes/_authed/learning.index.tsx`, `dashboard/src/routes/_authed/learning.sessions.tsx`, `dashboard/src/routes/_authed/learning.subscriptions.tsx`, `dashboard/src/routes/_authed/learning.tsx`
- Modify: `dashboard/src/features/scheduling/index.ts`, `dashboard/src/features/shell/nav.ts`, `dashboard/src/routes/_authed/index.tsx`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`, `dashboard/src/routeTree.gen.ts` (generated)
- Test: `dashboard/src/features/scheduling/FamilySessions.test.tsx` (new), `dashboard/src/features/scheduling/FamilySubscriptions.test.tsx` (new), `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/routes/_authed/index.test.tsx`

**Interfaces:**
- Consumes: Task 9's hooks and `requireRole`; Task 12's `useViewerZone`; Plan 4's `useSubscriptions`, `SubscriptionProgress`, `isLive`.
- Produces: `ChildFilter({ value, onChange })` (D3); exported `FamilySessions()`, `FamilySubscriptions()`, `FamilyHome()`; `SubscriptionCard({ sub })`.
- Produces: `NavItem.requiresRole?: Role | readonly Role[]`; the `learning` group (`/learning/sessions`, `/learning/subscriptions`) for students and parents; routes `/learning` (student/parent guard) with its pages and `/learning/` → sessions; Home shows `FamilyHome` to students and parents.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/scheduling/FamilySessions.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "@/features/identity/api";
import type { Me } from "@/features/identity/schemas";
import { renderWithRouter } from "@/test/render";
import { page, sessionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { FamilySessions } from "./FamilySessions";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, sessionList: vi.fn() },
	};
});
vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { ...actual.identityApi, me: vi.fn() } };
});

const PARENT: Me = {
	id: 30,
	email: "omar@demo.test",
	full_name: "Omar",
	role: "parent",
	profiles: ["parent"],
	timezone: "Asia/Riyadh",
	children: [
		{ id: 11, full_name: "Yusuf", student_profile_id: 1 },
		{ id: 12, full_name: "Aisha", student_profile_id: 2 },
	],
};

describe("FamilySessions", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(identityApi.me).mockResolvedValue(PARENT);
		vi.mocked(schedulingApi.sessionList).mockImplementation(async (params) =>
			params.when === "upcoming"
				? page([sessionRow()])
				: page([
						sessionRow({
							id: 40,
							occurs_on: "2026-05-27",
							starts_at: "2026-05-27T18:00:00Z",
							status: "completed",
							student_attendance: "excused",
						}),
					]),
		);
	});

	it("lists upcoming sessions with Join and past ones with attendance", async () => {
		renderWithRouter(<FamilySessions />);
		const upcoming = (
			await screen.findByRole("heading", { name: "Upcoming sessions" })
		).closest("[data-slot='card']") as HTMLElement;
		const past = screen
			.getByRole("heading", { name: "Past sessions" })
			.closest("[data-slot='card']") as HTMLElement;
		// On the viewer's clock: 18:00 UTC is 21:00 in Riyadh.
		expect(await within(upcoming).findByText("21:00")).toBeInTheDocument();
		expect(
			within(upcoming).getByRole("link", {
				name: "Join the session with Yusuf",
			}),
		).toBeInTheDocument();
		expect(await within(past).findByText("Excused")).toBeInTheDocument();
		expect(within(past).queryByRole("link")).toBeNull();
		expect(schedulingApi.sessionList).toHaveBeenCalledWith({
			when: "upcoming",
			student: "",
			page: 1,
		});
	});

	it("lets a parent of several children pick one", async () => {
		const user = userEvent.setup();
		renderWithRouter(<FamilySessions />);
		await user.selectOptions(await screen.findByLabelText("Child"), "12");
		await waitFor(() =>
			expect(schedulingApi.sessionList).toHaveBeenCalledWith({
				when: "past",
				student: "12",
				page: 1,
			}),
		);
	});

	it("has no child filter for a student", async () => {
		vi.mocked(identityApi.me).mockResolvedValue({
			...PARENT,
			role: "student",
			profiles: ["student"],
			children: undefined,
		});
		renderWithRouter(<FamilySessions />);
		expect(
			await screen.findByRole("heading", { name: "Upcoming sessions" }),
		).toBeInTheDocument();
		await screen.findAllByText("21:00");
		expect(screen.queryByLabelText("Child")).toBeNull();
	});

	it("says when there are none, and when loading failed", async () => {
		vi.mocked(schedulingApi.sessionList).mockImplementation(async (params) => {
			if (params.when === "past") throw new Error("x");
			return page([]);
		});
		renderWithRouter(<FamilySessions />);
		expect(await screen.findByText("No sessions here.")).toBeInTheDocument();
		expect(
			await screen.findByText("Couldn't load the sessions."),
		).toBeInTheDocument();
	});
});
```

Create `dashboard/src/features/scheduling/FamilySubscriptions.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "@/features/identity/api";
import { renderWithRouter } from "@/test/render";
import { page, subscriptionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { FamilySubscriptions } from "./FamilySubscriptions";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, list: vi.fn() },
	};
});
vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { ...actual.identityApi, me: vi.fn() } };
});

describe("FamilySubscriptions", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(identityApi.me).mockResolvedValue({
			id: 30,
			email: "omar@demo.test",
			full_name: "Omar",
			role: "parent",
			profiles: ["parent"],
			children: [
				{ id: 11, full_name: "Yusuf", student_profile_id: 1 },
				{ id: 12, full_name: "Aisha", student_profile_id: 2 },
			],
		});
		vi.mocked(schedulingApi.list).mockResolvedValue(
			page([
				subscriptionRow(),
				subscriptionRow({
					id: 8,
					student: { id: 12, full_name: "Aisha", timezone: "UTC" },
					sessions_used: 8,
					carried_over_sessions: 2,
					sessions_remaining: -2,
					extra_sessions: 2,
					in_grace: true,
				}),
			]),
		);
	});

	it("shows used of total, extras, the end date and the grace notice", async () => {
		renderWithRouter(<FamilySubscriptions />);
		expect(await screen.findByText("3 of 8 sessions")).toBeInTheDocument();
		expect(screen.getByText("Ends on Jun 30, 2026")).toBeInTheDocument();
		expect(screen.getByText("10 of 8 sessions")).toBeInTheDocument();
		expect(screen.getByText("+2 extra")).toBeInTheDocument();
		expect(screen.getByText("In grace until Jul 7, 2026")).toBeInTheDocument();
		expect(screen.getByText("Aisha with Bilal")).toBeInTheDocument();
		expect(schedulingApi.list).toHaveBeenCalledWith({ student: "", page: 1 });
	});

	it("filters by child for a parent of several", async () => {
		const user = userEvent.setup();
		renderWithRouter(<FamilySubscriptions />);
		await user.selectOptions(await screen.findByLabelText("Child"), "11");
		await waitFor(() =>
			expect(schedulingApi.list).toHaveBeenLastCalledWith({
				student: "11",
				page: 1,
			}),
		);
	});

	it("says when there are none, and when loading failed", async () => {
		vi.mocked(schedulingApi.list).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<FamilySubscriptions />);
		expect(
			await screen.findByText("No subscriptions yet."),
		).toBeInTheDocument();
		unmount();
		vi.mocked(schedulingApi.list).mockRejectedValueOnce(new Error("x"));
		renderWithRouter(<FamilySubscriptions />);
		expect(
			await screen.findByText("Couldn't load subscriptions."),
		).toBeInTheDocument();
	});
});
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
			"/scheduling/subscriptions",
			"/teaching/sessions",
			"/teaching/reports",
			"/people/students",
			"/people/parents",
			"/people/teachers",
```

with:

```ts
			"/scheduling/subscriptions",
			"/teaching/sessions",
			"/teaching/reports",
			"/learning/sessions",
			"/learning/subscriptions",
			"/people/students",
			"/people/parents",
			"/people/teachers",
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
		]);
	});

	it("gates every grouped item to one role", () => {
		for (const item of NAV_ITEMS.filter((i) => i.group)) {
			expect(item.requiresRole).toBe(
				item.group === "teaching" ? "teacher" : "admin",
			);
		}
	});
```

with:

```ts
		]);
	});

	it("gates every grouped item by role", () => {
		const roles = { teaching: "teacher", learning: ["student", "parent"] };
		for (const item of NAV_ITEMS.filter((i) => i.group)) {
			const group = item.group as string;
			expect(item.requiresRole).toEqual(
				roles[group as keyof typeof roles] ?? "admin",
			);
		}
	});
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
		]);
	});

	it("shows only home and account to students and parents", () => {
		for (const role of ["student", "parent"] as const) {
			expect(visibleNavItems(NAV_ITEMS, [], role).map((i) => i.to)).toEqual([
				"/",
				"/account",
			]);
		}
	});

	it("groups consecutive items", () => {
		const groups = groupNavItems(visibleNavItems(NAV_ITEMS, [], "admin"));
		expect(groups.map((g) => g.group)).toEqual([
```

with:

```ts
		]);
	});

	it("shows students and parents their sessions and subscriptions", () => {
		for (const role of ["student", "parent"] as const) {
			expect(visibleNavItems(NAV_ITEMS, [], role).map((i) => i.to)).toEqual([
				"/",
				"/learning/sessions",
				"/learning/subscriptions",
				"/account",
			]);
		}
	});

	it("shows a role-gated item to nobody signed out", () => {
		expect(visibleNavItems(NAV_ITEMS, []).map((i) => i.to)).toEqual([
			"/",
			"/account",
		]);
	});

	it("groups consecutive items", () => {
		const groups = groupNavItems(visibleNavItems(NAV_ITEMS, [], "admin"));
		expect(groups.map((g) => g.group)).toEqual([
```

In `dashboard/src/routes/_authed/index.test.tsx`, replace:

```tsx
import type { Me } from "@/features/identity/schemas";
import { schedulingApi } from "@/features/scheduling/api";
import { ThemeProvider } from "@/lib/theme";
import { page, sessionRow } from "@/test/scheduling-fixtures";
import { Home } from "./index";

vi.mock("@/features/scheduling/api", async (orig) => {
	const actual = await orig<typeof import("@/features/scheduling/api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, sessionList: vi.fn() },
	};
});
vi.mock("@/features/identity/api", async (orig) => {
```

with:

```tsx
import type { Me } from "@/features/identity/schemas";
import { schedulingApi } from "@/features/scheduling/api";
import { ThemeProvider } from "@/lib/theme";
import { page, sessionRow, subscriptionRow } from "@/test/scheduling-fixtures";
import { Home } from "./index";

vi.mock("@/features/scheduling/api", async (orig) => {
	const actual = await orig<typeof import("@/features/scheduling/api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			sessionList: vi.fn(),
			list: vi.fn(),
		},
	};
});
vi.mock("@/features/identity/api", async (orig) => {
```

In `dashboard/src/routes/_authed/index.test.tsx`, replace:

```tsx
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(
			page([sessionRow()]),
		);
	});

	it("shows a teacher today's sessions and their menu", async () => {
```

with:

```tsx
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(
			page([sessionRow()]),
		);
		vi.mocked(schedulingApi.list).mockResolvedValue(
			page([subscriptionRow(), subscriptionRow({ id: 9, status: "expired" })]),
		);
	});

	it("shows a teacher today's sessions and their menu", async () => {
```

In `dashboard/src/routes/_authed/index.test.tsx`, replace:

```tsx
		expect(screen.getByText("Courses")).toBeInTheDocument();
	});

	it("shows a student only their account tile", async () => {
		renderHome(student);
		expect(await screen.findByText("Account")).toBeInTheDocument();
		expect(screen.queryByText("Students")).toBeNull();
	});

```

with:

```tsx
		expect(screen.getByText("Courses")).toBeInTheDocument();
	});

	it("shows a student their next session, progress and own menu", async () => {
		vi.mocked(identityApi.me).mockResolvedValue({
			...student,
			timezone: "Asia/Riyadh",
		});
		renderHome(student);
		expect(await screen.findByText("Next session")).toBeInTheDocument();
		expect(
			await screen.findByRole("link", { name: "Join the session with Yusuf" }),
		).toBeInTheDocument();
		// On the student's clock: 18:00 UTC is 21:00 in Riyadh.
		expect(screen.getByText("21:00")).toBeInTheDocument();
		expect(schedulingApi.sessionList).toHaveBeenCalledWith({
			when: "upcoming",
			status: "scheduled",
			page_size: 1,
		});
		// Only the live subscription's progress.
		expect(await screen.findAllByRole("progressbar")).toHaveLength(1);
		expect(screen.getByText("My subscriptions")).toBeInTheDocument();
		expect(screen.getByText("Account")).toBeInTheDocument();
		expect(screen.queryByText("Students")).toBeNull();
	});

```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling/FamilySessions.test.tsx src/features/scheduling/FamilySubscriptions.test.tsx src/features/shell/nav.test.ts src/routes/_authed/index.test.tsx`
Expected: FAIL — `Failed to resolve import "./FamilySessions"` (and `./FamilySubscriptions`), the nav shows students only Home and Account, and Home has no "Next session".

- [ ] **Step 3: Implement**

Create `dashboard/src/features/scheduling/ChildFilter.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { useMe } from "@/features/identity/queries";
import { Select } from "@/ui";

/** A parent with several children picks one (spec §6); the lists pass the
 * child's user id as `student`, which the server scopes to their children
 * anyway. Nothing for a student or a parent of one. */
export function ChildFilter({
	value,
	onChange,
}: {
	value: string;
	onChange: (student: string) => void;
}) {
	const { t } = useTranslation();
	const { data: me } = useMe();
	const children = me?.children ?? [];
	if (children.length < 2) return null;
	return (
		<Select
			aria-label={t("scheduling.family.child")}
			className="w-auto"
			value={value}
			onChange={(e) => onChange(e.target.value)}
		>
			<option value="">{t("scheduling.family.allChildren")}</option>
			{children.map((child) => (
				<option key={child.id} value={child.id}>
					{child.full_name}
				</option>
			))}
		</Select>
	);
}
```

Create `dashboard/src/features/scheduling/FamilyHome.tsx`:

```tsx
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { dayIn, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
} from "@/ui";
import { JoinLink, useLocalName, useViewerZone } from "./bits";
import { SubscriptionCard } from "./FamilySubscriptions";
import { useSessionList, useSubscriptions } from "./queries";
import { isLive } from "./schemas";

/** The student's or parent's home (spec §6): the next session with Join, on
 * their own clock, and the progress of each live subscription. */
export function FamilyHome() {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	const zone = useViewerZone();
	const next = useSessionList({
		when: "upcoming",
		status: "scheduled",
		page_size: 1,
	});
	const subs = useSubscriptions({});
	const session = next.data?.results[0];
	const live = (subs.data?.results ?? []).filter((s) => isLive(s.status));

	let nextBody: ReactNode;
	if (next.isError) {
		nextBody = (
			<Alert variant="destructive">
				<AlertDescription>
					{t("scheduling.sessions.loadError")}
				</AlertDescription>
			</Alert>
		);
	} else if (next.isPending || !zone) {
		nextBody = <Spinner />;
	} else if (!session) {
		nextBody = (
			<p className="text-sm text-muted-foreground">
				{t("scheduling.family.noNext")}
			</p>
		);
	} else {
		const instant = new Date(session.starts_at);
		nextBody = (
			<div className="flex flex-wrap items-center justify-between gap-2">
				<div className="flex flex-col">
					<span className="font-medium">
						{dayIn(instant, zone, i18n.language)}{" "}
						<span dir="ltr">{wallTime(instant, zone, i18n.language)}</span>
					</span>
					<span className="text-sm text-muted-foreground">
						{t("scheduling.family.sessionLine", {
							student: session.student.full_name,
							course: localName(session.course),
							teacher: session.teacher.full_name,
						})}
					</span>
				</div>
				<JoinLink session={session} />
			</div>
		);
	}

	return (
		<div className="flex flex-col gap-4">
			<Card>
				<CardHeader className="border-b border-border">
					<CardTitle>{t("scheduling.family.next")}</CardTitle>
				</CardHeader>
				<CardContent>{nextBody}</CardContent>
			</Card>
			{subs.isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("scheduling.loadError")}</AlertDescription>
				</Alert>
			) : (
				<div className="grid gap-4 md:grid-cols-2">
					{live.map((sub) => (
						<SubscriptionCard key={sub.id} sub={sub} />
					))}
				</div>
			)}
		</div>
	);
}
```

Create `dashboard/src/features/scheduling/FamilySessions.tsx`:

```tsx
import { type ReactNode, useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { dayIn, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
} from "@/ui";
import {
	JoinLink,
	SessionStatusChip,
	useLocalName,
	useViewerZone,
} from "./bits";
import { ChildFilter } from "./ChildFilter";
import { useSessionList } from "./queries";

const PAGE_SIZE = 25;

function SessionsCard({
	when,
	student,
}: {
	when: "upcoming" | "past";
	student: string;
}) {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	const zone = useViewerZone();
	const [page, setPage] = useState(1);
	const { data, isPending, isError } = useSessionList({ when, student, page });
	const rows = data?.results ?? [];
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	let body: ReactNode;
	if (isError) {
		body = (
			<Alert variant="destructive">
				<AlertDescription>
					{t("scheduling.sessions.loadError")}
				</AlertDescription>
			</Alert>
		);
	} else if (isPending || !zone) {
		body = <Spinner />;
	} else if (rows.length === 0) {
		body = (
			<p className="text-sm text-muted-foreground">
				{t("scheduling.sessions.none")}
			</p>
		);
	} else {
		body = (
			<ul className="flex flex-col divide-y divide-border">
				{rows.map((session) => {
					const instant = new Date(session.starts_at);
					return (
						<li
							key={session.id}
							className="flex flex-wrap items-center justify-between gap-2 py-3"
						>
							<div className="flex flex-col">
								<span className="font-medium">
									{dayIn(instant, zone, i18n.language)}{" "}
									<span dir="ltr">
										{wallTime(instant, zone, i18n.language)}
									</span>
								</span>
								<span className="text-sm text-muted-foreground">
									{t("scheduling.family.sessionLine", {
										student: session.student.full_name,
										course: localName(session.course),
										teacher: session.teacher.full_name,
									})}
								</span>
							</div>
							<div className="flex items-center gap-2">
								{when === "past" && session.status === "completed" ? (
									<span className="text-sm">
										{t(`scheduling.attendance.${session.student_attendance}`)}
									</span>
								) : (
									<SessionStatusChip status={session.status} />
								)}
								{when === "upcoming" ? <JoinLink session={session} /> : null}
							</div>
						</li>
					);
				})}
			</ul>
		);
	}
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t(`scheduling.family.${when}`)}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				{body}
				<Pager page={page} pages={pages} onChange={setPage} />
			</CardContent>
		</Card>
	);
}

/** Spec §6 My sessions (student, parent): upcoming ones with Join, and past
 * ones with the attendance, on the viewer's own clock. */
export function FamilySessions() {
	const [student, setStudent] = useState("");
	return (
		<div className="flex flex-col gap-4">
			<ChildFilter value={student} onChange={setStudent} />
			{/* Keyed, so a new child starts again on page 1. */}
			<SessionsCard key={`u${student}`} when="upcoming" student={student} />
			<SessionsCard key={`p${student}`} when="past" student={student} />
		</div>
	);
}
```

Create `dashboard/src/features/scheduling/FamilySubscriptions.tsx`:

```tsx
import { CalendarClock } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	EmptyState,
	Spinner,
} from "@/ui";
import {
	SubscriptionProgress,
	SubscriptionStatusChip,
	useLocalName,
} from "./bits";
import { ChildFilter } from "./ChildFilter";
import { useSubscriptions } from "./queries";
import type { Subscription } from "./schemas";

const PAGE_SIZE = 25;

export function SubscriptionCard({ sub }: { sub: Subscription }) {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	const day = (value: string) => formatDay(value, i18n.language);
	return (
		<Card>
			<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
				<CardTitle>{localName(sub.course)}</CardTitle>
				<SubscriptionStatusChip status={sub.status} />
			</CardHeader>
			<CardContent className="flex flex-col gap-3">
				<p className="text-sm text-muted-foreground">
					{t("scheduling.family.subscriptionLine", {
						student: sub.student.full_name,
						teacher: sub.teacher.full_name,
					})}
				</p>
				<SubscriptionProgress
					name={sub.student.full_name}
					used={sub.sessions_used}
					carried={sub.carried_over_sessions}
					total={sub.sessions_total}
					extra={sub.extra_sessions}
				/>
				<p className="text-sm">
					{sub.in_grace
						? t("scheduling.inGraceUntil", { date: day(sub.grace_ends_on) })
						: t("scheduling.family.endsOn", { date: day(sub.ends_on) })}
				</p>
			</CardContent>
		</Card>
	);
}

/** Spec §6 My subscriptions (student, parent): used of total, extras, the
 * end date and a grace notice, from the scoped `subscriptions/` list. */
export function FamilySubscriptions() {
	const { t } = useTranslation();
	const [student, setStudent] = useState("");
	const [page, setPage] = useState(1);
	const { data, isPending, isError } = useSubscriptions({ student, page });
	const rows = data?.results ?? [];
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	return (
		<div className="flex flex-col gap-4">
			<ChildFilter
				value={student}
				onChange={(next) => {
					setStudent(next);
					setPage(1);
				}}
			/>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("scheduling.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<Spinner />
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={CalendarClock} title={t("scheduling.empty")} />
					</CardContent>
				</Card>
			) : (
				<div className="grid gap-4 md:grid-cols-2">
					{rows.map((sub) => (
						<SubscriptionCard key={sub.id} sub={sub} />
					))}
				</div>
			)}
			<Pager page={page} pages={pages} onChange={setPage} />
		</div>
	);
}
```

In `dashboard/src/features/scheduling/index.ts`, replace:

```ts
export { schedulingApi, sessionsCsvUrl, subscriptionsCsvUrl } from "./api";
export { MissingReports } from "./MissingReports";
export * from "./queries";
export { SessionPage } from "./SessionPage";
```

with:

```ts
export { schedulingApi, sessionsCsvUrl, subscriptionsCsvUrl } from "./api";
export { FamilyHome } from "./FamilyHome";
export { FamilySessions } from "./FamilySessions";
export { FamilySubscriptions } from "./FamilySubscriptions";
export { MissingReports } from "./MissingReports";
export * from "./queries";
export { SessionPage } from "./SessionPage";
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
export type NavGroup =
	| "scheduling"
	| "teaching"
	| "people"
	| "catalogue"
	| "settings";
```

with:

```ts
export type NavGroup =
	| "scheduling"
	| "teaching"
	| "learning"
	| "people"
	| "catalogue"
	| "settings";
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	icon: LucideIcon;
	requires?: ProfileType;
	requiresAny?: ProfileType[];
	requiresRole?: Role;
	group?: NavGroup;
};

```

with:

```ts
	icon: LucideIcon;
	requires?: ProfileType;
	requiresAny?: ProfileType[];
	requiresRole?: Role | readonly Role[];
	group?: NavGroup;
};

```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
		group: "teaching",
		requiresRole: "teacher",
	},
	admin("/people/students", "nav.students", GraduationCap, "people"),
	admin("/people/parents", "nav.parents", Users, "people"),
	admin("/people/teachers", "nav.teachers", Presentation, "people"),
```

with:

```ts
		group: "teaching",
		requiresRole: "teacher",
	},
	// Plan 5: a student's or parent's sessions and subscriptions.
	{
		to: "/learning/sessions",
		labelKey: "nav.mySessions",
		icon: CalendarClock,
		group: "learning",
		requiresRole: ["student", "parent"],
	},
	{
		to: "/learning/subscriptions",
		labelKey: "nav.mySubscriptions",
		icon: Repeat,
		group: "learning",
		requiresRole: ["student", "parent"],
	},
	admin("/people/students", "nav.students", GraduationCap, "people"),
	admin("/people/parents", "nav.parents", Users, "people"),
	admin("/people/teachers", "nav.teachers", Presentation, "people"),
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	role?: Role,
): NavItem[] {
	return items.filter((i) => {
		if (i.requiresRole) return i.requiresRole === role;
		if (i.requires) return profiles.includes(i.requires);
		if (i.requiresAny) return i.requiresAny.some((r) => profiles.includes(r));
		return true;
```

with:

```ts
	role?: Role,
): NavItem[] {
	return items.filter((i) => {
		if (i.requiresRole) {
			const roles: readonly Role[] =
				typeof i.requiresRole === "string" ? [i.requiresRole] : i.requiresRole;
			return role !== undefined && roles.includes(role);
		}
		if (i.requires) return profiles.includes(i.requires);
		if (i.requiresAny) return i.requiresAny.some((r) => profiles.includes(r));
		return true;
```

In `dashboard/src/routes/_authed/index.tsx`, replace:

```tsx
import { usePageTitle } from "@/features/branding";
import { useMe } from "@/features/identity/queries";
import type { Me } from "@/features/identity/schemas";
import { TeacherHome } from "@/features/scheduling";
import { NAV_ITEMS, visibleNavItems } from "@/features/shell/nav";
import { BentoTile, PageContainer, PageHeader } from "@/ui";

```

with:

```tsx
import { usePageTitle } from "@/features/branding";
import { useMe } from "@/features/identity/queries";
import type { Me } from "@/features/identity/schemas";
import { FamilyHome, TeacherHome } from "@/features/scheduling";
import { NAV_ITEMS, visibleNavItems } from "@/features/shell/nav";
import { BentoTile, PageContainer, PageHeader } from "@/ui";

```

In `dashboard/src/routes/_authed/index.tsx`, replace:

```tsx
		<PageContainer>
			<PageHeader title={t("auth.greeting", { name: me.full_name })} />
			{me.role === "teacher" ? <TeacherHome /> : null}
			<div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
				{tiles.map((item) => (
					<BentoTile
```

with:

```tsx
		<PageContainer>
			<PageHeader title={t("auth.greeting", { name: me.full_name })} />
			{me.role === "teacher" ? <TeacherHome /> : null}
			{me.role === "student" || me.role === "parent" ? <FamilyHome /> : null}
			<div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
				{tiles.map((item) => (
					<BentoTile
```

Create `dashboard/src/routes/_authed/learning.index.tsx`:

```tsx
import { createFileRoute, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/_authed/learning/")({
	beforeLoad: () => {
		throw redirect({ to: "/learning/sessions" });
	},
});
```

Create `dashboard/src/routes/_authed/learning.sessions.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { FamilySessions } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/learning/sessions")({
	component: function LearningSessionsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.mySessions"));
		return (
			<>
				<PageHeader title={t("nav.mySessions")} />
				<FamilySessions />
			</>
		);
	},
});
```

Create `dashboard/src/routes/_authed/learning.subscriptions.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { FamilySubscriptions } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/learning/subscriptions")({
	component: function LearningSubscriptionsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.mySubscriptions"));
		return (
			<>
				<PageHeader title={t("nav.mySubscriptions")} />
				<FamilySubscriptions />
			</>
		);
	},
});
```

Create `dashboard/src/routes/_authed/learning.tsx`:

```tsx
import { createFileRoute, Outlet } from "@tanstack/react-router";
import { requireRole } from "@/features/identity/require-admin";
import { PageContainer } from "@/ui";

export const Route = createFileRoute("/_authed/learning")({
	beforeLoad: ({ context }) => requireRole(context, ["student", "parent"]),
	component: () => (
		<PageContainer>
			<Outlet />
		</PageContainer>
	),
});
```

Merge these keys into `dashboard/src/locales/en/common.json` and `dashboard/src/locales/ar/common.json` (a nested object merges into the existing one of the same name; a key that already exists takes the new value). Keep the files' tab indentation.

English:

```json
{
  "nav": {
    "mySubscriptions": "My subscriptions",
    "group": {
      "learning": "My learning"
    }
  },
  "scheduling": {
    "family": {
      "child": "Child",
      "allChildren": "All children",
      "upcoming": "Upcoming sessions",
      "past": "Past sessions",
      "next": "Next session",
      "noNext": "No sessions are coming up.",
      "sessionLine": "{{student}} · {{course}} · {{teacher}}",
      "subscriptionLine": "{{student}} with {{teacher}}",
      "endsOn": "Ends on {{date}}"
    }
  }
}
```

Arabic:

```json
{
  "nav": {
    "mySubscriptions": "اشتراكاتي",
    "group": {
      "learning": "تعلّمي"
    }
  },
  "scheduling": {
    "family": {
      "child": "الابن",
      "allChildren": "كل الأبناء",
      "upcoming": "الحصص القادمة",
      "past": "الحصص السابقة",
      "next": "الحصة القادمة",
      "noNext": "لا توجد حصص قادمة.",
      "sessionLine": "{{student}} · {{course}} · {{teacher}}",
      "subscriptionLine": "{{student}} مع {{teacher}}",
      "endsOn": "ينتهي في {{date}}"
    }
  }
}
```

- [ ] **Step 4: Format and regenerate routes**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src && npx pnpm@10 exec vite build`
(the build regenerates `src/routeTree.gen.ts`).

- [ ] **Step 5: Run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src`
Expected: PASS.

- [ ] **Step 6: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass; coverage lines/statements ≥ 80, branches/functions ≥ 70; `check-colors` prints no findings.

- [ ] **Step 7: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): student and parent sessions, subscriptions and home

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: End-to-end through Caddy, STATE.md

**Files:**
- Create: `dashboard/e2e/sessions.spec.ts`
- Modify: `STATE.md` (meta), submodule pointers (meta, after merge)
- CI: no change. The `e2e` job already migrates a fresh database, runs `seed_dev`, sends email inline into files that `e2e/mail.ts` reads (`E2E_MAIL_DIR`) and runs every spec in `e2e/`.

**Interfaces:**
- Consumes: `login`, `expectLoggedIn`, `DEMO_URL`, `DEMO_ADMIN` from `e2e/fixtures.ts`; `latestLink` from `e2e/mail.ts` (as `people-catalogue.spec.ts`); the labels and texts of Tasks 9–13; Task 8's seeded missing report.
- Produces: the spec §8 journey. It creates its own teacher, course, package and student; the Missing-reports check expects Task 8's seeded row, so a dev database seeded before Plan 5 needs `seed_dev` run once more (it adds the marks and reports and changes nothing else).

- [ ] **Step 1: Write the e2e spec**

The demo academy keeps UTC. Today's session must already have started when the teacher marks it (P5-5), so the slot starts an hour before now (or at 00:00 in the day's first hour); generation creates today's session even though its time has passed (Plan 4 D13). Teacher and student set their passwords through the emailed invite, as in `people-catalogue.spec.ts`. Button and label names that are substrings of others use `exact: true`.

Spec §8 step 3 says the session is gone from Missing reports; a session taught today can never be on that list (it needs to have ended more than 24 hours ago), so the spec checks that the list renders the seeded row and not this student, and the 24-hour window itself is pinned by Task 5's `test_a_report_is_missing_24_hours_after_the_session_ends` and Task 7's `test_missing_reports_for_admins_and_the_teachers_own`.

Create `dashboard/e2e/sessions.spec.ts`:

```ts
import { type Browser, expect, type Page, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { latestLink } from "./mail";

const INVITE =
	/http:\/\/[^\s"<]+\/app\/reset-password\?uid=[^\s"<&]+&token=[^\s"<]+/;
const weekday = (day: string) =>
	new Intl.DateTimeFormat("en", { weekday: "short", timeZone: "UTC" }).format(
		new Date(`${day}T00:00:00Z`),
	);

/** An hour ago on the demo academy's clock (UTC), or midnight in the first
 * hour of the day: today's session must already have started, or its
 * attendance stays closed (P5-5). Generation still creates today's session
 * when its time has passed (Plan 4 D13). */
function startedTime(now = new Date()): string {
	const earlier = new Date(now.getTime() - 60 * 60_000);
	if (earlier.getUTCDate() !== now.getUTCDate()) return "00:00";
	return earlier.toISOString().slice(11, 16);
}

/** Follow the emailed invite, set a password and sign in, in a new context. */
async function acceptInvite(
	browser: Browser,
	email: string,
	password: string,
	name: string,
): Promise<Page> {
	const link = await latestLink(email, INVITE);
	const context = await browser.newContext();
	const page = await context.newPage();
	await page.goto(link);
	await page.getByLabel(/^new password/i).fill(password);
	await page.getByRole("button", { name: "Reset password" }).click();
	await expect(page.getByText(/you can now sign in/i)).toBeVisible();
	await page.goto(`${DEMO_URL}/app/login`);
	await page.getByRole("textbox", { name: /email/i }).fill(email);
	await page.getByRole("textbox", { name: /password/i }).fill(password);
	await page.getByRole("button", { name: /sign in/i }).click();
	await expectLoggedIn(page, new RegExp(name));
	return page;
}

// Spec §8: the admin sees today's session; the invited teacher marks the
// student present and writes the report; the admin sees the report; the
// student sees one session used. Required labels end in `*`, hence regexes.
test("a teacher marks today's session and reports; the student sees it used", async ({
	page,
	browser,
}) => {
	const stamp = Date.now();
	const teacher = `E2E Tutor ${stamp}`;
	const teacherEmail = `e2e-tutor-${stamp}@e2e.test`;
	const student = `E2E Learner ${stamp}`;
	const studentEmail = `e2e-learner-${stamp}@e2e.test`;
	const course = `E2E Recitation ${stamp}`;
	const pkg = `E2E Eight ${stamp}`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// A teacher (invited by email), their course, a package and a student
	await page.goto(`${DEMO_URL}/app/people/teachers/new`);
	await page.getByLabel(/^full name/i).fill(teacher);
	await page.getByLabel(/^gender/i).selectOption("male");
	await page.getByLabel(/^email/i).fill(teacherEmail);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/teachers\/\d+$/);

	await page.goto(`${DEMO_URL}/app/catalogue/courses/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`تلاوة ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(course);
	await page.getByLabel(teacher, { exact: true }).click();
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/courses$/);

	await page.goto(`${DEMO_URL}/app/catalogue/packages/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`ثمان ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(pkg);
	await page.getByLabel("Sessions per week").fill("2");
	await page.getByLabel("Duration", { exact: true }).fill("1");
	await page.getByLabel("Duration unit").selectOption("month");
	await expect(page.getByText("8 sessions in total")).toBeVisible();
	await page.getByLabel("Price").fill("400");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/packages$/);

	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(student);
	await page.getByLabel(/^email/i).fill(studentEmail);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);

	// A subscription whose slot today started an hour ago
	await page.goto(`${DEMO_URL}/app/scheduling/subscriptions/new`);
	const startsOn = page.getByLabel(/^Starts/);
	await expect(startsOn).toHaveValue(/^\d{4}-\d{2}-\d{2}$/);
	const today = await startsOn.inputValue();
	await page.getByLabel("Find a student").fill(student);
	await page.getByLabel(/^Student/).selectOption({ label: student });
	await page.getByLabel(/^Course/).selectOption({ label: course });
	await page.getByLabel(/^Teacher/).selectOption({ label: teacher });
	await page.getByLabel(/^Package/).selectOption({ label: pkg });
	await page.getByLabel(weekday(today), { exact: true }).click();
	await page.getByLabel(/^Start time/).fill(startedTime());
	await page.getByRole("button", { name: "Create subscription" }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/subscriptions\/\d+$/);

	// 1. The admin sees today's session (the list opens on Today)
	await page.goto(`${DEMO_URL}/app/scheduling/sessions`);
	await page.getByRole("searchbox").fill(student);
	const adminRow = page.getByRole("row", { name: new RegExp(student) });
	await expect(adminRow).toContainText("Scheduled");

	// 2. The teacher accepts the invite, marks the student present and reports
	const tutor = await acceptInvite(
		browser,
		teacherEmail,
		"e2e-Tutor-2026",
		teacher,
	);
	await tutor.getByRole("link", { name: "My sessions" }).first().click();
	await expect(tutor).toHaveURL(/\/app\/teaching\/sessions$/);
	const row = tutor.getByRole("row", { name: new RegExp(student) });
	await row
		.getByLabel(`Student attendance for ${student}`, { exact: true })
		.selectOption("present");
	await expect(row).toContainText("Completed");
	await row
		.getByRole("button", { name: `Write the report for ${student}`, exact: true })
		.click();
	const report = tutor.getByRole("dialog");
	await report.getByLabel(/^Behaviour/).selectOption({ label: "Excellent" });
	await report.getByLabel(/^Participation/).selectOption({ label: "Good" });
	await report.getByLabel("Notes").fill("Clear recitation.");
	await report.getByRole("button", { name: "Save report" }).click();
	await expect(tutor.getByRole("dialog")).toHaveCount(0);
	await expect(
		row.getByRole("button", {
			name: `Edit the report for ${student}`,
			exact: true,
		}),
	).toBeVisible();
	await tutor.context().close();

	// 3. The admin sees the report; the session is not under Missing reports
	await page.reload();
	await page.getByRole("searchbox").fill(student);
	await page
		.getByRole("row", { name: new RegExp(student) })
		.getByRole("link", { name: student, exact: true })
		.click();
	await expect(page).toHaveURL(/\/app\/scheduling\/sessions\/\d+$/);
	await expect(page.getByText(`Written by ${teacher}`)).toBeVisible();
	await expect(page.getByLabel(/^Behaviour/)).toHaveValue("5");
	await page.goto(`${DEMO_URL}/app/scheduling/reports`);
	// The seeded demo leaves one old completed session without a report.
	await expect(page.getByRole("listitem").first()).toBeVisible();
	await expect(page.getByRole("listitem").filter({ hasText: student })).toHaveCount(
		0,
	);

	// 4. The student signs in and sees one session used
	const learner = await acceptInvite(
		browser,
		studentEmail,
		"e2e-Learner-2026",
		student,
	);
	await learner.goto(`${DEMO_URL}/app/learning/subscriptions`);
	await expect(learner.getByText("1 of 8 sessions")).toBeVisible();
	await learner.context().close();
});
```


- [ ] **Step 2: Run it against the stack, as the CI `e2e` job does**

From the meta root, with a fresh database: migrate and seed, start Django, the dashboard preview and the Caddy edge, then run Playwright.

```bash
cd backend
export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan_e2e CELERY_BROKER_URL=redis://localhost:56379/0 \
  DJANGO_SETTINGS_MODULE=config.settings.local DJANGO_SECRET_KEY=ci-only DJANGO_READ_DOT_ENV_FILE=False \
  DJANGO_EMAIL_BACKEND=django.core.mail.backends.filebased.EmailBackend DJANGO_EMAIL_FILE_PATH=/tmp/etqan-mail \
  CELERY_TASK_ALWAYS_EAGER=true DJANGO_TENANT_URL_TEMPLATE=http://{domain}
mkdir -p /tmp/etqan-mail
.venv/bin/python manage.py migrate_schemas --shared && .venv/bin/python manage.py seed_dev
nohup .venv/bin/python manage.py runserver 127.0.0.1:8000 > /tmp/django.log 2>&1 &
cd ../dashboard
npx pnpm@10 build
nohup npx pnpm@10 preview --port 4173 --host 127.0.0.1 > /tmp/preview.log 2>&1 &
docker run -d --name edge --network host -v "$PWD/../caddy/Caddyfile.e2e:/etc/caddy/Caddyfile:ro" caddy:2.11.4-alpine
E2E_DEMO_URL=http://demo.etqan.localhost E2E_OTHER_URL=http://other.etqan.localhost E2E_MAIL_DIR=/tmp/etqan-mail \
  npx pnpm@10 exec playwright test e2e/sessions.spec.ts
```

(`etqan_e2e` must be an empty database: `createdb -h localhost -p 55432 -U etqan etqan_e2e`.) Expected: `sessions.spec.ts` passes; running `npx pnpm@10 e2e` passes every spec, `academy-sites.spec.ts` included once the marketing server runs on `:4321` as in CI. Afterwards stop the three servers (`docker rm -f edge`, and the Django and preview processes) and drop `etqan_e2e`.

- [ ] **Step 3: Update `STATE.md`**

Replace the "Where we are", "Next" and "Follow-ups" sections with:

```markdown
## Where we are

Plan 5 (sessions, attendance & reports, B0 milestone 5) in review: branch `feat/sessions-attendance`
in backend, dashboard and meta (spec `docs/superpowers/specs/2026-09-25-sessions-attendance-design.md`,
plan `docs/superpowers/plans/2026-09-25-plan-5-sessions-attendance.md`). Teachers mark attendance
on their own sessions once they start and write staff-only reports; admins list, filter, export,
bulk-mark, cancel and restore sessions and see missing reports; students and parents see their
sessions and progress. `sessions_used` now follows the one counting rule with the academy's
absent/excused switches.

## Next

Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
Plan 6 of the roadmap. Counting goes through `scheduling.services` (`rules.consuming` inside
`derive`) and attendance through `mark_attendance`; never restate either.

## Follow-ups (from Plans 4–5)

- Changing the academy timezone leaves already-generated sessions at their old UTC instant.
- Deactivated students and teachers keep generating sessions until the subscription expires.
- A renewal that starts today can duplicate a slot session that already started today on the old subscription.
- The teacher and course pickers in the subscription and session filters cap at 100.
- Restoring a cancelled session is allowed whatever its subscription's state, so a session can come back inside a pause or on an ended subscription.
- A teacher's attendance controls open within a minute of the start (the list re-reads each minute), not at the exact second.
```

- [ ] **Step 4: Commit (dashboard, then meta) and open PRs**

```bash
git -C dashboard add e2e/sessions.spec.ts
git -C dashboard commit -m "test(e2e): teacher marks and reports today's session; the student sees it used

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git -C backend push -u origin feat/sessions-attendance
git -C dashboard push -u origin feat/sessions-attendance
git add STATE.md
git commit -m "chore: state for Plan 5 — sessions, attendance & reports

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push -u origin feat/sessions-attendance
```

Open one PR per repo: backend → `main`, dashboard → `main`, meta → `master`. PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Nothing merges without the user's approval. After the submodule PRs merge, bump the meta pointers (`git add backend dashboard`) to the merge commits, commit `chore: bump backend and dashboard for Plan 5 — sessions, attendance & reports` with the trailer above, and push.
