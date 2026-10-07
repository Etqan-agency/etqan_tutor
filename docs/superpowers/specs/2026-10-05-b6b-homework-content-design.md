# Slice B6b — Homework & Educational Content — Design

**Date:** 2026-10-05
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); review findings applied 2026-10-05.
**Phase spec:** `2026-10-05-b6-learning-design.md` (B6-1…B6-11 bind this slice; §3 row B6b is its contract).
**Evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` (P1) and `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` (TH). What the audits
do not show is marked `[assumed]` (ledger D1).
**Requires:** B6a (it extends `etqan.learning` and reuses `learning.services.teaches` / `taught_pairs`); branched after
B6a merges. No other phase's slice.

## 1. Goal

Teachers (and the office) set homework for a student — a written task or a file — the student (or a parent) answers with
text and an optional attachment, and the teacher comments and marks it complete. Each course gets a shelf of teaching
materials its subscribed students can open. Both behind switches, off by default.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| H-1 | **Homework belongs to one student and one course**, optionally linked to one session of that student in that course (TH's "weekly-schedule data" tab: we link the session, not the slot). Fields: title\*, kind `text` / `file`, instructions, the teacher's file, the student's answer text and attachment, who answered and when, the teacher's comment, status `incomplete` / `complete`, who set it, when it was completed. A `text` homework requires instructions and may also carry a file; a `file` homework requires a file and may also carry instructions. | P1 SCHED-011 (4 tabs; student\*, title\*, type\* file/text, file upload\*, student response, student attachment, teacher comment, status\* incomplete/complete); P1 §13.1 · [assumed] the conditional requirement (P1 marks "file upload\*" unconditionally), course + optional session link |
| H-2 | **No due date and no grade**: TH shows none; the status is the outcome. | P1 SCHED-011 · [assumed] |
| H-3 | **Who sets homework**: the office, or a teacher who teaches the student in the course (B6-5). For everyone the student must have an `active` or `paused` subscription in the course (homework is for a student taking the course). Errors (400 with field): unknown or inactive student → `student`; teacher who does not teach the pair → `student`; unknown course or no live subscription for the pair → `course`; session unknown, cancelled, or not that student's in that course → `session`. The linked session's date is copied to `session_on` so it survives the session row being regenerated or deleted (the FK is `SET_NULL`). | B6-4, B6-5; B6a C-11 error precedent; `scheduling/services/rules.py` `delete_untouched` · [assumed] live-subscription rule |
| H-4 | **Who answers**: the student, or a parent of the student (B6-4 "homework answers in B6b"), may write or replace the answer text and attachment while the homework is `incomplete`. Each answer sets `answered_at` (the latest answer) and `answered_by`. "Answered" means `answered_at IS NOT NULL`. A complete homework refuses answers (409 `learning.homework_complete`). An answer leaving neither text nor attachment → 400 `answer_text`. Nobody else answers: admins, staff and teachers get 403 on the answer route. | P1 SCHED-011 (student response, student attachment) · [assumed] parent may answer; replace until complete |
| H-5 | **Who reviews and edits**: the office, or the teacher who teaches the pair, may at any time edit title, instructions, file and session, write the comment and set the status. Marking complete is allowed with or without an answer and stamps `completed_at`; reopening clears it. `kind` cannot change (400 `kind`). Removing the file of a `file` homework → 400 `file`; clearing the instructions of a `text` homework → 400 `instructions`. **Delete**: office any time; the teacher of the pair only while not answered (409 `learning.homework_answered`). A teacher whose subscriptions with the student end loses all access, including homework they set (B6-5). | P1 SCHED-011 (teacher comment, status) · [assumed] edit/delete rules |
| H-6 | **Concurrency**: `answer_homework`, `update_homework` and `delete_homework` lock the row (`select_for_update`) inside `transaction.atomic` and re-check status/answer on the locked row, so an answer cannot land on a homework being completed. | review finding · [assumed] |
| H-7 | **Files are private** (B6-7): teacher files and student attachments live on `STORAGES["private"]` via `etqan.platform.uploads.check_upload` and are streamed only to readers of the homework. Accepted: PDF, PNG/JPEG/WEBP, DOCX/XLSX/PPTX, TXT, MP3/M4A (recitation answers); at most **10 MiB** each (`CONTRACT_MAX`). Original names are kept in `*_file_name`, trimmed to 255 characters keeping the extension (a small helper in learning; learning may not import `etqan.employment`). Replaced or removed files, and the files of a deleted homework, are deleted after commit (`on_commit(robust=True)`). A rolled-back upload may leave an orphan file in storage (accepted, as in B9a). | ledger D2, D12; B9a A-6/A-10 precedent · [assumed] types/size |
| H-8 | **Educational content** (CATALOG-007): teaching items per course — title\*, description, and exactly one of a file or an external `https://` link (400 `url` for any other scheme). Ordered (`position`), active flag. The office manages them. Readers: the office (all items, inactive included), teachers who teach the course (a live subscription of theirs in it, or listed in `Course.teachers`), students with an `active` or `paused` subscription in the course, and their parents — active items only. Files: PDF, images, Office, TXT, MP3/M4A, MP4; at most **20 MiB** (`LIBRARY_MAX`); private, streamed. When a content row is deleted — directly or by a course delete cascading — a `post_delete` receiver on `EducationalContent` deletes its file after commit. | P1 CATALOG-007 ("upload teaching files for students subscribed to the courses", course filter); TH §2.8 (form UNKNOWN) · [assumed] fields, link, readers |
| H-9 | Switches: `homework` (the existing `_later` line flipped in place to built, off) and `educational_content` (new under the B6 marker, group `teaching`, built, off). Off: 404 after the role check, records kept (FT-4; B6a C-12). | B6-2 |
| H-10 | Access resources (new, under the B6 marker): `homework` ("Homework" / "الواجبات": `view`, `view_any`, `create`, `update`, `delete`); `educational_content` ("Educational content" / "المحتوى التعليمي": `view_any`, `create`, `update`, `delete`, `reorder`). Staff need codes; admins always pass coded routes; teachers, students and parents pass by role + scoping. | P1 permission keys `homework`, `educational::content` |
| H-11 | **B5 hook (B6-6):** `learning.services.homework_events(*, since, until) -> list[HomeworkEvent]`, `HomeworkEvent(kind: "set" \| "answered" \| "completed", homework_id, student_user_id, course_id, set_by_user_id \| None, at)`. Window `[since, until)`, aware UTC datetimes, called inside the academy's `tenant_context`. Events are **derived from current state** (`created_at`, the latest `answered_at`, `completed_at`), not an event log: a replaced answer yields one event at its latest time; deleted homework yields none. B5 resolves parents through `identity.services`. B6b sends nothing. | B6-6 |
| H-12 | **B10 hook (B6-9):** `learning.services.homework_of(student_user_id, *, month) -> list[HomeworkMonth]`, `HomeworkMonth(homework_id, course_id, course_name_en, course_name_ar, title, status, set_on: date, answered_at, completed_at)` for homework set **or** completed in the calendar month in the academy's timezone (as `progress_of`); `set_on` is the academy-local date of `created_at`. Recorded in the ledger with H-11, extending D26. | B6-9; ledger D26 |
| H-13 | No column on any existing table; two new tables in `etqan.learning` (B6-10). | B6-10 |
| H-14 | Homework is reached from its own nav items (and a "Homework" link on the session detail is left to a later B2 request): TH reaches it from the sessions page; one list per role is simpler here. | P1 SCHED-011 location · [assumed] |

