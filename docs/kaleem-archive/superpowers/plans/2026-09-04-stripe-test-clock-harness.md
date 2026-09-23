# Stripe Test-Clock Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove, against real Stripe, that a failing renewal on an already-`active` subscription drives kaleem from `ACTIVE` → `PAST_DUE` → `UNPAID`, and that entitlement survives the first and dies at the second.

**Architecture:** A pytest module marked `stripe_clock` and deselected from the default run. It stands up a real Django via pytest-django's `live_server`, points the **Stripe CLI** (`stripe listen`) at that server so Stripe's outbound connection substitutes for an inbound webhook Stripe cannot make to a CI runner, then drives a **Stripe test clock** through a renewal that fails. Runs nightly in its own workflow, not in the merge path.

**Tech Stack:** Python 3.13, pytest + pytest-django (`live_server`), `stripe>=15.5,<16.0`, the Stripe CLI, GitHub Actions, Postgres 18, Redis 8.

**Spec:** [docs/superpowers/specs/2026-09-04-stripe-test-clock-harness-design.md](../specs/2026-09-04-stripe-test-clock-harness-design.md)

## Global Constraints

- **Every product API route lives under `/api/v1/`** (ADR-0029). The webhook is `POST /api/v1/billing/webhook/`. This plan adds no routes.
- **Coverage is a ratchet floor** (ADR-0026): `fail_under = 97` in `backend/pyproject.toml`. This slice must leave it **unchanged** — these tests are excluded from the measured run, so they can neither raise nor flatter it.
- **Module boundaries** (D4): `billing` only. No new `import-linter` contracts, no cross-module model imports.
- **No `--no-verify`** (D5). Commit with `PIP_CONFIG_FILE=/dev/null` — the machine has a dead pip proxy in `pip.conf` that breaks the pre-commit hook otherwise.
- **Trunk-based** (ADR-0028): all work on `feat/stripe-test-clock-harness`, PR into `main` (backend submodule) and `master` (meta). Never commit to a trunk.
- **Stripe API version is pinned in both directions:** `DJANGO_STRIPE_API_VERSION`, defaulting to the installed SDK's `stripe.api_version`. Currently `2026-08-26.dahlia`.
- **Stripe test-mode card tokens used, verbatim:** `pm_card_visa` (succeeds), `pm_card_chargeCustomerFail` (attaches fine, fails at charge time).
- **Status values, verbatim** from `Subscription.Status`: `"active"`, `"past_due"`, `"unpaid"`, `"canceled"`, `"incomplete"`, `"incomplete_expired"`.

## Deviation from the spec — read before Task 1

The spec places the harness at `backend/kaleem/billing/tests/test_stripe_test_clock.py`. **Do not put it there.** `backend/kaleem/billing/tests/conftest.py` defines:

```python
@pytest.fixture(autouse=True)
def fake_provider(settings):
    settings.BILLING_PAYMENT_PROVIDER = "kaleem.billing.tests.fakes.FakePaymentProvider"
```

`autouse=True` applies to every test in that package. A harness placed there would run against `FakePaymentProvider` and pass while touching no Stripe at all — the precise failure this whole slice exists to prevent.

It goes in the top-level `backend/tests/stripe_clock/` package instead. That directory is already outside coverage measurement (`include = ["kaleem/**"]`, `omit = ["*/tests/*"]`), which independently satisfies the ratchet constraint. **Task 7 amends the spec to say so** — the spec is wrong on this point and gets corrected, not quietly ignored.

## File Structure

| File | Responsibility |
| --- | --- |
| `backend/pyproject.toml` (modify) | Register the `stripe_clock` marker; deselect it by default via `addopts`. |
| `backend/tests/stripe_clock/__init__.py` (create) | Package marker. |
| `backend/tests/stripe_clock/clock.py` (create) | Thin Stripe test-clock wrapper: create, advance-and-wait, delete. No assertions, no Django. |
| `backend/tests/stripe_clock/conftest.py` (create) | Fixtures: credential guard, the `stripe listen` subprocess, the plan/user rows, the clock lifecycle. |
| `backend/tests/stripe_clock/test_renewal_dunning.py` (create) | The scenario and its assertions. |
| `backend/tests/test_marker_deselection.py` (create) | Guard: proves the default run excludes `stripe_clock`. |
| `.github/workflows/stripe-clock.yml` (create, **meta repo**) | Nightly + `workflow_dispatch` job. |
| `docs/runbook/stripe-billing.md` (modify, **meta repo**) | The two required Stripe settings. |

Two repos are touched. Tasks 1–6 are **backend**; Task 7 is **backend + meta**.

---

### Task 1: Marker registration and default deselection

Nothing else can be written safely until the default `pytest` run is proven to skip these tests. If this is wrong, every later task risks a network call in the `backend-test` job.

**Files:**
- Modify: `backend/pyproject.toml` (`[tool.pytest.ini_options]`, currently lines 1–5 of that table)
- Test: `backend/tests/test_marker_deselection.py`

**Interfaces:**
- Consumes: nothing.
- Produces: the marker name `stripe_clock`, used by every later task as `@pytest.mark.stripe_clock`.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_marker_deselection.py`:

```python
"""The stripe_clock marker must be deselected by the default pytest run.

These tests hit live Stripe over the network. If the default run ever picks them
up, the backend-test CI job becomes dependent on a third party and the coverage
ratchet (ADR-0026) starts measuring network-dependent code.
"""

import subprocess
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parent.parent


