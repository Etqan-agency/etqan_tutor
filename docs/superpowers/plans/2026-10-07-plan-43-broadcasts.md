# Plan 43 — B5b Broadcasts & notification log — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The office sends one message to one of ten audiences, by in-app notice and email. It sees per-recipient email status and read state, and it can read a log of every notice.

**Architecture:**
- Everything lives in `etqan.notifications` (owned by B5).
- A `Broadcast` record plus one Plan 8 `Notification` row per recipient: type `broadcast`, target kind `broadcast`.
- Delivery reuses `email.queue`.
- The list and log are read-only queries.
- Everything sits behind the `broadcasts` switch.
- The dashboard adds two office pages under People and keeps line breaks in notice bodies.

**Tech Stack:** Django 5 + DRF + django-tenants, pytest; React + TanStack Router/Query + react-hook-form + zod, vitest; Playwright.

**Spec:** `docs/superpowers/specs/2026-10-07-b5b-broadcasts-design.md`, with the phase spec `docs/superpowers/specs/2026-10-07-b5-communication-design.md`.

**Requires:**
- B5a: Plan 42, merged before Task 1 starts.
- B2f and request R5 (`scheduling.services.study_group_members`), for Task 7 only.

## Global Constraints

- **Feature switch** `broadcasts`: "Broadcasts and notification log" / "الرسائل الجماعية وسجل الإشعارات", group `communication`. It is `built=True`, off by default, and registered under `# ── phase B5 ──` in `etqan/platform/features.py`.
- **Access resources** under `# ── phase B5 ──` in `etqan/access/registry.py`:
  - `Resource("broadcast", "Broadcasts", "الرسائل الجماعية", ("view_any", "create", "delete"))`;
  - `Resource("notification_log", "Notification log", "سجل الإشعارات", ("view_any",))`.
