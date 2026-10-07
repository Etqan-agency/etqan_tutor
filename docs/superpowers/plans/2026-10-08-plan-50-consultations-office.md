# Plan 50 — B7c Consultations: Office — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new tenant app `etqan.consultations` with consultation products, the teacher opt-in, consultation requests the office records (free-slot picker from B2e availability, capacity, status machine, attendance, completion, hand payments recorded in billing), a week calendar and a teacher's "My consultations", behind the switch `consultations` (off by default).

**Architecture:** Models, services and DRF views in `backend/etqan/consultations/`. Slot arithmetic is a pure module (`slot_math.py`) fed by a thin query layer (`services/slots.py`) that reads B2e windows and sessions only through `scheduling.services`. Every write that sets a start takes a per-teacher advisory lock before counting places. Billing is reached only through `billing.services.create_record`. Dashboard feature folder `src/features/consultations/`, office pages `/catalogue/consultations` and `/scheduling/consultations`, teacher page `/teaching/consultations`, and a `ConsultantCard` on the teacher page.

**Tech Stack:** Django 5 + DRF + django-tenants + pytest; React + TanStack Router/Query + Vitest + RTL; Playwright.

**Spec:** `docs/superpowers/specs/2026-10-08-b7c-consultations-office-design.md` (C-1…C-16, §3–§7) and the phase spec `docs/superpowers/specs/2026-10-08-b7-add-on-sales-design.md` §1–§4 (B7-1…B7-17). Read both before any task.

**Requires:** — (no other phase's unmerged slice: B2e availability and B3g `billing.services.create_record` are merged; independent of B7a's code — it shares only the B7 markers and `etqan/tenants/seeds/b7.py`).

**Written in spec-only mode** (ledger D45, 2026-10-08): no stack existed when it was written, so no command below has been run. Build only after the conductor gives B7 a slot (`ledger.py phase B7 --slot n`, `.env.stream` rewritten, `just dev-backend`).

## Global Constraints

- Work from `/home/abdulkhalek/Projects/etqan_tutor-wt/b7`. `backend/` and `dashboard/` are separate git worktrees; create `feat/b7c-consultations` in the meta worktree and in both submodules (`git fetch origin && git switch -c feat/b7c-consultations origin/main` per submodule, `origin/master` for meta). Never run `git submodule update` or any writing `git submodule` command.
- Commands (after `set -a; . ./.env.stream; set +a` in the meta worktree), written below as:
  - `B <cmd>` = `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django <cmd>`
  - `F <cmd>` = `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard <cmd>`
  - Whole suites: `just migrate`, `just test`, `just lint`, `just e2e e2e/b7-consultations-office.spec.ts`, `just seed`.
- Backend coverage ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- Business logic only in `etqan/consultations/services/` (and the pure `slot_math.py`). `etqan.consultations` imports only `etqan.platform`, `etqan.identity.services`, `etqan.academy.services`, `etqan.billing.services`, `etqan.scheduling.services`. Never another app's models or api (B7-1). Session status is compared as the string `"cancelled"`.
- Shared lists: add lines only under `── phase B7 ──` markers (`TENANT_APPS`, `config/api_router.py`, the access `RESOURCES`, `seed_dev.seed_academy`, `pyproject.toml`, the dashboard `NAV_ITEMS`). If B7a's lines are already there, B7c's go directly below them under the same marker. The registry's `_later("consultations", …)` line is flipped in place. Access route tables in `access/tests/test_routes.py`: append a `# Phase B7, slice B7c` block to `ROUTES`, `FEATURES` and `SELF_SERVICE`, and one `FEATURE_WORDS` line.
- The teacher page (`routes/_authed/people.teachers.$personId.tsx`) gets exactly one import and one `<ConsultantCard>` line (phase spec §4).
- `consultations` is off by default. Routes under `/api/v1/consultations/`. People addressed by **user id** in the API; services convert to profiles (`identity.services.get_teacher_profile(user_id)`, `get_student_profile(user_id)`); windows and the advisory lock use the TeacherProfile id.
- Billing ids: `billing.services.create_record(student_id=…)` takes the student's **user id**.
- Times: stored instants are UTC; slots are computed in the academy's timezone (`academy.services.get_settings().timezone`); a local start that does not exist is skipped, an ambiguous one takes `fold=0`.
- Migrations only create new tables (B7-14).
- Text fields are plain text (D2). Meeting links https only.
- Money: integer minor units + 3-letter currency; never summed across currencies.
- Locale files `dashboard/src/locales/{en,ar}/consultations.json` (keys `consultations.*`), en and ar key-equal (no es file, D22).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Stage explicit paths; never `git commit -a`.

## Review Focus

1. **Two office users booking the last place of a slot at once.** One must get 409 `consultations.slot_full`, never a 500 or an overbooking. Pinned in Task 5: `test_lock_taken_before_places_are_counted` asserts from captured SQL that the advisory lock comes before the count, as the repo's lock tests do, and `test_warnings_come_back_and_capacity_refuses` covers the refusal.
2. **A slot that straddles a DST change, or a wall time that does not exist.** The nonexistent local start is skipped, the ambiguous one resolves with `fold=0`, and no slot ends past its window. Pinned in Task 2, `test_spring_forward_gap_is_skipped` and `test_fall_back_takes_first_instant`.
3. **A teacher reaching another teacher's request, or an office-only action.** Another teacher's request is 404. Confirm, cancel, payment and delete are 403 for a teacher. Pinned in Task 10, `test_teacher_scope`.
4. **A payment recorded twice, or for a deactivated student.** The second gives 409 `consultations.already_paid`. A deactivated student gives 400 `student` with nothing written. Pinned in Task 7.
5. **A cancelled scheduling session, or a consultation of the same product at a different start.** A cancelled session never blocks. A same-product consultation at an overlapping but different start does block. Pinned in Task 2, `test_same_product_other_start_blocks`, and Task 4, `test_cancelled_session_does_not_block`.

---

## File Structure

```text
backend/etqan/consultations/
  __init__.py
  apps.py                  ConsultationsConfig
  files.py                 cover_path, IMAGES, COVER_MAX, store(), remove_after_commit()
  models.py                Product, Consultant, Request
  slot_math.py             pure: merge_spans, candidate_starts, pick_free, Busy, Slot
  migrations/0001_initial.py   (generated)
  services/
    __init__.py            the public API (re-exports)
    common.py              LIVE, lock_teacher(), teacher_profile(), student_profile(), clean_https()
    products.py            create/update/delete/get, products_queryset, filter_products
    consultants.py         set_consultant, offers(), opted_in_teachers()
    slots.py               free_slots, warnings_for, taken_places
    requests.py            create_request, update_request, delete_request, get_request,
                           requests_queryset, filter_requests, for_teacher
    transitions.py         confirm, cancel, request_reschedule, reschedule,
                           decline_reschedule, record_delivery, complete
    payments.py            record_payment
    reads.py               ConsultationEvent, consultation_events, consultations_starting, week_agenda
  api/
    __init__.py
    serializers.py
    views.py               products, consultants, slots
    request_views.py       requests, transitions, delivery, payment, schedule
    urls.py
  tests/
    __init__.py conftest.py
    test_models.py test_slot_math.py test_products.py test_slots.py
    test_requests.py test_transitions.py test_payments.py test_reads.py
    test_api_products.py test_api_requests.py test_seeds.py
backend/etqan/tenants/seeds/b7.py          (gains seed_consultations; created if B7a has not made it)
Modified (B7 markers / in place): backend/config/settings/base.py, backend/config/api_router.py,
  backend/etqan/platform/features.py, backend/etqan/platform/tests/test_features.py,
  backend/etqan/access/registry.py, backend/etqan/access/tests/test_routes.py,
  backend/etqan/tenants/management/commands/seed_dev.py, backend/pyproject.toml

dashboard/src/features/consultations/
  schemas.ts api.ts api.test.ts queries.ts errors.ts errors.test.ts fixtures.ts index.ts
  ProductsAdmin.tsx ProductDialog.tsx ConsultantCard.tsx
  RequestsAdmin.tsx RequestDialog.tsx SlotPicker.tsx PaymentDialog.tsx
  ScheduleWeek.tsx MyConsultations.tsx
  (+ a .test.tsx next to each component)
dashboard/src/routes/_authed/
  catalogue.consultations.tsx  scheduling.consultations.tsx  teaching.consultations.tsx
dashboard/src/locales/{en,ar}/consultations.json
Modified: dashboard/src/features/identity/schemas.ts (FeatureCode), dashboard/src/features/shell/nav.ts (B7 marker),
  dashboard/src/routes/_authed/people.teachers.$personId.tsx (one line), dashboard/src/routeTree.gen.ts (regenerated)
dashboard/e2e/b7-consultations-office.spec.ts
```

---

### Task 1: The app, its models and the switch

**Files:**
- Create: `backend/etqan/consultations/__init__.py` (empty), `apps.py`, `files.py`, `models.py`, `tests/__init__.py` (empty), `tests/conftest.py`, `tests/test_models.py`
- Generate: `backend/etqan/consultations/migrations/0001_initial.py`
- Modify: `backend/config/settings/base.py` (`TENANT_APPS`, B7 marker), `backend/etqan/platform/features.py` (flip the `consultations` line in place), `backend/etqan/platform/tests/test_features.py` (BUILT dict), `backend/pyproject.toml` (B7 marker)

**Interfaces:**
- Produces: models `Product` (`Mode`, `Status`), `Consultant`, `Request` (`Status`, `SessionStatus`, `Attendance`, `PaidMethod`); `files.cover_path`, `files.IMAGES`, `files.COVER_MAX`, `files.store(field_file, upload, *, extensions, max_bytes, field) -> str | None`, `files.remove_after_commit(storage, name)`; test fixture `people` (SimpleNamespace: `teacher`, `teacher2`, `student`, `teacher_profile`, `teacher2_profile`, `student_profile`) and helper `product_row(**extra)`.

- [ ] **Step 1: Write the failing model tests**

`backend/etqan/consultations/tests/conftest.py`:

```python
"""Consultation fixtures: two teachers and a student, made through identity's
services; `product_row` builds a product straight through the model for
model tests (service tests build through the services)."""

from types import SimpleNamespace

import pytest

from etqan.consultations.models import Product
from etqan.identity import services as identity_services


@pytest.fixture
def people(set_features):
    set_features(consultations=True, teacher_availability=True)
    teacher = identity_services.create_person(
        "teacher", full_name="Bilal", email="bilal@x.test", invite=False
    )
    teacher2 = identity_services.create_person(
        "teacher", full_name="Maryam", email="maryam@x.test", invite=False
    )
    student = identity_services.create_person(
        "student", full_name="Yusuf Omar", email="yusuf@x.test",
        phone="+201000000001", timezone="Africa/Cairo", invite=False,
    )
    return SimpleNamespace(
        teacher=teacher,
        teacher2=teacher2,
        student=student,
        teacher_profile=identity_services.get_teacher_profile(teacher.pk),
        teacher2_profile=identity_services.get_teacher_profile(teacher2.pk),
        student_profile=identity_services.get_student_profile(student.pk),
    )


def product_row(**extra) -> Product:
    data = {
        "name_ar": "استشارة",
        "name_en": "Placement",
        "description_en": "d",
        "price_minor": 1500,
        "currency": "USD",
        "duration_minutes": 30,
        "validity_days": 7,
        "participants": 1,
        "delivery_mode": "video_call",
        **extra,
    }
    return Product.objects.create(**data)
```

(If `create_person` has no `invite` keyword in this checkout, drop it; check with `B grep -n "invite" etqan/identity/services.py | head -3`.)

`backend/etqan/consultations/tests/test_models.py`:

```python
from datetime import UTC
from datetime import datetime
from datetime import timedelta

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.consultations.models import Request
from etqan.consultations.tests.conftest import product_row

pytestmark = pytest.mark.django_db
T = datetime(2026, 10, 12, 14, 0, tzinfo=UTC)


def request_row(people, product, **extra):
    data = {
        "product": product,
        "teacher": people.teacher_profile,
        "name": "Yusuf",
        "email": "y@x.test",
        "whatsapp": "+20100",
        "timezone": "UTC",
        **extra,
    }
    return Request.objects.create(**data)


@pytest.mark.parametrize(
    "extra",
    [
        {"price_minor": 0},
        {"duration_minutes": 10},
        {"duration_minutes": 241},
        {"validity_days": 0},
        {"participants": 51},
        {"teacher_share_bp": 10001},
        {"description_en": "", "description_ar": ""},
    ],
)
def test_product_limits(extra):
    with pytest.raises(IntegrityError), transaction.atomic():
        product_row(**extra)


def test_request_start_and_end_go_together(people):
    p = product_row()
    with pytest.raises(IntegrityError), transaction.atomic():
        request_row(people, p, starts_at=T)
    with pytest.raises(IntegrityError), transaction.atomic():
        request_row(people, p, starts_at=T, ends_at=T)
    row = request_row(people, p, starts_at=T, ends_at=T + timedelta(minutes=30))
    assert row.status == "pending_review"
    assert (row.session_status, row.student_attendance) == ("scheduled", "not_set")
    assert row.reference == f"CR-{row.pk:06d}"


def test_email_request_has_no_start(people):
    p = product_row(delivery_mode="email")
    assert request_row(people, p).starts_at is None
```

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/consultations/tests/test_models.py -q`
Expected: collection error, `ModuleNotFoundError: No module named 'etqan.consultations'`.

- [ ] **Step 3: Write the app**

`backend/etqan/consultations/apps.py`:

```python
from django.apps import AppConfig


class ConsultationsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.consultations"
```

`backend/etqan/consultations/files.py`:

```python
"""Spec C-1: a product's cover is public marketing media (default storage),
re-encoded by etqan.platform.uploads."""

from django.core.files.base import ContentFile
from django.db import transaction

from etqan.platform import uploads
from etqan.platform.uploads import tenant_upload_path

IMAGES = frozenset({".png", ".jpg", ".jpeg", ".webp"})
COVER_MAX = 5 * 1024 * 1024

# An identifier as the folder name, so migrations serialize the callable by path.
cover_path = tenant_upload_path("consultation_covers")
cover_path.__module__ = __name__


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

`backend/etqan/consultations/models.py`:

```python
"""Slice B7c §3: consultation products (CONS-001), the teacher opt-in
(CONS-004) and consultation requests (CONS-002). Not scheduling sessions
(phase B7-10): their own time, link, statuses and attendance."""

from django.conf import settings
from django.core.validators import MaxValueValidator
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
from django.db import models
from django.db.models import F
from django.db.models import Q
from django.utils import timezone

from etqan.consultations.files import cover_path

CURRENCY = RegexValidator(r"^[A-Z]{3}$")


class Product(models.Model):
    class Mode(models.TextChoices):
        VIDEO_CALL = "video_call", "Video call"
        LIVE_CHAT = "live_chat", "Live chat"
        EMAIL = "email", "Email"

    class Status(models.TextChoices):
        AVAILABLE = "available", "Available"
        ARCHIVED = "archived", "Archived"

    cover = models.ImageField(upload_to=cover_path, blank=True, max_length=255)
    name_ar = models.CharField(max_length=120)
    name_en = models.CharField(max_length=120)
    description_ar = models.TextField(blank=True, default="", max_length=5000)
    description_en = models.TextField(blank=True, default="", max_length=5000)
    price_minor = models.BigIntegerField(validators=[MinValueValidator(1)])
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    duration_minutes = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(15), MaxValueValidator(240)]
    )
    validity_days = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(365)]
    )
    participants = models.PositiveSmallIntegerField(
        default=1, validators=[MinValueValidator(1), MaxValueValidator(50)]
    )
    delivery_mode = models.CharField(max_length=10, choices=Mode.choices)
    status = models.CharField(
        max_length=9, choices=Status.choices, default=Status.AVAILABLE
    )
    enabled = models.BooleanField(default=True)
    featured = models.BooleanField(default=False)
    reschedulable = models.BooleanField(default=False)
    fee_enabled = models.BooleanField(default=False)
    teacher_share_bp = models.PositiveSmallIntegerField(
        default=0, validators=[MaxValueValidator(10000)]
    )
    teachers = models.ManyToManyField("identity.TeacherProfile", related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-featured", "name_en", "id")
        constraints = [
            models.CheckConstraint(
                condition=Q(price_minor__gt=0), name="consult_product_price_positive"
            ),
            models.CheckConstraint(
                condition=Q(duration_minutes__gte=15) & Q(duration_minutes__lte=240),
                name="consult_product_duration_range",
            ),
            models.CheckConstraint(
                condition=Q(validity_days__gte=1) & Q(validity_days__lte=365),
                name="consult_product_validity_range",
            ),
            models.CheckConstraint(
                condition=Q(participants__gte=1) & Q(participants__lte=50),
                name="consult_product_participants_range",
            ),
            models.CheckConstraint(
                condition=Q(teacher_share_bp__lte=10000),
                name="consult_product_share_range",
            ),
            models.CheckConstraint(
                condition=~Q(description_ar="") | ~Q(description_en=""),
                name="consult_product_has_description",
            ),
        ]

    def __str__(self):
        return self.name_en

    @property
    def bookable(self) -> bool:
        """C-2."""
        return self.status == self.Status.AVAILABLE and self.enabled


class Consultant(models.Model):
    """C-3: the teacher's "offers consultations" switch, B7-owned (B7-1)."""

    teacher = models.OneToOneField(
        "identity.TeacherProfile", on_delete=models.CASCADE, related_name="+"
    )
    offers = models.BooleanField(default=False)
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    updated_at = models.DateTimeField(auto_now=True)


class Request(models.Model):
    class Status(models.TextChoices):
        PENDING_REVIEW = "pending_review", "Under review"
        CONFIRMED = "confirmed", "Confirmed"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"
        RESCHEDULE_REQUESTED = "reschedule_requested", "Reschedule requested"

    class SessionStatus(models.TextChoices):
        SCHEDULED = "scheduled", "Scheduled"
        COMPLETED = "completed", "Completed"
        ABSENT = "absent", "Absent"

    class Attendance(models.TextChoices):
        NOT_SET = "not_set", "Not recorded"
        PRESENT = "present", "Present"
        ABSENT = "absent", "Absent"

    class PaidMethod(models.TextChoices):
        NONE = "", "Unpaid"
        MANUAL = "manual", "Manual"
        STRIPE = "stripe", "Stripe"
        PAYPAL = "paypal", "PayPal"

    product = models.ForeignKey(
        Product, on_delete=models.PROTECT, related_name="requests"
    )
    teacher = models.ForeignKey(
        "identity.TeacherProfile", on_delete=models.PROTECT, related_name="+"
    )
    student = models.ForeignKey(
        "identity.StudentProfile",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    name = models.CharField(max_length=120)
    email = models.EmailField()
    whatsapp = models.CharField(max_length=30)
    timezone = models.CharField(max_length=64)
    starts_at = models.DateTimeField(null=True, blank=True)
    ends_at = models.DateTimeField(null=True, blank=True)
    meeting_url = models.URLField(max_length=500, blank=True, default="")
    session_status = models.CharField(
        max_length=9, choices=SessionStatus.choices, default=SessionStatus.SCHEDULED
    )
    student_attendance = models.CharField(
        max_length=7, choices=Attendance.choices, default=Attendance.NOT_SET
    )
    teacher_attendance = models.CharField(
        max_length=7, choices=Attendance.choices, default=Attendance.NOT_SET
    )
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.PENDING_REVIEW
    )
    notes = models.TextField(blank=True, default="", max_length=2000)
    reschedule_note = models.TextField(blank=True, default="", max_length=2000)
    paid_method = models.CharField(
        max_length=6, choices=PaidMethod.choices, blank=True, default=""
    )
    billing_method = models.CharField(max_length=16, blank=True, default="")
    payment = models.ForeignKey(
        "billing.Payment",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    amount_minor = models.BigIntegerField(default=0)
    fee_minor = models.BigIntegerField(default=0)
    currency = models.CharField(max_length=3, blank=True, default="")
    transaction_number = models.CharField(max_length=120, blank=True, default="")
    paid_on = models.DateField(null=True, blank=True)
    teacher_share_bp = models.PositiveSmallIntegerField(null=True, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    # Set by create_request from the services' clock (C-16 reads it as the
    # "created" stamp), so a default rather than auto_now_add.
    created_at = models.DateTimeField(default=timezone.now)
    confirmed_at = models.DateTimeField(null=True, blank=True)
    reschedule_requested_at = models.DateTimeField(null=True, blank=True)
    rescheduled_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at", "-id")
        constraints = [
            models.CheckConstraint(
                condition=(Q(starts_at__isnull=True) & Q(ends_at__isnull=True))
                | (
                    Q(starts_at__isnull=False)
                    & Q(ends_at__isnull=False)
                    & Q(ends_at__gt=F("starts_at"))
                ),
                name="consult_request_times_together",
            ),
            models.CheckConstraint(
                condition=Q(amount_minor__gte=0) & Q(fee_minor__gte=0),
                name="consult_request_money_not_negative",
            ),
        ]
        indexes = [
            models.Index(fields=["teacher", "starts_at"]),
            models.Index(fields=["status"]),
            models.Index(fields=["product", "teacher", "starts_at"]),
        ]

    def __str__(self):
        return self.reference

    @property
    def reference(self) -> str:
        """C-4: CR-<pk padded to 6>."""
        return f"CR-{self.pk:06d}"

    @property
    def paid(self) -> bool:
        """C-9: paid while a method is set, whatever became of the billing row."""
        return bool(self.paid_method)
```

`backend/config/settings/base.py`, in `TENANT_APPS` under `# ── phase B7 ──` (below `"etqan.recorded",` if B7a is merged):

```python
    "etqan.consultations",
```

`backend/etqan/platform/features.py`, the `_later("consultations", …)` line (line 121 on trunk today), replaced in place:

```python
    # Phase B7, slice B7c: flipped to built in place, off by default.
    _built(
        "consultations",
        "Consultations",
        "نظام الاستشارات",
        "teaching",
        default=False,
    ),
```

`backend/etqan/platform/tests/test_features.py`: in the `BUILT` dict, under `# ── phase B7 ──` (create the marker between the B6 and B8 blocks if B7a has not), add `"consultations": False,`. If a test lists the remaining `_later` codes, remove `consultations` from it.

`backend/pyproject.toml`, under `# ── phase B7 ──` (after B7a's contract if present):

```toml
[[tool.importlinter.contracts]]
name = "consultations reach other apps only through their services"
type = "forbidden"
# B7-1 (spec 2026-10-08): whole apps forbidden, only their services let
# through, so a module an app adds later is forbidden too.
source_modules = ["etqan.consultations"]
forbidden_modules = [
    "etqan.identity", "etqan.academy", "etqan.billing", "etqan.gateways",
    "etqan.catalogue", "etqan.scheduling", "etqan.tenants", "etqan.site",
    "etqan.notifications", "etqan.access", "etqan.payroll", "etqan.finance",
    "etqan.learning", "etqan.recorded",
]
allow_indirect_imports = true
ignore_imports = [
    "etqan.consultations.** -> etqan.identity.services",
    "etqan.consultations.** -> etqan.academy.services",
    "etqan.consultations.** -> etqan.billing.services",
    "etqan.consultations.** -> etqan.scheduling.services",
    "etqan.consultations.tests.** -> etqan.**",
]
```

Then `B python manage.py makemigrations consultations --name initial` and `just migrate`. Check the migration creates only the three new tables (plus the M2M table), and references `etqan.consultations.files.cover_path` by path.

- [ ] **Step 4: Run the tests to see them pass**

Run: `B pytest etqan/consultations/tests/test_models.py etqan/platform/tests/test_features.py -q` → PASS. Then `B lint-imports` and `B ruff check etqan/consultations && B ruff format --check etqan/consultations`.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/consultations config/settings/base.py etqan/platform/features.py etqan/platform/tests/test_features.py pyproject.toml
git -C backend commit -m "feat(consultations): B7c app, models and the consultations switch" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Slot arithmetic, pure (B7-10, B7-15, C-5)

**Files:**
- Create: `backend/etqan/consultations/slot_math.py`, `backend/etqan/consultations/tests/test_slot_math.py`

**Interfaces:**
- Produces (no database, no Django):
  - `Window(weekday: int, start: time, end: time)`, `Busy(starts_at: datetime, ends_at: datetime, product_id: int | None)` (`product_id=None` for a scheduling session), `Slot(starts_at: datetime, remaining: int)`, all frozen dataclasses.
  - `merge_spans(windows) -> dict[int, list[tuple[time, time]]]`
  - `local_instant(day: date, at: time, zone: str) -> datetime | None` (aware UTC; None when the wall time does not exist)
  - `candidate_starts(windows, *, start_date: date, days: int, minutes: int, zone: str, last_date: date | None = None, not_before: datetime | None = None) -> list[datetime]`
  - `pick_free(candidates, *, minutes: int, busy: list[Busy], product_id: int, participants: int) -> list[Slot]`
  - `overlaps(a_start, a_end, b_start, b_end) -> bool`

- [ ] **Step 1: Write the failing tests** (`tests/test_slot_math.py`)

```python
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta

from etqan.consultations.slot_math import Busy
from etqan.consultations.slot_math import Slot
from etqan.consultations.slot_math import Window
from etqan.consultations.slot_math import candidate_starts
from etqan.consultations.slot_math import local_instant
from etqan.consultations.slot_math import merge_spans
from etqan.consultations.slot_math import pick_free

MON = date(2026, 10, 12)  # a Monday


def utc(*args):
    return datetime(*args, tzinfo=UTC)


def test_touching_and_overlapping_windows_merge():
    spans = merge_spans(
        [Window(0, time(9), time(10)), Window(0, time(10), time(11)),
         Window(0, time(10, 30), time(12)), Window(1, time(8), time(9))]
    )
    assert spans == {0: [(time(9), time(12))], 1: [(time(8), time(9))]}


def test_windows_are_stepped_by_duration_and_end_inside():
    starts = candidate_starts(
        [Window(0, time(16), time(17, 40))],
        start_date=MON, days=1, minutes=30, zone="UTC",
    )
    assert starts == [utc(2026, 10, 12, 16), utc(2026, 10, 12, 16, 30),
                      utc(2026, 10, 12, 17)]


def test_days_weekdays_and_the_academy_zone():
    starts = candidate_starts(
        [Window(1, time(9), time(10))],  # Tuesdays, Cairo time (UTC+3 in Oct 2026)
        start_date=MON, days=8, minutes=60, zone="Africa/Cairo",
    )
    assert starts == [utc(2026, 10, 13, 6)]


def test_last_date_and_not_before_trim():
    windows = [Window(d, time(9), time(10)) for d in range(7)]
    starts = candidate_starts(
        windows, start_date=MON, days=7, minutes=60, zone="UTC",
        last_date=MON + timedelta(days=2), not_before=utc(2026, 10, 12, 9, 30),
    )
    assert starts == [utc(2026, 10, 13, 9), utc(2026, 10, 14, 9)]


def test_spring_forward_gap_is_skipped():
    # Europe/Berlin, Sunday 2026-03-29: 02:00-03:00 does not exist.
    starts = candidate_starts(
        [Window(6, time(1), time(4))],
        start_date=date(2026, 3, 29), days=1, minutes=60, zone="Europe/Berlin",
    )
    assert starts == [utc(2026, 3, 29, 0), utc(2026, 3, 29, 1)]
    assert local_instant(date(2026, 3, 29), time(2, 30), "Europe/Berlin") is None


def test_fall_back_takes_first_instant():
    # Europe/Berlin, Sunday 2026-10-25: 02:00-03:00 happens twice; fold=0.
    starts = candidate_starts(
        [Window(6, time(2), time(3))],
        start_date=date(2026, 10, 25), days=1, minutes=60, zone="Europe/Berlin",
    )
    assert starts == [utc(2026, 10, 25, 0)]


def test_sessions_block_overlapping_starts():
    starts = [utc(2026, 10, 12, 16), utc(2026, 10, 12, 16, 30), utc(2026, 10, 12, 17)]
    busy = [Busy(utc(2026, 10, 12, 16, 45), utc(2026, 10, 12, 17, 0), None)]
    assert pick_free(starts, minutes=30, busy=busy, product_id=1, participants=1) == [
        Slot(utc(2026, 10, 12, 16), 1),
        Slot(utc(2026, 10, 12, 17), 1),
    ]


def test_same_product_same_start_shares_capacity():
    start = utc(2026, 10, 12, 16)
    busy = [Busy(start, start + timedelta(minutes=30), 1)]
    assert pick_free([start], minutes=30, busy=busy, product_id=1, participants=3) == [
        Slot(start, 2)
    ]
    assert pick_free([start], minutes=30, busy=busy * 3, product_id=1, participants=3) == []


def test_same_product_other_start_blocks():
    start = utc(2026, 10, 12, 16)
    busy = [Busy(start + timedelta(minutes=15), start + timedelta(minutes=45), 1)]
    assert pick_free([start], minutes=30, busy=busy, product_id=1, participants=3) == []


def test_other_product_blocks_even_at_the_same_start():
    start = utc(2026, 10, 12, 16)
    busy = [Busy(start, start + timedelta(minutes=30), 2)]
    assert pick_free([start], minutes=30, busy=busy, product_id=1, participants=3) == []


def test_touching_intervals_do_not_overlap():
    start = utc(2026, 10, 12, 16)
    busy = [Busy(start - timedelta(minutes=30), start, None),
            Busy(start + timedelta(minutes=30), start + timedelta(minutes=60), 2)]
    assert pick_free([start], minutes=30, busy=busy, product_id=1, participants=1) == [
        Slot(start, 1)
    ]
```

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/consultations/tests/test_slot_math.py -q` → FAIL (`ModuleNotFoundError`).

- [ ] **Step 3: Implement** `backend/etqan/consultations/slot_math.py`:

```python
"""Phase B7-10 / B7-15, slice B7c C-5: which starts a teacher can take for a
product. Pure: windows on the academy's wall clock (B2e E-9), busy intervals
in UTC, results in UTC. A wall time that does not exist (spring forward) is
skipped; an ambiguous one (fall back) takes its first instant (fold=0)."""

from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta
from zoneinfo import ZoneInfo


@dataclass(frozen=True)
class Window:
    weekday: int  # Monday = 0, as TeacherAvailability
    start: time
    end: time


@dataclass(frozen=True)
class Busy:
    starts_at: datetime
    ends_at: datetime
    # The consultation's product; None for a scheduling session.
    product_id: int | None


@dataclass(frozen=True)
class Slot:
    starts_at: datetime
    remaining: int


def merge_spans(windows) -> dict[int, list[tuple[time, time]]]:
    """Each weekday's windows, sorted; touching or overlapping ones merged
    (B2e §4.5: touching windows count as one)."""
    by_day: dict[int, list[tuple[time, time]]] = defaultdict(list)
    for w in sorted(windows, key=lambda w: (w.weekday, w.start)):
        day = by_day[w.weekday]
        if day and w.start <= day[-1][1]:
            day[-1] = (day[-1][0], max(day[-1][1], w.end))
        else:
            day.append((w.start, w.end))
    return dict(by_day)


def local_instant(day: date, at: time, zone: str) -> datetime | None:
    naive = datetime.combine(day, at)
    tz = ZoneInfo(zone)
    aware = naive.replace(tzinfo=tz, fold=0)
    instant = aware.astimezone(UTC)
    if instant.astimezone(tz).replace(tzinfo=None) != naive:
        return None  # inside a spring-forward gap
    return instant


def _wall_steps(start: time, end: time, minutes: int):
    step = timedelta(minutes=minutes)
    at = datetime.combine(date.min, start)
    stop = datetime.combine(date.min, end)
    while at + step <= stop:
        yield at.time()
        at += step


def candidate_starts(  # noqa: PLR0913 -- keyword-only; one slot query's inputs
    windows,
    *,
    start_date: date,
    days: int,
    minutes: int,
    zone: str,
    last_date: date | None = None,
    not_before: datetime | None = None,
) -> list[datetime]:
    spans = merge_spans(windows)
    result = []
    for offset in range(days):
        day = start_date + timedelta(days=offset)
        if last_date is not None and day > last_date:
            break
        for span_start, span_end in spans.get(day.weekday(), ()):
            for at in _wall_steps(span_start, span_end, minutes):
                instant = local_instant(day, at, zone)
                if instant is None:
                    continue
                if not_before is not None and instant < not_before:
                    continue
                result.append(instant)
    return sorted(result)


def overlaps(a_start, a_end, b_start, b_end) -> bool:
    return a_start < b_end and b_start < a_end


def pick_free(
    candidates, *, minutes: int, busy: list[Busy], product_id: int, participants: int
) -> list[Slot]:
    """C-5: a start is blocked by any overlapping session, and by any
    overlapping consultation unless it is of the same product at the same
    start, which takes one of the `participants` places instead."""
    length = timedelta(minutes=minutes)
    free = []
    for start in candidates:
        end = start + length
        taken, blocked = 0, False
        for b in busy:
            if not overlaps(start, end, b.starts_at, b.ends_at):
                continue
            if b.product_id == product_id and b.starts_at == start:
                taken += 1
            else:
                blocked = True
                break
        if not blocked and taken < participants:
            free.append(Slot(start, participants - taken))
    return free
```

- [ ] **Step 4: Run** — `B pytest etqan/consultations/tests/test_slot_math.py -q` → PASS.
- [ ] **Step 5: Commit** — `git -C backend add etqan/consultations/slot_math.py etqan/consultations/tests/test_slot_math.py && git -C backend commit -m "feat(consultations): B7c slot arithmetic" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 3: Shared helpers, products and the teacher opt-in (C-1…C-3)

**Files:**
- Create: `backend/etqan/consultations/services/__init__.py`, `services/common.py`, `services/products.py`, `services/consultants.py`, `tests/test_products.py`

**Interfaces:**
- Consumes: Task 1's models and `files`.
- Produces:
  - `common.LIVE: tuple[str, ...]` (`"pending_review", "confirmed", "reschedule_requested"`), `common.lock_teacher(profile_id: int) -> None`, `common.teacher_profile(user_id, field="teacher")`, `common.student_profile(user_id)`, `common.clean_https(url, field="meeting_url") -> str`, `common.academy_zone() -> str`, `common.now() -> datetime`, `common.clean(row, *, exclude=(), all_field="")` (full_clean → platform `ValidationError(field)`)
  - `create_product(*, teacher_user_ids: list[int], cover=None, **fields) -> Product`, `update_product(product, *, teacher_user_ids=None, cover=None, remove_cover=False, **changes) -> Product`, `delete_product(product) -> None`, `get_product(pk) -> Product` (NotFoundError), `products_queryset()`, `filter_products(qs, *, mode="", featured: bool | None = None, status="")`
  - `set_consultant(teacher_user_id, offers: bool, *, by) -> bool`, `offers(profile_id) -> bool`, `opted_in_teachers() -> list[TeacherProfile]` (active, opted in, by name, with `user`)

- [ ] **Step 1: Write the failing tests** (`tests/test_products.py`)

```python
import pytest

from etqan.consultations import services
from etqan.consultations.models import Consultant
from etqan.consultations.models import Request
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db


@pytest.fixture
def admin(api_for):
    return api_for("admin").user


def make(people, **extra):
    data = {
        "name_ar": "استشارة",
        "name_en": "Placement",
        "description_en": "Talk to a teacher.",
        "price_minor": 1500,
        "currency": "usd",
        "duration_minutes": 30,
        "validity_days": 7,
        "delivery_mode": "video_call",
        "teacher_user_ids": [people.teacher.pk],
        **extra,
    }
    return services.create_product(**data)


def test_opt_in_round_trip(people, admin):
    assert services.offers(people.teacher_profile.pk) is False
    assert services.set_consultant(people.teacher.pk, True, by=admin) is True
    assert services.offers(people.teacher_profile.pk) is True
    assert [t.user_id for t in services.opted_in_teachers()] == [people.teacher.pk]
    services.set_consultant(people.teacher.pk, False, by=admin)
    assert services.opted_in_teachers() == []
    assert Consultant.objects.get().updated_by == admin


def test_set_consultant_refuses_a_non_teacher(people, admin):
    with pytest.raises(ValidationError) as e:
        services.set_consultant(people.student.pk, True, by=admin)
    assert e.value.field == "teacher"


def test_product_needs_opted_in_teachers(people, admin):
    with pytest.raises(ValidationError) as e:
        make(people)
    assert e.value.field == "teachers"
    services.set_consultant(people.teacher.pk, True, by=admin)
    with pytest.raises(ValidationError) as e:
        make(people, teacher_user_ids=[])
    assert e.value.field == "teachers"
    with pytest.raises(ValidationError) as e:
        make(people, teacher_user_ids=[people.student.pk])
    assert e.value.field == "teachers"
    product = make(people)
    assert product.currency == "USD"
    assert [t.user_id for t in product.teachers.all()] == [people.teacher.pk]


@pytest.mark.parametrize(
    ("extra", "field"),
    [
        ({"price_minor": 0}, "price_minor"),
        ({"duration_minutes": 241}, "duration_minutes"),
        ({"validity_days": 0}, "validity_days"),
        ({"participants": 51}, "participants"),
        ({"teacher_share_bp": 10001}, "teacher_share_bp"),
        ({"delivery_mode": "fax"}, "delivery_mode"),
        ({"description_en": ""}, "description_en"),
        ({"name_en": ""}, "name_en"),
        ({"currency": "dollars"}, "currency"),
    ],
)
def test_product_limits_are_400_on_the_field(people, admin, extra, field):
    services.set_consultant(people.teacher.pk, True, by=admin)
    with pytest.raises(ValidationError) as e:
        make(people, **extra)
    assert e.value.field == field


def test_currency_defaults_to_the_academy(people, admin):
    services.set_consultant(people.teacher.pk, True, by=admin)
    product = make(people, currency=None)
    from etqan.academy import services as academy_services  # noqa: PLC0415

    assert product.currency == academy_services.get_settings().default_currency


def test_edit_rechecks_only_new_teachers(people, admin):
    services.set_consultant(people.teacher.pk, True, by=admin)
    product = make(people)
    services.set_consultant(people.teacher.pk, False, by=admin)
    services.update_product(product, teacher_user_ids=[people.teacher.pk], name_en="New")
    assert product.name_en == "New"
    with pytest.raises(ValidationError) as e:
        services.update_product(
            product, teacher_user_ids=[people.teacher.pk, people.teacher2.pk]
        )
    assert e.value.field == "teachers"


def test_delete_refused_once_requested(people, admin):
    services.set_consultant(people.teacher.pk, True, by=admin)
    product = make(people)
    Request.objects.create(
        product=product, teacher=people.teacher_profile, name="n",
        email="n@x.test", whatsapp="1", timezone="UTC",
    )
    with pytest.raises(ConflictError) as e:
        services.delete_product(product)
    assert e.value.code == "consultations.product_in_use"
    other = make(people, name_en="Other")
    services.delete_product(other)


def test_filters(people, admin):
    services.set_consultant(people.teacher.pk, True, by=admin)
    a = make(people, featured=True)
    b = make(people, name_en="Email", delivery_mode="email", status="archived")
    qs = services.products_queryset()
    assert list(services.filter_products(qs, mode="email")) == [b]
    assert list(services.filter_products(qs, featured=True)) == [a]
    assert list(services.filter_products(qs, status="available")) == [a]
    assert services.get_product(a.pk) == a
```

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/consultations/tests/test_products.py -q` → FAIL (`ImportError`).

- [ ] **Step 3: Implement**

`services/common.py`:

```python
"""Helpers every consultation service shares."""

from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.validators import URLValidator
from django.db import connection
from django.utils import timezone as dj_timezone

from etqan.academy import services as academy_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError

# C-5: a request that holds its place (B7d adds unexpired holds).
LIVE = ("pending_review", "confirmed", "reschedule_requested")
_URL = URLValidator(schemes=["https"])


def now():
    return dj_timezone.now()


def academy_zone() -> str:
    return academy_services.get_settings().timezone


def lock_teacher(profile_id: int) -> None:
    """§4: one teacher's starts are set one at a time, in this academy.
    Transaction-scoped; taken before any place is counted."""
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT pg_advisory_xact_lock(hashtext(%s))",
            [f"consultations.teacher.{connection.schema_name}.{profile_id}"],
        )


