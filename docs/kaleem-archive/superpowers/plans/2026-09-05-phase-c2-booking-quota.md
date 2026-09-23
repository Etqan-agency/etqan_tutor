# Phase C2 — Booking + Quota Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A student claims a weekly slot with the teacher C1 matched them to; a daily job materialises that billing cycle's sessions up to quota; either side can cancel, and a cancellation 24h+ ahead returns the unit — always, if the teacher cancelled.

**Architecture:** Two new models in `scheduling` (`RecurringSlot`, `Session`). Slot times are stored in **UTC** because a slot belongs to two people in two timezones. Quota is a filter over `Session` rows carrying the billing period's `cycle_end` and a stored `consumes_quota` flag — not a status inference. Generation is a **daily idempotent Celery beat task** that fills forward from today to the period end and stops at quota, so quota holds by construction rather than by a check.

**Tech Stack:** Django 5 + DRF + Celery/beat (backend submodule), React 19 + TanStack Router/Query + Tailwind + shadcn (dashboard submodule), Playwright, pytest, vitest, import-linter.

**Spec:** `docs/superpowers/specs/2026-09-05-phase-c2-booking-quota-design.md` — read it before Task 1.

## Global Constraints

- **Two repos, two PRs.** Tasks 1–10 in `backend` (trunk `main`); Tasks 11–15 in `dashboard` (trunk `main`). Both on `feat/phase-c2-booking-quota` → PR → trunk. Never commit to a trunk. Never `--no-verify`.
- **Backend commands run from the meta root `/home/abdulkhalek/Projects/kaleem`** against the already-running stack: `docker compose -f docker-compose.local.yml exec -T django <cmd>`. Git commands run inside the submodule directory. Dashboard commands run from `/home/abdulkhalek/Projects/kaleem/dashboard` with `pnpm`.
- **Commit backend changes with `PIP_CONFIG_FILE=/dev/null git commit …`** — a dead pip proxy otherwise breaks the pre-commit hook. Dashboard uses a normal `git commit`.
- **Coverage floors are ratchets (ADR-0026), raise them if this slice lifts coverage:** backend `fail_under = 97.2` with `precision = 1` in `pyproject.toml` (**`precision` is load-bearing** — coverage.py rounds the total to that many decimals before comparing, so removing it makes a fractional floor fail); dashboard 92.5 lines / 88.5 branches / 85 functions / 92.5 statements in `vitest.config.ts`.
- **Every route under `/api/v1/`,** mounted via `config/api_router.py`. `backend/tests/test_api_versioning_is_enforced.py` fails otherwise.
- **No module imports another module's models.** `scheduling → billing` and `scheduling → curriculum` are open (ADR-0033) through `<module>.services` only. `lint-imports` must stay 10 kept / 0 broken with no warnings; a test-only model import needs its `ignore_imports` line added in the same commit.
- **No business logic on models. No bare `except Exception`. No `print()`.** Typed exceptions (`ValidationError` 400, `PermissionDeniedError` 403, `NotFoundError` 404, `ConflictError` 409) propagate to the DRF handler; the error body is `{"detail": …}` with no `code` key.
- **No response payload may contain an email address** (ADR-0023). Display names only.
- **Weekday 0 is SATURDAY** throughout (`WEEKDAY_LABELS` in `scheduling/models.py`). Python's `date.weekday()` has Monday 0 / Saturday 5, so the conversion is `python_weekday = (5 + kaleem_weekday) % 7`.
- **Sessions are 60 minutes** in C2, as a named constant.
- **Frontend:** i18n keys in both `src/locales/en/common.json` and `src/locales/ar/common.json` with **real Arabic** (Arabic needs six plural categories where English needs two); RTL verified; all style values from design tokens — never a raw hex, `color-mix`, or an arbitrary `[...]` value; WCAG 2.2 AA including announcing status changes.
- **Fixture identifiers must be realistic in shape** — a fake Stripe id is `sub_` plus 24 characters.

---

### Task 1: `billing.get_session_allowance`

Quota needs two numbers from billing: how many sessions the plan allows, and which cycle we are in. They live in `billing`, so `scheduling` asks for them rather than reaching for the models.

**Files:**
- Modify: `kaleem/billing/services.py`
- Test: `kaleem/billing/tests/test_entitlement.py`

**Interfaces:**
- Produces: `get_session_allowance(user) -> tuple[int, datetime] | None` — `(sessions_per_cycle, current_period_end)` for the user's live subscription, or `None` when they have no entitlement. Resolves a child through a parent's family plan exactly as `is_entitled_to` does.

- [ ] **Step 1: Write the failing tests**

Append to `kaleem/billing/tests/test_entitlement.py`, following the fixtures already in that file and `kaleem/billing/tests/conftest.py` (`family_plan`, `individual_plan`, `parent`, `adult_student`, `child`):

```python
def test_session_allowance_is_none_without_a_subscription(adult_student):
    assert services.get_session_allowance(adult_student) is None


def test_session_allowance_returns_the_plans_limit_and_period_end(
    adult_student, individual_plan
):
    subscription = _active_subscription(adult_student, individual_plan)

    limit, cycle_end = services.get_session_allowance(adult_student)

    assert limit == individual_plan.sessions_per_cycle
    assert cycle_end == subscription.current_period_end


def test_a_child_inherits_the_parents_family_allowance(child, parent, family_plan):
    subscription = _active_subscription(parent, family_plan)

    limit, cycle_end = services.get_session_allowance(child)

    assert limit == family_plan.sessions_per_cycle
    assert cycle_end == subscription.current_period_end


def test_session_allowance_is_none_when_the_subscription_is_unpaid(
    adult_student, individual_plan
):
    subscription = _active_subscription(adult_student, individual_plan)
    subscription.status = Subscription.Status.UNPAID
    subscription.save(update_fields=["status"])

    assert services.get_session_allowance(adult_student) is None
```

Add the helper next to them, using the real-shaped id convention:

```python
def _active_subscription(user, plan):
    return Subscription.objects.create(
        user=user,
        plan=plan,
        stripe_subscription_id=f"sub_{user.id:024d}",
        status=Subscription.Status.ACTIVE,
        current_period_end=timezone.now() + dt.timedelta(days=30),
    )
```

If that file already defines an equivalent helper or imports, reuse rather than duplicate.

- [ ] **Step 2: Run and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/billing/tests/test_entitlement.py -v`
Expected: FAIL — `AttributeError: module 'kaleem.billing.services' has no attribute 'get_session_allowance'`.

- [ ] **Step 3: Implement**

Append to `kaleem/billing/services.py`:

```python
def get_session_allowance(user) -> tuple[int, dt.datetime] | None:
    """How many sessions this cycle, and which cycle — or None if not covered.

    The cycle is identified by its END rather than a start-and-end pair:
    `Subscription` mirrors `current_period_end` from the provider and has no
    `current_period_start`, so keying on a start would mean a new field, its
    mirroring, and a backfill of every existing row — a billing migration in
    service of a scheduling counter. The end alone identifies a cycle, and it is
    the only bound generation needs.

    Resolves a child through a parent's family plan, exactly as `is_entitled_to`
    does, so a child of a subscribed parent gets that plan's allowance.
    """
    subscription = _live_subscription_for_user_id(user.id)
    if subscription is None:
        for parent_id in identity_services.get_parent_user_ids(user.id):
            candidate = _live_subscription_for_user_id(parent_id)
            if candidate is not None and (
                candidate.plan.plan_type == SubscriptionPlan.PlanType.FAMILY
            ):
                subscription = candidate
                break
    if subscription is None or not _is_paid_through(subscription):
        return None
    if subscription.current_period_end is None:
        return None
    return subscription.plan.sessions_per_cycle, subscription.current_period_end
```

- [ ] **Step 4: Run the tests**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/billing/tests/ -v`
Expected: all pass, including the pre-existing entitlement tests.

- [ ] **Step 5: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git commit -am "feat(billing): expose the session allowance and its cycle

Keyed by the period END, because Subscription mirrors current_period_end
and has no start — and the end is the only bound generation needs."
```

---

### Task 2: One overlap helper, two callers

C1's matcher computes overlap *minutes*; C2 needs the *intervals* to offer bookable times. Two implementations of "when are these two both free" that could disagree is the exact drift C1's final review flagged, so the computation is extracted once and `overlap_minutes` becomes its caller.

**Files:**
- Modify: `kaleem/scheduling/matching.py`
- Test: `kaleem/scheduling/tests/test_matching_eligibility.py`

**Interfaces:**
- Produces: `overlap_intervals(teacher, student, reference_date) -> list[tuple[datetime, datetime]]` — UTC intervals where both are free, sorted by start.
- `overlap_minutes(teacher, student, reference_date) -> int` keeps its exact signature and behaviour.

- [ ] **Step 1: Write the failing test**

Append to `kaleem/scheduling/tests/test_matching_eligibility.py` (fixtures `teacher`, `student`, `_slot` and `REFERENCE` live in `kaleem/scheduling/tests/conftest.py`):

```python
def test_overlap_intervals_returns_the_shared_window(teacher, student):
    # teacher Sat 09:00-12:00 UTC, student Sat 10:00-11:00 UTC
    [(start, end)] = matching.overlap_intervals(teacher, student, REFERENCE)

    assert (end - start) == dt.timedelta(hours=1)
    assert start.hour == 10
    assert start.tzinfo is not None


