# Slice B2c — Session Activity Log — Design

**Date:** 2026-10-03
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); its 21 findings are applied below.
**Phase:** B2, slice c (`2026-10-03-b2-scheduling-depth-design.md` §3, as amended by B2b: B2c = the activity log).
**Builds on:** B2a (`2026-10-03-b2a-session-classes-design.md`: disposal, `pays_teacher`, make-ups, lock order),
B2b (`2026-10-03-b2b-times-postponement-design.md`: `record_times`, `postpone_session`, teacher change and renewal
moves), Plan 5 (attendance, cancel, restore, bulk), Plan 7 (payroll lock), Plan 12a/b (codes, supervision),
Plan 13 (switches, FT-4).
**Evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` §4.7 SCHED-004, SYS-008, §19 (open question on other entities);
`docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` SCHED-004 (page exists, no rows captured), §5.1 / §5.5 (NOT ADDRESSED).

## 1. Goal

The office opens a session and sees every change people and the system made to it: who, what, when, and each
field's value before and after. One entry can be **reverted**: its fields go back to their earlier values, through
the same rules that govern the change itself, unless something changed them since.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| C-1 | The log covers **sessions only**. A subscription log is not built. | P1 SYS-008 (confirmed for sessions only; other entities UNKNOWN); phase B2-9 as amended by B2b |
| C-2 | An entry holds the session, the actor (null = the system), an action, the time, and the changed fields as `{field: [before, after]}`. Only fields whose value actually changed are stored; a call that changes nothing writes no entry. | P1 SCHED-004 (actor · action · timestamp · field / before / now) |
| C-3 | **Creation is not a stored entry.** The log's first line is built from the session row itself (`created_at`, `created_by`, `kind`, `generated`): generation bulk-creates rows and must not write one log row each. | P1 SCHED-004 ("إنشاء" entries) · [assumed] derived line |
| C-4 | Entries are written by the scheduling **services** that change a session (§4.1), inside the same transaction, after the row is saved; never by model signals. Writes through no service (admin site, shell, migrations) are not logged. | phase B2-9 ("every change a service makes") |
| C-5 | **Revert runs the inverse service** with the entry's before-values, as the person reverting, so every rule (payslip lock, frozen original, status rules, the postponement window) applies exactly as for a fresh change. The codes and switches the forward route checks are checked again for the revert (§4.2). Field values are never written back directly. | [assumed]: a raw write would bypass consumption, compensation and payroll rules |
| C-6 | **Revert conflict:** an entry is revertible only while every field it changed still holds its after-value; otherwise 409 `scheduling.changed_since`. Then the inverse service's own refusals apply. | phase B2-9; P1 SCHED-004 ("أسترجاع") · [assumed] rule |
| C-7 | A revert is itself an entry (the inverse's action) that points at the entry it reverted. A revert can be reverted by the same rule. | [assumed] |
| C-8 | Some actions have no inverse and show no revert button: the subscription-wide changes (B2b's teacher change and renewal moves, a subscription's supervisor change). | [assumed]: their inverse is a subscription change, not a session change |
| C-9 | Not logged: creation (C-3), deletion (the row and its entries go together, `CASCADE`), the original's `compensated` flag (its make-up is already linked on the page, B2a), the supervisor's opening stamp, report writes (reports are their own record, Plan 5), the payroll lock (shown on the session), and `marked_by` / `marked_at` / `cancelled_by` / `cancelled_at` / `updated_at` (the entry's own actor and time say the same). | [assumed] scope |
| C-10 | Office only: reading needs `session.view` and the session in the viewer's scope; reverting needs `session.update` plus the codes of the forward route (§4.1). Teachers, students and parents never see the log (404). A logged field whose own switch is off (supervision, times, postponement, `pays_teacher`) is hidden from the read and its entry is not revertible (FT-4). | TH SCHED-004 is an `/admin` page; Plan 12a codes |
| C-11 | Switch `activity_log`, off by default. Entries are written only while it is on; off, the routes 404 and nothing is written. Turning it back on shows the entries written earlier (FT-4). | PO-5; spec Plan 13 FT-4 |
| C-12 | Entries are kept with their session; no pruning. The read returns the newest 200. | [assumed]; per-academy tables are small |

## 3. Data

### 3.1 `SessionActivity` (new, `etqan.scheduling`)

| Field | Notes |
|---|---|
| `session` | → Session, `CASCADE`, `related_name="activity"` |
| `actor` | → User, nullable, `SET_NULL` (null = the system, or a deleted user: the payload says "System" only when `actor_kind` is `system`) |
| `actor_kind` | `user` \| `system` |
| `action` | one of §4.1's actions, max 24 |
| `changes` | JSON `{field: [before, after]}`; values JSON-safe (§3.2) |
| `reverts` | → self, nullable, `SET_NULL`, `related_name="reverted_by"` |
| `created_at` | auto, UTC |

Index `(session, created_at)`. One new table; no change to existing rows (phase B2-16).

Field → switch that must be on to show it: `supervisor_id`, `supervisor_attendance` → `supervision`; the four in / out
times and `actual_minutes` → `session_times`; `occurs_on`, `starts_at` (postponement) → `postponement`; `pays_teacher` →
`extra_sessions` (the only route that sets it, B2a). An entry with no visible field is left out of the read.

### 3.2 Logged fields and their JSON form

`status`, `student_attendance`, `teacher_attendance`, `supervisor_attendance`, `cancel_reason`, `disposal_reason`:
strings. `pays_teacher`: bool. `supervisor`, `teacher`, `subscription`: the id or null (stored as `supervisor_id`,
`teacher_id`, `subscription_id`). `occurs_on`: ISO date. `starts_at`, `teacher_in_at`, `teacher_out_at`,
`student_in_at`, `student_out_at`: ISO UTC instants or null. `actual_minutes`: int or null.

The set is one tuple, `LOGGED_FIELDS`, in `services/activity.py`; a field no service changes is not in it.

## 4. Behaviour

### 4.1 What is logged

`services/activity.py` offers two writers; both do nothing while `activity_log` is off, and `by=None` writes
`actor_kind=system`:

- `track(session, by, action)`: a context manager a service enters **immediately after it locks the row** (before
  `refuse_if_paid` and its other refusals). It snapshots `LOGGED_FIELDS` and, on a clean exit after the save, writes
  one entry with the fields that differ (none differ → no entry). On an exception nothing is written (the
  transaction rolls back). Used by every single-session service, and by `bulk_sessions` through the services it
  calls (one entry per done session, none for a skipped one).
- `record_many(rows, by, action)`: one `bulk_create` for services that change many rows with `.update()`; each row is
  `(session_id, changes)`, computed from the values read under the service's own lock.

| Action | Service | Inverse on revert | Revert also needs (code · switch) |
|---|---|---|---|
| `attendance` | `mark_attendance` (also via bulk) | `mark_attendance` with **only** the attendance fields present in `changes`, at their before-values; `status` is derived and never passed. A teacher-only entry on an `at_disposal` session passes only `teacher_attendance` (B2a A-11). Clearing to `not_set` is the office undo (Plan 5 D7). | `attendance.update`; `teacher_attendance` switch not needed (the reverter is office) |
| `cancel` | `cancel_session` (also via bulk) | before-status `scheduled` / `completed` → `restore_session`; before-status `at_disposal` → `restore_session(to_disposal=True)`, a new keyword that returns it to `at_disposal` keeping `disposal_reason` (which the cancel kept) | — · `disposal_status` when before-status is `at_disposal` |
| `restore` | `restore_session` | before-status `cancelled` → `cancel_session(reason=before cancel_reason, disposal_reason=before disposal_reason)` (new optional keyword, set only when given); before-status `at_disposal` → `place_at_disposal(reason=before disposal_reason)` | — · `disposal_status` when the entry changed `disposal_reason` or before-status is `at_disposal` |
| `disposal` | `place_at_disposal` | `restore_session` | — · `disposal_status` |
| `pays_teacher` | `set_pays_teacher` | `set_pays_teacher(before)` | — · `extra_sessions` |
| `supervision` | `update_session_supervision` (the session PATCH) | `update_session_supervision` with the before `supervisor_id` and / or `supervisor_attendance`, only those in `changes` (a reassignment's reset of the attendance is in the same entry) | the field codes the PATCH checks for those fields · `supervision` |
| `supervisor_attendance` | `mark_supervisor_attendance` (the supervisor) | `update_session_supervision(supervisor_attendance=before)` | that field's PATCH code · `supervision` |
| `times` | B2b `record_times` | `record_times` with the before-values of exactly the fields in `changes`; an `actual_minutes` key sent as null counts as sent, so it is not recomputed (B2b B-3) | `attendance.update` · `session_times` |
| `postpone` | B2b `postpone_session` | `postpone_session(..., starts_at=before starts_at)`, a new internal keyword that takes the exact instant (no local-time round trip, so an ambiguous DST hour is kept); office rules (any time); B2b's move-back rule re-attaches the slot | `session.update` · `postponement` |
| `teacher_moved` | B2b teacher change, via `record_many` | none (C-8) | |
| `renewal_moved` | B2b renewal move, via `record_many` | none (C-8) | |
| `subscription_supervisor` | `set_subscription_supervisor` (its `.update()` on unstarted sessions), via `record_many` | none (C-8) | |

**Additive signatures** (CLAUDE.md, orchestration §6.2.5): `restore_session`, `place_at_disposal`, `set_pays_teacher`,
`update_subscription` and `renew_subscription` gain an optional `by=None`, and their views pass `request.user`;
`restore_session` gains `to_disposal=False`; `cancel_session` gains `disposal_reason=None`; `postpone_session` gains
`starts_at=None` (when given, `occurs_on` and `start_time` are derived from it). Callers that pass nothing behave as
today and write system entries.

Restoring a supervisor reassignment does not bring back `opened_by_supervisor_at` (not logged, C-9).

### 4.2 Revert

`revert_activity(entry, by)`:

1. Refusals before any lock, in order: the action has no inverse → 409 `scheduling.not_revertible`; the entry's
   switch(es) (§4.1, and C-10's field switches) off → 409 `scheduling.not_revertible`; `by` lacks the codes in §4.1 →
   403.
2. Run the inverse as `by` inside `activity.reverting(entry)`. That context sets a contextvar, which the inverse's own
   `track` reads right after the inverse locks the row (in the lock order that service already uses, B2a / Plan 4):
   if any field in `entry.changes` no longer holds its after-value → 409 `scheduling.changed_since`, before the
   inverse's other refusals. `revert_activity` takes no lock of its own, so the lock order is the forward service's,
   and two concurrent reverts of one entry serialise on that lock: the second sees `changed_since`.
3. The inverse's other refusals propagate unchanged: `payroll.payslip_issued`, `scheduling.has_compensation`, status
   rules (`scheduling.not_allowed_in_status`, `scheduling.session_cancelled`, `scheduling.not_started` — e.g. an
   early "I'm in" reverted before the start), B2b's postponement refusals (a postponement cannot be reverted once its
   earlier start is in the past or outside the window), and a 400 on `supervisor_id` when the earlier supervisor is no
   longer one.
4. The entry `track` writes gets `reverts = entry`. Because step 2 confirmed every field still held its after-value
   and the inverse sets them to the before-values, the inverse always changes something, so that entry exists.
   Answer `{session, entry}`.

### 4.3 Reading

`session_activity(session, viewer)`: the newest 200 visible entries, newest first, with `truncated: true` when older ones
exist, then the derived creation line (C-3) ("Created by System" when `created_by` is null and `generated` is false,
such as seeded rows). Each entry's
payload: `id`, `action`, `actor` (`{id, name}` or null), `actor_kind`, `created_at`, `changes` as a list
`[{field, before, after}]` with ids resolved to display names (supervisor, teacher → name; subscription → its code;
a deleted record shows its id), `reverts` (id or null), `reverted_by` (ids), and `can_revert`. `can_revert` is
true when step 1 of §4.2 would pass for the viewer and every field still holds its after-value; the inverse service's other rules are checked only when the revert is sent. Names are
resolved with one query per related model for the whole page.

## 5. Access

| | Office | Teacher / student / parent |
|---|---|---|
| Read the log | `session.view`, session in scope | 404 |
| Revert | `session.update` (+ the inverse's codes) | 404 |

Mechanism: the views first raise 404 for a viewer who is not office (`is_office`, as the report views do), then check
`HasCode` (403 for an office user lacking `session.view`; revert's extra codes per §4.2), then `FeatureOn(activity_log)`
(404). Out-of-scope sessions are 404. The access `RESOURCES` line for `session` already carries `view` and `update`;
no new resource or verb.

## 6. API (`/api/v1/`)

| Route | Method | Notes |
|---|---|---|
| `sessions/<id>/activity/` | GET | §4.3. Feature `activity_log`. `{results: [...], truncated, created: {at, by, kind, generated}}`. |
| `sessions/<id>/activity/<entry_id>/revert/` | POST | §4.2. Feature `activity_log`. `200 {session, entry}`. An entry of another session is 404. |

The switch is checked after the permission (§5), before anything else, as Plan 13 does. New 409 codes:
`scheduling.changed_since`, `scheduling.not_revertible`.

## 7. Dashboard (`/app/`)

- **Session page (office):** an **Activity** section (with `activity_log` on and `session.view`): newest first; each
  entry shows the actor (or "System"), the action's label, the time in academy time, and a field / before / after
  table with translated field names and translated values (statuses, attendance, yes / no, dates and times in academy
  time plus the student's when it differs, B2-15). "Reverted" / "Reverts an earlier change" badges; "Earlier changes are not shown" when `truncated`. A **Revert**
  button on entries with `can_revert` opens a confirm dialog; after success the session and the log reload; 409 codes
  and the inverse's codes are translated.
- The creation line: "Created by {name}" / "Created by System" / "Generated from the weekly timetable" with the time.
- Strings in en and ar in a new area file `sessionActivity.json`; RTL, phone width (the table stacks), semantic tokens.

## 8. Seeds

In `demo`, under the B2 marker, with `activity_log` among `features.BUILT`: one past session with an attendance entry by the
demo admin, and a cancel by the demo admin that the same admin reverted through `revert_activity`. Idempotent (skipped when the session already has entries); `other`
gets nothing.

## 9. Testing

- **Tracking:** each §4.1 service writes exactly one entry with exactly the changed fields; a no-op writes none; bulk
  writes one per done session and none for skipped ones; switch off writes none; `by=None` is system; a refused
  change writes nothing (the transaction rolls back).
- **Revert:** each action's inverse round-trips the fields; `not_revertible` for B2b moves; `changed_since` when any
  field moved on (including after a later revert); inverse refusals propagate (payslip issued, `has_compensation`,
  a restore whose re-cancel is now impossible, a former supervisor, a past postponement origin, an early stamp before
  the start); missing codes 403 and switches off 409 `not_revertible`; cancel-from-disposal and restore-of-it round
  trips keep `disposal_reason`; a teacher-only attendance entry on an `at_disposal` session; `actual_minutes` cleared
  by a revert stays null; a DST-ambiguous postponement round trip; `record_many` for the three subscription-wide
  actions; the new
  entry points at the reverted one; revert of a revert; two concurrent reverts (one wins); lock order (SQL capture).
- **Reading:** order, the 200 cap, the creation line for generated and hand-added sessions, name resolution with a
  deleted user, `can_revert` per case, fields of switched-off features hidden, `truncated`, query count bounded.
- **Access:** office codes; teacher, student, parent 404; out of scope 404; other academy 404; switch off 404 on both
  routes after the permission check.
- **Existing suites** pass unchanged.
- **Dashboard:** the section, the table's value formatting, the badges, the revert dialog and its error states.
- **e2e** (`e2e/b2-activity.spec.ts`, spec-owned data): the admin marks attendance on a started session, sees the
  entry, reverts it, and sees the attendance back to not set with a revert entry.

## 10. Known limits (accepted)

- Changes made outside the services (Django admin, shell) are not logged.
- Deleting a session deletes its log.
- A revert restores only logged fields; side stamps (`marked_at`, the supervisor's opening) keep their new values.
- The system's automatic deletions (regeneration, pauses, renewal overlap, cancel, expiry: Plan 4 "untouched"
  sessions) delete future, scheduled, unmarked sessions with their entries, even when they were cancelled and restored,
  had `pays_teacher` changed or a supervisor reassigned. "Untouched" (P4-7) is not widened.
- Entries are written only while the switch is on: a change made while it was off and undone (A → B → A) is invisible,
  and an earlier entry still passes the `changed_since` check.
- Reverting a postponed hand-added session leaves `postponed_at` and `original_starts_at` set (B2b moves a hand-added
  session back without clearing them), so its page still says "Postponed from …".

## 11. Out of scope

A subscription or academy-wide audit log; exports of the log; notices about reverts (B5); archives (B2d); trials
(B2e); bundles (B2f); weekly schedules (B2g).
