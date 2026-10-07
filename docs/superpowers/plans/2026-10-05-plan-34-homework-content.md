# Plan 34 — B6b Homework & Educational Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Homework (set by a teacher or the office, answered by the student or a parent, reviewed and completed by the teacher) and per-course educational content in `etqan.learning`, with API, dashboard screens and e2e, behind the switches `homework` and `educational_content` (off by default).

**Architecture:** Two new models in the existing `etqan.learning` app (B6a), private file storage through `etqan.platform.uploads` and `STORAGES["private"]` (B9a precedent), services in `etqan/learning/services/homework.py` and `content.py`, views in `etqan/learning/api/`. Dashboard feature folders `src/features/homework/` and `src/features/content/`.

**Tech Stack:** Django 5 + DRF + django-tenants + pytest; React + TanStack Router/Query + Vitest; Playwright.

**Spec:** `docs/superpowers/specs/2026-10-05-b6b-homework-content-design.md` (decisions H-1…H-14). Phase spec: `docs/superpowers/specs/2026-10-05-b6-learning-design.md`.

**Requires:** B6a (merged before any task starts).

## Global Constraints

- Work from `/home/abdulkhalek/Projects/etqan_tutor-wt/b6`; `backend/` and `dashboard/` are separate git worktrees on `feat/b6b-homework`. Never run `git submodule update` or any writing `git submodule` command.
- Run everything via the stream wrapper `D=/home/abdulkhalek/.claude/jobs/0bc5cdff/tmp/dc` (full path in zsh): `D pytest <paths> -q`; `D django ruff check .`; `D django ruff format --check .`; `D django lint-imports`; `D manage makemigrations learning` then `just migrate`; `D dash pnpm vitest run <paths>`; `D dash pnpm tsc --noEmit`; `D dash pnpm lint`; whole suites `just test`, `just lint`, `just e2e [spec]`, `just seed`.
- Backend coverage ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- Logic only in `etqan/learning/services/`. `etqan.learning` imports only `etqan.platform`, `etqan.identity.services`, `etqan.catalogue.services`, `etqan.scheduling.services`, `etqan.academy.services` (never `etqan.employment`).
- Shared lists: lines only under `── phase B6 ──` markers; the registry's `_later("homework", …)` line is flipped in place. Access route tables in `access/tests/test_routes.py`: append to the existing `# Phase B6` blocks.
- Both switches off by default. Routes under `/api/v1/learning/`. Students addressed by user id.
- Files private (`STORAGES["private"]`), streamed with `FileResponse(as_attachment=True)`, `X-Content-Type-Options: nosniff`, `Cache-Control: private, no-store`. Homework files ≤ 10 MiB (`uploads.CONTRACT_MAX`), content files ≤ 20 MiB (`uploads.LIBRARY_MAX`). Stored names trimmed to 255 keeping the extension.
- Migrations only create new tables.
- Locale files `dashboard/src/locales/{en,ar}/homework.json` and `content.json`, **no top-level wrapper** (keys `homework.*`, `content.*`); en + ar key-equal. Date-only values formatted with `formatDay` (`src/lib/zoned-time.ts`).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`; explicit paths, no `-a`.

## Review Focus

1. **An answer landing on a completed homework** (student submits while the teacher completes): the locked re-check refuses it with 409. Pinned in Task 2 `test_answer_after_complete_conflicts` and by the `select_for_update` in code.
2. **A teacher of course A reaching course B homework of the same student** — list excludes, detail/file 404. Task 2 and Task 5 tests.
3. **The answer route reachable by staff/admin/teacher** — must be 403. Task 5 matrix test.
4. **Orphaned or leaked files** — replaced/removed/deleted files deleted after commit; content files deleted when a course delete cascades; files never served publicly. Tasks 1–3, 6.
5. **Materials visible to a student whose subscription ended** — empty list, 404 file. Task 3 and Task 6.

---

## File Structure

```text
backend/etqan/learning/
  files.py                      private_storage, homework_path, content_path, bounded_name, attach(), remove_after_commit()
  models.py                     + Homework, EducationalContent (+ post_delete receiver in signals.py, connected in apps.ready)
  signals.py                    content file cleanup on row delete
  migrations/0002_homework_content.py
  services/homework.py          homework_queryset, get_homework, set_homework, update_homework, answer_homework, delete_homework
  services/content.py           content_queryset, get_content, create_content, update_content, delete_content, reorder_content
  services/hooks.py             HomeworkEvent, homework_events, HomeworkMonth, homework_of
  api/homework_views.py, api/content_views.py, api/serializers.py (+), api/urls.py (+)
  tests/test_homework.py, test_content.py, test_hooks.py, test_api_homework.py, test_api_content.py
