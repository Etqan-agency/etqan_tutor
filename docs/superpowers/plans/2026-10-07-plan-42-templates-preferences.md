# Plan 42 — B5a Templates & preferences — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let each academy edit the ar/en text of every automatic notice, and let students, parents and teachers mute notice categories. The every-minute scan honours both.

**Architecture:** Everything lives in the existing tenant app `etqan.notifications` (owned by B5). There are two new tables:
- `NotificationTemplate`: per-type, per-language overrides;
- `NotificationOptOut`: a row per muted (user, category).

The catalogue `kinds.Kind` gains `category`, `roles` and `duty_roles`. `text.render` takes an optional override. The scan:
- drops muted `(hit, user)` pairs after `recipients.resolve`;
- renders with the overrides in `store`.

Each part is behind its own feature switch, off by default. The dashboard gets:
- a templates settings page;
- a preferences card on `/account`;
- the same card on the student, teacher and parent detail pages.

**Tech Stack:** Django 5 + DRF + django-tenants, pytest; React + TanStack Router/Query + react-hook-form + zod, vitest; Playwright e2e.

**Spec:** `docs/superpowers/specs/2026-10-07-b5-communication-design.md` (§2 B5-13, §5–§11).

**Requires:** — (no other phase's slice; B5a extends only merged Plan 8 code).

## Global Constraints

- Every new feature is registered in `etqan/platform/features.py`, under the `# ── phase B5 ──` marker, `built=True`, off by default:
  - `notification_templates`: "Notification templates" / "قوالب الإشعارات", group `communication`;
  - `notification_preferences`: "Notification preferences" / "تفضيلات الإشعارات", group `communication`.
- Shared lists: add lines only under the `── phase B5 ──` markers:
  - `features.py`;
  - `seed_dev.py` (`seed_b5(subdomain)`);
  - `dashboard/src/features/shell/nav.ts`.
- Outside the markers, B5 owns these edits:
  - the `pyproject.toml` contract "no app imports notifications" gains `ignore_imports` entry `"etqan.tenants.seeds.b5 -> etqan.notifications.services"`;
  - the `FeatureCode` union in `dashboard/src/features/identity/schemas.ts` gains both codes;
  - one mount line each in `routes/_authed/account.tsx` and `people.{students,teachers,parents}.$personId.tsx`.
- No migration touches an existing table. Exactly one new migration, `etqan/notifications/migrations/0002_templates_optouts.py`.
- The scan's query count must not grow with the number of hits. Templates add one query, only while `notification_templates` is on and there are pairs. Preferences add one query, only while `notification_preferences` is on and there are pairs.
- Error code for a bad placeholder: `notifications.bad_placeholder` (D25 `ValidationError(message, field=, code=)`).
- Limits: title 1–150 characters, body 1–1000 characters, both after `.strip()`.
- Languages: `ar`, `en` only (D22: Spanish readers already get the academy default via `text.language_for`).
- Translations: en and ar only, key-for-key equal, in the existing `dashboard/src/locales/{en,ar}/notifications.json`. Do not create an `es` file.
- Backend coverage ≥ 80 %. Dashboard: lines/statements ≥ 80, branches/functions ≥ 70.
- Run every tool inside this stream's stack, from the meta worktree root
  (`/home/abdulkhalek/Projects/etqan_tutor-wt/b5`); `.env.stream` selects the stack. Define once per shell:
  `S() { (set -a; . ./.env.stream; set +a; docker compose -f docker-compose.local.yml exec -T "$@"); }`
  - backend tests: `S django pytest <paths> -q` (full gate: `just test-backend`);
  - migrations / manage.py: `just _stack-manage <command>` (never a host `manage.py`);
  - import contracts: `S django lint-imports`;
  - dashboard tests: `S dashboard pnpm vitest run <paths>`; types: `S dashboard pnpm tsc --noEmit`.

## Review Focus

1. **Duty notices to a teacher must survive the teacher's opt-out.** `session.late` is a duty for the teacher only: the student and parents can still mute it. A muted parent must not stop the teacher's copy. Task 3 tests both.
2. **A template using `{sessions}` on a type other than `subscription.low` must be refused**, even though `render` would fill it with "". So must `{{` inside a placeholder name, `{student!r}`, `{0}` and a lone `}`. Task 2 tests each.
3. **Overrides are read only while the switch is on.** Turning `notification_templates` off makes the very next scan use the built-ins, and the saved rows survive. Task 2 tests both.
4. **A staff member holding only `teacher.view` asking for a student's preferences gets 404, not 403 and not the data.** Task 4 tests it.
5. **The preferences card must not show switches for a student without an email address, and must not crash on `/people/students/new`.** Task 7 tests both.

---

### Task 1: Notice catalogue — categories, roles, duties, placeholders, overrides in render

**Files:**
- Modify: `backend/etqan/notifications/kinds.py`
- Modify: `backend/etqan/notifications/finders.py` (an `AUDIENCES` table the finders read)
- Modify: `backend/etqan/notifications/text.py` (`PLACEHOLDERS`, `SAMPLE_FACTS`, `render(..., template=None)`)
- Create: `backend/etqan/notifications/tests/test_kinds.py`
- Modify: `backend/etqan/notifications/tests/test_text.py`

**Interfaces:**
- Produces in `kinds`:
  - the constants `SESSIONS = "sessions"`, `PAYMENTS = "payments"`, `SCHEDULE = "schedule"`, `REPORTS_HOMEWORK = "reports_homework"` and `CHAT = "chat"`;
  - `CATEGORIES = (SESSIONS, PAYMENTS, SCHEDULE, REPORTS_HOMEWORK, CHAT)`;
  - `PREFERENCE_ROLES = ("student", "parent", "teacher")`;
  - `Kind.category: str`, `Kind.roles: tuple[str, ...]` and `Kind.duty_roles: tuple[str, ...]`;
  - `categories_for(role: str) -> tuple[str, ...]`.
- Produces in `finders`:
  - `AUDIENCES: dict[str, tuple[str, ...]]`, type → audience parts;
  - `PART_ROLES: dict[str, tuple[str, ...]]`.
- Produces in `text`:
  - `PLACEHOLDERS: dict[str, tuple[str, ...]]`;
  - `SAMPLE_FACTS: dict[str, Facts]`, keyed by target kind;
  - `render(type_, facts, *, language, timezone, template: tuple[str, str] | None = None) -> tuple[str, str]`.

- [ ] **Step 1: Write the failing tests** — `tests/test_kinds.py`:

```python
"""Spec B5a §8.3: every type has a category, its roles match its finder's
audience, and a role sees only categories with a non-duty type for it."""

import pytest

from etqan.notifications import finders
from etqan.notifications import kinds
from etqan.notifications import text


def test_every_type_has_a_known_category():
    for kind in kinds.KINDS:
        assert kind.category in kinds.CATEGORIES, kind.type


def test_roles_match_the_finders_audiences():
    for kind in kinds.KINDS:
        parts = finders.AUDIENCES[kind.type]
        roles = {role for part in parts for role in finders.PART_ROLES[part]}
        assert set(kind.roles) == roles, kind.type
        assert set(kind.duty_roles) <= roles, kind.type


def test_duties_are_the_teachers_late_and_missing_report():
    duties = {k.type: k.duty_roles for k in kinds.KINDS if k.duty_roles}
    assert duties == {
        kinds.LATE: ("teacher",),
        kinds.REPORT_MISSING: ("teacher",),
    }


@pytest.mark.parametrize(
    ("role", "expected"),
    [
        ("student", (kinds.SESSIONS, kinds.PAYMENTS)),
        ("parent", (kinds.SESSIONS, kinds.PAYMENTS)),
        ("teacher", (kinds.SESSIONS,)),
        ("admin", ()),
        ("staff", ()),
    ],
)
def test_categories_for_each_role(role, expected):
    assert kinds.categories_for(role) == expected


def test_builtin_templates_use_only_their_placeholders():
    from string import Formatter

    for type_, languages in text.TEMPLATES.items():
        for title, body in languages.values():
            for piece in (title, body):
                names = {n for _, n, _, _ in Formatter().parse(piece) if n}
                assert names <= set(text.PLACEHOLDERS[type_]), type_


def test_placeholders_per_target():
    assert text.PLACEHOLDERS[kinds.REMINDER] == ("student", "course", "time")
    assert text.PLACEHOLDERS[kinds.REPORT_MISSING] == ("student", "course", "time")
    assert text.PLACEHOLDERS[kinds.SUBSCRIPTION_LOW] == (
        "student", "course", "sessions",
    )
    assert text.PLACEHOLDERS[kinds.SUBSCRIPTION_EXPIRED] == ("student", "course")
    assert text.PLACEHOLDERS[kinds.INVOICE_ISSUED] == (
        "student", "number", "amount", "due_on",
    )
```

Append to `tests/test_text.py`:

```python
def test_render_uses_an_override_with_the_same_values():
    facts = text.SAMPLE_FACTS[kinds.SESSION]
    title, body = text.render(
        kinds.REMINDER,
        facts,
        language="en",
        timezone="UTC",
        template=("Hi {student}", "{course} at {time} {{ok}}"),
    )
    assert title == "Hi Sara Ahmed"
    assert body == "Qur'an at 2026-01-15 16:00 (UTC) {ok}"


def test_samples_cover_every_target():
    assert set(text.SAMPLE_FACTS) == set(kinds.TARGETS)
    assert text.SAMPLE_FACTS[kinds.SUBSCRIPTION].remaining == 3
    assert text.SAMPLE_FACTS[kinds.INVOICE].number == "INV-0001"
```

(`test_text.py` already imports `text` and `kinds`; add the imports if not.)

- [ ] **Step 2: Run to verify they fail**

Run: `S django pytest etqan/notifications/tests/test_kinds.py etqan/notifications/tests/test_text.py -q`
Expected: FAIL (`AttributeError: module 'etqan.notifications.kinds' has no attribute 'CATEGORIES'`, …).

- [ ] **Step 3: Implement**

In `kinds.py`, after the type constants:

```python
# Spec B5a T-8: the person's notice categories (TH's student toggles).
SESSIONS = "sessions"
PAYMENTS = "payments"
SCHEDULE = "schedule"
REPORTS_HOMEWORK = "reports_homework"
CHAT = "chat"
CATEGORIES = (SESSIONS, PAYMENTS, SCHEDULE, REPORTS_HOMEWORK, CHAT)
# B5-13: admins and staff have no preferences; office alerts are their job.
PREFERENCE_ROLES = ("student", "parent", "teacher")
FAMILY_ROLES = ("student", "parent")
```

Extend `Kind` (keyword fields after `high`):

```python
    category: str = SESSIONS
    # The roles the type reaches (its finder's audience, `finders.AUDIENCES`)
    # and those for whom it is a duty nobody mutes (B5-13).
    roles: tuple[str, ...] = ()
    duty_roles: tuple[str, ...] = ()
```

Rewrite `KINDS`:

```python
KINDS = (
    Kind(EARLY_REMINDER, SESSION, 120, 30, 1440, roles=FAMILY_ROLES),
    Kind(REMINDER, SESSION, 60, 5, 720, roles=FAMILY_ROLES),
    Kind(TEACHER_REMINDER, SESSION, 30, 5, 720, roles=("teacher",)),
    Kind(
        LATE, SESSION, 5, 1, 55,
        roles=("teacher", *FAMILY_ROLES), duty_roles=("teacher",),
    ),
    Kind(STUDENT_ABSENT, SESSION, None, roles=("parent",)),
    Kind(
        SUBSCRIPTION_LOW, SUBSCRIPTION, 2, 0, 10,
        category=PAYMENTS, roles=(*FAMILY_ROLES, "admin"),
    ),
    Kind(
        SUBSCRIPTION_EXPIRED, SUBSCRIPTION, None,
        category=PAYMENTS, roles=(*FAMILY_ROLES, "admin"),
    ),
    Kind(INVOICE_ISSUED, INVOICE, None, category=PAYMENTS, roles=FAMILY_ROLES),
    Kind(
        INVOICE_OVERDUE, INVOICE, None,
        category=PAYMENTS, roles=(*FAMILY_ROLES, "admin"),
    ),
    Kind(
        REPORT_MISSING, SESSION, None,
        category=REPORTS_HOMEWORK, roles=("teacher",), duty_roles=("teacher",),
    ),
)  # fmt: skip
BY_TYPE = {kind.type: kind for kind in KINDS}
TYPES = tuple(BY_TYPE)


def categories_for(role: str) -> tuple[str, ...]:
    """The categories ``role`` may mute: those with a type that reaches it
    and is not a duty for it, in `CATEGORIES` order (spec B5a T-9)."""
    if role not in PREFERENCE_ROLES:
        return ()
    wanted = {
        kind.category
        for kind in KINDS
        if role in kind.roles and role not in kind.duty_roles
    }
    return tuple(category for category in CATEGORIES if category in wanted)
```

In `finders.py`, after `FAMILY = (STUDENT, GUARDIANS)`:

```python
# Who each type tells (spec §4.2); `kinds.Kind.roles` mirrors it (a test).
AUDIENCES: dict[str, tuple[str, ...]] = {
    kinds.EARLY_REMINDER: FAMILY,
    kinds.REMINDER: FAMILY,
    kinds.TEACHER_REMINDER: (TEACHER,),
    kinds.LATE: (TEACHER, *FAMILY),
    kinds.STUDENT_ABSENT: (GUARDIANS,),
    kinds.SUBSCRIPTION_LOW: (*FAMILY, ADMINS),
    kinds.SUBSCRIPTION_EXPIRED: (*FAMILY, ADMINS),
    kinds.INVOICE_ISSUED: (PAYER,),
    kinds.INVOICE_OVERDUE: (PAYER, ADMINS),
    kinds.REPORT_MISSING: (TEACHER,),
}
# The user roles an audience part can be (a payer is a student or a parent).
PART_ROLES: dict[str, tuple[str, ...]] = {
    STUDENT: ("student",),
    GUARDIANS: ("parent",),
    TEACHER: ("teacher",),
    ADMINS: ("admin",),
    PAYER: ("student", "parent"),
}
```

Then replace every literal audience in the finders with `AUDIENCES[<type>]`:
- `_reminder(type_, audience)` → `_reminder(type_)`, using `AUDIENCES[type_]`;
- `late` uses `AUDIENCES[kinds.LATE]`;
- `student_absent` uses `AUDIENCES[kinds.STUDENT_ABSENT]`;
- `_subscription_hit` uses `AUDIENCES[type_]` instead of `(*FAMILY, ADMINS)`;
- `invoice_issued` and `invoice_overdue` pass `AUDIENCES[...]`;
- `report_missing` uses `AUDIENCES[kinds.REPORT_MISSING]`;
- `FINDERS` becomes `_reminder(kinds.EARLY_REMINDER)` and so on.

Behaviour is unchanged, and the existing finder and scan tests prove it.

In `text.py`, after `TEMPLATES`:

```python
# Spec B5a T-2: the facts a template may name, by what the type is about.
_BY_TARGET = {
    kinds.SESSION: ("student", "course", "time"),
    kinds.SUBSCRIPTION: ("student", "course"),
    kinds.INVOICE: ("student", "number", "amount", "due_on"),
}
PLACEHOLDERS: dict[str, tuple[str, ...]] = {
    kind.type: _BY_TARGET[kind.target]
    + (("sessions",) if kind.type == kinds.SUBSCRIPTION_LOW else ())
    for kind in kinds.KINDS
}
```

After the `Facts` dataclass:

```python
# Spec B5a §8.2: what a preview fills in, one per target kind.
_SAMPLE = {"student": "Sara Ahmed", "course_ar": "القرآن", "course_en": "Qur'an"}
SAMPLE_FACTS: dict[str, Facts] = {
    kinds.SESSION: Facts(**_SAMPLE, starts_at=datetime(2026, 1, 15, 16, 0, tzinfo=UTC)),
    kinds.SUBSCRIPTION: Facts(**_SAMPLE, remaining=3),
    kinds.INVOICE: Facts(
        student="Sara Ahmed",
        number="INV-0001",
        amount_minor=150000,
        currency="EGP",
        due_on=date(2026, 1, 31),
    ),
}
```

Import `UTC` from `datetime`. In `render`, add the keyword parameter `template: tuple[str, str] | None = None` and replace `title, body = TEMPLATES[type_][language]` with:

```python
    title, body = template or TEMPLATES[type_][language]
```

Update the docstring: "``template`` is an academy's override (spec B5a §8.1)".

- [ ] **Step 4: Run the notifications suite**

Run: `S django pytest etqan/notifications -q`
Expected: all PASS, including the untouched finder and scan tests.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/notifications
git -C backend commit -m "feat(notifications): categories, roles, duties and placeholders per notice type (B5a)"
```

---

### Task 2: Templates — model, checker, services, overrides in the scan, feature switch

**Files:**
- Modify: `backend/etqan/notifications/models.py` (`NotificationTemplate`, `NotificationOptOut`; both models land here so there is one migration)
- Create: `backend/etqan/notifications/migrations/0002_templates_optouts.py` (generated)
- Create: `backend/etqan/notifications/services/templates.py`
- Modify: `backend/etqan/notifications/services/scan.py` (`store` passes overrides)
- Modify: `backend/etqan/notifications/services/__init__.py`
- Modify: `backend/etqan/platform/features.py` (both B5 switches under the marker)
- Create: `backend/etqan/notifications/tests/test_templates.py`

**Interfaces:**
- Consumes: `text.PLACEHOLDERS`, `text.SAMPLE_FACTS`, `text.render(..., template=)`, `text.LANGUAGES` (Task 1).
- Produces:
  - `services.templates.BAD_PLACEHOLDER = "notifications.bad_placeholder"`;
  - `TemplateRow` (frozen dataclass: `type, language, title, body, customised, default_title, default_body, placeholders, enabled`);
  - `check(type_, title, body) -> tuple[str, str]` (stripped);
  - `listing() -> list[TemplateRow]`;
  - `save(type_, language, *, title, body) -> TemplateRow`;
  - `reset(type_, language) -> TemplateRow`;
  - `preview(type_, language, *, title, body) -> tuple[str, str]`;
  - `overrides() -> dict[tuple[str, str], tuple[str, str]]`.
- Exported from `etqan.notifications.services` as `template_rows`, `save_template`, `reset_template` and `preview_template`.
- Models `NotificationTemplate` and `NotificationOptOut`. Task 3 uses `NotificationOptOut`.

- [ ] **Step 1: Write the failing tests** — `tests/test_templates.py`:

```python
"""Spec B5a T-1..T-6, §8.1, §8.2."""

import pytest

from etqan.notifications import kinds
from etqan.notifications import services
from etqan.notifications.models import Notification
from etqan.notifications.models import NotificationTemplate
from etqan.notifications.services import templates
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db


@pytest.mark.parametrize(
    "bad",
    [
        "{nobody}",            # unknown name
        "{}",                  # positional
        "{0}",                 # positional by index
        "{student.name}",      # attribute
        "{student[0]}",        # index
        "{student!r}",         # conversion
        "{student:>5}",        # format spec
        "lone } brace",        # unbalanced
        "open { brace",        # unbalanced
        "{sessions}",          # only subscription.low may use it
    ],
)
def test_bad_placeholders_are_refused(bad):
    with pytest.raises(ValidationError) as caught:
        templates.check(kinds.REMINDER, "Title", bad)
    assert caught.value.code == templates.BAD_PLACEHOLDER
    assert caught.value.field == "body"


def test_title_is_checked_too():
    with pytest.raises(ValidationError) as caught:
        templates.check(kinds.REMINDER, "{nobody}", "fine")
    assert caught.value.field == "title"


def test_doubled_braces_and_unused_placeholders_are_fine():
    assert templates.check(kinds.SUBSCRIPTION_LOW, "  Left: {sessions} ", "{{x}}") == (
        "Left: {sessions}",
        "{{x}}",
    )


@pytest.mark.parametrize(
    ("title", "body", "field"),
    [("   ", "b", "title"), ("t", "  ", "body"), ("t" * 151, "b", "title"), ("t", "b" * 1001, "body")],
)
def test_lengths(title, body, field):
    with pytest.raises(ValidationError) as caught:
        templates.check(kinds.REMINDER, title, body)
    assert caught.value.field == field


def test_listing_shows_defaults_then_overrides():
    rows = {(r.type, r.language): r for r in templates.listing()}
    assert len(rows) == len(kinds.KINDS) * 2
    row = rows[(kinds.REMINDER, "en")]
    assert (row.customised, row.title) == (False, "Starting soon: {course}")
    assert row.placeholders == ("student", "course", "time")
    assert row.enabled is True
    templates.save(kinds.REMINDER, "en", title="Soon: {course}", body="At {time}")
    row = {(r.type, r.language): r for r in templates.listing()}[(kinds.REMINDER, "en")]
    assert (row.customised, row.title, row.default_title) == (
        True,
        "Soon: {course}",
        "Starting soon: {course}",
    )


def test_save_twice_keeps_one_row_and_reset_deletes_it():
    templates.save(kinds.REMINDER, "ar", title="أ", body="ب")
    templates.save(kinds.REMINDER, "ar", title="ج", body="د")
    assert NotificationTemplate.objects.get().title == "ج"
    row = templates.reset(kinds.REMINDER, "ar")
    assert row.customised is False
    assert not NotificationTemplate.objects.exists()
    templates.reset(kinds.REMINDER, "ar")  # a no-op


@pytest.mark.parametrize(("type_", "language"), [("nope", "en"), (kinds.REMINDER, "es")])
def test_unknown_type_or_language_is_not_found(type_, language):
    with pytest.raises(NotFoundError):
        templates.save(type_, language, title="t", body="b")


def test_preview_renders_samples_in_the_academy_timezone(academy_timezone):
    academy_timezone("Africa/Cairo")
    title, body = templates.preview(
        kinds.INVOICE_OVERDUE, "en", title="{number}", body="{amount} by {due_on}"
    )
    assert (title, body) == ("INV-0001", "1,500.00 EGP by 2026-01-31")
    title, body = templates.preview(kinds.REMINDER, "en", title="t", body="{time}")
    assert body == "2026-01-15 18:00 (Africa/Cairo)"


def test_preview_validates_like_save():
    with pytest.raises(ValidationError):
        templates.preview(kinds.REMINDER, "en", title="t", body="{nobody}")
```

`academy_timezone` is a small fixture you add to `tests/conftest.py`. It sets the academy's timezone through `etqan.academy.services`. Find the setter in `etqan/academy/services.py` (`update_settings` or the equivalent; the conftest docstring says the academy is on UTC).

Scan tests go in the same file. Use the existing `family`, `clock` and `only` fixtures from `test_scan.py`: move `only` into `tests/conftest.py` so both files share it, and import `TEN`/`REMINDER_AT` from `test_scan` or redefine them.

```python
def test_scan_renders_an_override_only_while_the_switch_is_on(
    family, clock, only, set_features
):
    only(kinds.REMINDER)
    templates.save(kinds.REMINDER, "en", title="Custom {course}", body="b")
    set_features(notification_templates=False)
    clock.set(REMINDER_AT)
    services.scan_now()
    yusuf = Notification.objects.get(recipient=family.student)
    assert yusuf.title == "Starting soon: Tajweed"
    Notification.objects.all().delete()
    set_features(notification_templates=True)
    services.scan_now()
    assert Notification.objects.get(recipient=family.student).title == "Custom Tajweed"
```

Check the `family` namespace attribute names in `conftest.py` (`build_family` returns a `SimpleNamespace`) and use the real ones. Also add a query-count test: the scan with templates on costs the same number of queries for one hit as for three. Copy the existing `CaptureQueriesContext` query-count test in `test_scan.py` and turn `notification_templates` on.

- [ ] **Step 2: Run to verify they fail**

Run: `S django pytest etqan/notifications/tests/test_templates.py -q`
Expected: FAIL (`ImportError: cannot import name 'NotificationTemplate'`).

- [ ] **Step 3: Implement**

`models.py`, appended:

```python
LANGUAGE_CHOICES = [("ar", "ar"), ("en", "en")]
CATEGORY_CHOICES = [(value, value) for value in CATEGORIES]


class NotificationTemplate(models.Model):
    """An academy's own text for one type in one language (spec B5a T-1).
    No row: the built-in text (`text.TEMPLATES`)."""

    type = models.CharField(max_length=32, choices=TYPE_CHOICES)
    language = models.CharField(max_length=2, choices=LANGUAGE_CHOICES)
    title = models.CharField(max_length=150)
    body = models.TextField()
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["type", "language"], name="notification_template_unique"
            )
        ]

    def __str__(self):
        return f"NotificationTemplate<{self.type}, {self.language}>"


