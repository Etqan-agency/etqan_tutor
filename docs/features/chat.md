---
title: "Chat"
---

Internal chat inside an academy: one-to-one conversations and office-managed groups, with plain-text messages,
up to three file attachments, read pointers and read counts. Admins, staff, teachers and students can be in chat;
parents never are. The office (admins, staff with codes) manages groups, per-student chat switches and a
moderation list where it can edit or delete any message. Delivery is by polling (no websockets); an
in-app-only `chat.unread` notice reminds people of messages left unread (see [notifications.md](notifications.md)).

## Concepts

Models in `etqan/chat/models.py` (the only foreign model referenced is the user):

| Model | Key fields | Notes |
|---|---|---|
| `Conversation` | `kind` (`direct`/`group`), `name`, `direct_key`, `created_by`, `last_message_at`, `image` | A direct one has `direct_key = "<min_id>:<max_id>"` (unique), so a pair has exactly one conversation even under a race. Groups have a name and optional image. |
| `Participant` | `conversation`, `user`, `joined_at`, `last_read_message_id` | Unique per (conversation, user). The read pointer is a message id, never a time; it only moves forward. |
| `Message` | `conversation`, `sender` (SET_NULL), `body`, `created_at`, `deleted_at`, `edited_at`, `edited_by` | A delete is soft: stamps `deleted_at` and clears `body`; office edits stamp `edited_*`. |
| `Attachment` | `message`, `file`, `name`, `size`, `content_type` | Private storage (`chat/files.py:private_storage`), tenant-scoped path. |
| `ChatAccess` | `user` (1:1), `chat_enabled`, `can_start` | A student's two switches. No row: both on. |

## How it works

**Who is in chat** (`services/access.py`): active users with role `admin`, `staff`, `teacher` or `student`;
a student only while `chat_enabled`. `switches(user)` returns (in chat, may start). Out-of-chat users get a
403 from the `InChat` permission; `GET chat/me/` never 403s and answers `in_chat: false` instead.

**Who may start with whom** (`services/conversations.py:allowed_ids`, `contacts`, `start_direct`):

| Starter | May reach |
|---|---|
| admin | everyone in chat |
| staff | admins and staff; teachers/students only with `teacher.view_any` / `student.view_any` |
| teacher | admins, staff, and students they teach (subscription `active` or `paused`) |
| student (with `can_start`) | admins, staff, and their current teachers |

`start_direct` returns the existing conversation for the pair, else creates it with two participants (201 vs 200).

**Visibility.** `conversations_of(user)` lists the user's conversations by `last_message_at`; a direct one whose
other participant is out of chat is hidden. Sending into a direct conversation whose other side is out of chat
is a 409 `chat.recipient_unavailable`.

**Messages** (`services/messages.py`):
- `send`: body 1–4000 chars after trimming, or 0–4000 when files are attached; ≤ 3 files, ≤ 10 MB each, types
  PDF / images / Office / txt / audio (`chat/files.py:ATTACHMENT_TYPES`). Files are written inside the
  transaction and removed if it fails. Updates `last_message_at` and moves the sender's own pointer.
- `page`: newest first, 50 per page, `before=<id>` for older.
- `mark_read(up_to)`: max-merge of the pointer (never goes backward). While impersonating nothing is written.
- `read_counts`: for the sender's own messages, how many other participants' pointers reached each message.
- `delete` (sender) / `remove` / `remove_many` (office, ≤ 100): soft delete; attachments and their files go on commit.
- `edit` (office): body may be empty only when the message has files; a deleted message is a 409.
- Unread: `unread_by_conversation`, `total_unread` — others' live messages above the user's pointer.

**Groups** (`services/groups.py`): office-created; name ≤ 120, 1–200 participants, each new participant must be in
chat. `delete_group` cascades messages and files. Group image: png/jpg/webp ≤ 2 MB, re-encoded
(`set_image`, `remove_image`); readable by members and the office (`image_file`). Group list filters by
created date (academy days, `services/days.py`).

**Moderation** (`services/moderation.py:messages_list`): every message, newest first, with sender and receiver
types (`student`, `teacher`, `supervisor` = staff, `admin`; sender may be `removed`, receiver of a group is
`all`), attachment counts and read counts; filters `sender_type`, `receiver_type`, `date_from`, `date_to`.

**Unread notice** (`services/notices.py:unread_digest`): per student/teacher participant with live unread messages
from others older than the type's `value` minutes (default 15, 5–720) and within 24 h. The finder
`notifications/finders.py:chat_unread` uses the read pointer as the occurrence, so a person is told at most once
per pointer position. Office roles are not told. The notice is in-app (and web push) only; its link is
`/chat?c=<conversation id>`.

## API

