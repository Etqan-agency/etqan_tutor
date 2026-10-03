# Slice B2e — Trial Sessions and Teacher Availability — Design

**Date:** 2026-10-03
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); its 22 findings are applied below.
**Phase:** B2, slice e (`2026-10-03-b2-scheduling-depth-design.md` §3, as amended by B2b: B2e = trials & availability).
**Builds on:** Plan 2 (site inquiries, kind `trial`), Plan 4 (subscriptions, slots, P4-9 clashes reported, never
blocked), Plan 5 (attendance, cancel, restore, reports), Plan 7 (payroll by course rate), B2a (session kinds,
hand-added sessions and their wall-clock input, `pays_teacher`, `delete_session`, the one-live-compensation pattern),
B2b (postponement), B2c (activity log), B2d (archives), Plan 13 (switches).
**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §2.4 SCHED-007 (full field list), §5.5 SCHED-007 / SCHED-012;
`docs/PHASE_1_SYSTEM_AUDIT.md` SCHED-007, SCHED-012 (fields UNKNOWN), FLOW-002 (conversion INFERRED), §5.2 resources
(`trial::session`, `teacher::schedule`), §7 entity TrialSession, §19 (teacher schedules' fields MEDIUM gap).

## 1. Goal

The office records trial requests with TutorHamster's fields, schedules each as a trial session with a teacher it can
pick with a "suggest" button, follows it through attendance like any session, and turns a completed trial into a
subscription. Teachers have weekly availability windows that power the suggestion and warn when the office schedules
outside them.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| E-1 | A **trial request** is its own record in `etqan.scheduling` with TutorHamster's fields: student\* (an existing student whose account is active, any profile status — `trial` included), request source\* (website / app / API), course\*, number of students\* (1–20), preferred teacher gender\* (male / female / no preference), minutes\* (15–180), desired start, request date\*, request status\*, "how did you hear about us"\* (Facebook / Google / YouTube / web search / referral / other), "student rated the trial?", notes (\* required). | TH SCHED-007; P1 SCHED-007, FLOW-002 · [assumed] minutes from 15, not TH's 1, because sessions hold 15–240 (Plan 4); 1–20 students |
| E-2 | **Request status**: `under_review` (default), `accepted`, `rejected`. TutorHamster's other values are UNKNOWN. A rejected request cannot be scheduled and its sessions cannot be restored. | TH SCHED-007 ("default under review; other values UNKNOWN") · [assumed] values |
| E-3 | **Scheduling creates a `trial` session** (Session.kind gains `trial`; ledger D8) that points at its request (`Session.trial`, as a make-up points at its original): no subscription, never consumes; attendance, cancel, restore, reports, postponement and the log work unchanged. **At most one live (non-cancelled) session per request** (a partial unique constraint, as `scheduling_one_live_compensation`). The request's **current session** is its live one, else its latest; the trial's status (not scheduled / scheduled / completed / cancelled / at disposal) is the current session's. A cancelled trial is scheduled again with a new session; its cancelled rows stay as history. | phase B2-4, B2-11; TH SCHED-007 status; review · [assumed] |
| E-4 | The trial session's `pays_teacher` defaults to on (ledger D9) and is TutorHamster's "paid to teacher?"; it is set at scheduling and changed with B2a's pays-teacher action, which for a `trial` session needs `trial_sessions` on (instead of `extra_sessions`). Today's payroll pays it by its course rate (0 without a rate); B4 decides trial pay. | TH SCHED-007; ledger D9; phase "Unblocks B4 (trial pay)" |
| E-5 | **The teacher** must be active and teach the course, by Plan 4's rule (a course that lists no teachers accepts any active teacher). The preferred gender is advice, never enforced. The start may be in the past (recording a trial that happened, as B2a A-14). | TH SCHED-007 ("any available teacher"); spec B2a §4.1 |
| E-6 | **Suggest a teacher**: candidates are the course's teachers (all active teachers when it lists none), active. Ranked by: **free** (no overlapping non-cancelled session), then **available** (inside their windows: yes, then no windows, then no; ignored while `teacher_availability` is off), then **gender match** (a teacher with no gender never matches; ignored with no preference), then fewest non-cancelled sessions in the academy week (Monday–Sunday) of the local start date, then name. Up to 5, each with its flags. Never blocks. | TH SCHED-007 ("suggest button for the best match"); phase B2-12 · [assumed] ranking |
| E-7 | **Conversion**: a request whose current session is `completed` (any student attendance: a no-show may still subscribe) and that is not yet converted opens the subscription form pre-filled (student, course, teacher); creating the subscription links it to the request in the same transaction. One conversion per request; a converted request cannot be scheduled again. | P1 FLOW-002 (conversion INFERRED); phase B2-11 · [assumed] |
| E-8 | **Inquiry intake** happens in the dashboard: an inquiry of kind `trial` offers "Create trial request" (shown with both `trial_session.create` and `inquiry.update`), which opens the trial form with source `website` and the inquiry's name, contact and message in the notes; on success the dashboard marks the inquiry handled through the site's existing admin API. The trial stores the inquiry's id as a plain integer, unique when set (no foreign key, no scheduling → site import: `lint-imports`). The student must exist (the office creates one first when needed). This refines phase B2-11 ("through `etqan.site`'s services"), amended. | phase B2-11; P1 FLOW-002; orchestration §4.3 (site is B8's) · [assumed] |
| E-9 | **Teacher availability** is weekly windows: teacher, weekday, start time, end time, in academy time (like slots, Plan 4 P4-6). Windows of one teacher on one weekday never overlap; touching windows count as one when checking. A window may not cross midnight. | P1 SCHED-012 (fields UNKNOWN) · [assumed] |
| E-10 | Availability is edited by the office (`teacher_schedule.update`) and by each teacher for themselves. | P1 §5.2 `teacher::schedule`; §11 (teacher "availability") · [assumed] teacher self-service |
| E-11 | **Warnings, never blocks**: every slot row carries `outside_availability` (computed on read, in the slot payload: slots and windows share weekday + academy time), so subscription create, renewal, teacher change, slot add / edit all show it. A session-level `outside_availability` is in the answers of B2a's three add-session routes, the trial schedule route and B2b's office postponement. Only when the teacher has at least one window: a teacher with no windows gets no warning (unknown, not unavailable). | phase B2-12; spec Plan 4 P4-9; review |
| E-12 | Trial requests are office records: teachers, students and parents never see the request; they see the trial session in their own session lists as any session (a "Trial" badge). Non-office users may postpone a trial session by B2b's rules; a trial has no window (like an extra). | [assumed]; spec B2b B-6, B-7 |
| E-13 | Switches, off by default: `trial_sessions` and `teacher_availability` (new lines under the B2 marker). With `trial_sessions` off the trial routes 404, `trial_id` on subscription create is a 400, and the screens hide; trial sessions already made keep showing, counting and working in the session lists (FT-4). With `teacher_availability` off its routes 404, no suggestion uses it and no warning is computed. | PO-5; spec Plan 13 FT-4 |

## 3. Data

### 3.1 `TrialRequest` (new)

| Field | Notes |
|---|---|
| `student` | → StudentProfile, PROTECT |
| `source` | `website` \| `app` \| `api` |
| `course` | → Course, PROTECT |
| `students_count` | small int 1–20, default 1 |
| `preferred_gender` | `male` \| `female` \| `any` (default) |
| `minutes` | small int 15–180 |
| `desired_at` | datetime (UTC), nullable |
| `requested_on` | date, default today (academy) |
| `request_status` | `under_review` (default) \| `accepted` \| `rejected` |
| `heard_from` | `facebook` \| `google` \| `youtube` \| `web_search` \| `referral` \| `other` |
| `rated` | bool, default false |
| `notes` | text |
| `inquiry_id` | positive int, nullable; `UNIQUE WHERE NOT NULL` (E-8) |
| `converted_to` | → Subscription, nullable, `SET_NULL`, unique |
| `created_by` | → User, nullable, `SET_NULL` |
| `created_at`, `updated_at` | auto |

### 3.2 Session (existing)

- `Kind` gains `trial` (a choices-only migration, no data change). The check "compensation has an original" holds
  for `trial`.
- New `trial` → TrialRequest, nullable, PROTECT, `related_name="sessions"`. Constraints: `kind = 'trial'` ⇔ `trial`
  set; `UNIQUE(trial) WHERE trial IS NOT NULL AND status <> 'cancelled'` (one live session per request).
- A `trial` session has no subscription and no slot (so it is not on the Today board, like other hand-added sessions
  without a slot).

### 3.3 `TeacherAvailability` (new)

`teacher` → TeacherProfile (CASCADE), `weekday` 0–6 (Monday = 0, as slots), `start_time`, `end_time`
(`end_time > start_time`). Index `(teacher, weekday)`.

## 4. Behaviour

**Lock order** for everything below: trial request → its sessions (pk order) → a new subscription. A session-first
caller (B2a/Plan 5 services on a trial session) never locks the request.

### 4.1 Requests

`create_trial(by, **fields)` / `update_trial(trial, by, **fields)`: validate E-1. While the request has a non-cancelled
session: changing `student`, `course` or `minutes` → 409 `scheduling.trial_scheduled` (change the session), and
`request_status = rejected` → 409 `scheduling.trial_scheduled` (cancel it first).

`delete_trial(trial)`: lock the request, then its sessions. Refusals, in order: converted → 409
`scheduling.trial_converted`; any session marked, completed, at disposal or payroll-locked → 409
`scheduling.not_allowed_in_status`. Then delete its sessions (scheduled or cancelled) and the request.

The generic `DELETE sessions/<id>/` refuses a `trial` session (409 `scheduling.trial_session`: delete or cancel it
through its trial), so no path deletes a trial session session-first.

`restore_session` gains one refusal for a `trial` session (after its lock, read-only on the request): the request is
`rejected` or converted, or another of its sessions is live → 409 `scheduling.trial_scheduled` /
`scheduling.trial_rejected` / `scheduling.trial_converted`. The partial unique constraint backs the live-session rule.

### 4.2 Scheduling

`schedule_trial(trial, by, *, teacher_id, occurs_on, start_time, minutes=None, meeting_url="", pays_teacher=True)`:

1. Lock the request, then its sessions.
2. Refusals, in order: converted → 409 `scheduling.trial_converted`; `rejected` → 409 `scheduling.trial_rejected`; a
   live session → 409 `scheduling.trial_scheduled`; teacher inactive or not teaching the course → 400 on `teacher_id`.
3. Create the session through B2a's hand-added helper (`manual._session`: academy wall-clock to UTC with Plan 4's one
   conversion, `full_clean`) with `kind=trial`, `trial`, no subscription, the request's student and course, minutes
   (default the request's), meeting link (default the teacher's), `pays_teacher`, `created_by=by`. Past starts are
   allowed (E-5). Set `request_status = accepted` when it was `under_review`.
