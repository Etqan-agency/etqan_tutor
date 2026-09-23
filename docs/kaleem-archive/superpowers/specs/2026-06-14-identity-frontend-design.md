---
name: identity-frontend
phase: A
modules: [identity]
status: draft
created: 2026-06-14
closed: null
---

## Goal

Build the dashboard slice for the identity module. The Phase A identity *backend* shipped
without a frontend (it predates the every-feature-ships-its-frontend rule), so the dashboard
is still the Phase-0 scaffold: `features/identity/` is empty and the only route is a
placeholder. This spec covers the **full identity frontend surface** — registration, login,
email verification, the authenticated role-aware home, profile editing, parent child
management, invites, and student onboarding — built on the now-live Serene Scholar design
system (`@/ui` primitives + `AuthLayout`).

It is delivered in one spec but built in **three phases**, each its own `feat` branch + PR.
Phase 1 (auth core) closes Phase A: the immediate, non-negotiable outcome is that the
**register → verify → login → /me click-through works on `app-staging.kaleem.academy`
against `api-staging.kaleem.academy`**, proving the cross-subdomain session cookie
(ADR-0019) end-to-end.

Reference: [identity-module](2026-06-08-identity-module.md) (backend) · ADR-0019 (cookies) ·
ADR-0020 (a11y/i18n/l10n baseline).

---

## User flow

From the user's point of view. Error cases inline.

