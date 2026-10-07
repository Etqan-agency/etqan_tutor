# Plan 49 — B7a Recorded Courses: Catalogue, Enrolment and Watching — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new tenant app `etqan.recorded` with playlists, ordered videos (link / file / live), office-recorded enrolments (manual ones also recorded as billing payments), a student course player with watch tracking and progress, and a read-only parent view, behind the switch `recorded_courses` (off by default).

**Architecture:** Models, services and DRF views in `backend/etqan/recorded/` (services package, views split office / file / my). Other apps reached only through `identity.services`, `academy.services` and `billing.services` (import contract). Lesson files on `STORAGES["private"]`, served by one authenticated route that redirects to a signed URL only with a dedicated private S3 bucket and otherwise streams with single-range (206) support. Dashboard feature folder `src/features/recorded/`, office pages under `/catalogue/recorded…`, student/parent pages under `/learning/recorded…`.

**Tech Stack:** Django 5 + DRF + django-tenants + pytest; React + TanStack Router/Query + Vitest + RTL; Playwright.

**Spec:** `docs/superpowers/specs/2026-10-08-b7-add-on-sales-design.md` — phase decisions B7-1…B7-17 (§2), slice B7a §5–§12 (A-1…A-16). Read both before any task.

**Requires:** — (no other phase's slice; B3b, B3c and B3g are merged and B7a uses none of their unmerged parts).

**Written in spec-only mode** (ledger D45, 2026-10-08): no stack existed when it was written, so no command below has been run. Build only after the conductor gives B7 a slot (`ledger.py phase B7 --slot n`, `.env.stream` rewritten, `just dev-backend`).

Ledger D19 (NotImpersonating on money-moving actions) does not apply to B7a: it takes no online money. The office's manual enrolment writes a billing record, which office staff record as themselves anyway.

## Global Constraints

- Work from `/home/abdulkhalek/Projects/etqan_tutor-wt/b7`. `backend/` and `dashboard/` are separate git worktrees; create `feat/b7a-recorded` in the meta worktree and in both submodules (`git fetch origin && git switch -c feat/b7a-recorded origin/main` per submodule, `origin/master` for meta). Never run `git submodule update` or any writing `git submodule` command.
- Commands (after `set -a; . ./.env.stream; set +a` in the meta worktree), written below as:
  - `B <cmd>` = `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django <cmd>` (e.g. `B pytest etqan/recorded -q`, `B ruff check .`, `B ruff format --check .`, `B lint-imports`, `B python manage.py makemigrations recorded`).
  - `F <cmd>` = `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard <cmd>` (e.g. `F pnpm vitest run src/features/recorded`, `F pnpm tsc --noEmit`, `F pnpm lint`).
  - Whole suites: `just migrate`, `just test`, `just lint`, `just e2e e2e/b7-recorded.spec.ts`, `just seed`.
- Backend coverage ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- Business logic only in `etqan/recorded/services/`. `etqan.recorded` imports only `etqan.platform`, `etqan.identity.services`, `etqan.academy.services`, `etqan.billing.services` (and, from B7b, `etqan.gateways.services`). Never another app's models or api.
- Shared lists: add lines only under `── phase B7 ──` markers (`TENANT_APPS` in `config/settings/base.py`, `config/api_router.py`, the access `RESOURCES`, `seed_dev.seed_academy`, `pyproject.toml`, the dashboard `NAV_ITEMS`). The registry's `_later("recorded_courses", …)` line is flipped in place. Access route tables in `access/tests/test_routes.py`: append a `# Phase B7, slice B7a` block to each table.
- `recorded_courses` is off by default. Routes under `/api/v1/recorded/`. People addressed by **user id** in the API and services.
- Billing ids: `billing.services.create_record(student_id=…)` takes the student's **user id** (it calls `active_student`, which calls `identity.services.get_student_profile(user_id)`). `record_link_payment(student_id=…)` (B7b) takes the **profile pk**. B7a uses only `create_record`.
- Migrations only create new tables (B7-14).
- Text fields are plain text (D2). Links are https only. Only YouTube and Vimeo are embedded, by validated id.
- Money: integer minor units + 3-letter currency; never summed across currencies.
- Locale files `dashboard/src/locales/{en,ar}/recorded.json`, no top-level wrapper (keys `recorded.*`); en and ar key-equal (no es file, D22).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Stage explicit paths; never `git commit -a`.

## Review Focus

1. **A revoked enrolment, a hidden video or an unpublished playlist still serving its lesson file.** `can_watch` must check all three on every request, and the file route must 404 for a student. Pinned in Task 8, `test_file_refused_when_not_watchable`.
2. **A seek request (`Range`) on a streamed lesson.** The answer must be 206 with the right `Content-Range`. An unsatisfiable range must be 416, never a 500. Pinned in Task 8, `test_range_requests`.
3. **Two office users enrolling the same student at once.** One must get 409, not a 500 from the partial unique index. Pinned in Task 5, `test_duplicate_enrolment_race_is_409`, by catching the `IntegrityError`.
4. **A manual enrolment whose billing record fails** (a duplicate transaction number). Nothing may be written: no enrolment without its payment. Pinned in Task 5, `test_manual_enrolment_rolls_back_with_billing`.
5. **A parent reaching a lesson file or the watched toggle, or a student reaching another student's course.** The parent must get 403, the other student 404. Pinned in Tasks 8 and 9.

---

## File Structure

```text
backend/etqan/recorded/
  __init__.py
  apps.py                  RecordedConfig (ready() imports signals)
  files.py                 upload paths, private storage, store(), remove_after_commit()
  embeds.py                clean_url(), parse_video_url()
  models.py                Playlist, PlaylistVideo, Enrolment, WatchedVideo
  signals.py               post_delete file cleanup
  migrations/0001_initial.py   (generated)
  services/
    __init__.py            the public API (re-exports)
    playlists.py           create/update/delete/get, playlists_queryset, filter_playlists
    videos.py              create/update/delete/move, videos_of
    enrolments.py          enrol_by_office, enrol_from_sale, revoke, restore, delete, update, queries
    watching.py            set_watched, progress, enrolment_for, is_complete
    scope.py               my_enrolments, my_playlist, can_watch
    serving.py             serve_video (signed redirect or ranged stream)
  api/
    __init__.py
    serializers.py
    views.py               office playlists / videos / enrolments
    file_views.py          videos/<id>/file/
    my_views.py            my/, my/<id>/, my/videos/<id>/watched/
    urls.py
  tests/
    __init__.py
    conftest.py
    test_models.py test_embeds.py test_playlists.py test_videos.py
    test_enrolments.py test_watching.py test_serving.py
    test_api_office.py test_api_enrolments.py test_api_file.py test_api_my.py
    test_seeds.py
backend/etqan/tenants/seeds/b7.py
Modified (B7 markers / in place): backend/config/settings/base.py, backend/config/api_router.py,
  backend/etqan/platform/features.py, backend/etqan/platform/tests/test_features.py,
  backend/etqan/access/registry.py, backend/etqan/access/tests/test_routes.py,
  backend/etqan/tenants/management/commands/seed_dev.py, backend/pyproject.toml

dashboard/src/features/recorded/
  schemas.ts  duration.ts  api.ts  queries.ts  errors.ts  fixtures.ts  index.ts
  PlaylistsAdmin.tsx  PlaylistForm.tsx  VideosTab.tsx  VideoDialog.tsx
  EnrolmentsTab.tsx  EnrolmentDialog.tsx  MyCourses.tsx  CoursePlayer.tsx  VideoPane.tsx
  (+ a .test.tsx / .test.ts next to each)
dashboard/src/routes/_authed/
  catalogue.recorded.index.tsx  catalogue.recorded.$playlistId.tsx
  learning.recorded.index.tsx   learning.recorded.$playlistId.tsx
dashboard/src/locales/{en,ar}/recorded.json
Modified: dashboard/src/features/identity/schemas.ts (FeatureCode), dashboard/src/features/shell/nav.ts (B7 marker),
  dashboard/src/routeTree.gen.ts (regenerated)
dashboard/e2e/b7-recorded.spec.ts
```

---

### Task 1: The app, its models and the switch

**Files:**
- Create: `backend/etqan/recorded/__init__.py` (empty), `apps.py`, `files.py`, `models.py`, `tests/__init__.py` (empty), `tests/conftest.py`, `tests/test_models.py`
- Generate: `backend/etqan/recorded/migrations/0001_initial.py`
- Modify: `backend/config/settings/base.py` (under `# ── phase B7 ──` in `TENANT_APPS`), `backend/etqan/platform/features.py` (flip line 111 in place), `backend/etqan/platform/tests/test_features.py` (BUILT dict), `backend/pyproject.toml` (B7 marker)

**Interfaces:**
- Produces: models `Playlist` (`Language`, fields per spec §7), `PlaylistVideo` (`Kind`, `Status`, `Provider`), `Enrolment` (`Method`, `Status`), `WatchedVideo`; `files.thumb_path`, `files.intro_path`, `files.video_path`, `files.private_storage()`, `files.IMAGES`, `files.THUMB_MAX`, `files.INTRO_MAX`, `files.video_max()`, `files.store(field_file, upload, *, extensions, max_bytes, field) -> str | None`, `files.remove_after_commit(storage, name)`.

- [ ] **Step 1: Write the failing model tests**

`backend/etqan/recorded/tests/conftest.py`:

```python
"""Recorded-course fixtures: a student (child of a parent), another student,
and helpers that build rows straight through the models for model tests.
Service and API tests build through the services."""

import io
from types import SimpleNamespace

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from PIL import Image
from rest_framework.test import APIClient

from etqan.identity import services as identity_services

MP4 = b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 64


def png(name="t.png"):
    buf = io.BytesIO()
    Image.new("RGB", (40, 22)).save(buf, "PNG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/png")


def mp4(name="v.mp4", body=MP4):
    return SimpleUploadedFile(name, body, content_type="video/mp4")


def as_user(user):
    client = APIClient()
    client.force_login(user)
    client.user = user
    return client


@pytest.fixture
def people(set_features):
    set_features(recorded_courses=True)
    student = identity_services.create_person("student", full_name="Yusuf")
    other = identity_services.create_person("student", full_name="Zaid")
    parent = identity_services.create_person(
        "parent", full_name="Omar", email="omar@x.test"
    )
    identity_services.link_guardian(parent, student)
    teacher = identity_services.create_person("teacher", full_name="Bilal")
    return SimpleNamespace(
        student=student,
        other=other,
        parent=parent,
        teacher=teacher,
        profile=identity_services.get_student_profile(student.pk),
        other_profile=identity_services.get_student_profile(other.pk),
    )
```

`backend/etqan/recorded/tests/test_models.py`:

```python
import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.recorded.models import Enrolment
from etqan.recorded.models import Playlist
from etqan.recorded.models import PlaylistVideo
from etqan.recorded.tests.conftest import png

pytestmark = pytest.mark.django_db


def playlist(**extra):
    data = {
        "title": "Tajweed",
        "slug": "tajweed",
        "description": "d",
        "code": "TAJ-1",
        "content_language": "ar",
        "currency": "USD",
        "terms": "t",
        **extra,
    }
    row = Playlist(**data)
    row.thumbnail.save("t.png", png(), save=False)
    row.save()
    return row


def video(pl, **extra):
    data = {
        "playlist": pl,
        "code": "V1",
        "title": "One",
        "slug": "one",
        "kind": "link",
        "url": "https://youtu.be/abcdefghijk",
        "duration_seconds": 60,
        "position": 0,
        **extra,
    }
    return PlaylistVideo.objects.create(**data)


def test_discount_cannot_exceed_price():
    with pytest.raises(IntegrityError), transaction.atomic():
        playlist(price_minor=100, discount_minor=101)


@pytest.mark.parametrize(
    "extra",
    [
        {"kind": "link", "url": ""},
        {"kind": "file", "url": "https://x.test/a"},
        {"kind": "link", "downloadable": True},
    ],
)
def test_video_kind_matches_media(extra):
    pl = playlist()
    with pytest.raises(IntegrityError), transaction.atomic():
        video(pl, **extra)


def test_one_active_enrolment_per_student_and_playlist(people):
    pl = playlist()
    Enrolment.objects.create(
        playlist=pl, student=people.profile, amount_minor=0, currency="USD",
        method="free",
    )
    with pytest.raises(IntegrityError), transaction.atomic():
        Enrolment.objects.create(
            playlist=pl, student=people.profile, amount_minor=0, currency="USD",
            method="free",
        )
    Enrolment.objects.update(status="revoked")
    Enrolment.objects.create(
        playlist=pl, student=people.profile, amount_minor=0, currency="USD",
        method="free",
    )


def test_free_enrolment_has_no_amount(people):
    pl = playlist()
    with pytest.raises(IntegrityError), transaction.atomic():
        Enrolment.objects.create(
            playlist=pl, student=people.profile, amount_minor=5, currency="USD",
            method="free",
        )
```

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_models.py -q`
Expected: collection error, `ModuleNotFoundError: No module named 'etqan.recorded'`.

- [ ] **Step 3: Write the app**

`backend/etqan/recorded/apps.py`:

```python
from django.apps import AppConfig


class RecordedConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.recorded"
```

`backend/etqan/recorded/files.py`:

```python
"""Spec B7-8, A-1, A-4: playlist media. Thumbnails and intro videos are public
marketing media (default storage); lesson files are private."""

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import storages
from django.db import transaction

from etqan.platform import uploads
from etqan.platform.uploads import tenant_upload_path

IMAGES = frozenset({".png", ".jpg", ".jpeg", ".webp"})
THUMB_MAX = 2 * 1024 * 1024
INTRO_MAX = 100 * 1024 * 1024  # BR-39
VIDEOS = uploads.VIDEO  # .mp4 only

# Underscored folder names: the callable's __name__ must be an identifier so
# migrations can serialize it by its module path.
thumb_path = tenant_upload_path("recorded_thumbs")
thumb_path.__module__ = __name__
intro_path = tenant_upload_path("recorded_intros")
intro_path.__module__ = __name__
video_path = tenant_upload_path("recorded_videos")
video_path.__module__ = __name__


def private_storage():
    return storages["private"]


def video_max() -> int:
    """A-4: RECORDED_VIDEO_MAX_MB (default 100), in bytes."""
    return getattr(settings, "RECORDED_VIDEO_MAX_MB", 100) * 1024 * 1024


def store(field_file, upload, *, extensions, max_bytes, field) -> str | None:
    """Check ``upload`` and put it on ``field_file`` (the row is not saved).
    Returns the old stored name, to remove after commit."""
    checked = uploads.check_upload(
        upload, extensions=extensions, max_bytes=max_bytes, field=field
    )
    old = field_file.name or None
    stored = checked.file
    if isinstance(stored, ContentFile):
        stored.name = checked.original_name
    stored.content_type = checked.content_type
    field_file.save(checked.original_name, stored, save=False)
    return old


def remove_after_commit(storage, name: str | None) -> None:
    if name:
        transaction.on_commit(lambda: storage.delete(name), robust=True)
```

`backend/etqan/recorded/models.py`:

```python
"""Slice B7a §7: recorded courses (TutorHamster's playlists), their videos,
enrolments (TutorHamster's RC subscriptions) and watched videos."""

from django.conf import settings
from django.core.validators import MaxValueValidator
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
from django.db import models
from django.db.models import Q
from django.utils import timezone

from etqan.recorded.files import intro_path
from etqan.recorded.files import private_storage
from etqan.recorded.files import thumb_path
from etqan.recorded.files import video_path

CURRENCY = RegexValidator(r"^[A-Z]{3}$")


class Playlist(models.Model):
    class Language(models.TextChoices):
        AR = "ar", "Arabic"
        EN = "en", "English"
        UR = "ur", "Urdu"
        TR = "tr", "Turkish"
        FR = "fr", "French"
        ES = "es", "Spanish"

    thumbnail = models.ImageField(upload_to=thumb_path, max_length=255)
    intro_video = models.FileField(upload_to=intro_path, blank=True, max_length=255)
    title = models.CharField(max_length=160)
    slug = models.SlugField(max_length=80, unique=True)
    description = models.TextField(max_length=2000)
    code = models.CharField(max_length=40, unique=True)
    content_language = models.CharField(max_length=2, choices=Language.choices)
    price_minor = models.BigIntegerField(default=0, validators=[MinValueValidator(0)])
    discount_minor = models.BigIntegerField(
        default=0, validators=[MinValueValidator(0)]
    )
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    content = models.TextField(blank=True, default="", max_length=20000)
    terms = models.TextField(max_length=10000)
    is_published = models.BooleanField(default=False)
    certificate = models.BooleanField(default=False)
    app_only = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at", "id")
        constraints = [
            models.CheckConstraint(
                condition=Q(price_minor__gte=0)
                & Q(discount_minor__gte=0)
                & Q(discount_minor__lte=models.F("price_minor")),
                name="recorded_playlist_discount_within_price",
            )
        ]

    def __str__(self):
        return self.title


class PlaylistVideo(models.Model):
    class Kind(models.TextChoices):
        LINK = "link", "Link"
        FILE = "file", "File"
        LIVE = "live", "Live stream"

    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        PUBLISHED = "published", "Published"
        HIDDEN = "hidden", "Hidden"

    class Provider(models.TextChoices):
        NONE = "", "External"
        YOUTUBE = "youtube", "YouTube"
        VIMEO = "vimeo", "Vimeo"

    playlist = models.ForeignKey(
        Playlist, on_delete=models.CASCADE, related_name="videos"
    )
    thumbnail = models.ImageField(upload_to=thumb_path, blank=True, max_length=255)
    code = models.CharField(max_length=40)
    title = models.CharField(max_length=160)
    slug = models.SlugField(max_length=80)
    kind = models.CharField(max_length=4, choices=Kind.choices)
    url = models.URLField(max_length=500, blank=True, default="")
    embed_provider = models.CharField(
        max_length=7, choices=Provider.choices, blank=True, default=""
    )
    embed_id = models.CharField(max_length=20, blank=True, default="")
    file = models.FileField(
        storage=private_storage, upload_to=video_path, blank=True, max_length=255
    )
    duration_seconds = models.PositiveIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(86400)]
    )
    position = models.PositiveSmallIntegerField(default=0)
    description = models.TextField(blank=True, default="", max_length=2000)
    status = models.CharField(
        max_length=9, choices=Status.choices, default=Status.DRAFT
    )
    downloadable = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("position", "id")
        constraints = [
            models.UniqueConstraint(
                fields=["playlist", "code"], name="recorded_video_code_unique"
            ),
            models.UniqueConstraint(
                fields=["playlist", "slug"], name="recorded_video_slug_unique"
            ),
            models.CheckConstraint(
                condition=(Q(kind="file") & ~Q(file="") & Q(url=""))
                | (Q(kind__in=["link", "live"]) & ~Q(url="") & Q(file="")),
                name="recorded_video_kind_matches_media",
            ),
            models.CheckConstraint(
                condition=Q(downloadable=False) | Q(kind="file"),
                name="recorded_video_downloadable_file_only",
            ),
            models.CheckConstraint(
                condition=Q(duration_seconds__gte=1)
                & Q(duration_seconds__lte=86400),
                name="recorded_video_duration_range",
            ),
        ]

    def __str__(self):
        return self.title


class Enrolment(models.Model):
    class Method(models.TextChoices):
        MANUAL = "manual", "Manual"
        FREE = "free", "Free"
        STRIPE = "stripe", "Stripe"
        PAYPAL = "paypal", "PayPal"
        CODE = "code", "Activation code"

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        REVOKED = "revoked", "Revoked"

    playlist = models.ForeignKey(
        Playlist, on_delete=models.PROTECT, related_name="enrolments"
    )
    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    amount_minor = models.BigIntegerField(validators=[MinValueValidator(0)])
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    method = models.CharField(max_length=7, choices=Method.choices)
    transaction_number = models.CharField(max_length=120, blank=True, default="")
    payment = models.ForeignKey(
        "billing.Payment",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    notes = models.TextField(blank=True, default="", max_length=2000)
    status = models.CharField(
        max_length=7, choices=Status.choices, default=Status.ACTIVE
    )
    enrolled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    enrolled_at = models.DateTimeField(default=timezone.now)
    revoked_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    revoked_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-enrolled_at", "id")
        constraints = [
            models.UniqueConstraint(
                fields=["playlist", "student"],
                condition=Q(status="active"),
                name="recorded_enrolment_one_active",
            ),
            models.CheckConstraint(
                condition=~Q(method="free") | Q(amount_minor=0),
                name="recorded_enrolment_free_is_zero",
            ),
            models.CheckConstraint(
                condition=Q(amount_minor__gte=0),
                name="recorded_enrolment_amount_not_negative",
            ),
        ]
        indexes = [models.Index(fields=["student", "status"])]

    def __str__(self):
        return f"Enrolment<{self.playlist_id}, {self.student_id}, {self.status}>"


class WatchedVideo(models.Model):
    enrolment = models.ForeignKey(
        Enrolment, on_delete=models.CASCADE, related_name="watched"
    )
    video = models.ForeignKey(
        PlaylistVideo, on_delete=models.PROTECT, related_name="watches"
    )
    watched_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["enrolment", "video"], name="recorded_watched_unique"
            )
        ]
```

`backend/config/settings/base.py`, in `TENANT_APPS` directly under `# ── phase B7 ──`:

```python
    "etqan.recorded",
```

`backend/etqan/platform/features.py` line 111, replace in place:

```python
    # Phase B7, slice B7a: flipped to built in place, off by default.
    _built(
        "recorded_courses",
        "Recorded courses",
        "نظام الدورات المسجلة",
        "content",
        default=False,
    ),
```

`backend/etqan/platform/tests/test_features.py`: in the `BUILT` dict, between the `# ── phase B6 ──` block and `# ── phase B8 ──`, add:

```python
    # ── phase B7 ──
    "recorded_courses": False,
```

(If a test in that file lists the remaining `_later` codes, remove `recorded_courses` from that list.)

`backend/pyproject.toml`, the B7 marker block (directly under `# ── phase B7 ──`):

```toml
[[tool.importlinter.contracts]]
name = "recorded reaches other apps only through their services"
type = "forbidden"
# B7-1 (spec 2026-10-08): whole apps forbidden, only their services let
# through, so a module an app adds later is forbidden too.
source_modules = ["etqan.recorded"]
forbidden_modules = [
    "etqan.identity", "etqan.academy", "etqan.billing", "etqan.gateways",
    "etqan.catalogue", "etqan.scheduling", "etqan.tenants", "etqan.site",
    "etqan.notifications", "etqan.access", "etqan.payroll", "etqan.finance",
    "etqan.learning",
]
allow_indirect_imports = true
ignore_imports = [
    "etqan.recorded.** -> etqan.identity.services",
    "etqan.recorded.** -> etqan.academy.services",
    "etqan.recorded.** -> etqan.billing.services",
    "etqan.recorded.** -> etqan.gateways.services",
    "etqan.recorded.tests.** -> etqan.**",
]
```

Then generate the migration: `B python manage.py makemigrations recorded --name initial` and apply it: `just migrate`. Check the generated file creates only the four new tables and references `etqan.recorded.files.thumb_path` / `intro_path` / `video_path` / `private_storage` by path.

- [ ] **Step 4: Run the tests to see them pass**

Run: `B pytest etqan/recorded/tests/test_models.py etqan/platform/tests/test_features.py -q`
Expected: PASS. Then `B lint-imports` (PASS) and `B ruff check etqan/recorded && B ruff format --check etqan/recorded`.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded config/settings/base.py etqan/platform/features.py etqan/platform/tests/test_features.py pyproject.toml
git -C backend commit -m "feat(recorded): B7a app, models and the recorded_courses switch

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Video URLs and embeds (A-5)

**Files:**
- Create: `backend/etqan/recorded/embeds.py`, `backend/etqan/recorded/tests/test_embeds.py`

**Interfaces:**
- Produces: `embeds.clean_url(url: str, *, field: str = "url") -> str` (https only, ≤ 500, `ValidationError(field=field)`), `embeds.parse_video_url(url: str) -> tuple[str, str]` → `("youtube", id)`, `("vimeo", id)` or `("", "")`.

- [ ] **Step 1: Write the failing tests**

```python
import pytest

from etqan.platform.exceptions import ValidationError
from etqan.recorded.embeds import clean_url
from etqan.recorded.embeds import parse_video_url

YT = "dQw4w9WgXcQ"


@pytest.mark.parametrize(
    ("url", "expected"),
    [
        (f"https://www.youtube.com/watch?v={YT}", ("youtube", YT)),
        (f"https://youtube.com/watch?v={YT}&t=42", ("youtube", YT)),
        (f"https://m.youtube.com/watch?v={YT}", ("youtube", YT)),
        (f"https://youtu.be/{YT}", ("youtube", YT)),
        (f"https://youtu.be/{YT}?si=x", ("youtube", YT)),
        (f"https://www.youtube.com/embed/{YT}", ("youtube", YT)),
        (f"https://www.youtube.com/live/{YT}", ("youtube", YT)),
        (f"https://www.youtube.com/shorts/{YT}", ("youtube", YT)),
        (f"https://www.youtube-nocookie.com/embed/{YT}", ("youtube", YT)),
        ("https://vimeo.com/123456789", ("vimeo", "123456789")),
        ("https://player.vimeo.com/video/123456789", ("vimeo", "123456789")),
        ("https://www.youtube.com/watch?v=short", ("", "")),
        ("https://youtube.com.evil.test/watch?v=" + YT, ("", "")),
        ("https://vimeo.com/channels/abc", ("", "")),
        ("https://example.com/lesson.mp4", ("", "")),
    ],
)
def test_parse_video_url(url, expected):
    assert parse_video_url(url) == expected


@pytest.mark.parametrize(
    "bad",
    ["", "http://x.test/a", "javascript:alert(1)", "https://", "ftp://x.test",
     "https://x.test/" + "a" * 500],
)
def test_clean_url_refuses(bad):
    with pytest.raises(ValidationError) as caught:
        clean_url(bad)
    assert caught.value.field == "url"


def test_clean_url_strips_and_keeps_https():
    assert clean_url("  https://x.test/a  ") == "https://x.test/a"
```

- [ ] **Step 2: Run to see it fail**

Run: `B pytest etqan/recorded/tests/test_embeds.py -q` → FAIL (`No module named 'etqan.recorded.embeds'`).

- [ ] **Step 3: Implement**

```python
"""Spec A-5, B7-7: a link video's URL is https only; YouTube and Vimeo are
recognised by host and a validated id and embedded from a fixed template;
anything else is only ever opened in a new tab."""

import re
from urllib.parse import parse_qs
from urllib.parse import urlsplit

from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.validators import URLValidator

from etqan.platform.exceptions import ValidationError

URL_MAX = 500
YOUTUBE_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
VIMEO_ID = re.compile(r"^\d{1,12}$")
YOUTUBE_HOSTS = frozenset(
    {
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "youtube-nocookie.com",
        "www.youtube-nocookie.com",
    }
)
YOUTUBE_PATHS = frozenset({"embed", "live", "shorts"})
VIMEO_HOSTS = frozenset({"vimeo.com", "www.vimeo.com"})


def clean_url(url: str, *, field: str = "url") -> str:
    url = (url or "").strip()
    if not url:
        raise ValidationError("Enter a link.", field=field)
    if len(url) > URL_MAX:
        raise ValidationError("The link is too long.", field=field)
    if not url.lower().startswith("https://"):
        raise ValidationError("The link must start with https://.", field=field)
    try:
        URLValidator(schemes=["https"])(url)
    except DjangoValidationError:
        raise ValidationError("Enter a valid link.", field=field) from None
    return url


def _youtube(parts) -> str:
    host = (parts.hostname or "").lower()
    if host == "youtu.be":
        return parts.path.lstrip("/").split("/")[0]
    if host not in YOUTUBE_HOSTS:
        return ""
    if parts.path == "/watch":
        return parse_qs(parts.query).get("v", [""])[0]
    segments = parts.path.strip("/").split("/")
    if len(segments) >= 2 and segments[0] in YOUTUBE_PATHS:  # noqa: PLR2004
        return segments[1]
    return ""


def _vimeo(parts) -> str:
    host = (parts.hostname or "").lower()
    segments = parts.path.strip("/").split("/")
    if host in VIMEO_HOSTS and len(segments) == 1:
        return segments[0]
    if host == "player.vimeo.com" and len(segments) == 2 and segments[0] == "video":  # noqa: PLR2004
        return segments[1]
    return ""


def parse_video_url(url: str) -> tuple[str, str]:
    parts = urlsplit(url)
    candidate = _youtube(parts)
    if YOUTUBE_ID.fullmatch(candidate or ""):
        return ("youtube", candidate)
    candidate = _vimeo(parts)
    if VIMEO_ID.fullmatch(candidate or ""):
        return ("vimeo", candidate)
    return ("", "")
```

- [ ] **Step 4: Run to see it pass** — `B pytest etqan/recorded/tests/test_embeds.py -q` → PASS.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded/embeds.py etqan/recorded/tests/test_embeds.py
git -C backend commit -m "feat(recorded): B7a video URL rules and embeds

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Playlist services and file cleanup (A-1, A-2, A-12)

**Files:**
- Create: `backend/etqan/recorded/services/__init__.py`, `services/playlists.py`, `backend/etqan/recorded/signals.py`, `tests/test_playlists.py`
- Modify: `backend/etqan/recorded/apps.py` (add `ready()`)

**Interfaces:**
- Consumes: Task 1 models and `files.*`.
- Produces (exported from `etqan.recorded.services`):
  - `create_playlist(*, title, slug, description, code, content_language, terms, thumbnail, price_minor=0, discount_minor=0, currency=None, content="", intro_video=None, is_published=False, certificate=False, app_only=False) -> Playlist`
  - `update_playlist(playlist, **changes) -> Playlist` (same keys; `thumbnail` / `intro_video` replace the file; `remove_intro=True` clears the intro)
  - `delete_playlist(playlist) -> None` (409 `recorded.playlist_in_use`)
  - `get_playlist(pk) -> Playlist` (NotFoundError)
  - `playlists_queryset() -> QuerySet[Playlist]`, annotated `lessons`, `seconds`, `enrolment_count`
  - `filter_playlists(qs, *, published: bool | None = None, language: str = "", has_discount: bool | None = None, q: str = "") -> QuerySet`

- [ ] **Step 1: Write the failing tests** (`tests/test_playlists.py`)

```python
import pytest

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.recorded import services
from etqan.recorded.models import Enrolment
from etqan.recorded.models import Playlist
from etqan.recorded.models import PlaylistVideo
from etqan.recorded.tests.conftest import mp4
from etqan.recorded.tests.conftest import png

pytestmark = pytest.mark.django_db


def make(**extra):
    data = {
        "title": "Tajweed",
        "slug": "tajweed",
        "description": "About",
        "code": "taj-1",
        "content_language": "ar",
        "terms": "Terms",
        "thumbnail": png(),
        "price_minor": 2000,
        "discount_minor": 500,
        "currency": "usd",
        **extra,
    }
    return services.create_playlist(**data)


def test_create_cleans_values():
    pl = make(title="  Tajweed  ")
    assert (pl.title, pl.code, pl.currency) == ("Tajweed", "TAJ-1", "USD")
    assert pl.thumbnail.name.startswith("tenants/")
    assert pl.is_published is False


def test_currency_defaults_to_the_academy(monkeypatch):
    pl = make(currency=None)
    from etqan.academy import services as academy_services  # noqa: PLC0415

    assert pl.currency == academy_services.get_settings().default_currency


@pytest.mark.parametrize(
    ("extra", "field"),
    [
        ({"title": ""}, "title"),
        ({"title": "x" * 161}, "title"),
        ({"slug": "Not A Slug"}, "slug"),
        ({"code": "bad code!"}, "code"),
        ({"description": ""}, "description"),
        ({"description": "x" * 2001}, "description"),
        ({"terms": ""}, "terms"),
        ({"content_language": "de"}, "content_language"),
        ({"price_minor": -1}, "price_minor"),
        ({"discount_minor": 2001}, "discount_minor"),
        ({"currency": "us"}, "currency"),
        ({"content": "x" * 20001}, "content"),
        ({"thumbnail": mp4("t.png")}, "thumbnail"),
        ({"intro_video": png("i.mp4")}, "intro_video"),
    ],
)
def test_create_refuses(extra, field):
    with pytest.raises(ValidationError) as caught:
        make(**extra)
    assert caught.value.field == field


def test_slug_and_code_are_unique():
    make()
    with pytest.raises(ValidationError) as caught:
        make(code="OTHER")
    assert caught.value.field == "slug"
    with pytest.raises(ValidationError) as caught:
        make(slug="other")
    assert caught.value.field == "code"


def test_update_replaces_thumbnail_and_clears_intro(django_capture_on_commit_callbacks):
    pl = make(intro_video=mp4())
    old_thumb = pl.thumbnail.name
    with django_capture_on_commit_callbacks(execute=True):
        pl = services.update_playlist(
            pl, title="New", thumbnail=png("n.png"), remove_intro=True
        )
    assert pl.title == "New"
    assert pl.thumbnail.name != old_thumb
    assert not pl.intro_video
    assert not pl.thumbnail.storage.exists(old_thumb)


def test_update_keeps_discount_within_price():
    pl = make()
    with pytest.raises(ValidationError) as caught:
        services.update_playlist(pl, price_minor=100)
    assert caught.value.field == "discount_minor"


def test_counts_published_videos_only():
    pl = make()
    for i, (status, seconds) in enumerate(
        [("published", 60), ("published", 90), ("draft", 600), ("hidden", 30)]
    ):
        PlaylistVideo.objects.create(
            playlist=pl, code=f"V{i}", title="v", slug=f"v{i}", kind="link",
            url="https://x.test/v", duration_seconds=seconds, position=i,
            status=status,
        )
    row = services.playlists_queryset().get(pk=pl.pk)
    assert (row.lessons, row.seconds, row.enrolment_count) == (2, 150, 0)


def test_filters():
    a = make(is_published=True)
    b = make(slug="b", code="B", content_language="en", discount_minor=0)
    qs = services.playlists_queryset()
    assert list(services.filter_playlists(qs, published=True)) == [a]
    assert list(services.filter_playlists(qs, language="en")) == [b]
    assert list(services.filter_playlists(qs, has_discount=True)) == [a]
    assert list(services.filter_playlists(qs, q="b")) == [b]  # code B


def test_delete_refused_with_enrolments(people):
    pl = make()
    Enrolment.objects.create(
        playlist=pl, student=people.profile, amount_minor=0, currency="USD",
        method="free",
    )
    with pytest.raises(ConflictError) as caught:
        services.delete_playlist(pl)
    assert caught.value.code == "recorded.playlist_in_use"


def test_delete_removes_files(django_capture_on_commit_callbacks):
    pl = make()
    name = pl.thumbnail.name
    with django_capture_on_commit_callbacks(execute=True):
        services.delete_playlist(pl)
    assert not Playlist.objects.exists()
    assert not pl.thumbnail.storage.exists(name)


def test_get_playlist_404():
    with pytest.raises(NotFoundError):
        services.get_playlist(999999)
```

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/recorded/tests/test_playlists.py -q` → FAIL (`cannot import name 'services'`).

- [ ] **Step 3: Implement**

`backend/etqan/recorded/services/playlists.py`:

```python
"""Spec A-1, A-2, A-12: playlists (TutorHamster's play lists)."""

