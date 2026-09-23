---
name: dashboard-email-management-ui
phase: A
modules: [identity]
status: draft
created: 2026-06-18
closed: null
---

## Goal

Give the dashboard a UI for the multi-email backend shipped in ADR-0022. A
signed-in user can see their email addresses, add a new one (which starts
unverified and requires verification), promote a verified address to primary
(the login identity), and remove a non-primary address. This is **Spec 2 of 4**
in the dashboard-completion roadmap (shell → **email management** →
children/invites → onboarding) and consumes the existing
`/api/v1/identity/me/emails/` endpoints — no backend change.

It also closes a loose end: the profile form still has an `email` field that
PATCHes `/me/`, but the backend dropped `email` from that serializer when
email-management shipped, so the field is dead. This spec removes it; email is
managed only through the new UI.

## User flow

The `/profile` route is renamed to **`/account`** (heading "Account"). The page
stacks two cards:

1. **Profile** — the existing full-name form (now name-only).
2. **Email addresses** — lists every address with a state-driven row:
   - **Primary** (always verified): a "primary" badge, no actions.
   - **Verified, non-primary**: **Make primary** and **Remove**.
   - **Unverified**: an "Unverified" badge, **Resend verification**, and
     **Remove**.

Actions:

- **Add address.** A "+ Add email address" button reveals an inline form (email +
  current password). Submit → `POST /me/emails/`. On success the form collapses,
  the list shows the new address as *Unverified*, and a confirmation appears:
  "Verification link sent to <email>." The user verifies by clicking the emailed
  link, which lands on the existing `/verify-email?key=…` route.
- **Make primary.** Opens a small **Dialog** asking for the current password
  (the backend requires it), then `POST /me/emails/{id}/primary/`. On success the
  dialog closes and the promoted address shows the primary badge; the previous
  primary becomes a verified, non-primary row.
- **Remove.** Opens an **AlertDialog** confirm ("Remove this address?"), then
  `DELETE /me/emails/{id}/`. On success the row disappears.
- **Resend verification.** Calls the existing resend endpoint for that address;
  shows a neutral "If it still needs verifying, a new link is on its way."

### Error / edge cases (mapped via the existing `parseApiError`)

- Add with a wrong current password → the form's `current_password` field shows
  the error; the address is not added.
- Add a duplicate / already-in-use address → the `email` field shows the error.
- Add beyond the cap (5) → the `email` field shows the backend message.
- Make-primary with a wrong password → the dialog's password field shows the
  error; the dialog stays open.
- The backend forbids removing the primary and forbids promoting an unverified
  address, but the UI never offers those actions, so they are defense-in-depth:
  if such an error returns, it surfaces in the row's/dialog's error slot.
- Throttle (429) on resend/add → a neutral "please wait a moment" message
  (`parseApiError` already flags `throttled`).

## Data model delta

None server-side. Frontend types/schemas only (see Frontend).

## API delta

None. Consumes existing endpoints:
`GET/POST /api/v1/identity/me/emails/`,
`POST /api/v1/identity/me/emails/{id}/primary/`,
`DELETE /api/v1/identity/me/emails/{id}/`,
and the existing `resend-verification/` + `verify-email/` for the verification
loop.

## Frontend

**Route.** Rename `src/routes/_authed/profile.tsx` → `src/routes/_authed/account.tsx`
(path `/account`). Update the shell nav item (`features/shell/nav.ts`: `/profile`
→ `/account`, label key) and the topbar user-menu link/label to "Account". The
TanStack generated route tree is regenerated. The page renders the Profile card +
the new `EmailAddresses` card.

**Data layer** (`features/identity/`):
- `schemas.ts`:
  - `interface EmailAddress { id: number; email: string; verified: boolean; primary: boolean }`
  - `addEmailSchema = z.object({ email: z.email(), current_password: z.string().min(1) })`
  - `setPrimarySchema = z.object({ current_password: z.string().min(1) })`
  - Remove `email` from `profileEditSchema` (becomes `{ full_name }`).
