# Plan 38 — B6c Session Reviews & Honour Board Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Session reviews (1–5 stars + comment on an attended session, written by the student, a parent or the office; read by the office, the session's teacher and the family) and an office-managed honour board read by everyone, in `etqan.learning`, with API, dashboard and e2e, behind the switches `session_reviews` and `honour_board` (off by default).

**Architecture:** Two new models in `etqan.learning`; services `services/reviews.py`, `services/honour.py`; views in `api/review_views.py`, `api/honour_views.py`. Dashboard features `src/features/reviews/`, `src/features/honour/`.

**Tech Stack:** Django 5 + DRF + django-tenants + pytest; React + TanStack Router/Query + Vitest; Playwright.

**Spec:** `docs/superpowers/specs/2026-10-05-b6c-reviews-honour-design.md` (R-1…R-10). Phase spec `docs/superpowers/specs/2026-10-05-b6-learning-design.md`. Ledger D32 (hooks).

**Requires:** B6a (merged). Branch `feat/b6c-reviews` off trunk after B6b merges.

## Global Constraints

- Work from `/home/abdulkhalek/Projects/etqan_tutor-wt/b6`; `backend/`, `dashboard/` are git worktrees on `feat/b6c-reviews`. Never run writing `git submodule` commands. Never touch the main checkout `/home/abdulkhalek/Projects/etqan_tutor`.
- Run via `D=/home/abdulkhalek/.claude/jobs/0bc5cdff/tmp/dc`: `D pytest <paths> -q`, `D django ruff check .`, `D django ruff format --check .`, `D django lint-imports`, `D manage makemigrations learning` then `just migrate`, `D dash pnpm vitest run <paths>`, `D dash pnpm tsc --noEmit`, `D dash pnpm lint`; suites `just test`, `just lint`, `just e2e [spec]`, `just seed`.
- Coverage: backend ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- Logic in `etqan/learning/services/`; learning imports only `etqan.platform`, `etqan.identity.services`, `etqan.catalogue.services`, `etqan.scheduling.services`, `etqan.academy.services`. Scheduling values compared as strings.
- Shared lists: lines only under `── phase B6 ──` markers; access route tables: append to the existing `# Phase B6` blocks.
- Switches off by default; routes under `/api/v1/learning/`; students addressed by user id; numeric query params via `api/params.py` `_int_param`.
- Migrations only create new tables.
- Locales `dashboard/src/locales/{en,ar}/reviews.json`, `honour.json`, no top-level wrapper, en + real ar parity. Date-only → `formatDay`.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`; explicit paths.
- Before pushing: gitleaks dir scan (in the controller's gate script).

## Review Focus

1. **A review of a session the caller doesn't own** (another student, another parent's child, a teacher) — 404 on read, 403/404 on write. Task 2, Task 4.
2. **Excused or absent attendance treated as attended** — only `present` is eligible. Task 2.
3. **The 30-day window edge** — day 30 allowed, day 31 refused, for PUT and DELETE; the office exempt. Task 2.
4. **A review left counted after the session stops being eligible** (attendance cleared / cancelled) — excluded from lists and hooks. Task 2.
5. **Unpublished honour entries seen by non-office** — never. Task 3, Task 4.

---

### Task 1: Models, switches, resources, migration

**Files:** `backend/etqan/learning/models.py` (+ `SessionReview`, `HonourEntry` exactly as spec §3: `SessionReview.session` OneToOne `scheduling.Session` CASCADE, rating CHECK 1..5, comment ≤ 2000, `written_by` SET_NULL; `HonourEntry.student` PROTECT, title ≤ 120, message ≤ 1000, emoji CharField(16, blank), `month` DateField with CHECK `EXTRACT(day) = 1` — implement as `models.CheckConstraint(condition=Q(month__day=1), name="learning_honour_month_first")`, `is_published` default False, `created_by`, timestamps, ordering `(-month, -id)`), migration `0003_reviews_honour` (generated), `platform/features.py` (under B6 marker: `Feature("session_reviews", "Session reviews", "تقييمات الحصص", "teaching", built=True)`, `Feature("honour_board", "Honour board", "لوحة الشرف", "people", built=True)`), `access/registry.py` (under B6 marker: `Resource("session_review", "Session reviews", "تقييمات الحصص", ("view_any", "view", "update", "delete"))`, `Resource("honour_entry", "Honour board", "لوحة الشرف", ("view_any", "create", "update", "delete"))`), `platform/tests/test_features.py` BUILT dict (B6 marker), `learning/tests/test_review_models.py`.

Tests: switches built/off; rating CHECK (0 and 6 refused); one review per session (IntegrityError); honour month CHECK (day 2 refused); deleting a session deletes its review.

- [ ] tests → RED → implement → `D manage makemigrations learning --name reviews_honour`, `just migrate` → GREEN (`D pytest etqan/learning etqan/platform -q`; access `in_use` fails until Task 4 — accepted) → ruff, lint-imports → commit `feat(learning): session review and honour entry models (B6c)`.

---

### Task 2: Review services

**Files:** create `services/reviews.py`, `tests/test_reviews.py`; modify `services/__init__.py` (+ `__all__`).

**Produces:**
- `ELIGIBLE = Q(session__status="completed", session__student_attendance="present", session__subscription__isnull=False) & ~Q(session__kind="trial")` — and a session-level equivalent `_eligible_sessions()` built on `scheduling.services.sessions_queryset().filter(status="completed", student_attendance="present", subscription__isnull=False).exclude(kind="trial")`.
- `WINDOW_DAYS = 30`
- `reviews_queryset(user, *, teacher=None, course=None, student=None, rating=None)` — eligible reviews only; office all; teacher: `session__teacher__user_id=user.pk`; student: `session__student__user_id=user.pk`; parent: `session__student__in=identity.get_children(user.pk)`; else none. `select_related("session__student__user", "session__teacher__user", "session__course", "written_by")`.
- `get_review(user, review_id)` (NotFoundError).
- `reviewable_sessions(user, *, student_user_id=None)` — eligible sessions with no review; student: self (a `student_user_id` other than self → NotFoundError); parent: `student_user_id` required and `is_parent_of` else NotFoundError; office: `student_user_id` required (400 `student` if missing); window applies to student/parent only (`occurs_on >= today - 30 days`); newest first.
- `write_review(*, session_id, rating, comment="", by) -> SessionReview` — session must exist and be eligible (400 `session`); caller must be office, the session's student, or a parent of that student (else NotFoundError → 404); rating 1..5 (400 `rating`); student/parent window: `today <= occurs_on + 30 days` else `ConflictError(code="learning.review_window_closed")`; create-or-replace atomically: lock existing row with `select_for_update`, update rating/comment/written_by; else create inside a savepoint, catching `IntegrityError` and retrying as an update.
- `delete_review(review, *, by)` — office any; student/parent own within the window (409 otherwise); teacher → ForbiddenError.
- `review_summary(*, teacher_user_id=None, student_user_id=None, since, until) -> ReviewSummary(count: int, average: float | None)` and `reviews_of(student_user_id, *, month) -> list[ReviewMonth(...)]` per spec R-5 (field order exactly as D32).
- `today` via `scheduling.services.today()`.

Tests (write first; each must fail if the rule is removed): eligibility (present ok; absent, excused, scheduled, cancelled, no subscription, kind "trial" via a `.update(kind="trial")` row → 400 `session`); writer rights (student own, parent of student, office any; other student / other parent / teacher → 404 or ForbiddenError as specified); replace keeps one row and sets `written_by`; a parent replacing a student's review; rating 0/6 → 400; window: `clock.set` so `today == occurs_on + 30` allowed, `+31` → 409, office exempt; delete rights and window; `reviews_queryset` per role (teacher sees only their sessions — after `Session.objects.filter(pk=…).update(teacher=…)` the old teacher no longer sees it); a review whose session's attendance is set back to `not_set`/status `scheduled` (via `.update`) disappears from `reviews_queryset`, `review_summary`, `reviews_of`; `reviewable_sessions` per role incl. window and parent/child check; `review_summary` average/None and the `[since, until)` bounds; `reviews_of` month bounds and field shape.

Fixtures: `etqan/learning/tests/conftest.py` (`world`, `subscribe`, `clock`); mark a session attended with `scheduling.services.mark_attendance(...)` (check its signature) or `.update(status="completed", student_attendance="present")` for setup.

- [ ] tests → RED → implement → GREEN (`D pytest etqan/learning -q`, reviews.py coverage ≥ 90 %) → ruff → commit `feat(learning): session review services (B6c)`.

---

### Task 3: Honour services

**Files:** `services/honour.py`, `tests/test_honour.py`, `services/__init__.py`.

**Produces:** `honour_queryset(user, *, month=None)` — office (`is_office`): all; teacher/student/parent: `is_published=True`; others none; `select_related("student__user")`. `create_entry(*, student_user_id, title, message="", emoji="", month, is_published=False, by)`; `update_entry(entry, **changes)` (keys: title, message, emoji, month, is_published, student_user_id; unknown keys 400); `delete_entry(entry)`; `get_entry(user, id)` (NotFoundError for unpublished to non-office). Rules: student must be a student (400 `student`, via `progress._student`); title stripped, required (400 `title`); `month` must have `day == 1` (400 `month`); emoji ≤ 16 (400 `emoji`).

Tests: CRUD; month rule; student rule; visibility per role (unpublished hidden from teacher/student/parent, shown to office); deactivated student's entry still listed.

- [ ] tests → RED → implement → GREEN → ruff → commit `feat(learning): honour board services (B6c)`.

---

### Task 4: API (reviews + honour) and route tables

**Files:** create `api/review_views.py`, `api/honour_views.py`, `tests/test_api_reviews.py`, `tests/test_api_honour.py`; modify `api/serializers.py`, `api/urls.py`, `access/tests/test_routes.py`.

Routes and permissions exactly as spec §5: `reviews/` (GET, `HasCode | (ReadOnly & ReadsOwn)`, `session_review.view_any`, paginated), `reviews/reviewable/` (GET, `HasCode | (ReadOnly & (IsStudent | IsParent))`, `session_review.update`, unpaginated list of session items `{id, occurs_on, course, teacher, student}`; place it before `reviews/<int:pk>/`), `reviews/<int:pk>/` (GET `session_review.view`; DELETE `HasCode | IsStudent | IsParent` with `session_review.delete`), `sessions/<int:session_id>/review/` (PUT, `HasCode | IsStudent | IsParent`, `session_review.update`, body `{rating, comment}`), `honour/` (GET `HasCode | (ReadOnly & ReadsOwn)` `honour_entry.view_any`; POST `HasCode` `honour_entry.create`), `honour/<int:pk>/` (PATCH `honour_entry.update`, DELETE `honour_entry.delete`, `HasCode`). Serializers cap comment 2000, title 120, message 1000, emoji 16; rating IntegerField 1..5. Item shapes per spec §5. `FeatureOn` last everywhere; features `session_reviews` / `honour_board`.

Route tables: add every coded (method, path) row to `ROUTES` with `N` ids; `FEATURES` blocks; `FEATURE_WORDS` `"/learning/reviews": "session_reviews"`, `"/review/": "session_reviews"`, `"/learning/honour": "honour_board"` — confirm `"/review/"` matches no existing route outside learning (grep), else use `"/learning/sessions/"`.

Tests: per-role matrix for every route (office with/without codes, teacher own vs other's session, student own vs other, parent child vs not child) — reads 404 outside scope, writes 403 for teachers/staff-without-code; PUT create then replace; window 409 through the API; reviewable for student (no param), parent (param required, 404 for not-child), office (param required → 400 without); honour visibility (unpublished hidden), office CRUD; switch off → 404 after the role check; `?teacher=²` ignored.

- [ ] tests → RED → implement → GREEN — the full access suite must pass now (`D pytest etqan/learning etqan/access etqan/platform -q`), then the whole backend once (`D pytest -q --no-cov`) → ruff, lint-imports → commit `feat(learning): reviews and honour board API (B6c)`.

---

### Task 5: Demo seed

**Files:** `backend/etqan/tenants/seeds/b6.py` (+ `seed_b6_reviews`, `seed_b6_honour`, each independently idempotent and called from `seed_b6`), `etqan/tenants/tests/test_seed_b6.py`.

Reviews: for the first eligible demo session of a demo student (if any), a 5-star review "Clear and patient." written by the student; skip when none. Honour: two entries for the current academy month (`scheduling.services.today().replace(day=1)`) — "⭐ Star of the month" for Yusuf (published) and "Proficient memoriser" for Zaid (unpublished); skip a missing student. Idempotent (skip when any entry exists for that month / any review exists).

- [ ] tests → RED → implement → GREEN → commit `feat(learning): demo reviews and honour entries (B6c)`.

---

### Task 6: Dashboard data layers and translations

**Files:** `src/features/reviews/{schemas,api,queries,fixtures,errors,index}.ts` + `api.test.ts`; `src/features/honour/{schemas,api,queries,fixtures,index}.ts` + `api.test.ts`; `src/locales/{en,ar}/reviews.json`, `honour.json`; `src/features/identity/schemas.ts` FeatureCode `// Phase B6, slice B6c.` (`"session_reviews"`, `"honour_board"`).