class NotificationOptOut(models.Model):
    """One muted category of one person (spec B5a T-10). No row: on."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+"
    )
    category = models.CharField(max_length=24, choices=CATEGORY_CHOICES)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["user", "category"], name="notification_optout_unique"
            )
        ]

    def __str__(self):
        return f"NotificationOptOut<{self.user_id}, {self.category}>"
```

Import `CATEGORIES` from `etqan.notifications.kinds`. Generate the migration inside the stream:

`just _stack-manage makemigrations notifications --name templates_optouts` (the file appears in `backend/` through the bind mount).

`services/templates.py`:

```python
"""Editable notice text (spec B5a T-1..T-7, §8.1, §8.2): an academy's
override per type and language, checked once for save and preview."""

from dataclasses import dataclass
from string import Formatter

from etqan.academy import services as academy_services
from etqan.notifications import kinds
from etqan.notifications import text
from etqan.notifications.models import NotificationTemplate
from etqan.notifications.services import settings
from etqan.platform import features
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

BAD_PLACEHOLDER = "notifications.bad_placeholder"
FEATURE = "notification_templates"
LIMITS = {"title": 150, "body": 1000}


@dataclass(frozen=True)
class TemplateRow:
    type: str
    language: str
    title: str
    body: str
    customised: bool
    default_title: str
    default_body: str
    placeholders: tuple[str, ...]
    enabled: bool


def _known(type_: str, language: str) -> None:
    if type_ not in kinds.BY_TYPE or language not in text.LANGUAGES:
        raise NotFoundError("Template", f"{type_}/{language}")


def _refuse(field: str, allowed: tuple[str, ...]) -> ValidationError:
    names = ", ".join(f"{{{name}}}" for name in allowed)
    return ValidationError(
        f"Use only these placeholders: {names}. Write {{{{ and }}}} for a brace.",
        field=field,
        code=BAD_PLACEHOLDER,
    )


def _check_text(field: str, value: str, allowed: tuple[str, ...]) -> None:
    try:
        parts = list(Formatter().parse(value))
    except ValueError:
        raise _refuse(field, allowed) from None
    for _literal, name, spec, conversion in parts:
        if name is None:
            continue
        if name not in allowed or spec or conversion:
            raise _refuse(field, allowed)


def check(type_: str, title: str, body: str) -> tuple[str, str]:
    """The stripped ``(title, body)``, or a 400 on the first bad field."""
    allowed = text.PLACEHOLDERS[type_]
    cleaned = {"title": title.strip(), "body": body.strip()}
    for field, value in cleaned.items():
        if not value:
            raise ValidationError("This field is required.", field=field)
        if len(value) > LIMITS[field]:
            raise ValidationError(
                f"Use at most {LIMITS[field]} characters.", field=field
            )
        _check_text(field, value, allowed)
    return cleaned["title"], cleaned["body"]


def _row(type_: str, language: str, override, enabled: bool) -> TemplateRow:
    default_title, default_body = text.TEMPLATES[type_][language]
    return TemplateRow(
        type=type_,
        language=language,
        title=override.title if override else default_title,
        body=override.body if override else default_body,
        customised=override is not None,
        default_title=default_title,
        default_body=default_body,
        placeholders=text.PLACEHOLDERS[type_],
        enabled=enabled,
    )


def listing() -> list[TemplateRow]:
    """Every type in `KINDS` order, ar then en."""
    switches = settings.current()
    saved = {(t.type, t.language): t for t in NotificationTemplate.objects.all()}
    return [
        _row(kind.type, language, saved.get((kind.type, language)),
             switches[kind.type].enabled)
        for kind in kinds.KINDS
        for language in text.LANGUAGES
    ]  # fmt: skip


def _one(type_: str, language: str) -> TemplateRow:
    override = NotificationTemplate.objects.filter(
        type=type_, language=language
    ).first()
    return _row(type_, language, override, settings.current()[type_].enabled)


def save(type_: str, language: str, *, title: str, body: str) -> TemplateRow:
    _known(type_, language)
    title, body = check(type_, title, body)
    NotificationTemplate.objects.update_or_create(
        type=type_, language=language, defaults={"title": title, "body": body}
    )
    return _one(type_, language)


def reset(type_: str, language: str) -> TemplateRow:
    _known(type_, language)
    NotificationTemplate.objects.filter(type=type_, language=language).delete()
    return _one(type_, language)


def preview(type_: str, language: str, *, title: str, body: str) -> tuple[str, str]:
    _known(type_, language)
    template = check(type_, title, body)
    facts = text.SAMPLE_FACTS[kinds.BY_TYPE[type_].target]
    academy = academy_services.get_settings()
    return text.render(
        type_, facts, language=language, timezone=academy.timezone, template=template
    )


def overrides() -> dict[tuple[str, str], tuple[str, str]]:
    """What the scan renders with: empty while the switch is off (T-6)."""
    if not features.enabled(FEATURE):
        return {}
    return {
        (t.type, t.language): (t.title, t.body)
        for t in NotificationTemplate.objects.all()
    }
```

In `services/scan.py`:
- `_row(hit, user, key, *, now, academy, overrides)` passes `template=overrides.get((hit.type, language))` to `text.render`;
- in `store`, after `existing` is read and before `new` is built, add `custom = templates.overrides()`, and pass `overrides=custom` to each `_row`;
- import `from etqan.notifications.services import templates`.

Add to `services/__init__.py`:

```python
from etqan.notifications.services.templates import listing as template_rows
from etqan.notifications.services.templates import preview as preview_template
from etqan.notifications.services.templates import reset as reset_template
from etqan.notifications.services.templates import save as save_template
```

Add the four names to `__all__` in alphabetical order.

In `platform/features.py`, under `# ── phase B5 ──`:

```python
    # Slice B5a (Plan 42): editable notice text and per-person preferences.
    Feature(
        "notification_templates",
        "Notification templates",
        "قوالب الإشعارات",
        "communication",
        built=True,
    ),
    Feature(
        "notification_preferences",
        "Notification preferences",
        "تفضيلات الإشعارات",
        "communication",
        built=True,
    ),
```

If a features test counts the registry or lists the built codes (search `etqan/platform/tests` for `"articles"` or `BUILT`), update it.

- [ ] **Step 4: Run**

Run: `S django pytest etqan/notifications etqan/platform -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/notifications etqan/platform/features.py
git -C backend commit -m "feat(notifications): editable notice templates with placeholder checks (B5a)"
```

---

### Task 3: Preferences — service and the scan honouring opt-outs

**Files:**
- Create: `backend/etqan/notifications/services/preferences.py`
- Modify: `backend/etqan/notifications/services/scan.py`
- Modify: `backend/etqan/notifications/services/__init__.py`
- Create: `backend/etqan/notifications/tests/test_preferences.py`

**Interfaces:**
- Consumes: `kinds.categories_for`, `kinds.BY_TYPE`, `kinds.PREFERENCE_ROLES`, `NotificationOptOut` (Tasks 1–2).
- Produces in `services.preferences`:
  - `FEATURE = "notification_preferences"`;
  - `of(user) -> list[tuple[str, bool]]`;
  - `change(user, changes: list[tuple[str, bool]]) -> list[tuple[str, bool]]`;
  - `opted_out(user_ids) -> set[tuple[int, str]]`;
  - `muted(type_: str, user, off: set[tuple[int, str]]) -> bool`.
- Exported as `preferences_of` and `change_preferences`.

- [ ] **Step 1: Write the failing tests** — `tests/test_preferences.py`:

```python
"""Spec B5a T-8..T-12, §8.4."""

import pytest

from etqan.notifications import kinds
from etqan.notifications import services
from etqan.notifications.models import Notification
from etqan.notifications.models import NotificationOptOut
from etqan.notifications.services import preferences
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db


def test_everything_starts_on(family):
    assert preferences.of(family.student) == [
        (kinds.SESSIONS, True),
        (kinds.PAYMENTS, True),
    ]
    assert preferences.of(family.teacher) == [(kinds.SESSIONS, True)]
    assert preferences.of(family.admin) == []


def test_change_is_idempotent(family):
    off = [(kinds.PAYMENTS, False)]
    preferences.change(family.student, off)
    assert preferences.change(family.student, off) == [
        (kinds.SESSIONS, True),
        (kinds.PAYMENTS, False),
    ]
    assert NotificationOptOut.objects.count() == 1
    preferences.change(family.student, [(kinds.PAYMENTS, True)])
    assert not NotificationOptOut.objects.exists()


@pytest.mark.parametrize("category", ["nope", kinds.CHAT, kinds.PAYMENTS])
def test_a_category_the_role_lacks_is_refused(family, category):
    # A teacher has `sessions` only; chat has no type yet.
    with pytest.raises(ValidationError) as caught:
        preferences.change(family.teacher, [(category, False)])
    assert caught.value.field == "category"


def test_scan_skips_the_muted_and_keeps_the_others(
    family, clock, only, set_features
):
    set_features(notification_preferences=True)
    only(kinds.REMINDER)
    preferences.change(family.student, [(kinds.SESSIONS, False)])
    clock.set(REMINDER_AT)
    services.scan_now()
    told = set(Notification.objects.values_list("recipient_id", flat=True))
    assert family.student.pk not in told
    assert family.omar.pk in told


def test_duties_reach_a_teacher_who_muted_sessions(family, clock, only, set_features):
    set_features(notification_preferences=True)
    only(kinds.LATE)
    preferences.change(family.teacher, [(kinds.SESSIONS, False)])
    preferences.change(family.omar, [(kinds.SESSIONS, False)])
    clock.set(LATE_AT)
    services.scan_now()
    told = set(Notification.objects.values_list("recipient_id", flat=True))
    assert family.teacher.pk in told       # a duty for the teacher
    assert family.omar.pk not in told      # not a duty for a parent
    assert family.student.pk in told


def test_opt_outs_are_ignored_while_the_switch_is_off(
    family, clock, only, set_features
):
    set_features(notification_preferences=False)
    only(kinds.REMINDER)
    preferences.change(family.student, [(kinds.SESSIONS, False)])
    clock.set(REMINDER_AT)
    services.scan_now()
    assert Notification.objects.filter(recipient=family.student).exists()
```

Define `REMINDER_AT` and `LATE_AT` from the lesson time used in `test_scan.py`. `LATE_AT` must be a minute past start + 5 minutes, with no attendance marked; copy how `test_scan.py`'s late test sets it up. Use the real attribute names of the `family` namespace.

Add a query-count test: with the switch on and one opt-out row, a scan producing 1 hit and one producing 3 hits cost the same number of queries. Copy the existing pattern.

- [ ] **Step 2: Run to verify they fail**

Run: `S django pytest etqan/notifications/tests/test_preferences.py -q`
Expected: FAIL (`ImportError ... preferences`).

- [ ] **Step 3: Implement** `services/preferences.py`:

```python
"""Per-person notice preferences (spec B5a T-8..T-12, §8.4). A row in
`NotificationOptOut` mutes a category; no row means on."""

from django.db import transaction

from etqan.notifications import kinds
from etqan.notifications.models import NotificationOptOut
from etqan.platform.exceptions import ValidationError

FEATURE = "notification_preferences"


def of(user) -> list[tuple[str, bool]]:
    """The categories ``user``'s role may mute, each with whether it is on."""
    shown = kinds.categories_for(user.role)
    if not shown:
        return []
    off = set(
        NotificationOptOut.objects.filter(user=user).values_list("category", flat=True)
    )
    return [(category, category not in off) for category in shown]


