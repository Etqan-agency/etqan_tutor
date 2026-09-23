# Phase C1 — Matching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An entitled student who has stated a subject is broadcast to every eligible teacher; the first teacher to accept becomes their teacher, recorded as a durable `TeacherAssignment`.

**Architecture:** Three new models in `scheduling` (`MatchRequest`, `TeacherAssignment`, `MatchDecline`). Offers are **not** stored — a teacher's inbox is computed live from open requests they are eligible for, minus their own declines. Requests are opened by a reconciler that asks `billing.is_entitled_to`, so `billing` never learns `scheduling` exists. Accept is a `select_for_update` transaction backed by a partial-unique index.

**Tech Stack:** Django 5 + DRF (backend submodule), React 19 + TanStack Router/Query + Tailwind + shadcn (dashboard submodule), Playwright (e2e), pytest, vitest, import-linter.

**Spec:** `docs/superpowers/specs/2026-09-05-phase-c1-matching-design.md` — read it before Task 1. ADR-0033 (`docs/adr/0033-scheduling-depends-on-curriculum-and-billing.md`) is the boundary decision Task 1 implements.

## Global Constraints

- **Two repos, two PRs.** Tasks 1–9 are in the `backend` submodule (trunk `main`); Tasks 10–14 are in `dashboard` (trunk `main`). Both are `feat/phase-c1-matching` → PR → trunk. Never commit to a trunk. Never `--no-verify`.
- **Commit with `PIP_CONFIG_FILE=/dev/null git commit …`** — a dead pip proxy in `pip.conf` otherwise breaks the pre-commit hook.
- **Coverage floors are ratchets (ADR-0026):** backend 97 line/branch (`pyproject.toml`), dashboard 92 lines / 87 branches / 84 functions (`vitest.config.ts`). Raise them if this slice lifts coverage; lowering needs an ADR.
- **Every route under `/api/v1/`,** mounted via `config/api_router.py`. `backend/tests/test_api_versioning_is_enforced.py` fails otherwise.
- **No business logic on models** — services in `<module>/services.py`. **No bare `except Exception`** — typed `KaleemError` subclasses only. **No `print()`** — structured logging.
- **No module imports another module's models.** Cross-module reads go through `<module>.services`; cross-module FKs are declared by **string label** (`"curriculum.Subject"`).
- **Frontend:** i18n keys in both `src/locales/en/common.json` and `src/locales/ar/common.json`, RTL verified, all style values from design tokens (semantic utilities — never a hex or `color-mix`), WCAG 2.2 AA.
- **Fixture identifiers must be realistic in shape** — a fake Stripe id is `sub_` plus 24 characters, not `sub_test`. A short stub silently removes the length constraint under test.
- **Gender rule, inherited verbatim from C0:** a teacher whose `gender` is `""` is **excluded** when the student stated `male`/`female`, and **eligible** when the student stated `no_preference`.

---

### Task 1: Widen the scheduling boundary, and prove the new contracts fail

ADR-0033 in code. This lands **first** because every later task imports across the boundary it opens — and because a contract nobody has watched fail is not known to work. This is the discipline C0 used and whose absence let scheduling's identity hole survive four months.

**Files:**
- Modify: `pyproject.toml` — the `scheduling imports no business modules except identity` contract, plus two new contracts

- [ ] **Step 1: Widen the "except identity" contract**

In `pyproject.toml`, find the contract named `scheduling imports no business modules except identity` and remove `"kaleem.billing"` and `"kaleem.curriculum"` from `forbidden_modules`, leaving:

```toml
[[tool.importlinter.contracts]]
name = "scheduling imports no business modules except identity, curriculum and billing"
type = "forbidden"
source_modules = ["kaleem.scheduling"]
# ADR-0033. scheduling reads subjects (curriculum) and entitlement (billing) to
# match a student to a teacher. Public APIs only -- the two contracts below keep
# the widening from reopening the direct-model-import hole this module already
# shipped once.
forbidden_modules = [
    "kaleem.assessment",
    "kaleem.content",
    "kaleem.messaging",
    "kaleem.notifications",
    "kaleem.engagement",
    "kaleem.analytics",
]
```

- [ ] **Step 2: Add the two mirror contracts**

Immediately after the `scheduling does not reach past identity's public API` contract, add:

```toml
[[tool.importlinter.contracts]]
name = "scheduling does not reach past curriculum's public API"
type = "forbidden"
source_modules = ["kaleem.scheduling"]
# ADR-0033. The mirror of the identity contract above, for the same reason: the
# "except" contract permits *any* curriculum import, so a direct model import
# would pass. scheduling calls kaleem.curriculum.services, which imports its own
# models; allow_indirect_imports keeps that chain legal.
forbidden_modules = ["kaleem.curriculum.models"]
allow_indirect_imports = true
ignore_imports = [
    "kaleem.scheduling.tests.* -> kaleem.curriculum.models",
]

[[tool.importlinter.contracts]]
name = "scheduling does not reach past billing's public API"
type = "forbidden"
source_modules = ["kaleem.scheduling"]
# ADR-0033.
forbidden_modules = ["kaleem.billing.models"]
allow_indirect_imports = true
ignore_imports = [
    "kaleem.scheduling.tests.* -> kaleem.billing.models",
]
```

- [ ] **Step 3: Verify the contracts are green as written**

Run: `docker compose -f docker-compose.local.yml run --rm django lint-imports`
Expected: all contracts PASS (no code imports curriculum or billing from scheduling yet).

- [ ] **Step 4: Break the curriculum contract on purpose**

Add this line temporarily at the top of `kaleem/scheduling/services.py`:

```python
from kaleem.curriculum.models import Subject  # PROBE -- delete me
```

- [ ] **Step 5: Run the linter and watch it go red**

Run: `docker compose -f docker-compose.local.yml run --rm django lint-imports`
Expected: FAIL, naming `scheduling does not reach past curriculum's public API`.
**If it passes, the contract is decorative — stop and fix it before going further.**

- [ ] **Step 6: Repeat for billing**

Replace the probe with:

```python
from kaleem.billing.models import Subscription  # PROBE -- delete me
```

Run the linter again. Expected: FAIL, naming `scheduling does not reach past billing's public API`.

- [ ] **Step 7: Remove the probe and confirm green**

Delete the probe line. Run: `docker compose -f docker-compose.local.yml run --rm django lint-imports`
Expected: all contracts PASS.

- [ ] **Step 8: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git commit -am "chore: open scheduling -> curriculum and billing (ADR-0033)

Both new contracts verified by breaking them: a direct model import turns
each one red, green once removed."
```

---

### Task 2: A typed 409 for the accept race

`platform.exceptions` has no conflict type, so the losing accepter would fall through to a 400 — which reads to a client as "your request was malformed" when in fact it was fine and merely late.

**Files:**
- Modify: `kaleem/platform/exceptions.py`
- Modify: `kaleem/platform/drf.py:14-21` (the exception → status tuple list)
- Test: `kaleem/platform/tests/test_drf.py`

**Interfaces:**
- Produces: `ConflictError(message: str)` — a `KaleemError` with `code="conflict"`, mapped to HTTP 409.

- [ ] **Step 1: Write the failing test**

Append to `kaleem/platform/tests/test_drf.py`:

```python
def test_conflict_error_maps_to_409():
    from rest_framework import status

    from kaleem.platform.drf import exception_handler
    from kaleem.platform.exceptions import ConflictError

    response = exception_handler(ConflictError("Already taken."), {})

    assert response.status_code == status.HTTP_409_CONFLICT
    assert response.data["code"] == "conflict"
    assert response.data["message"] == "Already taken."
```

- [ ] **Step 2: Run it and watch it fail**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/platform/tests/test_drf.py::test_conflict_error_maps_to_409 -v`
Expected: FAIL — `ImportError: cannot import name 'ConflictError'`.

- [ ] **Step 3: Add the exception**

In `kaleem/platform/exceptions.py`, after `PermissionDeniedError`:

```python
class ConflictError(KaleemError):
    """The request was well-formed but lost a race for a resource.

    Distinct from ValidationError on purpose: nothing about the caller's input
    was wrong, so telling them it was would send them off editing a correct
    request. The canonical case is two teachers accepting one match request.
    """

    def __init__(self, message: str):
        super().__init__(message=message, code="conflict")
```

- [ ] **Step 4: Map it in the DRF handler**

In `kaleem/platform/drf.py`, import `ConflictError` alongside the others and add to the status tuple list, after the `ValidationError` entry:

```python
    (ConflictError, status.HTTP_409_CONFLICT),
```

- [ ] **Step 5: Run the test**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/platform/tests/test_drf.py -v`
Expected: PASS, and no other platform test regresses.

- [ ] **Step 6: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git commit -am "feat(platform): add ConflictError, mapped to 409

The accept race needs a status that says 'you were late', not 'your
request was malformed'."
```

---

### Task 3: The three models

**Files:**
- Modify: `kaleem/scheduling/models.py`
- Create: `kaleem/scheduling/migrations/0003_matching.py` (generated; number may differ — use whatever `makemigrations` produces)
- Test: `kaleem/scheduling/tests/test_matching_models.py`

**Interfaces:**
- Produces: `MatchRequest` (`.Status.OPEN|MATCHED|CANCELLED`), `TeacherAssignment` (`.Status.ACTIVE|ENDED`), `MatchDecline`. Later tasks import these from `kaleem.scheduling.models`.

- [ ] **Step 1: Write the failing test**

Create `kaleem/scheduling/tests/test_matching_models.py`:

```python
import pytest
from django.db import IntegrityError
from django.db import transaction

from kaleem.curriculum.models import Subject
from kaleem.identity.models import User
from kaleem.scheduling.models import MatchDecline
from kaleem.scheduling.models import MatchRequest
from kaleem.scheduling.models import TeacherAssignment

pytestmark = pytest.mark.django_db


@pytest.fixture
def subject():
    return Subject.objects.create(slug="quran", name="Quran")


@pytest.fixture
def student():
    return User.objects.create_user(email="s@kaleem.test", password="x")  # noqa: S106


@pytest.fixture
def teacher():
    return User.objects.create_user(email="t@kaleem.test", password="x")  # noqa: S106


def test_only_one_open_request_per_student_and_subject(student, subject):
    MatchRequest.objects.create(student=student, subject=subject)
    with pytest.raises(IntegrityError), transaction.atomic():
        MatchRequest.objects.create(student=student, subject=subject)


def test_a_second_request_is_allowed_once_the_first_is_matched(student, subject):
    first = MatchRequest.objects.create(student=student, subject=subject)
    first.status = MatchRequest.Status.MATCHED
    first.save()

    # A student whose teacher left may be rematched; the partial index must
    # constrain only the OPEN row, not the history.
    MatchRequest.objects.create(student=student, subject=subject)

    assert MatchRequest.objects.filter(student=student).count() == 2


def test_only_one_active_assignment_per_student_and_subject(
    student, teacher, subject
):
    request = MatchRequest.objects.create(student=student, subject=subject)
    TeacherAssignment.objects.create(
        student=student, teacher=teacher, subject=subject, source_request=request
    )
    with pytest.raises(IntegrityError), transaction.atomic():
        TeacherAssignment.objects.create(
            student=student, teacher=teacher, subject=subject, source_request=request
        )


def test_a_teacher_declines_a_request_once(student, teacher, subject):
    request = MatchRequest.objects.create(student=student, subject=subject)
    MatchDecline.objects.create(request=request, teacher=teacher)
    with pytest.raises(IntegrityError), transaction.atomic():
        MatchDecline.objects.create(request=request, teacher=teacher)
```

- [ ] **Step 2: Run it and watch it fail**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/scheduling/tests/test_matching_models.py -v`
Expected: FAIL — `ImportError: cannot import name 'MatchRequest'`.

- [ ] **Step 3: Write the models**

Append to `kaleem/scheduling/models.py`:

```python
class MatchRequest(models.Model):
    """A student waiting for a teacher, in one subject.

    Kept open indefinitely when nobody is eligible or nobody accepts: the pool
    changes (a teacher adds a subject, declares a gender, edits availability)
    and the request becomes matchable without anything re-running. Staff see
    open requests in Django admin.
    """

    class Status(models.TextChoices):
        OPEN = "open", "Open"
        MATCHED = "matched", "Matched"
        CANCELLED = "cancelled", "Cancelled"

    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="match_requests",
    )
    # By string label, never an import: this is what keeps D4 true while the FK
    # is still a real database relation (ADR-0033).
    subject = models.ForeignKey("curriculum.Subject", on_delete=models.CASCADE)
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.OPEN
    )
    created_at = models.DateTimeField(auto_now_add=True)
    matched_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["status", "subject"])]
        constraints = [
            # Partial, not plain: a rematched student legitimately accumulates
            # rows, so only the OPEN one is constrained.
            models.UniqueConstraint(
                fields=["student", "subject"],
                condition=models.Q(status="open"),
                name="unique_open_match_request",
            )
        ]

    def __str__(self):
        return f"MatchRequest<{self.student_id}:{self.subject_id}:{self.status}>"


class TeacherAssignment(models.Model):
    """An ongoing 1-on-1 relationship. Many-over-time (rule #7): reassignment
    writes a new row and ends the old one, so a student's history survives."""

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        ENDED = "ended", "Ended"

    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="teacher_assignments",
    )
    teacher = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="student_assignments",
    )
    subject = models.ForeignKey("curriculum.Subject", on_delete=models.CASCADE)
    source_request = models.ForeignKey(
        MatchRequest, on_delete=models.PROTECT, related_name="assignments"
    )
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.ACTIVE
    )
    created_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["teacher", "status"])]
        constraints = [
            # The invariant the accept race exists to protect, stated where a
            # service-layer bug cannot get around it.
            models.UniqueConstraint(
                fields=["student", "subject"],
                condition=models.Q(status="active"),
                name="unique_active_assignment",
            )
        ]

    def __str__(self):
        return f"TeacherAssignment<{self.student_id}<-{self.teacher_id}>"


class MatchDecline(models.Model):
    """A teacher opting out of one request. The only reason offers need any
    storage at all -- eligibility itself is computed, not materialised."""

    request = models.ForeignKey(
        MatchRequest, on_delete=models.CASCADE, related_name="declines"
    )
    teacher = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="match_declines",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["request", "teacher"], name="unique_match_decline"
            )
        ]

    def __str__(self):
        return f"MatchDecline<{self.request_id}:{self.teacher_id}>"
```

- [ ] **Step 4: Generate and read the migration**

Run: `docker compose -f docker-compose.local.yml run --rm django python manage.py makemigrations scheduling`
Then read the generated file. Confirm all three `UniqueConstraint`s carry their `condition` — a partial index silently generated as a plain one would make Task 3's second test fail *and* break rematching in production.

- [ ] **Step 5: Run the tests**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/scheduling/tests/test_matching_models.py -v`
Expected: 4 passed.

- [ ] **Step 6: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A && PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): MatchRequest, TeacherAssignment, MatchDecline

Partial-unique indexes carry the two invariants: one OPEN request and one
ACTIVE assignment per (student, subject), while history accumulates freely."
```

---

### Task 4: Curriculum lookups the matcher needs

`curriculum.services` answers "what does this user teach?" by slug. Matching asks two questions it cannot: "which subject ids does this teacher teach?" (to filter requests) and "every (student, subject) interest pair" (to reconcile). Adding them here keeps `scheduling` off `curriculum.models`.

**Files:**
- Modify: `kaleem/curriculum/services.py`
- Test: `kaleem/curriculum/tests/test_services.py`

**Interfaces:**
- Produces:
  - `teacher_subject_ids(user_id: int) -> list[int]`
  - `all_student_interest_pairs() -> list[tuple[int, int]]` — `(user_id, subject_id)`
  - `get_subject(subject_id: int) -> Subject` — raises `NotFoundError`

- [ ] **Step 1: Write the failing tests**

Append to `kaleem/curriculum/tests/test_services.py`:

```python
def test_teacher_subject_ids_returns_ids_not_slugs(teacher_user, quran, arabic):
    services.set_teacher_subjects(teacher_user.id, ["quran", "arabic"])

    assert sorted(services.teacher_subject_ids(teacher_user.id)) == sorted(
        [quran.id, arabic.id]
    )


def test_teacher_subject_ids_is_empty_for_a_teacher_who_set_none(teacher_user):
    assert services.teacher_subject_ids(teacher_user.id) == []


def test_all_student_interest_pairs_spans_every_student(
    student_user, other_student_user, quran, arabic
):
    services.set_student_subjects(student_user.id, ["quran"])
    services.set_student_subjects(other_student_user.id, ["quran", "arabic"])

    pairs = set(services.all_student_interest_pairs())

    assert pairs == {
        (student_user.id, quran.id),
        (other_student_user.id, quran.id),
        (other_student_user.id, arabic.id),
    }


def test_get_subject_raises_for_an_unknown_id():
    from kaleem.platform.exceptions import NotFoundError

    with pytest.raises(NotFoundError):
        services.get_subject(999999)
```

If `teacher_user`, `student_user`, `other_student_user`, `quran` or `arabic` fixtures do not already exist in that file, add them following the fixtures already there — do not invent a different naming scheme.

- [ ] **Step 2: Run and watch them fail**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/curriculum/tests/test_services.py -v`
Expected: FAIL — `AttributeError: module ... has no attribute 'teacher_subject_ids'`.

- [ ] **Step 3: Implement**

Append to `kaleem/curriculum/services.py`:

```python
def teacher_subject_ids(user_id: int) -> list[int]:
    """Subject ids a teacher teaches. Ids rather than slugs because the caller
    (scheduling's matcher) filters foreign keys, and re-resolving slugs there
    would mean a second query per request row."""
    return list(
        TeacherSubject.objects.filter(user_id=user_id).values_list(
            "subject_id", flat=True
        )
    )


def all_student_interest_pairs() -> list[tuple[int, int]]:
    """Every (student user id, subject id) interest, for the match reconciler.

    Returned whole rather than per-user: the reconciler sweeps all students, and
    a query per student is the shape that stops being viable first.
    """
    return list(
        StudentSubjectInterest.objects.values_list("user_id", "subject_id")
    )


def get_subject(subject_id: int) -> Subject:
    subject = Subject.objects.filter(id=subject_id).first()
    if subject is None:
        raise NotFoundError("Subject", subject_id)
    return subject
```

Add `from kaleem.platform.exceptions import NotFoundError` to that file's imports.

- [ ] **Step 4: Run the tests**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/curriculum/tests/test_services.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git commit -am "feat(curriculum): id-shaped lookups for the matcher"
```

---

### Task 5: Eligibility and rank

The heart of C1, and pure enough to test without an HTTP request. Three hard filters; rank orders only.

**Files:**
- Create: `kaleem/scheduling/matching.py`
- Test: `kaleem/scheduling/tests/test_matching_eligibility.py`

**Interfaces:**
- Consumes: `MatchRequest`, `MatchDecline` (Task 3); `curriculum_services.teacher_subject_ids` (Task 4); `to_utc_intervals` (existing, `kaleem/scheduling/services.py:77`).
- Produces:
  - `gender_allows(teacher_gender: str, preference: str) -> bool`
  - `overlap_minutes(teacher, student, reference_date: dt.date) -> int`
  - `is_eligible(teacher, request, reference_date: dt.date) -> bool`
  - `list_offers_for(teacher, reference_date: dt.date) -> list[Offer]` where `Offer` is a `TypedDict` with `request_id: int`, `student_name: str`, `subject_slug: str`, `subject_name: str`, `overlap_minutes: int`, `waiting_since: dt.datetime`

Living in its own module rather than in `services.py`: `services.py` is already the availability editor's home, and matching is a distinct responsibility with its own vocabulary. `services.py` re-exports the public entry points in Task 7 so callers still see one public API.

- [ ] **Step 1: Write the failing tests**

Create `kaleem/scheduling/tests/test_matching_eligibility.py`:

```python
import datetime as dt

