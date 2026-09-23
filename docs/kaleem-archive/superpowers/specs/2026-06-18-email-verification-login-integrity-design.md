---
name: email-verification-login-integrity
phase: A
modules: [identity]
status: approved
created: 2026-06-18
closed: null
---

## Goal

Close the verification gaps in the just-shipped identity flow. An unverified email
address must never grant access, and the email-verification landing page must always
resolve to a clear success or error state. This is a hardening slice over Phase A
identity — two real bug fixes plus tests that lock in behaviour the architecture
already mostly enforces. It covers four `tasks.todo` items: #9 (login with an
unverified email), #1 (email-change re-verification), #2 (activation link → frontend
page), and #6 (`/verify-email` spins forever).

## Reconciling the four items

| Item | State after investigation | Work here |
| --- | --- | --- |
| #9 login with unverified email | **Real bug.** `LoginView` gates on "user has *any* verified email" ([views.py](../../../backend/kaleem/identity/api/views.py)), not the email being used to log in. | **Fix (backend)** |
| #1 change-email re-verification | **Already enforced.** No single "change email" action exists; the flow is add → verify → `set_primary` (requires `verified`) → remove old, so the old verified email keeps working until the new one is verified. Only #9 violated "can't use until verified". | **Lock in with tests; no new endpoint** |
| #2 activation URL → frontend page | **Already done.** The account adapter routes confirmation links to `{FRONTEND_URL}/verify-email?key=…`. | **Confirm; covered by #6** |
| #6 `/verify-email` spins forever | **Real bug** on the page, plus a latent CSRF gap on first contact. | **Fix (frontend)** |

Decisions taken in brainstorming:
- **Keep the multi-email manager; do not add a dedicated "change email" flow.** The
  existing add/verify/set-primary/remove surface already satisfies #1.
- **A user may sign in with any of their verified email addresses; unverified
  addresses are always rejected** (matches allauth's default and the multi-email
  feature's intent).

## User flow

**Verify email (happy path).**
1. User receives a verification email and clicks the link → dashboard `/verify-email?key=…`.
2. The page obtains a CSRF token, then POSTs the key to confirm the address.
3. On success the page shows a confirmation and a **"Continue to sign in"** button.
4. User clicks through to `/login` and signs in.

**Verify email (failure).** An invalid or expired key returns `400`; the page shows a
clear error and a path to sign in / request a fresh link. The page never hangs on the
spinner.

**Login gate.**
- Sign in with a **verified** email (primary or secondary) → success.
- Sign in with an **unverified** email (e.g. a newly added one) → `400 "Email address
  is not verified."`
- A user whose only email is unverified still cannot sign in (unchanged).

**Change email (unchanged surface, now correct).** Add a new email (created unverified)
→ the old verified email keeps functioning normally → verify the new one → set it
primary → optionally remove the old. The new email cannot be used for login until
verified (the #9 fix).

## Data model delta

None. No new tables or fields. Behaviour changes only.

## API delta

- **Changed — `POST identity/login/`**: the verification gate now checks the
  **submitted** email's `EmailAddress.verified`, not merely whether the user has any
  verified address. Response shapes unchanged (`200` me-payload / `400` not-verified /
  `400` invalid credentials).
- **New — `GET identity/csrf/`**: a minimal `@ensure_csrf_cookie` endpoint that
  guarantees a `csrftoken` cookie is set. `AllowAny`, returns `200` with an empty body.
  Used by the verify-email page (a public route) so its POST succeeds on first contact.
- **Unchanged — `POST identity/verify-email/`**: stays a POST (never GET — a GET link
  could be auto-confirmed by email-client link prefetching).

## Frontend

The dashboard slice that exposes this:
- **Route:** `/verify-email` (public; reached from the email link). No new routes.
- **Components / states:** the existing `VerifyEmailPage` becomes a deterministic state
  machine — `pending` → `success` | `error`, never stuck on `pending`.
  - `success`: confirmation message + a "Continue to sign in" button (replaces the
    `setTimeout` auto-redirect).
  - `error`: invalid/expired message + sign-in link / request-a-new-link path.
- **API calls (via `src/lib/api.ts`):** `GET identity/csrf/` before `POST
  identity/verify-email/` so the confirm POST has a CSRF token on first contact.
- **i18n / a11y:** en + ar with full RTL; jest-axe clean (repo baseline, ADR-0020).
- **"Done"** = built, deployed to staging, and verified in the browser end-to-end.

## Module boundaries

Entirely within `identity`. No new cross-module calls or events. The login gate reads
allauth's `EmailAddress` (already used throughout the module); the CSRF endpoint is a
plain Django/DRF view.

## Out of scope

- A dedicated single-step "change email" flow (the multi-email manager stays as-is).
- Password change / reset (#7), birthdate at registration (#8).
- Toast notifications (#12), email-body privacy review (#11), GDPR ADR (#10).
- Any change to how secondary emails are added, set primary, or removed.

## Test plan

**Backend (TDD, 100% line + branch).**
- Verified primary + unverified secondary: login with the **secondary** → `400`
  not-verified.
- Login with a **verified secondary** → `200`.
- Unverified-only user → `400` (unchanged).
- Verified-primary login → `200` (unchanged).
- `GET identity/csrf/` → `200` and sets the `csrftoken` cookie.

**Frontend (TDD, 100% line + branch).**
- A test that reproduces the hang: on confirm success the page must reach the success
  UI, not remain pending (guards #6 against regression).
- CSRF GET is issued before the confirm POST.
- `400` from confirm → error UI (not a spinner).
- Success UI renders the "Continue to sign in" button; en/ar + RTL; jest-axe clean.

**E2E (Playwright, D9 primary + key failure paths).**
- Register → click the verification link → page shows success → login succeeds.
- Add an unverified email → attempt to log in with it → rejected.

## Open questions

None. The two scoping decisions (no dedicated change-email flow; any verified email may
log in) were resolved in brainstorming.
