# Password management — design

**Status:** approved (decisions made autonomously per the user's "do all of them" directive).
**Date:** 2026-06-19
**Slice:** 4 of 4 (final) in the post-verification backlog campaign. Backend + dashboard.

## Goal

Let users (1) **change their password** while signed in, and (2) **reset a forgotten
password** via an emailed link — closing `tasks.todo`: "setup change password and account
password reset".

## Three backend endpoints

All under `kaleem.identity`, services in `services.py`, views thin. New password min length 8
(matches registration). Reuses the Celery email adapter (ADR-0018) and `FRONTEND_URL`.

1. **Change password (signed in)** — `POST /api/v1/identity/me/password/`
   `{current_password, new_password}`. Auth required. Verifies `current_password`
   (`user.check_password`), rejects if wrong (`ValidationError(field="current_password")`),
   then `set_password` + save. **Keeps the session alive** via
   `update_session_auth_hash(request, user)` (Django rotates the session hash on password
   change, which would otherwise log the user out). 200 on success.

2. **Request reset (forgotten)** — `POST /api/v1/identity/password/reset/` `{email}`.
   AllowAny. Looks up a user by a **verified** `EmailAddress`. If found, generates a Django
   `default_token_generator` token + base64 uid and emails a link to
   `{FRONTEND_URL}/reset-password?uid={uid}&token={token}` (via the Celery task). **Always
   returns 200** regardless of whether the email exists (no account enumeration), and is
   **throttled per email** (mirrors `resend-verification`).

3. **Confirm reset** — `POST /api/v1/identity/password/reset/confirm/`
   `{uid, token, new_password}`. AllowAny. Decodes uid → user, validates the token with
   `default_token_generator.check_token`; on success `set_password` + save. Invalid/expired
   uid or token → typed 400 (`field="token"`). Tokens are single-use-ish (invalidated once the
   password changes, since the token hash includes the password).

**Why Django's `default_token_generator` (not allauth's):** it's the standard
`PasswordResetTokenGenerator` allauth itself wraps — time-limited, tied to the password hash
+ `last_login`, no new table. We control the URL (frontend route) and the email via the
existing adapter, exactly like the verify-email override.

## Three dashboard surfaces

Reuses the toast system (slice 2) for success and the verify-email page shape (slice "email").
All TDD, en/ar + RTL, jest-axe.

1. **Change-password card on `/account`** — `current_password` + `new_password` fields;
   on success a success **toast** ("Password updated.") and the form resets. Field/root errors
   inline (e.g. wrong current password).
2. **`/forgot-password` route** — email field → `POST password/reset/` → swap to a neutral
   "If that account exists, a reset link is on its way." message (no enumeration). Linked from
   the login page ("Forgot your password?"). Public route; redirect authed users away (reuse
   `redirectIfAuthed`).
3. **`/reset-password?uid=&token=` route** — new-password field → `POST
   password/reset/confirm/` → success state ("Password reset — sign in") linking to `/login`;
   invalid/expired link → error state. Mirrors `verify-email.tsx`'s terminal-state structure.
   Public route.

CSRF: the reset/confirm POSTs are unauthenticated mutations — fetch the CSRF cookie first
(`GET identity/csrf/`) exactly like the verify-email confirm does.

## Files

**Backend**
- `serializers.py` — `ChangePasswordSerializer` (current+new), `PasswordResetSerializer`
  (email), `PasswordResetConfirmSerializer` (uid, token, new_password).
- `services.py` — `change_password(user_id, current, new)`,
  `request_password_reset(email)` (returns None; sends email if user found),
  `confirm_password_reset(uid, token, new_password)`.
- `api/views.py` — `ChangePasswordView` (IsAuthenticated), `PasswordResetView` (AllowAny,
  throttled), `PasswordResetConfirmView` (AllowAny). `api/urls.py` — three routes.
- `adapter.py` — add `get_password_reset_url` analogous to `get_email_confirmation_url` if we
  route through allauth; otherwise build the URL in the service. (Decision: build in the
  service — the reset isn't an allauth flow.)
- Tests: `tests/test_password_management.py`.

**Dashboard**
- `features/identity/schemas.ts` — `changePasswordSchema`, `forgotPasswordSchema`,
  `resetPasswordSchema`.
- `features/identity/api.ts` + `queries.ts` — `changePassword`, `requestPasswordReset`,
  `confirmPasswordReset` + hooks.
- `components/ChangePasswordCard.tsx`; `routes/forgot-password.tsx`,
  `routes/reset-password.tsx`; link from `LoginForm`/login page; mount the card on `/account`.
- `locales/{en,ar}/common.json` — password keys.
- Tests beside each.

## Testing

- Backend: change with correct/incorrect current password (200 / 400 + session kept);
  reset request for known-verified / unknown email (both 200, email only for known) + throttle;
  confirm with valid / invalid / expired token (200 / 400); 100% line+branch; ruff/mypy/import-linter.
- Dashboard: each form submits the right payload + shows success (toast or page state) and
  inline errors; reset-password terminal states (success/invalid); `redirectIfAuthed` on the
  public routes; en/ar parity; jest-axe; tsc/biome clean.

## Out of scope

- Password strength meter / complexity rules beyond min-length 8 (YAGNI; can be a later slice).
- Rotating/invalidating other sessions on password change (single-session model today).
- Rate-limiting the change-password endpoint (it's authenticated + re-auth'd).