import pytest

from kaleem.curriculum import services as curriculum_services
from kaleem.curriculum.models import Subject
from kaleem.identity.models import StudentProfile
from kaleem.identity.models import TeacherProfile
from kaleem.identity.models import User
from kaleem.scheduling import matching
from kaleem.scheduling.models import MatchDecline
from kaleem.scheduling.models import MatchRequest
from kaleem.scheduling.services import set_availability

pytestmark = pytest.mark.django_db

REFERENCE = dt.date(2026, 9, 7)  # a Monday; the helpers anchor to its Saturday


def _slot(weekday, start, end):
    return {
        "weekday": weekday,
        "start_time": dt.time(start),
        "end_time": dt.time(end),
    }


@pytest.fixture
def quran():
    return Subject.objects.create(slug="quran", name="Quran")


@pytest.fixture
def arabic():
    return Subject.objects.create(slug="arabic", name="Arabic")


@pytest.fixture
def teacher(quran):
    user = User.objects.create_user(  # noqa: S106
        email="t@kaleem.test", password="x", full_name="Ustadh Teacher"
    )
    TeacherProfile.objects.create(user=user, gender=TeacherProfile.Gender.MALE)
    curriculum_services.set_teacher_subjects(user.id, ["quran"])
    set_availability(user, [_slot(0, 9, 12)], timezone="UTC")
    return user


@pytest.fixture
def student(quran):
    user = User.objects.create_user(  # noqa: S106
        email="s@kaleem.test", password="x", full_name="Amina Student"
    )
    StudentProfile.objects.create(
        user=user,
        teacher_gender_preference=StudentProfile.GenderPreference.NO_PREFERENCE,
    )
    set_availability(user, [_slot(0, 10, 11)], timezone="UTC")
    return user


@pytest.fixture
def request_row(student, quran):
    return MatchRequest.objects.create(student=student, subject=quran)


@pytest.mark.parametrize(
    ("teacher_gender", "preference", "allowed"),
    [
        ("male", "male", True),
        ("male", "female", False),
        ("female", "no_preference", True),
        # The C0 rule, and the reason it is spelled out: an undeclared teacher is
        # not a wildcard. A student who asked for a woman must not be handed a
        # teacher whose gender nobody knows.
        ("", "female", False),
        ("", "male", False),
        ("", "no_preference", True),
    ],
)
def test_gender_rule(teacher_gender, preference, allowed):
    assert matching.gender_allows(teacher_gender, preference) is allowed


def test_overlap_is_measured_in_minutes(teacher, student):
    assert matching.overlap_minutes(teacher, student, REFERENCE) == 60


def test_overlap_is_computed_in_utc_across_timezones(teacher, student):
    # Same wall-clock hours, three timezones apart: the naive comparison says
    # they overlap, UTC says they do not.
    set_availability(student, [_slot(0, 10, 11)], timezone="Africa/Cairo")
    student.refresh_from_db()

    assert matching.overlap_minutes(teacher, student, REFERENCE) == 0


def test_a_teacher_who_does_not_teach_the_subject_is_not_eligible(
    teacher, student, arabic
):
    other = MatchRequest.objects.create(student=student, subject=arabic)

    assert matching.is_eligible(teacher, other, REFERENCE) is False


def test_a_teacher_with_no_overlap_is_not_eligible(teacher, student, request_row):
    set_availability(teacher, [_slot(3, 9, 12)], timezone="UTC")
    teacher.refresh_from_db()

    assert matching.is_eligible(teacher, request_row, REFERENCE) is False


def test_a_matching_teacher_is_eligible(teacher, request_row):
    assert matching.is_eligible(teacher, request_row, REFERENCE) is True


def test_the_inbox_excludes_declined_requests(teacher, request_row):
    MatchDecline.objects.create(request=request_row, teacher=teacher)

    assert matching.list_offers_for(teacher, REFERENCE) == []


def test_the_inbox_excludes_requests_that_are_no_longer_open(teacher, request_row):
    request_row.status = MatchRequest.Status.MATCHED
    request_row.save()

    assert matching.list_offers_for(teacher, REFERENCE) == []


def test_an_offer_carries_the_student_name_and_never_their_email(
    teacher, request_row, student
):
    [offer] = matching.list_offers_for(teacher, REFERENCE)

    assert offer["student_name"] == "Amina Student"
    assert offer["subject_slug"] == "quran"
    assert offer["overlap_minutes"] == 60
    assert student.email not in repr(offer)


def test_offers_rank_by_overlap_then_by_oldest_request(teacher, student, quran):
    # A second student with double the overlap must outrank the first.
    keen = User.objects.create_user(  # noqa: S106
        email="k@kaleem.test", password="x", full_name="Keen Student"
    )
    StudentProfile.objects.create(
        user=keen,
        teacher_gender_preference=StudentProfile.GenderPreference.NO_PREFERENCE,
    )
    set_availability(keen, [_slot(0, 9, 11)], timezone="UTC")
    MatchRequest.objects.create(student=student, subject=quran)
    MatchRequest.objects.create(student=keen, subject=quran)

    names = [o["student_name"] for o in matching.list_offers_for(teacher, REFERENCE)]

    assert names == ["Keen Student", "Amina Student"]
```

- [ ] **Step 2: Run and watch them fail**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/scheduling/tests/test_matching_eligibility.py -v`
Expected: FAIL — `ModuleNotFoundError: kaleem.scheduling.matching`.

- [ ] **Step 3: Implement**

Create `kaleem/scheduling/matching.py`:

```python
"""Who may be offered which student, and in what order.

Offers are computed, never stored. A materialised offer table would go stale the
moment a teacher added a subject or edited availability, and the spec's promise
-- an unmatched request is re-evaluated when the pool changes -- would then need
a job to re-fan-out. Here it is a property of the query.
"""

from __future__ import annotations

import datetime as dt
from typing import TypedDict

from kaleem.curriculum import services as curriculum_services
from kaleem.identity import services as identity_services
from kaleem.scheduling.models import MatchDecline
from kaleem.scheduling.models import MatchRequest
from kaleem.scheduling.services import to_utc_intervals

NO_PREFERENCE = "no_preference"


class Offer(TypedDict):
    request_id: int
    student_name: str
    subject_slug: str
    subject_name: str
    overlap_minutes: int
    waiting_since: dt.datetime


def gender_allows(teacher_gender: str, preference: str) -> bool:
    """C0's rule. An undeclared teacher ("") is not a wildcard: they are
    eligible only where the student expressed no preference at all."""
    if preference == NO_PREFERENCE:
        return True
    return teacher_gender == preference


def overlap_minutes(teacher, student, reference_date: dt.date) -> int:
    """Total weekly overlap, in UTC.

    Compared as instants rather than as (weekday, wall clock) pairs: kaleem's
    teachers and students are in different countries, and 10:00 in Cairo is not
    10:00 in London. Comparing local times would pair people who are asleep.
    """
    teacher_intervals = to_utc_intervals(teacher, reference_date)
    student_intervals = to_utc_intervals(student, reference_date)
    total = 0
    for t_start, t_end in teacher_intervals:
        for s_start, s_end in student_intervals:
            start = max(t_start, s_start)
            end = min(t_end, s_end)
            if end > start:
                total += int((end - start).total_seconds() // 60)
    return total


def _student_preference(student_user_id: int) -> str:
    profile = identity_services.get_student_profile(student_user_id)
    return profile.teacher_gender_preference if profile else NO_PREFERENCE


def _teacher_gender(teacher_user_id: int) -> str | None:
    profile = identity_services.get_teacher_profile(teacher_user_id)
    return None if profile is None else profile.gender


def is_eligible(teacher, request: MatchRequest, reference_date: dt.date) -> bool:
    gender = _teacher_gender(teacher.id)
    if gender is None:
        return False
    if request.subject_id not in curriculum_services.teacher_subject_ids(teacher.id):
        return False
    if not gender_allows(gender, _student_preference(request.student_id)):
        return False
    student = identity_services.get_user(request.student_id)
    return overlap_minutes(teacher, student, reference_date) > 0


def list_offers_for(teacher, reference_date: dt.date) -> list[Offer]:
    subject_ids = curriculum_services.teacher_subject_ids(teacher.id)
    if not subject_ids:
        return []
    gender = _teacher_gender(teacher.id)
    if gender is None:
        return []
    declined = MatchDecline.objects.filter(teacher=teacher).values_list(
        "request_id", flat=True
    )
    rows = (
        MatchRequest.objects.filter(
            status=MatchRequest.Status.OPEN, subject_id__in=subject_ids
        )
        .exclude(id__in=declined)
        .select_related("subject")
    )

    offers: list[Offer] = []
    for row in rows:
        if not gender_allows(gender, _student_preference(row.student_id)):
            continue
        student = identity_services.get_user(row.student_id)
        minutes = overlap_minutes(teacher, student, reference_date)
        if minutes <= 0:
            continue
        offers.append(
            {
                "request_id": row.id,
                # Full name, never the email address (ADR-0023).
                "student_name": student.full_name,
                "subject_slug": row.subject.slug,
                "subject_name": row.subject.name,
                "overlap_minutes": minutes,
                "waiting_since": row.created_at,
            }
        )
    # Best fit first, then longest wait. Rank orders the list and decides
    # nothing: with first-to-accept, whoever clicks first wins.
    offers.sort(key=lambda o: (-o["overlap_minutes"], o["waiting_since"]))
    return offers
```

- [ ] **Step 4: Run the tests**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/scheduling/tests/test_matching_eligibility.py -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A && PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): eligibility and rank for matching

Three hard filters (subject, gender, UTC availability overlap); rank
orders the inbox and decides nothing."
```

---

### Task 6: The reconciler

**Files:**
- Create: `kaleem/scheduling/tests/test_matching_reconciler.py`
- Modify: `kaleem/scheduling/matching.py`

**Interfaces:**
- Consumes: `curriculum_services.all_student_interest_pairs` (Task 4); `billing.services.is_entitled_to` + `Capability` (existing, `kaleem/billing/services.py:981-1013`).
- Produces: `sync_match_requests() -> int` — number of requests opened.

- [ ] **Step 1: Write the failing tests**

Create `kaleem/scheduling/tests/test_matching_reconciler.py`:

```python
import pytest

