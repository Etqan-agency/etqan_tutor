# Notifications

In-app notices for every signed-in role, with each notice's email (and optionally WhatsApp and web push)
delivered from the same row. Notices are produced by a once-a-minute **scanner** that polls other apps'
services; no other app calls into notifications. Admins tune the catalogue (on/off, timing, WhatsApp, text);
students, parents and teachers can mute categories. Delivery channels are covered in
[email-whatsapp.md](email-whatsapp.md) and [web-push.md](web-push.md); broadcasts also live in
[email-whatsapp.md](email-whatsapp.md).

## Concepts

| Model (`etqan/notifications/models.py`) | What it is |
|---|---|
| `Notification` | One row per recipient per occurrence. Holds `title`/`body` rendered once in the recipient's language (never re-rendered), `read_at`, `email_status` (`pending/sent/failed/skipped`), `whatsapp_status` (`none/pending/sending/sent/failed/skipped`), `target_kind` + `target_id`, and a unique `dedupe_key` `<type>:<target>:<id>[:<occurrence>]:<recipient_id>`. |
| `NotificationSetting` | Academy switch per type: `enabled`, `value` (minutes, or sessions for `subscription.low`), `whatsapp`. Rows are created lazily with catalogue defaults (`services/settings.py:current`). |
| `NotificationTemplate` | Academy override of a type's title/body per language (`ar`/`en`). No row: built-in text in `text.py:TEMPLATES`. |
| `NotificationOptOut` | One muted category for one user. No row: on. |
| `WhatsAppChoice` | One user's WhatsApp opt-in (see [email-whatsapp.md](email-whatsapp.md)). |
| `Broadcast` | An office message; its recipients are `Notification` rows of type `broadcast`. |

**Catalogue** — `etqan/notifications/kinds.py:KINDS` is the single source of truth: 23 automatic types, each with a
target kind, default number and range, category, the roles it reaches, its "duty" roles, and whether it emails.
`broadcast` is a 24th notice type with no setting, template, category or finder.

| Category | Types |
|---|---|
| `sessions` | `session.early_reminder`, `session.reminder`, `session.teacher_reminder`, `session.teacher_early_reminder`, `session.late`, `session.student_absent`, `session.teacher_absent`, `session.ended` |
| `payments` | `subscription.low`, `subscription.expired`, `invoice.issued`, `invoice.overdue` |
| `schedule` | `session.postponed`, `session.compensation_booked`, `session.trial_booked`, `schedule.substitution` |
| `reports_homework` | `report.missing`, `homework.set`, `homework.answered`, `homework.completed`, `level.upgrade_requested`, `level.upgrade_decided` |
| `chat` | `chat.unread` (in-app only: `emails=False`) |

Audiences per type are in `finders.py:AUDIENCES` (parts: student, guardians, teacher, admins, payer, extra
teacher, requester, recipient); a test keeps `Kind.roles` in step with it.

## How it works

**The boundary.** `etqan/notifications/services/__init__.py` says it plainly: no other app imports
notifications. Instead the scanner *reads* other apps through their services (scheduling, billing, learning,
chat, identity). The only importers are `etqan.devices.push` (web push reads `created_since`) and dev seeds.
`lint-imports` (`backend/pyproject.toml`) forbids notifications from reaching other apps' models/APIs and
forbids e.g. `etqan.academy` from importing notifications. Apps that want a notice expose a read-only query
(e.g. `etqan/billing/services/notices.py`, `etqan/chat/services/notices.py:unread_digest`) and a finder here
consumes it.

**Scan flow** (`services/scan.py:scan`, per academy, one instant from `clock.now()`):

1. `settings.current()` loads every type's row; a type is read only if `enabled` and its academy features are
   on (`scan.py:FEATURE_OF`, e.g. homework types need `homework`, `chat.unread` needs `internal_chat`).
2. Each type's finder (`finders.py:FINDERS`) returns `Hit`s: what is due now. Event types look back 24 h
   (`LOOK_BACK`) so turning notifications on sends no flood; `session.late` gives up after 60 min,
   `report.missing` looks back 7 days, `invoice.overdue` stops 90 days after the due date.
3. `recipients.py:resolve` turns hits into `(hit, user)` pairs: guardians and admins are read once per scan;
   guardians only while `parents` is on; inactive users and students without an email are dropped (others
   without an email get the in-app notice with `email_status=skipped`).
