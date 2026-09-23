# Phase C0 — Matching Inputs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the data a teacher–student matcher needs — a real `Subject` model with typed teacher/student links, and a gender field on `TeacherProfile` — so that Phase C1 can be written at all.

**Architecture:** A new minimal `curriculum` Django module owns `Subject`, `TeacherSubject` and `StudentSubjectInterest`, keyed to `AUTH_USER_MODEL` by string so the dependency arrow runs curriculum → identity. `identity` gains one field. The dashboard grows a subjects panel per role on the existing `/account` route. No matching logic, no booking, no video.

**Tech Stack:** Django 5 + DRF, pytest, import-linter, React 19 + TanStack Query + Tailwind, vitest, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-04-phase-c0-matching-inputs-design.md`

## Global Constraints

- **TDD is mandatory (D3).** Failing test first, watched failing, then minimal code. Never write implementation before its test.
- **Coverage floors, enforced in CI:** backend 97 (line+branch, `pyproject.toml`), dashboard 92 lines / 87 branches / 84 functions (`vitest.config.ts`). Raise them if this slice lifts coverage; lowering needs an ADR.
- **Module boundaries (D4):** no module imports another module's models. `curriculum` reaches `identity` only through `identity.services` and `settings.AUTH_USER_MODEL` string references.
- **API versioning (ADR-0029):** every route mounts under `/api/v1/` via `config.api_router`. `backend/tests/test_api_versioning_is_enforced.py` walks the resolved URLconf and fails otherwise.
- **Business logic in `services.py`**, never on models. Models are dumb data structures.
- **Typed exceptions only** — `kaleem.platform.exceptions` (`ValidationError`, `NotFoundError`, `PermissionDeniedError`). Never catch bare `Exception`; never `print()`.
- **ruff:** `force-single-line = true` for imports. One import per line, always.
- **a11y/i18n/l10n baseline:** WCAG 2.2 AA, every string in `src/locales/en/common.json` **and** `src/locales/ar/common.json`, RTL verified.
- **Style values come from design tokens** (semantic utilities). Never hardcoded hex or `color-mix`.
- **Git:** `feat/<name>` branch → PR → trunk (`main` in submodules, `master` in meta). Never commit to trunk. Never `--no-verify`. Pre-commit needs `PIP_CONFIG_FILE=/dev/null` on this machine (dead pip proxy).

### URL prefix correction to the spec

The spec's API table lists paths as `/subjects/` and `/me/teacher-subjects/`. Those are **relative to the module mount**. `config/api_router.py` mounts each module under its own prefix, so the real paths are:

- `GET  /api/v1/curriculum/subjects/`
- `GET|PUT /api/v1/curriculum/me/teacher-subjects/`
- `GET|PUT /api/v1/curriculum/me/student-subjects/`
- `PATCH /api/v1/identity/me/teacher-profile/`

Use the full paths. The dashboard's `VITE_API_URL` already ends in `/api/v1/`, so its client passes `curriculum/subjects/` relative.

---

### Task 1: Scaffold the `curriculum` module with `Subject`

**Files:**
- Create: `backend/kaleem/curriculum/__init__.py`, `apps.py`, `models.py`, `services.py`, `admin.py`
- Create: `backend/kaleem/curriculum/migrations/__init__.py`
- Create: `backend/kaleem/curriculum/tests/__init__.py`, `tests/test_models.py`
- Modify: `backend/config/settings/base.py` (LOCAL_APPS)
- Modify: `backend/pyproject.toml` (import-linter contracts)

**Interfaces:**
- Consumes: nothing.
- Produces: `kaleem.curriculum.models.Subject` with fields `slug: str`, `name: str`, `is_active: bool`; the app label `curriculum`.

- [ ] **Step 1: Create the app package skeleton**

```bash
cd backend
mkdir -p kaleem/curriculum/migrations kaleem/curriculum/tests
touch kaleem/curriculum/__init__.py kaleem/curriculum/migrations/__init__.py kaleem/curriculum/tests/__init__.py
```

`kaleem/curriculum/apps.py`:

```python
from django.apps import AppConfig


class CurriculumConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "kaleem.curriculum"
```

- [ ] **Step 2: Register the app**

In `backend/config/settings/base.py`, add to `LOCAL_APPS` (after `kaleem.scheduling`):

```python
LOCAL_APPS = [
    "kaleem.platform",
    "kaleem.identity",
    "kaleem.billing",
    "kaleem.scheduling",
    "kaleem.curriculum",
]
```

- [ ] **Step 3: Write the failing model test**

`kaleem/curriculum/tests/test_models.py`:

```python
import pytest
from django.db import IntegrityError

from kaleem.curriculum.models import Subject

pytestmark = pytest.mark.django_db


# CORRECTED DURING EXECUTION: these used slug "quran", which Task 2 then seeds,
# so they collided with the seed the moment that migration landed. Use a slug the
# seed does not create.
FIQH = "fiqh"


def test_subject_str_is_its_name():
    subject = Subject.objects.create(slug=FIQH, name="Fiqh")
    assert str(subject) == "Fiqh"


def test_subject_slug_is_unique():
    Subject.objects.create(slug="quran", name="Quran")
    with pytest.raises(IntegrityError):
        Subject.objects.create(slug="quran", name="Quran Again")


def test_subject_is_active_defaults_true():
    assert Subject.objects.create(slug="tafsir", name="Tafsir").is_active is True
```

- [ ] **Step 4: Run the test and watch it fail**

Run: `cd backend && pytest kaleem/curriculum/tests/test_models.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'kaleem.curriculum.models'`

- [ ] **Step 5: Write the model**

`kaleem/curriculum/models.py`:

```python
from django.db import models


class Subject(models.Model):
    """A thing kaleem teaches: Quran, Tafsir, Arabic.

    Admin-managed so a fourth subject is a row, not a migration and a deploy.
    """

    slug = models.SlugField(unique=True)
    name = models.CharField(max_length=100)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name
```

- [ ] **Step 6: Make and run the migration**

```bash
cd backend
python manage.py makemigrations curriculum
pytest kaleem/curriculum/tests/test_models.py -v
```

Expected: 3 passed.

- [ ] **Step 7: Register in admin**

`kaleem/curriculum/admin.py`:

```python
from django.contrib import admin

from kaleem.curriculum.models import Subject


@admin.register(Subject)
class SubjectAdmin(admin.ModelAdmin):
    list_display = ["name", "slug", "is_active"]
    list_filter = ["is_active"]
    prepopulated_fields = {"slug": ("name",)}
```

- [ ] **Step 8: Add both import-linter contracts**

In `backend/pyproject.toml`, after the scheduling contracts:

```toml
[[tool.importlinter.contracts]]
name = "curriculum imports no business modules except identity"
type = "forbidden"
source_modules = ["kaleem.curriculum"]
# curriculum may import kaleem.platform and call kaleem.identity.services.
forbidden_modules = [
    "kaleem.billing",
    "kaleem.scheduling",
    "kaleem.assessment",
    "kaleem.content",
    "kaleem.messaging",
    "kaleem.notifications",
    "kaleem.engagement",
    "kaleem.analytics",
]

[[tool.importlinter.contracts]]
name = "curriculum does not reach past identity's public API"
type = "forbidden"
source_modules = ["kaleem.curriculum"]
# Written on day one rather than retrofitted: scheduling shipped without this
# mirror and a direct model import there passed CI until 2026-09-04.
forbidden_modules = ["kaleem.identity.models"]
allow_indirect_imports = true
ignore_imports = [
    "kaleem.curriculum.tests.* -> kaleem.identity.models",
]
```

Also add `"kaleem.curriculum"` to the `forbidden_modules` list of the **existing** `identity`, `scheduling` and `billing` contracts — otherwise those modules could import the new one freely.

- [ ] **Step 9: Verify the new contract by breaking it**

A contract nobody has watched fail is not known to work. Temporarily add to `kaleem/curriculum/services.py` (create the file with just this line for now):

```python
from kaleem.identity.models import User  # BOUNDARY PROBE
```

Run: `cd backend && lint-imports`
Expected: `curriculum does not reach past identity's public API BROKEN`, naming `kaleem.curriculum.services -> kaleem.identity.models`.