def test_overlap_intervals_is_empty_when_they_never_coincide(teacher, student):
    from kaleem.scheduling.services import set_availability

    set_availability(
        teacher,
        [{"weekday": 3, "start_time": dt.time(9), "end_time": dt.time(12)}],
        timezone="UTC",
    )
    teacher.refresh_from_db()

    assert matching.overlap_intervals(teacher, student, REFERENCE) == []


def test_overlap_minutes_agrees_with_the_intervals(teacher, student):
    intervals = matching.overlap_intervals(teacher, student, REFERENCE)
    total = sum(int((e - s).total_seconds() // 60) for s, e in intervals)

    assert matching.overlap_minutes(teacher, student, REFERENCE) == total
```

The third test is the point of the task: it pins the two to each other, so a future change to one that does not change the other fails.

- [ ] **Step 2: Run and watch it fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_matching_eligibility.py -v`
Expected: FAIL — `AttributeError: ... has no attribute 'overlap_intervals'`.

- [ ] **Step 3: Implement**

In `kaleem/scheduling/matching.py`, add `overlap_intervals` and rewrite `overlap_minutes` to consume it. Keep `overlap_minutes`' existing docstring, which explains why UTC instants rather than wall-clock pairs:

```python
def overlap_intervals(
    teacher, student, reference_date: dt.date
) -> list[tuple[dt.datetime, dt.datetime]]:
    """UTC windows where both are free, sorted by start.

    The single source of truth for "when are these two both available".
    `overlap_minutes` sums this rather than recomputing it: matching and booking
    must never be able to disagree about when a lesson could happen.
    """
    teacher_intervals = to_utc_intervals(teacher, reference_date)
    student_intervals = to_utc_intervals(student, reference_date)
    out: list[tuple[dt.datetime, dt.datetime]] = []
    for t_start, t_end in teacher_intervals:
        for s_start, s_end in student_intervals:
            start = max(t_start, s_start)
            end = min(t_end, s_end)
            if end > start:
                out.append((start, end))
    out.sort()
    return out


def overlap_minutes(teacher, student, reference_date: dt.date) -> int:
    """Total weekly overlap, in UTC.

    Compared as instants rather than as (weekday, wall clock) pairs: kaleem's
    teachers and students are in different countries, and 10:00 in Cairo is not
    10:00 in London. Comparing local times would pair people who are asleep.
    """
    return sum(
        int((end - start).total_seconds() // 60)
        for start, end in overlap_intervals(teacher, student, reference_date)
    )
```

- [ ] **Step 4: Run the whole matching suite**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/ -v`
Expected: all pass — every existing eligibility and rank test still green, since `overlap_minutes` is behaviour-identical.

- [ ] **Step 5: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git commit -am "refactor(scheduling): one overlap computation, two callers

Booking needs the intervals; matching needs their total. Two copies that
could disagree about when two people are both free is the drift C1's final
review flagged — a test now pins them to each other."
```

---

### Task 3: `RecurringSlot` and `Session`

**Files:**
- Modify: `kaleem/scheduling/models.py`
- Create: the migration `makemigrations` generates
- Test: `kaleem/scheduling/tests/test_booking_models.py`

**Interfaces:**
- Produces: `RecurringSlot` (`.Status.ACTIVE|ENDED`), `Session` (`.Status.SCHEDULED|COMPLETED|CANCELLED`), and the constant `SESSION_DURATION_MINUTES = 60`.

- [ ] **Step 1: Write the failing test**

Create `kaleem/scheduling/tests/test_booking_models.py`:

```python
import datetime as dt

import pytest
from django.db import IntegrityError
from django.db import transaction
from django.utils import timezone

from kaleem.scheduling.models import RecurringSlot
from kaleem.scheduling.models import Session

pytestmark = pytest.mark.django_db


def test_only_one_active_slot_per_assignment(assignment):
    RecurringSlot.objects.create(
        assignment=assignment, weekday=0, start_time=dt.time(10)
    )
    with pytest.raises(IntegrityError), transaction.atomic():
        RecurringSlot.objects.create(
            assignment=assignment, weekday=1, start_time=dt.time(11)
        )


def test_a_new_slot_is_allowed_once_the_old_one_ended(assignment):
    first = RecurringSlot.objects.create(
        assignment=assignment, weekday=0, start_time=dt.time(10)
    )
    first.status = RecurringSlot.Status.ENDED
    first.save()

    RecurringSlot.objects.create(
        assignment=assignment, weekday=1, start_time=dt.time(11)
    )

    assert RecurringSlot.objects.filter(assignment=assignment).count() == 2


def test_a_teacher_cannot_hold_two_active_slots_at_one_time(
    assignment, other_assignment
):
    RecurringSlot.objects.create(
        assignment=assignment, weekday=0, start_time=dt.time(10)
    )
    with pytest.raises(IntegrityError), transaction.atomic():
        RecurringSlot.objects.create(
            assignment=other_assignment, weekday=0, start_time=dt.time(10)
        )


def test_a_session_is_unique_per_assignment_and_instant(assignment):
    when = timezone.now() + dt.timedelta(days=1)
    Session.objects.create(
        assignment=assignment,
        slot=RecurringSlot.objects.create(
            assignment=assignment, weekday=0, start_time=dt.time(10)
        ),
        starts_at=when,
        cycle_end=when + dt.timedelta(days=20),
    )
    with pytest.raises(IntegrityError), transaction.atomic():
        Session.objects.create(
            assignment=assignment,
            slot=RecurringSlot.objects.get(assignment=assignment),
            starts_at=when,
            cycle_end=when + dt.timedelta(days=20),
        )


def test_a_session_consumes_quota_by_default(assignment):
    slot = RecurringSlot.objects.create(
        assignment=assignment, weekday=0, start_time=dt.time(10)
    )
    when = timezone.now() + dt.timedelta(days=1)

    session = Session.objects.create(
        assignment=assignment, slot=slot, starts_at=when, cycle_end=when
    )

    assert session.consumes_quota is True
    assert session.status == Session.Status.SCHEDULED
    assert session.duration_minutes == 60
```

Both `assignment` and `other_assignment` go in `kaleem/scheduling/tests/conftest.py`, NOT in this
test file — Tasks 4, 5, 6 and 7 all need `assignment`, and a fixture defined in one test module is
invisible to the others. `assignment` is an `ACTIVE` `TeacherAssignment` for `student` + `teacher`
+ `quran`, using the existing `request_row` as its `source_request`:

```python
@pytest.fixture
def assignment(teacher, student, quran, request_row):
    return TeacherAssignment.objects.create(
        student=student, teacher=teacher, subject=quran, source_request=request_row
    )
```

Add an `other_assignment` fixture — the SAME teacher with a DIFFERENT student, since that is what the teacher-conflict test needs. Build the second student the way the existing `student` fixture does, give it a `StudentProfile`, and create its own `MatchRequest` to satisfy `source_request`.

- [ ] **Step 2: Run and watch it fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_booking_models.py -v`
Expected: FAIL — `ImportError: cannot import name 'RecurringSlot'`.

- [ ] **Step 3: Write the models**

Append to `kaleem/scheduling/models.py`:

```python
# One length, named once. Not a plan field and not per-teacher: nothing in the
# product sells a different length yet, and the field is easy to add when
# something does.
SESSION_DURATION_MINUTES = 60


class RecurringSlot(models.Model):
    """A student's standing weekly time with their teacher.

    `start_time` is UTC, not a local wall-clock. `WeeklyAvailability` stores
    local times because it belongs to one person in one timezone; a slot belongs
    to TWO people in two zones, so a local time has no single meaning -- a
    student who travels would silently move their teacher's lesson.
    """

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        ENDED = "ended", "Ended"

    assignment = models.ForeignKey(
        TeacherAssignment, on_delete=models.CASCADE, related_name="slots"
    )
    # Denormalised from `assignment.teacher` so the double-booking invariant can
    # be a database constraint rather than only a service-layer check. Task 5
    # sets it and a test asserts the two agree.
    teacher = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="teaching_slots",
    )
    weekday = models.PositiveSmallIntegerField()  # 0=Sat .. 6=Fri
    start_time = models.TimeField()  # UTC
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.ACTIVE
    )
    created_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["teacher", "status"])]
        constraints = [
            models.UniqueConstraint(
                fields=["assignment"],
                condition=models.Q(status="active"),
                name="unique_active_slot_per_assignment",
            ),
            # Catches the exact-collision case in the database. Partial overlaps
            # (10:00 against 10:30) cannot be expressed as a unique index and are
            # enforced in the claiming transaction -- see Task 5.
            models.UniqueConstraint(
                fields=["teacher", "weekday", "start_time"],
                condition=models.Q(status="active"),
                name="unique_active_teacher_slot",
            ),
        ]

    def __str__(self):
        label = WEEKDAY_LABELS[self.weekday]
        return f"RecurringSlot<{self.assignment_id} {label} {self.start_time}Z>"