All under `/api/v1/chat/`, feature `internal_chat` (except `me/`). Writes by an impersonated session are refused
(`NotImpersonating`) on POST/DELETE of conversations, messages and office edits.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/chat/me/` | any signed-in | `{in_chat, can_start, unread}`; all false/0 while the feature is off |
| GET | `/api/v1/chat/contacts/?q=` | in chat | People the caller may start with |
| GET, POST | `/api/v1/chat/conversations/` | in chat | List own conversations / start a direct one `{user}` |
| GET, POST | `/api/v1/chat/conversations/<id>/messages/` | participant | Page (`before`) / send (JSON or multipart with `files`) |
| POST | `/api/v1/chat/conversations/<id>/read/` | participant | `{up_to}`; 204 |
| GET | `/api/v1/chat/attachments/<id>/` | participant, or `conversation.view_any` | Download |
| GET, POST | `/api/v1/chat/groups/` | `conversation_group.view_any` / `.create` | List (created-date filter) / create |
| GET, PATCH, DELETE | `/api/v1/chat/groups/<id>/` | `conversation_group.view` / `.update` / `.delete` | Group detail / rename, change members / delete |
| GET, PUT, DELETE | `/api/v1/chat/groups/<id>/image/` | GET: members or `conversation_group.view` / `conversation.view_any`; writes: `conversation_group.update` | Group image |
| GET, PATCH | `/api/v1/chat/access/<user_id>/` | `student.view` / `student.update` | A student's `chat_enabled`, `can_start` (non-student → 404) |
| GET | `/api/v1/chat/messages/` | `conversation.view_any` | Moderation list with filters |
| PATCH | `/api/v1/chat/messages/<id>/` | `conversation.update` | Office edit |
| DELETE | `/api/v1/chat/messages/<id>/` | sender, or `conversation.delete` | Soft delete |
| POST | `/api/v1/chat/messages/bulk-delete/` | `conversation.delete_any` | `{ids}` (1–100) |

Message payloads (`api/payloads.py:message_row`) hide `body` of deleted messages, show `read_count` only on the
viewer's own messages, and flag `edited_by_office`.

## Dashboard

| Route | Component (`dashboard/src/features/chat/`) | Gate |
|---|---|---|
| `routes/_authed/chat.tsx` (`/chat?c=<id>`) | `ChatPage`, `ConversationList`, `Thread`, `ContactsPicker` | feature `internal_chat`; page shows a notice when `me.in_chat` is false |
| `routes/_authed/people.chat-groups.tsx` | `GroupsPage`, `GroupDialog` | `conversation_group.view_any` |
| `routes/_authed/people.messages.tsx` | `MessagesModerationPage` | `conversation.view_any` |
| `routes/_authed/people.students.$personId.tsx` | `StudentChatCard` | student's chat switches |

Polling (`features/chat/queries.ts`): `chat/me/` every 60 s for the nav badge (`chatUnread` in
`features/shell/nav.ts`), every 15 s while `/chat` is open; the open thread every 10 s. Intervals pause while the
tab is hidden. The Chat nav item is dropped unless `me/` says `in_chat`. Translations:
`dashboard/src/locales/<lng>/chat.json`.

## Background jobs

None in the chat app. The `chat.unread` notice is produced by the notifications scan (`notifications.scan`, every
minute) through `chat.services.unread_digest`.

## Configuration

- Feature `internal_chat` (built, default off).
- Notice setting `chat.unread` (on/off, delay in minutes) in Settings → Academy; also gated by `internal_chat`.
- Permission codes: `conversation.view_any`, `conversation.update`, `conversation.delete`, `conversation.delete_any`,
  `conversation_group.view_any|view|create|update|delete`, `student.view|update` (switches).

## Code map

- `backend/etqan/chat/models.py`, `files.py` (upload rules, private storage, on-commit file removal).
- `backend/etqan/chat/services/` — `access.py`, `conversations.py`, `messages.py`, `groups.py`, `moderation.py`, `attachments.py`, `days.py`, `notices.py`; `__init__.py:me`.
- `backend/etqan/chat/api/` — `views.py`, `permissions.py` (`InChat`, `GroupImageRead`, `SenderOrCode`), `payloads.py`.
- `dashboard/src/features/chat/`.

## Design history

- [B5 communication phase](../superpowers/specs/2026-10-07-b5-communication-design.md) — B5-10 (switches in chat-owned tables), parents not in chat.
- [B5e chat core](../superpowers/specs/2026-10-07-b5e-chat-design.md) — conversations, groups, read state, polling (E-1…E-14). E-7 (plain text only) amended by B5f.
- [B5f chat extras](../superpowers/specs/2026-10-08-b5f-chat-extras-design.md) — attachments, group images, moderation, created-date filter; moves the chat notice to B5d.
- [B5d more notices](../superpowers/specs/2026-10-07-b5d-more-notices-design.md) — D-CHAT addendum: `chat.unread`.
- Plans: [plan 44](../superpowers/plans/2026-10-07-plan-44-chat.md), [plan 58](../superpowers/plans/2026-10-08-plan-58-chat-extras.md).
