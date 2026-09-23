# Scheduling Availability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teachers and students set a recurring weekly availability in their own timezone via a Calendly-style per-day editor, stored in a new queryable `scheduling.WeeklyAvailability` table.

**Architecture:** New Django `scheduling` module (Phase B) owns `WeeklyAvailability` + a `/me/availability/` API. `User` gains a `timezone` field (identity). The student's old `StudentProfile.time_preferences` JSON is removed (no data migration — dev DB reset). A shared React `WeeklyAvailabilityEditor` is used on a new teacher `/availability` page and inside the student `/account` prefs card. A tested `to_utc_intervals` service primitive converts a user's weekly local slots to UTC (foundation for future matching).

**Tech Stack:** Django + DRF (session + CSRF), pytest-django, import-linter; React 19 + TanStack Router/Query, `@kaleem/tokens`, react-i18next (en/ar + RTL), vitest + jest-axe + biome.

## Global Constraints

- **TDD, 100% coverage (line + branch)** in every repo; failing test first. (D3, ADR-0021)
- **Module boundaries:** `scheduling` may import `kaleem.platform` and call `kaleem.identity.services`; it must NOT import another module's models. Enforced by import-linter. (D4)
- **Weekday convention:** integer `0..6`, **Saturday-first** — `0=Saturday … 6=Friday`. Matches the dashboard `WEEKDAYS` constant.
- **Time granularity:** 15-minute steps in the UI; `end_time > start_time` always.
- **Timezone:** IANA names validated against `zoneinfo.available_timezones()`; `User.timezone` default `"UTC"`.
- **PUT is full-replace:** the client always submits the complete availability set.
- **No data migration:** dev/staging DB is reset; do not preserve existing `time_preferences`.
- **Auth:** DRF SessionAuthentication + real CSRF; availability endpoints require a student or teacher profile.
- **Frontend baseline:** en/ar parity + full RTL + jest-axe on every component; no hardcoded UI strings; import UI only from `@/ui`.
- **Commits:** backend commits run pre-commit with `PIP_CONFIG_FILE=/dev/null` (dead proxy); never `--no-verify`.
- **Git-flow:** backend work on `feat/scheduling-availability` → PR to `main`; dashboard on `feat/scheduling-availability` → PR to `main`; meta spec/plan/pointer-bumps → PR to `develop`.

---

## File structure

**Backend (`backend/kaleem/scheduling/`):**
- `__init__.py`, `apps.py` — app config
- `models.py` — `WeeklyAvailability`
- `services.py` — `get_availability`, `set_availability`, `merge_ranges`, `validate_timezone`, `to_utc_intervals`
- `admin.py` — register `WeeklyAvailability`
- `api/__init__.py`, `api/serializers.py`, `api/views.py`, `api/urls.py`
- `migrations/0001_initial.py`
- `tests/test_models.py`, `tests/test_services.py`, `tests/test_to_utc.py`, `tests/test_api.py`
- Modify `backend/config/settings/base.py` (LOCAL_APPS), `backend/config/api_router.py` (include), `backend/pyproject.toml` (import-linter contract)
- Modify `backend/kaleem/identity/models.py` (User.timezone, drop StudentProfile.time_preferences), `services.py` (set_timezone; drop time_preferences), `api/views.py` + `api/serializers.py` (student-profile shrinks), plus identity migrations

**Frontend (`dashboard/src/features/scheduling/`):**
- `schemas.ts`, `api.ts`, `queries.ts`
- `components/WeeklyAvailabilityEditor.tsx`, `components/TimezoneBar.tsx`
- `index.ts`
- New route `dashboard/src/routes/_authed/availability.tsx`
- Modify `dashboard/src/features/identity/components/StudentPreferencesCard.tsx` (drop time-slot rows; embed editor; keep gender)
- Modify `dashboard/src/features/shell/nav.ts` (+ `nav.test.ts`), `dashboard/src/locales/{en,ar}/common.json`

---

## Task 1: Scaffold the `scheduling` app

**Files:**
- Create: `backend/kaleem/scheduling/__init__.py`, `backend/kaleem/scheduling/apps.py`, `backend/kaleem/scheduling/migrations/__init__.py`, `backend/kaleem/scheduling/tests/__init__.py`
- Modify: `backend/config/settings/base.py:58` (LOCAL_APPS), `backend/pyproject.toml` (import-linter)

**Interfaces:**
- Produces: a registered Django app `kaleem.scheduling`.

- [ ] **Step 1: Create the app config**

`backend/kaleem/scheduling/apps.py`:
```python
from django.apps import AppConfig


class SchedulingConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "kaleem.scheduling"
```
Create empty `backend/kaleem/scheduling/__init__.py`, `backend/kaleem/scheduling/migrations/__init__.py`, `backend/kaleem/scheduling/tests/__init__.py`.

- [ ] **Step 2: Register in settings**

In `backend/config/settings/base.py`, add to `LOCAL_APPS` (after `"kaleem.identity",`):
```python
    "kaleem.scheduling",
```

