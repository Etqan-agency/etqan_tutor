# Slice B2g — Weekly Schedules — Design

**Date:** 2026-10-03
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); its 22 findings are applied below
(the substitution became a record that generation reads; "delete and move" was dropped).
**Phase:** B2, slice g (`2026-10-03-b2-scheduling-depth-design.md` §3, as amended by B2b: B2g = weekly schedules).
**Builds on:** Plan 4 (slots, generation, "untouched" sessions, regenerating callers, renewal, the Today board), Plan 7
(payroll pays `session.teacher`), Plan 13 (switches), B2a (lock order), B2b (postponed sessions, teacher-change moves),
B2c (activity log), B2d (archives: the same live-subscription filter in generation), B2e (availability warnings), B2f
(bundles, current members, `member_id` errors).
**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §2.4 SCHED-001 (list, tabs, actions, forms);
`docs/PHASE_1_SYSTEM_AUDIT.md` SCHED-001, SCHED-004 (`substitute teacher` on a session), §5.2 (`weekly::schedule`
resource), BR-01, BR-44, §19 (BR-44's move target: HIGH gap, UNKNOWN).

## 1. Goal

The office manages weekly timetables on their own screen: every subscription's (or bundle's) timetable in one list with
TutorHamster's tabs; stop and restart a timetable; put it away and restore it; give a period of lessons to a substitute
teacher; change the teacher of many timetables at once; download all timetables; see them on an expanded week grid.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| G-1 | **A weekly schedule is a subscription's slot set**, not a new table: our slots already belong to a subscription with one course and one teacher (TH puts a course and teacher on each timing line). A bundle shows as one schedule row with its current members' lines (a group bundle's identical lines collapse to one per time). The state lives on `Subscription.schedule_status`. Refines phase B2-14, amended. | TH SCHED-001; P1 SCHED-001; phase B2-14 · [assumed] |
| G-2 | **Status** `active` (default) / `stopped` / `deleted` (TH tabs active · stopped · deleted). A stopped or deleted schedule generates nothing; stopping removes its untouched future generated sessions; activating regenerates the horizon when the subscription is live. | TH SCHED-001 ("when stopped, no new sessions are created from this schedule") · [assumed] removal of already-generated sessions |
| G-3 | **Delete is soft** (the "deleted" tab; restore → `active`). Permanent delete is not built (slots with sessions are PROTECTed; Plan 4's slot delete already removes a slot without sessions). A deleted schedule's slots cannot be added or edited (409 `scheduling.schedule_deleted`). | TH SCHED-001 · [assumed] |
| G-4 | Stop, activate, delete and restore work on any subscription status; generation happens only for a live subscription (BR-01 is about creating a schedule: "Add" picks a live subscription without slots and opens its slot editor). | P1 BR-01; review |
| G-5 | **Substitute teacher** is a record: subscription, substitute teacher, from date, to date (required, at most 366 days). Generation gives sessions dated in the range the substitute as `teacher` and the subscription's teacher as `substitute_for`. Substituted sessions stay ordinary "untouched" rows, so every regenerating caller (pause, term or slot edits, teacher change, renewal) recreates them correctly. Adding or removing a substitution deletes the untouched generated sessions in its range and regenerates them. Ranges of one subscription never overlap. Payroll pays the session's teacher. | P1 SCHED-004 (`substitute teacher`); phase §3 B2g · [assumed] mechanism; review |
| G-6 | A substitution applies to **generated** sessions only; a postponed or hand-added session in the range keeps its teacher (change it on its own). A renewal copies the substitution ranges overlapping its term. | review · [assumed] |
| G-7 | **Bulk change** = set the teacher of several schedules at once through `update_subscription(teacher)` per subscription, all or nothing. Substitutions stay (they replace whoever is the regular teacher). B2b's teacher-change move of postponed sessions sets the new teacher on a postponed session only when it has no `substitute_for`, else it sets `substitute_for`. Bulk change of times is not built (times differ per schedule; edited per slot, Plan 4). | TH SCHED-001 "تغيير جماعي" (fields UNKNOWN) · [assumed] teacher only |
| G-8 | **"Delete and move sessions" is not built**: its target is UNKNOWN (P1 §19 HIGH). Moving lessons to another teacher is the teacher change (G-7) or a substitution (G-5). | P1 BR-44, §19 · [assumed] |
| G-9 | **Renewal** copies `stopped`; a renewal of a `deleted` schedule starts `active`. `add_to_group_bundle` (B2f) copies the template member's status. | review · [assumed] |
| G-10 | **Download all schedules**: CSV (`?format=csv`), one row per slot: student, subscription id, bundle id, `schedule_status`, weekday, start, end (academy time), course, teacher. | TH SCHED-001 |
| G-11 | **Expanded calendar**: a week grid (Monday–Sunday, no dates) of active schedules' active slots of live subscriptions, filterable by teacher and student; read-only; shows slots, not sessions (substitutions and postponements are not reflected). | TH SCHED-001 "expand calendar" · [assumed] |
| G-12 | The per-course WhatsApp group of a schedule is B5's; notices to a replaced teacher are B5's. | TH SCHED-001; phase §6 |
| G-13 | Switch `weekly_schedules`, off by default (new line under the B2 marker). Off: the list, calendar, stop, delete, bulk teacher and substitution routes 404 and the screen hides; **activate and restore stay ungated** (listed as intentionally ungated in the route-table test), and the subscription page always shows a "Schedule stopped / deleted" badge with Activate / Restore, so nothing is stuck (FT-4, B2f F-11 precedent). Existing substitutions keep applying. **Deploy note:** keep the switch off for an academy until the previous release is drained (its generation ignores `schedule_status` and substitutions). | PO-5; spec Plan 13 FT-4; B2b B-12 |

## 3. Data

| Model | Field | Notes |
|---|---|---|
| Subscription | `schedule_status` | `active` \| `stopped` \| `deleted`, `db_default` `active` |
| Subscription | `schedule_changed_at`, `schedule_changed_by` | datetime / → User (`SET_NULL`), nullable: who last changed the status |
| Session | `substitute_for` | → TeacherProfile, nullable, PROTECT, `related_name="+"` |
| `TeacherSubstitution` (new) | `subscription` (CASCADE, `related_name="substitutions"`), `teacher` → TeacherProfile (PROTECT), `from_date`, `to_date`, `created_by`, `created_at` | `to_date ≥ from_date`; no overlap per subscription (checked in the service under the subscription lock) |

No data rewritten (phase B2-16).

## 4. Behaviour

**Lock order:** bundle (when acting on a bundle row) → all selected subscriptions, locked up front in pk order → their
sessions (Plan 4). Per-subscription services called afterwards only re-lock rows already held.

- **Generation** (`generation._lock_live` and the daily job, range runs, regeneration) skips subscriptions whose
  `schedule_status` is not `active` — the same filter B2d extends for archived subscriptions (coordinate the edit).
  `_new_session` reads the subscription's substitutions (prefetched once per run) and, for a date in a range, sets
  `teacher = substitution.teacher`, `substitute_for = subscription.teacher`. The range-run answer reports
  `skipped_stopped` for stopped / deleted schedules.
- `stop_schedules(ids, by)` / `delete_schedules(ids, by)`: set the status (and `schedule_changed_*`), then
  `delete_untouched(untouched_sessions(subscription__in=…, generated=True, occurs_on__gte=today,
  postponed_at__isnull=True))`.
- `activate_schedules(ids, by)` / `restore_schedules(ids, by)`: set `active`; `generate_horizon(subscription)` for live
  ones.
- `add_substitution(ids, by, *, teacher_id, from_date, to_date)`: per subscription, teacher active, teaches the course
  and is not the subscription's teacher (400, `member_id`); no overlapping range (400 on `from_date`, `member_id`).
  Create the record, then delete the untouched generated sessions in the range and `generate(from_date, to_date,
  subscription=s)` (within the generating window; dates beyond the horizon get the substitute when the daily job
  reaches them). Answer `{substitutions, conflicts, outside_availability}`.
- `remove_substitution(substitution, by)`: delete the record, then delete and regenerate the untouched generated sessions
  in its range (they return to the regular teacher).
- `bulk_change_teacher(ids, by, *, teacher_id)`: `update_subscription(teacher)` per subscription; answer
  `{subscriptions, conflicts, outside_availability}`.
- **Bundle rows:** actions on a bundle row apply to its current members (B2f F-5), lock the bundle first, and name a
  refusing member with `member_id`; the row's status is the members' common status, or `mixed`.
- **Today board:** slots of non-`active` schedules are left out; a row with a session shows `session.teacher` and the
  substitute label.
- **Slots:** `add_slots` / `update_slot` refuse a `deleted` schedule (409 `scheduling.schedule_deleted`).
- **B2c:** substitution changes are regenerations (creation and deletion are not logged, C-3 / C-9); `substitute_for`
  joins `LOGGED_FIELDS` for B2b's `teacher_moved` entries.

## 5. Lists

`filter_schedules(**filters)`: one row per subscription with at least one slot (bundle members grouped under their
bundle row). Tabs: `active`, `stopped`, `deleted`, `live_subscription` (active / paused), `ended_subscription` (expired /
cancelled), `all`. Filters: student, teacher (the subscription's), bundle kind (TH "subscription type"), study group.
Row: student, timing lines (weekday, start–end in academy time and the student's when it differs, course, teacher),
subscription progress (derived), status, current substitutions. Archived subscriptions (B2d) are left out while
`subscription_archive` is on.

## 6. Access

New resource under the B2 marker: `weekly_schedule` ("Weekly schedules" / "الجداول الأسبوعية", TH `weekly::schedule`,
`verbs=ALL_VERBS`), in use: view_any, update, delete, restore.

| Action | Code |
|---|---|
| List, CSV, calendar | `weekly_schedule.view_any` |
| Stop, activate, bulk teacher | `weekly_schedule.update` |
| Delete | `weekly_schedule.delete` |
| Restore | `weekly_schedule.restore` |
| Add / remove a substitution | `weekly_schedule.update` |

Non-office 404 (`is_office` before `HasCode`). A substitute teacher sees the substituted sessions in their own lists
(teacher scope follows `session.teacher`) but not the subscription; the regular teacher no longer sees them.
Everyone who sees a substituted session sees "Substitute for {teacher}".

## 7. API (`/api/v1/`)

| Route | Method | Feature | Notes |
|---|---|---|---|
| `schedules/` | GET | `weekly_schedules` | §5; `?format=csv` (G-10). |
| `schedules/stop/`, `schedules/delete/` | POST | `weekly_schedules` | `{subscription_ids}` (or `{bundle_ids}`). |
| `schedules/activate/`, `schedules/restore/` | POST | — (ungated) | Same body. |
| `schedules/teacher/` | POST | `weekly_schedules` | `{subscription_ids, teacher_id}`. |
| `schedules/substitutions/` | POST | `weekly_schedules` | `{subscription_ids, teacher_id, from_date, to_date}`. |
| `schedules/substitutions/<id>/` | DELETE | `weekly_schedules` | Remove one. |
| `schedules/calendar/` | GET | `weekly_schedules` | `?teacher=&student=` (G-11). |

Payloads: subscription gains `schedule_status` (always) and `substitutions`; session gains `substitute_for`
(`{id, name}`). New 409 `scheduling.schedule_deleted`.

## 8. Dashboard (`/app/`)

- **Weekly schedules** (`/app/scheduling/schedules`, NAV under the B2 marker): TH's tabs, filters, rows; header Add
  (pick a live subscription without slots → slot editor), **Expanded calendar**, **Download all**; bulk Stop / Activate
  / Delete / Restore / Change teacher / Substitute; row Edit (the subscription's slot editor; a group bundle's shared
  times are edited per member, a known limit).
- **Expanded calendar** (`/app/scheduling/schedules/calendar`): week grid; phone: one day at a time.
- **Subscription page:** status badge with Activate / Restore (always), substitutions list with Remove.
- **Sessions:** "Substitute for {teacher}" label.
- Strings in en and ar in a new area file `schedules.json`; RTL, phone width, semantic tokens.

## 9. Seeds

In `demo`, under the B2 marker, with `weekly_schedules` among `features.BUILT`: one stopped schedule; one active
schedule with a one-week substitution. Idempotent; `other` gets nothing.

## 10. Testing

- **Status:** stop removes untouched future generated sessions and keeps postponed / marked / hand-added ones; activate
  regenerates only when live; restore of an ended subscription's schedule; generation skips stopped / deleted in the
  daily job, range runs (`skipped_stopped`) and regeneration; renewal copies `stopped`, starts `active` after `deleted`;
  `add_to_group_bundle` copies the status; slots of a deleted schedule refused; bundle rows (`mixed`, current members,
  `member_id`).
- **Substitutions:** validation (overlap, own teacher, course, 366 days); generated sessions in range get the
  substitute and `substitute_for`; the daily job applies it beyond the horizon; pause, slot edit, `starts_on` edit,
  teacher change and renewal regenerate them correctly (renewal copies overlapping ranges; no duplicate dates);
  postponed / hand-added sessions untouched; remove restores the regular teacher; B2b's teacher-change move with and
  without `substitute_for`; payroll pays the substitute; conflicts and `outside_availability`.
- **Bulk teacher:** all or nothing; substitutions kept.
- **Lists:** tabs, filters, bundle grouping and group line collapse, archived hidden, CSV rows, calendar.
- **Today board:** stopped schedules' slots absent; substituted session's teacher.
- **Access & switch:** code matrix; non-office 404; switch off: gated routes 404, activate / restore work, badge shown.
- **Existing suites** pass unchanged.
- **Dashboard:** list, bulk dialogs, substitution dialog, calendar, subscription badge.
- **e2e** (`e2e/b2-schedules.spec.ts`, spec-owned data): the admin stops a schedule (its future sessions go), activates
  it (they return), and gives next week to a substitute (the sessions show the substitute).

## 11. Known limits (accepted)

- No permanent delete of a schedule; no bulk change of times; no "delete and move" (G-8).
- A group bundle's shared times are edited per member.
- A substitution does not change postponed or hand-added sessions in its range.
- The replaced teacher is not told (B5); reminders already sent are not resent (B2b B-13).
- Payroll needs the substitute to have a rate for the course (Plan 7 refuses a payslip otherwise); no warning is given
  at substitution time (payroll is B4's).

## 12. Out of scope

WhatsApp group routing per schedule course and substitution notices (B5); substitute pay rules (B4).

## Amendments from plan 41 (2026-10-06)

The shipped contract where it differs from the sections above (plan 41 rulings):

- **D1** — §4 "Bundle rows": actions apply to the bundle's **schedule members — current or still live** (not only current), so an old link with a pending renewal stops too; teacher change and substitution apply to the live ones among them (none live → 409 `scheduling.not_allowed_in_status`); the row's status is computed over the same members. A subscription id naming a member acts on that member alone.
- **D3** — §4: stop and activate refuse a deleted schedule; restore changes only deleted ones; the same status is a no-op; the bulk teacher change and a substitution refuse a deleted schedule; `delete_slot` stays allowed.
- **D5** — §4: `skipped_stopped` counts schedules (live, unarchived, with an active slot), not dates.
- **D9** — §4 `add_substitution`: the range regenerated is `max(from_date, today)` to the later of `min(to_date, today + horizon)` and the last deleted date.
- **D11** — §4: `remove_substitution(substitution)` takes no `by`.
- **D13** — §5: a schedule is a subscription with a slot that is **current or still live** — D1's rule for plain subscriptions too (review I-3), so a renewed link leaves the list once it has ended; filter `q` (student name) added; the kind filter is `kind=single|multi_course|family|group`; the default tab is `active`; rows newest first.
- **D15** — a route added to §7: `GET schedules/candidates/?q=` (code `weekly_schedule.update`, feature `weekly_schedules`), up to 20 live subscriptions without a slot whose schedule is not deleted; "Add" opens the chosen subscription's page.
- **D16** — §7: session `substitute_for` is `{id, full_name}` and appears only on substituted sessions (Today rows and My supervision's rows too); a **Today row's `teacher` follows its session** (the substitute on a substituted lesson; the subscription's teacher only for a row without a session) — B5 and B11 reading Today should know; the office's subscription detail adds `substitutions` (current and future), `schedule_changed_at`, `schedule_changed_by`.
- **D17** — §7 answers: status actions `{subscriptions}`; bulk teacher `{subscriptions, conflicts, outside_availability?}`; substitution 201 `{substitutions, conflicts, outside_availability?}`; remove 204.
- **D24 / ledger R2, D35:** `create_subscription` gains `schedule_status=` and `substitutions_from=` (additive), passed by `renew_subscription` and `add_to_group_bundle`; B3d keeps both slices' keyword arguments on rebase.
