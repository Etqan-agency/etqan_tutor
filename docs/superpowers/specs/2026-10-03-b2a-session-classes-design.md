# Slice B2a — Session Classes — Design

**Date:** 2026-10-03
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); the review's findings are
applied below.
**Phase:** B2, slice a (`2026-10-03-b2-scheduling-depth-design.md` §3).
**Builds on:** Plan 4 (`etqan.scheduling`, generation, "untouched" sessions), Plan 5 (attendance, the one
consumption rule, cancel / restore, the session payload), Plan 7 (`payroll_sessions`, the payroll lock, P7-4), Plan
12a (permission codes), Plan 13 (feature switches).
**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §1.3 #4 and #18, §2.4 SCHED-003, §3 items 3, 6–7;
`docs/PHASE_1_SYSTEM_AUDIT.md` SCHED-003, SCHED-004 (the session's attribute names), SCHED-008, BR-02…04, §8.2,
§15 ("student absent … can spawn a compensation session").

## 1. Goal

The office can add sessions by hand: a regular session on a subscription, an **extra** session outside the
package, and a **compensation** (make-up) session for one that did not use up the package. Every session says
what **kind** it is and whether it **pays the teacher**. A session can be placed **at the administration's
disposal**. Payroll (B4) gets the session classes it needs; nothing about pay arithmetic changes here. In / out
times move to B2b (phase spec §3).

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| A-1 | `Session.kind`: `regular · compensation · extra`. Generated sessions are `regular`. (`trial` is added by B2d.) | TH §2.4 SCHED-003 tabs; P1 SCHED-008 |
| A-2 | The consumption rule (Plan 5 §4.2) gains two clauses: the kind is `regular` or `compensation`, and the session is not `compensated` (A-3). An extra session never uses up the package. (TutorHamster's subscription field "extra sessions outside the package, deducted next month" is Plan 4's grace overflow and carry-over, unrelated to SCHED-008's extra sessions.) | P1 SCHED-008 ("outside the package"); TH §3 item 3; phase B2-4 |
| A-3 | A **compensation** session replaces one **original** session that did not use up the package: the original is `cancelled` or `at_disposal`, or `completed` without consuming (the student excused or absent while the academy's switch says it doesn't count, or a teacher no-show). An original that is `scheduled`, consuming, of kind `extra`, or already compensated cannot be compensated. A compensation may itself be compensated when it qualifies. At most one live (non-cancelled) compensation per original. | P1 §8.2, §15 · [assumed] eligibility |
| A-4 | **The original is frozen while it has a live compensation.** A stored flag `compensated` is set on the original when a compensation is created or restored, and cleared when that compensation is cancelled or deleted. While it is set: the original takes no attendance change, restore, cancel or disposal (409 `scheduling.has_compensation`), and the consumption rule leaves it out, so flipping an academy switch never makes an original and its make-up both count. | review finding · [assumed] |
| A-5 | A compensation copies the original's student, course and subscription (any subscription status, so make-ups after the term are possible); the teacher, date, time and minutes are chosen, defaulting to the original's teacher and minutes. It consumes by the normal rule. Its date is free. | [assumed] |
| A-6 | A **regular** session added by hand needs a subscription that is `active` or `paused`, an active student, and a date inside the subscription's generating window (`starts_on` … last generating day, Plan 4 §4.1) and outside its pauses. Student and course come from it; the teacher defaults to it and may be any active teacher who teaches the course (Plan 4's teacher rule). | P1 BR-02, BR-04; spec Plan 4 §3.2 · [assumed] paused allowed, any course teacher |
| A-7 | An **extra** session names an active student, a course and an active teacher who teaches it; a subscription is optional and, when given, must be that student's. `pays_teacher` defaults to on and can be switched off. | P1 SCHED-008 (student, teacher, datetime, duration, link, paid to teacher) · [assumed] course |
| A-8 | `pays_teacher` (default on) exists on every session. `payroll_sessions` leaves out sessions with it off; nothing else about pay changes. | phase B2-5 |
| A-9 | **Which sessions the system deletes.** Regeneration (teacher change, `starts_on` edit, slot add / edit / deactivate, pause add / end / delete, and the old subscription's sessions dated on or after a renewal's start) deletes only **generated** untouched sessions. Ending a subscription (cancel, expiry — including the expiry a renewal triggers) deletes its untouched **regular** sessions, generated or hand-added. Untouched compensation and extra sessions are never deleted by the system: the office deletes or cancels them. | spec Plan 4 P4-7 · [assumed] |
| A-10 | A hand-added session may be deleted by the office while both attendances are `not_set`, its status is `scheduled` or `at_disposal`, it is not payroll-locked and nothing compensates it; a generated one may not (cancel it instead). | [assumed] |
| A-11 | **`at_disposal`**: the office places a `scheduled` session whose student attendance is `not_set` at the administration's disposal, with an optional reason. Its student attendance cannot be marked; its teacher attendance can. It never consumes, today's payroll rule does not pay it, and the system never deletes it. Restore returns it to `scheduled`; cancel is allowed from it. | TH §1.3 #4; phase B2-6 |
| A-12 | `created_by` (→ User, nullable) records who added a session by hand; generated sessions have none ("system"). | TH SCHED-003 "Created by" |
| A-13 | Each class is its own switch, off by default: `manual_sessions`, `extra_sessions`, `compensation_sessions`, `disposal_status`. A switch off hides its create action, its tab and its disposal action (404 on its routes). Records made while it was on keep their kind, status and counting, keep showing their label, and can still be cancelled, restored and deleted by the usual rules (FT-4). | spec Plan 13 FT-4; PO-5 |
| A-14 | Times follow P5-8: the office sees academy time plus the student's when it differs; everyone else sees their own timezone. A new session's date and time are sent as the academy's local date and wall-clock time. | spec Plan 5 P5-8; phase B2-15 |
| A-15 | A hand-added session dated in a month whose payslip is already issued is paid the way any late change is: as an adjustment on a later month (Plan 7 P7-4). Recorded for B4. | spec Plan 7 P7-4 |

## 3. Data (`etqan.scheduling`)

### 3.1 Session (existing) — new columns

All nullable or with a database default (phase B2-16).

| Field | Notes |
|---|---|
| `kind` | `regular · compensation · extra`, `db_default` `regular` |
| `compensates` | → Session, nullable, `on_delete=PROTECT`, `related_name="compensations"`. Set only on `compensation`. |
| `compensated` | bool, `db_default` false (A-4) |
| `pays_teacher` | bool, `db_default` true |
| `created_by` | → User, nullable, SET_NULL |
| `disposal_reason` | text, `db_default` "" |

`status` gains `at_disposal`; its column widens from 10 to 12 characters (a length increase; no data changes).

Constraints:
- `UNIQUE(compensates)` where `compensates` is not null and `status` ≠ `cancelled` (one live compensation);
- `kind = compensation` ⇔ `compensates` is not null.

## 4. Behaviour

### 4.1 Adding a session (office)

`create_session(kind, by, …)`. Times: `occurs_on` (academy date), `start_time` (academy wall-clock), `minutes`
(15–240); `starts_at` uses Plan 4's single conversion. A start in the past is allowed (recording a session that
happened). `meeting_url` optional: else the teacher's default. `notes` optional.