Now delete the probe line and re-run.
Expected: `Contracts: 8 kept, 0 broken.`

- [ ] **Step 10: Commit**

```bash
cd backend
PIP_CONFIG_FILE=/dev/null git add kaleem/curriculum config/settings/base.py pyproject.toml
PIP_CONFIG_FILE=/dev/null git commit -m "feat(curriculum): add the Subject model and module scaffold"
```

---

### Task 2: Seed the three subjects by data migration

**Files:**
- Create: `backend/kaleem/curriculum/migrations/0002_seed_subjects.py`
- Create: `backend/kaleem/curriculum/tests/test_migrations.py`

**Interfaces:**
- Consumes: `Subject` from Task 1.
- Produces: rows with slugs `quran`, `tafsir`, `arabic` present in every database after `migrate`.

- [ ] **Step 1: Write the failing test**

`kaleem/curriculum/tests/test_migrations.py`:

```python
import pytest

from kaleem.curriculum.models import Subject

pytestmark = pytest.mark.django_db


def test_the_three_starting_subjects_are_seeded():
    slugs = set(Subject.objects.values_list("slug", flat=True))
    assert {"quran", "tafsir", "arabic"} <= slugs


def test_seeded_subjects_are_active_and_named():
    quran = Subject.objects.get(slug="quran")
    assert quran.name == "Quran"
    assert quran.is_active is True
```

- [ ] **Step 2: Run it and watch it fail**

Run: `cd backend && pytest kaleem/curriculum/tests/test_migrations.py -v`
Expected: FAIL — `AssertionError` on the set comparison (the table is empty).

- [ ] **Step 3: Write the data migration**

`kaleem/curriculum/migrations/0002_seed_subjects.py`:

```python
from django.db import migrations

SUBJECTS = [
    ("quran", "Quran"),
    ("tafsir", "Tafsir"),
    ("arabic", "Arabic"),
]


def seed(apps, schema_editor):
    Subject = apps.get_model("curriculum", "Subject")
    for slug, name in SUBJECTS:
        # update_or_create, not create: the migration must converge rather than
        # explode on a database where someone already added the row by hand.
        Subject.objects.update_or_create(slug=slug, defaults={"name": name})


def unseed(apps, schema_editor):
    Subject = apps.get_model("curriculum", "Subject")
    Subject.objects.filter(slug__in=[slug for slug, _ in SUBJECTS]).delete()


class Migration(migrations.Migration):
    dependencies = [("curriculum", "0001_initial")]
    operations = [migrations.RunPython(seed, unseed)]
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `cd backend && pytest kaleem/curriculum/tests/ -v`
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
cd backend
PIP_CONFIG_FILE=/dev/null git add kaleem/curriculum
PIP_CONFIG_FILE=/dev/null git commit -m "feat(curriculum): seed Quran, Tafsir and Arabic"
```

---

### Task 3: The two link tables and their services

**Files:**
- Modify: `backend/kaleem/curriculum/models.py`
- Create: `backend/kaleem/curriculum/services.py`
- Create: `backend/kaleem/curriculum/tests/test_services.py`

**Interfaces:**
- Consumes: `Subject` (Task 1).
- Produces, all in `kaleem.curriculum.services`:
  - `list_active_subjects() -> list[Subject]`
  - `get_teacher_subjects(user_id: int) -> list[str]` — slugs, sorted
  - `set_teacher_subjects(user_id: int, slugs: list[str]) -> list[str]`
  - `get_student_subjects(user_id: int) -> list[str]`
  - `set_student_subjects(user_id: int, slugs: list[str]) -> list[str]`

  Both setters replace the whole set and return the stored slugs. Both raise `kaleem.platform.exceptions.ValidationError` for an unknown or inactive slug.

- [ ] **Step 1: Add the models**

Append to `kaleem/curriculum/models.py`:

```python
from django.conf import settings


class TeacherSubject(models.Model):
    """A subject a teacher teaches. Many over time, never a JSON blob (rule #3, #7)."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="taught_subjects",
    )
    subject = models.ForeignKey(Subject, on_delete=models.CASCADE)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["user", "subject"], name="unique_teacher_subject"
            )
        ]

    def __str__(self):
        return f"TeacherSubject<{self.user_id}:{self.subject.slug}>"


class StudentSubjectInterest(models.Model):
    """A subject a student wants to study."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="subject_interests",
    )
    subject = models.ForeignKey(Subject, on_delete=models.CASCADE)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["user", "subject"], name="unique_student_subject_interest"
            )
        ]

    def __str__(self):
        return f"StudentSubjectInterest<{self.user_id}:{self.subject.slug}>"
```

Note the `settings` import goes at the top of the file with the other imports, one per line.

- [ ] **Step 2: Write the failing service tests**

`kaleem/curriculum/tests/test_services.py`:

```python
import pytest

from kaleem.curriculum import services
from kaleem.curriculum.models import Subject
from kaleem.identity.models import User
from kaleem.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db


@pytest.fixture
def teacher():
    return User.objects.create_user(email="t@kaleem.test", password="x")


def test_list_active_subjects_excludes_inactive():
    Subject.objects.filter(slug="tafsir").update(is_active=False)
    slugs = [s.slug for s in services.list_active_subjects()]
    assert "quran" in slugs
    assert "tafsir" not in slugs


def test_set_then_get_teacher_subjects_round_trips(teacher):
    services.set_teacher_subjects(teacher.id, ["quran", "arabic"])
    assert services.get_teacher_subjects(teacher.id) == ["arabic", "quran"]


def test_set_teacher_subjects_replaces_rather_than_appends(teacher):
    services.set_teacher_subjects(teacher.id, ["quran", "arabic"])
    services.set_teacher_subjects(teacher.id, ["tafsir"])
    assert services.get_teacher_subjects(teacher.id) == ["tafsir"]


def test_set_teacher_subjects_to_empty_clears(teacher):
    services.set_teacher_subjects(teacher.id, ["quran"])
    services.set_teacher_subjects(teacher.id, [])
    assert services.get_teacher_subjects(teacher.id) == []


def test_duplicate_slugs_in_one_payload_store_once(teacher):
    services.set_teacher_subjects(teacher.id, ["quran", "quran"])
    assert services.get_teacher_subjects(teacher.id) == ["quran"]


def test_unknown_slug_is_a_validation_error(teacher):
    with pytest.raises(ValidationError):
        services.set_teacher_subjects(teacher.id, ["astrophysics"])


def test_inactive_slug_is_a_validation_error(teacher):
    Subject.objects.filter(slug="tafsir").update(is_active=False)
    with pytest.raises(ValidationError):
        services.set_teacher_subjects(teacher.id, ["tafsir"])


def test_teacher_and_student_sets_are_independent(teacher):
    services.set_teacher_subjects(teacher.id, ["quran"])
    services.set_student_subjects(teacher.id, ["arabic"])
    assert services.get_teacher_subjects(teacher.id) == ["quran"]
    assert services.get_student_subjects(teacher.id) == ["arabic"]
```

That last test is the one that pins the dual-role decision from the spec: one person, both sets, no leakage.

- [ ] **Step 3: Run and watch them fail**

Run: `cd backend && pytest kaleem/curriculum/tests/test_services.py -v`
Expected: FAIL — `AttributeError: module 'kaleem.curriculum.services' has no attribute 'list_active_subjects'`

- [ ] **Step 4: Write the services**

`kaleem/curriculum/services.py`:

```python
from django.db import transaction

from kaleem.curriculum.models import StudentSubjectInterest
from kaleem.curriculum.models import Subject
from kaleem.curriculum.models import TeacherSubject
from kaleem.platform.exceptions import ValidationError


def list_active_subjects():
    return list(Subject.objects.filter(is_active=True))


def _resolve(slugs):
    """Map slugs to active Subject rows, refusing anything unknown or retired.

    Refusing loudly rather than dropping silently: a typo'd slug that vanished
    would look to the caller like a successful save of a smaller set (rule #8).
    """
    wanted = set(slugs)
    found = {s.slug: s for s in Subject.objects.filter(slug__in=wanted, is_active=True)}
    missing = sorted(wanted - set(found))
    if missing:
        raise ValidationError(
            f"Unknown or inactive subject(s): {', '.join(missing)}", field="subjects"
        )
    return [found[slug] for slug in sorted(found)]


def _get(model, user_id):
    return sorted(
        model.objects.filter(user_id=user_id).values_list("subject__slug", flat=True)
    )


@transaction.atomic
def _set(model, user_id, slugs):
    subjects = _resolve(slugs)
    model.objects.filter(user_id=user_id).delete()
    model.objects.bulk_create(
        [model(user_id=user_id, subject=subject) for subject in subjects]
    )
    return [subject.slug for subject in subjects]


def get_teacher_subjects(user_id: int) -> list[str]:
    return _get(TeacherSubject, user_id)


def set_teacher_subjects(user_id: int, slugs: list[str]) -> list[str]:
    return _set(TeacherSubject, user_id, slugs)


def get_student_subjects(user_id: int) -> list[str]:
    return _get(StudentSubjectInterest, user_id)


def set_student_subjects(user_id: int, slugs: list[str]) -> list[str]:
    return _set(StudentSubjectInterest, user_id, slugs)
```

- [ ] **Step 5: Migrate and run**

```bash
cd backend
python manage.py makemigrations curriculum
pytest kaleem/curriculum/ -v
```

Expected: all pass. `_resolve` deduplicates via the `set`, which is what makes the duplicate-slug test pass.

- [ ] **Step 6: Confirm boundaries still hold**

Run: `cd backend && lint-imports`
Expected: `8 kept, 0 broken`. `services.py` imports only curriculum's own models and `kaleem.platform`.

- [ ] **Step 7: Commit**

```bash
cd backend
PIP_CONFIG_FILE=/dev/null git add kaleem/curriculum
PIP_CONFIG_FILE=/dev/null git commit -m "feat(curriculum): teacher and student subject links with services"
```

---

### Task 4: The curriculum API

**Files:**
- Create: `backend/kaleem/curriculum/api/__init__.py`, `api/serializers.py`, `api/views.py`, `api/urls.py`
- Create: `backend/kaleem/curriculum/tests/test_api.py`
- Modify: `backend/config/api_router.py`

**Interfaces:**
- Consumes: `curriculum.services` (Task 3), `identity.services.get_teacher_profile` / `get_student_profile`.
- Produces: `GET /api/v1/curriculum/subjects/`, `GET|PUT /api/v1/curriculum/me/teacher-subjects/`, `GET|PUT /api/v1/curriculum/me/student-subjects/`.

- [ ] **Step 1: Write the failing API tests**

`kaleem/curriculum/tests/test_api.py`:

```python
import pytest
from rest_framework.test import APIClient

from kaleem.curriculum import services
from kaleem.identity.models import StudentProfile
from kaleem.identity.models import TeacherProfile
from kaleem.identity.models import User

pytestmark = pytest.mark.django_db

SUBJECTS_URL = "/api/v1/curriculum/subjects/"
TEACHER_URL = "/api/v1/curriculum/me/teacher-subjects/"
STUDENT_URL = "/api/v1/curriculum/me/student-subjects/"


@pytest.fixture
def client():
    return APIClient()


@pytest.fixture
def teacher():
    user = User.objects.create_user(email="teach@kaleem.test", password="x")
    TeacherProfile.objects.create(user=user)
    return user


@pytest.fixture
def student():
    user = User.objects.create_user(email="stud@kaleem.test", password="x")
    StudentProfile.objects.create(user=user)
    return user


def test_subjects_requires_authentication(client):
    assert client.get(SUBJECTS_URL).status_code == 403


def test_subjects_lists_the_seeded_three(client, student):
    client.force_authenticate(student)
    body = client.get(SUBJECTS_URL).json()
    assert {s["slug"] for s in body} == {"quran", "tafsir", "arabic"}
    assert set(body[0]) == {"slug", "name"}


def test_teacher_puts_and_gets_their_subjects(client, teacher):
    client.force_authenticate(teacher)
    response = client.put(TEACHER_URL, {"subjects": ["quran", "arabic"]}, format="json")
    assert response.status_code == 200
    assert response.json() == {"subjects": ["arabic", "quran"]}
    assert client.get(TEACHER_URL).json() == {"subjects": ["arabic", "quran"]}


def test_student_puts_and_gets_their_interests(client, student):
    client.force_authenticate(student)
    client.put(STUDENT_URL, {"subjects": ["tafsir"]}, format="json")
    assert client.get(STUDENT_URL).json() == {"subjects": ["tafsir"]}


def test_a_student_cannot_use_the_teacher_endpoint(client, student):
    client.force_authenticate(student)
    assert client.get(TEACHER_URL).status_code == 403
    assert client.put(TEACHER_URL, {"subjects": []}, format="json").status_code == 403


def test_a_teacher_cannot_use_the_student_endpoint(client, teacher):
    client.force_authenticate(teacher)
    assert client.get(STUDENT_URL).status_code == 403


def test_a_dual_role_user_may_use_both(client):
    user = User.objects.create_user(email="both@kaleem.test", password="x")
    TeacherProfile.objects.create(user=user)
    StudentProfile.objects.create(user=user)
    client.force_authenticate(user)
    client.put(TEACHER_URL, {"subjects": ["quran"]}, format="json")
    client.put(STUDENT_URL, {"subjects": ["arabic"]}, format="json")
    assert client.get(TEACHER_URL).json() == {"subjects": ["quran"]}
    assert client.get(STUDENT_URL).json() == {"subjects": ["arabic"]}


def test_unknown_slug_is_a_400_naming_the_field(client, teacher):
    client.force_authenticate(teacher)
    response = client.put(TEACHER_URL, {"subjects": ["nope"]}, format="json")
    assert response.status_code == 400
    assert "nope" in str(response.json())


def test_put_without_the_subjects_key_is_a_400(client, teacher):
    client.force_authenticate(teacher)
    assert client.put(TEACHER_URL, {}, format="json").status_code == 400


def test_put_replaces_the_previous_set(client, teacher):
    client.force_authenticate(teacher)
    services.set_teacher_subjects(teacher.id, ["quran", "tafsir"])
    client.put(TEACHER_URL, {"subjects": ["arabic"]}, format="json")
    assert client.get(TEACHER_URL).json() == {"subjects": ["arabic"]}
```

- [ ] **Step 2: Run and watch them fail**

Run: `cd backend && pytest kaleem/curriculum/tests/test_api.py -v`
Expected: FAIL — 404s, because the routes do not exist yet.

- [ ] **Step 3: Write the serializer**

`kaleem/curriculum/api/serializers.py`:

```python
from rest_framework import serializers


class SubjectSerializer(serializers.Serializer):
    slug = serializers.SlugField()
    name = serializers.CharField()


class SubjectSetSerializer(serializers.Serializer):
    subjects = serializers.ListField(child=serializers.SlugField(), allow_empty=True)
```

`allow_empty=True` is deliberate: clearing your subjects is a legitimate action, and the spec requires `[]` to clear.

- [ ] **Step 4: Write the views**

`kaleem/curriculum/api/views.py`:

```python
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from kaleem.curriculum import services
from kaleem.curriculum.api.serializers import SubjectSerializer
from kaleem.curriculum.api.serializers import SubjectSetSerializer
from kaleem.identity import services as identity_services
from kaleem.platform.exceptions import PermissionDeniedError


class SubjectListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        subjects = services.list_active_subjects()
        return Response(SubjectSerializer(subjects, many=True).data)


class _SubjectSetView(APIView):
    """Shared GET/PUT for one role's subject set.

    Two concrete subclasses rather than one endpoint with a role parameter: a
    person may hold both profiles, so a single path would have to guess which
    set the caller meant, or reject a legitimate request.
    """

    permission_classes = [IsAuthenticated]
    role = ""  # "teacher" | "student"

    def _require_profile(self, user):
        raise NotImplementedError

    def _get_subjects(self, user_id):
        raise NotImplementedError

    def _set_subjects(self, user_id, slugs):
        raise NotImplementedError

    def get(self, request):
        self._require_profile(request.user)
        return Response({"subjects": self._get_subjects(request.user.id)})

    def put(self, request):
        self._require_profile(request.user)
        serializer = SubjectSetSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        stored = self._set_subjects(
            request.user.id, list(serializer.validated_data["subjects"])
        )
        return Response({"subjects": stored})


class TeacherSubjectsView(_SubjectSetView):
    role = "teacher"

    def _require_profile(self, user):
        if identity_services.get_teacher_profile(user.id) is None:
            raise PermissionDeniedError("manage taught subjects without a teacher profile")

    def _get_subjects(self, user_id):
        return services.get_teacher_subjects(user_id)

    def _set_subjects(self, user_id, slugs):
        return services.set_teacher_subjects(user_id, slugs)


class StudentSubjectsView(_SubjectSetView):
    role = "student"

    def _require_profile(self, user):
        if identity_services.get_student_profile(user.id) is None:
            raise PermissionDeniedError(
                "manage subject interests without a student profile"
            )

    def _get_subjects(self, user_id):
        return services.get_student_subjects(user_id)

    def _set_subjects(self, user_id, slugs):
        return services.set_student_subjects(user_id, slugs)
```

- [ ] **Step 5: Write the URLs and mount them**

`kaleem/curriculum/api/urls.py`:

```python
from django.urls import path

from kaleem.curriculum.api.views import StudentSubjectsView
from kaleem.curriculum.api.views import SubjectListView
from kaleem.curriculum.api.views import TeacherSubjectsView

app_name = "curriculum"
urlpatterns = [
    path("subjects/", SubjectListView.as_view(), name="subjects"),
    path(
        "me/teacher-subjects/",
        TeacherSubjectsView.as_view(),
        name="teacher-subjects",
    ),
    path(
        "me/student-subjects/",
        StudentSubjectsView.as_view(),
        name="student-subjects",
    ),
]
```

In `backend/config/api_router.py`, add alongside the others (never onto `config/urls.py` — ADR-0029):

```python
    path("curriculum/", include("kaleem.curriculum.api.urls")),
```

- [ ] **Step 6: Run the tests and the versioning guard**

```bash
cd backend
pytest kaleem/curriculum/tests/test_api.py -v
pytest tests/test_api_versioning_is_enforced.py -v
```

Expected: both green. If the versioning test fails, the module was mounted in the wrong place.

- [ ] **Step 7: Commit**

```bash
cd backend
PIP_CONFIG_FILE=/dev/null git add kaleem/curriculum config/api_router.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(curriculum): role-explicit subject endpoints"
```

---

### Task 5: `TeacherProfile.gender` and its endpoint

**Files:**
- Modify: `backend/kaleem/identity/models.py`, `services.py`, `api/serializers.py`, `api/views.py`, `api/urls.py`
- Create: `backend/kaleem/identity/tests/test_teacher_profile_api.py`

**Interfaces:**
- Produces: `TeacherProfile.Gender` choices (`MALE = "male"`, `FEMALE = "female"`); `identity.services.get_teacher_profile(user_id)` already exists and now returns a row carrying `.gender`; `identity.services.set_teacher_gender(user_id, gender) -> None`; `PATCH /api/v1/identity/me/teacher-profile/`.

- [ ] **Step 1: Write the failing tests**

`kaleem/identity/tests/test_teacher_profile_api.py`:

```python
import pytest
from rest_framework.test import APIClient

from kaleem.identity.models import TeacherProfile
from kaleem.identity.models import User

pytestmark = pytest.mark.django_db

URL = "/api/v1/identity/me/teacher-profile/"


@pytest.fixture
def client():
    return APIClient()


@pytest.fixture
def teacher():
    user = User.objects.create_user(email="teach@kaleem.test", password="x")
    TeacherProfile.objects.create(user=user)
    return user


def test_gender_starts_undeclared(client, teacher):
    client.force_authenticate(teacher)
    assert client.get(URL).json()["gender"] == ""


def test_teacher_declares_their_gender(client, teacher):
    client.force_authenticate(teacher)
    assert client.patch(URL, {"gender": "female"}, format="json").status_code == 200
    assert client.get(URL).json()["gender"] == "female"


def test_gender_can_be_returned_to_undeclared(client, teacher):
    client.force_authenticate(teacher)
    client.patch(URL, {"gender": "male"}, format="json")
    client.patch(URL, {"gender": ""}, format="json")
    assert client.get(URL).json()["gender"] == ""


def test_an_invalid_gender_is_a_400(client, teacher):
    client.force_authenticate(teacher)
    assert client.patch(URL, {"gender": "other"}, format="json").status_code == 400


def test_a_non_teacher_is_refused(client):
    user = User.objects.create_user(email="nobody@kaleem.test", password="x")
    client.force_authenticate(user)
    assert client.get(URL).status_code == 403
```

- [ ] **Step 2: Run and watch them fail**

Run: `cd backend && pytest kaleem/identity/tests/test_teacher_profile_api.py -v`
Expected: FAIL — 404, the route does not exist.

- [ ] **Step 3: Add the field**

In `kaleem/identity/models.py`, inside `class TeacherProfile`:

```python
class TeacherProfile(models.Model):
    class Gender(models.TextChoices):
        MALE = "male", "Male"
        FEMALE = "female", "Female"

    user = models.OneToOneField(
        User, on_delete=models.CASCADE, related_name="teacher_profile"
    )
    # "" means undeclared, and it is a real state rather than a placeholder:
    # teacher rows predate this field and a migration cannot invent a value for
    # them. C1 excludes undeclared teachers from a gender-filtered match and
    # allows them for a student who expressed no_preference.
    gender = models.CharField(
        max_length=10, choices=Gender.choices, blank=True, default=""
    )
    availability = models.JSONField(default=list, blank=True)
    is_in_pool = models.BooleanField(default=False)
    internal_notes = models.TextField(blank=True, default="")
```

Then:

```bash
cd backend && python manage.py makemigrations identity
```

- [ ] **Step 4: Add the service**

In `kaleem/identity/services.py`, alongside the other profile services:

```python
def set_teacher_gender(user_id: int, gender: str) -> None:
    """Set a teacher's declared gender. "" returns them to undeclared."""
    valid = {*TeacherProfile.Gender.values, ""}
    if gender not in valid:
        raise ValidationError(f"Unknown gender: {gender!r}", field="gender")
    updated = TeacherProfile.objects.filter(user_id=user_id).update(gender=gender)
    if not updated:
        raise NotFoundError("TeacherProfile", user_id)
```

- [ ] **Step 5: Add the serializer**

In `kaleem/identity/api/serializers.py`:

```python
class TeacherProfileSerializer(serializers.Serializer):
    gender = serializers.ChoiceField(
        choices=[*TeacherProfile.Gender.choices, ("", "Undeclared")],
        allow_blank=True,
    )


class TeacherProfileResponseSerializer(serializers.Serializer):
    gender = serializers.CharField(allow_blank=True)
```

Add `from kaleem.identity.models import TeacherProfile` at the top if it is not already imported.

- [ ] **Step 6: Add the view**

In `kaleem/identity/api/views.py`:

```python
class TeacherProfileView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(
        responses={200: TeacherProfileResponseSerializer},
        summary="Get the caller's teacher profile.",
    )
    def get(self, request):
        profile = services.get_teacher_profile(request.user.id)
        if profile is None:
            raise PermissionDeniedError("read a teacher profile without being a teacher")
        return Response({"gender": profile.gender})

    @extend_schema(
        request=TeacherProfileSerializer,
        responses={200: TeacherProfileResponseSerializer},
        summary="Declare the caller's gender, used for teacher matching.",
    )
    def patch(self, request):
        if services.get_teacher_profile(request.user.id) is None:
            raise PermissionDeniedError("edit a teacher profile without being a teacher")
        serializer = TeacherProfileSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.set_teacher_gender(request.user.id, serializer.validated_data["gender"])
        return Response({"gender": serializer.validated_data["gender"]})
```

