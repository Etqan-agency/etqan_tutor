# Plan 32 — B6a Curriculum Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Levels → sub-levels → topics per course, Qur'an chapters, each student's level and completed topics per course, and level upgrade requests — a new tenant app `etqan.learning` with its API and dashboard screens, behind the switches `levels` and `quran_chapters` (off by default).

**Architecture:** One new Django tenant app `etqan.learning` (models, a `services/` package, `api/`), reading other apps only through `identity.services`, `catalogue.services` and `scheduling.services`. The dashboard gets a new feature folder `src/features/curriculum/` with office pages under `/catalogue/*` and `/scheduling/*`, a teacher page under `/teaching/levels` and a student/parent page under `/learning/progress`.

**Tech Stack:** Django 5 + DRF + django-tenants + pytest (backend); React + TanStack Router/Query + react-hook-form + Vitest + Testing Library (dashboard); Playwright (e2e).

**Spec:** `docs/superpowers/specs/2026-10-05-b6-learning-design.md` (§2 phase decisions, §5–§11 slice B6a). Read it before any task; decision ids (C-n, B6-n) below refer to it.

**Requires:** — (no other phase's slice; B6a reads only merged B0/B1 code).

## Global Constraints

- Every command runs from the worktree `/home/abdulkhalek/Projects/etqan_tutor-wt/b6`, against this stream's stack (its `.env.stream`; the stack is up via `just dev-backend`). Never run `git submodule update` or any writing `git submodule` command. Never run `manage.py`, `migrate` or e2e any other way than below.
- **How to run things** (wherever a step says `uv run pytest …`, `just manage …`, `pnpm vitest …`, use these; `D=/home/abdulkhalek/.claude/jobs/0bc5cdff/tmp/dc`, a wrapper that loads `.env.stream` and calls `docker compose` on this stack):
  - backend tests: `$D pytest <paths> -q` (paths relative to `backend/`; add `--cov=etqan.learning --cov-report=term-missing` for coverage)
  - backend lint: `$D django sh -euc 'ruff check . && ruff format --check .'`; boundaries: `$D django lint-imports`; format: `$D django ruff format <paths>`
  - migrations: `$D manage makemigrations learning`, then `just migrate`
  - dashboard: `$D dash pnpm vitest run <paths>`; `$D dash pnpm tsc --noEmit`; `$D dash pnpm lint`
  - whole suites: `just test`, `just lint`, `just e2e [spec]`, `just seed`
- Backend coverage ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- Business logic only in `etqan/learning/services/`; views are thin. `etqan.learning` imports only `etqan.platform`, `etqan.identity.services`, `etqan.catalogue.services`, `etqan.scheduling.services` (tests may import other apps' models).
- Shared lists: add lines only under the `── phase B6 ──` markers (settings `TENANT_APPS`, `config/api_router.py`, `etqan/platform/features.py`, `etqan/access/registry.py` `RESOURCES`, `seed_academy` in `seed_dev.py`, `backend/pyproject.toml`, dashboard `NAV_ITEMS`). The only in-place edit allowed outside markers is flipping the registry's `_later("levels", …)` line.
- Both switches are **off by default**. All API routes live under `/api/v1/learning/`.
- Students are addressed by **user id** in every API path and body.
- No migration touches an existing table. Migrations are generated with `makemigrations learning` through the stream stack (`just` recipe / `docker compose … run django`), never `--merge`.
- Translations: new files `dashboard/src/locales/en/curriculum.json` and `dashboard/src/locales/ar/curriculum.json` only (en + ar, key-for-key equal). Error codes `learning.*` are translated there under `curriculum.errors.*`.
- Commit after each task in the repo(s) it touched (`backend/`, `dashboard/` are their own git worktrees on branch `feat/b6a-learning`). Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **A teacher of course A reading course B of the same student** — every progress read (summary, detail, list, upgrades) must leave course B out (summary) or 404 (detail). Pinned in Task 7 `test_teacher_sees_only_taught_course`.
2. **Deleting history through a cascade** — removing a sub-level or level whose topics a student completed must answer 409, never 500 (`ProtectedError`). Pinned in Task 3 `test_dropping_sub_level_with_completed_topic_conflicts` and `test_delete_level_with_only_a_completion_conflicts`.
3. **Two current levels after a race or a repeated click** — `set_level` twice with the same level is a no-op; the partial unique constraint holds. Pinned in Task 4 `test_set_same_level_is_noop` and Task 1 `test_one_current_level_per_course`.
4. **Approving a stale request** — current level moved or `to_level` deactivated since the request: 409, request stays pending. Pinned in Task 5.
5. **A student with no level is invisible** — the Student levels list must show live (student, course) pairs with no level so a first level can be set. Pinned in Task 4 `test_level_rows_include_pairs_without_level` and in the e2e.

---

## File Structure

```text
backend/etqan/learning/
  __init__.py
  apps.py                      LearningConfig
  models.py                    Level, SubLevel, Topic, QuranChapter, StudentLevel, TopicCompletion, LevelUpgradeRequest
  migrations/0001_initial.py   generated
  data/quran_chapters.json     114 chapters (generated once, committed)
  services/__init__.py         public API (re-exports)
  services/access.py           teaches, taught_pairs, live_pairs, office_reads, progress_scope
  services/curriculum.py       levels_queryset, get_level, create_level, update_level, delete_level, reorder_levels
  services/quran.py            chapters, sync_chapters, update_chapter, SyncResult
  services/progress.py         level_rows, progress, progress_summary, set_level, complete_topic, uncomplete_topic, progress_of
  services/upgrades.py         request_upgrade, approve_request, reject_request, requests_queryset
  api/__init__.py
  api/serializers.py
  api/views.py
  api/urls.py
  tests/__init__.py
  tests/conftest.py            world fixtures (course, levels, students, teachers, subscriptions)
  tests/test_models.py
  tests/test_quran.py
  tests/test_curriculum.py
  tests/test_progress.py
  tests/test_upgrades.py
  tests/test_api_levels.py
  tests/test_api_progress.py
backend/scripts/fetch_quran_chapters.py
backend/etqan/tenants/seeds/b6.py
backend/etqan/tenants/tests/test_seed_b6.py
Modified: backend/config/settings/base.py, backend/config/api_router.py, backend/etqan/platform/features.py,
  backend/etqan/access/registry.py, backend/etqan/access/tests/test_routes.py, backend/pyproject.toml,
  backend/etqan/tenants/management/commands/seed_dev.py

dashboard/src/features/curriculum/
  schemas.ts  api.ts  queries.ts  fixtures.ts  errors.ts  index.ts
  LevelsList.tsx  LevelDialog.tsx  ChaptersTable.tsx
  StudentLevelsList.tsx  ProgressPanel.tsx  UpgradesList.tsx
  MyProgress.tsx  StudentLevelCard.tsx
  *.test.tsx next to each component, api.test.ts
dashboard/src/routes/_authed/catalogue.levels.tsx, catalogue.quran.tsx,
  scheduling.student-levels.tsx, scheduling.level-upgrades.tsx, teaching.levels.tsx, learning.progress.tsx
dashboard/src/locales/{en,ar}/curriculum.json
dashboard/e2e/b6-curriculum.spec.ts
Modified: dashboard/src/features/identity/schemas.ts (FeatureCode), dashboard/src/features/shell/nav.ts (NAV_ITEMS),
  dashboard/src/routeTree.gen.ts (regenerated)
```

---

### Task 1: The `etqan.learning` app, models and wiring

**Files:**
- Create: `backend/etqan/learning/__init__.py`, `apps.py`, `models.py`, `migrations/__init__.py`, `migrations/0001_initial.py` (generated), `services/__init__.py` (empty docstring for now), `tests/__init__.py`, `tests/conftest.py`, `tests/test_models.py`
- Modify: `backend/config/settings/base.py` (TENANT_APPS, B6 marker ≈ line 93), `backend/etqan/platform/features.py` (flip `levels`, add `quran_chapters` under B6 marker), `backend/etqan/access/registry.py` (RESOURCES, B6 marker ≈ line 124), `backend/pyproject.toml` (platform forbidden list B6 marker ≈ line 83; a learning contract under the per-app B6 marker ≈ line 345)

**Interfaces:**
- Produces: models `Level`, `SubLevel`, `Topic`, `QuranChapter`, `StudentLevel`, `TopicCompletion`, `LevelUpgradeRequest` (fields exactly as below); feature codes `levels`, `quran_chapters` (built, off); resources `level`, `quran_chapter`, `student_level`, `level_upgrade_request` with `in_use` exactly as below; test fixtures in `tests/conftest.py` (`world`, `make_level`, `subscribe`, `teacher_client`, `student_client`, `parent_client`) used by every later backend task.

- [ ] **Step 1: Write the failing model tests** — `backend/etqan/learning/tests/test_models.py`

```python
from datetime import date

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.learning.models import LevelUpgradeRequest
from etqan.learning.models import StudentLevel
from etqan.learning.models import Topic
from etqan.learning.models import TopicCompletion
from etqan.platform import features


def test_switches_are_built_and_off():
    assert features.get("levels").built is True
    assert features.get("levels").default is False
    assert features.get("quran_chapters").built is True
    assert features.get("quran_chapters").default is False


def test_one_current_level_per_course(world, make_level):
    level = make_level(world.course)
    student = world.student_profile
    StudentLevel.objects.create(
        student=student, course=world.course, level=level, started_on=date(2026, 6, 1)
    )
    with pytest.raises(IntegrityError), transaction.atomic():
        StudentLevel.objects.create(
            student=student, course=world.course, level=level, started_on=date(2026, 6, 2)
        )


def test_ended_levels_do_not_count_as_current(world, make_level):
    level = make_level(world.course)
    student = world.student_profile
    StudentLevel.objects.create(
        student=student,
        course=world.course,
        level=level,
        started_on=date(2026, 5, 1),
        ended_on=date(2026, 6, 1),
    )
    StudentLevel.objects.create(
        student=student, course=world.course, level=level, started_on=date(2026, 6, 1)
    )
    assert StudentLevel.objects.filter(ended_on__isnull=True).count() == 1


def test_topic_completion_is_unique(world, make_level):
    topic = Topic.objects.filter(sub_level__level=make_level(world.course)).first()
    TopicCompletion.objects.create(
        student=world.student_profile, topic=topic, completed_on=date(2026, 6, 1)
    )
    with pytest.raises(IntegrityError), transaction.atomic():
        TopicCompletion.objects.create(
            student=world.student_profile, topic=topic, completed_on=date(2026, 6, 2)
        )


def test_verses_need_a_chapter(world, make_level):
    sub = make_level(world.course).sub_levels.first()
    with pytest.raises(IntegrityError), transaction.atomic():
        Topic.objects.create(
            sub_level=sub, name_ar="x", name_en="x", position=9, from_verse=1, to_verse=2
        )


def test_one_pending_request_per_student_and_course(world, make_level):
    low = make_level(world.course, name_en="L1")
    high = make_level(world.course, name_en="L2")
    fields = {
        "student": world.student_profile,
        "course": world.course,
        "from_level": low,
        "to_level": high,
    }
    LevelUpgradeRequest.objects.create(**fields)
    with pytest.raises(IntegrityError), transaction.atomic():
        LevelUpgradeRequest.objects.create(**fields)
    LevelUpgradeRequest.objects.create(**fields | {"status": "rejected"})
```

- [ ] **Step 2: Write the shared fixtures** — `backend/etqan/learning/tests/conftest.py`

```python
"""Learning fixtures. Time is pinned through scheduling's clock (Monday
1 June 2026, academy timezone UTC), reused from its conftest helpers."""

from datetime import date
from types import SimpleNamespace

import pytest
from rest_framework.test import APIClient

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.identity.models import StudentProfile
from etqan.learning.models import Level
from etqan.learning.models import SubLevel
from etqan.learning.models import Topic
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import Clock


@pytest.fixture
def clock(monkeypatch):
    return Clock(monkeypatch)


def as_user(user):
    client = APIClient()
    client.force_login(user)
    client.user = user
    return client


def _package():
    return catalogue_services.create_package(
        name_ar="شهري",
        name_en="Monthly",
        sessions_per_week=2,
        session_minutes=45,
        duration_value=1,
        duration_unit="month",
        freeze_days_allowed=0,
        price_minor=100000,
        currency="EGP",
    )


@pytest.fixture
def world(clock, set_features):
    """Two courses (`course`, `course_b`), both listing `teacher` and
    `other_teacher`; `student` (child of `parent`) and `other_student`. No
    subscription yet: tests call `subscribe`."""
    set_features(levels=True, quran_chapters=True)
    teacher = identity_services.create_person(
        "teacher", full_name="Bilal", profile={"gender": "male"}
    )
    other_teacher = identity_services.create_person(
        "teacher", full_name="Hamza", profile={"gender": "male"}
    )
    course = catalogue_services.create_course(
        name_ar="تحفيظ", name_en="Quran", teacher_ids=[teacher.id, other_teacher.id]
    )
    course_b = catalogue_services.create_course(
        name_ar="تجويد", name_en="Tajweed", teacher_ids=[teacher.id, other_teacher.id]
    )
    student = identity_services.create_person("student", full_name="Yusuf")
    other_student = identity_services.create_person("student", full_name="Zaid")
    parent = identity_services.create_person(
        "parent", full_name="Omar", email="omar@x.test"
    )
    identity_services.update_person(parent, {"children": [student.id]})
    return SimpleNamespace(
        teacher=teacher,
        other_teacher=other_teacher,
        course=course,
        course_b=course_b,
        student=student,
        student_profile=StudentProfile.objects.get(user=student),
        other_student=other_student,
        parent=parent,
        package=_package(),
    )


@pytest.fixture
def subscribe(world):
    """`subscribe(student=…, course=…, teacher=…)` → an active subscription."""

    def make(student=None, course=None, teacher=None, starts_on=date(2026, 6, 1)):
        return scheduling_services.create_subscription(
            student_id=(student or world.student).id,
            course_id=(course or world.course).id,
            teacher_id=(teacher or world.teacher).id,
            package_id=world.package.id,
            starts_on=starts_on,
        )

    return make


@pytest.fixture
def make_level():
    """`make_level(course, name_en=…, topics=2, is_active=True)` → a level with
    one sub-level holding `topics` topics, appended at the course's end."""

    def make(course, name_en="Level", topics=2, is_active=True):
        position = Level.objects.filter(course=course).count()
        level = Level.objects.create(
            course=course,
            name_ar=name_en,
            name_en=name_en,
            position=position,
            is_active=is_active,
        )
        sub = SubLevel.objects.create(level=level, name_ar="s", name_en="Sub", position=0)
        for i in range(topics):
            Topic.objects.create(
                sub_level=sub, name_ar=f"t{i}", name_en=f"Topic {i}", position=i
            )
        return level

    return make


@pytest.fixture
def teacher_client(world):
    return as_user(world.teacher)


@pytest.fixture
def student_client(world):
    return as_user(world.student)


@pytest.fixture
def parent_client(world):
    return as_user(world.parent)
```

> If `identity_services.update_person(parent, {"children": …})` is not how a parent's children are set, look at `etqan/identity/tests` for the helper the families/parents tests use (search `children` in `identity/services.py` `_apply_profile`) and use that; keep the fixture's shape.

- [ ] **Step 3: Run to verify failure**

Run: `cd backend && uv run pytest etqan/learning -q`
Expected: collection error `No module named 'etqan.learning'`.

- [ ] **Step 4: Create the app** — `apps.py`

```python
from django.apps import AppConfig


class LearningConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.learning"
```

`backend/etqan/learning/__init__.py`, `migrations/__init__.py`, `tests/__init__.py`: empty. `services/__init__.py`:

```python
"""Public API of the learning module (phase B6). Other apps import only this package."""
```

- [ ] **Step 5: Write the models** — `backend/etqan/learning/models.py`

```python
"""Phase B6, slice B6a (spec 2026-10-05 §7): the curriculum ladder, the
Qur'an chapters and each student's place on the ladder. Other apps' models
are referenced by string only (B6-1)."""

from django.conf import settings
from django.db import models
from django.db.models import Q


class QuranChapter(models.Model):
    class Place(models.TextChoices):
        MAKKAH = "makkah", "Makkah"
        MADINAH = "madinah", "Madinah"

    number = models.PositiveSmallIntegerField(unique=True)
    name_arabic = models.CharField(max_length=60)
    name_simple = models.CharField(max_length=60)
    name_complex = models.CharField(max_length=60)
    revelation_place = models.CharField(max_length=7, choices=Place.choices)
    revelation_order = models.PositiveSmallIntegerField()
    verses_count = models.PositiveSmallIntegerField()
    page_start = models.PositiveSmallIntegerField()
    page_end = models.PositiveSmallIntegerField()

    class Meta:
        ordering = ("number",)

    def __str__(self):
        return f"{self.number}. {self.name_simple}"


class Level(models.Model):
    # CASCADE: a course without learning history stays deletable (§7); the
    # history below is PROTECT and blocks it.
    course = models.ForeignKey(
        "catalogue.Course", on_delete=models.CASCADE, related_name="+"
    )
    name_ar = models.CharField(max_length=120)
    name_en = models.CharField(max_length=120)
    position = models.PositiveSmallIntegerField(default=0)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("course_id", "position", "id")

    def __str__(self):
        return self.name_en


class SubLevel(models.Model):
    level = models.ForeignKey(Level, on_delete=models.CASCADE, related_name="sub_levels")
    name_ar = models.CharField(max_length=120)
    name_en = models.CharField(max_length=120)
    position = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ("position", "id")

    def __str__(self):
        return self.name_en


class Topic(models.Model):
    sub_level = models.ForeignKey(
        SubLevel, on_delete=models.CASCADE, related_name="topics"
    )
    name_ar = models.CharField(max_length=200)
    name_en = models.CharField(max_length=200)
    position = models.PositiveSmallIntegerField(default=0)
    chapter = models.ForeignKey(
        QuranChapter,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    from_verse = models.PositiveSmallIntegerField(null=True, blank=True)
    to_verse = models.PositiveSmallIntegerField(null=True, blank=True)

    class Meta:
        ordering = ("position", "id")
        constraints = [
            models.CheckConstraint(
                condition=Q(from_verse__isnull=True, to_verse__isnull=True)
                | Q(
                    chapter__isnull=False,
                    from_verse__isnull=False,
                    to_verse__isnull=False,
                    from_verse__lte=models.F("to_verse"),
                ),
                name="learning_topic_verses",
            )
        ]

    def __str__(self):
        return self.name_en


class StudentLevel(models.Model):
    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    course = models.ForeignKey(
        "catalogue.Course", on_delete=models.PROTECT, related_name="+"
    )
    level = models.ForeignKey(
        Level, on_delete=models.PROTECT, related_name="student_levels"
    )
    started_on = models.DateField()
    ended_on = models.DateField(null=True, blank=True)
    set_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-started_on", "-id")
        constraints = [
            models.UniqueConstraint(
                fields=("student", "course"),
                condition=Q(ended_on__isnull=True),
                name="learning_one_current_level",
            )
        ]


class TopicCompletion(models.Model):
    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    topic = models.ForeignKey(
        Topic, on_delete=models.PROTECT, related_name="completions"
    )
    completed_on = models.DateField()
    recorded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=("student", "topic"), name="learning_topic_once"
            )
        ]


class LevelUpgradeRequest(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        APPROVED = "approved", "Approved"
        REJECTED = "rejected", "Rejected"

    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    course = models.ForeignKey(
        "catalogue.Course", on_delete=models.PROTECT, related_name="+"
    )
    subscription = models.ForeignKey(
        "scheduling.Subscription",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    from_level = models.ForeignKey(Level, on_delete=models.PROTECT, related_name="+")
    to_level = models.ForeignKey(Level, on_delete=models.PROTECT, related_name="+")
    note = models.TextField(blank=True, default="", max_length=2000)
    status = models.CharField(
        max_length=8, choices=Status.choices, default=Status.PENDING
    )
    rejection_reason = models.TextField(blank=True, default="", max_length=2000)
    requested_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    decided_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at", "-id")
        constraints = [
            models.UniqueConstraint(
                fields=("student", "course"),
                condition=Q(status="pending"),
                name="learning_one_pending_request",
            )
        ]
```

> `CheckConstraint(condition=…)` is Django ≥ 5.1; if the installed Django is older, use `check=`. Check `backend/requirements/base.txt`.

- [ ] **Step 6: Wire the app**

`backend/config/settings/base.py`, under `# ── phase B6 ──` in `TENANT_APPS`:

```python
    "etqan.learning",
```

`backend/etqan/platform/features.py`: replace `_later("levels", "Levels", "نظام المستويات", "teaching"),` in place with

```python
    # Phase B6, slice B6a: built, off by default.
    Feature("levels", "Levels", "نظام المستويات", "teaching", built=True),
```

and under `# ── phase B6 ──`:

```python
    Feature(
        "quran_chapters",
        "Qur'an chapters",
        "سور القرآن الكريم",
        "teaching",
        built=True,
    ),
```

`backend/etqan/access/registry.py`, under `# ── phase B6 ──` in `RESOURCES`:

```python
    Resource(
        "level",
        "Levels",
        "المستويات",
        ("view", "view_any", "create", "update", "delete", "reorder"),
    ),
    Resource("quran_chapter", "Qur'an chapters", "سور القرآن", ("view_any", "create", "update")),
    Resource("student_level", "Student levels", "مستويات الطلاب", ("view", "view_any", "update")),
    Resource(
        "level_upgrade_request",
        "Level upgrade requests",
        "طلبات رفع المستوى",
        ("view_any", "create", "update"),
    ),
```

> Until Tasks 6–7 add the routes, `access/tests/test_routes.py::test_every_code_in_the_table_is_in_the_registry_and_in_use` fails (registry codes in use but no route). That is expected between Task 1 and Task 7; Task 7 Step "full suite" must show it green. Do not weaken the test.

`backend/pyproject.toml`: add `"etqan.learning",` under the B6 marker of the platform contract's `forbidden_modules` list (≈ line 83), and under the per-app `# ── phase B6 ──` marker (≈ line 345):

```toml
[[tool.importlinter.contracts]]
name = "learning reaches other apps only through their services"
type = "forbidden"
source_modules = ["etqan.learning"]
forbidden_modules = [
    "etqan.identity.models", "etqan.identity.api",
    "etqan.catalogue.models", "etqan.catalogue.api",
    "etqan.scheduling.models", "etqan.scheduling.api",
    "etqan.tenants", "etqan.site", "etqan.academy", "etqan.billing", "etqan.payroll",
    "etqan.finance", "etqan.gateways", "etqan.notifications", "etqan.access",
    "etqan.library", "etqan.employment", "etqan.systemstatus",
]
allow_indirect_imports = true
ignore_imports = [
    "etqan.learning.tests.* -> etqan.identity.models",
    "etqan.learning.tests.* -> etqan.catalogue.models",
    "etqan.learning.tests.* -> etqan.scheduling.models",
    "etqan.learning.tests.* -> etqan.scheduling.tests.conftest",
]
```

> `etqan.scheduling.tests.conftest` imports scheduling models; if lint-imports still flags the indirect import, add `"etqan.learning.tests.* -> etqan.scheduling.tests.*"` too. Run `cd backend && uv run lint-imports` to confirm.

- [ ] **Step 7: Generate the migration**

Run (through the stream stack): `just manage makemigrations learning` (or the repo's equivalent recipe that runs `manage.py` in the stream's django container; check `justfile`).
Expected: `etqan/learning/migrations/0001_initial.py` creating the seven tables and three constraints. Then `just migrate`.

- [ ] **Step 8: Run tests**

Run: `cd backend && uv run pytest etqan/learning etqan/platform -q`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git -C backend add etqan/learning config/settings/base.py etqan/platform/features.py etqan/access/registry.py pyproject.toml
git -C backend commit -m "feat(learning): app, curriculum models and switches (B6a)"
```

---

### Task 2: Qur'an chapters — data file and services

**Files:**
- Create: `backend/scripts/fetch_quran_chapters.py`, `backend/etqan/learning/data/quran_chapters.json`, `backend/etqan/learning/services/quran.py`, `backend/etqan/learning/tests/test_quran.py`
- Modify: `backend/etqan/learning/services/__init__.py`

**Interfaces:**
- Produces: `SyncResult(created: int, reset: int)` (frozen dataclass); `chapters() -> QuerySet[QuranChapter]`; `sync_chapters() -> SyncResult`; `update_chapter(chapter, *, name_arabic, name_simple, name_complex) -> QuranChapter`; `DATA_FILE: Path`.

- [ ] **Step 1: Write the fetch script** — `backend/scripts/fetch_quran_chapters.py` (one-off, not run in CI)

```python
"""Regenerate etqan/learning/data/quran_chapters.json from the public
Quran.com API v4 (spec B6a C-3). Run by hand: `uv run python scripts/fetch_quran_chapters.py`."""

import json
from pathlib import Path

import httpx

OUT = Path(__file__).resolve().parent.parent / "etqan/learning/data/quran_chapters.json"


def main() -> None:
    data = httpx.get("https://api.quran.com/api/v4/chapters", timeout=30).json()
    rows = [
        {
            "number": c["id"],
            "name_arabic": c["name_arabic"],
            "name_simple": c["name_simple"],
            "name_complex": c["name_complex"],
            "revelation_place": c["revelation_place"],
            "revelation_order": c["revelation_order"],
            "verses_count": c["verses_count"],
            "page_start": c["pages"][0],
            "page_end": c["pages"][1],
        }
        for c in data["chapters"]
    ]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(rows, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
```

Run it once: `cd backend && uv run python scripts/fetch_quran_chapters.py`; commit the JSON. (Ruff may want `# noqa: T201`-free code; it prints nothing.)

- [ ] **Step 2: Write the failing tests** — `backend/etqan/learning/tests/test_quran.py`

```python
import json

from etqan.learning import services
from etqan.learning.models import QuranChapter


def test_data_file_is_the_whole_quran():
    rows = json.loads(services.DATA_FILE.read_text(encoding="utf-8"))
    assert [r["number"] for r in rows] == list(range(1, 115))
    assert sum(r["verses_count"] for r in rows) == 6236
    assert all(1 <= r["page_start"] <= r["page_end"] <= 604 for r in rows)
    assert {r["revelation_place"] for r in rows} == {"makkah", "madinah"}


def test_sync_creates_then_resets():
    assert services.sync_chapters() == services.SyncResult(created=114, reset=0)
    fatiha = QuranChapter.objects.get(number=1)
    services.update_chapter(
        fatiha, name_arabic="x", name_simple="y", name_complex="z"
    )
    assert services.sync_chapters() == services.SyncResult(created=0, reset=114)
    fatiha.refresh_from_db()
    assert fatiha.name_simple == "Al-Fatihah"
    assert services.chapters().count() == 114


def test_update_changes_names_only():
    services.sync_chapters()
    baqarah = QuranChapter.objects.get(number=2)
    services.update_chapter(
        baqarah, name_arabic="البقرة", name_simple="Baqara", name_complex="Baqara"
    )
    baqarah.refresh_from_db()
    assert (baqarah.name_simple, baqarah.verses_count) == ("Baqara", 286)
```

- [ ] **Step 3: Run to verify failure** — `uv run pytest etqan/learning/tests/test_quran.py -q` → FAIL (`services` has no `DATA_FILE`).

- [ ] **Step 4: Implement** — `backend/etqan/learning/services/quran.py`

```python
"""Spec B6a C-3, §8.2: the Qur'an chapters, loaded from the bundled file."""

import json
from dataclasses import dataclass
from pathlib import Path

from django.db import transaction

from etqan.learning.models import QuranChapter

DATA_FILE = Path(__file__).resolve().parent.parent / "data" / "quran_chapters.json"
FIELDS = (
    "name_arabic",
    "name_simple",
    "name_complex",
    "revelation_place",
    "revelation_order",
    "verses_count",
    "page_start",
    "page_end",
)


@dataclass(frozen=True)
class SyncResult:
    created: int
    reset: int


def chapters():
    return QuranChapter.objects.all()


@transaction.atomic
def sync_chapters() -> SyncResult:
    rows = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    existing = {c.number: c for c in QuranChapter.objects.select_for_update()}
    created, reset = [], []
    for row in rows:
        chapter = existing.get(row["number"]) or QuranChapter(number=row["number"])
        for field in FIELDS:
            setattr(chapter, field, row[field])
        (reset if chapter.pk else created).append(chapter)
    QuranChapter.objects.bulk_create(created)
    QuranChapter.objects.bulk_update(reset, FIELDS)
    return SyncResult(created=len(created), reset=len(reset))


def update_chapter(chapter, *, name_arabic: str, name_simple: str, name_complex: str):
    chapter.name_arabic = name_arabic
    chapter.name_simple = name_simple
    chapter.name_complex = name_complex
    chapter.save(update_fields=["name_arabic", "name_simple", "name_complex"])
    return chapter
```

`services/__init__.py` gains:

```python
from etqan.learning.services.quran import DATA_FILE
from etqan.learning.services.quran import SyncResult
from etqan.learning.services.quran import chapters
from etqan.learning.services.quran import sync_chapters
from etqan.learning.services.quran import update_chapter
```

- [ ] **Step 5: Run** — PASS. **Step 6: Commit** — `git -C backend add scripts/fetch_quran_chapters.py etqan/learning && git -C backend commit -m "feat(learning): Qur'an chapters data and sync (B6a)"`.

---

### Task 3: Curriculum services (levels with sub-levels and topics)

**Files:**
- Create: `backend/etqan/learning/services/curriculum.py`, `backend/etqan/learning/tests/test_curriculum.py`
- Modify: `backend/etqan/learning/services/__init__.py`

**Interfaces:**
- Consumes: models (Task 1); `chapters()` (Task 2).
- Produces:
  - `levels_queryset() -> QuerySet[Level]` annotated `sub_level_count`, `topic_count`, `select_related("course")`, prefetching `sub_levels__topics__chapter`.
  - `get_level(level_id: int) -> Level` (raises `NotFoundError("Level", id)`).
  - `create_level(*, course_id: int, name_ar: str, name_en: str, is_active: bool = True, sub_levels: list[dict]) -> Level`
  - `update_level(level, *, name_ar, name_en, is_active, sub_levels: list[dict], course_id: int | None = None) -> Level`
  - `delete_level(level) -> None`
  - `reorder_levels(*, course_id: int, ids: list[int]) -> None`
  - sub_levels item: `{"id"?: int, "name_ar": str, "name_en": str, "topics": [{"id"?: int, "name_ar", "name_en", "chapter"?: int | None, "from_verse"?: int | None, "to_verse"?: int | None}]}` (`chapter` is a `QuranChapter` id).
  - Limits `MAX_SUB_LEVELS = 50`, `MAX_TOPICS = 200`.

- [ ] **Step 1: Write the failing tests** — `backend/etqan/learning/tests/test_curriculum.py`

```python
from datetime import date

import pytest

from etqan.catalogue import services as catalogue_services
from etqan.learning import services
from etqan.learning.models import Level
from etqan.learning.models import QuranChapter
from etqan.learning.models import StudentLevel
from etqan.learning.models import Topic
from etqan.learning.models import TopicCompletion
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError


def _tree(*subs):
    return [
        {"name_ar": s, "name_en": s, "topics": [{"name_ar": t, "name_en": t} for t in ts]}
        for s, ts in subs
    ]


def _create(world, name="L1", subs=(("S1", ("T1", "T2")),)):
    return services.create_level(
        course_id=world.course.id, name_ar=name, name_en=name, sub_levels=_tree(*subs)
    )


def _payload(level):
    """The level's current tree as an update body (ids kept)."""
    return [
        {
            "id": s.id,
            "name_ar": s.name_ar,
            "name_en": s.name_en,
            "topics": [
                {"id": t.id, "name_ar": t.name_ar, "name_en": t.name_en}
                for t in s.topics.all()
            ],
        }
        for s in level.sub_levels.all()
    ]


def test_create_appends_and_orders(world):
    first = _create(world, "L1")
    second = _create(world, "L2", (("A", ("x",)), ("B", ("y", "z"))))
    assert (first.position, second.position) == (0, 1)
    subs = list(second.sub_levels.all())
    assert [s.name_en for s in subs] == ["A", "B"]
    assert [t.name_en for t in subs[1].topics.all()] == ["y", "z"]
    row = services.levels_queryset().get(pk=second.pk)
    assert (row.sub_level_count, row.topic_count) == (2, 3)


def test_create_needs_a_known_course(world):
    with pytest.raises(ValidationError) as err:
        services.create_level(course_id=999999, name_ar="x", name_en="x", sub_levels=[])
    assert err.value.field == "course"


def test_update_keeps_renames_moves_and_deletes(world):
    level = _create(world, subs=(("S1", ("T1", "T2")), ("S2", ("T3",))))
    body = _payload(level)
    moved = body[0]["topics"].pop(1)  # T2 moves to S2, first
    body[1]["topics"].insert(0, moved | {"name_en": "T2*"})
    body[0]["name_en"] = "S1*"
    body[1]["topics"].append({"name_ar": "T4", "name_en": "T4"})
    t3_id = body[1]["topics"][1]["id"]
    body[1]["topics"] = [t for t in body[1]["topics"] if t.get("id") != t3_id]
    services.update_level(level, name_ar="L", name_en="L", is_active=True, sub_levels=body)
    s1, s2 = level.sub_levels.all()
    assert s1.name_en == "S1*"
    assert [t.name_en for t in s1.topics.all()] == ["T1"]
    assert [(t.name_en, t.position) for t in s2.topics.all()] == [("T2*", 0), ("T4", 1)]
    assert not Topic.objects.filter(pk=t3_id).exists()
    assert Topic.objects.get(name_en="T2*").pk == moved["id"]


def test_update_refuses_foreign_ids_and_course_change(world, make_level):
    level = _create(world)
    other = make_level(world.course_b)
    body = _payload(level)
    body[0]["topics"].append(
        {"id": other.sub_levels.first().topics.first().id, "name_ar": "x", "name_en": "x"}
    )
    with pytest.raises(ValidationError) as err:
        services.update_level(level, name_ar="L", name_en="L", is_active=True, sub_levels=body)
    assert err.value.field == "sub_levels"
    with pytest.raises(ValidationError) as err:
        services.update_level(
            level, name_ar="L", name_en="L", is_active=True,
            sub_levels=_payload(level), course_id=world.course_b.id,
        )
    assert err.value.field == "course"


def _complete(world, topic):
    TopicCompletion.objects.create(
        student=world.student_profile, topic=topic, completed_on=date(2026, 6, 1)
    )


def test_dropping_completed_topic_conflicts(world):
    level = _create(world)
    body = _payload(level)
    _complete(world, Topic.objects.get(pk=body[0]["topics"][0]["id"]))
    body[0]["topics"].pop(0)
    with pytest.raises(ConflictError) as err:
        services.update_level(level, name_ar="L", name_en="L", is_active=True, sub_levels=body)
    assert err.value.code == "learning.topic_in_use"


def test_dropping_sub_level_with_completed_topic_conflicts(world):
    level = _create(world, subs=(("S1", ("T1",)), ("S2", ("T2",))))
    body = _payload(level)
    _complete(world, Topic.objects.get(pk=body[1]["topics"][0]["id"]))
    with pytest.raises(ConflictError) as err:
        services.update_level(
            level, name_ar="L", name_en="L", is_active=True, sub_levels=body[:1]
        )
    assert err.value.code == "learning.topic_in_use"


def test_delete_level_with_only_a_completion_conflicts(world):
    level = _create(world)
    _complete(world, Topic.objects.filter(sub_level__level=level).first())
    with pytest.raises(ConflictError) as err:
        services.delete_level(level)
    assert err.value.code == "learning.level_in_use"


def test_delete_level_with_a_student_level_conflicts(world):
    level = _create(world)
    StudentLevel.objects.create(
        student=world.student_profile, course=world.course, level=level,
        started_on=date(2026, 6, 1),
    )
    with pytest.raises(ConflictError):
        services.delete_level(level)


def test_delete_unused_level_and_positions_close_up(world):
    a, b, c = (_create(world, n) for n in ("A", "B", "C"))
    services.delete_level(b)
    assert list(Level.objects.filter(course=world.course).values_list("name_en", "position")) == [
        ("A", 0),
        ("C", 1),
    ]


def test_reorder(world):
    a, b = _create(world, "A"), _create(world, "B")
    services.reorder_levels(course_id=world.course.id, ids=[b.id, a.id])
    assert list(Level.objects.filter(course=world.course).values_list("name_en", flat=True)) == ["B", "A"]
    with pytest.raises(ValidationError) as err:
        services.reorder_levels(course_id=world.course.id, ids=[a.id])
    assert err.value.field == "ids"


def test_limits(world):
    with pytest.raises(ValidationError):
        services.create_level(
            course_id=world.course.id, name_ar="x", name_en="x",
            sub_levels=_tree(*[(f"S{i}", ()) for i in range(51)]),
        )


def test_topic_chapter_rules(world, set_features):
    services.sync_chapters()
    fatiha = QuranChapter.objects.get(number=1)  # 7 verses

    def topic(**extra):
        return [{"name_ar": "s", "name_en": "s", "topics": [{"name_ar": "t", "name_en": "t", **extra}]}]

    level = services.create_level(
        course_id=world.course.id, name_ar="x", name_en="x",
        sub_levels=topic(chapter=fatiha.id, from_verse=1, to_verse=7),
    )
    assert Topic.objects.get(sub_level__level=level).chapter == fatiha
    for bad in (
        {"chapter": fatiha.id, "from_verse": 1},
        {"chapter": fatiha.id, "from_verse": 5, "to_verse": 2},
        {"chapter": fatiha.id, "from_verse": 1, "to_verse": 8},
        {"from_verse": 1, "to_verse": 2},
        {"chapter": 999999},
    ):
        with pytest.raises(ValidationError) as err:
            services.create_level(course_id=world.course.id, name_ar="x", name_en="x", sub_levels=topic(**bad))
        assert err.value.field.startswith("sub_levels.0.topics.0."), bad
    set_features(quran_chapters=False)
    with pytest.raises(ValidationError) as err:
        services.create_level(course_id=world.course.id, name_ar="x", name_en="x", sub_levels=topic(chapter=fatiha.id))
    assert err.value.field == "sub_levels.0.topics.0.chapter"


def test_course_without_history_stays_deletable(world):
    _create(world)
    course = catalogue_services.create_course(name_ar="ك", name_en="Empty")
    services.create_level(course_id=course.id, name_ar="x", name_en="x", sub_levels=[])
    catalogue_services.delete_course(course)
    assert not Level.objects.filter(course_id=course.id).exists()
```

- [ ] **Step 2: Run to verify failure** — FAIL (`create_level` missing).

- [ ] **Step 3: Implement** — `backend/etqan/learning/services/curriculum.py`

```python
"""Spec B6a C-1, C-2, C-4, C-5, §8.1: a course's levels with their sub-levels
and topics, edited as one tree."""

from django.db import transaction
from django.db.models import Count
from django.db.models import Prefetch

from etqan.catalogue import services as catalogue_services
from etqan.learning.models import Level
from etqan.learning.models import LevelUpgradeRequest
from etqan.learning.models import QuranChapter
from etqan.learning.models import StudentLevel
from etqan.learning.models import SubLevel
from etqan.learning.models import Topic
from etqan.learning.models import TopicCompletion
from etqan.platform import features
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

MAX_SUB_LEVELS = 50
MAX_TOPICS = 200
TOPIC_IN_USE = "A student has completed this topic: rename it instead of removing it."


def levels_queryset():
    return (
        Level.objects.select_related("course")
        .annotate(
            sub_level_count=Count("sub_levels", distinct=True),
            topic_count=Count("sub_levels__topics", distinct=True),
        )
        .prefetch_related(
            Prefetch(
                "sub_levels",
                queryset=SubLevel.objects.prefetch_related(
                    Prefetch("topics", queryset=Topic.objects.select_related("chapter"))
                ),
            )
        )
    )


def get_level(level_id: int) -> Level:
    level = levels_queryset().filter(pk=level_id).first()
    if level is None:
        raise NotFoundError("Level", level_id)
    return level


def _course(course_id):
    course = catalogue_services.get_course(course_id)
    if course is None:
        raise ValidationError("Choose a course.", field="course")
    return course


def _chapter_fields(topic: dict, path: str) -> dict:
    chapter_id = topic.get("chapter")
    first, last = topic.get("from_verse"), topic.get("to_verse")
    if chapter_id is None:
        if first is not None or last is not None:
            raise ValidationError("Choose a chapter for a verse range.", field=f"{path}.chapter")
        return {"chapter": None, "from_verse": None, "to_verse": None}
    if not features.enabled("quran_chapters"):
        raise ValidationError("Qur'an chapters are switched off.", field=f"{path}.chapter")
    chapter = QuranChapter.objects.filter(pk=chapter_id).first()
    if chapter is None:
        raise ValidationError("Choose a chapter.", field=f"{path}.chapter")
    if (first is None) != (last is None):
        raise ValidationError("Give both verses or neither.", field=f"{path}.to_verse")
    if first is not None and not (1 <= first <= last <= chapter.verses_count):
        raise ValidationError(
            f"Verses run from 1 to {chapter.verses_count}, first to last.",
            field=f"{path}.to_verse",
        )
    return {"chapter": chapter, "from_verse": first, "to_verse": last}


def _check_limits(sub_levels: list[dict]) -> None:
    if len(sub_levels) > MAX_SUB_LEVELS:
        raise ValidationError(f"At most {MAX_SUB_LEVELS} sub-levels.", field="sub_levels")
    for i, sub in enumerate(sub_levels):
        if len(sub.get("topics", [])) > MAX_TOPICS:
            raise ValidationError(f"At most {MAX_TOPICS} topics.", field=f"sub_levels.{i}.topics")


def _write_tree(level: Level, sub_levels: list[dict]) -> None:
    """C-2: keep rows by id, create the rest, delete what was left out."""
    _check_limits(sub_levels)
    old_subs = {s.pk: s for s in SubLevel.objects.filter(level=level)}
    old_topics = {t.pk: t for t in Topic.objects.filter(sub_level__level=level)}
    sent_subs = {s["id"] for s in sub_levels if s.get("id")}
    sent_topics = {t["id"] for s in sub_levels for t in s.get("topics", []) if t.get("id")}
    if not sent_subs <= old_subs.keys() or not sent_topics <= old_topics.keys():
        raise ValidationError("A sub-level or topic is not part of this level.", field="sub_levels")
    dropped = old_topics.keys() - sent_topics
    if TopicCompletion.objects.filter(topic_id__in=dropped).exists():
        raise ConflictError(TOPIC_IN_USE, code="learning.topic_in_use")
    kept_subs = []
    for i, data in enumerate(sub_levels):
        sub = old_subs.get(data.get("id")) or SubLevel(level=level)
        sub.name_ar, sub.name_en, sub.position = data["name_ar"], data["name_en"], i
        sub.save()
        kept_subs.append(sub.pk)
        for j, t in enumerate(data.get("topics", [])):
            topic = old_topics.get(t.get("id")) or Topic()
            topic.sub_level = sub
            topic.name_ar, topic.name_en, topic.position = t["name_ar"], t["name_en"], j
            for field, value in _chapter_fields(t, f"sub_levels.{i}.topics.{j}").items():
                setattr(topic, field, value)
            topic.save()
    Topic.objects.filter(pk__in=dropped).delete()
    SubLevel.objects.filter(level=level).exclude(pk__in=kept_subs).delete()


@transaction.atomic
def create_level(*, course_id, name_ar, name_en, is_active=True, sub_levels) -> Level:
    course = _course(course_id)
    level = Level.objects.create(
        course=course,
        name_ar=name_ar,
        name_en=name_en,
        is_active=is_active,
        position=Level.objects.filter(course=course).count(),
    )
    _write_tree(level, sub_levels)
    return get_level(level.pk)


@transaction.atomic
def update_level(level, *, name_ar, name_en, is_active, sub_levels, course_id=None) -> Level:
    if course_id is not None and course_id != level.course_id:
        raise ValidationError("A level cannot move to another course.", field="course")
    level.name_ar, level.name_en, level.is_active = name_ar, name_en, is_active
    level.save(update_fields=["name_ar", "name_en", "is_active", "updated_at"])
    _write_tree(level, sub_levels)
    return get_level(level.pk)


def _renumber(course_id) -> None:
    for i, level in enumerate(Level.objects.filter(course_id=course_id)):
        if level.position != i:
            Level.objects.filter(pk=level.pk).update(position=i)


@transaction.atomic
def delete_level(level) -> None:
    in_use = (
        StudentLevel.objects.filter(level=level).exists()
        or LevelUpgradeRequest.objects.filter(from_level=level).exists()
        or LevelUpgradeRequest.objects.filter(to_level=level).exists()
        or TopicCompletion.objects.filter(topic__sub_level__level=level).exists()
    )
    if in_use:
        raise ConflictError(
            "Students have records on this level: deactivate it instead.",
            code="learning.level_in_use",
        )
    course_id = level.course_id
    level.delete()
    _renumber(course_id)


@transaction.atomic
def reorder_levels(*, course_id, ids) -> None:
    current = set(Level.objects.filter(course_id=course_id).values_list("pk", flat=True))
    if len(ids) != len(set(ids)) or set(ids) != current:
        raise ValidationError("Send every level of the course once.", field="ids")
    for i, pk in enumerate(ids):
        Level.objects.filter(pk=pk).update(position=i)
```

Re-export in `services/__init__.py`: `levels_queryset, get_level, create_level, update_level, delete_level, reorder_levels, MAX_SUB_LEVELS, MAX_TOPICS`.

> Ordering note: `_write_tree` saves a moved topic under its new sub-level before deleting dropped sub-levels, so a topic moved out of a dropped sub-level survives.

- [ ] **Step 4: Run** — `uv run pytest etqan/learning/tests/test_curriculum.py -q` → PASS.
- [ ] **Step 5: Commit** — `git -C backend add etqan/learning && git -C backend commit -m "feat(learning): levels with sub-levels and topics (B6a)"`.

---

### Task 4: Access helpers and progress services

**Files:**
- Create: `backend/etqan/learning/services/access.py`, `backend/etqan/learning/services/progress.py`, `backend/etqan/learning/tests/test_progress.py`
- Modify: `backend/etqan/learning/services/__init__.py`

**Interfaces:**
- Consumes: Task 1 models and fixtures; Task 3 `levels_queryset`.
- Produces (access.py):
  - `LIVE = ("active", "paused")`
  - `teaches(teacher_user_id: int, student_user_id: int, course_id: int) -> bool`
  - `taught_pairs(teacher_user_id: int) -> set[tuple[int, int]]` — (student_user_id, course_id)
  - `live_pairs() -> set[tuple[int, int]]`
  - `office_reads(user, code: str) -> bool` — admin, or staff holding `code`
  - `progress_scope(user, student_user_id: int) -> set[int] | None` — None = all courses; raises `NotFoundError`
- Produces (progress.py):
  - `LevelRow(student_id: int, student_name: str, course_id: int, course_name_en: str, course_name_ar: str, level_id: int | None, level_name_en: str, level_name_ar: str, since: date | None, completed: int, total: int)` (frozen dataclass)
  - `level_rows(user, *, course: int | None = None, level: int | None = None, no_level: bool = False, search: str = "") -> list[LevelRow]`
  - `progress(student_user_id: int, course_id: int) -> dict` (shape in Step 3)
  - `progress_summary(student_user_id: int, course_ids: set[int] | None = None) -> list[dict]`
  - `current_level(student_user_id: int, course_id: int) -> StudentLevel | None`
  - `set_level(*, student_user_id: int, course_id: int, level_id: int, by) -> StudentLevel`
  - `complete_topic(*, student_user_id: int, course_id: int, topic_id: int, completed_on: date | None = None, by) -> TopicCompletion`
  - `uncomplete_topic(*, student_user_id: int, course_id: int, topic_id: int, by) -> None`
  - `progress_of(student_user_id: int, *, month: date) -> list[dict]` (B6-9 / ledger D26)
  - `academy_today() -> date` (wraps `scheduling.services.today()`)

- [ ] **Step 1: Write the failing tests** — `backend/etqan/learning/tests/test_progress.py`

```python
from datetime import date
from datetime import datetime
from datetime import UTC

import pytest

from etqan.learning import services
from etqan.learning.models import StudentLevel
from etqan.learning.models import Topic
from etqan.learning.models import TopicCompletion
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services


def _topics(level):
    return list(Topic.objects.filter(sub_level__level=level).order_by("position"))


def test_teaches_follows_live_subscriptions(world, subscribe):
    sub = subscribe()
    assert services.teaches(world.teacher.id, world.student.id, world.course.id)
    assert not services.teaches(world.teacher.id, world.student.id, world.course_b.id)
    assert not services.teaches(world.other_teacher.id, world.student.id, world.course.id)
    scheduling_services.cancel_subscription(sub, by=None)
    assert not services.teaches(world.teacher.id, world.student.id, world.course.id)


def test_progress_scope(world, subscribe, api_for, staff_for):
    subscribe()
    admin = api_for("admin").user
    assert services.progress_scope(admin, world.student.id) is None
    assert services.progress_scope(world.student, world.student.id) is None
    assert services.progress_scope(world.parent, world.student.id) is None
    assert services.progress_scope(world.teacher, world.student.id) == {world.course.id}
    assert services.progress_scope(staff_for("student_level.view").user, world.student.id) is None
    for outsider in (world.other_teacher, world.other_student, staff_for().user):
        with pytest.raises(NotFoundError):
            services.progress_scope(outsider, world.student.id)


def test_office_sets_and_changes_level_with_history(world, make_level, clock):
    low, high = make_level(world.course, "L1"), make_level(world.course, "L2")
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=low.id, by=None)
    clock.set(datetime(2026, 6, 10, 8, tzinfo=UTC))
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=high.id, by=None)
    rows = StudentLevel.objects.filter(student=world.student_profile).order_by("started_on")
    assert [(r.level_id, r.started_on, r.ended_on) for r in rows] == [
        (low.id, date(2026, 6, 1), date(2026, 6, 10)),
        (high.id, date(2026, 6, 10), None),
    ]


def test_set_same_level_is_noop(world, make_level):
    level = make_level(world.course)
    one = services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=level.id, by=None)
    two = services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=level.id, by=None)
    assert one.pk == two.pk
    assert StudentLevel.objects.count() == 1


def test_set_level_refuses_foreign_inactive_and_bad_student(world, make_level):
    foreign = make_level(world.course_b)
    inactive = make_level(world.course, is_active=False)
    for level in (foreign, inactive):
        with pytest.raises(ValidationError) as err:
            services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=level.id, by=None)
        assert err.value.field == "level"
    with pytest.raises(ValidationError) as err:
        services.set_level(student_user_id=world.teacher.id, course_id=world.course.id, level_id=make_level(world.course).id, by=None)
    assert err.value.field == "student"


def test_teacher_sets_first_level_only(world, make_level, subscribe):
    subscribe()
    low, high = make_level(world.course, "L1"), make_level(world.course, "L2")
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=low.id, by=world.teacher)
    with pytest.raises(ConflictError) as err:
        services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=high.id, by=world.teacher)
    assert err.value.code == "learning.level_already_set"


def test_complete_and_uncomplete_are_idempotent(world, make_level, clock):
    topic = _topics(make_level(world.course))[0]
    args = {"student_user_id": world.student.id, "course_id": world.course.id, "topic_id": topic.id}
    first = services.complete_topic(**args, by=None)
    again = services.complete_topic(**args, completed_on=date(2026, 5, 1), by=None)
    assert first.pk == again.pk and again.completed_on == date(2026, 6, 1)
    services.uncomplete_topic(**args, by=None)
    services.uncomplete_topic(**args, by=None)
    assert not TopicCompletion.objects.exists()
    with pytest.raises(ValidationError) as err:
        services.complete_topic(**args, completed_on=date(2026, 6, 2), by=None)
    assert err.value.field == "completed_on"


def test_topic_of_another_course_is_not_found(world, make_level):
    topic = _topics(make_level(world.course_b))[0]
    with pytest.raises(NotFoundError):
        services.complete_topic(student_user_id=world.student.id, course_id=world.course.id, topic_id=topic.id, by=None)


def test_level_rows_include_pairs_without_level(world, make_level, subscribe, api_for):
    subscribe()
    subscribe(student=world.other_student, course=world.course_b, teacher=world.other_teacher)
    level = make_level(world.course, topics=4)
    make_level(world.course, "Off", topics=3, is_active=False)
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=level.id, by=None)
    services.complete_topic(student_user_id=world.student.id, course_id=world.course.id, topic_id=_topics(level)[0].id, by=None)
    admin = api_for("admin").user
    rows = services.level_rows(admin)
    assert [(r.student_name, r.course_name_en, r.level_name_en, r.completed, r.total) for r in rows] == [
        ("Yusuf", "Quran", "Level", 1, 4),
        ("Zaid", "Tajweed", "", 0, 0),
    ]
    assert [r.student_name for r in services.level_rows(admin, no_level=True)] == ["Zaid"]
    assert [r.student_name for r in services.level_rows(admin, search="yus")] == ["Yusuf"]
    assert [r.student_name for r in services.level_rows(world.teacher)] == ["Yusuf"]
    assert [r.student_name for r in services.level_rows(world.other_teacher)] == ["Zaid"]


def test_level_rows_keep_a_level_without_live_subscription(world, make_level, api_for):
    level = make_level(world.course)
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=level.id, by=None)
    assert [r.student_name for r in services.level_rows(api_for("admin").user)] == ["Yusuf"]


def test_progress_detail_and_summary(world, make_level):
    level = make_level(world.course, topics=2)
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=level.id, by=None)
    services.complete_topic(student_user_id=world.student.id, course_id=world.course.id, topic_id=_topics(level)[1].id, by=None)
    detail = services.progress(world.student.id, world.course.id)
    assert detail["current"]["level_id"] == level.id
    assert [t["completed_on"] for t in detail["levels"][0]["sub_levels"][0]["topics"]] == [None, date(2026, 6, 1)]
    assert detail["pending_request"] is None
    summary = services.progress_summary(world.student.id)
    assert [(s["course_id"], s["completed"], s["total"]) for s in summary] == [(world.course.id, 1, 2)]
    assert services.progress_summary(world.student.id, course_ids={world.course_b.id}) == []


def test_progress_of_a_past_month(world, make_level, clock):
    low, high = make_level(world.course, "L1", topics=3), make_level(world.course, "L2")
    t = _topics(low)
    clock.set(datetime(2026, 5, 20, 8, tzinfo=UTC))
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=low.id, by=None)
    services.complete_topic(student_user_id=world.student.id, course_id=world.course.id, topic_id=t[0].id, by=None)
    clock.set(datetime(2026, 6, 5, 8, tzinfo=UTC))
    services.complete_topic(student_user_id=world.student.id, course_id=world.course.id, topic_id=t[1].id, by=None)
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=high.id, by=None)
    (may,) = services.progress_of(world.student.id, month=date(2026, 5, 1))
    assert may["level_id"] == low.id
    assert [c["topic_id"] for c in may["completed_in_month"]] == [t[0].id]
    assert may["level_changes"] == [{"from_level_id": None, "to_level_id": low.id, "on": date(2026, 5, 20)}]
    (june,) = services.progress_of(world.student.id, month=date(2026, 6, 15))
    assert june["level_id"] == high.id
    assert [c["topic_id"] for c in june["completed_in_month"]] == [t[1].id]
    assert june["level_changes"] == [{"from_level_id": low.id, "to_level_id": high.id, "on": date(2026, 6, 5)}]
    assert june["completed_total"] == 2
    assert services.progress_of(world.student.id, month=date(2026, 4, 1)) == []
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** — `backend/etqan/learning/services/access.py`

```python
"""Spec B6-4, B6-5, §8.3: who may read and act on a student's learning."""

from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError
from etqan.platform.permissions import codes_of
from etqan.platform.permissions import role_of
from etqan.scheduling import services as scheduling_services

# Subscription statuses compared as strings: learning never imports
# scheduling's models (B6-5).
LIVE = ("active", "paused")


def _live():
    return scheduling_services.subscriptions_queryset().filter(status__in=LIVE)


def teaches(teacher_user_id: int, student_user_id: int, course_id: int) -> bool:
    return _live().filter(
        teacher__user_id=teacher_user_id,
        student__user_id=student_user_id,
        course_id=course_id,
    ).exists()


def taught_pairs(teacher_user_id: int) -> set[tuple[int, int]]:
    return set(
        _live()
        .filter(teacher__user_id=teacher_user_id)
        .values_list("student__user_id", "course_id")
    )


def live_pairs() -> set[tuple[int, int]]:
    return set(_live().values_list("student__user_id", "course_id"))


def office_reads(user, code: str) -> bool:
    role = role_of(user)
    return role == "admin" or (role == "staff" and code in codes_of(user))


def progress_scope(user, student_user_id: int) -> set[int] | None:
    """The courses ``user`` may read of this student: None for all."""
    role = role_of(user)
    if office_reads(user, "student_level.view"):
        return None
    if role == "student" and user.pk == student_user_id:
        return None
    if role == "parent" and identity_services.is_parent_of(user.pk, student_user_id):
        return None
    if role == "teacher":
        courses = {c for s, c in taught_pairs(user.pk) if s == student_user_id}
        if courses:
            return courses
    raise NotFoundError("Student", student_user_id)
```

`backend/etqan/learning/services/progress.py`

```python
"""Spec B6a C-7..C-9, C-15, §8.4: each student's place on a course's ladder."""

import calendar
from dataclasses import dataclass
from datetime import date

from django.db import transaction

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.learning.models import Level
from etqan.learning.models import LevelUpgradeRequest
from etqan.learning.models import StudentLevel
from etqan.learning.models import Topic
from etqan.learning.models import TopicCompletion
from etqan.learning.services import access
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import role_of
from etqan.scheduling import services as scheduling_services


def academy_today() -> date:
    return scheduling_services.today()


@dataclass(frozen=True)
class LevelRow:
    student_id: int
    student_name: str
    course_id: int
    course_name_en: str
    course_name_ar: str
    level_id: int | None
    level_name_en: str
    level_name_ar: str
    since: date | None
    completed: int
    total: int


def _student(student_user_id: int):
    profile = identity_services.get_student_profile(student_user_id)
    if profile is None or profile.user.role != "student" or not profile.user.is_active:
        raise ValidationError("Choose an active student.", field="student")
    return profile


def current_level(student_user_id: int, course_id: int) -> StudentLevel | None:
    return (
        StudentLevel.objects.select_related("level")
        .filter(student__user_id=student_user_id, course_id=course_id, ended_on__isnull=True)
        .first()
    )


def _totals(course_ids) -> dict[int, int]:
    """C-15: topics of active levels, per course."""
    totals: dict[int, int] = {}
    for course_id in Topic.objects.filter(
        sub_level__level__course_id__in=course_ids, sub_level__level__is_active=True
    ).values_list("sub_level__level__course_id", flat=True):
        totals[course_id] = totals.get(course_id, 0) + 1
    return totals


def _completed(pairs) -> dict[tuple[int, int], int]:
    students = {s for s, _ in pairs}
    counts: dict[tuple[int, int], int] = {}
    for s, c in TopicCompletion.objects.filter(
        student__user_id__in=students, topic__sub_level__level__is_active=True
    ).values_list("student__user_id", "topic__sub_level__level__course_id"):
        counts[(s, c)] = counts.get((s, c), 0) + 1
    return counts


def level_rows(user, *, course=None, level=None, no_level=False, search="") -> list[LevelRow]:
    if role_of(user) == "teacher":
        pairs = access.taught_pairs(user.pk)
    else:
        current = StudentLevel.objects.filter(ended_on__isnull=True).values_list(
            "student__user_id", "course_id"
        )
        pairs = access.live_pairs() | set(current)
    if course is not None:
        pairs = {p for p in pairs if p[1] == course}
    levels = {
        (sl.student.user_id, sl.course_id): sl
        for sl in StudentLevel.objects.select_related("level", "student")
        .filter(ended_on__isnull=True)
        .filter(student__user_id__in={s for s, _ in pairs})
    }
    users = identity_services.get_users({s for s, _ in pairs})
    courses = catalogue_services.courses_by_id({c for _, c in pairs})
    totals = _totals(courses.keys())
    done = _completed(pairs)
    rows = []
    for s, c in pairs:
        sl = levels.get((s, c))
        if level is not None and (sl is None or sl.level_id != level):
            continue
        if no_level and sl is not None:
            continue
        name = users[s].full_name
        if search and search.lower() not in name.lower():
            continue
        rows.append(
            LevelRow(
                student_id=s,
                student_name=name,
                course_id=c,
                course_name_en=courses[c].name_en,
                course_name_ar=courses[c].name_ar,
                level_id=sl.level_id if sl else None,
                level_name_en=sl.level.name_en if sl else "",
                level_name_ar=sl.level.name_ar if sl else "",
                since=sl.started_on if sl else None,
                completed=done.get((s, c), 0),
                total=totals.get(c, 0),
            )
        )
    return sorted(rows, key=lambda r: (r.student_name.lower(), r.course_name_en.lower(), r.student_id))


def _level_dict(level) -> dict:
    return {"level_id": level.pk, "name_en": level.name_en, "name_ar": level.name_ar}


def progress(student_user_id: int, course_id: int) -> dict:
    """Shape: {course_id, current: {level_id, name_en, name_ar, since} | None,
    history: [{level_id, name_en, name_ar, started_on, ended_on}],
    levels: [{id, name_en, name_ar, is_active, sub_levels: [{id, name_en, name_ar,
    topics: [{id, name_en, name_ar, chapter, from_verse, to_verse, completed_on}]}]}],
    pending_request: {id, from_level_id, to_level_id, note, created_at} | None,
    completed, total}"""
    from etqan.learning.services.curriculum import levels_queryset  # noqa: PLC0415

    done = dict(
        TopicCompletion.objects.filter(
            student__user_id=student_user_id, topic__sub_level__level__course_id=course_id
        ).values_list("topic_id", "completed_on")
    )
    history = StudentLevel.objects.select_related("level").filter(
        student__user_id=student_user_id, course_id=course_id
    )
    current = next((h for h in history if h.ended_on is None), None)
    pending = LevelUpgradeRequest.objects.filter(
        student__user_id=student_user_id, course_id=course_id, status="pending"
    ).first()
    levels = levels_queryset().filter(course_id=course_id)
    active_topics = [
        t.pk for lv in levels if lv.is_active for s in lv.sub_levels.all() for t in s.topics.all()
    ]
    return {
        "course_id": course_id,
        "current": _level_dict(current.level) | {"since": current.started_on} if current else None,
        "history": [
            _level_dict(h.level) | {"started_on": h.started_on, "ended_on": h.ended_on}
            for h in history
        ],
        "levels": [
            {
                "id": lv.pk,
                "name_en": lv.name_en,
                "name_ar": lv.name_ar,
                "is_active": lv.is_active,
                "sub_levels": [
                    {
                        "id": s.pk,
                        "name_en": s.name_en,
                        "name_ar": s.name_ar,
                        "topics": [
                            {
                                "id": t.pk,
                                "name_en": t.name_en,
                                "name_ar": t.name_ar,
                                "chapter": t.chapter.number if t.chapter else None,
                                "from_verse": t.from_verse,
                                "to_verse": t.to_verse,
                                "completed_on": done.get(t.pk),
                            }
                            for t in s.topics.all()
                        ],
                    }
                    for s in lv.sub_levels.all()
                ],
            }
            for lv in levels
        ],
        "pending_request": None
        if pending is None
        else {
            "id": pending.pk,
            "from_level_id": pending.from_level_id,
            "to_level_id": pending.to_level_id,
            "note": pending.note,
            "created_at": pending.created_at,
        },
        "completed": sum(1 for t in active_topics if t in done),
        "total": len(active_topics),
    }


def progress_summary(student_user_id: int, course_ids: set[int] | None = None) -> list[dict]:
    """Per course with a current level or a completion: {course_id, course_name_en,
    course_name_ar, level: {level_id, name_en, name_ar, since} | None, completed, total}."""
    levels = {
        sl.course_id: sl
        for sl in StudentLevel.objects.select_related("level").filter(
            student__user_id=student_user_id, ended_on__isnull=True
        )
    }
    completed_courses = set(
        TopicCompletion.objects.filter(student__user_id=student_user_id).values_list(
            "topic__sub_level__level__course_id", flat=True
        )
    )
    wanted = set(levels) | completed_courses
    if course_ids is not None:
        wanted &= course_ids
    courses = catalogue_services.courses_by_id(wanted)
    totals = _totals(wanted)
    done = _completed({(student_user_id, c) for c in wanted})
    out = []
    for c in sorted(wanted, key=lambda c: courses[c].name_en.lower()):
        sl = levels.get(c)
        out.append(
            {
                "course_id": c,
                "course_name_en": courses[c].name_en,
                "course_name_ar": courses[c].name_ar,
                "level": _level_dict(sl.level) | {"since": sl.started_on} if sl else None,
                "completed": done.get((student_user_id, c), 0),
                "total": totals.get(c, 0),
            }
        )
    return out


@transaction.atomic
def set_level(*, student_user_id: int, course_id: int, level_id: int, by) -> StudentLevel:
    student = _student(student_user_id)
    level = Level.objects.filter(pk=level_id, course_id=course_id, is_active=True).first()
    if level is None:
        raise ValidationError("Choose an active level of this course.", field="level")
    current = (
        StudentLevel.objects.select_for_update()
        .filter(student=student, course_id=course_id, ended_on__isnull=True)
        .first()
    )
    if current is not None and current.level_id == level.pk:
        return current
    if current is not None and role_of(by) == "teacher":
        raise ConflictError(
            "This student already has a level: ask for an upgrade.",
            code="learning.level_already_set",
        )
    today = academy_today()
    if current is not None:
        current.ended_on = today
        current.save(update_fields=["ended_on"])
    return StudentLevel.objects.create(
        student=student, course_id=course_id, level=level, started_on=today, set_by=by
    )


def _topic(course_id: int, topic_id: int) -> Topic:
    topic = Topic.objects.filter(pk=topic_id, sub_level__level__course_id=course_id).first()
    if topic is None:
        raise NotFoundError("Topic", topic_id)
    return topic


@transaction.atomic
def complete_topic(*, student_user_id, course_id, topic_id, completed_on=None, by) -> TopicCompletion:
    topic = _topic(course_id, topic_id)
    student = _student(student_user_id)
    today = academy_today()
    if completed_on is not None and completed_on > today:
        raise ValidationError("A topic cannot be completed in the future.", field="completed_on")
    completion, _ = TopicCompletion.objects.get_or_create(
        student=student,
        topic=topic,
        defaults={"completed_on": completed_on or today, "recorded_by": by},
    )
    return completion


def uncomplete_topic(*, student_user_id, course_id, topic_id, by) -> None:
    topic = _topic(course_id, topic_id)
    TopicCompletion.objects.filter(student__user_id=student_user_id, topic=topic).delete()


def _month_bounds(month: date) -> tuple[date, date]:
    first = month.replace(day=1)
    last = first.replace(day=calendar.monthrange(first.year, first.month)[1])
    return first, last


def progress_of(student_user_id: int, *, month: date) -> list[dict]:
    """B6-9 / ledger D26: what B10's monthly report reads."""
    first, last = _month_bounds(month)
    history = list(
        StudentLevel.objects.select_related("level")
        .filter(student__user_id=student_user_id)
        .order_by("started_on", "id")
    )
    at_end = {
        h.course_id: h
        for h in history
        if h.started_on <= last and (h.ended_on is None or h.ended_on > last)
    }
    completions = list(
        TopicCompletion.objects.select_related("topic__sub_level__level")
        .filter(student__user_id=student_user_id, completed_on__lte=last)
        .order_by("completed_on", "id")
    )
    in_month = [c for c in completions if c.completed_on >= first]
    courses_wanted = set(at_end) | {c.topic.sub_level.level.course_id for c in in_month}
    courses = catalogue_services.courses_by_id(courses_wanted)
    totals = _totals(courses_wanted)
    decisions = LevelUpgradeRequest.objects.filter(
        student__user_id=student_user_id,
        decided_at__date__gte=first,
        decided_at__date__lte=last,
    )
    out = []
    for c in sorted(courses_wanted, key=lambda c: courses[c].name_en.lower()):
        h = at_end.get(c)
        course_history = [x for x in history if x.course_id == c]
        changes = []
        for i, x in enumerate(course_history):
            if first <= x.started_on <= last:
                previous = course_history[i - 1].level_id if i else None
                changes.append({"from_level_id": previous, "to_level_id": x.level_id, "on": x.started_on})
        out.append(
            {
                "course_id": c,
                "course_name_en": courses[c].name_en,
                "course_name_ar": courses[c].name_ar,
                "level_id": h.level_id if h else None,
                "level_name_en": h.level.name_en if h else "",
                "level_name_ar": h.level.name_ar if h else "",
                "completed_in_month": [
                    {
                        "topic_id": x.topic_id,
                        "name_en": x.topic.name_en,
                        "name_ar": x.topic.name_ar,
                        "completed_on": x.completed_on,
                    }
                    for x in in_month
                    if x.topic.sub_level.level.course_id == c
                ],
                "completed_total": sum(
                    1 for x in completions if x.topic.sub_level.level.course_id == c
                ),
                "total_topics": totals.get(c, 0),
                "level_changes": changes,
                "decisions": [
                    {
                        "request_id": d.pk,
                        "status": d.status,
                        "decided_at": d.decided_at,
                        "rejection_reason": d.rejection_reason,
                    }
                    for d in decisions
                    if d.course_id == c
                ],
            }
        )
    return out
```

> `decided_at__date` uses the database timezone (UTC). If the academy timezone is not UTC this can shift a decision across a month boundary; acceptable for B10 drafts (note it in the docstring). `identity_services.get_users(ids)` returns `{id: User}` (it exists in `identity/services.py:118`).

`services/__init__.py` re-exports every name in **Produces** above.

- [ ] **Step 4: Run** — PASS. If `scheduling_services.cancel_subscription(sub, by=None)` has another signature, read `scheduling/services/subscriptions.py` and adapt the test call only.
- [ ] **Step 5: Commit** — `git -C backend add etqan/learning && git -C backend commit -m "feat(learning): student levels and topic progress (B6a)"`.

---

### Task 5: Level upgrade requests

**Files:**
- Create: `backend/etqan/learning/services/upgrades.py`, `backend/etqan/learning/tests/test_upgrades.py`
- Modify: `backend/etqan/learning/services/__init__.py`

**Interfaces:**
- Consumes: `access.teaches`, `access.taught_pairs`, `progress.set_level`, `progress.current_level`, `progress._student` (Task 4).
- Produces:
  - `request_upgrade(*, student_user_id: int, course_id: int, subscription_id: int | None = None, note: str = "", by) -> LevelUpgradeRequest`
  - `approve_request(req: LevelUpgradeRequest, *, by) -> LevelUpgradeRequest`
  - `reject_request(req: LevelUpgradeRequest, *, reason: str, by) -> LevelUpgradeRequest`
  - `requests_queryset(user, *, status: str | None = None, student: int | None = None, course: int | None = None) -> QuerySet` (select_related student__user, course, from_level, to_level, requested_by, decided_by)
  - `get_request(user, request_id: int) -> LevelUpgradeRequest` (scoped; `NotFoundError`)

- [ ] **Step 1: Write the failing tests** — `backend/etqan/learning/tests/test_upgrades.py`

```python
import pytest

from etqan.learning import services
from etqan.learning.models import Level
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError


@pytest.fixture
def ladder(world, make_level, subscribe):
    sub = subscribe()
    low, high = make_level(world.course, "L1"), make_level(world.course, "L2")
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=low.id, by=None)
    return sub, low, high


def _ask(world, by, **extra):
    return services.request_upgrade(student_user_id=world.student.id, course_id=world.course.id, by=by, **extra)


def test_teacher_asks_office_approves(world, ladder, api_for):
    sub, low, high = ladder
    req = _ask(world, world.teacher, subscription_id=sub.id, note="Ready")
    assert (req.from_level, req.to_level, req.status) == (low, high, "pending")
    services.approve_request(req, by=api_for("admin").user)
    assert services.current_level(world.student.id, world.course.id).level == high
    req.refresh_from_db()
    assert req.status == "approved" and req.decided_at is not None


def test_ask_rules(world, ladder, make_level):
    sub, low, high = ladder
    _ask(world, None)
    with pytest.raises(ConflictError) as err:
        _ask(world, None)
    assert err.value.code == "learning.request_pending"
    with pytest.raises(ConflictError) as err:
        services.request_upgrade(student_user_id=world.other_student.id, course_id=world.course.id, by=None)
    assert err.value.code == "learning.no_level"
    services.set_level(student_user_id=world.other_student.id, course_id=world.course.id, level_id=high.id, by=None)
    with pytest.raises(ConflictError) as err:
        services.request_upgrade(student_user_id=world.other_student.id, course_id=world.course.id, by=None)
    assert err.value.code == "learning.top_level"


def test_next_level_skips_inactive(world, ladder, make_level):
    sub, low, high = ladder
    Level.objects.filter(pk=high.pk).update(is_active=False)
    top = make_level(world.course, "L3")
    assert _ask(world, None).to_level == top


def test_teacher_who_does_not_teach_is_refused(world, ladder):
    with pytest.raises(ValidationError) as err:
        _ask(world, world.other_teacher)
    assert err.value.field == "student"


def test_foreign_subscription_is_refused(world, ladder, subscribe):
    other = subscribe(student=world.other_student)
    with pytest.raises(ValidationError) as err:
        _ask(world, None, subscription_id=other.id)
    assert err.value.field == "subscription"


def test_approve_stale_requests(world, ladder, make_level):
    sub, low, high = ladder
    req = _ask(world, None)
    Level.objects.filter(pk=high.pk).update(is_active=False)
    with pytest.raises(ConflictError) as err:
        services.approve_request(req, by=None)
    assert err.value.code == "learning.level_inactive"
    Level.objects.filter(pk=high.pk).update(is_active=True)
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=high.id, by=None)
    with pytest.raises(ConflictError) as err:
        services.approve_request(req, by=None)
    assert err.value.code == "learning.level_changed"
    req.refresh_from_db()
    assert req.status == "pending"


def test_reject_needs_reason_and_decisions_are_final(world, ladder):
    req = _ask(world, None)
    with pytest.raises(ValidationError) as err:
        services.reject_request(req, reason="  ", by=None)
    assert err.value.field == "reason"
    services.reject_request(req, reason="Not yet", by=None)
    for decide in (lambda: services.approve_request(req, by=None), lambda: services.reject_request(req, reason="x", by=None)):
        with pytest.raises(ConflictError) as err:
            decide()
        assert err.value.code == "learning.request_decided"


def test_requests_queryset_scopes_teachers_by_pair(world, ladder, subscribe, make_level, api_for):
    _ask(world, None)
    # The same student in course B with another teacher: world.teacher must not see it.
    subscribe(course=world.course_b, teacher=world.other_teacher)
    b1, b2 = make_level(world.course_b, "B1"), make_level(world.course_b, "B2")
    services.set_level(student_user_id=world.student.id, course_id=world.course_b.id, level_id=b1.id, by=None)
    services.request_upgrade(student_user_id=world.student.id, course_id=world.course_b.id, by=None)
    assert services.requests_queryset(api_for("admin").user).count() == 2
    assert [r.course_id for r in services.requests_queryset(world.teacher)] == [world.course.id]
    assert [r.course_id for r in services.requests_queryset(world.other_teacher)] == [world.course_b.id]
    assert services.requests_queryset(world.student).count() == 0
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** — `backend/etqan/learning/services/upgrades.py`

```python
"""Spec B6a C-10, C-11, §8.5: a teacher asks, the office decides."""

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from etqan.learning.models import Level
from etqan.learning.models import LevelUpgradeRequest
from etqan.learning.services import access
from etqan.learning.services import progress
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import is_office
from etqan.platform.permissions import role_of
from etqan.scheduling import services as scheduling_services

PENDING = LevelUpgradeRequest.Status.PENDING


def _next_level(level: Level) -> Level | None:
    return (
        Level.objects.filter(course_id=level.course_id, is_active=True)
        .filter(Q(position__gt=level.position) | Q(position=level.position, pk__gt=level.pk))
        .order_by("position", "id")
        .first()
    )


@transaction.atomic
def request_upgrade(*, student_user_id, course_id, subscription_id=None, note="", by):
    student = progress._student(student_user_id)  # noqa: SLF001 -- same package
    if role_of(by) == "teacher" and not access.teaches(by.pk, student_user_id, course_id):
        raise ValidationError("You do not teach this student in this course.", field="student")
    if subscription_id is not None and not scheduling_services.subscriptions_queryset().filter(
        pk=subscription_id, student__user_id=student_user_id, course_id=course_id
    ).exists():
        raise ValidationError("Choose this student's subscription to this course.", field="subscription")
    current = progress.current_level(student_user_id, course_id)
    if current is None:
        raise ConflictError("Set the student's level first.", code="learning.no_level")
    target = _next_level(current.level)
    if target is None:
        raise ConflictError("The student is at the last level.", code="learning.top_level")
    if LevelUpgradeRequest.objects.filter(student=student, course_id=course_id, status=PENDING).exists():
        raise ConflictError("A request is already waiting.", code="learning.request_pending")
    return LevelUpgradeRequest.objects.create(
        student=student,
        course_id=course_id,
        subscription_id=subscription_id,
        from_level=current.level,
        to_level=target,
        note=note.strip(),
        requested_by=by,
    )


def _pending(req) -> LevelUpgradeRequest:
    locked = LevelUpgradeRequest.objects.select_for_update().get(pk=req.pk)
    if locked.status != PENDING:
        raise ConflictError("This request has been decided.", code="learning.request_decided")
    return locked


@transaction.atomic
def approve_request(req, *, by):
    req = _pending(req)
    current = progress.current_level(req.student.user_id, req.course_id)
    if current is None or current.level_id != req.from_level_id:
        raise ConflictError("The student's level changed since the request.", code="learning.level_changed")
    if not Level.objects.filter(pk=req.to_level_id, is_active=True).exists():
        raise ConflictError("The next level was deactivated.", code="learning.level_inactive")
    progress.set_level(
        student_user_id=req.student.user_id, course_id=req.course_id, level_id=req.to_level_id, by=None
    )
    req.status, req.decided_by, req.decided_at = LevelUpgradeRequest.Status.APPROVED, by, timezone.now()
    req.save(update_fields=["status", "decided_by", "decided_at"])
    return req


@transaction.atomic
def reject_request(req, *, reason: str, by):
    req = _pending(req)
    if not reason.strip():
        raise ValidationError("Give a reason.", field="reason")
    req.status, req.rejection_reason = LevelUpgradeRequest.Status.REJECTED, reason.strip()
    req.decided_by, req.decided_at = by, timezone.now()
    req.save(update_fields=["status", "rejection_reason", "decided_by", "decided_at"])
    return req


def requests_queryset(user, *, status=None, student=None, course=None):
    qs = LevelUpgradeRequest.objects.select_related(
        "student__user", "course", "from_level", "to_level", "requested_by", "decided_by"
    )
    if role_of(user) == "teacher":
        pairs = access.taught_pairs(user.pk)
        condition = Q(pk__in=[])
        for s, c in pairs:
            condition |= Q(student__user_id=s, course_id=c)
        qs = qs.filter(condition)
    elif not is_office(user):
        qs = qs.none()
    if status:
        qs = qs.filter(status=status)
    if student:
        qs = qs.filter(student__user_id=student)
    if course:
        qs = qs.filter(course_id=course)
    return qs


def get_request(user, request_id: int) -> LevelUpgradeRequest:
    req = requests_queryset(user).filter(pk=request_id).first()
    if req is None:
        raise NotFoundError("Level upgrade request", request_id)
    return req
```

> `approve_request` passes `by=None` to `set_level` so the office's approval is never refused by the teacher rule; `set_by` stays None on that row (the request records who decided).

Re-export the Produces names in `services/__init__.py`.

- [ ] **Step 4: Run** `uv run pytest etqan/learning -q` → PASS.
- [ ] **Step 5: Commit** — `git -C backend commit -am "feat(learning): level upgrade requests (B6a)"` (use explicit `git add etqan/learning` first).


---

### Task 6: API — levels and Qur'an chapters

**Files:**
- Create: `backend/etqan/learning/api/__init__.py` (empty), `api/serializers.py`, `api/views.py`, `api/urls.py`, `backend/etqan/learning/tests/test_api_levels.py`
- Modify: `backend/config/api_router.py` (under `# ── phase B6 ──`), `backend/etqan/access/tests/test_routes.py` (append a `# Phase B6, slice B6a` block to `ROUTES`, `FEATURES` and `FEATURE_WORDS`)

**Interfaces:**
- Consumes: Task 2 and Task 3 services.
- Produces: routes `levels/`, `levels/<int:pk>/`, `levels/reorder/`, `quran-chapters/`, `quran-chapters/<int:pk>/`, `quran-chapters/sync/` under `/api/v1/learning/`. Response shapes (the dashboard's `schemas.ts` in Task 9 mirrors them):
  - Level list item: `{id, course: {id, name_en, name_ar}, name_en, name_ar, position, is_active, sub_level_count, topic_count}`
  - Level detail: list item + `sub_levels: [{id, name_en, name_ar, topics: [{id, name_en, name_ar, chapter: int | null, from_verse, to_verse}]}]` (`chapter` = the chapter's **id**)
  - Chapter: `{id, number, name_arabic, name_simple, name_complex, revelation_place, revelation_order, verses_count, page_start, page_end}`
  - Sync: `{created, reset}`

- [ ] **Step 1: Write the failing API tests** — `backend/etqan/learning/tests/test_api_levels.py`

```python
from etqan.learning import services
from etqan.learning.models import Level

L = "/api/v1/learning/"


def _body(world, name="L1", **extra):
    return {
        "course": world.course.id,
        "name_ar": name,
        "name_en": name,
        "is_active": True,
        "sub_levels": [{"name_ar": "S", "name_en": "S", "topics": [{"name_ar": "T", "name_en": "T"}]}],
        **extra,
    }


def test_admin_creates_reads_updates_deletes(world, api_for):
    admin = api_for("admin")
    resp = admin.post(f"{L}levels/", _body(world), format="json")
    assert resp.status_code == 201, resp.content
    level = resp.json()
    assert level["course"] == {"id": world.course.id, "name_en": "Quran", "name_ar": "تحفيظ"}
    assert level["sub_levels"][0]["topics"][0]["name_en"] == "T"
    body = _body(world, "L1*") | {"sub_levels": level["sub_levels"]}
    resp = admin.put(f"{L}levels/{level['id']}/", body, format="json")
    assert resp.status_code == 200 and resp.json()["name_en"] == "L1*"
    listed = admin.get(f"{L}levels/", {"course": world.course.id}).json()
    assert [r["topic_count"] for r in listed["results"]] == [1]
    assert admin.delete(f"{L}levels/{level['id']}/").status_code == 204


def test_reorder_and_validation_errors(world, api_for):
    admin = api_for("admin")
    a = admin.post(f"{L}levels/", _body(world, "A"), format="json").json()
    b = admin.post(f"{L}levels/", _body(world, "B"), format="json").json()
    resp = admin.post(f"{L}levels/reorder/", {"course": world.course.id, "ids": [b["id"], a["id"]]}, format="json")
    assert resp.status_code == 204
    assert list(Level.objects.values_list("name_en", flat=True)) == ["B", "A"]
    resp = admin.post(f"{L}levels/", _body(world, course=999999), format="json")
    assert resp.status_code == 400 and "course" in resp.json()


def test_conflict_carries_its_code(world, api_for, make_level):
    from datetime import date

    from etqan.learning.models import StudentLevel

    level = make_level(world.course)
    StudentLevel.objects.create(student=world.student_profile, course=world.course, level=level, started_on=date(2026, 6, 1))
    resp = api_for("admin").delete(f"{L}levels/{level.id}/")
    assert resp.status_code == 409 and resp.json()["code"] == "learning.level_in_use"


def test_names_are_readable_by_people_not_writable(world, make_level, teacher_client, student_client, parent_client):
    level = make_level(world.course)
    for client in (teacher_client, student_client, parent_client):
        assert client.get(f"{L}levels/").status_code == 200
        assert client.get(f"{L}levels/{level.id}/").status_code == 200
        assert client.get(f"{L}quran-chapters/").status_code == 200
        assert client.post(f"{L}levels/", _body(world), format="json").status_code == 403


def test_staff_with_a_neighbouring_code_reads_names(world, staff_for):
    assert staff_for("student_level.view_any").get(f"{L}levels/").status_code == 200
    assert staff_for("level.create").get(f"{L}quran-chapters/").status_code == 200
    assert staff_for().get(f"{L}levels/").status_code == 403


def test_chapters_sync_list_edit(world, api_for):
    admin = api_for("admin")
    assert admin.post(f"{L}quran-chapters/sync/").json() == {"created": 114, "reset": 0}
    chapters = admin.get(f"{L}quran-chapters/").json()
    assert len(chapters) == 114 and chapters[0]["name_simple"] == "Al-Fatihah"
    resp = admin.patch(
        f"{L}quran-chapters/{chapters[0]['id']}/",
        {"name_arabic": "الفاتحة", "name_simple": "Fatiha", "name_complex": "Fatiha", "verses_count": 99},
        format="json",
    )
    assert resp.status_code == 200
    assert (resp.json()["name_simple"], resp.json()["verses_count"]) == ("Fatiha", 7)


def test_switches_off_hide_routes(world, api_for, set_features):
    set_features(levels=False, quran_chapters=False)
    admin = api_for("admin")
    assert admin.get(f"{L}levels/").status_code == 404
    assert admin.get(f"{L}quran-chapters/").status_code == 404
    services.sync_chapters()  # data stays (FT-4)
```

- [ ] **Step 2: Run to verify failure** (404s: no routes).

- [ ] **Step 3: Serializers** — `backend/etqan/learning/api/serializers.py`

```python
from rest_framework import serializers

from etqan.learning.models import Level
from etqan.learning.models import QuranChapter


def course_ref(course) -> dict:
    return {"id": course.pk, "name_en": course.name_en, "name_ar": course.name_ar}


class TopicInput(serializers.Serializer):
    id = serializers.IntegerField(required=False, min_value=1)
    name_ar = serializers.CharField(max_length=200)
    name_en = serializers.CharField(max_length=200)
    chapter = serializers.IntegerField(required=False, allow_null=True, min_value=1)
    from_verse = serializers.IntegerField(required=False, allow_null=True, min_value=1)
    to_verse = serializers.IntegerField(required=False, allow_null=True, min_value=1)


class SubLevelInput(serializers.Serializer):
    id = serializers.IntegerField(required=False, min_value=1)
    name_ar = serializers.CharField(max_length=120)
    name_en = serializers.CharField(max_length=120)
    topics = TopicInput(many=True, required=False, default=list)


class LevelInput(serializers.Serializer):
    course = serializers.IntegerField(min_value=1)
    name_ar = serializers.CharField(max_length=120)
    name_en = serializers.CharField(max_length=120)
    is_active = serializers.BooleanField(required=False, default=True)
    sub_levels = SubLevelInput(many=True, required=False, default=list)


class ReorderInput(serializers.Serializer):
    course = serializers.IntegerField(min_value=1)
    ids = serializers.ListField(child=serializers.IntegerField(min_value=1), max_length=500)


class LevelSerializer(serializers.ModelSerializer):
    course = serializers.SerializerMethodField()
    sub_level_count = serializers.IntegerField(read_only=True)
    topic_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = Level
        fields = ("id", "course", "name_en", "name_ar", "position", "is_active", "sub_level_count", "topic_count")

    def get_course(self, obj) -> dict:
        return course_ref(obj.course)


class LevelDetailSerializer(LevelSerializer):
    sub_levels = serializers.SerializerMethodField()

    class Meta(LevelSerializer.Meta):
        fields = (*LevelSerializer.Meta.fields, "sub_levels")

    def get_sub_levels(self, obj) -> list[dict]:
        return [
            {
                "id": s.pk,
                "name_en": s.name_en,
                "name_ar": s.name_ar,
                "topics": [
                    {
                        "id": t.pk,
                        "name_en": t.name_en,
                        "name_ar": t.name_ar,
                        "chapter": t.chapter_id,
                        "from_verse": t.from_verse,
                        "to_verse": t.to_verse,
                    }
                    for t in s.topics.all()
                ],
            }
            for s in obj.sub_levels.all()
        ]


class ChapterSerializer(serializers.ModelSerializer):
    class Meta:
        model = QuranChapter
        fields = (
            "id", "number", "name_arabic", "name_simple", "name_complex",
            "revelation_place", "revelation_order", "verses_count", "page_start", "page_end",
        )


class ChapterNamesInput(serializers.Serializer):
    name_arabic = serializers.CharField(max_length=60)
    name_simple = serializers.CharField(max_length=60)
    name_complex = serializers.CharField(max_length=60)
```

- [ ] **Step 4: Views** — `backend/etqan/learning/api/views.py` (levels + chapters part; Task 7 appends the rest)

```python
from django.http import Http404
from rest_framework import generics
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.learning import services
from etqan.learning.api import serializers as s
from etqan.learning.models import QuranChapter
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.platform.permissions import IsTeacher
from etqan.platform.permissions import ReadOnly
from etqan.platform.permissions import ReadsOwn

# C-14: names are readable by teachers, students and parents; staff by code.
NAMES = [HasCode | (ReadOnly & ReadsOwn), FeatureOn]
OFFICE = [HasCode, FeatureOn]
LEVEL_NAME_CODES = ("level.view_any", "student_level.view_any", "level_upgrade_request.view_any")


class LevelListView(generics.ListAPIView):
    feature = "levels"
    serializer_class = s.LevelSerializer
    permission_classes = NAMES  # ReadOnly: people read; writes need a code
    permission_codes = {"GET": LEVEL_NAME_CODES, "POST": "level.create"}

    def get_queryset(self):
        qs = services.levels_queryset()
        course = self.request.query_params.get("course", "")
        return qs.filter(course_id=int(course)) if course.isdigit() else qs

    def post(self, request):
        data = s.LevelInput(data=request.data)
        data.is_valid(raise_exception=True)
        v = data.validated_data
        level = services.create_level(
            course_id=v["course"], name_ar=v["name_ar"], name_en=v["name_en"],
            is_active=v["is_active"], sub_levels=v["sub_levels"],
        )
        return Response(s.LevelDetailSerializer(level).data, status=status.HTTP_201_CREATED)


class LevelDetailView(APIView):
    feature = "levels"
    permission_classes = NAMES
    permission_codes = {"GET": "level.view", "PUT": "level.update", "DELETE": "level.delete"}

    def get(self, request, pk):
        return Response(s.LevelDetailSerializer(services.get_level(pk)).data)

    def put(self, request, pk):
        level = services.get_level(pk)
        data = s.LevelInput(data=request.data)
        data.is_valid(raise_exception=True)
        v = data.validated_data
        level = services.update_level(
            level, name_ar=v["name_ar"], name_en=v["name_en"], is_active=v["is_active"],
            sub_levels=v["sub_levels"], course_id=v["course"],
        )
        return Response(s.LevelDetailSerializer(level).data)

    def delete(self, request, pk):
        services.delete_level(services.get_level(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class LevelReorderView(APIView):
    permission_classes = OFFICE
    permission_codes = {"POST": "level.reorder"}
    feature = "levels"

    def post(self, request):
        data = s.ReorderInput(data=request.data)
        data.is_valid(raise_exception=True)
        services.reorder_levels(course_id=data.validated_data["course"], ids=data.validated_data["ids"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class ChapterListView(APIView):
    permission_classes = NAMES
    permission_codes = {"GET": ("quran_chapter.view_any", "level.create", "level.update")}
    feature = "quran_chapters"

    def get(self, request):
        return Response(s.ChapterSerializer(services.chapters(), many=True).data)


class ChapterDetailView(APIView):
    permission_classes = OFFICE
    permission_codes = {"PATCH": "quran_chapter.update"}
    feature = "quran_chapters"

    def patch(self, request, pk):
        chapter = QuranChapter.objects.filter(pk=pk).first()
        if chapter is None:
            raise Http404
        data = s.ChapterNamesInput(data=request.data)
        data.is_valid(raise_exception=True)
        chapter = services.update_chapter(chapter, **data.validated_data)
        return Response(s.ChapterSerializer(chapter).data)


class ChapterSyncView(APIView):
    permission_classes = OFFICE
    permission_codes = {"POST": "quran_chapter.create"}
    feature = "quran_chapters"

    def post(self, request):
        result = services.sync_chapters()
        return Response({"created": result.created, "reset": result.reset})
```

> `ReadOnly & ReadsOwn` passes teachers, students and parents on GET only, so one permission list serves reads and office writes alike; `test_routes` reads `permission_classes` to check `FeatureOn` is listed.

- [ ] **Step 5: URLs** — `backend/etqan/learning/api/urls.py`

```python
from django.urls import path

from etqan.learning.api import views

urlpatterns = [
    path("levels/", views.LevelListView.as_view()),
    path("levels/reorder/", views.LevelReorderView.as_view()),
    path("levels/<int:pk>/", views.LevelDetailView.as_view()),
    path("quran-chapters/", views.ChapterListView.as_view()),
    path("quran-chapters/sync/", views.ChapterSyncView.as_view()),
    path("quran-chapters/<int:pk>/", views.ChapterDetailView.as_view()),
]
```

`backend/config/api_router.py`, under `# ── phase B6 ──`:

```python
    path("learning/", include("etqan.learning.api.urls")),
```

- [ ] **Step 6: Access route tables** — append to `backend/etqan/access/tests/test_routes.py`

In `ROUTES` (before the closing `]`):

```python
    # Phase B6, slice B6a: curriculum.
    ("GET", "/api/v1/learning/levels/", ("level.view_any", "student_level.view_any", "level_upgrade_request.view_any")),
    ("POST", "/api/v1/learning/levels/", "level.create"),
    ("POST", "/api/v1/learning/levels/reorder/", "level.reorder"),
    ("GET", f"/api/v1/learning/levels/{N}/", "level.view"),
    ("PUT", f"/api/v1/learning/levels/{N}/", "level.update"),
    ("DELETE", f"/api/v1/learning/levels/{N}/", "level.delete"),
    ("GET", "/api/v1/learning/quran-chapters/", ("quran_chapter.view_any", "level.create", "level.update")),
    ("PATCH", f"/api/v1/learning/quran-chapters/{N}/", "quran_chapter.update"),
    ("POST", "/api/v1/learning/quran-chapters/sync/", "quran_chapter.create"),
```

In `FEATURES` (before the closing `}`):

```python
    # Phase B6, slice B6a
    **dict.fromkeys(
        (
            ("GET", "/api/v1/learning/levels/"),
            ("POST", "/api/v1/learning/levels/"),
            ("POST", "/api/v1/learning/levels/reorder/"),
            ("GET", f"/api/v1/learning/levels/{N}/"),
            ("PUT", f"/api/v1/learning/levels/{N}/"),
            ("DELETE", f"/api/v1/learning/levels/{N}/"),
        ),
        "levels",
    ),
    **dict.fromkeys(
        (
            ("GET", "/api/v1/learning/quran-chapters/"),
            ("PATCH", f"/api/v1/learning/quran-chapters/{N}/"),
            ("POST", "/api/v1/learning/quran-chapters/sync/"),
        ),
        "quran_chapters",
    ),
```

In `FEATURE_WORDS`:

```python
    "/learning/levels/": "levels",  # B6a
    "/quran-chapters/": "quran_chapters",  # B6a
```

> `POST levels/reorder/` with `{}` from a staff without the code → 403 (good); with the code → 400 (not 403, good). `PUT levels/{N}/` with `{}` from an admin → 404 or 400; both are fine for the "is there" test.

- [ ] **Step 7: Run** — `uv run pytest etqan/learning etqan/access -q`. Expected: learning PASS; `test_every_code_in_the_table_is_in_the_registry_and_in_use` still FAILS only because `student_level.*` and `level_upgrade_request.*` routes come in Task 7 — confirm that is the only failure (`-k in_use`).
- [ ] **Step 8: Commit** — `git -C backend add etqan/learning config/api_router.py etqan/access/tests/test_routes.py && git -C backend commit -m "feat(learning): levels and Qur'an chapters API (B6a)"`.

---

### Task 7: API — student levels, progress and upgrade requests

**Files:**
- Modify: `backend/etqan/learning/api/serializers.py`, `api/views.py`, `api/urls.py`, `backend/etqan/access/tests/test_routes.py`
- Create: `backend/etqan/learning/tests/test_api_progress.py`

**Interfaces:**
- Consumes: Task 4 and Task 5 services.
- Produces routes (all `levels` feature):
  - `GET student-levels/?course=&level=&no_level=1&search=&page=` → paginated `{count, next, previous, results: [LevelRow as dict, since ISO date or null]}`
  - `GET students/<int:student_id>/progress/` → `progress_summary` list
  - `GET students/<int:student_id>/progress/<int:course_id>/` → `progress` dict
  - `PUT students/<int:student_id>/progress/<int:course_id>/level/` body `{level}` → the new `progress` dict
  - `PUT|DELETE students/<int:student_id>/progress/<int:course_id>/topics/<int:topic_id>/` body `{completed_on?}` → `progress` dict (PUT 200) / 204
  - `GET level-upgrades/?status=&student=&course=&page=` → paginated request items `{id, student: {id, full_name}, course: {id, name_en, name_ar}, from_level: {id, name_en, name_ar}, to_level: {…}, note, status, rejection_reason, requested_by: {id, full_name} | null, decided_by: … | null, decided_at, created_at, subscription: int | null}`
  - `POST level-upgrades/` body `{student, course, subscription?, note?}` → 201 request item
  - `POST level-upgrades/<int:pk>/approve/` → 200 item; `POST level-upgrades/<int:pk>/reject/` body `{reason}` → 200 item

- [ ] **Step 1: Write the failing tests** — `backend/etqan/learning/tests/test_api_progress.py`

```python
import pytest

from etqan.learning import services
from etqan.learning.models import Topic

L = "/api/v1/learning/"


@pytest.fixture
def ladder(world, make_level, subscribe):
    subscribe()
    return make_level(world.course, "L1"), make_level(world.course, "L2")


def _p(world, course=None):
    return f"{L}students/{world.student.id}/progress/{(course or world.course).id}/"


def test_office_list_shows_rows_without_level(world, ladder, api_for):
    resp = api_for("admin").get(f"{L}student-levels/", {"no_level": "1"})
    assert resp.status_code == 200
    (row,) = resp.json()["results"]
    assert (row["student_id"], row["level_id"], row["since"]) == (world.student.id, None, None)


def test_teacher_sets_first_level_ticks_and_asks(world, ladder, teacher_client, api_for):
    low, high = ladder
    resp = teacher_client.put(f"{_p(world)}level/", {"level": low.id}, format="json")
    assert resp.status_code == 200 and resp.json()["current"]["level_id"] == low.id
    resp = teacher_client.put(f"{_p(world)}level/", {"level": high.id}, format="json")
    assert resp.status_code == 409 and resp.json()["code"] == "learning.level_already_set"
    topic = Topic.objects.filter(sub_level__level=low).first()
    assert teacher_client.put(f"{_p(world)}topics/{topic.id}/", {}, format="json").status_code == 200
    resp = teacher_client.post(
        f"{L}level-upgrades/", {"student": world.student.id, "course": world.course.id, "note": "ok"}, format="json"
    )
    assert resp.status_code == 201
    req = resp.json()
    assert teacher_client.post(f"{L}level-upgrades/{req['id']}/approve/").status_code == 403
    admin = api_for("admin")
    resp = admin.post(f"{L}level-upgrades/{req['id']}/approve/")
    assert resp.status_code == 200 and resp.json()["status"] == "approved"
    assert teacher_client.delete(f"{_p(world)}topics/{topic.id}/").status_code == 204


def test_teacher_sees_only_taught_course(world, ladder, make_level, subscribe, teacher_client):
    low, _ = ladder
    subscribe(course=world.course_b, teacher=world.other_teacher)
    b = make_level(world.course_b, "B1")
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=low.id, by=None)
    services.set_level(student_user_id=world.student.id, course_id=world.course_b.id, level_id=b.id, by=None)
    summary = teacher_client.get(f"{L}students/{world.student.id}/progress/").json()
    assert [c["course_id"] for c in summary] == [world.course.id]
    assert teacher_client.get(_p(world, world.course_b)).status_code == 404
    assert teacher_client.put(f"{_p(world, world.course_b)}level/", {"level": b.id}, format="json").status_code == 404
    rows = teacher_client.get(f"{L}student-levels/").json()["results"]
    assert [r["course_id"] for r in rows] == [world.course.id]


def test_student_and_parent_read_only(world, ladder, student_client, parent_client, api_for):
    low, _ = ladder
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=low.id, by=None)
    for client in (student_client, parent_client):
        assert client.get(_p(world)).status_code == 200
        assert client.get(f"{L}students/{world.student.id}/progress/").status_code == 200
        assert client.put(f"{_p(world)}level/", {"level": low.id}, format="json").status_code == 403
        assert client.get(f"{L}student-levels/").status_code == 403
        assert client.get(f"{L}level-upgrades/").status_code == 403
    other = api_for("student")
    assert other.get(_p(world)).status_code == 404


def test_teacher_not_teaching_gets_404_and_400(world, ladder, api_for):
    from etqan.scheduling.tests.conftest import as_user

    low, _ = ladder
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=low.id, by=None)
    stranger = as_user(world.other_teacher)
    assert stranger.get(_p(world)).status_code == 404
    resp = stranger.post(f"{L}level-upgrades/", {"student": world.student.id, "course": world.course.id}, format="json")
    assert resp.status_code == 400 and "student" in resp.json()


def test_staff_codes(world, ladder, staff_for):
    assert staff_for("student_level.view_any").get(f"{L}student-levels/").status_code == 200
    assert staff_for("student_level.view").get(_p(world)).status_code == 200
    assert staff_for("student_level.view_any").get(_p(world)).status_code == 403
    assert staff_for().get(_p(world)).status_code == 403


def test_reject_needs_reason(world, ladder, api_for):
    low, _ = ladder
    services.set_level(student_user_id=world.student.id, course_id=world.course.id, level_id=low.id, by=None)
    admin = api_for("admin")
    req = admin.post(f"{L}level-upgrades/", {"student": world.student.id, "course": world.course.id}, format="json").json()
    assert admin.post(f"{L}level-upgrades/{req['id']}/reject/", {"reason": ""}, format="json").status_code == 400
    resp = admin.post(f"{L}level-upgrades/{req['id']}/reject/", {"reason": "Later"}, format="json")
    assert resp.json()["status"] == "rejected"
    pending = admin.get(f"{L}level-upgrades/", {"status": "pending"}).json()
    assert pending["count"] == 0


def test_switch_off_is_404_for_allowed_callers(world, ladder, set_features, teacher_client, student_client):
    set_features(levels=False)
    assert teacher_client.get(f"{L}student-levels/").status_code == 404
    assert student_client.get(_p(world)).status_code == 404
    assert student_client.put(f"{_p(world)}level/", {"level": 1}, format="json").status_code == 403
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Serializers** — append to `api/serializers.py`

```python
def person_ref(user) -> dict | None:
    return None if user is None else {"id": user.pk, "full_name": user.full_name}


def level_ref(level) -> dict:
    return {"id": level.pk, "name_en": level.name_en, "name_ar": level.name_ar}


class SetLevelInput(serializers.Serializer):
    level = serializers.IntegerField(min_value=1)


class CompleteInput(serializers.Serializer):
    completed_on = serializers.DateField(required=False, allow_null=True)


class UpgradeInput(serializers.Serializer):
    student = serializers.IntegerField(min_value=1)
    course = serializers.IntegerField(min_value=1)
    subscription = serializers.IntegerField(required=False, allow_null=True, min_value=1)
    note = serializers.CharField(required=False, allow_blank=True, max_length=2000, default="")


class RejectInput(serializers.Serializer):
    reason = serializers.CharField(allow_blank=True, max_length=2000)


def upgrade_data(req) -> dict:
    return {
        "id": req.pk,
        "student": person_ref(req.student.user),
        "course": course_ref(req.course),
        "subscription": req.subscription_id,
        "from_level": level_ref(req.from_level),
        "to_level": level_ref(req.to_level),
        "note": req.note,
        "status": req.status,
        "rejection_reason": req.rejection_reason,
        "requested_by": person_ref(req.requested_by),
        "decided_by": person_ref(req.decided_by),
        "decided_at": req.decided_at,
        "created_at": req.created_at,
    }
```

- [ ] **Step 4: Views** — append to `api/views.py`

```python
from dataclasses import asdict

from django.http import Http404
from rest_framework.pagination import PageNumberPagination

from etqan.platform.exceptions import NotFoundError
from etqan.platform.pagination import StandardPagination
from etqan.platform.permissions import role_of

PEOPLE = [HasCode | (ReadOnly & ReadsOwn), FeatureOn]
TEACHER_READS = [HasCode | (ReadOnly & IsTeacher), FeatureOn]
TEACHER_WRITES = [HasCode | IsTeacher, FeatureOn]


def _scope(request, student_id, course_id=None):
    """§8.3: the courses the caller may read; 404 outside them."""
    try:
        courses = services.progress_scope(request.user, student_id)
    except NotFoundError:
        raise Http404 from None
    if course_id is not None and courses is not None and course_id not in courses:
        raise Http404
    return courses


def _teacher_must_teach(request, student_id, course_id):
    if role_of(request.user) == "teacher" and not services.teaches(request.user.pk, student_id, course_id):
        raise Http404


class StudentLevelListView(APIView):
    permission_classes = TEACHER_READS
    permission_codes = {"GET": "student_level.view_any"}
    feature = "levels"

    def get(self, request):
        p = request.query_params

        def num(key):
            value = p.get(key, "")
            return int(value) if value.isdigit() else None

        rows = services.level_rows(
            request.user,
            course=num("course"),
            level=num("level"),
            no_level=p.get("no_level") in ("1", "true"),
            search=p.get("search", "").strip(),
        )
        paginator = StandardPagination()
        page = paginator.paginate_queryset([asdict(r) for r in rows], request, view=self)
        return paginator.get_paginated_response(page)


class ProgressSummaryView(APIView):
    permission_classes = PEOPLE
    permission_codes = {"GET": "student_level.view"}
    feature = "levels"

    def get(self, request, student_id):
        courses = _scope(request, student_id)
        return Response(services.progress_summary(student_id, course_ids=courses))


class ProgressDetailView(APIView):
    permission_classes = PEOPLE
    permission_codes = {"GET": "student_level.view"}
    feature = "levels"

    def get(self, request, student_id, course_id):
        _scope(request, student_id, course_id)
        return Response(services.progress(student_id, course_id))


class SetLevelView(APIView):
    permission_classes = TEACHER_WRITES
    permission_codes = {"PUT": "student_level.update"}
    feature = "levels"

    def put(self, request, student_id, course_id):
        _teacher_must_teach(request, student_id, course_id)
        data = s.SetLevelInput(data=request.data)
        data.is_valid(raise_exception=True)
        services.set_level(
            student_user_id=student_id, course_id=course_id,
            level_id=data.validated_data["level"], by=request.user,
        )
        return Response(services.progress(student_id, course_id))


class TopicCompletionView(APIView):
    permission_classes = TEACHER_WRITES
    permission_codes = {"PUT": "student_level.update", "DELETE": "student_level.update"}
    feature = "levels"

    def put(self, request, student_id, course_id, topic_id):
        _teacher_must_teach(request, student_id, course_id)
        data = s.CompleteInput(data=request.data)
        data.is_valid(raise_exception=True)
        services.complete_topic(
            student_user_id=student_id, course_id=course_id, topic_id=topic_id,
            completed_on=data.validated_data.get("completed_on"), by=request.user,
        )
        return Response(services.progress(student_id, course_id))

    def delete(self, request, student_id, course_id, topic_id):
        _teacher_must_teach(request, student_id, course_id)
        services.uncomplete_topic(
            student_user_id=student_id, course_id=course_id, topic_id=topic_id, by=request.user
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class UpgradeListView(APIView):
    feature = "levels"
    permission_codes = {"GET": "level_upgrade_request.view_any", "POST": "level_upgrade_request.create"}
    permission_classes = TEACHER_WRITES  # GET for a teacher is scoped by requests_queryset

    def get(self, request):
        p = request.query_params
        qs = services.requests_queryset(
            request.user,
            status=p.get("status") or None,
            student=int(p["student"]) if p.get("student", "").isdigit() else None,
            course=int(p["course"]) if p.get("course", "").isdigit() else None,
        )
        paginator = StandardPagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        return paginator.get_paginated_response([s.upgrade_data(r) for r in page])

    def post(self, request):
        data = s.UpgradeInput(data=request.data)
        data.is_valid(raise_exception=True)
        v = data.validated_data
        req = services.request_upgrade(
            student_user_id=v["student"], course_id=v["course"],
            subscription_id=v.get("subscription"), note=v["note"], by=request.user,
        )
        return Response(s.upgrade_data(services.get_request(request.user, req.pk)), status=status.HTTP_201_CREATED)


class UpgradeApproveView(APIView):
    permission_classes = OFFICE
    permission_codes = {"POST": "level_upgrade_request.update"}
    feature = "levels"

    def post(self, request, pk):
        req = services.approve_request(services.get_request(request.user, pk), by=request.user)
        return Response(s.upgrade_data(services.get_request(request.user, req.pk)))


class UpgradeRejectView(APIView):
    permission_classes = OFFICE
    permission_codes = {"POST": "level_upgrade_request.update"}
    feature = "levels"

    def post(self, request, pk):
        req = services.get_request(request.user, pk)
        data = s.RejectInput(data=request.data)
        data.is_valid(raise_exception=True)
        req = services.reject_request(req, reason=data.validated_data["reason"], by=request.user)
        return Response(s.upgrade_data(services.get_request(request.user, req.pk)))
```

> Move the new imports to the top of `views.py` (ruff `E402`). `services.get_request` raises `NotFoundError`, which the platform handler maps to 404. Drop the unused `PageNumberPagination` import.

- [ ] **Step 5: URLs** — append to `urlpatterns` in `api/urls.py`

```python
    path("student-levels/", views.StudentLevelListView.as_view()),
    path("students/<int:student_id>/progress/", views.ProgressSummaryView.as_view()),
    path("students/<int:student_id>/progress/<int:course_id>/", views.ProgressDetailView.as_view()),
    path("students/<int:student_id>/progress/<int:course_id>/level/", views.SetLevelView.as_view()),
    path(
        "students/<int:student_id>/progress/<int:course_id>/topics/<int:topic_id>/",
        views.TopicCompletionView.as_view(),
    ),
    path("level-upgrades/", views.UpgradeListView.as_view()),
    path("level-upgrades/<int:pk>/approve/", views.UpgradeApproveView.as_view()),
    path("level-upgrades/<int:pk>/reject/", views.UpgradeRejectView.as_view()),
```

- [ ] **Step 6: Access route tables** — extend the B6a blocks in `test_routes.py`

`ROUTES`:

```python
    ("GET", "/api/v1/learning/student-levels/", "student_level.view_any"),
    ("GET", f"/api/v1/learning/students/{N}/progress/", "student_level.view"),
    ("GET", f"/api/v1/learning/students/{N}/progress/{N}/", "student_level.view"),
    ("PUT", f"/api/v1/learning/students/{N}/progress/{N}/level/", "student_level.update"),
    ("PUT", f"/api/v1/learning/students/{N}/progress/{N}/topics/{N}/", "student_level.update"),
    ("DELETE", f"/api/v1/learning/students/{N}/progress/{N}/topics/{N}/", "student_level.update"),
    ("GET", "/api/v1/learning/level-upgrades/", "level_upgrade_request.view_any"),
    ("POST", "/api/v1/learning/level-upgrades/", "level_upgrade_request.create"),
    ("POST", f"/api/v1/learning/level-upgrades/{N}/approve/", "level_upgrade_request.update"),
    ("POST", f"/api/v1/learning/level-upgrades/{N}/reject/", "level_upgrade_request.update"),
```

`FEATURES` — a third `dict.fromkeys(…, "levels")` with those ten keys. `FEATURE_WORDS`:

```python
    "/student-levels/": "levels",  # B6a
    "/progress/": "levels",  # B6a
    "/level-upgrades/": "levels",  # B6a
```

> Check no existing route path contains `/progress/`; if one does, use `"/learning/students/"` instead.

- [ ] **Step 7: Full backend suite** — `just test-backend` (or `cd backend && uv run pytest -q`), `cd backend && uv run lint-imports`, `uv run ruff check . && uv run ruff format --check .`. Expected: all green, including `test_every_code_in_the_table_is_in_the_registry_and_in_use`; learning coverage ≥ 80 % (`uv run pytest etqan/learning --cov=etqan.learning --cov-report=term-missing`).
- [ ] **Step 8: Commit** — `git -C backend add etqan/learning etqan/access/tests/test_routes.py && git -C backend commit -m "feat(learning): student levels, progress and upgrade API (B6a)"`.

---

### Task 8: Demo seed

**Files:**
- Create: `backend/etqan/tenants/seeds/b6.py`, `backend/etqan/tenants/tests/test_seed_b6.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (import + one call under `# ── phase B6 ──` in `seed_academy`)

**Interfaces:**
- Consumes: `learning.services` (`sync_chapters`, `create_level`, `set_level`, `complete_topic`, `request_upgrade`, `levels_queryset`), `catalogue.services.find_course`, `identity.services.get_user_by_email`.
- Produces: `seed_b6(subdomain: str) -> None` — demo only, idempotent.

- [ ] **Step 1: Write the failing test** — `backend/etqan/tenants/tests/test_seed_b6.py`

```python
from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.learning.models import Level
from etqan.learning.models import LevelUpgradeRequest
from etqan.learning.models import QuranChapter
from etqan.learning.models import StudentLevel
from etqan.tenants.seeds.b6 import seed_b6


def _demo_people():
    teacher = identity_services.create_person(
        "teacher", full_name="Ustadha Maryam", email="maryam@demo.test", profile={"gender": "female"}
    )
    catalogue_services.create_course(name_ar="تحفيظ", name_en="Quran Memorisation", teacher_ids=[teacher.id])
    catalogue_services.create_course(name_ar="تجويد", name_en="Tajweed", teacher_ids=[teacher.id])
    identity_services.create_person("student", full_name="Yusuf Omar", email="yusuf@demo.test")
    identity_services.create_person("student", full_name="Zaid Huda", email="zaid@demo.test")


def test_seed_is_demo_only_and_idempotent():
    seed_b6("other")
    assert not QuranChapter.objects.exists()
    _demo_people()
    seed_b6("demo")
    seed_b6("demo")
    assert QuranChapter.objects.count() == 114
    assert Level.objects.filter(course__name_en="Quran Memorisation").count() == 3
    assert Level.objects.filter(course__name_en="Tajweed").count() == 1
    assert StudentLevel.objects.filter(ended_on__isnull=True).count() == 2
    assert LevelUpgradeRequest.objects.filter(status="pending").count() == 1


def test_seed_skips_levels_without_the_quran_course():
    seed_b6("demo")
    assert QuranChapter.objects.count() == 114
    assert not Level.objects.exists()
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** — `backend/etqan/tenants/seeds/b6.py`

```python
"""Phase B6 demo data (slice B6a): Qur'an chapters, a level ladder for the
Qur'an course, two students' levels and one pending upgrade request. Demo
academy only; idempotent; the switches stay off."""

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.learning import services as learning
from etqan.platform.exceptions import NotFoundError

QURAN = "Quran Memorisation"
OTHER = "Tajweed"
# (name_en, name_ar, [(sub-level en, ar, [(chapter number, from, to)])])
LADDER = (
    ("Juz' Amma", "جزء عمّ", (("Short surahs", "قصار السور", ((114, None, None), (113, None, None), (112, None, None))), ("An-Naba'", "النبأ", ((78, 1, 20), (78, 21, 40))))),
    ("Juz' Tabarak", "جزء تبارك", (("Al-Mulk", "الملك", ((67, 1, 15), (67, 16, 30))), ("Al-Qalam", "القلم", ((68, None, None),)))),
    ("Al-Baqarah", "البقرة", (("Opening", "البداية", ((2, 1, 20), (2, 21, 40))), ("Ayat al-Kursi", "آية الكرسي", ((2, 255, 257),)))),
)


def _student(email):
    try:
        return identity_services.get_user_by_email(email)
    except NotFoundError:
        return None


def _topics(rows):
    by_number = {c.number: c for c in learning.chapters()}
    topics = []
    for number, first, last in rows:
        chapter = by_number[number]
        suffix = f" {first}–{last}" if first else ""
        topics.append(
            {
                "name_en": f"{chapter.name_simple}{suffix}",
                "name_ar": f"{chapter.name_arabic}{suffix}",
                "chapter": chapter.pk,
                "from_verse": first,
                "to_verse": last,
            }
        )
    return topics


def seed_b6(subdomain: str) -> None:
    """Run inside the academy's schema."""
    if subdomain != "demo":
        return
    learning.sync_chapters()
    quran = catalogue_services.find_course(QURAN)
    if quran is None or learning.levels_queryset().filter(course=quran).exists():
        return
    levels = [
        learning.create_level(
            course_id=quran.pk,
            name_en=en,
            name_ar=ar,
            sub_levels=[{"name_en": s_en, "name_ar": s_ar, "topics": _topics(rows)} for s_en, s_ar, rows in subs],
        )
        for en, ar, subs in LADDER
    ]
    other = catalogue_services.find_course(OTHER)
    if other is not None:
        learning.create_level(
            course_id=other.pk, name_en="Foundations", name_ar="الأساسيات",
            sub_levels=[{"name_en": "Makharij", "name_ar": "المخارج", "topics": [
                {"name_en": "Throat letters", "name_ar": "حروف الحلق"},
                {"name_en": "Tongue letters", "name_ar": "حروف اللسان"},
            ]}],
        )
    yusuf, zaid = _student("yusuf@demo.test"), _student("zaid@demo.test")
    for student, level in ((yusuf, levels[0]), (zaid, levels[1])):
        if student is None:
            continue
        learning.set_level(student_user_id=student.pk, course_id=quran.pk, level_id=level.pk, by=None)
        first_topics = level.sub_levels.first().topics.all()[:2]
        for topic in first_topics:
            learning.complete_topic(student_user_id=student.pk, course_id=quran.pk, topic_id=topic.pk, by=None)
    if yusuf is not None:
        learning.request_upgrade(student_user_id=yusuf.pk, course_id=quran.pk, note="Finished Juz' Amma revision", by=None)
```

> Chapter names with `ʿ` etc. come from the data file as-is. The second run returns early at `levels_queryset().filter(course=quran).exists()`, so nothing doubles. `find_course(name_en)` exists in `catalogue/services.py:117`.

`seed_dev.py`: add `from etqan.tenants.seeds.b6 import seed_b6` beside the other seed imports, and under `# ── phase B6 ──` in `seed_academy`: `        seed_b6(subdomain)`.

- [ ] **Step 4: Run** — `uv run pytest etqan/tenants/tests/test_seed_b6.py -q` → PASS; then `just seed` against the stream stack and confirm no error.
- [ ] **Step 5: Commit** — `git -C backend add etqan/tenants && git -C backend commit -m "feat(learning): demo seed for curriculum (B6a)"`.

---

### Task 9: Dashboard — curriculum data layer, switches and translations

**Files:**
- Create: `dashboard/src/features/curriculum/schemas.ts`, `api.ts`, `queries.ts`, `fixtures.ts`, `errors.ts`, `index.ts`, `api.test.ts`, `errors.test.ts`; `dashboard/src/locales/en/curriculum.json`, `dashboard/src/locales/ar/curriculum.json`
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode`: add a `// Phase B6, slice B6a.` group with `"levels"` and `"quran_chapters"`)

**Interfaces:**
- Consumes: the API of Tasks 6–7 (shapes listed there).
- Produces (all exported from `@/features/curriculum`):
  - types `LevelSummary`, `LevelDetail`, `SubLevelInput`, `TopicInput`, `LevelInput`, `Chapter`, `LevelRow`, `Progress`, `ProgressSummary`, `Upgrade`, `UpgradeStatus`, `Paginated<T>`
  - `curriculumApi` with `levels(params)`, `level(id)`, `createLevel(body)`, `updateLevel(id, body)`, `deleteLevel(id)`, `reorderLevels(course, ids)`, `chapters()`, `updateChapter(id, names)`, `syncChapters()`, `studentLevels(params)`, `summary(studentId)`, `progress(studentId, courseId)`, `setLevel(studentId, courseId, level)`, `completeTopic(studentId, courseId, topicId, completedOn?)`, `uncompleteTopic(studentId, courseId, topicId)`, `upgrades(params)`, `requestUpgrade(body)`, `approveUpgrade(id)`, `rejectUpgrade(id, reason)`
  - hooks `useLevels`, `useLevel`, `useSaveLevel`, `useDeleteLevel`, `useReorderLevels`, `useChapters`, `useUpdateChapter`, `useSyncChapters`, `useStudentLevels`, `useProgressSummary`, `useProgress`, `useSetLevel`, `useToggleTopic`, `useUpgrades`, `useRequestUpgrade`, `useDecideUpgrade`
  - `curriculumErrorText(error, t): string`
  - query keys under `["curriculum", …]`; every mutation invalidates `["curriculum"]`.

- [ ] **Step 1: Write the failing tests** — `dashboard/src/features/curriculum/api.test.ts`

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { curriculumApi } from "./api";

vi.mock("@/lib/api", () => ({
	api: { get: vi.fn(), post: vi.fn(), put: vi.fn(), patch: vi.fn(), delete: vi.fn() },
}));

describe("curriculumApi", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(api.get).mockResolvedValue({ data: { ok: true } });
		vi.mocked(api.put).mockResolvedValue({ data: { ok: true } });
		vi.mocked(api.post).mockResolvedValue({ data: { ok: true } });
	});

	it("addresses students by user id under learning/", async () => {
		await curriculumApi.progress(7, 3);
		expect(api.get).toHaveBeenCalledWith("learning/students/7/progress/3/");
		await curriculumApi.completeTopic(7, 3, 11, "2026-06-01");
		expect(api.put).toHaveBeenCalledWith(
			"learning/students/7/progress/3/topics/11/",
			{ completed_on: "2026-06-01" },
		);
		await curriculumApi.setLevel(7, 3, 5);
		expect(api.put).toHaveBeenCalledWith("learning/students/7/progress/3/level/", { level: 5 });
	});

	it("drops empty filters from list params", async () => {
		await curriculumApi.studentLevels({ course: undefined, noLevel: true, search: "", page: 2 });
		expect(api.get).toHaveBeenCalledWith("learning/student-levels/", {
			params: { no_level: "1", page: 2 },
		});
	});

	it("rejects with a reason", async () => {
		await curriculumApi.rejectUpgrade(4, "Later");
		expect(api.post).toHaveBeenCalledWith("learning/level-upgrades/4/reject/", { reason: "Later" });
	});
});
```

`dashboard/src/features/curriculum/errors.test.ts`

```ts
import { AxiosError, type AxiosResponse } from "axios";
import { describe, expect, it } from "vitest";
import i18n from "@/lib/i18n";
import { curriculumErrorText } from "./errors";

function conflict(code: string) {
	return new AxiosError("x", "409", undefined, undefined, {
		status: 409,
		data: { detail: "server words", code },
	} as AxiosResponse);
}

describe("curriculumErrorText", () => {
	it("translates learning codes from the curriculum area", () => {
		expect(curriculumErrorText(conflict("learning.topic_in_use"), i18n.t)).toBe(
			i18n.t("curriculum.errors.topic_in_use"),
		);
	});
	it("falls back to the shared text", () => {
		expect(curriculumErrorText(conflict("other.code"), i18n.t)).toBe("server words");
	});
});
```

- [ ] **Step 2: Run** `cd dashboard && pnpm vitest run src/features/curriculum` → FAIL (modules missing).

- [ ] **Step 3: Implement** — `schemas.ts`

```ts
export interface Paginated<T> {
	count: number;
	next: string | null;
	previous: string | null;
	results: T[];
}

export interface Named {
	id: number;
	name_en: string;
	name_ar: string;
}

export interface TopicInput {
	id?: number;
	name_en: string;
	name_ar: string;
	chapter?: number | null;
	from_verse?: number | null;
	to_verse?: number | null;
}

export interface SubLevelInput {
	id?: number;
	name_en: string;
	name_ar: string;
	topics: TopicInput[];
}

export interface LevelInput {
	course: number;
	name_en: string;
	name_ar: string;
	is_active: boolean;
	sub_levels: SubLevelInput[];
}

export interface LevelSummary extends Named {
	course: Named;
	position: number;
	is_active: boolean;
	sub_level_count: number;
	topic_count: number;
}

export interface LevelDetail extends LevelSummary {
	sub_levels: (SubLevelInput & { id: number; topics: (TopicInput & { id: number })[] })[];
}

export interface Chapter {
	id: number;
	number: number;
	name_arabic: string;
	name_simple: string;
	name_complex: string;
	revelation_place: "makkah" | "madinah";
	revelation_order: number;
	verses_count: number;
	page_start: number;
	page_end: number;
}

export interface LevelRow {
	student_id: number;
	student_name: string;
	course_id: number;
	course_name_en: string;
	course_name_ar: string;
	level_id: number | null;
	level_name_en: string;
	level_name_ar: string;
	since: string | null;
	completed: number;
	total: number;
}

export interface LevelRef {
	level_id: number;
	name_en: string;
	name_ar: string;
}

export interface ProgressTopic {
	id: number;
	name_en: string;
	name_ar: string;
	chapter: number | null; // the chapter's number (1–114) here
	from_verse: number | null;
	to_verse: number | null;
	completed_on: string | null;
}

export interface Progress {
	course_id: number;
	current: (LevelRef & { since: string }) | null;
	history: (LevelRef & { started_on: string; ended_on: string | null })[];
	levels: (Named & {
		is_active: boolean;
		sub_levels: (Named & { topics: ProgressTopic[] })[];
	})[];
	pending_request: {
		id: number;
		from_level_id: number;
		to_level_id: number;
		note: string;
		created_at: string;
	} | null;
	completed: number;
	total: number;
}

export interface ProgressSummary {
	course_id: number;
	course_name_en: string;
	course_name_ar: string;
	level: (LevelRef & { since: string }) | null;
	completed: number;
	total: number;
}

export type UpgradeStatus = "pending" | "approved" | "rejected";

export interface Upgrade {
	id: number;
	student: { id: number; full_name: string };
	course: Named;
	subscription: number | null;
	from_level: Named;
	to_level: Named;
	note: string;
	status: UpgradeStatus;
	rejection_reason: string;
	requested_by: { id: number; full_name: string } | null;
	decided_by: { id: number; full_name: string } | null;
	decided_at: string | null;
	created_at: string;
}

/** Picks the name in the reader's language (ar → name_ar, else name_en). */
export function localName(item: { name_en: string; name_ar: string }, language: string) {
	return language.startsWith("ar") ? item.name_ar || item.name_en : item.name_en || item.name_ar;
}
```

`api.ts`

```ts
import { api } from "@/lib/api";
import type {
	Chapter,
	LevelDetail,
	LevelInput,
	LevelRow,
	LevelSummary,
	Paginated,
	Progress,
	ProgressSummary,
	Upgrade,
	UpgradeStatus,
} from "./schemas";

const B = "learning/";
const progressPath = (student: number, course: number) =>
	`${B}students/${student}/progress/${course}/`;

function clean(params: Record<string, unknown>) {
	return Object.fromEntries(
		Object.entries(params).filter(([, v]) => v !== undefined && v !== "" && v !== false),
	);
}

export interface StudentLevelParams {
	course?: number;
	level?: number;
	noLevel?: boolean;
	search?: string;
	page?: number;
}

export const curriculumApi = {
	levels: async (params: { course?: number; page?: number; page_size?: number } = {}) =>
		(await api.get<Paginated<LevelSummary>>(`${B}levels/`, { params: clean(params) })).data,
	level: async (id: number) => (await api.get<LevelDetail>(`${B}levels/${id}/`)).data,
	createLevel: async (body: LevelInput) => (await api.post<LevelDetail>(`${B}levels/`, body)).data,
	updateLevel: async (id: number, body: LevelInput) =>
		(await api.put<LevelDetail>(`${B}levels/${id}/`, body)).data,
	deleteLevel: async (id: number) => {
		await api.delete(`${B}levels/${id}/`);
	},
	reorderLevels: async (course: number, ids: number[]) => {
		await api.post(`${B}levels/reorder/`, { course, ids });
	},
	chapters: async () => (await api.get<Chapter[]>(`${B}quran-chapters/`)).data,
	updateChapter: async (
		id: number,
		names: Pick<Chapter, "name_arabic" | "name_simple" | "name_complex">,
	) => (await api.patch<Chapter>(`${B}quran-chapters/${id}/`, names)).data,
	syncChapters: async () =>
		(await api.post<{ created: number; reset: number }>(`${B}quran-chapters/sync/`)).data,
	studentLevels: async ({ course, level, noLevel, search, page }: StudentLevelParams = {}) =>
		(
			await api.get<Paginated<LevelRow>>(`${B}student-levels/`, {
				params: clean({ course, level, no_level: noLevel ? "1" : undefined, search, page }),
			})
		).data,
	summary: async (student: number) =>
		(await api.get<ProgressSummary[]>(`${B}students/${student}/progress/`)).data,
	progress: async (student: number, course: number) =>
		(await api.get<Progress>(progressPath(student, course))).data,
	setLevel: async (student: number, course: number, level: number) =>
		(await api.put<Progress>(`${progressPath(student, course)}level/`, { level })).data,
	completeTopic: async (student: number, course: number, topic: number, completedOn?: string) =>
		(
			await api.put<Progress>(
				`${progressPath(student, course)}topics/${topic}/`,
				completedOn ? { completed_on: completedOn } : {},
			)
		).data,
	uncompleteTopic: async (student: number, course: number, topic: number) => {
		await api.delete(`${progressPath(student, course)}topics/${topic}/`);
	},
	upgrades: async (params: { status?: UpgradeStatus; student?: number; course?: number; page?: number } = {}) =>
		(await api.get<Paginated<Upgrade>>(`${B}level-upgrades/`, { params: clean(params) })).data,
	requestUpgrade: async (body: { student: number; course: number; subscription?: number; note?: string }) =>
		(await api.post<Upgrade>(`${B}level-upgrades/`, body)).data,
	approveUpgrade: async (id: number) =>
		(await api.post<Upgrade>(`${B}level-upgrades/${id}/approve/`)).data,
	rejectUpgrade: async (id: number, reason: string) =>
		(await api.post<Upgrade>(`${B}level-upgrades/${id}/reject/`, { reason })).data,
};
```

`queries.ts`

```ts
import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { curriculumApi, type StudentLevelParams } from "./api";
import type { LevelInput, UpgradeStatus } from "./schemas";

export const curriculumKey = ["curriculum"] as const;

function useInvalidating<A, R>(fn: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSuccess: () => qc.invalidateQueries({ queryKey: curriculumKey }),
	});
}

