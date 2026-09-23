# Phase C3e-a — Call Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the channel through which a call failure on a browser we cannot run becomes a row that names the failure.

**Architecture:** One `POST` endpoint under `/api/v1/scheduling/`, backed by one model in the `scheduling` module, authorized by the existing `rooms.is_participant` predicate and throttled by a new DRF scope. A Celery beat job deletes rows after 90 days. On the client, a pure allow-list redaction function strips every address field from `getStats()` output before anything is sent, and a fire-and-forget hook reports the four failures the code already detects.

**Tech Stack:** Django 5 + DRF, Celery beat, PostgreSQL; React 19 + TanStack Query + axios + zod, Vitest, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-07-phase-c3e-a-call-diagnostics-design.md`

## Global Constraints

- **Every route lives under `/api/v1/`** and is mounted through `kaleem/scheduling/api/urls.py`, never straight onto `config/urls.py` (ADR-0017, ADR-0029). CI walks the URLconf and fails on anything unversioned.
- **No business logic on models** (rule #4). Logic goes in `kaleem/scheduling/services.py`; views validate and delegate.
- **No module may import another module's models** (D4, `import-linter`). Cross-module calls go through `<module>/services.py`.
- **No bare `except Exception` stringified into a response** (rule #8). Use the typed exceptions in `kaleem/platform/exceptions.py`.
- **No `print()`** in production code (rule #9). Structured logging only.
- **Backend coverage floor is 97.7** (line and branch), in `backend/pyproject.toml` `[tool.coverage.report]`. Measure with `pytest --cov=kaleem --cov=signaling` — **never a bare `pytest --cov`**, which omits unimported files, reads roughly 0.55 high and has previously set a false floor that turned CI red. Floors may only rise (ADR-0026).
- **Dashboard coverage floors are 95.1 lines / 91.4 branches / 86.6 functions**, in `dashboard/vitest.config.ts`. Same ratchet rule.
- **Styles come from design tokens** — semantic utilities only, never a hardcoded hex or `color-mix`.
- **a11y/i18n/RTL are a repo-wide baseline**, not per-feature. Any user-visible string goes through `react-i18next`; no physical-direction utilities where a logical one exists.
- **Failure codes, exactly these eight strings**, and no others: `gum-denied`, `gum-not-found`, `gum-in-use`, `autoplay-blocked`, `gum-no-gesture`, `ice-restart-unsupported`, `backgrounded`, `device-lost`.
- **Throttle rate is `"call-diagnostics": "20/hour"`.**
- **`user_agent` is truncated to 512 characters** and read server-side from the request header, never from the request body.
- **Retention is 90 days.**
- **Redaction is an allow-list**, and the allowed stat fields are exactly: `type`, `candidateType`, `bytesSent`, `bytesReceived`, `state`, `nominated`, `codecId`, `mimeType`, `packetsLost`, `jitter`.
- **Trunk-based git** (ADR-0028): `feat/<name>` → PR → `main` in submodules, `master` in meta. Never commit to a trunk. Never `--no-verify`. Commit with `PIP_CONFIG_FILE=/dev/null` — a dead pip proxy in `pip.conf` otherwise breaks pre-commit.

---

## File Structure

**Backend (`backend/`, branch `feat/call-diagnostics`):**

| File | Responsibility |
| --- | --- |
| `kaleem/scheduling/diagnostics.py` (create) | The failure-code enum and `record_diagnostic()`. A new file, not an addition to `rooms.py`: rooms is about admission to a lesson, this is about reporting on one. |
| `kaleem/scheduling/models.py` (modify) | Add `CallDiagnostic`. |
| `kaleem/scheduling/migrations/00XX_calldiagnostic.py` (create) | Generated. |
| `kaleem/scheduling/api/diagnostics_serializers.py` (create) | `CallDiagnosticSerializer` — matches the existing `booking_serializers` / `matching_serializers` split. |
| `kaleem/scheduling/api/views.py` (modify) | `SessionDiagnosticView`. |
| `kaleem/scheduling/api/urls.py` (modify) | One `path()`. |
| `kaleem/scheduling/tasks.py` (modify) | `purge_call_diagnostics()`. |
| `config/settings/base.py` (modify) | Throttle rate; beat schedule entry. |
| `kaleem/scheduling/tests/test_diagnostics_service.py` (create) | Service + model. |
| `kaleem/scheduling/tests/test_diagnostics_api.py` (create) | Endpoint, authorization, validation, throttle. |
| `kaleem/scheduling/tests/test_diagnostics_retention.py` (create) | The 90-day boundary. |

**Dashboard (`dashboard/`, branch `feat/call-diagnostics`):**

| File | Responsibility |
| --- | --- |
| `src/features/call/redactStats.ts` (create) | Pure. No React, no network. The security boundary. |
| `src/features/call/redactStats.test.ts` (create) | Safari-shaped fixture with real addresses. |
| `src/features/call/diagnosticsApi.ts` (create) | The axios call and the code union. |
| `src/features/call/useCallDiagnostics.ts` (create) | `report(code, pc?)`, fire-and-forget. |
| `src/features/call/useCallDiagnostics.test.ts` (create) | Including "a rejected POST does not propagate". |
| `src/features/call/useLocalMedia.ts` (modify) | Emit on classified failure. |
| `src/features/call/VideoTile.tsx` (modify) | Emit on rejected `play()`. |
| `e2e/call-diagnostics.spec.ts` (create) | The contract test over all eight codes. |

**Meta (`docs/`, branch `docs/c3e-a-shipped`):** the D3 table in `CLAUDE.md`, `STATE.md`, `ISSUES.md`, `docs/runbook/video-call.md`, `docs/superpowers/journal/2026-W36.md`.

---

### Task 1: The `CallDiagnostic` model

**Files:**
- Modify: `backend/kaleem/scheduling/models.py`
- Create: `backend/kaleem/scheduling/migrations/00XX_calldiagnostic.py` (generated)
- Test: `backend/kaleem/scheduling/tests/test_diagnostics_service.py`

**Interfaces:**
- Consumes: `Session` (already in `models.py`), `settings.AUTH_USER_MODEL`.
- Produces: `CallDiagnostic` with fields `session`, `user`, `code`, `user_agent`, `stats`, `created_at`, and `CallDiagnostic.Code` as a `TextChoices` holding the eight codes.

- [ ] **Step 1: Write the failing test**

Create `backend/kaleem/scheduling/tests/test_diagnostics_service.py`:

```python
import datetime as dt

import pytest
from django.utils import timezone

