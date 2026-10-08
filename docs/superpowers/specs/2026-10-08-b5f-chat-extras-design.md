# Slice B5f — Chat extras — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (orchestration PO-3); review findings applied 2026-10-08.
**Phase spec:** `2026-10-07-b5-communication-design.md` §3 (B5f row). This spec moves the chat notice to B5d, with
its own addendum in the B5d spec. It builds on B5e (`2026-10-07-b5e-chat-design.md`, E-1…E-14) and **amends E-7**
(F-3).
**Evidence:**
- P1 COMM-001: the office can view, edit and delete all messages. Columns include attachments and read count;
  filters cover sender type, receiver type and created dates; bulk delete.
- P1 COMM-002: group image; created-date filter.
- Ledger D2 and D12 (uploads); D19.
- B6's private-file precedent (`etqan.learning.files`).

R7 is dropped (D1).
**Requires:** B5e (merged before building).

## 1. Goal

This slice completes TutorHamster's chat:
- files on messages and an image on groups, private and scoped;
- the office's moderation list across every conversation, with edit, delete and bulk delete.

Everything sits behind `internal_chat`.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| F-1 | **Attachments.** A message may carry up to 3 files of 10 MB each, of exactly these types:<br>• images `png`, `jpg`, `jpeg`, `webp`, re-encoded by Pillow;<br>• PDF;<br>• office documents;<br>• `txt`;<br>• audio.<br>That is `HOMEWORK_TYPES`'s set: no GIF, HTML or SVG (D2). Files are validated with `platform.uploads.check_upload` and stored on `STORAGES["private"]` under `tenant_upload_path("chat")`. `chat.Attachment` has: message FK (CASCADE), file, original name (120), size, content type, created_at. They are not gated by `file_uploads` (as B6 homework). | P1 COMM-001; D2, D12; B6-7 |
| F-2 | **Download** `GET /api/v1/chat/attachments/<id>/`:<br>• **Who:** participants of the conversation who are in chat, and the office with `conversation.view_any`.<br>• **Order of checks:** out of chat → 403, as every chat route (B5e §4); then `FeatureOn`; then not a participant and without the code → 404.<br>• **Response:** streamed with `Content-Disposition: attachment` (images `inline`), `X-Content-Type-Options: nosniff`, `Cache-Control: private, no-store`, following `learning.files`. | B5e §4; B6 precedent |
| F-3 | **Amends B5e E-7.**<br>• **Body rule:** a message may be **files only**. The body is 0–4000 characters after trimming when at least one file is attached, and 1–4000 otherwise. `SendInput` and `messages._clean` change accordingly.<br>• **Send order:** the recipient is checked (409 `chat.recipient_unavailable`) **before** any file is stored. Files are written inside the transaction, and an on-commit-failure cleanup removes them on rollback.<br>• **Excerpt:** the last-message excerpt gains `attachment_count`, and a files-only message shows "📎 n files" in the list (a translated label, computed client-side). | review I-6, I-8 |
| F-4 | **Deleting removes the files.**<br>• Deleting a message (by the sender or the office) deletes its `Attachment` rows and, on commit, their files. A deleted message shows 0 attachments.<br>• Deleting a group (E-6 cascade) collects every attachment file and the group image first, and removes them on commit.<br>• Replacing or removing a group image removes the old file on commit.<br>• The on-commit helper is `chat.files.remove_after_commit(names)`. Chat may not import learning, so it is re-implemented in chat (a small function). | review I-8; `learning.files.remove_after_commit` |
| F-5 | **Group image**: one optional image (PNG, JPEG or WEBP, ≤ 2 MB, re-encoded).<br>• **Routes:** `GET/PUT/DELETE /api/v1/chat/groups/<id>/image/`.<br>• **GET:** participants in chat, `conversation_group.view` or `conversation.view_any`.<br>• **PUT and DELETE:** `conversation_group.update`, plus `NotImpersonating`.<br>• **Payloads:** the group row and conversation rows gain `has_image` and `image_version` (`updated_at`), so the client can cache. | P1 COMM-002; review M-2 |
| F-6 | **Office moderation list (COMM-001).** The page is **People → Messages**, `/people/messages` (nav under the B5 marker, `conversation.view_any`, `internal_chat`). The API is `GET /api/v1/chat/messages/`: every message, newest first, 25 per page.<br>**Each row:** id, conversation id, the full body (null if deleted), sender {name, type}, receiver {type, name}, `attachment_count`, `read_count`, created_at, `edited_at`, `deleted`.<br>**Filters:**<br>• `sender_type`: student · teacher · supervisor (staff) · admin · removed (null sender);<br>• `receiver_type`: student · teacher · supervisor · admin · all (group), per B5e E-13;<br>• `from` / `to`: academy days, inclusive, as B5b's log.<br>**Queries:** a fixed number. `read_count` comes from a new general `messages.read_counts_for(messages)` (any sender, one query). | P1 COMM-001; B5e E-13; review M-7..M-9 |
| F-7 | **Office edit and delete.** A new access resource, `conversation` ("Chat messages" / "رسائل المحادثات"), with `view_any`, `update`, `delete` and `delete_any`. No preset gets them [assumed].<br>`messages/<id>/` serves both the sender and the office:<br>• **PATCH** (office, `conversation.update`, `NotImpersonating`) edits the body. It stamps `edited_at` and `edited_by`, and participants see "edited by the office". The body may be empty only if the message has files. A deleted message → 409 `chat.message_deleted`.<br>• **DELETE** (the sender, or the office with `conversation.delete`; `NotImpersonating`) soft-deletes (E-7) and removes the files (F-4). Anyone else gets 404.<br>• **Bulk delete:** `POST messages/bulk-delete/ {ids}` (`conversation.delete_any`, `NotImpersonating`), at most 100 ids (400 above). It soft-deletes them all and removes their files on commit. | P1 COMM-001 ("view, edit and delete all messages", bulk delete); D19 |
| F-8 | **Groups' created-date filter** (COMM-002): the office groups list takes `created_from` / `created_to` (academy days, inclusive). | P1 COMM-002 |
| F-9 | **Message API additions.**<br>• `POST conversations/<id>/messages/` accepts JSON or multipart: `body` and repeated `files` (`parser_classes = [MultiPartParser, JSONParser]`).<br>• The message payload gains `attachments: [{id, name, size, content_type}]` and `edited_by_office`.<br>• Attachments are prefetched, so B5e's query caps hold (one extra query per page). | review I-7 |
| F-10 | **Dashboard.**<br>• **Composer:** attach files (chips with remove; per-file and count limits checked client-side too).<br>• **Thread:** images are shown inline through authenticated blob URLs, **cached in memory by attachment id**, with object URLs revoked on unmount, so 10 s polls do not download them again. Other files appear as a download link.<br>• **Group dialog:** the image field.<br>• **Moderation page:** the filters, an edit dialog (full body), delete, and bulk delete with row checkboxes and a confirm.<br>• **Strings:** in `chat.json` (en/ar). | review M-4 |
| F-11 | **Schema** (one chat migration, additive, B5-10):<br>• the `Attachment` table;<br>• `Message.edited_at` and `Message.edited_by` (SET_NULL);<br>• `Conversation.image`, a private file field, null;<br>• an index on `Message.created_at` for the list's date filters. | B5-10 |

## 3. Tests

- **Attachments:**
  - upload validation: each allowed type, GIF and SVG refused, size, count, signature;
  - files-only messages, with an empty body allowed only with files;
  - recipient-unavailable stores no file;
  - rollback cleanup;
  - download scoping (participant, office code, out of chat 403, outsider 404, removed participant 404) and headers;
  - files deleted with their message, with their group, and on image replace.
- **Group image:** set, replace and remove; scoped GET; `NotImpersonating`.
- **Moderation list:** each filter (types, removed sender, dates in a non-UTC academy); `read_counts_for`; full body; deleted rows; fixed query count.
- **Edit and delete:** office edit, including on a deleted message and an empty body with and without files; sender vs office delete; bulk delete ≤ 100; codes; `NotImpersonating`.
- **Dashboard:** composer attachments; thread rendering and the blob cache (no refetch on poll); group image; the moderation page.
- **e2e** `b5-chat-extras.spec.ts`: a student sends a PDF to the admin; the admin opens People → Messages, sees it with an attachment count of 1, and deletes it.

## 4. Non-goals

- The chat notice (moved to B5d, addendum D-CHAT).
- Message search beyond the filters.
- Reactions and typing indicators.
- Virus scanning beyond the signature check.
- Parents in chat.
