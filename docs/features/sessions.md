---
title: "Sessions: lifecycle, attendance, classes, postponement, archives and the activity log"
---

A session is one lesson: a student, a teacher, a course and a UTC start instant with a
length. Most sessions are generated from a subscription's weekly slots
([subscriptions.md](subscriptions.md)). The office can also add sessions by hand. Teachers
mark attendance and write reports. The office (admins and staff) marks, cancels,
restores, postpones, archives and reverts. Students and parents read their own sessions
and, when the academy allows it, postpone them. Supervisors (staff with
`session.supervise`) open the sessions assigned to them.

## Concepts

`Session` (`backend/etqan/scheduling/models.py`):

| Group | Fields |
|---|---|
| Identity | `slot` (null for hand-added or postponed sessions), `subscription` (null for trial or standalone extra sessions), `student`, `teacher`, `course`, `occurs_on` (local date), `starts_at` (UTC), `minutes` |
| State | `status`: `scheduled`, `completed`, `cancelled`, `at_disposal`. `student_attendance` / `teacher_attendance`: `not_set`, `present`, `absent`, `excused`. `cancel_reason`, `disposal_reason`, `marked_by/at`, `cancelled_by/at` |
| Class (B2a) | `kind`: `regular`, `compensation`, `extra`, `trial`. `compensates` → original (DB check: only compensations have one). `compensated` and `compensated_by` (`makeup`/`balance`) on the original. `pays_teacher`, `created_by`, `generated` |
| Times (B2b) | `teacher_in_at/out_at`, `student_in_at/out_at`, `actual_minutes`. These are a record only: pay and consumption use `minutes` |
| Postponement (B2b) | `original_slot` + `original_on` (unique pair), `original_starts_at`, `postponed_by/at` |
| Archive (B2d) | `archived_at`, `archived_with_subscription` |
| Other | `trial` (B2e), `substitute_for` (B2g), `supervisor`, `supervisor_attendance`, `opened_by_supervisor_at` (Plan 12b), `payroll_locked` (Plan 7), `meeting_url/provider/ref` ([meetings.md](meetings.md)) |

Related models: `SessionReport` (one per session: behaviour and participation 1–5, plus
notes; written by the session's teacher or the office) and `SessionActivity` (the B2c
log: actor, action, `changes` as `{field: [before, after]}`, `reverts`).

Key DB rules: one session per (slot, date). At most one live compensation per original.
At most one live session per trial request.

**"Untouched"** (`rules.untouched_sessions`) means scheduled, no attendance, and in the
future. These are the only sessions that automatic changes may delete. Regeneration
deletes only untouched sessions that were generated and never postponed
(`rules.regenerable`).

## How it works

Services: `backend/etqan/scheduling/services/`.

- **Attendance** (`attendance.py:mark_attendance`). Attendance opens once `starts_at`
  has passed (`has_started`). A student mark completes a scheduled session. A teacher
  mark never changes the status. Setting a mark back to `not_set` is an undo, and only
  the office may do it. A teacher may mark only while the `teacher_attendance` feature
  is on. The office always may. Marking is refused when the session is on an issued
  payslip (`paylock.refuse_if_paid`) or is a compensated original.
- **Cancel / restore** (`cancel_session`, `restore_session`). A session can be cancelled
  from scheduled, completed or at disposal. Attendance and reports are kept. Restore
  returns it to scheduled, or to completed when the student's attendance is set.
  Cancelling a live compensation frees its original.
- **Bulk** (`bulk_sessions`): `present`, `absent` or `cancel` on up to 200 ids. Rows are
  locked up front in id order. Each row reports its own result.
- **At disposal** (`place_at_disposal`, feature `disposal_status`). A scheduled session
  with no student mark becomes `at_disposal`. It never consumes a package session, is
  never paid and is never auto-deleted.
- **Hand-added sessions** (`manual.py`). Each one returns the teacher's overlapping
  sessions as warnings. Conflicts are never blocked.
  - `create_regular_session` (feature `manual_sessions`): on a live subscription,
    inside its generating window and outside its pauses.
  - `create_extra_session` (`extra_sessions`): optionally tied to a subscription. It
    never consumes.
  - `create_compensation` (`compensation_sessions`): a make-up for a compensable
    original (`rules.is_compensable`): cancelled, at disposal, or completed without
    consuming, and not `extra`. The original becomes `compensated` and frozen.
    `claim_session_for_balance` is the wallet's alternative to a make-up (B3e).
  - `delete_session` works only on an unmarked, unpaid, hand-added session that has no
    make-up. Deleting a compensation frees its original.
  - `set_pays_teacher` (feature `extra_sessions`) is allowed until a payslip locks the
    session.