import re

from django.db import IntegrityError
from django.db import transaction
from django.db.models import Count
from django.db.models import IntegerField
from django.db.models import OuterRef
from django.db.models import Q
from django.db.models import Subquery
from django.db.models import Sum
from django.db.models.functions import Coalesce

from etqan.academy import services as academy_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency
from etqan.recorded import files
from etqan.recorded.models import Enrolment
from etqan.recorded.models import Playlist
from etqan.recorded.models import PlaylistVideo

SLUG = re.compile(r"^[a-z0-9-]{1,80}$")
CODE = re.compile(r"^[A-Z0-9_-]{1,40}$")
LIMITS = {"title": 160, "description": 2000, "terms": 10000, "content": 20000}
REQUIRED = ("title", "description", "terms")
FLAGS = ("is_published", "certificate", "app_only")
PUBLISHED = PlaylistVideo.Status.PUBLISHED


def _text(value, field) -> str:
    text = (value or "").strip()
    if field in REQUIRED and not text:
        raise ValidationError("This field is required.", field=field)
    if len(text) > LIMITS[field]:
        raise ValidationError(
            f"At most {LIMITS[field]} characters.", field=field
        )
    return text


def _slug(value) -> str:
    slug = (value or "").strip()
    if not SLUG.fullmatch(slug):
        raise ValidationError(
            "Use lower-case letters, digits and dashes.", field="slug"
        )
    return slug


def _code(value) -> str:
    code = (value or "").strip().upper()
    if not CODE.fullmatch(code):
        raise ValidationError(
            "Use letters, digits, dashes and underscores (at most 40).",
            field="code",
        )
    return code


def _language(value) -> str:
    if value not in Playlist.Language.values:
        raise ValidationError("Choose a language.", field="content_language")
    return value


def _money(row: Playlist) -> None:
    if row.price_minor < 0:
        raise ValidationError("The price cannot be negative.", field="price_minor")
    if row.discount_minor < 0 or row.discount_minor > row.price_minor:
        raise ValidationError(
            "The discount must be between 0 and the price.", field="discount_minor"
        )


def _unique(row: Playlist) -> None:
    others = Playlist.objects.exclude(pk=row.pk)
    if others.filter(slug=row.slug).exists():
        raise ValidationError("This slug is taken.", field="slug")
    if others.filter(code=row.code).exists():
        raise ValidationError("This code is taken.", field="code")


def _save(row: Playlist) -> None:
    """Unique checks first; a race on the same slug or code still answers
    400, not 500 (the savepoint rolls back only the insert)."""
    _unique(row)
    try:
        with transaction.atomic():
            row.save()
    except IntegrityError:
        _unique(row)
        raise


def _apply(row: Playlist, changes: dict) -> list[str | None]:
    """Set every given value on ``row``; returns stale file names."""
    stale: list[str | None] = []
    for field in ("title", "description", "terms", "content"):
        if field in changes:
            setattr(row, field, _text(changes[field], field))
    if "slug" in changes:
        row.slug = _slug(changes["slug"])
    if "code" in changes:
        row.code = _code(changes["code"])
    if "content_language" in changes:
        row.content_language = _language(changes["content_language"])
    for field in ("price_minor", "discount_minor"):
        if field in changes:
            setattr(row, field, int(changes[field]))
    if changes.get("currency") is not None:
        row.currency = clean_currency(changes["currency"], field="currency")
    for flag in FLAGS:
        if flag in changes:
            setattr(row, flag, bool(changes[flag]))
    if changes.get("thumbnail") is not None:
        stale.append(
            files.store(
                row.thumbnail,
                changes["thumbnail"],
                extensions=files.IMAGES,
                max_bytes=files.THUMB_MAX,
                field="thumbnail",
            )
        )
    if changes.get("intro_video") is not None:
        stale.append(
            files.store(
                row.intro_video,
                changes["intro_video"],
                extensions=files.VIDEOS,
                max_bytes=files.INTRO_MAX,
                field="intro_video",
            )
        )
    elif changes.get("remove_intro"):
        stale.append(row.intro_video.name or None)
        row.intro_video = ""
    _money(row)
    return stale


@transaction.atomic
def create_playlist(  # noqa: PLR0913 -- keyword-only; one playlist's columns
    *,
    title,
    slug,
    description,
    code,
    content_language,
    terms,
    thumbnail,
    price_minor=0,
    discount_minor=0,
    currency=None,
    content="",
    intro_video=None,
    is_published=False,
    certificate=False,
    app_only=False,
) -> Playlist:
    if thumbnail is None:
        raise ValidationError("Choose a thumbnail.", field="thumbnail")
    row = Playlist(
        currency=academy_services.get_settings().default_currency
    )
    _apply(
        row,
        {
            "title": title,
            "slug": slug,
            "description": description,
            "code": code,
            "content_language": content_language,
            "terms": terms,
            "content": content,
            "price_minor": price_minor,
            "discount_minor": discount_minor,
            "currency": currency,
            "thumbnail": thumbnail,
            "intro_video": intro_video,
            "is_published": is_published,
            "certificate": certificate,
            "app_only": app_only,
        },
    )
    _save(row)
    return row


@transaction.atomic
def update_playlist(playlist: Playlist, **changes) -> Playlist:
    row = Playlist.objects.select_for_update().get(pk=playlist.pk)
    stale = _apply(row, changes)
    _save(row)
    for name in stale:
        files.remove_after_commit(row.thumbnail.storage, name)
    return row


@transaction.atomic
def delete_playlist(playlist: Playlist) -> None:
    row = Playlist.objects.select_for_update().get(pk=playlist.pk)
    if Enrolment.objects.filter(playlist=row).exists():
        raise ConflictError(
            "This course has enrolments: unpublish it instead.",
            code="recorded.playlist_in_use",
        )
    row.delete()  # videos cascade; signals remove every file after commit


def get_playlist(pk) -> Playlist:
    row = playlists_queryset().filter(pk=pk).first()
    if row is None:
        raise NotFoundError("Recorded course", pk)
    return row


def playlists_queryset():
    """Each playlist with its published lessons, their total seconds and its
    active enrolments, as subqueries (two joins would multiply each other)."""
    published = PlaylistVideo.objects.filter(
        playlist=OuterRef("pk"), status=PUBLISHED
    ).values("playlist")
    active = Enrolment.objects.filter(
        playlist=OuterRef("pk"), status=Enrolment.Status.ACTIVE
    ).values("playlist")
    return Playlist.objects.annotate(
        lessons=Coalesce(
            Subquery(
                published.annotate(n=Count("pk")).values("n"),
                output_field=IntegerField(),
            ),
            0,
        ),
        seconds=Coalesce(
            Subquery(
                published.annotate(s=Sum("duration_seconds")).values("s"),
                output_field=IntegerField(),
            ),
            0,
        ),
        enrolment_count=Coalesce(
            Subquery(
                active.annotate(n=Count("pk")).values("n"),
                output_field=IntegerField(),
            ),
            0,
        ),
    )


def filter_playlists(qs, *, published=None, language="", has_discount=None, q=""):
    if published is not None:
        qs = qs.filter(is_published=published)
    if language:
        qs = qs.filter(content_language=language)
    if has_discount is not None:
        qs = qs.filter(discount_minor__gt=0) if has_discount else qs.filter(
            discount_minor=0
        )
    if q.strip():
        needle = q.strip()
        qs = qs.filter(Q(title__icontains=needle) | Q(code__iexact=needle))
    return qs
```

`backend/etqan/recorded/signals.py`:

```python
from django.db.models.signals import post_delete
from django.dispatch import receiver

from etqan.recorded import files
from etqan.recorded.models import Playlist
from etqan.recorded.models import PlaylistVideo


@receiver(post_delete, sender=Playlist)
def _drop_playlist_files(sender, instance, **kwargs):
    """A-12: a deleted course loses its thumbnail and intro video."""
    for field in (instance.thumbnail, instance.intro_video):
        files.remove_after_commit(field.storage, field.name or None)


@receiver(post_delete, sender=PlaylistVideo)
def _drop_video_files(sender, instance, **kwargs):
    """A-12: a deleted video (directly or by its course) loses its files."""
    for field in (instance.thumbnail, instance.file):
        files.remove_after_commit(field.storage, field.name or None)
```

`apps.py` gains:

```python
    def ready(self):
        from etqan.recorded import signals  # noqa: F401, PLC0415
```

`backend/etqan/recorded/services/__init__.py`:

```python
"""Public API of the recorded module (B7-1). Other apps import only this
package; the recorded API layer imports it too."""

from etqan.recorded.services.playlists import create_playlist
from etqan.recorded.services.playlists import delete_playlist
from etqan.recorded.services.playlists import filter_playlists
from etqan.recorded.services.playlists import get_playlist
from etqan.recorded.services.playlists import playlists_queryset
from etqan.recorded.services.playlists import update_playlist

__all__ = [
    "create_playlist",
    "delete_playlist",
    "filter_playlists",
    "get_playlist",
    "playlists_queryset",
    "update_playlist",
]
```

Note: the `q` filter matches a title substring or the exact code, case-insensitively. Adjust `test_filters` if `b` matches `a` by title; it does not ("Tajweed" has no `b`).

- [ ] **Step 4: Run** — `B pytest etqan/recorded -q` → PASS.

- [ ] **Step 5: Commit** — `git -C backend add etqan/recorded && git -C backend commit -m "feat(recorded): B7a playlist services" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 4: Video services (A-4…A-7, A-12)

**Files:**
- Create: `backend/etqan/recorded/services/videos.py`, `tests/test_videos.py`
- Modify: `services/__init__.py` (exports)

**Interfaces:**
- Produces:
  - `create_video(playlist, *, code, title, slug, kind, duration_seconds, url="", file=None, thumbnail=None, description="", status="draft", downloadable=False) -> PlaylistVideo`
  - `update_video(video, **changes) -> PlaylistVideo` (any of the same keys; `remove_thumbnail=True`)
  - `delete_video(video) -> None` (409 `recorded.video_in_use`; closes the position gap)
  - `move_video(video, direction: "up" | "down") -> None`
  - `videos_of(playlist_id) -> QuerySet[PlaylistVideo]`
  - `get_video(pk) -> PlaylistVideo`

- [ ] **Step 1: Write the failing tests**

```python
import threading

import pytest
from django.db import connection

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.recorded import services
from etqan.recorded.models import Enrolment
from etqan.recorded.models import PlaylistVideo
from etqan.recorded.models import WatchedVideo
from etqan.recorded.tests.conftest import mp4
from etqan.recorded.tests.conftest import png

pytestmark = pytest.mark.django_db
YT = "https://youtu.be/dQw4w9WgXcQ"


@pytest.fixture
def pl():
    return services.create_playlist(
        title="T", slug="t", description="d", code="T", content_language="ar",
        terms="t", thumbnail=png(), currency="USD",
    )


def add(pl, n=0, **extra):
    data = {"code": f"V{n}", "title": f"V{n}", "slug": f"v{n}", "kind": "link",
            "url": YT, "duration_seconds": 60, **extra}
    return services.create_video(pl, **data)


def positions(pl):
    return list(
        PlaylistVideo.objects.filter(playlist=pl).values_list("code", "position")
    )


def test_link_video_parses_embed(pl):
    v = add(pl)
    assert (v.embed_provider, v.embed_id, v.position) == ("youtube", "dQw4w9WgXcQ", 0)
    ext = add(pl, 1, url="https://example.com/a")
    assert (ext.embed_provider, ext.embed_id, ext.position) == ("", "", 1)


def test_file_video_is_private(pl):
    v = add(pl, kind="file", url="", file=mp4(), downloadable=True)
    assert v.file.name and v.url == "" and v.downloadable


@pytest.mark.parametrize(
    ("extra", "field"),
    [
        ({"kind": "file", "url": ""}, "file"),
        ({"kind": "link", "url": ""}, "url"),
        ({"kind": "link", "url": "http://x.test"}, "url"),
        ({"kind": "link", "downloadable": True}, "downloadable"),
        ({"kind": "tape"}, "kind"),
        ({"duration_seconds": 0}, "duration_seconds"),
        ({"duration_seconds": 86401}, "duration_seconds"),
        ({"status": "gone"}, "status"),
        ({"slug": "Bad Slug"}, "slug"),
        ({"title": ""}, "title"),
        ({"description": "x" * 2001}, "description"),
        ({"kind": "file", "url": "", "file": png("v.mp4")}, "file"),
    ],
)
def test_create_refuses(pl, extra, field):
    with pytest.raises(ValidationError) as caught:
        add(pl, **extra)
    assert caught.value.field == field


def test_file_cap(pl, settings):
    settings.RECORDED_VIDEO_MAX_MB = 0
    with pytest.raises(ValidationError) as caught:
        add(pl, kind="file", url="", file=mp4())
    assert caught.value.field == "file"


def test_code_and_slug_unique_within_playlist(pl):
    add(pl)
    with pytest.raises(ValidationError) as caught:
        add(pl, code="V9")
    assert caught.value.field == "slug"


def test_switch_link_to_file_and_back(pl, django_capture_on_commit_callbacks):
    v = add(pl)
    v = services.update_video(v, kind="file", file=mp4())
    assert v.url == "" and v.embed_provider == "" and v.file
    name = v.file.name
    with django_capture_on_commit_callbacks(execute=True):
        v = services.update_video(v, kind="live", url=YT)
    assert not v.file and v.embed_provider == "youtube" and not v.downloadable
    assert not v.file.storage.exists(name)


def test_move_and_delete_keep_positions_dense(pl):
    for n in range(3):
        add(pl, n)
    services.move_video(PlaylistVideo.objects.get(code="V2"), "up")
    assert positions(pl) == [("V0", 0), ("V2", 1), ("V1", 2)]
    services.move_video(PlaylistVideo.objects.get(code="V0"), "up")  # no-op
    services.delete_video(PlaylistVideo.objects.get(code="V2"))
    assert positions(pl) == [("V0", 0), ("V1", 1)]


def test_bad_direction(pl):
    with pytest.raises(ValidationError):
        services.move_video(add(pl), "sideways")


def test_watched_video_cannot_be_deleted(pl, people):
    v = add(pl, status="published")
    e = Enrolment.objects.create(
        playlist=pl, student=people.profile, amount_minor=0, currency="USD",
        method="free",
    )
    WatchedVideo.objects.create(enrolment=e, video=v)
    with pytest.raises(ConflictError) as caught:
        services.delete_video(v)
    assert caught.value.code == "recorded.video_in_use"
```

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/recorded/tests/test_videos.py -q` → FAIL (`has no attribute 'create_video'`).

- [ ] **Step 3: Implement** `backend/etqan/recorded/services/videos.py`:

```python
"""Spec A-4…A-7, A-12: a playlist's videos, in a dense order."""

import re

from django.db import IntegrityError
from django.db import transaction
from django.db.models import Max

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.recorded import files
from etqan.recorded.embeds import clean_url
from etqan.recorded.embeds import parse_video_url
from etqan.recorded.models import Playlist
from etqan.recorded.models import PlaylistVideo
from etqan.recorded.models import WatchedVideo

SLUG = re.compile(r"^[a-z0-9-]{1,80}$")
CODE = re.compile(r"^[A-Z0-9_-]{1,40}$")
FILE = PlaylistVideo.Kind.FILE


def _text(value, field, limit, *, required) -> str:
    text = (value or "").strip()
    if required and not text:
        raise ValidationError("This field is required.", field=field)
    if len(text) > limit:
        raise ValidationError(f"At most {limit} characters.", field=field)
    return text


def _apply(row: PlaylistVideo, changes: dict) -> list:
    """Set the given values; returns (storage, stale name) pairs."""
    stale = []
    if "title" in changes:
        row.title = _text(changes["title"], "title", 160, required=True)
    if "description" in changes:
        row.description = _text(
            changes["description"], "description", 2000, required=False
        )
    if "code" in changes:
        row.code = (changes["code"] or "").strip().upper()
        if not CODE.fullmatch(row.code):
            raise ValidationError("Use letters, digits, - and _.", field="code")
    if "slug" in changes:
        row.slug = (changes["slug"] or "").strip()
        if not SLUG.fullmatch(row.slug):
            raise ValidationError(
                "Use lower-case letters, digits and dashes.", field="slug"
            )
    if "kind" in changes:
        if changes["kind"] not in PlaylistVideo.Kind.values:
            raise ValidationError("Choose a type.", field="kind")
        row.kind = changes["kind"]
    if "status" in changes:
        if changes["status"] not in PlaylistVideo.Status.values:
            raise ValidationError("Choose a status.", field="status")
        row.status = changes["status"]
    if "duration_seconds" in changes:
        seconds = int(changes["duration_seconds"])
        if not 1 <= seconds <= 86400:  # noqa: PLR2004
            raise ValidationError(
                "Between 1 second and 24 hours.", field="duration_seconds"
            )
        row.duration_seconds = seconds
    if "downloadable" in changes:
        row.downloadable = bool(changes["downloadable"])
    if changes.get("thumbnail") is not None:
        stale.append(
            (
                row.thumbnail.storage,
                files.store(
                    row.thumbnail,
                    changes["thumbnail"],
                    extensions=files.IMAGES,
                    max_bytes=files.THUMB_MAX,
                    field="thumbnail",
                ),
            )
        )
    elif changes.get("remove_thumbnail"):
        stale.append((row.thumbnail.storage, row.thumbnail.name or None))
        row.thumbnail = ""
    if row.kind == FILE:
        if changes.get("file") is not None:
            stale.append(
                (
                    row.file.storage,
                    files.store(
                        row.file,
                        changes["file"],
                        extensions=files.VIDEOS,
                        max_bytes=files.video_max(),
                        field="file",
                    ),
                )
            )
        if not row.file:
            raise ValidationError("Attach an MP4 file.", field="file")
        row.url, row.embed_provider, row.embed_id = "", "", ""
    else:
        if "url" in changes or not row.url:
            row.url = clean_url(changes.get("url", ""))
        row.embed_provider, row.embed_id = parse_video_url(row.url)
        if row.file:
            stale.append((row.file.storage, row.file.name))
            row.file = ""
        if row.downloadable:
            raise ValidationError(
                "Only an uploaded file can be downloadable.", field="downloadable"
            )
    return stale


def _unique(row: PlaylistVideo) -> None:
    others = PlaylistVideo.objects.filter(playlist_id=row.playlist_id).exclude(
        pk=row.pk
    )
    if others.filter(slug=row.slug).exists():
        raise ValidationError("This slug is taken in this course.", field="slug")
    if others.filter(code=row.code).exists():
        raise ValidationError("This code is taken in this course.", field="code")


def _save(row: PlaylistVideo) -> None:
    _unique(row)
    try:
        with transaction.atomic():
            row.save()
    except IntegrityError:
        _unique(row)
        raise


def _lock_playlist(playlist_id) -> None:
    Playlist.objects.select_for_update().filter(pk=playlist_id).first()


@transaction.atomic
def create_video(  # noqa: PLR0913 -- keyword-only; one video's columns
    playlist,
    *,
    code,
    title,
    slug,
    kind,
    duration_seconds,
    url="",
    file=None,
    thumbnail=None,
    description="",
    status="draft",
    downloadable=False,
) -> PlaylistVideo:
    _lock_playlist(playlist.pk)
    last = PlaylistVideo.objects.filter(playlist=playlist).aggregate(
        last=Max("position")
    )["last"]
    row = PlaylistVideo(
        playlist=playlist, position=0 if last is None else last + 1
    )
    _apply(
        row,
        {
            "code": code,
            "title": title,
            "slug": slug,
            "kind": kind,
            "duration_seconds": duration_seconds,
            "url": url,
            "file": file,
            "thumbnail": thumbnail,
            "description": description,
            "status": status,
            "downloadable": downloadable,
        },
    )
    _save(row)
    return row


@transaction.atomic
def update_video(video: PlaylistVideo, **changes) -> PlaylistVideo:
    row = PlaylistVideo.objects.select_for_update().get(pk=video.pk)
    stale = _apply(row, changes)
    _save(row)
    for storage, name in stale:
        files.remove_after_commit(storage, name)
    return row


def _renumber(playlist_id) -> None:
    ids = PlaylistVideo.objects.filter(playlist_id=playlist_id).values_list(
        "pk", flat=True
    )
    for position, pk in enumerate(ids):
        PlaylistVideo.objects.filter(pk=pk).update(position=position)


@transaction.atomic
def delete_video(video: PlaylistVideo) -> None:
    _lock_playlist(video.playlist_id)
    row = PlaylistVideo.objects.select_for_update().get(pk=video.pk)
    if WatchedVideo.objects.filter(video=row).exists():
        raise ConflictError(
            "Students have watched this video: hide it instead.",
            code="recorded.video_in_use",
        )
    playlist_id = row.playlist_id
    row.delete()  # the signal removes its files after commit
    _renumber(playlist_id)


@transaction.atomic
def move_video(video: PlaylistVideo, direction: str) -> None:
    if direction not in ("up", "down"):
        raise ValidationError("Move up or down.", field="direction")
    _lock_playlist(video.playlist_id)
    rows = list(PlaylistVideo.objects.filter(playlist_id=video.playlist_id))
    index = next(i for i, r in enumerate(rows) if r.pk == video.pk)
    other = index - 1 if direction == "up" else index + 1
    if not 0 <= other < len(rows):
        return
    rows[index], rows[other] = rows[other], rows[index]
    for position, row in enumerate(rows):
        if row.position != position:
            PlaylistVideo.objects.filter(pk=row.pk).update(position=position)


def videos_of(playlist_id):
    return PlaylistVideo.objects.filter(playlist_id=playlist_id)


def get_video(pk) -> PlaylistVideo:
    row = PlaylistVideo.objects.select_related("playlist").filter(pk=pk).first()
    if row is None:
        raise NotFoundError("Video", pk)
    return row
```

Add the six names to `services/__init__.py` (`create_video`, `update_video`, `delete_video`, `move_video`, `videos_of`, `get_video`) and to `__all__`.

- [ ] **Step 4: Run** — `B pytest etqan/recorded -q` → PASS.
- [ ] **Step 5: Commit** — `git -C backend add etqan/recorded && git -C backend commit -m "feat(recorded): B7a video services" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 5: Enrolments, the billing record and watching (A-8…A-11)

**Files:**
- Create: `backend/etqan/recorded/services/enrolments.py`, `services/watching.py`, `tests/test_enrolments.py`, `tests/test_watching.py`
- Modify: `services/__init__.py`

**Interfaces:**
- Consumes: `billing.services.create_record(*, customer_type, amount_minor, method, by, student_id, currency, transaction_number, reference, paid_on, notes) -> Payment` (`student_id` = **user id**); `billing.services.MANUAL_PAYMENT_METHODS` (tuple of `(value, label)`); `identity.services.get_student_profile(user_id) -> StudentProfile | None`.
- Spec §8.2 (as amended 2026-10-08): `set_watched` and `update_enrolment`'s watched-set change lock the enrolment row (`select_for_update`) first, then write, then count. `is_complete` is false for a playlist with no published videos. `Enrolment` has **no** `certificate_obtained` field (B7g reads certificates from learning). `create_record` gets the **user id** and answers 400 `student` for a deactivated student; that error propagates unchanged (400 on the enrol route).
- Produces:
  - `enrol_by_office(*, playlist, student_user_id, method, amount_minor, billing_method="", paid_on=None, reference="", transaction_number="", notes="", by) -> Enrolment`
  - `enrol_from_sale(*, playlist, student_user_id, method, amount_minor, currency, transaction_number, payment_id, by=None) -> Enrolment` (methods `stripe`, `paypal`, `code`; no view calls it)
  - `revoke(enrolment, *, by) -> Enrolment`, `restore(enrolment, *, by) -> Enrolment`, `delete_enrolment(enrolment) -> None`
  - `update_enrolment(enrolment, *, notes=None, transaction_number=None, watched_video_ids=None) -> Enrolment`
  - `enrolments_queryset() -> QuerySet[Enrolment]` (student + user selected, `watched` prefetched, annotated `watched_count` of published videos), `filter_enrolments(qs, *, method="", status="")`, `get_enrolment(pk) -> Enrolment`
  - `Progress(watched: int, total: int)`, `progress(enrolment) -> Progress`, `set_watched(enrolment, video, watched: bool) -> None`, `enrolment_for(student_user_id, playlist_id) -> Enrolment | None` (active only), `is_complete(enrolment) -> bool`

- [ ] **Step 1: Write the failing tests** (`tests/test_enrolments.py`)

```python
import threading

import pytest
from django.db import connection

from etqan.billing import services as billing_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.recorded import services
from etqan.recorded.models import Enrolment
from etqan.recorded.models import WatchedVideo
from etqan.recorded.tests.conftest import png

pytestmark = pytest.mark.django_db


@pytest.fixture
def pl():
    pl = services.create_playlist(
        title="T", slug="t", description="d", code="T", content_language="ar",
        terms="t", thumbnail=png(), currency="USD", price_minor=2000,
    )
    for n, status in enumerate(["published", "published", "hidden"]):
        services.create_video(
            pl, code=f"V{n}", title="v", slug=f"v{n}", kind="link",
            url="https://x.test/v", duration_seconds=60, status=status,
        )
    return pl


@pytest.fixture
def admin(api_for):
    return api_for("admin").user


def manual(pl, people, admin, **extra):
    data = {"playlist": pl, "student_user_id": people.student.pk,
            "method": "manual", "amount_minor": 1500, "billing_method": "cash",
            "by": admin, **extra}
    return services.enrol_by_office(**data)


def test_manual_enrolment_records_a_billing_payment(pl, people, admin):
    e = manual(pl, people, admin, transaction_number="TX1", reference="r")
    assert (e.method, e.amount_minor, e.currency, e.status) == (
        "manual", 1500, "USD", "active",
    )
    payment = billing_services.payments_queryset().get(pk=e.payment_id)
    assert (payment.amount_minor, payment.currency, payment.method) == (
        1500, "USD", "cash",
    )
    assert payment.student.user_id == people.student.pk
    assert payment.notes == "Recorded course: T"
    assert e.enrolled_by == admin


def test_free_enrolment_has_no_payment(pl, people, admin):
    e = services.enrol_by_office(
        playlist=pl, student_user_id=people.student.pk, method="free",
        amount_minor=900, by=admin,
    )
    assert (e.amount_minor, e.payment_id) == (0, None)


@pytest.mark.parametrize(
    ("extra", "field"),
    [
        ({"method": "stripe"}, "method"),
        ({"method": "code"}, "method"),
        ({"amount_minor": 0}, "amount_minor"),
        ({"billing_method": ""}, "billing_method"),
        ({"billing_method": "stripe"}, "billing_method"),
        ({"notes": "x" * 2001}, "notes"),
        ({"transaction_number": "x" * 121}, "transaction_number"),
    ],
)
def test_office_refusals(pl, people, admin, extra, field):
    with pytest.raises(ValidationError) as caught:
        manual(pl, people, admin, **extra)
    assert caught.value.field == field


def test_deactivated_student_is_refused_by_billing(pl, people, admin):
    from etqan.identity import services as identity_services  # noqa: PLC0415

    identity_services.deactivate(people.student, by=admin)
    with pytest.raises(ValidationError) as caught:
        manual(pl, people, admin)
    assert caught.value.field == "student"
    assert not Enrolment.objects.exists()


def test_not_a_student(pl, people, admin):
    with pytest.raises(ValidationError) as caught:
        manual(pl, people, admin, student_user_id=people.teacher.pk)
    assert caught.value.field == "student"


def test_duplicate_is_409(pl, people, admin):
    manual(pl, people, admin)
    with pytest.raises(ConflictError) as caught:
        services.enrol_by_office(
            playlist=pl, student_user_id=people.student.pk, method="free",
            amount_minor=0, by=admin,
        )
    assert caught.value.code == "recorded.already_enrolled"


def test_manual_enrolment_rolls_back_with_billing(pl, people, admin):
    manual(pl, people, admin, transaction_number="DUP")
    other = services.create_playlist(
        title="O", slug="o", description="d", code="O", content_language="ar",
        terms="t", thumbnail=png(), currency="USD",
    )
    with pytest.raises(ValidationError) as caught:
        manual(other, people, admin, transaction_number="DUP")
    assert caught.value.field == "transaction_number"
    assert not Enrolment.objects.filter(playlist=other).exists()


@pytest.mark.django_db(transaction=True)
def test_duplicate_enrolment_race_is_409(tenants, people, admin):
    """Two office users at once: one enrols, the other gets 409."""
    connection.set_tenant(tenants.main)
    pl = services.create_playlist(
        title="R", slug="r", description="d", code="R", content_language="ar",
        terms="t", thumbnail=png(), currency="USD",
    )
    results = []

    def go():
        connection.set_tenant(tenants.main)
        try:
            services.enrol_by_office(
                playlist=pl, student_user_id=people.student.pk, method="free",
                amount_minor=0, by=admin,
            )
            results.append("ok")
        except ConflictError:
            results.append("409")
        finally:
            connection.close()

    threads = [threading.Thread(target=go) for _ in range(2)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sorted(results) == ["409", "ok"]


def test_from_sale_only_sale_methods(pl, people):
    with pytest.raises(ValidationError):
        services.enrol_from_sale(
            playlist=pl, student_user_id=people.student.pk, method="manual",
            amount_minor=1, currency="USD", transaction_number="t", payment_id=None,
        )
    e = services.enrol_from_sale(
        playlist=pl, student_user_id=people.student.pk, method="stripe",
        amount_minor=1500, currency="USD", transaction_number="pi_1",
        payment_id=None,
    )
    assert (e.method, e.enrolled_by) == ("stripe", None)


def test_revoke_restore_delete(pl, people, admin):
    e = services.enrol_by_office(
        playlist=pl, student_user_id=people.student.pk, method="free",
        amount_minor=0, by=admin,
    )
    e = services.revoke(e, by=admin)
    assert (e.status, e.revoked_by) == ("revoked", admin)
    second = services.enrol_by_office(
        playlist=pl, student_user_id=people.student.pk, method="free",
        amount_minor=0, by=admin,
    )
    with pytest.raises(ConflictError) as caught:
        services.restore(e, by=admin)
    assert caught.value.code == "recorded.already_enrolled"
    services.delete_enrolment(second)
    e = services.restore(e, by=admin)
    assert (e.status, e.revoked_at) == ("active", None)
    video = pl.videos.first()
    WatchedVideo.objects.create(enrolment=e, video=video)
    with pytest.raises(ConflictError) as caught:
        services.delete_enrolment(e)
    assert caught.value.code == "recorded.enrolment_in_use"


def test_paid_online_enrolment_cannot_be_deleted(pl, people):
    e = services.enrol_from_sale(
        playlist=pl, student_user_id=people.student.pk, method="paypal",
        amount_minor=1, currency="USD", transaction_number="o", payment_id=None,
    )
    with pytest.raises(ConflictError):
        services.delete_enrolment(e)


def test_update_sets_the_watched_set(pl, people, admin):
    e = manual(pl, people, admin)
    published, other_pub, hidden = pl.videos.order_by("position")
    e = services.update_enrolment(
        e, notes=" n ", watched_video_ids=[published.pk, hidden.pk]
    )
    assert e.notes == "n"
    assert set(e.watched.values_list("video_id", flat=True)) == {
        published.pk, hidden.pk,
    }
    e = services.update_enrolment(e, watched_video_ids=[other_pub.pk])
    assert list(e.watched.values_list("video_id", flat=True)) == [other_pub.pk]


def test_watched_set_rejects_foreign_videos(pl, people, admin):
    e = manual(pl, people, admin)
    with pytest.raises(ValidationError) as caught:
        services.update_enrolment(e, watched_video_ids=[999999])
    assert caught.value.field == "watched_video_ids"
```