def teacher_profile(user_id, field: str = "teacher"):
    profile = identity_services.get_teacher_profile(user_id) if user_id else None
    if profile is None:
        raise ValidationError("Choose a teacher.", field=field)
    return profile


def student_profile(user_id):
    profile = identity_services.get_student_profile(user_id) if user_id else None
    if profile is None:
        raise ValidationError("Choose a student.", field="student")
    return profile


def clean_https(url: str, field: str = "meeting_url") -> str:
    url = (url or "").strip()
    if not url:
        return ""
    try:
        _URL(url)
    except DjangoValidationError:
        raise ValidationError("Enter an https link.", field=field) from None
    return url


def clean(row, *, exclude=(), all_field: str = "") -> None:
    """The model's validators and checks as a platform 400 on one field."""
    try:
        row.full_clean(exclude=list(exclude))
    except DjangoValidationError as exc:
        field, messages = next(iter(exc.message_dict.items()))
        if field == "__all__":
            field = all_field or None
        raise ValidationError(str(messages[0]), field=field) from None
```

`services/consultants.py`:

```python
"""C-3: the teacher opt-in, a B7-owned row per teacher."""

from etqan.consultations.models import Consultant
from etqan.consultations.services.common import teacher_profile
from etqan.identity import services as identity_services


def set_consultant(teacher_user_id: int, offers: bool, *, by) -> bool:
    profile = teacher_profile(teacher_user_id)
    Consultant.objects.update_or_create(
        teacher=profile, defaults={"offers": bool(offers), "updated_by": by}
    )
    return bool(offers)


def offers(profile_id: int) -> bool:
    return Consultant.objects.filter(teacher_id=profile_id, offers=True).exists()


def opted_in_ids() -> set[int]:
    return set(
        Consultant.objects.filter(offers=True).values_list("teacher_id", flat=True)
    )


def opted_in_teachers() -> list:
    """Active, opted-in teachers, by name, with their users (two queries)."""
    ids = opted_in_ids()
    return [t for t in identity_services.active_teachers() if t.pk in ids]
```

`services/products.py`:

```python
"""C-1, C-2: consultation products."""

from django.core.files.storage import default_storage
from django.db import transaction

from etqan.academy import services as academy_services
from etqan.consultations import files
from etqan.consultations.models import Product
from etqan.consultations.services.common import clean
from etqan.consultations.services.consultants import opted_in_ids
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency

FIELDS = (
    "name_ar", "name_en", "description_ar", "description_en", "price_minor",
    "duration_minutes", "validity_days", "participants", "delivery_mode",
    "status", "enabled", "featured", "reschedulable", "fee_enabled",
    "teacher_share_bp",
)


def _profiles(user_ids, *, already=frozenset()):
    """C-3: at least one teacher; every newly added one opted in."""
    ids = list(dict.fromkeys(user_ids or []))
    if not ids:
        raise ValidationError("Choose at least one teacher.", field="teachers")
    try:
        profiles = identity_services.teacher_profiles_for(ids)
    except ValidationError:
        raise ValidationError("Choose teachers from the list.", field="teachers") from None
    opted = opted_in_ids()
    if any(p.pk not in opted and p.pk not in already for p in profiles):
        raise ValidationError(
            "Only teachers who offer consultations can be added.", field="teachers"
        )
    return profiles


def _strip(fields: dict) -> dict:
    for key in ("name_ar", "name_en", "description_ar", "description_en"):
        if key in fields and isinstance(fields[key], str):
            fields[key] = fields[key].strip()
    return fields


@transaction.atomic
def create_product(*, teacher_user_ids, cover=None, currency=None, **fields) -> Product:
    unknown = set(fields) - set(FIELDS)
    if unknown:
        raise ValidationError("Unknown field.", field=sorted(unknown)[0])
    row = Product(**_strip(fields))
    row.currency = clean_currency(
        currency or academy_services.get_settings().default_currency, field="currency"
    )
    if cover is not None:
        files.store(row.cover, cover, extensions=files.IMAGES,
                    max_bytes=files.COVER_MAX, field="cover")
    clean(row, exclude=("cover",), all_field="description_en")
    profiles = _profiles(teacher_user_ids)
    row.save()
    row.teachers.set(profiles)
    return row


@transaction.atomic
def update_product(
    product, *, teacher_user_ids=None, cover=None, remove_cover=False,
    currency=None, **changes,
) -> Product:
    row = Product.objects.select_for_update().get(pk=product.pk)
    unknown = set(changes) - set(FIELDS)
    if unknown:
        raise ValidationError("Unknown field.", field=sorted(unknown)[0])
    for key, value in _strip(changes).items():
        setattr(row, key, value)
    if currency is not None:
        row.currency = clean_currency(currency, field="currency")
    old = None
    if cover is not None:
        old = files.store(row.cover, cover, extensions=files.IMAGES,
                          max_bytes=files.COVER_MAX, field="cover")
    elif remove_cover and row.cover:
        old, row.cover = row.cover.name, ""
    clean(row, exclude=("cover",), all_field="description_en")
    profiles = None
    if teacher_user_ids is not None:
        already = set(row.teachers.values_list("pk", flat=True))
        profiles = _profiles(teacher_user_ids, already=already)
    row.save()
    if profiles is not None:
        row.teachers.set(profiles)
    files.remove_after_commit(default_storage, old)
    for key in (*changes, "currency", "cover"):
        setattr(product, key, getattr(row, key))
    return row


@transaction.atomic
def delete_product(product) -> None:
    """C-2: a product with any request is archived, never deleted."""
    if product.requests.exists():
        raise ConflictError(
            "This product has requests: archive it instead.",
            code="consultations.product_in_use",
        )
    name = product.cover.name if product.cover else None
    product.delete()
    files.remove_after_commit(default_storage, name)


def products_queryset():
    return Product.objects.prefetch_related("teachers__user")


def filter_products(qs, *, mode: str = "", featured: bool | None = None, status: str = ""):
    if mode:
        qs = qs.filter(delivery_mode=mode)
    if featured is not None:
        qs = qs.filter(featured=featured)
    if status:
        qs = qs.filter(status=status)
    return qs


def get_product(pk) -> Product:
    row = products_queryset().filter(pk=pk).first()
    if row is None:
        raise NotFoundError("Consultation", pk)
    return row
```

`services/__init__.py` (later tasks append their names to the imports and `__all__`):

```python
"""Public API of the consultations module (slice B7c). Other apps import
only this package."""

from etqan.consultations.services.consultants import offers
from etqan.consultations.services.consultants import opted_in_teachers
from etqan.consultations.services.consultants import set_consultant
from etqan.consultations.services.products import create_product
from etqan.consultations.services.products import delete_product
from etqan.consultations.services.products import filter_products
from etqan.consultations.services.products import get_product
from etqan.consultations.services.products import products_queryset
from etqan.consultations.services.products import update_product

__all__ = [
    "create_product",
    "delete_product",
    "filter_products",
    "get_product",
    "offers",
    "opted_in_teachers",
    "products_queryset",
    "set_consultant",
    "update_product",
]
```

If `full_clean` reports `price_minor` under `__all__` (the check constraint) rather than on the field, the `MinValueValidator(1)` on the field fires first; verify with the parametrized test and, if a case lands on `__all__`, pass a per-case `all_field` only where the test shows it.

- [ ] **Step 4: Run** — `B pytest etqan/consultations -q` → PASS; `B lint-imports`.
- [ ] **Step 5: Commit** — `git -C backend add etqan/consultations && git -C backend commit -m "feat(consultations): B7c products and the teacher opt-in" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 4: Free slots, warnings and capacity (C-5, C-10, C-15)

**Files:**
- Create: `backend/etqan/consultations/services/slots.py`, `backend/etqan/consultations/tests/test_slots.py`
- Modify: `backend/etqan/consultations/services/__init__.py` (exports)

**Interfaces:**
- Consumes: `slot_math` (Task 2); `common.LIVE`, `common.teacher_profile`, `common.academy_zone` (Task 3); `consultants.opted_in_ids`; `scheduling.services.windows_of(profile_id)`, `scheduling.services.is_available(profile_id, starts_at, minutes)`, `scheduling.services.sessions_queryset()`.
- Produces:
  - `SlotList(slots: list[Slot], availability_off: bool)`
  - `free_slots(product, teacher_user_id, start_date: date, days: int, *, request=None) -> SlotList`
  - `bookable_teacher(product, teacher_user_id, *, current=None) -> TeacherProfile` (400 `teacher` unless one of the product's teachers and opted in; `current`, the request's own teacher, is accepted even if opted out since)
  - `Warnings(conflicts: list[dict], outside_availability: bool, outside_validity: bool)` with `.as_dict()`
  - `warnings_for(product, profile, starts_at, *, exclude_id=None, paid_on=None) -> Warnings`
  - `check_capacity(product, profile, starts_at, *, exclude_id=None) -> None` (409 `consultations.slot_full`; the caller holds `lock_teacher`)

- [ ] **Step 1: Write the failing tests** (`tests/test_slots.py`)

```python
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta

import pytest

from etqan.consultations import services
from etqan.consultations.models import Request
from etqan.consultations.slot_math import Slot
from etqan.consultations.tests.conftest import product_row
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import subscription_for

pytestmark = pytest.mark.django_db
MON = date(2026, 6, 1)


def at(day, hour, minute=0):
    return datetime.combine(day, time(hour, minute), tzinfo=UTC)


@pytest.fixture
def setup(world, set_features, api_for):
    """world.teacher (Bilal) teaches Mondays 16:00-18:00 academy time (UTC),
    is opted in and is the product's only teacher."""
    set_features(consultations=True, teacher_availability=True)
    profile = identity_services.get_teacher_profile(world.teacher.pk)
    scheduling_services.set_availability(
        profile.pk, [{"weekday": 0, "start_time": time(16), "end_time": time(18)}]
    )
    services.set_consultant(world.teacher.pk, True, by=api_for("admin").user)
    product = product_row(duration_minutes=60, participants=2)
    product.teachers.add(profile)
    world.profile, world.product = profile, product
    return world


def live(world, start, *, product=None, status="pending_review"):
    return Request.objects.create(
        product=product or world.product, teacher=world.profile, name="n",
        email="n@x.test", whatsapp="1", timezone="UTC", status=status,
        starts_at=start, ends_at=start + timedelta(minutes=60),
    )


def test_windows_become_slots(setup):
    result = services.free_slots(setup.product, setup.teacher.pk, MON, 7)
    assert result.availability_off is False
    assert result.slots == [Slot(at(MON, 16), 2), Slot(at(MON, 17), 2)]


def test_no_windows_or_switch_off_gives_nothing(setup, set_features):
    scheduling_services.set_availability(setup.profile.pk, [])
    assert services.free_slots(setup.product, setup.teacher.pk, MON, 7).slots == []
    set_features(teacher_availability=False)
    result = services.free_slots(setup.product, setup.teacher.pk, MON, 7)
    assert (result.slots, result.availability_off) == ([], True)


def test_teacher_must_be_the_products_and_opted_in(setup, api_for):
    other = identity_services.create_person("teacher", full_name="Other")
    with pytest.raises(ValidationError) as e:
        services.free_slots(setup.product, other.pk, MON, 7)
    assert e.value.field == "teacher"
    services.set_consultant(setup.teacher.pk, False, by=api_for("admin").user)
    with pytest.raises(ValidationError):
        services.free_slots(setup.product, setup.teacher.pk, MON, 7)


@pytest.mark.parametrize("days", [0, 32])
def test_days_is_1_to_31(setup, days):
    with pytest.raises(ValidationError) as e:
        services.free_slots(setup.product, setup.teacher.pk, MON, days)
    assert e.value.field == "days"


def test_capacity_and_the_moving_requests_own_place(setup):
    mine = live(setup, at(MON, 16))
    live(setup, at(MON, 16))
    slots = services.free_slots(setup.product, setup.teacher.pk, MON, 1).slots
    assert slots == [Slot(at(MON, 17), 2)]
    slots = services.free_slots(setup.product, setup.teacher.pk, MON, 1, request=mine).slots
    assert slots == [Slot(at(MON, 16), 1), Slot(at(MON, 17), 2)]


def test_cancelled_and_closed_requests_free_their_place(setup):
    live(setup, at(MON, 16), status="cancelled")
    live(setup, at(MON, 16), status="completed")
    slots = services.free_slots(setup.product, setup.teacher.pk, MON, 1).slots
    assert slots[0] == Slot(at(MON, 16), 2)


def test_scheduling_sessions_block(setup):
    sub = subscription_for(setup)
    hand_session(sub, occurs_on=MON, start=time(16, 30), status="at_disposal")
    # 16:30-17:15 overlaps both starts; at-disposal still takes the teacher's time.
    assert services.free_slots(setup.product, setup.teacher.pk, MON, 1).slots == []


def test_a_session_ending_at_the_start_does_not_block(setup):
    sub = subscription_for(setup)
    hand_session(sub, occurs_on=MON, start=time(15, 15))  # 45 min: ends 16:00
    assert len(services.free_slots(setup.product, setup.teacher.pk, MON, 1).slots) == 2


def test_cancelled_session_does_not_block(setup):
    sub = subscription_for(setup)
    hand_session(sub, occurs_on=MON, start=time(16), status="cancelled")
    assert len(services.free_slots(setup.product, setup.teacher.pk, MON, 1).slots) == 2


def test_validity_of_a_paid_request_ends_the_list(setup):
    mine = live(setup, at(MON, 16))
    mine.paid_on, mine.paid_method = MON - timedelta(days=6), "manual"
    mine.save()
    setup.product.validity_days = 7
    setup.product.save()
    result = services.free_slots(setup.product, setup.teacher.pk, MON, 14, request=mine)
    assert {s.starts_at.date() for s in result.slots} == {MON}


def test_warnings_for_a_typed_start(setup):
    sub = subscription_for(setup)
    hand_session(sub, occurs_on=MON, start=time(20))
    other_product = product_row(name_en="Other")
    other = live(setup, at(MON, 21), product=other_product)
    w = services.warnings_for(setup.product, setup.profile, at(MON, 20, 30))
    assert w.outside_availability is True
    assert [c["kind"] for c in w.conflicts] == ["session"]
    w = services.warnings_for(
        setup.product, setup.profile, at(MON, 21), paid_on=MON - timedelta(days=30)
    )
    assert [c["id"] for c in w.conflicts] == [other.pk]
    assert w.outside_validity is True
    assert services.warnings_for(setup.product, setup.profile, at(MON, 16)).as_dict() == {
        "conflicts": [], "outside_availability": False, "outside_validity": False,
    }


def test_check_capacity(setup):
    live(setup, at(MON, 16))
    services.check_capacity(setup.product, setup.profile, at(MON, 16))
    second = live(setup, at(MON, 16))
    with pytest.raises(ConflictError) as e:
        services.check_capacity(setup.product, setup.profile, at(MON, 16))
    assert e.value.code == "consultations.slot_full"
    services.check_capacity(setup.product, setup.profile, at(MON, 16), exclude_id=second.pk)
```

(`subscription_for(setup)` works because `setup` is the scheduling `world` with two attributes added. If `create_subscription` generates sessions on its own for the subscription's slots, pass `slots=[]` or delete `Session` rows first; check `subscription_for`'s defaults with `B grep -n "def create_subscription" -A30 etqan/scheduling/services/subscriptions.py`.)

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/consultations/tests/test_slots.py -q` → FAIL (`AttributeError: free_slots`).

- [ ] **Step 3: Implement** `services/slots.py`:

```python
"""Slice B7c C-5, C-10, C-15: a teacher's free starts for a product, the
warnings on a typed start, and the one refusal (a full slot)."""

from dataclasses import asdict
from dataclasses import dataclass
from datetime import date
from datetime import timedelta
from zoneinfo import ZoneInfo

from etqan.consultations.models import Request
from etqan.consultations.services.common import LIVE
from etqan.consultations.services.common import academy_zone
from etqan.consultations.services.common import teacher_profile
from etqan.consultations.services.consultants import opted_in_ids
from etqan.consultations.slot_math import Busy
from etqan.consultations.slot_math import Slot
from etqan.consultations.slot_math import Window
from etqan.consultations.slot_math import candidate_starts
from etqan.consultations.slot_math import overlaps
from etqan.consultations.slot_math import pick_free
from etqan.platform import features
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services

AVAILABILITY = "teacher_availability"
# The longest scheduling session (Session.minutes' validators): a session that
# started this long before an instant may still be running then.
LONGEST_SESSION = timedelta(minutes=240)


@dataclass(frozen=True)
class SlotList:
    slots: list[Slot]
    availability_off: bool


@dataclass(frozen=True)
class Warnings:
    conflicts: list[dict]
    outside_availability: bool
    outside_validity: bool

    def as_dict(self) -> dict:
        return asdict(self)


def bookable_teacher(product, teacher_user_id, *, current=None):
    profile = teacher_profile(teacher_user_id)
    if current is not None and profile.pk == current.pk:
        return profile
    on_product = product.teachers.filter(pk=profile.pk).exists()
    if not on_product or profile.pk not in opted_in_ids():
        raise ValidationError(
            "Choose one of this consultation's teachers.", field="teacher"
        )
    return profile


def _session_busy(profile_id, since, until) -> list[Busy]:
    rows = (
        scheduling_services.sessions_queryset()
        .filter(
            teacher_id=profile_id,
            starts_at__gte=since - LONGEST_SESSION,
            starts_at__lt=until,
        )
        .exclude(status="cancelled")
        .values_list("pk", "starts_at", "minutes")
    )
    return [
        Busy(start, start + timedelta(minutes=minutes), None)
        for _, start, minutes in rows
        if start + timedelta(minutes=minutes) > since
    ]


def _live_requests(profile_id, since, until, exclude_id=None):
    qs = Request.objects.filter(
        teacher_id=profile_id,
        status__in=LIVE,
        starts_at__lt=until,
        ends_at__gt=since,
    )
    if exclude_id is not None:
        qs = qs.exclude(pk=exclude_id)
    return qs


def _last_date(product, request) -> date | None:
    """C-10: a paid request's consultation falls on or before paid_on +
    validity_days (academy dates)."""
    if request is None or request.paid_on is None:
        return None
    return request.paid_on + timedelta(days=product.validity_days)


def free_slots(product, teacher_user_id, start_date: date, days: int, *, request=None):
    if not 1 <= days <= 31:  # noqa: PLR2004 -- spec C-5 range
        raise ValidationError("Choose 1 to 31 days.", field="days")
    profile = bookable_teacher(
        product, teacher_user_id, current=request.teacher if request else None
    )
    if not features.enabled(AVAILABILITY):
        return SlotList(slots=[], availability_off=True)
    if product.delivery_mode == product.Mode.EMAIL:
        return SlotList(slots=[], availability_off=False)
    windows = [
        Window(w.weekday, w.start_time, w.end_time)
        for w in scheduling_services.windows_of(profile.pk)
    ]
    starts = candidate_starts(
        windows,
        start_date=start_date,
        days=days,
        minutes=product.duration_minutes,
        zone=academy_zone(),
        last_date=_last_date(product, request),
    )
    if not starts:
        return SlotList(slots=[], availability_off=False)
    since = starts[0]
    until = starts[-1] + timedelta(minutes=product.duration_minutes)
    busy = _session_busy(profile.pk, since, until) + [
        Busy(r.starts_at, r.ends_at, r.product_id)
        for r in _live_requests(
            profile.pk, since, until, exclude_id=request.pk if request else None
        )
    ]
    return SlotList(
        slots=pick_free(
            starts,
            minutes=product.duration_minutes,
            busy=busy,
            product_id=product.pk,
            participants=product.participants,
        ),
        availability_off=False,
    )


def warnings_for(product, profile, starts_at, *, exclude_id=None, paid_on=None) -> Warnings:
    """C-5: what the office is told about a typed start; never a refusal."""
    minutes = product.duration_minutes
    ends_at = starts_at + timedelta(minutes=minutes)
    conflicts = [
        {"kind": "session", "id": None, "starts_at": b.starts_at.isoformat()}
        for b in _session_busy(profile.pk, starts_at, ends_at)
        if overlaps(starts_at, ends_at, b.starts_at, b.ends_at)
    ]
    conflicts += [
        {"kind": "consultation", "id": r.pk, "starts_at": r.starts_at.isoformat()}
        for r in _live_requests(profile.pk, starts_at, ends_at, exclude_id)
        if not (r.product_id == product.pk and r.starts_at == starts_at)
    ]
    outside = features.enabled(AVAILABILITY) and (
        scheduling_services.is_available(profile.pk, starts_at, minutes) is False
    )
    local_day = starts_at.astimezone(ZoneInfo(academy_zone())).date()
    late = paid_on is not None and local_day > paid_on + timedelta(
        days=product.validity_days
    )
    return Warnings(
        conflicts=conflicts, outside_availability=bool(outside), outside_validity=late
    )


def check_capacity(product, profile, starts_at, *, exclude_id=None) -> None:
    """C-5: the one refusal. Call under `lock_teacher(profile.pk)`."""
    taken = Request.objects.filter(
        product=product, teacher=profile, starts_at=starts_at, status__in=LIVE
    )
    if exclude_id is not None:
        taken = taken.exclude(pk=exclude_id)
    if taken.count() >= product.participants:
        raise ConflictError(
            "This slot is full.", code="consultations.slot_full"
        )
```

Append to `services/__init__.py`: `SlotList`, `Warnings`, `bookable_teacher`, `check_capacity`, `free_slots`, `warnings_for` (imports and `__all__`).

- [ ] **Step 4: Run** — `B pytest etqan/consultations -q` → PASS; `B lint-imports` (scheduling reached through its services only).
- [ ] **Step 5: Commit** — `git -C backend add etqan/consultations && git -C backend commit -m "feat(consultations): B7c free slots, warnings and capacity" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 5: Requests — create, edit, delete, list (C-4, C-5, C-7, C-14)

**Files:**
- Create: `backend/etqan/consultations/services/requests.py`, `backend/etqan/consultations/tests/test_requests.py`
- Modify: `backend/etqan/consultations/tests/conftest.py` (a `booking` fixture), `services/__init__.py` (exports)

**Interfaces:**
- Consumes: Tasks 3–4 (`get_product`, `bookable_teacher`, `check_capacity`, `warnings_for`, `common.*`).
- Produces:
  - `create_request(*, product_id, teacher_user_id, by, student_user_id=None, name="", email="", whatsapp="", timezone="", starts_at=None, meeting_url="", notes="") -> tuple[Request, Warnings | None]`
  - `update_request(row, *, by, **changes) -> tuple[Request, Warnings | None]`; `changes` keys: `name`, `email`, `whatsapp`, `timezone`, `notes`, `meeting_url` (any open status); `product_id`, `teacher_user_id`, `starts_at` (only while `pending_review`, else 409 `consultations.use_reschedule`)
  - `delete_request(row) -> None`
  - `get_request(pk) -> Request` (NotFoundError), `requests_queryset()`, `filter_requests(qs, **filters)`, `for_teacher(qs, user)`
  - helpers reused by Tasks 6–7: `locked(row) -> Request` (`select_for_update`), `refuse_closed(row)` (409 `consultations.request_closed`), `place(product, profile, starts_at, *, exclude_id=None) -> Warnings` (lock the teacher, check capacity, return warnings)

- [ ] **Step 1: Write the failing tests**

Add to `tests/conftest.py`:

```python
from datetime import UTC
from datetime import datetime
from datetime import time

from etqan.consultations import services as consult_services
from etqan.scheduling import services as scheduling_services

MONDAY_4PM = datetime(2026, 10, 12, 16, 0, tzinfo=UTC)  # academy zone UTC in tests


@pytest.fixture
def booking(people, api_for):
    """An opted-in Bilal with Monday 16:00-18:00 windows, a 30-minute video
    product for two, and the admin who records requests."""
    admin = api_for("admin").user
    consult_services.set_consultant(people.teacher.pk, True, by=admin)
    scheduling_services.set_availability(
        people.teacher_profile.pk,
        [{"weekday": 0, "start_time": time(16), "end_time": time(18)}],
    )
    product = consult_services.create_product(
        name_ar="استشارة", name_en="Placement", description_en="d",
        price_minor=1500, currency="USD", duration_minutes=30, validity_days=7,
        participants=2, delivery_mode="video_call",
        teacher_user_ids=[people.teacher.pk],
    )
    people.admin, people.product = admin, product
    return people


def new_request(b, **extra):
    data = {
        "product_id": b.product.pk,
        "teacher_user_id": b.teacher.pk,
        "student_user_id": b.student.pk,
        "starts_at": MONDAY_4PM,
        "by": b.admin,
        **extra,
    }
    row, _ = consult_services.create_request(**data)
    return row
```

`tests/test_requests.py`:

```python
from datetime import date
from datetime import timedelta

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.consultations import services
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import new_request
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db


def test_a_students_request_is_prefilled(booking):
    row = new_request(booking)
    assert (row.name, row.email, row.whatsapp, row.timezone) == (
        "Yusuf Omar", "yusuf@x.test", "+201000000001", "Africa/Cairo",
    )
    assert row.ends_at == MONDAY_4PM + timedelta(minutes=30)
    assert row.status == "pending_review" and row.created_by == booking.admin


def test_an_unregistered_person_needs_name_email_whatsapp(booking):
    with pytest.raises(ValidationError) as e:
        new_request(booking, student_user_id=None, name="", email="a@x.test", whatsapp="1")
    assert e.value.field == "name"
    with pytest.raises(ValidationError) as e:
        new_request(booking, student_user_id=None, name="A", email="nope", whatsapp="1")
    assert e.value.field == "email"
    with pytest.raises(ValidationError) as e:
        new_request(booking, student_user_id=None, name="A", email="a@x.test", whatsapp="")
    assert e.value.field == "whatsapp"
    row = new_request(booking, student_user_id=None, name=" Ali ", email="a@x.test",
                      whatsapp="+1555", timezone="Europe/London")
    assert (row.student, row.name, row.timezone) == (None, "Ali", "Europe/London")


def test_academy_zone_for_a_person_without_account(booking):
    row = new_request(booking, student_user_id=None, name="A", email="a@x.test",
                      whatsapp="1")
    from etqan.academy import services as academy_services  # noqa: PLC0415

    assert row.timezone == academy_services.get_settings().timezone


@pytest.mark.parametrize(
    ("extra", "field"),
    [
        ({"timezone": "Mars/Base"}, "timezone"),
        ({"meeting_url": "http://meet.test/x"}, "meeting_url"),
        ({"student_user_id": 999999}, "student"),
        ({"product_id": 999999}, "product"),
    ],
)
def test_bad_fields_are_400(booking, extra, field):
    with pytest.raises(ValidationError) as e:
        new_request(booking, **extra)
    assert e.value.field == field


def test_product_must_be_bookable_and_teacher_its_own(booking):
    services.update_product(booking.product, status="archived")
    with pytest.raises(ValidationError) as e:
        new_request(booking)
    assert e.value.field == "product"
    services.update_product(booking.product, status="available")
    with pytest.raises(ValidationError) as e:
        new_request(booking, teacher_user_id=booking.teacher2.pk)
    assert e.value.field == "teacher"


def test_video_link_prefilled_from_the_teacher(booking):
    booking.teacher_profile.default_meeting_url = "https://meet.test/bilal"
    booking.teacher_profile.save()
    assert new_request(booking).meeting_url == "https://meet.test/bilal"
    assert new_request(booking, meeting_url="https://other.test/x").meeting_url == (
        "https://other.test/x"
    )


def test_email_mode_takes_no_start(booking):
    services.update_product(booking.product, delivery_mode="email")
    with pytest.raises(ValidationError) as e:
        new_request(booking)
    assert e.value.field == "starts_at"
    assert new_request(booking, starts_at=None).starts_at is None


def test_warnings_come_back_and_capacity_refuses(booking):
    _, warnings = services.create_request(
        product_id=booking.product.pk, teacher_user_id=booking.teacher.pk,
        student_user_id=booking.student.pk, by=booking.admin,
        starts_at=MONDAY_4PM + timedelta(hours=3),
    )
    assert warnings.outside_availability is True
    new_request(booking)
    new_request(booking)
    with pytest.raises(ConflictError) as e:
        new_request(booking)
    assert e.value.code == "consultations.slot_full"


def test_lock_taken_before_places_are_counted(booking):
    with CaptureQueriesContext(connection) as ctx:
        new_request(booking)
    sqls = [q["sql"] for q in ctx.captured_queries]
    lock = next(i for i, s in enumerate(sqls) if "pg_advisory_xact_lock" in s)
    count = next(
        i for i, s in enumerate(sqls)
        if "COUNT(" in s and "consultations_request" in s
    )
    assert lock < count


def test_edit_while_pending_and_refusals_after(booking):
    row = new_request(booking)
    row, warnings = services.update_request(
        row, by=booking.admin, starts_at=MONDAY_4PM + timedelta(minutes=30),
        notes="Bring the book",
    )
    assert row.ends_at == MONDAY_4PM + timedelta(minutes=60)
    assert warnings.outside_availability is False and row.notes == "Bring the book"
    row.status = "confirmed"
    row.save()
    with pytest.raises(ConflictError) as e:
        services.update_request(row, by=booking.admin, starts_at=MONDAY_4PM)
    assert e.value.code == "consultations.use_reschedule"
    row, _ = services.update_request(row, by=booking.admin, whatsapp="+2")
    assert row.whatsapp == "+2"
    row.status = "cancelled"
    row.save()
    with pytest.raises(ConflictError) as e:
        services.update_request(row, by=booking.admin, notes="x")
    assert e.value.code == "consultations.request_closed"


def test_product_fixed_once_paid(booking):
    row = new_request(booking)
    other = services.create_product(
        name_ar="ب", name_en="Other", description_en="d", price_minor=100,
        currency="USD", duration_minutes=60, validity_days=3,
        delivery_mode="video_call", teacher_user_ids=[booking.teacher.pk],
    )
    row, _ = services.update_request(row, by=booking.admin, product_id=other.pk)
    assert row.product == other and row.ends_at == MONDAY_4PM + timedelta(minutes=60)
    row.paid_method = "manual"
    row.save()
    with pytest.raises(ValidationError) as e:
        services.update_request(row, by=booking.admin, product_id=booking.product.pk)
    assert e.value.field == "product"


def test_delete_only_unpaid_pending(booking):
    row = new_request(booking)
    row.paid_method = "manual"
    row.save()
    with pytest.raises(ConflictError) as e:
        services.delete_request(row)
    assert e.value.code == "consultations.request_in_use"
    other = new_request(booking)
    services.delete_request(other)


def test_filters_and_teacher_scope(booking):
    a = new_request(booking)
    b = new_request(booking, student_user_id=None, name="B", email="b@x.test",
                    whatsapp="1", starts_at=MONDAY_4PM + timedelta(days=7))
    b.status = "confirmed"
    b.save()
    qs = services.requests_queryset()
    assert list(services.filter_requests(qs, status="confirmed")) == [b]
    assert list(services.filter_requests(qs, teacher=booking.teacher.pk)) == [b, a]
    assert list(
        services.filter_requests(qs, date_from=date(2026, 10, 13))
    ) == [b]
    assert list(services.filter_requests(qs, date_to=date(2026, 10, 12))) == [a]
    assert list(services.for_teacher(qs, booking.teacher2)) == []
    assert services.get_request(a.pk) == a
```

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/consultations/tests/test_requests.py -q` → FAIL.

- [ ] **Step 3: Implement** `services/requests.py`:

```python
"""Slice B7c C-4, C-5, C-7, C-14: requests the office records."""

from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta
from zoneinfo import ZoneInfo

from django.core.validators import validate_email
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction

from etqan.consultations.models import Product
from etqan.consultations.models import Request
from etqan.consultations.services import common
from etqan.consultations.services.common import academy_zone
from etqan.consultations.services.common import clean_https
from etqan.consultations.services.common import lock_teacher
from etqan.consultations.services.common import student_profile
from etqan.consultations.services.products import get_product
from etqan.consultations.services.slots import bookable_teacher
from etqan.consultations.services.slots import check_capacity
from etqan.consultations.services.slots import warnings_for
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_timezone

CLOSED = ("completed", "cancelled")
CONTACT = ("name", "email", "whatsapp", "timezone", "notes", "meeting_url")
PLACE = ("product_id", "teacher_user_id", "starts_at")


def locked(row) -> Request:
    return Request.objects.select_for_update().get(pk=row.pk)


def refuse_closed(row) -> None:
    if row.status in CLOSED:
        raise ConflictError(
            "This request is closed.", code="consultations.request_closed"
        )


def _bookable(product_id) -> Product:
    try:
        product = get_product(product_id)
    except NotFoundError:
        raise ValidationError("Choose a consultation.", field="product") from None
    if not product.bookable:
        raise ValidationError(
            "This consultation takes no new requests.", field="product"
        )
    return product


def _contact(name, email, whatsapp, timezone) -> dict:
    name, whatsapp = (name or "").strip(), (whatsapp or "").strip()
    if not name or len(name) > 120:  # noqa: PLR2004 -- C-4 limit
        raise ValidationError("Enter the person's name.", field="name")
    try:
        validate_email(email or "")
    except DjangoValidationError:
        raise ValidationError("Enter a valid email.", field="email") from None
    if not whatsapp or len(whatsapp) > 30:  # noqa: PLR2004 -- C-4 limit
        raise ValidationError("Enter a WhatsApp number.", field="whatsapp")
    return {
        "name": name,
        "email": email.strip(),
        "whatsapp": whatsapp,
        "timezone": clean_timezone(timezone),
    }


def place(product, profile, starts_at, *, exclude_id=None, paid_on=None):
    """C-5: under the teacher's lock, refuse a full slot, then warn."""
    lock_teacher(profile.pk)
    check_capacity(product, profile, starts_at, exclude_id=exclude_id)
    return warnings_for(
        product, profile, starts_at, exclude_id=exclude_id, paid_on=paid_on
    )


def _start(product, starts_at):
    if product.delivery_mode == Product.Mode.EMAIL:
        if starts_at is not None:
            raise ValidationError(
                "An email consultation has no time.", field="starts_at"
            )
        return None, None
    if starts_at is None:
        return None, None
    return starts_at, starts_at + timedelta(minutes=product.duration_minutes)