4. Answer `{trial, conflicts, outside_availability}`.

### 4.3 Suggest

`suggest_teachers(course_id, occurs_on, start_time, minutes, preferred_gender)`: E-6. Candidates come from a new
additive identity service `active_teachers(user_ids=None)` (scheduling may not import `identity.models`) after reading
the course's teacher ids. About five queries: course teacher ids, candidate profiles and users, their windows that
weekday, their overlapping sessions, their week's counts. Answer `[{teacher, free, available, gender_match}]`
(`available`: true / false / null).

### 4.4 Conversion

`create_subscription` gains an optional `trial=None` (additive). When given: lock the request, then its current
session (`select_for_update`), and refuse: session not `completed` → 409 `scheduling.trial_not_completed`; already
converted → 409 `scheduling.trial_converted`; `student_id` differs from the session's student → 400 on `student_id`.
Then create as today and set `trial.converted_to`. The subscription view checks `trial_session.update` explicitly
(its route declares only `subscription.create`); `trial_id` while `trial_sessions` is off is a 400 on `trial_id`.

### 4.5 Availability

`set_availability(teacher, windows)`: replaces the teacher's windows in one transaction, under a transaction-scoped
advisory lock per teacher (`pg_advisory_xact_lock`), so two saves cannot interleave. Validation: weekday 0–6,
`end > start`, no overlap on a weekday → 400 naming the index.