export const useLevels = (params: { course?: number; page?: number } = {}, enabled = true) =>
	useQuery({
		queryKey: [...curriculumKey, "levels", params],
		queryFn: () => curriculumApi.levels({ page_size: 100, ...params }),
		placeholderData: keepPreviousData,
		enabled,
	});

export const useLevel = (id: number | undefined) =>
	useQuery({
		queryKey: [...curriculumKey, "level", id],
		queryFn: () => curriculumApi.level(id as number),
		enabled: id !== undefined,
	});

export const useSaveLevel = (id?: number) =>
	useInvalidating((body: LevelInput) =>
		id === undefined ? curriculumApi.createLevel(body) : curriculumApi.updateLevel(id, body),
	);
export const useDeleteLevel = () => useInvalidating((id: number) => curriculumApi.deleteLevel(id));
export const useReorderLevels = () =>
	useInvalidating(({ course, ids }: { course: number; ids: number[] }) =>
		curriculumApi.reorderLevels(course, ids),
	);

export const useChapters = (enabled = true) =>
	useQuery({
		queryKey: [...curriculumKey, "chapters"],
		queryFn: curriculumApi.chapters,
		staleTime: 5 * 60_000,
		enabled,
	});
export const useUpdateChapter = () =>
	useInvalidating(
		({ id, ...names }: { id: number; name_arabic: string; name_simple: string; name_complex: string }) =>
			curriculumApi.updateChapter(id, names),
	);