- [ ] **Step 3: Add the import-linter contract**

In `backend/pyproject.toml`, append a new contract after the identity one:
```toml
[[tool.importlinter.contracts]]
name = "scheduling imports no business modules except identity"
type = "forbidden"
source_modules = ["kaleem.scheduling"]
# scheduling may import kaleem.platform and call kaleem.identity.services
# (roadmap-stated dependency). All other business siblings are forbidden.
forbidden_modules = [
    "kaleem.billing",
    "kaleem.assessment",
    "kaleem.curriculum",
    "kaleem.content",
    "kaleem.messaging",
    "kaleem.notifications",
    "kaleem.engagement",
    "kaleem.analytics",
]
```

- [ ] **Step 4: Verify the app loads and contracts pass**

Run: `cd backend && python manage.py check && lint-imports`
Expected: system check passes (0 errors); import-linter "Contracts: N kept, 0 broken".

- [ ] **Step 5: Commit**

```bash
cd backend && PIP_CONFIG_FILE=/dev/null git commit -am "feat(scheduling): scaffold module + import-linter contract"
```

---

## Task 2: `WeeklyAvailability` model

**Files:**
- Create: `backend/kaleem/scheduling/models.py`, `backend/kaleem/scheduling/tests/test_models.py`
- Create (generated): `backend/kaleem/scheduling/migrations/0001_initial.py`

**Interfaces:**
- Produces: `WeeklyAvailability(user, weekday, start_time, end_time)` with `weekday` 0..6 Saturday-first; DB constraint `end_time > start_time`.

- [ ] **Step 1: Write the failing test**

`backend/kaleem/scheduling/tests/test_models.py`:
```python
import datetime as dt

import pytest
from django.db import IntegrityError

from kaleem.identity.models import User
from kaleem.scheduling.models import WeeklyAvailability


@pytest.fixture
def user(db):
    return User.objects.create_user(email="t@example.com", password="x")


def test_creates_a_slot(user):
    slot = WeeklyAvailability.objects.create(
        user=user, weekday=0, start_time=dt.time(9, 0), end_time=dt.time(12, 0)
    )
    assert str(slot) == "t@example.com Sat 09:00:00-12:00:00"


def test_rejects_end_before_start(user):
    with pytest.raises(IntegrityError):
        WeeklyAvailability.objects.create(
            user=user, weekday=0, start_time=dt.time(12, 0), end_time=dt.time(9, 0)
        )
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && pytest kaleem/scheduling/tests/test_models.py -v`
Expected: FAIL — `ModuleNotFoundError: kaleem.scheduling.models`.

- [ ] **Step 3: Write the model**

`backend/kaleem/scheduling/models.py`:
```python
from django.conf import settings
from django.db import models

# Saturday-first weekday labels, indices 0..6.
WEEKDAY_LABELS = ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"]


class WeeklyAvailability(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="availability",
    )
    weekday = models.PositiveSmallIntegerField()  # 0=Sat .. 6=Fri
    start_time = models.TimeField()
    end_time = models.TimeField()

    class Meta:
        indexes = [models.Index(fields=["user", "weekday"])]
        constraints = [
            models.CheckConstraint(
                check=models.Q(end_time__gt=models.F("start_time")),
                name="availability_end_after_start",
            ),
        ]

    def __str__(self):
        label = WEEKDAY_LABELS[self.weekday]
        return f"{self.user.email} {label} {self.start_time}-{self.end_time}"
```

- [ ] **Step 4: Make and run the migration, verify tests pass**

Run:
```bash
cd backend && python manage.py makemigrations scheduling && pytest kaleem/scheduling/tests/test_models.py -v
```
Expected: migration `0001_initial.py` created; both tests PASS.

- [ ] **Step 5: Commit**

```bash
cd backend && PIP_CONFIG_FILE=/dev/null git commit -am "feat(scheduling): WeeklyAvailability model + migration"
```

---

## Task 3: `User.timezone` + `identity.services.set_timezone`

**Files:**
- Modify: `backend/kaleem/identity/models.py` (User), `backend/kaleem/identity/services.py`
- Create: `backend/kaleem/identity/tests/test_timezone.py`
- Create (generated): identity migration

**Interfaces:**
- Produces: `User.timezone` (str, default `"UTC"`); `identity.services.set_timezone(user, tz: str) -> None` (validates IANA, saves). Raises `platform.exceptions.ValidationError(field="timezone")` on bad zone.

- [ ] **Step 1: Write the failing test**

`backend/kaleem/identity/tests/test_timezone.py`:
```python
import pytest

from kaleem.identity import services
from kaleem.identity.models import User
from kaleem.platform.exceptions import ValidationError


@pytest.fixture
def user(db):
    return User.objects.create_user(email="t@example.com", password="x")


def test_default_timezone_is_utc(user):
    assert user.timezone == "UTC"


def test_set_timezone_saves_valid_zone(user):
    services.set_timezone(user, "Africa/Cairo")
    user.refresh_from_db()
    assert user.timezone == "Africa/Cairo"


def test_set_timezone_rejects_invalid_zone(user):
    with pytest.raises(ValidationError) as exc:
        services.set_timezone(user, "Mars/Phobos")
    assert exc.value.field == "timezone"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && pytest kaleem/identity/tests/test_timezone.py -v`