- **Migration:** one new migration `etqan/notifications/migrations/0003_broadcasts.py` (after B5a's `0002`). It:
  - creates `Broadcast`;
  - alters the choices of `Notification.type` and `Notification.target_kind`;
  - adds `Index(fields=["target_kind", "target_id"], name="notification_target_idx")`.

  No existing data changes.
- **Unchanged:** `kinds.TYPES`, `kinds.TARGETS`, `kinds.KINDS`, the settings, the templates and `text.SAMPLE_FACTS`. A broadcast is not an automatic type.
- **Text:**
  - message 1–2000 characters after `.strip()`, plain text, line breaks kept;
  - title "New message" / "رسالة جديدة", in the recipient's language via `text.language_for(user.preferred_language, academy.default_language)`.
- **Channels:** `channels` must equal `["email"]`; anything else is 400 on `channels`. WhatsApp is on hold (ledger D41).
- **People lists:** `teachers` and `students` take 1–500 ids. `student`, `teacher` and `parent` take exactly 1 id.
- **Permissions:**
  - send: `[HasCode, FeatureOn, NotImpersonating]`;
  - every other route: `[HasCode, FeatureOn]`;
  - non-office roles get 403, and a switched-off feature answers 404 after the role check.
- **Query counts:** sending costs a fixed number of queries for 1 or 50 recipients, and so does a list or log page.
- **Shared lists:** add lines only under `── phase B5 ──` markers (`features.py`, `registry.py`, `nav.ts`). `FeatureCode` gains `broadcasts`. New translation area: `dashboard/src/locales/{en,ar}/broadcasts.json`, key-for-key equal, no es.
- **Coverage:** backend ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- **Tools:** run everything in this stream's stack from the meta worktree root:
  `S() { (set -a; . ./.env.stream; set +a; docker compose -f docker-compose.local.yml exec -T "$@"); }`
  - backend tests: `S django pytest <paths> -q`;
  - migrations: `just _stack-manage makemigrations notifications --name broadcasts`;
  - lint: `S django ruff check etqan && S django ruff format --check etqan && S django lint-imports`;
  - dashboard: `S dashboard pnpm vitest run <paths>`, `S dashboard pnpm tsc --noEmit` and `S dashboard pnpm lint`;
  - e2e: `just e2e e2e/b5-broadcasts.spec.ts`;
  - after the migration: `just migrate`.

## Review Focus

1. A pending broadcast email whose broadcast is deleted before the worker picks it up must never be sent. Task 2 tests it.
2. The `admins` audience must exclude the sender. When the sender is the only admin, the answer is 400 "Nobody in this audience can be told", not an empty broadcast. Task 2 tests it.
3. A `people` id of the wrong role, a duplicate id, or an inactive user must not produce a row. Wrong role is a 400; duplicates collapse; an inactive user is skipped and counted. Task 2 tests all three.
4. With `auto_notifications` off, a stuck pending broadcast email must still be re-queued by the beat job. Task 1 tests it.
5. A 2000-character multi-line message must keep its line breaks on `/notifications` and must not overflow the bell. Task 5 tests it.

---

### Task 1: Data — Broadcast model, notice choices, index, link branch, re-queue regardless, switch

**Files:**
- Modify: `backend/etqan/notifications/kinds.py`
- Modify: `backend/etqan/notifications/models.py`
- Create: `backend/etqan/notifications/migrations/0003_broadcasts.py` (generated)
- Modify: `backend/etqan/notifications/links.py`
- Modify: `backend/etqan/notifications/services/scan.py` (`scan_now`)
- Modify: `backend/etqan/platform/features.py`
- Modify: `backend/etqan/platform/tests/test_features.py`, if it lists built codes
- Test: `backend/etqan/notifications/tests/test_broadcast_data.py`

**Interfaces:**
- Produces in `kinds`:
  - `BROADCAST = "broadcast"`;
  - `NOTICE_TYPES = (*TYPES, BROADCAST)`;
  - `NOTICE_TARGETS = (*TARGETS, BROADCAST)`.
- Produces the model `Broadcast` with these fields:
  - `audience` (CharField 16, choices `Broadcast.Audience`);
  - `audience_label` (CharField 200);
  - `message` (TextField);
  - `channels` (JSONField, default list);
  - `created_by` (FK User, SET_NULL, null, `related_name="+"`);
  - `created_at` (default now);
  - `recipient_count` (PositiveIntegerField);
  - `Meta.ordering = ["-created_at", "-id"]`.
- `Broadcast.Audience` is a TextChoices with the values `admins`, `teachers`, `students`, `student`, `teacher`, `parent`, `all_students`, `all_teachers`, `all_parents` and `study_group`.
- `Notification.type` choices come from `NOTICE_TYPES`, `target_kind` choices from `NOTICE_TARGETS`, and the model gains the index named `notification_target_idx`.
- `links.path_for(type_="broadcast", target_kind="broadcast", …)` returns `"/notifications"` for every role.
- `scan_now()` re-queues stuck emails even while `auto_notifications` is off.

- [ ] **Step 1: Write the failing tests** — `tests/test_broadcast_data.py`:

```python
"""Spec B5b §3, C-11, C-13."""

from datetime import timedelta

import pytest

from etqan.notifications import kinds
from etqan.notifications import links
from etqan.notifications import services
from etqan.notifications.channels import email
from etqan.notifications.models import Broadcast
from etqan.notifications.models import Notification

pytestmark = pytest.mark.django_db


def test_broadcast_is_a_notice_but_not_an_automatic_type():
    assert kinds.BROADCAST in kinds.NOTICE_TYPES
    assert kinds.BROADCAST in kinds.NOTICE_TARGETS
    assert kinds.BROADCAST not in kinds.TYPES
    assert kinds.BROADCAST not in kinds.TARGETS


@pytest.mark.parametrize("role", ["admin", "staff", "teacher", "student", "parent"])
def test_a_broadcast_notice_leads_to_the_notifications_page(role):
    assert (
        links.path_for(type_="broadcast", target_kind="broadcast", target_id=1, role=role)
        == "/notifications"
    )


def test_a_broadcast_row_can_be_stored(api_for):
    user = api_for("student").user
    sent = Broadcast.objects.create(
        audience=Broadcast.Audience.STUDENT,
        audience_label="Student 1",
        message="Hi",
        channels=["email"],
        recipient_count=1,
    )
    Notification.objects.create(
        recipient=user,
        type=kinds.BROADCAST,
        dedupe_key=f"broadcast:broadcast:{sent.pk}:{user.pk}",
        target_kind=kinds.BROADCAST,
        target_id=sent.pk,
        language="en",
        title="New message",
        body="Hi",
    )
    assert Notification.objects.filter(target_kind="broadcast", target_id=sent.pk).count() == 1


def test_stuck_emails_are_requeued_while_automatic_notices_are_off(
    api_for, set_features, clock, monkeypatch
):
    set_features(auto_notifications=False)
    user = api_for("student").user
    row = Notification.objects.create(
        recipient=user,
        type=kinds.BROADCAST,
        dedupe_key="broadcast:broadcast:1:x",
        target_kind=kinds.BROADCAST,
        target_id=1,
        language="en",
        title="t",
        body="b",
        created_at=clock.now() - timedelta(minutes=10),
    )
    queued = []
    monkeypatch.setattr(email, "queue", lambda ids: queued.extend(ids))
    assert services.scan_now() == 0
    assert row.pk in queued
```

Use the notifications `clock` fixture from `tests/conftest.py`; adapt the name if it differs (it is `clock`, with `.set()`). If `clock.now()` does not exist, compute `now` from `etqan.notifications.clock.now()` after `clock.set(...)`.

- [ ] **Step 2: Run to verify they fail**

Run: `S django pytest etqan/notifications/tests/test_broadcast_data.py -q`
Expected: FAIL (`ImportError: cannot import name 'Broadcast'`).

- [ ] **Step 3: Implement**

`kinds.py`, after `TYPES`:

```python
# Spec B5b §3: a broadcast is a notice but not an automatic type, so it has
# no setting, template, category or finder; only `Notification` names it.
BROADCAST = "broadcast"
NOTICE_TYPES = (*TYPES, BROADCAST)
NOTICE_TARGETS = (*TARGETS, BROADCAST)
```

`models.py`:
- `Notification.type` → `choices=[(v, v) for v in NOTICE_TYPES]`;
- `target_kind` → `choices=[(v, v) for v in NOTICE_TARGETS]`;
- add to `Notification.Meta.indexes`: `models.Index(fields=["target_kind", "target_id"], name="notification_target_idx")`;
- update the `SKIPPED` comment to `# No email was sent: no address, or email not chosen (B5b C-7).`

Leave `TYPE_CHOICES` (used by settings and templates) on `TYPES`. Then add:

```python
class Broadcast(models.Model):
    """One message from the office to an audience (spec B5b C-1); its
    recipients are `Notification` rows with target kind `broadcast`."""

    class Audience(models.TextChoices):
        ADMINS = "admins", "Admins"
        TEACHERS = "teachers", "Several teachers"
        STUDENTS = "students", "Several students"
        STUDENT = "student", "One student"
        TEACHER = "teacher", "One teacher"
        PARENT = "parent", "One parent"
        ALL_STUDENTS = "all_students", "All students"
        ALL_TEACHERS = "all_teachers", "All teachers"
        ALL_PARENTS = "all_parents", "All parents"
        STUDY_GROUP = "study_group", "Study group"

    audience = models.CharField(max_length=16, choices=Audience.choices)
    # A snapshot at send time (C-2): later renames or deletions change nothing.
    audience_label = models.CharField(max_length=200)
    message = models.TextField()
    channels = models.JSONField(default=list)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="+",
    )
    created_at = models.DateTimeField(default=timezone.now)
    recipient_count = models.PositiveIntegerField()

    class Meta:
        ordering = ["-created_at", "-id"]

    def __str__(self):
        return f"Broadcast<{self.audience}, {self.recipient_count}>"
```

Generate the migration: `just _stack-manage makemigrations notifications --name broadcasts`, then `just migrate`.

`links.py`, first line of `path_for`'s body:

```python
    if target_kind == kinds.BROADCAST:
        # Spec B5b C-11: the message is the whole content.
        return "/notifications"
```

`scan.py` `scan_now`:

```python
def scan_now() -> int:
    """The beat job's work in the current academy (`for_each_academy`).
    Stuck emails are re-queued in every academy (spec B5b C-13); the scan
    itself runs only while automatic notifications are on (Plan 13 §5.3)."""
    now = clock.now()
    if not features.enabled("auto_notifications"):
        requeue_stuck(now=now)
        return 0
    return scan(now=now)
```

`features.py`, under `# ── phase B5 ──`, after the B5a lines:

```python
    # Slice B5b (Plan 43): broadcasts and the notification log.
    Feature(
        "broadcasts",
        "Broadcasts and notification log",
        "الرسائل الجماعية وسجل الإشعارات",
        "communication",
        built=True,
    ),
```

Update the `BUILT` list in `platform/tests/test_features.py` if it enumerates codes.

- [ ] **Step 4: Run.** `S django pytest etqan/notifications etqan/platform -q`, then the lint command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/notifications etqan/platform
git -C backend commit -m "feat(notifications): broadcast record, notice choices and switch (B5b)"
```

---

### Task 2: Sending and deleting a broadcast (service)

**Files:**
- Create: `backend/etqan/notifications/services/broadcasts.py`
- Modify: `backend/etqan/notifications/services/__init__.py`
- Test: `backend/etqan/notifications/tests/test_broadcast_send.py`

**Interfaces:**
- Consumes: `Broadcast`, `kinds.BROADCAST` (Task 1); `recipients.eligible`; `text.language_for`; `email.queue`; `academy_services.get_settings()` (`.default_language`); `identity_services.people_queryset(role)`, `get_users(ids)` and `active_admins()`.
- Produces in `services.broadcasts`:
  - `MAX_MESSAGE = 2000`;
  - `MAX_PEOPLE = 500`;
  - `TITLES = {"en": "New message", "ar": "رسالة جديدة"}`;
  - `Sent` (a frozen dataclass: `broadcast: Broadcast`, `skipped: int`);
  - `send(*, audience: str, people: list[int] | None, study_group: int | None, message: str, channels: list[str], by) -> Sent`;
  - `delete(broadcast_id: int) -> None`.
- Exported as `services.send_broadcast` and `services.delete_broadcast`.
- In this task `study_group` is refused: 400 on `audience` with "Study groups are not available yet." Task 7 adds it.

- [ ] **Step 1: Write the failing tests** — `tests/test_broadcast_send.py`. Use `api_for(role)` for users and `set_features` for switches. Patch `etqan.notifications.channels.email.queue` with a recorder (as Task 1's test does) to see the queued ids.

```python
"""Spec B5b C-2..C-5, C-8, C-12, §6."""

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.notifications.channels import email
from etqan.notifications.models import Broadcast
from etqan.notifications.models import Notification
from etqan.notifications.services import broadcasts
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db


@pytest.fixture
def queued(monkeypatch):
    ids = []
    monkeypatch.setattr(email, "queue", lambda rows: ids.extend(rows))
    return ids


def send(by, audience, people=None, message="Hello\nthere", channels=("email",)):
    return broadcasts.send(
        audience=audience, people=people, study_group=None,
        message=message, channels=list(channels), by=by,
    )


def test_one_student_gets_a_notice_and_an_email(api_for, queued):
    admin = api_for("admin").user
    student = api_for("student", preferred_language="ar").user
    sent = send(admin, "student", [student.pk])
    row = Notification.objects.get(recipient=student)
    assert (row.type, row.target_kind, row.target_id) == ("broadcast", "broadcast", sent.broadcast.pk)
    assert row.dedupe_key == f"broadcast:broadcast:{sent.broadcast.pk}:{student.pk}"
    assert (row.title, row.body, row.language) == ("رسالة جديدة", "Hello\nthere", "ar")
    assert row.email_status == "pending"
    assert queued == [row.pk]
    assert (sent.broadcast.recipient_count, sent.skipped) == (1, 0)
    assert sent.broadcast.audience_label == student.full_name
    assert sent.broadcast.created_by == admin


def test_admins_exclude_the_sender(api_for, queued):
    me = api_for("admin").user
    other = api_for("admin").user
    send(me, "admins")
    assert list(Notification.objects.values_list("recipient_id", flat=True)) == [other.pk]


def test_nobody_eligible_is_refused(api_for, queued):
    me = api_for("admin").user
    with pytest.raises(ValidationError) as caught:
        send(me, "admins")
    assert caught.value.field == "audience"
    assert not Broadcast.objects.exists()


def test_all_students_skips_the_inactive_and_those_without_email(api_for, queued):
    admin = api_for("admin").user
    ok = api_for("student").user
    gone = api_for("student").user
    gone.is_active = False
    gone.save(update_fields=["is_active"])
    from etqan.identity import services as identity_services
    identity_services.create_person("student", full_name="No Mail", email=None, invite=False)
    sent = send(admin, "all_students")
    assert list(Notification.objects.values_list("recipient_id", flat=True)) == [ok.pk]
    assert sent.broadcast.audience_label == "All students"


def test_chosen_people_wrong_role_duplicates_and_inactive(api_for, queued):
    admin = api_for("admin").user
    a = api_for("student").user
    b = api_for("student").user
    b.is_active = False
    b.save(update_fields=["is_active"])
    teacher = api_for("teacher").user
    with pytest.raises(ValidationError) as caught:
        send(admin, "students", [a.pk, teacher.pk])
    assert caught.value.field == "people"
    sent = send(admin, "students", [a.pk, a.pk, b.pk])
    assert Notification.objects.count() == 1
    assert (sent.broadcast.recipient_count, sent.skipped) == (1, 1)


@pytest.mark.parametrize(
    ("audience", "people"),
    [("student", []), ("student", [1, 2]), ("students", []), ("students", list(range(1, 502)))],
)
def test_people_counts(api_for, queued, audience, people):
    with pytest.raises(ValidationError) as caught:
        send(api_for("admin").user, audience, people)
    assert caught.value.field == "people"


def test_parents_need_the_parents_feature(api_for, queued, set_features):
    admin = api_for("admin").user
    api_for("parent")
    set_features(parents=False)
    with pytest.raises(ValidationError) as caught:
        send(admin, "all_parents")
    assert caught.value.field == "audience"


@pytest.mark.parametrize(
    ("field", "kwargs"),
    [
        ("message", {"message": "   "}),
        ("message", {"message": "x" * 2001}),
        ("channels", {"channels": ()}),
        ("channels", {"channels": ("email", "whatsapp")}),
    ],
)
def test_message_and_channels(api_for, queued, field, kwargs):
    student = api_for("student").user
    with pytest.raises(ValidationError) as caught:
        send(api_for("admin").user, "student", [student.pk], **kwargs)
    assert caught.value.field == field


def test_study_group_is_not_available_yet(api_for, queued):
    with pytest.raises(ValidationError) as caught:
        broadcasts.send(audience="study_group", people=None, study_group=1,
                        message="m", channels=["email"], by=api_for("admin").user)
    assert caught.value.field == "audience"


def test_sending_costs_a_fixed_number_of_queries(api_for, queued):
    admin = api_for("admin").user
    api_for("student")

    def cost():
        with CaptureQueriesContext(connection) as ctx:
            send(admin, "all_students")
        return len([q for q in ctx.captured_queries if "search_path" not in q["sql"]])

    one = cost()
    for _ in range(49):
        api_for("student")
    assert cost() == one


def test_delete_removes_rows_and_a_pending_email_is_never_sent(api_for, queued, mailoutbox):
    from etqan.notifications.channels.email import send as send_email

    admin = api_for("admin").user
    student = api_for("student").user
    sent = send(admin, "student", [student.pk])
    row_id = Notification.objects.get().pk
    broadcasts.delete(sent.broadcast.pk)
    assert not Broadcast.objects.exists()
    assert not Notification.objects.exists()
    assert send_email(row_id) == "skipped"
    assert mailoutbox == []


def test_delete_unknown_is_not_found(api_for):
    with pytest.raises(NotFoundError):
        broadcasts.delete(999999)
```

If `mailoutbox` is not available, assert `django.core.mail.outbox == []`. If `create_person` needs other arguments, follow `tests/test_api_b5a.py`'s use of it.

- [ ] **Step 2: Run to verify they fail.** `S django pytest etqan/notifications/tests/test_broadcast_send.py -q`. Expected: ImportError.

- [ ] **Step 3: Implement** `services/broadcasts.py`:

```python
"""The office's messages (spec B5b C-1..C-12, §6): resolve an audience,
store one notice per eligible recipient, email them after commit."""

from dataclasses import dataclass

from django.db import transaction

from etqan.academy import services as academy_services
from etqan.identity import services as identity_services
from etqan.notifications import kinds
from etqan.notifications import recipients
from etqan.notifications import text
from etqan.notifications.channels import email
from etqan.notifications.models import Broadcast
from etqan.notifications.models import Notification
from etqan.platform import features
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

MAX_MESSAGE = 2000
MAX_PEOPLE = 500
LABEL_NAMES = 3
TITLES = {"en": "New message", "ar": "رسالة جديدة"}
A = Broadcast.Audience
# Chosen people: the role each audience names, and whether it takes one.
CHOSEN = {
    A.TEACHERS: ("teacher", False),
    A.STUDENTS: ("student", False),
    A.STUDENT: ("student", True),
    A.TEACHER: ("teacher", True),
    A.PARENT: ("parent", True),
}
EVERYONE = {A.ALL_STUDENTS: "student", A.ALL_TEACHERS: "teacher", A.ALL_PARENTS: "parent"}
PENDING = Notification.EmailStatus.PENDING
SKIPPED = Notification.EmailStatus.SKIPPED


@dataclass(frozen=True)
class Sent:
    broadcast: Broadcast
    skipped: int


def _check_text(message: str, channels: list[str]) -> str:
    cleaned = (message or "").strip()
    if not cleaned:
        raise ValidationError("This field is required.", field="message")
    if len(cleaned) > MAX_MESSAGE:
        raise ValidationError(f"Use at most {MAX_MESSAGE} characters.", field="message")
    if list(channels) != ["email"]:
        raise ValidationError("Choose email.", field="channels")
    return cleaned


def _chosen(audience: str, people: list[int] | None) -> tuple[list, str]:
    role, single = CHOSEN[audience]
    ids = list(dict.fromkeys(people or []))
    if single and len(ids) != 1:
        raise ValidationError("Choose one person.", field="people")
    if not single and not 1 <= len(ids) <= MAX_PEOPLE:
        raise ValidationError(f"Choose 1 to {MAX_PEOPLE} people.", field="people")
    found = identity_services.get_users(ids)
    if len(found) != len(ids) or any(u.role != role for u in found.values()):
        raise ValidationError("Choose people of this kind only.", field="people")
    users = [found[i] for i in ids]
    names = [u.full_name for u in users[:LABEL_NAMES]]
    more = len(users) - LABEL_NAMES
    label = ", ".join(names) + (f" and {more} more" if more > 0 else "")
    return users, label


def _audience(audience: str, people, by) -> tuple[list, str]:
    if audience not in A.values:
        raise ValidationError("Unknown audience.", field="audience")
    if audience == A.STUDY_GROUP:
        raise ValidationError("Study groups are not available yet.", field="audience")
    if audience in (A.PARENT, A.ALL_PARENTS) and not features.enabled("parents"):
        raise ValidationError("Parents are switched off.", field="audience")
    if audience == A.ADMINS:
        return [u for u in identity_services.active_admins() if u.pk != by.pk], A(audience).label
    if audience in EVERYONE:
        users = list(identity_services.people_queryset(EVERYONE[audience]).filter(is_active=True))
        return users, A(audience).label
    return _chosen(audience, people)


@transaction.atomic
def send(*, audience, people, study_group, message, channels, by) -> Sent:
    cleaned = _check_text(message, channels)
    users, label = _audience(audience, people, by)
    told = [u for u in users if recipients.eligible(u)]
    if not told:
        raise ValidationError("Nobody in this audience can be told.", field="audience")
    sent = Broadcast.objects.create(
        audience=audience,
        audience_label=label[:200],
        message=cleaned,
        channels=["email"],
        created_by=by,
        recipient_count=len(told),
    )
    default = academy_services.get_settings().default_language
    rows = []
    for user in told:
        language = text.language_for(user.preferred_language, default)
        rows.append(
            Notification(
                recipient=user,
                type=kinds.BROADCAST,
                dedupe_key=f"broadcast:broadcast:{sent.pk}:{user.pk}",
                target_kind=kinds.BROADCAST,
                target_id=sent.pk,
                language=language,
                title=TITLES[language],
                body=cleaned,
                email_status=PENDING if user.email else SKIPPED,
                created_at=sent.created_at,
            )
        )
    Notification.objects.bulk_create(rows, ignore_conflicts=True)
    email.queue(
        Notification.objects.filter(
            target_kind=kinds.BROADCAST, target_id=sent.pk, email_status=PENDING
        ).values_list("pk", flat=True)
    )
    return Sent(broadcast=sent, skipped=len(users) - len(told))


@transaction.atomic
def delete(broadcast_id: int) -> None:
    """C-8: the record and its notices; a pending email not yet being sent is
    never sent (its row is gone)."""
    deleted, _ = Broadcast.objects.filter(pk=broadcast_id).delete()
    if not deleted:
        raise NotFoundError("Broadcast", broadcast_id)
    Notification.objects.filter(target_kind=kinds.BROADCAST, target_id=broadcast_id).delete()
```

If `people_queryset` prefetches per-row data that breaks the fixed query count, use `.prefetch_related(None)` and `select_related(None)` on it, or ask in your report. `email.queue` already defers to on-commit. If `A(audience).label` is lazy-translated, use `str(...)`. The ruff line length is the repo's; wrap as needed.

Exports in `services/__init__.py`:

```python
from etqan.notifications.services.broadcasts import delete as delete_broadcast
from etqan.notifications.services.broadcasts import send as send_broadcast
```

- [ ] **Step 4: Run.** The notifications suite plus lint. Expected: PASS.

- [ ] **Step 5: Commit** `feat(notifications): send and delete broadcasts (B5b)`.

---

### Task 3: Read side and API — broadcast list/detail, log, permissions, route table

**Files:**
- Create: `backend/etqan/notifications/services/log.py` (list and detail queries for broadcasts, and the log query)
- Modify: `backend/etqan/notifications/api/views.py`, `serializers.py`, `payloads.py`, `urls.py`
- Modify: `backend/etqan/access/registry.py` (two resources under `# ── phase B5 ──`)
- Modify: `backend/etqan/access/tests/test_routes.py` (`ROUTES`, `FEATURES`/`FEATURE_WORDS` per convention)
- Test: `backend/etqan/notifications/tests/test_api_b5b.py`

**Interfaces:**
- Consumes: `services.send_broadcast` and `delete_broadcast` (Task 2).
- Produces these routes, under `/api/v1/notifications/`:
  - `broadcasts/` (GET, POST);
  - `broadcasts/<int:pk>/` (GET, DELETE);
  - `log/` (GET).
- Produces this broadcast row payload: `{id, audience, audience_label, message (first 140 characters on the list, full on the detail), channels, created_by (name or null), created_at, recipient_count, email: {pending, sent, failed, skipped}, read}`.
- The detail payload adds `recipients`: a page of `{id, name, role, email_status, read_at}`, using the standard pagination params `page`.
- The POST response is the row plus `skipped`.
- Produces this log row payload: `{id, created_at, type, recipient: {id, name, role}, title, email_status, read_at}`. Filters: `type` (one of `NOTICE_TYPES`, else 400), `email_status` (one of the four, else 400), and `from` / `to` (ISO dates, academy timezone, inclusive).
- Produces in `services.log`:
  - `broadcast_rows(queryset_page) -> list[dict]`, computing the counts for a page in one aggregate query over `Notification` (`target_kind="broadcast"`, `target_id__in=page ids`), grouped by `target_id` and `email_status`, plus one read-count aggregate;
  - `broadcasts(audience=None) -> QuerySet[Broadcast]` (with `select_related("created_by")`);
  - `recipients(broadcast_id) -> QuerySet[Notification]` (with `select_related("recipient")`, ordered by recipient name);
  - `notices(*, type_=None, email_status=None, since=None, until=None) -> QuerySet[Notification]` (with `select_related("recipient")`, newest first).

- [ ] **Step 1: Write the failing tests** — `tests/test_api_b5b.py`. Turn `broadcasts` on in a fixture with `set_features(broadcasts=True)`, and patch `email.queue` as in Task 2. Cover:
  1. **Admin round trip.** An admin POSTs `{audience: "student", people: [id], message: "Hi", channels: ["email"]}` and gets 201, with `recipient_count` 1 and `skipped` 0. The GET list shows the row with `email.pending == 1` and `read == 0`. After `Notification.read_at` is set, the GET detail shows the recipient with `read_at` set and the list shows `read == 1`. DELETE gives 204, and then GET detail gives 404.
  2. **A 400 body.** `message` "" gives 400 with the error on `message`.
  3. **Codes.** Staff with `broadcast.view_any` only can GET but get 403 on POST and DELETE. Staff with `broadcast.create` can POST. Staff with no codes get 403.
  4. **Other roles.** `@pytest.mark.parametrize` over teacher, student and parent: every route gives 403.
  5. **Switch off.** Admin gets 404 on `broadcasts/` and `log/`; a student gets 403.
  6. **Impersonation.** With the session carrying `IMPERSONATOR_KEY` (`etqan.platform.permissions.IMPERSONATOR_KEY`), an admin POST gives 403 with code `identity.impersonating`. Set it via `client.session` and save, as B9b tests do; grep `IMPERSONATOR_KEY` in backend tests for the pattern.
  7. **Log.** It lists an automatic notice and a broadcast notice (create one with the `notice()` helper from `tests/conftest.py`). The `type`, `email_status` and `from`/`to` filters work. A bad `type` gives 400. Staff need `notification_log.view_any`.
  8. **Fixed query counts.** The list with 1 vs 5 broadcasts costs the same, and so does the log with 1 vs 5 rows (the `CaptureQueriesContext` pattern from Task 2).
  9. **Audience filter.** `GET broadcasts/?audience=student` filters.

  Write each as explicit test functions in the style of `test_api_b5a.py`.

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement.**
  - **Views:** `BroadcastListView` (GET `broadcast.view_any`, POST `broadcast.create`; POST adds `NotImpersonating` as a third permission class, which is fine for GET as well because admins impersonating only matter for POST). Then `BroadcastDetailView` (GET `broadcast.view_any`, DELETE `broadcast.delete`) and `NotificationLogView` (GET `notification_log.view_any`). Each has `feature = "broadcasts"`.
  - **Pagination:** use DRF `generics.GenericAPIView` pagination as `NotificationListView` does. The detail's recipients page uses `self.paginate_queryset` on `log.recipients(pk)` and returns `{**row, "message": full, "recipients": paginated}`. Follow the repo's paginated shape `{count, next, previous, results}` nested under `recipients`.
  - **Serializers:**
    - `BroadcastInput`:
      - `audience` ChoiceField of `Broadcast.Audience`;
      - `people` ListField(IntegerField, required=False);
      - `study_group` IntegerField(required=False, allow_null=True);
      - `message` CharField(allow_blank=True, trim_whitespace=False);
      - `channels` ListField(CharField).
    - `LogQuery`:
      - `type` ChoiceField(`NOTICE_TYPES`, required=False);
      - `email_status` ChoiceField(the four, required=False);
      - `from` and `to` as DateField(required=False).

      Map `from`/`to` to aware datetimes at local midnight in the academy timezone: `since` = start of `from`, `until` = start of the day after `to`.
  - **Registry:** add under `# ── phase B5 ──`:

```python
    # Slice B5b (Plan 43): the office's messages and the notice log.
    Resource("broadcast", "Broadcasts", "الرسائل الجماعية", ("view_any", "create", "delete")),
    Resource("notification_log", "Notification log", "سجل الإشعارات", ("view_any",)),
```

  - **`test_routes.py`:** add ROUTES rows for every method above, with `N` for ids, plus the feature entries for `/notifications/broadcasts/` and `/notifications/log/` following the B5a convention.

- [ ] **Step 4: Run.** `S django pytest etqan/notifications etqan/access -q` plus lint. Expected: PASS.

- [ ] **Step 5: Commit** `feat(notifications): broadcasts and notification log API (B5b)`.

---

### Task 4: Dashboard — broadcasts page, composer, detail

**Files:**
- Modify: `dashboard/src/features/notifications/schemas.ts`, `api.ts`, `queries.ts`, `index.ts`
- Create: `dashboard/src/features/notifications/BroadcastsPage.tsx`, `BroadcastComposer.tsx`, `BroadcastDetail.tsx`, and a test for each
- Create: `dashboard/src/routes/_authed/people.broadcasts.tsx`
- Modify: `dashboard/src/features/shell/nav.ts` (under `// ── phase B5 ──`) and its enumeration tests (`nav.test.ts`, `routes/permissions.test.ts`)
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode` gains `"broadcasts"`)
- Create: `dashboard/src/locales/en/broadcasts.json` and `ar/broadcasts.json` (wired into the `common` namespace the way other area files are; check `src/lib/i18n.ts` for how areas are collected)
- Regenerate: `routeTree.gen.ts` (via the dev server)

**Interfaces:**
- Consumes the Task 3 API.
- Produces these types:

```ts
export type Audience =
	| "admins" | "teachers" | "students" | "student" | "teacher" | "parent"
	| "all_students" | "all_teachers" | "all_parents" | "study_group";
export type Broadcast = {
	id: number; audience: Audience; audience_label: string; message: string;
	channels: string[]; created_by: string | null; created_at: string;
	recipient_count: number;
	email: { pending: number; sent: number; failed: number; skipped: number };
	read: number;
};
export type BroadcastRecipient = {
	id: number; name: string; role: string;
	email_status: "pending" | "sent" | "failed" | "skipped"; read_at: string | null;
};
export type BroadcastDetail = Broadcast & { recipients: Paginated<BroadcastRecipient> };
export type BroadcastInput = {
	audience: Audience; people?: number[]; message: string; channels: ["email"];
};
```

- Produces these `notificationsApi` additions: `broadcasts(params)`, `broadcast(id, params)`, `sendBroadcast(input)` (the result has `skipped`), `deleteBroadcast(id)`, and `log(params)` (the log is used by Task 5).

- [ ] **Step 1: Write the failing tests** (mock `./api`; use `CanProvider` with `staffMe(...)` and `adminMe` fixtures from `src/test/`; follow `TemplatesPage.test.tsx`):
  1. **The list.** It shows date, audience label, a message excerpt, sent/failed/pending chips, `read n / total` and the sender. The audience filter calls `broadcasts({audience})`.
  2. **The composer.**
     - The audience select offers ten options. `parent` and `all_parents` are hidden while `parents` is off; `study_group` is always hidden in this task.
     - Choosing `student` shows a single person picker. Choosing `teachers` shows a multi picker. `all_students` and `admins` show no picker.
     - Email is shown ticked and disabled.
     - Without `student.view_any`, the student picker is disabled with the hint.
     - Send opens a confirm naming the audience. Confirming calls `sendBroadcast` with `channels: ["email"]`, then shows a toast with the recipient and skipped counts.
     - A 400 `{message: [...]}` shows under the message field. A 400 on `audience` shows as a form error, translated by its code if present (use `useFieldError` as `TemplateDialog` does).
  3. **The detail drawer.** It shows the full message with its line breaks (`whitespace-pre-line`), and a recipients table with status chips and read state. Delete, with `broadcast.delete`, confirms and then calls `deleteBroadcast`; without the code it is absent.
  4. **No `broadcast.create`.** The "New broadcast" button is absent.

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement.**
  - **Pickers:** reuse the people search the people pages use. Grep `features/people` for the list API (`peopleApi.list(role, {q})` or similar). Build a small `PersonPicker` inside `BroadcastComposer.tsx` using the repo's `Select` and `Input`, or an existing combobox if one exists (grep `Combobox`). The multi picker shows chosen people as removable chips.
  - **Route:** `staticData: { permission: "broadcast.view_any", feature: "broadcasts" }`.
  - **Nav:** `office("/people/broadcasts", "broadcasts.nav.broadcasts", Megaphone, "people", "broadcast.view_any", "broadcasts")`. Import `Megaphone` from `lucide-react`.
  - **Strings:** put every string in `broadcasts.json`, en and ar, including the ten audience names with these Arabic names:

    | Value | Arabic |
    |---|---|
    | admins | مديرو النظام |
    | teachers | معلمون متعددون |
    | students | طلاب متعددون |
    | student | طالب محدد |
    | teacher | معلم محدد |
    | parent | ولي أمر محدد |
    | all_students | كل الطلاب |
    | all_teachers | كل المعلمين |
    | all_parents | كل أولياء الأمور |
    | study_group | مجموعة دراسية |

    The email status names in Arabic: قيد الانتظار / مرسل / فشل / لم يُرسل.

- [ ] **Step 4: Run.** The notifications and shell tests, tsc and lint. Expected: PASS.

- [ ] **Step 5: Commit** `feat(notifications): broadcasts page and composer (B5b)`.

---

### Task 5: Dashboard — notification log page; line breaks and clamp in notice bodies

**Files:**
- Create: `dashboard/src/features/notifications/NotificationLogPage.tsx` and its test
- Create: `dashboard/src/routes/_authed/people.notification-log.tsx`
- Modify: `dashboard/src/features/shell/nav.ts` (under `// ── phase B5 ──`) and its enumeration tests
- Modify: `dashboard/src/features/notifications/bits.tsx` (`NotificationText`: `whitespace-pre-line` on the body; a `clamp` prop for the bell giving `line-clamp-3`)
- Modify: `dashboard/src/features/notifications/NotificationBell.tsx` (pass `clamp`)
- Modify: `dashboard/src/locales/{en,ar}/broadcasts.json`

**Interfaces:**
- Consumes: `notificationsApi.log(params)` (Task 4), returning `Paginated<LogRow>`, where `LogRow = { id; created_at; type; recipient: {id; name; role}; title; email_status; read_at }`.

- [ ] **Step 1: Write the failing tests:**
  1. **The log page.** A table of date, type (translated: the automatic types reuse the labels from `TYPE_INFO`, and `broadcast` → "Broadcast" / "رسالة جماعية"), recipient (name and role), title, an email status chip, and read. The type, status and date filters call `log` with the params. A pager is present.
  2. **`NotificationText`.** A two-line body renders with `whitespace-pre-line`. With `clamp` it has `line-clamp-3`; without, it does not.
  3. **The bell.** It passes `clamp`; the `/notifications` page does not.

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement.**
  - Route: `staticData: { permission: "notification_log.view_any", feature: "broadcasts" }`.
  - Nav: `office("/people/notification-log", "broadcasts.nav.log", ScrollText, "people", "notification_log.view_any", "broadcasts")`.

- [ ] **Step 4: Run.** The notifications and shell tests, tsc and lint.

- [ ] **Step 5: Commit** `feat(notifications): notification log page and readable notice bodies (B5b)`.

---

### Task 6: e2e and gates

**Files:**
- Create: `dashboard/e2e/b5-broadcasts.spec.ts`

- [ ] **Step 1: Write the spec.**
  - Setup: `manage("set_features", "demo", "--on", "broadcasts")`.
  - Copy `visit`, `signInStudent` and `postAsAdmin` usage from `e2e/b5-templates.spec.ts`; never import from another spec.
  - Create a stamped student as the admin (`b5b-${stamp}@demo.test`) and sign them in.
  - As the admin, open `/app/people/broadcasts`, choose "One student" and pick the stamped student. Type the two-line message `Hello ${stamp}\nSecond line`, then Send and Confirm, and see the toast.
  - As the student, the bell shows "New message" and the body. Mailpit (`E2E_MAILPIT_URL`; see `e2e/mail.ts`) has an email to the student containing `Hello ${stamp}`. Opening the notification marks it read.
  - As the admin, the broadcast's detail shows the student with "Sent" and read. `/app/people/notification-log` filtered to type Broadcast lists the row. Delete the broadcast; it leaves the list.

- [ ] **Step 2: Run.**
  1. `just migrate`.
  2. `just e2e e2e/b5-broadcasts.spec.ts` until green. If the Vite container serves blank pages, `docker restart etqan-b5-dashboard-1`.
  3. The gates: `just test`, `just lint`, `just e2e`, and `S dashboard pnpm test:coverage` (thresholds above).

- [ ] **Step 3: Commit** `test(e2e): B5b broadcasts`.

---

### Task 7: Study-group audience (only once B2f is merged and R5 is done)

**Requires:** B2f merged; `scheduling.services.study_group_members(group_id) -> StudyGroupMembers(name, is_active, student_user_ids)` exported (ledger request R5). If either is missing when Tasks 1–6 are done, skip this task. Record it in the phase notes, and the audience moves to B5d (spec §7).

**Files:**
- Modify: `backend/etqan/notifications/services/broadcasts.py` (`_audience`)
- Modify: `backend/etqan/notifications/tests/test_broadcast_send.py`
- Modify: `dashboard/src/features/notifications/BroadcastComposer.tsx` and its test

**Interfaces:**
- Consumes: `scheduling_services.study_group_members`.
- Consumes: the B2f groups list endpoint `GET /api/v1/scheduling/groups/` (check the real path in B2f's `urls.py`).

- [ ] **Step 1: Write the failing backend tests:**
  1. A group with two active students and one inactive gives 2 rows, 1 skipped, and `audience_label` = the group name.
  2. `study_groups` off gives 400 `audience`.
  3. A missing group gives 400 `study_group`.
  4. An inactive group gives 400 `study_group`.
  5. A missing `study_group` gives 400 `study_group`.

- [ ] **Step 2: Implement.** In `_audience`, replace the "not available yet" refusal with:

```python
    if audience == A.STUDY_GROUP:
        if not features.enabled("study_groups"):
            raise ValidationError("Study groups are switched off.", field="audience")
        if study_group is None:
            raise ValidationError("Choose a study group.", field="study_group")
        try:
            group = scheduling_services.study_group_members(study_group)
        except NotFoundError:
            raise ValidationError("Choose a study group.", field="study_group") from None
        if not group.is_active:
            raise ValidationError("This group is not active.", field="study_group")
        found = identity_services.get_users(group.student_user_ids)
        return [found[i] for i in group.student_user_ids if i in found], group.name
```

Pass `study_group` through to `_audience`, and import `from etqan.scheduling import services as scheduling_services`. That import is allowed by the notifications contract.

- [ ] **Step 3: Dashboard.**
  - The composer offers `study_group` when `study_groups` is on.
  - It shows a group select (from the groups list API), which is disabled with a hint without `study_group.view_any`.
  - It sends `study_group: id`.
  - Tests cover each.

- [ ] **Step 4: Run** the backend notifications suite, the dashboard notifications tests, tsc, lint, and the b5-broadcasts e2e.

- [ ] **Step 5: Commit** `feat(notifications): study-group broadcast audience (B5b)`.