export const useSyncChapters = () => useInvalidating((_: void) => curriculumApi.syncChapters());

export const useStudentLevels = (params: StudentLevelParams) =>
	useQuery({
		queryKey: [...curriculumKey, "student-levels", params],
		queryFn: () => curriculumApi.studentLevels(params),
		placeholderData: keepPreviousData,
	});

export const useProgressSummary = (student: number | undefined) =>
	useQuery({
		queryKey: [...curriculumKey, "summary", student],
		queryFn: () => curriculumApi.summary(student as number),
		enabled: student !== undefined,
		retry: false,
	});

export const useProgress = (student: number, course: number) =>
	useQuery({
		queryKey: [...curriculumKey, "progress", student, course],
		queryFn: () => curriculumApi.progress(student, course),
	});

export const useSetLevel = (student: number, course: number) =>
	useInvalidating((level: number) => curriculumApi.setLevel(student, course, level));

export const useToggleTopic = (student: number, course: number) =>
	useInvalidating(({ topic, done }: { topic: number; done: boolean }) =>
		done
			? curriculumApi.completeTopic(student, course, topic)
			: curriculumApi.uncompleteTopic(student, course, topic),
	);

export const useUpgrades = (params: { status?: UpgradeStatus; page?: number }) =>
	useQuery({
		queryKey: [...curriculumKey, "upgrades", params],
		queryFn: () => curriculumApi.upgrades(params),
		placeholderData: keepPreviousData,
	});