from kaleem.curriculum import services as curriculum_services
from kaleem.curriculum.models import Subject
from kaleem.identity.models import StudentProfile
from kaleem.identity.models import User
from kaleem.scheduling import matching
from kaleem.scheduling.models import MatchRequest
from kaleem.scheduling.models import TeacherAssignment

pytestmark = pytest.mark.django_db


@pytest.fixture
def quran():
    return Subject.objects.create(slug="quran", name="Quran")


@pytest.fixture
def arabic():
    return Subject.objects.create(slug="arabic", name="Arabic")


@pytest.fixture
def student(quran):
    user = User.objects.create_user(email="s@kaleem.test", password="x")  # noqa: S106
    StudentProfile.objects.create(user=user)
    curriculum_services.set_student_subjects(user.id, ["quran"])
    return user


def test_an_unentitled_student_gets_no_request(student):
    assert matching.sync_match_requests() == 0
    assert MatchRequest.objects.count() == 0


def test_an_entitled_student_gets_one_request_per_interest(
    student, quran, arabic, entitled
):
    curriculum_services.set_student_subjects(student.id, ["quran", "arabic"])
    entitled(student)

    assert matching.sync_match_requests() == 2
    assert set(
        MatchRequest.objects.values_list("subject__slug", flat=True)
    ) == {"quran", "arabic"}


def test_reconciling_twice_opens_one_request(student, entitled):
    entitled(student)

    matching.sync_match_requests()
    second = matching.sync_match_requests()

    assert second == 0
    assert MatchRequest.objects.count() == 1


def test_a_student_with_an_active_assignment_gets_no_new_request(
    student, quran, entitled
):
    entitled(student)
    teacher = User.objects.create_user(email="t@kaleem.test", password="x")  # noqa: S106
    source = MatchRequest.objects.create(
        student=student, subject=quran, status=MatchRequest.Status.MATCHED
    )
    TeacherAssignment.objects.create(
        student=student, teacher=teacher, subject=quran, source_request=source
    )

    assert matching.sync_match_requests() == 0


def test_a_request_with_no_eligible_teacher_stays_open_and_becomes_matchable(
    student, quran, entitled
):
    """The load-bearing claim of the whole design, asserted rather than assumed.

    Offers are computed, so a request nobody could take today must become
    visible the moment a teacher qualifies -- with nothing re-run in between.
    If this test ever fails, the "offers are not rows" decision has been undone.
    """
    import datetime as dt

    from kaleem.curriculum import services as curriculum_services
    from kaleem.identity.models import TeacherProfile
    from kaleem.scheduling import matching as matching_module
    from kaleem.scheduling.services import set_availability

    entitled(student)
    set_availability(
        student,
        [{"weekday": 0, "start_time": dt.time(9), "end_time": dt.time(12)}],
        timezone="UTC",
    )
    matching.sync_match_requests()

    teacher = User.objects.create_user(email="t@kaleem.test", password="x")  # noqa: S106
    TeacherProfile.objects.create(user=teacher, gender=TeacherProfile.Gender.MALE)
    set_availability(
        teacher,
        [{"weekday": 0, "start_time": dt.time(9), "end_time": dt.time(12)}],
        timezone="UTC",
    )
    reference = dt.date(2026, 9, 7)

    # Teaches nothing yet: eligible for no one.
    assert matching_module.list_offers_for(teacher, reference) == []

    curriculum_services.set_teacher_subjects(teacher.id, ["quran"])

    # The pool changed. Nothing re-ran. The offer exists.
    assert len(matching_module.list_offers_for(teacher, reference)) == 1
    assert MatchRequest.objects.get().status == MatchRequest.Status.OPEN


def test_an_ended_assignment_lets_the_student_be_rematched(student, quran, entitled):
    entitled(student)
    teacher = User.objects.create_user(email="t@kaleem.test", password="x")  # noqa: S106
    source = MatchRequest.objects.create(
        student=student, subject=quran, status=MatchRequest.Status.MATCHED
    )
    TeacherAssignment.objects.create(
        student=student,
        teacher=teacher,
        subject=quran,
        source_request=source,
        status=TeacherAssignment.Status.ENDED,
    )

    assert matching.sync_match_requests() == 1
```

The `entitled` fixture belongs in `kaleem/scheduling/tests/conftest.py` — add it there so Task 8's API tests reuse it rather than growing a second copy:

```python
import datetime as dt

import pytest
from django.utils import timezone

from kaleem.billing.models import Subscription
from kaleem.billing.models import SubscriptionPlan


@pytest.fixture
def entitled(db):
    """Give a user a live subscription, the way billing's own tests do.

    The Stripe ids are fake but real-shaped -- `sub_` plus 24 characters. A short
    stub would quietly stop exercising the id length the column constrains.
    """

    def _entitle(user):
        plan, _ = SubscriptionPlan.objects.get_or_create(
            stripe_price_id="price_1QcMatchingFixture0001",
            defaults={
                "name": "Matching fixture plan",
                "amount": 5000,
                "currency": "usd",
                "is_active": True,
            },
        )
        return Subscription.objects.create(
            user=user,
            plan=plan,
            stripe_subscription_id=f"sub_{user.id:024d}",
            status=Subscription.Status.ACTIVE,
            current_period_end=timezone.now() + dt.timedelta(days=30),
        )

    return _entitle
```

If `SubscriptionPlan` requires fields beyond those, copy the working construction from `kaleem/billing/tests/` rather than guessing — the plan model has evolved and billing's own fixtures are the reference.

- [ ] **Step 2: Run and watch them fail**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/scheduling/tests/test_matching_reconciler.py -v`
Expected: FAIL — `AttributeError: ... has no attribute 'sync_match_requests'`.

- [ ] **Step 3: Implement**

Append to `kaleem/scheduling/matching.py`:

```python
def sync_match_requests() -> int:
    """Open a request for every entitled student with an unmet interest.

    Pull, not push: billing must never import scheduling, so entitlement is
    asked for rather than announced. That is also why this needs no event bus
    and no beat schedule -- a reconciler is idempotent, so running it on a read
    is correct, merely repeated.

    Gated on BOOK_SESSION rather than a capability of its own: every capability
    resolves to the same subscription check today, so a second name would be a
    distinction the code cannot make -- and being matched to a teacher you
    cannot book is not a state worth building.
    """
    pairs = curriculum_services.all_student_interest_pairs()
    if not pairs:
        return 0

    taken = set(
        TeacherAssignment.objects.filter(
            status=TeacherAssignment.Status.ACTIVE
        ).values_list("student_id", "subject_id")
    )
    already_open = set(
        MatchRequest.objects.filter(
            status=MatchRequest.Status.OPEN
        ).values_list("student_id", "subject_id")
    )
    wanted = [p for p in pairs if p not in taken and p not in already_open]
    if not wanted:
        return 0

    # One entitlement check per student, not per pair: it is the expensive call
    # in this loop and a student's coverage does not vary by subject.
    entitlement: dict[int, bool] = {}
    opened = 0
    for student_id, subject_id in wanted:
        if student_id not in entitlement:
            student = identity_services.get_user(student_id)
            entitlement[student_id] = billing_services.is_entitled_to(
                student, billing_services.Capability.BOOK_SESSION
            )
        if not entitlement[student_id]:
            continue
        MatchRequest.objects.create(student_id=student_id, subject_id=subject_id)
        opened += 1
    return opened
```

Add to that module's imports:

```python
from kaleem.billing import services as billing_services
from kaleem.scheduling.models import TeacherAssignment
```

- [ ] **Step 4: Run the tests**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/scheduling/tests/test_matching_reconciler.py -v`
Expected: all pass.

- [ ] **Step 5: Check the boundary still holds**

Run: `docker compose -f docker-compose.local.yml run --rm django lint-imports`
Expected: PASS — `matching.py` imports `billing.services`, not `billing.models`, and the tests exemption covers `conftest.py`'s `Subscription` import.

- [ ] **Step 6: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A && PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): reconcile match requests from entitlement

Pull rather than push, so billing never learns scheduling exists. No event
bus and no beat schedule: an idempotent reconciler is correct on a read."
```

---

### Task 7: Accept and decline, with the race closed

**Files:**
- Modify: `kaleem/scheduling/matching.py`
- Modify: `kaleem/scheduling/services.py` (re-export the public entry points)
- Test: `kaleem/scheduling/tests/test_matching_accept.py`

**Interfaces:**
- Produces:
  - `accept_offer(teacher, request_id: int, reference_date: dt.date) -> TeacherAssignment`
  - `decline_offer(teacher, request_id: int) -> None`
  - Re-exported from `kaleem.scheduling.services`: `list_offers_for`, `accept_offer`, `decline_offer`, `sync_match_requests`, `list_assignments_for`

- [ ] **Step 1: Write the failing tests**

Create `kaleem/scheduling/tests/test_matching_accept.py`. Reuse the fixture shapes from `test_matching_eligibility.py` (same `_slot` helper, same `teacher`/`student`/`quran` fixtures — move them into `kaleem/scheduling/tests/conftest.py` if both files now need them, rather than duplicating):

