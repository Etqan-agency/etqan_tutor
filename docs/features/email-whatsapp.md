---
title: "Email, WhatsApp and broadcasts"
---

How a notice leaves the app. Every `Notification` row (see [notifications.md](notifications.md)) is the in-app item
**and** the record of its email and WhatsApp delivery. Email goes to anyone with an address; WhatsApp only to
people who opted in, for types the academy switched to WhatsApp. Broadcasts are office-written messages sent to
an audience as in-app notices plus email. Accounts (SMTP server, WhatsApp Cloud API number) come only from
`etqan.integrations.services.resolve(service)`; notifications stores no keys.

## Concepts

| Thing | Where | Notes |
|---|---|---|
| `Notification.email_status` | `etqan/notifications/models.py` | `pending` → `sent` / `failed`; `skipped` when the recipient has no address or the type is in-app only (`chat.unread`) |
| `Notification.whatsapp_status` | same | `none` (type not on WhatsApp, or a broadcast), `pending`, `sending` (claimed by a worker), `sent`, `failed`, `skipped` (not opted in, no phone, no account) |
| `whatsapp_tried_at` | same | The claim's owner token; never in a payload |
| `NotificationSetting.whatsapp` | same | Per-type academy switch "also send on WhatsApp" |
| `WhatsAppChoice` | same | Per-user opt-in. No row: a **parent** follows identity's `has_whatsapp`; everyone else is off (`services/whatsapp_choice.py:choice_of`) |
| `Broadcast` | same | `audience`, `audience_label` (snapshot at send), `message`, `channels` (always `["email"]`), `created_by`, `recipient_count` |

## How it works

### Email channel (`etqan/notifications/channels/email.py`)

- `queue(ids)` schedules one `notifications.deliver_email(schema_name, id)` task per row **on commit**
  (`robust=True`: one failed `delay` does not stop the others; the scan re-queues it later).
- `send(id)` re-reads the row with `select_for_update(skip_locked=True)` filtered to `pending`, so a re-queued
  task never sends twice. It composes the message (`compose`): greeting + body + absolute link from
  `templates/email/notifications/message.<lang>.txt`, wrapped in the academy's branded layout
  (`etqan.site.emails.brand_email`), then calls `integrations.services.send_email_now`.
- Errors: `OSError` (SMTP) retries twice with 60 s / 120 s backoff, then `failed` with `email_error`; any other
  exception fails the row immediately.
- Notifications uses `send_email_now` inside its own task (not `queue_email`) so it can track per-row status.
  Other email (account emails in `etqan/identity`) uses `integrations.services.queue_email`.
- Metering: `integrations/services/email.py:meter_email` records usage only when the account is Etqan's default.

### WhatsApp channel (`etqan/notifications/channels/whatsapp.py`)

- At store time (`services/scan.py:_whatsapp_statuses`), only while the `whatsapp` feature is on and only for types
  with `NotificationSetting.whatsapp` and `emails=True`: a recipient who opted in, has a `phone` and whose academy
  resolves a WhatsApp account gets `pending`; otherwise `skipped`.
- `deliver_whatsapp` holds **no row lock across Meta's call**: `claim()` flips `pending → sending` with a
  conditional UPDATE stamping `whatsapp_tried_at`; the outcome is written by `Try.finish` only while the row is
  still `sending` with that token. Email and WhatsApp write disjoint columns.
- The message is a pre-approved utility template with three body parameters (`integrations.services.build_params`):
  academy name (from the branded sender), title, body; collapsed and cut to stay under Meta's 1024-char limit.