export const useRequestUpgrade = () => useInvalidating(curriculumApi.requestUpgrade);

export const useDecideUpgrade = () =>
	useInvalidating(({ id, reject, reason }: { id: number; reject?: boolean; reason?: string }) =>
		reject ? curriculumApi.rejectUpgrade(id, reason ?? "") : curriculumApi.approveUpgrade(id),
	);
```

`errors.ts`

```ts
import type { TFunction } from "i18next";
import { parseApiError } from "@/features/identity/api";
import { errorText } from "@/lib/form-errors";

/** A failed curriculum action as one sentence: `learning.*` codes from the
 * curriculum area (spec §10), anything else as everywhere else. */
export function curriculumErrorText(error: unknown, t: TFunction): string {
	const code = parseApiError(error).code;
	if (code?.startsWith("learning.")) {
		const text = t(`curriculum.errors.${code.slice("learning.".length)}`, { defaultValue: "" });
		if (text) return text;
	}
	return errorText(error, t);
}
```

`fixtures.ts` — test data used by Tasks 10–12:

```ts
import type { Chapter, LevelDetail, LevelRow, LevelSummary, Paginated, Progress, Upgrade } from "./schemas";

export const page = <T,>(results: T[]): Paginated<T> => ({ count: results.length, next: null, previous: null, results });