class Session(models.Model):
    """One lesson at one instant. A row exists on ordinary weeks, not only on
    deviating ones: C3 hangs a join link on it and B3 hangs a report on it."""

    class Status(models.TextChoices):
        SCHEDULED = "scheduled", "Scheduled"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"

    assignment = models.ForeignKey(
        TeacherAssignment, on_delete=models.CASCADE, related_name="sessions"
    )
    slot = models.ForeignKey(
        RecurringSlot, on_delete=models.PROTECT, related_name="sessions"
    )
    starts_at = models.DateTimeField()
    duration_minutes = models.PositiveSmallIntegerField(
        default=SESSION_DURATION_MINUTES
    )
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.SCHEDULED
    )
    cancelled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="cancelled_sessions",
    )
    cancelled_at = models.DateTimeField(null=True, blank=True)
    # The billing period this counts against, identified by its end.
    cycle_end = models.DateTimeField()
    # Stored, not inferred from status: a session cancelled 30 hours ahead and
    # one cancelled 30 minutes ahead are both CANCELLED and only the first
    # returns the unit. Storing it makes the quota count a filter and leaves an
    # audit trail of why a unit came back.
    consumes_quota = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["assignment", "starts_at"]),
            models.Index(fields=["status", "starts_at"]),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=["assignment", "starts_at"], name="unique_session_instant"
            )
        ]

    def __str__(self):
        return f"Session<{self.assignment_id} @{self.starts_at:%Y-%m-%d %H:%M}Z>"
```

- [ ] **Step 4: Generate and read the migration**

Run: `docker compose -f docker-compose.local.yml exec -T django python manage.py makemigrations scheduling`
Read the generated file and confirm both `RecurringSlot` constraints carry their `condition=`. A partial index silently generated as a plain one would forbid a student from ever claiming a second slot after ending their first.

- [ ] **Step 5: Run the tests**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_booking_models.py -v`
Expected: 5 passed.

- [ ] **Step 6: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): RecurringSlot and Session

Slot times are UTC because a slot belongs to two people in two timezones.
consumes_quota is stored rather than inferred, because cancelled-early and
cancelled-late are both CANCELLED and only one returns the unit."
```

---

### Task 4: The quota counter

**Files:**
- Create: `kaleem/scheduling/booking.py`
- Test: `kaleem/scheduling/tests/test_booking_quota.py`

**Interfaces:**
- Consumes: `billing_services.get_session_allowance(user)` (Task 1); `Session` (Task 3).
- Produces: `Quota` TypedDict (`limit: int`, `used: int`, `remaining: int`, `cycle_end: datetime`) and `get_quota(student) -> Quota | None` — `None` when the student has no entitlement.

Booking lives in its own module rather than in `matching.py` or `services.py`: matching answers "who", booking answers "when", and `services.py` is the availability editor's home. All three are re-exported nowhere — the API layer imports the module it needs directly, as C1 established.

- [ ] **Step 1: Write the failing tests**

Create `kaleem/scheduling/tests/test_booking_quota.py`:

```python
import datetime as dt

import pytest
from django.utils import timezone

from kaleem.scheduling import booking
from kaleem.scheduling.models import RecurringSlot
from kaleem.scheduling.models import Session

pytestmark = pytest.mark.django_db


def _session(assignment, slot, cycle_end, *, days_out=1, **kwargs):
    return Session.objects.create(
        assignment=assignment,
        slot=slot,
        starts_at=timezone.now() + dt.timedelta(days=days_out),
        cycle_end=cycle_end,
        **kwargs,
    )


@pytest.fixture
def slot(assignment):
    return RecurringSlot.objects.create(
        assignment=assignment,
        teacher_id=assignment.teacher_id,
        weekday=0,
        start_time=dt.time(10),
    )


def test_no_entitlement_means_no_quota(student):
    assert booking.get_quota(student) is None


def test_a_fresh_cycle_has_everything_remaining(student, entitled):
    subscription = entitled(student)

    quota = booking.get_quota(student)

    assert quota["limit"] == subscription.plan.sessions_per_cycle
    assert quota["used"] == 0
    assert quota["remaining"] == quota["limit"]
    assert quota["cycle_end"] == subscription.current_period_end


def test_scheduled_sessions_count_against_the_cycle(
    student, entitled, assignment, slot
):
    subscription = entitled(student)
    for day in (1, 8):
        _session(assignment, slot, subscription.current_period_end, days_out=day)

    assert booking.get_quota(student)["used"] == 2


def test_a_refunded_session_does_not_count(student, entitled, assignment, slot):
    subscription = entitled(student)
    _session(
        assignment,
        slot,
        subscription.current_period_end,
        status=Session.Status.CANCELLED,
        consumes_quota=False,
    )

    assert booking.get_quota(student)["used"] == 0


def test_a_late_cancellation_still_counts(student, entitled, assignment, slot):
    subscription = entitled(student)
    _session(
        assignment,
        slot,
        subscription.current_period_end,
        status=Session.Status.CANCELLED,
        consumes_quota=True,
    )

    assert booking.get_quota(student)["used"] == 1


def test_a_previous_cycles_sessions_do_not_count(
    student, entitled, assignment, slot
):
    subscription = entitled(student)
    _session(
        assignment,
        slot,
        subscription.current_period_end - dt.timedelta(days=30),
        days_out=-20,
    )

    assert booking.get_quota(student)["used"] == 0
```

- [ ] **Step 2: Run and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_booking_quota.py -v`
Expected: FAIL — `ModuleNotFoundError: kaleem.scheduling.booking`.

- [ ] **Step 3: Implement**

Create `kaleem/scheduling/booking.py`:

```python
"""Slots, sessions, and the quota that limits them.

Separate from `matching.py` on purpose: matching answers *who* teaches a
student, booking answers *when*. They share the overlap computation and nothing
else.
"""

from __future__ import annotations

import datetime as dt
from typing import TypedDict

from kaleem.billing import services as billing_services
from kaleem.scheduling.models import Session


class Quota(TypedDict):
    limit: int
    used: int
    remaining: int
    cycle_end: dt.datetime


def _consumed(student_id: int, cycle_end: dt.datetime) -> int:
    """Sessions counting against this cycle, in any status.

    Status is deliberately not part of the filter: a completed session and a
    late-cancelled one both consumed their unit, and `consumes_quota` is the
    single fact that says whether one did.
    """
    return Session.objects.filter(
        assignment__student_id=student_id,
        cycle_end=cycle_end,
        consumes_quota=True,
    ).count()


def get_quota(student) -> Quota | None:
    allowance = billing_services.get_session_allowance(student)
    if allowance is None:
        return None
    limit, cycle_end = allowance
    used = _consumed(student.id, cycle_end)
    return {
        "limit": limit,
        "used": used,
        "remaining": max(0, limit - used),
        "cycle_end": cycle_end,
    }
```

`remaining` is floored at zero rather than allowed to go negative: an admin who creates a session by hand should not make the number nonsensical.

- [ ] **Step 4: Run the tests**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_booking_quota.py -v`
Expected: 6 passed.

- [ ] **Step 5: Verify the boundary**

Run: `docker compose -f docker-compose.local.yml exec -T django lint-imports`
Expected: 10 kept, 0 broken — `booking.py` imports `billing.services`, never `billing.models`.

- [ ] **Step 6: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): the per-cycle session quota

Counted by cycle_end and consumes_quota, in any status: a completed session
and a late-cancelled one both spent their unit."
```

---

### Task 5: Claiming a slot, and the double-booking race

**Files:**
- Modify: `kaleem/scheduling/booking.py`
- Test: `kaleem/scheduling/tests/test_booking_claim.py`

**Interfaces:**
- Consumes: `matching.overlap_intervals` (Task 2); `RecurringSlot` (Task 3).
- Produces:
  - `slot_options(student, reference_date) -> list[SlotOption]` where `SlotOption` is a TypedDict with `weekday: int`, `start_time: time` (UTC), `starts_at: datetime` (the next UTC instant, for display)
  - `claim_slot(actor, weekday: int, start_time: time, *, reference_date) -> RecurringSlot`
  - `end_slot(actor, slot_id: int, *, now=None) -> None`

- [ ] **Step 1: Write the failing tests**

Create `kaleem/scheduling/tests/test_booking_claim.py`:

```python
import datetime as dt

import pytest

from kaleem.platform.exceptions import ConflictError
from kaleem.platform.exceptions import PermissionDeniedError
from kaleem.platform.exceptions import ValidationError
from kaleem.scheduling import booking
from kaleem.scheduling.models import RecurringSlot
from kaleem.scheduling.models import Session

pytestmark = pytest.mark.django_db

REFERENCE = dt.date(2026, 9, 7)  # a Monday; weekday 0 is the Saturday before


def test_options_are_inside_the_shared_window(student, assignment):
    options = booking.slot_options(student, REFERENCE)

    # teacher Sat 09:00-12:00 UTC, student Sat 10:00-11:00 UTC -> one 60-minute
    # start at 10:00 only; 10:30 would run past the student's window.
    assert [(o["weekday"], o["start_time"]) for o in options] == [(0, dt.time(10))]


def test_a_student_with_no_assignment_gets_no_options(other_student):
    assert booking.slot_options(other_student, REFERENCE) == []


def test_options_are_computed_across_a_timezone_difference(
    student, teacher, assignment
):
    """The two parties are in different countries; the shared window is the
    UTC intersection, not the intersection of their wall-clocks."""
    from kaleem.scheduling.services import set_availability

    # Teacher 09:00-13:00 in Cairo (UTC+3) == 06:00-10:00 UTC.
    set_availability(
        teacher,
        [{"weekday": 0, "start_time": dt.time(9), "end_time": dt.time(13)}],
        timezone="Africa/Cairo",
    )
    teacher.refresh_from_db()
    # Student 09:00-11:00 in London (UTC+1 in September) == 08:00-10:00 UTC.
    set_availability(
        student,
        [{"weekday": 0, "start_time": dt.time(9), "end_time": dt.time(11)}],
        timezone="Europe/London",
    )
    student.refresh_from_db()

    options = booking.slot_options(student, REFERENCE)

    # Shared window is 08:00-10:00 UTC -> two whole-hour starts.
    assert [o["start_time"] for o in options] == [dt.time(8), dt.time(9)]


def test_claiming_creates_an_active_slot_carrying_the_teacher(student, assignment):
    slot = booking.claim_slot(student, 0, dt.time(10), reference_date=REFERENCE)

    assert slot.status == RecurringSlot.Status.ACTIVE
    assert slot.teacher_id == assignment.teacher_id
    assert slot.assignment_id == assignment.id


def test_claiming_a_time_outside_the_shared_window_is_refused(student, assignment):
    with pytest.raises(ValidationError):
        booking.claim_slot(student, 0, dt.time(6), reference_date=REFERENCE)


def test_a_second_student_cannot_take_the_teachers_time(
    student, other_student, assignment, other_assignment
):
    booking.claim_slot(student, 0, dt.time(10), reference_date=REFERENCE)

    with pytest.raises(ConflictError):
        booking.claim_slot(other_student, 0, dt.time(10), reference_date=REFERENCE)


def test_a_partial_overlap_also_conflicts(
    student, other_student, assignment, other_assignment
):
    # 10:30 starts inside the 10:00-11:00 lesson. The unique index cannot see
    # this -- only the in-transaction scan can.
    booking.claim_slot(student, 0, dt.time(10), reference_date=REFERENCE)

    with pytest.raises(ConflictError):
        booking.claim_slot(other_student, 0, dt.time(10, 30), reference_date=REFERENCE)


def test_a_student_cannot_hold_two_slots(student, assignment):
    booking.claim_slot(student, 0, dt.time(10), reference_date=REFERENCE)

    with pytest.raises(ConflictError):
        booking.claim_slot(student, 0, dt.time(10), reference_date=REFERENCE)


def test_a_stranger_cannot_end_a_slot(student, other_student, assignment):
    slot = booking.claim_slot(student, 0, dt.time(10), reference_date=REFERENCE)

    with pytest.raises(PermissionDeniedError):
        booking.end_slot(other_student, slot.id)


def test_ending_a_slot_cancels_its_future_sessions_under_the_same_rule(
    student, assignment, entitled
):
    from django.utils import timezone

    subscription = entitled(student)
    slot = booking.claim_slot(student, 0, dt.time(10), reference_date=REFERENCE)
    now = timezone.now()
    soon = Session.objects.create(
        assignment=assignment,
        slot=slot,
        starts_at=now + dt.timedelta(hours=2),
        cycle_end=subscription.current_period_end,
    )
    later = Session.objects.create(
        assignment=assignment,
        slot=slot,
        starts_at=now + dt.timedelta(days=3),
        cycle_end=subscription.current_period_end,
    )

    booking.end_slot(student, slot.id, now=now)

    soon.refresh_from_db()
    later.refresh_from_db()
    slot.refresh_from_db()
    assert slot.status == RecurringSlot.Status.ENDED
    assert soon.status == Session.Status.CANCELLED
    assert soon.consumes_quota is True  # under 24h: the unit is spent
    assert later.status == Session.Status.CANCELLED
    assert later.consumes_quota is False  # 24h+ out: refunded
```

- [ ] **Step 2: Run and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_booking_claim.py -v`
Expected: FAIL — `AttributeError: ... has no attribute 'slot_options'`.

- [ ] **Step 3: Implement**

Append to `kaleem/scheduling/booking.py`:

```python
MINUTES_PER_WEEK = 7 * 24 * 60


def _weekly_minute(weekday: int, start_time: dt.time) -> int:
    return weekday * 24 * 60 + start_time.hour * 60 + start_time.minute


def _conflicts(a_weekday, a_time, b_weekday, b_time, duration: int) -> bool:
    """Do two weekly slots of `duration` minutes overlap?

    Compared as a circular distance so a slot late on Friday and one early on
    Saturday are seen as adjacent -- the week wraps, and a Friday 23:30 lesson
    really does run into Saturday.
    """
    gap = abs(_weekly_minute(a_weekday, a_time) - _weekly_minute(b_weekday, b_time))
    circular_gap = min(gap, MINUTES_PER_WEEK - gap)
    return circular_gap < duration


def _active_assignment(student):
    return (
        TeacherAssignment.objects.filter(
            student=student, status=TeacherAssignment.Status.ACTIVE
        )
        .select_related("subject")
        .first()
    )


def slot_options(student, reference_date: dt.date) -> list[SlotOption]:
    """Weekly start times where both are free for a whole session and the
    teacher is not already booked."""
    assignment = _active_assignment(student)
    if assignment is None:
        return []
    teacher = identity_services.get_user(assignment.teacher_id)
    taken = list(
        RecurringSlot.objects.filter(
            teacher_id=assignment.teacher_id, status=RecurringSlot.Status.ACTIVE
        ).values_list("weekday", "start_time")
    )
    duration = dt.timedelta(minutes=SESSION_DURATION_MINUTES)
    options: list[SlotOption] = []
    for window_start, window_end in matching.overlap_intervals(
        teacher, student, reference_date
    ):
        candidate = window_start
        while candidate + duration <= window_end:
            weekday = _kaleem_weekday(candidate)
            start_time = candidate.time()
            if not any(
                _conflicts(
                    weekday, start_time, t_day, t_time, SESSION_DURATION_MINUTES
                )
                for t_day, t_time in taken
            ):
                options.append(
                    {
                        "weekday": weekday,
                        "start_time": start_time,
                        "starts_at": candidate,
                    }
                )
            candidate += dt.timedelta(minutes=SESSION_DURATION_MINUTES)
    return options


@transaction.atomic
def claim_slot(actor, weekday: int, start_time: dt.time, *, reference_date: dt.date):
    """Claim a standing weekly time.

    The double-booking race is closed by locking every ACTIVE assignment of the
    teacher before scanning their slots. Locking the slot rows themselves would
    not do it: `select_for_update` over a queryset that matches nothing locks
    nothing, so two students claiming a teacher's FIRST slot would both see an
    empty scan. Every claimant necessarily has an assignment with that teacher,
    so that set is never empty and the two transactions serialise on it.
    """
    assignment = _active_assignment(actor)
    if assignment is None:
        raise PermissionDeniedError("claim a slot without an assigned teacher")

    list(
        TeacherAssignment.objects.select_for_update()
        .filter(
            teacher_id=assignment.teacher_id, status=TeacherAssignment.Status.ACTIVE
        )
        .values_list("id", flat=True)
    )

    if RecurringSlot.objects.filter(
        assignment=assignment, status=RecurringSlot.Status.ACTIVE
    ).exists():
        raise ConflictError("You already have a weekly time with this teacher.")

    if not any(
        option["weekday"] == weekday and option["start_time"] == start_time
        for option in slot_options(actor, reference_date)
    ):
        raise ValidationError(
            "That time is not available for both of you.", field="start_time"
        )

    for taken_day, taken_time in RecurringSlot.objects.filter(
        teacher_id=assignment.teacher_id, status=RecurringSlot.Status.ACTIVE
    ).values_list("weekday", "start_time"):
        if _conflicts(
            weekday, start_time, taken_day, taken_time, SESSION_DURATION_MINUTES
        ):
            raise ConflictError("Your teacher is already booked at that time.")

    return RecurringSlot.objects.create(
        assignment=assignment,
        teacher_id=assignment.teacher_id,
        weekday=weekday,
        start_time=start_time,
    )


@transaction.atomic
def end_slot(actor, slot_id: int, *, now: dt.datetime | None = None) -> None:
    """End a standing time and cancel what it had scheduled.

    Future sessions go through the same 24-hour rule a manual cancellation
    does -- ending a slot must not become a way to reclaim a unit that a direct
    cancellation would have spent.
    """
    now = now or timezone.now()
    slot = RecurringSlot.objects.select_for_update().filter(id=slot_id).first()
    if slot is None:
        raise NotFoundError("Recurring slot", slot_id)
    assignment = slot.assignment
    if not _is_party(actor, assignment):
        raise PermissionDeniedError("end a slot you are not part of")

    for session in Session.objects.filter(
        slot=slot, status=Session.Status.SCHEDULED, starts_at__gt=now
    ):
        _apply_cancellation(session, actor=actor, now=now)

    slot.status = RecurringSlot.Status.ENDED
    slot.ended_at = now
    slot.save(update_fields=["status", "ended_at"])
```

Add to the module's imports and helpers:

```python
from django.db import transaction
from django.utils import timezone

from kaleem.identity import services as identity_services
from kaleem.platform.exceptions import ConflictError
from kaleem.platform.exceptions import NotFoundError
from kaleem.platform.exceptions import PermissionDeniedError
from kaleem.platform.exceptions import ValidationError
from kaleem.scheduling import matching
from kaleem.scheduling.models import SESSION_DURATION_MINUTES
from kaleem.scheduling.models import RecurringSlot
from kaleem.scheduling.models import TeacherAssignment


