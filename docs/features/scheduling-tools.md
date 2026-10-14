# Scheduling tools: trials, availability, groups, bundles, weekly schedules

These are the office tools built on top of subscriptions and sessions in phase B2:

- **trial requests** with one trial session each, and conversion of a trial into a subscription;
- **teacher availability** windows, used for warnings and teacher suggestions;
- **study groups** and **subscription bundles** (multi-course, family, group);
- **weekly schedules**: stopping, deleting and restoring a schedule, bulk teacher changes and substitute teachers.

Every tool is behind its own feature switch, and each switch is off by default. Admins
and staff use all of them. Teachers only edit their own availability. Students and
parents get a 404 on every route on this page.

## Concepts

| Model (`backend/etqan/scheduling/models.py`) | Purpose |
|---|---|
| `TrialRequest` | An office record of a trial request: `student`, `course`, `source` (`website`/`app`/`api`), `students_count` (1–20), `preferred_gender`, `minutes` (15–180), `desired_at`, `requested_on`, `request_status` (`under_review`/`accepted`/`rejected`), `heard_from`, `rated`, `notes`, `inquiry_id` (the site inquiry, unique), `converted_to` (one-to-one → `Subscription`). |
| `Session.kind="trial"` + `Session.trial` | The request's sessions. At most one live (not cancelled) session per request. They have no subscription and no slot. |
| `TeacherAvailability` | A weekly window (`weekday`, `start_time` < `end_time`) on the academy's wall clock, per teacher. It never blocks anything. |
| `StudyGroup` / `StudyGroupMember` | A named set of students taught together. A student is in at most one group (enforced by a one-to-one on `student`). |
| `SubscriptionBundle` | `kind` is `multi_course` (owner `student`), `family` (owner `family`) or `group` (owner `study_group`). A DB check makes sure exactly the owner field for the kind is set. Members are ordinary `Subscription`s with `bundle` set. Totals are computed and never stored. |
| `Subscription.schedule_status` | B2g: `active`/`stopped`/`deleted`, plus `schedule_changed_at/by`. A "schedule" is a subscription that has at least one slot. |
| `TeacherSubstitution` | A substitute `teacher` for one subscription from `from_date` to `to_date` (max 366 days, no overlaps). |

## How it works

**Trials** (`services/trials.py`, `conversion.py`, `suggest.py`; feature `trial_sessions`)

1. `create_trial` needs an active student (a `trial` profile status is fine) and an active course. Requests can also be created from a website inquiry (`inquiry_id`, see the dashboard's `TrialFromInquiry`).
2. `schedule_trial` adds the trial session through `manual.add_trial_session`. It is refused when the request was converted, was rejected or already has a live session, or when the teacher does not teach the course. A start time in the past is allowed. Length defaults to the request's minutes, and the meeting link defaults to the teacher's default. An `under_review` request becomes `accepted`. Overlaps are only warned about.
3. `trial_status` is `not_scheduled`, or the status of the current session.
4. `suggest_teachers` returns up to 5 candidates from the course's teachers (every active teacher when the course lists none). They are ranked by: free at that time, then availability (inside the window, then no windows, then outside the window), then gender match, then fewest sessions that week, then name.
5. Conversion: `POST /api/v1/subscriptions/` with `trial_id` (needs `trial_session.update`). `conversion.claim_trial` locks the request and its session. It requires a completed session, a request that was not converted yet, and the same student. It then sets `converted_to`.
6. `delete_trial` deletes the request and its sessions, unless the request was converted or a session is marked, completed, at disposal or paid.

**Availability** (`services/availability.py`; feature `teacher_availability`)

- `set_availability` replaces all of a teacher's windows (max 50).
- `is_available` returns True or False, or None when the teacher has no windows, which counts as "unknown" rather than unavailable.
- `outside_availability`, `slots_outside` and `sessions_outside` add warnings to session, slot and schedule payloads. They return None while the switch is off.

**Study groups and bundles** (`services/groups.py`, `bundles.py`, `bundle_actions.py`, `bundle_reads.py`)

- Groups (feature `study_groups`): create, update (members sent as a full list) and delete. A group with bundles can't be deleted. New members must be active.
- `create_bundle` builds every member through `create_subscription(..., bundle=)` in one transaction, so either all members are created or none.
  - `multi_course`: one student and at least 2 distinct courses.
  - `family`: an active family, at least 2 rows, with distinct students and courses.
  - `group`: an active study group and exactly one row. It creates one subscription per active member, all in one currency.
- Bundle actions lock the bundle, then every member in id order. They apply each member's own service, and when one member refuses, the whole action is refused and names that member. The actions are `renew_bundle`, `pause_bundle`, `cancel_bundle`, `archive_bundle`/`restore_bundle`, `dissolve_bundle` (members become plain subscriptions and the bundle row goes), `add_to_group_bundle` (copies the newest current member) and `remove_from_group_bundle` (cancels that student's live members).
- A member's renewal stays in the bundle and keeps its course. Members can still be edited one by one with the subscription endpoints.
- In conflict checks, the rows of one group class (same teacher, start and length in a group bundle) are not counted as clashing with each other (`rules.group_siblings`).

