# Phase C3a — Video Room + Provider Seam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a `Session` a room and let exactly its assigned student and teacher — nobody else, and only inside a time window — obtain a short-lived join URL for it.

**Architecture:** A `Room` row per live session, created lazily on the first join under a per-session lock, behind a `VideoProvider` protocol resolved from settings. `FakeVideoProvider` is the CI and dev default and is a real implementation, so the whole slice ships with genuine unit, component and e2e coverage before any video, signaling, or external service exists. Authorization — participant, status, and window — is the load-bearing part and every branch of it is its own test.

**Tech Stack:** Django 5 + DRF, pytest, React 19 + TanStack Router/Query + Tailwind + shadcn, Vitest + Testing Library, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-05-phase-c3a-video-room-design.md`

## Global Constraints

- **No business logic on models.** Services live in `scheduling/services.py`, `booking.py`, `matching.py`, and the new `rooms.py`. Models are dumb data structures (rule #4).
- **No cross-module model imports.** `scheduling` may call `identity.services`, `curriculum.services`, `billing.services` — never their models. `lint-imports` must stay **10 kept / 0 broken**.
- **Every route under `/api/v1/`**, mounted via `config.api_router` → `kaleem/scheduling/api/urls.py`. Never onto `config/urls.py` (ADR-0029).
- **No bare `except Exception` stringified into a response.** Raise typed `kaleem.platform.exceptions` errors; `kaleem.platform.drf.exception_handler` maps them. `PermissionDeniedError`→403, `ValidationError`→400, `ConflictError`→409, `NotFoundError`→404, `ExternalServiceError`→**502** (rule #8).
- **The API error body is `{"detail": "<message>"}` and carries no machine-readable code field.** Clients branch on HTTP status only.
- **No email addresses in any response payload** (ADR-0023). Use `full_name`.
- **A join URL is a capability:** per-user, short-lived, never persisted on `Session`, never in a list payload, never logged.
- **Coverage floors are ratchets (ADR-0026):** backend `fail_under = 97.3` with **`precision = 1`** in `backend/pyproject.toml` — do not remove that line; dashboard `93 / 89.5 / 86 / 93` in `dashboard/vitest.config.ts`. Raise them if this slice lifts coverage; **lowering needs an ADR**.
- **a11y / i18n / RTL are repo baseline (ADR-0020).** Every user-visible string is an i18n key in both `dashboard/src/locales/en/common.json` and `dashboard/src/locales/ar/common.json`. Style values come from design tokens (semantic utilities) — never hardcoded hex or `color-mix`.
- **Window constants, defined once:** `JOIN_OPENS_BEFORE = dt.timedelta(minutes=10)`, `JOIN_CLOSES_AFTER = dt.timedelta(minutes=15)`.
- **TDD (D3):** failing test first, every task. **Never `--no-verify`.** Backend commits run as `PIP_CONFIG_FILE=/dev/null git commit` (a dead pip proxy otherwise breaks pre-commit).
- **Branch `feat/phase-c3a-video-room`** in `backend` and `dashboard`. Never commit to a trunk.

---

## File Structure

**backend** (`kaleem/scheduling/`)
- `models.py` — **modify**: add `Room`.
- `migrations/0006_room.py` — **create** (generated).
- `providers/__init__.py` — **create**: `RoomRequest`, `ProviderRoom`, `Participant`, `JoinGrant`, the `VideoProvider` `Protocol`, `get_provider()`.
- `providers/fake_provider.py` — **create**: `FakeVideoProvider`, the CI/dev default.
- `rooms.py` — **create**: the service — window constants, `join_window`, `ensure_room`, `join_session`, `end_room_for_session`.
- `api/booking_serializers.py` — **modify**: `JoinGrantSerializer`, plus `can_join_at` on `SessionSerializer`.
- `api/views.py` — **modify**: `SessionJoinView`, `can_join_at` in `_session_payload`.
- `api/urls.py` — **modify**: the `sessions/<id>/join/` route.
- `admin.py` — **modify**: register `Room` read-only.
- `management/commands/seed_e2e_matching.py` — **modify**: seed a session inside the join window.
- `tests/test_room_models.py`, `tests/test_rooms_service.py`, `tests/test_rooms_api.py` — **create**.
- `config/settings/base.py` — **modify**: `VIDEO_PROVIDER`.

**dashboard** (`src/features/booking/`)
- `schemas.ts` — **modify**: `can_join_at` on `sessionSchema`; `joinGrantSchema`.
- `api.ts` — **modify**: `joinSession`; `isOutsideJoinWindowError`, `isVideoUnavailableError`.
- `queries.ts` — **modify**: `useJoinSession`.
- `components/JoinButton.tsx` + `.test.tsx` — **create**.
- `components/SessionList.tsx` — **modify**: render `JoinButton`.
- `src/locales/{en,ar}/common.json` — **modify**.
- `e2e/booking.spec.ts` — **modify**: three flows.

---

### Task 1: The `Room` model

**Files:**
- Modify: `backend/kaleem/scheduling/models.py`
- Create: `backend/kaleem/scheduling/migrations/0006_room.py` (generated)
- Test: `backend/kaleem/scheduling/tests/test_room_models.py`

**Interfaces:**
- Consumes: `Session` from `kaleem.scheduling.models`; the `session`, `slot`, `assignment` fixtures in `kaleem/scheduling/tests/conftest.py`.
- Produces: `Room` with `Room.Status.ACTIVE == "active"`, `Room.Status.ENDED == "ended"`, fields `session`, `provider`, `external_id`, `status`, `created_at`, `ended_at`, and the constraint named `room_one_active_per_session`.

**Context:** `RecurringSlot` in the same file already uses a partial `UniqueConstraint` for "one active X per Y" — copy that shape. `on_delete` here must be `CASCADE`; read the comment above `Session.slot` before choosing anything else.

- [ ] **Step 1: Write the failing tests**

Create `backend/kaleem/scheduling/tests/test_room_models.py`:

```python
import datetime as dt

import pytest
from django.db import IntegrityError
from django.db import transaction
from django.utils import timezone

from kaleem.scheduling.models import Room
from kaleem.scheduling.models import Session

pytestmark = pytest.mark.django_db


@pytest.fixture
def session(assignment, slot):
    return Session.objects.create(
        assignment=assignment,
        slot=slot,
        starts_at=timezone.now() + dt.timedelta(days=1),
        cycle_end=timezone.now() + dt.timedelta(days=30),
    )


def _room(session, **kwargs):
    return Room.objects.create(
        session=session,
        provider="fake",
        external_id=kwargs.pop("external_id", "room_0001"),
        **kwargs,
    )


def test_a_room_defaults_to_active(session):
    assert _room(session).status == Room.Status.ACTIVE


def test_a_session_cannot_have_two_active_rooms(session):
    _room(session)
    with pytest.raises(IntegrityError), transaction.atomic():
        _room(session, external_id="room_0002")


def test_a_session_may_have_a_second_room_once_the_first_ended(session):
    first = _room(session)
    first.status = Room.Status.ENDED
    first.ended_at = timezone.now()
    first.save()

    second = _room(session, external_id="room_0002")

    assert Room.objects.filter(session=session).count() == 2
    assert second.status == Room.Status.ACTIVE


def test_deleting_a_session_deletes_its_rooms(session):
    _room(session)
    session.delete()
    assert not Room.objects.exists()


def test_deleting_a_matched_student_with_a_room_is_allowed(session, student):
    """The C2 regression, extended to the new table: PROTECT here would
    refuse a legitimate cascade from User and break account deletion."""
    _room(session)
    student.delete()
    assert not Room.objects.exists()
```

- [ ] **Step 2: Run them and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_room_models.py -v`
Expected: FAIL — `ImportError: cannot import name 'Room'`.

- [ ] **Step 3: Add the model**

Append to `backend/kaleem/scheduling/models.py`:

```python
class Room(models.Model):
    """A video room for one session.

    A row over time, not a field on Session (rule #7): a provider failure, a
    reconnection, or a rescheduled lesson can each mean a second room for the
    same session. At most one is ACTIVE, enforced by the database rather than
    by a service that remembers to check.

    CASCADE, and deliberately not PROTECT. A Room has no meaning apart from
    its lesson, and Session is itself reachable by cascade from User. PROTECT
    is evaluated per cascade branch and cannot tell an orphaning delete from a
    legitimate same-operation one -- that is exactly what broke account
    deletion for every matched student in C1 and had to be fixed in C2. See
    the comment on Session.slot.
    """

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        ENDED = "ended", "Ended"

    session = models.ForeignKey(
        Session, on_delete=models.CASCADE, related_name="rooms"
    )
    # Which adapter minted it, so a room created under one provider is still
    # readable after the setting changes.
    provider = models.CharField(max_length=50)
    external_id = models.CharField(max_length=255)
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.ACTIVE
    )
    created_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["session", "status"])]
        constraints = [
            # Partial, and conditional on `status` rather than on a nullable
            # `ended_at`: NULLs are distinct in a unique index, so the nullable
            # version would not constrain anything.
            models.UniqueConstraint(
                fields=["session"],
                condition=models.Q(status="active"),
                name="room_one_active_per_session",
            ),
        ]

    def __str__(self):
        return f"Room {self.external_id} ({self.status})"
```

- [ ] **Step 4: Generate and run the migration**

```bash
docker compose -f docker-compose.local.yml exec -T django python manage.py makemigrations scheduling
docker compose -f docker-compose.local.yml exec -T django python manage.py migrate
```
Expected: `0006_room.py` created, migration applies.

- [ ] **Step 5: Run the tests and watch them pass**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_room_models.py -v`
Expected: 5 passed.

- [ ] **Step 6: Commit**

```bash
git add kaleem/scheduling/models.py kaleem/scheduling/migrations/0006_room.py kaleem/scheduling/tests/test_room_models.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): add Room, one active per session"
```

---

### Task 2: The provider seam and `FakeVideoProvider`

**Files:**
- Create: `backend/kaleem/scheduling/providers/__init__.py`
- Create: `backend/kaleem/scheduling/providers/fake_provider.py`
- Modify: `backend/config/settings/base.py`
- Test: `backend/kaleem/scheduling/tests/test_video_providers.py`

**Interfaces:**
- Consumes: nothing from Task 1 — this task is independent of the model.
- Produces, all importable from `kaleem.scheduling.providers`:
  - `RoomRequest(session_id: int, subject_name: str, starts_at: dt.datetime, duration_minutes: int)`
  - `ProviderRoom(external_id: str, provider: str)`
  - `Participant(user_id: int, display_name: str, is_teacher: bool)`
  - `JoinGrant(join_url: str, expires_at: dt.datetime)`
  - `VideoProvider` Protocol: `create_room(request) -> ProviderRoom`, `get_join_url(room, participant, *, expires_at) -> JoinGrant`, `end_room(room) -> None`
  - `get_provider() -> VideoProvider`
  - `FakeVideoProvider` from `kaleem.scheduling.providers.fake_provider`, with class attribute `name = "fake"`.

**Context:** Mirror `kaleem/billing/providers/__init__.py` exactly — frozen dataclasses, a `Protocol`, and a `get_provider()` that resolves `import_string(settings.<SETTING>)`. Read that file first. `Participant` carries `display_name`, never an email (ADR-0023).

- [ ] **Step 1: Write the failing tests**

Create `backend/kaleem/scheduling/tests/test_video_providers.py`:

```python
import datetime as dt

import pytest
from django.test import override_settings
from django.utils import timezone

from kaleem.scheduling.providers import Participant
from kaleem.scheduling.providers import RoomRequest
from kaleem.scheduling.providers import get_provider
from kaleem.scheduling.providers.fake_provider import FakeVideoProvider


@pytest.fixture
def room_request():
    return RoomRequest(
        session_id=42,
        subject_name="Quran",
        starts_at=timezone.now(),
        duration_minutes=60,
    )


def test_the_configured_provider_is_the_fake_by_default():
    assert isinstance(get_provider(), FakeVideoProvider)


@override_settings(
    VIDEO_PROVIDER="kaleem.scheduling.providers.fake_provider.FakeVideoProvider"
)
def test_the_provider_is_resolved_from_settings():
    assert isinstance(get_provider(), FakeVideoProvider)


def test_creating_a_room_is_deterministic_for_a_session(room_request):
    provider = FakeVideoProvider()
    assert provider.create_room(room_request).external_id == "fake-room-42"
    assert provider.create_room(room_request).provider == "fake"


def test_join_urls_differ_per_participant(room_request):
    """A join URL is a per-user capability. Two participants sharing one URL
    would make it a room password instead."""
    provider = FakeVideoProvider()
    room = provider.create_room(room_request)
    expires_at = timezone.now() + dt.timedelta(minutes=30)

    teacher = provider.get_join_url(
        room,
        Participant(user_id=1, display_name="Ustadh", is_teacher=True),
        expires_at=expires_at,
    )
    student = provider.get_join_url(
        room,
        Participant(user_id=2, display_name="Amina", is_teacher=False),
        expires_at=expires_at,
    )

    assert teacher.join_url != student.join_url
    assert teacher.expires_at == expires_at


def test_a_join_url_carries_no_email_and_names_the_room(room_request):
    provider = FakeVideoProvider()
    room = provider.create_room(room_request)
    grant = provider.get_join_url(
        room,
        Participant(user_id=2, display_name="Amina", is_teacher=False),
        expires_at=timezone.now() + dt.timedelta(minutes=30),
    )

    assert room.external_id in grant.join_url
    assert "@" not in grant.join_url


def test_ending_a_room_is_accepted(room_request):
    provider = FakeVideoProvider()
    provider.end_room(provider.create_room(room_request))
```

- [ ] **Step 2: Run them and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_video_providers.py -v`
Expected: FAIL — `ModuleNotFoundError: kaleem.scheduling.providers`.

- [ ] **Step 3: Write the seam**

Create `backend/kaleem/scheduling/providers/__init__.py`:

```python
from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING
from typing import Protocol

from django.conf import settings
from django.utils.module_loading import import_string

if TYPE_CHECKING:
    import datetime as dt


@dataclass(frozen=True)
class RoomRequest:
    """What a provider needs to mint a room. Deliberately not a Session: the
    provider layer never touches an ORM object."""

    session_id: int
    subject_name: str
    starts_at: dt.datetime
    duration_minutes: int


@dataclass(frozen=True)
class ProviderRoom:
    external_id: str
    provider: str


@dataclass(frozen=True)
class Participant:
    """One person's identity as the provider should see it.

    `display_name`, never an email: ADR-0023 keeps addresses out of anything
    outward-facing, and a third party is as outward-facing as it gets.
    """

    user_id: int
    display_name: str
    is_teacher: bool


@dataclass(frozen=True)
class JoinGrant:
    """A capability with an expiry. Never persisted, never logged."""

    join_url: str
    expires_at: dt.datetime


class VideoProvider(Protocol):
    def create_room(self, request: RoomRequest) -> ProviderRoom: ...

    def get_join_url(
        self, room: ProviderRoom, participant: Participant, *, expires_at: dt.datetime
    ) -> JoinGrant: ...

    def end_room(self, room: ProviderRoom) -> None: ...


def get_provider() -> VideoProvider:
    """Instantiate the configured video provider (ADR-0034)."""
    provider_class = import_string(settings.VIDEO_PROVIDER)
    return provider_class()
```

Create `backend/kaleem/scheduling/providers/fake_provider.py`:

```python
"""The default provider everywhere until C3b-C3d build the real one.

A real implementation, not a mock: it mints deterministic ids and per-user,
expiring join URLs, which is what lets C3a have genuine unit, component and
e2e coverage before any signaling, TURN server, or media code exists.
"""

from __future__ import annotations

import hashlib
from typing import TYPE_CHECKING

from kaleem.scheduling.providers import JoinGrant
from kaleem.scheduling.providers import ProviderRoom

if TYPE_CHECKING:
    import datetime as dt

    from kaleem.scheduling.providers import Participant
    from kaleem.scheduling.providers import RoomRequest


class FakeVideoProvider:
    name = "fake"

    def create_room(self, request: RoomRequest) -> ProviderRoom:
        return ProviderRoom(
            external_id=f"fake-room-{request.session_id}", provider=self.name
        )

    def get_join_url(
        self, room: ProviderRoom, participant: Participant, *, expires_at: dt.datetime
    ) -> JoinGrant:
        # Per-participant and per-expiry, so two people in one lesson never
        # share a URL and a stale grant is not indistinguishable from a fresh
        # one. Not a security boundary -- the real provider signs properly --
        # but it keeps the fake honest about the shape it stands in for.
        token = hashlib.sha256(
            f"{room.external_id}:{participant.user_id}:{expires_at.isoformat()}".encode()
        ).hexdigest()[:32]
        return JoinGrant(
            join_url=f"https://video.kaleem.test/{room.external_id}?t={token}",
            expires_at=expires_at,
        )

    def end_room(self, room: ProviderRoom) -> None:
        """Nothing to release: a fake room is a string."""
```