`is_available(teacher_id, starts_at, minutes)` → `True | False | None` (`None`: no windows). The local start comes from
`starts_at` and the local end from `starts_at + minutes` (both converted from UTC, so DST is right); a session crossing
local midnight is outside; touching windows are merged before checking.

### 4.6 Lists

`filter_trials(**filters)`: student, course, teacher (the current session's), teacher gender (the current session
teacher's), status (`not_scheduled` or the current session's status), request status, source, heard from, requested
from / to; newest first. CSV export with all columns (TH "Export to Excel"). The sessions list's `kind` filter already
accepts every `Session.Kind` value, so `trial` comes with the choice.

## 5. Access

New resources under the B2 marker, `verbs=ALL_VERBS` (TH's twelve):

- `trial_session` ("Trial sessions" / "الحصص التجريبية"), in use: view, view_any, create, update, delete (TH
  `trial::session`).
- `teacher_schedule` ("Teacher schedules" / "مواعيد المعلمين"), in use: view, update (TH `teacher::schedule`).

| | Office code | Teacher | Student / parent |
|---|---|---|---|
| Trials: list, read | `trial_session.view_any` / `.view` | 404 | 404 |
| Create, update, schedule, suggest | `trial_session.create` / `.update` | 404 | 404 |
| Delete | `trial_session.delete` | 404 | 404 |
| Convert | `subscription.create` + `trial_session.update` (explicit) | 404 | 404 |
| Availability: read / write | `teacher_schedule.view` / `.update` | own | 404 |

The trial session itself follows the session rules (Plan 5, B2a).

## 6. API (`/api/v1/`)

| Route | Method | Notes |
|---|---|---|
| `trials/` | GET, POST | List (filters §4.6, CSV) and create. Feature `trial_sessions`. |
| `trials/<id>/` | GET, PATCH, DELETE | Read, update, delete. |
| `trials/<id>/schedule/` | POST | §4.2. `{teacher_id, occurs_on, start_time, minutes?, meeting_url?, pays_teacher?}`. `201 {trial, conflicts, outside_availability}`. |
| `trials/suggest/` | GET | `?course=&occurs_on=&start_time=&minutes=&gender=`. §4.3. |
| `subscriptions/` | POST | Accepts `trial_id` (§4.4). |
| `schedule/availability/<user_id>/` | GET, PUT | §4.5. Feature `teacher_availability`. People by User id. Office, or the teacher for themselves. |
| `schedule/availability/` | GET, PUT | The signed-in teacher's own. |

Also: `slot_row` gains `outside_availability`; B2a's add-session answers and B2b's office postponement answer gain it
(E-11); `sessions/<id>/pays-teacher/` takes `trial_sessions` for trial sessions (E-4); B2c's field → switch map shows
`pays_teacher` while `extra_sessions` or `trial_sessions` is on. Trial payload: every field, the current session (id,
status, starts_at, teacher, attendance, pays_teacher), the sessions' count, `converted_to` (id). New codes: 409
`scheduling.trial_rejected`, `scheduling.trial_scheduled`, `scheduling.trial_not_completed`,
`scheduling.trial_converted`, `scheduling.trial_session`.

## 7. Dashboard (`/app/`)

- **Trials** (`/app/scheduling/trials`, NAV entry under the B2 marker with `trial_sessions` on and
  `trial_session.view_any`): the list with TH's filters and optional columns (minutes, request date, paid to teacher,
  how did you hear), CSV; the form (E-1); a detail with **Schedule** (teacher picker with a **Suggest** button showing
  the ranked list with its flags, date and time in academy time and the student's, minutes, link, paid to teacher),
  the current session's status and attendance with a link to it, earlier cancelled sessions, and **Convert to
  subscription** on a completed, unconverted trial (opens the subscription form pre-filled; returns to the trial).
- **Inquiries:** a trial inquiry gets "Create trial request" (E-8). This is a small additive edit to B8's
  `features/website/InquiriesList.tsx`, made under a one-commit ledger `claim` and `release` (orchestration §6.2.1),
  or as a `request` to B8 if it is more than a trivial additive line (conductor ruling, 2026-10-03).
- **Teachers:** an **Availability** tab on the teacher page (week grid of windows, add / remove, save); **My
  availability** for teachers.
- **Warnings:** "Outside {teacher}'s availability" on slot rows and next to any `conflicts` display.
- **Sessions:** a "Trial" badge, and a Trial tab beside B2a's tabs while `trial_sessions` is on.
- Strings in en and ar in new area files `trials.json` and `availability.json`; RTL, phone width, semantic tokens;
  new codes translated.

## 8. Seeds

In `demo`, under the B2 marker, with both switches among `features.BUILT` (so seeding turns them on, as B2a's do):
weekly windows for two teachers; one trial request under review, one scheduled in the coming days, one with a past
completed session converted to a subscription through the service (no invoice: billing is applied in the view).
Idempotent; `other` gets nothing.

## 9. Testing

- **Requests:** validation (every bound — minutes 14 / 15 / 180 / 181 — and choice), active account with profile
  status `trial`, update refusals with a live session (student, course, minutes, rejected), delete refusals in order
  and deletion of cancelled history, generic session delete refused for trial sessions, restore refusals.
- **Scheduling:** refusals in order; the session's fields and defaults; past start allowed; `accepted` set; conflicts;
  the warning; cancel then schedule again (one live, history kept); the partial constraint; a trial session never
  consumes, gets today's reminder, appears in `payroll_sessions` with `pays_teacher` on and not with it off;
  postponement by the student and the office; pays-teacher with `trial_sessions` on and `extra_sessions` off.
- **Suggest:** ranking per flag and tie-break; a course with no teachers; a teacher with no gender; availability off;
  query count bounded.
- **Conversion:** refusals; the session lock; the link in the same transaction; one per request; deleting the
  subscription makes it convertible again; lock order (SQL capture).
- **Availability:** replace semantics; the advisory lock; overlap and bounds; `is_available` across window edges,
  touching windows, midnight, no windows → None, academy timezone and DST; `outside_availability` on slot rows and the
  listed answers only when on.
- **Access:** the code matrix; the teacher edits only their own availability; non-office 404 on trials; trial sessions
  visible to the teacher and student in their lists.
- **Switches:** routes 404 when off, after the permission check; `trial_id` 400 when off; trial sessions keep showing.
- **Existing suites** pass unchanged.
- **Dashboard:** list, form, schedule dialog with suggestions, conversion, availability grid, warnings, inquiry button.
- **e2e** (`e2e/b2-trials.spec.ts`, spec-owned data): the admin creates a trial request, uses Suggest, schedules it at
  a past start, marks the student present, converts it to a subscription.

## 10. Known limits (accepted)

- Intake from an inquiry is two calls from the dashboard; a failure between them leaves the inquiry unhandled.
- Availability is in academy time; a teacher abroad enters windows in the academy's time.
- A trial for several students (`students_count` > 1) is still one session for the named student: group trials wait for
  B2f's groups.
- Deleting a converted subscription unlinks the conversion (`SET_NULL`), so the request can be converted again.
- A course a trial request uses cannot be deleted; the catalogue's refusal message speaks of subscriptions.

## 11. Out of scope

Trial notices beyond today's session reminders (B5); trial pay rules (B4); a public self-booking page (not taken);
group trials (B2f); weekly-schedule substitutes (B2g).