```python
import datetime as dt

import pytest
from django.db import IntegrityError
from django.db import transaction

from kaleem.platform.exceptions import ConflictError
from kaleem.platform.exceptions import NotFoundError
from kaleem.platform.exceptions import PermissionDeniedError
from kaleem.scheduling import matching
from kaleem.scheduling.models import MatchDecline
from kaleem.scheduling.models import MatchRequest
from kaleem.scheduling.models import TeacherAssignment

pytestmark = pytest.mark.django_db

REFERENCE = dt.date(2026, 9, 7)


def test_accepting_creates_an_active_assignment(teacher, request_row):
    assignment = matching.accept_offer(teacher, request_row.id, REFERENCE)

    request_row.refresh_from_db()
    assert assignment.status == TeacherAssignment.Status.ACTIVE
    assert assignment.teacher_id == teacher.id
    assert request_row.status == MatchRequest.Status.MATCHED
    assert request_row.matched_at is not None


def test_the_second_accepter_gets_a_conflict_not_a_validation_error(
    teacher, other_teacher, request_row
):
    matching.accept_offer(teacher, request_row.id, REFERENCE)

    with pytest.raises(ConflictError):
        matching.accept_offer(other_teacher, request_row.id, REFERENCE)

    assert TeacherAssignment.objects.count() == 1


def test_accepting_an_unknown_request_is_a_404(teacher):
    with pytest.raises(NotFoundError):
        matching.accept_offer(teacher, 999999, REFERENCE)


def test_an_ineligible_teacher_cannot_accept(teacher, request_row):
    # Availability edited between render and click: the inbox showed it, the
    # transaction must still refuse it.
    from kaleem.scheduling.services import set_availability

    set_availability(
        teacher,
        [{"weekday": 3, "start_time": dt.time(9), "end_time": dt.time(12)}],
        timezone="UTC",
    )
    teacher.refresh_from_db()

    with pytest.raises(PermissionDeniedError):
        matching.accept_offer(teacher, request_row.id, REFERENCE)

    assert TeacherAssignment.objects.count() == 0


def test_the_database_refuses_a_second_active_assignment(
    teacher, other_teacher, request_row
):
    # The service is not the only guard: bypass it entirely and the index still
    # holds. This is the invariant, stated where a service bug cannot reach.
    matching.accept_offer(teacher, request_row.id, REFERENCE)

    with pytest.raises(IntegrityError), transaction.atomic():
        TeacherAssignment.objects.create(
            student_id=request_row.student_id,
            teacher=other_teacher,
            subject_id=request_row.subject_id,
            source_request=request_row,
        )


def test_declining_hides_it_from_that_teacher_only(
    teacher, other_teacher, request_row
):
    matching.decline_offer(teacher, request_row.id)

    assert matching.list_offers_for(teacher, REFERENCE) == []
    assert len(matching.list_offers_for(other_teacher, REFERENCE)) == 1


def test_declining_twice_is_not_an_error(teacher, request_row):
    matching.decline_offer(teacher, request_row.id)
    matching.decline_offer(teacher, request_row.id)

    assert MatchDecline.objects.count() == 1
```

`other_teacher` is a second teacher with the same subject, gender and availability as `teacher` — add it to `conftest.py` next to `teacher`.

- [ ] **Step 2: Run and watch them fail**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/scheduling/tests/test_matching_accept.py -v`
Expected: FAIL — `AttributeError: ... has no attribute 'accept_offer'`.

- [ ] **Step 3: Implement**

Append to `kaleem/scheduling/matching.py`:

```python
@transaction.atomic
def accept_offer(teacher, request_id: int, reference_date: dt.date):
    """Claim a student. The whole race lives in these eight lines.

    `select_for_update` serialises concurrent accepts on the request row, and
    eligibility is re-checked *inside* the transaction because the inbox that
    produced this click may be seconds stale -- the teacher could have edited
    their availability in another tab. The partial-unique index on
    (student, subject) WHERE active is the backstop if any of this is wrong.
    """
    request = (
        MatchRequest.objects.select_for_update().filter(id=request_id).first()
    )
    if request is None:
        raise NotFoundError("Match request", request_id)
    if request.status != MatchRequest.Status.OPEN:
        raise ConflictError("Another teacher has already taken this student.")
    if not is_eligible(teacher, request, reference_date):
        raise PermissionDeniedError("accept a match request you are not eligible for")

    request.status = MatchRequest.Status.MATCHED
    request.matched_at = timezone.now()
    request.save(update_fields=["status", "matched_at"])
    return TeacherAssignment.objects.create(
        student_id=request.student_id,
        teacher=teacher,
        subject_id=request.subject_id,
        source_request=request,
    )


def decline_offer(teacher, request_id: int) -> None:
    """Idempotent: declining twice is a double-click, not an error."""
    if not MatchRequest.objects.filter(id=request_id).exists():
        raise NotFoundError("Match request", request_id)
    MatchDecline.objects.get_or_create(request_id=request_id, teacher=teacher)


def list_assignments_for(user) -> list[dict]:
    """Role-aware, and symmetric: each side sees the other's name, never their
    email (ADR-0023)."""
    rows = (
        TeacherAssignment.objects.filter(status=TeacherAssignment.Status.ACTIVE)
        .filter(models.Q(student=user) | models.Q(teacher=user))
        .select_related("subject", "student", "teacher")
        .order_by("created_at")
    )
    return [
        {
            "id": row.id,
            "subject_slug": row.subject.slug,
            "subject_name": row.subject.name,
            "teacher_name": row.teacher.full_name,
            "student_name": row.student.full_name,
            "since": row.created_at,
        }
        for row in rows
    ]
```

Add to that module's imports:

```python
from django.db import models
from django.db import transaction
from django.utils import timezone

from kaleem.platform.exceptions import ConflictError
from kaleem.platform.exceptions import NotFoundError
from kaleem.platform.exceptions import PermissionDeniedError
```

- [ ] **Step 4: Re-export the public API**

Append to `kaleem/scheduling/services.py`:

```python
# Matching's public entry points. The implementation lives in `matching.py` --
# availability and matching are two responsibilities and share no state -- but
# other modules and the API layer see one public API, per D4.
from kaleem.scheduling.matching import accept_offer  # noqa: E402, F401
from kaleem.scheduling.matching import decline_offer  # noqa: E402, F401
from kaleem.scheduling.matching import list_assignments_for  # noqa: E402, F401
from kaleem.scheduling.matching import list_offers_for  # noqa: E402, F401
from kaleem.scheduling.matching import sync_match_requests  # noqa: E402, F401
```

If `matching.py` importing `services.to_utc_intervals` while `services.py` imports from `matching` creates a circular import, move `to_utc_intervals` into `matching.py`'s own import of the model layer instead — do **not** solve it with a function-local import.

- [ ] **Step 5: Run the tests**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/scheduling/ -v`
Expected: all pass, including the earlier matching files.

- [ ] **Step 6: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A && PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): accept and decline a match offer

Accept is select_for_update plus an in-transaction eligibility re-check,
with the partial-unique index as the backstop. The loser gets a typed 409."
```

---

### Task 8: The API

**Files:**
- Create: `kaleem/scheduling/api/matching_serializers.py`
- Modify: `kaleem/scheduling/api/views.py`
- Modify: `kaleem/scheduling/api/urls.py`
- Test: `kaleem/scheduling/tests/test_matching_api.py`

**Interfaces:**
- Consumes: everything re-exported in Task 7.
- Produces: five routes under `/api/v1/scheduling/`, named `scheduling:match-offers`, `scheduling:match-offer-accept`, `scheduling:match-offer-decline`, `scheduling:match-requests-mine`, `scheduling:assignments`.

- [ ] **Step 1: Write the failing tests**

Create `kaleem/scheduling/tests/test_matching_api.py`:

```python
import datetime as dt

import pytest
from django.urls import reverse
from rest_framework.test import APIClient

from kaleem.scheduling.models import MatchRequest
from kaleem.scheduling.models import TeacherAssignment

pytestmark = pytest.mark.django_db


@pytest.fixture
def teacher_client(teacher):
    client = APIClient()
    client.force_authenticate(teacher)
    return client


def test_the_inbox_lists_eligible_requests(teacher_client, request_row):
    response = teacher_client.get(reverse("api:scheduling:match-offers"))

    assert response.status_code == 200
    assert response.data[0]["request_id"] == request_row.id
    assert "overlap_minutes" in response.data[0]


def test_the_inbox_403s_for_a_caller_without_a_teacher_profile(student):
    client = APIClient()
    client.force_authenticate(student)

    response = client.get(reverse("api:scheduling:match-offers"))

    assert response.status_code == 403


def test_accepting_returns_the_assignment(teacher_client, request_row):
    response = teacher_client.post(
        reverse("api:scheduling:match-offer-accept", args=[request_row.id])
    )

    assert response.status_code == 201
    assert response.data["subject_slug"] == "quran"
    assert TeacherAssignment.objects.count() == 1


def test_accepting_a_taken_request_returns_409(
    teacher_client, other_teacher, request_row
):
    from kaleem.scheduling import matching

    matching.accept_offer(other_teacher, request_row.id, dt.date.today())

    response = teacher_client.post(
        reverse("api:scheduling:match-offer-accept", args=[request_row.id])
    )

    assert response.status_code == 409
    assert response.data["code"] == "conflict"


def test_declining_returns_204_and_empties_the_inbox(teacher_client, request_row):
    response = teacher_client.post(
        reverse("api:scheduling:match-offer-decline", args=[request_row.id])
    )

    assert response.status_code == 204
    assert teacher_client.get(reverse("api:scheduling:match-offers")).data == []


def test_a_student_sees_their_pending_request(student, request_row):
    client = APIClient()
    client.force_authenticate(student)

    response = client.get(reverse("api:scheduling:match-requests-mine"))

    assert response.status_code == 200
    assert response.data[0]["status"] == MatchRequest.Status.OPEN
    assert response.data[0]["subject_slug"] == "quran"


def test_both_sides_see_the_assignment_and_no_email_appears(
    teacher, teacher_client, student, request_row
):
    teacher_client.post(
        reverse("api:scheduling:match-offer-accept", args=[request_row.id])
    )
    student_client = APIClient()
    student_client.force_authenticate(student)

    teacher_view = teacher_client.get(reverse("api:scheduling:assignments"))
    student_view = student_client.get(reverse("api:scheduling:assignments"))

    assert len(teacher_view.data) == 1
    assert len(student_view.data) == 1
    body = str(teacher_view.data) + str(student_view.data)
    assert student.email not in body
    assert teacher.email not in body
```

- [ ] **Step 2: Run and watch them fail**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/scheduling/tests/test_matching_api.py -v`
Expected: FAIL — `NoReverseMatch: 'match-offers' is not a valid view function or pattern name`.