Expected: FAIL — `AttributeError`/`User has no field 'timezone'`.

- [ ] **Step 3: Add the field and service**

In `backend/kaleem/identity/models.py`, add to `User` (after `date_joined`):
```python
    timezone = models.CharField(max_length=64, default="UTC")
```

In `backend/kaleem/identity/services.py`, add (top-level import `from zoneinfo import available_timezones`):
```python
def set_timezone(user: User, tz: str) -> None:
    if tz not in available_timezones():
        raise ValidationError("Unknown timezone.", field="timezone")
    user.timezone = tz
    user.save(update_fields=["timezone"])
```
(Use the existing `ValidationError` import in this module; confirm it accepts `field=`.)

- [ ] **Step 4: Migrate and verify**

Run:
```bash
cd backend && python manage.py makemigrations identity && pytest kaleem/identity/tests/test_timezone.py -v
```
Expected: identity migration created; 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd backend && PIP_CONFIG_FILE=/dev/null git commit -am "feat(identity): User.timezone + set_timezone service"
```

---

## Task 4: Remove `StudentProfile.time_preferences`

**Files:**
- Modify: `backend/kaleem/identity/models.py`, `services.py`, `api/views.py`, `api/serializers.py`; affected tests
- Create (generated): identity migration

**Interfaces:**
- Produces: `StudentProfile` with no `time_preferences`; `GET/POST /me/student-profile/` handles only `teacher_gender_preference`.

- [ ] **Step 1: Find every reference**

Run: `cd backend && grep -rn "time_preferences" kaleem/`
You will edit: `models.py` (field), `services.py` (`set_student_profile` param + the child-create flow ~line 134), `api/views.py` (`StudentProfileView.get/post`), `api/serializers.py` (`StudentProfileSerializer`, `StudentProfileResponseSerializer`), and any test asserting it.

- [ ] **Step 2: Update the student-profile API test first (failing)**

In the existing student-profile test (find via `grep -rln "student-profile\|StudentProfile" kaleem/identity/tests/`), change the GET/POST cases so the response/body contain **only** `teacher_gender_preference` (no `time_preferences`). Add an assertion that a posted `time_preferences` key is ignored/absent.

Run: `cd backend && pytest kaleem/identity/tests/ -k student_profile -v`
Expected: FAIL (serializer/view still reference `time_preferences`).

- [ ] **Step 3: Remove the field and all references**

- `models.py`: delete the `time_preferences = models.JSONField(...)` line.
- `services.py`: remove the `time_preferences` parameter from `set_student_profile`; in the child-create flow remove the `time_preferences=preferences.get("time_preferences", [])` argument.
- `api/serializers.py`: remove `time_preferences` from `StudentProfileSerializer` and `StudentProfileResponseSerializer`.
- `api/views.py`: in `StudentProfileView.get`, return only `{"teacher_gender_preference": ...}`; in `post`, pass only `teacher_gender_preference` to the service.

- [ ] **Step 4: Migrate and verify the whole identity suite**

Run:
```bash
cd backend && python manage.py makemigrations identity && pytest kaleem/identity/ -v
```
Expected: removal migration created; identity suite PASS (fix any other test that referenced the field).

- [ ] **Step 5: Commit**

```bash
cd backend && PIP_CONFIG_FILE=/dev/null git commit -am "refactor(identity): drop StudentProfile.time_preferences (moves to scheduling)"
```

---

## Task 5: `scheduling.services` — validate, merge, get/set

**Files:**
- Create: `backend/kaleem/scheduling/services.py`, `backend/kaleem/scheduling/tests/test_services.py`

**Interfaces:**
- Consumes: `WeeklyAvailability` (Task 2); `identity.services.set_timezone` (Task 3).
- Produces:
  - `Slot = TypedDict("Slot", {"weekday": int, "start_time": time, "end_time": time})`
  - `merge_ranges(slots: list[Slot]) -> list[Slot]` — sorts, merges same-day overlapping/adjacent ranges.
  - `get_availability(user) -> list[Slot]` — ordered by weekday, start_time.
  - `set_availability(user, slots: list[Slot], timezone: str | None) -> list[Slot]` — validates, merges, full-replace in a transaction, sets tz via identity. Raises `ValidationError` for `end<=start`/bad weekday.

- [ ] **Step 1: Write failing tests**

`backend/kaleem/scheduling/tests/test_services.py`:
```python
import datetime as dt

import pytest

from kaleem.identity.models import User
from kaleem.platform.exceptions import ValidationError
from kaleem.scheduling import services
from kaleem.scheduling.models import WeeklyAvailability


@pytest.fixture
def user(db):
    return User.objects.create_user(email="t@example.com", password="x")


