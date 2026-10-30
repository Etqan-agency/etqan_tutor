---
title: "Sign-in and account security"
---

How people get into an academy's dashboard. This covers session login by email or phone, two-factor sign-in, password resets (by link or by code), Google sign-in, email address management, quick login (impersonation) and quick-login links, and the security log. Every academy role (admin, staff, teacher, student, parent) signs in through the same `/app/login` page on the academy's host. Etqan staff are different: they sign in only to the Django admin on the bare base domain (`config/urls_public.py`), and none of these API routes exist there.

## Concepts

All tables are in the academy schema unless noted otherwise.

| Model | Purpose |
|---|---|
| `identity.User` | `email` is the Django `USERNAME_FIELD`. `phone` is a second identifier. `last_login_ip` / `_device` / `_timezone` are written on each real sign-in. |
| allauth `EmailAddress`, `EmailConfirmation` | A user's addresses and their verification. Keys are stored, not HMAC (`ACCOUNT_EMAIL_CONFIRMATION_HMAC = False`), so a key can't cross academies. |
| allauth `mfa.Authenticator` | TOTP and recovery codes. Secrets are Fernet-encrypted by `identity/mfa.py:EtqanMFAAdapter` using `ETQAN_SECRETS_KEY`. |
| `identity.SecurityEvent` | Audit row: `impersonate`, `return`, `link_sent`, `link_used`, `mfa_disabled` (actor, target, IP, at). |
| `identity.ResetCode` | One-time 6-digit reset code. Only an HMAC (bound to schema, channel and target) is stored. Lasts 10 minutes, 5 tries, and a newer code replaces it. |
| `identity.GoogleSignIn` | The academy's own Google OAuth client (single row, pk 1). The secret is a Fernet token and write-only. |
| `identity.GoogleLink` | The Google `sub` a person first signed in with. A different `sub` is refused afterwards. |

Sessions are Django DB sessions (`django.contrib.sessions`, in each schema). DRF uses `identity/authentication.py:SessionAuthentication`. Cookies are HTTP-only. The `csrftoken` cookie is readable by JavaScript, and the dashboard's axios client (`dashboard/src/lib/api.ts`) sends it back as `X-CSRFToken`. Public pages call `GET identity/csrf/` before they POST. DRF itself checks CSRF only for a signed-in session, so the views that sign someone in (`login/`, `login/2fa/`, `quick-login/`) add `platform/permissions.py:CsrfChecked`: without the token, or from another origin, they answer 403 `CSRF Failed: …` (login CSRF, ETQAN-QA-006). The dashboard fetches `identity/csrf/` before each of them.

allauth's server-rendered pages are **not** mounted (`config/urls.py`). Everything goes through `/api/v1/identity/`. `CeleryAccountAdapter.is_open_for_signup` returns `False`. The adapter also sends allauth's emails through `queue_email` and points verification links at `/app/verify-email?key=…`.

## How it works

### Password sign-in (`identity/signin.py`, `LoginView`)
1. `POST identity/login/` with `identifier` (`email` is accepted as an alias), `password` and the browser's `timezone`.
2. **Rate limits** (`identity/limits.py`) count failures only:
   - 50 per IP per hour, 10 per identifier per hour. A blocked request gets 429 with `Retry-After`.
   - A success clears the identifier's counter only.
   - Counters live in the tenant-keyed Redis cache.
3. **Identification** (`signin.identify`):
   - An identifier containing `@` is treated as an email and checked through Django `authenticate`.
   - Anything else is treated as a phone number. That path works only while `phone_login` is on. It checks up to 10 accounts with that phone and requires exactly one password match; if several match, an active account wins over an inactive one.
4. **Checks, in order** (S-6a):
   1. The account is active. If it is inactive, the user is told why only when the password matched and a reason is registered: `identity.email_unverified`, `registration.pending` or `registration.rejected` (see `signin.register_inactive_reason`). Otherwise the response is "Invalid credentials."
   2. The academy lets them in (`services.sign_in_refusal`). A parent is refused while `parents` is off.
   3. When signing in by email, that address must be verified.
   4. Second factor.
5. **Completion** (`signin.complete`): calls `login()`, clears any impersonation mark, and records IP, device (`identity/devices.py`) and timezone. The response is the `me/` payload.

### Two-factor (`identity/twofactor.py`)
- Available while the `two_factor` switch is on. Every role can opt in (self-service). The routes 404 while the switch is off, and sign-in then ignores existing authenticators (they are kept, not deleted).
- **Set-up** returns a secret, an otpauth URL and a QR SVG. The secret is held encrypted in the session until the first code confirms it. Confirming returns 10 recovery codes.
- **Regenerating codes** and **turning 2FA off** each need a current code.
- **Sign-in with 2FA:**
  - A correct password or link answers `{"mfa_required": true}` and stores a pending sign-in in the session (`signin.start_pending`: 5 minutes, fresh session key, bound to the password hash).
  - `POST identity/login/2fa/` accepts a TOTP code or an unused recovery code.
  - Wrong codes are limited to 5 per pending sign-in (then `identity.mfa_locked`) and 10 per person per hour.