export const quran = { id: 3, name_en: "Quran", name_ar: "تحفيظ" };

export const levelSummary: LevelSummary = {
	id: 10, course: quran, name_en: "Juz' Amma", name_ar: "جزء عمّ",
	position: 0, is_active: true, sub_level_count: 1, topic_count: 2,
};

export const levelDetail: LevelDetail = {
	...levelSummary,
	sub_levels: [
		{
			id: 20, name_en: "Short surahs", name_ar: "قصار السور",
			topics: [
				{ id: 30, name_en: "An-Nas", name_ar: "الناس", chapter: 114, from_verse: null, to_verse: null },
				{ id: 31, name_en: "Al-Falaq", name_ar: "الفلق", chapter: 113, from_verse: null, to_verse: null },
			],
		},
	],
};

export const fatiha: Chapter = {
	id: 1, number: 1, name_arabic: "الفاتحة", name_simple: "Al-Fatihah", name_complex: "Al-Fātiĥah",
	revelation_place: "makkah", revelation_order: 5, verses_count: 7, page_start: 1, page_end: 1,
};

export const rowWithLevel: LevelRow = {
	student_id: 7, student_name: "Yusuf", course_id: 3, course_name_en: "Quran", course_name_ar: "تحفيظ",
	level_id: 10, level_name_en: "Juz' Amma", level_name_ar: "جزء عمّ", since: "2026-06-01", completed: 1, total: 2,
};