Follow `src/features/homework/` exactly (wrapped mutations via `useInvalidating`, `clean()` params, `reviewsErrorText` mapping `learning.review_window_closed` → `reviews.errors.review_window_closed`, `formErrors`). API: `reviewsApi.list(params)`, `get(id)`, `reviewable(student?)`, `write(sessionId, {rating, comment})` (PUT JSON), `remove(id)`; `honourApi.list({month?})`, `create(body)`, `update(id, body)`, `remove(id)` (JSON). Locale keys for every label, column, filter, toast, empty state, error, the star labels ("1 star" … "5 stars"), honour fields.

- [ ] tests → RED → implement → GREEN (`D dash pnpm vitest run src/features/reviews src/features/honour src/locales`, tsc, lint) → commit `feat(reviews,honour): data layers and translations (B6c)`.

---

### Task 7: Dashboard review screens

**Files:** `src/features/reviews/StarRating.tsx` (accessible radio group of 5, `role="radiogroup"`, labelled stars, keyboard arrows; read-only variant), `ReviewsList.tsx` (office: filters teacher/course/rating, paging, open → `ReviewDialog` edit/delete; "Add review" → student picker (`usePeople("students")`) → `reviewable(student)` session select → stars + comment), `MyReviews.tsx` (teacher: read-only list + average), `RateLessons.tsx` (student/parent: parent child picker from `useMe().children`; "To review" list with inline StarRating + comment + Submit; "My reviews" list with edit/delete; 409 window message via `reviewsErrorText`), tests for each; routes `scheduling.reviews.tsx` (`{permission: "session_review.view_any", feature: "session_reviews"}`), `teaching.reviews.tsx`, `learning.reviews.tsx` (`{feature: "session_reviews"}`); nav under `// ── phase B6 ──` (office scheduling group; teacher; student/parent); extend `routes/permissions.test.ts`, `features/shell/nav.test.ts` (and any shell test a new label's text matcher collides with, minimally).

- [ ] tests → RED → implement → GREEN → commit `feat(reviews): session review screens (B6c)`.

---

### Task 8: Dashboard honour screens

**Files:** `src/features/honour/HonourAdmin.tsx` (office, People group `/people/honour` `{permission: "honour_entry.view_any", feature: "honour_board"}`: month filter (default this month, `<input type="month">`), entries list with published toggle (`honour_entry.update`), add/edit dialog (student picker, title, emoji, message, month, published), delete), `HonourBoard.tsx` (published entries grouped by month newest first, emoji + title + student name + message; month labels via `Intl` month-year in the reader's language), tests; routes `people.honour.tsx`, `teaching.honour.tsx`, `learning.honour.tsx` (`{feature: "honour_board"}`); nav under B6 marker; test lists extended.

- [ ] tests → RED → implement → GREEN → whole dashboard suite with coverage (`D dash pnpm test:coverage`) meets thresholds → commit `feat(honour): honour board screens (B6c)`.

---

### Task 9: e2e — `dashboard/e2e/b6-reviews.spec.ts`

Follow `e2e/b6-homework.spec.ts` (visit() 2 attempts + annotations, sign-in helpers, CSRF API helper, stamped names). Journey: switches `session_reviews`, `honour_board` on; admin API set-up of a stamped student with a live Quran Memorisation subscription with Ustadha Maryam and one session marked completed + present (find the session via the sessions API and mark attendance via the scheduling attendance endpoint — read the e2e for B2 attendance or the API); the student rates it 4 stars with a comment on `/app/learning/reviews`; the admin sees it on `/app/scheduling/reviews`; Maryam sees it on `/app/teaching/reviews`; the admin adds and publishes an honour entry for the student on `/app/people/honour`; the student sees it on `/app/learning/honour`.

- [ ] write → `just e2e e2e/b6-reviews.spec.ts` passes twice → whole `just e2e` → commit `test(e2e): B6c reviews and honour board journey`.

---

### Task 10: Slice verification

- [ ] Fresh-stack gates (controller's gate script: stream-down, up, migrate, seed, test, lint, dashboard coverage, e2e, gitleaks) all green; R-1…R-10 and §6 traced to code + tests; phase notes updated.
