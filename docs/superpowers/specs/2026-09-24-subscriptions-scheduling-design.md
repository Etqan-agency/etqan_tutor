# Plan 4 — Subscriptions & Scheduling — Design

**Date:** 2026-09-24
**Status:** Approved in brainstorming (sections 1–4), pending written-spec review.
**Phase:** B0, milestone 4 of the parity roadmap (`2026-09-24-parity-roadmap-design.md`).
**Builds on:** v1 spec §4.4–4.6, §5.1, §5.3, §6 (`2026-09-23-etqan-tutor-v1-design.md`); Plan 3 (`2026-09-24-people-catalogue-design.md`): people, courses with teachers, packages, `AcademySettings`, role permissions, `scope_for`, CSV export.
**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §2.3 (SUB-001), §2.4 (SCHED-001, SCHED-002, SCHED-017) and §3 items 3 and 5. Roadmap rule R4 applies.

## 1. Goal

An admin turns a student's package into a running timetable:
1. They create a subscription (one student, one course, one teacher, one package).
2. They give it weekly slots and, when needed, pauses.
3. The system generates the sessions ahead of time.

A job per academy keeps the timetable current:
- it moves subscriptions in and out of pauses;
- it expires them after their grace period;
- it generates the next horizon.

Admins can also:
- see today's slots on a Today board;
- generate any date range on demand;
- renew a subscription. Sessions taken beyond the package are carried into the renewal and subtracted from it.

Attendance, session reports, and the teacher, student and parent screens are Plan 5. Plan 4 creates the `Session` table they will use.

## 2. Decisions

| # | Decision |
|---|---|
| P4-1 | One tenant app, `etqan.scheduling`, owns `Subscription`, `SubscriptionPause`, `ScheduleSlot` and `Session`. It has separate service modules for subscriptions, generation and the Today board. Subscriptions and sessions share one rule set, so one app avoids circular calls. Other apps reach it only through its services. |
| P4-2 | A subscription has one course, one teacher and one package (v1 D8). Multi-course bundles and family or group subscriptions are phase B2. |
| P4-3 | **Running out of sessions does not stop the subscription.** Generation continues. Sessions used beyond the total are **extra sessions**, and the renewal subtracts them (TutorHamster: "extra sessions outside the package… deducted in the following month"). |
| P4-4 | **Grace period.** A subscription keeps generating sessions for `AcademySettings.renewal_grace_days` (default 7) after its end date, then expires. Sessions in that window are extras. A setting of 0 means it expires at the end date. |
| P4-5 | Package values are copied onto the subscription at creation (sessions, minutes, allowed freeze days, price and currency). Package edits never change existing subscriptions. The price is editable when creating and renewing. |
| P4-6 | Slot times are in the academy's timezone. The UI also shows the student's local time when it differs (SCHED-017). |
| P4-7 | Automatic changes delete only **untouched** sessions: status `scheduled`, both attendances `not_set`, and `starts_at` in the future. Past or marked sessions are never changed by the system. |
| P4-8 | Generation is idempotent. It is guarded by a unique (slot, date) constraint and runs daily, on demand, and after every change that affects the timetable. |
| P4-9 | Teacher double-bookings are reported, never blocked. |
| P4-10 | A renewal defaults to the previous subscription's price, as TutorHamster renews at the amount paid. |
| P4-11 | Plan 4 builds admin screens only. The read endpoints for teachers, students and parents exist now; their screens are Plan 5. |

## 3. Data (tenant schema)

### 3.1 AcademySettings (existing, `etqan.academy`)

New fields:
- `generation_horizon_days`, 1–60, default 14;
- `renewal_grace_days`, 0–60, default 7.

### 3.2 Subscription

| Field | Notes |
|---|---|
| `student` | → `StudentProfile` |
| `course` | → `catalogue.Course` |
| `teacher` | → `TeacherProfile`. It must be an active teacher. When the course lists teachers, it must be one of them. |
| `package` | → `catalogue.Package` (for reference; the numbers below are copies) |
| `starts_on` | date |
| `term_ends_on` | Stored when the subscription is created (see below). |
| `sessions_total` | copied from the package's `sessions_total` |
| `session_minutes` | copied |
| `freeze_days_allowed` | copied |
| `price_minor`, `currency` | copied, editable at creation and renewal |
| `status` | `active · paused · expired · cancelled` |
| `renewed_from` | nullable one-to-one → Subscription (a subscription is renewed at most once) |
| `notes` | text |