- `api.ts` — add to `identityApi`:
  - `listEmails(): Promise<EmailAddress[]>` → `GET me/emails/`
  - `addEmail(input): Promise<EmailAddress>` → `POST me/emails/`
  - `setPrimaryEmail(id, input): Promise<EmailAddress>` → `POST me/emails/${id}/primary/`
  - `removeEmail(id): Promise<void>` → `DELETE me/emails/${id}/`
- `queries.ts`:
  - `emailsQueryKey = ["emails"]`, `emailsQueryOptions`, `useEmails()`
  - `useAddEmail()` — invalidates `emailsQueryKey`
  - `useSetPrimaryEmail()` — invalidates `emailsQueryKey` **and** `meQueryKey`
  - `useRemoveEmail()` — invalidates `emailsQueryKey`
- On the `/verify-email` route's success, invalidate `emailsQueryKey` so the list
  reflects the just-verified address.

**Components** (`features/identity/components/`), each small and prop-driven,
following `ProfileEditForm` (react-hook-form + zod + `Field`/`Input`/`Alert`/
`Button`):
- `EmailAddresses.tsx` — the card: renders the list (one row per address with the
  state-driven actions) and hosts the add form + the dialogs.
- `AddEmailForm.tsx` — reveal-on-click email + current-password form.
- `SetPrimaryDialog.tsx` — radix `Dialog` with a password field.
- `RemoveEmailDialog.tsx` — radix `AlertDialog` confirm.

Dialogs use the already-installed `radix-ui` (`import { Dialog, AlertDialog } from "radix-ui"`) — **no new dependency**.

**States.** Loading: the card shows a `Spinner` while `useEmails` is pending.
Empty: not reachable (a user always has ≥1 primary address). Error: a query error
shows an inline `Alert`. Success/mutation feedback: inline confirmations as above.

**Cleanup folded in.** Remove the `email` field from `ProfileEditForm.tsx` and its
test; the form submits `{ full_name }` only.

**"Done"** = built, all dashboard tests green at 100% coverage, deployed to
staging, and verified in the browser end-to-end (add → receive link → verify →
make primary → remove; light/dark; en + ar/RTL).

## Module boundaries

Frontend-only, inside the dashboard's `features/identity` slice; it calls the
identity API via `src/lib/api.ts`. The shell's `nav.ts` gains the renamed
`/account` entry (the data-driven nav anticipated in Spec 1). No backend module
boundary involved.

## Out of scope

- Any backend change (the endpoints already exist).
- In-app verification code entry — verification stays on the emailed-link flow
  (`/verify-email`).
- Password change / other account-security settings (future spec).
- Children/invites and onboarding UIs (Specs 3 and 4).
- A standalone `/account/emails` sub-route — emails live on the single Account
  page.

## Test plan

Vitest + React Testing Library; failing test first; 100% line+branch.

Component / hook tests:
- **Row rendering by state**: primary (badge, no actions), verified-non-primary
  (Make primary + Remove), unverified (Unverified badge + Resend + Remove).
- **Add**: success collapses the form, shows "verification link sent", and the
  new address appears (mock `addEmail`, assert query invalidation/refetch);
  wrong-password → `current_password` field error; duplicate → `email` field
  error.
- **Make primary**: opening the dialog shows the password field; submit calls
  `setPrimaryEmail` and invalidates `me` + `emails`; wrong password keeps the
  dialog open with the error.
- **Remove**: confirm in the AlertDialog calls `removeEmail` and the row goes
  away; cancel closes without calling.
- **Resend**: calls the resend endpoint and shows the neutral message.
- **Loading/error**: spinner while pending; inline alert on query error.
- **Verify route**: on confirm success it invalidates the emails query.
- **Profile form**: no longer renders or submits an email field.
- a11y: dialogs are labelled + focus-trapped (radix), keyboard-operable; jest-axe
  on each component; RTL logical CSS.

## Open questions

Resolved during brainstorming (2026-06-18):
- Placement: a single **Account** page (rename `/profile` → `/account`) with a
  Profile card + an Email addresses card; no separate emails route/nav item.
- Confirmations: **make-primary** uses a password **Dialog**; **remove** uses an
  **AlertDialog**.
- Verification: reuse the existing emailed-link `/verify-email` flow, not in-app
  code entry.
- The dead `email` field on the profile form is removed as part of this spec.