| Kind | Required | Rules |
|---|---|---|
| `regular` | `subscription`, `occurs_on`, `start_time` | A-6. Subscription not `active` / `paused`: 409 `scheduling.not_allowed_in_status`. Student inactive: 400 on `subscription`. A date outside the window or inside a pause: 400 on `occurs_on`. `teacher` optional (A-6; 400 on `teacher`). `minutes` defaults to the subscription's `session_minutes`. |
| `extra` | `student`, `course`, `teacher`, `occurs_on`, `start_time`, `minutes` | A-7; 400 on the failing field. `subscription` optional, the student's (400). `pays_teacher` optional, default true. |
| `compensation` | `compensates`, `occurs_on`, `start_time` | The original is locked; it must qualify (A-3; else 409 `scheduling.not_compensable`, or `scheduling.already_compensated` when it has a live one). Student, course and subscription from it; `teacher` (an active teacher who teaches the course) and `minutes` default to it. Sets the original's `compensated`. |

The kind's switch must be on, else 404 (checked after the permission, before validation, as Plan 13 does; each kind has its own route, so each route
declares one feature). The new
session is `scheduled`, `generated = false`, `created_by = by`, `pays_teacher` as given (default true), with the
subscription's supervisor when it has one (Plan 12b). The answer includes `conflicts`: the teacher's other
non-cancelled sessions that overlap it (reported, never blocked, P4-9).

