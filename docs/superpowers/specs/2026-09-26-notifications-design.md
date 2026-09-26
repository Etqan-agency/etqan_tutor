# Plan 8 — Notifications — Design

**Date:** 2026-09-26
**Status:** Approved in brainstorming (sections 1–3), pending written-spec review.
**Phase:** B0, milestone 8 of the parity roadmap (`2026-09-24-parity-roadmap-design.md`).
**Builds on:**
- v1 spec §4.9 and §6.5 (`2026-09-23-etqan-tutor-v1-design.md`);
- Plans 4–6 (sessions, attendance, reports, subscriptions, invoices), which this app reads through their services;
- Plan 2 (the branded ar/en email layout) and Plan 3 (the invite email, roles and guardians).

**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md`, which covers:
- COMM-003 and COMM-004 (the automated templates and their timings: early reminder 2 h before, lateness 5 min after the start, teacher reminder 30 min before);
- COMM-008 (the in-app stream);
- SCHED-003 (per-session reminder stamps).

Roadmap rule R4 applies.

## 1. Goal

Students, parents, teachers and admins are told about what matters to them without having to look:
- sessions about to start;
- lateness;
- absences;
- subscriptions running low or expired;
- invoices issued or overdue;
- missing session reports.

Every notification shows in the app, under a bell with an unread count, and is emailed when the recipient has an email address. Each is written in the recipient's language.

## 2. Decisions

| # | Decision |
|---|---|
| N8-1 | A new tenant app, `etqan.notifications`, is the only place that decides who is told what, and when. It reads scheduling, billing, identity and academy only through their `services`. **No other app imports it**, and `lint-imports` enforces that. |
| N8-2 | **One scanner (owner decision).** A Celery beat job runs every minute and loops over every academy. It runs one finder per type against current state, and creates notifications keyed by a unique `dedupe_key`, so re-runs and overlapping runs never send twice. Domain apps don't call into notifications. The delay is at most about one minute, and a missed run catches up. |
| N8-3 | **Scope (owner decision):** the v1 list plus TutorHamster's extra timings, as the 10 types in §4.2. The invite email (Plan 3) is unchanged. |
| N8-4 | One `Notification` row per recipient per occurrence. It is both the in-app item and the record of the email. Its title and body are rendered once, in the recipient's language, and frozen. |
| N8-5 | Each type has an academy-level on/off switch, and the timed types have an editable number of minutes. Templates live in code (ar and en). Editable templates and per-user preferences are phase B5. |
| N8-6 | Email goes through a small channel interface (`channels.email`), so WhatsApp can be added in B5 without touching the finders. |
| N8-7 | A notification is never deleted or changed when its cause is undone, for example when attendance is corrected or an invoice is paid. Repeating types stop repeating once their condition no longer holds. |

## 3. Data

### 3.1 Notification (new, `etqan.notifications`)

| Field | Notes |
|---|---|
| `recipient` | → User |
| `type` | one of the 10 types in §4.2 |
| `dedupe_key` | unique; `<type>:<object>:<id>[:<occurrence>]:<recipient_id>` |
| `target_kind`, `target_id` | what it is about (`session · subscription · invoice`), used to build the link |
| `title`, `body` | rendered in the recipient's language when created |
| `read_at` | null until read |
| `email_status` | `pending · sent · failed · skipped` (`skipped` means the recipient has no email address) |
| `email_sent_at`, `email_error` | |
| `created_at` | |

There is an index on (recipient, read_at, created_at) for the bell and the list.

### 3.2 NotificationSetting (new)

| Field | Notes |
|---|---|
| `type` | unique, one row per type |
| `enabled` | default `true` |
| `value` | for timed types, minutes; for `subscription.low`, the session threshold; otherwise null |

Missing rows are created with the defaults in §4.2 on first read.

### 3.3 Subscription (existing, `etqan.scheduling`)

New field: `expired_at` (UTC, nullable). Scheduling's `expire()` sets it, so the scanner can find subscriptions that expired recently. Existing expired subscriptions keep a null, and so are never announced.

## 4. Behaviour

### 4.1 The scanner

`notifications.scan`, every minute, uses `for_each_academy`. One academy's failure is logged and rolled back, and the others still run. In each academy:

1. Load the settings.
2. For each enabled type, run its finder and build `(recipient, dedupe_key, target, rendered text)` for each hit.
3. Insert them with `bulk_create(ignore_conflicts=True)`.
4. After commit, queue one email task per row that was actually new and whose recipient has an email address. Rows for recipients without an email address are stored as `skipped`.

**Recipients:**
- Only active users are notified.
- A student with no login (an inactive `User`) gets nothing; their guardians still do.
- "Guardians" means the student's linked parents (identity's services).
- "Admins" means every active admin of the academy.
- The payer is the invoice's `payer`.

**Look-back:**
- **Event types** (absent, invoice issued, expired) only consider events from the last 24 hours. So enabling notifications on an academy with history sends no flood, and a scanner outage of up to a day loses nothing.
- **State types** (low, missing report) are deduped once per object.

### 4.2 The types

Time comparisons use UTC instants. "Today" is the academy's calendar.

| # | Type | Recipients | Fires when | Default value | Occurrence |
|---|---|---|---|---|---|
| 1 | `session.early_reminder` | student, guardians | `now ≥ starts_at − value` and `now < starts_at`, for a session still `scheduled` | 120 min | once per session |
| 2 | `session.reminder` | student, guardians | same, with its own value | 60 min | once per session |
| 3 | `session.teacher_reminder` | the session's teacher | same, with its own value | 30 min | once per session |
| 4 | `session.late` | teacher, student, guardians | `now ≥ starts_at + value` and `now < starts_at + 60 min`, while the session is `scheduled` with both attendances `not_set` | 5 min | once per session |
| 5 | `session.student_absent` | guardians | a `completed` session whose `student_attendance` is `absent`, with `marked_at` in the last 24 h | — | once per session |
| 6 | `subscription.low` | student, guardians, admins | an `active` subscription whose `sessions_remaining ≤ value` | 2 sessions | once per subscription |
| 7 | `subscription.expired` | student, guardians, admins | `expired_at` in the last 24 h | — | once per subscription |
| 8 | `invoice.issued` | payer | a non-void invoice created in the last 24 h | — | once per invoice |
| 9 | `invoice.overdue` | payer, admins | an `unpaid` or `partial` invoice with today > `due_on` | — | week `n = (today − due_on − 1) // 7`, so the day after the due date, then every 7 days |
| 10 | `report.missing` | the session's teacher | the session is in scheduling's `missing_reports()` (Plan 5 §4.5) | — | once per session |