@transaction.atomic
def change(user, changes: list[tuple[str, bool]]) -> list[tuple[str, bool]]:
    """Apply ``[(category, enabled)]``; every change is checked first. The
    same change twice changes nothing."""
    shown = kinds.categories_for(user.role)
    for category, _enabled in changes:
        if category not in shown:
            raise ValidationError("Unknown category.", field="category")
    off = [category for category, enabled in changes if not enabled]
    on = [category for category, enabled in changes if enabled]
    NotificationOptOut.objects.bulk_create(
        [NotificationOptOut(user=user, category=category) for category in off],
        ignore_conflicts=True,
    )
    NotificationOptOut.objects.filter(user=user, category__in=on).delete()
    return of(user)


def opted_out(user_ids) -> set[tuple[int, str]]:
    """``(user_id, category)`` of every opt-out of these users: one query."""
    return set(
        NotificationOptOut.objects.filter(user_id__in=list(user_ids)).values_list(
            "user_id", "category"
        )
    )


def muted(type_: str, user, off: set[tuple[int, str]]) -> bool:
    """Whether ``user`` muted this type (B5-13: never a duty, never the
    office)."""
    kind = kinds.BY_TYPE[type_]
    return (
        user.role in kinds.PREFERENCE_ROLES
        and user.role not in kind.duty_roles
        and (user.pk, kind.category) in off
    )
