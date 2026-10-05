# Plan 28 — B9c Registration, Google sign-in and code reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B9b (merged first: `identity/signin.py` — `find_user`, `refusal`, `start_pending`, `complete`, `client_ip`, code-check budget; `identity/limits.py`; `identity/links.py` pattern; `sign-in-options/`; `etqan.platform.secrets`).

**Goal:** Ship slice B9c: student self-registration with the enhanced funnel (adult or parent-with-children), confirmation-then-approval activation with a waiting list and registration codes, Google sign-in for students and parents, and password reset by one-time code over email or SMS (Twilio backend, console/test backends) — each off by default.

**Architecture:** New tenant app `etqan.registration` (models `Registration`, `RegistrationCode`; services; API; daily expiry job) that creates people only through new identity services (`register_person`) and existing ones (`create_family`, `link_guardian`). Identity gains Google sign-in (`GoogleSignIn`, `GoogleLink`, `identity/google.py`), code reset (`ResetCode`, `identity/codereset.py`) and an inactive-reason hook so sign-in can name pending/rejected registrations without importing `registration`. `etqan.platform.sms` sends SMS through a backend chosen by settings. Dashboard: `/app/register`, Google buttons, forgot-password code path, People → Registrations, Settings → Registration codes and Settings → Sign-in.

**Tech Stack:** Django 6 + DRF + django-tenants + allauth (email confirmation) + PyJWT (Google ID tokens, `PyJWKClient`) + requests (Google token endpoint, Twilio REST); React + TanStack Router/Query + zod + i18next + vitest + Playwright.

**Spec:** `docs/superpowers/specs/2026-10-03-b9c-registration-design.md` (R-1…R-8c, G-1…G-5, C-1…C-5, X-1, X-2). Read it before each task. Phase spec: `docs/superpowers/specs/2026-10-03-platform-extras-design.md`.

## Global Constraints