backend/etqan/tenants/seeds/b6.py (+ seed step), etqan/tenants/tests/test_seed_b6.py (+)
dashboard/src/features/homework/   schemas.ts api.ts queries.ts fixtures.ts index.ts HomeworkList.tsx HomeworkDialog.tsx NewHomeworkDialog.tsx MyHomework.tsx (+ tests)
dashboard/src/features/content/    schemas.ts api.ts queries.ts fixtures.ts index.ts ContentAdmin.tsx ContentDialog.tsx Materials.tsx (+ tests)
dashboard/src/routes/_authed/scheduling.homework.tsx teaching.homework.tsx learning.homework.tsx catalogue.content.tsx teaching.materials.tsx learning.materials.tsx
dashboard/src/locales/{en,ar}/homework.json, content.json
dashboard/e2e/b6-homework.spec.ts
```

---

### Task 1: Models, file helpers, switches, resources, migration

**Files:** create `backend/etqan/learning/files.py`, `signals.py`, `tests/test_homework_models.py`; modify `learning/models.py`, `learning/apps.py`, `platform/features.py`, `access/registry.py`, `platform/tests/test_features.py` (BUILT dict: `homework` in place, `educational_content` under the B6 marker), `academy/tests/test_features_api.py` if it pins `homework`'s `built`; generate `migrations/0002_homework_content.py`.

**Interfaces — Produces:**
- `files.private_storage()`, `files.homework_path`, `files.content_path` (callables with `__module__` set for migrations), `files.NAME_MAX = 255`, `files.bounded_name(name) -> str`, `files.attach(field_file, upload, *, extensions, max_bytes) -> tuple[str, str | None]` (stores, returns `(bounded original name, old stored name or None)`), `files.remove_after_commit(name | None)`.
- `HOMEWORK_TYPES = uploads.PDF | {".png", ".jpg", ".jpeg", ".webp"} | uploads.OFFICE | {".txt"} | uploads.AUDIO`; `CONTENT_TYPES = HOMEWORK_TYPES | uploads.VIDEO` (in `files.py`).
- Models exactly as spec §3 (`Homework`, `EducationalContent`) with the CHECKs, the `(student, course)` index, and `Homework.Kind`, `Homework.Status` TextChoices.
- Features `homework` (flipped: `Feature("homework", "Homework", "نظام الواجبات", "teaching", built=True)`), `educational_content` (new, B6 marker, `"Educational content"`, `"المحتوى التعليمي"`, `"teaching"`, built, off).
- Resources under the B6 marker: `Resource("homework", "Homework", "الواجبات", ("view", "view_any", "create", "update", "delete"))`, `Resource("educational_content", "Educational content", "المحتوى التعليمي", ("view_any", "create", "update", "delete", "reorder"))`.

- [ ] **Step 1: failing tests** — `tests/test_homework_models.py`

```python
from datetime import date

import pytest
from django.core.files.base import ContentFile
from django.db import IntegrityError
from django.db import transaction
from django.utils import timezone

from etqan.learning import files
from etqan.learning.models import EducationalContent
from etqan.learning.models import Homework
from etqan.platform import features


def test_switches_are_built_and_off():
    for code in ("homework", "educational_content"):
        assert features.get(code).built is True
        assert features.get(code).default is False


def test_bounded_name_keeps_extension():
    long = "a" * 300 + ".pdf"
    out = files.bounded_name(long)
    assert len(out) == 255 and out.endswith(".pdf")
    assert files.bounded_name("x.pdf") == "x.pdf"


def _hw(world, **extra):
    fields = {"student": world.student_profile, "course": world.course, "title": "T", "kind": "text", "instructions": "Read"}
    return Homework(**(fields | extra))


@pytest.mark.parametrize(
    "extra",
    [
        {"kind": "text", "instructions": ""},
        {"kind": "file", "instructions": "x"},  # no file
        {"status": "complete"},  # no completed_at
        {"completed_at": timezone.now()},  # incomplete with completed_at
        {"kind": "audio"},
    ],
)
def test_homework_checks(world, extra):
    with pytest.raises(IntegrityError), transaction.atomic():
        _hw(world, **extra).save()


def test_file_homework_saves_with_a_file(world):
    hw = _hw(world, kind="file", instructions="")
    hw.file.save("w.pdf", ContentFile(b"%PDF-1.4"), save=False)
    hw.save()
    assert hw.file.storage is files.private_storage()


def test_content_needs_exactly_one_of_file_or_url(world):
    with pytest.raises(IntegrityError), transaction.atomic():
        EducationalContent.objects.create(course=world.course, title="x", position=0)
    with pytest.raises(IntegrityError), transaction.atomic():
        c = EducationalContent(course=world.course, title="x", position=0, url="https://e.test")
        c.file.save("a.pdf", ContentFile(b"%PDF-1.4"), save=False)
        c.save()
    EducationalContent.objects.create(course=world.course, title="ok", position=0, url="https://e.test")