def S(weekday, a, b):
    h1, m1 = a
    h2, m2 = b
    return {"weekday": weekday, "start_time": dt.time(h1, m1), "end_time": dt.time(h2, m2)}


def test_merge_combines_overlapping_same_day():
    merged = services.merge_ranges([S(0, (9, 0), (11, 0)), S(0, (10, 0), (12, 0))])
    assert merged == [S(0, (9, 0), (12, 0))]


def test_merge_combines_adjacent_same_day():
    merged = services.merge_ranges([S(0, (9, 0), (10, 0)), S(0, (10, 0), (11, 0))])
    assert merged == [S(0, (9, 0), (11, 0))]


def test_merge_keeps_separate_days_and_gaps():
    out = services.merge_ranges([S(1, (9, 0), (10, 0)), S(0, (9, 0), (10, 0)), S(0, (11, 0), (12, 0))])
    assert out == [S(0, (9, 0), (10, 0)), S(0, (11, 0), (12, 0)), S(1, (9, 0), (10, 0))]


def test_set_replaces_and_sets_timezone(user):
    services.set_availability(user, [S(0, (9, 0), (12, 0))], timezone="Africa/Cairo")
    services.set_availability(user, [S(1, (18, 0), (20, 0))], timezone=None)
    user.refresh_from_db()
    assert user.timezone == "Africa/Cairo"
    rows = WeeklyAvailability.objects.filter(user=user).values_list("weekday", flat=True)
    assert list(rows) == [1]  # old Saturday row replaced


def test_set_rejects_end_before_start(user):
    with pytest.raises(ValidationError):
        services.set_availability(user, [S(0, (12, 0), (9, 0))], timezone=None)


def test_set_rejects_bad_weekday(user):
    with pytest.raises(ValidationError):
        services.set_availability(user, [S(7, (9, 0), (10, 0))], timezone=None)


def test_get_returns_ordered_slots(user):
    services.set_availability(user, [S(1, (9, 0), (10, 0)), S(0, (9, 0), (10, 0))], timezone=None)
    assert services.get_availability(user) == [S(0, (9, 0), (10, 0)), S(1, (9, 0), (10, 0))]
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && pytest kaleem/scheduling/tests/test_services.py -v`
Expected: FAIL — service functions missing.

- [ ] **Step 3: Implement the service**

`backend/kaleem/scheduling/services.py`:
```python
from __future__ import annotations

import datetime as dt
from typing import TypedDict

from django.db import transaction

from kaleem.identity import services as identity_services
from kaleem.platform.exceptions import ValidationError
from kaleem.scheduling.models import WeeklyAvailability


class Slot(TypedDict):
    weekday: int
    start_time: dt.time
    end_time: dt.time


def _validate(slots: list[Slot]) -> None:
    for s in slots:
        if not (0 <= s["weekday"] <= 6):
            raise ValidationError("Weekday must be 0..6.", field="slots")
        if s["end_time"] <= s["start_time"]:
            raise ValidationError("End time must be after start time.", field="slots")


def merge_ranges(slots: list[Slot]) -> list[Slot]:
    ordered = sorted(slots, key=lambda s: (s["weekday"], s["start_time"], s["end_time"]))
    out: list[Slot] = []
    for s in ordered:
        if out and out[-1]["weekday"] == s["weekday"] and s["start_time"] <= out[-1]["end_time"]:
            if s["end_time"] > out[-1]["end_time"]:
                out[-1] = {**out[-1], "end_time": s["end_time"]}
        else:
            out.append(dict(s))  # type: ignore[arg-type]
    return out


def get_availability(user) -> list[Slot]:
    rows = WeeklyAvailability.objects.filter(user=user).order_by("weekday", "start_time")
    return [
        {"weekday": r.weekday, "start_time": r.start_time, "end_time": r.end_time}
        for r in rows
    ]


@transaction.atomic
def set_availability(user, slots: list[Slot], timezone: str | None) -> list[Slot]:
    _validate(slots)
    merged = merge_ranges(slots)
    WeeklyAvailability.objects.filter(user=user).delete()
    WeeklyAvailability.objects.bulk_create(
        [
            WeeklyAvailability(
                user=user, weekday=s["weekday"], start_time=s["start_time"], end_time=s["end_time"]
            )
            for s in merged
        ]
    )
    if timezone is not None:
        identity_services.set_timezone(user, timezone)
    return merged
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd backend && pytest kaleem/scheduling/tests/test_services.py -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
cd backend && PIP_CONFIG_FILE=/dev/null git commit -am "feat(scheduling): availability service (merge, get, set)"
```

---

## Task 6: `to_utc_intervals` tz-conversion primitive

**Files:**
- Modify: `backend/kaleem/scheduling/services.py`
- Create: `backend/kaleem/scheduling/tests/test_to_utc.py`

**Interfaces:**
- Consumes: `get_availability`, `User.timezone`.
- Produces: `to_utc_intervals(user, reference_date: date) -> list[tuple[datetime, datetime]]` — each weekly slot resolved on the week containing `reference_date`, converted to UTC; handles weekday wraparound. Returned datetimes are tz-aware UTC.

- [ ] **Step 1: Write failing tests**

`backend/kaleem/scheduling/tests/test_to_utc.py`:
```python
import datetime as dt