@transaction.atomic
def create_request(  # noqa: PLR0913 -- keyword-only; mirrors the API body
    *,
    product_id,
    teacher_user_id,
    by,
    student_user_id=None,
    name="",
    email="",
    whatsapp="",
    timezone="",
    starts_at=None,
    meeting_url="",
    notes="",
):
    product = _bookable(product_id)
    profile = bookable_teacher(product, teacher_user_id)
    student = None
    if student_user_id:
        student = student_profile(student_user_id)
        user = identity_services.get_user(student_user_id)
        name = name or user.full_name
        email = email or (user.email or "")
        whatsapp = whatsapp or user.phone
        timezone = timezone or user.timezone
    contact = _contact(name, email, whatsapp, timezone or academy_zone())
    link = clean_https(meeting_url)
    if not link and product.delivery_mode == Product.Mode.VIDEO_CALL:
        link = profile.default_meeting_url
    if len(notes or "") > 2000:  # noqa: PLR2004 -- C-4 limit
        raise ValidationError("Keep notes under 2000 characters.", field="notes")
    start, end = _start(product, starts_at)
    warnings = place(product, profile, start) if start else None
    row = Request.objects.create(
        product=product, teacher=profile, student=student, starts_at=start,
        ends_at=end, meeting_url=link, notes=notes or "", created_by=by,
        created_at=common.now(), **contact,
    )
    return row, warnings


@transaction.atomic
def update_request(row, *, by, **changes):  # noqa: ARG001 -- `by` kept for symmetry and logs
    unknown = set(changes) - set(CONTACT) - set(PLACE)
    if unknown:
        raise ValidationError("Unknown field.", field=sorted(unknown)[0])
    current = Request.objects.get(pk=row.pk)
    refuse_closed(current)
    moving = set(changes) & set(PLACE)
    if moving and current.status != Request.Status.PENDING_REVIEW:
        raise ConflictError(
            "Use reschedule to move a confirmed request.",
            code="consultations.use_reschedule",
        )
    product = current.product
    if "product_id" in changes and changes["product_id"] != current.product_id:
        if current.paid:
            raise ValidationError(
                "A paid request keeps its consultation.", field="product"
            )
        product = _bookable(changes["product_id"])
    teacher_uid = changes.get("teacher_user_id", current.teacher.user_id)
    same_product = product.pk == current.product_id
    profile = bookable_teacher(
        product, teacher_uid, current=current.teacher if same_product else None
    )
    starts_at = changes.get("starts_at", current.starts_at)
    warnings = None
    if moving:
        start, end = _start(product, starts_at)
        if start:
            warnings = place(product, profile, start, exclude_id=current.pk,
                             paid_on=current.paid_on)
    fresh = locked(current)
    refuse_closed(fresh)
    if moving:
        fresh.product, fresh.teacher = product, profile
        fresh.starts_at, fresh.ends_at = start, end
    contact_changes = {k: changes[k] for k in CONTACT if k in changes}
    if {"name", "email", "whatsapp", "timezone"} & set(contact_changes):
        merged = _contact(
            contact_changes.get("name", fresh.name),
            contact_changes.get("email", fresh.email),
            contact_changes.get("whatsapp", fresh.whatsapp),
            contact_changes.get("timezone", fresh.timezone),
        )
        for key, value in merged.items():
            setattr(fresh, key, value)
    if "meeting_url" in contact_changes:
        fresh.meeting_url = clean_https(contact_changes["meeting_url"])
    if "notes" in contact_changes:
        if len(contact_changes["notes"]) > 2000:  # noqa: PLR2004
            raise ValidationError("Keep notes under 2000 characters.", field="notes")
        fresh.notes = contact_changes["notes"]
    fresh.save()
    return fresh, warnings


@transaction.atomic
def delete_request(row) -> None:
    """C-14: only an unpaid request still under review."""
    fresh = locked(row)
    if fresh.status != Request.Status.PENDING_REVIEW or fresh.paid:
        raise ConflictError(
            "Cancel this request instead.", code="consultations.request_in_use"
        )
    fresh.delete()


def requests_queryset():
    return Request.objects.select_related(
        "product", "teacher__user", "student__user", "payment"
    )


def get_request(pk) -> Request:
    row = requests_queryset().filter(pk=pk).first()
    if row is None:
        raise NotFoundError("Consultation request", pk)
    return row


def _day_start(day: date) -> datetime:
    return datetime.combine(day, time.min, tzinfo=ZoneInfo(academy_zone()))


def filter_requests(  # noqa: PLR0913 -- keyword-only; mirrors the list's query
    qs,
    *,
    product=None,
    teacher=None,
    session_status="",
    student_attendance="",
    teacher_attendance="",
    paid_method="",
    billing_method="",
    status="",
    date_from: date | None = None,
    date_to: date | None = None,
):
    """§4 (CONS-002 filters). Dates are academy days over the start."""
    if product:
        qs = qs.filter(product_id=product)
    if teacher:
        qs = qs.filter(teacher__user_id=teacher)
    for field, value in (
        ("session_status", session_status),
        ("student_attendance", student_attendance),
        ("teacher_attendance", teacher_attendance),
        ("billing_method", billing_method),
        ("status", status),
    ):
        if value:
            qs = qs.filter(**{field: value})
    if paid_method == "unpaid":
        qs = qs.filter(paid_method="")
    elif paid_method:
        qs = qs.filter(paid_method=paid_method)
    if date_from:
        qs = qs.filter(starts_at__gte=_day_start(date_from))
    if date_to:
        qs = qs.filter(starts_at__lt=_day_start(date_to + timedelta(days=1)))
    return qs.order_by("-starts_at", "-id")


def for_teacher(qs, user):
    """C-12: a teacher's own requests only."""
    return qs.filter(teacher__user_id=user.pk)
```

Lock order: `update_request` reads the row unlocked, takes the teacher's advisory lock inside `place`, then locks the row (`locked`). Tasks 6–7 keep the same order: the advisory lock always comes before the row lock.

Note: `filter_requests` orders by `-starts_at`. Postgres sorts NULLs first on a descending sort, so start-less email requests come first; acceptable for the list.

Append to `services/__init__.py`: `create_request`, `update_request`, `delete_request`, `get_request`, `requests_queryset`, `filter_requests`, `for_teacher`.

- [ ] **Step 4: Run** — `B pytest etqan/consultations -q` → PASS.
- [ ] **Step 5: Commit** — `git -C backend add etqan/consultations && git -C backend commit -m "feat(consultations): B7c requests" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 6: Status machine, delivery and completion (C-6, C-7, C-8)

**Files:**
- Create: `backend/etqan/consultations/services/transitions.py`, `backend/etqan/consultations/tests/test_transitions.py`
- Modify: `services/__init__.py` (exports)

**Interfaces:**
- Consumes: `requests.locked`, `requests.refuse_closed`, `requests.place`, `slots.bookable_teacher`, `common.now`.
- Produces (each returns the fresh `Request`; `reschedule` returns `(Request, Warnings)`):
  - `confirm(row, *, by)`, `cancel(row, *, by)`, `request_reschedule(row, *, note="", by)`, `reschedule(row, *, starts_at, by, teacher_user_id=None)`, `decline_reschedule(row, *, note="", by)`, `record_delivery(row, *, student_attendance=None, teacher_attendance=None, session_status=None, meeting_url=None)`, `complete(row, *, by)`
  - Error codes: 409 `consultations.request_closed`, 409 `consultations.wrong_status` (a move from a state the machine does not allow), 409 `consultations.not_reschedulable`, 409 `consultations.not_started`, 409 `consultations.not_delivered`; 400 on `starts_at`, `student_attendance`, `teacher_attendance`, `session_status`.

- [ ] **Step 1: Write the failing tests** (`tests/test_transitions.py`)

```python
from datetime import timedelta

import pytest
from django.utils import timezone

from etqan.consultations import services
from etqan.consultations.services import common
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import new_request
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
AFTER = MONDAY_4PM + timedelta(hours=1)


@pytest.fixture
def after_start(monkeypatch):
    monkeypatch.setattr(common, "now", lambda: AFTER)


def code_of(fn, *args, **kwargs):
    with pytest.raises(ConflictError) as e:
        fn(*args, **kwargs)
    return e.value.code


def test_confirm_needs_a_start_and_stamps(booking):
    row = new_request(booking, starts_at=None)
    with pytest.raises(ValidationError) as e:
        services.confirm(row, by=booking.admin)
    assert e.value.field == "starts_at"
    row = services.confirm(new_request(booking), by=booking.admin)
    assert row.status == "confirmed" and row.confirmed_at is not None
    assert code_of(services.confirm, row, by=booking.admin) == "consultations.wrong_status"


def test_email_requests_confirm_without_a_start(booking):
    services.update_product(booking.product, delivery_mode="email")
    row = services.confirm(new_request(booking, starts_at=None), by=booking.admin)
    assert row.status == "confirmed"


def test_cancel_from_every_open_state_and_closed_is_final(booking):
    for status in ("pending_review", "confirmed", "reschedule_requested"):
        row = new_request(booking, starts_at=None)
        row.status = status
        row.save()
        row = services.cancel(row, by=booking.admin)
        assert row.status == "cancelled" and row.cancelled_at is not None
    assert code_of(services.cancel, row, by=booking.admin) == "consultations.request_closed"
    assert code_of(services.confirm, row, by=booking.admin) == "consultations.request_closed"


def test_reschedule_request_needs_a_reschedulable_product(booking):
    row = services.confirm(new_request(booking), by=booking.admin)
    assert code_of(services.request_reschedule, row, by=booking.admin) == (
        "consultations.not_reschedulable"
    )
    services.update_product(booking.product, reschedulable=True)
    row = services.request_reschedule(row, note="Travelling", by=booking.admin)
    assert (row.status, row.reschedule_note) == ("reschedule_requested", "Travelling")
    assert row.reschedule_requested_at is not None


def test_office_moves_any_confirmed_start(booking):
    row = services.confirm(new_request(booking), by=booking.admin)
    row, warnings = services.reschedule(
        row, starts_at=MONDAY_4PM + timedelta(minutes=30), by=booking.admin
    )
    assert row.status == "confirmed" and row.rescheduled_at is not None
    assert row.ends_at == MONDAY_4PM + timedelta(minutes=60)
    assert warnings.conflicts == []
    pending = new_request(booking)
    assert code_of(
        services.reschedule, pending, starts_at=MONDAY_4PM, by=booking.admin
    ) == "consultations.wrong_status"


def test_reschedule_back_to_confirmed_or_declined(booking):
    services.update_product(booking.product, reschedulable=True)
    row = services.confirm(new_request(booking), by=booking.admin)
    row = services.request_reschedule(row, by=booking.admin)
    row, _ = services.reschedule(
        row, starts_at=MONDAY_4PM + timedelta(days=7), by=booking.admin
    )
    assert row.status == "confirmed"
    row = services.request_reschedule(row, by=booking.admin)
    row = services.decline_reschedule(row, note="No other time", by=booking.admin)
    assert (row.status, row.reschedule_note) == ("confirmed", "No other time")
    assert row.starts_at == MONDAY_4PM + timedelta(days=7)


def test_reschedule_respects_capacity(booking):
    services.update_product(booking.product, participants=1)
    new_request(booking, starts_at=MONDAY_4PM + timedelta(minutes=30))
    row = services.confirm(new_request(booking), by=booking.admin)
    assert code_of(
        services.reschedule, row, starts_at=MONDAY_4PM + timedelta(minutes=30),
        by=booking.admin,
    ) == "consultations.slot_full"


def test_delivery_only_after_the_start(booking, monkeypatch):
    row = services.confirm(new_request(booking), by=booking.admin)
    monkeypatch.setattr(common, "now", lambda: MONDAY_4PM - timedelta(minutes=1))
    assert code_of(
        services.record_delivery, row, student_attendance="present"
    ) == "consultations.not_started"
    row = services.record_delivery(row, meeting_url="https://meet.test/new")
    assert row.meeting_url == "https://meet.test/new"
    monkeypatch.setattr(common, "now", lambda: AFTER)
    row = services.record_delivery(
        row, student_attendance="present", teacher_attendance="present",
        session_status="completed",
    )
    assert (row.student_attendance, row.session_status) == ("present", "completed")
    with pytest.raises(ValidationError) as e:
        services.record_delivery(row, student_attendance="maybe")
    assert e.value.field == "student_attendance"


def test_delivery_needs_confirmed(booking, after_start):
    row = new_request(booking)
    assert code_of(
        services.record_delivery, row, session_status="absent"
    ) == "consultations.wrong_status"


def test_complete_needs_delivery_and_snapshots_the_share(booking, after_start):
    services.update_product(booking.product, teacher_share_bp=4000)
    row = services.confirm(new_request(booking), by=booking.admin)
    assert code_of(services.complete, row, by=booking.admin) == "consultations.not_delivered"
    row = services.record_delivery(row, session_status="absent", student_attendance="absent",
                                   teacher_attendance="present")
    row = services.complete(row, by=booking.admin)
    assert (row.status, row.teacher_share_bp) == ("completed", 4000)
    assert row.completed_at is not None
    services.update_product(booking.product, teacher_share_bp=1000)
    row.refresh_from_db()
    assert row.teacher_share_bp == 4000


def test_email_completes_without_attendance(booking):
    services.update_product(booking.product, delivery_mode="email")
    row = services.confirm(new_request(booking, starts_at=None), by=booking.admin)
    with pytest.raises(ValidationError) as e:
        services.record_delivery(row, student_attendance="present")
    assert e.value.field == "student_attendance"
    row = services.complete(row, by=booking.admin)
    assert (row.status, row.session_status) == ("completed", "completed")


def test_stamps_use_the_service_clock(booking, after_start):
    row = services.confirm(new_request(booking), by=booking.admin)
    assert row.confirmed_at == AFTER
    assert timezone.is_aware(row.confirmed_at)
```

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/consultations/tests/test_transitions.py -q` → FAIL.

- [ ] **Step 3: Implement** `services/transitions.py`:

```python
"""Slice B7c C-6, C-7, C-8: the request status machine (P1 §8.4), the
office's moves, delivery and completion. The teacher's advisory lock (when a
start changes) is always taken before the row lock."""

from datetime import timedelta

from django.db import transaction

from etqan.consultations.models import Product
from etqan.consultations.models import Request
from etqan.consultations.services import common
from etqan.consultations.services.requests import locked
from etqan.consultations.services.requests import place
from etqan.consultations.services.requests import refuse_closed
from etqan.consultations.services.slots import bookable_teacher
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

S = Request.Status
ATTENDANCE = {c for c, _ in Request.Attendance.choices}
SESSION = {c for c, _ in Request.SessionStatus.choices}


def _from(row, *allowed) -> Request:
    fresh = locked(row)
    refuse_closed(fresh)
    if fresh.status not in allowed:
        raise ConflictError(
            "This request cannot do that now.", code="consultations.wrong_status"
        )
    return fresh


def _email(row) -> bool:
    return row.product.delivery_mode == Product.Mode.EMAIL


def _save(fresh, *fields) -> Request:
    fresh.save(update_fields=[*fields])
    return fresh


@transaction.atomic
def confirm(row, *, by) -> Request:  # noqa: ARG001
    fresh = _from(row, S.PENDING_REVIEW)
    if fresh.starts_at is None and not _email(fresh):
        raise ValidationError("Choose a time first.", field="starts_at")
    fresh.status, fresh.confirmed_at = S.CONFIRMED, common.now()
    return _save(fresh, "status", "confirmed_at")


@transaction.atomic
def cancel(row, *, by) -> Request:  # noqa: ARG001
    fresh = _from(row, S.PENDING_REVIEW, S.CONFIRMED, S.RESCHEDULE_REQUESTED)
    fresh.status, fresh.cancelled_at = S.CANCELLED, common.now()
    return _save(fresh, "status", "cancelled_at")


@transaction.atomic
def request_reschedule(row, *, note: str = "", by) -> Request:  # noqa: ARG001
    fresh = _from(row, S.CONFIRMED)
    if not fresh.product.reschedulable:
        raise ConflictError(
            "This consultation cannot be rescheduled.",
            code="consultations.not_reschedulable",
        )
    fresh.status = S.RESCHEDULE_REQUESTED
    fresh.reschedule_requested_at, fresh.reschedule_note = common.now(), note[:2000]
    return _save(fresh, "status", "reschedule_requested_at", "reschedule_note")


@transaction.atomic
def reschedule(row, *, starts_at, by, teacher_user_id=None):  # noqa: ARG001
    """C-7: the office may always move a confirmed start (BR-27 gates only
    the booker's ask)."""
    current = Request.objects.select_related("product", "teacher").get(pk=row.pk)
    refuse_closed(current)
    if current.status not in (S.CONFIRMED, S.RESCHEDULE_REQUESTED):
        raise ConflictError(
            "This request cannot do that now.", code="consultations.wrong_status"
        )
    if _email(current) or starts_at is None:
        raise ValidationError("Choose a time.", field="starts_at")
    profile = bookable_teacher(
        current.product,
        teacher_user_id or current.teacher.user_id,
        current=current.teacher,
    )
    warnings = place(current.product, profile, starts_at, exclude_id=current.pk,
                     paid_on=current.paid_on)
    fresh = _from(current, S.CONFIRMED, S.RESCHEDULE_REQUESTED)
    fresh.teacher, fresh.starts_at = profile, starts_at
    fresh.ends_at = starts_at + timedelta(minutes=fresh.product.duration_minutes)
    fresh.status, fresh.rescheduled_at = S.CONFIRMED, common.now()
    return _save(fresh, "teacher", "starts_at", "ends_at", "status", "rescheduled_at"), warnings


@transaction.atomic
def decline_reschedule(row, *, note: str = "", by) -> Request:  # noqa: ARG001
    fresh = _from(row, S.RESCHEDULE_REQUESTED)
    fresh.status, fresh.reschedule_note = S.CONFIRMED, note[:2000]
    return _save(fresh, "status", "reschedule_note")


def _choice(value, allowed, field):
    if value not in allowed:
        raise ValidationError("Choose a value from the list.", field=field)
    return value


@transaction.atomic
def record_delivery(
    row, *, student_attendance=None, teacher_attendance=None, session_status=None,
    meeting_url=None,
) -> Request:
    """C-8: the link while open; attendance and session status once
    confirmed and started (email requests take neither)."""
    fresh = locked(row)
    refuse_closed(fresh)
    fields = []
    if meeting_url is not None:
        fresh.meeting_url = common.clean_https(meeting_url)
        fields.append("meeting_url")
    marks = {
        "student_attendance": student_attendance,
        "teacher_attendance": teacher_attendance,
        "session_status": session_status,
    }
    marks = {k: v for k, v in marks.items() if v is not None}
    if marks:
        if _email(fresh):
            raise ValidationError(
                "An email consultation takes no attendance.", field=next(iter(marks))
            )
        if fresh.status != S.CONFIRMED:
            raise ConflictError(
                "Confirm this request first.", code="consultations.wrong_status"
            )
        if fresh.starts_at is None or fresh.starts_at > common.now():
            raise ConflictError(
                "This consultation has not started yet.",
                code="consultations.not_started",
            )
        for field, value in marks.items():
            allowed = SESSION if field == "session_status" else ATTENDANCE
            setattr(fresh, field, _choice(value, allowed, field))
        fields += list(marks)
    if fields:
        fresh.save(update_fields=fields)
    return fresh


@transaction.atomic
def complete(row, *, by) -> Request:  # noqa: ARG001
    fresh = _from(row, S.CONFIRMED)
    if _email(fresh):
        fresh.session_status = Request.SessionStatus.COMPLETED
    elif fresh.session_status == Request.SessionStatus.SCHEDULED:
        raise ConflictError(
            "Record how the session went first.", code="consultations.not_delivered"
        )
    fresh.status, fresh.completed_at = S.COMPLETED, common.now()
    fresh.teacher_share_bp = fresh.product.teacher_share_bp
    return _save(fresh, "status", "completed_at", "session_status", "teacher_share_bp")
```

`services.common.now` is looked up through the module (`common.now()`), so the tests' `monkeypatch.setattr(common, "now", …)` takes effect. Keep every call to it in that form.

Append to `services/__init__.py`: `cancel`, `complete`, `confirm`, `decline_reschedule`, `record_delivery`, `request_reschedule`, `reschedule`, and export the `common` module's `now` via the package as `services.common` (import `from etqan.consultations.services import common` in `__init__`).

- [ ] **Step 4: Run** — `B pytest etqan/consultations -q` → PASS.
- [ ] **Step 5: Commit** — `git -C backend add etqan/consultations && git -C backend commit -m "feat(consultations): B7c status machine, delivery and completion" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 7: Payment by hand (C-9, phase B7-4)

**Files:**
- Create: `backend/etqan/consultations/services/payments.py`, `backend/etqan/consultations/tests/test_payments.py`
- Modify: `services/__init__.py` (export `record_payment`, and re-export billing's `MANUAL_PAYMENT_METHODS` as `BILLING_METHODS` for the API's choices)

