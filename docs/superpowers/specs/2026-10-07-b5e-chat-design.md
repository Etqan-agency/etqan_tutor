# Slice B5e — Internal chat (core) — Design

**Date:** 2026-10-07
**Status:** Self-approved after an independent spec review (orchestration PO-3); review findings applied 2026-10-07.
**Phase spec:** `2026-10-07-b5-communication-design.md` §3, which is amended here to split the old B5e row:
- **B5e, chat core** (this spec): conversations, groups, messages, read state, student switches, polling,
  unread badge.
- **B5f, chat extras** (later spec): attachments and group images; the office's moderation list (view, edit,
  delete and bulk delete any message; filters for sender / receiver type and dates); the groups' created-date
  filter; chat notices.

Decisions B5-1…B5-13 bind both slices. The split keeps each slice within one plan; B5e is M–L because it
creates a whole new app, and B5f is M.
**Evidence:** P1 COMM-001, COMM-002, BR-43, §5.1–5.4, §19 (realtime UNKNOWN); TH §2.1 PEOPLE-001 preferences,
§2.7 COMM-001/002, SYS-002. R7 is dropped (D1).
**Requires:** nothing unmerged. The app is new and reads only `identity.services` and `scheduling.services`.

## 1. Goal

Students, teachers and the office talk inside the academy:
- one-to-one conversations;
- groups the office sets up;
- a conversation list with unread counts;
- a nav badge.

