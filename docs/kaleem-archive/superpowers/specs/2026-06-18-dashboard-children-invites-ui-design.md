---
name: dashboard-children-invites-ui
phase: A
modules: [identity]
status: draft
created: 2026-06-18
closed: null
---

## Goal

Give the dashboard a UI for the parent/student family-linking backend that
shipped with Phase A identity. A signed-in **parent** can see their children,
add a child (name only), set a child's login password, and generate an invite
code to link an existing student account to themselves. A signed-in **student**
can accept an invite code to link to a parent. This is **Spec 3 of 4** in the
dashboard-completion roadmap (shell → email management → **children/invites** →
onboarding) and consumes the existing `/api/v1/identity/children/`,
`/children/{id}/set-password/`, `/invites/`, and `/invites/accept/` endpoints —
no backend change.

## User flow

A new **`/family`** route (heading "Family") renders role-aware cards, mirroring
the role-aware Home page:

- **Parent** sees a **My children** card and an **Invite a student** card.
- **Student** sees a **Link to a parent** card.
- A user who is both (a parent who is also a student) sees all three.
- A user who is neither (e.g. a pure teacher) sees a muted "Nothing here yet"
  note.

### Parent: My children

The card lists the parent's children (one row per child: full name + a **Set
password** button). Below the list, a **"+ Add child"** button reveals an inline
form.

- **Add child.** Inline form with a single **Full name** field. Submit →
  `POST /children/`. On success the form collapses, the list refetches and shows
  the new child, and a confirmation appears: "{name} added."
- **Set password.** The **Set password** button opens a **Dialog** with a single
  **New password** field (min 8). Submit → `POST /children/{student_profile_id}/
  set-password/`. On success the dialog closes and a confirmation appears:
  "Password set for {name}." The endpoint requires only the new password — **no
  parent re-authentication** (unlike email changes).

### Parent: Invite a student

A **"Generate invite code"** button → `POST /invites/`. On success the card
shows:

- the generated **code**,
- a **Copy** button (`navigator.clipboard.writeText`) that shows a transient
  "Copied" confirmation,
- the expiry: "Expires in 24 hours."

After a code is shown, the button becomes **"Generate new code"**, with a note
that generating a new code invalidates the previous one (the backend expires any
prior unused invite). The displayed code lives in component state only — there is
no endpoint to re-fetch an existing invite, so the parent copies it there and
then. (Reloading the page clears the display; the code itself stays valid on the
backend for 24 hours.)

### Student: Link to a parent

A card with a single **Invite code** field and a **Link** button → `POST
/invites/accept/`. On success the card shows "You're now linked to
{parent_name}." The student always sees this form; the backend rejects a second
link (defense-in-depth — see error cases).

### Error / edge cases (mapped via the existing `parseApiError`)

- **Add child** with an empty name → client-side zod error on the name field.
- **Set password** shorter than 8 chars → client-side zod error on the dialog
  field; a backend rejection surfaces on the same field.
- **Accept invite** with an invalid/expired code → the `code` field shows
  "Invalid or expired invite code."
- **Accept invite** when already linked → the `code` field shows "You are
  already linked to a parent account."
- **Accept invite** without a student profile → the `code` field shows "You must
  have a student account to accept an invite."
- Throttle (429) on any action → a neutral "please wait a moment" message
  (`parseApiError` already flags `throttled`).
- A query error loading the children list → an inline `Alert` in the card.

## Data model delta

None server-side. Frontend types/schemas only (see Frontend).

## API delta

None. Consumes existing endpoints:

- `GET /api/v1/identity/children/` →
  `[{ id, full_name, student_profile_id, teacher_gender_preference }]`
- `POST /api/v1/identity/children/` — body `{ full_name }` →
  `201 { child_user_id, student_profile_id }`
- `POST /api/v1/identity/children/{student_profile_id}/set-password/` — body
  `{ password }` (min 8) → `200`
- `POST /api/v1/identity/invites/` — no body → `201 { code, expires_at }`
- `POST /api/v1/identity/invites/accept/` — body `{ code }` →
  `200 { parent_name, linked }`

## Frontend

**Route.** Create `src/routes/_authed/family.tsx` (path `/family`). The component
reads `useMe()`, computes `isParent`/`isStudent`, and composes the role-appropriate
cards. The TanStack generated route tree is regenerated (`pnpm exec vite build`).

**Navigation.** Add a "Family" entry to `features/shell/nav.ts`:
`{ to: "/family", labelKey: "nav.family", icon: Users, requiresAny: ["parent", "student"] }`.
Extend `NavItem` with an optional `requiresAny?: ProfileType[]` and update
`visibleNavItems` so an item shows when it has neither `requires` nor
`requiresAny`, when `requires` matches, **or** when any `requiresAny` role
matches. Existing items (Home, Account) carry neither field and stay visible to
all.

**Data layer** (`features/identity/`):

- `schemas.ts`:
  - `interface Child { id: number; full_name: string; student_profile_id: number; teacher_gender_preference: string }`
  - `interface Invite { code: string; expires_at: string }`
  - `addChildSchema = z.object({ full_name: z.string().min(1) })` → `AddChildInput`
  - `setChildPasswordSchema = z.object({ password: z.string().min(8) })` → `SetChildPasswordInput`
  - `acceptInviteSchema = z.object({ code: z.string().min(1) })` → `AcceptInviteInput`