- **Lost device:** an admin can turn off another person's 2FA (`twofactor.admin_disable`). This is logged as `mfa_disabled`. Admins can't do this for their own account, and staff can never do it.
- If no `ETQAN_SECRETS_KEY` is set, set-up answers 503 `identity.mfa_unavailable`.

### Password reset
- **By link:** `password/reset/` emails a link to a verified address and stays silent otherwise. For an invited account, the invite is re-sent instead. `password/reset/confirm/` sets the password and verifies the primary email. It sends a security alert unless this was the first activation. Throttle: 5 per hour per email (`EmailScopedThrottle`).
- **By code** (`identity/codereset.py`, switch `code_reset`): only for active students and parents.
  1. `password/code/` always answers 202. The lookup and sending run in the Celery task `identity.tasks.issue_reset_code` under `academy_context`, so the request doesn't reveal whether an account exists.
  2. The code goes out by email or by SMS (`etqan.platform.sms`). The phone option is offered only when `sms.phone_available()`. SMS is capped at 200 per academy per day.
  3. `verify` returns the accounts the code can reset (several students or parents can share one phone).
  4. `reset` sets the chosen account's password and signs it out everywhere. It never signs the person in.
  5. Limits: 10 requests per IP per hour, 3 codes per identifier per hour, 20 wrong codes per IP per hour.

### Google sign-in (`identity/google.py`, switch `google_sign_in`)
- Offered only when the switch is on **and** the admin has entered a client in Settings → Sign-in.
- The flow uses OAuth with PKCE and a nonce. `start` redirects to the academy's canonical host first.
- **Callback:** if the address matches a student's or parent's verified primary email, that person is signed in (or sent to `/app/login?step=2fa`) and the Google `sub` is linked.
- If nothing matches and `self_registration` is on, the email and name are kept in the session for 30 minutes and the browser goes to `/app/register?google=1`. Otherwise it goes to `/app/login?error=google`.

### Email addresses (`me/emails/`)
- Adding an address or making one primary needs the current password.
- The primary address can't be removed.
- Changing the password or the primary address sends a security alert to the old primary address.

### Quick login (impersonation) (`identity/impersonation.py`, switch `quick_login`)
- **Who can do it:** an admin, or staff holding `quick_login.create` **and** the target kind's `view` code. Targets can only be teachers, students or parents.
- `start` signs in as the target without stamping `last_login`, writes `etqan.impersonator` (`id`, auth hash, `since`) into the session, and logs `impersonate`.
- On every request, `SessionAuthentication` re-checks `impersonation.session_valid`. The session must still have:
  - an active impersonator
  - an unchanged auth hash
  - permission to impersonate
  - `quick_login` switched on
  - an age of at most 1 hour

  If any check fails, the user is signed out.
- `NotImpersonating` (in `etqan.platform.permissions`) blocks credential, money and messaging actions while impersonating. For example, `me/password/`, `me/emails/` writes, phone edits and every `me/2fa/` route return 403 `identity.impersonating`.
- `impersonation/stop/` signs the original user back in and logs `return`.

### Quick-login links (`identity/links.py`)
- Each person gets a one-time token emailed to `/app/quick-login?token=…`. The token's lifetime is 24 hours. It uses its own salt and includes the schema in its hash, and a password change or login invalidates it.
- Each person gets at most one link per 5 minutes. Staff must hold `view` for every kind in the batch, or the whole call is refused.
- The link page never acts on load. It strips the token from the address bar and exchanges it only when the user clicks.
- Invalid links count against the IP (20 per hour).

## API

All paths are under `/api/v1/identity/` unless shown otherwise.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `csrf/` | anyone | Set the `csrftoken` cookie |
| GET | `sign-in-options/` | anyone | What the login page offers: `phone_login`, `google`, `self_registration`, `waitlist`, `parent_registration`, `code_reset.{email,phone}` |
| POST | `login/` | anyone | Email/phone + password; returns `me` or `{"mfa_required": true}` |
| POST | `login/2fa/` | pending sign-in | Second factor |
| POST | `logout/` | signed in | Clear the session |
| POST | `resend-verification/`, `verify-email/` | anyone | Email verification (silent on unknown addresses) |
| POST | `password/reset/`, `password/reset/confirm/` | anyone | Reset by link (also used to accept invites) |
| POST | `password/code/`, `password/code/verify/`, `password/code/reset/` | anyone, `code_reset` | Reset by code |
| POST | `me/password/` | signed in, not impersonating | Change password |
| GET, POST | `me/emails/` | signed in (POST: not impersonating) | List / add addresses |
| DELETE | `me/emails/<id>/` | not impersonating | Remove a non-primary address |
| POST | `me/emails/<id>/primary/` | not impersonating | Make an address primary |
| GET | `me/2fa/` | `two_factor` | Status and recovery codes left |
| POST | `me/2fa/setup/`, `me/2fa/confirm/`, `me/2fa/recovery-codes/`, `me/2fa/disable/` | `two_factor`, not impersonating | 2FA self-service |
| GET | `google/start/`, `google/callback/` | anyone, `google_sign_in` | Browser redirects |
| GET, PATCH | `google/settings/` | admins | Client ID and write-only secret; shows the `redirect_uri` |
| POST | `quick-login/` | anyone | Exchange a link token |
| POST | `impersonation/stop/` | impersonated session | Return to your own account |
| GET | `security-log/` | admins, `quick_login` | `SecurityEvent` rows, paged |
| POST | `/api/v1/people/<students\|parents\|teachers>/<id>/quick-login/` | `quick_login.create` + kind `view` | Start impersonating |
| POST | `/api/v1/people/quick-login-links/` | `quick_login.create` | Email links to `user_ids` |
| POST | `/api/v1/people/<kind>/<id>/two-factor/disable/` | admins, `two_factor` | Lost-device turn-off |