The office can bar a student from chat, or from starting conversations. Parents are not in chat, as on TH.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| E-1 | **A new tenant app, `etqan.chat`**, added to `TENANT_APPS` under the B5 marker.<br>• Its import contract: it may import `etqan.platform`, `identity.services` and `scheduling.services`; it is forbidden other apps' `models` and `api`, and `etqan.notifications`.<br>• A second contract, "no app imports `etqan.chat`". Its only planned exception is B5f's `etqan.notifications -> etqan.chat.services`.<br>• `etqan.chat` is added to the existing per-app `forbidden_modules` lists in `pyproject.toml` that enumerate apps, including the platform contract's list. | B5-1, B5-2 |
| E-2 | **Who is in chat:** admins, staff and teachers, plus students whose `chat_enabled` is on. P1's "supervisor" (مشرف) is a staff account (the `SUPERVISOR` access preset; `Subscription.supervisor` is a staff user). **Parents are never in chat** (403 on every chat route). Inactive users are never in chat. | P1 §5.4 (sender/receiver types student · teacher · supervisor · admin; parents absent); BR-43 |
| E-3 | **Per-student switches (BR-43):**<br>• `chat_enabled`: the student is in chat at all;<br>• `can_start`: the student may start a one-to-one conversation.<br>Both default **on** [assumed]. They live in `chat.ChatAccess(user one-to-one)`, B5-owned (B5-10), and no row means both on. The office sets them on the student's page (`student.view` to see, `student.update` to change). | TH §2.1 PEOPLE-001; P1 BR-43 |
| E-4 | **Who may start a one-to-one with whom** [assumed; the teacher and student panels are unobserved, TH U2]. "Office" means admins and staff.<br>• **Admins:** anyone in chat.<br>• **Staff:** the office always. Teachers only with `teacher.view_any`, and students only with `student.view_any`. That keeps Plan 12's rule that staff reach only what their codes allow.<br>• **A teacher:** the office, and **their students**. That is a student with a subscription with that teacher whose status is `active` or `paused`, in any course; archived rows count (D14). It is read as `scheduling.services.subscriptions_queryset().filter(teacher__user_id=…, status__in=("active", "paused")).values_list("student__user_id")`. This is B6-5's rule without the course. Chat may not import learning, so it is a deliberate re-implementation and B6's `teaches` stays B6's.<br>• **A student with `can_start` on:** the office and their teachers, by the same rule.<br>Starting a conversation with someone you already have a one-to-one with returns the existing one (200, not 201). | spec 2026-10-05-b6 B6-5; ledger D14; Plan 12 R-5 · [assumed] |
| E-5 | **Replying.** Anyone who is a participant and is in chat may post in an existing conversation, even after the start rule stops holding: a past teacher, or a student whose `can_start` is now off [assumed]. A **direct message to someone not in chat** (chat off, parent, inactive) is **409 `chat.recipient_unavailable`**. In a group, such a person keeps their participant row but is left out of the list, the unread counts and the contacts until they are back in chat. | [assumed]; review |
| E-6 | **Chat groups (COMM-002)** are made and managed by the office only, with `conversation_group` codes. The fields are name\* and participants; the image comes in B5f. TH's form has name\*, image and a participants repeater.<br>• The creator is added as a participant by default and may be removed.<br>• At least one participant is required, and every participant must be in chat (400 `participant_ids`).<br>• Every participant may read and post. Joiners see the history, with their read pointer set to the latest message at join.<br>• A removed participant loses access to the group, past messages included.<br>• Deleting a group deletes its messages. | P1 COMM-002; TH COMM-002 · [assumed] |
| E-7 | **Messages:**<br>• plain text, 1–4000 characters after trimming;<br>• no edit by the sender: P1 COMM-001 gives viewing, editing and deleting "all messages" to the office, which is B5f;<br>• the sender may delete their own message (`deleted_at` stamped, body cleared), and everyone then sees "Message deleted" in its place, including as the list's last-message excerpt.<br>Attachments are B5f. | P1 COMM-001 ("يمكن عرض جميع الرسائل … وتعديلها، وحذفها") · [assumed] sender delete |
| E-8 | **Read state by message id, not time.**<br>• Each participant has `last_read_message_id`, null meaning nothing read. `POST read/ {up_to}` keeps the larger of the stored and the given id; the id must belong to the conversation.<br>• Unread for a person = messages from others in their conversations with `id > last_read_message_id`, not deleted.<br>• **Read count** of a message = participants other than the sender with `last_read_message_id >= id`. Only the sender sees it.<br>• **Opening a chat while impersonating changes nothing:** `read/` answers 204 without writing (D19). | P1 COMM-001 (read count); ledger D19; review |
| E-9 | **Polling, no websockets** [assumed: realtime is UNKNOWN on TH]. Every poll pauses while the tab is hidden (`document.visibilityState`).<br>• **The open thread** re-fetches its newest page (≤ 50 messages) every 10 s. New messages, read counts and deletions on that page all refresh in one request; older pages are fetched once.<br>• **`GET me/`** returns `{in_chat, can_start, unread}`. It is polled every 60 s for the nav badge (D27), and every 15 s while `/chat` is open. The conversation list re-fetches only when `unread` changes, or after the user's own action.<br>• Every chat endpoint has a fixed query cap, asserted in tests. | P1 §19; ledger D27 |
| E-10 | **Guard on messaging:** starting a conversation, sending and deleting add `NotImpersonating` (D19). | ledger D19 |
| E-11 | **Switch `internal_chat`**: the registry's `_later` line, flipped in place to built, off by default. While it is off:<br>• every chat route answers 404 after the role check;<br>• the nav item, the badge and the student chat card are hidden;<br>• the groups page is hidden.<br>Data is kept. | B5-3; TH SYS-002 "internal chat (paid)" |
| E-12 | **Access resource** `conversation_group` ("Chat groups" / "مجموعات المحادثة"), with `view_any`, `view`, `create`, `update` and `delete` in use. No access preset (Supervisor included) gets these codes [assumed]. The office's own one-to-one chat needs no code (E-4 limits staff reach). | P1 permission keys `conversation`, `conversation::group` |
| E-13 | **Receiver-type vocabulary**, so B5f's moderation filters can match TH's sender / receiver types (student · teacher · supervisor · admin · all):<br>• the sender type is the sender's role (`staff` shows as "supervisor");<br>• the receiver type of a direct message is the other participant's role;<br>• the receiver type of a group message is **all** (الجميع) [assumed: TH's sample row "a student → all" reads as a message to a group]. | TH §2.7 COMM-001 (filters, seen row) · [assumed] |
| E-14 | **Pages:**<br>• conversations are ordered by `last_message_at` descending, 20 per page;<br>• messages come newest-first, 50 per page, with `?before=<id>` for older ones;<br>• the poll is the newest page (E-9).<br>A page answer includes `has_more`. | [assumed] |

## 3. Data (`etqan.chat`, new tables only)

```text
Conversation
  kind             CharField(8: direct | group)
  name             CharField(120, blank)            # groups
  direct_key       CharField(40, null, unique)      # "<min_user_id>:<max_user_id>" for direct, null for groups
  created_by       FK User SET_NULL null related_name="+"
  created_at, updated_at
  last_message_at  DateTimeField(null, db_index)
Participant
  conversation         FK Conversation CASCADE related_name="participants"
  user                 FK User CASCADE related_name="+"
  joined_at            default now
  last_read_message_id BigIntegerField(null)
  unique (conversation, user); index (user, conversation)
Message
  conversation     FK Conversation CASCADE related_name="messages"
  sender           FK User SET_NULL null related_name="+"
  body             TextField
  created_at       default now
  deleted_at       DateTimeField(null)
  index (conversation, id)
ChatAccess
  user             OneToOne User CASCADE related_name="+"
  chat_enabled     Boolean default True
  can_start        Boolean default True
```

A direct conversation is created inside `transaction.atomic()`, and the unique `direct_key` makes the pair
unique. On `IntegrityError` the service re-reads the existing conversation and returns it (200). This is tested
deterministically by creating the row in between.

## 4. API (`/api/v1/chat/`; `config/api_router.py` under the B5 marker)

| Method & path | Who | What |
|---|---|---|
| `GET me/` | any signed-in user | `{in_chat, can_start, unread}`; a parent or anyone out of chat gets `{in_chat: false, can_start: false, unread: 0}`, never a 403. This is self-service: the dashboard asks it before anything else. |
| `GET conversations/` | in chat | Their conversations: id, kind, title (the other person's name or the group's name), last message excerpt (or "deleted") and time, unread count |
| `POST conversations/` | E-4 (+ NotImpersonating) | `{user}` → the direct conversation (201 new, 200 existing); 400 `user` when not allowed |
| `GET conversations/<id>/messages/` | participants in chat | `?before=` pages, newest first: id, sender {id, name, role}, body (null if deleted), created_at, deleted, read_count (own messages only), plus `has_more` |
| `POST conversations/<id>/messages/` | participants in chat (+ NotImpersonating) | `{body}` → the message; bumps `last_message_at`; 409 `chat.recipient_unavailable` per E-5 |
| `POST conversations/<id>/read/` | participants in chat | `{up_to}` → 204 (no write while impersonating) |
| `DELETE messages/<id>/` | the sender (+ NotImpersonating) | Soft delete |
| `GET contacts/` | in chat | Whom they may start with (E-4), active users only, `?q=` search, 20 per page |
| `GET/POST groups/`, `GET/PATCH/DELETE groups/<id>/` | `conversation_group.view_any / create / view / update / delete` | Office group management: name, `participant_ids` |
| `GET/PATCH access/<user_id>/` | `student.view` / `student.update` | A student's two switches; any other target → 404 |

Out of chat (a parent, a student with chat off, an inactive user): 403 on every route but `me/`. A conversation
the caller is not in: 404. Every route is under `FeatureOn("internal_chat")` after the role check.

## 5. Screens (dashboard; code in `src/features/chat/`, strings in a new area `locales/{en,ar}/chat.json`)

| Who | Where | What |
|---|---|---|
| Admin, staff, teacher, student in chat | **Chat** `/chat`: a top-level nav item placed right after Home; `requiresRole` admin · staff · teacher · student; `internal_chat`; shown only when `me.in_chat` | Two panes:<br>• conversations, with search and an unread dot;<br>• the open thread: an older-messages loader, a composer (Enter sends, Shift+Enter adds a new line), delete on your own messages, and read counts on your own messages.<br>"New conversation" opens the contacts picker; it is hidden when `can_start` is false. On a phone the panes stack. |
| Same | **Nav badge** `chatUnread` (D27) | A new `NavBadge` key `chatUnread`, with its `NAV_BADGE_LABELS` entry `chat.badge`, wired in `AppShell.tsx` with a `useChatUnread` hook. That is an edit outside the phase markers, as D27 anticipates. The hook reads `me/` and is disabled while `internal_chat` is off. Sending and `read/` invalidate it. |
| Office | **People → Chat groups** `/people/chat-groups` (`conversation_group.view_any`, `internal_chat`) | A list (name, participant count, last activity); an add / edit dialog (name, participants multi-picker of users in chat); delete with a confirm. |
| Office | **Student detail → Chat** card (`student.view`, edit with `student.update`, `internal_chat`) | "Chat enabled" and "Can start conversations" switches. One mount line, as B5a's preferences card. |

## 6. Tests

- **Backend:**
  - the E-4 matrix: each role pair, staff with and without codes, a student without `can_start`, chat off, a
    parent, an inactive user;
  - a past teacher: a new start is refused, a reply is allowed (E-5);
  - E-5's 409;
  - `direct_key` uniqueness, including the simulated race returning 200;
  - groups: creator added, validation, joiner's pointer, removal hides history, delete cascades;
  - messages: send, pages, soft delete, the deleted excerpt;
  - read state: unread, read count, `up_to` max-merge, no write while impersonating;
  - `NotImpersonating` on start, send and delete;
  - `me/` for every role;
  - the switch 404 after the role check; parents 403;
  - query caps on `me/`, `conversations/`, `messages/` and `contacts/` for 1 vs many rows;
  - the import contracts.
- **Dashboard:**
  - the chat panes, sending and Enter handling;
  - thread polling with fake timers, paused while hidden;
  - delete;
  - the contacts picker and the `can_start` rule;
  - the nav item and badge depending on `me`;
  - the groups page;
  - the student chat card.
- **e2e** `e2e/b5-chat.spec.ts`:
  1. an admin starts a conversation with a stamped student and sends a message;
  2. the student sees the badge, opens the conversation and replies;
  3. within one poll the admin sees the reply, and a read count of 1 on their own message.

## 7. Non-goals (B5e)

- Attachments and group images, the office moderation list and its filters, the groups' created-date filter,
  and chat notices (all B5f).
- Typing indicators, reactions, message search, websockets.
- Parents in chat.
- An academy-wide "everyone" conversation: TH's "all" receiver type is read as a group message (E-13).