**Weekly schedules** (`services/schedules.py`, `schedule_reads.py`, `substitute_teachers.py`; feature `weekly_schedules`)

- Targets are subscription ids and/or bundle ids. Each action locks bundles, then subscriptions, and is all-or-nothing.
- `stop_schedules`: no new sessions are generated, and untouched future sessions are deleted. Generation skips stopped and deleted schedules whatever the switch says.
- `delete_schedules` moves the schedule to the "deleted" tab, which also stops it. `restore_schedules` brings a deleted schedule back as active. `activate_schedules` makes the schedule active again and fills the horizon. Activate and restore stay ungated, so nothing gets stuck while the switch is off.
- `bulk_change_teacher` calls `update_subscription(teacher)` on every target.
- `add_substitution`/`remove_substitution` regenerate the untouched generated sessions in the range, so they go to the substitute (with `Session.substitute_for` set) or back to the regular teacher. Postponed and hand-added sessions keep their teacher. Renewal copies overlapping substitutions unless the course changes.
- Reads:
  - `schedule_rows`: one row per subscription, or one row per bundle. Tabs are `active`, `stopped`, `deleted`, `live_subscription`, `ended_subscription` and `all`.
  - `schedule_calendar`: active slots by day and time, with a group class shown as one entry.
  - `schedule_candidates`: live subscriptions with no slot yet, used to add a schedule.

## API

All routes are under `/api/v1/`. "Office" means `OfficeOr404` + permission code + feature switch.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET, POST | `/api/v1/trials/` | office `trial_session.view_any` / `.create` | List (CSV) / create |
| GET, PATCH, DELETE | `/api/v1/trials/<id>/` | office `trial_session.view` / `.update` / `.delete` | Read / edit / delete |
| POST | `/api/v1/trials/<id>/schedule/` | office `trial_session.update` | Schedule the trial session |
| GET | `/api/v1/trials/suggest/?course&occurs_on&start_time&minutes&gender` | office `trial_session.create` or `.update` | Teacher suggestions |
| GET, PUT | `/api/v1/schedule/availability/` | the teacher; `teacher_availability` | My windows |
| GET, PUT | `/api/v1/schedule/availability/<user_id>/` | `teacher_schedule.view` / `.update`, or that teacher | A teacher's windows |
| GET, POST | `/api/v1/groups/` | office `study_group.view_any` / `.create`; `study_groups` | List / create |
| GET | `/api/v1/groups/candidates/` | office `study_group.create`/`.update` | Students who may join |
| GET, PATCH, DELETE | `/api/v1/groups/<id>/` | office `study_group.*` | Read / edit / delete |
| POST | `/api/v1/bundles/multi-course/`, `/bundles/family/`, `/bundles/group/` | office `subscription.create`; `multi_course_subscriptions` / `family_subscriptions` / `group_subscriptions` | Create a bundle (each member is invoiced as usual) |
| GET | `/api/v1/bundles/` | office `subscription.view_any` | List (`student`, `state=live|ended`) |
| GET, PATCH, DELETE | `/api/v1/bundles/<id>/` | office `subscription.view` / `.update` | Read / edit notes / dissolve |
| POST | `/api/v1/bundles/<id>/renew/`, `/pause/`, `/cancel/` | office `subscription.update` | Whole-bundle actions |
| POST, DELETE | `/api/v1/bundles/<id>/archive/` | office; `subscription_archive` | Archive / restore |
| POST | `/api/v1/bundles/<id>/members/` | office `subscription.update` | Add a student to a group bundle |
| DELETE | `/api/v1/bundles/<id>/members/<student_id>/` | office `subscription.update` | Remove a student from a group bundle |
| GET | `/api/v1/schedules/` | office `weekly_schedule.view_any`; `weekly_schedules` | Rows by tab (CSV) |
| GET | `/api/v1/schedules/calendar/` | office `weekly_schedule.view_any` | Slot calendar |
| GET | `/api/v1/schedules/candidates/` | office `weekly_schedule.update` | Subscriptions without slots |
| POST | `/api/v1/schedules/stop/`, `/delete/` | office `weekly_schedule.update` / `.delete` | Stop / delete |
| POST | `/api/v1/schedules/activate/`, `/restore/` | office `weekly_schedule.update` / `.restore` (no feature gate) | Activate / restore |
| POST | `/api/v1/schedules/teacher/` | office `weekly_schedule.update` | Bulk teacher change |
| POST | `/api/v1/schedules/substitutions/` | office `weekly_schedule.update` | Add a substitution |
| DELETE | `/api/v1/schedules/substitutions/<id>/` | office `weekly_schedule.update` | Remove a substitution |