**Interfaces:**
- Consumes: `requests.locked`; `billing.services.create_record(*, customer_type, amount_minor, method, by, student_id=None, customer_name="", customer_email="", customer_phone="", currency=None, transaction_number="", reference="", paid_on=None, notes="") -> Payment` (student_id is the **user id**); `billing.services.MANUAL_PAYMENT_METHODS` (tuple of `(value, label)`).
- Produces: `record_payment(row, *, billing_method, by, amount_minor=None, paid_on=None, reference="", transaction_number="") -> Request`. Errors: 409 `consultations.already_paid`, 409 `consultations.request_closed` (a cancelled request), 400 `amount_minor`, 400 `billing_method` (billing's `method` refusal renamed), billing's other 400s (`student`, `transaction_number`, `paid_on`) unchanged.

- [ ] **Step 1: Write the failing tests** (`tests/test_payments.py`)

```python
from datetime import date

import pytest

from etqan.billing import services as billing_services
from etqan.consultations import services
from etqan.consultations.tests.conftest import new_request
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import deactivated

pytestmark = pytest.mark.django_db


def pay(booking, row, **extra):
    data = {"billing_method": "cash", "by": booking.admin, **extra}
    return services.record_payment(row, **data)


def test_a_students_payment_is_a_billing_record(booking):
    row = pay(booking, new_request(booking), reference="Front desk", paid_on=date(2026, 10, 1))
    payment = billing_services.payments_queryset().get(pk=row.payment_id)
    assert (payment.student.user_id, payment.amount_minor, payment.currency) == (
        booking.student.pk, 1500, "USD",
    )
    assert (payment.method, payment.reference, payment.recorded_by) == (
        "cash", "Front desk", booking.admin,
    )
    assert payment.notes == f"Consultation {row.reference}"
    assert (row.paid_method, row.billing_method, row.amount_minor, row.currency) == (
        "manual", "cash", 1500, "USD",
    )
    assert row.paid_on == date(2026, 10, 1) and row.paid


def test_an_unregistered_persons_payment(booking):
    row = new_request(booking, student_user_id=None, name="Ali", email="ali@x.test",
                      whatsapp="+1555")
    row = pay(booking, row, billing_method="zelle", amount_minor=900,
              transaction_number="ZL-1")
    payment = billing_services.payments_queryset().get(pk=row.payment_id)
    assert (payment.customer_type, payment.customer_name, payment.customer_phone) == (
        "unregistered", "Ali", "+1555",
    )
    assert (payment.amount_minor, payment.transaction_number) == (900, "ZL-1")


def test_one_payment_only_even_after_billing_deletes_it(booking):
    row = pay(booking, new_request(booking))
    with pytest.raises(ConflictError) as e:
        pay(booking, row)
    assert e.value.code == "consultations.already_paid"
    billing_services.payments_queryset().filter(pk=row.payment_id).delete()
    row.refresh_from_db()
    assert row.payment_id is None and row.paid
    with pytest.raises(ConflictError):
        pay(booking, row)


def test_cancelled_requests_take_no_payment(booking):
    row = services.cancel(new_request(booking), by=booking.admin)
    with pytest.raises(ConflictError) as e:
        pay(booking, row)
    assert e.value.code == "consultations.request_closed"


@pytest.mark.parametrize(
    ("extra", "field"),
    [
        ({"amount_minor": 0}, "amount_minor"),
        ({"billing_method": "stripe"}, "billing_method"),
        ({"billing_method": "barter"}, "billing_method"),
    ],
)
def test_bad_payment_fields(booking, extra, field):
    with pytest.raises(ValidationError) as e:
        pay(booking, new_request(booking), **extra)
    assert e.value.field == field


def test_a_deactivated_student_is_400_and_nothing_written(booking):
    row = new_request(booking)
    deactivated(booking.student)
    with pytest.raises(ValidationError) as e:
        pay(booking, row)
    assert e.value.field == "student"
    row.refresh_from_db()
    assert not row.paid and not billing_services.payments_queryset().exists()
```

(If `payments_queryset().filter(...).delete()` is refused by a PROTECT elsewhere, delete through `billing.services.delete_payment(payment, by=…)` instead; the point is a null `payment`.)

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/consultations/tests/test_payments.py -q` → FAIL.

- [ ] **Step 3: Implement** `services/payments.py`:

```python
"""Slice B7c C-9, phase B7-4: money paid by hand is recorded in billing in
the same transaction, so a hand sale is never left out of revenue."""

from django.db import transaction

from etqan.billing import services as billing_services
from etqan.consultations.models import Request
from etqan.consultations.services.requests import locked
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

BILLING_METHODS = billing_services.MANUAL_PAYMENT_METHODS
NOTES_LENGTH = 500


@transaction.atomic
def record_payment(  # noqa: PLR0913 -- keyword-only; mirrors the API body
    row,
    *,
    billing_method,
    by,
    amount_minor=None,
    paid_on=None,
    reference="",
    transaction_number="",
) -> Request:
    fresh = locked(row)
    if fresh.status == Request.Status.CANCELLED:
        raise ConflictError(
            "This request is closed.", code="consultations.request_closed"
        )
    if fresh.paid:
        raise ConflictError(
            "This request is paid already.", code="consultations.already_paid"
        )
    product = fresh.product
    amount = product.price_minor if amount_minor is None else amount_minor
    if amount <= 0:
        raise ValidationError("Enter an amount above zero.", field="amount_minor")
    customer = (
        {"customer_type": "student", "student_id": fresh.student.user_id,
         "customer_email": fresh.email}
        if fresh.student_id
        else {"customer_type": "unregistered", "customer_name": fresh.name,
              "customer_email": fresh.email, "customer_phone": fresh.whatsapp}
    )
    try:
        payment = billing_services.create_record(
            amount_minor=amount,
            method=billing_method,
            by=by,
            currency=product.currency,
            transaction_number=transaction_number,
            reference=reference,
            paid_on=paid_on,
            notes=f"Consultation {fresh.reference}"[:NOTES_LENGTH],
            **customer,
        )
    except ValidationError as exc:
        if exc.field == "method":
            raise ValidationError(exc.message, field="billing_method") from None
        raise
    fresh.paid_method = Request.PaidMethod.MANUAL
    fresh.billing_method = billing_method
    fresh.payment = payment
    fresh.amount_minor, fresh.currency = amount, product.currency
    fresh.transaction_number, fresh.paid_on = transaction_number, payment.paid_on
    fresh.save(update_fields=[
        "paid_method", "billing_method", "payment", "amount_minor", "currency",
        "transaction_number", "paid_on",
    ])
    return fresh
```

Confirm that `create_record` rejects `"stripe"` (online methods are not manual) with `field="method"` (`records.py:_check_method`), so the parametrized case maps to `billing_method`.

- [ ] **Step 4: Run** — `B pytest etqan/consultations -q` → PASS.
- [ ] **Step 5: Commit** — `git -C backend add etqan/consultations && git -C backend commit -m "feat(consultations): B7c hand payments recorded in billing" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 8: Read services for B5 and the week agenda (C-11, C-16)

**Files:**
- Create: `backend/etqan/consultations/services/reads.py`, `backend/etqan/consultations/tests/test_reads.py`
- Modify: `services/__init__.py` (exports)

**Interfaces:**
- Produces:
  - `ConsultationEvent(kind, request_id, product_name_ar, product_name_en, teacher_user_id, student_user_id, name, email, whatsapp, timezone, starts_at, at)` (frozen dataclass; `kind` in `created | confirmed | reschedule_requested | rescheduled | cancelled | completed`)
  - `consultation_events(*, since: datetime, until: datetime) -> list[ConsultationEvent]`: stamps in `[since, until)`, oldest first; one query
  - `consultations_starting(*, since: datetime, until: datetime) -> list[Request]`: confirmed requests starting in `[since, until)`, with `product`, `teacher__user`, `student__user`; one query
  - `AgendaDay(day: date, requests: list[Request])`, `week_agenda(week_start: date, *, teacher_user_id=None, product_id=None) -> list[AgendaDay]`: 7 academy days from `week_start`, non-cancelled requests with a start, by start; one query

- [ ] **Step 1: Write the failing tests** (`tests/test_reads.py`)

```python
from datetime import date
from datetime import timedelta

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.consultations import services
from etqan.consultations.services import common
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import new_request

pytestmark = pytest.mark.django_db
WEEK = date(2026, 10, 12)


def test_events_window_and_shape(booking, monkeypatch):
    monkeypatch.setattr(common, "now", lambda: MONDAY_4PM - timedelta(days=1))
    row = new_request(booking)
    row = services.confirm(row, by=booking.admin)
    monkeypatch.setattr(common, "now", lambda: MONDAY_4PM + timedelta(days=1))
    services.cancel(row, by=booking.admin)
    since = MONDAY_4PM - timedelta(days=2)
    with CaptureQueriesContext(connection) as ctx:
        events = services.consultation_events(since=since, until=MONDAY_4PM)
    assert len(ctx.captured_queries) == 1
    assert [e.kind for e in events] == ["created", "confirmed"]
    first = events[1]
    assert (first.request_id, first.teacher_user_id, first.student_user_id) == (
        row.pk, booking.teacher.pk, booking.student.pk,
    )
    assert (first.product_name_en, first.timezone, first.starts_at) == (
        "Placement", "Africa/Cairo", MONDAY_4PM,
    )
    later = services.consultation_events(since=MONDAY_4PM, until=MONDAY_4PM + timedelta(days=2))
    assert [e.kind for e in later] == ["cancelled"]


def test_starting_window_lists_confirmed_only(booking):
    a = services.confirm(new_request(booking), by=booking.admin)
    new_request(booking)  # pending, not listed
    services.confirm(new_request(booking, starts_at=MONDAY_4PM + timedelta(days=7)),
                     by=booking.admin)
    with CaptureQueriesContext(connection) as ctx:
        rows = services.consultations_starting(
            since=MONDAY_4PM, until=MONDAY_4PM + timedelta(hours=1)
        )
        [r.teacher.user.full_name for r in rows]
    assert rows == [a] and len(ctx.captured_queries) == 1


def test_week_agenda(booking):
    a = new_request(booking)
    b = services.confirm(
        new_request(booking, starts_at=MONDAY_4PM + timedelta(days=2, minutes=30)),
        by=booking.admin,
    )
    services.cancel(new_request(booking, starts_at=MONDAY_4PM + timedelta(days=1)),
                    by=booking.admin)
    new_request(booking, starts_at=MONDAY_4PM + timedelta(days=7))
    days = services.week_agenda(WEEK)
    assert [d.day for d in days] == [WEEK + timedelta(days=n) for n in range(7)]
    assert days[0].requests == [a] and days[2].requests == [b]
    assert sum(len(d.requests) for d in days) == 2
    assert services.week_agenda(WEEK, teacher_user_id=booking.teacher2.pk)[0].requests == []
```

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/consultations/tests/test_reads.py -q` → FAIL.

- [ ] **Step 3: Implement** `services/reads.py`:

```python
"""Slice B7c C-11, C-16: what B5's finders read (ledger D29/D39 shape) and
the office's week agenda."""

from dataclasses import dataclass
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta
from zoneinfo import ZoneInfo

from django.db.models import Q

from etqan.consultations.models import Request
from etqan.consultations.services.common import academy_zone

STAMPS = (
    ("created", "created_at"),
    ("confirmed", "confirmed_at"),
    ("reschedule_requested", "reschedule_requested_at"),
    ("rescheduled", "rescheduled_at"),
    ("cancelled", "cancelled_at"),
    ("completed", "completed_at"),
)
RELATED = ("product", "teacher__user", "student__user")


@dataclass(frozen=True)
class ConsultationEvent:
    kind: str
    request_id: int
    product_name_ar: str
    product_name_en: str
    teacher_user_id: int
    student_user_id: int | None
    name: str
    email: str
    whatsapp: str
    timezone: str
    starts_at: datetime | None
    at: datetime


@dataclass(frozen=True)
class AgendaDay:
    day: date
    requests: list


def consultation_events(*, since: datetime, until: datetime) -> list[ConsultationEvent]:
    window = Q()
    for _, field in STAMPS:
        window |= Q(**{f"{field}__gte": since, f"{field}__lt": until})
    events = []
    for row in Request.objects.select_related(*RELATED).filter(window):
        for kind, field in STAMPS:
            at = getattr(row, field)
            if at is not None and since <= at < until:
                events.append(
                    ConsultationEvent(
                        kind=kind,
                        request_id=row.pk,
                        product_name_ar=row.product.name_ar,
                        product_name_en=row.product.name_en,
                        teacher_user_id=row.teacher.user_id,
                        student_user_id=row.student.user_id if row.student_id else None,
                        name=row.name,
                        email=row.email,
                        whatsapp=row.whatsapp,
                        timezone=row.timezone,
                        starts_at=row.starts_at,
                        at=at,
                    )
                )
    return sorted(events, key=lambda e: (e.at, e.request_id))


def consultations_starting(*, since: datetime, until: datetime) -> list[Request]:
    return list(
        Request.objects.select_related(*RELATED)
        .filter(status=Request.Status.CONFIRMED, starts_at__gte=since, starts_at__lt=until)
        .order_by("starts_at", "pk")
    )


def week_agenda(week_start: date, *, teacher_user_id=None, product_id=None) -> list[AgendaDay]:
    zone = ZoneInfo(academy_zone())
    first = datetime.combine(week_start, time.min, tzinfo=zone)
    last = datetime.combine(week_start + timedelta(days=7), time.min, tzinfo=zone)
    rows = (
        Request.objects.select_related(*RELATED)
        .exclude(status=Request.Status.CANCELLED)
        .filter(starts_at__gte=first, starts_at__lt=last)
        .order_by("starts_at", "pk")
    )
    if teacher_user_id:
        rows = rows.filter(teacher__user_id=teacher_user_id)
    if product_id:
        rows = rows.filter(product_id=product_id)
    days = {week_start + timedelta(days=n): [] for n in range(7)}
    for row in rows:
        days[row.starts_at.astimezone(zone).date()].append(row)
    return [AgendaDay(day, items) for day, items in days.items()]
```

Append to `services/__init__.py`: `AgendaDay`, `ConsultationEvent`, `consultation_events`, `consultations_starting`, `week_agenda`.

- [ ] **Step 4: Run** — `B pytest etqan/consultations -q` → PASS.
- [ ] **Step 5: Commit** — `git -C backend add etqan/consultations && git -C backend commit -m "feat(consultations): B7c read services and the week agenda" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 9: Access resources and the API for products, consultants and slots (C-3, C-5, C-13, C-15)

**Files:**
- Create: `backend/etqan/consultations/api/__init__.py` (empty), `api/serializers.py`, `api/views.py`, `api/urls.py`, `tests/test_api_products.py`
- Modify: `backend/config/api_router.py` (B7 marker), `backend/etqan/access/registry.py` (B7 marker), `backend/etqan/access/tests/test_routes.py` (`ROUTES`, `FEATURES`, `FEATURE_WORDS`)

**Interfaces:**
- Consumes: Tasks 3–4 services.
- Produces routes and JSON shapes used by the dashboard (Task 12):
  - `GET|POST consultations/products/` (filters `mode`, `featured`, `status`), `GET|PATCH|DELETE consultations/products/<pk>/`
  - product: `{id, name_ar, name_en, description_ar, description_en, price_minor, currency, duration_minutes, validity_days, participants, delivery_mode, status, enabled, featured, reschedulable, fee_enabled, teacher_share_bp, bookable, cover_url, teachers: [{id, full_name}]}` (`id` = user id)
  - `GET consultations/products/<pk>/slots/?teacher=&from=&days=&request=` → `{slots: [{starts_at, remaining}], availability_off}`
  - `GET consultations/consultants/?offers=true` → `[{id, full_name, offers}]`; `GET|PUT consultations/consultants/<user id>/` → `{teacher_id, offers}`
  - serializer helpers `product_data(p) -> dict`, `person(user) -> dict`

- [ ] **Step 1: Write the failing tests** (`tests/test_api_products.py`)

```python
from datetime import time

import pytest

from etqan.consultations import services
from etqan.consultations.models import Product
from etqan.scheduling import services as scheduling_services

pytestmark = pytest.mark.django_db
P = "/api/v1/consultations/products/"
C = "/api/v1/consultations/consultants/"


@pytest.fixture
def admin(api_for, people):
    return api_for("admin")


def body(people, **extra):
    return {
        "name_ar": "استشارة", "name_en": "Placement", "description_en": "d",
        "price_minor": 1500, "currency": "USD", "duration_minutes": 30,
        "validity_days": 7, "participants": 2, "delivery_mode": "video_call",
        "teacher_ids": [people.teacher.pk], **extra,
    }


def test_opt_in_then_product_round_trip(admin, people):
    assert admin.put(f"{C}{people.teacher.pk}/", {"offers": True}, format="json").json() == {
        "teacher_id": people.teacher.pk, "offers": True,
    }
    assert [t["id"] for t in admin.get(C, {"offers": "true"}).json()] == [people.teacher.pk]
    resp = admin.post(P, body(people), format="multipart")
    assert resp.status_code == 201, resp.content
    pid = resp.json()["id"]
    assert resp.json()["teachers"] == [{"id": people.teacher.pk, "full_name": "Bilal"}]
    assert resp.json()["bookable"] is True
    resp = admin.patch(f"{P}{pid}/", {"status": "archived"}, format="multipart")
    assert (resp.status_code, resp.json()["bookable"]) == (200, False)
    assert [p["id"] for p in admin.get(P, {"status": "archived"}).json()] == [pid]
    assert admin.delete(f"{P}{pid}/").status_code == 204
    assert not Product.objects.exists()


def test_product_errors_name_their_field(admin, people):
    resp = admin.post(P, body(people), format="multipart")
    assert (resp.status_code, list(resp.json())) == (400, ["teachers"])
    admin.put(f"{C}{people.teacher.pk}/", {"offers": True}, format="json")
    resp = admin.post(P, body(people, price_minor=0), format="multipart")
    assert (resp.status_code, list(resp.json())) == (400, ["price_minor"])


def test_slots(admin, people):
    admin.put(f"{C}{people.teacher.pk}/", {"offers": True}, format="json")
    scheduling_services.set_availability(
        people.teacher_profile.pk,
        [{"weekday": 0, "start_time": time(16), "end_time": time(17)}],
    )
    pid = admin.post(P, body(people), format="multipart").json()["id"]
    resp = admin.get(f"{P}{pid}/slots/", {"teacher": people.teacher.pk,
                                           "from": "2026-10-12", "days": 7})
    assert resp.status_code == 200, resp.content
    assert resp.json() == {
        "availability_off": False,
        "slots": [
            {"starts_at": "2026-10-12T16:00:00+00:00", "remaining": 2},
            {"starts_at": "2026-10-12T16:30:00+00:00", "remaining": 2},
        ],
    }
    assert admin.get(f"{P}{pid}/slots/", {"from": "2026-10-12"}).status_code == 400


def test_product_list_tuple_codes(staff_for, people, admin):
    admin.put(f"{C}{people.teacher.pk}/", {"offers": True}, format="json")
    admin.post(P, body(people), format="multipart")
    for code in ("consultation.view_any", "consultation_request.create",
                 "consultation_request.update"):
        assert staff_for(code).get(P).status_code == 200
    assert staff_for("consultation_request.view_any").get(P).status_code == 403


def test_family_and_teachers_get_403(api_for, people):
    for role in ("student", "parent", "teacher"):
        assert api_for(role).get(P).status_code == 403


def test_switch_off_is_404(admin, people, set_features):
    set_features(consultations=False)
    assert admin.get(P).status_code == 404
```

(The view renders `starts_at` itself with `datetime.isoformat()`, so UTC reads `+00:00`, the same as the rest of this app's payloads.)

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/consultations/tests/test_api_products.py -q` → FAIL (404s).

- [ ] **Step 3: Implement**

`api/serializers.py`:

```python
from rest_framework import serializers

from etqan.consultations.models import Product
from etqan.consultations.models import Request


def _iso(value):
    return value.isoformat() if value else None


def person(user) -> dict:
    return {"id": user.pk, "full_name": user.full_name}


class ProductInput(serializers.Serializer):
    """Shape only; the services own every rule (and its field name)."""

    name_ar = serializers.CharField(required=False, allow_blank=True, max_length=400)
    name_en = serializers.CharField(required=False, allow_blank=True, max_length=400)
    description_ar = serializers.CharField(required=False, allow_blank=True, max_length=10000)
    description_en = serializers.CharField(required=False, allow_blank=True, max_length=10000)
    price_minor = serializers.IntegerField(required=False)
    currency = serializers.CharField(required=False, allow_blank=True, max_length=8)
    duration_minutes = serializers.IntegerField(required=False)
    validity_days = serializers.IntegerField(required=False)
    participants = serializers.IntegerField(required=False)
    delivery_mode = serializers.CharField(required=False, max_length=16)
    status = serializers.CharField(required=False, max_length=16)
    enabled = serializers.BooleanField(required=False)
    featured = serializers.BooleanField(required=False)
    reschedulable = serializers.BooleanField(required=False)
    fee_enabled = serializers.BooleanField(required=False)
    teacher_share_bp = serializers.IntegerField(required=False)
    teacher_ids = serializers.ListField(
        child=serializers.IntegerField(min_value=1), required=False, max_length=200
    )
    cover = serializers.FileField(required=False)
    remove_cover = serializers.BooleanField(required=False)


class OffersInput(serializers.Serializer):
    offers = serializers.BooleanField()


class SlotsQuery(serializers.Serializer):
    teacher = serializers.IntegerField(min_value=1)
    # "from" is a Python keyword: read it from the query dict by hand.
    days = serializers.IntegerField(required=False, default=7)
    request = serializers.IntegerField(required=False, min_value=1)


def product_data(p: Product) -> dict:
    return {
        "id": p.pk,
        "name_ar": p.name_ar,
        "name_en": p.name_en,
        "description_ar": p.description_ar,
        "description_en": p.description_en,
        "price_minor": p.price_minor,
        "currency": p.currency,
        "duration_minutes": p.duration_minutes,
        "validity_days": p.validity_days,
        "participants": p.participants,
        "delivery_mode": p.delivery_mode,
        "status": p.status,
        "enabled": p.enabled,
        "featured": p.featured,
        "reschedulable": p.reschedulable,
        "fee_enabled": p.fee_enabled,
        "teacher_share_bp": p.teacher_share_bp,
        "bookable": p.bookable,
        "cover_url": p.cover.url if p.cover else "",
        "teachers": sorted(
            (person(t.user) for t in p.teachers.all()), key=lambda t: t["full_name"]
        ),
    }
```

(Task 10 adds the request serializers to this module.)

`api/views.py`:

```python
from datetime import date
from zoneinfo import ZoneInfo

from django.http import Http404
from rest_framework import status
from rest_framework.parsers import JSONParser
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.consultations import services
from etqan.consultations.api import serializers as s
from etqan.consultations.services import common
from etqan.consultations.services.common import teacher_profile
from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode

FEATURE = "consultations"
OFFICE = [HasCode, FeatureOn]
PARSERS = [MultiPartParser, JSONParser]
PRODUCT_READERS = (
    "consultation.view_any",
    "consultation_request.create",
    "consultation_request.update",
)


def _valid(serializer_class, data, **kwargs) -> dict:
    ser = serializer_class(data=data, **kwargs)
    ser.is_valid(raise_exception=True)
    return dict(ser.validated_data)


def _flag(value: str):
    return {"true": True, "false": False}.get(value or "")


def _product(pk):
    try:
        return services.get_product(pk)
    except NotFoundError:
        raise Http404 from None


def _product_fields(v: dict) -> dict:
    if "teacher_ids" in v:
        v["teacher_user_ids"] = v.pop("teacher_ids")
    return v


class ProductListView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"GET": PRODUCT_READERS, "POST": "consultation.create"}
    parser_classes = PARSERS

    def get(self, request):
        p = request.query_params
        qs = services.filter_products(
            services.products_queryset(),
            mode=p.get("mode", ""),
            featured=_flag(p.get("featured")),
            status=p.get("status", ""),
        )
        return Response([s.product_data(row) for row in qs])

    def post(self, request):
        v = _product_fields(_valid(s.ProductInput, request.data))
        v.pop("remove_cover", None)
        row = services.create_product(
            teacher_user_ids=v.pop("teacher_user_ids", []), **v
        )
        return Response(
            s.product_data(services.get_product(row.pk)),
            status=status.HTTP_201_CREATED,
        )


class ProductDetailView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {
        "GET": "consultation.view_any",
        "PATCH": "consultation.update",
        "DELETE": "consultation.delete",
    }
    parser_classes = PARSERS

    def get(self, request, pk):
        return Response(s.product_data(_product(pk)))

    def patch(self, request, pk):
        v = _product_fields(_valid(s.ProductInput, request.data, partial=True))
        services.update_product(_product(pk), **v)
        return Response(s.product_data(services.get_product(pk)))

    def delete(self, request, pk):
        services.delete_product(_product(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class SlotsView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {
        "GET": ("consultation_request.create", "consultation_request.update")
    }

    def get(self, request, pk):
        product = _product(pk)
        v = _valid(s.SlotsQuery, request.query_params)
        raw = request.query_params.get("from", "")
        try:
            start = date.fromisoformat(raw) if raw else None
        except ValueError:
            raise ValidationError("Use a date like 2026-10-12.", field="from") from None
        if start is None:
            start = common.now().astimezone(ZoneInfo(common.academy_zone())).date()
        moving = None
        if v.get("request"):
            try:
                moving = services.get_request(v["request"])
            except NotFoundError:
                raise ValidationError("Unknown request.", field="request") from None
        result = services.free_slots(
            product, v["teacher"], start, v["days"], request=moving
        )
        return Response(
            {
                "availability_off": result.availability_off,
                "slots": [
                    {"starts_at": slot.starts_at.isoformat(), "remaining": slot.remaining}
                    for slot in result.slots
                ],
            }
        )


class ConsultantListView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"GET": PRODUCT_READERS}

    def get(self, request):
        teachers = services.opted_in_teachers()
        rows = [{**s.person(t.user), "offers": True} for t in teachers]
        if request.query_params.get("offers") != "true":
            ids = {t.pk for t in teachers}
            rows = [
                {**s.person(t.user), "offers": t.pk in ids}
                for t in identity_services.active_teachers()
            ]
        return Response(rows)


class ConsultantDetailView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"GET": "consultation.view_any", "PUT": "consultation.update"}

    def _profile(self, user_id):
        try:
            return teacher_profile(user_id)
        except ValidationError:
            raise Http404 from None

    def get(self, request, user_id):
        profile = self._profile(user_id)
        return Response({"teacher_id": user_id, "offers": services.offers(profile.pk)})

    def put(self, request, user_id):
        self._profile(user_id)
        v = _valid(s.OffersInput, request.data)
        offers = services.set_consultant(user_id, v["offers"], by=request.user)
        return Response({"teacher_id": user_id, "offers": offers})
```

`api/urls.py`:

```python
from django.urls import path

from etqan.consultations.api import views

urlpatterns = [
    path("products/", views.ProductListView.as_view()),
    path("products/<int:pk>/", views.ProductDetailView.as_view()),
    path("products/<int:pk>/slots/", views.SlotsView.as_view()),
    path("consultants/", views.ConsultantListView.as_view()),
    path("consultants/<int:user_id>/", views.ConsultantDetailView.as_view()),
]
```

`backend/config/api_router.py`, under `# ── phase B7 ──` (below B7a's `recorded/` line if present):

```python
    path("consultations/", include("etqan.consultations.api.urls")),
```

`backend/etqan/access/registry.py`, under `# ── phase B7 ──` in `RESOURCES` (below B7a's three resources if present). All three go in now; the `in_use` test passes only after Task 10 adds the request routes:

```python
    Resource(
        "consultation",
        "Consultations",
        "الاستشارات",
        ("view_any", "create", "update", "delete"),
    ),
    Resource(
        "consultation_request",
        "Consultation requests",
        "طلبات الاستشارات",
        ("view", "view_any", "create", "update", "delete"),
    ),
    Resource(
        "consultation_schedule",
        "Consultation schedules",
        "مواعيد الاستشارات",
        ("view_any",),
    ),
```

`backend/etqan/access/tests/test_routes.py`:
- `ROUTES`, append:

```python
    # Phase B7, slice B7c
    (
        "GET",
        "/api/v1/consultations/products/",
        ("consultation.view_any", "consultation_request.create", "consultation_request.update"),
    ),
    ("POST", "/api/v1/consultations/products/", "consultation.create"),
    ("GET", f"/api/v1/consultations/products/{N}/", "consultation.view_any"),
    ("PATCH", f"/api/v1/consultations/products/{N}/", "consultation.update"),
    ("DELETE", f"/api/v1/consultations/products/{N}/", "consultation.delete"),
    (
        "GET",
        f"/api/v1/consultations/products/{N}/slots/",
        ("consultation_request.create", "consultation_request.update"),
    ),
    (
        "GET",
        "/api/v1/consultations/consultants/",
        ("consultation.view_any", "consultation_request.create", "consultation_request.update"),
    ),
    ("GET", f"/api/v1/consultations/consultants/{N}/", "consultation.view_any"),
    ("PUT", f"/api/v1/consultations/consultants/{N}/", "consultation.update"),
```

- `FEATURES`, append:

```python
    # Phase B7, slice B7c
    **dict.fromkeys(
        (
            ("GET", "/api/v1/consultations/products/"),
            ("POST", "/api/v1/consultations/products/"),
            ("GET", f"/api/v1/consultations/products/{N}/"),
            ("PATCH", f"/api/v1/consultations/products/{N}/"),
            ("DELETE", f"/api/v1/consultations/products/{N}/"),
            ("GET", f"/api/v1/consultations/products/{N}/slots/"),
            ("GET", "/api/v1/consultations/consultants/"),
            ("GET", f"/api/v1/consultations/consultants/{N}/"),
            ("PUT", f"/api/v1/consultations/consultants/{N}/"),
        ),
        "consultations",
    ),
```

- `FEATURE_WORDS`, append `"/consultations/": "consultations",  # B7c`.

- [ ] **Step 4: Run** — `B pytest etqan/consultations etqan/access -q`. Expected: consultations PASS; `test_every_code_in_the_table_is_in_the_registry_and_in_use` FAILS on the request and schedule codes until Task 10. This is expected; do not weaken the test.
- [ ] **Step 5: Commit** — `git -C backend add etqan/consultations config/api_router.py etqan/access && git -C backend commit -m "feat(consultations): B7c API for products, consultants and slots" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 10: The request API, teacher scoping and the schedule (C-6…C-12)

**Files:**
- Create: `backend/etqan/consultations/api/request_views.py`, `tests/test_api_requests.py`
- Modify: `api/serializers.py` (request shapes), `api/urls.py`, `backend/etqan/access/tests/test_routes.py`

**Interfaces:**
- Consumes: Tasks 5–8 services; `etqan.platform.permissions` `HasCode`, `IsTeacher`, `ReadOnly`, `FeatureOn`, `NotImpersonating`, `codes_of`, `role_of`; `etqan.platform.pagination.StandardPagination`; `etqan.platform.params.as_int`.
- Produces routes (all under `/api/v1/consultations/`, feature `consultations`):
  - `GET|POST requests/` (paginated; filters `product`, `teacher`, `session_status`, `student_attendance`, `teacher_attendance`, `paid_method` (`manual|stripe|paypal|unpaid`), `billing_method`, `status`, `from`, `to`)
  - `GET|PATCH|DELETE requests/<pk>/`
  - `POST requests/<pk>/{confirm,cancel,request-reschedule,reschedule,decline-reschedule}/`
  - `POST requests/<pk>/delivery/`, `POST requests/<pk>/complete/` (office or the request's teacher)
  - `POST requests/<pk>/payment/` (office with `consultation_request.update` and `payment.create`; `NotImpersonating`)
  - `GET schedule/?week=YYYY-MM-DD&teacher=&product=` → `{week, days: [{day, requests: [...]}]}`
  - request JSON (`request_data(row, *, for_teacher=False)`): `{id, reference, product: {id, name_ar, name_en, delivery_mode, duration_minutes, price_minor, currency, reschedulable}, teacher: {id, full_name}, student: {id, full_name} | null, name, email, whatsapp, timezone, starts_at, ends_at, meeting_url, session_status, student_attendance, teacher_attendance, status, reschedule_note, outside_validity, confirmed_at, reschedule_requested_at, rescheduled_at, cancelled_at, completed_at, created_at}` plus, for the office only, `notes` and `payment: {paid_method, billing_method, amount_minor, fee_minor, currency, transaction_number, paid_on, payment_id, billing_status}`
  - write answers for a start (create, PATCH, reschedule): `{request, warnings: {conflicts, outside_availability, outside_validity} | null}`

- [ ] **Step 1: Write the failing tests** (`tests/test_api_requests.py`)

```python
from datetime import timedelta

import pytest
from rest_framework.test import APIClient

from etqan.consultations import services
from etqan.consultations.services import common
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import new_request
from etqan.platform.permissions import IMPERSONATOR_KEY

pytestmark = pytest.mark.django_db
R = "/api/v1/consultations/requests/"


@pytest.fixture
def admin(booking, api_for):
    client = api_for("admin")
    booking.admin = client.user
    return client


def as_teacher(user):
    client = APIClient()
    client.force_login(user)
    return client


def test_create_list_and_detail(admin, booking):
    resp = admin.post(R, {
        "product": booking.product.pk, "teacher": booking.teacher.pk,
        "student": booking.student.pk, "starts_at": MONDAY_4PM.isoformat(),
    }, format="json")
    assert resp.status_code == 201, resp.content
    data = resp.json()
    assert data["warnings"] == {
        "conflicts": [], "outside_availability": False, "outside_validity": False,
    }
    rid = data["request"]["id"]
    assert data["request"]["reference"] == f"CR-{rid:06d}"
    assert data["request"]["payment"]["paid_method"] == ""
    listing = admin.get(R, {"status": "pending_review"}).json()
    assert [r["id"] for r in listing["results"]] == [rid]
    assert admin.get(f"{R}{rid}/").json()["name"] == "Yusuf Omar"


def test_transitions_over_http(admin, booking, monkeypatch):
    row = new_request(booking)
    assert admin.post(f"{R}{row.pk}/confirm/").json()["request"]["status"] == "confirmed"
    resp = admin.post(f"{R}{row.pk}/request-reschedule/", {"note": "x"}, format="json")
    assert (resp.status_code, resp.json()["code"]) == (409, "consultations.not_reschedulable")
    resp = admin.post(f"{R}{row.pk}/reschedule/", {
        "starts_at": (MONDAY_4PM + timedelta(minutes=30)).isoformat()}, format="json")
    assert resp.status_code == 200 and resp.json()["warnings"] is not None
    monkeypatch.setattr(common, "now", lambda: MONDAY_4PM + timedelta(hours=2))
    resp = admin.post(f"{R}{row.pk}/delivery/", {
        "student_attendance": "present", "teacher_attendance": "present",
        "session_status": "completed"}, format="json")
    assert resp.status_code == 200, resp.content
    assert admin.post(f"{R}{row.pk}/complete/").json()["request"]["status"] == "completed"
    assert admin.post(f"{R}{row.pk}/cancel/").status_code == 409


def test_payment_needs_payment_create_and_no_impersonation(booking, staff_for, admin):
    row = new_request(booking)
    url = f"{R}{row.pk}/payment/"
    clerk = staff_for("consultation_request.update")
    resp = clerk.post(url, {"billing_method": "cash"}, format="json")
    assert resp.status_code == 403
    assert "payment" in str(resp.json())
    cashier = staff_for("consultation_request.update", "payment.create")
    resp = cashier.post(url, {"billing_method": "cash"}, format="json")
    assert resp.status_code == 200, resp.content
    assert resp.json()["request"]["payment"]["billing_method"] == "cash"
    other = new_request(booking)
    session = admin.session
    session[IMPERSONATOR_KEY] = {"id": 1}
    session.save()
    resp = admin.post(f"{R}{other.pk}/payment/", {"billing_method": "cash"}, format="json")
    assert resp.status_code == 403


def test_teacher_scope(booking, admin, monkeypatch):
    mine = services.confirm(new_request(booking), by=booking.admin)
    teacher = as_teacher(booking.teacher)
    stranger = as_teacher(booking.teacher2)
    listing = teacher.get(R).json()["results"]
    assert [r["id"] for r in listing] == [mine.pk]
    assert "payment" not in listing[0] and "notes" not in listing[0]
    assert stranger.get(R).json()["results"] == []
    assert stranger.get(f"{R}{mine.pk}/").status_code == 404
    for action in ("confirm", "cancel", "payment"):
        assert teacher.post(f"{R}{mine.pk}/{action}/", {}, format="json").status_code == 403
    assert teacher.patch(f"{R}{mine.pk}/", {"notes": "x"}, format="json").status_code == 403
    assert teacher.delete(f"{R}{mine.pk}/").status_code == 403
    monkeypatch.setattr(common, "now", lambda: MONDAY_4PM + timedelta(hours=1))
    resp = teacher.post(f"{R}{mine.pk}/delivery/", {
        "meeting_url": "https://meet.test/b", "session_status": "completed",
        "student_attendance": "present", "teacher_attendance": "present"}, format="json")
    assert resp.status_code == 200, resp.content
    assert stranger.post(f"{R}{mine.pk}/complete/").status_code == 404
    assert teacher.post(f"{R}{mine.pk}/complete/").json()["request"]["status"] == "completed"


def test_students_and_parents_get_403(api_for, booking):
    for role in ("student", "parent"):
        assert api_for(role).get(R).status_code == 403


def test_schedule_week(admin, booking):
    row = new_request(booking)
    resp = admin.get("/api/v1/consultations/schedule/", {"week": "2026-10-12"})
    assert resp.status_code == 200, resp.content
    days = resp.json()["days"]
    assert len(days) == 7 and [r["id"] for r in days[0]["requests"]] == [row.pk]


def test_delete_and_switch_off(admin, booking, set_features):
    row = new_request(booking)
    assert admin.delete(f"{R}{row.pk}/").status_code == 204
    set_features(consultations=False)
    assert admin.get(R).status_code == 404
```

(`IMPERSONATOR_KEY` is set on the admin client's session to impersonate, as B9b's tests do. If those tests use a helper, use it; check with `B grep -rn "IMPERSONATOR_KEY" etqan/*/tests | head -3`.)

- [ ] **Step 2: Run to see it fail** — `B pytest etqan/consultations/tests/test_api_requests.py -q` → FAIL (404s).

- [ ] **Step 3: Implement**

`api/serializers.py` gains:

```python
class RequestInput(serializers.Serializer):
    product = serializers.IntegerField(min_value=1, required=False)
    teacher = serializers.IntegerField(min_value=1, required=False)
    student = serializers.IntegerField(min_value=1, required=False, allow_null=True)
    name = serializers.CharField(required=False, allow_blank=True, max_length=400)
    email = serializers.CharField(required=False, allow_blank=True, max_length=400)
    whatsapp = serializers.CharField(required=False, allow_blank=True, max_length=100)
    timezone = serializers.CharField(required=False, allow_blank=True, max_length=64)
    starts_at = serializers.DateTimeField(required=False, allow_null=True)
    meeting_url = serializers.CharField(required=False, allow_blank=True, max_length=1000)
    notes = serializers.CharField(required=False, allow_blank=True, max_length=4000)


class NoteInput(serializers.Serializer):
    note = serializers.CharField(required=False, allow_blank=True, default="", max_length=4000)


class RescheduleInput(serializers.Serializer):
    starts_at = serializers.DateTimeField()
    teacher = serializers.IntegerField(min_value=1, required=False)


class DeliveryInput(serializers.Serializer):
    student_attendance = serializers.CharField(required=False, max_length=16)
    teacher_attendance = serializers.CharField(required=False, max_length=16)
    session_status = serializers.CharField(required=False, max_length=16)
    meeting_url = serializers.CharField(required=False, allow_blank=True, max_length=1000)


class PaymentInput(serializers.Serializer):
    billing_method = serializers.CharField(max_length=32)
    amount_minor = serializers.IntegerField(required=False)
    paid_on = serializers.DateField(required=False, allow_null=True, default=None)
    reference = serializers.CharField(required=False, allow_blank=True, default="", max_length=120)
    transaction_number = serializers.CharField(
        required=False, allow_blank=True, default="", max_length=200
    )


def _outside_validity(row: Request) -> bool:
    """C-10, shown in the list."""
    if not (row.paid_on and row.starts_at):
        return False
    local = row.starts_at.astimezone(ZoneInfo(academy_zone())).date()
    return local > row.paid_on + timedelta(days=row.product.validity_days)


def request_data(row: Request, *, for_teacher: bool = False) -> dict:
    data = {
        "id": row.pk,
        "reference": row.reference,
        "product": {
            "id": row.product_id,
            "name_ar": row.product.name_ar,
            "name_en": row.product.name_en,
            "delivery_mode": row.product.delivery_mode,
            "duration_minutes": row.product.duration_minutes,
            "price_minor": row.product.price_minor,
            "currency": row.product.currency,
            "reschedulable": row.product.reschedulable,
        },
        "teacher": person(row.teacher.user),
        "student": person(row.student.user) if row.student_id else None,
        "name": row.name,
        "email": row.email,
        "whatsapp": row.whatsapp,
        "timezone": row.timezone,
        "starts_at": _iso(row.starts_at),
        "ends_at": _iso(row.ends_at),
        "meeting_url": row.meeting_url,
        "session_status": row.session_status,
        "student_attendance": row.student_attendance,
        "teacher_attendance": row.teacher_attendance,
        "status": row.status,
        "reschedule_note": row.reschedule_note,
        "outside_validity": _outside_validity(row),
        "created_at": _iso(row.created_at),
        "confirmed_at": _iso(row.confirmed_at),
        "reschedule_requested_at": _iso(row.reschedule_requested_at),
        "rescheduled_at": _iso(row.rescheduled_at),
        "cancelled_at": _iso(row.cancelled_at),
        "completed_at": _iso(row.completed_at),
    }
    if for_teacher:
        return data
    data["notes"] = row.notes
    data["payment"] = {
        "paid_method": row.paid_method,
        "billing_method": row.billing_method,
        "amount_minor": row.amount_minor,
        "fee_minor": row.fee_minor,
        "currency": row.currency,
        "transaction_number": row.transaction_number,
        "paid_on": row.paid_on.isoformat() if row.paid_on else None,
        "payment_id": row.payment_id,
        "billing_status": row.payment.status if row.payment_id else None,
    }
    return data
```

Add at the top of `serializers.py`: `from datetime import timedelta`, `from zoneinfo import ZoneInfo`, `from etqan.consultations.services.common import academy_zone`.

`api/request_views.py`:

```python
from datetime import date
from datetime import timedelta
from zoneinfo import ZoneInfo

from django.http import Http404
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.consultations import services
from etqan.consultations.api import serializers as s
from etqan.consultations.services import common
from etqan.platform.exceptions import ForbiddenError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.pagination import StandardPagination
from etqan.platform.params import as_int
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.platform.permissions import IsTeacher
from etqan.platform.permissions import NotImpersonating
from etqan.platform.permissions import ReadOnly
from etqan.platform.permissions import codes_of
from etqan.platform.permissions import role_of

FEATURE = "consultations"
OFFICE = [HasCode, FeatureOn]
TEACHER_READS = [HasCode | (ReadOnly & IsTeacher), FeatureOn]
TEACHER_WRITES = [HasCode | IsTeacher, FeatureOn]
UPDATE = {"POST": "consultation_request.update"}


def _is_teacher(user) -> bool:
    return role_of(user) == "teacher"


def _row(request, pk):
    """C-12: a teacher reaches only their own requests (404 otherwise)."""
    qs = services.requests_queryset()
    if _is_teacher(request.user):
        qs = services.for_teacher(qs, request.user)
    row = qs.filter(pk=pk).first()
    if row is None:
        raise Http404
    return row


def _data(request, row) -> dict:
    return s.request_data(row, for_teacher=_is_teacher(request.user))


def _answer(request, row, warnings=None, code=status.HTTP_200_OK):
    fresh = services.get_request(row.pk)
    return Response(
        {"request": _data(request, fresh),
         "warnings": warnings.as_dict() if warnings else None},
        status=code,
    )


def _valid(serializer_class, data, **kwargs) -> dict:
    ser = serializer_class(data=data, **kwargs)
    ser.is_valid(raise_exception=True)
    return dict(ser.validated_data)


def _day(value, field):
    if not value:
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        raise ValidationError("Use a date like 2026-10-12.", field=field) from None


def _changes(v: dict) -> dict:
    renames = {"product": "product_id", "teacher": "teacher_user_id",
               "student": "student_user_id"}
    return {renames.get(k, k): value for k, value in v.items()}


class RequestListView(APIView):
    feature = FEATURE
    permission_classes = TEACHER_READS
    permission_codes = {
        "GET": "consultation_request.view_any",
        "POST": "consultation_request.create",
    }

    def get(self, request):
        p = request.query_params
        qs = services.requests_queryset()
        if _is_teacher(request.user):
            qs = services.for_teacher(qs, request.user)
        qs = services.filter_requests(
            qs,
            product=as_int(p.get("product", "")),
            teacher=as_int(p.get("teacher", "")),
            session_status=p.get("session_status", ""),
            student_attendance=p.get("student_attendance", ""),
            teacher_attendance=p.get("teacher_attendance", ""),
            paid_method=p.get("paid_method", ""),
            billing_method=p.get("billing_method", ""),
            status=p.get("status", ""),
            date_from=_day(p.get("from"), "from"),
            date_to=_day(p.get("to"), "to"),
        )
        paginator = StandardPagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        return paginator.get_paginated_response([_data(request, r) for r in page])

    def post(self, request):
        v = _changes(_valid(s.RequestInput, request.data))
        row, warnings = services.create_request(
            product_id=v.pop("product_id", None),
            teacher_user_id=v.pop("teacher_user_id", None),
            by=request.user,
            **v,
        )
        return _answer(request, row, warnings, status.HTTP_201_CREATED)


class RequestDetailView(APIView):
    feature = FEATURE
    permission_classes = TEACHER_READS
    permission_codes = {
        "GET": "consultation_request.view",
        "PATCH": "consultation_request.update",
        "DELETE": "consultation_request.delete",
    }

    def get(self, request, pk):
        return Response(_data(request, _row(request, pk)))

    def patch(self, request, pk):
        row = _row(request, pk)
        v = _changes(_valid(s.RequestInput, request.data, partial=True))
        v.pop("student_user_id", None)  # the person is fixed once recorded
        row, warnings = services.update_request(row, by=request.user, **v)
        return _answer(request, row, warnings)

    def delete(self, request, pk):
        services.delete_request(_row(request, pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class _Move(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = UPDATE


class ConfirmView(_Move):
    def post(self, request, pk):
        return _answer(request, services.confirm(_row(request, pk), by=request.user))


class CancelView(_Move):
    def post(self, request, pk):
        return _answer(request, services.cancel(_row(request, pk), by=request.user))


class RequestRescheduleView(_Move):
    def post(self, request, pk):
        v = _valid(s.NoteInput, request.data)
        row = services.request_reschedule(_row(request, pk), note=v["note"], by=request.user)
        return _answer(request, row)


class RescheduleView(_Move):
    def post(self, request, pk):
        v = _valid(s.RescheduleInput, request.data)
        row, warnings = services.reschedule(
            _row(request, pk), starts_at=v["starts_at"], by=request.user,
            teacher_user_id=v.get("teacher"),
        )
        return _answer(request, row, warnings)


class DeclineRescheduleView(_Move):
    def post(self, request, pk):
        v = _valid(s.NoteInput, request.data)
        row = services.decline_reschedule(_row(request, pk), note=v["note"], by=request.user)
        return _answer(request, row)


class DeliveryView(APIView):
    feature = FEATURE
    permission_classes = TEACHER_WRITES
    permission_codes = UPDATE

    def post(self, request, pk):
        v = _valid(s.DeliveryInput, request.data)
        return _answer(request, services.record_delivery(_row(request, pk), **v))


class CompleteView(APIView):
    feature = FEATURE
    permission_classes = TEACHER_WRITES
    permission_codes = UPDATE

    def post(self, request, pk):
        return _answer(request, services.complete(_row(request, pk), by=request.user))


class PaymentView(APIView):
    feature = FEATURE
    permission_classes = [HasCode, NotImpersonating, FeatureOn]
    permission_codes = UPDATE

    def post(self, request, pk):
        row = _row(request, pk)
        if role_of(request.user) != "admin" and "payment.create" not in codes_of(
            request.user
        ):
            # C-9: platform ForbiddenError carries no code; the message names
            # the permission.
            raise ForbiddenError(
                "Recording a payment also needs the payment permission "
                "(payment.create).",
                field="payment",
            )
        v = _valid(s.PaymentInput, request.data)
        return _answer(request, services.record_payment(row, by=request.user, **v))


class ScheduleView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"GET": "consultation_schedule.view_any"}

    def get(self, request):
        p = request.query_params
        week = _day(p.get("week"), "week")
        if week is None:
            today = common.now().astimezone(ZoneInfo(common.academy_zone())).date()
            week = today - timedelta(days=today.weekday())
        days = services.week_agenda(
            week,
            teacher_user_id=as_int(p.get("teacher", "")),
            product_id=as_int(p.get("product", "")),
        )
        return Response(
            {
                "week": week.isoformat(),
                "days": [
                    {"day": d.day.isoformat(),
                     "requests": [_data(request, r) for r in d.requests]}
                    for d in days
                ],
            }
        )
```

The view looks the row up before the `payment.create` check, so a staff account holding only `consultation_request.update` gets 404 for an unknown id. The route-coverage test (`test_staff_pass_with_the_code_and_get_403_without_it`) posts to id `N` and expects "not 403" with the declared code alone, so the order matters. `NotFoundError` from `services.get_request` cannot occur in `_answer` because the row was just read.

`api/urls.py` adds:

```python
from etqan.consultations.api import request_views as rv

    path("requests/", rv.RequestListView.as_view()),
    path("requests/<int:pk>/", rv.RequestDetailView.as_view()),
    path("requests/<int:pk>/confirm/", rv.ConfirmView.as_view()),
    path("requests/<int:pk>/cancel/", rv.CancelView.as_view()),
    path("requests/<int:pk>/request-reschedule/", rv.RequestRescheduleView.as_view()),
    path("requests/<int:pk>/reschedule/", rv.RescheduleView.as_view()),
    path("requests/<int:pk>/decline-reschedule/", rv.DeclineRescheduleView.as_view()),
    path("requests/<int:pk>/delivery/", rv.DeliveryView.as_view()),
    path("requests/<int:pk>/complete/", rv.CompleteView.as_view()),
    path("requests/<int:pk>/payment/", rv.PaymentView.as_view()),
    path("schedule/", rv.ScheduleView.as_view()),
```

`test_routes.py`, appended to the B7c `ROUTES` block:

```python
    ("GET", "/api/v1/consultations/requests/", "consultation_request.view_any"),
    ("POST", "/api/v1/consultations/requests/", "consultation_request.create"),
    ("GET", f"/api/v1/consultations/requests/{N}/", "consultation_request.view"),
    ("PATCH", f"/api/v1/consultations/requests/{N}/", "consultation_request.update"),
    ("DELETE", f"/api/v1/consultations/requests/{N}/", "consultation_request.delete"),
    ("POST", f"/api/v1/consultations/requests/{N}/confirm/", "consultation_request.update"),
    ("POST", f"/api/v1/consultations/requests/{N}/cancel/", "consultation_request.update"),
    ("POST", f"/api/v1/consultations/requests/{N}/request-reschedule/", "consultation_request.update"),
    ("POST", f"/api/v1/consultations/requests/{N}/reschedule/", "consultation_request.update"),
    ("POST", f"/api/v1/consultations/requests/{N}/decline-reschedule/", "consultation_request.update"),
    ("POST", f"/api/v1/consultations/requests/{N}/delivery/", "consultation_request.update"),
    ("POST", f"/api/v1/consultations/requests/{N}/complete/", "consultation_request.update"),
    ("POST", f"/api/v1/consultations/requests/{N}/payment/", "consultation_request.update"),
    ("GET", "/api/v1/consultations/schedule/", "consultation_schedule.view_any"),
```

and the same fourteen `(method, path)` pairs in the B7c `FEATURES` block.

- [ ] **Step 4: Run** — `B pytest etqan/consultations etqan/access -q` → PASS, including the `in_use` equality test. `B lint-imports`.
- [ ] **Step 5: Commit** — `git -C backend add etqan/consultations etqan/access/tests/test_routes.py && git -C backend commit -m "feat(consultations): B7c request API, teacher scope and schedule" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 11: Demo seed (§6)

**Files:**
- Modify or create: `backend/etqan/tenants/seeds/b7.py` (add `seed_consultations`; if B7a has not created the module yet, create it with only this function)
- Create: `backend/etqan/consultations/tests/test_seeds.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (under `# ── phase B7 ──` in `seed_academy`, below B7a's `seed_b7` call if present)

**Interfaces:**
- Produces: `seed_consultations(subdomain: str) -> None` — demo academy only; idempotent by product `name_en`; works whether or not `consultations` is on (it writes through the services, which check no switch).

- [ ] **Step 1: Write the failing test** (`tests/test_seeds.py`)

```python
import pytest

from etqan.billing import services as billing_services
from etqan.consultations import services
from etqan.consultations.models import Product
from etqan.consultations.models import Request
from etqan.identity import services as identity_services
from etqan.tenants.seeds.b7 import seed_consultations

pytestmark = pytest.mark.django_db


def test_seed_is_idempotent_and_demo_only(api_for):
    identity_services.create_person("student", full_name="Yusuf Omar",
                                    email="yusuf@demo.test")
    teacher = identity_services.create_person("teacher", full_name="Ustadh Bilal",
                                              email="bilal@demo.test")
    api_for("admin", email="admin@demo.test")
    seed_consultations("other")
    assert not Product.objects.exists()
    seed_consultations("demo")
    seed_consultations("demo")
    assert sorted(Product.objects.values_list("name_en", flat=True)) == [
        "Placement consultation", "Written question",
    ]
    profile = identity_services.get_teacher_profile(teacher.pk)
    assert services.offers(profile.pk)
    assert sorted(Request.objects.values_list("status", flat=True)) == [
        "completed", "confirmed", "pending_review",
    ]
    paid = Request.objects.get(status="confirmed")
    assert (paid.paid_method, paid.billing_method) == ("manual", "cash")
    assert billing_services.payments_queryset().filter(pk=paid.payment_id).exists()
    done = Request.objects.get(status="completed")
    assert (done.student_attendance, done.teacher_attendance) == ("present", "present")
```

- [ ] **Step 2: Run** — FAIL (`ImportError: seed_consultations`).

- [ ] **Step 3: Implement** — add to `backend/etqan/tenants/seeds/b7.py` (keep B7a's imports and `seed_b7`; add the imports below that are missing):

```python
from datetime import datetime
from datetime import time
from datetime import timedelta
from zoneinfo import ZoneInfo

from etqan.academy import services as academy_services
from etqan.consultations import services as consultations
from etqan.consultations.models import Product
from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError

PRODUCTS = (
    {
        "name_en": "Placement consultation",
        "name_ar": "استشارة تحديد المستوى",
        "description_en": "Thirty minutes with a teacher to find your level.",
        "description_ar": "ثلاثون دقيقة مع معلم لتحديد مستواك.",
        "price_minor": 1500,
        "duration_minutes": 30,
        "validity_days": 14,
        "participants": 1,
        "delivery_mode": "video_call",
        "reschedulable": True,
        "teacher_share_bp": 5000,
        "featured": True,
    },
    {
        "name_en": "Written question",
        "name_ar": "سؤال مكتوب",
        "description_en": "Send a question; a teacher answers by email.",
        "description_ar": "أرسل سؤالك ويجيبك معلم بالبريد.",
        "price_minor": 2000,
        "duration_minutes": 30,
        "validity_days": 7,
        "participants": 1,
        "delivery_mode": "email",
        "teacher_share_bp": 5000,
    },
)


def _found(email):
    try:
        return identity_services.get_user_by_email(email)
    except NotFoundError:
        return None


def _monday_at(weeks: int, day: int, hour: int, minute: int = 0):
    """A start on the academy's clock, `weeks` from this week's Monday."""
    zone = ZoneInfo(academy_services.get_settings().timezone)
    today = consultations.common.now().astimezone(zone).date()
    monday = today - timedelta(days=today.weekday()) + timedelta(weeks=weeks)
    return datetime.combine(monday + timedelta(days=day), time(hour, minute), tzinfo=zone)


def seed_consultations(subdomain: str) -> None:
    """Phase B7, slice B7c §6: Bilal opted in, two products and three
    requests (under review; confirmed and paid in cash; completed)."""
    if subdomain != "demo" or Product.objects.filter(
        name_en=PRODUCTS[0]["name_en"]
    ).exists():
        return
    teacher, student, admin = (
        _found("bilal@demo.test"), _found("yusuf@demo.test"), _found("admin@demo.test")
    )
    if teacher is None or admin is None:
        return
    consultations.set_consultant(teacher.pk, True, by=admin)
    placement, _ = (
        consultations.create_product(
            currency="USD", teacher_user_ids=[teacher.pk], **spec
        )
        for spec in PRODUCTS
    )
    if student is None:
        return

    def book(start):
        row, _ = consultations.create_request(
            product_id=placement.pk, teacher_user_id=teacher.pk,
            student_user_id=student.pk, starts_at=start, by=admin,
        )
        return row

    book(_monday_at(1, 0, 16))
    paid = consultations.confirm(book(_monday_at(1, 1, 16, 30)), by=admin)
    consultations.record_payment(paid, billing_method="cash", by=admin)
    done = consultations.confirm(book(_monday_at(-1, 0, 17)), by=admin)
    done = consultations.record_delivery(
        done, student_attendance="present", teacher_attendance="present",
        session_status="completed",
    )
    consultations.complete(done, by=admin)
```

`services/__init__.py` must export `common` (`from etqan.consultations.services import common` and `"common"` in `__all__`) so the seed reads the services' clock as `consultations.common.now()`.

`seed_dev.py`, under `# ── phase B7 ──` in `seed_academy`:

```python
        from etqan.tenants.seeds.b7 import seed_consultations  # noqa: PLC0415

        seed_consultations(subdomain)
```

The B2 seed (`seed_availability`, which runs earlier) already gives Bilal Monday–Thursday 16:00–21:00 windows, so the seeded starts sit inside his availability. `seed_dev.FEATURES` is `{"demo": features.BUILT}`, so the demo academy has `consultations` on with no edit.

- [ ] **Step 4: Run** — `B pytest etqan/consultations/tests/test_seeds.py etqan/tenants -q` → PASS; then `just seed` on the stream stack with no error.
- [ ] **Step 5: Commit** — `git -C backend add etqan/tenants/seeds/b7.py etqan/tenants/management/commands/seed_dev.py etqan/consultations && git -C backend commit -m "feat(consultations): B7c demo seed" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

Backend checkpoint: `B pytest -q --cov=etqan.consultations --cov-report=term-missing etqan/consultations` ≥ 90 % for the app; `B ruff check . && B ruff format --check . && B lint-imports` clean.

---

### Task 12: Dashboard data layer, strings and the switch

**Files:**
- Create: `dashboard/src/features/consultations/schemas.ts`, `api.ts`, `api.test.ts`, `queries.ts`, `errors.ts`, `errors.test.ts`, `fixtures.ts`, `index.ts`
- Create: `dashboard/src/locales/en/consultations.json`, `dashboard/src/locales/ar/consultations.json`
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode`)

**Interfaces:**
- Produces: types `Product`, `ConsultantRow`, `Slot`, `SlotList`, `ConsultationRequest`, `RequestPayment`, `Warnings`, `WriteAnswer`, `AgendaWeek`, `RequestFilters`, `DeliveryMode`, `RequestStatus`; constants `DELIVERY_MODES`, `REQUEST_STATUSES`, `SESSION_STATUSES`, `ATTENDANCE`, `BILLING_METHODS`; `consultationsApi` (below); hooks `useProducts`, `useProduct`, `useSaveProduct`, `useDeleteProduct`, `useConsultants`, `useConsultant`, `useSetConsultant`, `useSlots`, `useRequests`, `useRequest`, `useCreateRequest`, `useUpdateRequest`, `useDeleteRequest`, `useRequestAction`, `useDelivery`, `useComplete`, `useRecordPayment`, `useSchedule`; `consultationsErrorText(error, t)`, `formErrors(error, t, inputs)`; fixtures `product`, `request`, `writeAnswer`, `week`.

- [ ] **Step 1: Write the failing tests**

`api.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { consultationsApi } from "./api";

vi.mock("@/lib/api", () => ({
	api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

describe("consultationsApi", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		for (const fn of [api.get, api.post, api.patch, api.put])
			vi.mocked(fn).mockResolvedValue({ data: { ok: true } });
	});

	it("lists products with only the filters given", async () => {
		await consultationsApi.products({ mode: "email", featured: undefined });
		expect(api.get).toHaveBeenCalledWith("consultations/products/", {
			params: { mode: "email" },
		});
	});

	it("reads slots and opted-in teachers", async () => {
		await consultationsApi.slots(3, { teacher: 8, from: "2026-10-12", days: 7 });
		expect(api.get).toHaveBeenCalledWith("consultations/products/3/slots/", {
			params: { teacher: 8, from: "2026-10-12", days: 7 },
		});
		await consultationsApi.consultants(true);
		expect(api.get).toHaveBeenCalledWith("consultations/consultants/", {
			params: { offers: "true" },
		});
		await consultationsApi.setConsultant(8, true);
		expect(api.put).toHaveBeenCalledWith("consultations/consultants/8/", {
			offers: true,
		});
	});

	it("addresses requests and their actions", async () => {
		await consultationsApi.requests({ page: 2, status: "confirmed", teacher: undefined });
		expect(api.get).toHaveBeenCalledWith("consultations/requests/", {
			params: { page: 2, status: "confirmed" },
		});
		await consultationsApi.action(5, "request-reschedule", { note: "x" });
		expect(api.post).toHaveBeenCalledWith(
			"consultations/requests/5/request-reschedule/",
			{ note: "x" },
		);
		await consultationsApi.payment(5, { billing_method: "cash" });
		expect(api.post).toHaveBeenCalledWith("consultations/requests/5/payment/", {
			billing_method: "cash",
		});
		await consultationsApi.schedule({ week: "2026-10-12" });
		expect(api.get).toHaveBeenCalledWith("consultations/schedule/", {
			params: { week: "2026-10-12" },
		});
	});
});
```

`errors.test.ts`:

```ts
import { AxiosError, type AxiosResponse } from "axios";
import i18n from "i18next";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import { consultationsErrorText } from "./errors";

function conflict(code: string) {
	return new AxiosError("x", "409", undefined, undefined, {
		status: 409,
		data: { detail: "server words", code },
	} as AxiosResponse);
}

describe("consultationsErrorText", () => {
	it("translates consultations.* codes", () => {
		expect(consultationsErrorText(conflict("consultations.slot_full"), i18n.t)).toBe(
			"This slot is full. Pick another time.",
		);
	});
	it("falls back to the server's words", () => {
		expect(consultationsErrorText(conflict("other.code"), i18n.t)).toBe("server words");
	});
});
```

- [ ] **Step 2: Run** — `F pnpm vitest run src/features/consultations` → FAIL (modules missing).

- [ ] **Step 3: Implement**

`schemas.ts`:

```ts
export const DELIVERY_MODES = ["video_call", "live_chat", "email"] as const;
export type DeliveryMode = (typeof DELIVERY_MODES)[number];
export const REQUEST_STATUSES = [
	"pending_review",
	"confirmed",
	"reschedule_requested",
	"completed",
	"cancelled",
] as const;
export type RequestStatus = (typeof REQUEST_STATUSES)[number];
export const SESSION_STATUSES = ["scheduled", "completed", "absent"] as const;
export type SessionStatus = (typeof SESSION_STATUSES)[number];
export const ATTENDANCE = ["not_set", "present", "absent"] as const;
export type Attendance = (typeof ATTENDANCE)[number];
/** billing.Payment's manual methods (C-9). */
export const BILLING_METHODS = [
	"cash",
	"bank_transfer",
	"instapay",
	"vodafone_cash",
	"western_union",
	"zelle",
	"venmo",
	"cashapp",
	"other",
] as const;
export type BillingMethod = (typeof BILLING_METHODS)[number];

export interface PersonRef {
	id: number;
	full_name: string;
}

export interface Product {
	id: number;
	name_ar: string;
	name_en: string;
	description_ar: string;
	description_en: string;
	price_minor: number;
	currency: string;
	duration_minutes: number;
	validity_days: number;
	participants: number;
	delivery_mode: DeliveryMode;
	status: "available" | "archived";
	enabled: boolean;
	featured: boolean;
	reschedulable: boolean;
	fee_enabled: boolean;
	teacher_share_bp: number;
	bookable: boolean;
	cover_url: string;
	teachers: PersonRef[];
}

export interface ConsultantRow extends PersonRef {
	offers: boolean;
}

export interface Slot {
	starts_at: string;
	remaining: number;
}

export interface SlotList {
	slots: Slot[];
	availability_off: boolean;
}

export interface RequestPayment {
	paid_method: "" | "manual" | "stripe" | "paypal";
	billing_method: string;
	amount_minor: number;
	fee_minor: number;
	currency: string;
	transaction_number: string;
	paid_on: string | null;
	payment_id: number | null;
	billing_status: "completed" | "refunded" | null;
}

export interface ConsultationRequest {
	id: number;
	reference: string;
	product: {
		id: number;
		name_ar: string;
		name_en: string;
		delivery_mode: DeliveryMode;
		duration_minutes: number;
		price_minor: number;
		currency: string;
		reschedulable: boolean;
	};
	teacher: PersonRef;
	student: PersonRef | null;
	name: string;
	email: string;
	whatsapp: string;
	timezone: string;
	starts_at: string | null;
	ends_at: string | null;
	meeting_url: string;
	session_status: SessionStatus;
	student_attendance: Attendance;
	teacher_attendance: Attendance;
	status: RequestStatus;
	reschedule_note: string;
	outside_validity: boolean;
	created_at: string;
	confirmed_at: string | null;
	reschedule_requested_at: string | null;
	rescheduled_at: string | null;
	cancelled_at: string | null;
	completed_at: string | null;
	/** Office only (C-12). */
	notes?: string;
	payment?: RequestPayment;
}

export interface Warnings {
	conflicts: { kind: "session" | "consultation"; id: number | null; starts_at: string }[];
	outside_availability: boolean;
	outside_validity: boolean;
}

export interface WriteAnswer {
	request: ConsultationRequest;
	warnings: Warnings | null;
}

export interface AgendaWeek {
	week: string;
	days: { day: string; requests: ConsultationRequest[] }[];
}

export interface ProductFilters {
	mode?: string;
	featured?: boolean;
	status?: string;
}

export interface RequestFilters {
	page?: number;
	product?: number;
	teacher?: number;
	status?: string;
	session_status?: string;
	student_attendance?: string;
	teacher_attendance?: string;
	paid_method?: string;
	billing_method?: string;
	from?: string;
	to?: string;
}

export type RequestAction =
	| "confirm"
	| "cancel"
	| "request-reschedule"
	| "reschedule"
	| "decline-reschedule";
```

`api.ts`:

```ts
import { api, type Paginated } from "@/lib/api";
import type {
	AgendaWeek,
	ConsultantRow,
	ConsultationRequest,
	Product,
	ProductFilters,
	RequestAction,
	RequestFilters,
	SlotList,
	WriteAnswer,
} from "./schemas";

const B = "consultations/";

/** Only the params that are set: an empty filter is not sent. */
function given<T extends object>(params: T): Record<string, string | number> {
	const out: Record<string, string | number> = {};
	for (const [key, value] of Object.entries(params)) {
		if (value === undefined || value === null || value === "") continue;
		out[key] = typeof value === "boolean" ? String(value) : (value as string | number);
	}
	return out;
}

export interface RequestBody {
	product?: number;
	teacher?: number;
	student?: number | null;
	name?: string;
	email?: string;
	whatsapp?: string;
	timezone?: string;
	starts_at?: string | null;
	meeting_url?: string;
	notes?: string;
}

export interface DeliveryBody {
	student_attendance?: string;
	teacher_attendance?: string;
	session_status?: string;
	meeting_url?: string;
}

export interface PaymentBody {
	billing_method: string;
	amount_minor?: number;
	paid_on?: string | null;
	reference?: string;
	transaction_number?: string;
}

export const consultationsApi = {
	products: async (f: ProductFilters = {}) =>
		(await api.get<Product[]>(`${B}products/`, { params: given(f) })).data,
	product: async (id: number) =>
		(await api.get<Product>(`${B}products/${id}/`)).data,
	createProduct: async (form: FormData) =>
		(await api.post<Product>(`${B}products/`, form)).data,
	updateProduct: async (id: number, form: FormData) =>
		(await api.patch<Product>(`${B}products/${id}/`, form)).data,
	removeProduct: async (id: number) => {
		await api.delete(`${B}products/${id}/`);
	},
	consultants: async (offersOnly: boolean) =>
		(
			await api.get<ConsultantRow[]>(`${B}consultants/`, {
				params: offersOnly ? { offers: "true" } : {},
			})
		).data,
	consultant: async (userId: number) =>
		(await api.get<{ teacher_id: number; offers: boolean }>(`${B}consultants/${userId}/`))
			.data,
	setConsultant: async (userId: number, offers: boolean) =>
		(
			await api.put<{ teacher_id: number; offers: boolean }>(
				`${B}consultants/${userId}/`,
				{ offers },
			)
		).data,
	slots: async (
		productId: number,
		q: { teacher: number; from?: string; days?: number; request?: number },
	) =>
		(await api.get<SlotList>(`${B}products/${productId}/slots/`, { params: given(q) }))
			.data,
	requests: async (f: RequestFilters) =>
		(
			await api.get<Paginated<ConsultationRequest>>(`${B}requests/`, {
				params: given(f),
			})
		).data,
	request: async (id: number) =>
		(await api.get<ConsultationRequest>(`${B}requests/${id}/`)).data,
	createRequest: async (body: RequestBody) =>
		(await api.post<WriteAnswer>(`${B}requests/`, body)).data,
	updateRequest: async (id: number, body: RequestBody) =>
		(await api.patch<WriteAnswer>(`${B}requests/${id}/`, body)).data,
	removeRequest: async (id: number) => {
		await api.delete(`${B}requests/${id}/`);
	},
	action: async (
		id: number,
		action: RequestAction,
		body: { note?: string; starts_at?: string; teacher?: number } = {},
	) => (await api.post<WriteAnswer>(`${B}requests/${id}/${action}/`, body)).data,
	delivery: async (id: number, body: DeliveryBody) =>
		(await api.post<WriteAnswer>(`${B}requests/${id}/delivery/`, body)).data,
	complete: async (id: number) =>
		(await api.post<WriteAnswer>(`${B}requests/${id}/complete/`)).data,
	payment: async (id: number, body: PaymentBody) =>
		(await api.post<WriteAnswer>(`${B}requests/${id}/payment/`, body)).data,
	schedule: async (q: { week?: string; teacher?: number; product?: number }) =>
		(await api.get<AgendaWeek>(`${B}schedule/`, { params: given(q) })).data,
};
```

(The `complete` call passes no body; the test above does not check it.)

`queries.ts`:

```ts
import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
	consultationsApi,
	type DeliveryBody,
	type PaymentBody,
	type RequestBody,
} from "./api";
import type { ProductFilters, RequestAction, RequestFilters } from "./schemas";

export const consultationsKey = ["consultations"] as const;

function useInvalidating<A, R>(fn: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSuccess: () => qc.invalidateQueries({ queryKey: consultationsKey }),
	});
}