- [ ] **Step 3: Write the serializers**

Create `kaleem/scheduling/api/matching_serializers.py`:

```python
from rest_framework import serializers


class OfferSerializer(serializers.Serializer):
    """Read-only projection of a computed offer. Deliberately not a
    ModelSerializer: an offer is not a row, and there is no model to bind to."""

    request_id = serializers.IntegerField()
    student_name = serializers.CharField()
    subject_slug = serializers.CharField()
    subject_name = serializers.CharField()
    overlap_minutes = serializers.IntegerField()
    waiting_since = serializers.DateTimeField()


class MatchRequestSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    subject_slug = serializers.CharField()
    subject_name = serializers.CharField()
    status = serializers.CharField()
    teacher_name = serializers.CharField(allow_blank=True)


class AssignmentSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    subject_slug = serializers.CharField()
    subject_name = serializers.CharField()
    teacher_name = serializers.CharField()
    student_name = serializers.CharField()
    since = serializers.DateTimeField()
```

- [ ] **Step 4: Write the views**

Append to `kaleem/scheduling/api/views.py`:

```python
import datetime as dt

from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from kaleem.identity import services as identity_services
from kaleem.platform.exceptions import PermissionDeniedError
from kaleem.scheduling import services
from kaleem.scheduling.api.matching_serializers import AssignmentSerializer
from kaleem.scheduling.api.matching_serializers import MatchRequestSerializer
from kaleem.scheduling.api.matching_serializers import OfferSerializer
from kaleem.scheduling.models import MatchRequest
from kaleem.scheduling.models import TeacherAssignment


def _require_teacher(user):
    if identity_services.get_teacher_profile(user.id) is None:
        raise PermissionDeniedError("view match offers without a teacher profile")


def _today():
    # A seam, so a test can pin the reference week without freezing the clock
    # globally.
    return dt.date.today()


class MatchOfferListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        _require_teacher(request.user)
        # Reconcile on read: this is the pull half of "auto on subscribe". It is
        # idempotent, so doing it here costs a query and needs no scheduler.
        services.sync_match_requests()
        offers = services.list_offers_for(request.user, _today())
        return Response(OfferSerializer(offers, many=True).data)


class MatchOfferAcceptView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, request_id: int):
        _require_teacher(request.user)
        assignment = services.accept_offer(request.user, request_id, _today())
        return Response(
            AssignmentSerializer(
                {
                    "id": assignment.id,
                    "subject_slug": assignment.subject.slug,
                    "subject_name": assignment.subject.name,
                    "teacher_name": assignment.teacher.full_name,
                    "student_name": assignment.student.full_name,
                    "since": assignment.created_at,
                }
            ).data,
            status=status.HTTP_201_CREATED,
        )


class MatchOfferDeclineView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, request_id: int):
        _require_teacher(request.user)
        services.decline_offer(request.user, request_id)
        return Response(status=status.HTTP_204_NO_CONTENT)


class MyMatchRequestsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        services.sync_match_requests()
        rows = (
            MatchRequest.objects.filter(student=request.user)
            .exclude(status=MatchRequest.Status.CANCELLED)
            .select_related("subject")
            .order_by("created_at")
        )
        matched = {
            a.source_request_id: a.teacher.full_name
            for a in TeacherAssignment.objects.filter(
                student=request.user, status=TeacherAssignment.Status.ACTIVE
            ).select_related("teacher")
        }
        payload = [
            {
                "id": row.id,
                "subject_slug": row.subject.slug,
                "subject_name": row.subject.name,
                "status": row.status,
                "teacher_name": matched.get(row.id, ""),
            }
            for row in rows
        ]
        return Response(MatchRequestSerializer(payload, many=True).data)


class AssignmentListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(
            AssignmentSerializer(
                services.list_assignments_for(request.user), many=True
            ).data
        )
```

- [ ] **Step 5: Wire the routes**

Replace `kaleem/scheduling/api/urls.py` with:

```python
from django.urls import path

from kaleem.scheduling.api.views import AssignmentListView
from kaleem.scheduling.api.views import AvailabilityView
from kaleem.scheduling.api.views import MatchOfferAcceptView
from kaleem.scheduling.api.views import MatchOfferDeclineView
from kaleem.scheduling.api.views import MatchOfferListView
from kaleem.scheduling.api.views import MyMatchRequestsView

app_name = "scheduling"
urlpatterns = [
    path("me/availability/", AvailabilityView.as_view(), name="availability"),
    path("match-offers/", MatchOfferListView.as_view(), name="match-offers"),
    path(
        "match-offers/<int:request_id>/accept/",
        MatchOfferAcceptView.as_view(),
        name="match-offer-accept",
    ),
    path(
        "match-offers/<int:request_id>/decline/",
        MatchOfferDeclineView.as_view(),
        name="match-offer-decline",
    ),
    path(
        "match-requests/mine/",
        MyMatchRequestsView.as_view(),
        name="match-requests-mine",
    ),
    path("assignments/", AssignmentListView.as_view(), name="assignments"),
]
```

- [ ] **Step 6: Run the tests, including the versioning guard**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/scheduling/ tests/test_api_versioning_is_enforced.py -v`
Expected: all pass. The versioning test walks the resolved URLconf; these routes are mounted under `scheduling/` inside `api_router`, so they are already `/api/v1/`-prefixed.

- [ ] **Step 7: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A && PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): matching API

Five routes under /api/v1/scheduling/. The inbox reconciles on read, which
is the pull half of auto-on-subscribe."
```

---

### Task 9: Admin, e2e seed, and the backend gate

The spec promises staff can see an unmatched request; nothing in Tasks 1–8 delivers that. The e2e fixture also has to exist before Task 14 can be written.

**Files:**
- Modify: `kaleem/scheduling/admin.py`
- Create: `kaleem/scheduling/management/commands/seed_e2e_matching.py`
- Create: `kaleem/scheduling/management/__init__.py`, `kaleem/scheduling/management/commands/__init__.py`
- Test: `kaleem/scheduling/tests/test_seed_e2e_matching.py`

**Interfaces:**
- Produces: management command `seed_e2e_matching`, which gives the existing `e2e.teacher@kaleem.test` and `e2e.student@kaleem.test` accounts overlapping availability, a shared subject, a declared gender, and an entitlement, so a match offer exists deterministically.

The matching fixture cannot live in `identity`'s `seed_e2e`: `identity` is forbidden to import `curriculum` or `billing`, and that contract is not being widened. `scheduling` may import all three (ADR-0033), so the matching half of the fixture belongs here — one command per module that owns the data.

- [ ] **Step 1: Register the models in admin**

Append to `kaleem/scheduling/admin.py`:

```python
from kaleem.scheduling.models import MatchDecline
from kaleem.scheduling.models import MatchRequest
from kaleem.scheduling.models import TeacherAssignment


@admin.register(MatchRequest)
class MatchRequestAdmin(admin.ModelAdmin):
    # An open request has no deadline by design, so this list is the only place
    # a long wait becomes visible. Ordering oldest-first is the point.
    list_display = ("student", "subject", "status", "created_at", "matched_at")
    list_filter = ("status", "subject")
    search_fields = ("student__email", "student__full_name")
    ordering = ("created_at",)


@admin.register(TeacherAssignment)
class TeacherAssignmentAdmin(admin.ModelAdmin):
    list_display = ("student", "teacher", "subject", "status", "created_at")
    list_filter = ("status", "subject")
    search_fields = ("student__email", "teacher__email")


@admin.register(MatchDecline)
class MatchDeclineAdmin(admin.ModelAdmin):
    list_display = ("request", "teacher", "created_at")
```

- [ ] **Step 2: Write the failing seed test**

Create `kaleem/scheduling/tests/test_seed_e2e_matching.py`:

```python
import datetime as dt

import pytest
from django.core.management import CommandError
from django.core.management import call_command

from kaleem.scheduling import matching
from kaleem.scheduling.models import MatchRequest

pytestmark = pytest.mark.django_db


def test_it_refuses_to_run_outside_debug(settings):
    settings.DEBUG = False

    with pytest.raises(CommandError):
        call_command("seed_e2e_matching")


def test_it_produces_exactly_one_live_offer(settings):
    settings.DEBUG = True
    call_command("seed_e2e")
    call_command("seed_e2e_matching")

    from kaleem.identity.models import User

    teacher = User.objects.get(email="e2e.teacher@kaleem.test")
    offers = matching.list_offers_for(teacher, dt.date.today())

    assert MatchRequest.objects.filter(status=MatchRequest.Status.OPEN).count() == 1
    assert len(offers) == 1


def test_it_is_idempotent(settings):
    settings.DEBUG = True
    call_command("seed_e2e")
    call_command("seed_e2e_matching")
    call_command("seed_e2e_matching")

    assert MatchRequest.objects.filter(status=MatchRequest.Status.OPEN).count() == 1
```

- [ ] **Step 3: Run and watch them fail**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/scheduling/tests/test_seed_e2e_matching.py -v`
Expected: FAIL — `CommandError: Unknown command: 'seed_e2e_matching'`.

- [ ] **Step 4: Write the command**

Create `kaleem/scheduling/management/commands/seed_e2e_matching.py`:

```python
"""The matching half of the e2e fixture.

Separate from identity's `seed_e2e` because identity may not import curriculum
or billing, and that contract is not being widened for a fixture. Run both:
`seed_e2e` makes the accounts, this gives them the state a match needs.

Idempotent in the strong sense, like its sibling: it converges on the declared
state rather than skipping work when rows already exist.
"""

import datetime as dt

from django.conf import settings
from django.core.management.base import BaseCommand
from django.core.management.base import CommandError
from django.db import transaction
from django.utils import timezone

from kaleem.billing.models import Subscription
from kaleem.billing.models import SubscriptionPlan
from kaleem.curriculum import services as curriculum_services
from kaleem.identity.models import TeacherProfile
from kaleem.identity.models import User
from kaleem.scheduling import matching
from kaleem.scheduling.models import MatchDecline
from kaleem.scheduling.models import MatchRequest
from kaleem.scheduling.models import TeacherAssignment
from kaleem.scheduling.services import set_availability

