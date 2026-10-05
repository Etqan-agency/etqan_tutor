# Phase B6 — Learning — Design

**Date:** 2026-10-05
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); review findings applied 2026-10-05.
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
| B6-5 | **"Teaches"**: a teacher teaches a student in a course while some subscription of that student in that course with that teacher is `active` or `paused` (`scheduling.services.subscriptions_queryset`). The values are compared as the strings `"active"` / `"paused"` (learning never imports scheduling's models). Past teachers, B2g substitute teachers and a session's one-off teacher get no access [assumed]. One helper, `learning.services.teaches(teacher_user_id, student_user_id, course_id)`, is the only implementation. | [assumed]; Plan 4 statuses |
| B6-6 | **B6 sends no notifications.** Homework, upgrade-request and certificate notices are B5's (the student preference "reports & homework notifications", COMM-004/005): B6 exposes read-only service queries B5's finders can call (each slice names its own), and adds no notification kind. Notifications are pull-based and no app imports `etqan.notifications`. | TH §2.1 PEOPLE-001 preferences; `pyproject.toml` contract "no app imports notifications" |
| B6-7 | **Files are private.** Homework files and answers, teaching content, certificate templates and student photos are stored on `STORAGES["private"]` through `etqan.platform.uploads.check_upload` (ledger D12) and streamed by authenticated endpoints that apply B6-4's scoping; nothing B6 stores gets a public URL, and no uploaded HTML or SVG is accepted (ledger D2). | ledger D2, D12; spec 2026-10-03-platform-extras A-10 |
| B6-8 | **XP points and student tags already exist** (Plan 12, `StudentProfile.xp`, `Tag`). No B6 slice changes them automatically: awarding XP stays a manual office edit [assumed: TH's reward mechanism is UNKNOWN, TH V32]. | TH §2.1 PEOPLE-001; TH §6 V32 |
| B6-9 | **What B10 reads:** `learning.services.progress_of(student_user_id, *, month) -> list[CourseProgress]` (B6a §8.4: per course, the level at the month's end, topics completed in the month, level changes and upgrade decisions in the month; the month is the calendar month in the academy's timezone) and each later slice's read service (homework, reviews, certificates). Recorded as a shared decision so B10 designs against it. | roadmap §2 (B10 depends on B6) |
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
| **B6c** | reviews & honour board | Session reviews (a rating of a completed session; P1 shows an office "add review" action, so the office can add one; whether students / parents write them too is [assumed] in B6c's spec); honour board (office-published recognitions of students, shown to the academy's users) | SCHED-010, PEOPLE-007 | `session_reviews`, `honour_board` | S–M |
| **B6d** | certificates | Certificate templates (title, description, image ≤ 5 MB); issued certificates (type completion / appreciation / pride / custom template, student, course, completed-session count auto-filled from student + course, optional photo ≤ 2 MB, message); a printable certificate page (template image + overlaid text; no SVG / HTML templates, D2); verified certificates: an anonymous, throttled verification page by an unguessable code; the course "certificate" toggle as a learning-owned `CourseCertificate(course one-to-one)` row, not a catalogue field (B6-1, B6-10) | CERT-001, CERT-002, CERT-003, FLOW-011, BR-31, BR-39 | `certificates`, `verified_certificates` (flipped; requires `certificates`) | M |

Order: B6a, B6b, B6c, B6d. B6a goes first because B10 needs progress data soonest and it has the most
confirmed evidence.

Not taken by any B6 slice, with the reason:

- **AI monthly student reports** (EXP-001) and AI anything: B10.
- **Monthly teacher evaluation** (TH V27, SYS-004 action): behaviour UNKNOWN; not built (as B9a A-15).
- **Certificates for recorded courses** (playlist "accredited certificate", RC-003 "certificate obtained"):
  B7, which may reuse B6d's certificate service.
- **Note for the conductor:** the B2 phase spec's slice table says B2f "unblocks B6 (student levels on
  subscriptions)"; B6-3 keys levels by student and course, so B6 needs nothing from B2f.
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
  and `etqan.scheduling.services`. It has `allow_indirect_imports = true` and `ignore_imports` entries for
  `etqan.learning.tests.* -> etqan.<app>.models` (identity, catalogue, scheduling) so tests can build fixtures.
- New translation areas are new files `dashboard/src/locales/{en,ar}/<area>.json` (en and ar only, ledger
  D11/D22). New e2e specs are `e2e/b6-*.spec.ts`.
- **R-B6-1 (request to B2, optional, non-blocking):** one line in
  `dashboard/src/routes/_authed/scheduling.subscriptions.$subscriptionId.tsx` rendering
  `<StudentLevelCard studentId courseId />` exported from `@/features/curriculum` (it renders nothing while
  `levels` is off or the viewer may not read the student's progress), once B6a merges.

---


# Slice B6a — Curriculum

## 5. B6a decisions

| # | Decision | Source |
|---|---|---|
| C-1 | **Levels belong to one course** and are ordered (`position`). A level has an Arabic and English name, an active flag, and an ordered list of **sub-levels**, each with an ordered list of **topics**. The office edits a level with its sub-levels and topics in one form (TH's repeater) and saves it in one request. | P1 CATALOG-004 (course\*, level name\*, sub-levels repeater with topics); TH §2.2 CATALOG-004 (columns course, level, sub-levels, topic count) · [assumed] bilingual names as every catalogue name |
| C-2 | Saving a level **replaces** its sub-levels and topics with the submitted lists: rows with an `id` of this level are kept and updated (a topic may move to another sub-level of the same level), rows without one are created, rows left out are deleted. A topic some student has completed cannot be deleted, directly or by deleting its sub-level (409 `learning.topic_in_use`); a level that any student level, upgrade request or topic completion points to cannot be deleted (409 `learning.level_in_use`). Rename, move and reorder are always allowed. Deactivating a level hides it from new choices (setting a level, `to_level`) but keeps every record. | [assumed] keep history; Plan 4 "deactivate, don't delete" (plan D6) |
| C-3 | **The Qur'an chapters** are reference data per academy: number (1–114), Arabic, simple and complex names, revelation place (makkah / madinah), revelation order, verse count, start and end page. They come from a **data file shipped with the app** (`etqan/learning/data/quran_chapters.json`, generated once from the public Quran.com API v4 `/chapters` and committed); the office's **"Sync chapters"** action loads it into the academy, creating missing chapters and resetting every field of existing ones. The office may edit a chapter's names. Chapters are never added by hand or deleted — a deliberate deviation from TH's "add" and "bulk delete" (there are exactly 114). | TH §2.2 CATALOG-006 (columns, sync from API, form sections, add, bulk delete); P1 CATALOG-006, INT ("Qur'an chapters API") · [assumed] bundled file instead of a live call: the data never changes, and tenants make no outbound calls |
| C-4 | Qur'an chapters are under the switch **`quran_chapters`** (new, group `teaching`). The list and sync need only it; putting a chapter on a topic needs `levels` and `quran_chapters` (400 on the topic's `chapter` while `quran_chapters` is off). Topics keep an existing chapter when the switch is turned off. | B6-2 |
| C-5 | A topic may name **one chapter and an optional verse range** (`from_verse`–`to_verse`: both or neither, 1 ≤ from ≤ to ≤ the chapter's verse count). Its name stays required (the form pre-fills it from the chapter's name and range). | P1 FLOW-010 ("course optionally linked to the Qur'an curriculum") · [assumed] link at topic level |
| C-6 | The course "linked to the Qur'an curriculum" toggle is not built (§3); no catalogue field is added. | B6-1; [assumed] |
| C-7 | **Student level**: a student has at most one **current level per course** (`StudentLevel` with `ended_on` null; a partial unique constraint). Changing it ends the current row (`ended_on` = today in the academy's timezone) and starts a new one (`started_on` = today); ended rows are the level history. The level must belong to the course (400 `level`) and be active (400 `level`). Setting the current level again is a no-op. | P1 SUB-001 tab "مستويات الطلاب" (per-student level), FLOW-010 · [assumed] history rows |
| C-8 | **Who sets a level**: the office may set or change it at any time. A teacher who teaches the student in the course (B6-5) may set the **first** level only; when the student already has a current level in that course a teacher gets 409 `learning.level_already_set` and must ask for an upgrade instead. | P1 CATALOG-005, FLOW-010 (approval exists, so a level rise is approved) · [assumed] teacher's first-level right |
| C-9 | **Completed topics**: per student and topic (unique), with the date completed (default today in the academy's timezone, never in the future: 400 `completed_on`) and who recorded it. Any topic of the course's levels may be ticked or unticked, whatever the student's current level. The office, and a teacher who teaches the student in the course, may tick and untick. Ticking an already-ticked topic returns it unchanged; unticking a missing one is a no-op. | P1 SUB-001 ("completed topics repeater") · [assumed] who; any level |
| C-10 | **Level upgrade requests**: student, course, the subscription it was raised from (**optional** — P1 marks it required; [assumed] optional so the office can ask from the progress panel), the current level (`from_level`, read-only), the **next level** (`to_level`: the next active level of the course by position, fixed when the request is made), an optional note, status `pending` / `approved` / `rejected`, rejection reason, who asked and who decided, and when. At most one pending request per student and course (409 `learning.request_pending`). No current level → 409 `learning.no_level`; at the last active level → 409 `learning.top_level`; a given subscription not the student's in that course → 400 `subscription`. | P1 CATALOG-005 (student\*, subscription\*, course\*, current level read-only, approve toggle, rejection reason\*); P1 §13.1 (rejection reason when not approved) · [assumed] to_level = next by position, note, one pending, optional subscription |
| C-11 | **Who asks and who decides**: the office, or a teacher who teaches the student in the course, may ask (a teacher asking for a student/course they do not teach → 400 `student`, since the student is in the body). Only the office approves or rejects; decided requests are final (409 `learning.request_decided`). **Approve** moves the student to `to_level` (C-7) provided their current level is still `from_level` (else 409 `learning.level_changed`) and `to_level` is still active (else 409 `learning.level_inactive`); in both cases the request stays pending and the office rejects it. **Reject** requires a reason (400 `reason`). | P1 FLOW-010 (approve → level raised; otherwise reason required) · [assumed] office-only decision |
| C-12 | Levels, student levels and upgrade requests are under **`levels`** (flipped to built, off). Turning it off hides them and keeps every record (FT-4). As everywhere on the platform, the switch is checked after the role check (`[…, FeatureOn]`): a caller who passes the role check gets 404 while it is off; a caller who fails it gets 403 either way. | B6-2; spec 2026-09-30 FT-4; `etqan/platform/permissions.py` FeatureOn |
| C-13 | Access resources (new, under the B6 marker), `in_use` exactly the codes §9 declares: `level` ("Levels" / "المستويات": `view`, `view_any`, `create`, `update`, `delete`, `reorder`); `quran_chapter` ("Qur'an chapters" / "سور القرآن": `view_any`, `create`, `update` — `create` is the sync); `student_level` ("Student levels" / "مستويات الطلاب": `view`, `view_any`, `update`); `level_upgrade_request` ("Level upgrade requests" / "طلبات رفع المستوى": `view_any`, `create`, `update` — approve / reject). Staff need the codes; admins always pass; teachers, students and parents pass by role and B6-4 scoping, never by codes. | `etqan/access/registry.py`; `access/tests/test_routes.py`; P1 permission keys `level`, `level::upgrade::request`, `quran::chapter` |
| C-14 | **Names are readable widely**: levels and chapters (names, not student data) are readable by every teacher, student and parent while the switch is on, and by staff holding any code whose screen needs the names (tuple codes: `GET levels/` accepts `level.view_any`, `student_level.view_any` or `level_upgrade_request.view_any`; `GET quran-chapters/` accepts `quran_chapter.view_any`, `level.create` or `level.update`). | [assumed] names are not personal data; `required_code` tuples |
| C-15 | **Totals**: "completed n / total" counts topics of the course's **active** levels; completions of topics in inactive levels still show in the progress detail but not in the totals. | [assumed] |

## 6. B6a screens (dashboard)

| Who | Where | What |
|---|---|---|
| Office | **Catalogue → Levels** `/catalogue/levels` (nav, group `catalogue`, `level.view_any`, `levels`) | List: course · level · sub-levels · topic count · active; filter by course; move up / down within a course (`level.reorder`); add / edit in a dialog: course (fixed on edit), names, active, a repeater of sub-levels each with a repeater of topics (name ar/en; with `quran_chapters` on: chapter picker + verse range that pre-fills the names); delete. 409s are shown inline with their message. |
| Office | **Catalogue → Qur'an chapters** `/catalogue/quran` (`quran_chapter.view_any`, `quran_chapters`) | Table: number · Arabic name · simple name · revelation place · revelation order · verses · pages; "Sync chapters" (`quran_chapter.create`) with a result toast (created / reset counts); edit names in a dialog. Empty state with the sync button. |
| Office | **Scheduling → Student levels** `/scheduling/student-levels` (`student_level.view_any`, `levels`) | One row per **(student, course) pair** (§8.4 `level_rows`): student · course · level (or "No level") · since · completed n / total; filters: course, level, "no level", student search. A row opens the **progress panel**. |
| Office | **Scheduling → Level upgrades** `/scheduling/level-upgrades` (`level_upgrade_request.view_any`, `levels`) | Tabs pending / approved / rejected (pending count on its tab); columns student · course · from → to · asked by · date · note; approve; reject with a required reason. |
| Teacher | **Teaching → My students' levels** `/teaching/levels` (role teacher, `levels`) | The same rows, scoped to the (student, course) pairs they teach; progress panel with "set first level" (only while none), tick topics, "request upgrade" with a note. |
| Student / parent | **Learning → My progress** `/learning/progress` (roles student, parent, `levels`) | Per course with a level or a completion: current level, the level ladder with each sub-level's topics ticked / not, completed n / total; a parent picks a child. Read-only. |
| Any with access | `StudentLevelCard` (exported) | Compact card for one student + course (current level, completed n / total, "open progress"); renders nothing when `levels` is off or the progress endpoint answers 403/404. Used by R-B6-1. |

The **progress panel** (a drawer, shared by office and teacher): current level and since; "change level"
(office) or "set first level" (teacher, only when none); the course's levels as collapsible sections with
their sub-levels and topic checkboxes (completed date shown next to a ticked topic); level history; the
student's pending request if any; "request upgrade" (hidden when one is pending, when there is no level, or
at the top level).

No nav badge (the shell's `NavItem` has none); the pending count shows on the tab.

## 7. B6a data

```text
etqan.learning.Level
  course        FK catalogue.Course  CASCADE  related_name="+"
  name_ar, name_en   CharField(120)   required
  position      PositiveSmallIntegerField   (dense 0-based order within the course)
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
  chapter       FK QuranChapter  null  PROTECT  related_name="+"
  from_verse, to_verse   PositiveSmallIntegerField  null
  CHECK: from_verse/to_verse null unless chapter set; both null or both set; from_verse <= to_verse
  ordering (position, id)

etqan.learning.QuranChapter
  number        PositiveSmallIntegerField  unique  (1..114)
  name_arabic, name_simple, name_complex   CharField(60)
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
  set_by        FK AUTH_USER  null  SET_NULL  related_name="+"
  created_at
  UNIQUE (student, course) WHERE ended_on IS NULL

etqan.learning.TopicCompletion
  student       FK identity.StudentProfile  PROTECT  related_name="+"
  topic         FK Topic  PROTECT  related_name="completions"
  completed_on  DateField
  recorded_by   FK AUTH_USER  null  SET_NULL  related_name="+"
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
  requested_by, decided_by   FK AUTH_USER  null  SET_NULL  related_name="+"
  decided_at    DateTimeField  null
  created_at
  UNIQUE (student, course) WHERE status = 'pending'
  ordering (-created_at, -id)
```

Positions are rewritten densely by every save and reorder; no unique constraint on position.
`Level.course` is CASCADE so a course without learning history stays deletable exactly as today; a course
whose levels carry history (a student level, a completion, a request — all PROTECT) is refused by the
`ProtectedError` catalogue already turns into its 409 (in practice such a course also has subscriptions,
which catalogue's message names).

## 8. B6a rules and services

`etqan/learning/services/` is a package (`curriculum.py`, `quran.py`, `progress.py`, `upgrades.py`,
`access.py`), re-exported from `services/__init__.py`. All writes are `transaction.atomic`.

### 8.1 Curriculum

- `levels_queryset()` (annotated `sub_level_count`, `topic_count`), `get_level(id)`.
- `create_level(*, course_id, name_ar, name_en, is_active=True, sub_levels: list[dict]) -> Level`: appended
  at the end of the course; an unknown course → 400 `course`.
- `update_level(level, *, name_ar, name_en, is_active, sub_levels, course_id=None)`: a different course →
  400 `course`. Sub-level or topic ids not of this level → 400 `sub_levels`. Replaces as C-2; dropping a
  completed topic (alone or with its sub-level) → 409 `learning.topic_in_use`.
- `delete_level(level)`: 409 `learning.level_in_use` when a `StudentLevel`, `LevelUpgradeRequest` or a
  `TopicCompletion` of one of its topics points to it.
- `reorder_levels(*, course_id, ids)`: `ids` must be exactly the course's level ids (400 `ids`).
- Limits (400): at most 50 sub-levels per level and 200 topics per sub-level [assumed]; a level may have no
  sub-levels [assumed].
- Topic chapter rules (C-4, C-5) report on the topic's path, e.g. `sub_levels.0.topics.2.to_verse`.

### 8.2 Qur'an chapters

- `chapters()`; `sync_chapters() -> SyncResult(created, reset)`: upserts the 114 rows from the data file by
  `number`, setting every field; `created` counts new rows, `reset` counts existing rows (all of them,
  changed or not). A second sync answers `created=0, reset=114`.
- `update_chapter(chapter, *, name_arabic, name_simple, name_complex)` — only names are editable.
- The data file is generated by a one-off script `backend/scripts/fetch_quran_chapters.py` (not run in CI)
  and checked by a test: 114 rows, numbers 1–114, verse counts summing to 6236, pages within 1–604,
  `page_start <= page_end`.

### 8.3 Access helpers

- `teaches(teacher_user_id, student_user_id, course_id) -> bool` (B6-5), via
  `scheduling.services.subscriptions_queryset()` filtered on `status__in=("active", "paused")`.
- `taught_pairs(teacher_user_id) -> set[tuple[int, int]]` — the (student_user_id, course_id) pairs.
- `progress_scope(user, student_user_id) -> set[int] | None`: the course ids the user may read for that
  student — `None` for all (admin, or staff holding `student_level.view`), the student themself and a
  parent of the student (`identity.services.is_parent_of`); for a teacher the courses of `taught_pairs`
  with that student (empty → 404); anyone else → 404.

### 8.4 Progress

- `level_rows(user, *, course=None, level=None, no_level=False, search="") -> list[LevelRow]` — the list of
  §6. Office: the union of (student, course) pairs of `active` / `paused` subscriptions and pairs with a
  current `StudentLevel`; teacher: `taught_pairs`. Each row carries the current level (or none), since, and
  completed n / total (C-15). Built in Python and paginated by the view (page size as other lists), ordered
  by student name then course name.
- `progress(student_user_id, course_id) -> ProgressDetail`: current level, history, the course's levels
  with sub-levels and topics and each topic's completion, and the pending request if any.
- `progress_summary(student_user_id, course_ids=None)`: per course with a current level or a completion,
  the card's figures; `course_ids` restricts it (teachers, §8.3).
- `set_level(*, student_user_id, course_id, level_id, by)`: C-7/C-8. An inactive or unknown student →
  400 `student`.
- `complete_topic(*, student_user_id, topic_id, completed_on=None, by)` and
  `uncomplete_topic(*, student_user_id, topic_id, by)`: C-9. The topic must belong to the course in the
  path (404 otherwise).
- `progress_of(student_user_id, *, month: date) -> list[CourseProgress]` for B10 (B6-9). `month` is any day
  in the calendar month wanted, in the academy's timezone. For each course where the student had a level
  at the month's end or completed a topic in the month: `course_id`, `course_name_en`, `course_name_ar`,
  `level_id` / `level_name_en` / `level_name_ar` at the month's end (or none), `completed_in_month`
  (`[{topic_id, name_en, name_ar, completed_on}]`), `completed_total`, `total_topics` (C-15),
  `level_changes` (`[{from_level_id, to_level_id, on}]` from history rows starting in the month) and
  `decisions` (`[{request_id, status, decided_at, rejection_reason}]` decided in the month).

### 8.5 Upgrade requests

- `request_upgrade(*, student_user_id, course_id, subscription_id=None, note="", by)`: C-10/C-11.
- `approve_request(req, *, by)`, `reject_request(req, *, reason, by)`: C-11.
- `requests_queryset(user, *, status=None, student=None, course=None)`: office all; a teacher only requests
  whose (student, course) pair they teach (read-only).

## 9. B6a API

All under `/api/v1/learning/`; every view lists `FeatureOn` last (C-12). Students are addressed by **user
id**, as the scheduling API does. Every route goes into `access/tests/test_routes.py`'s tables.

| Method & path | Permission (codes for staff) | Feature | Notes |
|---|---|---|---|
| `GET levels/?course=` | `HasCode \| (ReadOnly & (IsTeacher \| IsStudent \| IsParent))` — (`level.view_any`, `student_level.view_any`, `level_upgrade_request.view_any`) | `levels` | paginated; `sub_level_count`, `topic_count` |
| `POST levels/` | `HasCode` — `level.create` | `levels` | `course`, `name_ar`, `name_en`, `is_active`, `sub_levels[{id?, name_ar, name_en, topics[{id?, name_ar, name_en, chapter?, from_verse?, to_verse?}]}]` |
| `GET levels/<id>/` | as `GET levels/`, code `level.view` | `levels` | full tree |
| `PUT levels/<id>/` | `HasCode` — `level.update` | `levels` | same body (C-2) |
| `DELETE levels/<id>/` | `HasCode` — `level.delete` | `levels` | 409 `learning.level_in_use` |
| `POST levels/reorder/` | `HasCode` — `level.reorder` | `levels` | `{course, ids}` |
| `GET quran-chapters/` | `HasCode \| (ReadOnly & (IsTeacher \| IsStudent \| IsParent))` — (`quran_chapter.view_any`, `level.create`, `level.update`) | `quran_chapters` | all 114, unpaginated |
| `PATCH quran-chapters/<id>/` | `HasCode` — `quran_chapter.update` | `quran_chapters` | names only |
| `POST quran-chapters/sync/` | `HasCode` — `quran_chapter.create` | `quran_chapters` | `{created, reset}` |
| `GET student-levels/?course=&level=&no_level=&search=` | `HasCode \| (ReadOnly & IsTeacher)` — `student_level.view_any` | `levels` | `level_rows`, scoped |
| `GET students/<student_id>/progress/` | `HasCode \| (ReadOnly & (IsTeacher \| IsStudent \| IsParent))` — `student_level.view` | `levels` | `progress_summary` within `progress_scope` |
| `GET students/<student_id>/progress/<course_id>/` | same — `student_level.view` | `levels` | `ProgressDetail`; course outside `progress_scope` → 404 |
| `PUT students/<student_id>/progress/<course_id>/level/` | `HasCode \| IsTeacher` — `student_level.update` | `levels` | `{level}`; teacher must teach the pair (404) and C-8 |
| `PUT students/<student_id>/progress/<course_id>/topics/<topic_id>/` | `HasCode \| IsTeacher` — `student_level.update` | `levels` | `{completed_on?}`; teacher must teach the pair (404) |
| `DELETE students/<student_id>/progress/<course_id>/topics/<topic_id>/` | same | `levels` | untick |
| `GET level-upgrades/?status=&student=&course=` | `HasCode \| (ReadOnly & IsTeacher)` — `level_upgrade_request.view_any` | `levels` | scoped |
| `POST level-upgrades/` | `HasCode \| IsTeacher` — `level_upgrade_request.create` | `levels` | `{student, course, subscription?, note?}` |
| `POST level-upgrades/<id>/approve/` | `HasCode` — `level_upgrade_request.update` | `levels` | |
| `POST level-upgrades/<id>/reject/` | `HasCode` — `level_upgrade_request.update` | `levels` | `{reason}` |

Errors use `etqan.platform.exceptions`: `ValidationError` with its field (no codes: ledger D25 is not on
trunk yet and B6a needs none) and `ConflictError` with the codes above. A student or parent calling a write
endpoint gets 403; a teacher on a pair they do not teach gets 404 (path) or 400 `student` (body).

## 10. B6a seeds, switches and wiring

- Registry: `levels` flipped in place to `Feature(..., built=True)` (off); `quran_chapters` new under the B6
  marker ("Qur'an chapters" / "سور القرآن الكريم", group `teaching`, built, off).
- `seed_b6(subdomain)` in `etqan/tenants/seeds/b6.py`, called from `seed_academy` in
  `etqan/tenants/management/commands/seed_dev.py` under the B6 marker (demo only, idempotent, through
  services): syncs the Qur'an chapters; when the academy has the "Quran Memorisation" course (skipped
  otherwise), three levels ("Juz' Amma", "Juz' Tabarak", "Al-Baqarah") with two sub-levels each and topics
  linked to chapters; for one other course one level with two topics; gives two demo students a current
  level, a few completed topics, and one pending upgrade request. Switches stay off (e2e turns them on with
  `set_features`).
- Dashboard: `FeatureCode` gains `levels`, `quran_chapters`; NAV_ITEMS under the B6 marker (office Levels,
  Qur'an chapters, Student levels, Level upgrades; teacher "My students' levels"; student/parent "My
  progress"); locale area `curriculum.json` (en, ar), which also holds the `learning.*` error messages (as
  `finance.errors.*` does), not the shared `errors.json`.

## 11. B6a tests

- **Backend (pytest, tenant fixtures as existing apps):** level create / replace (moving a topic between
  sub-levels, foreign ids, limits) / reorder / delete, including 409 for a completed topic dropped alone or
  with its sub-level and for a level whose only history is a completion; topic chapter validation and the
  switch rule; chapter data file invariants and sync counts (`114/0` then `0/114`, edited names reset);
  `teaches` across statuses (active, paused yes; expired, cancelled no; other course no); `set_level` for
  office and teacher (first only, then 409 `learning.level_already_set`; inactive / foreign level 400); the
  one-current-level constraint; complete / uncomplete idempotence and future date; upgrade request rules
  (no level, top level, pending twice, approve moves level, level changed, level inactive, reject needs a
  reason, decided final, teacher not teaching → 400); `level_rows` contents (subscription pairs without a
  level, level pairs without a live subscription, teacher scope); scoping for every endpoint and role
  (office with and without codes, tuple-code reads, teacher of course A not seeing course B in the summary
  or detail, student own / other → 404, parent child / not child); 404 when a switch is off for callers who
  pass the role check; `progress_of` for a past month (level at month end, completions and changes in the
  month only); the access route tables; seed idempotence and the skip without the Qur'an course.
  Coverage ≥ 80 %; `lint-imports` clean.
- **Dashboard (Vitest + Testing Library + MSW):** levels list and the nested repeater form (add / remove /
  reorder sub-levels and topics, chapter pre-fill, 409 message); chapters table and sync toast; student
  levels list (rows without a level, filters) and progress panel (office vs teacher actions, topic tick /
  untick, request upgrade states); upgrades tabs, approve, reject needs a reason; My progress for a student
  and for a parent with two children; `StudentLevelCard` hidden on 403/404; nav items gated by switch, role
  and permission; locale parity.
- **e2e `e2e/b6-curriculum.spec.ts`:** switches on; the admin syncs chapters and creates a level with a
  sub-level and a chapter-linked topic; on Student levels the admin opens a demo student's row with no
  level and sets the level; a teacher of that student ticks a topic and requests an upgrade; the admin
  approves it; the student sees the new level on My progress.
