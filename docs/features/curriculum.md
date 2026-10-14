# Curriculum and student progress

Each course can have a ladder of **levels**, and each level has **sub-levels** and **topics**. A topic can
point at a Qur'an chapter and a verse range. Each student has a **current level** per course and a set of
**completed topics**. To move a student up a level, a teacher (or the office) raises an **upgrade
request**, and the office approves or rejects it. The office (admins, and staff holding codes) manages
the ladder and every student's place on it. A teacher works only on students they currently teach in
that course. Students and parents read their own (or their children's) progress. Everything lives in
`etqan.learning`, behind the `levels` switch, plus `quran_chapters` for the chapter list.

## Concepts

| Model | Key fields | Notes |
|---|---|---|
| `QuranChapter` | `number` (unique), Arabic/simple/complex names, revelation place and order, `verses_count`, pages | Reference data. Loaded from the bundled `etqan/learning/data/quran_chapters.json`. There are exactly 114 rows, and none is added or deleted by hand. |
| `Level` | `course` (FK `catalogue.Course`, CASCADE), `name_ar`/`name_en`, `position`, `is_active` | Ordered per course. |
| `SubLevel` | `level`, names, `position` | Cascades with its level. |
| `Topic` | `sub_level`, names, `position`, `chapter` (nullable, PROTECT), `from_verse`/`to_verse` | DB check `learning_topic_verses`: give both verses or neither, and a verse range needs a chapter. |
| `StudentLevel` | `student` (`identity.StudentProfile`), `course`, `level`, `started_on`, `ended_on`, `set_by` | Partial unique `learning_one_current_level`: one row with `ended_on IS NULL` per (student, course). Rows that have ended form the history. |
| `TopicCompletion` | `student`, `topic`, `completed_on`, `recorded_by` | Unique per (student, topic). |
| `LevelUpgradeRequest` | `student`, `course`, optional `subscription`, `from_level`, `to_level`, `note`, `status` (pending/approved/rejected), `rejection_reason`, `requested_by`, `decided_by`, `decided_at` | Partial unique `learning_one_pending_request` per (student, course). |

- Levels are kept **per student and course**, not per subscription, so a renewal keeps the student's
  progress.
- Other apps' models are referenced by string FK only. Learning reads other apps only through their
  services (`scheduling`, `catalogue`, `identity`, `academy`).

## How it works

**Who "teaches" a student** (`services/access.py:teaches`, `taught_pairs`, `live_pairs`): a teacher
teaches a (student, course) pair while one of that student's subscriptions in that course with that
teacher is `active` or `paused` (`LIVE`). Past teachers and substitutes get no access.
`access.py:progress_scope` decides which courses of a student a caller may read. The office and the
student themselves (or a parent) see every course. A teacher sees only the courses they teach. Anyone
else gets 404.

**Editing the ladder** (`services/curriculum.py`):
- `create_level` / `update_level` save a level together with its whole sub-level/topic tree in one
  request (`_write_tree`):
  - Rows that carry an id are kept and updated. A topic can move to another sub-level of the same level.
  - Rows without an id are created.
  - Rows left out of the request are deleted.
- A level holds at most 50 sub-levels, and each sub-level at most 200 topics.
- If some student has completed a topic, dropping that topic is refused with 409
  `learning.topic_in_use`.
- A level cannot move to another course.
- `delete_level` refuses with 409 `learning.level_in_use` when any student level, upgrade request or
  completion points to the level. Deactivate it instead. After a delete, the remaining levels are
  renumbered.
- `reorder_levels` must receive every level of the course exactly once.
- `_chapter_fields`: a topic can carry a chapter only while `quran_chapters` is on. Verses must satisfy
  1 ≤ from ≤ to ≤ `verses_count`. When the switch is off, an existing topic keeps the chapter it already
  has.

**Qur'an chapters** (`services/quran.py`): `sync_chapters` loads the JSON file. It creates missing
chapters and resets every field of existing ones, and returns the created/reset counts.
`update_chapter` edits only the three names.

**Placing a student** (`services/progress.py`):
- `set_level`:
  - The level must be active and belong to the course.
  - The function ends the current row (`ended_on` = the academy's today) and starts a new one. Setting the
    same level again does nothing.
  - A teacher may set only the *first* level. If the student already has one, the teacher gets 409
    `learning.level_already_set`.
  - The function survives a concurrent first set: an `IntegrityError` on the unique constraint returns
    the row that won.
- `complete_topic` / `uncomplete_topic`: the call is idempotent. Any topic of the course can be ticked,
  whatever the current level. `completed_on` cannot be in the future.
- Totals ("completed n / total") count only topics of **active** levels (`_totals`, `_completed`).
- Read functions:
  - `level_rows`: the office list, one row per (student, course) pair. A teacher gets only the pairs
    they teach.
  - `progress`: the full ladder, with history and any pending request.
  - `progress_summary`: one summary per course.

**Upgrade requests** (`services/upgrades.py`):
- `request_upgrade`:
  - Only the office, or a teacher of the pair, can ask.
  - `to_level` is fixed when the request is made: it is the next active level by position.
  - 409 `learning.no_level` when the student has no current level, `learning.top_level` at the last
    level, and `learning.request_pending` when a request is already pending.
  - An optional subscription must be that student's subscription in that course.
- `approve_request` (office only):
  - It locks the row and re-checks that the request is still pending (`learning.request_decided`).
  - The current level must still be `from_level` (`learning.level_changed`), and `to_level` must still
    be active (`learning.level_inactive`).
  - It then calls `set_level`.
- `reject_request` requires a reason.

**Read hooks for other apps** (exported from `etqan/learning/services/__init__.py`):
- `progress_of(student_user_id, *, month)`: the B10 monthly-report facts. For each course it gives the
  level at month end, the topics completed in the month, level changes, and upgrade decisions made in
  the month (academy timezone).
- `notices.py:upgrade_notices(since, until)`: read by the notifications scanner.

## API

All routes are under `/api/v1/learning/`. Every one ends with `FeatureOn`. While the switch is off, a
caller who passes the role check gets 404 and the records are kept. "Readers" means teachers, students and
parents on GET; they are scoped by the services.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/learning/levels/?course=` | `level.view_any`, `student_level.view_any` or `level_upgrade_request.view_any`; any reader | List levels with their tree |
| POST | `/api/v1/learning/levels/` | `level.create` | Create a level with its tree |
| GET / PUT / DELETE | `/api/v1/learning/levels/<id>/` | `level.view` (or a reader) / `level.update` / `level.delete` | Read, replace the tree, delete |
| POST | `/api/v1/learning/levels/reorder/` | `level.reorder` | `{course, ids}` |
| GET | `/api/v1/learning/quran-chapters/` | `quran_chapter.view_any`, `level.create` or `level.update`; any reader | List chapters (switch `quran_chapters`) |
| POST | `/api/v1/learning/quran-chapters/sync/` | `quran_chapter.create` | Load the bundled file |
| PATCH | `/api/v1/learning/quran-chapters/<id>/` | `quran_chapter.update` | Edit names |
| GET | `/api/v1/learning/student-levels/?course=&level=&no_level=&search=` | `student_level.view_any`; teacher (read) | One row per (student, course) pair, paginated |
| GET | `/api/v1/learning/students/<user_id>/progress/` | `student_level.view`; readers in scope | Per-course summary |
| GET | `/api/v1/learning/students/<user_id>/progress/<course_id>/` | same | Full ladder with ticks |
| PUT | `/api/v1/learning/students/<user_id>/progress/<course_id>/level/` | `student_level.update`; teacher of the pair | Set level |
| PUT / DELETE | `/api/v1/learning/students/<user_id>/progress/<course_id>/topics/<topic_id>/` | `student_level.update`; teacher of the pair | Tick / untick a topic |
| GET / POST | `/api/v1/learning/level-upgrades/?status=&student=&course=` | `level_upgrade_request.view_any` / `.create`; teacher (scoped) | List / raise a request |
| POST | `/api/v1/learning/level-upgrades/<id>/approve/` | `level_upgrade_request.update` | Approve |
| POST | `/api/v1/learning/level-upgrades/<id>/reject/` | `level_upgrade_request.update` | Reject with `reason` |

## Dashboard

Feature folder: `dashboard/src/features/curriculum/` (locale area `curriculum.json`, which also holds the
`learning.*` error texts).

| Route file (`dashboard/src/routes/_authed/`) | Who | Component |
|---|---|---|
| `catalogue.levels.tsx` | Office | `LevelsList`, `LevelDialog` (sub-level/topic repeater, chapter picker) |
| `catalogue.quran.tsx` | Office | `ChaptersTable` (sync, edit names) |
| `scheduling.student-levels.tsx` | Office | `StudentLevelsList` → `ProgressPanel` drawer |
| `scheduling.level-upgrades.tsx` | Office | `UpgradesList` (pending/approved/rejected tabs) |
| `teaching.levels.tsx` | Teacher | `StudentLevelsList` scoped to their pairs |
| `learning.progress.tsx` | Student / parent | `MyProgress` (read-only; a parent picks a child) |

`StudentLevelCard` is exported from the feature's index, but nothing renders it yet.

## Background jobs

Curriculum has no tasks of its own. `notifications.scan` (every minute, looping over academies) calls
`upgrade_notices` to send `level.upgrade_requested` / `level.upgrade_decided`
(`etqan/notifications/finders.py`).

## Configuration

- Switches (`etqan/platform/features.py`), both built and off by default:
  - `levels`: levels, student levels and upgrades.
  - `quran_chapters`: the chapter list and putting chapters on topics.
- Access resources (`etqan/access/registry.py`, B6 marker): `level`, `quran_chapter`, `student_level`,
  `level_upgrade_request`.
- Demo data: `etqan/tenants/seeds/b6.py:seed_b6_levels`.

## Code map

- `backend/etqan/learning/models.py`: every model above.
- `backend/etqan/learning/services/curriculum.py`, `progress.py`, `upgrades.py`, `quran.py`, `access.py`,
  `notices.py`.
- `backend/etqan/learning/api/views.py` (curriculum views), `api/urls.py`, `api/params.py`
  (`_int_param`).
- `backend/etqan/learning/data/quran_chapters.json`.
- `dashboard/src/features/curriculum/`.

## Design history

- [B6 phase spec](../superpowers/specs/2026-10-05-b6-learning-design.md): phase decisions B6-1…B6-11.
  B6a (curriculum) is §5–§11.
- [Plan 32: curriculum](../superpowers/plans/2026-10-05-plan-32-curriculum.md).
- Phase decision B6-3 says the subscription page would show the student's level through `StudentLevelCard`
  (request R-B6-1). That is not wired yet.
