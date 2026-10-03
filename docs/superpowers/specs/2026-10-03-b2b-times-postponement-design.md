# Slice B2b — In / Out Times and Postponement — Design

**Date:** 2026-10-03
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); the review's findings are
applied below (it also split the activity log into its own slice, B2c).
**Phase:** B2, slice b (`2026-10-03-b2-scheduling-depth-design.md` §3).
**Builds on:** B2a (`2026-10-03-b2a-session-classes-design.md`: kinds, hand-added sessions, `at_disposal`, the
frozen original, pk-ordered session locks, A-9 system deletions), Plan 4 (generation, "untouched" sessions, the Today
board, lock order subscriptions → sessions), Plan 5 (attendance, the start gate), Plan 7 (payroll lock, P7-4),
Plan 12a/b (codes, supervision), Plan 13 (switches).
**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §1.3 #11, §2.4 SCHED-003 (teacher / student in and out,
actual duration), SCHED-015; `docs/PHASE_1_SYSTEM_AUDIT.md` SCHED-003, BR-13, §15.

## 1. Goal

Teachers record when they came in and left; the office records both sides' times and the minutes actually taught.
A session can be **postponed** to a new time — by its student, a parent or its teacher until a set time before it
starts, by the office at any time — and the weekly timetable never recreates it at the old time.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| B-1 | In / out times are recorded by people (no room stamps them): the teacher's "I'm in" / "I'm out" or a typed time for the teacher's pair; the office for all four and the actual minutes. | TH SCHED-003; phase B2-7 |
| B-2 | Times are recorded on `scheduled`, `completed` and `at_disposal` sessions once the Plan 5 start gate has passed, except that the teacher may stamp "I'm in" from 15 minutes before the start. | [assumed] 15 min |
| B-3 | `actual_minutes` is computed from the teacher's in / out only while it is empty; a value the office typed is never overwritten. A span over 600 minutes is refused. `actual_minutes` is a record only: pay and consumption stay on `minutes`. | [assumed] |
| B-4 | **Postponement moves the session.** On the first move of a slot session the row is detached from its slot and remembers the slot and slot date it came from (`original_slot`, `original_on`); generation treats that slot date as taken. `original_starts_at` keeps the first start across moves. Moving a session back to exactly its original slot date and start time re-attaches it and clears the postponement. (This refines phase B2-8, amended.) | phase B2-8 · [assumed] mechanism |
| B-5 | A **postponed** session is one with `postponed_at` set. Regeneration (teacher change, `starts_on` edit, slot edit, pause add / end / delete) never deletes it — deleting it would free the slot date and bring the old time back. Ending a subscription (cancel, expiry) deletes it like any other untouched regular session (A-9): nothing regenerates afterwards. A renewal deletes, with its generated overlap, the old subscription's untouched postponed sessions whose **original slot date** is on or after the renewal's start (the renewal regenerates that date itself), and moves the other postponed, unmarked sessions dated on or after the renewal's start onto the renewal (the lesson stays in the period it now falls in; its teacher and course are kept). (Amended during the build, Plan 21 ruling P15.) A pause added later does not remove a postponed session inside it. | review · spec B2a A-9 · [assumed] |
| B-6 | **Who.** The office (`session.update`) at any time. The session's teacher, its student, and an active parent of its student only while `now ≤ starts_at − postpone_limit_minutes`, and only to a new start at least `postpone_limit_minutes` from now and at most 14 days after the session's current start. | TH SCHED-015 · [assumed] parents act for children, the 14-day cap, the lead time |
| B-7 | **What.** Only a `scheduled` session with no attendance, no times recorded, no supervisor attendance, not payroll-locked and not compensated. A regular session's new date must lie inside its subscription's generating window (`starts_on` … last generating day, incl. a live renewal's cap) and outside its pauses, and the subscription must be `active` or `paused`. Compensation and extra sessions have no window (their dates were free when added, B2a A-5/A-7). | review · spec Plan 4 §4.1 |
| B-8 | **Clashes.** The office's postponement reports the teacher's overlapping sessions (P4-9: reported, never blocked). A student's, parent's or teacher's postponement onto a time that overlaps another non-cancelled session of the same teacher is refused (409 `scheduling.teacher_busy`), and no other session is ever shown to them. | review; spec Plan 4 P4-9 |
| B-9 | A postponed session keeps its teacher, minutes, link and supervisor. A subscription teacher change also moves its postponed, unmarked, future sessions to the new teacher (the generated ones are regenerated with it already). | review · [assumed] |
| B-10 | Payroll follows `occurs_on`: a session moved into another month is paid in that month; moved into a month whose payslip is already issued, it is paid as a later adjustment (Plan 7 P7-4; ledger D9). | spec Plan 7 P7-4 |
| B-11 | `AcademySettings.postpone_limit_minutes`, 0–10080, default 120, edited in Settings → Academy. Added under a one-commit `claim` on `etqan.academy`. | TH §1.3 #11; phase B2-17 · [assumed] default |
| B-12 | Switches, off by default: `session_times`, `postponement`. **Deploy note:** `postponement` stays off for an academy until the previous release is drained, because that release's generation does not know the skip rule. | PO-5; review |
| B-13 | Reminders are deduplicated per session (Plan 8), so a session moved after its reminder went out gets none at the new time. Accepted; notices are B5's. | spec Plan 8 · ledger |

## 3. Data

### 3.1 Session (existing) — new columns (nullable or `db_default`)

| Field | Notes |
|---|---|
| `teacher_in_at`, `teacher_out_at`, `student_in_at`, `student_out_at` | datetime (UTC), nullable |
| `actual_minutes` | small int, nullable, 1–600 |
| `original_slot` | → ScheduleSlot, nullable, PROTECT, `related_name="postponed_sessions"` |
| `original_on` | date, nullable |
| `original_starts_at` | datetime, nullable |
| `postponed_by` | → User, nullable, SET_NULL |
| `postponed_at` | datetime, nullable |

Constraints: each in / out pair `out ≥ in` when both are set; `original_slot` and `original_on` both set or both null;
`UNIQUE(original_slot, original_on)` where `original_slot` is not null. (Per-academy session tables are small; plain
constraint and index creation is accepted.)

### 3.2 AcademySettings (existing, `etqan.academy`)

`postpone_limit_minutes`, `db_default` 120, validators 0–10080.

## 4. Behaviour

### 4.1 In / out times

`record_times(session, by, fields)`: any of the four instants (or null to clear) and `actual_minutes`.

- The session's teacher sets or clears only the teacher pair (anything else 403) and needs `teacher_attendance` on
  (Plan 13 §5.3); the office (`attendance.update`) sets everything.
- Refusals, in order: `payroll.payslip_issued`; `cancelled` → 409 `scheduling.session_cancelled`; before the start
  gate → 409 `scheduling.not_started` (except B-2's early stamp); out before in → 400 on the out field; a teacher span
  over 600 minutes → 400 on `teacher_out_at`.
- After the change, when both teacher times are set and `actual_minutes` is empty and not sent, it becomes the
  rounded minutes between them (at least 1).
- Times never change status, attendance or consumption.

### 4.2 Postponement

`postpone_session(session, by, occurs_on, start_time)`; the date and time are the academy's (Plan 4's conversion).

1. Lock the subscription (when the session has one), then the session — read the session's `subscription_id`
   unlocked first, as `create_compensation` does.
2. Refusals, in order: `payroll.payslip_issued`; `scheduling.has_compensation`; not postponable under B-7 → 409
   `scheduling.not_allowed_in_status`; subscription not `active` / `paused` (regular) → 409
   `scheduling.not_allowed_in_status`; new start not in the future → 400 on `occurs_on`; outside the window or in a
   pause (regular) → 400 on `occurs_on`; for a non-office caller: too late (`now > starts_at − limit`) → 409
   `scheduling.too_late_to_postpone`, lead time or 14-day cap broken → 400 on `occurs_on`, teacher busy → 409
   `scheduling.teacher_busy`.
3. For a session with an `original_slot` only: if the new date and time are exactly `original_on` and the slot's
   current `start_time` (after a slot edit, "back" means the new time) and the slot is active and has no session on
   that date, re-attach `slot` and clear `original_slot`, `original_on`, `original_starts_at`, `postponed_by`,
   `postponed_at`. A hand-added session moved back to its first start stays postponed.
4. Otherwise: on a session with a slot, set `original_slot = slot`, `original_on = occurs_on`, `slot = null`; on the
   first move set `original_starts_at = starts_at`; set `occurs_on`, `starts_at`, `postponed_by = by`,
   `postponed_at = now`.
5. Answer `{session, conflicts}`; `conflicts` is filled for the office only.

**Generation** reads a second set alongside its existing `(slot, occurs_on)` one:
`Session.objects.filter(original_slot__in=slots, original_on__range=(first, last))`, and skips those slot dates
(counted as `skipped_existing`).

**System deletions:** the regenerating callers add `postponed_at__isnull=True` to their untouched filter; cancel and
expiry don't (B-5).

**Slots:** `delete_slot` and the slot payload's `has_sessions` also count `postponed_sessions`.

**Teacher change (B-9):** `update_subscription(teacher)` also sets the new teacher on the subscription's postponed,
unmarked, future sessions, locking them after the subscription, in pk order.

**Renewal (B-5):** `renew_subscription` deletes the old subscription's untouched postponed sessions whose `original_on`
is on or after the new `starts_on` with the generated overlap, then moves its other postponed, unmarked sessions dated
on or after the new `starts_on` onto the renewal (both subscriptions are already locked; the sessions are locked after
them, in pk order). Moving a session back re-attaches it only to a slot of its current subscription.

**Today board:** a slot whose session moved away shows the state `postponed` (linking the session); a postponed
session now dated today (no slot) is listed as its own row with its status's state. A board row's `slot` becomes
optional: such rows take their start, minutes and subscription from the session (payload and dashboard type change
with it).

### 4.3 Switches

`session_times` gates the times route and fields; `postponement` gates the postpone route, the setting's field and
`can_postpone`. Data recorded while a switch was on keeps showing (FT-4).

## 5. Access

| | Office (code) | Teacher | Student | Parent |
|---|---|---|---|---|
| Record times | `attendance.update` | own sessions, teacher pair | | |
| Postpone | `session.update` | own sessions (B-6) | own (B-6) | children's (B-6) |

Out-of-scope sessions are 404. Payload additions: with `session_times` on, everyone in scope sees the four times and
`actual_minutes`; with `postponement` on, `original_starts_at`, `postponed_at` and `can_postpone`; the office alone sees
`postponed_by`. `can_postpone` is computed from the row's own and `select_related` data only: the viewer's role and
scope, the time limit (non-office), status `scheduled`, no attendance, no times, no supervisor attendance, not
payroll-locked, not compensated, and the subscription `active` / `paused` (regular). The window, pauses and the
teacher's clashes are checked only when the postponement is sent.

## 6. API (`/api/v1/`)

| Route | Method | Notes |
|---|---|---|
| `sessions/<id>/times/` | POST | §4.1. Feature `session_times`. Code `attendance.update`, or the session's teacher. Returns the session. |
| `sessions/<id>/postpone/` | POST | `{occurs_on, start_time}`. Feature `postponement`. Office by `session.update`; teacher, student, parent in scope. `200 {session, conflicts}`. |
| `academy/settings/` | GET, PATCH | Adds `postpone_limit_minutes`. |
| `schedule/today/` | GET | Row state gains `postponed`; postponed sessions dated today get rows. |

New 409 codes: `scheduling.too_late_to_postpone`, `scheduling.teacher_busy`.

## 7. Dashboard (`/app/`)

- **Session page (office):** a Times panel (four time inputs, a "now" button each, actual minutes); **Postpone** (date
  and time dialog showing the student's time when it differs, then any conflicts); "Postponed from …" when
  `original_starts_at` is set.
- **Teacher, My sessions:** "I'm in" / "I'm out"; **Postpone** while `can_postpone`.
- **Student and parent, My sessions:** **Postpone** while `can_postpone`; when the limit has passed, a line says so.
- **Today board:** the `postponed` state and rows for sessions postponed into today.
- **Settings → Academy:** the postponement limit (with `postponement` on).
- Every string in en and ar, in a new area file `sessionTimes.json`; RTL, phone width, semantic tokens; 409 codes
  translated.

## 8. Seeds

In `demo`, under the B2 marker: one postponed upcoming session and one session with teacher times; the switches come
on with `features.BUILT`. Idempotent; `other` gets nothing.

## 9. Testing

- **Times:** roles, the early stamp boundary, statuses, ordering, the 600-minute bound, auto actual minutes only while
  empty, switches.
- **Postponement:** every refusal in order; each non-office role at the limit boundary, lead time and cap; teacher
  busy; the window, pauses and a renewal's cap; the slot date stays skipped by the daily job, a range run and
  regeneration after a slot edit; a postponed generated or hand-added session survives regeneration and is removed by
  cancel and expiry; moving back re-attaches; repeated moves keep the first origin; teacher change moves postponed
  sessions; `delete_slot` and `has_sessions`; `delete_subscription` with postponed rows; lock order (SQL capture);
  the Today board (moved away, moved into today); DST conversion; a move across a month boundary.
- **Access:** the role × route matrix; non-office callers never see conflicts; cross-academy isolation.
- **Existing suites** pass unchanged.
- **Dashboard:** each panel, dialog and button with error states.
- **e2e** (`e2e/b2-postpone.spec.ts`, spec-owned data): the student postpones a session before the limit; the admin
  sees it as postponed on the session page; the teacher stamps in and out on a started session.

## 10. Known limits (accepted)

- `teacher_busy` is checked under the session's own subscription lock, not a teacher lock: two students moving onto
  the same free time at the same instant can both succeed (the office sees the clash on the sessions list).
- A student's own overlapping sessions are not checked.
- For compensation and extra sessions (no window) the 14-day cap counts from the current start, so repeated moves can
  push them further.

- A renewal deletes a postponed lesson whose original slot date it regenerates (B-5); if that slot was deactivated
  after the postponement, the renewal does not copy it and the date is not recreated (narrow: a grace-period lesson, a
  deactivated slot, then a renewal).
- A lesson postponed from a date on or after the renewal's start that is already marked (or was moved to a past time
  and left unmarked) is kept, and the renewal also generates that date (as B2a does for marked generated sessions).

## 11. Out of scope

The activity log and revert (B2c); archives (B2d); trials and availability (B2e); bundles and groups (B2f); weekly
schedules (B2g); notices about postponements (B5).
