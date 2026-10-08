# Plan 56 — B5d More automatic notices — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The every-minute scan learns twelve more notices, each a finder over a read service its owner publishes, and reminders follow a moved session:
- three teacher/session notices (early reminder, teacher-absent apology, session-ended nudge);
- postponed, compensation booked, trial booked and substitution;
- homework set / answered / completed;
- level upgrade requested / decided.

**Architecture:**
- Everything is in `etqan.notifications`: the B5a catalogue, finders, recipients and templates, extended.
- Scheduling's reads are already on main (`notice_reads.py`: `teacher_absences_marked`, `sessions_ended`, `postponements`, `sessions_booked`, `substitutions`).
- Learning's reads (R7) are built here under a ledger claim on `etqan.learning` (D58): `learning/services/notices.py`.
- One notifications migration: it alters choices and widens `target_kind` to 16.
- The dashboard shows the new types in the settings form, the templates page and the log.

**Tech Stack:** Django 5 + DRF + django-tenants, pytest; React + TanStack + i18next, vitest; Playwright.

**Spec:** `docs/superpowers/specs/2026-10-07-b5d-more-notices-design.md`, with the phase spec `docs/superpowers/specs/2026-10-07-b5-communication-design.md`.

**Requires:** B5a, B5b and B2f (all merged before Task 1 starts), B2g (merged).

## Global Constraints

- **New types** (`kinds.Kind`; target · default / range · category · roles · duty roles):

| Type | Target | Default / range | Category | Roles | Duty roles |
|---|---|---|---|---|---|
| `session.teacher_early_reminder` | session | 120 / 30–1440 | sessions | teacher | — |
| `session.teacher_absent` | session | none | sessions | student, parent | — |
| `session.ended` | session | 5 / 1–55 | sessions | teacher | — (not a duty) |
| `session.postponed` | session | none | schedule | student, parent, teacher | — |
| `session.compensation_booked` | session | none | schedule | student, parent, teacher | — |
| `session.trial_booked` | session | none | schedule | student, parent, teacher | — |
| `schedule.substitution` | subscription | none | schedule | student, parent, teacher | — |
| `homework.set` | homework | none | reports_homework | student, parent | — |
| `homework.answered` | homework | none | reports_homework | teacher | — |
| `homework.completed` | homework | none | reports_homework | student, parent | — |
| `level.upgrade_requested` | upgrade | none | reports_homework | admin | — |
| `level.upgrade_decided` | upgrade | none | reports_homework | student, parent, teacher | — |

- **Targets:**
  - `kinds.HOMEWORK = "homework"` and `kinds.UPGRADE = "upgrade"` join `TARGETS`;
  - `Notification.target_kind` is widened to `max_length=16`.
- **Placeholders**, as additions to `text.PLACEHOLDERS`:
  - `session.postponed` adds `old_time`;
  - `schedule.substitution` uses `student, course, teacher, regular_teacher, from, to`;
  - homework types use `student, course, title`;
  - level types use `student, course, level`, plus `outcome` for `decided`.
- **Feature gating**, in scan `FEATURE_OF`, which becomes `type -> tuple[str, ...]` with all of them required:

| Type | Features |
|---|---|
| `session.ended` | `teacher_attendance` |
| `session.postponed` | `postponement`, `activity_log` |
| `session.compensation_booked` | `compensation_sessions` |
| `session.trial_booked` | `trial_sessions` |
| `schedule.substitution` | `weekly_schedules` |
| `homework.*` | `homework` |
| `level.*` | `levels` |

  `session.teacher_absent` and `session.teacher_early_reminder` are ungated. Existing entries become one-element tuples.
- **Occurrences:**
  - `session.postponed` uses the activity entry id;
  - the four reminder types (`session.reminder`, `session.early_reminder`, `session.teacher_reminder`, `session.teacher_early_reminder`) use the session's `starts_at` as ISO UTC;
  - `schedule.substitution` uses the substitution id;
  - every other new type uses `""`.