import pytest

from kaleem.identity.models import User
from kaleem.scheduling import services


@pytest.fixture
def user(db):
    return User.objects.create_user(email="t@example.com", password="x")


# 2026-06-27 is a Saturday (weekday 0 in our Saturday-first scheme).
REF = dt.date(2026, 6, 27)


def test_converts_cairo_plus3_to_utc(user):
    services.set_availability(user, [
        {"weekday": 0, "start_time": dt.time(9, 0), "end_time": dt.time(12, 0)}
    ], timezone="Africa/Cairo")  # Cairo = UTC+3 (no DST in 2026)
    out = services.to_utc_intervals(user, REF)
    assert out == [
        (dt.datetime(2026, 6, 27, 6, 0, tzinfo=dt.timezone.utc),
         dt.datetime(2026, 6, 27, 9, 0, tzinfo=dt.timezone.utc)),
    ]


def test_weekday_wraps_to_previous_day(user):
    # Sat 01:00 +3 -> Fri 22:00 UTC (previous calendar day)
    services.set_availability(user, [
        {"weekday": 0, "start_time": dt.time(1, 0), "end_time": dt.time(2, 0)}
    ], timezone="Africa/Cairo")
    out = services.to_utc_intervals(user, REF)
    assert out[0][0] == dt.datetime(2026, 6, 26, 22, 0, tzinfo=dt.timezone.utc)
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && pytest kaleem/scheduling/tests/test_to_utc.py -v`
Expected: FAIL — `to_utc_intervals` missing.

- [ ] **Step 3: Implement**

Append to `backend/kaleem/scheduling/services.py` (add `from zoneinfo import ZoneInfo` at top):
```python
# Saturday-first index -> Python date.weekday() where Mon=0..Sun=6.
# Sat=5, Sun=6, Mon=0, Tue=1, Wed=2, Thu=3, Fri=4
_PYWEEKDAY = [5, 6, 0, 1, 2, 3, 4]


def to_utc_intervals(user, reference_date: dt.date) -> list[tuple[dt.datetime, dt.datetime]]:
    tz = ZoneInfo(user.timezone)
    # Anchor to the Saturday on/just-before reference_date.
    ref_py = reference_date.weekday()
    sat_offset = (ref_py - 5) % 7  # days since the week's Saturday
    week_sat = reference_date - dt.timedelta(days=sat_offset)
    out: list[tuple[dt.datetime, dt.datetime]] = []
    for s in get_availability(user):
        day = week_sat + dt.timedelta(days=s["weekday"])
        start_local = dt.datetime.combine(day, s["start_time"], tzinfo=tz)
        end_local = dt.datetime.combine(day, s["end_time"], tzinfo=tz)
        out.append(
            (start_local.astimezone(dt.timezone.utc), end_local.astimezone(dt.timezone.utc))
        )
    return out
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd backend && pytest kaleem/scheduling/tests/test_to_utc.py -v`
Expected: both PASS. (If the wrap test fails, confirm `astimezone` is applied to a tz-aware local datetime.)

- [ ] **Step 5: Commit**

```bash
cd backend && PIP_CONFIG_FILE=/dev/null git commit -am "feat(scheduling): to_utc_intervals tz conversion (weekday wrap)"
```

---

## Task 7: `scheduling` API — GET/PUT `/me/availability/`

**Files:**
- Create: `backend/kaleem/scheduling/api/__init__.py`, `api/serializers.py`, `api/views.py`, `api/urls.py`, `backend/kaleem/scheduling/admin.py`, `backend/kaleem/scheduling/tests/test_api.py`
- Modify: `backend/config/api_router.py`

**Interfaces:**
- Consumes: `services.get_availability/set_availability` (Tasks 5).
- Produces: `GET/PUT /api/v1/scheduling/me/availability/` returning `{"timezone": str, "slots": [{weekday, start_time, end_time}]}` with `HH:MM` time strings.

- [ ] **Step 1: Write failing API tests**

`backend/kaleem/scheduling/tests/test_api.py`:
```python
import pytest
from rest_framework.test import APIClient

from kaleem.identity.models import StudentProfile, User

URL = "/api/v1/scheduling/me/availability/"


@pytest.fixture
def student(db):
    user = User.objects.create_user(email="s@example.com", password="pw12345!")
    StudentProfile.objects.create(user=user)
    return user


@pytest.fixture
def client(student):
    c = APIClient()
    c.force_authenticate(user=student)
    return c


def test_get_empty_returns_timezone_and_no_slots(client):
    resp = client.get(URL)
    assert resp.status_code == 200
    assert resp.json() == {"timezone": "UTC", "slots": []}


def test_put_then_get_roundtrips(client):
    body = {"timezone": "Africa/Cairo",
            "slots": [{"weekday": 0, "start_time": "09:00", "end_time": "12:00"}]}
    assert client.put(URL, body, format="json").status_code == 200
    got = client.get(URL).json()
    assert got["timezone"] == "Africa/Cairo"
    assert got["slots"] == [{"weekday": 0, "start_time": "09:00", "end_time": "12:00"}]


