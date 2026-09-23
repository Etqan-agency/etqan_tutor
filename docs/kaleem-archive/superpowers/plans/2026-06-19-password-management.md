# Password management — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Checkbox steps.

**Goal:** Change-password (signed in) + forgot/reset password (emailed link), backend + dashboard.

**Architecture:** Three DRF endpoints in `kaleem.identity` over Django's `default_token_generator`; three dashboard surfaces reusing the verify-email token-page shape + toasts + `redirectIfAuthed`. Spec: `docs/superpowers/specs/2026-06-19-password-management-design.md`.

## Global Constraints

- 100% line+branch (backend); ruff+mypy+import-linter; logic in services.py. Dashboard: en+ar, jest-axe, tsc+biome.
- New-password min length 8. Reset request: **no account enumeration** (always 200) + `EmailScopedThrottle`.
- Reset/confirm are unauthenticated mutations → dashboard must `GET identity/csrf/` before POST (like verify-email).
- Emails: URL on its own line, no trailing punctuation (ADR-0023; the dot-bug lesson).

---

### Task 1: Backend — change password (signed in)

**Files:** `serializers.py`, `services.py`, `api/views.py`, `api/urls.py`; test `tests/test_password_management.py`.

- [ ] **Step 1: failing test** (`tests/test_password_management.py`)

```python
import pytest
from rest_framework.test import APIClient
from kaleem.identity.models import User


@pytest.fixture
def api():
    return APIClient()


def _user(email="u@example.com", password="old-secret-pw"):
    return User.objects.create_user(email=email, password=password, full_name="U")


@pytest.mark.django_db
class TestChangePassword:
    URL = "/api/v1/identity/me/password/"

    def test_change_with_correct_current_password(self, api):
        user = _user()
        api.force_authenticate(user=user)
        resp = api.post(
            self.URL,
            {"current_password": "old-secret-pw", "new_password": "new-secret-pw"},
            format="json",
        )
        assert resp.status_code == 200, resp.data
        user.refresh_from_db()
        assert user.check_password("new-secret-pw")
        # session kept alive: a protected endpoint still works
        assert api.get("/api/v1/identity/me/").status_code == 200

    def test_change_with_wrong_current_password(self, api):
        user = _user()
        api.force_authenticate(user=user)
        resp = api.post(
            self.URL,
            {"current_password": "WRONG", "new_password": "new-secret-pw"},
            format="json",
        )
        assert resp.status_code == 400
        assert "current_password" in resp.data
        user.refresh_from_db()
        assert user.check_password("old-secret-pw")

    def test_change_requires_auth(self, api):
        assert api.post(self.URL, {}, format="json").status_code in (401, 403)
```

- [ ] **Step 2:** run → FAIL. `cd backend && DATABASE_URL=postgres://kaleem:kaleem@localhost:5432/kaleem python -m pytest kaleem/identity/tests/test_password_management.py -q --create-db`

- [ ] **Step 3: serializer**

```python
class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True, min_length=8)
```

- [ ] **Step 4: service** (in `services.py`)

```python
def change_password(user_id: int, current_password: str, new_password: str) -> User:
    """Change a signed-in user's password after verifying the current one."""
    user = get_user(user_id)
    if not user.check_password(current_password):
        raise ValidationError("Incorrect password.", field="current_password")
    user.set_password(new_password)
    user.save(update_fields=["password"])
    return user
```

- [ ] **Step 5: view + url**

```python
# views.py — imports: from django.contrib.auth import update_session_auth_hash
class ChangePasswordView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(
        request=ChangePasswordSerializer,
        responses={200: OpenApiResponse(description="Password changed.")},
        summary="Change the signed-in user's password.",
    )
    def post(self, request):
        serializer = ChangePasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.change_password(
            request.user.id,
            serializer.validated_data["current_password"],
            serializer.validated_data["new_password"],
        )
        # Django rotates the session auth hash on password change; refresh it so
        # the current session stays valid instead of logging the user out.
        update_session_auth_hash(request._request, request.user)  # noqa: SLF001
        return Response(status=status.HTTP_200_OK)
```

`urls.py`: `path("me/password/", ChangePasswordView.as_view(), name="change-password"),`

- [ ] **Step 6:** run → PASS. **Step 7:** commit `feat(identity): change-password endpoint`.

---

### Task 2: Backend — request + confirm password reset

**Files:** `serializers.py`, `services.py`, `api/views.py`, `api/urls.py`; extend `tests/test_password_management.py`.

- [ ] **Step 1: failing tests**