```

In `services/scan.py`:

```python
def honour_preferences(pairs: list[tuple[Hit, object]]) -> list[tuple[Hit, object]]:
    """Spec B5a §8.4: drop the pairs whose recipient muted the type's
    category. One query, and none while the switch is off."""
    if not pairs or not features.enabled(preferences.FEATURE):
        return pairs
    off = preferences.opted_out({user.pk for _hit, user in pairs})
    return [(hit, user) for hit, user in pairs if not preferences.muted(hit.type, user, off)]
```

In `scan()`: `created = store(honour_preferences(recipients.resolve(hits)), now=now)`. Import `from etqan.notifications.services import preferences`.

Export in `services/__init__.py`:

```python
from etqan.notifications.services.preferences import change as change_preferences
from etqan.notifications.services.preferences import of as preferences_of
```

Add both to `__all__`.

- [ ] **Step 4: Run**

Run: `S django pytest etqan/notifications -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/notifications
git -C backend commit -m "feat(notifications): per-person notice preferences honoured by the scan (B5a)"
```

---

### Task 4: API — templates and preferences endpoints, route table

**Files:**
- Modify: `backend/etqan/notifications/api/views.py`
- Modify: `backend/etqan/notifications/api/serializers.py`
- Modify: `backend/etqan/notifications/api/payloads.py`
- Modify: `backend/etqan/notifications/api/urls.py`
- Modify: `backend/etqan/access/tests/test_routes.py` (`ROUTES`, `SELF_SERVICE`)
- Create: `backend/etqan/notifications/tests/test_api_b5a.py`

**Interfaces:**
- Consumes: the services from Tasks 2–3 (`services.template_rows`, `save_template`, `reset_template`, `preview_template`, `preferences_of`, `change_preferences`), `recipients.eligible(user)`, `identity.services.get_user`, `platform.permissions.HasCode`, `FeatureOn`, `codes_of` and `role_of`, and `platform.features.enabled`.
- Produces these routes under `/api/v1/notifications/`:
  - `templates/`;
  - `templates/preview/`;
  - `templates/<type>/<language>/` (type matches `[a-z_.]+`);
  - `preferences/`;
  - `preferences/<int:user_id>/`.
- Produces these payloads:
  - template row: `{type, language, title, body, customised, default_title, default_body, placeholders: [..], enabled}`;
  - preferences: `{categories: [{category, enabled}], notifiable: bool}`.

- [ ] **Step 1: Write the failing tests** — `tests/test_api_b5a.py`:

```python
"""Spec B5a §9."""

