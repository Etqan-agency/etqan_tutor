# Slice B2a — Session Classes — Design

**Date:** 2026-10-03
**Status:** Self-approved after an independent spec review (orchestration spec PO-3).
**Phase:** B2, slice a (`2026-10-03-b2-scheduling-depth-design.md` §3).
**Builds on:** Plan 4 (`etqan.scheduling`, generation, "untouched" sessions), Plan 5 (attendance, the one
consumption rule, cancel / restore, the session payload), Plan 7 (`payroll_sessions`, the payroll lock), Plan 12a
(permission codes), Plan 13 (feature switches).
**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §1.3 #4 and #18, §2.4 SCHED-003, §3 items 6–7;
`docs/PHASE_1_SYSTEM_AUDIT.md` SCHED-003, SCHED-004 (the session's attribute names), SCHED-008, §8.2, §15
("student absent … can spawn a compensation session").

## 1. Goal

The office can add sessions by hand: a regular session on a subscription, an **extra** session outside the
package, and a **compensation** (make-up) session for one that did not use up the package. Every session says
what **kind** it is and whether it **pays the teacher**. A session can be placed **at the administration's
disposal**. Teachers and the office record **in / out times** and the **actual minutes** taught. Payroll (B4)
gets the session classes it needs; nothing about pay arithmetic changes here.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| A-1 | `Session.kind`: `regular · compensation · extra`. Generated sessions are `regular`. (`trial` is added by B2d.) | TH §2.4 SCHED-003 tabs; P1 SCHED-008 |
| A-2 | The consumption rule (Plan 5 §4.2) gains one clause: the kind is `regular` or `compensation`. An extra session never uses up the package. | TH §2.4 SCHED-008 ("outside the package"); phase B2-4 |
| A-3 | A **compensation** session replaces one **original** session of the same subscription that did not use up the package: the original is `cancelled` or `at_disposal`, or `completed` without consuming (an excused or absent student while the academy's switch says it doesn't count, or a teacher no-show). An original that is `scheduled`, consuming, or of kind `extra` cannot be compensated. At most one non-cancelled compensation per original. | P1 §8.2, §15 · [assumed] eligibility |
| A-4 | A compensation copies the original's student, course and subscription (any subscription status); the teacher, date, time and minutes are chosen, defaulting to the original's teacher and minutes. It then consumes by the normal rule. | [assumed] |
| A-5 | A **regular** session added by hand needs a subscription that is `active` or `paused`; the student and course come from it, the teacher defaults to it. | P1 BR-02, BR-03, BR-04 |
| A-6 | An **extra** session names a student (active), a course and a teacher (active); a subscription is optional and, when given, must be that student's. `pays_teacher` defaults to on and can be switched off. | P1 SCHED-008 |
| A-7 | `pays_teacher` (default on) exists on every session. `payroll_sessions` leaves out sessions with it off; nothing else about pay changes. | phase B2-5 |
| A-8 | Hand-added sessions (`generated = false`) are the office's: regeneration (teacher change, `starts_on` edit, slot add / edit / deactivate, pause add / end / delete, renewal overlap) deletes only **generated** untouched sessions. Ending a subscription (cancel, expiry) deletes every untouched session, hand-added ones included. | spec Plan 4 P4-7 · [assumed] |
| A-9 | A hand-added session may be deleted by the office while it has no attendance, is not cancelled and not on an issued payslip; a generated one may not (cancel it instead). | [assumed] |
| A-10 | **`at_disposal`**: the office places a `scheduled` session whose student attendance is `not_set` at the administration's disposal, with an optional reason. Its student attendance cannot be marked; its teacher attendance can. It never consumes and today's payroll rule does not pay it. Restore returns it to `scheduled`. | TH §1.3 #4; phase B2-6 |
| A-11 | **In / out times:** `teacher_in_at`, `teacher_out_at`, `student_in_at`, `student_out_at` (UTC) and `actual_minutes`. The session's teacher records the teacher's pair (an "I'm in" / "I'm out" stamp, or a typed time); the office records all four and the actual minutes. When both teacher times are set and `actual_minutes` is not sent, it is computed from them. | TH SCHED-003 ("time the teacher actually spent"); phase B2-7 |
| A-12 | `created_by` (→ User, nullable) records who added a session by hand; generated sessions have none ("system"). | TH SCHED-003 "Created by" |
| A-13 | Each class is its own switch, off by default: `manual_sessions`, `extra_sessions`, `compensation_sessions`, `session_times`, `disposal_status`. A switch off hides its routes (404), actions and fields; data already recorded is kept and keeps counting (FT-4). | spec Plan 13 FT-4; PO-5 |
| A-14 | Times follow P5-8: the office sees academy time plus the student's when it differs; everyone else sees their own timezone. Dates and times sent for a new session are the academy's local date and wall-clock time. | spec Plan 5 P5-8; phase B2-15 |

## 3. Data (`etqan.scheduling`)

### 3.1 Session (existing) — new columns

All nullable or with a database default (phase B2-16).

| Field | Notes |
|---|---|
| `kind` | `regular · compensation · extra`, `db_default` `regular` |
| `compensates` | → Session, nullable, `on_delete=PROTECT`, `related_name="compensations"`. Set only on `compensation`. |
| `pays_teacher` | bool, `db_default` true |
| `created_by` | → User, nullable, SET_NULL |
| `disposal_reason` | text, `db_default` "" |
| `teacher_in_at`, `teacher_out_at`, `student_in_at`, `student_out_at` | datetime (UTC), nullable |
| `actual_minutes` | small int, nullable, 1–600 |

`status` gains `at_disposal`; its column widens from 10 to 12 characters (a length increase; no data changes).

Constraints:
- `UNIQUE(compensates)` where `compensates` is not null and `status` ≠ `cancelled` (one live compensation).
- `kind = compensation` ⇔ `compensates` is not null.
- each in / out pair: `out ≥ in` when both are set.

## 4. Behaviour

### 4.1 Adding a session (office)

`create_session(kind, by, …)`. Times: `occurs_on` (academy date), `start_time` (academy wall-clock), `minutes`
(15–240); `starts_at` uses Plan 4's single conversion. A start in the past is allowed (recording a session that
happened). `meeting_url` optional: else the teacher's default. `notes` optional.