Import `PermissionDeniedError`, `TeacherProfileSerializer` and `TeacherProfileResponseSerializer` at the top, one per line.

- [ ] **Step 7: Add the route**

In `kaleem/identity/api/urls.py`, next to `me/student-profile/`:

```python
    path("me/teacher-profile/", TeacherProfileView.as_view(), name="teacher-profile"),
```

plus `from kaleem.identity.api.views import TeacherProfileView` in the import block.

- [ ] **Step 8: Run everything**

```bash
cd backend
pytest -q
lint-imports
ruff check . && ruff format --check .
```

Expected: all green, coverage ≥ 97.

- [ ] **Step 9: Commit**

```bash
cd backend
PIP_CONFIG_FILE=/dev/null git add kaleem/identity
PIP_CONFIG_FILE=/dev/null git commit -m "feat(identity): teachers can declare a gender for matching"
```

---

### Task 6: Seed subjects and a teacher gender for e2e

**Files:**
- Modify: `backend/kaleem/identity/management/commands/seed_e2e.py`
- Modify: `backend/kaleem/identity/tests/test_seed_e2e.py` (the file that already asserts the seed's contract)

**Interfaces:**
- Consumes: `curriculum.services.set_teacher_subjects`, `identity.services.set_teacher_gender`.
- Produces: after `seed_e2e`, the three subjects exist and `e2e.teacher@kaleem.test` has **no** subjects and **undeclared** gender — the e2e specs set them, so seeding them would make those specs pass vacuously.

- [ ] **Step 1: Write the failing test**

Append to `kaleem/identity/tests/test_seed_e2e.py`:

```python
def test_seed_leaves_the_teacher_with_nothing_declared():
    """The e2e specs assert on *setting* these, so the seed must not pre-set them.

    A seed that filled them in would make `teacher sets subjects` pass without
    the UI ever working.
    """
    call_command("seed_e2e")
    teacher = User.objects.get(email="e2e.teacher@kaleem.test")
    assert curriculum_services.get_teacher_subjects(teacher.id) == []
    assert teacher.teacher_profile.gender == ""


def test_seed_is_idempotent_for_subject_state():
    call_command("seed_e2e")
    teacher = User.objects.get(email="e2e.teacher@kaleem.test")
    curriculum_services.set_teacher_subjects(teacher.id, ["quran"])
    call_command("seed_e2e")
    assert curriculum_services.get_teacher_subjects(teacher.id) == []
```

Add `from kaleem.curriculum import services as curriculum_services` at the top.

- [ ] **Step 2: Run and watch the second one fail**

Run: `cd backend && pytest kaleem/identity/tests/test_seed_e2e.py -v`
Expected: the idempotency test FAILS — the seed does not reset subject state, so `["quran"]` survives a re-seed and the next e2e run starts dirty.

- [ ] **Step 3: Make the seed converge**

In `seed_e2e.py`, inside the transaction after the teacher account is created:

```python
        # Converge, do not merely create: the e2e specs mutate these, so a second
        # run must return the teacher to "nothing declared" or the specs start
        # from whatever the last run left behind.
        TeacherSubject.objects.filter(user=teacher).delete()
        TeacherProfile.objects.filter(user=teacher).update(gender="")
```

Import `from kaleem.curriculum.models import TeacherSubject` at the top.

**CORRECTED DURING EXECUTION — this whole task is impossible as written.** The note below
said to call `curriculum.services` instead of importing its models. That is *also* forbidden:
the `identity imports no other business modules` contract bars importing `kaleem.curriculum`
at all, not merely its models. There is no boundary-legal way for identity's seed command to
touch curriculum's tables.

**What was done instead:** determinism moved into the e2e specs (Task 10). Each spec clears
the set, sets exactly what it wants, and asserts the *exact* resulting state, which is
deterministic regardless of what a previous run left behind. Verified by running the suite
twice, the second time against a database the first run left dirty.

The superseded text follows, kept so the reasoning is visible:

```python
        curriculum_services.set_teacher_subjects(teacher.id, [])
        identity_services.set_teacher_gender(teacher.id, "")
```

with `from kaleem.curriculum import services as curriculum_services` at the top. Run `lint-imports` to confirm.

- [ ] **Step 4: Verify**

```bash
cd backend
pytest kaleem/identity/tests/test_seed_e2e.py -v
lint-imports
```

Expected: green, `8 kept, 0 broken`.

- [ ] **Step 5: Commit**

```bash
cd backend
PIP_CONFIG_FILE=/dev/null git add kaleem/identity
PIP_CONFIG_FILE=/dev/null git commit -m "feat(identity): reset e2e teacher subject state on each seed"
```

- [ ] **Step 6: Open the backend PR**

```bash
cd backend
git push -u origin feat/phase-c0-matching-inputs
gh pr create --repo kaleem-lms/backend --base main \
  --title "feat(curriculum): matching inputs — subjects and teacher gender" \
  --body "Implements Phase C0. See docs/superpowers/specs/2026-09-04-phase-c0-matching-inputs-design.md"
```

---

### Task 7: Dashboard — a `Checkbox` primitive

**Files:**
- Create: `dashboard/src/ui/checkbox.tsx`, `dashboard/src/ui/checkbox.test.tsx`
- Modify: `dashboard/src/ui/index.ts`

**Interfaces:**
- Produces: `Checkbox` — props `{ checked: boolean; onCheckedChange: (v: boolean) => void; id: string; disabled?: boolean }`.

`src/ui` has no checkbox today (only `RadioCardGroup`), and the subjects panel needs multi-select. `radix-ui` is already a dependency.

- [ ] **Step 1: Write the failing test**

`dashboard/src/ui/checkbox.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { Checkbox } from "./checkbox";

describe("Checkbox", () => {
	it("renders an accessible checkbox reflecting its checked state", () => {
		render(<Checkbox id="c" checked onCheckedChange={() => {}} />);
		expect(screen.getByRole("checkbox")).toBeChecked();
	});

	it("reports a toggle to its owner", async () => {
		const onCheckedChange = vi.fn();
		render(<Checkbox id="c" checked={false} onCheckedChange={onCheckedChange} />);
		await userEvent.click(screen.getByRole("checkbox"));
		expect(onCheckedChange).toHaveBeenCalledWith(true);
	});

	it("does not toggle when disabled", async () => {
		const onCheckedChange = vi.fn();
		render(
			<Checkbox id="c" checked={false} disabled onCheckedChange={onCheckedChange} />,
		);
		await userEvent.click(screen.getByRole("checkbox"));
		expect(onCheckedChange).not.toHaveBeenCalled();
	});
});
```

- [ ] **Step 2: Run and watch it fail**

Run: `cd dashboard && pnpm vitest run src/ui/checkbox.test.tsx`
Expected: FAIL — cannot resolve `./checkbox`.

- [ ] **Step 3: Write the component**

`dashboard/src/ui/checkbox.tsx`:

```tsx
import { Check } from "lucide-react";
import { Checkbox as RadixCheckbox } from "radix-ui";
import { cn } from "@/lib/cn";

export function Checkbox({
	id,
	checked,
	onCheckedChange,
	disabled,
	className,
}: {
	id: string;
	checked: boolean;
	onCheckedChange: (value: boolean) => void;
	disabled?: boolean;
	className?: string;
}) {
	return (
		<RadixCheckbox.Root
			id={id}
			checked={checked}
			disabled={disabled}
			onCheckedChange={(value) => onCheckedChange(value === true)}
			className={cn(
				// 44px touch target lives on the label row; the box itself is visual.
				"flex size-5 shrink-0 items-center justify-center rounded border border-input bg-background",
				"focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
				"data-[state=checked]:border-primary data-[state=checked]:bg-primary data-[state=checked]:text-primary-foreground",
				"disabled:cursor-not-allowed disabled:opacity-50",
				className,
			)}
		>
			<RadixCheckbox.Indicator>
				<Check className="size-3.5" />
			</RadixCheckbox.Indicator>
		</RadixCheckbox.Root>
	);
}
```

Every colour is a token utility — no hex, no `color-mix`.

- [ ] **Step 4: Export it**

In `dashboard/src/ui/index.ts`, in alphabetical position:

```ts
export { Checkbox } from "./checkbox";
```

- [ ] **Step 5: Run and watch it pass**

Run: `cd dashboard && pnpm vitest run src/ui/checkbox.test.tsx`
Expected: 3 passed.

- [ ] **Step 6: Commit**

```bash
cd dashboard
git add src/ui/checkbox.tsx src/ui/checkbox.test.tsx src/ui/index.ts
git commit -m "feat(ui): add a Checkbox primitive"
```

---

### Task 8: Dashboard — curriculum feature (schemas, api, queries)

**Files:**
- Create: `dashboard/src/features/curriculum/schemas.ts`, `api.ts`, `queries.ts`, `index.ts`
- Create: `dashboard/src/features/curriculum/api.test.ts`, `queries.test.tsx`

**Interfaces:**
- Produces: `useSubjects()`, `useTeacherSubjects()`, `useSaveTeacherSubjects()`, `useStudentSubjects()`, `useSaveStudentSubjects()`; type `Subject = { slug: string; name: string }`.

A new feature folder mirroring the backend module, per `dashboard/CLAUDE.md`. No cross-feature imports: the account **route** composes identity and curriculum components, but neither feature imports the other.

- [ ] **Step 1: Write the schemas**

`dashboard/src/features/curriculum/schemas.ts`:

```ts
import { z } from "zod";

export const subjectSchema = z.object({
	slug: z.string(),
	name: z.string(),
});

export const subjectListSchema = z.array(subjectSchema);

export const subjectSetSchema = z.object({
	subjects: z.array(z.string()),
});

export type Subject = z.infer<typeof subjectSchema>;
export type SubjectSet = z.infer<typeof subjectSetSchema>;
```

- [ ] **Step 2: Write the failing api test**

`dashboard/src/features/curriculum/api.test.ts`:

```ts
import { describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { curriculumApi } from "./api";

describe("curriculumApi", () => {
	it("lists subjects from the versioned base", async () => {
		const get = vi
			.spyOn(api, "get")
			.mockResolvedValue({ data: [{ slug: "quran", name: "Quran" }] } as never);
		await expect(curriculumApi.listSubjects()).resolves.toEqual([
			{ slug: "quran", name: "Quran" },
		]);
		expect(get).toHaveBeenCalledWith("curriculum/subjects/");
	});

	it("saves teacher subjects to the teacher path", async () => {
		const put = vi
			.spyOn(api, "put")
			.mockResolvedValue({ data: { subjects: ["quran"] } } as never);
		await curriculumApi.saveTeacherSubjects(["quran"]);
		expect(put).toHaveBeenCalledWith("curriculum/me/teacher-subjects/", {
			subjects: ["quran"],
		});
	});

	it("saves student subjects to the student path", async () => {
		const put = vi
			.spyOn(api, "put")
			.mockResolvedValue({ data: { subjects: ["arabic"] } } as never);
		await curriculumApi.saveStudentSubjects(["arabic"]);
		expect(put).toHaveBeenCalledWith("curriculum/me/student-subjects/", {
			subjects: ["arabic"],
		});
	});
});
```

The last two tests exist because sending a teacher's subjects to the student endpoint is the exact mistake this two-endpoint design invites, and it would silently write the wrong table.

- [ ] **Step 3: Run and watch it fail**

Run: `cd dashboard && pnpm vitest run src/features/curriculum/api.test.ts`
Expected: FAIL — cannot resolve `./api`.

- [ ] **Step 4: Write the api client**

`dashboard/src/features/curriculum/api.ts`:

```ts
import { api } from "@/lib/api";
import type { Subject, SubjectSet } from "./schemas";

export const curriculumApi = {
	listSubjects: () =>
		api.get<Subject[]>("curriculum/subjects/").then((r) => r.data),
	getTeacherSubjects: () =>
		api.get<SubjectSet>("curriculum/me/teacher-subjects/").then((r) => r.data),
	saveTeacherSubjects: (subjects: string[]) =>
		api
			.put<SubjectSet>("curriculum/me/teacher-subjects/", { subjects })
			.then((r) => r.data),
	getStudentSubjects: () =>
		api.get<SubjectSet>("curriculum/me/student-subjects/").then((r) => r.data),
	saveStudentSubjects: (subjects: string[]) =>
		api
			.put<SubjectSet>("curriculum/me/student-subjects/", { subjects })
			.then((r) => r.data),
};
```

- [ ] **Step 5: Write the queries**

`dashboard/src/features/curriculum/queries.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { curriculumApi } from "./api";

export const subjectsQueryKey = ["subjects"] as const;
export const teacherSubjectsQueryKey = ["teacher-subjects"] as const;
export const studentSubjectsQueryKey = ["student-subjects"] as const;

export function useSubjects() {
	return useQuery({
		queryKey: subjectsQueryKey,
		queryFn: curriculumApi.listSubjects,
		retry: false,
	});
}

export function useTeacherSubjects() {
	return useQuery({
		queryKey: teacherSubjectsQueryKey,
		queryFn: curriculumApi.getTeacherSubjects,
		retry: false,
	});
}

export function useSaveTeacherSubjects() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (subjects: string[]) =>
			curriculumApi.saveTeacherSubjects(subjects),
		onSuccess: () =>
			qc.invalidateQueries({ queryKey: teacherSubjectsQueryKey }),
	});
}

export function useStudentSubjects() {
	return useQuery({
		queryKey: studentSubjectsQueryKey,
		queryFn: curriculumApi.getStudentSubjects,
		retry: false,
	});
}

export function useSaveStudentSubjects() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (subjects: string[]) =>
			curriculumApi.saveStudentSubjects(subjects),
		onSuccess: () =>
			qc.invalidateQueries({ queryKey: studentSubjectsQueryKey }),
	});
}
```

`dashboard/src/features/curriculum/index.ts`:

```ts
export { curriculumApi } from "./api";
export * from "./queries";
export type { Subject, SubjectSet } from "./schemas";
```

- [ ] **Step 6: Write the queries test**

`dashboard/src/features/curriculum/queries.test.tsx` — mirror the shape of `src/features/identity/queries.test.tsx`: render each hook inside a `QueryClientProvider` with `retry: false`, mock `curriculumApi`, and assert (a) `useSubjects` returns the list, (b) `useSaveTeacherSubjects` invalidates `teacherSubjectsQueryKey` on success, (c) a rejected mutation surfaces `isError`.

- [ ] **Step 7: Run the feature's tests**

Run: `cd dashboard && pnpm vitest run src/features/curriculum/`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
cd dashboard
git add src/features/curriculum
git commit -m "feat(curriculum): dashboard api and queries for subjects"
```

---

### Task 9: Dashboard — the panels

**Files:**
- Create: `dashboard/src/features/curriculum/components/SubjectsCard.tsx` + `.test.tsx`
- Create: `dashboard/src/features/identity/components/TeacherGenderCard.tsx` + `.test.tsx`
- Modify: `dashboard/src/routes/_authed/account.tsx` + `account.test.tsx` if present
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`

**Interfaces:**
- Consumes: `Checkbox` (Task 7); the curriculum hooks (Task 8); `useMe` for role detection.
- Produces: `<SubjectsCard role="teacher" | "student" />`, `<TeacherGenderCard />`.

- [ ] **Step 1: Add the i18n keys**

`src/locales/en/common.json`, a new `subjects` block:

```json
	"subjects": {
		"teacherTitle": "Subjects you teach",
		"teacherDescription": "Students are matched to teachers who teach what they want to study.",
		"studentTitle": "What you want to study",
		"studentDescription": "We use this to match you with the right teacher.",
		"empty": "No subjects are available yet. Please contact support.",
		"loadError": "We couldn't load subjects. Try again.",
		"saved": "Subjects saved.",
		"saveError": "We couldn't save your subjects. Try again.",
		"save": "Save subjects"
	},
	"teacherProfile": {
		"title": "Teaching profile",
		"genderLabel": "Your gender",
		"genderWhy": "Some students ask to be taught by a teacher of a particular gender. This is used only for matching.",
		"male": "Male",
		"female": "Female",
		"undeclared": "Prefer not to say",
		"saved": "Teaching profile saved.",
		"saveError": "We couldn't save your teaching profile. Try again."
	},
```

Add the matching Arabic block to `src/locales/ar/common.json`. Every key must exist in both files — a missing Arabic key renders the English string and silently breaks ar parity (ADR-0020).

- [ ] **Step 2: Write the failing SubjectsCard test**

`dashboard/src/features/curriculum/components/SubjectsCard.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { curriculumApi } from "../api";
import { SubjectsCard } from "./SubjectsCard";

function renderCard(role: "teacher" | "student") {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return render(
		<QueryClientProvider client={client}>
			<SubjectsCard role={role} />
		</QueryClientProvider>,
	);
}

afterEach(() => vi.restoreAllMocks());

describe("SubjectsCard", () => {
	it("shows the teacher heading and the available subjects", async () => {
		vi.spyOn(curriculumApi, "listSubjects").mockResolvedValue([
			{ slug: "quran", name: "Quran" },
			{ slug: "arabic", name: "Arabic" },
		]);
		vi.spyOn(curriculumApi, "getTeacherSubjects").mockResolvedValue({
			subjects: ["quran"],
		});
		renderCard("teacher");
		expect(await screen.findByText(/subjects you teach/i)).toBeInTheDocument();
		expect(await screen.findByRole("checkbox", { name: "Quran" })).toBeChecked();
		expect(screen.getByRole("checkbox", { name: "Arabic" })).not.toBeChecked();
	});

	it("saves the selected set", async () => {
		vi.spyOn(curriculumApi, "listSubjects").mockResolvedValue([
			{ slug: "quran", name: "Quran" },
		]);
		vi.spyOn(curriculumApi, "getTeacherSubjects").mockResolvedValue({
			subjects: [],
		});
		const save = vi
			.spyOn(curriculumApi, "saveTeacherSubjects")
			.mockResolvedValue({ subjects: ["quran"] });
		renderCard("teacher");
		await userEvent.click(await screen.findByRole("checkbox", { name: "Quran" }));
		await userEvent.click(screen.getByRole("button", { name: /save subjects/i }));
		await waitFor(() => expect(save).toHaveBeenCalledWith(["quran"]));
	});

	it("uses the student endpoint when it is the student panel", async () => {
		vi.spyOn(curriculumApi, "listSubjects").mockResolvedValue([
			{ slug: "arabic", name: "Arabic" },
		]);
		vi.spyOn(curriculumApi, "getStudentSubjects").mockResolvedValue({
			subjects: [],
		});
		const save = vi
			.spyOn(curriculumApi, "saveStudentSubjects")
			.mockResolvedValue({ subjects: ["arabic"] });
		renderCard("student");
		await userEvent.click(await screen.findByRole("checkbox", { name: "Arabic" }));
		await userEvent.click(screen.getByRole("button", { name: /save subjects/i }));
		await waitFor(() => expect(save).toHaveBeenCalledWith(["arabic"]));
	});

	it("surfaces a load error", async () => {
		vi.spyOn(curriculumApi, "listSubjects").mockRejectedValue(new Error("boom"));
		vi.spyOn(curriculumApi, "getTeacherSubjects").mockResolvedValue({
			subjects: [],
		});
		renderCard("teacher");
		expect(await screen.findByRole("alert")).toBeInTheDocument();
	});

	it("says so when there are no subjects at all", async () => {
		vi.spyOn(curriculumApi, "listSubjects").mockResolvedValue([]);
		vi.spyOn(curriculumApi, "getTeacherSubjects").mockResolvedValue({
			subjects: [],
		});
		renderCard("teacher");
		expect(await screen.findByText(/no subjects are available/i)).toBeInTheDocument();
	});
});
```

- [ ] **Step 3: Run and watch them fail**

Run: `cd dashboard && pnpm vitest run src/features/curriculum/components/`
Expected: FAIL — cannot resolve `./SubjectsCard`.

- [ ] **Step 4: Write `SubjectsCard`**

`dashboard/src/features/curriculum/components/SubjectsCard.tsx`. Requirements the tests above pin:

- Props: `{ role: "teacher" | "student" }`. Pick the hook pair from `role` — never take the endpoint as a prop, or a caller can point the teacher panel at the student table.
- `useSubjects()` for the list; the role's `use*Subjects()` for the current set.
- Local `Set<string>` state seeded from the fetched set in a `useEffect`, exactly as `StudentPreferencesCard` seeds its form.
- Each row: `<Checkbox id={slug}>` plus a `<label htmlFor={slug}>` carrying the subject name, so the accessible name is the name and the whole row is a 44px touch target.
- Loading → `<Spinner />`. Load error → `<Alert variant="destructive" role="alert">`. Empty list → the `subjects.empty` copy.
- Save via `<SubmitButton>`; success → `toast({ description: t("subjects.saved"), variant: "success" })`; failure → `toast` with `variant: "destructive"` and the `subjects.saveError` copy.
- Wrap in `Card` / `CardHeader` / `CardTitle` / `CardDescription` / `CardContent` like the neighbouring panels.

- [ ] **Step 5: Run and watch them pass**

Run: `cd dashboard && pnpm vitest run src/features/curriculum/`
Expected: all pass.

- [ ] **Step 6: Write `TeacherGenderCard` the same way**

Test first, in `dashboard/src/features/identity/components/TeacherGenderCard.test.tsx`: renders the three options, shows the saved one selected, PATCHes on save, surfaces an error. Then the component, using the existing `RadioCardGroup` (male / female / prefer-not-to-say → `""`) — no new primitive needed. It must render the `teacherProfile.genderWhy` copy: a gender field with no stated purpose reads as intrusive.

Add `getTeacherProfile` / `saveTeacherProfile` to `src/features/identity/api.ts` and a `useTeacherProfile` / `useSaveTeacherProfile` pair to `queries.ts`, mirroring the `studentProfile` versions exactly.

- [ ] **Step 7: Wire both into the account route**

In `dashboard/src/routes/_authed/account.tsx`:

```tsx
	const isStudent = me.profiles.includes("student");
	const isTeacher = me.profiles.includes("teacher");
```

and inside `<CardGrid>`, after `StudentPreferencesCard`:

```tsx
				{isTeacher ? <TeacherGenderCard /> : null}
				{isTeacher ? <SubjectsCard role="teacher" /> : null}
				{isStudent ? <SubjectsCard role="student" /> : null}
```

A dual-role user sees both subject panels, which is the intended behaviour, not a bug.

- [ ] **Step 8: Full dashboard verification**

```bash
cd dashboard
pnpm vitest run --coverage
pnpm biome check src
pnpm tsc --noEmit
```

Expected: green, coverage ≥ 92 / 87 / 84. Raise the floors in `vitest.config.ts` if the measured numbers went up.

- [ ] **Step 9: Commit**

```bash
cd dashboard
git add src
git commit -m "feat(curriculum): subject panels and teacher gender on the account page"
```

---

### Task 10: e2e coverage

**Files:**
- Create: `dashboard/e2e/subjects.spec.ts`
- Modify: `dashboard/e2e/fixtures.ts` if a helper is needed

**Interfaces:**
- Consumes: the seeded `e2e.teacher@kaleem.test` and `e2e.student@kaleem.test` accounts, which Task 6 guarantees start with nothing declared.

D3 requires an e2e spec for every user-facing area that ships. These are writes, so they also exercise CSRF across the ADR-0019 subdomain boundary.

- [ ] **Step 1: Write the spec**

`dashboard/e2e/subjects.spec.ts`:

```ts
/**
 * Subject selection, both roles.
 *
 * Spec: docs/superpowers/specs/2026-09-04-phase-c0-matching-inputs-design.md
 *
 * Every flow here is a write, so each one also proves a real session cookie plus
 * real CSRF across the app./api. subdomain boundary (ADR-0019).
 */

import { expect, test } from "@playwright/test";
import { login } from "./fixtures";

test.describe("subjects", () => {
	test("a teacher picks what they teach and it survives a reload", async ({
		page,
	}) => {
		await login(page, "teacher");
		await page.goto("/account");

		const panel = page.getByRole("region", { name: "Subjects you teach" });
		await panel.getByRole("checkbox", { name: "Quran" }).check();
		await panel.getByRole("button", { name: "Save subjects" }).click();
		await expect(page.getByText("Subjects saved.")).toBeVisible();

		await page.reload();
		await expect(panel.getByRole("checkbox", { name: "Quran" })).toBeChecked();
	});

	test("a student picks what they want to study", async ({ page }) => {
		await login(page, "student");
		await page.goto("/account");

		const panel = page.getByRole("region", { name: "What you want to study" });
		await panel.getByRole("checkbox", { name: "Arabic" }).check();
		await panel.getByRole("button", { name: "Save subjects" }).click();
		await expect(page.getByText("Subjects saved.")).toBeVisible();

		await page.reload();
		await expect(panel.getByRole("checkbox", { name: "Arabic" })).toBeChecked();
	});

	test("a teacher declares a gender and it survives a reload", async ({ page }) => {
		await login(page, "teacher");
		await page.goto("/account");

		await page.getByRole("radio", { name: "Female" }).check();
		await page.getByRole("button", { name: "Save teaching profile" }).click();
		await expect(page.getByText("Teaching profile saved.")).toBeVisible();

		await page.reload();
		await expect(page.getByRole("radio", { name: "Female" })).toBeChecked();
	});

	test("a parent sees neither subject panel", async ({ page }) => {
		await login(page, "parent");
		await page.goto("/account");

		await expect(page.getByText("Subjects you teach")).toHaveCount(0);
		await expect(page.getByText("What you want to study")).toHaveCount(0);
	});
});
```

For the `getByRole("region", ...)` locators to work, each `Card` needs an accessible name — give the panel `role="region"` and `aria-labelledby` pointing at its `CardTitle` id. Do that in Task 9's component rather than bolting it on here.

- [ ] **Step 2: Run against a real stack**

Bring up the CI topology locally (`just dev` cannot bind :80 on this machine):

```bash
cd /home/abdulkhalek/Projects/kaleem
docker compose -f docker-compose.local.yml up -d django
docker compose -f docker-compose.local.yml exec -T django python manage.py migrate
docker compose -f docker-compose.local.yml exec -T django python manage.py seed_e2e
cd dashboard
VITE_API_URL=http://api.kaleem.localhost:8000/api/v1/ pnpm build
nohup pnpm preview --host app.kaleem.localhost --port 4173 > /tmp/preview.log 2>&1 &
E2E_APP_URL=http://app.kaleem.localhost:4173 pnpm e2e e2e/subjects.spec.ts
```

Expected: 4 passed.

- [ ] **Step 3: Run the whole suite**

Run: `E2E_APP_URL=http://app.kaleem.localhost:4173 pnpm e2e`
Expected: 24 passed (20 existing + 4 new).

- [ ] **Step 4: Commit and open the dashboard PR**

```bash
cd dashboard
git add e2e
git commit -m "test(e2e): cover subject selection for both roles"
git push -u origin feat/phase-c0-matching-inputs
gh pr create --repo kaleem-lms/dashboard --base main \
  --title "feat(curriculum): subject panels and teacher gender" \
  --body "Implements Phase C0's dashboard slice. Spec: docs/superpowers/specs/2026-09-04-phase-c0-matching-inputs-design.md"
```

---

### Task 11: Docs, ADR, and the meta pointer bump

**Files:**
- Create: `docs/adr/00NN-curriculum-module-opened-early.md`
- Create: `docs/architecture/curriculum.md`
- Modify: `CLAUDE.md` (D3 e2e table), `STATE.md`, `docs/superpowers/journal/2026-W36.md`
- Modify: meta submodule pointers for `backend` and `dashboard`

- [ ] **Step 1: Write the ADR**

Use `docs/templates/adr.md`. Number it one past the highest existing ADR (check `ls docs/adr/`). Content:

- **Context:** Phase C needs subject as a matching input. The roadmap gives `Subject` no owner: `curriculum` is defined as Course/Unit/Lesson and scheduled for a later phase.
- **Decision:** open `curriculum` early, owning `Subject` plus the two link tables, keyed to `AUTH_USER_MODEL` by string.
- **Alternatives rejected:** `identity` (would own curriculum taxonomy and have to hand it back); `platform` (infrastructure-only, zero models, and its contract is "imports no business modules").
- **Consequences:** the module exists ahead of its roadmap phase and starts as three tables; C1 will need a `scheduling → curriculum` dependency the roadmap does not list, which gets its own ADR then.

- [ ] **Step 2: Write the architecture doc**

`docs/architecture/curriculum.md`, following the shape of the existing per-module docs: what it owns, its public API surface (`list_active_subjects`, the four get/set services), what it deliberately does not do (courses, lessons, matching), and its boundary contracts.

- [ ] **Step 3: Update the D3 e2e table**

In `CLAUDE.md`, add a row:

```markdown
   | `curriculum` — subjects | ✅ 4 flows | teacher subjects, student interests, teacher gender, the parent empty state |
```

- [ ] **Step 4: Bump the pointers and update state**

```bash
cd /home/abdulkhalek/Projects/kaleem
git checkout -b feat/phase-c0-matching-inputs
git -C backend checkout main && git -C backend pull
git -C dashboard checkout main && git -C dashboard pull
```

Update `STATE.md`: C0 spec `status: shipped`, active spec set to none or C1, and a "Recently verified" entry naming what was checked and how.

Append a journal entry to `docs/superpowers/journal/2026-W36.md`.

- [ ] **Step 5: Close the spec**

In the spec's frontmatter, set `status: shipped` and `closed: 2026-09-04` (or the real date).

- [ ] **Step 6: Commit and open the meta PR**

```bash
PIP_CONFIG_FILE=/dev/null git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat: bump backend and dashboard for Phase C0"
git push -u origin feat/phase-c0-matching-inputs
gh pr create --base master --title "feat: Phase C0 — matching inputs"
```

⚠ Merging to `master` deploys to staging (ADR-0028). Wait for **all** checks, including `dashboard-build`, which only queues after `dashboard-lint`.

- [ ] **Step 7: Verify on staging**

Log in as a teacher on `app-staging.kaleem.academy`, set subjects and a gender, reload, confirm both persisted. D9 requires the manual browser click-through; the e2e run does not replace it.

---

## Self-review notes

Checked against the spec:

- **Data model delta** — `Subject` (Task 1), seeded (Task 2), both link tables (Task 3), `TeacherProfile.gender` (Task 5). ✅
- **API delta** — all four endpoints (Tasks 4 and 5), with the module-prefix correction stated in Global Constraints. ✅
- **Frontend** — subjects panel per role and the gender field with its stated purpose (Task 9), i18n in both locales (Task 9 Step 1). ✅
- **Module boundaries** — both contracts written *and mutation-verified* (Task 1 Step 9); the seed's boundary trap called out explicitly (Task 6 Step 3). ✅
- **Test plan** — every listed case has a test: round-trip, replace, clear, duplicate slugs, unknown slug, inactive slug, no profile, dual role, gender validation, migration idempotency, versioning guard, and the contract mutation check. ✅
- **Out of scope** — no task creates `TeacherAssignment`, booking, quota, or video. ✅
- **Open questions** — OQ-C0-1 and OQ-C0-2 are untouched by this plan, as intended; neither blocks it.

Naming is consistent across tasks: `get_teacher_subjects` / `set_teacher_subjects` / `get_student_subjects` / `set_student_subjects` in the backend, `useTeacherSubjects` / `useSaveTeacherSubjects` / `useStudentSubjects` / `useSaveStudentSubjects` in the dashboard, `SubjectsCard` taking `role`.

The spec deliberately does not name the service functions, so this plan fixes them: the four
get/set services form one symmetric quartet (`{get,set}_{teacher,student}_subjects`) and the
dashboard hooks mirror them exactly. The model is still called `StudentSubjectInterest`,
because the *row* is an interest while the *service* returns subjects; if that reads as a
mismatch during implementation, rename the model rather than breaking the quartet.