`tests/test_watching.py`:

```python
import pytest

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.recorded import services
from etqan.recorded.tests.conftest import png

pytestmark = pytest.mark.django_db


@pytest.fixture
def setup(people, api_for):
    pl = services.create_playlist(
        title="T", slug="t", description="d", code="T", content_language="ar",
        terms="t", thumbnail=png(), currency="USD", is_published=True,
    )
    videos = [
        services.create_video(
            pl, code=f"V{n}", title="v", slug=f"v{n}", kind="link",
            url="https://x.test/v", duration_seconds=60, status="published",
        )
        for n in range(2)
    ]
    e = services.enrol_by_office(
        playlist=pl, student_user_id=people.student.pk, method="free",
        amount_minor=0, by=api_for("admin").user,
    )
    return pl, videos, e


def test_set_watched_is_idempotent_and_counts(setup):
    pl, (a, b), e = setup
    services.set_watched(e, a, True)
    services.set_watched(e, a, True)
    assert services.progress(e) == services.Progress(watched=1, total=2)
    services.set_watched(e, a, False)
    services.set_watched(e, a, False)
    assert services.progress(e) == services.Progress(watched=0, total=2)


def test_hidden_video_kept_and_counted_again(setup):
    pl, (a, b), e = setup
    services.set_watched(e, a, True)
    services.update_video(a, status="hidden")
    assert services.progress(e) == services.Progress(watched=0, total=1)
    with pytest.raises(NotFoundError):
        services.set_watched(e, a, False)
    services.update_video(a, status="published")
    assert services.progress(e) == services.Progress(watched=1, total=2)


def test_complete_needs_at_least_one_published_video(people, api_for):
    pl = services.create_playlist(
        title="E", slug="e", description="d", code="E", content_language="ar",
        terms="t", thumbnail=png(), currency="USD", is_published=True,
    )
    e = services.enrol_by_office(
        playlist=pl, student_user_id=people.student.pk, method="free",
        amount_minor=0, by=api_for("admin").user,
    )
    assert services.progress(e) == services.Progress(watched=0, total=0)
    assert services.is_complete(e) is False


def test_watching_locks_the_enrolment_first(setup):
    """§8.2: lock, then write, then count (no write skew for B7g)."""
    from django.db import connection  # noqa: PLC0415
    from django.test.utils import CaptureQueriesContext  # noqa: PLC0415

    pl, (a, b), e = setup
    for call in (
        lambda: services.set_watched(e, a, True),
        lambda: services.update_enrolment(e, watched_video_ids=[b.pk]),
    ):
        with CaptureQueriesContext(connection) as ctx:
            call()
        sqls = [q["sql"] for q in ctx.captured_queries]
        lock = next(
            i for i, sql in enumerate(sqls)
            if "recorded_enrolment" in sql and "FOR UPDATE" in sql
        )
        first_write = next(
            i for i, sql in enumerate(sqls)
            if "recorded_watchedvideo" in sql
            and sql.lstrip().upper().startswith(("INSERT", "DELETE"))
        )
        assert lock < first_write


def test_complete(setup):
    pl, (a, b), e = setup
    assert not services.is_complete(e)
    services.set_watched(e, a, True)
    services.set_watched(e, b, True)
    assert services.is_complete(e)


def test_revoked_cannot_mark(setup, api_for):
    pl, (a, b), e = setup
    e = services.revoke(e, by=api_for("admin").user)
    with pytest.raises(ConflictError) as caught:
        services.set_watched(e, a, True)
    assert caught.value.code == "recorded.enrolment_revoked"


def test_video_of_another_playlist_is_404(setup):
    pl, (a, b), e = setup
    other = services.create_playlist(
        title="O", slug="o", description="d", code="O", content_language="ar",
        terms="t", thumbnail=png(), currency="USD",
    )
    v = services.create_video(
        other, code="X", title="x", slug="x", kind="link",
        url="https://x.test/v", duration_seconds=60, status="published",
    )
    with pytest.raises(NotFoundError):
        services.set_watched(e, v, True)


def test_enrolment_for(setup, people):
    pl, _, e = setup
    assert services.enrolment_for(people.student.pk, pl.pk) == e
    assert services.enrolment_for(people.other.pk, pl.pk) is None
```

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/recorded/tests/test_enrolments.py etqan/recorded/tests/test_watching.py -q` → FAIL.

- [ ] **Step 3: Implement**

`backend/etqan/recorded/services/enrolments.py`:

```python
"""Spec A-8…A-10, B7-4: enrolments (TutorHamster's RC subscriptions). The
office enrols by hand (manual or free); a manual enrolment records its money
in billing in the same transaction. Sales (B7b) and codes (B7g) enrol through
`enrol_from_sale`, which no view reaches."""

from django.db import IntegrityError
from django.db import transaction
from django.db.models import Count
from django.db.models import Q
from django.utils import timezone

from etqan.billing import services as billing_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.recorded.models import Enrolment
from etqan.recorded.models import Playlist
from etqan.recorded.models import PlaylistVideo
from etqan.recorded.models import WatchedVideo

OFFICE_METHODS = (Enrolment.Method.MANUAL, Enrolment.Method.FREE)
SALE_METHODS = (Enrolment.Method.STRIPE, Enrolment.Method.PAYPAL, Enrolment.Method.CODE)
ACTIVE = Enrolment.Status.ACTIVE
NOTES_MAX = 2000
TRANSACTION_MAX = 120
BILLING_NOTES_MAX = 500


def student_profile(student_user_id):
    profile = identity_services.get_student_profile(student_user_id)
    if profile is None:
        raise ValidationError("Choose a student.", field="student")
    return profile


def _already() -> ConflictError:
    return ConflictError(
        "This student is already enrolled in this course.",
        code="recorded.already_enrolled",
    )


def _create(**fields) -> Enrolment:
    """Lock the playlist, re-check, insert; a lost race on the partial unique
    index answers 409 (the savepoint rolls back only the insert)."""
    Playlist.objects.select_for_update().filter(pk=fields["playlist"].pk).first()
    if Enrolment.objects.filter(
        playlist=fields["playlist"], student=fields["student"], status=ACTIVE
    ).exists():
        raise _already()
    try:
        with transaction.atomic():
            return Enrolment.objects.create(**fields)
    except IntegrityError:
        raise _already() from None


def _notes(value) -> str:
    text = (value or "").strip()
    if len(text) > NOTES_MAX:
        raise ValidationError(f"At most {NOTES_MAX} characters.", field="notes")
    return text


def _transaction(value) -> str:
    text = (value or "").strip()
    if len(text) > TRANSACTION_MAX:
        raise ValidationError(
            f"At most {TRANSACTION_MAX} characters.", field="transaction_number"
        )
    return text


@transaction.atomic
def enrol_by_office(  # noqa: PLR0913 -- keyword-only; mirrors the API body
    *,
    playlist,
    student_user_id,
    method,
    amount_minor,
    billing_method="",
    paid_on=None,
    reference="",
    transaction_number="",
    notes="",
    by,
) -> Enrolment:
    if method not in OFFICE_METHODS:
        raise ValidationError("Choose manual or free.", field="method")
    profile = student_profile(student_user_id)
    notes = _notes(notes)
    transaction_number = _transaction(transaction_number)
    payment = None
    if method == Enrolment.Method.FREE:
        amount_minor = 0
    else:
        if int(amount_minor) <= 0:
            raise ValidationError("Enter the amount paid.", field="amount_minor")
        manual = {value for value, _ in billing_services.MANUAL_PAYMENT_METHODS}
        if billing_method not in manual:
            raise ValidationError(
                "Choose how it was paid.", field="billing_method"
            )
    if Enrolment.objects.filter(
        playlist=playlist, student=profile, status=ACTIVE
    ).exists():
        raise _already()
    if method == Enrolment.Method.MANUAL:
        payment = billing_services.create_record(
            customer_type="student",
            student_id=student_user_id,  # billing takes the user id here
            amount_minor=int(amount_minor),
            method=billing_method,
            currency=playlist.currency,
            transaction_number=transaction_number,
            reference=reference,
            paid_on=paid_on,
            notes=f"Recorded course: {playlist.title}"[:BILLING_NOTES_MAX],
            by=by,
        )
    return _create(
        playlist=playlist,
        student=profile,
        amount_minor=int(amount_minor),
        currency=playlist.currency,
        method=method,
        transaction_number=transaction_number,
        payment=payment,
        notes=notes,
        enrolled_by=by,
    )


@transaction.atomic
def enrol_from_sale(  # noqa: PLR0913 -- keyword-only; one sale
    *,
    playlist,
    student_user_id,
    method,
    amount_minor,
    currency,
    transaction_number,
    payment_id,
    by=None,
) -> Enrolment:
    if method not in SALE_METHODS:
        raise ValidationError("Not a sale method.", field="method")
    return _create(
        playlist=playlist,
        student=student_profile(student_user_id),
        amount_minor=int(amount_minor),
        currency=currency,
        method=method,
        transaction_number=_transaction(transaction_number),
        payment_id=payment_id,
        enrolled_by=by,
    )


def _locked(enrolment) -> Enrolment:
    return Enrolment.objects.select_for_update().get(pk=enrolment.pk)


@transaction.atomic
def revoke(enrolment, *, by) -> Enrolment:
    row = _locked(enrolment)
    if row.status != ACTIVE:
        return row
    row.status = Enrolment.Status.REVOKED
    row.revoked_by, row.revoked_at = by, timezone.now()
    row.save(update_fields=["status", "revoked_by", "revoked_at"])
    return row


@transaction.atomic
def restore(enrolment, *, by) -> Enrolment:
    row = _locked(enrolment)
    if row.status == ACTIVE:
        return row
    Playlist.objects.select_for_update().filter(pk=row.playlist_id).first()
    if Enrolment.objects.filter(
        playlist_id=row.playlist_id, student_id=row.student_id, status=ACTIVE
    ).exists():
        raise _already()
    row.status, row.revoked_by, row.revoked_at = ACTIVE, None, None
    row.save(update_fields=["status", "revoked_by", "revoked_at"])
    return row


@transaction.atomic
def delete_enrolment(enrolment) -> None:
    row = _locked(enrolment)
    if row.method not in OFFICE_METHODS or row.watched.exists():
        raise ConflictError(
            "This enrolment has history: revoke it instead.",
            code="recorded.enrolment_in_use",
        )
    row.delete()  # its billing payment stays: money is billing's (B7-4)


@transaction.atomic
def update_enrolment(
    enrolment, *, notes=None, transaction_number=None, watched_video_ids=None
) -> Enrolment:
    row = _locked(enrolment)
    fields = []
    if notes is not None:
        row.notes = _notes(notes)
        fields.append("notes")
    if transaction_number is not None:
        row.transaction_number = _transaction(transaction_number)
        fields.append("transaction_number")
    if fields:
        row.save(update_fields=fields)
    if watched_video_ids is not None:
        wanted = set(watched_video_ids)
        known = set(
            PlaylistVideo.objects.filter(
                playlist_id=row.playlist_id, pk__in=wanted
            ).values_list("pk", flat=True)
        )
        if known != wanted:
            raise ValidationError(
                "Choose videos of this course.", field="watched_video_ids"
            )
        row.watched.exclude(video_id__in=wanted).delete()
        have = set(row.watched.values_list("video_id", flat=True))
        WatchedVideo.objects.bulk_create(
            [WatchedVideo(enrolment=row, video_id=v) for v in wanted - have]
        )
    return row


def enrolments_queryset():
    return (
        Enrolment.objects.select_related("student__user", "playlist")
        .prefetch_related("watched")
        .annotate(
            watched_count=Count(
                "watched",
                filter=Q(watched__video__status=PlaylistVideo.Status.PUBLISHED),
                distinct=True,
            )
        )
    )


def filter_enrolments(qs, *, method="", status=""):
    if method:
        qs = qs.filter(method=method)
    if status:
        qs = qs.filter(status=status)
    return qs


def get_enrolment(pk) -> Enrolment:
    row = enrolments_queryset().filter(pk=pk).first()
    if row is None:
        raise NotFoundError("Enrolment", pk)
    return row
```

`backend/etqan/recorded/services/watching.py`:

```python
"""Spec A-6, A-11: watched videos and progress (published videos only)."""

from dataclasses import dataclass

from django.db import transaction

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.recorded.models import Enrolment
from etqan.recorded.models import PlaylistVideo
from etqan.recorded.models import WatchedVideo

PUBLISHED = PlaylistVideo.Status.PUBLISHED


@dataclass(frozen=True)
class Progress:
    watched: int
    total: int


def progress(enrolment) -> Progress:
    total = PlaylistVideo.objects.filter(
        playlist_id=enrolment.playlist_id, status=PUBLISHED
    ).count()
    watched = WatchedVideo.objects.filter(
        enrolment=enrolment, video__status=PUBLISHED
    ).count()
    return Progress(watched=watched, total=total)


def is_complete(enrolment) -> bool:
    p = progress(enrolment)
    return p.total > 0 and p.watched == p.total


@transaction.atomic
def set_watched(enrolment, video, watched: bool) -> None:
    row = Enrolment.objects.select_for_update().get(pk=enrolment.pk)
    if video.playlist_id != row.playlist_id or video.status != PUBLISHED:
        raise NotFoundError("Video", video.pk)
    if row.status != Enrolment.Status.ACTIVE:
        raise ConflictError(
            "This enrolment is revoked.", code="recorded.enrolment_revoked"
        )
    if watched:
        WatchedVideo.objects.get_or_create(enrolment=row, video=video)
    else:
        WatchedVideo.objects.filter(enrolment=row, video=video).delete()


def enrolment_for(student_user_id, playlist_id) -> Enrolment | None:
    return Enrolment.objects.filter(
        student__user_id=student_user_id,
        playlist_id=playlist_id,
        status=Enrolment.Status.ACTIVE,
    ).first()
```

Export from `services/__init__.py`: `Progress`, `progress`, `is_complete`, `set_watched`, `enrolment_for`, `enrol_by_office`, `enrol_from_sale`, `revoke`, `restore`, `delete_enrolment`, `update_enrolment`, `enrolments_queryset`, `filter_enrolments`, `get_enrolment`, `student_profile`.

If `create_record` refuses a `paid_on` of `None`, it defaults to today already (`paid_on or clock.today()`); no change needed.

- [ ] **Step 4: Run** — `B pytest etqan/recorded -q` → PASS. (The race test needs `transaction=True`; if the tenant fixture setup differs, follow `etqan/scheduling/tests` race tests' pattern for `transaction=True` with `tenants`.)
- [ ] **Step 5: Commit** — `git -C backend add etqan/recorded && git -C backend commit -m "feat(recorded): B7a enrolments, billing record and watching" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 6: Access resources and the office API for playlists and videos

**Files:**
- Create: `backend/etqan/recorded/api/__init__.py` (empty), `api/serializers.py`, `api/views.py`, `api/urls.py`, `tests/test_api_office.py`
- Modify: `backend/config/api_router.py` (B7 marker), `backend/etqan/access/registry.py` (B7 marker), `backend/etqan/access/tests/test_routes.py` (ROUTES, FEATURES, FEATURE_WORDS)

**Interfaces:**
- Produces: routes `recorded/playlists/`, `recorded/playlists/<pk>/`, `recorded/playlists/<pk>/videos/`, `recorded/videos/<pk>/`, `recorded/videos/<pk>/move/`; serializer helpers `playlist_data(p) -> dict`, `video_data(v) -> dict`, `money_ref`; JSON shapes used by the dashboard (Task 11):
  - playlist: `{id, title, slug, description, code, content_language, price_minor, discount_minor, currency, content, terms, is_published, certificate, app_only, thumbnail_url, intro_video_url, lessons, seconds, enrolments}`
  - video: `{id, playlist, code, title, slug, kind, url, embed_provider, embed_id, has_file, thumbnail_url, duration_seconds, position, description, status, downloadable}`

- [ ] **Step 1: Write the failing tests** (`tests/test_api_office.py`)

```python
import pytest

from etqan.recorded.models import Playlist
from etqan.recorded.tests.conftest import mp4
from etqan.recorded.tests.conftest import png

pytestmark = pytest.mark.django_db
P = "/api/v1/recorded/playlists/"
V = "/api/v1/recorded/videos/"


@pytest.fixture
def admin(api_for, people):
    return api_for("admin")


def create(client, **extra):
    data = {"title": "Tajweed", "slug": "tajweed", "description": "d",
            "code": "TAJ", "content_language": "ar", "terms": "t",
            "thumbnail": png(), "price_minor": 2000, "discount_minor": 500,
            "currency": "USD", **extra}
    resp = client.post(P, data, format="multipart")
    assert resp.status_code == 201, resp.content
    return resp.json()


def test_playlist_round_trip(admin):
    pl = create(admin, is_published="true")
    assert pl["thumbnail_url"].startswith("/") or pl["thumbnail_url"].startswith("http")
    assert (pl["lessons"], pl["seconds"], pl["enrolments"], pl["is_published"]) == (
        0, 0, 0, True,
    )
    assert [r["id"] for r in admin.get(P).json()] == [pl["id"]]
    assert admin.get(P, {"published": "false"}).json() == []
    resp = admin.patch(f"{P}{pl['id']}/", {"title": "New"}, format="multipart")
    assert resp.status_code == 200 and resp.json()["title"] == "New"
    assert admin.get(f"{P}{pl['id']}/").json()["title"] == "New"
    assert admin.delete(f"{P}{pl['id']}/").status_code == 204
    assert not Playlist.objects.exists()


def test_validation_is_400_on_the_field(admin):
    resp = admin.post(P, {"title": "x"}, format="multipart")
    assert resp.status_code == 400
    create(admin)
    resp = admin.post(
        P,
        {"title": "T", "slug": "tajweed", "description": "d", "code": "OTHER",
         "content_language": "ar", "terms": "t", "thumbnail": png()},
        format="multipart",
    )
    assert (resp.status_code, list(resp.json())) == (400, ["slug"])


def test_videos_round_trip_and_move(admin):
    pl = create(admin)
    url = f"{P}{pl['id']}/videos/"
    a = admin.post(url, {"code": "A", "title": "A", "slug": "a", "kind": "link",
                         "url": "https://youtu.be/dQw4w9WgXcQ",
                         "duration_seconds": 60}, format="multipart").json()
    b = admin.post(url, {"code": "B", "title": "B", "slug": "b", "kind": "file",
                         "file": mp4(), "duration_seconds": 90,
                         "downloadable": "true", "status": "published"},
                   format="multipart")
    assert b.status_code == 201, b.content
    b = b.json()
    assert (a["embed_provider"], a["embed_id"]) == ("youtube", "dQw4w9WgXcQ")
    assert (b["has_file"], b["url"], b["downloadable"]) == (True, "", True)
    assert admin.post(f"{V}{b['id']}/move/", {"direction": "up"}).status_code == 204
    assert [v["code"] for v in admin.get(url).json()] == ["B", "A"]
    resp = admin.patch(f"{V}{a['id']}/", {"status": "published"}, format="multipart")
    assert resp.json()["status"] == "published"
    assert admin.get(f"{P}{pl['id']}/").json()["lessons"] == 2
    assert admin.delete(f"{V}{a['id']}/").status_code == 204


def test_unknown_ids_are_404(admin):
    assert admin.get(f"{P}999999/").status_code == 404
    assert admin.patch(f"{V}999999/", {}, format="multipart").status_code == 404


def test_family_and_teachers_get_403(api_for, people):
    for role in ("student", "parent", "teacher"):
        assert api_for(role).get(P).status_code == 403
```

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/recorded/tests/test_api_office.py -q` → FAIL (404s: no routes).

- [ ] **Step 3: Implement**

`backend/etqan/recorded/api/serializers.py`:

```python
from rest_framework import serializers

from etqan.recorded.models import Enrolment
from etqan.recorded.models import Playlist
from etqan.recorded.models import PlaylistVideo


def _url(field) -> str:
    return field.url if field else ""


class PlaylistInput(serializers.Serializer):
    """Shape only; the services own every rule (and its field name)."""

    title = serializers.CharField(required=False, allow_blank=True, max_length=400)
    slug = serializers.CharField(required=False, allow_blank=True, max_length=200)
    description = serializers.CharField(required=False, allow_blank=True, max_length=4000)
    code = serializers.CharField(required=False, allow_blank=True, max_length=100)
    content_language = serializers.CharField(required=False, allow_blank=True, max_length=8)
    terms = serializers.CharField(required=False, allow_blank=True, max_length=20000)
    content = serializers.CharField(required=False, allow_blank=True, max_length=40000)
    price_minor = serializers.IntegerField(required=False)
    discount_minor = serializers.IntegerField(required=False)
    currency = serializers.CharField(required=False, allow_blank=True, max_length=8)
    thumbnail = serializers.FileField(required=False)
    intro_video = serializers.FileField(required=False)
    remove_intro = serializers.BooleanField(required=False)
    is_published = serializers.BooleanField(required=False)
    certificate = serializers.BooleanField(required=False)
    app_only = serializers.BooleanField(required=False)


class VideoInput(serializers.Serializer):
    code = serializers.CharField(required=False, allow_blank=True, max_length=100)
    title = serializers.CharField(required=False, allow_blank=True, max_length=400)
    slug = serializers.CharField(required=False, allow_blank=True, max_length=200)
    kind = serializers.CharField(required=False, max_length=8)
    url = serializers.CharField(required=False, allow_blank=True, max_length=1000)
    file = serializers.FileField(required=False)
    thumbnail = serializers.FileField(required=False)
    remove_thumbnail = serializers.BooleanField(required=False)
    duration_seconds = serializers.IntegerField(required=False)
    description = serializers.CharField(required=False, allow_blank=True, max_length=4000)
    status = serializers.CharField(required=False, max_length=12)
    downloadable = serializers.BooleanField(required=False)


class MoveInput(serializers.Serializer):
    direction = serializers.ChoiceField(choices=["up", "down"])


class EnrolInput(serializers.Serializer):
    student_id = serializers.IntegerField(min_value=1)
    method = serializers.CharField(max_length=8)
    amount_minor = serializers.IntegerField(required=False, default=0, min_value=0)
    billing_method = serializers.CharField(required=False, allow_blank=True, default="", max_length=20)
    paid_on = serializers.DateField(required=False, allow_null=True, default=None)
    reference = serializers.CharField(required=False, allow_blank=True, default="", max_length=120)
    transaction_number = serializers.CharField(required=False, allow_blank=True, default="", max_length=200)
    notes = serializers.CharField(required=False, allow_blank=True, default="", max_length=4000)


class EnrolmentPatch(serializers.Serializer):
    notes = serializers.CharField(required=False, allow_blank=True, max_length=4000)
    transaction_number = serializers.CharField(required=False, allow_blank=True, max_length=200)
    watched_video_ids = serializers.ListField(
        child=serializers.IntegerField(min_value=1), required=False, max_length=2000
    )


def playlist_data(p: Playlist) -> dict:
    return {
        "id": p.pk,
        "title": p.title,
        "slug": p.slug,
        "description": p.description,
        "code": p.code,
        "content_language": p.content_language,
        "price_minor": p.price_minor,
        "discount_minor": p.discount_minor,
        "currency": p.currency,
        "content": p.content,
        "terms": p.terms,
        "is_published": p.is_published,
        "certificate": p.certificate,
        "app_only": p.app_only,
        "thumbnail_url": _url(p.thumbnail),
        "intro_video_url": _url(p.intro_video),
        "lessons": getattr(p, "lessons", 0),
        "seconds": getattr(p, "seconds", 0),
        "enrolments": getattr(p, "enrolment_count", 0),
    }


def video_data(v: PlaylistVideo) -> dict:
    return {
        "id": v.pk,
        "playlist": v.playlist_id,
        "code": v.code,
        "title": v.title,
        "slug": v.slug,
        "kind": v.kind,
        "url": v.url,
        "embed_provider": v.embed_provider,
        "embed_id": v.embed_id,
        "has_file": bool(v.file),
        "thumbnail_url": _url(v.thumbnail),
        "duration_seconds": v.duration_seconds,
        "position": v.position,
        "description": v.description,
        "status": v.status,
        "downloadable": v.downloadable,
    }


def enrolment_data(e: Enrolment, total: int) -> dict:
    return {
        "id": e.pk,
        "playlist": e.playlist_id,
        "student": {"id": e.student.user_id, "full_name": e.student.user.full_name},
        "amount_minor": e.amount_minor,
        "currency": e.currency,
        "method": e.method,
        "transaction_number": e.transaction_number,
        "payment_id": e.payment_id,
        "notes": e.notes,
        "status": e.status,
        "enrolled_at": e.enrolled_at.isoformat(),
        "revoked_at": e.revoked_at.isoformat() if e.revoked_at else None,
        "watched_video_ids": sorted(w.video_id for w in e.watched.all()),
        "progress": {"watched": getattr(e, "watched_count", 0), "total": total},
    }
```

`backend/etqan/recorded/api/views.py` (playlists and videos; enrolments added in Task 7):

```python
from django.http import Http404
from rest_framework import status
from rest_framework.parsers import JSONParser
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.platform.exceptions import NotFoundError
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.recorded import services
from etqan.recorded.api import serializers as s

FEATURE = "recorded_courses"
OFFICE = [HasCode, FeatureOn]
PARSERS = [MultiPartParser, JSONParser]


def _flag(params, key) -> bool | None:
    value = params.get(key, "")
    return {"true": True, "false": False}.get(value)


def _playlist(pk):
    try:
        return services.get_playlist(pk)
    except NotFoundError:
        raise Http404 from None


def _video(pk):
    try:
        return services.get_video(pk)
    except NotFoundError:
        raise Http404 from None


def _valid(serializer_class, request, **kwargs) -> dict:
    data = serializer_class(data=request.data, **kwargs)
    data.is_valid(raise_exception=True)
    return dict(data.validated_data)


class PlaylistListView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"GET": "playlist.view_any", "POST": "playlist.create"}
    parser_classes = PARSERS

    def get(self, request):
        p = request.query_params
        qs = services.filter_playlists(
            services.playlists_queryset(),
            published=_flag(p, "published"),
            language=p.get("language", ""),
            has_discount=_flag(p, "has_discount"),
            q=p.get("q", ""),
        )
        return Response([s.playlist_data(row) for row in qs])

    def post(self, request):
        v = _valid(s.PlaylistInput, request)
        v.pop("remove_intro", None)
        row = services.create_playlist(
            title=v.pop("title", ""),
            slug=v.pop("slug", ""),
            description=v.pop("description", ""),
            code=v.pop("code", ""),
            content_language=v.pop("content_language", ""),
            terms=v.pop("terms", ""),
            thumbnail=v.pop("thumbnail", None),
            **v,
        )
        return Response(
            s.playlist_data(services.get_playlist(row.pk)),
            status=status.HTTP_201_CREATED,
        )