export const useProducts = (f: ProductFilters = {}, enabled = true) =>
	useQuery({
		queryKey: [...consultationsKey, "products", f],
		queryFn: () => consultationsApi.products(f),
		placeholderData: keepPreviousData,
		enabled,
	});
export const useProduct = (id: number | undefined) =>
	useQuery({
		queryKey: [...consultationsKey, "product", id],
		queryFn: () => consultationsApi.product(id as number),
		enabled: id !== undefined,
	});
export const useSaveProduct = (id?: number) =>
	useInvalidating((form: FormData) =>
		id === undefined
			? consultationsApi.createProduct(form)
			: consultationsApi.updateProduct(id, form),
	);
export const useDeleteProduct = () =>
	useInvalidating((id: number) => consultationsApi.removeProduct(id));
export const useConsultants = (offersOnly: boolean, enabled = true) =>
	useQuery({
		queryKey: [...consultationsKey, "consultants", offersOnly],
		queryFn: () => consultationsApi.consultants(offersOnly),
		enabled,
	});
export const useConsultant = (userId: number, enabled = true) =>
	useQuery({
		queryKey: [...consultationsKey, "consultant", userId],
		queryFn: () => consultationsApi.consultant(userId),
		enabled,
		retry: false,
	});
export const useSetConsultant = (userId: number) =>
	useInvalidating((offers: boolean) => consultationsApi.setConsultant(userId, offers));
export const useSlots = (
	productId: number | undefined,
	q: { teacher?: number; from?: string; days?: number; request?: number },
) =>
	useQuery({
		queryKey: [...consultationsKey, "slots", productId, q],
		queryFn: () =>
			consultationsApi.slots(productId as number, { ...q, teacher: q.teacher as number }),
		enabled: productId !== undefined && q.teacher !== undefined,
	});
export const useRequests = (f: RequestFilters) =>
	useQuery({
		queryKey: [...consultationsKey, "requests", f],
		queryFn: () => consultationsApi.requests(f),
		placeholderData: keepPreviousData,
	});
export const useRequest = (id: number | undefined) =>
	useQuery({
		queryKey: [...consultationsKey, "request", id],
		queryFn: () => consultationsApi.request(id as number),
		enabled: id !== undefined,
	});
export const useCreateRequest = () =>
	useInvalidating((body: RequestBody) => consultationsApi.createRequest(body));
export const useUpdateRequest = () =>
	useInvalidating(({ id, body }: { id: number; body: RequestBody }) =>
		consultationsApi.updateRequest(id, body),
	);
export const useDeleteRequest = () =>
	useInvalidating((id: number) => consultationsApi.removeRequest(id));
export const useRequestAction = () =>
	useInvalidating(
		({
			id,
			action,
			body,
		}: {
			id: number;
			action: RequestAction;
			body?: { note?: string; starts_at?: string; teacher?: number };
		}) => consultationsApi.action(id, action, body),
	);
export const useDelivery = () =>
	useInvalidating(({ id, body }: { id: number; body: DeliveryBody }) =>
		consultationsApi.delivery(id, body),
	);
export const useComplete = () =>
	useInvalidating((id: number) => consultationsApi.complete(id));
export const useRecordPayment = () =>
	useInvalidating(({ id, body }: { id: number; body: PaymentBody }) =>
		consultationsApi.payment(id, body),
	);
export const useSchedule = (q: { week?: string; teacher?: number; product?: number }) =>
	useQuery({
		queryKey: [...consultationsKey, "schedule", q],
		queryFn: () => consultationsApi.schedule(q),
		placeholderData: keepPreviousData,
	});
```

`errors.ts`:

```ts
import type { TFunction } from "i18next";
import { formErrors as baseFormErrors } from "@/features/curriculum/errors";
import { parseApiError } from "@/features/identity/api";
import { errorText } from "@/lib/form-errors";

/** `consultations.*` codes from this area; anything else as everywhere else. */
export function consultationsErrorText(error: unknown, t: TFunction): string {
	const code = parseApiError(error).code;
	if (code?.startsWith("consultations.")) {
		const text = t(`consultations.errors.${code.slice("consultations.".length)}`, {
			defaultValue: "",
		});
		if (text) return text;
	}
	return errorText(error, t);
}

export function formErrors(error: unknown, t: TFunction, inputs: readonly string[]) {
	return baseFormErrors(error, t, inputs, consultationsErrorText);
}
```

`fixtures.ts`:

```ts
import type { AgendaWeek, ConsultationRequest, Product, WriteAnswer } from "./schemas";

export const product: Product = {
	id: 3,
	name_ar: "استشارة تحديد المستوى",
	name_en: "Placement consultation",
	description_ar: "",
	description_en: "Thirty minutes with a teacher.",
	price_minor: 1500,
	currency: "USD",
	duration_minutes: 30,
	validity_days: 14,
	participants: 1,
	delivery_mode: "video_call",
	status: "available",
	enabled: true,
	featured: true,
	reschedulable: true,
	fee_enabled: false,
	teacher_share_bp: 5000,
	bookable: true,
	cover_url: "",
	teachers: [{ id: 8, full_name: "Ustadh Bilal" }],
};

export const request: ConsultationRequest = {
	id: 5,
	reference: "CR-000005",
	product: {
		id: 3,
		name_ar: "استشارة تحديد المستوى",
		name_en: "Placement consultation",
		delivery_mode: "video_call",
		duration_minutes: 30,
		price_minor: 1500,
		currency: "USD",
		reschedulable: true,
	},
	teacher: { id: 8, full_name: "Ustadh Bilal" },
	student: { id: 21, full_name: "Yusuf Omar" },
	name: "Yusuf Omar",
	email: "yusuf@demo.test",
	whatsapp: "+201000000001",
	timezone: "Africa/Cairo",
	starts_at: "2026-10-12T16:00:00+00:00",
	ends_at: "2026-10-12T16:30:00+00:00",
	meeting_url: "https://meet.test/bilal",
	session_status: "scheduled",
	student_attendance: "not_set",
	teacher_attendance: "not_set",
	status: "pending_review",
	reschedule_note: "",
	outside_validity: false,
	created_at: "2026-10-08T09:00:00+00:00",
	confirmed_at: null,
	reschedule_requested_at: null,
	rescheduled_at: null,
	cancelled_at: null,
	completed_at: null,
	notes: "",
	payment: {
		paid_method: "",
		billing_method: "",
		amount_minor: 0,
		fee_minor: 0,
		currency: "",
		transaction_number: "",
		paid_on: null,
		payment_id: null,
		billing_status: null,
	},
};

export const writeAnswer: WriteAnswer = {
	request,
	warnings: { conflicts: [], outside_availability: false, outside_validity: false },
};

export const week: AgendaWeek = {
	week: "2026-10-12",
	days: [
		{ day: "2026-10-12", requests: [request] },
		...["13", "14", "15", "16", "17", "18"].map((d) => ({
			day: `2026-10-${d}`,
			requests: [],
		})),
	],
};
```

`index.ts` re-exports `consultationsApi`, every hook, the types and constants, `consultationsErrorText`, and (added by later tasks) `ProductsAdmin`, `ConsultantCard`, `RequestsAdmin`, `ScheduleWeek`, `MyConsultations`.

`identity/schemas.ts` — at the end of the `FeatureCode` union (after B7a's `"recorded_courses"` if present):

```ts
	// Phase B7, slice B7c.
	| "consultations"
```

`locales/en/consultations.json` (complete; later tasks use only these keys):

```json
{
	"nav": {
		"products": "Consultations",
		"requests": "Consultation requests",
		"mine": "My consultations"
	},
	"modes": { "video_call": "Video call", "live_chat": "Live chat", "email": "Email" },
	"statuses": {
		"pending_review": "Under review",
		"confirmed": "Confirmed",
		"reschedule_requested": "Reschedule requested",
		"completed": "Completed",
		"cancelled": "Cancelled"
	},
	"session": { "scheduled": "Scheduled", "completed": "Completed", "absent": "Absent" },
	"attendance": { "not_set": "Not recorded", "present": "Present", "absent": "Absent" },
	"paid": { "manual": "Paid by hand", "stripe": "Stripe", "paypal": "PayPal", "unpaid": "Unpaid" },
	"billingMethods": {
		"cash": "Cash",
		"bank_transfer": "Bank transfer",
		"instapay": "InstaPay",
		"vodafone_cash": "Vodafone Cash",
		"western_union": "Western Union",
		"zelle": "Zelle",
		"venmo": "Venmo",
		"cashapp": "Cash App",
		"other": "Other"
	},
	"any": "Any",
	"yes": "Yes",
	"no": "No",
	"save": "Save",
	"cancel": "Cancel",
	"delete": "Delete",
	"minutes": "{{count}} min",
	"products": {
		"title": "Consultations",
		"subtitle": "Paid one-off sessions with a teacher.",
		"add": "Add consultation",
		"newTitle": "New consultation",
		"editTitle": "Consultation",
		"empty": "No consultations yet.",
		"noTeachers": "No teacher offers consultations yet. Turn it on from a teacher's page.",
		"deleteConfirm": "Delete this consultation? This cannot be undone.",
		"saved": "Consultation saved.",
		"deleted": "Consultation deleted.",
		"columns": {
			"name": "Name",
			"price": "Price",
			"duration": "Length",
			"mode": "Delivery",
			"teachers": "Teachers",
			"status": "Status",
			"enabled": "Enabled"
		},
		"filters": { "mode": "Delivery", "featured": "Featured", "status": "Status" },
		"productStatuses": { "available": "Available", "archived": "Archived" },
		"tabs": { "details": "Details", "booking": "Booking", "teachers": "Teachers" },
		"fields": {
			"cover": "Cover image",
			"removeCover": "Remove the cover",
			"nameAr": "Name (Arabic)",
			"nameEn": "Name (English)",
			"descriptionAr": "Description (Arabic)",
			"descriptionEn": "Description (English)",
			"price": "Price",
			"currency": "Currency",
			"status": "Status",
			"enabled": "Enabled",
			"featured": "Featured",
			"duration": "Length (minutes)",
			"validity": "Booking validity (days)",
			"validityHint": "Must be used within this many days of payment.",
			"participants": "Participants",
			"mode": "Delivery",
			"reschedulable": "Can be rescheduled",
			"fee": "Add the service fee to online payments",
			"teachers": "Responsible teachers",
			"share": "Teacher's share (%)"
		}
	},
	"consultant": {
		"title": "Consultations",
		"offers": "Offers consultations",
		"hint": "Only teachers who offer consultations can be named on a consultation."
	},
	"requests": {
		"title": "Consultation requests",
		"subtitle": "Book, confirm and follow consultations.",
		"add": "New request",
		"empty": "No consultation requests.",
		"tabs": { "list": "Requests", "calendar": "Calendar" },
		"columns": {
			"reference": "Request",
			"person": "Person",
			"product": "Consultation",
			"teacher": "Teacher",
			"start": "Time",
			"status": "Status",
			"session": "Session",
			"paid": "Payment"
		},
		"filters": {
			"product": "Consultation",
			"teacher": "Teacher",
			"status": "Status",
			"sessionStatus": "Session",
			"studentAttendance": "Student attendance",
			"teacherAttendance": "Teacher attendance",
			"paid": "Payment",
			"billingMethod": "Gateway",
			"from": "From",
			"to": "To"
		},
		"actions": {
			"edit": "Edit",
			"confirm": "Confirm",
			"cancel": "Cancel request",
			"requestReschedule": "Reschedule requested",
			"reschedule": "Reschedule",
			"declineReschedule": "Keep the time",
			"delivery": "Record attendance",
			"complete": "Complete",
			"delete": "Delete",
			"recordPayment": "Record payment"
		},
		"noTime": "No time",
		"note": "Note",
		"cancelConfirm": "Cancel this request?",
		"deleteConfirm": "Delete this request? This cannot be undone.",
		"outsideValidity": "Outside the booking validity",
		"done": "Saved."
	},
	"dialog": {
		"newTitle": "New consultation request",
		"editTitle": "Request {{reference}}",
		"rescheduleTitle": "Reschedule {{reference}}",
		"deliveryTitle": "Attendance for {{reference}}",
		"sections": {
			"person": "Person",
			"consultation": "Consultation",
			"session": "Session",
			"payment": "Payment"
		},
		"fields": {
			"student": "Student",
			"studentNone": "Not a registered student",
			"name": "Name",
			"email": "Email",
			"whatsapp": "WhatsApp",
			"timezone": "Their timezone",
			"product": "Consultation",
			"teacher": "Teacher",
			"date": "Date",
			"time": "Time (academy clock)",
			"link": "Meeting link",
			"notes": "Notes",
			"studentAttendance": "Student attendance",
			"teacherAttendance": "Teacher attendance",
			"sessionStatus": "Session status"
		},
		"pickTeacherFirst": "Select a teacher first to see available slots",
		"slots": {
			"title": "Free slots",
			"empty": "No free slot in these days.",
			"off": "Teacher availability is off: type a time instead.",
			"remaining": "{{count}} left",
			"typeInstead": "Type a time instead",
			"pickInstead": "Pick a free slot",
			"previous": "Earlier days",
			"next": "Later days"
		},
		"warnings": {
			"title": "Saved, with warnings",
			"session": "Overlaps a lesson at {{time}}",
			"consultation": "Overlaps another consultation at {{time}}",
			"outsideAvailability": "Outside the teacher's availability",
			"outsideValidity": "Outside the booking validity"
		},
		"paymentNone": "Unpaid",
		"paymentDone": "Paid {{amount}} on {{date}} ({{method}})",
		"refunded": "Refunded in billing",
		"saved": "Request saved."
	},
	"payment": {
		"title": "Record payment",
		"method": "Payment method",
		"amount": "Amount",
		"paidOn": "Paid on",
		"reference": "Reference",
		"transaction": "Transaction number",
		"hint": "For Telda, PayMob and similar, choose Other and write the name in the reference.",
		"saved": "Payment recorded."
	},
	"calendar": {
		"previous": "Previous week",
		"next": "Next week",
		"weekOf": "Week of {{date}}",
		"empty": "Nothing booked this week."
	},
	"mine": {
		"title": "My consultations",
		"subtitle": "Consultations booked with you.",
		"empty": "No consultations booked with you.",
		"theirTime": "Their time: {{time}}",
		"saveLink": "Save link",
		"complete": "Complete",
		"record": "Save attendance"
	},
	"errors": {
		"slot_full": "This slot is full. Pick another time.",
		"product_in_use": "This consultation has requests: archive it instead.",
		"request_closed": "This request is closed.",
		"wrong_status": "This request cannot do that now.",
		"not_reschedulable": "This consultation cannot be rescheduled.",
		"not_started": "This consultation has not started yet.",
		"not_delivered": "Record how the session went first.",
		"already_paid": "This request is paid already.",
		"request_in_use": "This request is confirmed or paid: cancel it instead.",
		"use_reschedule": "Use Reschedule to move a confirmed request."
	}
}
```

`locales/ar/consultations.json` (the same keys):

```json
{
	"nav": {
		"products": "الاستشارات",
		"requests": "طلبات الاستشارات",
		"mine": "استشاراتي"
	},
	"modes": { "video_call": "مكالمة فيديو", "live_chat": "دردشة مباشرة", "email": "بريد إلكتروني" },
	"statuses": {
		"pending_review": "قيد المراجعة",
		"confirmed": "تم التأكيد وتأكيد الموعد",
		"reschedule_requested": "تم طلب إعادة الجدولة",
		"completed": "مكتمل",
		"cancelled": "ملغي"
	},
	"session": { "scheduled": "مجدولة", "completed": "مكتملة", "absent": "غياب" },
	"attendance": { "not_set": "لم يبدأ", "present": "حاضر", "absent": "غائب" },
	"paid": { "manual": "مدفوع يدويًا", "stripe": "Stripe", "paypal": "PayPal", "unpaid": "غير مدفوع" },
	"billingMethods": {
		"cash": "نقدًا",
		"bank_transfer": "تحويل بنكي",
		"instapay": "إنستاباي",
		"vodafone_cash": "فودافون كاش",
		"western_union": "ويسترن يونيون",
		"zelle": "Zelle",
		"venmo": "Venmo",
		"cashapp": "Cash App",
		"other": "أخرى"
	},
	"any": "الكل",
	"yes": "نعم",
	"no": "لا",
	"save": "حفظ",
	"cancel": "إلغاء",
	"delete": "حذف",
	"minutes": "{{count}} دقيقة",
	"products": {
		"title": "الاستشارات",
		"subtitle": "جلسات مدفوعة لمرة واحدة مع معلم.",
		"add": "إضافة استشارة",
		"newTitle": "استشارة جديدة",
		"editTitle": "استشارة",
		"empty": "لا توجد استشارات بعد.",
		"noTeachers": "لا يوجد معلم يقدم استشارات بعد. فعّل ذلك من صفحة المعلم.",
		"deleteConfirm": "حذف هذه الاستشارة؟ لا يمكن التراجع.",
		"saved": "تم حفظ الاستشارة.",
		"deleted": "تم حذف الاستشارة.",
		"columns": {
			"name": "الاسم",
			"price": "السعر",
			"duration": "المدة",
			"mode": "طريقة التقديم",
			"teachers": "المعلمون",
			"status": "الحالة",
			"enabled": "مفعّلة"
		},
		"filters": { "mode": "طريقة التقديم", "featured": "مميزة", "status": "الحالة" },
		"productStatuses": { "available": "متاحة", "archived": "مؤرشفة" },
		"tabs": { "details": "التفاصيل", "booking": "الحجز", "teachers": "المعلمون" },
		"fields": {
			"cover": "صورة الغلاف",
			"removeCover": "إزالة الغلاف",
			"nameAr": "الاسم (عربي)",
			"nameEn": "الاسم (إنجليزي)",
			"descriptionAr": "الوصف (عربي)",
			"descriptionEn": "الوصف (إنجليزي)",
			"price": "السعر",
			"currency": "العملة",
			"status": "الحالة",
			"enabled": "مفعّلة",
			"featured": "مميزة",
			"duration": "المدة (بالدقائق)",
			"validity": "مدة صلاحية الحجز (بالأيام)",
			"validityHint": "يجب استخدامها خلال هذا العدد من الأيام بعد الدفع.",
			"participants": "عدد المشاركين",
			"mode": "طريقة التقديم",
			"reschedulable": "إمكانية إعادة الجدولة",
			"fee": "إضافة رسوم الخدمة إلى الدفع الإلكتروني",
			"teachers": "المعلمون المسؤولون",
			"share": "نصيب المعلم (٪)"
		}
	},
	"consultant": {
		"title": "الاستشارات",
		"offers": "يقدم استشارات",
		"hint": "لا يُضاف إلى الاستشارات إلا المعلمون الذين يقدمونها."
	},
	"requests": {
		"title": "طلبات الاستشارات",
		"subtitle": "احجز الاستشارات وأكدها وتابعها.",
		"add": "طلب جديد",
		"empty": "لا توجد طلبات استشارات.",
		"tabs": { "list": "الطلبات", "calendar": "التقويم" },
		"columns": {
			"reference": "الطلب",
			"person": "الشخص",
			"product": "الاستشارة",
			"teacher": "المعلم",
			"start": "الموعد",
			"status": "الحالة",
			"session": "الجلسة",
			"paid": "الدفع"
		},
		"filters": {
			"product": "الاستشارة",
			"teacher": "المعلم",
			"status": "الحالة",
			"sessionStatus": "الجلسة",
			"studentAttendance": "حضور الطالب",
			"teacherAttendance": "حضور المعلم",
			"paid": "الدفع",
			"billingMethod": "بوابة الدفع",
			"from": "من",
			"to": "إلى"
		},
		"actions": {
			"edit": "تعديل",
			"confirm": "تأكيد",
			"cancel": "إلغاء الطلب",
			"requestReschedule": "طُلبت إعادة الجدولة",
			"reschedule": "إعادة الجدولة",
			"declineReschedule": "الإبقاء على الموعد",
			"delivery": "تسجيل الحضور",
			"complete": "إكمال",
			"delete": "حذف",
			"recordPayment": "تسجيل دفعة"
		},
		"noTime": "بلا موعد",
		"note": "ملاحظة",
		"cancelConfirm": "إلغاء هذا الطلب؟",
		"deleteConfirm": "حذف هذا الطلب؟ لا يمكن التراجع.",
		"outsideValidity": "خارج مدة صلاحية الحجز",
		"done": "تم الحفظ."
	},
	"dialog": {
		"newTitle": "طلب استشارة جديد",
		"editTitle": "الطلب {{reference}}",
		"rescheduleTitle": "إعادة جدولة {{reference}}",
		"deliveryTitle": "حضور {{reference}}",
		"sections": {
			"person": "الشخص",
			"consultation": "الاستشارة",
			"session": "الجلسة",
			"payment": "الدفع"
		},
		"fields": {
			"student": "الطالب",
			"studentNone": "ليس طالبًا مسجلًا",
			"name": "الاسم",
			"email": "البريد الإلكتروني",
			"whatsapp": "واتساب",
			"timezone": "منطقته الزمنية",
			"product": "الاستشارة",
			"teacher": "المعلم",
			"date": "التاريخ",
			"time": "الوقت (توقيت النظام)",
			"link": "رابط الجلسة",
			"notes": "ملاحظات",
			"studentAttendance": "حضور الطالب",
			"teacherAttendance": "حضور المعلم",
			"sessionStatus": "حالة الجلسة"
		},
		"pickTeacherFirst": "يرجى اختيار المعلم أولاً لعرض المواعيد المتاحة",
		"slots": {
			"title": "المواعيد المتاحة",
			"empty": "لا توجد مواعيد متاحة في هذه الأيام.",
			"off": "إتاحة المعلمين متوقفة: اكتب الوقت بنفسك.",
			"remaining": "متبقٍ {{count}}",
			"typeInstead": "اكتب الوقت بنفسك",
			"pickInstead": "اختر موعدًا متاحًا",
			"previous": "أيام سابقة",
			"next": "أيام لاحقة"
		},
		"warnings": {
			"title": "تم الحفظ مع تنبيهات",
			"session": "يتعارض مع حصة في {{time}}",
			"consultation": "يتعارض مع استشارة أخرى في {{time}}",
			"outsideAvailability": "خارج أوقات إتاحة المعلم",
			"outsideValidity": "خارج مدة صلاحية الحجز"
		},
		"paymentNone": "غير مدفوع",
		"paymentDone": "دُفع {{amount}} في {{date}} ({{method}})",
		"refunded": "مُسترد في الفوترة",
		"saved": "تم حفظ الطلب."
	},
	"payment": {
		"title": "تسجيل دفعة",
		"method": "وسيلة الدفع",
		"amount": "المبلغ",
		"paidOn": "تاريخ الدفع",
		"reference": "المرجع",
		"transaction": "رقم العملية",
		"hint": "لتيلدا وباي موب وما شابه، اختر «أخرى» واكتب الاسم في المرجع.",
		"saved": "تم تسجيل الدفعة."
	},
	"calendar": {
		"previous": "الأسبوع السابق",
		"next": "الأسبوع التالي",
		"weekOf": "أسبوع {{date}}",
		"empty": "لا حجوزات هذا الأسبوع."
	},
	"mine": {
		"title": "استشاراتي",
		"subtitle": "الاستشارات المحجوزة معك.",
		"empty": "لا توجد استشارات محجوزة معك.",
		"theirTime": "توقيته: {{time}}",
		"saveLink": "حفظ الرابط",
		"complete": "إكمال",
		"record": "حفظ الحضور"
	},
	"errors": {
		"slot_full": "هذا الموعد ممتلئ. اختر وقتًا آخر.",
		"product_in_use": "لهذه الاستشارة طلبات: أرشفها بدلًا من حذفها.",
		"request_closed": "هذا الطلب مغلق.",
		"wrong_status": "لا يمكن إجراء ذلك على هذا الطلب الآن.",
		"not_reschedulable": "لا يمكن إعادة جدولة هذه الاستشارة.",
		"not_started": "لم تبدأ هذه الاستشارة بعد.",
		"not_delivered": "سجّل ما جرى في الجلسة أولًا.",
		"already_paid": "هذا الطلب مدفوع بالفعل.",
		"request_in_use": "هذا الطلب مؤكد أو مدفوع: ألغِه بدلًا من حذفه.",
		"use_reschedule": "استخدم «إعادة الجدولة» لتغيير موعد طلب مؤكد."
	}
}
```

Plural keys: `minutes` and `slots.remaining` use `{{count}}` without `_one`/`_other` forms, so the ar/en key-equality test passes as is. Check the existing area files: if they use i18next plural suffixes (`_one`, `_other`), add those forms to both files instead.

- [ ] **Step 4: Run** — `F pnpm vitest run src/features/consultations src/locales` → PASS (the locales test keeps en and ar equal); `F pnpm tsc --noEmit` clean.
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/consultations src/locales/en/consultations.json src/locales/ar/consultations.json src/features/identity/schemas.ts && git -C dashboard commit -m "feat(consultations): B7c data layer and strings" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 13: Products page and dialog, route and nav (C-1, C-2, §5)

**Files:**
- Create: `dashboard/src/features/consultations/ProductsAdmin.tsx`, `ProductsAdmin.test.tsx`, `ProductDialog.tsx`, `ProductDialog.test.tsx`, `dashboard/src/routes/_authed/catalogue.consultations.tsx`
- Modify: `dashboard/src/features/shell/nav.ts` (B7 marker), `features/consultations/index.ts`

**Interfaces:**
- Consumes: `useProducts`, `useSaveProduct`, `useDeleteProduct`, `useConsultants`, `formErrors`, `consultationsErrorText`, `formatMoney` (`@/lib/money`), `useCan`.
- Produces: `<ProductsAdmin />`; `<ProductDialog product?: Product; open; onOpenChange />`; route `/catalogue/consultations` (`staticData: { permission: "consultation.view_any", feature: "consultations" }`); nav item.

- [ ] **Step 1: Write the failing tests**

`ProductsAdmin.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { consultationsApi } from "./api";
import { product } from "./fixtures";
import { ProductsAdmin } from "./ProductsAdmin";