def test_put_rejects_end_before_start(client):
    body = {"timezone": "UTC",
            "slots": [{"weekday": 0, "start_time": "12:00", "end_time": "09:00"}]}
    assert client.put(URL, body, format="json").status_code == 400


def test_requires_student_or_teacher_profile(db):
    plain = User.objects.create_user(email="p@example.com", password="pw12345!")
    c = APIClient()
    c.force_authenticate(user=plain)
    assert c.get(URL).status_code == 403


def test_unauthenticated_rejected():
    assert APIClient().get(URL).status_code in (401, 403)
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && pytest kaleem/scheduling/tests/test_api.py -v`
Expected: FAIL — 404 (route not registered).

- [ ] **Step 3: Serializers**

`backend/kaleem/scheduling/api/serializers.py`:
```python
from rest_framework import serializers


class SlotSerializer(serializers.Serializer):
    weekday = serializers.IntegerField(min_value=0, max_value=6)
    start_time = serializers.TimeField(format="%H:%M", input_formats=["%H:%M", "%H:%M:%S"])
    end_time = serializers.TimeField(format="%H:%M", input_formats=["%H:%M", "%H:%M:%S"])


class AvailabilitySerializer(serializers.Serializer):
    timezone = serializers.CharField(max_length=64)
    slots = SlotSerializer(many=True)
```

- [ ] **Step 4: View + profile gate**

`backend/kaleem/scheduling/api/views.py`:
```python
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from kaleem.identity import services as identity_services
from kaleem.platform.exceptions import PermissionDeniedError
from kaleem.scheduling import services
from kaleem.scheduling.api.serializers import AvailabilitySerializer


def _require_student_or_teacher(user):
    if identity_services.get_student_profile(user.id) is None and \
            identity_services.get_teacher_profile(user.id) is None:
        raise PermissionDeniedError("A student or teacher profile is required.")


def _payload(user):
    return {
        "timezone": user.timezone,
        "slots": [
            {"weekday": s["weekday"],
             "start_time": s["start_time"].strftime("%H:%M"),
             "end_time": s["end_time"].strftime("%H:%M")}
            for s in services.get_availability(user)
        ],
    }


class AvailabilityView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        _require_student_or_teacher(request.user)
        return Response(_payload(request.user))

    def put(self, request):
        _require_student_or_teacher(request.user)
        serializer = AvailabilitySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        services.set_availability(
            request.user, list(data["slots"]), timezone=data["timezone"]
        )
        return Response(_payload(request.user))
```
(The `services.set_availability` raises `ValidationError` for end<=start → mapped to 400 by `platform.drf.exception_handler`; `PermissionDeniedError` → 403.)

- [ ] **Step 5: URLs + register + admin**

`backend/kaleem/scheduling/api/urls.py`:
```python
from django.urls import path

from kaleem.scheduling.api.views import AvailabilityView

app_name = "scheduling"
urlpatterns = [
    path("me/availability/", AvailabilityView.as_view(), name="availability"),
]
```
In `backend/config/api_router.py`, add inside `urlpatterns` (next to the identity include):
```python
    path("scheduling/", include("kaleem.scheduling.api.urls")),
```
`backend/kaleem/scheduling/admin.py`:
```python
from django.contrib import admin

from kaleem.scheduling.models import WeeklyAvailability

admin.site.register(WeeklyAvailability)
```

- [ ] **Step 6: Run the full backend gate**

Run:
```bash
cd backend && pytest kaleem/scheduling/ -v && lint-imports && ruff check kaleem/scheduling && mypy kaleem/scheduling
```
Expected: all scheduling tests PASS; import-linter kept; ruff/mypy clean.

- [ ] **Step 7: Commit + open backend PR**

```bash
cd backend && PIP_CONFIG_FILE=/dev/null git commit -am "feat(scheduling): GET/PUT me/availability API"
git push -u origin feat/scheduling-availability
gh pr create --repo kaleem-lms/backend --base main --head feat/scheduling-availability \
  --title "feat(scheduling): weekly availability module + tz" --body "Implements the scheduling-availability spec (backend)."
```

---

## Task 8: Dashboard data layer (`features/scheduling`)

**Files:**
- Create: `dashboard/src/features/scheduling/schemas.ts`, `api.ts`, `queries.ts`, `index.ts`
- Create: `dashboard/src/features/scheduling/schemas.test.ts`

**Interfaces:**
- Produces:
  - `WEEKDAYS` reuse from `@/features/identity/schemas` (Saturday-first) OR re-export; `Slot = {weekday, start_time, end_time}`; `Availability = {timezone, slots: Slot[]}`.
  - `getAvailability(): Promise<Availability>`, `saveAvailability(input: Availability): Promise<Availability>` (GET/PUT `/scheduling/me/availability/` via the shared axios in `src/lib/api.ts`).
  - `useAvailability()` (query key `["availability"]`), `useSaveAvailability()` (invalidates `["availability"]`).

- [ ] **Step 1: Write failing schema test**

`dashboard/src/features/scheduling/schemas.test.ts`:
```ts
import { describe, expect, it } from "vitest";
import { availabilitySchema } from "./schemas";

