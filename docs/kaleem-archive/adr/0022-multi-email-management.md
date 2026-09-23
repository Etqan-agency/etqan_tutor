---
number: 0022
title: Multi-email management with a user-chosen primary
status: accepted
date: 2026-06-17
---

## Context

The identity module started from a "single `User.email`" framing (see
`docs/architecture/identity.md` and the original identity spec). Changing an email was
wired naively: `PATCH /me/ {email}` rewrote `User.email` directly, with no verification
and no allauth `EmailAddress` sync. That meant a typo or a hijacked session could move
the login identity to an address nobody controls, and an unverified address could become
the account's login email.

The requirement that triggered this decision: when a user changes their email, the new
address must be unverified and require verification before it can be used, and the old
verified address must keep working normally until the new one is verified.

allauth's `account.EmailAddress` already models multiple addresses per user with
`verified` and `primary` flags, and already backs registration/verification here. The
question was whether to keep a single address (allauth `ACCOUNT_CHANGE_EMAIL=True`,
replace-on-change) or expose the full multi-address model.

## Decision

Expose **multi-email management** with a user-chosen primary, built on allauth's existing
`EmailAddress` (no new tables):

- A user may hold multiple addresses. Adding one (`POST /me/emails/`) creates it
  **unverified, non-primary** and never disturbs existing addresses.
- Verification reuses the existing `verify-email/` confirm-by-key endpoint; confirming
  only flips `verified=True` — it does **not** auto-promote.
- The user promotes any **verified** address to primary (`POST /me/emails/{id}/primary/`),
  which swaps the login identity. `User.email` (still `unique`, still the
  `USERNAME_FIELD`) is kept in sync with the primary address — and only ever by allauth's
  `set_as_primary()`, never by a manual write.
- Adding and promoting both require the current password (re-auth), and both send a
  security alert to the current/previous primary address. Addresses are capped
  (`ACCOUNT_MAX_EMAIL_ADDRESSES`, default 5). The primary cannot be deleted.
- The insecure `PATCH /me/ {email}` path is removed; email changes go exclusively through
  `/me/emails/`.

"Change my email" is therefore the composite flow **add → verify → set-primary**, and the
old verified address keeps authenticating throughout.

## Alternatives considered

- **Single address, replace-on-change (`ACCOUNT_CHANGE_EMAIL=True`).** Closest to the
  original "single `User.email`" framing and less surface area. Rejected: the user
  explicitly wanted to keep old addresses and choose the primary, and replace-on-change
  makes "old address keeps working until the new is verified" awkward to guarantee.
- **Keep `PATCH /me/ {email}` but add verification to it.** Rejected: conflates profile
  edits with a security-sensitive identity change, and a single endpoint can't cleanly
  model the add-then-verify-then-promote lifecycle.
- **A bespoke `EmailChangeRequest` table.** Rejected as reinventing what allauth's
  `EmailAddress` already provides (YAGNI, "don't do this" #7 favours the framework model).

## Consequences

- Richer, safer account surface; the original requirement is satisfied (new address
  unverified, old keeps working) and the takeover footgun in the old PATCH path is gone.
- `User.email` uniqueness is preserved; it is now derived state that tracks the primary
  `EmailAddress`. allauth's `set_as_primary()` is the single writer.
- New behaviour for the frontend to drive (a follow-up frontend spec consumes the
  contract); per-address notification routing remains out of scope (primary is the
  account address).
- Known follow-ups logged in `ISSUES.md`: the security-alert `delay()` runs inside
  `@transaction.atomic` (prefer `on_commit`, with a test-strategy caveat), and OpenAPI
  schemas document success responses only.