def test_deleting_content_removes_its_file_after_commit(world, django_capture_on_commit_callbacks):
    c = EducationalContent(course=world.course, title="x", position=0)
    c.file.save("a.pdf", ContentFile(b"%PDF-1.4"), save=False)
    c.save()
    name = c.file.name
    with django_capture_on_commit_callbacks(execute=True):
        c.delete()
    assert not files.private_storage().exists(name)
```

(`world` comes from `etqan/learning/tests/conftest.py`, B6a.)

- [ ] **Step 2: RED** — `D pytest etqan/learning/tests/test_homework_models.py -q`.
- [ ] **Step 3: implement** `files.py`

```python
"""Spec B6b H-7/H-8: private files of homework and course content."""

from pathlib import PurePosixPath

from django.core.files.base import ContentFile
from django.core.files.storage import storages
from django.db import transaction

from etqan.platform import uploads
from etqan.platform.uploads import tenant_upload_path

NAME_MAX = 255
IMAGES = frozenset({".png", ".jpg", ".jpeg", ".webp"})
HOMEWORK_TYPES = uploads.PDF | IMAGES | uploads.OFFICE | frozenset({".txt"}) | uploads.AUDIO
CONTENT_TYPES = HOMEWORK_TYPES | uploads.VIDEO

homework_path = tenant_upload_path("homework")
homework_path.__module__ = __name__
content_path = tenant_upload_path("content")
content_path.__module__ = __name__


def private_storage():
    return storages["private"]


def bounded_name(name: str) -> str:
    if len(name) <= NAME_MAX:
        return name
    ext = PurePosixPath(name).suffix
    if len(ext) >= NAME_MAX:
        return name[:NAME_MAX]
    return name[: NAME_MAX - len(ext)] + ext


def attach(field_file, upload, *, extensions, max_bytes, field="file"):
    """Store ``upload`` on ``field_file`` (not saving the row). Returns the
    bounded original name and the old stored name to delete after commit."""
    checked = uploads.check_upload(upload, extensions=extensions, max_bytes=max_bytes, field=field)
    old = field_file.name or None
    stored = checked.file
    if isinstance(stored, ContentFile):
        stored.name = checked.original_name
    stored.content_type = checked.content_type
    field_file.save(checked.original_name, stored, save=False)
    return bounded_name(checked.original_name), old


def remove_after_commit(name: str | None) -> None:
    if name:
        storage = private_storage()
        transaction.on_commit(lambda: storage.delete(name), robust=True)
```

Models (append to `models.py`; import `from etqan.learning.files import content_path, homework_path, private_storage`):

```python
class Homework(models.Model):
    class Kind(models.TextChoices):
        TEXT = "text", "Text"
        FILE = "file", "File"

    class Status(models.TextChoices):
        INCOMPLETE = "incomplete", "Incomplete"
        COMPLETE = "complete", "Complete"

    student = models.ForeignKey("identity.StudentProfile", on_delete=models.PROTECT, related_name="+")
    course = models.ForeignKey("catalogue.Course", on_delete=models.PROTECT, related_name="+")
    session = models.ForeignKey("scheduling.Session", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    session_on = models.DateField(null=True, blank=True)
    title = models.CharField(max_length=200)
    kind = models.CharField(max_length=4, choices=Kind.choices)
    instructions = models.TextField(blank=True, default="", max_length=5000)
    file = models.FileField(storage=private_storage, upload_to=homework_path, blank=True, max_length=255)
    file_name = models.CharField(max_length=255, blank=True, default="")
    answer_text = models.TextField(blank=True, default="", max_length=10000)
    answer_file = models.FileField(storage=private_storage, upload_to=homework_path, blank=True, max_length=255)
    answer_file_name = models.CharField(max_length=255, blank=True, default="")
    answered_at = models.DateTimeField(null=True, blank=True)
    answered_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    teacher_comment = models.TextField(blank=True, default="", max_length=5000)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.INCOMPLETE)
    completed_at = models.DateTimeField(null=True, blank=True)
    set_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at", "-id")
        indexes = [models.Index(fields=("student", "course"), name="learning_hw_student_course")]
        constraints = [
            models.CheckConstraint(condition=Q(kind__in=("text", "file")), name="learning_hw_kind"),
            models.CheckConstraint(condition=Q(status__in=("incomplete", "complete")), name="learning_hw_status"),
            models.CheckConstraint(condition=~Q(kind="file") | ~Q(file=""), name="learning_hw_file_kind"),
            models.CheckConstraint(condition=~Q(kind="text") | ~Q(instructions=""), name="learning_hw_text_kind"),
            models.CheckConstraint(
                condition=Q(status="complete", completed_at__isnull=False) | Q(status="incomplete", completed_at__isnull=True),
                name="learning_hw_completed_at",
            ),
        ]

    def __str__(self):
        return self.title