### Register (adult student or parent)
1. Visit `/register`. Fields: full name, email, password, account type (student | parent).
2. Submit → on success, navigate to `/verify-pending` (email passed through).
   - Error: duplicate email → field error under email ("A user with this email already
     exists."). Validation errors render under their field.
3. `/verify-pending` explains "check your inbox" and offers **Resend verification email**
   (calls the silent resend endpoint; always shows the same neutral confirmation; a 429
   shows "please wait before requesting another").

### Verify email (custom landing — replaces allauth's default HTML page)
1. The verification email links to `app-staging.kaleem.academy/verify-email?key=<key>`.
2. `/verify-email` reads `?key`, POSTs it to the confirm endpoint, shows pending → success
   → error states.
   - Success → auto-redirect to `/login` (or `/` if already authenticated).
   - Invalid/expired key → error state with a link back to `/verify-pending` to resend.

### Login
1. Visit `/login`. Email + password.
2. Submit → on success the `/me` payload primes the cache; navigate to `/` (role-aware home).
   - Invalid credentials → generic non-field error ("Invalid credentials.").
   - **Not verified** ("Email address is not verified.") → inline **Resend verification**
     affordance (links to/triggers the resend flow).

### Authenticated home (role-aware, branches on `/me` `profiles`)
- Always: greeting + name/email, link to **profile edit**, **logout**.
- If `parent` in profiles: children panel (list, add child, set child password) + invite
  creation.
- If `student` in profiles: onboarding/availability + invite-accept entry point.

### Profile edit
- Edit full name and/or email (PATCH `/me`). Email change validated for uniqueness
  (field error on conflict). On success the `me` cache updates.

### Parent — children & invites (Phase 2)
- **Children:** list children; add a child (full name + optional preferences); set a child's
  login password. Empty state when no children yet.
- **Invite:** generate a fresh code → display code + expiry, with a copy-to-clipboard action.
  Generating a new code expires any prior unused one (backend behaviour; UI reflects it).

### Student — invite accept & onboarding (Phase 3)
- **Accept invite:** enter a code → on success show "linked to <parent name>".
  - Invalid/expired code → typed field error.
- **Onboarding:** a **weekly availability grid** (7 days × time slots, painted/selected,
  serialized to the API's `time_preferences` list of `{day, start_time, end_time}`) +
  teacher gender preference. Must work in RTL. Save → POST student-profile.

### Logout
- POST `/logout`, clear the query cache, navigate to `/login`.

---

## Data model delta

None. This is a frontend slice over the existing identity API; no new tables or fields on the
backend models. The only backend change is an additional confirm endpoint + adapter URL
override (see API delta).

---

## API delta

The dashboard consumes the existing Phase A endpoints (all under `/api/v1/identity/`, via
`src/lib/api.ts` which is already CSRF + credentials wired):

| Method | Path | Used by |
| --- | --- | --- |
| POST | `register/` | Register |
| POST | `resend-verification/` | Verify-pending, login-not-verified |
| POST | `login/` | Login (returns full `/me` payload → primes cache) |
| POST | `logout/` | Logout |
| GET | `me/` | `useMe` (auth source of truth + route guard) |
| PATCH | `me/` | Profile edit |
| GET/POST | `children/` | Parent children list/create |
| POST | `children/<id>/set-password/` | Parent set child password |
| POST | `invites/` | Parent create invite |
| POST | `invites/accept/` | Student accept invite |
| POST | `me/student-profile/` | Student onboarding preferences |

**New backend endpoint (Phase 1, `backend` submodule):**

- `POST /api/v1/identity/verify-email/` — body `{ "key": "<hmac-key>" }`. Confirms the email
  via allauth's `EmailConfirmationHMAC.from_key(key).confirm(request)`. Returns `200` on
  success; typed `400` on a missing/invalid/expired key. `AllowAny`.
- Override `get_email_confirmation_url` in `kaleem/identity/adapter.py` so verification emails
  point at `{APP_DOMAIN}/verify-email?key=<key>` instead of allauth's server-rendered confirm
  page. (`APP_DOMAIN`/dashboard origin already configured for ADR-0019.)

---

## Frontend

The substance of this spec. Built on `@/ui` (Button, Input, Field/FormError, Label, Card,
Alert, Spinner), `AuthLayout`, the theme/locale toggles, `ThemeProvider`, and
`DirectionProvider`. The throwaway `/design-preview` route is removed.

### Routes (TanStack Router, file-based under `src/routes/`)

| Route | Auth | Role | Phase |
| --- | --- | --- | --- |
| `/register` | public | — | 1 |
| `/login` | public | — | 1 |
| `/verify-pending` | public | — | 1 |
| `/verify-email` | public | — | 1 |
| `_authed` (pathless layout, guard) | protected | — | 1 |
| `_authed/` (role-aware home) | protected | all | 1 |
| `_authed/profile` | protected | all | 1 |
| `_authed/children` | protected | parent | 2 |
| `_authed/invite` | protected | parent (create) / student (accept) | 2/3 |
| `_authed/onboarding` | protected | student | 3 |

### Module structure (`src/features/identity/`)

- `api.ts` — typed wrappers over `api` (one function per endpoint above).
- `queries.ts` — `useMe` query + mutation hooks (`useLogin`, `useLogout`, `useRegister`,
  `useResendVerification`, `useVerifyEmail`, children/invite/profile mutations).
- `schemas.ts` — zod schemas shared by forms (via react-hook-form resolver) and response
  parsing.
- `components/` — `RegisterForm`, `LoginForm`, `ProfileEditForm`, `ChildList`, `ChildForm`,
  `InvitePanel`, `InviteAcceptForm`, `AvailabilityGrid`.
- `index.ts` — public exports.

### Auth state & route protection

- `useMe()` = `useQuery(['me'], getMe)`; a `401` means unauthenticated.
- `_authed.tsx` `beforeLoad` runs `queryClient.ensureQueryData(meQuery)`; on `401`,
  `redirect({ to: '/login' })`. All protected routes nest under it.
- Login returns the `/me` payload → mutation does `setQueryData(['me'], data)` (no extra
  round-trip) then navigates home.
- Logout → POST, `queryClient.clear()`, navigate `/login`.

### Components / states

Every form/route handles **loading** (Spinner / disabled submit), **error** (field errors via
`FormError`, general via `Alert`), **empty** (e.g. parent with no children), and **success**
(navigation or inline confirmation). One `apiError → { fieldErrors, message }` helper maps the
DRF error shapes (`{field: [..]}` / `{non_field_errors: [..]}`). Specific cases: login
not-verified surfaces a resend affordance; resend `429` shows a wait message.

### i18n / RTL / a11y (ADR-0020 baseline)

All copy in `locales/en` + `ar`. Forms reuse the a11y-wired `Field/Label/FormError`. Every
route/component gets a `jest-axe` test. The availability grid is verified in both LTR and RTL.

### Tooling

- **Forms:** add `react-hook-form` + `@hookform/resolvers` (zod already a dependency).
- **Component tests:** `vi.mock` the typed `api.ts` layer (no MSW). The real golden path is
  browser-verified on staging (the DoD).

### Done

Built, deployed to staging, browser-verified end-to-end. Phase 1 "done" =
register → verify → login → `/me` click-through works on `app-staging` against `api-staging`.

---

## Module boundaries

Frontend-only; no backend module-boundary impact. The one backend change (verify-email
endpoint + adapter override) lives entirely within the `identity` module and touches no other
module. No new cross-module events.

---

## Out of scope

- Teacher self-registration (teachers are admin-created; ADR-0013).
- Password reset / change-password flows (not part of the Phase A backend surface).
- Admin dashboard UI (ADR-0013, separate effort).
- Date-of-birth capture for children (not in the current API).
- Any billing/scheduling/assessment UI — Phase B+.
- Production env wiring (staging only; deferred per ADR-0019).

---

## Test plan

### Happy paths
- Register (student) → verify-pending → resend works.
- Register (parent) → verify-pending.
- `/verify-email?key=<valid>` → success → redirect to `/login`.
- Login → `/me` cache primed → role-aware home renders.
- Profile edit → name/email updated, cache refreshed.
- Parent: add child → child appears in list → set child password (Phase 2).
- Parent: create invite → code + expiry shown → copy works (Phase 2).
- Student: accept valid invite → "linked to <parent>" (Phase 3).
- Student: onboarding grid → preferences saved (Phase 3).
- Logout → cache cleared → redirected to `/login`.
- **Golden path (browser, staging):** register → click email link → `/verify-email` →
  login → `/me` renders. Closes Phase A.

### Edge / failure cases
- Register duplicate email → field error.
- Login invalid credentials → generic non-field error.
- Login unverified → not-verified message + resend affordance.
- `/verify-email` with missing/invalid/expired key → error state + resend link.
- Resend throttled (`429`) → wait message.
- Invalid/expired invite code → typed field error (Phase 3).
- Accessing a protected route while unauthenticated (`401`) → redirect to `/login`.
- a11y: zero `jest-axe` violations on every route/component, LTR and RTL.

---

## Open questions

None blocking. (Resolved during brainstorming: full surface; one spec / phased build;
TanStack Query `useMe` + guard for auth state; custom `/verify-email` landing with its backend
dependency; role-aware home; weekly availability grid; react-hook-form + module-mocked tests.)