4. `scan.py:honour_preferences` drops pairs whose recipient muted the type's category (only while
   `notification_preferences` is on). Duty notices (`session.late`, `report.missing` to a teacher) are never
   muted; admins/staff have no preferences.
5. `scan.py:store` renders each new row (`text.py:render`, the recipient's language via
   `text.language_for` and time zone; academy template overrides from `templates.overrides()` when
   `notification_templates` is on), sets WhatsApp statuses, `bulk_create(ignore_conflicts=True)`, then queues
   email and WhatsApp tasks **on commit**.
6. `scan.py:requeue_stuck` re-queues emails pending 5 min–24 h (and stuck WhatsApp rows while `whatsapp` is on).

Invariants: the unique `dedupe_key` makes overlapping or repeated scans harmless; each delivery task re-reads
its row under a lock/claim so a message goes out once; a rolled-back scan sends nothing.
`scan_now()` (the beat entry) skips the scan while `auto_notifications` is off but still re-queues stuck emails.

**Links.** `links.py:path_for` maps a notice to a dashboard path for the recipient's role (admin → record
page, teacher → `/teaching/...`, family → `/learning/...`, chat → `/chat?c=<id>`, broadcast →
`/notifications`). The API returns it as `link`; the email uses it as an absolute URL (`app_url`).

**Inbox.** `services/inbox.py`: `inbox`, `unread_count`, `mark_read` (keeps first `read_at`), `mark_all_read`.
Another user's notice is a 404.

**Templates.** `services/templates.py`: `save`/`reset`/`preview`/`listing`. Only the type's placeholders
(`text.py:PLACEHOLDERS`) are accepted; `{{`/`}}` escape a brace; title ≤ 150, body ≤ 1000.

**Preferences.** `services/preferences.py:of/change`; `kinds.categories_for(role)` decides which categories a
role sees (a category appears only if a non-duty type reaches that role).

## API