class PlaylistDetailView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {
        "GET": "playlist.view",
        "PATCH": "playlist.update",
        "DELETE": "playlist.delete",
    }
    parser_classes = PARSERS

    def get(self, request, pk):
        return Response(s.playlist_data(_playlist(pk)))

    def patch(self, request, pk):
        row = _playlist(pk)
        services.update_playlist(row, **_valid(s.PlaylistInput, request, partial=True))
        return Response(s.playlist_data(services.get_playlist(pk)))

    def delete(self, request, pk):
        services.delete_playlist(_playlist(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class VideoListView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {
        "GET": "playlist_video.view_any",
        "POST": "playlist_video.create",
    }
    parser_classes = PARSERS

    def get(self, request, pk):
        _playlist(pk)
        return Response([s.video_data(v) for v in services.videos_of(pk)])

    def post(self, request, pk):
        row = _playlist(pk)
        v = _valid(s.VideoInput, request)
        v.pop("remove_thumbnail", None)
        video = services.create_video(
            row,
            code=v.pop("code", ""),
            title=v.pop("title", ""),
            slug=v.pop("slug", ""),
            kind=v.pop("kind", ""),
            duration_seconds=v.pop("duration_seconds", 0),
            **v,
        )
        return Response(s.video_data(video), status=status.HTTP_201_CREATED)


class VideoDetailView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {
        "PATCH": "playlist_video.update",
        "DELETE": "playlist_video.delete",
    }
    parser_classes = PARSERS

    def patch(self, request, pk):
        video = services.update_video(
            _video(pk), **_valid(s.VideoInput, request, partial=True)
        )
        return Response(s.video_data(video))

    def delete(self, request, pk):
        services.delete_video(_video(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class VideoMoveView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"POST": "playlist_video.reorder"}

    def post(self, request, pk):
        v = _valid(s.MoveInput, request)
        services.move_video(_video(pk), v["direction"])
        return Response(status=status.HTTP_204_NO_CONTENT)
```

Note: `create_video` with `duration_seconds=0` from a missing field raises the service's 400 on `duration_seconds`. `int("")` never happens because DRF already parsed it.

`backend/etqan/recorded/api/urls.py`:

```python
from django.urls import path

from etqan.recorded.api import views

urlpatterns = [
    path("playlists/", views.PlaylistListView.as_view()),
    path("playlists/<int:pk>/", views.PlaylistDetailView.as_view()),
    path("playlists/<int:pk>/videos/", views.VideoListView.as_view()),
    path("videos/<int:pk>/", views.VideoDetailView.as_view()),
    path("videos/<int:pk>/move/", views.VideoMoveView.as_view()),
]
```

`backend/config/api_router.py`, under `# ── phase B7 ──`:

```python
    path("recorded/", include("etqan.recorded.api.urls")),
```

`backend/etqan/access/registry.py`, under `# ── phase B7 ──` in `RESOURCES` (A-15; this task's routes use the playlist and video codes, Task 7 the enrolment ones; all three resources go in now, and the `in_use` test passes only after Task 7):

```python
    Resource(
        "playlist",
        "Recorded courses",
        "الدورات المسجلة",
        ("view", "view_any", "create", "update", "delete"),
    ),
    Resource(
        "playlist_video",
        "Recorded course videos",
        "فيديوهات الدورات المسجلة",
        ("view_any", "create", "update", "delete", "reorder"),
    ),
    Resource(
        "rc_enrolment",
        "Recorded course enrolments",
        "اشتراكات الدورات المسجلة",
        ("view", "view_any", "create", "update", "delete"),
    ),
```

`backend/etqan/access/tests/test_routes.py`:
- In `ROUTES`, append:

```python
    # Phase B7, slice B7a
    ("GET", "/api/v1/recorded/playlists/", "playlist.view_any"),
    ("POST", "/api/v1/recorded/playlists/", "playlist.create"),
    ("GET", f"/api/v1/recorded/playlists/{N}/", "playlist.view"),
    ("PATCH", f"/api/v1/recorded/playlists/{N}/", "playlist.update"),
    ("DELETE", f"/api/v1/recorded/playlists/{N}/", "playlist.delete"),
    ("GET", f"/api/v1/recorded/playlists/{N}/videos/", "playlist_video.view_any"),
    ("POST", f"/api/v1/recorded/playlists/{N}/videos/", "playlist_video.create"),
    ("PATCH", f"/api/v1/recorded/videos/{N}/", "playlist_video.update"),
    ("DELETE", f"/api/v1/recorded/videos/{N}/", "playlist_video.delete"),
    ("POST", f"/api/v1/recorded/videos/{N}/move/", "playlist_video.reorder"),
```

- In `FEATURES`, append:

```python
    # Phase B7, slice B7a
    **dict.fromkeys(
        (
            ("GET", "/api/v1/recorded/playlists/"),
            ("POST", "/api/v1/recorded/playlists/"),
            ("GET", f"/api/v1/recorded/playlists/{N}/"),
            ("PATCH", f"/api/v1/recorded/playlists/{N}/"),
            ("DELETE", f"/api/v1/recorded/playlists/{N}/"),
            ("GET", f"/api/v1/recorded/playlists/{N}/videos/"),
            ("POST", f"/api/v1/recorded/playlists/{N}/videos/"),
            ("PATCH", f"/api/v1/recorded/videos/{N}/"),
            ("DELETE", f"/api/v1/recorded/videos/{N}/"),
            ("POST", f"/api/v1/recorded/videos/{N}/move/"),
        ),
        "recorded_courses",
    ),
```

- In `FEATURE_WORDS`, append `"/recorded/": "recorded_courses",  # B7a`.

- [ ] **Step 4: Run** — `B pytest etqan/recorded etqan/access -q`. Expected: recorded PASS; `test_every_code_in_the_table_is_in_the_registry_and_in_use` FAILS on the `rc_enrolment.*` codes until Task 7. This is expected; do not weaken the test.
- [ ] **Step 5: Commit** — `git -C backend add etqan/recorded config/api_router.py etqan/access && git -C backend commit -m "feat(recorded): B7a office API for courses and videos" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 7: The office API for enrolments (A-8…A-10, A-9's `payment.create`)

**Files:**
- Modify: `backend/etqan/recorded/api/views.py`, `api/urls.py`, `backend/etqan/access/tests/test_routes.py`
- Create: `backend/etqan/recorded/tests/test_api_enrolments.py`

**Interfaces:**
- Produces routes: `recorded/playlists/<pk>/enrolments/` (GET paginated with `StandardPagination`, filters `method`, `status`; POST), `recorded/enrolments/<pk>/` (GET, PATCH, DELETE), `recorded/enrolments/<pk>/revoke/`, `…/restore/` (POST). The enrolment JSON comes from `enrolment_data` (Task 6).
- A manual enrolment by a staff account without `payment.create` → **403** `ForbiddenError` on field `method` (body `{"method": ["…"]}`; the platform's ForbiddenError carries no `code`, so the spec's `recorded.payment_code_required` is the message's meaning, not a body code).

- [ ] **Step 1: Write the failing tests**

```python
import pytest

from etqan.recorded import services
from etqan.recorded.tests.conftest import png

pytestmark = pytest.mark.django_db


@pytest.fixture
def pl(people):
    pl = services.create_playlist(
        title="T", slug="t", description="d", code="T", content_language="ar",
        terms="t", thumbnail=png(), currency="USD",
    )
    services.create_video(
        pl, code="A", title="a", slug="a", kind="link", url="https://x.test/a",
        duration_seconds=60, status="published",
    )
    return pl


def url(pl):
    return f"/api/v1/recorded/playlists/{pl.pk}/enrolments/"


def test_admin_manual_enrolment_and_list(api_for, people, pl):
    admin = api_for("admin")
    resp = admin.post(
        url(pl),
        {"student_id": people.student.pk, "method": "manual", "amount_minor": 1500,
         "billing_method": "cash", "transaction_number": "T1"},
        format="json",
    )
    assert resp.status_code == 201, resp.content
    body = resp.json()
    assert body["student"] == {"id": people.student.pk, "full_name": "Yusuf"}
    assert body["payment_id"] is not None
    assert body["progress"] == {"watched": 0, "total": 1}
    listed = admin.get(url(pl), {"status": "active"}).json()
    assert listed["count"] == 1 and listed["results"][0]["id"] == body["id"]
    assert admin.get(url(pl), {"method": "free"}).json()["count"] == 0


def test_staff_needs_payment_create_for_manual(staff_for, people, pl):
    staff = staff_for("rc_enrolment.create")
    body = {"student_id": people.student.pk, "method": "manual",
            "amount_minor": 100, "billing_method": "cash"}
    resp = staff.post(url(pl), body, format="json")
    assert (resp.status_code, list(resp.json())) == (403, ["method"])
    free = {"student_id": people.student.pk, "method": "free"}
    assert staff.post(url(pl), free, format="json").status_code == 201
    paid = staff_for("rc_enrolment.create", "payment.create")
    assert paid.post(url(pl), {**body, "student_id": people.other.pk},
                     format="json").status_code == 201


def test_patch_revoke_restore_delete(api_for, people, pl):
    admin = api_for("admin")
    e = admin.post(url(pl), {"student_id": people.student.pk, "method": "free"},
                   format="json").json()
    base = f"/api/v1/recorded/enrolments/{e['id']}/"
    video = pl.videos.get()
    resp = admin.patch(base, {"notes": "n", "watched_video_ids": [video.pk]},
                       format="json")
    assert resp.json()["watched_video_ids"] == [video.pk]
    assert resp.json()["progress"] == {"watched": 1, "total": 1}
    assert admin.post(base + "revoke/").json()["status"] == "revoked"
    assert admin.post(base + "restore/").json()["status"] == "active"
    resp = admin.delete(base)
    assert (resp.status_code, resp.json()["code"]) == (409, "recorded.enrolment_in_use")
    admin.patch(base, {"watched_video_ids": []}, format="json")
    assert admin.delete(base).status_code == 204


def test_deactivated_student_manual_is_400_on_student(api_for, people, pl):
    from etqan.identity import services as identity_services  # noqa: PLC0415

    admin = api_for("admin")
    identity_services.deactivate(people.student, by=admin.user)
    resp = admin.post(
        url(pl),
        {"student_id": people.student.pk, "method": "manual", "amount_minor": 100,
         "billing_method": "cash"},
        format="json",
    )
    assert (resp.status_code, list(resp.json())) == (400, ["student"])


def test_duplicate_is_409(api_for, people, pl):
    admin = api_for("admin")
    body = {"student_id": people.student.pk, "method": "free"}
    admin.post(url(pl), body, format="json")
    resp = admin.post(url(pl), body, format="json")
    assert (resp.status_code, resp.json()["code"]) == (409, "recorded.already_enrolled")
```

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/recorded/tests/test_api_enrolments.py -q` → FAIL (404).

- [ ] **Step 3: Implement** — append to `api/views.py`:

```python
from etqan.platform.exceptions import ForbiddenError
from etqan.platform.pagination import StandardPagination
from etqan.platform.permissions import codes_of
from etqan.platform.permissions import role_of


def _enrolment(pk):
    try:
        return services.get_enrolment(pk)
    except NotFoundError:
        raise Http404 from None


def _enrolment_json(row) -> dict:
    total = services.progress(row).total
    return s.enrolment_data(row, total)


class EnrolmentListView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"GET": "rc_enrolment.view_any", "POST": "rc_enrolment.create"}

    def get(self, request, pk):
        row = _playlist(pk)
        qs = services.filter_enrolments(
            services.enrolments_queryset().filter(playlist=row),
            method=request.query_params.get("method", ""),
            status=request.query_params.get("status", ""),
        )
        paginator = StandardPagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        return paginator.get_paginated_response(
            [s.enrolment_data(e, row.lessons) for e in page]
        )

    def post(self, request, pk):
        row = _playlist(pk)
        v = _valid(s.EnrolInput, request)
        if (
            v["method"] == "manual"
            and role_of(request.user) != "admin"
            and "payment.create" not in codes_of(request.user)
        ):
            raise ForbiddenError(
                "Recording the payment needs the payment.create permission.",
                field="method",
            )
        e = services.enrol_by_office(
            playlist=row,
            student_user_id=v["student_id"],
            method=v["method"],
            amount_minor=v["amount_minor"],
            billing_method=v["billing_method"],
            paid_on=v["paid_on"],
            reference=v["reference"],
            transaction_number=v["transaction_number"],
            notes=v["notes"],
            by=request.user,
        )
        return Response(
            _enrolment_json(services.get_enrolment(e.pk)),
            status=status.HTTP_201_CREATED,
        )


class EnrolmentDetailView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {
        "GET": "rc_enrolment.view",
        "PATCH": "rc_enrolment.update",
        "DELETE": "rc_enrolment.delete",
    }

    def get(self, request, pk):
        return Response(_enrolment_json(_enrolment(pk)))

    def patch(self, request, pk):
        services.update_enrolment(
            _enrolment(pk), **_valid(s.EnrolmentPatch, request, partial=True)
        )
        return Response(_enrolment_json(_enrolment(pk)))

    def delete(self, request, pk):
        services.delete_enrolment(_enrolment(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class EnrolmentRevokeView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"POST": "rc_enrolment.update"}

    def post(self, request, pk):
        services.revoke(_enrolment(pk), by=request.user)
        return Response(_enrolment_json(_enrolment(pk)))


class EnrolmentRestoreView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"POST": "rc_enrolment.update"}

    def post(self, request, pk):
        services.restore(_enrolment(pk), by=request.user)
        return Response(_enrolment_json(_enrolment(pk)))
```

`api/urls.py` gains:

```python
    path("playlists/<int:pk>/enrolments/", views.EnrolmentListView.as_view()),
    path("enrolments/<int:pk>/", views.EnrolmentDetailView.as_view()),
    path("enrolments/<int:pk>/revoke/", views.EnrolmentRevokeView.as_view()),
    path("enrolments/<int:pk>/restore/", views.EnrolmentRestoreView.as_view()),
```

`test_routes.py`: add to the B7a `ROUTES` block

```python
    ("GET", f"/api/v1/recorded/playlists/{N}/enrolments/", "rc_enrolment.view_any"),
    ("POST", f"/api/v1/recorded/playlists/{N}/enrolments/", "rc_enrolment.create"),
    ("GET", f"/api/v1/recorded/enrolments/{N}/", "rc_enrolment.view"),
    ("PATCH", f"/api/v1/recorded/enrolments/{N}/", "rc_enrolment.update"),
    ("DELETE", f"/api/v1/recorded/enrolments/{N}/", "rc_enrolment.delete"),
    ("POST", f"/api/v1/recorded/enrolments/{N}/revoke/", "rc_enrolment.update"),
    ("POST", f"/api/v1/recorded/enrolments/{N}/restore/", "rc_enrolment.update"),
```

and the same seven `(method, path)` pairs to the B7a `FEATURES` block.

- [ ] **Step 4: Run** — `B pytest etqan/recorded etqan/access -q` → PASS, including the `in_use` equality test.
- [ ] **Step 5: Commit** — `git -C backend add etqan/recorded etqan/access/tests/test_routes.py && git -C backend commit -m "feat(recorded): B7a office API for enrolments" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 8: Lesson files — scoping, signed redirect, ranged streaming (B7-8, A-14)

**Files:**
- Create: `backend/etqan/recorded/services/scope.py`, `services/serving.py`, `api/file_views.py`, `tests/test_serving.py`, `tests/test_api_file.py`
- Modify: `services/__init__.py`, `api/urls.py`, `access/tests/test_routes.py`

**Interfaces:**
- Produces:
  - `scope.can_watch(user, video) -> bool`: the user is a student with an active enrolment in the video's playlist, the playlist is published and the video is published.
  - `serving.serve_video(request, video, *, download: bool) -> HttpResponse`: 302 to `files.private_storage().url(name, parameters={"ResponseContentDisposition": …}, expire=600)` only when `settings.PRIVATE_STORAGE_SHARED_WITH_PUBLIC is False`; otherwise a stream (200, or 206 for one `Range: bytes=a-b`, or 416).
  - Route `recorded/videos/<pk>/file/` with `GET`, code `playlist_video.view_any`.

- [ ] **Step 1: Write the failing tests**

`tests/test_serving.py`:

```python
import pytest
from django.test import RequestFactory
from django.test import override_settings

from etqan.recorded import files
from etqan.recorded import services
from etqan.recorded.services.serving import serve_video
from etqan.recorded.tests.conftest import mp4
from etqan.recorded.tests.conftest import png

pytestmark = pytest.mark.django_db
BODY = bytes(range(256)) * 4  # 1024 bytes; starts with no ftyp, so prefix one
DATA = b"\x00\x00\x00\x18ftypmp42" + BODY


@pytest.fixture
def video():
    pl = services.create_playlist(
        title="T", slug="t", description="d", code="T", content_language="ar",
        terms="t", thumbnail=png(), currency="USD",
    )
    return services.create_video(
        pl, code="F", title="f", slug="lesson", kind="file", file=mp4(body=DATA),
        duration_seconds=60, status="published",
    )


def get(headers=None):
    return RequestFactory().get("/x", headers=headers or {})


def body(resp) -> bytes:
    return b"".join(resp.streaming_content)


def test_full_stream_is_inline(video):
    resp = serve_video(get(), video, download=False)
    assert resp.status_code == 200
    assert resp["Content-Disposition"].startswith("inline")
    assert resp["Accept-Ranges"] == "bytes"
    assert resp["X-Content-Type-Options"] == "nosniff"
    assert resp["Cache-Control"] == "private, no-store"
    assert body(resp) == DATA


def test_download_is_attachment(video):
    resp = serve_video(get(), video, download=True)
    assert resp["Content-Disposition"].startswith("attachment")


@pytest.mark.parametrize(
    ("header", "start", "end"),
    [("bytes=0-9", 0, 9), ("bytes=10-", 10, len(DATA) - 1),
     ("bytes=-5", len(DATA) - 5, len(DATA) - 1), ("bytes=5-99999", 5, len(DATA) - 1)],
)
def test_range_requests(video, header, start, end):
    resp = serve_video(get({"Range": header}), video, download=False)
    assert resp.status_code == 206
    assert resp["Content-Range"] == f"bytes {start}-{end}/{len(DATA)}"
    assert resp["Content-Length"] == str(end - start + 1)
    assert body(resp) == DATA[start : end + 1]


@pytest.mark.parametrize("header", ["bytes=99999-", "bytes=9-3"])
def test_unsatisfiable_range_is_416(video, header):
    resp = serve_video(get({"Range": header}), video, download=False)
    assert resp.status_code == 416
    assert resp["Content-Range"] == f"bytes */{len(DATA)}"


def test_multi_range_falls_back_to_full(video):
    resp = serve_video(get({"Range": "bytes=0-1,4-5"}), video, download=False)
    assert resp.status_code == 200


class FakeS3:
    def __init__(self):
        self.calls = []

    def url(self, name, parameters=None, expire=None):
        self.calls.append((name, parameters, expire))
        return "https://signed.example/x?sig=1"


def test_redirect_only_with_a_dedicated_private_bucket(video, monkeypatch):
    fake = FakeS3()
    monkeypatch.setattr(files, "private_storage", lambda: fake)
    with override_settings(PRIVATE_STORAGE_SHARED_WITH_PUBLIC=False):
        resp = serve_video(get(), video, download=True)
    assert (resp.status_code, resp["Location"]) == (302, "https://signed.example/x?sig=1")
    assert resp["Cache-Control"] == "private, no-store"
    name, params, expire = fake.calls[0]
    assert name == video.file.name and expire == 600
    assert params["ResponseContentDisposition"].startswith("attachment")
    with override_settings(PRIVATE_STORAGE_SHARED_WITH_PUBLIC=True):
        assert serve_video(get(), video, download=False).status_code == 200
```

`tests/test_api_file.py`:

```python
import pytest

from etqan.recorded import services
from etqan.recorded.tests.conftest import as_user
from etqan.recorded.tests.conftest import mp4
from etqan.recorded.tests.conftest import png

pytestmark = pytest.mark.django_db


@pytest.fixture
def lesson(people, api_for):
    pl = services.create_playlist(
        title="T", slug="t", description="d", code="T", content_language="ar",
        terms="t", thumbnail=png(), currency="USD", is_published=True,
    )
    v = services.create_video(
        pl, code="F", title="f", slug="f", kind="file", file=mp4(),
        duration_seconds=60, status="published", downloadable=False,
    )
    e = services.enrol_by_office(
        playlist=pl, student_user_id=people.student.pk, method="free",
        amount_minor=0, by=api_for("admin").user,
    )
    return pl, v, e


def path(v, download=False):
    return f"/api/v1/recorded/videos/{v.pk}/file/" + ("?download=1" if download else "")


def test_enrolled_student_streams_inline(people, lesson):
    pl, v, e = lesson
    resp = as_user(people.student).get(path(v))
    assert resp.status_code == 200
    assert resp["Content-Disposition"].startswith("inline")


def test_download_only_when_downloadable(people, lesson):
    pl, v, e = lesson
    client = as_user(people.student)
    assert client.get(path(v, download=True)).status_code == 404
    services.update_video(v, downloadable=True)
    assert client.get(path(v, download=True))["Content-Disposition"].startswith(
        "attachment"
    )


def test_file_refused_when_not_watchable(people, lesson, api_for):
    pl, v, e = lesson
    client = as_user(people.student)
    services.update_video(v, status="hidden")
    assert client.get(path(v)).status_code == 404
    services.update_video(v, status="published")
    services.update_playlist(pl, is_published=False)
    assert client.get(path(v)).status_code == 404
    services.update_playlist(pl, is_published=True)
    services.revoke(e, by=api_for("admin").user)
    assert client.get(path(v)).status_code == 404


def test_others(people, lesson, api_for, staff_for):
    pl, v, e = lesson
    assert as_user(people.other).get(path(v)).status_code == 404
    assert as_user(people.teacher).get(path(v)).status_code == 404
    assert as_user(people.parent).get(path(v)).status_code == 403
    assert staff_for().get(path(v)).status_code == 403
    services.update_video(v, status="draft")
    assert staff_for("playlist_video.view_any").get(path(v)).status_code == 200
    assert api_for("admin").get(path(v)).status_code == 200


def test_link_video_has_no_file(people, lesson, api_for):
    pl, v, e = lesson
    link = services.create_video(
        pl, code="L", title="l", slug="l", kind="link", url="https://x.test/a",
        duration_seconds=60, status="published",
    )
    assert api_for("admin").get(path(link)).status_code == 404


def test_off_is_404(people, lesson, set_features):
    pl, v, e = lesson
    set_features(recorded_courses=False)
    assert as_user(people.student).get(path(v)).status_code == 404
```

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/recorded/tests/test_serving.py etqan/recorded/tests/test_api_file.py -q` → FAIL.

- [ ] **Step 3: Implement**

`services/scope.py` (`can_watch` here; Task 9 adds `my_enrolments` and `my_playlist`):

```python
"""Spec A-13, A-14: what a student or parent may see of recorded courses."""

from etqan.platform.permissions import role_of
from etqan.recorded.models import Enrolment
from etqan.recorded.models import PlaylistVideo


def can_watch(user, video) -> bool:
    if role_of(user) != "student":
        return False
    return (
        video.status == PlaylistVideo.Status.PUBLISHED
        and video.playlist.is_published
        and Enrolment.objects.filter(
            playlist_id=video.playlist_id,
            student__user_id=user.pk,
            status=Enrolment.Status.ACTIVE,
        ).exists()
    )
```

`services/serving.py`:

```python
"""Spec B7-8: a lesson file. With a dedicated private S3 bucket, a 302 to a
signed URL (S3 then serves ranges). Otherwise, including local storage and
the shared-bucket fallback, where a URL must never be handed out, a stream
with single-range support."""

import re

from django.conf import settings
from django.http import HttpResponse
from django.http import HttpResponseRedirect
from django.http import StreamingHttpResponse

from etqan.recorded import files

SIGNED_FOR = 600
CHUNK = 64 * 1024
RANGE = re.compile(r"^bytes=(\d*)-(\d*)$")


def _disposition(video, download: bool) -> str:
    kind = "attachment" if download else "inline"
    return f'{kind}; filename="{video.slug}.mp4"'


def _headers(resp, video, download):
    resp["Content-Disposition"] = _disposition(video, download)
    resp["X-Content-Type-Options"] = "nosniff"
    resp["Cache-Control"] = "private, no-store"
    resp["Accept-Ranges"] = "bytes"
    return resp


def _chunks(handle, start: int, length: int):
    try:
        handle.seek(start)
        left = length
        while left > 0:
            data = handle.read(min(CHUNK, left))
            if not data:
                break
            left -= len(data)
            yield data
    finally:
        handle.close()


def _bounds(header: str, size: int) -> tuple[int, int] | None | bool:
    """(start, end) for one satisfiable range; None for no or an unusable
    header (serve it all); False for an unsatisfiable one (416)."""
    match = RANGE.fullmatch(header.strip())
    if not match or (match[1] == "" and match[2] == ""):
        return None
    if match[1] == "":
        start, end = max(size - int(match[2]), 0), size - 1
    else:
        start = int(match[1])
        end = min(int(match[2]), size - 1) if match[2] else size - 1
    if start >= size or start > end:
        return False
    return start, end


def serve_video(request, video, *, download: bool):
    name = video.file.name
    if getattr(settings, "PRIVATE_STORAGE_SHARED_WITH_PUBLIC", True) is False:
        url = files.private_storage().url(
            name,
            parameters={"ResponseContentDisposition": _disposition(video, download)},
            expire=SIGNED_FOR,
        )
        resp = HttpResponseRedirect(url)
        resp["Cache-Control"] = "private, no-store"
        return resp
    size = video.file.size
    bounds = _bounds(request.headers.get("Range", ""), size)
    if bounds is False:
        resp = HttpResponse(status=416)
        resp["Content-Range"] = f"bytes */{size}"
        return resp
    start, end = bounds or (0, size - 1)
    length = end - start + 1
    resp = StreamingHttpResponse(
        _chunks(video.file.open("rb"), start, length),
        status=206 if bounds else 200,
        content_type="video/mp4",
    )
    resp["Content-Length"] = str(length)
    if bounds:
        resp["Content-Range"] = f"bytes {start}-{end}/{size}"
    return _headers(resp, video, download)
```

`api/file_views.py`:

```python
from django.http import Http404
from rest_framework.views import APIView

from etqan.platform.exceptions import ForbiddenError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.platform.permissions import ReadOnly
from etqan.platform.permissions import ReadsOwn
from etqan.platform.permissions import is_office
from etqan.platform.permissions import role_of
from etqan.recorded import services


class VideoFileView(APIView):
    """A-14: the office (with the code), or the enrolled student; a parent
    may see the course but never open a lesson (403); anyone else 404."""

    feature = "recorded_courses"
    permission_classes = [HasCode | (ReadOnly & ReadsOwn), FeatureOn]
    permission_codes = {"GET": "playlist_video.view_any"}

    def get(self, request, pk):
        try:
            video = services.get_video(pk)
        except NotFoundError:
            raise Http404 from None
        if role_of(request.user) == "parent":
            raise ForbiddenError("A parent cannot open a lesson.")
        if not is_office(request.user) and not services.can_watch(request.user, video):
            raise Http404
        if not video.file:
            raise Http404
        download = request.query_params.get("download") == "1"
        if download and not video.downloadable:
            raise Http404
        return services.serve_video(request, video, download=download)
```

Export `can_watch` and `serve_video` from `services/__init__.py`. Add to `api/urls.py`:

```python
from etqan.recorded.api import file_views
    path("videos/<int:pk>/file/", file_views.VideoFileView.as_view()),
```

`test_routes.py`: add `("GET", f"/api/v1/recorded/videos/{N}/file/", "playlist_video.view_any"),` to the B7a `ROUTES` block, and the pair to the B7a `FEATURES` block.

Note: `ATOMIC_REQUESTS` wraps the view; a streamed body is read after the view returns. That is safe because the file handle does not depend on the transaction. `FileResponse`'s precedent (`learning/api/params.py`) is the same.

- [ ] **Step 4: Run** — `B pytest etqan/recorded etqan/access -q` → PASS.
- [ ] **Step 5: Commit** — `git -C backend add etqan/recorded etqan/access/tests/test_routes.py && git -C backend commit -m "feat(recorded): B7a lesson files with signed redirect or ranged stream" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 9: The student and parent API (A-11, A-13)

**Files:**
- Modify: `services/scope.py`, `services/__init__.py`, `api/serializers.py`, `api/urls.py`, `access/tests/test_routes.py` (SELF_SERVICE)
- Create: `api/my_views.py`, `tests/test_api_my.py`

**Interfaces:**
- Produces:
  - `scope.my_enrolments(user, student_user_id: int | None) -> list[Enrolment]`: a student gets their own; a parent passes a child's user id (missing or not their child → `NotFoundError`). Only active enrolments in published playlists, annotated `watched_count`.
  - `scope.my_playlist(user, playlist_id, student_user_id) -> tuple[Enrolment, list[PlaylistVideo], set[int]]`: published videos and the watched ids. NotFoundError otherwise.
  - Routes (`IsStudent | IsParent`, `FeatureOn`, listed in `SELF_SERVICE`): `GET recorded/my/?student=<id>`, `GET recorded/my/<playlist id>/?student=<id>`, `PUT|DELETE recorded/my/videos/<id>/watched/` (student only; parent 403).
  - JSON: `my/` → `[{enrolment_id, playlist: {id, title, thumbnail_url, content_language}, progress: {watched, total}}]`. `my/<id>/` → `{enrolment_id, playlist: {id, title, description, content, terms, thumbnail_url, content_language}, videos: [{id, title, description, kind, url, embed_provider, embed_id, has_file, downloadable, duration_seconds, thumbnail_url, watched}], progress}`. Watched PUT and DELETE → `{progress}`.

- [ ] **Step 1: Write the failing tests** (`tests/test_api_my.py`)

```python
import pytest

from etqan.recorded import services
from etqan.recorded.tests.conftest import as_user
from etqan.recorded.tests.conftest import png

pytestmark = pytest.mark.django_db
M = "/api/v1/recorded/my/"


@pytest.fixture
def course(people, api_for):
    pl = services.create_playlist(
        title="T", slug="t", description="d", code="T", content_language="ar",
        terms="terms", thumbnail=png(), currency="USD", is_published=True,
    )
    pub = services.create_video(
        pl, code="A", title="a", slug="a", kind="link",
        url="https://youtu.be/dQw4w9WgXcQ", duration_seconds=60, status="published",
    )
    services.create_video(
        pl, code="D", title="d", slug="d", kind="link", url="https://x.test/d",
        duration_seconds=60, status="draft",
    )
    services.enrol_by_office(
        playlist=pl, student_user_id=people.student.pk, method="free",
        amount_minor=0, by=api_for("admin").user,
    )
    return pl, pub


def test_student_lists_and_opens_own(people, course):
    pl, pub = course
    client = as_user(people.student)
    listed = client.get(M).json()
    assert listed == [{
        "enrolment_id": listed[0]["enrolment_id"],
        "playlist": {"id": pl.pk, "title": "T", "thumbnail_url": pl.thumbnail.url,
                     "content_language": "ar"},
        "progress": {"watched": 0, "total": 1},
    }]
    detail = client.get(f"{M}{pl.pk}/").json()
    assert [v["id"] for v in detail["videos"]] == [pub.pk]
    assert detail["videos"][0]["embed_id"] == "dQw4w9WgXcQ"
    assert detail["playlist"]["terms"] == "terms"
    resp = client.put(f"{M}videos/{pub.pk}/watched/")
    assert resp.json() == {"progress": {"watched": 1, "total": 1}}
    assert client.get(f"{M}{pl.pk}/").json()["videos"][0]["watched"] is True
    assert client.delete(f"{M}videos/{pub.pk}/watched/").json()["progress"]["watched"] == 0


def test_unpublished_or_revoked_hidden(people, course, api_for):
    pl, pub = course
    client = as_user(people.student)
    services.update_playlist(pl, is_published=False)
    assert client.get(M).json() == []
    assert client.get(f"{M}{pl.pk}/").status_code == 404
    services.update_playlist(pl, is_published=True)
    services.revoke(services.enrolment_for(people.student.pk, pl.pk),
                    by=api_for("admin").user)
    assert client.get(f"{M}{pl.pk}/").status_code == 404


def test_other_student_gets_404(people, course):
    pl, pub = course
    client = as_user(people.other)
    assert client.get(M).json() == []
    assert client.get(f"{M}{pl.pk}/").status_code == 404
    assert client.put(f"{M}videos/{pub.pk}/watched/").status_code == 404


def test_parent_reads_child_but_cannot_write(people, course):
    pl, pub = course
    client = as_user(people.parent)
    assert client.get(M, {"student": people.student.pk}).json()[0]["playlist"]["id"] == pl.pk
    assert client.get(f"{M}{pl.pk}/", {"student": people.student.pk}).status_code == 200
    assert client.get(M, {"student": people.other.pk}).status_code == 404
    assert client.get(M).status_code == 404
    assert client.put(f"{M}videos/{pub.pk}/watched/").status_code == 403


def test_office_and_teacher_refused(people, course, api_for):
    assert api_for("admin").get(M).status_code == 403
    assert as_user(people.teacher).get(M).status_code == 403
```

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/recorded/tests/test_api_my.py -q` → FAIL.

- [ ] **Step 3: Implement**

Append to `services/scope.py`:

```python
from django.db.models import Count
from django.db.models import Q

from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError


def _student_id(user, student_user_id) -> int:
    role = role_of(user)
    if role == "student":
        return user.pk
    if role == "parent" and student_user_id is not None:
        if identity_services.is_parent_of(user.pk, student_user_id):
            return student_user_id
    raise NotFoundError("Student", student_user_id)


def _visible():
    return Enrolment.objects.filter(
        status=Enrolment.Status.ACTIVE, playlist__is_published=True
    ).select_related("playlist")


def my_enrolments(user, student_user_id=None) -> list:
    sid = _student_id(user, student_user_id)
    return list(
        _visible()
        .filter(student__user_id=sid)
        .annotate(
            watched_count=Count(
                "watched",
                filter=Q(watched__video__status=PlaylistVideo.Status.PUBLISHED),
                distinct=True,
            )
        )
        .order_by("-enrolled_at")
    )


def my_playlist(user, playlist_id, student_user_id=None):
    sid = _student_id(user, student_user_id)
    enrolment = _visible().filter(student__user_id=sid, playlist_id=playlist_id).first()
    if enrolment is None:
        raise NotFoundError("Recorded course", playlist_id)
    videos = list(
        PlaylistVideo.objects.filter(
            playlist_id=playlist_id, status=PlaylistVideo.Status.PUBLISHED
        )
    )
    watched = set(enrolment.watched.values_list("video_id", flat=True))
    return enrolment, videos, watched
```

`api/serializers.py` append:

```python
def my_video_data(v, watched: set[int], fallback_thumb: str) -> dict:
    return {
        "id": v.pk,
        "title": v.title,
        "description": v.description,
        "kind": v.kind,
        "url": v.url,
        "embed_provider": v.embed_provider,
        "embed_id": v.embed_id,
        "has_file": bool(v.file),
        "downloadable": v.downloadable,
        "duration_seconds": v.duration_seconds,
        "thumbnail_url": _url(v.thumbnail) or fallback_thumb,
        "watched": v.pk in watched,
    }
```

`api/my_views.py`:

```python
from django.http import Http404
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.platform.exceptions import ForbiddenError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.params import int_param
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import IsParent
from etqan.platform.permissions import IsStudent
from etqan.platform.permissions import role_of
from etqan.recorded import services
from etqan.recorded.api.serializers import _url
from etqan.recorded.api.serializers import my_video_data

FAMILY = [IsStudent | IsParent, FeatureOn]


def _progress(p) -> dict:
    return {"watched": p.watched, "total": p.total}


class MyCoursesView(APIView):
    feature = "recorded_courses"
    permission_classes = FAMILY

    def get(self, request):
        try:
            rows = services.my_enrolments(
                request.user, int_param(request.query_params, "student")
            )
        except NotFoundError:
            raise Http404 from None
        return Response(
            [
                {
                    "enrolment_id": e.pk,
                    "playlist": {
                        "id": e.playlist_id,
                        "title": e.playlist.title,
                        "thumbnail_url": _url(e.playlist.thumbnail),
                        "content_language": e.playlist.content_language,
                    },
                    "progress": {
                        "watched": e.watched_count,
                        "total": services.progress(e).total,
                    },
                }
                for e in rows
            ]
        )


class MyCourseView(APIView):
    feature = "recorded_courses"
    permission_classes = FAMILY

    def get(self, request, pk):
        try:
            e, videos, watched = services.my_playlist(
                request.user, pk, int_param(request.query_params, "student")
            )
        except NotFoundError:
            raise Http404 from None
        pl = e.playlist
        thumb = _url(pl.thumbnail)
        return Response(
            {
                "enrolment_id": e.pk,
                "playlist": {
                    "id": pl.pk,
                    "title": pl.title,
                    "description": pl.description,
                    "content": pl.content,
                    "terms": pl.terms,
                    "thumbnail_url": thumb,
                    "content_language": pl.content_language,
                },
                "videos": [my_video_data(v, watched, thumb) for v in videos],
                "progress": _progress(services.progress(e)),
            }
        )


class MyWatchedView(APIView):
    """PUT marks watched, DELETE unmarks; the student's own only."""

    feature = "recorded_courses"
    permission_classes = FAMILY

    def _toggle(self, request, pk, watched: bool):
        if role_of(request.user) != "student":
            raise ForbiddenError("Only the student marks a lesson watched.")
        try:
            video = services.get_video(pk)
        except NotFoundError:
            raise Http404 from None
        if not services.can_watch(request.user, video):
            raise Http404
        enrolment = services.enrolment_for(request.user.pk, video.playlist_id)
        services.set_watched(enrolment, video, watched)
        return Response({"progress": _progress(services.progress(enrolment))})

    def put(self, request, pk):
        return self._toggle(request, pk, True)

    def delete(self, request, pk):
        return self._toggle(request, pk, False)
```

If `etqan.platform.params` has no `int_param`, copy `learning/api/params.py:_int_param` into `etqan/recorded/api/params.py` as `int_param` and import it from there. Check with `B grep -n "def " etqan/platform/params.py` first.

`api/urls.py` adds:

```python
from etqan.recorded.api import my_views
    path("my/", my_views.MyCoursesView.as_view()),
    path("my/<int:pk>/", my_views.MyCourseView.as_view()),
    path("my/videos/<int:pk>/watched/", my_views.MyWatchedView.as_view()),
```

Export `my_enrolments` and `my_playlist` from `services/__init__.py`.

`test_routes.py` `SELF_SERVICE` appends:

```python
    # Phase B7, slice B7a
    "etqan.recorded.api.my_views.MyCoursesView": (
        "the student's own recorded courses, or a parent's child's; scoped in the service"
    ),
    "etqan.recorded.api.my_views.MyCourseView": (
        "the student's own recorded course, or a parent's child's; scoped in the service"
    ),
    "etqan.recorded.api.my_views.MyWatchedView": (
        "the student's own watched toggle; parents 403; scoped in the view"
    ),
```

- [ ] **Step 4: Run** — `B pytest etqan/recorded etqan/access -q` → PASS.
- [ ] **Step 5: Commit** — `git -C backend add etqan/recorded etqan/access/tests/test_routes.py && git -C backend commit -m "feat(recorded): B7a student and parent API" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 10: Demo seed (§10, A-16)

**Files:**
- Create: `backend/etqan/tenants/seeds/b7.py`, `backend/etqan/recorded/tests/test_seeds.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (under `# ── phase B7 ──` in `seed_academy`)

**Interfaces:**
- Produces: `seed_b7(subdomain: str) -> None`, idempotent by playlist code; demo academy only.

- [ ] **Step 1: Write the failing test**

```python
import pytest

from etqan.identity import services as identity_services
from etqan.recorded.models import Enrolment
from etqan.recorded.models import Playlist
from etqan.recorded.models import WatchedVideo
from etqan.tenants.seeds.b7 import seed_b7

pytestmark = pytest.mark.django_db


def test_seed_is_idempotent_and_demo_only(api_for):
    identity_services.create_person(
        "student", full_name="Yusuf", email="yusuf@demo.test"
    )
    api_for("admin", email="admin@demo.test")
    seed_b7("other")
    assert not Playlist.objects.exists()
    seed_b7("demo")
    seed_b7("demo")
    assert sorted(Playlist.objects.values_list("code", flat=True)) == [
        "QURAN-INTRO", "TAJWEED-1",
    ]
    paid = Enrolment.objects.get(playlist__code="TAJWEED-1")
    assert (paid.method, paid.amount_minor, paid.payment_id is not None) == (
        "manual", 1500, True,
    )
    assert Enrolment.objects.get(playlist__code="QURAN-INTRO").method == "free"
    assert WatchedVideo.objects.count() == 1
```

- [ ] **Step 2: Run** — FAIL (`No module named 'etqan.tenants.seeds.b7'`).

- [ ] **Step 3: Implement** `backend/etqan/tenants/seeds/b7.py`:

```python
"""Phase B7 demo data (slice B7a, spec §10): two published recorded courses
with link videos, the demo student enrolled in both (one free, one manual with
its billing record), one video watched. Demo academy only; idempotent by
playlist code; works whether or not recorded_courses is on."""

import io

from django.core.files.uploadedfile import SimpleUploadedFile
from PIL import Image

from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError
from etqan.recorded import services as recorded
from etqan.recorded.models import Playlist

YT = (
    "https://www.youtube.com/watch?v=GfTOX3-ivzc",
    "https://www.youtube.com/watch?v=5Z5tc1rwhZs",
    "https://www.youtube.com/watch?v=bNlbKMyGGKk",
    "https://www.youtube.com/watch?v=4lXFoK0jW2k",
)
COURSES = (
    {
        "code": "QURAN-INTRO",
        "slug": "quran-intro",
        "title": "مدخل إلى تلاوة القرآن",
        "content_language": "ar",
        "price_minor": 0,
        "discount_minor": 0,
        "videos": [("link", YT[i]) for i in range(3)],
        "enrol": ("free", 0),
    },
    {
        "code": "TAJWEED-1",
        "slug": "tajweed-1",
        "title": "Tajweed, level 1",
        "content_language": "en",
        "price_minor": 2000,
        "discount_minor": 500,
        "videos": [("link", url) for url in YT]
        + [("live", "https://www.youtube.com/live/GfTOX3-ivzc")],
        "enrol": ("manual", 1500),
    },
)


def _thumb():
    buf = io.BytesIO()
    Image.new("RGB", (400, 225), (16, 94, 84)).save(buf, "PNG")
    return SimpleUploadedFile("thumb.png", buf.getvalue(), content_type="image/png")


def _user(email):
    try:
        return identity_services.get_user_by_email(email)
    except NotFoundError:
        return None


def seed_b7(subdomain: str) -> None:
    if subdomain != "demo":
        return
    student, admin = _user("yusuf@demo.test"), _user("admin@demo.test")
    for spec in COURSES:
        if Playlist.objects.filter(code=spec["code"]).exists():
            continue
        pl = recorded.create_playlist(
            title=spec["title"],
            slug=spec["slug"],
            description="A short recorded course for the demo academy.",
            code=spec["code"],
            content_language=spec["content_language"],
            terms="Personal use only.",
            thumbnail=_thumb(),
            price_minor=spec["price_minor"],
            discount_minor=spec["discount_minor"],
            currency="USD",
            is_published=True,
        )
        videos = [
            recorded.create_video(
                pl,
                code=f"L{n + 1}",
                title=f"Lesson {n + 1}",
                slug=f"lesson-{n + 1}",
                kind=kind,
                url=url,
                duration_seconds=600,
                status="published",
            )
            for n, (kind, url) in enumerate(spec["videos"])
        ]
        if student is None or admin is None:
            continue
        method, amount = spec["enrol"]
        enrolment = recorded.enrol_by_office(
            playlist=pl,
            student_user_id=student.pk,
            method=method,
            amount_minor=amount,
            billing_method="cash" if method == "manual" else "",
            by=admin,
        )
        if method == "free":
            recorded.set_watched(enrolment, videos[0], True)
```

`seed_dev.py`, under `# ── phase B7 ──` in `seed_academy`:

```python
        from etqan.tenants.seeds.b7 import seed_b7  # noqa: PLC0415

        seed_b7(subdomain)
```

`seed_dev.FEATURES` is `{"demo": features.BUILT}`, so the demo academy turns `recorded_courses` on with no edit.

Also confirm `identity_services.get_user_by_email` raises `NotFoundError` on a miss, as `seeds/b6.py:_student` assumes.

- [ ] **Step 4: Run** — `B pytest etqan/recorded/tests/test_seeds.py etqan/tenants -q` → PASS; then `just seed` on the stream stack and confirm no error.
- [ ] **Step 5: Commit** — `git -C backend add etqan/tenants/seeds/b7.py etqan/tenants/management/commands/seed_dev.py etqan/recorded/tests/test_seeds.py && git -C backend commit -m "feat(recorded): B7a demo seed" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

Backend checkpoint: `B pytest -q --cov=etqan.recorded --cov-report=term-missing etqan/recorded` shows ≥ 90 % for `etqan/recorded`; `B ruff check . && B ruff format --check . && B lint-imports` clean.

---

### Task 11: Dashboard data layer, strings and the switch

**Files:**
- Create: `dashboard/src/features/recorded/schemas.ts`, `duration.ts`, `duration.test.ts`, `api.ts`, `api.test.ts`, `queries.ts`, `errors.ts`, `errors.test.ts`, `fixtures.ts`, `index.ts`
- Create: `dashboard/src/locales/en/recorded.json`, `dashboard/src/locales/ar/recorded.json`
- Modify: `dashboard/src/features/identity/schemas.ts` (FeatureCode)

**Interfaces:**
- Produces: the types `Playlist`, `PlaylistVideo`, `Enrolment`, `MyCourse`, `MyPlaylist`, `MyVideo`, `Progress`; the constants `LANGUAGES`, `VIDEO_KINDS`, `VIDEO_STATUSES`, `OFFICE_METHODS`; `formatDuration(seconds) -> string`, `parseDuration(text) -> number | undefined`; `recordedApi` (below); hooks `usePlaylists`, `usePlaylist`, `useSavePlaylist`, `useDeletePlaylist`, `useVideos`, `useSaveVideo`, `useDeleteVideo`, `useMoveVideo`, `useEnrolments`, `useEnrol`, `useUpdateEnrolment`, `useEnrolmentAction`, `useDeleteEnrolment`, `useMyCourses`, `useMyCourse`, `useSetWatched`; `recordedErrorText(error, t)`, `formErrors(error, t, inputs)`.

- [ ] **Step 1: Write the failing tests**

`duration.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { formatDuration, parseDuration } from "./duration";

describe("duration", () => {
	it("formats as HH:MM:SS", () => {
		expect(formatDuration(0)).toBe("00:00:00");
		expect(formatDuration(3725)).toBe("01:02:05");
		expect(formatDuration(86400)).toBe("24:00:00");
	});
	it("parses H:MM:SS and MM:SS, refusing nonsense", () => {
		expect(parseDuration("01:02:05")).toBe(3725);
		expect(parseDuration("2:05")).toBe(125);
		expect(parseDuration(" 0:00:30 ")).toBe(30);
		for (const bad of ["", "abc", "1:60", "1:2:3:4", "00:00:00", "24:00:01", "-1:00"])
			expect(parseDuration(bad)).toBeUndefined();
	});
});
```

`api.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { recordedApi } from "./api";

vi.mock("@/lib/api", () => ({
	api: {
		defaults: { baseURL: "/api/v1/" },
		get: vi.fn(),
		post: vi.fn(),
		patch: vi.fn(),
		put: vi.fn(),
		delete: vi.fn(),
	},
}));

describe("recordedApi", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		for (const fn of [api.get, api.post, api.patch, api.put])
			vi.mocked(fn).mockResolvedValue({ data: { ok: true } });
	});

	it("lists playlists with only the filters given", async () => {
		await recordedApi.list({ published: true, q: "" });
		expect(api.get).toHaveBeenCalledWith("recorded/playlists/", {
			params: { published: "true" },
		});
	});

	it("addresses videos, moves and enrolments", async () => {
		const form = new FormData();
		await recordedApi.createVideo(4, form);
		expect(api.post).toHaveBeenCalledWith("recorded/playlists/4/videos/", form);
		await recordedApi.moveVideo(9, "up");
		expect(api.post).toHaveBeenCalledWith("recorded/videos/9/move/", {
			direction: "up",
		});
		await recordedApi.enrolments(4, { page: 2, status: "active" });
		expect(api.get).toHaveBeenCalledWith("recorded/playlists/4/enrolments/", {
			params: { page: 2, status: "active" },
		});
		await recordedApi.enrolmentAction(7, "revoke");
		expect(api.post).toHaveBeenCalledWith("recorded/enrolments/7/revoke/");
	});

	it("reads the family side with an optional child", async () => {
		await recordedApi.my(12);
		expect(api.get).toHaveBeenCalledWith("recorded/my/", {
			params: { student: 12 },
		});
		await recordedApi.myCourse(3);
		expect(api.get).toHaveBeenLastCalledWith("recorded/my/3/", { params: {} });
		await recordedApi.setWatched(5, true);
		expect(api.put).toHaveBeenCalledWith("recorded/my/videos/5/watched/");
		await recordedApi.setWatched(5, false);
		expect(api.delete).toHaveBeenCalledWith("recorded/my/videos/5/watched/");
	});

	it("builds the lesson file URL", () => {
		expect(recordedApi.fileUrl(5)).toBe("/api/v1/recorded/videos/5/file/");
		expect(recordedApi.fileUrl(5, true)).toBe(
			"/api/v1/recorded/videos/5/file/?download=1",
		);
	});
});
```

`errors.test.ts`:

```ts
import { AxiosError, type AxiosResponse } from "axios";
import i18n from "i18next";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import { recordedErrorText } from "./errors";

function conflict(code: string) {
	return new AxiosError("x", "409", undefined, undefined, {
		status: 409,
		data: { detail: "server words", code },
	} as AxiosResponse);
}

describe("recordedErrorText", () => {
	it("translates recorded.* codes from the area", () => {
		expect(recordedErrorText(conflict("recorded.already_enrolled"), i18n.t)).toBe(
			"This student is already enrolled in this course.",
		);
	});
	it("falls back to the server's words", () => {
		expect(recordedErrorText(conflict("other.code"), i18n.t)).toBe("server words");
	});
});
```

- [ ] **Step 2: Run** — `F pnpm vitest run src/features/recorded` → FAIL (modules missing).

- [ ] **Step 3: Implement**

`schemas.ts`:

```ts
export const LANGUAGES = ["ar", "en", "ur", "tr", "fr", "es"] as const;
export type ContentLanguage = (typeof LANGUAGES)[number];
export const VIDEO_KINDS = ["link", "file", "live"] as const;
export type VideoKind = (typeof VIDEO_KINDS)[number];
export const VIDEO_STATUSES = ["draft", "published", "hidden"] as const;
export type VideoStatus = (typeof VIDEO_STATUSES)[number];
export const OFFICE_METHODS = ["manual", "free"] as const;
export type EnrolmentMethod = "manual" | "free" | "stripe" | "paypal" | "code";
export type EmbedProvider = "" | "youtube" | "vimeo";

export interface Progress {
	watched: number;
	total: number;
}

export interface Playlist {
	id: number;
	title: string;
	slug: string;
	description: string;
	code: string;
	content_language: ContentLanguage;
	price_minor: number;
	discount_minor: number;
	currency: string;
	content: string;
	terms: string;
	is_published: boolean;
	certificate: boolean;
	app_only: boolean;
	thumbnail_url: string;
	intro_video_url: string;
	lessons: number;
	seconds: number;
	enrolments: number;
}

export interface PlaylistVideo {
	id: number;
	playlist: number;
	code: string;
	title: string;
	slug: string;
	kind: VideoKind;
	url: string;
	embed_provider: EmbedProvider;
	embed_id: string;
	has_file: boolean;
	thumbnail_url: string;
	duration_seconds: number;
	position: number;
	description: string;
	status: VideoStatus;
	downloadable: boolean;
}

export interface Enrolment {
	id: number;
	playlist: number;
	student: { id: number; full_name: string };
	amount_minor: number;
	currency: string;
	method: EnrolmentMethod;
	transaction_number: string;
	payment_id: number | null;
	notes: string;
	status: "active" | "revoked";
	enrolled_at: string;
	revoked_at: string | null;
	watched_video_ids: number[];
	progress: Progress;
}

export interface MyCourse {
	enrolment_id: number;
	playlist: {
		id: number;
		title: string;
		thumbnail_url: string;
		content_language: ContentLanguage;
	};
	progress: Progress;
}

export interface MyVideo {
	id: number;
	title: string;
	description: string;
	kind: VideoKind;
	url: string;
	embed_provider: EmbedProvider;
	embed_id: string;
	has_file: boolean;
	downloadable: boolean;
	duration_seconds: number;
	thumbnail_url: string;
	watched: boolean;
}

export interface MyPlaylist {
	enrolment_id: number;
	playlist: {
		id: number;
		title: string;
		description: string;
		content: string;
		terms: string;
		thumbnail_url: string;
		content_language: ContentLanguage;
	};
	videos: MyVideo[];
	progress: Progress;
}

export interface PlaylistFilters {
	published?: boolean;
	language?: string;
	has_discount?: boolean;
	q?: string;
}
```

`duration.ts`:

```ts
const pad = (n: number) => String(n).padStart(2, "0");

/** Spec A-4: durations are entered and shown as HH:MM:SS. */
export function formatDuration(seconds: number): string {
	const h = Math.floor(seconds / 3600);
	const m = Math.floor((seconds % 3600) / 60);
	return `${pad(h)}:${pad(m)}:${pad(seconds % 60)}`;
}

/** H:MM:SS or MM:SS → seconds in 1…86400, else undefined. */
export function parseDuration(text: string): number | undefined {
	const parts = text.trim().split(":");
	if (parts.length < 2 || parts.length > 3) return undefined;
	if (!parts.every((p) => /^\d{1,2}$/.test(p))) return undefined;
	const [h, m, s] = (parts.length === 3 ? parts : ["0", ...parts]).map(Number);
	if (m > 59 || s > 59) return undefined;
	const total = h * 3600 + m * 60 + s;
	return total >= 1 && total <= 86400 ? total : undefined;
}
```

`api.ts`:

```ts
import { api, type Paginated } from "@/lib/api";
import type {
	Enrolment,
	MyCourse,
	MyPlaylist,
	Playlist,
	PlaylistFilters,
	PlaylistVideo,
	Progress,
} from "./schemas";

const B = "recorded/";

function filterParams(f: PlaylistFilters) {
	const params: Record<string, string> = {};
	if (f.published !== undefined) params.published = String(f.published);
	if (f.has_discount !== undefined) params.has_discount = String(f.has_discount);
	if (f.language) params.language = f.language;
	if (f.q?.trim()) params.q = f.q.trim();
	return params;
}

export interface EnrolBody {
	student_id: number;
	method: "manual" | "free";
	amount_minor: number;
	billing_method?: string;
	paid_on?: string | null;
	reference?: string;
	transaction_number?: string;
	notes?: string;
}

export interface EnrolmentPatch {
	notes?: string;
	transaction_number?: string;
	watched_video_ids?: number[];
}

export const recordedApi = {
	list: async (f: PlaylistFilters = {}) =>
		(await api.get<Playlist[]>(`${B}playlists/`, { params: filterParams(f) }))
			.data,
	get: async (id: number) =>
		(await api.get<Playlist>(`${B}playlists/${id}/`)).data,
	create: async (form: FormData) =>
		(await api.post<Playlist>(`${B}playlists/`, form)).data,
	update: async (id: number, form: FormData) =>
		(await api.patch<Playlist>(`${B}playlists/${id}/`, form)).data,
	remove: async (id: number) => {
		await api.delete(`${B}playlists/${id}/`);
	},
	videos: async (playlistId: number) =>
		(await api.get<PlaylistVideo[]>(`${B}playlists/${playlistId}/videos/`))
			.data,
	createVideo: async (playlistId: number, form: FormData) =>
		(
			await api.post<PlaylistVideo>(
				`${B}playlists/${playlistId}/videos/`,
				form,
			)
		).data,
	updateVideo: async (id: number, form: FormData) =>
		(await api.patch<PlaylistVideo>(`${B}videos/${id}/`, form)).data,
	removeVideo: async (id: number) => {
		await api.delete(`${B}videos/${id}/`);
	},
	moveVideo: async (id: number, direction: "up" | "down") => {
		await api.post(`${B}videos/${id}/move/`, { direction });
	},
	enrolments: async (
		playlistId: number,
		params: { page?: number; method?: string; status?: string },
	) =>
		(
			await api.get<Paginated<Enrolment>>(
				`${B}playlists/${playlistId}/enrolments/`,
				{ params },
			)
		).data,
	enrol: async (playlistId: number, body: EnrolBody) =>
		(
			await api.post<Enrolment>(
				`${B}playlists/${playlistId}/enrolments/`,
				body,
			)
		).data,
	updateEnrolment: async (id: number, body: EnrolmentPatch) =>
		(await api.patch<Enrolment>(`${B}enrolments/${id}/`, body)).data,
	enrolmentAction: async (id: number, action: "revoke" | "restore") =>
		(await api.post<Enrolment>(`${B}enrolments/${id}/${action}/`)).data,
	removeEnrolment: async (id: number) => {
		await api.delete(`${B}enrolments/${id}/`);
	},
	my: async (student?: number) =>
		(
			await api.get<MyCourse[]>(`${B}my/`, {
				params: student === undefined ? {} : { student },
			})
		).data,
	myCourse: async (playlistId: number, student?: number) =>
		(
			await api.get<MyPlaylist>(`${B}my/${playlistId}/`, {
				params: student === undefined ? {} : { student },
			})
		).data,
	setWatched: async (videoId: number, watched: boolean) => {
		const path = `${B}my/videos/${videoId}/watched/`;
		const res = watched
			? await api.put<{ progress: Progress }>(path)
			: await api.delete<{ progress: Progress }>(path);
		return res.data;
	},
	/** A same-origin URL for `<video src>` and the download link: the session
	 * cookie authenticates it; the server streams or redirects (spec B7-8). */
	fileUrl: (videoId: number, download = false) =>
		`${api.defaults.baseURL ?? "/api/v1/"}${B}videos/${videoId}/file/${
			download ? "?download=1" : ""
		}`,
};
```

`queries.ts`:

```ts
import {
	keepPreviousData,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { type EnrolBody, type EnrolmentPatch, recordedApi } from "./api";
import type { MyPlaylist, PlaylistFilters } from "./schemas";

export const recordedKey = ["recorded"] as const;

function useInvalidating<A, R>(fn: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSuccess: () => qc.invalidateQueries({ queryKey: recordedKey }),
	});
}