```python
from django.contrib.auth.tokens import default_token_generator
from django.utils.encoding import force_bytes
from django.utils.http import urlsafe_base64_encode
from allauth.account.models import EmailAddress
from django.core.cache import cache


@pytest.fixture(autouse=True)
def _clear_throttle():
    cache.clear()
    yield
    cache.clear()


def _verified_user(email="u@example.com", password="old-secret-pw"):
    user = User.objects.create_user(email=email, password=password, full_name="U")
    EmailAddress.objects.create(user=user, email=email, primary=True, verified=True)
    return user


@pytest.mark.django_db
class TestPasswordReset:
    REQ = "/api/v1/identity/password/reset/"
    CONFIRM = "/api/v1/identity/password/reset/confirm/"

    def test_request_for_known_email_sends_link(self, api, mailoutbox):
        _verified_user()
        resp = api.post(self.REQ, {"email": "u@example.com"}, format="json")
        assert resp.status_code == 200
        assert len(mailoutbox) == 1
        assert "/reset-password?uid=" in mailoutbox[0].body
        assert "/reset-password?uid=" in mailoutbox[0].body.split("token=")[0] + "token="

    def test_request_for_unknown_email_is_silent_200(self, api, mailoutbox):
        resp = api.post(self.REQ, {"email": "nobody@example.com"}, format="json")
        assert resp.status_code == 200
        assert mailoutbox == []

    def test_confirm_with_valid_token_sets_password(self, api):
        user = _verified_user()
        uid = urlsafe_base64_encode(force_bytes(user.pk))
        token = default_token_generator.make_token(user)
        resp = api.post(
            self.CONFIRM,
            {"uid": uid, "token": token, "new_password": "brand-new-pw"},
            format="json",
        )
        assert resp.status_code == 200, resp.data
        user.refresh_from_db()
        assert user.check_password("brand-new-pw")

    def test_confirm_with_bad_token_returns_400(self, api):
        user = _verified_user()
        uid = urlsafe_base64_encode(force_bytes(user.pk))
        resp = api.post(
            self.CONFIRM,
            {"uid": uid, "token": "bad-token", "new_password": "brand-new-pw"},
            format="json",
        )
        assert resp.status_code == 400
        user.refresh_from_db()
        assert user.check_password("old-secret-pw")
```

- [ ] **Step 2:** run → FAIL.

- [ ] **Step 3: serializers**

```python
class PasswordResetSerializer(serializers.Serializer):
    email = serializers.EmailField()


class PasswordResetConfirmSerializer(serializers.Serializer):
    uid = serializers.CharField()
    token = serializers.CharField()
    new_password = serializers.CharField(write_only=True, min_length=8)
```

- [ ] **Step 4: services** (add imports: `from django.contrib.auth.tokens import default_token_generator`, `from django.utils.encoding import force_bytes`, `from django.utils.http import urlsafe_base64_decode, urlsafe_base64_encode`)

```python
def request_password_reset(email: str) -> None:
    """Email a reset link if a verified account exists. Silent otherwise (no enumeration)."""
    address = (
        EmailAddress.objects.filter(email__iexact=email, verified=True)
        .select_related("user")
        .first()
    )
    if address is None:
        return
    user = address.user
    uid = urlsafe_base64_encode(force_bytes(user.pk))
    token = default_token_generator.make_token(user)
    reset_url = f"{settings.FRONTEND_URL}/reset-password?uid={uid}&token={token}"
    send_email_message.delay(
        subject="Reset your kaleem password",
        body=(
            "We received a request to reset your kaleem password.\n\n"
            "Reset it here:\n"
            f"{reset_url}\n\n"
            "If you didn't request this, you can safely ignore this email."
        ),
        from_email=settings.DEFAULT_FROM_EMAIL,
        to=[email],
        alternatives=None,
    )


def confirm_password_reset(uid: str, token: str, new_password: str) -> User:
    """Validate a reset uid+token and set the new password."""
    invalid = ValidationError("Invalid or expired reset link.", field="token")
    try:
        user = User.objects.get(pk=urlsafe_base64_decode(uid).decode())
    except (User.DoesNotExist, ValueError, TypeError, OverflowError):
        raise invalid from None
    if not default_token_generator.check_token(user, token):
        raise invalid
    user.set_password(new_password)
    user.save(update_fields=["password"])
    return user
```

- [ ] **Step 5: views + urls**

