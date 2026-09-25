# Plan 5 — Sessions, Attendance & Reports — Design

**Date:** 2026-09-25
**Status:** Approved in brainstorming (sections 1–3), pending written-spec review.
**Phase:** B0, milestone 5 of the parity roadmap (`2026-09-24-parity-roadmap-design.md`).
**Builds on:** v1 spec §4.6, §5.2, §5.6, §6 (`2026-09-23-etqan-tutor-v1-design.md`); Plan 4 (`2026-09-24-subscriptions-scheduling-design.md`), which covers `etqan.scheduling`, generation, "untouched" sessions, derived `sessions_used`, carry-over and extras; Plan 3 (people, role permissions, `scope_for`, CSV).
**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §2.4 (SCHED-003, SCHED-016) and §3 item 6; `docs/PHASE_1_SYSTEM_AUDIT.md` SCHED-009 (report scales) and BR-32 (reports are staff notes). Roadmap rule R4 applies.

## 1. Goal

**Teachers** see their sessions with the join link, mark student and teacher attendance on their own sessions, and write a report for each completed session.

**Admins** can:
- see and filter every session, and export it to CSV;
- mark attendance or cancel sessions in bulk;
- cancel or restore a session;
- see which completed sessions still lack a report.

**Students and parents** see:
- their upcoming sessions, with the join link;
- their attendance history;
- each subscription's progress.

Marking attendance makes Plan 4's `sessions_used`, extras and carry-over real.

## 2. Decisions

| # | Decision |
|---|---|
| P5-1 | Everything lives in `etqan.scheduling`, in new service modules (attendance, reports). `sessions_used` and the subscription rules stay in one app (Plan 4 P4-1). |
| P5-2 | **Session reports are staff-only.** The session's teacher and admins write and read them. Students and parents never see them (TutorHamster BR-32). There is no sharing switch. |
| P5-3 | Marking the student's attendance completes a scheduled session (v1 §5.2). Status values stay `scheduled · completed · cancelled`. Attendance values are TutorHamster's: `not_set · present · absent · excused`. |
| P5-4 | **A teacher no-show never counts against the package.** A session where the teacher is marked absent does not use up a session. |
| P5-5 | Attendance can be marked only once the session's start time has passed. An absence announced in advance is a cancellation with a reason. |
| P5-6 | Only admins cancel, restore and bulk-edit. Teachers mark attendance and write reports on their own sessions only. Postponing is phase B2. |
| P5-7 | Report scales are TutorHamster's 5-point behaviour and participation scales (excellent, good, average, below average, poor), plus notes. |
| P5-8 | Non-admin screens show times in the viewer's own timezone (`User.timezone`). Admin screens show academy time, plus the student's time when it differs. |

## 3. Data

### 3.1 AcademySettings (existing)

New fields:
- `absent_consumes_session`, bool, default `true`;
- `excused_consumes_session`, bool, default `false`.

### 3.2 Session (existing, `etqan.scheduling`)

New fields:
- `marked_by` (nullable → User) and `marked_at` (nullable UTC). They record the last attendance change.
- `cancelled_by` (nullable → User) and `cancelled_at` (nullable UTC).

`cancel_reason` already exists. Status and attendance values are unchanged.

### 3.3 SessionReport (new)

| Field | Notes |
|---|---|
| `session` | one-to-one → Session |
| `behaviour` | 1–5 (5 = excellent … 1 = poor) |
| `participation` | 1–5 |
| `notes` | text, optional |
| `written_by` | → User |
| `created_at`, `updated_at` | |

## 4. Behaviour

### 4.1 Attendance

- **Who:** the session's teacher, or an admin.
- **When:** only once `starts_at` ≤ now. Otherwise 409 `scheduling.not_started`.
- **A cancelled session** can't be marked (409 `scheduling.session_cancelled`).
- **Student attendance:**
  - Setting it to `present`, `absent` or `excused` on a `scheduled` session makes it `completed`.
  - Changing it between those values keeps the session `completed`.
  - Setting it back to `not_set` is admin-only and returns the session to `scheduled`.
- **Teacher attendance** is set independently and never changes the status.
- Every change records `marked_by` and `marked_at`.
- A marked or cancelled session is not "untouched" (Plan 4 P4-7), so generation and lifecycle never delete or recreate it.

### 4.2 What counts as used (the one rule)

A session uses up one of its subscription's sessions when all of these hold:
- `status = completed`;
- `teacher_attendance ≠ absent`;
- `student_attendance` is:
  - `present`; or
  - `absent`, and `absent_consumes_session` is on; or
  - `excused`, and `excused_consumes_session` is on.

This replaces Plan 4's placeholder rule inside the single derived-values service (Plan 4 §3.2). Remaining, extra and carried-over sessions follow from it. The switches are read live, so changing a switch changes every subscription's numbers.

### 4.3 Cancel and restore (admin)

- **Cancel:**
  - `{reason}` is required.
  - Allowed from `scheduled`, or from `completed`, which stops the session counting.
  - Sets `cancelled_by` and `cancelled_at`.
  - Attendance is kept as it was, for the record. A report, if any, is kept.
- **Restore:**
  - Allowed only from `cancelled`.
  - The session returns to `scheduled` and its cancel fields are cleared.
  - If its student attendance is set, it returns to `completed` instead.
- A transition from any other status returns 409 `scheduling.not_allowed_in_status`.

### 4.4 Bulk (admin)

`{ids, action, reason?}`:
- `action` is `present`, `absent` or `cancel`;
- `ids` holds at most 200;
- `reason` is required for `cancel`.

Each session is handled on its own with the rules above. Sessions that fail a rule are skipped with their code. The response is `{done: [ids], skipped: [{id, code}]}`. Ids outside the admin's academy are not found and are reported as skipped with code `not_found`.

