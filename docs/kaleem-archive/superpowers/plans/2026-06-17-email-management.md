# Email-Address Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user hold multiple email addresses — adding one starts it unverified and leaves every existing verified address fully working — and change their login identity safely via add → verify → set-primary.

**Architecture:** All logic lives in `identity/services.py` (the module's only public API); thin DRF `APIView`s wrap it. We reuse allauth's `account.EmailAddress` (no new tables) and the existing confirm-by-key/resend endpoints. `User.email` stays in sync with the primary `EmailAddress` via allauth's `set_as_primary()`. The insecure `PATCH /me/ {email}` path is removed.

**Tech Stack:** Django, django-allauth, Django REST Framework, pytest, Celery (existing `platform.tasks.send_email_message`).

## Global Constraints

- All work happens in the **`backend` submodule** (Django project rooted at `backend/kaleem/`). Branch `feat/<name>` off `main` (submodules use feat→main; only meta has `develop`).
- **TDD**: failing test first, then minimal code. Target ≥80% coverage on `services.py`.
- **Module boundary**: identity code may import `kaleem.platform.*` but no other module. All inter-module entry is via `identity/services.py`. `import-linter` runs in CI.
- **Typed errors only**: raise `kaleem.platform.exceptions.ValidationError(message, field=...)` / `NotFoundError(resource, id)`. Never bare `Exception`. The platform DRF handler maps `ValidationError`→400 (body `{field: [message]}` if `field` set, else `{"detail": message}`) and `NotFoundError`→404.
- **No `--no-verify`.** Commit with `PIP_CONFIG_FILE=/dev/null` prefixed (dead pip proxy breaks pre-commit otherwise).
- API base path: `/api/v1/identity/`. All endpoints in this plan require an authenticated session + CSRF.
- Commit message footer on every commit:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

## File Structure

- `backend/kaleem/identity/services.py` — add `list_email_addresses`, `add_email_address`, `set_primary_email`, `remove_email_address`, and a private `_send_email_security_alert` helper.
- `backend/kaleem/identity/api/serializers.py` — add `AddEmailSerializer`, `SetPrimaryEmailSerializer`, `EmailAddressSerializer`; remove the `email` field from `MeUpdateSerializer`.
- `backend/kaleem/identity/api/views.py` — add `EmailListCreateView`, `EmailPrimaryView`, `EmailDeleteView`.
- `backend/kaleem/identity/api/urls.py` — wire the three new routes.
- `backend/config/settings/base.py` — add `ACCOUNT_MAX_EMAIL_ADDRESSES = 5`.
- `backend/kaleem/identity/tests/test_email_management.py` — new service + API tests.
- `backend/kaleem/identity/tests/test_api_auth.py` — add the `PATCH /me/` email-immutability test.
- `docs/adr/NNNN-multi-email-management.md` (meta repo) — the ADR.
- `docs/architecture/identity.md` (meta repo) — document the email-management surface.

Branch prep (run once, in the submodule):

```bash
cd backend
git checkout main && git pull
git checkout -b feat/email-management
```

---

### Task 1: List email addresses (`GET /me/emails/`)

**Files:**
- Modify: `backend/kaleem/identity/services.py`
- Modify: `backend/kaleem/identity/api/serializers.py`
- Modify: `backend/kaleem/identity/api/views.py`
- Modify: `backend/kaleem/identity/api/urls.py`
- Test: `backend/kaleem/identity/tests/test_email_management.py` (create)

**Interfaces:**
- Produces: `services.list_email_addresses(user_id: int) -> list[EmailAddress]` — the user's addresses ordered `id`. `EmailAddressSerializer` exposes `{id, email, verified, primary}`. Route name `identity:emails` at `/api/v1/identity/me/emails/`.

- [ ] **Step 1: Write the failing service + API test**

Create `backend/kaleem/identity/tests/test_email_management.py`:

```python
import pytest
from allauth.account.models import EmailAddress
from rest_framework.test import APIClient

from kaleem.identity import services
from kaleem.identity.models import StudentProfile
from kaleem.identity.models import User


@pytest.fixture
def api():
    return APIClient()


def _make_user(email="owner@example.com", password="sup3r-secret-pw", verified=True):
    user = User.objects.create_user(email=email, password=password, full_name="Owner")
    StudentProfile.objects.create(user=user)
    EmailAddress.objects.create(user=user, email=email, primary=True, verified=verified)
    return user


@pytest.mark.django_db
class TestListEmails:
    def test_service_lists_addresses_ordered_by_id(self):
        user = _make_user()
        EmailAddress.objects.create(
            user=user, email="second@example.com", primary=False, verified=False
        )
        result = services.list_email_addresses(user.id)
        assert [e.email for e in result] == ["owner@example.com", "second@example.com"]

    def test_get_endpoint_returns_flags(self, api):
        user = _make_user()
        api.force_authenticate(user=user)
        resp = api.get("/api/v1/identity/me/emails/")
        assert resp.status_code == 200, resp.data
        assert resp.data == [
            {"id": user.emailaddress_set.get().id,
             "email": "owner@example.com", "verified": True, "primary": True}
        ]

    def test_get_requires_auth(self, api):
        resp = api.get("/api/v1/identity/me/emails/")
        assert resp.status_code in (401, 403)
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd backend && pytest kaleem/identity/tests/test_email_management.py -v`
Expected: FAIL (`AttributeError: module 'kaleem.identity.services' has no attribute 'list_email_addresses'` / 404 on the URL).

- [ ] **Step 3: Add the service function**

In `backend/kaleem/identity/services.py`, add the allauth import near the top (it is already imported in this file) and append:

```python
def list_email_addresses(user_id: int) -> list[EmailAddress]:
    """Return the user's email addresses, oldest first."""
    return list(
        EmailAddress.objects.filter(user_id=user_id).order_by("id")
    )
```

- [ ] **Step 4: Add the serializer**

In `backend/kaleem/identity/api/serializers.py`, in the response-serializers section:

```python
class EmailAddressSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    email = serializers.EmailField()
    verified = serializers.BooleanField()
    primary = serializers.BooleanField()
```

- [ ] **Step 5: Add the view**

In `backend/kaleem/identity/api/views.py`, add the import `from kaleem.identity.api.serializers import EmailAddressSerializer` and:

```python
class EmailListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(
        responses={200: EmailAddressSerializer(many=True)},
        summary="List the caller's email addresses.",
    )
    def get(self, request):
        return Response(
            [
                {
                    "id": e.id,
                    "email": e.email,
                    "verified": e.verified,
                    "primary": e.primary,
                }
                for e in services.list_email_addresses(request.user.id)
            ]
        )
```

- [ ] **Step 6: Wire the URL**

In `backend/kaleem/identity/api/urls.py`, add the import `from kaleem.identity.api.views import EmailListCreateView` and, after the `me/` routes:

```python
    path("me/emails/", EmailListCreateView.as_view(), name="emails"),
```

- [ ] **Step 7: Run the tests — expect PASS**

Run: `cd backend && pytest kaleem/identity/tests/test_email_management.py -v`
Expected: PASS (3 tests).

- [ ] **Step 8: Commit**

```bash
cd backend
git add kaleem/identity/services.py kaleem/identity/api/serializers.py \
  kaleem/identity/api/views.py kaleem/identity/api/urls.py \
  kaleem/identity/tests/test_email_management.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(identity): GET /me/emails/ lists addresses

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Add an email (`POST /me/emails/`)

**Files:**
- Modify: `backend/config/settings/base.py`
- Modify: `backend/kaleem/identity/services.py`
- Modify: `backend/kaleem/identity/api/serializers.py`
- Modify: `backend/kaleem/identity/api/views.py`
- Test: `backend/kaleem/identity/tests/test_email_management.py`

**Interfaces:**
- Consumes: `_make_user` fixture from Task 1.
- Produces: `services.add_email_address(user_id: int, email: str, current_password: str) -> EmailAddress` — creates an **unverified, non-primary** `EmailAddress` after validating the password, uniqueness, and the cap, and alerts the current primary. `services._send_email_security_alert(user, new_email: str, action: str) -> None`. `AddEmailSerializer{email, current_password}`. The `POST /me/emails/` handler triggers the allauth confirmation send.

- [ ] **Step 1: Write the failing tests**

Append to `backend/kaleem/identity/tests/test_email_management.py`:

```python
from django.core import mail


@pytest.mark.django_db
class TestAddEmail:
    def test_service_adds_unverified_address(self):
        user = _make_user()
        addr = services.add_email_address(
            user.id, "new@example.com", "sup3r-secret-pw"
        )
        assert addr.verified is False
        assert addr.primary is False
        assert EmailAddress.objects.filter(
            user=user, email="new@example.com", verified=False
        ).exists()
        # old primary unchanged
        assert user.emailaddress_set.get(primary=True).email == "owner@example.com"

    def test_service_rejects_wrong_password(self):
        user = _make_user()
        with pytest.raises(services.ValidationError):
            services.add_email_address(user.id, "new@example.com", "wrong-pw")
        assert not EmailAddress.objects.filter(email="new@example.com").exists()

    def test_service_rejects_email_already_on_account(self):
        user = _make_user()
        with pytest.raises(services.ValidationError):
            services.add_email_address(
                user.id, "owner@example.com", "sup3r-secret-pw"
            )

    def test_service_rejects_email_owned_by_other_user(self):
        user = _make_user()
        _make_user(email="taken@example.com")
        with pytest.raises(services.ValidationError):
            services.add_email_address(
                user.id, "taken@example.com", "sup3r-secret-pw"
            )

    def test_service_enforces_cap(self, settings):
        settings.ACCOUNT_MAX_EMAIL_ADDRESSES = 2
        user = _make_user()
        services.add_email_address(user.id, "a@example.com", "sup3r-secret-pw")
        with pytest.raises(services.ValidationError):
            services.add_email_address(user.id, "b@example.com", "sup3r-secret-pw")

    def test_service_alerts_current_primary(self):
        user = _make_user()
        mail.outbox.clear()
        services.add_email_address(user.id, "new@example.com", "sup3r-secret-pw")
        assert len(mail.outbox) == 1
        assert mail.outbox[0].to == ["owner@example.com"]
        assert "new@example.com" in mail.outbox[0].body

    def test_post_endpoint_adds_and_sends_confirmation(self, api, settings):
        settings.ACCOUNT_EMAIL_VERIFICATION = "mandatory"
        user = _make_user()
        api.force_authenticate(user=user)
        mail.outbox.clear()
        resp = api.post(
            "/api/v1/identity/me/emails/",
            {"email": "new@example.com", "current_password": "sup3r-secret-pw"},
            format="json",
        )
        assert resp.status_code == 201, resp.data
        assert resp.data["email"] == "new@example.com"
        assert resp.data["verified"] is False
        # one alert to the old primary + one confirmation to the new address
        recipients = sorted(sum((m.to for m in mail.outbox), []))
        assert recipients == ["new@example.com", "owner@example.com"]

    def test_post_wrong_password_returns_400(self, api):
        user = _make_user()
        api.force_authenticate(user=user)
        resp = api.post(
            "/api/v1/identity/me/emails/",
            {"email": "new@example.com", "current_password": "wrong"},
            format="json",
        )
        assert resp.status_code == 400
        assert "current_password" in resp.data
```

Add `ValidationError` to the service's public surface so tests can reference `services.ValidationError`: it is already imported into `services.py` (`from kaleem.platform.exceptions import ValidationError`), so `services.ValidationError` resolves. No change needed.

- [ ] **Step 2: Run and confirm failure**

Run: `cd backend && pytest kaleem/identity/tests/test_email_management.py::TestAddEmail -v`
Expected: FAIL (`add_email_address` undefined; 404/405 on POST).

- [ ] **Step 3: Add the cap setting**

In `backend/config/settings/base.py`, in the `# ALLAUTH` block (near `ACCOUNT_EMAIL_VERIFICATION`):

```python
ACCOUNT_MAX_EMAIL_ADDRESSES = env.int("DJANGO_ACCOUNT_MAX_EMAIL_ADDRESSES", default=5)
```

- [ ] **Step 4: Add the service functions**

In `backend/kaleem/identity/services.py`, add imports at the top:

```python
from django.conf import settings
from kaleem.platform.tasks import send_email_message
```

Then append:

```python
def _send_email_security_alert(user: User, new_email: str, action: str) -> None:
    """Notify the user's current primary address of an email change."""
    primary = (
        EmailAddress.objects.filter(user=user, primary=True)
        .values_list("email", flat=True)
        .first()
    ) or user.email
    subject = "Security alert: a change was made to your kaleem account"
    body = (
        f"A request to {action} the email address {new_email} was made on your "
        f"kaleem account. If this was you, no action is needed. If it was not, "
        f"change your password immediately and contact support."
    )
    send_email_message.delay(
        subject=subject,
        body=body,
        from_email=settings.DEFAULT_FROM_EMAIL,
        to=[primary],
        alternatives=None,
    )


@transaction.atomic
def add_email_address(
    user_id: int, email: str, current_password: str
) -> EmailAddress:
    """Add a new unverified email address after a password re-auth check."""
    user = get_user(user_id)
    if not user.check_password(current_password):
        raise ValidationError("Incorrect password.", field="current_password")
    normalized = User.objects.normalize_email(email)
    if EmailAddress.objects.filter(
        user=user, email__iexact=normalized
    ).exists():
        raise ValidationError(
            "This email is already on your account.", field="email"
        )
    in_use = (
        EmailAddress.objects.filter(email__iexact=normalized)
        .exclude(user=user)
        .exists()
        or User.objects.filter(email__iexact=normalized).exclude(pk=user.pk).exists()
    )
    if in_use:
        raise ValidationError("This email is already in use.", field="email")
    if (
        EmailAddress.objects.filter(user=user).count()
        >= settings.ACCOUNT_MAX_EMAIL_ADDRESSES
    ):
        raise ValidationError(
            "You have reached the maximum number of email addresses.", field="email"
        )
    address = EmailAddress.objects.create(
        user=user, email=normalized, primary=False, verified=False
    )
    _send_email_security_alert(user, normalized, action="add")
    return address
```

- [ ] **Step 5: Add the serializer**

In `backend/kaleem/identity/api/serializers.py`:

```python
class AddEmailSerializer(serializers.Serializer):
    email = serializers.EmailField()
    current_password = serializers.CharField(write_only=True)
```

- [ ] **Step 6: Add the POST handler**

In `backend/kaleem/identity/api/views.py`, import `from kaleem.identity.api.serializers import AddEmailSerializer`, then add a `post` method to `EmailListCreateView`:

```python
    @extend_schema(
        request=AddEmailSerializer,
        responses={201: EmailAddressSerializer},
        summary="Add a new (unverified) email address; sends a verification link.",
    )
    def post(self, request):
        serializer = AddEmailSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        address = services.add_email_address(
            request.user.id,
            email=serializer.validated_data["email"],
            current_password=serializer.validated_data["current_password"],
        )
        if settings.ACCOUNT_EMAIL_VERIFICATION == "mandatory":
            # allauth needs the underlying Django HttpRequest, not the DRF wrapper.
            address.send_confirmation(request._request)  # noqa: SLF001
        return Response(
            {
                "id": address.id,
                "email": address.email,
                "verified": address.verified,
                "primary": address.primary,
            },
            status=status.HTTP_201_CREATED,
        )
```

(`settings` and `EmailAddress` are already imported in this module.)

- [ ] **Step 7: Run the tests — expect PASS**

Run: `cd backend && pytest kaleem/identity/tests/test_email_management.py::TestAddEmail -v`
Expected: PASS (8 tests).

- [ ] **Step 8: Commit**

```bash
cd backend
git add config/settings/base.py kaleem/identity/services.py \
  kaleem/identity/api/serializers.py kaleem/identity/api/views.py \
  kaleem/identity/tests/test_email_management.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(identity): POST /me/emails/ adds unverified address

Password-gated; sends verification to the new address and a security alert to
the current primary. Caps addresses at ACCOUNT_MAX_EMAIL_ADDRESSES.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Promote to primary (`POST /me/emails/{id}/primary/`)

**Files:**
- Modify: `backend/kaleem/identity/services.py`
- Modify: `backend/kaleem/identity/api/serializers.py`
- Modify: `backend/kaleem/identity/api/views.py`
- Modify: `backend/kaleem/identity/api/urls.py`
- Test: `backend/kaleem/identity/tests/test_email_management.py`

**Interfaces:**
- Produces: `services.set_primary_email(user_id: int, email_id: int, current_password: str) -> EmailAddress` — promotes a **verified** address, syncs `User.email`, alerts the previous primary. `SetPrimaryEmailSerializer{current_password}`. Route name `identity:email-primary` at `/api/v1/identity/me/emails/<int:email_id>/primary/`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/kaleem/identity/tests/test_email_management.py`:

```python
@pytest.mark.django_db
class TestSetPrimary:
    def _verified_secondary(self, user, email="second@example.com"):
        return EmailAddress.objects.create(
            user=user, email=email, primary=False, verified=True
        )

    def test_service_promotes_verified_address_and_syncs_user_email(self):
        user = _make_user()
        addr = self._verified_secondary(user)
        services.set_primary_email(user.id, addr.id, "sup3r-secret-pw")
        user.refresh_from_db()
        assert user.email == "second@example.com"
        assert EmailAddress.objects.get(pk=addr.pk).primary is True
        assert (
            EmailAddress.objects.get(email="owner@example.com").primary is False
        )

    def test_service_rejects_unverified_address(self):
        user = _make_user()
        addr = EmailAddress.objects.create(
            user=user, email="second@example.com", primary=False, verified=False
        )
        with pytest.raises(services.ValidationError):
            services.set_primary_email(user.id, addr.id, "sup3r-secret-pw")

    def test_service_rejects_wrong_password(self):
        user = _make_user()
        addr = self._verified_secondary(user)
        with pytest.raises(services.ValidationError):
            services.set_primary_email(user.id, addr.id, "wrong-pw")

    def test_service_rejects_other_users_address(self):
        user = _make_user()
        other = _make_user(email="other@example.com")
        other_addr = other.emailaddress_set.get()
        with pytest.raises(services.NotFoundError):
            services.set_primary_email(user.id, other_addr.id, "sup3r-secret-pw")

    def test_service_alerts_previous_primary(self):
        user = _make_user()
        addr = self._verified_secondary(user)
        mail.outbox.clear()
        services.set_primary_email(user.id, addr.id, "sup3r-secret-pw")
        assert len(mail.outbox) == 1
        assert mail.outbox[0].to == ["owner@example.com"]

    def test_post_endpoint_promotes(self, api):
        user = _make_user()
        addr = self._verified_secondary(user)
        api.force_authenticate(user=user)
        resp = api.post(
            f"/api/v1/identity/me/emails/{addr.id}/primary/",
            {"current_password": "sup3r-secret-pw"},
            format="json",
        )
        assert resp.status_code == 200, resp.data
        assert resp.data["primary"] is True
        assert resp.data["email"] == "second@example.com"
```

`NotFoundError` is already imported into `services.py`, so `services.NotFoundError` resolves.

- [ ] **Step 2: Run and confirm failure**

Run: `cd backend && pytest kaleem/identity/tests/test_email_management.py::TestSetPrimary -v`
Expected: FAIL (`set_primary_email` undefined).

- [ ] **Step 3: Add the service function**

In `backend/kaleem/identity/services.py`, append:

```python
@transaction.atomic
def set_primary_email(
    user_id: int, email_id: int, current_password: str
) -> EmailAddress:
    """Make a verified address primary (the login identity); alert the old one."""
    user = get_user(user_id)
    if not user.check_password(current_password):
        raise ValidationError("Incorrect password.", field="current_password")
    try:
        address = EmailAddress.objects.get(pk=email_id, user=user)
    except EmailAddress.DoesNotExist:
        raise NotFoundError("EmailAddress", email_id) from None
    if not address.verified:
        raise ValidationError(
            "Verify this email address before making it primary.", field="email"
        )
    previous_primary = (
        EmailAddress.objects.filter(user=user, primary=True)
        .values_list("email", flat=True)
        .first()
    )
    address.set_as_primary()  # sets this primary, unsets others, syncs user.email
    if previous_primary and previous_primary != address.email:
        _send_email_security_alert(user, address.email, action="set as primary on")
    return address
```

- [ ] **Step 4: Add the serializer**

In `backend/kaleem/identity/api/serializers.py`:

```python
class SetPrimaryEmailSerializer(serializers.Serializer):
    current_password = serializers.CharField(write_only=True)
```

- [ ] **Step 5: Add the view**

In `backend/kaleem/identity/api/views.py`, import `from kaleem.identity.api.serializers import SetPrimaryEmailSerializer` and add:

```python
class EmailPrimaryView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(
        request=SetPrimaryEmailSerializer,
        responses={200: EmailAddressSerializer},
        summary="Make a verified email address the primary (login) address.",
    )
    def post(self, request, email_id):
        serializer = SetPrimaryEmailSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        address = services.set_primary_email(
            request.user.id,
            email_id=email_id,
            current_password=serializer.validated_data["current_password"],
        )
        return Response(
            {
                "id": address.id,
                "email": address.email,
                "verified": address.verified,
                "primary": address.primary,
            }
        )
```

- [ ] **Step 6: Wire the URL**

In `backend/kaleem/identity/api/urls.py`, import `from kaleem.identity.api.views import EmailPrimaryView` and add after the `me/emails/` route:

```python
    path(
        "me/emails/<int:email_id>/primary/",
        EmailPrimaryView.as_view(),
        name="email-primary",
    ),
```

- [ ] **Step 7: Run the tests — expect PASS**

Run: `cd backend && pytest kaleem/identity/tests/test_email_management.py::TestSetPrimary -v`
Expected: PASS (6 tests).

- [ ] **Step 8: Commit**

```bash
cd backend
git add kaleem/identity/services.py kaleem/identity/api/serializers.py \
  kaleem/identity/api/views.py kaleem/identity/api/urls.py \
  kaleem/identity/tests/test_email_management.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(identity): POST /me/emails/{id}/primary/ promotes a verified address

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Remove an email (`DELETE /me/emails/{id}/`)

**Files:**
- Modify: `backend/kaleem/identity/services.py`
- Modify: `backend/kaleem/identity/api/views.py`
- Modify: `backend/kaleem/identity/api/urls.py`
- Test: `backend/kaleem/identity/tests/test_email_management.py`

**Interfaces:**
- Produces: `services.remove_email_address(user_id: int, email_id: int) -> None` — deletes a non-primary address owned by the user. Route name `identity:email-detail` at `/api/v1/identity/me/emails/<int:email_id>/`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/kaleem/identity/tests/test_email_management.py`:

```python
@pytest.mark.django_db
class TestRemoveEmail:
    def test_service_removes_secondary(self):
        user = _make_user()
        addr = EmailAddress.objects.create(
            user=user, email="second@example.com", primary=False, verified=True
        )
        services.remove_email_address(user.id, addr.id)
        assert not EmailAddress.objects.filter(pk=addr.pk).exists()

    def test_service_rejects_removing_primary(self):
        user = _make_user()
        primary = user.emailaddress_set.get(primary=True)
        with pytest.raises(services.ValidationError):
            services.remove_email_address(user.id, primary.id)
        assert EmailAddress.objects.filter(pk=primary.pk).exists()

    def test_service_rejects_other_users_address(self):
        user = _make_user()
        other = _make_user(email="other@example.com")
        other_addr = other.emailaddress_set.get()
        with pytest.raises(services.NotFoundError):
            services.remove_email_address(user.id, other_addr.id)

    def test_delete_endpoint_removes(self, api):
        user = _make_user()
        addr = EmailAddress.objects.create(
            user=user, email="second@example.com", primary=False, verified=True
        )
        api.force_authenticate(user=user)
        resp = api.delete(f"/api/v1/identity/me/emails/{addr.id}/")
        assert resp.status_code == 204
        assert not EmailAddress.objects.filter(pk=addr.pk).exists()
```

- [ ] **Step 2: Run and confirm failure**

Run: `cd backend && pytest kaleem/identity/tests/test_email_management.py::TestRemoveEmail -v`
Expected: FAIL (`remove_email_address` undefined).

- [ ] **Step 3: Add the service function**

In `backend/kaleem/identity/services.py`, append:

```python
@transaction.atomic
def remove_email_address(user_id: int, email_id: int) -> None:
    """Delete a non-primary email address owned by the user."""
    try:
        address = EmailAddress.objects.get(pk=email_id, user_id=user_id)
    except EmailAddress.DoesNotExist:
        raise NotFoundError("EmailAddress", email_id) from None
    if address.primary:
        raise ValidationError(
            "Set another address as primary before removing this one.",
            field="email",
        )
    address.delete()
```

- [ ] **Step 4: Add the DELETE handler**

In `backend/kaleem/identity/api/views.py`, add:

```python
class EmailDeleteView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(
        responses={204: OpenApiResponse(description="Address removed.")},
        summary="Remove an email address (the primary cannot be removed).",
    )
    def delete(self, request, email_id):
        services.remove_email_address(request.user.id, email_id)
        return Response(status=status.HTTP_204_NO_CONTENT)
```

- [ ] **Step 5: Wire the URL**

In `backend/kaleem/identity/api/urls.py`, import `from kaleem.identity.api.views import EmailDeleteView` and add:

```python
    path(
        "me/emails/<int:email_id>/",
        EmailDeleteView.as_view(),
        name="email-detail",
    ),
```

- [ ] **Step 6: Run the tests — expect PASS**

Run: `cd backend && pytest kaleem/identity/tests/test_email_management.py::TestRemoveEmail -v`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
cd backend
git add kaleem/identity/services.py kaleem/identity/api/views.py \
  kaleem/identity/api/urls.py kaleem/identity/tests/test_email_management.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(identity): DELETE /me/emails/{id}/ removes a non-primary address

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Remove the insecure `PATCH /me/ {email}` path + full-flow integration test

**Files:**
- Modify: `backend/kaleem/identity/api/serializers.py`
- Test: `backend/kaleem/identity/tests/test_api_auth.py`
- Test: `backend/kaleem/identity/tests/test_email_management.py`

**Interfaces:**
- Consumes: all services from Tasks 1–4. After this task `MeUpdateSerializer` no longer has an `email` field, so `PATCH /me/` cannot mutate the login identity.

- [ ] **Step 1: Write the failing tests**

Add to `backend/kaleem/identity/tests/test_api_auth.py` (uses that file's existing `api` fixture and register/login helpers):

```python
@pytest.mark.django_db
class TestEmailImmutableViaPatch:
    def test_patch_me_ignores_email(self, api):
        from allauth.account.models import EmailAddress
        from kaleem.identity.models import User
        user = User.objects.create_user(
            email="patch@example.com", password="sup3r-secret-pw", full_name="P"
        )
        EmailAddress.objects.create(
            user=user, email="patch@example.com", primary=True, verified=True
        )
        api.force_authenticate(user=user)
        resp = api.patch(
            "/api/v1/identity/me/", {"email": "hacked@example.com"}, format="json"
        )
        assert resp.status_code == 200, resp.data
        user.refresh_from_db()
        assert user.email == "patch@example.com"
```

Append a full add→verify→promote flow test to `test_email_management.py`:

```python
from allauth.account.models import EmailConfirmationHMAC


@pytest.mark.django_db
class TestFullChangeFlow:
    def test_add_verify_promote_old_still_logs_in(self, api, settings):
        settings.ACCOUNT_EMAIL_VERIFICATION = "mandatory"
        user = _make_user(email="old@example.com")

        # add new (unverified) while logged in
        api.force_authenticate(user=user)
        add = api.post(
            "/api/v1/identity/me/emails/",
            {"email": "fresh@example.com", "current_password": "sup3r-secret-pw"},
            format="json",
        )
        assert add.status_code == 201, add.data
        new_id = add.data["id"]

        # old email still authenticates while new is pending
        api.logout()
        login_old = api.post(
            "/api/v1/identity/login/",
            {"email": "old@example.com", "password": "sup3r-secret-pw"},
            format="json",
        )
        assert login_old.status_code == 200, login_old.data

        # verify the new address by key (reuses the existing endpoint)
        new_addr = EmailAddress.objects.get(pk=new_id)
        key = EmailConfirmationHMAC(new_addr).key
        verify = api.post(
            "/api/v1/identity/verify-email/", {"key": key}, format="json"
        )
        assert verify.status_code == 200, verify.data
        new_addr.refresh_from_db()
        assert new_addr.verified is True

        # promote it; user.email swaps
        api.force_authenticate(user=user)
        promote = api.post(
            f"/api/v1/identity/me/emails/{new_id}/primary/",
            {"current_password": "sup3r-secret-pw"},
            format="json",
        )
        assert promote.status_code == 200, promote.data
        user.refresh_from_db()
        assert user.email == "fresh@example.com"

        # old email is still a verified secondary and still logs in
        api.logout()
        still = api.post(
            "/api/v1/identity/login/",
            {"email": "old@example.com", "password": "sup3r-secret-pw"},
            format="json",
        )
        assert still.status_code == 200, still.data
```

This flow test depends on Task 3 of the `feat/verify-email-endpoint` work (`verify-email/` + `VerifyEmailView`). If that branch is not yet merged into the base, rebase this branch onto it first (see Task 7 dependency note).

- [ ] **Step 2: Run and confirm failure**

Run: `cd backend && pytest kaleem/identity/tests/test_api_auth.py::TestEmailImmutableViaPatch kaleem/identity/tests/test_email_management.py::TestFullChangeFlow -v`
Expected: FAIL — `test_patch_me_ignores_email` fails because `PATCH` still writes `email`; the flow test fails if run before the email is made immutable / endpoints exist.

- [ ] **Step 3: Remove the `email` field from `MeUpdateSerializer`**

In `backend/kaleem/identity/api/serializers.py`, change `MeUpdateSerializer` to drop the `email` field and its `validate_email`:

```python
class MeUpdateSerializer(serializers.Serializer):
    full_name = serializers.CharField(max_length=255, required=False)
```

(The `MeView.patch` loop already only sets fields present in `validated_data`, so removing `email` here is sufficient — no view change needed.)

- [ ] **Step 4: Run the tests — expect PASS**

Run: `cd backend && pytest kaleem/identity/tests/test_api_auth.py kaleem/identity/tests/test_email_management.py -v`
Expected: PASS (all, including the immutability + full-flow tests).

- [ ] **Step 5: Run the whole identity suite + lint**

Run:
```bash
cd backend
pytest kaleem/identity -q
ruff check . && mypy kaleem/identity && lint-imports
```
Expected: all green. (`lint-imports` is the import-linter command; confirm none of the new code imports another module's models.)

- [ ] **Step 6: Commit**

```bash
cd backend
git add kaleem/identity/api/serializers.py \
  kaleem/identity/tests/test_api_auth.py \
  kaleem/identity/tests/test_email_management.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(identity): make email immutable via PATCH /me/; add change-flow test

Email changes now go exclusively through /me/emails/. Full add->verify->promote
flow proves the old verified address keeps logging in throughout.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: ADR + architecture doc (meta repo)

**Files:**
- Create: `docs/adr/NNNN-multi-email-management.md` (use `/new-adr`; pick the next ADR number)
- Modify: `docs/architecture/identity.md`

**Interfaces:** None (documentation). This task is in the **meta repo** on branch `feat/email-management-spec` (the spec/plan branch), not the backend submodule.

- [ ] **Step 1: Write the ADR**

Run `/new-adr` (or copy `docs/templates/`'s ADR format). Record: decision to expose multi-email management with a user-chosen primary, password re-auth on add + set-primary, security alert to the current primary, cap of 5. Context: original framing was "single `User.email`"; uniqueness of `User.email` is preserved (it tracks the primary `EmailAddress`). Consequences: richer account surface; allauth `EmailAddress` is the source of truth; future per-address notification routing is out of scope.

- [ ] **Step 2: Update the identity architecture doc**

In `docs/architecture/identity.md`, add an "Email addresses" subsection: the `/me/emails/` surface, the add→verify→set-primary lifecycle, `User.email` ↔ primary `EmailAddress` sync, and the security-alert behaviour.

- [ ] **Step 3: Commit (meta repo)**

```bash
cd /home/abdulkhalek/Projects/kaleem
git add docs/adr/ docs/architecture/identity.md
PIP_CONFIG_FILE=/dev/null git commit -m "docs(identity): ADR + arch doc for multi-email management

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Open PRs (git-flow) and update project state

**Files:**
- Modify: `STATE.md` (meta repo)

**Dependency note:** the full-flow test in Task 5 consumes the `verify-email/` endpoint from the open `feat/verify-email-endpoint` branch (PR #15). **Land PR #15 into `main` first**, then rebase `feat/email-management` onto the updated `main` before opening this PR. If #15 is still open at execution time, coordinate the merge order rather than duplicating the endpoint.

- [ ] **Step 1: Push the backend branch and open its PR**

```bash
cd backend
git push -u origin feat/email-management
gh pr create --base main --title "feat(identity): email-address management" \
  --body "Implements docs/superpowers/specs/2026-06-17-email-management-design.md. Multi-email per user via allauth; add starts unverified and leaves existing verified addresses working; password-gated add + set-primary; security alert to current primary; removes the insecure PATCH /me/{email} path. Depends on #15 (verify-email endpoint).

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 2: Confirm CI is green**

Run: `gh pr checks --watch` (in `backend`). Expected: all checks pass. Do not merge red. No `--no-verify`.

- [ ] **Step 3: Bump the backend submodule pointer + update `STATE.md` (meta repo)**

After the backend PR merges to `main`, in the meta repo on `feat/email-management-spec`: update the `backend` submodule pointer to the merged commit, and update `STATE.md` (active spec / phase notes). Commit:

```bash
cd /home/abdulkhalek/Projects/kaleem
git add backend STATE.md
PIP_CONFIG_FILE=/dev/null git commit -m "chore: bump backend pointer; email-management shipped

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: Open the meta-repo PR into `develop`**

```bash
cd /home/abdulkhalek/Projects/kaleem
git push -u origin feat/email-management-spec
gh pr create --base develop --title "docs+pointer: email-address management" \
  --body "Spec, plan, ADR, identity arch doc, and backend pointer bump for email-address management.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-17-email-management-design.md`):
- List addresses → Task 1. Add (unverified, password-gated, alert, cap, uniqueness) → Task 2. Set-primary (verified-only, password, sync `User.email`, alert) → Task 3. Remove (not primary) → Task 4. Remove insecure `PATCH /me/{email}` → Task 5. Reuse of `verify-email/` + `resend-verification/` → exercised in Task 5 flow test; no new code needed. ADR → Task 6. Old-email-keeps-working → Task 5 flow test. ✓ All spec sections covered.
- Out-of-scope items (dashboard UI, login-rule changes) correctly have no task.

**Placeholder scan:** ADR number is `NNNN` by necessity (assigned via `/new-adr` at execution) — flagged, not a code placeholder. No "TBD"/"handle edge cases"/"add validation" left; every code step shows full code.

**Type consistency:** `add_email_address`, `set_primary_email`, `remove_email_address`, `list_email_addresses`, `_send_email_security_alert` — names identical across interfaces, code, and tests. `EmailAddressSerializer` field set `{id, email, verified, primary}` consistent in serializer, views, and assertions. Route names (`emails`, `email-primary`, `email-detail`) consistent between `urls.py` steps and the URLs used in tests.