- **R7** (under claim): `etqan/learning/services/notices.py` exports `HomeworkNotice`, `UpgradeNotice`, `homework_notices(*, since, until)` and `upgrade_notices(*, since, until)` from `etqan.learning.services`, with sorted `__all__`. It is unscoped and read-only, with a fixed query count asserted by `django_assert_num_queries`. It makes no change to existing learning models, services or routes and adds no learning migration. Learning tests reach scheduling only via `etqan.scheduling.tests.conftest`.
  - Claim: `python3 scripts/orchestration/ledger.py claim B5 learning --reason "R7"` right before that commit.
  - Release after merge.
- **Import contract:** the notifications contract's forbidden list gains `etqan.learning.models` and `etqan.learning.api`.
- **Migration:** one `etqan/notifications/migrations/0004_more_notices.py`, with choices and `target_kind` length only.
- **Dashboard:**
  - `TYPE_INFO` and `NOTIFICATION_TYPES` gain the twelve types;
  - notification strings (en/ar) go in the existing `notifications.json`;
  - the settings form and templates page gain the groups schedule, homework and levels.
- **Coverage:** backend ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- **Tools:** run from the meta root:
  `S() { (set -a; . ./.env.stream; set +a; docker compose -f docker-compose.local.yml exec -T "$@"); }`
  - tests: `S django pytest etqan/notifications etqan/learning -q`;
  - lint: `S django ruff check etqan && S django ruff format --check etqan && S django lint-imports`;
  - migrations: `just _stack-manage makemigrations notifications --name more_notices` and `just migrate`;
  - dashboard: `S dashboard pnpm vitest run …` / `tsc` / `lint`;
  - e2e: `just e2e e2e/b5-notices.spec.ts`.

## Review Focus

1. A session postponed twice notifies twice, and the mover is not told about their own move. Task 3 tests both.
2. A reminder already sent for a session that is then postponed is sent again at the new time, exactly once. Task 2 tests it.
3. `homework.answered` reaches only a teacher setter (office-set homework tells nobody), and `level.upgrade_decided` reaches the requester only when they are a teacher. Task 5 tests both.
4. `target_kind` "homework" and "upgrade" fit, and no scan's `bulk_create` fails. Task 1 tests the length.
5. Every new finder costs a fixed number of queries for 1 vs many hits. Tasks 3 and 5 test it.

---

### Task 1: Catalogue — types, targets, placeholders, texts, samples, migration

**Files:**
- Modify: `backend/etqan/notifications/kinds.py`, `text.py`, `models.py` (`target_kind` 16)
- Create: migration `0004_more_notices.py`
- Tests: `tests/test_kinds.py`, `tests/test_text.py`, `tests/test_templates.py` (invariants extend)

**Interfaces:**
- **`kinds`:** twelve type constants (`TEACHER_EARLY_REMINDER`, `TEACHER_ABSENT`, `ENDED`, `POSTPONED`, `COMPENSATION_BOOKED`, `TRIAL_BOOKED`, `SUBSTITUTION`, `HOMEWORK_SET`, `HOMEWORK_ANSWERED`, `HOMEWORK_COMPLETED`, `UPGRADE_REQUESTED` and `UPGRADE_DECIDED`) with `Kind` rows per the table; `HOMEWORK` and `UPGRADE` targets.
- **`text.Facts`** gains `old_starts_at`, `title`, `level_ar`, `level_en`, `outcome_approved: bool | None`, `teacher`, `regular_teacher`, `from_on` and `to_on`.
- **`text.render`** fills `old_time`, `title`, `level` (by language), `outcome` (en "approved" / "not approved", ar "تمت الموافقة" / "لم تتم الموافقة"), `teacher`, `regular_teacher`, `from` and `to` (ISO dates).
- **`text.TEMPLATES`** gets en/ar texts for the twelve types:

| Type | en title | en body | ar title | ar body |
|---|---|---|---|---|
| teacher_early_reminder | "Coming up: {course}" | session body | "حصة قادمة: {course}" | session body |
| teacher_absent | "Teacher absent: {course}" | "The teacher could not attend {course} with {student} at {time}. We apologise; the academy will contact you about a make-up." | "غياب المعلم: {course}" | "تعذّر على المعلم حضور حصة {course} مع {student} في {time}. نعتذر، وستتواصل معكم الأكاديمية بشأن التعويض." |
| ended | "Please mark the session: {course}" | "{course} with {student} at {time} has ended. Please mark attendance and write the report." | "سجّل الحصة: {course}" | "انتهت حصة {course} مع {student} في {time}. يرجى تسجيل الحضور وكتابة التقرير." |
| postponed | "Session moved: {course}" | "{course} with {student} moved from {old_time} to {time}." | "تم تأجيل الحصة: {course}" | "نُقلت حصة {course} مع {student} من {old_time} إلى {time}." |
| compensation_booked | "Make-up session booked: {course}" | "A make-up session of {course} for {student} is booked for {time}." | "حجز حصة تعويضية: {course}" | "حُجزت حصة تعويضية في {course} لـ{student} في {time}." |
| trial_booked | "Trial session booked: {course}" | "A trial session of {course} for {student} is booked for {time}." | "حجز حصة تجريبية: {course}" | "حُجزت حصة تجريبية في {course} لـ{student} في {time}." |
| substitution | "Substitute teacher: {course}" | "{teacher} will teach {course} for {student} instead of {regular_teacher} from {from} to {to}." | "معلم بديل: {course}" | "سيدرّس {teacher} مادة {course} لـ{student} بدلًا من {regular_teacher} من {from} إلى {to}." |
| homework.set | "New homework: {title}" | "{student} has new homework in {course}: {title}." | "واجب جديد: {title}" | "لدى {student} واجب جديد في {course}: {title}." |
| homework.answered | "Homework answered: {title}" | "{student} answered the homework {title} in {course}." | "تمت الإجابة على الواجب: {title}" | "أجاب {student} عن الواجب {title} في {course}." |
| homework.completed | "Homework completed: {title}" | "{student}'s homework {title} in {course} is complete." | "اكتمل الواجب: {title}" | "اكتمل واجب {student} {title} في {course}." |
| upgrade_requested | "Level upgrade requested: {student}" | "An upgrade of {student} to {level} in {course} is waiting for a decision." | "طلب رفع مستوى: {student}" | "طلب رفع مستوى {student} إلى {level} في {course} بانتظار القرار." |
| upgrade_decided | "Level upgrade {outcome}: {course}" | "The upgrade of {student} to {level} in {course} was {outcome}." | "رفع المستوى — {outcome}: {course}" | "طلب رفع مستوى {student} إلى {level} في {course}: {outcome}." |

- **`text.SAMPLE_FACTS`** gains HOMEWORK (title "Surah Al-Mulk, verses 1–10") and UPGRADE (level "Level 2" / "المستوى الثاني", outcome approved) samples. The SUBSCRIPTION sample gains a teacher, a regular teacher and dates for the substitution preview.

- [ ] **Step 1: Tests (RED).**
  - `test_kinds`: every new type has its category, roles and duties per the table; `categories_for("student")` now includes `schedule` and `reports_homework`; `categories_for("teacher")` includes `schedule` and `reports_homework`.
  - The `PLACEHOLDERS` and built-in-template invariant tests pass for all types.
  - Every `TARGETS` entry has a sample.
  - A Notification with `target_kind="homework"` saves.
  - Render cases for `old_time`, `outcome` in both languages, `level` by language, and the substitution placeholders.
- [ ] **Step 2: Implement; generate the migration; `just migrate`.**
- [ ] **Step 3: Run the notifications suite and lint.**
- [ ] **Step 4: Commit** `feat(notifications): twelve more notice types in the catalogue (B5d)`.

### Task 2: Recipients, links, gating tuples, reminder occurrences

**Files:** `finders.py` (`Hit` gains `extra_teacher`, `requester` and `exclude_user_id`; `AUDIENCES` parts `EXTRA_TEACHER` and `REQUESTER`; `PART_ROLES`), `recipients.py`, `links.py`, `services/scan.py` (`FEATURE_OF` as tuples), and the tests.