class EducationalContent(models.Model):
    course = models.ForeignKey("catalogue.Course", on_delete=models.CASCADE, related_name="+")
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True, default="", max_length=5000)
    file = models.FileField(storage=private_storage, upload_to=content_path, blank=True, max_length=255)
    file_name = models.CharField(max_length=255, blank=True, default="")
    url = models.URLField(max_length=500, blank=True, default="")
    position = models.PositiveSmallIntegerField(default=0)
    is_active = models.BooleanField(default=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("course_id", "position", "id")
        constraints = [
            models.CheckConstraint(
                condition=(~Q(file="") & Q(url="")) | (Q(file="") & ~Q(url="")),
                name="learning_content_file_or_url",
            )
        ]

    def __str__(self):
        return self.title
```

`signals.py`:

```python
from django.db.models.signals import post_delete
from django.dispatch import receiver

from etqan.learning.files import remove_after_commit
from etqan.learning.models import EducationalContent


@receiver(post_delete, sender=EducationalContent)
def _drop_content_file(sender, instance, **kwargs):
    """H-8: a deleted item (directly or by a course cascade) loses its file."""
    remove_after_commit(instance.file.name or None)
```

`apps.py`: `def ready(self): from etqan.learning import signals  # noqa: F401, PLC0415`.

Registry / features / BUILT-dict edits as in **Interfaces**. Then `D manage makemigrations learning --name homework_content` and `just migrate`.

- [ ] **Step 4: GREEN** — `D pytest etqan/learning etqan/platform etqan/academy -q` (the access `in_use` test will fail for the new codes until Tasks 5–6 — expected, do not weaken it). Ruff, lint-imports.
- [ ] **Step 5: commit** — `git -C backend add etqan/learning etqan/platform etqan/access/registry.py etqan/academy/tests && git -C backend commit -m "feat(learning): homework and course content models (B6b)"`.

---

### Task 2: Homework services

**Files:** create `services/homework.py`, `tests/test_homework.py`; modify `services/__init__.py` (+ `__all__`).

**Interfaces — Consumes:** `files.*`, `access.teaches`, `access.taught_pairs`, `progress._student` (import from `etqan.learning.services.progress` directly — `services.progress` is a function name), `scheduling.services.subscriptions_queryset`, `scheduling.services.sessions_queryset`, `identity.services.get_children`, `catalogue.services.get_course`.
**Produces:** `homework_queryset(user, *, student=None, course=None, status=None)`, `get_homework(user, homework_id) -> Homework` (NotFoundError), `set_homework(*, student_user_id, course_id, title, kind, instructions="", file=None, session_id=None, by) -> Homework`, `update_homework(hw, *, by, **changes) -> Homework` (keys: `title`, `instructions`, `file`, `remove_file`, `session_id`, `teacher_comment`, `status`), `answer_homework(hw, *, by, answer_text=None, answer_file=None, remove_answer_file=False) -> Homework`, `delete_homework(hw, *, by) -> None`.

Rules to implement (spec H-1, H-3…H-7): every one with a test.

- `set_homework`: `_student` (400 `student`); course exists (400 `course`); live subscription for the pair: `subscriptions_queryset().filter(student__user_id=s, course_id=c, status__in=("active","paused")).exists()` else 400 `course` "This student has no live subscription to this course."; teacher must `teaches` (400 `student`); `title.strip()` required (400 `title`); kind in Kind (400 `kind`); kind text needs instructions (400 `instructions`), kind file needs a file (400 `file`); optional file through `files.attach(..., extensions=HOMEWORK_TYPES, max_bytes=uploads.CONTRACT_MAX)`; session: `sessions_queryset().filter(pk=session_id, student__user_id=s, course_id=c).exclude(status="cancelled").first()` else 400 `session`; set `session_on = session.occurs_on`. Atomic.
- `update_homework`: lock (`Homework.objects.select_for_update().get(pk=hw.pk)`), apply only given keys; `kind` key present → 400 `kind`; `remove_file` on a file homework → 400 `file`; empty instructions on text → 400 `instructions`; status `complete` → `completed_at = timezone.now()` (if not already), `incomplete` → `completed_at = None`; session re-validated as in set; stale file removed after commit.
- `answer_homework`: role must be student owning it or parent (`identity.services.is_parent_of`) — otherwise `PermissionDeniedError`/`ForbiddenError` (the view also guards); lock; complete → `ConflictError(code="learning.homework_complete")`; apply text (strip) / file (`attach` with `field="answer_file"`) / remove; neither text nor file afterwards → 400 `answer_text`; set `answered_at=now`, `answered_by=by`.
- `delete_homework`: lock; teacher and `answered_at` set → `ConflictError(code="learning.homework_answered")`; delete; both files removed after commit.
- `homework_queryset`: office all; teacher: OR of `(student__user_id, course_id)` pairs from `taught_pairs` (empty → none); student: `student__user_id=user.pk`; parent: `student__in=identity_services.get_children(user.pk)`; others none; filters; `select_related("student__user", "course", "set_by", "answered_by")`.

Tests (minimum; write them first): set by office / by teaching teacher; every 400 field above; teacher not teaching → 400 student; session of another course → 400; cancelled session → 400; `session_on` survives `Session` row deletion; file homework stored privately with bounded name; wrong file type and > 10 MiB refused (field `file`); update kind → 400; remove file on file hw → 400; clear instructions on text → 400; complete without answer OK and stamps; reopen clears; answer by student; answer by parent sets `answered_by`; answer by another student → refused; `test_answer_after_complete_conflicts`; empty answer → 400; replace answer file removes the old file after commit (`django_capture_on_commit_callbacks`); teacher delete after answer → 409, office delete OK and files removed; queryset per role incl. teacher of course A not seeing course B homework of the same student, parent not child sees none.

- [ ] Steps: failing tests → RED → implement → GREEN (`D pytest etqan/learning -q`, coverage of homework.py ≥ 90 %) → ruff/lint-imports → commit `feat(learning): homework services (B6b)`.

---

### Task 3: Educational content services

**Files:** create `services/content.py`, `tests/test_content.py`; modify `services/__init__.py`.

**Produces:** `content_queryset(user, *, course=None)`, `get_content(user, content_id)` (NotFoundError), `create_content(*, course_id, title, description="", file=None, url="", is_active=True, by)`, `update_content(item, *, title=None, description=None, file=None, url=None, is_active=None)`, `delete_content(item)`, `reorder_content(*, course_id, ids)`.

Rules (H-8): exactly one of file / url (400 `file` when both or neither — message "Attach a file or give a link, not both."); url must start with `https://` (400 `url`); file via `files.attach(extensions=CONTENT_TYPES, max_bytes=uploads.LIBRARY_MAX)`; switching from file to url removes the file after commit; create appends `position`; delete renumbers densely; reorder: ids exactly the course's items (400 `ids`). Readers: office all items (inactive too); teacher: courses in `{c for _, c in taught_pairs(user.pk)} | set(catalogue_services.course_ids_for_teachers([user.pk]).get(user.pk, []))` (check that helper's return shape), active only; student: courses of their own live subscriptions, active only; parent: courses of children's live subscriptions, active only; others none.