def test_default_run_deselects_stripe_clock_tests():
    result = subprocess.run(
        [sys.executable, "-m", "pytest", "--collect-only", "-q", "tests/stripe_clock"],
        cwd=BACKEND_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert "deselected" in result.stdout, result.stdout
    assert "test_renewal_dunning" not in result.stdout, result.stdout


def test_marker_is_registered_so_it_cannot_be_a_typo():
    result = subprocess.run(
        [sys.executable, "-m", "pytest", "--markers"],
        cwd=BACKEND_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert "stripe_clock" in result.stdout, result.stdout
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd backend && pytest tests/test_marker_deselection.py -v
```

Expected: FAIL. `tests/stripe_clock` does not exist yet and the marker is unregistered.

- [ ] **Step 3: Create the package so the collection target exists**

```bash
mkdir -p backend/tests/stripe_clock && touch backend/tests/stripe_clock/__init__.py
```

Create `backend/tests/stripe_clock/test_renewal_dunning.py` as a placeholder that Task 4 replaces:

```python
import pytest


@pytest.mark.stripe_clock
def test_placeholder_replaced_in_task_4():
    raise AssertionError("Task 4 replaces this.")
```

- [ ] **Step 4: Register the marker and deselect it**

In `backend/pyproject.toml`, replace the `[tool.pytest.ini_options]` table with:

```toml
[tool.pytest.ini_options]
minversion = "6.0"
# `-m "not stripe_clock"` keeps the live-Stripe harness out of the default run and
# therefore out of the backend-test CI job. A command-line `-m` overrides this one
# (pytest takes the last `-m`), so `pytest -m stripe_clock` runs exactly what the
# nightly workflow runs. See docs/superpowers/specs/2026-09-04-stripe-test-clock-harness-design.md
addopts = "--ds=config.settings.test --reuse-db --import-mode=importlib -m 'not stripe_clock'"
python_files = ["tests.py", "test_*.py"]
markers = [
    "stripe_clock: drives live Stripe test mode over the network. Deselected by default; run with `pytest -m stripe_clock`.",
]
```

- [ ] **Step 5: Run the guard tests and watch them pass**

```bash
cd backend && pytest tests/test_marker_deselection.py -v
```

Expected: 2 passed.

- [ ] **Step 6: Prove the override works in the other direction**

```bash
cd backend && pytest -m stripe_clock --collect-only -q
```

Expected: `test_placeholder_replaced_in_task_4` **is** collected. If it is not, `addopts` is winning over the command line and the whole nightly workflow would silently run zero tests — stop and fix before continuing.

- [ ] **Step 7: Confirm the coverage floor is untouched**

```bash
cd backend && pytest --cov=kaleem --cov-report=term-missing -q 2>&1 | tail -5
```

Expected: PASS, `Required test coverage of 97% reached`. The percentage should be unchanged from `master`.

- [ ] **Step 8: Commit**

```bash
cd backend && git add pyproject.toml tests/test_marker_deselection.py tests/stripe_clock/
PIP_CONFIG_FILE=/dev/null git commit -m "test: register the stripe_clock marker and deselect it by default

The live-Stripe harness must never run in the backend-test job: it would
put a third party in the merge path and let network-dependent code count
toward the ADR-0026 coverage ratchet. A guard test asserts both the
deselection and the marker registration, so a typo'd marker name cannot
silently re-enable it."
```

---

### Task 2: The test-clock wrapper

A test clock advance is asynchronous — `advance` returns immediately with `status="advancing"` and the clock is unusable until it reports `ready`. Every later task depends on getting this polling right, so it is isolated here with no Django and no assertions.

**Files:**
- Create: `backend/tests/stripe_clock/clock.py`

**Interfaces:**
- Consumes: the `stripe_clock` marker from Task 1.
- Produces, used by Tasks 4–6:
  - `create_clock(frozen_time: datetime) -> str` (returns the clock id)
  - `advance_clock(clock_id: str, to_time: datetime, timeout_s: float = 300) -> None`
  - `delete_clock(clock_id: str) -> None`
  - `ClockTimeout(Exception)`

- [ ] **Step 1: Write the module**

Create `backend/tests/stripe_clock/clock.py`:

```python
"""A thin wrapper over Stripe test clocks.

Advancing a clock is asynchronous: `advance` returns a clock in `advancing` and
Stripe refuses further operations until it reports `ready`. Every caller needs the
same poll loop, so it lives here once.
"""

import datetime as dt
import time

import stripe

POLL_INTERVAL_S = 2.0


class ClockTimeout(Exception):
    """A clock did not reach `ready` in time."""


def create_clock(frozen_time: dt.datetime) -> str:
    clock = stripe.test_helpers.TestClock.create(
        frozen_time=int(frozen_time.timestamp()),
        name="kaleem-dunning-harness",
    )
    return clock.id


def advance_clock(clock_id: str, to_time: dt.datetime, timeout_s: float = 300) -> None:
    """Advance the clock and block until Stripe has finished processing it.

    Stripe generates the renewal invoice, attempts the charge and emits the
    resulting webhooks *during* the advance, so returning before `ready` would
    race every assertion that follows.
    """
    stripe.test_helpers.TestClock.advance(
        clock_id, frozen_time=int(to_time.timestamp())
    )
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        status = stripe.test_helpers.TestClock.retrieve(clock_id).status
        if status == "ready":
            return
        if status == "internal_failure":
            raise ClockTimeout(f"Clock {clock_id} failed internally at Stripe.")
        time.sleep(POLL_INTERVAL_S)
    raise ClockTimeout(
        f"Clock {clock_id} did not become ready within {timeout_s}s "
        f"(last status: {status})."
    )


def delete_clock(clock_id: str) -> None:
    """Delete the clock, which cascades to its customers and subscriptions.

    Called from a `finally`: a nightly job that leaked one customer per run would
    add 365 a year, which is how ISSUES.md accumulated its throwaway accounts.
    """
    try:
        stripe.test_helpers.TestClock.delete(clock_id)
    except stripe.InvalidRequestError:
        # Already gone. Teardown must not turn a green run red.
        pass
```

- [ ] **Step 2: Verify it imports and the SDK exposes what it uses**

```bash
cd backend && python -c "
from tests.stripe_clock.clock import create_clock, advance_clock, delete_clock, ClockTimeout
import stripe
assert hasattr(stripe.test_helpers, 'TestClock'), 'SDK has no TestClock'
for m in ('create', 'advance', 'retrieve', 'delete'):
    assert hasattr(stripe.test_helpers.TestClock, m), m
print('ok', stripe.VERSION)
"
```

Expected: `ok 15.x.x`. If `TestClock` is missing, the pinned SDK range is wrong — stop and report rather than working around it.

- [ ] **Step 3: Lint**

```bash
cd backend && ruff check tests/stripe_clock/ && ruff format --check tests/stripe_clock/
```

Expected: no findings. Fix with `ruff format tests/stripe_clock/` if the format check fails.

- [ ] **Step 4: Commit**

```bash
cd backend && git add tests/stripe_clock/clock.py
PIP_CONFIG_FILE=/dev/null git commit -m "test: add a Stripe test-clock wrapper

Advancing a clock is asynchronous and Stripe rejects operations until it
reports ready, so the poll loop lives in one place. Deleting the clock
cascades to its customers and subscriptions, which is the teardown."
```

---

### Task 3: Credentials guard, `stripe listen`, and the first real event

This is the task that proves the delivery mechanism. By the end, a real Stripe-signed event has passed through `verify_and_parse_webhook`.

**Files:**
- Create: `backend/tests/stripe_clock/conftest.py`

**Interfaces:**
- Consumes: `clock.create_clock` / `delete_clock` (Task 2).
- Produces, used by Tasks 4–6:
  - fixture `stripe_credentials` → `None`; fails the session fast if the key is missing
  - fixture `webhook_secret(live_server)` → `str` (the CLI's `whsec_…`), and sets `settings.STRIPE_WEBHOOK_SECRET`
  - fixture `harness_plan` → `SubscriptionPlan` (a row pointing at a real test-mode Price)
  - fixture `harness_user` → `User` with a `StudentProfile`
  - fixture `clock_id` → `str`, deleted on teardown

- [ ] **Step 1: Write the conftest**

Create `backend/tests/stripe_clock/conftest.py`:

```python
"""Fixtures for the live-Stripe dunning harness.

Note what is deliberately absent: the `fake_provider` autouse fixture from
`kaleem/billing/tests/conftest.py`. This package sits outside that one precisely
so the real StripeProvider is used — a harness silently running against the fake
would pass while proving nothing.
"""

import datetime as dt
import os
import re
import subprocess
import time

import pytest
import stripe
from django.conf import settings as django_settings

from kaleem.billing.models import SubscriptionPlan
from kaleem.identity.models import StudentProfile
from kaleem.identity.models import User
from tests.stripe_clock.clock import create_clock
from tests.stripe_clock.clock import delete_clock

# A real test-mode Price on the shared Stripe test account. Overridable so a
# developer can point the harness at their own account.
HARNESS_PRICE_ID = os.environ.get("STRIPE_CLOCK_PRICE_ID", "")
CLI_READY_TIMEOUT_S = 60
WHSEC_PATTERN = re.compile(r"(whsec_[A-Za-z0-9]+)")
# Verified against Stripe CLI 1.42.11: `listen` supports --api-key, --forward-to,
# --skip-verify and --print-secret. The secret comes from --print-secret (a
# deterministic one-shot) rather than from racing the forwarder's stdout; the
# forwarder's stdout is then read only to know when it is ready.
CLI_READY_MARKER = "Ready!"


@pytest.fixture(scope="session", autouse=True)
def stripe_credentials():
    """Fail fast and by name, rather than timing out twenty minutes in."""
    key = os.environ.get("DJANGO_STRIPE_SECRET_KEY", "")
    if not key:
        pytest.fail("DJANGO_STRIPE_SECRET_KEY is not set. The harness needs a Stripe test-mode secret key.")
    if not key.startswith("sk_test_"):
        pytest.fail("DJANGO_STRIPE_SECRET_KEY is not a test-mode key (expected an sk_test_ prefix). Refusing to run against live Stripe.")
    if not HARNESS_PRICE_ID:
        pytest.fail("STRIPE_CLOCK_PRICE_ID is not set. It must name a real recurring monthly Price in Stripe test mode.")
    stripe.api_key = key
    stripe.api_version = django_settings.STRIPE_API_VERSION


@pytest.fixture
def webhook_secret(live_server, settings):
    """Run `stripe listen`, forwarding Stripe's events to the live test server.

    Stripe cannot make an inbound connection to a CI runner, so the CLI holds an
    outbound one and forwards. It signs each forwarded request with its own
    secret, so signature verification is genuinely exercised rather than stubbed.
    """
    api_key = os.environ["DJANGO_STRIPE_SECRET_KEY"]
    target = f"{live_server.url}/api/v1/billing/webhook/"

    # One-shot, deterministic: no racing the forwarder's stdout for the secret.
    printed = subprocess.run(
        ["stripe", "listen", "--api-key", api_key, "--print-secret"],
        capture_output=True,
        text=True,
        check=False,
        timeout=CLI_READY_TIMEOUT_S,
    )
    match = WHSEC_PATTERN.search(printed.stdout)
    if match is None:
        pytest.fail(
            "`stripe listen --print-secret` produced no whsec_ value. "
            f"stdout={printed.stdout!r} stderr={printed.stderr!r}"
        )
    secret = match.group(1)
    settings.STRIPE_WEBHOOK_SECRET = secret

    process = subprocess.Popen(
        [
            "stripe", "listen",
            "--api-key", api_key,
            "--forward-to", target,
            "--skip-verify",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    # Read stdout only to learn when the forwarder is actually up. Starting the
    # scenario before this point drops the first events on the floor.
    deadline = time.monotonic() + CLI_READY_TIMEOUT_S
    ready = False
    while time.monotonic() < deadline:
        line = process.stdout.readline()
        if not line:
            break
        if CLI_READY_MARKER in line:
            ready = True
            break
    if not ready:
        process.kill()
        pytest.fail(
            f"`stripe listen` never reported {CLI_READY_MARKER!r} within "
            f"{CLI_READY_TIMEOUT_S}s. Is the CLI installed and the key valid?"
        )

    yield secret

    process.terminate()
    process.wait(timeout=10)


@pytest.fixture
def harness_plan(db):
    return SubscriptionPlan.objects.create(
        plan_type=SubscriptionPlan.PlanType.INDIVIDUAL,
        sessions_per_cycle=4,
        stripe_price_id=HARNESS_PRICE_ID,
        display_amount=2000,
        currency="usd",
    )


@pytest.fixture
def harness_user(db):
    user = User.objects.create_user(
        email="dunning.harness@example.com", password="pw12345!"
    )
    StudentProfile.objects.create(user=user)
    return user


@pytest.fixture
def clock_id():
    start = dt.datetime.now(tz=dt.UTC) - dt.timedelta(days=1)
    created = create_clock(start)
    try:
        yield created
    finally:
        delete_clock(created)
```

- [ ] **Step 2: Install the Stripe CLI locally if it is absent**

```bash
stripe version || {
  curl -fsSL https://packages.stripe.dev/api/security/keypair/stripe-cli-gpg/public \
    | gpg --dearmor | sudo tee /usr/share/keyrings/stripe.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/stripe.gpg] https://packages.stripe.dev/stripe-cli-debian-local stable main" \
    | sudo tee /etc/apt/sources.list.d/stripe.list
  sudo apt update && sudo apt install -y stripe
}
```

- [ ] **Step 3: Write a smoke test that proves an event arrives**

Append to `backend/tests/stripe_clock/test_renewal_dunning.py` (replacing the Task 1 placeholder):

```python
import pytest
import stripe
from django.conf import settings

from kaleem.billing.models import StripeEventLog


@pytest.mark.stripe_clock
@pytest.mark.django_db(transaction=True)
def test_a_real_stripe_event_reaches_the_webhook_view(webhook_secret, harness_user):
    """The delivery mechanism itself: Stripe -> CLI -> Django, real signature.

    Asserts on StripeEventLog rather than on a Subscription: this event is about
    nothing we own, so the point is only that a signed payload was accepted.
    """
    before = StripeEventLog.objects.count()
    stripe.Customer.create(email="delivery.probe@example.com")
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if StripeEventLog.objects.count() > before:
            return
        time.sleep(1)
    pytest.fail("No Stripe event reached the webhook view within 60s.")


@pytest.mark.stripe_clock
@pytest.mark.django_db(transaction=True)
def test_forwarded_events_match_our_pinned_api_version(webhook_secret, harness_user):
    """`stripe listen` forwards at the ACCOUNT default version, not our pin.

    ISSUES.md records the SDK default moving between two deploys on the same day
    (2026-07-29.dahlia -> 2026-08-26.dahlia) because requirements/base.txt allows
    stripe>=15.5,<16.0. Our payload parsers carry basil-vs-legacy fallbacks written
    for exactly this. Asserting it here turns a silent reshape into a red nightly.
    """
    account_version = stripe.Account.retrieve().get("api_version") or stripe.api_version
    assert account_version == settings.STRIPE_API_VERSION, (
        f"Stripe account default API version is {account_version} but "
        f"DJANGO_STRIPE_API_VERSION is {settings.STRIPE_API_VERSION}. "
        "Inbound payload shapes have drifted from what the parsers expect — "
        "see docs/runbook/stripe-billing.md."
    )
```

Add `import time` to the module's imports.

- [ ] **Step 4: Run it**

```bash
cd backend && DJANGO_STRIPE_SECRET_KEY=sk_test_... STRIPE_CLOCK_PRICE_ID=price_... \
  pytest -m stripe_clock tests/stripe_clock/ -v
```

Expected: both pass. If the first fails, the CLI is not forwarding — check the printed target URL and that `live_server` is reachable. If the second fails, that is a **real finding**, not a harness bug: report the version mismatch rather than editing the assertion.

- [ ] **Step 5: Confirm the default run still ignores all of it**

```bash
cd backend && pytest -q 2>&1 | tail -3
```

Expected: the same pass count as `master`, with `deselected` in the summary. No network access.

- [ ] **Step 6: Commit**

```bash
cd backend && git add tests/stripe_clock/
PIP_CONFIG_FILE=/dev/null git commit -m "test: deliver real Stripe events to a live test server

Stripe cannot reach a CI runner, so \`stripe listen\` holds an outbound
connection and forwards to pytest-django's live_server. The CLI signs with
its own secret, so signature verification is exercised for real.

Also asserts the account's default API version matches our pin: the CLI
forwards at the account default, and ISSUES.md records that default moving
between two deploys on one day."
```

---

### Task 4: Reach `ACTIVE` on a test-clock subscription

**Files:**
- Modify: `backend/tests/stripe_clock/test_renewal_dunning.py`

**Interfaces:**
- Consumes: `webhook_secret`, `harness_plan`, `harness_user`, `clock_id` (Task 3); `advance_clock` (Task 2).
- Produces, used by Tasks 5–6:
  - `wait_for_status(user, expected: str, timeout_s: float = 180) -> Subscription`
  - `subscribe_on_clock(clock_id, user, plan) -> tuple[str, str]` returning `(customer_id, subscription_id)`

- [ ] **Step 1: Write the helpers and the failing test**

Add to `backend/tests/stripe_clock/test_renewal_dunning.py`:

```python
from kaleem.billing.models import Subscription


def wait_for_status(user, expected: str, timeout_s: float = 180) -> Subscription:
    """Block until our row reaches `expected`, or fail naming what it actually is.

    Webhooks arrive asynchronously through the CLI, so every status assertion is a
    poll. Reporting the observed status matters: "expected unpaid, got past_due"
    tells you Stripe's dunning setting is wrong; a bare timeout tells you nothing.
    """
    deadline = time.monotonic() + timeout_s
    observed = None
    while time.monotonic() < deadline:
        subscription = Subscription.objects.filter(user=user).order_by("-id").first()
        if subscription is not None:
            subscription.refresh_from_db()
            observed = subscription.status
            if observed == expected:
                return subscription
        time.sleep(2)
    raise AssertionError(
        f"Subscription for {user.email} never reached {expected!r} within "
        f"{timeout_s}s (last observed: {observed!r})."
    )


def subscribe_on_clock(clock_id: str, user, plan) -> tuple[str, str]:
    """Create a paying customer and subscription bound to the test clock.

    The metadata is byte-for-byte what `StripeProvider.create_checkout_session`
    writes, because that is what `verify_and_parse_webhook` reads back to resolve
    an event to our user and plan.
    """
    customer = stripe.Customer.create(
        email=user.email,
        test_clock=clock_id,
        metadata={"user_id": str(user.id), "plan_id": str(plan.id)},
    )
    payment_method = stripe.PaymentMethod.attach("pm_card_visa", customer=customer.id)
    stripe.Customer.modify(
        customer.id,
        invoice_settings={"default_payment_method": payment_method.id},
    )
    subscription = stripe.Subscription.create(
        customer=customer.id,
        items=[{"price": plan.stripe_price_id}],
        metadata={"user_id": str(user.id), "plan_id": str(plan.id)},
    )
    return customer.id, subscription.id


@pytest.mark.stripe_clock
@pytest.mark.django_db(transaction=True)
def test_a_paid_subscription_on_a_test_clock_reaches_active(
    webhook_secret, harness_plan, harness_user, clock_id
):
    _, subscription_id = subscribe_on_clock(clock_id, harness_user, harness_plan)

    subscription = wait_for_status(harness_user, Subscription.Status.ACTIVE)

    assert subscription.stripe_subscription_id == subscription_id
    assert subscription.plan_id == harness_plan.id
    assert subscription.current_period_end is not None, (
        "current_period_end was never mirrored. The renewal advance in Task 5 "
        "targets this value, so the rest of the harness cannot run without it."
    )
```

- [ ] **Step 2: Run it**

```bash
cd backend && DJANGO_STRIPE_SECRET_KEY=sk_test_... STRIPE_CLOCK_PRICE_ID=price_... \
  pytest -m stripe_clock tests/stripe_clock/ -k active -v
```

Expected: PASS within ~60s. A failure at `current_period_end is not None` means the basil-vs-legacy fallback in `_subscription_period_end` is not matching this API version — a real finding.

- [ ] **Step 3: Confirm the clock was cleaned up**

```bash
stripe test_helpers test_clocks list --api-key sk_test_... | head -20
```

Expected: no `kaleem-dunning-harness` clock remains.

- [ ] **Step 4: Commit**

```bash
cd backend && git add tests/stripe_clock/test_renewal_dunning.py
PIP_CONFIG_FILE=/dev/null git commit -m "test: reach ACTIVE on a test-clock subscription

Sets up via the Stripe API rather than the hosted checkout, which cannot be
automated. The metadata matches what create_checkout_session writes, since
that is what the webhook parser reads back to resolve the user and plan."
```

---

### Task 5: A failing renewal drives `PAST_DUE`, and entitlement survives

**Files:**
- Modify: `backend/tests/stripe_clock/test_renewal_dunning.py`

**Interfaces:**
- Consumes: `subscribe_on_clock`, `wait_for_status` (Task 4); `advance_clock` (Task 2).
- Produces: `break_the_card(customer_id) -> None`, used by Task 6's shared setup.

- [ ] **Step 1: Write the failing test**

Add:

```python
import datetime as dt

from kaleem.billing.services import Capability
from kaleem.billing.services import is_entitled_to


def break_the_card(customer_id: str) -> None:
    """Swap in a card that fails at charge time.

    Deliberately done AFTER the subscription is active. A card that fails from the
    start never produces an active subscription at all — that is the checkout
    decline path, already verified manually on 2026-09-03. `past_due` arises only
    from a renewal failing on a subscription that is already active: the card that
    worked in March and expired in April.
    """
    payment_method = stripe.PaymentMethod.attach(
        "pm_card_chargeCustomerFail", customer=customer_id
    )
    stripe.Customer.modify(
        customer_id, invoice_settings={"default_payment_method": payment_method.id}
    )


@pytest.mark.stripe_clock
@pytest.mark.django_db(transaction=True)
def test_a_failed_renewal_drives_past_due_and_keeps_entitlement(
    webhook_secret, harness_plan, harness_user, clock_id
):
    customer_id, _ = subscribe_on_clock(clock_id, harness_user, harness_plan)
    active = wait_for_status(harness_user, Subscription.Status.ACTIVE)

    break_the_card(customer_id)
    advance_clock(clock_id, active.current_period_end + dt.timedelta(hours=1))

    wait_for_status(harness_user, Subscription.Status.PAST_DUE)

    # The half that matters. past_due keeps full access by design (OQ-B2-1), and
    # B1 stated the opposite in four places for eight weeks before B2's R8
    # reversed it. Asserting only the status would pass with the rule inverted.
    assert is_entitled_to(harness_user, Capability.BOOK_SESSION) is True, (
        "past_due must keep entitlement (OQ-B2-1). Stripe is still retrying; "
        "cutting access on the first decline punishes a paying customer."
    )
```

Add `from tests.stripe_clock.clock import advance_clock` to the imports.

- [ ] **Step 2: Run it**

```bash
cd backend && DJANGO_STRIPE_SECRET_KEY=sk_test_... STRIPE_CLOCK_PRICE_ID=price_... \
  pytest -m stripe_clock tests/stripe_clock/ -k past_due -v
```

Expected: PASS in ~2–3 minutes (the advance is the slow part).

- [ ] **Step 3: Commit**

```bash
cd backend && git add tests/stripe_clock/test_renewal_dunning.py
PIP_CONFIG_FILE=/dev/null git commit -m "test: a failed renewal drives PAST_DUE with entitlement intact

The card is broken only after the subscription is active — past_due arises
from a renewal failing on an already-active subscription, not from a decline
at checkout. Asserts entitlement survives (OQ-B2-1), which is the half a
status-only assertion would miss."
```

---

### Task 6: Exhausted retries drive `UNPAID`, and entitlement stops

The reason the whole slice exists. `unpaid` is the only status that revokes access and it has never been observed.

**Files:**
- Modify: `backend/tests/stripe_clock/test_renewal_dunning.py`

**Interfaces:**
- Consumes: everything from Tasks 2–5.
- Produces: nothing downstream.

- [ ] **Step 1: Write the failing test**

Add:

```python
# Stripe's Smart Retries schedule spans roughly two to three weeks and Stripe may
# tune it, so the harness advances in steps and polls rather than hardcoding the
# attempt times. The cap is generous; exceeding it means the account's dunning
# setting is wrong, not that the schedule moved.
DUNNING_STEP = dt.timedelta(days=2)
DUNNING_MAX_STEPS = 16


@pytest.mark.stripe_clock
@pytest.mark.django_db(transaction=True)
def test_exhausted_retries_drive_unpaid_and_revoke_entitlement(
    webhook_secret, harness_plan, harness_user, clock_id
):
    customer_id, _ = subscribe_on_clock(clock_id, harness_user, harness_plan)
    active = wait_for_status(harness_user, Subscription.Status.ACTIVE)

    break_the_card(customer_id)
    advance_clock(clock_id, active.current_period_end + dt.timedelta(hours=1))
    wait_for_status(harness_user, Subscription.Status.PAST_DUE)

    now = active.current_period_end + dt.timedelta(hours=1)
    for _ in range(DUNNING_MAX_STEPS):
        subscription = Subscription.objects.filter(user=harness_user).order_by("-id").first()
        subscription.refresh_from_db()
        if subscription.status == Subscription.Status.UNPAID:
            break
        now = now + DUNNING_STEP
        advance_clock(clock_id, now)
        time.sleep(5)
    else:
        raise AssertionError(
            "The subscription never reached `unpaid` after "
            f"{DUNNING_MAX_STEPS * DUNNING_STEP.days} simulated days. The usual "
            "cause is Stripe's dunning setting: Settings -> Subscriptions -> "
            "'manage failed payments' must be set to MARK SUBSCRIPTION AS UNPAID. "
            "If it is set to cancel, or to leave the subscription past_due, "
            "`unpaid` is unreachable and this harness cannot pass. "
            "See docs/runbook/stripe-billing.md."
        )

    wait_for_status(harness_user, Subscription.Status.UNPAID)

    assert is_entitled_to(harness_user, Capability.BOOK_SESSION) is False, (
        "unpaid must revoke entitlement. This is the transition the whole "
        "harness exists to observe: past_due keeps access, unpaid stops it."
    )
```

- [ ] **Step 2: Run the full harness end to end**

```bash
cd backend && DJANGO_STRIPE_SECRET_KEY=sk_test_... STRIPE_CLOCK_PRICE_ID=price_... \
  pytest -m stripe_clock tests/stripe_clock/ -v
```

Expected: all pass, total ~5–10 minutes. If the `else` branch fires, apply the Stripe dunning setting it names before touching the test.

- [ ] **Step 3: The mutation check — prove the harness can fail**

ADR-0027's precedent: prove a harness, do not merely run it. Temporarily break `backend/kaleem/billing/services.py:633`:

```python
def _apply_invoice_payment_failed(event: WebhookEvent) -> None:
    _apply_to_existing(event, status=Subscription.Status.ACTIVE)  # MUTATION
```

Run:

```bash
cd backend && DJANGO_STRIPE_SECRET_KEY=sk_test_... STRIPE_CLOCK_PRICE_ID=price_... \
  pytest -m stripe_clock tests/stripe_clock/ -k past_due -v
```

Expected: **FAIL** with "never reached 'past_due' within 180s (last observed: 'active')". A green run here invalidates the entire slice — stop and report.

- [ ] **Step 4: Revert the mutation**

```bash
cd backend && git checkout kaleem/billing/services.py && git diff --stat
```

Expected: no diff in `services.py`. **Do not skip this step.**

- [ ] **Step 5: Confirm no Stripe objects leaked**

```bash
stripe test_helpers test_clocks list --api-key sk_test_... | grep -c kaleem-dunning-harness || echo "0 — clean"
```

Expected: `0 — clean`.

- [ ] **Step 6: Commit**

```bash
cd backend && git add tests/stripe_clock/test_renewal_dunning.py
PIP_CONFIG_FILE=/dev/null git commit -m "test: exhausted retries drive UNPAID and revoke entitlement

The transition the harness exists for: past_due keeps access, unpaid stops
it, and unpaid is reachable only through a failing renewal. Advances in
steps and polls rather than hardcoding Stripe's retry schedule, and the
timeout message names the dunning setting that is the usual cause."
```

---

### Task 7: Nightly workflow, runbook, and the spec correction

**Files:**
- Create: `.github/workflows/stripe-clock.yml` (**meta repo**)
- Modify: `docs/runbook/stripe-billing.md` (**meta repo**)
- Modify: `docs/superpowers/specs/2026-09-04-stripe-test-clock-harness-design.md` (**meta repo**)
- Modify: `ISSUES.md`, `STATE.md`, `CLAUDE.md` (**meta repo**)

**Interfaces:**
- Consumes: the `stripe_clock` marker and `pytest -m stripe_clock` invocation from Tasks 1–6.
- Produces: nothing downstream.

- [ ] **Step 1: Open the backend PR first**

The workflow references code that must already be on the backend trunk.

```bash
cd backend && git push -u origin feat/stripe-test-clock-harness
gh pr create --base main --title "test: Stripe test-clock harness for the past_due -> unpaid renewal path" \
  --body "Implements docs/superpowers/specs/2026-09-04-stripe-test-clock-harness-design.md. Deselected from the default run, so backend-test and the ADR-0026 coverage floor are unchanged. Mutation-checked: breaking _apply_invoice_payment_failed turns the harness red."
```

Wait for green CI, then merge with `gh pr merge --merge --delete-branch`.

- [ ] **Step 2: Add the required repo secrets**

In the **meta** repo settings → Secrets and variables → Actions:
- `STRIPE_TEST_SECRET_KEY` — the `sk_test_…` key
- `STRIPE_CLOCK_PRICE_ID` — the recurring monthly test-mode Price id

- [ ] **Step 3: Write the workflow**

Create `.github/workflows/stripe-clock.yml`:

```yaml
name: Stripe test clock

# Nightly, not per PR, and deliberately NOT in deploy-staging's `needs:`.
# Three reasons, recorded in the spec: test clocks are account-scoped so parallel
# PRs would collide; forked PRs cannot read secrets, and ISSUES.md already carries
# an entry about a skipped job looking like success; and a Stripe outage must not
# block every merge. The cost is that a renewal-path regression is caught within
# 24h rather than before merge — the right trade for drift in an external payload
# shape, the wrong one for anything we author. A red run here is a real failure.
on:
  schedule:
    - cron: "17 3 * * *"
  workflow_dispatch:

concurrency:
  group: stripe-clock
  cancel-in-progress: false

jobs:
  dunning:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    services:
      postgres:
        image: postgres:18-alpine
        env:
          POSTGRES_DB: kaleem_clock
          POSTGRES_USER: kaleem
          POSTGRES_PASSWORD: kaleem
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      redis:
        image: redis:8-alpine
        ports:
          - 6379:6379
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    defaults:
      run:
        working-directory: backend
    env:
      DATABASE_URL: postgres://kaleem:kaleem@localhost:5432/kaleem_clock
      CELERY_BROKER_URL: redis://localhost:6379/0
      DJANGO_SETTINGS_MODULE: config.settings.test
      DJANGO_STRIPE_SECRET_KEY: ${{ secrets.STRIPE_TEST_SECRET_KEY }}
      STRIPE_CLOCK_PRICE_ID: ${{ secrets.STRIPE_CLOCK_PRICE_ID }}
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
          token: ${{ secrets.SUBMODULE_TOKEN }}
      - uses: actions/setup-python@v5
        with:
          python-version: "3.13"
      - name: Install dependencies
        run: pip install -r requirements/local.txt
      - name: Install the Stripe CLI
        run: |
          curl -fsSL https://packages.stripe.dev/api/security/keypair/stripe-cli-gpg/public \
            | gpg --dearmor | sudo tee /usr/share/keyrings/stripe.gpg >/dev/null
          echo "deb [signed-by=/usr/share/keyrings/stripe.gpg] https://packages.stripe.dev/stripe-cli-debian-local stable main" \
            | sudo tee /etc/apt/sources.list.d/stripe.list
          sudo apt-get update && sudo apt-get install -y stripe
          stripe version
      - name: Migrate
        run: python manage.py migrate --noinput
      - name: Run the dunning harness
        run: pytest -m stripe_clock tests/stripe_clock/ -v
```

- [ ] **Step 4: Trigger it manually and watch it pass**

```bash
gh workflow run stripe-clock.yml
gh run watch "$(gh run list --workflow=stripe-clock.yml --limit 1 --json databaseId -q '.[0].databaseId')"
```

Expected: green in under 30 minutes. This is the first proof it works on a runner rather than a dev box.

- [ ] **Step 5: Record the two Stripe settings in the runbook**

Append to `docs/runbook/stripe-billing.md`:

```markdown
## Required settings for the dunning harness

Two account-level settings the nightly `stripe-clock` workflow depends on and
cannot create for itself. An environment missing either produces a harness that
hangs or passes while testing nothing.

1. **Settings → Subscriptions → "manage failed payments" must be set to
   *mark the subscription as unpaid*** after retries are exhausted. The
   alternatives (cancel, or leave it `past_due`) make `unpaid` unreachable — and
   `unpaid` is the only status that revokes entitlement. The harness names this
   setting in its timeout message, so the failure diagnoses itself.
2. **A recurring monthly Price in test mode**, its id stored as the
   `STRIPE_CLOCK_PRICE_ID` repo secret, with `STRIPE_TEST_SECRET_KEY` alongside it.

The harness shares the staging Stripe test account. Its objects are bound to a
test clock and deleted on teardown, so they cannot be confused with staging data.
```

- [ ] **Step 6: Correct the spec's file path**

In `docs/superpowers/specs/2026-09-04-stripe-test-clock-harness-design.md`, in the *Placement* section, replace the `kaleem/billing/tests/test_stripe_test_clock.py` path with `backend/tests/stripe_clock/`, and add:

```markdown
> **Corrected during implementation (2026-09-04).** This spec originally placed the
> harness in `kaleem/billing/tests/`. That package's `conftest.py` has an
> `autouse=True` fixture swapping in `FakePaymentProvider`, so a harness placed
> there would have run against the fake and passed while touching no Stripe at all
> — the exact failure this slice exists to prevent. It lives in the top-level
> `backend/tests/stripe_clock/` instead, which is also already outside coverage
> measurement (`include = ["kaleem/**"]`).
```

- [ ] **Step 7: Update the D3 table, ISSUES.md and STATE.md**

In `CLAUDE.md`, add a row to the D3 e2e table:

```markdown
| `billing` — dunning | ✅ nightly | `past_due` → `unpaid` via Stripe test clocks; not in the merge path (ADR-0027 precedent, own workflow) |
```

In `ISSUES.md`, **delete** the "**The `past_due` / dunning path has never been exercised end to end**" entry under *Blocks a phase close* — resolved entries are deleted, not struck through.

In `STATE.md`, set `active_spec` to `None`, and note Phase B's gate is closed.

- [ ] **Step 8: Bump the backend submodule pointer and open the meta PR**

```bash
cd /home/abdulkhalek/Projects/kaleem
git add backend .github/workflows/stripe-clock.yml docs/ ISSUES.md STATE.md CLAUDE.md
PIP_CONFIG_FILE=/dev/null git commit -m "ci: run the Stripe dunning harness nightly

Closes the last Phase-B gate. The past_due -> unpaid renewal path is now
exercised against real Stripe every night: test clocks advance a live
test-mode subscription through a failing renewal, and stripe listen
forwards the resulting events to a real Django.

Nightly and non-gating by design — test clocks are account-scoped, forked
PRs cannot read secrets, and a Stripe outage must not block every merge.
A red run is a real failure, not noise to mute."
git push -u origin feat/stripe-test-clock-harness
gh pr create --base master --title "ci: run the Stripe dunning harness nightly"
```

**Merge with `--merge`, never `--squash`** — this PR carries a submodule pointer, and squashing is what used to drop those silently (ADR-0028).

---

## Self-Review

**Spec coverage.** Every section maps to a task: delivery → Task 3; placement/marker → Task 1; the six-step scenario → Tasks 4–6 (step 6, teardown, is the `clock_id` fixture's `finally` plus verification steps in Tasks 4 and 6); required Stripe config → Task 7 step 5 and the Task 6 timeout message; the API-version assertion → Task 3; cadence/non-gating → Task 7 step 3; the mutation check → Task 6 step 3. Out-of-scope items generate no tasks, correctly.

**One deliberate deviation,** flagged at the top and corrected in the spec itself in Task 7 step 6: the file path moves out of `kaleem/billing/tests/` because of the `autouse` fake-provider fixture.

**Type consistency.** `wait_for_status`, `subscribe_on_clock`, `break_the_card`, `advance_clock`, `create_clock`, `delete_clock`, `ClockTimeout` are each defined once and used with matching signatures. Status values use `Subscription.Status.*` throughout rather than string literals. `Capability.BOOK_SESSION` and `is_entitled_to` match `kaleem/billing/services.py:981,1013`.

**Known gaps, stated rather than hidden.** `STRIPE_CLOCK_PRICE_ID` must name a Price that exists before Task 3 runs; Task 3's credential guard fails by name if it does not. Stripe may retune Smart Retries — hence stepping and polling rather than a hardcoded schedule, with a 32-simulated-day cap whose failure message names the likely cause.