| Kind | Required | Rules |
|---|---|---|
| `regular` | `subscription` | Subscription `active` or `paused` (else 409 `scheduling.not_allowed_in_status`). Student and course from it; `teacher` defaults to it, must be active; `minutes` defaults to the subscription's `session_minutes`. |
| `extra` | `student`, `course`, `teacher` | Student and teacher active (400 on the field otherwise). `subscription` optional and must be the student's (400). `pays_teacher` optional, default true. |
| `compensation` | `compensates` | The original must qualify (A-3; else 409 `scheduling.not_compensable`) and have no live compensation (409 `scheduling.already_compensated`). Student, course and subscription from it; `teacher` and `minutes` default to it. The original is locked while this is checked. |

The kind's switch must be on, else 404 (the route answers it before validation, as Plan 13 does). The new
session is `scheduled`, `generated = false`, `created_by = by`, with the subscription's supervisor when it has
one (Plan 12b).

The answer includes `conflicts`: other non-cancelled sessions of the same teacher that overlap (reported, never
blocked, P4-9).

### 4.2 Deleting a hand-added session (office)

Allowed when `generated = false`, both attendances are `not_set`, the status is `scheduled` or `at_disposal`, and
it is not payroll-locked. Otherwise 409: `scheduling.session_generated`, `scheduling.session_marked`, or
`payroll.payslip_issued`. A session that has a compensation pointing at it cannot be deleted
(`scheduling.has_compensation`). Its report (if any) cascades.

### 4.3 Consumption (the one rule, extended)

`rules.consuming` adds `kind__in=(regular, compensation)`. Every derived value (used, remaining, extra,
carried-over, progress) follows. Sessions with no subscription never counted and still don't.

### 4.4 Regeneration and removal (A-8)

`untouched_sessions` keeps its meaning. The regenerating callers add `generated=True`; cancel and expiry don't.

### 4.5 At the administration's disposal

- `place_at_disposal(session, by, reason="")`: from `scheduled` with student attendance `not_set` and not
  payroll-locked; else 409 `scheduling.not_allowed_in_status` (or `payroll.payslip_issued`).
- `mark_attendance` on an `at_disposal` session: a student attendance is 409 `scheduling.not_allowed_in_status`; a
  teacher attendance is allowed (start gate and lock rules unchanged).
- `restore_session` also accepts `at_disposal` → `scheduled`, clearing `disposal_reason`.
- `cancel_session` also accepts `at_disposal`.
- Bulk: unchanged actions; a `present` / `absent` on an `at_disposal` session is skipped with
  `scheduling.not_allowed_in_status`.
- Untouched (P4-7) requires `scheduled`, so the system never deletes an `at_disposal` session.

### 4.6 In / out times

`record_times(session, by, fields)` with any of `teacher_in_at`, `teacher_out_at`, `student_in_at`, `student_out_at`
(a datetime or null to clear) and `actual_minutes`.

- The session's teacher may set or clear only the teacher pair; the office (holding `attendance.update`) may set
  everything. A teacher sending a student field or `actual_minutes` gets 403.
- Refused on a `cancelled` session (409 `scheduling.session_cancelled`), before the start (409
  `scheduling.not_started`, the Plan 5 gate) and on a payroll-locked session (409 `payroll.payslip_issued`).
- A pair whose out is before its in is a 400 on the out field.
- When both teacher times are set after the change and `actual_minutes` was not sent, it becomes the rounded
  minutes between them (at least 1).
- A teacher's writes also need `teacher_attendance` on (as marking does, Plan 13 §5.3).

### 4.7 `pays_teacher`

