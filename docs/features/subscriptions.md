---
title: "Subscriptions"
---

A subscription sells one **package** of one **course** to one **student**, taught by one
**teacher**, starting on a date. Its weekly **slots** produce the **sessions**
(see [sessions.md](sessions.md)). Admins and staff create, edit, pause, renew, cancel,
archive and delete subscriptions. Teachers, students and parents can only read their
own: a teacher reads the subscriptions they teach, a student their own, and a parent
their children's. Bundles (multi-course, family and group) are sets of ordinary
subscriptions. They are covered in [scheduling-tools.md](scheduling-tools.md).

## Concepts

| Model (`backend/etqan/scheduling/models.py`) | Purpose |
|---|---|
| `Subscription` | student, course, teacher, package (all `PROTECT`); `starts_on`, `term_ends_on`. Copies of the package values: `duration_value/unit`, `sessions_total`, `session_minutes`, `freeze_days_allowed`, `price_minor` + `currency`. `status` is `active`/`paused`/`expired`/`cancelled`. `renewed_from` (one-to-one chain), `supervisor`, `expired_at`, `archived_at/by` (B2d), `bundle` (B2f), `schedule_status` (`active`/`stopped`/`deleted`, B2g). |
| `SubscriptionPause` | A `from_date`..`to_date` freeze, with an optional reason. |
| `ScheduleSlot` | A weekly slot: `weekday` (0 = Monday), `start_time` on the academy's wall clock, `minutes`, an optional `meeting_url`, `is_active`. Two active slots of one subscription can't share a weekday and time. |
| `TeacherSubstitution` | B2g: a substitute teaches the generated sessions in a date range (see [scheduling-tools.md](scheduling-tools.md)). |

**Derived values** (`scheduling/services/rules.py:derive`). These are never stored. The
API, the Today board and the job all compute them the same way:

- `ends_on` = `term_ends_on` + the paused days. `grace_ends_on` = `ends_on` + the
  academy's `renewal_grace_days`. `in_grace` is true while today is between the two.
- `sessions_used` counts the subscription's sessions that match `rules.consuming`.
  A session counts when it is completed, the teacher was not absent, its kind is
  `regular` or `compensation`, it is not a compensated original, and the student was
  present. Absent and excused also count when the academy's
  `absent_consumes_session` / `excused_consumes_session` switches are on. An original
  "compensated as balance" (wallet, B3e) counts.
- `carried_over_sessions` = the predecessor's extra sessions, computed live along the
  renewal chain. `sessions_remaining` = total − carried − used. `extra_sessions` is the
  overrun. `freeze_days_left` and `progress` are also derived.

## How it works

Services live in `backend/etqan/scheduling/services/subscriptions.py` unless noted.

1. **Create** (`create_subscription`). The service copies the package (`_copy_package`)
   and computes `term_ends_on` (`scheduling/dates.py:term_ends_on`). It prices through
   `catalogue.services.package_price` for the student's country. An explicit
   `price_minor` overrides the amount, and a stale `currency` gets 400
   `catalogue.price_currency_changed`. The teacher must be active and teach the course.
   Then it adds the slots and generates the horizon
   (`generation.generate_horizon(subscription)`). With `trial`, it converts a completed
   trial (`conversion.claim_trial`). The API view then calls
   `billing.services.invoice_subscription` in the same transaction. That call issues an
   invoice only while the `invoices` feature and `auto_invoice_on_subscription` are on.
2. **Edit** (`update_subscription`): teacher, price, notes and `starts_on`. A new
   teacher or start date replaces the untouched generated sessions (`_regenerate`).
   Postponed unmarked sessions follow a teacher change. Changing `starts_on` is refused
   once any session is marked, and when a pause would fall outside the new term.
3. **Pause** (`add_pause`). The pause must start inside the term and must not overlap
   another pause (409 `scheduling.pause_overlaps`). Its length must fit the freeze days
   left (409 `scheduling.freeze_days_exceeded`). It deletes the untouched sessions inside
   the pause, sets the status to `paused` if the pause covers today, and regenerates
   (the term grew). `end_pause` works only on a pause that covers today: its end moves
   to yesterday, or the pause is deleted if it started today. `delete_pause` works only
   on a pause that has not started yet.
