# B9c — Registration, Google sign-in and code reset — Design

**Date:** 2026-10-03
**Status:** Approved after an independent spec review (orchestration spec PO-3); review findings
C1–C3, I1–I10 and M1–M13 applied 2026-10-03.
**Phase spec:** `2026-10-03-platform-extras-design.md`. This slice amends there, in its PR: the §3
row for B9c (Requires B9b; identifiers email and phone, no student ID) and B9-11 (the academy admin
enters the Google client; no escalation).
**Slice:** B9c — AUTH-008/009 student self-registration with the enhanced funnel, LEAD-004 waiting
list (approval or a code), AUTH-007 Google sign-in, AUTH-010 reset by one-time code, BR-20/21,
FLOW-001, FLOW-012.
**Requires:** B9b (`identity/signin.py`: `complete()`, the S-6a check order, failure limits, the
two-factor step, `sign-in-options/`).

## 1. Goal

A visitor to an academy's site can create their own student account — or, for minors, a guardian
account with children — and, once their email is confirmed and (if the academy wants) an admin
approves or they entered a code, sign in; students and parents can also sign in with Google and
recover a forgotten password with a one-time code by email or SMS. Each behind a switch, off by
default, and none of it usable to find out who has an account, squat an address, pump SMS or take
an account over.

## 2. Decisions

### 2.1 Registration