TEACHER_EMAIL = "e2e.teacher@kaleem.test"
STUDENT_EMAIL = "e2e.student@kaleem.test"
SUBJECT_SLUG = "quran"
# Real-shaped, not a stub: `sub_` plus 24 characters, so the column's length
# constraint stays exercised.
E2E_SUBSCRIPTION_ID = "sub_e2ematching0000000001"
E2E_PRICE_ID = "price_e2ematching00000001"


class Command(BaseCommand):
    help = "Give the e2e teacher and student the state one match needs."

    def handle(self, *args, **options):
        if not settings.DEBUG:
            raise CommandError(
                "seed_e2e_matching creates a fixture subscription and refuses to "
                "run with DEBUG=False. Local development and CI only."
            )

        with transaction.atomic():
            teacher = User.objects.get(email=TEACHER_EMAIL)
            student = User.objects.get(email=STUDENT_EMAIL)

            profile, _ = TeacherProfile.objects.get_or_create(user=teacher)
            profile.gender = TeacherProfile.Gender.MALE
            profile.save(update_fields=["gender"])

            curriculum_services.set_teacher_subjects(teacher.id, [SUBJECT_SLUG])
            curriculum_services.set_student_subjects(student.id, [SUBJECT_SLUG])

            # Identical UTC windows on the same weekday: overlap by construction,
            # so the spec never depends on what timezone CI happens to run in.
            window = [
                {
                    "weekday": 0,
                    "start_time": dt.time(9),
                    "end_time": dt.time(12),
                }
            ]
            set_availability(teacher, window, timezone="UTC")
            set_availability(student, window, timezone="UTC")

            plan, _ = SubscriptionPlan.objects.get_or_create(
                stripe_price_id=E2E_PRICE_ID,
                defaults={
                    "name": "E2E matching plan",
                    "amount": 5000,
                    "currency": "usd",
                    "is_active": True,
                },
            )
            Subscription.objects.update_or_create(
                stripe_subscription_id=E2E_SUBSCRIPTION_ID,
                defaults={
                    "user": student,
                    "plan": plan,
                    "status": Subscription.Status.ACTIVE,
                    "current_period_end": timezone.now() + dt.timedelta(days=30),
                },
            )

            # Reset anything a previous run's spec left matched, then reconcile.
            MatchRequest.objects.filter(student=student).delete()
            TeacherAssignment.objects.filter(student=student).delete()
            MatchDecline.objects.filter(teacher=teacher).delete()
            opened = matching.sync_match_requests()

        self.stdout.write(
            self.style.SUCCESS(f"Seeded e2e matching state. Opened {opened} request(s).")
        )
```

If `SubscriptionPlan` needs fields beyond these, copy the working construction from `kaleem/billing/tests/` rather than guessing.

- [ ] **Step 5: Run the seed tests**

Run: `docker compose -f docker-compose.local.yml run --rm django pytest kaleem/scheduling/tests/test_seed_e2e_matching.py -v`
Expected: 3 passed.

- [ ] **Step 6: Run the full backend gate**

Run:
```bash
docker compose -f docker-compose.local.yml run --rm django pytest
docker compose -f docker-compose.local.yml run --rm django lint-imports
docker compose -f docker-compose.local.yml run --rm django ruff check .
docker compose -f docker-compose.local.yml run --rm django mypy kaleem
```
Expected: all green, coverage ≥ 97 line and branch. If coverage came out above 97, **raise the floor in `pyproject.toml` to the new number** — that is a normal part of this PR (ADR-0026), not a separate task.

- [ ] **Step 7: Commit and open the backend PR**

```bash
PIP_CONFIG_FILE=/dev/null git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): admin surface and the e2e matching fixture"
git push -u origin feat/phase-c1-matching
gh pr create --base main --title "feat(scheduling): Phase C1 — matching" --body "Implements docs/superpowers/specs/2026-09-05-phase-c1-matching-design.md. Boundary change per ADR-0033, both new contracts verified by breaking them."
```

---

### Task 10: Dashboard — the matching feature module

Switch repos: everything from here is in `dashboard`, on `feat/phase-c1-matching`.

**Files:**
- Create: `src/features/matching/schemas.ts`
- Create: `src/features/matching/api.ts`
- Create: `src/features/matching/queries.ts`
- Create: `src/features/matching/index.ts`
- Test: `src/features/matching/api.test.ts`, `src/features/matching/queries.test.tsx`

A new `features/matching/` rather than extending `features/scheduling/`: the availability editor and the match inbox share no state, no queries and no components, and `features/` is already organised by feature rather than by module.

**Interfaces:**
- Produces: `useMatchOffers()`, `useAcceptOffer()`, `useDeclineOffer()`, `useMyMatchRequests()`, `useAssignments()`, and the `Offer` / `MatchRequest` / `Assignment` types.

- [ ] **Step 1: Write the schemas**

Create `src/features/matching/schemas.ts`:

```ts
import { z } from "zod";

export const offerSchema = z.object({
	request_id: z.number(),
	student_name: z.string(),
	subject_slug: z.string(),
	subject_name: z.string(),
	overlap_minutes: z.number(),
	waiting_since: z.string(),
});

export const matchRequestSchema = z.object({
	id: z.number(),
	subject_slug: z.string(),
	subject_name: z.string(),
	status: z.enum(["open", "matched", "cancelled"]),
	teacher_name: z.string(),
});

export const assignmentSchema = z.object({
	id: z.number(),
	subject_slug: z.string(),
	subject_name: z.string(),
	teacher_name: z.string(),
	student_name: z.string(),
	since: z.string(),
});

export type Offer = z.infer<typeof offerSchema>;
export type MatchRequest = z.infer<typeof matchRequestSchema>;
export type Assignment = z.infer<typeof assignmentSchema>;
```

- [ ] **Step 2: Write the failing api test**

Create `src/features/matching/api.test.ts`, following the shape of `src/features/curriculum/api.test.ts` (read it first — it establishes how `api` is mocked in this repo). Assert that:

```ts
it("hits the versioned relative paths", async () => {
	await matchingApi.listOffers();
	expect(api.get).toHaveBeenCalledWith("scheduling/match-offers/");

	await matchingApi.accept(7);
	expect(api.post).toHaveBeenCalledWith("scheduling/match-offers/7/accept/");
});
```

Paths are **relative** — the version lives in `VITE_API_URL` (ADR-0029). A leading slash here would bypass the versioned base.

- [ ] **Step 3: Run and watch it fail**

Run: `pnpm vitest run src/features/matching/api.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 4: Write the api client**

Create `src/features/matching/api.ts`:

```ts
import { api } from "@/lib/api";
import type { Assignment, MatchRequest, Offer } from "./schemas";

export const matchingApi = {
	listOffers: () =>
		api.get<Offer[]>("scheduling/match-offers/").then((r) => r.data),
	accept: (requestId: number) =>
		api
			.post<Assignment>(`scheduling/match-offers/${requestId}/accept/`)
			.then((r) => r.data),
	decline: (requestId: number) =>
		api.post<void>(`scheduling/match-offers/${requestId}/decline/`).then(() => {}),
	myRequests: () =>
		api
			.get<MatchRequest[]>("scheduling/match-requests/mine/")
			.then((r) => r.data),
	assignments: () =>
		api.get<Assignment[]>("scheduling/assignments/").then((r) => r.data),
};
```

- [ ] **Step 5: Write the queries**

Create `src/features/matching/queries.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { matchingApi } from "./api";

export const matchOffersQueryKey = ["match-offers"] as const;
export const myMatchRequestsQueryKey = ["my-match-requests"] as const;
export const assignmentsQueryKey = ["assignments"] as const;

export function useMatchOffers() {
	return useQuery({
		queryKey: matchOffersQueryKey,
		queryFn: matchingApi.listOffers,
		retry: false,
	});
}

export function useMyMatchRequests() {
	return useQuery({
		queryKey: myMatchRequestsQueryKey,
		queryFn: matchingApi.myRequests,
		retry: false,
	});
}

export function useAssignments() {
	return useQuery({
		queryKey: assignmentsQueryKey,
		queryFn: matchingApi.assignments,
		retry: false,
	});
}

export function useAcceptOffer() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (requestId: number) => matchingApi.accept(requestId),
		// Both keys: accepting removes a row from the inbox *and* adds an
		// assignment. Invalidating only the inbox leaves the teacher's own
		// student list stale until a reload.
		onSettled: () => {
			qc.invalidateQueries({ queryKey: matchOffersQueryKey });
			qc.invalidateQueries({ queryKey: assignmentsQueryKey });
		},
	});
}

export function useDeclineOffer() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (requestId: number) => matchingApi.decline(requestId),
		onSuccess: () => qc.invalidateQueries({ queryKey: matchOffersQueryKey }),
	});
}
```

`onSettled` rather than `onSuccess` on accept: a 409 means someone else took the student, so the inbox is stale precisely when the mutation *failed*.

- [ ] **Step 6: Write `index.ts` and the queries test**

`index.ts` re-exports the hooks and types, following `src/features/curriculum/index.ts`. Write `queries.test.tsx` following `src/features/curriculum/queries.test.tsx`, covering: offers load; accept invalidates both keys; a 409 from accept still invalidates.

- [ ] **Step 7: Run the tests**