import pytest

URL = "/api/v1/notifications/"
T = f"{URL}templates/"
P = f"{URL}preferences/"


@pytest.fixture
def on(set_features):
    set_features(notification_templates=True, notification_preferences=True)


def test_admin_lists_saves_previews_and_resets(api_for, on):
    admin = api_for("admin")
    rows = admin.get(T).json()
    assert {r["language"] for r in rows} == {"ar", "en"}
    url = f"{T}session.reminder/en/"
    saved = admin.put(url, {"title": "Hi {student}", "body": "At {time}"}, format="json")
    assert saved.status_code == 200
    assert saved.json()["customised"] is True
    bad = admin.put(url, {"title": "x", "body": "{nobody}"}, format="json")
    assert bad.status_code == 400
    assert bad.json()["code"] == "notifications.bad_placeholder"
    preview = admin.post(
        f"{T}preview/",
        {"type": "session.reminder", "language": "en", "title": "{student}", "body": "b"},
        format="json",
    )
    assert preview.json() == {"title": "Sara Ahmed", "body": "b"}
    assert admin.delete(url).json()["customised"] is False
    assert admin.put(f"{T}nope/en/", {"title": "t", "body": "b"}, format="json").status_code == 404


def test_template_codes(staff_for, on):
    viewer = staff_for("notification_settings.view")
    assert viewer.get(T).status_code == 200
    assert viewer.put(f"{T}session.reminder/en/", {"title": "t", "body": "b"}, format="json").status_code == 403
    assert staff_for().get(T).status_code == 403


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_templates_are_office_only(api_for, on, role):
    assert api_for(role).get(T).status_code == 403


def test_templates_404_while_off_after_the_role_check(api_for, staff_for, set_features):
    set_features(notification_templates=False)
    assert api_for("admin").get(T).status_code == 404
    assert api_for("student").get(T).status_code == 403


def test_own_preferences(api_for, on):
    student = api_for("student")
    body = student.get(P).json()
    assert body == {
        "categories": [
            {"category": "sessions", "enabled": True},
            {"category": "payments", "enabled": True},
        ],
        "notifiable": True,
    }
    changed = student.patch(
        P, {"categories": [{"category": "payments", "enabled": False}]}, format="json"
    )
    assert changed.json()["categories"][1] == {"category": "payments", "enabled": False}
    assert student.patch(
        P, {"categories": [{"category": "chat", "enabled": False}]}, format="json"
    ).status_code == 400
    assert api_for("admin").get(P).json()["categories"] == []


def test_own_preferences_404_while_off(api_for, set_features):
    set_features(notification_preferences=False)
    assert api_for("student").get(P).status_code == 404


def test_office_reads_and_changes_a_persons(api_for, staff_for, on):
    student = api_for("student").user
    url = f"{P}{student.pk}/"
    assert staff_for("student.view").get(url).status_code == 200
    assert staff_for("student.view").patch(
        url, {"categories": []}, format="json"
    ).status_code == 403  # holds no .update code at all
    editor = staff_for("student.view", "student.update")
    assert editor.patch(
        url, {"categories": [{"category": "sessions", "enabled": False}]}, format="json"
    ).status_code == 200


def test_the_wrong_role_code_is_404_not_403(api_for, staff_for, on):
    student = api_for("student").user
    assert staff_for("teacher.view").get(f"{P}{student.pk}/").status_code == 404


def test_targets_that_are_not_people_are_404(api_for, on):
    admin = api_for("admin")
    staff = api_for("staff").user
    assert admin.get(f"{P}{staff.pk}/").status_code == 404
    assert admin.get(f"{P}999999/").status_code == 404


def test_a_parent_needs_the_parents_feature(api_for, set_features, on):
    parent = api_for("parent").user
    set_features(parents=False)
    assert api_for("admin").get(f"{P}{parent.pk}/").status_code == 404


def test_a_student_without_email_is_not_notifiable(api_for, on):
    from etqan.identity import services as identity_services

    student = identity_services.create_person(
        "student", full_name="No Mail", email=None, invite=False
    )
    body = api_for("admin").get(f"{P}{student.pk}/").json()
    assert body["notifiable"] is False


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_people_cannot_read_each_other(api_for, on, role):
    other = api_for("student").user
    assert api_for(role).get(f"{P}{other.pk}/").status_code == 403
```

- [ ] **Step 2: Run to verify they fail**

Run: `S django pytest etqan/notifications/tests/test_api_b5a.py -q`
Expected: FAIL (404s, since the routes do not exist yet).

- [ ] **Step 3: Implement**

`serializers.py`, add:

```python
class TemplateInput(serializers.Serializer):
    # The service trims and checks lengths and placeholders (spec B5a T-2/T-3).
    title = serializers.CharField(allow_blank=True, trim_whitespace=False)
    body = serializers.CharField(allow_blank=True, trim_whitespace=False)


class PreviewInput(TemplateInput):
    type = serializers.CharField()
    language = serializers.CharField()


class PreferenceChange(serializers.Serializer):
    category = serializers.CharField()
    enabled = serializers.BooleanField()


class PreferencesInput(serializers.Serializer):
    categories = PreferenceChange(many=True)
```

`payloads.py`, add:

```python
def template_row(row) -> dict:
    return {
        "type": row.type,
        "language": row.language,
        "title": row.title,
        "body": row.body,
        "customised": row.customised,
        "default_title": row.default_title,
        "default_body": row.default_body,
        "placeholders": list(row.placeholders),
        "enabled": row.enabled,
    }


def preferences(rows, *, notifiable: bool) -> dict:
    return {
        "categories": [
            {"category": category, "enabled": enabled} for category, enabled in rows
        ],
        "notifiable": notifiable,
    }
```

`views.py`, add:

```python
TEMPLATES_FEATURE = "notification_templates"
PREFERENCES_FEATURE = "notification_preferences"
PEOPLE = ("student", "teacher", "parent")


