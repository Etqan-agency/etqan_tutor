---
title: "Homework and educational content"
---

**Homework** is set for one student in one course. The office or the student's current teacher sets it,
and it can be linked to one of the student's sessions. The student or a parent answers it with text
and/or a file. The teacher or the office then comments and marks it complete. **Educational content** is
a shelf of teaching items per course, each a private file or an `https://` link. The office manages it,
and the course's teachers and subscribed students (and their parents) read it. Both features live in
`etqan.learning`. They are behind the `homework` and `educational_content` switches.

## Concepts

| Model | Key fields | Notes |
|---|---|---|
| `Homework` | `student`, `course`, optional `session` (SET_NULL), `session_on`, `title`, `kind` (`text`/`file`), `instructions`, `file`/`file_name`, `answer_text`, `answer_file`/`answer_file_name`, `answered_at`/`answered_by`, `teacher_comment`, `status` (`incomplete`/`complete`), `completed_at`, `set_by` | DB checks: a `file` kind needs a file; a `text` kind needs instructions; `completed_at` is set exactly when the status is complete. |
| `EducationalContent` | `course` (CASCADE), `title`, `description`, `file`/`file_name` **or** `url`, `position`, `is_active`, `created_by` | DB check `learning_content_file_or_url`: exactly one of file or link. |

- There is no due date and no grade. The status is the outcome.
- `session_on` copies the linked session's date, so the date survives if the session row is regenerated
  or deleted.
- "Answered" means `answered_at IS NOT NULL`.
- All files are on the private storage. See [Private files](private-files.md).

## How it works

**Homework** (`etqan/learning/services/homework.py`):
- `homework_queryset(user, …)` scopes what each role sees:
  - Office: everything.
  - Teacher: the (student, course) pairs they teach (`access.taught_pairs`).
  - Student: their own.
  - Parent: their children's.
  - Anyone else sees nothing. Out of scope means 404.
- `set_homework`:
  - The student must be active, and the course must exist.
  - A teacher must teach the pair.
  - The pair must have a live (`active`/`paused`) subscription.
  - A text homework needs instructions, and a file homework needs a file.
  - An optional session must be that student's session in that course, and not cancelled.
- `update_homework` (office, or the teacher of the pair; checked by `_require_manager`):
  - It locks the row.
  - Fields that can change: title, instructions, file (replace or `remove_file`), session,
    `teacher_comment` and `status`. `kind` never changes.
  - Marking the homework complete stamps `completed_at`. Reopening clears it.
- `answer_homework` (the student, or a parent of the student):
  - It locks the row. A complete homework is refused with 409 `learning.homework_complete`.
  - Each answer replaces the text and/or file and re-stamps `answered_at` / `answered_by`.
  - The answer must leave either text or a file.
- `delete_homework`:
  - The office can delete at any time.
  - The teacher of the pair can delete only while the homework is unanswered (409
    `learning.homework_answered`).
- Files:
  - Accepted types: PDF, PNG/JPEG/WEBP, DOCX/XLSX/PPTX, TXT, MP3/M4A (`files.HOMEWORK_TYPES`).
  - Maximum size: 10 MiB (`uploads.CONTRACT_MAX`).
  - A replaced or removed file is deleted from storage after the transaction commits.

**Content** (`etqan/learning/services/content.py`):
- `content_queryset(user, …)` scopes what each role sees:
  - Office: everything, inactive items included.
  - Teacher: active items of courses they teach live, or courses where `Course.teachers` lists them.
  - Student / parent: active items of courses with a live subscription.
- `create_content` / `update_content`:
  - Exactly one of a file or a link; the link must be `https://`.
  - Switching from a file to a link deletes the old file after commit.
- Files: `files.CONTENT_TYPES` (the homework types plus MP4), at most 20 MiB (`uploads.LIBRARY_MAX`).
- `reorder_content` must receive every item of the course exactly once. `delete_content` renumbers the
  rest.
- A `post_delete` signal (`etqan/learning/signals.py`) removes the file even when a course delete
  cascades.

**Read hooks:**
- `hooks.py:homework_of(student_user_id, *, month)`: for B10's monthly report. It returns homework set or
  completed in the month (academy timezone).
