# Toast notifications — design

**Status:** approved (decisions made autonomously per the user's "do all of them" directive on the `tasks.todo` backlog).
**Date:** 2026-06-19
**Slice:** 2 of 4 in the post-verification backlog campaign (email-privacy → **toasts** → registration-polish → password-mgmt). Dashboard-only.

## Goal

Add a toast notification system to the dashboard and move transient "operation
succeeded" confirmations from inline `<Alert>` banners to toasts, so success feedback
is non-blocking, consistent, and doesn't push page content around.

## Backlog item

- `tasks.todo`: "we should use toast notifications and replace all current notes and
  notifications with toast".

## Scope decision (read this first)

"Replace all notes" is interpreted as **replace transient success/confirmation notices**,
not every banner. Specifically:

- **→ toast:** transient confirmations that today are shown via a `notice`/`saved`
  state + an `<Alert>` that lingers until the next interaction. These are pure "it
  worked" messages with no recoverable context: profile saved, preferences saved, email
  added (verification sent), verification resent, child added, child password set, invite
  copied.
- **stay inline (NOT toasted):**
  - **Form submission / validation errors** (`errors.root.server` and field errors in
    Login/Register/AddEmail/AddChild/ProfileEdit/SetChildPassword/preferences). An error
    the user must read while fixing the form belongs next to the form; a toast that
    auto-dismisses is a WCAG/UX regression (ADR-0020 a11y baseline).
  - **Query/load errors** (e.g. `account.loadError`, `family.loadError`): they replace
    the card's content in place; a toast would leave an empty card.
  - **Page/route states** (`/verify-email` success/fail, `/verify-pending`): these are the
    entire page's content, not notifications.

This keeps errors contextual and accessible while making confirmations ephemeral. The
user can later opt to toast errors too; that would be a follow-up, not this slice.

## Architecture

Build a toast primitive on **radix-ui's Toast** (already a dependency — no new package,
avoids the docker image-rebuild/node-modules reseed friction). Mirror the established
`src/ui/` pattern (cva + cn + `data-slot`, like `alert.tsx`).

- **`src/ui/toast.tsx`** — exports `toast()` and `<Toaster />`.
  - A tiny module-level store (plain array + `Set` of listeners) drives the toast list, so
    `toast(...)` is importable and callable from any component event/mutation handler
    (no context wiring at every call site). Consumed via `useSyncExternalStore`.
    IDs come from an incrementing counter (deterministic for tests; no `Date.now`).
  - `<Toaster />` renders radix `Toast.Provider` → one `Toast.Root` per item →
    `Toast.Title?` + `Toast.Description` + `Toast.Close`, then `Toast.Viewport`.
    radix supplies the a11y (live region, role, F8 hotkey, swipe, auto-dismiss via
    `duration`). On `onOpenChange(false)` the item is removed from the store.
  - **RTL:** `swipeDirection` = `i18n.dir() === "rtl" ? "left" : "right"`; the viewport
    uses logical positioning (`end-0`) so it sits bottom-trailing in both directions.
  - **Variants:** `default` and `success` (+ `destructive` for future error use), styled to
    match `alert.tsx`'s token classes.
  - The store is reset between tests via an exported `__resetToasts()` test hook (guarded,
    used only in tests) — or tests dismiss/clear explicitly.
- **Mount** `<Toaster />` once in `src/main.tsx`, inside `DirectionProvider` +
  `ThemeProvider` (so it inherits direction/theme) and inside `QueryClientProvider`.
- **i18n:** add `toast.dismiss` (close-button aria-label) and `toast.regionLabel`
  (Toast.Provider `label`) to `en/common.json` + `ar/common.json`. All message strings
  reuse existing keys (`auth.saved`, `prefs.saved`, `account.resent`,
  `account.verificationSent`, `family.childAdded`, `family.passwordSet`, …).

## Components migrated (success notices → toast)

| Component | Today | After |
| --- | --- | --- |
| `ProfileEditForm` | `isSubmitSuccessful && update.isSuccess` → `<Alert>` `auth.saved` | `toast({ description: t("auth.saved"), variant: "success" })` in submit success; drop the success Alert (keep error Alert) |
| `StudentPreferencesCard` | `saved` state → `<Alert>` `prefs.saved` | toast on save success; remove `saved` state + Alert |
| `EmailAddresses` | `notice` state → `<Alert>` (`account.resent`, `account.verificationSent`) | toast on resend/add success; remove `notice` state + Alert |
| `ChildrenCard` | `notice` state → `<Alert>` (`family.childAdded`, `family.passwordSet`) | toast on add/set-password success; remove `notice` state + Alert |
| `InviteCard` (if it shows a transient "copied") | inline state | toast `family.inviteCopied` (add key if missing) |

Each migration deletes the now-dead `notice`/`saved` state and its Alert branch, and its
test is updated to assert the toast text appears (and the inline Alert no longer does).

## Testing

- **`src/ui/toast.test.tsx`:** `toast()` then `<Toaster/>` shows the text; `success`
  variant class present; close button (`toast.dismiss` label) removes it; **jest-axe** clean;
  RTL render (wrap in DirectionProvider, `ar`) clean. StrictMode-safe (calling `toast()`
  from an event handler, not an effect — explicitly contrasted with the verify-email bug).
- **Component tests:** update ProfileEditForm/EmailAddresses/ChildrenCard/StudentPreferences
  tests to render within a `<Toaster/>` (or a small test helper) and assert the success
  **toast** text appears, and the old inline success Alert does not. Error-path tests are
  unchanged (errors still inline).
- tsc clean, biome clean, all dashboard tests green. (Note: dashboard CI runs only tsc +
  build today — vitest is run locally; logged in ISSUES.)

## Out of scope

- Toasting errors (kept inline by design above).
- A global QueryClient `onError` → toast for unexpected errors (nice future pattern; needs
  its own decision about which errors are "unexpected").
- Promise/loading toasts, action buttons in toasts (YAGNI).