vi.mock("./api", () => ({
	consultationsApi: { products: vi.fn(), consultants: vi.fn(), removeProduct: vi.fn() },
}));

function show(...codes: string[]) {
	return renderWithRouter(
		<CanProvider me={staffMe(...codes)}>
			<ProductsAdmin />
		</CanProvider>,
	);
}

describe("ProductsAdmin", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(consultationsApi.products).mockResolvedValue([product]);
		vi.mocked(consultationsApi.consultants).mockResolvedValue([
			{ id: 8, full_name: "Ustadh Bilal", offers: true },
		]);
	});

	it("lists products with price, length, mode and teachers", async () => {
		show("consultation.view_any", "consultation.create");
		expect(await screen.findByText("Placement consultation")).toBeInTheDocument();
		expect(screen.getByText("$15.00")).toBeInTheDocument();
		expect(screen.getByText("30 min")).toBeInTheDocument();
		expect(screen.getByText("Video call")).toBeInTheDocument();
		expect(screen.getByText("Ustadh Bilal")).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Add consultation" })).toBeInTheDocument();
	});

	it("filters by delivery, featured and status", async () => {
		const user = userEvent.setup();
		show("consultation.view_any");
		await screen.findByText("Placement consultation");
		await user.selectOptions(screen.getByLabelText("Delivery"), "email");
		await user.selectOptions(screen.getByLabelText("Featured"), "true");
		await user.selectOptions(screen.getByLabelText("Status"), "archived");
		await waitFor(() =>
			expect(consultationsApi.products).toHaveBeenLastCalledWith({
				mode: "email",
				featured: true,
				status: "archived",
			}),
		);
		expect(screen.queryByRole("button", { name: "Add consultation" })).toBeNull();
	});

	it("shows an empty state", async () => {
		vi.mocked(consultationsApi.products).mockResolvedValue([]);
		show("consultation.view_any");
		expect(await screen.findByText("No consultations yet.")).toBeInTheDocument();
	});
});
```

`ProductDialog.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError, type AxiosResponse } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { consultationsApi } from "./api";
import { product } from "./fixtures";
import { ProductDialog } from "./ProductDialog";

vi.mock("./api", () => ({
	consultationsApi: {
		consultants: vi.fn(),
		createProduct: vi.fn(),
		updateProduct: vi.fn(),
		removeProduct: vi.fn(),
	},
}));

describe("ProductDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(consultationsApi.consultants).mockResolvedValue([
			{ id: 8, full_name: "Ustadh Bilal", offers: true },
		]);
		vi.mocked(consultationsApi.createProduct).mockResolvedValue(product);
	});

	it("creates across the three tabs", async () => {
		const user = userEvent.setup();
		const onOpenChange = vi.fn();
		renderWithRouter(<ProductDialog open onOpenChange={onOpenChange} />);
		await user.type(screen.getByLabelText("Name (Arabic)"), "استشارة");
		await user.type(screen.getByLabelText("Name (English)"), "Placement");
		await user.type(screen.getByLabelText("Description (English)"), "Talk.");
		await user.type(screen.getByLabelText("Price"), "15.00");
		await user.click(screen.getByRole("tab", { name: "Booking" }));
		await user.clear(screen.getByLabelText("Length (minutes)"));
		await user.type(screen.getByLabelText("Length (minutes)"), "45");
		await user.click(screen.getByLabelText("Can be rescheduled"));
		await user.click(screen.getByRole("tab", { name: "Teachers" }));
		await user.click(await screen.findByLabelText("Ustadh Bilal"));
		await user.type(screen.getByLabelText("Teacher's share (%)"), "50");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() => expect(consultationsApi.createProduct).toHaveBeenCalled());
		const form = vi.mocked(consultationsApi.createProduct).mock.calls[0][0];
		expect(form.get("price_minor")).toBe("1500");
		expect(form.get("duration_minutes")).toBe("45");
		expect(form.get("reschedulable")).toBe("true");
		expect(form.getAll("teacher_ids")).toEqual(["8"]);
		expect(form.get("teacher_share_bp")).toBe("5000");
		await waitFor(() => expect(onOpenChange).toHaveBeenCalledWith(false));
	});

	it("puts a server error under its field and jumps to its tab", async () => {
		const user = userEvent.setup();
		vi.mocked(consultationsApi.updateProduct).mockRejectedValue(
			new AxiosError("x", "400", undefined, undefined, {
				status: 400,
				data: { teachers: ["Only teachers who offer consultations can be added."] },
			} as AxiosResponse),
		);
		renderWithRouter(<ProductDialog product={product} open onOpenChange={vi.fn()} />);
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(
			await screen.findByText("Only teachers who offer consultations can be added."),
		).toBeVisible();
		expect(screen.getByRole("tab", { name: "Teachers" })).toHaveAttribute(
			"aria-selected",
			"true",
		);
	});

	it("tells the office when no teacher offers consultations", async () => {
		const user = userEvent.setup();
		vi.mocked(consultationsApi.consultants).mockResolvedValue([]);
		renderWithRouter(<ProductDialog open onOpenChange={vi.fn()} />);
		await user.click(screen.getByRole("tab", { name: "Teachers" }));
		expect(
			await screen.findByText(/No teacher offers consultations yet/),
		).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run** — `F pnpm vitest run src/features/consultations/ProductsAdmin.test.tsx src/features/consultations/ProductDialog.test.tsx` → FAIL.

- [ ] **Step 3: Implement**

`ProductDialog.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";
import { toMajor, toMinor } from "@/lib/money";
import {
	AlertDialog,
	AlertDialogAction,
	AlertDialogCancel,
	AlertDialogContent,
	AlertDialogDescription,
	AlertDialogFooter,
	AlertDialogTitle,
	AlertDialogTrigger,
	Button,
	Checkbox,
	Dialog,
	DialogContent,
	DialogFooter,
	DialogTitle,
	Field,
	FormError,
	Input,
	Label,
	Select,
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { consultationsErrorText, formErrors } from "./errors";
import { useConsultants, useDeleteProduct, useSaveProduct } from "./queries";
import { DELIVERY_MODES, type Product } from "./schemas";

type Tab = "details" | "booking" | "teachers";
const TAB_OF: Record<string, Tab> = {
	duration_minutes: "booking",
	validity_days: "booking",
	participants: "booking",
	delivery_mode: "booking",
	teachers: "teachers",
	teacher_share_bp: "teachers",
};
const INPUTS = [
	"name_ar", "name_en", "description_ar", "description_en", "price_minor",
	"currency", "status", "cover", "duration_minutes", "validity_days",
	"participants", "delivery_mode", "teachers", "teacher_share_bp",
] as const;

interface Form {
	name_ar: string;
	name_en: string;
	description_ar: string;
	description_en: string;
	price: string;
	currency: string;
	status: "available" | "archived";
	enabled: boolean;
	featured: boolean;
	duration_minutes: string;
	validity_days: string;
	participants: string;
	delivery_mode: string;
	reschedulable: boolean;
	fee_enabled: boolean;
	teacher_ids: number[];
	share: string;
}

function initial(p?: Product): Form {
	return {
		name_ar: p?.name_ar ?? "",
		name_en: p?.name_en ?? "",
		description_ar: p?.description_ar ?? "",
		description_en: p?.description_en ?? "",
		price: p ? toMajor(p.price_minor, p.currency) : "",
		currency: p?.currency ?? "USD",
		status: p?.status ?? "available",
		enabled: p?.enabled ?? true,
		featured: p?.featured ?? false,
		duration_minutes: String(p?.duration_minutes ?? 30),
		validity_days: String(p?.validity_days ?? 7),
		participants: String(p?.participants ?? 1),
		delivery_mode: p?.delivery_mode ?? "video_call",
		reschedulable: p?.reschedulable ?? false,
		fee_enabled: p?.fee_enabled ?? false,
		teacher_ids: p?.teachers.map((t) => t.id) ?? [],
		share: p ? String(p.teacher_share_bp / 100) : "",
	};
}

function toFormData(f: Form, cover: File | null, removeCover: boolean): FormData {
	const data = new FormData();
	const put = (k: string, v: string) => data.append(k, v);
	put("name_ar", f.name_ar);
	put("name_en", f.name_en);
	put("description_ar", f.description_ar);
	put("description_en", f.description_en);
	const currency = f.currency.trim().toUpperCase();
	put("price_minor", String(toMinor(f.price || "0", currency)));
	put("currency", currency);
	put("status", f.status);
	for (const key of ["enabled", "featured", "reschedulable", "fee_enabled"] as const)
		put(key, String(f[key]));
	put("duration_minutes", f.duration_minutes);
	put("validity_days", f.validity_days);
	put("participants", f.participants);
	put("delivery_mode", f.delivery_mode);
	put("teacher_share_bp", String(Math.round(Number.parseFloat(f.share || "0") * 100)));
	for (const id of f.teacher_ids) data.append("teacher_ids", String(id));
	if (cover) data.append("cover", cover);
	if (removeCover) put("remove_cover", "true");
	return data;
}

export function ProductDialog({
	product,
	open,
	onOpenChange,
}: {
	product?: Product;
	open: boolean;
	onOpenChange: (open: boolean) => void;
}) {
	const { t } = useTranslation();
	const can = useCan();
	const [form, setForm] = useState<Form>(() => initial(product));
	const [cover, setCover] = useState<File | null>(null);
	const [removeCover, setRemoveCover] = useState(false);
	const [tab, setTab] = useState<Tab>("details");
	const teachers = useConsultants(true, open);
	const save = useSaveProduct(product?.id);
	const errors = save.error ? formErrors(save.error, t, INPUTS) : { fields: {} as Record<string, string> };
	const set = <K extends keyof Form>(key: K, value: Form[K]) =>
		setForm((f) => ({ ...f, [key]: value }));
	const err = (name: string) => errors.fields[name];

	async function submit(e: React.FormEvent) {
		e.preventDefault();
		try {
			await save.mutateAsync(toFormData(form, cover, removeCover));
			toast.success(t("consultations.products.saved"));
			onOpenChange(false);
		} catch (error) {
			const fields = formErrors(error, t, INPUTS).fields;
			const first = Object.keys(fields)[0];
			setTab(first ? (TAB_OF[first] ?? "details") : tab);
		}
	}

	const tabButton = (key: Tab) => (
		<button
			key={key}
			type="button"
			role="tab"
			aria-selected={tab === key}
			aria-controls={`product-tab-${key}`}
			className={tab === key ? "border-b-2 border-primary px-3 py-2 font-medium" : "px-3 py-2 text-muted-foreground"}
			onClick={() => setTab(key)}
		>
			{t(`consultations.products.tabs.${key}`)}
		</button>
	);
	const text = (id: keyof Form, label: string, props: React.ComponentProps<typeof Input> = {}) => (
		<Field id={`product-${id}`} label={label} error={err(id)}>
			<Input value={form[id] as string} onChange={(e) => set(id, e.target.value as never)} {...props} />
		</Field>
	);
	const check = (id: "enabled" | "featured" | "reschedulable" | "fee_enabled", label: string) => (
		<div className="flex items-center gap-2">
			<Checkbox id={`product-${id}`} checked={form[id]} onCheckedChange={(v) => set(id, v)} />
			<Label htmlFor={`product-${id}`}>{label}</Label>
		</div>
	);
	const remove = useDeleteProduct();
	async function destroy() {
		if (!product) return;
		try {
			await remove.mutateAsync(product.id);
			toast.success(t("consultations.products.deleted"));
			onOpenChange(false);
		} catch {
			// The message shows from remove.error below.
		}
	}

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent size="lg">
				<DialogTitle>
					{product ? t("consultations.products.editTitle") : t("consultations.products.newTitle")}
				</DialogTitle>
				<form onSubmit={submit} className="flex flex-col gap-4" noValidate>
					<div role="tablist" className="flex gap-1 border-b border-border">
						{(["details", "booking", "teachers"] as const).map(tabButton)}
					</div>
					{errors.form ? <FormError>{errors.form}</FormError> : null}
					{remove.error ? (
						<FormError>{consultationsErrorText(remove.error, t)}</FormError>
					) : null}
					<div id="product-tab-details" role="tabpanel" hidden={tab !== "details"} className="flex flex-col gap-3">
						<Field id="product-cover" label={t("consultations.products.fields.cover")} error={err("cover")}>
							<Input type="file" accept="image/png,image/jpeg,image/webp"
								onChange={(e) => setCover(e.target.files?.[0] ?? null)} />
						</Field>
						{product?.cover_url ? (
							<div className="flex items-center gap-2">
								<Checkbox id="product-remove-cover" checked={removeCover} onCheckedChange={setRemoveCover} />
								<Label htmlFor="product-remove-cover">{t("consultations.products.fields.removeCover")}</Label>
							</div>
						) : null}
						{text("name_ar", t("consultations.products.fields.nameAr"), { dir: "rtl" })}
						{text("name_en", t("consultations.products.fields.nameEn"), { dir: "ltr" })}
						<Field id="product-description_ar" label={t("consultations.products.fields.descriptionAr")} error={err("description_ar")}>
							<Textarea dir="rtl" value={form.description_ar} onChange={(e) => set("description_ar", e.target.value)} />
						</Field>
						<Field id="product-description_en" label={t("consultations.products.fields.descriptionEn")} error={err("description_en")}>
							<Textarea dir="ltr" value={form.description_en} onChange={(e) => set("description_en", e.target.value)} />
						</Field>
						<div className="grid gap-3 sm:grid-cols-2">
							<Field id="product-price" label={t("consultations.products.fields.price")} error={err("price_minor")}>
								<Input inputMode="decimal" value={form.price} onChange={(e) => set("price", e.target.value)} />
							</Field>
							{text("currency", t("consultations.products.fields.currency"), { maxLength: 3 })}
						</div>
						<Field id="product-status" label={t("consultations.products.fields.status")} error={err("status")}>
							<Select value={form.status} onChange={(e) => set("status", e.target.value as Form["status"])}>
								<option value="available">{t("consultations.products.productStatuses.available")}</option>
								<option value="archived">{t("consultations.products.productStatuses.archived")}</option>
							</Select>
						</Field>
						{check("enabled", t("consultations.products.fields.enabled"))}
						{check("featured", t("consultations.products.fields.featured"))}
					</div>
					<div id="product-tab-booking" role="tabpanel" hidden={tab !== "booking"} className="flex flex-col gap-3">
						{text("duration_minutes", t("consultations.products.fields.duration"), { inputMode: "numeric" })}
						{text("validity_days", t("consultations.products.fields.validity"), { inputMode: "numeric" })}
						<p className="text-sm text-muted-foreground">{t("consultations.products.fields.validityHint")}</p>
						{text("participants", t("consultations.products.fields.participants"), { inputMode: "numeric" })}
						<Field id="product-delivery_mode" label={t("consultations.products.fields.mode")} error={err("delivery_mode")}>
							<Select value={form.delivery_mode} onChange={(e) => set("delivery_mode", e.target.value)}>
								{DELIVERY_MODES.map((m) => (
									<option key={m} value={m}>{t(`consultations.modes.${m}`)}</option>
								))}
							</Select>
						</Field>
						{check("reschedulable", t("consultations.products.fields.reschedulable"))}
						{check("fee_enabled", t("consultations.products.fields.fee"))}
					</div>
					<div id="product-tab-teachers" role="tabpanel" hidden={tab !== "teachers"} className="flex flex-col gap-3">
						<fieldset className="flex flex-col gap-2" aria-describedby={err("teachers") ? "product-teachers-error" : undefined}>
							<legend className="text-sm font-medium">{t("consultations.products.fields.teachers")}</legend>
							{teachers.data?.length === 0 ? (
								<p className="text-sm text-muted-foreground">{t("consultations.products.noTeachers")}</p>
							) : null}
							{teachers.data?.map((teacher) => (
								<div key={teacher.id} className="flex items-center gap-2">
									<Checkbox
										id={`product-teacher-${teacher.id}`}
										checked={form.teacher_ids.includes(teacher.id)}
										onCheckedChange={(on) =>
											set("teacher_ids", on
												? [...form.teacher_ids, teacher.id]
												: form.teacher_ids.filter((id) => id !== teacher.id))
										}
									/>
									<Label htmlFor={`product-teacher-${teacher.id}`}>{teacher.full_name}</Label>
								</div>
							))}
							{err("teachers") ? (
								<p id="product-teachers-error" className="text-sm text-destructive">{err("teachers")}</p>
							) : null}
						</fieldset>
						<Field id="product-share" label={t("consultations.products.fields.share")} error={err("teacher_share_bp")}>
							<Input inputMode="decimal" value={form.share} onChange={(e) => set("share", e.target.value)} />
						</Field>
					</div>
					<DialogFooter>
						{product && can("consultation.delete") ? (
							<AlertDialog>
								<AlertDialogTrigger asChild>
									<Button type="button" variant="outline" className="me-auto">
										{t("consultations.delete")}
									</Button>
								</AlertDialogTrigger>
								<AlertDialogContent>
									<AlertDialogTitle>{t("consultations.products.editTitle")}</AlertDialogTitle>
									<AlertDialogDescription>
										{t("consultations.products.deleteConfirm")}
									</AlertDialogDescription>
									<AlertDialogFooter>
										<AlertDialogCancel asChild>
											<Button variant="outline">{t("consultations.cancel")}</Button>
										</AlertDialogCancel>
										<AlertDialogAction asChild>
											<Button onClick={destroy}>{t("consultations.delete")}</Button>
										</AlertDialogAction>
									</AlertDialogFooter>
								</AlertDialogContent>
							</AlertDialog>
						) : null}
						<Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
							{t("consultations.cancel")}
						</Button>
						<SubmitButton pending={save.isPending}>{t("consultations.save")}</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

(Teachers already on an edited product who have since opted out are not in the opted-in list. They stay in `teacher_ids`, and the server accepts them, because spec §4 re-checks opt-in only for newly added teachers. `ProductDialog.test.tsx` wraps the dialog in `<CanProvider me={staffMe("consultation.update", "consultation.delete")}>` in the edit test, and adds: `it("shows the product_in_use message when delete is refused")` — mock `removeProduct` to reject with a 409 `consultations.product_in_use`, click Delete then confirm, and expect "This consultation has requests: archive it instead.")

`ProductsAdmin.tsx`:

```tsx
import { MessagesSquare } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";
import { formatMoney } from "@/lib/money";
import {
	Button,
	Card,
	CardContent,
	EmptyState,
	FormError,
	Select,
	Spinner,
	StatusChip,
} from "@/ui";
import { consultationsErrorText } from "./errors";
import { ProductDialog } from "./ProductDialog";
import { useProducts } from "./queries";
import { DELIVERY_MODES, type Product, type ProductFilters } from "./schemas";

const flag = (v: string) => (v === "" ? undefined : v === "true");

export function ProductsAdmin() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const [mode, setMode] = useState("");
	const [featured, setFeatured] = useState("");
	const [status, setStatus] = useState("");
	const [editing, setEditing] = useState<Product | "new" | null>(null);
	const filters: ProductFilters = {
		mode: mode || undefined,
		featured: flag(featured),
		status: status || undefined,
	};
	const list = useProducts(filters);
	const name = (p: Product) => (i18n.language === "ar" ? p.name_ar : p.name_en);

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-2">
				<Select aria-label={t("consultations.products.filters.mode")} className="w-auto"
					value={mode} onChange={(e) => setMode(e.target.value)}>
					<option value="">{t("consultations.any")}</option>
					{DELIVERY_MODES.map((m) => (
						<option key={m} value={m}>{t(`consultations.modes.${m}`)}</option>
					))}
				</Select>
				<Select aria-label={t("consultations.products.filters.featured")} className="w-auto"
					value={featured} onChange={(e) => setFeatured(e.target.value)}>
					<option value="">{t("consultations.any")}</option>
					<option value="true">{t("consultations.yes")}</option>
					<option value="false">{t("consultations.no")}</option>
				</Select>
				<Select aria-label={t("consultations.products.filters.status")} className="w-auto"
					value={status} onChange={(e) => setStatus(e.target.value)}>
					<option value="">{t("consultations.any")}</option>
					<option value="available">{t("consultations.products.productStatuses.available")}</option>
					<option value="archived">{t("consultations.products.productStatuses.archived")}</option>
				</Select>
				{can("consultation.create") ? (
					<Button className="ms-auto" onClick={() => setEditing("new")}>
						{t("consultations.products.add")}
					</Button>
				) : null}
			</div>
			{list.isPending ? (
				<div className="flex justify-center py-6"><Spinner /></div>
			) : list.isError ? (
				<FormError>{consultationsErrorText(list.error, t)}</FormError>
			) : list.data.length === 0 ? (
				<Card><CardContent>
					<EmptyState icon={MessagesSquare} title={t("consultations.products.empty")} />
				</CardContent></Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{(["name", "price", "duration", "mode", "teachers", "status", "enabled"] as const).map((c) => (
									<th key={c} scope="col" className="p-3 text-start font-medium">
										{t(`consultations.products.columns.${c}`)}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{list.data.map((p) => (
								<tr key={p.id} className="border-t border-border">
									<td className="p-3">
										{can("consultation.update") ? (
											<button type="button" className="flex items-center gap-3 font-medium text-start"
												onClick={() => setEditing(p)}>
												{p.cover_url ? <img src={p.cover_url} alt="" className="h-9 w-16 rounded object-cover" /> : null}
												{name(p)}
											</button>
										) : (
											<span className="font-medium">{name(p)}</span>
										)}
									</td>
									<td className="p-3">{formatMoney(p.price_minor, p.currency, i18n.language)}</td>
									<td className="p-3">{t("consultations.minutes", { count: p.duration_minutes })}</td>
									<td className="p-3">{t(`consultations.modes.${p.delivery_mode}`)}</td>
									<td className="p-3">
										{p.teachers.map((x) => x.full_name).join(i18n.language === "ar" ? "، " : ", ")}
									</td>
									<td className="p-3">
										<StatusChip tone={p.status === "available" ? "live" : "neutral"}>
											{t(`consultations.products.productStatuses.${p.status}`)}
										</StatusChip>
									</td>
									<td className="p-3">{t(p.enabled ? "consultations.yes" : "consultations.no")}</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			{editing ? (
				<ProductDialog
					product={editing === "new" ? undefined : editing}
					open
					onOpenChange={(open) => !open && setEditing(null)}
				/>
			) : null}
		</div>
	);
}
```

Route `dashboard/src/routes/_authed/catalogue.consultations.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { ProductsAdmin } from "@/features/consultations";
import { PageHeader } from "@/ui";

// Plan 50 (B7c, spec C-1): consultation products.
export const Route = createFileRoute("/_authed/catalogue/consultations")({
	staticData: { permission: "consultation.view_any", feature: "consultations" },
	component: function ConsultationProductsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("consultations.products.title"));
		return (
			<>
				<PageHeader
					title={t("consultations.products.title")}
					description={t("consultations.products.subtitle")}
				/>
				<ProductsAdmin />
			</>
		);
	},
});
```

`nav.ts`, under `// ── phase B7 ──` (after B7a's items if present; import `MessagesSquare` from `lucide-react` with the others):

```ts
	office(
		"/catalogue/consultations",
		"consultations.nav.products",
		MessagesSquare,
		"catalogue",
		"consultation.view_any",
		"consultations",
	),
```

Regenerate `routeTree.gen.ts` (the dev server or `F pnpm tsr generate`, as the repo does).

- [ ] **Step 4: Run** — `F pnpm vitest run src/features/consultations src/features/shell` → PASS; `F pnpm tsc --noEmit`; `F pnpm lint`.
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/consultations src/routes/_authed/catalogue.consultations.tsx src/features/shell/nav.ts src/routeTree.gen.ts && git -C dashboard commit -m "feat(consultations): B7c products page" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 14: ConsultantCard on the teacher page (C-3, phase §4)

**Files:**
- Create: `dashboard/src/features/consultations/ConsultantCard.tsx`, `ConsultantCard.test.tsx`
- Modify: `dashboard/src/routes/_authed/people.teachers.$personId.tsx` (one import, one line), `features/consultations/index.ts`

**Interfaces:**
- Consumes: `useConsultant`, `useSetConsultant`, `useHasFeature`, `useCan`.
- Produces: `<ConsultantCard teacherId: number />`. It renders nothing while `consultations` is off, without `consultation.view_any`, or when the read fails (403/404). The toggle is enabled only with `consultation.update`.

- [ ] **Step 1: Write the failing test** (`ConsultantCard.test.tsx`)

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { consultationsApi } from "./api";
import { ConsultantCard } from "./ConsultantCard";

vi.mock("./api", () => ({
	consultationsApi: { consultant: vi.fn(), setConsultant: vi.fn() },
}));

describe("ConsultantCard", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(consultationsApi.consultant).mockResolvedValue({ teacher_id: 8, offers: false });
		vi.mocked(consultationsApi.setConsultant).mockResolvedValue({ teacher_id: 8, offers: true });
	});

	it("toggles the opt-in for an admin", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<CanProvider me={adminWith("consultations")}>
				<ConsultantCard teacherId={8} />
			</CanProvider>,
		);
		const box = await screen.findByLabelText("Offers consultations");
		await user.click(box);
		await waitFor(() => expect(consultationsApi.setConsultant).toHaveBeenCalledWith(8, true));
	});

	it("renders nothing while the switch is off", () => {
		const { container } = renderWithRouter(
			<CanProvider me={adminWith()}>
				<ConsultantCard teacherId={8} />
			</CanProvider>,
		);
		expect(container).toBeEmptyDOMElement();
		expect(consultationsApi.consultant).not.toHaveBeenCalled();
	});

	it("is read-only without consultation.update", async () => {
		renderWithRouter(
			<CanProvider me={{ ...staffMe("consultation.view_any"), features: ["consultations"] }}>
				<ConsultantCard teacherId={8} />
			</CanProvider>,
		);
		expect(await screen.findByLabelText("Offers consultations")).toBeDisabled();
	});
});
```

(If `renderWithRouter` wraps its children in a layout element, assert `screen.queryByText("Consultations")` is null instead of `toBeEmptyDOMElement`.)

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** `ConsultantCard.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { Card, CardContent, CardHeader, CardTitle, Checkbox, Label, toast } from "@/ui";
import { consultationsErrorText } from "./errors";
import { useConsultant, useSetConsultant } from "./queries";

/** Spec C-3: the teacher's "offers consultations" switch, on the teacher page. */
export function ConsultantCard({ teacherId }: { teacherId: number }) {
	const { t } = useTranslation();
	const can = useCan();
	const hasFeature = useHasFeature();
	const visible = hasFeature("consultations") && can("consultation.view_any");
	const state = useConsultant(teacherId, visible);
	const set = useSetConsultant(teacherId);
	if (!visible || !state.data) return null;
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("consultations.consultant.title")}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-2">
				<div className="flex items-center gap-2">
					<Checkbox
						id="consultant-offers"
						checked={state.data.offers}
						disabled={!can("consultation.update") || set.isPending}
						onCheckedChange={(offers) =>
							set.mutate(offers, {
								onError: (error) => toast.error(consultationsErrorText(error, t)),
							})
						}
					/>
					<Label htmlFor="consultant-offers">{t("consultations.consultant.offers")}</Label>
				</div>
				<p className="text-sm text-muted-foreground">{t("consultations.consultant.hint")}</p>
			</CardContent>
		</Card>
	);
}
```

`people.teachers.$personId.tsx`: add `import { ConsultantCard } from "@/features/consultations";` with the other feature imports, and directly after the availability card block:

```tsx
				{personId !== "new" ? <ConsultantCard teacherId={Number(personId)} /> : null}
```

- [ ] **Step 4: Run** — `F pnpm vitest run src/features/consultations "src/routes/_authed/people.teachers.\$personId.test.tsx"` → PASS (the existing route test still passes: the card renders nothing without the feature).
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/consultations "src/routes/_authed/people.teachers.\$personId.tsx" && git -C dashboard commit -m "feat(consultations): B7c teacher opt-in card" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 15: Request dialog, slot picker, delivery and payment dialogs (C-4, C-5, C-7, C-8, C-9)

**Files:**
- Create: `dashboard/src/features/consultations/SlotPicker.tsx`, `SlotPicker.test.tsx`, `RequestDialog.tsx` (exports `RequestDialog` and `DeliveryDialog`), `RequestDialog.test.tsx`, `PaymentDialog.tsx`, `PaymentDialog.test.tsx`, `WarningsList.tsx`

**Interfaces:**
- Consumes: `useSlots`, `useProducts`, `useCreateRequest`, `useUpdateRequest`, `useRequestAction`, `useDelivery`, `useRecordPayment`, `formErrors`, `usePeople` (`@/features/people`, `"students"`, `{ q, is_active: "true", page_size: 20 }`, rows `{ id, user: { full_name } }`), `useAcademySettings`, `zonedInstant`, `wallTime`, `dayIn`, `todayIn`, `addDays` (`@/lib/zoned-time`), `timezoneOptions` (`@/lib/timezones`), `toMinor`, `toMajor`, `formatMoney` (`@/lib/money`).
- Produces:
  - `<SlotPicker productId teacherId requestId? zone value onChange(iso) />`: a 7-day page of free slots grouped by academy day, with previous/next; "Select a teacher first…" while no teacher; the `availability_off` note.
  - `<RequestDialog mode: "new" | "edit" | "reschedule"; row?; open; onOpenChange />`: `new` and `edit` show the four CONS-002 sections; `reschedule` shows only teacher and start. Starts are picked from `SlotPicker` or typed (date + time on the academy clock → `zonedInstant`).
  - `<DeliveryDialog row open onOpenChange />`: link, both attendances, session status (email requests: link only).
  - `<PaymentDialog row open onOpenChange />`: billing method, amount (default the product price), paid on, reference, transaction number; the Telda/PayMob hint.
  - `<WarningsList warnings zone />`: the C-5 warnings, used after a save (shown in a toast-like `Alert` inside the dialog, which then stays open until closed).

- [ ] **Step 1: Write the failing tests**

`SlotPicker.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { consultationsApi } from "./api";
import { SlotPicker } from "./SlotPicker";

vi.mock("./api", () => ({ consultationsApi: { slots: vi.fn() } }));

describe("SlotPicker", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(consultationsApi.slots).mockResolvedValue({
			availability_off: false,
			slots: [
				{ starts_at: "2026-10-12T16:00:00+00:00", remaining: 1 },
				{ starts_at: "2026-10-12T16:30:00+00:00", remaining: 2 },
			],
		});
	});

	it("asks for a teacher first", () => {
		renderWithRouter(<SlotPicker productId={3} zone="UTC" value="" onChange={vi.fn()} from="2026-10-12" />);
		expect(screen.getByText("Select a teacher first to see available slots")).toBeInTheDocument();
		expect(consultationsApi.slots).not.toHaveBeenCalled();
	});

	it("lists slots by day and picks one", async () => {
		const user = userEvent.setup();
		const onChange = vi.fn();
		renderWithRouter(
			<SlotPicker productId={3} teacherId={8} zone="UTC" value="" onChange={onChange} from="2026-10-12" />,
		);
		await user.click(await screen.findByRole("radio", { name: /16:30/ }));
		expect(onChange).toHaveBeenCalledWith("2026-10-12T16:30:00+00:00");
		expect(screen.getByText("2 left")).toBeInTheDocument();
		await user.click(screen.getByRole("button", { name: "Later days" }));
		expect(consultationsApi.slots).toHaveBeenLastCalledWith(3, {
			teacher: 8, from: "2026-10-19", days: 7,
		});
	});

	it("says when availability is off", async () => {
		vi.mocked(consultationsApi.slots).mockResolvedValue({ availability_off: true, slots: [] });
		renderWithRouter(
			<SlotPicker productId={3} teacherId={8} zone="UTC" value="" onChange={vi.fn()} from="2026-10-12" />,
		);
		expect(await screen.findByText(/Teacher availability is off/)).toBeInTheDocument();
	});
});
```

`RequestDialog.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { consultationsApi } from "./api";
import { product, request, writeAnswer } from "./fixtures";
import { DeliveryDialog, RequestDialog } from "./RequestDialog";