- `api.ts` — add to `identityApi`:
  - `listChildren(): Promise<Child[]>` → `GET children/`
  - `addChild(input: AddChildInput): Promise<{ child_user_id: number; student_profile_id: number }>` → `POST children/`
  - `setChildPassword(studentProfileId: number, input: SetChildPasswordInput): Promise<void>` → `POST children/${studentProfileId}/set-password/`
  - `createInvite(): Promise<Invite>` → `POST invites/`
  - `acceptInvite(input: AcceptInviteInput): Promise<{ parent_name: string; linked: boolean }>` → `POST invites/accept/`
- `queries.ts`:
  - `childrenQueryKey = ["children"]`, `childrenQueryOptions`, `useChildren()`
  - `useAddChild()` — invalidates `childrenQueryKey` **and** `meQueryKey`
    (the `/me` payload also embeds a children summary)
  - `useSetChildPassword()` — pure mutation (nothing in any list changes)
  - `useCreateInvite()` — pure mutation (no invites query exists)
  - `useAcceptInvite()` — invalidates `meQueryKey`

**Components** (`features/identity/components/`), each small and prop-driven,
following `EmailAddresses`/`AddEmailForm`/`SetPrimaryDialog` (react-hook-form +
zod + `Field`/`Input`/`Alert`/`Button`, radix dialogs from the already-installed
`radix-ui`):

- `ChildrenCard.tsx` — the card: renders the children list (one row per child:
  name + **Set password**), and hosts the add form + the set-password dialog.
- `AddChildForm.tsx` — reveal-on-click full-name form (`{ onSuccess }`).
- `SetChildPasswordDialog.tsx` — radix `Dialog` with a password field, controlled
  per-row `open` state (one instance per child, like `SetPrimaryDialog`).
- `InviteCard.tsx` — generate/regenerate code, display, copy, expiry.
- `AcceptInviteCard.tsx` — the student's code-entry card.

**States.** Loading: `ChildrenCard` shows a `Spinner` while `useChildren` is
pending. Empty children: the list shows a muted "No children yet" line above the
add button. Error: a query error shows an inline `Alert`. Mutation feedback:
inline confirmations as described above.

**Home page.** Unchanged. The empty parent/student Home cards stay as they are;
family management is reached via the new nav item. (Wiring Home cards to deep-link
into `/family` is a possible later polish, not part of this spec.)

## Module boundaries

Frontend-only, inside the dashboard's `features/identity` slice; it calls the
identity API via `src/lib/api.ts`. The shell's `nav.ts` gains the `/family` entry
and the `requiresAny` capability. No backend module boundary involved.

## Out of scope

- Any backend change (the endpoints already exist).
- Time-preferences / teacher-gender on the add-child form — deferred to **Spec 4**
  (student onboarding) so the weekly time-grid is built once.
- **Real child login.** Children are created with a placeholder email
  (`child.<uuid>@placeholder.kaleem`) and no externally known login identity, so a
  child cannot actually sign in yet even after a password is set. Set-password is
  built (it consumes the existing endpoint and matches the agreed scope), but the
  end-to-end child-login flow needs its own spec. **This limitation is logged to
  `ISSUES.md`.**
- Editing or removing a child; unlinking a student from a parent.
- A persistent / fetchable "current invite" (the API only generates a fresh code;
  there is no GET).
- Parent management of a child's email or onboarding preferences.

## Test plan

Vitest + React Testing Library; failing test first; 100% line+branch.

Component / hook tests:

- **ChildrenCard**: lists children; spinner while pending; inline alert on query
  error; "No children yet" when empty; renders a Set-password button per row.
- **AddChild**: success collapses the form, shows "{name} added", and the new
  child appears (mock `addChild`, assert `children` + `me` invalidation/refetch);
  empty name → zod field error.
- **SetChildPassword**: opening the dialog shows the password field; submit calls
  `setChildPassword` with the child's `student_profile_id` and shows the
  confirmation; a too-short password → field error; cancel closes without calling.
- **InviteCard**: generate calls `createInvite` and renders the code + expiry;
  Copy calls `navigator.clipboard.writeText` and shows "Copied"; regenerate shows
  the new code and the "invalidates previous" note.
- **AcceptInvite**: success shows "linked to {parent_name}" (assert `me`
  invalidation); invalid/expired code → `code` field error; already-linked → field
  error; empty code → zod field error.
- **family route**: parent sees children + invite cards; student sees accept card;
  both sees all three; neither sees the muted note (mock `useMe`).
- **nav**: `visibleNavItems` shows Family for a parent, for a student, and hides
  it for a user who is neither; Home/Account stay visible regardless.
- a11y: dialogs are labelled + focus-trapped (radix), keyboard-operable; jest-axe
  on each component; RTL logical CSS.

## Open questions

Resolved during brainstorming (2026-06-18):

- **Placement:** a single role-aware **`/family`** page with a nav item visible to
  parents and students; not separate routes, not Home-page cards.
- **Add-child scope:** **name only**; time-preferences/teacher-gender deferred to
  Spec 4.
- **Set-password:** **included** (consumes the existing endpoint); the
  child-can't-actually-log-in limitation is logged to `ISSUES.md` for a future
  child-login spec.
