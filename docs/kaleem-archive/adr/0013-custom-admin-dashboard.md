---
number: 0013
title: Build admin UX in the custom dashboard; Django admin is internal-only
status: accepted
date: 2026-06-09
---

## Context

Phase A shipped a working Django admin (`kaleem/identity/admin.py`) with model
registrations and a teacher "send password-set email" action. Django admin is
fast to stand up, but it is not a product surface: it exposes raw tables, has no
room for our role model (parents, students, teachers, subscriptions, sessions),
can't enforce module service boundaries cleanly, and is not something we want
staff or future operations people running the business from.

We need an admin experience that matches kaleem's domain (manage teachers, the
teacher pool, parent/child links, invites, subscriptions, sessions). It belongs
in the **one authenticated React dashboard that all users share** — the same app,
session-auth, and CSRF stack students, parents, and teachers use.

## Decision

There is a single dashboard for all users; **what it renders is driven by the
user's role** (student / parent / teacher / admin). Admin is one of those role
views, not a separate staff app. Admin screens are built in this dashboard, going
through each module's `services.py` public API like every other dashboard feature.
Whether a user sees admin views is gated on their admin role (`User.is_staff`).

**Django admin stays enabled but internal-only** — a break-glass / superuser
utility behind staff auth (and IP-restricted in production), not a product
surface and not where day-to-day admin work happens. `identity/admin.py` is kept
as-is for that purpose; we do not invest in expanding it.

This work is **in current scope**: Phase A's "Django admin walkthrough" DoD item
is replaced by "admin actions (incl. teacher password-set) available in the
dashboard." Phase A does not close on Django admin.

## Alternatives considered

- **Django admin as the real admin product.** Cheapest, already half-built. Rejected:
  leaks raw schema, awkward for our role model, bypasses the service-layer boundary
  the whole architecture is built on (D4), and a poor operator experience.
- **Remove Django admin entirely.** Cleaner conceptually. Rejected: it's a useful
  break-glass tool when the dashboard is broken or for one-off superuser surgery,
  and deleting it buys nothing once it's locked down to staff/internal.
- **Defer custom admin to a later phase, keep Django admin interim.** Rejected: we'd
  close Phase A on a surface we've decided not to use, and the teacher password-set
  flow is needed now — better to build it where it will actually live.

## Consequences

Good:

- One auth/UX stack (React + session + CSRF) for all roles, admins included.
- Admin actions go through `services.py`, preserving module boundaries (D4).
- Admin screens can speak the domain (pool, invites, subscriptions) instead of raw tables.
- Django admin remains as a low-cost break-glass fallback.

Bad / costs:

- More work now: admin screens + the teacher password-set action must be built in
  the dashboard before Phase A closes (pulls dashboard work forward).
- Two admin surfaces exist (dashboard + locked-down Django admin); we must keep the
  Django one restricted (staff-only, prod IP-allowlist) so it doesn't become a
  shadow product or a security hole.
- `STATE.md` Phase A DoD updated to reflect the dashboard admin path.