Set on create (extra, compensation and regular) and changed by the office through `PATCH sessions/<id>/` while
the session is not payroll-locked. `payroll_sessions` filters `pays_teacher=True`.

## 5. Access

| | Office (code) | Teacher | Student / parent |
|---|---|---|---|
| Add a session (any kind) | `session.create` | | |
| Delete a hand-added session | `session.delete` | | |
| Place at disposal | `session.update` | | |
| Change `pays_teacher` | `session.update` | | |
| Record times | `attendance.update` | own sessions, teacher pair | |
| Read kind, compensation links | ✓ | ✓ (own) | ✓ (own) |

The `session` resource's `in_use` gains `create` and `delete` (phase §4).

Payload additions: everyone in scope sees `kind`, `compensates_id`, `compensation_id` (the live one) and, when
`session_times` is on, the four times and `actual_minutes`. The office alone sees `pays_teacher`, `created_by
{id, full_name} | null` and `disposal_reason`. A switched-off feature's fields are left out of the payload.

## 6. API (`/api/v1/`)

| Route | Method | Notes |
|---|---|---|
| `sessions/` | POST | `{kind, subscription?, compensates?, student?, course?, teacher?, occurs_on, start_time, minutes?, meeting_url?, pays_teacher?, notes?}`. Feature per kind. `201` with `{session, conflicts}`. People by User id, as elsewhere. |
| `sessions/` | GET | New filter `kind` (`regular · compensation · extra`); `status` accepts `at_disposal`. CSV adds Kind and Actual minutes columns (the latter only with `session_times` on). |
| `sessions/<id>/` | PATCH | Adds `pays_teacher` (`session.update`); supervision fields unchanged. |
| `sessions/<id>/` | DELETE | §4.2. `204`. Feature: `manual_sessions`, `extra_sessions` or `compensation_sessions`, as the session's kind. |
| `sessions/<id>/disposal/` | POST | `{reason?}`. Feature `disposal_status`. |
| `sessions/<id>/times/` | POST | §4.6. Feature `session_times`. |
| `sessions/<id>/restore/` | POST | Also from `at_disposal`. |

409 bodies are `{detail, code}`. New codes: `scheduling.not_compensable`, `scheduling.already_compensated`,
`scheduling.session_generated`, `scheduling.session_marked`, `scheduling.has_compensation`.

## 7. Dashboard (`/app/`)

- **Sessions list (office):** a kind badge on each row; tabs All · Core (regular) · Compensation · Extra (each tab
  shown with its feature); an **Add session** button opening a dialog that picks the kind (only switched-on kinds)
  and then the fields of §4.1, showing any teacher conflicts in the result; the status filter offers
  `at_disposal` when `disposal_status` is on.
- **Session page (office):**
  - the kind, the original or the compensation as links, `created_by`, `pays_teacher` (a toggle);
  - **Add make-up session** on an eligible session (pre-filled dialog); hidden when not eligible;
  - **Place at the administration's disposal** (reason dialog) and Restore;
  - **Delete** on a hand-added, unmarked session (confirmation);
  - a **Times** panel: four time inputs with a "now" button each, and actual minutes.
- **Teacher, My sessions:** "I'm in" / "I'm out" buttons on started sessions (with `session_times`), the kind badge.
- **Student and parent:** the kind label ("Make-up", "Extra") on their sessions.
- Every string in en and ar (a new area file `sessions-classes.json`), RTL, phone width, semantic tokens, 409 codes
  translated.

## 8. Seeds

In `demo`, turn on the five switches (under the B2 marker), then: one compensation for the seeded excused
session (cycle position 5), one extra session with `pays_teacher` off, one session with teacher in / out times.
Idempotent (skip when any hand-added session exists); `other` gets nothing.

## 9. Testing

- **Rules:** each kind's create rules and errors; compensation eligibility over every status × attendance × switch
  combination; one live compensation (service and database); the consumption rule with each kind; A-8 for every
  regenerating caller and for cancel / expiry; delete rules; `at_disposal` transitions and attendance refusal;
  times permissions, ordering, auto actual minutes; `payroll_sessions` without `pays_teacher=false`.
- **Switches:** every new route 404s with its feature off, after the permission check; payload fields hidden;
  data recorded while on keeps counting when off.
- **Access:** the role × route matrix (anonymous, student, parent, teacher, staff without and with each code,
  admin); another academy's sessions are never reachable (`until_pk_exceeds`).
- **Existing suites** (billing, payroll, notifications) pass unchanged.
- **Dashboard:** each dialog, panel and button, with error and not-found states.
- **e2e** (`e2e/b2-session-classes.spec.ts`, through Caddy): with the switches on, the admin adds a make-up for a
  past excused session and an extra session; the teacher stamps "I'm in" and "I'm out" on a started session; the
  admin sees the actual minutes.
- Coverage gates as today.

## 10. Out of scope

Postponement and the activity log (B2b); archives (B2c); trials (B2d); groups and bundles (B2e); weekly schedules
(B2f); paying these classes (B4); notices about them (B5).