## Dashboard

- Public routes:
  - `routes/login.tsx`: `LoginForm`, `TwoFactorStep`, `GoogleSignInButton`, and `?step=2fa` / `?error=google`
  - `forgot-password.tsx`: link reset, plus `CodeResetFlow`
  - `reset-password.tsx`: also accepts invites
  - `verify-email.tsx`, `verify-pending.tsx`
  - `quick-login.tsx`: `features/quicklogin/QuickLoginPage`
- `_authed` uses `requireAuth`, which redirects to `/login` when `me/` fails.
- `/account`: `EmailAddresses`, `ChangePasswordCard`, and `features/twofactor/TwoFactorCard`. These are hidden while impersonating.
- `features/quicklogin`:
  - `ImpersonationBanner` (shown in `AppShell`)
  - `QuickLoginActions` and `LastSignIn` (on person pages, via `people/AccountActions.tsx`)
  - `SendLinksButton` (teacher and parent lists)
  - `SecurityLogPage` at `/settings/security-log` (admins, `quick_login`)
- `/settings/sign-in`: `GoogleSettingsCard` (admins, `google_sign_in`).

## Background jobs

- `identity.tasks.issue_reset_code(schema_name, channel, target)`: queued once per code-reset request and run inside `academy_context`.
- Every account email (invite, reset, verification, alerts, link) goes through `integrations.services.queue_email` after commit.

There is no periodic job. Pending sign-ins and the Google prefill expire inside the session.

## Configuration

- **Switches** (`platform/features.py`, all default off): `two_factor`, `phone_login`, `quick_login`, `google_sign_in`, `code_reset`. Also relevant: `parents` and `self_registration`.
- **Env:**
  - `ETQAN_SECRETS_KEY`: Fernet key for MFA and the Google secret.
  - `SMS_BACKEND` (`console` / `locmem` / `twilio`), plus `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM`.
  - `DJANGO_CACHE_URL`: Redis that holds the failure counters.
  - `DJANGO_ACCOUNT_MAX_EMAIL_ADDRESSES`.
  - `CSRF_TRUSTED_ORIGINS` (production).
- **Settings:** `ACCOUNT_EMAIL_VERIFICATION = "mandatory"`, `MFA_TOTP_TOLERANCE = 1`, `REST_FRAMEWORK["NUM_PROXIES"] = 1` (client IP read from Caddy's `X-Forwarded-For`), `LOGIN_URL = "/app/login"`.

## Code map

- `backend/etqan/identity/signin.py`: identification, checks, pending 2FA, completion
- `backend/etqan/identity/limits.py`: failure counters
- `backend/etqan/identity/twofactor.py`, `mfa.py`
- `backend/etqan/identity/impersonation.py`, `links.py`
- `backend/etqan/identity/codereset.py`, `tasks.py`, `backend/etqan/platform/sms.py`
- `backend/etqan/identity/google.py`
- `backend/etqan/identity/authentication.py`, `adapter.py`, `signals.py`, `devices.py`
- `backend/etqan/identity/api/urls.py`, `views.py`, `serializers.py`
- `backend/etqan/platform/permissions.py`: `NotImpersonating`, `impersonator_id`, `IMPERSONATOR_KEY`
- `dashboard/src/features/identity/`, `dashboard/src/features/twofactor/`, `dashboard/src/features/quicklogin/`
- `dashboard/src/lib/api.ts`: CSRF header

## Design history

- [People & catalogue design](../superpowers/specs/2026-09-24-people-catalogue-design.md): the invite / set-password flow, email-less students, admin-sent resets.
- [B9b sign-in](../superpowers/specs/2026-10-03-b9b-sign-in-design.md) and [plan 23](../superpowers/plans/2026-10-03-plan-23-sign-in.md): removed allauth pages, 2FA, phone login, quick login, links, security log, failure-only limits.
- [B9c registration](../superpowers/specs/2026-10-03-b9c-registration-design.md) and [plan 28](../superpowers/plans/2026-10-04-plan-28-registration.md): reset by code (C-1…C-5), Google sign-in (G-1…G-5), registrant refusal reasons (R-8c).
- [Feature toggles](../superpowers/specs/2026-09-30-feature-toggles-design.md): `sign_in_refusal` (parents off) and the 404 behaviour of switched-off routes.