## 3. Data

```text
etqan.learning.Homework
  student       FK identity.StudentProfile  PROTECT  related_name="+"
  course        FK catalogue.Course  PROTECT  related_name="+"
  session       FK scheduling.Session  null  SET_NULL  related_name="+"
  session_on    DateField  null            (copied from the session, H-3)
  title         CharField(200)  required
  kind          CharField(4)  text | file
  instructions  TextField(blank, max 5000)
  file          FileField(private storage, upload_to=tenant_upload_path("homework"), max_length=255)  blank
  file_name     CharField(255, blank)
  answer_text   TextField(blank, max 10000)
  answer_file   FileField(private, same path)  blank
  answer_file_name  CharField(255, blank)
  answered_at   DateTimeField  null
  answered_by   FK AUTH_USER  null  SET_NULL  related_name="+"
  teacher_comment  TextField(blank, max 5000)
  status        CharField(10)  incomplete | complete  (default incomplete)
  completed_at  DateTimeField  null
  set_by        FK AUTH_USER  null  SET_NULL  related_name="+"
  created_at, updated_at
  CHECKs: kind in (text, file); status in (incomplete, complete);
          kind='file' → file <> '' ; kind='text' → instructions <> '' ;
          (status='complete') = (completed_at IS NOT NULL)
  INDEX (student, course)
  ordering (-created_at, -id)

etqan.learning.EducationalContent
  course        FK catalogue.Course  CASCADE  related_name="+"
  title         CharField(200)  required
  description   TextField(blank, max 5000)
  file          FileField(private, upload_to=tenant_upload_path("content"), max_length=255)  blank
  file_name     CharField(255, blank)
  url           URLField(500, blank)
  position      PositiveSmallIntegerField
  is_active     BooleanField(default True)
  created_by    FK AUTH_USER  null  SET_NULL  related_name="+"
  created_at, updated_at
  CHECK: exactly one of file / url is non-empty
  ordering (course_id, position, id)
```

