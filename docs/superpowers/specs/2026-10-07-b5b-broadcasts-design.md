# Slice B5b — Broadcasts & notification log — Design

**Date:** 2026-10-07
**Status:** Self-approved after an independent spec review (orchestration PO-3); review findings applied 2026-10-07.
**Phase spec:** `2026-10-07-b5-communication-design.md`. This is its §3 row B5b, and decisions B5-1…B5-13 bind it,
including B5-5 as amended for ledger D40–D42.
**Evidence:** P1 COMM-003, BR-42, FLOW-013; TH §2.7 COMM-003, COMM-009. R7 is dropped (ledger D1).
**Requires:** B5a (migration `0002`, `text.language_for`, the scan module). B2f is needed only for the
study-group audience: it is a separate task, built last, and it also needs request R-B5b-1 (§7).

## 1. Goal

The office writes one message to one of TutorHamster's ten audiences. Every recipient gets it as an in-app
notice, and by email. The office sees each message it sent and, per recipient, whether the email was sent or
failed and whether the notice was read. It also has a read-only log of every notice the academy has sent,
automatic ones included, which is TH's "الإشعارات (التلقائية)" page.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| C-1 | **A broadcast is one record plus one `Notification` row per recipient.** The record is a new model `Broadcast` (§3). Each recipient row has:<br>• type `broadcast`;<br>• target kind `broadcast`;<br>• `target_id` = the broadcast's id;<br>• dedupe key `broadcast:broadcast:<id>:<user_id>`.<br>The bell, the read flag and email delivery stay Plan 8's (N8-4). | P1 COMM-003; spec 2026-09-26 N8-4 |
| C-2 | **The ten audiences** (TH "الشخص المستهدف"):<br>• `admins`: every active admin except the sender;<br>• `teachers`, `students`: several, chosen;<br>• `student`, `teacher`, `parent`: one, chosen;<br>• `all_students`, `all_teachers`, `all_parents`: every *active* user of that role;<br>• `study_group`: the members of one active B2f study group.<br>Staff accounts are never an audience: TH's "مدير النظام" means admins. Recipients are resolved at send time; anyone added later gets nothing. | TH §2.7 COMM-003 options · [assumed] "group" = study group (P1 PEOPLE-003 "مجموعة"); sender excluded |
| C-3 | **Who is told:** Plan 8's `recipients.eligible`. Inactive users are never told, and neither is a student without an email address. `parent` and `all_parents` need the `parents` feature (else 400 `audience`). `study_group` needs `study_groups` (else 400 `audience`); an inactive or missing group is 400 `study_group`. A chosen person who is not eligible is skipped: not counted in `recipient_count`, and counted in the response's `skipped`. If nobody is eligible the request fails with 400 `audience` ("Nobody in this audience can be told"). | spec 2026-09-26 recipients · [assumed] |
| C-4 | **Channels.** TH's channel field is required (Email · WhatsApp). WhatsApp is on hold (D41), so `channels` must contain `email` and nothing else: `["email"]`. Anything else is 400 `channels`. The composer shows Email ticked and fixed. The in-app notice is always made, as our record and read flag. B5c will add `whatsapp`. | TH §2.7 COMM-003 (channels\* required), COMM-009; ledger D41 · [assumed] in-app always |
| C-5 | **Text.** `message` is plain text, 1–2000 characters after trimming, delivered exactly as written in one language; line breaks are kept. The title is fixed in the recipient's language (`text.language_for`, so a Spanish reader gets the academy default, D22): "New message" / "رسالة جديدة". The email subject already carries the academy's name (`brand_email`'s `[name]` prefix), so the title does not repeat it. No templates (B5a T-1 covers automatic notices only). | P1 COMM-003 (message\*) · [assumed] title; review |
| C-6 | **Preferences are ignored** (B5-9). FLOW-013 draws one dispatch path that respects toggles for every notice. Our preferences are per *category* of automatic notice (B5a T-8), and a broadcast belongs to no category, so there is nothing to respect. | P1 FLOW-013; B5-9 |
| C-7 | **Read-only status (BR-42), amending Plan 8 §4.5 for the office only.** The broadcast detail and the notification log show each row's `email_status` (`pending` · `sent` · `failed` · `skipped`) and `read_at`. `email_error` and `dedupe_key` stay hidden. The recipient's own inbox payload is unchanged. `skipped` now means "no email sent": either no address, or email not chosen (the model comment is updated). Nothing sent is editable. | P1 BR-42; spec 2026-09-26 §4.5 |
| C-8 | **Delete.** Deleting a broadcast removes the record and, explicitly, its rows (`Notification` where `target_kind="broadcast"` and `target_id=id`; there is no FK), so the notices leave the bells. Emails already sent stay sent. A pending email not yet being sent is never sent: its row is gone, and the task finds nothing. One whose send is in progress may still go out (the send holds the row lock). | TH COMM-003 row action delete · [assumed] |
| C-9 | **Permissions.** A new access resource `broadcast` ("Broadcasts" / "الرسائل الجماعية"), with `view_any`, `create` and `delete` in use. The detail uses `view_any`, as the list and detail are one screen. A new resource `notification_log` ("Notification log" / "سجل الإشعارات") has `view_any`. Sending is `[HasCode, FeatureOn, NotImpersonating]`. Quick login never targets admins or staff, so `NotImpersonating` is defence in depth (D19). Teachers, students and parents get 403 everywhere. | ledger D19; RBAC pattern |
| C-10 | **Switch `broadcasts`** ("Broadcasts and notification log" / "الرسائل الجماعية وسجل الإشعارات"; new, group `communication`, off by default). It covers both screens and every route here. While it is off, routes answer 404 after the role check, and sent notices stay in the bells. | B5-3; FT-4 |
| C-11 | **Where a broadcast notice leads.** `links.path_for` gains a first branch: target kind `broadcast` → `/notifications` for every role. Otherwise an unknown kind would fall through to the invoice branch. | spec 2026-09-26 §4.3 |
| C-12 | **Sending and cost.** `send_broadcast` does three things:<br>1. resolves the audience in a fixed number of queries (`identity.services.people_queryset(role).filter(is_active=True)`, `get_users`, `active_admins`, and the study-group service);<br>2. inserts every row in one `bulk_create(ignore_conflicts=True)`;<br>3. queues the emails on commit with Plan 8's `email.queue`, one task per row.<br>Academies are small [assumed], so audience size is not capped. A fan-out task is a later optimisation. Email goes through Plan 8's send path unchanged. When the integrations slice (D42) moves that path onto `integrations.resolve` and meters Etqan-default usage, broadcasts follow automatically, and B5b hard-wires nothing about the provider. | spec 2026-09-26 N8-2; ledger D42 |
| C-13 | **Email recovery does not depend on automatic notices.** Plan 8 re-queues stuck pending emails only inside `scan()`, which does not run while `auto_notifications` is off. B5b changes the beat job so `requeue_stuck` runs every minute in every academy regardless; it only re-queues existing rows. | spec 2026-09-26 §4.4; review |
| C-14 | **Pickers.**<br>• **People pickers** reuse the people list endpoints. They need `<role>.view_any`; without it that audience's picker is disabled with a hint.<br>• **Study-group select** needs `study_group.view_any` and `study_groups`, with the same rule.<br>Sending checks only `broadcast.create`. | [assumed] |
| C-15 | **The notification log** (COMM-003 is TH's log of all notices, automatic and manual). A read-only, paginated list of every `Notification`: created_at, type (`broadcast` included), recipient name and role, title, email status and read. Filters: type, email status, and created from / to. No delete or edit in the log [assumed: BR-42; TH's row delete is covered by deleting a broadcast]. | TH §2.7 COMM-003 (columns, filter target type, "Seen" automatic admin notice) |
| C-16 | **Bell display.** Notice bodies render with line breaks kept (`whitespace-pre-line`) everywhere. In the bell dropdown they are clamped to 3 lines; the full text stays on `/notifications`. | review; C-5 |

## 3. Data (in `etqan.notifications`, migration `0003` after B5a's `0002`)

```text
etqan.notifications.Broadcast
  audience        CharField(16, choices of C-2)
  audience_label  CharField(200)   # snapshot at send: up to 3 names (+ "and n more") or the group's name
  message         TextField
  channels        JSONField(default=list)   # ["email"] in B5b
  created_by      FK User  SET_NULL  null  related_name="+"
  created_at      default now
  recipient_count PositiveIntegerField
  ordering (-created_at, -id)
```

Changes to `Notification`, all on B5's own table (B5-10):
- `type` uses new `kinds.NOTICE_TYPES = (*TYPES, BROADCAST)`;
- `target_kind` uses `kinds.NOTICE_TARGETS = (*TARGETS, BROADCAST)`;
- both are `AlterField`s that change choices only;
- a new `Index(fields=["target_kind", "target_id"])`.

`TYPES`, `TARGETS` and `KINDS` are unchanged, as are the settings, templates, `SAMPLE_FACTS` and their
invariants. A broadcast is not an automatic type. The chosen people and group are not stored: the recipient
rows and `audience_label` carry everything shown (YAGNI).

## 4. API (under `/api/v1/notifications/`)

| Method & path | Permission | Body / answer |
|---|---|---|
| `GET broadcasts/` | `broadcast.view_any` + `broadcasts` | Paginated; `?audience=` filter. Each row: id, audience, audience_label, message (first 140 characters), channels, created_by name, created_at, recipient_count, `email` counts by status, `read` count |
| `POST broadcasts/` | `broadcast.create` + `broadcasts` + `NotImpersonating` | `{audience, people?, study_group?, message, channels}` → 201: the row plus `skipped`. 400s on `audience`, `people`, `study_group`, `message`, `channels` |
| `GET broadcasts/<id>/` | `broadcast.view_any` + `broadcasts` | The row with the full message, plus paginated `recipients` (name, role, email_status, read_at) |
| `DELETE broadcasts/<id>/` | `broadcast.delete` + `broadcasts` | 204 |
| `GET log/` | `notification_log.view_any` + `broadcasts` | Paginated rows (C-15); `?type=&email_status=&from=&to=` |

`people` must name users of the audience's role. `student`, `teacher` and `parent` take exactly one id;
`teachers` and `students` take 1–500. Any other id is a 400 on `people`, checked with one role-filtered
`id__in` query.

## 5. Screens (dashboard; code in `src/features/notifications/`, strings in a new area `locales/{en,ar}/broadcasts.json`)

The nav group is `people` [assumed]. The dashboard has no communication group, and adding one is shell work
B5e may do.

| Who | Where | What |
|---|---|---|
| Office | **Broadcasts** `/people/broadcasts`. Route `routes/_authed/people.broadcasts.tsx`; nav under the B5 marker; `broadcast.view_any` and `broadcasts`. | List: date · audience (label) · message · sent / failed / pending · read n / total · sent by, with an audience filter.<br>**New broadcast** dialog (`broadcast.create`):<br>• an audience select; `parent` / `all_parents` hidden while `parents` is off, and `study_group` shown only with `study_groups` on (and once its task is built);<br>• a people picker or a group select per C-14;<br>• the message, with a counter;<br>• Email, ticked and fixed;<br>• Send, with a confirm naming the audience.<br>After sending, a toast gives the recipient and skipped counts.<br>**Detail drawer**: the full message (line breaks kept), the recipients table (name, role, email status chip, read), and Delete (`broadcast.delete`, confirm). |
| Office | **Notification log** `/people/notification-log`. Route `routes/_authed/people.notification-log.tsx`; nav under the B5 marker; `notification_log.view_any` and `broadcasts`. | A read-only table (C-15) with filters for type, status and dates. |
| Everyone | Bell and `/notifications` | Line breaks kept; bell bodies clamped to 3 lines (C-16). |

`FeatureCode` gains `broadcasts`. No seed data: the demo academy gets the switch through `features.BUILT`.

## 6. Behaviour notes

- **Sending** (`services.broadcasts.send`) runs in one transaction:
  1. validate everything;
  2. resolve and filter recipients with `eligible`;
  3. 400 if nobody is left;
  4. create the `Broadcast`;
  5. build and `bulk_create` the rows, each title rendered in its recipient's language, with `email_status`
     `pending` if the user has an address, else `skipped`;
  6. `email.queue` the pending ids;
  7. return the record and the skipped count.
- **List counts** are one aggregate query per page (rows grouped by `target_id` and `email_status`, plus a read
  count) on the new index.

## 7. Tasks, requirements and requests

- **Tasks 1 to n−1 (everything but the study group)** need only B5a.
- **The last task, the `study_group` audience,** needs B2f merged and **R-B5b-1, a request to B2:** a read
  service `scheduling.services.study_group_members(group_id) -> StudyGroupMembers(name: str, is_active: bool,
  student_user_ids: list[int])`. It returns all of the group's members; eligibility is filtered by
  notifications, and a missing group raises `NotFoundError`. It is additive and read-only.
- If R-B5b-1 is not done when everything else is ready, B5b merges without that audience. The option stays
  hidden, and the API answers 400 `audience` for it; the audience moves to B5d.

## 8. Tests

- **Backend:**
  - resolution for each audience: inactive users, a student without email, the sender excluded from `admins`,
    `parents` off, `study_groups` off, wrong-role and duplicate ids, nobody eligible;
  - the rows: title per language, the dedupe key, `pending` vs `skipped`;
  - emails queued once;
  - delete removes rows, and a pending email is then not sent;
  - `requeue_stuck` runs while `auto_notifications` is off;
  - the `path_for` branch for each role;
  - the permission matrix, including the switch 404 after the role check;
  - list and detail counts, and log filters;
  - the query count is fixed for 1 and 50 recipients, and for list pages.
- **Dashboard:**
  - the composer: audience switching, the pickers' permission states, validation, 400 mapping, confirm, the
    result toast;
  - the list, the detail with chips, delete;
  - the log filters;
  - line breaks and the clamp in the bell.
- **e2e** `e2e/b5-broadcasts.spec.ts`: an admin sends to one stamped student. The student sees it in the bell
  and in Mailpit. The admin's detail shows "sent", and "read" once the student opens it. The log lists the row.
  The admin deletes the broadcast.

## 9. Non-goals

- WhatsApp (B5c, on hold).
- Scheduled sending.
- Attachments.
- Rich text.
- Editing after sending.
- Per-language message text.
- Replies (chat is B5e).
- Templates for broadcasts.
- Deleting individual notices from the log.
- A recipient-count preview before sending.