vi.mock("./api", () => ({
	consultationsApi: {
		products: vi.fn(),
		slots: vi.fn(),
		createRequest: vi.fn(),
		updateRequest: vi.fn(),
		action: vi.fn(),
		delivery: vi.fn(),
	},
}));
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
vi.mock("@/features/people/api", async (orig) => ({
	...(await orig<typeof import("@/features/people/api")>()),
	peopleApi: { list: vi.fn() },
}));

describe("RequestDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue({ timezone: "UTC" } as never);
		vi.mocked(consultationsApi.products).mockResolvedValue([product]);
		vi.mocked(consultationsApi.slots).mockResolvedValue({
			availability_off: false,
			slots: [{ starts_at: "2026-10-12T16:00:00+00:00", remaining: 1 }],
		});
		vi.mocked(peopleApi.list).mockResolvedValue({
			count: 1, next: null, previous: null,
			results: [{ id: 21, user: { full_name: "Yusuf Omar" } }],
		} as never);
		vi.mocked(consultationsApi.createRequest).mockResolvedValue(writeAnswer);
	});

	it("creates a request for an unregistered person from a free slot", async () => {
		const user = userEvent.setup();
		const onOpenChange = vi.fn();
		renderWithRouter(<RequestDialog mode="new" open onOpenChange={onOpenChange} />);
		await user.type(screen.getByLabelText("Name"), "Ali");
		await user.type(screen.getByLabelText("Email"), "ali@x.test");
		await user.type(screen.getByLabelText("WhatsApp"), "+1555");
		await user.selectOptions(await screen.findByLabelText("Consultation"), "3");
		await user.selectOptions(screen.getByLabelText("Teacher"), "8");
		await user.click(await screen.findByRole("radio", { name: /16:00/ }));
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(consultationsApi.createRequest).toHaveBeenCalledWith(
				expect.objectContaining({
					product: 3, teacher: 8, student: null, name: "Ali",
					email: "ali@x.test", whatsapp: "+1555",
					starts_at: "2026-10-12T16:00:00+00:00",
				}),
			),
		);
		await waitFor(() => expect(onOpenChange).toHaveBeenCalledWith(false));
	});

	it("types a time on the academy clock instead of a slot", async () => {
		const user = userEvent.setup();
		renderWithRouter(<RequestDialog mode="edit" row={request} open onOpenChange={vi.fn()} />);
		vi.mocked(consultationsApi.updateRequest).mockResolvedValue({
			...writeAnswer,
			warnings: { conflicts: [], outside_availability: true, outside_validity: false },
		});
		await user.click(await screen.findByRole("button", { name: "Type a time instead" }));
		await user.clear(screen.getByLabelText("Date"));
		await user.type(screen.getByLabelText("Date"), "2026-10-13");
		await user.type(screen.getByLabelText("Time (academy clock)"), "09:30");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(consultationsApi.updateRequest).toHaveBeenCalledWith(5,
				expect.objectContaining({ starts_at: "2026-10-13T09:30:00.000Z" })),
		);
		expect(await screen.findByText("Outside the teacher's availability")).toBeInTheDocument();
	});

	it("reschedules through the action route", async () => {
		const user = userEvent.setup();
		vi.mocked(consultationsApi.action).mockResolvedValue(writeAnswer);
		renderWithRouter(
			<RequestDialog mode="reschedule" row={{ ...request, status: "confirmed" }} open onOpenChange={vi.fn()} />,
		);
		await user.click(await screen.findByRole("radio", { name: /16:00/ }));
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(consultationsApi.action).toHaveBeenCalledWith(5, "reschedule", {
				starts_at: "2026-10-12T16:00:00+00:00", teacher: 8,
			}),
		);
	});
});

describe("DeliveryDialog", () => {
	it("records attendance and the session status", async () => {
		const user = userEvent.setup();
		vi.mocked(consultationsApi.delivery).mockResolvedValue(writeAnswer);
		renderWithRouter(<DeliveryDialog row={{ ...request, status: "confirmed" }} open onOpenChange={vi.fn()} />);
		await user.selectOptions(screen.getByLabelText("Student attendance"), "present");
		await user.selectOptions(screen.getByLabelText("Teacher attendance"), "present");
		await user.selectOptions(screen.getByLabelText("Session status"), "completed");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(consultationsApi.delivery).toHaveBeenCalledWith(5, {
				meeting_url: "https://meet.test/bilal",
				student_attendance: "present",
				teacher_attendance: "present",
				session_status: "completed",
			}),
		);
	});
});
```

(If `peopleApi` is not exported from `@/features/people/api` under that name, mock the module `usePeople` imports; check with `grep -n "export const peopleApi" dashboard/src/features/people/api.ts`.)

`PaymentDialog.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { consultationsApi } from "./api";
import { request, writeAnswer } from "./fixtures";
import { PaymentDialog } from "./PaymentDialog";

vi.mock("./api", () => ({ consultationsApi: { payment: vi.fn() } }));

describe("PaymentDialog", () => {
	it("records a hand payment, the amount defaulting to the price", async () => {
		const user = userEvent.setup();
		vi.mocked(consultationsApi.payment).mockResolvedValue(writeAnswer);
		renderWithRouter(<PaymentDialog row={request} open onOpenChange={vi.fn()} />);
		expect(screen.getByLabelText("Amount")).toHaveValue("15.00");
		expect(screen.getByText(/Telda, PayMob/)).toBeInTheDocument();
		await user.selectOptions(screen.getByLabelText("Payment method"), "other");
		await user.type(screen.getByLabelText("Reference"), "Telda");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(consultationsApi.payment).toHaveBeenCalledWith(5, {
				billing_method: "other",
				amount_minor: 1500,
				paid_on: null,
				reference: "Telda",
				transaction_number: "",
			}),
		);
	});
});
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

`SlotPicker.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { addDays, dayIn, wallTime } from "@/lib/zoned-time";
import { Button, Spinner } from "@/ui";
import { useSlots } from "./queries";

const DAYS = 7;

export function SlotPicker({
	productId,
	teacherId,
	requestId,
	zone,
	from,
	value,
	onChange,
}: {
	productId?: number;
	teacherId?: number;
	requestId?: number;
	zone: string;
	/** The first day shown, YYYY-MM-DD on the academy clock. */
	from: string;
	value: string;
	onChange: (startsAt: string) => void;
}) {
	const { t, i18n } = useTranslation();
	const [first, setFirst] = useState(from);
	const slots = useSlots(productId, {
		teacher: teacherId,
		from: first,
		days: DAYS,
		...(requestId ? { request: requestId } : {}),
	});
	if (productId === undefined || teacherId === undefined) {
		return <p className="text-sm text-muted-foreground">{t("consultations.dialog.pickTeacherFirst")}</p>;
	}
	const byDay = new Map<string, { starts_at: string; remaining: number }[]>();
	for (const slot of slots.data?.slots ?? []) {
		const day = dayIn(new Date(slot.starts_at), zone, i18n.language);
		byDay.set(day, [...(byDay.get(day) ?? []), slot]);
	}
	return (
		<fieldset className="flex flex-col gap-2">
			<legend className="text-sm font-medium">{t("consultations.dialog.slots.title")}</legend>
			{slots.isPending ? <Spinner /> : null}
			{slots.data?.availability_off ? (
				<p className="text-sm text-muted-foreground">{t("consultations.dialog.slots.off")}</p>
			) : slots.data && byDay.size === 0 ? (
				<p className="text-sm text-muted-foreground">{t("consultations.dialog.slots.empty")}</p>
			) : null}
			{[...byDay.entries()].map(([day, items]) => (
				<div key={day} className="flex flex-col gap-1">
					<span className="text-sm text-muted-foreground">{day}</span>
					<div role="radiogroup" aria-label={day} className="flex flex-wrap gap-2">
						{items.map((slot) => {
							const time = wallTime(new Date(slot.starts_at), zone, i18n.language);
							const chosen = value === slot.starts_at;
							return (
								<button
									key={slot.starts_at}
									type="button"
									role="radio"
									aria-checked={chosen}
									aria-label={`${day} ${time}`}
									onClick={() => onChange(slot.starts_at)}
									className={chosen
										? "rounded-md border border-primary bg-primary px-3 py-1 text-primary-foreground"
										: "rounded-md border border-border px-3 py-1"}
								>
									{time}
									{slot.remaining > 1 ? (
										<span className="ms-1 text-xs">
											{t("consultations.dialog.slots.remaining", { count: slot.remaining })}
										</span>
									) : null}
								</button>
							);
						})}
					</div>
				</div>
			))}
			<div className="flex gap-2">
				<Button type="button" size="sm" variant="outline" onClick={() => setFirst(addDays(first, -DAYS))}>
					{t("consultations.dialog.slots.previous")}
				</Button>
				<Button type="button" size="sm" variant="outline" onClick={() => setFirst(addDays(first, DAYS))}>
					{t("consultations.dialog.slots.next")}
				</Button>
			</div>
		</fieldset>
	);
}
```

(The test's "2 left" assertion is for the second slot, whose `remaining` is 2.)

`WarningsList.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { wallTime } from "@/lib/zoned-time";
import { Alert, AlertDescription, AlertTitle } from "@/ui";
import type { Warnings } from "./schemas";

export function hasWarnings(w: Warnings | null): w is Warnings {
	return !!w && (w.conflicts.length > 0 || w.outside_availability || w.outside_validity);
}

export function WarningsList({ warnings, zone }: { warnings: Warnings; zone: string }) {
	const { t, i18n } = useTranslation();
	return (
		<Alert>
			<AlertTitle>{t("consultations.dialog.warnings.title")}</AlertTitle>
			<AlertDescription>
				<ul className="list-disc ps-5">
					{warnings.conflicts.map((c) => (
						<li key={`${c.kind}-${c.id ?? c.starts_at}`}>
							{t(`consultations.dialog.warnings.${c.kind}`, {
								time: wallTime(new Date(c.starts_at), zone, i18n.language),
							})}
						</li>
					))}
					{warnings.outside_availability ? (
						<li>{t("consultations.dialog.warnings.outsideAvailability")}</li>
					) : null}
					{warnings.outside_validity ? (
						<li>{t("consultations.dialog.warnings.outsideValidity")}</li>
					) : null}
				</ul>
			</AlertDescription>
		</Alert>
	);
}
```

`RequestDialog.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy";
import { usePeople } from "@/features/people";
import { formatMoney } from "@/lib/money";
import { timezoneOptions } from "@/lib/timezones";
import { formatDay, todayIn, zonedInstant } from "@/lib/zoned-time";
import {
	Button,
	Dialog,
	DialogContent,
	DialogFooter,
	DialogTitle,
	Field,
	FormError,
	Input,
	Select,
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { formErrors } from "./errors";
import { useCreateRequest, useDelivery, useProducts, useRequestAction, useUpdateRequest } from "./queries";
import {
	ATTENDANCE,
	type ConsultationRequest,
	SESSION_STATUSES,
	type Warnings,
	type WriteAnswer,
} from "./schemas";
import { SlotPicker } from "./SlotPicker";
import { hasWarnings, WarningsList } from "./WarningsList";

const INPUTS = [
	"student", "name", "email", "whatsapp", "timezone", "product", "teacher",
	"starts_at", "meeting_url", "notes",
] as const;

type Mode = "new" | "edit" | "reschedule";

export function RequestDialog({
	mode,
	row,
	open,
	onOpenChange,
}: {
	mode: Mode;
	row?: ConsultationRequest;
	open: boolean;
	onOpenChange: (open: boolean) => void;
}) {
	const { t, i18n } = useTranslation();
	const zone = useAcademySettings().data?.timezone ?? "UTC";
	const products = useProducts({ status: "available" }, open);
	const [search, setSearch] = useState("");
	const students = usePeople<{ id: number; user: { full_name: string } }>(
		"students",
		{ q: search, is_active: "true", page_size: 20 },
		{ enabled: open && mode === "new" },
	);
	const [student, setStudent] = useState<string>(row?.student ? String(row.student.id) : "");
	const [name, setName] = useState(row?.name ?? "");
	const [email, setEmail] = useState(row?.email ?? "");
	const [whatsapp, setWhatsapp] = useState(row?.whatsapp ?? "");
	const [timezone, setTimezone] = useState(row?.timezone ?? "");
	const [productId, setProductId] = useState<string>(row ? String(row.product.id) : "");
	const [teacherId, setTeacherId] = useState<string>(row ? String(row.teacher.id) : "");
	const [startsAt, setStartsAt] = useState<string>(row?.starts_at ?? "");
	const [typing, setTyping] = useState(false);
	const [date, setDate] = useState(todayIn(zone));
	const [time, setTime] = useState("");
	const [link, setLink] = useState(row?.meeting_url ?? "");
	const [notes, setNotes] = useState(row?.notes ?? "");
	const [warnings, setWarnings] = useState<Warnings | null>(null);
	const create = useCreateRequest();
	const update = useUpdateRequest();
	const act = useRequestAction();
	const pending = create.isPending || update.isPending || act.isPending;
	const error = create.error ?? update.error ?? act.error;
	const errors = error ? formErrors(error, t, INPUTS) : { fields: {} as Record<string, string> };
	const product = products.data?.find((p) => String(p.id) === productId);
	const email_mode = (product?.delivery_mode ?? row?.product.delivery_mode) === "email";
	const teachers = product?.teachers ?? (row ? [row.teacher] : []);
	const editable = mode === "new" || row?.status === "pending_review";

	function start(): string | null {
		if (email_mode) return null;
		if (typing) return time ? zonedInstant(date, time, zone).toISOString() : null;
		return startsAt || null;
	}

	async function submit(e: React.FormEvent) {
		e.preventDefault();
		let answer: WriteAnswer;
		try {
			if (mode === "reschedule" && row) {
				answer = await act.mutateAsync({
					id: row.id,
					action: "reschedule",
					body: { starts_at: start() ?? "", teacher: Number(teacherId) },
				});
			} else {
				const body = {
					name, email, whatsapp, notes, meeting_url: link,
					...(timezone ? { timezone } : {}),
					...(editable
						? { product: Number(productId), teacher: Number(teacherId), starts_at: start() }
						: {}),
				};
				answer = mode === "new"
					? await create.mutateAsync({ ...body, student: student ? Number(student) : null })
					: await update.mutateAsync({ id: (row as ConsultationRequest).id, body });
			}
		} catch {
			return;
		}
		toast.success(t("consultations.dialog.saved"));
		if (hasWarnings(answer.warnings)) setWarnings(answer.warnings);
		else onOpenChange(false);
	}

	const title =
		mode === "new"
			? t("consultations.dialog.newTitle")
			: t(mode === "reschedule" ? "consultations.dialog.rescheduleTitle" : "consultations.dialog.editTitle",
				{ reference: row?.reference });
	const err = (k: string) => errors.fields[k];
	const productName = (p: { name_ar: string; name_en: string }) =>
		i18n.language === "ar" ? p.name_ar : p.name_en;

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent size="lg">
				<DialogTitle>{title}</DialogTitle>
				{warnings ? (
					<div className="flex flex-col gap-3">
						<WarningsList warnings={warnings} zone={zone} />
						<DialogFooter>
							<Button onClick={() => onOpenChange(false)}>{t("consultations.save")}</Button>
						</DialogFooter>
					</div>
				) : (
					<form onSubmit={submit} className="flex flex-col gap-4" noValidate>
						{errors.form ? <FormError>{errors.form}</FormError> : null}
						{mode !== "reschedule" ? (
							<section className="flex flex-col gap-3">
								<h3 className="font-medium">{t("consultations.dialog.sections.person")}</h3>
								{mode === "new" ? (
									<>
										<Input aria-label={t("consultations.dialog.fields.student")}
											placeholder={t("consultations.dialog.fields.student")}
											value={search} onChange={(e) => setSearch(e.target.value)} />
										<Field id="req-student" label={t("consultations.dialog.fields.student")} error={err("student")}>
											<Select value={student} onChange={(e) => setStudent(e.target.value)}>
												<option value="">{t("consultations.dialog.fields.studentNone")}</option>
												{(students.data?.results ?? []).map((s) => (
													<option key={s.id} value={s.id}>{s.user.full_name}</option>
												))}
											</Select>
										</Field>
									</>
								) : null}
								<Field id="req-name" label={t("consultations.dialog.fields.name")} error={err("name")}>
									<Input value={name} onChange={(e) => setName(e.target.value)} />
								</Field>
								<Field id="req-email" label={t("consultations.dialog.fields.email")} error={err("email")}>
									<Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
								</Field>
								<Field id="req-whatsapp" label={t("consultations.dialog.fields.whatsapp")} error={err("whatsapp")}>
									<Input dir="ltr" value={whatsapp} onChange={(e) => setWhatsapp(e.target.value)} />
								</Field>
								<Field id="req-timezone" label={t("consultations.dialog.fields.timezone")} error={err("timezone")}>
									<Select value={timezone} onChange={(e) => setTimezone(e.target.value)}>
										<option value="">{t("consultations.any")}</option>
										{timezoneOptions(timezone || undefined).map((z) => (
											<option key={z} value={z}>{z}</option>
										))}
									</Select>
								</Field>
							</section>
						) : null}
						<section className="flex flex-col gap-3">
							<h3 className="font-medium">{t("consultations.dialog.sections.consultation")}</h3>
							{mode !== "reschedule" ? (
								<Field id="req-product" label={t("consultations.dialog.fields.product")} error={err("product")}>
									<Select value={productId} disabled={!editable}
										onChange={(e) => { setProductId(e.target.value); setTeacherId(""); setStartsAt(""); }}>
										<option value="" />
										{(products.data ?? []).map((p) => (
											<option key={p.id} value={p.id}>{productName(p)}</option>
										))}
									</Select>
								</Field>
							) : null}
							<Field id="req-teacher" label={t("consultations.dialog.fields.teacher")} error={err("teacher")}>
								<Select value={teacherId} disabled={!editable && mode !== "reschedule"}
									onChange={(e) => { setTeacherId(e.target.value); setStartsAt(""); }}>
									<option value="" />
									{teachers.map((x) => (
										<option key={x.id} value={x.id}>{x.full_name}</option>
									))}
								</Select>
							</Field>
							{email_mode || !(editable || mode === "reschedule") ? null : typing ? (
								<>
									<div className="grid gap-3 sm:grid-cols-2">
										<Field id="req-date" label={t("consultations.dialog.fields.date")} error={err("starts_at")}>
											<Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
										</Field>
										<Field id="req-time" label={t("consultations.dialog.fields.time")}>
											<Input type="time" value={time} onChange={(e) => setTime(e.target.value)} />
										</Field>
									</div>
									<Button type="button" variant="outline" size="sm" className="self-start" onClick={() => setTyping(false)}>
										{t("consultations.dialog.slots.pickInstead")}
									</Button>
								</>
							) : (
								<>
									<SlotPicker
										productId={productId ? Number(productId) : undefined}
										teacherId={teacherId ? Number(teacherId) : undefined}
										requestId={row?.id}
										zone={zone}
										from={todayIn(zone)}
										value={startsAt}
										onChange={setStartsAt}
									/>
									{err("starts_at") ? <p className="text-sm text-destructive">{err("starts_at")}</p> : null}
									<Button type="button" variant="outline" size="sm" className="self-start" onClick={() => setTyping(true)}>
										{t("consultations.dialog.slots.typeInstead")}
									</Button>
								</>
							)}
						</section>
						{mode !== "reschedule" ? (
							<section className="flex flex-col gap-3">
								<h3 className="font-medium">{t("consultations.dialog.sections.session")}</h3>
								{!email_mode ? (
									<Field id="req-link" label={t("consultations.dialog.fields.link")} error={err("meeting_url")}>
										<Input type="url" dir="ltr" value={link} onChange={(e) => setLink(e.target.value)} />
									</Field>
								) : null}
								<Field id="req-notes" label={t("consultations.dialog.fields.notes")} error={err("notes")}>
									<Textarea value={notes} maxLength={2000} onChange={(e) => setNotes(e.target.value)} />
								</Field>
							</section>
						) : null}
						{mode === "edit" && row?.payment ? (
							<section className="flex flex-col gap-1">
								<h3 className="font-medium">{t("consultations.dialog.sections.payment")}</h3>
								<p className="text-sm">
									{row.payment.paid_method
										? t("consultations.dialog.paymentDone", {
												amount: formatMoney(row.payment.amount_minor, row.payment.currency, i18n.language),
												date: row.payment.paid_on ? formatDay(row.payment.paid_on, i18n.language) : "",
												method: row.payment.billing_method
													? t(`consultations.billingMethods.${row.payment.billing_method}`)
													: t(`consultations.paid.${row.payment.paid_method}`),
											})
										: t("consultations.dialog.paymentNone")}
									{row.payment.billing_status === "refunded"
										? ` · ${t("consultations.dialog.refunded")}`
										: null}
								</p>
							</section>
						) : null}
						<DialogFooter>
							<Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
								{t("consultations.cancel")}
							</Button>
							<SubmitButton pending={pending}>{t("consultations.save")}</SubmitButton>
						</DialogFooter>
					</form>
				)}
			</DialogContent>
		</Dialog>
	);
}

export function DeliveryDialog({
	row,
	open,
	onOpenChange,
}: {
	row: ConsultationRequest;
	open: boolean;
	onOpenChange: (open: boolean) => void;
}) {
	const { t } = useTranslation();
	const save = useDelivery();
	const email = row.product.delivery_mode === "email";
	const [link, setLink] = useState(row.meeting_url);
	const [studentAtt, setStudentAtt] = useState<string>(row.student_attendance);
	const [teacherAtt, setTeacherAtt] = useState<string>(row.teacher_attendance);
	const [session, setSession] = useState<string>(row.session_status);
	const errors = save.error
		? formErrors(save.error, t, ["meeting_url", "student_attendance", "teacher_attendance", "session_status"])
		: { fields: {} as Record<string, string> };

	async function submit(e: React.FormEvent) {
		e.preventDefault();
		const body = email
			? { meeting_url: link }
			: { meeting_url: link, student_attendance: studentAtt, teacher_attendance: teacherAtt, session_status: session };
		try {
			await save.mutateAsync({ id: row.id, body });
			toast.success(t("consultations.requests.done"));
			onOpenChange(false);
		} catch {
			// Shown below.
		}
	}
	const choose = (id: string, label: string, value: string, set: (v: string) => void, options: readonly string[], prefix: string) => (
		<Field id={id} label={label} error={errors.fields[id.replace("dlv-", "")]}>
			<Select value={value} onChange={(e) => set(e.target.value)}>
				{options.map((o) => <option key={o} value={o}>{t(`${prefix}.${o}`)}</option>)}
			</Select>
		</Field>
	);
	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent>
				<DialogTitle>{t("consultations.dialog.deliveryTitle", { reference: row.reference })}</DialogTitle>
				<form onSubmit={submit} className="flex flex-col gap-3" noValidate>
					{errors.form ? <FormError>{errors.form}</FormError> : null}
					{!email ? (
						<Field id="dlv-meeting_url" label={t("consultations.dialog.fields.link")} error={errors.fields.meeting_url}>
							<Input type="url" dir="ltr" value={link} onChange={(e) => setLink(e.target.value)} />
						</Field>
					) : null}
					{!email ? (
						<>
							{choose("dlv-student_attendance", t("consultations.dialog.fields.studentAttendance"), studentAtt, setStudentAtt, ATTENDANCE, "consultations.attendance")}
							{choose("dlv-teacher_attendance", t("consultations.dialog.fields.teacherAttendance"), teacherAtt, setTeacherAtt, ATTENDANCE, "consultations.attendance")}
							{choose("dlv-session_status", t("consultations.dialog.fields.sessionStatus"), session, setSession, SESSION_STATUSES, "consultations.session")}
						</>
					) : null}
					<DialogFooter>
						<Button type="button" variant="outline" onClick={() => onOpenChange(false)}>{t("consultations.cancel")}</Button>
						<SubmitButton pending={save.isPending}>{t("consultations.save")}</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

`PaymentDialog.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { toMajor, toMinor } from "@/lib/money";
import {
	Button,
	Dialog,
	DialogContent,
	DialogFooter,
	DialogTitle,
	Field,
	FormError,
	Input,
	Select,
	SubmitButton,
	toast,
} from "@/ui";
import { formErrors } from "./errors";
import { useRecordPayment } from "./queries";
import { BILLING_METHODS, type ConsultationRequest } from "./schemas";

const INPUTS = ["billing_method", "amount_minor", "paid_on", "reference", "transaction_number", "student"] as const;

export function PaymentDialog({
	row,
	open,
	onOpenChange,
}: {
	row: ConsultationRequest;
	open: boolean;
	onOpenChange: (open: boolean) => void;
}) {
	const { t } = useTranslation();
	const currency = row.product.currency;
	const [method, setMethod] = useState("cash");
	const [amount, setAmount] = useState(toMajor(row.product.price_minor, currency));
	const [paidOn, setPaidOn] = useState("");
	const [reference, setReference] = useState("");
	const [transaction, setTransaction] = useState("");
	const save = useRecordPayment();
	const errors = save.error ? formErrors(save.error, t, INPUTS) : { fields: {} as Record<string, string> };

	async function submit(e: React.FormEvent) {
		e.preventDefault();
		try {
			await save.mutateAsync({
				id: row.id,
				body: {
					billing_method: method,
					amount_minor: toMinor(amount || "0", currency),
					paid_on: paidOn || null,
					reference,
					transaction_number: transaction,
				},
			});
			toast.success(t("consultations.payment.saved"));
			onOpenChange(false);
		} catch {
			// Shown below.
		}
	}

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent>
				<DialogTitle>{t("consultations.payment.title")}</DialogTitle>
				<form onSubmit={submit} className="flex flex-col gap-3" noValidate>
					{errors.form ? <FormError>{errors.form}</FormError> : null}
					{errors.fields.student ? <FormError>{errors.fields.student}</FormError> : null}
					<Field id="pay-method" label={t("consultations.payment.method")} error={errors.fields.billing_method}>
						<Select value={method} onChange={(e) => setMethod(e.target.value)}>
							{BILLING_METHODS.map((m) => (
								<option key={m} value={m}>{t(`consultations.billingMethods.${m}`)}</option>
							))}
						</Select>
					</Field>
					<p className="text-sm text-muted-foreground">{t("consultations.payment.hint")}</p>
					<Field id="pay-amount" label={t("consultations.payment.amount")} error={errors.fields.amount_minor}>
						<Input inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
					</Field>
					<Field id="pay-paid-on" label={t("consultations.payment.paidOn")} error={errors.fields.paid_on}>
						<Input type="date" value={paidOn} onChange={(e) => setPaidOn(e.target.value)} />
					</Field>
					<Field id="pay-reference" label={t("consultations.payment.reference")} error={errors.fields.reference}>
						<Input value={reference} maxLength={120} onChange={(e) => setReference(e.target.value)} />
					</Field>
					<Field id="pay-transaction" label={t("consultations.payment.transaction")} error={errors.fields.transaction_number}>
						<Input value={transaction} maxLength={120} onChange={(e) => setTransaction(e.target.value)} />
					</Field>
					<DialogFooter>
						<Button type="button" variant="outline" onClick={() => onOpenChange(false)}>{t("consultations.cancel")}</Button>
						<SubmitButton pending={save.isPending}>{t("consultations.save")}</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

The `DeliveryDialog` test expects exactly the four fields in the body for a video request. The `SlotPicker` in `RequestDialog` starts on today's academy date (`todayIn(zone)`); the dialog tests do not assert `from`.

- [ ] **Step 4: Run** — `F pnpm vitest run src/features/consultations` → PASS; `F pnpm tsc --noEmit`; `F pnpm lint`.
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/consultations && git -C dashboard commit -m "feat(consultations): B7c request, delivery and payment dialogs" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 16: Requests page — list, filters, row actions; route and nav (C-6, §4 filters, §5)

**Files:**
- Create: `dashboard/src/features/consultations/time.ts`, `time.test.ts`, `RequestsAdmin.tsx`, `RequestsAdmin.test.tsx`, `NoteDialog.tsx`, `ConfirmButton.tsx`, `dashboard/src/routes/_authed/scheduling.consultations.tsx`
- Modify: `dashboard/src/features/shell/nav.ts` (B7 marker), `features/consultations/index.ts`

**Interfaces:**
- Consumes: `useRequests`, `useProducts`, `useConsultants`, `useRequestAction`, `useDeleteRequest`, `useComplete`, `useAcademySettings` (`@/features/academy`), `wallTime`, `dayIn`, `otherZoneTime` (`@/lib/zoned-time`), `formatMoney`, `useCan`. `RequestDialog`, `DeliveryDialog` and `PaymentDialog` (Task 15) are opened from here.
- Produces: `<RequestsAdmin />`; `formatStart(row, zone, language) -> { academy: string; theirs: string | null } | null` (`time.ts`); `<NoteDialog title, open, onSubmit(note), onOpenChange />`; route `/scheduling/consultations` with `validateSearch` `{ view?: "list" | "calendar" }` (`staticData: { permission: "consultation_request.view_any", feature: "consultations" }`).

- [ ] **Step 1: Write the failing tests**

`time.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { request } from "./fixtures";
import { formatStart } from "./time";

describe("formatStart", () => {
	it("shows the academy clock and the person's when it differs", () => {
		expect(formatStart(request, "UTC", "en")).toEqual({
			academy: "Oct 12, 2026, 16:00",
			theirs: "19:00",
		});
	});
	it("is null without a start", () => {
		expect(formatStart({ ...request, starts_at: null }, "UTC", "en")).toBeNull();
	});
});
```

`RequestsAdmin.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { consultationsApi } from "./api";
import { product, request, writeAnswer } from "./fixtures";
import { RequestsAdmin } from "./RequestsAdmin";

vi.mock("./api", () => ({
	consultationsApi: {
		requests: vi.fn(),
		products: vi.fn(),
		consultants: vi.fn(),
		action: vi.fn(),
		removeRequest: vi.fn(),
		complete: vi.fn(),
	},
}));
vi.mock("@/features/academy/api", () => ({
	academyApi: { get: vi.fn() },
}));

const page = (rows = [request]) => ({ count: rows.length, next: null, previous: null, results: rows });

function show(...codes: string[]) {
	return renderWithRouter(
		<CanProvider me={staffMe(...codes)}>
			<RequestsAdmin />
		</CanProvider>,
	);
}

describe("RequestsAdmin", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(consultationsApi.requests).mockResolvedValue(page());
		vi.mocked(consultationsApi.products).mockResolvedValue([product]);
		vi.mocked(consultationsApi.consultants).mockResolvedValue([
			{ id: 8, full_name: "Ustadh Bilal", offers: true },
		]);
		vi.mocked(consultationsApi.action).mockResolvedValue(writeAnswer);
		vi.mocked(academyApi.get).mockResolvedValue({ timezone: "UTC" } as never);
	});

	it("lists requests with time, status and payment", async () => {
		show("consultation_request.view_any");
		const row = (await screen.findByText("CR-000005")).closest("tr") as HTMLElement;
		expect(within(row).getByText("Yusuf Omar")).toBeInTheDocument();
		expect(within(row).getByText("Placement consultation")).toBeInTheDocument();
		expect(within(row).getByText(/Oct 12, 2026, 16:00/)).toBeInTheDocument();
		expect(within(row).getByText("Under review")).toBeInTheDocument();
		expect(within(row).getByText("Unpaid")).toBeInTheDocument();
	});

	it("sends every CONS-002 filter", async () => {
		const user = userEvent.setup();
		show("consultation_request.view_any");
		await screen.findByText("CR-000005");
		await user.selectOptions(screen.getByLabelText("Consultation"), "3");
		await user.selectOptions(screen.getByLabelText("Teacher"), "8");
		await user.selectOptions(screen.getByLabelText("Status"), "confirmed");
		await user.selectOptions(screen.getByLabelText("Session"), "absent");
		await user.selectOptions(screen.getByLabelText("Student attendance"), "present");
		await user.selectOptions(screen.getByLabelText("Teacher attendance"), "absent");
		await user.selectOptions(screen.getByLabelText("Payment"), "unpaid");
		await user.selectOptions(screen.getByLabelText("Gateway"), "zelle");
		await user.type(screen.getByLabelText("From"), "2026-10-01");
		await user.type(screen.getByLabelText("To"), "2026-10-31");
		await waitFor(() =>
			expect(consultationsApi.requests).toHaveBeenLastCalledWith({
				page: 1,
				product: 3,
				teacher: 8,
				status: "confirmed",
				session_status: "absent",
				student_attendance: "present",
				teacher_attendance: "absent",
				paid_method: "unpaid",
				billing_method: "zelle",
				from: "2026-10-01",
				to: "2026-10-31",
			}),
		);
	});

	it("confirms a pending request and offers only that state's actions", async () => {
		const user = userEvent.setup();
		show("consultation_request.view_any", "consultation_request.update");
		const row = (await screen.findByText("CR-000005")).closest("tr") as HTMLElement;
		expect(within(row).queryByRole("button", { name: "Complete" })).toBeNull();
		await user.click(within(row).getByRole("button", { name: "Confirm" }));
		await waitFor(() =>
			expect(consultationsApi.action).toHaveBeenCalledWith(5, "confirm", undefined),
		);
	});

	it("records a reschedule request with a note", async () => {
		const user = userEvent.setup();
		vi.mocked(consultationsApi.requests).mockResolvedValue(
			page([{ ...request, status: "confirmed" }]),
		);
		show("consultation_request.view_any", "consultation_request.update");
		const row = (await screen.findByText("CR-000005")).closest("tr") as HTMLElement;
		await user.click(within(row).getByRole("button", { name: "Reschedule requested" }));
		await user.type(screen.getByLabelText("Note"), "Travelling");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(consultationsApi.action).toHaveBeenCalledWith(5, "request-reschedule", {
				note: "Travelling",
			}),
		);
	});

	it("hides write actions without the update code", async () => {
		show("consultation_request.view_any");
		const row = (await screen.findByText("CR-000005")).closest("tr") as HTMLElement;
		expect(within(row).queryByRole("button", { name: "Confirm" })).toBeNull();
	});

	it("shows an empty state", async () => {
		vi.mocked(consultationsApi.requests).mockResolvedValue(page([]));
		show("consultation_request.view_any");
		expect(await screen.findByText("No consultation requests.")).toBeInTheDocument();
	});
});
```

(If `academyApi` lives elsewhere, mock the module `useAcademySettings` reads from; check with `grep -n "academyApi" dashboard/src/features/academy/api.ts`.)

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

`time.ts`:

```ts
import { dayIn, otherZoneTime, wallTime } from "@/lib/zoned-time";
import type { ConsultationRequest } from "./schemas";

/** C-4/CONS-002: the start on the academy's clock ("system timezone") and,
 * when it reads differently, on the person's. */
export function formatStart(
	row: Pick<ConsultationRequest, "starts_at" | "timezone">,
	zone: string,
	language: string,
): { academy: string; theirs: string | null } | null {
	if (!row.starts_at) return null;
	const at = new Date(row.starts_at);
	return {
		academy: `${dayIn(at, zone, language)}, ${wallTime(at, zone, language)}`,
		theirs: otherZoneTime(at, row.timezone, zone, language),
	};
}
```

`NoteDialog.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	Button,
	Dialog,
	DialogContent,
	DialogFooter,
	DialogTitle,
	Field,
	SubmitButton,
	Textarea,
} from "@/ui";

export function NoteDialog({
	title,
	open,
	pending,
	onSubmit,
	onOpenChange,
}: {
	title: string;
	open: boolean;
	pending?: boolean;
	onSubmit: (note: string) => void;
	onOpenChange: (open: boolean) => void;
}) {
	const { t } = useTranslation();
	const [note, setNote] = useState("");
	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent>
				<DialogTitle>{title}</DialogTitle>
				<form
					className="flex flex-col gap-3"
					onSubmit={(e) => {
						e.preventDefault();
						onSubmit(note);
					}}
				>
					<Field id="consult-note" label={t("consultations.requests.note")}>
						<Textarea value={note} maxLength={2000} onChange={(e) => setNote(e.target.value)} />
					</Field>
					<DialogFooter>
						<Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
							{t("consultations.cancel")}
						</Button>
						<SubmitButton pending={pending}>{t("consultations.save")}</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

`RequestsAdmin.tsx`:

```tsx
import { MessagesSquare } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy";
import { useCan } from "@/features/identity/permissions";
import { formatMoney } from "@/lib/money";
import {
	Button,
	Card,
	CardContent,
	EmptyState,
	FormError,
	Input,
	Select,
	Spinner,
	StatusChip,
	toast,
} from "@/ui";
import { ConfirmButton } from "./ConfirmButton";
import { consultationsErrorText } from "./errors";
import { NoteDialog } from "./NoteDialog";
import { PaymentDialog } from "./PaymentDialog";
import {
	useComplete,
	useConsultants,
	useDeleteRequest,
	useProducts,
	useRequestAction,
	useRequests,
} from "./queries";
import { DeliveryDialog, RequestDialog } from "./RequestDialog";
import {
	ATTENDANCE,
	BILLING_METHODS,
	type ConsultationRequest,
	REQUEST_STATUSES,
	type RequestAction,
	type RequestFilters,
	SESSION_STATUSES,
} from "./schemas";
import { formatStart } from "./time";

type Open =
	| { kind: "new" }
	| { kind: "edit" | "reschedule" | "delivery" | "payment"; row: ConsultationRequest }
	| { kind: "note"; row: ConsultationRequest; action: "request-reschedule" | "decline-reschedule" };

// @/ui StatusChip has three tones: neutral, live, warning.
const TONE: Record<string, "neutral" | "live" | "warning"> = {
	pending_review: "neutral",
	confirmed: "live",
	reschedule_requested: "neutral",
	completed: "neutral",
	cancelled: "warning",
};

const num = (v: string) => (v ? Number(v) : undefined);

export function RequestsAdmin() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const settings = useAcademySettings();
	const zone = settings.data?.timezone ?? "UTC";
	const [f, setF] = useState<Record<string, string>>({});
	const [page, setPage] = useState(1);
	const [open, setOpen] = useState<Open | null>(null);
	const filters: RequestFilters = {
		page,
		product: num(f.product ?? ""),
		teacher: num(f.teacher ?? ""),
		status: f.status || undefined,
		session_status: f.session_status || undefined,
		student_attendance: f.student_attendance || undefined,
		teacher_attendance: f.teacher_attendance || undefined,
		paid_method: f.paid_method || undefined,
		billing_method: f.billing_method || undefined,
		from: f.from || undefined,
		to: f.to || undefined,
	};
	const list = useRequests(filters);
	const products = useProducts();
	const teachers = useConsultants(false);
	const act = useRequestAction();
	const remove = useDeleteRequest();
	const complete = useComplete();
	const set = (key: string) => (value: string) => {
		setPage(1);
		setF((old) => ({ ...old, [key]: value }));
	};
	const canUpdate = can("consultation_request.update");

	function run(promise: Promise<unknown>) {
		promise
			.then(() => toast.success(t("consultations.requests.done")))
			.catch((error) => toast.error(consultationsErrorText(error, t)));
	}
	const move = (row: ConsultationRequest, action: RequestAction, body?: { note?: string }) =>
		run(act.mutateAsync({ id: row.id, action, body }));

	const select = (key: string, label: string, options: [string, string][]) => (
		<Select aria-label={label} className="w-auto" value={f[key] ?? ""}
			onChange={(e) => set(key)(e.target.value)}>
			<option value="">{t("consultations.any")}</option>
			{options.map(([value, text]) => (
				<option key={value} value={value}>{text}</option>
			))}
		</Select>
	);

	function actions(row: ConsultationRequest) {
		if (!canUpdate) return null;
		const paid = !!row.payment?.paid_method;
		const b = (label: string, onClick: () => void) => (
			<Button key={label} size="sm" variant="outline" onClick={onClick}>{label}</Button>
		);
		const a = (key: string) => t(`consultations.requests.actions.${key}`);
		const out = [];
		if (row.status === "pending_review") {
			out.push(b(a("edit"), () => setOpen({ kind: "edit", row })));
			out.push(b(a("confirm"), () => move(row, "confirm")));
		}
		if (row.status === "confirmed") {
			out.push(b(a("reschedule"), () => setOpen({ kind: "reschedule", row })));
			if (row.product.reschedulable)
				out.push(b(a("requestReschedule"), () =>
					setOpen({ kind: "note", row, action: "request-reschedule" })));
			out.push(b(a("delivery"), () => setOpen({ kind: "delivery", row })));
			out.push(b(a("complete"), () => run(complete.mutateAsync(row.id))));
		}
		if (row.status === "reschedule_requested") {
			out.push(b(a("reschedule"), () => setOpen({ kind: "reschedule", row })));
			out.push(b(a("declineReschedule"), () =>
				setOpen({ kind: "note", row, action: "decline-reschedule" })));
		}
		if (["pending_review", "confirmed", "reschedule_requested"].includes(row.status)) {
			out.push(
				<ConfirmButton key="cancel" label={a("cancel")} title={row.reference}
					description={t("consultations.requests.cancelConfirm")}
					onConfirm={() => move(row, "cancel")} />,
			);
		}
		if (!paid && row.status !== "cancelled" && can("payment.create"))
			out.push(b(a("recordPayment"), () => setOpen({ kind: "payment", row })));
		if (row.status === "pending_review" && !paid && can("consultation_request.delete"))
			out.push(
				<ConfirmButton key="delete" label={a("delete")} title={row.reference}
					description={t("consultations.requests.deleteConfirm")}
					onConfirm={() => run(remove.mutateAsync(row.id))} />,
			);
		return <div className="flex flex-wrap gap-1">{out}</div>;
	}

	const productName = (row: ConsultationRequest) =>
		i18n.language === "ar" ? row.product.name_ar : row.product.name_en;

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-2">
				{select("product", t("consultations.requests.filters.product"),
					(products.data ?? []).map((p) => [String(p.id), i18n.language === "ar" ? p.name_ar : p.name_en]))}
				{select("teacher", t("consultations.requests.filters.teacher"),
					(teachers.data ?? []).map((x) => [String(x.id), x.full_name]))}
				{select("status", t("consultations.requests.filters.status"),
					REQUEST_STATUSES.map((s) => [s, t(`consultations.statuses.${s}`)]))}
				{select("session_status", t("consultations.requests.filters.sessionStatus"),
					SESSION_STATUSES.map((s) => [s, t(`consultations.session.${s}`)]))}
				{select("student_attendance", t("consultations.requests.filters.studentAttendance"),
					ATTENDANCE.map((s) => [s, t(`consultations.attendance.${s}`)]))}
				{select("teacher_attendance", t("consultations.requests.filters.teacherAttendance"),
					ATTENDANCE.map((s) => [s, t(`consultations.attendance.${s}`)]))}
				{select("paid_method", t("consultations.requests.filters.paid"),
					(["manual", "stripe", "paypal", "unpaid"] as const).map((s) => [s, t(`consultations.paid.${s}`)]))}
				{select("billing_method", t("consultations.requests.filters.billingMethod"),
					BILLING_METHODS.map((m) => [m, t(`consultations.billingMethods.${m}`)]))}
				<Input type="date" aria-label={t("consultations.requests.filters.from")} className="w-auto"
					value={f.from ?? ""} onChange={(e) => set("from")(e.target.value)} />
				<Input type="date" aria-label={t("consultations.requests.filters.to")} className="w-auto"
					value={f.to ?? ""} onChange={(e) => set("to")(e.target.value)} />
				{can("consultation_request.create") ? (
					<Button className="ms-auto" onClick={() => setOpen({ kind: "new" })}>
						{t("consultations.requests.add")}
					</Button>
				) : null}
			</div>
			{list.isPending ? (
				<div className="flex justify-center py-6"><Spinner /></div>
			) : list.isError ? (
				<FormError>{consultationsErrorText(list.error, t)}</FormError>
			) : list.data.results.length === 0 ? (
				<Card><CardContent>
					<EmptyState icon={MessagesSquare} title={t("consultations.requests.empty")} />
				</CardContent></Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{(["reference", "person", "product", "teacher", "start", "status", "session", "paid"] as const).map((c) => (
									<th key={c} scope="col" className="p-3 text-start font-medium">
										{t(`consultations.requests.columns.${c}`)}
									</th>
								))}
								<th scope="col" className="p-3"><span className="sr-only">…</span></th>
							</tr>
						</thead>
						<tbody>
							{list.data.results.map((row) => {
								const start = formatStart(row, zone, i18n.language);
								const pay = row.payment;
								return (
									<tr key={row.id} className="border-t border-border align-top">
										<td className="p-3 font-medium">{row.reference}</td>
										<td className="p-3">{row.name}</td>
										<td className="p-3">{productName(row)}</td>
										<td className="p-3">{row.teacher.full_name}</td>
										<td className="p-3">
											{start ? (
												<>
													<div>{start.academy}</div>
													{start.theirs ? (
														<div className="text-muted-foreground">
															{t("consultations.mine.theirTime", { time: start.theirs })}
														</div>
													) : null}
													{row.outside_validity ? (
														<StatusChip tone="warning">{t("consultations.requests.outsideValidity")}</StatusChip>
													) : null}
												</>
											) : (
												t("consultations.requests.noTime")
											)}
										</td>
										<td className="p-3">
											<StatusChip tone={TONE[row.status]}>{t(`consultations.statuses.${row.status}`)}</StatusChip>
										</td>
										<td className="p-3">{t(`consultations.session.${row.session_status}`)}</td>
										<td className="p-3">
											{pay?.paid_method
												? `${formatMoney(pay.amount_minor, pay.currency, i18n.language)} · ${
														pay.billing_method
															? t(`consultations.billingMethods.${pay.billing_method}`)
															: t(`consultations.paid.${pay.paid_method}`)
													}`
												: t("consultations.paid.unpaid")}
										</td>
										<td className="p-3">{actions(row)}</td>
									</tr>
								);
							})}
						</tbody>
					</table>
				</div>
			)}
			{list.data && (list.data.next || list.data.previous) ? (
				<div className="flex justify-end gap-2">
					<Button variant="outline" size="sm" disabled={!list.data.previous}
						onClick={() => setPage((p) => p - 1)}>‹</Button>
					<Button variant="outline" size="sm" disabled={!list.data.next}
						onClick={() => setPage((p) => p + 1)}>›</Button>
				</div>
			) : null}
			{open?.kind === "new" || open?.kind === "edit" || open?.kind === "reschedule" ? (
				<RequestDialog
					mode={open.kind}
					row={open.kind === "new" ? undefined : open.row}
					open
					onOpenChange={(o) => !o && setOpen(null)}
				/>
			) : null}
			{open?.kind === "delivery" ? (
				<DeliveryDialog row={open.row} open onOpenChange={(o) => !o && setOpen(null)} />
			) : null}
			{open?.kind === "payment" ? (
				<PaymentDialog row={open.row} open onOpenChange={(o) => !o && setOpen(null)} />
			) : null}
			{open?.kind === "note" ? (
				<NoteDialog
					title={t(open.action === "request-reschedule"
						? "consultations.requests.actions.requestReschedule"
						: "consultations.requests.actions.declineReschedule")}
					open
					pending={act.isPending}
					onOpenChange={(o) => !o && setOpen(null)}
					onSubmit={(note) => {
						move(open.row, open.action, { note });
						setOpen(null);
					}}
				/>
			) : null}
		</div>
	);
}
```

`ConfirmButton.tsx` (used for cancel and delete):

```tsx
import { useTranslation } from "react-i18next";
import {
	AlertDialog,
	AlertDialogAction,
	AlertDialogCancel,
	AlertDialogContent,
	AlertDialogDescription,
	AlertDialogFooter,
	AlertDialogTitle,
	AlertDialogTrigger,
	Button,
} from "@/ui";

