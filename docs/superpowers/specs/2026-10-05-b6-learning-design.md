# Phase B6 — Learning — Design

**Date:** 2026-10-05
**Status:** Draft, pending independent spec review (orchestration spec PO-3).
**Phase:** B6 of `2026-09-24-parity-roadmap-design.md` §2: levels / sub-levels / topics with upgrade
requests and student levels; Qur'an chapters sync; educational content; homework; session reviews;
certificates and templates; honour board (CATALOG-004…007, SCHED-010/011, CERT-*, PEOPLE-007). Depends
on B2 (phase spec recorded; no B6 slice needs an unmerged B2 slice, §3).
**Works under:** `2026-10-02-parallel-orchestration-design.md` (ledger, slices, merge queue, ownership).
**Evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` (cited `P1 §x` / IDs) and
`docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` (cited `TH §x`). R7 is dropped (ledger D1): what the
audits do not show is marked `[assumed]`.

This document is the phase spec (§1–§4: the split into slices and the decisions that hold across them)
and the first slice's spec (§5–§11: **B6a — curriculum**). Later slices get their own spec files,
designed against this one.

## 1. Goal

Give each academy TutorHamster's learning layer on top of the scheduling core: a curriculum ladder per
course with each student's place on it, Qur'an reference data, teaching files, homework, session reviews,
certificates and an honour board. Every feature is a per-academy switch, off by default (PO-5), so each
slice merges on its own. B10 (AI monthly reports) later reads this data through `learning.services`.

## 2. Phase decisions

| # | Decision | Source |
|---|---|---|
| B6-1 | All of B6 lives in **one new tenant app, `etqan.learning`**, owned by B6 and added to `TENANT_APPS` under the `── phase B6 ──` marker. It references `catalogue.Course`, `identity.StudentProfile` / `TeacherProfile` and `scheduling.Session` / `Subscription` by string foreign keys only, and reads other apps only through their `services` (an import-linter contract, §4). It changes no model in another app. | orchestration §4.3 (new areas in new apps; `etqan.learning` named there); B2-1 precedent |
| B6-2 | B6 is four slices (§3), each behind its own switches, all **off by default**. The registry's existing `_later` lines `levels`, `homework` and `verified_certificates` are flipped in place to built-but-off by the slice that builds them; every other switch is new, under the `── phase B6 ──` marker. | PO-5; spec 2026-09-30 FT-2; TH SYS-002 flag list |
| B6-3 | **A student's level is kept per student and course, not per subscription.** TutorHamster shows it as the subscription's "student levels" tab; we show the same data wherever a student and course are in view (B6a §6 screens, and the subscription page through request R-B6-1). A renewal (a new subscription, Plan 4) therefore keeps the student's progress, and bundles (D7) and group rows (D6) need nothing extra: each is a subscription with one student and one course. | TH §2.8 CATALOG-004 (tab "add level for student", completed topics); P1 FLOW-010; ledger D6, D7 · [assumed] keying |
| B6-4 | **Who does what** (the teacher, student and parent panels are unobserved, TH §4 U2): the office (admins, and staff holding the resource's codes) manages everything; a **teacher acts only on students they teach** in that course (B6-5); a **student reads their own** learning records and a **parent their children's**, read-only except where a slice says otherwise (homework answers in B6b, session reviews in B6c). Anyone else gets 404 on a record, as Plan 5 scoping does. | P1 §3 actors; TH §4 U2 · [assumed] teacher/student rights; v1 spec §6.1 (404 scoping) |
| B6-5 | **"Teaches"**: a teacher teaches a student in a course while some subscription of that student in that course with that teacher is `active` or `paused` (`scheduling.services.subscriptions_queryset`). Past teachers keep read access to nothing. One helper, `learning.services.teaches(teacher_user_id, student_user_id, course_id)`, is the only implementation. | [assumed]; Plan 4 statuses |
| B6-6 | **B6 sends no notifications.** Homework, upgrade-request and certificate notices are B5's (the student preference "reports & homework notifications", COMM-004/005): B6 exposes read-only service queries B5's finders can call (each slice names its own), and adds no notification kind. Notifications are pull-based and no app imports `etqan.notifications`. | TH §2.1 PEOPLE-001 preferences; `pyproject.toml` contract "no app imports notifications" |
| B6-7 | **Files are private.** Homework files and answers, teaching content, certificate templates and student photos are stored on `STORAGES["private"]` through `etqan.platform.uploads.check_upload` (ledger D12) and streamed by authenticated endpoints that apply B6-4's scoping; nothing B6 stores gets a public URL, and no uploaded HTML or SVG is accepted (ledger D2). | ledger D2, D12; spec 2026-10-03-platform-extras A-10 |
| B6-8 | **XP points and student tags already exist** (Plan 12, `StudentProfile.xp`, `Tag`). No B6 slice changes them automatically: awarding XP stays a manual office edit [assumed: TH's reward mechanism is UNKNOWN, TH V32]. | TH §2.1 PEOPLE-001; TH §6 V32 |
| B6-9 | **What B10 reads:** `learning.services.progress_of(student_user_id) -> list[Progress]` (B6a §8.4) and each later slice's read service (homework, reviews, certificates). Recorded as a shared decision so B10 designs against it. | roadmap §2 (B10 depends on B6) |
| B6-10 | New columns go only on `etqan.learning`'s own new tables; no B6 migration touches an existing table. | orchestration §8.2; B2-16 precedent |
| B6-11 | Dashboard code lives in `src/features/curriculum/`, `features/homework/`, `features/certificates/` … (not `features/learning/`: the dashboard's `learning` nav group and `/learning/*` routes are already the student/parent area). Student/parent pages are added under `/learning/…`, teacher pages under `/teaching/…`, office pages under the existing groups. | `dashboard/src/features/shell/nav.ts` `NavGroup`; `routes/_authed/learning.tsx` |

## 3. Slices

Each slice is its own spec → plan → build → queue cycle. **None requires another phase's slice**: they read
only what B0/B1 built (courses, people, subscriptions, sessions, session reports) and what B9a built
(`etqan.platform.uploads`, `STORAGES["private"]`), all merged.

| Slice | Topic | Contents | Audit IDs | Switches (off by default) | Size |
|---|---|---|---|---|---|
| **B6a** | curriculum | Levels → sub-levels → topics per course; Qur'an chapters (bundled data, "sync"), optional chapter / verse range on a topic; each student's current level per course and completed topics; level upgrade requests (teacher asks, office approves / rejects with a reason) | CATALOG-004, CATALOG-005, CATALOG-006, FLOW-010 | `levels` (flipped), `quran_chapters` | M |
| **B6b** | homework & content | Homework set by a teacher or the office for a student (optionally on a session): title, type file / text, file, student answer and attachment, teacher comment, status incomplete / complete; educational content: teaching files per course, readable by the course's subscribed students | SCHED-011, CATALOG-007 | `homework` (flipped), `educational_content` | M |
| **B6c** | reviews & honour board | Session reviews (the student's or parent's rating of a completed session, read by the office and the teacher); honour board (office-published recognitions of students, shown to the academy's users) | SCHED-010, PEOPLE-007 | `session_reviews`, `honour_board` | S–M |
| **B6d** | certificates | Certificate templates (title, description, image ≤ 5 MB); issued certificates (type completion / appreciation / pride / custom template, student, course, completed-session count auto-filled from student + course, optional photo ≤ 2 MB, message); a printable certificate page; verified certificates: a public verification page by code; the course "certificate" toggle | CERT-001, CERT-002, CERT-003, FLOW-011, BR-31, BR-39 | `certificates`, `verified_certificates` (flipped; requires `certificates`) | M |

Order: B6a, B6b, B6c, B6d. B6a goes first because B10 needs progress data soonest and it has the most
confirmed evidence.

Not taken by any B6 slice, with the reason:

- **AI monthly student reports** (EXP-001) and AI anything: B10.
- **Monthly teacher evaluation** (TH V27, SYS-004 action): behaviour UNKNOWN; not built (as B9a A-15).
- **Certificates for recorded courses** (playlist "accredited certificate", RC-003 "certificate obtained"):
  B7, which may reuse B6d's certificate service.
- **The course's "linked to the Qur'an curriculum" toggle** (CATALOG-001): its only observable effect is
  linking a course's curriculum to the Qur'an; B6a's optional chapter on a topic covers that, so no course
  field is added (B6a C-6).

Each slice spec details its own data, rules, API, screens, seeds and tests; this table is the contract
between them. A slice may move an item to a later slice only by amending this table.

## 4. Shared lists, ownership and requests

- B6 adds lines only under its `── phase B6 ──` markers: `TENANT_APPS`, `config/api_router.py`
  (`path("learning/", include("etqan.learning.api.urls"))`, once, in B6a), the feature registry (and flips
  its own three `_later` lines in place), the access `RESOURCES`, `seed_academy` (`seed_b6(subdomain)` from
  `etqan/tenants/seeds/b6.py`), `pyproject.toml` (the platform contract's forbidden list and a
  `etqan.learning` contract), the dashboard's `NAV_ITEMS`.
- The `etqan.learning` contract forbids importing other apps' `models` and `api` (and `etqan.tenants`,
  `etqan.site`, `etqan.notifications`, `etqan.access`, `etqan.billing`, `etqan.payroll`, `etqan.finance`,
  `etqan.gateways`); it may import `etqan.platform`, `etqan.identity.services`, `etqan.catalogue.services`
  and `etqan.scheduling.services`. Tests may import other apps' models for fixtures.
- New translation areas are new files `dashboard/src/locales/{en,ar}/<area>.json` (en and ar only, ledger
  D11/D22). New e2e specs are `e2e/b6-*.spec.ts`.
- **R-B6-1 (request to B2, optional, non-blocking):** one line in
  `dashboard/src/routes/_authed/scheduling.subscriptions.$subscriptionId.tsx` rendering
  `<StudentLevelCard studentId courseId />` exported from `@/features/curriculum` (it renders nothing while
  `levels` is off or the viewer lacks `student_level.view_any`), once B6a merges.

---

# Slice B6a — Curriculum

## 5. B6a decisions

| # | Decision | Source |
|---|---|---|
| C-1 | **Levels belong to one course** and are ordered (`position`). A level has an Arabic and English name, an active flag, and an ordered list of **sub-levels**, each with an ordered list of **topics**. The office edits a level with its sub-levels and topics in one form (TH's repeater) and saves it in one request. | P1 CATALOG-004 (course\*, level name\*, sub-levels repeater with topics); TH §2.2 CATALOG-004 (columns course, level, sub-levels, topic count) · [assumed] bilingual names as every catalogue name |
| C-2 | Saving a level **replaces** its sub-levels and topics with the submitted lists, matching existing rows by `id` (kept and updated), creating rows without one, and deleting rows left out. A topic that a student has completed, or a level that any student level or upgrade request points to, **cannot be deleted** (409 `learning.topic_in_use` / `learning.level_in_use`); rename and reorder are always allowed. Deactivating a level hides it from new choices but keeps every record. | [assumed] keep history; Plan 4 "deactivate, don't delete" (plan D6) |
| C-3 | **The Qur'an chapters** are reference data per academy: number (1–114), Arabic, simple and complex names, revelation place (makkah / madinah), revelation order, verse count, start and end page. They come from a **data file shipped with the app** (`etqan/learning/data/quran_chapters.json`, generated once from the public Quran.com API v4 `/chapters` and committed); the office's **"Sync chapters"** action loads it into the academy, creating missing chapters and restoring every field of existing ones. The office may edit a chapter's names; chapters are never created by hand or deleted (there are exactly 114). | TH §2.2 CATALOG-006 (columns, sync from API, form sections); P1 CATALOG-006, INT ("Qur'an chapters API") · [assumed] bundled file instead of a live call: the data never changes, and tenants make no outbound calls |
| C-4 | Qur'an chapters are under the switch **`quran_chapters`** (new, group `teaching`). The list and sync need only it; picking a chapter on a topic needs `levels` and `quran_chapters`. | B6-2 |
| C-5 | A topic may name **one chapter and an optional verse range** (`from_verse`–`to_verse`, within the chapter's verse count, from ≤ to). Its name stays required (the form pre-fills it from the chapter's name and range). | P1 FLOW-010 ("course optionally linked to the Qur'an curriculum") · [assumed] link at topic level |
| C-6 | The course "linked to the Qur'an curriculum" toggle is not built (§3); no catalogue field is added. | B6-1; [assumed] |
| C-7 | **Student level**: a student has at most one **current level per course** (`StudentLevel` with `ended_on` null; a partial unique constraint). Changing it ends the current row (`ended_on` = today) and starts a new one (`started_on` = today); the ended rows are the student's level history. The level must belong to the course and be active. | P1 SUB-001 tab "مستويات الطلاب" (per-student level), FLOW-010 · [assumed] history rows |
| C-8 | **Who sets a level**: the office may set or change it at any time. A teacher who teaches the student in the course (B6-5) may set the **first** level only (when the student has none in that course); after that a teacher moves a student up only through an upgrade request. | P1 CATALOG-005, FLOW-010 (approval exists, so a level rise is approved) · [assumed] teacher's first-level right |
| C-9 | **Completed topics**: per student and topic (unique), with the date completed (default today in the academy's timezone) and who recorded it. Any topic of the course's levels may be ticked or unticked (not only the current level's). The office, and a teacher who teaches the student in the course, may tick and untick. | P1 SUB-001 ("completed topics repeater") · [assumed] who; any level |
| C-10 | **Level upgrade requests**: student, course, the subscription it was raised from (optional), the current level (`from_level`, read-only), the **next level** (`to_level`: the next active level of the course by position, fixed when the request is made), an optional note, status `pending` / `approved` / `rejected`, rejection reason, who asked and who decided, and when. At most one pending request per student and course (409 `learning.request_pending`). Without a current level → 409 `learning.no_level`; already at the last active level → 409 `learning.top_level`. | P1 CATALOG-005 (student\*, subscription\*, course\*, current level read-only, approve toggle, rejection reason\*); P1 BR (§13.1: rejection reason when not approved) · [assumed] to_level = next by position, note, one pending |
| C-11 | **Who asks and who decides**: the office, or a teacher who teaches the student in the course, may ask. Only the office approves or rejects. **Approve** moves the student to `to_level` (C-7) provided their current level is still `from_level`, else 409 `learning.level_changed` (the request stays pending; the office rejects it). **Reject** requires a reason (400 on `reason`). Decided requests are final. | P1 FLOW-010 (approve → level raised; otherwise reason required) · [assumed] office-only decision |
| C-12 | Levels, student levels and upgrade requests are under **`levels`** (flipped to built, off). Turning it off hides them (404) and keeps every record (FT-4). | B6-2; spec 2026-09-30 FT-4 |
| C-13 | Access resources (new, under the B6 marker): `level` ("Levels" / "المستويات": `view`, `view_any`, `create`, `update`, `delete`, `reorder`); `quran_chapter` ("Qur'an chapters" / "سور القرآن": `view_any`, `update`, `create` — `create` is the sync); `student_level` ("Student levels" / "مستويات الطلاب": `view`, `view_any`, `update` — set a level, tick topics); `level_upgrade_request` ("Level upgrade requests" / "طلبات رفع المستوى": `view_any`, `create`, `update` — approve/reject). Staff need the codes; admins always pass; teachers, students and parents pass by B6-4 rules, not codes. | `etqan/access/registry.py`; P1 permission keys `level`, `level::upgrade::request`, `quran::chapter` |
| C-14 | Reading levels and chapters (names, not student data) is allowed to every teacher, student and parent of the academy while the switch is on (`HasCode | (ReadOnly & (IsTeacher | IsStudent | IsParent))`), so they can see level and topic names; staff need `level.view` / `level.view_any` / `quran_chapter.view_any`. | [assumed] names are not personal data |

## 6. B6a screens (dashboard)

| Who | Where | What |
|---|---|---|
| Office | **Catalogue → Levels** `/catalogue/levels` (nav, group `catalogue`, `level.view_any`, `levels`) | List: course · level · sub-levels · topic count · active; filter by course; move up / down within a course (`level.reorder`); add / edit in a dialog: course, names, active, a repeater of sub-levels each with a repeater of topics (name ar/en; with `quran_chapters` on: chapter picker + verse range that pre-fills the names); delete. |
| Office | **Catalogue → Qur'an chapters** `/catalogue/quran` (`quran_chapter.view_any`, `quran_chapters`) | Table: number · Arabic name · simple name · revelation place · revelation order · verses · pages; "Sync chapters" (`quran_chapter.create`) with a result toast (created / restored counts); edit names in a dialog. Empty state with the sync button. |
| Office | **Scheduling → Student levels** `/scheduling/student-levels` (`student_level.view_any`, `levels`) | One row per current student level: student · course · level · since · completed topics (n / total of the course); filters: course, level, student search. Row opens the **progress panel** (below). |
| Office | **Scheduling → Level upgrades** `/scheduling/level-upgrades` (`level_upgrade_request.view_any`, `levels`) | Tabs pending / approved / rejected; columns student · course · from → to · asked by · date · note; approve; reject with a required reason. Pending count shows in the tab. |
| Teacher | **Teaching → My students' levels** `/teaching/levels` (role teacher, `levels`) | The same list scoped to students they teach (B6-5); progress panel with "set first level", tick topics, "request upgrade" (with a note). |
| Student / parent | **Learning → My progress** `/learning/progress` (roles student, parent, `levels`) | Per course: current level, the level ladder with each sub-level's topics ticked / not, completed count; a parent picks a child. Read-only. |
| Any with access | `StudentLevelCard` (exported) | Compact card for one student + course (current level, completed n / total, "open progress"); used by R-B6-1. |

The **progress panel** (a drawer, shared by office and teacher): current level and since; "change level"
(office) or "set first level" (teacher, only when none); the course's levels as collapsible sections with
their sub-levels and topic checkboxes (completed date on hover); level history; the student's pending
request if any; "request upgrade" (hidden when pending, no level or top level).

## 7. B6a data

```text
etqan.learning.Level
  course        FK catalogue.Course  PROTECT  related_name="+"
  name_ar, name_en   CharField(120)   required
  position      PositiveSmallIntegerField   (0-based order within the course)
  is_active     BooleanField(default True)
  created_at, updated_at
  ordering (course_id, position, id)

etqan.learning.SubLevel
  level         FK Level  CASCADE  related_name="sub_levels"
  name_ar, name_en   CharField(120)   required
  position      PositiveSmallIntegerField
  ordering (position, id)

etqan.learning.Topic
  sub_level     FK SubLevel  CASCADE  related_name="topics"
  name_ar, name_en   CharField(200)   required
  position      PositiveSmallIntegerField
  chapter       FK QuranChapter  null  PROTECT
  from_verse, to_verse   PositiveSmallIntegerField  null
  CHECK: verses null unless chapter set; from_verse <= to_verse when both set
  ordering (position, id)

etqan.learning.QuranChapter
  number        PositiveSmallIntegerField  unique  (1..114)
  name_arabic   CharField(60)
  name_simple   CharField(60)
  name_complex  CharField(60)
  revelation_place  CharField(7)  choices makkah | madinah
  revelation_order  PositiveSmallIntegerField
  verses_count      PositiveSmallIntegerField
  page_start, page_end  PositiveSmallIntegerField
  ordering (number)

etqan.learning.StudentLevel
  student       FK identity.StudentProfile  PROTECT  related_name="+"
  course        FK catalogue.Course  PROTECT  related_name="+"
  level         FK Level  PROTECT  related_name="student_levels"
  started_on    DateField
  ended_on      DateField  null
  set_by        FK AUTH_USER  null  SET_NULL
  created_at
  UNIQUE (student, course) WHERE ended_on IS NULL

etqan.learning.TopicCompletion
  student       FK identity.StudentProfile  PROTECT  related_name="+"
  topic         FK Topic  PROTECT  related_name="completions"
  completed_on  DateField
  recorded_by   FK AUTH_USER  null  SET_NULL
  created_at
  UNIQUE (student, topic)

etqan.learning.LevelUpgradeRequest
  student       FK identity.StudentProfile  PROTECT  related_name="+"
  course        FK catalogue.Course  PROTECT  related_name="+"
  subscription  FK scheduling.Subscription  null  SET_NULL  related_name="+"
  from_level    FK Level  PROTECT  related_name="+"
  to_level      FK Level  PROTECT  related_name="+"
  note          TextField(blank, max 2000)
  status        CharField  pending | approved | rejected  (default pending)
  rejection_reason  TextField(blank, max 2000)
  requested_by  FK AUTH_USER  null  SET_NULL
  decided_by    FK AUTH_USER  null  SET_NULL
  decided_at    DateTimeField  null
  created_at
  UNIQUE (student, course) WHERE status = 'pending'
  ordering (-created_at, -id)
```

Positions are rewritten densely (0, 1, 2 …) by every save and reorder, so they never collide; no unique
constraint on position. Course deletion is already refused while a course has subscriptions; a course with
levels is now refused too (PROTECT → catalogue's existing 409), consistent with "deactivate, don't delete".

## 8. B6a rules and services

`etqan/learning/services/` is a package (`curriculum.py`, `quran.py`, `progress.py`, `upgrades.py`,
`access.py`), re-exported from `services/__init__.py`. All writes are `transaction.atomic`.

### 8.1 Curriculum

- `levels_queryset()` (annotated `sub_level_count`, `topic_count`), `get_level(id)`.
- `create_level(*, course_id, name_ar, name_en, is_active=True, sub_levels: list[dict]) -> Level`: appends
  at the end of the course; the course must exist (400 `course`).
- `update_level(level, *, name_ar, name_en, is_active, sub_levels)`: the course cannot change (400
  `course` if sent different). Sub-level and topic ids that do not belong to this level → 400 (field
  `sub_levels`). Replaces as C-2; deleting a completed topic → 409 `learning.topic_in_use`.
- `delete_level(level)`: 409 `learning.level_in_use` if any `StudentLevel` or `LevelUpgradeRequest` points to it.
- `reorder_levels(*, course_id, ids)`: `ids` must be exactly the course's level ids (400 `ids`).
- Limits (400): at most 50 sub-levels per level and 200 topics per sub-level [assumed]; at least one
  sub-level is not required (a level may be just a name) [assumed].
- Topic chapter rules (C-5): `from_verse`/`to_verse` both or neither; 1 ≤ from ≤ to ≤ `verses_count`
  (400 on the topic's path, e.g. `sub_levels[0].topics[2].to_verse`). A chapter on a topic while
  `quran_chapters` is off → 400.

### 8.2 Qur'an chapters

- `sync_chapters() -> SyncResult(created, restored)`: upserts the 114 rows from the data file by `number`,
  setting every field. Idempotent.
- `update_chapter(chapter, *, name_arabic, name_simple, name_complex)` — only names are editable.
- The data file is generated by a one-off script `backend/scripts/fetch_quran_chapters.py` (not run in CI)
  and validated by a test: 114 rows, numbers 1–114, verse counts summing to 6236, pages within 1–604.

### 8.3 Access helpers

- `teaches(teacher_user_id, student_user_id, course_id) -> bool` (B6-5).
- `taught_pairs(teacher_user_id) -> QuerySet` of (student_user_id, course_id) the teacher teaches, for
  scoping lists.
- `can_view_progress(user, student_user_id) -> bool`: office (holding `student_level.view_any` or
  admin), a teacher teaching the student in **some** course (they see that course only — enforced by the
  list scoping and by `teaches` on the detail), the student themself, a parent of the student
  (`identity.services.is_parent_of`).

### 8.4 Progress

- `current_levels(user, *, course=None, level=None, search="")`: the list (§6) scoped by role.
- `progress(student_user_id, course_id) -> ProgressDetail` (current level, history, the course's levels with
  sub-levels and topics and each topic's completion).
- `set_level(*, student_user_id, course_id, level_id, by)`: C-7/C-8. The student must be an active student
  (400 `student`); a teacher with a current level already present → 403 `learning.office_only`; same level
  as current → no-op returning the current row.
- `complete_topic(*, student_user_id, topic_id, completed_on=None, by)` (idempotent: an existing completion
  is returned unchanged) and `uncomplete_topic(*, student_user_id, topic_id, by)` (missing → no-op). The
  topic's course gives the course for the `teaches` check. `completed_on` may not be in the future (400).
- `progress_of(student_user_id) -> list[Progress]` for B10 (B6-9): per course with a current level —
  `course_id`, `level_id`, `level_name_en`, `level_name_ar`, `started_on`, `completed_topics`,
  `total_topics`, `completed_this_month` (topics completed in the current academy month).

### 8.5 Upgrade requests

- `request_upgrade(*, student_user_id, course_id, subscription_id=None, note="", by)`: C-10/C-11. A given
  subscription must be the student's in that course (400 `subscription`).
- `approve_request(req, *, by)`, `reject_request(req, *, reason, by)`: only `pending` (else 409
  `learning.request_decided`); C-11.
- `pending_requests_count()` for the nav badge; `requests_queryset(user, status)` scoped (office all; a
  teacher the requests for students they teach, read-only after asking).

## 9. B6a API

All under `/api/v1/learning/`, all `FeatureOn` (404 when off), all via `etqan.platform.permissions`.
Students are addressed by **user id**, as the scheduling API does.

| Method & path | Who | Notes |
|---|---|---|
| `GET levels/?course=` | `level.view_any`; teacher, student, parent (C-14) | paginated as other catalogue lists; each with `sub_level_count`, `topic_count` |
| `POST levels/` | `level.create` | body: `course`, `name_ar`, `name_en`, `is_active`, `sub_levels[{id?, name_ar, name_en, topics[{id?, name_ar, name_en, chapter?, from_verse?, to_verse?}]}]` |
| `GET levels/<id>/` | `level.view`; teacher, student, parent (C-14) | full tree |
| `PUT levels/<id>/` | `level.update` | same body as POST (C-2) |
| `DELETE levels/<id>/` | `level.delete` | 409 `learning.level_in_use` |
| `POST levels/reorder/` | `level.reorder` | `{course, ids}` |
| `GET quran-chapters/` | `quran_chapter.view_any`; teacher, student, parent (C-14); switch `quran_chapters` | all 114, unpaginated |
| `PATCH quran-chapters/<id>/` | `quran_chapter.update` | names only |
| `POST quran-chapters/sync/` | `quran_chapter.create` | `{created, restored}` |
| `GET student-levels/?course=&level=&search=` | office `student_level.view_any`; teacher (scoped) | current levels list |
| `GET students/<student_id>/progress/` | B6-4 (`can_view_progress`) | `progress_of`-shaped summary per course (for "My progress" and the card) |
| `GET students/<student_id>/progress/<course_id>/` | office; teacher who teaches; the student; a parent | `ProgressDetail` |
| `PUT students/<student_id>/progress/<course_id>/level/` | office `student_level.update`; teacher (first level only) | `{level}` |
| `PUT students/<student_id>/progress/<course_id>/topics/<topic_id>/` | office `student_level.update`; teacher who teaches | `{completed_on?}`; topic must belong to the course (404 otherwise) |
| `DELETE students/<student_id>/progress/<course_id>/topics/<topic_id>/` | same | untick |
| `GET level-upgrades/?status=&student=&course=` | office `level_upgrade_request.view_any`; teacher (scoped) | |
| `POST level-upgrades/` | office `level_upgrade_request.create`; teacher who teaches | `{student, course, subscription?, note?}` |
| `POST level-upgrades/<id>/approve/` | `level_upgrade_request.update` (office) | |
| `POST level-upgrades/<id>/reject/` | `level_upgrade_request.update` (office) | `{reason}` required |

Errors use `etqan.platform.exceptions` (`ValidationError` with field and, per ledger D25, a `code` where one
is named above; `ConflictError` with code). A student or parent calling a write endpoint gets 403; a
teacher on a student they do not teach gets 404.

## 10. B6a seeds, switches and wiring

- Registry: `levels` flipped to `Feature(..., built=True)` (off); `quran_chapters` new under the B6 marker
  ("Qur'an chapters" / "سور القرآن الكريم", group `teaching`, built, off).
- `seed_b6(subdomain)` (demo only, idempotent, through services): syncs the Qur'an chapters; for the demo's
  Qur'an course, three levels ("Juz' Amma", "Juz' Tabarak", "Al-Baqarah") with two sub-levels each and topics
  linked to chapters; for one other course one level with two topics; gives two demo students a current
  level, a few completed topics, and one pending upgrade request. Switches stay off (e2e turns them on with
  `set_features`).
- Dashboard: `FeatureCode` gains `levels`, `quran_chapters`; NAV_ITEMS under the B6 marker (office
  Levels, Qur'an chapters, Student levels, Level upgrades with the pending badge; teacher "My students'
  levels"; student/parent "My progress"); locales `curriculum.json` (en, ar).

## 11. B6a tests

- **Backend (pytest, tenant fixtures as existing apps):** level create / replace / reorder / delete rules
  (C-2 conflicts, foreign ids, limits); topic chapter validation; chapter data file invariants and sync
  idempotence (created then restored counts, edited names restored); `teaches` across statuses (active,
  paused yes; expired, cancelled no; other course no); set_level rules for office and teacher (first only,
  403 after); one-current-level constraint; complete / uncomplete idempotence and future date; upgrade
  request rules (no level, top level, pending twice, approve moves level, level changed 409, reject needs
  reason, decided final); scoping for every endpoint and role (office with and without codes, teacher
  teaching / not teaching → 404, student own / other → 404, parent child / not child); every endpoint 404
  with the switch off; `progress_of` shape; seed idempotence. Coverage ≥ 80 %; `lint-imports` clean.
- **Dashboard (Vitest + Testing Library + MSW):** levels list and the nested repeater form (add / remove /
  reorder sub-levels and topics, chapter pre-fill, 409 message); chapters table and sync toast; student
  levels list and progress panel (office vs teacher actions, topic tick / untick, request upgrade states);
  upgrades tabs, approve, reject needs a reason; My progress for a student and a parent with two children;
  nav items gated by switch, role and permission; locale parity.
- **e2e `e2e/b6-curriculum.spec.ts`:** switches on; admin syncs chapters, creates a level with a sub-level
  and a chapter-linked topic; sets a demo student's level; a teacher of that student ticks a topic and
  requests an upgrade; the admin approves it; the student sees the new level on My progress.
