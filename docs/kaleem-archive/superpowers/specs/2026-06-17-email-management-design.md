---
name: email-management
phase: A
modules: [identity]
status: draft
created: 2026-06-17
closed: null
---

## Goal

Let a user hold more than one email address and change which one is their login
identity — safely. Adding an address starts it **unverified** and never disturbs
any existing address: login, the mandatory-verification gate, and `User.email`
all keep working off the already-verified/primary address. "Change my email" is
the composite flow **add → verify → set-primary**. This replaces today's
insecure path, where `PATCH /me/ {email}` rewrites `User.email` directly with no
verification at all.

## User flow

From the POV of a logged-in user managing their addresses.

1. **List.** User opens email settings → sees every address with `verified` and
   `primary` flags.
2. **Add a new email.** User enters a new address and their **current password**.
   - On success: a new `EmailAddress` is created **unverified**, a verification
     link is sent to the *new* address, and a **security alert** is sent to the
     *current primary* address ("a new email <new> was added to your account; if
     this wasn't you, …"). The new address is listed as unverified.
   - The old/primary address is unchanged — the user stays logged in and can
     still log in with it.
3. **Verify the new email.** User clicks the link → lands on the dashboard
   `/verify-email?key=…` route → it POSTs to the existing `verify-email/`
   endpoint → the address flips to `verified=True`. **It does not become primary
   automatically.**
4. **Promote to primary (the actual "email change").** User picks a *verified*
   address and confirms with their **current password**. `User.email` (the login
   identity) swaps to it; the previous primary is alerted. The previous address
   remains on the account as a secondary verified address.
5. **Remove an email.** User deletes a secondary address. The **primary cannot be
   removed** — they must promote another address first.

### Error cases (all surfaced as typed API errors)

- Add/promote with a **wrong current password** → 400.
- Add an email that is **already attached to the same user** → 400.
- Add an email **owned (verified) by another user**, or equal to any `User.email`
  → 400 (no account-existence leak beyond the existing register behaviour).
- Add beyond the **max-addresses cap** → 400.
- **Promote an unverified** address → 400 ("verify this address first").
- **Remove the primary** address → 400 ("set another address as primary first").
- Resend verification for an already-verified or unknown address → silent 200
  (reuses the existing resend endpoint's non-enumerating behaviour).

## Data model delta

**No new tables and no new fields.** We use allauth's existing
`account.EmailAddress` (one row per address, `user` FK, `email`, `verified`,
`primary`) — already in use for registration/verification. `User.email` (unique;
the `USERNAME_FIELD`) stays in sync with the `primary` `EmailAddress` via
allauth's `set_as_primary()`.

```
User (1) ──< EmailAddress (N)     # allauth; ≥0 verified, exactly ≤1 primary
  User.email  ==  the primary EmailAddress.email   (kept in sync)
```

Settings:
- `ACCOUNT_CHANGE_EMAIL = False` (allauth default → multiple addresses allowed).
- `ACCOUNT_MAX_EMAIL_ADDRESSES = 5` (new; bounds abuse).

## API delta

All endpoints are **authenticated** (session cookie + CSRF), under
`/api/v1/identity/`.

**New:**

| Method + path | Request | Response | Notes |
|---|---|---|---|
| `GET /me/emails/` | — | `200 [{id, email, verified, primary}]` | |
| `POST /me/emails/` | `{email, current_password}` | `201 {id, email, verified:false, primary:false}` | Password-gated. Sends verification to new address + security alert to current primary. |
| `POST /me/emails/{id}/primary/` | `{current_password}` | `200 {id, email, verified:true, primary:true}` | Address must be verified. Swaps `User.email`; alerts previous primary. |
| `DELETE /me/emails/{id}/` | — | `204` | Cannot delete the primary. |

**Reused (no change):**
- `POST /verify-email/` `{key}` — confirm-by-key (PR #15). Flips `verified=True`;
  does **not** promote to primary.
- `POST /resend-verification/` `{email}` — already works for any unverified
  address; covers "resend" for a pending new email.

**Removed / changed:**
- `MeUpdateSerializer` drops its `email` field; `PATCH /me/` no longer accepts or
  mutates `email`. Email changes go exclusively through the endpoints above. This
  is the insecure path this feature supersedes, so its removal is in scope here
  (not deferred to `ISSUES.md`).

## Module boundaries

- **Owner:** `identity`. No other module is touched.
- Inter-module calls: none. All logic is exposed through `identity/services.py`
  (`list_email_addresses`, `add_email_address`, `set_primary_email`,
  `remove_email_address`); the API views are thin wrappers.
- allauth coupling stays where it already is. Services do the data work +
  password check + uniqueness/cap validation and return the `EmailAddress`; the
  **view** triggers the allauth `send_confirmation(request._request)` (it needs
  the Django `HttpRequest`, exactly as `RegisterView` does today). The
  security-alert email is sent via the existing `platform` Celery task
  `send_email_message` (no request needed).
- New events: none.

## Frontend

**Out of scope for this spec — tracked as a separate follow-up spec** that
consumes the contract above (email-settings panel: list, add-with-password,
verify-link landing already exists, set-primary-with-password, delete; loading/
empty/error/success states; calls via `dashboard/src/lib/api.ts`). Backend
"done" here = endpoints built, tested, and deployed to staging; the browser
end-to-end check lands with the frontend spec.

## Out of scope

- Dashboard UI (separate spec, above).
- Changing the **login** rules (any verified address already authenticates via
  allauth's backend; the mandatory-verification gate already checks "any verified
  address"). No change needed.
- Phone numbers / other contact channels.
- Per-address notification routing (which address receives which mail) — primary
  remains the account address.
- Admin-side email management for other users.

## Test plan

TDD; failing test first. Target ≥80% coverage on `services.py`.

**Service unit tests** (`test_services.py` / new `test_email_management.py`):
- `add_email_address`: happy path creates unverified row; wrong password raises;
  duplicate-for-same-user raises; email owned by another user raises; over-cap
  raises.
- `set_primary_email`: promotes a verified address and `User.email` now equals it;
  unverified address raises; wrong password raises; non-owned `id` → NotFound.
- `remove_email_address`: removes a secondary; removing primary raises; non-owned
  `id` → NotFound.

**API tests** (`test_api_*`):
- Full flow: login (old email) → `POST /me/emails/` (new, unverified) →
  **old email still logs in and `/me/` works** while new is pending → confirm new
  via `verify-email/` → `POST /me/emails/{id}/primary/` → `/me/` now reports the
  new email → **old email still logs in** (secondary, verified).
- Security alert sent to the previous primary on add and on promote (assert the
  Celery task / outbox).
- Each error case returns the right status + typed error body.
- `PATCH /me/ {email}` is rejected/ignored (email no longer mutable there).
- All endpoints require auth + CSRF (403 without).

## Open questions

Resolved during brainstorming (2026-06-17):
- Re-auth: **current password required on both add and set-primary.**
- Retention: **keep all addresses; user picks which verified one is primary.**
- Old-email alert: **yes**, alert the current primary on add and on promote.
- Cap: `ACCOUNT_MAX_EMAIL_ADDRESSES = 5`.
- Frontend: separate follow-up spec.

An **ADR** will accompany implementation: exposing multi-email management +
password-gated email change is a deliberate behaviour choice relative to the
"single `User.email`" framing in CLAUDE.md (the uniqueness of `User.email` is
preserved; it simply tracks the primary address).