4. **Slots** (`add_slots`, `update_slot`, `delete_slot`). Adding or editing a slot
   replaces its untouched sessions and regenerates. A slot that has sessions can't be
   deleted (409 `scheduling.slot_has_sessions`): deactivate it instead. An ended
   subscription allows only deactivation.
5. **Renew** (`renew_subscription`). It works from `active`, `paused` or `expired`, and
   only once (409 `scheduling.already_renewed` unless the earlier renewal was
   cancelled). By default the renewal starts the day after `ends_on`, or today if that
   is later. Slots, supervisor, bundle, a stopped schedule and overlapping substitutions
   carry over. The price carries over unless the resolved currency changed. The old
   subscription's untouched sessions from the renewal start go now, and its postponed
   unmarked ones from then move to the renewal. The old subscription expires at once
   if the renewal has already started, and otherwise when the job reaches that day.
   Generation for the old term stops the day before the renewal starts
   (`rules.generation_last_day`).
6. **Cancel** (`cancel_subscription`): the status becomes `cancelled`, and the untouched
   `regular` sessions are deleted.
7. **Delete** (`delete_subscription`) is meant for mistakes. Billing refuses first (409
   `billing.subscription_invoiced`). It is also refused when the subscription was renewed
   or when any session is marked, completed, cancelled or at disposal. Otherwise every
   session goes, and the bundle goes too when this was its last member.
8. **Archive** (`services/archive.py:archive_subscription` / `restore_subscription`, B2d).
   Only an ended (expired or cancelled) subscription with no session still to come can
   be archived. Its sessions are archived with it (`archived_with_subscription`).
   Nothing is deleted, and no count or invoice changes. While the archive is on, an
   archived subscription is refused for actions such as renew until it is restored.
9. **Expiry** happens in the hourly job: see Background jobs.

Locking: subscriptions are locked first (id order), then sessions. Every service follows
this "Plan 4 lock order".

## API

