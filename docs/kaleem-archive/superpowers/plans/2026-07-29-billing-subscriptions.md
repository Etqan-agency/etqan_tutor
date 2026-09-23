# Billing Subscriptions (Phase B — B1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a parent or adult student subscribe to a monthly plan with Stripe, mirror Stripe's
subscription state via webhooks, and expose `billing.services.is_entitled_to(user, capability)` for
other modules to gate on — plus the dashboard UI to subscribe, see, and cancel a subscription.

**Architecture:** A new `kaleem.billing` Django module (models + `services.py` + `api/`) that never
imports another module's models: it calls `kaleem.identity.services` and talks to Stripe *only*
through a `PaymentProvider` Protocol. The provider does all Stripe-shape parsing and returns a
normalized `WebhookEvent`, so `services.py` contains zero Stripe payload knowledge and unit tests
run against a fake provider with no network. The dashboard replaces the scaffold `/billing`
placeholder with a real feature slice (`src/features/billing/`).

**Tech Stack:** Django 5 + DRF + pytest/pytest-django (backend, `backend/` submodule); Stripe Python
SDK; React 19 + TanStack Router/Query + Zod + vitest + jest-axe + i18next (dashboard submodule).

**Spec:** `docs/superpowers/specs/2026-07-09-billing-subscriptions-design.md` (read it first).

## Global Constraints

- **D3 TDD, 100% line + branch coverage** on every new backend and dashboard file. Failing test
  first, always. `kaleem/**` is measured (`pyproject.toml` `[tool.coverage.run]`), `*/migrations/*`
  and `*/tests/*` omitted.
- **No module may import another module's models.** `billing` may import `kaleem.platform` and call
  `kaleem.identity.services` only. Enforced by a new import-linter contract (Task 1).
- **Business logic lives in `services.py`.** Models are dumb data structures; views are thin.
- **Typed exceptions only** — `kaleem.platform.exceptions.{ValidationError, PermissionDeniedError,
  NotFoundError}`. Never `raise Exception`, never stringify a bare exception into an API error.
- **CSRF stays on everywhere except `POST /api/v1/billing/webhook/`**, which is authenticated by the
  Stripe signature instead. This is the only `csrf_exempt` in the codebase and requires ADR-0025
  (Task 8) plus an inline comment at the exemption site.
- **No secrets in code.** Stripe keys come from env via `django-environ`
  (`DJANGO_STRIPE_SECRET_KEY`, `DJANGO_STRIPE_WEBHOOK_SECRET`); production must fail loud if unset,
  matching the `DJANGO_FRONTEND_URL` pattern in `config/settings/production.py`.