- Outcomes: accepted → `sent` + `whatsapp_message_id` (wamid); `NotSetUpError` → `skipped`; `WhatsAppError` with
  `retry=True` → back to `pending`, retried twice (60 s, 120 s); otherwise `failed` with our wording + Meta's
  code only (never the number or Meta's body).
- Stuck rows: `scan.py:_stuck_whatsapp` resets `pending`/`sending` rows with no try for 5 min (within 24 h) to
  `pending` and re-queues them; this can rarely duplicate a message if a worker died after Meta accepted it
  (accepted trade-off).
- Metering: `integrations/services/whatsapp.py:meter_whatsapp` records one `conversation` per wamid on Etqan's default.
- No group posting, no inbound messages, no delivery-status webhook.

### Broadcasts (`etqan/notifications/services/broadcasts.py`)

- `send(audience, people, study_group, message, channels, by)` (atomic): message 1–2000 chars; `channels` must be
  exactly `["email"]`; resolve the audience; keep `recipients.eligible` users; create the `Broadcast` and one
  `Notification` per recipient (type/target `broadcast`, title "New message"/"رسالة جديدة" in the recipient's
  language, body = the message); queue emails on commit. Returns how many were skipped.
- Audiences: `admins` (all active admins but the sender), `teachers`/`students` (1–500 chosen), `student`/`teacher`/
  `parent` (exactly one), `all_students`/`all_teachers`/`all_parents`, `study_group` (needs `study_groups`;
  members via `scheduling.services.study_group_members`). Parent audiences need `parents` on.
- Broadcasts are not muted by preferences and never go on WhatsApp.
- `delete(id)` removes the broadcast and its notices; an email not yet sent never goes out.
- Log and counts: `services/log.py` (`broadcasts`, `broadcast_rows` with per-status email counts and read count,
  `recipients`, `notices` for the full notification log).

## API

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/notifications/broadcasts/?audience=` | `broadcast.view_any`; feature `broadcasts` | List with email/read counts |
| POST | `/api/v1/notifications/broadcasts/` | `broadcast.create`; feature `broadcasts`; not impersonating | Send; 201 with `skipped` |
| GET | `/api/v1/notifications/broadcasts/<id>/` | `broadcast.view_any` | Detail + paginated recipients with `email_status`, `whatsapp_status`, `read_at` |
| DELETE | `/api/v1/notifications/broadcasts/<id>/` | `broadcast.delete` | Delete broadcast and its notices |
| GET | `/api/v1/notifications/log/` | `notification_log.view_any`; feature `broadcasts` | Every notice; filters `type`, `email_status`, `whatsapp_status`, `from`, `to` |
| GET, PATCH | `/api/v1/notifications/whatsapp/` | signed-in; feature `whatsapp`; PATCH not impersonating | `{opted_in, phone_on_file}`; set own choice only |
| GET, PATCH | `/api/v1/notifications/settings/` | `notification_settings.view` / `.update` | Includes the per-type `whatsapp` flag |

Account setup (SMTP, WhatsApp number/template/token) is in the integrations API, not here.

## Dashboard

| Route | Component (`dashboard/src/features/notifications/`) |
|---|---|
| `routes/_authed/people.broadcasts.tsx` (`broadcast.view_any`, `broadcasts`) | `BroadcastsPage`, `BroadcastComposer`, `BroadcastDetail` |
| `routes/_authed/people.notification-log.tsx` (`notification_log.view_any`, `broadcasts`) | `NotificationLogPage` |
| `routes/_authed/account.tsx` | `WhatsAppChoiceCard` (read-only while impersonating) |
| `routes/_authed/settings.academy.tsx` | `NotificationSettingsForm` (per-type WhatsApp column) |

Translations: `dashboard/src/locales/<lng>/broadcasts.json`, `notifications.json`.

## Background jobs

| Task | Trigger | Notes |
|---|---|---|
| `notifications.deliver_email` | On commit of the scan / broadcast | 3 tries; runs in `academy_context(schema_name)` |
| `notifications.deliver_whatsapp` | On commit of the scan, or re-queue | 3 tries for retryable Meta errors |
| `notifications.scan` | Beat, every minute | Also re-queues stuck emails (always) and WhatsApp rows (while `whatsapp` on) |

## Configuration

- Features: `broadcasts` (also gates the log), `whatsapp` (gates the channel, the opt-in API, and Etqan's
  default WhatsApp account via integrations `SWITCHES`), `study_groups`, `parents`.
- Integrations: email account (academy's own SMTP, else Etqan's default); WhatsApp Cloud API account
  (`phone_number_id`, `waba_id`, template name with ar/en language codes, access token; incomplete account =
  skipped, not failed — `integrations/providers/whatsapp.py:complete`).
- Recipient data: `User.email`, `User.phone` (leading `+` stripped), parent `has_whatsapp` default.

## Code map

- `backend/etqan/notifications/channels/email.py`, `channels/whatsapp.py` — delivery tasks.
- `backend/etqan/notifications/services/broadcasts.py`, `services/log.py`, `services/whatsapp_choice.py`.
- `backend/etqan/notifications/services/scan.py` — `store`, `_whatsapp_statuses`, `requeue_stuck`.
- `backend/etqan/templates/email/notifications/message.{ar,en}.txt` — email text wrapper.
- `backend/etqan/integrations/services/email.py`, `services/whatsapp.py`, `providers/whatsapp.py` — sending and metering.
- `dashboard/src/features/notifications/` — composer, log, WhatsApp card.

## Design history

- [Plan 8 notifications design](../superpowers/specs/2026-09-26-notifications-design.md) — email channel §4.4.
- [B5 communication phase](../superpowers/specs/2026-10-07-b5-communication-design.md) — B5-5 (Cloud API, no groups; "on hold" note superseded by B5c).
- [B5b broadcasts](../superpowers/specs/2026-10-07-b5b-broadcasts-design.md) — composer, audiences, log.
- [B5c WhatsApp](../superpowers/specs/2026-10-08-b5c-whatsapp-design.md) — channel, opt-in, claim/re-queue; narrows B5: broadcasts by WhatsApp not built (X-9).
- Plans: [plan 43](../superpowers/plans/2026-10-07-plan-43-broadcasts.md), [plan 57](../superpowers/plans/2026-10-08-plan-57-whatsapp.md).