- **In/out times** (`times.py:record_times`, feature `session_times`). A teacher sets
  only the teacher pair. Teacher attendance must be on for that, and a teacher may stamp
  "in" 15 minutes before the start. The office sets every time. Times are refused on
  paid or cancelled sessions. `actual_minutes` follows the teacher's in and out times
  until someone sets it.
- **Postponement** (`postpone.py:postpone_session`, feature `postponement`). Only an
  untouched-state session can be postponed: scheduled, no marks or times, not paid, and
  not a compensated original. A regular session also needs a live subscription, and its
  new date must stay inside the term and outside pauses. Students, parents and teachers
  can postpone only until `postpone_limit_minutes` before the start, to a time at least
  that far ahead and at most 14 days after the old start, and only when the teacher is
  free (409s `too_late_to_postpone`, `teacher_busy`). The office has no window and gets
  conflicts back as warnings. A slot session leaves its slot and records
  `original_slot`/`original_on`, so generation never recreates it there. Moving it back
  to that exact slot date and time reattaches it.
- **Supervision** (`supervision.py`, feature `supervision`). A session takes the
  subscription's supervisor when it is generated. `set_subscription_supervisor` updates
  the sessions that have not started yet. A supervisor can open a session from 10
  minutes before the start until it ends (`can_open`/`open_session` returns the
  meeting link), and then marks their own attendance.
- **Reports** (`reports.py`, feature `session_reports`). Only the session's teacher and
  the office read or write them. `missing_reports` lists attended sessions that ended
  more than 24 hours ago with no report.
- **Archives** (`archive.py`, B2d, features `session_archive` / `subscription_archive`).
  A session that is no longer due can be archived alone, or with its subscription.
  Nothing is deleted, and counts, invoices and payroll still include archived sessions.
  Lists hide archived rows by default (`archived=exclude|only|include`). While the
  archive is on, an archived session refuses edits until it is unarchived.
- **Activity log** (`activity.py`, `activity_feed.py`, `revert.py`, feature
  `activity_log`). Each writing service wraps its change in `activity.track(...)` right
  after taking its lock. Bulk `.update()`s use `record_many`. Nothing is logged by
  signals. `revert_activity` runs the inverse service as the person reverting, so every
  normal rule applies. A field that changed since the entry gives 409
  `scheduling.changed_since`. Reverts are possible for attendance, cancel, restore,
  disposal, pays_teacher, supervision, supervisor attendance, times, postpone, archive
  and unarchive.
- **Payroll lock** (`paylock.py`). Payroll reads and locks sessions only through
  `payroll_sessions`, `hold_sessions` and `lock_sessions`. Once a session is locked,
  every write path refuses it.

## API