All under `/api/v1/notifications/`. "Code" = permission code via `HasCode`; "feature" = `FeatureOn`.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/notifications/?unread=` | any signed-in | Own inbox, paginated, newest first |
| GET | `/api/v1/notifications/unread-count/` | any signed-in | `{count}` for the bell |
| POST | `/api/v1/notifications/<id>/read/` | any signed-in | Mark one read |
| POST | `/api/v1/notifications/read-all/` | any signed-in | Mark all read |
| GET, PATCH | `/api/v1/notifications/settings/` | `notification_settings.view` / `.update` | Per-type `enabled`, `value`, `whatsapp` |
| GET | `/api/v1/notifications/templates/` | `notification_settings.view`; feature `notification_templates` | Every type × language with defaults and placeholders |
| PUT, DELETE | `/api/v1/notifications/templates/<type>/<lang>/` | `notification_settings.update`; same feature | Save / reset an override |
| POST | `/api/v1/notifications/templates/preview/` | `notification_settings.view`; same feature | Render a draft with sample facts |
| GET, PATCH | `/api/v1/notifications/preferences/` | signed-in; feature `notification_preferences` | Own category switches |
| GET, PATCH | `/api/v1/notifications/preferences/<user_id>/` | `<role>.view` / `<role>.update` of the target (student/teacher/parent); same feature | Office edits a person's switches (miss → 404) |
| GET, PATCH | `/api/v1/notifications/whatsapp/` | signed-in; feature `whatsapp`; PATCH not while impersonating | Own WhatsApp opt-in |
| GET, POST | `/api/v1/notifications/broadcasts/` | `broadcast.view_any` / `broadcast.create`; feature `broadcasts` | See [email-whatsapp.md](email-whatsapp.md) |
| GET, DELETE | `/api/v1/notifications/broadcasts/<id>/` | `broadcast.view_any` / `broadcast.delete`; feature `broadcasts` | Broadcast detail with recipients / delete |
| GET | `/api/v1/notifications/log/` | `notification_log.view_any`; feature `broadcasts` | Every notice with filters `type`, `email_status`, `whatsapp_status`, `from`, `to` (academy days) |

`email_status`, `email_error` and `dedupe_key` never appear in the inbox payload (`api/payloads.py`).

## Dashboard

| Route | Feature folder / component | Notes |
|---|---|---|
| `dashboard/src/routes/_authed/notifications.tsx` | `NotificationsPage` | Every role |
| top bar | `NotificationBell` (used in `features/shell/AppTopbar.tsx`) | Polls unread count every 60 s (`queries.ts:POLL_MS`) |
| `routes/_authed/settings.academy.tsx` | `NotificationSettingsForm` | Per-type switches, numbers, WhatsApp |
| `routes/_authed/settings.notification-templates.tsx` | `TemplatesPage`, `TemplateDialog` | `notification_settings.view` + `notification_templates` |
| `routes/_authed/account.tsx` | `NotificationPreferencesCard`, `WhatsAppChoiceCard` | Own preferences / WhatsApp choice |
| `routes/_authed/people.{students,teachers,parents}.$personId.tsx` | `NotificationPreferencesCard` | Office view of a person's switches |
| `routes/_authed/people.broadcasts.tsx`, `people.notification-log.tsx` | `BroadcastsPage`, `NotificationLogPage` | See [email-whatsapp.md](email-whatsapp.md) |

Feature code: `dashboard/src/features/notifications/`. Translations: `dashboard/src/locales/<lng>/notifications.json`
and `broadcasts.json`.

## Background jobs

| Task | Schedule | What |
|---|---|---|
| `notifications.scan` (`etqan/notifications/tasks.py`) | Beat every minute (`expires` 55 s), soft limit 240 s | `for_each_academy(services.scan_now)`; one academy's failure is logged and rolled back, others continue |
| `notifications.deliver_email`, `notifications.deliver_whatsapp` | Queued on commit | Per-row delivery; see [email-whatsapp.md](email-whatsapp.md) |

`python manage.py scan_notifications` runs the scan in every academy now. Dev seeds: `services/scan.py:add_samples`
(one read and one unread reminder per user, via `seed_dev`).

## Configuration

- Academy features (`etqan/platform/features.py`): `auto_notifications` (default on) gates the scan;
  `notification_templates`, `notification_preferences`, `broadcasts`, `whatsapp` (default off); per-type gates
  in `scan.py:FEATURE_OF`; `parents` gates guardian recipients.
- Per-type settings: Settings → Academy (`NotificationSetting`).
- Language: recipient's `preferred_language`, else the academy's `default_language`; time zone: user's, else academy's.

## Code map

- `backend/etqan/notifications/kinds.py` — the catalogue.
- `backend/etqan/notifications/finders.py` — one finder per type; `AUDIENCES`.
- `backend/etqan/notifications/recipients.py` — the one recipient resolver.
- `backend/etqan/notifications/text.py` — built-in ar/en text, placeholders, renderer.
- `backend/etqan/notifications/links.py` — dashboard path per notice and role.
- `backend/etqan/notifications/services/` — `scan.py`, `inbox.py`, `settings.py`, `templates.py`, `preferences.py`, `broadcasts.py`, `log.py`, `whatsapp_choice.py`, `push.py`.
- `backend/etqan/notifications/channels/` — `email.py`, `whatsapp.py`.
- `backend/etqan/notifications/api/` — views, payloads, urls.
- `dashboard/src/features/notifications/`.

## Design history

- [Plan 8 notifications design](../superpowers/specs/2026-09-26-notifications-design.md) — original ten types, scanner, email, bell (N8-*). Still the base; type list extended later.
- [B5 communication phase](../superpowers/specs/2026-10-07-b5-communication-design.md) — B5-1…B5-13 decisions; also contains slice B5a (editable templates T-1…T-7, preferences T-8…T-12). Its B5-5 "B5c on hold" is superseded by the B5c spec.
- [B5b broadcasts](../superpowers/specs/2026-10-07-b5b-broadcasts-design.md) — broadcasts, notification log, `skipped` email status.
- [B5d more notices](../superpowers/specs/2026-10-07-b5d-more-notices-design.md) — twelve more types and the D-CHAT addendum (`chat.unread`).
- [B5c WhatsApp](../superpowers/specs/2026-10-08-b5c-whatsapp-design.md) — WhatsApp channel and per-type switch.
- Plans: [plan 8](../superpowers/plans/2026-09-26-plan-8-notifications.md), [plan 42](../superpowers/plans/2026-10-07-plan-42-templates-preferences.md), [plan 43](../superpowers/plans/2026-10-07-plan-43-broadcasts.md), [plan 56](../superpowers/plans/2026-10-08-plan-56-more-notices.md), [plan 57](../superpowers/plans/2026-10-08-plan-57-whatsapp.md).