- [ ] **Step 4: Add the setting**

In `backend/config/settings/base.py`, next to `BILLING_PAYMENT_PROVIDER`:

```python
# VIDEO -- the adapter that mints rooms and join URLs (ADR-0034). The fake is
# the default everywhere until C3b-C3d build the real 1-on-1 WebRTC service;
# it is a real implementation, not a mock, so C3a ships fully covered.
VIDEO_PROVIDER = env(
    "VIDEO_PROVIDER",
    default="kaleem.scheduling.providers.fake_provider.FakeVideoProvider",
)
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_video_providers.py -v`
Expected: 6 passed.

- [ ] **Step 6: Verify the boundary linter is still clean**

Run: `docker compose -f docker-compose.local.yml exec -T django lint-imports`
Expected: 10 contracts kept, 0 broken.

- [ ] **Step 7: Commit**

```bash
git add kaleem/scheduling/providers config/settings/base.py kaleem/scheduling/tests/test_video_providers.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): add the video provider seam and FakeVideoProvider"
```

---

### Task 3: The join window

**Files:**
- Create: `backend/kaleem/scheduling/rooms.py`
- Test: `backend/kaleem/scheduling/tests/test_rooms_service.py`

**Interfaces:**
- Consumes: `Session` (Task 1's file, pre-existing model).
- Produces, from `kaleem.scheduling.rooms`: `JOIN_OPENS_BEFORE`, `JOIN_CLOSES_AFTER`, `join_window(session) -> tuple[dt.datetime, dt.datetime]`, `can_join_at(session) -> dt.datetime`.

**Context:** Pure functions, no database writes — this is the piece `_session_payload` will call for every row in a list, so it must not query. `booking.py` in the same package is the style to match.

- [ ] **Step 1: Write the failing tests**

Create `backend/kaleem/scheduling/tests/test_rooms_service.py`:

```python
import datetime as dt

import pytest
from django.utils import timezone

from kaleem.scheduling import rooms
from kaleem.scheduling.models import Session

pytestmark = pytest.mark.django_db


@pytest.fixture
def session(assignment, slot):
    return Session.objects.create(
        assignment=assignment,
        slot=slot,
        starts_at=timezone.now() + dt.timedelta(days=1),
        cycle_end=timezone.now() + dt.timedelta(days=30),
    )


def test_the_window_opens_ten_minutes_before_the_session(session):
    opens, _ = rooms.join_window(session)
    assert opens == session.starts_at - dt.timedelta(minutes=10)


def test_the_window_closes_fifteen_minutes_after_the_session_ends(session):
    _, closes = rooms.join_window(session)
    assert closes == session.starts_at + dt.timedelta(minutes=60 + 15)


def test_the_window_uses_the_rows_own_duration_not_the_constant(session):
    """duration_minutes is a per-row field and a future phase may vary it, so
    a 90-minute lesson must not close at the 60-minute default's boundary."""
    session.duration_minutes = 90
    _, closes = rooms.join_window(session)
    assert closes == session.starts_at + dt.timedelta(minutes=90 + 15)


def test_can_join_at_is_the_opening_bound(session):
    assert rooms.can_join_at(session) == rooms.join_window(session)[0]
```

- [ ] **Step 2: Run them and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_rooms_service.py -v`
Expected: FAIL — `ModuleNotFoundError: kaleem.scheduling.rooms`.

- [ ] **Step 3: Write the window**

Create `backend/kaleem/scheduling/rooms.py`:

```python
"""Video rooms: the lifecycle, and the authorization that guards it.

C3a contains no video. The provider seam stands in for it (ADR-0034), and
everything here is true whether media ends up peer-to-peer, on an SFU, or on
a vendor.
"""

from __future__ import annotations

import datetime as dt

# Chosen, not derived: early enough that a punctual teacher can open the room
# before the student arrives, late enough that a lesson running over is not
# cut off mid-sentence. Defined once, here, so the interface and the guard
# can never disagree about where the boundary is.
JOIN_OPENS_BEFORE = dt.timedelta(minutes=10)
JOIN_CLOSES_AFTER = dt.timedelta(minutes=15)


def join_window(session) -> tuple[dt.datetime, dt.datetime]:
    """When this session's room may be entered. Pure -- no queries: this runs
    once per row when the session list is serialised."""
    ends_at = session.starts_at + dt.timedelta(minutes=session.duration_minutes)
    return session.starts_at - JOIN_OPENS_BEFORE, ends_at + JOIN_CLOSES_AFTER


def can_join_at(session) -> dt.datetime:
    """The instant the window opens. Sent to clients so a countdown runs
    locally instead of polling the join endpoint."""
    return join_window(session)[0]
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_rooms_service.py -v`
Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add kaleem/scheduling/rooms.py kaleem/scheduling/tests/test_rooms_service.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): add the join window"
```

---

### Task 4: `join_session` — authorization and lazy room creation

**Files:**
- Modify: `backend/kaleem/scheduling/rooms.py`
- Test: `backend/kaleem/scheduling/tests/test_rooms_service.py` (append)

**Interfaces:**
- Consumes: `rooms.join_window` (Task 3); `Room` (Task 1); `get_provider`, `RoomRequest`, `Participant` (Task 2); `Session`, `TeacherAssignment` from `kaleem.scheduling.models`.
- Produces: `rooms.join_session(actor, session_id: int, *, now: dt.datetime | None = None) -> JoinGrant`, and `rooms.GRANT_TTL`.

**Context:** Copy `booking._locked_session` for the lock — it already does `select_for_update().select_related("assignment")` and raises `NotFoundError`. **Do not reuse `booking._is_party`**: that helper returns `True` for a parent, and Decision 3 says a parent may not join. Participants here are exactly the assigned student and teacher.

- [ ] **Step 1: Write the failing tests**

Append to `backend/kaleem/scheduling/tests/test_rooms_service.py`:

```python
from kaleem.platform.exceptions import ConflictError
from kaleem.platform.exceptions import ExternalServiceError
from kaleem.platform.exceptions import NotFoundError
from kaleem.platform.exceptions import PermissionDeniedError
from kaleem.scheduling.models import Room


@pytest.fixture
def open_now(session):
    """Move the session so that `timezone.now()` sits inside its window."""
    session.starts_at = timezone.now()
    session.save(update_fields=["starts_at"])
    return session


def test_a_student_inside_the_window_gets_a_grant(open_now, student):
    grant = rooms.join_session(student, open_now.id)
    assert grant.join_url
    assert grant.expires_at > timezone.now()


def test_the_teacher_gets_a_different_url_than_the_student(open_now, student, teacher):
    student_url = rooms.join_session(student, open_now.id).join_url
    teacher_url = rooms.join_session(teacher, open_now.id).join_url
    assert student_url != teacher_url


def test_joining_creates_exactly_one_room_and_reuses_it(open_now, student, teacher):
    rooms.join_session(student, open_now.id)
    rooms.join_session(teacher, open_now.id)
    rooms.join_session(student, open_now.id)
    assert Room.objects.filter(session=open_now).count() == 1


def test_a_parent_may_not_join_their_childs_lesson(open_now, parent):
    """Decision 3. A parent is not a participant, and the permissive default
    is the one that cannot be withdrawn. Deleting this assertion is the only
    way to change that."""
    with pytest.raises(PermissionDeniedError):
        rooms.join_session(parent, open_now.id)


def test_an_unrelated_user_may_not_join(open_now, other_student):
    with pytest.raises(PermissionDeniedError):
        rooms.join_session(other_student, open_now.id)


def test_joining_too_early_is_refused(session, student):
    with pytest.raises(ConflictError):
        rooms.join_session(student, session.id)


def test_joining_too_late_is_refused(open_now, student):
    _, closes = rooms.join_window(open_now)
    with pytest.raises(ConflictError):
        rooms.join_session(student, open_now.id, now=closes + dt.timedelta(seconds=1))


def test_joining_at_the_exact_opening_instant_is_allowed(session, student):
    opens, _ = rooms.join_window(session)
    assert rooms.join_session(student, session.id, now=opens).join_url


def test_joining_a_cancelled_session_is_refused(open_now, student):
    open_now.status = Session.Status.CANCELLED
    open_now.save(update_fields=["status"])
    with pytest.raises(ConflictError):
        rooms.join_session(student, open_now.id)


def test_joining_an_unknown_session_is_a_not_found(student):
    with pytest.raises(NotFoundError):
        rooms.join_session(student, 999_999)


def test_a_provider_failure_leaves_no_room_behind(open_now, student, monkeypatch):
    class BrokenProvider:
        def create_room(self, request):
            message = "boom"
            raise RuntimeError(message)

    monkeypatch.setattr(rooms, "get_provider", BrokenProvider)
    with pytest.raises(ExternalServiceError):
        rooms.join_session(student, open_now.id)
    assert not Room.objects.exists()


def test_an_ended_room_is_replaced_rather_than_reused(open_now, student):
    first = rooms.join_session(student, open_now.id)
    Room.objects.filter(session=open_now).update(
        status=Room.Status.ENDED, ended_at=timezone.now()
    )
    second = rooms.join_session(student, open_now.id)

    assert Room.objects.filter(session=open_now).count() == 2
    assert Room.objects.filter(
        session=open_now, status=Room.Status.ACTIVE
    ).count() == 1
    assert second.join_url and first.join_url
```

- [ ] **Step 2: Run them and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_rooms_service.py -v`
Expected: FAIL — `AttributeError: module 'kaleem.scheduling.rooms' has no attribute 'join_session'`.

- [ ] **Step 3: Implement it**

Append to `backend/kaleem/scheduling/rooms.py` (adding the imports at the top of the file):

```python
import logging

from django.db import transaction
from django.utils import timezone

from kaleem.platform.exceptions import ConflictError
from kaleem.platform.exceptions import ExternalServiceError
from kaleem.platform.exceptions import NotFoundError
from kaleem.platform.exceptions import PermissionDeniedError
from kaleem.scheduling.models import Room
from kaleem.scheduling.models import Session
from kaleem.scheduling.providers import Participant
from kaleem.scheduling.providers import ProviderRoom
from kaleem.scheduling.providers import RoomRequest
from kaleem.scheduling.providers import get_provider

logger = logging.getLogger(__name__)

# How long a minted join URL stays valid. Short, because it is a capability
# that admits its holder to a video call with a child; long enough that a
# reload or a slow connection does not strand someone mid-lesson.
GRANT_TTL = dt.timedelta(minutes=30)


def _participant(actor, assignment) -> Participant:
    """The assigned student and teacher, and nobody else.

    Deliberately NOT booking._is_party, which returns True for a parent:
    a parent may see the schedule but may not enter the lesson (Decision 3).
    """
    if actor.id == assignment.teacher_id:
        return Participant(
            user_id=actor.id, display_name=actor.full_name, is_teacher=True
        )
    if actor.id == assignment.student_id:
        return Participant(
            user_id=actor.id, display_name=actor.full_name, is_teacher=False
        )
    raise PermissionDeniedError("join a session you are not a participant in")


def _ensure_room(session) -> ProviderRoom:
    """Lazily, on first join -- not eagerly for every generated session.

    The row is written only after the provider returns, so an outage leaves
    no room at all rather than a half-created one the next join must reason
    about. The caller holds a lock on the session row, so the partial unique
    index is a backstop here rather than the mechanism.
    """
    existing = Room.objects.filter(
        session=session, status=Room.Status.ACTIVE
    ).first()
    if existing is not None:
        return ProviderRoom(
            external_id=existing.external_id, provider=existing.provider
        )

    provider = get_provider()
    try:
        created = provider.create_room(
            RoomRequest(
                session_id=session.id,
                subject_name=session.assignment.subject.name,
                starts_at=session.starts_at,
                duration_minutes=session.duration_minutes,
            )
        )
    except Exception:
        # Logged with the exception, raised as a typed domain error: the
        # provider's own wording must never reach a client (rule #8).
        logger.exception("video provider failed to create a room for session %s", session.id)
        raise ExternalServiceError("video") from None

    Room.objects.create(
        session=session,
        provider=created.provider,
        external_id=created.external_id,
    )
    return created


@transaction.atomic
def join_session(actor, session_id: int, *, now: dt.datetime | None = None):
    """Authorize `actor` for this session's room and mint them a join URL.

    Locks the session row, so two browsers hitting join at once produce one
    room rather than two.
    """
    now = now or timezone.now()
    session = (
        Session.objects.select_for_update()
        .select_related("assignment", "assignment__subject")
        .filter(id=session_id)
        .first()
    )
    if session is None:
        raise NotFoundError("Session", session_id)

    participant = _participant(actor, session.assignment)

    if session.status != Session.Status.SCHEDULED:
        raise ConflictError("This session is no longer scheduled.")

    opens, closes = join_window(session)
    if now < opens:
        raise ConflictError("This session's room is not open yet.")
    if now > closes:
        raise ConflictError("This session's room has closed.")

    room = _ensure_room(session)
    return get_provider().get_join_url(
        room, participant, expires_at=now + GRANT_TTL
    )
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_rooms_service.py -v`
Expected: 16 passed.

- [ ] **Step 5: Commit**

```bash
git add kaleem/scheduling/rooms.py kaleem/scheduling/tests/test_rooms_service.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): authorize joins and create rooms lazily"
```

---

### Task 5: The `join` endpoint and `can_join_at`

**Files:**
- Modify: `backend/kaleem/scheduling/api/booking_serializers.py`
- Modify: `backend/kaleem/scheduling/api/views.py`
- Modify: `backend/kaleem/scheduling/api/urls.py`
- Modify: `backend/kaleem/scheduling/admin.py`
- Test: `backend/kaleem/scheduling/tests/test_rooms_api.py`

**Interfaces:**
- Consumes: `rooms.join_session`, `rooms.can_join_at` (Tasks 3-4).
- Produces: route name `scheduling:session-join` at `sessions/<int:session_id>/join/`; `can_join_at` on every `SessionSerializer` payload; `JoinGrantSerializer` with `join_url` and `expires_at`.

**Context:** `_session_payload(session, actor, now)` in `api/views.py` builds each row — add the field there, not in the serializer. `SessionCancelView` is the shape to copy for the new view. `POST`, not `GET`: the call may create a room, and a capability-minting endpoint must not be reachable by prefetch or browser history.

- [ ] **Step 1: Write the failing tests**

Create `backend/kaleem/scheduling/tests/test_rooms_api.py`:

```python
import datetime as dt