class TemplateListView(APIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"GET": "notification_settings.view"}
    feature = TEMPLATES_FEATURE

    def get(self, request):
        return Response([payloads.template_row(r) for r in services.template_rows()])


class TemplateDetailView(APIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {
        "PUT": "notification_settings.update",
        "DELETE": "notification_settings.update",
    }
    feature = TEMPLATES_FEATURE

    def put(self, request, type_, language):
        body = TemplateInput(data=request.data)
        body.is_valid(raise_exception=True)
        row = services.save_template(type_, language, **body.validated_data)
        return Response(payloads.template_row(row))

    def delete(self, request, type_, language):
        return Response(payloads.template_row(services.reset_template(type_, language)))


class TemplatePreviewView(APIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"POST": "notification_settings.view"}
    feature = TEMPLATES_FEATURE

    def post(self, request):
        body = PreviewInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        title, text_ = services.preview_template(
            data["type"], data["language"], title=data["title"], body=data["body"]
        )
        return Response({"title": title, "body": text_})


def _changes(request) -> list[tuple[str, bool]]:
    body = PreferencesInput(data=request.data)
    body.is_valid(raise_exception=True)
    return [(c["category"], c["enabled"]) for c in body.validated_data["categories"]]


def _preferences(user, rows) -> Response:
    return Response(payloads.preferences(rows, notifiable=recipients.eligible(user)))


# Spec B5a §9: one's own; every signed-in role (admins and staff get none).
class MyPreferencesView(APIView):
    permission_classes = [IsAuthenticated, FeatureOn]
    feature = PREFERENCES_FEATURE

    def get(self, request):
        return _preferences(request.user, services.preferences_of(request.user))

    def patch(self, request):
        rows = services.change_preferences(request.user, _changes(request))
        return _preferences(request.user, rows)


class PersonPreferencesView(APIView):
    """The office on a student's, teacher's or parent's page. Any of the
    three codes passes `HasCode`; the target's own role code is then checked
    here, and a miss is a 404 so nothing tells who exists (spec B5a §9)."""

    permission_classes = [HasCode, FeatureOn]
    permission_codes = {
        "GET": tuple(f"{role}.view" for role in PEOPLE),
        "PATCH": tuple(f"{role}.update" for role in PEOPLE),
    }
    feature = PREFERENCES_FEATURE

    def _target(self, request, user_id: int, verb: str):
        user = identity_services.get_user(user_id)  # NotFoundError → 404
        if user.role not in PEOPLE:
            raise NotFoundError("Person", user_id)
        if user.role == "parent" and not features.enabled("parents"):
            raise NotFoundError("Person", user_id)
        if role_of(request.user) != "admin" and (
            f"{user.role}.{verb}" not in codes_of(request.user)
        ):
            raise NotFoundError("Person", user_id)
        return user

    def get(self, request, user_id):
        user = self._target(request, user_id, "view")
        return _preferences(user, services.preferences_of(user))

    def patch(self, request, user_id):
        user = self._target(request, user_id, "update")
        return _preferences(user, services.change_preferences(user, _changes(request)))
```

Imports to add:
- `IsAuthenticated` (already imported);
- `from etqan.identity import services as identity_services`;
- `from etqan.notifications import recipients`;
- `from etqan.platform import features`;
- `from etqan.platform.exceptions import NotFoundError`;
- `from etqan.platform.permissions import FeatureOn, codes_of, role_of`;
- the new serializers.

`notifications` may import `identity.services` (allowed by its contract).

`urls.py`, add (before `<int:pk>/read/`):

```python
    path("templates/", views.TemplateListView.as_view(), name="templates"),
    path("templates/preview/", views.TemplatePreviewView.as_view(), name="template-preview"),
    re_path(
        r"^templates/(?P<type_>[a-z_.]+)/(?P<language>[a-z]{2})/$",
        views.TemplateDetailView.as_view(),
        name="template",
    ),
    path("preferences/", views.MyPreferencesView.as_view(), name="preferences"),
    path(
        "preferences/<int:user_id>/",
        views.PersonPreferencesView.as_view(),
        name="person-preferences",
    ),
```

Import `re_path`.

`access/tests/test_routes.py`:
- in `ROUTES`, after the two notification settings lines, add:

```python
    ("GET", "/api/v1/notifications/templates/", "notification_settings.view"),
    ("POST", "/api/v1/notifications/templates/preview/", "notification_settings.view"),
    ("PUT", "/api/v1/notifications/templates/session.reminder/en/", "notification_settings.update"),
    ("DELETE", "/api/v1/notifications/templates/session.reminder/en/", "notification_settings.update"),
    ("GET", f"/api/v1/notifications/preferences/{N}/", ("student.view", "teacher.view", "parent.view")),
    ("PATCH", f"/api/v1/notifications/preferences/{N}/", ("student.update", "teacher.update", "parent.update")),
```

- in `SELF_SERVICE`, add `"etqan.notifications.api.views.MyPreferencesView": "the caller's own notification preferences"`.

If the route test switches features per route (look for how B6 routes with `FeatureOn` are listed), follow that convention so both new features are on while the route test runs.

- [ ] **Step 4: Run**

Run: `S django pytest etqan/notifications etqan/access -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/notifications etqan/access/tests/test_routes.py
git -C backend commit -m "feat(notifications): templates and preferences API (B5a)"
```

---

### Task 5: Seeds and import contract

**Files:**
- Create: `backend/etqan/tenants/seeds/b5.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (import, and one line under `# ── phase B5 ──`)
- Modify: `backend/pyproject.toml` (`ignore_imports` of "no app imports notifications")
- Modify: `backend/etqan/tenants/tests/test_seed_dev.py` (or the seeds test that covers b6; follow it)

**Interfaces:**
- Consumes: `services.save_template` (Task 2).
- Produces: `seed_b5(subdomain: str) -> None`.

- [ ] **Step 1: Write the failing test.** Add to the seed tests, following the existing `seed_b6` test:

```python
def test_seed_b5_customises_subscription_expired_once(demo_academy):
    from etqan.notifications.models import NotificationTemplate
    from etqan.tenants.seeds.b5 import seed_b5

    seed_b5("demo")
    seed_b5("demo")
    assert set(
        NotificationTemplate.objects.values_list("type", "language")
    ) == {("subscription.expired", "ar"), ("subscription.expired", "en")}


def test_seed_b5_skips_other_academies(other_academy):
    from etqan.notifications.models import NotificationTemplate
    from etqan.tenants.seeds.b5 import seed_b5

    seed_b5("other")
    assert not NotificationTemplate.objects.exists()
```

Adapt the fixture names to whatever the existing b6 seed test uses to be inside the demo or other academy.

- [ ] **Step 2: Run to verify it fails**

Run: `S django pytest etqan/tenants -q -k seed_b5`
Expected: FAIL (`ModuleNotFoundError`).

- [ ] **Step 3: Implement** `seeds/b5.py`:

```python
"""Phase B5 demo data (slice B5a): the demo academy's own text for the
"subscription ended" notice, in both languages. Demo academy only;
idempotent; the switch itself comes from `seed_dev.FEATURES`."""

from etqan.notifications import services as notifications

TEXT = {
    "en": (
        "Time to renew: {course}",
        "{student}'s {course} subscription has ended. Renew to keep the same "
        "teacher and time.",
    ),
    "ar": (
        "حان وقت التجديد: {course}",
        "انتهى اشتراك {student} في {course}. جدّد للحفاظ على المعلم والموعد نفسيهما.",
    ),
}


def seed_b5(subdomain: str) -> None:
    if subdomain != "demo":
        return
    for language, (title, body) in TEXT.items():
        notifications.save_template(
            "subscription.expired", language, title=title, body=body
        )
```

In `seed_dev.py`:
- add `from etqan.tenants.seeds.b5 import seed_b5` next to the b6 import;
- under `# ── phase B5 ──`, add `        seed_b5(subdomain)`.

In `pyproject.toml`'s "no app imports notifications" `ignore_imports`, add `"etqan.tenants.seeds.b5 -> etqan.notifications.services",`.

- [ ] **Step 4: Run**

Run: `S django pytest etqan/tenants -q && S django lint-imports`
Expected: PASS; every contract is kept.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/tenants pyproject.toml
git -C backend commit -m "feat(seeds): B5a demo notice template"
```

---

### Task 6: Dashboard — templates page

**Files:**
- Modify: `dashboard/src/features/notifications/schemas.ts` (`TemplateRow`, `TemplateLanguage`, `PreferenceCategory`, `Preferences`)
- Modify: `dashboard/src/features/notifications/api.ts` (`templates`, `saveTemplate`, `resetTemplate`, `previewTemplate`, plus the four preference calls used by Task 7)
- Modify: `dashboard/src/features/notifications/queries.ts` (`useNotificationTemplates`, `useSaveTemplate`, `useResetTemplate`, `usePreviewTemplate`)
- Create: `dashboard/src/features/notifications/TemplatesPage.tsx`, `TemplateDialog.tsx`, `TemplatesPage.test.tsx`
- Modify: `dashboard/src/features/notifications/index.ts`
- Create: `dashboard/src/routes/_authed/settings.notification-templates.tsx`
- Modify: `dashboard/src/features/shell/nav.ts` (under `// ── phase B5 ──`)
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode` gains `"notification_templates" | "notification_preferences"`)
- Modify: `dashboard/src/locales/{en,ar}/notifications.json`
- Regenerate: `dashboard/src/routeTree.gen.ts` (by the router plugin / `npx tsr generate`; never hand-edited)

**Interfaces:**
- Consumes: the API of Task 4.
- Produces these types:

```ts
export type TemplateLanguage = "ar" | "en";
export type TemplateRow = {
	type: NotificationType;
	language: TemplateLanguage;
	title: string;
	body: string;
	customised: boolean;
	default_title: string;
	default_body: string;
	placeholders: string[];
	enabled: boolean;
};
export type PreferenceCategory =
	| "sessions" | "payments" | "schedule" | "reports_homework" | "chat";
export type Preferences = {
	categories: { category: PreferenceCategory; enabled: boolean }[];
	notifiable: boolean;
};
```

- Produces these `notificationsApi` additions:

```ts
	templates: async () => (await api.get<TemplateRow[]>(`${N}templates/`)).data,
	saveTemplate: async (type: NotificationType, language: TemplateLanguage, text: { title: string; body: string }) =>
		(await api.put<TemplateRow>(`${N}templates/${type}/${language}/`, text)).data,
	resetTemplate: async (type: NotificationType, language: TemplateLanguage) =>
		(await api.delete<TemplateRow>(`${N}templates/${type}/${language}/`)).data,
	previewTemplate: async (draft: { type: NotificationType; language: TemplateLanguage; title: string; body: string }) =>
		(await api.post<{ title: string; body: string }>(`${N}templates/preview/`, draft)).data,
	preferences: async (userId?: number) =>
		(await api.get<Preferences>(userId ? `${N}preferences/${userId}/` : `${N}preferences/`)).data,
	updatePreferences: async (changes: Preferences["categories"], userId?: number) =>
		(await api.patch<Preferences>(userId ? `${N}preferences/${userId}/` : `${N}preferences/`, { categories: changes })).data,
```

- Produces `TemplatesPage` (exported) and the query key `notificationTemplatesKey = ["notification-templates"]`.

- [ ] **Step 1: Write the failing tests** — `TemplatesPage.test.tsx`. Mock `./api` as `NotificationSettingsForm.test.tsx` does, and render inside `CanProvider` with `staffMe(...)` from `@/test/access-fixtures` (read that file for its signature). Cases:
  1. **Groups and badges.** Lists the four groups (Sessions, Subscriptions, Invoices, Reports). "Session reminder" shows an "Customised (EN)" badge when the `en` row has `customised: true`, and an "Off" chip when `enabled: false`.
  2. **Edit and save.** Clicking a row opens the dialog on the AR tab (the academy default comes first, `ar`). Switching to EN shows the title and body inputs filled with the row's text. Clicking the `{student}` chip inserts `{student}` at the body caret. Save calls `saveTemplate("session.reminder", "en", {title, body})` and shows a toast.
  3. **Server 400.** `saveTemplate` rejects with an AxiosError 400 `{ "body": ["Use only these placeholders: …"], "code": "notifications.bad_placeholder" }`, and the message renders under the body field. Map it with `applyServerErrors` as `NotificationSettingsForm` does.
  4. **Preview.** The Preview button calls `previewTemplate` with the current draft and shows the returned title and body in a "Preview" box.
  5. **Reset.** "Reset to default" shows only for a customised language. It asks for confirmation (`Confirm` from `@/components/Confirm`), then calls `resetTemplate`.
  6. **Without `notification_settings.update`.** The inputs are read-only and Save, Reset and the chips are absent; Preview stays.
  7. **The settings link.** "Change on/off and timing" (a link to `/settings/academy`) shows only with `academy_settings.view`.

Write each as an `it(...)` with explicit `await screen.findBy…` / `userEvent` steps in the style of `NotificationSettingsForm.test.tsx`.

- [ ] **Step 2: Run to verify they fail**

Run: `S dashboard pnpm vitest run src/features/notifications/TemplatesPage.test.tsx`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement**

`TemplatesPage.tsx`:
- `useNotificationTemplates()` (`useQuery` on `notificationsApi.templates`);
- group the rows by the prefix before the first `.` of the type: `session`, `subscription`, `invoice`, `report`. Use the same group headings `NotificationSettingsForm` uses (reuse its `TYPE_INFO` label for each type's name);
- render one row per type (the ar and en rows merged), with badges and an Edit button opening `TemplateDialog`;
- loading shows a `Spinner`, an error shows an `Alert`.

`TemplateDialog.tsx`:
- props `{ type, rows: { ar: TemplateRow; en: TemplateRow }, canEdit: boolean, onClose }`;
- language tabs: two `Button`s with `aria-pressed`, `ar` first;
- per tab a react-hook-form form `{ title, body }` with `Input` and `Textarea`;
- placeholder chips: buttons that insert `` `{${name}}` `` at the textarea's `selectionStart` (keep a ref to the last focused field, title or body);
- Preview: `usePreviewTemplate().mutateAsync(draft)`, with the result in a bordered box with `role="status"` and `aria-label` "Preview";
- Save: `useSaveTemplate`, which `setQueryData`s the returned row into `notificationTemplatesKey`; a toast on success; a 400 goes through `applyServerErrors`;
- Reset: `Confirm`, then `useResetTemplate`;
- use `Dialog`, `DialogContent`, `DialogTitle` and `DialogFooter` from `@/ui` as `curriculum/LevelDialog.tsx` does.

Route `settings.notification-templates.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { TemplatesPage } from "@/features/notifications";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/settings/notification-templates")({
	staticData: {
		permission: "notification_settings.view",
		feature: "notification_templates",
	},
	component: function NotificationTemplatesRoute() {
		const { t } = useTranslation();
		usePageTitle(t("notifications.templates.title"));
		return (
			<>
				<PageHeader
					title={t("notifications.templates.title")}
					description={t("notifications.templates.subtitle")}
				/>
				<TemplatesPage />
			</>
		);
	},
});
```

`nav.ts`, under `// ── phase B5 ──` (pick an icon already imported in nav.ts or import `MessageSquareText` from `lucide-react`):