## Dashboard

- Routes (`dashboard/src/routes/_authed/`): `scheduling.trials.index.tsx`, `.new.tsx`,
  `.$trialId.tsx`; `scheduling.schedules.index.tsx`, `scheduling.schedules.calendar.tsx`;
  `scheduling.bundles.$bundleId.tsx`; `people.groups.index.tsx`;
  `teaching.availability.tsx` (teacher); `website.inquiries.tsx` (trial from inquiry).
  There is no bundle list route. Bundles are filtered in `SubscriptionsList` and created
  through `SubscriptionTypeChoice` → `BundleForm`.
- Components (`dashboard/src/features/scheduling/`): `TrialsList`, `TrialForm`,
  `TrialPage`, `ScheduleTrialDialog`, `TrialFromInquiry`, `AvailabilityEditor`,
  `StudyGroupsList`, `StudyGroupDialog`, `BundleForm`, `BundleRowFields`, `BundlePage`,
  `BundleMembers`, `BundleRoster`, `BundleActions`, `BundleLink`, `GroupChip`,
  `SchedulesList`, `ScheduleCalendar`, `ScheduleActions`, `ScheduleStatusCard`,
  `AddScheduleDialog`, `ScheduleTeacherDialog`, `SubstituteDialog`, `SubstituteChip`;
  `bundleApi.ts`, `scheduleApi.ts`.

## Background jobs

None of their own. `scheduling.run_daily` generation reads `schedule_status`,
substitutions and pauses ([subscriptions.md](subscriptions.md)).

## Configuration

Feature switches (all off by default): `trial_sessions`, `teacher_availability`,
`study_groups`, `multi_course_subscriptions`, `family_subscriptions` (requires
`families`), `group_subscriptions` (requires `study_groups`), `weekly_schedules`,
`subscription_archive`.

## Code map

- `backend/etqan/scheduling/services/trials.py`, `conversion.py`, `suggest.py`,
  `availability.py`, `groups.py`, `bundles.py`, `bundle_actions.py`, `bundle_reads.py`,
  `schedules.py`, `schedule_reads.py`, `substitute_teachers.py`
- `backend/etqan/scheduling/api/trial_views.py`, `availability_views.py`,
  `group_views.py`, `bundle_views.py`, `bundle_payloads.py`, `schedule_views.py`,
  `schedule_payloads.py`

## Design history

- [B2 scheduling depth](../superpowers/specs/2026-10-03-b2-scheduling-depth-design.md): the phase umbrella.
- [B2e trials and availability](../superpowers/specs/2026-10-03-b2e-trials-availability-design.md) ([plan 33](../superpowers/plans/2026-10-05-plan-33-trials-availability.md)).
- [B2f bundles and groups](../superpowers/specs/2026-10-03-b2f-bundles-groups-design.md) ([plan 37](../superpowers/plans/2026-10-05-plan-37-bundles-groups.md)).
- [B2g weekly schedules](../superpowers/specs/2026-10-03-b2g-weekly-schedules-design.md) ([plan 41](../superpowers/plans/2026-10-06-plan-41-weekly-schedules.md)).
- [B3d countries and currencies](../superpowers/specs/2026-10-05-b3d-countries-currencies-design.md): the group bundle's one-currency rule (D-5).