import pytest
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from kaleem.scheduling.models import Session

pytestmark = pytest.mark.django_db


@pytest.fixture
def session(assignment, slot):
    return Session.objects.create(
        assignment=assignment,
        slot=slot,
        starts_at=timezone.now(),
        cycle_end=timezone.now() + dt.timedelta(days=30),
    )


@pytest.fixture
def client_for():
    def _client(user):
        client = APIClient()
        client.force_authenticate(user=user)
        return client

    return _client


def _join_url(session):
    return reverse("api:scheduling:session-join", args=[session.id])


def test_a_participant_gets_a_join_url(session, student, client_for):
    response = client_for(student).post(_join_url(session))
    assert response.status_code == 200
    assert response.data["join_url"]
    assert response.data["expires_at"]


def test_a_parent_is_refused(session, parent, client_for):
    assert client_for(parent).post(_join_url(session)).status_code == 403


def test_an_unrelated_user_is_refused(session, other_student, client_for):
    assert client_for(other_student).post(_join_url(session)).status_code == 403


def test_joining_outside_the_window_is_a_conflict(session, student, client_for):
    session.starts_at = timezone.now() + dt.timedelta(days=2)
    session.save(update_fields=["starts_at"])
    assert client_for(student).post(_join_url(session)).status_code == 409


def test_joining_a_cancelled_session_is_a_conflict(session, student, client_for):
    session.status = Session.Status.CANCELLED
    session.save(update_fields=["status"])
    assert client_for(student).post(_join_url(session)).status_code == 409


def test_an_unknown_session_is_a_404(student, client_for):
    url = reverse("api:scheduling:session-join", args=[999_999])
    assert client_for(student).post(url).status_code == 404


def test_anonymous_callers_are_rejected(session):
    assert APIClient().post(_join_url(session)).status_code in (401, 403)


def test_the_session_list_carries_can_join_at(session, student, client_for):
    response = client_for(student).get(reverse("api:scheduling:sessions"))
    row = next(item for item in response.data if item["id"] == session.id)
    assert row["can_join_at"]


