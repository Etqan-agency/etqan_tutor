# Plan 58 — B5f Chat extras — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chat gains private file attachments, a group image, and the office's moderation list (view, edit, delete, bulk delete) across all messages.

**Architecture:**
- Everything is in `etqan.chat` (B5-owned).
- A new `chat/files.py` follows `learning/files.py`: storage, attach, bounded names and on-commit removal. It is re-implemented, because chat may not import learning.
- New services `attachments.py` and `moderation.py`.
- Changes to `messages.py`: files-only messages and file cleanup on delete.
- One chat migration.
- The dashboard extends `features/chat/`.

**Tech Stack:** Django 5 + DRF (multipart), private storage, Pillow re-encode via `platform.uploads`, pytest; React + TanStack, vitest; Playwright.

**Spec:** `docs/superpowers/specs/2026-10-08-b5f-chat-extras-design.md` (F-1…F-11; it amends B5e E-7), with `docs/superpowers/specs/2026-10-07-b5e-chat-design.md`.

**Requires:** B5e (merged before Task 1).

## Global Constraints

- **Attachment types:** `{.png, .jpg, .jpeg, .webp} | uploads.PDF | uploads.OFFICE | {.txt} | uploads.AUDIO`. At most 3 files per message, 10 MB each. Images are re-encoded.
- **Group image:** PNG, JPEG or WEBP, ≤ 2 MB, re-encoded.
- **Storage:** private, under `tenant_upload_path("chat")`. Downloads carry `Content-Disposition` (images inline), `X-Content-Type-Options: nosniff` and `Cache-Control: private, no-store`.
- **Body rule (amends E-7):** 1–4000 characters after trimming, or 0–4000 when at least one file is attached.
- **Access resource** under `# ── phase B5 ──`: `Resource("conversation", "Chat messages", "رسائل المحادثات", ("view_any", "update", "delete", "delete_any"))`. No preset gets it.
- **Office writes** (edit, delete, bulk delete, image put/delete) add `NotImpersonating`. Bulk delete takes ≤ 100 ids (400 above). Editing a deleted message → 409 `chat.message_deleted`.
- **Error ordering:**
  - out of chat → 403;
  - then `FeatureOn("internal_chat")` → 404;
  - then a non-participant without a code → 404.
- **Migration:** one chat migration adding `Attachment`, `Message.edited_at`, `Message.edited_by` (SET_NULL), `Conversation.image` (nullable private file field), and `Index(Message.created_at)`.
- **Dashboard:**
  - code in `src/features/chat/`, strings in `chat.json` (en/ar equal);
  - nav `/people/messages` under the B5 marker (`conversation.view_any`, `internal_chat`);
  - the image blob cache is keyed by attachment id, with object URLs revoked on unmount.
- **Coverage:** backend ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- **Tools:** from the meta root, `S() { (set -a; . ./.env.stream; set +a; docker compose -f docker-compose.local.yml exec -T "$@"); }`; `S django pytest etqan/chat etqan/access -q`; ruff; `lint-imports`; `just _stack-manage makemigrations chat --name extras`; `just migrate`; dashboard vitest, tsc and lint; `just e2e e2e/b5-chat-extras.spec.ts`.

## Review Focus

1. A 409 `chat.recipient_unavailable` send leaves no file in storage, and a rolled-back send removes the files it wrote. Task 2 tests both.
2. A removed group participant gets 404 on every attachment of that group, and a parent gets 403. Task 2 tests both.
3. Deleting a group removes every attachment file and the group image from storage. Task 3 tests it.
4. The thread does not download an image again on each 10 s poll. Task 5 tests it.
5. The moderation list's `read_count` is right for any sender, in one query. Task 4 tests it.

---

### Task 1: Files module, model and migration

**Files:**
- Create: `backend/etqan/chat/files.py` (`ATTACHMENT_TYPES`, `IMAGE_TYPES`, `private_storage()`, `bounded_name()`, `attach(...)`, `remove_after_commit(names)`), mirroring `learning/files.py` without importing it.
- Modify: `chat/models.py` (`Attachment(message FK CASCADE related_name="attachments", file FileField(storage=private, upload_to=chat path), name CharField(120), size PositiveIntegerField, content_type CharField(100), created_at)`; `Message.edited_at`, `edited_by`; `Conversation.image` with `Index(fields=["created_at"])` on Message).
- Create: the migration; `tests/test_files.py`.