Mounted at the root of `/api/v1/` (`backend/etqan/scheduling/api/urls.py`). Reads use
`HasCode | (ReadOnly & ReadsOwn)`: office by permission code, and teacher, student or
parent scoped to their own rows by `scheduling/scopes.py`. Out-of-scope rows return 404.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET, POST | `/api/v1/subscriptions/` | `subscription.view_any` / `.create`; own rows read-only | List (filters `status`, `student`, `teacher`, `course`, `q`, created/archived dates, `bundle`, `bundle_kind`, `archived`; CSV for office) / create (optional `trial_id`; the 201 answer adds `conflicts`, the new sessions' teacher double-bookings, never blocked) |
| GET, PATCH, DELETE | `/api/v1/subscriptions/<id>/` | `subscription.view` / `.update` / `.delete` | Detail with derived values / edit (incl. `supervisor_id`) / delete |
| POST | `/api/v1/subscriptions/<id>/renew/` | `subscription.update` | Renew (also invoices); like create, the 201 answer adds `conflicts` (the new sessions' teacher double-bookings, P4-9) |
| POST | `/api/v1/subscriptions/<id>/cancel/` | `subscription.update` | Cancel |
| POST, DELETE | `/api/v1/subscriptions/<id>/archive/` | `subscription.delete` / `.restore`; office; feature `subscription_archive` | Archive / restore |
| GET, POST | `/api/v1/subscriptions/<id>/pauses/` | `subscription.view` / `.update` | List / add a pause |
| DELETE | `/api/v1/pauses/<id>/` | `subscription.update` | Delete a future pause |
| POST | `/api/v1/pauses/<id>/end/` | `subscription.update` | End the current pause early |
| GET, POST | `/api/v1/subscriptions/<id>/slots/` | `subscription.view` / `.update` | List / add slots (`weekdays`, `start_time`, `minutes`, `meeting_url`) |
| PATCH, DELETE | `/api/v1/slots/<id>/` | `subscription.update` | Edit or (de)activate / delete a slot |
| GET | `/api/v1/subscriptions/<id>/sessions/` | `session.view_any`; own rows | The subscription's sessions |
| POST | `/api/v1/schedule/generate/` | `session.create` | Generate a date range now (optionally for one subscription); returns counts and teacher conflicts |
| GET | `/api/v1/schedule/today/` | `session.view_any` | The Today board (`services/board.py:today_board`) |

## Dashboard

- `dashboard/src/routes/_authed/scheduling.subscriptions.index.tsx`, `.new.tsx`,
  `.$subscriptionId.tsx` and `.archive.tsx`, plus `scheduling.today.tsx`.
  `scheduling.tsx` is office-only. `learning.subscriptions.tsx` is the student and parent
  view.
- `dashboard/src/features/scheduling/`: `SubscriptionsList`, `NewSubscription` +
  `SubscriptionForm` + `SubscriptionTypeChoice` (individual or bundle kinds),
  `SubscriptionDetail`, `SubscriptionActions`, `RenewDialog`, `PausesPanel`,
  `SlotsPanel` / `SlotFields`, `TermFields`, `GenerateDialog`, `TodayBoard`,
  `ArchiveActions`, `FamilySubscriptions`.

## Background jobs

- `scheduling.run_daily` (`scheduling/tasks.py`) is scheduled **hourly at minute 5** in
  `config/settings/base.py` `CELERY_BEAT_SCHEDULE`. Despite its name, it runs
  `services.lifecycle.run_lifecycle` in every academy via
  `platform.tenancy.for_each_academy`, with one transaction per academy. A failing
  academy is rolled back and logged. The steps:
  1. `rules.sync_pause_status`: `paused` exactly while a pause covers today.
  2. Expire live subscriptions past `grace_ends_on`, or whose live renewal has started
     (`rules.expire`). This sets `expired_at` and deletes the untouched `regular`
     sessions.
  3. `generation.generate_horizon()`: today through today + `generation_horizon_days`.
     A date whose student or teacher (the substitute's inside a substitution) is
     deactivated is skipped (`skipped_inactive`, `rules.person_inactive`), and the Today
     board shows no missing row for it; reactivating fills the horizon again.
- Notifications reads `services.notices.subscriptions_running_low` /
  `subscriptions_expired` in its own scan.

## Configuration

Academy settings (`backend/etqan/academy/models.py`): `timezone`,
`generation_horizon_days` (1–60, default 14), `renewal_grace_days` (0–60, default 7),
`absent_consumes_session` (default on), `excused_consumes_session` (default off),
`auto_invoice_on_subscription`. Feature switches: `subscription_archive`,
`supervision` (shows and edits `supervisor_id`), `invoices`, `country_pricing`,
`trial_sessions` (`trial_id` on create).

## Code map

- `backend/etqan/scheduling/services/subscriptions.py`: create, edit, pause, slot,
  renew, cancel and delete
- `backend/etqan/scheduling/services/rules.py`: shared rules (term, consumption,
  derive, expire, untouched sessions)
- `backend/etqan/scheduling/services/generation.py`, `lifecycle.py`, `board.py`,
  `archive.py`, `conversion.py`
- `backend/etqan/scheduling/dates.py`: local date and UTC conversions, term end
- `backend/etqan/scheduling/api/views.py`, `payloads.py`, `serializers.py`
- `backend/etqan/scheduling/scopes.py`: row scope per role

## Design history

- [Plan 4 subscriptions and scheduling spec](../superpowers/specs/2026-09-24-subscriptions-scheduling-design.md): statuses, term, renewal chain, generation, the hourly job. Amended to match the build. Still the base.
- [Plan 4 plan](../superpowers/plans/2026-09-24-plan-4-subscriptions-scheduling.md): the lock order and the D-decisions cited in the code.
- [Plan 5 sessions and attendance spec](../superpowers/specs/2026-09-25-sessions-attendance-design.md): the consumption rule and the academy switches.
- [B2 scheduling depth phase spec](../superpowers/specs/2026-10-03-b2-scheduling-depth-design.md): the umbrella for B2a–B2g. Its slice letters were re-assigned by B2b.
- [B2d archives](../superpowers/specs/2026-10-03-b2d-archives-design.md): the subscription archive.
- [B3d countries and currencies](../superpowers/specs/2026-10-05-b3d-countries-currencies-design.md): pricing by student country, and the currency-changed refusal.
- [Plan 12b supervision](../superpowers/plans/2026-09-29-plan-12b-supervision.md): the subscription and session supervisor.