export const rowWithoutLevel: LevelRow = {
	...rowWithLevel, student_id: 8, student_name: "Zaid", level_id: null, level_name_en: "", level_name_ar: "", since: null, completed: 0,
};

export const progress: Progress = {
	course_id: 3,
	current: { level_id: 10, name_en: "Juz' Amma", name_ar: "جزء عمّ", since: "2026-06-01" },
	history: [{ level_id: 10, name_en: "Juz' Amma", name_ar: "جزء عمّ", started_on: "2026-06-01", ended_on: null }],
	levels: [
		{
			id: 10, name_en: "Juz' Amma", name_ar: "جزء عمّ", is_active: true,
			sub_levels: [
				{
					id: 20, name_en: "Short surahs", name_ar: "قصار السور",
					topics: [
						{ id: 30, name_en: "An-Nas", name_ar: "الناس", chapter: 114, from_verse: null, to_verse: null, completed_on: "2026-06-01" },
						{ id: 31, name_en: "Al-Falaq", name_ar: "الفلق", chapter: 113, from_verse: null, to_verse: null, completed_on: null },
					],
				},
			],
		},
		{ id: 11, name_en: "Juz' Tabarak", name_ar: "جزء تبارك", is_active: true, sub_levels: [] },
	],
	pending_request: null,
	completed: 1,
	total: 2,
};