- `notices.py:homework_notices(since, until)`: for the notifications scanner. Events are derived from
  current state: set, answered, completed.

## API

All routes are under `/api/v1/learning/`. Each ends with `FeatureOn`. Students are addressed by user id.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/learning/homework/?student=&course=&status=` | `homework.view_any`; teacher, student, parent (scoped) | Paginated list |
| POST | `/api/v1/learning/homework/` (multipart) | `homework.create`; teacher of the pair | Set homework |
| GET / PATCH / DELETE | `/api/v1/learning/homework/<id>/` | `homework.view` / `.update` / `.delete`; teacher of the pair (writes); readers (GET) | Read, edit or review, delete |
| GET | `/api/v1/learning/homework/<id>/file/` | `homework.view`; readers in scope | Stream the teacher's file |
| GET | `/api/v1/learning/homework/<id>/answer-file/` | same | Stream the answer file |
| POST | `/api/v1/learning/homework/<id>/answer/` (multipart) | Student or parent only (`IsStudent \| IsParent`); others 403 | Write or replace the answer |
| GET | `/api/v1/learning/content/?course=` | `educational_content.view_any`; readers (scoped) | Unpaginated list |
| POST | `/api/v1/learning/content/` (multipart) | `educational_content.create` | Add an item |
| PATCH / DELETE | `/api/v1/learning/content/<id>/` | `educational_content.update` / `.delete` | Edit / delete |
| POST | `/api/v1/learning/content/reorder/` | `educational_content.reorder` | `{course, ids}` |
| GET | `/api/v1/learning/content/<id>/file/` | `educational_content.view_any`; readers in scope | Stream the file |

File responses are attachments sent with `X-Content-Type-Options: nosniff` and `Cache-Control: private,
no-store` (`api/params.py:_stream`).

## Dashboard

| Route file (`dashboard/src/routes/_authed/`) | Who | Component |
|---|---|---|
| `scheduling.homework.tsx` | Office | `HomeworkList` + `NewHomeworkDialog`, `HomeworkDialog` |
| `teaching.homework.tsx` | Teacher | `HomeworkList` (scoped) |
| `learning.homework.tsx` | Student / parent | `MyHomework` (answer, attach; a parent picks a child) |
| `catalogue.content.tsx` | Office | `ContentAdmin`, `ContentDialog` |
| `teaching.materials.tsx`, `learning.materials.tsx` | Teacher / student / parent | `Materials` (read-only shelf grouped by course) |

The feature folders are `dashboard/src/features/homework/` and `dashboard/src/features/content/`.
`homework/bits.ts` holds the `ACCEPT` list and the 10 MiB client limit. The content dialog adds `.mp4` to
that list.

## Background jobs

There are none of their own. `notifications.scan` (every minute, per academy) reads `homework_notices` for
the `homework.set` / `homework.answered` / `homework.completed` notices. Only the teacher who set a
homework hears about its answer (`etqan/notifications/finders.py:_homework`).

## Configuration

- Switches: `homework` and `educational_content` (both built and off by default).
- Access resources: `homework` (`view`, `view_any`, `create`, `update`, `delete`) and
  `educational_content` (`view_any`, `create`, `update`, `delete`, `reorder`).
- Demo data: `etqan/tenants/seeds/b6.py:seed_b6_homework`, `seed_b6_content`.

## Code map

- `backend/etqan/learning/models.py`: `Homework`, `EducationalContent`.
- `backend/etqan/learning/services/homework.py`, `content.py`, `hooks.py`, `notices.py`.
- `backend/etqan/learning/files.py`: allowed types, `attach`, `remove_after_commit`.
- `backend/etqan/learning/api/homework_views.py`, `content_views.py`, `serializers.py`.
- `dashboard/src/features/homework/`, `dashboard/src/features/content/`.

## Design history

- [B6b spec: homework and content](../superpowers/specs/2026-10-05-b6b-homework-content-design.md),
  decisions H-1…H-14.
- [Plan 34](../superpowers/plans/2026-10-05-plan-34-homework-content.md).
- H-11 in that spec names `homework_events` as the hook for B5 (notifications). B5 now uses
  `homework_notices` (B5d R7) instead. `homework_events` is still exported, but nothing calls it.