Tests: create file item / link item; both / neither → 400; http link → 400; > 20 MiB → 400; update file→link removes file after commit; delete renumbers; reorder rules; readers: office sees inactive, teacher via Course.teachers and via live subscription, student live sees active only, student with expired subscription sees nothing, parent of that student sees; course delete (`catalogue_services.delete_course`) with content and no history deletes rows and files after commit.

- [ ] Steps: tests → RED → implement → GREEN → ruff → commit `feat(learning): course content services (B6b)`.

---

### Task 4: B5 / B10 hooks

**Files:** create `services/hooks.py`, `tests/test_hooks.py`; modify `services/__init__.py`.

```python
"""Spec B6b H-11/H-12 (ledger D29): read services for B5 and B10."""

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo
import calendar

from django.db.models import Q

from etqan.academy import services as academy_services
from etqan.learning.models import Homework


@dataclass(frozen=True)
class HomeworkEvent:
    kind: str  # "set" | "answered" | "completed"
    homework_id: int
    student_user_id: int
    course_id: int
    set_by_user_id: int | None
    at: datetime


@dataclass(frozen=True)
class HomeworkMonth:
    homework_id: int
    course_id: int
    course_name_en: str
    course_name_ar: str
    title: str
    status: str
    set_on: date
    answered_at: datetime | None
    completed_at: datetime | None


def homework_events(*, since: datetime, until: datetime) -> list[HomeworkEvent]:
    """Derived from current state, window [since, until); aware UTC; call
    inside the academy's tenant_context."""
    rows = Homework.objects.select_related("student").filter(
        Q(created_at__gte=since, created_at__lt=until)
        | Q(answered_at__gte=since, answered_at__lt=until)
        | Q(completed_at__gte=since, completed_at__lt=until)
    )
    out = []
    for hw in rows:
        for kind, at in (("set", hw.created_at), ("answered", hw.answered_at), ("completed", hw.completed_at)):
            if at is not None and since <= at < until:
                out.append(HomeworkEvent(kind, hw.pk, hw.student.user_id, hw.course_id, hw.set_by_id, at))
    return sorted(out, key=lambda e: (e.at, e.homework_id, e.kind))


def homework_of(student_user_id: int, *, month: date) -> list[HomeworkMonth]:
    zone = ZoneInfo(academy_services.get_settings().timezone)
    first = month.replace(day=1)
    nxt = first + timedelta(days=calendar.monthrange(first.year, first.month)[1])
    start = datetime.combine(first, time.min, tzinfo=zone)
    end = datetime.combine(nxt, time.min, tzinfo=zone)
    rows = Homework.objects.select_related("course").filter(student__user_id=student_user_id).filter(
        Q(created_at__gte=start, created_at__lt=end) | Q(completed_at__gte=start, completed_at__lt=end)
    ).order_by("created_at", "id")
    return [
        HomeworkMonth(
            hw.pk, hw.course_id, hw.course.name_en, hw.course.name_ar, hw.title, hw.status,
            hw.created_at.astimezone(zone).date(), hw.answered_at, hw.completed_at,
        )
        for hw in rows
    ]
```