`term_ends_on` depends on the duration unit:
- **`day` × n:** `starts_on + (n − 1)` days.
- **`month` × n:** add n calendar months to `starts_on`, then step back one day. When the start day doesn't exist in the target month, the term ends on that month's last day instead. For example: 1 Mar + 1 month → 31 Mar; 31 Jan + 1 month → 28 Feb (or 29 Feb in a leap year); 15 Jan + 2 months → 14 Mar.

**Derived values, never stored.** One service computes all of them:
- `paused_days`: the total inclusive length of the subscription's pauses.
- `ends_on` = `term_ends_on` + `paused_days`.
- `grace_ends_on` = `ends_on` + `renewal_grace_days`, using the academy's current setting.
- `sessions_used`: the subscription's consuming sessions.
  - Plan 4 rule: `status = completed` and student attendance `present` or `absent`.
  - Plan 5 may add academy switches for absent and excused.
  - Nothing is completed in Plan 4, so it is 0 there.
- `carried_over_sessions`: the previous subscription's `extra_sessions` (0 when there is none). It is computed live, so a grace session marked after the renewal is still subtracted.
- `sessions_remaining` = `sessions_total` − `carried_over_sessions` − `sessions_used`. It can be negative.
- `extra_sessions` = `max(0, −sessions_remaining)`.
- `progress` = `(carried_over_sessions + sessions_used) / sessions_total`, shown capped at 100%.

### 3.3 SubscriptionPause

| Field | Notes |
|---|---|
| `subscription` | → Subscription |
| `from_date`, `to_date` | inclusive |
| `reason` | text, optional |

Rules:
- `from_date` ≤ `to_date`.
- `from_date` ≥ `starts_on`, and `from_date` ≤ the current `ends_on`.
- A pause may not overlap another pause of the same subscription.
- The total `paused_days` must not exceed `freeze_days_allowed`.

### 3.4 ScheduleSlot

| Field | Notes |
|---|---|
| `subscription` | → Subscription |
| `weekday` | 0 = Monday … 6 = Sunday |
| `start_time` | local time, academy timezone |
| `minutes` | 15–240, defaults to the subscription's `session_minutes` |
| `meeting_url` | optional; empty means the teacher's `default_meeting_url` |
| `is_active` | "stopped" slots generate nothing |

Two active slots of one subscription may not share the same weekday and start time.

### 3.5 Session

| Field | Notes |
|---|---|
| `slot` | nullable → ScheduleSlot (null for one-off sessions, Plan 5) |
| `subscription` | nullable → Subscription |
| `student`, `teacher`, `course` | copied from the subscription at creation |
| `occurs_on` | local date |
| `starts_at` | UTC |
| `minutes` | |
| `meeting_url` | resolved at creation: the slot's link, else the teacher's default, else empty |
| `status` | `scheduled · completed · cancelled` |
| `student_attendance`, `teacher_attendance` | `not_set · present · absent · excused` |
| `cancel_reason`, `notes` | text |
| `generated` | bool |

Constraint: `UNIQUE(slot, occurs_on)` where `slot` is not null.

## 4. Behaviour

### 4.1 Generation

`generate(from, to)` covers every active slot whose subscription is `active` or `paused`. For each date D in the window whose weekday matches the slot, it creates a session unless one of these applies:
- D < `starts_on` or D > `grace_ends_on` (counted as `skipped_out_of_term`);
- D falls inside a pause (`skipped_paused`);
- a session for (slot, D) already exists (`skipped_existing`). This uses `bulk_create(ignore_conflicts=True)`.

Converting to UTC: D + `start_time` is read in the academy timezone. A local time that doesn't exist (clock change) moves forward. An ambiguous one takes the first occurrence.

Double-bookings: the run lists every created session that overlaps another non-cancelled session of the same teacher. The run returns `{created, skipped_existing, skipped_paused, skipped_out_of_term, conflicts: [{session, other}]}`.

When generation runs:
- **Daily job:** for today … today + `generation_horizon_days`.
- **On demand:** for an admin range of at most 62 days.
- **For one subscription's horizon:** after it is created, renewed or resumed, and after any slot of it is added, edited or re-activated.

### 4.2 Lifecycle

