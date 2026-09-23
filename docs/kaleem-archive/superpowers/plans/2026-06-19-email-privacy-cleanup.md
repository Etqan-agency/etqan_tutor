# Email & privacy cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Outbound emails show "Kaleem"/correct domain (not `example.com`) and never echo personal data into bodies.

**Architecture:** All backend (`kaleem.identity`) + meta docs. Fix the allauth subject prefix in settings, fix the Django `Site` row via a data migration, override one allauth email-body template, and redact our own security-alert body. Spec: `docs/superpowers/specs/2026-06-19-email-privacy-cleanup-design.md`.

**Tech Stack:** Django 5, django-allauth, pytest-django (`mailoutbox`, locmem backend, eager Celery).

## Global Constraints

- 100% line + branch coverage (CI-enforced); ruff + mypy + import-linter green. No `print()`.
- Business logic stays in `services.py`; no cross-module model imports.
- `ACCOUNT_EMAIL_SUBJECT_PREFIX` value is exactly `"[Kaleem] "` (trailing space required).
- `Site` row: `name="Kaleem"`, `domain="kaleem.academy"`.
- Security/notification email bodies must not contain any email address other than implicitly the recipient's; detail lives behind auth at `{FRONTEND_URL}/account`.

---

### Task 1: Subject prefix + Site row (kill `example.com` in subject & body)

**Files:**
- Modify: `backend/config/settings/base.py` (ACCOUNT_ block, ~line 209-216)
- Modify: `backend/.env.example`
- Create: `backend/kaleem/identity/migrations/0003_set_site_name_domain.py`
- Test: `backend/kaleem/identity/tests/test_email_branding.py`

**Interfaces:**
- Consumes: allauth's `format_email_subject` (uses `ACCOUNT_EMAIL_SUBJECT_PREFIX`); `django.contrib.sites`.
- Produces: a configured `Site` and subject prefix relied on by Task 2's body test.

- [ ] **Step 1: Write the failing test**

```python
# backend/kaleem/identity/tests/test_email_branding.py
"""Outbound emails carry Kaleem branding, not the example.com placeholder."""

import pytest
from django.conf import settings
from django.contrib.sites.models import Site
from django.core.cache import cache
from rest_framework.test import APIClient

RESEND_URL = "/api/v1/identity/resend-verification/"


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture(autouse=True)
def _clear_throttle_cache():
    cache.clear()
    yield
    cache.clear()


def _register(api, email="ahmad@example.com"):
    return api.post(
        "/api/v1/identity/register/",
        {
            "full_name": "Ahmad Ali",
            "email": email,
            "password": "sup3r-secret-pw",
            "account_type": "student",
        },
        format="json",
    )


@pytest.mark.django_db
def test_site_is_kaleem():
    site = Site.objects.get(pk=settings.SITE_ID)
    assert site.name == "Kaleem"
    assert site.domain == "kaleem.academy"


@pytest.mark.django_db
def test_confirmation_subject_is_kaleem_branded(api, mailoutbox):
    _register(api)
    resp = api.post(RESEND_URL, {"email": "ahmad@example.com"}, format="json")
    assert resp.status_code == 200
    subject = mailoutbox[-1].subject
    assert subject.startswith("[Kaleem] ")
    assert "example.com" not in subject
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && pytest kaleem/identity/tests/test_email_branding.py -v`
Expected: FAIL — `test_site_is_kaleem` (Site is `example.com`), `test_confirmation_subject…` (subject is `[example.com] …`).

- [ ] **Step 3: Add the subject-prefix setting**

In `backend/config/settings/base.py`, in the `ACCOUNT_*` block (right after `ACCOUNT_EMAIL_VERIFICATION = "mandatory"`), add:

```python
# allauth defaults the subject prefix to "[{Site.name}] " (== "[example.com] ") when
# unset. Pin it so every transactional email is Kaleem-branded, env-independent.
ACCOUNT_EMAIL_SUBJECT_PREFIX = env("DJANGO_EMAIL_SUBJECT_PREFIX", default="[Kaleem] ")
```

- [ ] **Step 4: Document the env var**

In `backend/.env.example`, near the other `DJANGO_*` email vars, add:

```bash
# Subject prefix for transactional emails (trailing space kept). Default "[Kaleem] ".
DJANGO_EMAIL_SUBJECT_PREFIX="[Kaleem] "
```

- [ ] **Step 5: Create the Site data migration**

```python
# backend/kaleem/identity/migrations/0003_set_site_name_domain.py
"""Point the default Site at Kaleem so allauth emails stop saying example.com."""

from django.conf import settings
from django.db import migrations


def set_site(apps, schema_editor):
    Site = apps.get_model("sites", "Site")
    Site.objects.update_or_create(
        pk=settings.SITE_ID,
        defaults={"name": "Kaleem", "domain": "kaleem.academy"},
    )


def reset_site(apps, schema_editor):
    Site = apps.get_model("sites", "Site")
    Site.objects.filter(pk=settings.SITE_ID).update(
        name="example.com", domain="example.com"
    )


class Migration(migrations.Migration):
    dependencies = [
        ("identity", "0002_parentprofile_parentinvite_studentprofile_and_more"),
        ("sites", "0002_alter_domain_unique"),
    ]

    operations = [migrations.RunPython(set_site, reset_site)]
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd backend && pytest kaleem/identity/tests/test_email_branding.py -v`
Expected: PASS (both tests).

- [ ] **Step 7: Commit**

```bash
cd backend && git add config/settings/base.py .env.example kaleem/identity/migrations/0003_set_site_name_domain.py kaleem/identity/tests/test_email_branding.py
git commit -m "fix(email): brand subject prefix + Site so emails stop saying example.com"
```