Tests: events window bounds (an event exactly at `until` excluded, at `since` included), a replaced answer yields one `answered` event at the latest time, deleted homework yields none, `set_by_user_id`; `homework_of` with academy timezone Asia/Riyadh: homework created 2026-05-31 22:30 UTC counts in June with `set_on = 2026-06-01`; homework set in May and completed in June appears in both months. (Set created_at with `Homework.objects.filter(pk=…).update(created_at=…)`.)

- [ ] Steps: tests → RED → implement → GREEN → ruff (split imports one per line, house style) → commit `feat(learning): homework hooks for B5 and B10 (B6b)`.

---

### Task 5: Homework API

**Files:** create `api/homework_views.py`, `tests/test_api_homework.py`; modify `api/serializers.py`, `api/urls.py`, `access/tests/test_routes.py`.

Routes (spec §5): `homework/`, `homework/<int:pk>/`, `homework/<int:pk>/file/`, `homework/<int:pk>/answer-file/`, `homework/<int:pk>/answer/`.

- `HomeworkListView` (GET list paginated with `StandardPagination`, POST multipart): `permission_classes = [HasCode | (ReadOnly & ReadsOwn) | IsTeacher, FeatureOn]` — staff need the code; teachers read and create by role (the service scopes and checks `teaches`); students/parents read only (`ReadOnly`). Codes `{"GET": "homework.view_any", "POST": "homework.create"}`. Use B6a's `_int_param` (move it to `api/params.py`, shared by all learning view modules).
- `HomeworkDetailView` (GET / PATCH multipart / DELETE): same permission list; codes `homework.view` / `homework.update` / `homework.delete`; lookup via `services.get_homework(request.user, pk)` (404 outside scope); PATCH and DELETE by a student/parent are already 403 by permissions.
- `HomeworkFileView`, `HomeworkAnswerFileView` (GET): `[HasCode | (ReadOnly & ReadsOwn), FeatureOn]`, code `homework.view`; 404 when no file; FileResponse headers per Global Constraints; filename = stored `file_name`.
- `HomeworkAnswerView` (POST multipart): `permission_classes = [IsStudent | IsParent, FeatureOn]`, no `permission_codes`; add `"etqan.learning.api.homework_views.HomeworkAnswerView": "the student's or parent's own answer; scoped in the view"` to `SELF_SERVICE`.
- Serializers: `HomeworkWrite` (student, course, title, kind, instructions, file, session — multipart), `HomeworkPatch` (all optional + remove_file, teacher_comment, status), `AnswerInput` (answer_text, answer_file, remove_answer_file), `homework_data(hw)` producing the spec §5 item shape.
- Route tables: `ROUTES` rows for the 7 coded (method, path) pairs with `N`; `FEATURES` block → `"homework"`; `FEATURE_WORDS` `"/learning/homework": "homework"`.

Tests (`test_api_homework.py`): office create (multipart with a PDF) / list / detail / patch / delete; teacher create for taught student, 400 for not taught; student and parent read own/child, 404 other; teacher of course A vs B 404; staff with and without codes; the **answer matrix** (admin 403, staff with every code 403, teacher 403, student owner 200, other student 404, parent of student 200, other parent 404, switch off → 404 for the owner); answer after complete → 409 code; file download headers and bytes; answer-file 404 when none; `?student=²` ignored (200); switch off → 404 for coded routes after role check.

- [ ] Steps: tests → RED → implement → GREEN (`D pytest etqan/learning etqan/access -q`; `in_use` still fails only for `educational_content.*` until Task 6) → ruff → commit `feat(learning): homework API (B6b)`.

---

### Task 6: Educational content API

**Files:** create `api/content_views.py`, `tests/test_api_content.py`; modify `api/serializers.py`, `api/urls.py`, `access/tests/test_routes.py`.

Routes: `content/` (GET unpaginated list, POST multipart), `content/reorder/` (POST), `content/<int:pk>/` (PATCH multipart, DELETE), `content/<int:pk>/file/` (GET).
Permissions: list GET `[HasCode | (ReadOnly & ReadsOwn), FeatureOn]` code `educational_content.view_any`; writes `[HasCode, FeatureOn]` codes `create` / `reorder` / `update` / `delete`; file GET as list (lookup via `services.get_content(user, pk)` → 404 outside readers or inactive for non-office). `content_data(item)` per spec §5. Route tables: 6 `ROUTES` rows, `FEATURES` → `"educational_content"`, `FEATURE_WORDS` `"/learning/content": "educational_content"`.

Tests: office CRUD + reorder; http link 400; reader matrix (teacher via Course.teachers, student live, student expired → empty list and 404 file, parent, staff with/without code, other academy isolation not needed); inactive item hidden from student (list) and 404 (file); file headers; switch off.