- **Money is integer minor units** (`display_amount`), currency is a 3-letter lowercase ISO code
  (Stripe's convention). Never floats.
- **Datetimes are timezone-aware UTC** (`django.utils.timezone.now()`, `datetime.UTC`). Ruff's `DTZ`
  rules are on — naive `datetime.now()` fails lint.
- **Ruff config quirks:** `force-single-line = true` for imports (one `from x import y` per line),
  `T20` bans `print`, `TRY`/`EM` are on but literal messages are allowed (`EM101/EM102/TRY003`
  ignored). Run `ruff format` + `ruff check` before each commit.
- **Dashboard baseline (ADR-0020):** every user-facing string goes through `react-i18next` in **both**
  `src/locales/en/common.json` and `src/locales/ar/common.json`; every component test includes a
  `jest-axe` assertion; layout must be RTL-safe (logical properties: `start-*`/`end-*`, `ms-*`/`me-*`
  — never `left`/`right`).
- **Dashboard styling comes from design tokens** (semantic Tailwind utilities: `bg-card`,
  `text-muted-foreground`, `border-border`). No hardcoded hex, no `color-mix`.
- **Git-flow (ADR-0014):** work on `feat/billing-subscriptions` in each submodule → PR to that
  submodule's `main`; the meta repo carries docs + submodule pointer bumps via
  `feat/billing-spec` → PR to `develop`. Never commit to a trunk directly, never `--no-verify`.
  Pre-commit needs `PIP_CONFIG_FILE=/dev/null` on this machine (dead pip proxy).
- **Commands** (run from the submodule root): backend `pytest`, `ruff check .`, `ruff format .`,
  `mypy kaleem config`, `lint-imports`. Dashboard `pnpm test`, `pnpm exec tsc --noEmit`,
  `pnpm exec biome check src`.

## File Structure

**Backend (`backend/` submodule)**

| File | Responsibility |
| --- | --- |
| `kaleem/billing/__init__.py`, `apps.py` | Django app registration (`BillingConfig`, name `kaleem.billing`) |
| `kaleem/billing/models.py` | `SubscriptionPlan`, `BillingCustomer`, `Subscription`, `StripeEventLog` — data only |
| `kaleem/billing/migrations/0001_initial.py` | Generated migration |
| `kaleem/billing/admin.py` | Admin CRUD for plans + read-mostly views of the rest |
| `kaleem/billing/providers/__init__.py` | `PaymentProvider` Protocol, `WebhookEvent`/`CheckoutRequest` dataclasses, `get_provider()` |
| `kaleem/billing/providers/stripe_provider.py` | The only file that imports `stripe`; parses Stripe shapes into `WebhookEvent` |
| `kaleem/billing/services.py` | Public API: plans, checkout, cancel, webhook handling, `Capability` + `is_entitled_to` |
| `kaleem/billing/api/serializers.py` | Request/response serializers |
| `kaleem/billing/api/views.py` | Thin DRF views incl. the signature-authenticated webhook |
| `kaleem/billing/api/urls.py` | `app_name = "billing"` + routes |
| `kaleem/billing/tests/fakes.py` | `FakePaymentProvider` used by service/API tests |
| `kaleem/billing/tests/test_*.py` | models / providers / services / entitlement / webhook / api |
| `kaleem/identity/services.py` | + `get_parent_user_ids(student_user_id)` |
| `config/settings/base.py`, `production.py` | app registration + Stripe settings |
| `config/api_router.py` | mount `billing/` |
| `pyproject.toml` | import-linter contract for `billing` + `billing` added to identity/scheduling forbidden lists |
| `requirements/base.txt` | `stripe>=11.0` |

**Dashboard (`dashboard/` submodule)**

| File | Responsibility |
| --- | --- |
| `src/features/billing/schemas.ts` | Zod schemas + TS types for plan / subscription |
| `src/features/billing/api.ts` | `billingApi` — listPlans, createCheckout, getMySubscription, cancelSubscription |
| `src/features/billing/queries.ts` | TanStack Query hooks + query keys (incl. the polling option) |
| `src/features/billing/components/PlanList.tsx` | Plan cards + Subscribe → redirect to Stripe |
| `src/features/billing/components/SubscriptionCard.tsx` | Current status, renewal date, history |
| `src/features/billing/components/CancelSubscriptionDialog.tsx` | Confirm dialog → cancel mutation |
| `src/features/billing/components/CheckoutReturn.tsx` | "Finishing up…" poller + cancelled notice |
| `src/features/billing/index.ts` | Barrel export |
| `src/routes/_authed/billing.tsx` | Real page (replaces the `ModulePlaceholder`) |
| `src/features/shell/nav.ts` | `/billing` visible to parents **and** students |
| `src/routes/_authed/index.tsx` | Drop `/billing` from the `SOON` set + real description key |
| `src/locales/{en,ar}/common.json` | `billing.*` copy |

**Meta repo**

| File | Responsibility |
| --- | --- |
| `docs/adr/0025-stripe-webhook-csrf-exemption.md` | Why the webhook is CSRF-exempt |
| `docs/architecture/billing.md` | Module doc + ER diagram + entitlement rule |
| `docs/runbook/stripe-billing.md` | Stripe test-mode setup + the manual staging test |
| `ISSUES.md`, `STATE.md` | e2e limitation; state update |

---

## Task 1: Billing module skeleton, models, and boundary enforcement

**Files:**
- Create: `backend/kaleem/billing/__init__.py`, `backend/kaleem/billing/apps.py`,
  `backend/kaleem/billing/models.py`, `backend/kaleem/billing/admin.py`,
  `backend/kaleem/billing/tests/__init__.py`, `backend/kaleem/billing/tests/test_models.py`
- Modify: `backend/config/settings/base.py` (LOCAL_APPS), `backend/pyproject.toml` (import-linter),
  `backend/requirements/base.txt`
- Generated: `backend/kaleem/billing/migrations/0001_initial.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `kaleem.billing.models.SubscriptionPlan` (fields `plan_type`, `sessions_per_cycle`,
  `stripe_price_id`, `display_amount`, `currency`, `is_active`, `created_at`, `updated_at`;
  class constants `PlanType.INDIVIDUAL = "individual"`, `PlanType.FAMILY = "family"`),
  `BillingCustomer(user, stripe_customer_id, created_at)`,
  `Subscription(user, plan, stripe_subscription_id, status, current_period_end,
  cancel_at_period_end, created_at, updated_at)` with `Status` constants
  `ACTIVE/PAST_DUE/CANCELED/INCOMPLETE/INCOMPLETE_EXPIRED/UNPAID`,
  `StripeEventLog(stripe_event_id, event_type, received_at, processed_at)`.

- [ ] **Step 1: Write the failing model tests**

Create `backend/kaleem/billing/tests/__init__.py` (empty) and
`backend/kaleem/billing/tests/test_models.py`:

```python
import datetime as dt

import pytest
from django.db import IntegrityError
from django.utils import timezone

from kaleem.billing.models import BillingCustomer
from kaleem.billing.models import StripeEventLog
from kaleem.billing.models import Subscription
from kaleem.billing.models import SubscriptionPlan
from kaleem.identity.models import User


@pytest.fixture
def plan(db):
    return SubscriptionPlan.objects.create(
        plan_type=SubscriptionPlan.PlanType.FAMILY,
        sessions_per_cycle=4,
        stripe_price_id="price_fam",
        display_amount=5000,
        currency="usd",
    )


@pytest.fixture
def user(db):
    return User.objects.create_user(email="payer@example.com", password="pw12345!")


def test_plan_defaults_to_active_and_stringifies(plan):
    assert plan.is_active is True
    assert str(plan) == "family (4/cycle) 5000 usd"


def test_plan_stripe_price_id_is_unique(plan):
    with pytest.raises(IntegrityError):
        SubscriptionPlan.objects.create(
            plan_type=SubscriptionPlan.PlanType.INDIVIDUAL,
            sessions_per_cycle=4,
            stripe_price_id="price_fam",
            display_amount=2000,
            currency="usd",
        )


def test_billing_customer_is_one_per_user(user):
    BillingCustomer.objects.create(user=user, stripe_customer_id="cus_1")
    with pytest.raises(IntegrityError):
        BillingCustomer.objects.create(user=user, stripe_customer_id="cus_2")


def test_billing_customer_stringifies(user):
    customer = BillingCustomer.objects.create(user=user, stripe_customer_id="cus_1")
    assert str(customer) == "payer@example.com → cus_1"


def test_subscription_defaults_and_str(user, plan):
    end = timezone.now() + dt.timedelta(days=30)
    sub = Subscription.objects.create(
        user=user,
        plan=plan,
        stripe_subscription_id="sub_1",
        status=Subscription.Status.ACTIVE,
        current_period_end=end,
    )
    assert sub.cancel_at_period_end is False
    assert str(sub) == "payer@example.com family active"


def test_subscription_stripe_id_is_unique(user, plan):
    Subscription.objects.create(
        user=user, plan=plan, stripe_subscription_id="sub_1",
        status=Subscription.Status.ACTIVE,
    )
    with pytest.raises(IntegrityError):
        Subscription.objects.create(
            user=user, plan=plan, stripe_subscription_id="sub_1",
            status=Subscription.Status.ACTIVE,
        )


def test_event_log_is_unique_per_event_id(db):
    StripeEventLog.objects.create(stripe_event_id="evt_1", event_type="invoice.paid")
    with pytest.raises(IntegrityError):
        StripeEventLog.objects.create(stripe_event_id="evt_1", event_type="invoice.paid")


def test_event_log_stringifies(db):
    log = StripeEventLog.objects.create(stripe_event_id="evt_1", event_type="invoice.paid")
    assert str(log) == "evt_1 invoice.paid"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && pytest kaleem/billing -v`
Expected: collection error — `ModuleNotFoundError: No module named 'kaleem.billing'`.

- [ ] **Step 3: Create the app package**

`backend/kaleem/billing/__init__.py` — empty file.

`backend/kaleem/billing/apps.py`:

```python
from django.apps import AppConfig


class BillingConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "kaleem.billing"
```

`backend/kaleem/billing/models.py`:

```python
from django.conf import settings
from django.db import models


class SubscriptionPlan(models.Model):
    """A purchasable monthly plan. Stripe's Price is the charge source of truth;
    `display_amount`/`currency` are what we render on the pricing page."""

    class PlanType(models.TextChoices):
        INDIVIDUAL = "individual", "Individual"
        FAMILY = "family", "Family"

    plan_type = models.CharField(max_length=16, choices=PlanType.choices)
    sessions_per_cycle = models.PositiveSmallIntegerField()
    stripe_price_id = models.CharField(max_length=64, unique=True)
    display_amount = models.PositiveIntegerField()  # minor units (e.g. cents)
    currency = models.CharField(max_length=3)  # lowercase ISO-4217, Stripe convention
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return (
            f"{self.plan_type} ({self.sessions_per_cycle}/cycle) "
            f"{self.display_amount} {self.currency}"
        )


class BillingCustomer(models.Model):
    """One Stripe customer per user, created lazily on first checkout."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="billing_customer",
    )
    stripe_customer_id = models.CharField(max_length=64, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user.email} → {self.stripe_customer_id}"


class Subscription(models.Model):
    """A subscription over time. A user may accumulate rows (resubscribe after a
    lapse); at most one is *current* — enforced in services, not by the schema."""

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        PAST_DUE = "past_due", "Past due"
        CANCELED = "canceled", "Canceled"
        INCOMPLETE = "incomplete", "Incomplete"
        INCOMPLETE_EXPIRED = "incomplete_expired", "Incomplete expired"
        UNPAID = "unpaid", "Unpaid"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="subscriptions",
    )
    plan = models.ForeignKey(
        SubscriptionPlan, on_delete=models.PROTECT, related_name="subscriptions"
    )
    stripe_subscription_id = models.CharField(max_length=64, unique=True)
    status = models.CharField(max_length=32, choices=Status.choices)
    current_period_end = models.DateTimeField(null=True, blank=True)
    cancel_at_period_end = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [models.Index(fields=["user", "status"])]

    def __str__(self):
        return f"{self.user.email} {self.plan.plan_type} {self.status}"


class StripeEventLog(models.Model):
    """Idempotency ledger: a webhook whose event id is already processed is a no-op."""

    stripe_event_id = models.CharField(max_length=64, unique=True)
    event_type = models.CharField(max_length=64)
    received_at = models.DateTimeField(auto_now_add=True)
    processed_at = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"{self.stripe_event_id} {self.event_type}"
```

`backend/kaleem/billing/admin.py`:

```python
from django.contrib import admin

from kaleem.billing.models import BillingCustomer
from kaleem.billing.models import StripeEventLog
from kaleem.billing.models import Subscription
from kaleem.billing.models import SubscriptionPlan


@admin.register(SubscriptionPlan)
class SubscriptionPlanAdmin(admin.ModelAdmin):
    list_display = ("plan_type", "sessions_per_cycle", "display_amount", "currency", "is_active")
    list_filter = ("plan_type", "is_active")


@admin.register(Subscription)
class SubscriptionAdmin(admin.ModelAdmin):
    list_display = ("user", "plan", "status", "current_period_end", "cancel_at_period_end")
    list_filter = ("status",)
    search_fields = ("stripe_subscription_id",)


admin.site.register(BillingCustomer)
admin.site.register(StripeEventLog)
```

- [ ] **Step 4: Register the app and add the dependency**

In `backend/config/settings/base.py`, add to `LOCAL_APPS` (after `kaleem.identity`):

```python
LOCAL_APPS = [
    "kaleem.platform",
    "kaleem.identity",
    "kaleem.billing",
    "kaleem.scheduling",
]
```

In `backend/requirements/base.txt`, append:

```
stripe>=11.0
```

Install it: `cd backend && pip install -r requirements/local.txt` (inside the container:
`docker compose -f docker-compose.local.yml exec backend pip install stripe`). Note in the commit
message that the backend Docker image needs a rebuild for the new dependency.

- [ ] **Step 5: Add the import-linter contracts**

In `backend/pyproject.toml`, append a new contract and update the two existing ones so `billing`
is a first-class sibling:

```toml
[[tool.importlinter.contracts]]
name = "billing imports no business modules except identity"
type = "forbidden"
source_modules = ["kaleem.billing"]
# billing may import kaleem.platform and call kaleem.identity.services
# (entitlement chaining needs the parent/child links). All other siblings are forbidden.
forbidden_modules = [
    "kaleem.scheduling",
    "kaleem.assessment",
    "kaleem.curriculum",
    "kaleem.content",
    "kaleem.messaging",
    "kaleem.notifications",
    "kaleem.engagement",
    "kaleem.analytics",
]
```

(`kaleem.billing` is already listed in the identity and scheduling contracts' `forbidden_modules` —
leave those as they are.)

- [ ] **Step 6: Generate the migration**

Run: `cd backend && python manage.py makemigrations billing`
Expected: `kaleem/billing/migrations/0001_initial.py` created with the four models.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd backend && pytest kaleem/billing -v`
Expected: 8 passed.

- [ ] **Step 8: Run the lint + boundary gates**

Run: `cd backend && ruff format . && ruff check . && mypy kaleem config && lint-imports`
Expected: all clean; import-linter reports the new contract KEPT.

- [ ] **Step 9: Commit**

```bash
cd backend
git checkout -b feat/billing-subscriptions
git add kaleem/billing config/settings/base.py pyproject.toml requirements/base.txt
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): module skeleton, models, and boundary contract"
```

---

## Task 2: `identity.services.get_parent_user_ids`

**Files:**
- Modify: `backend/kaleem/identity/services.py` (add after `is_parent_of`, ~line 108)
- Test: `backend/kaleem/identity/tests/test_services.py` (append)

**Interfaces:**
- Consumes: `kaleem.identity.models.ParentStudent` (parent link table).
- Produces: `identity_services.get_parent_user_ids(student_user_id: int) -> list[int]` — the user ids
  of every parent linked to this student, ascending, `[]` when there are none. Task 6 (entitlement
  chaining) and Task 5 (Individual-plan eligibility) both depend on it.

- [ ] **Step 1: Write the failing test**

Append to `backend/kaleem/identity/tests/test_services.py` (match the file's existing fixture style —
read the top of the file first and reuse its helpers if equivalent ones exist):

```python
def test_get_parent_user_ids_returns_linked_parents(db):
    parent_user = User.objects.create_user(email="p1@example.com", password="pw12345!")
    parent = ParentProfile.objects.create(user=parent_user)
    child_user = User.objects.create_user(email="c1@example.com", password="pw12345!")
    child = StudentProfile.objects.create(user=child_user)
    ParentStudent.objects.create(parent=parent, student=child)

    assert services.get_parent_user_ids(child_user.id) == [parent_user.id]


def test_get_parent_user_ids_is_empty_for_an_unlinked_student(db):
    solo = User.objects.create_user(email="solo@example.com", password="pw12345!")
    StudentProfile.objects.create(user=solo)

    assert services.get_parent_user_ids(solo.id) == []
```

Add any missing imports at the top of the test file (`ParentProfile`, `ParentStudent`,
`StudentProfile`, `User` from `kaleem.identity.models`; `from kaleem.identity import services`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && pytest kaleem/identity/tests/test_services.py -k parent_user_ids -v`
Expected: FAIL — `AttributeError: module 'kaleem.identity.services' has no attribute 'get_parent_user_ids'`.

- [ ] **Step 3: Implement**

In `backend/kaleem/identity/services.py`, directly below `is_parent_of`:

```python
def get_parent_user_ids(student_user_id: int) -> list[int]:
    """User ids of every parent linked to this student (for billing entitlement
    chaining). Empty when the student has no parent."""
    return list(
        ParentStudent.objects.filter(student__user_id=student_user_id)
        .order_by("parent__user_id")
        .values_list("parent__user_id", flat=True)
    )
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && pytest kaleem/identity/tests/test_services.py -k parent_user_ids -v`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
cd backend
git add kaleem/identity/services.py kaleem/identity/tests/test_services.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(identity): add get_parent_user_ids for billing entitlement chaining"
```

---

## Task 3: `PaymentProvider` protocol, dataclasses, and `get_provider()`

**Files:**
- Create: `backend/kaleem/billing/providers/__init__.py`,
  `backend/kaleem/billing/tests/fakes.py`,
  `backend/kaleem/billing/tests/test_providers.py`
- Modify: `backend/config/settings/base.py` (Stripe + provider settings),
  `backend/config/settings/production.py` (fail-loud Stripe keys)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `@dataclass(frozen=True) CheckoutRequest(customer_id: str, price_id: str, success_url: str,
    cancel_url: str, user_id: int, plan_id: int)`
  - `@dataclass(frozen=True) WebhookEvent(event_id: str, event_type: str,
    stripe_subscription_id: str | None, stripe_customer_id: str | None, user_id: int | None,
    plan_id: int | None, status: str | None, current_period_end: datetime | None,
    cancel_at_period_end: bool | None)`
  - `class PaymentProvider(Protocol)` with `ensure_customer(user) -> str`,
    `create_checkout_session(request: CheckoutRequest) -> str`,
    `cancel_at_period_end(subscription_id: str) -> None`,
    `verify_and_parse_webhook(payload: bytes, signature: str) -> WebhookEvent`
  - `get_provider() -> PaymentProvider` — instantiates `settings.BILLING_PAYMENT_PROVIDER`
    (dotted path) via `django.utils.module_loading.import_string`.
  - `kaleem.billing.tests.fakes.FakePaymentProvider` — records calls, returns canned values;
    Tasks 5–7 select it with `settings.BILLING_PAYMENT_PROVIDER = "kaleem.billing.tests.fakes.FakePaymentProvider"`.

- [ ] **Step 1: Write the failing test**

`backend/kaleem/billing/tests/test_providers.py`:

```python
from kaleem.billing.providers import get_provider
from kaleem.billing.tests.fakes import FakePaymentProvider


def test_get_provider_instantiates_the_configured_dotted_path(settings):
    settings.BILLING_PAYMENT_PROVIDER = "kaleem.billing.tests.fakes.FakePaymentProvider"
    assert isinstance(get_provider(), FakePaymentProvider)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && pytest kaleem/billing/tests/test_providers.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'kaleem.billing.providers'`.

- [ ] **Step 3: Implement the provider package**

`backend/kaleem/billing/providers/__init__.py`:

```python
from __future__ import annotations

import datetime as dt
from dataclasses import dataclass
from typing import Protocol

from django.conf import settings
from django.utils.module_loading import import_string


@dataclass(frozen=True)
class CheckoutRequest:
    customer_id: str
    price_id: str
    success_url: str
    cancel_url: str
    user_id: int
    plan_id: int


@dataclass(frozen=True)
class WebhookEvent:
    """Provider-neutral view of a billing event. The provider owns all knowledge
    of the upstream payload shape; billing.services only ever sees this."""

    event_id: str
    event_type: str
    stripe_subscription_id: str | None = None
    stripe_customer_id: str | None = None
    user_id: int | None = None
    plan_id: int | None = None
    status: str | None = None
    current_period_end: dt.datetime | None = None
    cancel_at_period_end: bool | None = None


class PaymentProvider(Protocol):
    def ensure_customer(self, user) -> str: ...

    def create_checkout_session(self, request: CheckoutRequest) -> str: ...

    def cancel_at_period_end(self, subscription_id: str) -> None: ...

    def verify_and_parse_webhook(self, payload: bytes, signature: str) -> WebhookEvent: ...


def get_provider() -> PaymentProvider:
    """Instantiate the configured payment provider (OQ-06: local methods later)."""
    provider_class = import_string(settings.BILLING_PAYMENT_PROVIDER)
    return provider_class()
```

- [ ] **Step 4: Write the fake used by later tasks**

`backend/kaleem/billing/tests/fakes.py`:

```python
"""Test double for the payment provider. Service and API tests run against this,
so no test touches the network or the `stripe` SDK."""

from __future__ import annotations

from kaleem.billing.providers import CheckoutRequest
from kaleem.billing.providers import WebhookEvent


class FakePaymentProvider:
    # Class-level so tests can set expectations before get_provider() builds an
    # instance, and assert on calls afterwards.
    customer_id = "cus_fake"
    checkout_url = "https://checkout.stripe.test/session"
    next_event: WebhookEvent | None = None
    raise_on_webhook: Exception | None = None
    canceled: list[str] = []
    checkout_requests: list[CheckoutRequest] = []

    @classmethod
    def reset(cls) -> None:
        cls.customer_id = "cus_fake"
        cls.checkout_url = "https://checkout.stripe.test/session"
        cls.next_event = None
        cls.raise_on_webhook = None
        cls.canceled = []
        cls.checkout_requests = []

    def ensure_customer(self, user) -> str:
        return self.customer_id

    def create_checkout_session(self, request: CheckoutRequest) -> str:
        type(self).checkout_requests.append(request)
        return self.checkout_url

    def cancel_at_period_end(self, subscription_id: str) -> None:
        type(self).canceled.append(subscription_id)

    def verify_and_parse_webhook(self, payload: bytes, signature: str) -> WebhookEvent:
        if self.raise_on_webhook is not None:
            raise self.raise_on_webhook
        assert self.next_event is not None
        return self.next_event
```

- [ ] **Step 5: Add the settings**

In `backend/config/settings/base.py`, below the `FRONTEND_URL` block:

```python
# BILLING
# Swappable payment provider (OQ-06 leaves room for local payment methods).
BILLING_PAYMENT_PROVIDER = env(
    "DJANGO_BILLING_PAYMENT_PROVIDER",
    default="kaleem.billing.providers.stripe_provider.StripeProvider",
)
STRIPE_SECRET_KEY = env("DJANGO_STRIPE_SECRET_KEY", default="")
STRIPE_WEBHOOK_SECRET = env("DJANGO_STRIPE_WEBHOOK_SECRET", default="")
```

In `backend/config/settings/production.py`, beside the existing `FRONTEND_URL` line (fail loud —
no silent empty keys in production):

```python
STRIPE_SECRET_KEY = env("DJANGO_STRIPE_SECRET_KEY")
STRIPE_WEBHOOK_SECRET = env("DJANGO_STRIPE_WEBHOOK_SECRET")
```

Also add both keys (empty/test values) to `backend/.env.example`.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd backend && pytest kaleem/billing/tests/test_providers.py -v`
Expected: 1 passed.

- [ ] **Step 7: Commit**

```bash
cd backend
git add kaleem/billing config/settings .env.example
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): payment provider protocol + configurable selection"
```

---

## Task 4: `StripeProvider`

**Files:**
- Create: `backend/kaleem/billing/providers/stripe_provider.py`,
  `backend/kaleem/billing/tests/test_stripe_provider.py`

**Interfaces:**
- Consumes: `CheckoutRequest`, `WebhookEvent` from Task 3; `settings.STRIPE_SECRET_KEY`,
  `settings.STRIPE_WEBHOOK_SECRET`.
- Produces: `StripeProvider` implementing `PaymentProvider`. It is **the only module that imports
  `stripe`**. Invalid signatures raise `kaleem.platform.exceptions.ValidationError`. Checkout
  sessions carry `metadata={"user_id": ..., "plan_id": ...}` on both the session and the created
  subscription, which is how webhooks resolve back to our rows.

- [ ] **Step 1: Write the failing tests**

`backend/kaleem/billing/tests/test_stripe_provider.py`:

```python
import datetime as dt

import pytest
import stripe

from kaleem.billing.providers import CheckoutRequest
from kaleem.billing.providers.stripe_provider import StripeProvider
from kaleem.identity.models import User
from kaleem.platform.exceptions import ValidationError


@pytest.fixture
def provider(settings):
    settings.STRIPE_SECRET_KEY = "sk_test_x"
    settings.STRIPE_WEBHOOK_SECRET = "whsec_x"
    return StripeProvider()


@pytest.fixture
def user(db):
    return User.objects.create_user(email="payer@example.com", password="pw12345!")


def test_ensure_customer_creates_a_stripe_customer(provider, user, monkeypatch):
    calls = {}

    def fake_create(**kwargs):
        calls.update(kwargs)
        return {"id": "cus_new"}

    monkeypatch.setattr(stripe.Customer, "create", fake_create)
    assert provider.ensure_customer(user) == "cus_new"
    assert calls["email"] == "payer@example.com"
    assert calls["metadata"] == {"user_id": str(user.id)}


def test_create_checkout_session_returns_the_hosted_url(provider, monkeypatch):
    captured = {}

    def fake_create(**kwargs):
        captured.update(kwargs)
        return {"url": "https://checkout.stripe.com/c/pay/abc"}

    monkeypatch.setattr(stripe.checkout.Session, "create", fake_create)
    url = provider.create_checkout_session(
        CheckoutRequest(
            customer_id="cus_1",
            price_id="price_1",
            success_url="https://app/billing?checkout=success",
            cancel_url="https://app/billing?checkout=cancelled",
            user_id=7,
            plan_id=3,
        )
    )
    assert url == "https://checkout.stripe.com/c/pay/abc"
    assert captured["mode"] == "subscription"
    assert captured["line_items"] == [{"price": "price_1", "quantity": 1}]
    assert captured["metadata"] == {"user_id": "7", "plan_id": "3"}
    assert captured["subscription_data"]["metadata"] == {"user_id": "7", "plan_id": "3"}


def test_cancel_at_period_end_modifies_the_subscription(provider, monkeypatch):
    captured = {}

    def fake_modify(subscription_id, **kwargs):
        captured["id"] = subscription_id
        captured.update(kwargs)
        return {"id": subscription_id}

    monkeypatch.setattr(stripe.Subscription, "modify", fake_modify)
    provider.cancel_at_period_end("sub_1")
    assert captured == {"id": "sub_1", "cancel_at_period_end": True}


def _construct(monkeypatch, event):
    monkeypatch.setattr(
        stripe.Webhook, "construct_event", lambda payload, sig_header, secret: event
    )


def test_parses_checkout_session_completed(provider, monkeypatch):
    _construct(
        monkeypatch,
        {
            "id": "evt_1",
            "type": "checkout.session.completed",
            "data": {
                "object": {
                    "subscription": "sub_1",
                    "customer": "cus_1",
                    "metadata": {"user_id": "7", "plan_id": "3"},
                }
            },
        },
    )
    event = provider.verify_and_parse_webhook(b"{}", "sig")
    assert event.event_id == "evt_1"
    assert event.event_type == "checkout.session.completed"
    assert event.stripe_subscription_id == "sub_1"
    assert event.stripe_customer_id == "cus_1"
    assert event.user_id == 7
    assert event.plan_id == 3
    assert event.status == "active"


def test_parses_subscription_updated_with_period_end(provider, monkeypatch):
    _construct(
        monkeypatch,
        {
            "id": "evt_2",
            "type": "customer.subscription.updated",
            "data": {
                "object": {
                    "id": "sub_1",
                    "customer": "cus_1",
                    "status": "past_due",
                    "current_period_end": 1893456000,
                    "cancel_at_period_end": True,
                    "metadata": {},
                }
            },
        },
    )
    event = provider.verify_and_parse_webhook(b"{}", "sig")
    assert event.stripe_subscription_id == "sub_1"
    assert event.status == "past_due"
    assert event.cancel_at_period_end is True
    assert event.current_period_end == dt.datetime(2030, 1, 1, tzinfo=dt.UTC)
    assert event.user_id is None
    assert event.plan_id is None


def test_parses_invoice_paid_using_the_invoice_subscription(provider, monkeypatch):
    _construct(
        monkeypatch,
        {
            "id": "evt_3",
            "type": "invoice.paid",
            "data": {
                "object": {
                    "subscription": "sub_1",
                    "customer": "cus_1",
                    "lines": {"data": [{"period": {"end": 1893456000}}]},
                }
            },
        },
    )
    event = provider.verify_and_parse_webhook(b"{}", "sig")
    assert event.event_type == "invoice.paid"
    assert event.stripe_subscription_id == "sub_1"
    assert event.current_period_end == dt.datetime(2030, 1, 1, tzinfo=dt.UTC)


def test_parses_invoice_payment_failed_without_a_period(provider, monkeypatch):
    _construct(
        monkeypatch,
        {
            "id": "evt_4",
            "type": "invoice.payment_failed",
            "data": {"object": {"subscription": "sub_1", "customer": "cus_1", "lines": {"data": []}}},
        },
    )
    event = provider.verify_and_parse_webhook(b"{}", "sig")
    assert event.current_period_end is None


def test_parses_an_unknown_event_type_without_subscription_fields(provider, monkeypatch):
    _construct(monkeypatch, {"id": "evt_5", "type": "customer.created", "data": {"object": {}}})
    event = provider.verify_and_parse_webhook(b"{}", "sig")
    assert event.event_type == "customer.created"
    assert event.stripe_subscription_id is None


def test_invalid_signature_raises_a_typed_validation_error(provider, monkeypatch):
    def boom(payload, sig_header, secret):
        raise stripe.error.SignatureVerificationError("bad sig", sig_header)

    monkeypatch.setattr(stripe.Webhook, "construct_event", boom)
    with pytest.raises(ValidationError):
        provider.verify_and_parse_webhook(b"{}", "sig")


def test_malformed_payload_raises_a_typed_validation_error(provider, monkeypatch):
    def boom(payload, sig_header, secret):
        raise ValueError("not json")

    monkeypatch.setattr(stripe.Webhook, "construct_event", boom)
    with pytest.raises(ValidationError):
        provider.verify_and_parse_webhook(b"{}", "sig")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && pytest kaleem/billing/tests/test_stripe_provider.py -v`
Expected: collection error — `No module named 'kaleem.billing.providers.stripe_provider'`.

- [ ] **Step 3: Implement**

`backend/kaleem/billing/providers/stripe_provider.py`:

```python
"""The only module in `billing` that knows Stripe exists."""

from __future__ import annotations

import datetime as dt

import stripe
from django.conf import settings

from kaleem.billing.providers import CheckoutRequest
from kaleem.billing.providers import WebhookEvent
from kaleem.platform.exceptions import ValidationError

# Event types whose payload object *is* the subscription.
_SUBSCRIPTION_EVENTS = {
    "customer.subscription.updated",
    "customer.subscription.deleted",
}
# Event types whose payload object is an invoice referencing a subscription.
_INVOICE_EVENTS = {"invoice.paid", "invoice.payment_failed"}


def _to_datetime(epoch: int | None) -> dt.datetime | None:
    if epoch is None:
        return None
    return dt.datetime.fromtimestamp(epoch, tz=dt.UTC)


def _to_int(value: str | None) -> int | None:
    return int(value) if value else None


class StripeProvider:
    def __init__(self) -> None:
        self._client_key = settings.STRIPE_SECRET_KEY
        self._webhook_secret = settings.STRIPE_WEBHOOK_SECRET
        stripe.api_key = self._client_key

    def ensure_customer(self, user) -> str:
        customer = stripe.Customer.create(
            email=user.email, metadata={"user_id": str(user.id)}
        )
        return customer["id"]

    def create_checkout_session(self, request: CheckoutRequest) -> str:
        metadata = {"user_id": str(request.user_id), "plan_id": str(request.plan_id)}
        session = stripe.checkout.Session.create(
            mode="subscription",
            customer=request.customer_id,
            line_items=[{"price": request.price_id, "quantity": 1}],
            success_url=request.success_url,
            cancel_url=request.cancel_url,
            metadata=metadata,
            # Mirrored onto the subscription so later subscription events can be
            # resolved back to our user/plan rows.
            subscription_data={"metadata": metadata},
        )
        return session["url"]

    def cancel_at_period_end(self, subscription_id: str) -> None:
        stripe.Subscription.modify(subscription_id, cancel_at_period_end=True)

    def verify_and_parse_webhook(self, payload: bytes, signature: str) -> WebhookEvent:
        try:
            event = stripe.Webhook.construct_event(
                payload, signature, self._webhook_secret
            )
        except (stripe.error.SignatureVerificationError, ValueError) as exc:
            raise ValidationError("Invalid webhook signature.") from exc

        obj = event["data"]["object"]
        metadata = obj.get("metadata") or {}
        event_type = event["type"]

        if event_type == "checkout.session.completed":
            return WebhookEvent(
                event_id=event["id"],
                event_type=event_type,
                stripe_subscription_id=obj.get("subscription"),
                stripe_customer_id=obj.get("customer"),
                user_id=_to_int(metadata.get("user_id")),
                plan_id=_to_int(metadata.get("plan_id")),
                status="active",
            )
        if event_type in _SUBSCRIPTION_EVENTS:
            return WebhookEvent(
                event_id=event["id"],
                event_type=event_type,
                stripe_subscription_id=obj.get("id"),
                stripe_customer_id=obj.get("customer"),
                user_id=_to_int(metadata.get("user_id")),
                plan_id=_to_int(metadata.get("plan_id")),
                status=obj.get("status"),
                current_period_end=_to_datetime(obj.get("current_period_end")),
                cancel_at_period_end=obj.get("cancel_at_period_end"),
            )
        if event_type in _INVOICE_EVENTS:
            lines = (obj.get("lines") or {}).get("data") or []
            period_end = lines[0]["period"]["end"] if lines else None
            return WebhookEvent(
                event_id=event["id"],
                event_type=event_type,
                stripe_subscription_id=obj.get("subscription"),
                stripe_customer_id=obj.get("customer"),
                user_id=_to_int(metadata.get("user_id")),
                plan_id=_to_int(metadata.get("plan_id")),
                current_period_end=_to_datetime(period_end),
            )
        return WebhookEvent(event_id=event["id"], event_type=event_type)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && pytest kaleem/billing/tests/test_stripe_provider.py -v --cov=kaleem.billing.providers --cov-report=term-missing --cov-branch`
Expected: 10 passed, `providers/stripe_provider.py` **100%** line + branch. If a branch is missed,
add the test that exercises it before moving on.

- [ ] **Step 5: Commit**

```bash
cd backend
git add kaleem/billing
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): StripeProvider with normalized webhook parsing"
```

---

## Task 5: Checkout service (plans, eligibility, customer, checkout session)

**Files:**
- Create: `backend/kaleem/billing/services.py`,
  `backend/kaleem/billing/tests/conftest.py`,
  `backend/kaleem/billing/tests/test_services_checkout.py`

**Interfaces:**
- Consumes: models (Task 1), `identity_services.get_parent_profile/get_student_profile/
  get_parent_user_ids` (Task 2), `get_provider()`/`CheckoutRequest` (Task 3),
  `settings.FRONTEND_URL`.
- Produces:
  - `list_active_plans() -> QuerySet[SubscriptionPlan]`
  - `get_current_subscription(user) -> Subscription | None` — the newest non-terminal row
    (status in `active`/`past_due`, or a paid-through cancelled one)
  - `create_checkout(user, plan_id: int) -> str` — returns the hosted checkout URL; raises
    `NotFoundError` (unknown/inactive plan), `ValidationError` (already subscribed),
    `PermissionDeniedError` (role/plan mismatch)
  - `_ensure_customer(user) -> BillingCustomer` (module-private, reused by nothing else)

- [ ] **Step 1: Write the shared fixtures**

`backend/kaleem/billing/tests/conftest.py`:

```python
import pytest

from kaleem.billing.models import SubscriptionPlan
from kaleem.billing.tests.fakes import FakePaymentProvider
from kaleem.identity.models import ParentProfile
from kaleem.identity.models import ParentStudent
from kaleem.identity.models import StudentProfile
from kaleem.identity.models import User


@pytest.fixture(autouse=True)
def fake_provider(settings):
    """All billing service/API tests run against the fake provider."""
    settings.BILLING_PAYMENT_PROVIDER = "kaleem.billing.tests.fakes.FakePaymentProvider"
    settings.FRONTEND_URL = "https://app.test"
    FakePaymentProvider.reset()
    return FakePaymentProvider


@pytest.fixture
def family_plan(db):
    return SubscriptionPlan.objects.create(
        plan_type=SubscriptionPlan.PlanType.FAMILY,
        sessions_per_cycle=4,
        stripe_price_id="price_family",
        display_amount=5000,
        currency="usd",
    )


@pytest.fixture
def individual_plan(db):
    return SubscriptionPlan.objects.create(
        plan_type=SubscriptionPlan.PlanType.INDIVIDUAL,
        sessions_per_cycle=4,
        stripe_price_id="price_individual",
        display_amount=2000,
        currency="usd",
    )


@pytest.fixture
def parent(db):
    user = User.objects.create_user(email="parent@example.com", password="pw12345!")
    ParentProfile.objects.create(user=user)
    return user


@pytest.fixture
def adult_student(db):
    user = User.objects.create_user(email="adult@example.com", password="pw12345!")
    StudentProfile.objects.create(user=user)
    return user


@pytest.fixture
def child(db, parent):
    user = User.objects.create_user(email="child@example.com", password="pw12345!")
    profile = StudentProfile.objects.create(user=user)
    ParentStudent.objects.create(
        parent=ParentProfile.objects.get(user=parent), student=profile
    )
    return user


@pytest.fixture
def teacher(db):
    return User.objects.create_user(email="teacher@example.com", password="pw12345!")
```

- [ ] **Step 2: Write the failing checkout tests**

`backend/kaleem/billing/tests/test_services_checkout.py`:

```python
import pytest

from kaleem.billing import services
from kaleem.billing.models import BillingCustomer
from kaleem.billing.models import Subscription
from kaleem.billing.models import SubscriptionPlan
from kaleem.platform.exceptions import NotFoundError
from kaleem.platform.exceptions import PermissionDeniedError
from kaleem.platform.exceptions import ValidationError


def test_list_active_plans_excludes_inactive(db, family_plan, individual_plan):
    individual_plan.is_active = False
    individual_plan.save()
    assert list(services.list_active_plans()) == [family_plan]


def test_parent_can_check_out_a_family_plan(parent, family_plan, fake_provider):
    url = services.create_checkout(parent, family_plan.id)

    assert url == fake_provider.checkout_url
    request = fake_provider.checkout_requests[0]
    assert request.price_id == "price_family"
    assert request.user_id == parent.id
    assert request.plan_id == family_plan.id
    assert request.success_url == "https://app.test/billing?checkout=success"
    assert request.cancel_url == "https://app.test/billing?checkout=cancelled"


def test_checkout_creates_the_billing_customer_once(parent, family_plan):
    services.create_checkout(parent, family_plan.id)
    services.create_checkout(parent, family_plan.id)
    assert BillingCustomer.objects.filter(user=parent).count() == 1


def test_adult_student_can_check_out_an_individual_plan(adult_student, individual_plan):
    assert services.create_checkout(adult_student, individual_plan.id)


def test_unknown_plan_raises_not_found(parent, db):
    with pytest.raises(NotFoundError):
        services.create_checkout(parent, 4242)


def test_inactive_plan_raises_not_found(parent, family_plan):
    family_plan.is_active = False
    family_plan.save()
    with pytest.raises(NotFoundError):
        services.create_checkout(parent, family_plan.id)


def test_non_parent_cannot_buy_family(adult_student, family_plan):
    with pytest.raises(PermissionDeniedError):
        services.create_checkout(adult_student, family_plan.id)


def test_non_student_cannot_buy_individual(teacher, individual_plan):
    with pytest.raises(PermissionDeniedError):
        services.create_checkout(teacher, individual_plan.id)


def test_child_cannot_self_subscribe(child, individual_plan):
    with pytest.raises(PermissionDeniedError):
        services.create_checkout(child, individual_plan.id)


def test_second_checkout_while_active_is_rejected(parent, family_plan):
    Subscription.objects.create(
        user=parent,
        plan=family_plan,
        stripe_subscription_id="sub_live",
        status=Subscription.Status.ACTIVE,
    )
    with pytest.raises(ValidationError):
        services.create_checkout(parent, family_plan.id)


def test_checkout_allowed_after_a_canceled_subscription(parent, family_plan):
    Subscription.objects.create(
        user=parent,
        plan=family_plan,
        stripe_subscription_id="sub_old",
        status=Subscription.Status.CANCELED,
    )
    assert services.create_checkout(parent, family_plan.id)


def test_get_current_subscription_is_none_without_one(parent):
    assert services.get_current_subscription(parent) is None


def test_get_current_subscription_returns_the_newest_live_row(parent, family_plan):
    Subscription.objects.create(
        user=parent, plan=family_plan, stripe_subscription_id="sub_old",
        status=Subscription.Status.CANCELED,
    )
    live = Subscription.objects.create(
        user=parent, plan=family_plan, stripe_subscription_id="sub_new",
        status=Subscription.Status.ACTIVE,
    )
    assert services.get_current_subscription(parent) == live


def test_plan_type_choices_cover_both_products(db):
    assert set(SubscriptionPlan.PlanType.values) == {"individual", "family"}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd backend && pytest kaleem/billing/tests/test_services_checkout.py -v`
Expected: collection error — `No module named 'kaleem.billing.services'`.

- [ ] **Step 4: Implement**

`backend/kaleem/billing/services.py`:

```python
from __future__ import annotations

from django.conf import settings
from django.db import transaction
from django.db.models import QuerySet

from kaleem.billing.models import BillingCustomer
from kaleem.billing.models import Subscription
from kaleem.billing.models import SubscriptionPlan
from kaleem.billing.providers import CheckoutRequest
from kaleem.billing.providers import get_provider
from kaleem.identity import services as identity_services
from kaleem.platform.exceptions import NotFoundError
from kaleem.platform.exceptions import PermissionDeniedError
from kaleem.platform.exceptions import ValidationError

# Statuses that mean "this row is the user's current subscription", i.e. it still
# has a claim on them (paying, or failing to pay). Terminal rows are history.
LIVE_STATUSES = (Subscription.Status.ACTIVE, Subscription.Status.PAST_DUE)


def list_active_plans() -> QuerySet[SubscriptionPlan]:
    return SubscriptionPlan.objects.filter(is_active=True).order_by("id")


def get_current_subscription(user) -> Subscription | None:
    return (
        Subscription.objects.filter(user=user, status__in=LIVE_STATUSES)
        .order_by("-created_at", "-id")
        .first()
    )


def _require_eligible_buyer(user, plan: SubscriptionPlan) -> None:
    if plan.plan_type == SubscriptionPlan.PlanType.FAMILY:
        if identity_services.get_parent_profile(user.id) is None:
            raise PermissionDeniedError("buy a family plan without a parent profile")
        return
    if identity_services.get_student_profile(user.id) is None:
        raise PermissionDeniedError(
            "buy an individual plan without a student profile"
        )
    if identity_services.get_parent_user_ids(user.id):
        # A child is covered by their parent's family plan and may not self-subscribe.
        raise PermissionDeniedError("buy an individual plan as a linked child")


def _ensure_customer(user) -> BillingCustomer:
    customer = BillingCustomer.objects.filter(user=user).first()
    if customer is not None:
        return customer
    customer_id = get_provider().ensure_customer(user)
    return BillingCustomer.objects.create(user=user, stripe_customer_id=customer_id)


def create_checkout(user, plan_id: int) -> str:
    plan = SubscriptionPlan.objects.filter(id=plan_id, is_active=True).first()
    if plan is None:
        raise NotFoundError("SubscriptionPlan", plan_id)
    _require_eligible_buyer(user, plan)
    if get_current_subscription(user) is not None:
        raise ValidationError("You already have an active subscription.")

    customer = _ensure_customer(user)
    return get_provider().create_checkout_session(
        CheckoutRequest(
            customer_id=customer.stripe_customer_id,
            price_id=plan.stripe_price_id,
            success_url=f"{settings.FRONTEND_URL}/billing?checkout=success",
            cancel_url=f"{settings.FRONTEND_URL}/billing?checkout=cancelled",
            user_id=user.id,
            plan_id=plan.id,
        )
    )
```

(`transaction` is imported for Task 6 — if your linter flags it as unused now, add the import in
Task 6 instead.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd backend && pytest kaleem/billing -v`
Expected: all green (models + providers + checkout).

- [ ] **Step 6: Commit**

```bash
cd backend
git add kaleem/billing
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): checkout service with role/plan eligibility"
```

---

## Task 6: Webhook handling + cancel

**Files:**
- Modify: `backend/kaleem/billing/services.py`
- Test: `backend/kaleem/billing/tests/test_services_webhook.py`

**Interfaces:**
- Consumes: everything from Task 5 plus `WebhookEvent` and `StripeEventLog`.
- Produces:
  - `handle_webhook(payload: bytes, signature: str) -> None` — verifies via the provider
    (raising `ValidationError` on a bad signature), is idempotent per `stripe_event_id`, and applies
    the five handled event types. Unknown types are logged and acked with no state change.
  - `cancel_subscription(user) -> Subscription` — flags `cancel_at_period_end` upstream and
    locally; raises `NotFoundError` when the user has no current subscription.

- [ ] **Step 1: Write the failing tests**

`backend/kaleem/billing/tests/test_services_webhook.py`:

```python
import datetime as dt

import pytest
from django.utils import timezone

from kaleem.billing import services
from kaleem.billing.models import StripeEventLog
from kaleem.billing.models import Subscription
from kaleem.billing.providers import WebhookEvent
from kaleem.platform.exceptions import NotFoundError
from kaleem.platform.exceptions import ValidationError

PERIOD_END = dt.datetime(2030, 1, 1, tzinfo=dt.UTC)


def _completed(user, plan, event_id="evt_1"):
    return WebhookEvent(
        event_id=event_id,
        event_type="checkout.session.completed",
        stripe_subscription_id="sub_1",
        stripe_customer_id="cus_1",
        user_id=user.id,
        plan_id=plan.id,
        status="active",
    )


def test_checkout_completed_creates_an_active_subscription(parent, family_plan, fake_provider):
    fake_provider.next_event = _completed(parent, family_plan)
    services.handle_webhook(b"{}", "sig")

    sub = Subscription.objects.get(stripe_subscription_id="sub_1")
    assert sub.user == parent
    assert sub.plan == family_plan
    assert sub.status == Subscription.Status.ACTIVE
    assert StripeEventLog.objects.get(stripe_event_id="evt_1").processed_at is not None


def test_replaying_the_same_event_is_a_no_op(parent, family_plan, fake_provider):
    fake_provider.next_event = _completed(parent, family_plan)
    services.handle_webhook(b"{}", "sig")
    services.handle_webhook(b"{}", "sig")

    assert Subscription.objects.count() == 1
    assert StripeEventLog.objects.count() == 1


def test_invalid_signature_propagates_and_changes_nothing(parent, family_plan, fake_provider):
    fake_provider.raise_on_webhook = ValidationError("Invalid webhook signature.")
    with pytest.raises(ValidationError):
        services.handle_webhook(b"{}", "bad")
    assert Subscription.objects.count() == 0
    assert StripeEventLog.objects.count() == 0


def test_subscription_updated_syncs_status_and_period(parent, family_plan, fake_provider):
    fake_provider.next_event = _completed(parent, family_plan)
    services.handle_webhook(b"{}", "sig")

    fake_provider.next_event = WebhookEvent(
        event_id="evt_2",
        event_type="customer.subscription.updated",
        stripe_subscription_id="sub_1",
        status="past_due",
        current_period_end=PERIOD_END,
        cancel_at_period_end=True,
    )
    services.handle_webhook(b"{}", "sig")

    sub = Subscription.objects.get(stripe_subscription_id="sub_1")
    assert sub.status == Subscription.Status.PAST_DUE
    assert sub.current_period_end == PERIOD_END
    assert sub.cancel_at_period_end is True


def test_subscription_deleted_marks_it_canceled(parent, family_plan, fake_provider):
    fake_provider.next_event = _completed(parent, family_plan)
    services.handle_webhook(b"{}", "sig")

    fake_provider.next_event = WebhookEvent(
        event_id="evt_3",
        event_type="customer.subscription.deleted",
        stripe_subscription_id="sub_1",
        status="canceled",
    )
    services.handle_webhook(b"{}", "sig")

    assert Subscription.objects.get(stripe_subscription_id="sub_1").status == (
        Subscription.Status.CANCELED
    )


def test_invoice_paid_renews_and_reactivates(parent, family_plan, fake_provider):
    fake_provider.next_event = _completed(parent, family_plan)
    services.handle_webhook(b"{}", "sig")
    Subscription.objects.filter(stripe_subscription_id="sub_1").update(
        status=Subscription.Status.PAST_DUE
    )

    fake_provider.next_event = WebhookEvent(
        event_id="evt_4",
        event_type="invoice.paid",
        stripe_subscription_id="sub_1",
        current_period_end=PERIOD_END,
    )
    services.handle_webhook(b"{}", "sig")

    sub = Subscription.objects.get(stripe_subscription_id="sub_1")
    assert sub.status == Subscription.Status.ACTIVE
    assert sub.current_period_end == PERIOD_END


def test_invoice_payment_failed_marks_past_due(parent, family_plan, fake_provider):
    fake_provider.next_event = _completed(parent, family_plan)
    services.handle_webhook(b"{}", "sig")

    fake_provider.next_event = WebhookEvent(
        event_id="evt_5",
        event_type="invoice.payment_failed",
        stripe_subscription_id="sub_1",
    )
    services.handle_webhook(b"{}", "sig")

    assert Subscription.objects.get(stripe_subscription_id="sub_1").status == (
        Subscription.Status.PAST_DUE
    )


def test_unknown_event_type_is_logged_without_effect(db, fake_provider):
    fake_provider.next_event = WebhookEvent(event_id="evt_6", event_type="customer.created")
    services.handle_webhook(b"{}", "sig")

    assert Subscription.objects.count() == 0
    assert StripeEventLog.objects.get(stripe_event_id="evt_6").processed_at is not None


def test_event_for_an_unknown_subscription_is_ignored(db, fake_provider):
    fake_provider.next_event = WebhookEvent(
        event_id="evt_7",
        event_type="customer.subscription.updated",
        stripe_subscription_id="sub_missing",
        status="active",
    )
    services.handle_webhook(b"{}", "sig")
    assert Subscription.objects.count() == 0


def test_checkout_completed_for_an_unknown_user_or_plan_is_ignored(db, fake_provider):
    fake_provider.next_event = WebhookEvent(
        event_id="evt_8",
        event_type="checkout.session.completed",
        stripe_subscription_id="sub_x",
        user_id=999999,
        plan_id=999999,
        status="active",
    )
    services.handle_webhook(b"{}", "sig")
    assert Subscription.objects.count() == 0


def test_checkout_completed_twice_for_the_same_subscription_updates_in_place(
    parent, family_plan, fake_provider
):
    fake_provider.next_event = _completed(parent, family_plan, event_id="evt_9")
    services.handle_webhook(b"{}", "sig")
    fake_provider.next_event = _completed(parent, family_plan, event_id="evt_10")
    services.handle_webhook(b"{}", "sig")

    assert Subscription.objects.filter(stripe_subscription_id="sub_1").count() == 1


def test_cancel_subscription_flags_period_end_locally_and_upstream(
    parent, family_plan, fake_provider
):
    fake_provider.next_event = _completed(parent, family_plan)
    services.handle_webhook(b"{}", "sig")

    sub = services.cancel_subscription(parent)

    assert sub.cancel_at_period_end is True
    assert fake_provider.canceled == ["sub_1"]


def test_cancel_without_a_subscription_raises_not_found(parent):
    with pytest.raises(NotFoundError):
        services.cancel_subscription(parent)


def test_period_end_survives_a_cancel_flag(parent, family_plan, fake_provider):
    fake_provider.next_event = _completed(parent, family_plan)
    services.handle_webhook(b"{}", "sig")
    Subscription.objects.filter(stripe_subscription_id="sub_1").update(
        current_period_end=timezone.now() + dt.timedelta(days=10)
    )
    services.cancel_subscription(parent)
    assert Subscription.objects.get(stripe_subscription_id="sub_1").current_period_end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && pytest kaleem/billing/tests/test_services_webhook.py -v`
Expected: FAIL — `module 'kaleem.billing.services' has no attribute 'handle_webhook'`.

- [ ] **Step 3: Implement**

Append to `backend/kaleem/billing/services.py` (and add the imports it needs at the top:
`import logging`, `from django.utils import timezone`,
`from kaleem.billing.models import StripeEventLog`, `from kaleem.billing.providers import WebhookEvent`):

```python
logger = logging.getLogger(__name__)


def _apply_checkout_completed(event: WebhookEvent) -> None:
    plan = SubscriptionPlan.objects.filter(id=event.plan_id).first()
    user_exists = identity_services.get_profile_types(event.user_id or 0) is not None
    if plan is None or event.user_id is None or not user_exists:
        logger.warning(
            "billing.webhook.unresolved", extra={"event_id": event.event_id}
        )
        return
    Subscription.objects.update_or_create(
        stripe_subscription_id=event.stripe_subscription_id,
        defaults={
            "user_id": event.user_id,
            "plan": plan,
            "status": Subscription.Status.ACTIVE,
        },
    )


def _apply_to_existing(event: WebhookEvent, **updates) -> None:
    subscription = Subscription.objects.filter(
        stripe_subscription_id=event.stripe_subscription_id
    ).first()
    if subscription is None:
        logger.warning("billing.webhook.unknown_subscription", extra={"event_id": event.event_id})
        return
    for field, value in updates.items():
        setattr(subscription, field, value)
    subscription.save()


def _handle_event(event: WebhookEvent) -> None:
    if event.event_type == "checkout.session.completed":
        _apply_checkout_completed(event)
    elif event.event_type in {
        "customer.subscription.updated",
        "customer.subscription.deleted",
    }:
        updates: dict = {"status": event.status}
        if event.current_period_end is not None:
            updates["current_period_end"] = event.current_period_end
        if event.cancel_at_period_end is not None:
            updates["cancel_at_period_end"] = event.cancel_at_period_end
        _apply_to_existing(event, **updates)
    elif event.event_type == "invoice.paid":
        updates = {"status": Subscription.Status.ACTIVE}
        if event.current_period_end is not None:
            updates["current_period_end"] = event.current_period_end
        _apply_to_existing(event, **updates)
    elif event.event_type == "invoice.payment_failed":
        _apply_to_existing(event, status=Subscription.Status.PAST_DUE)
    else:
        logger.info("billing.webhook.ignored", extra={"event_type": event.event_type})


def handle_webhook(payload: bytes, signature: str) -> None:
    """Verify, de-duplicate, and apply one provider event. Raises ValidationError
    when the signature does not verify; unknown event types are a no-op."""
    event = get_provider().verify_and_parse_webhook(payload, signature)
    with transaction.atomic():
        log, created = StripeEventLog.objects.get_or_create(
            stripe_event_id=event.event_id,
            defaults={"event_type": event.event_type},
        )
        if not created:
            return  # already seen — idempotent no-op
        _handle_event(event)
        log.processed_at = timezone.now()
        log.save(update_fields=["processed_at"])


def cancel_subscription(user) -> Subscription:
    """Cancel at period end: access continues until current_period_end."""
    subscription = get_current_subscription(user)
    if subscription is None:
        raise NotFoundError("Subscription", user.id)
    get_provider().cancel_at_period_end(subscription.stripe_subscription_id)
    subscription.cancel_at_period_end = True
    subscription.save(update_fields=["cancel_at_period_end", "updated_at"])
    return subscription
```

Note on `_apply_checkout_completed`: `identity_services.get_profile_types` raises or returns for a
missing user depending on its implementation — read it first (`kaleem/identity/services.py:53`) and
use whichever identity service cleanly answers "does this user exist?". If none does, resolve the
user with `identity_services.get_user(event.user_id)` inside a `try/except NotFoundError`. Adjust
the test `test_checkout_completed_for_an_unknown_user_or_plan_is_ignored` only if the behaviour
(ignore + warn, no crash) still holds.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && pytest kaleem/billing -v`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
cd backend
git add kaleem/billing
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): idempotent webhook handling + cancel at period end"
```

---

## Task 7: Entitlement (`Capability`, `is_entitled_to`)

**Files:**
- Modify: `backend/kaleem/billing/services.py`
- Test: `backend/kaleem/billing/tests/test_entitlement.py`

**Interfaces:**
- Consumes: `Subscription`, `identity_services.get_parent_user_ids`.
- Produces:
  - `class Capability(StrEnum): BOOK_SESSION = "book_session"`
  - `is_entitled_to(user, capability: Capability) -> bool` — the single gate other modules call
    (scheduling will, when booking lands). Rule: the user is entitled when they hold a paid-through
    subscription (status `active`, **or** `canceled`/`cancel_at_period_end` with
    `current_period_end > now`); otherwise, if any parent holds a paid-through **Family**
    subscription, the student inherits it. `past_due` and lapsed are never entitled.

- [ ] **Step 1: Write the failing tests**

`backend/kaleem/billing/tests/test_entitlement.py`:

```python
import datetime as dt

from django.utils import timezone

from kaleem.billing import services
from kaleem.billing.models import Subscription
from kaleem.billing.services import Capability

FUTURE = lambda: timezone.now() + dt.timedelta(days=5)  # noqa: E731
PAST = lambda: timezone.now() - dt.timedelta(days=5)  # noqa: E731


def _sub(user, plan, status, *, period_end=None, cancel=False, sid="sub_1"):
    return Subscription.objects.create(
        user=user,
        plan=plan,
        stripe_subscription_id=sid,
        status=status,
        current_period_end=period_end,
        cancel_at_period_end=cancel,
    )


def test_active_subscriber_is_entitled(adult_student, individual_plan):
    _sub(adult_student, individual_plan, Subscription.Status.ACTIVE)
    assert services.is_entitled_to(adult_student, Capability.BOOK_SESSION) is True


def test_no_subscription_is_not_entitled(adult_student):
    assert services.is_entitled_to(adult_student, Capability.BOOK_SESSION) is False


def test_canceled_but_paid_through_is_still_entitled(adult_student, individual_plan):
    _sub(
        adult_student,
        individual_plan,
        Subscription.Status.CANCELED,
        period_end=FUTURE(),
        cancel=True,
    )
    assert services.is_entitled_to(adult_student, Capability.BOOK_SESSION) is True


def test_lapsed_subscription_is_not_entitled(adult_student, individual_plan):
    _sub(
        adult_student,
        individual_plan,
        Subscription.Status.CANCELED,
        period_end=PAST(),
        cancel=True,
    )
    assert services.is_entitled_to(adult_student, Capability.BOOK_SESSION) is False


def test_canceled_without_a_period_end_is_not_entitled(adult_student, individual_plan):
    _sub(adult_student, individual_plan, Subscription.Status.CANCELED)
    assert services.is_entitled_to(adult_student, Capability.BOOK_SESSION) is False


def test_past_due_is_not_entitled(adult_student, individual_plan):
    _sub(adult_student, individual_plan, Subscription.Status.PAST_DUE, period_end=FUTURE())
    assert services.is_entitled_to(adult_student, Capability.BOOK_SESSION) is False


def test_child_inherits_an_active_family_plan(child, parent, family_plan):
    _sub(parent, family_plan, Subscription.Status.ACTIVE)
    assert services.is_entitled_to(child, Capability.BOOK_SESSION) is True


def test_child_inherits_a_paid_through_canceled_family_plan(child, parent, family_plan):
    _sub(
        parent,
        family_plan,
        Subscription.Status.CANCELED,
        period_end=FUTURE(),
        cancel=True,
    )
    assert services.is_entitled_to(child, Capability.BOOK_SESSION) is True


def test_child_is_not_entitled_without_a_parent_subscription(child):
    assert services.is_entitled_to(child, Capability.BOOK_SESSION) is False


def test_child_does_not_inherit_a_parents_individual_plan(child, parent, individual_plan):
    _sub(parent, individual_plan, Subscription.Status.ACTIVE)
    assert services.is_entitled_to(child, Capability.BOOK_SESSION) is False


def test_child_does_not_inherit_a_past_due_family_plan(child, parent, family_plan):
    _sub(parent, family_plan, Subscription.Status.PAST_DUE)
    assert services.is_entitled_to(child, Capability.BOOK_SESSION) is False


def test_capability_enum_has_book_session():
    assert Capability.BOOK_SESSION == "book_session"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && pytest kaleem/billing/tests/test_entitlement.py -v`
Expected: FAIL — `cannot import name 'Capability' from 'kaleem.billing.services'`.

- [ ] **Step 3: Implement**

Append to `backend/kaleem/billing/services.py` (add `from enum import StrEnum` at the top):

```python
class Capability(StrEnum):
    """What a subscription entitles you to. Other modules gate on these."""

    BOOK_SESSION = "book_session"


def _is_paid_through(subscription: Subscription) -> bool:
    if subscription.status == Subscription.Status.ACTIVE:
        return True
    if subscription.status == Subscription.Status.CANCELED:
        return (
            subscription.current_period_end is not None
            and subscription.current_period_end > timezone.now()
        )
    return False


def _has_paid_through(user_id: int, *, plan_type: str | None = None) -> bool:
    query = Subscription.objects.filter(user_id=user_id)
    if plan_type is not None:
        query = query.filter(plan__plan_type=plan_type)
    return any(_is_paid_through(s) for s in query)


def is_entitled_to(user, capability: Capability) -> bool:
    """The single entitlement gate for the rest of the system.

    B1 answers "is this user covered?" — not "how many sessions remain?".
    All current capabilities resolve to the same subscription check.
    """
    del capability  # only BOOK_SESSION exists; kept for the stable call signature
    if _has_paid_through(user.id):
        return True
    return any(
        _has_paid_through(parent_id, plan_type=SubscriptionPlan.PlanType.FAMILY)
        for parent_id in identity_services.get_parent_user_ids(user.id)
    )
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && pytest kaleem/billing -v --cov=kaleem.billing --cov-report=term-missing --cov-branch`
Expected: all green; `kaleem/billing/*` at **100%** line + branch except `api/` (Task 8). Add tests
for any uncovered branch before continuing.

- [ ] **Step 5: Commit**

```bash
cd backend
git add kaleem/billing
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): entitlement service with family inheritance"
```

---

## Task 8: Billing API + the signature-authenticated webhook (+ ADR-0025)

**Files:**
- Create: `backend/kaleem/billing/api/__init__.py`,
  `backend/kaleem/billing/api/serializers.py`, `backend/kaleem/billing/api/views.py`,
  `backend/kaleem/billing/api/urls.py`, `backend/kaleem/billing/tests/test_api.py`
- Modify: `backend/config/api_router.py`
- Create (meta repo): `docs/adr/0025-stripe-webhook-csrf-exemption.md`

**Interfaces:**
- Consumes: all of `billing.services`.
- Produces these endpoints under `/api/v1/billing/`:
  - `GET plans/` → `[{id, plan_type, sessions_per_cycle, display_amount, currency}]`
  - `POST checkout/` `{plan_id}` → `{checkout_url}`
  - `GET me/subscription/` → `{current: {...} | null, history: [...]}` where a subscription is
    `{id, plan_type, sessions_per_cycle, status, current_period_end, cancel_at_period_end}`
  - `POST me/subscription/cancel/` → the updated current subscription
  - `POST webhook/` → `{"received": true}` (200) / 400 on a bad signature

- [ ] **Step 1: Write the failing API tests**

`backend/kaleem/billing/tests/test_api.py`:

```python
import pytest
from rest_framework.test import APIClient

from kaleem.billing import services
from kaleem.billing.models import Subscription
from kaleem.billing.providers import WebhookEvent
from kaleem.platform.exceptions import ValidationError

PLANS_URL = "/api/v1/billing/plans/"
CHECKOUT_URL = "/api/v1/billing/checkout/"
ME_URL = "/api/v1/billing/me/subscription/"
CANCEL_URL = "/api/v1/billing/me/subscription/cancel/"
WEBHOOK_URL = "/api/v1/billing/webhook/"


@pytest.fixture
def parent_client(parent):
    client = APIClient()
    client.force_authenticate(user=parent)
    return client


def test_plans_requires_authentication(db, family_plan):
    assert APIClient().get(PLANS_URL).status_code == 403


def test_plans_lists_active_plans(parent_client, family_plan):
    resp = parent_client.get(PLANS_URL)
    assert resp.status_code == 200
    assert resp.json() == [
        {
            "id": family_plan.id,
            "plan_type": "family",
            "sessions_per_cycle": 4,
            "display_amount": 5000,
            "currency": "usd",
        }
    ]


def test_checkout_returns_the_hosted_url(parent_client, family_plan, fake_provider):
    resp = parent_client.post(CHECKOUT_URL, {"plan_id": family_plan.id}, format="json")
    assert resp.status_code == 200
    assert resp.json() == {"checkout_url": fake_provider.checkout_url}


def test_checkout_requires_a_plan_id(parent_client, family_plan):
    assert parent_client.post(CHECKOUT_URL, {}, format="json").status_code == 400


def test_checkout_role_mismatch_returns_403(adult_student, family_plan):
    client = APIClient()
    client.force_authenticate(user=adult_student)
    resp = client.post(CHECKOUT_URL, {"plan_id": family_plan.id}, format="json")
    assert resp.status_code == 403


def test_checkout_when_already_subscribed_returns_400(parent_client, parent, family_plan):
    Subscription.objects.create(
        user=parent, plan=family_plan, stripe_subscription_id="sub_live",
        status=Subscription.Status.ACTIVE,
    )
    resp = parent_client.post(CHECKOUT_URL, {"plan_id": family_plan.id}, format="json")
    assert resp.status_code == 400
    assert resp.json() == {"detail": "You already have an active subscription."}


def test_me_subscription_is_empty_without_one(parent_client):
    assert parent_client.get(ME_URL).json() == {"current": None, "history": []}


def test_me_subscription_returns_current_and_history(parent_client, parent, family_plan):
    old = Subscription.objects.create(
        user=parent, plan=family_plan, stripe_subscription_id="sub_old",
        status=Subscription.Status.CANCELED,
    )
    live = Subscription.objects.create(
        user=parent, plan=family_plan, stripe_subscription_id="sub_new",
        status=Subscription.Status.ACTIVE,
    )
    body = parent_client.get(ME_URL).json()
    assert body["current"]["id"] == live.id
    assert body["current"]["plan_type"] == "family"
    assert [row["id"] for row in body["history"]] == [live.id, old.id]


def test_cancel_flags_period_end(parent_client, parent, family_plan, fake_provider):
    Subscription.objects.create(
        user=parent, plan=family_plan, stripe_subscription_id="sub_live",
        status=Subscription.Status.ACTIVE,
    )
    resp = parent_client.post(CANCEL_URL, {}, format="json")
    assert resp.status_code == 200
    assert resp.json()["cancel_at_period_end"] is True
    assert fake_provider.canceled == ["sub_live"]


def test_cancel_without_a_subscription_returns_404(parent_client):
    assert parent_client.post(CANCEL_URL, {}, format="json").status_code == 404


def test_webhook_accepts_a_signed_event_without_auth_or_csrf(
    db, parent, family_plan, fake_provider
):
    fake_provider.next_event = WebhookEvent(
        event_id="evt_api_1",
        event_type="checkout.session.completed",
        stripe_subscription_id="sub_api",
        user_id=parent.id,
        plan_id=family_plan.id,
        status="active",
    )
    client = APIClient(enforce_csrf_checks=True)
    resp = client.post(
        WEBHOOK_URL, data=b"{}", content_type="application/json",
        HTTP_STRIPE_SIGNATURE="t=1,v1=abc",
    )
    assert resp.status_code == 200
    assert resp.json() == {"received": True}
    assert Subscription.objects.filter(stripe_subscription_id="sub_api").exists()


def test_webhook_with_a_bad_signature_returns_400(db, fake_provider):
    fake_provider.raise_on_webhook = ValidationError("Invalid webhook signature.")
    resp = APIClient().post(
        WEBHOOK_URL, data=b"{}", content_type="application/json",
        HTTP_STRIPE_SIGNATURE="bad",
    )
    assert resp.status_code == 400
    assert Subscription.objects.count() == 0


def test_webhook_without_a_signature_header_returns_400(db, fake_provider):
    fake_provider.raise_on_webhook = ValidationError("Invalid webhook signature.")
    resp = APIClient().post(WEBHOOK_URL, data=b"{}", content_type="application/json")
    assert resp.status_code == 400


def test_entitlement_service_is_importable_from_the_module_api(parent):
    # Other modules call exactly this; keep the public name stable.
    assert services.is_entitled_to(parent, services.Capability.BOOK_SESSION) is False
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && pytest kaleem/billing/tests/test_api.py -v`
Expected: FAIL — 404s (routes not mounted).

- [ ] **Step 3: Implement the serializers**

`backend/kaleem/billing/api/__init__.py` — empty file.

`backend/kaleem/billing/api/serializers.py`:

```python
from rest_framework import serializers


class PlanSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    plan_type = serializers.CharField()
    sessions_per_cycle = serializers.IntegerField()
    display_amount = serializers.IntegerField()
    currency = serializers.CharField()


class CheckoutSerializer(serializers.Serializer):
    plan_id = serializers.IntegerField()


class SubscriptionSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    plan_type = serializers.CharField(source="plan.plan_type")
    sessions_per_cycle = serializers.IntegerField(source="plan.sessions_per_cycle")
    status = serializers.CharField()
    current_period_end = serializers.DateTimeField()
    cancel_at_period_end = serializers.BooleanField()
```

- [ ] **Step 4: Implement the views**

`backend/kaleem/billing/api/views.py`:

```python
from django.utils.decorators import method_decorator
from django.views.decorators.csrf import csrf_exempt
from rest_framework.permissions import AllowAny
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from kaleem.billing import services
from kaleem.billing.api.serializers import CheckoutSerializer
from kaleem.billing.api.serializers import PlanSerializer
from kaleem.billing.api.serializers import SubscriptionSerializer


class PlanListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(PlanSerializer(services.list_active_plans(), many=True).data)


class CheckoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = CheckoutSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        url = services.create_checkout(
            request.user, serializer.validated_data["plan_id"]
        )
        return Response({"checkout_url": url})


class MySubscriptionView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        current = services.get_current_subscription(request.user)
        history = request.user.subscriptions.select_related("plan").order_by(
            "-created_at", "-id"
        )
        return Response(
            {
                "current": SubscriptionSerializer(current).data if current else None,
                "history": SubscriptionSerializer(history, many=True).data,
            }
        )


class CancelSubscriptionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        subscription = services.cancel_subscription(request.user)
        return Response(SubscriptionSerializer(subscription).data)


@method_decorator(csrf_exempt, name="dispatch")
class StripeWebhookView(APIView):
    """Server-to-server callback from Stripe.

    CSRF-exempt **by design** and the only such endpoint in the codebase: there is
    no browser session and no cookie to protect — the request is authenticated by
    the Stripe signature header, which `services.handle_webhook` verifies before
    any state changes (a bad signature raises ValidationError → 400). See
    ADR-0025. Do NOT copy this pattern to any session-authenticated endpoint.
    """

    permission_classes = [AllowAny]
    authentication_classes: list = []

    def post(self, request):
        services.handle_webhook(
            request.body, request.META.get("HTTP_STRIPE_SIGNATURE", "")
        )
        return Response({"received": True})
```

`backend/kaleem/billing/api/urls.py`:

```python
from django.urls import path

from kaleem.billing.api.views import CancelSubscriptionView
from kaleem.billing.api.views import CheckoutView
from kaleem.billing.api.views import MySubscriptionView
from kaleem.billing.api.views import PlanListView
from kaleem.billing.api.views import StripeWebhookView

app_name = "billing"
urlpatterns = [
    path("plans/", PlanListView.as_view(), name="plans"),
    path("checkout/", CheckoutView.as_view(), name="checkout"),
    path("me/subscription/", MySubscriptionView.as_view(), name="my-subscription"),
    path(
        "me/subscription/cancel/",
        CancelSubscriptionView.as_view(),
        name="cancel-subscription",
    ),
    path("webhook/", StripeWebhookView.as_view(), name="webhook"),
]
```

In `backend/config/api_router.py`, add to `urlpatterns` above the scheduling line:

```python
    path("billing/", include("kaleem.billing.api.urls")),
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd backend && pytest kaleem/billing -v`
Expected: all green.

- [ ] **Step 6: Write ADR-0025 in the meta repo**

Create `docs/adr/0025-stripe-webhook-csrf-exemption.md` following the format of the existing ADRs
(read `docs/adr/0019-*.md` for the house style). It must state: **Context** — Stripe delivers
subscription state changes server-to-server; our global rule is CSRF always on (the old MVP's
disabled CSRF is on the "don't do this" list). **Decision** — exempt exactly one endpoint,
`POST /api/v1/billing/webhook/`, with no session authentication and `AllowAny`, authenticated
instead by verifying the `Stripe-Signature` HMAC against `DJANGO_STRIPE_WEBHOOK_SECRET` before any
state change; every handler is idempotent via `StripeEventLog`. **Consequences** — a leaked webhook
secret is equivalent to forged billing state (rotate via env, no code change); the exemption is
inline-commented and must never be copied to a cookie-authenticated endpoint; any future provider
callback needs its own ADR.

- [ ] **Step 7: Run the full backend gate**

Run: `cd backend && pytest --cov=kaleem --cov-branch --cov-report=term-missing && ruff format . && ruff check . && mypy kaleem config && lint-imports`
Expected: all tests green; `kaleem/billing/**` at 100% line + branch; lint/mypy/import-linter clean.

- [ ] **Step 8: Commit and open the backend PR**

```bash
cd backend
git add kaleem/billing config/api_router.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): REST API + signature-authenticated Stripe webhook"
git push -u origin feat/billing-subscriptions
gh pr create --base main --title "feat(billing): subscriptions, entitlement, and Stripe webhook (B1)" \
  --body "Implements docs/superpowers/specs/2026-07-09-billing-subscriptions-design.md (Phase B, B1)."
```

---

## Task 9: Dashboard billing data layer (schemas, api, queries)

**Files:**
- Create: `dashboard/src/features/billing/schemas.ts`, `dashboard/src/features/billing/api.ts`,
  `dashboard/src/features/billing/queries.ts`, `dashboard/src/features/billing/index.ts`
- Test: `dashboard/src/features/billing/schemas.test.ts`,
  `dashboard/src/features/billing/api.test.ts`
- Modify: `dashboard/src/features/billing/index.ts` (it currently exists as an empty barrel)

**Interfaces:**
- Consumes: `@/lib/api` (the configured axios instance; base URL already includes `/api/v1/`).
- Produces:
  - types `Plan {id, plan_type: "individual" | "family", sessions_per_cycle, display_amount,
    currency}`, `Subscription {id, plan_type, sessions_per_cycle, status, current_period_end:
    string | null, cancel_at_period_end}`, `MySubscription {current: Subscription | null, history:
    Subscription[]}`
  - `billingApi.listPlans()`, `billingApi.createCheckout(planId)`, `billingApi.getMySubscription()`,
    `billingApi.cancelSubscription()`
  - hooks `usePlans()`, `useCreateCheckout()`, `useMySubscription(options?)`,
    `useCancelSubscription()`; `mySubscriptionQueryKey = ["billing", "subscription"]`

- [ ] **Step 1: Write the failing schema test**

`dashboard/src/features/billing/schemas.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { mySubscriptionSchema, planSchema } from "./schemas";

describe("billing schemas", () => {
	it("parses a plan", () => {
		const plan = planSchema.parse({
			id: 1,
			plan_type: "family",
			sessions_per_cycle: 4,
			display_amount: 5000,
			currency: "usd",
		});
		expect(plan.plan_type).toBe("family");
	});

	it("rejects an unknown plan type", () => {
		expect(() =>
			planSchema.parse({
				id: 1,
				plan_type: "enterprise",
				sessions_per_cycle: 4,
				display_amount: 5000,
				currency: "usd",
			}),
		).toThrow();
	});

	it("parses an empty subscription payload", () => {
		expect(mySubscriptionSchema.parse({ current: null, history: [] })).toEqual({
			current: null,
			history: [],
		});
	});

	it("parses a subscription with a null period end", () => {
		const parsed = mySubscriptionSchema.parse({
			current: {
				id: 3,
				plan_type: "individual",
				sessions_per_cycle: 4,
				status: "active",
				current_period_end: null,
				cancel_at_period_end: false,
			},
			history: [],
		});
		expect(parsed.current?.status).toBe("active");
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd dashboard && pnpm test src/features/billing`
Expected: FAIL — cannot resolve `./schemas`.

- [ ] **Step 3: Implement the schemas**

`dashboard/src/features/billing/schemas.ts`:

```ts
import { z } from "zod";

export const planTypeSchema = z.enum(["individual", "family"]);

export const planSchema = z.object({
	id: z.number(),
	plan_type: planTypeSchema,
	sessions_per_cycle: z.number(),
	display_amount: z.number(),
	currency: z.string(),
});

export const subscriptionStatusSchema = z.enum([
	"active",
	"past_due",
	"canceled",
	"incomplete",
	"incomplete_expired",
	"unpaid",
]);

export const subscriptionSchema = z.object({
	id: z.number(),
	plan_type: planTypeSchema,
	sessions_per_cycle: z.number(),
	status: subscriptionStatusSchema,
	current_period_end: z.string().nullable(),
	cancel_at_period_end: z.boolean(),
});

export const mySubscriptionSchema = z.object({
	current: subscriptionSchema.nullable(),
	history: z.array(subscriptionSchema),
});

export type PlanType = z.infer<typeof planTypeSchema>;
export type Plan = z.infer<typeof planSchema>;
export type SubscriptionStatus = z.infer<typeof subscriptionStatusSchema>;
export type Subscription = z.infer<typeof subscriptionSchema>;
export type MySubscription = z.infer<typeof mySubscriptionSchema>;
```

- [ ] **Step 4: Write the failing api test**

`dashboard/src/features/billing/api.test.ts` (mirror `src/features/identity/api.test.ts` — read it
for the axios-mocking convention used in this repo and follow it exactly):

```ts
import { describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { billingApi } from "./api";

vi.mock("@/lib/api", () => ({
	api: { get: vi.fn(), post: vi.fn() },
}));

describe("billingApi", () => {
	it("lists plans", async () => {
		vi.mocked(api.get).mockResolvedValue({ data: [] });
		await expect(billingApi.listPlans()).resolves.toEqual([]);
		expect(api.get).toHaveBeenCalledWith("billing/plans/");
	});

	it("creates a checkout session", async () => {
		vi.mocked(api.post).mockResolvedValue({
			data: { checkout_url: "https://checkout.test/x" },
		});
		await expect(billingApi.createCheckout(2)).resolves.toBe(
			"https://checkout.test/x",
		);
		expect(api.post).toHaveBeenCalledWith("billing/checkout/", { plan_id: 2 });
	});

	it("gets the current subscription", async () => {
		vi.mocked(api.get).mockResolvedValue({
			data: { current: null, history: [] },
		});
		await expect(billingApi.getMySubscription()).resolves.toEqual({
			current: null,
			history: [],
		});
		expect(api.get).toHaveBeenCalledWith("billing/me/subscription/");
	});

	it("cancels the subscription", async () => {
		vi.mocked(api.post).mockResolvedValue({ data: {} });
		await billingApi.cancelSubscription();
		expect(api.post).toHaveBeenCalledWith("billing/me/subscription/cancel/");
	});
});
```

- [ ] **Step 5: Implement api + queries + barrel**

`dashboard/src/features/billing/api.ts`:

```ts
import { api } from "@/lib/api";
import type { MySubscription, Plan } from "./schemas";

export const billingApi = {
	listPlans: (): Promise<Plan[]> =>
		api.get<Plan[]>("billing/plans/").then((r) => r.data),

	createCheckout: (planId: number): Promise<string> =>
		api
			.post<{ checkout_url: string }>("billing/checkout/", { plan_id: planId })
			.then((r) => r.data.checkout_url),

	getMySubscription: (): Promise<MySubscription> =>
		api.get<MySubscription>("billing/me/subscription/").then((r) => r.data),

	cancelSubscription: (): Promise<void> =>
		api.post("billing/me/subscription/cancel/").then(() => undefined),
};
```

`dashboard/src/features/billing/queries.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { billingApi } from "./api";

export const plansQueryKey = ["billing", "plans"] as const;
export const mySubscriptionQueryKey = ["billing", "subscription"] as const;

export function usePlans() {
	return useQuery({
		queryKey: plansQueryKey,
		queryFn: billingApi.listPlans,
		retry: false,
	});
}

export function useMySubscription({ poll = false }: { poll?: boolean } = {}) {
	return useQuery({
		queryKey: mySubscriptionQueryKey,
		queryFn: billingApi.getMySubscription,
		retry: false,
		// While returning from Stripe the confirming webhook is still in flight,
		// so the page polls until the subscription reads active.
		refetchInterval: poll ? 2000 : false,
	});
}

export function useCreateCheckout() {
	return useMutation({
		mutationFn: (planId: number) => billingApi.createCheckout(planId),
	});
}

export function useCancelSubscription() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: () => billingApi.cancelSubscription(),
		onSuccess: () => qc.invalidateQueries({ queryKey: mySubscriptionQueryKey }),
	});
}
```

`dashboard/src/features/billing/index.ts` (replace the empty barrel):

```ts
export { billingApi } from "./api";
export {
	mySubscriptionQueryKey,
	plansQueryKey,
	useCancelSubscription,
	useCreateCheckout,
	useMySubscription,
	usePlans,
} from "./queries";
export type {
	MySubscription,
	Plan,
	PlanType,
	Subscription,
	SubscriptionStatus,
} from "./schemas";
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd dashboard && pnpm test src/features/billing && pnpm exec tsc --noEmit`
Expected: 8 passed, tsc clean.

- [ ] **Step 7: Commit**

```bash
cd dashboard
git checkout -b feat/billing-subscriptions
git add src/features/billing
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): dashboard data layer for plans and subscriptions"
```

---

## Task 10: i18n copy for billing (en + ar)

**Files:**
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`

**Interfaces:**
- Produces the `billing.*` namespace consumed by Tasks 11–13. Exact keys below — later tasks
  reference them verbatim.

- [ ] **Step 1: Add the English copy**

In `dashboard/src/locales/en/common.json`, add a top-level `"billing"` object (keep `modules.billing`
as-is — it still labels the nav/tile):

```json
"billing": {
  "title": "Billing",
  "subtitle": "Your subscription and payments.",
  "planIndividual": "Individual",
  "planFamily": "Family",
  "planIndividualDesc": "For one student. {{count}} sessions each month.",
  "planFamilyDesc": "For a parent and their children. {{count}} sessions per child each month.",
  "perMonth": "{{price}} / month",
  "subscribe": "Subscribe",
  "plansEmpty": "No plans are available right now.",
  "plansError": "Couldn't load the plans. Please try again.",
  "checkoutError": "Couldn't start checkout. Please try again.",
  "currentPlan": "Current plan",
  "statusActive": "Active",
  "statusPastDue": "Payment failed — please update your card.",
  "statusCanceled": "Canceled",
  "cancelsOn": "Cancels on {{date}}",
  "renewsOn": "Renews on {{date}}",
  "history": "Subscription history",
  "cancel": "Cancel subscription",
  "cancelTitle": "Cancel your subscription?",
  "cancelBody": "You keep access until {{date}}. After that your subscription ends and you won't be charged again.",
  "cancelBodyNoDate": "You keep access until the end of the current paid month. After that your subscription ends and you won't be charged again.",
  "cancelConfirm": "Yes, cancel",
  "cancelDismiss": "Keep subscription",
  "cancelError": "Couldn't cancel your subscription. Please try again.",
  "finishing": "Finishing up your subscription…",
  "finishingHint": "This can take a few seconds while your payment is confirmed.",
  "finishingTimeout": "This is taking longer than usual. Refresh the page in a moment — your payment may still be processing.",
  "checkoutCancelled": "Checkout was cancelled. You have not been charged.",
  "subscribed": "You're subscribed."
}
```

- [ ] **Step 2: Add the Arabic copy**

Add the same key set to `dashboard/src/locales/ar/common.json`:

```json
"billing": {
  "title": "الفوترة",
  "subtitle": "اشتراكك ومدفوعاتك.",
  "planIndividual": "فردي",
  "planFamily": "عائلي",
  "planIndividualDesc": "لطالب واحد. {{count}} حصص كل شهر.",
  "planFamilyDesc": "لولي أمر وأبنائه. {{count}} حصص لكل طفل كل شهر.",
  "perMonth": "{{price}} / شهريًا",
  "subscribe": "اشترك",
  "plansEmpty": "لا توجد خطط متاحة حاليًا.",
  "plansError": "تعذّر تحميل الخطط. حاول مرة أخرى.",
  "checkoutError": "تعذّر بدء عملية الدفع. حاول مرة أخرى.",
  "currentPlan": "الخطة الحالية",
  "statusActive": "نشط",
  "statusPastDue": "فشل الدفع — يرجى تحديث بطاقتك.",
  "statusCanceled": "ملغى",
  "cancelsOn": "ينتهي في {{date}}",
  "renewsOn": "يتجدد في {{date}}",
  "history": "سجل الاشتراكات",
  "cancel": "إلغاء الاشتراك",
  "cancelTitle": "إلغاء اشتراكك؟",
  "cancelBody": "يستمر وصولك حتى {{date}}. بعد ذلك ينتهي اشتراكك ولن تُحصَّل منك رسوم جديدة.",
  "cancelBodyNoDate": "يستمر وصولك حتى نهاية الشهر المدفوع الحالي. بعد ذلك ينتهي اشتراكك ولن تُحصَّل منك رسوم جديدة.",
  "cancelConfirm": "نعم، ألغِ الاشتراك",
  "cancelDismiss": "الاحتفاظ بالاشتراك",
  "cancelError": "تعذّر إلغاء اشتراكك. حاول مرة أخرى.",
  "finishing": "جارٍ إتمام اشتراكك…",
  "finishingHint": "قد يستغرق هذا بضع ثوانٍ أثناء تأكيد الدفع.",
  "finishingTimeout": "يستغرق هذا وقتًا أطول من المعتاد. حدّث الصفحة بعد قليل — قد تكون عملية الدفع قيد المعالجة.",
  "checkoutCancelled": "تم إلغاء عملية الدفع. لم تُخصم منك أي مبالغ.",
  "subscribed": "تم اشتراكك."
}
```

- [ ] **Step 3: Verify both files parse and stay in sync**

Run: `cd dashboard && node -e "const en=require('./src/locales/en/common.json'),ar=require('./src/locales/ar/common.json');const a=Object.keys(en.billing).sort(),b=Object.keys(ar.billing).sort();if(JSON.stringify(a)!==JSON.stringify(b)){console.error('key mismatch',a,b);process.exit(1)}console.log('billing keys in sync:',a.length)"`
Expected: `billing keys in sync: 28`

- [ ] **Step 4: Commit**

```bash
cd dashboard
git add src/locales
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): en/ar copy for the billing page"
```

---

## Task 11: `PlanList` component

**Files:**
- Create: `dashboard/src/features/billing/components/PlanList.tsx`
- Test: `dashboard/src/features/billing/components/PlanList.test.tsx`

**Interfaces:**
- Consumes: `usePlans`, `useCreateCheckout` (Task 9), `billing.*` i18n (Task 10),
  `Card*`, `Button`, `Spinner`, `Alert`, `AlertDescription`, `CardGrid`, `EmptyState` from `@/ui`.
- Produces: `<PlanList />` — self-fetching. Renders one card per plan (title + description +
  formatted price + Subscribe). On Subscribe it calls the checkout mutation and navigates with
  `window.location.assign(url)`. Exported through the feature barrel.

- [ ] **Step 1: Write the failing test**

`dashboard/src/features/billing/components/PlanList.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { billingApi } from "../api";
import { PlanList } from "./PlanList";

vi.mock("../api", () => ({
	billingApi: {
		listPlans: vi.fn(),
		createCheckout: vi.fn(),
		getMySubscription: vi.fn(),
		cancelSubscription: vi.fn(),
	},
}));

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

const familyPlan = {
	id: 1,
	plan_type: "family" as const,
	sessions_per_cycle: 4,
	display_amount: 5000,
	currency: "usd",
};

describe("PlanList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.stubGlobal("location", { assign: vi.fn() } as unknown as Location);
	});

	it("renders a plan with its formatted price", async () => {
		vi.mocked(billingApi.listPlans).mockResolvedValue([familyPlan]);
		render(<PlanList />, { wrapper });
		expect(await screen.findByText("Family")).toBeInTheDocument();
		expect(screen.getByText(/\$50\.00 \/ month/)).toBeInTheDocument();
	});

	it("redirects to the hosted checkout on subscribe", async () => {
		vi.mocked(billingApi.listPlans).mockResolvedValue([familyPlan]);
		vi.mocked(billingApi.createCheckout).mockResolvedValue(
			"https://checkout.test/session",
		);
		render(<PlanList />, { wrapper });
		await userEvent.click(await screen.findByRole("button", { name: /subscribe/i }));
		await waitFor(() =>
			expect(window.location.assign).toHaveBeenCalledWith(
				"https://checkout.test/session",
			),
		);
		expect(billingApi.createCheckout).toHaveBeenCalledWith(1);
	});

	it("shows an error when checkout fails", async () => {
		vi.mocked(billingApi.listPlans).mockResolvedValue([familyPlan]);
		vi.mocked(billingApi.createCheckout).mockRejectedValue(new Error("nope"));
		render(<PlanList />, { wrapper });
		await userEvent.click(await screen.findByRole("button", { name: /subscribe/i }));
		expect(await screen.findByRole("alert")).toHaveTextContent(
			/couldn't start checkout/i,
		);
	});

	it("shows an empty state when there are no plans", async () => {
		vi.mocked(billingApi.listPlans).mockResolvedValue([]);
		render(<PlanList />, { wrapper });
		expect(await screen.findByText(/no plans are available/i)).toBeInTheDocument();
	});

	it("shows an error state when plans fail to load", async () => {
		vi.mocked(billingApi.listPlans).mockRejectedValue(new Error("boom"));
		render(<PlanList />, { wrapper });
		expect(await screen.findByRole("alert")).toHaveTextContent(
			/couldn't load the plans/i,
		);
	});

	it("has no axe violations", async () => {
		vi.mocked(billingApi.listPlans).mockResolvedValue([familyPlan]);
		const { container } = render(<PlanList />, { wrapper });
		await screen.findByText("Family");
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd dashboard && pnpm test src/features/billing/components/PlanList`
Expected: FAIL — cannot resolve `./PlanList`.

- [ ] **Step 3: Implement**

`dashboard/src/features/billing/components/PlanList.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	CardDescription,
	CardGrid,
	CardHeader,
	CardTitle,
	EmptyState,
	Spinner,
} from "@/ui";
import { usePlans, useCreateCheckout } from "../queries";
import type { Plan } from "../schemas";

// Stripe amounts are minor units; render with the page locale.
export function formatPrice(plan: Plan, locale: string): string {
	return new Intl.NumberFormat(locale, {
		style: "currency",
		currency: plan.currency.toUpperCase(),
	}).format(plan.display_amount / 100);
}

export function PlanList() {
	const { t, i18n } = useTranslation();
	const { data, isPending, isError } = usePlans();
	const checkout = useCreateCheckout();

	if (isPending) return <Spinner />;
	if (isError)
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("billing.plansError")}</AlertDescription>
			</Alert>
		);
	if (data.length === 0)
		return <EmptyState title={t("billing.plansEmpty")} />;

	return (
		<div className="flex flex-col gap-4">
			{checkout.isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("billing.checkoutError")}</AlertDescription>
				</Alert>
			) : null}
			<CardGrid>
				{data.map((plan) => (
					<Card key={plan.id}>
						<CardHeader>
							<CardTitle>
								{plan.plan_type === "family"
									? t("billing.planFamily")
									: t("billing.planIndividual")}
							</CardTitle>
							<CardDescription>
								{plan.plan_type === "family"
									? t("billing.planFamilyDesc", { count: plan.sessions_per_cycle })
									: t("billing.planIndividualDesc", {
											count: plan.sessions_per_cycle,
										})}
							</CardDescription>
						</CardHeader>
						<CardContent className="flex flex-col gap-4">
							<p className="font-display text-2xl font-semibold">
								{t("billing.perMonth", {
									price: formatPrice(plan, i18n.language),
								})}
							</p>
							<div>
								<Button
									disabled={checkout.isPending}
									onClick={() =>
										checkout.mutate(plan.id, {
											onSuccess: (url) => window.location.assign(url),
										})
									}
								>
									{t("billing.subscribe")}
								</Button>
							</div>
						</CardContent>
					</Card>
				))}
			</CardGrid>
		</div>
	);
}
```

Check `EmptyState`'s actual prop names in `src/ui/empty-state.tsx` before using it and adapt the
call (it may require `icon`/`description`); same for `CardGrid`'s `--card-min` prop.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd dashboard && pnpm test src/features/billing/components/PlanList`
Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
cd dashboard
git add src/features/billing
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): PlanList with hosted-checkout redirect"
```

---

## Task 12: `SubscriptionCard` + `CancelSubscriptionDialog`

**Files:**
- Create: `dashboard/src/features/billing/components/SubscriptionCard.tsx`,
  `dashboard/src/features/billing/components/CancelSubscriptionDialog.tsx`
- Test: `dashboard/src/features/billing/components/SubscriptionCard.test.tsx`,
  `dashboard/src/features/billing/components/CancelSubscriptionDialog.test.tsx`

**Interfaces:**
- Consumes: `Subscription` type, `useCancelSubscription` (Task 9), `billing.*` i18n (Task 10),
  the `AlertDialog` pattern from `src/features/identity/components/RemoveEmailDialog.tsx`.
- Produces:
  - `<SubscriptionCard subscription={Subscription} history={Subscription[]} />` — status line,
    renewal/cancellation date, history list, and the cancel dialog (hidden once
    `cancel_at_period_end` is true).
  - `<CancelSubscriptionDialog periodEnd={string | null} />`.

- [ ] **Step 1: Write the failing dialog test**

`dashboard/src/features/billing/components/CancelSubscriptionDialog.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { billingApi } from "../api";
import { CancelSubscriptionDialog } from "./CancelSubscriptionDialog";

vi.mock("../api", () => ({
	billingApi: {
		listPlans: vi.fn(),
		createCheckout: vi.fn(),
		getMySubscription: vi.fn(),
		cancelSubscription: vi.fn(),
	},
}));

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("CancelSubscriptionDialog", () => {
	beforeEach(() => vi.clearAllMocks());

	it("explains that access continues until the period end", async () => {
		render(<CancelSubscriptionDialog periodEnd="2030-01-01T00:00:00Z" />, {
			wrapper,
		});
		await userEvent.click(screen.getByRole("button", { name: /cancel subscription/i }));
		const dialog = await screen.findByRole("alertdialog");
		expect(dialog).toHaveTextContent(/you keep access until/i);
	});

	it("falls back to undated copy when there is no period end", async () => {
		render(<CancelSubscriptionDialog periodEnd={null} />, { wrapper });
		await userEvent.click(screen.getByRole("button", { name: /cancel subscription/i }));
		expect(await screen.findByRole("alertdialog")).toHaveTextContent(
			/end of the current paid month/i,
		);
	});

	it("cancels on confirm", async () => {
		vi.mocked(billingApi.cancelSubscription).mockResolvedValue(undefined);
		render(<CancelSubscriptionDialog periodEnd={null} />, { wrapper });
		await userEvent.click(screen.getByRole("button", { name: /cancel subscription/i }));
		const dialog = await screen.findByRole("alertdialog");
		await userEvent.click(within(dialog).getByRole("button", { name: /yes, cancel/i }));
		await waitFor(() => expect(billingApi.cancelSubscription).toHaveBeenCalled());
	});

	it("does not cancel when dismissed", async () => {
		render(<CancelSubscriptionDialog periodEnd={null} />, { wrapper });
		await userEvent.click(screen.getByRole("button", { name: /cancel subscription/i }));
		await screen.findByRole("alertdialog");
		await userEvent.click(screen.getByRole("button", { name: /keep subscription/i }));
		expect(billingApi.cancelSubscription).not.toHaveBeenCalled();
	});

	it("shows an error when cancelling fails", async () => {
		vi.mocked(billingApi.cancelSubscription).mockRejectedValue(new Error("boom"));
		render(<CancelSubscriptionDialog periodEnd={null} />, { wrapper });
		await userEvent.click(screen.getByRole("button", { name: /cancel subscription/i }));
		const dialog = await screen.findByRole("alertdialog");
		await userEvent.click(within(dialog).getByRole("button", { name: /yes, cancel/i }));
		expect(await screen.findByRole("alert")).toHaveTextContent(/couldn't cancel/i);
	});

	it("has no axe violations when open", async () => {
		render(<CancelSubscriptionDialog periodEnd={null} />, { wrapper });
		await userEvent.click(screen.getByRole("button", { name: /cancel subscription/i }));
		await screen.findByRole("alertdialog");
		expect(
			await axe(document.body, { rules: { region: { enabled: false } } }),
		).toHaveNoViolations();
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd dashboard && pnpm test src/features/billing/components/CancelSubscriptionDialog`
Expected: FAIL — cannot resolve `./CancelSubscriptionDialog`.

- [ ] **Step 3: Implement the dialog**

`dashboard/src/features/billing/components/CancelSubscriptionDialog.tsx`:

```tsx
import { AlertDialog } from "radix-ui";
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription, Button } from "@/ui";
import { useCancelSubscription } from "../queries";

export function CancelSubscriptionDialog({
	periodEnd,
}: {
	periodEnd: string | null;
}) {
	const { t, i18n } = useTranslation();
	const cancel = useCancelSubscription();
	const formattedDate = periodEnd
		? new Intl.DateTimeFormat(i18n.language, { dateStyle: "long" }).format(
				new Date(periodEnd),
			)
		: null;

	return (
		<div className="flex flex-col gap-2">
			{cancel.isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("billing.cancelError")}</AlertDescription>
				</Alert>
			) : null}
			<AlertDialog.Root>
				<AlertDialog.Trigger asChild>
					<Button variant="outline">{t("billing.cancel")}</Button>
				</AlertDialog.Trigger>
				<AlertDialog.Portal>
					<AlertDialog.Overlay className="fixed inset-0 z-40 bg-black/40" />
					<AlertDialog.Content className="fixed start-1/2 top-1/2 z-50 w-[min(90vw,24rem)] -translate-x-1/2 -translate-y-1/2 rounded-lg border border-border bg-background p-6 shadow-lg rtl:translate-x-1/2">
						<AlertDialog.Title className="font-display text-lg font-semibold">
							{t("billing.cancelTitle")}
						</AlertDialog.Title>
						<AlertDialog.Description className="mt-1 text-sm text-muted-foreground">
							{formattedDate
								? t("billing.cancelBody", { date: formattedDate })
								: t("billing.cancelBodyNoDate")}
						</AlertDialog.Description>
						<div className="mt-4 flex justify-end gap-2">
							<AlertDialog.Cancel asChild>
								<Button type="button" variant="outline">
									{t("billing.cancelDismiss")}
								</Button>
							</AlertDialog.Cancel>
							<AlertDialog.Action asChild>
								<Button
									type="button"
									variant="destructive"
									onClick={() => cancel.mutate()}
								>
									{t("billing.cancelConfirm")}
								</Button>
							</AlertDialog.Action>
						</div>
					</AlertDialog.Content>
				</AlertDialog.Portal>
			</AlertDialog.Root>
		</div>
	);
}
```

- [ ] **Step 4: Write the failing SubscriptionCard test**

`dashboard/src/features/billing/components/SubscriptionCard.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import type { Subscription } from "../schemas";
import { SubscriptionCard } from "./SubscriptionCard";

vi.mock("../api", () => ({
	billingApi: {
		listPlans: vi.fn(),
		createCheckout: vi.fn(),
		getMySubscription: vi.fn(),
		cancelSubscription: vi.fn(),
	},
}));

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

const active: Subscription = {
	id: 1,
	plan_type: "family",
	sessions_per_cycle: 4,
	status: "active",
	current_period_end: "2030-01-01T00:00:00Z",
	cancel_at_period_end: false,
};

describe("SubscriptionCard", () => {
	it("shows an active plan with its renewal date", () => {
		render(<SubscriptionCard subscription={active} history={[active]} />, {
			wrapper,
		});
		expect(screen.getByText("Family")).toBeInTheDocument();
		expect(screen.getByText(/active/i)).toBeInTheDocument();
		expect(screen.getByText(/renews on/i)).toBeInTheDocument();
	});

	it("shows the cancellation date and hides the cancel button once cancelled", () => {
		render(
			<SubscriptionCard
				subscription={{ ...active, cancel_at_period_end: true }}
				history={[]}
			/>,
			{ wrapper },
		);
		expect(screen.getByText(/cancels on/i)).toBeInTheDocument();
		expect(
			screen.queryByRole("button", { name: /cancel subscription/i }),
		).not.toBeInTheDocument();
	});

	it("shows a past-due warning", () => {
		render(
			<SubscriptionCard
				subscription={{ ...active, status: "past_due" }}
				history={[]}
			/>,
			{ wrapper },
		);
		expect(screen.getByRole("alert")).toHaveTextContent(/payment failed/i);
	});

	it("renders history rows", () => {
		render(
			<SubscriptionCard
				subscription={active}
				history={[active, { ...active, id: 2, status: "canceled" }]}
			/>,
			{ wrapper },
		);
		expect(screen.getByText(/subscription history/i)).toBeInTheDocument();
		expect(screen.getAllByRole("listitem")).toHaveLength(2);
	});

	it("omits the history section when there is only the current row", () => {
		render(<SubscriptionCard subscription={active} history={[active]} />, {
			wrapper,
		});
		expect(screen.queryByText(/subscription history/i)).not.toBeInTheDocument();
	});

	it("renders without a period end", () => {
		render(
			<SubscriptionCard
				subscription={{ ...active, current_period_end: null }}
				history={[]}
			/>,
			{ wrapper },
		);
		expect(screen.queryByText(/renews on/i)).not.toBeInTheDocument();
	});

	it("has no axe violations", async () => {
		const { container } = render(
			<SubscriptionCard subscription={active} history={[active]} />,
			{ wrapper },
		);
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 5: Implement `SubscriptionCard`**

`dashboard/src/features/billing/components/SubscriptionCard.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
} from "@/ui";
import type { Subscription } from "../schemas";
import { CancelSubscriptionDialog } from "./CancelSubscriptionDialog";

function useDateFormatter() {
	const { i18n } = useTranslation();
	return (value: string | null) =>
		value
			? new Intl.DateTimeFormat(i18n.language, { dateStyle: "long" }).format(
					new Date(value),
				)
			: null;
}

export function SubscriptionCard({
	subscription,
	history,
}: {
	subscription: Subscription;
	history: Subscription[];
}) {
	const { t } = useTranslation();
	const formatDate = useDateFormatter();
	const periodEnd = formatDate(subscription.current_period_end);
	const planName =
		subscription.plan_type === "family"
			? t("billing.planFamily")
			: t("billing.planIndividual");

	return (
		<Card>
			<CardHeader>
				<CardTitle>{t("billing.currentPlan")}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-3">
				<p className="font-display text-xl font-semibold">{planName}</p>
				{subscription.status === "past_due" ? (
					<Alert variant="destructive">
						<AlertDescription>{t("billing.statusPastDue")}</AlertDescription>
					</Alert>
				) : (
					<p className="text-sm text-muted-foreground">
						{t("billing.statusActive")}
					</p>
				)}
				{periodEnd ? (
					<p className="text-sm text-muted-foreground">
						{subscription.cancel_at_period_end
							? t("billing.cancelsOn", { date: periodEnd })
							: t("billing.renewsOn", { date: periodEnd })}
					</p>
				) : null}
				{subscription.cancel_at_period_end ? null : (
					<div>
						<CancelSubscriptionDialog
							periodEnd={subscription.current_period_end}
						/>
					</div>
				)}
				{history.length > 1 ? (
					<section className="mt-2 border-t border-border pt-3">
						<h3 className="text-sm font-medium">{t("billing.history")}</h3>
						<ul className="mt-2 flex flex-col gap-1 text-sm text-muted-foreground">
							{history.map((row) => (
								<li key={row.id}>
									{row.plan_type === "family"
										? t("billing.planFamily")
										: t("billing.planIndividual")}{" "}
									— {row.status}
									{formatDate(row.current_period_end)
										? ` · ${formatDate(row.current_period_end)}`
										: ""}
								</li>
							))}
						</ul>
					</section>
				) : null}
			</CardContent>
		</Card>
	);
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd dashboard && pnpm test src/features/billing`
Expected: all green (schemas, api, PlanList, dialog, card).

- [ ] **Step 7: Commit**

```bash
cd dashboard
git add src/features/billing
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): SubscriptionCard + cancel-at-period-end dialog"
```

---

## Task 13: `CheckoutReturn` poller

**Files:**
- Create: `dashboard/src/features/billing/components/CheckoutReturn.tsx`
- Test: `dashboard/src/features/billing/components/CheckoutReturn.test.tsx`

**Interfaces:**
- Consumes: `useMySubscription({ poll: true })` (Task 9), `billing.*` i18n (Task 10).
- Produces: `<CheckoutReturn status="success" | "cancelled" onSettled={() => void} />` —
  on `success`, renders the "finishing up…" state while polling and calls `onSettled()` once the
  subscription reads `active`; after `POLL_TIMEOUT_MS` (20s) it shows the timeout copy and stops
  polling. On `cancelled`, renders a neutral notice. Exported `POLL_TIMEOUT_MS` for the test.

- [ ] **Step 1: Write the failing test**

`dashboard/src/features/billing/components/CheckoutReturn.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { billingApi } from "../api";
import { CheckoutReturn } from "./CheckoutReturn";

vi.mock("../api", () => ({
	billingApi: {
		listPlans: vi.fn(),
		createCheckout: vi.fn(),
		getMySubscription: vi.fn(),
		cancelSubscription: vi.fn(),
	},
}));

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

const activeSubscription = {
	current: {
		id: 1,
		plan_type: "family" as const,
		sessions_per_cycle: 4,
		status: "active" as const,
		current_period_end: null,
		cancel_at_period_end: false,
	},
	history: [],
};

describe("CheckoutReturn", () => {
	beforeEach(() => vi.clearAllMocks());
	afterEach(() => vi.useRealTimers());

	it("shows the finishing-up state while the webhook is in flight", async () => {
		vi.mocked(billingApi.getMySubscription).mockResolvedValue({
			current: null,
			history: [],
		});
		render(<CheckoutReturn status="success" onSettled={vi.fn()} />, { wrapper });
		expect(await screen.findByText(/finishing up/i)).toBeInTheDocument();
	});

	it("calls onSettled once the subscription is active", async () => {
		vi.mocked(billingApi.getMySubscription).mockResolvedValue(activeSubscription);
		const onSettled = vi.fn();
		render(<CheckoutReturn status="success" onSettled={onSettled} />, { wrapper });
		await waitFor(() => expect(onSettled).toHaveBeenCalled());
	});

	it("shows the timeout message after the poll window", async () => {
		vi.useFakeTimers({ shouldAdvanceTime: true });
		vi.mocked(billingApi.getMySubscription).mockResolvedValue({
			current: null,
			history: [],
		});
		render(<CheckoutReturn status="success" onSettled={vi.fn()} />, { wrapper });
		await screen.findByText(/finishing up/i);
		await vi.advanceTimersByTimeAsync(21_000);
		expect(
			await screen.findByText(/taking longer than usual/i),
		).toBeInTheDocument();
	});

	it("shows a neutral notice when checkout was cancelled", () => {
		render(<CheckoutReturn status="cancelled" onSettled={vi.fn()} />, { wrapper });
		expect(screen.getByText(/checkout was cancelled/i)).toBeInTheDocument();
	});

	it("has no axe violations", async () => {
		vi.mocked(billingApi.getMySubscription).mockResolvedValue({
			current: null,
			history: [],
		});
		const { container } = render(
			<CheckoutReturn status="success" onSettled={vi.fn()} />,
			{ wrapper },
		);
		await screen.findByText(/finishing up/i);
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd dashboard && pnpm test src/features/billing/components/CheckoutReturn`
Expected: FAIL — cannot resolve `./CheckoutReturn`.

- [ ] **Step 3: Implement**

`dashboard/src/features/billing/components/CheckoutReturn.tsx`:

```tsx
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription, Spinner } from "@/ui";
import { useMySubscription } from "../queries";

// How long we keep polling for the confirming webhook before telling the user
// to come back in a moment. Stripe usually delivers within a couple of seconds.
export const POLL_TIMEOUT_MS = 20_000;

export function CheckoutReturn({
	status,
	onSettled,
}: {
	status: "success" | "cancelled";
	onSettled: () => void;
}) {
	const { t } = useTranslation();
	const [timedOut, setTimedOut] = useState(false);
	const isSuccess = status === "success";
	const { data } = useMySubscription({ poll: isSuccess && !timedOut });
	const isActive = data?.current?.status === "active";

	useEffect(() => {
		if (!isSuccess || timedOut) return;
		const timer = setTimeout(() => setTimedOut(true), POLL_TIMEOUT_MS);
		return () => clearTimeout(timer);
	}, [isSuccess, timedOut]);

	useEffect(() => {
		if (isSuccess && isActive) onSettled();
	}, [isSuccess, isActive, onSettled]);

	if (!isSuccess)
		return (
			<Alert>
				<AlertDescription>{t("billing.checkoutCancelled")}</AlertDescription>
			</Alert>
		);
	if (timedOut)
		return (
			<Alert>
				<AlertDescription>{t("billing.finishingTimeout")}</AlertDescription>
			</Alert>
		);
	return (
		<div className="flex flex-col items-center gap-3 py-8 text-center">
			<Spinner />
			<p className="font-display text-lg">{t("billing.finishing")}</p>
			<p className="text-sm text-muted-foreground">
				{t("billing.finishingHint")}
			</p>
		</div>
	);
}
```

- [ ] **Step 4: Export the components from the barrel**

Add to `dashboard/src/features/billing/index.ts`:

```ts
export { CancelSubscriptionDialog } from "./components/CancelSubscriptionDialog";
export { CheckoutReturn } from "./components/CheckoutReturn";
export { PlanList } from "./components/PlanList";
export { SubscriptionCard } from "./components/SubscriptionCard";
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd dashboard && pnpm test src/features/billing && pnpm exec tsc --noEmit`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
cd dashboard
git add src/features/billing
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): checkout-return poller for the async webhook"
```

---

## Task 14: The real `/billing` page + nav + home tile

**Files:**
- Modify: `dashboard/src/routes/_authed/billing.tsx` (replace the `ModulePlaceholder`),
  `dashboard/src/features/shell/nav.ts`, `dashboard/src/routes/_authed/index.tsx`,
  `dashboard/src/routes/_authed/module-scaffolds.test.tsx` (drop `/billing` from the scaffold list),
  `dashboard/src/features/shell/nav.test.ts` (billing visibility)
- Test: `dashboard/src/routes/_authed/billing.test.tsx`

**Interfaces:**
- Consumes: `useMySubscription`, `PlanList`, `SubscriptionCard`, `CheckoutReturn`,
  `PageContainer`, `PageHeader`, `Spinner`, `Alert`.
- Produces: `BillingPage` — reads `?checkout=` from the router search params; renders
  `CheckoutReturn` while returning from Stripe, otherwise `SubscriptionCard` when a current
  subscription exists, otherwise `PlanList`. Nav shows `/billing` for parents **and** students
  (the spec's "adult students"; children see it too but the server rejects their checkout with a
  typed 403 — the honest, non-duplicated rule until an `is_child` flag exists on `/me`; log the
  refinement in `ISSUES.md`).

- [ ] **Step 1: Write the failing page test**

`dashboard/src/routes/_authed/billing.test.tsx` (follow the render approach in
`src/routes/_authed/availability.test.tsx` — read it first and reuse its router/query harness):

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { billingApi } from "@/features/billing/api";
import { BillingPage } from "./billing";

vi.mock("@/features/billing/api", () => ({
	billingApi: {
		listPlans: vi.fn(),
		createCheckout: vi.fn(),
		getMySubscription: vi.fn(),
		cancelSubscription: vi.fn(),
	},
}));

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("BillingPage", () => {
	beforeEach(() => vi.clearAllMocks());

	it("shows the plan list when there is no subscription", async () => {
		vi.mocked(billingApi.getMySubscription).mockResolvedValue({
			current: null,
			history: [],
		});
		vi.mocked(billingApi.listPlans).mockResolvedValue([
			{
				id: 1,
				plan_type: "family",
				sessions_per_cycle: 4,
				display_amount: 5000,
				currency: "usd",
			},
		]);
		render(<BillingPage checkout={undefined} />, { wrapper });
		expect(await screen.findByRole("button", { name: /subscribe/i })).toBeInTheDocument();
	});

	it("shows the subscription card when subscribed", async () => {
		vi.mocked(billingApi.getMySubscription).mockResolvedValue({
			current: {
				id: 1,
				plan_type: "family",
				sessions_per_cycle: 4,
				status: "active",
				current_period_end: "2030-01-01T00:00:00Z",
				cancel_at_period_end: false,
			},
			history: [],
		});
		render(<BillingPage checkout={undefined} />, { wrapper });
		expect(await screen.findByText(/current plan/i)).toBeInTheDocument();
	});

	it("shows the finishing-up state when returning from checkout", async () => {
		vi.mocked(billingApi.getMySubscription).mockResolvedValue({
			current: null,
			history: [],
		});
		render(<BillingPage checkout="success" />, { wrapper });
		expect(await screen.findByText(/finishing up/i)).toBeInTheDocument();
	});

	it("shows the cancelled notice when checkout was abandoned", async () => {
		vi.mocked(billingApi.getMySubscription).mockResolvedValue({
			current: null,
			history: [],
		});
		render(<BillingPage checkout="cancelled" />, { wrapper });
		expect(await screen.findByText(/checkout was cancelled/i)).toBeInTheDocument();
	});

	it("shows an error when the subscription fails to load", async () => {
		vi.mocked(billingApi.getMySubscription).mockRejectedValue(new Error("boom"));
		render(<BillingPage checkout={undefined} />, { wrapper });
		expect(await screen.findByRole("alert")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd dashboard && pnpm test src/routes/_authed/billing`
Expected: FAIL — `BillingPage` still renders the placeholder / doesn't accept `checkout`.

- [ ] **Step 3: Implement the page**

Replace `dashboard/src/routes/_authed/billing.tsx`:

```tsx
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useCallback } from "react";
import { useTranslation } from "react-i18next";
import {
	CheckoutReturn,
	PlanList,
	SubscriptionCard,
	useMySubscription,
} from "@/features/billing";
import { Alert, AlertDescription, PageContainer, PageHeader, Spinner } from "@/ui";

type CheckoutStatus = "success" | "cancelled" | undefined;

export function BillingPage({
	checkout,
	onClearCheckout,
}: {
	checkout: CheckoutStatus;
	onClearCheckout?: () => void;
}) {
	const { t } = useTranslation();
	const { data, isPending, isError } = useMySubscription();
	const handleSettled = useCallback(() => onClearCheckout?.(), [onClearCheckout]);

	return (
		<PageContainer>
			<PageHeader title={t("billing.title")} description={t("billing.subtitle")} />
			{checkout ? (
				<CheckoutReturn
					status={checkout === "success" ? "success" : "cancelled"}
					onSettled={handleSettled}
				/>
			) : isPending ? (
				<Spinner />
			) : isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("billing.plansError")}</AlertDescription>
				</Alert>
			) : data.current ? (
				<SubscriptionCard subscription={data.current} history={data.history} />
			) : (
				<PlanList />
			)}
		</PageContainer>
	);
}

function BillingRoute() {
	const { checkout } = Route.useSearch();
	const navigate = useNavigate();
	return (
		<BillingPage
			checkout={checkout}
			onClearCheckout={() => navigate({ to: "/billing", search: {}, replace: true })}
		/>
	);
}

export const Route = createFileRoute("/_authed/billing")({
	validateSearch: (search: Record<string, unknown>): { checkout?: "success" | "cancelled" } => {
		const value = search.checkout;
		return value === "success" || value === "cancelled" ? { checkout: value } : {};
	},
	component: BillingRoute,
});
```

Check `PageHeader`'s prop names in `src/ui/page-header.tsx` (it may be `subtitle`, not
`description`) and match them.

- [ ] **Step 4: Update nav, home tile, and the scaffold test**

In `dashboard/src/features/shell/nav.ts`, change the billing entry (billing is real now — remove
it from the scaffold NOTE's scope if the comment enumerates routes):

```ts
	{
		to: "/billing",
		labelKey: "nav.billing",
		icon: CreditCard,
		requiresAny: ["parent", "student"],
	},
```

In `dashboard/src/routes/_authed/index.tsx`, remove `"/billing"` from the `SOON` set and point its
description at the real copy:

```ts
	"/billing": "billing.subtitle",
```

In `dashboard/src/routes/_authed/module-scaffolds.test.tsx`, remove `/billing` from the list of
placeholder routes under test. Add to `dashboard/src/features/shell/nav.test.ts`:

```ts
it("shows billing to parents and students but not teachers", () => {
	const routes = (profiles: ProfileType[]) =>
		visibleNavItems(NAV_ITEMS, profiles).map((i) => i.to);
	expect(routes(["parent"])).toContain("/billing");
	expect(routes(["student"])).toContain("/billing");
	expect(routes(["teacher"])).not.toContain("/billing");
});
```

- [ ] **Step 5: Run the full dashboard gate**

Run: `cd dashboard && pnpm test && pnpm exec tsc --noEmit && pnpm exec biome check src`
Expected: everything green (the prior 260 + the new billing tests), tsc and biome clean.

- [ ] **Step 6: Commit and open the dashboard PR**

```bash
cd dashboard
git add src
PIP_CONFIG_FILE=/dev/null git commit -m "feat(billing): real /billing page replacing the scaffold placeholder"
git push -u origin feat/billing-subscriptions
gh pr create --base main --title "feat(billing): subscribe, view, and cancel a subscription (B1)" \
  --body "Frontend slice of docs/superpowers/specs/2026-07-09-billing-subscriptions-design.md."
```

---

## Task 15: Docs, runbook, and the meta PR

**Files:**
- Create: `docs/architecture/billing.md`, `docs/runbook/stripe-billing.md`
- Modify: `ISSUES.md`, `STATE.md`, submodule pointers (`backend`, `dashboard`)

**Interfaces:**
- Consumes: the merged submodule work.
- Produces: the meta-repo PR that closes the D9 paper trail for B1.

- [ ] **Step 1: Write the architecture doc**

`docs/architecture/billing.md`, following the shape of `docs/architecture/identity.md`: purpose;
the mermaid ER diagram from the spec; each model and what it is for; the public service API
(`list_active_plans`, `create_checkout`, `get_current_subscription`, `cancel_subscription`,
`handle_webhook`, `Capability`, `is_entitled_to`) with signatures; the entitlement rule stated as
a table (status × period-end × parent-plan ⇒ entitled?); the endpoint list; the provider
abstraction and how to add a second provider; the boundary rule (identity services only) and the
webhook CSRF exemption pointing at ADR-0025.

- [ ] **Step 2: Write the runbook**

`docs/runbook/stripe-billing.md` covering:
1. **Stripe test-mode setup:** create the two recurring Prices (Individual, Family) in the Stripe
   dashboard; copy each `price_…` id; create the matching `SubscriptionPlan` rows in Django admin
   with the same amount/currency.
2. **Env:** `DJANGO_STRIPE_SECRET_KEY`, `DJANGO_STRIPE_WEBHOOK_SECRET` — local `.env`, and on the
   staging VPS `.env.production` (managed on the box, not synced by CI — same as
   `DJANGO_FRONTEND_URL`).
3. **Webhook endpoint:** register `https://api-staging.kaleem.academy/api/v1/billing/webhook/` in
   Stripe for `checkout.session.completed`, `customer.subscription.updated`,
   `customer.subscription.deleted`, `invoice.paid`, `invoice.payment_failed`.
4. **Local development:** `stripe listen --forward-to
   http://api.kaleem.localhost/api/v1/billing/webhook/` and use the printed `whsec_…`.
5. **The manual staging test (D9):** log in as a parent → `/billing` → Subscribe → pay with
   `4242 4242 4242 4242`, any future expiry/CVC → return lands on "finishing up…" → page flips to
   the active subscription card → cancel → confirm the card reads "cancels on …" → verify in the
   Stripe dashboard that `cancel_at_period_end` is set.

- [ ] **Step 3: Log the follow-ups in `ISSUES.md`**

Append (one line each, matching the file's existing style):
- Billing e2e gap: the hosted-Stripe redirect can't run in Playwright; card→checkout→webhook is a
  manual staging test (`docs/runbook/stripe-billing.md`). Dashboard has no Playwright harness at
  all yet — D3's e2e requirement remains open repo-wide.
- `/billing` nav shows for every student; a linked child gets a server-side 403 at checkout rather
  than a hidden nav entry. Refine once `/me` exposes whether the student has a parent.
- Dunning UX beyond mirroring `past_due` (retry/notice flow) is deferred.
- Stripe billing portal / card-update UI deferred.
- Plan/Price creation is manual in Stripe; no programmatic sync (B1 scope).

- [ ] **Step 4: Bump the submodule pointers and update `STATE.md`**

After both submodule PRs merge to `main`:

```bash
cd /home/abdulkhalek/Projects/kaleem
git -C backend checkout main && git -C backend pull
git -C dashboard checkout main && git -C dashboard pull
git add backend dashboard
```

Update `STATE.md`: `current_phase: "B — Billing (B1 shipped, awaiting staging verification)"`,
`active_spec` → the billing spec, `active_branch` → this meta branch, and a new dated session
section summarising what shipped, what is deferred, and the manual Stripe staging test as the
remaining D9 step.

- [ ] **Step 5: Commit and open the meta PR**

```bash
cd /home/abdulkhalek/Projects/kaleem
git add docs ISSUES.md STATE.md backend dashboard
PIP_CONFIG_FILE=/dev/null git commit -m "docs(billing): ADR-0025, architecture doc, runbook + pointer bumps"
git push -u origin feat/billing-spec
gh pr create --base develop --title "feat(billing): Phase B B1 — subscriptions, entitlement, Stripe" \
  --body "Spec + plan + ADR-0025 + architecture doc + runbook; bumps backend and dashboard pointers to the merged B1 work."
```

- [ ] **Step 6: Definition of Done**

Run `/ship` and walk D9: spec closed (set `status: closed` + `closed:` date in the spec front
matter), plan done, backend + dashboard tests green, `lint-imports` green, coverage gate green,
manual browser test on staging per the runbook (Stripe test card), staging deploy via
`develop → master`, `docs/architecture/billing.md` written, journal entry for the week,
`STATE.md` updated.

---

## Self-Review

**Spec coverage**

| Spec requirement | Task |
| --- | --- |
| `SubscriptionPlan` / `BillingCustomer` / `Subscription` / `StripeEventLog` | 1 |
| `identity.services.get_parent_user_ids` | 2 |
| `PaymentProvider` protocol + provider selection | 3 |
| `StripeProvider`, nothing else imports `stripe` | 4 |
| `GET plans/` | 5 (service), 8 (endpoint) |
| `POST checkout/` incl. role fitness + already-subscribed 400 | 5, 8 |
| `POST webhook/` — signature auth, idempotency, 5 event types, unknown → 200 | 4, 6, 8 |
| `GET me/subscription/` (current + history) | 5, 8 |
| `POST me/subscription/cancel/` (cancel at period end) | 6, 8 |
| `Capability` + `is_entitled_to` incl. family inheritance | 7 |
| CSRF exemption documented in an ADR + inline comment | 8 |
| Import-linter contract for `billing` | 1 |
| Frontend `/billing` route, success/cancel return handling | 14 |
| `PlanList`, `CheckoutReturn`, `SubscriptionCard` + confirm dialog | 11, 13, 12 |
| `listPlans` / `createCheckout` / `getMySubscription` / `cancelSubscription` | 9 |
| en + ar, RTL, jest-axe, role-gated nav | 10, 11–14 |
| Test plan (happy path + every listed edge case) | 5, 6, 7, 8 |
| E2E limitation recorded in `ISSUES.md` | 15 |
| Manual staging test with test card `4242…` | 15 |

**Out-of-scope items confirmed absent from the plan:** session-pool consumption/quotas, teacher
payroll, free trial, refunds/proration, Stripe billing portal, dunning UX, live keys, programmatic
Price creation.

**Known judgement calls the implementer should not "fix" silently:**
1. `checkout.session.completed` sets `status=active` without a `current_period_end`;
   `customer.subscription.updated` / `invoice.paid` fill it in. Entitlement treats `active` alone as
   paid-through, so there is no gap.
2. `Subscription.current_period_end` is nullable for the same reason.
3. Nav shows `/billing` to all students; children are rejected server-side (Task 14 note, logged in
   ISSUES).
4. `is_entitled_to` ignores `capability` in B1 — the parameter exists so scheduling's call site
   never has to change when capabilities multiply.