class SlotOption(TypedDict):
    weekday: int
    start_time: dt.time
    starts_at: dt.datetime


def _kaleem_weekday(moment: dt.datetime) -> int:
    """Python's Monday-0 weekday to kaleem's Saturday-0."""
    return (moment.weekday() - 5) % 7


def _is_party(actor, assignment) -> bool:
    if actor.id in (assignment.student_id, assignment.teacher_id):
        return True
    return identity_services.is_parent_of(actor.id, assignment.student_id)
```

`_apply_cancellation` is written in Task 6 and used here; implement Task 6 first if you are working out of order, or write `_apply_cancellation` as part of this task and leave Task 6 to add only the public `cancel_session`.

- [ ] **Step 4: Run the tests**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_booking_claim.py -v`
Expected: 9 passed.

- [ ] **Step 5: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): claim and end a weekly slot

The double-booking race locks the teacher's assignments, not their slots:
select_for_update over an empty queryset locks nothing, so two students
claiming a teacher's first slot would both see an empty scan."
```

---

### Task 6: Cancelling and completing

**Files:**
- Modify: `kaleem/scheduling/booking.py`
- Test: `kaleem/scheduling/tests/test_booking_cancel.py`

**Interfaces:**
- Produces:
  - `CANCELLATION_NOTICE = dt.timedelta(hours=24)`
  - `_apply_cancellation(session, *, actor, now) -> None` (module-private; Task 5 calls it)
  - `cancel_session(actor, session_id, *, now=None) -> Session`
  - `complete_session(actor, session_id, *, now=None) -> Session`

- [ ] **Step 1: Write the failing tests**

Create `kaleem/scheduling/tests/test_booking_cancel.py`:

```python
import datetime as dt

import pytest
from django.utils import timezone

from kaleem.platform.exceptions import ConflictError
from kaleem.platform.exceptions import PermissionDeniedError
from kaleem.scheduling import booking
from kaleem.scheduling.models import Session

pytestmark = pytest.mark.django_db


@pytest.fixture
def scheduled(assignment, slot, entitled, student):
    subscription = entitled(student)
    return Session.objects.create(
        assignment=assignment,
        slot=slot,
        starts_at=timezone.now() + dt.timedelta(days=3),
        cycle_end=subscription.current_period_end,
    )


def test_a_student_cancelling_early_gets_the_unit_back(student, scheduled):
    booking.cancel_session(student, scheduled.id)

    scheduled.refresh_from_db()
    assert scheduled.status == Session.Status.CANCELLED
    assert scheduled.consumes_quota is False
    assert scheduled.cancelled_by_id == student.id
    assert scheduled.cancelled_at is not None


def test_a_student_cancelling_late_spends_the_unit(student, scheduled):
    late = scheduled.starts_at - dt.timedelta(hours=23)

    booking.cancel_session(student, scheduled.id, now=late)

    scheduled.refresh_from_db()
    assert scheduled.consumes_quota is True


def test_exactly_24_hours_still_refunds(student, scheduled):
    on_the_line = scheduled.starts_at - dt.timedelta(hours=24)

    booking.cancel_session(student, scheduled.id, now=on_the_line)

    scheduled.refresh_from_db()
    assert scheduled.consumes_quota is False


def test_a_teacher_cancelling_late_still_refunds(teacher, scheduled):
    ten_minutes_before = scheduled.starts_at - dt.timedelta(minutes=10)

    booking.cancel_session(teacher, scheduled.id, now=ten_minutes_before)

    scheduled.refresh_from_db()
    assert scheduled.consumes_quota is False
    assert scheduled.cancelled_by_id == teacher.id


def test_a_parent_may_cancel_their_childs_session(parent_of_student, scheduled):
    booking.cancel_session(parent_of_student, scheduled.id)

    scheduled.refresh_from_db()
    assert scheduled.status == Session.Status.CANCELLED


def test_a_stranger_cannot_cancel(other_student, scheduled):
    with pytest.raises(PermissionDeniedError):
        booking.cancel_session(other_student, scheduled.id)


def test_cancelling_twice_is_a_conflict(student, scheduled):
    booking.cancel_session(student, scheduled.id)

    with pytest.raises(ConflictError):
        booking.cancel_session(student, scheduled.id)


def test_only_the_teacher_completes(student, teacher, scheduled):
    with pytest.raises(PermissionDeniedError):
        booking.complete_session(student, scheduled.id)

    booking.complete_session(teacher, scheduled.id)

    scheduled.refresh_from_db()
    assert scheduled.status == Session.Status.COMPLETED


def test_a_completed_session_cannot_then_be_cancelled(teacher, student, scheduled):
    booking.complete_session(teacher, scheduled.id)

    with pytest.raises(ConflictError):
        booking.cancel_session(student, scheduled.id)


def test_a_completed_session_keeps_consuming_its_unit(teacher, scheduled):
    booking.complete_session(teacher, scheduled.id)

    scheduled.refresh_from_db()
    assert scheduled.consumes_quota is True
```

Add a `parent_of_student` fixture to `kaleem/scheduling/tests/conftest.py`: a user with a `ParentProfile` linked to `student` via `ParentStudent`, following how `kaleem/billing/tests/conftest.py` builds its `parent`/`child` pair. Add a `slot` fixture there too if Task 4 did not already.

- [ ] **Step 2: Run and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_booking_cancel.py -v`
Expected: FAIL — `AttributeError: ... has no attribute 'cancel_session'`.

- [ ] **Step 3: Implement**

Append to `kaleem/scheduling/booking.py`:

```python
# The line between "you changed your plans" and "your teacher held that hour
# for you". A constant until a second value is actually wanted (OQ-C2-3).
CANCELLATION_NOTICE = dt.timedelta(hours=24)


def _apply_cancellation(session: Session, *, actor, now: dt.datetime) -> None:
    """Cancel one session and decide whether its unit comes back.

    A teacher's cancellation always refunds, at any notice: a student should not
    pay for their teacher's change of plans. Otherwise the unit returns only
    with `CANCELLATION_NOTICE` to spare -- exactly at the boundary counts as in
    time, because a rule that punishes the 24-hours-exactly case is one nobody
    can act on.
    """
    by_teacher = actor.id == session.assignment.teacher_id
    refunds = by_teacher or (session.starts_at - now) >= CANCELLATION_NOTICE
    session.status = Session.Status.CANCELLED
    session.cancelled_by = actor
    session.cancelled_at = now
    if refunds:
        session.consumes_quota = False
    session.save(
        update_fields=["status", "cancelled_by", "cancelled_at", "consumes_quota"]
    )


def _locked_session(session_id: int) -> Session:
    session = (
        Session.objects.select_for_update()
        .select_related("assignment")
        .filter(id=session_id)
        .first()
    )
    if session is None:
        raise NotFoundError("Session", session_id)
    return session


@transaction.atomic
def cancel_session(actor, session_id: int, *, now: dt.datetime | None = None):
    now = now or timezone.now()
    session = _locked_session(session_id)
    if not _is_party(actor, session.assignment):
        raise PermissionDeniedError("cancel a session you are not part of")
    if session.status != Session.Status.SCHEDULED:
        raise ConflictError("This session is no longer scheduled.")
    _apply_cancellation(session, actor=actor, now=now)
    return session


@transaction.atomic
def complete_session(actor, session_id: int, *, now: dt.datetime | None = None):
    """Mark a lesson as delivered. Teacher only -- they are the one who knows."""
    session = _locked_session(session_id)
    if actor.id != session.assignment.teacher_id:
        raise PermissionDeniedError("complete a session you are not teaching")
    if session.status != Session.Status.SCHEDULED:
        raise ConflictError("This session is no longer scheduled.")
    session.status = Session.Status.COMPLETED
    session.save(update_fields=["status"])
    return session
```

- [ ] **Step 4: Run the tests**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/ -v`
Expected: all pass, including Task 5's end-slot test which depends on `_apply_cancellation`.

- [ ] **Step 5: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): cancel and complete a session

A teacher's cancellation always refunds, at any notice. Exactly 24 hours
counts as in time -- a rule that punishes the boundary case is one nobody
can act on."
```

---

### Task 7: Generation

The core of the phase. Quota is enforced here **by construction** — nothing generates the fifth session of a four-session cycle — so a quota bug cannot produce an unpaid lesson.

**Files:**
- Modify: `kaleem/scheduling/booking.py`
- Test: `kaleem/scheduling/tests/test_booking_generation.py`

**Interfaces:**
- Produces: `generate_sessions(*, now=None) -> int` — number of sessions created; idempotent.

- [ ] **Step 1: Write the failing tests**

Create `kaleem/scheduling/tests/test_booking_generation.py`:

```python
import datetime as dt

import pytest
from django.utils import timezone

from kaleem.scheduling import booking
from kaleem.scheduling.models import RecurringSlot
from kaleem.scheduling.models import Session
from kaleem.scheduling.models import TeacherAssignment

pytestmark = pytest.mark.django_db


def test_an_unentitled_student_generates_nothing(assignment, slot):
    assert booking.generate_sessions() == 0
    assert Session.objects.count() == 0


def test_it_fills_the_cycle_up_to_quota(student, entitled, assignment, slot):
    subscription = entitled(student)  # sessions_per_cycle == 4
    subscription.current_period_end = timezone.now() + dt.timedelta(days=60)
    subscription.save(update_fields=["current_period_end"])

    created = booking.generate_sessions()

    # 60 days holds more than four Saturdays; quota stops it at four.
    assert created == 4
    assert Session.objects.count() == 4


def test_it_stops_at_the_period_end_when_that_comes_first(
    student, entitled, assignment, slot
):
    subscription = entitled(student)
    subscription.current_period_end = timezone.now() + dt.timedelta(days=10)
    subscription.save(update_fields=["current_period_end"])

    booking.generate_sessions()

    assert Session.objects.count() <= 2
    assert all(
        s.starts_at <= subscription.current_period_end for s in Session.objects.all()
    )


def test_it_is_idempotent(student, entitled, assignment, slot):
    entitled(student)

    booking.generate_sessions()
    before = Session.objects.count()
    second = booking.generate_sessions()

    assert second == 0
    assert Session.objects.count() == before


def test_every_session_lands_on_the_slots_weekday_and_time(
    student, entitled, assignment, slot
):
    entitled(student)

    booking.generate_sessions()

    for session in Session.objects.all():
        assert booking._kaleem_weekday(session.starts_at) == slot.weekday
        assert session.starts_at.time() == slot.start_time
        assert session.slot_id == slot.id


def test_generated_sessions_carry_the_current_cycle_end(
    student, entitled, assignment, slot
):
    subscription = entitled(student)

    booking.generate_sessions()

    assert {s.cycle_end for s in Session.objects.all()} == {
        subscription.current_period_end
    }


def test_an_ended_slot_generates_nothing(student, entitled, assignment, slot):
    entitled(student)
    slot.status = RecurringSlot.Status.ENDED
    slot.save(update_fields=["status"])

    assert booking.generate_sessions() == 0


def test_an_ended_assignment_generates_nothing(student, entitled, assignment, slot):
    entitled(student)
    assignment.status = TeacherAssignment.Status.ENDED
    assignment.save(update_fields=["status"])

    assert booking.generate_sessions() == 0


def test_a_refunded_unit_is_refilled_only_when_an_occurrence_remains(
    student, entitled, assignment, slot
):
    """The spec's most surprising rule, asserted both ways.

    A returned unit has somewhere to go only if the slot has a later occurrence
    inside the cycle. When the cycle is already fully laid out, the unit simply
    goes unused -- there is no fifth Saturday to spend it on.
    """
    subscription = entitled(student)
    subscription.current_period_end = timezone.now() + dt.timedelta(days=60)
    subscription.save(update_fields=["current_period_end"])
    booking.generate_sessions()
    first = Session.objects.order_by("starts_at").first()

    booking.cancel_session(student, first.id)  # far future, so it refunds
    refilled = booking.generate_sessions()

    # 60 days leaves a later Saturday free, so the unit is spent again.
    assert refilled == 1

    # Now exhaust the horizon: no occurrence left, so nothing is refilled.
    subscription.current_period_end = Session.objects.order_by("starts_at").last(
    ).starts_at + dt.timedelta(hours=1)
    subscription.save(update_fields=["current_period_end"])
    Session.objects.filter(consumes_quota=True).exclude(
        id=Session.objects.order_by("starts_at").last().id
    ).delete()
    latest = Session.objects.order_by("starts_at").last()
    booking.cancel_session(student, latest.id, now=latest.starts_at - dt.timedelta(days=2))

    assert booking.generate_sessions() == 0
```

- [ ] **Step 2: Run and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_booking_generation.py -v`
Expected: FAIL — `AttributeError: ... has no attribute 'generate_sessions'`.

- [ ] **Step 3: Implement**

Append to `kaleem/scheduling/booking.py`:

```python
def _occurrences(
    slot: RecurringSlot, after: dt.datetime, until: dt.datetime
) -> list[dt.datetime]:
    """Every UTC instant of this weekly slot in (after, until]."""
    target_python_weekday = (5 + slot.weekday) % 7
    day = after.date()
    days_ahead = (target_python_weekday - day.weekday()) % 7
    candidate = dt.datetime.combine(
        day + dt.timedelta(days=days_ahead), slot.start_time, tzinfo=dt.UTC
    )
    if candidate <= after:
        candidate += dt.timedelta(days=7)
    out: list[dt.datetime] = []
    while candidate <= until:
        out.append(candidate)
        candidate += dt.timedelta(days=7)
    return out


def generate_sessions(*, now: dt.datetime | None = None) -> int:
    """Materialise each active slot's sessions for the current billing cycle.

    Daily and idempotent rather than fired on the renewal webhook, and that
    choice does the work of a late-renewal rule: an unentitled student generates
    nothing, and the first run after they are entitled again fills in whatever
    remains of the cycle. A webhook-triggered generator would need its own
    catch-up path for every way a renewal can be late, out of order or replayed.

    Quota is enforced *by construction* here, not merely checked: the loop stops
    at the limit, so a fifth session of a four-session cycle is never written.
    """
    now = now or timezone.now()
    created = 0
    slots = RecurringSlot.objects.filter(
        status=RecurringSlot.Status.ACTIVE,
        assignment__status=TeacherAssignment.Status.ACTIVE,
    ).select_related("assignment")

    for slot in slots:
        student = identity_services.get_user(slot.assignment.student_id)
        quota = get_quota(student)
        if quota is None:
            continue
        remaining = quota["remaining"]
        if remaining <= 0:
            continue
        for moment in _occurrences(slot, now, quota["cycle_end"]):
            if remaining <= 0:
                break
            _, was_created = Session.objects.get_or_create(
                assignment=slot.assignment,
                starts_at=moment,
                defaults={
                    "slot": slot,
                    "duration_minutes": SESSION_DURATION_MINUTES,
                    "cycle_end": quota["cycle_end"],
                },
            )
            if was_created:
                created += 1
                remaining -= 1
    return created
```

`get_or_create` on `(assignment, starts_at)` is what makes a second run a no-op, and it is also why a refunded unit is not re-materialised at the same instant: the cancelled row still occupies that slot's occurrence.

- [ ] **Step 4: Run the tests**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/ -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): generate a cycle's sessions from a slot

Quota holds by construction: the loop stops at the limit, so a fifth
session of a four-session cycle is never written."
```

---

### Task 8: The beat task

**Files:**
- Create: `kaleem/scheduling/tasks.py`
- Modify: `config/settings/base.py` (the `CELERY_BEAT_SCHEDULE` dict, around line 218)
- Test: `kaleem/scheduling/tests/test_tasks.py`

**Interfaces:**
- Produces: `kaleem.scheduling.tasks.generate_sessions` (Celery task), scheduled daily.

- [ ] **Step 1: Write the failing test**

Create `kaleem/scheduling/tests/test_tasks.py`:

```python
import pytest

from kaleem.scheduling import tasks

pytestmark = pytest.mark.django_db


def test_the_task_delegates_to_the_service(student, entitled, assignment, slot):
    entitled(student)

    tasks.generate_sessions()

    from kaleem.scheduling.models import Session

    assert Session.objects.exists()


def test_the_task_is_registered_in_the_beat_schedule(settings):
    scheduled = {
        entry["task"] for entry in settings.CELERY_BEAT_SCHEDULE.values()
    }

    assert "kaleem.scheduling.tasks.generate_sessions" in scheduled
```

The second test is not ceremony: a task nobody schedules never runs, and the failure mode is silent — sessions simply stop appearing.

- [ ] **Step 2: Run and watch it fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_tasks.py -v`
Expected: FAIL — `ModuleNotFoundError: kaleem.scheduling.tasks`.

- [ ] **Step 3: Write the task**

Create `kaleem/scheduling/tasks.py`, following `kaleem/billing/tasks.py`'s shape exactly — thin wrapper, logic in the module it delegates to:

```python
"""Scheduled scheduling jobs.

Thin wrappers: the logic lives in `booking`, so it can be tested without a
broker and called by hand from a shell during an incident.
"""

from celery import shared_task

from kaleem.scheduling import booking


@shared_task
def generate_sessions() -> None:
    """Daily. Materialise each active slot's sessions for the current cycle.

    No autoretry: it is idempotent and runs again tomorrow.
    """
    booking.generate_sessions()
```

- [ ] **Step 4: Schedule it**

In `config/settings/base.py`, add to `CELERY_BEAT_SCHEDULE` alongside the billing entries:

```python
    "scheduling-generate-sessions": {
        "task": "kaleem.scheduling.tasks.generate_sessions",
        # Daily, before the billing reconcile so a renewal applied last night is
        # already reflected when sessions are laid out.
        "schedule": crontab(hour="2", minute="43"),
    },
```

- [ ] **Step 5: Run the tests**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_tasks.py -v`
Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): schedule session generation daily

Declared in code, not only in the beat database, so the schedule is
reviewable and cannot be silently switched off in an admin."
```

---

### Task 9: The API

**Files:**
- Create: `kaleem/scheduling/api/booking_serializers.py`
- Modify: `kaleem/scheduling/api/views.py`, `kaleem/scheduling/api/urls.py`
- Test: `kaleem/scheduling/tests/test_booking_api.py`

**Interfaces:**
- Produces seven routes named `slot-options`, `slots`, `slot-detail`, `sessions`, `session-cancel`, `session-complete`, `quota`, all under `api:scheduling:`.

- [ ] **Step 1: Write the failing tests**

Create `kaleem/scheduling/tests/test_booking_api.py`. Client fixtures follow
`kaleem/scheduling/tests/test_matching_api.py` — `APIClient()` plus `force_authenticate`.

```python
import datetime as dt