- [ ] **Tests (RED):** `attach` validates (allowed types, GIF and SVG refused, size, signature) and re-encodes images; `remove_after_commit` deletes on commit and not on rollback.
- [ ] **Implement, migrate, run, commit** `feat(chat): private files module and attachment model (B5f)`.

### Task 2: Sending with attachments and downloading

**Files:** `services/messages.py` (send with files, files-only rule, recipient check before storage, rollback cleanup; delete removes attachment rows and files; the payload carries attachments and `edited_by_office`), new `services/attachments.py` (`download(user, attachment_id) -> (file, name, content_type)` with the scoping), `api/views.py` (multipart on `POST conversations/<id>/messages/`; `AttachmentView`), `api/payloads.py`, `api/urls.py`, the `test_routes` entries, and tests.

- [ ] **Tests (RED):**
  - send with 1–3 files and with 4 (400);
  - a files-only message;
  - an empty body without files (400);
  - Review Focus 1;
  - download as a participant, as the office with the code, as out of chat (403), as an outsider (404) and as a removed participant (404);
  - headers;
  - message delete removes files;
  - message page query cap with attachments (+1 query).
- [ ] **Implement, run, commit** `feat(chat): attachments on messages with scoped downloads (B5f)`.

### Task 3: Group image and cascade cleanup, groups' date filter

**Files:** `services/groups.py` (`set_image`, `remove_image`; `delete_group` collects attachment and image files and removes them on commit; `list_groups(created_from, created_to)`), views and urls (`groups/<id>/image/` GET, PUT, DELETE; filters on `groups/`), payloads (`has_image`, `image_version` on group and conversation rows), and tests.

- [ ] **Tests (RED):** image set, replace (old file removed) and remove; GET scoping; `NotImpersonating`; Review Focus 3; the date filter in a non-UTC academy.
- [ ] **Implement, run, commit** `feat(chat): group image, cleanup on delete, created-date filter (B5f)`.

### Task 4: Office moderation API

**Files:** new `services/moderation.py` (`messages_list(filters)` and `read_counts_for(messages)`, one query), `messages.py` (office edit with `edited_*`; office delete), views (`GET chat/messages/`; `PATCH/DELETE messages/<id>/` serving the sender's delete and the office's edit and delete; `POST messages/bulk-delete/`), the registry resource, `test_routes` (ROUTES, FEATURES, words), and tests.

- [ ] **Tests (RED):**
  - list rows and filters (sender and receiver types including `removed` and `all`, dates);
  - Review Focus 5;
  - fixed query count;
  - office edit, including on a deleted message (409) and an empty body with and without files;
  - sender vs office delete;
  - bulk delete ≤ 100 and 101 (400);
  - codes per method;
  - `NotImpersonating`.
- [ ] **Implement, run, commit** `feat(chat): office moderation list, edit and bulk delete (B5f)`.

### Task 5: Dashboard

**Files:** `features/chat/` (composer file chips; the thread's attachment rendering with an image blob cache hook `useAttachmentUrl(id)`; group dialog image; new `MessagesModerationPage.tsx` with filters, an edit dialog, delete and bulk delete), route `routes/_authed/people.messages.tsx`, nav under `// ── phase B5 ──` plus the enumeration tests, `chat.json` en/ar, and tests.

- [ ] **Tests (RED):**
  - composer attach, remove and client-side limits;
  - a files-only send;
  - images rendered inline from a blob, with no re-fetch on rerender or poll (Review Focus 4);
  - a download link for other files;
  - the group image upload;
  - the moderation page: filters, edit, delete, bulk delete with confirm, and gating by codes.
- [ ] **Implement, then run** vitest, tsc and lint.
- [ ] **Commit** `feat(chat): attachments, group image and the moderation page (B5f)`.

### Task 6: e2e and gates

- [ ] `e2e/b5-chat-extras.spec.ts`:
  1. a stamped student and the admin are in chat;
  2. the student sends a PDF (a small fixture file in `e2e/fixtures/`);
  3. the admin opens People → Messages and sees the row with an attachment count of 1;
  4. the admin deletes it, and it shows as deleted.
- [ ] **Gates:** `just migrate`, `just test`, `just lint`, `just secrets`, `just e2e`, and dashboard coverage.
- [ ] **Commit** `test(e2e): B5f chat extras`.