```ts
	office(
		"/settings/notification-templates",
		"notifications.nav.templates",
		MessageSquareText,
		"settings",
		"notification_settings.view",
		"notification_templates",
	),
```

Locales: add to both `notifications.json` files. Keep the keys equal; the Arabic is given here.
- `nav.templates`: "Notification templates" / "قوالب الإشعارات".
- `templates.title`: same as `nav.templates`.
- `templates.subtitle`: "The text of each automatic notice, in Arabic and English." / "نص كل إشعار تلقائي بالعربية والإنجليزية."
- `templates.customised`: "Customised ({{language}})" / "مخصّص ({{language}})".
- `templates.off`: "Off" / "متوقف".
- `templates.edit`: "Edit" / "تعديل".
- `templates.titleLabel`: "Title" / "العنوان".
- `templates.bodyLabel`: "Message" / "الرسالة".
- `templates.placeholders`: "Insert" / "إدراج".
- `templates.preview`: "Preview" / "معاينة".
- `templates.save`: "Save" / "حفظ".
- `templates.saved`: "Template saved" / "تم حفظ القالب".
- `templates.reset`: "Reset to default" / "استعادة النص الافتراضي".
- `templates.resetConfirm`: "Use the built-in text again for this language?" / "هل تريد العودة إلى النص الافتراضي لهذه اللغة؟".
- `templates.settingsLink`: "Change on/off and timing" / "تغيير التشغيل والتوقيت".
- `templates.lang.ar`: "Arabic" / "العربية".
- `templates.lang.en`: "English" / "الإنجليزية".

`FeatureCode`: add `| "notification_templates" | "notification_preferences"`. If a dashboard test lists the feature codes, update it.