**The job** runs hourly for every academy, inside `tenant_context`. "Today" is the academy's local date. Each step is safe to repeat:
1. **Pauses:** an `active` subscription with a pause covering today becomes `paused`. A `paused` subscription with no pause covering today becomes `active`.
2. **Expiry:** an `active` or `paused` subscription with today > `grace_ends_on` becomes `expired`. Its untouched sessions are deleted.
3. **Generation:** the horizon is generated.

**Admin actions:**

| Action | Allowed from | Effect |
|---|---|---|
| Create | – | Copies the package values; creates the given slots; generates the horizon. |
| Edit teacher / price / notes | active, paused | A teacher change deletes the untouched sessions and regenerates them with the new teacher. |
| Edit `starts_on` | active, paused, while none of its sessions has attendance marked | Recomputes `term_ends_on`; deletes the untouched sessions; regenerates. |
| Add pause | active, paused | Deletes the untouched sessions inside the pause. The status becomes `paused` at once if the pause covers today. |
| End pause early | a pause covering today | `to_date` becomes yesterday, or the pause is deleted if it started today. The status returns to `active` and the horizon is regenerated. |
| Delete pause | a pause that hasn't started | The horizon is regenerated. |
| Add / edit / re-activate slot | active, paused | Deletes that slot's untouched sessions, then regenerates. |
| Deactivate slot | any | Deletes that slot's untouched sessions. |
| Delete slot | only if it never produced a session | – |
| Cancel | active, paused | The status becomes `cancelled`; the untouched sessions are deleted. |
| Renew | active, paused, expired, and not already renewed | See below. |
| Delete subscription | only if none of its sessions has attendance marked or is completed | Deletes it together with its untouched sessions, for undoing mistakes. |

**Renewal:**
- The new subscription starts on the day after the old `ends_on`, or today if that is later.
- It defaults to the same student, course, teacher and package, and the old price. All of them can be changed in the renew dialog.
- It gets fresh package copies and the old subscription's active slots.
- It gets `renewed_from` = old.
- The old subscription becomes `expired`. Its untouched sessions dated on or after the new `starts_on` are deleted.
- The new subscription's horizon is generated.
- Grace sessions already taught on the old subscription stay there. They reach the new one through `carried_over_sessions`.

**Errors:** invalid transitions raise a domain error with a code, returned as `409`:
- `scheduling.not_allowed_in_status`
- `scheduling.already_renewed`
- `scheduling.freeze_days_exceeded`
- `scheduling.pause_overlaps`
- `scheduling.has_marked_sessions`

Field problems return `400` with Plan 3's field-error shape.

### 4.3 Today board

For the academy's local date, the board lists each active slot whose subscription would generate that day. Each row shows the student, teacher, course, time (plus the student's local time), subscription progress and a state:
- `generated`: a scheduled session exists;
- `missing`: no session exists;
- `completed`;
- `cancelled`.

`missing` rows offer "Generate", which runs generation for that subscription and date.

### 4.4 Access

| Resource | Admin | Teacher | Student | Parent |
|---|---|---|---|---|
| Subscriptions, slots, pauses, their sessions | full | read the ones they teach | read own | read their children's |
| Generate, Today board, renew, cancel, delete | ✓ | | | |

One permission class per role plus `scope_for` per resource, as in Plan 3. Out-of-scope objects return `404`.

## 5. API (`/api/v1/`, existing conventions)

| Route | Methods | Notes |
|---|---|---|
| `subscriptions/` | GET, POST | Filters: `status` (`active·paused·expired·cancelled`; none = all), `student`, `teacher`, `course`, `q` (student name). `?format=csv`. POST accepts `slots: [{weekdays: [..], start_time, minutes?, meeting_url?}]`. |
| `subscriptions/<id>/` | GET, PATCH, DELETE | PATCH: `teacher`, `price_minor`, `notes`, `starts_on` (rules in §4.2). The payload includes every derived value from §3.2. |
| `subscriptions/<id>/renew/` | POST | Optional `starts_on`, `teacher`, `package`, `price_minor`, `course`. |
| `subscriptions/<id>/cancel/` | POST | |
| `subscriptions/<id>/pauses/` | GET, POST | |
| `pauses/<id>/` | DELETE | Only when the pause hasn't started. |
| `pauses/<id>/end/` | POST | |
| `subscriptions/<id>/slots/` | GET, POST | POST `{weekdays: [..], start_time, minutes?, meeting_url?}` creates one slot per weekday. |
| `slots/<id>/` | PATCH, DELETE | PATCH: `start_time`, `minutes`, `meeting_url`, `is_active`. |
| `subscriptions/<id>/sessions/` | GET | Read-only, paginated, `?when=upcoming|past`. |
| `schedule/generate/` | POST | `{from, to}`, at most 62 days. Returns the run result from §4.1. |
| `schedule/today/` | GET | The Today board rows. |
| `academy/settings/` | GET, PATCH | Adds `generation_horizon_days` and `renewal_grace_days`. |