from kaleem.scheduling.models import CallDiagnostic
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


def test_the_code_vocabulary_is_closed_and_exact():
    """The eight codes are the contract the client is written against and the
    e2e contract test iterates. Adding one is a deliberate act that should
    break this test, not a silent widening of what the endpoint accepts."""
    assert set(CallDiagnostic.Code.values) == {
        "gum-denied",
        "gum-not-found",
        "gum-in-use",
        "autoplay-blocked",
        "gum-no-gesture",
        "ice-restart-unsupported",
        "backgrounded",
        "device-lost",
    }


def test_a_diagnostic_without_stats_is_valid(session, student):
    """The three getUserMedia failures happen in the Lobby, before any
    RTCPeerConnection exists, so they have no stats to carry. A null here is
    correct, not missing data."""
    row = CallDiagnostic.objects.create(
        session=session,
        user=student,
        code=CallDiagnostic.Code.GUM_DENIED,
        user_agent="Mozilla/5.0",
    )
    assert row.stats is None
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd backend && pytest kaleem/scheduling/tests/test_diagnostics_service.py -v
```
Expected: FAIL — `ImportError: cannot import name 'CallDiagnostic'`.

- [ ] **Step 3: Add the model**

Append to `backend/kaleem/scheduling/models.py`:

```python
class CallDiagnostic(models.Model):
    """One reported failure from one participant's browser during one call.

    Exists because C3e cannot be tested on the browsers it targets: this
    project has no Apple device and Playwright's WebKit is not iOS Safari,
    so a row here is the only evidence a Safari failure ever produces.

    CASCADE from Session for the same reason Room does: a diagnostic has no
    meaning apart from its lesson, and PROTECT would break account deletion
    (see the comment on Session.slot).
    """

    class Code(models.TextChoices):
        GUM_DENIED = "gum-denied", "Camera/microphone permission refused"
        GUM_NOT_FOUND = "gum-not-found", "No camera or microphone present"
        GUM_IN_USE = "gum-in-use", "Device held by another application"
        AUTOPLAY_BLOCKED = "autoplay-blocked", "Browser refused to play remote media"
        GUM_NO_GESTURE = "gum-no-gesture", "Media requested without user activation"
        ICE_RESTART_UNSUPPORTED = "ice-restart-unsupported", "restartIce() unavailable"
        BACKGROUNDED = "backgrounded", "Page suspended mid-call"
        DEVICE_LOST = "device-lost", "Device disappeared mid-call"

    session = models.ForeignKey(
        Session, on_delete=models.CASCADE, related_name="diagnostics"
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+"
    )
    code = models.CharField(max_length=32, choices=Code.choices)
    # Read server-side from the request header, never from the body: a
    # client-supplied value would be the one field an attacker could forge,
    # and it is the field the whole phase exists to read.
    user_agent = models.CharField(max_length=512, blank=True, default="")
    # Redacted client-side before it is sent -- see `redactStats.ts`. Null for
    # the Lobby failures, which happen before a peer connection exists.
    stats = models.JSONField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["session"]),
            # The retention job filters on this alone.
            models.Index(fields=["created_at"]),
        ]

    def __str__(self):
        return f"{self.code} on session {self.session_id}"
```

Confirm `from django.conf import settings` is imported at the top of `models.py`; add it if not.

- [ ] **Step 4: Generate the migration**

```bash
cd backend && python manage.py makemigrations scheduling
```

- [ ] **Step 5: Run the tests**

```bash
cd backend && pytest kaleem/scheduling/tests/test_diagnostics_service.py -v
```
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
cd backend && PIP_CONFIG_FILE=/dev/null git add kaleem/scheduling/models.py kaleem/scheduling/migrations/ kaleem/scheduling/tests/test_diagnostics_service.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): add CallDiagnostic with a closed code vocabulary"
```

---

### Task 2: `record_diagnostic()`

**Files:**
- Create: `backend/kaleem/scheduling/diagnostics.py`
- Test: `backend/kaleem/scheduling/tests/test_diagnostics_service.py` (append)

**Interfaces:**
- Consumes: `CallDiagnostic`, `Session`, `rooms.is_participant`.
- Produces: `record_diagnostic(actor, session_id: int, *, code: str, user_agent: str, stats: dict | None) -> CallDiagnostic`. Raises `NotFoundError` for an unknown session and `PermissionDeniedError` for a non-participant.

- [ ] **Step 1: Write the failing tests**

Append to `test_diagnostics_service.py`:

```python
from kaleem.platform.exceptions import NotFoundError
from kaleem.platform.exceptions import PermissionDeniedError
from kaleem.scheduling import diagnostics


def test_a_participant_can_record_a_diagnostic(session, student):
    row = diagnostics.record_diagnostic(
        student,
        session.id,
        code="autoplay-blocked",
        user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X)",
        stats={"candidateType": "relay"},
    )
    assert row.session_id == session.id
    assert row.user_id == student.id
    assert row.stats == {"candidateType": "relay"}


def test_a_parent_of_the_student_is_refused(session, student, parent):
    """The mistake a reader who thinks "related to this session" rather than
    "in this lesson" would make. A parent may see the schedule but may not
    enter the room (Decision 3), and must not report on it either."""
    with pytest.raises(PermissionDeniedError):
        diagnostics.record_diagnostic(
            parent, session.id, code="gum-denied", user_agent="x", stats=None
        )


def test_an_unknown_session_is_not_found(student):
    with pytest.raises(NotFoundError):
        diagnostics.record_diagnostic(
            student, 999_999, code="gum-denied", user_agent="x", stats=None
        )


def test_the_user_agent_is_truncated_rather_than_rejected(session, student):
    """A browser sending a 600-character UA must not cost someone the report;
    the column caps at 512 and the service is what makes that true."""
    row = diagnostics.record_diagnostic(
        session=session.id, actor=student, code="gum-denied",
        user_agent="U" * 600, stats=None,
    )
    assert len(row.user_agent) == 512
```

Note: the last test calls with keywords; keep the signature `record_diagnostic(actor, session_id, *, code, user_agent, stats)` and adjust that call to positional `student, session.id` to match — written here as keywords only to make the parameter names explicit.

- [ ] **Step 2: Run and watch it fail**

```bash
cd backend && pytest kaleem/scheduling/tests/test_diagnostics_service.py -v
```
Expected: FAIL — `ModuleNotFoundError: kaleem.scheduling.diagnostics`.

- [ ] **Step 3: Write the service**

Create `backend/kaleem/scheduling/diagnostics.py`:

```python
"""Recording what broke, on a browser we cannot run.

C3e targets Safari and iOS, and this project has no Apple device: the e2e
harness that gates every other area structurally cannot cover that phase.
A row written here is the only evidence a Safari failure produces, which is
why the vocabulary is closed and the authorization is shared rather than
re-derived.
"""

from __future__ import annotations

import logging

from kaleem.platform.exceptions import NotFoundError
from kaleem.scheduling.models import CallDiagnostic
from kaleem.scheduling.models import Session
from kaleem.scheduling.rooms import is_participant

logger = logging.getLogger(__name__)

USER_AGENT_MAX_LENGTH = 512


def record_diagnostic(
    actor,
    session_id: int,
    *,
    code: str,
    user_agent: str,
    stats: dict | None,
) -> CallDiagnostic:
    """Record one browser failure against one session.

    Authorization is `rooms.is_participant` -- the SAME predicate the join
    guard uses, deliberately not a second one that agrees with it today.
    Widening who may enter a lesson then lands on the room and its
    diagnostics together instead of drifting apart.
    """
    session = (
        Session.objects.select_related("assignment").filter(id=session_id).first()
    )
    if session is None:
        raise NotFoundError("Session", session_id)

    if not is_participant(actor, session.assignment):
        from kaleem.platform.exceptions import PermissionDeniedError

        raise PermissionDeniedError("report diagnostics for a session you are not in")

    # Truncated, not rejected: a browser with an unusually long User-Agent
    # must not cost us the report -- the report is the whole point.
    return CallDiagnostic.objects.create(
        session=session,
        user=actor,
        code=code,
        user_agent=(user_agent or "")[:USER_AGENT_MAX_LENGTH],
        stats=stats,
    )
```

Move the `PermissionDeniedError` import to the top of the file rather than leaving it inline.

- [ ] **Step 4: Run the tests**

```bash
cd backend && pytest kaleem/scheduling/tests/test_diagnostics_service.py -v
```
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
cd backend && PIP_CONFIG_FILE=/dev/null git add kaleem/scheduling/diagnostics.py kaleem/scheduling/tests/test_diagnostics_service.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): record_diagnostic, authorized by the join predicate"
```

---

### Task 3: The endpoint

**Files:**
- Create: `backend/kaleem/scheduling/api/diagnostics_serializers.py`
- Modify: `backend/kaleem/scheduling/api/views.py`, `backend/kaleem/scheduling/api/urls.py`, `backend/config/settings/base.py`
- Test: `backend/kaleem/scheduling/tests/test_diagnostics_api.py`

**Interfaces:**
- Consumes: `diagnostics.record_diagnostic`.
- Produces: route name `api:scheduling:session-diagnostics` at `sessions/<int:session_id>/diagnostics/`, responding `201` with an empty body.

- [ ] **Step 1: Write the failing tests**

Create `backend/kaleem/scheduling/tests/test_diagnostics_api.py`:

```python
import datetime as dt

import pytest
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from kaleem.scheduling.models import CallDiagnostic
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


def _url(session):
    return reverse("api:scheduling:session-diagnostics", args=[session.id])


def test_a_participant_can_report(session, student, client_for):
    response = client_for(student).post(
        _url(session), {"code": "autoplay-blocked"}, format="json"
    )
    assert response.status_code == 201
    assert CallDiagnostic.objects.filter(session=session).count() == 1


def test_an_unknown_code_is_rejected_and_stores_nothing(session, student, client_for):
    """The moment free text is accepted the field becomes an uncontrolled
    channel carrying whatever a browser puts in a localised error message."""
    response = client_for(student).post(
        _url(session), {"code": "something-new"}, format="json"
    )
    assert response.status_code == 400
    assert CallDiagnostic.objects.count() == 0


def test_a_parent_is_refused(session, parent, client_for):
    response = client_for(parent).post(
        _url(session), {"code": "gum-denied"}, format="json"
    )
    assert response.status_code == 403
    assert CallDiagnostic.objects.count() == 0


def test_anonymous_is_refused(session):
    response = APIClient().post(_url(session), {"code": "gum-denied"}, format="json")
    assert response.status_code in (401, 403)
    assert CallDiagnostic.objects.count() == 0


def test_the_user_agent_comes_from_the_header_not_the_body(
    session, student, client_for
):
    """A client-supplied UA would be the one forgeable field, and it is the
    field the phase exists to read."""
    response = client_for(student).post(
        _url(session),
        {"code": "gum-denied", "user_agent": "FORGED"},
        format="json",
        HTTP_USER_AGENT="Mozilla/5.0 (iPhone)",
    )
    assert response.status_code == 201
    row = CallDiagnostic.objects.get()
    assert row.user_agent == "Mozilla/5.0 (iPhone)"


def test_stats_are_stored_as_given(session, student, client_for):
    client_for(student).post(
        _url(session),
        {"code": "autoplay-blocked", "stats": {"candidateType": "relay"}},
        format="json",
    )
    assert CallDiagnostic.objects.get().stats == {"candidateType": "relay"}
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd backend && pytest kaleem/scheduling/tests/test_diagnostics_api.py -v
```
Expected: FAIL — `NoReverseMatch: 'session-diagnostics' is not a valid view function or pattern name`.

- [ ] **Step 3: Write the serializer**

Create `backend/kaleem/scheduling/api/diagnostics_serializers.py`:

```python
from rest_framework import serializers

from kaleem.scheduling.models import CallDiagnostic


class CallDiagnosticSerializer(serializers.Serializer):
    """Write-only. `ChoiceField` against the model's own vocabulary is what
    makes an unrecognised code a 400 rather than a stored row.

    `user_agent` is deliberately absent: it is read from the request header
    server-side, so a client cannot supply it.
    """

    code = serializers.ChoiceField(choices=CallDiagnostic.Code.choices)
    # Redacted in the browser before it arrives -- see `redactStats.ts`. The
    # server does not re-validate its shape: it is diagnostic data, stored as
    # given, and a schema here would reject a future browser's fields for no
    # gain.
    stats = serializers.JSONField(required=False, allow_null=True, default=None)
```

- [ ] **Step 4: Write the view**

Add to `backend/kaleem/scheduling/api/views.py` (import `diagnostics`, `CallDiagnosticSerializer`, `ScopedRateThrottle`, and `status` as needed):

```python
class SessionDiagnosticView(APIView):
    """Report one browser failure during this session's call.

    Throttled because a broken browser is exactly the client that retries in
    a loop; 20/hour sits above a bad lesson's honest count (a handful of
    failures plus a few rejoins) and well below a loop's.
    """

    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "call-diagnostics"

    def post(self, request, session_id: int):
        serializer = CallDiagnosticSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        diagnostics.record_diagnostic(
            request.user,
            session_id,
            code=serializer.validated_data["code"],
            user_agent=request.META.get("HTTP_USER_AGENT", ""),
            stats=serializer.validated_data["stats"],
        )
        return Response(status=status.HTTP_201_CREATED)