All routes are under `/api/v1/`. `HasCode` means an office role holding the code.
"Own" means a teacher, student or parent scoped to their own rows (404 otherwise).

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/sessions/` | `session.view_any`; own rows | List (filters `when`, dates, `status`, `kind`, `student_attendance`, people, `subscription`, `q`, `archived`; CSV for office) |
| GET, PATCH, DELETE | `/api/v1/sessions/<id>/` | `session.view`; PATCH `session.update`/`attendance.update` + `supervision`; DELETE `session.delete` | Read / set supervisor or supervisor attendance / delete a hand-added session |
| POST | `/api/v1/sessions/<id>/attendance/` | `attendance.update` or the teacher | Mark attendance |
| POST | `/api/v1/sessions/<id>/cancel/`, `/restore/` | `session.update` | Cancel / restore |
| POST | `/api/v1/sessions/bulk/` | `session.update` | Bulk present, absent or cancel |
| POST | `/api/v1/sessions/regular/`, `/extra/`, `/compensation/` | `session.create` + the matching feature | Add by hand |
| POST | `/api/v1/sessions/<id>/disposal/` | `session.update`; `disposal_status` | Place at disposal |
| POST | `/api/v1/sessions/<id>/pays-teacher/` | `session.update`; `extra_sessions` | Toggle `pays_teacher` |
| POST | `/api/v1/sessions/<id>/times/` | `attendance.update` or teacher; `session_times` | In/out times |
| POST | `/api/v1/sessions/<id>/postpone/` | `session.update` or own; `postponement` | Postpone |
| GET | `/api/v1/sessions/<id>/activity/` | office `session.view`; `activity_log` | The session's log |
| POST | `/api/v1/sessions/<id>/activity/<entry_id>/revert/` | office `session.update`; `activity_log` | Revert one entry |
| POST | `/api/v1/sessions/archive/`, `/sessions/unarchive/` | office `session.delete` / `session.restore`; `session_archive` | Bulk archive / unarchive |
| GET, PUT | `/api/v1/sessions/<id>/report/` | `session_report.view` / `.update`, or the teacher; `session_reports` | Read / write report |
| GET | `/api/v1/reports/missing/` | `session_report.view_any` or teacher; `session_reports` | Missing reports |
| GET | `/api/v1/sessions/<id>/host-link/` | the session's teacher only | See [meetings.md](meetings.md) |
| GET | `/api/v1/supervision/` | `session.supervise`; `supervision` | My supervised sessions |
| GET | `/api/v1/supervision/supervisors/` | any of `subscription.create`/`.update`, `session.update`; `supervision` | Supervisor picker choices |
| POST | `/api/v1/supervision/<id>/open/`, `/attendance/` | `session.supervise`; `supervision` | Open / mark supervisor attendance |

## Dashboard

- Routes (`dashboard/src/routes/_authed/`): `scheduling.sessions.index.tsx`,
  `scheduling.sessions.simple.tsx` (the `simplified_sessions` view),
  `scheduling.sessions.archive.tsx`, `scheduling.sessions.$sessionId.tsx`,
  `scheduling.supervision.tsx`, `scheduling.reports.tsx`, `teaching.sessions.tsx` and
  `teaching.reports.tsx` (teacher), `learning.sessions.tsx` (student and parent).
- Components (`dashboard/src/features/scheduling/`): `SessionsList`, `SimpleSessions`,
  `SessionPage`, `SessionsPanel`, `AttendanceControls`, `CancelSessionDialog`,
  `DisposalDialog`, `AddSessionDialog`, `MakeUpDialog`, `SessionKindChip`, `TimesPanel`,
  `PostponeDialog`/`PostponeAction`/`postponing.ts`, `RevertDialog`/`activityFormat.ts`,
  `ArchiveActions`, `ReportDialog`/`ReportForm`, `MissingReports`, `MySupervision`,
  `SessionSupervision`, `TeacherSessions`, `FamilySessions`.

## Background jobs

There is no session-only job. Sessions are created and removed by `scheduling.run_daily`
([subscriptions.md](subscriptions.md)) and get links from `scheduling.provision_meetings`
([meetings.md](meetings.md)). Notifications calls `services.notices`
(`sessions_starting`, `sessions_running_late`, `absences_marked`, `reports_missing`) and
`notice_reads` from its own per-minute scan.

## Configuration

Feature switches (all off by default unless noted): `teacher_attendance` (on),
`session_reports` (on), `supervision`, `manual_sessions`, `extra_sessions`,
`compensation_sessions`, `disposal_status`, `session_times`, `postponement`,
`activity_log`, `session_archive`, `subscription_archive`, `simplified_sessions`.
Academy settings: `postpone_limit_minutes` (default 120), `absent_consumes_session`,
`excused_consumes_session`, `timezone`.

## Code map

- `backend/etqan/scheduling/services/attendance.py`, `manual.py`, `postpone.py`,
  `times.py`, `archive.py`, `activity.py`, `activity_feed.py`, `revert.py`,
  `reports.py`, `supervision.py`, `paylock.py`, `notices.py`, `notice_reads.py`
- `backend/etqan/scheduling/api/session_views.py`, `activity_views.py`,
  `archive_views.py`, `supervision_views.py`, `archived.py`, `payloads.py`

## Design history

- [Plan 5 sessions and attendance](../superpowers/specs/2026-09-25-sessions-attendance-design.md): attendance, cancel/restore, bulk, reports, the consumption rule. Base spec, amended to match the build.
- [B2a session classes](../superpowers/specs/2026-10-03-b2a-session-classes-design.md): kinds, compensation, extra, disposal, pays_teacher ([plan 17](../superpowers/plans/2026-10-03-plan-17-session-classes.md)).
- [B2b times and postponement](../superpowers/specs/2026-10-03-b2b-times-postponement-design.md): also re-lettered the later B2 slices ([plan 21](../superpowers/plans/2026-10-03-plan-21-times-postponement.md)).
- [B2c activity log](../superpowers/specs/2026-10-03-b2c-activity-log-design.md) ([plan 25](../superpowers/plans/2026-10-04-plan-25-activity-log.md)).
- [B2d archives and simplified view](../superpowers/specs/2026-10-03-b2d-archives-design.md) ([plan 31](../superpowers/plans/2026-10-05-plan-31-archives.md)).
- [Plan 12b supervision](../superpowers/plans/2026-09-29-plan-12b-supervision.md).
- [B3e student wallet](../superpowers/specs/2026-10-06-b3e-student-wallet-design.md): R3/R4, compensating with balance instead of a make-up.