- [ ] Steps: tests → RED → implement → GREEN — **the full access suite must pass now**, including `in_use`: `D pytest etqan/learning etqan/access etqan/platform -q`; then the whole backend once `D pytest -q --no-cov` → ruff/lint-imports → commit `feat(learning): course content API (B6b)`.

---

### Task 7: Demo seed

**Files:** modify `backend/etqan/tenants/seeds/b6.py`, `etqan/tenants/tests/test_seed_b6.py`.

Add `seed_b6_homework(quran, yusuf, zaid)` called from `seed_b6` after the B6a part (it must also run when the B6a part returned early — restructure so each part is independently idempotent: homework part skips when any `Homework` exists for the Qur'an course; content part skips when any `EducationalContent` exists for it). Homework: for Yusuf (if he has a live Qur'an subscription) a text homework "Revise An-Naba' 1–20" answered with text "Done, recited twice."; for Zaid a text homework "Memorise Al-Mulk 1–5" unanswered — use `services.set_homework(..., by=None)` and `answer_homework(..., by=<the student user>)`. Skip a student without a live Qur'an subscription. Content: one link item "Tajweed rules chart" `https://quran.com` and one PDF item "Juz' Amma revision sheet" (`SimpleUploadedFile("juz-amma.pdf", b"%PDF-1.4\n% Etqan demo\n", content_type="application/pdf")`).

Tests: idempotent (run twice → 2 homework, 2 content); skip without the course; skip homework for a student without a live subscription.

- [ ] Steps: tests → RED → implement → GREEN → `just seed` twice OK → commit `feat(learning): demo homework and content (B6b)`.

---

### Task 8: Dashboard — data layers and translations

**Files:** create `src/features/homework/{schemas,api,queries,fixtures,index}.ts` (+ `api.test.ts`), `src/features/content/{schemas,api,queries,fixtures,index}.ts` (+ `api.test.ts`), `src/locales/{en,ar}/homework.json`, `content.json`; modify `src/features/identity/schemas.ts` (`FeatureCode`: B6b group `"homework"`, `"educational_content"`).

- Types mirror spec §5 shapes exactly (`Homework`, `HomeworkStatus`, `HomeworkKind`, `ContentItem`, `Paginated<T>` reuse from curriculum or local).
- `homeworkApi`: `list(params)`, `get(id)`, `create(form: FormData)`, `update(id, form: FormData)`, `remove(id)`, `answer(id, form: FormData)`, `download(id, fileName, which: "file" | "answer")` (blob + object URL, as `employmentApi.download`).
- `contentApi`: `list({course})`, `create(form)`, `update(id, form)`, `remove(id)`, `reorder(course, ids)`, `download(id, fileName)`.
- Hooks: `useHomeworkList(params)`, `useHomework(id)`, `useSetHomework()`, `useUpdateHomework(id)`, `useDeleteHomework()`, `useAnswerHomework(id)`; `useContent(course?)`, `useSaveContent(id?)`, `useDeleteContent()`, `useReorderContent()`. Mutations invalidate `["homework"]` / `["content"]`. Wrap API functions (`(v) => api.fn(v)`) — never pass them straight to `useMutation`.
- Error text helpers: `homeworkErrorText` mapping `learning.homework_complete`, `learning.homework_answered` to `homework.errors.*`, else `errorText`; reuse curriculum's `formErrors` pattern for unmatched field errors.
- Locale keys (en + real ar): nav (homework, myHomework, content, materials), list columns, status/kind labels, dialog labels (title, kind, instructions, file, session, answer, attach, comment, markComplete, reopen, delete, deleteConfirm), toasts, empty states, errors (homework_complete, homework_answered, fileOrLink), content labels (title, description, file, link, active, reorder, open, download).

Tests: api paths/FormData usage; error text mapping; locale parity.

- [ ] Steps: tests → RED → implement → GREEN (`D dash pnpm vitest run src/features/homework src/features/content src/locales`, tsc, lint) → commit `feat(homework): data layer, switches and translations (B6b)`.

---

### Task 9: Dashboard — homework screens

**Files:** create `src/features/homework/HomeworkList.tsx`, `HomeworkDialog.tsx`, `NewHomeworkDialog.tsx`, `MyHomework.tsx` (+ tests); routes `scheduling.homework.tsx` (`staticData {permission: "homework.view_any", feature: "homework"}`), `teaching.homework.tsx` (`{feature: "homework"}`), `learning.homework.tsx` (`{feature: "homework"}`); nav items under the B6 marker (office in group `scheduling`, teacher group `teaching` `requiresRole: "teacher"`, student/parent group `learning`); extend `routes/permissions.test.ts`, `features/shell/nav.test.ts` under B6 sections.