**Notes:**
- A reminder whose moment has passed still fires as long as the session hasn't started. This covers a session created or moved inside the window. It never fires after the start.
- A session cancelled before its reminder gets none. One cancelled after its reminder keeps the reminder already sent.
- Switching a type off stops new notifications of that type immediately. Existing ones stay.

**Value ranges** (outside them, a 400 on `value`):
- early reminder: 30–1440;
- reminder: 5–720;
- teacher reminder: 5–720;
- lateness: 1–55;
- low threshold: 0–10.

### 4.3 Text and links

- There is one template per type in code, in ar and en: a title, a short body, and an email body on the branded layout (Plan 2).
- The language is the recipient's `preferred_language`, falling back to the academy's `default_language`.
- Times are shown in the recipient's `timezone`.
- The body names the course, the student (to guardians, teachers and admins), the time, and the invoice number and amount where relevant.
- Links are built with `frontend_url()`:
  - **sessions:** the session page for teachers and admins, and the sessions list for students and parents;
  - **subscriptions:** the subscription page for admins, and the student's own page for families;
  - **invoices:** the invoice page.

### 4.4 Email delivery

- `notifications.deliver_email(notification_id)` runs inside the academy's schema. It renders through `channels.email`, sends with the existing platform send path, and sets `sent` with `email_sent_at`.
- A transient failure retries with backoff (3 tries), then sets `failed` with the error.
- The task re-reads the row, so a row already `sent` is never sent twice.

### 4.5 Access

- Every signed-in role (admin, teacher, student, parent) reads and marks only their own notifications. Another user's notification is a `404`. Anonymous callers get a `403`.
- The settings routes are admin-only; other roles get a `403`.
- `email_status`, `email_error` and `dedupe_key` never appear in the API.