export const usePlaylists = (filters: PlaylistFilters) =>
	useQuery({
		queryKey: [...recordedKey, "list", filters],
		queryFn: () => recordedApi.list(filters),
		placeholderData: keepPreviousData,
	});
export const usePlaylist = (id: number | undefined) =>
	useQuery({
		queryKey: [...recordedKey, "playlist", id],
		queryFn: () => recordedApi.get(id as number),
		enabled: id !== undefined,
	});
export const useSavePlaylist = (id?: number) =>
	useInvalidating((form: FormData) =>
		id === undefined ? recordedApi.create(form) : recordedApi.update(id, form),
	);
export const useDeletePlaylist = () =>
	useInvalidating((id: number) => recordedApi.remove(id));
export const useVideos = (playlistId: number) =>
	useQuery({
		queryKey: [...recordedKey, "videos", playlistId],
		queryFn: () => recordedApi.videos(playlistId),
	});
export const useSaveVideo = (playlistId: number, id?: number) =>
	useInvalidating((form: FormData) =>
		id === undefined
			? recordedApi.createVideo(playlistId, form)
			: recordedApi.updateVideo(id, form),
	);
export const useDeleteVideo = () =>
	useInvalidating((id: number) => recordedApi.removeVideo(id));
export const useMoveVideo = () =>
	useInvalidating(
		({ id, direction }: { id: number; direction: "up" | "down" }) =>
			recordedApi.moveVideo(id, direction),
	);
export const useEnrolments = (
	playlistId: number,
	params: { page?: number; method?: string; status?: string },
) =>
	useQuery({
		queryKey: [...recordedKey, "enrolments", playlistId, params],
		queryFn: () => recordedApi.enrolments(playlistId, params),
		placeholderData: keepPreviousData,
	});
export const useEnrol = (playlistId: number) =>
	useInvalidating((body: EnrolBody) => recordedApi.enrol(playlistId, body));
export const useUpdateEnrolment = () =>
	useInvalidating(({ id, body }: { id: number; body: EnrolmentPatch }) =>
		recordedApi.updateEnrolment(id, body),
	);
export const useEnrolmentAction = () =>
	useInvalidating(
		({ id, action }: { id: number; action: "revoke" | "restore" }) =>
			recordedApi.enrolmentAction(id, action),
	);
export const useDeleteEnrolment = () =>
	useInvalidating((id: number) => recordedApi.removeEnrolment(id));
export const useMyCourses = (student?: number, enabled = true) =>
	useQuery({
		queryKey: [...recordedKey, "my", student ?? null],
		queryFn: () => recordedApi.my(student),
		enabled,
	});
export const useMyCourse = (playlistId: number, student?: number, enabled = true) =>
	useQuery({
		queryKey: [...recordedKey, "my", playlistId, student ?? null],
		queryFn: () => recordedApi.myCourse(playlistId, student),
		enabled,
	});

/** Optimistic: the tick flips at once and rolls back on an error. */
export function useSetWatched(playlistId: number) {
	const qc = useQueryClient();
	const key = [...recordedKey, "my", playlistId, null];
	return useMutation({
		mutationFn: ({ videoId, watched }: { videoId: number; watched: boolean }) =>
			recordedApi.setWatched(videoId, watched),
		onMutate: async ({ videoId, watched }) => {
			await qc.cancelQueries({ queryKey: key });
			const before = qc.getQueryData<MyPlaylist>(key);
			if (before)
				qc.setQueryData<MyPlaylist>(key, {
					...before,
					videos: before.videos.map((v) =>
						v.id === videoId ? { ...v, watched } : v,
					),
				});
			return { before };
		},
		onError: (_e, _v, context) => {
			if (context?.before) qc.setQueryData(key, context.before);
		},
		onSettled: () => qc.invalidateQueries({ queryKey: recordedKey }),
	});
}
```

`errors.ts`:

```ts
import type { TFunction } from "i18next";
import { formErrors as baseFormErrors } from "@/features/curriculum/errors";
import { parseApiError } from "@/features/identity/api";
import { errorText } from "@/lib/form-errors";

/** A failed recorded-course action as one sentence: `recorded.*` codes from
 * this area, anything else as everywhere else. */
export function recordedErrorText(error: unknown, t: TFunction): string {
	const code = parseApiError(error).code;
	if (code?.startsWith("recorded.")) {
		const text = t(`recorded.errors.${code.slice("recorded.".length)}`, {
			defaultValue: "",
		});
		if (text) return text;
	}
	return errorText(error, t);
}

export function formErrors(
	error: unknown,
	t: TFunction,
	inputs: readonly string[],
) {
	return baseFormErrors(error, t, inputs, recordedErrorText);
}
```

`fixtures.ts`:

```ts
import type { Enrolment, MyPlaylist, Playlist, PlaylistVideo } from "./schemas";

export const playlist: Playlist = {
	id: 4,
	title: "Tajweed, level 1",
	slug: "tajweed-1",
	description: "Rules of recitation.",
	code: "TAJWEED-1",
	content_language: "en",
	price_minor: 2000,
	discount_minor: 500,
	currency: "USD",
	content: "",
	terms: "Personal use only.",
	is_published: true,
	certificate: false,
	app_only: false,
	thumbnail_url: "/media/t.png",
	intro_video_url: "",
	lessons: 2,
	seconds: 1200,
	enrolments: 1,
};

export const linkVideo: PlaylistVideo = {
	id: 10,
	playlist: 4,
	code: "L1",
	title: "Lesson 1",
	slug: "lesson-1",
	kind: "link",
	url: "https://youtu.be/dQw4w9WgXcQ",
	embed_provider: "youtube",
	embed_id: "dQw4w9WgXcQ",
	has_file: false,
	thumbnail_url: "",
	duration_seconds: 600,
	position: 0,
	description: "",
	status: "published",
	downloadable: false,
};

export const fileVideo: PlaylistVideo = {
	...linkVideo,
	id: 11,
	code: "L2",
	title: "Lesson 2",
	slug: "lesson-2",
	kind: "file",
	url: "",
	embed_provider: "",
	embed_id: "",
	has_file: true,
	position: 1,
	status: "draft",
	downloadable: true,
};

export const enrolment: Enrolment = {
	id: 7,
	playlist: 4,
	student: { id: 21, full_name: "Yusuf" },
	amount_minor: 1500,
	currency: "USD",
	method: "manual",
	transaction_number: "",
	payment_id: 3,
	notes: "",
	status: "active",
	enrolled_at: "2026-10-08T09:00:00+00:00",
	revoked_at: null,
	watched_video_ids: [10],
	progress: { watched: 1, total: 2 },
};

export const myPlaylist: MyPlaylist = {
	enrolment_id: 7,
	playlist: {
		id: 4,
		title: "Tajweed, level 1",
		description: "Rules of recitation.",
		content: "Week by week.",
		terms: "Personal use only.",
		thumbnail_url: "/media/t.png",
		content_language: "en",
	},
	videos: [
		{
			id: 10,
			title: "Lesson 1",
			description: "",
			kind: "link",
			url: "https://youtu.be/dQw4w9WgXcQ",
			embed_provider: "youtube",
			embed_id: "dQw4w9WgXcQ",
			has_file: false,
			downloadable: false,
			duration_seconds: 600,
			thumbnail_url: "",
			watched: true,
		},
		{
			id: 11,
			title: "Lesson 2",
			description: "Uploaded.",
			kind: "file",
			url: "",
			embed_provider: "",
			embed_id: "",
			has_file: true,
			downloadable: true,
			duration_seconds: 600,
			thumbnail_url: "",
			watched: false,
		},
		{
			id: 12,
			title: "Live Q&A",
			description: "",
			kind: "live",
			url: "https://example.com/live",
			embed_provider: "",
			embed_id: "",
			has_file: false,
			downloadable: false,
			duration_seconds: 3600,
			thumbnail_url: "",
			watched: false,
		},
	],
	progress: { watched: 1, total: 3 },
};
```

`index.ts` re-exports `recordedApi`, every hook, the types, `formatDuration`, `parseDuration`, `recordedErrorText`, and (added by later tasks) the components `PlaylistsAdmin`, `PlaylistPage`, `MyCourses`, `CoursePlayer`.

`identity/schemas.ts` — at the end of the `FeatureCode` union add:

```ts
	// Phase B7, slice B7a.
	| "recorded_courses"