### 4.2 Deleting a hand-added session (office)

A-10. Refusals, checked in this order: `payroll.payslip_issued`; `scheduling.session_generated`;
`scheduling.has_compensation` (it is `compensated`); `scheduling.session_marked` (an attendance is set);
`scheduling.not_allowed_in_status` (`completed` or `cancelled`). Deleting a compensation clears its original's
`compensated`.

### 4.3 Consumption (the one rule, extended)

`rules.consuming` adds `kind__in=(regular, compensation)` and `compensated=False` (positive lookups, as the rule
requires). Every derived value (used, remaining, extra, carried-over, progress) follows. Sessions with no
subscription never counted and still don't.

### 4.4 System deletions (A-9)

`untouched_sessions` keeps its meaning. The regenerating callers add `generated=True`; cancel and expiry
(`rules.expire`) add `kind=regular`.

### 4.5 At the administration's disposal (A-11)

- `place_at_disposal(session, by, reason="")`: from `scheduled` with student attendance `not_set`; refused on a
  payroll-locked (`payroll.payslip_issued`) or compensated (`scheduling.has_compensation`) session; any other
  status is 409 `scheduling.not_allowed_in_status`.
- `mark_attendance` on `at_disposal`: a student attendance is 409 `scheduling.not_allowed_in_status`; a teacher
  attendance is allowed (start gate and lock unchanged).