export const noLevelProgress: Progress = { ...progress, current: null, history: [], completed: 0 };

export const pendingUpgrade: Upgrade = {
	id: 40, student: { id: 7, full_name: "Yusuf" }, course: quran, subscription: null,
	from_level: { id: 10, name_en: "Juz' Amma", name_ar: "جزء عمّ" },
	to_level: { id: 11, name_en: "Juz' Tabarak", name_ar: "جزء تبارك" },
	note: "Ready", status: "pending", rejection_reason: "", requested_by: { id: 2, full_name: "Bilal" },
	decided_by: null, decided_at: null, created_at: "2026-06-02T08:00:00Z",
};
```

`index.ts` exports `curriculumApi`, every hook, `curriculumErrorText`, the types, and (after Tasks 10–12) the components.

- [ ] **Step 4: Translations** — `dashboard/src/locales/en/curriculum.json` (top-level key `curriculum`; `ar` mirrors every key with Arabic text). Minimum keys (add any key a component uses):

```json
{
	"curriculum": {
		"nav": {
			"levels": "Levels",
			"quran": "Qur'an chapters",
			"studentLevels": "Student levels",
			"upgrades": "Level upgrades",
			"myStudents": "My students' levels",
			"myProgress": "My progress"
		},
		"levels": {
			"title": "Levels",
			"subtitle": "Each course's levels, sub-levels and topics.",
			"add": "Add level",
			"edit": "Edit level",
			"course": "Course",
			"allCourses": "All courses",
			"nameEn": "Name (English)",
			"nameAr": "Name (Arabic)",
			"active": "Active",
			"inactive": "Inactive",
			"subLevels": "Sub-levels",
			"topics": "Topics",
			"topicCount": "{{count}} topics",
			"addSubLevel": "Add sub-level",
			"addTopic": "Add topic",
			"remove": "Remove",
			"moveUp": "Move up",
			"moveDown": "Move down",
			"chapter": "Chapter",
			"noChapter": "No chapter",
			"fromVerse": "From verse",
			"toVerse": "To verse",
			"empty": "No levels yet.",
			"delete": "Delete level",
			"deleteConfirm": "Delete “{{name}}” with its sub-levels and topics?",
			"saved": "Level saved.",
			"deleted": "Level deleted."
		},
		"quran": {
			"title": "Qur'an chapters",
			"subtitle": "The 114 chapters, from the bundled data.",
			"sync": "Sync chapters",
			"synced": "{{created}} added, {{reset}} reset.",
			"empty": "No chapters yet. Sync to load the 114 chapters.",
			"number": "No.",
			"arabic": "Arabic name",
			"simple": "Simple name",
			"complex": "Complex name",
			"place": "Revelation place",
			"order": "Revelation order",
			"verses": "Verses",
			"pages": "Pages",
			"makkah": "Makkah",
			"madinah": "Madinah",
			"edit": "Edit names",
			"saved": "Chapter saved."
		},
		"progress": {
			"title": "Student levels",
			"subtitle": "Where each student is on their course's ladder.",
			"student": "Student",
			"level": "Level",
			"noLevel": "No level",
			"onlyNoLevel": "Without a level",
			"since": "Since",
			"completed": "Completed",
			"completedOf": "{{completed}} / {{total}}",
			"search": "Search students",
			"empty": "No students to show.",
			"open": "Open progress",
			"changeLevel": "Change level",
			"setFirstLevel": "Set first level",
			"chooseLevel": "Choose a level",
			"save": "Save",
			"history": "Level history",
			"current": "Current level",
			"requestUpgrade": "Request upgrade",
			"note": "Note",
			"send": "Send request",
			"pending": "Upgrade requested: {{from}} → {{to}}",
			"completedOn": "Completed {{date}}",
			"childPicker": "Child",
			"noProgress": "No levels recorded yet.",
			"levelSaved": "Level saved.",
			"requested": "Upgrade requested."
		},
		"upgrades": {
			"title": "Level upgrades",
			"subtitle": "Teachers' requests to move students up a level.",
			"pending": "Pending",
			"approved": "Approved",
			"rejected": "Rejected",
			"fromTo": "{{from}} → {{to}}",
			"askedBy": "Asked by",
			"date": "Date",
			"approve": "Approve",
			"reject": "Reject",
			"reason": "Reason",
			"reasonRequired": "Give a reason.",
			"empty": "No requests.",
			"approvedToast": "Approved: the student moved up.",
			"rejectedToast": "Request rejected."
		},
		"errors": {
			"topic_in_use": "A student has completed this topic: rename it instead of removing it.",
			"level_in_use": "Students have records on this level: deactivate it instead.",
			"level_already_set": "This student already has a level: request an upgrade instead.",
			"request_pending": "An upgrade request is already waiting.",
			"no_level": "Set the student's level first.",
			"top_level": "The student is at the last level.",
			"request_decided": "This request has already been decided.",
			"level_changed": "The student's level changed since the request: reject it.",
			"level_inactive": "The next level was deactivated: reject the request."
		}
	}
}
```

- [ ] **Step 5: Run** `pnpm vitest run src/features/curriculum src/locales` → PASS (locale parity included). `pnpm tsc --noEmit` clean.
- [ ] **Step 6: Commit** — `git -C dashboard add src/features/curriculum src/locales src/features/identity/schemas.ts && git -C dashboard commit -m "feat(curriculum): data layer, switches and translations (B6a)"`.

---

### Task 10: Dashboard — Levels and Qur'an chapters pages (office)

**Files:**
- Create: `dashboard/src/features/curriculum/LevelsList.tsx`, `LevelDialog.tsx`, `ChaptersTable.tsx` and their `*.test.tsx`; routes `dashboard/src/routes/_authed/catalogue.levels.tsx`, `catalogue.quran.tsx`
- Modify: `dashboard/src/features/shell/nav.ts` (under `// ── phase B6 ──`), `dashboard/src/routeTree.gen.ts` (regenerate via `pnpm build` or the router plugin: never by hand), `dashboard/src/features/curriculum/index.ts`

**Interfaces:**
- Consumes: Task 9 hooks and types; `useCatalogue<Course>("courses", { page_size: 100 })` from `@/features/catalogue` (check `CatalogueParams` for the page-size key name); `useCan`, `useHasFeature` from `@/features/identity/permissions`; `Dialog*`, `AlertDialog*`, `Button`, `Field`, `Input`, `Select`, `Checkbox`, `EmptyState`, `Spinner`, `PageHeader`, `toast` from `@/ui`.
- Produces: `LevelsList` (no props), `LevelDialog({ level?: LevelDetail; defaultCourse?: number; trigger: ReactNode })`, `ChaptersTable` (no props).

Behaviour to implement and test (spec §6):

- **LevelsList**: course filter `<Select>` ("All courses" + courses); a table with columns course · level · sub-levels · topics · active; per row: move up / move down buttons (shown only with `level.reorder` and when a course filter is chosen — reorder needs one course; disabled at the ends), edit (opens `LevelDialog` with the loaded `useLevel(id)` detail), delete (AlertDialog, `level.delete`). Add button (`level.create`) opens an empty `LevelDialog` with `defaultCourse` = the filter. Mutation errors → `toast({ description: curriculumErrorText(e, t), variant: "destructive" })`.
- **LevelDialog**: local state (`useState`) holding a `LevelInput`; fields course (select, disabled when editing), name en / ar, active checkbox; a sub-level repeater (add, remove, move up/down; each with name en / ar) each with a topic repeater (add, remove, move up/down; name en / ar; when `useHasFeature()("quran_chapters")`: a chapter `<Select>` from `useChapters()` labelled `number. name_simple`, and from/to verse number inputs with `max={chapter.verses_count}`; choosing a chapter when both names are empty fills `name_en = name_simple`, `name_ar = name_arabic`, and filling verses appends ` from–to` to empty-or-prefilled names). Submit sends the whole tree (ids kept for existing rows). Server field errors (`parseApiError(e).fieldErrors`, keys like `sub_levels.0.topics.2.to_verse`) render under the matching input; a 409 renders `curriculumErrorText` in a `FormError` at the top. On success: toast `curriculum.levels.saved`, close.
- **ChaptersTable**: table of 114 rows (number, Arabic, simple, place translated, order, verses, `page_start–page_end`); "Sync chapters" button (`quran_chapter.create`) → toast `curriculum.quran.synced` with counts; empty state with the same button; per row "Edit names" (`quran_chapter.update`) dialog with three inputs.

- [ ] **Step 1: Write the failing tests** — `LevelDialog.test.tsx` (pattern of `employment/ContractsList.test.tsx`: `vi.mock("./api", …)`, `renderWithRouter`, `CanProvider` with `staffMe(...codes)` from `@/test/access-fixtures`; to turn `quran_chapters` on, give the `Me` fixture `features: ["levels", "quran_chapters"]`):

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError, type AxiosResponse } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { catalogueApi } from "@/features/catalogue";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { Button } from "@/ui";
import { curriculumApi } from "./api";
import { fatiha, levelDetail, quran } from "./fixtures";
import { LevelDialog } from "./LevelDialog";

vi.mock("./api", () => ({
	curriculumApi: { chapters: vi.fn(), createLevel: vi.fn(), updateLevel: vi.fn() },
}));
vi.mock("@/features/catalogue", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue")>();
	return { ...actual, catalogueApi: { ...actual.catalogueApi, list: vi.fn() } };
});

const me = { ...staffMe("level.create", "level.update"), features: ["levels", "quran_chapters"] };

