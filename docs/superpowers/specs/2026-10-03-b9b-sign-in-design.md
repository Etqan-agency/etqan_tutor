# B9b — Sign-in (two-factor, phone, quick login) — Design

**Date:** 2026-10-03
**Status:** Approved after an independent spec review (orchestration spec PO-3); review findings
C1, I1–I10 and M1–M12 applied 2026-10-03.
**Phase spec:** `2026-10-03-platform-extras-design.md` (B9-1…B9-11; slice table §3). This slice
amends B9-3 (`page.two_factor`, S-5) and B9-10 (timezone, S-8) there in the same change.
**Slice:** B9b — AUTH-003 two-factor authentication, AUTH-006 sign-in by email or phone (with the
login's technical fields, B9-10), AUTH-011 quick login (impersonation), AUTH-012 quick-login links.
**Requires:** none (B9 depends on B0 only).

## 1. Goal

Every academy user can protect their account with an authenticator app and sign in with their
phone number instead of their email; admins can open a teacher's, student's or parent's dashboard
as that person ("quick login") or email them a one-time sign-in link — each behind its own switch,
off by default — without opening any path to take an account over.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| S-0 | **allauth's server-rendered pages are removed.** `config/urls.py` no longer includes `allauth.urls`: every sign-in, email, password and two-factor action goes through `/api/v1/identity/` with this spec's rules. The one user of those pages, the staff-admin action "Send password-set email" (`identity/admin.py`), switches to `identity.services.send_password_reset` (the dashboard's `/app/reset-password` link). `LOGIN_URL` becomes `/app/login`. Every `/accounts/…` path answers 404 (tested). | review C1: `/accounts/email/`, `/accounts/password/set/`, `/accounts/2fa/…` are live, `login_required` only, and would bypass S-4, S-9 and S-14 |
| S-1 | **Two-factor = TOTP (authenticator app) plus 10 single-use recovery codes**, through `allauth.mfa` 65.x (`TOTP`, `RecoveryCodes`), driven from our API. No SMS or email codes. `MFA_TOTP_TOLERANCE = 1` (one step of clock drift). | P1 AUTH-003 (mechanism UNKNOWN; separate setup / challenge / OTP-verify pages); `[assumed]` TOTP |
| S-2 | Two-factor is **opt-in per user, for every role**, managed in My account: set up (QR code + secret), confirm with a first code, see the recovery codes once (copy / download), regenerate them, turn it off. Regenerate and turn-off accept a current TOTP code **or** a recovery code. No academy-wide "require 2FA" rule. | P1 AUTH-003 ("Secure your account", per account); `[assumed]` opt-in, every role (B9-4) |
| S-2a | **Secrets are encrypted at rest.** `MFA_ADAPTER` is a subclass of allauth's adapter whose `encrypt`/`decrypt` use Fernet under `ETQAN_SECRETS_KEY` (ledger D4's key), through a new `etqan.platform.secrets` helper (`encrypt(str) -> str`, `decrypt(str) -> str`) that any app may reuse; `get_totp_issuer` returns the academy's name. Missing key: a system check error in production, a fixed development key elsewhere. | review I5; ledger D4 |
| S-2b | **Lost device:** an admin can turn off a person's two-factor from their people page ("Turn off two-factor", confirm dialog); it is recorded as a security event (S-10). Not offered for the admin's own account (they use their recovery codes). | review I5; `[assumed]` |
| S-3 | **Sign-in with two-factor:** a correct password (or a valid link, S-11) for a user with an active TOTP authenticator does not sign in; it answers `200 {"mfa_required": true}` and keeps in the session `pending_user_id`, a fingerprint of the user's password hash and an expiry of 5 minutes. `POST identity/login/2fa/ {code}` accepts a TOTP code or a recovery code (each recovery code once). On success it re-checks the user (active, S-6a refusal, password unchanged), clears the pending keys and signs in (`200 me`). Errors: wrong code `400 {"code": ["Invalid code."]}`; no or expired pending sign-in `403 {"detail": …, "code": "identity.mfa_expired"}`; the 5th wrong code ends the pending sign-in (`403 … "identity.mfa_locked"`). | P1 AUTH-003 (`page_LoginTwoFactor`, `page_OTPVerify`); review M6, M9; `[assumed]` limits |
| S-4 | Switch `two_factor` (new, `platform`, off). Off: the My account card and its routes are hidden (404), and **sign-in ignores existing authenticators**: they are kept, not deleted (FT-4), so turning the switch off knowingly suspends everyone's second factor in that academy. Etqan alone sets switches (FT-1). | B9-2; spec 2026-09-30 FT-1, FT-4; review M12 |
| S-5 | `page.two_factor` stays **not in use**: two-factor is self-service for every role. B9-3 in the phase spec is amended accordingly in this slice's PR. | review I6; B9-3 |
| S-6 | **Sign in by email or phone.** The login form's one field (`identifier`) takes either; `email` is still accepted as an alias (used only when `identifier` is absent). A value with `@` is an email (today's path). Otherwise it is cleaned with `clean_phone`; a malformed value answers the same `400 {"non_field_errors": ["Invalid credentials."]}` as a wrong password. Candidates are found in SQL: active users with that phone and a usable password, at most 10 (`[assumed]` cap). When there are none, one dummy password hash is computed (equal timing). Exactly one candidate whose password matches signs in; none or several → "Invalid credentials." (two accounts sharing a phone **and** a password use their email). | P1 AUTH-006, FLOW-012; spec 2026-09-24 people P3-1 (E.164); review I8; `[assumed]` cap and ambiguity rule |
| S-6a | **One order of checks for every way in** (password, 2FA step, link, impersonation target): account active → `sign_in_refusal(user)` (e.g. a parent while `parents` is off) → email verified (email-identifier password sign-in only, as today) → second factor (S-3). | review I4 |
| S-7 | Phone sign-in is under switch `phone_login` (new, `platform`, off); off, a value without `@` is refused as today. It applies to every role (B9-4: one login). The login page learns it from `GET identity/sign-in-options/` (anonymous) → `{"phone_login": bool}`; no caching (a cheap read). | B9-2, B9-4; review M2 |
| S-8 | **Login technical fields (B9-10, amended):** each **password, 2FA-completed or link** sign-in records on the user `last_login_ip` (DRF's client IP with `NUM_PROXIES`), `last_login_device` (User-Agent: `iPad\|Tablet` → `tablet`; `Mobi\|Android\|iPhone` → `mobile`; any other non-empty → `desktop`; empty → `""`) and `last_login_timezone` (the browser's IANA zone sent by the login form, validated with `clean_timezone`, else `""`). The user's own `timezone` is never touched. Impersonation and "return" record none of them and leave `last_login` unchanged (S-9). Shown read-only on the student and teacher pages ("Last sign-in: device · IP · zone"); this edits identity's people payload, which B9 owns (`identity.auth` plus the identity app's own UI). | P1 AUTH-006 (hidden timezone, device_type, ip_address); TH §2.1 PEOPLE-001 "Technical" tab; review I2, I3, M10 |
| S-9 | **Quick login (impersonation):** an admin, or staff holding `quick_login.create` **and** the kind's `view` code (`student.view` · `teacher.view` · `parent.view`), opens a teacher's or student's dashboard as that person (TH shows it on students and teachers); parents too `[assumed]`, and then the `parents` switch must be on. Target must pass S-6a's first two checks and have `account_state` `active` or `invited` (not `inactive`, not `no_login`); never an admin or staff account; never while already impersonating. Mechanics: the server calls `login(request, target)` **first** (Django flushes the session for a different user), then writes `impersonator_id` and the impersonator's `get_session_auth_hash()` into the new session, then restores the target's previous `last_login` (no S-8 fields recorded). | P1 AUTH-011 (row action "دخول سريع" on students and teachers); review I1, I2, I4, M4, M5; security |
| S-9a | **While impersonating:** the session authentication re-checks on every request that the impersonator is still active, still an admin or holds `quick_login.create`, their auth hash is unchanged and the `quick_login` switch is on, and that the session is younger than 1 hour `[assumed]`; any failure logs the whole session out. `identity.services._end_sessions` (deactivation, password change) also ends sessions whose `impersonator_id` is that user. These are refused with `403 {"code": "identity.impersonating"}`: changing the password, emails, two-factor, and every route other phases mark as sensitive (S-9b). `logout/` ends everything. `POST identity/impersonation/stop/` signs the impersonator back in (same mechanics: `login` first, `last_login` restored for both) and returns their `me`. | review I1, I9 |
| S-9b | **Other phases can tell:** `etqan.platform.permissions.impersonator_id(request) -> int \| None` (reads the session key; no identity import) and a DRF permission `NotImpersonating`. Recorded as a shared decision: money-moving and messaging actions (payments, checkout, chat, broadcasts) refuse impersonated sessions with `NotImpersonating`. | review I9 |
| S-10 | **Security log:** every impersonation, return, link sent, link used and admin 2FA turn-off is a `SecurityEvent` (actor, target, kind, IP, at). Read-only for admins in Settings → Security log (TH has no such page `[assumed]`; it is the audit trail for S-9/S-11/S-2b). | review M5; security |
| S-11 | **Quick-login links:** an admin, or staff with `quick_login.create` and the kind's `view` code, sends selected teachers or students (TH: teachers row + bulk, students bulk), and parents `[assumed]` (with `parents` on), an email with a one-time link `app_url("/quick-login?token=…")`; at most 100 per call. Only `account_state == "active"` users who pass S-6a's first two checks receive one; the others are `skipped` with a reason `not_found` · `role` · `inactive` · `no_login` · `invited` · `refused` · `recent`. One email per person per 5 minutes (`recent`) `[assumed]`. One `link_sent` event per recipient. | P1 AUTH-012 (channel and expiry UNKNOWN); TH §4 U16; review I4, M5, M11 |
| S-11a | **Token:** a `PasswordResetTokenGenerator` subclass with its own `key_salt` (`etqan.identity.quick_login`), the academy's `schema_name` in the hashed value, and a 24-hour lifetime; like a reset token it hashes the password and `last_login`, so it **stops working once used** (signing in changes `last_login`), once the person signs in another way or changes their password. Exchange locks the user row (`select_for_update`) so two concurrent uses cannot both pass. If the person has two-factor, the exchange answers `{"mfa_required": true}` and `link_used` is recorded when the second step completes. A different user already signed in in that browser is replaced. | review M1; P1 AUTH-012 |
| S-11b | **The link page never acts on load:** `/app/quick-login?token=` strips the token from the address bar (`history.replaceState`), keeps it in memory, sends `Referrer-Policy: no-referrer`, and exchanges it only when the person clicks "Sign in" (so mail scanners that open links do not spend them). | review I10 |
| S-12 | Quick login and links are under switch `quick_login` (new, `people`, off). Access resource `quick_login` ("Quick login" / "الدخول السريع"), verb in use: `create`. | B9-2, B9-3 |
| S-13 | New User fields (`last_login_ip`, `last_login_device`, `last_login_timezone`) and the `SecurityEvent` model live in `identity` (B9 owns `identity.auth`); additive, nullable/blank, no data rewrite. | B9-5; ledger ownership |
| S-14 | **Rate limits count failures only** (a cache counter incremented on each failed attempt, reset on success): per client IP 50 failures/hour and per identifier 10 failures/hour on `login/`; 5 wrong codes per pending sign-in (S-3); per IP 20 failed `quick-login/` exchanges/hour. A locked identifier answers `429` with `Retry-After`. Knowing a password lets someone burn a user's 5 codes for that pending sign-in only (accepted). Successful sign-ins never count, so offices, families and e2e runs sharing an IP are unaffected. | review I7, M9 |

## 3. Data

```text
identity.User (new fields)
  last_login_ip         GenericIPAddressField, null
  last_login_device     CharField(10), blank, choices mobile|tablet|desktop
  last_login_timezone   CharField(64), blank

identity.SecurityEvent
  kind        CharField(16)  impersonate | return | link_sent | link_used | mfa_disabled
  actor       FK User, SET_NULL, null     (null for link_used)
  target      FK User, CASCADE
  ip          GenericIPAddressField, null
  at          DateTimeField(auto_now_add)
  ordering: -at, -id
```

Two-factor data is `allauth.mfa.models.Authenticator` (in SHARED and TENANT apps: rows live in each
academy's schema). Calls into allauth that read `allauth.core.context.request` are wrapped in
`context.request_context(request._request)`. Regenerating recovery codes deletes the old row, then
activates a new one (`RecoveryCodes.activate` returns an existing row otherwise).

## 4. API (under `/api/v1/identity/` unless the path starts with `/api/v1/`)

| Route | Method | Who | Response | Route table |
|---|---|---|---|---|
| `login/` | POST `{identifier, password, timezone?}` | anyone | `200 me` · `200 {"mfa_required": true}` · `400 non_field_errors` · `403` refusal · `429` | SELF_SERVICE |
| `login/2fa/` | POST `{code}` | pending session | S-3 | SELF_SERVICE |
| `sign-in-options/` | GET | anyone | `{"phone_login": bool}` | SELF_SERVICE |
| `me/2fa/` | GET | signed in | `{"enabled": bool, "recovery_codes_left": int}` | SELF_SERVICE, feature `two_factor` |
| `me/2fa/setup/` | POST | signed in, not enabled | `{"secret", "otpauth_url", "qr_svg"}` (secret held in the session until confirmed; `qr_svg` from allauth's `build_totp_svg`, rendered as a `data:` image) | SELF_SERVICE, `two_factor` |
| `me/2fa/confirm/` | POST `{code}` | signed in | `{"recovery_codes": [10]}` | SELF_SERVICE, `two_factor` |
| `me/2fa/recovery-codes/` | POST `{code}` | enabled | `{"recovery_codes": [10]}` | SELF_SERVICE, `two_factor` |
| `me/2fa/disable/` | POST `{code}` | enabled | `204` | SELF_SERVICE, `two_factor` |
| `/api/v1/people/<kind>/<id>/two-factor/disable/` | POST | admins | `204` (S-2b) | ADMIN_ONLY, `two_factor` |
| `/api/v1/people/<kind>/<id>/quick-login/` | POST (`kind` = `students` · `teachers` · `parents`) | S-9 | target's `me` | `quick_login.create`, feature `quick_login` (parents also refused in the view while `parents` is off) |
| `impersonation/stop/` | POST | impersonating session | actor's `me` | SELF_SERVICE |
| `/api/v1/people/quick-login-links/` | POST `{user_ids}` (1–100) | S-11 | `{"sent": int, "skipped": [{"id", "reason"}]}` | `quick_login.create`, `quick_login` |
| `quick-login/` | POST `{token}` | anyone | `200 me` · `200 {"mfa_required": true}` · `400 {"token": ["Invalid or expired link."]}` | SELF_SERVICE |
| `security-log/` | GET (paginated) | admins | events | ADMIN_ONLY, `quick_login` |

`me/` gains `impersonator: {id, full_name} | null`. The dashboard's `login()` result type becomes
`Me | {mfa_required: true}`.

## 5. Dashboard

- **Login page:** one "Email or phone" field while `phone_login` is on (from `sign-in-options/`),
  otherwise "Email" as today; sends the browser's IANA timezone. On `mfa_required` a second step
  asks for the 6-digit code with a "Use a recovery code" toggle; expired/locked errors return to
  step one with a message.
- **My account → Two-factor** card (switch `two_factor`): status, set up (QR image from `qr_svg`
  plus the secret for manual entry), confirm, recovery codes shown once with copy/download,
  regenerate, turn off.
- **People pages:** "Sign in as" on teacher, student and parent pages (switch `quick_login`, codes
  of S-9); "Send sign-in link" on those pages and as a bulk action on the three lists; "Turn off
  two-factor" for admins when the person has it; "Last sign-in: device · IP · zone".
- **App shell:** the impersonation banner with "Return to my account" whenever `me.impersonator`.
- **`/app/quick-login`** page (auth layout, S-11b).
- **Settings → Security log** (admins, switch `quick_login`).
- New locale files `dashboard/src/locales/{en,ar}/{twoFactor,quickLogin,signIn}.json`.

## 6. Testing

- Backend:
  - `/accounts/…` (login, email, password set/change/reset, 2fa) → 404; the staff-admin action sends
    our reset email.
  - TOTP setup/confirm/regenerate/disable with real codes (TOTP or recovery code), secrets
    encrypted in `Authenticator.data`, issuer = academy name; admin turn-off + event.
  - Login: with/without 2FA, recovery code single use, 5-code lock, expiry, re-checks at step two;
    switch off → authenticators ignored; S-6a order (inactive, parent refusal, unverified email).
  - Phone: one match; none (dummy hash called); two accounts different passwords; same password →
    refused; malformed → same 400; cap 10; switch off → refused.
  - Technical fields: IP behind one proxy, each device class, timezone validated, `timezone`
    untouched; none recorded on impersonate/return; `last_login` preserved.
  - Quick login: admin, staff with both codes, staff missing either (403), teacher (403); targets
    admin/staff/inactive/no_login refused, invited allowed; parents need `parents`; banner; credential
    routes 403 while impersonating; re-checks (actor deactivated, actor password changed, switch off,
    1-hour cap) log out; deactivating the actor ends the session; return; events.
  - Links: skipped reasons, `recent`, single use, two concurrent exchanges → one succeeds, expiry
    (time-frozen), invalid after password change / other sign-in, other academy → invalid, 2FA
    path, email language.
  - Failure-only throttles; route-table/registry tests; `impersonator_id` / `NotImpersonating`.
- Dashboard: two-step login; 2FA card states; banner and return; quick-login page (no request
  before the click, token stripped); actions hidden without switch/code.
- e2e `dashboard/e2e/b9-sign-in.spec.ts`: a teacher turns on two-factor (code computed in the test
  from the shown secret with a small RFC 6238 helper) and signs in with it; a student signs in by
  phone; an admin signs in as a student, sees the banner, returns; an admin sends a teacher a
  link, the link signs the teacher in once and fails the second time.

## 7. Non-goals (B9b)

SMS/email one-time codes; WebAuthn/passkeys; academy-wide 2FA enforcement; trusted devices;
impersonating admins or staff; passwordless phone sign-in (B9-9); Google sign-in and OTP reset
(B9c); a self-service "lost my authenticator" flow (admins turn it off, S-2b).