- **`recipients.resolve`:** the new parts resolve to `hit.extra_teacher` and `hit.requester`. `REQUESTER` counts only when that user's role is `teacher`. `hit.exclude_user_id` is never told.
- **`links.path_for`:**
  - `homework`: student/parent → `/learning/homework`, teacher → `/teaching/homework`, else home;
  - `upgrade`: admin/staff → `/scheduling/level-upgrades`, student/parent → `/learning/progress`, teacher → `/teaching/levels`;
  - `substitution` (target subscription) uses the existing subscription branch.

  Check the routes exist in `dashboard/src/routes/_authed`.
- **Reminders:** `_reminder` hits use `occurrence=session.starts_at.isoformat()`.

- [ ] **Tests (RED):**
  - the new parts resolve, with a non-teacher requester dropped and `exclude_user_id` honoured;
  - links per role;
  - `FEATURE_OF` with two features needs both;
  - a reminder is created again after `starts_at` changes, and only once per start (Review Focus 2).
- [ ] **Implement, run and commit** `feat(notifications): recipients, links and gating for the new notices (B5d)`.

### Task 3: Session and schedule finders (scheduling reads)

**Files:** `finders.py`, `tests/test_finders_b5d.py`.

Each finder takes `(now, today, value)` like Plan 8's and uses `scheduling_services` only:
- `teacher_early_reminder`: `sessions_starting(now=now, within=value)`; audience `(TEACHER,)`.
- `teacher_absent`: `teacher_absences_marked(since=now - LOOK_BACK)`; audience `FAMILY`.
- `ended`: `sessions_ended(now=now, after=timedelta(minutes=value), give_up=GIVE_UP)`; audience `(TEACHER,)`.
- `postponed`: for `p in postponements(since=now - LOOK_BACK, until=now)`:
  - skip it if `p.session.status == "cancelled"`;
  - facts: `starts_at = p.new_starts_at`, `old_starts_at = p.previous_starts_at`;
  - `occurrence = str(p.entry_id)`, `exclude_user_id = p.by_user_id`;
  - audience `(*FAMILY, TEACHER)`.
- `compensation_booked` / `trial_booked`: `sessions_booked(kind=..., since=now - LOOK_BACK, now=now)`; audience `(*FAMILY, TEACHER)`.
- `substitution`: `substitutions(since=now - LOOK_BACK, until=now)`:
  - target subscription, `target_id = subscription_id`, occurrence the substitution id;
  - `teacher` is the substitute user and `extra_teacher` the regular teacher;
  - facts `teacher` (substitute name), `regular_teacher`, `from_on` and `to_on`, plus course and student;
  - audience `(*FAMILY, TEACHER, EXTRA_TEACHER)`.

Register all of them in `FINDERS`.

- [ ] **Tests (RED):** one per finder covering window in/out, gating, recipients and dedupe. Also:
  - a session postponed twice gives two notices;
  - the mover is excluded;
  - a cancelled session is skipped;
  - fixed query counts for 1 vs 5 hits per finder.

  Build data with the scheduling test conftest helpers. Turn `activity_log` and `postponement` on for the postponement tests, and use `scheduling_services.postpone_session`.
- [ ] **Implement, run and commit** `feat(notifications): session and schedule notices (B5d)`.

### Task 4: R7 — learning notice reads (under a claim on etqan.learning)

**Files:** create `backend/etqan/learning/services/notices.py` and `backend/etqan/learning/tests/test_notices.py`; modify `backend/etqan/learning/services/__init__.py` (sorted exports).