```

- [ ] **Step 5: Wire the route**

In `backend/kaleem/scheduling/api/urls.py`, import `SessionDiagnosticView` and add, next to `session-join`:

```python
    path(
        "sessions/<int:session_id>/diagnostics/",
        SessionDiagnosticView.as_view(),
        name="session-diagnostics",
    ),
```

- [ ] **Step 6: Add the throttle rate**

In `backend/config/settings/base.py`, change the throttle line to:

```python
    "DEFAULT_THROTTLE_RATES": {"email": "5/hour", "call-diagnostics": "20/hour"},
```

- [ ] **Step 7: Run the tests**

```bash
cd backend && pytest kaleem/scheduling/tests/test_diagnostics_api.py kaleem/tests/test_api_versioning_is_enforced.py -v
```
Expected: PASS. The versioning test is included because a route added outside `/api/v1/` fails it, and that is the cheapest place to catch it.

- [ ] **Step 8: Commit**

```bash
cd backend && PIP_CONFIG_FILE=/dev/null git add kaleem/scheduling/api/ config/settings/base.py kaleem/scheduling/tests/test_diagnostics_api.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): POST /api/v1/scheduling/sessions/<id>/diagnostics/"
```

---

### Task 4: 90-day retention

**Files:**
- Modify: `backend/kaleem/scheduling/tasks.py`, `backend/config/settings/base.py`, `backend/kaleem/scheduling/diagnostics.py`
- Test: `backend/kaleem/scheduling/tests/test_diagnostics_retention.py`

**Interfaces:**
- Consumes: `CallDiagnostic`.
- Produces: `diagnostics.purge_expired(now=None) -> int` and the Celery task `kaleem.scheduling.tasks.purge_call_diagnostics`.

- [ ] **Step 1: Write the failing test**

Create `backend/kaleem/scheduling/tests/test_diagnostics_retention.py`:

```python
import datetime as dt

import pytest
from django.utils import timezone

from kaleem.scheduling import diagnostics
from kaleem.scheduling.models import CallDiagnostic
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


def _row_aged(session, user, days):
    row = CallDiagnostic.objects.create(
        session=session, user=user, code="gum-denied", user_agent="x"
    )
    # `auto_now_add` ignores an assigned value, so age it with an update.
    CallDiagnostic.objects.filter(id=row.id).update(
        created_at=timezone.now() - dt.timedelta(days=days)
    )
    return row


def test_the_boundary_is_ninety_days_on_both_sides(session, student):
    """Tested for what it LEAVES as well as what it removes. A retention job
    that silently deletes everything is worse than having none."""
    kept = _row_aged(session, student, 89)
    purged = _row_aged(session, student, 91)

    deleted = diagnostics.purge_expired()

    assert deleted == 1
    assert CallDiagnostic.objects.filter(id=kept.id).exists()
    assert not CallDiagnostic.objects.filter(id=purged.id).exists()


def test_purging_an_empty_table_is_a_no_op():
    assert diagnostics.purge_expired() == 0
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd backend && pytest kaleem/scheduling/tests/test_diagnostics_retention.py -v
```
Expected: FAIL — `AttributeError: module 'kaleem.scheduling.diagnostics' has no attribute 'purge_expired'`.

- [ ] **Step 3: Implement**

Append to `backend/kaleem/scheduling/diagnostics.py`:

```python
import datetime as dt

from django.utils import timezone

# 90 days: long enough to see a pattern tied to an iOS point release, which
# surfaces over weeks, and short enough to state plainly in a privacy policy.
RETENTION = dt.timedelta(days=90)


def purge_expired(*, now: dt.datetime | None = None) -> int:
    """Delete diagnostics past their retention window. Returns the count."""
    cutoff = (now or timezone.now()) - RETENTION
    deleted, _ = CallDiagnostic.objects.filter(created_at__lt=cutoff).delete()
    logger.info("purged %s expired call diagnostics", deleted)
    return deleted
```

Append to `backend/kaleem/scheduling/tasks.py`:

```python
@shared_task
def purge_call_diagnostics() -> None:
    """Daily. Enforce the 90-day retention window on call diagnostics.

    No autoretry: it is idempotent and runs again tomorrow, so a failure is
    left to surface rather than retried.
    """
    diagnostics.purge_expired()
```

with `from kaleem.scheduling import diagnostics` at the top.

- [ ] **Step 4: Schedule it**

In `backend/config/settings/base.py`, add to `CELERY_BEAT_SCHEDULE`:

```python
    "scheduling-purge-call-diagnostics": {
        "task": "kaleem.scheduling.tasks.purge_call_diagnostics",
        # Off-peak, and after the other nightly jobs so a slow purge cannot
        # delay session generation.
        "schedule": crontab(hour="4", minute="11"),
    },
```

- [ ] **Step 5: Run the tests**

```bash
cd backend && pytest kaleem/scheduling/tests/ -v
```
Expected: PASS.

- [ ] **Step 6: Ratchet the coverage floor and commit**

```bash
cd backend && pytest --cov=kaleem --cov=signaling --cov-report=term-missing -q | tail -5
```
Raise `fail_under` in `pyproject.toml` `[tool.coverage.report]` to the measured value (never lower it), then:

```bash
PIP_CONFIG_FILE=/dev/null git add kaleem/scheduling/ config/settings/base.py pyproject.toml
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): 90-day retention for call diagnostics"
```

---

### Task 5: `redactStats` — the security boundary

**Files:**
- Create: `dashboard/src/features/call/redactStats.ts`
- Test: `dashboard/src/features/call/redactStats.test.ts`

**Interfaces:**
- Produces: `redactStats(report: RTCStatsReport | null): Record<string, unknown>[] | null` and the exported constant `ALLOWED_STAT_FIELDS`.

- [ ] **Step 1: Write the failing test**

Create `dashboard/src/features/call/redactStats.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { redactStats } from "./redactStats";