Regenerate the route tree the way the repo does (the running dev server's router plugin rewrites `routeTree.gen.ts` on a new route file; else `S dashboard pnpm exec tsr generate`); never hand-edit it.

- [ ] **Step 4: Run**

Run: `S dashboard pnpm vitest run src/features/notifications src/features/shell && S dashboard pnpm tsc --noEmit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add -A src
git -C dashboard commit -m "feat(notifications): notice templates settings page (B5a)"
```

---

### Task 7: Dashboard — preferences card on the account and people pages

**Files:**
- Create: `dashboard/src/features/notifications/PreferencesCard.tsx`, `PreferencesCard.test.tsx`
- Modify: `dashboard/src/features/notifications/queries.ts` (`usePreferences(userId?)`, `useUpdatePreferences(userId?)`)
- Modify: `dashboard/src/features/notifications/index.ts`
- Modify: `dashboard/src/routes/_authed/account.tsx` (one line)
- Modify: `dashboard/src/routes/_authed/people.students.$personId.tsx`, `people.teachers.$personId.tsx`, `people.parents.$personId.tsx` (one line each)
- Modify: `dashboard/src/locales/{en,ar}/notifications.json`

**Interfaces:**
- Consumes: `notificationsApi.preferences` and `updatePreferences` (Task 6), `Preferences`, `hasFeature`, `useCan` and `useHasFeature`.
- Produces: `<NotificationPreferencesCard />` (own) and `<NotificationPreferencesCard userId={number} resource="student" | "teacher" | "parent" />` (office mode).

- [ ] **Step 1: Write the failing tests** — `PreferencesCard.test.tsx` (mock `./api`):
  1. **Own.** The card shows "Session notifications" and "Payment reminders" switches (checkboxes with `role="switch"` or the repo `Checkbox`), both checked. Unchecking "Payment reminders" calls `updatePreferences([{category:"payments", enabled:false}], undefined)`, and the box stays unchecked.
  2. **Optimistic revert.** `updatePreferences` rejects, so the box re-checks and an error toast shows.
  3. **Office mode, read-only.** `CanProvider` with `student.view` only: the switches render disabled.
  4. **Office mode, editable.** `student.update` added: the switches are enabled, and toggling one calls `updatePreferences(..., 42)`.
  5. **Not notifiable.** `notifiable: false`: shows "This student has no email address, so they receive no notices." and no switches.
  6. **No categories.** `categories: []` (an admin's own): the card renders nothing.
  7. **Feature off.** `notification_preferences` off (`hasFeature` false via the `CanProvider` me fixture): renders nothing and makes no API call.
  8. **Wrong permission or feature.** Office mode for `resource="parent"` while `parents` is off, or without `parent.view`: renders nothing, no call.

- [ ] **Step 2: Run to verify they fail**

Run: `S dashboard pnpm vitest run src/features/notifications/PreferencesCard.test.tsx`
Expected: FAIL.

- [ ] **Step 3: Implement**

`queries.ts`:

```ts
export const preferencesKey = (userId?: number) =>
	["notification-preferences", userId ?? "me"] as const;

export function usePreferences(userId?: number, { enabled = true } = {}) {
	return useQuery({
		queryKey: preferencesKey(userId),
		queryFn: () => notificationsApi.preferences(userId),
		enabled,
	});
}

export function useUpdatePreferences(userId?: number) {
	const qc = useQueryClient();
	const key = preferencesKey(userId);
	return useMutation({
		mutationFn: (changes: Preferences["categories"]) =>
			notificationsApi.updatePreferences(changes, userId),
		onMutate: async (changes) => {
			await qc.cancelQueries({ queryKey: key });
			const before = qc.getQueryData<Preferences>(key);
			if (before) {
				const next = new Map(changes.map((c) => [c.category, c.enabled]));
				qc.setQueryData<Preferences>(key, {
					...before,
					categories: before.categories.map((c) => ({
						...c,
						enabled: next.get(c.category) ?? c.enabled,
					})),
				});
			}
			return { before };
		},
		onError: (_error, _changes, context) => {
			if (context?.before) qc.setQueryData(key, context.before);
		},
		onSuccess: (data) => qc.setQueryData(key, data),
	});
}
```

`PreferencesCard.tsx`:
- compute `allowed` from:
  - `useHasFeature()("notification_preferences")`;
  - in office mode, `can(`${resource}.view`)`;
  - for a parent, `useHasFeature()("parents")`;
- call `usePreferences(userId, { enabled: allowed })`;
- render `null` when not allowed, when loading has no data yet, or when `categories` is empty;
- otherwise a `Card` titled `t("notifications.preferences.title")`;
- when `notifiable` is false, the note `t("notifications.preferences.notNotifiable")`;
- else one `Checkbox` per category, labelled `t(`notifications.preferences.category.${category}`)`, with a description `t(`notifications.preferences.hint.${category}`)`; disabled in office mode without `can(`${resource}.update`)`;
- on change, `mutate([{category, enabled}])`, and `onError` shows `toast.error(t("notifications.preferences.failed"))`.

Mounts:
- **`account.tsx`:** add `<NotificationPreferencesCard />` inside `CardGrid` after `MyProfileCard`, and import it from `@/features/notifications`.
- **The three people routes:** after the form, add
  `{personId !== "new" ? <NotificationPreferencesCard userId={Number(personId)} resource="student" /> : null}`,
  with `resource` set to `"teacher"` or `"parent"` respectively.

Locales (en / ar):
- `preferences.title`: "Notification preferences" / "تفضيلات الإشعارات".
- `preferences.category.sessions`: "Session notifications" / "إشعارات الحصص".
- `preferences.category.payments`: "Payment reminders" / "تذكيرات الدفع".
- `preferences.category.schedule`: "Schedule updates" / "تحديثات الجدول".
- `preferences.category.reports_homework`: "Reports & homework" / "التقارير والواجبات".
- `preferences.category.chat`: "Chat notifications" / "إشعارات المحادثات".
- `preferences.hint.sessions`: "Reminders before sessions, lateness and absence." / "تذكيرات قبل الحصص والتأخر والغياب."
- `preferences.hint.payments`: "Invoices, overdue payments and subscriptions running out." / "الفواتير والمدفوعات المتأخرة والاشتراكات القاربة على الانتهاء."
- `preferences.hint.schedule`: "Changes to your timetable." / "التغييرات على جدولك."
- `preferences.hint.reports_homework`: "Session reports and homework." / "تقارير الحصص والواجبات."
- `preferences.hint.chat`: "New chat messages." / "رسائل المحادثة الجديدة."
- `preferences.notNotifiable`: "This student has no email address, so they receive no notices." / "لا يملك هذا الطالب بريدًا إلكترونيًا، لذا لا تصله أي إشعارات."
- `preferences.failed`: "Could not save your choice." / "تعذّر حفظ اختيارك."

- [ ] **Step 4: Run**

Run: `S dashboard pnpm vitest run src/features/notifications src/routes && S dashboard pnpm tsc --noEmit`
Expected: PASS. The existing `account.test.tsx` still passes: the card renders nothing while its feature is off in that test's fixture, and makes no call.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add -A src
git -C dashboard commit -m "feat(notifications): notice preferences card on account and people pages (B5a)"
```

---

### Task 8: e2e and the full gates

**Files:**
- Create: `dashboard/e2e/b5-templates.spec.ts`

**Interfaces:**
- Consumes:
  - `manage("set_features", "demo", "--on", "notification_templates", "notification_preferences")` (see `e2e/manage.ts` and its use in `b6-curriculum.spec.ts`);
  - the `login`, `DEMO_URL`, `DEMO_ADMIN` and `DEV_PASSWORD` fixtures;
  - b6's `signInStudent` pattern for a student session (copy the helper into this spec; never import from another spec file).

- [ ] **Step 1: Write the spec:**

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, login } from "./fixtures";
import { manage } from "./manage";

// Plan 42 (B5a, spec 2026-10-07): editable notice text and preferences.
test.beforeAll(() => {
	manage("set_features", "demo", "--on", "notification_templates", "notification_preferences");
});

test("an admin customises, previews and resets a notice", async ({ page }) => {
	await login(page, DEMO_URL, DEMO_ADMIN);
	await page.goto(`${DEMO_URL}/app/settings/notification-templates`);
	await page.getByRole("row", { name: /Session reminder/ }).getByRole("button", { name: "Edit" }).click();
	const dialog = page.getByRole("dialog");
	await dialog.getByRole("button", { name: "English" }).click();
	await dialog.getByLabel("Title").fill("Soon: {course} (e2e)");
	await dialog.getByRole("button", { name: "Preview" }).click();
	await expect(dialog.getByRole("status", { name: "Preview" })).toContainText("Soon: Qur'an (e2e)");
	await dialog.getByRole("button", { name: "Save" }).click();
	await expect(page.getByText("Template saved")).toBeVisible();
	await expect(page.getByRole("row", { name: /Session reminder/ })).toContainText("Customised (EN)");
	await page.getByRole("row", { name: /Session reminder/ }).getByRole("button", { name: "Edit" }).click();
	await dialog.getByRole("button", { name: "English" }).click();
	await dialog.getByRole("button", { name: "Reset to default" }).click();
	await page.getByRole("button", { name: /confirm|reset/i }).last().click();
	await expect(page.getByRole("row", { name: /Session reminder/ })).not.toContainText("Customised (EN)");
});

test("a student turns payment reminders off and it stays off", async ({ browser }) => {
	const page = await signInStudent(browser); // copied from b6-curriculum.spec.ts
	await page.goto(`${DEMO_URL}/app/account`);
	const payments = page.getByLabel("Payment reminders");
	if (!(await payments.isChecked())) await payments.check(); // a re-run starts on
	await payments.uncheck();
	await page.reload();
	await expect(page.getByLabel("Payment reminders")).not.toBeChecked();
	await page.getByLabel("Payment reminders").check(); // leave it on for the next run
});
```

Copy `signInStudent` (and anything it needs) from `b6-curriculum.spec.ts` into this file and adapt its constants. Match the role, label and button names to what Task 6/7 actually render. The step must leave the demo data as it found it.

- [ ] **Step 2: Run the stack's e2e for this spec, then everything**

Run, from the meta worktree, with the stack up (`just dev-backend`):
- `just e2e e2e/b5-templates.spec.ts`;
- then `just test`, `just lint`, `just e2e`.

Expected: all green. Backend coverage ≥ 80 %; the dashboard thresholds are met.

- [ ] **Step 3: Commit**

```bash
git -C dashboard add e2e/b5-templates.spec.ts
git -C dashboard commit -m "test(e2e): B5a templates and preferences"
```