function open(props = {}) {
	renderWithRouter(
		<CanProvider me={me}>
			<LevelDialog trigger={<Button>open</Button>} defaultCourse={3} {...props} />
		</CanProvider>,
	);
	return userEvent.click(screen.getByRole("button", { name: "open" }));
}

describe("LevelDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(curriculumApi.chapters).mockResolvedValue([fatiha]);
		vi.mocked(catalogueApi.list).mockResolvedValue({ count: 1, next: null, previous: null, results: [quran] } as never);
		vi.mocked(curriculumApi.createLevel).mockResolvedValue(levelDetail);
	});

	it("builds a tree with a chapter-linked topic and submits it", async () => {
		const user = userEvent.setup();
		await open();
		await user.type(screen.getByLabelText("Name (English)"), "Juz' Amma");
		await user.type(screen.getByLabelText("Name (Arabic)"), "جزء عمّ");
		await user.click(screen.getByRole("button", { name: "Add sub-level" }));
		await user.type(screen.getAllByLabelText("Name (English)")[1], "Opening");
		await user.type(screen.getAllByLabelText("Name (Arabic)")[1], "البداية");
		await user.click(screen.getByRole("button", { name: "Add topic" }));
		await user.selectOptions(await screen.findByLabelText("Chapter"), "1");
		await user.type(screen.getByLabelText("From verse"), "1");
		await user.type(screen.getByLabelText("To verse"), "7");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() => expect(curriculumApi.createLevel).toHaveBeenCalled());
		expect(vi.mocked(curriculumApi.createLevel).mock.calls[0][0]).toEqual({
			course: 3,
			name_en: "Juz' Amma",
			name_ar: "جزء عمّ",
			is_active: true,
			sub_levels: [
				{
					name_en: "Opening",
					name_ar: "البداية",
					topics: [{ name_en: "Al-Fatihah 1–7", name_ar: "الفاتحة 1–7", chapter: 1, from_verse: 1, to_verse: 7 }],
				},
			],
		});
	});

	it("shows a nested server error under its field and a 409 at the top", async () => {
		const user = userEvent.setup();
		vi.mocked(curriculumApi.updateLevel).mockRejectedValueOnce(
			new AxiosError("x", "400", undefined, undefined, {
				status: 400,
				data: { "sub_levels.0.topics.1.name_en": ["Too long."] },
			} as AxiosResponse),
		);
		await open({ level: levelDetail });
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(await screen.findByText("Too long.")).toBeInTheDocument();
		vi.mocked(curriculumApi.updateLevel).mockRejectedValueOnce(
			new AxiosError("x", "409", undefined, undefined, {
				status: 409,
				data: { detail: "x", code: "learning.topic_in_use" },
			} as AxiosResponse),
		);
		await user.click(screen.getAllByRole("button", { name: "Remove" }).at(-1) as HTMLElement);
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(await screen.findByText(/rename it instead of removing it/)).toBeInTheDocument();
	});

	it("hides the chapter picker while quran_chapters is off", async () => {
		renderWithRouter(
			<CanProvider me={{ ...me, features: ["levels"] }}>
				<LevelDialog trigger={<Button>open</Button>} level={levelDetail} />
			</CanProvider>,
		);
		await userEvent.click(screen.getByRole("button", { name: "open" }));
		expect(screen.queryByLabelText("Chapter")).not.toBeInTheDocument();
	});
});
```

`LevelsList.test.tsx` — tests: lists levels with counts; the course filter calls `curriculumApi.levels` with `{ course: 3, page_size: 100 }`; move down calls `reorderLevels(3, [11, 10])` for two rows `[10, 11]`; delete confirms and shows the `level_in_use` message on 409; without `level.create` there is no "Add level" button.

`ChaptersTable.test.tsx` — tests: empty state shows "Sync chapters"; clicking it calls `syncChapters` and toasts "114 added, 0 reset."; the table shows `Al-Fatihah`, "Makkah", "1–1"; edit names submits the three names; without `quran_chapter.create` no sync button.

Write those tests with the same mocking pattern (`vi.mock("./api", …)` listing `levels, level, deleteLevel, reorderLevels, chapters, syncChapters, updateChapter`).

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** the three components to the behaviour above (tables styled like `features/access/StaffList.tsx`: `overflow-x-auto rounded-lg border border-border`, `table.w-full.text-sm`, `thead.bg-secondary`). Use `localName(item, i18n.language)` for every bilingual name. Each repeater row's controls get accessible labels from the translation keys above; repeat labels are fine (tests use `getAllByLabelText`).

- [ ] **Step 4: Routes**

`dashboard/src/routes/_authed/catalogue.levels.tsx`

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { LevelsList } from "@/features/curriculum";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/catalogue/levels")({
	staticData: { permission: "level.view_any", feature: "levels" },
	component: function LevelsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("curriculum.levels.title"));
		return (
			<>
				<PageHeader title={t("curriculum.levels.title")} description={t("curriculum.levels.subtitle")} />
				<LevelsList />
			</>
		);
	},
});
```

`catalogue.quran.tsx`: same shape, `staticData: { permission: "quran_chapter.view_any", feature: "quran_chapters" }`, title `curriculum.quran.title`, body `<ChaptersTable />`. (`catalogue.tsx` already guards office-only.)

- [ ] **Step 5: Nav** — under `// ── phase B6 ──` in `NAV_ITEMS` (icons from `lucide-react`; add imports at the top):

```ts
	office("/catalogue/levels", "curriculum.nav.levels", Layers, "catalogue", "level.view_any", "levels"),
	office("/catalogue/quran", "curriculum.nav.quran", BookOpen, "catalogue", "quran_chapter.view_any", "quran_chapters"),
```

- [ ] **Step 6: Run** `pnpm vitest run src/features/curriculum src/routes src/features/shell` (includes `src/routes/permissions.test.ts`, which checks `staticData`), `pnpm tsc --noEmit`, `pnpm lint`. → PASS.
- [ ] **Step 7: Commit** — `git -C dashboard add src && git -C dashboard commit -m "feat(curriculum): levels and Qur'an chapters pages (B6a)"`.

---

### Task 11: Dashboard — Student levels, progress panel, teacher page and upgrades

**Files:**
- Create: `dashboard/src/features/curriculum/StudentLevelsList.tsx`, `ProgressPanel.tsx`, `UpgradesList.tsx` with `*.test.tsx`; routes `dashboard/src/routes/_authed/scheduling.student-levels.tsx`, `scheduling.level-upgrades.tsx`, `teaching.levels.tsx`
- Modify: `nav.ts` (B6 marker), `index.ts`, `routeTree.gen.ts` (regenerated)

**Interfaces:**
- Consumes: Task 9 hooks; `useMe` (`@/features/identity/queries`) for the role; `useCan`.
- Produces: `StudentLevelsList({ asTeacher?: boolean })`, `ProgressPanel({ studentId: number; studentName: string; courseId: number; courseName: string; open: boolean; onOpenChange(open: boolean): void })`, `UpgradesList` (no props).

Behaviour (spec §6, C-8, C-11):

- **StudentLevelsList**: filters — course select (office only, from `useCatalogue("courses")`; teachers see no course select since they cannot read the catalogue), level select (from `useLevels({course})`, only when a course is chosen), "Without a level" checkbox, search input (debounced 300 ms); table student · course · level (or a muted "No level") · since · `completed / total`; pagination "Load more" via `page`; a row's "Open progress" button opens `ProgressPanel` for that pair.
- **ProgressPanel** (a `Dialog` with a wide content, not a drawer — the UI kit has no drawer): loads `useProgress`; header: current level + since or "No level"; level control:
  - office (`useCan()("student_level.update")` or role admin): "Change level" select of active levels + Save → `useSetLevel`;
  - teacher: "Set first level" select + Save, **only when `current === null`**;
  - each level a `<details>` section (current level open) listing sub-levels and their topics as checkboxes (`Checkbox` labelled with the topic name; checked = `completed_on !== null`; when checked shows "Completed {date}"); toggling calls `useToggleTopic`; checkboxes are disabled for readers without the right (staff without `student_level.update`);
  - "Level history" list;
  - pending request line `curriculum.progress.pending` when `pending_request`; otherwise, when `current` is set and a later active level exists and the user may ask (teacher, or `level_upgrade_request.create`), a "Request upgrade" button opening a small form with a note → `useRequestUpgrade({student, course, note})`.
  - Errors → toast `curriculumErrorText`.
- **UpgradesList**: three tab buttons (`role="tab"`, `aria-selected`) pending / approved / rejected, the pending one showing its count from `useUpgrades({status:"pending"}).data.count`; table student · course · from → to · asked by · date · note (· decided by + reason for rejected); pending rows: Approve (`level_upgrade_request.update`) and Reject opening a dialog with a required reason (client-side "Give a reason." when empty; server 400 shown too).

- [ ] **Step 1: Write the failing tests** — `ProgressPanel.test.tsx` (core cases; same mocking pattern; `useMe` reads `identityApi.me` — mock it or wrap in the existing `CanProvider`, whichever the role check uses; prefer passing the role through `CanProvider me`):

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import type { Me } from "@/features/identity/schemas";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { curriculumApi } from "./api";
import { noLevelProgress, progress } from "./fixtures";
import { ProgressPanel } from "./ProgressPanel";

vi.mock("./api", () => ({
	curriculumApi: {
		progress: vi.fn(), setLevel: vi.fn(), completeTopic: vi.fn(), uncompleteTopic: vi.fn(), requestUpgrade: vi.fn(),
	},
}));

const teacher = { ...staffMe(), role: "teacher", features: ["levels"] } as Me;
const office = { ...staffMe("student_level.view", "student_level.update", "level_upgrade_request.create"), features: ["levels"] } as Me;

function show(me: Me) {
	return renderWithRouter(
		<CanProvider me={me}>
			<ProgressPanel studentId={7} studentName="Yusuf" courseId={3} courseName="Quran" open onOpenChange={() => {}} />
		</CanProvider>,
	);
}

describe("ProgressPanel", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(curriculumApi.progress).mockResolvedValue(progress);
		vi.mocked(curriculumApi.completeTopic).mockResolvedValue(progress);
	});

	it("ticks and unticks topics", async () => {
		const user = userEvent.setup();
		show(office);
		await user.click(await screen.findByRole("checkbox", { name: "Al-Falaq" }));
		expect(curriculumApi.completeTopic).toHaveBeenCalledWith(7, 3, 31, undefined);
		await user.click(screen.getByRole("checkbox", { name: "An-Nas" }));
		expect(curriculumApi.uncompleteTopic).toHaveBeenCalledWith(7, 3, 30);
	});

	it("lets the office change a level but a teacher only set the first one", async () => {
		show(office);
		expect(await screen.findByLabelText("Change level")).toBeInTheDocument();
	});

	it("offers a teacher the first level only while there is none", async () => {
		show(teacher);
		expect(await screen.findByRole("checkbox", { name: "An-Nas" })).toBeInTheDocument();
		expect(screen.queryByLabelText("Set first level")).not.toBeInTheDocument();
		expect(screen.queryByLabelText("Change level")).not.toBeInTheDocument();
	});

	it("sends an upgrade request with a note", async () => {
		const user = userEvent.setup();
		show(teacher);
		await user.click(await screen.findByRole("button", { name: "Request upgrade" }));
		await user.type(screen.getByLabelText("Note"), "Ready");
		await user.click(screen.getByRole("button", { name: "Send request" }));
		await waitFor(() =>
			expect(curriculumApi.requestUpgrade).toHaveBeenCalledWith({ student: 7, course: 3, note: "Ready" }),
		);
	});

	it("hides the request button while one is pending", async () => {
		vi.mocked(curriculumApi.progress).mockResolvedValue({
			...progress,
			pending_request: { id: 40, from_level_id: 10, to_level_id: 11, note: "", created_at: "2026-06-02T08:00:00Z" },
		});
		show(teacher);
		expect(await screen.findByText("Upgrade requested: Juz' Amma → Juz' Tabarak")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Request upgrade" })).not.toBeInTheDocument();
	});
});
```

Add a separate test rendering a teacher with `noLevelProgress` that finds "Set first level", picks "Juz' Amma" and saves → `setLevel(7, 3, 10)`. `StudentLevelsList.test.tsx`: rows with and without level ("No level"), the "Without a level" checkbox calls `studentLevels` with `noLevel: true`, "Open progress" opens the panel (mock `progress`), a teacher sees no course select. `UpgradesList.test.tsx`: pending tab count, approve calls `approveUpgrade(40)`, reject with an empty reason shows "Give a reason." and does not call the API, with a reason calls `rejectUpgrade(40, "Later")`, the rejected tab shows the reason.

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** the three components.

- [ ] **Step 4: Routes**

`scheduling.student-levels.tsx`: `staticData: { permission: "student_level.view_any", feature: "levels" }`, `<PageHeader title={t("curriculum.progress.title")} description={t("curriculum.progress.subtitle")} />` + `<StudentLevelsList />`. Check `scheduling.tsx` (the parent) guards office-only; if it does not, add `beforeLoad: ({ context }) => requireOffice(context)` here.

`scheduling.level-upgrades.tsx`: `staticData: { permission: "level_upgrade_request.view_any", feature: "levels" }`, `<UpgradesList />`.

`teaching.levels.tsx`: `staticData: { feature: "levels" }` (the `teaching` layout guards the teacher role, as `teaching.reports.tsx`), title `curriculum.nav.myStudents`, `<StudentLevelsList asTeacher />`.

- [ ] **Step 5: Nav** — under the B6 marker:

```ts
	office("/scheduling/student-levels", "curriculum.nav.studentLevels", GraduationCap, "scheduling", "student_level.view_any", "levels"),
	office("/scheduling/level-upgrades", "curriculum.nav.upgrades", TrendingUp, "scheduling", "level_upgrade_request.view_any", "levels"),
	{
		to: "/teaching/levels",
		labelKey: "curriculum.nav.myStudents",
		icon: GraduationCap,
		group: "teaching",
		requiresRole: "teacher",
		feature: "levels",
	},
```

- [ ] **Step 6: Run** the curriculum, routes and shell tests, `pnpm tsc --noEmit`, `pnpm lint` → PASS.
- [ ] **Step 7: Commit** — `git -C dashboard add src && git -C dashboard commit -m "feat(curriculum): student levels, progress panel and upgrades (B6a)"`.

---

### Task 12: Dashboard — My progress (student / parent) and StudentLevelCard

**Files:**
- Create: `dashboard/src/features/curriculum/MyProgress.tsx`, `StudentLevelCard.tsx` with tests; route `dashboard/src/routes/_authed/learning.progress.tsx`
- Modify: `nav.ts` (B6 marker), `index.ts`, `routeTree.gen.ts` (regenerated)

**Interfaces:**
- Consumes: `useMe` (`@/features/identity/queries`; `me.role`, `me.id`, `me.children: {id, full_name}[]` — children's `id` is the child's user id), `useProgressSummary`, `useProgress`, `useHasFeature`.
- Produces: `MyProgress` (no props); `StudentLevelCard({ studentId: number; courseId: number; onOpen?: () => void })` — exported for request R-B6-1.

Behaviour:

- **MyProgress**: a student reads their own (`me.id`); a parent gets a "Child" select from `me.children` (first child preselected; none → empty state). For the chosen student: `useProgressSummary`; one card per course (course name, level or "No level", `completed / total` with a `Meter`), each expandable to the read-only ladder (`useProgress(student, course)`: levels → sub-levels → topics with a ✓ and the completion date, no checkboxes). Empty → `curriculum.progress.noProgress`.
- **StudentLevelCard**: renders nothing while `levels` is off or when `useProgressSummary(studentId)` fails (403/404 — the viewer may not read this student). When the summary loads: the course's entry shows level name, since and `completed / total`; a course absent from the summary shows "No level". An "Open progress" button appears when `onOpen` is given.

- [ ] **Step 1: Write the failing tests** — `MyProgress.test.tsx`: a student sees their course card with "Juz' Amma" and "1 / 2"; expanding shows "An-Nas" with "Completed …"; a parent with two children switches child and `summary` is called with the second child's id; no children → empty state. `StudentLevelCard.test.tsx`: renders the level for the course; renders nothing when `summary` rejects with a 404; renders nothing when `levels` is off; shows "No level" when the course is absent from a loaded summary.

Mock `./api` (`summary`, `progress`) and render inside `CanProvider me={…}`; for `useMe`, mock `@/features/identity/queries` the way `features/scheduling` student-side tests do (search `FamilySubscriptions.test.tsx` for the pattern) and reuse it.

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.**

- [ ] **Step 4: Route** — `learning.progress.tsx`: `staticData: { feature: "levels" }` (the `learning` layout guards student/parent), title `curriculum.nav.myProgress`, `<MyProgress />`. Nav under B6 marker:

```ts
	{
		to: "/learning/progress",
		labelKey: "curriculum.nav.myProgress",
		icon: GraduationCap,
		group: "learning",
		requiresRole: ["student", "parent"],
		feature: "levels",
	},
```

- [ ] **Step 5: Run** `pnpm test` (whole dashboard, with coverage as `just test` runs it) → PASS with thresholds met; `pnpm tsc --noEmit`; `pnpm lint`.
- [ ] **Step 6: Commit** — `git -C dashboard add src && git -C dashboard commit -m "feat(curriculum): my progress and the student level card (B6a)"`.

---

### Task 13: e2e — `dashboard/e2e/b6-curriculum.spec.ts`

**Files:**
- Create: `dashboard/e2e/b6-curriculum.spec.ts`

**Interfaces:**
- Consumes: `e2e/fixtures.ts` (`login`, `expectLoggedIn`, `acceptInvite`, `DEMO_URL`, `DEMO_ADMIN`), `e2e/manage.ts` (`manage`); the `signInTeacher` pattern of `e2e/b9-platform.spec.ts` (copy it locally with its own fixed password `e2e-Teacher-B6a`); the CSRF-header API call pattern of `e2e/b3-online-payments.spec.ts` (`page.request.post` with `X-CSRFToken` from the `csrftoken` cookie and `Referer: ${DEMO_URL}/app/`).

The journey (stamp names with `Date.now()` so re-runs on the same database work):

1. `beforeAll`: `manage("set_features", "demo", "--on", "levels", "--on", "quran_chapters")`.
2. Admin signs in; `/app/catalogue/quran` → click "Sync chapters" → toast shows "added" or "reset"; the table shows "Al-Fatihah".
3. Through the API as the admin (fast set-up, stamped): create a student `B6 Student <stamp>` with email `b6-<stamp>@demo.test` (`POST /api/v1/people/students/`, body as `e2e` people specs send it — read `e2e/people-catalogue.spec.ts` or the serializer for the minimal body), find course "Quran Memorisation" and teacher "Ustadha Maryam" ids (`GET /api/v1/catalogue/courses/?search=` / `GET /api/v1/people/teachers/`), find a package id (`GET /api/v1/catalogue/packages/`), and create a subscription starting today (`POST /api/v1/subscriptions/` with `student`, `course`, `teacher`, `package`, `starts_on`).
4. Admin UI: `/app/catalogue/levels` → "Add level": course "Quran Memorisation", names `Level A <stamp>` / `مستوى أ`, add a sub-level, add a topic with chapter "1. Al-Fatihah", verses 1–7, save → the row appears. Add a second level `Level B <stamp>` the same way (one plain topic).
5. Admin UI: `/app/scheduling/student-levels` → tick "Without a level", search the stamped student → "Open progress" → "Change level" = `Level A <stamp>` → Save → the panel shows the current level.
6. Teacher Maryam signs in (new context) → `/app/teaching/levels` → search the student → "Open progress" → tick the "Al-Fatihah 1–7" topic → "Request upgrade", note "Ready", "Send request" → the pending line shows.
7. Admin: `/app/scheduling/level-upgrades` → the stamped student's pending row → "Approve" → toast.
8. Student signs in: give the stamped student a password with the invite flow (`acceptInvite(browser, email, password, name)` after "Forgot your password?", as `signInTeacher` does) → `/app/learning/progress` shows `Level B <stamp>`.

> Level ordering: the course may already hold the seed's three levels; "next level" is by position, so create Level A and Level B last and in that order — Level B is then Level A's next active level.

- [ ] **Step 1: Write the spec** following the steps above (role-based locators, as other specs).
- [ ] **Step 2: Run** against the stream stack: `just dev-backend` (if not up), then `just e2e -- b6-curriculum` (or the recipe's filter syntax; read `justfile`). Expected: PASS. Then the whole `just e2e` → PASS.
- [ ] **Step 3: Commit** — `git -C dashboard add e2e/b6-curriculum.spec.ts && git -C dashboard commit -m "test(e2e): B6a curriculum journey"`.

---

### Task 14: Slice verification

- [ ] **Step 1:** `just test` → all green with coverage gates (backend ≥ 80 %, dashboard thresholds).
- [ ] **Step 2:** `just lint` → clean (ruff, lint-imports, biome / `pnpm lint`, tsc).
- [ ] **Step 3:** `just e2e` against the stream stack → all green.
- [ ] **Step 4:** Spec coverage check: walk spec §5 C-1…C-15 and §6 screens; each has code and a test. Fix any gap before the final review.
- [ ] **Step 5:** Commit any fixes; record the slice's state in the phase notes (`../_ledger/orchestration/phases/B6.md`).