def test_the_session_list_never_carries_a_join_url(session, student, client_for):
    """A join URL is a capability. It is minted on request, for one person,
    and must never ride along in a list every party can read."""
    response = client_for(student).get(reverse("api:scheduling:sessions"))
    assert "join_url" not in response.data[0]
    assert "join_url" not in str(response.data)
```

- [ ] **Step 2: Run them and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_rooms_api.py -v`
Expected: FAIL — `NoReverseMatch: 'session-join' is not a valid view function or pattern name`.

- [ ] **Step 3: Add the serializer**

In `backend/kaleem/scheduling/api/booking_serializers.py`, add `can_join_at` to `SessionSerializer` after `cancellation_refunds`:

```python
    # The instant this session's room opens. Carries no capability, so it is
    # safe in a list; it exists so a client counts down locally instead of
    # polling the join endpoint.
    can_join_at = serializers.DateTimeField()
```

and append:

```python
class JoinGrantSerializer(serializers.Serializer):
    """Minted per request, for one participant. Never stored, never logged."""

    join_url = serializers.CharField()
    expires_at = serializers.DateTimeField()
```

- [ ] **Step 4: Add the field and the view**

In `backend/kaleem/scheduling/api/views.py`, import `from kaleem.scheduling import rooms` and `from kaleem.scheduling.api.booking_serializers import JoinGrantSerializer`, then add to the dict returned by `_session_payload`:

```python
        "can_join_at": rooms.can_join_at(session),
```

and append the view:

```python
class SessionJoinView(APIView):
    """POST, not GET: this may create a room, and a capability-minting
    endpoint should not be reachable by prefetch, link, or history."""

    permission_classes = [IsAuthenticated]

    def post(self, request, session_id: int):
        grant = rooms.join_session(request.user, session_id)
        return Response(JoinGrantSerializer(grant).data)
```

- [ ] **Step 5: Wire the route**

In `backend/kaleem/scheduling/api/urls.py`, import `SessionJoinView` and add, after `session-complete`:

```python
    path(
        "sessions/<int:session_id>/join/",
        SessionJoinView.as_view(),
        name="session-join",
    ),
```

- [ ] **Step 6: Register `Room` in admin**

In `backend/kaleem/scheduling/admin.py`, following the existing registrations:

```python
@admin.register(Room)
class RoomAdmin(admin.ModelAdmin):
    list_display = ("external_id", "session", "provider", "status", "created_at")
    list_filter = ("status", "provider")
    # Read-only throughout: rooms are minted by the provider, and an
    # admin-edited external_id would point at a room that does not exist.
    readonly_fields = ("session", "provider", "external_id", "status", "created_at", "ended_at")

    def has_add_permission(self, request):
        return False
```

- [ ] **Step 7: Run the tests and watch them pass**

```bash
docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_rooms_api.py -v
docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling tests/test_api_versioning_is_enforced.py -q
```
Expected: 9 passed, then the whole scheduling suite and the versioning test green.

- [ ] **Step 8: Commit**

```bash
git add kaleem/scheduling/api kaleem/scheduling/admin.py kaleem/scheduling/tests/test_rooms_api.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): add POST sessions/<id>/join/ and can_join_at"
```

---

### Task 6: Backend gates green, floor raised

**Files:**
- Modify: `backend/pyproject.toml`

**Interfaces:**
- Consumes: everything from Tasks 1-5.
- Produces: a raised `fail_under`.

- [ ] **Step 1: Run the whole suite with coverage**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest --cov --cov-report=term-missing -q`
Expected: all pass; note the total percentage.

- [ ] **Step 2: Raise the floor**

In `backend/pyproject.toml` under `[tool.coverage.report]`, set `fail_under` to the achieved total rounded **down** to one decimal.

⚠ **Leave `precision = 1` exactly where it is.** coverage.py rounds the total to `precision` decimals before comparing it to `fail_under`; with the default precision of 0 a fractional floor compares `97.28` as `97` and CI goes red for no reason.

- [ ] **Step 3: Run the remaining gates**

```bash
docker compose -f docker-compose.local.yml exec -T django lint-imports
docker compose -f docker-compose.local.yml exec -T django ruff check .
docker compose -f docker-compose.local.yml exec -T django mypy kaleem config
```
Expected: 10 kept / 0 broken; ruff clean; mypy clean. (CI runs ruff and `lint-imports` but not mypy — run it anyway.)

- [ ] **Step 4: Commit**

```bash
git add pyproject.toml
PIP_CONFIG_FILE=/dev/null git commit -m "chore(backend): raise the coverage floor for C3a"
```

---

### Task 7: Dashboard schemas and API client

**Files:**
- Modify: `dashboard/src/features/booking/schemas.ts`
- Modify: `dashboard/src/features/booking/api.ts`
- Modify: `dashboard/src/features/booking/index.ts`
- Test: `dashboard/src/features/booking/schemas.test.ts`, `api.test.ts`, `index.test.ts` (append)

**Interfaces:**
- Consumes: the backend contract from Task 5 — `POST scheduling/sessions/<id>/join/` → `{join_url, expires_at}`; `can_join_at` on each session.
- Produces: `joinGrantSchema`, `JoinGrant`; `can_join_at: string` on `Session`; `bookingApi.joinSession(id)`; `isOutsideJoinWindowError(error)`; `isVideoUnavailableError(error)`.

**Context:** `api.ts` already has `isNoEntitlementError` / `isNoActiveSlotError` reading `error.response?.status` — copy that shape. Everything the route needs is re-exported from `index.ts`; append there too.

- [ ] **Step 1: Write the failing tests**

Append to `dashboard/src/features/booking/schemas.test.ts`:

```ts
import { joinGrantSchema, sessionSchema } from "./schemas";

describe("joinGrantSchema", () => {
	it("accepts a grant", () => {
		expect(
			joinGrantSchema.parse({
				join_url: "https://video.kaleem.test/fake-room-1?t=abc",
				expires_at: "2026-09-05T12:00:00Z",
			}).join_url,
		).toContain("fake-room-1");
	});

	it("rejects a grant with no url", () => {
		expect(() =>
			joinGrantSchema.parse({ expires_at: "2026-09-05T12:00:00Z" }),
		).toThrow();
	});
});

describe("sessionSchema can_join_at", () => {
	it("requires can_join_at", () => {
		expect(() =>
			sessionSchema.parse({
				id: 1,
				starts_at: "2026-09-05T12:00:00Z",
				duration_minutes: 60,
				status: "scheduled",
				subject_name: "Quran",
				teacher_name: "Ustadh",
				student_name: "Amina",
				may_cancel: true,
				cancellation_refunds: true,
			}),
		).toThrow();
	});
});
```

Append to `dashboard/src/features/booking/api.test.ts`:

```ts
import { AxiosError } from "axios";
import { isOutsideJoinWindowError, isVideoUnavailableError } from "./api";

function axiosErrorWithStatus(status: number) {
	const error = new AxiosError("failed");
	// @ts-expect-error -- a minimal response is all these predicates read
	error.response = { status };
	return error;
}