// A realistic Safari-shaped report, not a two-field stub: a stub would remove
// the very constraint under test. These entries carry the address fields
// Safari actually emits, in the shapes it emits them, including IPv6 and the
// `relatedAddress` that only appears on a reflexive candidate.
const SAFARI_REPORT = new Map<string, Record<string, unknown>>([
	["RTCIceCandidate_h4x", {
		id: "RTCIceCandidate_h4x",
		type: "local-candidate",
		candidateType: "host",
		address: "192.168.1.42",
		ip: "192.168.1.42",
		port: 52881,
		protocol: "udp",
		networkType: "wifi",
	}],
	["RTCIceCandidate_s9k", {
		id: "RTCIceCandidate_s9k",
		type: "remote-candidate",
		candidateType: "srflx",
		address: "46.225.151.255",
		relatedAddress: "10.0.0.7",
		relatedPort: 49195,
		port: 49553,
	}],
	["RTCIceCandidate_v6", {
		id: "RTCIceCandidate_v6",
		type: "local-candidate",
		candidateType: "relay",
		address: "2a01:4f8:1c0c:4b1c::1",
		port: 3478,
	}],
	["RTCIceCandidatePair_1", {
		id: "RTCIceCandidatePair_1",
		type: "candidate-pair",
		state: "succeeded",
		nominated: true,
		bytesSent: 453_812,
		bytesReceived: 466_120,
		currentRoundTripTime: 0.042,
	}],
	["RTCInboundRTPVideoStream_3", {
		id: "RTCInboundRTPVideoStream_3",
		type: "inbound-rtp",
		codecId: "RTCCodec_video_Inbound_96",
		mimeType: "video/H264",
		packetsLost: 12,
		jitter: 0.003,
		trackIdentifier: "6f2c-a11e-camera-front",
	}],
]) as unknown as RTCStatsReport;

function serialise(value: unknown): string {
	return JSON.stringify(value);
}

describe("redactStats", () => {
	it("keeps nothing that carries a network address", () => {
		const out = serialise(redactStats(SAFARI_REPORT));
		// Assert on the OUTPUT as a whole rather than per-field: a per-field
		// check would pass while a field nobody thought to name leaked.
		expect(out).not.toMatch(/\d{1,3}(\.\d{1,3}){3}/); // no dotted quad
		expect(out).not.toContain("2a01:4f8"); // no IPv6
		expect(out).not.toContain("relatedAddress");
		expect(out).not.toContain("192.168");
	});

	it("drops every field not on the allow-list, including unknown ones", () => {
		const out = serialise(redactStats(SAFARI_REPORT));
		// `networkType`, `port`, `currentRoundTripTime` and `trackIdentifier`
		// are all absent from the allow-list. `trackIdentifier` matters most:
		// it can carry a device name.
		expect(out).not.toContain("networkType");
		expect(out).not.toContain("trackIdentifier");
		expect(out).not.toContain("currentRoundTripTime");
		expect(out).not.toContain("port");
	});

	it("keeps the fields that answer the diagnostic questions", () => {
		const out = redactStats(SAFARI_REPORT);
		const pair = out?.find((entry) => entry.type === "candidate-pair");
		expect(pair).toMatchObject({
			state: "succeeded",
			nominated: true,
			bytesSent: 453_812,
			bytesReceived: 466_120,
		});
		const relay = out?.find((entry) => entry.candidateType === "relay");
		expect(relay).toBeDefined();
		const inbound = out?.find((entry) => entry.type === "inbound-rtp");
		expect(inbound).toMatchObject({ mimeType: "video/H264", packetsLost: 12 });
	});

	it("returns null for a null report", () => {
		expect(redactStats(null)).toBeNull();
	});
});
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd dashboard && pnpm vitest run src/features/call/redactStats.test.ts
```
Expected: FAIL — cannot resolve `./redactStats`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/call/redactStats.ts`:

```ts
// An ALLOW-list, and the distinction is the whole point.
//
// The obvious implementation of "strip the IPs" deletes `address`,
// `relatedAddress`, `raddr`, `ip` -- a deny-list. That is wrong here in the
// specific way this phase is dangerous: `RTCStatsReport` fields differ per
// browser and per version, and Safari is exactly the browser whose stat shape
// cannot be inspected from this project. A deny-list leaks every
// address-bearing field nobody here knew to name, and the browser most likely
// to have one is the browser this phase exists for.
//
// Copying named fields OUT means a field added by a future browser cannot
// leak, because nothing is copied unless it is listed. Changing this list is
// a security decision, not a tweak.
export const ALLOWED_STAT_FIELDS = [
	"type",
	"candidateType",
	"bytesSent",
	"bytesReceived",
	"state",
	"nominated",
	"codecId",
	"mimeType",
	"packetsLost",
	"jitter",
] as const;

/**
 * Reduce a `getStats()` report to the fields that answer a diagnostic
 * question, dropping everything else -- including every network address.
 *
 * Runs in the BROWSER, before anything is sent: a raw address never reaches
 * our server, our logs, or our database, so there is nothing to retain and
 * nothing to breach.
 *
 * Pure: no network, no DOM, no clock. That is what makes it directly
 * testable against a realistic Safari-shaped fixture.
 */
export function redactStats(
	report: RTCStatsReport | null,
): Record<string, unknown>[] | null {
	if (!report) {
		return null;
	}
	const out: Record<string, unknown>[] = [];
	report.forEach((entry: Record<string, unknown>) => {
		const kept: Record<string, unknown> = {};
		for (const field of ALLOWED_STAT_FIELDS) {
			if (entry[field] !== undefined) {
				kept[field] = entry[field];
			}
		}
		// An entry with nothing on the allow-list carries no signal; dropping
		// it keeps the payload to what is actually diagnostic.
		if (Object.keys(kept).length > 0) {
			out.push(kept);
		}
	});
	return out;
}
```