import pytest
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from kaleem.scheduling.models import RecurringSlot
from kaleem.scheduling.models import Session

pytestmark = pytest.mark.django_db

REFERENCE_TIME = dt.time(10)


def _client(user):
    client = APIClient()
    client.force_authenticate(user)
    return client


@pytest.fixture
def student_client(student):
    return _client(student)


@pytest.fixture
def teacher_client(teacher):
    return _client(teacher)


@pytest.fixture
def scheduled(assignment, slot, entitled, student):
    subscription = entitled(student)
    return Session.objects.create(
        assignment=assignment,
        slot=slot,
        starts_at=timezone.now() + dt.timedelta(days=3),
        cycle_end=subscription.current_period_end,
    )


def test_slot_options_lists_shared_times(student_client, assignment):
    response = student_client.get(reverse("api:scheduling:slot-options"))

    assert response.status_code == 200
    assert response.data[0]["start_time"] == "10:00:00"
    assert response.data[0]["weekday"] == 0


def test_slot_options_403s_without_a_student_profile(teacher_client):
    response = teacher_client.get(reverse("api:scheduling:slot-options"))

    assert response.status_code == 403


def test_claiming_returns_201_and_the_slot(student_client, assignment):
    response = student_client.post(
        reverse("api:scheduling:slots"), {"weekday": 0, "start_time": "10:00"}
    )

    assert response.status_code == 201
    assert response.data["weekday"] == 0
    assert RecurringSlot.objects.filter(assignment=assignment).count() == 1


def test_claiming_a_taken_time_returns_409(
    student_client, other_student, assignment, other_assignment
):
    student_client.post(
        reverse("api:scheduling:slots"), {"weekday": 0, "start_time": "10:00"}
    )

    response = _client(other_student).post(
        reverse("api:scheduling:slots"), {"weekday": 0, "start_time": "10:00"}
    )

    assert response.status_code == 409
    assert RecurringSlot.objects.filter(status="active").count() == 1


def test_claiming_an_unavailable_time_returns_400(student_client, assignment):
    response = student_client.post(
        reverse("api:scheduling:slots"), {"weekday": 0, "start_time": "06:00"}
    )

    assert response.status_code == 400


def test_ending_a_slot_returns_204(student_client, assignment):
    created = student_client.post(
        reverse("api:scheduling:slots"), {"weekday": 0, "start_time": "10:00"}
    )

    response = student_client.delete(
        reverse("api:scheduling:slot-detail", args=[created.data["id"]])
    )

    assert response.status_code == 204
    assert RecurringSlot.objects.get().status == "ended"


def test_sessions_are_role_aware(student_client, teacher_client, scheduled):
    student_view = student_client.get(reverse("api:scheduling:sessions"))
    teacher_view = teacher_client.get(reverse("api:scheduling:sessions"))

    assert [s["id"] for s in student_view.data] == [scheduled.id]
    assert [s["id"] for s in teacher_view.data] == [scheduled.id]


def test_a_stranger_sees_no_sessions_and_cannot_cancel(other_student, scheduled):
    client = _client(other_student)

    assert client.get(reverse("api:scheduling:sessions")).data == []
    response = client.post(
        reverse("api:scheduling:session-cancel", args=[scheduled.id])
    )
    assert response.status_code == 403


def test_cancelling_returns_the_updated_session(student_client, scheduled):
    response = student_client.post(
        reverse("api:scheduling:session-cancel", args=[scheduled.id])
    )

    assert response.status_code == 200
    assert response.data["status"] == "cancelled"
    scheduled.refresh_from_db()
    assert scheduled.consumes_quota is False


def test_a_session_states_its_cancellation_consequence(student_client, scheduled):
    """The client must never recompute the 24-hour rule against its own clock."""
    [payload] = student_client.get(reverse("api:scheduling:sessions")).data

    assert payload["may_cancel"] is True
    assert payload["cancellation_refunds"] is True


def test_completing_is_teacher_only(student_client, teacher_client, scheduled):
    refused = student_client.post(
        reverse("api:scheduling:session-complete", args=[scheduled.id])
    )
    assert refused.status_code == 403

    allowed = teacher_client.post(
        reverse("api:scheduling:session-complete", args=[scheduled.id])
    )
    assert allowed.status_code == 200
    assert allowed.data["status"] == "completed"


def test_quota_reports_limit_used_and_remaining(student_client, scheduled):
    response = student_client.get(reverse("api:scheduling:quota"))

    assert response.status_code == 200
    assert response.data["used"] == 1
    assert response.data["remaining"] == response.data["limit"] - 1
    assert response.data["cycle_end"] is not None


def test_quota_404s_or_empties_without_entitlement(student):
    """A student with no subscription has no quota to report. The endpoint
    answers 404 rather than inventing a zero, which would read as 'you have
    used them all' when the truth is 'you have not bought any'."""
    response = _client(student).get(reverse("api:scheduling:quota"))

    assert response.status_code == 404


def test_no_payload_contains_an_email(
    student_client, teacher_client, scheduled, student, teacher
):
    body = str(student_client.get(reverse("api:scheduling:sessions")).data) + str(
        teacher_client.get(reverse("api:scheduling:sessions")).data
    )

    assert student.email not in body
    assert teacher.email not in body
```

Note `test_quota_404s_or_empties_without_entitlement`: `get_quota` returns `None` for an
unentitled student, and the view must turn that into a 404 rather than a zeroed payload. A
zeroed quota reads as "you have used them all" when the truth is "you have not bought any",
and the frontend would then show a student a "you are out of sessions" state they cannot fix
by waiting for the cycle to reset.

- [ ] **Step 2: Run and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_booking_api.py -v`
Expected: FAIL — `NoReverseMatch`.

- [ ] **Step 3: Write the serializers**

Create `kaleem/scheduling/api/booking_serializers.py`:

```python
from rest_framework import serializers


class SlotOptionSerializer(serializers.Serializer):
    """A computed candidate, not a row -- hence Serializer, not ModelSerializer."""

    weekday = serializers.IntegerField()
    start_time = serializers.TimeField()
    starts_at = serializers.DateTimeField()


class SlotSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    weekday = serializers.IntegerField()
    start_time = serializers.TimeField()
    subject_name = serializers.CharField()
    teacher_name = serializers.CharField()


class SessionSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    starts_at = serializers.DateTimeField()
    duration_minutes = serializers.IntegerField()
    status = serializers.CharField()
    subject_name = serializers.CharField()
    teacher_name = serializers.CharField()
    student_name = serializers.CharField()
    may_cancel = serializers.BooleanField()
    cancellation_refunds = serializers.BooleanField()


class QuotaSerializer(serializers.Serializer):
    limit = serializers.IntegerField()
    used = serializers.IntegerField()
    remaining = serializers.IntegerField()
    cycle_end = serializers.DateTimeField()


class ClaimSlotSerializer(serializers.Serializer):
    weekday = serializers.IntegerField(min_value=0, max_value=6)
    start_time = serializers.TimeField()
```

`may_cancel` and `cancellation_refunds` are computed server-side and sent with each session **because the interface must state the consequence before the click**. Recomputing the 24-hour rule in the client would put the rule in two places, and the client's clock is not the one the server will use.

- [ ] **Step 4: Write the views and routes**

Append to `kaleem/scheduling/api/views.py`, merging imports into the existing block. Each view is thin: permission check, call `booking`, serialise. The session list is role-aware — a student sees their own, a teacher sees all their students', a parent sees their children's — built from `TeacherAssignment` the same way `matching.list_assignments_for` does, and ordered by `starts_at`.

Add to `kaleem/scheduling/api/urls.py`:

```python
    path("slot-options/", SlotOptionListView.as_view(), name="slot-options"),
    path("slots/", SlotView.as_view(), name="slots"),
    path("slots/<int:slot_id>/", SlotDetailView.as_view(), name="slot-detail"),
    path("sessions/", SessionListView.as_view(), name="sessions"),
    path(
        "sessions/<int:session_id>/cancel/",
        SessionCancelView.as_view(),
        name="session-cancel",
    ),
    path(
        "sessions/<int:session_id>/complete/",
        SessionCompleteView.as_view(),
        name="session-complete",
    ),
    path("quota/", QuotaView.as_view(), name="quota"),
```

- [ ] **Step 5: Run the tests plus the versioning guard**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/ tests/test_api_versioning_is_enforced.py -v`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): booking API

Sessions carry may_cancel and cancellation_refunds from the server: the
interface must state the consequence before the click, and the rule must
not live in two places against two clocks."
```

---

### Task 10: Admin, the e2e fixture, and the backend gate

**Files:**
- Modify: `kaleem/scheduling/admin.py`
- Modify: `kaleem/scheduling/management/commands/seed_e2e_matching.py`
- Test: `kaleem/scheduling/tests/test_seed_e2e_matching.py`, `kaleem/scheduling/tests/test_admin.py`

- [ ] **Step 1: Register both models in admin**

Append `RecurringSlot` and `Session` admin classes to `kaleem/scheduling/admin.py`, following the three classes already there. `SessionAdmin` lists `assignment`, `starts_at`, `status`, `consumes_quota`, `cycle_end`, filters on `status` and `consumes_quota`, and orders by `-starts_at` — staff answering "why does this parent say they lost a session" need `consumes_quota` visible next to `cancelled_by`.