| # | Decision | Source |
|---|---|---|
| R-1 | **One registration page, `/app/register`, with the enhanced funnel.** Step 1: **an adult learner** (→ one student account that signs in) or **a parent for minors** (→ a parent account that signs in, plus one to five `[assumed]` children as students without logins). TH's 3-step "standard" form is the adult path's fields. | P1 AUTH-008, AUTH-009, BR-21, FLOW-001 |
| R-2 | Fields. Adult: full name\* (≤ 120), email\*, phone\* (E.164), date of birth\*, gender\*, country\*, password\* + confirmation (Django's password validators), consent\*. Parent: full name\*, email\*, phone\*, password\* + confirmation, consent\*; per child: full name\*, date of birth\*, gender\*; the children get the parent's country `[assumed]`, time zone and language. Both: the preferences of R-3 and a time zone (browser's, editable). The registrant's `preferred_language` is the page's language. Consent is recorded as `consented_at`. | P1 AUTH-008/009; review I1, M5, M6 |
| R-2a | **Age (BR-20):** adult means 18 or older on the academy's today `[assumed]`; the adult path refuses a younger date of birth ("Ask a parent to register you"); each child must be under 18. | P1 BR-20, BR-21; review M3 |
| R-3 | **Scheduling preferences are stored, not acted on:** desired start date, hours per week (1–40 `[assumed]`), preferred days (Mon=0…Sun=6), intro-call day + time (registrant's zone, stored UTC), teacher preference `any`·`male`·`female` `[assumed]`. Shown on the registration. Turning them into a trial request is B2's (shared decision: B2's trial intake may read them through `registration.services.preferences(registration_id)`). | P1 AUTH-009; ledger D8; review M11 |
| R-4 | New tenant app **`etqan.registration`** (`Registration`, `RegistrationCode`). People are created by a new identity service **`identity.services.register_person(role, *, full_name, email=None, phone="", password=None, timezone, language, profile) -> User`**: creates the user **inactive**, sets the password (validated) or an unusable one (children), creates the primary `EmailAddress` unverified and sends allauth's confirmation email (no invite). Parent profiles keep their existing fields (no gender/country added). | review I1; B9-5; CLAUDE.md (apps talk through services) |
| R-5 | **When an account becomes active:** a registered login account is activated by `registration.services` when **its email is confirmed** (allauth `email_confirmed` signal → `registration.services.on_email_confirmed`) **and** its registration is approved — whichever happens last. Children are activated with their parent. `StudentProfile.status` is not used for waiting: it stays the default `active`, while `Registration.status` and `is_active` carry "waiting"; inactive students cannot be scheduled or billed. | review C2, I2; TH §2.1 ("pending" tab, not a form value) |
| R-5a | **Never-confirmed registrations expire** after 7 days `[assumed]` (the daily job of `registration`, looping over academies): status `expired`, the users' `EmailAddress` rows removed and `User.email` cleared (users are never deleted), so the address can register again. | review C2 |
| R-6 | **Waiting list (`registration_waitlist`, existing switch, flipped in place to `Feature(..., built=True, requires=("self_registration",))`):** on → a confirmed registration stays `pending` until an admin approves it in People → Registrations (approve: accounts active, family created (R-6a), welcome email; reject with an optional reason: email, and the address is freed as in R-5a). Approve and reject lock the row and answer 409 unless `pending`; Approve is disabled until the email is confirmed. A valid **registration code** skips the wait. Off → registrations are approved at creation and active once the email is confirmed; codes are ignored (not spent). Registrations already pending when the switch goes off stay pending and approvable. | P1 SYS-002 flag; TH §1.3 #16; review I9, M8 |
| R-6a | **Families are created at approval** (when the accounts are active, so the parent qualifies as payer): `create_family(name="{parent full name}'s family" [assumed], student_ids, payer_id=parent)` when `families` is on, then `link_guardian` per child when `parents` is on. | review C1; spec 2026-09-27 families |
| R-6b | **Codes:** `RegistrationCode` (code stored lower-case, unique, 6–32 chars; label; `uses_left` null = unlimited; `expires_at` null; `is_active`). An unknown, inactive, expired or used-up code → `400 {"code": ["Invalid code."]}`, nothing created. A use is spent atomically (`UPDATE … SET uses_left = uses_left - 1 WHERE id = … AND (uses_left IS NULL OR uses_left > 0)`, 1 row or invalid). | review I9, M7 |
| R-7 | Switches: **`self_registration`** (new, `people`, off) gates the page, the API and the admin pages (People → Registrations, Settings → Registration codes). Off: "Registration is closed", API 404. The parent path also needs `parents`; without `families` the children are linked as guardianships only. | B9-2; review I9 |
| R-8 | **No account-existence leaks:** a registration whose email is already taken (any `EmailAddress` or `User.email`) answers the same `201 {"status": "received"}` and instead emails that address's owner "someone tried to register with your address — sign in or reset your password", at most once per address per day `[assumed]`. All successful responses are `201 {"status": "received"}`; the next step (confirm your email) is the same for everyone. | review I3 |
| R-8a | **Notices:** the registrant gets allauth's confirmation email (no name in it; generic greeting); after confirmation, "we received your registration" (pending) or a welcome email; admins get one email per **confirmed** registration with a link to People → Registrations. In-app notifications are B5's and not added. The nav shows a pending count (`pending_count` in the list response). | P1 FLOW-001; review I4, M9 |
| R-8b | **Abuse limits (no CAPTCHA, deliberately):** per IP 10 registrations/hour (successes count, unlike sign-in failures; e2e stays under it), per email address 3/day, a hidden honeypot field (filled → `201` and nothing created), names ≤ 120 characters. | review I4, M13; INT-009 is config-only evidence |
| R-8c | **Sign-in messages for registrants:** once the password matches (so nothing leaks to others), sign-in answers `403 {"code": "identity.email_unverified"}`, `"registration.pending"` or `"registration.rejected"` instead of "Invalid credentials". This extends B9b's S-6a: active → (inactive: registration reason if any) → refusal → verified → second factor. | review I10 |

### 2.2 Google sign-in

| # | Decision | Source |
|---|---|---|
| G-1 | Switch **`google_sign_in`** (new, `platform`, off). Each academy uses **its own Google OAuth client**, entered by an **admin** (ADMIN_ONLY) in Settings → Sign-in: client ID and secret (secret encrypted with `etqan.platform.secrets`, write-only). The page shows the exact redirect URI to register at Google. Data `identity.GoogleSignIn` (singleton per academy). | P1 AUTH-007, INT-008; TH §5.1 INT; review I8; amends B9-11 |
| G-2 | **One canonical host:** start and callback always run on the academy's primary domain (`frontend_url()`); `identity/google/start/` on another host redirects there first. Redirect URI: `https://<primary host>/api/v1/identity/google/callback/`. | review I7 |
| G-3 | **Flow:** authorization code with PKCE (S256), `state` (single use, in the session, 10 min) and `nonce`; scopes `openid email profile`; no `next`/return parameter. The ID token is verified with PyJWT against Google's JWKS (`PyJWKClient`, cached): `iss` ∈ {`accounts.google.com`, `https://accounts.google.com`}, `aud == client_id`, `exp`, `nonce`, and `email_verified == true`. | review I7 |
| G-4 | **Who it signs in:** only **students and parents** (B9-4), matched by `User.email` (case-insensitive) whose primary `EmailAddress` is **verified**; never secondary or unverified addresses, never `pending_email`. On the first Google sign-in the Google `sub` is stored (`identity.GoogleLink(user, sub)`); afterwards a different `sub` for that email is refused. Invited accounts (no password yet) and inactive accounts are refused with the generic message. A match signs in through B9b's `complete()` (two-factor still applies → `/app/login?step=2fa`). | review C3; B9-4 |
| G-5 | **No match:** with `self_registration` on, the server keeps `google_email` and `google_name` in the session (30 min) and redirects to `/app/register?google=1`, which prefills them; the email counts as confirmed only if the submitted email equals the session value. The registrant still sets a password (R-2). Otherwise → `/app/login?error=google` ("No account for this Google address"). | review I7 |

### 2.3 Reset by one-time code

| # | Decision | Source |
|---|---|---|
| C-1 | Switch **`code_reset`** (new, `platform`, off). "Forgot password" offers *email* or *phone*; the email-link reset stays. TH's student-ID identifier is not offered (no public student IDs). | P1 AUTH-010, FLOW-012 |
| C-2 | **Eligible accounts:** students and parents only (B9-4), `account_state == "active"`; for email, matched on verified `EmailAddress` rows (as `request_password_reset` does); for phone, `User.phone` (E.164). Never admins/staff, `no_login` children, invited, inactive or pending accounts. | review I5 |
| C-3 | **Request** `identity/password/code/ {channel, identifier}` → always `202`, same timing (work queued on commit). Only when an eligible account exists: a 6-digit code `[assumed]` (TH: 4), stored as HMAC-SHA256 under `SECRET_KEY`, valid 10 minutes; a new code invalidates earlier ones; sent by email or SMS. **No SMS is sent for a number without an eligible account.** Limits: 3 codes per identifier per hour, 10 requests per IP per hour, a per-academy daily SMS cap of 200 `[assumed]`. Identifiers are normalised (lower-case email, E.164) before counting. | review I5, I6 |
| C-4 | **Verify** `…/verify/ {channel, identifier, code}` → `200 {"accounts": [{id, full_name}]}` — the eligible accounts on that identifier, shown only now (no enumeration before the code). Does not spend the code. **Reset** `…/reset/ {channel, identifier, code, account_id, new_password}` re-checks and spends the code under `select_for_update`; `account_id` must be one of the eligible accounts; then sets the password (validators), ends the user's sessions, sends the existing password-changed security email, marks the email verified when the email channel was used, and does not sign in (`204`). 5 wrong codes (verify + reset together) end the code; a per-IP failure limit (B9b's counter, 20/hour) applies. Errors are one `400 {"code": ["Invalid or expired code."]}`. | review I5, I6 |
| C-5 | **SMS:** `etqan.platform.sms.send_sms(to, text)`; `SMS_BACKEND` = `console` (development), `locmem` (tests, an outbox) or `twilio` (production): Twilio's Messages REST API over `requests` (no SDK), keys from env `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM`; tested with mocked HTTP only, never a live call. The owner supplies the account at deploy time (E1 resolved: Twilio). `sign-in-options/` reports `code_reset: {email: bool, phone: bool}`; `phone` is true only when `code_reset` is on and either the backend is not used in production (`console`/`locmem` outside production) or it is `twilio` with all three keys set — so the phone option stays hidden in production until the keys exist. | B9-7; spec 2026-10-02 §8.1; ledger E1 (owner chose Twilio); review M10 |

### 2.4 Shared

| # | Decision | Source |
|---|---|---|
| X-1 | B9b's `identity/sign-in-options/` grows to `{phone_login, google, self_registration, code_reset: {email, phone}}`; there is no separate registration options route. | review M10 |
| X-2 | Access: resource `registration` ("Registrations" / "التسجيلات") `view_any`, `view`, `update`; resource `registration_code` ("Registration codes" / "رموز التسجيل") `view_any`, `create`, `update`; Google settings ADMIN_ONLY. | B9-3; review I8 |

## 3. Data

```text
registration.Registration
  kind            adult | parent
  registrant      FK User, PROTECT
  students        M2M User (adult: the registrant; parent: the children)
  start_on        date, null;  hours_per_week smallint, null;  preferred_days JSON list
  intro_call_at   datetime (UTC), null;  teacher_gender any|male|female
  code            FK RegistrationCode, SET_NULL, null
  consented_at    datetime
  status          unconfirmed | pending | approved | rejected | expired
  reject_reason   text;  decided_by FK User SET_NULL null;  decided_at null
  created_at
  (the time zone is the registrant's User.timezone)

registration.RegistrationCode
  code (lower-case, unique), label, uses_left null, expires_at null, is_active, created_at

identity.GoogleSignIn   (singleton) client_id, client_secret (encrypted), updated_by, updated_at
identity.GoogleLink     user (OneToOne), sub (unique), created_at
identity.ResetCode      channel, target (normalised), code_hmac, expires_at, tries, used_at, created_at
```

Statuses: `unconfirmed` until the registrant's email is confirmed; then `pending` (waitlist on, no
code) or `approved`.

## 4. API (under `/api/v1/`)

| Route | Method | Who | Notes |
|---|---|---|---|
| `registration/` | POST | anyone; `self_registration` | `201 {"status": "received"}`; field errors (children as `children[i].field`); R-8, R-8b |
| `registration/registrations/` | GET (`status`, paginated; `pending_count`) | `registration.view_any` | |
| `registration/registrations/<id>/` | GET | `registration.view` | preferences, email confirmed, code |
| `registration/registrations/<id>/approve/` · `…/reject/` | POST (`reason`) | `registration.update` | 409 unless `pending` |
| `registration/codes/` | GET, POST | `registration_code.view_any` / `.create` | |
| `registration/codes/<id>/` | PATCH | `registration_code.update` | |
| `identity/google/start/` | GET | anyone; `google_sign_in` | 302 |
| `identity/google/callback/` | GET | anyone | 302 to `/app/`, `/app/login?step=2fa`, `/app/register?google=1` or `/app/login?error=google` |
| `identity/google/settings/` | GET, PATCH | admins | `{client_id, configured, redirect_uri}`; secret write-only |
| `identity/password/code/` · `…/verify/` · `…/reset/` | POST | anyone; `code_reset` | C-3, C-4 |

All anonymous routes are SELF_SERVICE in the route table; switches as listed.

## 5. Dashboard

`/app/register` (who → details → preferences → "check your email"), Google buttons on the login and
register pages, "Forgot password" with the code path (channel, identifier, code, choose account, new
password), People → Registrations (status tabs, pending badge, detail, approve / reject), Settings →
Registration codes, Settings → Sign-in (Google client, redirect URI to copy), login messages for
R-8c codes. Locale files `{registration,signInGoogle,codeReset}.json`.

## 6. Testing

- Registration: adult and parent (with/without `families`, `parents`); ages; taken email → same 201
  + owner notice once a day; honeypot; per-IP and per-email limits; consent stored; activation only
  after confirmation **and** approval in both orders; family created at approval; codes (valid,
  invalid, expired, used up, concurrent last use, ignored while the waitlist is off); approve/reject
  (409 when not pending, emails, address freed on reject); expiry job frees addresses; sign-in
  messages R-8c; phone sign-in refused before activation; switches off → 404.
- Google: state/PKCE/nonce; bad `iss`/`aud`/`exp`/`nonce`/unverified email refused (mocked token
  endpoint and JWKS); verified primary matched; secondary/unverified/pending_email not matched;
  admin/staff/invited/inactive not matched; `sub` stored and enforced; new visitor prefill and
  session-bound confirmation; two-factor user → 2fa step; non-canonical host redirected.
- Code reset: eligibility (no admin/staff/no_login/inactive), no SMS for unknown numbers,
  same responses, limits, HMAC storage, new code invalidates old, verify does not spend, reset
  spends once under lock, shared-phone account choice after the code, sessions ended, email
  verified on the email channel, SMS daily cap, `sign-in-options` phone flag.
- e2e `dashboard/e2e/b9-registration.spec.ts`: an adult registers, confirms (Mailpit), waits, the
  admin approves, the student signs in; a parent registers two children with a code and, after
  confirming, signs in; a code reset by email.

## 7. Non-goals (B9c)

Booking the intro call or a trial (B2); in-app notifications (B5); sending real SMS in tests;
student public IDs; Apple/Facebook sign-in; CAPTCHA; Google sign-in for admins and staff.