### 4.5 Reports

- **Writing:**
  - Only on a `completed` session; otherwise 409 `scheduling.not_completed`.
  - The session's teacher or an admin writes it, with PUT to create or replace.
  - The first writer is kept in `written_by`, and edits update `updated_at`.
- **Reading:** the session's teacher and admins. Anyone else gets 404.
- **Missing reports:**
  - completed sessions whose `starts_at + minutes` ended more than 24 hours ago, with no report and not cancelled;
  - admins see all of them, teachers see their own.

### 4.6 Access

| | Admin | Teacher | Student | Parent |
|---|---|---|---|---|
| Read sessions | all | sessions they teach | own | their children's |
| Mark attendance | ✓ | their own sessions | | |
| Cancel, restore, bulk, CSV | ✓ | | | |
| Read and write reports | ✓ | their own sessions | | |
| Missing reports | all | their own | | |

- One permission class per role plus `scope_for`, as before. Out-of-scope objects return 404.
- Session payloads:
  - everyone in scope sees the times (UTC, plus the academy's local date), minutes, meeting link, status, both attendances, and the course, teacher and student names;
  - `notes` and `cancel_reason` are admin-only;
  - `has_report` is shown to admins and to the session's teacher only.

## 5. API (`/api/v1/`, existing conventions)

| Route | Methods | Notes |
|---|---|---|
| `sessions/` | GET | Filters: `from`, `to` (academy-local dates), `status`, `student_attendance`, `teacher`, `student`, `course`, `subscription`, `q` (student name). Paginated. `?format=csv` is admin-only. Ordered by `starts_at`. |
| `sessions/<id>/` | GET | Scoped. |
| `sessions/<id>/attendance/` | POST | `{student_attendance?, teacher_attendance?}`, at least one. Returns the session. |
| `sessions/<id>/cancel/` | POST | `{reason}`. Returns the session. |
| `sessions/<id>/restore/` | POST | Returns the session. |
| `sessions/bulk/` | POST | See §4.4. |
| `sessions/<id>/report/` | GET, PUT | PUT `{behaviour, participation, notes?}`. |
| `reports/missing/` | GET | Paginated session rows. |
| `academy/settings/` | GET, PATCH | Adds the two switches. |

- 409 bodies are `{detail, code}` (Plan 4).
- The new codes are `scheduling.not_started`, `scheduling.session_cancelled` and `scheduling.not_completed`, plus the existing `scheduling.not_allowed_in_status`.
- Field problems return 400.
- The student's and parent's subscription progress uses Plan 4's scoped `subscriptions/` read endpoints.

## 6. Dashboard (`/app/`)

**Admin** (Scheduling group):
- **Sessions:**
  - filters, search, the shared Pager and CSV export;
  - row checkboxes with a bulk bar (present, absent, cancel with a reason, and a result summary of done and skipped);
  - academy time, plus the student's time when it differs.
- **Session page:**
  - details and the join link;
  - student and teacher attendance controls;
  - cancel (reason dialog) and restore;
  - the report form (two 5-choice scales and notes).
- **Missing reports:** a list linking to each session page.

**Teacher:**
- **My sessions:** Today / This week / History tabs. Each row has Join, the attendance controls (disabled until the start time) and "Write report" or "Edit report".
- **Reports to write:** their own missing reports.
- **Home:** today's sessions.

**Student and parent:**
- **My sessions:** upcoming sessions with Join, and past sessions with attendance.
- **My subscriptions:** each subscription's used/total, extras, end date and a grace notice.
- **Home:** the next session with Join, plus progress.
- **Parents** with several children get a child filter.

**Settings → Academy:** the two "counts as used" switches.

**Throughout:**
- every string is in Arabic and English;
- right-to-left and phone width;
- semantic colour tokens only;
- not-found and error states;
- 409 codes shown translated;
- the shared helpers reused;
- non-admin times in the viewer's own timezone.

## 7. Seeds

In the demo academy, past generated sessions are marked:
- a mix of present, absent and excused;
- one teacher no-show;
- reports written on most completed sessions, with one completed session older than 24 hours left without a report.

Running seeding twice changes nothing.

## 8. Testing

- **Backend:**
  - the "counts as used" rule for every attendance combination, both switches and a teacher no-show;
  - every transition, and the start-time gate;
  - admin-only undo;
  - cancel and restore round trips;
  - bulk results, including skipped reasons and other-academy ids;
  - report rules and the missing-reports window;
  - the role × route matrix, including anonymous;
  - cross-academy isolation with data in both academies;
  - Plan 4's carry-over and extras driven by real marks.
- **Dashboard:** each page, control and dialog, with error, not-found and validation states.
- **E2E through Caddy:**
  1. The admin sees today's session.
  2. The teacher (invited, sets a password) signs in, marks the student present and writes a report.
  3. The admin sees the report, and the session is gone from Missing reports.
  4. The student signs in and sees 1 session used.
- **Coverage gates as today.**

## 9. Risks

- **Wrong counts.** A counting mistake silently changes what families pay for. Mitigation: one rule in one service, and a test matrix over every combination.
- **Teachers marking the wrong session.** Mitigation: scoping, the start-time gate, and `marked_by`/`marked_at` recorded on every change.
- **Timezone display.** Mitigation: times come from the server's `starts_at`, formatted in the viewer's timezone. There is no client-side recomputation (Plan 4 M1).

## 10. Out of scope (roadmap phase)

- Payroll locks on issued payslips: Plan 7.
- Reminders and notifications: Plan 8.
- Make-up, extra and trial sessions, postponing, session in/out times, and "at the administration's disposal": B2.
- Session reviews by students, homework: B6.
- Report-based payroll deductions: B4.
