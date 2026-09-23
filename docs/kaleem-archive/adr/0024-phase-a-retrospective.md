---
number: 0024
title: Phase A (Identity) retrospective and exit
status: accepted
date: 2026-07-08
---

## Context

The roadmap (`docs/superpowers/specs/2026-04-11-rebuild-roadmap-design.md`) requires a
retrospective ADR at each phase exit (Section 7, T2). Phase A — Identity — is code-complete
and deployed to staging. This ADR walks the roadmap's Phase A exit criteria, records the
deviations taken during the phase, and states what carries into Phase B.

## Decision

**Phase A is declared closed** on the criteria below. One criterion — the real-inbox
staging click-through — is a manual human check tracked as a residual, not a code gate; it
does not block starting Phase B planning.

### Exit criteria (roadmap Phase A)

| Criterion | Status |
| --- | --- |
| All 3 registration flows work through the UI end-to-end | Student + parent self-register through the dashboard; **teachers are admin-created, not self-registered** (ADR-0013) — the "3 roles" are covered, but teacher onboarding is an admin action, not a public registration form. Verified end-to-end against the local dockerized stack (register → mailpit → verify → login → `/me`). Real-inbox staging click-through is the residual below. |
| Email verification in Mailpit (local) + real inbox (staging) | Mailpit local: verified. Staging: SES is out of sandbox and sends 201; the click-a-real-link check is the residual. |
| Password reset works | Shipped (backend #25); tested. |
| `identity/` services are the only thing importing from `allauth` | Enforced by import-linter, green in CI. |
| `docs/architecture/identity.md` written incl. ER diagram | Present; updated this session for child-verification. |
| import-linter passes | Green in CI. |
| Coverage on `identity/services.py` ≥ 90% | **97% (line + branch)**, 179 identity tests pass — re-verified 2026-07-08 (well above the 90% bar; grew from the 96% 2026-06-10 baseline as slices were added under TDD). |

### What Phase A actually delivered (beyond the original spec)

Phase A ran longer and wider than the ~5–7 specs estimated, because several identity
hardening items surfaced from the backlog and were done in-phase rather than deferred:

- Login-verification gate fix (gate on the *submitted* email, not "any verified email").
- Birthdate at registration (stored only; age-gating deferred).
- **Email-privacy campaign (ADR-0023):** PII minimization in transactional email bodies,
  Kaleem-brand subject/site, trailing-dot URL fix.
- **Multi-email management (ADR-0022):** add → verify → set-primary lifecycle.
- **Password management:** change-password (session-preserving) + reset.
- **Child verification (supersedes an earlier v1 decision):** the original design gave
  children a placeholder `@placeholder.kaleem` email and no login. That was reversed —
  children now get a real parent-provided email and activate like adults (`create_child`
  now takes an email + sends an activation link; parents manage email/password/preferences
  from `/family` with a Verified/Pending badge). This closes what `ISSUES.md` had tracked as
  "children can't actually log in yet." `docs/architecture/identity.md` updated to match.

### Deviations taken during Phase A (recorded, accepted)

1. **Frontend module scaffolds** — 6 non-functional "coming soon" placeholder routes
   (schedule/curriculum/assessments/messages/billing/insights) were built at user request
   (dashboard #18). They look built-out but have no backend; role-gating is provisional
   until each module's real D1 spec. Journal W26.
2. **Scheduling started early** — the first Phase B `scheduling` slice (tz-aware weekly
   availability + editor) shipped during Phase A at user direction, ahead of billing (which
   the roadmap sequences first in Phase B). Backend `scheduling` module now exists with
   `WeeklyAvailability` + `to_utc_intervals`. Matching/sessions/billing/video explicitly
   deferred. Journal W26.
3. **UI/UX audit passes** — a11y polish, a layout system, a visual-quality styling pass, and
   a bento dashboard home were done as audit-and-improve work on the pre-existing Serene
   Scholar design system (not roadmap features). Several token overrides live in the
   dashboard cascade pending a `@kaleem/tokens` release (ISSUES).

### Consequences / carried into Phase B

- **Residual (human step):** the real-inbox staging click-through for register (student +
  parent) → verify → login → `/me` → password reset. Everything else is green; this proves
  the cross-subdomain session cookie against a real SES inbox. Tracked in `STATE.md`.
- **Known gaps deferred (in `ISSUES.md`), not Phase A blockers:** dashboard CI does not yet
  enforce the D3 vitest/coverage gate; no Playwright e2e harness (e2e met by manual
  click-through); `develop → master` squash divergence; GDPR operational follow-ups
  (retention, DSAR/erasure, cookie consent, RoPA) due before public launch; zod validation
  messages not i18n'd; no security-alert on password change/reset.
- **Next:** Phase B per the roadmap sequence — `billing` (B1) with a proper D1 spec, which
  replaces the scaffold billing page with a real slice. The early scheduling slice does not
  change the roadmap order; billing remains the Phase B entry gate.

## Alternatives considered

- **Defer the identity-hardening backlog to a later phase** — rejected; these were security-
  and privacy-relevant (login gate, PII in email, password reset) and cheap to fix in-phase.
- **Block Phase A closure on the staging click-through** — rejected; it needs a human with a
  real inbox and gates nothing in code. Phase B *planning* (spec/plan) can proceed while the
  click-through is done in parallel; Phase B *implementation* still waits on nothing here.