A course with homework cannot be deleted (PROTECT); catalogue's existing 409 says the course "has subscriptions", which is
true in practice (H-3 requires one) — known wording, left as is.

## 4. Services (`etqan/learning/services/homework.py`, `content.py`)

- `homework_queryset(user, *, student=None, course=None, status=None)` — office all; teacher: pairs in `taught_pairs`;
  student: own; parent: children's (`identity.services.get_children`); anyone else none.
- `get_homework(user, id)` (scoped; `NotFoundError`).
- `set_homework(*, student_user_id, course_id, title, kind, instructions="", file=None, session_id=None, by)` — H-1, H-3, H-7.
- `update_homework(hw, *, by, **changes)` — `title`, `instructions`, `file`, `remove_file`, `session_id`, `teacher_comment`,
  `status`; only given keys change; H-5, H-6.
- `answer_homework(hw, *, by, answer_text=None, answer_file=None, remove_answer_file=False)` — H-4, H-6.
- `delete_homework(hw, *, by)` — H-5, H-6, H-7.
- `content_queryset(user, *, course=None)` — H-8 readers (office sees inactive).
- `create_content`, `update_content`, `delete_content`, `reorder_content(*, course_id, ids)` (ids must be exactly the
  course's items, 400 `ids`).
- `homework_events(*, since, until)`, `homework_of(student_user_id, *, month)` — H-11, H-12.

## 5. API (`/api/v1/learning/`, `FeatureOn` listed last everywhere)

| Method & path | Permission (staff code) | Feature |
|---|---|---|
| `GET homework/?student=&course=&status=&page=` | `HasCode \| (ReadOnly & ReadsOwn)` — `homework.view_any` | `homework` |
| `POST homework/` (multipart) | `HasCode \| IsTeacher` — `homework.create` | `homework` |
| `GET homework/<id>/` | `HasCode \| (ReadOnly & ReadsOwn)` — `homework.view` | `homework` |
| `PATCH homework/<id>/` (multipart) | `HasCode \| IsTeacher` — `homework.update` | `homework` |
| `DELETE homework/<id>/` | `HasCode \| IsTeacher` — `homework.delete` | `homework` |
| `GET homework/<id>/file/`, `GET homework/<id>/answer-file/` | as `GET homework/<id>/` — `homework.view` | `homework` |
| `POST homework/<id>/answer/` (multipart) | dedicated `HomeworkAnswerView`, `permission_classes = [IsStudent \| IsParent, FeatureOn]`; listed in `access/tests/test_routes.py` `SELF_SERVICE` ("the student's or parent's own answer; scoped in the view") | `homework` |
| `GET content/?course=` | `HasCode \| (ReadOnly & ReadsOwn)` — `educational_content.view_any` (unpaginated) | `educational_content` |
| `POST content/`, `PATCH content/<id>/`, `DELETE content/<id>/`, `POST content/reorder/` | `HasCode` — `educational_content.create` / `update` / `delete` / `reorder` | `educational_content` |
| `GET content/<id>/file/` | as `GET content/` — `educational_content.view_any` | `educational_content` |

All coded routes go into `ROUTES` / `FEATURES`; `FEATURE_WORDS` gains `"/learning/homework": "homework"` and
`"/learning/content": "educational_content"`. Because SELF_SERVICE routes are outside those tables, learning's own tests
cover the answer route: admin, staff holding every code and teachers get 403; a student or parent with the switch off gets
404 `FEATURE_OFF`; a student who does not own it and a parent who is not that student's get 404.

Students addressed by user id. Homework item: `{id, student:{id, full_name}, course:{id, name_en, name_ar}, session_id,
session_on, title, kind, instructions, has_file, file_name, answer_text, has_answer_file, answer_file_name, answered_at,
answered_by:{id, full_name}|null, teacher_comment, status, completed_at, set_by:{id, full_name}|null, created_at}`.
Content item: `{id, course:{id, name_en, name_ar}, title, description, has_file, file_name, url, position, is_active}`. A
reader outside scope: lists return nothing for that row; detail and file routes 404. File responses: `FileResponse`
attachment, `X-Content-Type-Options: nosniff`, `Cache-Control: private, no-store` (B9a). Numeric query params use B6a's
ASCII-only `_int_param`.

## 6. Screens (dashboard `src/features/homework/`, `src/features/content/`; locale areas `homework.json`, `content.json`, no top-level wrapper)

| Who | Where | What |
|---|---|---|
| Office | Scheduling → Homework `/scheduling/homework` (`homework.view_any`, `homework`) | Status tabs incomplete / complete / all; filters course, student search; columns student · course · title · kind · answered · status · set on; add (student → course of a live subscription → optional session → title, kind, instructions / file); a row opens the homework dialog (edit, comment, mark complete / reopen, download files, delete). |
| Teacher | Teaching → Homework `/teaching/homework` (role teacher, `homework`) | Same list scoped to their pairs; add for a student they teach. |
| Student / parent | Learning → Homework `/learning/homework` (roles student, parent, `homework`) | Their (children's) homework, incomplete first; open one: instructions, download the file, write the answer, attach a file, submit / replace while incomplete; teacher's comment and who answered shown; a parent picks a child. |
| Office | Catalogue → Educational content `/catalogue/content` (`educational_content.view_any`, `educational_content`) | Course filter; list with inactive items marked; add / edit (title, description, file or link), active toggle, reorder, delete. |
| Teacher / student / parent | Teaching → Course materials `/teaching/materials`, Learning → Course materials `/learning/materials` (`educational_content`) | Read-only shelf grouped by course name: open the link (new tab, `rel="noopener noreferrer"`) or download the file. |

Dates are date-only → `formatDay` (B6a fix); instants → the locale's date-time format.

## 7. Seeds and tests

- `seed_b6` gains a step (demo only, idempotent, skipped when the switch-dependent data cannot be made): two homework items
  for the demo students in the Qur'an course (one answered), two content items for that course (one link, one small PDF).
- Backend tests: every rule of §2–§4 — set errors per field (H-3), live-subscription rule, session snapshot surviving the
  session's deletion, conditional kind requirements, edit/remove-file/clear-instructions errors, complete with and without
  an answer, reopen, delete rules for office and teacher, answer rules (complete 409, empty 400, parent answers,
  `answered_by`), the answer-route matrix above, scoping per role (teacher of course A vs B, student own / other, parent
  child / not child, staff with / without codes), file type and size refusal, private storage and response headers, file
  deletion after commit (replace, remove, row delete, course cascade via `catalogue.services.delete_course`), content
  readers (expired subscription → empty list / 404 file), https-only links, reorder, switches off, `homework_events` window
  and shape, `homework_of` month; route tables; seed.
- Dashboard tests for each screen and role; locale parity.
- e2e `e2e/b6-homework.spec.ts`: switches on; a teacher sets text homework for their student; the student answers with an
  attachment; the teacher comments and marks complete; the office adds a course material and the student opens it.