```

`locales/en/recorded.json` (complete; later tasks use only these keys):

```json
{
	"nav": { "office": "Recorded courses", "mine": "My recorded courses" },
	"title": "Recorded courses",
	"subtitle": "Video courses students watch at their own pace.",
	"newTitle": "New recorded course",
	"editTitle": "Recorded course",
	"add": "Add course",
	"save": "Save",
	"cancel": "Cancel",
	"delete": "Delete",
	"deleteConfirm": "Delete this course? This cannot be undone.",
	"search": "Search by title or code",
	"empty": "No recorded courses yet.",
	"filters": {
		"published": "Published",
		"language": "Language",
		"discount": "Discount",
		"any": "Any",
		"yes": "Yes",
		"no": "No"
	},
	"languages": {
		"ar": "Arabic",
		"en": "English",
		"ur": "Urdu",
		"tr": "Turkish",
		"fr": "French",
		"es": "Spanish"
	},
	"columns": {
		"title": "Title",
		"code": "Code",
		"language": "Language",
		"price": "Price",
		"lessons": "Lessons",
		"hours": "Hours",
		"published": "Published",
		"enrolments": "Enrolments"
	},
	"free": "Free",
	"tabs": { "details": "Details", "videos": "Videos", "enrolments": "Enrolments" },
	"form": {
		"basic": "Basic",
		"details": "Course details",
		"contentSection": "Content",
		"termsSection": "Terms and conditions",
		"publishing": "Publishing",
		"thumbnail": "Thumbnail (400×225, up to 2 MB)",
		"introVideo": "Intro video (MP4, up to 100 MB)",
		"removeIntro": "Remove the intro video",
		"title": "Title",
		"slug": "Slug",
		"description": "Description",
		"code": "Code",
		"language": "Content language",
		"price": "Price",
		"discount": "Discount",
		"currency": "Currency",
		"content": "Course content",
		"terms": "Terms and conditions",
		"published": "Published",
		"certificate": "Accredited certificate",
		"appOnly": "Show in the app only",
		"required": "This field is required.",
		"thumbnailRequired": "Choose a thumbnail.",
		"discountTooHigh": "The discount cannot be more than the price.",
		"tooLarge": "The file is too large."
	},
	"videos": {
		"add": "Add video",
		"edit": "Edit video",
		"empty": "No videos yet.",
		"code": "Code",
		"title": "Title",
		"slug": "Slug",
		"kind": "Type",
		"kinds": { "link": "Link", "file": "File", "live": "Live stream" },
		"url": "Video link (https)",
		"file": "Video file (MP4)",
		"currentFile": "A file is uploaded.",
		"duration": "Duration (HH:MM:SS)",
		"durationInvalid": "Enter a duration like 00:12:30.",
		"description": "Description",
		"status": "Status",
		"statuses": { "draft": "Draft", "published": "Published", "hidden": "Hidden" },
		"downloadable": "Downloadable",
		"thumbnail": "Thumbnail (optional)",
		"moveUp": "Move up",
		"moveDown": "Move down",
		"urlInvalid": "The link must start with https://.",
		"deleteConfirm": "Delete this video? This cannot be undone."
	},
	"enrolments": {
		"add": "Enrol a student",
		"empty": "No enrolments yet.",
		"student": "Student",
		"studentSearch": "Search students",
		"method": "Method",
		"methods": {
			"manual": "Manual",
			"free": "Free",
			"stripe": "Stripe",
			"paypal": "PayPal",
			"code": "Activation code"
		},
		"amount": "Amount paid",
		"billingMethod": "Paid by",
		"paidOn": "Paid on",
		"reference": "Reference",
		"transaction": "Transaction number",
		"notes": "Notes",
		"manualHint": "A manual enrolment is also recorded as a payment.",
		"enrolledOn": "Enrolled on",
		"progress": "Progress",
		"status": "Status",
		"statuses": { "active": "Active", "revoked": "Revoked" },
		"watched": "Watched videos",
		"revoke": "Revoke",
		"restore": "Restore",
		"open": "Open",
		"saved": "Enrolment saved.",
		"previous": "Previous page",
		"next": "Next page"
	},
	"my": {
		"empty": "You are not enrolled in any recorded course yet.",
		"childPicker": "Child",
		"progress": "{{watched}} of {{total}} watched",
		"lessons": "Lessons",
		"markWatched": "Mark as watched",
		"watched": "Watched",
		"openVideo": "Open video",
		"download": "Download",
		"about": "About this course",
		"terms": "Terms and conditions",
		"readOnly": "You are viewing your child's course."
	},
	"toast": {
		"created": "Course created.",
		"updated": "Course saved.",
		"deleted": "Course deleted.",
		"videoSaved": "Video saved.",
		"videoDeleted": "Video deleted."
	},
	"errors": {
		"already_enrolled": "This student is already enrolled in this course.",
		"playlist_in_use": "This course has enrolments: unpublish it instead.",
		"video_in_use": "Students have watched this video: hide it instead.",
		"enrolment_in_use": "This enrolment has history: revoke it instead.",
		"enrolment_revoked": "This enrolment is revoked."
	}
}
```

`locales/ar/recorded.json` (same keys):

```json
{
	"nav": { "office": "الدورات المسجلة", "mine": "دوراتي المسجلة" },
	"title": "الدورات المسجلة",
	"subtitle": "دورات مصورة يشاهدها الطلاب في الوقت الذي يناسبهم.",
	"newTitle": "دورة مسجلة جديدة",
	"editTitle": "دورة مسجلة",
	"add": "إضافة دورة",
	"save": "حفظ",
	"cancel": "إلغاء",
	"delete": "حذف",
	"deleteConfirm": "حذف هذه الدورة؟ لا يمكن التراجع عن ذلك.",
	"search": "ابحث بالعنوان أو الرمز",
	"empty": "لا توجد دورات مسجلة بعد.",
	"filters": {
		"published": "منشورة",
		"language": "اللغة",
		"discount": "خصم",
		"any": "الكل",
		"yes": "نعم",
		"no": "لا"
	},
	"languages": {
		"ar": "العربية",
		"en": "الإنجليزية",
		"ur": "الأردية",
		"tr": "التركية",
		"fr": "الفرنسية",
		"es": "الإسبانية"
	},
	"columns": {
		"title": "العنوان",
		"code": "الرمز",
		"language": "اللغة",
		"price": "السعر",
		"lessons": "الدروس",
		"hours": "الساعات",
		"published": "منشورة",
		"enrolments": "الاشتراكات"
	},
	"free": "مجانية",
	"tabs": { "details": "التفاصيل", "videos": "الفيديوهات", "enrolments": "الاشتراكات" },
	"form": {
		"basic": "أساسي",
		"details": "تفاصيل الدورة",
		"contentSection": "المحتوى",
		"termsSection": "الشروط والأحكام",
		"publishing": "النشر",
		"thumbnail": "الصورة المصغرة (400×225، حتى 2 ميجابايت)",
		"introVideo": "فيديو تعريفي (MP4، حتى 100 ميجابايت)",
		"removeIntro": "إزالة الفيديو التعريفي",
		"title": "العنوان",
		"slug": "الرابط المختصر",
		"description": "الوصف",
		"code": "الرمز",
		"language": "لغة المحتوى",
		"price": "السعر",
		"discount": "الخصم",
		"currency": "العملة",
		"content": "محتوى الدورة",
		"terms": "الشروط والأحكام",
		"published": "منشورة",
		"certificate": "شهادة معتمدة",
		"appOnly": "تظهر في التطبيق فقط",
		"required": "هذا الحقل مطلوب.",
		"thumbnailRequired": "اختر صورة مصغرة.",
		"discountTooHigh": "لا يمكن أن يزيد الخصم عن السعر.",
		"tooLarge": "الملف كبير جدًا."
	},
	"videos": {
		"add": "إضافة فيديو",
		"edit": "تعديل الفيديو",
		"empty": "لا توجد فيديوهات بعد.",
		"code": "الرمز",
		"title": "العنوان",
		"slug": "الرابط المختصر",
		"kind": "النوع",
		"kinds": { "link": "رابط", "file": "ملف", "live": "بث مباشر" },
		"url": "رابط الفيديو (https)",
		"file": "ملف الفيديو (MP4)",
		"currentFile": "تم رفع ملف.",
		"duration": "المدة (س:د:ث)",
		"durationInvalid": "أدخل مدة مثل 00:12:30.",
		"description": "الوصف",
		"status": "الحالة",
		"statuses": { "draft": "مسودة", "published": "منشور", "hidden": "مخفي" },
		"downloadable": "قابل للتنزيل",
		"thumbnail": "صورة مصغرة (اختيارية)",
		"moveUp": "تحريك للأعلى",
		"moveDown": "تحريك للأسفل",
		"urlInvalid": "يجب أن يبدأ الرابط بـ https://.",
		"deleteConfirm": "حذف هذا الفيديو؟ لا يمكن التراجع عن ذلك."
	},
	"enrolments": {
		"add": "تسجيل طالب",
		"empty": "لا توجد اشتراكات بعد.",
		"student": "الطالب",
		"studentSearch": "ابحث عن طالب",
		"method": "طريقة الاشتراك",
		"methods": {
			"manual": "يدوي",
			"free": "مجاني",
			"stripe": "Stripe",
			"paypal": "PayPal",
			"code": "كود تفعيل"
		},
		"amount": "المبلغ المدفوع",
		"billingMethod": "وسيلة الدفع",
		"paidOn": "تاريخ الدفع",
		"reference": "المرجع",
		"transaction": "رقم العملية",
		"notes": "ملاحظات",
		"manualHint": "يُسجَّل الاشتراك اليدوي كدفعة أيضًا.",
		"enrolledOn": "تاريخ الاشتراك",
		"progress": "التقدم",
		"status": "الحالة",
		"statuses": { "active": "نشط", "revoked": "ملغى" },
		"watched": "الفيديوهات المشاهدة",
		"revoke": "إلغاء الاشتراك",
		"restore": "استعادة",
		"open": "فتح",
		"saved": "تم حفظ الاشتراك.",
		"previous": "الصفحة السابقة",
		"next": "الصفحة التالية"
	},
	"my": {
		"empty": "لست مشتركًا في أي دورة مسجلة بعد.",
		"childPicker": "الابن",
		"progress": "شوهد {{watched}} من {{total}}",
		"lessons": "الدروس",
		"markWatched": "تحديد كمشاهَد",
		"watched": "تمت المشاهدة",
		"openVideo": "فتح الفيديو",
		"download": "تنزيل",
		"about": "عن الدورة",
		"terms": "الشروط والأحكام",
		"readOnly": "أنت تشاهد دورة ابنك."
	},
	"toast": {
		"created": "تم إنشاء الدورة.",
		"updated": "تم حفظ الدورة.",
		"deleted": "تم حذف الدورة.",
		"videoSaved": "تم حفظ الفيديو.",
		"videoDeleted": "تم حذف الفيديو."
	},
	"errors": {
		"already_enrolled": "هذا الطالب مشترك في هذه الدورة بالفعل.",
		"playlist_in_use": "لهذه الدورة اشتراكات: ألغِ نشرها بدلًا من حذفها.",
		"video_in_use": "شاهد الطلاب هذا الفيديو: أخفِه بدلًا من حذفه.",
		"enrolment_in_use": "لهذا الاشتراك سجل: ألغِه بدلًا من حذفه.",
		"enrolment_revoked": "هذا الاشتراك ملغى."
	}
}
```

- [ ] **Step 4: Run** — `F pnpm vitest run src/features/recorded src/locales` → PASS (locales test keeps en/ar equal); `F pnpm tsc --noEmit` clean.
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/recorded src/locales/en/recorded.json src/locales/ar/recorded.json src/features/identity/schemas.ts && git -C dashboard commit -m "feat(recorded): B7a data layer and strings" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 12: Office list page, route and nav

**Files:**
- Create: `dashboard/src/features/recorded/PlaylistsAdmin.tsx`, `PlaylistsAdmin.test.tsx`, `dashboard/src/routes/_authed/catalogue.recorded.index.tsx`
- Modify: `dashboard/src/features/shell/nav.ts` (B7 marker), `features/recorded/index.ts`

**Interfaces:**
- Consumes: `usePlaylists`, `formatDuration`, `formatMoney` (`@/lib/money`), `useCan`.
- Produces: `<PlaylistsAdmin />`; route `/catalogue/recorded/` (`staticData: { permission: "playlist.view_any", feature: "recorded_courses" }`); nav item.

- [ ] **Step 1: Write the failing test** (`PlaylistsAdmin.test.tsx`)

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { playlist } from "./fixtures";
import { PlaylistsAdmin } from "./PlaylistsAdmin";

vi.mock("./api", () => ({ recordedApi: { list: vi.fn() } }));

function show(...codes: string[]) {
	return renderWithRouter(
		<CanProvider me={staffMe(...codes)}>
			<PlaylistsAdmin />
		</CanProvider>,
	);
}

describe("PlaylistsAdmin", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(recordedApi.list).mockResolvedValue([playlist]);
	});

	it("lists courses with price, discount, lessons and hours", async () => {
		show("playlist.view_any", "playlist.create");
		expect(await screen.findByText("Tajweed, level 1")).toBeInTheDocument();
		expect(screen.getByText("TAJWEED-1")).toBeInTheDocument();
		expect(screen.getByText("$15.00")).toBeInTheDocument();
		expect(screen.getByText("$20.00")).toHaveClass("line-through");
		expect(screen.getByText("00:20:00")).toBeInTheDocument();
		expect(screen.getByRole("link", { name: "Add course" })).toBeInTheDocument();
	});

	it("filters by published, language, discount and search", async () => {
		const user = userEvent.setup();
		show("playlist.view_any");
		await screen.findByText("Tajweed, level 1");
		await user.selectOptions(screen.getByLabelText("Published"), "true");
		await user.selectOptions(screen.getByLabelText("Language"), "en");
		await user.selectOptions(screen.getByLabelText("Discount"), "false");
		await user.type(screen.getByLabelText("Search by title or code"), "taj");
		await waitFor(() =>
			expect(recordedApi.list).toHaveBeenLastCalledWith({
				published: true,
				language: "en",
				has_discount: false,
				q: "taj",
			}),
		);
		expect(screen.queryByRole("link", { name: "Add course" })).toBeNull();
	});

	it("shows an empty state", async () => {
		vi.mocked(recordedApi.list).mockResolvedValue([]);
		show("playlist.view_any");
		expect(await screen.findByText("No recorded courses yet.")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run** — `F pnpm vitest run src/features/recorded/PlaylistsAdmin.test.tsx` → FAIL.

- [ ] **Step 3: Implement** `PlaylistsAdmin.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Clapperboard } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";
import { formatMoney } from "@/lib/money";
import {
	buttonVariants,
	Card,
	CardContent,
	EmptyState,
	FormError,
	Input,
	Select,
	Spinner,
	StatusChip,
} from "@/ui";
import { formatDuration } from "./duration";
import { recordedErrorText } from "./errors";
import { usePlaylists } from "./queries";
import { LANGUAGES, type PlaylistFilters } from "./schemas";

const flag = (v: string) => (v === "" ? undefined : v === "true");

export function PlaylistsAdmin() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const [published, setPublished] = useState("");
	const [language, setLanguage] = useState("");
	const [discount, setDiscount] = useState("");
	const [q, setQ] = useState("");
	const filters: PlaylistFilters = {
		published: flag(published),
		language: language || undefined,
		has_discount: flag(discount),
		q: q || undefined,
	};
	const list = usePlaylists(filters);
	const yesNo = (id: string, label: string, value: string, set: (v: string) => void) => (
		<Select aria-label={label} id={id} className="w-auto" value={value}
			onChange={(e) => set(e.target.value)}>
			<option value="">{t("recorded.filters.any")}</option>
			<option value="true">{t("recorded.filters.yes")}</option>
			<option value="false">{t("recorded.filters.no")}</option>
		</Select>
	);

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-2">
				{yesNo("rc-published", t("recorded.filters.published"), published, setPublished)}
				<Select aria-label={t("recorded.filters.language")} className="w-auto"
					value={language} onChange={(e) => setLanguage(e.target.value)}>
					<option value="">{t("recorded.filters.any")}</option>
					{LANGUAGES.map((l) => (
						<option key={l} value={l}>{t(`recorded.languages.${l}`)}</option>
					))}
				</Select>
				{yesNo("rc-discount", t("recorded.filters.discount"), discount, setDiscount)}
				<Input aria-label={t("recorded.search")} placeholder={t("recorded.search")}
					className="w-full sm:w-64" value={q} onChange={(e) => setQ(e.target.value)} />
				{can("playlist.create") ? (
					<Link to="/catalogue/recorded/$playlistId" params={{ playlistId: "new" }}
						className={buttonVariants({ className: "ms-auto" })}>
						{t("recorded.add")}
					</Link>
				) : null}
			</div>
			{list.isPending ? (
				<div className="flex justify-center py-6"><Spinner /></div>
			) : list.isError ? (
				<FormError>{recordedErrorText(list.error, t)}</FormError>
			) : list.data.length === 0 ? (
				<Card><CardContent>
					<EmptyState icon={Clapperboard} title={t("recorded.empty")} />
				</CardContent></Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{(["title", "code", "language", "price", "lessons", "hours", "published", "enrolments"] as const).map((c) => (
									<th key={c} scope="col" className="p-3 text-start font-medium">
										{t(`recorded.columns.${c}`)}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{list.data.map((p) => {
								const net = p.price_minor - p.discount_minor;
								return (
									<tr key={p.id} className="border-t border-border">
										<td className="p-3">
											<Link to="/catalogue/recorded/$playlistId"
												params={{ playlistId: String(p.id) }}
												className="flex items-center gap-3 font-medium">
												<img src={p.thumbnail_url} alt="" className="h-9 w-16 rounded object-cover" />
												{p.title}
											</Link>
										</td>
										<td className="p-3">{p.code}</td>
										<td className="p-3">{t(`recorded.languages.${p.content_language}`)}</td>
										<td className="p-3">
											{p.price_minor === 0 ? t("recorded.free") : (
												<span className="flex flex-wrap gap-2">
													<span>{formatMoney(net, p.currency, i18n.language)}</span>
													{p.discount_minor > 0 ? (
														<span className="text-muted-foreground line-through">
															{formatMoney(p.price_minor, p.currency, i18n.language)}
														</span>
													) : null}
												</span>
											)}
										</td>
										<td className="p-3">{p.lessons}</td>
										<td className="p-3">{formatDuration(p.seconds)}</td>
										<td className="p-3">
											<StatusChip tone={p.is_published ? "live" : "neutral"}>
												{t(p.is_published ? "recorded.filters.yes" : "recorded.filters.no")}
											</StatusChip>
										</td>
										<td className="p-3">{p.enrolments}</td>
									</tr>
								);
							})}
						</tbody>
					</table>
				</div>
			)}
		</div>
	);
}
```

(Format with `F pnpm biome format --write src/features/recorded`. `StatusChip` tones are `neutral`, `live` and `warning`.)

`routes/_authed/catalogue.recorded.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PlaylistsAdmin } from "@/features/recorded";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/catalogue/recorded/")({
	staticData: { permission: "playlist.view_any", feature: "recorded_courses" },
	component: function RecordedListRoute() {
		const { t } = useTranslation();
		usePageTitle(t("recorded.title"));
		return (
			<>
				<PageHeader title={t("recorded.title")} description={t("recorded.subtitle")} />
				<PlaylistsAdmin />
			</>
		);
	},
});
```

`nav.ts`, under `// ── phase B7 ──` (import `Clapperboard` from `lucide-react` at the top with the others):

```ts
	office(
		"/catalogue/recorded",
		"recorded.nav.office",
		Clapperboard,
		"catalogue",
		"playlist.view_any",
		"recorded_courses",
	),
```

Regenerate the route tree with `F pnpm build` (or run the dev server once) and commit `src/routeTree.gen.ts`. Never hand-merge it.

- [ ] **Step 4: Run** — `F pnpm vitest run src/features/recorded src/features/shell` → PASS; `F pnpm tsc --noEmit`.
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/recorded src/routes/_authed/catalogue.recorded.index.tsx src/features/shell/nav.ts src/routeTree.gen.ts && git -C dashboard commit -m "feat(recorded): B7a office course list" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 13: The course page and its Details tab

**Files:**
- Create: `dashboard/src/features/recorded/PlaylistPage.tsx`, `PlaylistForm.tsx`, `PlaylistForm.test.tsx`, `PlaylistPage.test.tsx`, `dashboard/src/routes/_authed/catalogue.recorded.$playlistId.tsx`
- Modify: `features/recorded/index.ts`

**Interfaces:**
- Produces: `<PlaylistPage playlistId: "new" | string />`, with tabs Details / Videos / Enrolments. Videos and Enrolments show only for an existing course, and each only with `playlist_video.view_any` or `rc_enrolment.view_any`. `<PlaylistForm playlist?: Playlist onSaved(p) />` posts multipart.

- [ ] **Step 1: Write the failing test** (`PlaylistForm.test.tsx`)

```tsx
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError, type AxiosResponse } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { playlist } from "./fixtures";
import { PlaylistForm } from "./PlaylistForm";

vi.mock("./api", () => ({ recordedApi: { create: vi.fn(), update: vi.fn() } }));
const onSaved = vi.fn();

function show(p = undefined as typeof playlist | undefined) {
	return renderWithRouter(
		<CanProvider me={staffMe("playlist.create", "playlist.update")}>
			<PlaylistForm playlist={p} onSaved={onSaved} />
		</CanProvider>,
	);
}

describe("PlaylistForm", () => {
	beforeEach(() => vi.clearAllMocks());

	it("checks required fields and the discount before sending", async () => {
		const user = userEvent.setup();
		show();
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(screen.getAllByText("This field is required.").length).toBeGreaterThan(2);
		expect(screen.getByText("Choose a thumbnail.")).toBeInTheDocument();
		expect(recordedApi.create).not.toHaveBeenCalled();
	});

	it("sends a new course as multipart with minor units", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.create).mockResolvedValue(playlist);
		show();
		await user.type(screen.getByLabelText(/^Title/), "Tajweed");
		await user.type(screen.getByLabelText(/^Slug/), "tajweed");
		await user.type(screen.getByLabelText(/^Description/), "d");
		await user.type(screen.getByLabelText(/^Code/), "TAJ");
		await user.type(screen.getByLabelText(/^Terms and conditions/), "t");
		await user.clear(screen.getByLabelText(/^Currency/));
		await user.type(screen.getByLabelText(/^Currency/), "USD");
		await user.type(screen.getByLabelText(/^Price/), "20");
		await user.type(screen.getByLabelText(/^Discount/), "5");
		await user.upload(screen.getByLabelText(/^Thumbnail/),
			new File(["x"], "t.png", { type: "image/png" }));
		await user.click(screen.getByRole("button", { name: "Save" }));
		const form = vi.mocked(recordedApi.create).mock.calls[0][0] as FormData;
		expect(form.get("price_minor")).toBe("2000");
		expect(form.get("discount_minor")).toBe("500");
		expect(form.get("thumbnail")).toBeInstanceOf(File);
		expect(onSaved).toHaveBeenCalledWith(playlist);
	});

	it("puts server errors on their fields", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.update).mockRejectedValue(
			new AxiosError("x", "400", undefined, undefined, {
				status: 400,
				data: { slug: ["This slug is taken."] },
			} as AxiosResponse),
		);
		show(playlist);
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(await screen.findByText("This slug is taken.")).toBeInTheDocument();
		expect(recordedApi.update).toHaveBeenCalledWith(4, expect.any(FormData));
	});
});
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

`PlaylistForm.tsx` follows `ContentDialog`'s state-per-field pattern, in sections with `<h3>` headings (basic, course details, content, terms, publishing). Required: title, slug, description, code, terms, and a thumbnail for a new course. Money is converted with `toMinor`/`toMajor(@/lib/money)` against the typed currency. For an existing course only changed files are sent, plus `remove_intro`.

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { toMajor, toMinor } from "@/lib/money";
import { Button, Checkbox, Field, FormError, Input, Select, Textarea, toast } from "@/ui";
import { formErrors } from "./errors";
import { useSavePlaylist } from "./queries";
import { LANGUAGES, type Playlist } from "./schemas";

const INPUTS = ["title", "slug", "description", "code", "content_language", "terms",
	"content", "price_minor", "discount_minor", "currency", "thumbnail", "intro_video"] as const;
const THUMB_MAX = 2 * 1024 * 1024;
const INTRO_MAX = 100 * 1024 * 1024;

export function PlaylistForm({ playlist, onSaved }: {
	playlist?: Playlist;
	onSaved: (saved: Playlist) => void;
}) {
	const { t } = useTranslation();
	const save = useSavePlaylist(playlist?.id);
	const cur0 = playlist?.currency ?? "USD";
	const [v, setV] = useState({
		title: playlist?.title ?? "",
		slug: playlist?.slug ?? "",
		description: playlist?.description ?? "",
		code: playlist?.code ?? "",
		content_language: playlist?.content_language ?? "ar",
		terms: playlist?.terms ?? "",
		content: playlist?.content ?? "",
		currency: cur0,
		price: playlist ? toMajor(playlist.price_minor, cur0) : "",
		discount: playlist ? toMajor(playlist.discount_minor, cur0) : "",
	});
	const [flags, setFlags] = useState({
		is_published: playlist?.is_published ?? false,
		certificate: playlist?.certificate ?? false,
		app_only: playlist?.app_only ?? false,
	});
	const [thumb, setThumb] = useState<File>();
	const [intro, setIntro] = useState<File>();
	const [removeIntro, setRemoveIntro] = useState(false);
	const [errors, setErrors] = useState<Record<string, string>>({});
	const [formError, setFormError] = useState<string>();
	const set = (k: keyof typeof v) => (e: { target: { value: string } }) =>
		setV((old) => ({ ...old, [k]: e.target.value }));

	async function submit(e: React.FormEvent) {
		e.preventDefault();
		const next: Record<string, string> = {};
		for (const k of ["title", "slug", "description", "code", "terms"] as const)
			if (!v[k].trim()) next[k] = t("recorded.form.required");
		if (!playlist && !thumb) next.thumbnail = t("recorded.form.thumbnailRequired");
		if (thumb && thumb.size > THUMB_MAX) next.thumbnail = t("recorded.form.tooLarge");
		if (intro && intro.size > INTRO_MAX) next.intro_video = t("recorded.form.tooLarge");
		const currency = v.currency.trim().toUpperCase();
		let price = 0;
		let discount = 0;
		if (/^[A-Z]{3}$/.test(currency)) {
			price = v.price.trim() ? toMinor(v.price, currency) : 0;
			discount = v.discount.trim() ? toMinor(v.discount, currency) : 0;
			if (discount > price) next.discount_minor = t("recorded.form.discountTooHigh");
		} else next.currency = t("recorded.form.required");
		setErrors(next);
		setFormError(undefined);
		if (Object.keys(next).length > 0) return;
		const form = new FormData();
		for (const k of ["title", "slug", "description", "code", "content_language", "terms", "content"] as const)
			form.append(k, v[k].trim());
		form.append("currency", currency);
		form.append("price_minor", String(price));
		form.append("discount_minor", String(discount));
		for (const [k, on] of Object.entries(flags)) form.append(k, on ? "true" : "false");
		if (thumb) form.append("thumbnail", thumb);
		if (intro) form.append("intro_video", intro);
		else if (removeIntro) form.append("remove_intro", "true");
		try {
			const saved = await save.mutateAsync(form);
			toast({ description: t(playlist ? "recorded.toast.updated" : "recorded.toast.created"), variant: "success" });
			onSaved(saved);
		} catch (error) {
			const out = formErrors(error, t, INPUTS);
			setErrors(out.fields);
			setFormError(out.form);
		}
	}

	const text = (k: "title" | "slug" | "code" | "currency", max: number) => (
		<Field id={`rc-${k}`} label={t(`recorded.form.${k}`)} error={errors[k]} required={k !== "currency"}>
			<Input maxLength={max} value={v[k]} onChange={set(k)} />
		</Field>
	);
	const area = (k: "description" | "content" | "terms", max: number, required: boolean) => (
		<Field id={`rc-${k}`} label={t(`recorded.form.${k}`)} error={errors[k]} required={required}>
			<Textarea maxLength={max} value={v[k]} onChange={set(k)} />
		</Field>
	);
	const toggle = (k: keyof typeof flags, label: string) => (
		<div className="flex items-center gap-2">
			<Checkbox id={`rc-${k}`} checked={flags[k]}
				onCheckedChange={(on) => setFlags((f) => ({ ...f, [k]: on }))} />
			<label htmlFor={`rc-${k}`} className="text-sm">{label}</label>
		</div>
	);

	return (
		<form onSubmit={submit} noValidate className="flex max-w-3xl flex-col gap-6">
			{formError ? <FormError>{formError}</FormError> : null}
			<section className="flex flex-col gap-4">
				<h3 className="font-semibold">{t("recorded.form.basic")}</h3>
				{playlist?.thumbnail_url ? (
					<img src={playlist.thumbnail_url} alt="" className="aspect-video w-48 rounded object-cover" />
				) : null}
				<Field id="rc-thumbnail" label={t("recorded.form.thumbnail")} error={errors.thumbnail} required={!playlist}>
					<Input type="file" accept=".png,.jpg,.jpeg,.webp" onChange={(e) => setThumb(e.target.files?.[0])} />
				</Field>
				<Field id="rc-intro" label={t("recorded.form.introVideo")} error={errors.intro_video}>
					<Input type="file" accept=".mp4" onChange={(e) => setIntro(e.target.files?.[0])} />
				</Field>
				{playlist?.intro_video_url ? toggle0() : null}
				{text("title", 160)}
				{text("slug", 80)}
				{area("description", 2000, true)}
			</section>
			<section className="flex flex-col gap-4">
				<h3 className="font-semibold">{t("recorded.form.details")}</h3>
				{text("code", 40)}
				<Field id="rc-language" label={t("recorded.form.language")} error={errors.content_language} required>
					<Select value={v.content_language} onChange={set("content_language")}>
						{LANGUAGES.map((l) => <option key={l} value={l}>{t(`recorded.languages.${l}`)}</option>)}
					</Select>
				</Field>
				<div className="grid gap-4 sm:grid-cols-3">
					{text("currency", 3)}
					<Field id="rc-price" label={t("recorded.form.price")} error={errors.price_minor}>
						<Input inputMode="decimal" value={v.price} onChange={set("price")} />
					</Field>
					<Field id="rc-discount" label={t("recorded.form.discount")} error={errors.discount_minor}>
						<Input inputMode="decimal" value={v.discount} onChange={set("discount")} />
					</Field>
				</div>
			</section>
			<section className="flex flex-col gap-4">
				<h3 className="font-semibold">{t("recorded.form.contentSection")}</h3>
				{area("content", 20000, false)}
			</section>
			<section className="flex flex-col gap-4">
				<h3 className="font-semibold">{t("recorded.form.termsSection")}</h3>
				{area("terms", 10000, true)}
			</section>
			<section className="flex flex-col gap-3">
				<h3 className="font-semibold">{t("recorded.form.publishing")}</h3>
				{toggle("is_published", t("recorded.form.published"))}
				{toggle("certificate", t("recorded.form.certificate"))}
				{toggle("app_only", t("recorded.form.appOnly"))}
			</section>
			<div><Button type="submit" disabled={save.isPending}>{t("recorded.save")}</Button></div>
		</form>
	);

	function toggle0() {
		return (
			<div className="flex items-center gap-2">
				<Checkbox id="rc-remove-intro" checked={removeIntro} onCheckedChange={setRemoveIntro} />
				<label htmlFor="rc-remove-intro" className="text-sm">{t("recorded.form.removeIntro")}</label>
			</div>
		);
	}
}
```

The labels end in a required marker; tests match them with `^Title`. Price fields are labelled "Price" / "Discount". The test's `getByLabelText(/^Price/)` must not also match another label; it does not.

`PlaylistPage.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";
import { Button, FormError, Spinner } from "@/ui";
import { EnrolmentsTab } from "./EnrolmentsTab";
import { recordedErrorText } from "./errors";
import { PlaylistForm } from "./PlaylistForm";
import { usePlaylist } from "./queries";
import { VideosTab } from "./VideosTab";

type Tab = "details" | "videos" | "enrolments";

export function PlaylistPage({ playlistId }: { playlistId: string }) {
	const { t } = useTranslation();
	const can = useCan();
	const navigate = useNavigate();
	const isNew = playlistId === "new";
	const id = isNew ? undefined : Number(playlistId);
	const query = usePlaylist(id);
	const [tab, setTab] = useState<Tab>("details");
	if (!isNew && query.isPending)
		return <div className="flex justify-center py-6"><Spinner /></div>;
	if (!isNew && query.isError) return <FormError>{recordedErrorText(query.error, t)}</FormError>;
	const tabs: Tab[] = ["details"];
	if (!isNew && can("playlist_video.view_any")) tabs.push("videos");
	if (!isNew && can("rc_enrolment.view_any")) tabs.push("enrolments");
	return (
		<div className="flex flex-col gap-4">
			{tabs.length > 1 ? (
				<div role="tablist" className="flex flex-wrap gap-2">
					{tabs.map((k) => (
						<Button key={k} role="tab" aria-selected={tab === k} size="sm"
							variant={tab === k ? "default" : "outline"} onClick={() => setTab(k)}>
							{t(`recorded.tabs.${k}`)}
						</Button>
					))}
				</div>
			) : null}
			{tab === "details" ? (
				<PlaylistForm key={query.data?.id ?? "new"} playlist={query.data}
					onSaved={(saved) => {
						if (isNew) navigate({ to: "/catalogue/recorded/$playlistId", params: { playlistId: String(saved.id) } });
					}} />
			) : tab === "videos" && id !== undefined ? (
				<VideosTab playlistId={id} />
			) : id !== undefined && query.data ? (
				<EnrolmentsTab playlist={query.data} />
			) : null}
		</div>
	);
}
```

Until Tasks 14 and 15 land, `VideosTab` and `EnrolmentsTab` are imported but missing. Create both now as one-line stubs (`export function VideosTab(_: { playlistId: number }) { return null; }`, likewise `EnrolmentsTab`) so `tsc` passes; Tasks 14 and 15 replace them.

`routes/_authed/catalogue.recorded.$playlistId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { newOrView } from "@/features/identity/permissions";
import { PlaylistPage } from "@/features/recorded";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/catalogue/recorded/$playlistId")({
	staticData: {
		permission: newOrView("playlistId", "playlist"),
		feature: "recorded_courses",
	},
	component: function RecordedCourseRoute() {
		const { t } = useTranslation();
		const { playlistId } = Route.useParams();
		const title = t(playlistId === "new" ? "recorded.newTitle" : "recorded.editTitle");
		usePageTitle(title);
		return (
			<>
				<PageHeader title={title} />
				<PlaylistPage playlistId={playlistId} />
			</>
		);
	},
});
```

Delete sits on the Details tab under the form. Add to `PlaylistPage.tsx`:

```tsx
function DeletePlaylist({ playlist }: { playlist: Playlist }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const remove = useDeletePlaylist();
	return (
		<AlertDialog>
			<AlertDialogTrigger asChild>
				<Button variant="outline" className="self-start">{t("recorded.delete")}</Button>
			</AlertDialogTrigger>
			<AlertDialogContent>
				<AlertDialogTitle>{playlist.title}</AlertDialogTitle>
				<AlertDialogDescription>{t("recorded.deleteConfirm")}</AlertDialogDescription>
				<AlertDialogFooter>
					<AlertDialogCancel>{t("recorded.cancel")}</AlertDialogCancel>
					<AlertDialogAction
						onClick={() =>
							remove.mutate(playlist.id, {
								onSuccess: () => {
									toast({ description: t("recorded.toast.deleted"), variant: "success" });
									navigate({ to: "/catalogue/recorded" });
								},
								onError: (error) =>
									toast({ description: recordedErrorText(error, t), variant: "destructive" }),
							})
						}
					>
						{t("recorded.delete")}
					</AlertDialogAction>
				</AlertDialogFooter>
			</AlertDialogContent>
		</AlertDialog>
	);
}
```

Render it in the details branch: wrap the form as `<div className="flex flex-col gap-6"><PlaylistForm … />{query.data && can("playlist.delete") ? <DeletePlaylist playlist={query.data} /> : null}</div>`. Import the AlertDialog parts, `toast` from `@/ui`, `useDeletePlaylist`, and the `Playlist` type.