- [ ] **Step 2: Extend the e2e fixture**

The e2e student already has an assignment after `seed_e2e_matching` accepts nothing — it opens a match request only. C2's specs need a *claimed slot* and *generated sessions*. Extend the command so that, after reconciling, it:

1. accepts the open request on the teacher's behalf via `matching.accept_offer`, producing a `TeacherAssignment`;
2. claims a slot inside the seeded overlap via `booking.claim_slot`;
3. runs `booking.generate_sessions()`.

Keep it idempotent and keep the DEBUG guard. Delete `Session` and `RecurringSlot` rows for the seeded student before re-seeding, **and mind the delete order**: `Session.slot` is `PROTECT`, so sessions go before slots, exactly as `TeacherAssignment` goes before `MatchRequest` today.

- [ ] **Step 3: Add the seed tests**

Extend `test_seed_e2e_matching.py`: after seeding, the e2e student has one active slot and at least one scheduled session; running it twice leaves the same counts.

- [ ] **Step 4: Run the whole backend gate**

```bash
docker compose -f docker-compose.local.yml exec -T django pytest --cov=kaleem
docker compose -f docker-compose.local.yml exec -T django lint-imports
docker compose -f docker-compose.local.yml exec -T django ruff check .
docker compose -f docker-compose.local.yml exec -T django mypy kaleem
```
All green, coverage ≥ 97.2. **If coverage came out higher, raise `fail_under`** to at or just below the achieved figure, keeping `precision = 1`, and leave headroom of a few tenths rather than hundredths — a floor equal to the achieved number is a tripwire that reddens unrelated PRs.

- [ ] **Step 5: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): admin surface and the C2 e2e fixture"
```

Do NOT open the pull request; the controller does that.

---

### Task 11: Dashboard — the booking feature module

Everything from here is in `dashboard`, on `feat/phase-c2-booking-quota`.

**Files:**
- Create: `src/features/booking/{schemas,api,queries,index}.ts` and their tests

**Interfaces:**
- Produces: `useSlotOptions()`, `useClaimSlot()`, `useEndSlot()`, `useSessions()`, `useCancelSession()`, `useCompleteSession()`, `useQuota()`, plus `SlotOption`, `Slot`, `Session`, `Quota` types.

Read `src/features/matching/{api,queries,schemas}.ts` first — it is the pattern, and C2 follows it exactly. Paths are RELATIVE (`scheduling/sessions/`); the `/api/v1/` prefix lives in `VITE_API_URL`, and a leading slash bypasses the versioned base.

Mutations invalidate **both** the sessions key and the quota key: cancelling changes what is scheduled *and* what is left, and a quota counter that lags by a refresh is worse than none. Use `onSettled` for cancel, as C1 does for accept — a failed mutation is exactly when the cached view is most likely stale.

- [ ] **Step 1: Write the failing api test**, asserting each path string character by character (a missing trailing slash is a 404 in Django).
- [ ] **Step 2: Run it and watch it fail.** `pnpm vitest run src/features/booking/api.test.ts`
- [ ] **Step 3: Write `schemas.ts`, `api.ts`, `queries.ts`, `index.ts`.**
- [ ] **Step 4: Write `queries.test.tsx`** — covering that cancel invalidates both keys, including on failure.
- [ ] **Step 5: Run `pnpm vitest run src/features/booking` — all green.**
- [ ] **Step 6: Commit** `feat(booking): api client, schemas and queries`

---

### Task 12: The schedule page

**Files:**
- Create: `src/features/booking/components/SessionList.tsx`, `QuotaBadge.tsx` (+ tests)
- Modify: `src/routes/_authed/schedule.tsx` (currently a `ModulePlaceholder` scaffold — this replaces it), `src/routes/_authed/schedule.test.tsx` (create), both locale files

- [ ] **Step 1: Write the failing tests** covering: upcoming sessions render with subject, other party's name, date and time in the viewer's locale; the empty state; loading; a server error; a session where `may_cancel` is false shows no cancel control; a cancel where `cancellation_refunds` is false warns **before** the click that the session will still be counted; the quota badge shows used/remaining and the reset date; a student at zero remaining is told when it resets rather than only refused.
- [ ] **Step 2: Run and watch them fail.**
- [ ] **Step 3: Build the components** from existing `@/ui` primitives only. Cancel is a confirmation, not a bare button: the consequence comes from `cancellation_refunds`, server-computed, never recomputed in the client.
- [ ] **Step 4: Add i18n keys to both locales** — real Arabic, six plural categories where a count is involved.
- [ ] **Step 5: Replace the scaffold route** and update `src/features/shell/nav.ts` only if the nav entry's gating changes (it already exists as `/schedule` for everyone).
- [ ] **Step 6: Run `pnpm vitest run`, `pnpm lint`, `pnpm tsc --noEmit`.**
- [ ] **Step 7: Commit** `feat(booking): the schedule page and the quota counter`

---

### Task 13: Claiming a slot in the UI

**Files:**
- Create: `src/features/booking/components/ClaimSlotCard.tsx` (+ test)
- Modify: `src/routes/_authed/schedule.tsx`, both locale files

- [ ] **Step 1: Write the failing tests**: a student with an assignment and no active slot sees the candidate times; picking one calls the mutation with that weekday and time; a 409 renders as "your teacher was just booked at that time" and refetches the options, **not** as an error; a student with an active slot sees it and an option to end it; a student with no assignment sees nothing at all.
- [ ] **Step 2: Run and watch them fail.**
- [ ] **Step 3: Build it.** Times are rendered in the viewer's timezone — the API returns UTC, and a student in Cairo must not be shown 07:00 for their 10:00 lesson. Use the same `Intl` formatting the rest of the app uses.
- [ ] **Step 4: i18n both locales, real Arabic.**
- [ ] **Step 5: Run the dashboard gate; raise the floors if coverage rose,** leaving tenths of headroom, not hundredths.
- [ ] **Step 6: Commit** `feat(booking): claim a weekly slot`

---

### Task 14: RTL and a real browser

Not a formality: it is D9's manual click-through, and C1's browser pass is what found a WCAG reflow failure no unit test saw.

- [ ] **Step 1: Bring up the stack** per the local visual-run recipe (`app.kaleem.localhost`; the compose file is at the meta root).
- [ ] **Step 2: Migrate and seed**: `python manage.py migrate`, then `seed_e2e`, then `seed_e2e_matching`.
- [ ] **Step 3: As the student** — claim a slot, see the generated sessions appear, read the quota counter, cancel one far out and watch the counter go back up, then cancel one inside 24 hours and confirm the interface said so first.
- [ ] **Step 4: As the teacher** — the same sessions appear on their schedule, and completing one works.
- [ ] **Step 5: Switch to Arabic** — both pages mirror, no clipping, and **measure** `document.documentElement.scrollWidth` against `window.innerWidth` rather than eyeballing it.
- [ ] **Step 6: Record what you saw.** Anything wrong and unrelated to C2 goes to `ISSUES.md` (D10); anything wrong and part of C2 gets fixed here.

---

### Task 15: e2e

**Files:**
- Create: `e2e/booking.spec.ts`

- [ ] **Step 1: Write the spec** with three flows: a student claims a slot and sees sessions generated from it; cancelling more than 24h ahead returns the unit visibly in the quota counter; the teacher sees the same session on their own schedule. Follow `e2e/matching.spec.ts` — including its header comment stating that every flow is a write across the ADR-0019 boundary and therefore exercises real CSRF, and its explicit statement of the ordering decision.

  Claiming is **destructive to the fixture** exactly as accepting is in `matching.spec.ts`. Say in a comment which strategy you chose — fixed order, or a spec that re-establishes its own state — because a later reader will otherwise "tidy" the order and break it silently.

- [ ] **Step 2: Wire the seed into CI** if `seed_e2e_matching` does not already cover C2's state — check `.github/workflows/ci.yml` in the meta repo; the line calling it already exists, so this is only needed if you added a *new* command in Task 10. Report to the controller rather than committing in the meta repo.
- [ ] **Step 3: Run the whole suite** at CI's real setting: `pnpm playwright test --workers=1`. Report the count; the existing 27 must still pass.
- [ ] **Step 4: Mutation-check one assertion.** Break `_apply_cancellation` so it never sets `consumes_quota = False`, confirm the refund flow turns RED, restore it, confirm green. Verify with `git diff` that the backend file ends unchanged.
- [ ] **Step 5: Commit** `test(e2e): booking — claim, generate, cancel, refund`

---

## Notes for the executor

- **The reference date.** Availability is a weekly pattern, so slot options need a week to anchor to. Views pass a `_today()` seam as C1's do. Do not freeze the clock globally; pass explicit dates in tests, as these tests do.
- **`now` is always injectable.** Every cancellation and generation function takes `now=None` and defaults to `timezone.now()`. That is what makes the 24-hour boundary testable without sleeping or mocking the clock module.
- **Quota is enforced in generation, not in the API.** There is no "you have run out" error on booking, because booking a slot is not booking a session. If you find yourself adding a quota check to `claim_slot`, re-read the spec — the limit is on sessions, and generation is the only thing that creates them.
- **If a task needs something not in this plan,** stop and say so rather than improvising across a module boundary. Boundary changes need an ADR (D8), not an implementation PR.