describe("availabilitySchema", () => {
  it("accepts a valid availability payload", () => {
    const ok = availabilitySchema.safeParse({
      timezone: "Africa/Cairo",
      slots: [{ weekday: 0, start_time: "09:00", end_time: "12:00" }],
    });
    expect(ok.success).toBe(true);
  });
  it("rejects end before start", () => {
    const bad = availabilitySchema.safeParse({
      timezone: "UTC",
      slots: [{ weekday: 0, start_time: "12:00", end_time: "09:00" }],
    });
    expect(bad.success).toBe(false);
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd dashboard && pnpm test src/features/scheduling/schemas.test.ts`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement schemas/api/queries**

`schemas.ts`:
```ts
import { z } from "zod";

export const slotSchema = z
  .object({
    weekday: z.number().int().min(0).max(6),
    start_time: z.string().regex(/^\d{2}:\d{2}$/),
    end_time: z.string().regex(/^\d{2}:\d{2}$/),
  })
  .refine((s) => s.end_time > s.start_time, { message: "endAfterStart", path: ["end_time"] });

export const availabilitySchema = z.object({
  timezone: z.string().min(1),
  slots: z.array(slotSchema),
});

export type Slot = z.infer<typeof slotSchema>;
export type Availability = z.infer<typeof availabilitySchema>;
```
`api.ts` and `queries.ts`: mirror `dashboard/src/features/identity/api.ts` + `queries.ts` (same axios instance, `parseApiError`, TanStack Query patterns). `getAvailability` → `GET scheduling/me/availability/`; `saveAvailability` → `PUT scheduling/me/availability/`. `useSaveAvailability` invalidates `["availability"]`.

- [ ] **Step 4: Verify**

Run: `cd dashboard && pnpm test src/features/scheduling/schemas.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd dashboard && git commit -am "feat(scheduling): dashboard availability data layer"
```

---

## Task 9: `WeeklyAvailabilityEditor` component

**Files:**
- Create: `dashboard/src/features/scheduling/components/WeeklyAvailabilityEditor.tsx`, `WeeklyAvailabilityEditor.test.tsx`
- Modify: `dashboard/src/locales/{en,ar}/common.json` (keys under `availability.*`)

**Interfaces:**
- Consumes: `Slot`, `Availability` (Task 8); `@/ui` primitives; `WEEKDAYS`.
- Produces: `<WeeklyAvailabilityEditor value={Availability} onSave={(a: Availability) => Promise} pending={boolean} />` — fully controlled-from-load; renders 7 day rows, range pills with remove, inline `+ Add time` start→end `<select>` (15-min options, `end>start` validated inline with `t("availability.endAfterStart")`), "Copy [day] to all", and a Save button calling `onSave` with the full set.

- [ ] **Step 1: Write failing component tests** (render rows; add a range; remove a pill; end≤start shows error; save emits full set; jest-axe). Use `@testing-library/react` + `user-event`, wrap with i18n (`import "@/lib/i18n"`). Assert Saturday-first order and that an empty day shows `t("availability.unavailable")`.

- [ ] **Step 2: Run to verify failure** — `cd dashboard && pnpm test WeeklyAvailabilityEditor` → FAIL (missing component).

- [ ] **Step 3: Implement the component** using `@/ui` `Button`, `Field`/`Label`, a `<select>` styled like the existing `StudentPreferencesCard` select. Generate 15-minute `HH:MM` options 00:00–23:45. Keep local state seeded from `value`; "Save" calls `onSave({ timezone: value.timezone, slots })`. All labels via `t(...)`; logical CSS (`ps-/pe-`) for RTL; each remove button has an `aria-label`.

- [ ] **Step 4: Add i18n keys** under `availability` in both `en` and `ar` (`title`, `addTime`, `copyToAll`, `unavailable`, `start`, `end`, `to`, `remove`, `save`, `saved`, `endAfterStart`, `loadError`, `genericError`).

- [ ] **Step 5: Run tests** — `cd dashboard && pnpm test WeeklyAvailabilityEditor` → PASS (incl. axe).

- [ ] **Step 6: Commit** — `cd dashboard && git commit -am "feat(scheduling): WeeklyAvailabilityEditor component"`

---

## Task 10: Timezone bar + picker

**Files:**
- Create: `dashboard/src/features/scheduling/components/TimezoneBar.tsx`, `TimezoneBar.test.tsx`
- Modify: locales (`availability.timezoneLabel`, `availability.changeTimezone`, `availability.searchTimezone`)

**Interfaces:**
- Produces: `<TimezoneBar value={string} onChange={(tz: string) => void} />` — shows "Times shown in your timezone: {tz} (UTC±X)"; **Change** opens a searchable list from `Intl.supportedValuesOf("timeZone")`; selecting calls `onChange`. Auto-detect helper `detectTimezone()` = `Intl.DateTimeFormat().resolvedOptions().timeZone`.

- [ ] **Step 1: Failing tests** — renders the current tz; clicking Change reveals a search box; typing filters; selecting one calls `onChange`; jest-axe clean.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** with a `@/ui` button + a simple searchable list (filter `Intl.supportedValuesOf("timeZone")` by query). Compute the `UTC±X` label from `Intl.DateTimeFormat(undefined,{timeZone,timeZoneName:"shortOffset"})`.
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(scheduling): timezone bar + picker"`

---

## Task 11: Pages — teacher `/availability` + student `/account` integration

**Files:**
- Create: `dashboard/src/routes/_authed/availability.tsx`, `dashboard/src/routes/_authed/availability.test.tsx`
- Modify: `dashboard/src/features/identity/components/StudentPreferencesCard.tsx` (+ its test), `dashboard/src/features/shell/nav.ts` (+ `nav.test.ts`), `dashboard/src/routeTree.gen.ts` (regenerated)

**Interfaces:**
- Consumes: `useAvailability`, `useSaveAvailability` (Task 8); `WeeklyAvailabilityEditor` (Task 9); `TimezoneBar` (Task 10).
- Produces: a teacher-gated `/availability` page composing `TimezoneBar` + `WeeklyAvailabilityEditor` fed by the query; the student `/account` prefs card uses the same editor for availability while keeping the gender control.

- [ ] **Step 1: Failing tests** — `availability.test.tsx` renders the page (mock `useAvailability`), shows the editor + tz bar, saves via `useSaveAvailability`. Update `StudentPreferencesCard.test.tsx`: assert the old day+start/end rows are gone and the `WeeklyAvailabilityEditor` renders; gender control still present. Update `nav.test.ts` for the new teacher item.

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement**
- `availability.tsx`: `export function AvailabilityPage()` using `useAvailability()` (loading → `Spinner`; error → `Alert`), rendering `TimezoneBar` + `WeeklyAvailabilityEditor`; `Route = createFileRoute("/_authed/availability")({ component: AvailabilityPage })`.
- `StudentPreferencesCard.tsx`: remove the `useFieldArray` time-slot rows; render `<WeeklyAvailabilityEditor>` fed by `useAvailability`/`useSaveAvailability`; keep the teacher-gender `<select>` saving to the identity endpoint as before. (Availability now saves to scheduling; gender stays on identity — two saves.)
- `nav.ts`: replace the placeholder `/schedule` scaffold item (or add) a teacher-gated **Availability** item `{ to: "/availability", labelKey: "nav.availability", icon: CalendarClock, requires: "teacher" }`; add `nav.availability` i18n keys.

- [ ] **Step 4: Regenerate the route tree + run gate**

Run:
```bash
cd dashboard && pnpm exec vite build && pnpm test && pnpm exec tsc --noEmit && pnpm exec biome check --write src && pnpm exec biome check src
```
Expected: route tree includes `/_authed/availability`; all tests PASS; tsc clean; biome exit 0.

- [ ] **Step 5: Commit + open dashboard PR**

```bash
cd dashboard && git commit -am "feat(scheduling): availability page + student prefs integration + nav"
git push -u origin feat/scheduling-availability
gh pr create --repo kaleem-lms/dashboard --base main --head feat/scheduling-availability \
  --title "feat(scheduling): weekly availability editor" --body "Implements the scheduling-availability spec (frontend)."
```

---

## Task 12: Manual verification + meta wiring

**Files:** none (verification) + meta pointer bumps after merges.

- [ ] **Step 1: Browser verification** (dev stack `just dev`): as a teacher, open `/availability`, add ranges across days, change timezone, Save, reload → state persists. As a student, open `/account`, set availability + gender, Save, reload → persists. Repeat in **ar/RTL**. Confirm `end ≤ start` blocks save with a visible error.
- [ ] **Step 2:** After both PRs merge to `main`, bump the `backend` + `dashboard` submodule pointers in a meta `feat → develop` PR, update `STATE.md`, and record the Phase-B-started deviation in the journal.
- [ ] **Step 3:** (Optional) promote `develop → master` to deploy to staging (`gh pr merge --merge`, never squash).

---

## Self-review notes

- **Spec coverage:** module+model (T1–T2), `User.timezone`+service (T3), remove `time_preferences` (T4), service merge/get/set (T5), `to_utc_intervals` incl. +3/+2 and wrap (T6), GET/PUT API + profile gate + typed 400 (T7), data layer (T8), editor (T9), tz bar (T10), pages + nav + student integration (T11), verification + e2e-manual note + meta (T12). All spec sections mapped.
- **Boundary:** `scheduling`→`identity.services` allowed by the new contract (T1); `scheduling` never imports identity models.
- **No data migration** (per spec): T4 just drops the field; dev DB reset.
- **e2e:** Playwright harness absent (ISSUES) → manual browser verification (T12), flagged.