`PlaylistPage.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError, type AxiosResponse } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { toast } from "@/ui";
import { recordedApi } from "./api";
import { playlist } from "./fixtures";
import { PlaylistPage } from "./PlaylistPage";

vi.mock("./api", () => ({
	recordedApi: { get: vi.fn(), remove: vi.fn(), videos: vi.fn(), enrolments: vi.fn() },
}));
vi.mock("@/ui", async (orig) => ({
	...(await orig<typeof import("@/ui")>()),
	toast: vi.fn(),
}));

function show(...codes: string[]) {
	return renderWithRouter(
		<CanProvider me={staffMe(...codes)}>
			<PlaylistPage playlistId="4" />
		</CanProvider>,
	);
}

describe("PlaylistPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(recordedApi.get).mockResolvedValue(playlist);
		vi.mocked(recordedApi.videos).mockResolvedValue([]);
	});

	it("shows only the tabs the codes allow", async () => {
		show("playlist.view", "playlist_video.view_any");
		expect(await screen.findByRole("tab", { name: "Videos" })).toBeInTheDocument();
		expect(screen.queryByRole("tab", { name: "Enrolments" })).toBeNull();
		expect(screen.queryByRole("button", { name: "Delete" })).toBeNull();
	});

	it("a 409 on delete shows the in-use sentence", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.remove).mockRejectedValue(
			new AxiosError("x", "409", undefined, undefined, {
				status: 409,
				data: { detail: "x", code: "recorded.playlist_in_use" },
			} as AxiosResponse),
		);
		show("playlist.view", "playlist.update", "playlist.delete");
		await user.click(await screen.findByRole("button", { name: "Delete" }));
		await user.click(screen.getByRole("button", { name: "Delete" }));
		expect(recordedApi.remove).toHaveBeenCalledWith(4);
		await vi.waitFor(() =>
			expect(toast).toHaveBeenCalledWith({
				description: "This course has enrolments: unpublish it instead.",
				variant: "destructive",
			}),
		);
	});
});
```

(The second "Delete" click is the confirm button inside the alert dialog. If both match, scope it with `within(screen.getByRole("alertdialog"))`.)

- [ ] **Step 4: Run** — `F pnpm vitest run src/features/recorded` → PASS; `F pnpm tsc --noEmit`; regenerate `routeTree.gen.ts`.
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/recorded "src/routes/_authed/catalogue.recorded.\$playlistId.tsx" src/routeTree.gen.ts && git -C dashboard commit -m "feat(recorded): B7a course page and details form" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 14: The Videos tab and dialog

**Files:**
- Create (replace the stub): `dashboard/src/features/recorded/VideosTab.tsx`, `VideoDialog.tsx`, `VideosTab.test.tsx`, `VideoDialog.test.tsx`

**Interfaces:**
- Consumes: `useVideos`, `useSaveVideo`, `useDeleteVideo`, `useMoveVideo`, `formatDuration`, `parseDuration`.
- Produces: `<VideosTab playlistId />`, `<VideoDialog playlistId video? open onOpenChange />`.

- [ ] **Step 1: Write the failing tests**

`VideoDialog.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { fileVideo, linkVideo } from "./fixtures";
import { VideoDialog } from "./VideoDialog";

vi.mock("./api", () => ({ recordedApi: { createVideo: vi.fn(), updateVideo: vi.fn() } }));

describe("VideoDialog", () => {
	beforeEach(() => vi.clearAllMocks());

	it("asks for a link for link and live, a file for file", async () => {
		const user = userEvent.setup();
		renderWithRouter(<VideoDialog playlistId={4} open onOpenChange={() => {}} />);
		expect(screen.getByLabelText(/^Video link/)).toBeInTheDocument();
		await user.selectOptions(screen.getByLabelText(/^Type/), "file");
		expect(screen.getByLabelText(/^Video file/)).toBeInTheDocument();
		expect(screen.getByLabelText("Downloadable")).toBeInTheDocument();
		await user.selectOptions(screen.getByLabelText(/^Type/), "live");
		expect(screen.queryByLabelText("Downloadable")).toBeNull();
	});

	it("checks the duration and the link, then sends seconds", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.createVideo).mockResolvedValue(linkVideo);
		renderWithRouter(<VideoDialog playlistId={4} open onOpenChange={() => {}} />);
		await user.type(screen.getByLabelText(/^Code/), "L1");
		await user.type(screen.getByLabelText(/^Title/), "Lesson 1");
		await user.type(screen.getByLabelText(/^Slug/), "lesson-1");
		await user.type(screen.getByLabelText(/^Video link/), "http://x.test");
		await user.type(screen.getByLabelText(/^Duration/), "99:99");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(screen.getByText("Enter a duration like 00:12:30.")).toBeInTheDocument();
		expect(screen.getByText("The link must start with https://.")).toBeInTheDocument();
		await user.clear(screen.getByLabelText(/^Video link/));
		await user.type(screen.getByLabelText(/^Video link/), "https://youtu.be/dQw4w9WgXcQ");
		await user.clear(screen.getByLabelText(/^Duration/));
		await user.type(screen.getByLabelText(/^Duration/), "00:10:00");
		await user.click(screen.getByRole("button", { name: "Save" }));
		const form = vi.mocked(recordedApi.createVideo).mock.calls[0][1] as FormData;
		expect(form.get("duration_seconds")).toBe("600");
		expect(form.get("kind")).toBe("link");
	});

	it("edits a file video without re-uploading", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.updateVideo).mockResolvedValue(fileVideo);
		renderWithRouter(<VideoDialog playlistId={4} video={fileVideo} open onOpenChange={() => {}} />);
		expect(screen.getByText("A file is uploaded.")).toBeInTheDocument();
		expect(screen.getByLabelText(/^Duration/)).toHaveValue("00:10:00");
		await user.click(screen.getByRole("button", { name: "Save" }));
		const form = vi.mocked(recordedApi.updateVideo).mock.calls[0][1] as FormData;
		expect(form.get("file")).toBeNull();
	});
});
```

`VideosTab.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError, type AxiosResponse } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { toast } from "@/ui";
import { recordedApi } from "./api";
import { fileVideo, linkVideo } from "./fixtures";
import { VideosTab } from "./VideosTab";

vi.mock("./api", () => ({
	recordedApi: { videos: vi.fn(), moveVideo: vi.fn(), removeVideo: vi.fn() },
}));
vi.mock("@/ui", async (orig) => ({
	...(await orig<typeof import("@/ui")>()),
	toast: vi.fn(),
}));

const ALL = ["playlist_video.view_any", "playlist_video.create", "playlist_video.update",
	"playlist_video.delete", "playlist_video.reorder"];

function show(codes = ALL) {
	return renderWithRouter(
		<CanProvider me={staffMe(...codes)}>
			<VideosTab playlistId={4} />
		</CanProvider>,
	);
}

describe("VideosTab", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(recordedApi.videos).mockResolvedValue([linkVideo, fileVideo]);
		vi.mocked(recordedApi.moveVideo).mockResolvedValue(undefined);
	});

	it("lists rows in order with type, duration, status and downloadable", async () => {
		show();
		const first = (await screen.findByText("Lesson 1")).closest("tr") as HTMLElement;
		expect(within(first).getByText("Link")).toBeInTheDocument();
		expect(within(first).getByText("00:10:00")).toBeInTheDocument();
		expect(within(first).getByText("Published")).toBeInTheDocument();
		const second = screen.getByText("Lesson 2").closest("tr") as HTMLElement;
		expect(within(second).getByText("Draft")).toBeInTheDocument();
		expect(within(second).getByText("Downloadable")).toBeInTheDocument();
	});

	it("moves within bounds", async () => {
		const user = userEvent.setup();
		show();
		expect(await screen.findByRole("button", { name: "Move up Lesson 1" })).toBeDisabled();
		await user.click(screen.getByRole("button", { name: "Move down Lesson 1" }));
		expect(recordedApi.moveVideo).toHaveBeenCalledWith(10, "down");
	});

	it("filters by status", async () => {
		const user = userEvent.setup();
		show();
		await screen.findByText("Lesson 1");
		await user.selectOptions(screen.getByLabelText("Status"), "draft");
		expect(screen.queryByText("Lesson 1")).toBeNull();
		expect(screen.getByText("Lesson 2")).toBeInTheDocument();
	});

	it("a 409 on delete becomes the hide-instead sentence", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.removeVideo).mockRejectedValue(
			new AxiosError("x", "409", undefined, undefined, {
				status: 409,
				data: { detail: "x", code: "recorded.video_in_use" },
			} as AxiosResponse),
		);
		show();
		const row = (await screen.findByText("Lesson 1")).closest("tr") as HTMLElement;
		await user.click(within(row).getByRole("button", { name: "Delete" }));
		await user.click(within(screen.getByRole("alertdialog")).getByRole("button", { name: "Delete" }));
		await vi.waitFor(() =>
			expect(toast).toHaveBeenCalledWith({
				description: "Students have watched this video: hide it instead.",
				variant: "destructive",
			}),
		);
	});

	it("a read-only staff account gets no controls", async () => {
		show(["playlist_video.view_any"]);
		await screen.findByText("Lesson 1");
		for (const name of ["Add video", "Edit video", "Delete"])
			expect(screen.queryByRole("button", { name })).toBeNull();
		expect(screen.queryByRole("button", { name: /Move/ })).toBeNull();
	});
});
```

The status filter's label is "Status" (`recorded.videos.status`). Its `Select` uses `aria-label`, so `getByLabelText("Status")` finds it. The column header says "Status" too but is not a label.

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

`VideoDialog.tsx` (pattern of `ContentDialog`; fields per A-4):

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	Button, Checkbox, Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter,
	DialogTitle, Field, FormError, Input, Select, Textarea, toast,
} from "@/ui";
import { formatDuration, parseDuration } from "./duration";
import { formErrors } from "./errors";
import { useSaveVideo } from "./queries";
import { type PlaylistVideo, VIDEO_KINDS, VIDEO_STATUSES, type VideoKind, type VideoStatus } from "./schemas";

const INPUTS = ["code", "title", "slug", "kind", "url", "file", "thumbnail",
	"duration_seconds", "description", "status", "downloadable"] as const;

export function VideoDialog({ playlistId, video, open, onOpenChange }: {
	playlistId: number;
	video?: PlaylistVideo;
	open: boolean;
	onOpenChange: (open: boolean) => void;
}) {
	const { t } = useTranslation();
	const save = useSaveVideo(playlistId, video?.id);
	const [code, setCode] = useState(video?.code ?? "");
	const [title, setTitle] = useState(video?.title ?? "");
	const [slug, setSlug] = useState(video?.slug ?? "");
	const [kind, setKind] = useState<VideoKind>(video?.kind ?? "link");
	const [url, setUrl] = useState(video?.url ?? "");
	const [file, setFile] = useState<File>();
	const [thumb, setThumb] = useState<File>();
	const [duration, setDuration] = useState(video ? formatDuration(video.duration_seconds) : "");
	const [description, setDescription] = useState(video?.description ?? "");
	const [status, setStatus] = useState<VideoStatus>(video?.status ?? "draft");
	const [downloadable, setDownloadable] = useState(video?.downloadable ?? false);
	const [errors, setErrors] = useState<Record<string, string>>({});
	const [formError, setFormError] = useState<string>();

	async function submit(e: React.FormEvent) {
		e.preventDefault();
		const next: Record<string, string> = {};
		for (const [k, value] of [["code", code], ["title", title], ["slug", slug]] as const)
			if (!value.trim()) next[k] = t("recorded.form.required");
		const seconds = parseDuration(duration);
		if (seconds === undefined) next.duration_seconds = t("recorded.videos.durationInvalid");
		if (kind === "file") {
			if (!file && !video?.has_file) next.file = t("recorded.form.required");
		} else if (!/^https:\/\//i.test(url.trim())) next.url = t("recorded.videos.urlInvalid");
		setErrors(next);
		setFormError(undefined);
		if (Object.keys(next).length > 0) return;
		const form = new FormData();
		form.append("code", code.trim());
		form.append("title", title.trim());
		form.append("slug", slug.trim());
		form.append("kind", kind);
		form.append("duration_seconds", String(seconds));
		form.append("description", description);
		form.append("status", status);
		form.append("downloadable", kind === "file" && downloadable ? "true" : "false");
		if (kind === "file") { if (file) form.append("file", file); }
		else form.append("url", url.trim());
		if (thumb) form.append("thumbnail", thumb);
		try {
			await save.mutateAsync(form);
			toast({ description: t("recorded.toast.videoSaved"), variant: "success" });
			onOpenChange(false);
		} catch (error) {
			const out = formErrors(error, t, INPUTS);
			setErrors(out.fields);
			setFormError(out.form);
		}
	}

	const input = (id: string, k: string, value: string, set: (v: string) => void, max: number) => (
		<Field id={id} label={t(`recorded.videos.${k}`)} error={errors[k === "duration" ? "duration_seconds" : k]} required>
			<Input maxLength={max} value={value} onChange={(e) => set(e.target.value)} />
		</Field>
	);

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent>
				<DialogTitle>{t(video ? "recorded.videos.edit" : "recorded.videos.add")}</DialogTitle>
				<DialogDescription>{t("recorded.subtitle")}</DialogDescription>
				<form onSubmit={submit} noValidate className="mt-4 flex flex-col gap-4">
					{formError ? <FormError>{formError}</FormError> : null}
					{input("rv-code", "code", code, setCode, 40)}
					{input("rv-title", "title", title, setTitle, 160)}
					{input("rv-slug", "slug", slug, setSlug, 80)}
					<Field id="rv-kind" label={t("recorded.videos.kind")} error={errors.kind} required>
						<Select value={kind} onChange={(e) => setKind(e.target.value as VideoKind)}>
							{VIDEO_KINDS.map((k) => <option key={k} value={k}>{t(`recorded.videos.kinds.${k}`)}</option>)}
						</Select>
					</Field>
					{kind === "file" ? (
						<>
							{video?.has_file ? <p className="text-sm text-muted-foreground">{t("recorded.videos.currentFile")}</p> : null}
							<Field id="rv-file" label={t("recorded.videos.file")} error={errors.file} required={!video?.has_file}>
								<Input type="file" accept=".mp4" onChange={(e) => setFile(e.target.files?.[0])} />
							</Field>
							<div className="flex items-center gap-2">
								<Checkbox id="rv-downloadable" checked={downloadable} onCheckedChange={setDownloadable} />
								<label htmlFor="rv-downloadable" className="text-sm">{t("recorded.videos.downloadable")}</label>
							</div>
						</>
					) : (
						<Field id="rv-url" label={t("recorded.videos.url")} error={errors.url} required>
							<Input type="url" inputMode="url" maxLength={500} value={url} onChange={(e) => setUrl(e.target.value)} />
						</Field>
					)}
					{input("rv-duration", "duration", duration, setDuration, 8)}
					<Field id="rv-status" label={t("recorded.videos.status")} error={errors.status}>
						<Select value={status} onChange={(e) => setStatus(e.target.value as VideoStatus)}>
							{VIDEO_STATUSES.map((s) => <option key={s} value={s}>{t(`recorded.videos.statuses.${s}`)}</option>)}
						</Select>
					</Field>
					<Field id="rv-thumb" label={t("recorded.videos.thumbnail")} error={errors.thumbnail}>
						<Input type="file" accept=".png,.jpg,.jpeg,.webp" onChange={(e) => setThumb(e.target.files?.[0])} />
					</Field>
					<Field id="rv-description" label={t("recorded.videos.description")} error={errors.description}>
						<Textarea maxLength={2000} value={description} onChange={(e) => setDescription(e.target.value)} />
					</Field>
					<DialogFooter className="mt-0">
						<DialogClose asChild><Button type="button" variant="outline">{t("recorded.cancel")}</Button></DialogClose>
						<Button type="submit" disabled={save.isPending}>{t("recorded.save")}</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

`VideosTab.tsx`:

```tsx
import { Film } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";
import {
	AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
	AlertDialogDescription, AlertDialogFooter, AlertDialogTitle, AlertDialogTrigger,
	Button, Card, CardContent, EmptyState, FormError, Select, Spinner, StatusChip, toast,
} from "@/ui";
import { formatDuration } from "./duration";
import { recordedErrorText } from "./errors";
import { useDeleteVideo, useMoveVideo, useVideos } from "./queries";
import { type PlaylistVideo, VIDEO_STATUSES } from "./schemas";
import { VideoDialog } from "./VideoDialog";

const TONE = { published: "live", draft: "neutral", hidden: "warning" } as const;

export function VideosTab({ playlistId }: { playlistId: number }) {
	const { t } = useTranslation();
	const can = useCan();
	const list = useVideos(playlistId);
	const move = useMoveVideo();
	const remove = useDeleteVideo();
	const [status, setStatus] = useState("");
	const [downloadable, setDownloadable] = useState("");
	const [editing, setEditing] = useState<PlaylistVideo>();
	const [adding, setAdding] = useState(false);
	const onError = (error: unknown) =>
		toast({ description: recordedErrorText(error, t), variant: "destructive" });

	if (list.isPending) return <div className="flex justify-center py-6"><Spinner /></div>;
	if (list.isError) return <FormError>{recordedErrorText(list.error, t)}</FormError>;
	const all = list.data;
	const rows = all.filter(
		(v) =>
			(!status || v.status === status) &&
			(!downloadable || String(v.downloadable) === downloadable),
	);

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-center gap-2">
				<Select aria-label={t("recorded.videos.status")} className="w-auto" value={status}
					onChange={(e) => setStatus(e.target.value)}>
					<option value="">{t("recorded.filters.any")}</option>
					{VIDEO_STATUSES.map((s) => (
						<option key={s} value={s}>{t(`recorded.videos.statuses.${s}`)}</option>
					))}
				</Select>
				<Select aria-label={t("recorded.videos.downloadable")} className="w-auto" value={downloadable}
					onChange={(e) => setDownloadable(e.target.value)}>
					<option value="">{t("recorded.filters.any")}</option>
					<option value="true">{t("recorded.filters.yes")}</option>
					<option value="false">{t("recorded.filters.no")}</option>
				</Select>
				{can("playlist_video.create") ? (
					<Button className="ms-auto" onClick={() => setAdding(true)}>{t("recorded.videos.add")}</Button>
				) : null}
			</div>
			{rows.length === 0 ? (
				<Card><CardContent><EmptyState icon={Film} title={t("recorded.videos.empty")} /></CardContent></Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{(["title", "kind", "duration", "status", "downloadable"] as const).map((c) => (
									<th key={c} scope="col" className="p-3 text-start font-medium">{t(`recorded.videos.${c}`)}</th>
								))}
								<th scope="col" className="p-3"><span className="sr-only">{t("recorded.videos.edit")}</span></th>
							</tr>
						</thead>
						<tbody>
							{rows.map((v) => {
								const index = all.findIndex((x) => x.id === v.id);
								return (
									<tr key={v.id} className="border-t border-border">
										<td className="p-3 font-medium">{v.title}</td>
										<td className="p-3">{t(`recorded.videos.kinds.${v.kind}`)}</td>
										<td className="p-3">{formatDuration(v.duration_seconds)}</td>
										<td className="p-3"><StatusChip tone={TONE[v.status]}>{t(`recorded.videos.statuses.${v.status}`)}</StatusChip></td>
										<td className="p-3">{v.downloadable ? t("recorded.videos.downloadable") : ""}</td>
										<td className="p-3">
											<div className="flex flex-wrap justify-end gap-2">
												{can("playlist_video.reorder") ? (
													<>
														<Button size="sm" variant="outline" aria-label={`${t("recorded.videos.moveUp")} ${v.title}`}
															disabled={index === 0 || move.isPending}
															onClick={() => move.mutate({ id: v.id, direction: "up" }, { onError })}>↑</Button>
														<Button size="sm" variant="outline" aria-label={`${t("recorded.videos.moveDown")} ${v.title}`}
															disabled={index === all.length - 1 || move.isPending}
															onClick={() => move.mutate({ id: v.id, direction: "down" }, { onError })}>↓</Button>
													</>
												) : null}
												{can("playlist_video.update") ? (
													<Button size="sm" variant="outline" onClick={() => setEditing(v)}>{t("recorded.videos.edit")}</Button>
												) : null}
												{can("playlist_video.delete") ? (
													<AlertDialog>
														<AlertDialogTrigger asChild>
															<Button size="sm" variant="outline">{t("recorded.delete")}</Button>
														</AlertDialogTrigger>
														<AlertDialogContent>
															<AlertDialogTitle>{v.title}</AlertDialogTitle>
															<AlertDialogDescription>{t("recorded.videos.deleteConfirm")}</AlertDialogDescription>
															<AlertDialogFooter>
																<AlertDialogCancel>{t("recorded.cancel")}</AlertDialogCancel>
																<AlertDialogAction onClick={() => remove.mutate(v.id, {
																	onError,
																	onSuccess: () => toast({ description: t("recorded.toast.videoDeleted"), variant: "success" }),
																})}>{t("recorded.delete")}</AlertDialogAction>
															</AlertDialogFooter>
														</AlertDialogContent>
													</AlertDialog>
												) : null}
											</div>
										</td>
									</tr>
								);
							})}
						</tbody>
					</table>
				</div>
			)}
			{adding ? <VideoDialog playlistId={playlistId} open onOpenChange={setAdding} /> : null}
			{editing ? (
				<VideoDialog key={editing.id} playlistId={playlistId} video={editing} open
					onOpenChange={(o) => { if (!o) setEditing(undefined); }} />
			) : null}
		</div>
	);
}
```

The duration column header reads "Duration (HH:MM:SS)" (`recorded.videos.duration`).

- [ ] **Step 4: Run** — `F pnpm vitest run src/features/recorded` → PASS.
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/recorded && git -C dashboard commit -m "feat(recorded): B7a videos tab and dialog" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 15: The Enrolments tab and dialog

**Files:**
- Create (replace the stub): `dashboard/src/features/recorded/EnrolmentsTab.tsx`, `EnrolmentDialog.tsx`, `EnrolmentsTab.test.tsx`, `EnrolmentDialog.test.tsx`

**Interfaces:**
- Consumes: `useEnrolments`, `useEnrol`, `useUpdateEnrolment`, `useEnrolmentAction`, `useDeleteEnrolment`, `useVideos`, `usePeople` (`@/features/people/queries`, `"students"`, `{ q, page_size: 20 }`; a row is `{ id (user id), user: { full_name } }`), `PAYMENT_METHODS` (`@/features/billing/schemas`), `toMinor`, `formatMoney`, `formatDay` (`@/lib/zoned-time`).
- Produces: `<EnrolmentsTab playlist />`, `<EnrolmentDialog playlist enrolment? open onOpenChange />`. Without an enrolment the dialog creates one; with one it edits notes, transaction number and the watched set, and offers revoke, restore and delete.

- [ ] **Step 1: Write the failing tests**

`EnrolmentDialog.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { peopleApi } from "@/features/people/api";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { enrolment, fileVideo, linkVideo, playlist } from "./fixtures";
import { EnrolmentDialog } from "./EnrolmentDialog";

vi.mock("./api", () => ({
	recordedApi: {
		enrol: vi.fn(), updateEnrolment: vi.fn(), enrolmentAction: vi.fn(),
		removeEnrolment: vi.fn(), videos: vi.fn(),
	},
}));
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});

const ALL = ["rc_enrolment.create", "rc_enrolment.update", "rc_enrolment.delete", "payment.create"];

function show(e?: typeof enrolment, codes = ALL) {
	return renderWithRouter(
		<CanProvider me={staffMe(...codes)}>
			<EnrolmentDialog playlist={playlist} enrolment={e} open onOpenChange={() => {}} />
		</CanProvider>,
	);
}

describe("EnrolmentDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue({
			count: 1, next: null, previous: null,
			results: [{ id: 21, user: { full_name: "Yusuf" } }],
		} as never);
		vi.mocked(recordedApi.videos).mockResolvedValue([linkVideo, fileVideo]);
	});

	it("a manual enrolment asks how it was paid and sends minor units", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.enrol).mockResolvedValue(enrolment);
		show();
		expect(screen.getByText("A manual enrolment is also recorded as a payment.")).toBeInTheDocument();
		await user.selectOptions(await screen.findByLabelText(/^Student/), "21");
		await user.type(screen.getByLabelText(/^Amount paid/), "15");
		await user.selectOptions(screen.getByLabelText(/^Paid by/), "cash");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(recordedApi.enrol).toHaveBeenCalledWith(4, expect.objectContaining({
			student_id: 21, method: "manual", amount_minor: 1500, billing_method: "cash",
		}));
	});

	it("free hides the payment fields; without payment.create manual is not offered", async () => {
		const user = userEvent.setup();
		show(undefined, ["rc_enrolment.create"]);
		expect(screen.queryByRole("option", { name: "Manual" })).toBeNull();
		expect(screen.queryByLabelText(/^Paid by/)).toBeNull();
		await user.selectOptions(await screen.findByLabelText(/^Student/), "21");
		vi.mocked(recordedApi.enrol).mockResolvedValue(enrolment);
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(recordedApi.enrol).toHaveBeenCalledWith(4, expect.objectContaining({ method: "free", amount_minor: 0 }));
	});

	it("edits the watched set and revokes", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.updateEnrolment).mockResolvedValue(enrolment);
		vi.mocked(recordedApi.enrolmentAction).mockResolvedValue({ ...enrolment, status: "revoked" });
		show(enrolment);
		const lesson2 = await screen.findByRole("checkbox", { name: "Lesson 2" });
		await user.click(lesson2);
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(recordedApi.updateEnrolment).toHaveBeenCalledWith(7, expect.objectContaining({
			watched_video_ids: [10, 11],
		}));
		await user.click(screen.getByRole("button", { name: "Revoke" }));
		expect(recordedApi.enrolmentAction).toHaveBeenCalledWith(7, "revoke");
	});
});
```

`EnrolmentsTab.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { EnrolmentsTab } from "./EnrolmentsTab";
import { enrolment, playlist } from "./fixtures";

vi.mock("./api", () => ({ recordedApi: { enrolments: vi.fn(), videos: vi.fn() } }));
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn().mockResolvedValue({ count: 0, next: null, previous: null, results: [] }) } };
});

function show(...codes: string[]) {
	return renderWithRouter(
		<CanProvider me={staffMe(...codes)}>
			<EnrolmentsTab playlist={playlist} />
		</CanProvider>,
	);
}

describe("EnrolmentsTab", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(recordedApi.enrolments).mockResolvedValue({
			count: 1, next: null, previous: null, results: [enrolment],
		});
		vi.mocked(recordedApi.videos).mockResolvedValue([]);
	});

	it("shows the row", async () => {
		show("rc_enrolment.view_any");
		expect(await screen.findByText("Yusuf")).toBeInTheDocument();
		expect(screen.getByText("Manual")).toBeInTheDocument();
		expect(screen.getByText("$15.00")).toBeInTheDocument();
		expect(screen.getByText("1 of 2 watched")).toBeInTheDocument();
		expect(screen.getByText("Active")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Enrol a student" })).toBeNull();
	});

	it("filters from page 1 and opens the dialog", async () => {
		const user = userEvent.setup();
		show("rc_enrolment.view_any", "rc_enrolment.create");
		await screen.findByText("Yusuf");
		await user.selectOptions(screen.getByLabelText("Method"), "free");
		expect(recordedApi.enrolments).toHaveBeenLastCalledWith(4, { page: 1, method: "free", status: "" });
		await user.click(screen.getByRole("button", { name: "Enrol a student" }));
		expect(screen.getByRole("dialog")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

`EnrolmentDialog.tsx`, the key logic:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { PAYMENT_METHODS } from "@/features/billing/schemas";
import { useCan } from "@/features/identity/permissions";
import { usePeople } from "@/features/people/queries";
import { toMinor } from "@/lib/money";
import {
	Button, Checkbox, Dialog, DialogContent, DialogDescription, DialogFooter, DialogTitle,
	Field, FormError, Input, Select, Textarea, toast,
} from "@/ui";
import { formErrors, recordedErrorText } from "./errors";
import { useDeleteEnrolment, useEnrol, useEnrolmentAction, useUpdateEnrolment, useVideos } from "./queries";
import type { Enrolment, Playlist } from "./schemas";

const INPUTS = ["student", "method", "amount_minor", "billing_method", "paid_on",
	"reference", "transaction_number", "notes", "watched_video_ids"] as const;

export function EnrolmentDialog({ playlist, enrolment, open, onOpenChange }: {
	playlist: Playlist;
	enrolment?: Enrolment;
	open: boolean;
	onOpenChange: (open: boolean) => void;
}) {
	const { t } = useTranslation();
	const can = useCan();
	const canPay = can("payment.create");
	const enrol = useEnrol(playlist.id);
	const update = useUpdateEnrolment();
	const action = useEnrolmentAction();
	const remove = useDeleteEnrolment();
	const videos = useVideos(playlist.id);
	const [search, setSearch] = useState("");
	const people = usePeople<{ id: number; user: { full_name: string } }>(
		"students", { q: search, page_size: 20 }, { enabled: !enrolment },
	);
	const [student, setStudent] = useState("");
	const [method, setMethod] = useState<"manual" | "free">(canPay ? "manual" : "free");
	const [amount, setAmount] = useState("");
	const [billingMethod, setBillingMethod] = useState("");
	const [paidOn, setPaidOn] = useState("");
	const [reference, setReference] = useState("");
	const [transaction, setTransaction] = useState(enrolment?.transaction_number ?? "");
	const [notes, setNotes] = useState(enrolment?.notes ?? "");
	const [watched, setWatched] = useState<number[]>(enrolment?.watched_video_ids ?? []);
	const [errors, setErrors] = useState<Record<string, string>>({});
	const [formError, setFormError] = useState<string>();

	function fail(error: unknown) {
		const out = formErrors(error, t, INPUTS);
		setErrors(out.fields);
		setFormError(out.form);
	}

	async function submit(e: React.FormEvent) {
		e.preventDefault();
		setFormError(undefined);
		try {
			if (enrolment) {
				await update.mutateAsync({ id: enrolment.id, body: {
					notes, transaction_number: transaction,
					watched_video_ids: [...watched].sort((a, b) => a - b),
				} });
			} else {
				const next: Record<string, string> = {};
				if (!student) next.student = t("recorded.form.required");
				if (method === "manual") {
					if (!amount.trim() || toMinor(amount, playlist.currency) <= 0) next.amount_minor = t("recorded.form.required");
					if (!billingMethod) next.billing_method = t("recorded.form.required");
				}
				setErrors(next);
				if (Object.keys(next).length > 0) return;
				await enrol.mutateAsync({
					student_id: Number(student), method,
					amount_minor: method === "manual" ? toMinor(amount, playlist.currency) : 0,
					billing_method: method === "manual" ? billingMethod : "",
					paid_on: paidOn || null, reference, transaction_number: transaction, notes,
				});
			}
			toast({ description: t("recorded.enrolments.saved"), variant: "success" });
			onOpenChange(false);
		} catch (error) {
			fail(error);
		}
	}

	async function run(fn: () => Promise<unknown>) {
		try {
			await fn();
			onOpenChange(false);
		} catch (error) {
			toast({ description: recordedErrorText(error, t), variant: "destructive" });
		}
	}
	const money = (minor: number, currency: string) =>
		formatMoney(minor, currency, i18n.language);
	const editable = (videos.data ?? []).filter((v) => v.status !== "draft");

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent>
				<DialogTitle>
					{enrolment ? enrolment.student.full_name : t("recorded.enrolments.add")}
				</DialogTitle>
				<DialogDescription>{playlist.title}</DialogDescription>
				<form onSubmit={submit} noValidate className="mt-4 flex flex-col gap-4">
					{formError ? <FormError>{formError}</FormError> : null}
					{enrolment ? (
						<p className="text-sm text-muted-foreground">
							{t(`recorded.enrolments.methods.${enrolment.method}`)} ·{" "}
							{money(enrolment.amount_minor, enrolment.currency)} ·{" "}
							{t(`recorded.enrolments.statuses.${enrolment.status}`)}
						</p>
					) : (
						<>
							<Input
								aria-label={t("recorded.enrolments.studentSearch")}
								placeholder={t("recorded.enrolments.studentSearch")}
								value={search}
								onChange={(e) => setSearch(e.target.value)}
							/>
							<Field id="re-student" label={t("recorded.enrolments.student")} error={errors.student} required>
								<Select value={student} onChange={(e) => setStudent(e.target.value)}>
									<option value="" />
									{(people.data?.results ?? []).map((p) => (
										<option key={p.id} value={p.id}>{p.user.full_name}</option>
									))}
								</Select>
							</Field>
							<Field id="re-method" label={t("recorded.enrolments.method")} error={errors.method} required>
								<Select value={method} onChange={(e) => setMethod(e.target.value as "manual" | "free")}>
									{canPay ? <option value="manual">{t("recorded.enrolments.methods.manual")}</option> : null}
									<option value="free">{t("recorded.enrolments.methods.free")}</option>
								</Select>
							</Field>
							{method === "manual" ? (
								<>
									<p className="text-sm text-muted-foreground">{t("recorded.enrolments.manualHint")}</p>
									<Field id="re-amount" label={`${t("recorded.enrolments.amount")} (${playlist.currency})`} error={errors.amount_minor} required>
										<Input inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
									</Field>
									<Field id="re-billing" label={t("recorded.enrolments.billingMethod")} error={errors.billing_method} required>
										<Select value={billingMethod} onChange={(e) => setBillingMethod(e.target.value)}>
											<option value="" />
											{PAYMENT_METHODS.map((m) => (
												<option key={m} value={m}>{t(`billing.methods.${m}`)}</option>
											))}
										</Select>
									</Field>
									<Field id="re-paid-on" label={t("recorded.enrolments.paidOn")} error={errors.paid_on}>
										<Input type="date" value={paidOn} onChange={(e) => setPaidOn(e.target.value)} />
									</Field>
									<Field id="re-reference" label={t("recorded.enrolments.reference")} error={errors.reference}>
										<Input maxLength={120} value={reference} onChange={(e) => setReference(e.target.value)} />
									</Field>
								</>
							) : null}
						</>
					)}
					{enrolment ? (
						<fieldset className="flex flex-col gap-2">
							<legend className="mb-1 text-sm font-medium">{t("recorded.enrolments.watched")}</legend>
							{errors.watched_video_ids ? <FormError>{errors.watched_video_ids}</FormError> : null}
							{editable.map((v) => (
								<div key={v.id} className="flex items-center gap-2">
									<Checkbox
										id={`re-watched-${v.id}`}
										checked={watched.includes(v.id)}
										onCheckedChange={(on) =>
											setWatched((old) => (on ? [...old, v.id] : old.filter((x) => x !== v.id)))
										}
									/>
									<label htmlFor={`re-watched-${v.id}`} className="text-sm">{v.title}</label>
								</div>
							))}
						</fieldset>
					) : null}
					<Field id="re-transaction" label={t("recorded.enrolments.transaction")} error={errors.transaction_number}>
						<Input maxLength={120} value={transaction} onChange={(e) => setTransaction(e.target.value)} />
					</Field>
					<Field id="re-notes" label={t("recorded.enrolments.notes")} error={errors.notes}>
						<Textarea maxLength={2000} value={notes} onChange={(e) => setNotes(e.target.value)} />
					</Field>
					<DialogFooter className="mt-0 flex-wrap">
						{enrolment && can("rc_enrolment.update") ? (
							<Button type="button" variant="outline"
								onClick={() => run(() => action.mutateAsync({
									id: enrolment.id,
									action: enrolment.status === "active" ? "revoke" : "restore",
								}))}>
								{t(enrolment.status === "active" ? "recorded.enrolments.revoke" : "recorded.enrolments.restore")}
							</Button>
						) : null}
						{enrolment && can("rc_enrolment.delete") && (enrolment.method === "manual" || enrolment.method === "free") ? (
							<Button type="button" variant="outline" onClick={() => run(() => remove.mutateAsync(enrolment.id))}>
								{t("recorded.delete")}
							</Button>
						) : null}
						<Button type="button" variant="outline" onClick={() => onOpenChange(false)}>{t("recorded.cancel")}</Button>
						<Button type="submit" disabled={enrol.isPending || update.isPending}>{t("recorded.save")}</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Add `formatMoney` to the imports (`import { formatMoney, toMinor } from "@/lib/money";`) and `i18n` to `useTranslation()`'s destructuring. The `editable` list uses published and hidden videos, never drafts (A-11).


`EnrolmentsTab.tsx`:

```tsx
import { Users } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";
import { formatMoney } from "@/lib/money";
import { formatDay } from "@/lib/zoned-time";
import { Button, Card, CardContent, EmptyState, FormError, Select, Spinner, StatusChip } from "@/ui";
import { EnrolmentDialog } from "./EnrolmentDialog";
import { recordedErrorText } from "./errors";
import { useEnrolments } from "./queries";
import type { Enrolment, Playlist } from "./schemas";

const METHODS = ["manual", "free", "stripe", "paypal", "code"] as const;

export function EnrolmentsTab({ playlist }: { playlist: Playlist }) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const [page, setPage] = useState(1);
	const [method, setMethod] = useState("");
	const [status, setStatus] = useState("");
	const [open, setOpen] = useState<Enrolment | "new">();
	const list = useEnrolments(playlist.id, { page, method, status });
	const filter = (set: (v: string) => void) => (e: { target: { value: string } }) => {
		set(e.target.value);
		setPage(1);
	};

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-center gap-2">
				<Select aria-label={t("recorded.enrolments.method")} className="w-auto" value={method} onChange={filter(setMethod)}>
					<option value="">{t("recorded.filters.any")}</option>
					{METHODS.map((m) => <option key={m} value={m}>{t(`recorded.enrolments.methods.${m}`)}</option>)}
				</Select>
				<Select aria-label={t("recorded.enrolments.status")} className="w-auto" value={status} onChange={filter(setStatus)}>
					<option value="">{t("recorded.filters.any")}</option>
					<option value="active">{t("recorded.enrolments.statuses.active")}</option>
					<option value="revoked">{t("recorded.enrolments.statuses.revoked")}</option>
				</Select>
				{can("rc_enrolment.create") ? (
					<Button className="ms-auto" onClick={() => setOpen("new")}>{t("recorded.enrolments.add")}</Button>
				) : null}
			</div>
			{list.isPending ? (
				<div className="flex justify-center py-6"><Spinner /></div>
			) : list.isError ? (
				<FormError>{recordedErrorText(list.error, t)}</FormError>
			) : list.data.results.length === 0 ? (
				<Card><CardContent><EmptyState icon={Users} title={t("recorded.enrolments.empty")} /></CardContent></Card>
			) : (
				<>
					<div className="overflow-x-auto rounded-lg border border-border">
						<table className="w-full text-sm">
							<thead className="bg-secondary text-muted-foreground">
								<tr>
									{(["student", "method", "amount", "enrolledOn", "progress", "status"] as const).map((c) => (
										<th key={c} scope="col" className="p-3 text-start font-medium">{t(`recorded.enrolments.${c}`)}</th>
									))}
									<th scope="col" className="p-3"><span className="sr-only">{t("recorded.enrolments.open")}</span></th>
								</tr>
							</thead>
							<tbody>
								{list.data.results.map((e) => (
									<tr key={e.id} className="border-t border-border">
										<td className="p-3 font-medium">{e.student.full_name}</td>
										<td className="p-3">{t(`recorded.enrolments.methods.${e.method}`)}</td>
										<td className="p-3">{e.amount_minor === 0 ? t("recorded.free") : formatMoney(e.amount_minor, e.currency, i18n.language)}</td>
										<td className="p-3">{formatDay(e.enrolled_at.slice(0, 10), i18n.language)}</td>
										<td className="p-3">{t("recorded.my.progress", e.progress)}</td>
										<td className="p-3">
											<StatusChip tone={e.status === "active" ? "live" : "neutral"}>
												{t(`recorded.enrolments.statuses.${e.status}`)}
											</StatusChip>
										</td>
										<td className="p-3 text-end">
											<Button size="sm" variant="outline" onClick={() => setOpen(e)}>{t("recorded.enrolments.open")}</Button>
										</td>
									</tr>
								))}
							</tbody>
						</table>
					</div>
					<div className="flex justify-end gap-2">
						<Button size="sm" variant="outline" aria-label={t("recorded.enrolments.previous")} disabled={!list.data.previous} onClick={() => setPage((p) => p - 1)}>‹</Button>
						<Button size="sm" variant="outline" aria-label={t("recorded.enrolments.next")} disabled={!list.data.next} onClick={() => setPage((p) => p + 1)}>›</Button>
					</div>
				</>
			)}
			{open ? (
				<EnrolmentDialog key={open === "new" ? "new" : open.id} playlist={playlist}
					enrolment={open === "new" ? undefined : open} open
					onOpenChange={(o) => { if (!o) setOpen(undefined); }} />
			) : null}
		</div>
	);
}
```


- [ ] **Step 4: Run** — `F pnpm vitest run src/features/recorded` → PASS.
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/recorded && git -C dashboard commit -m "feat(recorded): B7a enrolments tab and dialog" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 16: Student and parent pages: My recorded courses and the player

**Files:**
- Create: `dashboard/src/features/recorded/MyCourses.tsx`, `MyCourses.test.tsx`, `CoursePlayer.tsx`, `CoursePlayer.test.tsx`, `VideoPane.tsx`, `VideoPane.test.tsx`, `dashboard/src/routes/_authed/learning.recorded.index.tsx`, `dashboard/src/routes/_authed/learning.recorded.$playlistId.tsx`
- Modify: `dashboard/src/features/shell/nav.ts` (B7 marker), `features/recorded/index.ts`

**Interfaces:**
- Consumes: `useMe` (`@/features/identity/queries`: `role`, `children[]` with user `id`), `useMyCourses`, `useMyCourse`, `useSetWatched`, `recordedApi.fileUrl`, `Meter` (`role="progressbar"`).
- Produces: `<MyCourses />` (cards linking to `/learning/recorded/$playlistId?student=` for a parent), `<CoursePlayer playlistId student? />`, `<VideoPane video readOnly onEnded />`.

- [ ] **Step 1: Write the failing tests**

`VideoPane.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { myPlaylist } from "./fixtures";
import { VideoPane } from "./VideoPane";