export function ConfirmButton({
	label,
	title,
	description,
	onConfirm,
}: {
	label: string;
	title: string;
	description: string;
	onConfirm: () => void;
}) {
	const { t } = useTranslation();
	return (
		<AlertDialog>
			<AlertDialogTrigger asChild>
				<Button size="sm" variant="outline">{label}</Button>
			</AlertDialogTrigger>
			<AlertDialogContent>
				<AlertDialogTitle>{title}</AlertDialogTitle>
				<AlertDialogDescription>{description}</AlertDialogDescription>
				<AlertDialogFooter>
					<AlertDialogCancel asChild>
						<Button variant="outline">{t("consultations.cancel")}</Button>
					</AlertDialogCancel>
					<AlertDialogAction asChild>
						<Button onClick={onConfirm}>{label}</Button>
					</AlertDialogAction>
				</AlertDialogFooter>
			</AlertDialogContent>
		</AlertDialog>
	);
}
```

Add a test: a pending request's "Cancel request" opens the confirm dialog, and its "Cancel request" button calls `action(5, "cancel", undefined)`.

Route `dashboard/src/routes/_authed/scheduling.consultations.tsx`:

```tsx
import { createFileRoute, Link } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { z } from "zod";
import { usePageTitle } from "@/features/branding";
import { RequestsAdmin } from "@/features/consultations";
import { useCan } from "@/features/identity/permissions";
import { PageHeader } from "@/ui";

// Plan 50 (B7c, spec §5): consultation requests and their calendar.
export const Route = createFileRoute("/_authed/scheduling/consultations")({
	staticData: { permission: "consultation_request.view_any", feature: "consultations" },
	validateSearch: z.object({ view: z.enum(["list", "calendar"]).optional() }),
	component: function ConsultationRequestsRoute() {
		const { t } = useTranslation();
		const can = useCan();
		const { view = "list" } = Route.useSearch();
		usePageTitle(t("consultations.requests.title"));
		const calendar = view === "calendar" && can("consultation_schedule.view_any");
		return (
			<>
				<PageHeader
					title={t("consultations.requests.title")}
					description={t("consultations.requests.subtitle")}
				/>
				{can("consultation_schedule.view_any") ? (
					<nav aria-label={t("consultations.requests.title")} className="flex gap-1 border-b border-border">
						{(["list", "calendar"] as const).map((v) => (
							<Link key={v} to="/scheduling/consultations" search={{ view: v }}
								aria-current={view === v ? "page" : undefined}
								className={view === v ? "border-b-2 border-primary px-3 py-2 font-medium" : "px-3 py-2 text-muted-foreground"}>
								{t(`consultations.requests.tabs.${v}`)}
							</Link>
						))}
					</nav>
				) : null}
				{calendar ? null : <RequestsAdmin />}
			</>
		);
	},
});
```

(Task 17 replaces `{calendar ? null : …}` with `{calendar ? <ScheduleWeek /> : …}`. Match `validateSearch` to the repo's zod usage: `grep -rn validateSearch dashboard/src/routes | head -3`.)

`nav.ts`, under `// ── phase B7 ──` after the products item (import `CalendarClock` from `lucide-react`):

```ts
	office(
		"/scheduling/consultations",
		"consultations.nav.requests",
		CalendarClock,
		"scheduling",
		"consultation_request.view_any",
		"consultations",
	),
```

Regenerate `routeTree.gen.ts`.

- [ ] **Step 4: Run** — `F pnpm vitest run src/features/consultations src/features/shell` → PASS; `F pnpm tsc --noEmit`; `F pnpm lint`.
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/consultations src/routes/_authed/scheduling.consultations.tsx src/features/shell/nav.ts src/routeTree.gen.ts && git -C dashboard commit -m "feat(consultations): B7c requests page" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 17: The calendar tab (C-11)

**Files:**
- Create: `dashboard/src/features/consultations/ScheduleWeek.tsx`, `ScheduleWeek.test.tsx`
- Modify: `dashboard/src/routes/_authed/scheduling.consultations.tsx` (render it for `view=calendar`), `features/consultations/index.ts`

**Interfaces:**
- Consumes: `useSchedule`, `useProducts`, `useConsultants`, `useAcademySettings`, `formatStart`, `addDays`, `todayIn`, `formatDay`.
- Produces: `<ScheduleWeek />`: a week of academy days (Monday first), previous/next/this week, teacher and product filters, each day listing its requests (time, reference, person, consultation, status).

- [ ] **Step 1: Write the failing test** (`ScheduleWeek.test.tsx`)

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { renderWithRouter } from "@/test/render";
import { consultationsApi } from "./api";
import { product, week } from "./fixtures";
import { ScheduleWeek } from "./ScheduleWeek";

vi.mock("./api", () => ({
	consultationsApi: { schedule: vi.fn(), products: vi.fn(), consultants: vi.fn() },
}));
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

describe("ScheduleWeek", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.useFakeTimers({ toFake: ["Date"] });
		vi.setSystemTime(new Date("2026-10-14T10:00:00Z"));
		vi.mocked(academyApi.get).mockResolvedValue({ timezone: "UTC" } as never);
		vi.mocked(consultationsApi.schedule).mockResolvedValue(week);
		vi.mocked(consultationsApi.products).mockResolvedValue([product]);
		vi.mocked(consultationsApi.consultants).mockResolvedValue([
			{ id: 8, full_name: "Ustadh Bilal", offers: true },
		]);
	});

	it("opens on this week and lists each day's requests", async () => {
		renderWithRouter(<ScheduleWeek />);
		expect(await screen.findByText("CR-000005")).toBeInTheDocument();
		expect(consultationsApi.schedule).toHaveBeenCalledWith({ week: "2026-10-12" });
		expect(screen.getAllByRole("listitem")).toHaveLength(1);
		vi.useRealTimers();
	});

	it("moves between weeks and filters", async () => {
		vi.useRealTimers();
		const user = userEvent.setup();
		renderWithRouter(<ScheduleWeek initialWeek="2026-10-12" />);
		await screen.findByText("CR-000005");
		await user.click(screen.getByRole("button", { name: "Next week" }));
		await user.selectOptions(screen.getByLabelText("Teacher"), "8");
		await waitFor(() =>
			expect(consultationsApi.schedule).toHaveBeenLastCalledWith({ week: "2026-10-19", teacher: 8 }),
		);
	});
});
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** `ScheduleWeek.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy";
import { addDays, formatDay, todayIn } from "@/lib/zoned-time";
import { Button, Card, CardContent, Select, Spinner } from "@/ui";
import { useConsultants, useProducts, useSchedule } from "./queries";
import { formatStart } from "./time";

/** Monday of the week holding `day` (YYYY-MM-DD). */
function mondayOf(day: string): string {
	const weekday = (new Date(`${day}T00:00:00Z`).getUTCDay() + 6) % 7;
	return addDays(day, -weekday);
}

export function ScheduleWeek({ initialWeek }: { initialWeek?: string }) {
	const { t, i18n } = useTranslation();
	const zone = useAcademySettings().data?.timezone ?? "UTC";
	const [week, setWeek] = useState(() => initialWeek ?? mondayOf(todayIn(zone)));
	const [teacher, setTeacher] = useState("");
	const [product, setProduct] = useState("");
	const agenda = useSchedule({
		week,
		...(teacher ? { teacher: Number(teacher) } : {}),
		...(product ? { product: Number(product) } : {}),
	});
	const products = useProducts();
	const teachers = useConsultants(false);
	const empty = agenda.data?.days.every((d) => d.requests.length === 0);

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-center gap-2">
				<Button variant="outline" size="sm" onClick={() => setWeek(addDays(week, -7))}>
					{t("consultations.calendar.previous")}
				</Button>
				<span className="font-medium">
					{t("consultations.calendar.weekOf", { date: formatDay(week, i18n.language) })}
				</span>
				<Button variant="outline" size="sm" onClick={() => setWeek(addDays(week, 7))}>
					{t("consultations.calendar.next")}
				</Button>
				<Select aria-label={t("consultations.requests.filters.teacher")} className="w-auto"
					value={teacher} onChange={(e) => setTeacher(e.target.value)}>
					<option value="">{t("consultations.any")}</option>
					{(teachers.data ?? []).map((x) => <option key={x.id} value={x.id}>{x.full_name}</option>)}
				</Select>
				<Select aria-label={t("consultations.requests.filters.product")} className="w-auto"
					value={product} onChange={(e) => setProduct(e.target.value)}>
					<option value="">{t("consultations.any")}</option>
					{(products.data ?? []).map((p) => (
						<option key={p.id} value={p.id}>{i18n.language === "ar" ? p.name_ar : p.name_en}</option>
					))}
				</Select>
			</div>
			{agenda.isPending ? <Spinner /> : null}
			{empty ? <p className="text-muted-foreground">{t("consultations.calendar.empty")}</p> : null}
			<div className="grid gap-3 md:grid-cols-7">
				{agenda.data?.days.map((d) => (
					<Card key={d.day}>
						<CardContent className="flex flex-col gap-2 p-3">
							<h3 className="text-sm font-medium">{formatDay(d.day, i18n.language)}</h3>
							<ul className="flex flex-col gap-2">
								{d.requests.map((r) => {
									const start = formatStart(r, zone, i18n.language);
									return (
										<li key={r.id} className="rounded-md border border-border p-2 text-sm">
											<div className="font-medium">{start?.academy.split(", ").pop()}</div>
											<div>{r.reference}</div>
											<div>{r.name}</div>
											<div className="text-muted-foreground">
												{i18n.language === "ar" ? r.product.name_ar : r.product.name_en} ·{" "}
												{r.teacher.full_name}
											</div>
											<div className="text-muted-foreground">{t(`consultations.statuses.${r.status}`)}</div>
										</li>
									);
								})}
							</ul>
						</CardContent>
					</Card>
				))}
			</div>
		</div>
	);
}
```

`scheduling.consultations.tsx`: import `ScheduleWeek` from `@/features/consultations` and replace `{calendar ? null : <RequestsAdmin />}` with `{calendar ? <ScheduleWeek /> : <RequestsAdmin />}`.

- [ ] **Step 4: Run** — `F pnpm vitest run src/features/consultations` → PASS.
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/consultations src/routes/_authed/scheduling.consultations.tsx && git -C dashboard commit -m "feat(consultations): B7c calendar" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 18: The teacher's "My consultations" (C-8, C-12)

**Files:**
- Create: `dashboard/src/features/consultations/MyConsultations.tsx`, `MyConsultations.test.tsx`, `dashboard/src/routes/_authed/teaching.consultations.tsx`
- Modify: `dashboard/src/features/shell/nav.ts` (B7 marker), `features/consultations/index.ts`

**Interfaces:**
- Consumes: `useRequests` (the server scopes a teacher to their own), `useDelivery`, `useComplete`, `DeliveryDialog`, `formatStart`, `useAcademySettings`.
- Produces: `<MyConsultations />`; route `/teaching/consultations` (`staticData: { feature: "consultations" }`, inside the teacher-only `teaching` layout); nav item for teachers.

- [ ] **Step 1: Write the failing test** (`MyConsultations.test.tsx`)

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { renderWithRouter } from "@/test/render";
import { consultationsApi } from "./api";
import { request, writeAnswer } from "./fixtures";
import { MyConsultations } from "./MyConsultations";

vi.mock("./api", () => ({
	consultationsApi: { requests: vi.fn(), delivery: vi.fn(), complete: vi.fn() },
}));
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const { notes: _n, payment: _p, ...teacherView } = request;

describe("MyConsultations", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue({ timezone: "UTC" } as never);
		vi.mocked(consultationsApi.requests).mockResolvedValue({
			count: 1, next: null, previous: null,
			results: [{ ...teacherView, status: "confirmed", session_status: "completed" }],
		});
		vi.mocked(consultationsApi.complete).mockResolvedValue(writeAnswer);
	});

	it("lists the teacher's consultations with both clocks", async () => {
		renderWithRouter(<MyConsultations />);
		expect(await screen.findByText("Placement consultation")).toBeInTheDocument();
		expect(screen.getByText("Their time: 19:00")).toBeInTheDocument();
		expect(screen.getByRole("link", { name: "https://meet.test/bilal" })).toHaveAttribute(
			"rel", "noopener noreferrer",
		);
	});

	it("completes a delivered consultation", async () => {
		const user = userEvent.setup();
		renderWithRouter(<MyConsultations />);
		await user.click(await screen.findByRole("button", { name: "Complete" }));
		await waitFor(() => expect(consultationsApi.complete).toHaveBeenCalledWith(5));
	});

	it("shows an empty state", async () => {
		vi.mocked(consultationsApi.requests).mockResolvedValue({ count: 0, next: null, previous: null, results: [] });
		renderWithRouter(<MyConsultations />);
		expect(await screen.findByText("No consultations booked with you.")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** `MyConsultations.tsx`:

```tsx
import { MessagesSquare } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy";
import { Button, Card, CardContent, EmptyState, FormError, Spinner, toast } from "@/ui";
import { consultationsErrorText } from "./errors";
import { useComplete, useRequests } from "./queries";
import { DeliveryDialog } from "./RequestDialog";
import type { ConsultationRequest } from "./schemas";
import { formatStart } from "./time";

export function MyConsultations() {
	const { t, i18n } = useTranslation();
	const zone = useAcademySettings().data?.timezone ?? "UTC";
	const [page, setPage] = useState(1);
	const list = useRequests({ page });
	const complete = useComplete();
	const [recording, setRecording] = useState<ConsultationRequest | null>(null);

	if (list.isPending) return <div className="flex justify-center py-6"><Spinner /></div>;
	if (list.isError) return <FormError>{consultationsErrorText(list.error, t)}</FormError>;
	if (list.data.results.length === 0)
		return (
			<Card><CardContent>
				<EmptyState icon={MessagesSquare} title={t("consultations.mine.empty")} />
			</CardContent></Card>
		);

	return (
		<div className="flex flex-col gap-3">
			{list.data.results.map((row) => {
				const start = formatStart(row, zone, i18n.language);
				return (
					<Card key={row.id}>
						<CardContent className="flex flex-col gap-2 p-4">
							<div className="flex flex-wrap items-baseline justify-between gap-2">
								<h3 className="font-medium">
									{i18n.language === "ar" ? row.product.name_ar : row.product.name_en}
								</h3>
								<span className="text-sm text-muted-foreground">
									{row.reference} · {t(`consultations.statuses.${row.status}`)}
								</span>
							</div>
							<div>{row.name}</div>
							{start ? (
								<div className="text-sm">
									{start.academy}
									{start.theirs ? (
										<span className="ms-2 text-muted-foreground">
											{t("consultations.mine.theirTime", { time: start.theirs })}
										</span>
									) : null}
								</div>
							) : null}
							{row.meeting_url ? (
								<a href={row.meeting_url} target="_blank" rel="noopener noreferrer" dir="ltr"
									className="text-sm underline">
									{row.meeting_url}
								</a>
							) : null}
							{row.status === "confirmed" ? (
								<div className="flex flex-wrap gap-2">
									<Button size="sm" variant="outline" onClick={() => setRecording(row)}>
										{t("consultations.requests.actions.delivery")}
									</Button>
									<Button
										size="sm"
										onClick={() =>
											complete.mutate(row.id, {
												onSuccess: () => toast.success(t("consultations.requests.done")),
												onError: (error) => toast.error(consultationsErrorText(error, t)),
											})
										}
									>
										{t("consultations.mine.complete")}
									</Button>
								</div>
							) : null}
						</CardContent>
					</Card>
				);
			})}
			{list.data.next || list.data.previous ? (
				<div className="flex justify-end gap-2">
					<Button variant="outline" size="sm" disabled={!list.data.previous} onClick={() => setPage((p) => p - 1)}>‹</Button>
					<Button variant="outline" size="sm" disabled={!list.data.next} onClick={() => setPage((p) => p + 1)}>›</Button>
				</div>
			) : null}
			{recording ? (
				<DeliveryDialog row={recording} open onOpenChange={(o) => !o && setRecording(null)} />
			) : null}
		</div>
	);
}
```

Route `dashboard/src/routes/_authed/teaching.consultations.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { MyConsultations } from "@/features/consultations";
import { PageHeader } from "@/ui";

// Plan 50 (B7c, spec C-8/C-12): a teacher's own consultations.
export const Route = createFileRoute("/_authed/teaching/consultations")({
	staticData: { feature: "consultations" },
	component: function MyConsultationsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("consultations.mine.title"));
		return (
			<>
				<PageHeader title={t("consultations.mine.title")} description={t("consultations.mine.subtitle")} />
				<MyConsultations />
			</>
		);
	},
});
```

`nav.ts`, under `// ── phase B7 ──` after the two office items:

```ts
	{
		to: "/teaching/consultations",
		labelKey: "consultations.nav.mine",
		icon: MessagesSquare,
		group: "teaching",
		requiresRole: "teacher",
		feature: "consultations",
	},
```

Regenerate `routeTree.gen.ts`.

- [ ] **Step 4: Run** — `F pnpm vitest run src/features/consultations src/features/shell src/test/a11y.test.tsx` → PASS; `F pnpm tsc --noEmit`; `F pnpm lint`.
- [ ] **Step 5: Commit** — `git -C dashboard add src/features/consultations src/routes/_authed/teaching.consultations.tsx src/features/shell/nav.ts src/routeTree.gen.ts && git -C dashboard commit -m "feat(consultations): B7c teacher's consultations" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

Dashboard checkpoint: `F pnpm test:coverage` meets the gates; `src/features/consultations` itself ≥ 80 % lines.

---

### Task 19: e2e journey

**Files:**
- Create: `dashboard/e2e/b7-consultations-office.spec.ts`

**Interfaces:**
- Consumes: `e2e/fixtures.ts` (`DEMO_URL`, `DEMO_ADMIN`, `DEV_PASSWORD`, `expectLoggedIn`, `acceptInvite`), `e2e/manage.ts` (`manage("set_features", "demo", "--on", "consultations", "teacher_availability")`). The demo teacher is Ustadh Bilal (`bilal@demo.test`), with Monday–Thursday 16:00–21:00 windows from the B2 seed.

- [ ] **Step 1: Write the spec** (it fails until the stack runs the B7c build):

```ts
import { type Browser, expect, type Locator, type Page, test } from "@playwright/test";
import { acceptInvite, DEMO_ADMIN, DEMO_URL, DEV_PASSWORD, expectLoggedIn } from "./fixtures";
import { manage } from "./manage";

// Plan 50 (B7c, spec 2026-10-08): the office side of consultations, end to
// end. Names are stamped so a second run on the same database works too.

const TEACHER_EMAIL = "bilal@demo.test";
const TEACHER_NAME = "Ustadh Bilal";
/** Fixed, so a re-run signs in with it and needs no new reset link. */
const TEACHER_PASSWORD = "e2e-Teacher-B7c";

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

async function signInTeacher(browser: Browser): Promise<Page> {
	const context = await browser.newContext();
	const page = await context.newPage();
	await visit(page, `${DEMO_URL}/app/login`, page.getByRole("textbox", { name: /email/i }));
	await page.getByRole("textbox", { name: /email/i }).fill(TEACHER_EMAIL);
	await page.getByRole("textbox", { name: /password/i }).fill(TEACHER_PASSWORD);
	await page.getByRole("button", { name: /sign in/i }).click();
	if (await page.getByText(TEACHER_NAME).first().isVisible({ timeout: 5_000 }).catch(() => false)) {
		return page;
	}
	await context.close();
	const reset = await browser.newContext();
	const resetPage = await reset.newPage();
	await visit(resetPage, `${DEMO_URL}/app/forgot-password`, resetPage.getByRole("textbox", { name: "Email" }));
	await resetPage.getByRole("textbox", { name: "Email" }).fill(TEACHER_EMAIL);
	const requested = Date.now();
	await resetPage.getByRole("button", { name: "Send reset link" }).click();
	await expect(resetPage.getByText("If that account exists, a reset link is on its way.")).toBeVisible();
	await reset.close();
	return acceptInvite(browser, TEACHER_EMAIL, TEACHER_PASSWORD, TEACHER_NAME, { after: requested });
}

test.describe("B7c consultations, office", () => {
	test.beforeAll(() => {
		manage("set_features", "demo", "--on", "consultations", "teacher_availability");
	});

	test("office books a slot, confirms and takes cash; teacher records; office completes", async ({
		page,
		browser,
	}) => {
		test.setTimeout(240_000);
		const stamp = Date.now();
		const productName = `Consultation ${stamp}`;
		const person = `Visitor ${stamp}`;

		await visit(page, `${DEMO_URL}/app/login`, page.getByRole("textbox", { name: /email/i }));
		await page.getByRole("textbox", { name: /email/i }).fill(DEMO_ADMIN);
		await page.getByRole("textbox", { name: /password/i }).fill(DEV_PASSWORD);
		await page.getByRole("button", { name: /sign in/i }).click();
		await expectLoggedIn(page, /demo academy admin/i);
		await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

		// 1. Opt Bilal in from his page (the seed did too; the toggle stays on)
		await visit(page, `${DEMO_URL}/app/people/teachers`, page.getByRole("link", { name: TEACHER_NAME }));
		await page.getByRole("link", { name: TEACHER_NAME }).click();
		const offers = page.getByLabel("Offers consultations");
		await expect(offers).toBeVisible();
		if ((await offers.getAttribute("aria-checked")) !== "true") await offers.click();
		await expect(offers).toHaveAttribute("aria-checked", "true");

		// 2. Create a product
		await visit(page, `${DEMO_URL}/app/catalogue/consultations`, page.getByRole("button", { name: "Add consultation" }));
		await page.getByRole("button", { name: "Add consultation" }).click();
		await page.getByLabel("Name (Arabic)").fill(`استشارة ${stamp}`);
		await page.getByLabel("Name (English)").fill(productName);
		await page.getByLabel("Description (English)").fill("e2e");
		await page.getByLabel("Price").fill("15.00");
		await page.getByRole("tab", { name: "Teachers" }).click();
		await page.getByLabel(TEACHER_NAME).click();
		await page.getByRole("button", { name: "Save" }).click();
		await expect(page.getByText(productName)).toBeVisible();

		// 3. A request on the first free slot
		await visit(page, `${DEMO_URL}/app/scheduling/consultations`, page.getByRole("button", { name: "New request" }));
		await page.getByRole("button", { name: "New request" }).click();
		await page.getByLabel("Name").fill(person);
		await page.getByLabel("Email").fill(`v${stamp}@x.test`);
		await page.getByLabel("WhatsApp").fill("+15550000");
		await page.getByLabel("Consultation").selectOption({ label: productName });
		await page.getByLabel("Teacher").selectOption({ label: TEACHER_NAME });
		await page.getByRole("radio").first().click();
		await page.getByRole("button", { name: "Save" }).click();
		const row = page.getByRole("row").filter({ hasText: person });
		await expect(row).toBeVisible();

		// 4. Confirm, then record a cash payment
		await row.getByRole("button", { name: "Confirm" }).click();
		await expect(row.getByText("Confirmed")).toBeVisible();
		await row.getByRole("button", { name: "Record payment" }).click();
		await page.getByLabel("Payment method").selectOption("cash");
		await page.getByRole("button", { name: "Save" }).click();
		await expect(row.getByText(/\$15\.00 · Cash/)).toBeVisible();

		// 5. Move it into the past so attendance can be recorded: reschedule by typing
		//    yesterday 16:00 on the academy clock (the office may record what happened).
		await row.getByRole("button", { name: "Reschedule" }).click();
		await page.getByRole("button", { name: "Type a time instead" }).click();
		const yesterday = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);
		await page.getByLabel("Date").fill(yesterday);
		await page.getByLabel("Time (academy clock)").fill("16:00");
		await page.getByRole("button", { name: "Save" }).click();
		const close = page.getByRole("button", { name: "Save" });
		if (await close.isVisible().catch(() => false)) await close.click(); // warnings view

		// 6. The teacher records attendance
		const teacherPage = await signInTeacher(browser);
		await visit(teacherPage, `${DEMO_URL}/app/teaching/consultations`, teacherPage.getByText(productName).first());
		const card = teacherPage.locator("div").filter({ hasText: person }).filter({ hasText: productName }).last();
		await card.getByRole("button", { name: "Record attendance" }).click();
		await teacherPage.getByLabel("Student attendance").selectOption("present");
		await teacherPage.getByLabel("Teacher attendance").selectOption("present");
		await teacherPage.getByLabel("Session status").selectOption("completed");
		await teacherPage.getByRole("button", { name: "Save" }).click();
		await teacherPage.context().close();

		// 7. The office completes it
		await page.reload();
		const done = page.getByRole("row").filter({ hasText: person });
		await done.getByRole("button", { name: "Complete" }).click();
		await expect(done.getByText("Completed")).toBeVisible();
	});
});
```

(Check `acceptInvite`'s signature and the login form's labels against `e2e/b6-homework.spec.ts`, which signs a seeded teacher in the same way, and match it exactly.)

- [ ] **Step 2: Run** — `just e2e e2e/b7-consultations-office.spec.ts` against the stream stack (`just dev-backend` up, `just seed` run) → PASS. Then the whole suite: `just e2e`.
- [ ] **Step 3: Commit** — `git -C dashboard add e2e/b7-consultations-office.spec.ts && git -C dashboard commit -m "test(consultations): B7c e2e journey" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 20: Gates, final review and queue

These steps run only once the phase holds a slot (ledger D45). None were run when this plan was written.

- [ ] **Step 1:** `just test` → all green, backend coverage ≥ 80 %, dashboard lines/statements ≥ 80 and branches/functions ≥ 70.
- [ ] **Step 2:** `just lint` → clean, including `lint-imports` with the `etqan.consultations` contract.
- [ ] **Step 3:** `just e2e` (the whole Playwright suite against this stream's stack) → green.
- [ ] **Step 4:** Dispatch a fresh reviewer for the whole slice against the spec (C-1…C-16), the phase spec and this plan. Fix every critical or important finding; log minor ones in `../_ledger/orchestration/phases/B7.md`.
- [ ] **Step 5:** `python3 scripts/orchestration/ledger.py queue B7c`, then follow the merge-queue steps (rebase onto `origin/main` / `origin/master`, regenerate `routeTree.gen.ts`, regenerate the migration on a clash, rerun the gates, push, open the PRs, `ledger.py slice B7c --prs "<urls>"`).