- Switches, `built=True`, default off, under `# ── phase B9 ──` (after B9b's): `self_registration` (people), `google_sign_in` (platform), `code_reset` (platform). `registration_waitlist` is flipped in place to `Feature(..., built=True, requires=("self_registration",))`. Dashboard `FeatureCode` gains them in a `// B9c` block.
- New tenant app `etqan.registration` under the B9 markers (TENANT_APPS, api_router `path("registration/", …)`, import-linter forbidden list + a contract: imports `etqan.platform`, `etqan.identity.services` only). Identity models added only in `identity` (B9 owns `identity.auth`): `GoogleSignIn`, `GoogleLink`, `ResetCode`.
- Access resources under the B9 marker: `registration` (`view_any`, `view`, `update`), `registration_code` (`view_any`, `create`, `update`). Google settings route ADMIN_ONLY. Anonymous routes SELF_SERVICE. `# B9c` blocks in unmarked lists.
- Exact values: adult age 18; children 1–5; names ≤ 120; hours/week 1–40; preferred days 0–6 (Mon=0); unconfirmed expiry 7 days; registration limits 10/IP/hour (successes count) and 3 per email address/day; taken-email notice ≤ 1 per address per day; Google state/PKCE 10 minutes, prefill session 30 minutes; reset code 6 digits, 10 minutes, 5 tries (verify + reset together), 3 codes per identifier per hour, 10 requests per IP per hour, per-academy SMS cap 200 per day, code-check IP failure limit 20/hour; family name `"{parent full name}'s family"`.
- Status codes/strings (exact): sign-in 403 codes `identity.email_unverified`, `registration.pending`, `registration.rejected`; registration success `201 {"status": "received"}`; code reset errors `400 {"code": ["Invalid or expired code."]}`; approve/reject on non-pending 409.
- SMS: `etqan.platform.sms.send_sms(to: str, text: str) -> None`; `SMS_BACKEND` = `console` | `locmem` | `twilio`; Twilio via REST with `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM`; tests mock HTTP only, never live. `sign-in-options` `code_reset.phone` true only when `code_reset` is on and (backend not used in production — `console`/`locmem` with `DEBUG` or test settings) or (`twilio` with all three keys set).
- Business logic in services; FKs via `settings.AUTH_USER_MODEL`; stored instants UTC; emails in the recipient's language (en + ar templates) through identity's email helpers.
- New locale files only: `dashboard/src/locales/{en,ar}/{registration,signInGoogle,codeReset}.json`, key-equal.
- Run gates one at a time (focused pytest via `just _compose run --rm -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan django pytest <paths>`; `just test-backend`; `just lint-backend`; `just check-boundaries`; dashboard vitest, `pnpm test:coverage`, `just test-frontend`, `just lint-frontend`; `just e2e`).
- Coverage: backend ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.

## Review Focus

1. **Someone registers with an address that already has an account** → the same `201 {"status": "received"}`, the owner gets one notice a day, nothing is created (Task 4 `test_taken_email_answers_the_same_and_notifies_once_a_day`).
2. **A registrant confirms their email while the waiting list is on, then signs in by phone** → refused with `registration.pending` (Task 5 `test_phone_sign_in_refused_until_approved`).
3. **A Google account whose email matches an admin, or an unverified secondary address** → not signed in, generic message (Task 7 `test_admin_or_secondary_not_matched`).
4. **Code reset requested for a phone with no eligible account** → `202`, no SMS sent, nothing stored (Task 8 `test_unknown_phone_sends_nothing`).
5. **Two people use the last use of a registration code at the same moment** → exactly one is approved at once (Task 3 `test_last_code_use_is_spent_once`).

---

### Task 1: Switches, sign-in options, SMS

**Files:** `backend/etqan/platform/features.py`, `backend/etqan/platform/sms.py` (+ `tests/test_sms.py`), `backend/config/settings/{base,test,production}.py` (`SMS_BACKEND` default `console` in base/local, `locmem` in test, `twilio` read from env in production with default `console`; Twilio keys from env, default ""), `backend/etqan/identity/signin.py` + `SignInOptionsView` (X-1 fields), `backend/etqan/platform/tests/test_features.py`, dashboard `schemas.ts` FeatureCode.

**Interfaces:** `sms.send_sms(to, text)`; `sms.outbox: list[tuple[str, str]]` (locmem); `sms.phone_available() -> bool` (the C-5 rule); `sign-in-options/` → `{"phone_login", "google", "self_registration", "code_reset": {"email", "phone"}}` (`google` = switch on AND a configured client — Task 7 adds the client model; until then `google` = switch only, Task 7 refines).

- [ ] Tests: switches off by default, `registration_waitlist` requires `self_registration`; console logs (caplog), locmem outbox, twilio posts to `https://api.twilio.com/2010-04-01/Accounts/<sid>/Messages.json` with basic auth and `To`/`From`/`Body` (mock `requests.post`), twilio HTTP error → logged, raises `sms.SmsError`; `phone_available` matrix; sign-in-options payload. Commit (backend + dashboard).

### Task 2: `identity.services.register_person` and the inactive-reason hook

**Files:** `backend/etqan/identity/services.py` (new function, additive), `backend/etqan/identity/signin.py` (hook), `LoginView` (R-8c codes), tests `identity/tests/test_register_person.py`, `test_signin_registrants.py`.

**Interfaces:**
- `register_person(role: str, *, full_name: str, email: str | None = None, phone: str = "", password: str | None = None, timezone: str, language: str, profile: dict) -> User` — creates the user **inactive**; password validated with Django's validators (`ValidationError` field `password`) or unusable when None; with an email, creates the primary `EmailAddress` unverified and sends allauth's confirmation email (no invite); profile via the existing `create_person` internals (reuse, don't duplicate: factor a private helper if needed).
- `signin.register_inactive_reason(fn: Callable[[User], str | None]) -> None` — registration calls it in `AppConfig.ready()`; `signin.inactive_reason(user) -> str | None`.
- `LoginView`: after the password matches an **inactive** user (today: "Invalid credentials"), answer `403 {"detail", "code"}` with `identity.email_unverified` when the primary email is unverified, else the hook's code (`registration.pending` / `registration.rejected`), else the old 400. Only after the password matched (no leak).

- [ ] Tests: inactive user created, password validators, confirmation email sent in the person's language, no invite; profile fields; R-8c codes only with the right password; wrong password still 400; existing inactive (deactivated) staff/teacher still 400 "Invalid credentials" (no hook reason). Commit.

### Task 3: `etqan.registration` models and services

**Files:** create `backend/etqan/registration/{__init__,apps,models,services,tasks}.py`, migrations, tests; settings TENANT_APPS (B9 marker); pyproject (both markers); access registry resources; `CELERY_BEAT_SCHEDULE` entry `"registration.expire_unconfirmed"` daily 03:15 (add after the last entry with a `# B9c` comment).

**Interfaces (services):**
- `register(*, kind, data: dict, code: str | None, request) -> Registration | None` — None for the honeypot and taken-email paths (caller answers the same 201). Creates people via `register_person` (adult: student with login; parent: parent with login + children via `register_person("student", email=None, password=None, ...)` with the parent's country/timezone/language), stores preferences, `consented_at`; validates ages (adult ≥ 18 on `clock.today()`, children < 18), children 1–5; code: when `registration_waitlist` is on and a code is given, spend it atomically (`RegistrationCode.objects.filter(pk=…, is_active=True).filter(Q(uses_left__isnull=True) | Q(uses_left__gt=0)).filter(Q(expires_at__isnull=True) | Q(expires_at__gt=now)).update(uses_left=F("uses_left") - 1)` with the null case handled — write it so unlimited codes are not decremented) else `400 {"code": ["Invalid code."]}`; when the waitlist is off, codes are ignored. Status `unconfirmed`.
- `on_email_confirmed(user)` (connected to allauth's `email_confirmed` signal in `apps.ready()`): the registration whose registrant is the user → `pending` (waitlist on and no code) or `approved`; if `approved`, `_activate(registration)`; send the received/welcome email; email the academy's admins once (R-8a).
- `approve(registration, *, by)`, `reject(registration, *, by, reason="")` — `select_for_update`; 409 unless `pending`. Approve is refused with 400 `registration.unconfirmed` until the registrant's email is confirmed (the UI disables the button); otherwise `_activate` + welcome email. Reject: rejected email + `_free_addresses`.
- `_activate(registration)`: users active; for parent kind: `create_family(name=f"{parent.full_name}'s family", student_ids=…, payer_id=parent.pk)` when `families` is on, then `link_guardian` per child when `parents` is on.
- `_free_addresses(registration)`: delete the users' `EmailAddress` rows, clear `User.email` (users kept inactive).
- `expire_unconfirmed()` (task loops academies with `for_each_academy`): `unconfirmed` older than 7 days → `expired` + `_free_addresses`.
- `inactive_reason(user) -> str | None` registered with the signin hook: pending → `registration.pending`, rejected → `registration.rejected`.
- `preferences(registration_id) -> dict` (ledger D21 for B2).
- Codes CRUD: `create_code(code, label, uses_left, expires_at, by)`, `update_code(...)`; codes stored lower-case, unique.

- [ ] Tests: adult and parent paths (with/without `families`, `parents`), ages, children limits, preferences stored, consent; codes valid/invalid/expired/inactive/case-insensitive/unlimited, `test_last_code_use_is_spent_once` (two spends of a 1-use code → one success); confirmation with waitlist off → approved + active, on → pending; approve before confirmation refused; approve after → active, family created with the parent as payer (the parent is active when `create_family` runs); reject → email + addresses freed (re-register with the same email works); expiry job; hook codes; admin emails once per confirmed registration. Commit.

### Task 4: Registration API and abuse limits

**Files:** `backend/etqan/registration/api/{serializers,views,urls}.py`, route table `# B9c` entries, `identity/emails.py` subjects + `templates/email/registration/{received,welcome,rejected,taken,admin_new}.{en,ar}.txt`, tests.

- `POST registration/` (anonymous; `self_registration`): serializer validates R-2 fields (children as a list; errors as `children[i].field`), honeypot field `website` (filled → 201, nothing created), limits: `REGISTRATION_IP` (10/3600, counts successes) and per-email (3/86400) using `identity.limits.FailureLimit`-style counters (add a `RateLimit` for successes in `identity/limits.py` additively, or a small one in registration); taken email → same 201 + `taken` notice once per address per day (cache key); always `201 {"status": "received"}`.
- `GET registration/registrations/?status=&page=` (`registration.view_any`, includes `pending_count`), `GET …/<id>/` (`registration.view`; registrant, students, preferences, `email_confirmed`, code label), `POST …/<id>/approve/`, `POST …/<id>/reject/ {reason}` (`registration.update`).
- `GET/POST registration/codes/`, `PATCH registration/codes/<id>/`.
- [ ] Tests: per route × role (admin, staff with/without codes, teacher/student/parent 403, anonymous for the public route), switch off → 404 after the permission check, honeypot, limits, taken email same response + one notice/day, field errors shape, pending_count. Commit.

### Task 5: Sign-in integration tests for registrants

**Files:** tests only (and any small fix they reveal) in `identity` / `registration`.
- [ ] `test_phone_sign_in_refused_until_approved` (phone_login on): confirmed + pending → 403 `registration.pending` via phone and email; approved → signs in; unconfirmed → `identity.email_unverified`; rejected → `registration.rejected`. Commit.

### Task 6: Code reset (email and SMS)

**Files:** `backend/etqan/identity/codereset.py`, `ResetCode` model + migration, views/urls `identity/password/code/`, `…/verify/`, `…/reset/`, email templates `reset_code.{en,ar}.txt`, tests.

**Interfaces:** `request_code(channel, identifier, request) -> None` (always 202; eligibility C-2; queue on commit; no row/SMS when no eligible account); `verify(channel, identifier, code) -> list[User]`; `reset(channel, identifier, code, account_id, new_password, request) -> None`. Codes: `secrets.randbelow(10**6)` zero-padded; stored `hmac.new(SECRET_KEY, f"{schema}:{channel}:{target}:{code}", sha256)`; new code invalidates older ones for the target; 5 tries across verify+reset (`tries` incremented with `F()` under `select_for_update`); limits per identifier (3 codes/hour), per IP (10 requests/hour), per academy SMS/day (200, cache counter with the academy schema and the date), code-check IP failures (20/hour). Reset: password validators, `_end_sessions`, password-changed security email, email channel marks the `EmailAddress` verified, does not sign in.
- [ ] Tests: eligibility (no admin/staff/no_login/inactive/invited/pending); `test_unknown_phone_sends_nothing`; same 202 timing path (queued on commit); verify lists only eligible accounts on a shared phone; verify doesn't spend; reset spends once under lock; wrong account id → 400; 5 tries; new code invalidates; limits; SMS cap; HMAC storage (no plaintext code in the DB); switch off → 404; phone channel hidden (`phone_available` false) → phone requests answer 202 and send nothing. Commit.

### Task 7: Google sign-in

**Files:** `backend/etqan/identity/google.py`, models `GoogleSignIn` (singleton: `client_id`, `client_secret` encrypted with `etqan.platform.secrets`, `updated_by`, `updated_at`), `GoogleLink` (`user` OneToOne, `sub` unique, `created_at`) + migration; views `google/start/`, `google/callback/`, `google/settings/` (ADMIN_ONLY); `sign-in-options` `google` = switch on and configured; tests with mocked token endpoint and JWKS (generate an RSA key in the test, serve its JWK via a patched `PyJWKClient.get_signing_key_from_jwt`).

**Rules (G-2…G-5):** canonical host = the academy's primary domain via `etqan.platform.frontend.frontend_url()` (start on another host → 302 to the canonical start URL); `state` (single use, session, 10 min), PKCE S256 verifier in the session, `nonce`; scopes `openid email profile`; no `next`. Callback: exchange the code (`requests.post` to `https://oauth2.googleapis.com/token`), verify the ID token with `jwt.decode` (RS256, `audience=client_id`, `issuer` in the two allowed values, `exp`), check `nonce` and `email_verified`. Match: role student/parent, `User.email` iexact whose primary `EmailAddress` is verified, active, not invited (usable password); `GoogleLink` stored on first sign-in, a different `sub` later refused. Match → `signin.complete` or `start_pending(via="google")` → redirect `/app/` or `/app/login?step=2fa`; no match + `self_registration` → session `google_email`/`google_name` (30 min) → `/app/register?google=1`; otherwise `/app/login?error=google`. Registration (Task 3 `register`) marks the email verified when it equals the session's `google_email` (no confirmation email then).
- [ ] Tests: state/PKCE/nonce mismatches; bad `iss`/`aud`/`exp`/`nonce`; `email_verified` false; `test_admin_or_secondary_not_matched` (admin, staff, unverified primary, secondary address, pending_email, invited, inactive); sub stored then enforced; prefill + registration verified only for the same email; 2FA user → 2fa step; non-canonical host redirected; switch off → 404; settings ADMIN_ONLY, secret write-only, `redirect_uri` shown. Commit.

### Task 8: Dashboard — registration page

**Files:** `dashboard/src/features/registration/*`, `routes/register.tsx` (public, auth layout), locale `registration.json`, tests.
- [ ] Steps: who (adult / parent) → details (adult fields or parent fields + 1–5 children) → preferences (start date, hours/week, days checkboxes, intro-call date+time in the browser zone, teacher preference) → consent → submit → "Check your email to confirm" (same screen for every outcome). Optional registration code field shown when `sign-in-options.self_registration` and the waitlist is on (expose `waitlist: bool` in sign-in-options for this — add it in the backend here with a test). Google prefill when `?google=1` (GET `registration/google-prefill/` → `{email, full_name}` from the session — add this small backend route, SELF_SERVICE, test). Hidden honeypot input. Client validation mirrors the server; server field errors mapped (children index). Closed → "Registration is closed". Tests per step and error. Commit.

### Task 9: Dashboard — admin screens

**Files:** `dashboard/src/features/registration/admin/*`, routes `_authed/people.registrations.tsx`, `_authed/settings.registration-codes.tsx`, nav items under `// ── phase B9 ──` (Registrations in `people` group with a pending badge from `pending_count`; codes in `settings`), `// B9c` entries in nav.test.ts / permissions.test.ts, regenerate route tree; tests.
- [ ] Registrations: status tabs (unconfirmed, pending, approved, rejected, expired), detail panel (registrant, children, preferences in the academy's zone, email confirmed, code), Approve (disabled until confirmed) / Reject (reason dialog); codes: list, create (code, label, uses, expiry), deactivate. Commit.

### Task 10: Dashboard — Google, code reset, sign-in settings, login messages

**Files:** `features/identity` (login page Google button, R-8c messages for the three codes, `?error=google` and `?step=2fa` handling), `routes/forgot-password.tsx` (code path: channel → identifier → code → choose account (if several) → new password; email-link path kept), `routes/_authed/settings.sign-in.tsx` (Google client form, redirect URI with copy; admins only; nav under B9 marker), locales `signInGoogle.json`, `codeReset.json`; tests.
- [ ] Phone channel shown only when `code_reset.phone`; Google button only when `google`. Commit.

### Task 11: End-to-end

**Files:** `dashboard/e2e/b9-registration.spec.ts`.
- [ ] Journeys (re-runnable, stamped data): an adult registers, confirms via Mailpit, waits (waitlist on), the admin approves, the student signs in; a parent registers two children with a code (approved at once), confirms, signs in and sees the children; a code reset by email (code from Mailpit) sets a new password. Run twice, then the full `just e2e`. Commit.

## Final checks

- [ ] `just test`, `just lint`, `just e2e` green; final whole-slice review; minors logged; `ledger.py queue B9c`.