```python
class PasswordResetView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [EmailScopedThrottle]

    @extend_schema(
        request=PasswordResetSerializer,
        responses={200: OpenApiResponse(description="Always 200; link sent if the account exists.")},
        summary="Request a password-reset link (silent on unknown email).",
    )
    def post(self, request):
        serializer = PasswordResetSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.request_password_reset(serializer.validated_data["email"])
        return Response(status=status.HTTP_200_OK)


class PasswordResetConfirmView(APIView):
    permission_classes = [AllowAny]

    @extend_schema(
        request=PasswordResetConfirmSerializer,
        responses={
            200: OpenApiResponse(description="Password reset."),
            400: OpenApiResponse(description="Invalid or expired link."),
        },
        summary="Set a new password from a reset uid+token.",
    )
    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.confirm_password_reset(
            serializer.validated_data["uid"],
            serializer.validated_data["token"],
            serializer.validated_data["new_password"],
        )
        return Response(status=status.HTTP_200_OK)
```

`urls.py`: `path("password/reset/", PasswordResetView.as_view(), name="password-reset")` and `path("password/reset/confirm/", PasswordResetConfirmView.as_view(), name="password-reset-confirm")`.

- [ ] **Step 6:** run full identity suite + ruff+mypy+import-linter → green. **Step 7:** commit `feat(identity): password reset request + confirm`.

---

### Task 3: Dashboard — change-password card on /account

**Files:** `schemas.ts`, `api.ts`, `queries.ts`, `components/ChangePasswordCard.tsx`, the `/account` route, `locales/{en,ar}`; tests beside.

Mirror `AddEmailForm`/`ProfileEditForm`: react-hook-form + zodResolver, inline `errors.root.server` Alert, success → `toast({description: t("account.passwordChanged"), variant:"success"})` + `reset()`.

- `changePasswordSchema = z.object({ current_password: z.string().min(1), new_password: z.string().min(8) })`.
- `identityApi.changePassword(input)` → `api.post("identity/me/password/", input)`; `useChangePassword` mutation.
- Card with two password inputs (autoComplete `current-password` / `new-password`), submit button. Mount on `/account` below the profile card.
- i18n keys: `account.changePassword`, `account.currentPassword` (exists), `account.newPassword`, `account.passwordChanged`, `account.changePasswordSubmit`.
- Tests: success path asserts the toast + `changePassword` payload; wrong-current-password surfaces the inline error (mock 400 `{current_password:[...]}`); jest-axe.

- [ ] Write test (RED) → implement → green → tsc+biome → commit `feat(ui): change-password card on /account`.

---

### Task 4: Dashboard — forgot-password + reset-password routes

**Files:** `schemas.ts`, `api.ts`, `queries.ts`, `routes/forgot-password.tsx`, `routes/reset-password.tsx`, link in `LoginForm`/login page, `locales/{en,ar}`; tests.

- `forgotPasswordSchema = z.object({ email: z.email() })`; `resetPasswordSchema = z.object({ new_password: z.string().min(8) })`.
- `identityApi.requestPasswordReset({email})` → `GET identity/csrf/` then `POST identity/password/reset/`. `confirmPasswordReset({uid,token,new_password})` → `GET identity/csrf/` then `POST identity/password/reset/confirm/`. Hooks `useRequestPasswordReset`, `useConfirmPasswordReset`.
- **`/forgot-password`** (public, `beforeLoad: redirectIfAuthed`): email field → on submit, swap to neutral message `t("auth.resetLinkSent")` ("If that account exists, a reset link is on its way."). Linked from login page (`t("auth.forgotPassword")`).
- **`/reset-password`** (public): reads `uid`+`token` from search params (`validateSearch`); new-password field → confirm → success state (`t("auth.passwordReset")` + link to `/login`); on error → `t("auth.resetLinkInvalid")`. Model the terminal states on `verify-email.tsx` (but this one has a form, so: form → submit → success/error). Missing uid/token → show invalid state.
- i18n keys (en+ar): `auth.forgotPassword`, `auth.forgotPasswordTitle`, `auth.forgotPasswordSubtitle`, `auth.sendResetLink`, `auth.resetLinkSent`, `auth.resetPasswordTitle`, `auth.newPassword`, `auth.resetPassword`, `auth.passwordReset`, `auth.resetLinkInvalid`, `auth.backToSignIn`.
- Tests: forgot form posts email + shows neutral message; reset form posts uid/token/new_password + success; invalid token → error; missing params → invalid; jest-axe on both.

- [ ] Write tests (RED) → implement → green → full `vitest`+tsc+biome → commit `feat(ui): forgot-password + reset-password routes`.