- **`HomeworkNotice`:** frozen dataclass with `kind`, `homework_id`, `title`, `course_name_ar`, `course_name_en`, `student` (a StudentProfile with `user` selected), `set_by_user_id`, `set_by_role` and `at`.
- **`homework_notices(*, since, until)`:** derived like `homework_events`, with one query that `select_related`s `student__user`, `course` and `set_by`. `set_by_role` is `set_by.role` or None.
- **`UpgradeNotice`:** frozen dataclass with `kind` ("requested" \| "decided"), `request_id`, `student`, `course_name_ar`, `course_name_en`, `level_name_ar`, `level_name_en` (the `to_level`), `status`, `requested_by_user_id`, `requested_by_role` and `at`.
- **`upgrade_notices(*, since, until)`:** "requested" at `created_at` and "decided" at `decided_at` within the window, in one query (with `select_related` as needed). Read the `LevelUpgradeRequest` field names in `learning/models.py`.

Steps:
- [ ] Take the claim: `python3 scripts/orchestration/ledger.py claim B5 learning --reason "R7"` (from the meta root).
- [ ] **Tests (RED):** each kind in and out of the window; `set_by_role` for teacher, office and None; `django_assert_num_queries` for 1 vs 5 rows.
- [ ] **Implement, run** `S django pytest etqan/learning -q` and lint, then **commit** `feat(learning): unscoped notice reads for homework and level upgrades (R7, B5d)`. Record the claim in the phase notes; release it after B5d merges.

### Task 5: Homework and level finders

**Files:** `finders.py`, `pyproject.toml` (notifications contract forbids `etqan.learning.models` and `etqan.learning.api`), and tests.

- **Homework:** one finder each for `homework.set`, `homework.answered` and `homework.completed`, from `learning_services.homework_notices(since=now - LOOK_BACK, until=now)` filtered by kind.
  - Target homework, `target_id = homework_id`, occurrence `""`.
  - Facts: student name, course names, title.
  - Audiences: set and completed → `FAMILY`; answered → `(REQUESTER,)`, with `requester` = the setter's user when `set_by_role == "teacher"`, else None.

  Load the requester users with `identity_services.get_users` in one query.
- **Levels:** `level.upgrade_requested` (audience `(ADMINS,)`) and `level.upgrade_decided` (audience `(*FAMILY, REQUESTER)`, requester only when a teacher), from `upgrade_notices`.
  - Facts: level names and `outcome_approved = status == "approved"`.
  - Target upgrade, `target_id = request_id`.

- [ ] **Tests (RED):**
  - each type, plus Review Focus 3 (an office-set homework tells nobody on answer; an office-requested upgrade tells only the family);
  - gating by `homework` / `levels`;
  - fixed query counts.
- [ ] **Implement, run** (notifications and learning suites, `lint-imports`) **and commit** `feat(notifications): homework and level-upgrade notices (B5d)`.

### Task 6: Dashboard — new types in settings, templates, log and bell

**Files:** `dashboard/src/features/notifications/schemas.ts` (`NOTIFICATION_TYPES`, `TYPE_INFO` with labels and value ranges for `session.teacher_early_reminder` (30–1440) and `session.ended` (1–55)), `NotificationSettingsForm.tsx` (groups schedule, homework, levels), `TemplatesPage.tsx` (same groups), the `PreferencesCard` category labels (exist), locales `notifications.json` en/ar, and the tests.

- [ ] **Tests (RED):**
  - the settings form shows the new groups with the numbers' ranges;
  - the templates page lists them;
  - the log shows their labels;
  - the bell renders a homework notice with a link.
- [ ] **Implement, then run** vitest, tsc and lint.
- [ ] **Commit** `feat(notifications): new notice types in settings, templates and log (B5d)`.

### Task 7: e2e and gates

- [ ] `e2e/b5-notices.spec.ts`:
  1. `set_features demo --on postponement activity_log homework`;
  2. as the admin, postpone a stamped student's session through the API;
  3. run `manage("scan_notifications", "demo")` (check the command name in `backend/etqan/notifications/management/commands`);
  4. the student's bell shows "Session moved";
  5. as the admin, set homework for that student through the API and scan;
  6. the student sees "New homework".

  Copy the helpers from `b5-broadcasts.spec.ts`.
- [ ] **Gates:** `just migrate`, `just test`, `just lint`, `just secrets`, `just e2e`, and dashboard coverage.
- [ ] **Commit** `test(e2e): B5d notices`.