Run: `pnpm vitest run src/features/matching/`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git commit -am "feat(matching): api client, schemas and queries"
```

---

### Task 11: The teacher inbox

**Files:**
- Create: `src/features/matching/components/MatchOfferList.tsx`
- Create: `src/features/matching/components/MatchOfferList.test.tsx`
- Create: `src/routes/_authed/match-requests.tsx`
- Create: `src/routes/_authed/match-requests.test.tsx`
- Modify: `src/features/shell/nav.ts`, `src/features/shell/nav.test.ts`
- Modify: `src/locales/en/common.json`, `src/locales/ar/common.json`

**Interfaces:**
- Consumes: `useMatchOffers`, `useAcceptOffer`, `useDeclineOffer` (Task 10).

- [ ] **Step 1: Write the failing component test**

Create `src/features/matching/components/MatchOfferList.test.tsx`. Read `src/features/curriculum/components/SubjectsCard.test.tsx` first for the render helper and i18n setup this repo uses. Cover:

```tsx
it("renders an offer with the student name and the overlap", async () => { /* … */ });
it("shows the empty state when there are no offers", async () => { /* … */ });
it("shows the loading state", async () => { /* … */ });
it("surfaces a server error", async () => { /* … */ });
it("renders a 409 as 'another teacher took this', not as a failure", async () => {
	// The mutation rejects with a 409; the row disappears and the message is
	// informational. This is normal traffic in a first-to-accept race, and the
	// single most likely thing to be got wrong.
});
it("removes a declined offer", async () => { /* … */ });
```

- [ ] **Step 2: Run and watch it fail**

Run: `pnpm vitest run src/features/matching/components/MatchOfferList.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Build the component**

Create `MatchOfferList.tsx` using existing `@/ui` primitives (`Card`, `CardHeader`, `CardTitle`, `CardContent`, `Button`) — do not introduce new primitives, and do not write a hex colour or `color-mix` anywhere. Every string comes from `t(…)`. Requirements:

- One row per offer: student name, subject name, a human overlap summary (`t("matching.overlapHours", { count })` — convert minutes to hours in the component, not in the API), and Accept / Decline buttons.
- Accept in flight disables both buttons on that row only.
- A rejected accept whose status is 409 renders `t("matching.alreadyTaken")` as an informational message, not an error, and the list refetches.
- Empty state: `t("matching.noOffers")`.
- Buttons carry accessible names; the list is a `<ul>`; loading uses the repo's existing skeleton or spinner pattern.

- [ ] **Step 4: Add the i18n keys**

Add to **both** `src/locales/en/common.json` and `src/locales/ar/common.json`, under a new `matching` object: `title`, `noOffers`, `overlapHours`, `accept`, `decline`, `alreadyTaken`, `error`, `waitingSince`, plus `nav.matchRequests`. Arabic must be real Arabic, not an English placeholder.

- [ ] **Step 5: Add the route and the nav entry**

`src/routes/_authed/match-requests.tsx` renders `<PageContainer><PageHeader title={t("matching.title")} /><MatchOfferList /></PageContainer>`, following `src/routes/_authed/availability.tsx`.

In `src/features/shell/nav.ts`, add after the `/availability` entry:

```ts
	{
		to: "/match-requests",
		labelKey: "nav.matchRequests",
		icon: UserPlus,
		requires: "teacher",
	},
```

Import `UserPlus` from `lucide-react`. Update `src/features/shell/nav.test.ts` — it asserts the **exact** ordered list of nav paths, so it fails until the new entry is added there too. Add an assertion that `/match-requests` is teacher-only, mirroring the existing `/availability` one.

- [ ] **Step 6: Run the tests**

Run: `pnpm vitest run src/features/matching src/features/shell src/routes/_authed/match-requests.test.tsx`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git commit -am "feat(matching): the teacher match-request inbox

A 409 renders as 'another teacher took this'. In a first-to-accept race
that is normal traffic, not an error."
```

---

### Task 12: The student and parent side

**Files:**
- Create: `src/features/matching/components/MyTeacherCard.tsx`
- Create: `src/features/matching/components/MyTeacherCard.test.tsx`
- Modify: `src/routes/_authed/account.tsx`
- Modify: `src/routes/_authed/account.test.tsx`
- Modify: `src/locales/en/common.json`, `src/locales/ar/common.json`

- [ ] **Step 1: Write the failing test**

`MyTeacherCard.test.tsx` covers: a pending request renders the searching state; a matched request renders the teacher's name; a student with no requests renders nothing at all (not an empty card); the error state.

The pending copy is load-bearing — an open request has no deadline, so it must not imply one. Assert the string is the `matching.searching` key and that no time estimate appears.

- [ ] **Step 2: Run and watch it fail**

Run: `pnpm vitest run src/features/matching/components/MyTeacherCard.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Build the component**

`MyTeacherCard` calls `useMyMatchRequests()`, returns `null` when the list is empty, and otherwise renders one row per request: subject name plus either `t("matching.searching")` or the teacher's name. New keys in both locales: `myTeacher`, `searching`, `matchedWith`.

- [ ] **Step 4: Mount it on the account page**

In `src/routes/_authed/account.tsx`, inside `<CardGrid>`, after the student subjects panel:

```tsx
				{isStudent ? <MyTeacherCard /> : null}
```

Update `account.test.tsx`: a student sees it, a parent with no student profile does not.

- [ ] **Step 5: Run the tests and the whole gate**

Run:
```bash
pnpm vitest run
pnpm lint
pnpm tsc --noEmit
```
Expected: green, coverage ≥ 92 lines / 87 branches / 84 functions. If it came out higher, **raise the floors in `vitest.config.ts`** as part of this PR.

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(matching): show a student who their teacher is, or that we are looking"
```

---

### Task 13: RTL and a real browser

Not optional and not a formality: this is D9's manual click-through, and the two panels in C0 that automation could not reach are exactly why it is a task with steps rather than a line in a checklist.

- [ ] **Step 1: Bring up the stack**

Follow the local visual-run recipe: the dashboard at `app.kaleem.localhost` with the backend on its sibling subdomain. `just dev` cannot bind `:80` on this machine, so use the documented one-off container topology.

- [ ] **Step 2: Seed**

```bash
docker compose -f docker-compose.local.yml run --rm django python manage.py seed_e2e
docker compose -f docker-compose.local.yml run --rm django python manage.py seed_e2e_matching
```

- [ ] **Step 3: Click through as the teacher**

Log in as `e2e.teacher@kaleem.test`. Confirm: the nav shows Match requests; the page lists one offer with the student's name and an overlap figure; **no email address appears anywhere on the page**; Accept works and the row disappears.

- [ ] **Step 4: Click through as the student**

Log in as `e2e.student@kaleem.test`, open `/account`, confirm the card names the teacher. Re-seed and check the pending state reads honestly before any teacher accepts.

- [ ] **Step 5: Switch to Arabic and check RTL**

Both pages: layout mirrors, no clipped text, no `scrollWidth` overflow past the viewport, buttons still reachable by keyboard, focus ring visible.

- [ ] **Step 6: Record what you saw**

If anything is wrong and it is *not* part of C1, add a line to `ISSUES.md` and keep going (D10). If it is part of C1, fix it here.

---

### Task 14: e2e

**Files:**
- Create: `e2e/matching.spec.ts`
- Modify: `e2e/fixtures.ts` if a helper is genuinely shared (do not copy the login helper)
- Modify: the CI workflow step that seeds, to call `seed_e2e_matching` after `seed_e2e`

- [ ] **Step 1: Write the spec**

Create `e2e/matching.spec.ts`, following `e2e/subjects.spec.ts`. Three flows:

```ts
test("a teacher accepts a match and the student sees them", async ({ page }) => {
	// login as teacher → /match-requests → expect one offer → Accept
	// → login as student → /account → expect the teacher's name
});

test("an accepted request leaves the inbox after a reload", async ({ page }) => {
	// proves the server, not just optimistic client state
});

test("a student with no match sees the searching state", async ({ page }) => {
	// run before any accept, or against a second subject
});
```

Every flow is a **write** across the ADR-0019 boundary, so each one also exercises real CSRF on a real mutation — state that in a comment, the way the other specs do.

Order matters here in a way it does not elsewhere: accepting is destructive to the fixture (the request becomes `MATCHED` and cannot be re-offered). Either run the searching-state assertion first, or re-seed between flows. Say which one you chose in a comment — a later reader will otherwise "tidy" the ordering and break it.

- [ ] **Step 2: Wire the seed into CI**

Find where the e2e job runs `seed_e2e` in the CI workflow and add `seed_e2e_matching` immediately after. Without it the suite passes locally and fails in CI, which is the worst of both.

- [ ] **Step 3: Run the whole suite locally against a real stack**

Run: `pnpm playwright test`
Expected: the existing 24 flows plus the 3 new ones, all green.

- [ ] **Step 4: Mutation-check one assertion**

Break `accept_offer` in the backend so it does not set `status = MATCHED`, and confirm the "leaves the inbox after a reload" flow turns red. Restore it. An e2e assertion nobody has watched fail is not known to test anything.

- [ ] **Step 5: Commit and open the dashboard PR**

```bash
git add -A
git commit -m "test(e2e): matching — offer, accept, and the student's view

Every flow is a write across the subdomain boundary, so CSRF on real
mutations is covered too."
git push -u origin feat/phase-c1-matching
gh pr create --base main --title "feat(matching): Phase C1 dashboard" --body "Implements docs/superpowers/specs/2026-09-05-phase-c1-matching-design.md."
```

- [ ] **Step 6: Bump the submodule pointers**

Once both submodule PRs are merged, open the meta PR that bumps both pointers, updates `STATE.md`, updates the D3 e2e table in `CLAUDE.md` (matching becomes a covered area with 3 flows), and writes the journal entry. **Merging that meta PR deploys to staging** — merge deliberately.

---

## Notes for the executor

- **The reference date.** Availability is a recurring weekly pattern, so every overlap calculation needs a week to anchor to. Views pass `dt.date.today()` through a `_today()` seam. Do not freeze the clock globally in tests; pass an explicit date, as the tests here do.
- **Reconcile-on-read is deliberate.** It looks like a hack and is not: the reconciler is idempotent, so calling it on a read is correct and merely repeated. The alternative — an event bus or a beat schedule — is real infrastructure the spec explicitly declined.
- **If you find yourself wanting an offers table,** re-read the spec's data-model section before writing it. That is the decision the whole design turns on, and it was made with reasons.
- **If a task turns out to need something not in this plan,** stop and say so rather than improvising across a module boundary. Boundary changes need an ADR (D8), not a line in an implementation PR.