## 5. API (`/api/v1/notifications/`, existing conventions)

| Method | Path | Notes |
|---|---|---|
| GET | `` | The caller's notifications, newest first, paged; `?unread=1`. Each row: `id, type, title, body, link, read_at, created_at`. |
| GET | `unread-count/` | `{count}` |
| POST | `<id>/read/` | Marks one read; idempotent; returns the row. |
| POST | `read-all/` | Marks all the caller's unread notifications read; returns `{count}`. |
| GET | `settings/` | Admin only. All 10 types: `type, enabled, value`. |
| PATCH | `settings/` | Admin only. A list of `{type, enabled?, value?}`; returns a fresh read of all 10. |

## 6. Dashboard (`/app/`)

- **Bell (top bar, all roles):**
  - an unread badge, polled every 60 s through `unread-count/`;
  - a dropdown of the latest 10 with "Mark all read" and "See all";
  - clicking an item marks it read and follows its link.
- **Notifications page (`/notifications`):** the full list, an All/Unread filter, paging, and read and unread styling.
- **Admin settings:** a Notifications section on the academy settings page. It lists the 10 types, each with a switch, and a number field for the timed types and the low threshold. Saving answers with the fresh settings, and field errors land on their field.
- **General:**
  - every string is in en and ar, RTL, and works at phone width;
  - it reuses the shared helpers (Pager, `applyServerErrors`, `useFieldError`, the zoned-time helpers).

## 7. Seeds

- `seed_dev` creates the default settings.
- It runs the scanner once for the demo academy, which yields whatever is due in the seeded data, such as a missing report, a low subscription or an overdue invoice.
- It adds one read and one unread notification per demo role, so the bell has something in every panel.
- It is idempotent, and leaves the `other` academy alone.

## 8. Testing

- **Finders, per type:**
  - fires at its moment and not a minute early (pinned clocks);
  - fires once across repeated scans;
  - the right recipients;
  - a switched-off type creates nothing.
- **Recipients:** a student without a login, a deactivated user, several guardians, and a parent with no email address (`skipped`).
- **Look-back:** events older than 24 h and existing expired subscriptions send nothing.
- **Overdue:** the day after due, then the 8th day after, then stops once paid.
- **Reminders:**
  - a session created inside the window gets its reminder once;
  - a started session gets none;
  - a cancelled one gets none.
- **Lateness:** fires only while attendance is unmarked, and gives up after 60 minutes.
- **Text:**
  - the recipient's language and timezone, where both differ from the academy's;
  - the links.
- **Email:** sent once; a re-queued task doesn't resend; a failure retries and then sets `failed`.
- **The scanner:**
  - one academy's error doesn't stop the others;
  - a scan in one academy never writes to another (cross-academy tests with `until_pk_exceeds`);
  - its query count doesn't grow with the number of notifications created.
- **API:**
  - each role reads only its own;
  - another user's notification is a 404;
  - settings are admin-only, with value ranges;
  - query-count tests on the list and the unread count.
- **Boundaries:** `lint-imports` shows no app imports notifications.
- **E2E through Caddy:** an admin marks a student absent; the scan runs (a management command); the parent signs in through the invite, sees the bell's count and the item, and follows it; the email is in the file outbox.

## 9. Risks

| Risk | Mitigation |
|---|---|
| A flood of notifications when first enabled | 24 h look-back on events; state types deduped once; existing expired subscriptions have no `expired_at` |
| Double sends from overlapping scans or task retries | a unique `dedupe_key` with `ignore_conflicts`; the email task checks `sent` before sending |
| Scanner cost every minute across many academies | indexed windows (`starts_at`, `marked_at`, `created_at`, `expired_at`), one query per finder, a flat query count |
| Email noise for families | per-type switches in academy settings; per-user preferences in B5 |

## 10. Out of scope (roadmap phase)

B5:
- editable templates;
- per-user notification preferences;
- WhatsApp routing;
- manual broadcasts;
- chat;
- per-session custom reminder times;
- notices for schedule changes, cancellations, payslips and payments;
- push or real-time delivery (the bell polls).