People are referenced by User id, as in Plan 3.

## 6. Dashboard (`/app/`, admin)

- **Navigation:** a new group "Scheduling" holds Today and Subscriptions.
- **Subscriptions list:**
  - status tabs, filters (teacher, course), search and a CSV link;
  - columns: student, course, teacher, progress (bar, used/total, a "+N extra" badge), status, and end date ("in grace until …" once past `ends_on`);
  - uses the shared Pager.
- **New subscription:**
  - Student, then course, then teacher (limited to the course's teachers when it lists any), then package. Choosing the package shows its sessions, minutes and duration.
  - Start date, and the price pre-filled from the package (editable).
  - A slot editor: several weekdays, a start time and minutes. It shows the student's local time when the student's timezone differs.
- **Subscription detail:**
  - **Summary:** dates, remaining/extra/carried-over sessions, grace end, status.
  - **Actions:** Renew (a pre-filled dialog), Cancel and Delete (confirmations).
  - **Slots panel:** add, edit, deactivate, delete.
  - **Pauses panel:** freeze days left, add, end early, delete.
  - **Sessions panel:** upcoming and past, read-only.
- **Today:**
  - the board, with "Generate" on missing rows;
  - a "Generate for range" dialog showing the run result and any double-bookings.
- **Settings → Academy:** the horizon and grace days fields.
- **Throughout:** every string is in Arabic and English; screens work right-to-left and at phone width; only semantic colour tokens are used; not-found and error states are handled.

## 7. Jobs and seeds

- A Celery beat entry `scheduling.run_daily` runs hourly. It loops over every academy with `tenant_context` and runs §4.2 steps 1–3. A failure in one academy is logged and does not stop the others.
- `seed_dev` gives the demo academy four subscriptions with slots (one paused, one in grace), plus one in `other`. Running it twice changes nothing.

## 8. Testing

- **Backend:**
  - **Dates:** `term_ends_on` edge cases (month-end clamping, leap year).
  - **Generation:** window boundaries, pauses, grace, idempotence, clock-change times, double-booking reports, untouched-only deletion.
  - **Lifecycle:** every transition, and the job running twice.
  - **Renewal carry-over,** including a grace session completed after the renewal.
  - **Access:** each endpoint × role, and the other academy returning 404.
  - **The hourly job across two academies,** one failing.
- **Dashboard:** each list, form, panel and dialog, including error, not-found and validation states.
- **E2E through Caddy:** an admin creates a subscription with two slots, the sessions appear on the detail page and on Today, the admin adds a pause, and then renews.
- **Coverage gates as today:** backend ≥ 80%; dashboard lines/statements ≥ 80, branches/functions ≥ 70.

## 9. Risks

- **Timezones.** Wrong UTC conversion puts every session at the wrong hour. Mitigation: a single conversion function, tested for clock-change dates and several timezones.
- **Deleting sessions someone relies on.** Mitigation: only untouched sessions are ever deleted (P4-7), and that is tested for every action.
- **Carry-over surprises.** Extras from a long grace can make a renewal start partly used. Mitigation: the detail page and renew dialog show the carried-over count.
- **The hourly job over many academies.** Each academy runs in its own transaction and is idempotent, so a failure affects only that academy.

## 10. Out of scope (roadmap phase)

- Attendance, cancelling sessions, reports, and the teacher/student/parent screens: Plan 5.
- Invoices on subscription (auto-invoice): Plan 6 (billing).
- Payment fields on the subscription, auto-renew, activation/renewal codes: B3.
- Multi-course, family and group subscriptions; weekly-schedule bulk change and move; make-up, extra and trial sessions; teacher availability: B2.
- Session reminders: Plan 8 (notifications) and B5.
