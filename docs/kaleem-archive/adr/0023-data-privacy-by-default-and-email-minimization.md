---
number: 0023
title: Data privacy by default, and personal-data minimization in emails
status: accepted
date: 2026-06-19
---

## Context

kaleem serves EU users (parents, students, teachers) and is therefore subject to the
GDPR and related EU/member-state data-protection law. The codebase had no recorded
principle to point new features at, and two concrete leaks surfaced from the backlog:

- The security-alert email sent when an address is added/promoted (`_send_email_security_alert`)
  named the *changed* email address in the body — and that alert is sent to the
  current/previous **primary**, which can be a *different* address. Plain email (no
  transport guarantees, retained on intermediate servers, often synced to third-party
  inboxes) is a poor channel for disclosing one person's identifier to the holder of
  another.
- The default allauth confirmation body echoed the user's identifier (`user_display`,
  i.e. their email) into the body.

Neither is catastrophic, but both are avoidable, and we want a standing rule rather than
case-by-case judgement.

## Decision

**1. Privacy by default is a build-time requirement.** Every feature is designed for data
minimization, purpose limitation, and storage limitation from the start — not retrofitted.
When a feature collects, stores, or transmits personal data, the spec must say what data,
why, for how long, and who can see it. "We might want it later" is not a lawful basis
(YAGNI applies to personal data with extra force).

**2. Outbound email carries the minimum necessary personal data.** Concretely:

- A notification/security email must not disclose any person's personal data (email
  addresses, names, phone numbers) to a recipient who is not that person. It states *that*
  something happened and how to react; **detail lives behind authentication** on the
  dashboard (`{FRONTEND_URL}/account`).
- Transactional emails (verification, password reset) include only what the action needs —
  the action link/token — and avoid restating account identifiers in the body.
- This is enforced by tests asserting the absence of addresses in alert/confirmation bodies
  (see `kaleem/identity/tests/test_email_branding.py`, `test_email_management.py`).

**3. Correct sender identity.** Emails are branded "Kaleem" with the real domain, never the
framework placeholder `example.com` (subject prefix pinned via `ACCOUNT_EMAIL_SUBJECT_PREFIX`,
`Site` row set by migration). A misbranded sender is itself a phishing/clarity risk.

This ADR is the principle the email-privacy-cleanup slice
(`docs/superpowers/specs/2026-06-19-email-privacy-cleanup-design.md`) implements, and the
reference future specs cite for data-handling decisions.

## Alternatives considered

- **Mask the address in alerts** (e.g. `n***@e***.com`) instead of omitting it. Rejected:
  a mask still transmits a fingerprint of the address over an insecure channel for marginal
  UX gain; omission + an authenticated link is strictly more private and just as actionable.
- **Treat privacy purely as a deploy/ops concern** (DPA, retention config) without a code
  principle. Rejected: most personal-data decisions are made in code (what a serializer
  returns, what an email says); the principle has to bind at design time.
- **A full GDPR compliance programme now** (RoPA, DPIA templates, DSAR tooling, consent
  management). Deferred: those are real but heavier obligations; this ADR fixes the
  by-design engineering rule and the immediate leaks. Operational compliance artefacts get
  their own decision/governance docs when the product is closer to public launch.

## Consequences

- New specs that touch personal data must address minimization explicitly; reviewers can
  cite this ADR to block over-collection or PII-in-email.
- Security/notification emails are less specific (no inline address); users get full detail
  by signing in. Accepted trade-off.
- Future work (not in this slice): data-retention policy, DSAR/erasure flow, a cookie/consent
  decision for the marketing site, and a Records-of-Processing doc — to be specced when
  approaching public launch. Logged in `ISSUES.md`.