- `restore_session` also accepts `at_disposal` → `scheduled`, clearing `disposal_reason`.
- `cancel_session` also accepts `at_disposal`; `disposal_reason` is kept for the record, and a later restore goes
  to `scheduled` (Plan 5's restore rule), not back to `at_disposal`.
- Bulk: unchanged actions; `present` / `absent` on an `at_disposal` session are skipped with
  `scheduling.not_allowed_in_status`.
- Reports: unchanged (only `completed` sessions take one); `at_disposal` never appears on Missing reports.
- `delete_subscription` treats `at_disposal` like a marked session: it refuses with `scheduling.has_marked_sessions`.
  Every compensation's original is cancelled, `at_disposal` or completed, so a subscription with a compensation
  is always refused too (no PROTECT error).
- The Today board shows `at_disposal` as its own state.

### 4.6 Compensation lifecycle (A-4)

- Cancelling a compensation clears the original's `compensated`.
- Restoring a cancelled compensation first re-checks that the original still qualifies and has no other live
  compensation (409 `scheduling.not_compensable` / `scheduling.already_compensated`), then sets `compensated` again.
- Attendance, restore, cancel and disposal on a `compensated` original: 409 `scheduling.has_compensation`
  (bulk skips with that code).

### 4.7 `pays_teacher`

Set on create and changed by the office through `POST sessions/<id>/pays-teacher/` while the session is not
payroll-locked (409 `payroll.payslip_issued`). `PATCH sessions/<id>/` stays supervision's (its feature is `supervision`). `payroll_sessions` filters `pays_teacher=True`.

## 5. Access

| | Office (code) | Teacher | Student / parent |
|---|---|---|---|
| Add a session (any kind) | `session.create` | | |
| Delete a hand-added session | `session.delete` | | |
| Place at disposal | `session.update` | | |
| Change `pays_teacher` (`extra_sessions` on) | `session.update` | | |
| Read kind and compensation links | ✓ | ✓ (own) | ✓ (own) |

`session.create` is already in the resource's `in_use`; `delete` is added (phase §4).

Payload additions: everyone in scope sees `kind`, `compensates_id` and `compensation_id` (the live one). The office
alone sees `pays_teacher`, `compensated`, `created_by {id, full_name} | null` and `disposal_reason`.

## 6. API (`/api/v1/`)

| Route | Method | Notes |
|---|---|---|
| `sessions/regular/` | POST | `{subscription, occurs_on, start_time, teacher?, minutes?, meeting_url?, pays_teacher?, notes?}`. Feature `manual_sessions`. `201` with `{session, conflicts}`. People by User id, as elsewhere. |
| `sessions/extra/` | POST | `{student, course, teacher, occurs_on, start_time, minutes, subscription?, meeting_url?, pays_teacher?, notes?}`. Feature `extra_sessions`. Same answer. |
| `sessions/compensation/` | POST | `{compensates, occurs_on, start_time, teacher?, minutes?, meeting_url?, pays_teacher?, notes?}`. Feature `compensation_sessions`. Same answer. |
| `sessions/` | GET | New filter `kind` (`regular · compensation · extra`); `status` accepts `at_disposal`. CSV adds a Kind column. |
| `sessions/<id>/pays-teacher/` | POST | `{pays_teacher}` (`session.update`). Feature `extra_sessions`. Returns the session. |
| `sessions/<id>/` | DELETE | §4.2. `204`. No feature check (A-13). |
| `sessions/<id>/disposal/` | POST | `{reason?}`. Feature `disposal_status`. |
| `sessions/<id>/restore/` | POST | Also from `at_disposal`; compensation rules of §4.6. |
| `schedule/today/` | GET | Row state gains `at_disposal`. |

409 bodies are `{detail, code}`. New codes: `scheduling.not_compensable`, `scheduling.already_compensated`,
`scheduling.has_compensation`, `scheduling.session_generated`, `scheduling.session_marked`.

## 7. Dashboard (`/app/`)

- **Status everywhere:** `at_disposal` gets a label and badge wherever a session status is shown — sessions list
  and filter, session page, Today board, subscription Sessions panel, teacher My sessions, student / parent
  sessions and home, CSV — and the kind gets a badge ("Make-up", "Extra"; regular shows none).
- **Sessions list (office):** tabs All · Core (regular) · Compensation · Extra; All and Core always show, the other
  two with their feature. An **Add session** button opens a dialog that picks the kind (switched-on kinds only)
  and then §4.1's fields, and shows any teacher conflicts in the result.
- **Session page (office):** the kind, links to the original or the compensation, `created_by`, a `pays_teacher`
  toggle; **Add make-up session** on an eligible session (pre-filled dialog, hidden otherwise); **Place at the
  administration's disposal** (reason dialog) with Restore; **Delete** on a deletable hand-added session.
- Every string in en and ar, in a new area file `sessionClasses.json`; RTL, phone width, semantic tokens; 409 codes
  translated.

## 8. Seeds

In `demo`, under the B2 marker: turn on the four switches, then add one compensation for the seeded excused session
(cycle position 5) and one extra session with `pays_teacher` off. Idempotent (skip when any hand-added session
exists); `other` gets nothing.

## 9. Testing

- **Rules:** each kind's create rules and errors; compensation eligibility over every status × attendance × switch
  combination, chains, and the frozen original (attendance, restore, cancel, disposal, a switch flip); restoring a
  cancelled compensation; one live compensation (service and database); the consumption rule with each kind and
  `compensated`; A-9 for every regenerating caller, cancel, expiry and renewal; delete rules and order;
  `at_disposal` transitions, attendance refusal, bulk skip, `delete_subscription` refusal, Today board state;
  `payroll_sessions` without `pays_teacher=false`.
- **Switches:** every gated route 404s with its feature off, after the permission check; records made while on keep
  counting, showing and restoring when off.
- **Access:** the role × route matrix (anonymous, student, parent, teacher, staff without and with each code,
  admin); another academy's sessions are never reachable (`until_pk_exceeds`).
- **Existing suites** (billing, payroll, notifications) pass unchanged.
- **Dashboard:** each dialog, tab, badge and action, with error and not-found states.
- **e2e** (`e2e/b2-session-classes.spec.ts`, through Caddy): with the switches on, the admin adds a make-up for a
  past excused session (the original then shows its make-up and refuses a new one) and an extra session, and places
  a session at the administration's disposal and restores it.
- Coverage gates as today.

## 10. Out of scope

In / out times, postponement and the activity log (B2b); archives (B2c); trials (B2d); groups and bundles (B2e);
weekly schedules and substitute teachers in bulk (B2f); paying these classes (B4); notices about them (B5).
