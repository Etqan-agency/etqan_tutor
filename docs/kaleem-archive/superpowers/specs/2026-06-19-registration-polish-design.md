# Registration polish — design

**Status:** approved (decisions made autonomously per the user's "do all of them" directive).
**Date:** 2026-06-19
**Slice:** 3 of 4 in the post-verification backlog campaign (email-privacy → toasts → **registration-polish** → password-mgmt). Backend + dashboard.

## Goal

Two small registration/auth UX fixes:
1. Collect the user's **birthdate** at registration.
2. **Redirect already-authenticated users** away from `/login` and `/register` to the app.

## Backlog items

- `tasks.todo`: "users should enter their birthdate on registration"
- `tasks.todo`: "if user go to login/register page should redirect to profile page if he is authenticated"

## Part 1 — Birthdate at registration

**Storage.** Add `birthdate = models.DateField(null=True, blank=True)` to `identity.User`
(the single identity; not a profile — it's a per-person attribute). Nullable so existing
users and parent-created children (who don't self-register) are unaffected.

**Collection.** `RegisterSerializer` gains a **required** `birthdate = serializers.DateField()`
(DRF parses ISO `YYYY-MM-DD`). `register_user(...)` gains a `birthdate` param, passed to
`create_user`. `RegisterView` forwards `serializer.validated_data["birthdate"]`.

**Validation.** Must be a real date, **not in the future**, and within a sane range
(age ≤ 120, i.e. not absurdly old). Enforced in the serializer (`validate_birthdate`).

**Data-privacy (per ADR-0023).** Birthdate is personal data; stated here as the ADR requires:
- *What:* date of birth, one value per user.
- *Why:* an age record for age-appropriate provisioning and future parental-consent logic.
- *Who sees it:* the user and admins; it is **not** placed in any email or surfaced to other users.
- *Retention:* lifetime of the account (covered by the account-deletion/erasure flow deferred in ADR-0023).

**Explicitly out of scope (logged in ISSUES):** any **age-gate / minor-consent** behaviour
(GDPR-K: under-16 self-registration needs parental consent). We *collect* the date now; the
consent/gating policy is a product+legal decision for its own spec. We also do **not** surface
or let users edit birthdate post-registration in this slice (store-at-registration only; an
edit surface is a later slice).

## Part 2 — Redirect authenticated users from /login + /register

The `_authed` layout route already does `beforeLoad → ensureAuthed(queryClient)` and redirects
to `/login` on rejection. The public auth pages need the **inverse**: if the session is valid,
redirect to `/` (the authed home); otherwise render the page.

- Add a tiny helper `redirectIfAuthed(queryClient)` in `features/identity/queries.ts`:
  awaits `ensureAuthed`; on success `throw redirect({ to: "/" })`; on rejection returns (not
  authed → show the page). Extracted (not inlined) so it is unit-testable without the router.
- `routes/login.tsx` and `routes/register.tsx` add
  `beforeLoad: ({ context }) => redirectIfAuthed(context.queryClient)`.
- `/verify-pending` is left as-is (a transient post-register state, not a sign-in entry point).

## Files

**Backend**
- Modify `kaleem/identity/models.py` — add `birthdate` to `User`.
- Create `kaleem/identity/migrations/0004_user_birthdate.py`.
- Modify `kaleem/identity/api/serializers.py` — `birthdate` field + `validate_birthdate`; add to `RegisterResponseSerializer` (doc).
- Modify `kaleem/identity/services.py` — `register_user(..., birthdate)`.
- Modify `kaleem/identity/api/views.py` — pass `birthdate`.
- Tests: `kaleem/identity/tests/test_api_auth.py` (register-with-birthdate, missing → 400, future → 400).

**Dashboard**
- Modify `src/features/identity/schemas.ts` — `birthdate` in `registerSchema` (+ message).
- Modify `src/features/identity/components/RegisterForm.tsx` — date `Field`.
- Modify `src/features/identity/queries.ts` — `redirectIfAuthed`.
- Modify `src/routes/login.tsx`, `src/routes/register.tsx` — `beforeLoad`.
- Modify `src/locales/{en,ar}/common.json` — `auth.birthdate` + validation copy.
- Tests: RegisterForm (birthdate field + submitted), a `redirectIfAuthed` unit test, schema test.

## Testing

- Backend: register with valid birthdate → 201 and stored on the user; missing birthdate → 400;
  future date → 400; 100% line+branch; ruff/mypy/import-linter green.
- Dashboard: RegisterForm renders a date input and includes `birthdate` in the payload;
  `redirectIfAuthed` throws a redirect when `ensureQueryData` resolves and returns when it
  rejects; en/ar parity; jest-axe on the form; tsc/biome green.

## Out of scope

- Age-gating / minor parental-consent (ISSUES; own spec).
- Editing birthdate after registration / showing it on `/account` (later slice).
- Backfilling birthdate for existing users or children (nullable; left null).