const [yt, file, live] = myPlaylist.videos;

describe("VideoPane", () => {
	it("embeds YouTube from the validated id only", () => {
		const { container } = render(<VideoPane video={yt} onEnded={() => {}} />);
		const frame = container.querySelector("iframe");
		expect(frame?.getAttribute("src")).toBe("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ");
		expect(frame?.getAttribute("title")).toBe("Lesson 1");
	});

	it("embeds Vimeo by id", () => {
		const { container } = render(
			<VideoPane video={{ ...yt, embed_provider: "vimeo", embed_id: "123" }} onEnded={() => {}} />,
		);
		expect(container.querySelector("iframe")?.getAttribute("src")).toBe("https://player.vimeo.com/video/123");
	});

	it("plays a file natively and reports its end", () => {
		const onEnded = vi.fn();
		const { container } = render(<VideoPane video={file} onEnded={onEnded} />);
		const el = container.querySelector("video") as HTMLVideoElement;
		expect(el.getAttribute("src")).toBe("/api/v1/recorded/videos/11/file/");
		el.dispatchEvent(new Event("ended"));
		expect(onEnded).toHaveBeenCalled();
		expect(screen.getByRole("link", { name: "Download" })).toHaveAttribute(
			"href", "/api/v1/recorded/videos/11/file/?download=1",
		);
	});

	it("opens an external or live link in a new tab, never embedded", () => {
		const { container } = render(<VideoPane video={live} onEnded={() => {}} />);
		expect(container.querySelector("iframe")).toBeNull();
		const link = screen.getByRole("link", { name: "Open video" });
		expect(link).toHaveAttribute("href", "https://example.com/live");
		expect(link).toHaveAttribute("target", "_blank");
		expect(link).toHaveAttribute("rel", "noopener noreferrer");
	});

	it("read-only shows no player", () => {
		const { container } = render(<VideoPane video={file} readOnly onEnded={() => {}} />);
		expect(container.querySelector("video")).toBeNull();
	});
});
```

`CoursePlayer.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { toast } from "@/ui";
import { recordedApi } from "./api";
import { CoursePlayer } from "./CoursePlayer";
import { myPlaylist } from "./fixtures";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		recordedApi: { ...actual.recordedApi, myCourse: vi.fn(), setWatched: vi.fn() },
	};
});
vi.mock("@/ui", async (orig) => ({
	...(await orig<typeof import("@/ui")>()),
	toast: vi.fn(),
}));

const lessons = () =>
	within(screen.getByRole("navigation", { name: "Lessons" })).getAllByRole("button");

describe("CoursePlayer", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(recordedApi.myCourse).mockResolvedValue(myPlaylist);
	});

	it("lists lessons in order and opens the first unwatched", async () => {
		renderWithRouter(<CoursePlayer playlistId={4} />);
		await screen.findByRole("heading", { name: "Lesson 2" });
		expect(lessons().map((b) => b.textContent)).toEqual([
			expect.stringContaining("Lesson 1"),
			expect.stringContaining("Lesson 2"),
			expect.stringContaining("Live Q&A"),
		]);
		expect(within(lessons()[0]).getByText("Watched")).toBeInTheDocument();
		expect(document.querySelector("video")).not.toBeNull();
	});

	it("marks watched at once and rolls back on an error", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.setWatched).mockRejectedValue(new Error("boom"));
		renderWithRouter(<CoursePlayer playlistId={4} />);
		await screen.findByRole("heading", { name: "Lesson 2" });
		await user.click(screen.getByLabelText("Mark as watched"));
		expect(recordedApi.setWatched).toHaveBeenCalledWith(11, true);
		await vi.waitFor(() => expect(toast).toHaveBeenCalled());
		expect(within(lessons()[1]).queryByText("Watched")).toBeNull();
	});

	it("shows the course panels", async () => {
		renderWithRouter(<CoursePlayer playlistId={4} />);
		expect(await screen.findByText("About this course")).toBeInTheDocument();
		expect(screen.getByText("Week by week.")).toBeInTheDocument();
		expect(screen.getByText("Personal use only.")).toBeInTheDocument();
	});

	it("is read-only for a parent", async () => {
		renderWithRouter(<CoursePlayer playlistId={4} student={21} />);
		expect(await screen.findByText("You are viewing your child's course.")).toBeInTheDocument();
		expect(screen.queryByLabelText("Mark as watched")).toBeNull();
		expect(document.querySelector("video, iframe")).toBeNull();
		expect(recordedApi.myCourse).toHaveBeenCalledWith(4, 21);
	});
});
```

The optimistic flip is tested through the rollback. A success test would also assert the tick appears; add one with `setWatched` resolved if branch coverage needs it.

`MyCourses.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { useMe } from "@/features/identity/queries";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { MyCourses } from "./MyCourses";

vi.mock("./api", () => ({ recordedApi: { my: vi.fn() } }));
vi.mock("@/features/identity/queries", async (orig) => ({
	...(await orig<typeof import("@/features/identity/queries")>()),
	useMe: vi.fn(),
}));

const course = {
	enrolment_id: 7,
	playlist: { id: 4, title: "Tajweed, level 1", thumbnail_url: "/t.png", content_language: "en" as const },
	progress: { watched: 1, total: 3 },
};

function asMe(data: object) {
	vi.mocked(useMe).mockReturnValue({ data, isPending: false } as never);
}

describe("MyCourses", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(recordedApi.my).mockResolvedValue([course]);
	});

	it("shows a student's courses with progress", async () => {
		asMe({ id: 21, role: "student" });
		renderWithRouter(<MyCourses />);
		expect(await screen.findByRole("link", { name: /Tajweed, level 1/ })).toHaveAttribute(
			"href", expect.stringContaining("/learning/recorded/4"),
		);
		expect(screen.getByRole("progressbar", { name: "1 of 3 watched" })).toBeInTheDocument();
		expect(recordedApi.my).toHaveBeenCalledWith(undefined);
	});

	it("a parent picks a child", async () => {
		const user = userEvent.setup();
		asMe({ id: 30, role: "parent", children: [
			{ id: 21, full_name: "Yusuf", student_profile_id: 1 },
			{ id: 22, full_name: "Maryam", student_profile_id: 2 },
		] });
		renderWithRouter(<MyCourses />);
		await screen.findByRole("link", { name: /Tajweed/ });
		expect(recordedApi.my).toHaveBeenCalledWith(21);
		await user.selectOptions(screen.getByLabelText("Child"), "22");
		expect(recordedApi.my).toHaveBeenLastCalledWith(22);
		expect(await screen.findByRole("link", { name: /Tajweed/ })).toHaveAttribute(
			"href", expect.stringContaining("student=22"),
		);
	});

	it("shows an empty state", async () => {
		asMe({ id: 21, role: "student" });
		vi.mocked(recordedApi.my).mockResolvedValue([]);
		renderWithRouter(<MyCourses />);
		expect(await screen.findByText("You are not enrolled in any recorded course yet.")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

`VideoPane.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { buttonVariants } from "@/ui";
import { recordedApi } from "./api";
import type { MyVideo } from "./schemas";

/** Spec B7-7, A-5: only YouTube and Vimeo embed, from a server-validated id,
 * through a fixed template; any other link opens in a new tab. */
function embedSrc(v: MyVideo): string | undefined {
	if (v.embed_provider === "youtube") return `https://www.youtube-nocookie.com/embed/${encodeURIComponent(v.embed_id)}`;
	if (v.embed_provider === "vimeo") return `https://player.vimeo.com/video/${encodeURIComponent(v.embed_id)}`;
	return undefined;
}

export function VideoPane({ video, readOnly = false, onEnded }: {
	video: MyVideo;
	readOnly?: boolean;
	onEnded: () => void;
}) {
	const { t } = useTranslation();
	if (readOnly) return null;
	const src = embedSrc(video);
	return (
		<div className="flex flex-col gap-3">
			{video.kind === "file" && video.has_file ? (
				<video controls preload="metadata" className="aspect-video w-full rounded-lg bg-black"
					src={recordedApi.fileUrl(video.id)} onEnded={onEnded}
					controlsList={video.downloadable ? undefined : "nodownload"}>
					<track kind="captions" />
				</video>
			) : src ? (
				<iframe title={video.title} src={src} className="aspect-video w-full rounded-lg"
					allow="encrypted-media; picture-in-picture; fullscreen" allowFullScreen
					referrerPolicy="strict-origin-when-cross-origin" />
			) : (
				<a href={video.url} target="_blank" rel="noopener noreferrer"
					className={buttonVariants({ className: "self-start" })}>
					{t("recorded.my.openVideo")}
				</a>
			)}
			{video.kind === "file" && video.downloadable ? (
				<a href={recordedApi.fileUrl(video.id, true)}
					className={buttonVariants({ variant: "outline", className: "self-start" })}>
					{t("recorded.my.download")}
				</a>
			) : null}
		</div>
	);
}
```

`CoursePlayer.tsx`:

```tsx
import { Check } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { Checkbox, FormError, Meter, PageHeader, Spinner, toast } from "@/ui";
import { formatDuration } from "./duration";
import { recordedErrorText } from "./errors";
import { useMyCourse, useSetWatched } from "./queries";
import { VideoPane } from "./VideoPane";

export function CoursePlayer({ playlistId, student }: { playlistId: number; student?: number }) {
	const { t } = useTranslation();
	const readOnly = student !== undefined;
	const course = useMyCourse(playlistId, student);
	const watch = useSetWatched(playlistId);
	const [picked, setPicked] = useState<number>();
	usePageTitle(course.data?.playlist.title ?? t("recorded.nav.mine"));

	if (course.isPending) return <div className="flex justify-center py-6"><Spinner /></div>;
	if (course.isError) return <FormError>{recordedErrorText(course.error, t)}</FormError>;
	const { playlist, videos } = course.data;
	const watchedCount = videos.filter((v) => v.watched).length;
	const current =
		videos.find((v) => v.id === picked) ?? videos.find((v) => !v.watched) ?? videos[0];
	const mark = (videoId: number, watched: boolean) =>
		watch.mutate(
			{ videoId, watched },
			{ onError: (error) => toast({ description: recordedErrorText(error, t), variant: "destructive" }) },
		);

	return (
		<div className="flex flex-col gap-4">
			<PageHeader title={playlist.title} />
			{readOnly ? <p className="text-sm text-muted-foreground">{t("recorded.my.readOnly")}</p> : null}
			<Meter role="progressbar" label={t("recorded.my.progress", { watched: watchedCount, total: videos.length })}
				value={watchedCount} max={videos.length} />
			<div className="grid gap-4 lg:grid-cols-[18rem_1fr]">
				<nav aria-label={t("recorded.my.lessons")}>
					<ol className="flex flex-col gap-1">
						{videos.map((v) => (
							<li key={v.id}>
								<button type="button" aria-current={v.id === current?.id ? "true" : undefined}
									onClick={() => setPicked(v.id)}
									className="flex w-full items-center justify-between gap-2 rounded-md p-2 text-start text-sm hover:bg-secondary aria-[current=true]:bg-secondary">
									<span>{v.title}</span>
									<span className="flex items-center gap-1 text-muted-foreground">
										{formatDuration(v.duration_seconds)}
										{v.watched ? (
											<>
												<Check aria-hidden className="size-4 text-success" />
												<span className="sr-only">{t("recorded.my.watched")}</span>
											</>
										) : null}
									</span>
								</button>
							</li>
						))}
					</ol>
				</nav>
				{current ? (
					<section className="flex flex-col gap-3">
						<VideoPane video={current} readOnly={readOnly}
							onEnded={() => { if (!current.watched) mark(current.id, true); }} />
						<h2 className="text-lg font-semibold">{current.title}</h2>
						{current.description ? <p className="whitespace-pre-line text-sm">{current.description}</p> : null}
						{readOnly ? null : (
							<div className="flex items-center gap-2">
								<Checkbox id="rc-mark" checked={current.watched} onCheckedChange={(on) => mark(current.id, on)} />
								<label htmlFor="rc-mark" className="text-sm">{t("recorded.my.markWatched")}</label>
							</div>
						)}
					</section>
				) : null}
			</div>
			<details className="rounded-lg border border-border p-3">
				<summary className="cursor-pointer font-medium">{t("recorded.my.about")}</summary>
				<p className="mt-2 whitespace-pre-line text-sm">{playlist.content || playlist.description}</p>
			</details>
			<details className="rounded-lg border border-border p-3">
				<summary className="cursor-pointer font-medium">{t("recorded.my.terms")}</summary>
				<p className="mt-2 whitespace-pre-line text-sm">{playlist.terms}</p>
			</details>
		</div>
	);
}
```

Check that `PageHeader` is exported from `@/ui` (it is: `ui/index.ts`) and that `text-success` is an existing token class (`F node scripts/check-colors.mjs` passes). Otherwise use `text-primary`.

`MyCourses.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Clapperboard } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useMe } from "@/features/identity/queries";
import { Card, CardContent, CardGrid, EmptyState, Field, FormError, Meter, Select, Spinner } from "@/ui";
import { recordedErrorText } from "./errors";
import { useMyCourses } from "./queries";

export function MyCourses() {
	const { t } = useTranslation();
	const { data: me, isPending } = useMe();
	const children = me?.children ?? [];
	const isParent = me?.role === "parent";
	const [picked, setPicked] = useState<number>();
	const child = isParent ? (picked ?? children[0]?.id) : undefined;
	const list = useMyCourses(child, !isPending && (!isParent || child !== undefined));

	if (isPending || (list.isPending && list.fetchStatus !== "idle"))
		return <div className="flex justify-center py-6"><Spinner /></div>;
	return (
		<div className="flex flex-col gap-4">
			{isParent && children.length > 0 ? (
				<Field id="rc-child" label={t("recorded.my.childPicker")}>
					<Select className="w-auto" value={child ?? ""} onChange={(e) => setPicked(Number(e.target.value))}>
						{children.map((c) => <option key={c.id} value={c.id}>{c.full_name}</option>)}
					</Select>
				</Field>
			) : null}
			{list.isError ? (
				<FormError>{recordedErrorText(list.error, t)}</FormError>
			) : !list.data || list.data.length === 0 ? (
				<Card><CardContent><EmptyState icon={Clapperboard} title={t("recorded.my.empty")} /></CardContent></Card>
			) : (
				<CardGrid>
					{list.data.map((c) => (
						<Card key={c.enrolment_id}>
							<CardContent className="flex flex-col gap-3 pt-4">
								<Link to="/learning/recorded/$playlistId" params={{ playlistId: String(c.playlist.id) }}
									search={child === undefined ? {} : { student: child }}
									className="flex flex-col gap-2 font-medium">
									<img src={c.playlist.thumbnail_url} alt="" className="aspect-video w-full rounded object-cover" />
									{c.playlist.title}
								</Link>
								<Meter role="progressbar" label={t("recorded.my.progress", c.progress)}
									value={c.progress.watched} max={c.progress.total} />
							</CardContent>
						</Card>
					))}
				</CardGrid>
			)}
		</div>
	);
}
```

Routes:

```tsx
// learning.recorded.index.tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { MyCourses } from "@/features/recorded";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/learning/recorded/")({
	staticData: { feature: "recorded_courses" },
	component: function MyRecordedRoute() {
		const { t } = useTranslation();
		usePageTitle(t("recorded.nav.mine"));
		return (
			<>
				<PageHeader title={t("recorded.nav.mine")} />
				<MyCourses />
			</>
		);
	},
});
```

```tsx
// learning.recorded.$playlistId.tsx
import { createFileRoute } from "@tanstack/react-router";
import { CoursePlayer } from "@/features/recorded";

export const Route = createFileRoute("/_authed/learning/recorded/$playlistId")({
	staticData: { feature: "recorded_courses" },
	validateSearch: (search: Record<string, unknown>): { student?: number } => {
		const student = Number(search.student);
		return Number.isInteger(student) && student > 0 ? { student } : {};
	},
	component: function RecordedPlayerRoute() {
		const { playlistId } = Route.useParams();
		const { student } = Route.useSearch();
		return <CoursePlayer playlistId={Number(playlistId)} student={student} />;
	},
});
```

(`CoursePlayer` sets the page title to the course title with `usePageTitle` and renders its own `PageHeader`. `validateSearch` follows `routes/pay.return.tsx`'s function style.)

`nav.ts`, under `// ── phase B7 ──` after the office item:

```ts
	{
		to: "/learning/recorded",
		labelKey: "recorded.nav.mine",
		icon: Clapperboard,
		group: "learning",
		requiresRole: ["student", "parent"],
		feature: "recorded_courses",
	},
```

Regenerate `routeTree.gen.ts`.

- [ ] **Step 4: Run** — `F pnpm vitest run src/features/recorded src/features/shell src/test/a11y.test.tsx` → PASS; `F pnpm tsc --noEmit`; `F pnpm lint`.
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/recorded src/routes/_authed/learning.recorded.index.tsx "src/routes/_authed/learning.recorded.\$playlistId.tsx" src/features/shell/nav.ts src/routeTree.gen.ts && git -C dashboard commit -m "feat(recorded): B7a student player and parent view" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

Dashboard checkpoint: `F pnpm test:coverage` meets the gates; `src/features/recorded` itself ≥ 80 % lines.

---

### Task 17: e2e journey

**Files:**
- Create: `dashboard/e2e/b7-recorded.spec.ts`

**Interfaces:**
- Consumes: `e2e/fixtures.ts` (`DEMO_URL`, `DEMO_ADMIN`, `DEV_PASSWORD`, `expectLoggedIn`, `acceptInvite`, `postAsAdmin`), `e2e/manage.ts` (`manage("set_features", "demo", "--on", "recorded_courses")`).

- [ ] **Step 1: Write the spec** (it fails until the stack runs the B7a build)

```ts
import { type Browser, expect, type Locator, type Page, test } from "@playwright/test";
import { acceptInvite, DEMO_ADMIN, DEMO_URL, DEV_PASSWORD, expectLoggedIn, postAsAdmin } from "./fixtures";
import { manage } from "./manage";

// Plan 49 (B7a, spec 2026-10-08): a recorded course end to end. Names are
// stamped so a second run on the same database works too.

const STUDENT_PASSWORD = "e2e-Student-B7a";

async function visit(page: Page, url: string, ready: Locator) {
	for (let attempt = 1; ; attempt++) {
		await page.goto(url);
		try {
			await expect(ready).toBeVisible({ timeout: 15_000 });
			return;
		} catch (error) {
			if (attempt === 2) throw error;
			test.info().annotations.push({ type: "retry", description: url });
		}
	}
}

async function signInStudent(browser: Browser, email: string, name: string) {
	const context = await browser.newContext();
	const page = await context.newPage();
	await visit(page, `${DEMO_URL}/app/forgot-password`, page.getByRole("textbox", { name: "Email" }));
	await page.getByRole("textbox", { name: "Email" }).fill(email);
	const requested = Date.now();
	await page.getByRole("button", { name: "Send reset link" }).click();
	await expect(page.getByText("If that account exists, a reset link is on its way.")).toBeVisible();
	await context.close();
	return acceptInvite(browser, email, STUDENT_PASSWORD, name, { after: requested });
}

test.describe("B7a recorded courses", () => {
	test.beforeAll(() => {
		manage("set_features", "demo", "--on", "recorded_courses");
	});

	test("office builds a course, enrols a student who watches a lesson", async ({ page, browser }) => {
		test.setTimeout(240_000);
		const stamp = Date.now();
		const title = `Course ${stamp}`;
		const student = `B7 Student ${stamp}`;
		const email = `b7a-${stamp}@demo.test`;

		await visit(page, `${DEMO_URL}/app/login`, page.getByRole("textbox", { name: /email/i }));
		await page.getByRole("textbox", { name: /email/i }).fill(DEMO_ADMIN);
		await page.getByRole("textbox", { name: /password/i }).fill(DEV_PASSWORD);
		await page.getByRole("button", { name: /sign in/i }).click();
		await expectLoggedIn(page, /demo academy admin/i);
		await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

		const made = await postAsAdmin(page, "people/students/", {
			user: { full_name: student, email },
			profile: {},
		});
		expect(made.status(), await made.text()).toBe(201);

		// 1. Create the course in the form
		await visit(page, `${DEMO_URL}/app/catalogue/recorded/new`, page.getByLabel(/^Title/));
		await page.getByLabel(/^Thumbnail/).setInputFiles({
			name: "t.png",
			mimeType: "image/png",
			buffer: Buffer.from(
				"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC",
				"base64",
			),
		});
		await page.getByLabel(/^Title/).fill(title);
		await page.getByLabel(/^Slug/).fill(`course-${stamp}`);
		await page.getByLabel(/^Description/).fill("An e2e course.");
		await page.getByLabel(/^Code/).fill(`E2E-${stamp}`);
		await page.getByLabel(/^Terms and conditions/).fill("Terms.");
		await page.getByLabel("Published").check();
		await page.getByRole("button", { name: "Save" }).click();
		await expect(page.getByRole("tab", { name: "Videos" })).toBeVisible();

		// 2. Add a published link video
		await page.getByRole("tab", { name: "Videos" }).click();
		await page.getByRole("button", { name: "Add video" }).click();
		const dialog = page.getByRole("dialog");
		await dialog.getByLabel(/^Code/).fill("L1");
		await dialog.getByLabel(/^Title/).fill("Lesson one");
		await dialog.getByLabel(/^Slug/).fill("lesson-one");
		await dialog.getByLabel(/^Video link/).fill("https://youtu.be/dQw4w9WgXcQ");
		await dialog.getByLabel(/^Duration/).fill("00:05:00");
		await dialog.getByLabel(/^Status/).selectOption("published");
		await dialog.getByRole("button", { name: "Save" }).click();
		await expect(page.getByText("Lesson one")).toBeVisible();

		// 3. Enrol the student free
		await page.getByRole("tab", { name: "Enrolments" }).click();
		await page.getByRole("button", { name: "Enrol a student" }).click();
		const enrol = page.getByRole("dialog");
		await enrol.getByLabel("Search students").fill(student);
		await enrol.getByLabel(/^Student/).selectOption({ label: student });
		await enrol.getByLabel(/^Method/).selectOption("free");
		await enrol.getByRole("button", { name: "Save" }).click();
		await expect(page.getByText(student)).toBeVisible();

		// 4. The student watches it
		const learner = await signInStudent(browser, email, student);
		await visit(learner, `${DEMO_URL}/app/learning/recorded`, learner.getByText(title));
		await learner.getByText(title).click();
		await expect(learner.locator("iframe[src*='youtube-nocookie.com/embed/dQw4w9WgXcQ']")).toBeVisible();
		await learner.getByLabel("Mark as watched").check();
		await expect(learner.getByRole("progressbar", { name: "1 of 1 watched" })).toBeVisible();
	});
});
```

- [ ] **Step 2: Run** — once the stack is up: `just e2e e2e/b7-recorded.spec.ts` → PASS.
- [ ] **Step 3: Commit** — `git -C dashboard add e2e/b7-recorded.spec.ts && git -C dashboard commit -m "test(recorded): B7a e2e journey" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 18: Gates, final review and queue

- [ ] **Step 1:** `just test` (backend coverage ≥ 80 %, dashboard gates), `just lint` (ruff, biome, colors, `lint-imports`, gitleaks). Both must pass.
- [ ] **Step 2:** `just seed` on the stream stack, then `just e2e` (the whole suite, since `features.spec.ts` and others read the registry). It must pass.
- [ ] **Step 3:** Dispatch a fresh whole-slice reviewer against spec §5–§12 and this plan's Review Focus. Fix every critical or important finding. Log minor ones in `../_ledger/orchestration/phases/B7.md`.
- [ ] **Step 4:** Commit the meta worktree's submodule pointers on `feat/b7a-recorded` (`git add backend dashboard` explicitly, never `-a`). Then `python3 scripts/orchestration/ledger.py queue B7a`, and follow the merge-queue steps in the phase prompt (rebase onto trunks, regenerate `routeTree.gen.ts` and any migration clash per §6.2, rerun the gates, push, open the PRs, `slice B7a --prs "<urls>"`).