describe("join error predicates", () => {
	it("reads 409 as outside the join window", () => {
		expect(isOutsideJoinWindowError(axiosErrorWithStatus(409))).toBe(true);
		expect(isOutsideJoinWindowError(axiosErrorWithStatus(403))).toBe(false);
	});

	it("reads 502 as the video service being unavailable", () => {
		expect(isVideoUnavailableError(axiosErrorWithStatus(502))).toBe(true);
		expect(isVideoUnavailableError(axiosErrorWithStatus(409))).toBe(false);
	});

	it("does not treat a non-axios error as either", () => {
		expect(isOutsideJoinWindowError(new Error("boom"))).toBe(false);
		expect(isVideoUnavailableError(new Error("boom"))).toBe(false);
	});
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `pnpm vitest run src/features/booking`
Expected: FAIL — `joinGrantSchema` and the predicates are not exported.

- [ ] **Step 3: Implement**

In `dashboard/src/features/booking/schemas.ts`, add to `sessionSchema` after `cancellation_refunds`:

```ts
	// The instant this session's room opens. Drives the countdown locally so
	// the client never has to poll the join endpoint to find out.
	can_join_at: z.string(),
```

and append:

```ts
export const joinGrantSchema = z.object({
	join_url: z.string(),
	expires_at: z.string(),
});

export type JoinGrant = z.infer<typeof joinGrantSchema>;
```

In `dashboard/src/features/booking/api.ts`, add the predicates next to the existing ones:

```ts
// 409 from `join/` means the room is not open yet, or has closed. The API
// error body is `{detail}` with no machine-readable code, so status is all a
// client can branch on -- which is fine, because `can_join_at` is what
// actually drives the UI and a well-behaved client never provokes this.
export function isOutsideJoinWindowError(error: unknown): boolean {
	return isAxiosError(error) && error.response?.status === 409;
}

// 502, not 503: the backend acts as a gateway to the video provider, and the
// provider is what failed. Distinct copy, because "try again in a moment" is
// true here and misleading for a 409.
export function isVideoUnavailableError(error: unknown): boolean {
	return isAxiosError(error) && error.response?.status === 502;
}
```

and to `bookingApi`:

```ts
	joinSession: (id: number) =>
		api
			.post<JoinGrant>(`scheduling/sessions/${id}/join/`)
			.then((r) => r.data),
```

adding `JoinGrant` to the existing `import type { … } from "./schemas"`.

In `dashboard/src/features/booking/index.ts`, re-export `joinGrantSchema`, the `JoinGrant` type, `isOutsideJoinWindowError`, and `isVideoUnavailableError` alongside the existing exports, and append to `index.test.ts` an assertion that each is defined, matching the existing test's style.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `pnpm vitest run src/features/booking`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add src/features/booking
git commit -m "feat(booking): add the join grant schema and API client"
```

---

### Task 8: `useJoinSession`

**Files:**
- Modify: `dashboard/src/features/booking/queries.ts`
- Test: `dashboard/src/features/booking/queries.test.tsx` (append)

**Interfaces:**
- Consumes: `bookingApi.joinSession` (Task 7).
- Produces: `useJoinSession()` — a mutation taking a session id and resolving to a `JoinGrant`.

**Context:** Follow `useCancelSession`'s shape. **No `invalidateQueries` here**: minting a join URL changes no server state a cached query reads — the room is an implementation detail, and `can_join_at` is derived from `starts_at`, which has not moved. Invalidating would be cargo-cult.

- [ ] **Step 1: Write the failing test**

Append to `dashboard/src/features/booking/queries.test.tsx`:

```tsx
import { useJoinSession } from "./queries";

describe("useJoinSession", () => {
	it("returns the grant for a session", async () => {
		vi.spyOn(bookingApi, "joinSession").mockResolvedValue({
			join_url: "https://video.kaleem.test/fake-room-7?t=abc",
			expires_at: "2026-09-05T12:00:00Z",
		});

		const { result } = renderHook(() => useJoinSession(), { wrapper });
		await act(async () => {
			await result.current.mutateAsync(7);
		});

		expect(bookingApi.joinSession).toHaveBeenCalledWith(7);
		expect(result.current.data?.join_url).toContain("fake-room-7");
	});
});
```

(Reuse the file's existing `wrapper`, `renderHook`, `act` and `bookingApi` imports; add only what is missing.)

- [ ] **Step 2: Run it and watch it fail**

Run: `pnpm vitest run src/features/booking/queries.test.tsx`
Expected: FAIL — `useJoinSession is not exported`.

- [ ] **Step 3: Implement**

Append to `dashboard/src/features/booking/queries.ts`:

```ts
// No invalidation: minting a join URL changes nothing any cached query
// reads. The room is an implementation detail, and `can_join_at` derives
// from `starts_at`, which has not moved.
export function useJoinSession() {
	return useMutation({
		mutationFn: (id: number) => bookingApi.joinSession(id),
	});
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `pnpm vitest run src/features/booking/queries.test.tsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/features/booking/queries.ts src/features/booking/queries.test.tsx
git commit -m "feat(booking): add useJoinSession"
```

---

### Task 9: `JoinButton`

**Files:**
- Create: `dashboard/src/features/booking/components/JoinButton.tsx`
- Create: `dashboard/src/features/booking/components/JoinButton.test.tsx`
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`

**Interfaces:**
- Consumes: `useJoinSession` (Task 8), the `Session` type with `can_join_at` (Task 7), `isOutsideJoinWindowError` / `isVideoUnavailableError` (Task 7).
- Produces: `JoinButton({ session }: { session: Session })`.

**Context:** `SessionList.tsx`'s `SessionRow` is the style to follow — `useTranslation`, `@/ui` primitives, `aria-label` naming the subject and date. Every string is an i18n key in **both** locale files. Colours come from semantic token utilities (`text-muted-foreground`, `border-border`), never hex.

**Behaviour:** before `can_join_at` the button is disabled and shows a live countdown, updating every second on an interval cleared on unmount. From `can_join_at` onward it is enabled; clicking mints a grant and opens `join_url` in a new tab via `window.open(url, "_blank", "noopener,noreferrer")`. On failure it renders one of three messages by status — 409, 502, anything else.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/booking/components/JoinButton.test.tsx`:

```tsx
import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { bookingApi } from "../api";
import type { Session } from "../schemas";
import { JoinButton } from "./JoinButton";

function makeSession(overrides: Partial<Session> = {}): Session {
	return {
		id: 1,
		starts_at: "2026-09-05T12:00:00Z",
		duration_minutes: 60,
		status: "scheduled",
		subject_name: "Quran",
		teacher_name: "Ustadh",
		student_name: "Amina",
		may_cancel: true,
		cancellation_refunds: true,
		can_join_at: "2026-09-05T11:50:00Z",
		...overrides,
	};
}

function renderButton(session: Session) {
	const client = new QueryClient({
		defaultOptions: { mutations: { retry: false } },
	});
	return render(
		<QueryClientProvider client={client}>
			<JoinButton session={session} />
		</QueryClientProvider>,
	);
}

function axiosErrorWithStatus(status: number) {
	const error = new AxiosError("failed");
	// @ts-expect-error -- a minimal response is all the predicates read
	error.response = { status };
	return error;
}

beforeEach(() => {
	vi.useFakeTimers({ shouldAdvanceTime: true });
	vi.setSystemTime(new Date("2026-09-05T11:45:00Z"));
});

afterEach(() => {
	vi.useRealTimers();
	vi.restoreAllMocks();
});

it("is disabled before the window opens", () => {
	renderButton(makeSession());
	expect(screen.getByRole("button")).toBeDisabled();
});

it("counts down while the window is closed", () => {
	renderButton(makeSession());
	const before = screen.getByRole("button").textContent;
	act(() => {
		vi.advanceTimersByTime(60_000);
	});
	expect(screen.getByRole("button").textContent).not.toBe(before);
});

it("enables itself once the window opens", () => {
	renderButton(makeSession());
	act(() => {
		vi.advanceTimersByTime(5 * 60_000 + 1_000);
	});
	expect(screen.getByRole("button")).toBeEnabled();
});

it("opens the join url in a new tab", async () => {
	vi.setSystemTime(new Date("2026-09-05T11:55:00Z"));
	const open = vi.spyOn(window, "open").mockReturnValue(null);
	vi.spyOn(bookingApi, "joinSession").mockResolvedValue({
		join_url: "https://video.kaleem.test/fake-room-1?t=abc",
		expires_at: "2026-09-05T12:25:00Z",
	});

	renderButton(makeSession());
	await userEvent.click(screen.getByRole("button"));

	await waitFor(() =>
		expect(open).toHaveBeenCalledWith(
			"https://video.kaleem.test/fake-room-1?t=abc",
			"_blank",
			"noopener,noreferrer",
		),
	);
});

it("says the room is not open on a 409", async () => {
	vi.setSystemTime(new Date("2026-09-05T11:55:00Z"));
	vi.spyOn(bookingApi, "joinSession").mockRejectedValue(
		axiosErrorWithStatus(409),
	);

	renderButton(makeSession());
	await userEvent.click(screen.getByRole("button"));

	expect(await screen.findByText(/not open/i)).toBeInTheDocument();
});

it("says the video service is unavailable on a 502", async () => {
	vi.setSystemTime(new Date("2026-09-05T11:55:00Z"));
	vi.spyOn(bookingApi, "joinSession").mockRejectedValue(
		axiosErrorWithStatus(502),
	);

	renderButton(makeSession());
	await userEvent.click(screen.getByRole("button"));

	expect(await screen.findByText(/unavailable/i)).toBeInTheDocument();
});

it("falls back to a generic message on any other failure", async () => {
	vi.setSystemTime(new Date("2026-09-05T11:55:00Z"));
	vi.spyOn(bookingApi, "joinSession").mockRejectedValue(
		axiosErrorWithStatus(403),
	);

	renderButton(makeSession());
	await userEvent.click(screen.getByRole("button"));

	expect(await screen.findByRole("alert")).toBeInTheDocument();
});

it("renders nothing for a session that is not scheduled", () => {
	const { container } = renderButton(makeSession({ status: "cancelled" }));
	expect(container).toBeEmptyDOMElement();
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `pnpm vitest run src/features/booking/components/JoinButton.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the component**

Create `dashboard/src/features/booking/components/JoinButton.tsx`:

```tsx
import { Video } from "lucide-react";
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription, Button } from "@/ui";
import { isOutsideJoinWindowError, isVideoUnavailableError } from "../api";
import { useJoinSession } from "../queries";
import type { Session } from "../schemas";

function minutesUntil(target: string, now: number): number {
	return Math.max(0, Math.ceil((new Date(target).getTime() - now) / 60_000));
}

export function JoinButton({ session }: { session: Session }) {
	const { t } = useTranslation();
	const join = useJoinSession();
	const [now, setNow] = useState(() => Date.now());
	const [failure, setFailure] = useState<string | null>(null);

	// One-second tick so the countdown is live and the button enables itself
	// at the boundary without a reload. Cleared on unmount -- a list of
	// sessions would otherwise leave one interval running per row.
	useEffect(() => {
		const timer = setInterval(() => setNow(Date.now()), 1_000);
		return () => clearInterval(timer);
	}, []);

	if (session.status !== "scheduled") return null;

	const open = now >= new Date(session.can_join_at).getTime();

	async function handleJoin() {
		setFailure(null);
		try {
			const grant = await join.mutateAsync(session.id);
			// noopener,noreferrer: the room must not get a handle on the
			// dashboard window, and the grant must not leak as a referrer.
			window.open(grant.join_url, "_blank", "noopener,noreferrer");
		} catch (error) {
			if (isOutsideJoinWindowError(error)) {
				setFailure(t("booking.joinNotOpen"));
			} else if (isVideoUnavailableError(error)) {
				setFailure(t("booking.joinUnavailable"));
			} else {
				setFailure(t("booking.joinError"));
			}
		}
	}

	return (
		<>
			<Button
				className="self-start"
				disabled={!open || join.isPending}
				onClick={handleJoin}
				aria-label={t("booking.joinFor", { subject: session.subject_name })}
			>
				<Video aria-hidden="true" className="size-4" />
				{open
					? t("booking.join")
					: t("booking.joinOpensIn", {
							count: minutesUntil(session.can_join_at, now),
						})}
			</Button>
			{failure ? (
				<Alert variant="destructive">
					<AlertDescription>{failure}</AlertDescription>
				</Alert>
			) : null}
		</>
	);
}
```

- [ ] **Step 4: Add the i18n keys**

In `dashboard/src/locales/en/common.json`, inside `booking`:

```json
      "join": "Join lesson",
      "joinFor": "Join the {{subject}} lesson",
      "joinOpensIn": "Opens in {{count}} min",
      "joinNotOpen": "This lesson's room is not open yet.",
      "joinUnavailable": "Video is temporarily unavailable. Please try again in a moment.",
      "joinError": "Could not join the lesson. Please try again."
```

and the Arabic equivalents in `dashboard/src/locales/ar/common.json`:

```json
      "join": "انضم إلى الدرس",
      "joinFor": "انضم إلى درس {{subject}}",
      "joinOpensIn": "يفتح خلال {{count}} دقيقة",
      "joinNotOpen": "لم تُفتح غرفة هذا الدرس بعد.",
      "joinUnavailable": "خدمة الفيديو غير متاحة مؤقتًا. يرجى المحاولة بعد قليل.",
      "joinError": "تعذّر الانضمام إلى الدرس. يرجى المحاولة مرة أخرى."
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `pnpm vitest run src/features/booking/components/JoinButton.test.tsx`
Expected: 8 passed.

- [ ] **Step 6: Commit**

```bash
git add src/features/booking/components src/locales
git commit -m "feat(booking): add JoinButton with a live countdown"
```

---

### Task 10: Wire `JoinButton` into `SessionList`

**Files:**
- Modify: `dashboard/src/features/booking/components/SessionList.tsx`
- Test: `dashboard/src/features/booking/components/SessionList.test.tsx` (append)

**Interfaces:**
- Consumes: `JoinButton` (Task 9).
- Produces: no new exports — `SessionRow` renders a `JoinButton` for every scheduled session.

**Context:** The button belongs to the row, above the cancel control, and renders for **every** viewer role — a teacher joins the same lesson the student does. The API is the authority on who may actually join; the parent's 403 is asserted in Task 5 and again in the e2e flow, not by hiding the control here.

⚠ `SessionList.test.tsx`'s existing session fixtures must gain `can_join_at`, or `sessionSchema`-shaped objects will no longer typecheck.

- [ ] **Step 1: Write the failing test**

Append to `dashboard/src/features/booking/components/SessionList.test.tsx`:

```tsx
it("renders a join control on each scheduled session", async () => {
	// (build the same mocked useSessions state the file's other tests use,
	//  with can_join_at present on each row)
	renderList("student");
	expect(
		await screen.findByRole("button", { name: /join/i }),
	).toBeInTheDocument();
});

it("renders a join control for a teacher too", async () => {
	renderList("teacher");
	expect(
		await screen.findByRole("button", { name: /join/i }),
	).toBeInTheDocument();
});
```

Adapt to the file's existing helpers — reuse its render helper and mock rather than inventing new ones — and add `can_join_at` to every session fixture in the file.

- [ ] **Step 2: Run them and watch them fail**

Run: `pnpm vitest run src/features/booking/components/SessionList.test.tsx`
Expected: FAIL — no button named `/join/i`.

- [ ] **Step 3: Render it**

In `SessionRow`, import `JoinButton` and render it immediately before the `session.may_cancel` block:

```tsx
			<JoinButton session={session} />
```

- [ ] **Step 4: Run them and watch them pass**

Run: `pnpm vitest run src/features/booking`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add src/features/booking/components
git commit -m "feat(booking): show the join control on each session row"
```

---

### Task 11: Seed a joinable session for e2e

**Files:**
- Modify: `backend/kaleem/scheduling/management/commands/seed_e2e_matching.py`

**Interfaces:**
- Consumes: the existing fixture — `e2e.booked@kaleem.test` already assigned, slotted, and with generated sessions.
- Produces: exactly one session for the booked student whose `starts_at` is `now`, so `now` sits inside its join window in any CI timezone.

**Context:** The command is idempotent "in the strong sense" — it converges rather than skipping. Preserve that: reposition a generated session deterministically rather than creating an extra one, or the session count grows on every run.

- [ ] **Step 1: Write the failing test**

Create `backend/kaleem/scheduling/tests/test_seed_e2e_joinable.py`:

```python
import pytest
from django.core.management import call_command
from django.test import override_settings
from django.utils import timezone

from kaleem.scheduling import rooms
from kaleem.scheduling.models import Session

pytestmark = pytest.mark.django_db


@override_settings(DEBUG=True)
def test_the_seed_leaves_one_session_joinable_right_now(e2e_accounts):
    """Playwright cannot wait for a lesson to start, so the fixture has to
    put one inside its own join window."""
    call_command("seed_e2e")
    call_command("seed_e2e_matching")

    now = timezone.now()
    joinable = [
        session
        for session in Session.objects.filter(status=Session.Status.SCHEDULED)
        if rooms.join_window(session)[0] <= now <= rooms.join_window(session)[1]
    ]

    assert len(joinable) == 1
```

If no `e2e_accounts` fixture exists, drop the parameter and call `seed_e2e` alone — it creates the accounts itself.

- [ ] **Step 2: Run it and watch it fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_seed_e2e_joinable.py -v`
Expected: FAIL — 0 joinable sessions.

- [ ] **Step 3: Reposition one session**

After `created = booking.generate_sessions()` in `handle`, add:

```python
            # Playwright cannot wait for a lesson to come round, so the
            # earliest generated session is moved onto `now`, putting it
            # inside its own join window. Repositioned, never added: this
            # command converges rather than accumulating, and an extra row
            # per run would break that.
            joinable = (
                Session.objects.filter(
                    assignment__student=booked_student,
                    status=Session.Status.SCHEDULED,
                )
                .order_by("starts_at")
                .first()
            )
            if joinable is not None:
                joinable.starts_at = timezone.now()
                joinable.save(update_fields=["starts_at"])
```

- [ ] **Step 4: Run it and watch it pass, twice**

```bash
docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_seed_e2e_joinable.py -v
docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling -q
```
Expected: passes, and the scheduling suite stays green. Idempotence is what the second run of the seed inside the test proves.

- [ ] **Step 5: Commit**

```bash
git add kaleem/scheduling/management/commands/seed_e2e_matching.py kaleem/scheduling/tests/test_seed_e2e_joinable.py
PIP_CONFIG_FILE=/dev/null git commit -m "test(scheduling): seed a session inside its join window for e2e"
```

---

### Task 12: e2e flows

**Files:**
- Modify: `dashboard/e2e/booking.spec.ts`

**Interfaces:**
- Consumes: the seeded state from Task 11; `JoinButton` from Tasks 9-10.
- Produces: three new Playwright flows — 30 → 33.

**Context:** Read `e2e/booking.spec.ts` and `e2e/fixtures.ts` first and follow their login helpers exactly. Accounts: `e2e.booked@kaleem.test` (the joinable session), `e2e.teacher@kaleem.test`, and the parent account `seed_e2e` creates. **Do not actually follow the join URL** — the room does not exist until C3b–C3d. Assert the grant was issued, not that a call connected.

- [ ] **Step 1: Write the three flows**

Append to `dashboard/e2e/booking.spec.ts`:

```ts
test("a student can join the lesson that is happening now", async ({ page }) => {
	await loginAs(page, "e2e.booked@kaleem.test");
	await page.goto("/schedule");

	// The seeded session sits inside its join window, so exactly one row's
	// control is enabled while any later rows still count down.
	const join = page.getByRole("button", { name: /join/i }).first();
	await expect(join).toBeEnabled();

	// Assert the grant is issued rather than following it: the room itself
	// does not exist until C3b-C3d build the signaling and media layers.
	const response = page.waitForResponse(
		(r) => r.url().includes("/join/") && r.request().method() === "POST",
	);
	await join.click();
	expect((await response).status()).toBe(200);
});

test("a teacher sees the join control on the same lesson", async ({ page }) => {
	await loginAs(page, "e2e.teacher@kaleem.test");
	await page.goto("/schedule");
	await expect(
		page.getByRole("button", { name: /join/i }).first(),
	).toBeEnabled();
});

test("a future lesson counts down instead of being joinable", async ({ page }) => {
	await loginAs(page, "e2e.booked@kaleem.test");
	await page.goto("/schedule");

	// Every row after the seeded one is a week or more away.
	const later = page.getByRole("button", { name: /join/i }).nth(1);
	await expect(later).toBeDisabled();
});
```

Replace `loginAs` with whatever the file's own helper is called.

- [ ] **Step 2: Run the suite**

```bash
docker compose -f docker-compose.local.yml exec -T django python manage.py seed_e2e
docker compose -f docker-compose.local.yml exec -T django python manage.py seed_e2e_matching
pnpm exec playwright test --workers=1
```
Expected: 33 passed. `--workers=1` matters — the specs share seeded accounts.

- [ ] **Step 3: Prove the flows can fail**

Temporarily change `toBeEnabled()` to `toBeDisabled()` in the first flow and re-run it. It must fail. Revert. A flow that passes against broken code is not coverage.

- [ ] **Step 4: Commit**

```bash
git add e2e/booking.spec.ts
git commit -m "test(e2e): cover joining a lesson, both roles, and the countdown"
```

---

### Task 13: Dashboard gates green, floors raised

**Files:**
- Modify: `dashboard/vitest.config.ts`

**Interfaces:**
- Consumes: everything from Tasks 7-12.
- Produces: raised thresholds.

- [ ] **Step 1: Run the full suite with coverage**

Run: `pnpm vitest run --coverage`
Expected: all pass; note lines / branches / functions / statements.

- [ ] **Step 2: Raise the floors**

In `dashboard/vitest.config.ts`, raise `lines`, `branches`, `functions` and `statements` to the achieved numbers rounded **down**. Never lower one — that needs an ADR (ADR-0026).

- [ ] **Step 3: Run lint and typecheck**

```bash
pnpm biome check .
pnpm tsc --noEmit
```
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add vitest.config.ts
git commit -m "chore(dashboard): raise the coverage floors for C3a"
```

---

### Task 14: Manual browser verification, then ship

**Files:**
- Modify: `STATE.md`, `ISSUES.md`, `CLAUDE.md` (D3 tables), `docs/superpowers/journal/2026-W36.md`
- Modify: `docs/superpowers/specs/2026-09-05-phase-c3a-video-room-design.md` (`status: shipped`)

**Interfaces:**
- Consumes: everything.
- Produces: three PRs — backend, dashboard, meta — in that order.

**Context:** D9. The meta merge **is a staging deploy** (ADR-0028), so it goes last and only with the other two merged. Meta carries docs, CI, and submodule pointers only — never feature code.

- [ ] **Step 1: Click it through in a real browser**

Bring the stack up and sign in at `app.kaleem.localhost` as the booked student (see `reference_dashboard_visual_run`). Confirm: the countdown ticks; the button enables at the boundary; clicking opens a new tab at the fake URL; the teacher sees the same control; a parent sees the schedule with no join control; Arabic renders RTL with the countdown reading correctly.

- [ ] **Step 2: Re-run every gate from a clean state**

```bash
docker compose -f docker-compose.local.yml exec -T django pytest --cov -q
docker compose -f docker-compose.local.yml exec -T django lint-imports
docker compose -f docker-compose.local.yml exec -T django mypy kaleem config
pnpm vitest run --coverage
pnpm exec playwright test --workers=1
```
Expected: all green, both floors satisfied.

- [ ] **Step 3: Push both submodule branches and open their PRs**

```bash
git -C backend push -u origin feat/phase-c3a-video-room
git -C dashboard push -u origin feat/phase-c3a-video-room
```
Open a PR from each into `main`, stating what is and is not covered — **there is no video yet**, and the e2e flows assert a grant is issued, not that a call connects.

- [ ] **Step 4: Update the meta docs**

On a `feat/phase-c3a-video-room` branch in the meta repo: bump both submodule pointers, close the spec (`status: shipped`, `closed: 2026-09-05`), update `STATE.md`, add the booking row's new e2e count and both new floors to the **D3 tables in `CLAUDE.md`**, append a journal entry to `docs/superpowers/journal/2026-W36.md`, and add any `ISSUES.md` entries found along the way. Open the meta PR.

- [ ] **Step 5: Merge in order once every check is green**

backend → dashboard → meta. **The meta merge deploys to staging.** Afterwards, confirm `deploy-staging` succeeded and that `POST /api/v1/scheduling/sessions/1/join/` answers 403 rather than 404 on staging — routes are mounted per-module, so the prefix is `/api/v1/scheduling/`, not `/api/v1/`.

---

## Self-Review

**Spec coverage.** Data model → Task 1. Provider seam and `FakeVideoProvider` → Task 2. Window → Task 3. Authorization, lazy creation, provider failure → Task 4. API delta (`POST join/`, `can_join_at`) → Task 5. Frontend → Tasks 7-10. e2e → Tasks 11-12. Coverage ratchets → Tasks 6 and 13. Manual click-through and D9 → Task 14. Module boundaries are verified in Tasks 2, 6 and 14 (`lint-imports` 10/0).

**Deliberately not built, and why:** `end_room` has no caller in C3a. The provider protocol declares it and `FakeVideoProvider` implements it, because C3b needs the verb and ADR-0011's interface names it — but nothing in this slice ends a room, so no task wires one up. Rooms end when their session is deleted. This is stated here so a reviewer reads it as a scoped decision rather than a gap.

**Type consistency.** `join_session`, `join_window`, `can_join_at`, `JOIN_OPENS_BEFORE`, `JOIN_CLOSES_AFTER`, `GRANT_TTL` are named identically in Tasks 3-5. `Room.Status.ACTIVE`/`ENDED` match between Tasks 1 and 4. `join_url` / `expires_at` match across the backend serializer (Task 5), the zod schema (Task 7) and the component (Task 9). `can_join_at` is added to `_session_payload` (Task 5), `SessionSerializer` (Task 5), `sessionSchema` (Task 7), and the test fixtures in Tasks 9-10.

**Known ordering hazard:** Task 7 adds `can_join_at` to `sessionSchema`, which invalidates every existing session fixture in the dashboard's test files. Task 10 calls this out for `SessionList.test.tsx`; the implementer of Task 7 should expect to fix fixtures in `queries.test.tsx` and `schedule.test.tsx` too, and Task 7's suite run is what surfaces them.