Behaviour (spec §6):
- **HomeworkList** `({ asTeacher?: boolean })`: tabs incomplete / complete / all (`role="tab"`); filters course (office only, `useCatalogue("courses")`), student search (debounced 300 ms); table student · course · title · kind · answered (date via the locale's date-time format) · status · set on (`formatDay` of `created_at`'s local date is fine via `Intl` date — it's an instant); Load more paging; row "Open" → `HomeworkDialog`; "New homework" button (office with `homework.create`, or teacher) → `NewHomeworkDialog`.
- **NewHomeworkDialog**: student picker (office: `usePeople("students", {search})`; teacher: students from `useStudentLevels({})` rows of `@/features/curriculum` — the pairs they teach — deduped), course select (for the chosen student: office from the student's live subscriptions via the scheduling subscriptions API filtered by student — check `features/scheduling` for a hook; teacher: courses from the same pairs), optional session select (that student's upcoming/past sessions in the course via the scheduling sessions API filtered by student+course), title, kind radio (text/file), instructions textarea, file input (accept list from Global Constraints; client-side 10 MiB check). Submit as FormData. Server field errors under fields, others via `formErrors` at top.
- **HomeworkDialog** (office/teacher): shows all fields, downloads (file, answer file), answer text, answered by/at; edit title/instructions/file (replace/remove), comment, Mark complete / Reopen, Delete (AlertDialog; 409 message). Read-only for staff without `homework.update`.
- **MyHomework** (student/parent): parent child picker (from `useMe().children`); list incomplete first; open → instructions, download, answer textarea + attach (replace/remove existing), Submit (disabled when empty), comment shown; complete → read-only with a "Completed" chip.

Tests per component: office list renders rows + tabs filter; teacher sees no course filter; new homework submits FormData with the right keys; kind file requires a file client-side; dialog mark complete / reopen calls update with `status`; delete 409 shows `homework.errors.homework_answered`; MyHomework submit answer FormData; complete homework shows no submit; parent switches child.

- [ ] Steps: tests → RED → implement → GREEN (curriculum+homework+routes+shell+locales vitest, tsc, lint) → commit `feat(homework): homework screens (B6b)`.

---

### Task 10: Dashboard — educational content screens

**Files:** create `src/features/content/ContentAdmin.tsx`, `ContentDialog.tsx`, `Materials.tsx` (+ tests); routes `catalogue.content.tsx` (`{permission: "educational_content.view_any", feature: "educational_content"}`), `teaching.materials.tsx`, `learning.materials.tsx` (`{feature: "educational_content"}`); nav under B6 marker (office group `catalogue`; teacher `teaching`; student/parent `learning`); test lists extended.

- **ContentAdmin**: course select (required to show items and to reorder), table title · type (file/link) · active · actions (move up/down with `educational_content.reorder`, edit, delete); Add (`create`) → ContentDialog.
- **ContentDialog**: title, description, a radio "File / Link", file input (20 MiB client check) or https URL input (client check `^https://`), active checkbox; FormData submit; errors as elsewhere.
- **Materials** (teacher/student/parent): `useContent()` grouped by course name (`localName`), each item: open link (`<a target="_blank" rel="noopener noreferrer">`) or Download button; empty state.

Tests: admin requires a course to list; reorder call; dialog link validation and FormData; materials grouping and link attributes; download calls `contentApi.download`.

- [ ] Steps: tests → RED → implement → GREEN; then the **whole dashboard suite with coverage** (`D dash pnpm test:coverage`) meets thresholds → commit `feat(content): course materials screens (B6b)`.

---

### Task 11: e2e — `dashboard/e2e/b6-homework.spec.ts`

Follow `e2e/b6-curriculum.spec.ts` (its `visit()` helper with 2 attempts + annotations, `signInTeacher`/`signInStudent`, CSRF API helper, stamped names). Journey:
1. `manage("set_features", "demo", "--on", "homework", "--on", "educational_content")`.
2. Admin API set-up: a stamped student with a live Quran Memorisation subscription with Ustadha Maryam (as in the B6a spec).
3. Teacher Maryam: `/app/teaching/homework` → New homework → that student, course, title `HW <stamp>`, kind text, instructions → save → row visible.
4. Student: `/app/learning/homework` → open `HW <stamp>` → answer text + attach a small PDF → Submit → "answered" shown.
5. Teacher: open it → comment → Mark complete → status Complete.
6. Admin: `/app/catalogue/content` → course Quran Memorisation → Add a link item `Material <stamp>` (`https://quran.com`) → visible.
7. Student: `/app/learning/materials` → `Material <stamp>` link visible with `href="https://quran.com"`.

- [ ] Steps: write → `just e2e e2e/b6-homework.spec.ts` passes twice in a row → whole `just e2e` → commit `test(e2e): B6b homework and materials journey`.

---

### Task 12: Slice verification

- [ ] `just test`, `just lint`, dashboard coverage, `just e2e` all green on the stream stack; spec H-1…H-14 and §6 screens each traced to code + test; record results in the phase notes.