- [ ] **Step 4: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/redactStats.test.ts
```
Expected: PASS (4 tests).

- [ ] **Step 5: Mutation-check the allow-list**

Temporarily change `ALLOWED_STAT_FIELDS` to include `"address"`, re-run, and confirm the first test **fails** with a real dotted-quad in the output. Revert. A redaction test that passes both ways is not a test.

- [ ] **Step 6: Commit**

```bash
cd dashboard && PIP_CONFIG_FILE=/dev/null git add src/features/call/redactStats.ts src/features/call/redactStats.test.ts
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): allow-list redaction of WebRTC stats"
```

---

### Task 6: The reporting client

**Files:**
- Create: `dashboard/src/features/call/diagnosticsApi.ts`, `dashboard/src/features/call/useCallDiagnostics.ts`, `dashboard/src/features/call/useCallDiagnostics.test.ts`

**Interfaces:**
- Consumes: `redactStats`, `api` from `@/lib/api`.
- Produces: `type DiagnosticCode` (the eight strings), `DIAGNOSTIC_CODES` (a readonly array of all eight), and `useCallDiagnostics(sessionId: number)` returning `{ report: (code: DiagnosticCode, pc?: RTCPeerConnection | null) => void }`.

- [ ] **Step 1: Write the failing test**

Create `dashboard/src/features/call/useCallDiagnostics.test.ts`:

```ts
import { renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { useCallDiagnostics } from "./useCallDiagnostics";

vi.mock("@/lib/api", () => ({ api: { post: vi.fn() } }));

describe("useCallDiagnostics", () => {
	beforeEach(() => {
		vi.mocked(api.post).mockReset().mockResolvedValue({ data: null });
	});

	it("posts the code to the session's diagnostics route", async () => {
		const { result } = renderHook(() => useCallDiagnostics(42));
		result.current.report("gum-denied");
		expect(api.post).toHaveBeenCalledWith(
			"scheduling/sessions/42/diagnostics/",
			{ code: "gum-denied", stats: null },
		);
	});

	it("does not propagate a rejected post", async () => {
		vi.mocked(api.post).mockRejectedValue(new Error("network down"));
		const { result } = renderHook(() => useCallDiagnostics(42));
		// The assertion is that this line does not throw and no unhandled
		// rejection escapes. A diagnostics outage must never turn a
		// survivable call problem into a broken one.
		expect(() => result.current.report("gum-denied")).not.toThrow();
		await Promise.resolve();
	});

	it("attaches redacted stats when a peer connection is given", async () => {
		const pc = {
			getStats: vi.fn().mockResolvedValue(
				new Map([["p", { type: "candidate-pair", state: "succeeded", address: "10.0.0.1" }]]),
			),
		} as unknown as RTCPeerConnection;
		const { result } = renderHook(() => useCallDiagnostics(42));
		result.current.report("autoplay-blocked", pc);
		await vi.waitFor(() => expect(api.post).toHaveBeenCalled());
		const body = vi.mocked(api.post).mock.calls[0][1] as {
			stats: Record<string, unknown>[];
		};
		expect(JSON.stringify(body.stats)).not.toContain("10.0.0.1");
		expect(body.stats[0]).toMatchObject({ state: "succeeded" });
	});
});
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd dashboard && pnpm vitest run src/features/call/useCallDiagnostics.test.ts
```
Expected: FAIL — cannot resolve `./useCallDiagnostics`.

- [ ] **Step 3: Write the API module**

Create `dashboard/src/features/call/diagnosticsApi.ts`:

```ts
import { api } from "@/lib/api";

// The backend's `CallDiagnostic.Code` is the source of truth. This is
// necessarily a second copy -- a Vitest test cannot read a Python enum, and
// the dashboard is a separate submodule -- so drift is caught by the e2e
// contract test, which POSTs every code in this array through the real
// endpoint and asserts each is accepted.
export const DIAGNOSTIC_CODES = [
	"gum-denied",
	"gum-not-found",
	"gum-in-use",
	"autoplay-blocked",
	"gum-no-gesture",
	"ice-restart-unsupported",
	"backgrounded",
	"device-lost",
] as const;

export type DiagnosticCode = (typeof DIAGNOSTIC_CODES)[number];

export function postDiagnostic(
	sessionId: number,
	code: DiagnosticCode,
	stats: Record<string, unknown>[] | null,
): Promise<unknown> {
	return api.post(`scheduling/sessions/${sessionId}/diagnostics/`, {
		code,
		stats,
	});
}
```

- [ ] **Step 4: Write the hook**

Create `dashboard/src/features/call/useCallDiagnostics.ts`:

```ts
import { useCallback } from "react";
import { type DiagnosticCode, postDiagnostic } from "./diagnosticsApi";
import { redactStats } from "./redactStats";

/**
 * Report a call failure. Fire-and-forget, by design.
 *
 * Nothing here is awaited by a caller and every rejection is swallowed: a
 * diagnostics outage, a throttle, or an offline client must never turn a
 * survivable call problem into a broken one. This is the one place in the
 * call feature where an empty catch is CORRECT -- do not "fix" it into an
 * await; the whole point is that reporting cannot affect the lesson.
 */
export function useCallDiagnostics(sessionId: number) {
	const report = useCallback(
		(code: DiagnosticCode, pc?: RTCPeerConnection | null) => {
			void (async () => {
				let stats: Record<string, unknown>[] | null = null;
				if (pc) {
					// A failing connection can also fail to produce stats;
					// that must not cost us the report itself, which is the
					// part that names the failure.
					try {
						stats = redactStats(await pc.getStats());
					} catch {
						stats = null;
					}
				}
				await postDiagnostic(sessionId, code, stats);
			})().catch(() => {});
		},
		[sessionId],
	);

	return { report };
}
```

- [ ] **Step 5: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd dashboard && PIP_CONFIG_FILE=/dev/null git add src/features/call/diagnosticsApi.ts src/features/call/useCallDiagnostics.ts src/features/call/useCallDiagnostics.test.ts
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): fire-and-forget diagnostics reporting"
```

---

### Task 7: Wire the four emitters

**Files:**
- Modify: `dashboard/src/features/call/useLocalMedia.ts`, `dashboard/src/features/call/VideoTile.tsx`, `dashboard/src/features/call/CallRoom.tsx`, `dashboard/src/routes/_call/sessions.$sessionId.room.tsx`
- Test: `dashboard/src/features/call/useLocalMedia.test.ts`, `dashboard/src/features/call/VideoTile.test.tsx` (append to both)

**Interfaces:**
- Consumes: `useCallDiagnostics`, `DiagnosticCode`.
- Produces: `useLocalMedia` gains an optional `onFailure?: (code: DiagnosticCode) => void` in `UseLocalMediaDeps`; `VideoTile` gains an optional `onAutoplayBlocked?: () => void` prop.

Both are optional so every existing call site and test keeps working, and so neither module has to import a hook that needs a session id it does not have.

- [ ] **Step 1: Write the failing tests**

Append to `dashboard/src/features/call/useLocalMedia.test.ts`:

```ts
it("reports the classified code when getUserMedia fails", async () => {
	const onFailure = vi.fn();
	const denied = Object.assign(new Error("no"), { name: "NotAllowedError" });
	renderHook(() =>
		useLocalMedia({
			getUserMedia: vi.fn().mockRejectedValue(denied),
			enumerateDevices: vi.fn().mockResolvedValue([]),
			onFailure,
		}),
	);
	await vi.waitFor(() => expect(onFailure).toHaveBeenCalledWith("gum-denied"));
});

it("maps each failure kind to its own code", async () => {
	for (const [name, code] of [
		["NotFoundError", "gum-not-found"],
		["NotReadableError", "gum-in-use"],
	] as const) {
		const onFailure = vi.fn();
		renderHook(() =>
			useLocalMedia({
				getUserMedia: vi.fn().mockRejectedValue(Object.assign(new Error("x"), { name })),
				enumerateDevices: vi.fn().mockResolvedValue([]),
				onFailure,
			}),
		);
		await vi.waitFor(() => expect(onFailure).toHaveBeenCalledWith(code));
	}
});
```

Append to `dashboard/src/features/call/VideoTile.test.tsx`:

```tsx
it("reports when the browser refuses to play remote media", async () => {
	const onAutoplayBlocked = vi.fn();
	const play = vi
		.spyOn(HTMLMediaElement.prototype, "play")
		.mockRejectedValue(Object.assign(new Error("blocked"), { name: "NotAllowedError" }));
	render(
		<VideoTile
			stream={new MediaStream()}
			onAutoplayBlocked={onAutoplayBlocked}
			data-testid="remote"
		/>,
	);
	await waitFor(() => expect(onAutoplayBlocked).toHaveBeenCalled());
	play.mockRestore();
});
```

- [ ] **Step 2: Run and watch them fail**

```bash
cd dashboard && pnpm vitest run src/features/call/useLocalMedia.test.ts src/features/call/VideoTile.test.tsx
```
Expected: FAIL — `onFailure` / `onAutoplayBlocked` never called.

- [ ] **Step 3: Emit from `useLocalMedia`**

Add to `UseLocalMediaDeps`:

```ts
	// Optional so every existing call site and test keeps working, and so
	// this hook does not have to know a session id.
	onFailure?: (code: DiagnosticCode) => void;
```

Add a code table beside the existing `FAILURES` table:

```ts
// The diagnostic code for each classified failure. A second table rather
// than a field on `FAILURES` because the two vocabularies belong to
// different systems: `MediaFailure` drives what the person is TOLD, the code
// drives what we later FIND OUT. They are parallel today and need not stay so.
//
// `Partial`, and `unknown` is deliberately absent: reporting an
// unclassifiable failure under a specific code would put a wrong answer into
// the one table this phase exists to read, and there is no honest code for
// "we could not classify this". An unreported unknown is a gap we can see;
// a mislabelled one is a gap we cannot.
const FAILURE_CODES: Partial<Record<MediaFailure, DiagnosticCode>> = {
	denied: "gum-denied",
	"not-found": "gum-not-found",
	"in-use": "gum-in-use",
};
```

In the `catch` inside `acquire`, after `setFailure(classified)`:

```ts
			} catch (error) {
				const classified = classifyFailure(error);
				setFailure(classified);
				const code = FAILURE_CODES[classified];
				if (code) {
					onFailure?.(code);
				}
			}
```

Add `onFailure` to the destructure at the top and to `acquire`'s dependency array.

- [ ] **Step 4: Emit from `VideoTile`**

Add `onAutoplayBlocked?: () => void` to `VideoTileProps`, and change the play call:

```tsx
		// A rejection here has nothing actionable for the user, but it is the
		// single most likely Safari failure and was previously swallowed
		// entirely -- a still frame and no sound, which reads as "the other
		// person's camera is off". The report is what turns that into a fact.
		void video.play().catch(() => {
			onAutoplayBlocked?.();
		});
```

with `onAutoplayBlocked` in the props destructure and the effect's dependency array.

- [ ] **Step 5: Wire the call sites**

In `dashboard/src/routes/_call/sessions.$sessionId.room.tsx`, build the reporter and pass it in:

```tsx
	const diagnostics = useCallDiagnostics(Number(sessionId));
	const localMedia = useLocalMedia({
		getUserMedia: (constraints) => navigator.mediaDevices.getUserMedia(constraints),
		enumerateDevices: () => navigator.mediaDevices.enumerateDevices(),
		onFailure: diagnostics.report,
	});
```

In `dashboard/src/features/call/CallRoom.tsx`, accept an `onAutoplayBlocked?: () => void` prop and pass it to the **remote** `VideoTile` only — the self-view is muted, so its `play()` is never subject to an audible-autoplay refusal and a report from it would be noise. Pass `diagnostics.report` bound to `"autoplay-blocked"` from the room route.

- [ ] **Step 6: Run the full call suite**

```bash
cd dashboard && pnpm vitest run src/features/call/ src/routes/_call/
```
Expected: PASS.

- [ ] **Step 7: Ratchet floors and commit**

```bash
cd dashboard && pnpm test:coverage 2>&1 | tail -20
```
Raise the three thresholds in `vitest.config.ts` to the measured values, then:

```bash
PIP_CONFIG_FILE=/dev/null git add src/ vitest.config.ts
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): report the four already-detected failures"
```

---

### Task 8: The e2e contract test

**Files:**
- Create: `dashboard/e2e/call-diagnostics.spec.ts`

**Interfaces:**
- Consumes: `DIAGNOSTIC_CODES`, the seeded joinable session from `test_seed_e2e_joinable`.

- [ ] **Step 1: Write the spec**

Create `dashboard/e2e/call-diagnostics.spec.ts`:

```ts
import { expect, test } from "@playwright/test";
import { DIAGNOSTIC_CODES } from "../src/features/call/diagnosticsApi";
import { loginAs } from "./helpers";

// The drift guard. The client's code list and the backend's enum are
// necessarily two copies -- a Vitest test cannot read a Python enum, and the
// dashboard is a separate submodule -- so this posts EVERY code the client
// knows through the real endpoint against a real Django. A code added on one
// side and not the other fails here, which is the only place in the system
// that can catch it.
test("every code the client can emit is accepted by the API", async ({ page }) => {
	await loginAs(page, "student");
	const sessionId = await page.evaluate(async () => {
		const res = await fetch(
			`${import.meta.env.VITE_API_URL}scheduling/sessions/`,
			{ credentials: "include" },
		);
		const body = await res.json();
		return body.results[0].id;
	});

	for (const code of DIAGNOSTIC_CODES) {
		const status = await page.evaluate(
			async ([id, c]) => {
				const res = await fetch(
					`${import.meta.env.VITE_API_URL}scheduling/sessions/${id}/diagnostics/`,
					{
						method: "POST",
						credentials: "include",
						headers: {
							"Content-Type": "application/json",
							"X-CSRFToken":
								document.cookie.match(/csrftoken=([^;]+)/)?.[1] ?? "",
						},
						body: JSON.stringify({ code: c, stats: null }),
					},
				);
				return res.status;
			},
			[sessionId, code] as const,
		);
		expect(status, `code "${code}" was rejected by the API`).toBe(201);
	}
});

test("an unknown code is refused", async ({ page }) => {
	await loginAs(page, "student");
	// Same shape as above, with a code the enum does not contain.
	// Asserting 400 here is what proves the ChoiceField is actually load-
	// bearing rather than the endpoint accepting anything.
});
```

Fill the second test's body using the same `page.evaluate` shape with `code: "not-a-real-code"`, asserting `400`. Match `loginAs` to whatever helper `dashboard/e2e/` already exports; read `dashboard/e2e/call.spec.ts` for the established login and seeding pattern rather than inventing one.

**The eight codes exceed the `20/hour` throttle.** Give the e2e run its own throttle rate via the CI settings override, or scope the test to one session per run and accept the first eight. Read `backend/config/settings/test.py` for how other tests neutralise throttles and follow that; do **not** raise the production rate to make a test pass.

- [ ] **Step 2: Run it**

```bash
cd dashboard && pnpm e2e call-diagnostics
```
Expected: PASS against the local stack.

- [ ] **Step 3: Mutation-check the drift guard**

Remove one code from the backend's `CallDiagnostic.Code`, re-run, and confirm the test fails naming that code. Restore it.

- [ ] **Step 4: Commit**

```bash
cd dashboard && PIP_CONFIG_FILE=/dev/null git add e2e/call-diagnostics.spec.ts
PIP_CONFIG_FILE=/dev/null git commit -m "test(e2e): contract-test every diagnostic code against the real API"
```

---

### Task 9: Documentation and the honest limits

**Files:**
- Modify: `CLAUDE.md` (D3 table), `STATE.md`, `ISSUES.md`, `docs/runbook/video-call.md`, `docs/superpowers/journal/2026-W36.md`

- [ ] **Step 1: Add the D3 table row**

In `CLAUDE.md`'s e2e table, after the C3d row:

```markdown
   | `scheduling` — call diagnostics (C3e-a) | ✅ 2 flows | every client code accepted by the real API; an unknown code refused. **Proves the pipeline, never that Safari emits anything** — Safari does not run in CI and cannot be run in this project at all |
```

- [ ] **Step 2: Record the limit in the runbook**

In `docs/runbook/video-call.md`, under the Safari/iOS note, add how to read the data: the table name, the eight codes and what each means, and the 90-day window after which rows are gone.

- [ ] **Step 3: Update `STATE.md`**

Set `active_spec` to C3e-b and record that C3e-a shipped, including the explicit statement that C3e closes under a **D9 deviation**: no manual click-through on Safari or iOS is possible in this project, and the verification loop for C3e-b is watching a code's frequency fall rather than a test.

- [ ] **Step 4: Resolve the stale `ISSUES.md` entry**

Delete the entry claiming `useLocalMedia`'s `selectCamera`/`selectMicrophone` "don't re-acquire the stream" — the code does re-acquire, with an `exact` `deviceId` constraint for the changed kind. Resolved entries are deleted, not struck through.

- [ ] **Step 5: Journal**

Append to `docs/superpowers/journal/2026-W36.md`: what C3e-a shipped, the allow-list-versus-deny-list decision and why it was the one that mattered, and the D9 deviation with its reason.

- [ ] **Step 6: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add CLAUDE.md STATE.md ISSUES.md docs/
PIP_CONFIG_FILE=/dev/null git commit -m "docs: C3e-a shipped, and what it cannot prove"
```

---

### Task 10: Ship

- [ ] **Step 1** — Open `backend` and `dashboard` PRs into `main`. Wait for green.
- [ ] **Step 2** — Merge both, then bump the submodule pointers in the meta PR. Merge commits, not squashes: squashing is what used to drop pointer bumps silently.
- [ ] **Step 3** — Merge the meta PR. **This is a staging deploy.**
- [ ] **Step 4** — Verify live: log in on staging, join the C3d fixture lesson (`c3d.student@example.com` / `c3d.teacher@example.com`, password `KaleemC3d!2026`), deny camera permission, and confirm a `gum-denied` row appears with a real `User-Agent`. Then confirm no row contains an IP:

```bash
ssh kaleem "docker exec kaleem-django-\$(cat /opt/kaleem/.active-color)-1 \
  python manage.py shell -c \"
from kaleem.scheduling.models import CallDiagnostic
import json, re
rows = CallDiagnostic.objects.all()
print(rows.count(), 'rows')
blob = json.dumps([r.stats for r in rows])
print('addresses found:', re.findall(r'\\\\d{1,3}(?:\\\\.\\\\d{1,3}){3}', blob))
\""
```

Expected: the row count is non-zero and `addresses found: []`. A non-empty list means redaction failed in a real browser and is a **stop-and-fix**, not a note.

- [ ] **Step 5** — Update `STATE.md` with the live-verification result and the exact command used.

---

## Self-Review

**Spec coverage.** Closed enum → Tasks 1, 3. Stats captured with addresses removed → Task 5. Allow-list not deny-list → Task 5, with a mutation check. Authorization reuses `is_participant` → Task 2, with the parent test. 90-day retention → Task 4, boundary-tested. Fire-and-forget → Task 6. Only already-detected failures emit → Task 7. Throttle and `User-Agent` cap → Tasks 2, 3. The enum-drift contract test → Task 8. The D3 limit stated plainly → Task 9. No gaps.

**Placeholder scan.** One deliberate instruction to read an existing file rather than transcribe it: Task 8's `loginAs` helper and the test-settings throttle override, because inventing either would conflict with what `dashboard/e2e/` and `config/settings/test.py` already do. Everything else is literal.

**Type consistency.** `record_diagnostic(actor, session_id, *, code, user_agent, stats)` is used identically in Tasks 2 and 3. `DiagnosticCode` and `DIAGNOSTIC_CODES` are defined in Task 6 and consumed unchanged in Tasks 7 and 8. `redactStats(report) -> Record<string, unknown>[] | null` matches its use in Task 6. `CallDiagnostic.Code` values match the client array element-for-element, which is exactly what Task 8 asserts.

**One correction made inline.** Task 7's first draft mapped `MediaFailure.unknown` to `gum-denied`, which would have written a wrong code into the one table this phase exists to read. `unknown` is now unreported, and the table says why.