---

### Task 2: Confirmation-email body override (no user-identifier echo)

**Files:**
- Create: `backend/kaleem/templates/account/email/email_confirmation_message.txt`
- Create: `backend/kaleem/templates/account/email/email_confirmation_signup_message.txt`
- Test: `backend/kaleem/identity/tests/test_email_branding.py` (add a test)

**Interfaces:**
- Consumes: allauth render context (`activate_url`, `current_site`) + the `Site`/prefix from Task 1.
- Produces: a confirmation body with no PII; relied on by no later task.

- [ ] **Step 1: Write the failing test**

Append to `backend/kaleem/identity/tests/test_email_branding.py`:

```python
@pytest.mark.django_db
def test_confirmation_body_has_no_pii_and_is_branded(api, mailoutbox):
    _register(api)
    api.post(RESEND_URL, {"email": "ahmad@example.com"}, format="json")
    body = mailoutbox[-1].body
    assert "Kaleem" in body
    assert "/verify-email?key=" in body  # the activate_url
    assert "ahmad@example.com" not in body  # no email echoed into the body
    assert "example.com" not in body  # no placeholder domain
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && pytest kaleem/identity/tests/test_email_branding.py::test_confirmation_body_has_no_pii_and_is_branded -v`
Expected: FAIL — allauth's default body echoes `user_display` (`ahmad@example.com`).

- [ ] **Step 3: Create the override templates**

```text
{# backend/kaleem/templates/account/email/email_confirmation_message.txt #}
{% extends "account/email/base_message.txt" %}
{% load i18n %}
{% block content %}{% autoescape off %}{% blocktranslate %}You requested to confirm this email address for your Kaleem account.

To confirm, follow this link:

{{ activate_url }}

If you did not request this, you can safely ignore this email.{% endblocktranslate %}{% endautoescape %}{% endblock content %}
```

```text
{# backend/kaleem/templates/account/email/email_confirmation_signup_message.txt #}
{% include "account/email/email_confirmation_message.txt" %}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && pytest kaleem/identity/tests/test_email_branding.py -v`
Expected: PASS (all three).

- [ ] **Step 5: Commit**

```bash
cd backend && git add kaleem/templates/account/email/ kaleem/identity/tests/test_email_branding.py
git commit -m "fix(email): override confirmation body to drop user-identifier echo"
```

---

### Task 3: Redact the security-alert body

**Files:**
- Modify: `backend/kaleem/identity/services.py` (`_send_email_security_alert` + callers)
- Modify: `backend/kaleem/identity/tests/test_email_management.py` (flip body assertion)

**Interfaces:**
- Consumes: `settings.FRONTEND_URL`.
- Produces: `_send_email_security_alert(*, to_email, action)` — `changed_email` removed.

- [ ] **Step 1: Update the existing test to assert redaction**

In `backend/kaleem/identity/tests/test_email_management.py`, replace the body assertion in `test_service_alerts_current_primary` (currently `assert "new@example.com" in mail.outbox[0].body`) with:

```python
        body = mail.outbox[0].body
        assert "new@example.com" not in body  # changed address is NOT disclosed
        assert "/account" in body  # points to the authenticated dashboard
```

And in `test_service_alerts_previous_primary` (after the existing recipient asserts) add:

```python
        body = mail.outbox[0].body
        assert "second@example.com" not in body
        assert "/account" in body
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && pytest kaleem/identity/tests/test_email_management.py -k "alerts_current_primary or alerts_previous_primary" -v`
Expected: FAIL — current body contains the address and no `/account` link.

- [ ] **Step 3: Redact `_send_email_security_alert` and drop the param**

In `backend/kaleem/identity/services.py`, replace the function body (lines ~199-225) with:

```python
def _send_email_security_alert(*, to_email: str, action: str) -> None:
    """Send a security alert to ``to_email`` describing the ``action`` taken.

    ``action`` must be ``"added"`` or ``"set_primary"``. The body never names the
    changed address — that is personal data and would disclose one address to the
    holder of another over plain email. Detail lives behind auth on the dashboard.
    See ADR-0023.
    """
    subject = "Security alert: a change was made to your kaleem account"
    review_url = f"{settings.FRONTEND_URL}/account"
    if action == "added":
        body = (
            "A new email address was added to your kaleem account and is pending "
            "verification. If this wasn't you, change your password immediately and "
            f"contact support. Review your account's email addresses at {review_url}."
        )
    else:  # set_primary
        body = (
            "The primary email address on your kaleem account was changed. If this "
            "wasn't you, change your password immediately and contact support. "
            f"Review your account at {review_url}."
        )
    send_email_message.delay(
        subject=subject,
        body=body,
        from_email=settings.DEFAULT_FROM_EMAIL,
        to=[to_email],
        alternatives=None,
    )
```

- [ ] **Step 4: Update both callers (drop `changed_email`)**

In `add_email_address` (~line 264), change the call to:

```python
    _send_email_security_alert(to_email=_current_primary_email(user), action="added")
```

In `set_primary_email` (~line 295), change the call to:

```python
        _send_email_security_alert(to_email=previous_primary, action="set_primary")
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && pytest kaleem/identity/tests/test_email_management.py -v`
Expected: PASS (all email-management tests, including the updated alert assertions).

- [ ] **Step 6: Full identity suite + lint**

Run: `cd backend && pytest kaleem/identity -q && ruff check . && ruff format --check . && mypy kaleem/identity && lint-imports`
Expected: all green; coverage 100%.

- [ ] **Step 7: Commit**

```bash
cd backend && git add kaleem/identity/services.py kaleem/identity/tests/test_email_management.py
git commit -m "fix(email): redact changed address from security-alert body (ADR-0023)"
```
